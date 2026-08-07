extends Node3D
func _ready() -> void:
	var V = load("res://scripts/ui/vfx.gd")
	var v = V.new()
	add_child(v)
	await get_tree().process_frame
	v.lightning(Vector3(0,3,0), Vector3(30,3,20))
	v.siphon_beam(Vector3(0,3,0), Vector3(-25,3,10))
	v.static_ring(Vector3(10,0,10), 6.0)
	v.doom_tether(Vector3(0,3,0), Vector3(20,3,-15))
	v.shockwave(Vector3(-10,0,0), 8.0)
	v.dome(Vector3(5,0,5))
	await get_tree().process_frame
	await get_tree().process_frame
	# shader compiled + node exists?
	var found := 0
	for c in v.get_children():
		if c is Node3D and c.get_child_count() == 2:
			found += 1
	var rings := 0
	for c in v.get_children():
		if c is MeshInstance3D and c.mesh is PlaneMesh and (c.mesh as PlaneMesh).size.x > 10.0:
			rings += 1
	var domes := 0
	for c in v.get_children():
		if c is MeshInstance3D and c.mesh is SphereMesh:
			domes += 1
	print("beam holders: %d (want >=3) | ground quads: %d (want >=2) | domes: %d (want 1)  %s" % [
		found, rings, domes, "OK" if found >= 3 and rings >= 2 and domes >= 1 else "*** FAIL"])
	get_tree().quit()
