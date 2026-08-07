## THE TOWN — the hub between the title screen and everywhere else. A backdrop, the player's
## career context (guild badge, league, gold, week, stable size), and a map of locations.
##
## Three locations are REAL destinations: the Market (scenes/market.tscn), the Stable
## (scenes/stable.tscn), and a Tournament (scenes/tactics.tscn). The rest of the guild town
## described in docs/WORLD_GUILDS.md — the Ranch Shop, the Lab, the Breeding Ranch, the Hall of
## Fame — do not have a Godot-side system behind them yet (docs/META_GAME_DISPOSITION.md §5: still
## TypeScript-only in town.ts/game.ts, not ported). Four full screens that open and either do
## nothing or fake a transaction would be worse than not being there at all — so those doors are
## shown LOCKED instead: visible, named, tooltipped with why, never clickable. "A visibly-not-yet-
## implemented door is fine; a button that lies is not."
##
## Reached from the title screen: New Career / Continue both land here (title_ui.gd), per
## docs/CORE_LOOP_PORT.md §2 — the town is the hub, the stable/market/tournament are destinations
## FROM it, not the game's front door.
##
## ⚠️ A NEW CAREER STARTS WITH AN EMPTY STABLE, ON PURPOSE (docs/CORE_LOOP_PORT.md §1). That's the
## single biggest fix this file makes over the previous build, which handed the player a
## pre-made six-monster team and deleted the game's opening decision. Two things follow from an
## empty stable being the correct state, not a bug: an honest callout pointing at the Market
## (`_empty_stable_banner`), and the Tournament door staying VISIBLE and marked "real" (it IS
## built) while being DISABLED with a stated reason until there's a team to field
## (`_make_location_button`'s `forced_disabled` — never a silent dead end).
##
## UI built entirely in code, matching stable_ui.gd/training_ui.gd's established house style —
## dynamic content (career numbers, roster count, locked/unlocked/waiting state) means a
## hand-authored .tscn would just be a template this script overwrites on the first frame anyway.
## Styled via scripts/ui/theme.gd tokens (docs/UI_LAYOUT_RULES.md's "never hand-roll a
## StyleBoxFlat" rule) rather than the inline Color()/StyleBoxFlat literals this file used before.
extends Control

const UiTheme = preload("res://scripts/ui/theme.gd")

const GRID_COLUMNS := 4

## Guild-town locations, in grid reading order (left-to-right, top-to-bottom). `real` locations
## navigate to a working scene; locked ones say why not rather than pretending. "The Stable" is
## the Ranch of docs/CORE_LOOP_PORT.md's loop diagram — training, feeding-preview and the roster
## all live there.
const LOCATIONS := [
	{"icon": "🛒", "title": "The Market", "desc": "recruit new partners, release old ones", "real": true, "scene": "res://scenes/market.tscn"},
	{"icon": "🏟", "title": "The Stable", "desc": "train and manage your monsters", "real": true, "scene": "res://scenes/stable.tscn"},
	{"icon": "🥊", "title": "Tournament", "desc": "enter the Circuit", "real": true, "scene": "res://scenes/tournament.tscn"},
	{"icon": "🏗️", "title": "Ranch Shop", "desc": "licences and barn upgrades", "real": true, "scene": "res://scenes/shop.tscn"},
	{"icon": "🧪", "title": "Lab", "desc": "cryo storage for the bloodline", "real": true, "scene": "res://scenes/lab.tscn"},
	{"icon": "🐎", "title": "Breeding Ranch", "desc": "raise the next generation", "real": true, "scene": "res://scenes/breeding.tscn"},
	{"icon": "🏛", "title": "Hall of Fame", "desc": "retired champions, honoured", "real": false},
]

const LOCKED_TOOLTIP := "Not yet built in Godot — the logic still lives in the TypeScript build (docs/META_GAME_DISPOSITION.md §5). Shown so the town reads whole; wired up once it's ported."
const NO_TEAM_TOOLTIP := "Recruit a monster at the Market first — a tournament needs a team to field."

var accent: Color
var badge: String
var header_label: Label
var loc_buttons: Array = []  # PanelContainer per location, LOCATIONS order


func _ready() -> void:
	self.theme = UiTheme.base_theme()
	var identity: Dictionary = Art.team_identity(0)
	badge = identity["badge"]
	accent = UiTheme.team_border_color(0)
	_build_ui()


