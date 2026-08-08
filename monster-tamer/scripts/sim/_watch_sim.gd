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
##
## POLISH PASS 2 (2026-08-07): ground tinted to warm stone (creatures brightest on the board),
## per-unit label shelf heights + distance shrink (scrum stays readable), hp% coloured by band,
## camera glides high→side-on as the deploy becomes the fight, status chips render IF the frame
## stream ever carries 'statuses' (guarded, degrades to nothing), and the winner banner waits
## for the corpses to sink.
##
## WATCH UX PASS (2026-08-07): opening card (both rosters, tactics + kits — the READ before the
## answer), playback controls (SPACE pause · 1/2/4 speed · R replays the SAME frames, never a
## re-sim), a fading kill feed, an end scoreboard aggregated from the stream (damage dealt/taken,
## healing only if the stream carries heal events, decisions from the per-unit decision log),
## and big-hit feedback (sine-based camera micro-shake — NO randf — plus a larger crit pop).
extends Node3D

const Sim = preload("res://scripts/sim/sim.gd")
const Kit = preload("res://scripts/sim/kit.gd")
const Rig = preload("res://scripts/ui/creature_rig.gd")
const UiTheme = preload("res://scripts/ui/theme.gd")

const GROUND := Vector2(110, 62)
const OBSTACLES := [{"rect": Rect2(-14, -9, 7, 7)}, {"rect": Rect2(7, 3, 7, 7)}]
const TEAM_COL := {"A": Color(0.35, 0.55, 0.95), "B": Color(0.85, 0.35, 0.3)}

## How long a corpse lies before it sinks away (design: deaths must be READ, then decluttered).
const CORPSE_LINGER := 3.0
## The winner banner waits for the last corpse to sink so the final frame is a clean board.
const BANNER_DELAY := CORPSE_LINGER + 1.6

## HP% reads by BAND, not by number: white = healthy, amber = pressured, red = dying.
const HP_GOOD := Color(0.96, 0.96, 0.96)
const HP_MID := Color(1.0, 0.72, 0.25)
const HP_LOW := Color(1.0, 0.30, 0.25)

## Status chip colours (dots under the label). Anything unmapped gets neutral grey.
const STATUS_COL := {
	"poison": Color(0.35, 0.85, 0.30), "burn": Color(1.0, 0.55, 0.15),
	"bleed": Color(0.80, 0.15, 0.15), "stun": Color(1.0, 0.90, 0.30),
	"blind": Color(0.55, 0.55, 0.60), "fear": Color(0.60, 0.30, 0.80),
	"confusion": Color(0.95, 0.55, 0.85), "silence": Color(0.35, 0.55, 0.95),
	"vulnerable": Color(0.95, 0.35, 0.70), "sleep": Color(0.65, 0.78, 0.95),
	"doom": Color(0.25, 0.20, 0.30), "haste": Color(0.30, 0.90, 0.90),
	"charm": Color(0.95, 0.60, 0.65), "healblock": Color(0.65, 0.65, 0.30),
}
const MAX_CHIPS := 4

var _frames: Array = []
var _result: Dictionary = {}
var _rigs := {}
var _labels := {}
var _discs := {}          # uid -> team-colour ground ring (the at-a-glance side read)
var _base_scale := {}     # uid -> the rig's build-time scale (pop tweens return here)
var _pop_tweens := {}     # uid -> active scale-pop tween (killed before restarting)
var _unit_index := {}     # uid -> stable int (cast-glow pool key)
var _label_h := {}        # uid -> stable label height (id-order slot; breaks scrum overlap)
var _chips := {}          # uid -> Array[MeshInstance3D], the pooled status dots
var _move_by_name := {}   # data.json move name -> the full move dict (VFX recipes want it)
var _t := 0.0
var _fi := 0
var _done := false

