## ONE ANIMATION AT A TIME: six frames evenly across each clip's length, side by side, frozen.
## The only way to judge a motion is to see its keyframes; a single pose proves nothing.
extends Node3D

const RigScript = preload("res://scripts/ui/creature_rig.gd")
const CLIPS := ["advance"]
const N := 8

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
	lamp.rotation_degrees = Vector3(-50, -34, 0); add_child(lamp)

	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(40, 40); fl.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.48, 0.46, 0.44)
	fl.material_override = fm; add_child(fl)

	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.position = Vector3(0, 2.4, 15.5)
	cam.rotation_degrees = Vector3(-7, 0, 0)
	add_child(cam); cam.make_current()

	var rigs := []
	var players := []
	for i in range(N):
		var rig = RigScript.new(); add_child(rig)
		rig.position = Vector3(-7.0 + i * 2.0, 0, 0)
		rig.build("kongrath", 2.6)
		rig.set_state("advance", Vector2(0.6, 0.8))
		rigs.append(rig)
		players.append(_find(rig, "AnimationPlayer"))

	for clip in CLIPS:
		for i in range(N):
			rigs[i].set_state(clip, Vector2(0, 1))
		await get_tree().process_frame
		var ap: AnimationPlayer = players[0]
		var length: float = ap.get_animation(ap.current_animation).length
		for i in range(N):
			var p: AnimationPlayer = players[i]
			p.seek(length * (float(i) / float(N - 1)) * 0.999, true)
			p.pause()
		for f in range(3):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://strip_%s.png" % clip)
		print("  %-9s length %.2fs -> strip_%s.png" % [clip, length, clip])
		for i in range(N):
			players[i].play()
	print("done")
	get_tree().quit()

func _find(n: Node, c: String) -> Node:
	if n.is_class(c): return n
	for k in n.get_children():
		var r := _find(k, c)
		if r != null: return r
	return null
