## THE VFX SCALE PROBE — measures whether an effect is the right SIZE for the board it is
## played on, and whether a flash out-lights the venue.
##
## Run WINDOWED (Phase B reads the framebuffer; `--headless` has none):
##   P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/_probe_vfx_scale.tscn
##
## ⚠️ WHY THIS EXISTS. `docs/ABILITY_BALANCE_REVIEW.md` records the project's standing failure
## class: "every spatial constant is a fixed absolute tuned to a ~40-wide field and none scale
## with the board." VFX had the same disease — a ground ring authored to look right around one
## 1v1 duel is a lake on a 5v5 ground, and a 6-energy omni with a 14-unit range does not light an
## impact, it lights the STANDS. Neither is visible in code review: both look like small numbers.
##
## TWO PHASES, TWO KINDS OF MEASUREMENT:
##
##   A. GEOMETRY (analytic, exact). Fire each effect and measure the world-space footprint of the
##      nodes it actually created or claimed — mesh AABBs for the shader decals and beams, an
##      explicit spray model for the particle emitters (documented at `_particle_span`). Judged
##      against the SMALLEST board in the game (1v1), because an effect that fits there fits
##      everywhere, and against the body, because an effect smaller than a monster is invisible.
##
##   B. PHOTOMETRY (rendered, whole-frame). A board-sized ground under the venue's own lamp and
##      tonemap. Take a baseline frame, fire a flash, take the peak frame. The number that matters
##      is the RATIO: a flash may brighten the frame, it may not replace it.
##
## ⚠️ THE FRACTIONS BELOW ARE THE CONTRACT, NOT A PREFERENCE. They are the reason this stops
## regressing: a future effect authored in absolutes fails here before it ships.
extends Node3D

const Sp = preload("res://scripts/spatial.gd")
const VfxScript = preload("res://scripts/ui/vfx.gd")

# ── THE THRESHOLDS ────────────────────────────────────────────────────────────────────────────
## No single effect may cover more than this fraction of the board's SHORT dimension. At 0.30 a
## sonic boom on a 1v1 ground still reads as a big loud thing (~13 units, three bodies across)
## without becoming the floor. Measured against the short side because that is the one the camera
## runs out of first.
const MAX_GROUND_FRAC := 0.30
## A light's diameter of influence, same yardstick. A flash is a PUDDLE around an impact; past
## this it is venue lighting, and venue lighting is `arena_3d.gd`'s job, not an explosion's.
const MAX_LIGHT_FRAC := 0.22
## Absolute ceiling on a pooled flash's energy. The venue's own key runs at 2.0-2.2.
const MAX_LIGHT_ENERGY := 3.0
## An effect must not be a speck: below half a body it cannot carry a read at the game's camera.
const MIN_SPAN_BODY_FRAC := 0.5
## Floor luminance FAR from a flash (beyond a quarter-board), relative to its unlit baseline. A
## flash is allowed to light its impact; it is not allowed to relight the far end of the ground —
## and the stands are directly behind that.
const MAX_FAR_LUMA_RATIO := 1.12
## ...and the opposite guard, so a fix cannot land by making effects invisible: the floor UNDER a
## flash must actually brighten.
const MIN_NEAR_LUMA_RATIO := 1.02
## The half-span the battle camera closes to while following a fight. `_probe_venue.gd` uses 26 for
## the same reason: it frames roughly five bodies plus the ground around them at every board size,
## which is what the player is looking at when an ability goes off.
const FIGHT_SPAN := 26.0
## Whole-frame luminance at FIGHT framing, during an effect, relative to the frame without it. A
## flash may punctuate the picture; it may not become it.
const MAX_FRAME_LUMA_RATIO := 1.30

var _rows: Array = []
var _luma_rows: Array = []
var _vfx: Node3D = null
var _cam: Camera3D = null
var _board := Vector2(100, 60)
var _body_r := 2.2
var _fail := 0
var _bodies: Array = []
## How far a floor sample must stay from a body to still be floor.
const BODY_CLEARANCE := 4.0


