## GUILD COLOURS — the shared UI theme, token set and component builders for every Godot
## screen in this project.
##
## WHY THIS FILE EXISTS: every screen (title/stable/tactics/arena3d/report/training) was built
## independently, each hand-rolling its own StyleBoxFlat, font size and colour inline. Nothing
## matched, and every new screen re-invented the look from scratch. This file is the fix: one
## token set — docs/ART_THEME.md's "Guild Colours" identity, docs/ART_BIBLE_GUILD_COLOURS.md's
## binding spec, docs/ACCESSIBILITY.md's measured floors — and a set of builder functions, so a
## screen calls `UiTheme.panel_style()` / `UiTheme.heading()` / `UiTheme.stat_bar()` instead of
## inventing a new StyleBoxFlat every time. See docs/UI_THEME.md for the adoption guide.
##
## HOW TO USE THIS FILE — short version, full version in docs/UI_THEME.md:
##   const UiTheme = preload("res://scripts/ui/theme.gd")
##   self.theme = UiTheme.base_theme()            # buttons/panels/bars look right for free
##   var head := UiTheme.heading("The Stable")    # ready-made Label
##   var hp := UiTheme.hp_bar(m.hp, m.max_hp)      # numeric value baked in, never colour-alone
##
## ⚠️ NOT AN AUTOLOAD, ON PURPOSE. Six screens are being rewritten concurrently right now
## (town_ui/tutorial_ui/sandbox_ui/tactics_ui/arena_3d and others). Adding an autoload means
## editing project.godot, which every one of those streams may also touch. `preload()` gets
## every screen the exact same static functions with zero risk of a project.godot merge
## collision. Revisit once the concurrent rewrites land and this can be coordinated once.
##
## ⚠️ NOT `class_name`, ON PURPOSE — see .claude/docs/technical-preferences.md's standing
## Forbidden Pattern: a script-level `class_name` reports a false "not declared" to this
## project's script validator while the class cache is cold. `preload()` sidesteps it entirely
## and every function below is `static`, so no instance is ever needed.
##
## ⚠️ THIS FILE DOES NOT OWN `Art.TEAM_COLOURS`. Team colour stays exactly where it already
## lives (`scripts/art.gd`) — this file only CONSUMES it (see `team_chip()`/`team_border_color()`
## below) and never redefines the 8 liveries. Editing art.gd is out of this file's scope; where
## a team colour's contrast needs guaranteeing, this file fixes it dynamically at the point of
## use (`ensure_contrast()`) rather than by changing the shared palette out from under every
## other screen that already reads it.
extends RefCounted

# =============================================================================
# 1. PALETTE — three systems that must never collide (docs/ART_THEME.md, docs/
#    ART_BIBLE_GUILD_COLOURS.md §4): league material / team colour / status vocabulary. This
#    file owns SURFACE/TEXT/STATUS tokens and the contrast utilities. League material (per-venue
#    masonry/stone) is a future token set once more leagues have art to borrow from — see
#    docs/UI_THEME.md "what's still missing". Team colour is consumed, never redefined (above).
# =============================================================================

## Chrome surfaces — the "guild office" register: dark, warm-neutral, not a sci-fi black. Values
## match what every screen already independently converged on (Color(0.09,0.09,0.12) window bg
## in stable_ui.gd, arena_3d.gd's #0D0D12 nameplate panel) rather than inventing new ones —
## formalising an existing convergence, not overriding it.
const SURFACE      := Color(0.0784, 0.0784, 0.1059)  # #14141B — window/root background
const PANEL        := Color(0.1098, 0.1098, 0.1412)  # #1C1C24 — card/panel background
const PANEL_RAISED := Color(0.1412, 0.1412, 0.1804)  # #24242E — hover/selected panel
const BORDER       := Color(0.2000, 0.2000, 0.2392)  # #33333D — resting panel border
const BORDER_FAINT := Color(0.1490, 0.1490, 0.1804)  # #26262E — separators, low contrast on purpose

