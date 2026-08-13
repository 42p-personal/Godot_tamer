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
## ⚠️ `SURFACE` DARKENED FROM #14141B TO #0A0A0E IN THE CRAFT ROUND (2026-08-13), AND IT IS THE
## ONLY PALETTE VALUE THAT MOVED. The page→card step measured **1.083:1** — a card was 8% brighter
## than the page it sat on, so every panel in the game was defined by its 1px border and nothing
## else. Remove the borders and thirteen screens became one rectangle.
##
## ⚠️ AND THE OBVIOUS FIX — LIFTING `PANEL`/`PANEL_RAISED` — IS THE WRONG ONE. Measured on the
## 4.7.1 binary: lifting PANEL_RAISED to #2A2A36 takes page→card to 1.168 but drops
## `TEXT_MUTED` on raised to **4.27, under the 4.5 AA floor**. The text-contrast budget on the
## panels is already spent (TEXT_MUTED on PANEL_RAISED is 4.628 — 0.13 above the floor). Darkening
## the PAGE buys the identical separation and *improves every ratio on it*: TEXT_PRIMARY
## 16.13→17.39, TEXT_MUTED 5.52→5.95, and DANGER 4.23→**4.56**, which lifts DANGER clear of the
## 4.5 floor it had been sitting *under*. Elevation is bought with shadow and edge (see
## `panel_style()`), which cost zero contrast; fill tone moves only where it is free.
const SURFACE      := Color(0.0392, 0.0392, 0.0549)  # #0A0A0E — window/root background. 1.168:1 to PANEL.
const PANEL        := Color(0.1098, 0.1098, 0.1412)  # #1C1C24 — card/panel background. ⚠️ MUST NOT MOVE, see above.
const PANEL_RAISED := Color(0.1412, 0.1412, 0.1804)  # #24242E — hover/selected panel. ⚠️ MUST NOT MOVE, see above.
const BORDER       := Color(0.2000, 0.2000, 0.2392)  # #33333D — resting panel border
const BORDER_FAINT := Color(0.1490, 0.1490, 0.1804)  # #26262E — separators, low contrast on purpose

## Control chrome — the fill a BUTTON rests at, distinct from any PANEL tone.
##
## ⚠️ THE BUTTON FILL AND THE PANEL FILL ARE SEPARATE CONTRAST BUDGETS, AND ONLY THE PANEL ONE IS
## SPENT. Buttons used to rest at `PANEL_RAISED` (#24242E), which is why the pressed state measured
## **1.069:1** from resting — there was no room left *below* the fill to press into. Darkening
## PANEL_RAISED all the way to pure black only reaches 1.367, so the direction doc's "pressed ≥1.25
## by darkening" was arithmetically unreachable at the old resting tone; the fix is to raise the
## resting tone, not to darken harder. That is free here because the only muted text a button ever
## carries is its DISABLED label, and the disabled state's fill is `SURFACE` (the darkest tone in
## the file), where TEXT_MUTED reads 5.95:1. A raised button fill also does the craft job the panels
## cannot afford: a control now reads as a control sitting ON a card (1.383:1) instead of as a
## slightly different rectangle.
const CONTROL         := Color(0.2039, 0.2039, 0.2588)  # #343442 — button/OptionButton resting fill
const CONTROL_PRIMARY := Color(0.2784, 0.2196, 0.0941)  # #473818 — the call-to-action fill (unchanged tone, now named)
const CONTROL_DANGER  := Color(0.3216, 0.1255, 0.1216)  # #52201F — destructive fill, lifted so `pressed` has room

# -- ELEVATION -------------------------------------------------------------------------------
## ⚠️ ELEVATION IS INFORMATION, NOT DECORATION — a page where every panel floats is exactly as flat
## as one where none do. Only `raised` (selected/primary) and `interactive` (a card you can act on)
## cast; `default` and `flat` never do. Verified against the 4.7.1 binary: `StyleBoxFlat` exposes
## `shadow_color`/`shadow_size`/`shadow_offset` and per-side `border_width_*` but exactly ONE
## `border_color` and no gradient, so a two-tone bevel is not available from a single stylebox and
## any recipe assuming one is wrong. A shadow is DRAWN, never MEASURED, so none of this moves a
## layout — the whole gain is free of the clipping class of bug rounds 18–20 fixed.
const SHADOW          := Color(0, 0, 0, 0.55)
const ELEV_INTERACTIVE := 4   # shadow_size for a card that can be acted on
const ELEV_RAISED      := 8   # shadow_size for the selected/primary thing on the page

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

## The POSTER register — one multiple of one token, for the title-screen wordmark and nothing else.
##
## ⚠️ THIS IS DELIBERATELY **NOT** IN `TOKEN_FONT_SIZES`, AND THAT IS THE WHOLE POINT OF IT.
## Round 21's theme builder asked for a published poster token on the grounds that it would take
## the project's off-scale count from 1 to 0 "and cost nothing". It would cost the only thing that
## number is FOR. `off-scale = 1` is not a defect the project is carrying — it is a single, known,
## explained exception, and a probe that reports 1 can detect a SECOND poster label appearing on
## some other screen. Widen the token list and it reports 0 forever, including on the day a fifth
## screen decides it deserves 64px too. So the constant exists to kill the magic number and to name
## the intent; the tripwire keeps its meaning. See `_probe_house.gd` T1.
const SIZE_POSTER     := SIZE_DISPLAY * 2  # 64 — title wordmark ONLY; scored off-scale on purpose

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

