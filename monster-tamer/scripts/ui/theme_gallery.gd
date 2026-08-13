## THEME GALLERY — every UiTheme token and builder on one screen, for visual review and
## regression-checking. Not part of the navigation graph (nothing links to it); open it directly
## (res://scenes/theme_gallery.tscn) to review the theme after any change to scripts/ui/theme.gd.
##
## Sections, top to bottom: palette swatches with hand-computed contrast ratios, type scale,
## spacing/radii, panel + button states, stat/HP bars, team chips (all 8 liveries), status chips
## (every STATUS_META entry), and a before/after comparing a hand-rolled StyleBoxFlat (the
## pattern this file replaces) against UiTheme.panel_style() (the replacement).
##
## ── SECTIONS 16–20 ADDED BY THE CRAFT ROUND (2026-08-13) ──────────────────────────────────────
## ⚠️ THE GALLERY COULD SHOW EVERY COMPONENT AND STILL NOT SHOW THE PROBLEM. Round 21's audit found
## that the game reads as a prototype for four reasons, and NOT ONE of them was visible on this
## screen, because each is a *relationship between two things* and the gallery only ever drew one
## thing at a time:
##
##   16  ELEVATION      the whole page→card→raised ladder spans 1.08:1 and 1.10:1. Three panels
##                      drawn apart look fine; drawn touching, they are one rectangle.
##   17  STATES         hover/pressed/disabled are 1.36 / 1.07 / 1.10 from resting. YOU CANNOT
##                      HOVER FIVE BUTTONS AT ONCE, so a live Button can never show its own state
##                      set — the states have to be drawn side by side as static panels or they
##                      are unreviewable, which is exactly why nobody noticed pressed was invisible.
##   18  ABILITY ICONS  141 authored 64×64 icons ship; arena_3d.gd is the only file that loads one.
##   19  STAT HUES      those icons carry a six-hue stat system nobody named — and its CHA hue is
##                      1.012:1 from GOLD, i.e. the same colour as the brand ink.
##   20  GLYPH COVER    the packaged font (Open Sans SemiBold) does not contain →, ⚠, ✓, ✗, ▲ or ◆.
##                      They render only because a Windows system font is silently supplying them.
##
## Every one of those is a NUMBER, so every one of them is printed next to the thing it describes,
## computed live through UiTheme's own `contrast_ratio()` / `Font.has_char()` rather than copied
## from the audit. ⚠️ A gallery that quotes a measurement instead of taking one is a document, not
## an instrument — and this project has been burned twice by a guard keeping its own stale copy of
## the truth (UI_LAYOUT_RULES R7). If a builder improves `theme.gd`, these numbers must move on
## their own. See docs/POLISH_DIRECTION.md for the targets they are moving toward.
##
## ── RUNNING IT ────────────────────────────────────────────────────────────────────────────────
##   P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/theme_gallery.tscn
##
## ⚠️ RUN IT WITH A WINDOW, NEVER `--headless` — the dummy renderer hands back blank images and
## the run "passes" having captured nothing. With `--capture` it walks its own scroll and writes
## user://gallery/NN.png, then quits; the same blank-frame canary `_probe_screens.gd` uses guards
## it, and the run exits NON-ZERO if any capture carried no picture.
extends Control

const UiTheme = preload("res://scripts/ui/theme.gd")

## Where `--capture` writes. Mirrors `_probe_screens.gd`'s convention so the two sets sit
## side by side under the same user:// root.
const OUT_DIR := "user://gallery/"

## Capture geometry. ⚠️ 1152x648 is the SMALL size UI_LAYOUT_RULES R5 requires review at, and the
## gallery is reviewed at the same size as the screens it governs — a component that only works at
## 1280x800 is a component that fails on the screen it was built for.
const WINDOW := Vector2i(1152, 648)

## Blank-frame canary, same contract as `_probe_screens.gd:_shoot`.
const CANARY_GRID := 48
const CANARY_MIN_COLOURS := 8

var _scroll: ScrollContainer = null
var _blank: Array[String] = []


func _ready() -> void:
	self.theme = UiTheme.base_theme()
	_build_ui()
	# ⚠️ BOTH ARG LISTS, ON PURPOSE. Godot splits the command line at `--`: anything after it goes
	# to `get_cmdline_user_args()` and anything before to `get_cmdline_args()`. Reading only one of
	# them makes the flag work or silently do nothing depending on how it was typed, and "silently
	# do nothing" here means an open window that never quits and a capture directory that never
	# appears — which is exactly how the first run of this went.
	var args: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	if "--capture" in args:
		await _capture_walk()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.SURFACE
	bg.anchor_right = 1; bg.anchor_bottom = 1
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1; scroll.anchor_bottom = 1
	add_child(scroll)
	_scroll = scroll

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, UiTheme.SPACE_XL)
	scroll.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XL)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(col)

	col.add_child(UiTheme.heading("Guild Colours — Theme Gallery", 1))
	col.add_child(UiTheme.body_text(
		"Every token and builder in scripts/ui/theme.gd, on one screen, for visual review. " +
		"Re-open this scene after any change to theme.gd.", "secondary"))

	_section(col, "1. Palette + measured contrast", _build_palette_section())
	_section(col, "2. Type scale", _build_type_scale_section())
	_section(col, "3. Spacing + radii", _build_spacing_section())
	_section(col, "4. Panels + buttons", _build_panel_button_section())
	_section(col, "5. Stat bars + HP bar", _build_bars_section())
	_section(col, "6. Team chips (all 8 liveries)", _build_team_section())
	_section(col, "7. Status chips (every STATUS_META entry)", _build_status_section())
	_section(col, "8. Before / after", _build_before_after_section())
	_section(col, "9. Monster card — ONE shape, everywhere a monster appears", _build_card_section())
	_section(col, "10. Stat bar with a CAP MARKER", _build_capbar_section())
	_section(col, "11. Delta chips — what changed since last week", _build_delta_section())
	_section(col, "12. Comparison row — which of these two", _build_compare_section())
	_section(col, "13. Empty state + a dead control that says why", _build_empty_section())
	_section(col, "14. Commit bar — the affordance that pins itself outside the scroll", _build_commit_section())
	_section(col, "15. THE ACCEPTANCE TEST — the same monster, three screens", _build_three_screens_section())
	_section(col, "16. ⚠️ THE ELEVATION LADDER — the measured reason the game reads flat", _build_elevation_section())
	_section(col, "17. ⚠️ INTERACTIVE STATES, DRAWN SIDE BY SIDE", _build_states_section())
	_section(col, "18. THE 141 ABILITY ICONS — the asset exactly one file loads", _build_icons_section())
	_section(col, "19. THE SIX STAT HUES — and the GOLD collision", _build_stathue_section())
	_section(col, "20. ⚠️ GLYPH COVERAGE — what the packaged font does NOT contain", _build_glyph_section())


