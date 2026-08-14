## WATCH AUDIT — the playtest record this repo has never had.
##
## ⚠️ THIS PROBE'S JOB IS NOT "DOES IT RENDER". It is: can a viewer who committed a plan 30
## seconds ago tell WHAT IS HAPPENING, WHY, WHO IS WINNING, and WHETHER THEIR READ WAS RIGHT —
## without pausing, without the decision log, and without knowing the codebase.
## So it drives the REAL production watch path (title -> watch.gd -> arena3d.tscn ->
## `scripts/ui/arena_3d.gd`), plays a fight at true speed, and CAPTURES A STRIP — a sequence,
## not a pose, because a single frame cannot show whether a fight is readable over time.
##
## It reports three families of number, all of them about the VIEWER:
##   A. VOCABULARY  — which sim event kinds the fight produced, and which of those reach the
##      player's EYES (the visual adapter `arena_3d._adapt_event`) vs which reach only the ears
##      (`scripts/audio/battle_audio.gd`) vs which reach neither.
##   B. FRAMING     — how many pixels tall a monster actually is, over time, and what fraction of
##      the frame the bodies occupy. The camera fits all living units' bounding box, so a spread
##      fight averages into a distant blob; this measures how distant.
##   C. RHYTHM      — event density per second, the longest dead-air gap, and the busiest second.
##      Dead air and noise are both legibility failures and they are opposite ones.
##
## RUN IT WITH A WINDOW, NOT `--headless`. The dummy renderer returns blank images, so a headless
## run of this probe would "pass" while capturing black rectangles — exactly the class of silent
## success this project keeps recording.
##   P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/_probe_watch.tscn -- four_pillar 0.35
##
## It also keeps the original entry-point check (section A of the probe this replaced): the arena
## rendered perfectly in every earlier probe while the ENTRY POINT into it was broken. Testing the
## destination is not testing the journey.
extends Node

const Arena = preload("res://scripts/ui/arena_3d.gd")

## Sim seconds between strip captures. A fight is 20-140s; 12 frames is a readable contact sheet.
const STRIP_STEP := 2.0
## Every sim event kind, from `scripts/sim/sim.gd`. ⚠️ HARD-CODED ON PURPOSE — this is the
## tripwire: a kind the sim emits that is not in this list prints as UNKNOWN, and a kind in this
## list the fight never produced prints as NOT PRODUCED. Both are findings.
const ALL_KINDS := [
	"aoe", "buff", "cast_done", "cast_miss", "cast_start", "cleanse", "death", "debuff",
	"fizzle", "heal", "interrupt", "miss", "proj_fizzle", "proj_hit", "proj_launch",
	"status_applied", "status_break", "status_expire", "status_tick", "strike", "taunted",
	"thorns", "ward_soak",
]
## Kinds `arena_3d._adapt_event` translates into a log record / float / VFX. Anything outside this
## set is INVISIBLE — it may still be audible, which is a different question, answered separately.
## ⚠️ FOUR KINDS ADDED 2026-08-09 — `taunted`, `aoe`, `fizzle`, `debuff` are now presented
## (tether + float, impact ring at the sim's own centre/radius, grey "No target" cast bar, and the
## buff grammar inverted). Leaving them out of this list would have reported a fixed renderer as
## still silent, which is how a fix gets re-done. `cast_start` and `proj_launch` are presented
## through the FRAME STREAM (cast bar, projectile bodies) rather than through events — counted
## here because the question is what the viewer sees, not which code path shows it.
const SEEN_KINDS := [
	"strike", "cast_done", "proj_hit", "miss", "cast_miss", "status_applied", "status_expire",
	"heal", "buff", "cleanse", "interrupt", "death",
	"taunted", "aoe", "fizzle", "debuff", "cast_start", "proj_launch",
	# Presented once the roster could produce them — `thorns` reflects backwards along the arrow
	# the viewer just watched, `ward_soak` distinguishes a hit that landed and did nothing from
	# a miss. Both were "never fired, and that is its own finding" in the audit.
	"thorns", "ward_soak",
]

var _arena: Node = null
var _out: Array = []            # the report, printed at the end so it is not interleaved with engine spam
var _samples: Array = []        # per-engine-frame framing measurements
## Per-unit DRAWN body width/height in world units, read once from each rig's own `drawn_width` /
## `drawn_height` (the rig records what it actually scaled to — probe and renderer cannot
## disagree). ⚠️ THIS FEEDS THE OVERLAP-AT-REST METRIC, the number behind round 13's "the scrum
## is a pile" finding: the sim separates enemy centres by 2*Sp.BODY_RADIUS ground units
## (= 1.50 world at WORLD_SCALE 0.34) while bodies were drawn ~2.2-2.6 wide, so bodies
## interpenetrated ~40% AT REST by construction. Overlap depth for a pair = how far inside each
## other's drawn discs two living bodies sit, as a fraction of their mean drawn width.
var _body_w: Array = []
var _body_h: Array = []
## Overlap depths split by whether the pair was AT REST (both units' frame `state` is not
## "advance" — the sim's own definition: moved ≤0.02 this tick) or CROSSING (either moving).
## ⚠️ THE SPLIT IS THE HONESTY OF THE METRIC, NOT A SOFTENING OF IT. Allies are PASSABLE by
## design (`AUTOBATTLER_DESIGN.md` #22), so two allies crossing legitimately pass through each
## other and briefly measure 100% overlap — that is motion, and it reads as motion. The pile
## complaint is bodies STANDING inside each other, and that is what the rest figure isolates.
## Both are reported; hiding the crossing number would be the probe lying by omission.
var _ov_rest: Array = []        # depth fractions, pairs at rest — CROSS-TEAM (enemy push-out is
								#  the hard rule, so this is the pure read of drawn vs simulated)
var _ov_rest_ally: Array = []   # depth fractions, ALLY pairs at rest — the sim's soft-avoid only
								#  drifts allies apart, so standing ally overlap is a SIM spacing
								#  finding, not a drawing one; split so the fault gets the right owner
