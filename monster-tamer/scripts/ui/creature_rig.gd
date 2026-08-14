## SKELETAL CREATURE ANIMATION — the real thing, for species that have a rigged model.
##
## Presents EXACTLY the interface `creature_anim.gd` presents (`setup`/`set_state`/`flinch`), so
## `arena_3d.gd` drives a rigged creature and a procedurally-posed sprite through the same two
## calls and never branches on which it got. That symmetry is the point: the roster is 65 species
## and models arrive one at a time, so the renderer must not care which kind of unit it is holding.
##
## ⚠️ THE CLIPS ARRIVE AS TEN SEPARATE .glb FILES, EACH CARRYING THE WHOLE RIGGED MESH.
## That is how Meshy's `/v1/animations` endpoint returns them — one file per motion, 24 bones and
## 1,235 triangles repeated in every one. Instantiating ten of those per unit would put ~12,000
## triangles and ten skeletons on screen for one monster. So: instantiate ONE as the body, and
## merge the other nine clips into its `AnimationPlayer` as a library. Nine meshes are loaded at
## import time and discarded here; only their animation tracks survive.
##
## ⚠️ CLIP NAMES ARE READ FROM THE FILE, NEVER ASSUMED FROM THE FILENAME. Every one of the ten
## clips was misnamed on disk on 2026-08-05 — `kongrath_dead.glb` contained a BLOCK animation —
## because a download loop wrote them in the wrong order. `tools/fix_clip_names.py` corrected the
## files, but the lesson stands: this reads `get_animation_list()[0]` and uses whatever is
## actually in there. A future mis-download changes which motion plays; it can never crash.
extends Node3D

const SHADER_PATH := "res://assets/shaders/spatial_creature_lowpoly.gdshader"

## sim `state` -> the FILE that holds the clip for it. The sim emits exactly seven states
## (`spatial_sim.gd:_record_frame`); `hurt` is not one of them — it arrives out-of-band through
## `flinch()`, because the sim reports shots rather than a "being hit" state.
##
## ⚠️ `guard`, `attack_alt` and `victory` are generated and on disk but UNMAPPED. The sim has no
## state for them yet. They are listed here as a comment rather than silently dropped so the next
## person knows the art exists and only the sim hookup is missing:
##   guard      — when the sim emits a blocking state (the Guard effect already exists in combat)
##   attack_alt — a second swing, to break up repetition on long melee exchanges
##   victory    — the winning side, after the last enemy falls
const CLIP_FILE := {
	"idle": "idle",
	"advance": "advance",
	"retreat": "advance",     # ⚠️ walk played backwards would look wrong; a backpedal is its own
	                          # motion we have not generated. Walking while retreating reads as
	                          # "moving", which is true, and is the honest placeholder.
	"attack": "attack",
	"cast": "cast",
	"stunned": "stunned",
	"dead": "dead",
	"hurt": "hurt",
}

## The states that repeat while they persist. Everything else fires once and holds its last pose
## until the sim moves the unit to another state.
const LOOPING := ["idle", "advance", "retreat"]

## How long a flinch owns the body before the sim's own state resumes.
const HURT_TIME := 0.34

## ⚠️ Meshy's models face -Z (Godot's own "forward"), so no offset is needed today. Kept as a
## named constant rather than a bare 0 because the next generator, or a hand-authored model, may
## not agree — and a creature facing the wrong way is the kind of bug that gets blamed on the sim.
const MODEL_YAW_OFFSET_DEG := 0.0

var _player: AnimationPlayer
var _mesh: MeshInstance3D
var _clip_of: Dictionary = {}      ## sim state -> the real animation name inside the player
var _state: String = ""
## ⚠️ SIDESTEP WITHOUT SIDESTEP CLIPS — THE UPPER/LOWER BODY SPLIT. There are no strafe clips in
## the packs and retargeting external ones onto these bespoke skeletons is exactly what produced
## the 16% limb-length morphing earlier in this session. So the legs orient to TRAVEL (the walk
## clip is then honest about where the feet are going) and the torso counter-rotates back toward
## the TARGET. This is the standard trick for strafing without strafe animation.
##
## ⚠️ IT ONLY MAKES SENSE ON A LEGGED RIG, AND MOST OF THE ROSTER IS NOT ONE. Measured: 17 of 45
## pack models have leg bones; the other 28 are blobs, birds and wing-only rigs at 4–13 bones,
## where there are no legs to cross and simply facing the target is already correct. `_has_legs`
## gates the whole thing — do not "fix" it by applying the twist everywhere.
##
## ⚠️ A `SkeletonModifier3D`, NOT a `_process()` write. Bone poses are overwritten by the
## AnimationPlayer every frame, so anything set in `_process` fights the animation and wins only
## by accident of ordering. `_process_modification()` is the sanctioned hook that runs AFTER the
## animation has posed the skeleton. And the twist is applied in SKELETON space about its up axis,
## never about the bone's own local axes — GLTF bone axes vary per exporter and per rig, so
## local-axis maths would work on some packs and quietly corkscrew others.
class TorsoTwist extends SkeletonModifier3D:
	var bone_idx := -1
	var twist := 0.0

	func _process_modification() -> void:
		var sk := get_skeleton()
		if sk == null or bone_idx < 0 or absf(twist) < 0.002:
			return
		var gp: Transform3D = sk.get_bone_global_pose(bone_idx)
		sk.set_bone_global_pose(bone_idx, Transform3D(Basis(Vector3.UP, twist) * gp.basis, gp.origin))


