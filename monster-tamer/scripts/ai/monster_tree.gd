## THE MONSTER TREE — per-monster decision-making, per docs/BUILD_CONTRACT.md §1 and
## docs/TACTICS_TREES.md. Stream B of the spatial rebuild.
##
## ⚠️ THE ONLY CONTRACT SURFACE IS `static func tick(ctx: Dictionary) -> Dictionary`. `spatial_sim.gd`
## loads this script with `ResourceLoader`/`load()` and calls `.call("tick", ctx)` — it never
## references a class name, so this file does not need (and does not rely on) `class_name` to be
## reachable. It is declared anyway for readability/tooling, matching this codebase's other leaf
## scripts (`Spatial`, `SpatialAi`, `Tactics`).
##
## ── WHY THIS IS NATIVE GDSCRIPT CONTROL FLOW, NOT A LITERAL `bt_node.gd` OBJECT GRAPH ───────────
## `scripts/ai/bt_*.gd` is shared, stable infrastructure — read, not changed, per the brief — but
## its `tick(ctx: Object) -> BTResult` shape does not fit `docs/BUILD_CONTRACT.md §1`'s
## `tick(ctx: Dictionary) -> Dictionary` verbatim: the contract wants an ACTION (desired_pos,
## target_id, move_name) back, and `BTResult` only carries status/path/reason. Reconciling the two
## would mean leaves writing their real decision into a side-channel (the blackboard) for this file
## to read back out after ticking a root `BTSelector` — plumbing with no behavioural payoff, since
## every selector/sequence property this codebase's own library exists for (reactive top-to-bottom
## re-evaluation every tick, so a higher branch pre-empts a lower one with zero interrupt
## machinery, RUNNING state that lives on the blackboard rather than a node instance) is reproduced
## here directly: every subtree below is a plain "first branch that doesn't fail wins" cascade,
## re-run from the top every tick, with all persistent state on `ctx.blackboard` — never on `self`
## (there is no `self`; every function here is `static`). This is the SAME semantics the library
## encodes as objects, written as functions because the contract wants Dictionaries. Flagged
## honestly in the report rather than silently deviating.
##
## ── SCOPE HONESTLY NOT COVERED, AND WHY ──────────────────────────────────────────────────────────
## - **Taunt** has no representation in the field engine today — `data/data.json`'s `fieldStatus`
##   table carries no "taunt" kind, and `spatial_sim.gd::_resolve_hit` never reads a move's
##   `tauntForce` flag. The taunt branches below are wired and dead until that lands — the moment
##   `unit.has_status("taunt")` can return true, the whole path lights up with no further changes.
## - **`threat_score` (docs/TACTICS_TREES.md §2.2)** needs a rolling per-unit damage-received log
##   that nothing in the engine tracks (`ctx` carries no combat history) — `targetPriority ==
##   "threat"` degrades to proximity ("nearest"), the same "flag the degrade, don't fake the
##   number" pattern `disengage`'s cover-seeking branch already uses in the source doc.
## - **Blocking Policy (§7)** cannot live in this file at all: detecting "an enemy body sits on my
##   path right now" requires the pathfinding/collision result, which is computed downstream of
##   this call in `spatial_sim.gd::_move_phase`/`_resolve_attack_target` and never surfaced back
##   into `ctx`. `spatial_sim.gd`'s own header comment confirms the always-bullThrough-with-
##   opportunistic-swings default already lives there, underneath whatever this file decides — so
##   §7 is already partially built, just not in this file, and not configurable by tactic yet. A
##   real finding for the report, not a shortcut.
## - **Ability Policy `holdBig`/`combo` (§6)** need an authored capstone/opener/payoff flag on move
##   data that does not exist (`CLAUDE.md`: "No ultimates removed"; no `comboRole` field ported) —
##   both degrade to `free` (empty `move_name`, `spatial_sim.gd`'s own strongest-ready-move
##   default) until that authoring lands.
## - **Guard's named charge** (`tactics.guardedAlly`) now HAS a producer — `deployment_board.gd`'s
##   `current_guard_targets()`, wired through `tactics_ui.gd::_on_board_changed()` into
##   `orders_a[m]["guardedAlly"]` (2026-08-04). **Formation's per-slot `home_point`** still has no
##   producer (no deployment UI writes it into `ctx.tactics`) and is read here as forward-compatible
##   plumbing, exactly like `markedUnit` was before scouting UI existed — degrades to its documented
##   fallback (this unit's own first-tick position, which in the current build IS its deploy/
##   formation station).
##
## Determinism: every random draw goes through `ctx.rng` (none currently needed — nothing here
## rolls dice yet), fixed child order (every cascade below is a straight-line if/elif/return, no
## Dictionary iteration whose order could vary), same ctx -> same output.
class_name MonsterTree
extends RefCounted

const Sp = preload("res://scripts/spatial.gd")
const StatusMathLib = preload("res://scripts/status_math.gd")   # HARD_CONTROL, for cleanse awareness
const DeriveLib = preload("res://scripts/derive.gd")            # field_mp_cost, to know a cleanse is affordable
const TacticsScript = preload("res://scripts/tactics.gd")

# ── tunables — ILLUSTRATIVE, per docs/TACTICS_TREES.md §11: "every constant named... is
# illustrative, not tuned"; the balance baseline is suspended project-wide (CLAUDE.md). Getting
# the BRANCH STRUCTURE right is this file's job, not these numbers. ─────────────────────────────
const LETHAL_RISK_FRAC := 0.18
const THREAT_MARGIN := 2.0
const ESCAPE_FLEE_DIST := 8.0

const STICKY_MIN := 2.5
const STICKY_MAX := 6.0

const FALLBACK_TRIGGER := 0.35
const DISENGAGE_TRIGGER := 0.22
const DWELL_MIN := 1.0
const DWELL_MAX := 3.0
const ALLY_CLUSTER_RADIUS := 22.0

## ⚠️ THE SIXTH AND SEVENTH SCALE BUGS. Both are DISTANCES written as bare numbers, authored for a
## 40x22 field and never scaled — a 14-unit flank arc on a 352-unit board is not a flank, it is a
## sidestep. `Spatial.GEOMETRY_SCALE` exists precisely so world distances stop being re-derived by
## hand; anything measured in world units here must carry it.
const HOLD_SLACK_MIN := 4.0 * Sp.GEOMETRY_SCALE
const HOLD_SLACK_MAX := 14.0 * Sp.GEOMETRY_SCALE
const PUSH_LEAD_MIN := 4.0
const PUSH_LEAD_MAX := 10.0
const WING_OFFSET := 14.0 * Sp.GEOMETRY_SCALE
const WING_TOLERANCE := 3.0 * Sp.GEOMETRY_SCALE
const GUARD_LEASH := 10.0
const INTERCEPT_RADIUS := 14.0


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# THE ONE CONTRACT ENTRY POINT — docs/BUILD_CONTRACT.md §1
# ═══════════════════════════════════════════════════════════════════════════════════════════════

static func tick(ctx: Dictionary) -> Dictionary:
	var unit = ctx["unit"]
	var self_pos: Vector2 = ctx["pos"]

	# ── ROOT §1: GATE — incapacitated, dead, or feared ──────────────────────────────────────────
	if unit.is_incapacitated() or unit.has_status("fear"):
		return _finish(ctx, "idle", self_pos, -1, "", "waiting it out",
			"%s can't act right now" % _unit_name(unit), "")

	var tactics: Dictionary = ctx["tactics"]
	# ⚠️ Reads the SAME default as `_mode_select`. Left on the literal "fightOn" it disagreed with
	# the mode selector the moment a per-kit default existed: a fragile monster would be given a
	# withdrawal mode by one function and denied its emergency bail-out by the other, purely
	# because two places spelled the default differently. One source, consulted twice.
	var when_hurt: String = str(tactics.get("whenHurt", _default_when_hurt(ctx)))

	# ── ROOT §1 / §8 #28: EMERGENCY DISENGAGE — the reflex, not a mode ──────────────────────────
	# ⚠️ `fight on` BEATS this override. The guard is exactly this one clause, per §1.1.
	if when_hurt != "fightOn":
		var threat := _threatening_enemies(ctx)
		if _about_to_die(ctx, threat):
			return _finish(ctx, "move", _flee_point(ctx, threat), -1, "", "bailing out",
				# ⚠️ Same attribution honesty as the withdrawal branches — "orders" only when there
				# were any. Fixed together because half-fixing an honesty bug leaves it a bug.
				("%s nearly died — broke off despite orders to survive" % _unit_name(unit)
					if _when_hurt_is_ordered(ctx)
					else "%s nearly died and broke off on its own" % _unit_name(unit)), "reacted")

	# ── ROOT §1: STANDING PLAN ───────────────────────────────────────────────────────────────────
	var tsel := _target_select(ctx)
	var mode := _mode_select(ctx)

	var out: Dictionary
	if mode == "fallback":
		out = _fallback_withdrawal(ctx, tsel)
	elif mode == "disengage":
		out = _disengage_withdrawal(ctx, tsel)
	else:
		out = _engage(ctx, tsel)

	# §10's worked example: a real target switch is usually the more meaningful "moment" than
	# whatever the positional subtree's own steady-state reason says, UNLESS something more urgent
	# (an override, attribution "reacted") already claimed the tick.
	if bool(tsel.get("changed", false)) and str(tsel.get("reason", "")) != "" \
			and str(out.get("attribution", "")) != "reacted":
		out["reason"] = str(tsel["reason"])
		out["attribution"] = str(tsel["attribution"])

	return out


