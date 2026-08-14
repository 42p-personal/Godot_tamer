## PERF TRIPWIRE — the standing watch-scene performance instrument (task #36, waited 20 rounds).
##
## Drives the REAL production watch path (same boot as `_probe_watch.gd`: watch.gd rosters ->
## tactics.gd commit -> arena3d.tscn) at 1920x1200 and reports MEDIAN frame time, draw calls and
## node count. Median, not mean — round 13 measured that a single PNG write poisons the mean for
## multiple frames, so the mean describes the instrument; the median is the frame the player gets.
## The screenshot is therefore captured AFTER the sampling window closes.
##
## ⚠️ RUN WINDOWED, NEVER --headless. The dummy renderer returns 0 draw calls and blank frames —
## a headless run "passes" while measuring nothing (the class of silent success this project
## keeps recording). The probe refuses to report if its own liveness canaries fail:
##   · draw calls must be nonzero and frame times must VARY (a dead instrument reads constant);
##   · the crowd must actually be seated (a probe that measured an empty house once reported the
##     144fps of a scene it thought it had fixed).
##
##   P:/Godot_v4.7.1-stable_win64.exe --path monster-tamer res://scenes/_probe_perf.tscn -- ab
##
## Modes: `ab` (default — batched crowd, then round-13 rigged crowd via spectators.force_legacy,
## same process, same fight setup, delta reported) · `new` · `legacy`.
## Exit code: 0 iff the NEW path meets budget — median >= 60fps AND mean draw calls < 600 —
## with all canaries green. Legacy-only runs judge nothing (it is the baseline arm).
extends Node

const SETTLE_S := 6.0     # past the 1.5s opening hold, well into the scrum
const SAMPLE_S := 8.0
const FPS_FLOOR := 60.0
const DRAW_CEIL := 600.0

var _out: Array = []


func _ready() -> void:
	get_window().size = Vector2i(1920, 1200)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "ab"
	_line("")
	_line("═══ PERF PROBE — mode=%s · 1920x1200 · %s ═══" % [mode, Time.get_datetime_string_from_system()])
	var res_new: Dictionary = {}
	var res_leg: Dictionary = {}
	if mode == "ab" or mode == "new":
		res_new = await _pass(false)
	if mode == "ab" or mode == "legacy":
		res_leg = await _pass(true)
	var green := true
	if not res_new.is_empty():
		_report("NEW (batched crowd)", res_new)
		if not bool(res_new["alive"]):
			_line("  ✗ CANARY FAILED — measurement not trusted")
			green = false
		if float(res_new["fps_median"]) < FPS_FLOOR:
			_line("  ✗ median %.1f fps < %.0f floor" % [res_new["fps_median"], FPS_FLOOR])
			green = false
		if float(res_new["draws_mean"]) >= DRAW_CEIL:
			_line("  ✗ mean draw calls %.0f >= %.0f ceiling" % [res_new["draws_mean"], DRAW_CEIL])
			green = false
	if not res_leg.is_empty():
		_report("LEGACY (round-13 rigged crowd)", res_leg)
	if not res_new.is_empty() and not res_leg.is_empty():
		_line("")
		_line("── A/B DELTA (new vs legacy, same process, same fight boot) ──")
		_line("  fps median   %.1f -> %.1f  (x%.2f)" % [res_leg["fps_median"], res_new["fps_median"],
			float(res_new["fps_median"]) / maxf(0.001, float(res_leg["fps_median"]))])
		_line("  draw calls   %.0f -> %.0f" % [res_leg["draws_mean"], res_new["draws_mean"]])
		_line("  nodes        %d -> %d" % [int(res_leg["nodes"]), int(res_new["nodes"])])
		_line("  crowd bodies %d -> %d  (must match — same seed seats the same house)" % [
			int(res_leg["bodies"]), int(res_new["bodies"])])
		if int(res_leg["bodies"]) != int(res_new["bodies"]):
			_line("  ✗ BODY COUNT DIVERGED between paths — the A/B is not comparing the same crowd")
			green = false
	if mode == "legacy":
		_line("")
		_line("(legacy-only run: baseline arm, no verdict)")
		_dump()
		get_tree().quit(0)
		return
	_line("")
	_line("VERDICT: %s" % ("GREEN — 60fps at budget, canaries live" if green else "RED"))
	_dump()
	get_tree().quit(0 if green else 1)


