## PERFORMANCE PROBE — measures the spatial sim and (optionally) the arena3d renderer.
## THROWAWAY-STYLE INSTRUMENT owned by performance-analyst. Not part of the contract suite.
##
## ⚠️ Autoloads exist under `--script` (the engine's normal boot still creates Art/GameData/
## Career/Roster/SaveGame/McpInteractionServer and adds them to /root) BUT a script-level
## `const X = preload(...)` of anything that bare-references an autoload (monster_instance.gd
## -> `GameData.class_lines`) compiles too early — before those autoloads are registered as
## globals — and fails with "Identifier not found". Fix used throughout this file: never
## top-level-preload monster_instance.gd/spatial_sim.gd; `load()` them from inside a function,
## deferred to frame 2 or later, and reach other autoloads via `root.get_node("/root/Name")`
## (a runtime path lookup, not a compile-time bare identifier) rather than by bare name.
##
## Usage:
##   SIM-ONLY, headless:
##     Godot.exe --headless --path monster-tamer --script res://scripts/_perf_probe.gd -- sim
##   FULL (windowed, needs a real display; draw calls/VRAM are unavailable under --headless):
##     Godot.exe --path monster-tamer --script res://scripts/_perf_probe.gd -- render
extends SceneTree

const Sp = preload("res://scripts/spatial.gd")

var _frame := 0
var _mode := "sim"
var _game_data = null
var _render_arena = null
var _render_frame := 0
var _render_elapsed := 0.0      # REAL seconds since the arena scene was instantiated — frame
                                 # COUNT is not a reliable proxy for this because this custom
                                 # SceneTree main loop runs uncapped (no vsync wait observed:
                                 # ~136fps measured on an RTX 5080), so a fixed frame count landed
                                 # inside the opening hold, not mid-fight, on the first attempt.
const RENDER_SETTLE_SECONDS := 10.0   # real seconds — past the 1.5s opening hold and well into
                                       # a typical fight (sim durations measured at 14-40s)
const RENDER_SAMPLE_SECONDS := 3.0
var _last_tick_usec := 0
var _sampling := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_mode = args[0]
	print("[_perf_probe] mode=%s" % _mode)


func _process(_delta: float) -> bool:
	_frame += 1
	if _mode == "sim":
		if _frame == 2:
			_run_sim_bench()
			quit(0)
		return false

	# render mode
	if _frame == 2:
		_boot_render_scene()
		_last_tick_usec = Time.get_ticks_usec()
	if _render_arena != null:
		var now_usec := Time.get_ticks_usec()
		var frame_ms: float = float(now_usec - _last_tick_usec) / 1000.0
		_last_tick_usec = now_usec
		_render_frame += 1
		_render_elapsed += _delta
		if not _sampling and _render_elapsed >= RENDER_SETTLE_SECONDS:
			_sampling = true
			print("[_perf_probe] settle done at frame %d (%.2fs real) — sampling for %.1fs" % [
				_render_frame, _render_elapsed, RENDER_SAMPLE_SECONDS])
		elif _sampling and _render_elapsed < RENDER_SETTLE_SECONDS + RENDER_SAMPLE_SECONDS:
			_sample_frame(frame_ms)
		elif _sampling:
			_dump_render_stats()
			quit(0)
	return false


# ═══════════════════════════════════════════════════════════════════════════
# SIM BENCH — headless-safe. Builds monsters via the real GameData autoload
# (reached by /root path lookup, not bare identifier) and times SpatialSim.run().
# ═══════════════════════════════════════════════════════════════════════════

