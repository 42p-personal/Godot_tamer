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

## MOVEMENT FEEL — the constants that make the fight read as bodies, not sliding chips.
const SLOT_COUNT := 6           # surround slots per target, 60° apart: chord at SLOT_RADIUS is
								#  4.8, comfortably above ALLY_MIN_SEP, so a full ring never
								#  fights the ally soft-avoid
const SLOT_RADIUS := 4.8        # where an attacker stands: above the enemy body ring (2*2.2=4.4)
								#  so the push-out never fights the slot, below BASE_REACH*0.95
								#  so a unit AT its slot is always in reach
const SLOT_SETTLE := 1.2        # close enough to the slot to stop strafing and stand
const MAX_ACCEL := 30.0         # u/s² — rest to full speed in ~3 ticks; kills the zigzag without
								#  making starts feel drunk
const TURN_RATE := 5.0          # rad/s turn cap while far from the aim point: paths render as
								#  curves. ⚠️ NEVER make this unconditional —
const TURN_RELAX_DIST := 6.0    #  — inside this of the aim point the cap LIFTS. The old sim's
								#  fixed turn cap at speed orbited the target forever.
const WAYPOINT_RADIUS := 1.5    # advance the path index when this close; the velocity model
								#  rounds corners instead of snapping exactly onto waypoints
const ENEMY_PUSH_MAX := 0.9     # max enemy-overlap resolved per tick — deep overlaps resolve
								#  over a few ticks instead of one teleport
const ALLY_MIN_SEP := BODY_RADIUS * 2.0  # allies are PASSABLE (#22) but drift apart to this —
								#  engages at the same ring as enemies so crossing paths still
								#  read as two bodies, but the FORCE below stays soft
const ALLY_SOFT_FRAC := 0.4     # fraction of ally overlap resolved per tick (enemy: all of it)
const ALLY_PUSH_MAX := 0.5      # cap on that drift per tick (enemy cap: 0.9)
const MAX_TICK_MOVE := 1.8      # hard per-tick displacement ceiling, enforced at the source —
								#  the probe's anti-teleport tripwire is 2.0 (old repo lesson)

## STAGNATION PRESSURE — the anti-turtle rule. Two hold/guard remnants out of each other's
## reach would otherwise stand at their anchors forever (measured: caster_peel/seed3333, both
## sides parked 65 units apart from tick ~285 to the cap). When NO damage lands for
## STAGNATION_ARM_TICKS, the sim GROWS the published `hold_radius` each tick.
## ⚠️ The pressure is a RATCHET: landed damage only PAUSES the growth — a DEATH resets it.
## Resetting on mere damage was tried first and produced approach-exchange-retreat oscillation
## (the leash snapped back after every exchange and the remnants disengaged again, whittling
## slower than the cap). Deaths are the one signal the fight genuinely progressed.
const HOLD_RADIUS_BASE := 8.0        # must match the tree's hold default
const STAGNATION_ARM_TICKS := 150    # 15s of silence arms the pressure
const STAGNATION_LEASH_RATE := 0.1   # leash growth per stagnant tick (1 u/s per side)

