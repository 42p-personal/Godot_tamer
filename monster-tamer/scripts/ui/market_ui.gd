## THE MARKET — recruit a new partner, or release one back.
##
## A deliberately SIMPLIFIED stand-in for `town.ts`'s real market (monthly stock, market scout,
## market coach — see docs/META_GAME_DISPOSITION.md §5, none of it ported yet). Rather than fake
## that system, this does the smallest REAL version: offers are generated deterministically off
## `Career.week` (drawn from the painted twelve in `Art.ROSTER` the player doesn't already own),
## and the recruit's price reads straight off its own generated stats via `_estimate_value` — a
## recruit that looks better costs more for a legible reason, not an opaque roll. Buying spends
## real `Career.gold` and adds a real `MonsterInstance` to `Roster.monsters`; releasing removes it
## and refunds a fraction of the same value estimate. Offers stay put across a purchase within the
## same week (buying doesn't reshuffle the rest of the stock) and only regenerate when
## `Career.week` changes — which is what ties this to the Town hub's "End Week" button.
##
## UI built entirely in code, matching stable_ui.gd/training_ui.gd's established house style.
extends Control

const FOCUS_COLOR := Color(0.40, 0.85, 1.0)

## Fallback cap, used ONLY if the Career autoload is missing (a standalone scene run). The real
## cap is `Career.barn_capacity` — town.ts:START_BARN is 2, and CLAUDE.md/CORE_LOOP_PORT.md are
## explicit that a two-slot barn is load-bearing, not a placeholder: it's what makes the first
## recruit a real decision instead of a formality. No barn-upgrade purchase exists yet (that's the
## locked "Ranch Shop" door on the Town map), so this cap is fixed at 2 for the whole vertical
## slice.
const FALLBACK_BARN_CAPACITY := 2
const OFFER_COUNT := 4
const RELEASE_REFUND_FRAC := 0.35

var accent: Color
var gold_label: Label
var offers_box: VBoxContainer
var release_box: VBoxContainer
var offer_rows: Array = []
var release_rows: Array = []

var offers: Array = []  # Array[Dictionary] {id, mi, price}
var _cached_week: int = -1


func _ready() -> void:
	accent = Art.team_identity(0)["colour"]
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var tex := Art.area_texture("market")
	if tex != null:
		var bg_rect := TextureRect.new()
		bg_rect.anchor_right = 1; bg_rect.anchor_bottom = 1
		bg_rect.texture = tex
		bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(bg_rect)
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.09, 0.09, 0.12)
		bg.anchor_right = 1; bg.anchor_bottom = 1
		add_child(bg)

	var scrim := ColorRect.new()
	scrim.color = Color(0.04, 0.04, 0.06, 0.6)
	scrim.anchor_right = 1; scrim.anchor_bottom = 1
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var root_margin := MarginContainer.new()
	root_margin.anchor_right = 1; root_margin.anchor_bottom = 1
	root_margin.add_theme_constant_override("margin_left", 24)
	root_margin.add_theme_constant_override("margin_top", 20)
	root_margin.add_theme_constant_override("margin_right", 24)
	root_margin.add_theme_constant_override("margin_bottom", 20)
	add_child(root_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	root_margin.add_child(vbox)

	# ---- header ----
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	vbox.add_child(header)

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_col)

	var title := Label.new()
	title.text = "The Market"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35))
	title_col.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "A simplified recruiting desk — the full monthly stock, scouting and coach system is still TypeScript-only."
	subtitle.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD
	title_col.add_child(subtitle)

	gold_label = Label.new()
	gold_label.add_theme_font_size_override("font_size", 16)
	gold_label.add_theme_color_override("font_color", accent)
	header.add_child(gold_label)

	var back_btn := Button.new()
	back_btn.text = "← Town"
	back_btn.focus_mode = Control.FOCUS_ALL
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/town.tscn"))
	header.add_child(back_btn)

	var hsplit := HBoxContainer.new()
	hsplit.add_theme_constant_override("separation", 20)
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(hsplit)

	# ---- left: recruits ----
	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", 8)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_child(left_col)

	var recruits_title := Label.new()
	recruits_title.text = "This week's recruits"
	recruits_title.add_theme_font_size_override("font_size", 18)
	recruits_title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.93))
	left_col.add_child(recruits_title)

	var offers_scroll := ScrollContainer.new()
	offers_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(offers_scroll)

	offers_box = VBoxContainer.new()
	offers_box.add_theme_constant_override("separation", 8)
	offers_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offers_scroll.add_child(offers_box)

	# ---- right: release ----
	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", 8)
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_child(right_col)

	var release_title := Label.new()
	release_title.text = "Your stable"
	release_title.add_theme_font_size_override("font_size", 18)
	release_title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.93))
	right_col.add_child(release_title)

	var release_hint := Label.new()
	release_hint.text = "Release a monster for a partial refund."
	release_hint.add_theme_font_size_override("font_size", 12)
	release_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	right_col.add_child(release_hint)

	var release_scroll := ScrollContainer.new()
	release_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_child(release_scroll)

	release_box = VBoxContainer.new()
	release_box.add_theme_constant_override("separation", 8)
	release_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	release_scroll.add_child(release_box)


