## BATTLE VFX — pooled one-shot particle bursts + looping cast glows, driven ENTIRELY by the
## frame/event stream (BUILD_CONTRACT §2: the renderer derives nothing; these are visual echoes
## of events the sim already emitted, never new information).
##
## Textures: 12 curated sprites from Kenney's Particle Pack (CC0 — assets/vfx/kenney/LICENSE.txt).
## ⚠️ COLOUR DISCIPLINE (docs/ART_THEME.md): effects are coloured by CHANNEL — melee amber,
## ranged steel, magic violet, support green — NEVER by team. Team identity already owns its
## colour system and Guild Colours' standing rule is that the systems must not collide.
##
## ⚠️ A POOL, NOT PER-EVENT NODES. A 5v5 lands several hits a second; allocating a
## GPUParticles3D per hit churns nodes and stutters exactly when the fight is busiest. 24
## emitters round-robin; a burst that outlives its slot's next claim is simply cut short, which
## at 0.5s lifetimes is imperceptible.
class_name BattleVfx
extends Node3D

const TEX_DIR := "res://assets/vfx/kenney/"

## Channel palette — the fourth colour system debate is settled by NOT introducing one: these are
## the same hue families the log/float text already uses for the same channels.
const CHANNEL_COLOUR := {
	"melee": Color(0.95, 0.68, 0.25),
	"ranged": Color(0.78, 0.84, 0.94),
	"magic": Color(0.72, 0.50, 0.95),
	"support": Color(0.50, 0.85, 0.60),
}

const POOL_SIZE := 24
const LIGHT_POOL := 8
const SPARK_TRAIL_POOL := 6

## ⚠️ COLOUR OVER LIFETIME IS WHAT SEPARATES "PARTICLES" FROM "FIRE" (docs/3d/particles:
## color_ramp). A flat-tinted particle is a moving decal; fire is WHITE at birth, gold in its
## prime, deep red dying and smoke at the end. Ramps below are built once and shared.
static func _ramp(points: Array) -> GradientTexture1D:
	var g := Gradient.new()
	# Set the arrays WHOLE — the add_point/remove_point dance interleaves with the Gradient's
	# two default stops and can silently delete your own first stops instead.
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for pt in points:
		offs.append(float(pt[0]))
		cols.append(pt[1])
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


static func _curve_tex(points: Array) -> CurveTexture:
	var c := Curve.new()
	for pt in points:
		c.add_point(Vector2(float(pt[0]), float(pt[1])))
	var t := CurveTexture.new()
	t.curve = c
	return t

var _pool: Array = []
var _next := 0
var _lights: Array = []
var _light_next := 0
var _spark_trails: Array = []
var _spark_next := 0

# lifetime ramps (built in _ready — static funcs, instance storage)
var RAMP_FIRE: GradientTexture1D
var RAMP_SMOKE: GradientTexture1D
var RAMP_MAGIC: GradientTexture1D
var RAMP_HEAL: GradientTexture1D
var RAMP_SPARK: GradientTexture1D
var CURVE_POP: CurveTexture     # snap in, hold, shrink — impacts
var CURVE_GROW: CurveTexture    # swell over life — smoke plumes
## Per-role finishing: which ramp/curve/turbulence a burst role gets. A role not listed keeps
## the flat tint + linear fade (some things SHOULD be simple — a dust kick is a dust kick).
var ROLE_FINISH := {}
var _textures := {}
var _cast_loops := {}   # unit index -> GPUParticles3D (looping glow while casting)

# ── flipbooks (Brackeys CC0 bundle) — ANIMATED sheets, one burst = one full play-through ──────
# name -> {file, h, v} (h × v grid). The frame counts are baked into the filenames upstream.
## `dur` is the sheet's OWN playback time — a blood splat is a snap, a frost cloud drifts.
## Callers passing dur <= 0 get the sheet's authored speed; explicit durs still win (craft pass
## 2026-08-06 — one global 0.6s made explosions sluggish and blood floaty at once).
const FLIPBOOKS := {
	"explosion": {"file": "explosion_01_8x8_clean.png", "h": 8, "v": 8, "dur": 0.45},
	"fire": {"file": "fire_01_8x8_clean.png", "h": 8, "v": 8, "dur": 0.8},  # ⚠️ the .png, not the .tga — the TGA ships with NO alpha (255 everywhere, the only sheet in the pack without it) and rendered as a plate; alpha is baked from luminance
	"smoke_wisp": {"file": "wispy_smoke_01_8x8_clean.png", "h": 8, "v": 8, "dur": 0.7},
	"big_hit": {"file": "big_hit_6x5_clean.png", "h": 6, "v": 5, "dur": 0.35},
	"impact_burst": {"file": "explosion_6x5_clean.png", "h": 6, "v": 5, "dur": 0.4},
	"fire_ring": {"file": "fire_ring_6x5_clean.png", "h": 6, "v": 5, "dur": 0.55},
	"charge": {"file": "charge_7x6_clean.png", "h": 7, "v": 6, "dur": 0.5},
	"electric_ring": {"file": "electric_ring_6x5_clean.png", "h": 6, "v": 5, "dur": 0.4},
	"lightstreaks": {"file": "lightstreaks_6x5_clean.png", "h": 6, "v": 5, "dur": 0.4},
	"blood_hit": {"file": "blood_impact_6x5_clean.png", "h": 6, "v": 5, "dur": 0.3},
	"frost_veil": {"file": "cloud_01_8x8_clean.png", "h": 8, "v": 8, "dur": 1.1},
}
const FLIPBOOK_DIR := "res://assets/vfx/flipbooks/"
var _flip_tex := {}
var _flip_pool: Array = []
var _flip_next := 0