func _pass(legacy: bool) -> Dictionary:
	var tag := "legacy" if legacy else "new"
	var Spec = load("res://scripts/ui/spectators.gd")
	Spec.force_legacy = legacy
	_setup_fight()
	var arena: Node = (load("res://scenes/arena3d.tscn") as PackedScene).instantiate()
	add_child(arena)
	var ok := false
	for i in range(1800):
		await get_tree().process_frame
		var nodes_arr: Array = arena.get("nodes")
		if nodes_arr != null and not nodes_arr.is_empty() and not (arena.get("frames") as Array).is_empty():
			ok = true
			break
	if not ok:
		_line("FAIL[%s]: arena never produced units + frames" % tag)
		arena.queue_free()
		Spec.force_legacy = false
		return {"alive": false, "fps_median": 0.0, "draws_mean": 0.0, "nodes": 0, "bodies": 0}
	# settle on REAL time, not frame count — this loop runs uncapped on fast hardware and
	# capped at ~31fps on the legacy arm; frames are not seconds on either.
	var t0 := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - t0) / 1e6 < SETTLE_S:
		await get_tree().process_frame
	# sample: frame dt measured OURSELVES (usec delta between process frames) — round 13 found
	# Performance.TIME_PROCESS reporting 151ms inside a 35ms frame, so it is not quoted.
	var dts: Array = []
	var draws: Array = []
	var last := Time.get_ticks_usec()
	var s0 := last
	while float(Time.get_ticks_usec() - s0) / 1e6 < SAMPLE_S:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		dts.append(float(now - last) / 1000.0)   # ms
		last = now
		draws.append(float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	var node_ct := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	# ── CANARIES ──────────────────────────────────────────────────────────────────────────────
	var bodies := 0
	var sp = arena.get("spectators")
	if sp != null:
		bodies = (sp.get("_spectators") as Array).size() if legacy else (sp.get("_crowd") as Array).size()
	var dt_min := 1e18
	var dt_max := 0.0
	for d in dts:
		dt_min = minf(dt_min, float(d))
		dt_max = maxf(dt_max, float(d))
	var alive := dts.size() > 30 and _mean(draws) > 0.0 and dt_max > dt_min and bodies > 0
	if bodies == 0:
		_line("CANARY[%s]: crowd EMPTY — a fast empty house is not a fix" % tag)
	if _mean(draws) <= 0.0:
		_line("CANARY[%s]: zero draw calls — headless/blank render, nothing measured" % tag)
	# screenshot AFTER sampling (the write stalls frames). Sampling runs on the DEFAULT camera —
	# the shot the player actually gets — but the capture switches to the ARENA-wide cam first:
	# the ACTION cam frames the scrum and the stands are OFF-FRAME, so a capture in that mode
	# cannot verify the crowd it just measured (found on this probe's first run).
	# REAL-time settle for the cam lerp, not frames — 20 frames is 0.14s on the fast arm and
	# 0.9s on the slow one, which produced two captures at different zooms on the first run.
	arena.set("_cam_mode", 2)
	var c0 := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - c0) / 1e6 < 2.0:
		await get_tree().process_frame
	var shot := "user://perf_%s_%s.png" % [tag, Time.get_datetime_string_from_system().replace(":", "-")]
	var img1: Image = get_viewport().get_texture().get_image()
	img1.save_png(shot)
	# ── MOTION CANARY ─────────────────────────────────────────────────────────────────────────
	# A batched crowd whose _process died renders a FROZEN house with no error — same fps, same
	# draws, silent. So: two grabs 1s apart, diffed over the LEFT stand band (x 0-120, y 400-900
	# at 1920x1200 — stands only: no HUD, no nameplates, no fight). Zero delta = dead crowd.
	var c1 := Time.get_ticks_usec()
	while float(Time.get_ticks_usec() - c1) / 1e6 < 1.0:
		await get_tree().process_frame
	var img2: Image = get_viewport().get_texture().get_image()
	var moved := 0
	for y in range(400, 900, 4):
		for x in range(0, 120, 4):
			var d: Color = img1.get_pixel(x, y) - img2.get_pixel(x, y)
			if absf(d.r) + absf(d.g) + absf(d.b) > 0.02:
				moved += 1
	if moved == 0:
		_line("CANARY[%s]: crowd band pixel-identical across 1s — the house is FROZEN" % tag)
	dts.sort()
	var med: float = float(dts[dts.size() / 2]) if not dts.is_empty() else 0.0
	var p95: float = float(dts[mini(dts.size() - 1, int(float(dts.size()) * 0.95))]) if not dts.is_empty() else 0.0
	var out := {
		"alive": alive and moved > 0,
		"moved_px": moved,
		"fps_median": 1000.0 / maxf(0.001, med),
		"med_ms": med,
		"p95_ms": p95,
		"mean_ms": _mean(dts),
		"draws_mean": _mean(draws),
		"draws_max": _maxa(draws),
		"nodes": node_ct,
		"bodies": bodies,
		"frames": dts.size(),
		"shot": ProjectSettings.globalize_path(shot),
	}
	arena.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	Spec.force_legacy = false
	return out