var _ov_move: Array = []        # depth fractions, pairs where at least one body is travelling
var _ov_episodes: Array = []    # deep rest overlaps, identified: who stood inside whom, and when
var _next_strip := 0.0
## Any canary tripping sets this; `_finish_audit` exits non-zero on it. A probe that reports a
## failure in prose and exits 0 is a probe nobody notices twice.
var _canary_failed := false
var _aoe_seen := 0
var _aoe_shot_at := 0
var _per_unit_gap: Array = []
var _per_unit_orph: Array = []
var _per_unit_n: Array = []
var _shot := 0
var _tag := "four_pillar"
var _cam_mode := 0


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var layout: String = args[0] if args.size() > 0 else "four_pillar"
	var train: float = float(args[1]) if args.size() > 1 else 0.35
	_cam_mode = int(args[2]) if args.size() > 2 else 0   # 0 TEAM · 1 ACTION · 2 ARENA
	_tag = "%s_t%02d_cam%d" % [layout, int(train * 100.0), _cam_mode]

	if not await _check_entry_point():
		get_tree().quit(1)
		return

	_line("")
	_line("═══ WATCH AUDIT — layout=%s training=%.2f ═══" % [layout, train])

	var W = load("res://scripts/watch.gd")
	var a: Array = []
	var b: Array = []
	for s in W.ROSTER_A:
		a.append(GameData.make_monster(s, train))
	for s in W.ROSTER_B:
		b.append(GameData.make_monster(s, train))
	# ⚠️ THE ROLES COME FROM `watch.gd`, THEY ARE NOT COPIED HERE. This probe reconstructs the
	# viewer's roster rather than launching it (it needs the arena as a child to measure), and a
	# reconstruction that drifts measures a fight the player never sees — which is precisely the
	# failure this audit exists to catch. Calling the viewer's own `_cast_role` makes drift
	# impossible: change the composition in one place and the instrument follows.
	for role in W.ROLES_A:
		W._cast_role(a[int(role["i"])], role)
	for role in W.ROLES_B:
		W._cast_role(b[int(role["i"])], role)
	# Same committed plan the viewer uses — including the `manmark` order, so the report screen
	# this probe captures grades a real claim instead of printing "you committed no claim".
	var plan_a := {"targetPriority": "manmark", "markedUnit": b[2],
		"positionalIntent": "push", "temperament": "balanced", "formation": "tight"}
	var plan_b := {"targetPriority": "tanks", "positionalIntent": "dive",
		"temperament": "aggressive", "formation": "loose"}
	var T = load("res://scripts/tactics.gd")
	T.committed = {"teamA": a, "teamB": b, "planA": plan_a, "planB": plan_b,
		"orders": {}, "ordersA": {}, "ordersB": {}, "layout": layout}

	_arena = (load("res://scenes/arena3d.tscn") as PackedScene).instantiate()
	add_child(_arena)
	var ok := false
	for i in range(1200):
		await get_tree().process_frame
		var nodes: Array = _arena.get("nodes")
		if nodes != null and not nodes.is_empty() and not (_arena.get("frames") as Array).is_empty():
			ok = true
			break
	if not ok:
		_line("FAIL: the arena never produced units + frames")
		_dump()
		get_tree().quit(1)
		return

	_arena.set("_cam_mode", _cam_mode)
	await _report_vocabulary()
	_report_rhythm()
	# Playback runs in `_process` below; it finishes by calling `_finish_audit`.
	_line("")
	_line("── C. FRAMING (measured every engine frame during real playback) ──")


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# A. THE ENTRY POINT — is the destination reachable at all
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _check_entry_point() -> bool:
	var title: Node = (load("res://scenes/title.tscn") as PackedScene).instantiate()
	add_child(title)
	await get_tree().process_frame
	var btn := _find_button(title, "Watch a Battle")
	if btn == null:
		_line("FAIL: no 'Watch a Battle' button on the title screen")
		_dump()
		return false
	var live: bool = not btn.disabled and not btn.pressed.get_connections().is_empty()
	_line("entry point: '%s' disabled=%s connections=%d -> %s"
		% [btn.text, btn.disabled, btn.pressed.get_connections().size(), "LIVE" if live else "DEAD"])
	title.queue_free()
	await get_tree().process_frame
	return live


func _find_button(n: Node, label: String) -> Button:
	if n is Button and (n as Button).text == label:
		return n
	for c in n.get_children():
		var r := _find_button(c, label)
		if r != null:
			return r
	return null


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# B. VOCABULARY — what the fight said, and which senses heard it
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _report_vocabulary() -> void:
	# ⚠️ `arena_3d.gd` THROWS THE RAW EVENT STREAM AWAY at `_adapt_result` — only the twelve kinds
	# `_adapt_event` recognises survive into `event_log`. So the raw vocabulary has to be counted
	# from a second, IDENTICAL run of the same sim (same seed, same inputs, deterministic), which
	# is itself the finding: the renderer cannot tell you what it dropped.
	var counts: Dictionary = await _count_kinds_by_resim()
	_line("")
	_line("── A. VOCABULARY — %d event kinds fired ──" % counts.size())
	var eyes := 0
	var blind := 0
	var kinds: Array = counts.keys()
	kinds.sort()
	for k in kinds:
		var sense := "EYES+log" if k in SEEN_KINDS else "no visual"
		if k in SEEN_KINDS:
			eyes += 1
		else:
			blind += 1
		if not (k in ALL_KINDS):
			sense += "  ⚠ UNKNOWN KIND (sim grew, this probe did not)"
		_line("   %-16s %5d   %s" % [k, int(counts[k]), sense])
	for k in ALL_KINDS:
		if not counts.has(k):
			_line("   %-16s     0   NOT PRODUCED by this roster" % k)
	_line("   → %d kinds have a visual read, %d are visually silent this fight" % [eyes, blind])
	# ⚠️ AND WHY A KIND NEVER FIRED IS A ROSTER QUESTION, NOT A RENDERER ONE. `COMBAT_SPATIAL_LOG`
	# already recorded this once: "a demo roster that cannot produce a mechanic is a demo that
	# hides it". So print what the ten monsters actually brought.
	_line("   the ten kits that produced the above:")
	for m in (_arena.get("all_units") as Array):
		var names: Array = []
		for mv in m.moveset:
			names.append(str((mv as Dictionary).get("name", "")))
		_line("     %-12s %s" % [m.species_name, ", ".join(PackedStringArray(names))])


