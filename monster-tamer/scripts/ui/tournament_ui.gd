## TOURNAMENTS — the ladder, which is the spine of the whole game.
##
## `CLAUDE.md`: *"The ladder is the spine. Wood → Tamers Apex must be completable, paced and
## satisfying end to end."* This screen is where that climb actually happens, and until now the
## Stable's "Enter a tournament" button dropped the player onto a tactics screen with no cup
## behind it.
##
## ⚠️ A CUP IS ALL-OR-NOTHING: `career.gd:enter_league_tournament()` promotes only on a SWEEP.
## That is a deliberately hard gate, so this screen must say so BEFORE entry, not after the loss —
## a player who finds out the rule by failing has been cheated of the decision.
##
## ⚠️ YOU MAY ENTER YOUR OWN LEAGUE OR ANY BELOW IT, NEVER ABOVE (`can_enter_league`). Punching
## down pays less: `REWARD_BY_DROP` mirrors React's 100/50/20% `rewardMultiplier`, so farming a
## league you have already cleared is a safety net, not a strategy.
extends Control

const UiTheme = preload("res://scripts/ui/theme.gd")

## Base purse for sweeping a cup at each league, scaling with the ladder. ⚠️ PROPOSED, NOT
## BALANCED — `CLAUDE.md` records that the balance baseline is SUSPENDED for the Godot rebuild,
## so these exist to make the economy *function*, not to be correct. Re-tune at the re-baseline.
const BASE_PURSE := 220
const PURSE_PER_LEAGUE := 140

## Punching down pays less — index is how many leagues BELOW your frontier you entered.
const REWARD_BY_DROP := [1.0, 0.5, 0.2]

var _list: VBoxContainer
var _result_box: VBoxContainer
var _header: Label


func _ready() -> void:
	self.theme = UiTheme.base_theme()
	_build()
	_refresh()
	# A cup just fought live (tactics -> arena, round by round via CupRun) lands back here once
	# every round is resolved and `CupRun.finish()` has already applied promotion. Render its
	# result exactly like the old headless path did, then drain it — same "show once" pattern as
	# `ReportScript.pending`.
	var cup := get_node_or_null("/root/CupRun")
	if cup != null and not cup.last_result.is_empty():
		var out: Dictionary = cup.last_result
		cup.last_result = {}
		_show_result(out)
		_refresh()  # league_index may have changed (promotion) — the cup-card list needs it too


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

	page.add_child(UiTheme.heading("Tournaments", 1))
	_header = UiTheme.body_text("", "secondary")
	page.add_child(_header)
	page.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	_result_box = VBoxContainer.new()
	_result_box.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	body.add_child(_result_box)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	body.add_child(_list)

	page.add_child(HSeparator.new())
	var back := Button.new()
	back.text = "Back to the Stable"
	back.custom_minimum_size = Vector2(0, 44)
	back.focus_mode = Control.FOCUS_ALL
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/stable.tscn"))
	page.add_child(back)


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()

	var have: int = Roster.monsters.size()
	_header.text = "%s league · week %d · %d gold · %d in the stable" % [
		Career.current_league_name(), Career.week, Career.gold, have]

	for idx in range(Career.league_index, -1, -1):
		_list.add_child(_cup_card(idx))


func _purse_for(idx: int) -> int:
	var drop: int = clampi(Career.league_index - idx, 0, REWARD_BY_DROP.size() - 1)
	var base: int = BASE_PURSE + PURSE_PER_LEAGUE * idx
	return int(round(float(base) * float(REWARD_BY_DROP[drop])))


