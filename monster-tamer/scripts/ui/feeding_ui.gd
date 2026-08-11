## FEEDING — the week resolving, one monster at a time.
##
## ⚠️ SEQUENTIAL BY NECESSITY, NOT BY STYLE. `town.ts:advanceWeek()` feeds per-monster because
## favourite and hated foods DIFFER per monster, so a single bulk-feed button cannot express the
## decision. This screen is that phase: you see each monster's week land, and you see what it cost.
##
## Reached from the Stable's Advance Week. `WeekPlan.advance()` has already run by the time this
## screen builds — this narrates the result rather than computing it, so the numbers here can
## never disagree with the tick.
extends Control

const UiTheme = preload("res://scripts/ui/theme.gd")
const WeekLib = preload("res://scripts/week.gd")

var _report: Dictionary = {}
var _list: VBoxContainer


func _ready() -> void:
	self.theme = UiTheme.base_theme()
	if has_node("/root/WeekPlan") and WeekPlan.has_meta("last_report"):
		_report = WeekPlan.get_meta("last_report")
	_build()


func _build() -> void:
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

	var wk: int = int(_report.get("week", 0))
	# ⚠️ THE SCREEN IS CALLED "FEEDING" IN THE SCENE TREE AND IT FEEDS NOBODY — that name is a
	# fossil of `town.ts`'s sequential feeding phase; food is chosen a week earlier on the Training
	# screen (docs/META_UI_DIRECTION.md §A7). The heading says what the screen IS: the week's
	# ledger. The FILE and scene keep their names deliberately — renaming them touches
	# `stable_ui.gd`'s scene change, `save_game.gd` and the probe's screen table, none of which are
	# this stream's to move. Flagged for the integrator rather than done here.
	page.add_child(UiTheme.heading("The Week — %d resolved" % wk, 1))

	var spent: int = int(_report.get("goldSpent", 0))
	var sub := "The stable ate, trained, rested — and aged one week. %s" % (
		"Nothing was spent." if spent <= 0 else "%d gold went on food and upkeep." % spent)
	page.add_child(UiTheme.body_text(sub, "secondary"))
	page.add_child(HSeparator.new())

	# ── the per-monster ledger: scrolls, per docs/UI_LAYOUT_RULES.md rule 1 ──────────────────────
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	var monsters: Array = _report.get("monsters", [])
	if monsters.is_empty():
		_list.add_child(UiTheme.body_text(
			"No monsters in the stable — nothing to feed. Buy one at the Market.", "muted"))
	for m in monsters:
		_list.add_child(_monster_row(m))

	# ── sticky rail — the primary action never scrolls away (rule 2) ─────────────────────────────
	page.add_child(HSeparator.new())
	var back := Button.new()
	back.text = "Back to the Stable"
	back.custom_minimum_size = Vector2(0, 44)
	back.focus_mode = Control.FOCUS_ALL
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/stable.tscn"))
	page.add_child(back)
	back.grab_focus()


