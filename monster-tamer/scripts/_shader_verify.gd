## Verification harness for spatial_creature_lowpoly.gdshader — kongrath_lowpoly.glb, real arena
## camera (38deg / 26fov, per ART_DIRECTION.md), two identical creatures side by side: LEFT keeps
## the model's own imported material (Meshy's baked shading), RIGHT gets the shader applied.
## Also drives a warm "working lamp" DirectionalLight3D + cool ambient, per the arena's lighting
## doctrine, so the comparison is judged under the same light the battlefield actually uses.
extends Node3D

const MODEL_PATH := "res://assets/models/kongrath_lowpoly.glb"
const SHADER_PATH := "res://assets/shaders/spatial_creature_lowpoly.gdshader"

# ⚠️ A warm working-lamp colour standing in for a league's lamp (Wood-ish amber). arena_3d.gd does
# not yet vary lamp colour per league — this is a stand-in so the shader's lamp-tint behaviour can
# be judged, not a claim that this exact colour is the shipped Wood value.
const LAMP_COLOUR := Color(1.0, 0.82, 0.55)
const LAMP_ENERGY := 2.2
const AMBIENT_COLOUR := Color(0.42, 0.48, 0.58)   # cool sky bounce
const AMBIENT_ENERGY := 0.55

var shader_mat: ShaderMaterial


func _ready() -> void:
	_build_environment()
	_build_floor()

	var left := _spawn(MODEL_PATH, Vector3(-2.6, 0, 0), false)
	var right := _spawn(MODEL_PATH, Vector3(2.6, 0, 0), true)

	var lbl_l := _label("baked (no shader)", Vector3(-2.6, 3.2, 0))
	var lbl_r := _label("spatial_creature_lowpoly.gdshader", Vector3(2.6, 3.2, 0))
	add_child(lbl_l)
	add_child(lbl_r)

	_build_camera()
	print("[_shader_verify] ready — left=baked, right=shaded. Screenshot now.")


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.05, 0.07)   # deep-shadow "past the wall" backdrop
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = AMBIENT_COLOUR
	e.ambient_light_energy = AMBIENT_ENERGY
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_color = LAMP_COLOUR
	sun.light_energy = LAMP_ENERGY
	sun.shadow_enabled = true
	add_child(sun)


func _build_floor() -> void:
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 20)
	floor_mesh.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.28, 0.26, 0.22)
	mat.roughness = 0.95
	floor_mesh.material_override = mat
	add_child(floor_mesh)


func _spawn(path: String, pos: Vector3, apply_shader: bool) -> Node3D:
	var packed = load(path)
	if packed == null:
		push_warning("missing %s" % path)
		return null
	var inst: Node3D = packed.instantiate()
	inst.position = pos
	add_child(inst)

	if apply_shader:
		var shader := load(SHADER_PATH) as Shader
		shader_mat = ShaderMaterial.new()
		shader_mat.shader = shader
		for mi in _find_mesh_instances(inst):
			var src_mat := mi.get_active_material(0)
			var tex: Texture2D = null
			if src_mat is BaseMaterial3D:
				tex = (src_mat as BaseMaterial3D).albedo_texture
			elif src_mat is StandardMaterial3D:
				tex = (src_mat as StandardMaterial3D).albedo_texture
			if tex != null:
				shader_mat.set_shader_parameter("albedo_texture", tex)
			mi.material_override = shader_mat
	return inst


func _find_mesh_instances(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_find_mesh_instances(c))
	return out


func _label(text: String, pos: Vector3) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 34
	lbl.outline_size = 10
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.pixel_size = 0.0035
	lbl.position = pos
	return lbl


## ⚠️ THE ARENA CAMERA, EXACTLY: 38deg elevation, 26fov long lens (ART_DIRECTION.md §Camera).
## Framed on a ~7-unit span so a single creature reads at roughly the real in-arena silhouette
## size, matching `_spike_models.gd`'s already-vetted framing.
func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.fov = 26.0
	var theta := deg_to_rad(38.0)
	var r := 9.0 / tan(deg_to_rad(13.0))
	cam.position = Vector3(0, r * sin(theta), r * cos(theta))
	add_child(cam)
	cam.look_at(Vector3(0, 1.4, 0), Vector3.UP)
	cam.current = true
