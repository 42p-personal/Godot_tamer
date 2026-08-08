## THE FRAME COMPOSITION PROBE — cover relief, cover-vs-floor separation, and frame void.
##
## Run WINDOWED (it reads the framebuffer; --headless has none):
##   P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/_probe_frame.tscn
##
## ⚠️ WHY A SECOND LOOK PROBE ALONGSIDE `_probe_venue.gd`. That one asks "is the value ladder
## right" and answers it well. This round's three complaints are different questions it structurally
## cannot answer:
##
##   1. "the majors read as flat pasted rectangles" — a claim about the RELIEF of one object: the
##      difference between its TOP face and its SIDE face in the rendered frame. `_probe_venue`
##      samples only the top face, so a piece with no side at all scores identically to a piece
##      with a metre of visible wall.
##   2. "at Masters the cover hue-matches the floor" — a claim about HUE, and about the LOCAL floor
##      beside the piece, not the board median. `_probe_venue` compares luminance against a global
##      median; two objects can match that test perfectly and still be the same orange.
##   3. "~45% of the frame is black void" — `_probe_venue` measures `empty%` by matching the corner
##      pixel exactly, which reports 0% the moment anything non-flat is drawn back there. The
##      honest question is "how much of the frame carries no content", split ABOVE and BELOW the
##      venue, because those two are fixed by different things.
##
## ⚠️ AND IT SAMPLES ON A FROZEN FRAME, WHICH IS THE FIX FOR THE INSTRUMENT FAULT RECORDED IN
## `arena_3d.gd:OBSTACLE_TINT` (crate frozen at 0.477, planter at 0.243 across seven runs and five
## tints). Two causes were live at once and this probe removes both:
##   (a) the replay was still running, so a sample landed wherever the bodies happened to be;
##   (b) a small prop is a handful of pixels at whole-venue framing, so its unprojected top could
##       land on a banner, a creature or the floor behind it — and would then return the SAME
##       number whatever you did to the prop.
## The cure for (b) is not a better sample point, it is REFUSING TO SAMPLE. Every row below carries
## its projected pixel size and a piece under `MIN_PIXELS` is reported as `skip`, never as a value.
## An instrument that says "I cannot see this" is worth more than one that confidently reports the
## floor behind it.
extends Node

const TacticsScript = preload("res://scripts/tactics.gd")
const ARENA_SCENE := "res://scenes/arena3d.tscn"

## Every league with authored ground art — the hue collision is a per-league fault (Masters' red
## brick against red-brick cover) so a subset cannot see it.
const SWEEP := [
	"Wood", "Copper", "Tin", "Bronze", "Iron", "Silver",
	"Gold", "Platinum", "Masters", "Tamer Elite", "Tamers Apex",
]

## A prop whose drawn top face projects to fewer than this many pixels across is not measurable at
## whole-venue framing. See the header: reporting it anyway is what produced two frozen columns.
const MIN_PIXELS := 6.0
## Value separation a cover piece needs from the floor immediately beside it — |log2 ratio|, so it
## is symmetric (cover darker than floor is just as legible as brighter).
const SEP_VALUE := 0.16          # ~1.12x either way
## ⚠️ CHROMA SEPARATION, NOT HUE — AND THE FIRST VERSION OF THIS PROBE MEASURED HUE AND MISLED THE
## FIX IT WAS BUILT TO GUIDE. Hue is undefined at zero saturation and unstable near it, so the same
## nearly-grey timber reported 0.003 on one kind and 0.148 on another; worse, "increase the hue
## distance" is advice whose literal execution produced pink walls and green boulders. Distance in a
## cheap opponent-colour plane is well behaved at every saturation and cannot be satisfied by an
## absurd colour, because it counts DESATURATION as separation — which is what real masonry uses.
const SEP_CHROMA := 0.055
## Relief: side face against top face, |log2|. A box lit from above with no visible side reads 0.
const RELIEF_MIN := 0.20
## ⚠️ CONTACT SHADOW, AND ADDING IT IS THE MOST IMPORTANT CORRECTION THIS PROBE HAS HAD. The first
## version measured only face-against-face and reported "4 of 5 FLAT" both before and after a change
## that visibly transformed the board — because a cast shadow is not a property of any face. It is a
## dark shape on a THIRD surface, and an instrument that only ever samples the object cannot see the
## single strongest cue that the object is standing on something. Measured as the floor on the piece's
## shadow side against the floor on its lit side, in stops.
const SHADOW_MIN := 0.22
## The key lamp's horizontal shadow direction and length-per-unit-height, derived from the SAME
## rotation `arena_3d.gd` gives the key. ⚠️ Kept here as a documented constant rather than read off
## the light, because a probe that asks the renderer where its shadows go would agree with a broken
## renderer; this is the independent prediction the frame is checked against.
const KEY_SHADOW_DIR := Vector2(0.940, -0.342)
const KEY_SHADOW_PER_H := 1.19
## Anything at or below this luminance is carrying no content — void.
const VOID_LUMA := 0.045