func _section(parent: VBoxContainer, title: String, body: Control) -> void:
	parent.add_child(HSeparator.new())
	parent.add_child(UiTheme.heading(title, 2))
	parent.add_child(body)


# -- 1. Palette -----------------------------------------------------------------

func _build_palette_section() -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", UiTheme.SPACE_LG)
	grid.add_theme_constant_override("v_separation", UiTheme.SPACE_SM)

	var entries := [
		["TEXT_PRIMARY on SURFACE", UiTheme.TEXT_PRIMARY, UiTheme.SURFACE],
		["TEXT_SECONDARY on PANEL", UiTheme.TEXT_SECONDARY, UiTheme.PANEL],
		["TEXT_MUTED on PANEL", UiTheme.TEXT_MUTED, UiTheme.PANEL],
		["GOLD on SURFACE", UiTheme.GOLD, UiTheme.SURFACE],
		["SAFE on SURFACE", UiTheme.SAFE, UiTheme.SURFACE],
		["CAUTION on SURFACE", UiTheme.CAUTION, UiTheme.SURFACE],
		["DANGER on SURFACE", UiTheme.DANGER, UiTheme.SURFACE],
		["FOCUS on PANEL", UiTheme.FOCUS, UiTheme.PANEL],
	]
	for e in entries:
		var name: String = e[0]
		var fg: Color = e[1]
		var bg: Color = e[2]
		var ratio := UiTheme.contrast_ratio(fg, bg)
		var swatch := _swatch(fg, bg, 64)
		grid.add_child(swatch)
		var lbl := UiTheme.body_text("%s\n%.2f:1  %s" % [name, ratio, ("PASS AA" if ratio >= 4.5 else ("PASS non-text (3:1)" if ratio >= 3.0 else "FAIL"))], "muted")
		grid.add_child(lbl)

	var wrap := VBoxContainer.new()
	wrap.add_child(grid)
	return wrap


func _swatch(fg: Color, bg: Color, sz: int) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(sz, sz * 0.5)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(UiTheme.RADIUS_SM)
	p.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = "Aa"
	lbl.add_theme_color_override("font_color", fg)
	lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_HEADING)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p.add_child(lbl)
	return p


# -- 2. Type scale ----------------------------------------------------------

func _build_type_scale_section() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	var sizes := [
		["SIZE_DISPLAY (32)", UiTheme.SIZE_DISPLAY],
		["SIZE_HEADING (22)", UiTheme.SIZE_HEADING],
		["SIZE_SUBHEADING (18) — accessibility floor", UiTheme.SIZE_SUBHEADING],
		["SIZE_BODY (16)", UiTheme.SIZE_BODY],
		["SIZE_CAPTION (14)", UiTheme.SIZE_CAPTION],
	]
	for s in sizes:
		var lbl := Label.new()
		lbl.text = s[0]
		lbl.add_theme_font_size_override("font_size", s[1])
		lbl.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY)
		col.add_child(lbl)
	return col


# -- 3. Spacing + radii -------------------------------------------------------

func _build_spacing_section() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	var spaces := [
		["XS", UiTheme.SPACE_XS], ["SM", UiTheme.SPACE_SM], ["MD", UiTheme.SPACE_MD],
		["LG", UiTheme.SPACE_LG], ["XL", UiTheme.SPACE_XL], ["XXL", UiTheme.SPACE_XXL],
	]
	for s in spaces:
		var box := VBoxContainer.new()
		var block := ColorRect.new()
		block.color = UiTheme.GOLD
		block.custom_minimum_size = Vector2(s[1], s[1])
		box.add_child(block)
		box.add_child(UiTheme.body_text("%s (%dpx)" % [s[0], s[1]], "muted"))
		row.add_child(box)
	return row


# -- 4. Panels + buttons ------------------------------------------------------

func _build_panel_button_section() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_LG)

	var p1 := PanelContainer.new()
	p1.custom_minimum_size = Vector2(160, 60)
	p1.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	p1.add_child(UiTheme.body_text("panel_style(\"default\")", "secondary"))
	row.add_child(p1)

	var p2 := PanelContainer.new()
	p2.custom_minimum_size = Vector2(160, 60)
	p2.add_theme_stylebox_override("panel", UiTheme.panel_style("raised", UiTheme.GOLD))
	p2.add_child(UiTheme.body_text("panel_style(\"raised\")", "secondary"))
	row.add_child(p2)

	var btn_col := VBoxContainer.new()
	btn_col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	for kind in ["secondary", "primary", "danger"]:
		var b := Button.new()
		b.text = kind
		b.custom_minimum_size = Vector2(120, 32)
		var sb := UiTheme.button_stylebox(kind, "normal")
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", UiTheme.button_stylebox(kind, "hover"))
		b.add_theme_stylebox_override("pressed", UiTheme.button_stylebox(kind, "pressed"))
		b.add_theme_stylebox_override("focus", UiTheme.button_stylebox(kind, "focus"))
		btn_col.add_child(b)
	row.add_child(btn_col)

	return row


# -- 5. Bars ------------------------------------------------------------------

func _build_bars_section() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	col.add_child(UiTheme.stat_bar("STR", 340, 500, UiTheme.GOLD))
	col.add_child(UiTheme.stat_bar("WIS", 120, 500, UiTheme.GOLD))

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	hp_row.add_child(UiTheme.hp_bar(88, 100))
	hp_row.add_child(UiTheme.hp_bar(38, 100))
	hp_row.add_child(UiTheme.hp_bar(9, 100))
	col.add_child(hp_row)
	col.add_child(UiTheme.body_text("hp_bar() at 88%, 38%, 9% — colour AND the printed value change together", "muted"))
	return col


