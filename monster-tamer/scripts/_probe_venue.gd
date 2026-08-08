## THE VENUE LOOK PROBE — boots the REAL battle screen and LOOKS at it.
##
## Run WINDOWED (rendering is the whole point; `--headless` has no framebuffer to read):
##   P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/_probe_venue.tscn
##
## ⚠️ WHY A SEPARATE PROBE FROM `_probe_arena_rig.gd`. That one measures the CAMERA — how much of
## the frame the bodies fill and where they sit. This one measures the LIGHTING AND VALUE
## STRUCTURE, which is a different failure: a perfectly framed fight on a blinding floor is still
## unreadable. The specific complaint it exists to answer is "the ground is blinding and the
## creatures are not the brightest things on screen" — so it samples the floor and the bodies from
## the SAME rendered frame and reports the ratio, rather than trusting a material value in code
## (albedo is not luminance once a light, an ambient term and a tonemap have had their say).
##
## It also sweeps every league, because the ground texture and the lamp both change per league and
## a value structure that works on Wood can blow out on Platinum's marble — which is exactly what
## happened.
##
## ═══════════════════════════════════════════════════════════════════════════════════════════════
## ⚠️ THE 2026-08-08 INSTRUMENT REPAIR — READ THIS BEFORE TRUSTING ANY NUMBER BELOW
## ═══════════════════════════════════════════════════════════════════════════════════════════════
## A broken instrument is worse than no instrument: it launders a guess into a number, and every
## art decision downstream then leans on it. Three faults were found and fixed here. Each fix is
## marked ⚠️ REPAIR at its site.
##
## REPAIR 1 — THE CAPTURE WAS TAKEN ON A WALL-CLOCK FRAME, NOT A SIM TICK. The old code played the
##   replay and polled `frame_pos` from `_process`, so the photographed instant depended on how
##   fast the machine happened to render; the bodies were wherever they happened to be, at whatever
##   phase their walk cycle happened to be at. Two lamp decisions last round had to be judged over
##   repeated runs because of it. The capture is now PINNED: a deterministic quiet tick is chosen
##   from the frame stream, applied directly, transients are allowed to COMPLETE, the scene is then
##   frozen and every animation clock is driven to a fixed phase with fixed deltas. `_pin_and_freeze`.
##   The evidence it worked is printed: `CAPTURE DETERMINISM` reports the frame-to-frame deviation
##   across three grabs of the frozen venue, which must be 0.0000.
##
## REPAIR 2 — THE PER-KIND PROP SAMPLER WAS NOT SAMPLING THE PROPS. It unprojected the prop's top
##   face and averaged the brightest third of a 5x5 patch. In the shipping ARENA frame a soft cover
##   piece is 0.42 creature-heights tall and a creature is about ten pixels — so a crate is roughly
##   FOUR PIXELS and that patch is mostly the floor behind it. Floor pixels do not move when a
##   crate's tint moves, which is exactly the reported symptom: crate frozen at 0.477 and planter
##   at 0.243 to three decimals across seven runs and five different tints. The sampler now
##   ATTRIBUTES pixels the same way the layer pass does — hide the kind, diff two frames, and use
##   only the pixels that actually changed — and reports how many pixels it resolved, so a thin
##   sample is visible rather than silently substituted. `_kind_stats`.
##
## REPAIR 3 — NOTHING PROVED ANY MEASURE COULD MOVE AT ALL. A probe that cannot fail is not a
##   probe. `_self_test` now perturbs each measure's own input (an unshaded flat material on the
##   ground, on the bodies, on each prop kind in turn) and asserts the number responds. Every
##   measure is listed in the `SELF-TEST` table as RESPONDS or FROZEN. A kind is only tested until
##   it has been proven once — the sweep is long enough already.
extends Node

const TacticsScript = preload("res://scripts/tactics.gd")
const ARENA_SCENE := "res://scenes/arena3d.tscn"

## Leagues with their own authored ground art (`Art.ARENA_LEAGUES`) — the ones whose value can
## actually differ.
##
## ⚠️ THIS LIST WAS FIVE AND IS NOW ELEVEN, AND THE STALENESS HID REAL FAILURES. The old comment
## read "sweeping all eleven would re-shoot the same five textures", which was true when six
## leagues borrowed their venue from a lower rung. It stopped being true the moment the missing
## six were painted — and those six were then the only leagues in the game whose value structure
## had never been measured, including the three with the BRIGHTEST `ground` multipliers in
## `arena_3d.gd:LEAGUE_LOOK` (Iron 0.92, Masters 0.92, Tamer Elite 0.90). An instrument that
## samples a fixed subset silently stops covering the thing it was built to cover.
##
## Keep this mirroring `Art.ARENA_LEAGUES`. If a league has its own ground texture, its lighting
## is its own problem and must be photographed.
const SWEEP := [
	"Wood", "Copper", "Tin", "Bronze", "Iron", "Silver",
	"Gold", "Platinum", "Masters", "Tamer Elite", "Tamers Apex",
]

var _rows: Array = []
## One row per league from the GAMEPLAY frame — the composition/value pass. See `_shoot`.
var _shots: Array = []
## Every prop row seen across the sweep, for the proportion table.
var _props: Array = []
## kind -> Array[float] of measured lit-face luminances, for the tint table.
var _kind_luma: Dictionary = {}
## ⚠️ AND kind -> SATURATION, BECAUSE VALUE IS NOT THE ONLY CHANNEL. The brick walls measured
## perfectly in band on luminance and were still the loudest object in the frame — they are a
## saturated orange on a brown floor. `ART_BIBLE_GUILD_COLOURS.md` reserves chroma for the team and
## status channels, so a prop out-saturating the creatures is the same defect as one out-valuing
## them, and an instrument that only measures luminance cannot see it.
var _kind_sat: Dictionary = {}
var _body_sat: Array = []
## kind -> {"placed": int, "resolved": int, "pixels": int} — how much of what was BUILT the sampler
## could actually find on screen. See REPAIR 2.
var _kind_cover: Dictionary = {}
## One row per capture: pin tick, whether it was quiet, and the measured frame-to-frame deviation.
var _pins: Array = []
## Self-test rows: {"measure", "league", "before", "after", "delta", "ok"}.
var _selftest: Array = []
## kind -> true once its luminance has been PROVEN to respond to its own material.
var _kind_proven: Dictionary = {}
## One row per league identifying WHICH BOARD AND WHICH FIGHT was photographed. See `_report_scene`.
var _scenes: Array = []

## ⚠️ THE PROPORTION BAR, AND WHY IT IS 3.0. A cover piece is drawn `max(w, d)` long and `h` tall,
## and the report this pass answers was "crates read as brick loaves roughly three monsters long".
## Long-over-tall is that complaint as a number. Below ~2.0 a piece reads as an object; a wall run
## is legitimately 2-3 (it is a wall); past 3.0 it reads as something spilled on the floor, and the
## measured board had blocking majors at 4.2 and soft crates at 2.2 with no wall-ness to earn it.
const LOAF_RATIO := 3.0
## A soft piece taller than this is not "cover you shoot over" any more (ARENA_DESIGN.md §4, in
## creature heights: its 3.4 cap was written against a ~2.0-unit body).
const COVER_MAX_BODIES := 1.7

## ── PIN CONSTANTS (REPAIR 1) ────────────────────────────────────────────────────────────────────
## Where in the frame stream to photograph. A third of the way in is reliably mid-fight at every
## team size; the exact tick is then nudged forward to the first QUIET one (see `_pin_tick`).
const PIN_FRACTION := 0.34
## How far forward the search for a quiet tick may run before giving up and taking the nominal one.
const PIN_SEARCH := 60
## Frames allowed to elapse, unfrozen, so one-shot transients started by the pinned tick (a topple
## tween, a smoke burst, a camera lerp) reach their END STATE. A transient that has COMPLETED is
## deterministic; one caught mid-flight is not. This is the only wall-clock wait left and it is
## deliberately generous.
const SETTLE_FRAMES := 48
## The animation phase every body is driven to before the shutter opens, in seconds. Any fixed
## value works; what matters is that it is the SAME one every run.
const PIN_ANIM_T := 0.37
## Fixed-delta steps used to drive exponential lerps (facing, torso twist) to convergence without
## consuming any wall-clock time. 24 steps of 0.1s against `exp(-12*dt)` leaves ~1e-12.
const CONVERGE_STEPS := 24
const CONVERGE_DT := 0.1


func _ready() -> void:
	for league in SWEEP:
		await _shoot(league)
	_report_scene()
	# ⚠️ AND THE REST OF THE REPORT IS SUPPRESSED ENTIRELY, not printed with zeros in it. Every
	# summary line below counts failures out of a total, so an empty sweep renders as a page of
	# "0/0 ... correctly" — which reads exactly like a pass and is how a broken instrument launders
	# a build failure into a green result.
	if _scenes.is_empty():
		get_tree().quit(1)
		return
	_report_capture()
	_report_value()
	_report_proportion()
	_report_composition()
	_report_selftest()
	get_tree().quit()


## ── PASS -1 — WHICH BOARD AND WHICH FIGHT DID WE PHOTOGRAPH?
##
## ⚠️ THIS TABLE EXISTS BECAUSE THE ONE BELOW IT IS NOT ENOUGH, AND THE DIFFERENCE BETWEEN THEM IS
## THE DIFFERENCE BETWEEN TWO KINDS OF DETERMINISM. `CAPTURE DETERMINISM` proves the SHUTTER is
## pinned — that the same scene, photographed three times, gives the same pixels. It says nothing
## about whether the same SCENE was built. Those are separate failures and only one of them was
## being watched.
##
## ⚠️ AND IT IS NOT WATCHED IDLY: RUN-TO-RUN DIVERGENCE WAS MEASURED HERE ON 2026-08-08. Three
## sweeps of identical code produced 284, 164 and 302 obstacle rows, with the Masters fight running
## 192 ticks in one run and 201 in another. The per-kind value table is a median over every piece in
## the sweep, so a board that changes between runs silently changes the POPULATION every number is
## taken over — an art decision made on "pillar reads 0.24" is then a decision about whichever
## pillars happened to exist that afternoon.
##
## ⚠️ THE CAUSE IS NOT IN THIS FILE and must not be papered over from here. `_obstacles` is
## overwritten from the SIM's own result (`arena_3d.gd:696`), the fight seed is a pure hash of
## week/league/round, and one of the divergent runs logged a `nav_service.gd:49` failure — so the
## live suspicion is that navmesh build failure (or GPU resource pressure across an 11-venue sweep)
## changes which obstacles survive, which changes the fight, which changes the board. Whoever owns
## `nav_service.gd` / `arena_layout.gd` should read `hash` below across two runs before trusting any
## per-kind aggregate. The instrument's job is to make the divergence VISIBLE, which is all it does.
## Where the board fingerprint is remembered between runs. Delete it after an INTENTIONAL layout
## change; every run will otherwise report drift against the old boards forever.
const BOARD_GOLDEN := "user://venue_board_golden.json"