## ⚠️ VOID_LUMA ALONE PASSES A FRAME THE EYE CALLS HALF-EMPTY, AND THAT IS THE FAULT THIS CONSTANT
## FIXES. The integrator's report said "~45% of the hero frame is black void"; measured at 0.045
## luma that is 2-9% and the check reads a comfortable green at 11/11. Both numbers are correct
## and only one of them is about the picture: a dead band is not *black*, it is a band with no
## content in it, and a row of near-black stand backs at 0.09 luma reads as nothing while
## measuring as something. The eye judges by ROW, so this measures by row.
##
## A row counts as DEAD when its mean luminance is under DIM_LUMA. 0.12 is set from the frames:
## the venue's darkest surface that still carries readable content (the far stand's shadowed
## coping) sits at 0.13-0.15, and the dead bands above and below the bowl sit at 0.06-0.10.
const DIM_LUMA := 0.12
## A third of the picture carrying nothing is the most a hero frame can afford. Set at the level
## the frames already reach at the best leagues (Copper/Iron ~0.22) rather than at an aspiration.
const DEAD_BAND_MAX := 0.30

## Leagues that also get a sample-point overlay saved beside the frame. Two is enough to audit the
## sampler; every league would be eleven more PNGs nobody opens.
const ANNOTATE := ["Wood", "Masters"]

var _annotate: Image = null
var _rows: Array = []       # per league composition
var _cover: Array = []      # per piece separation/relief
var _skipped := 0
var _sampled := 0


func _ready() -> void:
	for league in SWEEP:
		await _shoot(league)
	_report_void()
	_report_cover()
	get_tree().quit()


func _report_void() -> void:
	print("")
	print("═══ FRAME VOID (shipping hero frame, ARENA mode) ═══")
	print("league          void%   above%  below%  | dead-rows%  topband%  botband%  verdict")
	var bad := 0
	var dead_bad := 0
	for r in _rows:
		# A frame that is more than a quarter nothing is wasting the shot.
		var ok: bool = float(r["void"]) <= 0.25
		var dead_ok: bool = float(r["dead"]) <= DEAD_BAND_MAX
		if not ok:
			bad += 1
		if not dead_ok:
			dead_bad += 1
		var verdict := "ok"
		if not ok:
			verdict = "VOID"
		elif not dead_ok:
			verdict = "DEAD BANDS"
		print("%-14s  %5.1f   %5.1f   %5.1f  |   %5.1f      %5.1f     %5.1f    %s" % [
			r["league"], float(r["void"]) * 100.0, float(r["above"]) * 100.0,
			float(r["below"]) * 100.0, float(r["dead"]) * 100.0,
			float(r["top_run"]) * 100.0, float(r["bot_run"]) * 100.0, verdict])
	print("")
	print("%d/%d leagues fill the frame (literal void <= 25%%)" % [_rows.size() - bad, _rows.size()])
	print("%d/%d leagues carry content across the frame (dead rows <= %.0f%%)"
		% [_rows.size() - dead_bad, _rows.size(), DEAD_BAND_MAX * 100.0])


