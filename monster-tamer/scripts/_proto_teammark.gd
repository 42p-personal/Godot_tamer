## Team identity attached IN-ENGINE — the same creature in two liveries, at the arena camera.
extends Node3D

const TeamMarker = preload("res://scripts/ui/team_marker.gd")
const UNIT_H := 2.0

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.11, 0.11, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.52, 0.54, 0.60)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-56, -38, 0)
	sun.light_energy = 1.5
	add_child(sun)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(30, 30)
	ground.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.75, 0.73, 0.68)
	ground.material_override = gm
	add_child(ground)

	var packed = load("res://assets/models/kongrath_lowpoly.glb")
	var sides := [
		{"i": 0, "x": -1.6, "label": "team A"},
		{"i": 1, "x":  1.6, "label": "team B"},
	]
	for s in sides:
		var holder := Node3D.new()
		holder.position = Vector3(s["x"], 0, 0)
		add_child(holder)

		var vis: Node3D = packed.instantiate() if packed != null else Node3D.new()
		holder.add_child(vis)
		# normalise the model to UNIT_H so the marks scale predictably
		var aabb := TeamMarker._visual_aabb(vis)
		if aabb.size.y > 0.001:
			var k := UNIT_H / aabb.size.y
			vis.scale = Vector3(k, k, k)

		holder.add_child(TeamMarker.make_ring(UNIT_H, int(s["i"])))
		var sash = TeamMarker.make_sash(vis, UNIT_H, int(s["i"]))
		if sash != null:
			holder.add_child(sash)

		var ident: Dictionary = Art.team_identity(int(s["i"]))
		var tag := Label3D.new()
		tag.text = "%s  %s" % [str(s["label"]), str(ident["badge"])]
		tag.font_size = 44; tag.outline_size = 14
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.pixel_size = 0.0035
		tag.modulate = ident["colour"]
		tag.position = Vector3(s["x"], UNIT_H * 1.35, 0)
		add_child(tag)

	var cam := Camera3D.new()
	cam.fov = 26.0
	var theta := deg_to_rad(38.0)
	var r := 3.4 / tan(deg_to_rad(13.0))
	cam.position = Vector3(0, r * sin(theta), r * cos(theta))
	add_child(cam)
	cam.look_at(Vector3(0, UNIT_H * 0.45, 0), Vector3.UP)
	cam.current = true
