## THE BATTLE REPORT — the payoff for a game where the player never intervenes. They committed
## tactics, watched the fight, and now this screen answers the one question that matters: was
## the read right? Who won, how long it took, what each creature did and took, the single
## biggest hit, a short causal line naming the turning point, and — per monster — a DECISION LOG
## that says whether what it did was an order, its own nature, or something it reacted to.
## docs/UX_LEGIBILITY.md is the spec this section implements; read its §2/§4/§7 before touching
## the decision-log code below.
##
## ── PUBLIC ENTRY POINT ─────────────────────────────────────────────────────────────────────
## A caller that already has a finished sim result (BattleSim.run() OR SpatialSim.run() — both
## shapes are handled, see _analyze()/_decision_events_by_id() below) shows this screen like so:
##
##   var report := load("res://scenes/report.tscn").instantiate()
##   report.set_battle_result(battle_result, team_a, team_b)
##   get_tree().root.add_child(report)
##   get_tree().current_scene.queue_free()
##   get_tree().current_scene = report
##
## ⚠️ `SpatialSim.run()` IS A COROUTINE (BUILD_CONTRACT.md §2, added after stream A's navmesh-sync
## finding) — a caller feeding this screen from `SpatialSim` must `await sim.run()` BEFORE calling
## `set_battle_result`/`hand_off`. This file's own entry points take a plain, already-resolved
## `Dictionary` and never await anything themselves — the awaiting is entirely the CALLER's job
## (arena3d.gd, stream C). Passing an un-awaited `GDScriptFunctionState` here would not error; it
## would silently read as an empty result (`frames`/`winner` both blank), which is exactly the
## "looks like a data bug, not a missing keyword" failure the contract note warns about.
## `BattleSimScript` (this file's own demo fallback, below) stays synchronous — nothing here needs
## to await it.
##
## `battle_result` is exactly the sim's return value. `team_a`/`team_b` are the Array[MonsterInstance]
## that were actually fielded — passed separately because the result dict's flat `log` only ever
## carries species NAMES (never a stable id) on its hit/death/etc. entries, and this screen wants
## real per-monster identity too.
##
## set_battle_result() may be called before OR after this node enters the tree; either order
## rebuilds correctly. If it is never called (e.g. running res://scenes/report.tscn standalone
## for a screenshot), _ready() runs a small self-contained demo fight using the player's own
## Roster against a generated rival team, so the screen is never blank.
## ────────────────────────────────────────────────────────────────────────────────────────────
extends Control

const UiTheme = preload("res://scripts/ui/theme.gd")

## Height of the pinned bottom rail (see `_build_shell()` — R2).
const RAIL_H := 72

const BattleSimScript = preload("res://scripts/battle_sim.gd")
const TacticsScript = preload("res://scripts/tactics.gd")
const Sp = preload("res://scripts/spatial.gd")
## ⚠️ ONE PACE ADAPTER, NOT THREE. `career.gd` owns par, the grade and the frontier verdict;
## `scripts/ui/ending_ui.gd` is the single adapter that reads them, and this screen and
## `town_ui.gd` both call into it rather than keeping a second table that agrees until it doesn't.
const Pace = preload("res://scripts/ui/ending_ui.gd")

var _result: Dictionary = {}
var _team_a: Array = []
var _team_b: Array = []
var _sim: BattleSimScript = null
var _content: VBoxContainer


## ⚠️ CROSS-SCENE HANDOFF, because `set_battle_result` alone cannot survive one.
## `change_scene_to_file` frees the caller before the new scene exists, so there is no instance
## to call the setter on. A static slot persists process-wide with no autoload registration —
## the same pattern `tactics.gd:commit()` already uses to hand orders to the fight. The arena
## fills this in just before navigating here; `_ready` drains it exactly once so a later manual
## visit to this scene doesn't redisplay a stale fight.
static var pending: Dictionary = {}

static func hand_off(result: Dictionary, team_a: Array, team_b: Array) -> void:
	pending = {"result": result, "teamA": team_a, "teamB": team_b}


func set_battle_result(result: Dictionary, team_a: Array, team_b: Array) -> void:
	_result = result
	_team_a = team_a
	_team_b = team_b
	if _content != null:
		_rebuild()


# ══════════════════════════════════════════════════════════════════════════════════════════════
# THE READ — the two screens' single shared claim, stated on `tactics_ui.gd` and answered here
# ══════════════════════════════════════════════════════════════════════════════════════════════
#
# ⚠️ THE PROMISE AND THE VERDICT ARE ONE PIECE OF TEXT, GENERATED ONCE. `tactics_ui.gd` calls
# `build_read()` to show the player what they are committing TO; this screen calls the same
# function (or reads the stored copy) and then `grade_read()`. That is `UX_LEGIBILITY.md` §1
# rule 1 — "the vocabulary is not invented twice" — taken literally: not two tables that agree,
# ONE function. A report that grades a differently-worded claim than the one the player
# confirmed does not close the loop, however true its sentence is.
#
# ⚠️ AND THE CLAIMS ARE FALSIFIABLE ON PURPOSE (`FUN_ADDITIONS.md` §1: "three specific claims
# beat ten fuzzy ones"). Every claim below names a MONSTER or a NUMBER and states the measurement
# that decides it, so a ✗ is never an opinion. `grade_read()` reads only `frames[].shots[]` and
# `frames[].units[]` — the id-keyed stream — never the flat `log`, whose entries carry species
# NAMES and collide between same-species teammates.
#
# ⚠️ CAP: THREE. `UX_LEGIBILITY.md` §12 item 1 names "a general-purpose explain-the-whole-fight
# generator" as the single biggest scope risk in the design, and §8 caps the narrative at two or
# three hand-authored detectors. The claim ladder below is that cap applied to the read: a ranked
# candidate list, first three that apply, no more.
const READ_MAX_CLAIMS := 3

## ⚠️ ORDERS THE PLAYER CAN GIVE THAT DO NOT REACH THE FIGHT. An order named here is still shown
## and still stated as a claim — but it is NEVER GRADED, because a ✗ on an order the engine never
## received teaches the player the exact opposite of the truth, and in a game where preparation is
## the whole skill, teaching a false lesson is the fatal failure (`FUN_ADDITIONS.md` §1: "a wrong
## or vague grade is worse than no grade at all").
##
## ⚠️ `manmark` WAS THE ONE ENTRY HERE AND IT IS NOW WIRED (2026-08-09).
## `arena_3d.gd:_new_sim_tactics()` sends `target_priority: "marked"` + `ordered_id` into
## `combat_tree.gd:build()`, which seeds the blackboard from the tactics dict on its first descent.
## The claim grades itself from that moment and needs no special case. The MECHANISM stays: the
## next order that ships ahead of its sim wiring goes in here, so the report says "not simulated
## yet" instead of scoring a ✗ against an order the engine never received.
const UNWIRED_ORDERS := {}

## The measured "supported" radius — `Spatial.FLANK_MELEE_RANGE`, the same distance the engine
## itself uses to decide whether a body is fighting alone. Reused rather than invented so the
## report's "died alone" and the sim's "is flanked" mean one thing.
const SUPPORT_RADIUS := Sp.FLANK_MELEE_RANGE


## Build the player's read — up to three specific, falsifiable claims generated from the orders
## they actually gave. Pure; no scene, no sim, safe to call from either screen at any time.
##
## Returns Array[Dictionary]: {id, axis, order, claim, test, gradeable, why_ungradeable}
static func build_read(plan_a: Dictionary, orders_a: Dictionary, team_a: Array, team_b: Array) -> Array:
	var out: Array = []
	if team_a.is_empty() or team_b.is_empty():
		return out

	# ── 1. WHO DIES. The target order, resolved to the monsters the ENGINE will actually pick,
	# not to the category name — `combat_tree.gd`'s `casters` scorer is INT+WIS and its `tanks`
	# scorer is CON, so naming "their supports" and grading "their two highest INT+WIS" would be
	# two different claims wearing one sentence.
	var tp := _read_target_order(plan_a, orders_a, team_a)
	if tp != "":
		var marks: Array = _read_target_monsters(tp, plan_a, team_b)
		if not marks.is_empty():
			var names := _read_names(marks)
			# ⚠️ "%s FALLS" WAS SINGULAR AND `casters` ALWAYS RESOLVES TO TWO BODIES
			# (`_read_target_monsters` returns `mini(2, …)` for it on purpose), so every graded
			# capture of the commonest target order read "Regalor and Pyrodrake falls before their
			# front line". A claim the player confirms before the fight and is graded against has
			# to be a sentence.
			var plural: bool = marks.size() > 1
			var claim := ""
			match tp:
				"manmark": claim = "We hunt %s. It falls, and it falls first." % names
				"casters": claim = "We go through their casters — %s %s before their front line." % [names, "fall" if plural else "falls"]
				"tanks": claim = "We break %s, the biggest body they have." % names
			out.append({
				"id": "target", "axis": "targetPriority", "order": _read_order_name(TacticsScript.TARGET_PRIORITY_INFO, tp),
				"claim": claim,
				"test": "measured as the share of your damage that lands on %s, and whether %s" % [names, "they fall" if plural else "it falls"],
				"marks": marks,
				"gradeable": not UNWIRED_ORDERS.has(tp),
				"why_ungradeable": str(UNWIRED_ORDERS.get(tp, "")),
			})

	# ── 2. WHAT SHAPE. Formation is DERIVED from the deployment board, so it is a real placement
	# the player made even when they never opened a dropdown. Both buckets get a claim because
	# both are a genuine two-sided trade (`tactics.gd:aoe_coverage`/`aura_coverage`).
	var fo := str(plan_a.get("formation", "tight"))
	if fo == "loose":
		out.append({
			"id": "shape", "bucket": "loose", "axis": "formation", "order": _read_order_name(TacticsScript.FORMATION_INFO, "loose"),
			"claim": "We stay spread: nothing they throw catches more than half of us at once.",
			"test": "measured as the most of your monsters caught by any one enemy ability, in any one moment",
			"gradeable": true, "why_ungradeable": "",
		})
	else:
		out.append({
			"id": "shape", "bucket": "tight", "axis": "formation", "order": _read_order_name(TacticsScript.FORMATION_INFO, "tight"),
			"claim": "We stay together: nobody of mine dies out of reach of an ally.",
			"test": "measured as the distance to the nearest living ally at the moment each of yours falls",
			"gradeable": true, "why_ungradeable": "",
		})

	# ── 3. WHO HOLDS. The first per-monster order that describes something the fight can be held
	# to, in the order they are worth claiming. One only — a claim per monster is a statistics
	# dump wearing a narrative hat.
	var third := _read_third_claim(orders_a, team_a)
	if not third.is_empty():
		out.append(third)

	return out.slice(0, READ_MAX_CLAIMS)


## The target order actually in force for the team: the team plan first, else a per-monster
## priority only when at least half the team shares it (one monster hunting casters is that
## monster's business, not the team's read).
static func _read_target_order(plan_a: Dictionary, orders_a: Dictionary, team_a: Array) -> String:
	var team_tp := str(plan_a.get("targetPriority", ""))
	if team_tp != "":
		return team_tp
	var tally: Dictionary = {}
	for m in team_a:
		var v := str((orders_a.get(m, {}) as Dictionary).get("targetPriority", ""))
		if v != "":
			tally[v] = int(tally.get(v, 0)) + 1
	var best := ""
	var best_n := 0
	for k in tally:
		if int(tally[k]) > best_n:
			best_n = int(tally[k])
			best = str(k)
	return best if best_n * 2 >= team_a.size() else ""


## Which enemy monsters the order resolves to. Mirrors `combat_tree.gd:_mark_target`'s own
## scorers exactly — `casters` = highest INT+WIS, `tanks` = highest CON, `marked` = the mark.
static func _read_target_monsters(tp: String, plan_a: Dictionary, team_b: Array) -> Array:
	match tp:
		"manmark":
			var marked = plan_a.get("markedUnit")
			return [marked] if marked != null and team_b.has(marked) else []
		"tanks":
			return [_read_top_by(team_b, func(m): return float(m.stats.get("CON", 0.0)), 1)[0]] \
				if not team_b.is_empty() else []
		"casters":
			# Two, not one: "hunt the casters" is a plural order, and a team_b of five normally
			# fields two bodies whose INT+WIS clears the rest.
			return _read_top_by(team_b, func(m): return float(m.stats.get("INT", 0.0)) + float(m.stats.get("WIS", 0.0)), mini(2, team_b.size()))
	return []