# -- 6. Team chips --------------------------------------------------------------

func _build_team_section() -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", UiTheme.SPACE_LG)
	grid.add_theme_constant_override("v_separation", UiTheme.SPACE_SM)
	for i in range(8):
		var chip := UiTheme.team_chip(i, "Team %d" % i)
		grid.add_child(chip)
	return grid


# -- 7. Status chips ------------------------------------------------------------

func _build_status_section() -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", UiTheme.SPACE_MD)
	flow.add_theme_constant_override("v_separation", UiTheme.SPACE_SM)
	for status_name in UiTheme.STATUS_META.keys():
		flow.add_child(UiTheme.status_chip(status_name))
	return flow


# -- 8. Before / after ----------------------------------------------------------

func _build_before_after_section() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_LG)

	# BEFORE — the pattern already live in stable_ui.gd/tactics_ui.gd/arena_3d.gd: a fresh
	# StyleBoxFlat, hand-picked colours, invented on the spot.
	var before := PanelContainer.new()
	before.custom_minimum_size = Vector2(220, 80)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.15)
	sb.border_color = Color(0.22, 0.22, 0.26)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	before.add_theme_stylebox_override("panel", sb)
	var before_lbl := Label.new()
	before_lbl.text = "BEFORE\nHand-rolled StyleBoxFlat,\ninvented per screen"
	before_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	before.add_child(before_lbl)
	row.add_child(before)

	# AFTER — one call, tokens shared with every other screen.
	var after := PanelContainer.new()
	after.custom_minimum_size = Vector2(220, 80)
	after.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	var after_lbl := UiTheme.body_text("AFTER\nUiTheme.panel_style(\"default\")\nsame tokens, every screen", "secondary")
	after.add_child(after_lbl)
	row.add_child(after)

	return row


# -- 9. Monster card ------------------------------------------------------------

## Five screens hand-roll a portrait today (stable/market/report/tactics/ending) with three
## different signatures, and seven more name a monster while showing none. This is the one shape.
func _build_card_section() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_SM)

	col.add_child(UiTheme.monster_card({
		"species_id": "aegisox", "name": "Terrock", "subtitle": "Tank · support",
		"note": "● Growing — 6y left of 8y", "note_colour": UiTheme.SAFE,
		"chips": [UiTheme.delta_chip(9, "STR"), UiTheme.delta_chip(-15, "stamina")],
	}, {"selected": true}))

	col.add_child(UiTheme.monster_card({
		"species_id": "corvaan", "name": "Cobalon", "subtitle": "Wizard · damage",
		"note": "● At cap — 4y left of 8y", "note_colour": UiTheme.GOLD,
		"trailing": UiTheme.body_text("Recruit · 365g", "secondary"),
	}))

	# The deliberate degrade: an unknown species id, so `Art.creature_texture()` returns null and
	# the placeholder renders at the SAME footprint. This row is the proof the layout does not
	# jump the moment art lands mid-session.
	col.add_child(UiTheme.monster_card({
		"species_id": "no_such_species", "name": "Unarted", "subtitle": "Art.* returned null",
		"note": "the placeholder is the contract, not a fallback nobody sees",
	}, {"focusable": false}))
	return col


# -- 10. Cap bar ----------------------------------------------------------------

func _build_capbar_section() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	col.add_child(UiTheme.body_text(
		"Round 18 found the stable reading 115 / 540 and training reading 115 / 400 for the SAME " +
		"stat in the SAME week. Both were true of a different 'max'. One bar that draws all three " +
		"quantities — where it is, the ceiling, the scale — makes that lie unspeakable.", "secondary"))
	col.add_child(UiTheme.stat_bar("STR", 130, 400, UiTheme.GOLD, 40, 1100))
	col.add_child(UiTheme.stat_bar("CON", 340, 540, UiTheme.GOLD, 40, 1100))
	col.add_child(UiTheme.stat_bar("WIS", 88, 400, UiTheme.GOLD, 40, 1100))
	col.add_child(UiTheme.body_text(
		"fill = now · white tick = this monster's ceiling · dark band = the scale it can never " +
		"reach. Old two-argument callers get no dead zone and no tick — unchanged.", "muted"))
	col.add_child(UiTheme.stat_bar("DEX", 300, 500, UiTheme.GOLD))
	return col


# -- 11. Delta chips -------------------------------------------------------------

func _build_delta_section() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", UiTheme.SPACE_SM)
	row.add_theme_constant_override("v_separation", UiTheme.SPACE_XS)
	row.add_child(UiTheme.delta_chip(9, "STR"))
	row.add_child(UiTheme.delta_chip(-4, "DEX"))
	row.add_child(UiTheme.delta_chip(0, "CON"))
	row.add_child(UiTheme.delta_chip(-15, "stamina"))
	row.add_child(UiTheme.delta_chip(107, "g"))
	row.add_child(UiTheme.delta_chip(-1, "happiness"))
	row.add_child(UiTheme.delta_chip(40, "g upkeep", false))
	row.add_child(UiTheme.delta_chip(1.2, "potential", true, 2))
	col.add_child(row)
	col.add_child(UiTheme.body_text(
		"Sign is a GLYPH as well as a colour (▲ ▼ •), so a training week reads without the hue. " +
		"Default: bigger is better, so −15 stamina is amber. good_is_up=false flips it for a " +
		"quantity where SMALLER is better — +40g of upkeep is amber going UP.", "muted"))
	return col


# -- 12. Comparison row ----------------------------------------------------------

func _build_compare_section() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(110, 0)
	head.add_child(spacer)
	for n in ["Terrock (sire)", "Rosewing (dam)"]:
		var h := UiTheme.heading(n, 2)
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(h)
	var vspacer := Control.new()
	vspacer.custom_minimum_size = Vector2(180, 0)
	head.add_child(vspacer)
	col.add_child(head)

	col.add_child(UiTheme.comparison_row("Potential", "×1.00 Gen 1", "×1.14 Gen 3", "child inherits ×1.14", 2))
	col.add_child(UiTheme.comparison_row("Best stat", "CON 340", "CHA 291", "sire leads by 49", 1))
	col.add_child(UiTheme.comparison_row("Age", "5y of 8y", "7y of 8y", "dam has one season left", 1))
	col.add_child(UiTheme.comparison_row("Heirloom", "none", "Hymn of Shields", "only the dam can bequeath", 2))
	col.add_child(UiTheme.body_text(
		"Round 18 found five breeding rows all reading 'potential ×1.00 · Wild stock — Gen 1'. " +
		"Five values with no difference between them is a list, not a choice.", "muted"))
	return col