static func _finish(ctx: Dictionary, action: String, desired_pos: Vector2, target_id: int,
		move_name: String, intent: String, reason: String, attribution: String) -> Dictionary:
	return {
		"action": action, "desired_pos": desired_pos, "target_id": target_id,
		"move_name": move_name, "intent": intent, "reason": reason, "attribution": attribution,
	}


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# §2 — TARGET SELECT. One shared cascade, six scoring modes, sticky/reassess commitment.
# ⚠️ Blackboard stores the TARGET UNIT (object identity), never a raw index — `ctx.enemies` is
# rebuilt fresh every tick via `_living()`, so a survivor's INDEX can shift as other units at
# lower indices die. Storing an index across ticks would silently point at the wrong monster.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

static func _target_select(ctx: Dictionary) -> Dictionary:
	var unit = ctx["unit"]
	var enemies: Array = ctx["enemies"]
	var bb: Dictionary = ctx["blackboard"]
	var tactics: Dictionary = ctx["tactics"]
	var now: float = float(ctx["now"])

	if enemies.is_empty():
		bb["target_unit"] = null
		return {"target_id": -1, "reason": "", "attribution": "", "changed": false}

	var prev_unit = bb.get("target_unit")
	var prev_idx: int = enemies.find(prev_unit) if prev_unit != null else -1

	# ── taunted — §8 override #1. Currently unreachable; see the file header. ──────────────────
	if unit.has_status("taunt"):
		var taunter_idx := _find_taunter(ctx)
		if taunter_idx != -1:
			var changed_t: bool = prev_idx != taunter_idx
			bb["target_unit"] = enemies[taunter_idx]
			bb["target_committed_until"] = now + 9999.0
			return {
				"target_id": taunter_idx,
				"reason": "%s is taunted by %s" % [_unit_name(unit), _unit_name(enemies[taunter_idx])],
				"attribution": "reacted", "changed": changed_t,
			}

	var explicit_priority: bool = tactics.has("targetPriority")
	var priority: String = str(tactics.get("targetPriority", ""))

	# ── marked — §1.2 override #1 lives here ────────────────────────────────────────────────────
	if priority == "manmark" or priority == "marked":
		var marked = tactics.get("markedUnit")
		var idx: int = (enemies.find(marked) if marked != null else -1)
		if idx != -1:
			var changed_m: bool = prev_idx != idx
			bb["target_unit"] = enemies[idx]
			bb["target_committed_until"] = now + 9999.0
			return {
				"target_id": idx, "reason": "%s is hunting its marked target" % _unit_name(unit),
				"attribution": "order", "changed": changed_m,
			}
		# marked unit dead/never scouted — fall through to the default scorer as the substitute.
		var scored_m := _default_score(ctx, "")
		var changed_mg: bool = prev_idx != scored_m["target_id"]
		bb["target_unit"] = enemies[scored_m["target_id"]]
		bb["target_committed_until"] = now + _sticky_hold(ctx)
		return {
			"target_id": scored_m["target_id"],
			"reason": "the marked target is down — %s reverts to no standing order" % _unit_name(unit),
			"attribution": "reacted", "changed": changed_mg,
		}

	# ── commitment: sticky (Focus-scaled hold) vs reassess every tick ───────────────────────────
	var commitment: String = str(tactics.get("commitment", ""))
	if commitment == "":
		commitment = "sticky" if _axis(ctx, ["focus"], 50.0) >= 50.0 else "reassess"

	# suspended (not consumed) while not ENGAGE, per §2's decorator note and §12's open item —
	# `bb["withdraw_mode"]` still holds the PREVIOUS tick's mode here, since `_mode_select` runs
	# after this function; that one-tick lag is the cheap, deterministic proxy this file uses.
	var was_withdrawing: bool = str(bb.get("withdraw_mode", "")) != ""
	var held_until: float = float(bb.get("target_committed_until", -1.0))

	if commitment == "sticky" and prev_idx != -1 and was_withdrawing:
		return {"target_id": prev_idx, "reason": "", "attribution": "", "changed": false}
	if commitment == "sticky" and prev_idx != -1 and now < held_until:
		return {"target_id": prev_idx, "reason": "", "attribution": "", "changed": false}

	var scored := _default_score(ctx, priority)
	var changed: bool = prev_idx != int(scored["target_id"])
	bb["target_unit"] = enemies[scored["target_id"]]
	bb["target_committed_until"] = now + _sticky_hold(ctx)

	var reason := ""
	var attribution := ""
	if changed:
		reason = "%s switched target → %s (%s)" % [
			_unit_name(unit), _unit_name(enemies[scored["target_id"]]), _priority_label(priority)]
		attribution = "order" if explicit_priority else "nature"
	return {"target_id": scored["target_id"], "reason": reason, "attribution": attribution, "changed": changed}


## §2.1's six scoring modes. `"threat"` degrades to proximity — see the file header.
static func _default_score(ctx: Dictionary, priority: String) -> Dictionary:
	var enemies: Array = ctx["enemies"]
	var positions: Array = ctx["enemy_positions"]
	var self_pos: Vector2 = ctx["pos"]

	var best_i := 0
	var best_score := -INF
	for i in range(enemies.size()):
		var e = enemies[i]
		var epos: Vector2 = positions[i]
		var dist: float = self_pos.distance_to(epos)
		var score: float
		match priority:
			"nearest":
				score = -dist
			"threat":
				score = -dist  # degrade — no damage-received log wired into ctx yet, see header
			"casters":
				score = maxf(float(e.stats.get("INT", 0.0)), float(e.stats.get("WIS", 0.0))) - dist * 0.001
			"tanks":
				score = float(e.stats.get("CON", 0.0)) - dist * 0.001
			_:
				score = -(e.hp_frac() * 1000.0) - dist * 0.01
		if score > best_score:
			best_score = score
			best_i = i
	return {"target_id": best_i}


static func _priority_label(priority: String) -> String:
	var info: Dictionary = TacticsScript.info_by_id(TacticsScript.TARGET_PRIORITY_INFO, priority)
	if not info.is_empty():
		return "your order: %s" % str(info.get("name", priority))
	match priority:
		"nearest":
			return "your order: nearest"
		"threat":
			return "your order: threat"
		_:
			return "your order: %s" % priority


static func _find_taunter(ctx: Dictionary) -> int:
	# No "taunt" kind exists in `data/data.json`'s fieldStatus table and nothing in
	# `spatial_sim.gd` ever applies one — this is unreachable today. Kept so the day taunt is
	# wired in, only the `unit.has_status("taunt")` predicate above needs to start returning true.
	var enemies: Array = ctx["enemies"]
	var unit = ctx["unit"]
	for s in unit.statuses:
		if str(s.get("kind", "")) != "taunt":
			continue
		for i in range(enemies.size()):
			if str(enemies[i].species_name) == str(s.get("from", "")):
				return i
	return -1


static func _sticky_hold(ctx: Dictionary) -> float:
	return lerpf(STICKY_MIN, STICKY_MAX, _axis(ctx, ["focus"], 50.0) / 100.0)


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# §5.1 — MODE SELECT. Chooses ENGAGE | fallback-withdrawal | disengage-withdrawal.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## ⚠️ RETREAT WAS BUILT AND UNREACHABLE — the same shape as flanking. `fallback` and `disengage`
## are fully implemented below, but `whenHurt` defaulted to the literal `"fightOn"`, so unless a
## player opened the tactics screen and changed it, no monster in any fight had ever withdrawn
## from anything. Three reactive systems existed on paper and none of them could fire.
##
## ⚠️ AND `AUTOBATTLER_DESIGN.md` #14 IS NOT BEING VIOLATED: *"'When hurt' is a tactic, never
## automatic."* It still is — the player's setting wins outright, and this is only consulted when
## they have not chosen. What changes is the DEFAULT, which was silently the most reckless of the
## three options for every creature ever generated. A wall that fights to the last point of HP is
## a wall doing its job; a glass cannon doing the same is not obeying an order, it is a default
## nobody picked.
##
## Read off the kit, like the positional default:
##   fragile + long reach  -> disengage. Its whole value is being alive at range.
##   fragile + short reach -> fallBack.  It has to be close, so it buys distance and returns.
##   tough                 -> fightOn.   Absorbing damage IS its contribution.
## Steps out from behind cover when it is the unit's OWN line that is blocked. Returns {} when the
## line is already clear (the normal case) or when the unit is still closing — a unit walking
## toward its target will clear most blocks for free as it moves, and sidestepping while it is
## still out of range would be a detour to fix a problem that is about to solve itself.
## `stationary` relaxes the in-reach gate: a unit that has stopped moving has no walk left to
## clear the block for it, so it must reposition at any distance or it stands there permanently.
static func _clear_line_override(ctx: Dictionary, tsel: Dictionary, stationary: bool = false) -> Dictionary:
	var obstacles: Array = ctx["obstacles"]
	if obstacles.is_empty():
		return {}
	var tid := int(tsel.get("target_id", -1))
	var enemies: Array = ctx["enemies"]
	if tid < 0 or tid >= enemies.size():
		return {}
	var self_pos: Vector2 = ctx["pos"]
	var tpos: Vector2 = ctx["enemy_positions"][tid]
	var reach := _reach(ctx)
	if not stationary and self_pos.distance_to(tpos) > reach:
		return {}                       # still closing — the walk will clear it
	if not bool(Sp.cover_between(self_pos, tpos, obstacles)["blocked"]):
		return {}                       # nothing in the way

	var spot := _clear_line_point(ctx, tpos, reach if not stationary else maxf(reach, self_pos.distance_to(tpos)))
	if spot.distance_to(self_pos) < 0.01:
		# ⚠️ Nowhere sampled works. Say so rather than pretending — the unit stays put, and the
		# decision log carries a sentence the player can act on next time they deploy.
		return _finish(ctx, "idle", self_pos, tid, "", "no shot",
			"%s has no shot at %s — cover is in the way and there is nowhere better to stand"
				% [_unit_name(ctx["unit"]), _unit_name(enemies[tid])], "nature")
	return _finish(ctx, "move", spot, tid, "", "clearing its line",
		"%s stepped out from behind cover to get a shot at %s"
			% [_unit_name(ctx["unit"]), _unit_name(enemies[tid])], "nature")


