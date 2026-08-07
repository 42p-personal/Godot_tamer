## WHY DON'T FIGHTS RESOLVE? Fast diagnostic — 30s cap, prints where it stalls.
extends Node
const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const SpatialSimScript = preload("res://scripts/spatial_sim.gd")
const ClassifyLib = preload("res://scripts/classify.gd")
const DeriveLib = preload("res://scripts/derive.gd")
const SpatialLib = preload("res://scripts/spatial.gd")
var _moves: Array = []

func _load() -> void:
	var f := FileAccess.open("res://data/data.json", FileAccess.READ)
	var p = JSON.parse_string(f.get_as_text()); f.close()
	_moves = p.get("moves", [])

func _mk(nm: String, s: float, c: float):
	var mi = MonsterInstanceScript.new()
	mi.id = nm; mi.species_id = "test"; mi.species_name = nm; mi.body = "Mammal"
	mi.stats = {"STR": s, "DEX": 200.0, "CON": c, "WIS": 100.0, "INT": 100.0, "CHA": 100.0}
	mi.class_name_ = ClassifyLib.class_for_stats(mi.stats)
	mi.basic_attack = ClassifyLib.basic_attack_for(mi.stats)
	mi.max_hp = DeriveLib.max_hp(c); mi.hp = mi.max_hp
	mi.max_mp = DeriveLib.max_mana(100.0, 100.0); mi.mp = mi.max_mp
	var sl: Array = []
	for j in range(6): sl.append(_moves[j % _moves.size()])
	mi.moveset = sl
	return mi

func _ready() -> void:
	_load()
	print("=== WHY DON'T FIGHTS RESOLVE? ===\n")
	var a: Array = []
	for i in range(3): a.append(_mk("A%d" % i, 250.0, 200.0))
	var b: Array = []
	b.append(_mk("SQUISHY", 100.0, 60.0))
	b.append(_mk("TANK", 150.0, 400.0))
	b.append(_mk("MID", 200.0, 200.0))
	print("  HP pools: A=%.0f each   SQUISHY=%.0f  TANK=%.0f  MID=%.0f" % [
		a[0].max_hp, b[0].max_hp, b[1].max_hp, b[2].max_hp])
	print("  basic attack: %s  reach %s" % [str(a[0].basic_attack.get("name","?")), str(a[0].basic_attack.get("reach","?"))])

	var sim = SpatialSimScript.new(a, b, 4242, {"formation":"tight"}, {"formation":"loose"}, {}, [])
	var r: Dictionary = await sim.run()
	var frames: Array = r.get("frames", [])
	print("\n  duration %.1fs  winner %s  frames %d" % [r.get("duration",0.0), r.get("winner","?"), frames.size()])

	var shots := 0; var hits := 0; var dmg := 0.0
	for fr in frames:
		for s in fr.get("shots", []):
			shots += 1
			if bool(s.get("hit", false)):
				hits += 1; dmg += float(s.get("dmg", 0))
	print("  shots %d   hits %d   total damage %.0f" % [shots, hits, dmg])
	if shots == 0:
		print("  >>> NEVER ENGAGED — units never got in reach or never chose to attack")

	# distance between the two closest opposing units over time
	print("\n  t     closest gap   A0 state      A0 hp    SQUISHY hp")
	for i in range(0, frames.size(), maxi(1, frames.size()/8)):
		var u: Array = frames[i].get("units", [])
		if u.size() < 6: continue
		var best := 9999.0
		for x in range(3):
			for y in range(3, 6):
				best = minf(best, (u[x]["pos"] as Vector2).distance_to(u[y]["pos"] as Vector2))
		print("  %5.1f   %8.1f     %-12s %6.1f   %6.1f" % [
			float(frames[i].get("t",0.0)), best, str(u[0].get("state","?")),
			float(u[0].get("hp",0)), float(u[3].get("hp",0))])
	get_tree().quit(0)
