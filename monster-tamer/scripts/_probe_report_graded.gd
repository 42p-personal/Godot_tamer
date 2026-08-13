## THE GRADED REPORT — drive the REAL graded path and look at it.
##
##   P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/_probe_report_graded.tscn
##   P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/_probe_report_graded.tscn -- --fights 6
##
## ⚠️ RUN IT WITH A WINDOW, NEVER `--headless`: the dummy renderer returns blank images, so a
## headless run saves black rectangles and "passes".
##
## ── WHY THIS EXISTS ───────────────────────────────────────────────────────────────────────────
## ⚠️ NOTHING BELOW THE ROUND-20 EDITS HAS BEEN RUN. The Godot binary this whole project shells out
## to — `P:/Godot_v4.7.1-stable_win64.exe`, named in CLAUDE.md, `run_contract.sh` and every probe
## header — was not present on the machine when the phase-2 hunt and the liveness canary were
## written (P:\ searched to depth 3: no `*odot*`; the godot MCP reports `C:\Program
## Files\Godot\Godot.exe ENOENT`). The last real capture set in `user://screens/` is dated
## 2026-08-11 22:11. The structural argument about `warn` below is derived from source and is
## checkable by reading `sim.gd:413` and `report_ui.gd:_read_third_claim`; the HUNT is an
## unexecuted experiment. Treat its first run as the measurement, not as a re-run.
##
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
## ── ⚠️ AND "NOT REACHED IN 6 FIGHTS" WAS THE WRONG FINDING. IT WAS NOT RARE, IT WAS FORBIDDEN. ──
## Round 19 reported `warn` unreached across six fights spanning trained-stat deltas of −36% to
## +94% and left open whether the branch is rare or dead. It is neither: with the order set this
## probe committed, RIGHT-AND-LOST was IMPOSSIBLE, and the proof is three lines of the sim rather
## than a statistic.
##
##   1. `sim.gd:413` sets `winner = "B"` only when `alive_a == 0`. A decisive loss therefore means
##      EVERY body on your side is dead. There is no such thing here as losing with survivors —
##      the only other exit is the tick cap, and `_probe_sim_quality.gd` asserts that never fires.
##   2. `warn` requires `held == judged`: every graded claim must hold.
##   3. The probe's orders put `temperament: cautious` on `_team_a[0]`, and
##      `report_ui.gd:_read_third_claim` turns the FIRST cautious body it finds into a `survive`
##      claim — "it is standing at the end". In a decisive loss that body is dead, so the claim
##      grades `broke`, so `held < judged`, so `warn` cannot fire. Ever. On any seed.
##
## The same block closes a second door at the bottom of the ladder: when the target order resolves
## to the WHOLE enemy side (`casters` returns two bodies, and Wood/Copper/Tin field 1–2), the
## target claim can only grade `held` if every mark died — which is `alive_b == 0`, which is a WIN.
## `_probe_screens.gd` captures the report at exactly that size, so neither of its report captures
## could ever have shown this verdict either.
##
## So the sweep now runs TWO order sets and says which of them can reach the branch at all:
##
##   ordinary   the round-19 orders (casters · tight · one cautious body) — kept unchanged so the
##              existing rows stay comparable, and now labelled with WHY warn is closed to them.
##   rightlost  a deliberate right-and-lost candidate, and every part of it is an order a player
##              can actually give: man-mark their softest body (one mark of five, so the marks are
##              never the whole side), stand LOOSE (the shape claim then measures their AoE and not
##              our diver's isolation), and send one body on a DIVE — `reach_back` is the only
##              third claim in `_read_third_claim` that a corpse can still have satisfied, because
##              it asks whether the blow LANDED, not whether the body lived.
##
## `_warn_possible()` states that reachability per fight from the claim set alone, before the
## verdict is read, so a future sweep can never again report a branch as "not reached" when the
## fixture forbade it.
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

