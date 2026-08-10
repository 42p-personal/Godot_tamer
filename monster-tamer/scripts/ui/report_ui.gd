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
			var claim := ""
			match tp:
				"manmark": claim = "We hunt %s. It falls, and it falls first." % names
				"casters": claim = "We go through their casters — %s falls before their front line." % names
				"tanks": claim = "We break %s, the biggest body they have." % names
			out.append({
				"id": "target", "axis": "targetPriority", "order": _read_order_name(TacticsScript.TARGET_PRIORITY_INFO, tp),
				"claim": claim,
				"test": "measured as the share of your damage that lands on %s, and whether it falls" % names,
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
	for m in marks:
		var uid2: int = int(idx.get(m, -1))
		if uid2 < 0:
			continue
		mark_ids.append(uid2)
		on_marks += float(to_total.get(uid2, 0.0))
		if not deaths.has(uid2):
			all_dead = false
	if mark_ids.is_empty() or a_total <= 0.0:
		g["verdict"] = "ungraded"
		g["evidence"] = "your team landed no damage at all, so there is no share to measure"
		return

	var share: float = on_marks / a_total
	var enemy_n: int = maxi(1, (idx.size() - n_a))
	var fair: float = float(mark_ids.size()) / float(enemy_n)
	var concentrated: bool = share >= fair * 1.4
	var fell_first: bool = first_enemy_death_id in mark_ids

	var bits := "%.0f%% of your damage went into %s (an even spread would be %.0f%%)" % [share * 100.0, _read_names(marks), fair * 100.0]
	if all_dead:
		bits += "; it fell%s" % (" first" if fell_first else " — but not first")
	else:
		bits += "; it was still standing at the end"
	g["evidence"] = bits
	if all_dead and (concentrated or fell_first):
		g["verdict"] = "held"
	elif all_dead or concentrated:
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
		if nearest > SUPPORT_RADIUS:
			alone.append(uid)
			worst = maxf(worst, nearest if nearest < INF else 0.0)
	var fallen: int = 0
	for uid3 in deaths:
		if int(uid3) < n_a:
			fallen += 1
	if fallen == 0:
		g["verdict"] = "held"
		g["evidence"] = "nobody of yours fell at all"
	elif alone.is_empty():
		g["verdict"] = "held"
		g["evidence"] = "%d of yours fell, every one of them with an ally inside %.0f units" % [fallen, SUPPORT_RADIUS]
	else:
		g["verdict"] = "broke" if alone.size() * 2 > fallen else "partly"
		g["evidence"] = "%d of your %d losses died alone — nearest ally %.0f units away, support range is %.0f" % [
			alone.size(), fallen, worst, SUPPORT_RADIUS]


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
		return {"headline": "YOUR READ WAS RIGHT. YOU LOST ANYWAY.", "tone": "warn",
			"sub": "%s, and it still was not enough. %s" % [score, _strength_line(team_a, team_b)]}
	if held + partly == judged and held > 0:
		return {"headline": "MOST OF THE READ HELD." if won else "THE READ HALF HELD.", "tone": "mixed",
			"sub": "%s. Look at the claim that only partly landed — that is the one to change." % score}
	if held == 0:
		if won:
			return {"headline": "YOU WON WITHOUT THE READ.", "tone": "mixed",
				"sub": "%s. You took this on raw strength, not on the plan — the same orders against a team your own size will not hold." % score}
		return {"headline": "THE READ BROKE, AND IT COST YOU.", "tone": "bad",
			"sub": "%s. Every claim you committed to failed; the orders are the thing to change, not the roster." % score}
	return {"headline": "PART OF THE READ HELD." if won else "PART OF THE READ HELD, AND IT WAS NOT ENOUGH.",
		"tone": "mixed", "sub": "%s." % score}


## ⚠️ ROSTER STRENGTH, NOT A POWER RATING. The flat sum of the six trained stats over a side —
## exactly the thing the ladder's `field_fill` dial moves and the one number a player can act on
## by training. Quoted only in the right-and-lost case, where "was it me or was it them" is the
## actual question and an unanswered one turns a teachable loss into a grievance.
static func _strength_line(team_a: Array, team_b: Array) -> String:
	var pa := _roster_power(team_a)
	var pb := _roster_power(team_b)
	if pa <= 0.0:
		return "The tactics were not the problem."
	var pct: float = (pb / pa - 1.0) * 100.0
	if pct >= 8.0:
		return "Their roster carries %.0f%% more trained stat than yours — this was a stable problem, not a tactics problem. Go and train." % pct
	if pct <= -8.0:
		return "And you were the STRONGER side by %.0f%%, so the orders held and something else lost it — read the turning point below." % absf(pct)
	return "The two rosters are within %.0f%% of each other, so the plan was not the difference. Read the turning point below." % absf(pct)


static func _roster_power(team: Array) -> float:
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
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.1)
	bg.anchor_right = 1; bg.anchor_bottom = 1
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1; scroll.anchor_bottom = 1
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	scroll.add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 14)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_content)


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

	# ⚠️ THE READ GOES FIRST, ABOVE THE SCORELINE. The vision's payoff is not "who won" — it is
	# "my read was right" — so the verdict on the read is the most prominent thing on this screen
	# and the result is demoted to a subtitle under it. A report that leads with the score and
	# buries the grading has told the player what happened without telling them whether they were
	# right, which is the half of "commit, then observe" this screen exists for.
	# ⚠️ THE ORDER OF THIS SCREEN IS THE ARGUMENT IT MAKES: verdict, then result, then WHY, then
	# the detail. It used to open with a 40px VICTORY/DEFEAT and put the causal sentence below ten
	# monster panels — which tells the player what happened and makes them scroll for whether they
	# were right. The turning point is promoted with the verdict because `read_verdict()` points at
	# it by name in the right-and-lost case, and a sentence that refers to something off-screen is
	# not a sentence.
	_content.add_child(_read_block(applies))
	_content.add_child(HSeparator.new())
	_content.add_child(_banner())

	var narrative := _narrative(analysis, dec, id_of, roster)
	if narrative != "":
		_content.add_child(_line(narrative, 14, Color(0.85, 0.85, 0.9)))

	var big_hit: Dictionary = analysis.get("biggest_hit", {})
	if int(big_hit.get("dmg", -1)) >= 0:
		var crit_tag := " (CRIT)" if big_hit.get("crit", false) else ""
		_content.add_child(_line(
			"Biggest hit: %s's %s on %s for %d%s" % [big_hit["attacker"], big_hit["move"], big_hit["target"], int(big_hit["dmg"]), crit_tag],
			15, Color(1.0, 0.8, 0.4)))

	_content.add_child(HSeparator.new())
	_content.add_child(_teams_row(analysis, id_of, dec, applies))
	_content.add_child(HSeparator.new())

	var back := Button.new()
	back.text = "Back to the Stable"
	back.custom_minimum_size = Vector2(0, 40)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/stable.tscn"))
	_content.add_child(back)


