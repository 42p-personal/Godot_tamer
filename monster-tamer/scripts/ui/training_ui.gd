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
##
## ⚠️ 2026-08-11 — THE ARRANGEMENT WAS THE REMAINING PROBLEM, NOT THE INFORMATION.
## `docs/META_UI_DIRECTION.md` §A2 measured this screen at **6,071px of single-column scroll, 43
## buttons, ~130px per card**: choosing between STR and CHA meant scrolling four screen-heights
## and holding two numbers in your head. Every number on it was already exact and already
## explained — the player simply could not COMPARE two of them. The old React `RanchView`
## condensed the same thirty drills into six columns by stat for precisely this reason and that
## did not survive the port. It is restored here: one column per stat, basic/intensive/extreme
## stacked inside it, the six cross-training drills in their own row underneath.
##
## ⚠️ NOTHING WAS DELETED TO MAKE IT FIT, but one thing was MOVED. The multiplier chain used to
## read as a full sentence per raised stat ("STR: natural aptitude ×1.10 · STR already leads this
## build — focus cost ×0.98"). At ~305px of column width that wraps to three lines and the grid
## stops comparing. The chain is now a terse strip on the card (`×1.10 apt · ×0.98 focus`) with
## the FULL sentence on the card's tooltip — the knowledge is still reachable, and round 14's
## lesson (a preview that hides its multipliers teaches nothing) still holds. If a future round
## finds the terse form is not teaching, put the sentence back and drop to four columns; do not
## delete it.
##
## ⚠️ AND THE CEILING NUMBER CHANGED, DELIBERATELY, BECAUSE THIS SCREEN WAS CONTRADICTING ITSELF.
## Every bar here read against the flat league cap (`400` at Bronze) while `WeekPlan.drill_note` —
## the function that decides whether the BUTTON on the same card is enabled — gates on
## `week.gd:stat_ceiling` (`540`). So the screen refused to admit 140 points of room its own
## buttons would happily let you train into, and the Stable (which reads `stat_ceiling`) printed a
## different denominator for the same stat in the same week. `stat_ceiling` is what the tick
## clamps to, so `stat_ceiling` is what the bars read, and the flat league cap is now stated as
## what it actually is: the rung's number, which promotion moves.
extends Control

const Pace = preload("res://scripts/ui/ending_ui.gd")
const UiTheme = preload("res://scripts/ui/theme.gd")
const WeekLib = preload("res://scripts/week.gd")

## ⚠️ ONE TABLE OF STAT HUES, NOT TWO. `stable_ui.gd:stat_hue()` is a static function reading
## `theme.gd`'s `STAT_HUES` when that token exists and falling back to the values sampled from the
## 141 authored ability icons when it does not. This screen SHARES it rather than keeping a second
## copy — a hand-copied six-entry table on this exact pair of screens is what round 14's
## `INTENSIVE_PAIR` failure was, and a colour table drifts as quietly as a drill table did.
## (`ending_ui.gd` is already preloaded the same way for `Pace`, so the pattern is the house one.)
const StatHue = preload("res://scripts/ui/stable_ui.gd")

var stat_box: VBoxContainer
var header_label: Label
var arc_label: Label
var ladder_label: Label
var pace_label: Label
var plan_label: Label
var food_box: VBoxContainer