## PEEL THRESHOLDS. An ally is "in trouble" when it is badly hurt AND something is standing on it.
## ⚠️ Both conditions are required. Hurt alone is not a peel — a wall at 40% is simply working —
## and an enemy nearby alone is not either, or every unit would peel for every other unit on
## contact and the line would dissolve into mutual babysitting.
const PEEL_ALLY_HP := 0.45
const PEEL_MAX_HELPERS := 1        ## one peeler per victim; two is the line collapsing, not peeling
const PEEL_SELF_HP := 0.5          ## a unit already in trouble cannot save anyone


## ⚠️ THE THIRD REACTION, AND THE ONE THAT WAS GENUINELY MISSING. Retreat and guard both existed
## and were merely unreachable; nothing in the tree ever noticed an ALLY was in danger. A monster
## would walk its flank arc past a teammate being killed, which is exactly the failure
## `AUTOBATTLER_DESIGN.md` §0 quotes from TFM2's complaint thread — "blindly following programmed
## strategies" — and the bar it sets is not "is the AI clever" but "can the player tell why it did
## that, and was it their own order?". So this emits a reason naming the ally and the threat.
##
## Returns {} when there is nothing to peel for, which is the normal case.
static func _peel_override(ctx: Dictionary) -> Dictionary:
	var unit = ctx["unit"]
	if unit.hp_frac() < PEEL_SELF_HP:
		return {}                       # save yourself first; a corpse peels for nobody
	var self_pos: Vector2 = ctx["pos"]
	var allies: Array = ctx["allies"]
	var ally_positions: Array = ctx["ally_positions"]
	var enemies: Array = ctx["enemies"]
	var enemy_positions: Array = ctx["enemy_positions"]
	var reach := _reach(ctx)

	var best_ally := -1
	var best_enemy := -1
	var best_d := INF
	for i in range(allies.size()):
		var a = allies[i]
		if not a.alive or a.hp_frac() > PEEL_ALLY_HP:
			continue
		var apos: Vector2 = ally_positions[i]
		# Who is on them? Nearest living enemy within ITS OWN reach of the ally — an enemy that
		# cannot actually hit them is not a threat to peel from.
		for j in range(enemies.size()):
			var e = enemies[j]
			if not e.alive:
				continue
			var epos: Vector2 = enemy_positions[j]
			if epos.distance_to(apos) > _unit_best_reach(e):
				continue
			# ⚠️ Am I the CLOSEST available helper? Without this every short-reach ally converges on
			# the same victim and the formation dissolves — the blob, re-created by kindness.
			var closer := 0
			for k in range(allies.size()):
				var h = allies[k]
				if not h.alive or h == a or h.hp_frac() < PEEL_SELF_HP:
					continue
				if ally_positions[k].distance_to(epos) < self_pos.distance_to(epos):
					closer += 1
			if closer >= PEEL_MAX_HELPERS:
				continue
			var d: float = self_pos.distance_to(epos)
			if d < best_d:
				best_d = d
				best_ally = i
				best_enemy = j
	if best_enemy == -1:
		return {}

	var epos2: Vector2 = enemy_positions[best_enemy]
	var reason := "%s broke off to protect %s from %s" % [
		_unit_name(unit), _unit_name(allies[best_ally]), _unit_name(enemies[best_enemy])]
	if best_d <= reach:
		return _finish(ctx, "attack", epos2, best_enemy, _pick_move_name(ctx, best_enemy),
			"peeling", reason, "reacted")
	# Stand between the threat and the charge, not on top of the threat — a body in the way is the
	# whole point of a peel, and `_separate()` makes that physically real.
	var toward := (self_pos - epos2).normalized()
	return _finish(ctx, "move", epos2 + toward * maxf(0.5, reach * 0.9), best_enemy, "",
		"peeling", reason, "reacted")


## ⚠️ DID THE PLAYER ACTUALLY ORDER THIS? Both withdrawal branches hard-coded "your order:" into
## their reason text and "order" into their attribution — correct while `whenHurt` could only ever
## be set by hand, and a LIE the moment a default started supplying it. The first measured run of
## the new default printed *"Balaenix fell back (your order: When hurt → Fall back)"* for an order
## no player had given.
##
## That matters more here than in most games. `AUTOBATTLER_DESIGN.md` §0 sets the bar as *"can the
## player tell why it did that, and was it their own order?"* — attribution IS the feature. A
## decision log that credits the player for the AI's own judgement destroys the one thing the
## player uses to learn whether their read was right.
static func _when_hurt_is_ordered(ctx: Dictionary) -> bool:
	return (ctx["tactics"] as Dictionary).has("whenHurt")


static func _default_when_hurt(ctx: Dictionary) -> String:
	var unit = ctx["unit"]
	var reach := _unit_best_reach(unit)
	# ⚠️ TOUGHNESS RELATIVE TO THE TEAM, not an absolute HP number — the same correction the wings
	# threshold needed after `dex >= 120` turned out to be unreachable against DEX 19-54 monsters.
	# Stat magnitudes move by an order of magnitude across the eleven leagues; ranks do not.
	var tougher := 0
	var counted := 0
	for a in ctx["allies"]:
		if not a.alive:
			continue
		counted += 1
		if float(a.max_hp) > float(unit.max_hp):
			tougher += 1
	var is_fragile: bool = counted >= 2 and tougher >= int(round(float(counted) * 0.6))
	if not is_fragile:
		return "fightOn"
	return "disengage" if reach >= float(Sp.CHANNEL_RANGE.get("ranged", 70.0)) * 0.70 else "fallBack"


static func _mode_select(ctx: Dictionary) -> String:
	var bb: Dictionary = ctx["blackboard"]
	var tactics: Dictionary = ctx["tactics"]
	var when_hurt: String = str(tactics.get("whenHurt", _default_when_hurt(ctx)))
	var hp_frac: float = ctx["unit"].hp_frac()
	var now: float = float(ctx["now"])
	var prev_mode: String = str(bb.get("withdraw_mode", ""))
	var mode := "engage"

	if when_hurt == "fallBack":
		var still: bool = prev_mode == "fallback" and not _fallback_exit_ready(ctx)
		if hp_frac <= FALLBACK_TRIGGER or still:
			mode = "fallback"
	elif when_hurt == "disengage":
		var still2: bool = prev_mode == "disengage" and not _disengage_exit_ready(ctx)
		if hp_frac <= DISENGAGE_TRIGGER or still2:
			mode = "disengage"
	# `fightOn` (or anything unrecognised): `mode` stays "engage" — no withdrawal branch exists to
	# fall into at all, the second, structural reinforcement of §1.1's guard.

	if mode != "engage" and prev_mode != mode:
		if mode == "fallback":
			bb["fallback_committed_until"] = now + _min_dwell_fallback(ctx)
		else:
			bb["disengage_committed_until"] = now + _min_dwell_disengage(ctx)

	bb["_just_exited_withdraw"] = (prev_mode != "" and mode == "engage")
	bb["withdraw_mode"] = ("" if mode == "engage" else mode)
	return mode


static func _safe_hp_frac(ctx: Dictionary) -> float:
	return lerpf(0.65, 0.40, _axis(ctx, ["nerve"], 50.0) / 100.0)


static func _disengage_heal_frac(ctx: Dictionary) -> float:
	return lerpf(0.90, 0.60, _axis(ctx, ["nerve"], 50.0) / 100.0)


static func _min_dwell_fallback(ctx: Dictionary) -> float:
	return lerpf(DWELL_MAX, DWELL_MIN, _axis(ctx, ["nerve"], 50.0) / 100.0)


static func _min_dwell_disengage(ctx: Dictionary) -> float:
	return _min_dwell_fallback(ctx) * 1.6


static func _ally_nearby(ctx: Dictionary, radius: float) -> bool:
	var self_pos: Vector2 = ctx["pos"]
	for p in ctx["ally_positions"]:
		if self_pos.distance_to(p as Vector2) <= radius:
			return true
	return false


