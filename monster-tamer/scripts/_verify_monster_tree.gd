## THROWAWAY VERIFICATION SCRIPT for scripts/ai/monster_tree.gd — not a deliverable, not part of
## the contract, safe to delete after use.
##
## Builds synthetic monsters WITHOUT the GameData autoload (same technique as
## `_selftest_spatial_a.gd`), runs `SpatialSim` under a few `positionalIntent` pairings, and prints
## the exact "board coverage — peak/mid/final" numbers `sandbox_ui.gd::_update_verdict` shows,
## computed with the identical formula (duplicated here on purpose, not imported — that file's own
## comment explains why: this shows what the sim's own logic sees, not a guess at it).
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . --script res://scripts/_verify_monster_tree.gd
extends SceneTree

const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const SpatialSimScript = preload("res://scripts/spatial_sim.gd")
const SpatialLib = preload("res://scripts/spatial.gd")
const ClassifyLib = preload("res://scripts/classify.gd")
const DeriveLib = preload("res://scripts/derive.gd")

var _moves: Array = []


func _load_moves() -> void:
	var f := FileAccess.open("res://data/data.json", FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	_moves = parsed.get("moves", [])


func _make_monster(stats: Dictionary, moveset_slice: Array):
	var mi = MonsterInstanceScript.new()
	mi.species_id = "test"
	mi.species_name = "TestMon"
	mi.body = "Mammal"
	mi.stats = stats.duplicate()
	mi.class_name_ = ClassifyLib.class_for_stats(mi.stats)
	mi.role = ClassifyLib.role_of_class(mi.class_name_)
	mi.mana_role = ClassifyLib.mana_role_of(mi.stats, mi.class_name_)
	mi.basic_attack = ClassifyLib.basic_attack_for(mi.stats)
	mi.max_hp = DeriveLib.max_hp(mi.stats.get("CON", 0.0))
	mi.max_mp = DeriveLib.max_mana(mi.stats.get("WIS", 0.0), mi.stats.get("INT", 0.0))
	mi.moveset = moveset_slice
	mi.hp = mi.max_hp
	mi.mp = mi.max_mp
	return mi


## Mixed melee/ranged/caster team so all five positional subtrees see varied reach — a team of
## identical melee bruisers would make `push`/`hold`/`wings` look more alike than they are.
func _build_team(count: int) -> Array:
	var out: Array = []
	var archetypes := [
		{"STR": 320.0, "DEX": 180.0, "CON": 260.0, "WIS": 80.0, "INT": 60.0, "CHA": 60.0},
		{"STR": 140.0, "DEX": 340.0, "CON": 140.0, "WIS": 90.0, "INT": 100.0, "CHA": 90.0},
		{"STR": 90.0, "DEX": 120.0, "CON": 130.0, "WIS": 180.0, "INT": 320.0, "CHA": 100.0},
		{"STR": 110.0, "DEX": 140.0, "CON": 300.0, "WIS": 220.0, "INT": 80.0, "CHA": 90.0},
		{"STR": 100.0, "DEX": 130.0, "CON": 120.0, "WIS": 160.0, "INT": 120.0, "CHA": 300.0},
	]
	for i in range(count):
		var stats: Dictionary = archetypes[i % archetypes.size()]
		var slice: Array = []
		for j in range(6):
			slice.append(_moves[(i * 3 + j) % _moves.size()])
		out.append(_make_monster(stats, slice))
	return out


func _coverage_at_frame(frame: Dictionary, ground: Vector2) -> float:
	var pts: Array = []
	for rec in frame.get("units", []):
		if bool(rec.get("alive", false)):
			pts.append(rec.get("pos", Vector2.ZERO) as Vector2)
	if pts.size() < 2:
		return 0.0
	var mn: Vector2 = pts[0]
	var mx: Vector2 = pts[0]
	for p in pts:
		mn.x = minf(mn.x, p.x); mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x); mx.y = maxf(mx.y, p.y)
	var area := (mx.x - mn.x) * (mx.y - mn.y)
	var ground_area := ground.x * ground.y
	return 0.0 if ground_area <= 0.0 else clampf(area / ground_area, 0.0, 1.0)


func _summary(frames: Array, ground: Vector2) -> Dictionary:
	if frames.is_empty():
		return {"peak": 0.0, "mid": 0.0, "final": 0.0}
	var peak := 0.0
	for f in frames:
		var c := _coverage_at_frame(f, ground)
		if c > peak:
			peak = c
	var mid_idx := int(frames.size() / 2)
	return {
		"peak": peak, "mid": _coverage_at_frame(frames[mid_idx], ground),
		"final": _coverage_at_frame(frames[frames.size() - 1], ground),
	}


func _run_case(label: String, plan_a: Dictionary, plan_b: Dictionary, seed_: int) -> void:
	var team_a := _build_team(5)
	var team_b := _build_team(5)
	var sim = SpatialSimScript.new(team_a, team_b, seed_, plan_a, plan_b, {}, [])
	var result: Dictionary = await sim.run()
	var frames: Array = result.get("frames", [])
	var ground: Vector2 = result.get("groundSize", Vector2(160, 88))
	var cov := _summary(frames, ground)
	print("%-32s winner=%-5s dur=%6.1fs survivors=%d/%d  coverage peak=%3d%% mid=%3d%% final=%3d%%" % [
		label, result.get("winner", "?"), float(result.get("duration", 0.0)),
		int(result.get("survivorsA", 0)), int(result.get("survivorsB", 0)),
		int(round(float(cov["peak"]) * 100.0)), int(round(float(cov["mid"]) * 100.0)),
		int(round(float(cov["final"]) * 100.0)),
	])


func _initialize() -> void:
	_load_moves()
	print("moves loaded: ", _moves.size())
	print("")
	print("=== board coverage — monster_tree.gd verification ===")
	await _run_case("both hold (baseline)",  {"positionalIntent": "hold"},  {"positionalIntent": "hold"},  4242)
	await _run_case("both push",             {"positionalIntent": "push"}, {"positionalIntent": "push"},  4242)
	await _run_case("A wings / B hold",      {"positionalIntent": "wings"}, {"positionalIntent": "hold"},  4242)
	await _run_case("A wings / B push",      {"positionalIntent": "wings"}, {"positionalIntent": "push"},  4242)
	await _run_case("A dive / B hold",       {"positionalIntent": "dive"},  {"positionalIntent": "hold"},  4242)
	await _run_case("no order (engine default)", {}, {}, 4242)
	print("")
	quit()
