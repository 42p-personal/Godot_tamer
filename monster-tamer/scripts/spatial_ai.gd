## TEAM-LEVEL AI — stream A of the spatial rebuild (2026-08-04 rewrite).
##
## ⚠️ THIS FILE'S SCOPE SHRANK ON PURPOSE. The previous version of this file (see git history)
## also carried PER-UNIT decisions — `choose_target()`, `desired_position()` and their supporting
## geometry (cover-seeking, aura clamping, unit-reach). All of that now lives in the behaviour
## tree (`scripts/ai/monster_tree.gd`, stream B, per `docs/BUILD_CONTRACT.md` §1 and
## `docs/TACTICS_TREES.md`) — the tree decides WHAT a monster does, `spatial_sim.gd` only
## legality-gates it. What's left here is genuinely TEAM-scoped: a computation that has to see
## every living member of a side at once to mean anything, which a per-unit tree leaf cannot do
## in isolation.
##
## Pure, deterministic, stateless. Every function here is a plain fold over its arguments — no
## stored state, no `randf()`, no Dictionary iteration whose order could vary. Called once per
## side per decision cycle by `spatial_sim.gd` (`team_focus()`), and the result (an index into
## `enemies`) is handed to every living unit on that side via `ctx.team_focus_id` — the structural
## fix for weak focus fire that `docs/TACTICS_BRAINSTORM.md` §1 identifies: target priority used
## to live per-monster, so five monsters "agreeing" on a target was coincidence. Computing it once
## for the team and passing it down is what turns coincidence into coordination. The TREE still
## decides, per unit, whether following it is worth the walk (`ctx.team_focus_id` is advisory,
## not a command) — that per-unit weighing is tree logic now, not this file's.
class_name SpatialAi
extends RefCounted

# ═══════════════════════════════════════════════════════════════════════════════════════════════
# TEAM FOCUS — one shared target per team per decision cycle.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## `units`/`positions` — the FOCUSING team, fixed order, parallel arrays (used only for the
## spatial default's reachability term). `enemies`/`enemy_positions` — the opposing team, fixed
## order, parallel arrays; the return value is an INDEX into these two, or -1 if `enemies` is
## empty. `tactics` is the team's merged plan (`tactics.gd` vocabulary) — reads `targetPriority`.
##
## Mirrors `Tactics.pick_target`'s priority semantics exactly (manmark / tanks / casters / default
## lowest-HP) so a team's read is the same whether asked once here or per-unit there — but the
## "default" branch is resolved spatially instead of by HP alone; see `_team_default_focus`.
static func team_focus(units: Array, positions: Array, enemies: Array, enemy_positions: Array,
		tactics: Dictionary) -> int:
	if enemies.is_empty():
		return -1

	var priority: String = String(tactics.get("targetPriority", ""))
	if priority == "manmark":
		var marked = tactics.get("markedUnit")
		var idx: int = enemies.find(marked)
		if idx != -1:
			return idx
		# marked unit already dead / never set — fall through to the default read below, exactly
		# like tactics.gd's pick_target does for the non-spatial engine.
	elif priority == "tanks":
		return _highest_stat_index(enemies, "CON")
	elif priority == "casters":
		var casters: Array = []
		for i in enemies.size():
			if enemies[i].role == "support":
				casters.append(i)
		if not casters.is_empty():
			return _lowest_hp_index(enemies, casters)
		# no caster left alive — falls through to the default read, same as tactics.gd.

	return _team_default_focus(units, positions, enemies, enemy_positions)


## `_team_focus_for`'s distance term, weighed against HP-fraction (0..1, coefficient 1.0
## implicit). 0.3 means: a target that's genuinely much weaker (>~30% lower HP fraction) always
## wins the team's attention regardless of position; among targets that are roughly equally hurt,
## the team gravitates to whichever is closer to more of the team. Keeps the default "weakest"
## read from tactics.gd but makes it spatially sane instead of "weakest, anywhere on the map."
const TEAM_FOCUS_DIST_WEIGHT := 0.3

## The spatially-aware "weakest" default: hp_frac plus a normalised mean-distance-from-the-team
## term. Distance is normalised against the largest mean distance among the candidates, so this
## needs no arena-scale constant and behaves identically at every team size / ground scale.
static func _team_default_focus(units: Array, positions: Array, enemies: Array,
		enemy_positions: Array) -> int:
	var mean_d: Array = []
	var max_d := 0.0
	for j in enemies.size():
		var total := 0.0
		for i in positions.size():
			total += positions[i].distance_to(enemy_positions[j])
		var m: float = total / maxf(1.0, float(positions.size()))
		mean_d.append(m)
		max_d = maxf(max_d, m)

	var best_idx := 0
	var best_score: float = INF
	for j in enemies.size():
		var hp_frac: float = enemies[j].hp_frac()
		var dist_norm: float = 0.0 if max_d <= 0.0 else float(mean_d[j]) / max_d
		var score: float = hp_frac + dist_norm * TEAM_FOCUS_DIST_WEIGHT
		if score < best_score or (score == best_score and j < best_idx):
			best_score = score
			best_idx = j
	return best_idx


static func _highest_stat_index(enemies: Array, stat: String) -> int:
	var best := 0
	var best_v: float = float(enemies[0].stats.get(stat, 0.0))
	for i in enemies.size():
		var v: float = float(enemies[i].stats.get(stat, 0.0))
		if v > best_v:
			best_v = v
			best = i
	return best


static func _lowest_hp_index(enemies: Array, subset: Array) -> int:
	var best: int = subset[0]
	var best_hp: float = enemies[best].hp_frac()
	for i in subset:
		var hp: float = enemies[i].hp_frac()
		if hp < best_hp:
			best_hp = hp
			best = i
	return best