## ⚠️ THE HUNT ONLY SWEEPS FILLS THAT CAN PRODUCE A LOSS, because RIGHT-AND-LOST needs a loss and
## `RIVAL_FILL` above spends half its budget on walkovers. The band is a STARTING GUESS, not a
## measured crossover — nobody has plotted win rate against fill on this fixture, so if the hunt
## comes back all-wins the answer is to raise this list, and the summary says so in those words
## rather than reporting the branch as unreachable.
## The top of the band is deliberately not absurd: at a fill where your side never lands a killing
## blow the MARK cannot fall either, and the target claim breaks for the opposite reason.
const HUNT_FILL := [1.15, 1.30, 1.45, 1.60, 1.80, 2.00]

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
		await _one_fight(i, 160 + i * 37, float(RIVAL_FILL[i % RIVAL_FILL.size()]), "ordinary")

	# ── PHASE 2: THE RIGHT-AND-LOST HUNT. Same screen, same roster shape, DIFFERENT ORDERS — and
	# the orders are the variable that decides whether the branch is reachable at all (see the ⚠️ at
	# the head of this file). It stops at the first `warn` because one honest capture of the verdict
	# is the whole acceptance criterion; if none fires, every row is still printed and the
	# structural column says whether the fixture even allowed it.
	# ⚠️ Phase 1 CAN in principle reach `warn` on its own (see the head of this file for why it
	# cannot with the orders it commits, but that is a property of those orders, not a law), so ask
	# BEFORE the hunt whether the branch is already covered. Otherwise the first hunt fight runs and
	# then reports itself as the one that reached it, which is the harness taking credit for the
	# other phase's result.
	var warn_before: bool = _tones_seen.has("warn")
	for j in range(HUNT_FILL.size()):
		await _one_fight(1000 + j, 173 + j * 53, float(HUNT_FILL[j]), "rightlost")
		if _tones_seen.has("warn") and not warn_before:
			print("  RIGHT-AND-LOST reached on hunt fight %d — stopping the hunt." % j)
			break

	_report()
	# ⚠️ A UNIFORM FRAME IS NOT AN OUTPUT, IT IS A FAILURE. Exit non-zero so a `--headless` run —
	# the one this file's header warns about — cannot be mistaken for a pass by whatever ran it.
	if not _blank.is_empty():
		printerr("*** BLANK CAPTURES (%d): %s" % [_blank.size(), ", ".join(_blank)])
		printerr("*** Run this WITH A WINDOW, never --headless.")
		get_tree().quit(1)
		return
	print("liveness: all %d captures carry a picture." % _shots)
	get_tree().quit(0)


## The orders under test. ⚠️ EVERY ONE OF THESE IS AN ORDER THE TACTICS SCREEN CAN ACTUALLY ISSUE.
## The moment a probe reaches a verdict through a plan the player cannot give, the capture stops
## being evidence about the game and becomes evidence about the probe.
func _plan_and_orders(profile: String) -> Array:
	if profile == "rightlost" and not _team_b.is_empty():
		# The softest body they have, by the pool the report itself would grade against: maxHp is
		# `40 + CON*2 + CON^2/1600` (CLAUDE.md), so lowest CON IS lowest pool. One mark of five, so
		# `_grade_target`'s `whole_team` escape hatch never fires and the claim is graded on focus
		# AND on the kill, the way it is at the top of the ladder.
		var soft = _team_b[0]
		for m in _team_b:
			if float(m.stats.get("CON", 0.0)) < float(soft.stats.get("CON", 0.0)):
				soft = m
		var plan_r: Dictionary = {"targetPriority": "manmark", "markedUnit": soft,
			"formation": "loose"}
		var orders_r: Dictionary = {}
		for i in range(_team_a.size()):
			# ⚠️ NOT ONE `cautious` BODY IN HERE, AND THAT IS THE POINT, NOT AN OVERSIGHT.
			# `_read_third_claim` takes the FIRST cautious body it sees and writes a survive claim
			# ("it is standing at the end"), which a decisive loss falsifies by definition. The dive
			# is the only third claim that survives its own subject's death.
			orders_r[_team_a[i]] = {"temperament": "balanced"}
			if i == 0:
				(orders_r[_team_a[i]] as Dictionary)["positionalIntent"] = "dive"
		return [plan_r, orders_r]

	var plan: Dictionary = {"targetPriority": "casters", "formation": "tight"}
	var orders: Dictionary = {}
	for i in range(_team_a.size()):
		orders[_team_a[i]] = {"temperament": "cautious" if i == 0 else "balanced"}
	return [plan, orders]


