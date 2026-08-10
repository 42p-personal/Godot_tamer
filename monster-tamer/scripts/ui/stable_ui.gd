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

## ⚠️ `INTENSIVE_PAIR` USED TO LIVE HERE AND IT WAS A LIE IN THREE SEPARATE WAYS (round 14).
## It was a hand-copied six-entry table "kept in sync" with training_ui.gd, and it had drifted:
## it claimed CON pairs with DEX and CHA with CON, while `week.gd:DRILLS` — the table the tick
## actually reads — carries TWO intensive drills per stat with different pairs (CON/DEX *and*
## CON/INT; CHA/INT *and* CHA/CON), plus a whole extreme and diverse tier this screen never
## mentioned at all. The preview also hardcoded "+6 basic / +12 intensive" and so ignored every
## multiplier the week is actually decided by: life stage, stamina, happiness, species aptitude,
## focus cost, the training food, and the monster's own bloodline ceiling.
##
## That is this project's signature failure in its purest form — a screen whose whole job is to
## let the player "make a decision with knowledge they have earned", printing numbers the tick
## does not use. It is now drawn from `week.gd:preview_week`, which runs the REAL tick on a
## throwaway clone, exactly as training_ui.gd does. There is no second copy of the math left on
## this screen to drift.
const WeekLib = preload("res://scripts/week.gd")

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

	# ⚠️ THIS LINE HAS TO TRACK WHICH GAME IS ACTUALLY RUNNING. "Class is emergent" is true today and
	# becomes a lie the moment `assigned_class` lands — and a header that misdescribes the single
	# largest decision in the game is worse than no header. It reads the same feature detect
	# `week.gd` does, so it can never be left behind by the build.
	var assignable: bool = not Roster.monsters.is_empty() and WeekLib.assignment_active(Roster.monsters[0])
	var subtitle := UiTheme.body_text(
		("Your monsters, mid-career. A class is a COMMITMENT — it lifts the ceiling on its own two stats and lowers it on the other four."
			if assignable else
			"Your monsters, mid-career. Class is emergent — the two stats it's strongest in decide what it fights as, right now."),
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


## ⚠️ THE MONSTER'S OWN CEILING, NOT THE LEAGUE'S FLAT NUMBER. `week.gd:stat_ceiling` is league cap
## x bloodline potential, with the headroom a committed build has traded for out of its own total
## budget. Reading the raw league cap here would show "At cap" on exactly the two monsters that
## still have room — the bred body breeding exists to produce, and the specialist the headroom
## trade exists to allow.
func _has_room(m) -> bool:
	var cap := GameData.stat_cap()
	for stat in Classify.STATS:
		if float(m.stats.get(stat, 0.0)) < WeekLib.stat_ceiling(m, cap, stat) - 0.001:
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

	detail_box.add_child(_class_commitment_section(m))

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
	var ceiling := WeekLib.stat_ceiling(m, cap, stat)
	var value := float(m.stats.get(stat, 0.0))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	# The bar is drawn against this monster's OWN ceiling, so a stat trained into its headroom is
	# not silently painted as overflowing a bar it has legitimately passed.
	col.add_child(UiTheme.stat_bar(stat, value, maxf(ceiling, value), accent, 40))
	# ⚠️ THE TIER IS THE STAT'S MOST IMPORTANT PROPERTY ONCE CLASSES ARE ASSIGNED, so it is on the
	# bar itself, not buried in the commitment panel. An off-class stat stopping 30% short of the
	# number the league calls "the cap" is the single most likely thing to read as a bug.
	var tier: String = WeekPlan.stat_ceiling_tier(m, stat)
	if tier == "primary" or tier == "secondary" or tier == "off-class":
		col.add_child(UiTheme.body_text("%s for a %s · ceiling %d" % [
			tier, WeekLib.assigned_class_of(m), int(round(ceiling))],
			"secondary" if tier != "off-class" else "muted"))
	if value >= ceiling - 0.001:
		col.add_child(UiTheme.body_text(
			WeekPlan.drill_note(m, "x" + stat.to_lower(), cap).get("note",
				"at the %s ceiling — win promotion to train further" % _league_name()), "muted"))
	elif value > cap + 0.001:
		# ⚠️ SAY IT, DO NOT LET THEM FIND IT. A stat above the league number is the headroom trade
		# paying out, and a player who sees a stat pass a cap the rest of the UI calls a cap will
		# read it as a bug unless the screen names it.
		col.add_child(UiTheme.body_text(
			"%d above the %s cap — headroom traded from this monster's other stats" % [
				int(round(value - cap)), _league_name()], "muted"))
	return col


# =============================================================================
# CLASS — THE COMMITMENT. The largest decision in the game and, until this section existed, the
# only one the player made without being shown its consequences.
#
# ⚠️ `docs/SHAPE_DIAGNOSIS.md` §2 measured kit alignment at 5.50x on a byte-identical stat vector,
# and a kit drawn for the WRONG class at 0.07x. Class is not a label on a stat pair — it is the
# whole moveset, and now the ceiling on all six stats too. A decision that large has to state what
# it buys, what it forecloses, and whether it can be taken back, BEFORE it is taken.
#
# ⚠️ THIS SECTION SHOWS THE TRADE; IT DOES NOT OWN THE RULE. The eligible set comes from the
# SHIPPED gate, `Classify.classes_available_for()` — never from a screen-local re-derivation. A
# hand-copied rule on this exact file has already gone wrong once (see the `INTENSIVE_PAIR` note at
# the top: a six-entry table "kept in sync" that had silently drifted in three ways), and a gate
# that disagrees with the one the assign button enforces is the same bug with higher stakes.
# =============================================================================

## The classes this monster could commit to right now, straight from the shipped gate. ⚠️ The gate
## is keyed on the monster's NOMINAL cap (league cap x bloodline potential), not the raw league
## number — `Classify.GATE_FLOOR` is a fraction of it — so a bred body's floor is genuinely higher
## and this must pass the same value `week.gd` does or the screen offers classes the button refuses.
func _candidate_classes(m) -> Array:
	var nominal: float = float(WeekLib.stat_cap_for(m, GameData.stat_cap()))
	var names: Array = Classify.classes_available_for(m.stats, nominal)
	var out: Array = []
	for c in GameData.classes:
		if names.has(str(c.get("name", ""))):
			out.append(c)
	return out


## What committing to `cls` would do to this body, in the units the player already reads.
##
## ⚠️ IT NO LONGER PROMISES STAT ROOM, BECAUSE THE PER-CLASS CAPS ARE RETIRED (see the block above
## `week.gd:class_headroom`). This line used to read "STR to 1485, CON to 1265, the other four stop
## at 962" — every one of those numbers is now false; `class_headroom` hands 1.35x to every stat on
## every body. Class is a KIT AND IDENTITY commitment, not a stat-ceiling one, so the line has to
## sell what it actually does: it decides which three ability LINES the monster draws from, which
## is the largest measured lever in the game (14x between a matched and a mismatched kit).
##
## ⚠️ AND IT MUST STILL WARN ABOUT THE ONE REAL COST, which the caps' retirement did not remove:
## reassigning re-draws the kit, and a body whose stats do not yet suit the new class fights with a
## kit it cannot use until it trains in. Round 15 measured that transit state at 2% — the sharpest
## cliff in the game — so the screen naming it is not decoration.
func _commitment_line(m, cls: Dictionary, cap: float) -> String:
	var _unused_cap := cap
	var pri := str(cls.get("primary", ""))
	var sec := str(cls.get("secondary", ""))
	var suited: bool = false
	var top := ""
	var best := -1.0
	for stat in Classify.STATS:
		var v := float(m.stats.get(stat, 0.0))
		if v > best:
			best = v
			top = str(stat)
	suited = (top == pri or top == sec)
	var txt := "%s — draws its moveset from %s/%s lines" % [str(cls.get("name", "")), pri, sec]
	if not suited:
		txt += "   ·   ⚠ this body leads on %s — it will carry a kit it cannot use until it trains in" % top
	return txt


func _class_commitment_section(m) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	box.add_child(UiTheme.heading("Class — the commitment", 2))

	var cap := GameData.stat_cap()
	var active: bool = WeekLib.assignment_active(m)
	var assigned: String = WeekLib.assigned_class_of(m)

	if active and assigned != "":
		box.add_child(UiTheme.body_text("Committed: %s." % assigned, "primary"))
	elif active:
		box.add_child(UiTheme.body_text(
			"Uncommitted — the moveset is redrawn from whichever two stats happen to lead. Commit, and it draws from the class you chose instead. Every stat stops at %d either way." % int(round(WeekLib.stat_cap_for(m, cap))),
			"primary"))
	else:
		# ⚠️ SAY WHICH GAME IS RUNNING. Assignment is not built on this build; the numbers below are
		# a forecast of what committing WOULD buy, not a description of a control that exists. A
		# panel that reads as live when it is not is how a system gets documented as shipped.
		box.add_child(UiTheme.body_text(
			"Class is still emergent on this build — it follows the two highest stats and the moveset follows it. What committing would buy:",
			"muted"))

	# what it BUYS, what it FORECLOSES — per candidate class
	var candidates: Array = _candidate_classes(m)
	if candidates.is_empty():
		# ⚠️ AN EMPTY GATE MUST STILL GIVE TRAINING A GOAL. A fresh monster qualifies for nothing —
		# `Classify.GATE_FLOOR` is 0.20 of its nominal cap and its stats start near 10 — and a panel
		# that just goes blank there teaches the player that the system is broken rather than that
		# it is not yet earned. `gate_reason` exists precisely for this and was going unused.
		var nearest := Classify.class_for_stats(m.stats)
		var why: String = Classify.gate_reason(m.stats, WeekLib.stat_cap_for(m, cap), nearest)
		box.add_child(UiTheme.body_text(
			"  Nothing yet — train it further first. %s: %s" % [nearest, why if why != "" else "not yet eligible"],
			"muted"))
	for c in candidates:
		var cname := str(c.get("name", ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiTheme.SPACE_XS)
		var lbl := UiTheme.body_text("  " + _commitment_line(m, c, cap),
			"primary" if cname == assigned else "secondary")
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lbl)
		if active and cname != assigned:
			var btn := Button.new()
			btn.text = "Reassign" if assigned != "" else "Assign"
			_style_button(btn, "primary" if assigned == "" else "secondary")
			btn.pressed.connect(_on_assign_class.bind(m, cname))
			row.add_child(btn)
		box.add_child(row)

	# ⚠️ THE UNCOMMITTED STATE MUST BE REACHABLE FROM THE COMMITTED ONE, OR "reversible" IS A LIE.
	# `Classify.classes_available_for` never lists Generalist (it is the ungated fallback, not a
	# gated option), so without this row a committed player can swap trades but can never step back
	# out of the system — and the panel two lines below promises they can.
	if active and assigned != "":
		var back := HBoxContainer.new()
		back.add_theme_constant_override("separation", UiTheme.SPACE_XS)
		var bl := UiTheme.body_text(
			"  Uncommitted — all six stats back to the flat cap of %d, kit redrawn from the two highest." %
				int(round(WeekLib.stat_cap_for(m, cap))), "secondary")
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		back.add_child(bl)
		var bbtn := Button.new()
		bbtn.text = "Release"
		_style_button(bbtn, "secondary")
		bbtn.pressed.connect(_on_release_class.bind(m))
		back.add_child(bbtn)
		box.add_child(back)

	# the part everyone forgets to say
	box.add_child(UiTheme.body_text(
		"Reversible: yes — a class can be reassigned, and no stat is ever REDUCED by it. What you cannot take back is the time; a stat parked above a new class's ceiling stops growing until you change class again.",
		"muted"))
	# ⚠️ THE MOVESET IS THE REAL PRICE AND IT IS NOT DENOMINATED IN GOLD. `week.gd:_redraft_if_stale`
	# redraws the kit the week the class changes, and SHAPE_DIAGNOSIS §2 measured a kit drawn for a
	# class the body is not at 0.07x. Charging gold on top of that would be double-pricing a
	# decision that already costs a season — so this WARNS rather than bills.
	box.add_child(UiTheme.body_text(
		"⚠  Reassigning redraws the whole moveset the same week. A kit drawn for a class this body is not yet trained for is the single worst state in the game — reassign toward where the stats are going, not away from where they are.",
		"muted"))
	return box


## Commit this monster to a trade, and REDRAW ITS KIT.
##
## ⚠️ THE `rng` IS NOT OPTIONAL AND IT IS NOT A DETAIL — IT IS THE WHOLE FEATURE.
## Kit alignment is the largest measured lever in the game (round 15: 5.50x on a byte-identical
## stat vector; a kit drawn for a class the body is not measures 0.07x). `assign_class` only
## redraws when handed a generator, and `week.gd:_redraft_if_stale` CANNOT be relied on to rescue
## a forgotten one: it fires on `class_before != class_name_`, which after a reassignment are
## already equal. `_probe_integrate.gd` §2 proves both branches — a body that has outgrown its kit
## does self-heal on the next tick, and a body level with its kit carries the WRONG kit for the
## rest of its life. So passing it here is a contract, not a nicety.
##
## ⚠️ AND THE SEED IS DERIVED, NOT ENTROPY. `RandomNumberGenerator.new()` unseeded would draft a
## different kit every process for the same decision — a straight violation of the determinism
## contract, and the exact bug `game_data.gd:make_monster` already shipped once.
func _on_assign_class(m, cls: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|%s|%d" % [str(m.id), cls, int(Career.week)])
	m.assign_class(cls, rng)
	_refresh_list()
	_refresh_detail()


## Step back out of the system entirely. The class derives from stats again and the kit follows it,
## which is precisely the pre-round-15 behaviour — so this is the migration in reverse and it must
## redraw for the same reason assignment does.
func _on_release_class(m) -> void:
	m.clear_class_assignment()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s|release|%d" % [str(m.id), int(Career.week)])
	m.assign_moveset(rng)
	_refresh_list()
	_refresh_detail()


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

## ⚠️ THE KNOWLEDGE THE PLAYER IS SUPPOSED TO HAVE EARNED, PUT WHERE THEY SPEND IT.
## `career.gd:champion_for()` already returns an archetype, a scouting `read` AND a `counter`, and
## `tactics.gd:champion_counter` has been asserted against the event log by
## `scenes/_probe_archetypes.tscn` since round 10 — but the only screen that showed any of it was
## the tournament sign-up card, and even that dropped the `counter` on the floor. So the player
## read "what beats this champion" on one screen and made every training decision on another,
## with nothing in between. CLAUDE.md's bar is a decision "made with knowledge the player has
## earned"; earned knowledge that is not on the screen where the decision happens is not knowledge,
## it is trivia. This connects the two — no new system, three existing ones wired together.
func _frontier_brief() -> Control:
	if not has_node("/root/Career"):
		return null
	var idx: int = Career.league_index
	var champ: Dictionary = Career.champion_for(idx)
	var counter: String = str(champ.get("counter", ""))
	var read: String = str(champ.get("read", ""))
	if counter == "" and read == "":
		return null

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	box.add_child(UiTheme.body_text("What you are training FOR — %s, %s (%s)" % [
		str(champ.get("name", "the titleholder")), str(champ.get("title", "")),
		str(champ.get("archetype", ""))], "primary"))
	if read != "":
		var read_lbl := UiTheme.body_text("   they fight like this: %s" % read, "secondary")
		read_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(read_lbl)
	if counter != "":
		var ctr := UiTheme.body_text("   what beats them: %s" % counter, "primary")
		ctr.add_theme_color_override("font_color", UiTheme.GOLD)
		ctr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(ctr)
	return box


func _training_preview_section(m) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UiTheme.SPACE_XS)

	box.add_child(UiTheme.heading("Training — what's on offer", 2))

	var brief := _frontier_brief()
	if brief != null:
		box.add_child(brief)
		box.add_child(HSeparator.new())

	box.add_child(UiTheme.body_text(
		"The push drill for each stat, run through the real week — aptitude, focus cost, stamina, age and this week's food are all already in these numbers.",
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


## The EXTREME drill for `stat` — the one a player pushing a shape actually spends. It is the
## honest row to show: it carries the biggest gain, the two paired drains, and the steepest focus
## cost, so it is where the trade is visible at all. (The basic and intensive tiers, and the whole
## diverse row, are on training.tscn with the same preview behind them.)
func _push_drill_id(stat: String) -> String:
	return "x" + stat.to_lower()


func _training_preview_row(m, stat: String) -> Control:
	var cap := GameData.stat_cap()
	var drill_id := _push_drill_id(stat)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_SM)

	var lbl := UiTheme.body_text(stat, "secondary")
	lbl.custom_minimum_size = Vector2(36, 0)
	row.add_child(lbl)

	var note: Dictionary = WeekPlan.drill_note(m, drill_id, cap)
	var desc: String
	if not bool(note.get("allowed", true)):
		desc = str(note.get("note", "unavailable"))
	else:
		# ⚠️ THE REAL TICK ON A CLONE. `preview_week` runs `apply_week` itself, so this cannot drift
		# from what Advance Week will do — the same invariant week.gd's header pins.
		var plan: Dictionary = WeekPlan.plan_for(m.id)
		var food: String = str(plan.get("food", ""))
		var pv: Dictionary = WeekLib.preview_week(m, {"kind": "train", "drillId": drill_id},
			Career.gold if has_node("/root/Career") else 0, 0, food, bool(plan.get("forage", false)),
			WeekPlan.price_of(food), cap, _league_name())
		var parts: Array = []
		var deltas: Dictionary = pv.get("statDeltas", {})
		for s in Classify.STATS:
			var d: float = float(deltas.get(s, 0.0))
			if absf(d) >= 0.5:
				parts.append("%+d %s" % [int(round(d)), s])
		desc = ", ".join(PackedStringArray(parts)) if parts.size() > 0 else "no gain"
		var fc: float = WeekLib.focus_cost(m, stat)
		var apt: float = WeekLib.stat_training_bonus(m, stat)
		var chain: Array = []
		if absf(apt - 1.0) > 0.01:
			chain.append("aptitude x%.2f" % apt)
		if fc < 0.999:
			chain.append("focus x%.2f" % fc)
		if chain.size() > 0:
			desc += "   (%s)" % ", ".join(PackedStringArray(chain))
		var after := _class_after(m, deltas)
		if after != str(m.class_name_):
			desc += "   → %s" % after
		var extra: String = str(note.get("note", ""))
		if extra != "":
			desc += "   · %s" % extra

	var desc_lbl := UiTheme.body_text(desc, "primary")
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(desc_lbl)

	return row


## Would this week's deltas tip the monster into a different class? Read-only — the deltas come
## from the preview, so this asks the question against the numbers the tick will actually apply.
## ⚠️ This is the single most decision-relevant line on the card: `docs/SHAPE_DIAGNOSIS.md` §2
## measured that the kit is redrawn from the CLASS (`week.gd:_redraft_if_stale`) and that a kit
## drawn for the wrong class collapses a roster's win rate from 56% to 4%. A class change is not
## cosmetic; it is the whole moveset.
## ⚠️ AND FOR A COMMITTED MONSTER THE QUESTION IS NO LONGER "would this tip me into a different
## class" — IT CANNOT. `recompute_class()` returns the stored choice, so a preview that answered
## with `class_for_stats` would print a class the tick will never produce: a lie on the line the
## comment above calls the most decision-relevant on the card. `docs/CLASS_REWORK.md` §10.2 row 9
## is right that this must be REPLACED rather than deleted — the useful question under assignment
## is which classes this week's training would OPEN at the gate, so that is what it now answers.
## The caller prints nothing when this returns the current class, so an uninformative week stays
## quiet exactly as before.
func _class_after(m, deltas: Dictionary) -> String:
	var stats_copy: Dictionary = m.stats.duplicate()
	for s in deltas:
		stats_copy[s] = float(stats_copy.get(s, 0.0)) + float(deltas[s])
	if not WeekLib.assignment_active(m):
		return Classify.class_for_stats(stats_copy)
	var nominal: float = float(WeekLib.stat_cap_for(m, GameData.stat_cap()))
	var before: Array = Classify.classes_available_for(m.stats, nominal)
	var after: Array = Classify.classes_available_for(stats_copy, nominal)
	var opened: Array = []
	for c in after:
		if not before.has(c):
			opened.append(str(c))
	if not opened.is_empty():
		return "opens %s" % ", ".join(PackedStringArray(opened))
	# nothing new opens: for an UNCOMMITTED body the derived class still moves and still redraws
	# the kit, so that answer is still live and still worth printing.
	if not m.is_class_assigned():
		return Classify.class_for_stats(stats_copy)
	return str(m.class_name_)


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
	# The week turning is the one irreversible thing on this screen — checkpoint it. See
	# `town_ui.gd:_autosave()` for why the project needs explicit save calls at all.
	if has_node("/root/SaveGame"):
		SaveGame.save_game()
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
