## THE STABLE — the heart of the meta-game. Pick a monster, SEE it, read what training would
## actually do to it, then go spend the drill or head into a tournament.
##
## Rewritten 2026-08-04 against docs/UI_LAYOUT_RULES.md (the clipping fix) and
## docs/UI_THEME.md (shared tokens/builders instead of hand-rolled StyleBoxFlats). Brings across
## what src/App.tsx's RanchView did well: a roster strip with an at-a-glance status, a rich detail
## panel (personality as character, stat bars with the LEAGUE cap visible), and a training section
## that shows the trade-off — gain, cost, and any class shift — before the player commits, per
## CLAUDE.md's "training week... should be a decision made with knowledge the player has earned."
##
## The roster is drawn as real creature portraits (Art.creature_texture), each in a
## team-colour-accented card, not a text-only ItemList row. Every portrait slot degrades to a
## deliberate accent-tinted placeholder (initials, not a blank box) when art hasn't landed for
## that species yet, and swaps to the real texture automatically the moment Art.load_or_null()
## finds the file — no code path here needs to change when art lands mid-development.
##
## UI is still built entirely in code, not authored in the .tscn — the roster and every stat/
## move panel are inherently dynamic, so a hand-authored scene tree would just be a template this
## script overwrites on the first frame anyway (see the equivalent choice in training_ui.gd and
## battle_ui.gd).
extends Control

const UiTheme = preload("res://scripts/ui/theme.gd")

## The player's own guild colour + badge — Art.team_identity(0), used as the UI accent throughout
## this screen (selection highlight, stat bar fill, portrait-fallback tint). ⚠️ Colour alone is
## never sufficient team identification (art.gd's own rule, for collision and colourblind
## readers) — `badge` is shown once, prominently, in the header; the rest of the screen's accent
## uses are plain UI-accent reuse of the same colour, not fresh "whose is this" claims.
var accent: Color
var badge: String

## Four of the seven personality axes, surfaced as character (docs/PERSONALITY_STATS.md §7) —
## see `_axis_bias()` for the load-bearing caveat on what this approximates.
const TEMPERAMENT_AXES := [
	{"key": "aggression", "label": "Aggression"},
	{"key": "temperament", "label": "Discipline"},
	{"key": "mental", "label": "Nerve"},
	{"key": "focus", "label": "Focus"},
]

## ⚠️ DUPLICATED FROM training_ui.gd's INTENSIVE_PAIR, ON PURPOSE — this screen only PREVIEWS a
## drill's trade-off (read-only, no mutation happens here), training_ui.gd is where the drill is
## actually spent (GameData.train). Keep the two tables in sync if the pairing ever changes; they
## are a one-line-per-stat mockup table, not worth a shared module for.
const INTENSIVE_PAIR := {
	"STR": "DEX", "DEX": "STR", "CON": "DEX", "WIS": "INT", "INT": "WIS", "CHA": "CON",
}

var roster_col: VBoxContainer
var detail_box: VBoxContainer
var advance_note: Label
var _advance_btn: Button
var card_panels: Array = []       # PanelContainer per monster, Roster.monsters order — for reselect restyle
var card_chip_labels: Array = []  # Label per monster, parallel to card_panels — the "growing / at cap" tell


