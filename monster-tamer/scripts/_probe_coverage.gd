## THE ANTI-BLOB ACCEPTANCE TEST. Throwaway probe — delete freely.
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . --script res://scripts/_probe_coverage.gd
##
## Answers exactly two questions, both of which have been GUESSED AT before and never measured:
##   1. Does the board actually get used?  (span of living units / ground size)
##   2. Do the five positional intents produce DIFFERENT fights, or the same fight relabelled?
##
## ⚠️ (2) is the one that matters. Coverage can rise for boring reasons — a slower closing speed
## spreads units out too. The proof that the TREE is doing the work is that `wings` and `hold`
## diverge from each other. If every intent produces identical positions, the tree is being
## called but its positional subtrees are inert, and the honest report is "not fixed".
extends Node

const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const SpatialSimScript = preload("res://scripts/spatial_sim.gd")
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


func _build_team(count: int, s: float, d: float, c: float, w: float, i_: float, ch: float) -> Array:
	var out: Array = []
	for i in range(count):
		var stats := {"STR": s, "DEX": d, "CON": c, "WIS": w, "INT": i_, "CHA": ch}
		var slice: Array = []
		for j in range(6):
			slice.append(_moves[(i * 3 + j) % _moves.size()])
		out.append(_make_monster(stats, slice))
	return out


func _run_once(seed_: int, intent_a: String, intent_b: String) -> Dictionary:
	var a := _build_team(5, 300.0, 250.0, 200.0, 150.0, 120.0, 100.0)
	var b := _build_team(5, 150.0, 400.0, 150.0, 250.0, 200.0, 150.0)
	var plan_a := {"formation": "tight", "positionalIntent": intent_a}
	var plan_b := {"formation": "loose", "positionalIntent": intent_b}
	var sim = SpatialSimScript.new(a, b, seed_, plan_a, plan_b, {}, [])
	return await sim.run()


## Peak coverage = the largest bounding box the living units ever occupied, as a fraction of the
## ground area. Reported as area (x_frac * y_frac) to match the sandbox's own banner figure.
func _coverage(result: Dictionary) -> Dictionary:
	var g: Vector2 = result.get("groundSize", Vector2(160, 88))
	var peak := 0.0
	var lateral_peak := 0.0
	for frame in result.get("frames", []):
		var min_p := Vector2(INF, INF)
		var max_p := Vector2(-INF, -INF)
		var n := 0
		for u in frame.get("units", []):
			if bool(u.get("alive", true)):
				var p: Vector2 = u["pos"]
				min_p.x = minf(min_p.x, p.x); min_p.y = minf(min_p.y, p.y)
				max_p.x = maxf(max_p.x, p.x); max_p.y = maxf(max_p.y, p.y)
				n += 1
		if n >= 2:
			var span := max_p - min_p
			peak = maxf(peak, (span.x / g.x) * (span.y / g.y))
			lateral_peak = maxf(lateral_peak, span.y / g.y)
	return {"area": peak, "lateral": lateral_peak}


## The divergence test. Same seed, same teams, only the ORDER differs. Returns the mean distance
## between where team A's units stand under intent 1 vs intent 2, at matched ticks.
func _divergence(r1: Dictionary, r2: Dictionary) -> float:
	var f1: Array = r1.get("frames", [])
	var f2: Array = r2.get("frames", [])
	var n: int = mini(f1.size(), f2.size())
	if n == 0:
		return -1.0
	var total := 0.0
	var samples := 0
	for i in range(n):
		var u1: Array = f1[i].get("units", [])
		var u2: Array = f2[i].get("units", [])
		for j in range(mini(u1.size(), u2.size())):
			if bool(u1[j].get("alive", true)) and bool(u2[j].get("alive", true)):
				total += (u1[j]["pos"] as Vector2).distance_to(u2[j]["pos"] as Vector2)
				samples += 1
	return -1.0 if samples == 0 else total / float(samples)


func _ready() -> void:
	_load_moves()
	print("=== ANTI-BLOB ACCEPTANCE TEST ===")
	print("baseline on record: peak board coverage 9%%\n")

	var intents := ["hold", "push", "wings", "dive", "guard"]
	var results: Dictionary = {}

	print("--- coverage by positional intent (both teams same order, seed 12345) ---")
	for it in intents:
		var r: Dictionary = await _run_once(12345, it, it)
		results[it] = r
		var cov: Dictionary = _coverage(r)
		print("  %-6s  area %5.1f%%   lateral span %5.1f%%   winner %-5s  dur %5.1fs  frames %d" % [
			it, cov["area"] * 100.0, cov["lateral"] * 100.0,
			str(r.get("winner", "?")), float(r.get("duration", 0.0)), r.get("frames", []).size()])

	print("\n--- DIVERGENCE: do the orders actually produce different fights? ---")
	print("  (mean distance between matched unit positions, same seed, different order)")
	var base_r: Dictionary = results["hold"]
	var any_live := false
	for it in intents:
		if it == "hold":
			continue
		var d := _divergence(base_r, results[it])
		var verdict := "INERT — identical to hold" if d >= 0.0 and d < 0.01 else "distinct"
		if d >= 0.01:
			any_live = true
		print("  hold vs %-6s  mean delta %7.2f units   %s" % [it, d, verdict])

	print("\n--- asymmetric: A=wings vs B=hold (the shape the sandbox screenshots) ---")
	var asym: Dictionary = await _run_once(777, "wings", "hold")
	var acov: Dictionary = _coverage(asym)
	print("  area %5.1f%%   lateral span %5.1f%%   winner %s  dur %.1fs" % [
		acov["area"] * 100.0, acov["lateral"] * 100.0,
		str(asym.get("winner", "?")), float(asym.get("duration", 0.0))])

	print("\n--- determinism: same seed twice, byte-identical? ---")
	var d1: Dictionary = await _run_once(999, "wings", "dive")
	var d2: Dictionary = await _run_once(999, "wings", "dive")
	var det := _divergence(d1, d2)
	print("  mean delta %.6f  ->  %s" % [det, "DETERMINISTIC" if det >= 0.0 and det < 0.000001 else "NON-DETERMINISTIC"])

	print("\n=== VERDICT ===")
	print("  orders produce distinct fights: %s" % ("YES" if any_live else "NO — tree positional subtrees are inert"))
	get_tree().quit(0)