static func _fallback_exit_ready(ctx: Dictionary) -> bool:
	var bb: Dictionary = ctx["blackboard"]
	var committed_until: float = float(bb.get("fallback_committed_until", 0.0))
	return float(ctx["now"]) >= committed_until \
		and ctx["unit"].hp_frac() >= _safe_hp_frac(ctx) \
		and _ally_nearby(ctx, ALLY_CLUSTER_RADIUS)


static func _disengage_exit_ready(ctx: Dictionary) -> bool:
	var bb: Dictionary = ctx["blackboard"]
	var committed_until: float = float(bb.get("disengage_committed_until", 0.0))
	return float(ctx["now"]) >= committed_until \
		and ctx["unit"].hp_frac() >= _disengage_heal_frac(ctx)


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# §5.2 / §5.3 — the two withdrawal subtrees.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

static func _fallback_withdrawal(ctx: Dictionary, tsel: Dictionary) -> Dictionary:
	var unit = ctx["unit"]
	var self_pos: Vector2 = ctx["pos"]
	var allies: Array = ctx["allies"]
	var ally_positions: Array = ctx["ally_positions"]

	var dest: Vector2 = self_pos
	if not allies.is_empty():
		dest = _nearest_point(self_pos, ally_positions)

	# ⚠️ FALL BACK *THROUGH* COVER, NOT PAST IT. This branch retreats toward the nearest ally,
	# which is right — falling back is rejoining the line, not fleeing the field — but it never
	# consulted the terrain, and MEASURED it was the dominant withdrawal branch (179 of 188
	# withdrawing moves). So every cover-seeking measurement read ~0% no matter what
	# `_break_los_point` did, because the branch that does most of the withdrawing never called it.
	#
	# The rally point still governs WHERE; cover only chooses among ways of getting there. A unit
	# that broke line of sight while retreating to its allies has done both jobs at once, and one
	# that cannot simply retreats as before.
	var threats := _threatening_enemies(ctx)
	if not threats.is_empty() and not (ctx["obstacles"] as Array).is_empty():
		var sheltered := _sheltered_step(ctx, dest, threats)
		if sheltered != Vector2.INF:
			dest = sheltered

	var target_id := int(tsel.get("target_id", -1))
	var action := "move"
	if target_id != -1 and target_id < ctx["enemy_positions"].size():
		var tpos: Vector2 = ctx["enemy_positions"][target_id]
		if self_pos.distance_to(tpos) <= _reach(ctx):
			action = "attack"  # opportunistic only — never turns the retreat vector off, never chases

	var nerve := int(round(_axis(ctx, ["nerve"], 50.0)))
	return _finish(ctx, action, dest, target_id, "", "falling back",
		("%s fell back (your order: When hurt → Fall back; Nerve %d)" % [_unit_name(unit), nerve]
			if _when_hurt_is_ordered(ctx)
			else "%s fell back — it is fragile and stays alive by giving ground (Nerve %d)"
				% [_unit_name(unit), nerve]),
		("order" if _when_hurt_is_ordered(ctx) else "nature"))


static func _disengage_withdrawal(ctx: Dictionary, tsel: Dictionary) -> Dictionary:
	var unit = ctx["unit"]
	var self_pos: Vector2 = ctx["pos"]

	# ⚠️ Cover-seeking (§5.3's first branch) depends on unbuilt infra — no queryable "break LOS"
	# cover point and no cast-interrupt-on-LOS-break exist in this engine yet
	# (docs/TACTICS_TREES.md §12). Degrades to the second branch unconditionally, exactly as that
	# document specifies for this exact dependency.
	var away: Vector2
	var threats := _threatening_enemies(ctx)
	if not threats.is_empty():
		away = _flee_point(ctx, threats)
	else:
		var centroid := _living_centroid(ctx)
		var dir := self_pos - centroid
		if dir.length() < 0.01:
			dir = Vector2(1, 0)
		away = self_pos + dir.normalized() * ESCAPE_FLEE_DIST

	return _finish(ctx, "move", away, -1, "", "breaking off",
		("%s broke off (your order: When hurt → Disengage)" % _unit_name(unit)
			if _when_hurt_is_ordered(ctx)
			else "%s broke off — a long-reach body has no business in a scrum" % _unit_name(unit)),
		("order" if _when_hurt_is_ordered(ctx) else "nature"))


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# §1 STANDING PLAN / ENGAGE — installs one of the five Positional Intent subtrees (§3).
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## ⚠️ CLEANSE AWARENESS — the counter-play to hard control, which nothing used to ask for.
##
## The pool authors THREE cleanse abilities (Clarity, Vital Surge, Providence), the engine applies
## them, and `status_math.gd` even grants a cleansed unit brief immunity so a chain cannot instantly
## re-land. `tactics.gd` writes counter-reads telling the player to *"bring cleanse and healing"*.
## ⚠️ And nothing in the AI had ever heard of it — `grep cleanse` over this file and `spatial_ai.gd`
## returned NOTHING. A Mender holding Clarity cast it whenever the generic strongest-ready-move
## scorer happened to rank it, never because an ally was stunned.
##
## ⚠️ NO PLAYER KNOB, BY DESIGN (studio owner's call): it is automatic whenever the creature brought
## a cleanse to the fight. The decision lives at the LOADOUT level — do I train a cleanser? — which
## is the meta-game feeding the fight, exactly as `CLAUDE.md`'s vision asks. A per-fight toggle
## would move that decision to the wrong screen.
static func _has_hard_control(u) -> bool:
	for st in u.statuses:
		if StatusMathLib.HARD_CONTROL.has(st["kind"]):
			return true
	return false


## A ready cleanse in this unit's own moveset, or "" if it has none / cannot pay / is on cooldown.
## ⚠️ Silence blocks casting entirely, and silence is ITSELF hard control — a silenced cleanser
## cannot cleanse itself out, which is the intended trap rather than an oversight.
static func _ready_cleanse_name(ctx: Dictionary) -> String:
	var unit = ctx["unit"]
	if unit.has_status("silence"):
		return ""
	for mv in unit.moveset:
		var fx = mv.get("effects")
		if not (fx is Dictionary) or not fx.get("cleanse", false):
			continue
		var nm: String = str(mv.get("name", ""))
		if float(unit.cooldowns.get(nm, 0.0)) > 0.0:
			continue
		if float(unit.mp) < DeriveLib.field_mp_cost(mv):
			continue
		return nm
	return ""


## Fires when this unit carries a ready cleanse AND somebody on its side is hard-controlled.
## Returns {} when there is nothing to answer, so the normal plan proceeds untouched.
##
## ⚠️ Sits BELOW the urgent overrides and ABOVE the positional subtrees: a cleanse is a reaction to
## the fight, but it must never outrank "you are about to die" or a taunt. `attribution` is
## "reacted" because the player did not order this tick — they ordered the LOADOUT that made it
## possible, which the report screen should credit as the read it was.
static func _cleanse_override(ctx: Dictionary, tsel: Dictionary) -> Dictionary:
	var name_: String = _ready_cleanse_name(ctx)
	if name_ == "":
		return {}

	var unit = ctx["unit"]
	var who := ""
	if _has_hard_control(unit):
		who = "itself"
	else:
		for a in ctx["allies"]:
			if _has_hard_control(a):
				who = _unit_name(a)
				break
	if who == "":
		return {}

	# Keep the enemy target_id the plan already chose — the sim redirects an ally/self-target move
	# to the right friendly unit in `_resolve_single_target`, which is now cleanse-aware.
	var tid := int(tsel.get("target_id", -1))
	var pos: Vector2 = ctx["pos"]
	if tid >= 0 and tid < ctx["enemy_positions"].size():
		pos = ctx["enemy_positions"][tid]
	return {
		"action": "attack", "desired_pos": pos, "target_id": tid, "move_name": name_,
		"intent": "cleansing",
		"reason": "%s is breaking the hold on %s" % [_unit_name(unit), who],
		"attribution": "reacted",
	}


## ⚠️ THE ENGAGEMENT GATE — "can I act? no → make it so I can", BEFORE any positional preference.
##
## ⚠️ THIS FIXED A FIGHT THAT COULD NOT END. Measured: a 3v3 ran the full 180s MAX_DURATION twice
## with ZERO deaths, both draws, the closest gap between the two sides pinned at 33.1 units for
## every one of 1801 ticks — exactly `Spatial.DEPLOY_SEPARATION`. Neither side ever moved.
##
## Cause: `_default_positional_intent()` returns "hold" below aggression 66, default aggression is
## 50, and `_positional_hold` anchors to `home_point` — the spawn point. So with no explicit order
## BOTH TEAMS STOOD AT SPAWN, 33.1 apart, while every weapon in the game reaches 3-11. Nobody could
## hit anybody and nothing in the tree was responsible for fixing that.
##
## ⚠️ WHY IT WENT UNCAUGHT: `push`, `wings` and `dive` each close as a SIDE EFFECT of their own
## logic, and every probe written so far passed an explicit intent. Engagement was incidental to
## three subtrees rather than owned by the root — so the two that didn't implement it (`hold`,
## `guard`) were silently broken, and the DEFAULT path — the one every real fight takes, since no
## UI sets `positionalIntent` yet — was the broken one.
##
## The gate sits BELOW the urgent overrides on purpose: a standing order stays sovereign (§1.1's
## `fight on` rule), and this closes only to the range at which the unit's orders become
## EXECUTABLE — it is not a charge. A unit told to hold a flank closes to ITS reach, not the
## enemy's face, and then its positional subtree takes over normally.
static func _engagement_gate(ctx: Dictionary, tsel: Dictionary) -> Dictionary:
	var tid := int(tsel.get("target_id", -1))
	var enemies: Array = ctx["enemies"]
	if tid < 0 or tid >= enemies.size():
		return {}   # no target at all — the positional subtrees own that case

	var self_pos: Vector2 = ctx["pos"]
	var target_pos: Vector2 = ctx["enemy_positions"][tid]
	var reach := _reach(ctx)
	var gap := self_pos.distance_to(target_pos)
	if gap <= reach:
		return {}   # already able to act — let the positional subtree decide how to fight

	# Close to just inside reach, never onto the target's own position: stand where the weapon
	# works, which is exactly what `Spatial.reach_of` means by taking the SHORTER of best weapon
	# and class basic.
	var stand_off: float = maxf(0.5, reach * 0.9)
	var toward := (self_pos - target_pos).normalized()
	var desired := target_pos + toward * stand_off
	return {
		"action": "move", "desired_pos": desired, "target_id": tid, "move_name": "",
		"intent": "closing",
		"reason": "%s is out of range — closing to where it can fight" % _unit_name(ctx["unit"]),
		"attribution": "nature",
	}