func _run_sim_bench() -> void:
	var gd = root.get_node_or_null("/root/GameData")
	if gd == null:
		print("FATAL: /root/GameData not present even after a settle frame")
		quit(1)
		return
	_game_data = gd

	var SpatialSimScript = load("res://scripts/spatial_sim.gd")
	var ArenaLayoutScript = load("res://scripts/arena_layout.gd")

	print("")
	print("=== SIM BENCH (headless, 10 Hz fixed step) ===")
	for team_size in [1, 3, 5]:
		var samples_ms: Array = []
		var samples_ticks: Array = []
		var samples_duration: Array = []
		var reps := 8
		for r in range(reps):
			var rng := RandomNumberGenerator.new()
			rng.seed = 1000 + r
			var team_a := _build_team(team_size, rng)
			var team_b := _build_team(team_size, rng)
			var layout: Dictionary = ArenaLayoutScript.generate(team_size, "Platinum", rng)
			var obstacles: Array = layout.get("obstacles", [])

			var t0 := Time.get_ticks_usec()
			var sim = SpatialSimScript.new(team_a, team_b, 5000 + r, {"formation": "tight"}, {"formation": "tight"}, {}, obstacles)
			var result: Dictionary = sim.run()
			var t1 := Time.get_ticks_usec()

			var wall_ms: float = float(t1 - t0) / 1000.0
			var ticks: int = result["frames"].size()
			samples_ms.append(wall_ms)
			samples_ticks.append(ticks)
			samples_duration.append(float(result["duration"]))

		var mean_ms := _mean(samples_ms)
		var mean_ticks := _mean(samples_ticks)
		var mean_dur := _mean(samples_duration)
		var max_ms := _max(samples_ms)
		print("%dv%d: wall=%.2fms (max %.2fms over %d reps) | sim-ticks=%.0f | sim-duration=%.1fs | wall/tick=%.4fms | ground=%s"
			% [team_size, team_size, mean_ms, max_ms, reps, mean_ticks, mean_dur,
			   mean_ms / maxf(1.0, mean_ticks), str(Sp.ground_size(team_size))])

	# Frame-stream memory estimate for a worst-case-length fight.
	print("")
	print("=== FRAME-STREAM SHAPE (5v5, one long rep) ===")
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 42
	var ta := _build_team(5, rng2)
	var tb := _build_team(5, rng2)
	var layout2: Dictionary = ArenaLayoutScript.generate(5, "Platinum", rng2)
	var sim2 = SpatialSimScript.new(ta, tb, 42, {"formation": "loose"}, {"formation": "loose"}, {}, layout2.get("obstacles", []))
	var t0b := Time.get_ticks_usec()
	var result2: Dictionary = sim2.run()
	var t1b := Time.get_ticks_usec()
	var frames: Array = result2["frames"]
	print("duration=%.1fs frames=%d wall=%.2fms" % [result2["duration"], frames.size(), float(t1b - t0b) / 1000.0])
	if not frames.is_empty():
		var one_frame_bytes := _estimate_frame_bytes(frames[frames.size() / 2])
		print("packed-payload estimate: %d bytes/frame (mid-fight, 10 units) -> ~%.1f KB for this fight" % [
			one_frame_bytes, float(one_frame_bytes * frames.size()) / 1024.0])
	print("event_log entries=%d" % result2["log"].size())

	# ── REAL heap measurement, not a packed-payload guess. GDScript Dictionaries carry hash-table
	# overhead per instance that a byte-count of the payload does not capture. Run a batch of 5v5
	# fights, KEEP every frame array alive (nothing freed), and read the actual static memory delta.
	print("")
	print("=== FRAME-STREAM REAL MEMORY (batch of 5v5 fights, all frame arrays retained) ===")
	var mem_before := Performance.get_monitor(Performance.MEMORY_STATIC)
	var kept: Array = []
	var total_frames := 0
	var max_frames_seen := 0
	var reps3 := 15
	for r in range(reps3):
		var rngm := RandomNumberGenerator.new()
		rngm.seed = 7000 + r
		var tam := _build_team(5, rngm)
		var tbm := _build_team(5, rngm)
		var laym: Dictionary = ArenaLayoutScript.generate(5, "Platinum", rngm)
		var simm = SpatialSimScript.new(tam, tbm, 7000 + r, {"formation": "loose"}, {"formation": "loose"}, {}, laym.get("obstacles", []))
		var resm: Dictionary = simm.run()
		var fr: Array = resm["frames"]
		kept.append(fr)
		total_frames += fr.size()
		max_frames_seen = maxi(max_frames_seen, fr.size())
	var mem_after := Performance.get_monitor(Performance.MEMORY_STATIC)
	var delta_bytes: float = mem_after - mem_before
	print("reps=%d total_frames=%d longest_fight=%d ticks (%.1fs)" % [reps3, total_frames, max_frames_seen, float(max_frames_seen) / 10.0])
	print("MEMORY_STATIC before=%.2fMB after=%.2fMB delta=%.2fMB" % [
		mem_before / 1048576.0, mem_after / 1048576.0, delta_bytes / 1048576.0])
	if total_frames > 0:
		var real_bytes_per_frame: float = delta_bytes / float(total_frames)
		print("REAL bytes/frame (10 units, incl. Dictionary/Array overhead) = %.0f" % real_bytes_per_frame)
		print("extrapolated to a 180s (1800-tick) worst-case 5v5 fight: %.2f MB" % (real_bytes_per_frame * 1800.0 / 1048576.0))
	kept.clear()


