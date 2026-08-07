## THE LAB — cryo storage, and the freezer bill that makes it a decision.
##
## ⚠️ THE LAB'S JOB IS TO DECOUPLE THE BARN FROM THE BLOODLINE. A monster you want to breed from
## later does not need to occupy a barn slot in the meantime — but it does not become free either,
## because the freezer charges rent EVERY WEEK (`town.ts:742 labUpkeepPerFrozen`).
##
## ⚠️ WITHOUT THE RENT THIS IS AN INFINITE BARN AND THE 2-SLOT LIMIT STOPS MEANING ANYTHING. The
## upkeep is not flavour; it is the entire reason freezing is a trade rather than a free win.
##
## ⚠️ ALL NUMBERS ARE PLACEHOLDERS, accepted as such by the user. The SHAPE is ported from
## `town.ts`; the VALUES are due a pass at the re-baseline (the baseline is SUSPENDED).
extends Control

const UiTheme = preload("res://scripts/ui/theme.gd")

## Weekly rent per frozen monster (`town.ts:RENTAL_PER_FROZEN`). Placeholder.
const RENTAL_PER_FROZEN := 12

var _box: VBoxContainer
var _header: Label


func _ready() -> void:
	self.theme = UiTheme.base_theme()
	_build()
	_refresh()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.SURFACE
	bg.anchor_right = 1; bg.anchor_bottom = 1
	add_child(bg)

	var tex: Texture2D = Art.area_texture("lab")
	if tex != null:
		var backdrop := TextureRect.new()
		backdrop.texture = tex
		backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		backdrop.anchor_right = 1; backdrop.anchor_bottom = 1
		backdrop.modulate = Color(1, 1, 1, 0.28)
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(backdrop)

	var margin := MarginContainer.new()
	margin.anchor_right = 1; margin.anchor_bottom = 1
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, UiTheme.SPACE_XL)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	margin.add_child(page)

	page.add_child(UiTheme.heading("The Lab", 1))
	_header = UiTheme.body_text("", "secondary")
	page.add_child(_header)
	page.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)

	page.add_child(HSeparator.new())
	var back := Button.new()
	back.text = "Back to Town"
	back.custom_minimum_size = Vector2(0, 44)
	back.focus_mode = Control.FOCUS_ALL
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/town.tscn"))
	page.add_child(back)


func _refresh() -> void:
	for c in _box.get_children():
		c.queue_free()

	var frozen: Array = Roster.frozen if "frozen" in Roster else []
	var rent: int = frozen.size() * RENTAL_PER_FROZEN
	_header.text = "%d gold · %d in the barn (holds %d) · %d frozen · freezer rent %dg/week" % [
		Career.gold, Roster.monsters.size(), Career.barn_capacity, frozen.size(), rent]

	_box.add_child(UiTheme.body_text(
		"Freezing takes a monster out of the barn without losing it. It stops ageing and cannot train, compete or breed while frozen — and the freezer charges %dg every week it stays in." % RENTAL_PER_FROZEN,
		"secondary"))

	if not Roster.monsters.is_empty():
		_box.add_child(UiTheme.heading("In the barn", 2))
	for i in range(Roster.monsters.size()):
		_box.add_child(_barn_row(i))

	if not frozen.is_empty():
		_box.add_child(UiTheme.heading("In the freezer", 2))
	for i in range(frozen.size()):
		_box.add_child(_frozen_row(i))


func _barn_row(i: int) -> Control:
	var mi = Roster.monsters[i]
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	col.add_child(UiTheme.heading("%s — %s · potential ×%.2f" % [
		mi.species_name, mi.class_name_, mi.potential], 3))

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 34)
	btn.focus_mode = Control.FOCUS_ALL
	# ⚠️ Never freeze the last monster — an empty barn cannot advance a week or enter a cup, and
	# the player would have to pay rent to get back to a playable state.
	if Roster.monsters.size() <= 1:
		btn.disabled = true
		btn.text = "Your only monster — the barn cannot be left empty"
	else:
		btn.text = "Freeze — %dg/week thereafter" % RENTAL_PER_FROZEN
		btn.pressed.connect(func():
			if not ("frozen" in Roster):
				return
			Roster.frozen.append(mi)
			Roster.monsters.remove_at(i)
			Roster.selected_index = 0
			_refresh())
	col.add_child(btn)
	return panel


func _frozen_row(i: int) -> Control:
	var frozen: Array = Roster.frozen
	var mi = frozen[i]
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("raised", UiTheme.GOLD))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	col.add_child(UiTheme.heading("%s — %s · potential ×%.2f" % [
		mi.species_name, mi.class_name_, mi.potential], 3))
	col.add_child(UiTheme.body_text("Frozen. Not ageing, not training, costing %dg a week." % RENTAL_PER_FROZEN, "muted"))

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 34)
	btn.focus_mode = Control.FOCUS_ALL
	if Roster.monsters.size() >= Career.barn_capacity:
		btn.disabled = true
		btn.text = "Barn is full (%d of %d) — extend it at the Shop" % [
			Roster.monsters.size(), Career.barn_capacity]
	else:
		btn.text = "Thaw into the barn"
		btn.pressed.connect(func():
			Roster.monsters.append(mi)
			Roster.frozen.remove_at(i)
			_refresh())
	col.add_child(btn)
	return panel
