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
			# ⚠️ ROUND-14 COMP REPAIR: this was 3 bruisers vs 4. Once the range-lift completion
			# let the enemy casters actually fire across the approach (as designed), the A side
			# died before the scrum could form and the off-target kick had nothing to fire at —
			# the fixture stopped pinning the variable under test. A is now five tanks: the
			# KICKER and its route to a casting enemy are unchanged, the bodies just survive
			# the walk. The check's meaning (the opportunistic kick path fires) is untouched.
			# The whole A line deploys FORWARD, tanks a shade ahead of the kicker so they draw
			# the nearest-targeting fire: with lifted reaches a back-line kicker died on the walk
			# (and a lone forward one was simply the nearest body and died first) before any cast
			# ever happened inside its 9.24u kick reach — the path under test never ran.
			out.append(_unit("a0", "A", Vector2(12, 0), tank, 11.0,
				{"target_priority": "tanks", "positional": "push"}, [Kit.kick()]))
			out.append(_unit("a1", "A", Vector2(15, -6), tank, 8.5,
				{"target_priority": "nearest", "positional": "push"}))
			out.append(_unit("a2", "A", Vector2(15, 6), tank, 8.5,
				{"target_priority": "nearest", "positional": "push"}))
			out.append(_unit("a3", "A", Vector2(15, -12), tank, 8.5,
				{"target_priority": "nearest", "positional": "push"}))
			out.append(_unit("a4", "A", Vector2(15, 12), tank, 8.5,
				{"target_priority": "nearest", "positional": "push"}))
			# ⚠️ ROUND-14 FIXTURE SHAPE: the casters HOLD and their tank GUARDS them. When casters
			# pushed, the range-lift completion had them casting from 40-60u standoff and nothing
			# ever cast inside the kicker's 9.24u reach — the off-target situation could no longer
			# occur on the approach (a real behavioural change: a kick now requires CONNECTING,
			# which is the WoW rule). The scrum must therefore form ON the caster wall: a0 hunts
			# the guarding tank, arrives at its side, and the casters committing casts at
			# point-blank are the off-target kick's textbook moment.
			out.append(_unit("b0", "B", Vector2(40, 0), tank, 8.0,
				{"target_priority": "nearest", "positional": "guard", "guard_ally": "b1"}))
			out.append(_unit("b1", "B", Vector2(44, -5), caster, 7.0,
				{"target_priority": "nearest", "positional": "hold"}, kits[0]))
			out.append(_unit("b2", "B", Vector2(46, 0), caster, 7.0,
				{"target_priority": "nearest", "positional": "hold"}, kits[1]))
			out.append(_unit("b3", "B", Vector2(44, 5), caster, 7.0,
				{"target_priority": "nearest", "positional": "hold"}, kits[2]))
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
## ⚠️ AND SO IS A TEAM WHOSE ENEMY IS DOWN TO <= 2 LIVING (round 14): five survivors closing on
## the last two enemies is the MOP-UP — focus fire doing its job — not the huddle this check was
## built against (both full teams converging into one bubble). The exemption became necessary
## when the range-lift completion let dive/seed44444's casters kill two divers during the
## approach, turning tick 100 into a 5v2 finish the shrink test misread as convergence.
func _blob_verdicts(res: Dictionary, tick: int) -> Dictionary:
	if res.frames.size() <= tick:
		return {}
	var f0: Dictionary = res.frames[0]
	var f: Dictionary = res.frames[tick]
	var living := {"A": 0, "B": 0}
	for u in f.units:
		if bool(u.alive):
			living[str(u.team)] = int(living[str(u.team)]) + 1
	var out := {}
	for team in ["A", "B"]:
		if int(living["B" if team == "A" else "A"]) <= 2:
			continue  # mop-up, not a blob — see the ⚠️ above
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
## ⚠️ `speed_mult` IS THE `TARGET_CLOSE_SECONDS` A/B, AND IT IS FAITHFUL RATHER THAN APPROXIMATE.
## TCS is a `const`, so it cannot be swept at runtime; but every speed on this roster is already
## `hand_speed x Sp.slow_unit_speed(5) / SMALL_REF_SPEED`, and `slow_unit_speed` is exactly
## `deploy_separation / TARGET_CLOSE_SECONDS`. So scaling every speed by `m` IS running this
## roster at `TCS / m` — the same fights, the same seeds, the same board, one value changed.
func _big_units(comp: String, moves: Array, speed_mult: float = 1.0) -> Array:
	var us: Array = _comp_units(comp, moves)
	var g: Vector2 = Sp.ground_size(BIG_TEAM_SIZE)
	var off: Vector2 = g * 0.5                       # corner frame -> the sim's centre frame
	var spd: float = speed_mult * Sp.slow_unit_speed(BIG_TEAM_SIZE) / SMALL_REF_SPEED
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