## Text — three tiers. Contrast ratios below are hand-computed against the WCAG relative-
## luminance formula (same method docs/ACCESSIBILITY.md §3 used) — see docs/UI_THEME.md for the
## full worked table. Stated here so an edit to one of these can't silently drift below the
## floor it was chosen to clear.
const TEXT_PRIMARY   := Color(0.9412, 0.9412, 0.9569)  # #F0F0F4 — 16.13:1 on SURFACE
const TEXT_SECONDARY := Color(0.6510, 0.6510, 0.7020)  # #A6A6B3 — 7.03:1 on PANEL (matches existing stable_ui.gd/tactics_ui.gd usage exactly)
const TEXT_MUTED     := Color(0.5490, 0.5490, 0.6000)  # #8C8C99 — 5.10:1 on PANEL. Do not darken further without re-measuring — this already sits close to the 4.5:1 AA floor for normal text.

## Brand ink — the "guild paperwork" heading colour. Fixed warm gold, NOT team colour: this is
## the wordmark/heading register used regardless of whose match this is. Matches title_ui.gd's
## existing tagline colour and stable_ui.gd's section-title colour EXACTLY (both already hand-
## picked Color(0.85, 0.72, 0.35) independently) — formalising a convergence, not a new choice.
const GOLD := Color(0.85, 0.72, 0.35)  # #D8B859 — 9.53:1 on SURFACE

## Threat gradient — HP fill. Hues match arena_3d.gd's already-shipped values exactly; do not
## "improve" these independently of that file, they are the live game's HP colours today.
## ⚠️ docs/ACCESSIBILITY.md's CVD simulation found danger/caution collapse toward the same olive
## hue under deuteranopia/protanopia, and safe reads as flat grey. The fix this file enforces is
## STRUCTURAL, not a new hue: `hp_bar()` below ALWAYS renders the numeric value as text baked
## into the bar itself, so no screen that adopts it can reintroduce that colour-alone failure
## (docs/ACCESSIBILITY.md §0 finding #2, the single highest-value item in that audit).
const SAFE    := Color(0.32, 0.76, 0.36)  # #52C25C — 8.05:1 on SURFACE
const CAUTION := Color(0.88, 0.70, 0.25)  # #E0B340 — 9.33:1 on SURFACE
const DANGER  := Color(0.87, 0.24, 0.24)  # #DE3D3D — 4.23:1 on SURFACE: large text / fills / icons only — falls just under the 4.5:1 AA floor for small body text, do not use as small-text colour

## Status vocabulary — docs/ART_THEME.md §3's four category anchors, given concrete hex here for
## the first time. Chosen to sit clear of both the threat gradient above and every
## `Art.TEAM_COLOURS` swatch (docs/ART_BIBLE_GUILD_COLOURS.md §4 Finding 1 is the collision this
## fixes) — the swatch-by-swatch comparison is in docs/UI_THEME.md, not repeated here.
## ⚠️ PROPOSED, NOT YET RUN THROUGH A REAL CVD SIMULATOR. docs/ART_BIBLE_GUILD_COLOURS.md asks
## for a Coblis/Sim Daltonism pass before sign-off; this session had no execution environment to
## run one (see the report this file shipped with) — flagged as a follow-up, not skipped
## silently. `status_chip()` below pairs every hue with a distinct drawn SHAPE for exactly this
## reason: the shape channel survives a CVD collision even if a hue turns out to collide.
const STATUS_HARD_CONTROL := Color(0.9608, 0.9020, 0.7216)  # #F5E6B8 pale cream — stun/sleep/fear/confusion
const STATUS_POISON       := Color(0.5490, 0.7765, 0.2471)  # #8CC63F yellow-green — distinct from SAFE's pure green
const STATUS_BURN         := Color(1.0000, 0.5412, 0.2392)  # #FF8A3D vivid orange — distinct from CAUTION's muted amber
const STATUS_BLEED        := Color(0.8784, 0.1882, 0.2902)  # #E0304A crimson — deliberately close to DANGER; disambiguated by chip register (icon+text), not hue, per docs/ART_BIBLE_GUILD_COLOURS.md §4's "rendering register" strategy
const STATUS_DOOM         := Color(0.2902, 0.1804, 0.3216)  # #4A2E52 near-black purple — distinct by darkness alone
const STATUS_UTILITY      := Color(0.5490, 0.4784, 0.6000)  # #8C7A99 desaturated violet-grey
const STATUS_BUFF         := Color(0.2471, 0.6588, 0.7529)  # #3FA8C0 cool teal — kept clear of FOCUS's brighter cyan on purpose