func _report_scene() -> void:
	print("")
	print("═══ SCENE FINGERPRINT (which board, which fight) ═══")
	# ⚠️ AN EMPTY SWEEP MUST NOT READ AS A CLEAN ONE. Before this guard, a sweep in which the arena
	# script failed to parse produced eleven screens of Nil errors and then the cheerful line
	# "0/0 boards match the golden". That is the single worst thing an instrument can do — this
	# project has already had a probe pass 9/9 while the thing it tested did not exist — so a sweep
	# that photographed nothing says so, first, in its own words.
	if _scenes.is_empty():
		print("⚠️ NOTHING WAS PHOTOGRAPHED. Every league failed to build — see the errors above.")
		print("   Do not read the tables below: they are empty, not passing.")
		return
	# ⚠️ THE GOLDEN IS THE POINT, NOT THE TABLE. Printing a hash only helps someone who thought to
	# save the previous run's output and diff it by hand — which is to say it helps nobody. The
	# probe remembers its own subject and says, on every run, whether it photographed the same
	# eleven boards it photographed last time.
	var golden: Dictionary = {}
	var had_golden := false
	if FileAccess.file_exists(BOARD_GOLDEN):
		var f := FileAccess.open(BOARD_GOLDEN, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				golden = parsed
				had_golden = true
	print("league          layout                    obstacles  ticks   board hash   vs golden")
	var drift := 0
	var fresh: Dictionary = {}
	for s in _scenes:
		var key := str(s["league"])
		var h := int(s["hash"])
		fresh[key] = h
		var verdict := "(new)"
		if had_golden and golden.has(key):
			if int(golden[key]) == h:
				verdict = "match"
			else:
				verdict = "DRIFTED"
				drift += 1
		print("%-14s  %-24s %9d  %5d   %10d   %s" % [
			key, s["layout"], int(s["obstacles"]), int(s["ticks"]), h, verdict])
	if not had_golden:
		var w := FileAccess.open(BOARD_GOLDEN, FileAccess.WRITE)
		if w != null:
			w.store_string(JSON.stringify(fresh))
		print("")
		print("captured board golden -> %s" % ProjectSettings.globalize_path(BOARD_GOLDEN))
		return
	print("")
	if drift == 0:
		print("%d/%d boards match the golden — every table below is over the same population as last run"
			% [_scenes.size(), _scenes.size()])
		return
	# ⚠️ WHAT DRIFT MEANT THE FIRST TIME IT FIRED, AND WHY THE OBVIOUS READING WAS WRONG.
	# MEASURED 2026-08-08 over six sweeps. Two entirely different boards came out:
	#     board X   Wood 12 · Copper 14 · Tin 16 · Bronze 20 · Iron 22 ... Tamers Apex 44
	#     board Y   Wood 18 · Copper 20 · Tin 22 · Bronze 30 · Iron 24 ... Tamers Apex 52
	# differing in piece COUNT, in piece SIZE (`low_wall` 2.98 vs 2.86 bodies wide) and in the
	# resulting FIGHT (Iron 113 ticks vs 101, Masters 192 vs 201).
	#
	# ⚠️ THE TEMPTING CONCLUSION — "the board build is not reproducible" — WAS NOT THE RIGHT ONE,
	# and writing it down as a finding would have sent someone hunting a nav-determinism bug that
	# is not there. Back-to-back sweeps of an UNCHANGED tree matched to the last digit; the boards
	# only moved BETWEEN sweeps, and a later run caught the actual cause in the log: a parse error
	# for `_cover_architecture()` in `arena_3d.gd`, i.e. the board-composition workstream editing
	# that file while this probe was reading it. Board X and board Y are their before and after.
	#
	# The lesson the golden encodes: when a measurement moves, the FIRST question is whether the
	# thing being measured changed, and a probe that cannot answer that question leaves everyone
	# guessing. Genuine non-reproducibility would look different — drift between two runs with no
	# edit in between — and this line is what would show it.
	print("⚠️ %d/%d BOARDS DRIFTED FROM THE GOLDEN. This run did not measure the same arenas as the"
		% [drift, _scenes.size()])
	print("   last one, so no table below it can be compared with a previous run's. Either the")
	print("   layout was changed on purpose — delete %s and re-baseline —" % BOARD_GOLDEN)
	print("   or the board build is not reproducible, which is a bug in the arena, not in the probe.")


## A stable fingerprint of the board: kind, grade and drawn geometry of every piece, order-independent.
func _board_hash(rows: Array) -> int:
	var parts: Array = []
	for p in rows:
		var c: Vector3 = p["centre"]
		parts.append("%s|%s|%.2f|%.2f|%.2f|%.2f|%.2f" % [
			str(p["kind"]), str(p["grade"]), c.x, c.z, float(p["w"]), float(p["d"]), float(p["h"])])
	parts.sort()
	return hash(parts)


## ── PASS 0 (REPAIR 1) — DID THE SHUTTER LAND ON THE SAME FRAME EVERY TIME?
##
## ⚠️ THIS IS THE TABLE THAT DECIDES WHETHER ANY OTHER TABLE MEANS ANYTHING. `dev` is the largest
## per-pixel luminance change between three grabs of a venue nobody is touching. If it is not
## 0.0000 the scene is still moving and every number below it is a sample of a moving target — the
## exact fault this repair exists to remove. `quiet` says the pinned tick had no shots landing and
## nobody casting, so no VFX one-shot was in flight when the shutter opened.
func _report_capture() -> void:
	print("")
	print("═══ CAPTURE DETERMINISM (pinned sim tick, frozen scene) ═══")
	print("league          tick/total  quiet  settle-dev  frozen-dev  noise p99.5")
	var moving := 0
	for p in _pins:
		var ok: bool = float(p["frozen_dev"]) <= 0.0005
		if not ok:
			moving += 1
		print("%-14s  %5d/%-5d %-6s %10.4f  %10.4f  %10.4f  %s" % [
			p["league"], int(p["tick"]), int(p["total"]), "yes" if bool(p["quiet"]) else "NO",
			float(p["settle_dev"]), float(p["frozen_dev"]), float(p["noise"]),
			"" if ok else "STILL MOVING"])
	print("")
	print("%d/%d captures are frozen (max per-pixel deviation over 3 grabs <= 0.0005)"
		% [_pins.size() - moving, _pins.size()])


## ── PASS 1 — the value check. Unchanged in what it asks; repaired in how it samples.
##
## ⚠️ `floor(diff)` IS THE MEASURE; `floor(grid)` IS THE OLD ONE, KEPT AS A CROSS-CHECK. The grid
## sampler unprojects an 11x9 lattice of ground points and takes a median, which lands on whatever
## happens to be at those points — a VFX ground decal, a prop, a shadow. The diff sampler hides the
## `Ground` nodes and uses only the pixels that changed, which is the ground and nothing else. When
## the two columns disagree, something large and non-ground is sitting on the board and the grid
## number is the one lying. Printing both is how that stays visible instead of becoming a mystery.
func _report_value() -> void:
	print("")
	print("═══ VALUE (metric frame, span 26) ═══")
	print("league          frame   floor   body   body/floor   verdict   | floor(grid)  body(patch)")
	var bad := 0
	for r in _rows:
		var ratio: float = r["body"] / maxf(0.001, r["floor"])
		# The bodies must out-value the ground they stand on. 1.0 is parity — a body that reads
		# exactly as bright as the floor has no value separation at all and relies on hue alone.
		var ok: bool = ratio >= 1.12 and r["floor"] <= 0.62
		if not ok:
			bad += 1
		print("%-14s  %.3f   %.3f   %.3f   %.2f         %-8s  | %10.3f  %10.3f" % [
			r["league"], r["frame"], r["floor"], r["body"], ratio, "ok" if ok else "FAIL",
			float(r["floor_grid"]), float(r["body_patch"])])
	print("")
	print("%d/%d leagues read correctly (body out-values floor by >=12%%, floor luma <= 0.62)"
		% [_rows.size() - bad, _rows.size()])


## ── PASS 2 — PROP PROPORTION, measured in creature heights.
##
## ⚠️ THE YARDSTICK IS `UNIT_HEIGHT`, NOT WORLD UNITS, because the complaint was stated that way
## ("three monsters long") and because world units are meaningless to an eye: the same 13.5-unit
## wall is a barricade next to a 4.4-unit creature and a kerb next to a 40-unit one. Everything
## here comes from `arena_3d.gd:prop_report()`, which is the renderer's own arithmetic — the probe
## never re-derives a drawn size.
func _report_proportion() -> void:
	print("")
	print("═══ PROP PROPORTION (yardstick: UNIT_HEIGHT = one creature) ═══")
	print("kind             n  grade     w(bodies) d(bodies) h(bodies)  long/tall  segs   verdict")
	var by_kind: Dictionary = {}
	for p in _props:
		var k: String = str(p["kind"])
		if not by_kind.has(k):
			by_kind[k] = []
		by_kind[k].append(p)
	var keys: Array = by_kind.keys()
	keys.sort()
	var bad := 0
	for k in keys:
		var rows: Array = by_kind[k]
		var w := 0.0
		var d := 0.0
		var h := 0.0
		var lt := 0.0
		var sx := 0
		var sz := 0
		for p in rows:
			w += float(p["w_bodies"]); d += float(p["d_bodies"]); h += float(p["h_bodies"])
			lt = maxf(lt, float(p["long_over_tall"]))
			sx = maxi(sx, int((p["segments"] as Vector2i).x))
			sz = maxi(sz, int((p["segments"] as Vector2i).y))
		var n := float(rows.size())
		var grade: String = str(rows[0]["grade"])
		var hb: float = h / n
		# ⚠️ THE BAR IS GRADE-AWARE, AND THE FIRST VERSION OF IT WAS NOT — IT SCORED THE ONE THING
		# THE DESIGN EXPLICITLY WANTS AS A DEFECT. A flat `long/tall <= 3.0` failed `low_wall` at
		# 7.5, but `ARENA_DESIGN.md` §3 says "fewer and larger, always" and `ArenaLayout`'s
		# `MAJOR_MIN_BODIES` deliberately makes a blocking major nine bodies of frontage so it can
		# shelter a whole line. A nine-body wall IS 7.5 : 1 and is correct.
		#
		# What separates a wall from a loaf is not length, it is HEIGHT AGAINST THE CREATURE. A
		# long thing shorter than the monster beside it reads as something spilled on the floor; a
		# long thing taller than the monster reads as architecture. So:
		#   blocking — must be OVER the creature's head (>= 1.0 bodies); length is unbounded
		#   soft/hard — must be an object, not a slab (long/tall <= 3.0), and under the cover cap
		var ok: bool
		var why := "ok"
		if grade == "blocking":
			ok = hb >= 1.0 and hb <= COVER_MAX_BODIES
			why = "ok" if ok else ("NOT A WALL (under head height)" if hb < 1.0 else "TOO TALL")
		else:
			ok = lt <= LOAF_RATIO and hb <= COVER_MAX_BODIES
			why = "ok" if ok else ("LOAF" if lt > LOAF_RATIO else "TOO TALL")
		if not ok:
			bad += 1
		print("%-14s %3d %-9s %6.2f    %6.2f    %6.2f     %5.2f    %dx%d   %s" % [
			k, rows.size(), grade, w / n, d / n, hb, lt, sx, sz, why])
	print("")
	print("%d/%d kinds in proportion (blocking >= 1.0 creature tall; other cover <= %.1f : 1 and <= %.1f creatures)"
		% [keys.size() - bad, keys.size(), LOAF_RATIO, COVER_MAX_BODIES])


## ── PASS 3 — COMPOSITION AND THE VALUE LADDER, both from the SHIPPING frame.
##
## ⚠️ THIS IS A DIFFERENT FRAME FROM PASS 1 ON PURPOSE. Pass 1 photographs a fixed 26-unit span so
## eleven leagues are comparable; that frame is an instrument and no player ever sees it. "The
## stands are cropped" and "the props are the brightest thing on the board" are claims about the
## frame the game actually renders, so they have to be measured there.
##
## ⚠️ AND THE LAYERS ARE SEPARATED BY VISIBILITY DIFF, NOT BY CLASSIFYING PIXELS. Asking "is this
## pixel stand or floor?" from colour is a heuristic that fails exactly when a tint change makes
## them similar — i.e. at the moment the measurement matters. Hiding one named node and diffing two
## frames gives the node's screen coverage EXACTLY, and the luminance of those same pixels in the
## unmodified frame is that layer's value with no sampling geometry to get wrong.
func _report_composition() -> void:
	print("")
	print("═══ COMPOSITION + VALUE LADDER (shipping frame) ═══")
	print("league          stands%  props%  floor%  empty%   |  stands  walls  floor  cover  body   ladder")
	var bad_ladder := 0
	var thin := 0
	for s in _shots:
		# The ladder the direction asks for: stands < walls < floor < cover < creatures. Cover
		# sitting ABOVE the creatures is the specific failure reported this round.
		var lad: Array = [s["l_stands"], s["l_walls"], s["l_floor"], s["l_props"], s["l_body"]]
		var ladder_ok := true
		for i in range(lad.size() - 1):
			# A layer absent from the frame reads as -1 and is skipped rather than failing.
			if float(lad[i]) < 0.0 or float(lad[i + 1]) < 0.0:
				continue
			if float(lad[i]) > float(lad[i + 1]) + 0.005:
				ladder_ok = false
		if not ladder_ok:
			bad_ladder += 1
		# "The stands are cropped to a thin band" as a number: what fraction of the frame is venue.
		var stands_ok: bool = float(s["f_stands"]) >= 0.06
		if not stands_ok:
			thin += 1
		print("%-14s  %5.1f    %5.1f   %5.1f   %5.1f   |  %5.3f  %5.3f  %5.3f  %5.3f  %5.3f  %s%s" % [
			s["league"], float(s["f_stands"]) * 100.0, float(s["f_props"]) * 100.0,
			float(s["f_floor"]) * 100.0, float(s["f_empty"]) * 100.0,
			float(s["l_stands"]), float(s["l_walls"]), float(s["l_floor"]),
			float(s["l_props"]), float(s["l_body"]),
			"ok" if ladder_ok else "LADDER", "" if stands_ok else " THIN-STANDS"])
	print("")
	print("%d/%d leagues hold the value ladder (stands < walls < floor < cover < creatures)"
		% [_shots.size() - bad_ladder, _shots.size()])
	print("%d/%d leagues show their venue (stands >= 6%% of the frame)" % [_shots.size() - thin, _shots.size()])

	# ── PER-KIND PROP VALUE, the table the tints are actually set from.
	#
	# ⚠️ THE COMPARISON IS AGAINST THE FLOOR AND AGAINST THE CREATURES, because "too bright" is a
	# RELATION, not a number: a pale pillar is fine on a pale floor and wrong on a dark one, and the
	# grand-circuit grounds were darkened last round without the props following. A kind wants to
	# sit a little ABOVE the floor (it is an object standing on the ground, not a stain) and clearly
	# BELOW the creatures (`ART_DIRECTION.md`: the cast is the brightest thing on screen, always).
	var floor_med := 0.0
	var body_med := 0.0
	var fl: Array = []
	var bl: Array = []
	for s in _shots:
		fl.append(s["l_floor"]); bl.append(s["l_body"])
	if not fl.is_empty():
		floor_med = _median(fl)
		body_med = _median(bl)
	print("")
	print("═══ PROP VALUE BY KIND (attributed pixels; floor %.3f, creatures %.3f) ═══" % [floor_med, body_med])
	var body_sat: float = _median(_body_sat) if not _body_sat.is_empty() else 1.0
	print("cast saturation %.3f — a prop above it is shouting over the channel the bible reserves"
		% body_sat)
	# ⚠️ `found` IS PART OF THE MEASUREMENT, NOT DECORATION. It is the share of BUILT pieces whose
	# own pixels the sampler could actually resolve on screen, and `px` is the median number of
	# pixels behind each of those samples. This is REPAIR 2's receipt: the old sampler reported a
	# confident number for every piece because it never checked whether it had hit one, which is how
	# crate and planter came back frozen. A kind at low `found` or a handful of `px` is a kind whose
	# luminance is thin evidence — say so rather than tune against it.
	print("kind             n  found   px    luma   vs floor   vs body    sat   sat/cast  verdict")
	var kk: Array = _kind_luma.keys()
	kk.sort()
	var hot := 0
	for k in kk:
		var arr: Array = _kind_luma[k]
		var m := _median(arr)
		var vf: float = m / maxf(0.001, floor_med)
		var vb: float = m / maxf(0.001, body_med)
		var sm: float = _median(_kind_sat[k])
		var vs: float = sm / maxf(0.001, body_sat)
		var cov: Dictionary = _kind_cover.get(k, {"placed": 0, "resolved": 0, "pixels": []})
		var found: float = float(int(cov["resolved"])) / maxf(1.0, float(int(cov["placed"])))
		var px: float = _median(cov["pixels"]) if not (cov["pixels"] as Array).is_empty() else 0.0
		# Above 0.80 of the creatures' value a prop is competing with them for the eye; below 1.02
		# of the floor it has stopped reading as an object standing on the ground; above 0.85 of
		# their saturation it is competing on the OTHER channel instead.
		# ⚠️ THE CHROMA COLUMN IS ADVISORY AND MUST STAY THAT WAY UNTIL IT IS DECONFOUNDED. Absolute
		# saturation in this scene is dominated by the LAMP, not the material: the key is a strongly
		# warm (1.00, 0.87, 0.66) and the ambient a cool blue, so plain grey stone renders at ~0.70
		# saturation and the number says almost nothing about the prop's own colour. It caught the
		# one thing it can catch — `low_wall_border`'s saturated brick, which fell 0.55 -> 0.25 once
		# tinted — and it should not be tuned against beyond that. Deconfounding it means sampling
		# the FLOOR's saturation as the reference (same lamp, same surface class) rather than the
		# creatures'; worth doing, not worth blocking this pass on.
		var ok: bool = vb <= 0.80 and vf >= 1.02
		if not ok:
			hot += 1
		var why := "ok"
		if vb > 0.80:
			why = "OUT-VALUES CAST"
		elif vf < 1.02:
			why = "SINKS INTO FLOOR"
		if vs > 1.15:
			why += " (loud)"
		if found < 0.5:
			why += " [THIN SAMPLE]"
		print("%-14s %3d %5.0f%% %4d   %.3f    %5.2f     %5.2f   %.3f   %5.2f    %s" % [
			k, arr.size(), found * 100.0, int(px), m, vf, vb, sm, vs, why])
	print("")
	print("%d/%d kinds sit correctly between floor and cast on VALUE (chroma column is advisory)"
		% [kk.size() - hot, kk.size()])

	# ── THE KINDS THAT COULD NOT BE MEASURED AT ALL, AND THE NUMBER THAT EXPLAINS THEM.
	#
	# ⚠️ THIS TABLE IS THE HONEST VERSION OF WHAT THE OLD SAMPLER WAS DOING SILENTLY. It reported a
	# confident luminance for every one of these kinds by averaging the FLOOR BEHIND THEM, which is
	# why crate and planter never moved. They are absent from the table above because the sampler
	# now refuses to invent a number for something it cannot find, and the reason it cannot find
	# them is printed here: at gameplay distance the camera draws them a handful of pixels tall.
	#
	# ⚠️ AND THAT IS ITSELF AN ART FINDING, NOT JUST AN INSTRUMENT LIMIT. A prop the shipping camera
	# resolves at four pixels cannot carry value, hue or silhouette — it can only add speckle. The
	# integrator's "the accent layer is debris, not architecture" is the same observation arrived at
	# by eye; this is it in pixels. Do not answer it by tinting these kinds, and do not answer it by
	# moving the camera to suit the probe.
	var missing: Array = []
	for k in _kind_cover.keys():
		if not _kind_luma.has(k) or (_kind_luma[k] as Array).is_empty():
			missing.append(k)
	missing.sort()
	if not missing.is_empty():
		print("")
		print("═══ KINDS THE SHIPPING CAMERA CANNOT RESOLVE (no attributed pixels, so NO value reported) ═══")
		print("kind             placed  off-frame  unkeyed  drawn h  instances  keyed px  hidden px  nodes")
		for k in missing:
			var cov: Dictionary = _kind_cover[k]
			var hs: Array = cov["px_h"]
			var off: int = int(cov.get("offscreen", 0))
			print("%-14s %7d  %9d  %7d  %5.1fpx  %9d  %8d  %9d  %s" % [
				k, int(cov["placed"]), off, int(cov["placed"]) - off,
				_median(hs) if not hs.is_empty() else -1.0,
				int(cov.get("insts", 0)), int(cov.get("frame_px", 0)),
				int(cov.get("hidden_px", 0)), str(cov.get("nodes", ""))])
		print("   'hidden px' = pixels that change when the kind's nodes are hidden outright.")
		print("   0 keyed but hidden > 0  -> it draws; `material_override` does not reach it. A PROBE bug.")
		print("   0 keyed AND 0 hidden    -> it contributes NOTHING to the frame: either never drawn, or")
		print("                              wholly occluded in every frame sampled. Not a probe bug —")
		print("                              the probe's own controls key 290-2674 px on the same frames.")
		# For scale: what a kind that DOES resolve keys over the same frame.
		var ref: Array = []
		for k in _kind_cover.keys():
			if _kind_luma.has(k) and not (_kind_luma[k] as Array).is_empty():
				ref.append("%s %d" % [k, int(_kind_cover[k].get("frame_px", 0))])
		ref.sort()
		print("   for scale, keyed px/frame of the kinds that DO resolve: %s" % ", ".join(ref))


## ── PASS 4 (REPAIR 3) — CAN EACH MEASURE MOVE AT ALL?
##
## ⚠️ THIS IS THE PASS THAT WOULD HAVE CAUGHT THE FROZEN CRATE ON DAY ONE. Every row perturbs one
## measure's own input — an unshaded flat white material on the thing being measured — and reads
## the SAME sampler back. A measure that does not move when its material is replaced with pure
## white is not measuring that material; it is measuring something else and reporting it under the
## wrong name. There is no bar to argue about here: the perturbation is the largest one available.
func _report_selftest() -> void:
	print("")
	print("═══ SELF-TEST — does each measure MOVE when its input moves? ═══")
	print("measure                league          before   after    delta   verdict")
	var frozen := 0
	for r in _selftest:
		if not bool(r["ok"]):
			frozen += 1
		print("%-22s %-14s  %6.3f  %6.3f  %6.3f   %s" % [
			r["measure"], r["league"], float(r["before"]), float(r["after"]),
			float(r["after"]) - float(r["before"]), "RESPONDS" if bool(r["ok"]) else "FROZEN"])
	var untested: Array = []
	for k in _kind_cover.keys():
		if not bool(_kind_proven.get(k, false)):
			untested.append(k)
	untested.sort()
	print("")
	print("%d/%d measures respond to a flat-white perturbation of their own input"
		% [_selftest.size() - frozen, _selftest.size()])
	if not untested.is_empty():
		print("⚠️ NEVER PROVEN RESPONSIVE: %s — treat their luminance as unverified"
			% ", ".join(untested))


func _setup_state(league_name: String) -> int:
	# ⚠️ SEED THE GLOBAL RNG OR THIS PROBE IS NOT AN INSTRUMENT. `Roster._generate_starting_roster()`
	# and `CupRun.current_rival_team()` do not draw from the fight seed (the same finding
	# `_probe_arena_switch.gd` records), so every run fought a different battle with different
	# species — and the measured floor luminance for Tamers Apex swung 0.12 -> 0.53 between two runs
	# of IDENTICAL renderer code. A lighting number that moves 4x when nothing about the lighting
	# changed cannot be used to judge a lighting change.
	seed(20260808)
	Career.reset_new_game()
	# ⚠️ THE TUTORIAL CARD AND ITS SCRIM SIT OVER THE FRAME AND SKEW EVERY LUMINANCE SAMPLE. The
	# first run of this probe measured the arena through the onboarding overlay — the floor came
	# back a flat lavender because a UI panel was in front of it, not because the ground was lit
	# that way. A look probe must photograph the look, not the onboarding.
	Tutorial.enabled = false
	Tutorial.dismissed = true
	Roster.reset_to_empty()
	Roster._generate_starting_roster()
	var idx := 0
	for i in range(Career.leagues.size()):
		if str(Career.leagues[i].get("name", "")) == league_name:
			idx = i
			break
	Career.league_index = idx
	CupRun.start(idx, 3)
	CupRun.current_round = 1
	return idx


func _shoot(league_name: String) -> void:
	var idx := _setup_state(league_name)
	var team_size: int = Career.team_size_for_league(idx)
	while Roster.monsters.size() < team_size:
		Roster.monsters.append(GameData.make_monster(
			Art.ROSTER[Roster.monsters.size() % Art.ROSTER.size()], 0.5))
	var team_a: Array = Roster.monsters.slice(0, mini(team_size, Roster.monsters.size()))
	var team_b: Array = CupRun.current_rival_team()
	for m in team_a + team_b:
		m.reset_for_battle()
	var gp_id := TacticsScript.gameplan_for(team_b.map(func(m): return m.species_name))
	TacticsScript.commit({}, TacticsScript.team_plan_for_gameplan(gp_id), {},
		TacticsScript.orders_for_gameplan(gp_id, team_b), {}, {}, team_a, team_b)

	var arena = load(ARENA_SCENE).instantiate()
	add_child(arena)
	# ⚠️ A SCENE WHOSE SCRIPT FAILED TO PARSE STILL INSTANTIATES, AND THAT IS THE TRAP. Godot logs
	# the parse error, drops the script and hands back a bare Node — so `arena.get("nodes")` returns
	# `null`, the wait loop below spins 900 frames assigning Nil to a typed Array, and the probe
	# marches on to photograph a venue that was never built. Caught live on 2026-08-08 when another
	# workstream was mid-edit on `arena_3d.gd`. Check that the script is actually there and say so
	# plainly; an instrument that cannot tell "measured zero" from "failed to measure" is the whole
	# class of fault this file's 2026-08-08 repair exists to remove.
	if arena.get_script() == null or not (arena.get("nodes") is Array):
		print("⚠️ ARENA SCRIPT FAILED TO LOAD — %s built with no script. Nothing can be measured;"
			% ARENA_SCENE)
		print("   fix the parse error reported above and re-run. NOT reporting on this league.")
		await _teardown(arena)
		return
	var nodes: Array = []
	for i in range(900):
		await get_tree().process_frame
		nodes = arena.get("nodes")
		if not nodes.is_empty():
			break
	if nodes.is_empty():
		print("⚠️ NO UNITS after 900 frames at %s — the fight never resolved. NOT reporting."
			% league_name)
		await _teardown(arena)
		return

	# The HUD is not the venue. Photograph the world, so a nameplate cannot be mistaken for floor.
	var ov: CanvasLayer = arena.get("overlay")
	if ov != null:
		ov.visible = false

	# ⚠️ REPAIR 1 — PIN THE SHUTTER TO A SIM TICK. Everything after this line photographs a scene
	# that is not moving, chosen by frame INDEX rather than by when a timer happened to fire.
	var pin: Dictionary = await _pin_and_freeze(arena, nodes, league_name)

	# ⚠️ WHAT IS ACTUALLY IN THE SCENE. The first look-shots showed an apparently EMPTY board and
	# the honest question was "did the cover fail to build, or is it just too far away to see?" —
	# a picture cannot answer that and a batch dump can.
	var batches := 0
	var insts := 0
	for c in arena.get_children():
		if c is MultiMeshInstance3D:
			batches += 1
			insts += (c as MultiMeshInstance3D).multimesh.instance_count
	print("   scene: %d multimesh batches, %d instances; cam span %.1f, mode %d; pinned tick %d/%d%s"
		% [batches, insts, float(arena.get("_cam_span")), int(arena.get("_cam_mode")),
			int(pin["tick"]), int(pin["total"]), "" if bool(pin["quiet"]) else " (NOT QUIET)"])
	print("      league_name=%s" % str(arena.get("league_name")))
	var slug := league_name.to_lower().replace(" ", "-")
	var cam: Camera3D = arena.get("camera")

	# ── THE SHIPPING FRAME. Everything about composition — how much venue is in shot, whether the
	# cover out-values the creatures — is a claim about THIS frame, so it is measured here and not
	# in the instrument's own framing.
	await _shoot_composition(arena, cam, nodes, league_name, slug)
	var report: Array = arena.call("prop_report")
	for p in report:
		var row: Dictionary = p.duplicate()
		row["league"] = league_name
		_props.append(row)
	_scenes.append({
		"league": league_name,
		"layout": str(arena.get("_layout_name")),
		"obstacles": report.size(),
		"ticks": int(pin["total"]),
		"hash": _board_hash(report),
	})

	# ⚠️ MEASURE ON A FRAME WHERE A CREATURE IS MORE THAN A DOZEN PIXELS TALL. The gameplay camera
	# frames the whole engagement, so on a 5v5 ground a body is ~10px and a sample patch centred on
	# it is mostly the FLOOR BEHIND IT — which pinned the measured body/floor ratio at 1.02-1.07 for
	# the three big leagues through six rounds of real lighting change while the two small ones
	# moved freely. That divergence was the tell: an instrument that reports the same number no
	# matter what you do to the thing it measures is reporting on itself.
	#
	# So the metric frame is the arena's own FREE camera, parked on the living units' centroid at a
	# span that actually contains them. Same renderer, same lamps, same materials — only the framing
	# is the probe's, and it is the framing the complaint was about ("the creatures must be the
	# brightest things on screen" is a claim about a frame you can see them in).
	var centre := Vector3.ZERO
	var alive := 0
	for nd in nodes:
		if bool(nd.get("dead", false)):
			continue
		centre += (nd["holder"] as Node3D).global_position
		alive += 1
	if alive > 0:
		centre /= float(alive)
	# ⚠️ A FIXED SPAN, NOT ONE SIZED TO THE FIGHT. The comparison across leagues is only fair if a
	# creature is the same number of pixels tall in every frame; a span that tracks how spread out
	# this particular engagement happens to be makes each league's number incomparable with the
	# next. 26 units frames roughly five bodies plus the ground around them at every board size.
	var span := 26.0
	arena.set("_free_center", centre)
	arena.set("_free_span", span)
	arena.set("_cam_center", centre)
	arena.set("_cam_span", span)
	arena.set("_cam_mode", 3)   # CamMode.FREE
	arena.call("_apply_camera_now")
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var img: Image = get_viewport().get_texture().get_image()
	img.save_png("user://venue_%s.png" % slug)
	var isz := Vector2(img.get_width(), img.get_height())
	var vp: Vector2 = get_viewport().get_visible_rect().size

	# ── FLOOR AND BODY, BOTH BY ATTRIBUTION (REPAIR 2 applied to pass 1 as well).
	# ⚠️ THE OLD GRID SAMPLER IS KEPT AS A CROSS-CHECK AND HERE IS WHY IT NEEDED ONE. Dumping every
	# large visual in the scene turned up a `MeshInstance3D` 61.6 x 61.6 units across sitting at
	# y = 0.12 on the 5v5 boards: a VFX ground decal (`vfx.gd`, another workstream's file) covering
	# roughly a third of the arena floor. Every grid sample near the engagement was landing on IT,
	# which is why the Platinum floor reading was byte-identical (0.128) whether the ground material
	# was tinted pale grey or PURE RED. The diff sampler cannot make that mistake — it uses the
	# pixels the Ground nodes themselves own — but keeping both columns is how the NEXT decal gets
	# noticed instead of quietly moving a number.
	var ground_nodes: Array = _find_named(arena, "Ground")
	var body_nodes: Array = _body_visuals(nodes)
	var gr_m: Dictionary = await _layer_stats(ground_nodes, img)
	var bd_m: Dictionary = await _layer_stats(body_nodes, img)

	var gs: Vector2 = arena.get("ground_size")
	# ⚠️ A `const` is NOT a property, so `arena.get("WORLD_SCALE")` returns null. Read it off the
	# script resource's constant map, which is where a const actually lives.
	var ws: float = float((arena.get_script() as GDScript).get_script_constant_map().get("WORLD_SCALE", 1.0))
	var floor_vals: Array = []
	for ix in range(11):
		for iy in range(9):
			var w := Vector3(
				lerpf(-0.42, 0.42, float(ix) / 10.0) * gs.x * ws, 0.0,
				lerpf(-0.40, 0.40, float(iy) / 8.0) * gs.y * ws)
			if cam.is_position_behind(w) or not _clear_of(w, nodes):
				continue
			var l := _luma_at(img, cam.unproject_position(w), vp, isz)
			if l >= 0.0:
				floor_vals.append(l)

	# The old 5x5 bright-third body patch, also kept as a cross-check for the same reason.
	var body_patch: Array = []
	for nd in nodes:
		if bool(nd.get("dead", false)):
			continue
		var h: Node3D = nd["holder"]
		for up in [1.4, 2.2, 3.0]:
			var l2 := _luma_bright_at(img, cam.unproject_position(
				h.global_position + Vector3(0, up, 0)), vp, isz)
			if l2 >= 0.0:
				body_patch.append(l2)

	if float(gr_m["luma"]) < 0.0 or float(bd_m["luma"]) < 0.0:
		print("   NO USABLE SAMPLE for %s (floor %.3f, body %.3f)"
			% [league_name, float(gr_m["luma"]), float(bd_m["luma"])])
		await _teardown(arena)
		return

	# ── SELF-TEST on this frame, while the camera is still framing the cast (REPAIR 3).
	await _self_test_metric(arena, league_name, ground_nodes, body_nodes, img)

	_rows.append({
		"league": league_name,
		"frame": _frame_luma(img),
		"floor": gr_m["luma"],
		"body": bd_m["luma"],
		"floor_grid": _median(floor_vals) if not floor_vals.is_empty() else -1.0,
		"body_patch": _median(body_patch) if not body_patch.is_empty() else -1.0,
	})
	print("shot %-14s -> %s" % [league_name,
		ProjectSettings.globalize_path("user://venue_%s.png" % slug)])
	await _teardown(arena)


## ═══════════════════════════════════════════════════════════════════════════════════════════════
## REPAIR 1 — PINNING THE SHUTTER
## ═══════════════════════════════════════════════════════════════════════════════════════════════

## The tick to photograph: a third of the way into the stream, then nudged forward to the first
## QUIET one. Quiet means no shot lands and nobody is casting on that tick — so `_apply_frame` fires
## no one-shot VFX (a flash, a charge ring, an impact burst) whose decay would still be in flight
## when the shutter opens. Deterministic: it reads only the frame stream.
func _pin_tick(arena: Node) -> Dictionary:
	var frames: Array = arena.get("frames")
	var total: int = frames.size()
	if total <= 1:
		return {"tick": 0, "total": total, "quiet": true}
	var want: int = clampi(int(float(total - 1) * PIN_FRACTION), 0, total - 1)
	for i in range(want, mini(total - 1, want + PIN_SEARCH) + 1):
		var f: Dictionary = frames[i]
		if not (f.get("shots", []) as Array).is_empty():
			continue
		var casting := false
		for u in (f.get("units", []) as Array):
			if str((u as Dictionary).get("state", "")) == "cast":
				casting = true
				break
		if not casting:
			return {"tick": i, "total": total, "quiet": true}
	return {"tick": want, "total": total, "quiet": false}


## Apply the pinned tick, let its transients COMPLETE, then stop the world.
##
## ⚠️ THE ORDER MATTERS AND EACH STEP EARNS ITS PLACE.
##  1. `playing = false` before `_apply_frame` — otherwise `_process` immediately advances past the
##     tick we just chose and the pin means nothing.
##  2. `SETTLE_FRAMES` unfrozen — a topple tween (0.45s) and a smoke burst are already running for
##     any unit that died before the pinned tick. Freezing mid-tween would preserve a DIFFERENT
##     half-fallen pose every run. A transient that has finished is deterministic; one caught in
##     flight is not. This is the only wall-clock wait left in the probe and it waits for
##     completion, not for a look.
##  3. `PROCESS_MODE_DISABLED` — stops every `_process` in the arena subtree: playback, the camera
##     follow, the crowd, the animators.
##  4. The animation clocks are then driven by hand. Freezing alone is not enough: a rig's
##     `AnimationPlayer` and a sprite animator's `_t` are both WALL-CLOCK accumulators, so freezing
##     captures whatever phase the machine's frame rate happened to reach. `seek()` to a fixed time
##     and a fixed-delta convergence loop make the pose a function of the tick alone.
##  5. The camera is SNAPPED to its own target rather than lerped there, so its position is not a
##     function of how many frames elapsed either.
func _pin_and_freeze(arena: Node, nodes: Array, league_name: String) -> Dictionary:
	var pin: Dictionary = _pin_tick(arena)
	arena.set("playing", false)
	# ⚠️ AN EMPTY FRAME STREAM IS A REAL STATE, NOT AN IMPOSSIBLE ONE — `arena_3d.gd:_process` has a
	# named non-spatial fallback for it. `_apply_frame` indexes `frames[0]` unguarded, so applying a
	# pin to an empty stream crashes the probe rather than reporting the venue it can still see.
	if int(pin["total"]) > 0:
		arena.set("frame_pos", float(pin["tick"]))
		arena.call("_apply_frame", float(pin["tick"]))

	# Step 2 — let the transients finish, and MEASURE how much the frame was still moving at the
	# end of it. `settle_dev` near zero is the evidence that waiting was enough.
	for i in range(SETTLE_FRAMES):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var a: Image = get_viewport().get_texture().get_image()
	await RenderingServer.frame_post_draw
	var b: Image = get_viewport().get_texture().get_image()
	var settle_dev := _max_dev(a, b)

	# Step 3 — stop the world.
	(arena as Node).process_mode = Node.PROCESS_MODE_DISABLED
	arena.set("_shake", 0.0)

	# Step 4 — drive every body to a fixed pose.
	for nd in nodes:
		var anim = nd.get("anim")
		if anim == null or not is_instance_valid(anim):
			continue
		# Converge the exponential lerps (facing yaw, torso twist) with FIXED deltas. `_process` is
		# a plain method — the node being disabled only stops the engine calling it.
		for i in range(CONVERGE_STEPS):
			anim.call("_process", CONVERGE_DT)
		var player = anim.get("_player")
		if player is AnimationPlayer:
			# The rigged path: a real clip on a real player. Park it at a fixed time and pause it.
			# ⚠️ RE-PLAY WITH A ZERO BLEND FIRST. `creature_rig.gd:_play` starts every clip with a
			# 0.12s cross-fade, so a rig whose state changed near the pinned tick is still BLENDING
			# when the shutter opens — and how far through that blend it is depends on how many
			# wall-clock frames elapsed, which is exactly the fault this repair removes. Restarting
			# the same clip with blend 0 discards the residual blend; `seek` then places the pose as
			# a pure function of `PIN_ANIM_T`. Measured worth: it took the run-to-run spread on body
			# luminance from 0.001 to 0.000.
			var pl := player as AnimationPlayer
			var cur := pl.current_animation
			if cur != "":
				pl.play(cur, 0.0)
				pl.pause()
				pl.seek(PIN_ANIM_T, true)
		else:
			# The sprite path (`creature_anim.gd`): four wall-clock accumulators, all writable.
			# `_death_t` is pinned PAST its own `DEATH_TIME` so a corpse is fully toppled rather
			# than caught somewhere on the way down.
			anim.set("_t", PIN_ANIM_T)
			anim.set("_attack_t", -1.0)
			anim.set("_hit_t", -1.0)
			if float(anim.get("_death_t")) >= 0.0:
				anim.set("_death_t", 4.0)
			anim.call("_process", 0.0)

	# Step 5 — snap the camera onto its own target instead of lerping toward it.
	var tgt: Dictionary = arena.call("_camera_target")
	arena.set("_cam_center", tgt["center"])
	arena.set("_cam_span", tgt["span"])
	arena.call("_apply_camera_now")

	# ── THE RECEIPT. Three grabs of a venue nobody is touching; the largest per-pixel luminance
	# change between them is `frozen_dev`. Anything above zero means something is still animating
	# and every number taken from this capture is a sample of a moving target.
	var grabs: Array = []
	for i in range(3):
		await RenderingServer.frame_post_draw
		grabs.append(get_viewport().get_texture().get_image())
	var frozen_dev: float = maxf(_max_dev(grabs[0], grabs[1]), _max_dev(grabs[1], grabs[2]))

	# ⚠️ THE DIFF THRESHOLD IS MEASURED, NOT ASSUMED, AND THE FIRST RUN OF THE LAYER PASS IS WHY.
	# SSAO is on and its sampling was not frame-stable, so TWO IDENTICAL FRAMES differed across most
	# of the picture; at a fixed 0.012 threshold the visibility diff attributed 64% of the frame to
	# the stands and 92% to the ground — sums well over 100%, i.e. the instrument reporting its own
	# noise. With the scene frozen the control comes back at 0.0000, but the measurement stays: the
	# day someone adds a temporal effect, this is what catches it instead of the numbers drifting.
	var noise: Array = []
	for x in range(0, grabs[0].get_width(), DIFF_STEP):
		for y in range(0, grabs[0].get_height(), DIFF_STEP):
			noise.append(absf(grabs[0].get_pixel(x, y).get_luminance()
				- grabs[1].get_pixel(x, y).get_luminance()))
	noise.sort()
	var p995: float = float(noise[mini(noise.size() - 1, int(float(noise.size()) * 0.995))])
	_eps = maxf(DIFF_EPS, p995 * 1.6)

	_pins.append({
		"league": league_name, "tick": pin["tick"], "total": pin["total"], "quiet": pin["quiet"],
		"settle_dev": settle_dev, "frozen_dev": frozen_dev, "noise": p995,
	})
	return pin


## Largest per-pixel luminance difference between two frames, on the same lattice the diffs use.
func _max_dev(a: Image, b: Image) -> float:
	var w := mini(a.get_width(), b.get_width())
	var h := mini(a.get_height(), b.get_height())
	var m := 0.0
	for x in range(0, w, DIFF_STEP):
		for y in range(0, h, DIFF_STEP):
			m = maxf(m, absf(a.get_pixel(x, y).get_luminance() - b.get_pixel(x, y).get_luminance()))
	return m


## ⚠️ ONE `process_frame` AFTER `queue_free()` DOES NOT RELEASE THE GPU RESOURCES, and on a sweep
## that builds a fresh venue per league that is the difference between an instrument and a crash.
## MEASURED 2026-08-08: Wood and Bronze shot clean, then the THIRD build died with "not enough room
## in the RESOURCES descriptor heap" and every prop multimesh after it came back with a null
## uniform set — so the probe photographed two leagues and reported on five.
##
## `queue_free()` only marks the node; the free happens at end of frame, the RenderingServer frees
## its own objects on ITS next frame, and the freed materials only then drop the last reference to
## their textures. Detaching first and then spending frames — including two that actually reach the
## rasteriser via `frame_post_draw` — is what makes the release land before the next venue is built.
##
## ⚠️ THIS IS A HARNESS FIX, NOT A LEAK FIX, AND THE DISTINCTION MATTERS. Nothing here proves
## `arena_3d.gd` releases everything it allocates; it proves the sweep no longer outruns the
## release. The real game builds one venue per fight and returns to a menu between, so it has the
## frames this probe was not giving. If a future round sees this fire in normal play, the answer is
## an ownership audit of the venue's materials, NOT a bigger descriptor heap.
##
## ⚠️ AND THE ARENA IS FROZEN BY THE TIME THIS RUNS, so `process_mode` is restored first —
## `queue_free` on a disabled subtree still works, but a half-frozen node left in the tree would be
## a trap for anyone who later moves the teardown.
func _teardown(arena: Node) -> void:
	if arena == null:
		return
	(arena as Node).process_mode = Node.PROCESS_MODE_INHERIT
	if arena.get_parent() != null:
		arena.get_parent().remove_child(arena)
	arena.queue_free()
	for i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


## ═══════════════════════════════════════════════════════════════════════════════════════════════
## THE COMPOSITION PASS — layer coverage and the value ladder, by visibility diff
## ═══════════════════════════════════════════════════════════════════════════════════════════════
const DIFF_STEP := 3            # sample every 3rd pixel on each axis — ~114k samples at 1280x800
const DIFF_EPS := 0.012         # FLOOR for the threshold; the real one is measured — see `_pin_and_freeze`
var _eps := DIFF_EPS

func _shoot_composition(arena: Node, cam: Camera3D, nodes: Array, league_name: String,
		slug: String) -> void:
	# ⚠️ THE WHOLE-VENUE FRAME, NOT WHATEVER THE FOLLOW CAMERA HAPPENED TO BE DOING. The first run
	# of this pass photographed `CamMode.TEAM`, and TEAM frames only the units that are still alive
	# on YOUR side — so a league whose team A had been wiped by the sample moment fell back to the
	# all-units wide shot while a league still fighting was zoomed to a scrum. Two leagues framed
	# differently cannot be compared on "how much of the frame is venue", which is the entire
	# question. `CamMode.ARENA` (2) is a real shipping mode — the `C` toggle — and it is the only
	# one that frames the same thing at every board size.
	#
	# ⚠️ AND IT IS SNAPPED, NOT LERPED. The old code called `_update_camera(4.0)` and hoped a single
	# large delta got there; the scene is frozen now, so the target is read directly and applied.
	arena.set("_cam_mode", 2)
	var tgt: Dictionary = arena.call("_camera_target")
	arena.set("_cam_center", tgt["center"])
	arena.set("_cam_span", tgt["span"])
	arena.call("_apply_camera_now")
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var base: Image = get_viewport().get_texture().get_image()
	base.save_png("user://venue_%s_hero.png" % slug)

	var stands: Array = _find_named(arena, "VenueStands")
	var walls: Array = _find_named(arena, "VenueWalls")
	var ground: Array = _find_named(arena, "Ground")
	var props: Array = _find_named(arena, "Prop_")
	var bodies: Array = _body_visuals(nodes)

	var st: Dictionary = await _layer_stats(stands, base)
	var wl: Dictionary = await _layer_stats(walls, base)
	var gr: Dictionary = await _layer_stats(ground, base)
	var pr: Dictionary = await _layer_stats(props, base)
	var bd: Dictionary = await _layer_stats(bodies, base)

	# The backdrop. `_build_world` sets `BG_COLOR` with `fog_sky_affect = 0`, so every pixel that no
	# geometry reached is EXACTLY the league's fog colour — an empty-frame measure that needs no
	# threshold guessing. It is the honest counterpart to "stands%": a frame that is 60% void is
	# not showing a stadium however tall the stands are.
	# ⚠️ THE BACKDROP IS READ OFF THE FRAME, NOT OFF `Environment.background_color`. The first
	# version compared against the authored fog colour and reported 0.0% empty on every league —
	# on frames with an obviously black third at the top. FILMIC tonemapping and the exposure term
	# sit between the authored colour and the pixel, so the two are simply different numbers. The
	# four corners of this framing are always backdrop, so they are the honest reference.
	var bg: Color = base.get_pixel(2, 2)
	var empty := 0
	var total := 0
	var isz := Vector2(base.get_width(), base.get_height())
	for x in range(0, int(isz.x), DIFF_STEP):
		for y in range(0, int(isz.y), DIFF_STEP):
			total += 1
			var c2: Color = base.get_pixel(x, y)
			if absf(c2.r - bg.r) < 0.01 and absf(c2.g - bg.g) < 0.01 and absf(c2.b - bg.b) < 0.01:
				empty += 1

	# ── PER-KIND PROP VALUE (REPAIR 2) and the cast's own saturation, from this same frame.
	var cover_lit: Array = await _kind_stats(arena, cam, base, league_name)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	for nd in nodes:
		if bool(nd.get("dead", false)):
			continue
		var hb: Node3D = nd["holder"]
		var s2 := _sat_at(base, cam.unproject_position(hb.global_position + Vector3(0, 2.2, 0)),
			vp, isz)
		if s2 >= 0.0:
			_body_sat.append(s2)

	_shots.append({
		"league": league_name,
		"f_stands": st["frac"], "f_props": pr["frac"], "f_floor": gr["frac"],
		"f_empty": float(empty) / maxf(1.0, float(total)),
		"l_stands": st["luma"], "l_walls": wl["luma"], "l_floor": gr["luma"],
		"l_props": _median(cover_lit) if not cover_lit.is_empty() else pr["luma"],
		# ⚠️ THE BODY VALUE IS NOW ATTRIBUTED TOO, NOT PATCH-SAMPLED. See REPAIR 2 — the same
		# four-pixel problem that froze the crate applies to a ten-pixel creature in the wide shot.
		"l_body": bd["luma"],
	})


## ⚠️ REPAIR 2 — THE PER-KIND PROP SAMPLER, REBUILT ON ATTRIBUTION.
##
## THE OLD VERSION unprojected each piece's top face and averaged the brightest third of a 5x5
## patch. That is 25 pixels centred on an object that, in the shipping ARENA frame, is about four
## pixels across — so most of the patch was the FLOOR BEHIND THE PROP, and taking the brightest
## third made it worse by preferring whatever in the patch was brightest, which is usually not the
## prop. Floor pixels do not move when a crate's tint moves. That is the whole of the reported
## symptom: crate 0.477 and planter 0.243, identical to three decimals across seven runs and five
## different tints, while boulder and pillar — twice as tall, and therefore actually hit by the
## patch — moved freely.
##
## THE NEW VERSION hides the kind's own nodes, diffs, and keeps only the pixels that changed. If
## a piece resolves no pixels it is DROPPED and counted, so a kind the camera cannot see reports as
## a thin sample rather than as a confident number about the floor. This is the same technique the
## layer pass already trusted; it simply was not being applied where the objects are small, which
## is exactly where it was needed.
##
## Returns the flat list of every resolved lit-face luminance, for the ladder's cover term.
func _kind_stats(arena: Node, cam: Camera3D, base: Image, league_name: String) -> Array:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var isz := Vector2(base.get_width(), base.get_height())
	var by_kind: Dictionary = {}
	for p in arena.call("prop_report"):
		var k: String = str(p["kind"])
		if not by_kind.has(k):
			by_kind[k] = []
		by_kind[k].append(p)

	var out: Array = []
	var keys: Array = by_kind.keys()
	keys.sort()
	for k in keys:
		var group: Array = _kind_nodes(arena, k)
		if group.is_empty():
			continue
		var mm: Array = await _matte_pair(group)
		var ma: Image = mm[0]
		var mb: Image = mm[1]
		# ⚠️ WHAT GEOMETRY THIS KIND ACTUALLY HAS. Recorded for every kind because the guesses about
		# why four of them resolved nothing were wrong twice running — first "too small", refuted by
		# the drawn-height column, then "off frame", refuted by the off-frame column. The node names
		# and instance counts are the next thing a sampler can be wrong about, so they get measured
		# too rather than reasoned about.
		var names: Array = []
		var insts := 0
		for n in group:
			names.append(str((n as Node).name))
			if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
				insts += (n as MultiMeshInstance3D).multimesh.instance_count
		if not _kind_cover.has(k):
			_kind_cover[k] = {"placed": 0, "resolved": 0, "pixels": [], "px_h": [], "offscreen": 0,
				"nodes": "", "insts": 0}
		_kind_cover[k]["nodes"] = ", ".join(names)
		_kind_cover[k]["insts"] = int(_kind_cover[k].get("insts", 0)) + insts
		# ⚠️ THE DECISIVE COUNT: how many pixels ANYWHERE in the frame belong to this kind. It
		# separates the last two candidate faults from each other without another guess —
		# ~0 means the kind is not reaching the screen at all (or the matte does not reach the
		# kind), while a healthy count with zero resolved windows means the sample POINTS are in
		# the wrong place. Two wrong hypotheses in a row is enough; this one is measured.
		var full := 0
		for x in range(0, mini(base.get_width(), ma.get_width()), DIFF_STEP):
			for y in range(0, mini(base.get_height(), ma.get_height()), DIFF_STEP):
				if _keyed(ma, mb, x, y):
					full += 1
		_kind_cover[k]["frame_px"] = maxi(int(_kind_cover[k].get("frame_px", 0)), full)
		# ⚠️ AND ONE LAST DISCRIMINATION, BECAUSE ZERO HAS TWO CAUSES. A kind that keys no pixels is
		# either not being DRAWN, or is being drawn by something the matte cannot reach (a shader
		# that ignores `material_override`, a second node under another name). Hiding it outright
		# tells the two apart: if the frame changes when the nodes are hidden, they were on screen
		# and the matte is the thing at fault; if the frame does not change, they were never drawn.
		# Only run for the zero case — it is two extra frame grabs and nothing else needs it.
		if full == 0:
			for n in group:
				(n as VisualInstance3D).visible = false
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var hid: Image = get_viewport().get_texture().get_image()
			for n in group:
				(n as VisualInstance3D).visible = true
			await RenderingServer.frame_post_draw
			var hpx := 0
			for x in range(0, mini(base.get_width(), hid.get_width()), DIFF_STEP):
				for y in range(0, mini(base.get_height(), hid.get_height()), DIFF_STEP):
					if absf(base.get_pixel(x, y).get_luminance()
							- hid.get_pixel(x, y).get_luminance()) >= _eps:
						hpx += 1
			_kind_cover[k]["hidden_px"] = maxi(int(_kind_cover[k].get("hidden_px", 0)), hpx)
		for p in by_kind[k]:
			_kind_cover[k]["placed"] = int(_kind_cover[k]["placed"]) + 1
			var c3: Vector3 = p["centre"]
			var top := c3 + Vector3(0, float(p["h"]) * 0.42, 0)
			if cam.is_position_behind(top):
				continue
			var sp := cam.unproject_position(top)
			# ⚠️ THE WINDOW IS SIZED FROM THE PIECE'S OWN PROJECTED HEIGHT, not fixed. A blocking
			# major and a barrel differ by an order of magnitude on screen, and one radius cannot
			# serve both: too small and a wall is sampled at its centre pixel only, too large and a
			# barrel's window is mostly its neighbours. Projecting the piece's top and bottom gives
			# the size the camera actually draws it at.
			var bot := c3 - Vector3(0, float(p["h"]) * 0.5, 0)
			var px_h := 8.0
			if not cam.is_position_behind(bot):
				px_h = absf(cam.unproject_position(bot).y - sp.y)
			# ⚠️ RECORDED FOR EVERY PIECE, RESOLVED OR NOT. How many pixels tall the camera actually
			# draws this thing is the number that explains a failed sample, and without it "0%
			# found" is a shrug. With it, it is a finding about the art.
			(_kind_cover[k]["px_h"] as Array).append(px_h)
			# ⚠️ OFF-FRAME AND UNATTRIBUTABLE ARE DIFFERENT DIAGNOSES AND MUST NOT BE POOLED. The
			# first guess at why four kinds resolved nothing was "they are too small to hit" — and
			# the drawn-height column, added to prove it, REFUTED it: bench 19px, crate 17px, shrine
			# 37px. Big enough to hit and still zero pixels, which only leaves "the sampler is not
			# looking where they are". Counting the two cases apart is what turns a shrug into a
			# question someone can answer.
			var ip := Vector2(sp.x / maxf(1.0, vp.x) * isz.x, sp.y / maxf(1.0, vp.y) * isz.y)
			if ip.x < 0.0 or ip.y < 0.0 or ip.x >= isz.x or ip.y >= isz.y:
				_kind_cover[k]["offscreen"] = int(_kind_cover[k].get("offscreen", 0)) + 1
				continue
			var radius: int = clampi(int(px_h * 0.6), 3, 22)
			var st: Dictionary = _attributed(base, ma, mb, sp, vp, isz, radius)
			if int(st["n"]) < 4:
				continue
			if not _kind_luma.has(k):
				_kind_luma[k] = []
				_kind_sat[k] = []
			_kind_luma[k].append(st["luma"])
			_kind_sat[k].append(st["sat"])
			(_kind_cover[k]["pixels"] as Array).append(float(int(st["n"])))
			_kind_cover[k]["resolved"] = int(_kind_cover[k]["resolved"]) + 1
			out.append(st["luma"])
		# REPAIR 3 — prove this kind's luminance can move, once, at the first league that has it.
		if not bool(_kind_proven.get(k, false)):
			await _self_test_kind(arena, cam, k, group, by_kind[k], league_name)
	return out


## Every MultiMeshInstance3D drawing this kind. ⚠️ EXACT NAMES, NOT A PREFIX — `arena_3d.gd` names
## its batches `Prop_<kind>`, `Prop_<kind>_alt`, `Prop_<kind>_box`, `Prop_<kind>_cyl`, and a prefix
## match on `Prop_low_wall` also swallows every `Prop_low_wall_border`. Hiding the border's pieces
## while measuring the wall would attribute the border's pixels to the wall and, worse, would make
## the border's own diff come back empty — a frozen number by a different route.
func _kind_nodes(arena: Node, kind: String) -> Array:
	var want := {
		"Prop_%s" % kind: true, "Prop_%s_alt" % kind: true,
		"Prop_%s_box" % kind: true, "Prop_%s_cyl" % kind: true,
	}
	var out: Array = []
	for c in arena.get_children():
		if c is VisualInstance3D and want.has(str(c.name)):
			out.append(c)
	return out


## Every VisualInstance3D that draws a living creature — the group whose pixels are "the cast".
func _body_visuals(nodes: Array) -> Array:
	var out: Array = []
	for nd in nodes:
		if bool(nd.get("dead", false)):
			continue
		_collect_visuals(nd["holder"], out)
	return out


func _collect_visuals(n: Node, out: Array) -> void:
	if n is VisualInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_visuals(c, out)


## ⚠️ THE KEY MATTE, AND WHY IT REPLACED THE HIDE-AND-DIFF.
##
## Hiding a group to find its pixels also removes the SHADOW IT CASTS, so the diff returns the
## group's own pixels PLUS a skirt of ground that merely got lighter. For a layer covering a third
## of the frame that skirt is a rounding error and the median absorbs it. For a CREATURE it is not:
## a body is ~10px in the shipping frame and its shadow is a comparable patch of DARK floor, so the
## hide-diff was dragging the measured "creature value" down toward the ground — the exact
## direction that flatters nothing and quietly manufactures a value-ladder failure.
##
## Two flat UNSHADED mattes fix it: render the group magenta, render it green, and keep the pixels
## that differ. Geometry is unchanged between the two grabs, so every shadow, every AO term and
## every occlusion is IDENTICAL in both — only the group's own visible pixels can differ. The
## luminance is then read from the UNMODIFIED frame at exactly those pixels.
##
## ⚠️ ONE HONEST LIMITATION: a genuinely TRANSPARENT surface renders opaque under the matte, so its
## key includes pixels a player sees through. Nothing measured here is transparent (ground, stands,
## walls, prop batches, creature bodies are all opaque), but a future translucent layer would need
## its own treatment rather than this one.
const MATTE_A := Color(1.0, 0.0, 1.0)
const MATTE_B := Color(0.0, 1.0, 0.0)
## How far apart the two mattes must land, summed over RGB, for a pixel to belong to the group.
## Generous: the two colours are ~2.0 apart before tonemapping and this only has to beat noise.
const MATTE_EPS := 0.15

func _matte_pair(group: Array) -> Array:
	var saved := _override(group, _flat(MATTE_A))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var a: Image = get_viewport().get_texture().get_image()
	_override(group, _flat(MATTE_B))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var b: Image = get_viewport().get_texture().get_image()
	for i in range(group.size()):
		var g := group[i] as GeometryInstance3D
		if g != null:
			g.material_override = saved[i] as Material
	await RenderingServer.frame_post_draw
	return [a, b]


## True when this pixel belongs to the matted group.
func _keyed(a: Image, b: Image, x: int, y: int) -> bool:
	var ca: Color = a.get_pixel(x, y)
	var cb: Color = b.get_pixel(x, y)
	return absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) >= MATTE_EPS