## How far the torso may come back toward the target before the legs have to give up and turn.
const MAX_TWIST_DEG := 55.0
## Bones that count as "the torso", best first. All 45 packs carry one of these.
const SPINE_NAMES := ["torso", "chest", "spine", "abdomen", "body"]
const LEG_NAMES := ["leg", "foot", "thigh", "shin", "knee"]

var _twist_mod: TorsoTwist
var _has_legs := false
var _pack_id := ""   # which pack model this rig built (outlier-scale lookup)
## What this rig actually occupies on screen, in world units, measured from the skinned bounds at
## the scale `_scale_to` chose. ⚠️ READ-ONLY TRUTH FOR INSTRUMENTS (`_probe_watch.gd` measures
## body overlap with it) — the renderer itself derives nothing from these; they exist so the
## probe and the rig can never disagree about how big a creature was drawn.
var drawn_width := 0.0    # widest horizontal extent (max of x/z), world units, after scaling
var drawn_height := 0.0   # vertical extent, world units, after scaling
var _facing: Vector2 = Vector2(1, 0)
var _move_dir: Vector2 = Vector2.ZERO
var _backwards := false
var _hurt_t: float = -1.0
var _species: String = ""
## Per-instance surface materials for the hit flash on pack creatures, and their original colours.
var _flash_mats: Array = []
var _flash_base: Dictionary = {}
var _flash_tween: Tween = null

## Loaded scenes are shared across every unit of the same species — `load()` is cached by Godot,
## but the assembled clip library is not, so this saves re-walking nine files per unit.
static var _lib_cache: Dictionary = {}


## Assembles the body. Returns false when this species has no model, which is the SIGNAL for
## `arena_3d.gd` to fall back to the sprite path — not an error.
func build(species_id: String, target_height: float, max_footprint: float = 0.0) -> bool:
	_species = species_id
	# ⚠️ PACK CREATURES FIRST — one .glb carrying the mesh, the skeleton AND every clip. This is
	# the shape CC0 sources ship (`tools/poly_fetch.py`), and it is strictly better than the
	# one-file-per-clip shape below: hand-authored motion instead of auto-retargeted, correct clip
	# names inside the file, and 0.07-0.98 MB for the whole creature against 8.4 MB PER CLIP.
	if _build_from_pack(species_id, target_height, max_footprint):
		return true

	# ⚠️ The base body is just "a file that carries the mesh and skeleton" — every clip file has
	# both. Preferring `idle` is a convention, not a requirement, and hard-requiring it meant a
	# creature whose clips are still being generated and reviewed one at a time could not be
	# looked at at all until the idle happened to be the one that existed.
	var base_path := ""
	for f in ["idle"] + CLIP_FILE.values():
		var p := _path_for(species_id, f)
		if ResourceLoader.exists(p):
			base_path = p
			break
	if base_path == "":
		return false

	var body: Node3D = (load(base_path) as PackedScene).instantiate() as Node3D
	if body == null:
		return false
	add_child(body)

	_player = _find(body, "AnimationPlayer") as AnimationPlayer
	_mesh = _find(body, "MeshInstance3D") as MeshInstance3D
	if _player == null or _mesh == null:
		body.queue_free()
		return false

	_install_clips(species_id)
	_scale_to(body, target_height, max_footprint)
	_apply_shader()

	# Start somewhere valid — a rig sitting in its bind pose reads as broken, not as idle.
	set_state("idle", _facing)
	return true


const PACK_DIR := "res://assets/models/creatures/"

## ⚠️ SIM STATE -> CLIP NAME, MATCHED AGAINST A SET AND NEVER ONE NAME. The pack spans several
## authoring conventions — `HitReact` vs `HitRecieve` (the source's own typo, kept as shipped),
## `Punch` vs `Attack` vs `Headbutt` vs `Bite_Front`, `Walk` vs `Fast_Flying` for things that do
## not have legs. Matching a single name would silently drop whole creatures into a fallback pose
## and the only symptom would be "that one looks a bit still".
##
## Order within each list is PREFERENCE, first match wins.
const PACK_CLIPS := {
	"idle":    ["idle", "flying_idle"],
	"advance": ["walk", "fast_flying", "run", "swim", "flying"],
	"retreat": ["walk", "fast_flying", "run", "swim", "flying"],
	"attack":  ["attack", "punch", "headbutt", "bite_front", "attack2", "spellcast"],
	# ⚠️ `cast` deliberately prefers the SECOND attack or a spell clip — a caster that plays the
	# same motion as a melee swing tells the player nothing, and legibility is load-bearing in a
	# game you cannot intervene in.
	"cast":    ["spellcast", "attack2", "weapon", "wave", "headbutt", "attack", "punch"],
	"stunned": ["duck", "hitrecieve", "hitreact", "no", "idle"],
	"dead":    ["death", "die"],
	"hurt":    ["hitreact", "hitrecieve", "hit", "damage"],
}


