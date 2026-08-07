## Same procedural animator, driving the ARENA'S ACTUAL SPRITES — the case that was broken by
## billboarding. Three creatures, three states held side by side so the poses can be compared.
extends Node3D

const CreatureAnim = preload("res://scripts/ui/creature_anim.gd")
const UNIT_HEIGHT := 1.8
const SHOW := [
	{"id": "kongrath", "state": "advance", "x": -3.0},
	{"id": "crocmaw",  "state": "attack",  "x":  0.0},
	{"id": "larkessa", "state": "stunned", "x":  3.0},
]

var _anims: Array = []

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.12, 0.15)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.57, 0.64)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(30, 30)
	ground.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.74, 0.72, 0.67)
	ground.material_override = gm
	add_child(ground)

	for cfg in SHOW:
		var holder := Node3D.new()
		holder.position = Vector3(cfg["x"], 0, 0)
		add_child(holder)

		# ⚠️ Built exactly as arena_3d.gd:_build_units does — BILLBOARD_FIXED_Y and all. That flag
		# is the whole point of this test: it is what silently ate every rotation.
		var spr := Sprite3D.new()
		var tex: Texture2D = Art.creature_texture(str(cfg["id"]))
		if tex != null:
			spr.texture = tex
			spr.pixel_size = UNIT_HEIGHT / float(tex.get_height())
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		spr.shaded = false
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		spr.position = Vector3(0, UNIT_HEIGHT * 0.5, 0)
		holder.add_child(spr)

		var anim = CreatureAnim.new()
		holder.add_child(anim)
		anim.setup(spr)                       # takes billboarding off so rotation applies
		anim.set_state(str(cfg["state"]), Vector2(0, -1))
		_anims.append({"a": anim, "s": str(cfg["state"])})

		var tag := Label3D.new()
		tag.text = "%s\n%s" % [str(cfg["id"]), str(cfg["state"]).to_upper()]
		tag.font_size = 40; tag.outline_size = 12
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.pixel_size = 0.0035
		tag.position = Vector3(cfg["x"], 2.6, 0)
		tag.modulate = Color(0.85, 0.72, 0.35)
		add_child(tag)

	var cam := Camera3D.new()
	cam.fov = 26.0
	var theta := deg_to_rad(38.0)
	var r := 5.5 / tan(deg_to_rad(13.0))
	cam.position = Vector3(0, r * sin(theta), r * cos(theta))
	add_child(cam)
	cam.look_at(Vector3(0, 0.9, 0), Vector3.UP)
	cam.current = true


func _process(_d: float) -> void:
	# hold the attack pose so it can actually be photographed — it is a 0.26s transient
	for e in _anims:
		if e["s"] == "attack":
			(e["a"] as Node)._attack_t = 0.06