func _ready() -> void:
	for role in ["impact", "slash", "magic", "smoke", "dust", "spark", "glow", "muzzle", "twirl", "scorch", "flare", "circle"]:
		var path: String = TEX_DIR + role + ".png"
		if ResourceLoader.exists(path):
			_textures[role] = load(path)
	# ── CUSTOM procedurally-generated textures (assets/vfx/custom, built by our own generator —
	# no licence, any palette, regenerable at any resolution). They OVERRIDE the stock sprite
	# where the custom one is simply better: a clean gaussian glow beats a photographed light
	# for auras, a 4-point flare reads sharper than a soft star for sparks, a crisp annulus
	# makes shockwaves/auras geometric instead of blobby. The rune ring is NEW — the arcane
	# circle identity nothing stock provided.
	var custom := {"glow": "soft_glow", "spark": "star4", "circle": "ring_thin",
		"magic": "rune_ring", "flare": "hard_core", "slash": "slash_arc", "impact": "bolt"}
	# Brand-new identity roles our generator created — nothing stock had these shapes.
	for extra in ["droplet", "note", "skull"]:
		var epath: String = "res://assets/vfx/custom/" + extra + ".png"
		if ResourceLoader.exists(epath):
			_textures[extra] = load(epath)
	for role in custom:
		var cpath: String = "res://assets/vfx/custom/" + str(custom[role]) + ".png"
		if ResourceLoader.exists(cpath):
			_textures[role] = load(cpath)
	for i in range(POOL_SIZE):
		_pool.append(_make_emitter())
	for nm in FLIPBOOKS:
		var fp: String = FLIPBOOK_DIR + str(FLIPBOOKS[nm]["file"])
		if ResourceLoader.exists(fp):
			_flip_tex[nm] = load(fp)
	for i in range(10):
		_flip_pool.append(_make_flip())
	# ── the quality tier's shared resources ──
	RAMP_FIRE = _ramp([[0.0, Color(1, 1, 0.9, 1)], [0.25, Color(1, 0.85, 0.4, 1)],
		[0.6, Color(1, 0.45, 0.15, 0.9)], [0.85, Color(0.5, 0.12, 0.05, 0.5)], [1.0, Color(0.1, 0.1, 0.1, 0.0)]])
	RAMP_SMOKE = _ramp([[0.0, Color(0.75, 0.73, 0.70, 0.0)], [0.2, Color(0.6, 0.58, 0.56, 0.5)],
		[0.7, Color(0.35, 0.34, 0.33, 0.35)], [1.0, Color(0.2, 0.2, 0.2, 0.0)]])
	RAMP_MAGIC = _ramp([[0.0, Color(1, 1, 1, 1)], [0.3, Color(0.72, 0.5, 0.95, 0.9)],
		[1.0, Color(0.3, 0.15, 0.5, 0.0)]])
	RAMP_HEAL = _ramp([[0.0, Color(1, 1, 1, 1)], [0.4, Color(0.5, 0.9, 0.55, 0.8)], [1.0, Color(0.3, 0.7, 0.4, 0.0)]])
	RAMP_SPARK = _ramp([[0.0, Color(1, 1, 0.95, 1)], [0.4, Color(1, 0.8, 0.4, 1)], [1.0, Color(0.9, 0.4, 0.1, 0.0)]])
	CURVE_POP = _curve_tex([[0.0, 0.2], [0.12, 1.0], [0.6, 0.85], [1.0, 0.0]])
	CURVE_GROW = _curve_tex([[0.0, 0.35], [0.6, 1.0], [1.0, 1.25]])
	ROLE_FINISH = {
		"smoke": {"ramp": RAMP_SMOKE, "curve": CURVE_GROW, "turb": 0.35, "grav": Vector3(0, 1.8, 0)},
		"flare": {"ramp": RAMP_FIRE, "curve": CURVE_POP, "turb": 0.2},
		"spark": {"ramp": RAMP_SPARK, "curve": CURVE_POP},
		"magic": {"ramp": RAMP_MAGIC, "curve": CURVE_POP, "turb": 0.3},
		"glow": {"curve": CURVE_POP, "turb": 0.15},
		"impact": {"curve": CURVE_POP},
		"slash": {"curve": CURVE_POP},
	}
	for i in range(LIGHT_POOL):
		var li := OmniLight3D.new()
		li.light_energy = 0.0
		li.omni_range = 14.0
		li.shadow_enabled = false   # 8 shadowless omnis is cheap in Forward+; shadows are not
		add_child(li)
		_lights.append(li)
	for i in range(SPARK_TRAIL_POOL):
		_spark_trails.append(_make_spark_trail())


## Ribbon-trailed sparks (docs/3d/particles/trails): trail_enabled on the NODE, RibbonTrailMesh
## as the draw pass, use_particle_trails on the material. The debris streaks every real
## explosion has — the single biggest "pro" tell in particle work.
func _make_spark_trail() -> GPUParticles3D:
	var pt := GPUParticles3D.new()
	pt.one_shot = true
	pt.emitting = false
	pt.amount = 10
	pt.lifetime = 0.55
	pt.explosiveness = 1.0
	pt.trail_enabled = true
	pt.trail_lifetime = 0.18
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 80.0
	mat.initial_velocity_min = 10.0
	mat.initial_velocity_max = 22.0
	mat.gravity = Vector3(0, -22.0, 0)
	mat.damping_min = 4.0
	mat.damping_max = 8.0
	mat.scale_min = 0.10
	mat.scale_max = 0.22
	mat.color_ramp = RAMP_SPARK
	pt.process_material = mat
	var rm := RibbonTrailMesh.new()
	rm.size = 0.28
	rm.sections = 5
	rm.section_length = 0.04
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.use_particle_trails = true
	rm.material = m
	pt.draw_pass_1 = rm
	add_child(pt)
	return pt


func spark_trails(pos: Vector3, size: float = 1.0) -> void:
	var pt: GPUParticles3D = _spark_trails[_spark_next]
	_spark_next = (_spark_next + 1) % SPARK_TRAIL_POOL
	pt.emitting = false
	pt.position = pos
	var mat: ParticleProcessMaterial = pt.process_material
	mat.initial_velocity_min = 10.0 * size
	mat.initial_velocity_max = 22.0 * size
	pt.restart()
	pt.emitting = true