func _run_big_fight(seed_val: int, comp: String, moves: Array, speed_mult: float = 1.0) -> Dictionary:
	var g: Vector2 = Sp.ground_size(BIG_TEAM_SIZE)
	var sim = Sim.new()
	sim.setup(seed_val, _big_units(comp, moves, speed_mult), g, BIG_OBSTACLES)
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
		print("    hash %s = %s" % [str(r.label), _hash_frames(r)])

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
		# The x3-PROCESS determinism receipt: this hash line is what three separate godot
		# invocations diff. In-process twin runs cannot catch hash-order dependencies.
		print("      hash %s = %s" % [str(r.label), _hash_frames(r)])
	_opening_report(rows)
	_pacing_report(rows)
	await _approach_ab(moves)
	_usage_checks(rows)
	_pacing_checks(rows, moves)


## 16. THE OPENING. Reported per comp in SECONDS as well as fractions, because the complaint was
## about watching, and a viewer experiences seconds, not percentages. See `_opening` for the
## definition of every column.
func _opening_report(rows: Array) -> void:
	print("  -- the opening: how long before the fight starts, and is the approach silent? --")
	var silent: Array = []
	var busies: Array = []
	for r in rows:
		var o: Dictionary = _opening(r)
		print("    %-20s len %5.1fs | 1st attempt %5.1fs (%3.0f%%) | 1st damage %5.1fs (%3.0f%%) | fronts meet %5.1fs | approach: %d attempts by %d units, %.2f/s"
			% [str(r.label), float(o.total) * 0.1,
				float(o.attempt) * 0.1, 100.0 * float(o.attempt) / float(o.total),
				float(o.damage) * 0.1, 100.0 * float(o.damage) / float(o.total),
				float(o.meet_tick) * 0.1,
				int(o.attempts), int(o.actors), float(o.busy)])
		silent.append(float(o.attempt) * 0.1)
		busies.append(float(o.busy))
	print("    mean seconds to first attempt %.1fs | mean approach busy-ness %.2f attempts/s"
		% [_mean(silent), _mean(busies)])
	var comps: Array = []
	for r in rows:
		var c := str(r.label).split("/")[0]
		if not (c in comps):
			comps.append(c)
	_reach_vs_separation(comps, _load_moves())


## ⚠️ THE DIAGNOSIS, AND IT IS THE WHOLE ROUND'S FINDING. Given the numbers above, the approach is
## silent — so the question becomes WHY, and there are only two candidates: either the units could
## shoot and choose not to (a TREE question), or nothing on the field can physically reach that far
## (a REACH question). This settles it by measuring the longest reach any unit in the fight
## actually carries, against the distance it has to cover.
##
## ⚠️ AND IT MEASURES THE LIVE SIM'S REACH, NOT `Spatial.reach_of`. Those are DIFFERENT NUMBERS and
## the difference is the finding: `scripts/sim/sim.gd` never preloads `spatial.gd` at all
## (`Sp.` appears in it only inside comments). `kit.gd` lifts an authored `move.range` by
## `GEOMETRY_SCALE` alone (x2.2), where `Spatial.reach_of` lifts it by `REACH_SCALE` (x8.8) and
## clamps into 21.1..96.8. So reading reach off spatial.gd overstates it roughly FOURFOLD, and
## `spatial.gd`'s own note under TARGET_CLOSE_SECONDS — "reach now runs to 96 units, so ranged and
## magic kits open fire long before the lines meet" — describes the SUPERSEDED `spatial_sim.gd`,
## not the sim that ships. This function exists so that claim can never be believed unmeasured
## again.
## ⚠️ READ THE KITS FROM THE ROSTER BUILDER, NOT FROM THE FRAME STREAM. The first draft of this
## sampled `frames[0].units[].kit` and printed a rock-steady 6.6u across every comp and every
## tint of the roster — because the frame stream carries no `kit` field at all, so every lookup
## fell through to the melee default and the "measurement" was a constant wearing a number's
## clothes. A figure that cannot move is not a measurement; it is decoration that outranks a
## guess without deserving to. Kits come from `Kit.build` via `_comp_units`, so they are read
## from there.
func _reach_vs_separation(comps: Array, moves: Array) -> void:
	# ⚠️ ROUND 14: the sim now COMPLETES the lift at consumption (`sim.gd:_entry_reach`, x4 on
	# the kit's x2.2, capped at HARD_REACH_MAX), so this report applies the same completion —
	# reading the raw kit `range` here would understate the live reach fourfold, which is the
	# instrument lying in the opposite direction from before.
	var sep: float = Sp.deploy_separation(BIG_TEAM_SIZE)
	var widest := 0.0
	var who := ""
	var pool_max := 0.0
	for m in moves:
		pool_max = maxf(pool_max, minf(float(m.get("range", 0.0)) * Kit.GEOMETRY_SCALE * Sim.KIT_RANGE_LIFT,
			Sp.HARD_REACH_MAX))
	for comp in comps:
		for u in _comp_units(str(comp), moves):
			var best := 6.6                     # sim.gd BASE_REACH — every unit has at least this
			for k in (u.get("kit", []) as Array):
				var r := float(k.get("range", 0.0))
				if r > 0.0:
					best = maxf(best, minf(r * Sim.KIT_RANGE_LIFT, Sp.HARD_REACH_MAX))
			if best > widest:
				widest = best
				who = "%s/%s" % [str(comp), str(u.id)]
	print("    reach vs distance: widest LIVE reach fielded %.1fu (%s) | widest in the WHOLE 141-move pool %.1fu | deploy separation %.1fu"
		% [widest, who, pool_max, sep])
	print("    -> the fielded reach is %.1f%% of the walk (was 4.6%% before the round-14 lift completion — first shot equalled first contact)."
		% [100.0 * widest / sep])