## Same fight the player watches — reconstructed via watch.gd's OWN rosters/roles so the
## instrument cannot drift from the production composition (`_probe_watch.gd`'s rule).
func _setup_fight() -> void:
	var W = load("res://scripts/watch.gd")
	var a: Array = []
	var b: Array = []
	for s in W.ROSTER_A:
		a.append(GameData.make_monster(s, 0.35))
	for s in W.ROSTER_B:
		b.append(GameData.make_monster(s, 0.35))
	for role in W.ROLES_A:
		W._cast_role(a[int(role["i"])], role)
	for role in W.ROLES_B:
		W._cast_role(b[int(role["i"])], role)
	var plan_a := {"targetPriority": "manmark", "markedUnit": b[2],
		"positionalIntent": "push", "temperament": "balanced", "formation": "tight"}
	var plan_b := {"targetPriority": "tanks", "positionalIntent": "dive",
		"temperament": "aggressive", "formation": "loose"}
	var T = load("res://scripts/tactics.gd")
	T.committed = {"teamA": a, "teamB": b, "planA": plan_a, "planB": plan_b,
		"orders": {}, "ordersA": {}, "ordersB": {}, "layout": "four_pillar"}


func _report(label: String, r: Dictionary) -> void:
	_line("")
	_line("── %s ──" % label)
	_line("  frame time   median %.2f ms (%.1f fps) · mean %.2f ms · p95 %.2f ms · n=%d" % [
		r["med_ms"], r["fps_median"], r["mean_ms"], r["p95_ms"], int(r["frames"])])
	_line("  draw calls   mean %.0f · max %.0f" % [r["draws_mean"], r["draws_max"]])
	_line("  nodes        %d" % int(r["nodes"]))
	_line("  crowd bodies %d · moving stand pixels %d (motion canary)" % [int(r["bodies"]), int(r.get("moved_px", -1))])
	_line("  capture      %s" % str(r["shot"]))


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for x in a:
		s += float(x)
	return s / float(a.size())


func _maxa(a: Array) -> float:
	var m := 0.0
	for x in a:
		m = maxf(m, float(x))
	return m


func _line(s: String) -> void:
	_out.append(s)


func _dump() -> void:
	print("\n".join(_out))
