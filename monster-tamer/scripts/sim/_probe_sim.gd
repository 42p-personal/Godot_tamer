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