func _ready() -> void:
	self.theme = UiTheme.base_theme()
	var identity: Dictionary = Art.team_identity(0)
	accent = identity["colour"]
	badge = identity["badge"]
	_build_ui()
	_refresh_list()
	_refresh_detail()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.SURFACE
	bg.anchor_right = 1; bg.anchor_bottom = 1
	add_child(bg)

	var root_margin := MarginContainer.new()
	root_margin.anchor_right = 1; root_margin.anchor_bottom = 1
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		root_margin.add_theme_constant_override(side, UiTheme.SPACE_XL)
	add_child(root_margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	root_margin.add_child(page)

	# ── header: fixed, never scrolls ────────────────────────────────────────
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UiTheme.SPACE_LG)
	page.add_child(header)

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_col)

	title_col.add_child(UiTheme.heading("The Stable", 1))

	var subtitle := UiTheme.body_text(
		"Your monsters, mid-career. Class is emergent — the two stats it's strongest in decide what it fights as, right now.",
		"secondary")
	title_col.add_child(subtitle)

	var chip := _career_chip()
	if chip != null:
		header.add_child(chip)

	# ⚠️ Points at res://scenes/town.tscn, not title.tscn — town_ui.gd's own header comment flags
	# this exact gap: "stable_ui.gd, which would be the natural place to add a Town button... out
	# of this stream's scope to edit" for whoever owns THIS file. That's this stream; fixed here.
	var town_btn := Button.new()
	town_btn.text = "Town"
	town_btn.focus_mode = Control.FOCUS_ALL
	town_btn.tooltip_text = "Back to the Town map."
	town_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/town.tscn"))
	header.add_child(town_btn)

	page.add_child(HSeparator.new())

	# ── body: roster + detail, ONE outer scroll (rule 5 — nested scrolls trap the wheel) ───────
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)

	var hsplit := HBoxContainer.new()
	hsplit.add_theme_constant_override("separation", UiTheme.SPACE_XL)
	hsplit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(hsplit)

	var list_panel := PanelContainer.new()
	list_panel.custom_minimum_size = Vector2(280, 0)
	list_panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	hsplit.add_child(list_panel)

	roster_col = VBoxContainer.new()
	roster_col.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	roster_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_panel.add_child(roster_col)

	var detail_panel := PanelContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	hsplit.add_child(detail_panel)

	detail_box = VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	detail_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.add_child(detail_box)

	# ── sticky action rail: rule 2 — the primary action is pinned OUTSIDE the scroll ───────────
	page.add_child(HSeparator.new())

	# ⚠️ The weekly tick IS ported now (scripts/week.gd + week_plan.gd). This label used to read
	# "the full weekly tick still lives in the TypeScript build, not here yet" — a footer confessing
	# the game had no loop. It now reports the week's bill instead, so the player sees what Advance
	# Week will cost BEFORE they press it (docs/CORE_LOOP_PORT.md §4).
	advance_note = UiTheme.body_text("", "muted")
	page.add_child(advance_note)

	var advance_btn := Button.new()
	advance_btn.custom_minimum_size = Vector2(0, 46)
	advance_btn.focus_mode = Control.FOCUS_ALL
	advance_btn.text = "Advance Week"
	advance_btn.pressed.connect(_on_advance_week)
	page.add_child(advance_btn)
	_advance_btn = advance_btn

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	page.add_child(actions)

	var battle_btn := Button.new()
	battle_btn.text = "Enter a tournament"
	battle_btn.custom_minimum_size = Vector2(0, 40)
	battle_btn.focus_mode = Control.FOCUS_ALL
	_style_button(battle_btn, "primary")
	battle_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/tournament.tscn"))
	actions.add_child(battle_btn)


## Applies a UiTheme button_stylebox override across every state so one button on the screen can
## read as the primary call-to-action while everything else keeps base_theme()'s default look.
func _style_button(btn: Button, kind: String) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(state, UiTheme.button_stylebox(kind, state))
	btn.add_theme_stylebox_override("focus", UiTheme.button_stylebox(kind, "focus"))


func _league_name() -> String:
	if has_node("/root/Career"):
		return Career.current_league_name()
	return "current league"


## Career context — league, gold, week — shown only if the Career autoload exists (guarded for
## a standalone scene run). This is also the one place on this screen that draws the player's
## team identity properly: badge AND colour together, per art.gd's hard requirement that colour
## alone is never sufficient identification.
func _career_chip() -> Control:
	if not has_node("/root/Career"):
		return null
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", UiTheme.SPACE_XS)

	var badge_lbl := Label.new()
	badge_lbl.text = badge
	badge_lbl.add_theme_color_override("font_color", accent)
	badge_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	chip.add_child(badge_lbl)

	var text_lbl := Label.new()
	text_lbl.text = "%s  ·  %d gold  ·  week %d" % [Career.current_league_name(), Career.gold, Career.week]
	text_lbl.add_theme_color_override("font_color", accent)
	text_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	chip.add_child(text_lbl)
	return chip