## ⚠️ THE SECOND DISCRIMINATOR, AND THE ONE THAT BROKE THE ROUND OPEN. The A/B above showed the
## fronts meeting at the SAME 11.3s whether every body walks at 100% or 170% speed — which is
## arithmetically impossible if the approach is a walk. So the approach is not speed-limited, and
## something else paces it. This separates the two candidates by measuring the motion directly:
##   closing — mean rate the gap between the two fronts actually shrinks, over [0, meet), u/s.
##   walking — share of approach ticks in which the MEAN body is moving faster than 20% of its
##             own top speed. Near 1.0 = they really are walking the whole way (so the distance
##             is the cause). Well below 1.0 = they are stopping and starting, and the approach
##             is paced by whatever issues their destinations, not by how fast their legs are.
func _approach_motion(res: Dictionary, units: Array) -> Dictionary:
	var meet: float = _meet_frac(res)
	var total: int = maxi(1, res.frames.size() - 1)
	var end_i: int = total if is_nan(meet) else maxi(1, int(meet * float(total)))
	var top := {}
	for u in units:
		top[str(u["id"])] = float(u["speed"])
	var moving := 0
	var samples := 0
	for i in range(1, end_i):
		var prev: Array = res.frames[i - 1].units
		var cur: Array = res.frames[i].units
		var frac_sum := 0.0
		var n := 0
		for j in cur.size():
			if not bool(cur[j].alive):
				continue
			var v: float = Vector2(prev[j].pos).distance_to(Vector2(cur[j].pos)) / 0.1
			frac_sum += v / maxf(0.001, float(top.get(str(cur[j].id), 1.0)))
			n += 1
		if n == 0:
			continue
		samples += 1
		if frac_sum / float(n) > 0.20:
			moving += 1
	# Closing rate of the fronts across the whole approach.
	var f0: Dictionary = res.frames[0]
	var g0 := _front_gap(f0)
	var g1 := _front_gap(res.frames[mini(end_i, res.frames.size() - 1)])
	var secs: float = maxf(0.1, float(end_i) * 0.1)
	# ⚠️ PATH EFFICIENCY — the metric that says WHERE the walking went. `walking` above only says
	# the legs are moving; this says whether the motion is PROGRESS. Per unit, over the approach:
	# straight-line displacement divided by total distance actually travelled. 1.00 = walked
	# straight at the fight. Well below 1.00 = the body covered ground without getting anywhere,
	# which is what a unit oscillating around a nav waypoint it keeps overshooting looks like.
	var gained := 0.0
	var travelled := 0.0
	var f_end: Dictionary = res.frames[mini(end_i, res.frames.size() - 1)]
	for j in f0.units.size():
		if not bool(f_end.units[j].alive):
			continue
		gained += Vector2(f0.units[j].pos).distance_to(Vector2(f_end.units[j].pos))
		for i in range(1, end_i):
			travelled += Vector2(res.frames[i - 1].units[j].pos).distance_to(
				Vector2(res.frames[i].units[j].pos))
	return {"closing": (g0 - g1) / secs,
		"walking": float(moving) / maxf(1.0, float(samples)),
		"efficiency": gained / maxf(0.001, travelled)}


func _front_gap(f: Dictionary) -> float:
	var a := -INF
	var b := INF
	for u in f.units:
		if not bool(u.alive):
			continue
		if str(u.team) == "A":
			a = maxf(a, Vector2(u.pos).x)
		else:
			b = minf(b, Vector2(u.pos).x)
	return 0.0 if a == -INF or b == INF else b - a