static func _engage(ctx: Dictionary, tsel: Dictionary) -> Dictionary:
	var bb: Dictionary = ctx["blackboard"]
	var tactics: Dictionary = ctx["tactics"]
	var explicit_intent: bool = tactics.has("positionalIntent")
	var intent_id: String = str(tactics.get("positionalIntent", ""))
	if intent_id == "":
		intent_id = _default_positional_intent(ctx)

	# ⚠️ Cleanse BEFORE the engagement gate. Breaking a stun on an ally is worth more than
	# shuffling into weapon range, and a cleanse has its own reach — a unit that stopped to close
	# the gap first would arrive after the control had already expired.
	var cleanse := _cleanse_override(ctx, tsel)
	if not cleanse.is_empty():
		return cleanse

	# PEEL — protecting an ally who is being cut down. Sits below cleanse (breaking control is
	# still worth more) and above the positional branches, because a unit that walks its planned
	# arc while a teammate dies behind it is doing the thing TFM2's complaint thread names: acting
	# on a plan the situation has already overtaken.
	var peel := _peel_override(ctx)
	if not peel.is_empty():
		return peel

	# ⚠️ CLEAR-YOUR-LINE IS RETIRED, AND THE REASON IS THAT THE RULE IT SERVED IS GONE.
	# It existed because a blocked line made a shot IMPOSSIBLE, so a unit behind cover could not
	# fight and had to step out. Cover is now a heavy accuracy DEBUFF rather than an on/off switch
	# (`Sp.COVER_BLOCK_ACC`, per `SPATIAL_COMBAT_DESIGN.md` §2), so there is no longer any such
	# thing as a shot that cover forbids.
	#
	# ⚠️ LEAVING IT IN WAS ACTIVELY HARMFUL AND MEASURED AS SUCH: with shots allowed through cover
	# but the AI still fleeing it, units optimised against a deleted rule — `four_pillar` ranged
	# kits sat at ZERO shelter across 522 threat-instances while chance alone would have given 34%.
	# An override that chases a condition the sim no longer applies is worse than no override.
	#
	# The behaviour survives where it is still correct: `_engagement_gate` closes a unit that
	# genuinely cannot reach, and the withdrawal branches still seek to BREAK line of sight, where
	# refusing to fight is the entire point.

	# ⚠️ THE GATE USED TO RUN *BEFORE* THE BRANCH, AND THAT IS WHY NOTHING EVER FLANKED. It closes
	# toward the TARGET'S OWN POSITION, so a unit whose intent was `wings` walked straight at the
	# enemy until it was already inside reach — and only then began its arc, by which point the
	# arc had nothing left to buy. Every positional intent collapsed into "advance in a line", and
	# the fight used 30% of the arena no matter how large the arena was made.
	#
	# The gate's PURPOSE is still right and is preserved: it exists because `hold` and `guard`
	# never closed at all, leaving both teams stood at spawn for 1801 ticks. So the order is now:
	# let the branch state where it wants to stand, and gate only if it produced no way to get
	# there. A branch that returns a MOVE is already closing — in its own shape.
	var out: Dictionary
	match intent_id:
		"push":
			out = _positional_push(ctx, tsel)
		"wings":
			out = _positional_wings(ctx, tsel)
		"dive":
			out = _positional_dive(ctx, tsel)
		"guard":
			out = _positional_guard(ctx, tsel)
		"shelter":
			out = _positional_shelter(ctx, tsel)
		_:
			out = _positional_hold(ctx, tsel)

	# ⚠️ THE GATE, NOW AS A BACKSTOP RATHER THAN AN OVERRIDE. Only a branch that is NOT moving can
	# be stranded out of range — a moving branch is closing under its own plan and must be left
	# alone, or we are back to marching in a line. This is the check that keeps `hold` and `guard`
	# from re-creating the 1801-tick standoff.
	# ⚠️ THE GATE FIRES WHEN THE BRANCH IS NOT CLOSING THE DISTANCE — NOT WHEN IT IS NOT "MOVING".
	# Gating on `action != "move"` was WRONG and shipped a regression the studio owner caught by
	# watching: `hold` returns action "move" toward its own home point, so it was exempt, and a
	# long-reach kit therefore held its DEPLOY position 303 units from the enemy with a 70-97 unit
	# reach. Corvaan and Larkessa never moved for an entire fight.
	#
	# That is the exact failure `_engagement_gate`'s own comment already documents — "BOTH TEAMS
	# STOOD AT SPAWN... Nobody could reach anybody" — reintroduced for one branch because I tested
	# the wrong property. A destination is only closing if it is nearer the target than here is.
	var here2: Vector2 = ctx["pos"]
	var closing := false
	var tid2 := int(tsel.get("target_id", -1))
	if tid2 >= 0 and tid2 < (ctx["enemies"] as Array).size():
		var tp2: Vector2 = ctx["enemy_positions"][tid2]
		var want2: Vector2 = out.get("desired_pos", here2)
		closing = want2.distance_to(tp2) < here2.distance_to(tp2) - 0.5
	if not closing:
		var gate := _engagement_gate(ctx, tsel)
		if not gate.is_empty():
			return gate

	# ⚠️ AND THE SAME BACKSTOP FOR A BLOCKED LINE — BUT GATED ON GOING NOWHERE, NOT ON THE ACTION
	# FIELD. MEASURED twice: on the authored four-wall arena, units with a blocked line idled 67%
	# of ticks (against 41% on the old scatter — big deliberate cover blocks more lines than small
	# scattered cover does), and 439 of those 604 ticks were `returning to post`.
	#
	# `hold` returns action "move" toward its home point, so an `action != "move"` test skipped it
	# entirely — and a unit ALREADY AT its post is "moving" to where it is standing. The honest
	# test is whether the branch's desired position is anywhere other than here.
	#
	# A unit holding a post it cannot shoot from is not holding ground, it is standing still: the
	# position has already failed at the only thing a post is for.
	var here: Vector2 = ctx["pos"]
	var going_nowhere: bool = (out.get("desired_pos", here) as Vector2).distance_to(here) < 1.0
	if going_nowhere:
		var unblock := _clear_line_override(ctx, tsel, true)
		if not unblock.is_empty():
			return unblock

	if str(out.get("attribution", "")) == "":
		out["attribution"] = ("order" if explicit_intent else "nature")

	if bool(bb.get("_just_exited_withdraw", false)):
		out["intent"] = "re-engaging"
		out["reason"] = "%s steadied up and is back in the fight" % _unit_name(ctx["unit"])
		out["attribution"] = "reacted"

	return out