## Keyboard-focus ring — its own colour, distinct from every accent/status/team hue above (see
## the collision table in docs/UI_THEME.md), so a focus ring can never be misread as "a status
## is active" or "this is the selected team". Matches stable_ui.gd's existing FOCUS_COLOR
## exactly — formalising a value already in use, not introducing a new one.
const FOCUS := Color(0.40, 0.85, 1.0)  # #66D9FF — 10.42:1 on PANEL

# =============================================================================
# 2. TYPE SCALE — px. docs/ACCESSIBILITY.md §5 measured the live nameplate text at 9px/8px,
#    "50%/44% of the 18px minimum". Every size below already clears that floor; a screen that
#    adopts these constants instead of an inline `add_theme_font_size_override` cannot
#    reintroduce that specific finding.
# =============================================================================
const SIZE_DISPLAY    := 32  # title-screen wordmark register
const SIZE_HEADING    := 22  # section headers ("The Stable", "Stats", "Moveset")
const SIZE_SUBHEADING := 18  # card titles, list item primary text — the accessibility FLOOR
const SIZE_BODY       := 16  # dense data — stat tables, standings, button labels
const SIZE_CAPTION    := 14  # secondary/help text — the smallest size this file ever hands out

# =============================================================================
# 3. SPACING + RADII
# =============================================================================
const SPACE_XS  := 4
const SPACE_SM  := 8
const SPACE_MD  := 12
const SPACE_LG  := 16
const SPACE_XL  := 24
const SPACE_XXL := 32

const RADIUS_SM := 4
const RADIUS_MD := 6
const RADIUS_LG := 10

# =============================================================================
# 4. CONTRAST UTILITIES — the WCAG relative-luminance formula, the same method
#    docs/ACCESSIBILITY.md used by hand. Exists so a builder can GUARANTEE a floor at the point
#    of use instead of hoping a token chosen elsewhere still clears it once composited against a
#    caller-supplied background — e.g. a team colour, which this file does not control.
# =============================================================================

static func _linearize(c: float) -> float:
	if c <= 0.03928:
		return c / 12.92
	return pow((c + 0.055) / 1.055, 2.4)


static func relative_luminance(c: Color) -> float:
	var r := _linearize(c.r)
	var g := _linearize(c.g)
	var b := _linearize(c.b)
	return 0.2126 * r + 0.7152 * g + 0.0722 * b


static func contrast_ratio(a: Color, b: Color) -> float:
	var la := relative_luminance(a)
	var lb := relative_luminance(b)
	var lighter: float = maxf(la, lb)
	var darker: float = minf(la, lb)
	return (lighter + 0.05) / (darker + 0.05)


## Returns fg unchanged if it already clears min_ratio against bg; otherwise nudges it toward
## white or black (whichever direction increases contrast) in small steps until it does, or
## until it hits pure white/black. Use wherever a CALLER-SUPPLIED colour — a team colour, most
## often — is drawn as a border/text on a background this file doesn't control.
##
## ⚠️ THIS IS THE FIX FOR docs/ACCESSIBILITY.md FINDING #6: iron-grey's nameplate border
## measured 2.60:1, below the 3:1 floor for SC 1.4.11. Call
## `ensure_contrast(Art.team_colour(i), panel_bg, 3.0)` instead of drawing the raw team colour
## and the border can never ship below the floor again, for ANY of the 8 liveries, without
## touching `art.gd`'s shared palette. `team_border_color()` below wraps this for the common case.
static func ensure_contrast(fg: Color, bg: Color, min_ratio: float = 3.0) -> Color:
	if contrast_ratio(fg, bg) >= min_ratio:
		return fg
	var toward_white: bool = relative_luminance(bg) < 0.5
	var target := Color.WHITE if toward_white else Color.BLACK
	var out := fg
	for _i in range(24):
		out = out.lerp(target, 0.08)
		if contrast_ratio(out, bg) >= min_ratio or out.is_equal_approx(target):
			break
	return out

