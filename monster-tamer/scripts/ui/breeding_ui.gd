## THE BREEDING RANCH — where a stable becomes a DYNASTY.
##
## ⚠️ THIS IS THE META-GAME'S LOAD-BEARING PILLAR, not a side feature. `CLAUDE.md`: *"The
## meta-game is a MIXTURE... advanced training knowledge plus breeding the right monsters to have
## the correct tactics and skills. Knowing WHICH monster to make is the skill."*
##
## ⚠️ AND IT IS THE ONLY WAY PAST A LEAGUE CAP. `potential` multiplies the league stat ceiling
## (`monster_instance.gd:33`), a wild monster is 1.0, and training cannot raise it. So a player who
## never breeds is permanently capped at the raw league number no matter how well they train —
## which is exactly the long-run engine that makes the ladder's top half reachable.
##
## ⚠️ ALL NUMBERS HERE ARE PLACEHOLDERS, and the user has explicitly accepted them as such. The
## SHAPE is ported from `town.ts` (cost, head start, potential climbing off the better parent);
## the VALUES are due a pass at the re-baseline (`CLAUDE.md`: the balance baseline is SUSPENDED).
extends Control

const UiTheme = preload("res://scripts/ui/theme.gd")
const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const ClassifyLib = preload("res://scripts/classify.gd")
const DeriveLib = preload("res://scripts/derive.gd")

## `town.ts:752 BREED_COST`.
const BREED_COST := 300

## `town.ts:774 BREED_HEAD_START` — the fraction of the parents' average stats a child hatches
## with. ⚠️ Tuned 0.45 → 0.15 → 0.30 in the React build, so this number has already been argued
## over twice: parents' stats SHOULD carry to the child, but the dynasty's real engine is the
## climbing `potential`, not the head start.
const BREED_HEAD_START := 0.30

## Per-generation potential step, and the ceiling it climbs toward. Placeholder values.
const POTENTIAL_STEP := 0.06
const MAX_POTENTIAL := 2.0

## ⚠️ Each parent is good for at most this many children (`town.ts:744`). Without a limit,
## breeding the same optimal pair forever is strictly correct and the system stops being a choice.
const MAX_CHILDREN_PER_PARENT := 2

var _box: VBoxContainer
var _header: Label
var _pick_a: int = -1
var _pick_b: int = -1
var _log_label: Label


func _ready() -> void:
	self.theme = UiTheme.base_theme()
	_build()
	_refresh()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.SURFACE
	bg.anchor_right = 1; bg.anchor_bottom = 1
	add_child(bg)

	var tex: Texture2D = Art.area_texture("breeding")
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

	page.add_child(UiTheme.heading("The Breeding Ranch", 1))
	_header = UiTheme.body_text("", "secondary")
	page.add_child(_header)

	_log_label = UiTheme.body_text("Choose two parents.", "primary")
	_log_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	page.add_child(_log_label)
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


func _children_of(mi) -> int:
	return int(mi.get_meta("children", 0))


## The child's potential: climbs off the BETTER parent, not their average. ⚠️ `town.ts:775`
## changed this deliberately in v0.88 — averaging meant one exceptional founder was diluted by a
## modest partner, which punished exactly the breeding the system wants to reward.
func _child_potential(a, b) -> float:
	var base: float = maxf(a.potential, b.potential)
	return minf(MAX_POTENTIAL, snappedf(base + POTENTIAL_STEP, 0.01))


func _refresh() -> void:
	for c in _box.get_children():
		c.queue_free()

	_header.text = "%d gold · %d in the barn (holds %d) · breeding costs %dg" % [
		Career.gold, Roster.monsters.size(), Career.barn_capacity, BREED_COST]

	if Roster.monsters.size() < 2:
		_box.add_child(UiTheme.body_text(
			"You need two monsters to breed. Recruit another at the Market.", "muted"))
		return

	for i in range(Roster.monsters.size()):
		_box.add_child(_parent_card(i))

	if _pick_a >= 0 and _pick_b >= 0:
		_box.add_child(_pairing_card())


func _parent_card(i: int) -> Control:
	var mi = Roster.monsters[i]
	var picked: bool = (i == _pick_a or i == _pick_b)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UiTheme.panel_style("raised", UiTheme.GOLD) if picked else UiTheme.panel_style("default"))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	var used: int = _children_of(mi)
	col.add_child(UiTheme.heading("%s — %s" % [mi.species_name, mi.class_name_], 3))
	col.add_child(UiTheme.body_text(
		"%s body · potential ×%.2f · %d of %d matings used" % [
			mi.body, mi.potential, used, MAX_CHILDREN_PER_PARENT], "secondary"))

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 34)
	btn.focus_mode = Control.FOCUS_ALL
	if used >= MAX_CHILDREN_PER_PARENT:
		btn.disabled = true
		btn.text = "Retired from the stud book — %d children already" % used
	elif picked:
		btn.text = "✓ Chosen — tap to release"
		btn.pressed.connect(func():
			if _pick_a == i: _pick_a = -1
			elif _pick_b == i: _pick_b = -1
			_refresh())
	else:
		btn.text = "Choose as a parent"
		btn.pressed.connect(func():
			if _pick_a < 0: _pick_a = i
			elif _pick_b < 0: _pick_b = i
			else: _pick_b = i
			_refresh())
	col.add_child(btn)
	return panel