## A pooled light flash — the cheapest one-line upgrade in 3D VFX: an explosion that does not
## LIGHT the arena floor reads as a sticker on the screen.
func light_flash(pos: Vector3, color: Color, energy: float = 5.0, dur: float = 0.35) -> void:
	var li: OmniLight3D = _lights[_light_next]
	_light_next = (_light_next + 1) % LIGHT_POOL
	li.position = pos + Vector3(0, 2.0, 0)
	li.light_color = color
	li.light_energy = energy
	var tw := create_tween()
	tw.tween_property(li, "light_energy", 0.0, dur).set_ease(Tween.EASE_OUT)


## THE LAYERED EXPLOSION — flash, fire sheet, trailed debris, turbulent smoke plume, ground
## light. Five layers at five timescales is what makes it read as an EVENT, not an effect.
func explosion_pro(pos: Vector3, size: float = 1.0) -> void:
	light_flash(pos, Color(1.0, 0.65, 0.3), 6.0 * size, 0.3)
	flip(pos, "explosion", 5.0 * size, Color.WHITE)
	spark_trails(pos, size)
	burst(pos + Vector3(0, 1.0, 0), "smoke", Color.WHITE, 1.4 * size, 10)


func _make_emitter() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 12
	p.lifetime = 0.5
	p.explosiveness = 1.0
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 60.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 5.0
	mat.gravity = Vector3(0, -3.0, 0)
	mat.scale_min = 0.6
	mat.scale_max = 1.4
	# Craft pass: random spin and a whisper of hue drift, so the same burst fired twice never
	# reads as a stamped copy. Render-side randomness only — the sim's determinism is untouched.
	mat.angle_min = 0.0
	mat.angle_max = 360.0
	mat.hue_variation_min = -0.03
	mat.hue_variation_max = 0.03
	# Fade out over life — a particle that pops out of existence reads as a glitch.
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	curve.curve = c
	mat.alpha_curve = curve
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD   # additive: light, not paint — reads on any ground
	quad.material = m
	p.draw_pass_1 = quad
	add_child(p)
	return p