var nav: NavService
var rng: RandomNumberGenerator
var units: Array = []           # ordered by id — the determinism order
var frames: Array = []
var tick_now := 0
var winner := ""
var last_damage_tick := 0       # last tick any strike/cast landed — pauses stagnation growth
var stagnation_level := 0.0     # the pressure ratchet: grows in silence, resets ONLY on a death

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
			"aggression": int(u.get("personality", {}).get("aggression", 50)),
			"focus_sticky": float(u.get("personality", {}).get("focus_sticky", 1.3)),
			"tree": CombatTree.build(u.get("tactics", {})),
			"bb": _fresh_bb(),
			"path": PackedVector2Array(), "path_i": 0,
			"cooldown": 0, "has_attacked": false, "alive": true,
			"mp": Derive.max_mana(float(stats.get("WIS", 10)), float(stats.get("INT", 10))),
			"max_mp": Derive.max_mana(float(stats.get("WIS", 10)), float(stats.get("INT", 10))),
			"regen": Derive.regen_per_sec(float(stats.get("WIS", 10)), false),
			"kit": u.get("kit", []), "cds": {}, "casting": {},
			"dmg_from": {},   # attacker id -> decaying recent damage (the THREAT ledger)
			"kite_ticks": int(u.get("kite_budget", 80)),  # #39: kiting ENDS - 8s default budget
			"facing": Vector2(1, 0) if str(u["team"]) == "A" else Vector2(-1, 0),
			"vel": Vector2.ZERO,          # smoothed velocity — movement feel state
			"slot_angle": 0.0, "slot_ok": false,  # this tick's surround slot, if attacking
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
	# EXECUTE — every tick: surround slots, then movement toward the requested point, then strikes.
	_assign_slots()
	for u in units:
		if not u.alive:
			continue
		if u.casting.is_empty():
			_execute_move(u)
		else:
			u.vel = Vector2.ZERO  # a cast is a full commitment — no residual drift after it ends
	for u in units:
		if not u.alive:
			continue
		for a in u.dmg_from.keys():
			u.dmg_from[a] = float(u.dmg_from[a]) * 0.985   # ~2s half-life at 10Hz
		u.mp = minf(u.max_mp, u.mp + u.regen * DT)
		for k in u.cds.keys():
			u.cds[k] = maxi(0, int(u.cds[k]) - 1)
		_execute_cast(u, events)
	for u in units:
		if not u.alive:
			continue
		_execute_attack(u, events)
	# Stagnation clock: a landed hit PAUSES the ratchet (miss/fizzle does not — silence is
	# silence); growth happens below only after ARM ticks of real silence. Deaths reset it
	# further down, once they are detected.
	for e in events:
		if str(e.kind) in ["strike", "cast_done"]:
			last_damage_tick = tick_now
	if tick_now - last_damage_tick > STAGNATION_ARM_TICKS:
		stagnation_level += STAGNATION_LEASH_RATE
	# Deaths and victory.
	var alive_a := 0
	var alive_b := 0
	for u in units:
		if u.alive and u.hp <= 0:
			u.alive = false
			events.append({"kind": "death", "id": u.id})
			stagnation_level = 0.0   # a death IS progress — the ratchet releases
			last_damage_tick = tick_now
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
			# WISHLIST keys, now filled (contract at top of combat_tree.gd):
			#   threat   — recent damage THIS enemy dealt ME (my own ledger row);
			#   casting  — committed to a cast (feeds the opportunistic kick);
			#   team_dmg — recent damage MY TEAM dealt this enemy, summed in unit-id
			#              order (float addition order is part of determinism).
			rec["threat"] = float(u.dmg_from.get(o.id, 0.0))
			rec["casting"] = o.alive and not o.casting.is_empty()
			var team_dmg := 0.0
			for t in units:
				if t.team == u.team:
					team_dmg += float(o.dmg_from.get(t.id, 0.0))
			rec["team_dmg"] = team_dmg
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
	bb.set_value("aggression", u.aggression)   # 0-100 personality; 50 = every multiplier 1.0
	bb.set_value("focus_sticky", u.focus_sticky)
	bb.set_value("kick_range", INTERRUPT_REACH)  # advertise the ENFORCED reach — never two numbers
	# Stagnation pressure (see the constants block): the ratchet grows in silence, pauses on
	# damage, releases on a death. Always SET both keys — a stale grown radius surviving a
	# reset would leak the pressure.
	bb.set_value("hold_radius", HOLD_RADIUS_BASE + stagnation_level)
	bb.set_value("stagnation_pressure", stagnation_level > 0.0)
	# Cast/interrupt context (the WoW-arena layer): is my current target committed to a cast,
	# and is my kick off cooldown? The tree decides to spend it; the sim executes.
	var tgt = _unit(str(bb.get_value("target_id", "")))
	bb.set_value("target_casting", tgt != null and tgt.alive and not tgt.casting.is_empty())
	bb.set_value("kite_ticks_left", u.kite_ticks)
	var near_d := INF
	for o2 in units:
		if o2.alive and o2.team != u.team:
			near_d = minf(near_d, u.pos.distance_to(o2.pos))
	bb.set_value("nearest_enemy_dist", near_d)
	bb.set_value("interrupt_ready", _ready_move(u, "interrupt") != "")
	bb.set_value("cast_ready", _ready_move(u, "cast") != "")
	# Guard/peel context: who is hurting my CHARGE right now? The charge's own threat ledger
	# answers it - ties break by id order (strict >), determinism as always.
	var gid: String = str(u.tactics.get("guard_ally", ""))
	bb.set_value("guard_id", gid)
	if gid != "":
		var charge = _unit(gid)
		if charge != null and charge.alive:
			bb.set_value("charge_pos", charge.pos)
			var best_att := ""
			var best_v := 0.0
			for a in _ledger_keys_sorted(charge):
				var v: float = float(charge.dmg_from[a])
				var att = _unit(str(a))
				if att != null and att.alive and att.team != u.team and v > best_v:
					best_v = v
					best_att = str(a)
			bb.set_value("charge_attacker_id", best_att)
		else:
			bb.set_value("charge_attacker_id", "")
	# taunt/orders arrive here when abilities and the tactics screen wire in (v1: keys absent).