func _build_team(count: int, rng: RandomNumberGenerator) -> Array:
	var roster := ["kongrath", "aegisox", "grivvel", "corvaan", "larkessa", "strixil",
		"scarabrute", "mantevoke", "crocmaw", "pyraxon", "tenebrae", "titanrex"]
	var out: Array = []
	for i in range(count):
		var sid: String = roster[i % roster.size()]
		var mi = _game_data.make_monster(sid, 0.5, rng)
		out.append(mi)
	return out


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for x in a:
		s += float(x)
	return s / float(a.size())


func _max(a: Array) -> float:
	var m := 0.0
	for x in a:
		m = maxf(m, float(x))
	return m


## Rough serialized-size estimate for one frame record (Vector2s ~ 2 floats @ 4 bytes as stored
## in a Dictionary/Variant, plus Dictionary/Array overhead which dwarfs the payload in GDScript —
## this is a byte-count of the PACKED DATA, not the actual heap footprint of nested Dictionaries,
## which is stated explicitly in the report.
func _estimate_frame_bytes(frame: Dictionary) -> int:
	var units: Array = frame.get("units", [])
	var per_unit := 0
	per_unit += 4   # id (int)
	per_unit += 8   # pos (Vector2)
	per_unit += 8   # facing (Vector2)
	per_unit += 4   # hp (float)
	per_unit += 4   # mp (float)
	per_unit += 1   # alive (bool)
	per_unit += 12  # state (String, ~"advance")
	per_unit += 4   # targetId
	per_unit += 16  # statuses (Array, usually 0-2 entries ~8 bytes each)
	return units.size() * per_unit + 8  # + t (float)


# ═══════════════════════════════════════════════════════════════════════════
# RENDER BENCH — windowed only. Boots the real arena3d.tscn scene (autoloads are
# already live by frame 2 under normal --script boot) and samples Performance.
# ═══════════════════════════════════════════════════════════════════════════

func _boot_render_scene() -> void:
	var scene = load("res://scenes/arena3d.tscn")
	if scene == null:
		print("FATAL: could not load arena3d.tscn")
		quit(1)
		return
	var inst = scene.instantiate()
	root.add_child(inst)
	current_scene = inst
	_render_arena = inst
	print("[_perf_probe] arena3d instantiated, settling for %.1f real seconds before sampling" % RENDER_SETTLE_SECONDS)


var _sample_frame_ms: Array = []
var _sample_draw_calls: Array = []
var _sample_primitives: Array = []


## `frame_ms` is measured OURSELVES (Time.get_ticks_usec delta between successive _process
## calls), not read from Performance.TIME_PROCESS/TIME_FPS — those two monitors were observed to
## return a single unchanging value across an entire 30-frame sampling window on this custom
## SceneTree main loop (min==mean==max exactly), i.e. they are not refreshed per-call here, and
## trusting them silently would have reported a false constant. draw_calls/primitives DID vary
## frame to frame and are trusted as-is.
func _sample_frame(frame_ms: float) -> void:
	_sample_frame_ms.append(frame_ms)
	_sample_draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_sample_primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))


func _dump_render_stats() -> void:
	var lines := []
	lines.append("=== RENDER BENCH (windowed, arena3d.tscn, sampled %.1fs after a %.1fs settle) ===" % [RENDER_SAMPLE_SECONDS, RENDER_SETTLE_SECONDS])
	lines.append("frame_ms mean=%.3f max=%.3f min=%.3f (n=%d samples) -> mean fps=%.1f" % [
		_mean(_sample_frame_ms), _max(_sample_frame_ms), _min(_sample_frame_ms), _sample_frame_ms.size(),
		1000.0 / maxf(0.001, _mean(_sample_frame_ms))])
	lines.append("draw_calls mean=%.1f max=%.1f" % [_mean(_sample_draw_calls), _max(_sample_draw_calls)])
	lines.append("primitives mean=%.0f max=%.0f" % [_mean(_sample_primitives), _max(_sample_primitives)])
	lines.append("video_mem_mb=%.2f" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0))
	lines.append("texture_mem_mb=%.2f" % (Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0))
	lines.append("buffer_mem_mb=%.2f" % (Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0))
	lines.append("static_mem_mb=%.2f" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0))
	lines.append("object_count=%d node_count=%d" % [
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	var out := "\n".join(lines)
	print(out)
	var f := FileAccess.open("C:/Users/P/AppData/Local/Temp/claude/G--p42-uk-Monster-Tamer/fdaca410-f09e-4030-a42c-1169a1f50bc9/scratchpad/perf_render.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(out)
		f.close()


func _min(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var m: float = a[0]
	for x in a:
		m = minf(m, float(x))
	return m