## §9 Aggression row: high Aggression defaults toward push (dive/wings/guard need extra context —
## an explicit order for guard's charge, or are simply a stronger commitment than a bare default
## should make — so only push/hold are reachable as DEFAULTS; the other three are order-only).
## ⚠️ THIS USED TO RETURN ONE OF TWO ANSWERS FOR EVERY UNIT ON THE FIELD, AND THAT IS WHY NOBODY
## EVER FLANKED. `wings` and `dive` were deliberately order-only, so a team with no explicit
## orders had five monsters running the same branch — and since `personality` is still a stub
## (`spatial_sim.gd:_personality_of` returns {}), aggression was 50 for everyone, so all ten units
## defaulted to `hold` and then closed anyway through the engagement gate. Ten units walking in a
## straight line at each other was not an AI that had decided to; it was an AI with one option.
##
## A team's default should be a FORMATION OF ROLES, not one behaviour repeated five times — and
## the role each kit wants is exactly `CLAUDE.md`'s open "kit doctrine" axis: *what KIND of fight
## does this kit want*. Derived here from the two facts the sim already knows about a unit:
##
##   long reach   -> HOLD.  Ground IS its advantage; walking forward throws that away.
##   fast + short -> WINGS. It can pay the cost of the arc and arrive with the line.
##   otherwise    -> PUSH.  A slow short-reach body has nothing to gain by going the long way.
##
## ⚠️ AN EXPLICIT ORDER STILL WINS — this is only consulted when the player has not said. And it
## is DETERMINISTIC (no rng, no unit index), so it cannot desync the sim and cannot change between
## two replays of the same fight.
## ⚠️ WHEN IS COVER WORTH WANTING? Symmetric cover is worth nothing — a blocking piece costs both
## sides the same accuracy, so standing behind one is a wash and no unit should prefer it. That is
## why the AI measured as AVOIDING cover: it was correctly refusing a neutral trade.
##
## Cover becomes profitable only where the trade stops being even, and there are exactly two such
## cases that need no new machinery because the sim already knows both:
##
##   OUTNUMBERED — three enemies shooting you while you shoot one makes a symmetric penalty a 3:1
##                 trade in your favour. This is why real formations put the weak side behind
##                 something, and it is legible in one sentence.
##   SUPPORT     — a kit whose moves target ALLIES pays nothing for cover between it and the
##                 enemy. It is the classic healer-behind-a-pillar, it costs us nothing to build,
##                 and it gives WIS/CHA kits a spatial identity `CLAUDE.md` notes they lack —
##                 today 18 classes differ in exactly one way.
##
## ⚠️ Deliberately NOT a universal "seek cover" drive. A duelling melee kit gains nothing from
## cover and should not want it; making every unit hug a wall would replace one wrong behaviour
## with another.
static func _cover_is_profitable(ctx: Dictionary) -> bool:
	if (ctx["obstacles"] as Array).is_empty():
		return false
	if _is_support_kit(ctx["unit"]):
		return true
	return _threatening_enemies(ctx).size() >= 2


## A kit is "support" when most of what it can do points at its own side. Counted from the moveset
## rather than from a class name, so it stays true for any future roster or reclassification.
static func _is_support_kit(u) -> bool:
	var friendly := 0
	var hostile := 0
	for mv in u.moveset:
		if str(mv.get("target", "enemy")) in ["ally", "team", "self"]:
			friendly += 1
		else:
			hostile += 1
	return friendly > hostile


## §3.6 SHELTER — stand where the incoming fire is worst for the ATTACKER. Reachable as a default
## when `_cover_is_profitable`, and as an explicit order.
static func _positional_shelter(ctx: Dictionary, tsel: Dictionary) -> Dictionary:
	var unit = ctx["unit"]
	var self_pos: Vector2 = ctx["pos"]
	var threats := _threatening_enemies(ctx)
	if threats.is_empty():
		# Nothing shooting at us — shelter has nothing to shelter FROM, so behave as hold and say so.
		var out := _positional_hold(ctx, tsel)
		out["intent"] = "holding position"
		out["reason"] = "%s has nothing to take cover from yet" % _unit_name(unit)
		return out

	var spot := _sheltered_step(ctx, self_pos, threats)
	var tid := int(tsel.get("target_id", -1))
	if spot == Vector2.INF:
		var out2 := _positional_hold(ctx, tsel)
		out2["intent"] = "holding position"
		out2["reason"] = "%s wants cover but there is none within reach" % _unit_name(unit)
		return out2

	var why := ("%s is a support kit and loses nothing behind cover" % _unit_name(unit)
		if _is_support_kit(unit)
		else "%s is outnumbered %d-to-1 and took cover" % [_unit_name(unit), threats.size()])
	if spot.distance_to(self_pos) < 1.0 and tid != -1:
		# Already sheltered — fight from here rather than shuffling.
		return _finish(ctx, "attack", ctx["enemy_positions"][tid], tid, _pick_move_name(ctx, tid),
			"in cover", why, "nature")
	return _finish(ctx, "move", spot, tid, "", "taking cover", why, "nature")


static func _default_positional_intent(ctx: Dictionary) -> String:
	var aggression := _axis(ctx, ["aggression"], 50.0)
	var unit = ctx["unit"]
	var reach := _unit_best_reach(unit)

	# Cover first, when cover actually pays — see `_cover_is_profitable`.
	if _cover_is_profitable(ctx):
		return "shelter"

	# A kit that already outranges the melee band has no reason to close.
	if reach >= float(Sp.CHANNEL_RANGE.get("ranged", 70.0)) * 0.70:
		return "hold"

	# Aggression, when personality finally supplies it, still overrides toward the direct answer.
	if aggression >= 66.0:
		return "push"

	# ⚠️ COLLAPSE — the flank is a luxury a shrinking team cannot afford. A wide arc trades time
	# for angle, and that trade only pays while the line it left behind can hold without it. Once
	# this team is down bodies, the same unit walking the long way round is just absent from the
	# fight it is losing. So a team that has lost a THIRD of its strength abandons the arc and
	# comes back to the line — which also reads correctly to a watching player: the flank breaks
	# and the survivors close ranks.
	var living := 1                     # self (allies excludes it)
	for a in ctx["allies"]:
		if a.alive:
			living += 1
	var started: int = int(ctx.get("team_size", living))
	if started > 0 and float(living) / float(started) <= 0.66:
		return "push"

	# ⚠️ WHO FLANKS IS A QUESTION ABOUT THE TEAM, NOT ABOUT AN ABSOLUTE NUMBER. The first version of
	# this asked `dex >= 120`, a threshold picked without measuring the distribution — the fielded
	# monsters run DEX 19-54, so the branch was unreachable and every unit still marched straight
	# in. That is the same failure as every scale bug this session: a bare constant compared
	# against a quantity nobody had looked at.
	#
	# A formation assigns roles from who is AVAILABLE. The fastest short-reach bodies on the team
	# take the arc; the rest carry the line. That holds at any stat level, at any league, and for
	# any roster — including one where every monster is slow, where the answer is still "the two
	# fastest go wide" rather than "nobody does".
	var dex: float = _dex_of(unit)
	var faster := 0
	var short_reach_allies := 0
	for a in ctx["allies"]:
		if not a.alive:
			continue
		if _unit_best_reach(a) >= float(Sp.CHANNEL_RANGE.get("ranged", 70.0)) * 0.70:
			continue                      # long-reach allies are holding; they are not candidates
		short_reach_allies += 1
		if _dex_of(a) > dex:
			faster += 1
	# Roughly the quickest third of the line goes wide — enough to be a flank, not so many that
	# the centre gives way. ⚠️ Strict `<`, so a team where everyone ties sends nobody rather than
	# everyone: an accidental full-team flank would be a rout, not a manoeuvre.
	# ⚠️ `>= 3` and a strict third sent exactly ONE unit wide across both teams — measured. A flank
	# of one is a straggler, not a manoeuvre. `maxi(1, ...)` guarantees the fastest short-reach body
	# always goes, and a line of four sends two.
	if short_reach_allies >= 2 and faster < maxi(1, int(round(float(short_reach_allies) / 2.5))):
		return "wings"
	return "push"


static func _dex_of(u) -> float:
	var st = u.get("stats")
	return float(st.get("DEX", 0.0)) if st != null else 0.0


# ── §3.1 push ─────────────────────────────────────────────────────────────────────────────────

static func _positional_push(ctx: Dictionary, tsel: Dictionary) -> Dictionary:
	var unit = ctx["unit"]
	var self_pos: Vector2 = ctx["pos"]
	var tid := int(tsel.get("target_id", -1))
	var enemies: Array = ctx["enemies"]
	var positions: Array = ctx["enemy_positions"]

	if tid == -1 or tid >= enemies.size():
		return _finish(ctx, "idle", self_pos, -1, "", "pushing",
			"%s has no one left to press" % _unit_name(unit), "")

	var tpos: Vector2 = positions[tid]
	if self_pos.distance_to(tpos) <= _reach(ctx):
		return _finish(ctx, "attack", tpos, tid, _pick_move_name(ctx, tid), "pushing",
			"%s is pressing the line (your order: Push)" % _unit_name(unit), "")

	var lead := lerpf(PUSH_LEAD_MIN, PUSH_LEAD_MAX, _axis(ctx, ["aggression"], 50.0) / 100.0)
	var dir := tpos - self_pos
	if dir.length() < 0.01:
		dir = Vector2(1, 0)
	var beyond := tpos + dir.normalized() * lead
	return _finish(ctx, "move", beyond, tid, "", "pushing",
		"%s is pressing the line (your order: Push)" % _unit_name(unit), "")


# ── §3.2 hold ─────────────────────────────────────────────────────────────────────────────────

static func _positional_hold(ctx: Dictionary, tsel: Dictionary) -> Dictionary:
	var unit = ctx["unit"]
	var bb: Dictionary = ctx["blackboard"]
	var self_pos: Vector2 = ctx["pos"]
	var reach := _reach(ctx)

	# §4's Formation Resolve has no producer yet (no deployment UI writes a per-slot station into
	# ctx.tactics) — this unit's own first-tick position IS its deploy/formation station today, so
	# stamping it here on first use is the honest stand-in.
	if not bb.has("home_point"):
		bb["home_point"] = self_pos
	var home: Vector2 = bb["home_point"]

	var slack := lerpf(HOLD_SLACK_MAX, HOLD_SLACK_MIN, _axis(ctx, ["discipline"], 50.0) / 100.0)
	var enemies: Array = ctx["enemies"]
	var positions: Array = ctx["enemy_positions"]

	var best_i := -1
	var best_d := INF
	for i in range(enemies.size()):
		var d: float = home.distance_to(positions[i])
		if d <= reach and d < best_d:
			best_d = d
			best_i = i
	if best_i != -1:
		return _finish(ctx, "attack", positions[best_i], best_i, _pick_move_name(ctx, best_i),
			"holding the line", "%s is holding position (your order: Hold)" % _unit_name(unit), "")

	var tid := int(tsel.get("target_id", -1))
	if tid != -1 and tid < positions.size() and home.distance_to(positions[tid]) <= reach + slack:
		return _finish(ctx, "move", positions[tid], tid, "", "holding the line",
			"%s is holding position (your order: Hold)" % _unit_name(unit), "")

	return _finish(ctx, "move", home, tid, "", "returning to post",
		"%s pulled back to its station — nothing near enough to chase" % _unit_name(unit), "")