func _refresh() -> void:
	var current_week := (Career.week if has_node("/root/Career") else 1)
	if offers.is_empty() or _cached_week != current_week:
		_generate_offers()
		_cached_week = current_week
	_render_offers()
	_render_release()
	_refresh_gold()


## Deterministic per-week stock: same seed until `Career.week` changes, drawn from the species
## the player doesn't already own so a recruit trip introduces something new to look at (mirrors
## `roster.gd:make_rival_team`'s own fallback — if owning most of the painted set leaves too few
## unowned species, top up from the full painted pool rather than running dry).
func _generate_offers() -> void:
	offers.clear()
	var owned := {}
	for m in Roster.monsters:
		owned[m.species_id] = true
	var pool: Array = Art.ROSTER.filter(func(id): return not owned.has(id))
	if pool.size() < OFFER_COUNT:
		pool = Art.ROSTER.duplicate()

	var rng := RandomNumberGenerator.new()
	var week := (Career.week if has_node("/root/Career") else 1)
	rng.seed = week * 104729  # a large prime so consecutive weeks don't alias into similar shuffles

	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]; pool[i] = pool[j]; pool[j] = tmp

	var n := mini(OFFER_COUNT, pool.size())
	for i in range(n):
		var t := rng.randf_range(0.05, 0.5)
		var mi = GameData.make_monster(pool[i], t, rng)
		if mi == null:
			continue
		offers.append({"id": pool[i], "mi": mi, "price": _estimate_value(mi)})


## Price/refund basis shared by both sides of this screen — reads directly off the monster's own
## generated stats relative to the current league cap, so the number on the button is explained by
## something the player can see (the portrait, class, stats), not an opaque roll.
func _estimate_value(mi) -> int:
	var cap: float = GameData.stat_cap()
	var total := 0.0
	for stat in Classify.STATS:
		total += float(mi.stats.get(stat, 0.0))
	var frac: float = clampf(total / maxf(1.0, cap * Classify.STATS.size()), 0.0, 1.0)
	return int(round(120.0 + frac * 520.0))


func _render_offers() -> void:
	for c in offers_box.get_children():
		c.queue_free()
	offer_rows.clear()

	if offers.is_empty():
		_row(offers_box, "Sold out — restocks with the next week.", 13, Color(0.6, 0.6, 0.65))
		return

	var stable_full: bool = Roster.monsters.size() >= _barn_capacity()
	for o in offers:
		var row := _offer_row(o, stable_full)
		offers_box.add_child(row)
		offer_rows.append(row)
	_wire_vertical_focus(offer_rows)


func _offer_row(o: Dictionary, stable_full: bool) -> PanelContainer:
	var mi = o["mi"]
	var panel := _card_panel()

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	panel.add_child(hbox)

	hbox.add_child(_portrait(mi.species_id, mi.species_name, Vector2(44, 44)))

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(col)
	_row(col, mi.species_name, 15, Color(0.9, 0.9, 0.93))
	_row(col, "%s · %s" % [mi.body, mi.class_name_], 12, Color(0.65, 0.65, 0.7))
	# The one-line flavour is the recruit pitch; the full bestiary story lives on the stable
	# detail once the monster is yours.
	var pitch := Label.new()
	pitch.text = str(mi.flavour)
	pitch.add_theme_font_size_override("font_size", 11)
	pitch.add_theme_color_override("font_color", Color(0.55, 0.55, 0.62))
	pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pitch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(pitch)

	var buy_btn := Button.new()
	buy_btn.text = "Recruit · %dg" % int(o["price"])
	buy_btn.focus_mode = Control.FOCUS_ALL
	var have_gold: bool = has_node("/root/Career") and Career.gold >= int(o["price"])
	buy_btn.disabled = stable_full or not have_gold
	if stable_full:
		buy_btn.tooltip_text = "Stable full (%d) — release a monster first." % _barn_capacity()
	elif not have_gold:
		buy_btn.tooltip_text = "Not enough gold."
	buy_btn.pressed.connect(func(): _on_buy(o))
	hbox.add_child(buy_btn)

	return panel


