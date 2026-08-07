## QUALITY PROBE — the flawlessness instrument. Runs several seeded 5v5 fights across varied
## tactic mixes and asserts FIGHT-QUALITY invariants: resolution, no-teleport (the old repo's
## hard-won tripwire), no ghost fights, legibility (intent every frame, compact logs), the
## duration band, anti-blob spread, harness perf, and determinism at scale.
## Run: godot --headless --path . res://scenes/_probe_sim_quality.tscn — exit code is the result.
## NOTE: it is FINE for checks to FAIL — this probe is the instrument that says WHICH and WHY.
extends Node3D

const Sim = preload("res://scripts/sim/sim.gd")
const Kit = preload("res://scripts/sim/kit.gd")

const GROUND := Vector2(110, 62)
const OBSTACLES := [{"rect": Rect2(-4, -4, 8, 8)}]  # central pillar, same as _probe_sim
const TICK_CAP := 1800
const TELEPORT_MAX := 2.0        # world units per tick — the hard-won tripwire
const MIN_ACTION_EVENTS := 20    # strike + cast_done per fight
const DURATION_LO := 80          # ticks (8s)
const DURATION_HI := 1700        # ticks (170s)
const BLOB_RADIUS := 10.0        # anti-blob absolute floor at tick 100 (see _blob_verdicts)
const BLOB_SHRINK_FRAC := 0.7    # a team is a blob only if it also COLLAPSED below this
								 #  fraction of its own deploy spread — convergence, not size
const LOG_CAP := 80              # decision log stays compact (changes only)
const PERF_MS := 8000            # harness wall-time budget per fight

var _fails := 0


func _check(name: String, ok: bool) -> void:
	if ok:
		print("  ok  ", name)
	else:
		_fails += 1
		print("  FAIL ", name)


func _ready() -> void:
	_go()


## ---- rosters ------------------------------------------------------------------------------
## Five 5v5 compositions spanning the tactic vocabulary: a plain brawl, a winged flank, a
## caster/peel/kick fight on REAL authored kits, an all-in dive, and a kiting back line.

func _load_moves() -> Array:
	var txt := FileAccess.get_file_as_string("res://data/data.json")
	return JSON.parse_string(txt)["moves"]


## Deterministic authored-kit picks: first magic damage moves by name, same rule as _probe_sim.
func _magic_kits(moves: Array, n: int) -> Array:
	var magic: Array = moves.filter(func(m): return str(m.get("channel")) == "magic" and str(m.get("type")) == "damage")
	magic.sort_custom(func(a, b): return str(a.name) < str(b.name))
	var out: Array = []
	for i in n:
		out.append(Kit.build([str(magic[i].name)], moves))
	return out


func _unit(id: String, team: String, pos: Vector2, stats: Dictionary, speed: float,
		tactics: Dictionary, kit: Array = [], extra: Dictionary = {}) -> Dictionary:
	var u := {"id": id, "team": team, "pos": pos, "stats": stats, "speed": speed,
		"tactics": tactics, "kit": kit}
	for k in extra:
		u[k] = extra[k]
	return u


