## Same mesh, same rig, THREE textures. The UVs are identical (all three refines ran on the same
## preview geometry), so this is a free comparison — no generation, no credits.
extends Node3D
const RigScript = preload("res://scripts/ui/creature_rig.gd")

const TEX := [
	["new flat", "res://assets/models/anim/kongrath_advance_texture_0.png"],
	["lp2 proven", "res://assets/models/kongrath_lp2_final_0.jpg"],
	["first refine", "res://assets/models/kongrath_lowpoly_0.jpg"],
]

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
	var pm := PlaneMesh.new(); pm.size = Vector2(30, 30); fl.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.48, 0.46, 0.44)
	fl.material_override = fm; add_child(fl)

	for i in range(TEX.size()):
		var rig = RigScript.new(); add_child(rig)
		rig.position = Vector3(-3.0 + i * 3.0, 0, 0)
		rig.build("kongrath", 2.6)
		rig.set_state("idle", Vector2(0, 1))
		var path: String = TEX[i][1]
		var mi := _find(rig, "MeshInstance3D") as MeshInstance3D
		if ResourceLoader.exists(path):
			(mi.material_override as ShaderMaterial).set_shader_parameter("albedo_texture", load(path))
		else:
			print("MISSING ", path)
		var lbl := Label3D.new(); lbl.text = TEX[i][0]
		lbl.font_size = 40; lbl.pixel_size = 0.005
		lbl.position = Vector3(-3.0 + i * 3.0, 3.15, 0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED; add_child(lbl)

	var cam := Camera3D.new()
	cam.fov = 30.0; cam.position = Vector3(0, 1.6, 13.0)
	cam.rotation_degrees = Vector3(-4, 0, 0)
	add_child(cam); cam.make_current()
	for i in range(60): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://tex_cmp.png")
	print("shot -> ", ProjectSettings.globalize_path("user://tex_cmp.png"))
	get_tree().quit()

func _find(n: Node, c: String) -> Node:
	if n.is_class(c): return n
	for k in n.get_children():
		var r := _find(k, c)
		if r != null: return r
	return null