## Removes the bought offer from the CURRENT session's list rather than regenerating the whole
## stock — buying one recruit shouldn't reshuffle everyone else standing next to it. The full list
## only regenerates once `Career.week` actually advances (see `_refresh`).
func _barn_capacity() -> int:
	return Career.barn_capacity if has_node("/root/Career") else FALLBACK_BARN_CAPACITY


func _on_buy(o: Dictionary) -> void:
	if not has_node("/root/Career") or not has_node("/root/Roster"):
		return
	if Roster.monsters.size() >= _barn_capacity():
		return
	if not Career.spend_gold(int(o["price"])):
		return
	Roster.monsters.append(o["mi"])
	offers.erase(o)
	_render_offers()
	_render_release()
	_refresh_gold()


func _render_release() -> void:
	for c in release_box.get_children():
		c.queue_free()
	release_rows.clear()

	if not has_node("/root/Roster") or Roster.monsters.is_empty():
		_row(release_box, "No monsters in the stable yet.", 13, Color(0.6, 0.6, 0.65))
		return

	for mi in Roster.monsters:
		var row := _release_row(mi)
		release_box.add_child(row)
		release_rows.append(row)
	_wire_vertical_focus(release_rows)


func _release_row(mi) -> PanelContainer:
	var panel := _card_panel()

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	panel.add_child(hbox)

	hbox.add_child(_portrait(mi.species_id, mi.species_name, Vector2(40, 40)))

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(col)
	_row(col, mi.species_name, 14, Color(0.9, 0.9, 0.93))
	_row(col, "%s · %s" % [mi.body, mi.class_name_], 12, Color(0.65, 0.65, 0.7))

	var refund := int(round(_estimate_value(mi) * RELEASE_REFUND_FRAC))
	var release_btn := Button.new()
	release_btn.text = "Release · +%dg" % refund
	release_btn.focus_mode = Control.FOCUS_ALL
	release_btn.tooltip_text = "%s leaves the stable for good." % mi.species_name
	release_btn.pressed.connect(func(): _on_release(mi, refund))
	hbox.add_child(release_btn)

	return panel


func _on_release(mi, refund: int) -> void:
	if not has_node("/root/Roster"):
		return
	Roster.monsters.erase(mi)
	if Roster.selected_index >= Roster.monsters.size():
		Roster.selected_index = maxi(0, Roster.monsters.size() - 1)
	if has_node("/root/Career"):
		Career.add_gold(refund)
	_render_release()
	_render_offers()  # stable-full state may have just changed
	_refresh_gold()


func _refresh_gold() -> void:
	if gold_label == null:
		return
	gold_label.text = "%d gold" % (Career.gold if has_node("/root/Career") else 0)


## ⚠️ ACCESSIBILITY (docs/ACCESSIBILITY.md #1 pattern, reused from stable_ui.gd) — explicit
## up/down focus neighbours between consecutive rows in a scrolled list, rather than trusting
## Godot's automatic spatial-neighbour search inside a ScrollContainer.
func _wire_vertical_focus(rows: Array) -> void:
	for i in range(rows.size()):
		var btn: Button = rows[i].get_child(0).get_child(rows[i].get_child(0).get_child_count() - 1)
		if i > 0:
			var prev_btn: Button = rows[i - 1].get_child(0).get_child(rows[i - 1].get_child(0).get_child_count() - 1)
			btn.focus_neighbor_top = btn.get_path_to(prev_btn)
		if i < rows.size() - 1:
			var next_btn: Button = rows[i + 1].get_child(0).get_child(rows[i + 1].get_child(0).get_child_count() - 1)
			btn.focus_neighbor_bottom = btn.get_path_to(next_btn)


func _card_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.13, 0.16)
	sb.border_color = Color(0.24, 0.24, 0.28)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 6; sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	return panel


## Real portrait if Art has one, otherwise the species' own initials on an accent-tinted panel at
## the SAME footprint — duplicated from stable_ui.gd's `_portrait` rather than shared, since that
## file is out of this stream's scope to edit or refactor.
func _portrait(species_id: String, species_name: String, portrait_size: Vector2) -> Control:
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
	sb.bg_color = Color(accent.r, accent.g, accent.b, 0.16)
	sb.border_color = accent
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = species_name.substr(0, 2).to_upper()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", accent)
	lbl.add_theme_font_size_override("font_size", int(portrait_size.y * 0.35))
	panel.add_child(lbl)
	return panel


func _row(parent: Node, text: String, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
