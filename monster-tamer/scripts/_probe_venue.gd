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

## ⚠️ THE PROPORTION BAR, AND WHY IT IS 3.0. A cover piece is drawn `max(w, d)` long and `h` tall,
## and the report this pass answers was "crates read as brick loaves roughly three monsters long".
## Long-over-tall is that complaint as a number. Below ~2.0 a piece reads as an object; a wall run
## is legitimately 2-3 (it is a wall); past 3.0 it reads as something spilled on the floor, and the
## measured board had blocking majors at 4.2 and soft crates at 2.2 with no wall-ness to earn it.
const LOAF_RATIO := 3.0
## A soft piece taller than this is not "cover you shoot over" any more (ARENA_DESIGN.md §4, in
## creature heights: its 3.4 cap was written against a ~2.0-unit body).
const COVER_MAX_BODIES := 1.7


func _ready() -> void:
	for league in SWEEP:
		await _shoot(league)
	_report_value()
	_report_proportion()
	_report_composition()
	get_tree().quit()


## ── PASS 1 (unchanged, and deliberately so) — the metric-frame value check from the lighting
## round. It is the regression detector for that work: if a prop tint or a stand change moves the
## floor or the bodies, this is what says so.
func _report_value() -> void:
	print("")
	print("═══ VALUE (metric frame, span 26) ═══")
	print("league          frame   floor   body   body/floor   verdict")
	var bad := 0
	for r in _rows:
		var ratio: float = r["body"] / maxf(0.001, r["floor"])
		# The bodies must out-value the ground they stand on. 1.0 is parity — a body that reads
		# exactly as bright as the floor has no value separation at all and relies on hue alone.
		var ok: bool = ratio >= 1.12 and r["floor"] <= 0.62
		if not ok:
			bad += 1
		print("%-14s  %.3f   %.3f   %.3f   %.2f         %s" % [
			r["league"], r["frame"], r["floor"], r["body"], ratio, "ok" if ok else "FAIL"])
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
	print("═══ PROP VALUE BY KIND (lit face; floor %.3f, creatures %.3f) ═══" % [floor_med, body_med])
	var body_sat: float = _median(_body_sat) if not _body_sat.is_empty() else 1.0
	print("cast saturation %.3f — a prop above it is shouting over the channel the bible reserves"
		% body_sat)
	print("kind             n    luma   vs floor   vs body    sat   sat/cast  verdict")
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
		print("%-14s %3d   %.3f    %5.2f     %5.2f   %.3f   %5.2f    %s" % [
			k, arr.size(), m, vf, vb, sm, vs, why])
	print("")
	print("%d/%d kinds sit correctly between floor and cast on VALUE (chroma column is advisory)"
		% [kk.size() - hot, kk.size()])


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
	var nodes: Array = []
	for i in range(900):
		await get_tree().process_frame
		nodes = arena.get("nodes")
		if not nodes.is_empty():
			break
	# ⚠️ SHOOT WHEN THE FIGHT IS JOINED, NOT WHEN THE SCENE EXISTS. The first version waited a flat
	# frame count and photographed either the opening wide (camera still at max span, bodies six
	# pixels tall) or the aftermath. Wait on the replay's own clock instead: a third of the way
	# through the frame stream is reliably mid-fight at every team size.
	var total: int = (arena.get("frames") as Array).size()
	for i in range(2000):
		await get_tree().process_frame
		if float(arena.get("frame_pos")) >= float(total) * 0.34:
			break

	# The HUD is not the venue. Photograph the world, so a nameplate cannot be mistaken for floor.
	var ov: CanvasLayer = arena.get("overlay")
	if ov != null:
		ov.visible = false

	# ⚠️ WHAT IS ACTUALLY IN THE SCENE. The first look-shots showed an apparently EMPTY board and
	# the honest question was "did the cover fail to build, or is it just too far away to see?" —
	# a picture cannot answer that and a batch dump can.
	var batches := 0
	var insts := 0
	for c in arena.get_children():
		if c is MultiMeshInstance3D:
			batches += 1
			insts += (c as MultiMeshInstance3D).multimesh.instance_count
	print("   scene: %d multimesh batches, %d instances; cam span %.1f, mode %d"
		% [batches, insts, float(arena.get("_cam_span")), int(arena.get("_cam_mode"))])
	for c in arena.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is PlaneMesh:
			var pmm := (c as MeshInstance3D).mesh as PlaneMesh
			var mo := (c as MeshInstance3D).material_override
			print("      plane size=%s pos=%s albedo=%s tex=%s vis=%s" % [
				pmm.size, (c as MeshInstance3D).position,
				(mo as StandardMaterial3D).albedo_color if mo is StandardMaterial3D else "?",
				"yes" if (mo is StandardMaterial3D and (mo as StandardMaterial3D).albedo_texture != null) else "no",
				(c as MeshInstance3D).visible])
	print("      league_name=%s" % str(arena.get("league_name")))
	var slug := league_name.to_lower().replace(" ", "-")
	var cam: Camera3D = arena.get("camera")

	# ── THE SHIPPING FRAME, PHOTOGRAPHED BEFORE THE METRIC CAMERA TAKES OVER. Everything about
	# composition — how much venue is in shot, whether the cover out-values the creatures — is a
	# claim about THIS frame, so it is measured here and not in the instrument's own framing.
	await _shoot_composition(arena, cam, nodes, league_name, slug)
	for p in arena.call("prop_report"):
		var row: Dictionary = p.duplicate()
		row["league"] = league_name
		_props.append(row)

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
	var spread := 0.0
	for nd in nodes:
		if bool(nd.get("dead", false)):
			continue
		centre += (nd["holder"] as Node3D).global_position
		alive += 1
	if alive > 0:
		centre /= float(alive)
	for nd in nodes:
		if bool(nd.get("dead", false)):
			continue
		spread = maxf(spread, (nd["holder"] as Node3D).global_position.distance_to(centre))
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
	for i in range(4):
		await get_tree().process_frame

	# ⚠️ THREE FRAMES, MEDIAN — BECAUSE THE VFX LAYER LIGHTS THE WHOLE VENUE. `vfx.gd:light_flash`
	# fires a pooled `OmniLight3D` at energy 6 for every explosion, and its range is large enough to
	# tint the STANDS AND THE CROWD: a shot taken during one comes back with the entire frame washed
	# warm red, floor and bodies alike, and their ratio pinned at 1.0. That is a real thing the
	# player sees and it is not this pass's to change (`vfx.gd` is another workstream's file), but a
	# lighting instrument must not report a one-frame explosion as the venue's lighting. Three
	# samples a third of a second apart, median taken.
	var gs: Vector2 = arena.get("ground_size")
	# ⚠️ A `const` is NOT a property, so `arena.get("WORLD_SCALE")` returns null. Read it off the
	# script resource's constant map, which is where a const actually lives.
	var ws: float = float((arena.get_script() as GDScript).get_script_constant_map().get("WORLD_SCALE", 1.0))
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var floors: Array = []
	var bodies: Array = []
	var frames_l: Array = []
	var saved := false

	for pass_i in range(3):
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		if not saved:
			img.save_png("user://venue_%s.png" % slug)
			saved = true
		var isz := Vector2(img.get_width(), img.get_height())

		# ── FLOOR luminance. Sampled INSIDE the metric frame — the comparison only means anything
		# between two things visible in the same picture — and never within 5 units of a unit, so a
		# monster standing on a sample point can not be counted as ground.
		# ⚠️ MEDIAN OVER THE WHOLE BOARD, NOT A MEAN AROUND THE FIGHT — because THE GROUND IS NOT
		# THE ONLY THING ON THE GROUND. Dumping every large visual in the scene turned up a
		# `MeshInstance3D` 61.6 x 61.6 units across sitting at y = 0.12 on the 5v5 boards: a VFX
		# ground decal (`vfx.gd`, another workstream's file) covering roughly a third of the arena
		# floor. Every floor sample taken near the engagement was landing on IT, which is why the
		# Platinum floor reading was byte-identical (0.128) whether the ground material was tinted
		# pale grey or PURE RED — a control test run precisely because a number that will not move
		# is not measuring the thing you think it is. A median over the full board outvotes it.
		var floor_vals: Array = []
		for ix in range(11):
			for iy in range(9):
				var w := Vector3(
					lerpf(-0.42, 0.42, float(ix) / 10.0) * gs.x * ws, 0.0,
					lerpf(-0.40, 0.40, float(iy) / 8.0) * gs.y * ws)
				if cam.is_position_behind(w) or not _clear_of(w, nodes):
					continue
				var l := _luma_at(img, cam.unproject_position(w), vp, isz)
				if l < 0.0:
					continue
				floor_vals.append(l)
		var floor_n: int = floor_vals.size()
		var floor_sum: float = _median(floor_vals) * float(floor_n) if floor_n > 0 else 0.0

		# ── BODY luminance: the mid-torso of every unit the replay is still drawing.
		# ⚠️ `dead`, NOT `last_rec.alive`. The renderer's own `dead` flag is what decides whether a
		# body is still on screen; `last_rec` can carry a stale `alive` for a unit already toppled,
		# and sampling one of those reads the empty floor where it used to be.
		var body_sum := 0.0
		var body_n := 0
		for nd in nodes:
			if bool(nd.get("dead", false)):
				continue
			var h: Node3D = nd["holder"]
			for up in [1.4, 2.2, 3.0]:
				# ⚠️ THE BODY SAMPLE IS THE BRIGHT THIRD OF ITS PATCH AND THE FLOOR SAMPLE IS A MEAN,
				# and the asymmetry is deliberate: a patch centred on a distant creature contains a
				# lot of the floor BEHIND it, and averaging that in manufactures a ratio of 1.0 no
				# matter what the lighting does. The question is "is the creature brighter than the
				# ground it stands on", so the creature's lit body is the right sample.
				var l2 := _luma_bright_at(img, cam.unproject_position(
					h.global_position + Vector3(0, up, 0)), vp, isz)
				if l2 < 0.0:
					continue
				body_sum += l2
				body_n += 1

		if floor_n > 0 and body_n > 0:
			floors.append(floor_sum / float(floor_n))
			bodies.append(body_sum / float(body_n))
			frames_l.append(_frame_luma(img))
		for f in range(20):
			await get_tree().process_frame

	if floors.is_empty():
		print("   NO USABLE SAMPLE for %s" % league_name)
		await _teardown(arena)
		return
	_rows.append({
		"league": league_name,
		"frame": _median(frames_l),
		"floor": _median(floors),
		"body": _median(bodies),
	})
	print("shot %-14s -> %s  (%d usable samples of 3)"
		% [league_name, ProjectSettings.globalize_path("user://venue_%s.png" % slug), floors.size()])
	await _teardown(arena)


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
func _teardown(arena: Node) -> void:
	if arena == null:
		return
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
const DIFF_EPS := 0.012         # FLOOR for the threshold; the real one is measured — see below
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
	arena.set("_cam_mode", 2)
	arena.set("playing", false)
	arena.call("_update_camera", 4.0)
	arena.call("_apply_camera_now")
	for i in range(6):
		await get_tree().process_frame
	# ⚠️ THE FRAME MUST BE FROZEN, AND THE FIRST RUN OF THIS PASS PROVED IT LOUDLY. The control
	# noise below came back at p99.5 = 0.08-0.19 — an eighth to a fifth of the whole luminance
	# range between two "identical" frames. That is not renderer noise, it is THE REPLAY STILL
	# PLAYING: bodies walk, the vfx layer animates and the camera lerps, so the visibility diff was
	# measuring the fight rather than the layer. Disabling the arena's processing after the camera
	# has settled makes every subsequent grab byte-comparable.
	(arena as Node).process_mode = Node.PROCESS_MODE_DISABLED
	for i in range(2):
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var base: Image = get_viewport().get_texture().get_image()
	base.save_png("user://venue_%s_hero.png" % slug)

	# ⚠️ THE NOISE FLOOR IS MEASURED, NOT ASSUMED, AND THE FIRST RUN OF THIS PASS IS WHY. SSAO is
	# on and its sampling is not frame-stable, so TWO IDENTICAL FRAMES differ across most of the
	# picture. At a fixed 0.012 threshold the visibility diff attributed 64% of the frame to the
	# stands and 92% to the ground — sums well over 100%, i.e. the instrument was reporting its own
	# noise. The control below diffs two consecutive UNMODIFIED frames and takes the 99.5th
	# percentile of the change; the layer threshold is set above that, so a "hit" means the layer
	# and not the renderer.
	await RenderingServer.frame_post_draw
	var ctrl: Image = get_viewport().get_texture().get_image()
	var noise: Array = []
	for x in range(0, base.get_width(), DIFF_STEP):
		for y in range(0, base.get_height(), DIFF_STEP):
			noise.append(absf(base.get_pixel(x, y).get_luminance()
				- ctrl.get_pixel(x, y).get_luminance()))
	noise.sort()
	var p995: float = float(noise[mini(noise.size() - 1, int(float(noise.size()) * 0.995))])
	_eps = maxf(DIFF_EPS, p995 * 1.6)
	print("   composition: noise p99.5 = %.4f -> diff threshold %.4f" % [p995, _eps])

	var stands: Array = _find_named(arena, "VenueStands")
	var walls: Array = _find_named(arena, "VenueWalls")
	var ground: Array = _find_named(arena, "Ground")
	var props: Array = _find_named(arena, "Prop_")

	var st: Dictionary = await _layer_stats(stands, base)
	var wl: Dictionary = await _layer_stats(walls, base)
	var gr: Dictionary = await _layer_stats(ground, base)
	var pr: Dictionary = await _layer_stats(props, base)

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

	# Bodies, from the same frame, with the same bright-third sample pass 1 uses.
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var body_sum := 0.0
	var body_n := 0
	for nd in nodes:
		if bool(nd.get("dead", false)):
			continue
		var hn: Node3D = nd["holder"]
		for up in [1.4, 2.2, 3.0]:
			var l := _luma_bright_at(base, cam.unproject_position(
				hn.global_position + Vector3(0, up, 0)), vp, isz)
			if l >= 0.0:
				body_sum += l
				body_n += 1

	# ── PER-KIND PROP VALUE. ⚠️ SAMPLED GEOMETRICALLY, NOT BY ANOTHER VISIBILITY DIFF: a diff per
	# kind is nine more double frame-grabs per league and the whole sweep already takes minutes.
	# The top face of a cover piece is a large, flat, key-lit surface whose world position
	# `prop_report()` hands over exactly, so unprojecting it is reliable in a way that sampling a
	# ten-pixel creature is not. This is the table the prop TINTS are set from.
	# ⚠️ THE LADDER'S COVER TERM IS THE LIT FACE, NOT THE LAYER MEDIAN, AND THE FIRST VERSION GOT
	# THIS WRONG IN A WAY THAT LOOKED LIKE A REAL FAILURE. A prop has a lit face and a shadow side;
	# the ground is almost entirely lit. So the median over ALL prop pixels is structurally below
	# the median over all floor pixels even when the cover plainly reads above the ground — six
	# leagues "failed" the ladder on that asymmetry alone. Comparing the prop's LIT face against the
	# floor is the comparison the eye actually makes.
	var cover_lit: Array = []
	for p in arena.call("prop_report"):
		var c3: Vector3 = p["centre"]
		var top := c3 + Vector3(0, float(p["h"]) * 0.42, 0)
		if cam.is_position_behind(top) or not _clear_of(top, nodes):
			continue
		var sp := cam.unproject_position(top)
		var lp := _luma_bright_at(base, sp, vp, isz)
		if lp < 0.0:
			continue
		var k2: String = str(p["kind"])
		if not _kind_luma.has(k2):
			_kind_luma[k2] = []
			_kind_sat[k2] = []
		_kind_luma[k2].append(lp)
		_kind_sat[k2].append(_sat_at(base, sp, vp, isz))
		cover_lit.append(lp)

	# The cast's own saturation, for the same frame — the reference the props are judged against.
	for nd in nodes:
		if bool(nd.get("dead", false)):
			continue
		var hb: Node3D = nd["holder"]
		var s2 := _sat_at(base, cam.unproject_position(hb.global_position + Vector3(0, 2.2, 0)),
			vp, isz)
		if s2 >= 0.0:
			_body_sat.append(s2)

	# ⚠️ HAND THE ARENA BACK EXACTLY AS IT WAS FOUND, AND THIS COST A WHOLE RUN TO SPOT. Freezing
	# the scene is correct FOR THIS PASS and catastrophic for the next one: pass 1 takes a median
	# over three live frames a third of a second apart, and against a frozen replay it instead
	# sampled ONE instant three times. The measured body value fell from 0.45 to 0.25 at four
	# leagues and the value check dropped 11/11 -> 6/11 with no renderer change at all — a probe
	# reporting on its own side effect. An instrument must not perturb what it measures next.
	(arena as Node).process_mode = Node.PROCESS_MODE_INHERIT
	arena.set("playing", true)

	_shots.append({
		"league": league_name,
		"f_stands": st["frac"], "f_props": pr["frac"], "f_floor": gr["frac"],
		"f_empty": float(empty) / maxf(1.0, float(total)),
		"l_stands": st["luma"], "l_walls": wl["luma"], "l_floor": gr["luma"],
		"l_props": _median(cover_lit) if not cover_lit.is_empty() else pr["luma"],
		"l_body": (body_sum / float(body_n)) if body_n > 0 else -1.0,
	})


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
	for n in group:
		(n as VisualInstance3D).visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var off: Image = get_viewport().get_texture().get_image()
	for n in group:
		(n as VisualInstance3D).visible = true
	await RenderingServer.frame_post_draw

	var vals: Array = []
	var total := 0
	var w := mini(base.get_width(), off.get_width())
	var h := mini(base.get_height(), off.get_height())
	for x in range(0, w, DIFF_STEP):
		for y in range(0, h, DIFF_STEP):
			total += 1
			var a: float = base.get_pixel(x, y).get_luminance()
			var b: float = off.get_pixel(x, y).get_luminance()
			if absf(a - b) >= _eps:
				vals.append(a)
	if vals.is_empty():
		return {"frac": 0.0, "luma": -1.0}
	# ⚠️ THE MEDIAN, NOT A MEAN AND NOT THE BRIGHT HALF, AND THE REASON IS SET SIZE. Hiding a layer
	# also removes the SHADOW it casts, so the diffed set is the layer's own pixels plus a skirt of
	# floor that merely got lighter. A bright-half mean answers that by taking the top of the
	# distribution — but a layer covering 0.3% of the frame then reports the value of its rim-lit
	# top edges while one covering 30% reports a broad average, and comparing those two IS the
	# ladder. The median is size-neutral: it is the value of a TYPICAL pixel of this layer, which is
	# the question "does the cover read brighter than the floor" actually asks.
	vals.sort()
	return {
		"frac": float(vals.size()) / maxf(1.0, float(total)),
		"luma": float(vals[vals.size() / 2]),
	}


static func _median(a: Array) -> float:
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])


## Mean luminance of a 5x5 pixel patch, so one stray highlight cannot decide a sample. Returns -1
## when the point is off-frame.
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


## Mean of the brightest third of a 5x5 patch — see the note at the call site.
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
