## THE CROWD — HUMAN spectators on the venue apron (user call 2026-08-06: no monsters watching
## monsters). Six CC0 Quaternius humans, every one carrying a REAL `Sitting` clip — found by
## sweeping Poly Pizza's animated CC0 humans and reading each GLB's clips (the bundle the user
## suggested was static meshes; these are the rigged ones). They SIT, desynced; they bounce and
## cheer on crits and kills. The full sports grammar, purely render-side.
##
## ⚠️ FILL IS A PARAMETER BECAUSE FAME WILL DRIVE IT (standing memory: "stadium seats fill from
## team fame and meta modifiers; NEVER scale the crowd to arena size"). Today it defaults to a
## modest house; when the fame meta lands, the caller passes the real figure. Do not "fix" an
## empty-looking stand by raising the default — wire fame.
##
## ⚠️ THE CROWD IS BATCHED (2026-08-13, round 14). Round 13's A/B measured ~1,050 individually
## instantiated rigged GLBs at 4.6x the whole frame budget (31fps / 2,986 draw calls / 30,111
## nodes at fill 1.0 vs 144fps / 281 / 713 at 0.0 — `docs/WATCH_AUDIT.md`). The fix: each pack's
## Sitting pose is baked ONCE at runtime (`bake_mesh_from_current_skeleton_pose`) and the house
## renders as one MultiMesh per pack — one draw call per pack surface instead of ~2.6 per body.
## Tint moved from per-instance material duplication to MultiMesh instance COLOR; sway and the
## cheer hop moved from AnimationPlayers to `assets/shaders/crowd_sway.gdshader` driven by
## per-instance custom data. Two measured facts shape the build path (probe, 2026-08-13):
##   · the armature carries a x100 scale, so baked verts are ~0.04 local units tall, local +Z up;
##   · a bake in the SAME frame as its seek returns the STALE pose — the skeleton applies the
##     seek next frame — so `_build_batched` awaits two frames between posing and baking.
## The rigged path survives below (`force_legacy`) as the probe's A/B baseline — it is the
## measurement instrument's other arm, not a fallback to ship.
extends Node3D

const PACK_DIR := "res://assets/models/spectators/"
const SPECTATOR_SCALE := 0.75  # ⚠️ user-tuned 2026-08-06: 2.6 towered over the stands; spectators are set dressing, not units
const ROW_SEATS := 22          # seats per row at fill = 1.0 (smaller bodies, denser rows)
const CHEER_CLIPS := ["Clapping", "Jump"]
const SIT_CLIPS := ["Sitting"]
const SWAY_SHADER := "res://assets/shaders/crowd_sway.gdshader"
## Quaternius armatures carry a x100 scale (measured 2026-08-13): world units -> baked-mesh
## local units. Cheer amplitudes are authored in world units and converted with this.
const LOCAL_UNITS_PER_WORLD := 0.01
const SIT_BAKE_PHASE := 0.35   # where in the Sitting loop the pose is baked

## Probe hook (`scripts/_probe_perf.gd`): set BEFORE build() to force the round-13 rigged path
## for the A/B. Never ship true.
static var force_legacy := false

var _spectators: Array = []    # legacy path: {player, idle, cheers: Array[String]}
var _crowd: Array = []         # batched path: {mms: Array[MultiMesh], idx, phase, until}
var _materials: Array = []     # shared ShaderMaterials fed the u_now clock each frame
var _rng := RandomNumberGenerator.new()
var _legacy := false
var _now := 0.0


