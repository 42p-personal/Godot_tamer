## THE SPATIAL FIELD SIMULATION — rewritten from scratch, 2026-08-04, per docs/BUILD_CONTRACT.md
## and docs/AUTOBATTLER_DESIGN.md. Replaces the previous version wholesale — see
## `docs/AUTOBATTLER_DESIGN.md` #32: "the flat-scoring structure is what produces the blob, and it
## survives incremental refactors."
##
## ⚠️ THE MATHS IS STILL NOT REWRITTEN. `Damage.resolve_strike`, `Derive`, `StatusMath.apply_status`
## and `Tick.tick_unit` are called exactly as before; only the geometry/decision layer around them
## changed. This file's job is real space — pathfinding, solid bodies, reach/cover/flanking — and
## handing the per-unit DECISION to a behaviour tree instead of making it here.
##
## ── The five-step loop (per docs/BUILD_CONTRACT.md §1) ──────────────────────────────────────────
##   1. tick statuses/regen/cooldowns/attrition           (Tick.tick_unit, unchanged)
##   2. build each living unit's `ctx` and call the tree  (scripts/ai/monster_tree.gd, if it exists)
##   3. path and move                                     (NavigationServer3D + deterministic
##                                                          body-vs-body separation)
##   4. resolve actions                                   (reach/min-range/cover gate, then the
##                                                          verified damage/status maths)
##   5. record a frame                                    (docs/BUILD_CONTRACT.md §2)
## ─────────────────────────────────────────────────────────────────────────────────────────────
##
## ⚠️ `scripts/ai/monster_tree.gd` (stream B) MAY NOT EXIST YET. Every call site guards with
## `ResourceLoader.exists()` + `has_method("tick")` and falls back to "nearest living enemy; move
## toward it" (per the task brief). See `_fallback_decide()`. The fallback is not a design — it
## exists so this file runs and is measurable standalone.
##
## ⚠️ PATHFINDING IS `NavigationServer3D.map_get_path()` OVER A BAKED STATIC NAVMESH
## (docs/SPIKE_DETERMINISM.md verdict: byte-identical across 5 separate processes). The trap named
## in that doc and in docs/BUILD_CONTRACT.md §0 is real and is handled explicitly here, not
## incidentally: `map_get_path()` returns an EMPTY path with no error if the map has not synced,
## and — measured directly by the spike — `map_force_update()` alone does NOT force that sync; only
## real elapsed `SceneTree` frames do. Since this class has no frame loop of its own, `run()` is
## now a COROUTINE that awaits `SceneTree.process_frame` a fixed number of times before the very
## first query, using the exact mechanism the spike proved deterministic.
##
## ⚠️ BREAKING CHANGE FOR EVERY CALLER: `run()` used to be synchronous (`var result := sim.run()`).
## It is now `await sim.run()`. This is unavoidable given the sync trap above — see the report for
## the full reasoning — and it is flagged here as loudly as possible because nothing in
## docs/BUILD_CONTRACT.md specifies this either way, so no other stream would know to expect it.
##
## ⚠️ THE LEASH IS GONE AND STAYS GONE. Desired position is NEVER clamped anywhere in this file.
## See the tombstone comment near `_move_phase` for what used to be here and why it was deleted.
##
## Determinism (docs/BUILD_CONTRACT.md §0): fixed `Sp.DT`, one injected `RandomNumberGenerator`,
## fixed iteration order (`_units`: team A in slot order, then team B), no `randf()`, no
## `Array.shuffle()`. Dictionaries (`spatial_state`, `unit_ids`) are used ONLY as keyed lookups,
## never iterated, so their insertion order never leaks into the result.
class_name SpatialSim
extends RefCounted

## ⚠️ PRELOAD, NOT THE BARE CLASS NAMES — the global script-class cache is COLD under
## `--headless --script` and during early autoload boot. See `.claude/docs/technical-preferences.md`.
const Sp = preload("res://scripts/spatial.gd")
const DamageMath = preload("res://scripts/damage.gd")
const Innates = preload("res://scripts/innate_fx.gd")
const DeriveMath = preload("res://scripts/derive.gd")
const TickLib = preload("res://scripts/tick.gd")
const StatusMathLib = preload("res://scripts/status_math.gd")
const TacticsScript = preload("res://scripts/tactics.gd")

const AI_SCRIPT_PATH := "res://scripts/spatial_ai.gd"
const TREE_SCRIPT_PATH := "res://scripts/ai/monster_tree.gd"

## Healing multiplier when the target is healblocked — `src/battle.ts:430`.
const HEALBLOCK_MULT := 0.4

const MAX_DURATION := 180.0  # seconds of sim-time before a forced draw-by-attrition

# ── navigation ────────────────────────────────────────────────────────────────────────────────
const OBSTACLE_HEIGHT := 4.0   # taller than agent_max_climb, so recast carves it out as a real block
## ⚠️ PROVEN, NOT GUESSED — the exact margin docs/SPIKE_DETERMINISM.md measured as sufficient
## (full sync completed by ~frame 10 there) and confirmed byte-identical across 5 separate process
## invocations at this margin. Do not shrink this without re-running that spike's protocol.
const NAV_SYNC_FRAMES := 40
const REPATH_EPS := 1.0         # re-query the navmesh once the goal moves this far from the last query
const WAYPOINT_EPS := 1.0       # advance to the next waypoint once this close to the current one

var team_a: Array = []  # Array[MonsterInstance]
var team_b: Array = []
var team_a_plan: Dictionary = {}
var team_b_plan: Dictionary = {}
var unit_orders: Dictionary = {}  # MonsterInstance -> per-monster order dict
var _pack_hits: Dictionary = {}   # target -> {side, by, tick} — arms packDmg inside its window
var _projectiles: Array = []      # in-flight aimed abilities — {id, atk, tgt, mv, is_basic, pos, kind}
var _next_proj_id: int = 0
var _tick_no: int = 0
var obstacles: Array = []         # [{rect: Rect2, grade: "soft"|"hard"|"blocking", kind: String}]

var rng: RandomNumberGenerator
var now := 0.0
var event_log: Array = []
var frames: Array = []
var pending_shots: Array = []

var team_size: int = 1
var ground: Vector2 = Vector2.ZERO

var _units: Array = []            # fixed order: team A slot order, then team B — THE iteration order
var unit_ids: Dictionary = {}     # MonsterInstance -> stable int id (lookup only, never iterated)
var id_to_unit: Array = []        # int id -> MonsterInstance
var spatial_state: Dictionary = {}  # MonsterInstance -> {pos, facing, casting, nav, blackboard, ...}

var _ai_script = null     # loaded res://scripts/spatial_ai.gd, or null if absent
var _tree_script = null   # loaded res://scripts/ai/monster_tree.gd, or null if absent (fallback active)

var _nav_map: RID
var _nav_region: RID
var _nav_ready := false


func _init(a: Array, b: Array, seed_: int = 0, plan_a: Dictionary = {}, plan_b: Dictionary = {},
		orders: Dictionary = {}, obs: Array = []) -> void:
	team_a = a
	team_b = b
	team_a_plan = plan_a
	team_b_plan = plan_b
	unit_orders = orders
	obstacles = obs

	rng = RandomNumberGenerator.new()
	rng.seed = seed_

	for m in team_a:
		m.side = "A"
		m.reset_for_battle()
	for m in team_b:
		m.side = "B"
		m.reset_for_battle()

	_units = team_a + team_b
	for i in range(_units.size()):
		unit_ids[_units[i]] = i
		id_to_unit.append(_units[i])

	team_size = maxi(team_a.size(), team_b.size())
	ground = Sp.ground_size(team_size)

	if ResourceLoader.exists(AI_SCRIPT_PATH):
		var loaded_ai = load(AI_SCRIPT_PATH)
		if loaded_ai != null:
			_ai_script = loaded_ai
	if ResourceLoader.exists(TREE_SCRIPT_PATH):
		var loaded_tree = load(TREE_SCRIPT_PATH)
		if loaded_tree != null:
			_tree_script = loaded_tree

	_deploy()


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# SETUP
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## ⚠️ A DRAGGED CHIP IS NOW A REAL START POSITION. `unit_orders[m]["deployPos"]` — written by the
## deployment board via the tactics commit — overrides this side's default slot. This was THE
## missing hook the board's own header documented: free placement drew a plan the fight never
## read. The override is VALIDATED, not trusted: clamped into the side's legal `deploy_zone`
## (the shared definition — the board clamps to the same rect, but a stale save or a future
## caller must not be able to start a unit in the enemy zone), then pushed out of any blocking
## obstacle. `monster_tree.gd` treats a unit's first-tick position as its station, so a custom
## start IS a custom station with no further plumbing.
func _deploy() -> void:
	var pos_a: Array = Sp.deploy_positions(team_size, "A")
	var pos_b: Array = Sp.deploy_positions(team_size, "B")
	for i in range(team_a.size()):
		var p: Vector2 = pos_a[i] if i < pos_a.size() else pos_a[pos_a.size() - 1]
		p = _deploy_override(team_a[i], p, "A")
		spatial_state[team_a[i]] = _new_state(p, Vector2(1, 0))
	for i in range(team_b.size()):
		var p: Vector2 = pos_b[i] if i < pos_b.size() else pos_b[pos_b.size() - 1]
		p = _deploy_override(team_b[i], p, "B")
		spatial_state[team_b[i]] = _new_state(p, Vector2(-1, 0))

	# ⚠️ THE CARE LOOP ARRIVES ON THE FIELD HERE. Until 2026-08-06 all 130 innates and every care
	# stat had ZERO references in this engine — raising a monster changed its numbers and nothing
	# else. Now: the active innate's effects land potency-scaled by happiness (a neglected
	# monster's gift burns at half strength), and a monster sent out under WEARY_STAMINA fights
	# visibly weary. `station` is the deploy spot — real, player-placed since the deployment fix —
	# and homeGround innates measure from it.
	for m in _units:
		var st: Dictionary = spatial_state[m]
		st["fx"] = Innates.compute(m, GameData.innate_effects)
		st["weary"] = float(m.stamina if m.get("stamina") != null else 100.0) < Innates.WEARY_STAMINA
		var ward := float((st["fx"] as Dictionary).get("startWard", 0.0))
		if ward > 0.0:
			# Same mods shape `_mod_sum(..., "ward")` already reads; effectively permanent.
			m.mods.append({"ward": ward, "until": 999999.0})


func _deploy_override(m, fallback: Vector2, side: String) -> Vector2:
	var own: Dictionary = unit_orders.get(m, {})
	if not own.has("deployPos"):
		return fallback
	var want: Vector2 = own["deployPos"]
	var zone: Rect2 = Sp.deploy_zone(team_size, side)
	want.x = clampf(want.x, zone.position.x, zone.position.x + zone.size.x)
	want.y = clampf(want.y, zone.position.y, zone.position.y + zone.size.y)
	return _resolve_obstacles(want)


func _new_state(p: Vector2, facing: Vector2) -> Dictionary:
	return {
		"pos": p, "facing": facing, "casting": null,
		"_moved": false, "_just_hit": false, "_advancing": true,
		"nav": {"path": PackedVector2Array(), "goal": Vector2(INF, INF), "i": 0},
			"move_dir": Vector2.ZERO,   # heading carried between ticks so the body has momentum
		"blackboard": {},
		# ── the care loop (innate_fx.gd) ──
		"fx": {},                # potency-scaled active-innate effects, computed at deploy
		"station": p,            # deploy position — homeGround measures from here
		"run": 0.0,              # sustained straight-run distance — arms chargeDmg
		"hit_done": false,       # firstHitMult consumed?
		"weary": false,          # fighting under WEARY_STAMINA
	}


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# NAVIGATION — bake once, sync explicitly, then plain synchronous queries for the rest of the fight.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## Deterministic box-face triangulation, identical construction to the proven spike
## (`_spike_determinism.gd`) — kept local rather than shared because that file is a throwaway,
## seed-free fixture script, not production code to depend on.
static func _box_faces(cx: float, cz: float, hx: float, hz: float, y0: float, y1: float) -> PackedVector3Array:
	var x0 := cx - hx
	var x1 := cx + hx
	var z0 := cz - hz
	var z1 := cz + hz
	var corners := [
		Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1),
		Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1),
	]
	var order := [
		0, 1, 2, 0, 2, 3,       # bottom
		4, 6, 5, 4, 7, 6,       # top
		0, 4, 1, 1, 4, 5,       # four sides
		1, 5, 2, 2, 5, 6,
		2, 6, 3, 3, 6, 7,
		3, 7, 0, 0, 7, 4,
	]
	var out := PackedVector3Array()
	for i in order:
		out.append(corners[i])
	return out