## ── watch-UX state ──
const INTRO_TIME := 2.5   # the opening card holds this long before the replay rolls
const FEED_HOLD := 3.2    # kill-feed line holds, then fades over FEED_FADE
const FEED_FADE := 0.8
var _us_meta: Array = []  # per-unit roster facts for the card + scoreboard (threaded from _run_fight)
var _spawn := {}          # uid -> deploy Vector2 (restart resets bodies here)
var _rig_y := {}          # uid -> the rig's build-time y (corpse sink moves it; restart restores)
var _paused := false
var _speed := 1.0
var _intro_left := 0.0
var _gen := 0             # replay generation — corpse/banner timers from a stale replay no-op
var _intro_layer: CanvasLayer = null
var _hud_layer: CanvasLayer = null
var _speed_lbl: Label = null
var _feed_box: VBoxContainer = null
var _end_layer: CanvasLayer = null
var _last_hit := {}       # uid -> {"from","move"} — the kill feed's attribution memory
var _shake := 0.0         # camera micro-shake magnitude; decays exponentially
var _sink_tweens := {}    # uid -> active corpse-sink tween (killed on restart)
var _has_heal := false    # the stream carried >=1 heal event → scoreboard shows the column
var _totals := {}         # uid -> {dealt, taken, healed} aggregated ONCE from the frame stream

var _cam: Camera3D
var _cam_look := Vector3.ZERO
var _team_size := 5       # per side, read from setup — the camera push-in denominator

## In-flight shots (#34), pooled by index: the sim streams a projectiles array per frame and
## this pool grows to the high-water mark, never per-shot allocation. A shot the stream stops
## publishing simply hides — arrival, fizzle and expiry all read the same to the pool.
var _shots: Array = []          # Array[MeshInstance3D], the pooled projectile bodies
var _shot_trails: Array = []    # Array[MeshInstance3D], the stretched tail behind each shot

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
	_build_shot_pool()
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
		# ⚠️ The league tiles are bright by themselves and wash out the creatures under the
		# working lamp. Multiply-tint toward the house palette's warm stone: the CREATURES
		# must be the brightest thing on the board, never the floor.
		fmat.albedo_color = Color(0.60, 0.55, 0.48)
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
	sim.nav.free_rids()  # the teardown every discarded sim owes (nav_service.gd)
	_frames = _result.frames
	print("WATCH: winner=%s ticks=%d frames=%d" % [str(_result.winner), int(_result.ticks), _frames.size()])

	# Roster facts for the opening card + scoreboard: species name, posture, kit move names.
	for u in us:
		var sp_name := str((by_id[str(u.species)] as Dictionary).get("name", str(u.species)))
		var tac: Dictionary = u.tactics
		var posture := str(tac.get("positional", "push")).capitalize()
		var prio := str(tac.get("target_priority", "nearest"))
		var move_names: Array = []
		for kentry in u.kit:
			move_names.append(str(kentry.get("name", "?")))
		_us_meta.append({"id": str(u.id), "team": str(u.team), "species": sp_name,
			"posture": posture, "priority": prio, "moves": move_names})
		_spawn[str(u.id)] = Vector2(u.pos)
	_aggregate_totals()

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
		_rig_y[u.id] = rig.position.y
		# Bodies stand ON THE DEPLOY SPOTS during the opening card — the card names the
		# formation, the board shows it.
		rig.position = Vector3(u.pos.x, rig.position.y, u.pos.y)
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
		lbl.modulate = HP_GOOD
		# Team identity moves to the OUTLINE (the disc carries it too) so the face colour is
		# free to carry the hp band.
		lbl.outline_modulate = Color(TEAM_COL[u.team]).darkened(0.55)
		add_child(lbl)
		_labels[u.id] = lbl
		# Stable per-unit label height: id-order slot within the side, so five labels in a
		# scrum stack into distinct shelves instead of overlapping into noise.
		_label_h[u.id] = 6.6 + 0.75 * float(int(_unit_index[u.id]) % 5)
		lbl.text = str(u.id)   # names over the deploy spots while the opening card holds
		lbl.position = Vector3(u.pos.x, float(_label_h[u.id]), u.pos.y)
		# Status chip pool: MAX_CHIPS unshaded dots under the label, hidden until the frame
		# stream carries a 'statuses' array (guarded with .get — absence degrades to nothing).
		var pool: Array = []
		for _c in range(MAX_CHIPS):
			var chip := MeshInstance3D.new()
			var chm := SphereMesh.new()
			chm.radius = 0.30
			chm.height = 0.60
			chip.mesh = chm
			var cmat := StandardMaterial3D.new()
			cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			chip.material_override = cmat
			chip.visible = false
			add_child(chip)
			pool.append(chip)
		_chips[u.id] = pool

	_build_hud()
	_show_opening_card()


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# PLAYBACK — SPACE pause · 1/2/4 speed · R replays the SAME frames (never re-sim)
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE:
			_paused = not _paused
			_update_speed_label()
		KEY_1:
			_speed = 1.0
			_update_speed_label()
		KEY_2:
			_speed = 2.0
			_update_speed_label()
		KEY_4:
			_speed = 4.0
			_update_speed_label()
		KEY_R:
			_restart_replay()