func _ready() -> void:
	var cmap: Dictionary = (load("res://scripts/ui/arena_3d.gd") as GDScript).get_script_constant_map()
	var world_scale := float(cmap.get("WORLD_SCALE", 0.34))
	var unit_h := float(cmap.get("UNIT_HEIGHT", 4.4))
	_body_r = unit_h * 0.5   # `arena_3d.gd:CAM_BODY_RADIUS` — the renderer's own idea of body size

	for team_size in [1, 5]:
		var g: Vector2 = Sp.ground_size(team_size)
		_board = Vector2(g.x * world_scale, g.y * world_scale)
		await _run_case_set(team_size)

	_report()
	get_tree().quit(1 if _fail > 0 else 0)


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# STAGE
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _build_stage() -> void:
	for c in get_children():
		c.queue_free()
	await get_tree().process_frame

	# ⚠️ THE STAGE IS THE REAL VENUE'S LAMP, NOT A LAMP THAT LOOKS LIKE IT. The first stage used a
	# hand-picked floor albedo and measured a baseline floor luminance of 0.889 — SATURATED, so no
	# light on earth could brighten it and every ratio came back 1.00 including the control. Reading
	# `arena_3d.gd:LEAGUE_LOOK` means the headroom a flash is competing for is the headroom the
	# player's frame actually has. Platinum is the sample: a grand-circuit board, the exact league
	# the "entirely magenta" screenshot came from.
	var acmap: Dictionary = (load("res://scripts/ui/arena_3d.gd") as GDScript).get_script_constant_map()
	var look: Dictionary = (acmap.get("LEAGUE_LOOK", {}) as Dictionary).get(
		"Platinum", acmap.get("DEFAULT_LOOK", {}))

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = look.get("fog", Color(0.13, 0.14, 0.18))
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = look.get("amb", Color(0.32, 0.38, 0.50))
	e.ambient_light_energy = float(look.get("amb_e", 0.32))
	# Same tonemap as the real venue — a luminance number taken under a different transfer curve
	# is not comparable with the one the player sees.
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 1.0
	e.tonemap_exposure = 1.0
	env.environment = e
	add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, -34, 0)
	key.light_color = look.get("key", Color(1.00, 0.86, 0.64))
	key.light_energy = float(look.get("key_e", 2.0))
	key.shadow_enabled = false
	add_child(key)

	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = _board
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new()
	# `arena_3d.gd`'s own untextured-ground branch, verbatim.
	var g: Color = look.get("ground", Color(0.58, 0.55, 0.50))
	fm.albedo_color = Color(0.55 * g.r, 0.50 * g.g, 0.43 * g.b)
	fm.roughness = 0.96
	fm.metallic = 0.0
	fm.metallic_specular = 0.08
	floor_mesh.material_override = fm
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(floor_mesh)

	# ── THE CAST AND THE VENUE SHELL ──────────────────────────────────────────────────────────
	# ⚠️ A BARE FLOOR UNDER-REPORTS THE BUG, MEASURABLY. With nothing but ground in the stage, an
	# `explosion_pro` moved the frame by 1% — because a flat plane lit from two units above it
	# takes light at a grazing angle and barely brightens. The screenshots that started this round
	# (an entirely magenta Platinum) are magenta because the light hits things standing UP: the
	# bodies, the barrier, the stands. So the stage has them, and the numbers move.
	#
	# ⚠️ AND THE BODIES BREAK THE FLOOR PHOTOMETER IF IGNORED — an earlier stage put one capsule at
	# the origin and every "floor" sample around the impact was reading the capsule (or the smoke
	# drawn over it), so a flash measured as DARKENING the ground. `_floor_luma` skips any sample
	# within `BODY_CLEARANCE` of one, the same guard `_probe_venue.gd` uses for the same reason.
	_bodies = [Vector3(-6, 0, -4), Vector3(-3, 0, 5), Vector3(2.5, 0, -2), Vector3(6, 0, 3.5), Vector3(8, 0, -6)]
	for bp in _bodies:
		var body := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = _body_r * 0.45
		cap.height = _body_r * 2.2
		body.mesh = cap
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.62, 0.58, 0.54)
		bm.roughness = 0.85
		body.material_override = bm
		body.position = bp + Vector3(0, _body_r * 1.1, 0)
		add_child(body)

	# The barrier ring, at `arena_3d.gd:WALL_H`.
	var wall_h := float(acmap.get("WALL_H", 1.4))
	for w in [[Vector3(0, wall_h * 0.5, -_board.y * 0.5 - 0.4), Vector3(_board.x + 1.6, wall_h, 0.8)],
			[Vector3(0, wall_h * 0.5, _board.y * 0.5 + 0.4), Vector3(_board.x + 1.6, wall_h, 0.8)],
			[Vector3(-_board.x * 0.5 - 0.4, wall_h * 0.5, 0), Vector3(0.8, wall_h, _board.y + 1.6)],
			[Vector3(_board.x * 0.5 + 0.4, wall_h * 0.5, 0), Vector3(0.8, wall_h, _board.y + 1.6)]]:
		var wall := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = w[1]
		wall.mesh = bm2
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.30 * g.r * 0.85, 0.24 * g.g * 0.85, 0.19 * g.b * 0.85)
		wm.roughness = 0.9
		wall.material_override = wm
		wall.position = w[0]
		add_child(wall)

	_cam = Camera3D.new()
	_cam.fov = 26.0   # `arena_3d.gd:CAM_FOV` — the long lens the venue is framed with
	add_child(_cam)
	_set_framing(maxf(_board.x, _board.y) * 0.55)

	_vfx = VfxScript.new()
	add_child(_vfx)
	# The probe has no arena to resolve a basis from, so it states one explicitly.
	_vfx.set_scale_basis(_board, _body_r * 2.0)
	for i in range(4):
		await get_tree().process_frame


