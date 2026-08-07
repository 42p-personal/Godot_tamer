## central_mass now times out at 1801 frames. WHO is stuck, WHERE, doing WHAT?
extends Node
func _ready() -> void:
	# Reproduce the interrupt probe's EXACT process state: it runs four_pillar first, and monster
	# creation consumes shared rng, so the second fight fields different monsters.
	await _run_one("central_mass", true)

func _run_one(layout: String, verbose: bool) -> void:
	var Sim = load("res://scripts/spatial_sim.gd")
	var L = load("res://scripts/arena_layout.gd")
	var mrng := RandomNumberGenerator.new(); mrng.seed = 9001
	var a: Array = []; var b: Array = []
	for i in range(5):
		a.append(GameData.make_monster(Art.ROSTER[i], 0.35, mrng))
		b.append(GameData.make_monster(Art.ROSTER[i + 5], 0.35, mrng))
	var rng := RandomNumberGenerator.new(); rng.seed = 9001
	var obs: Array = L.generate(5, "Platinum", rng, layout).get("obstacles", [])
	var sim = Sim.new(a, b, 9001, {}, {}, {}, obs)
	var res: Dictionary = await sim.run()
	var frames: Array = res.get("frames", [])
	print("%s frames: %d" % [layout, frames.size()])
	if not verbose:
		return
	var lastf: Dictionary = frames[frames.size() - 1]
	# how much did each survivor MOVE over the last 200 frames?
	var t0: Dictionary = frames[maxi(0, frames.size() - 200)]
	for i in range((lastf["units"] as Array).size()):
		var u: Dictionary = lastf["units"][i]
		if not bool(u.get("alive", true)): continue
		var p0: Vector2 = (t0["units"][i] as Dictionary).get("pos", Vector2.ZERO)
		var p1: Vector2 = u.get("pos", Vector2.ZERO)
		print("  id %d hp %5.0f  pos %s  moved(last 20s) %5.1f  state %-8s tgt %2d  %s" % [
			int(u["id"]), float(u.get("hp", 0)), str(p1.round()), p0.distance_to(p1),
			str(u.get("state", "")), int(u.get("targetId", -1)), str(u.get("reason", ""))])
	for o in obs:
		if str(o.get("grade","")) == "blocking":
			print("  wall: ", o.get("rect"))
	get_tree().quit()