func _refresh_list() -> void:
	for c in roster_col.get_children():
		c.queue_free()
	card_panels.clear()
	card_chip_labels.clear()
	for i in range(Roster.monsters.size()):
		var m = Roster.monsters[i]
		var card := _make_card(m, i)
		roster_col.add_child(card)
		card_panels.append(card)
	_restyle_cards()

	# ⚠️ ACCESSIBILITY (docs/ACCESSIBILITY.md #1, P0) — wire explicit up/down focus neighbours
	# between consecutive cards rather than trusting Godot's automatic spatial-neighbour search.
	# The cards sit inside a shared outer ScrollContainer beside the detail pane; the heuristic
	# search is reliable for a flat list but this removes any doubt that Up/Down tracks visual
	# order. Boundary cards (first/last) are left unset so Tab/Shift+Tab falls through to the
	# surrounding scene in normal tree order (Town button above, action rail below).
	for i in range(card_panels.size()):
		var panel: PanelContainer = card_panels[i]
		if i > 0:
			panel.focus_neighbor_top = panel.get_path_to(card_panels[i - 1])
			panel.focus_previous = panel.get_path_to(card_panels[i - 1])
		if i < card_panels.size() - 1:
			panel.focus_neighbor_bottom = panel.get_path_to(card_panels[i + 1])
			panel.focus_next = panel.get_path_to(card_panels[i + 1])

	# Land keyboard focus on the currently-selected card so a keyboard-only player reaches the
	# roster in one Tab press rather than having to guess it's there.
	if not card_panels.is_empty():
		var start_idx: int = clampi(Roster.selected_index, 0, card_panels.size() - 1)
		card_panels[start_idx].grab_focus()

	_refresh_advance_note()