# =============================================================================
# 5. BUILDERS — call these instead of hand-rolling a StyleBoxFlat. See docs/UI_THEME.md for a
#    before/after example lifted from the current screens.
# =============================================================================

## A panel stylebox. variant: "default" (resting card), "raised" (hover/selected — wider border,
## lighter fill), "flat" (no border, e.g. a full-bleed root background panel).
static func panel_style(variant: String = "default", accent: Color = BORDER) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_RAISED if variant == "raised" else PANEL
	sb.border_color = accent
	sb.set_border_width_all(2 if variant == "raised" else 1)
	sb.set_corner_radius_all(RADIUS_MD)
	sb.content_margin_left = SPACE_SM
	sb.content_margin_right = SPACE_SM
	sb.content_margin_top = SPACE_SM
	sb.content_margin_bottom = SPACE_SM
	if variant == "flat":
		sb.set_border_width_all(0)
	return sb


## Keyboard-focus stylebox — duplicates the caller's base stylebox (so the panel's own bg/radius
## survives) and overrides ONLY the border, to FOCUS at 3px. Per docs/ACCESSIBILITY.md §7 (SC
## 2.4.7): focus must be visually distinct from selection, not the same treatment wider — do not
## reuse an accent-coloured "selected" border for both states.
static func focus_style(base: StyleBoxFlat) -> StyleBoxFlat:
	var sb: StyleBoxFlat = base.duplicate() as StyleBoxFlat
	sb.border_color = FOCUS
	sb.set_border_width_all(3)
	return sb


## Section header — "ringside signage" register. ⚠️ Approximates the slab/display face
## docs/ART_THEME.md §4 asks for using only Godot's built-in font (bold weight + the GOLD ink +
## a larger size) — no display face is packaged in this repo yet. See docs/UI_THEME.md "what's
## still missing" for the exact swap-in point: once a font file lands in assets/ui/fonts/, this
## is the one function that needs to change for every screen's headings to pick it up.
static func heading(text: String, level: int = 1) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", SIZE_HEADING if level == 1 else SIZE_SUBHEADING)
	l.add_theme_color_override("font_color", GOLD)
	return l


## Body text at one of three tiers. "primary"/"secondary" both render at SIZE_BODY (16px, clears
## AA at normal size against PANEL — see the token comments above); "muted" drops to
## SIZE_CAPTION (14px) and should be reserved for genuinely secondary information, not anything
## load-bearing to read at a glance.
static func body_text(text: String, tier: String = "primary") -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	var col := TEXT_PRIMARY
	var fsize := SIZE_BODY
	if tier == "secondary":
		col = TEXT_SECONDARY
	elif tier == "muted":
		col = TEXT_MUTED
		fsize = SIZE_CAPTION
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", fsize)
	return l


## A single Button-state stylebox. kind: "primary" (gold-bordered call-to-action), "danger"
## (destructive action), "secondary" (everything else — the base_theme() default). state:
## "normal"/"hover"/"pressed"/"disabled"/"focus".
static func button_stylebox(kind: String, state: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var base_bg := PANEL_RAISED
	var border := BORDER
	match kind:
		"primary":
			base_bg = Color(0.28, 0.22, 0.10)
			border = GOLD
		"danger":
			base_bg = Color(0.26, 0.11, 0.11)
			border = DANGER
		_:
			base_bg = PANEL_RAISED
			border = BORDER
	match state:
		"hover":
			base_bg = base_bg.lightened(0.10)
		"pressed":
			base_bg = base_bg.darkened(0.15)
		"disabled":
			base_bg = PANEL
			border = BORDER_FAINT
		"focus":
			border = FOCUS
	sb.bg_color = base_bg
	sb.border_color = border
	sb.set_border_width_all(3 if state == "focus" else 1)
	sb.set_corner_radius_all(RADIUS_SM)
	sb.content_margin_left = SPACE_MD
	sb.content_margin_right = SPACE_MD
	sb.content_margin_top = SPACE_SM
	sb.content_margin_bottom = SPACE_SM
	return sb


## A labelled stat bar with the numeric value ALWAYS rendered as text — never fill colour alone.
## General-purpose version (training/stat screens, any 0..max quantity); see `hp_bar()` for the
## specific green/amber/red threat-gradient version used on the live arena screen.
static func stat_bar(label_text: String, value: float, max_value: float, fill_color: Color = GOLD, label_width: int = 40) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SPACE_SM)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(label_width, 0)
	lbl.add_theme_font_size_override("font_size", SIZE_CAPTION)
	lbl.add_theme_color_override("font_color", TEXT_SECONDARY)
	row.add_child(lbl)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = maxf(max_value, 0.0001)
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill_color
	fg.set_corner_radius_all(RADIUS_SM)
	var bg2 := StyleBoxFlat.new()
	bg2.bg_color = SURFACE
	bg2.set_corner_radius_all(RADIUS_SM)
	bar.add_theme_stylebox_override("fill", fg)
	bar.add_theme_stylebox_override("background", bg2)
	row.add_child(bar)

	var val_lbl := Label.new()
	val_lbl.text = "%d / %d" % [int(round(value)), int(round(max_value))]
	val_lbl.custom_minimum_size = Vector2(80, 0)
	val_lbl.add_theme_font_size_override("font_size", SIZE_CAPTION)
	val_lbl.add_theme_color_override("font_color", TEXT_SECONDARY)
	row.add_child(val_lbl)

	return row