func _comp_units(comp: String, moves: Array) -> Array:
	var bruiser := {"STR": 60, "CON": 45, "INT": 10, "WIS": 15}
	var tank := {"STR": 45, "CON": 70, "INT": 10, "WIS": 25}
	var caster := {"STR": 15, "CON": 35, "INT": 75, "WIS": 55}
	var diver := {"STR": 65, "CON": 35, "INT": 10, "WIS": 15}
	var kits := _magic_kits(moves, 4)
	var out: Array = []
	match comp:
		"brawl":
			for i in 5:
				out.append(_unit("a%d" % i, "A", Vector2(-40, -12 + 6 * i), bruiser, 9.0,
					{"target_priority": "nearest", "positional": "push"}))
				out.append(_unit("b%d" % i, "B", Vector2(40, -12 + 6 * i), tank, 8.0,
					{"target_priority": "nearest", "positional": "push"}))
		"wings":
			for i in 5:
				var side: int = -1 if i < 2 else 1
				var t_a: Dictionary = {"target_priority": "weakest", "positional": "wings", "wing_side": side} \
					if i != 2 else {"target_priority": "nearest", "positional": "push"}
				out.append(_unit("a%d" % i, "A", Vector2(-40, -12 + 6 * i), bruiser, 9.5, t_a))
				out.append(_unit("b%d" % i, "B", Vector2(40, -12 + 6 * i), tank, 8.0,
					{"target_priority": "nearest", "positional": "push"}))
		"caster_peel":
			out.append(_unit("a0", "A", Vector2(-40, 0), caster, 7.0,
				{"target_priority": "threat", "positional": "hold"}, kits[0]))
			out.append(_unit("a1", "A", Vector2(-36, 4), tank, 9.5,
				{"target_priority": "nearest", "positional": "guard", "guard_ally": "a0"}))
			out.append(_unit("a2", "A", Vector2(-40, -8), bruiser, 9.0,
				{"target_priority": "casters", "positional": "push"}, [Kit.kick()]))
			out.append(_unit("a3", "A", Vector2(-40, 8), bruiser, 9.0,
				{"target_priority": "nearest", "positional": "push"}))
			out.append(_unit("a4", "A", Vector2(-40, -14), caster, 7.5,
				{"target_priority": "weakest", "positional": "hold"}, kits[1]))
			out.append(_unit("b0", "B", Vector2(40, -4), diver, 11.0,
				{"target_priority": "weakest", "positional": "dive"}))
			out.append(_unit("b1", "B", Vector2(40, 0), caster, 7.0,
				{"target_priority": "weakest", "positional": "hold"}, kits[2]))
			out.append(_unit("b2", "B", Vector2(36, 4), tank, 9.0,
				{"target_priority": "nearest", "positional": "guard", "guard_ally": "b1"}))
			out.append(_unit("b3", "B", Vector2(40, 10), bruiser, 8.5,
				{"target_priority": "casters", "positional": "push"}, [Kit.kick()]))
			out.append(_unit("b4", "B", Vector2(40, -12), tank, 8.0,
				{"target_priority": "nearest", "positional": "push"}))
		"dive":
			for i in 5:
				out.append(_unit("a%d" % i, "A", Vector2(-40, -12 + 6 * i), diver, 10.5,
					{"target_priority": "weakest", "positional": "dive"}))
			out.append(_unit("b0", "B", Vector2(40, -6), caster, 7.0,
				{"target_priority": "nearest", "positional": "hold"}, kits[0]))
			out.append(_unit("b1", "B", Vector2(40, 6), caster, 7.0,
				{"target_priority": "nearest", "positional": "hold"}, kits[1]))
			for i in range(2, 5):
				out.append(_unit("b%d" % i, "B", Vector2(40, -18 + 8 * i), tank, 8.5,
					{"target_priority": "nearest", "positional": "push"}))
		"kite":
			for i in 5:
				out.append(_unit("a%d" % i, "A", Vector2(-40, -12 + 6 * i), bruiser, 9.0,
					{"target_priority": "nearest", "positional": "push"}))
			out.append(_unit("b0", "B", Vector2(40, -8), caster, 10.0,
				{"target_priority": "nearest", "positional": "kite"}, kits[2], {"kite_budget": 60}))
			out.append(_unit("b1", "B", Vector2(40, 8), caster, 10.0,
				{"target_priority": "nearest", "positional": "kite"}, kits[3], {"kite_budget": 60}))
			for i in range(2, 5):
				out.append(_unit("b%d" % i, "B", Vector2(40, -20 + 10 * i), tank, 8.5,
					{"target_priority": "nearest", "positional": "push"}))
		"caster_wall":
			# OFF-TARGET KICK COVERAGE comp: the kicker's ORDERED target is the tank, which
			# carries no kit and therefore never casts — target_casting stays false for the
			# whole fight, so the ONLY route by which its interrupt can ever fire is the
			# opportunistic off-target path in combat_tree's Engage node. The enemy casters
			# push, so the scrum forms with committed casts inside kick reach.
			out.append(_unit("a0", "A", Vector2(-40, 0), bruiser, 9.0,
				{"target_priority": "tanks", "positional": "push"}, [Kit.kick()]))
			out.append(_unit("a1", "A", Vector2(-40, -6), bruiser, 9.0,
				{"target_priority": "nearest", "positional": "push"}))
			out.append(_unit("a2", "A", Vector2(-40, 6), tank, 8.5,
				{"target_priority": "nearest", "positional": "push"}))
			out.append(_unit("b0", "B", Vector2(40, 0), tank, 8.0,
				{"target_priority": "nearest", "positional": "push"}))
			out.append(_unit("b1", "B", Vector2(44, -5), caster, 7.0,
				{"target_priority": "nearest", "positional": "push"}, kits[0]))
			out.append(_unit("b2", "B", Vector2(46, 0), caster, 7.0,
				{"target_priority": "nearest", "positional": "push"}, kits[1]))
			out.append(_unit("b3", "B", Vector2(44, 5), caster, 7.0,
				{"target_priority": "nearest", "positional": "push"}, kits[2]))
		"temper_lo", "temper_hi":
			# AGGRESSION DIVERGENCE comp: rosters byte-identical except team A's aggression
			# (10 vs 90). A falls back when hurt; B is fight_on and chases, so the fight still
			# resolves. hurt_at 0.5 puts both arming points (60% and 40% of max HP) well clear
			# of death, so the "falling back at N%" log entries exist to compare.
			var agg: int = 10 if comp == "temper_lo" else 90
			for i in 5:
				out.append(_unit("a%d" % i, "A", Vector2(-40, -12 + 6 * i), bruiser, 9.0,
					{"target_priority": "nearest", "positional": "push",
						"when_hurt": "fall_back", "hurt_at": 0.5},
					[], {"personality": {"aggression": agg}}))
				out.append(_unit("b%d" % i, "B", Vector2(40, -12 + 6 * i), tank, 8.0,
					{"target_priority": "nearest", "positional": "push"}))
		_:
			assert(false, "unknown comp: " + comp)
	return out