## A single .glb carrying mesh, skeleton and every clip. Returns false when this species has no
## pack model, which is a SIGNAL to try the per-clip path, not an error.
func _build_from_pack(species_id: String, target_height: float, max_footprint: float = 0.0) -> bool:
	# The species may BE a pack id (probes and galleries pass one directly), or it may map to one.
	var pack_id := species_id
	_pack_id = pack_id
	if not ResourceLoader.exists(PACK_DIR + pack_id + ".glb"):
		var art := get_node_or_null("/root/Art")
		if art != null and art.has_method("pack_model_for"):
			pack_id = str(art.pack_model_for(species_id))
			_pack_id = pack_id
	var path := PACK_DIR + pack_id + ".glb"
	if pack_id == "" or not ResourceLoader.exists(path):
		return false
	var body: Node3D = (load(path) as PackedScene).instantiate() as Node3D
	if body == null:
		return false
	add_child(body)
	_player = _find(body, "AnimationPlayer") as AnimationPlayer
	_mesh = _find(body, "MeshInstance3D") as MeshInstance3D
	if _player == null or _mesh == null:
		body.queue_free()
		return false

	# Index what the file actually carries, keyed on the bit after the armature prefix
	# ("CharacterArmature|Walk" -> "walk"). ⚠️ Read from the file, never assumed from a list we
	# wrote down — the same discipline that caught ten mislabelled clips.
	var by_name := {}
	for full in _player.get_animation_list():
		by_name[full.get_slice("|", full.get_slice_count("|") - 1).to_lower()] = full

	for state in PACK_CLIPS.keys():
		for want in PACK_CLIPS[state]:
			if by_name.has(want):
				_clip_of[state] = by_name[want]
				break
			# Some packs prefix the clip inside the last segment too ("Spider_Idle" -> "spider_idle"),
			# so an exact miss falls back to a suffix match. Suffix, not substring: "walk" must not
			# claim "moonwalk_dance" but must claim "spider_walk".
			var found := false
			for key in by_name.keys():
				if str(key).ends_with("_" + want):
					_clip_of[state] = by_name[key]
					found = true
					break
			if found:
				break

	if not _clip_of.has("idle"):
		# Nothing to stand still with means nothing worth showing.
		body.queue_free()
		_player = null
		_mesh = null
		_clip_of.clear()
		return false

	# ⚠️ Loop the locomotion states and one-shot the rest, same rule as the per-clip path — but
	# applied to the SHARED Animation resources this file owns, so duplicate first. Editing them
	# in place would change the clip for every other unit of the same species on the field.
	for state in _clip_of.keys():
		var a: Animation = _player.get_animation(_clip_of[state]).duplicate()
		a.loop_mode = Animation.LOOP_LINEAR if LOOPING.has(state) else Animation.LOOP_NONE
		if LOOPING.has(state):
			a = _strip_root_travel(a)
		var lib_name: String = "mt_" + str(state)
		if not _player.has_animation_library("mt"):
			_player.add_animation_library("mt", AnimationLibrary.new())
		_player.get_animation_library("mt").add_animation(lib_name, a)
		_clip_of[state] = "mt/" + lib_name

	_scale_to(body, target_height, max_footprint)
	_apply_species_tint(body, species_id)
	# Species colour identity on SHARED bodies (Art.SPECIES_TINT — authored, never random).
	# ⚠️ NO SHADER AND NO SIDECAR TEXTURE HERE. These models ship their own material and a palette
	# atlas that is already flat and unlit-looking — the exact thing the shader existed to fake on
	# Meshy output with baked lighting in it. Forcing the shader on would replace a good texture
	# with an unbound sampler, which is how the salmon creature happened.
	set_state("idle", _facing)
	return true


