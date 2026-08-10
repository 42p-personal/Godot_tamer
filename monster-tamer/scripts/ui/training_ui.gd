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
##
## ⚠️ 2026-08-09 — THIS SCREEN WAS SHOWING THE WRONG NUMBERS, AND THAT WAS THE REAL REASON THE
## WEEK WAS NOT A DECISION. Every card printed the drill's AUTHORED face value ("+12 STR · −4
## DEX"), which is the one number the tick never uses. Species aptitude (×0.8–×1.2), life stage
## (×0.5 Baby / ×1.35 Teen / ×1.15 grown / ×0.8 Elder), the stamina bracket (down to ×0.5), the
## happiness-weighted roll, the training food's boost and the league-cap clamp were ALL invisible
## — so two cards that read identically could be worth 8 and 21. CLAUDE.md is explicit that the
## Ranch shows a LIVE roll (`previewWeekEffects`) precisely because it is exact; that behaviour
## did not survive the port and this restores it.
##
## ⚠️ AND IT IS DRAWN FROM `week.gd:preview_week`, WHICH RUNS THE REAL TICK ON A CLONE. Not a
## second estimate. There is deliberately no arithmetic in this file that could drift from the
## tick — the number on the button IS the number that will land.
extends Control

const Pace = preload("res://scripts/ui/ending_ui.gd")
const UiTheme = preload("res://scripts/ui/theme.gd")
const WeekLib = preload("res://scripts/week.gd")

var stat_box: VBoxContainer
var header_label: Label
var ladder_label: Label
var pace_label: Label
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

	# The ladder line — what the climb is about to ask of this monster. See `_refresh`.
	ladder_label = UiTheme.body_text("", "secondary")
	ladder_label.add_theme_color_override("font_color", UiTheme.GOLD)
	page.add_child(ladder_label)

	## ⚠️ THE CLOCK, ON THE SCREEN WHERE THE WEEKS ARE SPENT. Round 17's whole thesis is that
	## PACE is the score (docs/CONVERSION_DIAGNOSIS.md — completion is a saturated boolean and
	## only weeks can respond to skill), and a score the player only meets on the win screen is
	## decoration. Training is where a week is committed, so it is where the cost of a week has to
	## be legible. Read live from `Career` through the ONE adapter (`ui/ending_ui.gd`); never
	## re-derive a par curve here — two definitions of par is this project's signature failure.
	pace_label = UiTheme.body_text("", "secondary")
	page.add_child(pace_label)

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


func _league_cap_next() -> float:
	if not has_node("/root/Career"):
		return 0.0
	var nxt: int = Career.league_index + 1
	if nxt >= Career.leagues.size():
		return 0.0
	return Career.stat_cap_for_league(nxt)


## The LIVE result of booking `action` for `m` this week, food included — straight off the tick.
## ⚠️ Feeding resolves BEFORE the activity, so the booked food's happiness/stamina swing is
## already folded into the roll this returns. That is the whole reason food and drill have to be
## chosen together rather than as two errands.
func _preview(m, action: Dictionary) -> Dictionary:
	var p: Dictionary = WeekPlan.plan_for(m.id)
	var food: String = str(p.get("food", ""))
	var forage: bool = bool(p.get("forage", false))
	var gold: int = Career.gold if has_node("/root/Career") else 0
	var league: String = _league_name()
	return WeekLib.preview_week(m, action, gold, 0, food, forage, WeekPlan.price_of(food),
		_cap(), league)


## "+18 STR  ·  −5 DEX" from a preview's statDeltas, in a stable stat order.
func _delta_text(deltas: Dictionary) -> String:
	var bits: Array = []
	for stat in ["STR", "DEX", "CON", "WIS", "INT", "CHA"]:
		var d: float = float(deltas.get(stat, 0.0))
		if absf(d) >= 0.5:
			bits.append("%+d %s" % [int(round(d)), stat])
	return "  ·  ".join(PackedStringArray(bits))


func _net_of(deltas: Dictionary) -> float:
	var n := 0.0
	for stat in deltas:
		n += float(deltas[stat])
	return n


func _league_name() -> String:
	return Career.current_league_name() if has_node("/root/Career") else "current league"


func _refresh() -> void:
	var m = Roster.selected()
	for c in stat_box.get_children():
		c.queue_free()
	if m == null:
		header_label.text = "No monster selected — buy one at the Market first."
		ladder_label.text = ""
		plan_label.text = ""
		_refresh_pace()   ## the clock does not stop because nothing is selected
		return

	header_label.text = "%s — %s · stamina %d/100 · happiness %d/10 · %s ceiling %d" % [
		m.species_name, m.class_name_, int(round(m.stamina)), m.happiness,
		_league_name(), int(round(_cap()))]

	# ⚠️ TRAIN *FOR* SOMETHING. The ladder is the spine of the game (CLAUDE.md) and this screen
	# had no idea it existed — a week planned against no target is maintenance by construction.
	# This line names the wall the build is currently sitting against and the one after it.
	var nxt := _league_cap_next()
	var lead_stat := ""
	var lead_val := -1.0
	for stat in ["STR", "DEX", "CON", "WIS", "INT", "CHA"]:
		if float(m.stats.get(stat, 0.0)) > lead_val:
			lead_val = float(m.stats.get(stat, 0.0)); lead_stat = str(stat)
	var ladder := "Leading stat %s %d/%d." % [lead_stat, int(round(lead_val)), int(round(_cap()))]
	if lead_val >= _cap() - 0.5:
		ladder += "  AT THE CEILING — further %s work is wasted until you win promotion." % lead_stat
	elif nxt > 0.0:
		ladder += "  Next league lifts the ceiling to %d." % int(round(nxt))
	ladder_label.text = ladder
	_refresh_pace()

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
	var food: String = str(p.get("food", ""))
	var meal := "nothing booked — it will go hungry"
	if bool(p.get("forage", false)):
		meal = "foraging"
	elif food != "":
		meal = "%s (%dg)" % [str(WeekLib.food_by_id(food).get("name", food)), WeekPlan.price_of(food)]
	if act == "rest":
		plan_label.text = "Booked: REST, eating %s. Stamina recovers; no stat gain." % meal
		plan_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	else:
		var d: Dictionary = WeekLib.drill_by_id(act)
		plan_label.text = "Booked: %s, eating %s. Nothing is spent until you Advance Week." % [
			str(d.get("name", act)), meal]
		plan_label.add_theme_color_override("font_color", UiTheme.GOLD)


