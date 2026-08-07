## 10 seeds x both layouts: do fights RESOLVE with the obstacle resolver in, and does anyone
## ever stand inside a wall? The pass criteria for the whole movement rework.
extends Node
func _ready() -> void:
	for layout in ["four_pillar", "central_mass"]:
		var timeouts := 0; var pen_total := 0; var frames_sum := 0
		for seed_i in range(10):
			var Sim = load("res://scripts/spatial_sim.gd")
			var L = load("res://scripts/arena_layout.gd")
			var mrng := RandomNumberGenerator.new(); mrng.seed = 9000 + seed_i
			var a: Array = []; var b: Array = []
			for i in range(5):
				a.append(GameData.make_monster(Art.ROSTER[i], 0.35, mrng))
				b.append(GameData.make_monster(Art.ROSTER[i + 5], 0.35, mrng))
			var rng := RandomNumberGenerator.new(); rng.seed = 9000 + seed_i
			var obs: Array = L.generate(5, "Platinum", rng, layout).get("obstacles", [])
			var sim = Sim.new(a, b, 9000 + seed_i, {}, {}, {}, obs)
			var res: Dictionary = await sim.run()
			var frames: Array = res.get("frames", [])
			frames_sum += frames.size()
			if frames.size() >= 1800:
				timeouts += 1
				print("   TIMEOUT seed %d" % (9000 + seed_i))
			for f in frames:
				for u in f.get("units", []):
					if not bool(u.get("alive", true)): continue
					var p: Vector2 = u.get("pos", Vector2.ZERO)
					for o in obs:
						if str(o.get("grade","")) != "blocking": continue
						if (o.get("rect", Rect2()) as Rect2).has_point(p):
							pen_total += 1
							break
		print("%-14s 10 seeds | timeouts %d | mean frames %4d | wall-penetration ticks %d" % [
			layout, timeouts, frames_sum / 10, pen_total])
	get_tree().quit()
