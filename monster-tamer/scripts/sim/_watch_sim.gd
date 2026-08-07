## WATCH THE REWRITTEN SIM — the first human-viewable battle on the new stack. Runs a 5v5 on
## sim.gd (real species stats, real data.json kits, the five positional tactics on display),
## then replays the frame stream with creature rigs and LIVE INTENT LABELS — the legibility
## payoff the whole tree architecture exists for. Dev scene; the production renderer switch
## follows once this view proves the stream carries everything a viewer needs.
##
## PRESENTATION PASS (2026-08-07): the board reads as a built PLACE now — textured league
## ground, perimeter rail, stone cover, tiered stands with the seated crowd, a drifting camera
## that keeps the fight framed, hit flinches, pooled VFX and a winner banner. Every visual is
## an echo of an event the sim already emitted; the renderer still derives NOTHING.
extends Node3D

const Sim = preload("res://scripts/sim/sim.gd")
const Kit = preload("res://scripts/sim/kit.gd")
const Rig = preload("res://scripts/ui/creature_rig.gd")

const GROUND := Vector2(110, 62)
const OBSTACLES := [{"rect": Rect2(-14, -9, 7, 7)}, {"rect": Rect2(7, 3, 7, 7)}]
const TEAM_COL := {"A": Color(0.35, 0.55, 0.95), "B": Color(0.85, 0.35, 0.3)}

## How long a corpse lies before it sinks away (design: deaths must be READ, then decluttered).
const CORPSE_LINGER := 3.0

var _frames: Array = []
var _result: Dictionary = {}
var _rigs := {}
var _labels := {}
var _discs := {}          # uid -> team-colour ground ring (the at-a-glance side read)
var _base_scale := {}     # uid -> the rig's build-time scale (pop tweens return here)
var _pop_tweens := {}     # uid -> active scale-pop tween (killed before restarting)
var _unit_index := {}     # uid -> stable int (cast-glow pool key)
var _move_by_name := {}   # data.json move name -> the full move dict (VFX recipes want it)
var _t := 0.0
var _fi := 0
var _done := false

var _cam: Camera3D
var _cam_look := Vector3.ZERO
var _team_size := 5       # per side, read from setup — the camera push-in denominator

var _vfx: Node3D = null   # BattleVfx, or null if anything about it is missing (degrade, never crash)
var _crowd: Node3D = null


func _ready() -> void:
	_build_environment()
	_build_arena()
	_build_stands_and_crowd()
	_cam = Camera3D.new()
	_cam.position = Vector3(0, 52, 58)
	add_child(_cam)
	_cam_look = Vector3(0, 0, -2)
	_cam.look_at(_cam_look)
	# VFX library — optional dependency: a missing file or a load failure degrades to nothing.
	if ResourceLoader.exists("res://scripts/ui/vfx.gd"):
		var vfx_script = load("res://scripts/ui/vfx.gd")
		if vfx_script != null:
			_vfx = vfx_script.new()
			add_child(_vfx)
	_run_fight()


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# ARENA DRESSING — the board as a built place (docs/ARENA_DESIGN.md: architecture is the default)
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.10, 0.14)   # night-venue navy, not debug grey
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.68, 0.68, 0.76)
	e.fog_enabled = true
	e.fog_light_color = Color(0.10, 0.11, 0.15)
	e.fog_density = 0.004   # the stands soften into the dark; the fight stays crisp
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.light_color = Color(1.0, 0.96, 0.88)   # the one warm working lamp (ART_DIRECTION)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var rim := DirectionalLight3D.new()   # cool fill from behind so silhouettes separate
	rim.rotation_degrees = Vector3(-30, 145, 0)
	rim.light_color = Color(0.55, 0.62, 0.85)
	rim.light_energy = 0.35
	add_child(rim)


