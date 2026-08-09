extends Node
const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const ClassifyLib = preload("res://scripts/classify.gd")
const DeriveLib = preload("res://scripts/derive.gd")
## ⚠️ THIS PROBE USED TO HARDCODE `STEP := 0.06` / `HEAD := 0.30` WITH NO SPECIES FLOOR, AND ALL
## THREE WERE WRONG. The port had flattened the per-heritage potential step to a single 0.06 (the
## design is `town.ts:762 BREED_STEP_BY_TIER`, 0.10 wild to 0.15 primeval) and had dropped the
## `maxf` against the child's own species base (`town.ts:796`) — so this dynasty table UNDERSTATED
## both the climb and the hatch stats. Read the rules from the screen that owns them; never
## re-type them here, or the instrument drifts from the game the moment either is tuned.
const BreedScript = preload("res://scripts/ui/breeding_ui.gd")

## ⚠️ Goes through a typed local, NOT `BreedScript.get_script_constant_map()` directly — GDScript
## refuses to call a non-static method on a class reference at parse time, so the direct form is
## a hard parse error that takes the whole probe offline rather than a warning.
func _konst(name: String, fallback):
	var s: GDScript = BreedScript
	var m: Dictionary = s.get_script_constant_map()
	return m[name] if m.has(name) else fallback

func _child(a, b, n: int):
	var c = MonsterInstanceScript.new()
	c.id = "g%d" % n
	c.species_id = a.species_id; c.species_name = a.species_name; c.body = a.body
	var maxp: float = float(_konst("MAX_POTENTIAL", 2.0))
	var head: float = float(_konst("BREED_HEAD_START", 0.30))
	c.potential = minf(maxp, snappedf(maxf(a.potential, b.potential) + BreedScript._step_for(a, b), 0.01))
	# The species' own base is a FLOOR, not an alternative: a champion's foal must never hatch
	# weaker than the same species bought wild off the market.
	var base: Dictionary = GameData.species_by_id.get(c.species_id, {}).get("base", {})
	c.stats = {}
	for s in ["STR","DEX","CON","WIS","INT","CHA"]:
		c.stats[s] = maxf(float(base.get(s, 10.0)),
			maxf(1.0, round((float(a.stats[s]) + float(b.stats[s])) * 0.5 * head)))
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
