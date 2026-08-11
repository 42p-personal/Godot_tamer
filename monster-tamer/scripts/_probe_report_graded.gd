## THE GRADED REPORT — drive the REAL graded path and look at it.
##
##   P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/_probe_report_graded.tscn
##   P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/_probe_report_graded.tscn -- --fights 6
##
## ⚠️ RUN IT WITH A WINDOW, NEVER `--headless`: the dummy renderer returns blank images, so a
## headless run saves black rectangles and "passes".
##
## ── WHY THIS EXISTS ───────────────────────────────────────────────────────────────────────────
## Round 18's brief recorded the report's graded path as NEVER SEEN — "every capture in the repo
## reads NOT GRADED, because the harness drives a frameless demo battle". That is true of
## `_probe_screens.gd` and it is the reason the round-18 direction doc had to caveat its own
## finding about this screen. It is NOT true of the repo: `_probe_read_shot.gd` has driven a real
## graded fight since 2026-08-09 and `user://watch_*_REPORT.png` are graded captures. What was
## missing was a probe that (a) says so in an inventory anyone can re-run, (b) drives MORE THAN
## ONE fight, because the four `read_verdict()` branches are decided by the fight and one fight
## can only ever reach one of them, and (c) MEASURES the screen it captured rather than leaving
## the whole judgement to an eye.
##
## ⚠️ THE VERDICT BRANCH CANNOT BE FORCED WITHOUT LYING. read_verdict()'s four cases turn on how
## many claims held and who won; the interesting one — RIGHT AND LOST — needs a fight where every
## committed claim holds and the player still loses. This probe SWEEPS real fights (the fight seed
## is `hash([week, league, round])`, so moving the career week gives genuinely different fights on
## the same roster) and reports which branches it reached. It never synthesises a graded array to
## make a screenshot of a verdict that did not happen — a capture of a fabricated verdict is worth
## less than an honest "not reached in N fights".
##
## ── WHAT IT WRITES ────────────────────────────────────────────────────────────────────────────
##   user://report_graded/fight_N.png        the report, full size, per swept fight
##   user://report_graded/fight_N_small.png  the same report at 1152x648 (UI_LAYOUT_RULES R5)
## plus a printed inventory per fight: winner, verdict headline+tone, every claim's verdict and
## evidence, the decision-log source, and four machine checks on the RENDERED label tree:
##
##   S1  every font size is one of `UiTheme.TOKEN_FONT_SIZES`      (UI_LAYOUT_RULES R7)
##   S2  every text colour is one of `UiTheme.TOKEN_TEXT_COLOURS`  (UI_LAYOUT_RULES R7)
##   S3  no label below the 14px floor                             (ACCESSIBILITY §5)
##   S4  ⚠️ NO RAW SIM ID IN ANY VISIBLE STRING. Round 13 found the report saying "bulling through
##       a03 to a02" and fixed it in `_humanise` — on ONE of the two decision-log paths. A regex
##       over the rendered text is the only check that covers both, and every future one.
extends Node

const UiTheme = preload("res://scripts/ui/theme.gd")
const TacticsScript = preload("res://scripts/tactics.gd")
const ReportScript = preload("res://scripts/ui/report_ui.gd")

const OUT_DIR := "user://report_graded/"
const BIG := Vector2i(1600, 1000)
const SMALL := Vector2i(1152, 648)

## Deliberately more than one: `read_verdict()` has four branches and a single fight reaches one.
const DEFAULT_FIGHTS := 6

## ⚠️ THE SWEEP HAS TO MOVE THE OPPONENT, NOT ONLY THE DICE, AND THE FIRST RUN OF THIS PROBE
## PROVED IT. Three fights at a rival fill of 0.3 against a 0.5 roster gave the player a 37%
## trained-stat advantage and three wins, so only the two happy branches were ever reachable —
## and the branch that matters most (RIGHT AND LOST) needs a loss. The fill runs from a walkover
## to an outclassing so the sweep can reach both ends honestly.
const RIVAL_FILL := [0.30, 0.55, 0.75, 0.95, 1.20, 1.50]