func _build_arena() -> void:
	# ── the ground: real league art when present, honest flat clay when not ──
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = GROUND
	floor_mi.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.roughness = 1.0
	var ground_tex: Texture2D = null
	if Art != null and Art.has_method("ground_for"):
		ground_tex = Art.ground_for("Platinum", Art.ARENA_LEAGUES)
	if ground_tex != null:
		fmat.albedo_texture = ground_tex
		# The jpg is a seamless square tile; repeat it every ~14 world units.
		fmat.uv1_scale = Vector3(GROUND.x / 14.0, GROUND.y / 14.0, 1.0)
	else:
		fmat.albedo_color = Color(0.24, 0.22, 0.19)
	floor_mi.material_override = fmat
	add_child(floor_mi)

	# ── the apron: a darker skirt under the stands so the field reads as raised and bounded ──
	var apron := MeshInstance3D.new()
	var am := PlaneMesh.new()
	am.size = Vector2(GROUND.x + 48, GROUND.y + 48)
	apron.mesh = am
	var amat := StandardMaterial3D.new()
	amat.albedo_color = Color(0.13, 0.125, 0.12)
	amat.roughness = 1.0
	apron.material_override = amat
	apron.position.y = -0.06
	add_child(apron)

	# ── stone: shared material for rail, obstacles and stands ──
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.42, 0.39, 0.35)
	stone.roughness = 0.95
	var stone_dark := StandardMaterial3D.new()
	stone_dark.albedo_color = Color(0.30, 0.28, 0.26)
	stone_dark.roughness = 0.95

	# ── perimeter rail: a low wall at the field edge, with corner pylons ──
	var hx := GROUND.x * 0.5
	var hz := GROUND.y * 0.5
	var rail_h := 1.3
	var rail_t := 1.0
	for side in range(4):
		var wall := MeshInstance3D.new()
		var wm := BoxMesh.new()
		var horizontal := side < 2
		wm.size = Vector3(GROUND.x + rail_t * 2.0, rail_h, rail_t) if horizontal \
			else Vector3(rail_t, rail_h, GROUND.y + rail_t * 2.0)
		wall.mesh = wm
		wall.material_override = stone
		wall.position = Vector3(0, rail_h * 0.5, (hz + rail_t * 0.5) * (1 if side == 0 else -1)) if horizontal \
			else Vector3((hx + rail_t * 0.5) * (1 if side == 2 else -1), rail_h * 0.5, 0)
		add_child(wall)
	for cx in [-1, 1]:
		for cz in [-1, 1]:
			var py := MeshInstance3D.new()
			var pyl := BoxMesh.new()
			pyl.size = Vector3(2.2, 3.4, 2.2)
			py.mesh = pyl
			py.material_override = stone_dark
			py.position = Vector3(hx * cx + rail_t * 0.5 * cx, 1.7, hz * cz + rail_t * 0.5 * cz)
			add_child(py)

	# ── obstacles: the sim's cover blocks, dressed as cut stone with a cap ──
	for ob in OBSTACLES:
		var r: Rect2 = ob["rect"]
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(r.size.x, 3.0, r.size.y)
		box.mesh = bm
		box.material_override = stone
		box.position = Vector3(r.get_center().x, 1.5, r.get_center().y)
		add_child(box)
		var cap := MeshInstance3D.new()
		var cm := BoxMesh.new()
		cm.size = Vector3(r.size.x + 0.7, 0.4, r.size.y + 0.7)   # the overhang says "built"
		cap.mesh = cm
		cap.material_override = stone_dark
		cap.position = Vector3(r.get_center().x, 3.2, r.get_center().y)
		add_child(cap)


