## SIM REWRITE PROBE — headless acceptance for sim.gd v1. Exit code is the result.
## Pins: fights resolve, pathing routes around cover, intent rides the stream, the anti-blob
## tactics separate destinations, and twin seeded runs hash byte-identical.
extends Node3D

const Sim = preload("res://scripts/sim/sim.gd")
const Kit = preload("res://scripts/sim/kit.gd")

var _fails := 0


func _check(name: String, ok: bool) -> void:
	if ok:
		print("  ok  ", name)
	else:
		_fails += 1
		print("  FAIL ", name)


func _units_5v5(tactics_a: Dictionary) -> Array:
	var out: Array = []
	for i in 5:
		out.append({"id": "a%d" % i, "team": "A", "pos": Vector2(-40, -12 + 6 * i),
			"stats": {"STR": 60, "CON": 40, "INT": 10, "WIS": 10}, "speed": 9.0, "tactics": tactics_a})
		out.append({"id": "b%d" % i, "team": "B", "pos": Vector2(40, -12 + 6 * i),
			"stats": {"STR": 45, "CON": 35, "INT": 30, "WIS": 25}, "speed": 8.0,
			"tactics": {"target_priority": "nearest", "positional": "push"}})
	return out


func _run_sim(seed_val: int, tactics_a: Dictionary) -> Dictionary:
	var sim = Sim.new()
	sim.setup(seed_val, _units_5v5(tactics_a),
		Vector2(110, 62), [{"rect": Rect2(-4, -4, 8, 8)}])  # central pillar
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-40, 0), Vector2(40, 0))
	if not ok:
		return {}
	return sim.run()


func _hash_frames(res: Dictionary) -> String:
	return str(JSON.stringify(res.get("frames", [])).hash()) + "|" + str(res.get("winner"))


func _ready() -> void:
	_go()


