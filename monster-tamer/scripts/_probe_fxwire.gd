extends Node
const Innates = preload("res://scripts/innate_fx.gd")
func _ready() -> void:
	var Sim = load("res://scripts/spatial_sim.gd")
	var a: Array = []; var b: Array = []
	for i in range(2):
		var m = GameData.make_monster(Art.ROSTER[i], 0.35)
		m.innate = [{"name": "Chest Beat"}]
		m.happiness = 10
		a.append(m)
		b.append(GameData.make_monster(Art.ROSTER[i + 5], 0.35))
	var sim = Sim.new(a, b, 5, {}, {}, {}, [])
	print("table size: ", GameData.innate_effects.size())
	print("fx of a0: ", sim.spatial_state[a[0]].get("fx"))
	# smoking gun: same 1v1, one side with an absurd test innate vs none. If damage is equal,
	# afx is not reaching _resolve_hit at all.
	GameData.innate_effects["__TEST__"] = {"dmgMult": 5.0}
	for use in [false, true]:
		var Sim2 = load("res://scripts/spatial_sim.gd")
		var mr := RandomNumberGenerator.new(); mr.seed = 3
		var x = GameData.make_monster(Art.ROSTER[0], 0.35, mr)
		var y = GameData.make_monster(Art.ROSTER[5], 0.35, mr)
		x.happiness = 10
		x.innate = [{"name": "__TEST__"}] if use else []
		var s2 = Sim2.new([x], [y], 3, {}, {}, {}, [])
		var r2: Dictionary = await s2.run()
		print("innate=%s -> frames %d, enemy hp %.0f, fx %s" % [str(use), (r2["frames"] as Array).size(), maxf(0.0, y.hp), str(s2.spatial_state[x].get("fx"))])
	get_tree().quit()
