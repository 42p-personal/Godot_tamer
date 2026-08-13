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
	# ⚠️ THE WEEK IS THE PAYOFF BEAT AND IT WAS PACKED LIKE A TABLE. Five rows at SPACE_SM filled
	# barely half the viewport, so the screen read as a dense receipt with an empty half beneath it —
	# `docs/UI_LAYOUT_RULES` treats a half-empty region as a defect for exactly this reason. This is
	# the one screen in the loop whose only job is to be READ, so it gets the register that suits it:
	# fewer, larger, further apart. The Training grid stays dense on purpose; a hub, a ledger and a
	# verdict should not all breathe the same way.
	_list.add_theme_constant_override("separation", UiTheme.SPACE_MD)
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
## ⚠️ ONE RESOLVER, USED BY BOTH THE ARC LINE AND THE PORTRAIT. Split out of `_arc_for` when the
## row gained a portrait: the portrait needs the monster's `species_id`, which only the roster
## instance knows, and resolving it a second way would have re-created exactly the ambiguity the
## refusal below exists to prevent — a row showing one monster's face over another's week.
func _resolve(name: String, id: String = ""):
	if not has_node("/root/Roster"):
		return null
	if id != "":
		for mi in Roster.monsters:
			if str(mi.id) == id:
				return mi
	if name == "":
		return null
	var found = null
	for mi in Roster.monsters:
		if str(mi.species_name) == name:
			if found != null:
				return null   # ambiguous — say nothing rather than guess
			found = mi
	return found


func _arc_for(name: String, id: String = "") -> String:
	var found = _resolve(name, id)
	if found == null:
		return ""
	var info: Dictionary = WeekLib.stage_info(found.age_weeks, found.lifespan_years)
	var span_weeks: int = int(round(float(found.lifespan_years) * float(WeekLib.WEEKS_PER_YEAR)))
	var left: int = maxi(0, span_weeks - int(found.age_weeks))
	return "now %.1f years — %s · %d weeks of career left" % [
		float(found.age_weeks) / float(WeekLib.WEEKS_PER_YEAR), str(info.get("stage", "?")), left]


## ── ONE MONSTER'S WEEK ────────────────────────────────────────────────────────────────────────
##
## ⚠️ THIS IS THE PAYOFF BEAT OF THE WEEK AND IT WAS DRAWN AS A RECEIPT. Five stacked text blocks,
## no faces, every line at the same weight, and the one thing the player pressed Advance Week to
## find out — what each body actually gained — sat as the third line of six inside the paragraph.
## `docs/UI_THEME.md` §4b names this screen among the seven that "name a monster while showing no
## portrait" and it is the one where the monster IS the subject of the row.
##
## The row is now SUBJECT · STORY · OUTCOME across, not six lines down: the face on the left, what
## it did and why in the middle, and the week's result as its own block on the right where the eye
## can run down five of them and compare. Nothing was deleted — the `why:` arithmetic chain, which
## is the earned-knowledge half of the whole loop, is still printed in full.
func _monster_row(m: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	panel.add_child(row)

	# ⚠️ THE PORTRAIT RESOLVES THROUGH `_resolve`, WHICH REFUSES TO GUESS. A row it cannot pin to a
	# body gets the shared placeholder at the SAME footprint (`UiTheme.portrait` degrades to tinted
	# initials), so the ledger never reflows and never shows the wrong creature — the same refusal
	# the arc line has always made, applied to the face.
	var found = _resolve(str(m.get("name", "")), str(m.get("id", "")))
	row.add_child(UiTheme.portrait(
		str(found.species_id) if found != null else "",
		str(m.get("name", "?")), Vector2(88, 88), UiTheme.GOLD))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)

	col.add_child(UiTheme.heading(str(m.get("name", "?")), 3))

	# ⚠️ WHAT IT DID AND WHAT IT ATE, NAMED. This screen used to print bare numbers with no
	# subject — "+13 STR" with no statement of which drill produced it or what the monster was
	# eating when it did. A ledger you cannot attribute teaches nothing, and the stable half only
	# becomes strategy if the player can carry a lesson from this week into the next one.
	var what: String = str(m.get("what", ""))
	var meal: String = str(m.get("meal", ""))
	# ⚠️ "ate unfed" WAS NOT WRONG, IT WAS UNREADABLE — and this screen is the one the player reads
	# to find out whether the week went well. `week_plan.gd` emits three meal values (`unfed`,
	# `foraged`, or a food's name) and the row glued a fixed verb onto all three. The VALUES are
	# untouched; only the verb agrees with them now. This is not the shared life-arc sentence, which
	# is reproduced word for word below.
	if what != "":
		var ate := "ate %s" % meal
		if meal == "unfed":
			ate = "went unfed"
		elif meal == "foraged":
			ate = "foraged"
		col.add_child(UiTheme.body_text("%s · %s" % [what, ate], "secondary"))

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

	# ── the outcome block, right ──────────────────────────────────────────────────────────────
	# ⚠️ THE RESULT GETS ITS OWN COLUMN BECAUSE FIVE RESULTS ARE THE POINT OF THE SCREEN. Stat gains
	# and the two condition deltas were three sentences buried at different depths of three
	# different paragraphs; a player could not answer "which of my five had a good week" without
	# reading all five in full. Aligned right, five weeks stack into a column you read in one pass.
	var out_col := VBoxContainer.new()
	out_col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	out_col.alignment = BoxContainer.ALIGNMENT_CENTER
	out_col.custom_minimum_size = Vector2(300, 0)
	out_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(out_col)

	# ⚠️ THE STRINGS COME FROM THE TICK'S OWN REPORT AND ARE NOT RE-DERIVED HERE. `WeekPlan.advance`
	# emits `stats` already formatted ("+9 STR"); this screen narrates, it never computes — the
	# invariant this file's header pins.
	var stats: Array = m.get("stats", [])
	if stats.is_empty():
		var rested := UiTheme.body_text("Rested — no training", "muted")
		rested.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rested.autowrap_mode = TextServer.AUTOWRAP_OFF
		out_col.add_child(rested)
	else:
		var gains := UiTheme.body_text("  ".join(PackedStringArray(stats)), "primary")
		gains.add_theme_color_override("font_color", UiTheme.GOLD)
		gains.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		gains.autowrap_mode = TextServer.AUTOWRAP_OFF
		out_col.add_child(gains)

	# ⚠️ `delta_chip` RATHER THAN A HAND-WRITTEN "+42 stamina · −1 happiness". The published
	# component already gets the two things this line kept getting wrong: the colour follows
	# MEANING not arithmetic sign (`good_is_up`), and a genuinely unchanged value says "no change"
	# instead of vanishing — a week that resolved and left no trace on screen reads as a bug.
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	chips.alignment = BoxContainer.ALIGNMENT_END
	var stam: float = float(m.get("stamina", 0.0))
	var happy: int = int(m.get("happiness", 0))
	if absf(stam) >= 0.5:
		chips.add_child(UiTheme.delta_chip(stam, "stamina"))
	if happy != 0:
		chips.add_child(UiTheme.delta_chip(float(happy), "heart"))
	if chips.get_child_count() > 0:
		out_col.add_child(chips)

	return panel
