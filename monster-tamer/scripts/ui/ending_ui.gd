## THE ENDING — the screen this project has never had.
##
## ⚠️ THE STARTING POSITION, VERIFIED BEFORE A LINE OF THIS WAS WRITTEN.
## `grep -rn "won_game\|gameWon" scripts/ui/` returned exactly ONE hit before this file existed
## (`tournament_ui.gd:423`, a two-line heading inside the cup result panel). `CLAUDE.md`'s ship
## target — *"Winning is completing Tamers Apex"* — ended by setting a bool at `career.gd:1220`
## that no screen read, persisted as `"wonGame"` at `save_game.gd:129`, and displayed nowhere.
##
## ── WHAT THIS SCREEN IS FOR (round 17, docs/CONVERSION_DIAGNOSIS.md §5 R17-1) ────────────────
## Round 16 measured a fight advantage compounding 1.09x → 4.03x across five hops and then dying
## against `Career.won_game`, a boolean already 88-94% true for a player with no advantage at all.
## The advantage does not leak; the OUTCOME SPACE has no room for it. The response is not to make
## the game harder (§2d: only ~6 points of headroom exist above the competent player, so any
## mechanism producing more separation must produce it by deleting the naive player). The response
## is to SCORE THE THING THAT ALREADY DIFFERS: pace. Median 354 weeks for a competent career
## against 502 for a naive one, n=16, paired p=0.0005 — a 148-week difference the game never
## mentioned.
##
## ⚠️ AND THE HONEST RISK, WHICH IS WHY THIS FILE ALSO OWNS `snapshot()`. A grade revealed after
## 400 weeks changes no decision anybody made. A scoreboard is not a stake unless the clock is
## FELT during the climb. So the pace model lives here as static functions and is read by
## `town_ui.gd` (every hub visit) and `report_ui.gd` (every fight) — one definition, three
## screens, never three tables that agree.
##
## ── ⚠️ WHERE THE NUMBERS COME FROM: `Career`, ALL OF THEM ────────────────────────────────────
## THIS FILE AUTHORS NO PACE, NO PAR AND NO GRADE. The career-side workstream owns all three
## (`career.gd`: `dynasty_standing()`, `dynasty_week_arrived()`, `dynasty_rung_at_week()`,
## `grade_result()`, `frontier_verdict()`), calibrated against round 16's measured medians and
## guarded by `scenes/_probe_grade.tscn`. Everything below is an ADAPTER: it calls those, formats
## them, and stops.
##
## An earlier draft of this file carried its own par curve and its own eight grade bands as a
## fallback. That was two definitions of the same fact waiting to disagree — the exact failure the
## `Pace` indirection exists to prevent — so it was deleted the moment `Career` shipped the real
## one. If `Career` ever loses these methods the screens go QUIET (no strip, no grade), which is
## the honest failure: a blank panel is recoverable, a screen quoting a par nothing else believes
## in is not.
##
## ⚠️ THE WORDING IS ALSO CAREER'S. `dynasty_standing()["line"]` and `frontier_verdict()["line"]`
## are shown verbatim. `career.gd` says it in its own comment — *"a screen that re-derives the
## wording is a screen that can disagree with the grade it is showing"* — and this file obeys it.
extends Control

const UiTheme = preload("res://scripts/ui/theme.gd")

const WEEKS_PER_YEAR := 48


# ══════════════════════════════════════════════════════════════════════════════════════════════
# THE PACE ADAPTER — one definition, read by town_ui.gd and report_ui.gd
# ══════════════════════════════════════════════════════════════════════════════════════════════

## Which authority answered. "career" when the career-side model is present, "absent" otherwise —
## and "absent" means the screens draw nothing rather than inventing a par.
## ⚠️ THIS IS THE LIVENESS CANARY for the whole feature: a probe that cannot tell a live model
## from a dead one cannot tell whether the integration landed.
static func pace_source() -> String:
	var c := _career()
	if c != null and c.has_method("dynasty_standing") and c.has_method("grade_result"):
		return "career"
	return "absent"


