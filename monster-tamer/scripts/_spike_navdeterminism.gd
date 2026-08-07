## THE DETERMINISM SPIKE (AUTOBATTLER_DESIGN.md §11) — do this FIRST; it gates the AI build.
##
## Question: does NavigationServer3D.map_get_path() return BYTE-IDENTICAL paths across separate
## processes for a baked static navmesh?
##
## ⚠️ FULLY SERVER-SIDE ON PURPOSE. The scene-node route (NavigationRegion3D +
## bake_navigation_mesh) failed VACUOUSLY in headless three different ways — parse warnings,
## a mesh that baked but never uploaded, a sync that reported done over an empty map — and a
## spike that hashes 400 empty paths "passes" while measuring nothing. Procedural face arrays +
## explicit server calls is also exactly how the deterministic sim would consume this API:
## no engine physics, no scene tree, injected geometry.
extends Node3D

const QUERIES := 400
const SEED := 0x5EED


static func _box_faces(center: Vector3, size: Vector3) -> PackedVector3Array:
	var h := size * 0.5
	var c := center
	var v := [
		c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z),
		c + Vector3(h.x, -h.y, h.z), c + Vector3(-h.x, -h.y, h.z),
		c + Vector3(-h.x, h.y, -h.z), c + Vector3(h.x, h.y, -h.z),
		c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z),
	]
	var idx := [0,1,2, 0,2,3, 4,6,5, 4,7,6, 0,4,5, 0,5,1, 2,6,7, 2,7,3, 1,5,6, 1,6,2, 0,3,7, 0,7,4]
	var out := PackedVector3Array()
	for i in idx:
		out.append(v[i])
	return out


func _ready() -> void:
	# Arena-shaped source geometry, procedural: 50x28 floor + four pillars at the four_pillar
	# layout's stations. add_faces, never meshes — no GPU readback, no parse deferral.
	var src := NavigationMeshSourceGeometryData3D.new()
	var floor_faces := PackedVector3Array([
		Vector3(-25, 0, -14), Vector3(25, 0, -14), Vector3(25, 0, 14),
		Vector3(-25, 0, -14), Vector3(25, 0, 14), Vector3(-25, 0, 14),
	])
	src.add_faces(floor_faces, Transform3D.IDENTITY)
	for p in [Vector3(-12, 1, -6), Vector3(12, 1, -6), Vector3(-12, 1, 6), Vector3(12, 1, 6)]:
		src.add_faces(_box_faces(p, Vector3(3.5, 2.0, 3.5)), Transform3D.IDENTITY)

	var nm := NavigationMesh.new()
	nm.agent_radius = 0.75
	NavigationServer3D.bake_from_source_geometry_data(nm, src)

	var map: RID = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(map, true)
	var region: RID = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map)
	NavigationServer3D.region_set_navigation_mesh(region, nm)

	if NavigationServer3D.has_method("map_set_use_async_iterations"):
		NavigationServer3D.map_set_use_async_iterations(map, false)
	var tries := 0
	while tries < 240:
		if NavigationServer3D.map_get_path(map, Vector3(-20, 0.2, 0), Vector3(20, 0.2, 0), true).size() > 0:
			break
		await get_tree().physics_frame
		tries += 1
	print("sync tries: ", tries)

	var q := NavigationPathQueryParameters3D.new()
	q.map = map
	q.start_position = Vector3(-20, 0.2, 0)
	q.target_position = Vector3(20, 0.2, 0)
	var res := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(q, res)
	print("polys: ", nm.get_polygon_count(),
		" | iteration: ", NavigationServer3D.map_get_iteration_id(map),
		" | closest: ", NavigationServer3D.map_get_closest_point(map, Vector3(3, 0, 2)),
		" | probe(old api): ", NavigationServer3D.map_get_path(map, Vector3(-20, 0.2, 0), Vector3(20, 0.2, 0), true).size(),
		" | probe(query_path): ", res.path.size())

	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var bytes := PackedByteArray()
	var nonempty := 0
	for i in QUERIES:
		var from := Vector3(rng.randf_range(-24, 24), 0, rng.randf_range(-13, 13))
		var to := Vector3(rng.randf_range(-24, 24), 0, rng.randf_range(-13, 13))
		var path: PackedVector3Array = NavigationServer3D.map_get_path(map, from, to, true)
		if path.size() > 0:
			nonempty += 1
		var floats := PackedFloat32Array()
		for v in path:
			floats.append(v.x)
			floats.append(v.y)
			floats.append(v.z)
		bytes.append_array(floats.to_byte_array())
		bytes.append(path.size())

	# ⚠️ Full bit precision, never printed decimals — rounding would hide exactly the
	# differences this spike exists to catch. A vacuous run (all paths empty) FAILS loudly.
	if nonempty == 0:
		print("NAVHASH VACUOUS — every path empty, spike invalid")
	else:
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(bytes)
		print("NAVHASH %s (%d/%d non-empty, %d bytes)" % [ctx.finish().hex_encode(), nonempty, QUERIES, bytes.size()])
	get_tree().quit()