## ⚠️ SCALED FROM THE MESH'S OWN AABB, never from a hand-tuned per-species number. The sprite path
## divides `UNIT_HEIGHT` by the texture height for exactly this reason; a model whose author
## happened to work in a different unit would otherwise arrive as a giant or an ant, and the fix
## would be a magic number nobody could derive later.
##
## ⚠️ THE AABB MUST BE TAKEN IN THE BODY'S SPACE, NOT THE MESH'S. `MeshInstance3D.get_aabb()`
## returns the mesh's LOCAL bounds, and Godot's glTF importer parks its own scale on the nodes
## between the scene root and the mesh — 0.01 for these files. Scaling by the local AABB therefore
## produced a creature **exactly 100x too small** (0.026 units against a 2.6 target), and it was
## the probe's measured height, not any amount of reading, that caught it. Composing the relative
## transform makes the calculation independent of whatever the exporter chose.
##
## ⚠️ AND THE SCALE GOES ON `self`, NEVER ON THE IMPORTED BODY. Meshy's clips animate the
## imported root's own transform, so an `AnimationPlayer` playing ANY of them overwrites a scale
## written onto that node — the creature was correctly sized right up until the first frame of
## animation, then collapsed back to the exporter's 0.01 and vanished. That is why the first probe
## passed on height and the screenshot still showed nothing: the measurement was taken before
## playback started. `self` sits above everything the clips touch, so nothing can reach it.
## `max_footprint` (world units, 0 = uncapped): the widest horizontal extent this body may be
## DRAWN at. ⚠️ THE CAP IS THE SIM'S BODY DISC ARRIVING IN THE RENDERER, NOT A TASTE NUMBER.
## Round 13 measured the scrum as a pile of interpenetrating bodies and proved no camera, plate
## or colour work could separate them, because the sim separates centres by
## `2 * Sp.BODY_RADIUS * WORLD_SCALE` = 1.50 world units while bodies were drawn 2.2-2.6 wide —
## ~40% overlap AT REST, by construction. The renderer must not draw a body meaningfully wider
## than the disc the sim actually keeps clear for it, or the fight reads as a single blob in
## exactly the ten seconds that decide the match (`docs/WATCH_AUDIT.md` §0). The cap value is
## derived in `arena_3d.gd` (`UNIT_FOOTPRINT_MAX`) from the sim's own constants, so if the sim's
## body radius ever moves, the drawn bodies re-expand to match without anyone editing this file.
func _scale_to(_body: Node3D, target_height: float, max_footprint: float = 0.0) -> void:
	scale = Vector3.ONE
	position.y = 0.0
	var aabb: AABB = _skinned_bounds()
	# ⚠️ NORMALISING BY HEIGHT ALONE IS WRONG FOR A ROSTER OF 45 DIFFERENT SHAPES. A bipedal ape
	# and a flat, wide fish can be the same HEIGHT and occupy wildly different amounts of screen —
	# `glub_evolved` fitted to 4.4 units tall came out roughly fifteen units long and swallowed the
	# frame while the plates said it was one unit among ten.
	#
	# What actually needs normalising is SCREEN PRESENCE, so the widest horizontal dimension is
	# weighed in too. The 0.8 weight keeps genuinely tall creatures tall — a pure max() would
	# squash every biped to match its own shoulder width — while stopping a long body from
	# dominating. ⚠️ Do NOT replace this with a per-species scale table: 45 hand-tuned numbers
	# that nobody can re-derive is exactly the kind of value `CLAUDE.md` warns became load-bearing
	# without ever being decided.
	var widest: float = maxf(aabb.size.x, aabb.size.z)
	var extent: float = maxf(aabb.size.y, widest * 0.8)
	if extent <= 0.0001:
		return
	var s: float = target_height / extent
	# BIND-POSE BOUNDS UNDER-MEASURE MODELS WHOSE IDLE SPREADS THEM. Squidle's tentacles and
	# ghost's arms are CURLED at bind, so the bounds are honest about the bind pose and wrong
	# about the creature on screen - the gallery showed them 3-4x their neighbours. Sampling
	# every clip's every frame for true extents is the "correct" fix and wildly over-engineered;
	# this table corrects the observed outliers, eye-tuned against the species gallery.
	# Keep this SHORT - an exception list for models whose bind pose lies, never a per-species
	# tuning table (that warning stands).
	var fix := {"squidle": 0.5, "ghost": 0.55, "ghost_skull": 0.55}
	s *= float(fix.get(_pack_id, 1.0))
	# The footprint cap (see header). Uniform, never a squash: a non-uniform scale would keep the
	# height by distorting every proportion the modeller chose, and a stocky creature slimmed 35%
	# stops reading as its species. A capped creature is instead honestly SMALLER — the same trade
	# the sim already makes by giving every unit one body disc. Applied after the outlier fix so
	# the two corrections compose instead of fighting.
	if max_footprint > 0.0 and widest * s > max_footprint:
		s = max_footprint / widest
	scale = Vector3(s, s, s)
	drawn_width = widest * s
	drawn_height = aabb.size.y * s
	# Sit the feet on the ground plane: the bottom of those same bounds, scaled, is the offset —
	# PLUS a small safety margin, because these are BIND-POSE bounds and the walk/attack cycles
	# dip below them (the user watched toes sink through the floor). 4% of height is invisible
	# as levitation and covers every clip's dip.
	position.y = -aabb.position.y * s + target_height * 0.04


## ⚠️ `MeshInstance3D.get_aabb()` IS THE WRONG NUMBER FOR A SKINNED MESH, AND IT IS WRONG BY A
## LOT — 0.017 against a real rendered 1.77, a factor of 104. It reports the mesh's BIND-POSE
## bounds in mesh space, but a skinned vertex is placed by `bone_pose * bind_pose`, and these
## models carry a bind matrix that rescales mesh space into the skeleton's own (centimetre) units.
## Scaling by `get_aabb()` therefore produced a creature ~150x too large — it filled the frame as
## a featureless white wall, which reads as a broken shader or a missing model rather than as a
## scale error, and cost several rounds of looking in the wrong place.
##
## So this computes what the GPU will actually draw: every vertex through its own bone weights.
## ~1,700 vertices once per unit, and the result is exact rather than calibrated against a
## screenshot — which matters because the next creature will have different proportions and any
## fudge factor derived from this one would silently be wrong for it.
## ⚠️ UNION OVER EVERY MeshInstance3D, NOT JUST THE FIRST. Several pack creatures are built from
## two or three separate skinned meshes (a body plus horns, a rider, a weapon), and measuring only
## the first one mis-sized 5 of 45 — the astronaut came out at 6.42 units against a 2.6 target and
## the dragon at 1.64. The symptom is a creature that is simply the wrong size next to the others,
## which reads as a modelling problem rather than a measurement one.
func _skinned_bounds() -> AABB:
	var out := AABB()
	var first := true
	for mi in _all_meshes(self):
		var b := _bounds_of(mi)
		if b.size == Vector3.ZERO:
			continue
		out = b if first else out.merge(b)
		first = false
	return out if not first else _bounds_of(_mesh)


func _all_meshes(n: Node, acc: Array = []) -> Array:
	if n is MeshInstance3D:
		acc.append(n)
	for c in n.get_children():
		_all_meshes(c, acc)
	return acc


