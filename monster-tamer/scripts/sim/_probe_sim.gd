## SIM REWRITE PROBE — headless acceptance for sim.gd v1. Exit code is the result.
## Pins: fights resolve, pathing routes around cover, intent rides the stream, the anti-blob
## tactics separate destinations, and twin seeded runs hash byte-identical.
extends Node3D

const Sim = preload("res://scripts/sim/sim.gd")

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
		{"id": "b0", "team": "B", "pos": Vector2(20, 0), "speed": 10.0, "kite_budget": 25,
			"stats": {"STR": 15, "CON": 45, "INT": 60, "WIS": 55},
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