## ⚠️ ONLY "blocking"-grade obstacles carve the navmesh. `Spatial.cover_between` already splits
## cover into soft/hard (accuracy penalty only — a worse shot, not an impossible path) and
## `blocking` (`Spatial.COVER_BLOCKS_LOS_GRADE`, stops a shot outright). Movement follows the same
## split: a unit paths straight through soft/hard cover (it's furniture height, not a wall) and
## only routes around `blocking` pieces. Keeping the two systems reading the same grade the same
## way is a deliberate consistency decision, not an oversight — flagged in the report.
func _bake_and_register_navmesh() -> void:
	var geo := NavigationMeshSourceGeometryData3D.new()
	var g := ground
	var ground_faces := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(g.x, 0.0, 0.0), Vector3(g.x, 0.0, g.y),
		Vector3(0.0, 0.0, 0.0), Vector3(g.x, 0.0, g.y), Vector3(0.0, 0.0, g.y),
	])
	geo.add_faces(ground_faces, Transform3D.IDENTITY)
	for o in obstacles:
		if str(o.get("grade", "soft")) != Sp.COVER_BLOCKS_LOS_GRADE:
			continue
		var rect: Rect2 = o["rect"]
		var cx := rect.position.x + rect.size.x * 0.5
		var cz := rect.position.y + rect.size.y * 0.5
		var hx := rect.size.x * 0.5
		var hz := rect.size.y * 0.5
		geo.add_faces(_box_faces(cx, cz, hx, hz, 0.0, OBSTACLE_HEIGHT), Transform3D.IDENTITY)

	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.1
	nm.agent_height = 2.0
	nm.agent_radius = Sp.BODY_RADIUS
	nm.agent_max_climb = 0.3
	nm.agent_max_slope = 45.0
	nm.region_min_size = 2.0
	NavigationMeshGenerator.bake_from_source_geometry_data(nm, geo)

	_nav_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_up(_nav_map, Vector3.UP)
	NavigationServer3D.map_set_cell_size(_nav_map, nm.cell_size)
	NavigationServer3D.map_set_cell_height(_nav_map, nm.cell_height)
	NavigationServer3D.map_set_active(_nav_map, true)
	_nav_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(_nav_region, _nav_map)
	NavigationServer3D.region_set_transform(_nav_region, Transform3D.IDENTITY)
	NavigationServer3D.region_set_navigation_mesh(_nav_region, nm)


## ⚠️ THE TRAP FROM docs/SPIKE_DETERMINISM.md §7.3, HANDLED EXPLICITLY. `map_get_path()` returns
## an empty path with no error if the map has not synced, and `map_force_update()` alone (measured
## directly by the spike) does NOT force that sync — only real elapsed `SceneTree` frames do. This
## sim has no frame loop of its own, so it borrows one: `await` a fixed number of `process_frame`
## signals from whatever `SceneTree` is actually running (the same mechanism `_spike_determinism.gd`
## proved byte-identical across 5 separate process invocations, there driven by `_process()` counting
## instead of `await` — structurally the same synchronization, since both just let real engine
## frames elapse before the first query).
func _ensure_nav_synced() -> void:
	if _nav_ready:
		return
	_bake_and_register_navmesh()
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var tree: SceneTree = loop
		for _i in range(NAV_SYNC_FRAMES):
			await tree.process_frame
	else:
		# ⚠️ No live SceneTree main loop to borrow frames from. This path is NOT covered by the
		# spike's determinism evidence (which always ran inside a real SceneTree main loop) — it
		# is a best-effort fallback, not a proven-deterministic one. Flagged in the report.
		NavigationServer3D.map_force_update(_nav_map)
	_nav_ready = true


func _free_navigation() -> void:
	NavigationServer3D.free_rid(_nav_region)
	NavigationServer3D.free_rid(_nav_map)


func _query_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var path3: PackedVector3Array = NavigationServer3D.map_get_path(
		_nav_map, Vector3(from.x, 0.0, from.y), Vector3(to.x, 0.0, to.y), true)
	if path3.size() < 2:
		# Empty (unsynced map, or a genuinely unreachable point — e.g. a goal generated slightly
		# outside the baked walkable polygon by an upstream rounding step) — degrade to a direct
		# line rather than leaving the unit with nowhere to go. A synced map with real obstacles
		# will not hit this path for a legitimate query; if it does, that is worth a QA look, not
		# a silent freeze.
		return PackedVector2Array([from, to])
	var out := PackedVector2Array()
	for p in path3:
		out.append(Vector2(p.x, p.z))
	return out


func _needs_repath(nav_state: Dictionary, desired: Vector2) -> bool:
	var path: PackedVector2Array = nav_state.get("path", PackedVector2Array())
	if path.is_empty():
		return true
	var goal: Vector2 = nav_state.get("goal", Vector2(INF, INF))
	return goal.distance_to(desired) > REPATH_EPS


func _next_path_point(nav_state: Dictionary, cur_pos: Vector2) -> Vector2:
	var path: PackedVector2Array = nav_state.get("path", PackedVector2Array())
	if path.is_empty():
		return cur_pos
	var i: int = int(nav_state.get("i", 0))
	while i < path.size() - 1 and cur_pos.distance_to(path[i]) < WAYPOINT_EPS:
		i += 1
	nav_state["i"] = i
	return path[i]


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# THE MAIN LOOP
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## ⚠️ COROUTINE. Callers must `await` this. See the file header for why.
func run() -> Dictionary:
	await _ensure_nav_synced()

	_log_event({"kind": "start", "teamA": _names(team_a), "teamB": _names(team_b)})

	while now < MAX_DURATION:
		if _living(team_a).is_empty() or _living(team_b).is_empty():
			break

		_tick_no += 1
		_tick_projectiles()
		# 1. tick statuses/regen/cooldowns
		for m in _units:
			if m.alive:
				_tick_one(m)
				# ── innate regen (per-round values, paid per second — same conversion tick.gd
				# uses for regen mods) ──
				var rfx: Dictionary = spatial_state[m].get("fx", {})
				var rpos: Vector2 = spatial_state[m]["pos"]
				var mana_regen := float(rfx.get("regen", 0.0)) \
					+ Innates.aura_sum("auraRegen", rpos, _living(_allies_of(m)), spatial_state) \
					- Innates.aura_sum("enemyRegenDebuff", rpos, _living(_enemies_of(m)), spatial_state)
				var hp_regen := float(rfx.get("hpRegen", 0.0)) \
					+ Innates.aura_sum("auraHpRegen", rpos, _living(_allies_of(m)), spatial_state)
				if mana_regen != 0.0:
					m.mp = clampf(m.mp + mana_regen / DeriveMath.rounds_to_seconds(1.0) * Sp.DT, 0.0, float(m.max_mana))
				if hp_regen > 0.0:
					m.hp = minf(float(m.max_hp), m.hp + hp_regen / DeriveMath.rounds_to_seconds(1.0) * Sp.DT)

		for m in _units:
			var st: Dictionary = spatial_state[m]
			st["_moved"] = false
			st["_just_hit"] = false

		# 2. decide — ctx + behaviour tree (or the fallback)
		var decisions: Dictionary = {}
		for m in _units:
			if m.alive and not m.is_incapacitated():
				decisions[m] = _decide(m)

		# 3. path and move
		_move_phase(decisions)

		# 4. resolve actions
		_act_phase(decisions)

		# 5. record frame
		_record_frame(decisions)

		now += Sp.DT

	var a_alive := _living(team_a).size()
	var b_alive := _living(team_b).size()
	var winner := "draw"
	if a_alive > 0 and b_alive == 0:
		winner = "A"
	elif b_alive > 0 and a_alive == 0:
		winner = "B"
	elif a_alive != b_alive:
		winner = "A" if a_alive > b_alive else "B"

	var result := {
		"winner": winner, "duration": now, "log": event_log,
		"survivorsA": a_alive, "survivorsB": b_alive,
		"groundSize": ground, "obstacles": obstacles, "frames": frames,
	}
	_log_event({"kind": "end", "winner": winner, "duration": now})
	_free_navigation()
	return result


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# TICK — statuses/regen/cooldowns/attrition. Unchanged maths, ported from battle_sim.gd.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _tick_one(m) -> void:
	var inp := {
		"dt": Sp.DT, "now": now, "statuses": m.statuses, "mods": m.mods,
		"cooldowns": m.cooldowns, "wis": m.stats.get("WIS", 0.0),
		"isSupport": m.mana_role == "support", "mp": m.mp, "maxMp": float(m.max_mp),
		"hp": m.hp, "maxHp": float(m.max_hp), "ccResist": m.cc_resist,
		"lastCcAt": m.last_cc_at,
	}
	var out := TickLib.tick_unit(inp)
	m.hp = out["hp"]
	m.mp = out["mp"]
	m.statuses = out["statuses"]
	m.mods = out["mods"]
	m.cooldowns = out["cooldowns"]
	m.cc_resist = out["ccResist"]

	for kind in out["expired"]:
		_log_event({"kind": "status_expire", "unit": m.species_name, "side": m.side, "status": kind})

	var sd := TickLib.sudden_death_loss(now, float(m.max_hp), Sp.DT)
	if sd > 0.0:
		m.hp = maxf(0.0, m.hp - sd)

	if out["dead"] or m.hp <= 0.0:
		if m.alive:
			m.alive = false
			_log_event({"kind": "death", "unit": m.species_name, "side": m.side})


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# DECIDE — build ctx (docs/BUILD_CONTRACT.md §1), call the tree, or fall back.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _decide(m) -> Dictionary:
	var ctx := _build_ctx(m)
	var raw: Dictionary = {}
	var used_tree := false
	if _tree_script != null and _tree_script.has_method("tick"):
		var out = _tree_script.call("tick", ctx)
		if out is Dictionary:
			raw = out
			used_tree = true
	if not used_tree:
		raw = _fallback_decide(m, ctx)

	var enemies: Array = ctx["enemies"]
	var tid: int = int(raw.get("target_id", -1))
	var target_unit = enemies[tid] if (tid >= 0 and tid < enemies.size()) else null

	raw["_target_unit"] = target_unit
	raw["_ctx"] = ctx
	if not raw.has("action"):
		raw["action"] = "move"
	if not raw.has("desired_pos"):
		raw["desired_pos"] = ctx["pos"]
	if not raw.has("move_name"):
		raw["move_name"] = ""
	if not raw.has("intent"):
		raw["intent"] = "idle"
	if not raw.has("reason"):
		raw["reason"] = ""
	return raw