func _report_cover() -> void:
	print("")
	print("═══ COVER READS AS OBJECT (relief + separation from the floor beside it) ═══")
	print("league          kind            n   top    side   relief  shadow |  floor  dV     dChr   verdict")
	var by: Dictionary = {}
	for c in _cover:
		var k: String = "%s|%s" % [c["league"], c["kind"]]
		if not by.has(k):
			by[k] = []
		by[k].append(c)
	var keys: Array = by.keys()
	keys.sort()
	var flat := 0
	var merged := 0
	for k in keys:
		var arr: Array = by[k]
		var top := _median_of(arr, "top")
		var side := _median_of(arr, "side")
		var fl := _median_of(arr, "floor")
		var relief: float = absf(log(maxf(0.002, side) / maxf(0.002, top)) / log(2.0))
		var dv: float = absf(log(maxf(0.002, top) / maxf(0.002, fl)) / log(2.0))
		var dh := _median_of(arr, "dchroma")
		var sh := _median_of(arr, "shadow")
		var why := "ok"
		var ok := true
		# ⚠️ RELIEF **OR** SHADOW, NOT BOTH. Either one alone makes a piece read as an object — a
		# lit face against a dark face does it, and so does a shape thrown on the floor beside it.
		# Requiring both would fail a wall lit flat-on that casts a three-metre shadow, which is
		# exactly what an evening stadium looks like.
		if relief < RELIEF_MIN and sh < SHADOW_MIN:
			ok = false
			why = "PASTED (no side face, no shadow)"
			flat += 1
		if dv < SEP_VALUE and dh < SEP_CHROMA:
			ok = false
			why = ("MERGES WITH FLOOR" if why == "ok" else why + " + MERGES")
			merged += 1
		var parts: Array = k.split("|")
		print("%-14s  %-14s %2d  %.3f  %.3f  %5.2f   %5.2f  |  %.3f  %5.2f  %.3f  %s" % [
			parts[0], parts[1], arr.size(), top, side, relief, sh, fl, dv, dh, why])
	print("")
	print("%d of %d league/kind groups read PASTED (relief < %.2f AND shadow < %.2f stops)"
		% [flat, keys.size(), RELIEF_MIN, SHADOW_MIN])
	print("%d of %d league/kind groups MERGE with their floor (under %.2f stops AND under %.3f chroma)"
		% [merged, keys.size(), SEP_VALUE, SEP_CHROMA])
	print("sampled %d pieces, skipped %d as too small to measure (< %.0f px)"
		% [_sampled, _skipped, MIN_PIXELS])


