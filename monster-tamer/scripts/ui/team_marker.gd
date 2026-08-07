## TEAM IDENTITY, ATTACHED IN-ENGINE — never generated into the model.
##
## ⚠️ WHY THIS EXISTS. `ART_BIBLE_GUILD_COLOURS.md` makes the diagonal chest sash the TEAM-COLOUR
## CARRIER: the one element tinted per team at runtime, deliberately kept OFF the creature's body
## so that "saturated means something is HAPPENING, muted means this is WHO YOU PLAY FOR" holds.
##
## `docs/LOWPOLY_MODEL_SPEC.md` measured the problem: the generated model returned a sash the SAME
## WHITE as the singlet — not a separable region, so it could not be tinted without recolouring the
## whole kit and putting team colour on the uniform, which is the exact collision the palette
## discipline exists to prevent.
##
## ⚠️ THE FIX IS TO STOP ASKING THE GENERATOR FOR IT. Team identity attached here is guaranteed
## tintable, identical across every creature, and costs nothing per model — so every future
## creature inherits it for free instead of depending on a prompt landing correctly.
##
## Two marks, and they do different jobs:
##
##   SASH   — a diagonal band across the torso. The in-fiction carrier, per the art bible.
##            ⚠️ Only meaningful on a body with a torso to cross. A fish or an insect has none.
##
##   RING   — a tinted disc on the ground under the unit, carrying the team BADGE glyph.
##            ⚠️ This is the one that actually works at the arena camera. `ACCESSIBILITY.md` found
##            3 of 8 TEAM_COLOURS collapse into one olive cluster under deuteranopia, and the badge
##            lived only in a 9px nameplate — invisible at 20-40px. A ground ring is never occluded
##            by the creature standing on it, reads at any distance, and works for EVERY body type
##            in a 13-body roster. Colour alone is never sufficient identification.
extends Node3D

const Sash := preload("res://scripts/ui/team_marker.gd")   # self-ref for the static builders

## Ring sizing, as fractions of the unit's height so it scales with any creature.
const RING_INNER := 0.34
const RING_OUTER := 0.46
const RING_LIFT := 0.02          ## above the floor, to beat z-fighting with the ground plane
const RING_SEGMENTS := 24

## Sash sizing, as fractions of the unit's HEIGHT — never of the model's bounding-box width.
## ⚠️ THE ARM SPAN IS NOT THE CHEST. Sizing the band from `aabb.size.x` produced a plank as wide as
## the outstretched arms, because every model is generated in an A-POSE with the arms held out.
## A torso is roughly 0.4 of a body's height across, and that holds for any creature, so the height
## is the stable reference.
const SASH_CHEST_FRAC := 0.40    ## band length, as a fraction of unit height
const SASH_WIDTH := 0.085        ## band thickness — a sash, not a slab
const SASH_TILT_DEG := 28.0


