## PROCEDURAL CREATURE ANIMATION — pose from state, no skeleton required.
##
## ⚠️ THIS EXISTS BECAUSE AUTO-RIGGING IS HUMANOID-ONLY. `docs/MESHY_SPIKE_RESULT.md`: Meshy rigs a
## biped mammal fine (24-joint standard skeleton) and REFUSES an avian with
## `422 Pose estimation failed` — three attempts, structural. The roster is 65 species across 13
## body types, so most of it cannot be auto-rigged at all.
##
## The alternative to hand-rigging every bird, fish and insect is to not use skeletons: drive the
## whole body's TRANSFORM from the frame stream's existing `state` and `facing`. That works
## identically for every body type, needs no rig, and at the 20-40px a creature actually occupies
## under the approved camera it competes with skeletal animation more closely than it would in a
## close-up.
##
## ⚠️ AND THE FAILURE MODE IT AVOIDS IS THE REAL ARGUMENT: animating only the creatures that happen
## to auto-rig gives an arena where mammals move and birds are statues. Inconsistency reads as a
## bug; uniformity reads as a style.
##
## Attach to the node that HOLDS the visual (never to the visual itself, so a swap between sprite
## and mesh changes nothing here). Call `set_state()` each frame from the frame stream.
extends Node3D

## Every state the sim emits — `spatial_sim.gd` builds this from `_advancing` and the unit's own
## flags. ⚠️ Keep in lockstep with `docs/BUILD_CONTRACT.md` §2's `state` enum.
const STATES := ["idle", "advance", "retreat", "attack", "cast", "stunned", "dead"]

## Tuning. ⚠️ PROPOSED, NOT BALANCED — these are read at 20-40px, so they are deliberately larger
## than would look right in a close-up. Judge them at arena distance or not at all.
## ⚠️ TUNED UP AFTER THE FIRST PASS READ AS "just wobbling around" (studio owner, in-engine).
## Two things were wrong: every ROTATION was silently eaten by billboarding (see `setup()`), and
## the surviving position/scale motion was pitched for a close-up. At 20-40px a subtle move is no
## move at all — these are deliberately theatrical, and should be judged at arena distance only.
const BREATH_HZ := 0.8           ## idle rise/fall
const BREATH_AMP := 0.055        ## as a fraction of height
const BREATH_LEAN_DEG := 2.5     ## a touch of sway, so idle is not purely vertical
const STRIDE_HZ := 3.2           ## bob while moving
const STRIDE_AMP := 0.13
const STRIDE_ROLL_DEG := 5.0     ## side-to-side roll — reads as WEIGHT shifting, not hovering
const LEAN_DEG := 16.0           ## forward lean when advancing, back when retreating
const ATTACK_LUNGE := 0.62       ## world units toward the target on a swing
const ATTACK_ROT_DEG := 18.0     ## wind up and swing THROUGH, not just a slide
const ATTACK_TIME := 0.26
const CAST_RISE := 0.30          ## a cast lifts and stills — visibly different from a swing
const CAST_SWAY_DEG := 6.0
const HIT_SHAKE := 0.16
const HIT_TIME := 0.22
const STUN_TILT_DEG := 22.0
const DEATH_TIME := 0.55

var _t := 0.0
var _state := "idle"
var _facing := Vector2(1, 0)
var _base_y := 0.0
var _attack_t := -1.0
var _hit_t := -1.0
var _death_t := -1.0
var _visual: Node3D
## ⚠️ True when we took billboarding off a Sprite3D so rotation would actually apply — see setup().
var _manual_facing := false


## ⚠️ BILLBOARDING SILENTLY EATS EVERY ROTATION, AND THAT IS THE WHOLE BUG THIS FIXES.
## `docs/BUILD_CONTRACT.md`:190 — "A `Sprite3D` with `billboard` enabled cannot be rotated —
## billboarding re-solves every frame and silently undoes it." The arena's sprites ship as
## `BILLBOARD_FIXED_Y`, so the first version of this animator applied lean, stun-tilt and death
## topple to a quad that then re-oriented itself, leaving ONLY position and scale — which reads
## exactly as the studio owner described it: "they are just wobbling around".
##
## The fix is to take billboarding off and do it ourselves, which is what the pre-existing death
## code at `arena_3d.gd:1268` already had to do for the same reason. `_face_camera()` below
## reproduces the Y-billboard behaviour, and the pose rotation is then composed ON TOP of it
## instead of being overwritten by it.
func setup(visual: Node3D) -> void:
	_visual = visual
	_base_y = visual.position.y
	if visual is SpriteBase3D and visual.billboard != BaseMaterial3D.BILLBOARD_DISABLED:
		visual.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		_manual_facing = true


