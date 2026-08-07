## Does decoupling facing from travel actually produce backpedalling and sidestepping — or do
## units still just walk where they look? Buckets every moving tick by the angle between the
## body's FACING and its TRAVEL direction.
extends Node
func _ready() -> void:
	for layout in ["four_pillar", "central_mass"]:
		var Sim = load("res://scripts/spatial_sim.gd")
		var L = load("res://scripts/arena_layout.gd")
		var a: Array = []; var b: Array = []
		for i in range(5):
			a.append(GameData.make_monster(Art.ROSTER[i], 0.35))
			b.append(GameData.make_monster(Art.ROSTER[i + 5], 0.35))
		var rng := RandomNumberGenerator.new(); rng.seed = 20260805
		var obs: Array = L.generate(5, "Platinum", rng, layout).get("obstacles", [])
		var sim = Sim.new(a, b, 20260805, {}, {}, {}, obs)
		var res: Dictionary = await sim.run()
		var fwd := 0; var side := 0; var back := 0
		for f in res.get("frames", []):
			for u in f.get("units", []):
				var md: Vector2 = u.get("moveDir", Vector2.ZERO)
				var fc: Vector2 = u.get("facing", Vector2.ZERO)
				if md.length_squared() < 0.000001 or fc.length_squared() < 0.000001:
					continue
				var d: float = fc.normalized().dot(md.normalized())
				if d > 0.35: fwd += 1
				elif d < -0.35: back += 1
				else: side += 1
		var tot: float = maxf(1.0, float(fwd + side + back))
		print("%-14s moving ticks %4d | forward %4.1f%% | SIDESTEP %4.1f%% | BACKPEDAL %4.1f%%" % [
			layout, int(tot), 100.0*fwd/tot, 100.0*side/tot, 100.0*back/tot])
	get_tree().quit()
