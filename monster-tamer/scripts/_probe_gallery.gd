## The CC0 creature set, on the arena's own lamp. Two sheets: the roster, and one creature's states.
extends Node3D
const RigScript = preload("res://scripts/ui/creature_rig.gd")

var PICK := ["goleling", "goleling_evolved", "armabee", "armabee_evolved", "dragon",
			 "dragon_evolved", "glub_evolved", "hywirl", "mushnub", "alpaking",
			 "squidle", "monkroose", "yeti", "demon", "crab_enemy", "green_spiky_blob",
			 "dino", "orc", "goblin", "skeleton"]

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.14, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.42, 0.48, 0.58); e.ambient_light_energy = 0.65
	env.environment = e; add_child(env)
	var lamp := DirectionalLight3D.new()
	lamp.light_color = Color(1.0, 0.86, 0.62); lamp.light_energy = 2.1
	lamp.rotation_degrees = Vector3(-48, -28, 0); add_child(lamp)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(60, 60); fl.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.50, 0.48, 0.45)
	fl.material_override = fm; add_child(fl)
	var cam := Camera3D.new()
	cam.fov = 30.0; cam.position = Vector3(0, 6.0, 34.0)
	cam.rotation_degrees = Vector3(-7, 0, 0)
	add_child(cam); cam.make_current()

	# SHEET 1 — ten creatures, two rows, idling
	var made := []
	for i in range(PICK.size()):
		var rig = RigScript.new(); add_child(rig)
		var col := i % 10
		var row := i / 10
		rig.position = Vector3(-15.75 + col * 3.5, 0, -row * 6.0)
		if not rig.build(PICK[i], 2.4):
			print("no model: ", PICK[i]); rig.queue_free(); continue
		rig.set_state("idle", Vector2(0, 1))
		made.append(rig)
		var lbl := Label3D.new(); lbl.text = PICK[i]
		lbl.font_size = 40; lbl.pixel_size = 0.0055
		lbl.position = Vector3(-15.75 + col * 3.5, 3.05, -row * 6.0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; add_child(lbl)
	print("built %d creatures" % made.size())
	for i in range(70): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://pack_roster.png")
	print("shot -> pack_roster.png")
	for r in made: r.queue_free()
	for l in get_children():
		if l is Label3D: l.queue_free()
	await get_tree().process_frame

	# SHEET 2 — one creature, every sim state
	cam.fov = 40.0; cam.position = Vector3(0, 2.4, 13.0); cam.rotation_degrees = Vector3(-6, 0, 0)
	var states := ["idle", "advance", "attack", "cast", "stunned", "dead"]
	var rigs := []
	for i in range(states.size()):
		var rig = RigScript.new(); add_child(rig)
		rig.position = Vector3(-6.25 + i * 2.5, 0, 0)
		rig.build("goleling_evolved", 2.4)
		rig.set_state(states[i], Vector2(0.5, 0.86))
		rigs.append(rig)
		var lbl := Label3D.new(); lbl.text = states[i]
		lbl.font_size = 34; lbl.pixel_size = 0.004
		lbl.position = Vector3(-6.25 + i * 2.5, 2.95, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; add_child(lbl)
	for i in range(80): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://pack_states.png")
	print("shot -> pack_states.png  at ", ProjectSettings.globalize_path("user://"))
	get_tree().quit()