func _go() -> void:
	var r1: Dictionary = await _run_sim(42, {"target_priority": "nearest", "positional": "push"})
	_check("nav ready and fight ran", not r1.is_empty() and r1.frames.size() > 10)
	_check("the fight RESOLVES (a side wins inside the cap)", str(r1.winner) in ["A", "B"])
	# The stream carries intent from the tree, and the log is a handful of decisions, not spam.
	var mid: Dictionary = r1.frames[mini(40, r1.frames.size() - 1)]
	var has_intent := false
	for u in mid.units:
		if str(u.intent) != "":
			has_intent = true
	_check("stream: units carry live intent", has_intent)
	var log_a0: Array = r1.decision_logs.get("a0", [])
	_check("decision log exists and is compact (changes only)", log_a0.size() >= 1 and log_a0.size() < 60)
	# Strikes actually flow through the contracted maths.
	var strikes := 0
	for f in r1.frames:
		for e in f.events:
			if e.kind == "strike":
				strikes += 1
	_check("strikes landed through resolve_strike", strikes > 10)

	# Anti-blob geometry: wings and push must produce genuinely different early destinations.
	var r_push: Dictionary = await _run_sim(42, {"target_priority": "nearest", "positional": "push"})
	var r_wing: Dictionary = await _run_sim(42, {"target_priority": "nearest", "positional": "wings", "wing_side": 1})
	var spread_push := _team_a_y_spread(r_push, 60)
	var spread_wing := _team_a_y_spread(r_wing, 60)
	_check("wings spreads team A wider than push by tick 60 (the anti-blob axis)",
		spread_wing > spread_push + 4.0)

	# Determinism: same seed twice — byte-identical frames. Different seed diverges.
	var t1: Dictionary = await _run_sim(1234, {"target_priority": "weakest", "positional": "push"})
	var t2: Dictionary = await _run_sim(1234, {"target_priority": "weakest", "positional": "push"})
	var t3: Dictionary = await _run_sim(4321, {"target_priority": "weakest", "positional": "push"})
	_check("determinism: same seed, twin runs, identical frame stream + winner",
		_hash_frames(t1) == _hash_frames(t2))
	_check("guard: different seed diverges (probe not vacuous)",
		_hash_frames(t1) != _hash_frames(t3))

	# The WoW-arena layer: a caster commits to a big cast; a fighter with a kick breaks it.
	var duel_kick: Dictionary = await _run_duel(true)
	var duel_free: Dictionary = await _run_duel(false)
	_check("casts: the caster commits (cast_start present)", _count(duel_free, "cast_start") > 0)
	_check("casts: uninterrupted casts LAND (control run)", _count(duel_free, "cast_done") > 0)
	_check("interrupt: the kick breaks a committed cast", _count(duel_kick, "interrupt") > 0)
	_check("interrupt: the lockout holds - the kicked school is silent for the full window",
		_lockout_respected(duel_kick, 30))
	var dk2: Dictionary = await _run_duel(true)
	_check("determinism holds with casts and kicks in play",
		_hash_frames(duel_kick) == _hash_frames(dk2))

	# The PEEL: a diver goes for the caster; the bodyguard swaps to the diver and body-blocks.
	var peel: Dictionary = await _run_peel()
	_check("peel: the guard swaps to the charge's attacker (reason logged)",
		_log_has(peel, "a1", "peel b0 off a0"))
	_check("peel: the guard actually fights the diver (strikes a1->b0)",
		_strikes_between(peel, "a1", "b0") > 0)
	_check("threat: the priority tracks the real damager", _log_has(peel, "a0", "(threat)"))
	var peel2: Dictionary = await _run_peel()
	_check("determinism holds with peels in play", _hash_frames(peel) == _hash_frames(peel2))

	# #39: the kite has a cost and an END - no infinite-kite stalemate.
	var kite: Dictionary = await _run_kite()
	_check("kite: the kiter kites (reason logged)", _log_has(kite, "b0", "kiting"))
	_check("kite: the budget ENDS it (standing logged)", _log_has(kite, "b0", "kite budget spent"))
	_check("kite: the fight RESOLVES inside the cap - no infinite kite", str(kite.winner) in ["A", "B"])
	var minr: Dictionary = await _run_minrange()
	_check("min range: casts happened at range (non-vacuous)", _count(minr, "cast_start") > 0)
	_check("min range: no cast starts with the chaser inside it", _min_range_respected(minr, "b0", 8.0))
	var kite2: Dictionary = await _run_kite()
	_check("determinism holds with kiting in play", _hash_frames(kite) == _hash_frames(kite2))

	# REAL KITS: authored moves from data.json drive the casts - names, damage and mana all real.
	var rk: Dictionary = await _run_real_kits()
	_check("real kits: authored moves cast by NAME from data.json", _cast_moves(rk).size() >= 2)
	_check("real kits: authored damage lands (dmg > 0 on cast_done)", _min_cast_dmg(rk) > 0)
	_check("real kits: the fight resolves on authored numbers", str(rk.winner) in ["A", "B"])
	var rk2: Dictionary = await _run_real_kits()
	_check("determinism holds on real kits", _hash_frames(rk) == _hash_frames(rk2))

	# MOVEMENT FEEL: surround slots fan melee into an arc, strafing keeps eyes on the target,
	# soft-avoid separates bodies, and nothing ever teleports.
	var srd: Dictionary = await _run_surround()
	_check("surround: 3 melee on one target occupy >= 2 distinct approach angles",
		_surround_angles(srd, ["a0", "a1", "a2"], "b0") >= 2)
	_check("strafe: attackers in reach keep FACING the target while repositioning",
		_strafe_faces_target(srd, ["a0", "a1", "a2"], "b0"))
	var srd2: Dictionary = await _run_surround()
	_check("determinism holds with slots and steering in play",
		_hash_frames(srd) == _hash_frames(srd2))
	_check("separation: no two living units within 1.6x body radius at fight end",
		_final_separation_ok(r1) and _final_separation_ok(srd))
	_check("anti-teleport: no unit moves more than 2.0 units in one tick (all runs)",
		_no_teleport(r1) and _no_teleport(peel) and _no_teleport(kite) and _no_teleport(srd))

	# FIELD STATUSES: DoTs tick with no attacker action, stun freezes body and hands, hard
	# control severs a committed cast, silence splits casts from melee, a 0-power control move
	# still lands its status, and determinism holds with statuses + DR in play.
	var brn: Dictionary = await _run_burn()
	_check("dot: burn landed on the walker (non-vacuous)", _applied(brn, "burn", "b0").size() > 0)
	_check("dot: the burn target loses HP on ticks where NO strike/cast hits it",
		_hp_drop_without_hit(brn, "b0"))
	var stn: Dictionary = await _run_stun_freeze()
	var stn_apps: Array = _applied(stn, "stun", "b0")
	_check("stun: landed mid-approach (non-vacuous)", stn_apps.size() > 0)
	_check("stun: the victim does not MOVE for the duration",
		stn_apps.size() > 0 and _frozen_during(stn, "b0", stn_apps[0]))
	_check("stun: the victim neither strikes nor casts for the duration",
		stn_apps.size() > 0 and _silent_during(stn, "b0", stn_apps[0], true))
	var cbk: Dictionary = await _run_castbreak()
	_check("control: a committed cast is LOST to a landed stun (status_break, not interrupt)",
		_count_break(cbk, "stun", "control") > 0)
	var sil: Dictionary = await _run_silence()
	var sil_apps: Array = _applied(sil, "silence", "b0")
	_check("control: a 0-power move still lands its status (silence applied)", sil_apps.size() > 0)
	var sil_ok := sil_apps.size() > 0
	for app in sil_apps:
		if not _silent_during(sil, "b0", app, false):
			sil_ok = false
	_check("silence: no cast_start inside ANY silence window", sil_ok)
	_check("silence: melee is NOT blocked (the silenced hybrid still swings)",
		_strikes_from_in_windows(sil, "b0", sil_apps) > 0)
	var sil2: Dictionary = await _run_silence()
	var brn2: Dictionary = await _run_burn()
	_check("determinism holds with statuses, DoTs and DR in play",
		_hash_frames(sil) == _hash_frames(sil2) and _hash_frames(brn) == _hash_frames(brn2))
	var moves_all := _load_moves()
	_check("kit: a real status-carrying control move builds (Hush)",
		Kit.build(["Hush"], moves_all).size() == 1)
	_check("kit: a status-less debuff still skips loudly (Sunder — mods not built)",
		Kit.build(["Sunder"], moves_all).size() == 0)

	print("SIM PROBE %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _team_a_y_spread(res: Dictionary, tick: int) -> float:
	var f: Dictionary = res.frames[mini(tick, res.frames.size() - 1)]
	var lo := INF
	var hi := -INF
	for u in f.units:
		if u.team == "A":
			lo = minf(lo, u.pos.y)
			hi = maxf(hi, u.pos.y)
	return hi - lo


func _count(res: Dictionary, kind: String) -> int:
	var n := 0
	for f in res.frames:
		for e in f.events:
			if str(e.kind) == kind:
				n += 1
	return n


## 2v2 close-quarters duel: one side has an interrupter, the other a hard-hitting caster.
func _run_duel(with_kick: bool) -> Dictionary:
	var kit_fighter: Array = [{"name": "Kick", "kind": "interrupt"}] if with_kick else []
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-12, 0), "speed": 10.0,
			"stats": {"STR": 70, "CON": 60, "INT": 10, "WIS": 20},
			"kit": kit_fighter, "tactics": {"target_priority": "casters", "positional": "push"}},
		{"id": "a1", "team": "A", "pos": Vector2(-12, 6), "speed": 9.0,
			"stats": {"STR": 50, "CON": 50, "INT": 10, "WIS": 20},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
		{"id": "b0", "team": "B", "pos": Vector2(12, 0), "speed": 7.0,
			"stats": {"STR": 15, "CON": 40, "INT": 85, "WIS": 60},
			"kit": [{"name": "Pyroblast", "kind": "cast", "power": 55, "cast_time": 2.2,
				"cooldown": 3.0, "mana": 8, "channel": "magic"}],
			"tactics": {"target_priority": "weakest", "positional": "hold"}},
		{"id": "b1", "team": "B", "pos": Vector2(12, 6), "speed": 8.0,
			"stats": {"STR": 55, "CON": 55, "INT": 10, "WIS": 20},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
	]
	var sim = Sim.new()
	sim.setup(777, us, Vector2(80, 44), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-12, 0), Vector2(12, 0))
	if not ok:
		return {}
	return sim.run()


