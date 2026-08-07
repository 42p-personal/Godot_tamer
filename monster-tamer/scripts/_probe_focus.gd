## Does kill-target calling (option B) actually work end to end?
extends Node
const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const SpatialSimScript = preload("res://scripts/spatial_sim.gd")
const ClassifyLib = preload("res://scripts/classify.gd")
const DeriveLib = preload("res://scripts/derive.gd")
var _moves: Array = []

func _load() -> void:
	var f := FileAccess.open("res://data/data.json", FileAccess.READ)
	var p = JSON.parse_string(f.get_as_text()); f.close()
	_moves = p.get("moves", [])

func _mk(nm: String, s: float, d: float, c: float):
	var mi = MonsterInstanceScript.new()
	mi.id = nm; mi.species_id = "test"; mi.species_name = nm; mi.body = "Mammal"
	mi.stats = {"STR": s, "DEX": d, "CON": c, "WIS": 100.0, "INT": 100.0, "CHA": 100.0}
	mi.class_name_ = ClassifyLib.class_for_stats(mi.stats)
	mi.basic_attack = ClassifyLib.basic_attack_for(mi.stats)
	mi.max_hp = DeriveLib.max_hp(c); mi.hp = mi.max_hp
	mi.max_mp = DeriveLib.max_mana(100.0, 100.0); mi.mp = mi.max_mp
	var sl: Array = []
	for j in range(6): sl.append(_moves[j % _moves.size()])
	mi.moveset = sl
	return mi

func _teams() -> Array:
	var a: Array = []
	for i in range(3): a.append(_mk("A%d" % i, 250.0, 200.0, 200.0))
	var b: Array = []
	b.append(_mk("SQUISHY", 100.0, 300.0, 60.0))   # low CON — the obvious kill target
	b.append(_mk("TANK", 150.0, 100.0, 400.0))
	b.append(_mk("MID", 200.0, 200.0, 200.0))
	return [a, b]

## What fraction of team A's shots landed on the named enemy, up to first death?
func _share_on(result: Dictionary, who: String) -> float:
	var on := 0.0
	var total := 0.0
	for frame in result.get("frames", []):
		for s in frame.get("shots", []):
			if int(s.get("fromId", -1)) < 3:   # team A occupies ids 0..2
				total += 1.0
				var tid: int = int(s.get("toId", -1))
				var units: Array = frame.get("units", [])
				if tid >= 0 and tid < units.size() and str(units[tid].get("name", "")) == who:
					on += 1.0
	return 0.0 if total == 0.0 else on / total

func _run(mark_squishy: bool) -> Dictionary:
	var t := _teams()
	var plan_a := {"formation": "tight"}
	if mark_squishy:
		plan_a["targetPriority"] = "manmark"
		plan_a["markedUnit"] = t[1][0]   # SQUISHY
	var sim = SpatialSimScript.new(t[0], t[1], 4242, plan_a, {"formation": "loose"}, {}, [])
	return await sim.run()

func _first_dead(result: Dictionary) -> String:
	for e in result.get("log", []):
		if str(e.get("kind", "")) == "death":
			return str(e.get("name", e.get("unit", "?")))
	return "(nobody died)"

func _ready() -> void:
	_load()
	print("=== OPTION B: KILL-TARGET CALLING ===")
	print("  Team B: SQUISHY (CON 60), TANK (CON 400), MID (CON 200)\n")

	var off: Dictionary = await _run(false)
	print("--- no order (default scorer) ---")
	print("  first death: %s   winner %s  dur %.1fs" % [
		_first_dead(off), off.get("winner","?"), off.get("duration",0.0)])

	var on: Dictionary = await _run(true)
	print("\n--- ordered: mark SQUISHY ---")
	print("  first death: %s   winner %s  dur %.1fs" % [
		_first_dead(on), on.get("winner","?"), on.get("duration",0.0)])

	print("\n--- did the ORDER change the fight? ---")
	var f1: Array = off.get("frames", [])
	var f2: Array = on.get("frames", [])
	var diff := 0
	var n: int = mini(f1.size(), f2.size())
	for i in range(n):
		var u1: Array = f1[i].get("units", [])
		var u2: Array = f2[i].get("units", [])
		for j in range(mini(u1.size(), u2.size())):
			if int(u1[j].get("targetId", -1)) != int(u2[j].get("targetId", -1)):
				diff += 1
	print("  ticks compared: %d   unit-ticks with a DIFFERENT target: %d" % [n, diff])
	print("  VERDICT: %s" % ("ORDER IS LIVE — marking changes who gets hit" if diff > 0 else "*** INERT — the order changed nothing ***"))

	print("\n--- attribution: is the decision labelled as the player's? ---")
	var order_ticks := 0
	for frame in f2:
		for u in frame.get("units", []):
			if str(u.get("attribution", "")) == "order":
				order_ticks += 1
	print("  unit-ticks attributed to 'order': %d  (the report screen reads this)" % order_ticks)
	get_tree().quit(0)
