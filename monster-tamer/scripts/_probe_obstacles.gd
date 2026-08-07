## THE OBSTACLE CANDIDATES, AT COVER GRADE, WITH A CREATURE FOR SCALE.
## ⚠️ The grades are what the sim means by cover (`arena_layout.gd`): soft 1.0 / hard 2.0 /
## blocking 3.2 — expressed in the game's own units, which `GEOMETRY_SCALE` has since moved. A
## prop is only useful if it still reads as that grade when scaled to it, so each is shown at the
## height the sim will actually give it, beside a monster.
extends Node3D
const RigScript = preload("res://scripts/ui/creature_rig.gd")

const GRADE := {"soft": 1.0, "hard": 2.0, "blocking": 3.2}
const PICKS := [
	["barrel",          "soft",     "Rock (Kenney)"],
	["crate",           "soft",     "Crate (KayLousberg)"],
	["crate_alt",       "soft",     "Crate (Quaternius)"],
	["planter",         "soft",     "Bush (Quaternius)"],
	["planter_hedge",   "hard",     "Hedge (Quaternius)"],
	["low_wall",        "hard",     "Wall Low (Kenney)"],
	["low_wall_border", "hard",     "Border High (Kenney)"],
	["pillar",          "blocking", "Column Wide (Kenney)"],
	["pillar_thin",     "blocking", "Column Thin (Kenney)"],
	["barrel_alt",      "soft",     "Rock Med (Quaternius)"],
	["boulder",         "hard",     "Rock Med 244 (Quaternius)"],
	["boulder_alt",     "hard",     "Rock Med 522 (Quaternius)"],
	["shrine",          "blocking", "Shrine (KayLousberg)"],
	["shrine_alt",      "blocking", "Shrine 360 (KayLousberg)"],
	["bench",           "soft",     "Bench (Quaternius)"],
	["bench_alt",       "soft",     "Bench (KayLousberg)"],
	["fence",           "soft",     "Fence (Quaternius)"],
	["fence_alt",       "soft",     "Fence 324 (Quaternius)"],
]

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.14, 0.17)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.44, 0.50, 0.60); e.ambient_light_energy = 0.7
	env.environment = e; add_child(env)
	var lamp := DirectionalLight3D.new()
	lamp.light_color = Color(1.0, 0.86, 0.62); lamp.light_energy = 2.0
	lamp.rotation_degrees = Vector3(-48, -30, 0); lamp.shadow_enabled = true
	add_child(lamp)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(80, 80); fl.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.52, 0.50, 0.47)
	fl.material_override = fm; add_child(fl)

	# A monster at the sim's real body scale, for size reference.
	var rig = RigScript.new(); add_child(rig)
	rig.position = Vector3(-14.5, 0, 0)
	rig.build("orc", 4.4)
	rig.set_state("idle", Vector2(0, 1))
	_label("MONSTER 4.4", Vector3(-14.5, 5.4, 0))

	print("%-17s %-9s %6s %7s  %s" % ["file", "grade", "tris", "scale", "footprint after scaling"])
	for i in range(PICKS.size()):
		var id: String = PICKS[i][0]
		var p := "res://assets/models/obstacles/%s.glb" % id
		if not ResourceLoader.exists(p):
			print("MISSING ", id); continue
		var n: Node3D = (load(p) as PackedScene).instantiate()
		add_child(n)
		var mi := _find(n, "MeshInstance3D") as MeshInstance3D
		var rel: Transform3D = n.global_transform.affine_inverse() * mi.global_transform
		var ab: AABB = rel * mi.get_aabb()
		var target: float = GRADE[PICKS[i][1]]
		var s: float = target / maxf(0.001, ab.size.y)
		n.scale = Vector3.ONE * s
		var x := -10.0 + i * 2.6
		n.position = Vector3(x, -ab.position.y * s, 0)
		var tris := 0
		for si in range(mi.mesh.get_surface_count()):
			tris += mi.mesh.surface_get_array_index_len(si) / 3
		print("%-17s %-9s %6d %7.2f  %.1f x %.1f x %.1f" % [id, PICKS[i][1], tris, s,
			ab.size.x * s, ab.size.y * s, ab.size.z * s])
		_label(PICKS[i][2], Vector3(x, 4.6, 0))
		_label(PICKS[i][1], Vector3(x, 4.1, 0))

	var cam := Camera3D.new()
	cam.fov = 34.0; cam.position = Vector3(-1.0, 4.6, 30.0)
	cam.rotation_degrees = Vector3(-9, 0, 0)
	add_child(cam); cam.make_current()
	for i in range(50): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://obstacles.png")
	print("shot -> ", ProjectSettings.globalize_path("user://obstacles.png"))
	get_tree().quit()

func _label(t: String, at: Vector3) -> void:
	var l := Label3D.new(); l.text = t; l.font_size = 30; l.pixel_size = 0.0065
	l.position = at; l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.outline_size = 8
	add_child(l)

func _find(n: Node, c: String) -> Node:
	if n.is_class(c): return n
	for k in n.get_children():
		var r := _find(k, c)
		if r != null: return r
	return null
