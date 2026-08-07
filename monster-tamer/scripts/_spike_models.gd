## Meshy spike viewer — the three models at the REAL arena camera distance.
extends Node3D

const MODELS := [
	{"path": "res://assets/models/kongrath.glb",         "label": "kongrath (raw)"},
	{"path": "res://assets/models/kongrath_rigged.glb",  "label": "kongrath (rigged, 24 joints)"},
	{"path": "res://assets/models/larkessa.glb",         "label": "larkessa (auto-rig REFUSED)"},
]

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.09, 0.11)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.45, 0.48, 0.55)
	e.ambient_light_energy = 0.7
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-56, -38, 0)
	sun.light_energy = 1.5
	add_child(sun)

	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mesh.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.70, 0.66)
	floor_mesh.material_override = mat
	add_child(floor_mesh)

	var x := -4.0
	for m in MODELS:
		var packed = load(m["path"])
		if packed == null:
			push_warning("missing %s" % m["path"])
			x += 4.0
			continue
		var inst = packed.instantiate()
		inst.position = Vector3(x, 0, 0)
		add_child(inst)
		var lbl := Label3D.new()
		lbl.text = str(m["label"])
		lbl.font_size = 42
		lbl.outline_size = 12
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.pixel_size = 0.004
		lbl.position = Vector3(x, 2.6, 0)
		add_child(lbl)
		# play whatever animation shipped with it
		for c in inst.get_children():
			if c is AnimationPlayer:
				var names: PackedStringArray = c.get_animation_list()
				if names.size() > 0:
					c.play(names[0])
		x += 4.0

	# ⚠️ The arena camera, exactly: 38 degrees, 26 fov long lens.
	var cam := Camera3D.new()
	cam.fov = 26.0
	var theta := deg_to_rad(38.0)
	var r := 7.0 / tan(deg_to_rad(13.0))
	cam.position = Vector3(0, r * sin(theta), r * cos(theta))
	# ⚠️ add_child BEFORE look_at — look_at needs the node in the tree, otherwise Godot errors
	# with "Node not inside tree" and the camera keeps its default orientation.
	add_child(cam)
	cam.look_at(Vector3(0, 1.0, 0), Vector3.UP)
	cam.current = true