## Rewind the SAME frame stream to tick 0 and play it again. Nothing is re-simulated — the
## fight already happened; this only resets what presentation mutated.
func _restart_replay() -> void:
	_gen += 1                      # every pending corpse/banner timer from this run goes stale
	_hide_shots()                  # no stale shot hangs in the air across a replay
	_t = 0.0
	_fi = 0
	_done = false
	_paused = false
	_last_hit.clear()
	_shake = 0.0
	if _end_layer != null and is_instance_valid(_end_layer):
		_end_layer.queue_free()
	_end_layer = null
	if _feed_box != null:
		for c in _feed_box.get_children():
			c.queue_free()
	for uid in _pop_tweens:
		var tw: Tween = _pop_tweens[uid]
		if tw != null and tw.is_valid():
			tw.kill()
	_pop_tweens.clear()
	for uid in _sink_tweens:
		var stw: Tween = _sink_tweens[uid]
		if stw != null and stw.is_valid():
			stw.kill()
	_sink_tweens.clear()
	for uid in _rigs:
		var rig = _rigs[uid]
		if rig == null or not is_instance_valid(rig):
			continue
		var sp: Vector2 = _spawn.get(uid, Vector2.ZERO)
		rig.visible = true
		rig.position = Vector3(sp.x, float(_rig_y.get(uid, 0.0)), sp.y)
		rig.scale = _base_scale.get(uid, rig.scale)
		if rig.has_method("set_state"):
			rig.set_state("idle", Vector2(1, 0))
		var disc: MeshInstance3D = _discs.get(uid)
		if disc != null:
			disc.visible = true
			disc.position = Vector3(sp.x, 0.06, sp.y)
		var lbl: Label3D = _labels.get(uid)
		if lbl != null:
			lbl.modulate = HP_GOOD
			lbl.text = str(uid)
			lbl.position = Vector3(sp.x, float(_label_h.get(uid, 7.2)), sp.y)
		for chip in _chips.get(uid, []):
			chip.visible = false
	if _cam != null:
		_cam.position = Vector3(0, 52, 58)
		_cam_look = Vector3(0, 0, -2)
		_cam.look_at(_cam_look)
	_update_speed_label()
	_show_opening_card()


## ── PROJECTILES (#34) — the shot is a BODY, not an instant ────────────────────────────────────
## Why this matters beyond looks: an aimed miss flies at where the target WAS, so a viewer
## watches the shot sail through empty ground and understands WHY it missed. That causal read
## is the whole point of the projectile layer, and it only exists if the renderer draws it.
const SHOT_POOL := 24
const SHOT_HIT := Color(1.0, 0.80, 0.35)     # a shot that will land: warm, confident
const SHOT_MISS := Color(0.62, 0.66, 0.78)   # a doomed shot: cold and pale, readable in flight