## HP threat-gradient bar. ⚠️ ALWAYS renders "current/max" as text drawn ON the bar itself (not
## merely beside it, so it survives even a very cramped nameplate) — the structural fix for
## docs/ACCESSIBILITY.md §0 finding #2, the single highest-value item in that whole audit. Any
## screen calling this instead of hand-rolling its own HP fill cannot reintroduce that finding,
## regardless of how the surrounding layout changes later.
static func hp_bar(current: float, max_hp: float, bar_size: Vector2 = Vector2(80, 14)) -> Control:
	var frac: float = clampf(current / maxf(max_hp, 0.0001), 0.0, 1.0)
	var fill_color := SAFE
	if frac < 0.25:
		fill_color = DANGER
	elif frac < 0.5:
		fill_color = CAUTION

	var wrap := Control.new()
	wrap.custom_minimum_size = bar_size

	var bg := ColorRect.new()
	bg.color = SURFACE
	bg.anchor_right = 1; bg.anchor_bottom = 1
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(bg)

	var fill := ColorRect.new()
	fill.color = fill_color
	fill.anchor_bottom = 1
	fill.anchor_right = frac
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(fill)

	var lbl := Label.new()
	lbl.text = "%d/%d" % [int(round(current)), int(round(max_hp))]
	lbl.anchor_right = 1; lbl.anchor_bottom = 1
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", SIZE_CAPTION)
	# White text with a dark outline reads on all three fill hues AND on the empty-bar SURFACE
	# behind it — a single flat colour could not do that across a bar whose fill colour changes
	# as HP drops.
	lbl.add_theme_color_override("font_color", TEXT_PRIMARY)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 3)
	wrap.add_child(lbl)

	return wrap


## Team identity chip — badge glyph AND colour together, per `art.gd`'s own hard rule that
## colour alone is never sufficient team identification. Prefer this over drawing
## `Art.team_colour()` directly anywhere a screen shows "whose is this". The glyph colour is run
## through `ensure_contrast()` against PANEL so it stays legible regardless of which of the 8
## liveries is selected.
static func team_chip(team_index: int, label_text: String = "") -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SPACE_XS)
	var identity: Dictionary = Art.team_identity(team_index)
	var col: Color = identity["colour"]
	var chip_col: Color = ensure_contrast(col, PANEL, 4.5)

	var badge := Label.new()
	badge.text = identity["badge"]
	badge.add_theme_color_override("font_color", chip_col)
	badge.add_theme_font_size_override("font_size", SIZE_BODY)
	row.add_child(badge)

	if label_text != "":
		var lbl := Label.new()
		lbl.text = label_text
		lbl.add_theme_color_override("font_color", chip_col)
		lbl.add_theme_font_size_override("font_size", SIZE_BODY)
		row.add_child(lbl)

	return row