func _bounds_of(mesh: MeshInstance3D) -> AABB:
	if mesh == null or mesh.mesh == null:
		return AABB()
	var sk := _find(self, "Skeleton3D") as Skeleton3D
	var skin: Skin = mesh.skin if mesh.skin != null else (mesh.get_skin_reference().get_skin() if mesh.get_skin_reference() != null else null)
	var _mesh := mesh          # the body of this function was written against `_mesh`
	if sk == null or skin == null or _mesh.mesh == null:
		return global_transform.affine_inverse() * _mesh.global_transform * _mesh.get_aabb()

	var arrays: Array = _mesh.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	if verts.is_empty() or bones.is_empty() or weights.is_empty():
		return global_transform.affine_inverse() * _mesh.global_transform * _mesh.get_aabb()

	var per_vertex: int = bones.size() / verts.size()   # 4, or 8 for eight-weight meshes
	# One matrix per bone, mesh-space -> world.
	var xf: Array[Transform3D] = []
	var root: Transform3D = global_transform.affine_inverse() * sk.global_transform
	for b in range(sk.get_bone_count()):
		var bind: Transform3D = skin.get_bind_pose(b) if b < skin.get_bind_count() else Transform3D.IDENTITY
		xf.append(root * sk.get_bone_global_pose(b) * bind)

	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in range(verts.size()):
		var v: Vector3 = verts[i]
		var acc := Vector3.ZERO
		var total := 0.0
		for k in range(per_vertex):
			var w: float = weights[i * per_vertex + k]
			if w <= 0.0:
				continue
			var bi: int = bones[i * per_vertex + k]
			if bi < 0 or bi >= xf.size():
				continue
			acc += (xf[bi] * v) * w
			total += w
		if total <= 0.0:
			continue
		acc /= total
		lo = lo.min(acc)
		hi = hi.max(acc)
	if lo.x == INF:
		return global_transform.affine_inverse() * _mesh.global_transform * _mesh.get_aabb()
	return AABB(lo, hi - lo)


## Merges every clip file's animations into the base body's player under one library. The nine
## donor scenes are freed immediately — only their `Animation` resources are retained, and those
## are refcounted so they survive the free.
func _install_clips(species_id: String) -> void:
	var cached: Dictionary = _lib_cache.get(species_id, {})
	var lib := AnimationLibrary.new()

	for state in CLIP_FILE.keys():
		var file: String = CLIP_FILE[state]
		if _clip_of.has(state):
			continue
		var anim: Animation = null
		var name_in_lib := "mt_" + file

		if cached.has(file):
			anim = cached[file]
		else:
			var p := _path_for(species_id, file)
			if not ResourceLoader.exists(p):
				continue
			var donor: Node = (load(p) as PackedScene).instantiate()
			var dp := _find(donor, "AnimationPlayer") as AnimationPlayer
			if dp != null:
				var names := dp.get_animation_list()
				if names.size() > 0:
					# ⚠️ names[0], not a guessed name — see the header. The file is the authority.
					anim = dp.get_animation(names[0]).duplicate()
			donor.queue_free()
			if anim == null:
				continue
			cached[file] = anim

		anim = _normalise_tracks(anim)
		if LOOPING.has(state):
			anim = _strip_root_travel(anim)
		anim.loop_mode = Animation.LOOP_LINEAR if LOOPING.has(state) else Animation.LOOP_NONE
		if not lib.has_animation(name_in_lib):
			lib.add_animation(name_in_lib, anim)
		_clip_of[state] = "mt/" + name_in_lib

	_lib_cache[species_id] = cached
	if _player.has_animation_library("mt"):
		_player.remove_animation_library("mt")
	_player.add_animation_library("mt", lib)


## ⚠️ THE FIX FOR "THE IMAGE IS MORPHING AND CHANGING SHAPE" — and the cause is not what it looks
## like. The ten clips share one skeleton (24 bones, identical names, worst rest-pose difference
## 0.0007 on a toe), so this is NOT a retargeting failure. It is a track-COVERAGE failure:
##
##   idle       pos=8  rot=24  scale=1
##   advance    pos=5  rot=24  scale=0
##   guard      pos=4  rot=24  scale=0
##   attack_alt pos=13 rot=24  scale=0
##
## Every clip rotates all 24 bones, but each one carries POSITION tracks for a different handful
## and only `idle` carries a scale track at all — Meshy exports a channel only where it changes.
## Godot's `AnimationMixer` leaves an untracked property at whatever the previous animation left
## it on, so switching from `attack_alt` (13 position tracks) to `guard` (4) strands nine bones at
## attack_alt's offsets. Bone offsets ARE limb lengths, so the creature visibly stretches and
## reshapes on every state change — worst on the transitions the sim makes most often.
##
## So: give every clip the SAME complete track set, filling anything the exporter omitted with the
## bone's own rest value. After this no property can ever carry over, because there is no such
## thing as an untracked property.
##
## ⚠️ AND FILLING THE GAPS WITH THE REST VALUE IS NOT ENOUGH — measured. With all 24 bones given
## position, rotation and scale tracks in every clip, intra-clip stretch went to 0.00% but the
## CROSS-clip spread stayed at 16.22% on `neck`. The reason: where a clip carries a real position
## track, Meshy's retargeter has baked a per-clip OFFSET into it, and the clips disagree about
## what that offset is. Rest-filling one clip and honouring another's baked offset produces two
## different neck lengths for the same creature.
##
## The principled fix, which is also what skeletal animation normally does: **only the ROOT bone
## may translate.** Every other bone's offset from its parent IS its limb length, fixed by the
## rest pose, and no pose should ever change it — a pose changes joint ANGLES. So non-root
## position tracks are replaced with a single rest key and scale is pinned to rest everywhere.
## Rotation is left completely untouched, which is where all the actual motion lives (all ten
## clips already rotate all 24 bones).
##
## ⚠️ Do NOT "fix" this by removing the blend in `_play()` instead. A hard cut hides the drift for
## a frame and leaves the wrong pose underneath; the bones are still wrong, just less obviously.
func _normalise_tracks(src: Animation) -> Animation:
	var sk := _find(self, "Skeleton3D") as Skeleton3D
	if sk == null:
		return src
	var anim: Animation = src.duplicate()

	# The track path prefix is whatever the exporter used ("Armature/Skeleton3D:BoneName"), read
	# off an existing track rather than assumed — the node path differs per export.
	var prefix := ""
	for t in range(anim.get_track_count()):
		var p := str(anim.track_get_path(t))
		if ":" in p:
			prefix = p.get_slice(":", 0)
			break
	if prefix == "":
		return anim

	# Drop every position track on a non-root bone, and every scale track anywhere. Walk backwards
	# so removal does not shift the indices still to be visited.
	for t in range(anim.get_track_count() - 1, -1, -1):
		var ttype := anim.track_get_type(t)
		if ttype != Animation.TYPE_POSITION_3D and ttype != Animation.TYPE_SCALE_3D:
			continue
		if ttype == Animation.TYPE_POSITION_3D:
			var bone := str(anim.track_get_path(t)).get_slice(":", 1)
			var bi := sk.find_bone(bone)
			if bi >= 0 and sk.get_bone_parent(bi) < 0:
				continue          # the root may translate — that is what moves the body
		anim.remove_track(t)

	# Pin what was just removed to the rest pose, so nothing can carry over from a previous clip.
	for b in range(sk.get_bone_count()):
		var rest: Transform3D = sk.get_bone_rest(b)
		var path := NodePath("%s:%s" % [prefix, sk.get_bone_name(b)])
		if sk.get_bone_parent(b) >= 0:
			var pi := anim.add_track(Animation.TYPE_POSITION_3D)
			anim.track_set_path(pi, path)
			anim.track_insert_key(pi, 0.0, rest.origin)
		var si := anim.add_track(Animation.TYPE_SCALE_3D)
		anim.track_set_path(si, path)
		anim.track_insert_key(si, 0.0, rest.basis.get_scale())
	return anim


