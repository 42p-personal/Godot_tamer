## Measures WOBBLE: how sharply a unit's heading changes tick to tick, how often it reverses,
## and how DIRECT its path is (net displacement / distance walked). The user's report is
## "monsters wobble around the enemies" — this puts a number on it so a fix can be judged.
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

		var trails := {}
		var steps := 0; var reversals := 0; var turn_sum := 0.0
		var walked := 0.0; var sp_sum := 0.0; var sp_n := 0
		for f in res.get("frames", []):
			for u in f.get("units", []):
				var id = u.get("id")
				var p: Vector2 = u.get("pos", Vector2.ZERO)
				if not trails.has(id):
					trails[id] = {"pos": p, "first": p, "walk": 0.0}
					continue
				var t: Dictionary = trails[id]
				var d: Vector2 = p - (t["pos"] as Vector2)
				if d.length() > 0.01:
					t["walk"] = float(t["walk"]) + d.length()
					sp_sum += d.length() / Sp.DT; sp_n += 1
					if t.has("dir"):
						var ang := rad_to_deg(absf((t["dir"] as Vector2).angle_to(d)))
						turn_sum += ang; steps += 1
						if ang > 90.0: reversals += 1
					t["dir"] = d.normalized()
				t["pos"] = p
		var net := 0.0
		for id in trails:
			var t: Dictionary = trails[id]
			net += (t["first"] as Vector2).distance_to(t["pos"] as Vector2)
			walked += float(t["walk"])
		print("%-14s moving ticks %5d | mean heading change %5.1f deg | reversals(>90) %5.1f%% | directness %4.2f | mean speed %5.1f u/s" % [
			layout, steps, turn_sum / maxf(1.0, float(steps)), 100.0 * float(reversals) / maxf(1.0, float(steps)),
			net / maxf(0.001, walked), sp_sum / maxf(1.0, float(sp_n))])
	get_tree().quit()