## The six stats in the fixed order every screen in this project prints them in. Also the column
## order of the grid — `Classify.STATS` is the same list, but this file must not go blank if the
## autoload is absent in a standalone scene run, so it is spelled out here as a display order only
## (never as a source of game rules).
const STAT_ORDER := ["STR", "DEX", "CON", "WIS", "INT", "CHA"]


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

	## ⚠️ THE LIFE ARC, ON THE SCREEN THAT SPENDS THE WEEKS. `docs/META_UI_DIRECTION.md` §2 slack
	## point 1: the training screen prints what a drill GAINS and never what the week COSTS, and
	## the one currency that is genuinely finite — the monster's remaining career — was on no
	## surface in the game except the ending screen. Monster Rancher's whole drama is that your
	## best monster is dying; `stage_info` has known that all along and no screen asked it.
	arc_label = UiTheme.body_text("", "secondary")
	page.add_child(arc_label)

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

	## ⚠️ FOOD IS PINNED ABOVE THE DRILL SCROLL, NOT STACKED INSIDE IT (§A6). It used to be the
	## first ~170px of the same scroll region as the thirty drills, so the first screenful of the
	## TRAINING screen was the feeding decision and the drills began below the fold — two decisions
	## in one scroll, wrong one first. It is still the first decision of the week (a training food
	## adds +30% to its two stats, so it changes what every drill below is worth); it just no
	## longer costs the drills their real estate.
	food_box = VBoxContainer.new()
	food_box.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	page.add_child(food_box)

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


## ⚠️ THE CEILING THE TICK ACTUALLY CLAMPS TO — the SAME call `stable_ui.gd:_stat_row` and
## `WeekPlan.drill_note` make. See the header note: reading the flat league cap here instead was
## the screen disagreeing with its own Book buttons, and with the Stable, about one stat in one
## week.
func _ceiling(m, stat: String) -> float:
	return WeekLib.stat_ceiling(m, _cap(), stat)


## Weeks of trainable career this body has left — `stage_info`'s span, in the currency the player
## is actually spending. Retirees return 0 rather than a negative.
func _weeks_left(m) -> int:
	var span_weeks: int = int(round(float(m.lifespan_years) * float(WeekLib.WEEKS_PER_YEAR)))
	return maxi(0, span_weeks - int(m.age_weeks))


