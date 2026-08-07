## VFX INSPECTION STAGE — fixed camera, dark ground plane, fires the full effect roster on a
## loop so each can be examined frame by frame. Dev tool, not a game scene.
extends Node3D
var vfx = null
var t := 0.0
var step := -1

func _ready() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 10, 26)
	add_child(cam)
	cam.look_at(Vector3(0, 3, 0))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.13, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.environment = e
	add_child(env)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(80, 80)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.34, 0.36)
	pm.material = gm
	ground.mesh = pm
	add_child(ground)
	var VfxScript = load("res://scripts/ui/vfx.gd")
	vfx = VfxScript.new()
	add_child(vfx)

func _process(delta: float) -> void:
	t += delta
	# STAGGER-FIRE: every 0.15s at rotating stations, so every life stage of every suspect is
	# on screen at once — any screenshot catches birth, mid-life and death frames together.
	if t < 0.15:
		return
	t = 0.0
	step = (step + 1) % 5
	var x := float(step - 2) * 8.0
	vfx.flip(Vector3(x, 3, -4), "big_hit", 5.0, Color(0.95, 0.68, 0.25))
	vfx.flip(Vector3(x, 3, 4), "explosion", 5.0, Color.WHITE)