## Point the camera at the board centre with a given half-span, at the venue's own 38-degree
## elevation. TWO framings matter and they answer different questions — see `_photometry`.
func _set_framing(span: float) -> void:
	var dist: float = span / tan(deg_to_rad(_cam.fov * 0.5))
	var elev := deg_to_rad(38.0)
	_cam.position = Vector3(0, sin(elev) * dist, cos(elev) * dist)
	_cam.look_at(Vector3.ZERO, Vector3.UP)


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# PHASE A — GEOMETRY
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## The catalogue. Every public entry point plus one representative move per `play_ability` recipe,
## so a recipe cannot quietly grow past the contract.
func _cases() -> Array:
	var v = _vfx
	var C := Vector3.ZERO
	var far := Vector3(_board.x * 0.25, 0, _board.y * 0.2)
	return [
		["burst/impact", func(): v.burst(C, "impact", Color.WHITE, 1.0, 10)],
		["burst/smoke", func(): v.burst(C, "smoke", Color.WHITE, 1.8, 16)],
		["spark_trails", func(): v.spark_trails(C, 1.0)],
		["explosion_pro x1", func(): v.explosion_pro(C, 1.0)],
		["explosion_pro x2.5", func(): v.explosion_pro(C, 2.5)],
		["flip/explosion", func(): v.flip(C, "explosion", 5.0)],
		["flip/frost_veil", func(): v.flip(C, "frost_veil", 8.0)],
		["static_ring default", func(): v.static_ring(C)],
		["shockwave default", func(): v.shockwave(C)],
		["shockwave 9 (boom)", func(): v.shockwave(C, 9.0)],
		["dome default", func(): v.dome(C)],
		["ward_dome", func(): v.ward_dome(C, Color.WHITE)],
		["aura_pulse", func(): v.aura_pulse(C, Color.WHITE)],
		["heal_rise", func(): v.heal_rise(C)],
		["light_flash default", func(): v.light_flash(C, Color.WHITE)],
		["lightning", func(): v.lightning(C + Vector3(0, 3, 0), far + Vector3(0, 3, 0))],
		["siphon_beam", func(): v.siphon_beam(C + Vector3(0, 3, 0), far + Vector3(0, 3, 0))],
		["doom_tether", func(): v.doom_tether(C + Vector3(0, 3, 0), far + Vector3(0, 3, 0))],
		["ab/Inferno", func(): v.play_ability(_mv("Inferno", "damage", "magic"), far, C, false)],
		["ab/Sonic Boom", func(): v.play_ability(_mv("Sonic Boom", "damage", "voice"), far, C, false)],
		["ab/Body Slam", func(): v.play_ability(_mv("Body Slam", "damage", "melee"), far, C, false)],
		["ab/Chain Lightning", func(): v.play_ability(_mv("Chain Lightning", "damage", "magic"), far, C, false)],
		["ab/Blizzard", func(): v.play_ability(_mv("Blizzard", "damage", "magic"), far, C, false)],
		["ab/Deadeye", func(): v.play_ability(_mv("Deadeye", "damage", "ranged"), far, C, false)],
		["ab/Taunt", func(): v.play_ability(_mv("Taunt", "control", "voice"), far, C, false)],
		["ab/Arcane Aegis", func(): v.play_ability(_mv("Arcane Aegis", "buff", "magic"), far, C, false)],
		["ab/Doom", func(): v.play_ability(_mv("Doom", "debuff", "magic"), far, C, false)],
		["ab/Siphon Soul", func(): v.play_ability(_mv("Siphon Soul", "damage", "magic"), far, C, false)],
		["ab/magic_hit crit", func(): v.play_ability(_mv("Firebolt", "damage", "magic"), far, C, true, 2.5)],
		["ab/voice_hit", func(): v.play_ability(_mv("Shout", "damage", "voice"), far, C, false)],
		["ab/control", func(): v.play_ability(_mv("Freeze", "control", "magic"), far, C, false)],
		["ab/aura_buff", func(): v.play_ability(_mv("Rally", "buff", "support"), far, C, false)],
	]