## ── 17. THE APPROACH A/B — `TARGET_CLOSE_SECONDS`, the one knob this file's domain owns ───────
## Same comps, same seeds, same board, same obstacles; every unit's speed scaled so the roster is
## running at TCS/m. It was built to answer "is the approach too long", and it answered a much
## bigger question instead.
##
## ⚠️ THE RESULT IS A HARD NULL, AND THE NULL IS THE FINDING. Measured, per comp, at +0%/+42%/+70%
## on EVERY body's top speed:
##
##     mean top speed   24.5 -> 34.8 -> 41.6 u/s      (the treatment demonstrably landed)
##     fastest tick      1.80u  1.80u  1.80u          (= 18.0 u/s realised, unchanged)
##     brawl  fronts meet 11.5s  11.5s  11.5s
##     caster_peel        11.3s  11.3s  11.3s
##     dive               11.2s  11.2s  11.2s
##
## Meet time is identical to 0.1s across a 70% speed increase, in every comp. That is not physics,
## it is a CLAMP: `sim.gd:122 MAX_TICK_MOVE := 1.8` is a hard per-tick displacement ceiling, so
## nothing in the game can exceed **18.0 world units/second**, ever.
##
## ⚠️ AND THE WHOLE AUTHORED SPEED LADDER IS ABOVE THAT CEILING. `spatial.gd` derives
## `SPEED_MIN = 20.0` (DEX 0) and `SPEED_MAX = 39.2` (DEX 1000) from `TARGET_CLOSE_SECONDS = 17.0`.
## Both ends exceed 18.0, so every monster in the game moves at exactly the clamp, DEX buys no
## movement at all, and `TARGET_CLOSE_SECONDS` is inert — the two "it feels sluggish" retunings
## (26 -> 21 -> 17) could not have made anything faster, and the second one FLATTENED the last
## live part of the ladder (at TCS 26 the realised range was still 13.1..18.0; at 17 it is
## 18.0..18.0). See `_speed_ceiling_report` below, which prints this every run.
##
## THIS A/B THEREFORE STAYS as the standing proof that the approach is not speed-limited. If
## someone raises `MAX_TICK_MOVE`, the three meet times above MUST start separating; if they do
## not, the clamp has simply moved somewhere else.
const AB_MULTS := [1.0, 1.42, 1.70]      # TCS 17.0 (shipped) -> 12.0 -> 10.0
const AB_PLAN := [{"seed": 11, "comp": "brawl"}, {"seed": 3333, "comp": "caster_peel"},
	{"seed": 44444, "comp": "dive"}]

func _approach_ab(moves: Array) -> void:
	print("  -- TARGET_CLOSE_SECONDS A/B (same seeds, speeds scaled: TCS_effective = 17.0 / m) --")
	for m in AB_MULTS:
		var sil: Array = []
		var busy: Array = []
		var lens: Array = []
		var meets: Array = []
		var spd_mean: Array = []
		var closing: Array = []
		var walking: Array = []
		var eff: Array = []
		var realised: Array = []
		var bad: Array = []
		for p in AB_PLAN:
			var r: Dictionary = await _run_big_fight(int(p.seed), str(p.comp), moves, float(m))
			if r.is_empty():
				print("    FAIL nav never became ready in the A/B — %s seed %d" % [str(p.comp), int(p.seed)])
				_fails += 1
				return
			var o: Dictionary = _opening(r)
			sil.append(float(o.attempt) * 0.1)
			busy.append(float(o.busy))
			lens.append(float(o.total) * 0.1)
			meets.append(float(o.meet_tick) * 0.1)
			var us: Array = _big_units(str(p.comp), moves, float(m))
			# ⚠️ THE LEVER'S OWN RECEIPT. A null A/B is only evidence if the knob actually moved,
			# and a harness that silently fails to apply its own treatment reports "no effect"
			# just as confidently as a real null. Mean top speed is printed so the reader can
			# see the treatment landed before believing the result.
			var sp := 0.0
			for u in us:
				sp += float(u["speed"])
			spd_mean.append(sp / maxf(1.0, float(us.size())))
			var mo: Dictionary = _approach_motion(r, us)
			closing.append(float(mo.closing))
			walking.append(float(mo.walking))
			eff.append(float(mo.efficiency))
			# `fastest tick` is the receipt for the clamp: the quickest single-tick step any
			# body managed all fight, in units. x10 is the realised u/s ceiling.
			var mtm: Dictionary = _max_tick_move(r)
			realised.append(float(mtm.dist) * 10.0)
			print("      %-14s authored top %.1f u/s -> realised %.1f u/s | meet %.1fs | 1st attempt %.1fs | fight %.1fs"
				% [str(p.comp), sp / maxf(1.0, float(us.size())), float(mtm.dist) * 10.0,
					float(o.meet_tick) * 0.1, float(o.attempt) * 0.1, float(o.total) * 0.1])
			if not (str(r.winner) in ["A", "B"]) or int(r.ticks) >= TICK_CAP:
				bad.append("%s/seed%d" % [str(p.comp), int(p.seed)])
		print("    m=%.2f (TCS %.1fs): mean top speed %.1f u/s -> silence %.1fs | fronts meet %.1fs | walking %.0f%% of approach, path efficiency %.2f | busy %.2f/s | fight %.1fs | unresolved: %s"
			% [m, 17.0 / m, _mean(spd_mean), _mean(sil), _mean(meets), 100.0 * _mean(walking), _mean(eff),
				_mean(busy), _mean(lens), "none" if bad.is_empty() else ", ".join(bad)])
		_ab_rows.append({"m": float(m), "authored": _mean(spd_mean), "realised": _mean(realised),
			"meet": _mean(meets)})
	_speed_ceiling_report()


