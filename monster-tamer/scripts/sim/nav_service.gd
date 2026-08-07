## NAV SERVICE — the sim's pathfinding, built on the determinism spike's verdict and its three
## binding lessons (AUTOBATTLER_DESIGN.md §11 RESULT):
##   1. FULLY SERVER-SIDE: procedural add_faces geometry, explicit map/region — the scene-node
##      bake path fails vacuously in headless.
##   2. Readiness is proven by a PROBE QUERY, never by iteration id or frame counts.
##   3. Async iterations OFF, so sync timing can never smuggle in frame-order dependence.
##
## One instance per battle. Geometry is the arena ground plus its obstacle rects — injected,
## like everything deterministic.
extends RefCounted

var _map: RID
var _region: RID
var _ready := false


static func _box_faces(center: Vector3, size: Vector3) -> PackedVector3Array:
	var h := size * 0.5
	var v := [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, -h.y, h.z), center + Vector3(-h.x, -h.y, h.z),
		center + Vector3(-h.x, h.y, -h.z), center + Vector3(h.x, h.y, -h.z),
		center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z),
	]
	var idx := [0,1,2, 0,2,3, 4,6,5, 4,7,6, 0,4,5, 0,5,1, 2,6,7, 2,7,3, 1,5,6, 1,6,2, 0,3,7, 0,7,4]
	var out := PackedVector3Array()
	for i in idx:
		out.append(v[i])
	return out


## ground: Vector2 full size. obstacles: Array of {rect: Rect2} in sim coordinates
## (x, z on the ground plane). agent_radius should be the sim's BODY_RADIUS.
func build(ground: Vector2, obstacles: Array, agent_radius: float) -> void:
	var src := NavigationMeshSourceGeometryData3D.new()
	var hw := ground.x * 0.5
	var hh := ground.y * 0.5
	src.add_faces(PackedVector3Array([
		Vector3(-hw, 0, -hh), Vector3(hw, 0, -hh), Vector3(hw, 0, hh),
		Vector3(-hw, 0, -hh), Vector3(hw, 0, hh), Vector3(-hw, 0, hh),
	]), Transform3D.IDENTITY)
	for ob in obstacles:
		var r: Rect2 = ob["rect"]
		var c := r.get_center()
		src.add_faces(_box_faces(Vector3(c.x, 1.0, c.y), Vector3(r.size.x, 2.0, r.size.y)), Transform3D.IDENTITY)

	var nm := NavigationMesh.new()
	nm.agent_radius = agent_radius
	NavigationServer3D.bake_from_source_geometry_data(nm, src)

	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(_map, true)
	if NavigationServer3D.has_method("map_set_use_async_iterations"):
		NavigationServer3D.map_set_use_async_iterations(_map, false)
	_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(_region, _map)
	NavigationServer3D.region_set_navigation_mesh(_region, nm)


## Readiness, proven by a probe query (lesson 2: never trust counters). Tries the synchronous
## route first (async off + force_update); if the map still serves nothing, the caller must be
## a NODE IN A RUNNING TREE and we wait real physics frames — the only route the spike ever
## proved. ⚠️ A --script SceneTree without a main loop CANNOT make a navmesh sync; hosts must
## run as a scene.
func make_ready_sync(probe_from: Vector2, probe_to: Vector2) -> bool:
	NavigationServer3D.map_force_update(_map)
	if path(probe_from, probe_to).size() > 0:
		_ready = true
	return _ready


func until_ready(tree: SceneTree, probe_from: Vector2, probe_to: Vector2) -> bool:
	if make_ready_sync(probe_from, probe_to):
		return true
	for i in 240:
		await tree.physics_frame
		if path(probe_from, probe_to).size() > 0:
			_ready = true
			return true
	return false


func is_ready() -> bool:
	return _ready


## A path in sim coordinates (Vector2 on the ground plane).
func path(from: Vector2, to: Vector2) -> PackedVector2Array:
	var p3 := NavigationServer3D.map_get_path(_map, Vector3(from.x, 0.2, from.y), Vector3(to.x, 0.2, to.y), true)
	var out := PackedVector2Array()
	for v in p3:
		out.append(Vector2(v.x, v.z))
	return out


func free_rids() -> void:
	NavigationServer3D.free_rid(_region)
	NavigationServer3D.free_rid(_map)