func _make_card(m, index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Keyboard path (docs/ACCESSIBILITY.md #1, the P0 "total block" finding) — a real Button would
	# be simpler, but the card's whole surface (portrait + name + class + chip) needs to be the hit
	# target, so this stays a focusable PanelContainer answering both the mouse AND ui_accept/
	# ui_select, exactly as the audit's recommended fix describes.
	panel.focus_mode = Control.FOCUS_ALL
	panel.tooltip_text = "%s — select" % m.species_name
	panel.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_select(index)
		elif event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_select"):
			_on_select(index)
			panel.accept_event())
	# Repaint on focus change so the focus ring (see _restyle_cards) appears the instant Tab or
	# an arrow key lands here — not only after the player also presses Enter.
	panel.focus_entered.connect(_restyle_cards)
	panel.focus_exited.connect(_restyle_cards)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	panel.add_child(hbox)

	hbox.add_child(_portrait(m.species_id, m.species_name, Vector2(48, 48), accent))

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(col)

	var name_lbl := UiTheme.body_text(m.species_name, "primary")
	col.add_child(name_lbl)

	var class_lbl := UiTheme.body_text("%s · %s" % [m.class_name_, m.role], "secondary")
	class_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	col.add_child(class_lbl)

	# The "plan status at a glance" tell React's RanchView had — adapted honestly: this build has
	# no weekly plan to show (docs/META_GAME_DISPOSITION.md §1, the tick isn't ported), so the
	# real state shown instead is whether this monster still has room to grow at all this league.
	var chip := Label.new()
	chip.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	col.add_child(chip)
	card_chip_labels.append(chip)
	_set_chip_text(chip, m)

	return panel


func _has_room(m) -> bool:
	var cap := GameData.stat_cap()
	for stat in Classify.STATS:
		if float(m.stats.get(stat, 0.0)) < cap - 0.001:
			return true
	return false


func _set_chip_text(chip: Label, m) -> void:
	if _has_room(m):
		chip.text = "● Growing"
		chip.add_theme_color_override("font_color", UiTheme.SAFE)
	else:
		chip.text = "● At cap"
		chip.add_theme_color_override("font_color", UiTheme.GOLD)


func _update_card_chip(index: int) -> void:
	if index < 0 or index >= card_chip_labels.size() or index >= Roster.monsters.size():
		return
	_set_chip_text(card_chip_labels[index], Roster.monsters[index])


## Three distinct visual states, never colour-alone: resting (thin default border), selected
## (accent colour AND a wider border — panel_style("raised", accent)), keyboard-focused (the
## dedicated FOCUS ring colour, per docs/UI_THEME.md's worked example lifted from this exact
## function).
func _restyle_cards() -> void:
	for i in range(card_panels.size()):
		var panel: PanelContainer = card_panels[i]
		var selected: bool = (i == Roster.selected_index)
		var focused: bool = panel.has_focus()
		var base: StyleBoxFlat
		if selected:
			base = UiTheme.panel_style("raised", accent)
		else:
			base = UiTheme.panel_style("default")
		if focused:
			panel.add_theme_stylebox_override("panel", UiTheme.focus_style(base))
		else:
			panel.add_theme_stylebox_override("panel", base)


func _on_select(index: int) -> void:
	Roster.selected_index = index
	_restyle_cards()
	_refresh_detail()


func _refresh_detail() -> void:
	for c in detail_box.get_children():
		c.queue_free()

	var m = Roster.selected()
	if m == null:
		detail_box.add_child(UiTheme.body_text("No monsters in the stable yet.", "secondary"))
		return

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UiTheme.SPACE_LG)
	detail_box.add_child(header)

	header.add_child(_portrait(m.species_id, m.species_name, Vector2(180, 180), accent))

	var id_col := VBoxContainer.new()
	id_col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	id_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	id_col.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(id_col)

	id_col.add_child(UiTheme.heading(m.species_name, 2))
	id_col.add_child(UiTheme.body_text(
		"%s  ·  %s body  ·  %s (%s role)" % [m.flavour, m.body, m.class_name_, m.role], "secondary"))
	id_col.add_child(UiTheme.body_text(
		"HP pool %d   ·   MP pool %d   ·   refuels via %s" % [m.max_hp, m.max_mp, m.mana_role], "secondary"))
	id_col.add_child(UiTheme.body_text(
		"Free attack: %s, %s channel, reach %.1f" % [m.basic_attack.get("stat", "?"), m.basic_attack.get("channel", "?"), float(m.basic_attack.get("range", 0.0))], "secondary"))

	detail_box.add_child(HSeparator.new())

	# ── the bestiary story — the long-form lore, same text as docs/BESTIARY.md ────────────────
	detail_box.add_child(UiTheme.heading("Story", 2))
	var bio := UiTheme.body_text(GameData.bio_for(m.species_id), "secondary")
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_box.add_child(bio)

	detail_box.add_child(HSeparator.new())

	detail_box.add_child(UiTheme.heading("Temperament", 2))
	detail_box.add_child(UiTheme.body_text("How it fights, not just what it can do.", "muted"))
	for axis in TEMPERAMENT_AXES:
		detail_box.add_child(_temperament_row(m, axis))

	detail_box.add_child(HSeparator.new())

	detail_box.add_child(UiTheme.heading("Stats", 2))
	for stat in Classify.STATS:
		detail_box.add_child(_stat_row(m, stat))

	detail_box.add_child(HSeparator.new())
	detail_box.add_child(_training_preview_section(m))

	detail_box.add_child(HSeparator.new())
	detail_box.add_child(UiTheme.heading("Moveset (%d known)" % m.moveset.size(), 2))
	if m.moveset.is_empty():
		detail_box.add_child(UiTheme.body_text("None yet — every stat is still below the pool's lowest learnLevel. Train it.", "muted"))
	for mv in m.moveset:
		detail_box.add_child(UiTheme.body_text("  %s  (%s, %s · %s line)" % [mv["name"], mv["type"], mv["channel"], mv["line"]], "secondary"))

	if not m.innate.is_empty():
		detail_box.add_child(HSeparator.new())
		detail_box.add_child(UiTheme.heading("Innate traits", 2))
		for inn in m.innate:
			detail_box.add_child(UiTheme.body_text("  %s — %s" % [inn["name"], inn["desc"]], "secondary"))