## The ctx contract, docs/BUILD_CONTRACT.md §1. ⚠️ Every key here is load-bearing — this is the
## sim/tree interface and must not silently drift from the spec.
func _build_ctx(m) -> Dictionary:
	var idx: int = unit_ids[m]
	var allies: Array = _living(_allies_of(m)).filter(func(u): return u != m)
	var enemies: Array = _living(_enemies_of(m))
	var ally_positions: Array = []
	for a in allies:
		ally_positions.append(spatial_state[a]["pos"])
	var enemy_positions: Array = []
	for e in enemies:
		enemy_positions.append(spatial_state[e]["pos"])
	var tac: Dictionary = _effective_tactics(m)
	var focus_id: int = _team_focus_for(m, enemies, enemy_positions, tac)
	return {
		"unit": m, "unit_id": idx, "pos": spatial_state[m]["pos"],
		"allies": allies, "ally_positions": ally_positions,
		"enemies": enemies, "enemy_positions": enemy_positions,
		"obstacles": obstacles, "tactics": tac,
		# ⚠️ The team's STARTING strength, not its current one. `allies` is filtered to the living,
		# so a tree cannot tell "we are five and all fine" from "we were five and are now two" —
		# and that difference is the whole trigger for collapsing a flank back onto the line.
		# Without it the collapse check compares living against living and can never fire, which
		# is a silent no-op rather than a visible bug.
		"team_size": _allies_of(m).size(),
		"personality": _personality_of(m),
		"team_focus_id": focus_id, "now": now,
		"blackboard": spatial_state[m]["blackboard"], "rng": rng,
	}


## ⚠️ FALLBACK ACTIVE — `scripts/personality.gd` (stream H) does not exist yet and
## `MonsterInstance` carries no `personality` field. Every `ctx.personality` is an empty
## Dictionary. The tree (and this file's own fallback) must treat a missing key as "no lean, use
## the axis default" rather than erroring. Replace the moment stream H lands.
func _personality_of(_m) -> Dictionary:
	return {}


func _team_focus_for(m, enemies: Array, enemy_positions: Array, tac: Dictionary) -> int:
	if _ai_script == null or not _ai_script.has_method("team_focus"):
		return -1
	var side_units: Array = []
	var side_positions: Array = []
	for u in (team_a if m.side == "A" else team_b):
		if u.alive:
			side_units.append(u)
			side_positions.append(spatial_state[u]["pos"])
	var fid = _ai_script.call("team_focus", side_units, side_positions, enemies, enemy_positions, tac)
	return int(fid) if fid is int else -1


## ⚠️ FALLBACK ACTIVE — `scripts/ai/monster_tree.gd` (stream B) does not exist yet, or does not
## expose `tick()`. "Nearest living enemy; move toward it" (task brief), stopping at 85% of this
## unit's own best attack reach. No target-priority, no kiting, no formation reasoning, no
## positional intent — that is the tree's job. This exists only so the sim runs and is measurable
## standalone.
func _fallback_decide(m, ctx: Dictionary) -> Dictionary:
	var enemies: Array = ctx["enemies"]
	if enemies.is_empty():
		return {
			"action": "idle", "desired_pos": ctx["pos"], "target_id": -1, "move_name": "",
			"intent": "idle", "reason": "no enemies remain",
		}
	var positions: Array = ctx["enemy_positions"]
	var my_pos: Vector2 = ctx["pos"]
	var best_i := 0
	var best_d := my_pos.distance_squared_to(positions[0])
	for i in range(1, enemies.size()):
		var d := my_pos.distance_squared_to(positions[i])
		if d < best_d:
			best_d = d
			best_i = i
	var target_pos: Vector2 = positions[best_i]
	var stand_off := _best_reach(m) * 0.85
	var dir := target_pos - my_pos
	var dist := dir.length()
	var desired := target_pos if dist <= stand_off else target_pos - dir.normalized() * stand_off
	return {
		"action": "move", "desired_pos": desired, "target_id": best_i, "move_name": "",
		"intent": "closing", "reason": "fallback: nearest living enemy (monster_tree.gd not present)",
	}


## The longest reach among this unit's ENEMY-targeted moves (basic included) — a rough "can I
## already act from here" signal for movement/closing-bonus purposes. Support/self/team/allEnemies
## moves are excluded so a long-range buff doesn't make a melee unit stand off.
func _best_reach(m) -> float:
	var best := Sp.reach_of(m.basic_attack, true)
	for mv in m.moveset:
		if mv.get("target", "enemy") != "enemy":
			continue
		var r := Sp.reach_of(mv, false)
		if r > best:
			best = r
	return best


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# MOVE — path via the baked navmesh, step along it, then separate overlapping bodies.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## ⚠️ `_apply_leash` WAS HERE AND HAS BEEN DELETED. Do not restore it.
##
## It used to clamp every unit's desired position into a circle around the living centroid of BOTH
## teams — 24% of board width at tight, 42% at loose, on a 160×88 arena — and was self-reinforcing:
## the anchor was wherever everyone already was, so units could never spread, so the centroid never
## moved, so units still could not spread. **That is the arithmetic cause of the user's core
## complaint** — "a big blob of monsters moving to a central area". No AI work could have fixed it
## while this ran; it was a hard geometric bound on every fight, not a tuning problem.
## `docs/ARENA_BLUEPRINT.md` §4's "confinement is intentional" framing is SUPERSEDED
## (`AUTOBATTLER_DESIGN.md` #36). Shape now comes from positional intent, formations and
## objectives — never from a positional clamp. `Spatial.engagement_radius()` still exists, renamed,
## as a LAYOUT-ONLY helper for `arena_layout.gd`'s cover placement; it must never gate movement.
func _move_phase(decisions: Dictionary) -> void:
	var new_positions: Dictionary = {}

	for m in _units:
		if not m.alive or m.is_incapacitated():
			continue
		var st: Dictionary = spatial_state[m]
		if st.get("casting") != null:
			new_positions[m] = st["pos"]  # rooted while casting
			st["_moved"] = false
			continue

		# ── knockback flight: control is lost until the distance is spent ──
		var kb = st.get("kb")
		if kb != null and float(kb.get("left", 0.0)) > 0.0:
			var fly := minf(Sp.KNOCKBACK_SPEED * Sp.DT, float(kb["left"]))
			kb["left"] = float(kb["left"]) - fly
			if float(kb["left"]) <= 0.0:
				st["kb"] = null
			new_positions[m] = st["pos"] + (kb["dir"] as Vector2) * fly
			st["_moved"] = true
			st["_still"] = 0
			st["run"] = 0.0
			continue

		var dec: Dictionary = decisions.get(m, {})
		if str(dec.get("action", "move")) == "idle":
			new_positions[m] = st["pos"]
			st["_moved"] = false
			continue

		var pos: Vector2 = st["pos"]
		var desired: Vector2 = dec.get("desired_pos", pos)
		var target = dec.get("_target_unit")

		# ── pathfinding: re-query only when the goal has moved meaningfully ──
		var nav_state: Dictionary = st["nav"]
		if _needs_repath(nav_state, desired):
			nav_state["path"] = _query_path(pos, desired)
			nav_state["goal"] = desired
			nav_state["i"] = 0
		var step_target: Vector2 = _next_path_point(nav_state, pos)
		# ⚠️ THE DEADZONE APPLIES TO THE GOAL, NEVER TO A WAYPOINT — or the two epsilons sandwich.
		# Found as 2 of 10 central_mass fights timing out with three survivors frozen at wall
		# corners, each wanting to close: the obstacle resolver parks a body ~1.1 from the wall,
		# inside the navmesh's 2.2 carve, so the path's first waypoint sits clamped nearby — and a
		# waypoint 1.0–1.1 away is too far to advance past (WAYPOINT_EPS 1.0) yet too close to
		# step toward (ARRIVE_EPS 1.1). Frozen, permanently, while reporting "closing to where it
		# can fight". An intermediate waypoint is somewhere you pass THROUGH; only the final goal
		# is somewhere you STOP.
		var nav_path: PackedVector2Array = nav_state.get("path", PackedVector2Array())
		var at_final: bool = nav_path.is_empty() or int(nav_state.get("i", 0)) >= nav_path.size() - 1
		var deadzone: float = Sp.ARRIVE_EPS if at_final else 0.001

		var target_pos: Vector2 = spatial_state[target]["pos"] if target != null else desired
		var dist_to_target: float = pos.distance_to(target_pos) if target != null else INF
		var reach := _best_reach(m)
		var in_reach := (target != null) and dist_to_target <= reach
		var advancing := true
		if target != null:
			advancing = (desired - target_pos).length() < (pos - target_pos).length() - 0.0001

		var to_step := step_target - pos
		var dist_move := to_step.length()
		var dex := float(m.stats.get("DEX", 0.0))
		var step := Sp.step_len(dex, advancing, dist_to_target, in_reach)
		# ── care/innate movement hooks ──
		var ufx: Dictionary = st.get("fx", {})
		if not advancing and ufx.has("fleetfoot"):
			# fleetfoot REPLACES the standard backpedal penalty rather than stacking on it.
			step *= float(ufx["fleetfoot"]) / Sp.BACKPEDAL_MULT
		if bool(st.get("weary", false)):
			step *= Innates.WEARY_SPEED
		# auraEnemySlow: the strongest slow whose owner's REACH covers this unit. Enemy auras use
		# the owner's reach, not AURA_RADIUS — "inside your reach" is the zoner identity.
		var slow := 1.0
		for e in _living(_enemies_of(m)):
			var efx: Dictionary = spatial_state[e].get("fx", {})
			if efx.has("auraEnemySlow") and (spatial_state[e]["pos"] as Vector2).distance_to(pos) <= _best_reach(e):
				slow = minf(slow, float(efx["auraEnemySlow"]))
		step *= slow

		# ⚠️ MOMENTUM AND AN ARRIVAL DEADZONE — the two halves of the wobble fix. See the block
		# above `Spatial.MAX_TURN_DEG_PER_SEC` for the measurement that motivated both. The heading
		# is STEERED toward the path point rather than snapped to it, and a step shorter than
		# ARRIVE_EPS is not taken at all: sub-body-radius stepping reads as jitter, never travel.
		var new_pos := pos
		if dist_move > deadzone:
			var free_turn: bool = int(st.get("_still", 99)) >= Sp.STATIONARY_TICKS_FOR_FREE_TURN
			var dir: Vector2 = Sp.steer(st.get("move_dir", to_step), to_step,
				step / Sp.DT, dist_move, free_turn)
			st["move_dir"] = dir
			new_pos = pos + dir * minf(step, dist_move)
			st["_move_dir_out"] = dir
			st["_moved"] = true
			st["_still"] = 0
			# chargeDmg: a sustained ADVANCING run arms the charge; any pause or retreat resets it.
			st["run"] = (float(st.get("run", 0.0)) + minf(step, dist_move)) if advancing else 0.0
		else:
			st["_moved"] = false
			st["_still"] = int(st.get("_still", 0)) + 1
			st["_move_dir_out"] = Vector2.ZERO

		# ⚠️ FACING IS NOT TRAVEL. It used to be assigned straight from the movement direction, so a
		# body physically rotated to point wherever it was walking — the user's report that monsters
		# "have to turn their whole body to move in that direction". A combatant watches its enemy
		# and backpedals or sidesteps; it turns its back only when it commits to leaving.
		#
		# ⚠️ AND THE SIM ALREADY ASSUMED THIS. `BACKPEDAL_MULT` (0.60) has always slowed units that
		# move while not advancing, and the renderer has always had a `retreat` state. The model was
		# right; only the presentation was welding the two together.
		#
		# ⚠️ THIS CHANGES A LIVE MECHANIC, DELIBERATELY. `facing_arc()` gives +15% rear damage and a
		# flanking accuracy bonus on the sides, so a unit that keeps its front to its target while
		# withdrawing no longer hands an assassin a free back. That is the intended reading: turning
		# to run is what exposes you. It does make the rear bonus harder to land than it was
		# yesterday, and that is a balance consequence to watch, not a silent side effect.
		var face_want: Vector2 = st.get("_move_dir_out", Vector2.ZERO)
		if target != null and dist_to_target <= Sp.FACE_TARGET_DIST:
			face_want = target_pos - pos
		if face_want.length_squared() > 0.000001:
			st["facing"] = Sp.steer(st.get("facing", face_want), face_want,
				Sp.FACE_TURN_REF_SPEED, 0.0, false)
		st["_advancing"] = advancing
		new_positions[m] = new_pos

	_separate(new_positions)

	for m in _units:
		if new_positions.has(m):
			spatial_state[m]["pos"] = _resolve_obstacles(Sp.clamp_to_ground(new_positions[m], team_size))