## A flipbook player: GPUParticles3D with ONE particle whose lifetime spans exactly one
## play-through of the sheet — the standard Godot flipbook idiom (particles_anim_* on the
## material, anim speed 1, loop off). One burst = the whole animation, billboarded.
func _make_flip() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 1
	p.lifetime = 0.6
	p.explosiveness = 1.0
	var mat := ParticleProcessMaterial.new()
	mat.gravity = Vector3.ZERO
	mat.anim_speed_min = 1.0
	mat.anim_speed_max = 1.0
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(4.0, 4.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.particles_anim_loop = false
	quad.material = m
	p.draw_pass_1 = quad
	add_child(p)
	return p


## Play one animated sheet at a position. `size` is world height of the billboard.
func flip(pos: Vector3, book: String, size: float = 4.0, tint: Color = Color.WHITE, dur: float = 0.0) -> void:
	if not _flip_tex.has(book):
		return
	var spec: Dictionary = FLIPBOOKS[book]
	if dur <= 0.0:
		dur = float(spec.get("dur", 0.5))
	var p: GPUParticles3D = _flip_pool[_flip_next]
	_flip_next = (_flip_next + 1) % _flip_pool.size()
	p.emitting = false
	p.position = pos
	p.lifetime = dur
	var quad: QuadMesh = p.draw_pass_1
	quad.size = Vector2(size, size) * _oomph
	var m: StandardMaterial3D = quad.material
	m.albedo_texture = _flip_tex[book]
	m.particles_anim_h_frames = int(spec["h"])
	m.particles_anim_v_frames = int(spec["v"])
	(p.process_material as ParticleProcessMaterial).color = tint
	p.restart()
	p.emitting = true


## One-shot burst. `role` picks the sprite, `color` tints it (channel palette above), `size`
## scales both sprite and spray, `count` the particle amount.
func burst(pos: Vector3, role: String, color: Color, size: float = 1.0, count: int = 12) -> void:
	var p: GPUParticles3D = _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.emitting = false
	p.position = pos
	p.amount = count
	size *= _oomph
	var mat: ParticleProcessMaterial = p.process_material
	mat.color = color
	mat.scale_min = 0.6 * size
	mat.scale_max = 1.4 * size
	mat.initial_velocity_min = 2.0 * size
	mat.initial_velocity_max = 5.0 * size
	# ── role finishing (the quality tier): ramp + curve + turbulence per role. Reset first —
	# pooled emitters carry the previous burst's finish otherwise, and a smoke ramp on a slash
	# is exactly the kind of once-a-minute wrongness nobody can reproduce. ──
	var fin: Dictionary = ROLE_FINISH.get(role, {})
	mat.color_ramp = fin.get("ramp")
	mat.scale_curve = fin.get("curve")
	mat.turbulence_enabled = fin.has("turb")
	if fin.has("turb"):
		mat.turbulence_noise_strength = float(fin["turb"]) * 4.0
	mat.gravity = fin.get("grav", Vector3(0, -3.0, 0))
	var quad: QuadMesh = p.draw_pass_1
	(quad.material as StandardMaterial3D).albedo_texture = _textures.get(role)
	p.restart()
	p.emitting = true


## Looping glow at a unit's feet while it casts — the windup telegraph, visible from any camera.
## Keyed by unit index; safe to call every frame (idempotent).
func cast_glow(idx: int, holder: Node3D, color: Color) -> void:
	if _cast_loops.has(idx):
		(_cast_loops[idx] as GPUParticles3D).position = holder.position + Vector3(0, 0.3, 0)
		return
	var p := _make_emitter()
	p.one_shot = false
	p.amount = 8
	p.lifetime = 0.7
	p.explosiveness = 0.0
	var mat: ParticleProcessMaterial = p.process_material
	mat.color = color
	mat.gravity = Vector3(0, 2.0, 0)   # rises — gathering power, not falling debris
	mat.initial_velocity_min = 0.5
	mat.initial_velocity_max = 1.2
	mat.scale_min = 0.5
	mat.scale_max = 0.9
	# Quality tier: the gathering swirls — ring emission + tangential acceleration is the
	# classic "power converging" motion, and the magic ramp fades it white → violet → nothing.
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_axis = Vector3(0, 1, 0)
	mat.emission_ring_radius = 2.0
	mat.emission_ring_inner_radius = 1.2
	mat.emission_ring_height = 0.2
	mat.tangential_accel_min = 6.0
	mat.tangential_accel_max = 9.0
	mat.color_ramp = RAMP_MAGIC
	mat.turbulence_enabled = true
	mat.turbulence_noise_strength = 0.6
	(p.draw_pass_1.material as StandardMaterial3D).albedo_texture = _textures.get("magic")
	p.position = holder.position + Vector3(0, 0.3, 0)
	p.emitting = true
	_cast_loops[idx] = p


func end_cast_glow(idx: int) -> void:
	if not _cast_loops.has(idx):
		return
	var p: GPUParticles3D = _cast_loops[idx]
	_cast_loops.erase(idx)
	p.emitting = false
	# Let live particles fade before the node goes.
	get_tree().create_timer(1.0).timeout.connect(func(): if is_instance_valid(p): p.queue_free())


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# PLAY_ABILITY — the docs/VFX_ABILITY_MAP.md engine. One entry point: given the MOVE (the sim's
# own dict), the caster/victim positions and the hit outcome, play the mapped recipe.
# ⚠️ Mirrors the map's rule cascade EXACTLY: name override → line flavour → type/channel rules.
# When the map and this dispatch disagree, the map is the spec — fix HERE.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

const STATUS_TINT := {
	"poison": Color(0.55, 0.80, 0.35), "burn": Color(1.0, 0.55, 0.2), "bleed": Color(0.65, 0.15, 0.15),
	"stun": Color(0.95, 0.85, 0.45), "sleep": Color(0.75, 0.65, 0.90), "fear": Color(0.60, 0.40, 0.85),
	"confusion": Color(0.90, 0.55, 0.75), "blind": Color(0.6, 0.6, 0.65), "silence": Color(0.6, 0.75, 0.9),
	"charm": Color(0.95, 0.60, 0.70), "doom": Color(0.35, 0.20, 0.45), "haste": Color(1.0, 0.95, 0.75),
	"vulnerable": Color(0.95, 0.6, 0.3), "healblock": Color(0.55, 0.5, 0.45), "knockback": Color(0.75, 0.68, 0.55),
}

## Name overrides — the hand-authored fits from the map.
const ABILITY_OVR := {
	"Static Chain": "chain_lightning",
	"Inferno": "ring_explosions", "Cinderburst": "explosion_scorch", "Detonate": "explosion_scorch",
	"Chain Lightning": "chain_lightning", "Blizzard": "frost_field", "Lullaby": "sleep_rings",
	"Mass Hysteria": "debuff_storm", "Sonic Boom": "shockwave", "Body Slam": "stomp",
	"Quagmire Stomp": "stomp", "Overrun": "stomp", "Deadeye": "beam", "Piercing Shot": "beam",
	"Blood Price": "blood_price", "Twist the Knife": "blood", "Bloodletter": "blood",
	"Executioner": "execute_hit", "Doom": "doom_mark", "Arcane Aegis": "ward",
	"Hymn of Shields": "ward", "Bravura": "ward", "Siphon Soul": "siphon", "Mana Burn": "siphon",
	"Life Drain": "siphon", "Taunt": "taunt_ring", "Challenge": "taunt_ring",
	"Bulwark's Challenge": "taunt_ring",
}

const LINE_FLAVOUR := {"Assassin": "shadow_knife", "Venomcraft": "venom", "Siphon": "siphon"}


func _tint_of(mv: Dictionary) -> Color:
	var st = mv.get("status")
	if st is Dictionary and STATUS_TINT.has(str(st.get("kind", ""))):
		return STATUS_TINT[str(st.get("kind", ""))]
	return Color.WHITE


var _oomph := 1.0   # transient effect-size multiplier set per play_ability call (game feel)

func play_ability(mv: Dictionary, caster: Vector3, victim: Vector3, crit: bool, oomph: float = 1.0) -> void:
	_oomph = clampf(oomph, 0.5, 2.5)
	var mv_name := str(mv.get("name", ""))
	var recipe: String = ABILITY_OVR.get(mv_name, "")
	if recipe == "" and LINE_FLAVOUR.has(str(mv.get("line", ""))) and str(mv.get("type", "")) == "damage":
		recipe = LINE_FLAVOUR[str(mv.get("line", ""))]
	if recipe == "":
		recipe = _rule_recipe(mv)
	var tint := _tint_of(mv)
	match recipe:
		"ring_explosions":
			flip(victim, "fire_ring", 7.0, Color.WHITE, 0.6)
			explosion_pro(victim + Vector3(0, 1.5, 0), 1.1)
		"explosion_scorch":
			explosion_pro(victim, 1.2)
			burst(victim, "scorch", Color(0.9, 0.45, 0.2), 1.2, 6)
		"chain_lightning":
			lightning(caster + Vector3(0, 3.0, 0), victim + Vector3(0, 3.0, 0))
			static_ring(victim, 3.5)
		"frost_field":
			flip(victim, "frost_veil", 8.0, Color(0.8, 0.9, 1.0), 0.9)
		"sleep_rings":
			burst(victim + Vector3(0, 2.5, 0), "note", STATUS_TINT["sleep"], 1.0, 8)
		"debuff_storm":
			burst(victim + Vector3(0, 2.0, 0), "smoke", STATUS_TINT["fear"], 1.3, 12)
			burst(caster + Vector3(0, 2.0, 0), "twirl", STATUS_TINT["fear"], 1.2, 8)
		"shockwave":
			shockwave(victim, 9.0, Color(0.9, 0.9, 0.95))
			burst(victim, "dust", Color(0.75, 0.68, 0.55), 1.4, 10)
		"stomp":
			shockwave(victim, 7.0)
			burst(victim, "dust", Color(0.75, 0.68, 0.55), 1.8, 16)
			flip(victim + Vector3(0, 1.0, 0), "big_hit", 5.0, Color.WHITE, 0.45)
		"beam":
			_beam_line(caster, victim, Color(0.95, 0.95, 0.8))
			burst(victim, "impact", Color(0.95, 0.95, 0.8), 1.1, 8)
		"blood_price":
			flip(caster + Vector3(0, 2.0, 0), "blood_hit", 3.5, Color.WHITE, 0.45)
			burst(victim, "slash", CHANNEL_COLOUR["melee"], 1.2, 10)
		"blood":
			flip(victim + Vector3(0, 2.0, 0), "blood_hit", 4.5, Color.WHITE, 0.5)
		"execute_hit":
			flip(victim + Vector3(0, 1.5, 0), "big_hit", 6.0, Color.WHITE, 0.5)
			flip(victim + Vector3(0, 2.0, 0), "blood_hit", 4.0, Color.WHITE, 0.5)
		"doom_mark":
			# Reskin (AD): Doom is a FORFEIT BRAND, not a violet skull — iron-orange mark + the
			# scorch of the iron. The skull shape stays (it reads at 16px); the palette is the
			# guild's, and the tether it pairs with is the same iron.
			burst(victim + Vector3(0, 3.0, 0), "skull", Color(0.92, 0.42, 0.16), 1.8, 4)
			burst(victim, "scorch", Color(0.6, 0.28, 0.1), 1.0, 5)
			doom_tether(caster + Vector3(0, 3.0, 0), victim + Vector3(0, 3.0, 0))
		"ward":
			# Reskin (AD): wards shimmer BRASS — riveted guild plate, not a sci-fi energy dome.
			ward_dome(victim, Color(0.85, 0.72, 0.42))
		"siphon":
			# Reskin (AD): drains read as a TAUT LEASH — rope-tan base, the craftsman's tool, not
			# an energy beam. Mana Burn keeps a steel-blue cast (it drinks the pool, not the body).
			var stint := Color(0.78, 0.62, 0.40)
			match mv_name:
				"Mana Burn": stint = Color(0.55, 0.66, 0.82)
			siphon_beam(victim + Vector3(0, 3.0, 0), caster + Vector3(0, 3.0, 0), stint)
		"taunt_ring":
			static_ring(caster, 4.0, Color(0.92, 0.55, 0.30), 0.7)
		"shadow_knife":
			flip(victim + Vector3(0, 1.5, 0), "smoke_wisp", 4.0, Color(0.3, 0.25, 0.4), 0.5)
			burst(victim, "slash", Color(0.55, 0.45, 0.75), 1.2, 10)
		"venom":
			burst(victim, "droplet", STATUS_TINT["poison"], 1.1, 10)
			burst(victim, "smoke", STATUS_TINT["poison"], 1.0, 6)
		"aura_buff":
			aura_pulse(victim, tint if tint != Color.WHITE else CHANNEL_COLOUR["support"])
			flip(caster + Vector3(0, 2.0, 0), "charge", 4.5, Color(0.85, 0.95, 0.85), 0.5)
		"heal":
			heal_rise(victim)
			aura_pulse(victim, CHANNEL_COLOUR["support"])
		"control":
			static_ring(victim, 3.2, tint if tint != Color.WHITE else Color(0.75, 0.85, 1.0))
		"debuff":
			burst(victim + Vector3(0, 2.5, 0), "smoke", tint if tint != Color.WHITE else Color(0.6, 0.5, 0.7), 1.1, 10)
			burst(caster + Vector3(0, 2.0, 0), "twirl", tint, 0.9, 6)
		"magic_hit":
			explosion_pro(victim + Vector3(0, 1.5, 0), 1.25 if crit else 1.0)
		"ranged_hit":
			burst(victim, "impact", CHANNEL_COLOUR["ranged"], 1.2 if crit else 1.0, 10)
		"voice_hit":
			burst(victim + Vector3(0, 2.0, 0), "circle", tint if tint != Color.WHITE else Color(0.9, 0.8, 0.9), 1.8, 8)
		_:
			burst(victim, "slash", CHANNEL_COLOUR["melee"], 1.2 if crit else 1.0, 10)
	if crit:
		burst(victim, "spark", Color(1.0, 0.9, 0.5), 1.3, 10)
	_oomph = 1.0


func _rule_recipe(mv: Dictionary) -> String:
	var t := str(mv.get("type", "damage"))
	var tgt := str(mv.get("target", "enemy"))
	var ch := str(mv.get("channel", "melee"))
	if t == "buff" or tgt in ["ally", "team", "self"]:
		var e = mv.get("effects")
		if e is Dictionary and (e as Dictionary).has("hpRegenBuff"):
			return "heal"
		return "aura_buff"
	if t == "control":
		return "control"
	if t == "debuff":
		return "debuff"
	if ch == "magic":
		return "magic_hit"
	if ch == "ranged":
		return "ranged_hit"
	if ch == "voice":
		return "voice_hit"
	return "melee_hit"


## THE BUFF GRAMMAR (user direction 2026-08-06): a channel-coloured ring pulses under the
## affected monster for ~1s. Called once per affected unit — the sim's buff events arrive per
## unit, so a team buff naturally rings everyone it touched, and ONLY them.
func aura_pulse(pos: Vector3, color: Color) -> void:
	var p: GPUParticles3D = _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.emitting = false
	p.position = pos + Vector3(0, 0.25, 0)
	p.amount = 14
	p.lifetime = 1.0
	var mat: ParticleProcessMaterial = p.process_material
	mat.color = color
	mat.gravity = Vector3(0, 0.8, 0)
	mat.initial_velocity_min = 0.2
	mat.initial_velocity_max = 0.6
	mat.scale_min = 0.5
	mat.scale_max = 1.0
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	mat.emission_ring_axis = Vector3(0, 1, 0)
	mat.emission_ring_radius = 2.2
	mat.emission_ring_inner_radius = 1.8
	mat.emission_ring_height = 0.1
	(p.draw_pass_1.material as StandardMaterial3D).albedo_texture = _textures.get("glow")
	p.restart()
	p.emitting = true


func heal_rise(pos: Vector3) -> void:
	# Quality tier: heal uses the HEAL ramp via the magic role slot — white sparks that green as
	# they rise, with a soft light so the mend illuminates the healed.
	burst(pos + Vector3(0, 1.0, 0), "spark", Color(0.5, 0.9, 0.55), 1.0, 12)
	light_flash(pos, Color(0.5, 0.9, 0.55), 2.2, 0.5)


func ward_dome(pos: Vector3, color: Color) -> void:
	# Quality tier: a real fresnel hemisphere wrapping the body, with the ring pulse as accent.
	dome(pos, color)
	burst(pos + Vector3(0, 2.0, 0), "circle", color, 1.4, 6)


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# SHADER LIGHTNING — the pure-procedural tier. No texture, no sheet: fbm noise displaces a
# centreline, STEPPED in time so the bolt re-strikes (real lightning is a sequence of strokes,
# not a shape), pinned at both endpoints, hot core + soft glow, additive. Two crossed quads so
# it reads from every camera angle without axis-billboard maths.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

const LIGHTNING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.75, 0.85, 1.0, 1.0);
uniform float seed_p;
uniform float life : hint_range(0.0, 1.0) = 0.0;