## After every interrupt, the kicked unit must start no cast for `lockout` ticks - the
## mechanically exact contract, immune to fight-length differences between runs.
func _lockout_respected(res: Dictionary, lockout: int) -> bool:
	var found := false
	for i in res.frames.size():
		for e in res.frames[i].events:
			if str(e.kind) == "interrupt":
				found = true
				for j in range(i, mini(i + lockout, res.frames.size())):
					for e2 in res.frames[j].events:
						if str(e2.kind) == "cast_start" and str(e2.from) == str(e.to):
							print("    LOCKOUT VIOLATION: kick@%d cast_start@%d by %s move %s" % [i, j, str(e2.from), str(e2.move)])
							return false
	return found


func _log_has(res: Dictionary, unit_id: String, needle: String) -> bool:
	for entry in res.decision_logs.get(unit_id, []):
		if str(entry.get("reason", "")).contains(needle):
			return true
	return false


func _strikes_between(res: Dictionary, from_id: String, to_id: String) -> int:
	var n := 0
	for f in res.frames:
		for e in f.events:
			if str(e.kind) == "strike" and str(e.get("from", "")) == from_id and str(e.get("to", "")) == to_id:
				n += 1
	return n


## The peel scenario: a0 is a soft caster on `threat` priority, a1 its bodyguard on `guard`,
## b0 a fast diver ordered onto the weakest, b1 a frontliner to keep a1 honest.
func _run_peel() -> Dictionary:
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-24, 0), "speed": 6.0,
			"stats": {"STR": 15, "CON": 30, "INT": 80, "WIS": 55},
			"kit": [{"name": "Bolt", "kind": "cast", "power": 30, "cast_time": 1.4,
				"cooldown": 2.0, "mana": 5, "channel": "magic"}],
			"tactics": {"target_priority": "threat", "positional": "hold"}},
		{"id": "a1", "team": "A", "pos": Vector2(-18, 2), "speed": 9.5,
			"stats": {"STR": 65, "CON": 70, "INT": 10, "WIS": 25},
			"tactics": {"target_priority": "nearest", "positional": "guard", "guard_ally": "a0"}},
		{"id": "b0", "team": "B", "pos": Vector2(24, -4), "speed": 11.0,
			"stats": {"STR": 60, "CON": 35, "INT": 10, "WIS": 15},
			"tactics": {"target_priority": "weakest", "positional": "dive"}},
		{"id": "b1", "team": "B", "pos": Vector2(24, 4), "speed": 8.0,
			"stats": {"STR": 55, "CON": 60, "INT": 10, "WIS": 20},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
	]
	var sim = Sim.new()
	sim.setup(4242, us, Vector2(96, 52), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-20, 0), Vector2(20, 0))
	if not ok:
		return {}
	return sim.run()