## ⚠️ THE LAST WORD ON WHERE A BODY MAY STAND. Found 2026-08-06 when the user WATCHED a monster
## walk through a wall: `central_mass` had units inside blocking obstacles on 3.95% of unit-ticks,
## up to 15.9 units deep. The cause is structural, not a tuning slip — NOTHING enforced obstacle
## collision on the final position. The navmesh only shapes PATH TARGETS; momentum steering arcs
## off the path (the turn-radius change made corner-cutting arcs routine), `_separate()` shoves
## bodies sideways, and neither result was ever checked against a wall.
##
## So this runs after separation and the ground clamp, on the position that will actually be
## written: push out of any blocking rect along the axis of least penetration. Two passes, because
## one push can land inside a neighbouring rect; deterministic order throughout (fixed rect order,
## no rng). Only "blocking" grade collides — soft/hard cover is stood IN, that is what it is for.
##
## ⚠️ The margin is deliberately HALF the body radius, not the full one. The navmesh already
## carves with the agent radius, so honest pathing never hugs a wall; this margin only catches
## trespass. A full-radius margin would make gaps between central_mass slabs narrower than the
## resolver believes they are, and a unit in such a gap would be pushed back and forth forever.
const OBSTACLE_RESOLVE_MARGIN := Sp.BODY_RADIUS * 0.5

func _resolve_obstacles(p: Vector2) -> Vector2:
	for _pass in range(2):
		var moved := false
		for o in obstacles:
			if str(o.get("grade", "")) != "blocking":
				continue
			var g: Rect2 = (o.get("rect", Rect2()) as Rect2).grow(OBSTACLE_RESOLVE_MARGIN)
			if not g.has_point(p):
				continue
			var c := g.get_center()
			var pen_x: float = g.size.x * 0.5 - absf(p.x - c.x)
			var pen_y: float = g.size.y * 0.5 - absf(p.y - c.y)
			var sx: float = 1.0 if p.x >= c.x else -1.0
			var sy: float = 1.0 if p.y >= c.y else -1.0
			if pen_x <= pen_y:
				p.x = c.x + sx * (g.size.x * 0.5 + 0.001)
			else:
				p.y = c.y + sy * (g.size.y * 0.5 + 0.001)
			moved = true
		if not moved:
			break
	return p


## One deterministic separation pass over the fixed unit order — not a physics solver, just enough
## to stop bodies stacking exactly on top of each other tick after tick. Ally bodies and enemy
## bodies are separated identically (both are "solid" — AUTOBATTLER_DESIGN.md #10); which one you
## fight is decided in `_act_phase`, not here.
## ⚠️ THE PUSH IS DAMPED. It used to apply the FULL overlap correction to both bodies every tick,
## so a crowded pair over-corrected, re-overlapped on the next step and pushed back — a ping-pong
## that the wobble probe sees as heading reversals and the eye sees as a shuffle. Half the
## correction converges just as surely and does not overshoot. Still not a physics solver, still
## one deterministic pass over the fixed unit order.
const SEPARATION_DAMP := 0.5

func _separate(new_positions: Dictionary) -> void:
	var min_dist := Sp.BODY_RADIUS * 2.0
	for i in range(_units.size()):
		var a = _units[i]
		if not a.alive or not new_positions.has(a):
			continue
		for j in range(i + 1, _units.size()):
			var b = _units[j]
			if not b.alive or not new_positions.has(b):
				continue
			var pa: Vector2 = new_positions[a]
			var pb: Vector2 = new_positions[b]
			var d: float = (pa as Vector2).distance_to(pb)
			if d <= 0.0001:
				var push := Vector2(min_dist * 0.5, 0.0)  # coincident — deterministic nudge, no rng
				new_positions[a] = pa + push
				new_positions[b] = pb - push
			elif d < min_dist:
				var push2 := (pa - pb).normalized() * (min_dist - d) * 0.5 * SEPARATION_DAMP
				new_positions[a] = pa + push2
				new_positions[b] = pb - push2


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# ACT — resolve an in-progress cast, or start a new one.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## ⚠️ THE BLOCKING RULE, AS A STRUCTURAL DEFAULT (AUTOBATTLER_DESIGN.md §9, §12 #30). The ordered
## target is never a blocker — it's a destination, and the tree/fallback's `desired_pos` keeps
## aiming at it regardless. But because bodies are solid (`_separate`), a unit whose path is
## physically obstructed can end up with some OTHER living enemy in reach without ever having
## chosen it. This is the "attack it while pressing on" half of #9's rule, implemented once, here,
## underneath whatever the tree decides — so it applies whether or not `monster_tree.gd` exists.
## ⚠️ NOT YET A TACTIC. §12 #30 later split this into `bullThrough`/`engageIntercept` as a
## player-chosen axis; that choice belongs to the tree (§7 of docs/TACTICS_TREES.md), which can
## override this by simply returning the blocker as its own `target_id` (in which case this
## function is a no-op — the ordered target already IS the thing in reach). Until the tree makes
## that choice, every unit behaves as an always-`bullThrough`-with-opportunistic-swings default.
func _resolve_attack_target(m, ordered_target):
	if ordered_target != null and ordered_target.alive:
		var reach := _best_reach(m)
		var d: float = (spatial_state[m]["pos"] as Vector2).distance_to(spatial_state[ordered_target]["pos"])
		if d <= reach:
			return ordered_target
	var mp: Vector2 = spatial_state[m]["pos"]
	var reach2 := _best_reach(m)
	var best = null
	var best_d := INF
	for e in _living(_enemies_of(m)):
		var d2 := mp.distance_to(spatial_state[e]["pos"])
		if d2 <= reach2 and d2 < best_d:
			best_d = d2
			best = e
	return best if best != null else ordered_target


func _act_phase(decisions: Dictionary) -> void:
	for m in _units:
		if not m.alive or m.is_incapacitated():
			continue
		var st: Dictionary = spatial_state[m]

		if st.get("casting") != null:
			var cast: Dictionary = st["casting"]
			# ⚠️ A LONG CAST NEEDS A SUSTAINED VIEW — this is the mechanic that finally gives cover
			# a REASON to exist. Everything else about cover is symmetric: a blocking piece costs
			# both sides the same accuracy, so no unit ever had a motive to stand behind one.
			# Interruption is not symmetric. It destroys the caster's TIME, and time is what a WoW
			# pillar actually takes. Cover becomes valuable the moment it can WASTE something.
			#
			# ⚠️ AND IT IS CONSISTENT WITH SHOTS PASSING THROUGH COVER, not a contradiction of it.
			# A quick strike fires through a wall at a heavy accuracy penalty; a slow, telegraphed
			# cast needs to keep seeing its target. That distinction is legible in one sentence,
			# which is the bar for a game the player only watches.
			if _cast_broken_by_cover(m, cast):
				event_log.append({
					"kind": "interrupt", "unit": m.species_name, "side": m.side,
					"move": str((cast["move"] as Dictionary).get("name", "")),
					"reason": "lost sight of its target behind cover",
				})
				st["casting"] = null
				continue
			cast["remaining"] = float(cast["remaining"]) - Sp.DT
			if cast["remaining"] <= 0.0:
				_resolve_cast(m, cast)
				st["casting"] = null
			continue

		if m.has_status("fear"):  # noAttack — same as battle_sim.gd
			continue

		var dec: Dictionary = decisions.get(m, {})
		if str(dec.get("action", "move")) == "idle":
			continue

		var ordered_target = dec.get("_target_unit")
		var attack_target = _resolve_attack_target(m, ordered_target)
		if attack_target == null:
			continue

		var ctx: Dictionary = dec.get("_ctx", {})
		var tac: Dictionary = ctx.get("tactics", _effective_tactics(m))
		var move_name: String = str(dec.get("move_name", ""))
		var picked: Dictionary = _choose_move_for(m, attack_target, tac, move_name)
		if picked.is_empty():
			continue
		_start_cast(m, picked)


## Ready-move selection, ported from battle_sim.gd's `_act` (cooldown/mp/manaPolicy/temperament
## filter, then "strongest ready move" priority with the same 2-way random tie-break), PLUS the
## spatial legality gate this rewrite exists to add — AND, new this pass, an optional NAMED move
## the tree asked for (`move_name`, docs/BUILD_CONTRACT.md §1's `Cast(move, target)` leaf). If the
## named move isn't legal/ready, this falls through to the same default the fallback path uses,
## rather than doing nothing — a tree that asks for an unready move still gets SOME action if one
## is available, matching "the sim decides whether it is legal", not "whether to try at all".
func _choose_move_for(m, target, tac: Dictionary, move_name: String = "") -> Dictionary:
	if target == null:
		return {}

	if not m.has_status("silence"):
		if move_name != "":
			for mv in m.moveset:
				if str(mv.get("name", "")) != move_name:
					continue
				var cd0: float = m.cooldowns.get(mv["name"], 0.0)
				var cost0: float = DeriveMath.field_mp_cost(mv)
				if cd0 > 0.0 or m.mp < cost0:
					break
				var kind0: String = mv.get("target", "enemy")
				if kind0 == "enemy" or kind0 == "ally":
					var candidate0 = _resolve_single_target(m, kind0, target, mv)
					if candidate0 == null:
						break
					if not _spatially_legal(m, candidate0, mv, false):
						break
					return {"mv": mv, "is_basic": false, "target_kind": kind0, "target": candidate0}
				return {"mv": mv, "is_basic": false, "target_kind": kind0,
					"target": _resolve_single_target(m, kind0, target, mv)}
			# named move not known / not ready / not legal — fall through to the default below.

		var ready: Array = []
		for mv in m.moveset:
			var cd: float = m.cooldowns.get(mv["name"], 0.0)
			var cost: float = DeriveMath.field_mp_cost(mv)
			if cd > 0.0 or m.mp < cost:
				continue
			if tac.get("manaPolicy", "normal") == "conserve" and (m.mp - cost) < 0.25 * float(m.max_mp):
				continue
			if tac.get("temperament", "") == "cautious" \
					and mv.get("effects", {}).has("recoil") and m.hp_frac() < 0.4:
				continue
			var kind: String = mv.get("target", "enemy")
			if kind == "enemy" or kind == "ally":
				var candidate = _resolve_single_target(m, kind, target, mv)
				if candidate == null or not _spatially_legal(m, candidate, mv, false):
					continue
			ready.append(mv)
		if not ready.is_empty():
			ready.sort_custom(func(a, b): return float(a.get("power", 0)) > float(b.get("power", 0)))
			var chosen: Dictionary = ready[rng.randi_range(0, mini(1, ready.size() - 1))]
			var kind2: String = chosen.get("target", "enemy")
			return {
				"mv": chosen, "is_basic": false, "target_kind": kind2,
				"target": _resolve_single_target(m, kind2, target, chosen),
			}

	var basic_cd: float = m.cooldowns.get("__basic__", 0.0)
	if basic_cd > 0.0:
		return {}
	if not _spatially_legal(m, target, m.basic_attack, true):
		return {}
	var mv2: Dictionary = m.basic_attack
	if not mv2.has("name"):
		mv2["name"] = "Attack"
		mv2["target"] = "enemy"
	return {"mv": mv2, "is_basic": true, "target_kind": "enemy", "target": target}


