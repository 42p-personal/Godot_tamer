## THE SIM, REWRITTEN — decision #32: from scratch, around the combat tree; never evolved from
## the flat-scoring sim that produced the blob.
##
## Architecture: DECIDE / EXECUTE / EMIT, fixed-step.
##   DECIDE  — every DECISION_EVERY ticks each unit's combat tree runs over a blackboard the
##             sim fills (the contract at the top of combat_tree.gd). The tree writes REQUESTS.
##   EXECUTE — the sim carries requests out under the movement rules: NavigationServer paths
##             (spike-proven deterministic), per-unit speed, solid enemy bodies (#10, allies
##             passable #22), strikes through the CONTRACTED damage maths — resolve_strike is
##             the one formula; this file must never grow a second one.
##   EMIT    — one frame per tick, the REDESIGNED stream (#33): pos/hp/state plus INTENT and
##             REASON straight from each unit's tree, and the per-unit decision log at the end.
##             The renderer derives NOTHING.
##
## ⚠️ DETERMINISM CONTRACT: one injected RNG consumed in unit-id order, integer ticks, no clock,
## no engine physics. Same seed + same inputs -> byte-identical frames. The probe hashes it.
##
## ⚠️ V1 SCOPE, STATED HONESTLY: movement, targeting, basic-attack strikes, deaths, victory.
## Abilities/casts, projectiles (#34), statuses on the field, and innate auras layer on next —
## the seams for them are the request keys the tree already writes (req_cast_allowed) and the
## events array in the stream.
extends RefCounted

const BT = preload("res://scripts/ai/bt.gd")
const CombatTree = preload("res://scripts/ai/combat_tree.gd")
const NavService = preload("res://scripts/sim/nav_service.gd")
const Damage = preload("res://scripts/damage.gd")
const Derive = preload("res://scripts/derive.gd")

const DT := 0.1                 # fixed step, matches Sp.DT — never frame delta
const DECISION_EVERY := 5       # decision tick = 0.5s; movement executes every tick
const BODY_RADIUS := 2.2        # agreed with the renderer (spatial.gd)
const MAX_TICKS := 1800         # 3 min hard stop (fight length is emergent, #11)
const BASE_REACH := 6.6         # melee basic reach: 3.0 * GEOMETRY_SCALE, per CLASS_BASIC melee
const BASIC_COOLDOWN := 12      # ticks between basic attacks (1.2s)

var nav: NavService
var rng: RandomNumberGenerator
var units: Array = []           # ordered by id — the determinism order
var frames: Array = []
var tick_now := 0
var winner := ""

## unit: {id, team ("A"/"B"), pos: Vector2, stats: {STR..CHA}, speed, tactics: Dictionary,
##        personality: {nerve, focus_sticky}}  — everything injected, nothing global.


func setup(seed_val: int, in_units: Array, ground: Vector2, obstacles: Array) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed_val
	nav = NavService.new()
	nav.build(ground, obstacles, BODY_RADIUS)
	units = []
	for u in in_units:
		var stats: Dictionary = u["stats"]
		units.append({
			"id": str(u["id"]), "team": str(u["team"]),
			"pos": u["pos"], "home": u["pos"],
			"stats": stats,
			"hp": Derive.max_hp(float(stats.get("CON", 10))),
			"max_hp": Derive.max_hp(float(stats.get("CON", 10))),
			"speed": float(u.get("speed", 8.0)),
			"tactics": u.get("tactics", {}),
			"nerve": int(u.get("personality", {}).get("nerve", 50)),
			"focus_sticky": float(u.get("personality", {}).get("focus_sticky", 1.3)),
			"tree": CombatTree.build(u.get("tactics", {})),
			"bb": _fresh_bb(),
			"path": PackedVector2Array(), "path_i": 0,
			"cooldown": 0, "has_attacked": false, "alive": true,
			"facing": Vector2(1, 0) if str(u["team"]) == "A" else Vector2(-1, 0),
		})
	units.sort_custom(func(a, b): return a.id < b.id)  # id order IS the tick order