static func _career() -> Node:
	var loop := Engine.get_main_loop()
	if loop == null:
		return null
	var root := (loop as SceneTree).get_root()
	if root == null:
		return null
	return root.get_node_or_null("Career")


## The week the pace-setter is expected to ARRIVE at rung `idx`. Straight passthrough.
static func par_week_for(idx: int) -> int:
	var c := _career()
	if c == null or not c.has_method("dynasty_week_arrived"):
		return 0
	return int(c.call("dynasty_week_arrived", idx))


## Which rung the pace-setter holds in a given week. Straight passthrough — the town's track draws
## the race off this, so the two bars can never disagree about who is where.
static func par_rung_at_week(w: int) -> int:
	var c := _career()
	if c == null or not c.has_method("dynasty_rung_at_week"):
		return -1
	return int(c.call("dynasty_rung_at_week", w))


## The one call the other two screens make. Read from `Career` at the moment of the call — no
## cached copy, so this cannot go stale against the thing it describes (round 13's scoreboard
## announced its winner at frame 0 and disagreed with the frame in 100% of frames; round 15's
## stable screen promised ceilings the tick never applied — both held their own copy of a fact).
static func snapshot() -> Dictionary:
	var c := _career()
	if pace_source() != "career":
		return {}
	var stand: Dictionary = c.call("dynasty_standing")
	var grade: Dictionary = c.call("grade_result")
	return {
		"week": int(c.get("week")),
		"leagueIndex": int(c.get("league_index")),
		"leagueName": str(c.call("current_league_name")),
		"wonGame": bool(c.get("won_game")),
		"dynasty": stand,
		"grade": grade,
		"state": str(stand.get("state", "level")),
		"marginWeeks": int(stand.get("marginWeeks", 0)),
		"marginSeasons": int(stand.get("marginSeasons", 0)),
		"line": str(stand.get("line", "")),
		"source": "career",
	}


static func grade_result() -> Dictionary:
	var c := _career()
	if c == null or not c.has_method("grade_result"):
		return {}
	return c.call("grade_result")


## THE FRONTIER VERDICT — "outclassed" / "unlucky" / "climbing" / "fresh", named by `Career` off
## the round record it keeps (`frontier_rounds` / `frontier_round_wins`). **This function DERIVES
## NOTHING.** A screen cannot tell "outclassed" from "unlucky" — that distinction is the entire
## finding of `docs/CONVERSION_DIAGNOSIS.md` §2c, and it needs the round history, which lives on
## the career. No authority means no banner, never a guessed one.
static func frontier_verdict() -> Dictionary:
	var c := _career()
	if c == null or not c.has_method("frontier_verdict"):
		return {}
	return c.call("frontier_verdict")


## The sentence the town and the report both show — CAREER'S OWN WORDING, prefixed with the week
## so the clock is in the sentence rather than only in a corner of the header.
static func pace_line(snap: Dictionary) -> String:
	if snap.is_empty():
		return ""
	return "Week %d, holding %s. %s" % [int(snap["week"]), str(snap["leagueName"]), str(snap["line"])]


static func pace_color(snap: Dictionary) -> Color:
	if snap.is_empty():
		return UiTheme.TEXT_SECONDARY
	match str(snap.get("state", "level")):
		"ahead":
			return UiTheme.SAFE
		"behind":
			return UiTheme.CAUTION
		_:
			return UiTheme.GOLD


