## THROWAWAY VERIFICATION SCRIPT for the spatial_sim.gd rewrite — not a deliverable, stream A's
## own proof for its task report. Not part of any ownership boundary; delete freely.
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . --script res://scripts/_selftest_spatial_a.gd
##
## `SpatialSim.run()` is now a coroutine (navmesh sync trap, see spatial_sim.gd's header) so this
## whole probe is written as an async chain off `_initialize()`.
extends SceneTree

const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const SpatialSimScript = preload("res://scripts/spatial_sim.gd")
const SpatialLib = preload("res://scripts/spatial.gd")
const ArenaLayoutLib = preload("res://scripts/arena_layout.gd")
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


func _build_team(count: int, str_: float, dex: float, con: float, wis: float, intel: float, cha: float) -> Array:
	var out: Array = []
	for i in range(count):
		var stats := {"STR": str_, "DEX": dex, "CON": con, "WIS": wis, "INT": intel, "CHA": cha}
		var slice: Array = []
		for j in range(6):
			slice.append(_moves[(i * 3 + j) % _moves.size()])
		out.append(_make_monster(stats, slice))
	return out


## `str()`, not the `String()` constructor — Godot 4's `String()` only accepts
## String/StringName/NodePath and is a RUNTIME error on floats/Vector2s. This bug sat
## invisible for as long as the harness compared empty frame streams.
func _vec_eq(a, b) -> bool:
	return typeof(a) == typeof(b) and str(a) == str(b)


func _frames_equal_strict(f1: Array, f2: Array) -> bool:
	if f1.size() != f2.size():
		print("  frame count differs: ", f1.size(), " vs ", f2.size())
		return false
	for i in range(f1.size()):
		var a: Dictionary = f1[i]
		var b: Dictionary = f2[i]
		if str(a["t"]) != str(b["t"]):
			print("  tick %d: t differs %s vs %s" % [i, a["t"], b["t"]])
			return false
		var ua: Array = a["units"]
		var ub: Array = b["units"]
		if ua.size() != ub.size():
			print("  tick %d: unit count differs" % i)
			return false
		for j in range(ua.size()):
			var x: Dictionary = ua[j]
			var y: Dictionary = ub[j]
			for k in ["id", "hp", "mp", "alive", "state", "targetId", "intent", "reason"]:
				if str(x[k]) != str(y[k]):
					print("  tick %d unit %d: %s differs %s vs %s" % [i, j, k, x[k], y[k]])
					return false
			if not _vec_eq(x["pos"], y["pos"]):
				print("  tick %d unit %d: pos differs %s vs %s" % [i, j, x["pos"], y["pos"]])
				return false
			if not _vec_eq(x["facing"], y["facing"]):
				print("  tick %d unit %d: facing differs %s vs %s" % [i, j, x["facing"], y["facing"]])
				return false
	return true


func _run_once(seed_: int, obstacles: Array) -> Dictionary:
	var a := _build_team(5, 300.0, 250.0, 200.0, 150.0, 120.0, 100.0)
	var b := _build_team(5, 150.0, 400.0, 150.0, 250.0, 200.0, 150.0)
	var plan_a := {"formation": "tight"}
	var plan_b := {"formation": "loose"}
	var sim = SpatialSimScript.new(a, b, seed_, plan_a, plan_b, {}, obstacles)
	return await sim.run()


## Board coverage: bounding box of every LIVING unit position across every frame, as a fraction of
## ground size on each axis. This is the direct measurement for "did the rewrite actually fix the
## blob", per the task's explicit ask.
func _measure_coverage(result: Dictionary) -> Dictionary:
	var g: Vector2 = result["groundSize"]
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	var sum_pairwise := 0.0
	var pairwise_n := 0
	for frame in result["frames"]:
		var units: Array = frame["units"]
		var alive_positions: Array = []
		for u in units:
			if bool(u.get("alive", true)):
				var p: Vector2 = u["pos"]
				min_p.x = minf(min_p.x, p.x)
				min_p.y = minf(min_p.y, p.y)
				max_p.x = maxf(max_p.x, p.x)
				max_p.y = maxf(max_p.y, p.y)
				alive_positions.append(p)
		for i in alive_positions.size():
			for j in range(i + 1, alive_positions.size()):
				sum_pairwise += alive_positions[i].distance_to(alive_positions[j])
				pairwise_n += 1
	var span := max_p - min_p
	var mean_pairwise := 0.0 if pairwise_n == 0 else sum_pairwise / float(pairwise_n)
	return {
		"span_x_frac": span.x / g.x, "span_y_frac": span.y / g.y,
		"min": min_p, "max": max_p, "ground": g,
		"mean_pairwise_dist": mean_pairwise, "mean_pairwise_frac_of_diag": mean_pairwise / g.length(),
	}