func _fresh_bb() -> BT.Blackboard:
	var bb := BT.Blackboard.new()
	bb.rng = rng  # the ONE rng — trees must draw from the same deterministic stream
	return bb


## Run the whole fight synchronously (nav must be ready — host awaits until_ready first).
func run() -> Dictionary:
	assert(nav.is_ready(), "await nav.until_ready() before run()")
	while tick_now < MAX_TICKS and winner == "":
		_step()
	var logs := {}
	for u in units:
		logs[u.id] = u.bb.decision_log()
	return {"winner": winner, "ticks": tick_now, "frames": frames, "decision_logs": logs}


func _step() -> void:
	var events: Array = []
	# DECIDE — on the decision tick, refill each blackboard and run the tree.
	if tick_now % DECISION_EVERY == 0:
		for u in units:
			if u.alive:
				_fill_bb(u)
				u.tree.tick(u.bb, tick_now)
	# EXECUTE — every tick: movement toward the requested point, then strikes.
	for u in units:
		if not u.alive:
			continue
		_execute_move(u)
	for u in units:
		if not u.alive:
			continue
		_execute_attack(u, events)
	# Deaths and victory.
	var alive_a := 0
	var alive_b := 0
	for u in units:
		if u.alive and u.hp <= 0:
			u.alive = false
			events.append({"kind": "death", "id": u.id})
		if u.alive:
			if u.team == "A":
				alive_a += 1
			else:
				alive_b += 1
	if alive_a == 0 or alive_b == 0:
		winner = "draw" if alive_a == 0 and alive_b == 0 else ("A" if alive_b == 0 else "B")
	_emit_frame(events)
	tick_now += 1


func _fill_bb(u: Dictionary) -> void:
	var bb: BT.Blackboard = u.bb
	bb.set_value("_tick_now", tick_now)
	bb.set_value("self", {"id": u.id, "pos": u.pos, "hp": u.hp, "max_hp": u.max_hp, "speed": u.speed})
	var enemies: Array = []
	var allies: Array = []
	var enemy_line_x := 0.0
	var n_enemy := 0
	for o in units:
		if o.id == u.id:
			continue
		var rec := {"id": o.id, "pos": o.pos, "hp": o.hp if o.alive else 0, "max_hp": o.max_hp,
			"int_stat": o.stats.get("INT", 0), "wis": o.stats.get("WIS", 0),
			"con": o.stats.get("CON", 0), "threat": 0.0}
		if o.team == u.team:
			allies.append(rec)
		else:
			enemies.append(rec)
			if o.alive:
				enemy_line_x += o.pos.x
				n_enemy += 1
	bb.set_value("enemies", enemies)   # already id-ordered because units is
	bb.set_value("allies", allies)
	bb.set_value("home_pos", u.home)
	bb.set_value("safe_pos", u.home)   # v1: safety is the deployment anchor
	bb.set_value("enemy_line_x", enemy_line_x / maxf(1.0, float(n_enemy)))
	bb.set_value("nerve", u.nerve)
	bb.set_value("focus_sticky", u.focus_sticky)
	# taunt/orders arrive here when abilities and the tactics screen wire in (v1: keys absent).


