## PROCEDURAL ANIMATION PROTOTYPE — does state-driven transform animation read at arena distance?
## Cycles one Meshy model (biped, rigged-capable) and one avian (rig REFUSED) through every state.
extends Node3D

const CreatureAnim = preload("res://scripts/ui/creature_anim.gd")
const SEQ := ["idle", "advance", "attack", "retreat", "cast", "stunned", "dead"]
const HOLD := 1.6

var _anims: Array = []
var _label: Label3D
var _t := 0.0
var _i := 0


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.13, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.48, 0.50, 0.58)
	e.ambient_light_energy = 0.8
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-56, -38, 0)
	sun.light_energy = 1.6
	add_child(sun)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(30, 30)
	ground.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.70, 0.68, 0.63)
	ground.material_override = gm
	add_child(ground)

	var models := [
		{"p": "res://assets/models/kongrath.glb", "x": -1.3, "tag": "kongrath (auto-rig OK)"},
		{"p": "res://assets/models/larkessa.glb", "x": 1.3,  "tag": "larkessa (auto-rig REFUSED)"},
	]
	for m in models:
		var packed = load(m["p"])
		if packed == null:
			continue
		var holder := Node3D.new()
		holder.position = Vector3(m["x"], 0, 0)
		add_child(holder)
		var vis = packed.instantiate()
		holder.add_child(vis)
		var anim = CreatureAnim.new()
		holder.add_child(anim)
		anim.setup(vis)
		_anims.append(anim)
		var tag := Label3D.new()
		tag.text = str(m["tag"])
		tag.font_size = 34; tag.outline_size = 10
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.pixel_size = 0.0035
		tag.position = Vector3(m["x"], 2.3, 0)
		add_child(tag)

	_label = Label3D.new()
	_label.font_size = 64; _label.outline_size = 18
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.pixel_size = 0.004
	_label.position = Vector3(0, 3.1, 0)
	_label.modulate = Color(0.85, 0.72, 0.35)
	add_child(_label)

	# ⚠️ The arena camera exactly: 38 degrees, 26 fov long lens.
	var cam := Camera3D.new()
	cam.fov = 26.0
	var theta := deg_to_rad(38.0)
	var r := 4.2 / tan(deg_to_rad(13.0))
	cam.position = Vector3(0, r * sin(theta), r * cos(theta))
	add_child(cam)                       # in-tree BEFORE look_at, or it silently keeps default rot
	cam.look_at(Vector3(0, 0.9, 0), Vector3.UP)
	cam.current = true
	_apply(0)


func _apply(i: int) -> void:
	var st: String = SEQ[i % SEQ.size()]
	_label.text = st.to_upper()
	for a in _anims:
		a.set_state(st, Vector2(0, -1))
	# a flinch on the swing, so the pair reads as an exchange rather than a solo
	if st == "attack":
		for a in _anims:
			a.flinch()


func _process(delta: float) -> void:
	_t += delta
	if _t >= HOLD:
		_t = 0.0
		_i += 1
		_apply(_i)