# -- 13. Empty state + disabled-with-a-reason ------------------------------------

func _build_empty_section() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	col.add_child(UiTheme.empty_state(
		"The freezer is empty",
		"Preserved bodies appear here when a monster retires. Nothing has retired yet — " +
		"your oldest is Rosewing, 7y of 8y.",
		"Go to the Stable"))

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	var locked := Button.new()
	locked.text = "Barn Extension · 900g"
	UiTheme.disable_with_reason(locked, "Locked — reach Iron league (you are Bronze)", true)
	btn_row.add_child(locked)
	var broke := Button.new()
	broke.text = "Breed"
	UiTheme.disable_with_reason(broke, "Needs two unretired parents; you have one")
	btn_row.add_child(broke)
	col.add_child(btn_row)
	col.add_child(UiTheme.body_text(
		"disable_with_reason() makes the reason a REQUIRED argument — the rule is enforced by " +
		"the signature, not by memory. in_label=true puts it in the visible text (left), which " +
		"beats a tooltip a keyboard user never hovers.", "muted"))
	return col


# -- 14. Commit bar --------------------------------------------------------------

func _build_commit_section() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_MD)

	var ready_bar := UiTheme.commit_bar(
		"5 monsters · 4 have a plan · this week costs 0 gold and 80 stamina", "Advance Week")
	col.add_child(ready_bar)

	var blocked := UiTheme.commit_bar("", "Commit and fight")
	UiTheme.commit_bar_set(blocked, "", false, "Two of five have no station — drag them onto the board")
	col.add_child(blocked)

	col.add_child(UiTheme.body_text(
		"Add it as a SIBLING of the ScrollContainer, never inside it. Round 18 could not find a " +
		"commit button on the tactics screen at 1152x648 in either capture — this is the shape " +
		"that cannot be lost below the fold, and cannot be disabled without saying why.", "muted"))
	return col


# -- 15. The same monster, three screens ----------------------------------------

## ⚠️ THE ACCEPTANCE TEST FOR THIS WHOLE FILE, PUT ON THE SCREEN RATHER THAN ASSERTED.
## The brief's bar was "a capture of three different screens side by side reads as ONE game".
## Three screens cannot be composited into one capture, so this section does the honest
## equivalent: ONE monster, rendered THREE TIMES, in each screen's current treatment — copied
## line-for-line from the live files, not caricatured — and then once through `monster_card()`.
##
## The three treatments below are verbatim:
##   stable_ui.gd:295-321   portrait 48 · name at SIZE_BODY · class at SIZE_CAPTION · state chip
##   market_ui.gd:262-282   portrait 34 · name at 15px in a grade colour · body at 12px grey
##   report_ui.gd:960-996   portrait 40 · name at theme default · dealt/took at 12px sage green
##
## They are not variations on a house style. They are three house styles.
func _build_three_screens_section() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_MD)

	col.add_child(UiTheme.body_text(
		"One monster, three screens, as they render TODAY — each block copied from the live file. " +
		"Read the three together: three portrait sizes, three name sizes, three greys, three " +
		"ideas of what a row of a monster is.", "secondary"))

	var today := HBoxContainer.new()
	today.add_theme_constant_override("separation", UiTheme.SPACE_LG)
	today.add_child(_today_stable())
	today.add_child(_today_market())
	today.add_child(_today_report())
	col.add_child(today)

	col.add_child(HSeparator.new())
	col.add_child(UiTheme.body_text("The same three rows through monster_card():", "secondary"))

	var after := HBoxContainer.new()
	after.add_theme_constant_override("separation", UiTheme.SPACE_LG)
	for spec in [
		{"note": "● Growing — 6y left of 8y", "note_colour": UiTheme.SAFE, "trailing": null, "sel": true},
		{"note": "Prospect · ceiling 400 (×1.00)", "note_colour": UiTheme.TEXT_MUTED, "trailing": "Recruit · 173g", "sel": false},
		{"note": "dealt 130 · took 399 · fell at 6.2s", "note_colour": UiTheme.TEXT_MUTED, "trailing": null, "sel": false},
	]:
		var info := {
			"species_id": "aegisox", "name": "Terrock", "subtitle": "Mammal · Tank · support",
			"note": spec["note"], "note_colour": spec["note_colour"],
		}
		if spec["trailing"] != null:
			info["trailing"] = UiTheme.body_text(str(spec["trailing"]), "secondary")
		var card := UiTheme.monster_card(info, {"selected": spec["sel"], "focusable": false})
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		after.add_child(card)
	col.add_child(after)

	col.add_child(UiTheme.body_text(
		"⚠️ The components exist; the three screens do not call them yet, and converting them is " +
		"not this stream's file to touch. The measurable target is _probe_house.gd's last two " +
		"columns reaching zero on report_ui / tactics_ui / market_ui.", "muted"))
	return col


func _label(parent: Node, text: String, fsize: int, col: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	parent.add_child(l)


func _today_panel(title: String) -> Array:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	box.add_child(UiTheme.body_text(title, "muted"))
	var panel := PanelContainer.new()
	box.add_child(panel)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	panel.add_child(hbox)
	return [box, panel, hbox]


## stable_ui.gd — 48px portrait, name at SIZE_BODY, class at SIZE_CAPTION, a coloured state chip.
func _today_stable() -> Control:
	var parts := _today_panel("stable_ui.gd (theme-adopted)")
	var panel: PanelContainer = parts[1]
	var hbox: HBoxContainer = parts[2]
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("raised", UiTheme.GOLD))
	hbox.add_child(UiTheme.portrait("aegisox", "Terrock", Vector2(48, 48), UiTheme.GOLD))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(col)
	col.add_child(UiTheme.body_text("Terrock", "primary"))
	_label(col, "Tank · support", UiTheme.SIZE_CAPTION, UiTheme.TEXT_SECONDARY)
	_label(col, "● Growing", UiTheme.SIZE_CAPTION, UiTheme.SAFE)
	return parts[0]