## Re-runs the same fight headlessly to count RAW event kinds. ⚠️ Deterministic: same seed, same
## inputs, same fight — this is a second read of the same match, not a second match.
func _count_kinds_by_resim() -> Dictionary:
	var counts: Dictionary = {}
	var NewSim = load("res://scripts/sim/sim.gd")
	var Sp = load("res://scripts/spatial.gd")
	var inputs: Array = _arena.call("_new_sim_inputs")
	var ground: Vector2 = _arena.get("ground_size")
	var off: Vector2 = ground * 0.5
	var nav_obstacles: Array = []
	for ob in (_arena.get("_obstacles") as Array):
		if str((ob as Dictionary).get("grade", "blocking")) == Sp.COVER_BLOCKS_LOS_GRADE:
			var r: Rect2 = (ob as Dictionary)["rect"]
			nav_obstacles.append({"rect": Rect2(r.position - off, r.size)})
	var sim = NewSim.new()
	sim.setup(20260804, inputs, ground, nav_obstacles)
	var half_x: float = ground.x * 0.5 - 4.0
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-half_x, 0), Vector2(half_x, 0))
	if not ok:
		_line("   (cannot re-sim: navigation never became ready)")
		return counts
	var raw: Dictionary = sim.run()
	sim.nav.free_rids()
	for rf in (raw.get("frames", []) as Array):
		for e in (rf.get("events", []) as Array):
			var k := str(e.get("kind", ""))
			counts[k] = int(counts.get(k, 0)) + 1
	return counts


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# C. RHYTHM — dead air and noise, both measured off the log the player actually reads
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _report_rhythm() -> void:
	var log: Array = _arena.get("event_log")
	var dur: float = float((_arena.get("frames") as Array).size()) * 0.1
	_line("")
	_line("── B. RHYTHM — %.1fs fight, %d log lines the player can read ──" % [dur, log.size()])
	# Bucket by whole second.
	var per_sec: Dictionary = {}
	var last_t := 0.0
	var worst_gap := 0.0
	var worst_at := 0.0
	# Only BIG events count as "something happened" for the dead-air test — a 4-damage tick is not
	# a beat. Deaths, interrupts, cleanses and heals are; routine hits are counted separately.
	var big := ["death", "interrupt", "cleanse", "status_apply"]
	var big_last := 0.0
	var big_worst := 0.0
	var big_worst_at := 0.0
	for e in log:
		var t: float = float(e.get("t", 0.0))
		var k := str(e.get("kind", ""))
		if k == "start" or k == "end":
			continue
		var s := int(floor(t))
		per_sec[s] = int(per_sec.get(s, 0)) + 1
		if t - last_t > worst_gap:
			worst_gap = t - last_t
			worst_at = last_t
		last_t = t
		if k in big:
			if t - big_last > big_worst:
				big_worst = t - big_last
				big_worst_at = big_last
			big_last = t
	var busiest := 0
	var busiest_s := 0
	var quiet := 0
	for s in range(int(ceil(dur))):
		var n: int = int(per_sec.get(s, 0))
		if n > busiest:
			busiest = n
			busiest_s = s
		if n == 0:
			quiet += 1
	# ⚠️ "21 LINES IN THE BUSIEST SECOND" IS A VERDICT WITHOUT A CULPRIT. A density number that
	# does not say WHICH lines cost the second cannot tell you whether the fix is coalescing,
	# suppression, or nothing at all — and a presentation change made without that breakdown is a
	# change made on a feeling. So: what the whole log is made of, and what the worst second is made
	# of. This is also how an AFTER run proves a coalescer MERGED lines rather than deleting them:
	# the merged line count falls while the underlying raw event count (section A) does not.
	_line("   log composition     %s" % _kind_hist(log, -1))
	_line("   busiest second is   %s" % _kind_hist(log, busiest_s))
	_line("   density        %.2f log lines/sec average" % (float(log.size()) / maxf(dur, 0.01)))
	_line("   busiest second %d lines at t=%ds  ← can a viewer read %d lines in one second?"
		% [busiest, busiest_s, busiest])
	_line("   silent seconds %d of %d (%.0f%% of the fight has NO log line at all)"
		% [quiet, int(ceil(dur)), 100.0 * float(quiet) / maxf(1.0, ceil(dur))])
	_line("   longest gap    %.1fs of nothing, starting t=%.1fs" % [worst_gap, worst_at])
	_line("   longest gap between BIG beats (death/interrupt/cleanse/status): %.1fs from t=%.1fs"
		% [big_worst, big_worst_at])
	# When did the fight's outcome become obvious? First death, and the score at each death.
	var deaths: Array = []
	for e in log:
		if str(e.get("kind", "")) == "death":
			deaths.append(float(e.get("t", 0.0)))
	var first_hit := -1.0
	for e in log:
		if str(e.get("kind", "")) == "hit":
			first_hit = float(e.get("t", 0.0))
			break
	_line("   first DAMAGE   t=%.1fs (%.0f%% of the fight is the approach — nothing is at stake yet)"
		% [first_hit, 100.0 * first_hit / maxf(dur, 0.01)])
	if deaths.is_empty():
		_line("   deaths         NONE — the fight was decided by the clock, not by kills")
	else:
		_line("   deaths at      %s" % str(deaths.map(func(t): return "%.1f" % t)))
		_line("   first blood    t=%.1fs (%.0f%% into the fight)"
			% [deaths[0], 100.0 * deaths[0] / maxf(dur, 0.01)])


## THE DENSITY THE VIEWER ACTUALLY FACES, BEFORE AND AFTER, OUT OF ONE RUN.
##
## ⚠️ SECTION B COUNTS `event_log`, WHICH IS NOT WHAT IS ON THE SCREEN. It counts adapted sim
## events and knows nothing about the intent ticker, which writes to the same log surface, or
## about coalescing. So "21 lines in the busiest second" was never the number of ROWS the player
## reads. The renderer now records both: every statement the fight made, and every row that
## survived merging. Bucketing the two by second gives the before and the after from the SAME
## fight - which matters more than usual this round, because the sim is being changed underneath
## this probe (the same move burst measured r=96.8 in one run and r=43.1 in the next, an hour
## apart), and a two-run comparison would be measuring two different fights.
func _report_density() -> void:
	var stmts: Array = _arena.get("_log_stmt_times")
	var rows: Array = _arena.get("_log_row_times")
	var merges: int = int(_arena.get("_log_merges"))
	if stmts == null or rows == null:
		_line("   log density     UNAVAILABLE - the renderer exposes no row model")
		_canary_failed = true
		return
	_line("")
	_line("-- D4. LOG DENSITY - the rows a viewer has to read, not the events behind them --")
	_line("   statements the fight made      %d" % stmts.size())
	_line("   rows the player actually reads %d   (%d folded away by coalescing)"
		% [rows.size(), merges])
	_line("   busiest second BEFORE merging  %d rows" % _busiest(stmts))
	_line("   busiest second AFTER  merging  %d rows   <- the acceptance number" % _busiest(rows))
	if merges <= 0:
		_line("   CANARY FAILED - the coalescer merged nothing; it is dead or unreachable.")
		_canary_failed = true


func _busiest(times: Array) -> int:
	var per: Dictionary = {}
	var worst := 0
	for t in times:
		var sec := int(floor(float(t)))
		per[sec] = int(per.get(sec, 0)) + 1
		worst = maxi(worst, int(per[sec]))
	return worst


## One line of "kind=count", biggest first. `sec` < 0 counts the whole log; otherwise only the
## lines that landed inside that whole second.
func _kind_hist(log: Array, sec: int) -> String:
	var c: Dictionary = {}
	for e in log:
		var k := str(e.get("kind", ""))
		if k == "start" or k == "end":
			continue
		if sec >= 0 and int(floor(float(e.get("t", 0.0)))) != sec:
			continue
		c[k] = int(c.get(k, 0)) + 1
	var ks: Array = c.keys()
	ks.sort_custom(func(a, b): return int(c[a]) > int(c[b]))
	var parts: Array = []
	var tot := 0
	for k in ks:
		parts.append("%s=%d" % [k, int(c[k])])
		tot += int(c[k])
	return "%d lines: %s" % [tot, " ".join(PackedStringArray(parts))]