func _build_shot_pool() -> void:
	for i in SHOT_POOL:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.55
		sm.height = 1.1
		sm.radial_segments = 8
		sm.rings = 4
		mi.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.emission_enabled = true
		mi.material_override = m
		mi.visible = false
		add_child(mi)
		_shots.append(mi)
		var trail := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.22, 3.2)
		trail.mesh = bm
		var tm := StandardMaterial3D.new()
		tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		trail.material_override = tm
		trail.visible = false
		add_child(trail)
		_shot_trails.append(trail)


func _hide_shots() -> void:
	for mi in _shots:
		(mi as MeshInstance3D).visible = false
	for t in _shot_trails:
		(t as MeshInstance3D).visible = false


## Draw this frame's in-flight shots. Everything comes off the stream: pos, the live aim point,
## and will_hit — the renderer decides nothing about the fight, only how it looks.
func _update_shots(f: Dictionary) -> void:
	var pr: Array = f.get("projectiles", [])
	for i in _shots.size():
		var mi: MeshInstance3D = _shots[i]
		var trail: MeshInstance3D = _shot_trails[i]
		if i >= pr.size():
			mi.visible = false
			trail.visible = false
			continue
		var p: Dictionary = pr[i]
		var pos := Vector3(p.pos.x, 3.2, p.pos.y)
		var aim := Vector3(p.aim.x, 3.2, p.aim.y)
		var hit: bool = bool(p.get("will_hit", true))
		var col: Color = SHOT_HIT if hit else SHOT_MISS
		mi.position = pos
		mi.visible = true
		var mat: StandardMaterial3D = mi.material_override
		mat.albedo_color = col
		mat.emission = col
		mat.emission_energy_multiplier = 2.2 if hit else 1.1
		var dir := aim - pos
		if dir.length() > 0.4:
			trail.visible = true
			trail.position = pos - dir.normalized() * 1.6
			trail.look_at(pos, Vector3.UP)
			var tmat: StandardMaterial3D = trail.material_override
			tmat.albedo_color = Color(col.r, col.g, col.b, 0.38)
		else:
			trail.visible = false


func _process(delta: float) -> void:
	if _frames.is_empty() or _done:
		return
	# The opening card holds in real time (never speed-scaled): it is the READ.
	if _intro_left > 0.0:
		_intro_left -= delta
		if _intro_left <= 0.0:
			_dismiss_opening_card()
		_drift_camera(delta)
		_scale_labels()
		return
	if not _paused:
		_t += delta * _speed
	var target_fi := mini(int(_t / Sim.DT), _frames.size() - 1)
	while _fi < target_fi:
		_fi += 1
		var f: Dictionary = _frames[_fi]
		for e in f.events:
			_present_event(e)
		_update_shots(f)
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
			var hp_frac: float = float(uf.hp) / maxf(float(uf.max_hp), 1.0)
			lbl.modulate = HP_GOOD if hp_frac > 0.60 else (HP_MID if hp_frac >= 0.25 else HP_LOW)
			lbl.text = "" if st == "dead" else "%s %d%%\n%s" % [str(uf.id), int(100.0 * hp_frac), line2]
			lbl.position = Vector3(uf.pos.x, float(_label_h.get(uid, 7.2)), uf.pos.y)
			_update_chips(uid, uf, st)
	_drift_camera(delta)
	_scale_labels()
	if _fi >= _frames.size() - 1 and not _done:
		_done = true
		# Hold the scoreboard until the last corpses have sunk — the final frame must be clean.
		get_tree().create_timer(BANNER_DELAY).timeout.connect(_show_scoreboard.bind(_gen))
		print("WATCH: replay complete — winner %s" % str(_result.winner))


