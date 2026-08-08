## QUALITY PROBE — the flawlessness instrument. Runs several seeded 5v5 fights across varied
## tactic mixes and asserts FIGHT-QUALITY invariants: resolution, no-teleport (the old repo's
## hard-won tripwire), no ghost fights, legibility (intent every frame, compact logs), the
## duration band, anti-blob spread, harness perf, and determinism at scale.
## Run: godot --headless --path . res://scenes/_probe_sim_quality.tscn — exit code is the result.
## NOTE: it is FINE for checks to FAIL — this probe is the instrument that says WHICH and WHY.
extends Node3D

const Sim = preload("res://scripts/sim/sim.gd")
const Kit = preload("res://scripts/sim/kit.gd")
const Sp = preload("res://scripts/spatial.gd")

const GROUND := Vector2(110, 62)
const OBSTACLES := [{"rect": Rect2(-4, -4, 8, 8)}]  # central pillar, same as _probe_sim

## ── THE REAL BOARD (board-usage section, checks 12-15) ────────────────────────────────────────
## ⚠️ `GROUND` ABOVE IS NOT THE BOARD THE GAME IS PLAYED ON, AND EVERY CHECK ABOVE IS MEASURED ON
## IT. `Spatial.ground_size(5)` is 440x246.4 with a deploy separation of 391.6; the constant above
## is 110x62 with the comps deploying 80 apart. That is a board a QUARTER the linear size and two
## lines FIVE TIMES closer together — so the small board hides every failure that only appears at
## distance, which is exactly the class of failure the venue frames caught ("both teams hug their
## deploy edges with an empty centre at 34%"). The small-board checks are kept as-is (they are
## cheap, and they pin behaviour that must not regress), and the board-usage section below re-runs
## the SAME comps at real scale so the instrument can finally see the reported shape.
##
## ⚠️ THE OBSTACLE FIELD IS DELIBERATELY *NOT* `arena_layout.gd`'s. The layout is being reworked
## (density + per-league variety) in the same round as this; keying these numbers to it would make
## the board-usage baseline move for reasons that belong to another workstream. One central mass,
## scaled by the same factor as the ground, keeps this measuring BEHAVIOUR.
const BIG_TEAM_SIZE := 5
const BIG_SCALE := 4.0                        # 440/110 — ground_size(5).x / GROUND.x
const BIG_OBSTACLES := [{"rect": Rect2(-16, -16, 32, 32)}]
## The probe's own reference body speed (the tanks). Hand speeds are relative to it, so one ratio
## lifts the whole roster onto the real board without inventing a second speed curve: the real
## board's slowest-body speed IS `Sp.slow_unit_speed(5)`, derived from TARGET_CLOSE_SECONDS.
const SMALL_REF_SPEED := 8.0
## Fractions of each fight's own length at which usage is sampled. 0.34 is the frame the venue
## look-pass complained about; the others bracket it so a single unlucky moment cannot be the
## whole verdict.
const USAGE_SAMPLES := [0.20, 0.34, 0.50, 0.75]
const COVER_GRID := Vector2i(12, 8)           # cumulative-coverage grid over the whole fight
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
## The 5v5 compositions spanning the tactic vocabulary: a plain brawl, a winged flank, a
## caster/peel/kick fight on REAL authored kits, an all-in dive, a kiting back line, an
## off-target-kick wall, the aggression-divergence pair, and a sustain fight with a real
## authored healer per side (resolution's hard case — the stagnation ratchet's guard).

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
		"sustain":
			# RESOLUTION x HEALING comp: a REAL authored healer (Mend) on BOTH sides — the
			# named risk of the support layer is a heal-stalemate at 5v5 scale. Heals are
			# deliberately ABSENT from the stagnation pause list (sim.gd: sustain is not
			# fight progress), so the ratchet must still close this fight inside the cap;
			# this comp is that choice's regression guard at scale. The healers GUARD their
			# tanks: Mend's reach is ~18 world units and a held back-line healer would drift
			# out of range of its own front (the 3b check below would catch that vacuity).
			# ⚠️ COMP SHAPE IS MEASURED, NOT ASSUMED (first two drafts were vacuous): guard
			# stations the healer ON its charge — first contact, lowest DPS — so with any
			# `weakest`/`nearest` hunters opposite, BOTH healers were the first kill of every
			# fight, dying with full mana before a single ally was wounded ("kill the healer
			# first" is correct emergence, but it tests nothing here). And a healer weaker
			# than the bruisers re-magnetises every `weakest` hunter the moment it is nicked.
			# So: CON 60 (never the weakest body) and the pushers hunt TANKS — the tank soaks,
			# is wounded early and adjacent, and the healer demonstrably works (measured
			# 11 heal events, both sides, resolution at ~364 ticks).
			var healer := {"STR": 10, "CON": 60, "INT": 20, "WIS": 80}
			var mend_a := Kit.build(["Mend"], moves)
			var mend_b := Kit.build(["Mend"], moves)
			out.append(_unit("a0", "A", Vector2(-40, 0), tank, 8.5,
				{"target_priority": "tanks", "positional": "push"}))
			out.append(_unit("a1", "A", Vector2(-40, -6), bruiser, 9.0,
				{"target_priority": "tanks", "positional": "push"}))
			out.append(_unit("a2", "A", Vector2(-40, 6), bruiser, 9.0,
				{"target_priority": "tanks", "positional": "push"}))
			out.append(_unit("a3", "A", Vector2(-40, -12), caster, 7.0,
				{"target_priority": "weakest", "positional": "hold"}, kits[0]))
			out.append(_unit("a4", "A", Vector2(-36, 12), healer, 8.0,
				{"target_priority": "nearest", "positional": "guard", "guard_ally": "a0"}, mend_a))
			out.append(_unit("b0", "B", Vector2(40, 0), tank, 8.5,
				{"target_priority": "tanks", "positional": "push"}))
			out.append(_unit("b1", "B", Vector2(40, -6), bruiser, 9.0,
				{"target_priority": "tanks", "positional": "push"}))
			out.append(_unit("b2", "B", Vector2(40, 6), bruiser, 9.0,
				{"target_priority": "tanks", "positional": "push"}))
			out.append(_unit("b3", "B", Vector2(40, 12), caster, 7.0,
				{"target_priority": "weakest", "positional": "hold"}, kits[1]))
			out.append(_unit("b4", "B", Vector2(36, -12), healer, 8.0,
				{"target_priority": "nearest", "positional": "guard", "guard_ally": "b0"}, mend_b))
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


