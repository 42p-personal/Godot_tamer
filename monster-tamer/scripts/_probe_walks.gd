## THREE WALK CANDIDATES, SIX FRAMES EACH, SAME CAMERA. Judge motion by its keyframes.
extends Node3D

const RigScript = preload("res://scripts/ui/creature_rig.gd")
const CANDIDATES := [
	["kongrathB", "OLD bind pose - 106 Confident_Walk"],
	["kongrath",  "NEW A-pose bind - 106 Confident_Walk"],
]
const N := 6

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.14, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.48, 0.58); e.ambient_light_energy = 0.6
	env.environment = e; add_child(env)
	var lamp := DirectionalLight3D.new()
	lamp.light_color = Color(1.0, 0.82, 0.55); lamp.light_energy = 2.2
	lamp.rotation_degrees = Vector3(-50, -30, 0); add_child(lamp)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(40, 40); fl.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.48, 0.46, 0.44)
	fl.material_override = fm; add_child(fl)
	var cam := Camera3D.new()
	cam.fov = 38.0; cam.position = Vector3(0, 2.2, 15.0)
	cam.rotation_degrees = Vector3(-5, 0, 0)
	add_child(cam); cam.make_current()

	for c in CANDIDATES:
		var rigs := []
		var players := []
		for i in range(N):
			var rig = RigScript.new(); add_child(rig)
			rig.position = Vector3(-6.25 + i * 2.5, 0, 0)
			if not rig.build(c[0], 2.6):
				print("BUILD FAILED ", c[0]); continue
			# 3/4 view — a walk read dead-on hides the stride
			rig.set_state("advance", Vector2(0.55, 0.84))
			rigs.append(rig); players.append(_find(rig, "AnimationPlayer"))
		await get_tree().process_frame
		var ap: AnimationPlayer = players[0]
		var length: float = ap.get_animation(ap.current_animation).length
		for i in range(N):
			players[i].seek(length * (float(i) / float(N - 1)) * 0.999, true)
			players[i].pause()
		for f in range(4): await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://walk_%s.png" % c[0])
		print("  %-11s %-20s %.2fs -> walk_%s.png" % [c[0], c[1], length, c[0]])
		for r in rigs: r.queue_free()
		await get_tree().process_frame
	print("done")
	get_tree().quit()

func _find(n: Node, c: String) -> Node:
	if n.is_class(c): return n
	for k in n.get_children():
		var r := _find(k, c)
		if r != null: return r
	return null