## THE VERDICT BLOCK — the answer to the promise `tactics_ui.gd` took. Reads the claims the
## player actually confirmed (stored on `Tactics.committed.read` at commit time, so the words
## graded here are byte-identical to the words they said yes to), grades them against this fight,
## and leads with the sentence.
func _read_block(tactics_apply: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)

	var committed: Dictionary = TacticsScript.committed if tactics_apply else {}
	var stored: Dictionary = committed.get("read", {})
	var plan_a: Dictionary = committed.get("planA", {})
	var claims: Array = stored.get("claims", [])
	if claims.is_empty() and tactics_apply:
		# A committed plan with no stored read (an older save, or a screen that committed before
		# this block existed) — rebuild the same claims from the same orders rather than showing
		# nothing. Same function, so the wording is identical either way.
		claims = build_read(plan_a, committed.get("ordersA", {}), _team_a, _team_b)
	var graded: Array = grade_read(claims, _result, _team_a, _team_b)
	var verdict: Dictionary = read_verdict(graded, str(_result.get("winner", "draw")), _team_a, _team_b)

	var tone_colour := {
		"good": Color(0.5, 0.9, 0.55), "warn": Color(0.95, 0.75, 0.35),
		"mixed": Color(0.8, 0.8, 0.85), "bad": Color(0.95, 0.5, 0.45), "flat": Color(0.6, 0.6, 0.65),
	}
	var eyebrow := Label.new()
	eyebrow.text = "THE READ"
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35))
	box.add_child(eyebrow)

	var headline := Label.new()
	headline.text = str(verdict.get("headline", ""))
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD
	headline.add_theme_font_size_override("font_size", 34)
	headline.add_theme_color_override("font_color", tone_colour.get(str(verdict.get("tone", "flat")), Color(0.8, 0.8, 0.85)))
	box.add_child(headline)

	box.add_child(_line(str(verdict.get("sub", "")), 14, Color(0.78, 0.78, 0.83)))

	var gp_id: String = str(stored.get("gameplan", ""))
	if gp_id != "":
		var cl := counter_line(gp_id, plan_a)
		if cl != "":
			box.add_child(_line(cl, 12, Color(0.7, 0.75, 0.72)))

	for c in graded:
		box.add_child(_claim_row(c))
	return box