static func _read_top_by(roster: Array, score: Callable, n: int) -> Array:
	var sorted_r: Array = roster.duplicate()
	sorted_r.sort_custom(func(a, b): return float(score.call(a)) > float(score.call(b)))
	return sorted_r.slice(0, maxi(1, n))


static func _read_third_claim(orders_a: Dictionary, team_a: Array) -> Dictionary:
	for m in team_a:
		var own: Dictionary = orders_a.get(m, {})
		if str(own.get("temperament", "balanced")) == "cautious":
			return {
				"id": "hold", "mode": "survive", "axis": "temperament", "order": _read_order_name(TacticsScript.TEMPERAMENT_INFO, "cautious"),
				"claim": "%s breaks off rather than trading down — it is standing at the end." % m.species_name,
				"test": "measured as whether %s is alive when the fight ends" % m.species_name,
				"subject": m, "gradeable": true, "why_ungradeable": "",
			}
	for m in team_a:
		var own2: Dictionary = orders_a.get(m, {})
		if str(own2.get("positionalIntent", "")) == "guard" and own2.get("guardedAlly") != null:
			var ally = own2["guardedAlly"]
			return {
				"id": "hold", "mode": "survive", "axis": "positionalIntent", "order": _read_order_name(TacticsScript.POSITIONAL_INTENT_INFO, "guard"),
				"claim": "%s stays on %s — %s is standing at the end." % [m.species_name, ally.species_name, ally.species_name],
				"test": "measured as whether %s is alive when the fight ends" % ally.species_name,
				"subject": ally, "gradeable": true, "why_ungradeable": "",
			}
	for m in team_a:
		var own3: Dictionary = orders_a.get(m, {})
		var pi := str(own3.get("positionalIntent", ""))
		if pi == "dive" or pi == "wings":
			return {
				"id": "hold", "mode": "reach_back", "axis": "positionalIntent", "order": _read_order_name(TacticsScript.POSITIONAL_INTENT_INFO, pi),
				"claim": "%s gets onto their back line." % m.species_name,
				# ⚠️ THE TEST IS "DID IT REACH THEM", NOT "DID IT CROSS THE HALFWAY LINE", AND THE
				# FIRST VERSION OF THIS CLAIM GOT IT WRONG. Measured over 14 real fights, a diving
				# monster NEVER crossed the centre line in any of them — not because the dive
				# failed but because the two lines meet wherever they meet, and a side under
				# pressure meets them in its OWN half. A test that a correct dive cannot pass is a
				# grader teaching a false lesson, which is the one thing this screen must not do.
				"test": "measured as whether %s lands a blow on one of the two monsters they deploy furthest back" % m.species_name,
				"subject": m, "gradeable": true, "why_ungradeable": "",
			}
	return {}


static func _read_order_name(info_list: Array, id) -> String:
	var info: Dictionary = info_by_id_static(info_list, id)
	if info.is_empty():
		return str(id)
	return "%s %s" % [info.get("icon", ""), info.get("name", "?")]


static func info_by_id_static(info_list: Array, id) -> Dictionary:
	for entry in info_list:
		if entry["id"] == id:
			return entry
	return {}


static func _read_names(monsters: Array) -> String:
	var names: Array = []
	for m in monsters:
		names.append(str(m.species_name))
	if names.size() <= 1:
		return names[0] if names.size() == 1 else "?"
	return "%s and %s" % [", ".join(names.slice(0, names.size() - 1)), names[names.size() - 1]]


# ── GRADING ───────────────────────────────────────────────────────────────────────────────────

## Answer each claim from the fight that happened. Returns a NEW array of claim dicts with
## `verdict` ("held" / "partly" / "broke" / "ungraded") and `evidence` (the number that decided
## it) added. Never mutates the input, so the pre-fight copy the player confirmed stays intact.
##
## ⚠️ FRAME STREAM REQUIRED. Every measurement below is id-keyed off `frames[].shots[]` /
## `frames[].units[]`. The legacy `battle_sim.gd` path has no frames and its flat `log` carries
## species names only; rather than grade on a source that collides between same-species
## teammates, a frameless result reports every claim UNGRADED and says why. An honest blank beats
## a confident wrong tick.
static func grade_read(claims: Array, result: Dictionary, team_a: Array, team_b: Array) -> Array:
	var out: Array = []
	var frames: Array = result.get("frames", [])
	var n_a: int = team_a.size()
	var roster: Array = team_a + team_b
	var idx: Dictionary = {}
	for i in range(roster.size()):
		idx[roster[i]] = i

	if frames.is_empty():
		for c in claims:
			var u: Dictionary = (c as Dictionary).duplicate()
			u["verdict"] = "ungraded"
			u["evidence"] = "this fight produced no frame stream, so there is nothing to measure it against"
			out.append(u)
		return out

	var dmg := _read_damage(frames, roster.size(), n_a)
	var deaths := _read_deaths(frames)

	for c in claims:
		var g: Dictionary = (c as Dictionary).duplicate()
		if not bool(g.get("gradeable", true)):
			g["verdict"] = "ungraded"
			g["evidence"] = str(g.get("why_ungradeable", "not measurable in this build"))
			out.append(g)
			continue
		match str(g.get("id", "")):
			"target": _grade_target(g, dmg, deaths, idx, n_a)
			"shape": _grade_shape(g, frames, deaths, n_a)
			"hold": _grade_hold(g, frames, deaths, idx, n_a)
			_:
				g["verdict"] = "ungraded"
				g["evidence"] = "no measurement is defined for this claim"
		out.append(g)
	return out


## Per-pair damage totals plus each side's own total, straight off the id-keyed shot records.
static func _read_damage(frames: Array, n: int, n_a: int) -> Dictionary:
	var to_total: Dictionary = {}       # target id -> damage taken from the OTHER side
	var a_total: float = 0.0
	for f in frames:
		for s in (f.get("shots", []) as Array):
			var from_i: int = int((s as Dictionary).get("fromId", -1))
			var to_i: int = int((s as Dictionary).get("toId", -1))
			var d: float = float((s as Dictionary).get("dmg", 0))
			if from_i < 0 or to_i < 0 or from_i >= n or to_i >= n or d <= 0.0:
				continue
			if (from_i < n_a) == (to_i < n_a):
				continue   # friendly fire / self-damage is not "damage into them"
			to_total[to_i] = float(to_total.get(to_i, 0.0)) + d
			if from_i < n_a:
				a_total += d
	return {"to_total": to_total, "a_total": a_total}


## id -> {"t", "frame_index"} for the first frame in which a living unit reads dead.
static func _read_deaths(frames: Array) -> Dictionary:
	var alive_now: Dictionary = {}
	var out: Dictionary = {}
	for fi in range(frames.size()):
		var f: Dictionary = frames[fi]
		for u in (f.get("units", []) as Array):
			var uid: int = int((u as Dictionary).get("id", -1))
			if uid < 0:
				continue
			var is_alive: bool = bool((u as Dictionary).get("alive", true))
			if bool(alive_now.get(uid, true)) and not is_alive and not out.has(uid):
				out[uid] = {"t": float(f.get("t", 0.0)), "frame_index": fi}
			alive_now[uid] = is_alive
	return out


## THE TARGET CLAIM. Two questions, both answered with a number: did the damage CONCENTRATE on
## the named body, and did the body FALL. Concentration is judged against the target's own fair
## share (one body out of the enemy side), because "40% of your damage" means something very
## different against a 1v1 and a 5v5.
static func _grade_target(g: Dictionary, dmg: Dictionary, deaths: Dictionary, idx: Dictionary, n_a: int) -> void:
	var marks: Array = g.get("marks", [])
	var to_total: Dictionary = dmg["to_total"]
	var a_total: float = float(dmg["a_total"])
	var on_marks: float = 0.0
	var all_dead := true
	var first_enemy_death_id := -1
	var first_t := INF
	for uid in deaths:
		if int(uid) >= n_a and float((deaths[uid] as Dictionary)["t"]) < first_t:
			first_t = float((deaths[uid] as Dictionary)["t"])
			first_enemy_death_id = int(uid)
	var mark_ids: Array = []
	var fell_names: Array = []
	var stood_names: Array = []
	for m in marks:
		var uid2: int = int(idx.get(m, -1))
		if uid2 < 0:
			continue
		mark_ids.append(uid2)
		on_marks += float(to_total.get(uid2, 0.0))
		if not deaths.has(uid2):
			all_dead = false
			stood_names.append(str(m.species_name))
		else:
			fell_names.append(str(m.species_name))
	if mark_ids.is_empty() or a_total <= 0.0:
		g["verdict"] = "ungraded"
		g["evidence"] = "your team landed no damage at all, so there is no share to measure"
		return

	var share: float = on_marks / a_total
	var enemy_n: int = maxi(1, (idx.size() - n_a))
	var fair: float = float(mark_ids.size()) / float(enemy_n)
	var concentrated: bool = share >= fair * 1.4
	var fell_first: bool = first_enemy_death_id in mark_ids

	# ⚠️ "IT" WAS A LIE THE MOMENT THE ORDER NAMED TWO BODIES, AND `casters` ALWAYS DOES.
	# `_read_target_monsters` returns TWO for "hunt the casters", so a fight where one caster fell
	# and the other lived printed "…went into Titanus and Bristleye; it was still standing at the
	# end" — the screen denying a kill the player actually got, on the one claim it exists to
	# adjudicate. Seen in the round-19 graded capture. Each mark is now accounted for by name.
	# ⚠️ WHEN THE MARKS ARE THE WHOLE ENEMY TEAM THE CONCENTRATION TEST CARRIES NO INFORMATION, AND
	# PRINTING IT ANYWAY IS THE SCREEN LYING BY ARITHMETIC. `_read_target_monsters` returns two
	# bodies for "hunt the casters"; at the small team sizes the ladder OPENS on (Wood/Copper/Tin/
	# Bronze field 1–3) those two can be the entire other side, and then `share` and `fair` are both
	# 100% by construction — `concentrated` (share >= fair * 1.4) cannot be true no matter how the
	# fight went. The round-19 graded capture of `12_report` printed "100% of your damage went into
	# Capling and Regalor (an even spread would be 100%)" and then WHAT TO CHANGE told the player to
	# change that order on the strength of it.
	#
	# The FOCUS half of the claim is genuinely unaskable here, so the screen says so and grades on
	# the half that is still real: did they fall. Which is what "fall before their front line"
	# meant anyway — there is no front line to fall before when the marks ARE the line.
	var whole_team: bool = mark_ids.size() >= enemy_n
	var bits := ""
	if whole_team:
		bits = "they were the whole other side, so there was no spread to measure — graded on whether they fell"
	else:
		bits = "%.0f%% of your damage went into %s (an even spread would be %.0f%%)" % [share * 100.0, _read_names(marks), fair * 100.0]
	if all_dead:
		if mark_ids.size() == 1:
			bits += "; it fell%s" % (" first" if fell_first else " — but not first")
		else:
			bits += "; both fell%s" % (", one of them first" if fell_first else " — but neither first")
	elif fell_names.is_empty():
		bits += "; %s still standing at the end" % ("it was" if mark_ids.size() == 1 else "they were both")
	else:
		bits += "; %s fell%s, %s still standing at the end" % [
			", ".join(fell_names), (" first" if fell_first else ""), ", ".join(stood_names)]
	g["evidence"] = bits
	# With no spread to measure, `concentrated` is not merely false — it is meaningless, so it must
	# not be allowed to drag a fight where every mark died down from `held` to `partly`.
	var conc: bool = concentrated and not whole_team
	if all_dead and (conc or fell_first or whole_team):
		g["verdict"] = "held"
	elif all_dead or conc:
		g["verdict"] = "partly"
	else:
		g["verdict"] = "broke"