func build(ground: Vector2, to_world: Callable, fill: float = 0.5) -> void:
	_rng.seed = 20260806   # fixed: the same crowd every fight, until fame varies it
	_legacy = force_legacy
	var packs: Array = ["man_a.glb", "man_b.glb", "woman_dress.glb", "woman_casual.glb",
		"woman_tank.glb", "woman.glb"]
	if packs.is_empty():
		return
	# ⚠️ ALL FOUR SIDES, three stepped rows, density derived from edge length — every step of
	# the apron holds a seat at fill = 1.0 (user: "I want to see all of the seats filled").
	var seats: Array = []
	var seat_spacing := 6.0
	for row in range(5):
		var off := 4.5 + row * 3.5
		# ⚠️ The Sitting clip drops the hips BELOW the model origin, so without this lift they
		# sink INTO the step. Lift = step height + seated-hip offset, tuned by screenshot.
		var lift := 1.6 + row * 1.4
		var nx := maxi(2, int(ground.x * 0.9 / seat_spacing))
		for i in range(nx):
			var x := ground.x * (0.05 + 0.90 * float(i) / float(nx - 1))
			seats.append({"g": Vector2(x, -off), "lift": lift, "face": 0.0})
			seats.append({"g": Vector2(x, ground.y + off), "lift": lift, "face": PI})
		var ny := maxi(2, int(ground.y * 0.8 / seat_spacing))
		for i in range(ny):
			var y := ground.y * (0.10 + 0.80 * float(i) / float(ny - 1))
			seats.append({"g": Vector2(-off, y), "lift": lift, "face": PI * 0.5})
			seats.append({"g": Vector2(ground.x + off, y), "lift": lift, "face": -PI * 0.5})
	# Fill: fame decides HOW MANY seats hold a body; empty seats stay empty (a half-full house
	# must READ half-full — that is the whole point of fame-driven attendance).
	var occupied := int(round(seats.size() * clampf(fill, 0.0, 1.0)))
	# ⚠️ Deterministic Fisher–Yates on the SEEDED rng. This used to be `seats.shuffle()`, which
	# draws from Godot's GLOBAL randomised rng — so "fixed seed = same crowd every fight" was
	# silently untrue: WHO sat WHERE changed every run. Now the whole house is a pure function
	# of the seed, on both paths.
	for i in range(seats.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = seats[i]
		seats[i] = seats[j]
		seats[j] = tmp
	if _legacy:
		for k in range(occupied):
			var seat: Dictionary = seats[k]
			var pack: String = packs[_rng.randi_range(0, packs.size() - 1)]
			_spawn(seat, pack, to_world)
		return
	# ⚠️ ALL rng draws happen HERE, synchronously, in the same per-spectator order the legacy
	# path draws them (pack · yaw jitter · scale · tint h/s/v · phase) — so the two paths seat
	# the SAME crowd from the same seed, and the async bake below cannot perturb determinism
	# however frames land.
	var records: Array = []
	for k in range(occupied):
		records.append({
			"seat": seats[k],
			"pack": _rng.randi_range(0, packs.size() - 1),
			"jit": _rng.randf_range(-0.25, 0.25),
			"scl": _rng.randf_range(0.85, 1.15),
			# Colour variance: six models repeat visibly in a full house — a per-instance tint
			# breaks the clone army. Subtle hue shift, not team colours (the crowd must never
			# read as either side's colour system).
			"tint": Color.from_hsv(_rng.randf(), _rng.randf_range(0.05, 0.30), _rng.randf_range(0.75, 1.0)),
			"phase": _rng.randf(),
		})
	_build_batched(packs, records, to_world)


## Async on purpose: posing a skeleton and baking it CANNOT happen in the same frame (the bake
## reads the pre-seek pose — measured, see header). The crowd appears 2-3 frames after build();
## the arena is still in its opening hold, so nothing observable changes.
func _build_batched(packs: Array, records: Array, to_world: Callable) -> void:
	# One seated temp per pack, parked far below the venue. Visible (not hidden) so animation
	# and skeleton processing definitely run before the bake.
	var temps: Array = []
	for p in packs:
		var t := {"holder": null, "meshes": []}
		var scene: PackedScene = load(PACK_DIR + p)
		if scene != null:
			var inst := scene.instantiate()
			var holder := Node3D.new()
			holder.position = Vector3(0, -500, 0)
			add_child(holder)
			holder.add_child(inst)
			var player := _find_player(inst)
			if player != null:
				for anim_name in player.get_animation_list():
					var short := str(anim_name).get_slice("|", str(anim_name).get_slice_count("|") - 1)
					var is_sit := false
					for sc in SIT_CLIPS:
						if short.ends_with(sc):
							is_sit = true
					if is_sit:
						player.play(anim_name)
						player.seek(SIT_BAKE_PHASE, true)
						break
			var mis: Array = []
			_find_mesh_instances(inst, mis)
			for mi in mis:
				t["meshes"].append({
					"mi": mi,
					# mesh transform relative to the pack ROOT (carries the armature's x100
					# scale + rotation) — folded into every instance transform below.
					"rel": (inst as Node3D).global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform,
				})
			t["holder"] = holder
		temps.append(t)
	# ⚠️ two frames, not one: seek applies to the skeleton the bake reads on the NEXT frame.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	# Bake each pack's seated pose and dress the surfaces in the sway shader.
	var parts_by_pack: Array = []
	for t in temps:
		var parts: Array = []
		for entry in t["meshes"]:
			var mi: MeshInstance3D = entry["mi"]
			var baked: ArrayMesh = null
			if mi.has_method("bake_mesh_from_current_skeleton_pose"):
				baked = mi.bake_mesh_from_current_skeleton_pose()
			if baked == null or baked.get_surface_count() == 0:
				# Unskinned or bake-refused: batch the raw mesh (bind pose). Duplicated so the
				# material dressing below cannot mutate the shared import resource.
				if mi.mesh != null:
					baked = mi.mesh.duplicate()
			if baked == null:
				continue
			for s in range(baked.get_surface_count()):
				baked.surface_set_material(s, _crowd_material(mi.get_active_material(s)))
			parts.append({"mesh": baked, "rel": entry["rel"]})
		parts_by_pack.append(parts)
		if t["holder"] != null:
			(t["holder"] as Node3D).queue_free()
	# One MultiMesh per (pack, mesh part) — the whole house in ~6 instanced draws per surface.
	for p in range(packs.size()):
		var recs: Array = records.filter(func(r): return int(r["pack"]) == p)
		if recs.is_empty() or (parts_by_pack[p] as Array).is_empty():
			continue
		var mms: Array = []
		for part in parts_by_pack[p]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = part["mesh"]
			mm.instance_count = recs.size()
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			add_child(mmi)
			for i in range(recs.size()):
				var r: Dictionary = recs[i]
				var seat: Dictionary = r["seat"]
				var wpos: Vector3 = to_world.call(seat["g"]) + Vector3(0, float(seat["lift"]), 0)
				var basis := Basis(Vector3.UP, float(seat["face"]) + float(r["jit"])) \
					* Basis.from_scale(Vector3.ONE * SPECTATOR_SCALE * float(r["scl"]))
				mm.set_instance_transform(i, Transform3D(basis, wpos) * (part["rel"] as Transform3D))
				mm.set_instance_color(i, r["tint"])
				# custom = (sway phase, cheer_start, cheer_dur, cheer_amp) — dur 0 means idle
				mm.set_instance_custom_data(i, Color(float(r["phase"]), -1000.0, 0.0, 0.0))
			mms.append(mm)
		for i in range(recs.size()):
			_crowd.append({"mms": mms, "idx": i, "phase": float(recs[i]["phase"]), "until": 0.0})
	set_process(true)


## Shared ShaderMaterial per SOURCE material — tint is instance COLOR now, so nothing is
## duplicated per body (the rigged path duplicated up to 6 materials per spectator).
var _mat_cache: Dictionary = {}
func _crowd_material(src: Material) -> ShaderMaterial:
	var key := src.get_instance_id() if src != null else 0
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := ShaderMaterial.new()
	m.shader = load(SWAY_SHADER)
	if src is BaseMaterial3D:
		m.set_shader_parameter("albedo_mul", (src as BaseMaterial3D).albedo_color)
		var tex := (src as BaseMaterial3D).albedo_texture
		if tex != null:
			m.set_shader_parameter("albedo_tex", tex)
	_mat_cache[key] = m
	_materials.append(m)
	return m


## The crowd's shared clock. GDScript writes cheer start times in the same clock the shader
## reads — TIME is unreadable from here, hence a pushed uniform (a few dozen calls a frame).
func _process(delta: float) -> void:
	_now += delta
	for m in _materials:
		(m as ShaderMaterial).set_shader_parameter("u_now", _now)


## The fight's beats reach the stands — and ONLY the beats (user direction: sitting is the
## default; cheering happens on camera shakes and deaths, never ambiently).
## ⚠️ PER-MODEL RANDOM DELAY (0–0.7s) before each cheer starts: a crowd that reacts on the same
## frame reads as an animatronic display, one that RIPPLES reads as people. The roll is also
## per model, so who stands differs every event. On the batched path the delay lives in the
## per-instance cheer_start the shader compares against — no timers.
func react(intensity: float = 0.4) -> void:
	if _legacy:
		for sp in _spectators:
			if _rng.randf() > intensity:
				continue
			if bool(sp.get("cheering", false)):
				continue
			var cheers: Array = sp["cheers"]
			if cheers.is_empty() or sp["player"] == null:
				continue
			sp["cheering"] = true
			var clip: String = cheers[_rng.randi_range(0, cheers.size() - 1)]
			var delay := _rng.randf_range(0.0, 0.7)
			get_tree().create_timer(delay).timeout.connect(_start_cheer.bind(sp, clip))
		return
	for h in _crowd:
		if _rng.randf() > intensity:
			continue
		if _now < float(h["until"]):
			continue
		var delay2 := _rng.randf_range(0.0, 0.7)
		var dur := _rng.randf_range(0.55, 0.95)
		var amp_world := _rng.randf_range(0.30, 0.60)
		var start := _now + delay2
		h["until"] = start + dur
		var cd := Color(float(h["phase"]), start, dur, amp_world * LOCAL_UNITS_PER_WORLD)
		for mm in h["mms"]:
			(mm as MultiMesh).set_instance_custom_data(int(h["idx"]), cd)


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# LEGACY RIGGED PATH — round 13's crowd, kept ONLY as the probe's A/B baseline (force_legacy).
# ~1,050 rigged GLBs measured at 31fps; do not ship it, do not delete it while the probe A/Bs it.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _spawn(seat: Dictionary, pack: String, to_world: Callable) -> void:
	var scene: PackedScene = load(PACK_DIR + pack)
	if scene == null:
		return
	var inst := scene.instantiate()
	var holder := Node3D.new()
	var wpos: Vector3 = to_world.call(seat["g"])
	holder.position = wpos + Vector3(0, float(seat["lift"]), 0)
	holder.rotation.y = float(seat["face"]) + _rng.randf_range(-0.25, 0.25)
	holder.scale = Vector3.ONE * SPECTATOR_SCALE * _rng.randf_range(0.85, 1.15)
	holder.add_child(inst)
	add_child(holder)
	_tint_meshes(inst, Color.from_hsv(_rng.randf(), _rng.randf_range(0.05, 0.30), _rng.randf_range(0.75, 1.0)))
	var player := _find_player(inst)
	if player == null:
		return
	var idle := ""
	var cheers: Array = []
	for anim_name in player.get_animation_list():
		var short := str(anim_name).get_slice("|", str(anim_name).get_slice_count("|") - 1)
		for sc in SIT_CLIPS:
			if short.ends_with(sc) and idle == "":
				idle = anim_name   # the seat IS the idle
		for c in CHEER_CLIPS:
			if short.ends_with(c):
				cheers.append(anim_name)
	if idle != "":
		var a := player.get_animation(idle)
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR
		player.play(idle)
		# Desync: a crowd breathing in perfect unison reads as an army, not an audience.
		player.seek(_rng.randf() * 2.0, true)
	_spectators.append({"player": player, "idle": idle, "cheers": cheers})


func _start_cheer(sp: Dictionary, clip: String) -> void:
	var p: AnimationPlayer = sp["player"]
	if p == null or not is_instance_valid(p):
		return
	p.play(clip)
	if not p.animation_finished.is_connected(_back_to_idle):
		p.animation_finished.connect(_back_to_idle.bind(sp))


func _back_to_idle(_anim: StringName, sp: Dictionary) -> void:
	sp["cheering"] = false
	if sp["idle"] != "" and sp["player"] != null:
		(sp["player"] as AnimationPlayer).play(sp["idle"])


func _tint_meshes(n: Node, tint: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in range(mi.get_surface_override_material_count()):
			var mat := mi.mesh.surface_get_material(i) if mi.get_surface_override_material(i) == null else mi.get_surface_override_material(i)
			if mat is StandardMaterial3D:
				var dup := (mat as StandardMaterial3D).duplicate()
				dup.albedo_color = dup.albedo_color * tint
				mi.set_surface_override_material(i, dup)
	for c in n.get_children():
		_tint_meshes(c, tint)


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_player(c)
		if r != null:
			return r
	return null


func _find_mesh_instances(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_find_mesh_instances(c, out)
