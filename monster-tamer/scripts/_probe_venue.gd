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


func _ready() -> void:
	for league in SWEEP:
		await _shoot(league)
	print("")
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
	get_tree().quit()


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