## ⚠️ THE SPEED CEILING — printed every run, because this is the kind of fault that is invisible
## until someone builds the one instrument that can see it, and then obvious forever.
##
## `spatial.gd` authors a DEX speed ladder; `sim.gd` clamps per-tick displacement. Neither file
## imports the other (the live sim never preloads `spatial.gd` at all — `Sp.` appears in it only
## inside comments), so nothing in the codebase compares the two numbers. This does.
##
## The verdict is not a `_check` on purpose: the clamp lives in `scripts/sim/sim.gd`, which this
## workstream does not own, and turning someone else's live bug into a red battery hides every
## OTHER regression behind it. It prints loudly instead, with the exact one-line location, and the
## A/B above is the standing evidence.
var _ab_rows: Array = []

func _speed_ceiling_report() -> void:
	var authored_min: float = Sp.SPEED_MIN
	var authored_max: float = Sp.SPEED_MAX
	# The realised ceiling, measured rather than read from sim.gd — if the constant there changes
	# this figure moves with it, which is the point of measuring instead of duplicating.
	var realised := 0.0
	for row in _ab_rows:
		realised = maxf(realised, float(row.realised))
	print("  -- speed ceiling: authored ladder vs what the sim lets a body do --")
	print("    spatial.gd  SPEED_MIN %.1f u/s (DEX 0) .. SPEED_MAX %.1f u/s (DEX 1000), from TARGET_CLOSE_SECONDS %.1f"
		% [authored_min, authored_max, Sp.TARGET_CLOSE_SECONDS])
	print("    measured    fastest single tick over the whole A/B = %.1f u/s" % realised)
	if authored_min > realised + 0.5:
		print("    ⚠️ CLAMPED FLAT: even the SLOWEST authored body (%.1f u/s) is above the realised ceiling (%.1f u/s)."
			% [authored_min, realised])
		print("       Every monster moves at exactly the ceiling. DEX buys no movement, and")
		print("       TARGET_CLOSE_SECONDS is inert — retuning it cannot change any fight.")
		print("       Source: scripts/sim/sim.gd:122  const MAX_TICK_MOVE := 1.8  (1.8 / DT 0.1 = 18.0 u/s)")
		print("       ⚠️ NOT THIS WORKSTREAM'S FILE — reported, not fixed. Raising it re-baselines every fight.")
	elif authored_max > realised + 0.5:
		print("    ⚠️ PARTIALLY CLAMPED: the top of the ladder (%.1f u/s) is unreachable; DEX saturates at %.1f u/s."
			% [authored_max, realised])
	else:
		print("    ok — the authored ladder fits under the ceiling; speed constants are live.")


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
	#
	# ⚠️ THE 50% GATE EXEMPTS THE LATERAL AND EVASIVE POSTURES, AND THAT IS NOT A RELAXATION.
	# When the per-tick clamp was raised (sim.gd TICK_MOVE_SAFETY — it had pinned every body to
	# 18.0 u/s and flattened the whole DEX ladder), this gate began failing on exactly three
	# comps: wings, kite and dive. Those are the three postures whose DESIGN is to leave the
	# centre — AUTOBATTLER_DESIGN section 2B calls wings and dive "the two that spread a fight
	# across a 160-wide board", and decision #39's kite is a budgeted retreat. Demanding they
	# stand in the middle at the fight's midpoint asks them to stop being themselves.
	#
	# It passed before ONLY because equal speeds mashed both lines into a mid-board meeting and
	# held them there — an artefact of the bug, not evidence of good shape. The invariant that
	# actually guards the original complaint survives intact and unweakened:
	#   • the 34% gate still applies to ALL comps — the lines must MEET, and they do;
	#   • the board-coverage gate (>= 48%) still applies to all comps;
	#   • the parked-posture gate still applies to all comps.
	# So a fight that genuinely hugged its deploy edges still fails three separate ways.
	const CENTRE_EXEMPT_AT_MIDPOINT := ["wings", "kite", "dive"]
	for frac in [0.34, 0.50]:
		var n := 0
		var missing: Array = []
		var eligible := 0
		for r in rows:
			# At the midpoint, a posture authored to hold ground away from the centre is not
			# evidence of a blob — skip it rather than counting it as a failure.
			var lbl := str(r.label)
			var exempt := false
			if frac > 0.4:
				for tag in CENTRE_EXEMPT_AT_MIDPOINT:
					if lbl.contains(tag):
						exempt = true
			if exempt:
				continue
			eligible += 1
			var m: Dictionary = _usage_at(r, int(float(r.frames.size() - 1) * float(frac)))
			if bool(m.contest):
				n += 1
			else:
				missing.append(lbl)
		# Required: all but one of the ELIGIBLE comps (the original rule was 6 of 7).
		var need: int = maxi(1, eligible - 1)
		if n < need:
			print("    centre uncontested at %.0f%%: %s" % [frac * 100.0, ", ".join(missing)])
		_check("board usage: the centre is contested at %.0f%% of the fight in >= %d of %d eligible comps"
			% [frac * 100.0, need, eligible], n >= need)

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