## ⚠️ THE BURST IS THE ONE EFFECT WHOSE SIZE IS NOT A TASTE DECISION - it is the sim's own
## `radius`, and round 23 left that number doing double duty as the THROW DISTANCE, so a burst drew
## a ring spanning a third of the arena. The geometry agent is separating the two THIS ROUND, which
## means the renderer must read correctly at a radius about to change by a large factor and at a
## centre that may stop being the caster. This census is how "reads at both sizes" stops being an
## assertion: every burst the fight produced, with its radius in ground units, in world units, and
## as an on-screen DIAMETER in pixels beside the body height measured in the same run. A ring 40x a
## body is a wash; a ring 0.3x a body is a spark. Both are failures and both are visible here.
func _report_aoe(px_per_world: float, mean_body_px: float) -> void:
	var log: Array = _arena.get("event_log")
	var bursts: Array = []
	for e in log:
		if str(e.get("kind", "")) == "aoe":
			bursts.append(e)
	_line("")
	_line("-- D3. THE AoE BURST - %d bursts, and whether a viewer could size or count one --" % bursts.size())
	if bursts.is_empty():
		_line("   NO BURST FIRED. This roster produced no allEnemies cast, so nothing here is evidence")
		_line("   either way - a demo that cannot produce a mechanic hides it (the standing lesson).")
		return
	var ws: float = float(Arena.WORLD_SCALE)
	for e in bursts:
		var r: float = float(e.get("radius", 0.0))
		var dia_px: float = 2.0 * r * ws * px_per_world
		_line("   t=%5.1fs  %-14s r=%6.1f ground = %5.1f world -> %6.0f px across (%.1fx a body) - caught %d, falloff %.2f"
			% [float(e.get("t", 0.0)), str(e.get("move", "?")), r, r * ws, dia_px,
			   dia_px / maxf(1.0, mean_body_px), int(e.get("targets", 0)), float(e.get("falloff", 1.0))])
	# THE CANARY. Counters live on the arena, so a presentation that silently stops firing reports
	# zero rather than passing quietly - the same discipline section F uses for the mix.
	var drawn: int = int(_arena.get("_aoe_bursts_drawn"))
	var counted: int = int(_arena.get("_aoe_counts_drawn"))
	_line("   CANARY  events %d -> rings drawn %d - count reads drawn %d" % [bursts.size(), drawn, counted])
	if drawn < bursts.size() or counted < bursts.size():
		_line("   CANARY FAILED - a burst fired that the viewer was never shown.")
		_canary_failed = true
	# THE COALESCER'S OWN CANARY. A log that merges nothing and a log with no coalescer at all are
	# indistinguishable from the line count alone - both just print what the fight produced. The
	# renderer counts its merges, so "the density fell" can be separated from "the fight was quieter
	# this run", which matters here because the sim is being changed underneath this probe today.
	_report_density()


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# D. FRAMING — measured live, during real playback, with the real camera
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _process(_delta: float) -> void:
	if _arena == null:
		return
	var frames: Array = _arena.get("frames")
	if frames == null or frames.is_empty():
		return
	var cam: Camera3D = _arena.get("camera")
	if cam == null:
		return
	var t: float = float(_arena.get("frame_pos")) * 0.1
	_measure(cam, t)
	if t >= _next_strip:
		_next_strip += STRIP_STEP
		_capture(t)
	# THE BURST IS SHORTER THAN THE STRIP INTERVAL, SO THE STRIP CANNOT SEE IT. A ring lives ~0.6s
	# and the contact sheet samples every 2.0s, which means every capture in `docs/WATCH_AUDIT.md`
	# was taken with no burst on screen - the effect this round is judged on was literally never
	# photographed. Trigger off the renderer's own draw counter and shoot a few frames later, while
	# the ring is still expanding.
	var drawn: int = int(_arena.get("_aoe_bursts_drawn"))
	if drawn > _aoe_seen:
		_aoe_seen = drawn
		_aoe_shot_at = 6
	elif _aoe_shot_at > 0:
		_aoe_shot_at -= 1
		if _aoe_shot_at == 0:
			_capture_named("burst%d_t%05.1f" % [_aoe_seen, t])
	if not bool(_arena.get("playing")) and t > 0.2:
		_finish_audit()


## ⚠️ ALIVENESS COMES FROM THE FRAME, NOT FROM `all_units[k].alive`. `_write_back_final()` stamps
## the fight's FINAL state onto the monster objects before playback starts, so `MonsterInstance.alive`
## is the ANSWER, not the current state. This probe must not repeat the renderer's own mistake —
## and comparing the two is how the mistake gets measured.
func _frame_alive() -> Array:
	var frames: Array = _arena.get("frames")
	var i: int = clampi(int(floor(float(_arena.get("frame_pos")))), 0, frames.size() - 1)
	var out: Array = []
	for rec in (frames[i].get("units", []) as Array):
		out.append(bool(rec.get("alive", true)))
	return out


## Per-unit `state` from the DISPLAYED frame — the sim's own word for whether a body is
## travelling ("advance": moved more than 0.02 this tick) or standing/casting/idle.
func _frame_states() -> Array:
	var frames: Array = _arena.get("frames")
	var i: int = clampi(int(floor(float(_arena.get("frame_pos")))), 0, frames.size() - 1)
	var out: Array = []
	for rec in (frames[i].get("units", []) as Array):
		out.append(str(rec.get("state", "idle")))
	return out


