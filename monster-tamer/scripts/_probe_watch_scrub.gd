## SCRUB PROBE — does going BACK actually work, and does it lie?
##
## ⚠️ `_probe_watch.gd` (the watch audit) plays a fight FORWARDS ONCE and cannot see any of this.
## Rewind is the one control added this round that has irreversible state behind it: the text log
## only ever grows, a death topples a body with a tween and hides its plate, and the director
## remembers who was hit and who fell. A seek that leaves any of those out of step produces the
## worst possible failure for a legibility round — a replay that shows a corpse standing at 80%
## HP, or fires 130 damage numbers in a single frame.
##
## It runs the REAL production path (the same arena scene `watch.gd` opens) and checks, at three
## points in the fight, that after a jump the screen agrees with the frame it jumped to:
##   1. the toppled set matches the frame's dead set
##   2. the log has exactly the events up to that time and no more
##   3. the squad HUD's pips match the frame
##   4. no floating damage numbers were spawned by the catch-up (the `_fx_muted` contract)
##
## RUN IT WITH A WINDOW, NOT `--headless` — same reason as the watch audit: it needs a camera and
## a viewport, and the dummy renderer would let a broken frame pass.
##   P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/_probe_watch_scrub.tscn
extends Node

var _arena: Node = null
var _out: Array = []
var _fail := false


func _ready() -> void:
	var W = load("res://scripts/watch.gd")
	var a: Array = []
	var b: Array = []
	for s in W.ROSTER_A:
		a.append(GameData.make_monster(s, 0.35))
	for s in W.ROSTER_B:
		b.append(GameData.make_monster(s, 0.35))
	var T = load("res://scripts/tactics.gd")
	T.committed = {"teamA": a, "teamB": b, "planA": {}, "planB": {}, "orders": {},
		"layout": "four_pillar"}

	_arena = (load("res://scenes/arena3d.tscn") as PackedScene).instantiate()
	add_child(_arena)
	var ok := false
	for _i in range(1200):
		await get_tree().process_frame
		var nodes: Array = _arena.get("nodes")
		if nodes != null and not nodes.is_empty() and not (_arena.get("frames") as Array).is_empty():
			ok = true
			break
	if not ok:
		_line("FAIL: the arena never produced units + frames")
		_done(1)
		return

	var frames: Array = _arena.get("frames")
	var dur: float = float(frames.size() - 1) * 0.1
	_line("")
	_line("═══ SCRUB PROBE — %.1fs fight, %d frames ═══" % [dur, frames.size()])

	# Play forward to the very end first, so EVERY unit that dies has toppled and the log is
	# fully drained. That is the state a backwards seek has to undo.
	_arena.set("opening_timer", 100.0)
	_arena.set("frame_pos", float(frames.size() - 1))
	_arena.call("_apply_frame", float(frames.size() - 1))
	_arena.call("_drain_log", (_arena.get("event_log") as Array).size())
	for _i in range(4):
		await get_tree().process_frame
	_check("after playing to the end", dur)
	_report_new_kinds()

	# Then jump BACKWARDS, hardest case first: all the way to the opening.
	for target in [0.5, dur * 0.5, dur * 0.75, 1.0]:
		var before_floats := _count_floats()
		_arena.call("_seek", float(target))
		await get_tree().process_frame
		await get_tree().process_frame
		_check("after seeking to t=%.1fs" % target, float(target))
		# ⚠️ THE ASSERTION IS "NO BULK REPLAY", NOT "NO FLOATS AT ALL". `_seek` finishes by applying
		# the frame it landed on, and that frame's own shots SHOULD present — landing on the tick
		# a blow lands and seeing nothing would be the bug. What must never happen is the 130
		# events between here and there all firing at once, which is what an unguarded re-drain
		# does. The ceiling is therefore the landing tick's own shot count.
		var frames2: Array = _arena.get("frames")
		var li: int = clampi(int(round(float(target) / 0.1)), 0, frames2.size() - 1)
		var allow: int = (frames2[li].get("shots", []) as Array).size() + 1
		var spawned := _count_floats() - before_floats
		if spawned > allow:
			_fail = true
			_line("   FAIL: the catch-up spawned %d floats, landing tick allows %d — `_fx_muted` is not holding"
				% [spawned, allow])
		else:
			_line("   floats spawned by the catch-up: %d (landing tick allows %d)  ✓" % [spawned, allow])
	_done(1 if _fail else 0)


