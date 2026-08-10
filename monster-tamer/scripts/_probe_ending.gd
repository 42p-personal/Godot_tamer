## LOOK AT WHAT WAS BUILT — round 17's ending screen, the town pace strip and the frontier
## verdict banner, captured as PNGs and asserted live.
##
## ⚠️ RUN IT WITH A WINDOW, NEVER `--headless`: the dummy renderer returns blank images, so a
## headless run would save black rectangles and "pass" (the trap `_probe_read_shot.gd` warns about).
##
##   P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/_probe_ending.tscn
##
## Writes to user://:  ending_ahead.png · ending_behind.png · ending_outclassed.png · ending_win.png
##
## ── WHAT IT IS FOR ────────────────────────────────────────────────────────────────────────────
## These three screens are the UI half of round 17 (docs/CONVERSION_DIAGNOSIS.md §5 R17-1). They
## display the career-side pace model — `career.gd`'s `dynasty_standing()`, `grade_result()` and
## `frontier_verdict()` — and display NOTHING they compute themselves. So the thing worth asserting
## is not "does a panel appear" but "is the panel wired to that model, and does it move when the
## model moves".
##
## ── LIVENESS CANARIES (signature failure #2: instruments that lie) ────────────────────────────
##   C1  `Pace.snapshot()` reports source "career" and echoes `Career.week` — i.e. the adapter is
##       reading the shipped model, not a UI fallback. FAILS LOUDLY if the career model is absent,
##       which is the point: the screens go quiet, and a quiet screen must not pass silently.
##   C2  moving the WEEK alone flips the standing ahead -> behind and changes the sentence.
##   C3  the pace-setter's rung on the track advances as weeks pass — it is a race, not a label.
##   C4  the grade tier moves across the margin range, >= 5 distinct tiers over the sweep.
##   C5  the frontier banner appears ONLY when `Career.frontier_verdict()` says so, and the
##       outclassed and unlucky states render differently.
## A capture that renders is not evidence the numbers are live; these are.
extends Node

const Pace = preload("res://scripts/ui/ending_ui.gd")
const OUT_DIR := "user://"