## Build a flat ring (annulus) mesh on the XZ plane.
static func _ring_mesh(inner: float, outer: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(segments):
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var i0 := Vector3(cos(a0) * inner, 0, sin(a0) * inner)
		var i1 := Vector3(cos(a1) * inner, 0, sin(a1) * inner)
		var o0 := Vector3(cos(a0) * outer, 0, sin(a0) * outer)
		var o1 := Vector3(cos(a1) * outer, 0, sin(a1) * outer)
		for v in [i0, o0, o1, i0, o1, i1]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	return st.commit()


static func _unlit(colour: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	# ⚠️ UNSHADED on purpose. `ART_DIRECTION.md` gives the arena ONE warm working lamp, and a lit
	# team mark would shift hue with the venue — a Bronze arena would tint every team's colour
	# warmer than a Platinum one, which breaks identity across the ladder.
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(colour.r, colour.g, colour.b, alpha)
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## ⚠️ THE RING IS A LEGIBILITY CHANNEL, NOT A DECAL — this is the studio owner's call that team
## identity lives in the ring and the health bar rather than in the creature's design. That saves
## the character budget, removes a prompt failure mode, and works for all 13 body types. It also
## means the ring is now the most valuable free surface in the arena, so it carries more than
## colour:
##
##   FOCUS   the ring brightens and pulses when this unit is the team's called target — the
##           `markedUnit` order finally has somewhere to SHOW, having been invisible until now
##   DEAD    the ring fades and stops pulsing, so a corpse is legible at a glance
##   CLEANSE a gold flash, because breaking hard control off a pinned ally is the most dramatic
##           counter-play in the game and it logged nothing at all until yesterday
##
## ⚠️ All three read from data the sim ALREADY emits (`targetId`, `alive`, the `cleanse` event).
## The renderer derives nothing — `docs/BUILD_CONTRACT.md` §2.
class RingState:
	extends Node3D
	var _base: Color
	var _mesh: MeshInstance3D
	var _badge: Label3D
	var _t := 0.0
	var _focused := false
	var _dead := false
	var _flash := -1.0

	func setup(mesh: MeshInstance3D, badge: Label3D, base: Color) -> void:
		_mesh = mesh; _badge = badge; _base = base

	func set_focused(v: bool) -> void: _focused = v
	func set_dead(v: bool) -> void: _dead = v
	func flash_cleanse() -> void: _flash = 0.0

	func _process(delta: float) -> void:
		if _mesh == null: return
		_t += delta
		if _flash >= 0.0:
			_flash += delta
			if _flash > 0.6: _flash = -1.0
		var col := _base
		var alpha := 0.85
		if _dead:
			# A corpse keeps its livery but stops competing for attention.
			alpha = 0.22
		elif _focused:
			# ⚠️ Pulse, do not just brighten. A static bright ring is indistinguishable from a
			# team whose colour happens to be light; motion is the unambiguous signal.
			var pulse: float = 0.5 + 0.5 * sin(_t * TAU * 1.6)
			col = _base.lerp(Color(1, 1, 1), 0.35 * pulse)
			alpha = 0.85 + 0.15 * pulse
		if _flash >= 0.0:
			var k: float = 1.0 - (_flash / 0.6)
			col = col.lerp(Color(0.85, 0.72, 0.35), k)   # UiTheme.GOLD — a save, not upkeep
			alpha = maxf(alpha, k)
		var m := _mesh.material_override as StandardMaterial3D
		if m != null:
			m.albedo_color = Color(col.r, col.g, col.b, alpha)
		if _badge != null:
			_badge.modulate = Color(col.r, col.g, col.b, 1.0 if not _dead else 0.35)


## Ground ring + badge glyph. `unit_height` scales it; `side_index` picks the livery.
## Returns a node carrying a `RingState` child — call `set_focused` / `set_dead` / `flash_cleanse`
## on `node.get_meta("state")`.
static func make_ring(unit_height: float, side_index: int) -> Node3D:
	var ident: Dictionary = Art.team_identity(side_index)
	var root := Node3D.new()
	root.name = "TeamRing"

	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh(RING_INNER * unit_height, RING_OUTER * unit_height, RING_SEGMENTS)
	mi.material_override = _unlit(ident["colour"], 0.85)
	mi.position.y = RING_LIFT
	# ⚠️ Never casts a shadow — it is a UI mark wearing a 3D costume, not a physical object.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)

	# ⚠️ THE NON-COLOUR TELL, and it is a hard requirement not a nicety. `art.gd`'s
	# `index % TEAM_COLOURS.size()` makes colour collisions EXACT rather than merely likely, and a
	# colourblind player loses the colour channel entirely. The badge must always travel with it.
	var badge := Label3D.new()
	badge.text = str(ident["badge"])
	badge.font_size = 96
	badge.outline_size = 26
	badge.outline_modulate = Color(0, 0, 0, 0.85)
	badge.modulate = ident["colour"]
	badge.pixel_size = unit_height * 0.0022
	badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge.no_depth_test = true
	badge.position = Vector3(0, unit_height * 0.06, RING_OUTER * unit_height * 0.72)
	root.add_child(badge)

	var st := RingState.new()
	st.setup(mi, badge, ident["colour"])
	root.add_child(st)
	root.set_meta("state", st)
	return root


## Diagonal chest sash. Sized from the creature's own bounding box so it fits any model without
## per-creature authoring. Returns null when the body has no torso worth crossing.
static func make_sash(visual: Node3D, unit_height: float, side_index: int) -> Node3D:
	var ident: Dictionary = Art.team_identity(side_index)
	var aabb := _visual_aabb(visual)
	if aabb.size.y <= 0.001:
		return null

	var root := Node3D.new()
	root.name = "TeamSash"
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	# ⚠️ Length from HEIGHT, not from the bounding box — see SASH_CHEST_FRAC. The tilt means the
	# band needs a little extra length to still cross the torso corner to corner.
	qm.size = Vector2(unit_height * SASH_CHEST_FRAC * 1.15, unit_height * SASH_WIDTH)
	mi.mesh = qm
	mi.material_override = _unlit(ident["colour"])
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Sit it just proud of the chest, at shoulder-to-hip height, tilted across the torso.
	# ⚠️ Depth offset is a small fraction of HEIGHT, not of aabb.size.z — an A-posed model's depth
	# is dominated by the feet and tail, which would push the band off the body entirely.
	mi.position = Vector3(0, aabb.position.y * _scale_of(visual) + unit_height * 0.62,
		unit_height * 0.11)
	mi.rotation_degrees = Vector3(0, 0, SASH_TILT_DEG)
	root.add_child(mi)
	return root


## The uniform scale applied to a visual, so AABB values measured in the MESH's own space can be
## converted to the space the marker lives in.
static func _scale_of(n: Node3D) -> float:
	return n.scale.y if n != null else 1.0


## Union of every MeshInstance3D AABB under `n`, in `n`'s own space.
static func _visual_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in _all_descendants(n):
		if c is MeshInstance3D and c.mesh != null:
			var a: AABB = c.mesh.get_aabb()
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
	return out


static func _all_descendants(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all_descendants(c))
	return out
