## PORTRAIT CAPTURE — renders every species' ACTUAL 3D rig (model + tint, the same
## creature_rig.gd build the arena fields) to a transparent 512x512 PNG in assets/creatures/,
## replacing the pre-rework painted portraits that still showed the OLD identities.
## Dev scene: run once, read the console, commit the PNGs. Deterministic by construction —
## same models + tints in, same pixels out.
extends Node3D
const Rig = preload("res://scripts/ui/creature_rig.gd")

const SIZE := 512
## A beat into the idle clip so the pose reads alive rather than bind-stiff.
const POSE_TIME := 0.35

var _vp: SubViewport
var _cam: Camera3D


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	# The subviewport owns its world, so it needs its own light rig: the gallery's proven
	# setup — one sun plus flat ambient so the palette textures read true.
	var env_node := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.78, 0.78, 0.82)
	env_node.environment = e
	_vp.add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	_vp.add_child(sun)

	# Ortho three-quarter portrait camera: slight side angle and a touch of down-look give
	# the silhouette depth; ortho keeps all 65 the same size on the card.
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = 9.0
	_cam.position = Vector3(1.1, 2.3, 9.0)
	_vp.add_child(_cam)
	_cam.look_at(Vector3(0.0, 1.7, 0.0))

	_run()


func _run() -> void:
	var ids: Array = []
	for sp in GameData.species:
		ids.append(sp["id"])
	ids.sort()

	var done := 0
	for id in ids:
		var rig = Rig.new()
		_vp.add_child(rig)
		if not rig.build(str(id), 4.0):
			print("PORTRAIT FAIL (no rig): ", id)
			rig.queue_free()
			continue
		rig.set_state("idle", Vector2(0.35, 1.0))
		# Advance the idle clip to the pose beat, then let two frames render.
		var player: AnimationPlayer = rig.get("_player")
		if player != null and player.current_animation != "":
			player.seek(POSE_TIME, true)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://assets/creatures/%s.png" % id)
		var err := img.save_png(path)
		if err != OK:
			print("PORTRAIT FAIL (save ", err, "): ", id)
		else:
			done += 1
		rig.queue_free()
		await get_tree().process_frame

	print("PORTRAITS DONE: %d/%d" % [done, ids.size()])