## Tiered stands on all four sides, matching the seat grid spectators.gd lays out
## (rows at off = 4.5 + row*3.5 beyond the field edge), then the crowd itself.
func _build_stands_and_crowd() -> void:
	var step_mat := StandardMaterial3D.new()
	step_mat.albedo_color = Color(0.26, 0.25, 0.24)
	step_mat.roughness = 1.0
	var hx := GROUND.x * 0.5
	var hz := GROUND.y * 0.5
	for row in range(5):
		var off := 4.5 + row * 3.5
		var top := 1.0 + row * 1.4   # seat lift is 1.6 + row*1.4 (step + seated hip)
		for side in range(4):
			var step := MeshInstance3D.new()
			var sm := BoxMesh.new()
			var horizontal := side < 2
			if horizontal:
				sm.size = Vector3(GROUND.x * 0.96, top, 3.5)
			else:
				sm.size = Vector3(3.5, top, GROUND.y * 0.86)
			step.mesh = sm
			step.material_override = step_mat
			if horizontal:
				step.position = Vector3(0, top * 0.5, (hz + off) * (1 if side == 0 else -1))
			else:
				step.position = Vector3((hx + off) * (1 if side == 2 else -1), top * 0.5, 0)
			add_child(step)
	# The crowd builder speaks GRID coordinates (0..ground); this scene's world is centred.
	if ResourceLoader.exists("res://scripts/ui/spectators.gd"):
		var spec_script = load("res://scripts/ui/spectators.gd")
		if spec_script != null:
			_crowd = spec_script.new()
			add_child(_crowd)
			var to_world := func(g: Vector2) -> Vector3:
				return Vector3(g.x - GROUND.x * 0.5, 0.0, g.y - GROUND.y * 0.5)
			if _crowd.has_method("build"):
				_crowd.build(GROUND, to_world, 0.45)


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# THE FIGHT — unchanged sim path; presentation reads its stream
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _run_fight() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/data.json"))
	var moves: Array = data["moves"]
	for m in moves:
		_move_by_name[str(m.get("name", ""))] = m
	var by_id := {}
	for sp in data["species"]:
		by_id[str(sp.id)] = sp
	var magic: Array = moves.filter(func(m): return str(m.get("channel")) == "magic" and str(m.get("type")) == "damage")
	magic.sort_custom(func(a, b): return str(a.name) < str(b.name))

	# Ten real species from the roster; team A shows the tactic spread, B pushes classically.
	var roster: Array = Art.ROSTER.slice(0, 10)
	var tactics_a: Array = [
		{"target_priority": "casters", "positional": "push"},
		{"target_priority": "nearest", "positional": "guard", "guard_ally": ""},
		{"target_priority": "weakest", "positional": "wings", "wing_side": 1},
		{"target_priority": "weakest", "positional": "hold"},
		{"target_priority": "weakest", "positional": "dive", "when_hurt": "fall_back"},
	]
	var us: Array = []
	var caster_a := ""
	for i in roster.size():
		var sid: String = str(roster[i])
		var sp: Dictionary = by_id[sid]
		var base: Dictionary = sp["base"]
		var team := "A" if i < 5 else "B"
		var idx := i % 5
		var stats := {}
		for k in ["STR", "DEX", "CON", "WIS", "INT", "CHA"]:
			stats[k] = float(base.get(k, 10)) * 1.6   # early-career scale
		var uid := "%s%d" % [team.to_lower(), idx]
		var kit: Array = []
		if float(stats["INT"]) >= 40.0:
			kit = Kit.build([str(magic[idx % magic.size()].name)], moves)
			if team == "A" and caster_a == "":
				caster_a = uid
		elif float(stats["STR"]) >= 55.0:
			kit = [Kit.kick()]
		var tac: Dictionary = tactics_a[idx].duplicate() if team == "A" \
			else {"target_priority": "nearest", "positional": "push"}
		us.append({"id": uid, "team": team, "species": sid,
			"pos": Vector2(-38 if team == "A" else 38, -14 + 7 * idx),
			"speed": 7.0 + float(stats["DEX"]) * 0.03,
			"stats": stats, "kit": kit, "tactics": tac})
	# The guard guards team A's first caster (or its neighbour if no caster rolled).
	for u in us:
		if u.tactics.get("positional", "") == "guard":
			u.tactics["guard_ally"] = caster_a if caster_a != "" else "a0"
	_team_size = 5

	var sim = Sim.new()
	sim.setup(2026, us, GROUND, OBSTACLES)
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-38, 0), Vector2(38, 0))
	assert(ok, "nav never became ready")
	_result = sim.run()
	_frames = _result.frames
	print("WATCH: winner=%s ticks=%d frames=%d" % [str(_result.winner), int(_result.ticks), _frames.size()])

	# Bodies + labels + team rings.
	var next_idx := 0
	for u in us:
		var rig = Rig.new()
		add_child(rig)
		if not rig.build(str(u.species), 4.2):
			var box := MeshInstance3D.new()
			box.mesh = CapsuleMesh.new()
			rig.add_child(box)
		_rigs[u.id] = rig
		_base_scale[u.id] = rig.scale
		_unit_index[u.id] = next_idx
		next_idx += 1
		var disc := MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = 2.5
		dm.bottom_radius = 2.5
		dm.height = 0.07
		disc.mesh = dm
		var dmat := StandardMaterial3D.new()
		dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dmat.albedo_color = Color(TEAM_COL[u.team], 0.55)
		dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		disc.material_override = dmat
		disc.position = Vector3(u.pos.x, 0.06, u.pos.y)
		add_child(disc)
		_discs[u.id] = disc
		var lbl := Label3D.new()
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.font_size = 44
		lbl.outline_size = 14
		lbl.pixel_size = 0.030
		lbl.modulate = TEAM_COL[u.team]
		add_child(lbl)
		_labels[u.id] = lbl