## market_ui.gd — 34px portrait, name at 15px in a per-grade amber, body line at 12px grey
## Color(0.65,0.65,0.7), aptitude line at 12px in the file's own FOCUS_COLOR.
func _today_market() -> Control:
	var parts := _today_panel("market_ui.gd (never adopted)")
	var panel: PanelContainer = parts[1]
	var hbox: HBoxContainer = parts[2]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.13, 0.17)
	sb.border_color = Color(0.22, 0.22, 0.26)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	hbox.add_child(UiTheme.portrait("aegisox", "Terrock", Vector2(34, 34), Color(0.9, 0.75, 0.4)))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(col)
	_label(col, "Terrock — Prospect", 15, Color(0.9, 0.75, 0.4))
	_label(col, "Mammal · Tank", 12, Color(0.65, 0.65, 0.7))
	_label(col, "now 91/stat · ceiling 400 (×1.00) · 7y left of 8y", 11, Color(0.6, 0.6, 0.65))
	_label(col, "trains: STR ×1.20, WIS ×1.10, DEX ×0.95", 12, Color(0.4, 0.65, 0.95))
	return parts[0]


## report_ui.gd — 40px portrait, name at the theme's default size in Color(0.9,0.9,0.93),
## dealt/took at 12px in a sage Color(0.7,0.75,0.7), orders line at 12px in a fourth warm grey.
func _today_report() -> Control:
	var parts := _today_panel("report_ui.gd (never adopted)")
	var panel: PanelContainer = parts[1]
	var hbox: HBoxContainer = parts[2]
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.1)
	sb.border_color = Color(0.26, 0.43, 0.65)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	hbox.add_child(UiTheme.portrait("aegisox", "Terrock", Vector2(40, 40), Color(0.2, 0.38, 0.62)))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(col)
	_label(col, "Terrock  (fallen)", 16, Color(0.9, 0.9, 0.93))
	_label(col, "dealt 130 · took 399", 12, Color(0.7, 0.75, 0.7))
	_label(col, "◆ Hold · ⚑ Team default", 12, Color(0.82, 0.78, 0.62))
	_label(col, "▸ Orders & decision log", 11, Color(0.6, 0.6, 0.68))
	return parts[0]


# =============================================================================
# 16-20. THE CRAFT ROUND SECTIONS (2026-08-13)
#
# ⚠️ EVERY NUMBER BELOW IS TAKEN LIVE, NEVER QUOTED. `contrast_ratio()` and `Font.has_char()`
# are called at build time against the tokens and the packaged face as they exist right now, so
# improving `theme.gd` moves these readings on its own. A gallery that printed the audit's
# figures as string literals would keep its own copy of the truth and drift from it — the exact
# failure UI_LAYOUT_RULES R7 exists to stop.
# =============================================================================

## A non-wrapping body label, for use inside an HBox/GridContainer cell.
##
## ⚠️ `body_text()` SETS AUTOWRAP_WORD, WHICH IS RIGHT FOR A PARAGRAPH AND WRONG IN A ROW — and
## this is the SECOND time that has been found by reading a capture rather than by reading code.
## UI_THEME.md §6 records the first: a `monster_card` trailing slot that wrapped a price over
## three lines and slid off the card edge. Sections 17, 18 and 20 reproduced it exactly — the
## glyph table came out one word per line, unreadable — because a Label with no width constraint
## inside a horizontal container gets a minimum width of one word and the container honours it.
## Call this for anything that sits in a row.
func _inline(text: String, tier: String = "primary", min_w: int = 0) -> Label:
	var l: Label = UiTheme.body_text(text, tier)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	if min_w > 0:
		l.custom_minimum_size = Vector2(min_w, 0)
	return l


## Format a ratio with a PASS/FAIL against the target from docs/POLISH_DIRECTION.md §6.
func _ratio_label(text: String, a: Color, b: Color, target: float) -> Label:
	var r: float = UiTheme.contrast_ratio(a, b)
	var lbl := Label.new()
	lbl.text = "%s  %.3f : 1   (target >= %.2f)  %s" % [text, r, target, "OK" if r >= target else "UNDER"]
	lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	lbl.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY if r >= target else UiTheme.DANGER)
	return lbl


# -- 16. Elevation ------------------------------------------------------------
#
# ⚠️ THE POINT OF THIS SECTION IS THAT THE THREE PANELS TOUCH. Section 4 already draws a
# "default" and a "raised" panel — with 16px of page between them, which is precisely the gap
# that hides the problem. Nested and edge-to-edge, page->card->raised is one rectangle with two
# hairlines in it, and that is what thirteen screens actually look like.

