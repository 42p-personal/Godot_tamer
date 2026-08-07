extends Node
const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const ClassifyLib = preload("res://scripts/classify.gd")
const DeriveLib = preload("res://scripts/derive.gd")
const STEP := 0.06
const MAXP := 2.0
const HEAD := 0.30

func _child(a, b, n: int):
	var c = MonsterInstanceScript.new()
	c.id = "g%d" % n
	c.species_id = a.species_id; c.species_name = a.species_name; c.body = a.body
	c.potential = minf(MAXP, snappedf(maxf(a.potential, b.potential) + STEP, 0.01))
	c.stats = {}
	for s in ["STR","DEX","CON","WIS","INT","CHA"]:
		c.stats[s] = maxf(1.0, round((float(a.stats[s]) + float(b.stats[s])) * 0.5 * HEAD))
	c.class_name_ = ClassifyLib.class_for_stats(c.stats)
	c.max_hp = DeriveLib.max_hp(c.stats["CON"])
	return c

func _ready() -> void:
	print("=== BREEDING — does a dynasty actually climb? ===\n")
	Career.reset_new_game(); Roster.reset_to_empty(); Roster._generate_starting_roster()
	var a = Roster.monsters[0]
	var b = Roster.monsters[1]
	print("  gen | potential | Wood cap | Apex cap | hatch STR")
	print("   P0 |   ×%.2f   |   %4d   |   %4d   |    %3d" % [
		a.potential, int(Career.stat_cap_for_league(0) * a.potential),
		int(Career.stat_cap_for_league(10) * a.potential), int(a.stats["STR"])])
	var p1 = a
	var p2 = b
	for g in range(1, 12):
		var kid = _child(p1, p2, g)
		print("   G%-2d |   ×%.2f   |   %4d   |   %4d   |    %3d" % [
			g, kid.potential, int(Career.stat_cap_for_league(0) * kid.potential),
			int(Career.stat_cap_for_league(10) * kid.potential), int(kid.stats["STR"])])
		p1 = kid
		# partner keeps pace, as a real breeding programme would
		p2 = _child(p2, kid, g)
	print("\n  A wild monster is ×1.00 and TRAINING CANNOT RAISE IT.")
	print("  Breeding is the only route past a league cap — that is the dynasty engine.")
	get_tree().quit(0)