# ══════════════════════════════════════════════════════════════════════════════════════════════
# THE SCREEN
# ══════════════════════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	self.theme = UiTheme.base_theme()
	# ⚠️ SET BEFORE ANYTHING ELSE. `town_ui.gd` routes here on arrival when `won_game` is true and
	# this flag is unset; without it the player would be pinned to the ending forever, unable to
	# get back to a stable they may still want to run. Meta, not a save field, on purpose — it is
	# session state, and adding a field to `save_game.gd` is not this file's to add.
	var c := _career()
	if c != null:
		c.set_meta("ending_seen", true)
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.SURFACE
	bg.anchor_right = 1; bg.anchor_bottom = 1
	add_child(bg)

	var tex := Art.area_texture("town")
	if tex != null:
		var bg_rect := TextureRect.new()
		bg_rect.anchor_right = 1; bg_rect.anchor_bottom = 1
		bg_rect.texture = tex
		bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_rect.modulate = Color(1, 1, 1, 0.30)
		add_child(bg_rect)

	var root_margin := MarginContainer.new()
	root_margin.anchor_right = 1; root_margin.anchor_bottom = 1
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		root_margin.add_theme_constant_override(side, UiTheme.SPACE_XL)
	add_child(root_margin)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	root_margin.add_child(outer)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", UiTheme.SPACE_LG)
	scroll.add_child(col)

	col.add_child(_title_block())
	col.add_child(_grade_block())
	col.add_child(_ladder_block())
	col.add_child(_summary_block())
	col.add_child(_roster_block())

	outer.add_child(HSeparator.new())
	outer.add_child(_footer())


func _title_block() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UiTheme.SPACE_XS)

	var t := Label.new()
	t.text = "TAMERS APEX — TAKEN"
	t.add_theme_font_size_override("font_size", UiTheme.SIZE_DISPLAY)
	t.add_theme_color_override("font_color", UiTheme.GOLD)
	v.add_child(t)

	var c := _career()
	var champ: Dictionary = {}
	if c != null and c.has_method("champion_for"):
		var last: int = maxi(0, (c.get("leagues") as Array).size() - 1)
		champ = c.call("champion_for", last)
	var champ_name: String = str(champ.get("name", "the incumbent")) if not champ.is_empty() else "the incumbent"
	v.add_child(UiTheme.body_text(
		"The Circuit is finished. %s no longer holds the Apex title — you do." % champ_name,
		"secondary"))
	return v


## THE GRADE. Every value is `Career.grade_result()`'s, including the tier name and the blurb.
## ⚠️ THE NUMBERS ARE PRINTED NEXT TO THE TIER ON PURPOSE — a rank with nothing behind it is a
## screen the player cannot check, and this project has shipped two screens that disagreed with
## their own source. Week, seasons, titles, scraped rungs and the margin are all shown so the tier
## can be reconstructed from the row beneath it.
func _grade_block() -> Control:
	var grade: Dictionary = grade_result()
	var panel := PanelContainer.new()
	var sb := UiTheme.panel_style("raised", UiTheme.GOLD)
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)

	if grade.is_empty():
		# ⚠️ QUIET, NOT INVENTED. See the file header: no career model, no grade.
		var miss := UiTheme.body_text(
			"The career-side grade (Career.grade_result) is not available in this build, so no rank is shown.",
			"muted")
		panel.add_child(miss)
		return panel

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_XL)
	panel.add_child(row)

	var tier_col := VBoxContainer.new()
	tier_col.custom_minimum_size = Vector2(230, 0)
	tier_col.add_theme_constant_override("separation", 0)
	row.add_child(tier_col)

	var tier := Label.new()
	tier.text = str(grade.get("tier", "?"))
	tier.autowrap_mode = TextServer.AUTOWRAP_OFF
	tier.add_theme_font_size_override("font_size", 40)
	tier.add_theme_color_override("font_color", UiTheme.GOLD)
	tier_col.add_child(tier)

	var score := Label.new()
	score.text = "score %d" % int(grade.get("score", 0))
	score.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBHEADING)
	score.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	tier_col.add_child(score)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	row.add_child(right)

	var weeks: int = int(grade.get("week", 0))
	var wk := UiTheme.body_text("Title taken in week %d — %d season%s on the road." % [
		weeks, int(grade.get("seasons", 0)), "" if int(grade.get("seasons", 0)) == 1 else "s"], "primary")
	wk.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBHEADING)
	right.add_child(wk)

	var dyn: Dictionary = grade.get("dynasty", {})
	var margin: int = int(grade.get("marginWeeks", 0))
	var vs_text := ""
	var vs_col := UiTheme.GOLD
	var par: int = int(dyn.get("parWeek", 0))
	var house: String = str(dyn.get("house", "the pace-setter"))
	if margin > 0:
		vs_text = "%s takes it in week %d. You were %d weeks quicker." % [_sentence_case(house), par, margin]
		vs_col = UiTheme.SAFE
	elif margin < 0:
		vs_text = "%s takes it in week %d. You were %d weeks slower." % [_sentence_case(house), par, -margin]
		vs_col = UiTheme.CAUTION
	else:
		vs_text = "%s takes it in week %d. You matched it exactly." % [_sentence_case(house), par]
	var vs := UiTheme.body_text(vs_text, "primary")
	vs.add_theme_color_override("font_color", vs_col)
	right.add_child(vs)

	var blurb := UiTheme.body_text(str(grade.get("blurb", "")), "secondary")
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(blurb)

	# The row the tier can be checked against. `line` is Career's own single formatting of the
	# same four numbers — shown verbatim rather than reassembled here.
	var detail := UiTheme.body_text(str(grade.get("line", "")), "muted")
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	right.add_child(detail)

	return panel