func _mv(nm: String, t: String, ch: String) -> Dictionary:
	return {"name": nm, "type": t, "channel": ch, "target": "ally" if t == "buff" else "enemy", "line": ""}


func _run_case_set(team_size: int) -> void:
	await _build_stage()
	for case in _cases():
		var before := _snapshot()
		(case[1] as Callable).call()
		var rec := _measure(before)
		rec["case"] = str(case[0])
		rec["team"] = team_size
		_rows.append(rec)
		# Let the tweened decals run to their free so the next case measures a clean stage.
		for i in range(3):
			await get_tree().process_frame
		_quiet()
		await get_tree().process_frame
	await _photometry(team_size)


func _snapshot() -> Dictionary:
	var ids := {}
	for c in _vfx.get_children():
		ids[c.get_instance_id()] = true
	var emitting := {}
	for p in _all_particles():
		if p.emitting:
			emitting[p.get_instance_id()] = true
	var lit := {}
	for li in _vfx._lights:
		if (li as OmniLight3D).light_energy > 0.001:
			lit[li.get_instance_id()] = true
	return {"ids": ids, "emitting": emitting, "lit": lit}


func _all_particles() -> Array:
	var out: Array = []
	out.append_array(_vfx._pool)
	out.append_array(_vfx._flip_pool)
	out.append_array(_vfx._spark_trails)
	return out


func _quiet() -> void:
	for p in _all_particles():
		(p as GPUParticles3D).emitting = false
	for li in _vfx._lights:
		(li as OmniLight3D).light_energy = 0.0
	if _ctrl != null and is_instance_valid(_ctrl):
		_ctrl.light_energy = 0.0


func _measure(before: Dictionary) -> Dictionary:
	var span := 0.0
	var widest := ""
	var energy := 0.0
	var lrange := 0.0
	for c in _vfx.get_children():
		if (before["ids"] as Dictionary).has(c.get_instance_id()):
			continue
		# A BEAM IS JUDGED ON ITS WIDTH, NOT ITS LENGTH. `lightning`/`siphon_beam`/`doom_tether`
		# span whatever gap the two monsters happen to be standing across — that is the fight's
		# geometry, not an authored size, and flagging it as "too big" would be flagging the
		# arena. What IS authored, and what was a fixed absolute, is how THICK the beam is.
		var s := _beam_width(c)
		if s < 0.0:
			s = _node_span(c)
		if s > span:
			span = s
			widest = c.get_class()
	for p in _all_particles():
		var gp := p as GPUParticles3D
		if not gp.emitting or (before["emitting"] as Dictionary).has(gp.get_instance_id()):
			continue
		var s := _particle_span(gp)
		if s > span:
			span = s
			widest = "particles"
	for li in _vfx._lights:
		var o := li as OmniLight3D
		if o.light_energy <= 0.001 or (before["lit"] as Dictionary).has(o.get_instance_id()):
			continue
		energy = maxf(energy, o.light_energy)
		lrange = maxf(lrange, o.omni_range)
	# Cast glows are looping nodes parented on demand; sweep them too.
	for k in _vfx._cast_loops:
		var s := _particle_span(_vfx._cast_loops[k] as GPUParticles3D)
		if s > span:
			span = s
			widest = "cast_glow"
	return {"span": span, "what": widest, "energy": energy, "range": lrange}