## THE SHAPE CLAIM.
## LOOSE — the widest single enemy ability, measured as the most of YOUR monsters caught by one
##   (attacker, ability) pair inside one frame. That is the thing "spread out" is bought to stop.
## TIGHT — the isolation-at-death check `UX_LEGIBILITY.md` §8 Extension 1 specifies, bounded to
##   the deaths that happened rather than run over every event (§12 item 3).
static func _grade_shape(g: Dictionary, frames: Array, deaths: Dictionary, n_a: int) -> void:
	# ⚠️ Branch on the machine key, never on the DISPLAY string — the `*_INFO` copy is the one
	# thing in this file that is expected to be reworded, and a grader that reads the wording
	# silently changes what it measures the first time someone edits a label.
	if str(g.get("bucket", "tight")) == "loose":
		var widest := 0
		var widest_move := ""
		for f in frames:
			var groups: Dictionary = {}
			for s in (f.get("shots", []) as Array):
				var from_i: int = int((s as Dictionary).get("fromId", -1))
				var to_i: int = int((s as Dictionary).get("toId", -1))
				if from_i < n_a or to_i < 0 or to_i >= n_a:
					continue   # only THEIR abilities landing on YOUR side
				var key := "%d|%s" % [from_i, str((s as Dictionary).get("move", ""))]
				if not groups.has(key):
					groups[key] = {}
				(groups[key] as Dictionary)[to_i] = true
			for k in groups:
				var n: int = (groups[k] as Dictionary).size()
				if n > widest:
					widest = n
					widest_move = str(k).split("|")[1]
		var half: int = int(floor(float(n_a) / 2.0))
		g["evidence"] = "their widest single blow caught %d of your %d%s" % [
			widest, n_a, (" (%s)" % widest_move) if widest_move != "" and widest_move != "Attack" else ""]
		if widest <= half:
			g["verdict"] = "held"
		elif widest <= half + 1:
			g["verdict"] = "partly"
		else:
			g["verdict"] = "broke"
		return

	# TIGHT — did anyone of ours die alone?
	var alone: Array = []
	var worst := 0.0
	# ⚠️ "NEAREST ALLY 0 UNITS AWAY" WAS PRINTED FOR A BODY WITH NO LIVING ALLY AT ALL, and the
	# round-19 sweep hit it in three fights of six. `nearest` is INF when every teammate is already
	# dead; the old line folded that into `worst` as 0.0 and rendered "died alone — nearest ally 0
	# units away, support range is 14" — simultaneously claiming isolation and contact. Counted
	# separately, and said in words, because "the last one standing" and "cut off from a live line"
	# are different lessons and only one of them is a formation problem.
	var last_alive := 0
	for uid in deaths:
		if int(uid) >= n_a:
			continue
		var fi: int = int((deaths[uid] as Dictionary)["frame_index"])
		var f: Dictionary = frames[fi]
		var me_pos := Vector2.ZERO
		var found := false
		var allies: Array = []
		for u in (f.get("units", []) as Array):
			var i2: int = int((u as Dictionary).get("id", -1))
			if i2 == int(uid):
				me_pos = (u as Dictionary).get("pos", Vector2.ZERO)
				found = true
			elif i2 >= 0 and i2 < n_a and bool((u as Dictionary).get("alive", false)):
				allies.append((u as Dictionary).get("pos", Vector2.ZERO))
		if not found:
			continue
		var nearest := INF
		for p in allies:
			nearest = minf(nearest, me_pos.distance_to(p))
		if nearest == INF:
			last_alive += 1
		elif nearest > SUPPORT_RADIUS:
			alone.append(uid)
			worst = maxf(worst, nearest)
	var fallen: int = 0
	for uid3 in deaths:
		if int(uid3) < n_a:
			fallen += 1
	# The last body standing has no line left to hold, so it cannot have broken one. Stated, not
	# silently dropped — it is why a count of losses and a count of isolations need not agree.
	var tail := ""
	if last_alive == 1:
		tail = "; the last of yours had no line left to hold"
	elif last_alive > 1:
		tail = "; the last %d of yours had no line left to hold" % last_alive
	var judged_n: int = fallen - last_alive
	if fallen == 0:
		g["verdict"] = "held"
		g["evidence"] = "nobody of yours fell at all"
	elif alone.is_empty():
		g["verdict"] = "held"
		g["evidence"] = ("%d of your %d losses fell with an ally inside %.0f units%s" % [
			judged_n, fallen, SUPPORT_RADIUS, tail]) if judged_n > 0 \
			else "every one of yours that fell was the last of yours alive — there was no line left to hold"
	else:
		g["verdict"] = "broke" if alone.size() * 2 > maxi(judged_n, 1) else "partly"
		g["evidence"] = "%d of your %d losses died cut off — nearest living ally %.0f units away, support range is %.0f%s" % [
			alone.size(), fallen, worst, SUPPORT_RADIUS, tail]


## The enemy ids the OPENING frame puts furthest along the deploy axis — "their back line" as the
## deployment board drew it. Returns {id: label}; at most two.
static func _read_back_line(frames: Array, n_a: int) -> Dictionary:
	if frames.is_empty() or n_a <= 0:
		return {}
	var rows: Array = []
	for u in (frames[0].get("units", []) as Array):
		var i: int = int((u as Dictionary).get("id", -1))
		if i >= n_a:
			rows.append({"id": i, "x": float(((u as Dictionary).get("pos", Vector2.ZERO) as Vector2).x)})
	if rows.is_empty():
		return {}
	rows.sort_custom(func(a, b): return float(a["x"]) > float(b["x"]))
	var out: Dictionary = {}
	for r in rows.slice(0, mini(2, rows.size())):
		out[int((r as Dictionary)["id"])] = "slot %d" % (int((r as Dictionary)["id"]) - n_a + 1)
	return out


static func _grade_hold(g: Dictionary, frames: Array, deaths: Dictionary, idx: Dictionary, n_a: int) -> void:
	var subject = g.get("subject")
	var uid: int = int(idx.get(subject, -1))
	if uid < 0:
		g["verdict"] = "ungraded"
		g["evidence"] = "that monster was not in this fight"
		return
	if str(g.get("mode", "survive")) == "reach_back":
		# The dive/wings claim — did it reach the bodies they parked at the back? "Their back
		# line" is read off the OPENING FRAME's deploy positions (the enemy two furthest along
		# the deploy axis), which is exactly what the player saw on the deployment board.
		var back: Dictionary = _read_back_line(frames, n_a)
		if back.is_empty():
			g["verdict"] = "ungraded"
			g["evidence"] = "the opening frame carries no deploy positions to read a back line from"
			return
		var landed := 0
		var names: Array = []
		for f in frames:
			for sh in (f.get("shots", []) as Array):
				var s2: Dictionary = sh
				if int(s2.get("fromId", -1)) == uid and back.has(int(s2.get("toId", -1))) and float(s2.get("dmg", 0)) > 0.0:
					landed += 1
		for bid in back:
			names.append(str(back[bid]))
		g["verdict"] = "held" if landed > 0 else "broke"
		g["evidence"] = ("it landed %d blows on their back line (%s)" % [landed, ", ".join(names)]) if landed > 0 			else "it never landed a blow on their back line (%s)" % ", ".join(names)
		return

	# Survival claims (cautious, guard).
	if deaths.has(uid):
		g["verdict"] = "broke"
		g["evidence"] = "it fell at %.1fs" % float((deaths[uid] as Dictionary)["t"])
	else:
		g["verdict"] = "held"
		g["evidence"] = "it was standing when the fight ended"


# ── THE VERDICT ───────────────────────────────────────────────────────────────────────────────

## The sentence the whole game is built to deliver. Four cases, and the one that matters most is
## RIGHT-AND-LOST: a player who countered correctly and still lost has learned the single most
## instructive thing the game can teach them, and it is also the result most likely to be misread
## as unfairness. It gets named explicitly, with the reason.
static func read_verdict(graded: Array, winner: String, team_a: Array, team_b: Array) -> Dictionary:
	var held := 0
	var partly := 0
	var broke := 0
	for c in graded:
		match str((c as Dictionary).get("verdict", "")):
			"held": held += 1
			"partly": partly += 1
			"broke": broke += 1
	var judged: int = held + partly + broke
	var won: bool = winner == "A"
	# ⚠️ NOT-A-WIN IS NOT THE SAME AS A LOSS, AND THE HEADLINE ASSERTED THE WRONG ONE.
	# `sim.gd:414` writes THREE outcomes — "A", "B" and "draw" — plus a fourth, the empty string,
	# when the fight hits `MAX_TICKS`. `_result_line()` on this very screen already renders "DRAW"
	# as its own banner at 34px. Every non-win branch below then hard-coded the word LOST underneath
	# it: a mutual wipe printed "▲ DRAW" and, two lines down, "YOUR READ WAS RIGHT. YOU LOST
	# ANYWAY." That is the screen contradicting itself about the single fact the player already
	# knows, on the sentence the observe half exists to deliver — the same class of defect as the
	# 400-vs-540 ceiling and the "an even spread would be 100%" evidence line, and the reason those
	# two are quoted at the top of every brief.
	#
	# The GRADE is unchanged: a draw is still not a win, so it still cannot reach the "and it won
	# it" copy. Only the word for what happened changes.
	var drawn: bool = not won and winner != "B"
	var lost_word: String = "DID NOT WIN IT" if drawn else "LOST"

	# ⚠️ TWO DIFFERENT ZEROES, AND THE FIRST DRAFT CONFLATED THEM. "You claimed nothing" and "your
	# claims could not be measured" look identical from here and are opposite messages: one is the
	# player's doing, the other is ours. `_probe_read.gd` reaches the second every time it walks a
	# frameless (legacy `battle_sim.gd`) result, so the wrong copy would have shipped as the common
	# case, telling a player who gave four orders that they gave none.
	if judged == 0:
		if graded.is_empty():
			return {"headline": "NO READ TO GRADE", "tone": "flat",
				"sub": "You committed no claim this fight. Set a target priority, a shape or a temperament on The Read screen and this line becomes a verdict."}
		return {"headline": "THE READ COULD NOT BE GRADED", "tone": "flat",
			"sub": "You committed %d claims and this fight cannot answer any of them — see the reason under each one. That is our gap, not yours." % graded.size()}

	var score := "%d of %d held" % [held, judged]
	if held == judged:
		if won:
			return {"headline": "YOUR READ WAS RIGHT — AND IT WON IT.", "tone": "good",
				"sub": "%s. This is the fight to remember: you predicted it and it happened." % score}
		return {"headline": "YOUR READ WAS RIGHT. YOU %s ANYWAY." % lost_word, "tone": "warn",
			"sub": "%s, and it still was not enough. %s" % [score, _strength_line(team_a, team_b)]}
	if held + partly == judged and held > 0:
		return {"headline": "MOST OF THE READ HELD." if won else "THE READ HALF HELD.", "tone": "mixed",
			"sub": "%s. Look at the claim that only partly landed — that is the one to change." % score}
	if held == 0:
		if won:
			return {"headline": "YOU WON WITHOUT THE READ.", "tone": "mixed",
				"sub": "%s. You took this on raw strength, not on the plan — the same orders against a team your own size will not hold." % score}
		# ⚠️ "EVERY CLAIM YOU COMMITTED TO FAILED" WAS FALSE WHENEVER ANY CLAIM GRADED *PARTLY*,
		# AND THE ROUND-19 SWEEP HIT IT IN FIVE FIGHTS OF SIX. This branch tests only `held == 0`
		# and then asserts total failure — so a fight where two of three claims landed most of the
		# way (74% of damage onto the two marked casters against a fair share of 40%, one of them
		# falling first) printed "Every claim you committed to failed". That is the screen lying
		# about the thing it describes, on the single sentence the observe half exists to deliver.
		#
		# ⚠️ AND THE ADVICE WAS WORSE THAN THE COUNT. "the orders are the thing to change, not the
		# roster" was hard-coded into the loss case, while the same sweep had the rival roster
		# carrying between 19% and 94% MORE trained stat. Telling an outclassed player to rewrite
		# orders that were substantially right is the "wrong or vague grade is worse than no grade"
		# failure `FUN_ADDITIONS.md` §1 names, and it is exactly how a teachable loss becomes a
		# grievance. The roster comparison now decides which half of the game gets named.
		if partly > 0:
			return {"headline": "THE READ ALMOST HELD, AND ALMOST WAS NOT ENOUGH.", "tone": "bad",
				"sub": "%s — but %d of %d landed most of the way. Read the evidence under each: you are closer than the score looks. %s" % [
					score, partly, judged, _strength_line(team_a, team_b, false)]}
		var broke_head: String = "THE READ BROKE, AND YOU COULD NOT CLOSE IT." if drawn \
			else "THE READ BROKE, AND IT COST YOU."
		return {"headline": broke_head, "tone": "bad",
			"sub": "%s. Every claim you committed to failed. %s" % [score, _strength_line(team_a, team_b, false)]}
	return {"headline": "PART OF THE READ HELD." if won else "PART OF THE READ HELD, AND IT WAS NOT ENOUGH.",
		"tone": "mixed", "sub": "%s." % score}


