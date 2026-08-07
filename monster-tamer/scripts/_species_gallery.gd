## THE SPECIES GALLERY — all 65 species as their mapped pack bodies, in a labelled grid, for a
## casting review by eye. Dev scene.
extends Node3D
const Rig = preload("res://scripts/ui/creature_rig.gd")

## Same control grammar as the arena's FREE camera: hold LMB and drag to pan, wheel to zoom.
var _cam: Camera3D
var _panning := false

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.15, 0.15, 0.18)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	add_child(sun)

	var ids: Array = []
	var names := {}
	for sp in GameData.species:
		ids.append(sp["id"])
		names[sp["id"]] = str(sp.get("name", sp["id"]))
	ids.sort()
	var cols := 10
	var sx := 7.0
	var sz := 9.0
	for i in range(ids.size()):
		var cx := (i % cols - cols / 2.0 + 0.5) * sx
		var cz := (i / cols) * sz
		var rig = Rig.new()
		add_child(rig)
		rig.position = Vector3(cx, 0, cz)
		var model: String = Art.pack_model_for(ids[i])
		# ⚠️ Pass the SPECIES id, never the model id — build() resolves the model itself, and the
		# species id is what keys SPECIES_TINT. Passing the model here silently skipped every tint.
		if not rig.build(ids[i], 4.0):
			var box := MeshInstance3D.new()
			box.mesh = BoxMesh.new()
			rig.add_child(box)
		rig.set_state("idle", Vector2(0, 1))
		var lbl := Label3D.new()
		lbl.text = "%s\n(%s · %s)" % [names[ids[i]], ids[i], model]
		lbl.font_size = 40
		lbl.outline_size = 12
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.pixel_size = 0.011
		lbl.position = Vector3(cx, 5.6, cz)
		add_child(lbl)

	var rows := ceili(float(ids.size()) / cols)
	var cam := Camera3D.new()
	var mid_z := (rows - 1) * sz * 0.5
	cam.position = Vector3(0, 42, mid_z + 44)
	add_child(cam)
	cam.look_at(Vector3(0, 0, mid_z - 4))
	# ⚠️ ORTHOGRAPHIC (user 2026-08-07: "scale them so they are similar size"). Every rig is
	# already normalised to the same world height — the size spread the eye saw was PERSPECTIVE,
	# the front row being three times nearer the lens. An ortho camera makes equal world height
	# equal pixels on every row, which is the honest instrument for comparing castings.
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 46.0
	_cam = cam


## ⚠️ `_input`, not `_unhandled_input` — the tutorial overlay (an autoload Control) eats mouse
## events before they reach the unhandled stage, and this is a dev scene where the camera should
## always win.
func _input(event: InputEvent) -> void:
	if _cam == null:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_panning = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			# Ortho zoom is the frame SIZE, not camera travel; clamped tight-portrait..whole-grid.
			var zf := 0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.14
			_cam.size = clampf(_cam.size * zf, 8.0, 80.0)
	elif event is InputEventMouseMotion and _panning:
		# Pan in the camera's ground plane: screen-x follows the camera's right axis, screen-y
		# follows its forward axis flattened to the ground, so the drag never tilts the view.
		# World-per-pixel in ortho is frame size over viewport height, so zoomed-in drags stay precise.
		var right := _cam.global_transform.basis.x
		var fwd := -_cam.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var k: float = _cam.size / float(get_viewport().get_visible_rect().size.y)
		_cam.global_position += (-right * event.relative.x + fwd * event.relative.y) * k