func _refresh() -> void:
	var m = Roster.selected()
	for c in stat_box.get_children():
		c.queue_free()
	for c in food_box.get_children():
		c.queue_free()
	if m == null:
		header_label.text = "No monster selected — buy one at the Market first."
		arc_label.text = ""
		ladder_label.text = ""
		plan_label.text = ""
		_refresh_pace()   ## the clock does not stop because nothing is selected
		return

	header_label.text = "%s — %s · stamina %d/100 · happiness %d/10" % [
		m.species_name, m.class_name_, int(round(m.stamina)), m.happiness]

	# ── the life arc: what this week is spent OUT OF ──────────────────────────────────────────
	var info: Dictionary = WeekLib.stage_info(m.age_weeks, m.lifespan_years)
	var left: int = _weeks_left(m)
	var stage: String = str(info.get("stage", "?"))
	var tm: float = float(info.get("trainMult", 1.0))
	arc_label.text = "%.1f of %.1f years — %s (training ×%.2f) · %d weeks of career left; this one is one of them." % [
		float(m.age_weeks) / float(WeekLib.WEEKS_PER_YEAR), float(m.lifespan_years), stage, tm, left]
	# Elder and Retiree are the states the player must not discover late. Nothing here is
	# colour-ALONE — the stage word and the week count carry it; the colour only raises the volume.
	if stage == "Retiree" or left <= 0:
		arc_label.add_theme_color_override("font_color", UiTheme.DANGER)
	elif stage == "Elder" or left <= WeekLib.WEEKS_PER_YEAR:
		arc_label.add_theme_color_override("font_color", UiTheme.CAUTION)
	else:
		arc_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)

	# ⚠️ TRAIN *FOR* SOMETHING. The ladder is the spine of the game (CLAUDE.md) and this screen
	# had no idea it existed — a week planned against no target is maintenance by construction.
	# This line names the wall the build is currently sitting against and the one after it.
	var nxt := _league_cap_next()
	var lead_stat := ""
	var lead_val := -1.0
	for stat in STAT_ORDER:
		if float(m.stats.get(stat, 0.0)) > lead_val:
			lead_val = float(m.stats.get(stat, 0.0)); lead_stat = str(stat)
	var lead_ceiling := _ceiling(m, lead_stat)
	# ⚠️ BOTH NUMBERS, NAMED, BECAUSE THEY ARE DIFFERENT THINGS. The league cap is the rung's
	# number and promotion is what moves it; the ceiling is what THIS body may train to out of its
	# own shared budget. Printing only one of them is how the Stable and this screen came to show
	# `115/540` and `115/400` for the same stat in the same week.
	var ladder := "Leading stat %s %d/%d." % [lead_stat, int(round(lead_val)), int(round(lead_ceiling))]
	if lead_ceiling > _cap() + 0.5:
		ladder += "  (%s cap %d, +%d of headroom traded out of its other stats.)" % [
			_league_name(), int(round(_cap())), int(round(lead_ceiling - _cap()))]
	if lead_val >= lead_ceiling - 0.5:
		ladder += "  AT THE CEILING — further %s work is wasted until you win promotion." % lead_stat
	elif nxt > 0.0:
		ladder += "  Next league lifts the cap to %d." % int(round(nxt))
	ladder_label.text = ladder
	_refresh_pace()

	_refresh_plan_label(m)

	# ⚠️ FEEDING IS PART OF THE WEEK'S PLAN, NOT A SEPARATE ERRAND. Without this section gold only
	# ever moved at the Market, so the weekly economy never bit and food was a mechanic on paper.
	# It is pinned above the scroll (see `_build_ui`) rather than stacked on top of the drills.
	_build_food_strip(m)

	# Rest is a real option and must be as easy to pick as a drill — resting is how stamina comes
	# back, and a week spent resting is a genuine strategic choice, not a failure state.
	stat_box.add_child(_rest_card(m))

	# ── SIX COLUMNS, ONE PER STAT (§A2) ───────────────────────────────────────────────────────
	# Bucket every drill by the stat it RAISES MOST. The six cross-training drills raise two stats
	# by the same amount and so belong to neither column — they get their own row underneath,
	# which is also honest about what they are: the option you take when you do not want to pick.
	var by_stat: Dictionary = {}
	for s in STAT_ORDER:
		by_stat[s] = []
	var cross: Array = []
	for d in WeekLib.DRILLS:
		var owner_stat: String = _primary_stat_of(d)
		if owner_stat == "":
			cross.append(d)
		else:
			(by_stat[owner_stat] as Array).append(d)

	var grid := GridContainer.new()
	grid.columns = STAT_ORDER.size()
	grid.add_theme_constant_override("h_separation", UiTheme.SPACE_SM)
	grid.add_theme_constant_override("v_separation", UiTheme.SPACE_SM)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stat_box.add_child(grid)

	for s in STAT_ORDER:
		grid.add_child(_stat_column(m, str(s), by_stat[s]))

	if not cross.is_empty():
		stat_box.add_child(UiTheme.heading("Cross-training — two stats, neither of them fast", 3))
		var cross_grid := GridContainer.new()
		cross_grid.columns = STAT_ORDER.size()
		cross_grid.add_theme_constant_override("h_separation", UiTheme.SPACE_SM)
		cross_grid.add_theme_constant_override("v_separation", UiTheme.SPACE_SM)
		cross_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stat_box.add_child(cross_grid)
		for d in cross:
			# ⚠️ A GridContainer GIVES A CHILD ONLY ITS MINIMUM WIDTH UNLESS THE CHILD ASKS TO
			# EXPAND. The stat columns above set this on the column; these cards are added to the
			# grid directly, and without it the first build rendered all six at ~55px — one word
			# per line, a wall of vertical text. Caught in the capture, not by the probe: the
			# content height was fine and every rule passed.
			var card := _drill_card(m, d)
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cross_grid.add_child(card)


