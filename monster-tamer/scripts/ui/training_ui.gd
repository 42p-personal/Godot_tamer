## TRAINING — book a drill for the week. ⚠️ IT SPENDS NOTHING.
##
## ⚠️ THIS SCREEN USED TO BE THE BUG. It called `GameData.train()` on click, which applied a stat
## gain immediately with no clock, no stamina and no gold — so the player could click a drill an
## unlimited number of times inside one week. That is what the user meant by *"i can still train
## infintely"*.
##
## The fix is PLAN-THEN-COMMIT, not a bigger cost. Clicking here writes `WeekPlan`; stats move only
## when the Stable's Advance Week runs `week.gd`'s tick. One action per monster per week, because
## the week is what advances.
##
## ⚠️ AND NOTE WHAT IS *NOT* THE FIX: stamina. `week.gd` mirrors `game.ts:149 staminaMalus()`,
## which floors at 0.5 and NEVER blocks a drill — at zero stamina you keep training at half rate,
## in this build and in the React one. The real ceiling is the league cap
## (`game.ts:361 statCapFor`), which is why the bars here read against it and never `/100`.
extends Control

const UiTheme = preload("res://scripts/ui/theme.gd")
const WeekLib = preload("res://scripts/week.gd")

var stat_box: VBoxContainer
var header_label: Label
var plan_label: Label


func _ready() -> void:
	self.theme = UiTheme.base_theme()
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.SURFACE
	bg.anchor_right = 1; bg.anchor_bottom = 1
	add_child(bg)

	var margin := MarginContainer.new()
	margin.anchor_right = 1; margin.anchor_bottom = 1
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, UiTheme.SPACE_XL)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	margin.add_child(page)

	page.add_child(UiTheme.heading("Training", 1))
	header_label = UiTheme.body_text("", "secondary")
	page.add_child(header_label)

	plan_label = UiTheme.body_text("Nothing booked this week.", "primary")
	plan_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	page.add_child(plan_label)

	page.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)

	stat_box = VBoxContainer.new()
	stat_box.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	stat_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stat_box)

	page.add_child(HSeparator.new())
	var back := Button.new()
	back.text = "Back to the Stable"
	back.custom_minimum_size = Vector2(0, 44)
	back.focus_mode = Control.FOCUS_ALL
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/stable.tscn"))
	page.add_child(back)


func _cap() -> float:
	return Career.current_stat_cap() if has_node("/root/Career") else 300.0


func _league_name() -> String:
	return Career.current_league_name() if has_node("/root/Career") else "current league"


func _refresh() -> void:
	var m = Roster.selected()
	for c in stat_box.get_children():
		c.queue_free()
	if m == null:
		header_label.text = "No monster selected — buy one at the Market first."
		plan_label.text = ""
		return

	header_label.text = "%s — %s · stamina %d/100 · happiness %d/10 · %s ceiling %d" % [
		m.species_name, m.class_name_, int(round(m.stamina)), m.happiness,
		_league_name(), int(round(_cap()))]

	_refresh_plan_label(m)

	# ⚠️ FEEDING IS PART OF THE WEEK'S PLAN, NOT A SEPARATE ERRAND. Without this section gold only
	# ever moved at the Market, so the weekly economy never bit and food was a mechanic on paper.
	# It sits ABOVE the drills deliberately: what a monster eats changes what its drill is worth
	# (training foods add +30% to their two stats), so the food is the first decision, not an
	# afterthought.
	stat_box.add_child(_food_card(m))

	# Rest is a real option and must be as easy to pick as a drill — resting is how stamina comes
	# back, and a week spent resting is a genuine strategic choice, not a failure state.
	stat_box.add_child(_rest_card(m))
	for d in WeekLib.DRILLS:
		stat_box.add_child(_drill_card(m, d))


## The week's food. Paid food costs gold; forage is free but costs stamina AND happiness — hunger
## is never free, it is only ever paid differently (`docs/CORE_LOOP_PORT.md` §3).
func _food_card(m) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	col.add_child(UiTheme.heading("This week's food", 3))

	var plan: Dictionary = WeekPlan.plan_for(m.id)
	var chosen: String = str(plan.get("food", ""))
	var foraging: bool = bool(plan.get("forage", false))
	var gold: int = Career.gold if has_node("/root/Career") else 0

	if chosen == "" and not foraging:
		col.add_child(UiTheme.body_text("Nothing chosen — it will go hungry and lose heart.", "muted"))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", UiTheme.SPACE_SM)
	grid.add_theme_constant_override("v_separation", UiTheme.SPACE_XS)
	col.add_child(grid)

	for f in WeekLib.FOODS:
		var fid: String = str(f["id"])
		var price: int = WeekPlan.price_of(fid)
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_ALL
		btn.custom_minimum_size = Vector2(0, 34)
		var boost: Array = f.get("boostStats", [])
		var label := "%s · %dg" % [str(f["name"]), price]
		if not boost.is_empty():
			label += "  (+30%% %s)" % "/".join(PackedStringArray(boost))
		if fid == chosen:
			btn.text = "✓ " + label
			btn.disabled = true
		elif price > gold:
			btn.text = label + " — can't afford"
			btn.disabled = true
		else:
			btn.text = label
			btn.pressed.connect(func():
				WeekPlan.set_food(m.id, fid)
				_refresh())
		# ⚠️ A monster's FAVOURITE and HATED foods differ per monster — that is exactly why feeding
		# cannot be one bulk button (town.ts:advanceWeek feeds per-monster for this reason).
		var delta: int = WeekLib.food_happiness_delta(m, fid)
		if delta > 0:
			btn.tooltip_text = "Favourite — happiness +%d, and happier monsters roll higher gains." % delta
		elif delta < 0:
			btn.tooltip_text = "Hates this — happiness %d." % delta
		grid.add_child(btn)

	var forage_btn := Button.new()
	forage_btn.focus_mode = Control.FOCUS_ALL
	forage_btn.custom_minimum_size = Vector2(0, 34)
	forage_btn.text = "✓ Forage — free" if foraging else "Forage — free"
	forage_btn.disabled = foraging
	forage_btn.tooltip_text = "No gold, but −%d stamina and −%d happiness. Hunger is never free." % [
		int(WeekLib.FORAGE_STAMINA_COST), int(WeekLib.FORAGE_HAPPINESS_COST)]
	forage_btn.pressed.connect(func():
		WeekPlan.set_forage(m.id)
		_refresh())
	col.add_child(forage_btn)

	return panel