func _run_fight(seed_val: int, comp: String, moves: Array) -> Dictionary:
	var sim = Sim.new()
	sim.setup(seed_val, _comp_units(comp, moves), GROUND, OBSTACLES)
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-40, 0), Vector2(40, 0))
	if not ok:
		sim.nav.free_rids()   # teardown even on the abort path — a failed build still allocated
		return {}
	var t0 := Time.get_ticks_msec()   # HARNESS measurement only — never inside sim code
	var res: Dictionary = sim.run()
	res["wall_ms"] = Time.get_ticks_msec() - t0
	# NAV TEARDOWN — the sim is discarded here; without this every fight leaks ~18 server RIDs.
	# Runs strictly after run(), so it can never touch determinism.
	sim.nav.free_rids()
	return res


func _hash_frames(res: Dictionary) -> String:
	return str(JSON.stringify(res.get("frames", [])).hash()) + "|" + str(res.get("winner"))


## ---- per-fight metric extraction ----------------------------------------------------------

## Largest single-tick displacement of any unit across the whole frame stream.
func _max_tick_move(res: Dictionary) -> Dictionary:
	var worst := 0.0
	var who := ""
	var at := -1
	var fs: Array = res.frames
	for i in range(1, fs.size()):
		var prev: Array = fs[i - 1].units
		var cur: Array = fs[i].units
		for j in cur.size():
			var d: float = Vector2(prev[j].pos).distance_to(Vector2(cur[j].pos))
			if d > worst:
				worst = d
				who = str(cur[j].id)
				at = int(fs[i].tick)
	return {"dist": worst, "id": who, "tick": at}


