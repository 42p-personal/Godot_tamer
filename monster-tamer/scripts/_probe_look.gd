## Two rigged creatures under the arena lamp: LEFT keeps the imported material, RIGHT gets the
## low-poly shader. Prints where each one lands on screen so an empty frame can be told apart
## from a mis-aimed camera.
extends Node3D
const RigScript = preload("res://scripts/ui/creature_rig.gd")

var cam: Camera3D

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.17, 0.20)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.48, 0.58)
	e.ambient_light_energy = 0.55
	env.environment = e
	add_child(env)

	var lamp := DirectionalLight3D.new()
	lamp.light_color = Color(1.0, 0.82, 0.55)
	lamp.light_energy = 2.2
	lamp.rotation_degrees = Vector3(-52, -38, 0)
	add_child(lamp)

	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(24, 24)
	fl.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.50, 0.48, 0.46)
	fl.material_override = fm
	add_child(fl)

	cam = Camera3D.new()
	cam.fov = 30.0
	cam.position = Vector3(0, 1.6, 12.0)
	cam.rotation_degrees = Vector3(-4, 0, 0)
	add_child(cam)
	cam.make_current()

	var states := ["advance", "advance", "advance"]
	var rigs := []
	for i in range(states.size()):
		var rig = RigScript.new()
		add_child(rig)
		rig.position = Vector3(-2.6 + i * 2.6, 0, 0)
		rig.build("kongrath", 2.6)
		rig.set_state(states[i], [Vector2(0, 1), Vector2(1, 0), Vector2(0, -1)][i])
		rigs.append(rig)
		var lbl := Label3D.new()
		lbl.text = ["front", "side", "back"][i]; lbl.font_size = 40; lbl.pixel_size = 0.004
		lbl.position = Vector3(-2.6 + i * 2.6, 3.15, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		add_child(lbl)

	for i in range(60):
		await get_tree().process_frame

	for i in range(rigs.size()):
		var mi := _find(rigs[i], "MeshInstance3D") as MeshInstance3D
		var wa: AABB = rigs[i].call("_skinned_bounds")
		wa = rigs[i].global_transform * wa
		var head: Vector3 = wa.position + Vector3(wa.size.x * 0.5, wa.size.y, wa.size.z * 0.5)
		var feet: Vector3 = wa.position + Vector3(wa.size.x * 0.5, 0, wa.size.z * 0.5)
		print("rig %d  %s  world y %.2f..%.2f  screen head=%s feet=%s  behind=%s" % [
			i, states[i], wa.position.y, wa.position.y + wa.size.y,
			cam.unproject_position(head), cam.unproject_position(feet),
			cam.is_position_behind(head)])

	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://rig_look.png")
	print("shot -> ", ProjectSettings.globalize_path("user://rig_look.png"))
	get_tree().quit()

func _find(n: Node, c: String) -> Node:
	if n.is_class(c): return n
	for k in n.get_children():
		var r := _find(k, c)
		if r != null: return r
	return null