## ⚠️ ROSTER STRENGTH, NOT A POWER RATING. The flat sum of the six trained stats over a side —
## exactly the thing the ladder's `field_fill` dial moves and the one number a player can act on
## by training. Quoted only in the right-and-lost case, where "was it me or was it them" is the
## actual question and an unanswered one turns a teachable loss into a grievance.
## ⚠️ `read_held` EXISTS BECAUSE THIS LINE USED TO BE QUOTED IN ONE CONTEXT AND IS NOW QUOTED IN
## THREE. Its old wording ("so the orders held and something else lost it") was written for the
## right-and-lost case and is simply false when the read did NOT hold — the same sentence has to
## stop asserting the grade it is being appended to.
static func _strength_line(team_a: Array, team_b: Array, read_held: bool = true) -> String:
	var pa := roster_power(team_a)
	var pb := roster_power(team_b)
	if pa <= 0.0:
		return ""
	var pct: float = (pb / pa - 1.0) * 100.0
	if pct >= 8.0:
		return "Their roster carries %.0f%% more trained stat than yours — this was a stable problem before it was a tactics problem. Go and train." % pct
	if pct <= -8.0:
		if read_held:
			return "And you were the STRONGER side by %.0f%%, so the orders held and something else lost it — read the turning point below." % absf(pct)
		return "And you were the STRONGER side by %.0f%% on trained stat, so this one is on the orders — read the turning point below." % absf(pct)
	return "The two rosters are within %.0f%% of each other, so the bodies were not the difference. Read the turning point below." % absf(pct)


## ⚠️ PUBLIC BECAUSE `tactics_ui.gd` QUOTES THE SAME NUMBER BEFORE THE FIGHT. The report tells a
## player who read correctly and lost that "their roster carries N% more trained stat than yours";
## the scouting panel now tells them the same N% BEFORE they commit, so the two bookends of a fight
## use one measurement rather than two that agree until they don't (`UX_LEGIBILITY.md` §1 rule 1).
static func roster_power(team: Array) -> float:
	var total := 0.0
	for m in team:
		for k in ["STR", "DEX", "CON", "WIS", "INT", "CHA"]:
			total += float(m.stats.get(k, 0.0))
	return total


## The one archetype whose published counter is an ORDER rather than a roster shape — so it is
## the one the report can honestly tick. Everything else in `GAMEPLANS.counter` is advice about
## which monsters to BUILD, which no single fight can grade.
static func counter_line(gameplan_id: String, plan_a: Dictionary) -> String:
	var gp: Dictionary = TacticsScript.GAMEPLANS.get(gameplan_id, {})
	if gp.is_empty():
		return ""
	var name: String = str(gp.get("name", "?"))
	if gameplan_id == "zone":
		var loose: bool = str(plan_a.get("formation", "tight")) == "loose"
		return "They fought as %s. The book counter is an order — stand LOOSE — and you stood %s. %s" % [
			name, "LOOSE" if loose else "TIGHT", "✓" if loose else "✗"]
	return "They fought as %s. Its counter is a ROSTER answer, not an order, so there is nothing here for one fight to grade — see the scouting line before the next one." % name


func _ready() -> void:
	_build_shell()
	if _result.is_empty() and not pending.is_empty():
		_result = pending.get("result", {})
		_team_a = pending.get("teamA", [])
		_team_b = pending.get("teamB", [])
		pending = {}  # drain — a real fight is shown once, not re-shown on a later visit
	if _result.is_empty():
		_run_demo_battle()
	_rebuild()


func _build_shell() -> void:
	# ⚠️ THE HOUSE THEME, NOT A SIXTH GREY. Round 19: this screen carried 55 off-scale labels and
	# 55 off-token colours — more than any other screen in the project — against a theme that
	# already publishes the scale and the palette (`UI_LAYOUT_RULES` R7). Every size below now
	# comes from `UiTheme.SIZE_*` and every text colour from `UiTheme.TOKEN_TEXT_COLOURS`.
	self.theme = UiTheme.base_theme()

	var bg := ColorRect.new()
	bg.color = UiTheme.SURFACE
	bg.anchor_right = 1; bg.anchor_bottom = 1
	add_child(bg)

	# ⚠️ THE SCROLL STOPS SHORT OF THE BOTTOM SO THE RAIL CAN LIVE THERE. `_probe_house.gd`
	# measures R2 — the primary action reachable WITHOUT scrolling — and this screen was the only
	# one in the project failing it: its single exit sat at the foot of an 1,179px report, so
	# "leave the report" required scrolling to the end of the analysis first. That is the wrong
	# way round for a screen the player reaches after a fight they could not influence: reading
	# the breakdown must be optional, and leaving must not be.
	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1; scroll.anchor_bottom = 1
	scroll.offset_bottom = -RAIL_H
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, UiTheme.SPACE_XL)
	scroll.add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(_content)

	# The pinned rail, a SIBLING of the scroll — built once in the shell, so `_rebuild()` clearing
	# `_content` can never take the exit with it.
	var rail := UiTheme.commit_bar("The breakdown below is optional reading.", "Back to the Stable")
	rail.anchor_left = 0; rail.anchor_top = 1
	rail.anchor_right = 1; rail.anchor_bottom = 1
	rail.offset_top = -RAIL_H
	add_child(rail)
	var rail_btn := UiTheme.commit_bar_button(rail)
	if rail_btn != null:
		rail_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/stable.tscn"))


## Self-contained default so this scene is screenshot-able standalone — same pattern battle_ui.gd
## uses for its own demo team_a/team_b, so a fresh report and a fresh battle look consistent.
## Also synthesizes a plausible standing-orders record into `Tactics.committed`, so the Orders
## Summary block (§2/§11 of UX_LEGIBILITY.md) has real ORDER-vs-NATURE content to show even when
## this scene is opened with no tactics screen having run first — normally that dict is populated
## by tactics_ui.gd before the fight.
func _run_demo_battle() -> void:
	## One predicate for "who fights" (roster.gd:fielded_team). Demo path, same reasoning as
	## battle_ui.gd: no fifth copy of `not m.retired`.
	var team_a: Array = Roster.fielded_team(5)
	if team_a.is_empty():
		team_a = Roster.monsters.slice(0, mini(5, Roster.monsters.size()))
	var team_b: Array = Roster.make_rival_team(team_a.size(), 0.3)

	var plan_a := {"targetPriority": "casters"}
	var orders_a := {}
	for i in range(team_a.size()):
		orders_a[team_a[i]] = {"temperament": "aggressive"} if i == 0 else {"temperament": "balanced"}
	var gp_id := TacticsScript.gameplan_for(team_b.map(func(m): return m.species_name))
	var plan_b := TacticsScript.team_plan_for_gameplan(gp_id)
	var orders_b := TacticsScript.orders_for_gameplan(gp_id, team_b)
	TacticsScript.commit(plan_a, plan_b, orders_a, orders_b)
	# Same extra key `tactics_ui.gd` writes at commit time, so the standalone screen exercises the
	# real Read path rather than a second one. ⚠️ The demo runs `battle_sim.gd`, which emits no
	# frame stream, so every claim here reports NOT GRADED — that is the honest output for a
	# frameless result and it is exactly what a real frameless fight would show.
	TacticsScript.committed["read"] = {
		"claims": build_read(plan_a, orders_a, team_a, team_b), "gameplan": gp_id,
	}

	var merged_orders: Dictionary = {}
	for k in orders_a:
		merged_orders[k] = orders_a[k]
	for k in orders_b:
		merged_orders[k] = orders_b[k]

	_sim = BattleSimScript.new(team_a, team_b, 20260804, plan_a, plan_b, merged_orders)
	_team_a = team_a
	_team_b = team_b
	_result = _sim.run()


func _rebuild() -> void:
	for c in _content.get_children():
		c.queue_free()
	if _result.is_empty():
		return

	var frames: Array = _result.get("frames", [])
	var built := _build_roster_and_ids(_team_a, _team_b)
	var roster: Array = built["roster"]
	var id_of: Dictionary = built["id_of"]
	var applies: bool = _tactics_applies(id_of)

	var analysis := _analyze(_result.get("log", []), _team_a, _team_b, frames, id_of, roster)
	var dec := _decision_events_by_id(_result.get("log", []), frames, _result, roster, _team_a.size())

	# ⚠️ THE ORDER OF THIS SCREEN IS THE ARGUMENT IT MAKES: result, then whether the read was right,
	# then WHY, then the detail. The turning point stays up here with the verdict because
	# `read_verdict()` points at it by name in the right-and-lost case, and a sentence that refers
	# to something off-screen is not a sentence.
	#
	# ⚠️ THIS ORDER WAS THE OTHER WAY ROUND AND THE REASONING FOR IT WAS HALF RIGHT. The previous
	# version led with the read verdict at 34px and demoted VICTORY/DEFEAT to a 24px subhead,
	# arguing — correctly — that the vision's payoff is "my read was right", not "who won". What
	# that argument missed is what happens when the grader has nothing to say: the first capture of
	# this screen has **`THE READ COULD NOT BE GRADED` as the largest type on a fight the player
	# WON**. A screen whose loudest sentence is an apology about its own machinery has led with the
	# machinery, not with the payoff.
	#
	# So they are now ONE block and the ranking is by what is always true. The result is always
	# knowable; the grade sometimes is not. Result largest, read verdict immediately beneath it at
	# heading size and in the tone colour — still the second thing on the screen, still above every
	# number, and it degrades to a quiet line instead of a shout when it cannot answer.
	# See `_verdict_block()`.
	var graded := _graded_claims(applies)
	_content.add_child(_verdict_block(applies, graded))

	var narrative := _narrative(analysis, dec, id_of, roster)
	if narrative != "":
		_content.add_child(_line(narrative, UiTheme.SIZE_BODY, UiTheme.TEXT_PRIMARY))

	var big_hit: Dictionary = analysis.get("biggest_hit", {})
	if int(big_hit.get("dmg", -1)) >= 0:
		var crit_tag := " (CRIT)" if big_hit.get("crit", false) else ""
		_content.add_child(_line(
			"Biggest hit: %s's %s on %s for %d%s" % [big_hit["attacker"], big_hit["move"], big_hit["target"], int(big_hit["dmg"]), crit_tag],
			UiTheme.SIZE_BODY, UiTheme.CAUTION))

	_content.add_child(HSeparator.new())
	var teams := _teams_row(analysis, id_of, dec, applies)
	teams.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(teams)

	# ⚠️ THE VOID GETS THE ONE THING THE SCREEN OWED AND NEVER SAID. Round 18 measured ~200px of
	# dead black under the two team columns on a small roster; round 19's answer is NOT another
	# table (a damage table is what you build when you cannot say what happened —
	# `META_UI_DIRECTION.md` §1) but the sentence the whole loop is for: what to change before the
	# next fight, and whether it is the ORDERS or the STABLE. Both halves are already computed —
	# the graded claims and `roster_power()` — and both were previously reachable only in the one
	# right-and-lost branch of `read_verdict()`. See `_next_step_block()`.
	_content.add_child(_next_step_block(graded))
	# ⚠️ NO EXIT BUTTON HERE ANY MORE — it is pinned in `_build_shell()`'s rail, outside the scroll.
	# Leaving a duplicate at the foot of the content would be two controls doing one job, and the
	# scrolled one is the one the player cannot see.