## THE CLIMB ITSELF, rung by rung, with the week you were meant to be there by. This is the screen
## saying what the score was made of — a single number would answer "how did I do" and leave "what
## did I do" unanswered, which is the half CLAUDE.md's "my read was right" fantasy lives in.
func _ladder_block() -> Control:
	var c := _career()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	v.add_child(UiTheme.heading("The Climb", 3))
	if c == null:
		return v

	var leagues: Array = c.get("leagues")
	var won: Array = c.get("leagues_won")
	var n: int = leagues.size()

	# ⚠️ FIXED CELL WIDTHS, AND `AUTOWRAP_OFF`. The first build of this block used
	# `UiTheme.body_text` in a GridContainer; those labels autowrap, which gives them a ~0 minimum
	# width, and every column collapsed on top of the next — legible in code, unreadable on screen.
	# Caught by looking at the capture, not by the probe, which is the whole reason the capture
	# exists.
	var grid := GridContainer.new()
	grid.columns = maxi(1, n)
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)

	for i in range(n):
		grid.add_child(_climb_cell(str((leagues[i] as Dictionary).get("name", "?")),
			UiTheme.TEXT_PRIMARY, UiTheme.SIZE_CAPTION))
	for i in range(n):
		var taken: bool = i < won.size() and bool(won[i])
		var bar := PanelContainer.new()
		bar.custom_minimum_size = Vector2(88, 16)
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiTheme.GOLD if taken else UiTheme.BORDER_FAINT
		sb.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("panel", sb)
		bar.tooltip_text = "%s — title %s" % [str((leagues[i] as Dictionary).get("name", "?")),
			"taken" if taken else "not taken"]
		grid.add_child(bar)
	## ⚠️ NAME THE PEOPLE. Eleven abstract rungs is a progress bar; eleven NAMED titleholders is a
	## career. `Career.champion_for()` has authored a name and a title for every rung since the
	## ladder shipped and this screen — the one that exists to say what the climb was worth —
	## printed none of them. Surnames only: a full name does not fit an eleven-column grid, and a
	## truncated first name ("Dunna…") identifies nobody. The tournament screen's Ladder Board uses
	## the same rule and the same source, so the two boards can never name different champions.
	if c.has_method("champion_for"):
		for i in range(n):
			var taken2: bool = i < won.size() and bool(won[i])
			var champ: Dictionary = c.call("champion_for", i)
			grid.add_child(_climb_cell(_surname(str(champ.get("name", ""))),
				UiTheme.TEXT_SECONDARY if taken2 else UiTheme.TEXT_MUTED, UiTheme.SIZE_CAPTION))

	for i in range(n):
		grid.add_child(_climb_cell("wk %d" % par_week_for(i), UiTheme.TEXT_MUTED, UiTheme.SIZE_CAPTION))

	var dyn: Dictionary = {}
	if c.has_method("dynasty_standing"):
		dyn = c.call("dynasty_standing")
	var foot := UiTheme.body_text(
		"A gold bar is a title TAKEN — the whole draw, the champion's belt included, off the titleholder named under it. The week beneath is when %s arrived there; they take the Apex title in week %d."
		% [str(dyn.get("house", "the pace-setter")), int(dyn.get("parWeek", 0))], "muted")
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(foot)
	return v