func _measure(cam: Camera3D, t: float) -> void:
	var nodes: Array = _arena.get("nodes")
	var units: Array = _frame_alive()
	_cache_body_sizes()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	var body_px := 0.0
	var drawn_h_px := 0.0
	var on_screen := 0
	var n := 0
	for k in range(nodes.size()):
		if k >= units.size() or not units[k]:
			continue
		var p: Vector3 = (nodes[k]["holder"] as Node3D).position
		var foot: Vector2 = cam.unproject_position(p)
		var head: Vector2 = cam.unproject_position(p + Vector3(0, Arena.UNIT_HEIGHT, 0))
		var h: float = absf(foot.y - head.y)
		# ⚠️ BODY AREA IS THE BODY AS DRAWN, NOT A 0.6-RATIO GUESS. This used to assume every body
		# is 0.6x as wide as it is tall at nominal UNIT_HEIGHT; once the rig records its real
		# drawn width/height (and the footprint cap makes them differ per species), the guess
		# both under-counted wide bodies and would have over-counted capped ones — the instrument
		# lying about the very trade-off the cap makes.
		var wf: float = (float(_body_w[k]) / Arena.UNIT_HEIGHT) if k < _body_w.size() else 0.6
		var hf: float = (float(_body_h[k]) / Arena.UNIT_HEIGHT) if k < _body_h.size() else 1.0
		body_px += PI * (h * wf * 0.5) * (h * hf * 0.5)
		drawn_h_px += h * hf
		# ⚠️ IS IT EVEN IN FRAME? `unproject_position` happily returns coordinates far outside the
		# viewport (and mirrored ones for points BEHIND the camera), so "action box area" is
		# meaningless once anything leaves the shot. The honest metric is a headcount.
		if foot.x >= 0.0 and foot.x <= vp.x and foot.y >= 0.0 and foot.y <= vp.y 				and not cam.is_position_behind(p):
			on_screen += 1
		mn.x = minf(mn.x, foot.x); mn.y = minf(mn.y, head.y)
		mx.x = maxf(mx.x, foot.x); mx.y = maxf(mx.y, foot.y)
		n += 1
	if n == 0:
		return
	var box: float = maxf(0.0, mx.x - mn.x) * maxf(0.0, mx.y - mn.y)
	# ── THE NAMEPLATE READ. A plate is the only HP/intent surface the player has, and it is only
	# usable if you can tell WHOSE it is. Two failures are measurable: a plate lifted far from the
	# head it annotates (unattributable), and two plates overlapping (illegible).
	var rects: Array = []
	var orphan := 0
	var orphan_drawn := 0
	var plate_gap := 0.0
	var gapped := 0
	var plate_px := 0.0
	for k in range(nodes.size()):
		if k >= units.size() or not units[k]:
			continue
		var plate: Control = nodes[k].get("plate")
		if plate == null or not plate.visible:
			continue
		var head: Vector2 = cam.unproject_position((nodes[k]["holder"] as Node3D).position
			+ Vector3(0, Arena.UNIT_HEIGHT, 0))
		# SIZE MUST INCLUDE SCALE - the same trap the renderer's own declutter pass records in its
		# comments and this probe walked into anyway. A collapsed "mini" plate is `scale`d, and
		# `Control.size` does not know that, so measuring the rect off the unscaled size put the
		# plate's bottom edge up to 30px BELOW where it is drawn (a plate is anchored by its bottom,
		# so the error is pure fiction added to the gap) and inflated the plate-area figure by the
		# same factor. Both are numbers this round is judged on.
		var r := Rect2(plate.position, plate.size * plate.scale)
		# "Far" = more than one body-height away from the head it belongs to.
		if (r.get_center() - head).length() > _mean_unit_height(cam, nodes, units):
			orphan += 1
		# THE SAME QUESTION ASKED OF THE HEAD THAT EXISTS.
		# The line above measures the plate against the NOMINAL head - holder + UNIT_HEIGHT - and the
		# plate is ANCHORED at nominal head + 0.7, so the two share their error and the metric can only
		# ever see lifting. It is blind by construction to the defect it is named for: a body drawn
		# 0.68 world units tall (the footprint cap, section D2) carries a plate 5.1 units up, four body
		# heights clear of the creature, and this measure calls that 0% orphaned. An instrument whose
		# reference point is the bug cannot see the bug. So measure it again against the head the RIG
		# says it drew, and report both - the nominal figure stays so the two runs remain comparable.
		var dh: float = float(_body_h[k]) if k < _body_h.size() else Arena.UNIT_HEIGHT
		var dhead: Vector2 = cam.unproject_position((nodes[k]["holder"] as Node3D).position
			+ Vector3(0, dh, 0))
		var foot_px: Vector2 = cam.unproject_position((nodes[k]["holder"] as Node3D).position)
		var body_px_h: float = maxf(1.0, absf(foot_px.y - dhead.y))
		# MEASURED FROM THE PLATE'S NEAREST EDGE, NOT ITS CENTRE. A plate is 4.4x the body's pixels
		# (see the ratio below), so a centre-to-head distance charges the plate for its own size and
		# would read as "orphaned" for a plate sitting squarely on the head. Attribution is carried by
		# the edge that faces the creature - that is the gap the eye has to jump.
		var bottom_mid := Vector2(r.position.x + r.size.x * 0.5, r.position.y + r.size.y)
		var gap: float = (bottom_mid - dhead).length() / body_px_h
		plate_gap += gap
		if gap > 1.0:
			orphan_drawn += 1
		gapped += 1
		# PER UNIT, because "18% orphaned" does not say whether the residue is one tiny body that can
		# never satisfy the test or every plate failing a little. Those want opposite fixes.
		while _per_unit_gap.size() <= k:
			_per_unit_gap.append(0.0)
			_per_unit_orph.append(0.0)
			_per_unit_n.append(0.0)
		_per_unit_gap[k] = float(_per_unit_gap[k]) + gap
		_per_unit_orph[k] = float(_per_unit_orph[k]) + (1.0 if gap > 1.0 else 0.0)
		_per_unit_n[k] = float(_per_unit_n[k]) + 1.0
		plate_px += r.size.x * r.size.y
		rects.append(r)
	var collide := 0
	for i in range(rects.size()):
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).intersects(rects[j]):
				collide += 1
	# ── THE SCOREBOARD READ. ⚠️ THIS MEASURED THE WRONG FIELD AFTER THE FIX AND WOULD HAVE READ
	# AS A REGRESSION. It counted `MonsterInstance.alive`, which `_write_back_final` stamped with
	# the fight's final state before playback began — the bug `docs/WATCH_AUDIT.md` §1 found. The
	# renderer now reads aliveness from the DISPLAYED FRAME via `_alive_now(k)`, and deliberately
	# leaves `MonsterInstance.alive` stale until `_finish()`, so the old count can never reach 0%
	# disagreement no matter how correct the scoreboard is. It now asks the scoreboard's own
	# source the same question the frame answers — which is what "does the HUD agree with what is
	# on screen" always meant.
	var hud_a := 0
	var hud_b := 0
	var na_side: int = (_arena.get("team_a") as Array).size()
	for k in range(nodes.size()):
		if not bool(_arena.call("_alive_now", k)):
			continue
		if k < na_side:
			hud_a += 1
		else:
			hud_b += 1
	var real_a := 0
	var real_b := 0
	var na: int = (_arena.get("team_a") as Array).size()
	for k in range(units.size()):
		if not units[k]:
			continue
		if k < na:
			real_a += 1
		else:
			real_b += 1
	# ── HOW MUCH OF THE BOARD THE FIGHT ACTUALLY USES. The ground is sized by `Sp.ground_size`;
	# the fight occupies whatever it occupies. `ARENA_BLUEPRINT`/`ART_DIRECTION` keep the VENUE
	# and the GROUND apart on purpose — this is the number that says whether the ground was sized
	# for the fight or for the spectacle.
	var frames2: Array = _arena.get("frames")
	var fi: int = clampi(int(floor(float(_arena.get("frame_pos")))), 0, frames2.size() - 1)
	var wmn := Vector2(1e9, 1e9)
	var wmx := Vector2(-1e9, -1e9)
	for rec in (frames2[fi].get("units", []) as Array):
		if not bool(rec.get("alive", true)):
			continue
		var wp: Vector2 = rec.get("pos", Vector2.ZERO)
		wmn.x = minf(wmn.x, wp.x); wmn.y = minf(wmn.y, wp.y)
		wmx.x = maxf(wmx.x, wp.x); wmx.y = maxf(wmx.y, wp.y)
	var gs: Vector2 = _arena.get("ground_size")
	var used: float = maxf(0.0, wmx.x - wmn.x) * maxf(0.0, wmx.y - wmn.y)
	# ── BODY OVERLAP — do five bodies read as five bodies, or as a pile? Measured between living
	# units' HOLDER positions (world units, the sim's own truth via `_to_world`) against the width
	# each rig says it drew. A pair "overlaps" when its centres sit closer than the mean of the two
	# drawn widths; depth is how far inside that the pair is. The acceptance bar for the footprint
	# fix is mean depth under ~10%.
	_cache_body_sizes()
	var states: Array = _frame_states()
	var ov_pairs := 0
	var ov_rest_pairs := 0
	var ov_worst := 0.0
	# ⚠️ NOT BEFORE PLAYBACK HAS PLACED THE BODIES. For the first few engine frames every holder
	# still sits at the scene origin, so all ten units measure 0.00 apart and 45 pairs read as
	# 100%-deep "standing overlaps" — this probe reported exactly that as a sim spacing fault
	# before this guard existed. Instruments lie at boundaries; skip the boot frames.
	for i2 in range(nodes.size() if t >= 0.2 else 0):
		if i2 >= units.size() or not units[i2]:
			continue
		for j2 in range(i2 + 1, nodes.size()):
			if j2 >= units.size() or not units[j2]:
				continue
			var touch: float = (float(_body_w[i2]) + float(_body_w[j2])) * 0.5
			if touch <= 0.0:
				continue
			var pa: Vector3 = (nodes[i2]["holder"] as Node3D).position
			var pb: Vector3 = (nodes[j2]["holder"] as Node3D).position
			var d2: float = Vector2(pa.x - pb.x, pa.z - pb.z).length()
			if d2 < touch:
				var depth: float = 1.0 - d2 / touch
				ov_pairs += 1
				ov_worst = maxf(ov_worst, depth)
				var at_rest: bool = i2 < states.size() and j2 < states.size() \
					and str(states[i2]) != "advance" and str(states[j2]) != "advance"
				if at_rest:
					ov_rest_pairs += 1
					var na_split: int = (_arena.get("team_a") as Array).size()
					if (i2 < na_split) == (j2 < na_split):
						_ov_rest_ally.append(depth)
					else:
						_ov_rest.append(depth)
					# A STANDING pair more than half inside each other is a spacing fault worth
					# naming, not just counting — record who, when, and how close (one line per
					# sampled second per pair, or the 10Hz sim x 144Hz probe floods the report).
					if depth > 0.5:
						var sig := "%d-%d@%d" % [i2, j2, int(t)]
						var dup := false
						for ep in _ov_episodes:
							if str((ep as Dictionary).get("sig", "")) == sig:
								dup = true
								break
						if not dup:
							_ov_episodes.append({"sig": sig, "t": t, "i": i2, "j": j2,
								"d": d2, "si": str(states[i2]) if i2 < states.size() else "?",
								"sj": str(states[j2]) if j2 < states.size() else "?"})
				else:
					_ov_move.append(depth)
	_samples.append({
		"ov_pairs": ov_pairs, "ov_rest_pairs": ov_rest_pairs, "ov_worst": ov_worst,
		"used_frac": used / maxf(1.0, gs.x * gs.y),
		"span_x": maxf(0.0, wmx.x - wmn.x), "span_y": maxf(0.0, wmx.y - wmn.y),
		"t": t, "n": n,
		"mean_h": _mean_unit_height(cam, nodes, units),
		"drawn_h": drawn_h_px / maxf(1.0, float(n)),
		"body_frac": body_px / (vp.x * vp.y),
		"box_frac": box / (vp.x * vp.y),
		"plate_frac": plate_px / (vp.x * vp.y),
		"on_screen": float(on_screen) / maxf(1.0, float(n)),
		"orphan": orphan, "collide": collide, "plates": rects.size(),
		"orphan_drawn": orphan_drawn, "plate_gap": plate_gap, "gapped": gapped,
		"hud_lies": 1 if (hud_a != real_a or hud_b != real_b) else 0,
		# ⚠️ THE FRAME BUDGET IS PART OF LEGIBILITY, NOT SEPARATE FROM IT. A round that adds a
		# director, off-screen pips, team rings, leader lines, tethers, impact rings and a mixer
		# can buy readability and spend it again on a stutter — and a fight the player cannot
		# intervene in is judged entirely on how it LOOKS running. Sampled where every other
		# framing number is sampled, so it describes the same fight.
		"dt": get_process_delta_time(),
		# Split the budget so a verdict names a CULPRIT rather than a number. `TIME_PROCESS` is
		# all GDScript `_process` in the tree (the director, the plates, the pips, this probe);
		# the remainder is the renderer.
		"cpu": Performance.get_monitor(Performance.TIME_PROCESS),
		"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objs": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	})