## ⚠️ The cap is the CURRENT LEAGUE's, not a flat placeholder — GameData.stat_cap() reads
## Career.current_stat_cap() (Wood 100 → Tamers Apex 1100), so a Wood-league monster's bars sit
## near-full almost immediately. That's the ladder doing real work, not a bug — but a bar that
## just silently stops moving reads as broken, so this SAYS SO explicitly the moment a stat has
## no room left, rather than leaving the player to guess why nothing happened.
func _stat_row(m, stat: String) -> Control:
	var cap := GameData.stat_cap()
	var value := float(m.stats.get(stat, 0.0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.add_child(UiTheme.stat_bar(stat, value, cap, accent, 40))
	if value >= cap - 0.001:
		col.add_child(UiTheme.body_text(
			"at the %s ceiling — win promotion to train further" % _league_name(), "muted"))
	return col


## ⚠️ MOCKUP APPROXIMATION, NOT THE PORTED SYSTEM — see docs/PERSONALITY_STATS.md §8.3:
## personality has not been ported to Godot at all yet (no personality.gd, no per-monster seed
## stream, no stored drift on MonsterInstance). Aggression/Discipline(temperament)/Nerve(mental)
## below mirror `speciesBias()` in src/tamerengine/personality.ts EXACTLY (species-bias term
## only — the ±18 individual-jitter roll needs a monster seed that doesn't exist on
## MonsterInstance yet, so two same-species monsters currently read identically here). Focus
## mirrors the formula PROPOSED in docs/PERSONALITY_STATS.md §1, which is not yet built in
## personality.ts itself — flagged so nobody mistakes this for shipped TS behaviour.
## Deliberately scoped to this one file rather than touching MonsterInstance or inventing
## scripts/personality.gd. Delete this function in favour of Career.personality /
## MonsterInstance.personality_drift the moment that lands.
func _axis_bias(m, axis: String) -> float:
	var s: Dictionary = m.stats
	var str_v := float(s.get("STR", 0.0))
	var dex_v := float(s.get("DEX", 0.0))
	var con_v := float(s.get("CON", 0.0))
	var wis_v := float(s.get("WIS", 0.0))
	var int_v := float(s.get("INT", 0.0))
	var cha_v := float(s.get("CHA", 0.0))
	var total: float = maxf(1.0, str_v + dex_v + con_v + wis_v + int_v + cha_v)
	var str_s: float = (str_v / total) * 6.0
	var dex_s: float = (dex_v / total) * 6.0
	var con_s: float = (con_v / total) * 6.0
	var wis_s: float = (wis_v / total) * 6.0
	var int_s: float = (int_v / total) * 6.0
	var cha_s: float = (cha_v / total) * 6.0
	var v := 50.0
	if axis == "aggression":
		v = 50.0 + (str_s + dex_s - con_s - wis_s) * 16.0
	elif axis == "temperament":
		v = 50.0 + (int_s + wis_s - str_s) * 15.0
	elif axis == "mental":
		v = 50.0 + (con_s + wis_s - dex_s) * 15.0
	elif axis == "focus":
		v = 50.0 + (str_s + int_s - dex_s - cha_s) * 16.0
	return clampf(v, 0.0, 100.0)


## The descriptor word is the PRIMARY read, the bar is secondary — per PERSONALITY_STATS.md §7,
## "no raw numbers as the primary readout... reads as temperament, not a sixth stat block." The
## exact number is still reachable (tooltip) for a player who wants it, never hidden — just not
## the headline.
func _axis_descriptor(axis: String, value: float) -> String:
	if axis == "aggression":
		return "Cautious" if value < 35.0 else ("Eager" if value >= 65.0 else "Balanced")
	elif axis == "temperament":
		return "Improvises" if value < 35.0 else ("By the book" if value >= 65.0 else "Follows orders")
	elif axis == "mental":
		return "Rattles easily" if value < 35.0 else ("Ice in its veins" if value >= 65.0 else "Steady")
	elif axis == "focus":
		return "Distractible" if value < 35.0 else ("Locked on" if value >= 65.0 else "Attentive")
	return "—"


func _temperament_row(m, axis: Dictionary) -> Control:
	var axis_key: String = axis["key"]
	var value: float = _axis_bias(m, axis_key)
	var desc: String = _axis_descriptor(axis_key, value)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	row.tooltip_text = "%s: %d / 100 — species tendency; coaching/breeding not wired up yet" % [axis["label"], int(round(value))]

	var lbl := UiTheme.body_text(axis["label"], "secondary")
	# ⚠️ 72px clipped "Aggression" hard against its value — it rendered as "AggressionBalanced".
	# The widest label here is "Discipline"/"Aggression"; 104 clears both with room for the gap.
	lbl.custom_minimum_size = Vector2(104, 0)
	row.add_child(lbl)

	var desc_lbl := UiTheme.body_text(desc, "primary")
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(desc_lbl)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = 100
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(90, 10)
	var fg := StyleBoxFlat.new()
	fg.bg_color = accent
	fg.set_corner_radius_all(UiTheme.RADIUS_SM)
	var bg2 := StyleBoxFlat.new()
	bg2.bg_color = UiTheme.SURFACE
	bg2.set_corner_radius_all(UiTheme.RADIUS_SM)
	bar.add_theme_stylebox_override("fill", fg)
	bar.add_theme_stylebox_override("background", bg2)
	row.add_child(bar)

	return row


# =============================================================================
# TRAINING PREVIEW — read-only. Shows exactly what a basic/intensive drill would do to THIS
# monster right now (gain, paired-stat cost, and any class shift) before the player commits, per
# CLAUDE.md's "training week... should be a decision made with knowledge the player has earned."
# The actual drill is spent on training.tscn (training_ui.gd) — this section never mutates state.
# =============================================================================

func _training_preview_section(m) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTheme.SPACE_XS)

	box.add_child(UiTheme.heading("Training — what's on offer", 2))
	box.add_child(UiTheme.body_text(
		"Every drill trades a stat gain against a cost — some tip %s into a different class outright. Rest and Excursion aren't modelled in this build yet." % m.species_name,
		"muted"))

	for stat in Classify.STATS:
		box.add_child(_training_preview_row(m, stat))

	var train_btn := Button.new()
	train_btn.text = "Train this monster →"
	train_btn.custom_minimum_size = Vector2(0, 36)
	train_btn.focus_mode = Control.FOCUS_ALL
	_style_button(train_btn, "primary")
	train_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/training.tscn"))
	box.add_child(train_btn)

	return box


func _training_preview_row(m, stat: String) -> Control:
	var cap := GameData.stat_cap()
	var current := float(m.stats.get(stat, 0.0))
	var paired: String = INTENSIVE_PAIR.get(stat, "")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_SM)

	var lbl := UiTheme.body_text(stat, "secondary")
	lbl.custom_minimum_size = Vector2(36, 0)
	row.add_child(lbl)

	var desc: String
	if current >= cap - 0.001:
		desc = "at the %s ceiling — win promotion to train further" % _league_name()
	else:
		var basic_gain := _preview_gain(m, stat, false)
		var intensive_gain := _preview_gain(m, stat, true)
		var intensive_cost := _preview_cost(m, paired)
		var intensive_class := _preview_class_after(m, stat, true, paired)
		desc = "basic +%d  ·  intensive +%d %s / −%d %s" % [
			int(round(basic_gain)), int(round(intensive_gain)), stat, int(round(intensive_cost)), paired]
		if intensive_class != m.class_name_:
			desc += "   (→ %s)" % intensive_class

	var desc_lbl := UiTheme.body_text(desc, "primary")
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(desc_lbl)

	return row