## One claim, exactly as it was stated before the fight, with its mark and the number that
## decided it. ⚠️ NOT COLOUR-ONLY (`UX_LEGIBILITY.md` §10) — the glyph and the word both carry
## the verdict, so it reads without hue.
func _claim_row(c: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var mark := "·"
	var word := ""
	var col := Color(0.6, 0.6, 0.65)
	match str(c.get("verdict", "")):
		"held": mark = "✓"; word = "HELD"; col = Color(0.5, 0.9, 0.55)
		"partly": mark = "~"; word = "PARTLY"; col = Color(0.9, 0.8, 0.4)
		"broke": mark = "✗"; word = "BROKE"; col = Color(0.95, 0.5, 0.45)
		_: mark = "·"; word = "NOT GRADED"; col = Color(0.6, 0.6, 0.65)
	row.add_child(_line("%s  %s  — %s" % [mark, str(c.get("claim", "")), word], 14, col))
	var order_text: String = str(c.get("order", ""))
	var evidence: String = str(c.get("evidence", ""))
	row.add_child(_line("      from your order “%s” · %s" % [order_text, evidence], 11, Color(0.62, 0.62, 0.68)))
	return row


func _banner() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var winner: String = _result.get("winner", "draw")
	var headline_text := "DRAW"
	var color := Color(0.7, 0.7, 0.72)
	if winner == "A":
		var id_a: Dictionary = Art.team_identity(0)
		headline_text = "%s VICTORY" % id_a["badge"]
		color = id_a["colour"]
	elif winner == "B":
		var id_b: Dictionary = Art.team_identity(1)
		headline_text = "%s DEFEAT" % id_b["badge"]
		color = id_b["colour"]

	var headline := Label.new()
	headline.text = headline_text
	# Demoted from 40 to 24: the score is context for the verdict above it, not the headline.
	headline.add_theme_font_size_override("font_size", 24)
	headline.add_theme_color_override("font_color", color)
	box.add_child(headline)

	var sub := Label.new()
	sub.text = "%.1fs — %d vs %d standing" % [float(_result.get("duration", 0.0)), int(_result.get("survivorsA", 0)), int(_result.get("survivorsB", 0))]
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	box.add_child(sub)

	# ⚠️ THE CLOCK, ON THE SCREEN THE PLAYER SEES MOST. Round 16 measured a fight advantage
	# compounding to 4.03x and dying against a boolean; round 17's answer is to score PACE instead
	# of adding difficulty (docs/CONVERSION_DIAGNOSIS.md §2d — there are only ~6 points of headroom
	# above a competent player, so any harder gate must work by deleting the naive one). That only
	# converts anything if the clock is FELT during the climb, so it is stated after every fight,
	# not saved for a screen visited once. Read live from `Career` via `Pace.snapshot()`.
	var snap: Dictionary = Pace.snapshot()
	if not snap.is_empty():
		var pace_lbl := Label.new()
		pace_lbl.text = Pace.pace_line(snap)
		pace_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pace_lbl.add_theme_font_size_override("font_size", 14)
		pace_lbl.add_theme_color_override("font_color", Pace.pace_color(snap))
		box.add_child(pace_lbl)
	return box


func _teams_row(analysis: Dictionary, id_of: Dictionary, dec: Dictionary, tactics_apply: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.add_child(_team_col("YOUR TEAM", _team_a, analysis, Art.team_identity(0), true, id_of, dec, tactics_apply))
	row.add_child(_team_col("RIVAL TEAM", _team_b, analysis, Art.team_identity(1), false, id_of, dec, tactics_apply))
	return row


## `identity` is {colour, badge} from Art.team_identity() — always drawn together here, since
## this is exactly the "two teams side by side" case art.gd's own rule is written for.
func _team_col(label_text: String, team: Array, analysis: Dictionary, identity: Dictionary,
		is_team_a: bool, id_of: Dictionary, dec: Dictionary, tactics_apply: bool) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)

	var tint: Color = identity["colour"]
	var header := Label.new()
	header.text = "%s  %s" % [identity["badge"], label_text]
	header.add_theme_color_override("font_color", tint)
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
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.13, 0.17)
	sb.border_color = tint
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 6; sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	panel.add_child(outer)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	outer.add_child(hbox)

	hbox.add_child(_portrait(m.species_id, m.species_name, Vector2(40, 40), tint))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var survived: bool = unit_stats.get("survived", true)
	var name_lbl := Label.new()
	name_lbl.text = "%s%s" % [m.species_name, ("" if survived else "  (fallen)")]
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.93) if survived else Color(0.55, 0.5, 0.5))
	info.add_child(name_lbl)

	var dmg_lbl := Label.new()
	var collision_tag := "  ⚠ shared with a same-species ally — tally split, see note below" if unit_stats.get("collision", false) else ""
	dmg_lbl.text = "dealt %d · took %d%s" % [int(unit_stats.get("dealt", 0)), int(unit_stats.get("taken", 0)), collision_tag]
	dmg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	dmg_lbl.add_theme_font_size_override("font_size", 12)
	dmg_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.7) if collision_tag == "" else Color(0.85, 0.65, 0.4))
	info.add_child(dmg_lbl)

	# Critical-event teaser — shown even collapsed, per UX_LEGIBILITY.md §7 item 2: the one line
	# of the decision log that matters most should never require a click to see.
	var teaser := _critical_teaser(decision_events)
	if teaser != "":
		var teaser_lbl := Label.new()
		teaser_lbl.text = teaser
		teaser_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		teaser_lbl.add_theme_font_size_override("font_size", 11)
		teaser_lbl.add_theme_color_override("font_color", Color(0.9, 0.6, 0.55))
		outer.add_child(teaser_lbl)

	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 6)
	details.visible = false

	var toggle := Button.new()
	toggle.text = "▸ Orders & decision log"
	toggle.flat = true
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.add_theme_font_size_override("font_size", 11)
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
			return [_summary_line("No standing orders yet — every monster is following its own nature.", Color(0.6, 0.6, 0.65))]

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
			Color(0.8, 0.8, 0.85) if source == "order" else Color(0.6, 0.6, 0.65)))
	return out