func _sim_body_radius() -> float:
	return float(load("res://scripts/spatial.gd").BODY_RADIUS)


func _depth_stats(depths: Array, suffix: String) -> String:
	if depths.is_empty():
		return "no overlapping pair-samples"
	depths.sort()
	var dsum := 0.0
	for d in depths:
		dsum += float(d)
	var p90: float = float(depths[mini(depths.size() - 1, int(float(depths.size()) * 0.90))])
	var worst: float = float(depths[depths.size() - 1])
	return "depth mean %.1f%% · p90 %.1f%% · worst %.1f%% · %d pair-samples %s" \
		% [100.0 * dsum / float(depths.size()), 100.0 * p90, 100.0 * worst, depths.size(), suffix]


## Reads each unit's drawn body size ONCE from its rig. A sprite unit (no rig) falls back to the
## probe's long-standing assumption that a billboarded body is ~0.6x as wide as it is tall — the
## same figure `body_px` in `_measure` has always used, so the two reads cannot drift apart.
func _cache_body_sizes() -> void:
	if not _body_w.is_empty():
		return
	var nodes: Array = _arena.get("nodes")
	if nodes == null or nodes.is_empty():
		return
	for nd in nodes:
		var rig = (nd as Dictionary).get("rig")
		if rig != null and float(rig.get("drawn_width")) > 0.0:
			_body_w.append(float(rig.get("drawn_width")))
			_body_h.append(float(rig.get("drawn_height")))
		else:
			_body_w.append(Arena.UNIT_HEIGHT * 0.6)
			_body_h.append(Arena.UNIT_HEIGHT)


func _mean_unit_height(cam: Camera3D, nodes: Array, units: Array) -> float:
	var tot := 0.0
	var n := 0
	for k in range(nodes.size()):
		if k >= units.size() or not units[k]:
			continue
		var p: Vector3 = (nodes[k]["holder"] as Node3D).position
		tot += absf(cam.unproject_position(p).y - cam.unproject_position(p + Vector3(0, Arena.UNIT_HEIGHT, 0)).y)
		n += 1
	return tot / maxf(1.0, float(n))