func _build_elevation_section() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_SM)

	col.add_child(UiTheme.body_text(
		"SURFACE (page) -> PANEL (card) -> PANEL_RAISED (raised), NESTED and touching — the way " +
		"they meet on a real screen. Every panel in the game is separated from its page by a " +
		"1px border and nothing else.", "secondary"))

	var page := PanelContainer.new()
	page.custom_minimum_size = Vector2(560, 150)
	var page_sb := StyleBoxFlat.new()
	page_sb.bg_color = UiTheme.SURFACE
	page_sb.content_margin_left = UiTheme.SPACE_XL
	page_sb.content_margin_top = UiTheme.SPACE_XL
	page_sb.content_margin_right = UiTheme.SPACE_XL
	page_sb.content_margin_bottom = UiTheme.SPACE_XL
	page.add_theme_stylebox_override("panel", page_sb)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	page.add_child(card)

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	card.add_child(inner)
	inner.add_child(UiTheme.body_text("PANEL — a card, on the page", "primary"))
	inner.add_child(UiTheme.body_text("TEXT_MUTED inside a card", "muted"))

	var raised := PanelContainer.new()
	raised.add_theme_stylebox_override("panel", UiTheme.panel_style("raised", UiTheme.BORDER))
	var raised_col := VBoxContainer.new()
	raised.add_child(raised_col)
	raised_col.add_child(UiTheme.body_text("PANEL_RAISED — a raised card, inside it", "primary"))
	raised_col.add_child(UiTheme.body_text("TEXT_MUTED on raised — the tightest ratio in the theme", "muted"))
	inner.add_child(raised)

	col.add_child(page)

	col.add_child(_ratio_label("page -> card    SURFACE vs PANEL          ",
		UiTheme.SURFACE, UiTheme.PANEL, 1.16))
	col.add_child(_ratio_label("card -> raised  PANEL vs PANEL_RAISED     ",
		UiTheme.PANEL, UiTheme.PANEL_RAISED, 1.16))
	col.add_child(_ratio_label("border edge     BORDER vs PANEL           ",
		UiTheme.BORDER, UiTheme.PANEL, 1.30))

	col.add_child(UiTheme.body_text(
		"⚠ THE REGRESSION TRIPWIRES. Elevation must NOT be bought by lifting the fills — the " +
		"text contrast budget is already spent. Neither of these two may fall:", "secondary"))
	# ⚠️ THE TARGETS ARE 5.09 AND 4.62, NOT THE 5.10 AND 4.63 QUOTED IN UI_THEME.md §3 AND IN THE
	# FIRST DRAFT OF POLISH_DIRECTION.md. Measured live here, these are 5.098 and 4.628 — the
	# published figures were rounded UP, so a tripwire set at the published value fails against the
	# untouched theme and would have reported a regression on the first run of any builder's diff.
	# Found by this section on its own first capture, which is the entire argument for it existing.
	col.add_child(_ratio_label("TEXT_MUTED on PANEL        (AA floor 4.5) ",
		UiTheme.TEXT_MUTED, UiTheme.PANEL, 5.09))
	col.add_child(_ratio_label("TEXT_MUTED on PANEL_RAISED (AA floor 4.5) ",
		UiTheme.TEXT_MUTED, UiTheme.PANEL_RAISED, 4.62))
	# ⚠️ THIS ONE IS *MEANT* TO READ UNDER. DANGER measures 4.226:1 on SURFACE — genuinely below
	# the 4.5 AA floor for normal text, exactly as theme.gd's own token comment warns. It is a
	# live finding, not a broken target, and C1's SURFACE darkening is what clears it.
	col.add_child(_ratio_label("DANGER on SURFACE          (AA floor 4.5) ",
		UiTheme.DANGER, UiTheme.SURFACE, 4.50))
	return col


# -- 17. Interactive states ---------------------------------------------------
#
# ⚠️ A LIVE Button CAN ONLY EVER BE IN ONE STATE, so section 4's three real buttons show three
# resting states and nothing else. That is why "pressed is 1.069:1 from normal" — a change no
# eye can resolve — survived a gallery whose entire job was showing button states. Here every
# state of every kind is drawn as a static panel with its own stylebox, all visible at once.

func _build_states_section() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	col.add_child(UiTheme.body_text(
		"Each cell draws button_stylebox(kind, state) directly. A real Button shows one state at " +
		"a time and hides the rest — this grid is the only place they can be compared.",
		"secondary"))

	var states := ["normal", "hover", "pressed", "disabled", "focus"]
	var grid := GridContainer.new()
	grid.columns = states.size() + 1
	grid.add_theme_constant_override("h_separation", UiTheme.SPACE_SM)
	grid.add_theme_constant_override("v_separation", UiTheme.SPACE_SM)

	grid.add_child(UiTheme.body_text("", "muted"))
	for s in states:
		grid.add_child(UiTheme.body_text(s, "secondary"))

	for kind in ["secondary", "primary", "danger"]:
		grid.add_child(UiTheme.body_text(kind, "secondary"))
		for s in states:
			var cell := PanelContainer.new()
			cell.custom_minimum_size = Vector2(112, 40)
			cell.add_theme_stylebox_override("panel", UiTheme.button_stylebox(kind, s))
			var t := Label.new()
			t.text = "Book"
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			t.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
			t.add_theme_color_override("font_color",
				UiTheme.TEXT_MUTED if s == "disabled" else UiTheme.TEXT_PRIMARY)
			cell.add_child(t)
			grid.add_child(cell)
	col.add_child(grid)

	# How far each state actually travels from resting, measured on the "secondary" kind — the one
	# base_theme() hands to every default Button, i.e. the ~30 "Book" buttons on the training
	# screen and every navigation button in the game.
	var base: StyleBoxFlat = UiTheme.button_stylebox("secondary", "normal")
	for s in ["hover", "pressed", "disabled"]:
		var sb: StyleBoxFlat = UiTheme.button_stylebox("secondary", s)
		var target: float = 1.45 if s == "hover" else (1.25 if s == "pressed" else 1.20)
		col.add_child(_ratio_label("normal -> %-9s (fill vs fill)      " % s,
			base.bg_color, sb.bg_color, target))
	col.add_child(UiTheme.body_text(
		"⚠ Pressed must also be GEOMETRICALLY distinct, not merely darker — a fill delta alone " +
		"is not click feedback. The fill is the number; losing the shadow is the feeling.", "muted"))

	# The dead-control rule, shown rather than described: the reason belongs in the LABEL, because
	# a keyboard user never hovers a tooltip (UI_LAYOUT_RULES R3).
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	var bad := Button.new()
	bad.text = "Recruit · 173g"
	bad.custom_minimum_size = Vector2(210, 34)
	bad.disabled = true
	row.add_child(bad)
	var good := Button.new()
	good.text = "Recruit · 173g"
	good.custom_minimum_size = Vector2(210, 34)
	UiTheme.disable_with_reason(good, "Barn full", true)
	row.add_child(good)
	row.add_child(_inline(
		"left: btn.disabled = true (banned) · right: disable_with_reason(…, in_label = true)", "muted"))
	col.add_child(row)
	return col


# -- 18. Ability icons --------------------------------------------------------
#
# ⚠️ 141 ICONS SHIP AND ONE FILE LOADS THEM (arena_3d.gd:3894). Every meta screen that lists a
# moveset — Stable, Report, Tactics, Breeding, Lab, Market — renders ability names as plain text
# while this sits on disk. Drawn here at the three sanctioned sizes so a builder can see what an
# inline icon costs a row before wiring one in.

const ICON_DIR := "res://assets/icons/abilities/"
const ICON_SAMPLE := ["STR-0", "STR-7", "STR-15", "DEX-0", "DEX-9", "DEX-18",
	"CON-0", "CON-8", "CON-16", "WIS-0", "WIS-9", "WIS-17",
	"INT-0", "INT-8", "INT-16", "CHA-0", "CHA-9", "CHA-18"]


