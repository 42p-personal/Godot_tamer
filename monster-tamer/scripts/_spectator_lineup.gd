## Lineup: the 7 bundle characters side by side, to SEE their poses.
extends Node3D
func _ready() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 4, 16)
	add_child(cam)
	cam.look_at(Vector3(0, 1.5, 0))
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.16, 0.2)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	add_child(sun)
	var names := ["cowboy", "cowgirl", "female_fighter", "warrior_a", "warrior_b", "male_fighter", "warrior_c"]
	for i in range(names.size()):
		var sc: PackedScene = load("res://assets/models/spectators/" + names[i] + ".glb")
		if sc == null:
			continue
		var inst := sc.instantiate()
		var h := Node3D.new()
		h.position = Vector3(float(i - 3) * 3.2, 0, 0)
		h.add_child(inst)
		add_child(h)
		# normalise rough scale: aabb of first mesh
		var mesh := _find_mesh(inst)
		if mesh != null:
			var aabb := mesh.get_aabb()
			if aabb.size.y > 0.01:
				h.scale = Vector3.ONE * (2.6 / aabb.size.y)
func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D: return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null: return r
	return null