## If `n` is a beam rig (a bare holder of FACE_Z PlaneMesh quads), return the authored beam WIDTH;
## otherwise -1. The width is the plane's `size.y` — `size.x` is the length of the gap it spans.
func _beam_width(n: Node) -> float:
	if n is MeshInstance3D or n.get_child_count() == 0:
		return -1.0
	var w := -1.0
	for c in n.get_children():
		if not (c is MeshInstance3D):
			return -1.0
		var m = (c as MeshInstance3D).mesh
		if not (m is PlaneMesh) or (m as PlaneMesh).orientation != PlaneMesh.FACE_Z:
			return -1.0
		w = maxf(w, (m as PlaneMesh).size.y)
	return w


## World-space XZ extent of a node's own meshes (recursing through beam holders).
func _node_span(n: Node) -> float:
	var best := 0.0
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			var ab: AABB = mi.mesh.get_aabb()
			var t: Transform3D = mi.global_transform
			var lo := Vector3(INF, INF, INF)
			var hi := Vector3(-INF, -INF, -INF)
			for i in range(8):
				var corner: Vector3 = t * (ab.position + Vector3(
					ab.size.x * float(i & 1), ab.size.y * float((i >> 1) & 1), ab.size.z * float((i >> 2) & 1)))
				lo = Vector3(minf(lo.x, corner.x), minf(lo.y, corner.y), minf(lo.z, corner.z))
				hi = Vector3(maxf(hi.x, corner.x), maxf(hi.y, corner.y), maxf(hi.z, corner.z))
			best = maxf(hi.x - lo.x, hi.z - lo.z)
	if n is GPUParticles3D:
		best = maxf(best, _particle_span(n as GPUParticles3D))
	for c in n.get_children():
		best = maxf(best, _node_span(c))
	return best