## Dictionary key order is insertion order in Godot, which depends on hit history - SORT before
## iterating a ledger anywhere a decision hangs on it.
func _ledger_keys_sorted(u: Dictionary) -> Array:
	var ks: Array = u.dmg_from.keys()
	ks.sort()
	return ks


## ATTACK SLOTS / SURROUND — melee converging on one target fan out into an arc instead of
## stacking into one pixel. Each attacker of a target gets one of SLOT_COUNT ring positions,
## assigned in unit-id order (the determinism order): nearest slot to its current bearing,
## bumping outward alternately (+1,-1,+2,-2…) when taken. Runs every tick; the quantized
## bearing keeps assignments stable as units strafe into place.
func _assign_slots() -> void:
	var by_target := {}   # target id -> attackers, in unit-id order because units is
	for u in units:
		u.slot_ok = false
		if not u.alive or not u.casting.is_empty():
			continue
		var tid: String = str(u.bb.get_value("req_attack", u.bb.get_value("target_id", "")))
		if tid == "":
			continue
		var tgt = _unit(tid)
		if tgt == null or not tgt.alive:
			continue
		if not by_target.has(tid):
			by_target[tid] = []
		by_target[tid].append(u)
	var tids: Array = by_target.keys()
	tids.sort()   # Dictionary order is insertion order — sort before any decision hangs on it
	for tid in tids:
		var tgt2 = _unit(tid)
		var step: float = TAU / float(SLOT_COUNT)
		var taken := {}
		for u in by_target[tid]:
			var to_u: Vector2 = u.pos - tgt2.pos
			var bearing: float = to_u.angle() if to_u.length() > 0.001 else u.facing.angle() + PI
			var base: int = posmod(int(roundf(bearing / step)), SLOT_COUNT)
			var chosen: int = base   # >SLOT_COUNT attackers on one body: latecomers share
			for probe in [0, 1, -1, 2, -2, 3]:
				var cand: int = posmod(base + probe, SLOT_COUNT)
				if not taken.has(cand):
					chosen = cand
					break
			taken[chosen] = true
			u.slot_angle = float(chosen) * step
			u.slot_ok = true


## VELOCITY SMOOTHING — steer toward `aim` under an accel cap and a turn-rate cap, so paths
## render as curves, not zigzags. ⚠️ The turn cap RELAXES inside TURN_RELAX_DIST: the old
## sim's fixed turn cap at speed orbited the target forever — never re-tighten it near goals.
## `face_along` false = STRAFE: the caller owns facing (locked on the target) while move_dir
## follows actual motion — the two decouple on the stream exactly here.
func _steer(u: Dictionary, aim: Vector2, face_along: bool) -> void:
	var to_aim: Vector2 = aim - u.pos
	var d: float = to_aim.length()
	if d < 0.001:
		u.vel = Vector2.ZERO
		return
	var desired: Vector2 = to_aim / d * u.speed
	if d < u.speed * DT:
		desired = to_aim / DT   # arrival: ask only for the closing speed, never overshoot
	var cur: Vector2 = u.vel
	if cur.length() > 0.1 and d > TURN_RELAX_DIST:
		var max_turn: float = TURN_RATE * DT
		var ang: float = cur.angle_to(desired)
		if absf(ang) > max_turn:
			desired = cur.rotated(signf(ang) * max_turn).normalized() * u.speed
	var dv: Vector2 = desired - cur
	var max_dv: float = MAX_ACCEL * DT
	if dv.length() > max_dv:
		dv = dv / dv.length() * max_dv
	u.vel = cur + dv
	if u.vel.length() > u.speed:
		u.vel = u.vel / u.vel.length() * u.speed   # nothing outruns its own speed stat
	u.pos += u.vel * DT
	if face_along and u.vel.length() > 0.05:
		u.facing = u.vel / u.vel.length()