## Median luminance and saturation of the pixels in a window that ACTUALLY BELONG to the keyed
## group. `n` is how many there were, and a caller that gets a small `n` back is being told its
## sample is thin, not handed a number anyway.
func _attributed(base: Image, ma: Image, mb: Image, sp: Vector2, vp: Vector2, isz: Vector2,
		radius: int) -> Dictionary:
	var p := Vector2(sp.x / maxf(1.0, vp.x) * isz.x, sp.y / maxf(1.0, vp.y) * isz.y)
	var lum: Array = []
	var sats: Array = []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			var x := int(p.x) + dx
			var y := int(p.y) + dy
			if x < 0 or y < 0 or x >= int(isz.x) or y >= int(isz.y):
				continue
			if not _keyed(ma, mb, x, y):
				continue
			var ca: Color = base.get_pixel(x, y)
			lum.append(ca.get_luminance())
			sats.append(ca.s)
	if lum.is_empty():
		return {"n": 0, "luma": -1.0, "sat": -1.0}
	return {"n": lum.size(), "luma": _median(lum), "sat": _median(sats)}


## Every descendant whose name starts with `prefix`.
func _find_named(root: Node, prefix: String) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is VisualInstance3D and str(c.name).begins_with(prefix):
			out.append(c)
		out.append_array(_find_named(c, prefix))
	return out