## THE SPRAY MODEL. A GPUParticles3D has no honest AABB until it has run, so the footprint is
## derived from what the emitter is AUTHORED to do: the emission shape it starts on, plus how far
## a particle travels in its lifetime, plus the sprite's own size.
## ⚠️ Damping is real and large on the trail emitters — a 22 u/s spark damped at 4-8 does not
## travel 22*lifetime. The 0.45 factor is the closed-form mean of an exponentially damped launch
## over these lifetimes; it is a MODEL and it is stated here rather than hidden in a constant.
func _particle_span(p: GPUParticles3D) -> float:
	var mat := p.process_material as ParticleProcessMaterial
	if mat == null:
		return 0.0
	var mesh := p.draw_pass_1
	var sprite := 0.0
	if mesh is QuadMesh:
		var sm: StandardMaterial3D = (mesh as QuadMesh).material
		var keep_scale: bool = sm != null and sm.billboard_keep_scale
		sprite = (mesh as QuadMesh).size.x * (1.0 if keep_scale else mat.scale_max)
	elif mesh is RibbonTrailMesh:
		sprite = (mesh as RibbonTrailMesh).size
	var damp := 1.0 if mat.damping_max <= 0.0 else 0.45
	var travel: float = mat.initial_velocity_max * p.lifetime * damp
	var emit := 0.0
	if mat.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_RING:
		emit = mat.emission_ring_radius
	return 2.0 * (emit + travel) + sprite


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# PHASE B — PHOTOMETRY
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## ⚠️ THE FIRST PHOTOMETER WAS A WHOLE-FRAME MEAN AND IT WAS USELESS — it reported a ratio of
## exactly 1.00 for every flash, and its own control (an absurd 16-energy board-wide omni, the row
## that is SUPPOSED to fail) only moved it to 1.03. The reason is that four fifths of the frame is
## background void, which no light in the arena touches, so the signal was diluted into nothing.
##
## What the complaint actually is — "a single explosion bathes the floor, the stands and the crowd
## in red" — is a statement about the GROUND, and about the ground FAR FROM THE IMPACT. So this
## samples the floor itself, in two rings:
##   NEAR  (within 2.5 body radii of the flash) — this SHOULD brighten; a flash that does not light
##         the ground it went off on reads as a sticker, and over-correcting into invisibility is
##         the same failure with the opposite sign.
##   FAR   (beyond a quarter of the board) — this MUST NOT. Past that distance the light is not
##         lighting an impact any more, it is relighting the venue, and the stands are just behind.
func _photometry(team_size: int) -> void:
	_quiet()
	for i in range(3):
		await get_tree().process_frame
	# The floor immediately under the impact — one body radius out. Wider than this and the ring
	# samples ground the flash was never meant to reach, and the NEAR check stops meaning
	# "did it light the hit" and starts meaning "did it light the neighbourhood".
	var near_r: float = _body_r * 2.0
	var shots := [
		# The control is the calibration source: an unmissable, untweened, board-wide light. It is
		# judged INVERTED — it must blow the FAR check. If it does not, the photometer is blind and
		# every row under it is decoration.
		# name, fire, is_control, check_near
		# ⚠️ NEAR IS ONLY CHECKED ON A BARE LIGHT. On a composite like `explosion_pro` the smoke
		# plume is drawn OVER the ground it just lit, so the near-floor reading falls even when the
		# light is working perfectly — that confound made the first run flag every row. The lit-ness
		# question belongs to the light alone; the composites are here for the FAR question, which
		# is the one about the venue.
		["CONTROL absurd light", func(): _control_light(), true, false],
		["light_flash e5 (bare)", func(): _vfx.light_flash(Vector3.ZERO, Color(1, 0.65, 0.3), 5.0, 0.35), false, true],
		["light_flash e2.2 (heal)", func(): _vfx.light_flash(Vector3.ZERO, Color(0.5, 0.9, 0.55), 2.2, 0.5), false, true],
		["explosion_pro x1", func(): _vfx.explosion_pro(Vector3.ZERO, 1.0), false, false],
		["explosion_pro x2.5", func(): _vfx.explosion_pro(Vector3.ZERO, 2.5), false, false],
		["ab/Inferno", func(): _vfx.play_ability(_mv("Inferno", "damage", "magic"), Vector3(20, 0, 0), Vector3.ZERO, false), false, false],
	]
	for shot in shots:
		# ⚠️ RE-BASELINE BEFORE EVERY SHOT, AND WAIT FOR THE STAGE TO GO DARK FIRST. A single
		# baseline taken once at the top read HIGHER than the shots that followed it — because
		# `emitting = false` stops new particles, it does not erase the live ones, and a 1s-lifetime
		# smoke plume from the previous case was still lit in the "baseline" frame. A flash then
		# measured as DARKENING the floor, which is not a thing an additive light can do.
		await _settle()
		var base_near := await _floor_luma(0.0, near_r)
		var base_far := await _floor_luma(_board.x * 0.25, INF)
		(shot[1] as Callable).call()
		var near := 0.0
		var far := 0.0
		for i in range(3):
			near = maxf(near, await _floor_luma(0.0, near_r))
			far = maxf(far, await _floor_luma(_board.x * 0.25, INF))

		# ── SECOND FRAMING: what the player is actually looking at. ────────────────────────────
		# ⚠️ THIS IS THE ONE THAT CATCHES THE REPORTED BUG, AND THE BOARD-WIDE ONE DOES NOT. The
		# complaint is screenshots of an ENTIRELY MAGENTA Platinum and an entirely green Silver,
		# and a 14-unit-range light cannot reach the far end of a 149-unit board — measured at
		# 1.00, every time. It does not have to: the battle camera closes to a ~26-unit span to
		# follow the fight (`_probe_venue.gd` frames at exactly that), and a light whose pool is
		# 28 units across is then WIDER THAN THE ENTIRE FRAME. The effect never grew; the camera
		# came in. An effect is only the right size relative to the shot it is played in.
		await _settle()
		_set_framing(FIGHT_SPAN)
		await get_tree().process_frame
		var fight_base := await _frame_luma()
		(shot[1] as Callable).call()
		var fight_peak := 0.0
		for i in range(3):
			fight_peak = maxf(fight_peak, await _frame_luma())
		_set_framing(maxf(_board.x, _board.y) * 0.55)

		_luma_rows.append({"team": team_size, "case": str(shot[0]), "control": bool(shot[2]),
			"check_near": bool(shot[3]),
			"base_near": base_near, "near": near, "base_far": base_far, "far": far,
			"fight_base": fight_base, "fight_peak": fight_peak})
		await _settle()