# ── §3.3 wings ────────────────────────────────────────────────────────────────────────────────

static func _positional_wings(ctx: Dictionary, tsel: Dictionary) -> Dictionary:
	var unit = ctx["unit"]
	var bb: Dictionary = ctx["blackboard"]
	var self_pos: Vector2 = ctx["pos"]
	var reach := _reach(ctx)
	var tid := int(tsel.get("target_id", -1))
	var enemies: Array = ctx["enemies"]
	var positions: Array = ctx["enemy_positions"]

	if tid == -1 or tid >= enemies.size():
		return _finish(ctx, "idle", self_pos, -1, "", "flanking",
			"%s has no one to flank" % _unit_name(unit), "")

	var tpos: Vector2 = positions[tid]
	if self_pos.distance_to(tpos) <= reach:
		return _finish(ctx, "attack", tpos, tid, _pick_move_name(ctx, tid), "flanking",
			"%s is working the flank (your order: Wings)" % _unit_name(unit), "")

	if not bb.has("flank_side"):
		bb["flank_side"] = _resolve_flank_side(ctx)
	var side: float = float(bb["flank_side"])

	var to_target := tpos - self_pos
	var fwd: Vector2 = (to_target.normalized() if to_target.length() > 0.01 else Vector2(1, 0))
	var perp := Vector2(-fwd.y, fwd.x)
	var flank_point := tpos - fwd * maxf(reach * 0.5, 4.0) + perp * side * WING_OFFSET

	if self_pos.distance_to(flank_point) <= WING_TOLERANCE:
		return _finish(ctx, "move", tpos, tid, "", "cutting in",
			"%s cut in from the flank onto %s" % [_unit_name(unit), _unit_name(enemies[tid])], "")

	return _finish(ctx, "move", flank_point, tid, "", "flanking",
		"%s is working the flank (your order: Wings)" % _unit_name(unit), "")


## §3.3's compose-time rule: use this unit's own side of its team's centreline if it already sits
## off-centre, else alternate deterministically by roster order (`unit_id` parity — no RNG draw).
## `ctx` carries no ground-size/centreline constant, so "centreline" is approximated as the mean y
## of this unit and its living allies at the moment of first use.
static func _resolve_flank_side(ctx: Dictionary) -> float:
	var self_pos: Vector2 = ctx["pos"]
	var allies: Array = ctx["ally_positions"]
	var sum_y: float = self_pos.y
	var n := 1
	for p in allies:
		sum_y += (p as Vector2).y
		n += 1
	var mean_y: float = sum_y / float(n)
	var d: float = self_pos.y - mean_y
	if absf(d) > 0.5:
		return (1.0 if d > 0.0 else -1.0)
	return (1.0 if int(ctx["unit_id"]) % 2 == 0 else -1.0)


# ── §3.4 dive ─────────────────────────────────────────────────────────────────────────────────

static func _positional_dive(ctx: Dictionary, tsel: Dictionary) -> Dictionary:
	var unit = ctx["unit"]
	var self_pos: Vector2 = ctx["pos"]
	var reach := _reach(ctx)
	var enemies: Array = ctx["enemies"]
	var positions: Array = ctx["enemy_positions"]

	if enemies.is_empty():
		return _finish(ctx, "idle", self_pos, -1, "", "diving for the back line",
			"%s has no one left to dive on" % _unit_name(unit), "")

	# back_target: deepest living enemy along this unit's own advance axis (its side's deploy
	# direction — Sp.deploy_positions puts team A facing +x, team B facing -x). current_target
	# from §2 (tsel) still governs who actually gets attacked once something is in reach — these
	# can legally diverge, per §3.4/§12.
	var axis := (Vector2(1, 0) if str(unit.side) == "A" else Vector2(-1, 0))
	var best_i := 0
	var best_depth := -INF
	for i in range(enemies.size()):
		var depth: float = (positions[i] as Vector2).dot(axis)
		if depth > best_depth:
			best_depth = depth
			best_i = i
	var back_pos: Vector2 = positions[best_i]

	var tid := int(tsel.get("target_id", -1))
	if self_pos.distance_to(back_pos) <= reach:
		var atid := (tid if (tid != -1 and tid < positions.size()) else best_i)
		return _finish(ctx, "attack", positions[atid], atid, _pick_move_name(ctx, atid),
			"diving for the back line",
			"%s is pushing for %s (your order: Dive)" % [_unit_name(unit), _unit_name(enemies[best_i])], "")

	return _finish(ctx, "move", back_pos, (tid if tid != -1 else best_i), "",
		"diving for the back line",
		"%s is pushing for %s (your order: Dive)" % [_unit_name(unit), _unit_name(enemies[best_i])], "")


# ── §3.5 guard ────────────────────────────────────────────────────────────────────────────────

static func _positional_guard(ctx: Dictionary, tsel: Dictionary) -> Dictionary:
	var unit = ctx["unit"]
	var tactics: Dictionary = ctx["tactics"]
	var allies: Array = ctx["allies"]
	var ally_positions: Array = ctx["ally_positions"]
	var self_pos: Vector2 = ctx["pos"]
	var reach := _reach(ctx)

	# `tactics.guardedAlly` — written by `tactics_ui.gd::_on_board_changed()` from the deployment
	# board's guard-target picker (2026-08-04). Still absent for AI-controlled rivals and any
	# caller that doesn't go through that screen, so the fallback below stays live.
	var charge_key = tactics.get("guardedAlly")
	var charge_idx: int = (allies.find(charge_key) if charge_key != null else -1)
	if charge_idx == -1:
		# §1.2 override #2 — no living charge to guard, behave as HOLD around own home_point.
		var hold_out := _positional_hold(ctx, tsel)
		hold_out["intent"] = "holding position"
		hold_out["reason"] = "%s has no living charge to guard — holding position instead" % _unit_name(unit)
		hold_out["attribution"] = "reacted"
		return hold_out

	var charge = allies[charge_idx]
	var charge_pos: Vector2 = ally_positions[charge_idx]
	var enemies: Array = ctx["enemies"]
	var positions: Array = ctx["enemy_positions"]

	var best_e := -1
	var best_d := INF
	for i in range(enemies.size()):
		var d: float = charge_pos.distance_to(positions[i])
		if d <= INTERCEPT_RADIUS and d < best_d:
			best_d = d
			best_e = i
	if best_e != -1:
		var epos: Vector2 = positions[best_e]
		var reason := "%s stepped between %s and %s" % [_unit_name(unit), _unit_name(enemies[best_e]), _unit_name(charge)]
		if self_pos.distance_to(epos) <= reach:
			return _finish(ctx, "attack", epos, best_e, _pick_move_name(ctx, best_e),
				"guarding %s" % _unit_name(charge), reason, "")
		var interpose := (epos + charge_pos) * 0.5
		return _finish(ctx, "move", interpose, best_e, "", "guarding %s" % _unit_name(charge), reason, "")

	if self_pos.distance_to(charge_pos) > GUARD_LEASH:
		return _finish(ctx, "move", charge_pos, int(tsel.get("target_id", -1)), "",
			"guarding %s" % _unit_name(charge), "%s is staying close to %s" % [_unit_name(unit), _unit_name(charge)], "")

	var tid := int(tsel.get("target_id", -1))
	if tid != -1 and tid < positions.size() and self_pos.distance_to(positions[tid]) <= reach:
		return _finish(ctx, "attack", positions[tid], tid, _pick_move_name(ctx, tid),
			"guarding %s" % _unit_name(charge), "%s is staying close to %s" % [_unit_name(unit), _unit_name(charge)], "")

	var orbit := charge_pos + Vector2(GUARD_LEASH * 0.5, 0.0)
	return _finish(ctx, "move", orbit, tid, "", "guarding %s" % _unit_name(charge),
		"%s is staying close to %s" % [_unit_name(unit), _unit_name(charge)], "")


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# §6 — ABILITY POLICY. `free` is `spatial_sim.gd`'s own strongest-ready-move default (empty
## `move_name`). `holdBig`/`combo` degrade to `free` — no authored capstone/opener/payoff flag
## exists on any move today. See the file header.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

static func _pick_move_name(_ctx: Dictionary, _target_idx: int) -> String:
	return ""


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# §8 — urgent-override helpers shared by the emergency-disengage branch and `disengage`'s degrade
# path (both need "who is currently threatening me" / "a point that gets away from them").
# ═══════════════════════════════════════════════════════════════════════════════════════════════