func _pairing_card() -> Control:
	var a = Roster.monsters[_pick_a]
	var b = Roster.monsters[_pick_b]
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("raised", UiTheme.GOLD))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	var pot := _child_potential(a, b)
	col.add_child(UiTheme.heading("%s × %s" % [a.species_name, b.species_name], 2))

	# ⚠️ Say what the child INHERITS before the gold is spent. Potential is the whole point and it
	# is invisible unless stated: it multiplies every league cap the child will ever train against.
	col.add_child(UiTheme.body_text(
		"The child hatches with %d%% of its parents' average stats, and a bloodline potential of ×%.2f." % [
			int(BREED_HEAD_START * 100.0), pot], "secondary"))
	var why := UiTheme.body_text(
		"Potential multiplies every league ceiling it will ever train against — at ×%.2f its Wood cap is %d instead of %d. This is the only way past a league cap; training cannot raise it." % [
			pot, int(Career.stat_cap_for_league(0) * pot), int(Career.stat_cap_for_league(0))], "primary")
	why.add_theme_color_override("font_color", UiTheme.GOLD)
	col.add_child(why)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 40)
	btn.focus_mode = Control.FOCUS_ALL
	if _pick_a == _pick_b:
		btn.disabled = true
		btn.text = "A monster cannot breed with itself"
	elif Roster.monsters.size() >= Career.barn_capacity:
		btn.disabled = true
		btn.text = "Barn is full (%d of %d) — extend it at the Shop" % [
			Roster.monsters.size(), Career.barn_capacity]
	elif Career.gold < BREED_COST:
		btn.disabled = true
		btn.text = "Need %d more gold" % (BREED_COST - Career.gold)
	else:
		btn.text = "Breed — %dg" % BREED_COST
		btn.pressed.connect(_on_breed)
	col.add_child(btn)
	return panel


func _on_breed() -> void:
	var a = Roster.monsters[_pick_a]
	var b = Roster.monsters[_pick_b]
	if not Career.spend_gold(BREED_COST):
		return

	var pot := _child_potential(a, b)
	var rng := RandomNumberGenerator.new()
	rng.seed = Career.week * 7919 + _pick_a * 31 + _pick_b

	# Inherit the better parent's species so the child reads as part of the line.
	var donor = a if a.potential >= b.potential else b
	var child = MonsterInstanceScript.new()
	child.id = "bred-%d-%d" % [Career.week, rng.randi() % 100000]
	child.species_id = donor.species_id
	child.species_name = donor.species_name
	child.body = donor.body
	child.potential = pot
	child.age_weeks = 0  # ⚠️ born, not bought — it has a full career ahead of it

	# ⚠️ HEAD START ONLY, never the parents' full stats. A child that inherited everything would
	# make breeding strictly dominant over training and collapse half the game into one button.
	child.stats = {}
	for stat in ["STR", "DEX", "CON", "WIS", "INT", "CHA"]:
		var avg: float = (float(a.stats.get(stat, 0.0)) + float(b.stats.get(stat, 0.0))) * 0.5
		child.stats[stat] = maxf(1.0, round(avg * BREED_HEAD_START))

	child.class_name_ = ClassifyLib.class_for_stats(child.stats)
	child.role = ClassifyLib.role_of_class(child.class_name_)
	child.mana_role = ClassifyLib.mana_role_of(child.stats, child.class_name_)
	child.basic_attack = ClassifyLib.basic_attack_for(child.stats)
	child.max_hp = DeriveLib.max_hp(child.stats["CON"])
	child.max_mp = DeriveLib.max_mana(child.stats["WIS"], child.stats["INT"])
	child.hp = child.max_hp
	child.mp = child.max_mp
	if child.has_method("assign_moveset"):
		child.assign_moveset(rng)

	a.set_meta("children", _children_of(a) + 1)
	b.set_meta("children", _children_of(b) + 1)
	Roster.monsters.append(child)

	_log_label.text = "%s born — %s, potential ×%.2f. Its Wood ceiling is %d." % [
		child.species_name, child.class_name_, pot, int(Career.stat_cap_for_league(0) * pot)]
	_log_label.add_theme_color_override("font_color", UiTheme.GOLD)
	_pick_a = -1
	_pick_b = -1
	_refresh()