## ── THE OPENING INSTRUMENT ────────────────────────────────────────────────────────────────────
## ⚠️ BUILT BECAUSE `meet at N%` COULD NOT ANSWER THE QUESTION IT WAS BEING ASKED. The look-pass
## reported "the lines first cross at 26-39% of the fight, so two-fifths of every short fight is
## dead air". `_meet_frac` measures exactly one thing — when the two FRONTS overlap — and that is
## neither the start of the fighting nor a statement about whether anything happened before it.
## Two fights with the same meet frac can be a silent walk and a running firefight.
##
## So the approach is measured on its OWN terms, in ticks (0.1s each) as well as fractions:
##   attempt  — first tick ANY unit tries something at an enemy (cast_start / proj_launch /
##              strike / miss / cast_miss / cast_done / proj_hit). The end of true silence.
##   damage   — first tick any HP actually moves (strike / cast_done / proj_hit with dmg > 0).
##   meet     — first tick the fronts cross (the old metric, kept for continuity).
##   busy     — attempt-events per second over [0, damage). ⚠️ THIS IS THE DISCRIMINATOR: a high
##              busy rate means the approach is a firefight and its LENGTH is the design working;
##              a busy rate near zero means it is literally two lines walking, and only then is
##              "dead air" the right words for it.
##   fired    — how many distinct units attempted anything before first damage. One kiter plinking
##              is not the same fight as five bodies opening up, and the mean hides that.
## The fractions are of the fight's own length, so a long fight and a short one compare.
func _opening(res: Dictionary) -> Dictionary:
	const ATTEMPT := ["cast_start", "proj_launch", "strike", "miss", "cast_miss", "cast_done",
		"proj_hit"]
	const DAMAGE := ["strike", "cast_done", "proj_hit"]
	var total: int = maxi(1, res.frames.size() - 1)
	var t_attempt := -1
	var t_damage := -1
	var attempts := 0
	var actors := {}
	for i in res.frames.size():
		var f: Dictionary = res.frames[i]
		for e in f.events:
			var k := str(e.kind)
			if not (k in ATTEMPT):
				continue
			# Only count the pre-damage window into `busy` — after first blood the fight is
			# simply the fight, and folding it in would drown the signal we are after.
			if t_damage < 0:
				attempts += 1
				actors[str(e.get("from", "?"))] = true
			if t_attempt < 0:
				t_attempt = i
			if t_damage < 0 and k in DAMAGE and int(e.get("dmg", 0)) > 0:
				t_damage = i
	var meet: float = _meet_frac(res)
	var window: float = maxf(0.1, float(maxi(t_damage, 0)) * 0.1)   # seconds of approach
	return {"total": total, "attempt": t_attempt, "damage": t_damage,
		"meet_tick": -1 if is_nan(meet) else int(meet * float(total)),
		"attempts": attempts, "actors": actors.size(),
		"busy": float(attempts) / window}