static func _unit_best_reach(u) -> float:
	var best: float = Sp.reach_of(u.basic_attack, true)
	for mv in u.moveset:
		if str(mv.get("target", "enemy")) != "enemy":
			continue
		var r: float = Sp.reach_of(mv, false)
		if r > best:
			best = r
	return best


static func _reach(ctx: Dictionary) -> float:
	return _unit_best_reach(ctx["unit"])


static func _threatening_enemies(ctx: Dictionary) -> Array:
	var self_pos: Vector2 = ctx["pos"]
	var enemies: Array = ctx["enemies"]
	var positions: Array = ctx["enemy_positions"]
	var out: Array = []
	for i in range(enemies.size()):
		var er := _unit_best_reach(enemies[i])
		if self_pos.distance_to(positions[i]) <= er + THREAT_MARGIN:
			out.append(i)
	return out


## `aboutToDie()`, §8: hp critical AND a threatening enemy exists. ⚠️ The spec's own second clause
## ("E's average hit ≥ current HP") needs the verified damage formula's full input set (mitigation,
## crit, variance) to answer honestly — reproducing that here would duplicate `damage.gd` rather
## than call it, for a reflex that only needs to be roughly right, not exactly right. Simplified to
## "a threatening enemy exists", flagged rather than faked.
static func _about_to_die(ctx: Dictionary, threat_idx: Array) -> bool:
	return ctx["unit"].hp_frac() <= LETHAL_RISK_FRAC and not threat_idx.is_empty()


## ⚠️ THE "UNBUILT INFRA" THIS FILE HAS BEEN DEGRADING AROUND SINCE IT WAS WRITTEN. Both
## `_disengage_withdrawal` and the blocked-line problem needed the same missing primitive: a way
## to ask "where near me is a position with the line-of-sight property I want?". There is no
## navmesh query for it and there does not need to be — `Spatial.cover_between` already answers
## the question for any pair of points, so the primitive is a deterministic SAMPLE around the unit
## scored against that function.
##
## ⚠️ DETERMINISM: fixed ring of angles and fixed radii, no rng, no dictionary iteration. Two
## replays of the same fight sample the same points in the same order. Sampling is the only part
## of this that could have desynced the sim, so it is the part written most conservatively.
const LOS_RING_ANGLES := 12
const LOS_RING_RADII := [0.55, 1.0, 1.6]     ## multiples of the unit's own reach

static func _ring_points(ctx: Dictionary, reach: float) -> Array:
	var self_pos: Vector2 = ctx["pos"]
	var out: Array = []
	for r in LOS_RING_RADII:
		var rad: float = reach * float(r) * 0.5
		for i in range(LOS_RING_ANGLES):
			var a: float = TAU * float(i) / float(LOS_RING_ANGLES)
			out.append(self_pos + Vector2(cos(a), sin(a)) * rad)
	return out


## The nearest sampled point from which this unit can actually SHOOT its target. Returns the
## unit's own position when the line is already clear, or when nothing sampled is better —
## "nowhere to go" must read as "stay", never as "walk to an arbitrary point".
static func _clear_line_point(ctx: Dictionary, target_pos: Vector2, reach: float) -> Vector2:
	var self_pos: Vector2 = ctx["pos"]
	var obstacles: Array = ctx["obstacles"]
	if not bool(Sp.cover_between(self_pos, target_pos, obstacles)["blocked"]):
		return self_pos
	var best := self_pos
	var best_d := INF
	for p in _ring_points(ctx, reach):
		# ⚠️ Must still be able to REACH the target from there, or clearing the line buys nothing.
		if (p as Vector2).distance_to(target_pos) > reach:
			continue
		if bool(Sp.cover_between(p, target_pos, obstacles)["blocked"]):
			continue
		var d: float = self_pos.distance_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best


## The best sampled point for BREAKING line of sight from a set of threats — the cover-seeking
## half. Scores by how many threats are fully blocked, then by distance gained, so a unit prefers
## to put something solid between itself and the people shooting it rather than merely run.
static func _break_los_point(ctx: Dictionary, threat_idx: Array, reach: float) -> Vector2:
	var self_pos: Vector2 = ctx["pos"]
	var positions: Array = ctx["enemy_positions"]
	var obstacles: Array = ctx["obstacles"]
	var best := Vector2.INF
	var best_score := -1.0
	for p in _ring_points(ctx, maxf(reach, ESCAPE_FLEE_DIST * 2.0)):
		var blocked := 0
		var gained := 0.0
		for i in threat_idx:
			var tp: Vector2 = positions[i]
			if bool(Sp.cover_between(p, tp, obstacles)["blocked"]):
				blocked += 1
			gained += (p as Vector2).distance_to(tp) - self_pos.distance_to(tp)
		# Blocking is worth far more than a step of distance — that is the whole point of cover,
		# and without the weighting this degenerates into the plain flee it is meant to replace.
		var score: float = float(blocked) * 100.0 + gained
		if score > best_score:
			best_score = score
			best = p
	return best


## A step toward `rally` that also breaks line of sight from `threat_idx`. Returns `Vector2.INF`
## when no sampled point blocks anything — "there is no cover on this route" must read as "go
## straight there", never as a detour to nowhere.
##
## ⚠️ Differs from `_break_los_point` in what it optimises: that one is escaping and wants distance
## AND cover; this one has a destination already and only chooses HOW to get there. Scored on
## blocked-threats first, then on progress toward the rally point — so a unit never retreats
## AWAY from its allies just to hug a pillar.
static func _sheltered_step(ctx: Dictionary, rally: Vector2, threat_idx: Array) -> Vector2:
	var self_pos: Vector2 = ctx["pos"]
	var positions: Array = ctx["enemy_positions"]
	var obstacles: Array = ctx["obstacles"]
	var here_d: float = self_pos.distance_to(rally)
	var best := Vector2.INF
	var best_score := 0.0
	for p in _ring_points(ctx, _reach(ctx)):
		var blocked := 0
		for i in threat_idx:
			if bool(Sp.cover_between(p, positions[i], obstacles)["blocked"]):
				blocked += 1
		if blocked == 0:
			continue
		# Progress toward the rally point, normalised, so it can never outweigh a blocked threat
		# but still breaks ties between equally-covered spots.
		var progress: float = here_d - (p as Vector2).distance_to(rally)
		var score: float = float(blocked) * 100.0 + clampf(progress, -50.0, 50.0)
		if score > best_score:
			best_score = score
			best = p
	return best


static func _flee_point(ctx: Dictionary, threat_idx: Array) -> Vector2:
	var self_pos: Vector2 = ctx["pos"]
	var positions: Array = ctx["enemy_positions"]

	# ⚠️ COVER FIRST, DISTANCE SECOND. Running in a straight line away from archers is the losing
	# move in every game that has ever had archers; breaking line of sight is the winning one, and
	# `blocking`-grade cover stops a shot outright (`Spatial.COVER_BLOCKS_LOS_GRADE`). Falls
	# through to the old open-ground flee when nothing sampled actually blocks anything, so a bare
	# arena behaves exactly as before.
	if not threat_idx.is_empty() and not (ctx["obstacles"] as Array).is_empty():
		var covered := _break_los_point(ctx, threat_idx, _reach(ctx))
		if covered != Vector2.INF:
			var any_blocked := false
			for i in threat_idx:
				if bool(Sp.cover_between(covered, positions[i], ctx["obstacles"])["blocked"]):
					any_blocked = true
					break
			if any_blocked:
				return covered

	var sum := Vector2.ZERO
	for i in threat_idx:
		sum += (positions[i] as Vector2)
	var centroid: Vector2 = sum / float(threat_idx.size())
	var dir := self_pos - centroid
	if dir.length() < 0.01:
		dir = Vector2(1, 0)
	return self_pos + dir.normalized() * ESCAPE_FLEE_DIST


static func _living_centroid(ctx: Dictionary) -> Vector2:
	var sum: Vector2 = ctx["pos"]
	var n := 1
	for p in ctx["ally_positions"]:
		sum += (p as Vector2)
		n += 1
	for p in ctx["enemy_positions"]:
		sum += (p as Vector2)
		n += 1
	return sum / float(n)


static func _nearest_point(from: Vector2, pts: Array) -> Vector2:
	var best: Vector2 = pts[0]
	var best_d: float = from.distance_to(best)
	for p in pts:
		var d: float = from.distance_to(p as Vector2)
		if d < best_d:
			best_d = d
			best = p
	return best


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# §9 — personality axis reads. `ctx.personality` is `{}` until stream H lands
## (`spatial_sim.gd::_personality_of` says so explicitly) — every read here defaults to 50.0
## (neutral), matching that file's own "missing key = no lean, use the axis default" contract.
## Keys tried match docs/TACTICS_TREES.md §9's own naming (Discipline/Nerve/Aggression/Focus,
## lower-cased) — `docs/PERSONALITY_STATS.md`'s internal field names (`temperament`/`mental`) are
## NOT tried here, since nothing populates ctx.personality under either naming yet; whichever
## naming stream H ships, this is the one seam to update.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

static func _axis(ctx: Dictionary, keys: Array, default_v: float) -> float:
	var personality: Dictionary = ctx.get("personality", {})
	for k in keys:
		if personality.has(k):
			return float(personality[k])
	return default_v


static func _unit_name(u) -> String:
	return str(u.species_name)
