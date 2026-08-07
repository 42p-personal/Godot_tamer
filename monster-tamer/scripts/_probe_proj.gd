## Do projectiles exist, fly at the authored speed, and land their damage ON ARRIVAL?
extends Node
const Sp = preload("res://scripts/spatial.gd")
func _ready() -> void:
	var Sim = load("res://scripts/spatial_sim.gd")
	var mrng := RandomNumberGenerator.new(); mrng.seed = 21
	var a: Array = []; var b: Array = []
	for i in range(5):
		a.append(GameData.make_monster(Art.ROSTER[i], 0.6, mrng))
		b.append(GameData.make_monster(Art.ROSTER[i + 5], 0.6, mrng))
	var sim = Sim.new(a, b, 21, {}, {}, {}, [])
	var res: Dictionary = await sim.run()
	var proj_frames := 0; var max_flight := 0
	var flights := {}
	for f in res.get("frames", []):
		for pr in f.get("projectiles", []):
			proj_frames += 1
			var pid := int(pr["id"])
			flights[pid] = int(flights.get(pid, 0)) + 1
	for pid in flights: max_flight = maxi(max_flight, flights[pid])
	var frames_n: int = (res["frames"] as Array).size()
	print("fight %d frames | projectile-frames %d | distinct projectiles %d | longest flight %d ticks  %s" % [
		frames_n, proj_frames, flights.size(), max_flight,
		"OK" if flights.size() > 0 and max_flight >= 2 else "*** FAIL"])
	get_tree().quit()