func _action_events(res: Dictionary) -> int:
	var n := 0
	for f in res.frames:
		for e in f.events:
			if str(e.kind) in ["strike", "cast_done"]:
				n += 1
	return n


## First frame after tick 10 where a LIVING unit carries an empty intent, or null.
func _intent_gap(res: Dictionary):
	for f in res.frames:
		if int(f.tick) <= 10:
			continue
		for u in f.units:
			if bool(u.alive) and str(u.intent) == "":
				return {"tick": int(f.tick), "id": str(u.id)}
	return null


## Decision-log discipline: every unit logged something; no log sprawls past LOG_CAP.
func _log_problem(res: Dictionary) -> String:
	var ids: Array = res.decision_logs.keys()
	ids.sort()
	for id in ids:
		var n: int = res.decision_logs[id].size()
		if n < 1:
			return "%s has an EMPTY decision log" % id
		if n >= LOG_CAP:
			return "%s log sprawls: %d entries (cap %d)" % [id, n, LOG_CAP]
	return ""


## THE SPREAD METRIC — what §2B actually forbids is CONVERGENCE: a side collapsing into one
## huddle. The first version compared the ABSOLUTE centroid radius at tick 100 against a fixed
## floor, which argued with DEPLOYMENT, not behaviour — dive/seed44444's DEFENDING team deploys
## at only ~10.4u spread, so it could "fail" at 9.6u while standing essentially still. The
## verdict is therefore SHRINKAGE-based: for each team, take the units still alive at `tick`,
## measure their centroid radius NOW and the centroid radius of those SAME units' deploy
## positions (frame 0, index-aligned — the units array order never changes), and call it a blob
## only when the team BOTH sits inside the absolute floor AND has collapsed below
## BLOB_SHRINK_FRAC of its own deploy spread. Standing still is never a blob (ratio ~1.0);
## everyone converging onto one body always is (ratio ~0.3). Returns {} when the fight was
## already decided (nothing to measure); teams with < 3 living bodies are exempt.
func _blob_verdicts(res: Dictionary, tick: int) -> Dictionary:
	if res.frames.size() <= tick:
		return {}
	var f0: Dictionary = res.frames[0]
	var f: Dictionary = res.frames[tick]
	var out := {}
	for team in ["A", "B"]:
		var now_ps: Array = []
		var deploy_ps: Array = []
		for j in f.units.size():
			var u: Dictionary = f.units[j]
			if bool(u.alive) and str(u.team) == team:
				now_ps.append(Vector2(u.pos))
				deploy_ps.append(Vector2(f0.units[j].pos))
		if now_ps.size() < 3:
			continue  # too few bodies for a blob verdict
		out[team] = {"at": _centroid_radius(now_ps), "deploy": _centroid_radius(deploy_ps)}
	return out


func _centroid_radius(ps: Array) -> float:
	var c := Vector2.ZERO
	for p in ps:
		c += p
	c /= float(ps.size())
	var r := 0.0
	for p in ps:
		r = maxf(r, c.distance_to(p))
	return r


## ---- the run ------------------------------------------------------------------------------