## ⚠️ CAN THIS FIGHT REACH `warn` AT ALL — asked of the CLAIM SET, before the fight is graded.
## `warn` = every graded claim held AND the player did not win. `sim.gd:413` only writes
## `winner = "B"` when `alive_a == 0`, so in any decisive loss every body of yours is dead. Two
## claim shapes are then unsatisfiable by construction:
##   * a `survive` claim — its subject is one of yours, and it is dead;
##   * a target claim whose marks are the WHOLE enemy side — "all marks fell" is `alive_b == 0`,
##     which is a win, not a loss.
## Returns {"possible": bool, "why": String}. A false here is not a bug in the game; it is the
## reason a sweep must never report this branch as merely "not reached".
func _warn_possible(claims: Array, enemy_n: int) -> Dictionary:
	for c in claims:
		var d: Dictionary = c
		if str(d.get("id", "")) == "hold" and str(d.get("mode", "")) == "survive":
			return {"possible": false,
				"why": "a survive claim is committed (%s) and a decisive loss kills its subject"
					% str(d.get("axis", "?"))}
		if str(d.get("id", "")) == "target" and (d.get("marks", []) as Array).size() >= enemy_n:
			return {"possible": false,
				"why": "the target order marks all %d of their bodies, so 'the marks fell' IS a win"
					% enemy_n}
	return {"possible": true, "why": "no claim in this set is falsified by losing"}