## Who a non-enemy single-target move actually resolves against. Positions don't change this for
## "ally"/"self", so it's safe to resolve at selection time and store it for the cast to use later.
func _resolve_single_target(m, kind: String, enemy_target, mv_hint = null):
	match kind:
		"enemy":
			return enemy_target
		"ally":
			var allies: Array = _living(_allies_of(m)).filter(func(u): return u != m)
			if allies.is_empty():
				return m
			# ⚠️ A CLEANSE MUST GO TO A CONTROLLED ALLY, NOT THE LOWEST-HP ONE. Default ally
			# resolution is "whoever is hurt most", which is right for a heal and wrong for a
			# cleanse — the stunned ally is frequently at full health, and cleansing the bleeding
			# one instead wastes the cast entirely. Fixed iteration order, so still deterministic.
			if bool((mv_hint.get("effects", {}) if mv_hint != null else {}).get("cleanse", false)):
				for a in allies:
					for st in a.statuses:
						if StatusMathLib.HARD_CONTROL.has(st["kind"]):
							return a
			return _pick_lowest_hp(allies)
		"self":
			return m
		_:
			return enemy_target


func _spatially_legal(m, target, mv: Dictionary, is_basic: bool) -> bool:
	var from: Vector2 = spatial_state[m]["pos"]
	var to: Vector2 = spatial_state[target]["pos"]
	var dist := from.distance_to(to)
	var reach := Sp.reach_of(mv, is_basic)
	if dist > reach:
		return false
	# ⚠️ MINIMUM RANGE IS AN ANTI-KITING RULE AND MUST NOT APPLY TO FRIENDLY TARGETS.
	# `Spatial.minimum_range` exists so "a ranged unit pinned inside this has to fight rather than
	# run further" (ENGAGEMENT_DESIGN Family B1) — it is about denying a KITER an infinite retreat.
	# Applied to a self/ally/team move it means the opposite of anything intended: you cannot heal,
	# ward or cleanse the ally standing NEXT TO YOU.
	#
	# MEASURED: Clarity authors range 8.0, lifted x4 by REACH_SCALE to 32.0; 32 >= 16 so the rule
	# engages at 32 * 0.22 = 7.04 units. Allies in formation stand far closer than 7, so the tree
	# would correctly request a cleanse, `_choose_move_for` would silently reject it as illegal, and
	# fall through to the default "strongest ready move". The cleanse never fired, and nothing
	# logged a reason.
	var friendly: bool = str(mv.get("target", "enemy")) in ["self", "ally", "team"]
	if not friendly and dist < Sp.minimum_range(reach, is_basic):
		return false
	# ⚠️ A BLOCKED LINE NO LONGER FORBIDS THE SHOT — it makes it much worse (`Sp.COVER_BLOCK_ACC`,
	# applied through `_geometry`'s accuracy penalty like every other grade). Rejecting the move
	# here was the on/off switch `SPATIAL_COMBAT_DESIGN.md` §2 says cover should never have been,
	# and it made hiding self-defeating: a sheltered unit could not fight, so every unit avoided
	# shelter. Measured at 0.22x a random-position baseline before this change.
	return true


func _start_cast(m, picked: Dictionary) -> void:
	var mv: Dictionary = picked["mv"]
	var is_basic: bool = picked["is_basic"]
	# ⚠️ Cost/cooldown are paid HERE, at cast START, not at resolution — a deliberate deviation from
	# battle_sim.gd (no windup, pays after resolving). A whiffed or interrupted shot still cost its
	# mana/cooldown. Flagged for a design sign-off, same as the previous version of this file.
	_pay_and_cooldown(m, mv, is_basic)
	# ⚠️ The ported value is the FLOOR, never the answer — `Sp.windup_of` only ever lengthens, so a
	# move nobody deliberately telegraphed behaves exactly as it did before.
	var ct := Sp.windup_of(mv, DeriveMath.cast_time_of(mv))
	# windupMult (innate): the quickcaster's casts arrive before the answer does.
	ct *= float((spatial_state[m].get("fx", {}) as Dictionary).get("windupMult", 1.0))
	spatial_state[m]["casting"] = {
		"move": mv, "is_basic": is_basic,
		"target_kind": picked.get("target_kind", "enemy"),
		"single_target": picked.get("target"),
		"remaining": ct,
		# Kept so `_cast_broken_by_cover` can tell an instant from a real windup — an instant has
		# no window in which to be interrupted.
		"total": ct,
		# Was the line clear when this began? Only then can losing it be an interruption rather
		# than a permanent state the caster already accepted.
		"los_at_start": _los_clear_to(m, picked.get("target")),
		"interruptible": Sp.is_interruptible(ct),
	}


## Resolve a completed windup. ⚠️ PORTED AS-IS FROM `battle_sim.gd`'s `_act`: only `target ==
## "team"` moves go through `_apply_team_effect` (the real buff/heal/cleanse path). "ally" and
## "self" moves fall through to the SAME generic `_resolve_hit` combat-strike resolution as an
## attack on an enemy — aimed at a friendly target. Reads like a latent gap in the reference sim
## rather than a deliberate choice; reproduced rather than silently fixed, per this project's own
## "port its resolution logic, do not rewrite the maths" doctrine.
func _resolve_cast(m, cast: Dictionary) -> void:
	var mv: Dictionary = cast["move"]
	var is_basic: bool = cast["is_basic"]
	match cast["target_kind"]:
		"allEnemies":
			# ⚠️ Coverage is the DEFENDING side's formation-based approximation
			# (`TacticsScript.aoe_coverage`), not a real AoE radius against `mv` — move-authored
			# area geometry is CLAUDE.md roadmap item 5, not yet built anywhere in this codebase.
			var def_plan: Dictionary = team_b_plan if m.side == "A" else team_a_plan
			var hit_any := false
			var aoe_reach := Sp.reach_of(mv, is_basic)
			for e in TacticsScript.aoe_coverage(_living(_enemies_of(m)), def_plan):
				# ⚠️ THE FAN-OUT WAS POSITION-BLIND — found when the user asked about a tracer
				# spanning the whole arena (2026-08-06). `_spatially_legal` range-gates the PRIMARY
				# target, but this loop then hit every covered enemy ANYWHERE on the board:
				# `aoe_coverage` is a formation-based fraction, not geometry (roadmap item 5), so a
				# voice AoE cast at reach 53 was landing on bodies 250 units away. The VFX tracer
				# made the abstraction visible — legibility catching a sim bug. An AoE now reaches
				# only what the MOVE's own authored range covers, measured from the caster.
				if (spatial_state[e]["pos"] as Vector2).distance_to(spatial_state[m]["pos"]) > aoe_reach:
					continue
				var geo := _geometry(m, e)
				_resolve_hit(m, e, mv, is_basic, geo["acc_penalty"], geo["flank_bonus"],
					geo["facing_mult"], geo["facing_arc"], bool(geo.get("open_field", false)))
				hit_any = true
			spatial_state[m]["_just_hit"] = hit_any
		"team":
			var own_plan: Dictionary = team_a_plan if m.side == "A" else team_b_plan
			for a in TacticsScript.aura_coverage(_living(_allies_of(m)), own_plan):
				_apply_team_effect(m, a, mv)
			spatial_state[m]["_just_hit"] = true
		"self", "ally":
			# ⚠️ THIS BRANCH DID NOT EXIST AND A FIFTH OF THE ABILITY POOL WAS INERT BECAUSE OF IT.
			# `self`/`ally` casts fell through to the default arm below and were resolved by
			# `_resolve_hit` — the COMBAT-STRIKE path, which only knows how to apply DEBUFFS
			# (`defDebuff`/`atkDebuff`/`accDebuff`) and statuses. Every friendly effect —
			# `guard`, `ward`, `atkBuff`, `defBuff`, `dodgeBuff`, `accBuff`, `hpRegenBuff`,
			# `thorns`, `heal`, `cleanse` — lives in `_apply_team_effect` and was never reached.
			#
			# MEASURED before the fix (`scripts/_probe_cleanse.gd`): 25 self/ally buff moves cast
			# in one fight, ZERO buff events in the log. Those units spent the mana, burned the
			# cooldown and gave up the action for nothing. 29 of 141 moves are affected —
			# Guard, Bracer, Shield Wall, Enrage, Last Stand, Riposte, Vanish, Sidestep,
			# Acrobatics, Focus Aim, Interpose, Steady Vigil, and both single-target cleanses.
			#
			# ⚠️ The gap was KNOWN and documented as "reproduced rather than silently fixed" under
			# this project's port-faithfully doctrine. That doctrine is right for combat MATHS; it
			# was wrong here, because this is not a maths difference — the effect simply never
			# fires, so no amount of tuning could ever surface it. `battle_sim.gd` has the same
			# shape and should be checked before the two engines are compared again.
			var self_target = cast.get("single_target")
			if self_target == null and str(cast["target_kind"]) == "self":
				self_target = m
			if self_target != null and self_target.alive:
				_apply_team_effect(m, self_target, mv)
				spatial_state[m]["_just_hit"] = true
		_:
			var target = cast.get("single_target")
			if target != null and target.alive:
				# ⚠️ RANGED AND MAGIC FLY (user decision 2026-08-06: MECHANICAL projectiles — the
				# hit resolves when the projectile ARRIVES, with arrival-time geometry). The
				# windup was the telegraph; the flight is the last chance for the world to
				# change — cover break, a facing turn, a death. Melee/voice stay instant: a
				# sword has no flight and a shout arrives at the speed of sound.
				var pch := str(mv.get("channel", "melee"))
				if Sp.PROJECTILE_SPEED.has(pch):
					_projectiles.append({
						"id": _next_proj_id, "atk": m, "tgt": target, "mv": mv,
						"is_basic": is_basic, "pos": Vector2(spatial_state[m]["pos"]),
						"kind": pch,
					})
					_next_proj_id += 1
					spatial_state[m]["_just_hit"] = true
				else:
					var geo := _geometry(m, target)
					_resolve_hit(m, target, mv, is_basic, geo["acc_penalty"], geo["flank_bonus"],
						geo["facing_mult"], geo["facing_arc"], bool(geo.get("open_field", false)))
					spatial_state[m]["_just_hit"] = true


## Cover penalty (points) + flanking bonus for a strike from `m` to `target`, computed at
## resolution time from CURRENT positions (the caster may have been legal when the cast started
## and the target may since have repositioned — reach/minimum-range are not re-validated at
## resolution, only the accuracy inputs are recomputed).
## True when a cast in progress has lost line of sight to its single target.
## ⚠️ ONLY single-target casts, and only ones with a real cast TIME. An instant has no window in
## which to be interrupted, and an area move is aimed at ground rather than at a creature — making
## either interruptible would be punishing something the player cannot read.
## Hard control lands on a unit mid-windup: the cast dies. ⚠️ Only a TELEGRAPHED cast can be
## interrupted (`Sp.is_interruptible`) — a kit built on fast cheap moves buys immunity to
## interruption with its damage ceiling, which is WoW's own rule and a trade worth having.
func _interrupt_if_casting(victim, by, status_kind: String) -> void:
	if not StatusMathLib.HARD_CONTROL.has(status_kind):
		return
	var st: Dictionary = spatial_state.get(victim, {})
	var cast = st.get("casting")
	if cast == null or not bool(cast.get("interruptible", false)):
		return
	# castSteady (innate, chance-based per user direction 2026-08-06): a chance to shrug off a
	# CONTROL interrupt. LOS breaks are handled elsewhere and always land — you can out-position
	# a steady caster, you just cannot always out-stun one.
	var steady := float((st.get("fx", {}) as Dictionary).get("castSteady", 0.0))
	if steady > 0.0 and rng.randf() * 100.0 < steady:
		_log_event({
			"kind": "cast_steady", "unit": victim.species_name, "side": victim.side,
			"move": str((cast["move"] as Dictionary).get("name", "")),
			"reason": "%s shrugged off %s's %s mid-cast" % [victim.species_name, by.species_name, status_kind],
		})
		return
	_log_event({
		"kind": "interrupt", "unit": victim.species_name, "side": victim.side,
		"move": str((cast["move"] as Dictionary).get("name", "")),
		"reason": "%s's %s cut the cast short" % [by.species_name, status_kind],
	})
	st["casting"] = null


func _los_clear_to(m, target) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	return not bool(Sp.cover_between(
		spatial_state[m]["pos"], spatial_state[target]["pos"], obstacles)["blocked"])