## Screen coverage and mean luminance of one venue layer. ⚠️ THE LUMINANCE IS READ FROM THE
## UNMODIFIED FRAME at the pixels the diff attributes to the layer — so it is the value the player
## sees, at exactly the pixels that layer occupies, with no sample geometry to place wrongly.
func _layer_stats(group: Array, base: Image) -> Dictionary:
	if group.is_empty():
		return {"frac": 0.0, "luma": -1.0}
	var mm: Array = await _matte_pair(group)
	var ma: Image = mm[0]
	var mb: Image = mm[1]

	var vals: Array = []
	var total := 0
	var w := mini(base.get_width(), ma.get_width())
	var h := mini(base.get_height(), ma.get_height())
	for x in range(0, w, DIFF_STEP):
		for y in range(0, h, DIFF_STEP):
			total += 1
			if _keyed(ma, mb, x, y):
				vals.append(base.get_pixel(x, y).get_luminance())
	if vals.is_empty():
		return {"frac": 0.0, "luma": -1.0}
	# ⚠️ THE MEDIAN, NOT A MEAN AND NOT THE BRIGHT HALF, AND THE REASON IS SET SIZE. A layer
	# covering 0.3% of the frame would report the value of its rim-lit top edges under a bright-half
	# mean while one covering 30% reported a broad average — and comparing those two IS the ladder.
	# The median is size-neutral: it is the value of a TYPICAL pixel of this layer, which is the
	# question "does the cover read brighter than the floor" actually asks.
	vals.sort()
	return {
		"frac": float(vals.size()) / maxf(1.0, float(total)),
		"luma": float(vals[vals.size() / 2]),
	}