func _execute_move(u: Dictionary) -> void:
	var bb: BT.Blackboard = u.bb
	var prev_pos: Vector2 = u.pos
	var dest = bb.get_value("req_move_to", null)
	var tid: String = str(bb.get_value("req_attack", bb.get_value("target_id", "")))
	var tgt = _unit(tid)
	var engaged: bool = tgt != null and tgt.alive
	# Heading AT the target? Aim for the surround slot, not the target's centre — three
	# attackers arrive as an arc, not a stack. Distant destinations (wings/dive waypoints,
	# retreats) are the tree's business and pass through untouched.
	# ⚠️ attacking_dest gates the WHOLE slot/strafe layer: a unit whose tree ordered it AWAY
	# (kite, flee, escape) must never be hijacked into orbiting the enemy standing in its reach
	# — that bug locked a kiter to its chaser and the kite probe caught it.
	var attacking_dest: bool = engaged and dest != null \
		and (dest as Vector2).distance_to(tgt.pos) < BASE_REACH
	if attacking_dest and bool(u.slot_ok):
		dest = tgt.pos + Vector2.from_angle(float(u.slot_angle)) * SLOT_RADIUS
	if engaged and (dest == null or attacking_dest) \
			and u.pos.distance_to(tgt.pos) <= BASE_REACH * 0.95:
		# In reach: FACE the target no matter how we move (strafe decouples facing/move_dir).
		u.facing = (tgt.pos - u.pos).normalized() if u.pos != tgt.pos else u.facing
		var slot_pos: Vector2 = tgt.pos + Vector2.from_angle(float(u.slot_angle)) * SLOT_RADIUS
		if bool(u.slot_ok) and u.pos.distance_to(slot_pos) > SLOT_SETTLE:
			_steer(u, slot_pos, false)   # strafe into the slot, eyes on the target
		else:
			u.vel = Vector2.ZERO         # in position — stand and fight
	elif dest == null:
		u.vel = Vector2.ZERO
	else:
		# (Re)path when the goal moved meaningfully or the path ran out.
		var need_path: bool = u.path.size() == 0 or u.path_i >= u.path.size() \
			or u.path[u.path.size() - 1].distance_to(dest) > 3.0
		if need_path:
			u.path = nav.path(u.pos, dest)
			u.path_i = 0
		while u.path_i < u.path.size() and u.pos.distance_to(u.path[u.path_i]) <= WAYPOINT_RADIUS:
			u.path_i += 1
		if u.path_i < u.path.size():
			_steer(u, u.path[u.path_i], true)
		else:
			u.vel = Vector2.ZERO
	# #39: the kite budget SPENDS while genuinely kiting - moving away from the nearest
	# enemy while it is close enough to matter. Structural: no speed tuning involved.
	var nearest = null
	var nd := INF
	for o2 in units:
		if o2.alive and o2.team != u.team:
			var dd: float = u.pos.distance_to(o2.pos)
			if dd < nd:
				nd = dd
				nearest = o2
	if nearest != null and nd < 14.0:
		var before: float = float(prev_pos.distance_to(nearest.pos))
		if u.pos.distance_to(nearest.pos) > before + 0.05:
			u.kite_ticks = maxi(0, u.kite_ticks - 1)
	# Overlap resolution, ALWAYS run (even standing still — someone may have walked into us):
	# solid ENEMY bodies (#10/#22) push out hard but capped per tick; ALLIES are passable but
	# drift apart softly when overlapping — a gentler force than the enemy push-out.
	for o in units:
		if not o.alive or o.id == u.id:
			continue
		var delta: Vector2 = u.pos - o.pos
		var dist := delta.length()
		if dist <= 0.001:
			continue
		if o.team != u.team:
			var min_d := BODY_RADIUS * 2.0
			if dist < min_d:
				u.pos += delta / dist * minf(min_d - dist, ENEMY_PUSH_MAX)
		elif dist < ALLY_MIN_SEP:
			u.pos += delta / dist * minf((ALLY_MIN_SEP - dist) * ALLY_SOFT_FRAC, ALLY_PUSH_MAX)
	# The anti-teleport tripwire, enforced at the source: whatever movement plus pushes summed
	# to this tick, nothing displaces more than MAX_TICK_MOVE (probe asserts 2.0).
	var moved: Vector2 = u.pos - prev_pos
	if moved.length() > MAX_TICK_MOVE:
		u.pos = prev_pos + moved / moved.length() * MAX_TICK_MOVE