## A panel stylebox — FOUR rungs of one ladder, and which rung a caller picks is a statement about
## what the panel IS, not about how it should look:
##
##   "flat"        structural. A full-bleed root background, a band, a gutter. No border, no lift.
##   "default"     a resting card. Hairline border, a GROUND LINE, no shadow. The page's furniture.
##   "interactive" a card you can act on — a monster in a strip, a recruit, a drill. Lifts a little.
##   "raised"      THE thing: selected, primary, the one this page is about. Lifts clearly.
##
## ⚠️ THE GROUND LINE (`border_width_bottom = 2` against 1 elsewhere) IS NOT A FLOURISH — it is
## `ART_DIRECTION.md`'s standing "never a raw 90° edge" rule expressed in 2D, the same instruction
## the arena meshes already follow. `StyleBoxFlat` carries only ONE border colour (verified against
## the 4.7.1 binary), so a two-tone bevel is impossible from a single box; a heavier bottom edge is
## the one asymmetry available, and it reads as a card sitting *on* something rather than floating
## in nothing. `flat` is excluded because a structural band sits on nothing.
##
## ⚠️ DO NOT REACH FOR "raised" TO MEAN "IMPORTANT-LOOKING". Rounds 18–20 bought a legibility
## baseline by making the arrangement honest; a page whose every panel is raised has thrown that
## away again, in the other direction. If everything on the screen lifts, nothing is lifted.
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

	match variant:
		"flat":
			sb.set_border_width_all(0)
		"interactive":
			sb.border_width_bottom = 2
			sb.shadow_color = SHADOW
			sb.shadow_size = ELEV_INTERACTIVE
			sb.shadow_offset = Vector2(0, 2)
		"raised":
			sb.border_width_bottom = 3
			sb.shadow_color = SHADOW
			sb.shadow_size = ELEV_RAISED
			sb.shadow_offset = Vector2(0, 4)
		_:
			sb.border_width_bottom = 2
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
##
## ⚠️ TRACKING IS THE ONLY PART OF THE DISPLAY FACE WE CAN HAVE FOR FREE, AND IT IS WORTH TAKING.
## No font file exists anywhere in this tree, so `heading()` renders in Godot's embedded Open Sans
## SemiBold like everything else — which is the most direct cause of the "prototype" reading and is
## deferred (C5) only because licensing a face is a studio call. `FontVariation` wrapping
## `ThemeDB.fallback_font` gives real letter-spacing with no asset, and letterspaced signage is the
## register `ART_THEME.md` §4 asks for. Kept to **1px** deliberately: a 12-character heading grows
## 12px, which no layout in the game notices, whereas the 2–3px that would look best could clip a
## heading in a tight HBox on a screen another stream is rewriting this same round.
static var _tracked_fonts: Dictionary = {}

## A tracked variant of the packaged face. Cached per amount — a FontVariation is a Resource and
## handing every Label its own copy would be a needless allocation on screens that build hundreds.
## ⚠️ Returns null if there is no fallback font (never seen, but a null override would silently
## reset a Label to default rather than erroring, so callers must not assume).
static func display_font(tracking: int = 1) -> FontVariation:
	if _tracked_fonts.has(tracking):
		return _tracked_fonts[tracking]
	var base: Font = ThemeDB.fallback_font
	if base == null:
		return null
	var fv := FontVariation.new()
	fv.base_font = base
	fv.spacing_glyph = tracking
	_tracked_fonts[tracking] = fv
	return fv


static func heading(text: String, level: int = 1) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", SIZE_HEADING if level == 1 else SIZE_SUBHEADING)
	l.add_theme_color_override("font_color", GOLD)
	if level == 1:
		var fv := display_font(1)
		if fv != null:
			l.add_theme_font_override("font", fv)
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
##
## ⚠️ THE FOUR STATES USED TO BE THREE INVISIBLE ONES AND A HOVER. Measured before this round:
## normal→hover **1.363**, normal→pressed **1.069**, normal→disabled **1.102**. A click was not
## acknowledged and a dead control looked live. The reason nobody caught it is structural and worth
## keeping in mind: **a live Button can only ever be in ONE state**, so no screen and no gallery
## built from real Buttons can put the set side by side. `theme_gallery.gd` §17 now draws all five
## as static panels, which is the only place they are comparable at all.
##
## ⚠️ AND PRESSED IS NOT A COLOUR PROBLEM, IT IS A GEOMETRY PROBLEM. Tone alone cannot carry it:
## darkening the old resting fill (`PANEL_RAISED`) all the way to pure black reaches only 1.367:1,
## so "pressed ≥1.25 by darkening" was unreachable as specified. Two changes make it real —
## the resting fill moves up to `CONTROL` (see the token), and pressed additionally
##   (a) DROPS ITS SHADOW, so the button stops floating, and
##   (b) SHIFTS ITS CONTENT DOWN 2px by moving margin from bottom to top,
## which is a genuine "presses in", costs no contrast, and — because top+bottom is unchanged at 16 —
## costs no minimum size either, so nothing reflows. Feedback, not transition: no tween, no delay.
static func button_stylebox(kind: String, state: String) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	var base_bg := CONTROL
	var border := BORDER
	var accent := BORDER.lightened(0.45)
	match kind:
		"primary":
			base_bg = CONTROL_PRIMARY
			border = GOLD
			accent = GOLD.lightened(0.25)
		"danger":
			base_bg = CONTROL_DANGER
			border = DANGER
			accent = DANGER.lightened(0.25)
		_:
			base_bg = CONTROL
			border = BORDER
			accent = BORDER.lightened(0.45)

	# ⚠️ THE PRIMARY ACTION MUST LOOK LIKE THE PRIMARY ACTION. A 2px gold edge against secondary's
	# 1px grey is the cheapest way to say so and it survives every fill change below.
	var edge: int = 2 if kind == "primary" else 1
	var lift: int = ELEV_INTERACTIVE
	var drop := Vector2(0, 2)

	match state:
		"hover":
			base_bg = base_bg.lightened(0.14)
			border = accent
			lift = ELEV_RAISED
			drop = Vector2(0, 3)
		"pressed":
			base_bg = base_bg.darkened(0.38)
			border = accent
			lift = 0            # the float is what you lose when you push it down
		"disabled":
			# The darkest tone in the file, so the fill itself says "not a control right now" —
			# and TEXT_MUTED still reads 5.95:1 on it, well clear of the AA floor.
			base_bg = SURFACE
			border = BORDER_FAINT
			lift = 0
		"focus":
			border = FOCUS

	sb.bg_color = base_bg
	sb.border_color = border
	sb.set_border_width_all(3 if state == "focus" else edge)
	sb.set_corner_radius_all(RADIUS_SM)
	sb.content_margin_left = SPACE_MD
	sb.content_margin_right = SPACE_MD
	# 8/8 resting; 10/6 when pressed. Same total, so `get_minimum_size()` is identical and no
	# button changes size as it is clicked — the label moves, the layout does not.
	sb.content_margin_top = (SPACE_SM + 2) if state == "pressed" else SPACE_SM
	sb.content_margin_bottom = (SPACE_SM - 2) if state == "pressed" else SPACE_SM
	if lift > 0:
		sb.shadow_color = SHADOW
		sb.shadow_size = lift
		sb.shadow_offset = drop
	return sb


# -- ELEVATION REPORT ------------------------------------------------------------------------