float hash_f(float n) { return fract(sin(n) * 43758.5453); }
float noise_f(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash_f(i), hash_f(i + 1.0), f);
}
float fbm(float x) {
	return 0.5 * noise_f(x) + 0.3 * noise_f(x * 2.7) + 0.2 * noise_f(x * 6.1);
}

void fragment() {
	float u = UV.x;
	float v = UV.y - 0.5;
	// Re-strike: the jag pattern jumps 24x/second — a sequence of strokes, never a static shape.
	float stroke = floor(TIME * 24.0);
	float pin = sin(u * 3.14159);   // displacement pinned to zero at both endpoints
	float jag = (fbm(u * 7.0 + seed_p + stroke * 13.7) - 0.5) * 0.55 * pin;
	float d = abs(v - jag);
	// A thinner secondary branch, offset pattern, only over the middle of the span.
	float jag2 = (fbm(u * 11.0 + seed_p * 1.7 + stroke * 7.3) - 0.5) * 0.7 * pin;
	float d2 = abs(v - jag2);
	float mid = smoothstep(0.15, 0.35, u) * (1.0 - smoothstep(0.65, 0.9, u));
	float core = exp(-d * 130.0) + exp(-d2 * 170.0) * 0.5 * mid;
	float glow = exp(-d * 16.0) * 0.30;
	float flicker = 0.7 + 0.3 * hash_f(stroke + seed_p);
	float fade = (1.0 - life) * (1.0 - life);
	vec3 col = tint.rgb * (core * 2.4 + glow) * flicker * fade;
	ALBEDO = col;
	ALPHA = clamp((core + glow) * fade, 0.0, 1.0);
}
"""
var _lightning_shader: Shader
var _siphon_shader: Shader
var _static_ring_shader: Shader
var _tether_shader: Shader
var _shockwave_shader: Shader
var _dome_shader: Shader

## DOOM TETHER — the beam family's dark sibling: slow, heavy, pulsing. The pulses travel
## from CASTER to VICTIM (the curse being fed), the inverse of the siphon's theft direction.
## ⚠️ Additive black is invisible — doom's "darkness" is carried by a bright violet core with
## slow dread-pulses, not by dark pixels.
const TETHER_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.55, 0.25, 0.85, 1.0);
uniform float life : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float u = UV.x;
	float v = UV.y - 0.5;
	float pin = sin(u * 3.14159);
	float wave = sin(u * 4.0 + TIME * 1.6) * 0.10 * pin;   // slow — a chain, not a current
	float d = abs(v - wave);
	float core = exp(-d * 80.0);
	float glow = exp(-d * 12.0) * 0.35;
	// Dread pulses: slow, travelling TOWARD the victim (u = 1).
	float pulse = 0.5 + 0.5 * sin(u * 10.0 - TIME * 5.0);
	float fade = sin(clamp(life, 0.0, 1.0) * 3.14159);
	vec3 col = tint.rgb * (core * 1.6 * (0.6 + 0.4 * pulse) + glow) * fade;
	ALBEDO = col;
	ALPHA = clamp((core + glow) * fade, 0.0, 1.0);
}
"""