## Status chips: minimal coloured dots under the label, driven ONLY by a per-unit 'statuses'
## array IF the frame stream carries one. Guarded with .get — absence renders nothing.
func _update_chips(uid: String, uf: Dictionary, st: String) -> void:
	var pool: Array = _chips.get(uid, [])
	if pool.is_empty():
		return
	var statuses: Array = uf.get("statuses", []) if st != "dead" else []
	for i in range(pool.size()):
		var chip: MeshInstance3D = pool[i]
		if i >= statuses.size():
			chip.visible = false
			continue
		var s = statuses[i]
		var sname := str(s.get("kind", s.get("name", ""))) if s is Dictionary else str(s)
		var mat: StandardMaterial3D = chip.material_override
		mat.albedo_color = STATUS_COL.get(sname.to_lower(), Color(0.7, 0.7, 0.7))
		var n: int = mini(statuses.size(), pool.size())
		chip.position = Vector3(uf.pos.x + (float(i) - float(n - 1) * 0.5) * 0.95,
			float(_label_h.get(uid, 7.2)) - 1.2, uf.pos.y)
		chip.visible = true


## Labels shrink modestly with camera distance (on top of perspective) so far-side units
## whisper while the framed action speaks — declutters the scrum without hiding anything.
func _scale_labels() -> void:
	if _cam == null:
		return
	for uid in _labels:
		var lbl: Label3D = _labels[uid]
		if lbl.text == "":
			continue
		var dist := _cam.position.distance_to(lbl.position)
		lbl.pixel_size = 0.030 * clampf(52.0 / maxf(dist, 1.0), 0.62, 1.05)


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
			if int(e.get("dmg", 0)) > 0:
				_last_hit[str(e.get("to", ""))] = {"from": str(e.get("from", "")), "move": ""}
			if victim != null:
				if victim.has_method("flinch"):
					victim.flinch()
				_scale_pop(str(e.to), 1.26 if bool(e.get("crit", false)) else 1.14)
				_float_dmg(str(e.to), int(e.get("dmg", 0)), false)
			if _vfx != null and _vfx.has_method("burst"):
				_vfx.burst(vpos + Vector3(0, 2.0, 0), "slash", Color(0.95, 0.68, 0.25), 1.0, 8)
				if bool(e.get("crit", false)):
					_vfx.burst(vpos + Vector3(0, 2.2, 0), "spark", Color(1.0, 0.9, 0.5), 1.3, 10)
					_crowd_react(0.25)
			if bool(e.get("crit", false)):
				_shake = maxf(_shake, 0.22)
		"cast_start":
			if _vfx != null and _vfx.has_method("flip") and caster != null:
				_vfx.flip(cpos + Vector3(0, 2.5, 0), "charge", 3.5, Color(0.85, 0.75, 1.0), 0.5)
		"cast_done":
			if int(e.get("dmg", 0)) > 0:
				_last_hit[str(e.get("to", ""))] = {"from": str(e.get("from", "")), "move": str(e.get("move", ""))}
			if victim != null:
				if victim.has_method("flinch"):
					victim.flinch()
				_scale_pop(str(e.to), 1.30 if bool(e.get("crit", false)) else 1.16)
				_float_dmg(str(e.to), int(e.get("dmg", 0)), true)
			if bool(e.get("crit", false)):
				_shake = maxf(_shake, 0.26)
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
			_feed_kill(uid)
			_shake = maxf(_shake, 0.34)
			var rig = _rigs.get(uid)
			if _vfx != null and _vfx.has_method("burst") and rig != null:
				_vfx.burst(rig.position + Vector3(0, 1.0, 0), "smoke", Color(0.5, 0.48, 0.46), 1.4, 12)
			_crowd_react(0.85)
		_:
			pass   # miss / cast_miss / fizzle stay silent — absence of impact IS the read


## A brief scale-pop on the victim: game feel, returns exactly to the rig's build scale.
## Crits pop LARGER (mult ~1.26+) — the big hit must read even before the number lands.
func _scale_pop(uid: String, mult: float = 1.14) -> void:
	var rig = _rigs.get(uid)
	if rig == null or not _base_scale.has(uid):
		return
	var base: Vector3 = _base_scale[uid]
	var old: Tween = _pop_tweens.get(uid)
	if old != null and old.is_valid():
		old.kill()
	rig.scale = base * mult
	var tw := create_tween()
	tw.tween_property(rig, "scale", base, 0.16).set_ease(Tween.EASE_OUT)
	_pop_tweens[uid] = tw


