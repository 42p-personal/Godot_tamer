## Judge the SILHOUETTE before paying to texture it — ART_BIBLE_LOWPOLY.md's acceptance test.
## Left: lit geometry. Right: flat black, which is the test that actually matters at 40px.
extends Node3D

const NEW_MODEL := "res://assets/models/kongrath_preview.glb"
const OLD_MODEL := "res://assets/models/kongrath_lp2_preview.glb"

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.86, 0.86, 0.88)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.62); e.ambient_light_energy = 0.7
	env.environment = e; add_child(env)
	var lamp := DirectionalLight3D.new()
	lamp.light_color = Color(1.0, 0.86, 0.62); lamp.light_energy = 2.0
	lamp.rotation_degrees = Vector3(-46, -32, 0); add_child(lamp)

	var specs := [[OLD_MODEL, false, -4.2], ["res://assets/models/kongrathA_preview.glb", false, -1.4],
				  [NEW_MODEL, false, 1.4], [NEW_MODEL, true, 4.2]]
	for s in specs:
		if not ResourceLoader.exists(s[0]):
			print("MISSING ", s[0]); continue
		var n: Node3D = (load(s[0]) as PackedScene).instantiate()
		add_child(n)
		var mi := _find(n, "MeshInstance3D") as MeshInstance3D
		# ⚠️ Bounds in the INSTANCE's own space — the importer parks its own scale between the
		# scene root and the mesh, and it differs per export, so comparing two models by their raw
		# local AABBs compares two different units.
		var rel: Transform3D = n.global_transform.affine_inverse() * mi.global_transform
		var aabb: AABB = rel * mi.get_aabb()
		var sc: float = 2.2 / maxf(0.0001, aabb.size.y)
		n.scale = Vector3.ONE * sc
		n.position = Vector3(s[2], -aabb.position.y * sc, 0)
		if s[1]:
			var m := StandardMaterial3D.new()
			m.albedo_color = Color.BLACK
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mi.material_override = m
		var tris := 0
		for si in range(mi.mesh.get_surface_count()):
			tris += mi.mesh.surface_get_array_index_len(si) / 3
		print("%-46s tris=%d %s" % [s[0].get_file(), tris, "SILHOUETTE" if s[1] else "lit"])

	var cam := Camera3D.new()
	cam.fov = 34.0; cam.position = Vector3(0, 1.15, 10.5)
	add_child(cam); cam.make_current()
	for i in range(40): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://preview_cmp.png")
	print("shot -> ", ProjectSettings.globalize_path("user://preview_cmp.png"))
	get_tree().quit()

func _find(n: Node, c: String) -> Node:
	if n.is_class(c): return n
	for k in n.get_children():
		var r := _find(k, c)
		if r != null: return r
	return null