## Every relationship this round is judged on, MEASURED rather than quoted, so the gallery and
## `_probe_house.gd` print the same numbers from one source and a future round cannot re-derive
## them by hand and get a different answer.
##
## ⚠️ THIS EXISTS BECAUSE THE PUBLISHED FIGURES WERE ALREADY WRONG IN THE THIRD DECIMAL.
## `UI_THEME.md` §3 rounded TEXT_MUTED-on-PANEL up to 5.10 and on-PANEL_RAISED up to 4.63; live
## they are 5.098 and 4.628, so a tripwire set at the *published* value fails against an
## *untouched* theme. A guard that keeps its own copy of the truth is a guard that decays — this
## project has watched that happen to a dozen invariants. Take the measurement; never quote it.
static func elevation_report() -> Dictionary:
	var n := button_stylebox("secondary", "normal")
	var h := button_stylebox("secondary", "hover")
	var p := button_stylebox("secondary", "pressed")
	var d := button_stylebox("secondary", "disabled")
	return {
		"page_to_card":       contrast_ratio(SURFACE, PANEL),
		"card_to_raised":     contrast_ratio(PANEL, PANEL_RAISED),
		"border_edge":        contrast_ratio(BORDER, PANEL),
		"control_on_card":    contrast_ratio(CONTROL, PANEL),
		"btn_hover":          contrast_ratio(n.bg_color, h.bg_color),
		"btn_pressed":        contrast_ratio(n.bg_color, p.bg_color),
		"btn_disabled":       contrast_ratio(n.bg_color, d.bg_color),
		"pressed_loses_lift": n.shadow_size > 0 and p.shadow_size == 0,
		"muted_on_panel":     contrast_ratio(TEXT_MUTED, PANEL),
		"muted_on_raised":    contrast_ratio(TEXT_MUTED, PANEL_RAISED),
		"danger_on_surface":  contrast_ratio(DANGER, SURFACE),
		"primary_on_page":    contrast_ratio(CONTROL_PRIMARY, SURFACE),
	}


## The drawn part of `stat_bar()` — track, fill, and (the point of it) a CAP MARKER at the
## ceiling with the unreachable remainder rendered as a visibly dead zone.
##
## ⚠️ WHY THIS IS A CUSTOM DRAW AND NOT A ProgressBar. A ProgressBar has exactly one quantity:
## a fill. A trained stat has THREE — where it is, where THIS monster can get to, and how wide
## the scale runs. Drawing only the first two is what let the stable read `115 / 540` and the
## training screen read `115 / 400` for the same stat in the same week (round 18's rule-1 find):
## both were true of a different "max", and neither said which. One bar that draws all three
## makes that particular lie unspeakable — the ceiling is a mark on the track, not a divisor
## chosen per screen.
class CapBar extends Control:
	var value: float = 0.0
	var ceiling: float = 1.0
	var hard_max: float = 1.0
	var fill_color: Color = Color.WHITE

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		var span: float = maxf(hard_max, 0.0001)

		# Track — the full scale, including what this body can never reach.
		draw_rect(Rect2(0, 0, w, h), SURFACE, true)

		# Dead zone — beyond the ceiling. Drawn as a distinct darker band, not merely "empty",
		# so "there is no more room here" is a visible fact rather than an inference.
		var cx: float = clampf(ceiling / span, 0.0, 1.0) * w
		if cx < w - 0.5:
			draw_rect(Rect2(cx, 0, w - cx, h), Color(0, 0, 0, 0.45), true)

		# Fill.
		var fx: float = clampf(value / span, 0.0, 1.0) * w
		if fx > 0.5:
			draw_rect(Rect2(0, 0, fx, h), fill_color, true)

		# Cap marker — a full-height tick plus a notch above/below, so it survives being drawn
		# over the fill AND over the dead zone. Never colour alone: `stat_bar()` prints the
		# ceiling as a number in the same row.
		if ceiling < span - 0.001:
			draw_rect(Rect2(cx - 1.0, -2.0, 2.0, h + 4.0), TEXT_PRIMARY, true)

		draw_rect(Rect2(0, 0, w, h), BORDER, false, 1.0)


## A labelled stat bar with the numeric value ALWAYS rendered as text — never fill colour alone —
## and a CAP MARKER at the ceiling this particular monster can actually reach.
##
## ⚠️ THE CALLER READS THE CEILING, THIS FUNCTION NEVER DERIVES IT. Pass the number you got from
## the system that owns it (`week.gd:stat_ceiling` for a trained stat) — do not pass a league cap
## because it was easier to reach. This file deliberately has no access to a monster, precisely so
## no second copy of that maths can grow here.
##
## `ceiling` — what this body can reach. Rendered as the marker AND as the denominator.
## `hard_max` — how wide to draw the scale (e.g. the final-league cap), so two monsters at
##   different ceilings are comparable at a glance. Defaults to `ceiling` (no dead zone drawn),
##   which is exactly the old single-max behaviour, so existing callers are unchanged.
static func stat_bar(label_text: String, value: float, ceiling: float, fill_color: Color = GOLD, label_width: int = 40, hard_max: float = -1.0) -> Control:
	var span: float = ceiling if hard_max < 0.0 else maxf(hard_max, ceiling)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SPACE_SM)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(label_width, 0)
	lbl.add_theme_font_size_override("font_size", SIZE_CAPTION)
	lbl.add_theme_color_override("font_color", TEXT_SECONDARY)
	row.add_child(lbl)

	var bar := CapBar.new()
	bar.value = value
	bar.ceiling = maxf(ceiling, 0.0001)
	bar.hard_max = maxf(span, 0.0001)
	bar.fill_color = fill_color
	bar.custom_minimum_size = Vector2(0, 14)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.tooltip_text = "%d now · ceiling %d%s" % [
		int(round(value)), int(round(ceiling)),
		("" if span <= ceiling + 0.001 else " · scale runs to %d" % int(round(span)))]
	row.add_child(bar)

	var val_lbl := Label.new()
	val_lbl.text = "%d / %d" % [int(round(value)), int(round(ceiling))]
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

# =============================================================================
# 8. SHARED COMPONENTS — the things EVERY screen needs and each currently hand-rolls.
#
#    ⚠️ FILE OWNERSHIP MANUFACTURED THIS DUPLICATION, AND THE CODE SAYS SO IN ITS OWN COMMENTS.
#    `market_ui.gd:445` carries the line: "duplicated from stable_ui.gd's `_portrait` rather than
#    shared, since that file is out of this stream's scope to edit or refactor." There are FIVE
#    independent `_portrait` implementations in scripts/ui/ (stable, market, report, tactics,
#    ending) with THREE different signatures, and seven screens that name a monster while showing
#    no portrait at all. Every one of those authors was right about the ownership rule; what was
#    missing was a shared place to put it. This is that place.
#
#    ⚠️ THE HARD RULE FOR EVERYTHING BELOW: A COMPONENT RENDERS, IT NEVER DERIVES.
#    Nothing in this section reads Career, Roster, WeekLib or a MonsterInstance. Callers pass
#    values they have already read from the system that owns them. That is deliberate, and it is
#    the structural form of the project's rule (1) — a screen must not lie about the thing it
#    describes. A second copy of the week's maths cannot grow in a file that cannot see the week.
#    The single exception is `Art` (portraits), which is an asset lookup, not a rule.
# =============================================================================

