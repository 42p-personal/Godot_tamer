## CAPTURE THE TWO BOOKENDS — look at the screens, do not only measure them.
## ⚠️ RUN IT WITH A WINDOW, NEVER `--headless`: the dummy renderer returns blank images, so a
## headless run would save black rectangles and "pass".
##   P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/_probe_read_shot.tscn
##
## Writes user://read_tactics.png and user://read_report.png — the COMMIT screen with its claims
## and the OBSERVE screen with its verdict, from one real fight, so the two can be read side by
## side and checked for the thing this stream is for: do they say the same thing in the same
## words?
extends Node

const TacticsScript = preload("res://scripts/tactics.gd")
const ReportScript = preload("res://scripts/ui/report_ui.gd")
const OUT_DIR := "user://"

var _team_a: Array = []
var _team_b: Array = []


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	await get_tree().process_frame
	_setup()

	# ── 1. THE COMMIT SCREEN, with the read panel populated from real orders. Driven through the
	# screen's own controls-facing state rather than poked: set the plan the way a player would
	# leave it, then let `_refresh_read()` regenerate the panel exactly as it does on a click.
	var tac := (load("res://scenes/tactics.tscn") as PackedScene).instantiate()
	add_child(tac)
	for _i in 240:
		await get_tree().process_frame
		if not (tac.get("team_a") as Array).is_empty():
			break
	var plan: Dictionary = tac.get("team_a_plan")
	plan["targetPriority"] = "casters"
	plan["formation"] = "tight"
	var orders: Dictionary = tac.get("orders_a")
	var first_a = (tac.get("team_a") as Array)[0]
	(orders[first_a] as Dictionary)["temperament"] = "cautious"
	tac.call("_refresh_read")
	await get_tree().process_frame
	await _shot("read_tactics.png")

	var claims: Array = ReportScript.build_read(plan, orders, tac.get("team_a"), tac.get("team_b"))
	var gp: String = str(tac.get("gameplan_id"))
	_team_a = tac.get("team_a")
	_team_b = tac.get("team_b")
	tac.queue_free()
	await get_tree().process_frame

	# ── 2. A REAL FIGHT through the real battle screen, so the report grades a real frame stream.
	for m in _team_a + _team_b:
		m.reset_for_battle()
	TacticsScript.commit(plan, TacticsScript.team_plan_for_gameplan(gp, _team_a), orders,
		TacticsScript.orders_for_gameplan(gp, _team_b), {}, {}, _team_a, _team_b)
	TacticsScript.committed["read"] = {"claims": claims, "gameplan": gp}
	var arena = load("res://scenes/arena3d.tscn").instantiate()
	add_child(arena)
	for _i in 6000:
		await get_tree().process_frame
		if not (arena.get("result") as Dictionary).is_empty():
			break
	var res: Dictionary = arena.get("result")
	arena.queue_free()
	await get_tree().process_frame

	# ── 3. THE OBSERVE SCREEN.
	ReportScript.hand_off(res, _team_a, _team_b)
	var rep := (load("res://scenes/report.tscn") as PackedScene).instantiate()
	add_child(rep)
	for _i in 120:
		await get_tree().process_frame
	await _shot("read_report.png")
	# ⚠️ PROVE THE SOURCE, DO NOT ASSUME IT. The tree's own decision log and the frame-diff
	# fallback produce similar-looking lines, so a capture cannot tell them apart by eye — which is
	# exactly how "wired" gets recorded for something that is not. Ask the screen which one ran.
	var dec: Dictionary = rep.call("_decision_events_by_id", res.get("log", []), res.get("frames", []),
		res, _team_a + _team_b, _team_a.size())
	print("capture: decision-log source = %s  (units with events: %d)" % [
		str(dec.get("source", "?")), (dec.get("events", {}) as Dictionary).size()])
	print("capture: result carries decisionLogs = %s (%d units)" % [
		str(res.has("decisionLogs")), (res.get("decisionLogs", {}) as Dictionary).size()])
	print("capture: wrote %s" % ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit(0)


func _setup() -> void:
	Career.reset_new_game()
	Roster.reset_to_empty()
	var idx := 0
	for i in range(Career.leagues.size()):
		if Career.team_size_for_league(i) >= 5:
			idx = i
			break
	Career.league_index = idx
	## ⚠️ THE CLOCK HAS TO BE ON THE CLOCK. Round 17 put a pace line on this screen
	## (`ui/report_ui.gd:_banner`), and a capture taken at week 1 cannot show whether it says
	## anything useful mid-career — a fresh career is exactly the state where "level" is the
	## trivially correct answer. `-- --week 200` places the capture where the question is live.
	var wk: int = 0
	var argv: Array = OS.get_cmdline_user_args()
	var wi: int = argv.find("--week")
	if wi >= 0 and wi + 1 < argv.size():
		wk = int(argv[wi + 1])
	if wk > 0:
		Career.week = wk
		Career.frontier_since_week = maxi(0, wk - 40)
	CupRun.start(idx, 3)
	CupRun.current_round = 1
	for i2 in range(5):
		Roster.monsters.append(GameData.make_monster(Art.ROSTER[i2 % Art.ROSTER.size()], 0.5))


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + name)
	print("capture: %s  %dx%d" % [name, img.get_width(), img.get_height()])
