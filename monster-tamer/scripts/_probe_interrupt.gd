## Does cover INTERRUPT casts, and does that make cover worth wanting?
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
		var by_cover := 0; var by_control := 0
		var samples: Array = []
		for e in res.get("log", []):
			if str(e.get("kind", "")) == "interrupt":
				if "cover" in str(e.get("reason", "")): by_cover += 1
				else: by_control += 1
				if samples.size() < 3:
					samples.append("%s's %s — %s" % [e["unit"], e["move"], e["reason"]])
		# how telegraphed is the pool now?
		var winds := {}
		for f in res.get("frames", []):
			for u in f.get("units", []):
				if str(u.get("state","")) == "cast":
					winds["casting_ticks"] = int(winds.get("casting_ticks", 0)) + 1
		print("%-14s frames %-4d  INTERRUPTS: %d by cover, %d by control   (cast ticks %d)" % [
			layout, (res.get("frames", []) as Array).size(), by_cover, by_control,
			int(winds.get("casting_ticks", 0))])
		for s in samples:
			print("      e.g. %s" % s)
	get_tree().quit()
