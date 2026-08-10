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

## ⚠️ THE OFFER RULES AND THE PRICE FORMULA MOVED TO `roster.gd` AND MUST NOT COME BACK HERE.
## Three things buy monsters and only one of them is a screen: this UI, the career autopilot
## (`_probe_career_arc.gd`) and `_probe_recruit.gd`. While the rules lived in this file the other
## two carried hand-copied mirrors of them — see the long note above `Roster.market_offers()` for
## the measurement that came out of that and the graded market that replaced it.
const RosterLib = preload("res://scripts/roster.gd")
const RELEASE_REFUND_FRAC := RosterLib.RELEASE_REFUND_FRAC
const WeekLib = preload("res://scripts/week.gd")

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
	subtitle.text = "Prospects are cheap, raw and keep their full ceiling. Veterans can play today — and never train past it. Choose which season you are buying for."
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


## Deterministic per-week stock — one call, because the rules live in `roster.gd` now.
func _generate_offers() -> void:
	offers.clear()
	var week := (Career.week if has_node("/root/Career") else 1)
	for o in Roster.market_offers(week, OFFER_COUNT):
		o["id"] = o["mi"].species_id
		offers.append(o)


## Price/refund basis shared by both sides of this screen. Delegates — see the ⚠️ at the top.
func _estimate_value(mi) -> int:
	return Roster.market_price(mi)


## The species' authored training profile, plus the class its aptitude pair points at. ⚠️ Read from
## `week.gd:training_profile`/`stat_training_bonus` — the tick's own functions — so this row can
## never disagree with the drills it is advising about.
func _aptitude_line(mi) -> String:
	var prof: Dictionary = WeekLib.training_profile(mi)
	var major := str(prof.get("major", ""))
	var minor := str(prof.get("minor", ""))
	var flaw := str(prof.get("flaw", ""))
	var parts: Array = []
	if major != "":
		parts.append("%s ×%.2f" % [major, WeekLib.stat_training_bonus(mi, major)])
	if minor != "" and minor != major:
		parts.append("%s ×%.2f" % [minor, WeekLib.stat_training_bonus(mi, minor)])
	if flaw != "":
		parts.append("%s ×%.2f" % [flaw, WeekLib.stat_training_bonus(mi, flaw)])
	var suits := _class_for_pair(major, minor)
	if suits == "":
		suits = _class_for_pair(minor, major)
	var tail := ("  →  trains toward %s" % suits) if suits != "" else ""
	if parts.is_empty():
		return "no authored training aptitude"
	return "trains: %s%s" % [", ".join(PackedStringArray(parts)), tail]


func _class_for_pair(primary: String, secondary: String) -> String:
	if primary == "" or secondary == "" or primary == secondary:
		return ""
	for c in GameData.classes:
		if str(c.get("primary", "")) == primary and str(c.get("secondary", "")) == secondary:
			return str(c.get("name", ""))
	return ""


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
	_row(col, "%s — %s" % [mi.species_name, str(o.get("label", ""))], 15, _grade_colour(str(o.get("grade", ""))))
	_row(col, "%s · %s" % [mi.body, mi.class_name_], 12, Color(0.65, 0.65, 0.7))
	# ⚠️ THE TRADE-OFF HAS TO BE ON THE CARD OR IT IS NOT A DECISION, IT IS A SURPRISE.
	# A Veteran is the FAST, EXPENSIVE, CEILING-LIMITED answer and a Prospect is the SLOW, CHEAP,
	# HIGH-CEILING one — but `potential` silently multiplies the league cap in `week.gd`, and an
	# invisible ceiling is exactly the kind of authored-but-unreadable rule this project keeps
	# finding. So the card states, in the player's own units: what it is worth NOW (mean stat),
	# what it can ever become (ceiling = league cap x potential), and how much of its career is
	# already spent.
	_row(col, "now %d/stat · ceiling %d (×%.2f) · %s" % [
		int(round(_mean_stat(mi))), int(round(GameData.stat_cap() * mi.potential)),
		mi.potential, _age_phrase(mi)], 12, _grade_colour(str(o.get("grade", ""))))
	# ⚠️ THE CLASS DECISION IS MADE AT THE MARKET, NOT AT THE STABLE, and it was invisible here.
	# What a recruit is WORTH depends on which class it will end up committed to, and the thing that
	# decides that is `trainingProfile` — a species' authored major/minor/flaw — which nothing on
	# this screen showed. Two recruits with identical stats and identical prices can be a 1.20x and
	# a 0.80x on the same stat, and the player found out weeks later. CLAUDE.md's bar is a decision
	# "made with knowledge the player has earned"; this is the earnable half, printed where it is
	# spent. The class NAME here is a suggestion from aptitude, never a lock — any species can train
	# into any class, and the whole point of an ASSIGNED class is that this row is advice.
	_row(col, _aptitude_line(mi), 12, FOCUS_COLOR)
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
	# ⚠️ A RECRUIT NEEDS A CAREER-SLOT ID BEFORE IT ENTERS THE STABLE. `GameData.make_monster()`
	# leaves `id` empty, and `week_plan.gd` keys every plan by it while `week.gd` seeds the
	# training roll off it — so two market recruits with the same empty id shared one plan slot
	# and one RNG stream. See `roster.gd:next_slot_id()`.
	o["mi"].id = Roster.next_slot_id()
	Roster.monsters.append(o["mi"])
	offers.erase(o)
	_render_offers()
	_render_release()
	_refresh_gold()


## Grade colour, so the three kinds are separable at a glance and not only by reading.
## ⚠️ Hue is a SECOND channel here, never the only one — the grade is spelled out in the title
## row as well (docs/ACCESSIBILITY.md: never encode meaning in colour alone).
func _grade_colour(grade: String) -> Color:
	match grade:
		"veteran": return Color(0.92, 0.66, 0.40)
		"journeyman": return Color(0.72, 0.82, 0.95)
		_: return Color(0.62, 0.86, 0.66)


func _mean_stat(mi) -> float:
	var t := 0.0
	for s in Classify.STATS:
		t += float(mi.stats.get(s, 0.0))
	return t / float(Classify.STATS.size())


## How much of this body's career is already behind it, said in years rather than in weeks —
## a number the stable screen also speaks.
func _age_phrase(mi) -> String:
	var span: float = maxf(1.0, mi.lifespan_years * 48.0)
	var left: int = int(round((span - float(mi.age_weeks)) / 48.0))
	return "%dy left of %dy" % [maxi(0, left), int(round(mi.lifespan_years))]


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