## The death state plays from the frame stream; after a linger the corpse sinks and hides,
## so a long fight's floor does not fill with bodies the camera must keep dodging.
## Gen-gated: a restart (R) invalidates every timer the previous playthrough scheduled.
func _begin_corpse_fade(uid: String) -> void:
	if _rigs.get(uid) == null:
		return
	get_tree().create_timer(CORPSE_LINGER).timeout.connect(_sink_corpse.bind(uid, _gen))


func _sink_corpse(uid: String, gen: int) -> void:
	if gen != _gen:
		return   # stale timer from a replayed run — the body is standing again
	var rig = _rigs.get(uid)
	if rig == null or not is_instance_valid(rig):
		return
	var tw := create_tween()
	tw.tween_property(rig, "position:y", rig.position.y - 4.0, 1.2).set_ease(Tween.EASE_IN)
	tw.tween_callback(_hide_corpse.bind(uid))
	_sink_tweens[uid] = tw


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
	# Angle tells the story: the opening deploy is HIGH so the formations read as shapes;
	# once the fight is joined the camera settles LOWER and more side-on so silhouettes read.
	# open_frac decays continuously over the first seconds — a glide, never a cut.
	var open_frac: float = smoothstep(0.0, 1.0, clampf(1.0 - _t / 7.0, 0.0, 1.0))
	var cam_h: float = lerpf(33.0, 52.0, open_frac) * zoom
	var cam_d: float = lerpf(66.0, 58.0, open_frac) * zoom
	var desired := Vector3(centroid.x * 0.55, cam_h, centroid.y * 0.55 + cam_d)
	var k: float = 1.0 - exp(-1.4 * delta)     # slow exponential drift — never a snap
	_cam.position = _cam.position.lerp(desired, k)
	var look_target := Vector3(centroid.x, 2.0, centroid.y)
	_cam_look = _cam_look.lerp(look_target, k)
	_cam.look_at(_cam_look)
	# Big-hit micro-shake: TINY (max ~0.34 world units), decays fast, sine-driven off replay
	# time — deterministic (no randf; the sim's determinism contract stays clean) and it never
	# accumulates, so it cannot become nausea.
	if _shake > 0.005:
		_cam.position += Vector3(sin(_t * 53.0), sin(_t * 67.0) * 0.5, cos(_t * 47.0)) * _shake
		_shake *= exp(-6.5 * delta)
	else:
		_shake = 0.0


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# STREAM AGGREGATION — the scoreboard's numbers, summed ONCE from the frames (renderer derives
# nothing about the fight; these are sums OF the stream, not re-derivations of the sim)
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _aggregate_totals() -> void:
	_totals.clear()
	_has_heal = false
	for meta in _us_meta:
		_totals[str(meta.id)] = {"dealt": 0, "taken": 0, "healed": 0}
	for f in _frames:
		for e in f.events:
			var kind := str(e.kind)
			var dmg := int(e.get("dmg", 0))
			var from_id := str(e.get("from", ""))
			var to_id := str(e.get("to", ""))
			match kind:
				"strike", "cast_done":
					if _totals.has(from_id):
						_totals[from_id]["dealt"] += dmg
					if _totals.has(to_id):
						_totals[to_id]["taken"] += dmg
				"status_tick":
					if _totals.has(to_id):
						_totals[to_id]["taken"] += dmg   # attrition has no dealer to credit
				"heal":
					# Guarded: heal events may not exist in the stream yet. Credit healing DONE
					# to the caster (or the target if the stream carries no 'from').
					var amt := int(e.get("amount", e.get("dmg", 0)))
					if amt > 0:
						_has_heal = true
						var who := from_id if _totals.has(from_id) else to_id
						if _totals.has(who):
							_totals[who]["healed"] += amt
				_:
					pass


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# OPENING CARD — the player's READ (rosters, postures, kits) before the fight answers it
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _show_opening_card() -> void:
	_intro_left = INTRO_TIME
	if _intro_layer != null and is_instance_valid(_intro_layer):
		_intro_layer.queue_free()
	_intro_layer = CanvasLayer.new()
	_intro_layer.layer = 20
	add_child(_intro_layer)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_layer.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	center.add_child(col)
	var title := Label.new()
	title.text = "EXHIBITION — 5v5"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	col.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	col.add_child(row)
	for team in ["A", "B"]:
		row.add_child(_team_card(team))