func _cast_broken_by_cover(m, cast: Dictionary) -> bool:
	var target = cast.get("single_target")
	if target == null or not is_instance_valid(target) or not target.alive:
		return false
	var mv: Dictionary = cast.get("move", {})
	if str(mv.get("target", "enemy")) != "enemy":
		return false                       # never interrupt a heal or a buff on an ally
	if float(cast.get("total", 0.0)) <= 0.0:
		return false                       # instant — no window to interrupt
	# ⚠️ ONLY A LINE THAT WAS CLEAR WHEN THE CAST BEGAN CAN BE BROKEN. This is the difference
	# between a mechanic and a deadlock, and it was measured: interrupting ANY blocked cast let
	# both sides hide behind the same mass, break each other's casts forever, and run out the
	# 180-second clock with nobody dead — `central_mass` hit MAX_DURATION at 1801 frames with 881
	# interrupts. A standoff where neither side can act is not tension, it is a hang.
	#
	# Requiring the line to have STARTED clear makes the mechanic asymmetric in the right
	# direction: it rewards the unit that MOVES into cover during someone's windup, and never
	# punishes one that simply chose to fight from cover. That is also exactly the WoW behaviour
	# the whole idea came from — you break line of sight DURING their cast, you do not win by
	# standing still.
	if not bool(cast.get("los_at_start", true)):
		return false
	return bool(Sp.cover_between(
		spatial_state[m]["pos"], spatial_state[target]["pos"], obstacles)["blocked"])


## PROJECTILE FLIGHT — homing (the autobattler standard: a fireball tracks its mark; "dodging"
## is what the accuracy/cover/facing inputs are for, and they are recomputed at ARRIVAL). A
## projectile whose target dies mid-flight fizzles. The CASTER dying does not recall the arrow —
## it was loosed. Deterministic: fixed order, no rng in the flight itself.
func _tick_projectiles() -> void:
	if _projectiles.is_empty():
		return
	var kept: Array = []
	for pr in _projectiles:
		var tgt = pr["tgt"]
		if not tgt.alive:
			continue   # fizzle — the mark fell before the shot landed
		var tpos: Vector2 = spatial_state[tgt]["pos"]
		var pos: Vector2 = pr["pos"]
		var speed := float(Sp.PROJECTILE_SPEED.get(str(pr["kind"]), 60.0))
		var step := speed * Sp.DT
		if pos.distance_to(tpos) <= step + Sp.BODY_RADIUS:
			# ARRIVAL: resolve with geometry as it is NOW — cover walked behind, a back turned,
			# a weary stagger — all of it counts at the moment the projectile lands.
			var atk = pr["atk"]
			var geo := _geometry(atk, tgt)
			_resolve_hit(atk, tgt, pr["mv"], pr["is_basic"], geo["acc_penalty"],
				geo["flank_bonus"], geo["facing_mult"], geo["facing_arc"],
				bool(geo.get("open_field", false)))
			continue
		pr["pos"] = pos + (tpos - pos).normalized() * step
		kept.append(pr)
	_projectiles = kept


func _geometry(m, target) -> Dictionary:
	var from: Vector2 = spatial_state[m]["pos"]
	var to: Vector2 = spatial_state[target]["pos"]
	var cover := Sp.cover_between(from, to, obstacles)
	var other_engagers := 0
	for a in _living(_allies_of(m)):
		if a == m:
			continue
		if spatial_state[a]["pos"].distance_to(to) <= Sp.FLANK_MELEE_RANGE:
			other_engagers += 1
	# ⚠️ FLANKING IS NOW WHERE YOU STAND, NOT HOW MANY OF YOU THERE ARE. The old rule
	# (`is_flanking`: outnumbering an unsupported target within 14 units) awarded the bonus to a
	# unit standing directly in FRONT of its victim, which is not a flank in any sense a player
	# would recognise. `facing` has been in the frame stream since the spatial layer was built and
	# nothing read it; this is the mechanic that does.
	var tfx: Dictionary = spatial_state[target].get("fx", {})
	var arc := Sp.facing_arc(from, to, spatial_state[target].get("facing", Vector2.ZERO),
		float(tfx.get("rearArcDeg", 0.0)))
	return {
		"acc_penalty": cover["accPenalty"],
		"open_field": not bool(cover["blocked"]) and float(cover["accPenalty"]) <= 0.0,
		"flank_bonus": Sp.facing_acc_bonus(arc),
		"facing_arc": arc,
		"facing_mult": Sp.facing_damage_mult(arc),
		# Kept because the surrounding-the-target idea is still real and worth measuring separately
		# from the geometric one — it just is not what "flanking" should mean.
		"other_engagers": other_engagers,
	}


