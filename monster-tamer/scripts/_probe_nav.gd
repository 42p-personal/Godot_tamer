## IS THE NAVMESH DOING ANYTHING, AND WOULD A BETTER ONE SPREAD THE FIGHT OUT?
## ⚠️ A navmesh constrains where units CAN go; it never decides where they DO go. So the honest
## test is not "is the mesh good" but "does pathing ever route a unit somewhere a straight line
## would not have taken it". If every path is straight, the mesh is inert and improving it cannot
## widen the fight by a single unit.
##
## ⚠️ Bakes its OWN map with the sim's exact parameters rather than borrowing the sim's — `run()`
## frees its navigation RIDs when it finishes, so querying afterwards silently hits a dead map.
extends Node
const Sp = preload("res://scripts/spatial.gd")
const OBSTACLE_HEIGHT := 2.5

var _map: RID
var _region: RID

func _ready() -> void:
	var Layout = load("res://scripts/arena_layout.gd")
	var rng := RandomNumberGenerator.new(); rng.seed = 20260804
	var lay: Dictionary = Layout.generate(5, "Platinum", rng)
	var obs: Array = lay.get("obstacles", [])
	var g: Vector2 = Sp.ground_size(5)
	var blocking := 0
	for o in obs:
		if str(o.get("grade","soft")) == Sp.COVER_BLOCKS_LOS_GRADE: blocking += 1

	var t0 := Time.get_ticks_msec()
	_bake(g, obs)
	var bake_ms := Time.get_ticks_msec() - t0
	for i in range(12):
		await get_tree().process_frame

	print("ground %.0f x %.0f   obstacles %d (%d LOS-blocking, the only ones that carve the mesh)"
		% [g.x, g.y, obs.size(), blocking])
	print("bake %d ms   cell_size %.2f  ->  %d x %d voxels\n"
		% [bake_ms, 0.25, int(g.x / 0.25), int(g.y / 0.25)])

	var straight := 0; var routed := 0; var failed := 0
	var detour_sum := 0.0; var worst := 1.0; var n := 0
	for i in range(14):
		for j in range(10):
			var a := Vector2(g.x * 0.06, g.y * (0.08 + 0.84 * float(j) / 9.0))
			var b := Vector2(g.x * 0.94, g.y * (0.08 + 0.84 * float(i) / 13.0))
			var p3: PackedVector3Array = NavigationServer3D.map_get_path(
				_map, Vector3(a.x, 0, a.y), Vector3(b.x, 0, b.y), true)
			n += 1
			if p3.size() < 2:
				failed += 1; continue
			var plen := 0.0
			for k in range(1, p3.size()):
				plen += Vector2(p3[k-1].x, p3[k-1].z).distance_to(Vector2(p3[k].x, p3[k].z))
			var ratio: float = plen / maxf(0.001, a.distance_to(b))
			detour_sum += ratio; worst = maxf(worst, ratio)
			if p3.size() <= 2 and ratio < 1.01: straight += 1
			else: routed += 1
	print("PATH QUERIES (%d journeys spanning the full board)" % n)
	print("   straight line (mesh inert) : %-4d (%.0f%%)" % [straight, 100.0*straight/n])
	print("   ROUTED around something    : %-4d (%.0f%%)" % [routed, 100.0*routed/n])
	print("   failed / empty             : %d" % failed)
	print("   mean detour %.4fx   worst %.3fx" % [detour_sum/maxf(1,n), worst])
	NavigationServer3D.free_rid(_region); NavigationServer3D.free_rid(_map)
	get_tree().quit()

func _bake(g: Vector2, obstacles: Array) -> void:
	var geo := NavigationMeshSourceGeometryData3D.new()
	geo.add_faces(PackedVector3Array([
		Vector3(0,0,0), Vector3(g.x,0,0), Vector3(g.x,0,g.y),
		Vector3(0,0,0), Vector3(g.x,0,g.y), Vector3(0,0,g.y)]), Transform3D.IDENTITY)
	for o in obstacles:
		if str(o.get("grade","soft")) != Sp.COVER_BLOCKS_LOS_GRADE: continue
		var r: Rect2 = o["rect"]
		geo.add_faces(_box(r.position.x + r.size.x*0.5, r.position.y + r.size.y*0.5,
			r.size.x*0.5, r.size.y*0.5, 0.0, OBSTACLE_HEIGHT), Transform3D.IDENTITY)
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25; nm.cell_height = 0.1
	nm.agent_height = 2.0; nm.agent_radius = Sp.BODY_RADIUS
	nm.agent_max_climb = 0.3; nm.agent_max_slope = 45.0; nm.region_min_size = 2.0
	NavigationMeshGenerator.bake_from_source_geometry_data(nm, geo)
	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_up(_map, Vector3.UP)
	NavigationServer3D.map_set_cell_size(_map, nm.cell_size)
	NavigationServer3D.map_set_cell_height(_map, nm.cell_height)
	NavigationServer3D.map_set_active(_map, true)
	_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(_region, _map)
	NavigationServer3D.region_set_transform(_region, Transform3D.IDENTITY)
	NavigationServer3D.region_set_navigation_mesh(_region, nm)

func _box(cx: float, cz: float, hx: float, hz: float, y0: float, y1: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var c := [Vector2(cx-hx, cz-hz), Vector2(cx+hx, cz-hz), Vector2(cx+hx, cz+hz), Vector2(cx-hx, cz+hz)]
	for i in range(4):
		var a: Vector2 = c[i]; var b: Vector2 = c[(i+1)%4]
		out.append_array(PackedVector3Array([Vector3(a.x,y0,a.y), Vector3(b.x,y0,b.y), Vector3(b.x,y1,b.y),
			Vector3(a.x,y0,a.y), Vector3(b.x,y1,b.y), Vector3(a.x,y1,a.y)]))
	out.append_array(PackedVector3Array([
		Vector3(c[0].x,y1,c[0].y), Vector3(c[1].x,y1,c[1].y), Vector3(c[2].x,y1,c[2].y),
		Vector3(c[0].x,y1,c[0].y), Vector3(c[2].x,y1,c[2].y), Vector3(c[3].x,y1,c[3].y)]))
	return out
