## THE DETERMINISM SPIKE — does NavigationServer3D.map_get_path() reproduce byte-identically
## across separate process invocations, for a baked static navmesh?
##
## Owner: engine-programmer. Touches nothing outside this file and docs/SPIKE_DETERMINISM.md
## per the task's ownership rule — this repo has ~15 concurrent agents.
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path "G:/p42.uk/Monster-Tamer/monster-tamer" \
##        --script res://scripts/_spike_determinism.gd
##
## WHAT THIS MEASURES (see docs/AUTOBATTLER_DESIGN.md §11 and docs/SPIKE_DETERMINISM.md):
##   1. Bake a NavigationMesh over a fixed 160x88 arena with 20 fixed box obstacles (no RNG).
##   2. Run 200 map_get_path() queries over 20 fixed start/end pairs (10 repeats each).
##   3. Hash the full float output of every path (SHA-256 over the raw Vector3 bytes, not text —
##      text formatting can round; the byte hash cannot).
##   4. Report that hash on stdout as `FRAME_HASH: <hex>` so a shell driver can diff it across
##      THREE SEPARATE PROCESS invocations. In-process repetition is checked too (as a sanity
##      floor) but is explicitly NOT the determinism test — cross-process is.
##   5. Also checks: does query ORDER affect the result (forward vs. reversed pass, per-pair
##      byte comparison)? Does baking the SAME geometry TWICE (independently, no shared state)
##      produce identical navmesh vertex/polygon data, and identical path output from a map
##      built on the second bake?
##
## DETERMINISM DISCIPLINE HONOURED (docs/SPATIAL_HANDOFF.md §1):
##   - no randf()/RNG of any kind — every position below is a literal.
##   - no RigidBody3D/CharacterBody3D/NavigationAgent3D/PhysicsDirectSpaceState — this spike
##     only touches NavigationServer3D's REGION + map_get_path surface, never the avoidance/
##     agent API (agent_create, obstacle_create, agent_set_velocity). That distinction is the
##     whole point: AUTOBATTLER_DESIGN.md §11 corrects an earlier over-broad worry — the risk
##     named there is Godot's THREADED AVOIDANCE, not static path queries, and this spike is
##     built to isolate exactly the surface we would actually use.
##   - fixed frame count to let NavigationServer3D sync the map before querying (see
##     SYNC_FRAMES below) — not a "wait until it looks synced" loop, so the wait itself doesn't
##     introduce a variable it doesn't need to.
extends SceneTree

# ═══════════════════════════════════════════════════════════════════════════════════════════════
# THE FIXED ARENA — no RNG. 160x88 matches Spatial.ground_size(5) (docs/ARENA_BLUEPRINT.md).
# ═══════════════════════════════════════════════════════════════════════════════════════════════

const GROUND_W := 160.0
const GROUND_H := 88.0
const OBSTACLE_HEIGHT := 4.0   # taller than agent_max_climb, so recast carves it out as a real block

## 20 fixed box obstacles: [center_x, center_z, half_x, half_z]. Three of them (45,44) / (75,44) /
## (105,44) sit astride the z=44 midline specifically so the long east-west queries below MUST
## detour, not just skim past cover.
const OBSTACLES := [
	[20.0, 20.0, 3.0, 3.0], [40.0, 15.0, 2.5, 4.0], [60.0, 30.0, 4.0, 2.0],
	[80.0, 44.0, 3.0, 3.0], [100.0, 60.0, 2.0, 5.0], [120.0, 70.0, 3.5, 3.5],
	[30.0, 60.0, 3.0, 2.0], [50.0, 75.0, 2.5, 2.5], [70.0, 10.0, 3.0, 3.0],
	[90.0, 20.0, 2.0, 2.0], [110.0, 40.0, 4.0, 2.5], [130.0, 20.0, 3.0, 3.0],
	[140.0, 60.0, 2.5, 3.0], [10.0, 44.0, 2.0, 2.0], [150.0, 44.0, 2.0, 2.0],
	[75.0, 44.0, 5.0, 1.5], [45.0, 44.0, 1.5, 5.0], [105.0, 44.0, 1.5, 5.0],
	[25.0, 75.0, 2.0, 2.0], [135.0, 10.0, 2.0, 2.0],
]