## SHOCKWAVE — a clean expanding pressure ring on the ground. No jitter (a pressure wave is
## smooth where electricity crawls); the ring expands over its life and thins as it goes.
const SHOCKWAVE_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.9, 0.85, 0.75, 1.0);
uniform float life : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 pnt = UV * 2.0 - 1.0;
	float r = length(pnt);
	float ring_r = mix(0.08, 0.95, life);
	float thick = mix(60.0, 160.0, life);    // thins as it expands
	float d = abs(r - ring_r);
	float ring = exp(-d * d * thick * 4.0);
	float fade = 1.0 - life * life;
	vec3 col = tint.rgb * ring * 1.8 * fade;
	ALBEDO = col;
	ALPHA = clamp(ring * fade, 0.0, 1.0);
}
"""

## WARD DOME — a fresnel hemisphere shell: bright at the rim, near-transparent face-on, with a
## slow shimmer. The classic shield read, and it wraps the WHOLE monster rather than floating
## as a sprite above it.
const DOME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.72, 0.5, 0.95, 1.0);
uniform float life : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	float shimmer = 0.5 + 0.5 * sin(UV.x * 40.0 + UV.y * 26.0 + TIME * 3.0);
	float fade = sin(clamp(life, 0.0, 1.0) * 3.14159);
	vec3 col = tint.rgb * (fres * 1.6 + 0.12 + shimmer * 0.10) * fade;
	ALBEDO = col;
	ALPHA = clamp((fres * 0.8 + 0.10 + shimmer * 0.06) * fade, 0.0, 1.0);
}
"""