## THE VERDICT BLOCK — what happened, and whether the plan was the reason, in that order.
##
## Reads the claims the player actually confirmed (stored on `Tactics.committed.read` at commit
## time, so the words graded here are byte-identical to the words they said yes to), grades them
## against this fight, and states both bookends as one piece.
## ⚠️ GRADED ONCE PER REBUILD, READ TWICE. The verdict block and the closing "what to change"
## block must never disagree, and the only way to guarantee that is for there to be ONE grading.
## Two callers each running `grade_read()` would agree today and drift the first time either
## screen region grew a special case — the exact shape of the market-vs-stable ceiling
## contradiction round 18 found (400 on one screen, 540 on another, both "true").
func _graded_claims(tactics_apply: bool) -> Array:
	var committed: Dictionary = TacticsScript.committed if tactics_apply else {}
	var stored: Dictionary = committed.get("read", {})
	var claims: Array = stored.get("claims", [])
	if claims.is_empty() and tactics_apply:
		# A committed plan with no stored read (an older save, or a screen that committed before
		# this block existed) — rebuild the same claims from the same orders rather than showing
		# nothing. Same function, so the wording is identical either way.
		claims = build_read(committed.get("planA", {}), committed.get("ordersA", {}), _team_a, _team_b)
	return grade_read(claims, _result, _team_a, _team_b)


## ⚠️ ONE `FontVariation` FOR TRACKING, AND TRACKING IS NOT A SIZE. The payoff line of the whole
## design has to LAND, and the two ways to make a line land are size and spacing. Size is spent —
## `SIZE_DISPLAY` already belongs to VICTORY/DEFEAT one line above, and a second display-register
## label would put the round's off-scale count up for a screen that is already on the scale. So
## the verdict gets the other half: letter-spacing, which reads as deliberate at a distance and
## costs nothing the probe measures. It comes from `UiTheme.display_font(px)` — see `title_ui.gd`.


func _verdict_block(tactics_apply: bool, graded: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTheme.SPACE_XS)

	# ── 1. WHAT HAPPENED. The one fact that is always knowable. ──────────────────────────────
	var winner: String = _result.get("winner", "draw")
	var result_text := "DRAW"
	# ⚠️ WON/LOST IS A STATUS, NOT A LIVERY. The result line used to be painted in the TEAM colour,
	# which meant the single loudest word on the screen changed hue with whichever of `art.gd`'s
	# eight liveries the player happened to be wearing — a rival in green could print DEFEAT in
	# green. The badge glyph still carries team identity (never colour alone); the ink now carries
	# the RESULT, from the theme's own threat vocabulary.
	var result_col := UiTheme.TEXT_SECONDARY
	if winner == "A":
		result_text = "%s VICTORY" % (Art.team_identity(0))["badge"]
		result_col = UiTheme.SAFE
	elif winner == "B":
		result_text = "%s DEFEAT" % (Art.team_identity(1))["badge"]
		result_col = UiTheme.DANGER

	## ⚠️ THE PAYOFF IS A PLATE NOW, NOT FOUR LOOSE LINES AT THE TOP OF A STACK. Every element of
	## this screen used to be a sibling in one column at one density: the result, the verdict, the
	## turning point, the biggest hit, the team columns and the closing advice, in the same rhythm,
	## on the same ground. The screen the whole "observation is the reward" promise is cashed on
	## therefore had no focal point — the loudest thing on it was loud only because of a font size.
	##
	## The result and the read verdict are ONE argument ("this happened, and here is whether your
	## plan was the reason") and they are now one bordered band, tinted by the verdict's own tone,
	## sitting above the evidence rather than in it. Nothing is removed, no branch is collapsed and
	## no sentence is rewritten — `read_verdict()` is untouched, including the branch this project
	## considers its most instructive result ("YOUR READ WAS RIGHT. YOU LOST ANYWAY."), which reads
	## far harder inside a CAUTION-edged plate than it did as the fourth line of a wall of text.
	## ⚠️ GRADED ONCE, READ ONCE — see `_graded_claims()`'s ⚠️. The verdict is now needed BEFORE the
	## result line is drawn (its tone tints the band the result sits in), so it is computed here and
	## reused below rather than computed a second time further down.
	var verdict: Dictionary = read_verdict(graded, str(_result.get("winner", "draw")),
		_team_a, _team_b)
	var tone: String = str(verdict.get("tone", "flat"))
	var hero := PanelContainer.new()
	hero.add_theme_stylebox_override("panel",
		UiTheme.panel_style("raised", _tone_colour(tone)))
	box.add_child(hero)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	hero.add_child(hv)

	# The result and the clock on ONE line: they are the same fact seen twice, and stacking them
	# spent a whole row on eight characters.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	hv.add_child(top)

	var result_lbl := Label.new()
	result_lbl.text = result_text
	# ⚠️ KEPT LOUD, TAKEN FROM THE SCALE. Round 18 judged "leading with VICTORY at display size" an
	# improvement and it stays the largest thing on the screen — but 40px was a number off the
	# keyboard, not a register. SIZE_DISPLAY is the same register the title screen's wordmark uses.
	result_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_DISPLAY)
	result_lbl.add_theme_color_override("font_color", result_col)
	result_lbl.add_theme_font_override("font", UiTheme.display_font(3))
	top.add_child(result_lbl)

	var sub := Label.new()
	sub.text = "%.1fs — %d vs %d standing" % [float(_result.get("duration", 0.0)),
		int(_result.get("survivorsA", 0)), int(_result.get("survivorsB", 0))]
	sub.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	sub.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.size_flags_vertical = Control.SIZE_SHRINK_END
	top.add_child(sub)

	# ⚠️ THE CLOCK, ON THE SCREEN THE PLAYER SEES MOST. Round 16 measured a fight advantage
	# compounding to 4.03x and dying against a boolean; round 17's answer is to score PACE instead
	# of adding difficulty (`docs/CONVERSION_DIAGNOSIS.md` §2d — there are only ~6 points of
	# headroom above a competent player, so any harder gate must work by deleting the naive one).
	# That only converts anything if the clock is FELT during the climb, so it is stated after every
	# fight, not saved for a screen visited once. Read live from `Career` via `Pace.snapshot()`.
	var snap: Dictionary = Pace.snapshot()
	if not snap.is_empty():
		var pace_lbl := Label.new()
		pace_lbl.text = Pace.pace_line(snap)
		pace_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pace_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
		pace_lbl.add_theme_color_override("font_color", Pace.pace_color(snap))
		hv.add_child(pace_lbl)

	# ⚠️ A TONE-COLOURED RULE, NOT AN `HSeparator`. Inside the band the divider is doing a second
	# job — it is the join between "what happened" and "was your plan the reason", the two halves
	# of the one argument — and a default separator says only "these are different rows". Same ink
	# as the band's edge, so the plate reads as one object.
	var rule := ColorRect.new()
	rule.color = _tone_colour(tone)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv.add_child(rule)

	# ── 2. WAS THE PLAN THE REASON. ──────────────────────────────────────────────────────────
	var committed: Dictionary = TacticsScript.committed if tactics_apply else {}
	var stored: Dictionary = committed.get("read", {})
	var plan_a: Dictionary = committed.get("planA", {})

	var eyebrow := Label.new()
	eyebrow.text = "THE READ"
	eyebrow.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	eyebrow.add_theme_color_override("font_color", UiTheme.GOLD)
	eyebrow.add_theme_font_override("font", UiTheme.display_font(4))
	hv.add_child(eyebrow)

	# ⚠️ SIZED BY TONE, AND THAT IS THE FIX RATHER THAN A NEW SENTENCE. `docs/META_UI_DIRECTION.md`
	# C3 says "fix the hierarchy, not the sentence" — so a verdict that ANSWERS the read is a
	# heading (22px, second-largest thing on the screen, right under the result) and a verdict that
	# reports our own inability to answer it ("flat" tone: NO READ TO GRADE / THE READ COULD NOT BE
	# GRADED) drops to body size. It still says the same honest thing in the same words; it just
	# stops being the loudest thing in a fight the player won.
	# ⚠️ AND THE TRACKING IS SIZED BY TONE TOO, FOR THE SAME REASON THE SIZE IS. A verdict that
	# answers the read is set with air in it; the "flat" apology stays at body size AND at normal
	# spacing, so the screen never looks proud of its own inability to grade.
	var flat: bool = tone == "flat"
	var headline := Label.new()
	headline.text = str(verdict.get("headline", ""))
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD
	headline.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY if flat else UiTheme.SIZE_HEADING)
	headline.add_theme_color_override("font_color", _tone_colour(tone))
	if not flat:
		headline.add_theme_font_override("font", UiTheme.display_font(2))
	hv.add_child(headline)

	hv.add_child(_line(str(verdict.get("sub", "")), UiTheme.SIZE_BODY, UiTheme.TEXT_SECONDARY))

	var gp_id: String = str(stored.get("gameplan", ""))
	if gp_id != "":
		var cl := counter_line(gp_id, plan_a)
		if cl != "":
			hv.add_child(_line(cl, UiTheme.SIZE_CAPTION, UiTheme.TEXT_MUTED))

	for c in graded:
		box.add_child(_claim_row(c))
	return box


## The five tones the verdict and the claim rows share, mapped onto the published palette rather
## than onto five hand-mixed near-duplicates. ⚠️ NOTHING HERE IS COLOUR-ALONE — every caller pairs
## the hue with a glyph and a word (`UX_LEGIBILITY.md` §10), which is what makes it safe to reuse
## the threat gradient here at all.
static func _tone_colour(tone: String) -> Color:
	match tone:
		"good": return UiTheme.SAFE
		"warn": return UiTheme.CAUTION
		"bad": return UiTheme.DANGER
		"mixed": return UiTheme.TEXT_PRIMARY
		_: return UiTheme.TEXT_MUTED