## Fast kiting caster with a min-range spell vs a slower melee chaser.
func _run_kite() -> Dictionary:
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-20, 0), "speed": 8.5,
			"stats": {"STR": 70, "CON": 95, "INT": 10, "WIS": 45},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
		# A PURE runner: no kit, so nothing interrupts the retreat - the budget is the only
		# thing that can end this chase, which is exactly what the check needs to see.
		# CON 90 (was 45): velocity smoothing makes each kite episode start from rest, so the
		# runner takes more hits before the budget spends - it must SURVIVE to the budget end.
		{"id": "b0", "team": "B", "pos": Vector2(20, 0), "speed": 10.0, "kite_budget": 25,
			"stats": {"STR": 15, "CON": 90, "INT": 60, "WIS": 55},
			"tactics": {"target_priority": "nearest", "positional": "kite"}},
	]
	var sim = Sim.new()
	sim.setup(51, us, Vector2(96, 52), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-20, 0), Vector2(20, 0))
	if not ok:
		return {}
	return sim.run()


## No cast_start by `caster` on a frame where its nearest enemy sat inside `min_range`.
func _min_range_respected(res: Dictionary, caster: String, min_range: float) -> bool:
	for f in res.frames:
		var cpos = null
		var epos = null
		for u in f.units:
			if str(u.id) == caster:
				cpos = u.pos
			elif u.alive:
				epos = u.pos
		if cpos == null or epos == null:
			continue
		for e in f.events:
			if str(e.kind) == "cast_start" and str(e.from) == caster \
					and Vector2(cpos).distance_to(epos) < min_range - 0.01:
				return false
	return true