## ═══════════════════════════════════════════════════════════════════════════════════════════════
## REPAIR 3 — THE SELF-TEST. A probe that cannot fail is not a probe.
## ═══════════════════════════════════════════════════════════════════════════════════════════════

## An unshaded flat material. ⚠️ UNSHADED IS THE POINT: it takes the lamp, the ambient term and the
## shadowing out of the perturbation, so the pixel goes to a value we chose. A lit white would move
## by an amount that depends on the very lighting the probe is measuring, and a small move would be
## ambiguous between "the measure is frozen" and "this corner is in shadow".
func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	return m


## Swap `material_override` on a group, returning the originals so they can be put back exactly.
func _override(group: Array, mat: Material) -> Array:
	var saved: Array = []
	for n in group:
		var g := n as GeometryInstance3D
		if g == null:
			saved.append(null)
			continue
		saved.append(g.material_override)
		g.material_override = mat
	return saved


func _restore(group: Array, saved: Array) -> void:
	for i in range(group.size()):
		var g := group[i] as GeometryInstance3D
		if g != null:
			g.material_override = saved[i] as Material
	await RenderingServer.frame_post_draw


## Perturb the FLOOR and the CAST on the metric frame and re-read the same samplers.
##
## ⚠️ THIS IS THE ROW THAT WOULD HAVE FAILED LOUDLY IN THE OLD PROBE. The old floor sampler was an
## 11x9 unprojected lattice, and a VFX ground decal 61.6 units across was sitting on top of a third
## of it — so painting the ground pure red moved the reported floor luminance by 0.000. Nobody
## found that until someone thought to try it by hand. Now it is tried automatically, every league.
func _self_test_metric(arena: Node, league_name: String, ground: Array, bodies: Array,
		base: Image) -> void:
	if not ground.is_empty():
		var before: Dictionary = await _layer_stats(ground, base)
		var saved := _override(ground, _flat(Color(1, 1, 1)))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var lit: Image = get_viewport().get_texture().get_image()
		var after: Dictionary = await _layer_stats(ground, lit)
		await _restore(ground, saved)
		_selftest.append({
			"measure": "floor luma", "league": league_name,
			"before": before["luma"], "after": after["luma"],
			"ok": float(after["luma"]) - float(before["luma"]) >= 0.10,
		})
	if not bodies.is_empty():
		var before2: Dictionary = await _layer_stats(bodies, base)
		var saved2 := _override(bodies, _flat(Color(1, 1, 1)))
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var lit2: Image = get_viewport().get_texture().get_image()
		var after2: Dictionary = await _layer_stats(bodies, lit2)
		await _restore(bodies, saved2)
		_selftest.append({
			"measure": "body luma", "league": league_name,
			"before": before2["luma"], "after": after2["luma"],
			"ok": float(after2["luma"]) - float(before2["luma"]) >= 0.10,
		})