## ⚠️ A LOCOMOTION CLIP TRAVELS, AND IN THIS GAME THE SIM OWNS POSITION. A walk cycle carries
## forward translation on the root bone — that is what makes it a walk rather than a march on the
## spot. But `arena_3d.gd` writes each unit's world position every tick from the frame stream, so
## clip travel does not move the unit; it slides the BODY away from the point the sim says it
## occupies. The nameplate, the shadow, the hit tests and the cover checks all stay at the sim's
## position while the creature drifts off it — which reads as the model being detached from the
## game, and gets worse the longer the unit walks.
##
## So horizontal root translation is flattened to its own average and only the VERTICAL component
## survives. The bob is the part that sells weight; the travel is the part the sim already does.
##
## ⚠️ Looping states ONLY. A one-shot like a death or a knockdown SHOULD displace the body — that
## is the motion, not a side effect — and stripping it would leave a creature dying on the spot
## it was standing rather than falling away from the blow.
func _strip_root_travel(src: Animation) -> Animation:
	var sk := _find(self, "Skeleton3D") as Skeleton3D
	if sk == null:
		return src
	var anim: Animation = src
	for t in range(anim.get_track_count()):
		if anim.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		var bone := str(anim.track_get_path(t)).get_slice(":", 1)
		var bi := sk.find_bone(bone)
		if bi < 0 or sk.get_bone_parent(bi) >= 0:
			continue                      # non-root position is already pinned to rest
		var n := anim.track_get_key_count(t)
		if n == 0:
			continue
		var mean := Vector3.ZERO
		for k in range(n):
			mean += anim.track_get_key_value(t, k)
		mean /= float(n)
		for k in range(n):
			var v: Vector3 = anim.track_get_key_value(t, k)
			# keep Y (the bob), pin X/Z to the clip's own average (the stance, not the travel)
			anim.track_set_key_value(t, k, Vector3(mean.x, v.y, mean.z))
	return anim


## The flat-shaded look, and the reason it matters: Meshy bakes lighting into its texture, so an
## unshaded import carries someone else's sun into an arena lit by one warm working lamp
## (`docs/ART_DIRECTION.md`). The shader neutralises that and lets the venue light the creature.
## ⚠️ Absent shader file = keep the imported material. A missing shader must degrade to "looks
## wrong", never to "renders nothing".
func _apply_shader() -> void:
	if not ResourceLoader.exists(SHADER_PATH):
		return
	var sh: Shader = load(SHADER_PATH)
	if sh == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var tex: Texture2D = _texture_for(_species)
	if tex != null:
		mat.set_shader_parameter("albedo_texture", tex)
	_mesh.material_override = mat


## ⚠️ THE ALBEDO COMES FROM A SIDECAR PNG, NOT FROM THE MESH'S OWN MATERIAL — because the .glb we
## load is the texture-STRIPPED one. `tools/glb_strip_textures.py` pulls the embedded image out of
## every animation file (they each carried an identical 8.6 MB copy; ten clips came to 1.65 GB
## across the roster projection), which is what makes shipping ten motions per creature viable at
## all. The cost is exactly this: the model arrives with no albedo, and binding it is the
## renderer's job.
##
## Getting this wrong is not subtle but it IS silent — the first build rendered a flat salmon
## creature with correct geometry, correct animation and correct facing. Everything measurable
## passed. Only the screenshot showed it.
##
## Falls back through the clip textures in order, because the stripper names its output after
## whichever clip it extracted from and they are byte-identical copies of one texture.
func _texture_for(species_id: String) -> Texture2D:
	for file in ["idle", "advance", "attack", "dead"]:
		var p := "res://assets/models/anim/%s_%s_texture_0.png" % [species_id, file]
		if ResourceLoader.exists(p):
			return load(p) as Texture2D
	return null