func _setup_state(league_name: String) -> int:
	seed(20260808)
	Career.reset_new_game()
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
	var total: int = (arena.get("frames") as Array).size()
	for i in range(2000):
		await get_tree().process_frame
		if float(arena.get("frame_pos")) >= float(total) * 0.34:
			break

	var ov: CanvasLayer = arena.get("overlay")
	if ov != null:
		ov.visible = false

	# The whole-venue framing, then FROZEN — see the header on why every sample below is taken on a
	# stopped scene.
	arena.set("_cam_mode", 2)
	arena.set("playing", false)
	arena.call("_update_camera", 4.0)
	arena.call("_apply_camera_now")
	for i in range(6):
		await get_tree().process_frame
	(arena as Node).process_mode = Node.PROCESS_MODE_DISABLED
	for i in range(2):
		await get_tree().process_frame

	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var slug := league_name.to_lower().replace(" ", "-")
	img.save_png("user://frame_%s.png" % slug)

	var cam: Camera3D = arena.get("camera")
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var isz := Vector2(img.get_width(), img.get_height())
	_annotate = img.duplicate() if ANNOTATE.has(league_name) else null

	# ── VOID. Counted in thirds of frame height so "above the venue" and "below it" are separable:
	# the top is fixed by a backdrop, the bottom by venue geometry, and one number cannot tell you
	# which to reach for.
	var void_n := 0
	var above := 0
	var below := 0
	var above_n := 0
	var below_n := 0
	var total_px := 0
	var band := 0
	var h_i: int = img.get_height()
	# Row means, for the DEAD BAND measure. Accumulated in the same pass so the two numbers can
	# never disagree about which frame they describe.
	var row_sum := PackedFloat32Array()
	var row_n := PackedInt32Array()
	row_sum.resize(h_i)
	row_n.resize(h_i)
	for x in range(0, img.get_width(), 3):
		for y in range(0, h_i, 3):
			total_px += 1
			var l: float = img.get_pixel(x, y).get_luminance()
			row_sum[y] += l
			row_n[y] += 1
			var is_void: bool = l <= VOID_LUMA
			if is_void:
				void_n += 1
			if y < h_i / 3:
				above_n += 1
				if is_void:
					above += 1
			elif y >= h_i * 2 / 3:
				below_n += 1
				if is_void:
					below += 1
			if not is_void:
				band += 1
	# DEAD BANDS: rows whose MEAN luminance is under DIM_LUMA, and the longest unbroken such run at
	# the top and at the bottom of the frame. The run lengths are the actionable pair — a scatter of
	# dim rows through the venue is texture, a 200-row block above the bowl is a hole in the shot.
	var dead_rows := 0
	var rows_seen := 0
	var top_run := 0
	var bot_run := 0
	var top_open := true
	for y in range(h_i):
		if row_n[y] <= 0:
			continue
		rows_seen += 1
		var dim: bool = (row_sum[y] / float(row_n[y])) < DIM_LUMA
		if dim:
			dead_rows += 1
		if top_open:
			if dim:
				top_run += 1
			else:
				top_open = false
	for y2 in range(h_i - 1, -1, -1):
		if row_n[y2] <= 0:
			continue
		if (row_sum[y2] / float(row_n[y2])) < DIM_LUMA:
			bot_run += 1
		else:
			break
	_rows.append({
		"league": league_name,
		"void": float(void_n) / maxf(1.0, float(total_px)),
		"above": float(above) / maxf(1.0, float(above_n)),
		"below": float(below) / maxf(1.0, float(below_n)),
		"band": float(band) / maxf(1.0, float(total_px)),
		"dead": float(dead_rows) / maxf(1.0, float(rows_seen)),
		"top_run": float(top_run) / maxf(1.0, float(h_i)),
		"bot_run": float(bot_run) / maxf(1.0, float(h_i)),
	})

	# ── COVER: top face, front face, and the floor immediately beside the piece.
	#
	# ⚠️ THE FLOOR REFERENCE IS LOCAL, NOT THE BOARD MEDIAN. "It hue-matches the floor" is a claim
	# about the two square metres around the piece; a median over the whole board averages the
	# deploy-zone paint, the centre stripe and the shadowed far end into a colour nothing on screen
	# actually is.
	for p in arena.call("prop_report"):
		var c3: Vector3 = p["centre"]          # already the piece's mid-height centre
		var ph: float = float(p["h"])
		var pw: float = float(p["w"])
		var pd: float = float(p["d"])
		var top_w := c3 + Vector3(0, ph * 0.5, 0)
		if cam.is_position_behind(top_w):
			continue
		# Projected size of the piece's own top face — the refusal test.
		var a := cam.unproject_position(c3 + Vector3(-pw * 0.5, ph * 0.5, 0))
		var b := cam.unproject_position(c3 + Vector3(pw * 0.5, ph * 0.5, 0))
		var px: float = a.distance_to(b)
		if px < MIN_PIXELS:
			_skipped += 1
			continue
		# The camera looks from +Z, so the +Z face is the one facing it.
		var side_w := c3 + Vector3(0, -ph * 0.16, pd * 0.5 + 0.02)
		var floor_w := c3 + Vector3(0, -ph * 0.5, pd * 0.5 + maxf(2.0, pd * 0.8))
		# The floor where the piece's own shadow must land, and the floor directly opposite it. Both
		# are clear of the piece by half its footprint plus a margin, so neither can sample the prop.
		var reach: float = maxf(pw, pd) * 0.5 + ph * KEY_SHADOW_PER_H * 0.55
		var shadow_w := Vector3(c3.x + KEY_SHADOW_DIR.x * reach, 0.05,
			c3.z + KEY_SHADOW_DIR.y * reach)
		var lit_w := Vector3(c3.x - KEY_SHADOW_DIR.x * reach, 0.05,
			c3.z - KEY_SHADOW_DIR.y * reach)
		var top_c := _colour_at(img, cam.unproject_position(top_w), vp, isz)
		var side_c := _colour_at(img, cam.unproject_position(side_w), vp, isz)
		var floor_c := _colour_at(img, cam.unproject_position(floor_w), vp, isz)
		var shadow_c := _colour_at(img, cam.unproject_position(shadow_w), vp, isz)
		var lit_c := _colour_at(img, cam.unproject_position(lit_w), vp, isz)
		if top_c.a < 0.5 or side_c.a < 0.5 or floor_c.a < 0.5:
			_skipped += 1
			continue
		_sampled += 1
		# ⚠️ THE SAMPLE POINTS ARE DRAWN ONTO A COPY OF THE FRAME AND SAVED. The first run of this
		# probe reported 0.05 stops of relief where the lamp arithmetic predicts 0.4-0.6, and there
		# are only two ways that happens: the renderer is doing something the arithmetic does not
		# model, or the probe is not sampling the faces it thinks it is. A picture with the three
		# points marked on it settles which, in one look, and costs one PNG per league.
		if _annotate != null:
			_mark(_annotate, cam.unproject_position(top_w), vp, isz, Color(1, 0, 0))
			_mark(_annotate, cam.unproject_position(side_w), vp, isz, Color(0, 1, 0))
			_mark(_annotate, cam.unproject_position(floor_w), vp, isz, Color(0, 0.4, 1))
		_cover.append({
			"league": league_name, "kind": str(p["kind"]),
			"top": top_c.get_luminance(), "side": side_c.get_luminance(),
			"floor": floor_c.get_luminance(),
			"dchroma": _chroma_of(top_c).distance_to(_chroma_of(floor_c)),
			"shadow": (absf(log(maxf(0.002, lit_c.get_luminance())
				/ maxf(0.002, shadow_c.get_luminance())) / log(2.0))
				if (shadow_c.a > 0.5 and lit_c.a > 0.5) else -1.0),
			"px": px,
		})

	if _annotate != null:
		_annotate.save_png("user://frame_%s_pts.png" % slug)
		_annotate = null
	(arena as Node).process_mode = Node.PROCESS_MODE_INHERIT
	arena.set("playing", true)
	print("shot %-14s -> %s" % [league_name,
		ProjectSettings.globalize_path("user://frame_%s.png" % slug)])
	await _teardown(arena)