## Perturb ONE PROP KIND and re-read the per-kind sampler through exactly the path `_kind_stats`
## uses — same window sizing, same attribution, same median. If this kind's number does not move
## when its material is replaced with unshaded white, the number is not about this kind.
##
## Run once per kind, at the first league that builds it, because the sweep is long enough already
## and a kind that responds at Wood is not going to stop responding at Gold. Kinds that never get
## proven are named in the report rather than quietly assumed fine.
func _self_test_kind(arena: Node, cam: Camera3D, kind: String, group: Array, pieces: Array,
		league_name: String) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size

	var before := await _sample_kind(cam, group, pieces, vp)
	if before < 0.0:
		return          # nothing resolvable on screen — nothing to prove either way
	var saved := _override(group, _flat(Color(1, 1, 1)))
	var after := await _sample_kind(cam, group, pieces, vp)
	await _restore(group, saved)
	if after < 0.0:
		return
	_kind_proven[kind] = after - before >= 0.10
	_selftest.append({
		"measure": "prop:%s" % kind, "league": league_name,
		"before": before, "after": after, "ok": after - before >= 0.10,
	})


## The median attributed lit-face luminance of one kind, as `_kind_stats` computes it, from a
## freshly grabbed frame. Shared by the measurement and its own self-test so they cannot diverge.
func _sample_kind(cam: Camera3D, group: Array, pieces: Array, vp: Vector2) -> float:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var base: Image = get_viewport().get_texture().get_image()
	var mm: Array = await _matte_pair(group)
	var ma: Image = mm[0]
	var mb: Image = mm[1]
	var isz := Vector2(base.get_width(), base.get_height())
	var vals: Array = []
	for p in pieces:
		var c3: Vector3 = p["centre"]
		var top := c3 + Vector3(0, float(p["h"]) * 0.42, 0)
		if cam.is_position_behind(top):
			continue
		var sp := cam.unproject_position(top)
		var bot := c3 - Vector3(0, float(p["h"]) * 0.5, 0)
		var px_h := 8.0
		if not cam.is_position_behind(bot):
			px_h = absf(cam.unproject_position(bot).y - sp.y)
		var st: Dictionary = _attributed(base, ma, mb, sp, vp, isz, clampi(int(px_h * 0.6), 3, 22))
		if int(st["n"]) >= 4:
			vals.append(st["luma"])
	return _median(vals) if not vals.is_empty() else -1.0