func _build_ui() -> void:
	var tex := Art.area_texture("town")
	if tex != null:
		var bg_rect := TextureRect.new()
		bg_rect.anchor_right = 1; bg_rect.anchor_bottom = 1
		bg_rect.texture = tex
		bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(bg_rect)
	else:
		var bg := ColorRect.new()
		bg.color = UiTheme.SURFACE
		bg.anchor_right = 1; bg.anchor_bottom = 1
		add_child(bg)

	# Scrim so text and cards read over the painted backdrop OR the flat fallback alike.
	var scrim := ColorRect.new()
	scrim.color = Color(0.04, 0.04, 0.06, 0.58)
	scrim.anchor_right = 1; scrim.anchor_bottom = 1
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var root_margin := MarginContainer.new()
	root_margin.anchor_right = 1; root_margin.anchor_bottom = 1
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		root_margin.add_theme_constant_override(side, UiTheme.SPACE_XL)
	add_child(root_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	root_margin.add_child(vbox)

	# ── header: title, guild flavour, career chip, Title button — fixed, never scrolls ─────────
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UiTheme.SPACE_LG)
	vbox.add_child(header)

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_col)

	title_col.add_child(UiTheme.heading("The Town", 1))

	var flavour := UiTheme.body_text(
		"Gradehall, seat of the Assay Table — the guilds that grade every Tamer-monster partnership on the Circuit, Wood to Tamers Apex.",
		"secondary")
	title_col.add_child(flavour)

	header.add_child(_career_chip())

	var title_btn := Button.new()
	title_btn.text = "Title"
	title_btn.focus_mode = Control.FOCUS_ALL
	title_btn.tooltip_text = "Back to the title screen."
	title_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/title.tscn"))
	header.add_child(title_btn)

	vbox.add_child(HSeparator.new())

	# ── the opening decision: an empty stable is the CORRECT new-game state, so say so ─────────
	var stable_empty: bool = not has_node("/root/Roster") or Roster.monsters.is_empty()
	if stable_empty:
		vbox.add_child(_empty_stable_banner())

	# ── location grid — the only region whose content can grow, so it's the scrollable one ─────
	var grid_scroll := ScrollContainer.new()
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(grid_scroll)

	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", UiTheme.SPACE_MD)
	grid.add_theme_constant_override("v_separation", UiTheme.SPACE_MD)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_scroll.add_child(grid)

	loc_buttons.clear()
	for loc in LOCATIONS:
		var forced_disabled: bool = (loc["title"] == "Tournament") and stable_empty
		var card := _make_location_button(loc, forced_disabled, NO_TEAM_TOOLTIP)
		grid.add_child(card)
		loc_buttons.append(card)
	_wire_grid_focus(GRID_COLUMNS)

	vbox.add_child(HSeparator.new())

	# ── footer: End Week — fixed, never scrolls, so the primary action stays reachable ─────────
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	vbox.add_child(footer)

	var week_btn := Button.new()
	week_btn.text = "End Week"
	week_btn.custom_minimum_size = Vector2(0, 40)
	week_btn.focus_mode = Control.FOCUS_ALL
	week_btn.tooltip_text = "Advances the week counter. Feeding, aging and the full weekly tick still live in the TypeScript build (docs/META_GAME_DISPOSITION.md §1)."
	week_btn.pressed.connect(_on_end_week)
	footer.add_child(week_btn)

	var footer_note := UiTheme.body_text("The Market's recruits restock with each new week.", "muted")
	footer_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(footer_note)

	# Land keyboard focus on the first ENABLED door so a keyboard-only player reaches somewhere
	# useful in one Tab press, even when Tournament is temporarily disabled by an empty stable.
	for card in loc_buttons:
		var btn: Button = card.get_child(0)
		if not btn.disabled:
			btn.grab_focus()
			break


func _career_chip() -> Control:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", UiTheme.SPACE_XS)

	var badge_lbl := Label.new()
	badge_lbl.text = badge
	badge_lbl.add_theme_color_override("font_color", accent)
	badge_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBHEADING)
	chip.add_child(badge_lbl)

	header_label = Label.new()
	header_label.add_theme_color_override("font_color", accent)
	header_label.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBHEADING)
	chip.add_child(header_label)
	_refresh_header_text()

	return chip


func _refresh_header_text() -> void:
	if header_label == null:
		return
	var league_name := "?"
	var gold := 0
	var week := 0
	if has_node("/root/Career"):
		league_name = Career.current_league_name()
		gold = Career.gold
		week = Career.week
	var stable_size := Roster.monsters.size() if has_node("/root/Roster") else 0
	header_label.text = "%s league  ·  %d gold  ·  week %d  ·  %d in the stable" % [league_name, gold, week, stable_size]


## The opening decision the player hasn't made yet. An empty stable used to be a bug in this
## build; now it's the correct state on a fresh career (docs/CORE_LOOP_PORT.md §1), so the town
## says why it looks bare and points at the one real door that fixes it, rather than leaving the
## player to guess — CORE_LOOP_PORT.md §4's "never leave a dead-end screen."
func _empty_stable_banner() -> Control:
	var panel := PanelContainer.new()
	var sb := UiTheme.panel_style("raised", UiTheme.GOLD)
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	panel.add_child(row)

	var icon := Label.new()
	icon.text = "🛒"
	icon.add_theme_font_size_override("font_size", UiTheme.SIZE_HEADING)
	row.add_child(icon)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	row.add_child(col)

	col.add_child(UiTheme.body_text("Your stable is empty — that's where every career starts.", "primary"))
	var gold := Career.gold if has_node("/root/Career") else 500
	var cap := Career.barn_capacity if has_node("/root/Career") else 2
	col.add_child(UiTheme.body_text(
		"%d gold, room for %d. Recruiting your first monster at the Market is the first real decision of the game." % [gold, cap],
		"secondary"))

	var go_btn := Button.new()
	go_btn.text = "Go to the Market →"
	go_btn.focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "disabled"]:
		go_btn.add_theme_stylebox_override(state, UiTheme.button_stylebox("primary", state))
	go_btn.add_theme_stylebox_override("focus", UiTheme.button_stylebox("primary", "focus"))
	go_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/market.tscn"))
	row.add_child(go_btn)

	return panel