## Called each frame from the frame stream. ⚠️ `facing` is the sim's own Vector2 — this NEVER
## computes a facing of its own, because `docs/BUILD_CONTRACT.md` §2 says the renderer derives
## nothing. If a pose needs information, the sim must emit it.
func set_state(state: String, facing: Vector2) -> void:
	if state != _state:
		# edge-triggered poses fire once on entry, not every frame they persist
		if state == "attack":
			_attack_t = 0.0
		elif state == "dead" and _state != "dead":
			_death_t = 0.0
		_state = state
	_facing = facing


## Call when this unit TAKES a hit — the sim emits shots, so the renderer knows the victim.
func flinch() -> void:
	_hit_t = 0.0


func _process(delta: float) -> void:
	if _visual == null:
		return
	_t += delta
	if _attack_t >= 0.0: _attack_t += delta
	if _hit_t >= 0.0: _hit_t += delta
	if _death_t >= 0.0: _death_t += delta

	var pos := Vector3.ZERO
	var rot := Vector3.ZERO
	var scl := Vector3.ONE

	match _state:
		"idle", "cast":
			# Breathing: a slow vertical rise with a matching squash, so the volume reads as
			# preserved rather than the whole body scaling.
			var b: float = sin(_t * TAU * BREATH_HZ)
			pos.y = b * BREATH_AMP
			scl.y = 1.0 + b * BREATH_AMP * 0.5
			scl.x = 1.0 - b * BREATH_AMP * 0.25
			scl.z = scl.x
			rot.z = deg_to_rad(BREATH_LEAN_DEG) * sin(_t * TAU * BREATH_HZ * 0.5)
			if _state == "cast":
				pos.y += CAST_RISE            # lift and still — legibly not a swing
				rot.z = deg_to_rad(CAST_SWAY_DEG) * sin(_t * 2.4)
		"advance", "retreat":
			var s: float = sin(_t * TAU * STRIDE_HZ)
			pos.y = absf(s) * STRIDE_AMP      # a bob never dips below the ground plane
			scl.y = 1.0 - absf(s) * 0.04
			var dir := 1.0 if _state == "advance" else -1.0
			rot.x = deg_to_rad(-LEAN_DEG * dir)
			# Roll with the stride so weight visibly shifts foot to foot.
			rot.z = deg_to_rad(STRIDE_ROLL_DEG) * s
		"stunned":
			# No breathing at all — stillness is the tell, and the tilt says which way it fell.
			rot.z = deg_to_rad(STUN_TILT_DEG) + sin(_t * 7.0) * 0.02
			pos.y = -0.04
		"dead":
			var d: float = clampf(_death_t / DEATH_TIME, 0.0, 1.0)
			rot.z = deg_to_rad(88.0 * d)
			pos.y = -0.35 * d
			scl.y = 1.0 - 0.15 * d

	# ── ATTACK: a lunge along facing, out fast and back slow. ⚠️ Overlays whatever the state pose
	# is doing rather than replacing it, so a unit can swing while still reading as advancing.
	if _attack_t >= 0.0:
		var a: float = _attack_t / ATTACK_TIME
		if a >= 1.0:
			_attack_t = -1.0
		else:
			# out on the first third, ease back over the rest — a symmetric curve reads as a nudge
			var k: float = (a / 0.33) if a < 0.33 else (1.0 - (a - 0.33) / 0.67)
			pos += Vector3(_facing.x, 0.0, _facing.y).normalized() * ATTACK_LUNGE * k
			# ⚠️ Swing THROUGH the lunge. Position alone reads as a slide; the rotation is what
			# makes it read as a strike — and it only works now that billboarding is off.
			rot.x += deg_to_rad(-ATTACK_ROT_DEG) * k
			scl.x *= 1.0 + 0.16 * k
			scl.y *= 1.0 - 0.10 * k

	# ── FLINCH: a short shake, independent of everything else.
	if _hit_t >= 0.0:
		var h: float = _hit_t / HIT_TIME
		if h >= 1.0:
			_hit_t = -1.0
		else:
			var damp: float = 1.0 - h
			pos.x += sin(_hit_t * 90.0) * HIT_SHAKE * damp
			pos.y += cos(_hit_t * 70.0) * HIT_SHAKE * 0.4 * damp

	_visual.position = Vector3(pos.x, _base_y + pos.y, pos.z)
	# ⚠️ Compose: face the camera FIRST (the job billboarding used to do), then add the pose on
	# top. Assigning `rotation` directly would throw the facing away and the sprite would show its
	# edge to the camera whenever the arena camera moved.
	if _manual_facing:
		_visual.rotation = Vector3(rot.x, _camera_yaw(), rot.z)
	else:
		_visual.rotation = rot
	_visual.scale = scl


## Y-axis billboard, done by hand: yaw the sprite to face the active camera, leaving pitch and roll
## free for the pose. Mirrors `BILLBOARD_FIXED_Y`, which is what these sprites used before.
func _camera_yaw() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null or _visual == null:
		return 0.0
	var to_cam := cam.global_position - _visual.global_position
	return atan2(to_cam.x, to_cam.z)