## The token sets, published so a PROBE can check conformance without keeping its own copy of the
## list — a rule nothing enforces is a rule that decays, and this project has watched that happen
## to a dozen invariants. `scripts/_probe_house.gd` walks every screen and flags any font size or
## text colour outside these. ⚠️ Adding an entry here WIDENS what the probe permits — do it on
## purpose, not to make a red line go away.
const TOKEN_FONT_SIZES := [SIZE_CAPTION, SIZE_BODY, SIZE_SUBHEADING, SIZE_HEADING, SIZE_DISPLAY]
const TOKEN_TEXT_COLOURS := [
	TEXT_PRIMARY, TEXT_SECONDARY, TEXT_MUTED, GOLD, SAFE, CAUTION, DANGER, FOCUS,
	STATUS_HARD_CONTROL, STATUS_POISON, STATUS_BURN, STATUS_BLEED, STATUS_DOOM,
	STATUS_UTILITY, STATUS_BUFF,
]


## True if `c` is one of the published text tokens. Tolerance is generous on purpose — the
## question a probe asks is "did someone invent a sixth grey", not "is this bit-identical".
static func is_token_colour(c: Color, tol: float = 0.02) -> bool:
	for t in TOKEN_TEXT_COLOURS:
		var tc: Color = t
		if absf(tc.r - c.r) <= tol and absf(tc.g - c.g) <= tol and absf(tc.b - c.b) <= tol:
			return true
	return false


# -- 8.1 PORTRAIT --------------------------------------------------------------------------

## A creature portrait, or a deliberate accent-tinted placeholder carrying the species' initials
## at the SAME footprint. Callers never branch on which they got, and the layout does not jump
## the moment art lands mid-session.
##
## ⚠️ THE PLACEHOLDER IS PART OF THE CONTRACT, not a fallback nobody sees — `UI_LAYOUT_RULES`
## checklist: "Degrades deliberately when `Art.*` returns null". Behaviour is lifted verbatim
## from `stable_ui.gd:_portrait`, which is the version the other four were copied from.
##
## ⚠️ THE FRAME IS THE CRAFT ROUND'S ONE CHANGE HERE, AND IT IS DELIBERATELY NOT A SIZE CHANGE.
## The game owns 65 real painted portraits and was showing them as bare bitmaps floating on a card
## — no ground, no edge, nothing that said "this is the artwork". A framed well (a darker recess,
## a hairline edge, the same corner radius as every other card) is what a trading card does, and it
## costs nothing: the frame draws INSIDE the existing rect, so the footprint is byte-identical and
## no caller's layout moves. Growing the portrait would have been the bigger visual win and is
## exactly the change that cannot be made safely while five screens are being re-laid out in
## parallel — it is a per-screen call, noted for the integrator, not taken here.
## ── THE SIX STAT HUES ─────────────────────────────────────────────────────────────────────────
##
## A FOURTH CHANNEL, AND IT IS LEGAL UNDER `docs/ART_THEME.md` FOR EXACTLY ONE REASON:
## **GOLD IS AN INK AND NEVER A FILL; A STAT HUE IS A FILL OR A GLYPH AND NEVER AN INK.** The two
## therefore never appear in a comparable role, which is what keeps this from being the fourth
## colour SYSTEM that ART_THEME.md records going wrong once already. The hues are not invented —
## they were sampled out of the 141 authored ability icons, where they had been a designed system
## nobody had named since the icons were drawn (`docs/POLISH_DIRECTION.md` §3.1).
##
## ⚠️ A STAT HUE MUST NEVER REACH `add_theme_color_override("font_color", ...)`. Not merely as
## taste: `_probe_house.gd` T2 scores every rendered LABEL against `TOKEN_TEXT_COLOURS`, and a hued
## label would push the project's measured off-token count off its known 7. Bar fills and borders
## are not scored, and that asymmetry is precisely the boundary the ruling draws. Measured on
## `PANEL`: STR 5.53 · DEX 7.50 · CON 5.85 · WIS 7.74 · INT 4.85 · CHA 8.90 — all six clear the 3:1
## non-text floor, so nothing here buys colour at the cost of contrast.
##
## ⚠️ CON AND CHA ARE THE WEAK ADJACENCY — both amber, and at bar width they are the hardest pair
## in the set to tell apart. Flagged by round 21's week-screens builder and NOT fixed here: the
## hues are consumed from authored art, and retuning one is an art call, not an integration one.
## If the studio retunes exactly one, retune CON.
const STAT_HUES := {
	"STR": Color(0.8706, 0.4706, 0.2431),  # #DE783E
	"DEX": Color(0.4706, 0.7451, 0.3529),  # #78BE5A
	"CON": Color(0.6667, 0.5882, 0.3922),  # #AA9664
	"WIS": Color(0.4314, 0.7451, 0.6667),  # #6EBEAA
	"INT": Color(0.5882, 0.4706, 0.8627),  # #9678DC
	"CHA": Color(0.9020, 0.7059, 0.3529),  # #E6B45A
}


## The hue for one stat, or TEXT_SECONDARY for anything that is not one of the six.
static func stat_hue(stat: String) -> Color:
	return STAT_HUES.get(stat, TEXT_SECONDARY)


## ── THE 141 ABILITY ICONS ─────────────────────────────────────────────────────────────────────
##
## ⚠️ THE PROJECT'S SIGNATURE FAILURE, CAUGHT: 141 authored ability icons shipped in
## `assets/icons/abilities/` and, until round 21, `arena_3d.gd` was the ONLY file in the codebase
## that loaded one. Every meta screen that listed a moveset rendered its abilities as plain text
## while the art sat on disk. Three screens then each grew their own loader in the same round —
## which is how the project got 141 off-scale labels in three files once before. This is the one.
##
## ⚠️ THE ICON NEVER REPLACES THE NAME, IT SITS BESIDE IT. An icon that needs a label is not an
## icon, but a 141-strong set nobody has learned yet is not one either — and a moveset the player
## cannot read is a legibility regression wearing a craft round's clothes.
##
## Degrades to a hue-bordered blank badge at the SAME FOOTPRINT when a move has no icon on disk, so
## a missing asset never reflows a row. `stat` may be "" for a neutral border.
static func ability_icon(move_id: String, stat: String = "", px: int = 32) -> Control:
	var path := "res://assets/icons/abilities/%s.png" % move_id
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		if tex != null:
			var t := TextureRect.new()
			t.texture = tex
			t.custom_minimum_size = Vector2(px, px)
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			return t
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(px, px)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_theme_stylebox_override("panel",
		panel_style("default", stat_hue(stat) if stat != "" else BORDER))
	return badge