## A standing caster with a min-range spell as melee closes: casts fire at range, never inside.
func _run_minrange() -> Dictionary:
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-20, 0), "speed": 8.5,
			"stats": {"STR": 70, "CON": 80, "INT": 10, "WIS": 30},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
		{"id": "b0", "team": "B", "pos": Vector2(20, 0), "speed": 7.0,
			"stats": {"STR": 15, "CON": 50, "INT": 70, "WIS": 55},
			"kit": [{"name": "Frostbolt", "kind": "cast", "power": 20, "cast_time": 1.2,
				"cooldown": 1.5, "mana": 4, "channel": "magic", "min_range": 8.0}],
			"tactics": {"target_priority": "nearest", "positional": "hold"}},
	]
	var sim = Sim.new()
	sim.setup(52, us, Vector2(96, 52), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-20, 0), Vector2(20, 0))
	if not ok:
		return {}
	return sim.run()


## Three melee ordered onto ONE tank: the surround must fan them into an arc, not a stack.
func _run_surround() -> Dictionary:
	var melee := {"target_priority": "nearest", "positional": "push"}
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-24, -6), "speed": 9.0,
			"stats": {"STR": 45, "CON": 60, "INT": 10, "WIS": 15}, "tactics": melee},
		{"id": "a1", "team": "A", "pos": Vector2(-24, 0), "speed": 8.5,
			"stats": {"STR": 45, "CON": 60, "INT": 10, "WIS": 15}, "tactics": melee},
		{"id": "a2", "team": "A", "pos": Vector2(-24, 6), "speed": 8.0,
			"stats": {"STR": 45, "CON": 60, "INT": 10, "WIS": 15}, "tactics": melee},
		{"id": "b0", "team": "B", "pos": Vector2(20, 0), "speed": 7.0,
			"stats": {"STR": 20, "CON": 160, "INT": 10, "WIS": 30},
			"tactics": {"target_priority": "nearest", "positional": "hold"}},
	]
	var sim = Sim.new()
	sim.setup(303, us, Vector2(96, 52), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-20, 0), Vector2(20, 0))
	if not ok:
		return {}
	return sim.run()


## Best count over the fight of DISTINCT 45-degree bearing buckets occupied by the attackers,
## sampled only on frames where the target lives and all attackers stand within reach of it.
func _surround_angles(res: Dictionary, attackers: Array, target: String) -> int:
	var best := 0
	for f in res.frames:
		var tpos = null
		var pos := {}
		for u in f.units:
			if str(u.id) == target and u.alive:
				tpos = u.pos
			elif str(u.id) in attackers and u.alive:
				pos[str(u.id)] = u.pos
		if tpos == null or pos.size() < attackers.size():
			continue
		var buckets := {}
		var all_in_reach := true
		for a in attackers:
			var d: float = Vector2(pos[a]).distance_to(tpos)
			if d > 6.6:  # BASE_REACH
				all_in_reach = false
				break
			buckets[int(roundf(Vector2(pos[a] - tpos).angle() / (TAU / 8.0)))] = true
		if all_in_reach:
			best = maxi(best, buckets.size())
	return best


## Every frame where an attacker is IN REACH of the living target and MOVING, its facing must
## point at the target (dot > 0.5) - facing and move_dir decouple during the strafe.
func _strafe_faces_target(res: Dictionary, attackers: Array, target: String) -> bool:
	var samples := 0
	for f in res.frames:
		var tpos = null
		for u in f.units:
			if str(u.id) == target and u.alive:
				tpos = u.pos
		if tpos == null:
			continue
		for u in f.units:
			if not (str(u.id) in attackers) or not u.alive:
				continue
			# d <= 5.0 post-move guarantees the unit was ALREADY in reach before it moved
			# (max tick move ~1.1 < 6.27-5.0), i.e. the strafe branch ran — boundary frames
			# where a unit crosses into reach mid-turn are the approach branch, not strafe.
			var d: float = Vector2(u.pos).distance_to(tpos)
			if d > 5.0 or d < 0.5 or Vector2(u.move_dir) == Vector2.ZERO:
				continue
			samples += 1
			if Vector2(u.facing).dot((Vector2(tpos) - u.pos).normalized()) < 0.5:
				return false
	return samples >= 3  # non-vacuous: the strafe actually happened