## 20 fixed (start, end) pairs. Long east/west crossings that must round the z=44 wall cluster,
## both diagonals corner-to-corner, several straight north/south sweeps through obstacle bands,
## two very short local hops next to a single obstacle, and one degenerate same-point query.
const QUERY_PAIRS := [
	[Vector3(5.0, 0.0, 44.0), Vector3(155.0, 0.0, 44.0)],
	[Vector3(5.0, 0.0, 10.0), Vector3(155.0, 0.0, 80.0)],
	[Vector3(5.0, 0.0, 80.0), Vector3(155.0, 0.0, 10.0)],
	[Vector3(15.0, 0.0, 44.0), Vector3(35.0, 0.0, 44.0)],
	[Vector3(60.0, 0.0, 5.0), Vector3(60.0, 0.0, 83.0)],
	[Vector3(80.0, 0.0, 5.0), Vector3(80.0, 0.0, 83.0)],
	[Vector3(100.0, 0.0, 5.0), Vector3(100.0, 0.0, 83.0)],
	[Vector3(5.0, 0.0, 5.0), Vector3(155.0, 0.0, 83.0)],
	[Vector3(155.0, 0.0, 5.0), Vector3(5.0, 0.0, 83.0)],
	[Vector3(20.0, 0.0, 20.0), Vector3(140.0, 0.0, 70.0)],
	[Vector3(140.0, 0.0, 20.0), Vector3(20.0, 0.0, 70.0)],
	[Vector3(2.0, 0.0, 44.0), Vector3(18.0, 0.0, 44.0)],
	[Vector3(148.0, 0.0, 44.0), Vector3(158.0, 0.0, 44.0)],
	[Vector3(60.0, 0.0, 25.0), Vector3(60.0, 0.0, 35.0)],
	[Vector3(35.0, 0.0, 44.0), Vector3(115.0, 0.0, 44.0)],
	[Vector3(10.0, 0.0, 10.0), Vector3(10.0, 0.0, 80.0)],
	[Vector3(150.0, 0.0, 10.0), Vector3(150.0, 0.0, 80.0)],
	[Vector3(80.0, 0.0, 44.0), Vector3(80.0, 0.0, 44.0)],   # degenerate: start == end
	[Vector3(5.0, 0.0, 44.0), Vector3(5.0, 0.0, 60.0)],
	[Vector3(90.0, 0.0, 15.0), Vector3(130.0, 0.0, 25.0)],
]

const REPEATS := 10                 # 20 pairs * 10 = 200 queries, per the brief
const SYNC_FRAMES := 40             # fixed wait for NavigationServer3D to sync both maps

var _map_a: RID
var _region_a: RID
var _map_b: RID
var _region_b: RID
var _frame_count := 0
var _done := false


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# GEOMETRY — built directly as triangle soup (add_faces), never from a scene-tree MeshInstance3D.
# This sidesteps rendering/physics-server geometry parsing entirely; the only thing under test is
# NavigationMeshGenerator + NavigationServer3D itself.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

static func _box_faces(cx: float, cz: float, hx: float, hz: float, y0: float, y1: float) -> PackedVector3Array:
	var x0 := cx - hx
	var x1 := cx + hx
	var z0 := cz - hz
	var z1 := cz + hz
	var corners := [
		Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x0, y0, z1),
		Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1),
	]
	var order := [
		0, 1, 2, 0, 2, 3,       # bottom
		4, 6, 5, 4, 7, 6,       # top
		0, 4, 1, 1, 4, 5,       # four sides
		1, 5, 2, 2, 5, 6,
		2, 6, 3, 3, 6, 7,
		3, 7, 0, 0, 7, 4,
	]
	var out := PackedVector3Array()
	for i in order:
		out.append(corners[i])
	return out


static func _build_geometry() -> NavigationMeshSourceGeometryData3D:
	var geo := NavigationMeshSourceGeometryData3D.new()
	var ground := PackedVector3Array([
		Vector3(0.0, 0.0, 0.0), Vector3(GROUND_W, 0.0, 0.0), Vector3(GROUND_W, 0.0, GROUND_H),
		Vector3(0.0, 0.0, 0.0), Vector3(GROUND_W, 0.0, GROUND_H), Vector3(0.0, 0.0, GROUND_H),
	])
	geo.add_faces(ground, Transform3D.IDENTITY)
	for o in OBSTACLES:
		var cx: float = o[0]
		var cz: float = o[1]
		var hx: float = o[2]
		var hz: float = o[3]
		geo.add_faces(_box_faces(cx, cz, hx, hz, 0.0, OBSTACLE_HEIGHT), Transform3D.IDENTITY)
	return geo


static func _bake_navmesh() -> NavigationMesh:
	var geo := _build_geometry()
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.1
	nm.agent_height = 2.0
	nm.agent_radius = 0.9
	nm.agent_max_climb = 0.3
	nm.agent_max_slope = 45.0
	nm.region_min_size = 2.0
	NavigationMeshGenerator.bake_from_source_geometry_data(nm, geo)
	return nm