## Stop every emitter and wait long enough for the longest live particle (1.1s flipbooks, 1.0s
## aura rings) to die, so the next baseline photographs an empty stage.
func _settle() -> void:
	_quiet()
	for i in range(100):
		await get_tree().process_frame


var _ctrl: DirectionalLight3D = null

## The photometer's calibration source: a second SUN. Deliberately not an omni — an omni bright
## enough to move the far floor has to be absurd (the far ring on a 5v5 board reaches 70 units out,
## where both distance falloff and the grazing N-dot-L have already killed it), and an instrument
## whose control is at the edge of its own sensitivity proves nothing. A directional light lifts
## every point on the ground by construction, so this row failing can only mean the photometer is
## not reading the frame.
func _control_light() -> void:
	if _ctrl == null or not is_instance_valid(_ctrl):
		_ctrl = DirectionalLight3D.new()
		_ctrl.shadow_enabled = false
		add_child(_ctrl)
	_ctrl.rotation_degrees = Vector3(-80, 0, 0)
	_ctrl.light_color = Color(1, 1, 1)
	_ctrl.light_energy = 3.0


## Mean luminance of the WHOLE rendered frame — the "did this effect replace the picture" number.
func _frame_luma() -> float:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var sum := 0.0
	var n := 0
	for ix in range(48):
		for iy in range(36):
			sum += img.get_pixel(int(float(ix) / 48.0 * w), int(float(iy) / 36.0 * h)).get_luminance()
			n += 1
	return sum / maxf(1.0, float(n))