## See `_probe_venue.gd:_teardown` — the descriptor heap runs out on a sweep that does not wait.
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


## Mean colour of a 5x5 patch. Alpha 0 means off-frame — the caller must check it rather than
## receive a plausible-looking black.
func _colour_at(img: Image, screen_pos: Vector2, vp: Vector2, isz: Vector2) -> Color:
	var p := Vector2(screen_pos.x / maxf(1.0, vp.x) * isz.x, screen_pos.y / maxf(1.0, vp.y) * isz.y)
	if p.x < 3 or p.y < 3 or p.x >= isz.x - 3 or p.y >= isz.y - 3:
		return Color(0, 0, 0, 0)
	var acc := Color(0, 0, 0)
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			acc += img.get_pixel(int(p.x) + dx, int(p.y) + dy)
	var c: Color = acc / 25.0
	c.a = 1.0
	return c


## A 3x3 dot at a screen position, in image pixels. Marks where a sample was actually taken.
static func _mark(img: Image, screen_pos: Vector2, vp: Vector2, isz: Vector2, col: Color) -> void:
	var p := Vector2(screen_pos.x / maxf(1.0, vp.x) * isz.x, screen_pos.y / maxf(1.0, vp.y) * isz.y)
	if p.x < 2 or p.y < 2 or p.x >= isz.x - 2 or p.y >= isz.y - 2:
		return
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			img.set_pixel(int(p.x) + dx, int(p.y) + dy, col)


## The same two opponent axes `arena_3d.gd:_chroma_of` uses. ⚠️ Duplicated deliberately: the probe
## must not import its own subject's idea of colour distance, or a bug in that function would make
## the renderer and the instrument agree with each other and with nothing else.
static func _chroma_of(c: Color) -> Vector2:
	return Vector2(c.r - c.g, 0.5 * (c.r + c.g) - c.b)


static func _median_of(arr: Array, key: String) -> float:
	var v: Array = []
	for e in arr:
		v.append(float(e[key]))
	v.sort()
	return float(v[v.size() / 2])