func _order_suffix(source: String, is_team_a: bool) -> String:
	if source == "order":
		return "— your order" if is_team_a else "— the rival's gameplan"
	return "— its nature"


func _summary_line(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", color)
	return l


## The decision log body: critical events always shown, standard shown once expanded (both are
## already inside the "Orders & decision log" toggle), minor collapsed under its own "+N more" —
## the third density lever from UX_LEGIBILITY.md §7. `rich` tells us whether these events carry a
## real `attribution` field (see _decision_events_by_id) or are a derived approximation.
func _decision_log_block(events: Array, rich: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var header := Label.new()
	header.text = "Decision log"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35))
	box.add_child(header)

	if events.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No decisions recorded for this fight." if rich else \
			"No intent data in this build yet — the tree AI (scripts/ai/monster_tree.gd) hasn't " + \
			"shipped, so there is nothing beyond the Orders Summary above to log here."
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty_lbl.add_theme_font_size_override("font_size", 11)
		empty_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
		box.add_child(empty_lbl)
		return box

	if not rich:
		var caveat := Label.new()
		caveat.text = "⚠ No ORDER / ITS NATURE / REACTED tag yet: the AI computes one on every decision, but the blackboard's log stores only the branch and the reason. Showing those."
		caveat.autowrap_mode = TextServer.AUTOWRAP_WORD
		caveat.add_theme_font_size_override("font_size", 10)
		caveat.add_theme_color_override("font_color", Color(0.6, 0.55, 0.4))
		box.add_child(caveat)

	var critical: Array = events.filter(func(e): return e.get("importance", "standard") == "critical")
	var standard: Array = events.filter(func(e): return e.get("importance", "standard") == "standard")
	var minor: Array = events.filter(func(e): return e.get("importance", "standard") == "minor")

	for e in critical:
		box.add_child(_decision_line(e, Color(0.95, 0.55, 0.5)))
	for e in standard:
		box.add_child(_decision_line(e, Color(0.8, 0.8, 0.85)))

	if not minor.is_empty():
		var minor_box := VBoxContainer.new()
		minor_box.visible = false
		var toggle := Button.new()
		toggle.text = "+%d more" % minor.size()
		toggle.flat = true
		toggle.focus_mode = Control.FOCUS_ALL
		toggle.add_theme_font_size_override("font_size", 10)
		toggle.pressed.connect(func():
			minor_box.visible = not minor_box.visible
			toggle.text = "Hide" if minor_box.visible else "+%d more" % minor.size()
		)
		box.add_child(toggle)
		box.add_child(minor_box)
		for e in minor:
			minor_box.add_child(_decision_line(e, Color(0.55, 0.55, 0.6)))

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
	l.add_theme_font_size_override("font_size", 11)
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
				by_id[uid2].append({
					"t": t, "label": intent, "reason": reason,
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


func _portrait(species_id: String, species_name: String, portrait_size: Vector2, tint: Color) -> Control:
	var tex := Art.creature_texture(species_id)
	if tex != null:
		var t := TextureRect.new()
		t.texture = tex
		t.custom_minimum_size = portrait_size
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		return t
	var panel := PanelContainer.new()
	panel.custom_minimum_size = portrait_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(tint.r, tint.g, tint.b, 0.18)
	sb.border_color = tint
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = species_name.substr(0, 2).to_upper()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", tint)
	lbl.add_theme_font_size_override("font_size", int(portrait_size.y * 0.4))
	panel.add_child(lbl)
	return panel


func _line(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