func _shot_kind(channel: String) -> String:
	if channel == "melee" or channel == "ranged" or channel == "magic":
		return channel
	return "support"  # "support" and "voice" both map here


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# RESOLUTION — unchanged maths, ported from battle_sim.gd's `_resolve_hit` / `_apply_team_effect`,
# extended with the spatial accPenalty/flankBonus inputs and a `shots` entry for the frame stream.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _resolve_hit(attacker, target, mv: Dictionary, is_basic: bool, acc_penalty_spatial: float,
		flank_bonus: float, facing_mult: float = 1.0, facing_arc: String = "front",
		open_field: bool = false) -> void:
	# ── THE CARE LOOP'S TEETH (innate_fx.gd) — every adjustment rides resolve_strike's own
	# inputs or wraps its output; the contracted maths is untouched. ──
	var afx: Dictionary = spatial_state.get(attacker, {}).get("fx", {})
	var tfx: Dictionary = spatial_state.get(target, {}).get("fx", {})
	var ast: Dictionary = spatial_state.get(attacker, {})
	var apos: Vector2 = ast.get("pos", Vector2.ZERO)
	var tpos: Vector2 = spatial_state.get(target, {}).get("pos", Vector2.ZERO)
	# coverPierce eats the COVER part of the accuracy penalty, never the status part.
	if afx.has("coverPierce"):
		acc_penalty_spatial *= 1.0 - clampf(float(afx["coverPierce"]), 0.0, 1.0)
	# rearArcBonus stacks onto the standard rear damage bonus.
	if facing_arc == "rear" and afx.has("rearArcBonus"):
		facing_mult += float(afx["rearArcBonus"])
	# One composed innate damage multiplier.
	var imult := float(afx.get("dmgMult", 1.0))
	if str(mv.get("channel", "")) == "magic":
		imult *= float(afx.get("magicDmgMult", 1.0))
	if attacker.hp_frac() < 0.3:
		imult *= float(afx.get("lowHpDmgMult", 1.0))
	if attacker.hp_frac() > 0.7:
		imult *= float(afx.get("highHpDmgMult", 1.0))
	if target.hp_frac() < 0.3:
		imult *= float(afx.get("executeMult", 1.0))
	if not bool(ast.get("hit_done", false)):
		imult *= float(afx.get("firstHitMult", 1.0))
	if open_field:
		imult *= float(afx.get("openFieldDmg", 1.0))
	if float(ast.get("run", 0.0)) >= Innates.CHARGE_RUN_DIST:
		imult *= float(afx.get("chargeDmg", 1.0))
		ast["run"] = 0.0    # the charge is spent on the collision
	if int(ast.get("_still", 0)) >= Innates.BRACE_TICKS:
		imult *= float(afx.get("braceDmg", 1.0))
	# predator: the target is moving AWAY from the attacker.
	if afx.has("predatorDmg"):
		var tmd: Vector2 = spatial_state.get(target, {}).get("_move_dir_out", Vector2.ZERO)
		if tmd.length_squared() > 0.000001 and tmd.dot((tpos - apos).normalized()) > 0.35:
			imult *= float(afx["predatorDmg"])
	# duel: nobody else near either of us.
	if afx.has("duelDmg"):
		var alone := true
		for u in _units:
			if u == attacker or u == target or not u.alive:
				continue
			var up: Vector2 = spatial_state[u]["pos"]
			if up.distance_to(apos) <= Innates.DUEL_RADIUS or up.distance_to(tpos) <= Innates.DUEL_RADIUS:
				alone = false
				break
		if alone:
			imult *= float(afx["duelDmg"])
	# pack: an ally hit this target within the window.
	if afx.has("packDmg"):
		var rec: Dictionary = _pack_hits.get(target, {})
		if not rec.is_empty() and rec.get("side") == attacker.side and rec.get("by") != attacker 				and _tick_no - int(rec.get("tick", -999)) <= Innates.PACK_WINDOW_TICKS:
			imult *= float(afx["packDmg"])
	# team auras (radius-bound — the spatial answer to the range question TS left open).
	imult *= Innates.aura_mult("auraDmgMult", apos, _living(_allies_of(attacker)), spatial_state)
	# enemy-facing debuff auras hit the ATTACKER standing near their owners.
	var enemy_acc := Innates.aura_sum("enemyAccDebuff", apos, _living(_enemies_of(attacker)), spatial_state)
	var enemy_dmg := Innates.aura_sum("enemyDmgDebuff", apos, _living(_enemies_of(attacker)), spatial_state)
	if enemy_dmg > 0.0:
		imult *= maxf(0.0, 1.0 - enemy_dmg / 100.0)
	# accuracy / dodge adjustments, folded into the strike inputs below.
	var innate_acc := float(afx.get("acc", 0.0)) - enemy_acc 		- Innates.aura_sum("enemyDodgeDebuff", tpos, _living(_allies_of(attacker)), spatial_state) * 0.0
	if bool(ast.get("weary", false)):
		innate_acc -= Innates.WEARY_ACC
	if afx.has("homeGroundAcc") and apos.distance_to(ast.get("station", apos)) <= Innates.HOME_RADIUS:
		innate_acc += float(afx["homeGroundAcc"])
	var innate_dodge := float(tfx.get("dodge", 0.0)) 		+ Innates.aura_sum("auraDodge", tpos, _living(_allies_of(target)), spatial_state) 		- Innates.aura_sum("enemyDodgeDebuff", tpos, _living(_enemies_of(target)), spatial_state)
	var innate_crit := float(afx.get("crit", 0.0))
	# flat DR on the TARGET: own + aura + homeGround, subtracted per strike after the maths.
	var flat_dr := float(tfx.get("flatDR", 0.0)) 		+ Innates.aura_sum("auraFlatDR", tpos, _living(_allies_of(target)), spatial_state)
	var tst: Dictionary = spatial_state.get(target, {})
	if tfx.has("homeGroundDR") and tpos.distance_to(tst.get("station", tpos)) <= Innates.HOME_RADIUS:
		flat_dr += float(tfx["homeGroundDR"])
	# innate pierce rides the MOVE's own fx channel (damage.gd reads pierce from the move).
	var mv_eff := mv
	if afx.has("pierce"):
		mv_eff = mv.duplicate(true)
		var mfx: Dictionary = mv_eff.get("fx", {}) if mv_eff.get("fx") is Dictionary else {}
		mfx = mfx.duplicate()
		mfx["pierce"] = minf(1.0, float(mfx.get("pierce", 0.0)) + float(afx["pierce"]))
		mv_eff["fx"] = mfx
	mv = mv_eff
	var fx: Dictionary = mv.get("effects", {})
	var mit_stat: float = target.stats.get("CON", 0.0) if (mv["channel"] == "melee" or mv["channel"] == "ranged") else target.stats.get("WIS", 0.0)

	var acc_penalty := acc_penalty_spatial
	if attacker.has_status("blind"):
		acc_penalty += StatusMathLib._rule("blind").get("accPenalty", 0.0)
	if attacker.has_status("confusion"):
		acc_penalty += StatusMathLib._rule("confusion").get("accPenalty", 0.0)

	# ⚠️ bonusVsStatus WAS HARDCODED DEAD. The inp below passed `defHasBonusStatus: false` as a
	# literal, so all 10 detonator moves (Twist the Knife, Detonate, Virulence...) shipped without
	# their entire mechanic — a combo payoff that never paid. Found in the 2026-08-06 pool audit.
	# `consume: true` on all 10: the status is SPENT by the detonation, so landing one both
	# cashes the bonus and clears the debuff — the payoff has a cost, which is what makes the
	# combo a decision rather than a stacking bonus.
	var bvs = (mv.get("effects", {}) as Dictionary).get("bonusVsStatus") if mv.get("effects") is Dictionary else null
	var bvs_armed: bool = bvs is Dictionary and target.has_status(str((bvs as Dictionary).get("kind", "")))

	var dmg_taken_mult := 1.0
	if target.has_status("vulnerable"):
		dmg_taken_mult *= StatusMathLib._rule("vulnerable").get("damageTakenMult", 1.0)

	var hits := 1
	if fx.has("hits"):
		var h: Array = fx["hits"]
		hits = rng.randi_range(int(h[0]), int(h[1]))

	var total_dmg := 0
	var last_out := {}
	for i in range(maxi(1, hits)):
		if not target.alive:
			break
		var inp := {
			"move": mv,
			"rolls": {"acc": rng.randf(), "crit": rng.randf(), "variance": rng.randf()},
			"accPenalty": acc_penalty, "accMod": _mod_sum(attacker, "accMod") + innate_acc,
			"dodgeMod": _mod_sum(target, "dodgeMod") + innate_dodge, "flankBonus": flank_bonus + innate_crit,
			"defHasAttacked": target.has_acted, "attackerHpFrac": attacker.hp_frac(),
			"attackerWard": _mod_sum(attacker, "ward"), "defHpFrac": target.hp_frac(),
			"defHasBonusStatus": bvs_armed, "defMaxHp": float(target.max_hp),
			"behindMult": 1.0, "falloff": 1.0,
			"atkMult": 1.0 + _mod_sum(attacker, "atkMultBonus"),
			"defMit": mit_stat, "defMitDebuff": _mod_sum(target, "defMitDebuff"),
			"defBlocking": false, "defStatusDmgTaken": dmg_taken_mult,
			"defDmgTakenMod": 1.0, "defGuard": _mod_sum(target, "guard"),
			"defWard": _mod_sum(target, "ward"), "atk": attacker.stats.get(mv.get("stat", "STR"), 0.0),
			"now": now,
		}
		var out := DamageMath.resolve_strike(inp)
		last_out = out
		if out["hit"]:
			# ⚠️ THE REAR BONUS IS APPLIED HERE, OUTSIDE `Damage.resolve_strike`, ON PURPOSE.
			# `damage.gd` is under an exact-equality port contract against the TypeScript
			# (`combat.json`, 62 cases) — adding a term inside it would break 62 contract cases and
			# claim the TypeScript does something it does not. Facing is a SPATIAL concept and the
			# spatial layer is where it belongs; `damage.gd` stays a faithful port.
			out["dmg"] = int(round(float(out["dmg"]) * facing_mult * imult))
			# Innate flat DR comes off each strike AFTER the maths — the contracted formula has no
			# input for it, and a floor of 0 (not 1) so a fully-armoured graze can be a zero.
			out["dmg"] = maxi(0, int(out["dmg"]) - int(round(flat_dr)))
			# ⚠️ `toHp` IS WHAT ACTUALLY SUBTRACTS HEALTH, AND UNTIL 2026-08-06 NOTHING RESCALED
			# IT. The rear-facing bonus multiplied `out["dmg"]` — the LOGGED number — while the HP
			# subtraction below read `out["toHp"]`, so the +15% rear bonus shipped COSMETIC: it
			# changed the float text and never the health bar. Found only because the care-loop
			# A/B probe refused to budge under an absurd 5× test innate. Every post-maths
			# multiplier must rescale toHp too: the ward keeps what it already soaked, and the
			# adjusted damage minus that soak is what reaches HP.
			out["toHp"] = maxi(0, int(out["dmg"]) - int(out.get("wardSoaked", 0)))
			total_dmg += out["dmg"]
			ast["hit_done"] = true
			if int(out["dmg"]) > 0:
				_pack_hits[target] = {"side": attacker.side, "by": attacker, "tick": _tick_no}
				if afx.has("lifesteal"):
					attacker.hp = minf(float(attacker.max_hp), attacker.hp + float(out["dmg"]) * float(afx["lifesteal"]))
				if afx.has("manaSteal"):
					var stolen: float = float(out["dmg"]) * float(afx["manaSteal"])
					stolen = minf(stolen, target.mp)
					target.mp -= stolen
					attacker.mp = minf(float(attacker.max_mana), attacker.mp + stolen)
			target.hp = maxf(0.0, target.hp - float(out["toHp"]))
			if out["wardSoaked"] > 0:
				var remaining: float = out["wardSoaked"]
				for mod in target.mods:
					if remaining <= 0.0:
						break
					if mod.has("ward") and float(mod["ward"]) > 0.0:
						var take: float = minf(float(mod["ward"]), remaining)
						mod["ward"] = float(mod["ward"]) - take
						remaining -= take

			var recoil = fx.get("recoil")
			if recoil != null:
				attacker.hp = maxf(0.0, attacker.hp - float(out["dmg"]) * minf(0.15, float(recoil)))
			var lifesteal = fx.get("lifesteal")
			if lifesteal != null:
				attacker.hp = minf(float(attacker.max_hp), attacker.hp + float(out["toHp"]) * float(lifesteal))
			var thorns = fx.get("thorns")
			if thorns != null and not is_basic:
				pass  # defender-reflect on being hit — out of scope, same as battle_sim.gd

	attacker.has_acted = true
	if target.hp <= 0.0 and target.alive:
		target.alive = false
		_log_event({"kind": "death", "unit": target.species_name, "side": target.side, "killer": attacker.species_name})

	_log_event({
		"kind": "hit" if last_out.get("hit", false) else "miss",
		"attacker": attacker.species_name, "attackerSide": attacker.side,
		"target": target.species_name, "targetSide": target.side,
		"move": mv["name"], "dmg": total_dmg, "crit": last_out.get("crit", false),
		"arc": facing_arc,
		"targetHpFrac": target.hp_frac(),
	})

	if last_out.get("hit", false) and target.alive:
		var debuff_mod := {}
		var has_debuff := false
		if fx.has("defDebuff"):
			debuff_mod["defMitDebuff"] = float(fx["defDebuff"]); has_debuff = true
		if fx.has("atkDebuff"):
			debuff_mod["atkMultBonus"] = -float(fx["atkDebuff"]); has_debuff = true
		if fx.has("accDebuff"):
			debuff_mod["accMod"] = -float(fx["accDebuff"]); has_debuff = true
		if fx.has("manaBurn"):
			target.mp = maxf(0.0, target.mp - float(fx["manaBurn"]))
		if has_debuff:
			debuff_mod["until"] = now + DeriveMath.rounds_to_seconds(float(fx.get("duration", 1)))
			target.mods.append(debuff_mod)
		# ⚠️ tauntForce — THE PRODUCER THE AI HAS BEEN WAITING FOR. `monster_tree.gd`'s target
		# selection has carried a complete taunt override since the tree was built, marked
		# "currently unreachable" because nothing ever applied a `taunt` status. The tenth
		# built-and-unreachable find. The entry is sim-side state, NOT a fieldStatus kind — the
		# contracted status table stays untouched; `has_status` scans the array and the tick
		# expires anything with an `until`, so a foreign kind rides safely. `from` carries the
		# taunter's name because that is the key `_find_taunter` resolves back to an enemy index.
		if fx.has("tauntForce"):
			target.statuses = target.statuses.filter(func(st_t): return str(st_t.get("kind", "")) != "taunt")
			target.statuses.append({
				"kind": "taunt", "from": attacker.species_name,
				"until": now + DeriveMath.rounds_to_seconds(float(fx.get("duration", 1))),
			})
			_log_event({
				"kind": "status_apply", "unit": target.species_name, "side": target.side,
				"status": "taunt", "from": attacker.species_name,
			})

	var status_spec = mv.get("status")
	if status_spec != null and target.alive:
		if rng.randf() * 100.0 < float(status_spec.get("chance", 100.0)):
			var out2 := StatusMathLib.apply_status({
				"kind": status_spec["kind"], "statuses": target.statuses,
				"ccResist": target.cc_resist, "targetDead": false,
				"rounds": float(status_spec.get("duration", 1)), "now": now,
				"ccImmuneUntil": -999.0, "targetCon": target.stats.get("CON", 0.0),
				"from": attacker.species_name,
			})
			if out2["applied"]:
				target.statuses = out2["statuses"]
				target.cc_resist = out2["ccResist"]
				if out2["ccMeterTouched"]:
					target.last_cc_at = now
				_log_event({
					"kind": "status_apply", "unit": target.species_name, "side": target.side,
					"status": status_spec["kind"], "from": attacker.species_name,
				})
				# ⚠️ THE INTERRUPT, AND IT NEEDED NO NEW CONTENT. WoW: "crowd control effects
				# (stuns, silences, knockbacks) can still cancel" a cast. The pool already authors
				# 3 silence movers and 4 stun movers, and `data/data.json` is GENERATED — every
				# contract run re-copies it — so an interrupt had to come from moves that already
				# exist rather than from new ones. Landing hard control on a caster now does what
				# a player would expect it to.
				_interrupt_if_casting(target, attacker, str(status_spec["kind"]))
				# ⚠️ KNOCKBACK NOW DISPLACES — the pool-audit fix. Until 2026-08-06 the status
				# ticked (0.6 speed) but nobody MOVED; the shove the move describes never
				# happened. NOTHING TELEPORTS: this arms a flight the move phase pays out at
				# KNOCKBACK_SPEED, control lost for the ride. `kbResist` (Immovable/Unstoppable,
				# potency-scaled) multiplies the distance — the innate that was dormant until
				# displacement existed.
				if str(status_spec["kind"]) == "knockback":
					var kb_dir: Vector2 = (spatial_state[target]["pos"] as Vector2) - (spatial_state[attacker]["pos"] as Vector2)
					if kb_dir.length_squared() < 0.000001:
						kb_dir = Vector2(1, 0)
					var kb_mult := float((spatial_state[target].get("fx", {}) as Dictionary).get("kbResist", 1.0))
					spatial_state[target]["kb"] = {
						"dir": kb_dir.normalized(), "left": Sp.KNOCKBACK_DIST * kb_mult,
					}

	# ⚠️ CONTAGION (spreadStatus) — ported from battle.ts semantics, given a RADIUS. From the
	# target's carried spreadable statuses (matching the move's kind if authored), the first
	# spreads to up to `targets` other enemies within CONTAGION_RADIUS of the infected body,
	# each on an independent chance roll, and the copy inherits the source's REMAINING duration —
	# contagion spreads a curse without extending it. Runs AFTER the move's own status, so a
	# cast can create the very status it then spreads (battle.ts's `willSet`).
	var sp_spec = (mv.get("effects", {}) as Dictionary).get("spreadStatus") if mv.get("effects") is Dictionary else null
	if sp_spec is Dictionary and target.alive and last_out.get("hit", false):
		var want_kind := str((sp_spec as Dictionary).get("kind", ""))
		var carried: Dictionary = {}
		for st_c in target.statuses:
			var ck := str(st_c.get("kind", ""))
			if (want_kind == "" or ck == want_kind) and ck != "taunt":
				carried = st_c
				break
		if not carried.is_empty():
			var spread_left := int((sp_spec as Dictionary).get("targets", 1))
			var remaining_s: float = maxf(0.0, float(carried.get("until", now)) - now)
			for other in _living(_enemies_of(attacker)):
				if spread_left <= 0:
					break
				if other == target or other.has_status(str(carried["kind"])):
					continue
				if (spatial_state[other]["pos"] as Vector2).distance_to(spatial_state[target]["pos"]) > Sp.CONTAGION_RADIUS:
					continue
				if rng.randf() * 100.0 >= float((sp_spec as Dictionary).get("chance", 0.0)):
					continue
				var outc := StatusMathLib.apply_status({
					"kind": carried["kind"], "statuses": other.statuses,
					"ccResist": other.cc_resist, "targetDead": false,
					"rounds": remaining_s / DeriveMath.rounds_to_seconds(1.0), "now": now,
					"ccImmuneUntil": -999.0, "targetCon": other.stats.get("CON", 0.0),
					"from": target.species_name,
				})
				if outc["applied"]:
					other.statuses = outc["statuses"]
					other.cc_resist = outc["ccResist"]
					if outc["ccMeterTouched"]:
						other.last_cc_at = now
					spread_left -= 1
					_log_event({
						"kind": "contagion", "unit": other.species_name, "side": other.side,
						"status": str(carried["kind"]),
						"reason": "%s spreads from %s to %s" % [str(carried["kind"]), target.species_name, other.species_name],
					})
					_interrupt_if_casting(other, attacker, str(carried["kind"]))

	# The detonator consumed its fuel: remove the status it cashed in.
	if bvs_armed and total_dmg > 0 and bool((bvs as Dictionary).get("consume", false)):
		var kept: Array = []
		for st_e in target.statuses:
			if str(st_e.get("kind", "")) != str((bvs as Dictionary).get("kind", "")):
				kept.append(st_e)
		target.statuses = kept
		_log_event({
			"kind": "detonate", "unit": target.species_name, "side": target.side,
			"status": str((bvs as Dictionary).get("kind", "")),
			"reason": "%s's %s detonated the %s" % [attacker.species_name, str(mv.get("name", "")), str((bvs as Dictionary).get("kind", ""))],
		})

	# Innate statusOnHit: the innate may inflict a status on any damaging hit.
	var soh = afx.get("statusOnHit")
	if soh is Dictionary and target.alive and total_dmg > 0:
		if rng.randf() * 100.0 < float(soh.get("chance", 0.0)):
			var out3 := StatusMathLib.apply_status({
				"kind": soh["kind"], "statuses": target.statuses,
				"ccResist": target.cc_resist, "targetDead": false,
				"rounds": float(soh.get("duration", 1)), "now": now,
				"ccImmuneUntil": -999.0, "targetCon": target.stats.get("CON", 0.0),
				"from": attacker.species_name,
			})
			if out3["applied"]:
				target.statuses = out3["statuses"]
				target.cc_resist = out3["ccResist"]
				if out3["ccMeterTouched"]:
					target.last_cc_at = now
				_log_event({
					"kind": "status_apply", "unit": target.species_name, "side": target.side,
					"status": soh["kind"], "from": "%s (innate %s)" % [attacker.species_name, str(afx.get("_name", ""))],
				})
				_interrupt_if_casting(target, attacker, str(soh["kind"]))

	pending_shots.append({
		"fromId": unit_ids.get(attacker, -1), "toId": unit_ids.get(target, -1),
		"kind": _shot_kind(str(mv.get("channel", "melee"))),
		"hit": last_out.get("hit", false), "dmg": total_dmg,
		"crit": last_out.get("crit", false), "move": str(mv.get("name", "Attack")),
		# ⚠️ THE RENDERER MUST BE ABLE TO SAY WHY. A 15% rear bonus the player cannot perceive is
		# invisible depth — and in a game with no mid-fight input, the ONLY way a read pays off is
		# by being visible afterwards. Carried on the shot so the float text can name it.
		"arc": facing_arc,
	})