func _capture_named(tag: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://watch_%s_%s.png" % [_tag, tag])


func _capture(t: float) -> void:
	await RenderingServer.frame_post_draw
	var path := "user://watch_%s_%02d_t%05.1f.png" % [_tag, _shot, t]
	get_viewport().get_texture().get_image().save_png(path)
	_shot += 1


func _finish_audit() -> void:
	set_process(false)
	if _samples.is_empty():
		_line("   (no framing samples)")
		_dump()
		get_tree().quit(0)
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var mean_h := 0.0
	var min_h := 1e9
	var max_h := 0.0
	var mean_body := 0.0
	var mean_box := 0.0
	for s in _samples:
		mean_h += float(s["mean_h"]); mean_body += float(s["body_frac"]); mean_box += float(s["box_frac"])
		min_h = minf(min_h, float(s["mean_h"])); max_h = maxf(max_h, float(s["mean_h"]))
	var c := float(_samples.size())
	_line("   viewport            %dx%d" % [int(vp.x), int(vp.y)])
	_line("   monster height      mean %.0f px  (%.1f%% of frame height) · min %.0f · max %.0f"
		% [mean_h / c, 100.0 * (mean_h / c) / vp.y, min_h, max_h])
	var drawn_h := 0.0
	for sd in _samples:
		drawn_h += float(sd.get("drawn_h", 0.0))
	_line("   DRAWN height        mean %.0f px — the body as actually scaled (footprint cap included);"
		% (drawn_h / c))
	_line("                       the line above is the nominal UNIT_HEIGHT anchor plates/VFX use")
	_line("   bodies occupy       %.2f%% of the frame on average" % (100.0 * mean_body / c))
	var on_scr := 0.0
	for s2 in _samples:
		on_scr += float(s2["on_screen"])
	_line("   living units IN FRAME %.0f%% on average  ← the camera fits only what it decides to fit"
		% (100.0 * on_scr / c))
	# ── THE FRAME BUDGET. Sorted, so the read is the WORST ONE PER CENT rather than a mean that
	# a single long hitch cannot move. A prettier slideshow is not a legibility win.
	var dts: Array = []
	for s3 in _samples:
		dts.append(float(s3["dt"]))
	dts.sort()
	var dt_sum := 0.0
	for d in dts:
		dt_sum += float(d)
	var p99: float = float(dts[mini(dts.size() - 1, int(float(dts.size()) * 0.99))])
	# ⚠️ READ THE MEDIAN, NOT THE MEAN. This probe saves a 1920x1200 PNG every two sim seconds and
	# that write is a multi-frame stall, so the mean and the 99th percentile both describe the
	# INSTRUMENT as much as the game. The median is the frame the player actually gets.
	var med: float = float(dts[dts.size() / 2])
	_line("   frame time          median %.1f fps · mean %.1f fps · p99 worst %.0f ms  (mean and p99 include this probe's PNG writes)"
		% [1.0 / maxf(0.0001, med), c / maxf(0.0001, dt_sum), p99 * 1000.0])
	# ⚠️ `Performance.TIME_PROCESS` REPORTED 151 ms INSIDE A 35 ms FRAME, so it is not measuring
	# what its name suggests and it is not quoted. Draw calls and node count are unambiguous and
	# they are the two numbers that located the cost, so those are what get printed.
	#
	# ⚠️ AND THE COST IS THE CROWD, MEASURED BY A/B, NOT BY INFERENCE. Same fight, same probe,
	# `spectators.build(..., fill)` at 1.0 vs 0.0:
	#     fill 1.0 → 31 fps median · 2,986 draw calls · 30,111 nodes
	#     fill 0.0 → 144 fps median ·   281 draw calls ·    713 nodes
	# ~1,050 individually instantiated rigged GLB spectators are 4.6x the whole frame budget, and
	# the fight, the director, the pips, the rings, the tethers and the mixer together fit inside
	# the remaining 7 ms with room to spare. Do NOT "fix" this by thinning the house — the full
	# house is a user call ("I want to see all of the seats filled") and fame-driven fill is a
	# standing rule. It is a MultiMesh/impostor job.
	var draws := 0.0
	var objs := 0.0
	for s4 in _samples:
		draws += float(s4["draws"]); objs += float(s4["objs"])
	_line("   scene cost          %.0f draw calls · %.0f nodes  ← the crowd; A/B in this file's comment"
		% [draws / c, objs / c])
	# The last-10-seconds read: does the camera tighten when the fight thins out?
	var late_h := 0.0
	var late_n := 0
	var dur: float = float(_samples[_samples.size() - 1]["t"])
	for s in _samples:
		if float(s["t"]) > dur - 10.0:
			late_h += float(s["mean_h"]); late_n += 1
	if late_n > 0:
		_line("   last 10s            monster height mean %.0f px" % (late_h / float(late_n)))
	var orphan := 0.0
	var collide := 0.0
	var plates := 0.0
	var lies := 0
	var plate_frac := 0.0
	var orphan_drawn := 0.0
	var plate_gap := 0.0
	var gapped := 0.0
	for s in _samples:
		orphan += float(s["orphan"]); collide += float(s["collide"]); plates += float(s["plates"])
		plate_frac += float(s["plate_frac"]); lies += int(s["hud_lies"])
		orphan_drawn += float(s.get("orphan_drawn", 0))
		plate_gap += float(s.get("plate_gap", 0.0)); gapped += float(s.get("gapped", 0))
	var used := 0.0
	var sx := 0.0
	var sy := 0.0
	var used_min := 1e9
	for s3 in _samples:
		used += float(s3["used_frac"]); sx += float(s3["span_x"]); sy += float(s3["span_y"])
		used_min = minf(used_min, float(s3["used_frac"]))
	var gs2: Vector2 = _arena.get("ground_size")
	_line("   ground              %.0f x %.0f world units (%.0f sq units)" % [gs2.x, gs2.y, gs2.x * gs2.y])
	_line("   fight footprint     %.0f x %.0f mean = %.1f%% of the ground (min %.2f%%)"
		% [sx / c, sy / c, 100.0 * used / c, 100.0 * used_min])
	# ── BODY OVERLAP — the round-14 acceptance metric. The sim's rest separations are fixed
	# (enemy push-out 2*BODY_RADIUS = 1.50 world, surround slots 4.8 ground = 1.63 world), so mean
	# overlap depth is a direct read of drawn width vs simulated width. Target: mean under ~10%.
	_line("")
	_line("── D2. BODY OVERLAP — do five bodies read as five bodies? ──")
	_line("   drawn body sizes (world units, sim clears a %.2f-wide disc per body):"
		% (2.0 * _sim_body_radius() * Arena.WORLD_SCALE))
	var names: Array = []
	for m in (_arena.get("all_units") as Array):
		names.append(str(m.species_name))
	for k in range(_body_w.size()):
		var nm: String = names[k] if k < names.size() else str(k)
		_line("     %-12s width %.2f · height %.2f" % [nm, float(_body_w[k]), float(_body_h[k])])
	var ovp := 0.0
	var ovrp := 0.0
	var frames_ov := 0
	for s5 in _samples:
		ovp += float(s5.get("ov_pairs", 0))
		ovrp += float(s5.get("ov_rest_pairs", 0))
		if int(s5.get("ov_pairs", 0)) > 0:
			frames_ov += 1
	if _ov_rest.is_empty() and _ov_rest_ally.is_empty() and _ov_move.is_empty():
		_line("   overlapping pairs   NONE in %d frames — every body reads as its own body" % _samples.size())
	else:
		_line("   AT REST, enemies    %s  ← the acceptance number: standing bodies inside each other"
			% _depth_stats(_ov_rest, "(target: mean under ~10%)"))
		_line("   AT REST, allies     %s  ← the sim's soft-avoid under anchor pressure: a SIM finding"
			% _depth_stats(_ov_rest_ally, ""))
		_line("   crossing            %s  ← allies are PASSABLE by design (#22); this is motion"
			% _depth_stats(_ov_move, ""))
		_line("   overlapping pairs   %.2f per frame (%.2f at rest) · %.0f%% of frames have at least one"
			% [ovp / c, ovrp / c, 100.0 * float(frames_ov) / c])
		if not _ov_episodes.is_empty():
			var names2: Array = []
			for m2 in (_arena.get("all_units") as Array):
				names2.append(str(m2.species_name))
			_line("   deep STANDING overlaps (>50%), by pair and second — a spacing fault, not a drawing one:")
			for ep2 in _ov_episodes.slice(0, 12):
				var e2: Dictionary = ep2
				_line("     t=%5.1fs  %s(%s) inside %s(%s)  centres %.2f world apart"
					% [float(e2["t"]), names2[int(e2["i"])], str(e2["si"]),
					   names2[int(e2["j"])], str(e2["sj"]), float(e2["d"])])
			if _ov_episodes.size() > 12:
				_line("     … and %d more" % (_ov_episodes.size() - 12))
	_line("")
	_line("── D. THE NAMEPLATE, which is the ONLY hp/intent surface the player has ──")
	_line("   plates shown        %.1f on average" % (plates / c))
	_line("   ORPHANED            %.1f per frame (%.0f%%) — lifted more than one body-height from"
		% [orphan / c, 100.0 * orphan / maxf(1.0, plates)])
	_line("                       the head they annotate, so they cannot be attributed")
	_line("   ORPHANED vs DRAWN   %.1f per frame (%.0f%%) - the same question asked of the head the RIG"
		% [orphan_drawn / c, 100.0 * orphan_drawn / maxf(1.0, plates)])
	_line("                       actually drew, not the nominal UNIT_HEIGHT the anchor uses. THIS is")
	_line("                       the number the anchor moves; the one above shares the anchor's error.")
	_line("   mean plate gap      %.2f drawn body-heights from the head it annotates (0 = on the head)"
		% (plate_gap / maxf(1.0, gapped)))
	var unames: Array = []
	for m3 in (_arena.get("all_units") as Array):
		unames.append(str(m3.species_name))
	_line("   per unit (drawn body height -> mean gap -> orphaned):")
	for k3 in range(_per_unit_n.size()):
		if float(_per_unit_n[k3]) <= 0.0:
			continue
		_line("     %-12s h=%.2f world   gap %.2f bodies   orphaned %.0f%%"
			% [unames[k3] if k3 < unames.size() else str(k3),
			   float(_body_h[k3]) if k3 < _body_h.size() else 0.0,
			   float(_per_unit_gap[k3]) / float(_per_unit_n[k3]),
			   100.0 * float(_per_unit_orph[k3]) / float(_per_unit_n[k3])])
	_line("   OVERLAPPING pairs   %.1f per frame — two plates sharing pixels are both unreadable"
		% (collide / c))
	_line("   plates occupy       %.2f%% of the frame vs %.2f%% for the bodies (ratio %.1fx)"
		% [100.0 * plate_frac / c, 100.0 * mean_body / c,
		   (plate_frac / maxf(0.0001, mean_body))])
	_line("")
	_line("── E. THE SCOREBOARD ──")
	_line("   frames where the standing HUD disagrees with the frame on screen: %d of %d (%.0f%%)"
		% [lies, _samples.size(), 100.0 * float(lies) / c])
	_line("   strip               %d frames -> %s" % [_shot, ProjectSettings.globalize_path("user://")])
	# ── F. THE MIX. ⚠️ A TRIPWIRE, NOT A NICETY. `docs/WATCH_AUDIT.md` §5 found 700 lines of
	# mix engineering that the production watch path never called, and the failure was completely
	# invisible from the outside: the scene ran, the probes passed, and the fight was silent. The
	# only honest question about a mix is what the LISTENER actually heard, and that is a count.
	# It reads the layer's own audit counters, so a wiring that goes stale reports zero rather
	# than passing quietly. Headless runs on the dummy driver — this proves the events REACHED
	# the mixer and were graded, never that anything sounded good.
	var au = _arena.get("_audio")
	if au == null:
		_line("── F. THE MIX ──")
		_line("   ⚠️ NO AUDIO LAYER ON THE PRODUCTION WATCH PATH — the fight is silent")
	else:
		var ev: Dictionary = au.get("stat_events")
		var pl: Dictionary = au.get("stat_played")
		var rf: Dictionary = au.get("stat_refused")
		var n_ev := 0
		for v in ev.values():
			n_ev += int(v)
		var n_pl := 0
		for v in pl.values():
			n_pl += int(v)
		var n_rf := 0
		for v in rf.values():
			n_rf += int(v)
		_line("── F. THE MIX ──")
		_line("   events reaching the mixer %d across %d kinds" % [n_ev, ev.size()])
		_line("   cues played %d · refused by the density gate %d · cast rises cut %d"
			% [n_pl, n_rf, int(au.get("stat_cut"))])
		var keys: Array = pl.keys()
		keys.sort()
		var parts: Array = []
		for k in keys:
			parts.append("%s=%d" % [k, int(pl[k])])
		_line("   " + " ".join(parts))
	_report_aoe(mean_h / c / Arena.UNIT_HEIGHT, drawn_h / c)
	if _canary_failed:
		_line("")
		_line("*** A CANARY FAILED - this run exits non-zero. See the section that named it. ***")
	_capture_endings()


## THE POST-FIGHT READ — the third watch surface, and the one that is supposed to answer "was my
## read right". Captured here because a report nobody has looked at is exactly as unproven as a
## fight nobody has watched.
func _capture_endings() -> void:
	for i in range(180):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://watch_%s_END.png" % _tag)
	# Hand the real result to the real report screen, exactly as `arena_3d._finish()` does.
	_arena.visible = false
	var rep: Node = (load("res://scenes/report.tscn") as PackedScene).instantiate()
	add_child(rep)
	rep.call("set_battle_result", _arena.get("result"), _arena.get("team_a"), _arena.get("team_b"))
	for i in range(60):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://watch_%s_REPORT.png" % _tag)
	_line("   endings             watch_%s_END.png · watch_%s_REPORT.png" % [_tag, _tag])
	_dump()
	get_tree().quit(1 if _canary_failed else 0)


func _line(s: String) -> void:
	_out.append(s)


func _dump() -> void:
	for s in _out:
		print(s)