## ⚠️ NOT `String.capitalize()` — that title-cases every word, turning Career's authored
## "the Varra stable" into "The Varra Stable" and inventing a proper noun the rest of the game
## does not use. Only the first character moves.
static func _sentence_case(s: String) -> String:
	return s if s == "" else s.substr(0, 1).to_upper() + s.substr(1)


## "Dunnal Bray" -> "Bray"; "The Dynast" -> "Dynast". ⚠️ `tournament_ui.gd:_surname()` is the same
## two lines — deliberately duplicated rather than shared, because the alternative is one screen
## preloading the other purely for a string helper, and `report_ui.gd` already reaches into THIS
## file for the pace model. Two ⚠️-marked copies of a two-line formatter is cheaper than a third
## cross-screen dependency; if a third caller appears, that is the signal to lift it into theme.gd.
static func _surname(full: String) -> String:
	var parts: PackedStringArray = full.strip_edges().split(" ", false)
	return full if parts.size() == 0 else str(parts[parts.size() - 1])


func _climb_cell(text: String, tint: Color, size: int) -> Control:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.clip_text = true
	l.custom_minimum_size = Vector2(88, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", tint)
	return l


func _summary_block() -> Control:
	var c := _career()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	v.add_child(UiTheme.heading("The Career", 3))
	if c == null:
		return v

	# ⚠️ TITLES AND SCRAPED RUNGS COME FROM `grade_result()`, NOT FROM A SECOND COUNT OF
	# `leagues_won` HERE. They are inputs to the tier shown above; a screen that recounted them
	# could show a tally that does not add up to its own grade.
	var grade: Dictionary = grade_result()
	var won: Array = c.get("leagues_won")
	var titles: int = int(grade.get("titles", 0))
	var scraped: int = int(grade.get("scraped", 0))

	var stable: Array = []
	var retired_n: int = 0
	if has_node("/root/Roster"):
		stable = Roster.monsters
		for m in stable:
			if bool(m.retired):
				retired_n += 1

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_XL)
	v.add_child(row)
	row.add_child(_stat_tile("%d" % int(grade.get("week", int(c.get("week")))), "weeks"))
	row.add_child(_stat_tile("%d / %d" % [titles, won.size()], "titles taken"))
	row.add_child(_stat_tile("%d" % scraped, "rungs scraped"))
	row.add_child(_stat_tile("%d" % int(c.get("gold")), "gold in hand"))
	row.add_child(_stat_tile("%d" % stable.size(), "in the stable"))
	row.add_child(_stat_tile("%d" % retired_n, "retired to the barn"))
	return v