## The raw texture for one ability, or null. Prefer `ability_icon()` — this exists for the callers
## that need to place the texture into a control they already own (a button's icon slot, a chip).
static func ability_texture(move_id: String) -> Texture2D:
	var path := "res://assets/icons/abilities/%s.png" % move_id
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func portrait(species_id: String, display_name: String, portrait_size: Vector2 = Vector2(48, 48), accent: Color = GOLD, framed: bool = true) -> Control:
	var tex: Texture2D = Art.creature_texture(species_id)
	if tex != null:
		var t := TextureRect.new()
		t.texture = tex
		t.custom_minimum_size = portrait_size
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.tooltip_text = display_name
		if not framed:
			return t
		var frame := PanelContainer.new()
		frame.custom_minimum_size = portrait_size
		frame.tooltip_text = display_name
		var fsb := StyleBoxFlat.new()
		# A recess, not a card: the well is SURFACE (the darkest tone) so the art reads as sitting
		# IN something. Zero content margin — the art fills the frame exactly and the 1px edge is
		# drawn over its outermost pixel, which is why the footprint cannot change.
		fsb.bg_color = SURFACE
		fsb.border_color = BORDER
		fsb.set_border_width_all(1)
		fsb.set_corner_radius_all(RADIUS_SM)
		fsb.content_margin_left = 0
		fsb.content_margin_right = 0
		fsb.content_margin_top = 0
		fsb.content_margin_bottom = 0
		frame.add_theme_stylebox_override("panel", fsb)
		frame.add_child(t)
		return frame

	var panel := PanelContainer.new()
	panel.custom_minimum_size = portrait_size
	panel.tooltip_text = display_name
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(accent.r, accent.g, accent.b, 0.16)
	sb.border_color = accent
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(RADIUS_MD)
	panel.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = display_name.substr(0, 2).to_upper()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", accent)
	lbl.add_theme_font_size_override("font_size", maxi(SIZE_CAPTION, int(portrait_size.y * 0.35)))
	panel.add_child(lbl)
	return panel


# -- 8.2 MONSTER CARD ----------------------------------------------------------------------

## THE monster card. One shape for "here is a monster", wherever a monster appears: the stable
## strip, the market shelf, the breeding parent picker, the lab freezer, a tournament roster, a
## report line-up.
##
## `info` keys (all optional except "name") — every one a value the CALLER has already read:
##   "name"        String  — the monster's own name, the primary line
##   "species_id"  String  — portrait lookup only
##   "subtitle"    String  — "Warrior · damage", "Mammal · Tank", whatever this screen is about
##   "note"        String  — one short state line: "● Growing", "4y left of 8y", "At cap"
##   "note_colour" Color   — defaults TEXT_MUTED. Pair it with a glyph in the text; never colour alone
##   "chips"       Array   — pre-built Controls (delta_chip/status_chip/team_chip), laid in a row
##   "trailing"    Control — a right-hand slot: a price, a Recruit button, a stat bar
##
## `opts` keys: "portrait" Vector2 (default 48x48) · "accent" Color · "selected" bool ·
## "focusable" bool (default true).
static func monster_card(info: Dictionary, opts: Dictionary = {}) -> PanelContainer:
	var accent: Color = opts.get("accent", GOLD)
	var selected: bool = bool(opts.get("selected", false))
	var psize: Vector2 = opts.get("portrait", Vector2(48, 48))

	var panel := PanelContainer.new()
	# ⚠️ THE ELEVATION LADDER IS THE CARD'S STATE, NOT ITS DECORATION. A monster card is the most
	# repeated object in the game, so it is also the place where "raise everything" would do the
	# most damage. Three rungs, and each one means something a player can act on:
	#   selected            → "raised"      the one this page is about
	#   focusable (default) → "interactive" a card you can click
	#   focusable = false   → "default"     a read-only line in a report or a roster listing
	# A tournament standings row and the recruit you are about to buy are not the same object and
	# they should not have been drawn the same way.
	var rung := "default"
	if selected:
		rung = "raised"
	elif bool(opts.get("focusable", true)):
		rung = "interactive"
	panel.add_theme_stylebox_override("panel", panel_style(rung, accent if selected else BORDER))
	if bool(opts.get("focusable", true)):
		panel.focus_mode = Control.FOCUS_ALL
		# Focus must be visually distinct from selection, not the same treatment wider
		# (docs/ACCESSIBILITY.md SC 2.4.7) — that is exactly what `focus_style()` guarantees.
		panel.add_theme_stylebox_override("focus", focus_style(panel_style("raised", accent)))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SPACE_MD)
	panel.add_child(row)

	row.add_child(portrait(str(info.get("species_id", "")), str(info.get("name", "?")), psize, accent))

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)

	var name_lbl := Label.new()
	name_lbl.text = str(info.get("name", "?"))
	name_lbl.add_theme_font_size_override("font_size", SIZE_SUBHEADING)
	name_lbl.add_theme_color_override("font_color", TEXT_PRIMARY)
	col.add_child(name_lbl)

	if str(info.get("subtitle", "")) != "":
		col.add_child(body_text(str(info["subtitle"]), "secondary"))

	if str(info.get("note", "")) != "":
		var note := Label.new()
		note.text = str(info["note"])
		note.add_theme_font_size_override("font_size", SIZE_CAPTION)
		note.add_theme_color_override("font_color", info.get("note_colour", TEXT_MUTED))
		col.add_child(note)

	var chips: Array = info.get("chips", [])
	if not chips.is_empty():
		var chip_row := HFlowContainer.new()
		chip_row.add_theme_constant_override("h_separation", SPACE_SM)
		chip_row.add_theme_constant_override("v_separation", SPACE_XS)
		for c in chips:
			if c is Control:
				chip_row.add_child(c)
		col.add_child(chip_row)

	var trailing: Variant = info.get("trailing", null)
	if trailing is Control:
		var t: Control = trailing
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		t.size_flags_horizontal = Control.SIZE_SHRINK_END
		# ⚠️ THE TRAILING SLOT MUST NOT WRAP, AND THE FIRST CAPTURE OF THIS COMPONENT SHOWED WHY.
		# `body_text()` sets AUTOWRAP_WORD, which is right for a paragraph and wrong for a price:
		# "Recruit · 365g" broke over three lines and slid off the card's right edge because the
		# name column claimed the width first. A trailing slot is a fixed fact — a price, a
		# button, a bar — so it opts out of wrapping.
		if t is Label:
			(t as Label).autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(t)

	return panel


# -- 8.3 DELTA CHIP ------------------------------------------------------------------------