## One team panel: team-coloured border, then per unit — id · species / posture · priority /
## kit move names (or the bare kick, or nothing).
func _team_card(team: String) -> Control:
	var panel := PanelContainer.new()
	var sb: StyleBoxFlat = UiTheme.panel_style("default", Color(TEAM_COL[team]).darkened(0.15))
	sb.bg_color = Color(UiTheme.PANEL, 0.93)
	panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	v.custom_minimum_size = Vector2(330, 0)
	panel.add_child(v)
	var head := Label.new()
	head.text = "TEAM %s" % team
	head.add_theme_font_size_override("font_size", 22)
	head.add_theme_color_override("font_color", TEAM_COL[team].lightened(0.25))
	v.add_child(head)
	for meta in _us_meta:
		if str(meta.team) != team:
			continue
		var name_l := Label.new()
		name_l.text = "%s · %s" % [str(meta.id), str(meta.species)]
		name_l.add_theme_font_size_override("font_size", 17)
		name_l.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY)
		v.add_child(name_l)
		var tac_l := Label.new()
		var moves: Array = meta.moves
		var kit_txt := ", ".join(PackedStringArray(moves)) if not moves.is_empty() else "—"
		tac_l.text = "   %s · targets %s\n   %s" % [str(meta.posture), str(meta.priority), kit_txt]
		tac_l.add_theme_font_size_override("font_size", 14)
		tac_l.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		v.add_child(tac_l)
	return panel


func _dismiss_opening_card() -> void:
	if _intro_layer == null or not is_instance_valid(_intro_layer):
		return
	var layer := _intro_layer
	_intro_layer = null
	var tw := create_tween()
	for c in layer.get_children():
		tw.parallel().tween_property(c, "modulate:a", 0.0, 0.45)
	tw.tween_callback(layer.queue_free)


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# HUD — speed/pause readout (bottom-left, muted) + kill feed (top-right, fading)
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _build_hud() -> void:
	if _hud_layer != null:
		return
	_hud_layer = CanvasLayer.new()
	_hud_layer.layer = 10
	add_child(_hud_layer)
	_speed_lbl = Label.new()
	_speed_lbl.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_speed_lbl.position = Vector2(14, -54)
	_speed_lbl.add_theme_font_size_override("font_size", 15)
	_speed_lbl.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	_hud_layer.add_child(_speed_lbl)
	var hint := Label.new()
	hint.text = "SPACE pause · 1/2/4 speed · R replay"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(14, -30)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(UiTheme.TEXT_MUTED, 0.55))
	_hud_layer.add_child(hint)
	_feed_box = VBoxContainer.new()
	_feed_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed_box.position = Vector2(-360, 14)
	_feed_box.custom_minimum_size = Vector2(346, 0)
	_feed_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed_box.add_theme_constant_override("separation", 4)
	_hud_layer.add_child(_feed_box)
	_update_speed_label()


func _update_speed_label() -> void:
	if _speed_lbl == null:
		return
	_speed_lbl.text = "⏸ paused" if _paused else "▶ %dx" % int(_speed)


