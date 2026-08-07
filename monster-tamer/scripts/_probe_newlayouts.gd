extends Node
func _ready() -> void:
	var L = load("res://scripts/arena_layout.gd")
	for lay in ["triad", "lanes"]:
		var timeouts := 0; var pen := 0; var fr := 0
		for i in range(4):
			var Sim = load("res://scripts/spatial_sim.gd")
			var mrng := RandomNumberGenerator.new(); mrng.seed = 3000+i
			var a: Array = []; var b: Array = []
			for j in range(5):
				a.append(GameData.make_monster(Art.ROSTER[j], 0.5, mrng))
				b.append(GameData.make_monster(Art.ROSTER[j+5], 0.5, mrng))
			var rng := RandomNumberGenerator.new(); rng.seed = 3000+i
			var obs: Array = L.generate(5, "Platinum", rng, lay).get("obstacles", [])
			var sim = Sim.new(a, b, 3000+i, {}, {}, {}, obs)
			var res: Dictionary = await sim.run()
			var frames: Array = res.get("frames", [])
			fr += frames.size()
			if frames.size() >= 1800: timeouts += 1
			for f in frames:
				for u in f.get("units", []):
					if not bool(u.get("alive",true)): continue
					var pp: Vector2 = u.get("pos", Vector2.ZERO)
					for o in obs:
						if str(o.get("grade",""))=="blocking" and (o.get("rect",Rect2()) as Rect2).has_point(pp):
							pen += 1; break
		print("%-12s 4 seeds | timeouts %d | mean frames %d | penetration %d" % [lay, timeouts, fr/4, pen])
	get_tree().quit()