## ═══════════════════════════════════════════════════════════════════════════════════════════════
## SAMPLING PRIMITIVES
## ═══════════════════════════════════════════════════════════════════════════════════════════════

static func _median(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])


## Mean luminance of a 5x5 pixel patch, so one stray highlight cannot decide a sample. Returns -1
## when the point is off-frame.
## ⚠️ ONLY THE CROSS-CHECK COLUMNS USE THIS NOW. Patch sampling is what REPAIR 2 removed from every
## load-bearing measure — it cannot tell the object from what is behind it. Do not reach for it for
## anything small.
func _luma_at(img: Image, screen_pos: Vector2, vp: Vector2, isz: Vector2) -> float:
	var p := Vector2(screen_pos.x / maxf(1.0, vp.x) * isz.x, screen_pos.y / maxf(1.0, vp.y) * isz.y)
	if p.x < 3 or p.y < 3 or p.x >= isz.x - 3 or p.y >= isz.y - 3:
		return -1.0
	var sum := 0.0
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			var c: Color = img.get_pixel(int(p.x) + dx, int(p.y) + dy)
			sum += c.get_luminance()
	return sum / 25.0


## HSV saturation of the mean colour of a 5x5 patch. -1 off-frame.
func _sat_at(img: Image, screen_pos: Vector2, vp: Vector2, isz: Vector2) -> float:
	var p := Vector2(screen_pos.x / maxf(1.0, vp.x) * isz.x, screen_pos.y / maxf(1.0, vp.y) * isz.y)
	if p.x < 3 or p.y < 3 or p.x >= isz.x - 3 or p.y >= isz.y - 3:
		return -1.0
	var acc := Color(0, 0, 0)
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			acc += img.get_pixel(int(p.x) + dx, int(p.y) + dy)
	return (acc / 25.0).s


