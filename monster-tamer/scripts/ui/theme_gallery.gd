## THEME GALLERY — every UiTheme token and builder on one screen, for visual review and
## regression-checking. Not part of the navigation graph (nothing links to it); open it directly
## (res://scenes/theme_gallery.tscn) to review the theme after any change to scripts/ui/theme.gd.
##
## Sections, top to bottom: palette swatches with hand-computed contrast ratios, type scale,
## spacing/radii, panel + button states, stat/HP bars, team chips (all 8 liveries), status chips
## (every STATUS_META entry), and a before/after comparing a hand-rolled StyleBoxFlat (the
## pattern this file replaces) against UiTheme.panel_style() (the replacement).
extends Control

const UiTheme = preload("res://scripts/ui/theme.gd")


func _ready() -> void:
	self.theme = UiTheme.base_theme()
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.SURFACE
	bg.anchor_right = 1; bg.anchor_bottom = 1
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1; scroll.anchor_bottom = 1
	add_child(scroll)

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