## One claim, exactly as it was stated before the fight, with its mark and the number that
## decided it. ⚠️ NOT COLOUR-ONLY (`UX_LEGIBILITY.md` §10) — the glyph and the word both carry
## the verdict, so it reads without hue.
func _claim_row(c: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var mark := "·"
	var word := ""
	var col := UiTheme.TEXT_MUTED
	match str(c.get("verdict", "")):
		"held": mark = "✓"; word = "HELD"; col = UiTheme.SAFE
		"partly": mark = "~"; word = "PARTLY"; col = UiTheme.CAUTION
		"broke": mark = "✗"; word = "BROKE"; col = UiTheme.DANGER
		_: mark = "·"; word = "NOT GRADED"; col = UiTheme.TEXT_MUTED
	# ⚠️ THE CLAIM IS THE PAYOFF LINE AND IT WAS SET BELOW THE ACCESSIBILITY FLOOR. It rendered at
	# 14px with its evidence at 11px — the sentence the whole observe half exists to deliver, in
	# the smallest type on the screen. Claim at SIZE_BODY, evidence at SIZE_CAPTION (the smallest
	# the theme ever hands out), and neither below it.
	row.add_child(_line("%s  %s  — %s" % [mark, str(c.get("claim", "")), word], UiTheme.SIZE_BODY, col))
	var order_text: String = str(c.get("order", ""))
	var evidence: String = str(c.get("evidence", ""))
	row.add_child(_line("      from your order “%s” · %s" % [order_text, evidence],
		UiTheme.SIZE_CAPTION, UiTheme.TEXT_MUTED))
	return row


# ── WHAT TO CHANGE ────────────────────────────────────────────────────────────────────────────

## THE CLOSING BLOCK — one instruction, and which half of the game it belongs to.
##
## ⚠️ IT DERIVES NO NEW FACT. Everything it says is already on the screen: the claims' own
## verdicts and order names (from `grade_read`, graded ONCE in `_rebuild` and passed in), and
## `roster_power()`, which `tactics_ui.gd` already quotes before the fight. This is a restatement,
## deliberately — `UX_LEGIBILITY.md` §8/§12 cap the narrative at two or three hand-authored
## detectors and this adds none. What it adds is a PLACE: the ~200px of dead black round 18
## measured under the team columns, and the fact that "was it my orders or my stable" was
## previously answered only inside the single right-and-lost branch of `read_verdict()`.
##
## ⚠️ AND IT MUST NOT INVENT AN INSTRUCTION IT CANNOT SUPPORT. Where nothing was graded, it says
## so and points at the screen that fixes it, rather than manufacturing advice from a blank.
func _next_step_block(graded: Array) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default", UiTheme.BORDER))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	var head := UiTheme.heading("WHAT TO CHANGE", 2)
	col.add_child(head)

	var broke: Array = []
	var judged := 0
	for c in graded:
		match str((c as Dictionary).get("verdict", "")):
			"held", "partly": judged += 1
			"broke":
				judged += 1
				broke.append(c)

	if judged == 0:
		col.add_child(_line(
			"Nothing this fight could be graded against, so there is no instruction to give. Set a target priority, a shape or a temperament on The Read screen and this block becomes an answer.",
			UiTheme.SIZE_BODY, UiTheme.TEXT_SECONDARY))
		return panel

	# ── THE ORDERS HALF. The first broken claim, named with the exact order it came from — the
	# same icon + name the tactics screen showed (`UX_LEGIBILITY.md` §1 rule 1).
	if not broke.is_empty():
		var b: Dictionary = broke[0]
		# Em-dash, not a full stop: the evidence strings are lower-case fragments written for the
		# claim rows above ("it fell at 18.9s"), and a full stop in front of one reads as a broken
		# sentence rather than a clause.
		col.add_child(_line("Your orders: “%s” did not hold — %s." % [
			str(b.get("order", "?")), str(b.get("evidence", ""))],
			UiTheme.SIZE_BODY, UiTheme.CAUTION))
		if broke.size() > 1:
			col.add_child(_line("%d other claims broke too — change ONE of them and fight the same league again, or you will not know which one moved it." % (broke.size() - 1),
				UiTheme.SIZE_CAPTION, UiTheme.TEXT_MUTED))
	else:
		col.add_child(_line("Your orders: every claim you committed held. Keep this plan against this archetype.",
			UiTheme.SIZE_BODY, UiTheme.SAFE))

	# ── THE STABLE HALF. The same trained-stat comparison `tactics_ui.gd` shows before the fight,
	# so the two bookends of a fight use ONE measurement (`UX_LEGIBILITY.md` §1 rule 1). It was
	# previously reachable only when the read held AND the player lost; the question "was it me or
	# was it them" is live after every result.
	var pa := roster_power(_team_a)
	var pb := roster_power(_team_b)
	if pa > 0.0:
		var pct: float = (pb / pa - 1.0) * 100.0
		var stable_col := UiTheme.TEXT_SECONDARY
		var stable_text := "Your stable: the two rosters are within %.0f%% of each other on trained stat, so the bodies were not the difference." % absf(pct)
		if pct >= 8.0:
			stable_col = UiTheme.CAUTION
			stable_text = "Your stable: theirs carries %.0f%% more trained stat than yours. No order closes that gap — go and train." % pct
		elif pct <= -8.0:
			# ⚠️ "SO ANYTHING THAT WENT WRONG WENT WRONG IN THE ORDERS" WAS PRINTED UNDER A CLEAN
			# SWEEP, where nothing went wrong at all — seen in the round-19 win capture. The
			# stronger-side reading means two different things depending on whether the plan held,
			# and one sentence cannot carry both.
			stable_col = UiTheme.SAFE
			stable_text = ("Your stable: yours is the STRONGER side by %.0f%% on trained stat — this was a fight you were meant to win, so it does not yet prove the plan." % absf(pct)) if broke.is_empty() \
				else "Your stable: yours is the STRONGER side by %.0f%% on trained stat, so what went wrong went wrong in the orders, not in the bodies." % absf(pct)
		col.add_child(_line(stable_text, UiTheme.SIZE_BODY, stable_col))
	return panel


func _teams_row(analysis: Dictionary, id_of: Dictionary, dec: Dictionary, tactics_apply: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_XL)
	row.add_child(_team_col("YOUR TEAM", _team_a, analysis, Art.team_identity(0), true, id_of, dec, tactics_apply))
	row.add_child(_team_col("RIVAL TEAM", _team_b, analysis, Art.team_identity(1), false, id_of, dec, tactics_apply))
	return row


## `identity` is {colour, badge} from Art.team_identity() — always drawn together here, since
## this is exactly the "two teams side by side" case art.gd's own rule is written for.
func _team_col(label_text: String, team: Array, analysis: Dictionary, identity: Dictionary,
		is_team_a: bool, id_of: Dictionary, dec: Dictionary, tactics_apply: bool) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", UiTheme.SPACE_SM)

	# ⚠️ THE TEAM COLOUR IS A BORDER, NOT INK. `art.gd`'s eight liveries are not text tokens and
	# `ensure_contrast()` exists precisely because some of them (iron grey, 2.60:1) cannot be read
	# as text on a panel. The badge glyph carries identity, the border carries the livery, and the
	# heading is the house GOLD like every other section header in the game.
	var tint: Color = UiTheme.team_border_color(0 if is_team_a else 1)
	var header := UiTheme.heading("%s  %s" % [identity["badge"], label_text], 2)
	col.add_child(header)

	var per_unit: Dictionary = analysis.get("per_unit", {})
	var events_by_id: Dictionary = dec.get("events", {})
	for m in team:
		var uid: int = id_of.get(m, -1)
		var stats: Dictionary = per_unit.get(uid, {})
		var events: Array = events_by_id.get(uid, [])
		col.add_child(_unit_report_row(m, uid, stats, tint, is_team_a, events, bool(dec.get("rich", false)), tactics_apply))
	return col


func _unit_report_row(m, uid: int, unit_stats: Dictionary, tint: Color, is_team_a: bool,
		decision_events: Array, rich: bool, tactics_apply: bool) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default", tint))

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(outer)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	outer.add_child(hbox)

	# ⚠️ THE SHARED COMPONENT, NOT THE FIFTH COPY. `theme.gd` §8 names five independent `_portrait`
	# implementations across scripts/ui/ with three signatures; this file carried one of them. It
	# is deleted below — behaviour (placeholder initials at the same footprint) is identical.
	hbox.add_child(UiTheme.portrait(m.species_id, m.species_name, Vector2(40, 40), tint))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var survived: bool = unit_stats.get("survived", true)
	var name_lbl := Label.new()
	name_lbl.text = "%s%s" % [m.species_name, ("" if survived else "  (fallen)")]
	name_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBHEADING)
	name_lbl.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY if survived else UiTheme.TEXT_MUTED)
	info.add_child(name_lbl)

	var dmg_lbl := Label.new()
	var collision_tag := "  ⚠ shared with a same-species ally — tally split, see note below" if unit_stats.get("collision", false) else ""
	dmg_lbl.text = "dealt %d · took %d%s" % [int(unit_stats.get("dealt", 0)), int(unit_stats.get("taken", 0)), collision_tag]
	dmg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	dmg_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	dmg_lbl.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY if collision_tag == "" else UiTheme.CAUTION)
	info.add_child(dmg_lbl)

	# ⚠️ THE ORDERS COME OUT OF THE DISCLOSURE. `docs/META_UI_DIRECTION.md` §2 slack-point 4: "the
	# two halves of the loop do not use the same words in the same places" — The Read commits
	# `🎯 Hunt the casters`, the report grades it, and then every per-monster row carried only
	# `dealt 180 · took 347`. A damage table is what you build when you cannot say what happened.
	# The row now leads with what this body was TOLD, in the tactics screen's own icon + name
	# (`Tactics.*_INFO`, `UX_LEGIBILITY.md` §1 rule 1 — one vocabulary, never two), and the full
	# order/nature breakdown stays inside the disclosure where it always was.
	var told := _orders_chip_line(m, is_team_a, tactics_apply)
	if told != "":
		var told_lbl := Label.new()
		told_lbl.text = told
		told_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		told_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
		told_lbl.add_theme_color_override("font_color", UiTheme.GOLD if is_team_a else UiTheme.TEXT_SECONDARY)
		info.add_child(told_lbl)

	# Critical-event teaser — shown even collapsed, per UX_LEGIBILITY.md §7 item 2: the one line
	# of the decision log that matters most should never require a click to see.
	var teaser := _critical_teaser(decision_events)
	if teaser != "":
		var teaser_lbl := Label.new()
		teaser_lbl.text = teaser
		teaser_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		teaser_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
		teaser_lbl.add_theme_color_override("font_color", UiTheme.CAUTION)
		outer.add_child(teaser_lbl)

	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	details.visible = false

	var toggle := Button.new()
	toggle.text = "▸ Orders & decision log"
	toggle.flat = true
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	toggle.pressed.connect(func():
		details.visible = not details.visible
		toggle.text = "▾ Orders & decision log" if details.visible else "▸ Orders & decision log"
	)
	outer.add_child(toggle)
	outer.add_child(details)

	var orders_box := VBoxContainer.new()
	orders_box.add_theme_constant_override("separation", 2)
	for line in _orders_summary_lines(m, is_team_a, tactics_apply):
		orders_box.add_child(line)
	details.add_child(orders_box)
	details.add_child(HSeparator.new())
	details.add_child(_decision_log_block(decision_events, rich))

	return panel


## Every axis `tactics.gd` tracks today, tagged ORDER vs NATURE, reusing its *_INFO copy verbatim
## (UX_LEGIBILITY.md §1 rule 1 — "the vocabulary is not invented twice"). This is the §11 item 1
## "cheap interim slice": real content, buildable against today's engine, with no dependency on
## the tree AI or the frame-stream intent/reason fields at all.
func _orders_summary_lines(m, is_team_a: bool, tactics_apply: bool) -> Array:
	var committed: Dictionary = TacticsScript.committed
	var plan: Dictionary = committed.get("planA" if is_team_a else "planB", {}) if tactics_apply else {}
	var orders_all: Dictionary = committed.get("ordersA" if is_team_a else "ordersB", {}) if tactics_apply else {}
	var own: Dictionary = orders_all.get(m, {})

	# Target priority — per-monster overrides the team plan; absent everywhere = "nature" default.
	var tp_source := "nature"
	var tp_value := ""
	if own.has("targetPriority"):
		tp_value = own["targetPriority"]; tp_source = "order"
	elif plan.has("targetPriority"):
		tp_value = plan["targetPriority"]; tp_source = "order"
	var tp_info: Dictionary = TacticsScript.info_by_id(TacticsScript.TARGET_PRIORITY_INFO, tp_value)

	# Mana policy — team-only, no per-monster override (tactics.gd's own doctrine).
	var mp_source := "order" if plan.has("manaPolicy") else "nature"
	var mp_value: String = plan.get("manaPolicy", "normal")
	var mp_info: Dictionary = TacticsScript.info_by_id(TacticsScript.MANA_POLICY_INFO, mp_value)

	# Formation — team-only, no per-monster override, ever (a formation can't be held alone).
	var fo_source := "order" if plan.has("formation") else "nature"
	var fo_value: String = plan.get("formation", "tight")
	var fo_info: Dictionary = TacticsScript.info_by_id(TacticsScript.FORMATION_INFO, fo_value)

	# Temperament — per-monster only. ⚠️ `tactics_ui.gd` writes {"temperament": "balanced"} into
	# every player-team row THE MOMENT THE ROW IS BUILT, not only when the player picks it — so
	# key-presence can't tell "the player chose Balanced" from "never touched" for team_a. We
	# degrade to a value-based read: only a value that DIFFERS from that untouched default counts
	# as an explicit order. The rival side has no such ambiguity — `orders_for_gameplan` always
	# writes an explicit value straight from `GAMEPLANS`, so presence there genuinely means the
	# gameplan set it.
	var te_value: String = own.get("temperament", "balanced")
	var te_source: String = ("order" if te_value != "balanced" else "nature") if is_team_a else "order"
	var te_info: Dictionary = TacticsScript.info_by_id(TacticsScript.TEMPERAMENT_INFO, te_value)

	var rows := [
		["Target priority", tp_info, tp_source],
		["Mana policy", mp_info, mp_source],
		["Formation", fo_info, fo_source],
		["Temperament", te_info, te_source],
	]

	# UX_LEGIBILITY.md §9's polish recommendation: if the player set literally nothing, a 4-line
	# table that reads "its nature" four times in a row teaches nothing — collapse to one line.
	if is_team_a:
		var any_order := false
		for r in rows:
			if r[2] == "order":
				any_order = true
				break
		if not any_order:
			return [_summary_line("No standing orders yet — every monster is following its own nature.", UiTheme.TEXT_MUTED)]

	var out: Array = []
	for r in rows:
		var axis_name: String = r[0]
		var info: Dictionary = r[1]
		var source: String = r[2]
		var suffix := _order_suffix(source, is_team_a)
		var icon: String = info.get("icon", "")
		var name: String = info.get("name", "?")
		out.append(_summary_line(
			"%s: %s %s %s" % [axis_name, icon, name, suffix],
			UiTheme.TEXT_PRIMARY if source == "order" else UiTheme.TEXT_MUTED))
	return out