## A nameplate-frame border colour GUARANTEED to clear WCAG SC 1.4.11 (3:1 non-text) against
## whatever panel background it's drawn on, for any of `art.gd`'s 8 TEAM_COLOURS. This is the
## fix for docs/ACCESSIBILITY.md finding #6 (iron grey measured 2.60:1), applied at the point of
## use rather than by editing `art.gd`'s shared palette, which this file does not own.
static func team_border_color(team_index: int, panel_bg: Color = PANEL) -> Color:
	return ensure_contrast(Art.team_colour(team_index), panel_bg, 3.0)

# =============================================================================
# 6. STATUS VOCABULARY — category, colour, abbreviation and a distinct drawn SHAPE per family
#    (docs/ART_THEME.md §3: "distinguished by icon shape as well as hue, so a colourblind read
#    still separates them"). Extend STATUS_META when a new status is authored; an unlisted
#    status falls back to the utility/grey family + hexagon rather than erroring.
# =============================================================================

const STATUS_META := {
	# hard control — pale cream, diamond
	"stun":       {"category": "control", "abbr": "STN"},
	"sleep":      {"category": "control", "abbr": "SLP"},
	"fear":       {"category": "control", "abbr": "FEAR"},
	"confusion":  {"category": "control", "abbr": "CNF"},
	# damage-over-time — one hue per KIND, circle
	"poison":     {"category": "poison", "abbr": "PSN"},
	"burn":       {"category": "burn",   "abbr": "BRN"},
	"bleed":      {"category": "bleed",  "abbr": "BLD"},
	"doom":       {"category": "doom",   "abbr": "DOOM"},
	# utility debuffs — desaturated violet, hexagon
	"blind":      {"category": "utility", "abbr": "BLND"},
	"silence":    {"category": "utility", "abbr": "SIL"},
	"vulnerable": {"category": "utility", "abbr": "VULN"},
	"knockback":  {"category": "utility", "abbr": "KB"},
	"healblock":  {"category": "utility", "abbr": "HBLK"},
	"charm":      {"category": "utility", "abbr": "CHRM"},
	# buffs — cool teal, upward triangle
	"haste":      {"category": "buff", "abbr": "HST"},
}


static func _status_colour(category: String) -> Color:
	match category:
		"control":
			return STATUS_HARD_CONTROL
		"poison":
			return STATUS_POISON
		"burn":
			return STATUS_BURN
		"bleed":
			return STATUS_BLEED
		"doom":
			return STATUS_DOOM
		"buff":
			return STATUS_BUFF
		_:
			return STATUS_UTILITY


static func _status_shape(category: String) -> int:
	match category:
		"control":
			return StatusIconShape.SHAPE_DIAMOND
		"buff":
			return StatusIconShape.SHAPE_TRIANGLE
		"poison", "burn", "bleed", "doom":
			return StatusIconShape.SHAPE_CIRCLE
		_:
			return StatusIconShape.SHAPE_HEXAGON


## A small custom-drawn icon carrying category as a SHAPE, not just a colour — the non-colour
## channel docs/ART_THEME.md §3 asks for. ⚠️ This is a placeholder register (flat geometric
## primitive), explicitly NOT the authored icon set §3 calls for ("exact hex values and the
## actual icon linework are a technical-artist/UI-programmer production task") — it exists so
## the grouping+shape LOGIC is correct and testable today, ready to be swapped for real linework
## later without any call-site changes (see docs/UI_THEME.md).
class StatusIconShape extends Control:
	const SHAPE_DIAMOND := 0
	const SHAPE_CIRCLE := 1
	const SHAPE_HEXAGON := 2
	const SHAPE_TRIANGLE := 3

	var shape: int = SHAPE_CIRCLE
	var fill: Color = Color.WHITE

	func _draw() -> void:
		var s: Vector2 = size
		var c: Vector2 = s * 0.5
		var r: float = minf(s.x, s.y) * 0.5 - 1.0
		match shape:
			SHAPE_DIAMOND:
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)
				]), fill)
			SHAPE_CIRCLE:
				draw_circle(c, r, fill)
			SHAPE_TRIANGLE:
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(0, -r), c + Vector2(r, r), c + Vector2(-r, r)
				]), fill)
			SHAPE_HEXAGON:
				var pts := PackedVector2Array()
				for i in range(6):
					var a: float = TAU * float(i) / 6.0 - PI / 2.0
					pts.append(c + Vector2(cos(a), sin(a)) * r)
				draw_colored_polygon(pts, fill)