func _out_of_reach_fraction(result: Dictionary) -> float:
	# Fraction of (living-unit, tick) samples where the unit's own state is "advance"/"retreat"
	# (i.e. still closing/repositioning rather than attacking/casting/idle-in-range) — a rough,
	# self-contained proxy for the chase problem, computed only from what's already in the frame
	# stream (no extra instrumentation needed for this probe).
	var moving := 0
	var total := 0
	for frame in result["frames"]:
		for u in frame["units"]:
			if not bool(u.get("alive", true)):
				continue
			total += 1
			var st := str(u.get("state", ""))
			if st == "advance" or st == "retreat":
				moving += 1
	return 0.0 if total == 0 else float(moving) / float(total)


func _initialize() -> void:
	print("═══ SPATIAL SIM A — determinism + blob measurement, Godot %s ═══" % Engine.get_version_info()["string"])
	_load_moves()
	print("moves loaded: ", _moves.size())

	var team_size := 5
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var layout: Dictionary = ArenaLayoutLib.generate(team_size, "Wood", rng)
	var obstacles: Array = layout["obstacles"]
	print("arena: %d obstacles (theme=%s)" % [obstacles.size(), layout["theme"]])

	print("")
	print("── run 1/2 (seed 777) ──")
	var r1 := await _run_once(777, obstacles)
	print("run1: winner=%s duration=%.1f frames=%d survivorsA=%d survivorsB=%d ground=%s" % [
		r1["winner"], r1["duration"], r1["frames"].size(), r1["survivorsA"], r1["survivorsB"], r1["groundSize"]])

	print("")
	print("── run 2/2 (seed 777, in-process repeat) ──")
	var r2 := await _run_once(777, obstacles)
	print("run2: winner=%s duration=%.1f frames=%d" % [r2["winner"], r2["duration"], r2["frames"].size()])

	print("")
	var same := _frames_equal_strict(r1["frames"], r2["frames"])
	print("DETERMINISM (in-process, same seed): ", "PASS - identical frame streams" if same else "FAIL - frame streams diverged")

	print("")
	print("── run 3 (seed 999, sensitivity check) ──")
	var r3 := await _run_once(999, obstacles)
	var different := not _frames_equal_strict(r1["frames"], r3["frames"])
	print("run3: winner=%s duration=%.1f frames=%d" % [r3["winner"], r3["duration"], r3["frames"].size()])
	print("SEED SENSITIVITY: ", "PASS - different seed changed the outcome" if different else "WARN - different seed produced identical frames")

	print("")
	print("── coverage / blob measurement (run 1) ──")
	var cov := _measure_coverage(r1)
	print("ground=%s  bbox min=%s max=%s" % [cov["ground"], cov["min"], cov["max"]])
	print("span: x=%.1f%% y=%.1f%% of ground axis" % [cov["span_x_frac"] * 100.0, cov["span_y_frac"] * 100.0])
	print("mean pairwise distance (living units, all frames): %.2f units (%.1f%% of board diagonal)" % [cov["mean_pairwise_dist"], cov["mean_pairwise_frac_of_diag"] * 100.0])

	var oor := _out_of_reach_fraction(r1)
	print("fraction of (unit,tick) samples spent advance/retreat (chase proxy): %.1f%%" % (oor * 100.0))

	print("")
	print("sample log size: ", r1["log"].size())
	if not r1["frames"].is_empty():
		print("first frame: ", r1["frames"][0])
		print("mid frame: ", r1["frames"][r1["frames"].size() / 2])

	quit(0 if same and different else 1)