## ---- BOARD USAGE: the real-board instrument -------------------------------------------------
## ⚠️ MEASURES SHAPE, NOT OUTCOME. The complaint is not that fights fail to resolve (they do) —
## it is that the two lines sit on their own edges with an empty middle, on a board four times
## the linear size of the one every check above runs on. So this section reports, per comp:
##   advance  — how far each team's living centroid has come from its deploy line, as a fraction
##              of the distance to the centre line. 0.0 = still on the edge, 1.0 = at the centre.
##   gap      — the empty band between the two lines (B's nearest body minus A's nearest body),
##              as a fraction of the deploy separation. This IS "the empty centre", measured.
##   lateral  — the y-extent the living bodies occupy, as a fraction of the ground's height.
##   contest  — do BOTH teams have a body inside the central third?
##   cover    — cumulative share of a 12x8 grid any living body ever stood in, whole fight.

## Re-deploy a comp onto the real 5v5 board: real deploy positions (centre-framed, as the sim
## wants), and speeds lifted by the one ratio that keeps the roster's relative order intact.
func _big_units(comp: String, moves: Array) -> Array:
	var us: Array = _comp_units(comp, moves)
	var g: Vector2 = Sp.ground_size(BIG_TEAM_SIZE)
	var off: Vector2 = g * 0.5                       # corner frame -> the sim's centre frame
	var spd: float = Sp.slow_unit_speed(BIG_TEAM_SIZE) / SMALL_REF_SPEED
	var slots := {"A": Sp.deploy_positions(BIG_TEAM_SIZE, "A"),
		"B": Sp.deploy_positions(BIG_TEAM_SIZE, "B")}
	var next := {"A": 0, "B": 0}
	for u in us:
		var team: String = str(u["team"])
		var i: int = int(next[team])
		assert(i < (slots[team] as Array).size(),
			"comp %s fields more than %d on team %s — big-board deploy has no slot for it" % [comp, BIG_TEAM_SIZE, team])
		u["pos"] = Vector2((slots[team] as Array)[i]) - off
		next[team] = i + 1
		u["speed"] = float(u["speed"]) * spd
	return us