## The one-line "what it was told" chip for the collapsed row: the axes the player (or the rival's
## gameplan) actually SET, in the exact icon + name the tactics screen showed. Axes left on their
## default are omitted rather than printed as "its nature" — a row that lists four defaults is the
## four-line table `UX_LEGIBILITY.md` §9 already asked to be collapsed, and it says nothing.
func _orders_chip_line(m, is_team_a: bool, tactics_apply: bool) -> String:
	if not tactics_apply:
		return ""
	var committed: Dictionary = TacticsScript.committed
	var plan: Dictionary = committed.get("planA" if is_team_a else "planB", {})
	var orders_all: Dictionary = committed.get("ordersA" if is_team_a else "ordersB", {})
	var own: Dictionary = orders_all.get(m, {})
	var parts: Array = []

	var tp_value := ""
	if own.has("targetPriority"):
		tp_value = str(own["targetPriority"])
	elif plan.has("targetPriority"):
		tp_value = str(plan["targetPriority"])
	if tp_value != "":
		parts.append(_read_order_name(TacticsScript.TARGET_PRIORITY_INFO, tp_value))

	# ⚠️ TEMPERAMENT'S DEFAULT IS AMBIGUOUS FOR YOUR OWN SIDE AND THE ROW MUST NOT GUESS.
	# `tactics_ui.gd` writes {"temperament": "balanced"} into every player row THE MOMENT THE ROW IS
	# BUILT, so key-presence cannot tell "the player chose Balanced" from "never touched". Only a
	# value that differs from that untouched default counts as an order — the same degradation
	# `_orders_summary_lines()` already makes, and for the same reason.
	var te_value: String = str(own.get("temperament", "balanced"))
	if te_value != "balanced" or not is_team_a:
		parts.append(_read_order_name(TacticsScript.TEMPERAMENT_INFO, te_value))

	var pi_value: String = str(own.get("positionalIntent", ""))
	if pi_value != "":
		parts.append(_read_order_name(TacticsScript.POSITIONAL_INTENT_INFO, pi_value))

	if plan.has("formation"):
		parts.append(_read_order_name(TacticsScript.FORMATION_INFO, str(plan["formation"])))

	if parts.is_empty():
		return "" if is_team_a else ""
	return "%s %s" % ["told:" if is_team_a else "their plan:", "  ·  ".join(parts)]


func _order_suffix(source: String, is_team_a: bool) -> String:
	if source == "order":
		return "— your order" if is_team_a else "— the rival's gameplan"
	return "— its nature"


