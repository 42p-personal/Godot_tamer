## THE RANCH SHOP — where gold turns back into capability.
##
## ⚠️ WITHOUT THIS THE ECONOMY HAS NO SINK BUT FOOD, so gold accumulates into meaninglessness and
## the barn stays at two forever. Every purchase here is permanent and changes what the player can
## DO, which is what makes winning a purse matter.
##
## ⚠️ THE LICENCE RANK GATE IS REAL, NOT COPY. `town.ts:22` records that the shop once *said*
## "Requires Silver league" while nothing checked it, so a Wood player with the gold walked
## straight into Draconics. **Reaching the league IS the cost; gold is only the receipt** — so
## both are enforced here, and a locked row states which of the two is missing.
extends Control

const UiTheme = preload("res://scripts/ui/theme.gd")

## Barn upgrades — price climbs steeply. ⚠️ PROPOSED, NOT BALANCED (`CLAUDE.md`: the baseline is
## suspended for the rebuild). The SHAPE is the intent: room 3 is affordable off a couple of
## purses, room 5 is a campaign goal.
const BARN_PRICES := [0, 0, 320, 700, 1400, 2600]
const MAX_BARN := 5

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

	var backdrop := TextureRect.new()
	var tex: Texture2D = Art.area_texture("shop")
	if tex != null:
		backdrop.texture = tex
		backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # ⚠️ default KEEP_SIZE ignores `size`
		backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		backdrop.anchor_right = 1; backdrop.anchor_bottom = 1
		backdrop.modulate = Color(1, 1, 1, 0.30)
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

	page.add_child(UiTheme.heading("The Ranch Shop", 1))
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
	_header.text = "%d gold · barn holds %d · %s league" % [
		Career.gold, Career.barn_capacity, Career.current_league_name()]

	_box.add_child(_barn_card())
	_box.add_child(_licence_card("Special License", 800, 4,
		"Draconic and Abyssal bloodlines appear at the Market."))
	_box.add_child(_licence_card("Elite License", 2000, 6,
		"Mythical bloodlines appear at the Market."))


func _barn_card() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("raised", UiTheme.GOLD))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	col.add_child(UiTheme.heading("Barn extension", 3))
	col.add_child(UiTheme.body_text(
		"Room for one more monster. ⚠️ Team leagues need bodies — Bronze fields 3, Platinum fields 5, and a cup you cannot field a team for is a cup you cannot enter.",
		"secondary"))

	var cur: int = Career.barn_capacity
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 38)
	btn.focus_mode = Control.FOCUS_ALL

	if cur >= MAX_BARN:
		btn.disabled = true
		btn.text = "Barn is at its largest (%d)" % MAX_BARN
	else:
		var price: int = BARN_PRICES[cur + 1] if cur + 1 < BARN_PRICES.size() else 9999
		if Career.gold < price:
			btn.disabled = true
			btn.text = "Extend to %d — %dg (need %d more)" % [cur + 1, price, price - Career.gold]
		else:
			btn.text = "Extend to %d — %dg" % [cur + 1, price]
			btn.pressed.connect(func():
				if Career.spend_gold(price):
					Career.barn_capacity += 1
					_refresh())
	col.add_child(btn)
	return panel


## ⚠️ TWO gates, and the button must name the one that is actually blocking. Saying "requires
## Silver" to a player who HAS Silver but lacks the gold is the same failure as not checking at all.
func _licence_card(label: String, price: int, league_req: int, effect: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	col.add_child(UiTheme.heading(label, 3))
	col.add_child(UiTheme.body_text(effect, "secondary"))

	var req_name: String = Career.league_at(league_req).get("name", "?")
	# ⚠️ NOT `Career.get_meta(label)`. Godot refuses a metadata identifier containing a space, so
	# `set_meta("Special License", true)` failed silently: the licence never registered, the button
	# never flipped to "✓ Held", and the player could buy the same licence repeatedly, losing 800g
	# (or 2000g) each time. `Career.licences` is a real field — see `career.gd:holds_licence()`.
	var owned: bool = Career.holds_licence(label)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 38)
	btn.focus_mode = Control.FOCUS_ALL

	if owned:
		btn.disabled = true
		btn.text = "✓ Held"
	elif Career.league_index < league_req:
		btn.disabled = true
		btn.text = "Locked — reach %s league (you are %s)" % [req_name, Career.current_league_name()]
		var note := UiTheme.body_text(
			"Reaching the league IS the cost. The gold is only the receipt.", "muted")
		col.add_child(note)
	elif Career.gold < price:
		btn.disabled = true
		btn.text = "%dg — need %d more" % [price, price - Career.gold]
	else:
		btn.text = "Buy — %dg" % price
		btn.pressed.connect(func():
			if Career.spend_gold(price):
				Career.grant_licence(label)
				_refresh())
	col.add_child(btn)
	return panel