func _rest_card(m) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	var pv: Dictionary = _preview(m, {"kind": "rest"})
	col.add_child(UiTheme.heading("Rest   → %+d stamina" % int(round(float(pv.get("staminaDelta", 0.0)))), 3))
	col.add_child(UiTheme.body_text(
		"Recovers stamina. No stat gain. ⚠️ Below 30 stamina every drill pays HALF, so a rest week often earns more than a tired drill.",
		"secondary"))
	# Rest is the ONLY thing that mends a monster between cups — say so with the actual numbers,
	# because "rest or train" is the one weekly choice the player will face every single week.
	var mend: Array = []
	if absf(float(pv.get("hpDelta", 0.0))) >= 0.5:
		mend.append("%+d HP" % int(round(float(pv["hpDelta"]))))
	if absf(float(pv.get("mpDelta", 0.0))) >= 0.5:
		mend.append("%+d MP" % int(round(float(pv["mpDelta"]))))
	if not mend.is_empty():
		var ml := UiTheme.body_text("  ·  ".join(PackedStringArray(mend)), "primary")
		ml.add_theme_color_override("font_color", UiTheme.SAFE)
		col.add_child(ml)

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

	# ⚠️ THE LIVE ROLL, not the face value. See the header — this is the restored behaviour.
	var pv: Dictionary = _preview(m, {"kind": "train", "drillId": drill_id})
	var deltas: Dictionary = pv.get("statDeltas", {})
	var net := _net_of(deltas)

	var title := UiTheme.heading("%s   → %+d net" % [str(d["name"]), int(round(net))], 3)
	col.add_child(title)

	# The bar for the stat this drill actually raises, read against the LEAGUE CAP — never /100.
	for stat in raised:
		var cur: float = float(m.stats.get(stat, 0.0))
		col.add_child(UiTheme.stat_bar(str(stat), cur, cap, UiTheme.GOLD, 34))

	var live := _delta_text(deltas)
	var live_lbl := UiTheme.body_text(
		("%s  ·  −%d stamina" % [live, int(round(WeekLib.drill_stamina(kind)))]) if live != ""
		else "No movement this week — −%d stamina for nothing." % int(round(WeekLib.drill_stamina(kind))),
		"primary")
	live_lbl.add_theme_color_override("font_color", UiTheme.GOLD if net > 0.0 else UiTheme.CAUTION)
	col.add_child(live_lbl)

	# The face value stays on the card, quietly, so the player can SEE the gap between what the
	# drill is written to do and what it does for THIS monster THIS week. That gap is the lesson.
	var face: Array = []
	for stat in raised:
		face.append("+%d %s" % [int(round(float(gains[stat]))), stat])
	for stat in lowered:
		face.append("−%d %s" % [int(round(absf(float(gains[stat])))), stat])
	col.add_child(UiTheme.body_text("on paper: %s" % "  ".join(PackedStringArray(face)), "muted"))

	# ⚠️ WHY the live number differs from the face value. Without this the preview is a magic
	# number and the player learns nothing they can carry to the next monster — and "knowledge the
	# player has earned" is the entire design bar for this screen.
	for stat in raised:
		var reasons: Array = []
		var bonus: float = WeekLib.stat_training_bonus(m, str(stat))
		if bonus > 1.05:
			reasons.append("natural aptitude ×%.2f" % bonus)
		elif bonus < 0.95:
			reasons.append("trains against the grain ×%.2f" % bonus)
		var focus: float = WeekLib.focus_cost(m, str(stat))
		if focus < 0.995:
			reasons.append("%s already leads this build — focus cost ×%.2f" % [stat, focus])
		var fmult: float = WeekLib.food_train_mult(str(WeekPlan.plan_for(m.id).get("food", "")), str(stat))
		if fmult > 1.0:
			reasons.append("this week's food ×%.2f" % fmult)
		if float(m.stats.get(stat, 0.0)) >= cap - 0.5:
			reasons.append("%s is AT the %s ceiling" % [stat, _league_name()])
		if not reasons.is_empty():
			var r := UiTheme.body_text("%s: %s" % [stat, "  ·  ".join(PackedStringArray(reasons))], "secondary")
			r.add_theme_color_override("font_color",
				UiTheme.SAFE if bonus > 1.05 and focus > 0.995 else UiTheme.CAUTION)
			col.add_child(r)

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


## The pace line. `Pace.snapshot()` is empty when the career model is absent, and an ABSENT clock
## must draw NOTHING rather than a reassuring guess — a screen that invents a standing is round
## 13's scoreboard that announced the winner at frame 0.
func _refresh_pace() -> void:
	if pace_label == null:
		return
	var snap: Dictionary = Pace.snapshot()
	if snap.is_empty():
		pace_label.text = ""
		pace_label.visible = false
		return
	pace_label.visible = true
	pace_label.text = Pace.pace_line(snap)
	pace_label.add_theme_color_override("font_color", Pace.pace_color(snap))
