## WATCH THE REWRITTEN SIM — the first human-viewable battle on the new stack. Runs a 5v5 on
## sim.gd (real species stats, real data.json kits, the five positional tactics on display),
## then replays the frame stream with creature rigs and LIVE INTENT LABELS — the legibility
## payoff the whole tree architecture exists for. Dev scene; the production renderer switch
## follows once this view proves the stream carries everything a viewer needs.
extends Node3D

const Sim = preload("res://scripts/sim/sim.gd")
const Kit = preload("res://scripts/sim/kit.gd")
const Rig = preload("res://scripts/ui/creature_rig.gd")

const GROUND := Vector2(110, 62)
const OBSTACLES := [{"rect": Rect2(-14, -9, 7, 7)}, {"rect": Rect2(7, 3, 7, 7)}]
const TEAM_COL := {"A": Color(0.35, 0.55, 0.95), "B": Color(0.85, 0.35, 0.3)}

var _frames: Array = []
var _result: Dictionary = {}
var _rigs := {}
var _labels := {}
var _t := 0.0
var _fi := 0
var _done := false


func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.13, 0.13, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.72, 0.78)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.shadow_enabled = true
	add_child(sun)

	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = GROUND
	floor_mi.mesh = pm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.24, 0.22, 0.19)
	floor_mi.material_override = fmat
	add_child(floor_mi)
	for ob in OBSTACLES:
		var r: Rect2 = ob["rect"]
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(r.size.x, 3.0, r.size.y)
		box.mesh = bm
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(0.38, 0.34, 0.3)
		box.material_override = bmat
		box.position = Vector3(r.get_center().x, 1.5, r.get_center().y)
		add_child(box)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 52, 58)
	add_child(cam)
	cam.look_at(Vector3(0, 0, -2))

	_run_fight()


func _run_fight() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/data.json"))
	var moves: Array = data["moves"]
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

	var sim = Sim.new()
	sim.setup(2026, us, GROUND, OBSTACLES)
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-38, 0), Vector2(38, 0))
	assert(ok, "nav never became ready")
	_result = sim.run()
	_frames = _result.frames
	print("WATCH: winner=%s ticks=%d frames=%d" % [str(_result.winner), int(_result.ticks), _frames.size()])

	# Bodies + labels.
	for u in us:
		var rig = Rig.new()
		add_child(rig)
		if not rig.build(str(u.species), 4.2):
			var box := MeshInstance3D.new()
			box.mesh = CapsuleMesh.new()
			rig.add_child(box)
		_rigs[u.id] = rig
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
			if str(e.kind) in ["strike", "cast_done"] and _rigs.has(str(e.get("to", ""))):
				_float_dmg(str(e.to), int(e.get("dmg", 0)), str(e.kind) == "cast_done")
		for uf in f.units:
			var rig = _rigs.get(str(uf.id))
			var lbl: Label3D = _labels.get(str(uf.id))
			if rig == null:
				continue
			rig.position = Vector3(uf.pos.x, rig.position.y, uf.pos.y)
			var st := str(uf.state)
			rig.set_state("dead" if st == "dead" else ("cast" if st == "cast" else ("advance" if st == "advance" else "idle")),
				Vector2(uf.facing) if uf.facing != Vector2.ZERO else Vector2(1, 0))
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
	if _fi >= _frames.size() - 1:
		_done = true
		print("WATCH: replay complete — winner %s" % str(_result.winner))


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