func _apply_team_effect(caster, target, mv: Dictionary) -> void:
	var fx: Dictionary = mv.get("effects", {})

	# ⚠️ HEAL FIRST, AND BEFORE THE EMPTY-EFFECTS BAIL-OUT. Port of `src/battle.ts:1052`
	# (`resolveUtilityOnTarget`). This engine had NO healing at all — `grep '.hp +'` found only
	# lifesteal; every other HP write subtracts. On a FRIENDLY move `power` is the HEAL AMOUNT,
	# not damage: Mending Surge 97, Tranquility 74, Vital Surge 46, Mend 15, Renewal 11.
	#
	# ⚠️ The `fx.is_empty()` guard below is why this must come first. Mend, Tranquility, Mending
	# Surge and Second Wind carry NO effects at all — they are pure heals — so they would hit that
	# early return and do nothing, which is exactly what happened after the routing fix landed:
	# they stopped damaging their own allies and started doing nothing instead. Half a fix.
	var power := float(mv.get("power", 0.0))
	if power > 0.0:
		var mult: float = HEALBLOCK_MULT if target.has_status("healblock") else 1.0
		var heal: float = round(power * 1.2 * mult)
		var before: float = target.hp
		target.hp = minf(float(target.max_hp), target.hp + heal)
		_log_event({
			"kind": "heal", "unit": target.species_name, "side": target.side,
			"move": mv["name"], "caster": caster.species_name,
			"amount": int(target.hp - before), "healblocked": target.has_status("healblock"),
		})

	if fx.is_empty():
		return
	var duration_s := DeriveMath.rounds_to_seconds(float(fx.get("duration", 1)))
	var mod := {"until": now + duration_s}
	var applied := false
	if fx.has("atkBuff"):
		mod["atkMultBonus"] = float(fx["atkBuff"]); applied = true
	if fx.has("defBuff"):
		mod["defMitDebuff"] = -float(fx["defBuff"]); applied = true
	if fx.has("accBuff"):
		mod["accMod"] = float(fx["accBuff"]); applied = true
	if fx.has("dodgeBuff"):
		mod["dodgeMod"] = float(fx["dodgeBuff"]); applied = true
	if fx.has("ward"):
		mod["ward"] = float(fx["ward"]); applied = true
	if fx.has("guard"):
		mod["guard"] = float(fx["guard"]); applied = true
	if fx.has("hpRegenBuff"):
		mod["hpRegen"] = float(fx["hpRegenBuff"]); applied = true
	if fx.has("regenBuff"):
		mod["regen"] = float(fx["regenBuff"]); applied = true
	if applied:
		target.mods.append(mod)
		_log_event({
			"kind": "buff", "unit": target.species_name, "side": target.side,
			"move": mv["name"], "caster": caster.species_name,
		})
		pending_shots.append({
			"fromId": unit_ids.get(caster, -1), "toId": unit_ids.get(target, -1),
			"kind": _shot_kind(str(mv.get("channel", "support"))),
			"hit": true, "dmg": 0, "crit": false, "move": str(mv.get("name", "")),
		})
	if fx.has("cleanse"):
		# ⚠️ LOG THE CLEANSE. It used to strip statuses silently, so the single most dramatic
		# counter-play in the game — breaking a stun off a pinned ally — produced NO event, showed
		# nothing on the report screen, and could not be measured. In a game whose whole premise is
		# that the player reads a fight they cannot influence, an invisible save is a save that
		# never happened as far as they are concerned.
		var broken: Array = []
		for st in target.statuses:
			if StatusMathLib.HARD_CONTROL.has(st["kind"]):
				broken.append(str(st["kind"]))
		target.statuses = target.statuses.filter(func(s): return not StatusMathLib.HARD_CONTROL.has(s["kind"]))
		if not broken.is_empty():
			_log_event({
				"kind": "cleanse", "unit": target.species_name, "side": target.side,
				"by": caster.species_name, "move": str(mv.get("name", "")), "broke": broken,
			})


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# FRAME RECORDING — docs/BUILD_CONTRACT.md §2
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _record_frame(decisions: Dictionary) -> void:
	var units_out: Array = []
	for m in _units:
		var st: Dictionary = spatial_state[m]
		var state := "dead"
		var tid := -1
		var intent := ""
		var reason := ""
		if m.alive:
			if m.is_incapacitated():
				state = "stunned"
			elif st.get("casting") != null:
				state = "cast"
			elif st.get("_just_hit", false):
				state = "attack"
			elif st.get("_moved", false):
				state = "advance" if st.get("_advancing", true) else "retreat"
			else:
				state = "idle"

			var cast = st.get("casting")
			if cast != null and cast.get("single_target") != null:
				tid = unit_ids.get(cast["single_target"], -1)

			var dec: Dictionary = decisions.get(m, {})
			if tid == -1 and dec.get("_target_unit") != null:
				tid = unit_ids.get(dec["_target_unit"], -1)
			intent = str(dec.get("intent", ""))
			reason = str(dec.get("reason", ""))

		units_out.append({
			"id": unit_ids[m], "pos": st["pos"], "facing": st.get("facing", Vector2(1, 0)),
			"moveDir": st.get("_move_dir_out", Vector2.ZERO),
			"weary": st.get("weary", false),
			# What is being wound up, so the renderer can telegraph it (AoE area rings need the
			# move's identity and reach — "the renderer derives nothing" means the sim must SAY).
			"castMove": str((st["casting"]["move"] as Dictionary).get("name", "")) if st.get("casting") != null else "",
			"castFrac": (1.0 - float(st["casting"]["remaining"]) / maxf(0.001, float(st["casting"]["total"]))) if st.get("casting") != null else 0.0,
			"hp": m.hp, "mp": m.mp, "alive": m.alive, "state": state,
			"statuses": m.statuses.map(func(s): return s["kind"]),
			"targetId": tid, "intent": intent, "reason": reason,
		})
	# ⚠️ `projectiles` is always [] this pass — AUTOBATTLER_DESIGN.md #34 (full per-ability
	# projectile data: speed/width/pierce) is not built. Every hit resolves instantaneously once
	# its windup completes; there is no in-flight travel to visualise yet. Flagged, not hidden.
	var projs_out: Array = []
	for pr in _projectiles:
		if not pr["tgt"].alive:
			continue
		var tp: Vector2 = spatial_state[pr["tgt"]]["pos"]
		var total: float = (Vector2(spatial_state[pr["atk"]]["pos"])).distance_to(tp)
		projs_out.append({
			"id": int(pr["id"]), "from": Vector2(pr["pos"]), "to": tp,
			# from == current position, so progress 0 keeps the renderer drawing AT the sim's
			# own projectile position — the stream stays authoritative, nothing extrapolates.
			"progress": 0.0, "kind": str(pr["kind"]),
		})
	frames.append({"t": now, "units": units_out, "shots": pending_shots, "projectiles": projs_out})
	pending_shots = []


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# SHARED HELPERS — ported verbatim from the previous version / battle_sim.gd
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _enemies_of(m) -> Array:
	return team_b if m.side == "A" else team_a


func _allies_of(m) -> Array:
	return team_a if m.side == "A" else team_b


func _living(units: Array) -> Array:
	return units.filter(func(u): return u.alive)


func _mod_sum(m, key: String) -> float:
	var total := 0.0
	for mod in m.mods:
		total += float(mod.get(key, 0.0))
	return total


## A unit's effective orders: its team's plan, with its own per-monster overrides layered on top.
func _effective_tactics(m) -> Dictionary:
	var plan: Dictionary = team_a_plan if m.side == "A" else team_b_plan
	var merged: Dictionary = plan.duplicate()
	var own: Dictionary = unit_orders.get(m, {})
	for k in own:
		merged[k] = own[k]
	return merged


func _pick_lowest_hp(units: Array):
	if units.is_empty():
		return null
	var best = units[0]
	for u in units:
		if u.hp_frac() < best.hp_frac():
			best = u
	return best


func _pay_and_cooldown(m, mv: Dictionary, is_basic: bool) -> void:
	m.has_acted = true
	if is_basic:
		m.cooldowns["__basic__"] = mv["cooldown"]
		return
	m.mp = maxf(0.0, m.mp - DeriveMath.field_mp_cost(mv))
	m.cooldowns[mv["name"]] = DeriveMath.cooldown_seconds(mv)


func _log_event(e: Dictionary) -> void:
	e["t"] = now
	event_log.append(e)


func _names(team: Array) -> Array:
	return team.map(func(m): return m.species_name)