func _run_big_fight(seed_val: int, comp: String, moves: Array) -> Dictionary:
	var g: Vector2 = Sp.ground_size(BIG_TEAM_SIZE)
	var sim = Sim.new()
	sim.setup(seed_val, _big_units(comp, moves), g, BIG_OBSTACLES)
	var half: float = g.x * 0.5 - 8.0
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-half, 0), Vector2(half, 0))
	if not ok:
		sim.nav.free_rids()
		return {}
	var res: Dictionary = sim.run()
	sim.nav.free_rids()
	return res


## One sample: living-centroid advance per team, the gap between the lines, lateral use, contest.
func _usage_at(res: Dictionary, tick: int) -> Dictionary:
	var g: Vector2 = Sp.ground_size(BIG_TEAM_SIZE)
	var f0: Dictionary = res.frames[0]
	var f: Dictionary = res.frames[clampi(tick, 0, res.frames.size() - 1)]
	var home := {"A": 0.0, "B": 0.0}
	var n0 := {"A": 0, "B": 0}
	for u in f0.units:
		home[str(u.team)] = float(home[str(u.team)]) + Vector2(u.pos).x
		n0[str(u.team)] = int(n0[str(u.team)]) + 1
	for t in ["A", "B"]:
		home[t] = float(home[t]) / maxf(1.0, float(n0[t]))
	var centre: float = 0.5 * (float(home["A"]) + float(home["B"]))
	var half_sep: float = absf(float(home["B"]) - float(home["A"])) * 0.5
	var sum := {"A": 0.0, "B": 0.0}
	var n := {"A": 0, "B": 0}
	var front := {"A": -INF, "B": INF}   # A's most advanced (max x), B's most advanced (min x)
	var ylo := INF
	var yhi := -INF
	var mid := {"A": false, "B": false}
	var third: float = g.x / 6.0
	for u in f.units:
		if not bool(u.alive):
			continue
		var t: String = str(u.team)
		var p: Vector2 = Vector2(u.pos)
		sum[t] = float(sum[t]) + p.x
		n[t] = int(n[t]) + 1
		if t == "A":
			front["A"] = maxf(float(front["A"]), p.x)
		else:
			front["B"] = minf(float(front["B"]), p.x)
		ylo = minf(ylo, p.y)
		yhi = maxf(yhi, p.y)
		if absf(p.x - centre) <= third:
			mid[t] = true
	var adv := {}
	for t in ["A", "B"]:
		if int(n[t]) == 0:
			adv[t] = NAN
		else:
			var mean_x: float = float(sum[t]) / float(n[t])
			adv[t] = absf(mean_x - float(home[t])) / maxf(1.0, half_sep)
	var gap: float = NAN
	if int(n["A"]) > 0 and int(n["B"]) > 0:
		gap = (float(front["B"]) - float(front["A"])) / maxf(1.0, half_sep * 2.0)
	return {"advA": adv["A"], "advB": adv["B"], "gap": gap,
		"lateral": (yhi - ylo) / g.y if int(n["A"]) + int(n["B"]) > 0 else NAN,
		"contest": bool(mid["A"]) and bool(mid["B"])}


## ⚠️ THE DISCRIMINATOR. "Empty centre at 34% into the fight" has TWO possible causes and they
## want opposite fixes: either the units are refusing to use the board (a TREE bug), or the two
## lines simply have not met yet because the approach is a large share of the fight (a BOARD/SPEED
## question — `TARGET_CLOSE_SECONDS`, which lives in spatial.gd, not here). This returns the
## fraction of the fight elapsed when the two fronts first cross, which separates them outright.
func _meet_frac(res: Dictionary) -> float:
	var f0: Dictionary = res.frames[0]
	var a0 := -INF
	var b0 := INF
	for u in f0.units:
		if str(u.team) == "A":
			a0 = maxf(a0, Vector2(u.pos).x)
		else:
			b0 = minf(b0, Vector2(u.pos).x)
	for i in res.frames.size():
		var f: Dictionary = res.frames[i]
		var af := -INF
		var bf := INF
		for u in f.units:
			if not bool(u.alive):
				continue
			if str(u.team) == "A":
				af = maxf(af, Vector2(u.pos).x)
			else:
				bf = minf(bf, Vector2(u.pos).x)
		if af == -INF or bf == INF:
			continue
		if bf - af <= 0.0:
			return float(i) / maxf(1.0, float(res.frames.size() - 1))
	return NAN   # the lines never crossed at all