## Mirrors game_data.gd:train()'s room/clamp math exactly — read-only, no state changes. Keep in
## sync with that function if the drill formula ever changes (same duplication rationale as
## INTENSIVE_PAIR above).
func _preview_gain(m, stat: String, intensive: bool) -> float:
	var cap := GameData.stat_cap()
	var current: float = float(m.stats.get(stat, 0.0))
	var raw := 12.0 if intensive else 6.0
	var room: float = maxf(0.0, cap - current)
	return minf(raw, room)


func _preview_cost(m, paired: String) -> float:
	if paired == "":
		return 0.0
	return minf(4.0, float(m.stats.get(paired, 0.0)))


## Applies the same gain/cost math to a COPY of the monster's stats, purely to preview a class
## shift before the player commits a drill. Never mutates `m`.
func _preview_class_after(m, stat: String, intensive: bool, paired: String) -> String:
	var stats_copy: Dictionary = m.stats.duplicate()
	stats_copy[stat] = float(stats_copy.get(stat, 0.0)) + _preview_gain(m, stat, intensive)
	if intensive and paired != "" and paired != stat:
		stats_copy[paired] = float(stats_copy.get(paired, 0.0)) - _preview_cost(m, paired)
	return Classify.class_for_stats(stats_copy)


## Real portrait if Art has one, otherwise a deliberate accent-tinted placeholder (the species'
## own initials, not a blank box) at the SAME footprint — callers never need to branch on which
## they got, and the layout doesn't jump the moment art lands mid-session.
func _portrait(species_id: String, species_name: String, portrait_size: Vector2, tint: Color) -> Control:
	var tex := Art.creature_texture(species_id)
	if tex != null:
		var t := TextureRect.new()
		t.texture = tex
		t.custom_minimum_size = portrait_size
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		return t
	var panel := PanelContainer.new()
	panel.custom_minimum_size = portrait_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(tint.r, tint.g, tint.b, 0.16)
	sb.border_color = tint
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(UiTheme.RADIUS_MD)
	panel.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = species_name.substr(0, 2).to_upper()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", tint)
	lbl.add_theme_font_size_override("font_size", int(portrait_size.y * 0.35))
	panel.add_child(lbl)
	return panel