func _process(delta: float) -> void:
	if _frames.is_empty() or _done:
		return
	_t += delta
	var target_fi := mini(int(_t / Sim.DT), _frames.size() - 1)
	while _fi < target_fi:
		_fi += 1
		var f: Dictionary = _frames[_fi]
		for e in f.events:
			_present_event(e)
		for uf in f.units:
			var uid := str(uf.id)
			var rig = _rigs.get(uid)
			var lbl: Label3D = _labels.get(uid)
			if rig == null:
				continue
			rig.position = Vector3(uf.pos.x, rig.position.y, uf.pos.y)
			var st := str(uf.state)
			rig.set_state("dead" if st == "dead" else ("cast" if st == "cast" else ("advance" if st == "advance" else "idle")),
				Vector2(uf.facing) if uf.facing != Vector2.ZERO else Vector2(1, 0))
			var disc: MeshInstance3D = _discs.get(uid)
			if disc != null:
				disc.position = Vector3(uf.pos.x, 0.06, uf.pos.y)
				disc.visible = st != "dead"
			# The cast telegraph: a looping glow at the caster's feet while committed.
			if _vfx != null and _vfx.has_method("cast_glow"):
				if st == "cast":
					_vfx.cast_glow(int(_unit_index[uid]), rig, Color(0.72, 0.50, 0.95))
				else:
					_vfx.end_cast_glow(int(_unit_index[uid]))
			# The label IS the legibility layer: name · hp — then the LIVE INTENT from the tree,
			# and a cast bar when committed.
			var line2: String = str(uf.intent)
			if str(uf.get("posture", "")) != "" and str(uf.posture) != "Push":
				line2 = "%s · %s" % [str(uf.posture), str(uf.intent)]
			if str(uf.castMove) != "":
				var frac: float = float(uf.castFrac)
				var bars: int = int(frac * 8.0)
				line2 = "%s %s" % [str(uf.castMove), "▰".repeat(bars) + "▱".repeat(8 - bars)]
			lbl.text = "" if st == "dead" else "%s %d%%\n%s" % [str(uf.id), int(100.0 * float(uf.hp) / float(uf.max_hp)), line2]
			lbl.position = Vector3(uf.pos.x, 7.2, uf.pos.y)
	_drift_camera(delta)
	if _fi >= _frames.size() - 1 and not _done:
		_done = true
		_show_winner_banner()
		print("WATCH: replay complete — winner %s" % str(_result.winner))


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# EVENT PRESENTATION — flinches, pops, VFX, crowd. Every effect echoes a sim event.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _present_event(e: Dictionary) -> void:
	var kind := str(e.kind)
	var victim = _rigs.get(str(e.get("to", "")))
	var caster = _rigs.get(str(e.get("from", "")))
	var vpos: Vector3 = victim.position if victim != null else Vector3.ZERO
	var cpos: Vector3 = caster.position if caster != null else vpos
	match kind:
		"strike":
			if victim != null:
				if victim.has_method("flinch"):
					victim.flinch()
				_scale_pop(str(e.to))
				_float_dmg(str(e.to), int(e.get("dmg", 0)), false)
			if _vfx != null and _vfx.has_method("burst"):
				_vfx.burst(vpos + Vector3(0, 2.0, 0), "slash", Color(0.95, 0.68, 0.25), 1.0, 8)
				if bool(e.get("crit", false)):
					_vfx.burst(vpos + Vector3(0, 2.2, 0), "spark", Color(1.0, 0.9, 0.5), 1.3, 10)
					_crowd_react(0.25)
		"cast_start":
			if _vfx != null and _vfx.has_method("flip") and caster != null:
				_vfx.flip(cpos + Vector3(0, 2.5, 0), "charge", 3.5, Color(0.85, 0.75, 1.0), 0.5)
		"cast_done":
			if victim != null:
				if victim.has_method("flinch"):
					victim.flinch()
				_scale_pop(str(e.to))
				_float_dmg(str(e.to), int(e.get("dmg", 0)), true)
			var mv: Dictionary = _move_by_name.get(str(e.get("move", "")), {})
			if _vfx != null and _vfx.has_method("play_ability") and not mv.is_empty():
				_vfx.play_ability(mv, cpos + Vector3(0, 2.0, 0), vpos, bool(e.get("crit", false)))
			elif _vfx != null and _vfx.has_method("burst"):
				_vfx.burst(vpos + Vector3(0, 2.0, 0), "magic", Color(0.72, 0.50, 0.95), 1.3, 12)
			if bool(e.get("crit", false)):
				_crowd_react(0.3)
		"interrupt":
			if _vfx != null and _vfx.has_method("burst") and victim != null:
				_vfx.burst(vpos + Vector3(0, 3.0, 0), "spark", Color(1.0, 0.95, 0.6), 1.4, 12)
			if _vfx != null and _vfx.has_method("light_flash") and victim != null:
				_vfx.light_flash(vpos, Color(1.0, 0.95, 0.6), 3.0, 0.25)
			_crowd_react(0.35)
		"death":
			var uid := str(e.get("id", ""))
			_begin_corpse_fade(uid)
			var rig = _rigs.get(uid)
			if _vfx != null and _vfx.has_method("burst") and rig != null:
				_vfx.burst(rig.position + Vector3(0, 1.0, 0), "smoke", Color(0.5, 0.48, 0.46), 1.4, 12)
			_crowd_react(0.85)
		_:
			pass   # miss / cast_miss / fizzle stay silent — absence of impact IS the read