func _icon_rect(move_id: String, px: int) -> Control:
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var path := ICON_DIR + move_id + ".png"
	if ResourceLoader.exists(path):
		tr.texture = load(path) as Texture2D
	return tr


func _build_icons_section() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_SM)

	var found := 0
	var dir := DirAccess.open(ICON_DIR)
	if dir != null:
		for f in dir.get_files():
			if f.ends_with(".png"):
				found += 1
	col.add_child(UiTheme.body_text(
		"%d icons on disk at %s — 64x64 RGBA, addressed by MOVE ID, loaded today by exactly one "
		% [found, ICON_DIR] + "file. Three per stat, sampled:", "secondary"))

	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", UiTheme.SPACE_SM)
	grid.add_theme_constant_override("v_separation", UiTheme.SPACE_SM)
	for id in ICON_SAMPLE:
		var cell := VBoxContainer.new()
		cell.add_child(_icon_rect(id, 48))
		cell.add_child(_inline(id, "muted"))
		grid.add_child(cell)
	col.add_child(grid)

	col.add_child(UiTheme.body_text(
		"The three sanctioned sizes — 24px inline, 32px in a list, 48px in a picker. ⚠ AN ICON " +
		"GOES BESIDE A NAME, NEVER INSTEAD OF ONE: these are abstract marks and nobody reads " +
		"three slashes as \"Rend\". Their job is scanning and stat colour, not naming.",
		"secondary"))

	for px in [24, 32, 48]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiTheme.SPACE_SM)
		row.add_child(_inline("%dpx" % px, "muted", 44))
		for pair in [["STR-0", "Rend"], ["WIS-0", "Mend"], ["INT-8", "Hex"]]:
			row.add_child(_icon_rect(pair[0], px))
			row.add_child(_inline(pair[1], "primary", 56))
		col.add_child(row)

	# The degrade case. UiTheme.portrait() already establishes the rule — a missing asset keeps
	# the SAME footprint so nothing reflows the day art lands. An icon must do the same.
	var miss := HBoxContainer.new()
	miss.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	miss.add_child(_icon_rect("NOPE-999", 32))
	miss.add_child(_inline(
		"a missing icon must hold its footprint, never collapse — the portrait() rule", "muted"))
	col.add_child(miss)
	return col


# -- 19. Stat hues ------------------------------------------------------------
#
# ⚠️ THESE ARE NOT NEW COLOURS. They are sampled out of the 141 icons above, which have carried a
# designed six-hue stat system since the day they were generated without anyone naming it. The
# stable screen meanwhile draws all six of its stat bars in one identical blue.
#
# ⚠️ AND THE COLLISION IS REAL: the CHA hue is 1.012:1 from GOLD — the same colour. Resolved by
# ROLE, not by hue: GOLD is an INK and never a FILL; a stat hue is a FILL or a GLYPH and never an
# INK. They then never appear in a comparable role. See docs/POLISH_DIRECTION.md §3.3.

## ⚠️ READ LIVE FROM `UiTheme.STAT_HUES`, NEVER COPIED. This was a `const` here for exactly one
## round, and a gallery holding its own copy of the values it exists to document is the single
## worst place in the project for that copy to live: it would keep rendering the OLD hue, in the
## page whose entire job is to show what the theme actually publishes, on the day someone retunes
## CON. Every other number on these pages is taken live for the same reason.


func _build_stathue_section() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	col.add_child(UiTheme.body_text(
		"Sampled from the icon set above — not invented here. Left: the six bars as the Stable " +
		"draws them today, in one colour. Right: the same six with their own hue as FILL.",
		"secondary"))

	var order := ["STR", "DEX", "CON", "WIS", "INT", "CHA"]
	var vals := {"STR": 130.0, "DEX": 87.0, "CON": 174.0, "WIS": 120.0, "INT": 115.0, "CHA": 118.0}
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", UiTheme.SPACE_XL)

	var before := VBoxContainer.new()
	before.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	before.add_child(UiTheme.body_text("today — six bars, one fill", "muted"))
	for s in order:
		before.add_child(UiTheme.stat_bar(s, vals[s], 400.0, Color(0.26, 0.43, 0.65), 40, 540.0))
	pair.add_child(before)

	var after := VBoxContainer.new()
	after.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	after.add_child(UiTheme.body_text("proposed — the stat's own hue as fill", "muted"))
	for s in order:
		after.add_child(UiTheme.stat_bar(s, vals[s], 400.0, UiTheme.STAT_HUES[s], 40, 540.0))
	pair.add_child(after)
	col.add_child(pair)

	col.add_child(_ratio_label("⚠ GOLD vs the CHA stat hue — the collision ",
		UiTheme.GOLD, UiTheme.STAT_HUES["CHA"], 1.30))
	col.add_child(_ratio_label("⚠ GOLD vs CAUTION — two tokens, one colour ",
		UiTheme.GOLD, UiTheme.CAUTION, 1.30))
	col.add_child(UiTheme.body_text(
		"Both read UNDER on purpose: they are findings, not failures of this screen. The fix is " +
		"the role rule above, plus retiring CAUTION as a TEXT ink — it survives as a fill and a " +
		"mark. Guild Colours is unaffected: a stat hue never touches arena stone, a nameplate " +
		"frame, or a status chip.", "muted"))
	return col


# -- 20. Glyph coverage -------------------------------------------------------
#
# ⚠️ THE FINDING THAT OUTRANKS THE POLISH. project.godot sets no font, so every screen renders in
# Godot's embedded Open Sans SemiBold — which contains almost none of the marks the meta UI
# prints. They appear on screen anyway because a system font is silently supplying them, which
# makes every one of them a platform-dependent accident that tofus on any machine without it.
# Round 19 shipped exactly this bug in ONE place and it was caught by eye; scripts/ui/*.gd carries
# 47 distinct such glyphs in 178 occurrences.
#
# ⚠️ SO THIS SECTION IS A TRAP FOR ITSELF: it draws each glyph next to its own has_char(). If a
# row says MISSING and you can still SEE the glyph in the left column, that IS the bug, rendered.