## "What changed" — a signed quantity with an explicit sign GLYPH as well as a colour, because a
## player who cannot separate green from red must still be able to read a training week.
## `▲ +9 STR`, `▼ −15 stamina`, `▲ +107g`. Zero renders as a muted `• no change`, never a blank.
##
## ⚠️ THE CALLER SUPPLIES THE NUMBER; THIS CANNOT COMPUTE A WEEK. Round 14 found a training
## preview hard-coding "+6 basic / +12 intensive", ignoring every multiplier the week is actually
## decided by. A delta shown to the player must come from the real tick on a throwaway clone
## (`week.gd:preview_week`), and this component is deliberately incapable of guessing one.
##
## `good_is_up` — which DIRECTION is good, so the colour follows the meaning rather than the
## arithmetic sign. Default true: bigger is better (a stat, gold held, happiness, stamina left),
## so a negative delta reads amber. Pass false where SMALLER is better (a price, a cooldown, an
## upkeep, weeks until retirement), so a positive delta reads amber instead.
static func delta_chip(amount: float, unit: String = "", good_is_up: bool = true, decimals: int = 0) -> Control:
	var up: bool = amount > 0.0001
	var down: bool = amount < -0.0001
	var glyph := "•"
	var col := TEXT_MUTED
	if up:
		glyph = "▲"
		col = SAFE if good_is_up else CAUTION
	elif down:
		glyph = "▼"
		col = CAUTION if good_is_up else SAFE

	var text := "no change"
	if up or down:
		var num := ("%+.*f" % [decimals, amount]) if decimals > 0 else ("%+d" % int(round(amount)))
		# Godot prints ASCII '-'; swap in a true minus, which stays legible at 14px.
		num = num.replace("-", "−")
		text = num if unit == "" else "%s %s" % [num, unit]

	var chip := PanelContainer.new()
	var sb := panel_style("default", BORDER_FAINT)
	sb.bg_color = Color(col.r, col.g, col.b, 0.14)
	sb.border_color = ensure_contrast(col, PANEL, 3.0)
	sb.content_margin_left = SPACE_SM
	sb.content_margin_right = SPACE_SM
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", sb)

	var lbl := Label.new()
	lbl.text = "%s %s" % [glyph, text]
	lbl.add_theme_font_size_override("font_size", SIZE_CAPTION)
	lbl.add_theme_color_override("font_color", ensure_contrast(col, PANEL, 4.5))
	chip.add_child(lbl)
	return chip


# -- 8.4 COMPARISON ROW --------------------------------------------------------------------

## Two candidates on one line with the difference SPELLED OUT — the shape "which of these two"
## needs, and which no screen currently has. Breeding's two parents; a market recruit against the
## body you already own; a cup's purse against the one before it.
##
## ⚠️ THE DIFFERENCE IS THE WHOLE POINT. Round 18's capture found five breeding rows reading an
## identical `potential ×1.00 · Wild stock — Gen 1` — five values with zero discriminating
## information, which is a list, not a choice. `verdict` is where the caller says what the
## difference MEANS; passing "" prints nothing rather than a reassuring blank.
static func comparison_row(label_text: String, left_text: String, right_text: String, verdict: String = "", winner: int = 0) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SPACE_MD)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(110, 0)
	lbl.add_theme_font_size_override("font_size", SIZE_CAPTION)
	lbl.add_theme_color_override("font_color", TEXT_SECONDARY)
	row.add_child(lbl)

	for side in [0, 1]:
		var v := Label.new()
		v.text = left_text if side == 0 else right_text
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_font_size_override("font_size", SIZE_BODY)
		var is_winner: bool = (winner == 1 and side == 0) or (winner == 2 and side == 1)
		v.add_theme_color_override("font_color", GOLD if is_winner else TEXT_PRIMARY)
		# Never colour alone — the winning side is also marked in the text.
		if is_winner:
			v.text = "▸ " + v.text
		row.add_child(v)

	var vd := Label.new()
	vd.text = verdict
	vd.custom_minimum_size = Vector2(180, 0)
	vd.add_theme_font_size_override("font_size", SIZE_CAPTION)
	vd.add_theme_color_override("font_color", TEXT_MUTED)
	row.add_child(vd)

	return row


# -- 8.5 EMPTY STATE -----------------------------------------------------------------------

## What a region says when it has nothing in it. ⚠️ NOT DECORATION — round 18 measured the town
## hub at 52% empty black, the shop at 55% and the market at 40%, and a blank region is
## indistinguishable from a screen that failed to load. An empty state states the fact, states
## what would fill it, and where possible offers the door.
##
## If `action_text` is non-empty the Button is reachable via `empty_state_button()`.
static func empty_state(title: String, body: String, action_text: String = "") -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := panel_style("default", BORDER_FAINT)
	sb.content_margin_left = SPACE_XL
	sb.content_margin_right = SPACE_XL
	sb.content_margin_top = SPACE_XL
	sb.content_margin_bottom = SPACE_XL
	panel.add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", SPACE_SM)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(col)

	var t := heading(title, 2)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)

	var b := body_text(body, "secondary")
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(b)

	if action_text != "":
		var btn := Button.new()
		btn.name = "EmptyStateAction"
		btn.text = action_text
		btn.focus_mode = Control.FOCUS_ALL
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		for state in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(state, button_stylebox("primary", state))
		col.add_child(btn)
	return panel


static func empty_state_button(panel: PanelContainer) -> Button:
	return panel.find_child("EmptyStateAction", true, false) as Button


# -- 8.6 DISABLED WITH A REASON ------------------------------------------------------------

## ⚠️ THE ONLY SANCTIONED WAY TO DISABLE A CONTROL. `UI_LAYOUT_RULES` rule 3 — never a dead
## control with no explanation — has no teeth as prose: `btn.disabled = true` is one token, and
## remembering the tooltip is a discipline nobody has consistently had. Here the reason is a
## REQUIRED ARGUMENT, so the rule is enforced by the signature instead of by memory.
##
## ⚠️ AND A TOOLTIP IS THE FLOOR, NOT THE CEILING. `shop_ui.gd` puts the reason in the LABEL —
## "Locked — reach Iron league (you are Bronze)" — which is strictly better, because a tooltip
## needs a hover a keyboard user may never perform. Pass `in_label` true for that. Round 18's
## probe scored those two shop buttons as violations precisely because it could only see
## tooltips; they were the best examples on the screen. `_probe_house.gd` now accepts either.
static func disable_with_reason(btn: Button, reason: String, in_label: bool = false) -> void:
	btn.disabled = true
	btn.tooltip_text = reason
	if in_label and not btn.text.contains(reason):
		# " · " not " — ", because the reasons themselves already use an em-dash
		# ("Locked — reach Iron league"), and dash-on-dash read as one run-on line in the capture.
		btn.text = "%s · %s" % [btn.text, reason]
	btn.add_theme_stylebox_override("disabled", button_stylebox("secondary", "disabled"))


## The inverse — re-enable and clear the reason, so a stale explanation cannot survive on a live
## control (the mirror failure: a button that works but still says why it does not).
static func enable_control(btn: Button, tooltip: String = "") -> void:
	btn.disabled = false
	btn.tooltip_text = tooltip


# -- 8.7 COMMIT BAR ------------------------------------------------------------------------