## `forced_disabled`/`forced_reason` let a location that IS built (e.g. Tournament) be temporarily
## unavailable for a stated reason — distinct from `loc["real"] == false`, which means "not built
## at all". Both end in a disabled button with a tooltip; neither is ever a silent dead end.
func _make_location_button(loc: Dictionary, forced_disabled: bool = false, forced_reason: String = "") -> PanelContainer:
	var authored_real: bool = loc["real"]
	var clickable: bool = authored_real and not forced_disabled

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(210, 112)

	var base_sb: StyleBoxFlat = UiTheme.panel_style("default", accent if clickable else UiTheme.BORDER_FAINT)
	if clickable:
		base_sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", base_sb)

	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_ALL
	btn.disabled = not clickable
	btn.anchor_right = 1; btn.anchor_bottom = 1
	if not authored_real:
		btn.tooltip_text = LOCKED_TOOLTIP
	elif forced_disabled:
		btn.tooltip_text = forced_reason
	else:
		btn.tooltip_text = "%s — select" % loc["title"]
	if clickable:
		var target: String = loc["scene"]
		btn.pressed.connect(func(): get_tree().change_scene_to_file(target))
	panel.add_child(btn)

	# Repaint the card's border on focus so the focus ring is visible for EVERY card — a keyboard
	# user tabbing past a locked or temporarily-disabled door should still see where focus landed,
	# even though activating it does nothing (docs/ACCESSIBILITY.md §7, SC 2.4.7).
	btn.focus_entered.connect(func(): panel.add_theme_stylebox_override("panel", UiTheme.focus_style(base_sb)))
	btn.focus_exited.connect(func(): panel.add_theme_stylebox_override("panel", base_sb))

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.anchor_right = 1; content.anchor_bottom = 1
	content.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(content)

	var icon_row := HBoxContainer.new()
	icon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon_row)

	var icon_lbl := Label.new()
	icon_lbl.text = loc["icon"]
	icon_lbl.add_theme_font_size_override("font_size", 22)
	icon_row.add_child(icon_lbl)

	if not authored_real:
		var lock_lbl := Label.new()
		lock_lbl.text = " 🔒"
		lock_lbl.add_theme_font_size_override("font_size", 16)
		lock_lbl.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
		icon_row.add_child(lock_lbl)
	elif forced_disabled:
		var wait_lbl := Label.new()
		wait_lbl.text = " ⏳"
		wait_lbl.add_theme_font_size_override("font_size", 16)
		wait_lbl.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
		icon_row.add_child(wait_lbl)

	var title_lbl := Label.new()
	title_lbl.text = loc["title"]
	title_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBHEADING)
	title_lbl.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY if clickable else UiTheme.TEXT_MUTED)
	content.add_child(title_lbl)

	var desc_lbl := Label.new()
	if not authored_real:
		desc_lbl.text = "not yet built"
	elif forced_disabled:
		desc_lbl.text = forced_reason
	else:
		desc_lbl.text = loc["desc"]
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	desc_lbl.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY if clickable else UiTheme.TEXT_MUTED)
	content.add_child(desc_lbl)

	return panel


## Explicit grid focus neighbours (docs/ACCESSIBILITY.md #1 pattern, reused from stable_ui.gd's
## roster-list wiring) rather than trusting automatic spatial search across a grid that mixes
## real, locked and temporarily-disabled cards.
func _wire_grid_focus(columns: int) -> void:
	var n := loc_buttons.size()
	for i in range(n):
		var btn: Button = loc_buttons[i].get_child(0)
		if i % columns != 0:
			btn.focus_neighbor_left = btn.get_path_to(loc_buttons[i - 1].get_child(0))
		if i % columns != columns - 1 and i + 1 < n:
			btn.focus_neighbor_right = btn.get_path_to(loc_buttons[i + 1].get_child(0))
		if i - columns >= 0:
			btn.focus_neighbor_top = btn.get_path_to(loc_buttons[i - columns].get_child(0))
		if i + columns < n:
			btn.focus_neighbor_bottom = btn.get_path_to(loc_buttons[i + columns].get_child(0))


## ⚠️ Advances ONLY `Career.week` — no feeding, aging or market-tick logic exists on the Godot
## side yet (docs/META_GAME_DISPOSITION.md §1). Real, not faked: the counter genuinely moves and
## the Market's offer generator genuinely reseeds off it. Just smaller than the real weekly tick.
func _on_end_week() -> void:
	if has_node("/root/Career"):
		Career.advance_week(1)
	_refresh_header_text()