## Final frame: every pair of living units at least 1.6x body radius apart - the blob is dead.
func _final_separation_ok(res: Dictionary) -> bool:
	var f: Dictionary = res.frames[res.frames.size() - 1]
	var live: Array = []
	for u in f.units:
		if u.alive:
			live.append(u)
	for i in live.size():
		for j in range(i + 1, live.size()):
			if Vector2(live[i].pos).distance_to(live[j].pos) < Sim.BODY_RADIUS * 1.6 - 0.01:
				print("    SEPARATION VIOLATION: %s-%s at %.2f" % [live[i].id, live[j].id,
					Vector2(live[i].pos).distance_to(live[j].pos)])
				return false
	return true


## The anti-teleport tripwire from the old repo: nothing displaces > 2.0 units in one tick.
func _no_teleport(res: Dictionary) -> bool:
	for i in range(1, res.frames.size()):
		var prev := {}
		for u in res.frames[i - 1].units:
			if u.alive:
				prev[str(u.id)] = u.pos
		for u in res.frames[i].units:
			if u.alive and prev.has(str(u.id)) \
					and Vector2(u.pos).distance_to(prev[str(u.id)]) > 2.0:
				print("    TELEPORT: %s moved %.2f at tick %d" % [str(u.id),
					Vector2(u.pos).distance_to(prev[str(u.id)]), i])
				return false
	return true


func _load_moves() -> Array:
	var txt := FileAccess.get_file_as_string("res://data/data.json")
	return JSON.parse_string(txt)["moves"]


func _cast_moves(res: Dictionary) -> Dictionary:
	var seen := {}
	for f in res.frames:
		for e in f.events:
			if str(e.kind) == "cast_done":
				seen[str(e.move)] = true
	return seen


func _min_cast_dmg(res: Dictionary) -> int:
	var lo := 999999
	for f in res.frames:
		for e in f.events:
			if str(e.kind) == "cast_done":
				lo = mini(lo, int(e.dmg))
	return 0 if lo == 999999 else lo


## Deterministic pick from the data: the two first magic damage moves by name, kitted onto
## casters against a melee pair. Everything the casts do comes from authoring.
func _run_real_kits() -> Dictionary:
	var moves := _load_moves()
	var magic: Array = moves.filter(func(m): return str(m.get("channel")) == "magic" and str(m.get("type")) == "damage")
	magic.sort_custom(func(a, b): return str(a.name) < str(b.name))
	var kit1 := Kit.build([str(magic[0].name)], moves)
	var kit2 := Kit.build([str(magic[1].name)], moves)
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-22, -4), "speed": 8.5,
			"stats": {"STR": 70, "CON": 75, "INT": 10, "WIS": 30},
			"kit": [Kit.kick()], "tactics": {"target_priority": "casters", "positional": "push"}},
		{"id": "a1", "team": "A", "pos": Vector2(-22, 4), "speed": 7.5,
			"stats": {"STR": 20, "CON": 45, "INT": 75, "WIS": 60},
			"kit": kit1, "tactics": {"target_priority": "weakest", "positional": "hold"}},
		{"id": "b0", "team": "B", "pos": Vector2(22, -4), "speed": 8.0,
			"stats": {"STR": 65, "CON": 70, "INT": 10, "WIS": 25},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
		{"id": "b1", "team": "B", "pos": Vector2(22, 4), "speed": 7.0,
			"stats": {"STR": 20, "CON": 50, "INT": 80, "WIS": 55},
			"kit": kit2, "tactics": {"target_priority": "weakest", "positional": "hold"}},
	]
	var sim = Sim.new()
	sim.setup(9001, us, Vector2(100, 56), [{"rect": Rect2(-3, -3, 6, 6)}])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-22, 0), Vector2(22, 0))
	if not ok:
		return {}
	return sim.run()