## THE commitment affordance: a pinned footer that states what is about to happen, in the same
## place on every screen, with the primary action in it.
##
## ⚠️ IT IS PINNED OUTSIDE THE SCROLL BY CONSTRUCTION, WHICH IS THE POINT. `UI_LAYOUT_RULES`
## rule 2 says a primary action must be reachable without the player guessing that a region
## scrolls; round 18 could not find a commit button on the tactics screen at 1152x648 in either
## capture. Add this as a SIBLING of the ScrollContainer, never inside it:
##
##     var bar := UiTheme.commit_bar("Five monsters · 80 stamina · 0 gold", "Advance Week")
##     root_vbox.add_child(bar)                       # sibling of the scroll, last child
##     UiTheme.commit_bar_button(bar).pressed.connect(_on_advance)
##     UiTheme.commit_bar_set(bar, "…", false, "Two monsters have no plan")
##
## ⚠️ THE SUMMARY IS NOT FLAVOUR. This game asks the player to commit and then WATCH; the summary
## line is the last chance to state what is being committed to. Read it from the system that owns
## it, per section 8's standing rule — and update it every time it changes, because a stale
## summary above a live commit button is a rule-(1) lie in the most expensive place on the screen.
static func commit_bar(summary: String, action_text: String, kind: String = "primary") -> PanelContainer:
	var bar := PanelContainer.new()
	# ⚠️ "raised" HERE IS A STATEMENT OF FACT, NOT AN EMPHASIS CHOICE. This bar is the one element
	# on the screen that is genuinely pinned above the scrolling content, and before this round
	# nothing said so — it sat at the same tone as the panels sliding underneath it. The shadow it
	# now casts onto that content is the literal truth of the layout, which is the only kind of
	# elevation this file is willing to spend.
	var sb := panel_style("raised", BORDER)
	sb.bg_color = PANEL
	sb.shadow_offset = Vector2(0, -3)   # it floats above what scrolls UNDER it, so the light says so
	sb.content_margin_left = SPACE_LG
	sb.content_margin_right = SPACE_LG
	sb.content_margin_top = SPACE_SM
	sb.content_margin_bottom = SPACE_SM
	bar.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SPACE_LG)
	bar.add_child(row)

	var summary_lbl := body_text(summary, "secondary")
	summary_lbl.name = "CommitSummary"
	summary_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(summary_lbl)

	var btn := Button.new()
	btn.name = "CommitAction"
	btn.text = action_text
	btn.focus_mode = Control.FOCUS_ALL
	btn.custom_minimum_size = Vector2(200, 40)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, button_stylebox(kind, state))
	row.add_child(btn)
	return bar


static func commit_bar_button(bar: PanelContainer) -> Button:
	return bar.find_child("CommitAction", true, false) as Button


static func commit_bar_summary(bar: PanelContainer) -> Label:
	return bar.find_child("CommitSummary", true, false) as Label


## Update summary AND readiness in one call. There is no route through this API that disables the
## commit button without stating a reason, and none that leaves the summary behind when the thing
## being committed changes.
static func commit_bar_set(bar: PanelContainer, summary: String, ready: bool, reason: String = "") -> void:
	var lbl := commit_bar_summary(bar)
	var btn := commit_bar_button(bar)
	if lbl == null or btn == null:
		return
	if ready:
		lbl.text = summary
		lbl.add_theme_color_override("font_color", TEXT_SECONDARY)
		enable_control(btn)
	else:
		var why := reason if reason != "" else "Not ready yet"
		lbl.text = why
		lbl.add_theme_color_override("font_color", CAUTION)
		disable_with_reason(btn, why)


# ══════════════════════════════════════════════════════════════════════════════════════════════
# THE PLACES — a drawn emblem per room, and the signboard every room hangs above its door.
#
# ⚠️ THIS LIVED IN `town_ui.gd` FOR ONE ROUND AND FOUR SCREENS PRELOADED THE HUB TO REACH IT.
# It was written there honestly — five screens were being polished concurrently and `theme.gd`
# belonged to another stream, so landing a component here would have been an edit-collision on the
# one file everything inherits. Round 21's integration finished the job. The coupling it removes is
# not cosmetic: `market_ui`, `shop_ui`, `lab_ui` and `breeding_ui` each held
# `preload("res://scripts/ui/town_ui.gd")` — dragging the hub's whole Career/Roster/WeekLib load
# graph into four screens for a DRAWING HELPER. Nothing in this block reads game state, which is
# exactly this section's standing rule and why the lift was safe.
#
# ⚠️ FIVE ROOMS ARE DIFFERENTIATED BY SHAPE AND RHYTHM, DELIBERATELY NOT BY HUE, and that is a
# ruling not an omission. `docs/ART_THEME.md`'s palette discipline publishes exactly three colour
# systems — league material, team colour, status vocabulary — and states that they went wrong once
# already by being collapsed into one axis. A sixth "room hue" would be a fourth system carrying a
# fourth meaning, and the probe would score every one of its colours as invented. So the emblem is
# always GOLD-on-plinth (the guild-signage ink the theme already publishes) and the room's identity
# is carried by the DRAWING, the FACT TILES and the page's rhythm instead. Shape is a free channel;
# hue is a spent one.
# ══════════════════════════════════════════════════════════════════════════════════════════════

