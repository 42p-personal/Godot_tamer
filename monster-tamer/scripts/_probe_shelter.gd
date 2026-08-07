## ARE THE MONSTERS ACTUALLY USING COVER? The honest test is not "did shelter improve this tick"
## — that measures noise on a 52-tick sample. It is: ARE UNITS MORE SHELTERED THAN CHANCE WOULD
## GIVE THEM? If a unit standing at a random legal spot is sheltered 9% of the time and the real
## units are sheltered 9% of the time, they are not using cover; they are standing where the fight
## put them.
##
## ⚠️ The baseline is sampled on the SAME board, from the SAME threats, at the SAME moments — so
## it controls for layout, for how spread the fight is, and for who happens to be shooting.
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
		var g: Vector2 = Sp.ground_size(5)
		var sim = Sim.new(a, b, 20260805, {}, {}, {}, obs)
		var frames: Array = (await sim.run()).get("frames", [])

		var brng := RandomNumberGenerator.new(); brng.seed = 99

		var real_sheltered := 0; var real_n := 0
		var rand_sheltered := 0; var rand_n := 0
		# split by kit, because only some kits SHOULD want cover
		var by_role := {}
		for f in frames:
			var us: Array = f.get("units", [])
			for i in range(us.size()):
				if not bool(us[i].get("alive", true)): continue
				# who is shooting at me right now?
				var threats: Array = []
				for e in range(us.size()):
					if e == i or not bool(us[e].get("alive", true)): continue
					if ((e < 5) == (i < 5)): continue
					if int(us[e].get("targetId", -1)) == i:
						threats.append(us[e]["pos"])
				if threats.is_empty(): continue

				var mypos: Vector2 = us[i]["pos"]
				var sh := 0
				for t in threats:
					if bool(Sp.cover_between(mypos, t, obs)["blocked"]): sh += 1
				real_sheltered += sh; real_n += threats.size()
				var key := "ranged" if _reach_of(i, a, b) > 40.0 else "melee"
				if not by_role.has(key): by_role[key] = [0, 0]
				by_role[key][0] += sh; by_role[key][1] += threats.size()

				# CHANCE BASELINE: the same unit teleported to a random legal spot, same threats.
				var rp := Vector2(brng.randf_range(6.0, g.x - 6.0), brng.randf_range(6.0, g.y - 6.0))
				for t in threats:
					if bool(Sp.cover_between(rp, t, obs)["blocked"]): rand_sheltered += 1
					rand_n += 1

		var real_pct: float = 100.0 * real_sheltered / maxf(1, real_n)
		var rand_pct: float = 100.0 * rand_sheltered / maxf(1, rand_n)
		print("── %s ──" % layout)
		print("   ACTUAL   shelter from live threats : %.1f%%  (%d of %d)" % [real_pct, real_sheltered, real_n])
		print("   CHANCE   same threats, random spot : %.1f%%  (%d of %d)" % [rand_pct, rand_sheltered, rand_n])
		print("   ratio    actual / chance           : %.2fx  %s" % [
			real_pct / maxf(0.01, rand_pct),
			"USING COVER" if real_pct > rand_pct * 1.25 else
			("AVOIDING cover" if real_pct < rand_pct * 0.8 else "indistinguishable from chance")])
		for k in by_role.keys():
			print("      %-7s %.1f%%  (%d of %d)" % [k, 100.0 * by_role[k][0] / maxf(1, by_role[k][1]),
				by_role[k][0], by_role[k][1]])
		print("")
	get_tree().quit()

func _reach_of(i: int, a: Array, b: Array) -> float:
	var T = load("res://scripts/ai/monster_tree.gd")
	var u = a[i] if i < 5 else b[i - 5]
	return T._unit_best_reach(u)