func _go() -> void:
	var moves := _load_moves()
	var plan: Array = [
		{"seed": 11, "comp": "brawl"},
		{"seed": 222, "comp": "wings"},
		{"seed": 3333, "comp": "caster_peel"},
		{"seed": 44444, "comp": "dive"},
		{"seed": 55555, "comp": "kite"},
		{"seed": 777, "comp": "caster_peel"},   # second seed on the richest comp
	]
	var results: Array = []
	for p in plan:
		var r: Dictionary = await _run_fight(int(p.seed), str(p.comp), moves)
		if r.is_empty():
			print("  FAIL nav never became ready for %s seed %d — aborting" % [str(p.comp), int(p.seed)])
			_finish(true)
			return
		r["label"] = "%s/seed%d" % [str(p.comp), int(p.seed)]
		results.append(r)

	# 1. RESOLUTION — every fight ends with a winner inside the cap. No stalemates, ever.
	var unresolved: Array = []
	for r in results:
		if not (str(r.winner) in ["A", "B"]) or int(r.ticks) >= TICK_CAP:
			unresolved.append("%s -> winner=%s ticks=%d" % [r.label, str(r.winner), int(r.ticks)])
	for s in unresolved:
		print("    unresolved: ", s)
	_check("resolution: all %d fights end with a winner inside the %d-tick cap" % [results.size(), TICK_CAP],
		unresolved.is_empty())

	# 2. NO TELEPORT — no unit moves >2.0 units in one tick. The old repo's tripwire, kept.
	var tele_bad := false
	for r in results:
		var m: Dictionary = _max_tick_move(r)
		if float(m.dist) > TELEPORT_MAX:
			tele_bad = true
			print("    teleport: %s unit %s moved %.2f in one tick at tick %d" % [r.label, str(m.id), float(m.dist), int(m.tick)])
	_check("no teleport: max single-tick move <= %.1f units across every fight" % TELEPORT_MAX, not tele_bad)

	# 3. NO GHOST FIGHTS — fights actually HAPPEN: >= 20 strike/cast_done events each.
	var ghost := false
	for r in results:
		var n := _action_events(r)
		if n < MIN_ACTION_EVENTS:
			ghost = true
			print("    ghost fight: %s only %d action events" % [r.label, n])
	_check("no ghost fights: >= %d strike+cast_done events per fight" % MIN_ACTION_EVENTS, not ghost)

	# 4. LEGIBILITY — live intent on every frame past tick 10; logs present and compact.
	var intent_bad := false
	for r in results:
		var gap = _intent_gap(r)
		if gap != null:
			intent_bad = true
			print("    intent gap: %s unit %s empty at tick %d" % [r.label, str(gap.id), int(gap.tick)])
	_check("legibility: every living unit carries a non-empty intent after tick 10", not intent_bad)
	var log_bad := false
	for r in results:
		var prob := _log_problem(r)
		if prob != "":
			log_bad = true
			print("    log: %s %s" % [r.label, prob])
	_check("legibility: every unit logged >= 1 decision and logs stay under %d entries" % LOG_CAP, not log_bad)

	# 5. DURATION BAND — no degenerate instant fights, none grinding at the cap.
	var band_bad := false
	for r in results:
		var t: int = int(r.ticks)
		if t < DURATION_LO or t > DURATION_HI:
			band_bad = true
			print("    duration: %s ran %d ticks (band %d..%d)" % [r.label, t, DURATION_LO, DURATION_HI])
	_check("duration band: every fight lands in %d..%d ticks (%.0fs..%.0fs)" % [DURATION_LO, DURATION_HI, DURATION_LO * 0.1, DURATION_HI * 0.1],
		not band_bad)

	# 6. SPREAD — the anti-blob acceptance, judged on SHRINKAGE (see _blob_verdicts): a team is
	# a blob only when its living units sit inside the absolute floor AND collapsed below
	# BLOB_SHRINK_FRAC of the spread those same units deployed at. Decided fights are exempt.
	var blob_bad := false
	for r in results:
		var verdicts: Dictionary = _blob_verdicts(r, 100)
		for team in verdicts:
			var v: Dictionary = verdicts[team]
			if float(v.at) <= BLOB_RADIUS and float(v.at) < float(v.deploy) * BLOB_SHRINK_FRAC:
				blob_bad = true
				print("    blob: %s team %s collapsed to %.1fu at tick 100 (deployed at %.1fu — shrank past %.0f%%)" % [r.label, team, float(v.at), float(v.deploy), BLOB_SHRINK_FRAC * 100.0])
	_check("spread: no team converges below %.0f%% of its deploy spread into a <= %.0fu blob at tick 100" % [BLOB_SHRINK_FRAC * 100.0, BLOB_RADIUS], not blob_bad)

	# 7. PERF — harness wall-time per fight under budget on this machine.
	var slow := false
	for r in results:
		if int(r.wall_ms) > PERF_MS:
			slow = true
			print("    perf: %s took %d ms (budget %d)" % [r.label, int(r.wall_ms), PERF_MS])
	_check("perf: every sim run under %d ms wall time" % PERF_MS, not slow)

	# 8. DETERMINISM AT SCALE — the richest comp, same seed twice, byte-identical frames.
	var d1: Dictionary = await _run_fight(3333, "caster_peel", moves)
	_check("determinism at scale: caster_peel/seed3333 twin runs hash byte-identical",
		not d1.is_empty() and _hash_frames(d1) == _hash_frames(results[2]))

	# 9. OFF-TARGET KICK COVERAGE — round 1 wired the opportunistic kick; this pins it. The
	# caster_wall kicker's ordered target NEVER casts, so any interrupt in its log can only
	# have come through the off-target path ("kick the cast on X (off-target)").
	var kw: Dictionary = await _run_fight(9090, "caster_wall", moves)
	var off_kick := false
	if not kw.is_empty():
		var kw_ids: Array = kw.decision_logs.keys()
		kw_ids.sort()
		for id in kw_ids:
			for entry in kw.decision_logs[id]:
				if str(entry.reason).contains("off-target"):
					off_kick = true
	_check("off-target kick: caster_wall/seed9090 decision logs carry an off-target interrupt", off_kick)

	# 10/11. AGGRESSION DIVERGENCE — same seed, rosters identical except team A's aggression
	# (10 vs 90). The trait must (a) actually change the fight — frame hashes differ — and
	# (b) move the fall_back arming point the way §9 intends: the aggressive side fights
	# DEEPER into its HP bar, so its first "falling back at N% HP" entries carry lower N
	# (thresholds 60% vs 40% of max HP; judged on the per-side mean, hit granularity is ~15%).
	var lo: Dictionary = await _run_fight(4242, "temper_lo", moves)
	var hi: Dictionary = await _run_fight(4242, "temper_hi", moves)
	_check("aggression: 10 vs 90 produce different fights (frame hash differs)",
		not lo.is_empty() and not hi.is_empty() and _hash_frames(lo) != _hash_frames(hi))
	var lo_pcts: Array = _first_fallback_pcts(lo, "a") if not lo.is_empty() else []
	var hi_pcts: Array = _first_fallback_pcts(hi, "a") if not hi.is_empty() else []
	var arms_later: bool = lo_pcts.size() >= 1 and hi_pcts.size() >= 1 \
		and _mean(lo_pcts) > _mean(hi_pcts)
	if not arms_later:
		print("    aggression: timid first-fallback %s%% vs aggressive %s%%" % [str(lo_pcts), str(hi_pcts)])
	_check("aggression: the aggressive side arms fall_back deeper into its HP bar (per decision logs)", arms_later)

	_finish(false)


## First "falling back at N% HP" decision-log entry per unit whose id starts with `prefix`;
## returns the N values in unit-id order. Reason format is combat_tree's when-hurt line.
func _first_fallback_pcts(res: Dictionary, prefix: String) -> Array:
	var out: Array = []
	var ids: Array = res.decision_logs.keys()
	ids.sort()
	for id in ids:
		if not str(id).begins_with(prefix):
			continue
		for entry in res.decision_logs[id]:
			var reason := str(entry.reason)
			var at := reason.find("falling back at ")
			if at >= 0:
				out.append(reason.substr(at + 16).to_float())  # to_float stops at the '%'
				break
	return out


func _mean(xs: Array) -> float:
	var s := 0.0
	for x in xs:
		s += float(x)
	return s / maxf(1.0, float(xs.size()))


func _finish(aborted: bool) -> void:
	if aborted:
		_fails += 1
	print("QUALITY PROBE %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
