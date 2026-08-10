## IS THE CLOCK FELT? — round 17's acceptance bar, checked by LOOKING.
##
## ⚠️ RUN WITH A WINDOW, NEVER `--headless`: the dummy renderer saves black rectangles and the
## probe would "pass" on four blank images.
##   P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/_probe_clock.tscn -- --week 200
##
## The round's stated bar is "can a player tell at week 200 whether they are doing well, without
## opening a menu?". `_probe_ending.gd` answers it for the Town hub and `_probe_read_shot.gd` for
## the battle report; this one covers the two screens where the WEEKS ARE ACTUALLY SPENT — the
## Stable and Training — because that is where the cost of a week has to be legible if pace is
## going to change how anyone plays.
##
## LIVENESS CANARIES (a capture that renders is not evidence the number is live):
##   K1  every screen under test carries a label whose text is EXACTLY `Pace.pace_line()` —
##       found by walking the built tree, not by trusting the call site.
##   K2  moving the WEEK alone changes that text on every screen (a label is not a constant).
##   K3  the sentence names the pace-setter, so it is a comparison rather than a status readout.
extends Node

const Pace = preload("res://scripts/ui/ending_ui.gd")
const OUT_DIR := "user://"

var _fail: Array = []


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1500, 950))
	await get_tree().process_frame

	var week: int = 200
	var argv: Array = OS.get_cmdline_user_args()
	var wi: int = argv.find("--week")
	if wi >= 0 and wi + 1 < argv.size():
		week = int(argv[wi + 1])

	_setup(week)
	var want_late: String = Pace.pace_line(Pace.snapshot())
	print("expected line @wk%d: %s" % [week, want_late])
	if not ("Varra" in want_late):
		_fail.append("K3 the pace sentence does not name the pace-setter — it is a status readout, not a race")

	for spec in [["res://scenes/stable.tscn", "clock_stable.png"],
			["res://scenes/training.tscn", "clock_training.png"]]:
		await _check_screen(str(spec[0]), str(spec[1]), want_late, week)

	print("")
	if _fail.is_empty():
		print("PROBE CLOCK: PASS — the pace line is live on the Stable and on Training")
		get_tree().quit(0)
		return
	for x in _fail:
		print("  FAIL  %s" % x)
	print("PROBE CLOCK: FAIL (%d)" % _fail.size())
	get_tree().quit(1)
	return


## Build the screen for real, find the pace line in its tree, then move the clock and rebuild.
func _check_screen(path: String, shot: String, want_late: String, week: int) -> void:
	var name: String = path.get_file()
	_set_week(week)
	var scene := (load(path) as PackedScene).instantiate()
	add_child(scene)
	for _i in 30:
		await get_tree().process_frame
	var found_late: bool = _tree_has_text(scene, want_late)
	if not found_late:
		_fail.append("K1 %s does not display Career's pace line (looked for the exact sentence)" % name)
	await _shot(shot)
	scene.queue_free()
	await get_tree().process_frame

	# K2 — the SAME screen, an earlier clock. The text must move.
	_set_week(maxi(8, week / 4))
	var want_early: String = Pace.pace_line(Pace.snapshot())
	var scene2 := (load(path) as PackedScene).instantiate()
	add_child(scene2)
	for _i in 30:
		await get_tree().process_frame
	var moved: bool = want_early != want_late and _tree_has_text(scene2, want_early) \
		and not _tree_has_text(scene2, want_late)
	if not moved:
		_fail.append("K2 %s's pace line did not move when the clock did — it is a constant, not a reading" % name)
	print("   %s %s  late=%s early=%s" % ["OK  " if (found_late and moved) else "FAIL",
		name, str(found_late), str(moved)])
	scene2.queue_free()
	await get_tree().process_frame


func _set_week(w: int) -> void:
	Career.week = w
	Career.frontier_since_week = maxi(0, w - 30)


func _tree_has_text(n: Node, text: String) -> bool:
	if n is Label and (n as Label).text == text:
		return true
	for c in n.get_children():
		if _tree_has_text(c, text):
			return true
	return false


func _setup(week: int) -> void:
	Career.reset_new_game()
	Roster.reset_to_empty()
	Career.league_index = 6
	for i in range(5):
		Roster.monsters.append(GameData.make_monster(Art.ROSTER[i % Art.ROSTER.size()], 0.55))
	Roster.selected_index = 0
	_set_week(week)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + name)
	print("capture: %s  %dx%d" % [name, img.get_width(), img.get_height()])