## A guild sign, drawn. Seven emblems, all line-work over a plinth, none of them a font glyph and
## none of them an asset — so a place mark cannot tofu on an export target and cannot go missing
## when an import fails. Drawn at whatever size the caller asks for; the geometry is expressed in
## fractions of the box, so 22px on a door and 40px on a room plate are the same emblem.
class PlaceMark extends Control:
	var kind: String = "market"
	var tint: Color = Color.WHITE

	func _draw() -> void:
		var s: float = minf(size.x, size.y)
		var o: Vector2 = (size - Vector2(s, s)) * 0.5
		var w: float = maxf(1.5, s * 0.075)

		match kind:
			# An awning over a stall — the shape a market has from across a street.
			"market":
				_line([Vector2(0.08, 0.34), Vector2(0.92, 0.34)], o, s, w)
				var valance := PackedVector2Array()
				for i in range(5):
					valance.append(Vector2(0.08 + 0.21 * i, 0.34))
					valance.append(Vector2(0.185 + 0.21 * i, 0.50))
				_line(valance, o, s, w)
				_line([Vector2(0.16, 0.50), Vector2(0.16, 0.92)], o, s, w)
				_line([Vector2(0.84, 0.50), Vector2(0.84, 0.92)], o, s, w)
			# A barn: pitched roof, wide door.
			"stable":
				_line([Vector2(0.10, 0.44), Vector2(0.50, 0.12), Vector2(0.90, 0.44)], o, s, w)
				_line([Vector2(0.14, 0.44), Vector2(0.14, 0.90), Vector2(0.86, 0.90),
					Vector2(0.86, 0.44)], o, s, w)
				_line([Vector2(0.38, 0.90), Vector2(0.38, 0.58), Vector2(0.62, 0.58),
					Vector2(0.62, 0.90)], o, s, w)
			# A trophy — the Circuit's own object, and unmistakable at 22px.
			"tournament":
				_line([Vector2(0.28, 0.14), Vector2(0.72, 0.14), Vector2(0.62, 0.56),
					Vector2(0.38, 0.56), Vector2(0.28, 0.14)], o, s, w)
				_line([Vector2(0.28, 0.22), Vector2(0.14, 0.22), Vector2(0.14, 0.34),
					Vector2(0.33, 0.44)], o, s, w)
				_line([Vector2(0.72, 0.22), Vector2(0.86, 0.22), Vector2(0.86, 0.34),
					Vector2(0.67, 0.44)], o, s, w)
				_line([Vector2(0.50, 0.56), Vector2(0.50, 0.76)], o, s, w)
				_line([Vector2(0.30, 0.88), Vector2(0.70, 0.88)], o, s, w)
			# A coin, edge-on notches — a counter where gold changes hands.
			"shop":
				draw_arc(o + Vector2(s * 0.5, s * 0.5), s * 0.36, 0.0, TAU, 40, tint, w)
				_line([Vector2(0.50, 0.28), Vector2(0.50, 0.72)], o, s, w)
				_line([Vector2(0.38, 0.38), Vector2(0.62, 0.38)], o, s, w)
				_line([Vector2(0.38, 0.62), Vector2(0.62, 0.62)], o, s, w)
			# A flask — the cryo bench.
			"lab":
				_line([Vector2(0.38, 0.10), Vector2(0.62, 0.10)], o, s, w)
				_line([Vector2(0.44, 0.10), Vector2(0.44, 0.40), Vector2(0.20, 0.84),
					Vector2(0.80, 0.84), Vector2(0.56, 0.40), Vector2(0.56, 0.10)], o, s, w)
				_line([Vector2(0.31, 0.64), Vector2(0.69, 0.64)], o, s, w)
			# Two eggs, one behind the other — a line continuing, which is the whole subject.
			"breeding":
				_oval(o + Vector2(s * 0.40, s * 0.56), s * 0.26, s * 0.34, w)
				_oval(o + Vector2(s * 0.68, s * 0.44), s * 0.17, s * 0.23, w)
			# A pediment on columns — the enshrinement register.
			"hall":
				_line([Vector2(0.08, 0.36), Vector2(0.50, 0.12), Vector2(0.92, 0.36),
					Vector2(0.08, 0.36)], o, s, w)
				for x in [0.22, 0.50, 0.78]:
					_line([Vector2(x, 0.42), Vector2(x, 0.80)], o, s, w)
				_line([Vector2(0.10, 0.88), Vector2(0.90, 0.88)], o, s, w)

	func _line(pts: Array, o: Vector2, s: float, w: float) -> void:
		var out := PackedVector2Array()
		for p in pts:
			out.append(o + Vector2(p.x * s, p.y * s))
		draw_polyline(out, tint, w, true)

	func _oval(centre: Vector2, rx: float, ry: float, w: float) -> void:
		var pts := PackedVector2Array()
		for i in range(25):
			var a: float = TAU * float(i) / 24.0
			pts.append(centre + Vector2(cos(a) * rx, sin(a) * ry))
		draw_polyline(pts, tint, w, true)


## One emblem, at the size asked for. `tint` defaults to the guild-signage ink.
static func place_mark(kind: String, px: int = 22, tint: Color = GOLD) -> Control:
	var m := PlaceMark.new()
	m.kind = kind
	m.tint = tint
	m.custom_minimum_size = Vector2(px, px)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m


## ⚠️ THE SIGNBOARD IS THE ROUND'S ANSWER TO "FIVE ROOMS THAT ARE NOT PLACES". Every one of the
## five screens opened with the SAME three lines — a gold title, a grey sentence, a grey run-on of
## the room's numbers — so the top 90px of the Market, the Shop, the Lab and the Breeding Ranch
## were interchangeable. This replaces them with a plinth carrying the room's own drawn emblem, its
## name, its sentence, and its standing numbers AS TILES rather than as a comma-run.
##
## ⚠️ THE TILES ARE THE POINT, NOT DECORATION. `2400 gold · 2 preserved in the Lab · 3 in the barn
## (holds 5) · breeding costs 300g` is four separate facts a player has to parse a sentence to
## reach. `facts` is `[{"value": "2400g", "label": "in hand"}, …]` — value at SUBHEADING, label at
## CAPTION beneath — which is the rhythm the Lab's own ledger row already had and the only screen
## of the five that read as designed. This generalises the good one rather than inventing a sixth
## register. Pass an empty array for a room with no standing numbers.
static func room_plate(mark_kind: String, title: String, blurb: String, facts: Array = []) -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := panel_style("raised", BORDER)
	sb.content_margin_left = SPACE_LG
	sb.content_margin_right = SPACE_LG
	sb.content_margin_top = SPACE_MD
	sb.content_margin_bottom = SPACE_MD
	panel.add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", SPACE_SM)
	panel.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", SPACE_MD)
	col.add_child(top)

	var badge := PanelContainer.new()
	var bsb := panel_style("default", GOLD)
	bsb.bg_color = SURFACE
	bsb.set_border_width_all(1)
	bsb.content_margin_left = SPACE_SM
	bsb.content_margin_right = SPACE_SM
	bsb.content_margin_top = SPACE_SM
	bsb.content_margin_bottom = SPACE_SM
	badge.add_theme_stylebox_override("panel", bsb)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_child(place_mark(mark_kind, 34))
	top.add_child(badge)

	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(words)
	words.add_child(heading(title, 1))
	if blurb != "":
		var b := body_text(blurb, "secondary")
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		words.add_child(b)

	if not facts.is_empty():
		var tiles := HBoxContainer.new()
		tiles.add_theme_constant_override("separation", SPACE_XL)
		col.add_child(tiles)
		for fv in facts:
			var f: Dictionary = fv
			var t := VBoxContainer.new()
			t.add_theme_constant_override("separation", 0)
			var v := Label.new()
			v.text = str(f.get("value", ""))
			v.autowrap_mode = TextServer.AUTOWRAP_OFF
			v.add_theme_font_size_override("font_size", SIZE_SUBHEADING)
			v.add_theme_color_override("font_color", f.get("tint", TEXT_PRIMARY))
			t.add_child(v)
			var l := Label.new()
			l.text = str(f.get("label", ""))
			l.autowrap_mode = TextServer.AUTOWRAP_OFF
			l.add_theme_font_size_override("font_size", SIZE_CAPTION)
			l.add_theme_color_override("font_color", TEXT_MUTED)
			t.add_child(l)
			tiles.add_child(t)
	return panel