var _team_a: Array = []
var _team_b: Array = []
var _rows: Array = []
var _tones_seen: Dictionary = {}


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var n := DEFAULT_FIGHTS
	var argv: Array = OS.get_cmdline_user_args()
	var fi: int = argv.find("--fights")
	if fi >= 0 and fi + 1 < argv.size():
		n = maxi(1, int(argv[fi + 1]))

	for i in range(n):
		# ⚠️ THE WEEK IS THE ONLY DIAL THAT CHANGES THE FIGHT WITHOUT CHANGING THE GAME.
		# `arena_3d.gd:_resolve_fight()` seeds the sim from `hash([week, league_index, round])`, so
		# stepping the week gives a genuinely different fight against the same league, same roster
		# shape and same orders. Nothing about the SCREEN under test varies across the sweep.
		await _one_fight(i, 160 + i * 37, float(RIVAL_FILL[i % RIVAL_FILL.size()]))

	_report()
	get_tree().quit(0)


func _one_fight(index: int, week: int, rival_fill: float) -> void:
	_setup(week, rival_fill)
	var plan: Dictionary = {"targetPriority": "casters", "formation": "tight"}
	var orders: Dictionary = {}
	for i in range(_team_a.size()):
		orders[_team_a[i]] = {"temperament": "cautious" if i == 0 else "balanced"}

	var gp: String = TacticsScript.gameplan_for(_team_b.map(func(m): return m.species_name))
	var claims: Array = ReportScript.build_read(plan, orders, _team_a, _team_b)
	for m in _team_a + _team_b:
		m.reset_for_battle()
	TacticsScript.commit(plan, TacticsScript.team_plan_for_gameplan(gp, _team_a), orders,
		TacticsScript.orders_for_gameplan(gp, _team_b), {}, {}, _team_a, _team_b)
	TacticsScript.committed["read"] = {"claims": claims, "gameplan": gp}

	# ── THE REAL FIGHT, through the real screen. Not `battle_sim.gd`: the whole point of this
	# probe is the path that emits a frame stream, because `grade_read()` refuses to grade without
	# one and that refusal is what every prior capture was showing.
	DisplayServer.window_set_size(BIG)
	await get_tree().process_frame
	var arena = load("res://scenes/arena3d.tscn").instantiate()
	add_child(arena)
	var resolved := false
	for _i in 8000:
		await get_tree().process_frame
		if not (arena.get("result") as Dictionary).is_empty():
			resolved = true
			break
	var res: Dictionary = arena.get("result") if resolved else {}
	arena.queue_free()
	await get_tree().process_frame
	if not resolved:
		printerr("fight %d: the arena never resolved — nothing to report" % index)
		return

	# ── THE SCREEN.
	ReportScript.hand_off(res, _team_a, _team_b)
	var rep := (load("res://scenes/report.tscn") as PackedScene).instantiate()
	add_child(rep)
	for _i in 60:
		await get_tree().process_frame
	await _shot("fight_%d.png" % index)

	DisplayServer.window_set_size(SMALL)
	for _i in 20:
		await get_tree().process_frame
	await _shot("fight_%d_small.png" % index)

	# ⚠️ THE FOLD IS WHERE THE CLOSING BLOCK LIVES, so a top-of-page capture cannot see it. On a
	# real 5v5 the report runs past two viewports and "WHAT TO CHANGE" — the instruction the whole
	# screen builds to — is the LAST thing on it. `_probe_screens.gd` learned the same lesson.
	var sc := _tallest_scroll(rep)
	if sc != null and sc.get_v_scroll_bar().max_value > sc.size.y + 8:
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
		for _i in 6:
			await get_tree().process_frame
		await _shot("fight_%d_end.png" % index)

	# ── WHAT THE SCREEN ACTUALLY SAYS. Read back through the same public functions the screen
	# used, so the row cannot describe a different grading than the one that was drawn.
	var graded: Array = ReportScript.grade_read(claims, res, _team_a, _team_b)
	var verdict: Dictionary = ReportScript.read_verdict(
		graded, str(res.get("winner", "draw")), _team_a, _team_b)
	var dec: Dictionary = rep.call("_decision_events_by_id", res.get("log", []),
		res.get("frames", []), res, _team_a + _team_b, _team_a.size())

	var style := _style_scan(rep)
	_tones_seen[str(verdict.get("tone", "flat"))] = true
	_rows.append({
		"i": index, "week": week, "fill": rival_fill, "winner": str(res.get("winner", "draw")),
		"frames": (res.get("frames", []) as Array).size(),
		"headline": str(verdict.get("headline", "")), "tone": str(verdict.get("tone", "flat")),
		"claims": graded, "dec_source": str(dec.get("source", "?")),
		"power_a": ReportScript.roster_power(_team_a), "power_b": ReportScript.roster_power(_team_b),
		"style": style,
	})

	rep.queue_free()
	await get_tree().process_frame