## Median luminance of the FLOOR, over board sample points whose distance from the origin (where
## every shot is fired) falls in [r_min, r_max). Median, not mean: one blown pixel must not decide
## a verdict, and the floor is what the player is trying to read the fight against.
func _floor_luma(r_min: float, r_max: float) -> float:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var isz := Vector2(img.get_width(), img.get_height())
	var vals: Array = []
	for ix in range(61):
		for iy in range(45):
			var w := Vector3(
				lerpf(-0.48, 0.48, float(ix) / 60.0) * _board.x, 0.0,
				lerpf(-0.48, 0.48, float(iy) / 44.0) * _board.y)
			var d := Vector2(w.x, w.z).length()
			if d < r_min or d >= r_max:
				continue
			if _cam == null or _cam.is_position_behind(w):
				continue
			var blocked := false
			for bp in _bodies:
				if Vector2(w.x - bp.x, w.z - bp.z).length() < BODY_CLEARANCE:
					blocked = true
					break
			if blocked:
				continue
			var sp: Vector2 = _cam.unproject_position(w)
			var p := Vector2(sp.x / maxf(1.0, vp.x) * isz.x, sp.y / maxf(1.0, vp.y) * isz.y)
			if p.x < 2 or p.y < 2 or p.x >= isz.x - 2 or p.y >= isz.y - 2:
				continue
			vals.append(img.get_pixel(int(p.x), int(p.y)).get_luminance())
	if vals.is_empty():
		return 0.0
	vals.sort()
	return float(vals[vals.size() / 2])


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# REPORT
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _report() -> void:
	var cmap: Dictionary = (load("res://scripts/ui/arena_3d.gd") as GDScript).get_script_constant_map()
	var world_scale := float(cmap.get("WORLD_SCALE", 0.34))
	print("")
	print("VFX SCALE PROBE — body radius %.2f, boards (world units):" % _body_r)
	for ts in [1, 5]:
		var g: Vector2 = Sp.ground_size(ts)
		print("   %dv%d  %.1f x %.1f   short side %.1f  |  max effect span %.1f  max light dia %.1f"
			% [ts, ts, g.x * world_scale, g.y * world_scale, minf(g.x, g.y) * world_scale,
			minf(g.x, g.y) * world_scale * MAX_GROUND_FRAC, minf(g.x, g.y) * world_scale * MAX_LIGHT_FRAC])
	print("")
	print("team  case                    span    %short  bodies  lightE  lightR  verdict")
	for r in _rows:
		var g: Vector2 = Sp.ground_size(int(r["team"]))
		var short: float = minf(g.x, g.y) * world_scale
		var frac: float = float(r["span"]) / short
		var bodies: float = float(r["span"]) / (_body_r * 2.0)
		var bad: Array = []
		# EPSILON, AND IT IS NOT A FUDGE. `vfx.gd:_cap_ground` clamps to exactly this fraction, so a
		# correctly-capped effect lands on the boundary and `12.566... / 41.888... = 0.30000000000000004`
		# reads as over it. Without the tolerance the probe fails the very thing it asked for.
		if frac > MAX_GROUND_FRAC + 1e-6:
			bad.append("TOO BIG")
		if float(r["span"]) > 0.0 and float(r["span"]) < _body_r * 2.0 * MIN_SPAN_BODY_FRAC:
			bad.append("TOO SMALL")
		if float(r["energy"]) > MAX_LIGHT_ENERGY:
			bad.append("LIGHT E")
		if float(r["range"]) * 2.0 > short * MAX_LIGHT_FRAC:
			bad.append("LIGHT R")
		if not bad.is_empty():
			_fail += 1
		print("%dv%d   %-22s %6.1f  %5.1f%%  %5.1f  %6.2f  %6.1f  %s" % [
			int(r["team"]), int(r["team"]), str(r["case"]), float(r["span"]), frac * 100.0, bodies,
			float(r["energy"]), float(r["range"]), "ok" if bad.is_empty() else " ".join(bad)])
	print("")
	print("team  flash                   floor near      floor far      frame@fight     verdict")
	print("                              base   peak  x   base  peak  x   base  peak  x")
	for r in _luma_rows:
		var nr: float = float(r["near"]) / maxf(0.0001, float(r["base_near"]))
		var fr: float = float(r["far"]) / maxf(0.0001, float(r["base_far"]))
		var is_ctrl: bool = bool(r["control"])
		var bad: Array = []
		if is_ctrl:
			# Judged inverted — the calibration light MUST move both photometers.
			if fr <= MAX_FAR_LUMA_RATIO or float(r["fight_peak"]) / maxf(0.0001, float(r["fight_base"])) <= MAX_FRAME_LUMA_RATIO:
				bad.append("INSTRUMENT DEAD - photometer cannot see a board-wide light")
		else:
			if fr > MAX_FAR_LUMA_RATIO:
				bad.append("FAR - the flash relights the venue")
			if float(r["fight_peak"]) / maxf(0.0001, float(r["fight_base"])) > MAX_FRAME_LUMA_RATIO:
				bad.append("FRAME - the flash replaces the shot")
			if bool(r["check_near"]) and nr < MIN_NEAR_LUMA_RATIO:
				bad.append("NEAR - the flash does not light its own impact")
		if not bad.is_empty():
			_fail += 1
		print("%dv%d   %-22s %5.3f  %5.3f %4.2f  %5.3f %5.3f %4.2f  %5.3f %5.3f %4.2f  %s" % [
			int(r["team"]), int(r["team"]), str(r["case"]),
			float(r["base_near"]), float(r["near"]), nr,
			float(r["base_far"]), float(r["far"]), fr,
			float(r["fight_base"]), float(r["fight_peak"]),
			float(r["fight_peak"]) / maxf(0.0001, float(r["fight_base"])),
			"ok" if bad.is_empty() else " ".join(bad)])

	print("")
	print("%d checks, %d FAILING" % [_rows.size() + _luma_rows.size(), _fail])