const GLYPH_PROBE := [
	["→", 0x2192, "every training card's payoff"],
	["⚠", 0x26A0, "every warning in the game"],
	["✓", 0x2713, "the Report's HELD verdict"],
	["✗", 0x2717, "the Report's BROKE verdict"],
	["▲", 0x25B2, "RIVAL TEAM marker"],
	["◆", 0x25C6, "YOUR TEAM marker"],
	["●", 0x25CF, "roster status dot"],
	["★", 0x2605, "bloodline potential"],
	["♥", 0x2665, "favourite food"],
	["▶", 0x25B6, "disclosure arrow"],
	["·", 0x00B7, "the separator — PACKAGED"],
	["•", 0x2022, "bullet — PACKAGED"],
	["×", 0x00D7, "multiplier — PACKAGED"],
	["−", 0x2212, "minus — PACKAGED"],
]


func _build_glyph_section() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_SM)

	var f: Font = ThemeDB.get_default_theme().get_font("font", "Label")
	col.add_child(UiTheme.body_text(
		"Packaged face: %s. has_char() asked live, per codepoint." % f.get_font_name(), "secondary"))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", UiTheme.SPACE_LG)
	grid.add_theme_constant_override("v_separation", UiTheme.SPACE_XS)
	var widths := [60, 110, 130, 0]
	var heads := ["glyph", "codepoint", "in packaged font", "where it is used"]
	for i in heads.size():
		grid.add_child(_inline(heads[i], "secondary", widths[i]))

	var missing := 0
	for row in GLYPH_PROBE:
		var cp: int = row[1]
		var has: bool = f.has_char(cp)
		if not has:
			missing += 1
		var g := Label.new()
		g.text = str(row[0])
		g.custom_minimum_size = Vector2(widths[0], 0)
		g.add_theme_font_size_override("font_size", UiTheme.SIZE_HEADING)
		g.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY)
		grid.add_child(g)
		grid.add_child(_inline("U+%04X" % cp, "muted", widths[1]))
		var verdict := Label.new()
		verdict.text = "yes" if has else "MISSING"
		verdict.custom_minimum_size = Vector2(widths[2], 0)
		verdict.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
		verdict.add_theme_color_override("font_color", UiTheme.SAFE if has else UiTheme.DANGER)
		grid.add_child(verdict)
		grid.add_child(_inline(str(row[2]), "muted"))
	col.add_child(grid)

	var verdict_line := Label.new()
	verdict_line.text = "%d of %d probed glyphs are NOT in the packaged font." % [missing, GLYPH_PROBE.size()]
	verdict_line.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBHEADING)
	verdict_line.add_theme_color_override("font_color", UiTheme.DANGER if missing > 0 else UiTheme.SAFE)
	col.add_child(verdict_line)
	col.add_child(UiTheme.body_text(
		"If a row reads MISSING and the glyph is still visible on the left, a system font outside " +
		"the export is drawing it. THAT is the defect. The fix is not a better glyph — it is a " +
		"drawn mark() component, the way status_chip() already draws its shapes in code and is " +
		"the one glyph system here that cannot tofu.", "secondary"))
	return col


# =============================================================================
# SELF-CAPTURE — `--capture` walks the gallery's own scroll and writes user://gallery/NN.png.
#
# ⚠️ A POLISH ROUND WITHOUT A PLACE TO COMPARE COMPONENTS IS DONE BLIND, and a gallery nobody can
# read back is exactly that place missing. `_probe_screens.gd` captures thirteen screens and not
# this one, so until now the only way to review the component library was to open it by hand and
# look — which is why sections 16-20's findings survived a gallery built to prevent them.
#
# ⚠️ THE BLANK-FRAME CANARY IS THE SAME CONTRACT AS `_probe_screens.gd:_shoot`. A uniform frame is
# a FAILURE, not an output: run headless and the dummy renderer hands back blank images while the
# log prints "captures: ..." exactly as a good run does. Exits NON-ZERO if any capture was blank.
# =============================================================================

func _capture_walk() -> void:
	DisplayServer.window_set_size(WINDOW)
	DirAccess.make_dir_recursive_absolute(OUT_DIR)

	# ⚠️ SWEEP THE DIRECTORY FIRST, AND THIS IS NOT HOUSEKEEPING. The page count is derived from
	# content height, so a run that gets SHORTER leaves the previous run's tail pages behind at
	# their old timestamps — and they are indistinguishable from output. This exact thing happened
	# on the second run of this file: fixing an autowrap bug took the gallery from 8 pages to 7 and
	# left a stale `08.png` sitting in the directory. Reading a capture nothing wrote any more is
	# the failure the round's brief opens with ("I just spent three attempts fixing a bug that was
	# already fixed"). A file that is not output must not be present.
	var stale := DirAccess.open(OUT_DIR)
	if stale != null:
		for f in stale.get_files():
			if f.ends_with(".png"):
				stale.remove(f)

	for _i in 8:
		await get_tree().process_frame

	var page_h: float = maxf(_scroll.size.y, 1.0)
	var total: float = maxf(_scroll.get_v_scroll_bar().max_value, page_h)
	var pages: int = int(ceil(total / page_h))
	print("=== THEME GALLERY (window %dx%d · content %d tall · %d pages) ==="
		% [WINDOW.x, WINDOW.y, int(total), pages])

	for p in pages:
		_scroll.scroll_vertical = int(min(float(p) * page_h, maxf(total - page_h, 0.0)))
		for _i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		_shoot("%02d" % (p + 1))

	print("captures: %s" % ProjectSettings.globalize_path(OUT_DIR))
	if _blank.is_empty():
		print("liveness: all %d captures carry a picture." % pages)
		get_tree().quit(0)
	else:
		printerr("BLANK CAPTURES — the run produced nothing to read: %s" % ", ".join(_blank))
		get_tree().quit(1)


func _shoot(shot_name: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	var colours := {}
	var w: int = img.get_width()
	var h: int = img.get_height()
	for gx in CANARY_GRID:
		for gy in CANARY_GRID:
			var px: int = int(float(gx) / CANARY_GRID * w)
			var py: int = int(float(gy) / CANARY_GRID * h)
			colours[img.get_pixel(px, py).to_rgba32()] = true
	if colours.size() < CANARY_MIN_COLOURS:
		_blank.append("%s (%d distinct colours)" % [shot_name, colours.size()])
	img.save_png(OUT_DIR + shot_name + ".png")