## First kit move of `kind` that is off cooldown and affordable, or "".
func _ready_move(u: Dictionary, kind: String) -> String:
	for m in u.kit:
		if str(m.get("kind", "cast")) != kind:
			continue
		if int(u.cds.get(str(m.name), 0)) > 0:
			continue
		if float(u.mp) < float(m.get("mana", 0)):
			continue
		return str(m.name)
	return ""


func _kit_move(u: Dictionary, name: String) -> Dictionary:
	for m in u.kit:
		if str(m.name) == name:
			return m
	return {}


const CAST_RANGE := 30.0        # spells reach far - the arena is big and casters stand off
const INTERRUPT_LOCKOUT := 30   # ticks (3s) the kicked school stays locked, WoW-style
const INTERRUPT_CD := 100       # ticks (10s) between kicks - a kick is a RESOURCE
const INTERRUPT_REACH := BASE_REACH * 1.4  # the kick's real reach — published to the tree as
									# bb `kick_range`; enforcement and advertisement must match


## Casts: begin when the tree allows and a kit cast is ready; complete after cast_time through
## the CONTRACTED maths; die to a kick. A casting unit stands still - the commitment is the
## legible tell the whole layer exists for.
func _execute_cast(u: Dictionary, events: Array) -> void:
	var bb: BT.Blackboard = u.bb
	if not u.casting.is_empty():
		var tgt = _unit(str(u.casting.target))
		if tgt == null or not tgt.alive:
			events.append({"kind": "fizzle", "from": u.id, "move": str(u.casting.move.name)})
			u.casting = {}
		elif tick_now >= int(u.casting.ends):
			var kentry: Dictionary = u.casting.move
			# The DATA move goes into resolve_strike verbatim when this kit entry carries one
			# (kit.gd path); hand-built test kits still describe themselves inline.
			var mv: Dictionary = kentry.get("move", {"name": str(kentry.name),
				"power": float(kentry.get("power", 30)), "accuracy": float(kentry.get("accuracy", 100)),
				"type": "damage", "channel": str(kentry.get("channel", "magic")), "effects": {}})
			# Mitigation follows the CHANNEL rule: physical (melee/ranged) vs CON, everything
			# else vs WIS — the documented split, not a per-move choice.
			var phys: bool = str(mv.get("channel", "magic")) in ["melee", "ranged"]
			var def_stat: float = float(tgt.stats.get("CON", 10)) if phys else float(tgt.stats.get("WIS", 10))
			var out: Dictionary = Damage.resolve_strike({
				"move": mv,
				"rolls": {"acc": rng.randf(), "crit": rng.randf(), "variance": rng.randf()},
				"now": tick_now * DT,
				"atk": float(u.stats.get(str(kentry.get("stat", "INT")), 10)),
				"atkMult": 1.0, "attackerHpFrac": float(u.hp) / float(u.max_hp), "attackerWard": 0,
				"accPenalty": 0.0, "accMod": 0.0, "dodgeMod": 0.0, "flankBonus": 0.0, "behindMult": 1.0,
				"falloff": 1.0,
				"defMit": Damage.mitigation_for(def_stat),
				"defMitDebuff": 0.0, "defDmgTakenMod": 1.0, "defStatusDmgTaken": 1.0,
				"defGuard": 0, "defWard": 0, "defBlocking": false, "defHasAttacked": tgt.has_attacked,
				"defHasBonusStatus": false, "defHpFrac": float(tgt.hp) / float(tgt.max_hp),
				"defMaxHp": tgt.max_hp,
			})
			u.cds[str(kentry.name)] = int(float(kentry.get("cooldown", 4.0)) / DT)
			if bool(out.get("hit", false)):
				tgt.hp -= int(out.get("toHp", 0))
				tgt.dmg_from[u.id] = float(tgt.dmg_from.get(u.id, 0.0)) + float(out.get("toHp", 0))
				events.append({"kind": "cast_done", "from": u.id, "to": tgt.id,
					"move": str(kentry.name), "dmg": int(out.get("dmg", 0)), "crit": bool(out.get("crit", false))})
			else:
				events.append({"kind": "cast_miss", "from": u.id, "to": tgt.id, "move": str(kentry.name)})
			u.casting = {}
		return
	if bool(bb.get_value("req_interrupt", false)):
		bb.set_value("req_interrupt", false)
		var iname := _ready_move(u, "interrupt")
		var tid: String = str(bb.get_value("target_id", ""))
		var tgt = _unit(tid)
		if iname != "" and tgt != null and tgt.alive and not tgt.casting.is_empty() \
				and u.pos.distance_to(tgt.pos) <= INTERRUPT_REACH:
			var locked: String = str(tgt.casting.move.name)
			tgt.casting = {}
			# +1: the victim's own cooldown decrement runs later THIS SAME tick and would eat
			# one tick of the lockout - found by the probe's exact-window check (29 of 30).
			tgt.cds[locked] = maxi(int(tgt.cds.get(locked, 0)), INTERRUPT_LOCKOUT + 1)
			u.cds[iname] = INTERRUPT_CD
			events.append({"kind": "interrupt", "from": u.id, "to": tid, "locked": locked})
			return
	if bool(bb.get_value("req_cast_allowed", false)):
		var cname := _ready_move(u, "cast")
		var tid2: String = str(bb.get_value("target_id", ""))
		var tgt2 = _unit(tid2)
		var mvx: Dictionary = _kit_move(u, cname) if cname != "" else {}
		var cast_range: float = float(mvx.get("range", CAST_RANGE)) if not mvx.is_empty() else CAST_RANGE
		# Opportunism: the ordered target when in range; otherwise the nearest IN-RANGE enemy
		# (id-order tiebreak). A caster staring at a distant kill target while an enemy stands
		# on its feet is not focus, it is paralysis — you cast at what you can hit.
		if cname != "" and (tgt2 == null or not tgt2.alive
				or u.pos.distance_to(tgt2.pos) > cast_range
				or u.pos.distance_to(tgt2.pos) < float(mvx.get("min_range", 0.0))):
			var best_d: float = INF
			for o3 in units:
				if o3.alive and o3.team != u.team:
					var d3: float = u.pos.distance_to(o3.pos)
					if d3 <= cast_range and d3 >= float(mvx.get("min_range", 0.0)) and d3 < best_d:
						best_d = d3
						tgt2 = o3
						tid2 = str(o3.id)
		if cname != "" and tgt2 != null and tgt2.alive \
				and u.pos.distance_to(tgt2.pos) <= cast_range \
				and u.pos.distance_to(tgt2.pos) >= float(mvx.get("min_range", 0.0)):
			var mv2: Dictionary = _kit_move(u, cname)
			u.mp -= float(mv2.get("mana", 0))
			u.casting = {"move": mv2, "target": tid2,
				"started": tick_now, "ends": tick_now + int(float(mv2.get("cast_time", 1.5)) / DT)}
			events.append({"kind": "cast_start", "from": u.id, "to": tid2, "move": cname})