## Which stat a drill BELONGS to — the one it raises most. "" when two stats tie for the top,
## which is exactly the six `diverse` drills and no others.
## ⚠️ READ FROM `gains`, NEVER FROM A LOCAL TABLE. `stable_ui.gd` used to carry a hand-copied
## six-entry drill table "kept in sync" with `week.gd:DRILLS` and it had silently drifted in three
## separate ways (see that file's header). This asks the shipped table.
func _primary_stat_of(d: Dictionary) -> String:
	var gains: Dictionary = d.get("gains", {})
	var best := ""
	var best_v := 0.0
	var tied := false
	for stat in gains.keys():
		var v: float = float(gains[stat])
		if v <= 0.0:
			continue
		if v > best_v + 0.001:
			best_v = v; best = str(stat); tied = false
		elif absf(v - best_v) <= 0.001:
			tied = true
	return "" if tied else best


## One stat's column: where the stat stands against the ceiling the tick clamps to, then every
## drill that leads with it, cheapest first.
func _stat_column(m, stat: String, drills: Array) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_FILL

	# ⚠️ SIX COLUMNS THAT LOOKED LIKE ONE COLUMN SIX TIMES. Round 20's fix was the right one — the
	# grid is what made STR and CHA comparable at all — but every column then opened with a GOLD bar
	# and a grey tag, so the eye had nothing to land on and the only way to know which column you
	# were in was to read its three-letter label. The rule and the bar now carry the stat's own hue
	# (`docs/POLISH_DIRECTION.md` §3.1, sampled from the ability icons), so a column has an identity
	# at a glance and the Stable's stat bars agree with it in the same six colours.
	var hue: Color = StatHue.stat_hue(stat)
	var rule := ColorRect.new()
	rule.color = hue
	rule.custom_minimum_size = Vector2(0, 4)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(rule)

	var cur: float = float(m.stats.get(stat, 0.0))
	var ceiling: float = _ceiling(m, stat)
	col.add_child(UiTheme.stat_bar(stat, cur, maxf(ceiling, cur), hue, 34))

	var apt: float = WeekLib.stat_training_bonus(m, stat)
	var tag := "even going"
	if apt > 1.05:
		tag = "natural ×%.2f" % apt
	elif apt < 0.95:
		tag = "against the grain ×%.2f" % apt
	var tag_lbl := UiTheme.body_text(tag, "muted")
	tag_lbl.add_theme_color_override("font_color",
		UiTheme.SAFE if apt > 1.05 else (UiTheme.CAUTION if apt < 0.95 else UiTheme.TEXT_MUTED))
	col.add_child(tag_lbl)

	for d in drills:
		col.add_child(_drill_card(m, d))
	return col