## ⚠️ THE ONLY THING THAT MOVES THE CLOCK. Everything else on this screen writes a PLAN; this
## spends it. `WeekPlan.advance()` runs `week.gd`'s tick over the whole stable, then the feeding
## screen narrates what landed.
func _on_advance_week() -> void:
	if Roster.monsters.is_empty():
		return
	var report: Dictionary = WeekPlan.advance(Roster.monsters)
	WeekPlan.set_meta("last_report", report)
	get_tree().change_scene_to_file("res://scenes/feeding.tscn")


## The week's bill, shown on the rail before it is paid.
func _refresh_advance_note() -> void:
	if advance_note == null:
		return
	if Roster.monsters.is_empty():
		advance_note.text = "No monsters yet — buy one at the Market before advancing the week."
		if _advance_btn != null:
			_advance_btn.disabled = true
		return
	if _advance_btn != null:
		_advance_btn.disabled = false
	var cost: Dictionary = WeekPlan.projected_cost(Roster.monsters)
	var planned := 0
	for mi in Roster.monsters:
		if WeekPlan.is_planned(mi.id):
			planned += 1
	advance_note.text = "%d of %d monsters have a plan  ·  this week costs %d gold and %d stamina" % [
		planned, Roster.monsters.size(), int(cost.get("gold", 0)), int(round(float(cost.get("stamina", 0.0))))]
