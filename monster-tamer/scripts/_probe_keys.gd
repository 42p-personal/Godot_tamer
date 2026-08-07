extends Node
func _ready() -> void:
	var Sim = load("res://scripts/spatial_sim.gd")
	var a: Array = []; var b: Array = []
	for i in range(5):
		a.append(GameData.make_monster(Art.ROSTER[i], 0.35))
		b.append(GameData.make_monster(Art.ROSTER[i + 5], 0.35))
	var sim = Sim.new(a, b, 1, {}, {}, {}, [])
	var res: Dictionary = await sim.run()
	var fr: Array = res.get("frames", [])
	print("frame keys: ", (fr[5] as Dictionary).keys())
	var us = (fr[5] as Dictionary).get("units", [])
	print("unit keys: ", (us[0] as Dictionary).keys())
	print("sample: ", us[0])
	get_tree().quit()