func _execute_move(u: Dictionary) -> void:
	var bb: BT.Blackboard = u.bb
	var dest = bb.get_value("req_move_to", null)
	if dest == null:
		return
	# Stop at reach of the attack target — standing inside a body is the old sim's disease.
	var tid: String = str(bb.get_value("req_attack", bb.get_value("target_id", "")))
	var tgt = _unit(tid)
	if tgt != null and tgt.alive and u.pos.distance_to(tgt.pos) <= BASE_REACH * 0.95:
		u.facing = (tgt.pos - u.pos).normalized() if u.pos != tgt.pos else u.facing
		return
	# (Re)path when the goal moved meaningfully or the path ran out.
	var need_path: bool = u.path.size() == 0 or u.path_i >= u.path.size() \
		or u.path[u.path.size() - 1].distance_to(dest) > 3.0
	if need_path:
		u.path = nav.path(u.pos, dest)
		u.path_i = 0
	if u.path_i >= u.path.size():
		return
	var step_left: float = u.speed * DT
	while step_left > 0.0 and u.path_i < u.path.size():
		var wp: Vector2 = u.path[u.path_i]
		var d: float = u.pos.distance_to(wp)
		if d <= step_left:
			u.pos = wp
			u.path_i += 1
			step_left -= d
		else:
			var dir: Vector2 = (wp - u.pos) / d
			u.pos += dir * step_left
			u.facing = dir
			step_left = 0.0
	# Solid ENEMY bodies (#10/#22): push out of overlap; allies are passable.
	for o in units:
		if o.alive and o.team != u.team:
			var delta: Vector2 = u.pos - o.pos
			var dist := delta.length()
			var min_d := BODY_RADIUS * 2.0
			if dist < min_d and dist > 0.001:
				u.pos += delta / dist * (min_d - dist)


func _execute_attack(u: Dictionary, events: Array) -> void:
	if u.cooldown > 0:
		u.cooldown -= 1
		return
	var tid: String = str(u.bb.get_value("req_attack", ""))
	if tid == "":
		return
	var tgt = _unit(tid)
	if tgt == null or not tgt.alive or u.pos.distance_to(tgt.pos) > BASE_REACH:
		return
	# ⚠️ THE ONE FORMULA: the contracted resolve_strike, with the basic-attack move shape.
	# Rolls come from the shared rng IN THIS CALL ORDER — reordering them changes every fight.
	var out: Dictionary = Damage.resolve_strike({
		"move": {"name": "Strike", "power": 12, "accuracy": 95.0, "type": "attack", "channel": "melee", "fx": {}},
		"rolls": {"acc": rng.randf(), "crit": rng.randf(), "variance": rng.randf()},
		"now": tick_now * DT,
		"atk": float(u.stats.get("STR", 10)),
		"atkMult": 1.0, "attackerHpFrac": float(u.hp) / float(u.max_hp), "attackerWard": 0,
		"accPenalty": 0.0, "accMod": 0.0, "dodgeMod": 0.0, "flankBonus": 0.0, "behindMult": 1.0,
		"falloff": 1.0,
		"defMit": Damage.mitigation_for(float(tgt.stats.get("CON", 10))),
		"defMitDebuff": 0.0, "defDmgTakenMod": 1.0, "defStatusDmgTaken": 1.0,
		"defGuard": 0, "defWard": 0, "defBlocking": false, "defHasAttacked": tgt.has_attacked,
		"defHasBonusStatus": false, "defHpFrac": float(tgt.hp) / float(tgt.max_hp),
		"defMaxHp": tgt.max_hp,
	})
	u.cooldown = BASIC_COOLDOWN
	u.has_attacked = true
	u.facing = (tgt.pos - u.pos).normalized() if u.pos != tgt.pos else u.facing
	if bool(out.get("hit", false)):
		tgt.hp -= int(out.get("toHp", 0))
		events.append({"kind": "strike", "from": u.id, "to": tid,
			"dmg": int(out.get("dmg", 0)), "crit": bool(out.get("crit", false))})
	else:
		events.append({"kind": "miss", "from": u.id, "to": tid})


func _unit(id: String):
	for o in units:
		if o.id == id:
			return o
	return null


## The redesigned stream (#33): intent and reason come FROM THE TREE, per unit, per frame.
func _emit_frame(events: Array) -> void:
	var us: Array = []
	for u in units:
		us.append({
			"id": u.id, "team": u.team, "pos": u.pos, "hp": maxi(0, u.hp), "alive": u.alive,
			"facing": u.facing,
			"intent": u.bb.intent_string() if u.alive else "",
			"reason": u.bb.reason() if u.alive else "",
		})
	frames.append({"tick": tick_now, "units": us, "events": events})