## The curse being fed: caster → victim, slow and heavy, ~1.2s.
func doom_tether(from: Vector3, to: Vector3, dur: float = 1.2) -> void:
	if _tether_shader == null:
		_tether_shader = Shader.new()
		_tether_shader.code = TETHER_SHADER
	# Guild Colours reskin (AD): the violet "curse" is now a BRANDING-IRON tether — iron-orange,
	# a forfeit-seal being applied, not a wizard's hex. Same shader, honest metaphor.
	_beam_rig(_tether_shader, Color(0.92, 0.42, 0.16), from, to, 2.4, dur)


## Expanding ground pressure ring — stomps, slams, sonic booms.
func shockwave(pos: Vector3, radius: float = 8.0, tint: Color = Color(0.9, 0.85, 0.75), dur: float = 0.45) -> void:
	if _shockwave_shader == null:
		_shockwave_shader = Shader.new()
		_shockwave_shader.code = SHOCKWAVE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shockwave_shader
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("life", 0.0)
	var mi := MeshInstance3D.new()
	var qm := PlaneMesh.new()
	qm.size = Vector2(radius * 2.0, radius * 2.0)
	qm.material = mat
	mi.mesh = qm
	mi.position = pos + Vector3(0, 0.18, 0)
	add_child(mi)
	var tw := create_tween()
	tw.tween_method(func(x): mat.set_shader_parameter("life", x), 0.0, 1.0, dur)
	tw.tween_callback(mi.queue_free)


## The shield shell around a body. Fades in, shimmers, fades out.
func dome(pos: Vector3, tint: Color = Color(0.72, 0.5, 0.95), size: float = 4.5, dur: float = 0.9) -> void:
	if _dome_shader == null:
		_dome_shader = Shader.new()
		_dome_shader.code = DOME_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _dome_shader
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("life", 0.0)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = size
	sm.height = size * 1.6
	sm.is_hemisphere = true
	sm.material = mat
	mi.mesh = sm
	mi.position = pos
	add_child(mi)
	var tw := create_tween()
	tw.tween_method(func(x): mat.set_shader_parameter("life", x), 0.0, 1.0, dur)
	tw.tween_callback(mi.queue_free)


## Shared crossed-quad rig for every beam-family shader (lightning built its own before this
## existed; tether and future beams use this).
func _beam_rig(shader: Shader, tint: Color, from: Vector3, to: Vector3, width: float, dur: float) -> void:
	var seg := to - from
	var length := seg.length()
	if length < 0.5:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("life", 0.0)
	var holder := Node3D.new()
	holder.position = (from + to) * 0.5
	var bx := seg.normalized()
	var up := Vector3.UP if absf(bx.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var bz := bx.cross(up).normalized()
	holder.basis = Basis(bx, bz.cross(bx).normalized(), bz)
	for flip_i in range(2):
		var mi := MeshInstance3D.new()
		var qm := PlaneMesh.new()
		qm.size = Vector2(length, width)
		qm.orientation = PlaneMesh.FACE_Z
		qm.material = mat
		mi.mesh = qm
		if flip_i == 1:
			mi.rotate_x(PI * 0.5)
		holder.add_child(mi)
	add_child(holder)
	var tw := create_tween()
	tw.tween_method(func(x): mat.set_shader_parameter("life", x), 0.0, 1.0, dur)
	tw.tween_callback(holder.queue_free)

## SIPHON BEAM — the drain grammar as a shader. Unlike lightning it is SMOOTH: a gently waving
## line with brightness pulses FLOWING along it toward the drinker (u=1 is the caster; pulses
## travel +u, so the direction of theft is readable at a glance). Same crossed-quad rig.
const SIPHON_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.55, 0.85, 0.55, 1.0);
uniform float life : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float u = UV.x;
	float v = UV.y - 0.5;
	float pin = sin(u * 3.14159);
	// A slow, organic wave — a drain is a flow, not a strike.
	float wave = sin(u * 7.0 - TIME * 5.0) * 0.16 * pin
		+ sin(u * 13.0 - TIME * 8.3) * 0.06 * pin;
	float d = abs(v - wave);
	float core = exp(-d * 90.0);
	float glow = exp(-d * 14.0) * 0.3;
	// The theft made visible: pulses of brightness travelling toward u = 1 (the caster).
	float pulse = 0.55 + 0.45 * sin(u * 24.0 - TIME * 16.0);
	float fade = sin(clamp(life, 0.0, 1.0) * 3.14159);   // ease in AND out — a flow, not a pop
	vec3 col = tint.rgb * (core * 1.8 * pulse + glow) * fade;
	ALBEDO = col;
	ALPHA = clamp((core + glow) * fade, 0.0, 1.0);
}
"""

## STATIC FIELD RING — a flat ground annulus whose radius jitters with fbm noise around the
## circumference, re-striking in steps like the bolt. Electricity crawling in a circle.
const STATIC_RING_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.75, 0.85, 1.0, 1.0);
uniform float life : hint_range(0.0, 1.0) = 0.0;

float hash_f(float n) { return fract(sin(n) * 43758.5453); }
float noise_f(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash_f(i), hash_f(i + 1.0), f);
}

void fragment() {
	vec2 pnt = UV * 2.0 - 1.0;
	float r = length(pnt);
	float ang = atan(pnt.y, pnt.x);
	float stroke = floor(TIME * 20.0);
	// The ring's radius crawls: fbm around the circumference, re-struck per stroke. The +6.2832
	// sample keeps the seam at ang = PI from snapping (noise is not periodic; blending two
	// samples across the wrap hides the joint).
	float n1 = noise_f(ang * 3.0 + stroke * 11.3);
	float n2 = noise_f((ang + 6.2832) * 3.0 + stroke * 11.3);
	float blend = smoothstep(2.6, 3.14159, abs(ang));
	float jit = mix(n1, n2, blend) - 0.5;
	float ring_r = 0.72 + jit * 0.12;
	float d = abs(r - ring_r);
	float core = exp(-d * 60.0);
	float glow = exp(-d * 14.0) * 0.35;
	// Travelling sparks: three bright points orbiting the ring.
	float spark = 0.0;
	for (int i = 0; i < 3; i++) {
		float sa = TIME * (2.0 + float(i) * 0.7) + float(i) * 2.1;
		float ad = abs(mod(ang - sa + 3.14159, 6.2832) - 3.14159);
		spark += exp(-ad * 14.0) * exp(-d * 30.0);
	}
	float flicker = 0.75 + 0.25 * hash_f(stroke);
	float fade = sin(clamp(life, 0.0, 1.0) * 3.14159);
	vec3 col = tint.rgb * (core * 1.6 + glow + spark * 1.8) * flicker * fade;
	ALBEDO = col;
	ALPHA = clamp((core + glow + spark) * fade, 0.0, 1.0);
}
"""