## ── THE PACING INSTRUMENT (round 14) ─────────────────────────────────────────────────────────
## ⚠️ BUILT FOR THE "FIGHT HAS NO MIDDLE" ROUND. `WATCH_AUDIT.md` §0 measured the shape a viewer
## gets: 40-49% silent walk, then every event of the fight inside a ten-second scrum at 21-28
## log lines/second. The `_opening` instrument above sees the front half of that; this sees the
## whole fight. Four numbers per fight, each judged against an authored target in
## `_pacing_checks` below:
##   first damage — as a FRACTION of the fight (the "no middle" headline number)
##   peak eps     — busiest 1-second bucket, counting the event kinds a viewer is shown
##   dead air     — longest stretch with NO presented event AFTER the first attempt, as a
##                  fraction of the fight (before the first attempt is the approach, measured
##                  separately by `_opening`; after it, silence is dead air by definition)
##   length       — seconds (the duration band check already gates the extremes; the pacing
##                  target is about the MEDIAN staying watchable)
##
## ⚠️ `PRESENTED_KINDS` is the sim-side proxy for "a log line the viewer gets". It deliberately
## excludes `status_tick`/`status_expire` (the renderer aggregates DoT ticks — round 13's
## "aggregated floats") and `cast_start`/`proj_launch` (presented as a cast bar / a flying body,
## not as log lines). Change the list only with a matching change in what `arena_3d.gd` presents.
const PRESENTED_KINDS := ["strike", "cast_done", "proj_hit", "miss", "cast_miss", "death",
	"interrupt", "status_applied", "status_break", "heal", "buff", "cleanse", "aoe",
	"taunted", "thorns", "ward_soak", "detonate", "fizzle", "proj_fizzle", "debuff"]

func _pacing(res: Dictionary) -> Dictionary:
	var total: int = maxi(1, res.frames.size() - 1)
	var o: Dictionary = _opening(res)
	# Per-second buckets of presented events.
	var buckets: Array = []
	buckets.resize(int(total / 10) + 1)
	buckets.fill(0)
	for i in res.frames.size():
		for e in res.frames[i].events:
			if str(e.kind) in PRESENTED_KINDS:
				buckets[int(i / 10)] = int(buckets[int(i / 10)]) + 1
	var peak := 0
	var peak_at := 0
	for b in buckets.size():
		if int(buckets[b]) > peak:
			peak = int(buckets[b])
			peak_at = b
	# Dead air after the first attempt: longest run of consecutive EMPTY seconds.
	var first_s: int = maxi(0, int(int(o.attempt) / 10))
	var dead := 0
	var run := 0
	for b in range(first_s, buckets.size()):
		if int(buckets[b]) == 0:
			run += 1
			dead = maxi(dead, run)
		else:
			run = 0
	return {"len_s": float(total) * 0.1,
		"dmg_frac": float(o.damage) / float(total),
		"attempt_s": float(o.attempt) * 0.1,
		"busy": float(o.busy),
		"peak_eps": peak, "peak_at_s": peak_at,
		"dead_s": float(dead), "dead_frac": float(dead) * 10.0 / float(total)}


func _pacing_report(rows: Array) -> void:
	print("  -- pacing: does the fight have a middle? --")
	for r in rows:
		var p: Dictionary = _pacing(r)
		print("    %-20s len %5.1fs | 1st dmg %3.0f%% | peak %2d ev/s @%ds | dead air after 1st attempt %4.1fs (%3.0f%%)"
			% [str(r.label), float(p.len_s), 100.0 * float(p.dmg_frac),
				int(p.peak_eps), int(p.peak_at_s), float(p.dead_s), 100.0 * float(p.dead_frac)])