func _summary_line(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	l.add_theme_color_override("font_color", color)
	return l


## The decision log body: critical events always shown, standard shown once expanded (both are
## already inside the "Orders & decision log" toggle), minor collapsed under its own "+N more" —
## the third density lever from UX_LEGIBILITY.md §7. `rich` tells us whether these events carry a
## real `attribution` field (see _decision_events_by_id) or are a derived approximation.
func _decision_log_block(events: Array, rich: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	var header := Label.new()
	header.text = "Decision log"
	header.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	header.add_theme_color_override("font_color", UiTheme.GOLD)
	box.add_child(header)

	if events.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No decisions recorded for this fight." if rich else \
			"No intent data in this build yet — the tree AI (scripts/ai/monster_tree.gd) hasn't " + \
			"shipped, so there is nothing beyond the Orders Summary above to log here."
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
		empty_lbl.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
		box.add_child(empty_lbl)
		return box

	if not rich:
		var caveat := Label.new()
		caveat.text = "⚠ No ORDER / ITS NATURE / REACTED tag yet: the AI computes one on every decision, but the blackboard's log stores only the branch and the reason. Showing those."
		caveat.autowrap_mode = TextServer.AUTOWRAP_WORD
		caveat.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
		caveat.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
		box.add_child(caveat)

	var critical: Array = events.filter(func(e): return e.get("importance", "standard") == "critical")
	var standard: Array = events.filter(func(e): return e.get("importance", "standard") == "standard")
	var minor: Array = events.filter(func(e): return e.get("importance", "standard") == "minor")

	for e in critical:
		box.add_child(_decision_line(e, UiTheme.CAUTION))
	for e in standard:
		box.add_child(_decision_line(e, UiTheme.TEXT_PRIMARY))

	if not minor.is_empty():
		var minor_box := VBoxContainer.new()
		minor_box.visible = false
		var toggle := Button.new()
		toggle.text = "+%d more" % minor.size()
		toggle.flat = true
		toggle.focus_mode = Control.FOCUS_ALL
		toggle.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
		toggle.pressed.connect(func():
			minor_box.visible = not minor_box.visible
			toggle.text = "Hide" if minor_box.visible else "+%d more" % minor.size()
		)
		box.add_child(toggle)
		box.add_child(minor_box)
		for e in minor:
			minor_box.add_child(_decision_line(e, UiTheme.TEXT_MUTED))

	return box


func _decision_line(e: Dictionary, color: Color) -> Label:
	var t: float = float(e.get("t", 0.0))
	var label_text: String = str(e.get("label", e.get("branch", "")))
	var reason: String = str(e.get("reason", ""))
	var attribution: String = str(e.get("attribution", ""))
	var suffix := ""
	if attribution == "order":
		suffix = " — your order"
	elif attribution == "nature":
		suffix = " — its nature"
	elif attribution == "reactive":
		suffix = " — reacted"
	var text := "%.1fs — %s" % [t, (label_text if label_text != "" else "(intent unavailable)")]
	if reason != "":
		text += ": %s" % reason
	text += suffix
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	l.add_theme_color_override("font_color", color)
	return l


func _critical_teaser(events: Array) -> String:
	for e in events:
		if e.get("importance", "") == "critical":
			var t: float = float(e.get("t", 0.0))
			var reason: String = str(e.get("reason", ""))
			var label_text: String = str(e.get("label", e.get("branch", "")))
			var body := reason if reason != "" else label_text
			if body != "":
				return "%.1fs — %s" % [t, body]
	return ""


## `Tactics.committed` is a process-wide static slot (same pattern as this file's own `pending`
## handoff) — it can outlive the fight it described. Guard against showing a STALE plan for a
## different roster: only trust it if at least one of ITS committed orders keys to a monster
## actually fielded in this fight (both `orders_a`/`orders_for_gameplan` always write one entry
## per fielded monster in the real flow, so a real, matching commit always passes this check).
func _tactics_applies(id_of: Dictionary) -> bool:
	var committed: Dictionary = TacticsScript.committed
	if committed.is_empty():
		return false
	# ⚠️ A TEAM PLAN COUNTS. THIS PREDICATE ASKED THE WRONG QUESTION AND IT DARKENED THE READ.
	# It only looked for PER-MONSTER orders, so a player who set a team-wide target priority,
	# shape and temperament — the normal case, and the only case if they never open a per-monster
	# row — got "You committed no claim this fight" on the report, no orders summary, and no
	# grading at all. Measured on the production watch path 2026-08-09: `planA` carried a live
	# `manmark` that the SIM demonstrably obeyed (a decision log reading "target: Regalor
	# (marked)") while the screen said no claim had been made. The predicate predates the read
	# grading and was never widened to it; a claim the engine received and the report denies is
	# the worst failure this screen has, because it teaches the player their order did nothing.
	if not (committed.get("planA", {}) as Dictionary).is_empty():
		return true
	if not (committed.get("planB", {}) as Dictionary).is_empty():
		return true
	var orders_all: Dictionary = {}
	for k in committed.get("ordersA", {}):
		orders_all[k] = true
	for k in committed.get("ordersB", {}):
		orders_all[k] = true
	for m in id_of:
		if orders_all.has(m):
			return true
	return false


func _build_roster_and_ids(team_a: Array, team_b: Array) -> Dictionary:
	var roster: Array = team_a + team_b
	var id_of: Dictionary = {}
	for i in range(roster.size()):
		id_of[roster[i]] = i
	return {"roster": roster, "id_of": id_of}


## Pure post-battle pass: per-unit damage dealt/taken/survival, the single biggest hit, and the
## first death (used by _narrative below) — now keyed by a stable per-fight `id`, not species
## NAME. Two paths:
##
## 1. FRAME STREAM PRESENT (BUILD_CONTRACT.md §2, SpatialSim.run()'s `frames[].shots[]`) — the
##    contract-precise path. `shots` already carries true `fromId`/`toId`, so there is NO
##    same-species collision risk here at all; the bug this file's comment used to flag cannot
##    occur on this path.
## 2. NO FRAME STREAM (today's battle_sim.gd demo path) — the flat `log` only ever carries
##    species NAME + side on its events, never an id. We narrow the old collision risk from "any
##    same-species pair anywhere" to "same species AND same side" by keying on both, and — unlike
##    the old silent behaviour — make a real collision VISIBLE: damage is split across the tied
##    candidates and a `collision` flag is set, surfaced as a caveat in the unit row.
func _analyze(battle_log: Array, team_a: Array, team_b: Array, frames: Array, id_of: Dictionary, roster: Array) -> Dictionary:
	var per_unit: Dictionary = {}
	for i in range(roster.size()):
		per_unit[i] = {"dealt": 0, "taken": 0, "survived": true, "collision": false}

	var biggest: Dictionary = {"dmg": -1}
	var first_death = null

	if not frames.is_empty():
		var alive_now: Dictionary = {}
		for f in frames:
			for u in f.get("units", []):
				var uid2: int = int(u.get("id", -1))
				if uid2 < 0 or not per_unit.has(uid2):
					continue
				var was_alive: bool = alive_now.get(uid2, true)
				var is_alive: bool = bool(u.get("alive", true))
				if was_alive and not is_alive:
					per_unit[uid2]["survived"] = false
					if first_death == null:
						var killer_name := ""
						var killer_dmg := -1
						for shot in f.get("shots", []):
							if int(shot.get("toId", -1)) == uid2 and bool(shot.get("hit", false)):
								var sdmg: int = int(shot.get("dmg", 0))
								if sdmg > killer_dmg:
									killer_dmg = sdmg
									var from_id: int = int(shot.get("fromId", -1))
									killer_name = roster[from_id].species_name if from_id >= 0 and from_id < roster.size() else ""
						first_death = {"t": float(f.get("t", 0.0)), "unit": roster[uid2].species_name, "killer": killer_name}
				alive_now[uid2] = is_alive
			for shot in f.get("shots", []):
				var from_id2: int = int(shot.get("fromId", -1))
				var to_id2: int = int(shot.get("toId", -1))
				var dmg: int = int(shot.get("dmg", 0))
				if per_unit.has(from_id2):
					per_unit[from_id2]["dealt"] += dmg
				if per_unit.has(to_id2):
					per_unit[to_id2]["taken"] += dmg
				if dmg > int(biggest.get("dmg", -1)) and to_id2 >= 0 and to_id2 < roster.size() and from_id2 >= 0 and from_id2 < roster.size():
					biggest = {
						"dmg": dmg, "attacker": roster[from_id2].species_name, "target": roster[to_id2].species_name,
						"move": str(shot.get("move", "Attack")), "crit": bool(shot.get("crit", false)), "t": float(f.get("t", 0.0)),
					}
		return {"per_unit": per_unit, "biggest_hit": biggest, "first_death": first_death}

	# ── Fallback: no frame stream (battle_sim.gd) ──────────────────────────────────────────────
	var name_side_to_ids: Dictionary = {}
	for m in team_a:
		var key := "%s|A" % m.species_name
		if not name_side_to_ids.has(key):
			name_side_to_ids[key] = []
		name_side_to_ids[key].append(id_of[m])
	for m in team_b:
		var key2 := "%s|B" % m.species_name
		if not name_side_to_ids.has(key2):
			name_side_to_ids[key2] = []
		name_side_to_ids[key2].append(id_of[m])

	for e in battle_log:
		var kind: String = e.get("kind", "")
		if kind == "hit":
			var dmg2 := int(e.get("dmg", 0))
			var att_ids: Array = name_side_to_ids.get("%s|%s" % [e.get("attacker", ""), e.get("attackerSide", "")], [])
			var tgt_ids: Array = name_side_to_ids.get("%s|%s" % [e.get("target", ""), e.get("targetSide", "")], [])
			_credit(per_unit, att_ids, "dealt", dmg2)
			_credit(per_unit, tgt_ids, "taken", dmg2)
			if dmg2 > int(biggest.get("dmg", -1)):
				biggest = {
					"dmg": dmg2, "attacker": e.get("attacker", "?"), "target": e.get("target", "?"),
					"move": e.get("move", "Attack"), "crit": e.get("crit", false), "t": e.get("t", 0.0),
				}
		elif kind == "death":
			var d_ids: Array = name_side_to_ids.get("%s|%s" % [e.get("unit", ""), e.get("side", "")], [])
			for did in d_ids:
				if per_unit.has(did):
					per_unit[did]["survived"] = false
					if d_ids.size() > 1:
						per_unit[did]["collision"] = true
			if first_death == null:
				first_death = e

	return {"per_unit": per_unit, "biggest_hit": biggest, "first_death": first_death}


func _credit(per_unit: Dictionary, ids: Array, field: String, dmg: int) -> void:
	if ids.is_empty():
		return
	if ids.size() == 1:
		if per_unit.has(ids[0]):
			per_unit[ids[0]][field] += dmg
		return
	var share := int(round(float(dmg) / float(ids.size())))
	for uid in ids:
		if per_unit.has(uid):
			per_unit[uid][field] += share
			per_unit[uid]["collision"] = true


## The shared Decision Event stream (UX_LEGIBILITY.md §2), grouped by unitId. Two sources, richest
## first:
##
## 1. `battle_log` entries with `kind == "intent_change"` — the full shape UX_LEGIBILITY.md §2
##    proposes (label/reason/attribution/importance/target), if a sim ever emits it directly onto
##    the flat log. Nothing here is derived from it; it's read as-authored.
## 2. Otherwise, derived by DETECTING TRANSITIONS in `frames[].units[].intent`/`.reason`
##    (BUILD_CONTRACT.md §2's actual, current shape) — the load-bearing density fix from
##    UX_LEGIBILITY.md §1 rule 2: log the transition, never the tick. ⚠️ This path has no
##    `attribution` to read (BUILD_CONTRACT §2's frame shape carries only `intent`/`reason` prose,
##    not a structured attribution enum) — we do NOT infer one by pattern-matching the reason
##    string, because that is exactly the kind of renderer-side derivation both docs forbid
##    ("the renderer derives nothing"). See this stream's final report for what's missing.
func _decision_events_by_id(battle_log: Array, frames: Array, result: Dictionary,
		roster: Array, n_a: int) -> Dictionary:
	var by_id: Dictionary = {}
	var rich_found := false
	for e in battle_log:
		if e.get("kind", "") == "intent_change":
			rich_found = true
			var uid := int(e.get("unitId", -1))
			if uid < 0:
				continue
			if not by_id.has(uid):
				by_id[uid] = []
			by_id[uid].append(e)
	if rich_found:
		for uid in by_id:
			var arr: Array = by_id[uid]
			arr.sort_custom(func(a, b): return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
		return {"events": by_id, "rich": true}

	# ── 2. THE SIM'S OWN DECISION LOG. ⚠️ THIS WAS ALREADY BEING RETURNED AND NOBODY READ IT.
	# `sim/sim.gd:run()` returns `decision_logs` — `bt.gd:Blackboard._log`, one entry per BRANCH
	# CHANGE, which is precisely the transition-only stream `UX_LEGIBILITY.md` §1 rule 2 asks for —
	# and `arena_3d.gd:_adapt_result()` forwards it as `decisionLogs`. This screen was instead
	# DIFFING `intent`/`reason` across the frame stream to reconstruct the same thing, which is a
	# second source of truth for data the first source already publishes, and a worse one (it
	# re-derives the transition the sim already decided).
	# ⚠️ AND IT IS STILL NOT "rich". `monster_tree.gd`/`combat_tree.gd` compute an `attribution`
	# ("order" / "nature" / "reacted") on every decision — `_finish()` returns it — but
	# `Blackboard._commit_pending()` records only `{tick, intent, reason}` and `_emit_frame()`
	# publishes only `intent`/`reason`. The three-bucket attribution the whole legibility design
	# turns on is computed once per decision and thrown away at the blackboard. See the integrator
	# note; it is two fields, not a feature.
	var tree_logs: Dictionary = result.get("decisionLogs", result.get("decision_logs", {}))
	if not tree_logs.is_empty():
		for sim_id in tree_logs:
			var uid_t: int = _uid_of_sim_id(str(sim_id), n_a)
			if uid_t < 0 or uid_t >= roster.size():
				continue
			var evs_t: Array = []
			for e2 in (tree_logs[sim_id] as Array):
				var rec: Dictionary = e2
				var tick: int = int(rec.get("tick", 0))
				# Seconds come from the FRAME the tick belongs to, never from a re-derived DT —
				# the stream already states the time and the renderer derives nothing.
				var t_s: float = float((frames[tick] as Dictionary).get("t", 0.0)) if tick < frames.size() else 0.0
				evs_t.append({
					"t": t_s, "label": _humanise(str(rec.get("intent", "")), roster, n_a),
					"reason": _humanise(str(rec.get("reason", "")), roster, n_a),
					"attribution": "", "importance": "standard", "kind": "tree",
				})
			if not evs_t.is_empty():
				evs_t[evs_t.size() - 1]["importance"] = "critical"
				by_id[uid_t] = evs_t
		if not by_id.is_empty():
			return {"events": by_id, "rich": false, "source": "tree"}

	var prev: Dictionary = {}  # id -> [intent, reason]
	for f in frames:
		var t: float = float(f.get("t", 0.0))
		for u in f.get("units", []):
			var uid2: int = int(u.get("id", -1))
			if uid2 < 0:
				continue
			var intent: String = str(u.get("intent", ""))
			var reason: String = str(u.get("reason", ""))
			var key: Array = [intent, reason]
			var prev_key: Array = prev.get(uid2, ["", ""])
			if key != prev_key and (intent != "" or reason != ""):
				if not by_id.has(uid2):
					by_id[uid2] = []
				# ⚠️ THIS PATH WAS PRINTING RAW SIM IDS AND THE TREE PATH ABOVE WAS NOT.
				# Round 13 found the report speaking in "bulling through a03 to a02" and fixed it —
				# in `_humanise`, applied to the tree-log branch only. The frame-diff FALLBACK
				# branch, three screens down the same function, kept writing `intent`/`reason`
				# verbatim. So the bug was fixed on the path that has richer data and left on the
				# path that runs when that data is missing, which is the copy a player is more
				# likely to hit. Same re-keying, same function, no fact invented.
				by_id[uid2].append({
					"t": t, "label": _humanise(intent, roster, n_a),
					"reason": _humanise(reason, roster, n_a),
					"attribution": "", "importance": "standard", "kind": "derived",
				})
			prev[uid2] = key

	# Best-effort tiering with no real importance signal available: the unit's FINAL recorded
	# transition is the branch it died (or ended) on — mark that one critical, per the tier table.
	for uid3 in by_id:
		var evs: Array = by_id[uid3]
		if not evs.is_empty():
			evs[evs.size() - 1]["importance"] = "critical"

	return {"events": by_id, "rich": false, "source": "frames"}


## ⚠️ THE SIM SPEAKS IN IDS AND THE PLAYER DOES NOT. The behaviour tree's own reason strings name
## monsters by their sim id — "bulling through b01 to b00", "target: a04 (weakest)" — and this
## screen was printing them verbatim, so the one place in the game that explains WHY a monster did
## something did it in a vocabulary that appears nowhere else in the product. This is a pure
## re-keying of an identifier the sim itself published (the same thing `arena_3d.gd:
## _name_of_sim_id` does for its own log), not a derivation: no fact is invented, one name is
## swapped for another name of the same body.
func _humanise(text: String, roster: Array, n_a: int) -> String:
	if text == "" or roster.is_empty():
		return text
	var out := text
	for k in range(roster.size()):
		var sim_id: String = ("a%02d" % k) if k < n_a else ("b%02d" % (k - n_a))
		if out.find(sim_id) >= 0:
			out = out.replace(sim_id, str(roster[k].species_name))
	return out


## "a03" / "b01" -> the index into `team_a + team_b`. The sim's ids are zero-padded and sorted
## into roster order, which is the invariant `_adapt_result()` asserts rather than assumes.
func _uid_of_sim_id(sim_id: String, n_a: int) -> int:
	if sim_id.length() < 2:
		return -1
	var slot: int = sim_id.substr(1).to_int()
	if sim_id.begins_with("a"):
		return slot
	if sim_id.begins_with("b"):
		return n_a + slot
	return -1


## One legible causal sentence, not a highlight reel — the whole point of this screen is telling
## the player WHY the fight went the way it did, in terms they can check their read against.
## ⚠️ Deliberately ONE hand-authored detector (turning point), per UX_LEGIBILITY.md §8/§12 —
## folding in the victim's own last recorded reason (when decision data exists) is an enrichment
## of this SAME detector, not a second one; the isolation-at-death and commitment-absence
## detectors §8 also describes are explicitly not built here (they need spatial support-range
## checks this pass doesn't have reliable data for yet — see the final report).
func _narrative(analysis: Dictionary, dec: Dictionary, id_of: Dictionary, roster: Array) -> String:
	var fd = analysis.get("first_death")
	if fd == null:
		return ""
	var when: float = float(fd.get("t", 0.0))
	var killer: String = fd.get("killer", "")
	var victim: String = fd.get("unit", "?")
	var reason := _reason_at_death(dec, id_of, roster, victim, when)

	# ⚠️ THE VICTIM'S LAST DECISION GETS ITS OWN CLAUSE, NOT AN INLINE SPLICE. Folded into the
	# middle of the sentence it produced "…at 13.2s — target: b00 (casters) and the fight never
	# came back level", which is two grammars in one line. The tree's reason strings are fragments
	# written for a log, so they are quoted as fragments.
	var head := ""
	if killer != "":
		head = "Turning point: %s brought down %s at %.1fs, and the fight never came back level." % [killer, victim, when]
	else:
		head = "%s fell at %.1fs to sustained damage, without a single blow finishing it." % [victim, when]
	if reason != "":
		head += "  %s's last decision: %s." % [victim, reason]
	return head


## Best-effort lookup of what the victim was doing when it died, from the decision-event stream —
## only produces text once real intent/reason data exists (see _decision_events_by_id); a no-op
## today. Matches by species name (prose enrichment only, not a stats-integrity path — the id-keyed
## per_unit dict above is what damage/survival numbers rely on).
func _reason_at_death(dec: Dictionary, id_of: Dictionary, roster: Array, victim_name: String, death_t: float) -> String:
	var events_by_id: Dictionary = dec.get("events", {})
	for m in id_of:
		if m.species_name != victim_name:
			continue
		var uid: int = id_of[m]
		var events: Array = events_by_id.get(uid, [])
		var best := ""
		for e in events:
			if float(e.get("t", 0.0)) <= death_t:
				var r := str(e.get("reason", ""))
				if r != "":
					best = r
		return best
	return ""


## ⚠️ `_portrait()` IS GONE — it was the third of five independent copies `theme.gd` §8 names, and
## the only one whose placeholder font size (`portrait_size.y * 0.4`) could land BELOW the 14px
## accessibility floor as the footprint shrank. Call `UiTheme.portrait()`; it clamps.


func _line(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