## 'a0 slew b3 — Arcane Bomb' from the death event + the victim's last recorded damage source.
func _feed_kill(victim_id: String) -> void:
	var lh: Dictionary = _last_hit.get(victim_id, {})
	var killer := str(lh.get("from", ""))
	var mv := str(lh.get("move", ""))
	var txt := ("%s slew %s" % [killer, victim_id]) if killer != "" else ("%s fell" % victim_id)
	if mv != "":
		txt += " — " + mv
	var team := "A" if killer.begins_with("a") else ("B" if killer.begins_with("b") else "")
	_feed_line(txt, TEAM_COL.get(team, Color(0.85, 0.85, 0.85)))


func _feed_line(txt: String, col: Color) -> void:
	if _feed_box == null:
		return
	var lbl := Label.new()
	lbl.text = txt
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", col.lightened(0.35))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("outline_size", 6)
	_feed_box.add_child(lbl)
	var tw := lbl.create_tween()
	tw.tween_interval(FEED_HOLD)
	tw.tween_property(lbl, "modulate:a", 0.0, FEED_FADE)
	tw.tween_callback(lbl.queue_free)


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# END SCOREBOARD — winner + duration, then the per-unit ledger the stream paid for
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _show_scoreboard(gen: int) -> void:
	if gen != _gen:
		return   # a restart outran the banner delay — this board belongs to a dead run
	if _end_layer != null and is_instance_valid(_end_layer):
		_end_layer.queue_free()
	_end_layer = CanvasLayer.new()
	_end_layer.layer = 15
	add_child(_end_layer)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_layer.add_child(center)
	var panel := PanelContainer.new()
	var sb: StyleBoxFlat = UiTheme.panel_style("default", UiTheme.GOLD.darkened(0.2))
	sb.bg_color = Color(UiTheme.PANEL, 0.95)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	var w := str(_result.get("winner", ""))
	var dur := float(int(_result.get("ticks", 0))) * Sim.DT
	var head := Label.new()
	head.text = ("DRAW — %.1fs" % dur) if w == "draw" else ("TEAM %s WINS — %.1fs" % [w, dur])
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 34)
	head.add_theme_color_override("font_color", TEAM_COL.get(w, Color(0.9, 0.9, 0.9)).lightened(0.2))
	v.add_child(head)

	var cols := 6 if _has_heal else 5
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 4)
	v.add_child(grid)
	var headers := ["unit", "species", "dealt", "taken"]
	if _has_heal:
		headers.append("healed")
	headers.append("decisions")
	for h in headers:
		grid.add_child(_score_cell(str(h), UiTheme.GOLD, true))
	var logs: Dictionary = _result.get("decision_logs", {})
	for meta in _us_meta:
		var uid := str(meta.id)
		var tot: Dictionary = _totals.get(uid, {"dealt": 0, "taken": 0, "healed": 0})
		var decisions: int = (logs.get(uid, []) as Array).size()
		grid.add_child(_score_cell(uid, TEAM_COL[str(meta.team)].lightened(0.3), true))
		grid.add_child(_score_cell(str(meta.species), UiTheme.TEXT_PRIMARY, false))
		grid.add_child(_score_cell(str(int(tot["dealt"])), UiTheme.TEXT_PRIMARY, false))
		grid.add_child(_score_cell(str(int(tot["taken"])), UiTheme.TEXT_SECONDARY, false))
		if _has_heal:
			grid.add_child(_score_cell(str(int(tot["healed"])), UiTheme.SAFE, false))
		grid.add_child(_score_cell(str(decisions), UiTheme.TEXT_SECONDARY, false))

	var foot := Label.new()
	foot.text = "R — watch it again"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.add_theme_font_size_override("font_size", 13)
	foot.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	v.add_child(foot)

	panel.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.6)


func _score_cell(txt: String, col: Color, bold: bool) -> Label:
	var lbl := Label.new()
	lbl.text = txt
	lbl.add_theme_font_size_override("font_size", 17 if bold else 15)
	lbl.add_theme_color_override("font_color", col)
	return lbl


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