func _one_fight(index: int, week: int, rival_fill: float, profile: String) -> void:
	_setup(week, rival_fill)
	var po: Array = _plan_and_orders(profile)
	var plan: Dictionary = po[0]
	var orders: Dictionary = po[1]

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
	# ⚠️ THE FILENAME CARRIES THE ORDER SET. Two profiles writing `fight_N.png` into one directory
	# is the stale-PNG trap `_probe_screens.gd` already paid for, one step removed: the pictures
	# would be fresh and still be read as one sweep.
	var stem: String = "%s_%d" % [profile, index]
	await _shot("%s.png" % stem)

	DisplayServer.window_set_size(SMALL)
	for _i in 20:
		await get_tree().process_frame
	await _shot("%s_small.png" % stem)

	# ⚠️ THE FOLD IS WHERE THE CLOSING BLOCK LIVES, so a top-of-page capture cannot see it. On a
	# real 5v5 the report runs past two viewports and "WHAT TO CHANGE" — the instruction the whole
	# screen builds to — is the LAST thing on it. `_probe_screens.gd` learned the same lesson.
	var sc := _tallest_scroll(rep)
	if sc != null and sc.get_v_scroll_bar().max_value > sc.size.y + 8:
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
		for _i in 6:
			await get_tree().process_frame
		await _shot("%s_end.png" % stem)

	# ── WHAT THE SCREEN ACTUALLY SAYS. Read back through the same public functions the screen
	# used, so the row cannot describe a different grading than the one that was drawn.
	var graded: Array = ReportScript.grade_read(claims, res, _team_a, _team_b)
	var verdict: Dictionary = ReportScript.read_verdict(
		graded, str(res.get("winner", "draw")), _team_a, _team_b)
	var dec: Dictionary = rep.call("_decision_events_by_id", res.get("log", []),
		res.get("frames", []), res, _team_a + _team_b, _team_a.size())

	var style := _style_scan(rep)
	# ⚠️ ASKED OF THE CLAIMS, NOT OF THE OUTCOME. Whether this fight COULD have shown
	# right-and-lost is a property of the orders, and it has to be recorded even on the fights that
	# won — otherwise the sweep's summary is once again a count of misses with no idea whether a hit
	# was available.
	var reach: Dictionary = _warn_possible(claims, _team_b.size())
	_tones_seen[str(verdict.get("tone", "flat"))] = true
	_rows.append({
		"i": index, "profile": profile, "week": week, "fill": rival_fill,
		"winner": str(res.get("winner", "draw")),
		"frames": (res.get("frames", []) as Array).size(),
		"headline": str(verdict.get("headline", "")), "tone": str(verdict.get("tone", "flat")),
		"claims": graded, "dec_source": str(dec.get("source", "?")),
		"power_a": ReportScript.roster_power(_team_a), "power_b": ReportScript.roster_power(_team_b),
		"warn_possible": bool(reach["possible"]), "warn_why": str(reach["why"]),
		"style": style, "stem": stem,
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


## ── THE LIVENESS CANARY ───────────────────────────────────────────────────────────────────────
## ⚠️ THIS PROBE SAVED PNGs WITHOUT EVER LOOKING AT THEM. `_probe_screens.gd` grew a canary because
## a blank PNG nobody notices is how a round reports success on nothing — and it has TWO standing
## ways to happen here too: run this `--headless` (the dummy renderer hands back an empty image, and
## the ⚠️ at the top of this file warns about it in prose that nothing enforced) or shoot before the
## report has laid itself out. Both write a file, both print "capture: ...", and both read as a good
## run in the log.
##
## The test is "does this frame contain a PICTURE", not "is it black": a flat SURFACE fill is a
## perfectly plausible dark colour. A real report of this project has a headline, claim rows,
## team cards and a livery badge and clears the floor by two orders of magnitude; any single-fill
## frame scores exactly 1.
const CANARY_GRID := 48
const CANARY_MIN_COLOURS := 8

var _blank: Array = []
var _shots: int = 0


func _shot(name: String) -> void:
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var colours := {}
	var w: int = img.get_width()
	var h: int = img.get_height()
	for gx in CANARY_GRID:
		for gy in CANARY_GRID:
			colours[img.get_pixel(int(float(gx) / CANARY_GRID * w),
				int(float(gy) / CANARY_GRID * h)).to_rgba32()] = true
	if colours.size() < CANARY_MIN_COLOURS:
		_blank.append("%s (%d distinct colours in %d samples)"
			% [name, colours.size(), CANARY_GRID * CANARY_GRID])
	img.save_png(OUT_DIR + name)
	_shots += 1
	print("capture: %s  %dx%d  (%d distinct colours sampled)"
		% [name, w, h, colours.size()])


func _report() -> void:
	print("")
	print("=== THE GRADED REPORT — %d real fights ===" % _rows.size())
	for r in _rows:
		var st: Dictionary = r["style"]
		print("")
		print("── %s fight %d (week %d · rival fill %.2f) ─── %s" % [
			r["profile"], r["i"], r["week"], r["fill"], r["stem"]])
		print("   winner=%s  frames=%d  decision-log source=%s" % [r["winner"], r["frames"], r["dec_source"]])
		print("   right-and-lost reachable with these orders: %s — %s" % [
			"YES" if r["warn_possible"] else "NO", r["warn_why"]])
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

	# ⚠️ "NOT REACHED" AND "COULD NOT BE REACHED" ARE DIFFERENT FINDINGS AND ROUND 19 REPORTED THE
	# FIRST WHEN THE TRUTH WAS THE SECOND. A branch that no fixture in the sweep ALLOWED is not a
	# rare branch; it is an untested one, and the fix is a different order set, not more seeds.
	var hunted := 0
	var allowed := 0
	var losses_allowed := 0
	for r in _rows:
		if str(r["profile"]) == "rightlost":
			hunted += 1
		if bool(r["warn_possible"]):
			allowed += 1
			if str(r["winner"]) != "A":
				losses_allowed += 1
	print("")
	print("RIGHT-AND-LOST (tone 'warn' — \"YOUR READ WAS RIGHT. YOU LOST ANYWAY.\")")
	print("   fights whose ORDERS allowed it:   %d of %d" % [allowed, _rows.size()])
	print("   of those, fights actually LOST:   %d   (the branch also needs every claim to hold)"
		% losses_allowed)
	print("   deliberate hunt fights run:       %d" % hunted)
	if _tones_seen.has("warn"):
		for r in _rows:
			if str(r["tone"]) == "warn":
				print("   SEEN: %s → %s" % [r["stem"], r["headline"]])
	elif allowed == 0:
		printerr("   *** THE SWEEP FORBADE IT. Not one fight committed a claim set that a loss "
			+ "could leave intact — this is a finding about the FIXTURE, not about the game.")
	elif losses_allowed == 0:
		print("   NOT SEEN: the orders allowed it but no fight was lost. Raise HUNT_FILL.")
	else:
		print("   NOT SEEN in %d losses that allowed it. The branch is REACHABLE but rare: it "
			% losses_allowed + "needs every claim to hold in a fight you lost, and the weakness "
			+ "that loses a fight usually breaks one. Widen the hunt before calling it dead.")
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