func _cup_card(idx: int) -> Control:
	var panel := PanelContainer.new()
	var is_frontier: bool = idx == Career.league_index
	panel.add_theme_stylebox_override("panel",
		UiTheme.panel_style("raised", UiTheme.GOLD) if is_frontier else UiTheme.panel_style("default"))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	var lname: String = Career.league_at(idx).get("name", "?")
	var team_size: int = Career.team_size_for_league(idx)
	var have: int = Roster.monsters.size()

	col.add_child(UiTheme.heading("%s Cup%s" % [lname, "  ·  your league" if is_frontier else ""], 3))
	col.add_child(UiTheme.body_text(
		"%dv%d  ·  three rivals  ·  stat ceiling %d  ·  purse %dg" % [
			team_size, team_size, int(Career.stat_cap_for_league(idx)), _purse_for(idx)], "secondary"))

	# ⚠️ State the sweep rule BEFORE entry. Promotion on a sweep is a hard gate and the player
	# must be able to weigh it, not discover it by losing.
	if is_frontier:
		var promo := UiTheme.body_text(
			"Win all three and you are promoted. Lose one and you keep the purse but not the rank.", "primary")
		promo.add_theme_color_override("font_color", UiTheme.GOLD)
		col.add_child(promo)
	else:
		col.add_child(UiTheme.body_text(
			"Already cleared — pays %d%% for punching down." % int(REWARD_BY_DROP[
				clampi(Career.league_index - idx, 0, REWARD_BY_DROP.size() - 1)] * 100.0), "muted"))

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 38)
	btn.focus_mode = Control.FOCUS_ALL
	if have < team_size:
		btn.disabled = true
		btn.text = "Need %d monsters — you have %d" % [team_size, have]
	else:
		btn.text = "Enter the %s Cup" % lname
		btn.pressed.connect(_on_enter.bind(idx))
	col.add_child(btn)
	return panel


## Starts a LIVE cup: `CupRun` pre-generates each round's rival team, then this screen hands off
## to "The Read" for round 1. No fight happens here anymore — the player watches every round play
## out (tactics -> arena3d, `rival_count` times) before landing back on this screen. The three
## fights headless-in-a-for-loop that used to happen here now only happen via
## `Career.enter_league_tournament()` directly, which the QA harness and sandbox still call.
func _on_enter(idx: int) -> void:
	CupRun.start(idx, 3)
	get_tree().change_scene_to_file("res://scenes/tactics.tscn")


## Renders a finished cup's result exactly as the old headless `_on_enter` did — reused for the
## live path (`out` from `CupRun.finish()`) so the two paths share one rendering code path.
## ⚠️ The purse is paid HERE, not in career.gd/cup_run.gd. `enter_league_tournament` (and, by
## extension, the promotion rule `CupRun.finish()` shares with it) is also driven by the QA
## harness and the sandbox; paying gold inside either would make those runs mutate the player's
## economy as a side effect of measuring something else.
func _show_result(out: Dictionary) -> void:
	var idx: int = int(out.get("leagueIndex", 0))
	var before_league: String = str(out.get("beforeLeague", Career.current_league_name()))

	var wins: int = int(out.get("wins", 0))
	var rival_count: int = maxi(1, int(out.get("rivalCount", 3)))
	var purse: int = int(round(float(_purse_for(idx)) * (float(wins) / float(rival_count))))
	Career.add_gold(purse)

	for c in _result_box.get_children():
		c.queue_free()

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("raised", UiTheme.GOLD))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	col.add_child(UiTheme.heading("%s Cup — %d of %d" % [str(out.get("league", "")), wins, rival_count], 2))

	var matches: Array = out.get("matches", [])
	for i in range(matches.size()):
		var won: bool = bool(matches[i].get("won", false))
		var line := UiTheme.body_text("Round %d — %s" % [i + 1, "WON" if won else "lost"], "primary")
		line.add_theme_color_override("font_color", UiTheme.SAFE if won else UiTheme.TEXT_SECONDARY)
		col.add_child(line)

	var purse_line := UiTheme.body_text("Purse: %d gold" % purse, "primary")
	purse_line.add_theme_color_override("font_color", UiTheme.GOLD)
	col.add_child(purse_line)

	if bool(out.get("gameWon", false)):
		var w := UiTheme.heading("TAMERS APEX TAKEN — you have finished the Circuit.", 2)
		w.add_theme_color_override("font_color", UiTheme.GOLD)
		col.add_child(w)
	elif bool(out.get("promoted", false)):
		var p := UiTheme.heading("PROMOTED — %s to %s" % [before_league, Career.current_league_name()], 3)
		p.add_theme_color_override("font_color", UiTheme.GOLD)
		col.add_child(p)
		col.add_child(UiTheme.body_text(
			"Your stat ceiling rises to %d. Everything you trained to the old cap can grow again."
			% int(Career.current_stat_cap()), "secondary"))
	elif not bool(out.get("swept", false)):
		col.add_child(UiTheme.body_text(
			"No promotion — a cup must be swept. Train, then come back.", "secondary"))

	_result_box.add_child(panel)