## The hit tell on a body that has no `modulate`. The shader already owns a body-tint channel
## (`status_tint`/`status_strength`, authored for status effects) and this reuses it rather than
## adding a second one that would have to be blended against the first.
##
## ⚠️ SO A HIT AND A STATUS SHARE ONE CHANNEL, AND THE HIT WINS FOR 0.23s. That is the right way
## round — being hit is the more urgent thing to read — but it means a poisoned unit briefly stops
## looking poisoned when struck. If status body-tint is ever driven live from the frame stream,
## this needs re-deciding rather than discovering.
const HIT_FLASH_COLOUR := Color(1.7, 0.55, 0.55)
const HIT_FLASH_TIME := 0.23

func hit_flash() -> void:
	if _mesh == null:
		return
	var mat := _mesh.material_override
	if mat is ShaderMaterial:
		var sm: ShaderMaterial = mat
		sm.set_shader_parameter("status_tint", HIT_FLASH_COLOUR)
		sm.set_shader_parameter("status_strength", 1.0)
		create_tween().tween_method(
			func(v: float): sm.set_shader_parameter("status_strength", v),
			1.0, 0.0, HIT_FLASH_TIME)
		return
	if mat is BaseMaterial3D:
		var tw := create_tween()
		tw.tween_property(mat, "albedo_color", HIT_FLASH_COLOUR, 0.05)
		tw.tween_property(mat, "albedo_color", Color(1, 1, 1), 0.18)
		return

	# ⚠️ PACK CREATURES HAVE NO `material_override` — they keep the material that shipped with the
	# .glb, which is the whole point (it is already the flat palette look). So neither branch above
	# fired, and the old code still called `create_tween()` first: Godot logged "started with no
	# Tweeners" once per hit, for every unit, for the whole fight.
	#
	# The fix is a per-SURFACE override duplicated once, lazily. Duplicating matters: the .glb's
	# material is SHARED across every unit of that species, so tinting it directly would flash the
	# whole team red when one of them got hit.
	if _flash_mats.is_empty():
		for i in range(_mesh.mesh.get_surface_count()):
			var src := _mesh.get_active_material(i)
			if src == null:
				continue
			var dup: Material = src.duplicate()
			_mesh.set_surface_override_material(i, dup)
			_flash_mats.append(dup)
	if _flash_mats.is_empty():
		return

	# ⚠️ KILL THE PREVIOUS FLASH FIRST. Hits land in bursts, and every call used to start its own
	# parallel tween on the same material. Several tweens driving one property do not queue, they
	# fight — the creature stayed blown-out red for the rest of the fight and read as a giant pink
	# blob rather than as a monster. This is the same class of bug as the animation track carry-over
	# fixed in `_normalise_tracks`: two writers, one property, last-write-wins by accident.
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.set_parallel(true)
	for m in _flash_mats:
		if m is BaseMaterial3D:
			var bm: BaseMaterial3D = m
			if not _flash_base.has(bm):
				_flash_base[bm] = bm.albedo_color
			var base: Color = _flash_base[bm]
			# ⚠️ BLEND TOWARD RED, NEVER REPLACE. `HIT_FLASH_COLOUR` is a >1.0 multiplier authored
			# for a Sprite3D's `modulate`, where it brightens a texture. Written straight into a
			# body's `albedo_color` it discards the creature's own colour entirely and overexposes
			# it. Lerping keeps the species readable while the hit still registers.
			bm.albedo_color = base.lerp(Color(1.0, 0.30, 0.28), 0.6)
			_flash_tween.tween_property(bm, "albedo_color", base, HIT_FLASH_TIME)


func _path_for(species_id: String, file: String) -> String:
	return "res://assets/models/anim/%s_%s_notex.glb" % [species_id, file]


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# THE INTERFACE `arena_3d.gd` DRIVES — identical to creature_anim.gd's
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## Present so a caller can hold either animator behind one variable. The rigged path owns its own
## body, so there is nothing to attach to — but a caller that has to check which kind it holds
## before calling is a caller that will eventually forget.
func setup(_visual: Node3D) -> void:
	pass


## ⚠️ `move_dir` IS TRAVEL, `facing` IS WHERE THE BODY POINTS, AND THEY ARE NO LONGER THE SAME
## THING. Until 2026-08-06 the sim assigned facing straight from the movement direction, so a
## monster physically rotated to point wherever it walked — the user's report that they "have to
## turn their whole body to move in that direction". Now a unit holds its front to its enemy and
## the renderer has to show the difference: walking backwards is the walk clip played in REVERSE,
## which is the whole reason this signature grew a third argument.
##
## ⚠️ THERE ARE NO STRAFE CLIPS IN THE PACKS, AND PRETENDING OTHERWISE WOULD LOOK WORSE. A pure
## sidestep plays the forward walk while the body faces its target. That is a compromise — the
## feet are wrong — but it is the compromise every game without strafe animation makes, and it
## reads far better than spinning the whole body to travel two metres sideways. Authoring real
## strafe clips is the honest fix and it is a content job, not a code one.
## Attach the torso-twist modifier if this rig is one of the legged ones. Safe to call repeatedly.
func _setup_twist() -> void:
	if _twist_mod != null:
		return
	var sk := _find(self, "Skeleton3D") as Skeleton3D
	if sk == null:
		return
	var spine := -1
	var best := SPINE_NAMES.size()
	for i in range(sk.get_bone_count()):
		var lname := sk.get_bone_name(i).to_lower()
		if not _has_legs:
			for l in LEG_NAMES:
				if l in lname:
					_has_legs = true
					break
		for r in range(SPINE_NAMES.size()):
			if SPINE_NAMES[r] in lname and r < best:
				best = r
				spine = i
	if not _has_legs or spine < 0:
		return
	_twist_mod = TorsoTwist.new()
	_twist_mod.bone_idx = spine
	sk.add_child(_twist_mod)