## The week's food, as ONE pinned strip. Paid food costs gold; forage is free but costs stamina
## AND happiness — hunger is never free, it is only ever paid differently
## (`docs/CORE_LOOP_PORT.md` §3).
##
## ⚠️ THE TASTE IS ON THE BUTTON NOW, NOT ONLY IN THE TOOLTIP. Every monster has a `favourite_food`
## and a `hated_food` and `docs/META_UI_DIRECTION.md` §2 slack point 2 found that **no screen in
## the game showed either**, so the one thing that makes feeding a per-monster decision rather
## than a bulk errand was invisible — which is why the capture showed all five monsters `ate
## unfed`. `week.gd:food_happiness_delta` is the source; nothing here re-derives a taste rule.
func _build_food_strip(m) -> void:
	var plan: Dictionary = WeekPlan.plan_for(m.id)
	var chosen: String = str(plan.get("food", ""))
	var foraging: bool = bool(plan.get("forage", false))
	var gold: int = Career.gold if has_node("/root/Career") else 0

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	food_box.add_child(head)
	head.add_child(UiTheme.heading("This week's food", 3))

	var fav_name: String = str(WeekLib.food_by_id(str(m.favourite_food)).get("name", ""))
	var hate_name: String = str(WeekLib.food_by_id(str(m.hated_food)).get("name", ""))
	var taste := ""
	if fav_name != "" and hate_name != "":
		taste = "loves %s · hates %s" % [fav_name, hate_name]
	elif fav_name != "":
		taste = "loves %s" % fav_name
	elif hate_name != "":
		taste = "hates %s" % hate_name
	# ⚠️ NEITHER OF THESE MAY AUTOWRAP INSIDE THE HBOX. `UiTheme.body_text` turns wrapping ON by
	# default, and an HBox hands a wrapping label whatever width is left after its siblings — which
	# on the first build of this strip was about ten pixels, so the hunger warning rendered as a
	# column of single letters down the right edge and forced the whole row ~90px tall. A label on
	# one line of a header row must be told it is one line.
	if taste != "":
		var tl := UiTheme.body_text(taste, "secondary")
		tl.autowrap_mode = TextServer.AUTOWRAP_OFF
		head.add_child(tl)
	if chosen == "" and not foraging:
		var warn := UiTheme.body_text("— nothing chosen, it will go hungry and lose heart", "muted")
		warn.autowrap_mode = TextServer.AUTOWRAP_OFF
		warn.add_theme_color_override("font_color", UiTheme.CAUTION)
		head.add_child(warn)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)

	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", UiTheme.SPACE_XS)
	grid.add_theme_constant_override("v_separation", UiTheme.SPACE_XS)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	food_box.add_child(grid)

	for f in WeekLib.FOODS:
		var fid: String = str(f["id"])
		var price: int = WeekPlan.price_of(fid)
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_ALL
		btn.custom_minimum_size = Vector2(0, 30)
		btn.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
		var boost: Array = f.get("boostStats", [])
		# ⚠️ A monster's FAVOURITE and HATED foods differ per monster — that is exactly why feeding
		# cannot be one bulk button (town.ts:advanceWeek feeds per-monster for this reason).
		var delta: int = WeekLib.food_happiness_delta(m, fid)
		var taste_mark := ""
		if delta > 0:
			taste_mark = "♥ "
		elif delta < 0:
			taste_mark = "✗ "
		var label := "%s%s %dg" % [taste_mark, str(f["name"]), price]
		if not boost.is_empty():
			label += " +30%% %s" % "/".join(PackedStringArray(boost))
		if fid == chosen:
			btn.text = "✓ " + label
			btn.disabled = true
			btn.tooltip_text = "Booked for this week."
		elif price > gold:
			btn.text = label
			btn.disabled = true
			# rule 3 — a dead control says why, in the label as well as the tooltip.
			btn.text = label + " — can't afford"
			btn.tooltip_text = "Costs %dg; you have %dg." % [price, gold]
		else:
			btn.text = label
			btn.pressed.connect(func():
				WeekPlan.set_food(m.id, fid)
				_refresh())
		if delta > 0:
			btn.tooltip_text = "Favourite — happiness +%d, and happier monsters roll higher gains." % delta
		elif delta < 0:
			btn.tooltip_text = "Hates this — happiness %d." % delta
		grid.add_child(btn)

	var forage_btn := Button.new()
	forage_btn.focus_mode = Control.FOCUS_ALL
	forage_btn.custom_minimum_size = Vector2(0, 30)
	forage_btn.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	forage_btn.text = "✓ Forage — free" if foraging else "Forage — free"
	forage_btn.disabled = foraging
	forage_btn.tooltip_text = "No gold, but −%d stamina and −%d happiness. Hunger is never free." % [
		int(WeekLib.FORAGE_STAMINA_COST), int(WeekLib.FORAGE_HAPPINESS_COST)]
	forage_btn.pressed.connect(func():
		WeekPlan.set_forage(m.id)
		_refresh())
	grid.add_child(forage_btn)


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
		"Recovers stamina. No stat gain. ⚠ Below 30 stamina every drill pays HALF, so a rest week often earns more than a tired drill.",
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
	# ⚠️ THIS WAS THE PROJECT'S ONE SILENT DEAD CONTROL, AND ONLY THE LOSING FIXTURE SHOWED IT.
	# `_probe_screens.gd` reported `B_thin/04_training` as **1 disabled button with no reason** while
	# `A_comfortable` reported zero — because the comfortable career has a drill booked, so the rest
	# button is live there and nobody ever saw it dead. `UI_LAYOUT_RULES` R3 is not satisfied by a
	# checkmark: it needs a stated reason. The rest of this screen already does it right (every
	# unaffordable food says "— can't afford"); the rest card was the exception.
	if booked:
		UiTheme.disable_with_reason(btn,
			"Already booked — this monster is resting this week. Pick a drill to change it.")
		# The card takes the same settled treatment a booked drill gets, so "what did I choose" has
		# one answer shape everywhere on the screen.
		panel.add_theme_stylebox_override("panel", UiTheme.panel_style("raised", UiTheme.SAFE))
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

	# ⚠️ THE NAME AND THE NUMBER WERE ONE STRING IN ONE INK, AND THE NUMBER IS THE DECISION.
	# `docs/POLISH_DIRECTION.md` §1.2 measured GOLD against CAUTION at **1.023:1** — two published
	# tokens that are the same colour — so a card's title and its footnote carried identical
	# emphasis, and `→ +9 net`, the one figure the player is actually choosing on, was buried inside
	# the gold title line with the drill's name. Splitting them into a row puts every net gain on the
	# same right-hand edge down all six columns: the comparison the grid exists for now happens
	# without reading a single word.
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	var title := UiTheme.body_text(str(d["name"]), "primary")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var net_lbl := UiTheme.body_text("%+d net" % int(round(net)), "primary")
	net_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	net_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# GOLD is the ink of the thing being bought; CAUTION marks a week that buys nothing. Both are
	# published tokens, and this is the one line on the card where the distinction is load-bearing.
	net_lbl.add_theme_color_override("font_color", UiTheme.GOLD if net > 0.0 else UiTheme.CAUTION)
	title_row.add_child(net_lbl)
	col.add_child(title_row)

	var live := _delta_text(deltas)
	# ⚠️ THE WEEK'S REAL COST IS NOT STAMINA (§A5). Stamina comes back — `week.gd:stamina_malus`
	# floors at 0.5 and never blocks a drill — but a week off this monster's career never does.
	# `docs/META_UI_DIRECTION.md` §2 slack point 1: the screen printed everything a drill GAINS and
	# nothing it SPENT, so "training and breeding are strategy, not maintenance" had no price to
	# reason about. One drill = one of the weeks counted here.
	var left: int = _weeks_left(m)
	var live_lbl := UiTheme.body_text(
		("%s  ·  −%d stam  ·  1 of %d wks left" % [live, int(round(WeekLib.drill_stamina(kind))), left]) if live != ""
		else "no movement — −%d stam and one of %d weeks, for nothing" % [
			int(round(WeekLib.drill_stamina(kind))), left],
		"secondary")
	col.add_child(live_lbl)

	# The face value stays on the card, quietly, so the player can SEE the gap between what the
	# drill is written to do and what it does for THIS monster THIS week. That gap is the lesson.
	var face: Array = []
	for stat in raised:
		face.append("+%d %s" % [int(round(float(gains[stat]))), stat])
	for stat in lowered:
		face.append("−%d %s" % [int(round(absf(float(gains[stat])))), stat])
	var face_lbl := UiTheme.body_text("on paper %s" % " ".join(PackedStringArray(face)), "muted")
	col.add_child(face_lbl)

	# ⚠️ WHY the live number differs from the face value. TERSE ON THE CARD, FULL IN THE TOOLTIP —
	# see the header note. Without this in some form the preview is a magic number and the player
	# learns nothing they can carry to the next monster, and "knowledge the player has earned" is
	# the entire design bar for this screen.
	var short_bits: Array = []
	var long_bits: Array = []
	var any_penalty := false
	var any_bonus := false
	for stat in raised:
		var bonus: float = WeekLib.stat_training_bonus(m, str(stat))
		if bonus > 1.05:
			short_bits.append("×%.2f apt" % bonus); any_bonus = true
			long_bits.append("%s: natural aptitude ×%.2f" % [stat, bonus])
		elif bonus < 0.95:
			short_bits.append("×%.2f apt" % bonus); any_penalty = true
			long_bits.append("%s: trains against the grain ×%.2f" % [stat, bonus])
		var focus: float = WeekLib.focus_cost(m, str(stat))
		if focus < 0.995:
			short_bits.append("×%.2f focus" % focus); any_penalty = true
			long_bits.append("%s already leads this build — focus cost ×%.2f" % [stat, focus])
		var fmult: float = WeekLib.food_train_mult(str(WeekPlan.plan_for(m.id).get("food", "")), str(stat))
		if fmult > 1.0:
			short_bits.append("×%.2f food" % fmult); any_bonus = true
			long_bits.append("this week's food ×%.2f on %s" % [fmult, stat])
		# ⚠️ AGAINST `stat_ceiling`, NOT THE FLAT CAP — the same number the Book button gates on.
		if float(m.stats.get(stat, 0.0)) >= _ceiling(m, str(stat)) - 0.5:
			short_bits.append("%s AT ceiling" % stat); any_penalty = true
			long_bits.append("%s is at this body's ceiling — promotion or a better bloodline moves it" % stat)
	if not short_bits.is_empty():
		var r := UiTheme.body_text("  ·  ".join(PackedStringArray(short_bits)), "muted")
		r.add_theme_color_override("font_color",
			UiTheme.CAUTION if any_penalty else (UiTheme.SAFE if any_bonus else UiTheme.TEXT_MUTED))
		col.add_child(r)
	if not long_bits.is_empty():
		panel.tooltip_text = "\n".join(PackedStringArray(long_bits))

	# drill_note's cap check must look at the RAISED stats only — a paired penalty stat sitting at
	# the ceiling says nothing about whether this drill is still worth taking.
	var note: Dictionary = WeekPlan.drill_note(m, drill_id, cap)
	var booked: bool = str(WeekPlan.plan_for(m.id).get("activity", "rest")) == drill_id

	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_ALL
	btn.custom_minimum_size = Vector2(0, 30)
	btn.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	if not bool(note.get("allowed", true)):
		btn.disabled = true
		# ⚠️ RULE 3 — a dead control must say WHY, and at column width the full sentence will not
		# fit on the button face. It goes on the tooltip AND stays legible on the button as a short
		# form; never a bare greyed "Book".
		btn.text = "At the ceiling"
		btn.tooltip_text = str(note.get("note", "Unavailable"))
	elif booked:
		btn.disabled = true
		btn.text = "✓ Booked"
		btn.tooltip_text = "This is the week's plan. Advance Week at the Stable to spend it."
		# ⚠️ A SETTLED DECISION SHOULD LOOK SETTLED FROM ACROSS SIX COLUMNS. `✓ Booked` differed from
		# `Book` by 1.10:1 of button fill plus a checkmark — below any glance threshold, so the
		# player's own committed week was the hardest card on the screen to find. The CARD is what
		# changes state now, not just the control inside it: raised fill, and the column's hue as its
		# border. Elevation is information, and this is the one card on the screen that is a decision
		# already made.
		panel.add_theme_stylebox_override("panel",
			UiTheme.panel_style("raised", StatHue.stat_hue(_primary_stat_of(d))))
	else:
		btn.text = "Book"
		btn.pressed.connect(func():
			WeekPlan.set_activity(m.id, drill_id)
			_refresh())
	col.add_child(btn)

	var warn: String = str(note.get("note", ""))
	if warn != "" and bool(note.get("allowed", true)):
		var w := UiTheme.body_text(warn, "muted")
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