## A brief scale-pop on the victim: game feel, returns exactly to the rig's build scale.
func _scale_pop(uid: String) -> void:
	var rig = _rigs.get(uid)
	if rig == null or not _base_scale.has(uid):
		return
	var base: Vector3 = _base_scale[uid]
	var old: Tween = _pop_tweens.get(uid)
	if old != null and old.is_valid():
		old.kill()
	rig.scale = base * 1.14
	var tw := create_tween()
	tw.tween_property(rig, "scale", base, 0.16).set_ease(Tween.EASE_OUT)
	_pop_tweens[uid] = tw


## The death state plays from the frame stream; after a linger the corpse sinks and hides,
## so a long fight's floor does not fill with bodies the camera must keep dodging.
func _begin_corpse_fade(uid: String) -> void:
	if _rigs.get(uid) == null:
		return
	get_tree().create_timer(CORPSE_LINGER).timeout.connect(_sink_corpse.bind(uid))


func _sink_corpse(uid: String) -> void:
	var rig = _rigs.get(uid)
	if rig == null or not is_instance_valid(rig):
		return
	var tw := create_tween()
	tw.tween_property(rig, "position:y", rig.position.y - 4.0, 1.2).set_ease(Tween.EASE_IN)
	tw.tween_callback(_hide_corpse.bind(uid))


func _hide_corpse(uid: String) -> void:
	var rig = _rigs.get(uid)
	if rig != null and is_instance_valid(rig):
		rig.visible = false


func _crowd_react(intensity: float) -> void:
	if _crowd != null and _crowd.has_method("react"):
		_crowd.react(intensity)


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# CAMERA — a slow drift framing the centroid of the living, pushing in as numbers drop. No cuts.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _drift_camera(delta: float) -> void:
	if _cam == null or _frames.is_empty():
		return
	var f: Dictionary = _frames[mini(_fi, _frames.size() - 1)]
	var centroid := Vector2.ZERO
	var alive := 0
	for uf in f.units:
		if bool(uf.get("alive", true)):
			centroid += Vector2(uf.pos)
			alive += 1
	if alive == 0:
		return
	centroid /= float(alive)
	# Push in as the fight thins: full house = the wide shot, last duel = close and low.
	var frac: float = clampf(float(alive) / float(_team_size * 2), 0.0, 1.0)
	var zoom: float = lerpf(0.60, 1.0, frac)
	var desired := Vector3(centroid.x * 0.55, 52.0 * zoom, centroid.y * 0.55 + 58.0 * zoom)
	var k: float = 1.0 - exp(-1.4 * delta)     # slow exponential drift — never a snap
	_cam.position = _cam.position.lerp(desired, k)
	var look_target := Vector3(centroid.x, 2.0, centroid.y)
	_cam_look = _cam_look.lerp(look_target, k)
	_cam.look_at(_cam_look)


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# WINNER BANNER
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _show_winner_banner() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var lbl := Label.new()
	var w := str(_result.get("winner", ""))
	var dur := float(int(_result.get("ticks", 0))) * Sim.DT
	lbl.text = ("DRAW — %.1fs" % dur) if w == "draw" else ("TEAM %s WINS — %.1fs" % [w, dur])
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.add_theme_font_size_override("font_size", 72)
	lbl.add_theme_color_override("font_color", TEAM_COL.get(w, Color(0.9, 0.9, 0.9)))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 18)
	lbl.modulate.a = 0.0
	layer.add_child(lbl)
	var tw := create_tween()
	tw.tween_property(lbl, "modulate:a", 1.0, 0.6)


func _float_dmg(uid: String, dmg: int, is_cast: bool) -> void:
	var f = _rigs.get(uid)
	if f == null or dmg <= 0:
		return
	var d := Label3D.new()
	d.text = str(dmg)
	d.font_size = 56 if is_cast else 44
	d.outline_size = 12
	d.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	d.no_depth_test = true
	d.pixel_size = 0.032
	d.modulate = Color(0.95, 0.55, 0.95) if is_cast else Color(1.0, 0.85, 0.4)
	d.position = f.position + Vector3(0, 5.4, 0)
	add_child(d)
	var tw := create_tween()
	tw.tween_property(d, "position:y", d.position.y + 2.6, 0.8)
	tw.parallel().tween_property(d, "modulate:a", 0.0, 0.8)
	tw.tween_callback(d.queue_free)