## A status chip: shape+colour icon (the category tell) plus its abbreviation as text (the
## colour-alone fallback, matching the team-badge pattern above). Unknown status names fall back
## to the utility/grey family + hexagon rather than erroring, so an unauthored status degrades
## visibly instead of crashing a screen mid-fight.
static func status_chip(status_name: String) -> Control:
	var meta: Dictionary = STATUS_META.get(status_name, {"category": "utility", "abbr": status_name.substr(0, 4).to_upper()})
	var category: String = meta["category"]
	var col: Color = _status_colour(category)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.tooltip_text = status_name.capitalize()

	var icon := StatusIconShape.new()
	icon.custom_minimum_size = Vector2(12, 12)
	icon.shape = _status_shape(category)
	icon.fill = col
	row.add_child(icon)

	var lbl := Label.new()
	lbl.text = meta["abbr"]
	lbl.add_theme_font_size_override("font_size", SIZE_CAPTION)
	lbl.add_theme_color_override("font_color", ensure_contrast(col, PANEL, 4.5))
	row.add_child(lbl)

	return row

# =============================================================================
# 7. BASE THEME — assign to a screen's root Control (`self.theme = UiTheme.base_theme()`) to get
#    consistent Button/PanelContainer/Label/ProgressBar/OptionButton/LineEdit styling for free,
#    with zero per-widget code. This is the actual fix for the drift the brief names: a screen
#    that sets this ONE property stops needing to hand-roll a StyleBoxFlat for its default
#    controls at all.
# =============================================================================
static func base_theme() -> Theme:
	var th := Theme.new()

	th.set_color("font_color", "Label", TEXT_PRIMARY)
	th.set_font_size("font_size", "Label", SIZE_BODY)

	th.set_stylebox("panel", "PanelContainer", panel_style("default"))

	for state in ["normal", "hover", "pressed", "disabled"]:
		th.set_stylebox(state, "Button", button_stylebox("secondary", state))
	th.set_stylebox("focus", "Button", button_stylebox("secondary", "focus"))
	th.set_color("font_color", "Button", TEXT_PRIMARY)
	th.set_color("font_hover_color", "Button", TEXT_PRIMARY)
	th.set_color("font_pressed_color", "Button", TEXT_PRIMARY)
	th.set_color("font_disabled_color", "Button", TEXT_MUTED)
	th.set_font_size("font_size", "Button", SIZE_BODY)

	var pb_fg := StyleBoxFlat.new()
	pb_fg.bg_color = GOLD
	pb_fg.set_corner_radius_all(RADIUS_SM)
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = SURFACE
	pb_bg.set_corner_radius_all(RADIUS_SM)
	th.set_stylebox("fill", "ProgressBar", pb_fg)
	th.set_stylebox("background", "ProgressBar", pb_bg)

	for state in ["normal", "hover", "pressed", "disabled"]:
		th.set_stylebox(state, "OptionButton", button_stylebox("secondary", state))
	th.set_color("font_color", "OptionButton", TEXT_PRIMARY)
	th.set_font_size("font_size", "OptionButton", SIZE_BODY)

	var le := StyleBoxFlat.new()
	le.bg_color = SURFACE
	le.border_color = BORDER
	le.set_border_width_all(1)
	le.set_corner_radius_all(RADIUS_SM)
	le.content_margin_left = SPACE_SM
	le.content_margin_right = SPACE_SM
	le.content_margin_top = SPACE_XS
	le.content_margin_bottom = SPACE_XS
	th.set_stylebox("normal", "LineEdit", le)
	var le_focus: StyleBoxFlat = le.duplicate() as StyleBoxFlat
	le_focus.border_color = FOCUS
	le_focus.set_border_width_all(2)
	th.set_stylebox("focus", "LineEdit", le_focus)
	th.set_color("font_color", "LineEdit", TEXT_PRIMARY)
	th.set_font_size("font_size", "LineEdit", SIZE_BODY)

	return th