## Mean advance per POSTURE at a sample tick — the direct indictment when one posture is parked.
## Advance is measured against that unit's OWN deploy x (frame 0, index-aligned), so a posture
## that never leaves its anchor reads 0.00 whatever the rest of its team does.
func _advance_by_posture(res: Dictionary, tick: int) -> Dictionary:
	var f0: Dictionary = res.frames[0]
	var f: Dictionary = res.frames[clampi(tick, 0, res.frames.size() - 1)]
	var home := {"A": 0.0, "B": 0.0}
	var n0 := {"A": 0, "B": 0}
	for u in f0.units:
		home[str(u.team)] = float(home[str(u.team)]) + Vector2(u.pos).x
		n0[str(u.team)] = int(n0[str(u.team)]) + 1
	for t in ["A", "B"]:
		home[t] = float(home[t]) / maxf(1.0, float(n0[t]))
	var half_sep: float = absf(float(home["B"]) - float(home["A"])) * 0.5
	var sums := {}
	var counts := {}
	for j in f.units.size():
		var u: Dictionary = f.units[j]
		if not bool(u.alive) or str(u.get("posture", "")) == "":
			continue
		var p: String = str(u.posture)
		var adv: float = absf(Vector2(u.pos).x - Vector2(f0.units[j].pos).x) / maxf(1.0, half_sep)
		sums[p] = float(sums.get(p, 0.0)) + adv
		counts[p] = int(counts.get(p, 0)) + 1
	var out := {}
	var keys: Array = sums.keys()
	keys.sort()
	for k in keys:
		out[k] = float(sums[k]) / float(counts[k])
	return out


func _fmt_advance(m: Dictionary) -> String:
	var keys: Array = m.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s %.2f" % [k, float(m[k])])
	return ", ".join(parts)


## Cumulative share of a COVER_GRID cell grid any living body ever occupied across the fight.
func _coverage(res: Dictionary) -> float:
	var g: Vector2 = Sp.ground_size(BIG_TEAM_SIZE)
	var seen := {}
	for f in res.frames:
		for u in f.units:
			if not bool(u.alive):
				continue
			var p: Vector2 = Vector2(u.pos) + g * 0.5
			var cx: int = clampi(int(p.x / g.x * float(COVER_GRID.x)), 0, COVER_GRID.x - 1)
			var cy: int = clampi(int(p.y / g.y * float(COVER_GRID.y)), 0, COVER_GRID.y - 1)
			seen[cy * COVER_GRID.x + cx] = true
	return float(seen.size()) / float(COVER_GRID.x * COVER_GRID.y)


