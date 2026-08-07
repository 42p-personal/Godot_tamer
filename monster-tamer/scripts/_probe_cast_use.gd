## Drafted-but-never-cast: across 12 fights, which moves sat in a kit and were never used?
extends Node
func _ready() -> void:
	var in_kit := {}
	var cast := {}
	var L = load("res://scripts/arena_layout.gd")
	for seed_i in range(12):
		var Sim = load("res://scripts/spatial_sim.gd")
		var mrng := RandomNumberGenerator.new(); mrng.seed = 500 + seed_i
		var a: Array = []; var b: Array = []
		for i in range(5):
			a.append(GameData.make_monster(Art.ROSTER[i], [0.35, 0.7][seed_i % 2], mrng))
			b.append(GameData.make_monster(Art.ROSTER[i + 5], [0.35, 0.7][seed_i % 2], mrng))
		var rng := RandomNumberGenerator.new(); rng.seed = 500 + seed_i
		var obs: Array = L.generate(5, "Platinum", rng, ["four_pillar","central_mass"][seed_i % 2]).get("obstacles", [])
		var sim = Sim.new(a, b, 500 + seed_i, {}, {}, {}, obs)
		var res: Dictionary = await sim.run()
		for m in a + b:
			for mv in m.moveset:
				in_kit[mv["name"]] = int(in_kit.get(mv["name"], 0)) + 1
		for f in res.get("frames", []):
			for sh in f.get("shots", []):
				cast[str(sh.get("move",""))] = true
		for e in res.get("log", []):
			if e.has("move"): cast[str(e["move"])] = true
	var dead: Array = []
	for nm in in_kit:
		if not cast.has(nm):
			dead.append("%s (in %d kits)" % [nm, in_kit[nm]])
	print("moves that appeared in kits: %d | of those, cast at least once: %d" % [in_kit.size(), in_kit.size() - dead.size()])
	dead.sort()
	print("IN A KIT BUT NEVER CAST (%d):" % dead.size())
	for x in dead: print("  ", x)
	get_tree().quit()