func _execute_attack(u: Dictionary, events: Array) -> void:
	if not u.casting.is_empty():
		return  # committed - the stillness and silence ARE the cast
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
		tgt.dmg_from[u.id] = float(tgt.dmg_from.get(u.id, 0.0)) + float(out.get("toHp", 0))
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
		# Renderer-grade state: the stream is the ONLY thing the renderer reads (#33).
		var state := "idle"
		if not u.alive:
			state = "dead"
		elif not u.casting.is_empty():
			state = "cast"
		elif u.pos.distance_to(u.get("prev_pos", u.pos)) > 0.02:
			state = "advance"
		us.append({
			"id": u.id, "team": u.team, "pos": u.pos, "hp": maxi(0, u.hp), "alive": u.alive,
			"max_hp": u.max_hp, "mp": u.mp, "max_mp": u.max_mp, "state": state,
			"move_dir": (u.pos - u.get("prev_pos", u.pos)).normalized() if u.pos != u.get("prev_pos", u.pos) else Vector2.ZERO,
			"facing": u.facing,
			"posture": str(u.bb.get_value("posture", "")) if u.alive else "",
			"intent": u.bb.intent_string() if u.alive else "",
			"reason": u.bb.reason() if u.alive else "",
			"castMove": str(u.casting.move.name) if not u.casting.is_empty() else "",
			"castFrac": clampf(float(tick_now - int(u.casting.started)) / maxf(1.0, float(int(u.casting.ends) - int(u.casting.started))), 0.0, 1.0) if not u.casting.is_empty() else 0.0,
		})
	frames.append({"tick": tick_now, "units": us, "events": events})
	for u in units:
		u["prev_pos"] = u.pos