## Flowing drain beam, victim → caster. Fire-and-forget, ~0.6s.
func siphon_beam(from: Vector3, to: Vector3, tint: Color = Color(0.55, 0.85, 0.55), dur: float = 0.6) -> void:
	if _siphon_shader == null:
		_siphon_shader = Shader.new()
		_siphon_shader.code = SIPHON_SHADER
	var seg := to - from
	var length := seg.length()
	if length < 0.5:
		return
	var mat := ShaderMaterial.new()
	mat.shader = _siphon_shader
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("life", 0.0)
	var holder := Node3D.new()
	holder.position = (from + to) * 0.5
	var bx := seg.normalized()
	var up := Vector3.UP if absf(bx.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var bz := bx.cross(up).normalized()
	holder.basis = Basis(bx, bz.cross(bx).normalized(), bz)
	for flip_i in range(2):
		var mi := MeshInstance3D.new()
		var qm := PlaneMesh.new()
		qm.size = Vector2(length, 2.6)
		qm.orientation = PlaneMesh.FACE_Z
		qm.material = mat
		mi.mesh = qm
		if flip_i == 1:
			mi.rotate_x(PI * 0.5)
		holder.add_child(mi)
	add_child(holder)
	var tw := create_tween()
	tw.tween_method(func(x): mat.set_shader_parameter("life", x), 0.0, 1.0, dur)
	tw.tween_callback(holder.queue_free)


## Electric ring crawling on the ground at `radius`. Fire-and-forget.
func static_ring(pos: Vector3, radius: float = 6.0, tint: Color = Color(0.75, 0.85, 1.0), dur: float = 0.6) -> void:
	if _static_ring_shader == null:
		_static_ring_shader = Shader.new()
		_static_ring_shader.code = STATIC_RING_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _static_ring_shader
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("life", 0.0)
	var mi := MeshInstance3D.new()
	var qm := PlaneMesh.new()
	qm.size = Vector2(radius * 2.8, radius * 2.8)   # the annulus sits at 0.72 of the quad half-size
	qm.material = mat
	mi.mesh = qm
	mi.position = pos + Vector3(0, 0.2, 0)
	add_child(mi)
	var tw := create_tween()
	tw.tween_method(func(x): mat.set_shader_parameter("life", x), 0.0, 1.0, dur)
	tw.tween_callback(mi.queue_free)

## An animated bolt from `from` to `to`. Builds two crossed quads along the segment, tweens the
## `life` uniform over `dur`, frees itself. Fire-and-forget.
func lightning(from: Vector3, to: Vector3, tint: Color = Color(0.75, 0.85, 1.0), dur: float = 0.4) -> void:
	if _lightning_shader == null:
		_lightning_shader = Shader.new()
		_lightning_shader.code = LIGHTNING_SHADER
	var seg := to - from
	var length := seg.length()
	if length < 0.5:
		return
	var mat := ShaderMaterial.new()
	mat.shader = _lightning_shader
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("seed_p", fposmod(from.x + to.z, 100.0))
	mat.set_shader_parameter("life", 0.0)
	var holder := Node3D.new()
	holder.position = (from + to) * 0.5
	# Orient the holder's X axis along the segment; two quads crossed at 90° around it.
	var basis_x := seg.normalized()
	var up := Vector3.UP if absf(basis_x.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var basis_z := basis_x.cross(up).normalized()
	var basis_y := basis_z.cross(basis_x).normalized()
	holder.basis = Basis(basis_x, basis_y, basis_z)
	for flip_i in range(2):
		var mi := MeshInstance3D.new()
		var qm := PlaneMesh.new()
		qm.size = Vector2(length, 3.2)
		qm.orientation = PlaneMesh.FACE_Z
		qm.material = mat
		mi.mesh = qm
		if flip_i == 1:
			mi.rotate_x(PI * 0.5)
		holder.add_child(mi)
	add_child(holder)
	var tw := create_tween()
	tw.tween_method(func(x): mat.set_shader_parameter("life", x), 0.0, 1.0, dur)
	tw.tween_callback(holder.queue_free)
	light_flash((from + to) * 0.5, tint, 3.0, dur * 0.8)


## A line of small bursts marching caster→victim — beams, chains and siphons without an oriented
## mesh (a billboard flipbook cannot lie along a 3D line; a particle march reads as one).
func _beam_line(from: Vector3, to: Vector3, color: Color) -> void:
	var steps: int = clampi(int(from.distance_to(to) / 4.0), 3, 8)
	for i in range(steps):
		var t := float(i) / float(maxi(1, steps - 1))
		burst(from.lerp(to, t) + Vector3(0, 1.5, 0), "spark", color, 0.8, 4)
