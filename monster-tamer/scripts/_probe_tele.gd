extends Node
func _ready() -> void:
	var mv_by := {}
	for mv in GameData.moves: mv_by[mv["name"]] = mv
	var aoe_cast_frames := 0
	for seed_i in range(4):
		var Sim = load("res://scripts/spatial_sim.gd")
		var mrng := RandomNumberGenerator.new(); mrng.seed = 60 + seed_i
		var a: Array = []; var b: Array = []
		for i in range(5):
			a.append(GameData.make_monster(Art.ROSTER[i], 0.6, mrng))
			b.append(GameData.make_monster(Art.ROSTER[i + 5], 0.6, mrng))
		var sim = Sim.new(a, b, 60 + seed_i, {}, {}, {}, [])
		var res: Dictionary = await sim.run()
		for f in res.get("frames", []):
			for u in f.get("units", []):
				var cm := str(u.get("castMove", ""))
				if cm != "" and str((mv_by.get(cm, {}) as Dictionary).get("target", "")) == "allEnemies":
					aoe_cast_frames += 1
	print("frames where an AoE windup is telegraphable: %d  %s" % [aoe_cast_frames, "OK" if aoe_cast_frames > 0 else "*** FAIL"])
	get_tree().quit()