## ── THE FIXTURE ───────────────────────────────────────────────────────────────────────────────
## A real 5v5 league mid-career, so the claims that only exist at size ("hunt the casters" resolves
## to TWO bodies) are actually generated. `_probe_read_shot.gd` uses the same shape deliberately.
func _setup(week: int, rival_fill: float) -> void:
	Career.reset_new_game()
	Roster.reset_to_empty()
	var idx := 0
	for i in range(Career.leagues.size()):
		if Career.team_size_for_league(i) >= 5:
			idx = i
			break
	Career.league_index = idx
	Career.week = week
	Career.frontier_since_week = maxi(0, week - 40)
	CupRun.start(idx, 3)
	CupRun.current_round = 1
	for i2 in range(5):
		var m = GameData.make_monster(Art.ROSTER[i2 % Art.ROSTER.size()], 0.5)
		m.id = Roster.next_slot_id()
		Roster.monsters.append(m)
	_team_a = Roster.fielded_team(5)
	if _team_a.is_empty():
		_team_a = Roster.monsters.duplicate()
	_team_b = Roster.make_rival_team(_team_a.size(), rival_fill)


## ── THE MACHINE CHECKS ────────────────────────────────────────────────────────────────────────

## ⚠️ THE ID PATTERN IS THE SIM'S, NOT A GUESS. `report_ui.gd:_humanise` builds ids as
## `"a%02d" / "b%02d"`, so `a03`/`b11` is exactly what leaks. The word boundary keeps it from
## firing on ordinary prose — no species name in `data/` matches `[ab]` followed by two digits.
const SIM_ID_RE := "\\b[ab][0-9]{2}\\b"


func _style_scan(root: Node) -> Dictionary:
	var out := {"labels": 0, "off_size": 0, "off_colour": 0, "below_floor": 0,
		"sizes": {}, "colours": {}, "sim_ids": []}
	var re := RegEx.new()
	re.compile(SIM_ID_RE)
	var stack: Array = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		for c in cur.get_children():
			stack.append(c)
		var text := ""
		if cur is Label:
			out["labels"] = int(out["labels"]) + 1
			var l := cur as Label
			text = l.text
			if l.has_theme_font_size_override("font_size"):
				var fs: int = l.get_theme_font_size("font_size")
				if not (fs in UiTheme.TOKEN_FONT_SIZES):
					out["off_size"] = int(out["off_size"]) + 1
					(out["sizes"] as Dictionary)[fs] = int((out["sizes"] as Dictionary).get(fs, 0)) + 1
				if fs < UiTheme.SIZE_CAPTION:
					out["below_floor"] = int(out["below_floor"]) + 1
			if l.has_theme_color_override("font_color"):
				var col: Color = l.get_theme_color("font_color")
				if not UiTheme.is_token_colour(col):
					out["off_colour"] = int(out["off_colour"]) + 1
					var key := "%.2f,%.2f,%.2f" % [col.r, col.g, col.b]
					(out["colours"] as Dictionary)[key] = int((out["colours"] as Dictionary).get(key, 0)) + 1
		elif cur is Button:
			text = (cur as Button).text
		if text != "" and re.search(text) != null:
			(out["sim_ids"] as Array).append(text)
	return out