## Posture mix over the whole fight (living units only), as "name:share" in share order.
func _posture_mix(res: Dictionary) -> String:
	var tally := {}
	var total := 0
	for f in res.frames:
		for u in f.units:
			if bool(u.alive) and str(u.get("posture", "")) != "":
				tally[str(u.posture)] = int(tally.get(str(u.posture), 0)) + 1
				total += 1
	var keys: Array = tally.keys()
	keys.sort_custom(func(a, b): return int(tally[a]) > int(tally[b]))
	var parts: Array = []
	for k in keys:
		parts.append("%s %.0f%%" % [k, 100.0 * float(tally[k]) / maxf(1.0, float(total))])
	return ", ".join(parts)


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
		{"seed": 8888, "comp": "sustain"},      # healing at 5v5 scale — resolution's hard case
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

	# 3b. SUSTAIN NON-VACUOUS — the healing comp only guards resolution if BOTH healers
	# actually healed. A silently-idle healer (out of range, gated, broken kit) would make
	# check 1 a lie for this comp, so vacuity fails loudly here.
	var heals := {"a4": 0, "b4": 0}
	for r in results:
		if not str(r.label).begins_with("sustain/"):
			continue
		for f in r.frames:
			for e in f.events:
				if str(e.kind) == "heal" and heals.has(str(e.get("from", ""))):
					heals[str(e.get("from", ""))] += 1
	if not (int(heals["a4"]) > 0 and int(heals["b4"]) > 0):
		print("    sustain heals by caster: ", heals)
		for r in results:
			if str(r.label).begins_with("sustain/"):
				print("    sustain winner=%s ticks=%d" % [str(r.winner), int(r.ticks)])
				for hid in ["a4", "b4"]:
					print("    %s decisions: " % hid, r.decision_logs.get(hid, []))
	_check("sustain: both healers actually healed in the 5v5 (comp non-vacuous)",
		int(heals["a4"]) > 0 and int(heals["b4"]) > 0)

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

	await _board_usage(moves)

	_finish(false)


## ---- 12-15. BOARD USAGE at real 5v5 scale ---------------------------------------------------
func _board_usage(moves: Array) -> void:
	var g: Vector2 = Sp.ground_size(BIG_TEAM_SIZE)
	print("  -- board usage on the REAL %dx%d ground (sep %.0f, slow speed %.1f) --"
		% [int(g.x), int(g.y), Sp.deploy_separation(BIG_TEAM_SIZE), Sp.slow_unit_speed(BIG_TEAM_SIZE)])
	var plan: Array = [
		{"seed": 11, "comp": "brawl"},
		{"seed": 222, "comp": "wings"},
		{"seed": 3333, "comp": "caster_peel"},
		{"seed": 44444, "comp": "dive"},
		{"seed": 55555, "comp": "kite"},
		{"seed": 8888, "comp": "sustain"},
		# ⚠️ A SECOND SEED ON `dive` SPECIFICALLY. dive/seed44444 is the comp that resolved on
		# the toy board and hit the 1800-tick cap with NO WINNER on the real one; a single seed
		# proving a fight-breaking bug fixed is a coincidence, not a result.
		{"seed": 12321, "comp": "dive"},
	]
	var rows: Array = []
	for p in plan:
		var r: Dictionary = await _run_big_fight(int(p.seed), str(p.comp), moves)
		if r.is_empty():
			print("    FAIL nav never became ready for big %s seed %d" % [str(p.comp), int(p.seed)])
			_fails += 1
			return
		r["label"] = "%s/seed%d" % [str(p.comp), int(p.seed)]
		rows.append(r)
	for r in rows:
		var cov: float = _coverage(r)
		var line := "    %-20s winner=%s ticks=%4d cover=%.2f  " % [str(r.label), str(r.winner), int(r.ticks), cov]
		for frac in USAGE_SAMPLES:
			var m: Dictionary = _usage_at(r, int(float(r.frames.size() - 1) * float(frac)))
			line += "| %.0f%% advA=%.2f advB=%.2f gap=%+.2f lat=%.2f %s " % [
				float(frac) * 100.0, float(m.advA), float(m.advB), float(m.gap), float(m.lateral),
				"C" if bool(m.contest) else "-"]
		print(line)
		print("      meet at %.0f%% of the fight | postures: %s" % [100.0 * _meet_frac(r), _posture_mix(r)])
		print("      advance by posture @34%%: ", _fmt_advance(_advance_by_posture(r, int(float(r.frames.size() - 1) * 0.34))))
	_usage_checks(rows)