# ═══ FIELD-STATUS SCENARIOS ══════════════════════════════════════════════════════════════════


## DoT: a standing caster lights the slow walker on fire; the burn must tick HP away on frames
## where nothing else touches the victim.
func _run_burn() -> Dictionary:
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-14, 0), "speed": 8.0,
			"stats": {"STR": 10, "CON": 45, "INT": 70, "WIS": 60},
			"kit": [{"name": "Ember", "kind": "cast", "power": 12, "accuracy": 100, "cast_time": 1.0,
				"cooldown": 4.0, "mana": 3, "channel": "magic",
				"status": {"kind": "burn", "chance": 100, "duration": 3}}],
			"tactics": {"target_priority": "nearest", "positional": "hold"}},
		{"id": "b0", "team": "B", "pos": Vector2(14, 0), "speed": 5.0,
			"stats": {"STR": 40, "CON": 120, "INT": 10, "WIS": 20},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
	]
	var sim = Sim.new()
	sim.setup(61, us, Vector2(96, 52), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-14, 0), Vector2(14, 0))
	if not ok:
		return {}
	return sim.run()


## Stun freeze: the holder stuns the approaching melee at range — the victim must not move,
## strike or cast for the (DR-resolved) duration the status_applied event reports.
func _run_stun_freeze() -> Dictionary:
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-22, 0), "speed": 8.0,
			"stats": {"STR": 10, "CON": 40, "INT": 60, "WIS": 60},
			"kit": [{"name": "Concuss", "kind": "cast", "power": 5, "accuracy": 100, "cast_time": 0.8,
				"cooldown": 5.0, "mana": 3, "channel": "magic",
				"status": {"kind": "stun", "chance": 100, "duration": 2}}],
			"tactics": {"target_priority": "nearest", "positional": "hold"}},
		{"id": "b0", "team": "B", "pos": Vector2(22, 0), "speed": 7.0,
			"stats": {"STR": 50, "CON": 30, "INT": 10, "WIS": 15},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
	]
	var sim = Sim.new()
	sim.setup(62, us, Vector2(96, 52), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-22, 0), Vector2(22, 0))
	if not ok:
		return {}
	return sim.run()


## Cast break: two standing casters — one on a fast stun, one on a long 2.5s commitment. The
## stun must sever the long cast: status_break with cause "control", never an "interrupt".
func _run_castbreak() -> Dictionary:
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-12, 0), "speed": 8.0,
			"stats": {"STR": 10, "CON": 40, "INT": 60, "WIS": 70},
			"kit": [{"name": "Concuss", "kind": "cast", "power": 5, "accuracy": 100, "cast_time": 0.8,
				"cooldown": 3.0, "mana": 3, "channel": "magic",
				"status": {"kind": "stun", "chance": 100, "duration": 1}}],
			"tactics": {"target_priority": "nearest", "positional": "hold"}},
		{"id": "b0", "team": "B", "pos": Vector2(12, 0), "speed": 8.0,
			"stats": {"STR": 10, "CON": 20, "INT": 60, "WIS": 70},
			"kit": [{"name": "Zap", "kind": "cast", "power": 10, "accuracy": 100, "cast_time": 2.5,
				"cooldown": 0.5, "mana": 2, "channel": "magic"}],
			"tactics": {"target_priority": "nearest", "positional": "hold"}},
	]
	var sim = Sim.new()
	sim.setup(63, us, Vector2(80, 44), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-12, 0), Vector2(12, 0))
	if not ok:
		return {}
	return sim.run()