func _make_map(nm: NavigationMesh) -> Array:
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_up(map, Vector3.UP)
	NavigationServer3D.map_set_cell_size(map, nm.cell_size)
	NavigationServer3D.map_set_cell_height(map, nm.cell_height)
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map)
	NavigationServer3D.region_set_transform(region, Transform3D.IDENTITY)
	NavigationServer3D.region_set_navigation_mesh(region, nm)
	return [map, region]


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# SETUP
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _initialize() -> void:
	print("═══ SPIKE: NavigationServer3D determinism — Godot %s, headless ═══" % Engine.get_version_info()["string"])

	var nm_a := _bake_navmesh()
	var nm_b := _bake_navmesh()   # independent second bake: fresh geometry object, fresh NavigationMesh

	print("bake A: vertices=%d polygons=%d" % [nm_a.get_vertices().size(), nm_a.get_polygon_count()])
	print("bake B: vertices=%d polygons=%d" % [nm_b.get_vertices().size(), nm_b.get_polygon_count()])

	var verts_a: PackedByteArray = nm_a.get_vertices().to_byte_array()
	var verts_b: PackedByteArray = nm_b.get_vertices().to_byte_array()
	print("BAKE_VERTICES_IDENTICAL: ", verts_a == verts_b)

	var polys_a := PackedInt32Array()
	for i in nm_a.get_polygon_count():
		polys_a.append_array(nm_a.get_polygon(i))
	var polys_b := PackedInt32Array()
	for i in nm_b.get_polygon_count():
		polys_b.append_array(nm_b.get_polygon(i))
	print("BAKE_POLYGONS_IDENTICAL: ", polys_a.to_byte_array() == polys_b.to_byte_array())

	var made_a := _make_map(nm_a)
	_map_a = made_a[0]
	_region_a = made_a[1]
	var made_b := _make_map(nm_b)
	_map_b = made_b[0]
	_region_b = made_b[1]


func _process(_delta: float) -> bool:
	_frame_count += 1
	if _done:
		return false
	if _frame_count >= SYNC_FRAMES:
		_done = true
		_run_queries_and_report()
		NavigationServer3D.free_rid(_region_a)
		NavigationServer3D.free_rid(_region_b)
		NavigationServer3D.free_rid(_map_a)
		NavigationServer3D.free_rid(_map_b)
		quit(0)
	return false


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# THE QUERIES
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _query(map: RID, start: Vector3, end: Vector3) -> PackedVector3Array:
	return NavigationServer3D.map_get_path(map, start, end, true)


func _run_queries_and_report() -> void:
	var pair_count := QUERY_PAIRS.size()

	# ── forward pass over map A: the canonical 200-query run, hashed as one SHA-256. ──
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var forward_ref := {}          # pair index -> bytes, from rep 0
	var repeat_mismatches: Array = []
	for rep in REPEATS:
		for i in pair_count:
			var pair: Array = QUERY_PAIRS[i]
			var path := _query(_map_a, pair[0], pair[1])
			var b: PackedByteArray = path.to_byte_array()
			ctx.update(b)
			if rep == 0:
				forward_ref[i] = b
			elif forward_ref[i] != b:
				repeat_mismatches.append([i, rep])
	var frame_hash := ctx.finish().hex_encode()

	# ── reversed-order pass over map A: does query ORDER affect the per-pair result? ──
	var reversed_ref := {}
	for rep in REPEATS:
		for j in pair_count:
			var i := pair_count - 1 - j
			var pair: Array = QUERY_PAIRS[i]
			var path := _query(_map_a, pair[0], pair[1])
			if rep == 0:
				reversed_ref[i] = path.to_byte_array()
	var order_mismatches: Array = []
	for i in pair_count:
		if forward_ref[i] != reversed_ref[i]:
			order_mismatches.append(i)

	# ── map B (independently rebaked navmesh): same per-pair queries, compared to map A. ──
	var rebake_mismatches: Array = []
	for i in pair_count:
		var pair: Array = QUERY_PAIRS[i]
		var path := _query(_map_b, pair[0], pair[1])
		var b: PackedByteArray = path.to_byte_array()
		if forward_ref[i] != b:
			rebake_mismatches.append(i)

	print("TOTAL_QUERIES: %d" % (REPEATS * pair_count))
	print("IN_PROCESS_REPEAT_MISMATCHES: %d %s" % [repeat_mismatches.size(), str(repeat_mismatches)])
	print("QUERY_ORDER_MISMATCHES: %d %s" % [order_mismatches.size(), str(order_mismatches)])
	print("REBAKE_MISMATCHES: %d %s" % [rebake_mismatches.size(), str(rebake_mismatches)])
	print("FRAME_HASH: %s" % frame_hash)

	# ── a few sample paths at full float precision, for the human-readable record. ──
	for i in mini(3, pair_count):
		var pair: Array = QUERY_PAIRS[i]
		var path := _query(_map_a, pair[0], pair[1])
		print("SAMPLE_PATH[%d] start=%s end=%s points=%d" % [i, pair[0], pair[1], path.size()])
		for p in path:
			print("    %.10f, %.10f, %.10f" % [p.x, p.y, p.z])