func set_state(state: String, facing: Vector2, move_dir: Vector2 = Vector2.ZERO) -> void:
	_facing = facing
	_move_dir = move_dir
	var backwards := false
	if move_dir.length_squared() > 0.000001 and facing.length_squared() > 0.000001:
		backwards = facing.normalized().dot(move_dir.normalized()) < -0.35
	if backwards != _backwards:
		_backwards = backwards
		if _player != null and (_state == "advance" or _state == "retreat"):
			_player.speed_scale = -1.0 if _backwards else 1.0
	if state == _state:
		return
	_state = state
	# ⚠️ Death and hard control OUTRANK a flinch in progress. Without this, a unit killed during
	# its hit reaction would finish flinching and then stand up dead.
	if state == "dead" or state == "stunned":
		_hurt_t = -1.0
	if _hurt_t >= 0.0:
		return
	_play(state)


func flinch() -> void:
	# A flinch is cosmetic; it must never interrupt something the SIM said is happening.
	if _state == "dead" or _state == "stunned" or _state == "attack" or _state == "cast":
		return
	if not _clip_of.has("hurt"):
		return
	_hurt_t = 0.0
	_play("hurt")


func _play(state: String) -> void:
	if _player == null:
		return
	var clip: String = str(_clip_of.get(state, _clip_of.get("idle", "")))
	if clip == "":
		return
	# A short blend stops the pose snapping when a unit flips between advance and attack every
	# few ticks, which at 10Hz it genuinely does.
	# ⚠️ Reverse playback ONLY for locomotion. Playing an attack or a death backwards is a bug that
	# looks like a joke, and `_backwards` can legitimately be true during either.
	var reverse: bool = _backwards and (state == "advance" or state == "retreat")
	_player.play(clip, 0.12, 1.0, reverse)
	_player.speed_scale = -1.0 if reverse else 1.0


func _process(delta: float) -> void:
	if _hurt_t >= 0.0:
		_hurt_t += delta
		if _hurt_t >= HURT_TIME:
			_hurt_t = -1.0
			_play(_state)

	# Face the sim's own direction. ⚠️ Never computed here — `docs/BUILD_CONTRACT.md` §2: the
	# renderer derives nothing. `facing` is the sim's, and a rigged body can simply be rotated,
	# which is the whole reason geometry unblocks facing where a billboarded sprite could not.
	if _facing.length_squared() > 0.0001:
		_setup_twist()
		var face_yaw: float = atan2(_facing.x, _facing.y)
		# How far travel sits from where the body is looking. Backpedalling is NOT a twist — the
		# reversed walk clip already reads correctly with the body square on to its target — so
		# only the sideways band splits the body.
		var t := 0.0
		if _twist_mod != null and not _backwards and _move_dir.length_squared() > 0.000001:
			var d: float = angle_difference(face_yaw, atan2(_move_dir.x, _move_dir.y))
			t = clampf(d, -deg_to_rad(MAX_TWIST_DEG), deg_to_rad(MAX_TWIST_DEG))
		if _twist_mod != null:
			# Legs take `t` toward travel; the torso gives exactly `t` back, so the chest still
			# points at the target. Eased, or a unit changing lane snaps at the waist.
			_twist_mod.twist = lerp_angle(_twist_mod.twist, -t, 1.0 - exp(-10.0 * delta))
		var yaw: float = face_yaw + t + deg_to_rad(MODEL_YAW_OFFSET_DEG)
		rotation.y = lerp_angle(rotation.y, yaw, 1.0 - exp(-12.0 * delta))


func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null


## Species colour identity on SHARED bodies (Art.SPECIES_TINT — authored, never random).
## Multiplies each surface's albedo so the palette texture keeps the detail and the tint
## carries the identity. Materials are DUPLICATED per rig: glTF surfaces are shared
## resources, and tinting one in place would recolour every other unit wearing this model.
func _apply_species_tint(body: Node3D, species_id: String) -> void:
	var art := get_node_or_null("/root/Art")
	if art == null or not art.has_method("species_tint"):
		return
	var tint: Color = art.species_tint(species_id)
	var glow: float = art.species_glow(species_id) if art.has_method("species_glow") else 0.0
	if tint == Color.WHITE and glow <= 0.0:
		return
	for mi in body.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i)
			if mat is StandardMaterial3D:
				var dup: StandardMaterial3D = mat.duplicate()
				dup.albedo_color = Color(dup.albedo_color.r * tint.r,
					dup.albedo_color.g * tint.g, dup.albedo_color.b * tint.b, dup.albedo_color.a)
				if glow > 0.0:
					# Light-on-dark identities: a multiply cannot brighten, so they GLOW.
					dup.emission_enabled = true
					dup.emission = Color(tint.r * 0.5, tint.g * 0.5, tint.b * 0.5)
					dup.emission_energy_multiplier = glow
				m.set_surface_override_material(i, dup)