## ── 12-15. THE BOARD-USAGE ACCEPTANCE ────────────────────────────────────────────────────────
## ⚠️ EVERY THRESHOLD HERE WAS SET FROM A MEASURED BEFORE/AFTER, not from taste. Baseline is the
## tree BEFORE combat_tree.gd's BOARD SCALE block; "now" is with it. Same seeds, same comps, same
## real 440x246 ground.
##
##                        BEFORE                          NOW
##   dive/seed44444       1800 ticks, NO WINNER (cap)     425 ticks, B wins
##   caster_peel/3333     877 ticks                       416 ticks
##   Hold advance @34%    0.04 / 0.05                     0.75 / 0.82 / 0.90
##   Guard advance @34%   0.07                            0.83
##   Kite  advance @34%   0.00                            0.29
##   centre contested     caster_peel and dive: NEVER     all six comps, at 20/34/50%
##   coverage (min)       0.46                            0.56
##
## The four checks below are the cheapest statements of those four gains that leave enough room
## for ordinary seed-to-seed movement. ⚠️ The `no parked posture` floor is the load-bearing one:
## it is the check that would have caught the original bug, and the one that catches any future
## posture written as an absolute distance.
##
## ⚠️ EACH THRESHOLD WAS CHECKED AGAINST THE PRE-FIX TREE, and three of the four genuinely fail
## on it (unresolved `dive`; five parked postures; the centre uncontested in two comps at 34%).
## The coverage floor is the weak one — it discriminates only narrowly (baseline min 0.46 vs
## 0.56 now), so it is set at 0.48 to keep it a real detector rather than decoration, and it
## should be re-judged if seed variance ever brushes it.
const USAGE_MIN_ADVANCE := 0.15     # every posture must at least be walking to the fight
const USAGE_MIN_COVERAGE := 0.48    # cumulative share of the board any body ever stood in
const USAGE_MIN_CONTESTED := 6      # of the 7 runs, at each of the 34% and 50% samples

func _usage_checks(rows: Array) -> void:
	# 12. RESOLUTION AT REAL SCALE. `dive` resolved on the toy board and hit the cap on the real
	# one — the single clearest statement that the small board was hiding a fight-breaking bug.
	var unresolved: Array = []
	for r in rows:
		if not (str(r.winner) in ["A", "B"]) or int(r.ticks) >= TICK_CAP:
			unresolved.append("%s -> winner=%s ticks=%d" % [str(r.label), str(r.winner), int(r.ticks)])
	for s in unresolved:
		print("    big-board unresolved: ", s)
	_check("board usage: every fight resolves on the REAL 5v5 ground too", unresolved.is_empty())

	# 13. NO PARKED POSTURE. A posture whose units sit on their deploy anchor while the rest of
	# the team fights is not a tactic, it is an absent monster — and the player picked it.
	var parked: Array = []
	for r in rows:
		var adv: Dictionary = _advance_by_posture(r, int(float(r.frames.size() - 1) * 0.34))
		for p in adv:
			if float(adv[p]) < USAGE_MIN_ADVANCE:
				parked.append("%s: %s advanced %.2f" % [str(r.label), str(p), float(adv[p])])
	for s in parked:
		print("    parked posture: ", s)
	_check("board usage: no posture is parked at 34%% (every posture advances >= %.2f)" % USAGE_MIN_ADVANCE,
		parked.is_empty())

	# 14. THE CENTRE IS CONTESTED. "Both teams hug their deploy edges with an empty centre" is
	# what this measures directly: do BOTH sides have a body in the central third of the board?
	for frac in [0.34, 0.50]:
		var n := 0
		var missing: Array = []
		for r in rows:
			var m: Dictionary = _usage_at(r, int(float(r.frames.size() - 1) * float(frac)))
			if bool(m.contest):
				n += 1
			else:
				missing.append(str(r.label))
		if n < USAGE_MIN_CONTESTED:
			print("    centre uncontested at %.0f%%: %s" % [frac * 100.0, ", ".join(missing)])
		_check("board usage: the centre is contested at %.0f%% of the fight in >= %d of %d comps"
			% [frac * 100.0, USAGE_MIN_CONTESTED, rows.size()], n >= USAGE_MIN_CONTESTED)

	# 15. COVERAGE. The whole-fight footprint, so a fight that resolves inside one thin band still
	# reads as the failure it is.
	var thin: Array = []
	for r in rows:
		var c: float = _coverage(r)
		if c < USAGE_MIN_COVERAGE:
			thin.append("%s: %.2f" % [str(r.label), c])
	for s in thin:
		print("    thin footprint: ", s)
	_check("board usage: every fight covers >= %.0f%% of the board over its length" % (USAGE_MIN_COVERAGE * 100.0),
		thin.is_empty())


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