## Label3D nodes are what `_float_text` creates; counting them counts the effect layer firing.
func _count_floats() -> int:
	var n := 0
	for c in _arena.get_children():
		if c is Label3D:
			n += 1
	return n


func _check(what: String, t: float) -> void:
	var frames: Array = _arena.get("frames")
	var i: int = clampi(int(round(t / 0.1)), 0, frames.size() - 1)
	var recs: Array = frames[i].get("units", [])
	var nodes: Array = _arena.get("nodes")
	_line("")
	_line("── %s ──" % what)

	var bad := 0
	for k in range(mini(nodes.size(), recs.size())):
		var frame_alive: bool = bool((recs[k] as Dictionary).get("alive", true))
		var shown_down: bool = bool((nodes[k] as Dictionary).get("dead", false))
		if frame_alive == shown_down:
			bad += 1
	if bad > 0:
		_fail = true
	_line("   bodies disagreeing with the frame (toppled but alive, or standing but dead): %d %s"
		% [bad, "✗" if bad > 0 else "✓"])

	# The log must carry exactly what has happened by now — no more (spoilers) and no less.
	var log: Array = _arena.get("event_log")
	var want := 0
	for e in log:
		if float((e as Dictionary).get("t", 0.0)) <= t:
			want += 1
	var got: int = int(_arena.get("logged_upto"))
	# ⚠️ ±1 IS NOT A BUG AND SAYING SO COSTS LESS THAN RE-DERIVING IT NEXT TIME. The seek's cutoff
	# is `frame_index * DT` and this check's is the requested time; an event sitting exactly on a
	# tick boundary falls on either side of `<=` depending on which of the two the float lands
	# above. The failure this test is for is a log that shows the FUTURE, or one that lost its
	# past — both of which are off by tens, not by one.
	if absi(got - want) > 1:
		_fail = true
	_line("   log lines drained %d, expected %d %s"
		% [got, want, "✗" if absi(got - want) > 1 else "✓"])

	# And the squad scoreboard — the surface this whole round exists to make honest.
	var na: int = (_arena.get("team_a") as Array).size()
	var real_a := 0
	var real_b := 0
	for k in range(recs.size()):
		if not bool((recs[k] as Dictionary).get("alive", true)):
			continue
		if k < na:
			real_a += 1
		else:
			real_b += 1
	var hud_a := 0
	var hud_b := 0
	for k in range(nodes.size()):
		if not bool(_arena.call("_alive_now", k)):
			continue
		if k < na:
			hud_a += 1
		else:
			hud_b += 1
	var hud_ok: bool = hud_a == real_a and hud_b == real_b
	if not hud_ok:
		_fail = true
	_line("   scoreboard reads %d v %d, frame holds %d v %d %s"
		% [hud_a, hud_b, real_a, real_b, "✓" if hud_ok else "✗"])


## ⚠️ THE FOUR KINDS `docs/WATCH_AUDIT.md` §4 FOUND SILENT — did they actually reach the player?
## The watch audit's own vocabulary table cannot answer this: its `SEEN_KINDS` list is hardcoded,
## so it reports what it was told in the past, not what the renderer does now. This reads the
## adapted log the player actually sees, which is the only source that cannot go stale.
func _report_new_kinds() -> void:
	var counts: Dictionary = {"taunted": 0, "aoe": 0, "fizzle": 0, "debuff": 0}
	var samples: Dictionary = {}
	for e in (_arena.get("event_log") as Array):
		var k := str((e as Dictionary).get("kind", ""))
		if counts.has(k):
			counts[k] = int(counts[k]) + 1
			if not samples.has(k):
				samples[k] = e
	_line("")
	_line("── the four kinds that were silent — do they now reach the adapted log? ──")
	for k in ["taunted", "aoe", "fizzle", "debuff"]:
		var n: int = int(counts[k])
		if n == 0:
			_line("   %-9s  0  — not produced by this roster (a roster question, not a renderer one)" % k)
		else:
			_line("   %-9s %2d  ✓  e.g. %s" % [k, n, str(samples[k])])


func _line(s: String) -> void:
	_out.append(s)


func _done(code: int) -> void:
	for s in _out:
		print(s)
	print("")
	print("SCRUB PROBE: %s" % ("FAIL" if code != 0 else "PASS"))
	get_tree().quit(code)