func _refresh_plan_label(m) -> void:
	var p: Dictionary = WeekPlan.plan_for(m.id)
	var act: String = str(p.get("activity", "rest"))
	if act == "rest":
		plan_label.text = "Booked this week: REST. Stamina recovers; no stat gain."
		plan_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	else:
		var d: Dictionary = WeekLib.drill_by_id(act)
		plan_label.text = "Booked this week: %s. Nothing is spent until you Advance Week." % str(d.get("name", act))
		plan_label.add_theme_color_override("font_color", UiTheme.GOLD)


func _rest_card(m) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	col.add_child(UiTheme.heading("Rest", 3))
	col.add_child(UiTheme.body_text(
		"Recovers stamina. No stat gain. ⚠️ Below 30 stamina every drill pays HALF, so a rest week often earns more than a tired drill.",
		"secondary"))

	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_ALL
	var booked: bool = str(WeekPlan.plan_for(m.id).get("activity", "rest")) == "rest"
	btn.text = "✓ Booked — resting" if booked else "Book a rest week"
	btn.disabled = booked
	btn.pressed.connect(func():
		WeekPlan.set_activity(m.id, "rest")
		_refresh())
	col.add_child(btn)
	return panel


func _drill_card(m, d: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	var drill_id: String = str(d["id"])
	var gains: Dictionary = d.get("gains", {})
	var kind: String = str(d.get("kind", "basic"))
	var cap := _cap()

	col.add_child(UiTheme.heading(str(d["name"]), 3))

	# ⚠️ A DRILL'S PAIRED COST LIVES INSIDE `gains` AS A NEGATIVE, not in a separate `costs` key —
	# `week.gd`'s intensive rows read {"STR": +12, "DEX": -4}. Split them here, or the paired stat
	# renders as "+-4 DEX" and gets a progress bar it should never have.
	var raised: Array = []
	var lowered: Array = []
	for stat in gains.keys():
		if float(gains[stat]) >= 0.0:
			raised.append(stat)
		else:
			lowered.append(stat)

	# The bar for the stat this drill actually raises, read against the LEAGUE CAP — never /100.
	for stat in raised:
		var cur: float = float(m.stats.get(stat, 0.0))
		col.add_child(UiTheme.stat_bar(str(stat), cur, cap, UiTheme.GOLD, 34))

	# What it pays and what it costs — stated before it is booked.
	var costs: Array = []
	for stat in raised:
		costs.append("+%d %s" % [int(round(float(gains[stat]))), stat])
	for stat in lowered:
		costs.append("−%d %s" % [int(round(absf(float(gains[stat])))), stat])
	costs.append("−%d stamina" % int(round(WeekLib.drill_stamina(kind))))
	col.add_child(UiTheme.body_text("  ·  ".join(PackedStringArray(costs)), "secondary"))

	# ⚠️ Aptitude is computed and was invisible in the UI — say why a drill suits THIS monster.
	for stat in raised:
		var bonus: float = WeekLib.stat_training_bonus(m, str(stat))
		if bonus > 1.05:
			var tag := UiTheme.body_text("Natural aptitude for %s — trains ×%.1f faster." % [stat, bonus], "primary")
			tag.add_theme_color_override("font_color", UiTheme.SAFE)
			col.add_child(tag)
		elif bonus < 0.95:
			var tag2 := UiTheme.body_text("Struggles with %s — trains ×%.1f." % [stat, bonus], "primary")
			tag2.add_theme_color_override("font_color", UiTheme.CAUTION)
			col.add_child(tag2)

	# drill_note's cap check must look at the RAISED stats only — a paired penalty stat sitting at
	# the ceiling says nothing about whether this drill is still worth taking.
	var note: Dictionary = WeekPlan.drill_note(m, drill_id, cap)
	var booked: bool = str(WeekPlan.plan_for(m.id).get("activity", "rest")) == drill_id

	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_ALL
	btn.custom_minimum_size = Vector2(0, 36)
	if not bool(note.get("allowed", true)):
		btn.disabled = true
		btn.text = str(note.get("note", "Unavailable"))
	elif booked:
		btn.disabled = true
		btn.text = "✓ Booked for this week"
	else:
		btn.text = "Book this drill"
		btn.pressed.connect(func():
			WeekPlan.set_activity(m.id, drill_id)
			_refresh())
	col.add_child(btn)

	var warn: String = str(note.get("note", ""))
	if warn != "" and bool(note.get("allowed", true)):
		var w := UiTheme.body_text(warn, "primary")
		w.add_theme_color_override("font_color", UiTheme.CAUTION)
		col.add_child(w)

	return panel