## Where this monster now sits on its life arc, or "" if it cannot be identified with certainty.
##
## ⚠️ THE REPORT ROW IS KEYED BY SPECIES NAME AND THAT IS NOT AN IDENTITY. `WeekPlan.advance()`
## emits `{"name": mi.species_name, ...}`, so two monsters of the same species collapse onto one
## key — the exact hazard `docs/UX_LEGIBILITY.md` §2 already flagged against `report_ui.gd`. This
## function REFUSES rather than guesses: if the name is ambiguous it returns "" and the row simply
## carries no arc line. A ledger that attributes one monster's ageing to another would be
## precisely the class of failure this project's rule (1) exists to stop, and no arc line is a
## much cheaper wrong than the wrong arc line.
##
## The real fix is upstream — `advance()` should carry `mi.id` — but `week_plan.gd` is not this
## stream's file. Flagged for the integrator.
## ⚠️ RESOLVES BY SLOT ID FIRST. This matched on species name only until round 18, and had to
## return "" whenever two monsters shared a species — silently dropping the life-arc line rather
## than risk attributing one monster's ageing to another. `week_plan.gd:advance()` now emits `id`
## on every report row, so the exact match is available; the name path stays as the fallback for a
## row written by an older build (or a save mid-migration) and keeps its refusal.
func _arc_for(name: String, id: String = "") -> String:
	if not has_node("/root/Roster"):
		return ""
	var found = null
	if id != "":
		for mi in Roster.monsters:
			if str(mi.id) == id:
				found = mi
				break
	if found == null:
		if name == "":
			return ""
		for mi in Roster.monsters:
			if str(mi.species_name) == name:
				if found != null:
					return ""   # ambiguous — say nothing rather than guess
				found = mi
	if found == null:
		return ""
	var info: Dictionary = WeekLib.stage_info(found.age_weeks, found.lifespan_years)
	var span_weeks: int = int(round(float(found.lifespan_years) * float(WeekLib.WEEKS_PER_YEAR)))
	var left: int = maxi(0, span_weeks - int(found.age_weeks))
	return "now %.1f years — %s · %d weeks of career left" % [
		float(found.age_weeks) / float(WeekLib.WEEKS_PER_YEAR), str(info.get("stage", "?")), left]


func _monster_row(m: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	col.add_child(UiTheme.heading(str(m.get("name", "?")), 3))

	# ⚠️ WHAT IT DID AND WHAT IT ATE, NAMED. This screen used to print bare numbers with no
	# subject — "+13 STR" with no statement of which drill produced it or what the monster was
	# eating when it did. A ledger you cannot attribute teaches nothing, and the stable half only
	# becomes strategy if the player can carry a lesson from this week into the next one.
	var what: String = str(m.get("what", ""))
	var meal: String = str(m.get("meal", ""))
	if what != "":
		col.add_child(UiTheme.body_text("%s · ate %s" % [what, meal], "secondary"))

	var stats: Array = m.get("stats", [])
	if stats.is_empty():
		col.add_child(UiTheme.body_text("Rested — no training this week.", "muted"))
	else:
		var gains := UiTheme.body_text("  ".join(PackedStringArray(stats)), "primary")
		gains.add_theme_color_override("font_color", UiTheme.GOLD)
		col.add_child(gains)

	# ⚠️ AND WHY. Every term the tick multiplied by, in the order it applied them — life stage,
	# stamina bracket, happiness skew, species aptitude, focus cost, food boost. This is the EARNED
	# KNOWLEDGE half of the loop: the player is not told a rule, they are shown the arithmetic of
	# their own week and left to draw the rule out of it.
	var why: Array = m.get("why", [])
	if not why.is_empty():
		var w := UiTheme.body_text("why: %s" % "  ·  ".join(PackedStringArray(why)), "muted")
		col.add_child(w)

	# ⚠️ THE WEEK COST A WEEK OF ITS LIFE, AND THE LEDGER NEVER SAID SO. `docs/META_UI_DIRECTION.md`
	# §2 slack point 1: the ledger accounts for stats, stamina, happiness and gold — every currency
	# except the only finite one. This adds the arc position AFTER the tick, so the week a monster
	# crosses into Elder or Retiree is announced on the screen that reports the week it happened in.
	var arc: String = _arc_for(str(m.get("name", "")), str(m.get("id", "")))
	if arc != "":
		col.add_child(UiTheme.body_text(arc, "secondary"))

	var stam: float = float(m.get("stamina", 0.0))
	var happy: int = int(m.get("happiness", 0))
	var bits: Array = []
	if absf(stam) >= 0.5:
		bits.append("%+d stamina" % int(round(stam)))
	if happy != 0:
		bits.append("%+d happiness" % happy)
	if not bits.is_empty():
		col.add_child(UiTheme.body_text("  ·  ".join(PackedStringArray(bits)), "secondary"))

	return panel