func _tallest_scroll(n: Node) -> ScrollContainer:
	var best: ScrollContainer = null
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is ScrollContainer:
			var s := cur as ScrollContainer
			if best == null or s.get_v_scroll_bar().max_value > best.get_v_scroll_bar().max_value:
				best = s
		for c in cur.get_children():
			stack.append(c)
	return best


func _shot(name: String) -> void:
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + name)
	print("capture: %s  %dx%d" % [name, img.get_width(), img.get_height()])


func _report() -> void:
	print("")
	print("=== THE GRADED REPORT — %d real fights ===" % _rows.size())
	for r in _rows:
		var st: Dictionary = r["style"]
		print("")
		print("── fight %d (week %d · rival fill %.2f) ───────────────────────────" % [r["i"], r["week"], r["fill"]])
		print("   winner=%s  frames=%d  decision-log source=%s" % [r["winner"], r["frames"], r["dec_source"]])
		print("   trained stat: yours %.0f · theirs %.0f (%+.0f%%)" % [
			r["power_a"], r["power_b"],
			((float(r["power_b"]) / maxf(float(r["power_a"]), 0.001)) - 1.0) * 100.0])
		print("   VERDICT [%s]  %s" % [r["tone"], r["headline"]])
		for c in (r["claims"] as Array):
			print("      %-9s %s" % [str((c as Dictionary).get("verdict", "?")).to_upper(),
				str((c as Dictionary).get("claim", ""))])
			print("                └ %s" % str((c as Dictionary).get("evidence", "")))
		print("   style: %d labels · off-scale %d · off-token %d · below 14px %d · raw sim ids %d" % [
			st["labels"], st["off_size"], st["off_colour"], st["below_floor"],
			(st["sim_ids"] as Array).size()])
		if int(st["off_size"]) > 0:
			print("      off-scale sizes: %s" % str(st["sizes"]))
		if int(st["off_colour"]) > 0:
			print("      off-token colours: %s" % str(st["colours"]))
		for s in (st["sim_ids"] as Array).slice(0, 4):
			print("      ⚠ RAW SIM ID ON SCREEN: %s" % s)

	# ⚠️ THE BRANCH COVERAGE IS THE POINT OF SWEEPING, SO STATE IT RATHER THAN IMPLYING IT FROM
	# the rows. A branch not reached is a branch not seen, and saying so is the finding.
	print("")
	print("verdict tones reached: %s" % str(_tones_seen.keys()))
	for t in ["good", "warn", "mixed", "bad", "flat"]:
		if not _tones_seen.has(t):
			print("   NOT REACHED: %-6s — no fight in this sweep produced it" % t)
	var tot_size := 0
	var tot_col := 0
	var tot_floor := 0
	var tot_ids := 0
	for r in _rows:
		var st2: Dictionary = r["style"]
		tot_size += int(st2["off_size"])
		tot_col += int(st2["off_colour"])
		tot_floor += int(st2["below_floor"])
		tot_ids += (st2["sim_ids"] as Array).size()
	print("")
	print("S1 off-scale font sizes: %d" % tot_size)
	print("S2 off-token colours:    %d" % tot_col)
	print("S3 labels below 14px:    %d" % tot_floor)
	print("S4 raw sim ids on screen:%d" % tot_ids)
	print("captures: %s" % ProjectSettings.globalize_path(OUT_DIR))