func _stat_tile(value: String, label: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default", UiTheme.BORDER))
	panel.custom_minimum_size = Vector2(150, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	panel.add_child(v)
	var big := Label.new()
	big.text = value
	big.add_theme_font_size_override("font_size", UiTheme.SIZE_HEADING)
	big.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY)
	v.add_child(big)
	var small := UiTheme.body_text(label, "muted")
	small.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	v.add_child(small)
	return panel


## ⚠️ THE MONSTERS ARE HALF THE SCREEN, NOT A FOOTNOTE. `CLAUDE.md`: "you run a STABLE; the stable
## produces the PARTY." An ending that prints a grade and no bodies has scored the player's
## calendar and ignored everything they actually made.
func _roster_block() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	v.add_child(UiTheme.heading("The Ones Who Did It", 3))

	if not has_node("/root/Roster") or Roster.monsters.is_empty():
		v.add_child(UiTheme.body_text("The stable is empty.", "muted"))
		return v

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", UiTheme.SPACE_MD)
	grid.add_theme_constant_override("v_separation", UiTheme.SPACE_MD)
	v.add_child(grid)
	for m in Roster.monsters:
		grid.add_child(_monster_card(m))
	return v


func _monster_card(m) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 108)
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("raised", UiTheme.BORDER))
	panel.tooltip_text = "stable slot %s" % str(m.id)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	panel.add_child(row)

	var tex := Art.creature_texture(str(m.species_id))
	if tex != null:
		var t := TextureRect.new()
		t.texture = tex
		t.custom_minimum_size = Vector2(84, 84)
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		row.add_child(t)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)

	# ⚠️ THE DISPLAY NAME IS `species_name`, NOT `id`. `id` is the stable SLOT key
	# ("slot3#2,STR,..."), and the first build of this card led with it — which rendered as a blank
	# line on a freshly generated roster where the bare id is "". `stable_ui.gd:296` has always
	# used `species_name`; this now matches it rather than inventing a second convention.
	var name_lbl := Label.new()
	name_lbl.text = str(m.species_name)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.clip_text = true
	name_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBHEADING)
	name_lbl.add_theme_color_override("font_color", UiTheme.GOLD if not bool(m.retired) else UiTheme.TEXT_SECONDARY)
	col.add_child(name_lbl)

	var years: float = float(int(m.age_weeks)) / float(WEEKS_PER_YEAR)
	var sub := UiTheme.body_text("%s · %.1f yrs%s" % [
		str(m.class_name_), years, "  ·  retired" if bool(m.retired) else ""], "secondary")
	sub.autowrap_mode = TextServer.AUTOWRAP_OFF
	sub.clip_text = true
	col.add_child(sub)

	# The three stats it was actually built on — read straight off `stats`, not off the class name.
	var stats: Dictionary = m.stats
	var keys: Array = stats.keys()
	keys.sort_custom(func(a, b): return float(stats[a]) > float(stats[b]))
	var parts: Array = []
	for i in range(mini(3, keys.size())):
		parts.append("%s %d" % [str(keys[i]), int(round(float(stats[keys[i]])))])
	var st := UiTheme.body_text(" · ".join(parts), "primary")
	st.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	col.add_child(st)

	return panel


func _footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_MD)

	var town_btn := Button.new()
	town_btn.text = "Back to the Town"
	town_btn.custom_minimum_size = Vector2(0, 40)
	town_btn.focus_mode = Control.FOCUS_ALL
	town_btn.tooltip_text = "The stable is still yours. Keep running it, or stop here."
	for state in ["normal", "hover", "pressed", "disabled"]:
		town_btn.add_theme_stylebox_override(state, UiTheme.button_stylebox("primary", state))
	town_btn.add_theme_stylebox_override("focus", UiTheme.button_stylebox("primary", "focus"))
	town_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/town.tscn"))
	row.add_child(town_btn)

	var title_btn := Button.new()
	title_btn.text = "Title Screen"
	title_btn.custom_minimum_size = Vector2(0, 40)
	title_btn.focus_mode = Control.FOCUS_ALL
	title_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/title.tscn"))
	row.add_child(title_btn)

	var note := UiTheme.body_text(
		"Your career continues if you want it to — the ending does not close the save.", "muted")
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(note)

	town_btn.call_deferred("grab_focus")
	return row
