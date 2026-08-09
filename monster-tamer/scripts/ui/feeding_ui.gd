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
	page.add_child(UiTheme.heading("Week %d resolved" % wk, 1))

	var spent: int = int(_report.get("goldSpent", 0))
	var sub := "The stable ate, trained and rested. %s" % (
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