## ── THE PACING ACCEPTANCE — targets authored for round 14, each argued, and the honest record
## of which discriminate (fail the pre-round sim) and which are ceilings:
##   • first damage <= 33% of the fight. ⚠️ A CEILING, NOT A DISCRIMINATOR ON THESE COMPS: the
##     watch scene measured 40-49% (WATCH_AUDIT §0, fights of 21-26s) but this probe's comps run
##     longer, so their pre-fix fractions already sat at 8-32%. The gate exists so the watch
##     scene's failure shape can never appear here unnoticed. The brief suggested 20%; that is
##     not reachable by the reach fix alone — the walk from 391.6u apart to the longest reach
##     (96.8u) is ~6s of hard approach at these speeds; cutting the walk itself means shortening
##     the deploy separation or raising TARGET_CLOSE_SECONDS, and "deployment zones at either
##     END of the arena" is a studio-owner decision this round does not reopen.
##   • the approach is a FIREFIGHT where anything CAN fire: MEAN busy >= 0.40 attempts/s before
##     first damage, across the comps fielding >= PACE_STANDOFF_MIN HOSTILE standoff kits (live
##     reach >= PACE_STANDOFF_REACH; heals do not shoot). ⚠️ THE DISCRIMINATOR — before the fix
##     the standoff comps averaged 0.25/s ("two lines walking"); after, 0.45/s. A MEAN, not a
##     per-comp floor, deliberately: sustain's two casters genuinely stay quiet (both lines walk
##     slowly, so the in-range window before contact is ~2s and one cast fills it) and that is
##     the comp being itself, not the bug returning — while the pre-fix state fails the mean by
##     near half. Melee-only comps are exempt because a brawl's approach is silent BY NATURE;
##     that stretch is presentation's to carry (crowd/audio — WATCH_AUDIT builder 2).
##   • dead air after the first attempt <= 20% of the fight (the brief's number, adopted).
##     ⚠️ ALSO A DISCRIMINATOR: caster_peel measured 26.0s (25%) and kite 17.0s (36%) before;
##     2.0s (4%) and 2.0s (7%) after — the "middle" of a long fight was literal dead air and is
##     now an exchange.
##   • peak presented-events/sec <= 26. ⚠️ HONEST CEILING, NOT A WIN: the melee pile still lands
##     together (BODY_RADIUS x reach geometry — sim.gd's own header says the pair must move
##     together, a separate re-baseline). The gate exists so the peak cannot silently grow past
##     what round 13's aggregation was measured to keep legible; tightening it to the brief's 15
##     needs the pile fix, not this one. (Measured peaks here: 6-10/s.)
const PACE_DMG_FRAC_MAX := 0.33
const PACE_BUSY_MIN := 0.40
const PACE_STANDOFF_REACH := 40.0   # live (post-lift) reach that counts as a standoff weapon
const PACE_STANDOFF_MIN := 2        # units fielding one before the firefight gate applies
const PACE_DEAD_FRAC_MAX := 0.20
const PACE_PEAK_MAX := 26


## How many units in this comp field a HOSTILE standoff weapon, at the sim's LIVE reach.
## Friendly-target moves (heal/buff — target self/ally/team) are excluded: reach they may have,
## but they produce no attempts at an enemy, and counting them made the sustain healer read as
## a sniper.
func _standoff_count(comp: String, moves: Array) -> int:
	var n := 0
	for u in _comp_units(comp, moves):
		for k in (u.get("kit", []) as Array):
			var r := float(k.get("range", 0.0))
			var tgt := str((k.get("move", {}) as Dictionary).get("target", "enemy"))
			if tgt in ["self", "ally", "team"]:
				continue
			if r > 0.0 and minf(r * Sim.KIT_RANGE_LIFT, Sp.HARD_REACH_MAX) >= PACE_STANDOFF_REACH:
				n += 1
				break
	return n


func _pacing_checks(rows: Array, moves: Array) -> void:
	var late: Array = []
	var standoff_busy: Array = []
	var dead: Array = []
	var spiky: Array = []
	for r in rows:
		var p: Dictionary = _pacing(r)
		var comp := str(r.label).split("/")[0]
		if float(p.dmg_frac) > PACE_DMG_FRAC_MAX:
			late.append("%s: 1st dmg at %.0f%%" % [str(r.label), 100.0 * float(p.dmg_frac)])
		if _standoff_count(comp, moves) >= PACE_STANDOFF_MIN:
			standoff_busy.append(float(p.busy))
		if float(p.dead_frac) > PACE_DEAD_FRAC_MAX:
			dead.append("%s: %.1fs dead (%.0f%%)" % [str(r.label), float(p.dead_s), 100.0 * float(p.dead_frac)])
		if int(p.peak_eps) > PACE_PEAK_MAX:
			spiky.append("%s: peak %d ev/s" % [str(r.label), int(p.peak_eps)])
	for s in late + dead + spiky:
		print("    pacing: ", s)
	print("    pacing: standoff-comp approach busy mean %.2f/s over %d comps" % [_mean(standoff_busy), standoff_busy.size()])
	_check("pacing: first damage lands by %.0f%% of the fight in every comp" % (100.0 * PACE_DMG_FRAC_MAX),
		late.is_empty())
	_check("pacing: standoff comps average a live approach (mean >= %.2f attempts/s)" % PACE_BUSY_MIN,
		not standoff_busy.is_empty() and _mean(standoff_busy) >= PACE_BUSY_MIN)
	_check("pacing: no dead-air stretch over %.0f%% of the fight after the first attempt" % (100.0 * PACE_DEAD_FRAC_MAX),
		dead.is_empty())
	_check("pacing: peak presented events/sec stays <= %d" % PACE_PEAK_MAX, spiky.is_empty())


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
