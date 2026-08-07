## Does any unit ever stand INSIDE an obstacle? Counts penetration ticks and worst depth,
## per layout. Also checks tick-to-tick teleports while we're here.
extends Node
const Sp = preload("res://scripts/spatial.gd")
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
		var pen_ticks := 0; var worst := 0.0; var total := 0
		var tele := 0
		var last := {}
		for f in res.get("frames", []):
			for u in f.get("units", []):
				if not bool(u.get("alive", true)): continue
				var p: Vector2 = u.get("pos", Vector2.ZERO)
				total += 1
				var id = u.get("id")
				if last.has(id) and (last[id] as Vector2).distance_to(p) > 4.0:
					tele += 1
				last[id] = p
				# ⚠️ Obstacles carry a `rect` (Rect2), not pos/w/h. The first version of this probe
				# read keys that do not exist, so every obstacle defaulted to a zero rect and the
				# probe reported 0% while testing NOTHING. A probe that cannot fail is not a probe.
				for o in obs:
					if str(o.get("grade", "")) != "blocking":
						continue
					var r: Rect2 = o.get("rect", Rect2())
					if r.has_point(p):
						pen_ticks += 1
						var c := r.get_center()
						worst = maxf(worst, minf(r.size.x * 0.5 - absf(p.x - c.x), r.size.y * 0.5 - absf(p.y - c.y)))
						break
		print("%-14s unit-ticks %6d | INSIDE an obstacle %4d (%5.2f%%) | worst depth %5.2f | teleports(>4u/tick) %d" % [
			layout, total, pen_ticks, 100.0 * pen_ticks / maxf(1.0, float(total)), worst, tele])
		print("      obstacle sample: ", obs[0] if obs.size() > 0 else "none")
	get_tree().quit()