## Silence: a 0-power hush vs a melee/caster hybrid. The hush must LAND its status (decision
## #20 analogue: same accuracy roll, no damage needed), the silenced hybrid must start no cast
## inside the window — and must still swing its fists.
func _run_silence() -> Dictionary:
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-16, 0), "speed": 9.0,
			"stats": {"STR": 55, "CON": 60, "INT": 20, "WIS": 40},
			"kit": [{"name": "Hush0", "kind": "cast", "power": 0, "accuracy": 100, "cast_time": 1.0,
				"cooldown": 5.0, "mana": 3, "channel": "voice",
				"status": {"kind": "silence", "chance": 100, "duration": 3}}],
			"tactics": {"target_priority": "nearest", "positional": "push"}},
		{"id": "b0", "team": "B", "pos": Vector2(16, 0), "speed": 8.0,
			"stats": {"STR": 45, "CON": 60, "INT": 60, "WIS": 50},
			"kit": [{"name": "Zap", "kind": "cast", "power": 15, "accuracy": 100, "cast_time": 1.2,
				"cooldown": 1.0, "mana": 2, "channel": "magic"}],
			"tactics": {"target_priority": "nearest", "positional": "push"}},
	]
	var sim = Sim.new()
	sim.setup(64, us, Vector2(96, 52), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-16, 0), Vector2(16, 0))
	if not ok:
		return {}
	return sim.run()


## All status_applied events of `status` onto `to_id`, as {t: frame index, n: window ticks
## derived from the event's own DR-resolved seconds}.
func _applied(res: Dictionary, status: String, to_id: String) -> Array:
	var out: Array = []
	for i in res.frames.size():
		for e in res.frames[i].events:
			if str(e.kind) == "status_applied" and str(e.get("status", "")) == status \
					and str(e.get("to", "")) == to_id:
				out.append({"t": i, "n": int(float(e.get("seconds", 0.0)) / 0.1)})
	return out


## True if some frame shows the victim's HP dropping with a status_tick and NO strike/cast
## landing on it that tick — damage with no attacker action, the DoT signature.
func _hp_drop_without_hit(res: Dictionary, victim: String) -> bool:
	for i in range(1, res.frames.size()):
		var prev_hp := -1
		var cur_hp := -1
		for u in res.frames[i - 1].units:
			if str(u.id) == victim:
				prev_hp = int(u.hp)
		for u in res.frames[i].units:
			if str(u.id) == victim:
				cur_hp = int(u.hp)
		if prev_hp <= cur_hp or cur_hp <= 0:
			continue
		var hit := false
		var ticked := false
		for e in res.frames[i].events:
			if str(e.kind) in ["strike", "cast_done"] and str(e.get("to", "")) == victim:
				hit = true
			if str(e.kind) == "status_tick" and str(e.get("to", "")) == victim:
				ticked = true
		if ticked and not hit:
			return true
	return false


## Position pinned for the whole control window (movement for the application tick itself has
## already happened, so the anchor is t+1; pushes would move it, but the scenarios stun at range).
func _frozen_during(res: Dictionary, victim: String, app: Dictionary) -> bool:
	var t := int(app.t)
	var n := int(app.n)
	if t + 2 >= res.frames.size() or n < 3:
		return false
	var anchor = null
	for u in res.frames[t + 1].units:
		if str(u.id) == victim:
			anchor = u.pos
	if anchor == null:
		return false
	for j in range(t + 1, mini(t + n, res.frames.size())):
		for u in res.frames[j].units:
			if str(u.id) == victim and Vector2(u.pos).distance_to(anchor) > 0.001:
				return false
	return true


## No cast_start (and, if `include_strikes`, no strike/miss) FROM the victim inside the window.
func _silent_during(res: Dictionary, victim: String, app: Dictionary, include_strikes: bool) -> bool:
	var t := int(app.t)
	var n := int(app.n)
	for j in range(t + 1, mini(t + n, res.frames.size())):
		for e in res.frames[j].events:
			if str(e.get("from", "")) != victim:
				continue
			if str(e.kind) == "cast_start":
				return false
			if include_strikes and str(e.kind) in ["strike", "miss"]:
				return false
	return true


func _count_break(res: Dictionary, status: String, cause: String) -> int:
	var c := 0
	for f in res.frames:
		for e in f.events:
			if str(e.kind) == "status_break" and str(e.get("status", "")) == status \
					and str(e.get("cause", "")) == cause:
				c += 1
	return c


func _strikes_from_in_windows(res: Dictionary, attacker: String, apps: Array) -> int:
	var c := 0
	for app in apps:
		for j in range(int(app.t), mini(int(app.t) + int(app.n), res.frames.size())):
			for e in res.frames[j].events:
				if str(e.kind) == "strike" and str(e.get("from", "")) == attacker:
					c += 1
	return c