var _fail: Array = []


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1500, 950))
	await get_tree().process_frame
	_setup_career()

	# ── C1 ───────────────────────────────────────────────────────────────────────────────────
	Career.week = 90
	var snap: Dictionary = Pace.snapshot()
	if snap.is_empty() or str(snap.get("source", "")) != "career":
		_fail.append("C1 the pace adapter is not reading Career's model (source=%s)"
			% str(snap.get("source", "<empty>")))
	elif int(snap.get("week", -1)) != Career.week:
		_fail.append("C1 snapshot week %d != Career.week %d" % [int(snap.get("week", -1)), Career.week])
	print("canary C1: source=%s  week=%d  league=%s  state=%s  margin=%dw" % [
		str(snap.get("source", "?")), int(snap.get("week", -1)), str(snap.get("leagueName", "?")),
		str(snap.get("state", "?")), int(snap.get("marginWeeks", 0))])

	# ── the town, AHEAD of the pace-setter: Gold reached early ────────────────────────────────
	Career.league_index = 6
	Career.frontier_since_week = 60
	Career.week = 60
	var ahead: Dictionary = Pace.snapshot()
	await _shot_town("ending_ahead.png")

	# ── C2/C3 — the same rung, arrived at far later ───────────────────────────────────────────
	Career.frontier_since_week = 200
	Career.week = 200
	var behind: Dictionary = Pace.snapshot()
	if str(ahead.get("state")) != "ahead" or str(behind.get("state")) != "behind":
		_fail.append("C2 the arrival week alone did not flip the standing (%s -> %s)" % [
			str(ahead.get("state")), str(behind.get("state"))])
	if Pace.pace_line(ahead) == Pace.pace_line(behind):
		_fail.append("C2 the pace sentence did not change")
	print("canary C2: ahead=%s" % Pace.pace_line(ahead))
	print("canary C2: behind=%s" % Pace.pace_line(behind))
	var d_early: int = Pace.par_rung_at_week(60)
	var d_late: int = Pace.par_rung_at_week(200)
	if d_late <= d_early:
		_fail.append("C3 the pace-setter's rung did not advance with the clock (%d -> %d)" % [d_early, d_late])
	print("canary C3: pace-setter rung wk60=%d  wk200=%d" % [d_early, d_late])
	await _shot_town("ending_behind.png")

	# ── C5 — the frontier banner. Silent while "fresh"; loud once Career has the rounds. ──────
	Career.frontier_cups = 1
	Career.frontier_rounds = 3
	Career.frontier_round_wins = 2
	var town_clean := _town()
	await _settle(town_clean)
	if _find_text(town_clean, "outclassed") != null:
		_fail.append("C5 a frontier banner appeared while the verdict was still 'fresh'")
	town_clean.queue_free()
	await get_tree().process_frame

	# the measured outclassed roster: 4 round wins in 120 (DIAGNOSIS §2c), scaled to one rung
	Career.frontier_cups = 9
	Career.frontier_rounds = 27
	Career.frontier_round_wins = 1
	if str(Career.frontier_verdict().get("state", "")) != "outclassed":
		_fail.append("C5 Career did not read this frontier record as outclassed — probe setup is stale")
	var town_oc := _town()
	await _settle(town_oc)
	if _find_text(town_oc, "OUTCLASSED") == null:
		_fail.append("C5 the outclassed banner did NOT appear when Career said outclassed")
	await _shot(town_oc, "ending_outclassed.png")
	town_oc.queue_free()
	await get_tree().process_frame

	# and the opposite advice — winning rounds, losing draws
	Career.frontier_round_wins = 18
	if str(Career.frontier_verdict().get("state", "")) != "unlucky":
		_fail.append("C5 Career did not read the high-round-rate record as unlucky")
	var town_un := _town()
	await _settle(town_un)
	if _find_text(town_un, "unlucky") == null:
		_fail.append("C5 the unlucky banner did NOT appear")
	if _find_text(town_un, "OUTCLASSED") != null:
		_fail.append("C5 the unlucky state rendered the OUTCLASSED wording")
	town_un.queue_free()
	await get_tree().process_frame
	Career.frontier_cups = 0
	Career.frontier_rounds = 0
	Career.frontier_round_wins = 0

	# ── C4 — the grade tier moves with the margin ─────────────────────────────────────────────
	var tiers: Dictionary = {}
	Career.won_game = true
	for w in [180, 250, 330, 400, 420, 470, 540, 620, 760]:
		Career.won_week = w
		tiers[str(Pace.grade_result().get("tier", "?"))] = true
	if tiers.size() < 5:
		_fail.append("C4 only %d distinct grade tiers across the sweep (need >= 5)" % tiers.size())
	print("canary C4: %d distinct tiers: %s" % [tiers.size(), str(tiers.keys())])

	# ── the ending itself ─────────────────────────────────────────────────────────────────────
	Career.league_index = Career.leagues.size() - 1
	for i in range(Career.leagues_won.size()):
		Career.leagues_won[i] = true
	Career.leagues_won[3] = false   # one rung scraped rather than swept, so the tally is not all-11
	Career.won_game = true
	Career.won_week = 337
	Career.week = 337
	Career.remove_meta("ending_seen")
	var end_scene := (load("res://scenes/ending.tscn") as PackedScene).instantiate()
	add_child(end_scene)
	await _settle(end_scene)
	await _shot(end_scene, "ending_win.png")
	if _find_text(end_scene, str(Pace.grade_result().get("tier", "@@"))) == null:
		_fail.append("the ending screen did not render Career's grade tier")
	if not Career.has_meta("ending_seen"):
		_fail.append("the ending did not mark itself seen — the town would pin the player here")

	print("capture: wrote %s" % ProjectSettings.globalize_path(OUT_DIR))
	# ⚠️ `get_tree().quit()` REQUESTS a quit at the end of the frame — it does NOT return. Without
	# the `return` this fell straight through to `quit(1)` and the probe exited NON-ZERO while
	# printing PASS. An instrument that lied, caught by diffing the exit code against a probe
	# known to pass.
	if _fail.is_empty():
		print("PROBE ENDING: PASS")
		get_tree().quit(0)
		return
	for f in _fail:
		printerr("PROBE ENDING FAIL: %s" % f)
	get_tree().quit(1)


func _setup_career() -> void:
	Career.reset_new_game()
	Roster.reset_to_empty()
	Career.barn_capacity = 8
	for i in range(5):
		Roster.monsters.append(GameData.make_monster(Art.ROSTER[i % Art.ROSTER.size()], 0.55))
	for m in Roster.monsters:
		m.age_weeks = 5 * 48
	Roster.monsters[4].retired = true


func _town() -> Node:
	var t := (load("res://scenes/town.tscn") as PackedScene).instantiate()
	add_child(t)
	return t


func _shot_town(name: String) -> void:
	var t := _town()
	await _settle(t)
	await _shot(t, name)
	t.queue_free()
	await get_tree().process_frame


func _settle(_n: Node) -> void:
	for _i in 8:
		await get_tree().process_frame


func _shot(_n: Node, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + name)
	print("capture: %s  %dx%d" % [name, img.get_width(), img.get_height()])


## Walks the built tree looking for a Label whose text contains `needle` — the screens are built
## entirely in code, so this is the only honest way to ask whether a block actually rendered.
func _find_text(root: Node, needle: String) -> Label:
	if root is Label and (root as Label).text.contains(needle):
		return root
	for c in root.get_children():
		var found := _find_text(c, needle)
		if found != null:
			return found
	return null