## Mean of the brightest third of a 5x5 patch — cross-check column only, see `_luma_at`.
func _luma_bright_at(img: Image, screen_pos: Vector2, vp: Vector2, isz: Vector2) -> float:
	var p := Vector2(screen_pos.x / maxf(1.0, vp.x) * isz.x, screen_pos.y / maxf(1.0, vp.y) * isz.y)
	if p.x < 3 or p.y < 3 or p.x >= isz.x - 3 or p.y >= isz.y - 3:
		return -1.0
	var vals: Array = []
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			vals.append(img.get_pixel(int(p.x) + dx, int(p.y) + dy).get_luminance())
	vals.sort()
	var take: int = maxi(1, vals.size() / 3)
	var sum := 0.0
	for i in range(vals.size() - take, vals.size()):
		sum += float(vals[i])
	return sum / float(take)


## True when no unit is standing within 5 world units of `w` — so a floor sample is floor.
func _clear_of(w: Vector3, nodes: Array) -> bool:
	for nd in nodes:
		if bool(nd.get("dead", false)):
			continue
		if (nd["holder"] as Node3D).global_position.distance_to(w) < 5.0:
			return false
	return true


func _frame_luma(img: Image) -> float:
	var sum := 0.0
	var n := 0
	var step := maxi(1, img.get_width() / 120)
	for x in range(0, img.get_width(), step):
		for y in range(0, img.get_height(), step):
			sum += img.get_pixel(x, y).get_luminance()
			n += 1
	return sum / maxf(1.0, float(n))
