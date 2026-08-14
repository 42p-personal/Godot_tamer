## THE SPATIAL BALANCE INSTRUMENT — task #32, pending for twenty rounds.
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_balance.tscn
##      ... -- --seeds=5        (default 3; 1..5)
##      ... -- --quick          (census + canaries only, no trade table)
## Exit code: 0 if every CANARY passed. ⚠️ The BALANCE numbers never set the exit code — this is
## an instrument, not a gate (the same split `_sweep_comps.gd` states). Only the canaries gate,
## because a canary failure means the numbers above it are meaningless.
##
## ── WHY IT EXISTS ────────────────────────────────────────────────────────────────────────────
## This project has two balance harnesses (`tools/sweep40.ts`, `tools/ab.ts`) and BOTH target the
## TypeScript engine. `_probe_sim_quality.gd` measures PACING and SHAPE on the spatial sim and is
## good at that; it cannot answer "is AoE now dominant" or "did melee get worse". Nothing could.
##
## ── WHAT IT MEASURES, IN FOUR SECTIONS ───────────────────────────────────────────────────────
##  §1 AOE GEOMETRY CENSUS — static, no fights. Every allEnemies move's LIVE blast radius after
##     `sim.gd:_entry_reach` (authored range x KIT_RANGE_LIFT 8.8, clamped at HARD_REACH_MAX),
##     against melee reach, the enemy team's own footprint, and the deploy separation.
##  §2 AOE IN FIGHT — the distribution of targets-caught-per-burst in REAL fights on the REAL
##     board, and AoE's share of all damage. The standing rule is "weak into one body, strong
##     into three", audited AT THREE. If bursts catch five every time, falloff-at-5 is the normal
##     case and the whole AoE half of the pool is priced against a case that never occurs.
##  §3 ARCHETYPE TRADE — four kit archetypes at EQUAL STAT TOTALS, every pairing, both sides,
##     paired seeds, judged on a two-sided exact SIGN TEST (never a mean with a CI: a few fights
##     swing wildly when they tip from timeout to kill, and those outliers hide real effects —
##     the Balancing discipline's own rule, paid for twice already).
##  §4 ENDING SHAPE — how a fight FINISHES, with an error band at n large enough to judge:
##     length, first-blood fraction, and the COLLAPSE WINDOW (first death -> last death). Round 23
##     measured 17.4s / first blood at 72% / six deaths in five seconds AT n=1 and correctly
##     refused to tune on it.
##
## ── ⚠️ LIVENESS CANARIES, NON-NEGOTIABLE (signature failure #2: instruments that lie) ─────────
## Round 10's nav spike "passed" on 400 empty paths; round 15's instrument read 100% everywhere
## because it was pinned above the ceiling. Every measurable here has a perturbation that MUST
## move it, and the probe exits non-zero if it does not:
##   C1  AOE RADIUS  — the same fights with every kit range scaled x0.25. Mean targets-caught
##                     must FALL. If it does not, §2 is not reading the geometry it claims to.
##       ⚠️ HOW IT PERTURBS WITHOUT EDITING THE SIM: `sim.gd:_entry_reach` reads `entry.range` off
##       the kit dictionary this file builds. Scaling that field IS scaling the exact quantity
##       under test, with no sim edit and no second code path.
##   C2  TRADE TABLE — a mirror matchup with one side given +25% on every stat. The sign test
##                     must CALL it (p < 0.10 and the buffed side ahead). If a 25% stat lead is
##                     invisible, §3 cannot see anything smaller and its p-values mean nothing.
##   C3  ENDING      — the same fights with CON scaled x0.55 on both sides (smaller HP pools).
##                     Fights must get SHORTER. If length does not move, §4 is not reading it.
##   C4  DETERMINISM — the same seed twice, in-process, identical frame hash.
##       ⚠️ WEAKER THAN `_probe_arena_switch`: an in-process twin cannot catch a hash-ORDER
##       dependency, which is exactly what the cross-process check exists for. This is a smoke
##       test that this probe's own roster construction draws no rng, not the determinism gate.
##
## ── ⚠️ WHAT THIS INSTRUMENT CANNOT SEE, STATED UP FRONT ──────────────────────────────────────
##  • COMPOSITION. Every archetype here is five identical bodies with one kit axis changed. That
##    is deliberate — a mixed comp confounds the axis under test — but it means this probe says
##    nothing about whether a tank/healer/caster MIX is healthy. `_sweep_comps.gd` owns that.
##  • THE LADDER. `career.gd` preloads `battle_sim.gd`; nothing in the ladder's dependency chain
##    loads `sim/sim.gd`. Every number here describes the WATCHED fight only, and the gap between
##    the two engines is real and widening.
##  • WHETHER IT IS FUN. Nothing numeric answers that. `docs/OUTSTANDING.md` §3 still stands.
extends Node3D

const Sim = preload("res://scripts/sim/sim.gd")
const Kit = preload("res://scripts/sim/kit.gd")
const Sp = preload("res://scripts/spatial.gd")

## ── THE BOARD ────────────────────────────────────────────────────────────────────────────────
## ⚠️ THE REAL 5v5 GROUND, NEVER THE 110x62 TOY. Measuring a 43-79 unit blast radius on a board
## whose deploy separation is 80 would report "AoE catches everyone" as a property of AoE when it
## is a property of the fixture. `Sp.ground_size(5)` is 440x246.4 with 391.6 of separation.
const TEAM_SIZE := 5
const OBSTACLES := [{"rect": Rect2(-16, -16, 32, 32)}]  # one central mass, as _probe_sim_quality
## Hand speeds below are relative to this, then lifted by `Sp.slow_unit_speed(5) / SMALL_REF`,
## so one ratio moves the whole roster onto the real board without a second speed curve.
const SMALL_REF_SPEED := 8.0
const SEEDS := [101, 2027, 31337, 44449, 5150]

## ── THE ARCHETYPES ───────────────────────────────────────────────────────────────────────────
## ⚠️ EQUAL STAT TOTALS, AND THAT IS THE POINT. `_sweep_comps.gd`'s role blocks run 235 to 305 —
## fine for asking about composition SHAPE, useless for asking whether two kits trade fairly,
## because a 30% stat-budget gap would swamp the axis. Every block below sums to STAT_TOTAL.
const STAT_TOTAL := 250.0
const ARCH_STATS := {
	# STR/CON body: swings, walks in. Sum 250.
	"melee":  {"STR": 85.0, "DEX": 40.0, "CON": 70.0, "WIS": 25.0, "INT": 15.0, "CHA": 15.0},
	# DEX/CON body: shoots, holds a line. Sum 250.
	"ranged": {"STR": 30.0, "DEX": 90.0, "CON": 65.0, "WIS": 35.0, "INT": 15.0, "CHA": 15.0},
	# INT/WIS body. ⚠️ `caster` and `aoe` share this block BYTE-FOR-BYTE — see below. Sum 250.
	"caster": {"STR": 15.0, "DEX": 35.0, "CON": 55.0, "WIS": 55.0, "INT": 75.0, "CHA": 15.0},
	"aoe":    {"STR": 15.0, "DEX": 35.0, "CON": 55.0, "WIS": 55.0, "INT": 75.0, "CHA": 15.0},
}
const ARCH_SPEED := {"melee": 9.5, "ranged": 8.5, "caster": 7.5, "aoe": 7.5}
## `hold` resolves to `span - HOLD_REACH_REF` clamped to 0.9 x half-span (combat_tree `_hold_radius`)
## = ~176u of advance on this board, so a standoff line closes to a ~40u firefight rather than
## standing at its anchor. Melee pushes all the way in. Both are the postures those kits want.
const ARCH_POSTURE := {"melee": "push", "ranged": "hold", "caster": "hold", "aoe": "hold"}
const ORDER := ["melee", "ranged", "caster", "aoe"]

## ⚠️ `caster` IS POWER-MATCHED TO `aoe`, MOVE BY MOVE, AND THAT IS THE SHARPEST TEST IN THE FILE.
## Same stat block, same `magic` channel, same authored POWER to within the nearest available
## move — the ONLY difference is `target: allEnemies` vs `target: enemy`. Any win-rate gap between
## those two sides is the price of the AoE axis, isolated. Picking the caster kit alphabetically
## instead would have put a power difference on the axis and the result would have meant nothing.
const MATCH_CHANNEL := "magic"

var _fails := 0
var _moves: Array = []
var _aoe_names := {}      # move name -> true, for the allEnemies set
var _instant_names := {}  # move name -> true when its channel does NOT fly (no cast_done/proj_hit
						  #  double count — see _damage_split)


func _ready() -> void:
	_go()


func _canary(name: String, ok: bool, detail: String) -> void:
	if ok:
		print("  ok    CANARY %-26s %s" % [name, detail])
	else:
		_fails += 1
		print("  FAIL  CANARY %-26s %s" % [name, detail])


# ═══ STATISTICS ══════════════════════════════════════════════════════════════════════════════
# ⚠️ THE SIGN TEST, NOT A MEAN WITH A CI. CLAUDE.md's Balancing standard, and it was paid for:
# "a few fights swing 20-30s when they tip from timeout to a kill, and those outliers hide real
# effects." A win is a win; the exact binomial is the honest test of a paired win column.

## Two-sided exact binomial p for `k` successes in `n` trials against p=0.5.
static func sign_test_p(k: int, n: int) -> float:
	if n <= 0:
		return 1.0
	var lo: int = mini(k, n - k)
	var tail := 0.0
	var c := 1.0
	for i in range(0, lo + 1):
		if i > 0:
			c = c * float(n - i + 1) / float(i)
		tail += c
	return minf(1.0, 2.0 * tail * pow(0.5, float(n)))


static func _mean(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var s := 0.0
	for x in xs:
		s += float(x)
	return s / float(xs.size())


## Sample standard deviation (n-1). Reported beside every mean so no proportion in this file is
## quoted without its error band.
static func _sd(xs: Array) -> float:
	if xs.size() < 2:
		return 0.0
	var m := _mean(xs)
	var s := 0.0
	for x in xs:
		s += (float(x) - m) * (float(x) - m)
	return sqrt(s / float(xs.size() - 1))


## Standard error of the mean — the band to quote, not the sd.
static func _sem(xs: Array) -> float:
	if xs.size() < 2:
		return 0.0
	return _sd(xs) / sqrt(float(xs.size()))


# ═══ KIT SELECTION ═══════════════════════════════════════════════════════════════════════════

func _load_moves() -> void:
	_moves = JSON.parse_string(FileAccess.get_file_as_string("res://data/data.json"))["moves"]
	for m in _moves:
		if str(m.get("target", "enemy")) == "allEnemies":
			_aoe_names[str(m.name)] = true
		# A move whose channel is not in the projectile table resolves INSTANTLY at cast
		# completion (sim.gd `PROJECTILE_SPEED`), so its `cast_done` is the damage event. A
		# flying move emits `cast_done` at LAUNCH and `proj_hit` at ARRIVAL with the same number.
		if not (str(m.get("channel", "magic")) in ["ranged", "magic"]):
			_instant_names[str(m.name)] = true


## Deterministic pool slice, always name-sorted — no rng anywhere in roster construction.
func _pool(channel: String, aoe: bool, n: int) -> Array:
	var out: Array = _moves.filter(func(m):
		return str(m.get("channel", "")) == channel \
			and str(m.get("type", "")) == "damage" \
			and (str(m.get("target", "enemy")) == "allEnemies") == aoe)
	out.sort_custom(func(a, b): return str(a.name) < str(b.name))
	return out.slice(0, n)


## The five kit moves each archetype fields, by name. `caster` is derived FROM `aoe` by nearest
## authored power among unused single-target magic moves — see the MATCH_CHANNEL note.
func _kit_names(arch: String) -> Array:
	match arch:
		"melee":
			return _pool("melee", false, TEAM_SIZE).map(func(m): return str(m.name))
		"ranged":
			return _pool("ranged", false, TEAM_SIZE).map(func(m): return str(m.name))
		"aoe":
			return _pool(MATCH_CHANNEL, true, TEAM_SIZE).map(func(m): return str(m.name))
		"caster":
			var singles: Array = _moves.filter(func(m):
				return str(m.get("channel", "")) == MATCH_CHANNEL \
					and str(m.get("type", "")) == "damage" \
					and str(m.get("target", "enemy")) == "enemy")
			singles.sort_custom(func(a, b): return str(a.name) < str(b.name))
			var used := {}
			var out: Array = []
			for a in _pool(MATCH_CHANNEL, true, TEAM_SIZE):
				var want := float(a.get("power", 0))
				var best := ""
				var best_d := INF
				for s in singles:
					if used.has(str(s.name)):
						continue
					var d: float = absf(float(s.get("power", 0)) - want)
					if d < best_d:   # strict < with a name-sorted list = deterministic tiebreak
						best_d = d
						best = str(s.name)
				if best != "":
					used[best] = true
					out.append(best)
			return out
	assert(false, "unknown archetype " + arch)
	return []


# ═══ ROSTER ══════════════════════════════════════════════════════════════════════════════════

## `con_mult` is the C3 canary perturbation. It defaults to 1.0 and is a pure multiplier on data
## the sim reads — no branch in the sim, no second code path.
##
## ⚠️ `range_mult` USED TO LIVE HERE AND IT WAS REMOVED IN ROUND 24, NOT MOVED BY PREFERENCE.
## C1 scaled `entry.range` and called the result "aoe radius". That was true only while ONE
## NUMBER DID BOTH JOBS — `_resolve_aoe` used the cast range as the blast radius. Round 24
## separated them (`Sim.aoe_blast_radius`, seeded per LINE), so scaling `entry.range` now
## perturbs how far a caster THROWS, not how wide the burst is, and the canary read
## x0.25 = 1.63 ABOVE the unperturbed 1.47 — a shorter throw makes a caster close further and
## land in a tighter cluster. Real behaviour, wrong instrument. The knob C1 needs is
## `Sim.aoe_blast_scale` (see `_run`), which is exactly the quantity §2 reports.
func _side(arch: String, team: String, stat_mult: float = 1.0,
		con_mult: float = 1.0, tight: float = 1.0) -> Array:
	var slots: Array = Sp.deploy_positions(TEAM_SIZE, team)
	var off: Vector2 = Sp.ground_size(TEAM_SIZE) * 0.5   # corner frame -> the sim's centre frame
	var spd: float = Sp.slow_unit_speed(TEAM_SIZE) / SMALL_REF_SPEED
	var names: Array = _kit_names(arch)
	# `tight` < 1.0 squeezes the deploy band toward its own centre — the §2B spread sweep. It
	# changes ONLY the y of each slot; x, kits, stats and speeds are untouched.
	if tight != 1.0:
		var cy := 0.0
		for s in slots:
			cy += Vector2(s).y
		cy /= float(slots.size())
		for i in slots.size():
			var p: Vector2 = Vector2(slots[i])
			slots[i] = Vector2(p.x, cy + (p.y - cy) * tight)
	var out: Array = []
	for i in TEAM_SIZE:
		var stats: Dictionary = (ARCH_STATS[arch] as Dictionary).duplicate()
		for k in stats:
			stats[k] = float(stats[k]) * stat_mult
		stats["CON"] = float(stats["CON"]) * con_mult
		var kit: Array = Kit.build([names[i % names.size()]], _moves)
		out.append({
			"id": "%s%d" % [team.to_lower(), i], "team": team,
			"pos": Vector2(slots[i]) - off,
			"stats": stats, "speed": float(ARCH_SPEED[arch]) * spd,
			"kit": kit,
			"tactics": {"target_priority": "nearest", "positional": str(ARCH_POSTURE[arch])},
		})
	return out


func _run(seed_val: int, arch_a: String, arch_b: String, opts: Dictionary = {}) -> Dictionary:
	var us: Array = _side(arch_a, "A", float(opts.get("stat_a", 1.0)),
		float(opts.get("con_mult", 1.0)))
	us.append_array(_side(arch_b, "B", float(opts.get("stat_b", 1.0)),
		float(opts.get("con_mult", 1.0)), float(opts.get("tight_b", 1.0))))
	var g: Vector2 = Sp.ground_size(TEAM_SIZE)
	var sim = Sim.new()
	sim.setup(seed_val, us, g, OBSTACLES)
	# C1's seam. `Sim.aoe_blast_scale` defaults to 1.0, draws no rng and is read only by
	# `Sim.aoe_blast_radius` — the function §2's "radius ACTUALLY fielded" reports. Setting it
	# here perturbs the blast geometry with no sim edit and no second code path, which is what
	# `entry.range` used to do before the blast and the throw were separated.
	sim.aoe_blast_scale = float(opts.get("blast_mult", 1.0))
	var half: float = g.x * 0.5 - 8.0
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-half, 0), Vector2(half, 0))
	if not ok:
		sim.nav.free_rids()
		return {}
	var res: Dictionary = sim.run()
	sim.nav.free_rids()   # every discarded sim owes this — otherwise each fight leaks ~18 RIDs
	return res


# ═══ METRICS ═════════════════════════════════════════════════════════════════════════════════

## Every `aoe` burst in the fight, with the number it CAUGHT and the number it COULD have caught.
## ⚠️ THE DENOMINATOR IS LIVING ENEMIES AT THAT TICK, not team size. A burst that catches 2 of 2
## survivors is catching everything; scored against 5 it would read as a modest hit and the whole
## finding would be diluted by the back half of every fight.
func _aoe_bursts(res: Dictionary) -> Array:
	var team_of := {}
	if (res.frames as Array).is_empty():
		return []
	for u in res.frames[0].units:
		team_of[str(u.id)] = str(u.team)
	var out: Array = []
	for f in res.frames:
		var alive := {"A": 0, "B": 0}
		for u in f.units:
			if bool(u.alive):
				alive[str(u.team)] = int(alive[str(u.team)]) + 1
		for e in f.events:
			if str(e.get("kind", "")) != "aoe":
				continue
			var caster_team: String = str(team_of.get(str(e.get("from", "")), "A"))
			var foe_team: String = "B" if caster_team == "A" else "A"
			var foes: int = int(alive[foe_team])
			# ⚠️ THE ACTIONABLE NUMBER: how big would this burst have had to BE to catch 2 and 3.
			# `need2`/`need3` are the distances from the caster to the 2nd and 3rd nearest living
			# enemy. Compared against the pool's authored radii they say whether the geometry is
			# generous or stingy — a radius the pool cannot reach is a rule that never fires.
			var ds: Array = []
			var centre: Vector2 = Vector2(e.get("centre", Vector2.ZERO))
			var lo := INF
			var hi := -INF
			for u in f.units:
				if bool(u.alive) and str(u.team) == foe_team:
					ds.append(centre.distance_to(Vector2(u.pos)))
					lo = minf(lo, Vector2(u.pos).y)
					hi = maxf(hi, Vector2(u.pos).y)
			ds.sort()
			out.append({"caught": int(e.get("targets", 0)), "living": maxi(1, foes),
				"radius": float(e.get("radius", 0.0)), "move": str(e.get("move", "")),
				"falloff": float(e.get("falloff", 1.0)), "tick": int(f.tick),
				"need2": float(ds[1]) if ds.size() > 1 else NAN,
				"need3": float(ds[2]) if ds.size() > 2 else NAN,
				"need_all": float(ds[ds.size() - 1]) if not ds.is_empty() else NAN,
				"foe_span": (hi - lo) if not ds.is_empty() else NAN})
	return out


## Damage split by SOURCE KIND, counted so nothing is double counted.
## ⚠️ A FLYING SINGLE-TARGET MOVE EMITS ITS DAMAGE TWICE — `cast_done` at launch and `proj_hit`
## at arrival, same number (sim.gd #34). `_sweep_comps.gd` dodges this by reading HP deltas, which
## cannot attribute a hit to a MOVE; this section must attribute, so it counts `proj_hit` for
## flying moves and `cast_done` only for instant ones. An AoE burst never takes the projectile
## branch at all (a burst has no flight path), so its `cast_done` is always the real event.
func _damage_split(res: Dictionary) -> Dictionary:
	var aoe := 0.0
	var single := 0.0
	var basic := 0.0
	var bursts := 0
	for f in res.frames:
		for e in f.events:
			var k := str(e.get("kind", ""))
			var mv := str(e.get("move", ""))
			if k == "strike":
				basic += float(e.get("dmg", 0))
			elif k == "aoe":
				bursts += 1
			elif k == "proj_hit":
				single += float(e.get("dmg", 0))   # flying moves: arrival is the one true event
			elif k == "cast_done":
				if _aoe_names.has(mv):
					aoe += float(e.get("dmg", 0))
				elif _instant_names.has(mv):
					single += float(e.get("dmg", 0))
				# else: the launch half of a flying shot — already counted at proj_hit
	return {"aoe": aoe, "single": single, "basic": basic, "bursts": bursts,
		"total": aoe + single + basic}


## How the fight ENDS. `first_frac` is when first blood lands as a fraction of the whole fight;
## `collapse` is the seconds between the FIRST and LAST death — round 23's "six deaths in five
## seconds", given a number and an error band.
func _ending(res: Dictionary) -> Dictionary:
	var first := -1
	var last := -1
	var deaths := 0
	var ticks: int = int(res.ticks)
	for f in res.frames:
		for e in f.events:
			if str(e.get("kind", "")) == "death":
				deaths += 1
				last = int(f.tick)
				if first < 0:
					first = int(f.tick)
	return {
		"secs": float(ticks) * Sim.DT,
		"deaths": deaths,
		"first_frac": float(first) / maxf(1.0, float(ticks)) if first >= 0 else NAN,
		"first_secs": float(first) * Sim.DT if first >= 0 else NAN,
		"collapse": float(last - first) * Sim.DT if first >= 0 else NAN,
		"capped": 1 if ticks >= Sim.MAX_TICKS or not (str(res.winner) in ["A", "B"]) else 0,
		"winner": str(res.winner),
	}


## The height of one side's deploy line at tick 0 — the reason a burst catches what it catches.
func _deploy_band() -> float:
	var lo := INF
	var hi := -INF
	for p in Sp.deploy_positions(TEAM_SIZE, "A"):
		lo = minf(lo, Vector2(p).y)
		hi = maxf(hi, Vector2(p).y)
	return hi - lo


func _hash(res: Dictionary) -> String:
	return str(JSON.stringify(res.get("frames", [])).hash())


# ═══ THE RUN ═════════════════════════════════════════════════════════════════════════════════

func _seed_count() -> int:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--seeds="):
			return clampi(int(str(a).substr(8)), 1, SEEDS.size())
	return 3


func _quick() -> bool:
	return "--quick" in OS.get_cmdline_user_args()


func _go() -> void:
	_load_moves()
	var t0 := Time.get_ticks_msec()
	print("")
	print("SPATIAL BALANCE INSTRUMENT — board %.0fx%.0f, deploy separation %.1f, melee reach %.1f"
		% [Sp.ground_size(TEAM_SIZE).x, Sp.ground_size(TEAM_SIZE).y,
			Sp.deploy_separation(TEAM_SIZE), Sim.BASE_REACH])
	_census()
	var n_seeds := _seed_count()
	var fights: Array = []          # every fight run in §3, kept for §4
	if not _quick():
		fights = await _trade_table(n_seeds)
		_ending_report(fights)
		_aoe_report(fights)
		await _spread_sweep(n_seeds)
	await _canaries(n_seeds)
	print("")
	print("BALANCE PROBE %s — %d canaries failed, %.1fs wall"
		% ["OK" if _fails == 0 else "CANARY FAILURE", _fails, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit(1 if _fails > 0 else 0)


# ── §1 ───────────────────────────────────────────────────────────────────────────────────────

## ⚠️ STATIC ARITHMETIC, NO FIGHT. This section cannot be wrong about the sim because it only
## restates what `sim.gd:_entry_reach` computes: `min(authored_range x KIT_RANGE_LIFT, HARD_REACH_MAX)`
## where KIT_RANGE_LIFT completes kit.gd's partial x2.2 to the design's x8.8. The same number is
## the TARGETING radius and the radius EMITTED to the renderer — one number doing two jobs.
func _census() -> void:
	var lift: float = Kit.GEOMETRY_SCALE * Sim.KIT_RANGE_LIFT
	var sep: float = Sp.deploy_separation(TEAM_SIZE)
	var aoe: Array = _moves.filter(func(m): return str(m.get("target", "enemy")) == "allEnemies")
	# `aoe_blast_radius` is an INSTANCE method (it reads `aoe_blast_scale`, the C1 seam), so the
	# census needs a Sim to ask. This one is never `setup()` so it holds no rng and runs no fight.
	var _sim_ref = Sim.new()
	aoe.sort_custom(func(a, b): return float(a.get("range", 0)) > float(b.get("range", 0)))
	print("")
	print("§1  AOE GEOMETRY CENSUS — %d allEnemies moves; cast range = min(range x %.1f, %.1f)"
		% [aoe.size(), lift, Sp.HARD_REACH_MAX])
	print("    ⚠️ THIS HEADER SAID 'There is NO `area` field. The blast radius IS the cast range.'")
	print("       HALF OF THAT IS STILL TRUE. There is still no `area` field — route (a) was")
	print("       refused, because §2 measured 1.43 caught per burst where the pool is priced at")
	print("       three, so authoring one would have paid a cross-tree change to fix a direction")
	print("       the numbers do not support. But the two jobs ARE now separated: `cast r` is how")
	print("       far it is thrown, `blast r` is `Sim.aoe_blast_radius` — seeded per LINE, lifted")
	print("       by GEOMETRY_SCALE (a blast covers ground) not REACH_SCALE (which scales")
	print("       separations), and centred on the TARGET for channels that fly, on the CASTER")
	print("       for those that do not. §2's 'radius ACTUALLY fielded' is the blast column.")
	print("")
	print("    %-22s %-12s %6s %8s %8s %8s %7s   %s"
		% ["move", "line", "range", "cast r", "blast r", "blast/melee", "cast/sep", "channel"])
	print("    " + "-".repeat(100))
	var radii: Array = []
	for m in aoe:
		var r := float(m.get("range", 0.0))
		var live: float = minf(r * lift, Sp.HARD_REACH_MAX)
		var blast: float = _sim_ref.aoe_blast_radius(m)
		radii.append(blast)
		print("    %-22s %-12s %6.1f %8.1f %8.1f %7.1fx %6.1f%%   %s"
			% [str(m.name), str(m.get("line", "?")), r, live, blast, blast / Sim.BASE_REACH,
				100.0 * live / sep, str(m.get("channel", "?"))])
	radii.sort()
	print("")
	print("    live BLAST radius: min %.1f  median %.1f  max %.1f   (melee basic reaches %.1f)"
		% [radii.min(), radii[radii.size() / 2], radii.max(), Sim.BASE_REACH])
	print("    falloff per burst size:  " + " ".join(range(1, 6).map(func(n):
		return "%dx%.2f(tot %.2f)" % [n, Sim.aoe_falloff(n), Sim.aoe_falloff(n) * float(n)])))
	print("    ⚠️ The standing rule prices AoE AT THREE TARGETS: total x%.2f. At five it is x%.2f"
		% [Sim.aoe_falloff(3) * 3.0, Sim.aoe_falloff(5) * 5.0])


# ── §3 ───────────────────────────────────────────────────────────────────────────────────────

## The full grid, both orders, so side bias cancels inside every unordered pair.
func _trade_table(n_seeds: int) -> Array:
	var fights: Array = []
	print("")
	print("§3  ARCHETYPE TRADE — %d archetypes, both sides, %d seeds (%d fights). Equal stat totals (%.0f/body)."
		% [ORDER.size(), n_seeds, ORDER.size() * ORDER.size() * n_seeds, STAT_TOTAL])
	for arch in ORDER:
		var names: Array = _kit_names(arch)
		var pw: Array = []
		var rr: Array = []
		for n in names:
			for m in _moves:
				if str(m.name) == n:
					pw.append(float(m.get("power", 0)))
					rr.append(minf(float(m.get("range", 0)) * Kit.GEOMETRY_SCALE * Sim.KIT_RANGE_LIFT, Sp.HARD_REACH_MAX))
		print("    %-7s mean power %5.1f  mean reach %5.1f  kit: %s"
			% [arch, _mean(pw), _mean(rr), ", ".join(names)])
	print("    ⚠️ `caster` is POWER-MATCHED to `aoe` move by move — same stats, same channel,")
	print("       same power. The only difference is target: enemy vs allEnemies.")
	print("")
	for a in ORDER:
		for b in ORDER:
			for s in n_seeds:
				var res: Dictionary = await _run(int(SEEDS[s]), a, b)
				if res.is_empty():
					print("    ABORT: nav never became ready (%s vs %s seed %d)" % [a, b, int(SEEDS[s])])
					return fights
				var row: Dictionary = _ending(res)
				row["a"] = a
				row["b"] = b
				row["seed"] = int(SEEDS[s])
				row["dmg"] = _damage_split(res)
				row["bursts"] = _aoe_bursts(res)
				fights.append(row)
	# One row per UNORDERED pair; a pair's fights are the same seeds under both side assignments.
	print("    %-8s %-8s %5s %7s %7s   %-22s %s"
		% ["X", "Y", "n", "X wins", "p", "mean length (s)", "verdict"])
	print("    " + "-".repeat(86))
	for i in ORDER.size():
		for j in range(i, ORDER.size()):
			var x: String = ORDER[i]
			var y: String = ORDER[j]
			var wins := 0
			var n := 0
			var lens: Array = []
			for f in fights:
				var is_xy: bool = str(f.a) == x and str(f.b) == y
				var is_yx: bool = str(f.a) == y and str(f.b) == x
				if not (is_xy or is_yx):
					continue
				if x == y and not is_xy:
					continue
				n += 1
				lens.append(float(f.secs))
				if str(f.winner) == ("A" if is_xy else "B"):
					wins += 1
			if n == 0:
				continue
			var p: float = sign_test_p(wins, n)
			var verdict := "no call (p >= 0.10)"
			if x == y:
				verdict = "mirror — side bias check"
			elif p < 0.10:
				verdict = "%s FAVOURED (p=%.3f)" % [x if wins * 2 > n else y, p]
			print("    %-8s %-8s %5d %6d/%d %7.3f   %6.1f +/- %-13.1f %s"
				% [x, y, n, wins, n, p, _mean(lens), _sem(lens), verdict])
	print("    ⚠️ p is a two-sided EXACT binomial sign test. At n=%d the smallest reachable p is %.3f —"
		% [ORDER.size() * n_seeds * 2 - ORDER.size() * n_seeds, sign_test_p(0, n_seeds * 2)])
	print("       a clean sweep at low seed counts is the ONLY result that can clear 0.10. Raise --seeds")
	print("       before reading any 'no call' row as evidence of balance.")
	return fights


# ── §4 ───────────────────────────────────────────────────────────────────────────────────────

func _ending_report(fights: Array) -> void:
	print("")
	print("§4  ENDING SHAPE — n=%d fights. Round 23 measured this at n=1 and refused to tune on it." % fights.size())
	var resolved: Array = fights.filter(func(f): return int(f.capped) == 0)
	var secs: Array = resolved.map(func(f): return float(f.secs))
	var ff: Array = resolved.filter(func(f): return not is_nan(float(f.first_frac))).map(func(f): return float(f.first_frac))
	var fs: Array = resolved.filter(func(f): return not is_nan(float(f.first_secs))).map(func(f): return float(f.first_secs))
	var col: Array = resolved.filter(func(f): return not is_nan(float(f.collapse))).map(func(f): return float(f.collapse))
	var dth: Array = resolved.map(func(f): return float(f.deaths))
	print("    resolved            %d of %d  (%.0f%% reached a winner inside the %d-tick cap)"
		% [resolved.size(), fights.size(), 100.0 * float(resolved.size()) / maxf(1.0, float(fights.size())), Sim.MAX_TICKS])
	print("    fight length        %6.1fs +/- %.1f   (sd %.1f)" % [_mean(secs), _sem(secs), _sd(secs)])
	print("    first blood at      %6.1fs +/- %.1f   = %.0f%% +/- %.0f%% of the fight"
		% [_mean(fs), _sem(fs), 100.0 * _mean(ff), 100.0 * _sem(ff)])
	print("    collapse window     %6.1fs +/- %.1f   (first death -> last death)" % [_mean(col), _sem(col)])
	print("    deaths per fight    %6.1f  +/- %.1f" % [_mean(dth), _sem(dth)])
	print("    ⚠️ READ THESE TOGETHER. A high first-blood fraction with a short collapse window is")
	print("       the shape round 23 flagged: the fight is an approach, then everything dies at once.")
	# Per-archetype-pair length, so a single grinding matchup cannot masquerade as the norm.
	var byl := {}
	for f in resolved:
		var k := "%s vs %s" % [f.a, f.b]
		if not byl.has(k):
			byl[k] = []
		(byl[k] as Array).append(float(f.secs))
	var ks: Array = byl.keys()
	ks.sort()
	var worst := ""
	var worst_v := -1.0
	for k in ks:
		var m: float = _mean(byl[k])
		if m > worst_v:
			worst_v = m
			worst = str(k)
	print("    longest matchup     %s at %.1fs" % [worst, worst_v])


func _aoe_report(fights: Array) -> void:
	var bursts: Array = []
	for f in fights:
		bursts.append_array(f.bursts as Array)
	print("")
	print("§2  AOE IN FIGHT — %d bursts across %d fights" % [bursts.size(), fights.size()])
	if bursts.is_empty():
		print("    ⚠️ NO BURSTS AT ALL. Either no AoE reached a kit or no cast completed — this")
		print("       section is VACUOUS and any conclusion drawn from it is invented.")
		return
	var caught: Array = bursts.map(func(b): return float(b.caught))
	var frac: Array = bursts.map(func(b): return float(b.caught) / float(b.living))
	var hist := [0, 0, 0, 0, 0, 0]
	var all_in := 0
	for b in bursts:
		hist[clampi(int(b.caught), 0, 5)] += 1
		if int(b.caught) >= int(b.living):
			all_in += 1
	print("    targets caught per burst: mean %.2f +/- %.2f  (sd %.2f)" % [_mean(caught), _sem(caught), _sd(caught)])
	print("    catch fraction of LIVING enemies: %.0f%% +/- %.0f%%" % [100.0 * _mean(frac), 100.0 * _sem(frac)])
	print("    every living enemy caught: %d of %d bursts (%.0f%%)"
		% [all_in, bursts.size(), 100.0 * float(all_in) / float(bursts.size())])
	print("    histogram  0:%d  1:%d  2:%d  3:%d  4:%d  5:%d" % [hist[0], hist[1], hist[2], hist[3], hist[4], hist[5]])
	print("    share of bursts catching >= 3 (the audited case): %.0f%%"
		% [100.0 * float(hist[3] + hist[4] + hist[5]) / float(bursts.size())])
	# ⚠️ THE GEOMETRY BUDGET. This is the number a geometry change is judged against.
	var n2: Array = bursts.filter(func(b): return not is_nan(float(b.need2))).map(func(b): return float(b.need2))
	var n3: Array = bursts.filter(func(b): return not is_nan(float(b.need3))).map(func(b): return float(b.need3))
	var na: Array = bursts.filter(func(b): return not is_nan(float(b.need_all))).map(func(b): return float(b.need_all))
	var sp: Array = bursts.filter(func(b): return not is_nan(float(b.foe_span))).map(func(b): return float(b.foe_span))
	var used: Array = bursts.map(func(b): return float(b.radius))
	print("    radius ACTUALLY fielded  %6.1f +/- %.1f" % [_mean(used), _sem(used)])
	print("    radius NEEDED to catch 2 %6.1f +/- %.1f   to catch 3 %6.1f +/- %.1f   to catch all %6.1f +/- %.1f"
		% [_mean(n2), _sem(n2), _mean(n3), _sem(n3), _mean(na), _sem(na)])
	print("    enemy line span at burst %6.1f +/- %.1f  (deploy band is %.1f tall on a %.0f-deep board)"
		% [_mean(sp), _sem(sp), _deploy_band(), Sp.ground_size(TEAM_SIZE).y])
	print("    ⚠️ COMPARE THOSE TWO LINES BEFORE CONCLUDING ANYTHING ABOUT AoE. A burst radius")
	print("       below the 'needed to catch 3' figure means the pool is priced at three targets")
	print("       and delivering fewer — the OPPOSITE of the dominance the radius census suggests.")
	var aoe_d := 0.0
	var sin_d := 0.0
	var bas_d := 0.0
	for f in fights:
		aoe_d += float((f.dmg as Dictionary).aoe)
		sin_d += float((f.dmg as Dictionary).single)
		bas_d += float((f.dmg as Dictionary).basic)
	var tot: float = maxf(1.0, aoe_d + sin_d + bas_d)
	print("    damage by source: AoE casts %.0f%%   single-target casts %.0f%%   free attacks %.0f%%"
		% [100.0 * aoe_d / tot, 100.0 * sin_d / tot, 100.0 * bas_d / tot])
	print("    ⚠️ Damage is attributed by EVENT KIND, not HP delta: a flying single-target move")
	print("       emits its damage twice (cast_done at launch, proj_hit at arrival) and only the")
	print("       arrival is counted. DoT attrition and thorns belong to neither column and are")
	print("       therefore ABSENT from these three percentages — they do not sum to all damage.")


# ── §2B ──────────────────────────────────────────────────────────────────────────────────────

## ⚠️ THE DISCRIMINATOR FOR §2, AND THE REASON ITS HEADLINE NUMBER IS NOT WHAT ANYONE EXPECTED.
## A burst catching few bodies has TWO possible causes wanting opposite fixes: the radius is too
## small, or the enemy is too spread out to be caught by any radius the pool authors. This sweep
## squeezes the TARGET side's deploy band toward its own centre and leaves everything else — kits,
## radii, stats, seeds — byte-identical. If catch rises steeply as the enemy tightens, the radius
## is fine and the SPREAD is the governing variable; if it barely moves, the radius is the problem.
func _spread_sweep(n_seeds: int) -> void:
	print("")
	print("§2B AOE CATCH vs ENEMY SPREAD — the target side's deploy band squeezed, nothing else changed.")
	print("    %8s %10s %14s %14s" % ["band", "targets/burst", "catch fraction", "bursts"])
	print("    " + "-".repeat(52))
	for tight in [1.0, 0.6, 0.3, 0.12]:
		var caught: Array = []
		var frac: Array = []
		for s in n_seeds:
			for foe in ["melee", "ranged"]:
				var r: Dictionary = await _run(int(SEEDS[s]), "aoe", foe, {"tight_b": tight})
				for b in _aoe_bursts(r):
					caught.append(float(b.caught))
					frac.append(float(b.caught) / float(b.living))
		print("    %7.0fu %10.2f %13.0f%% %14d"
			% [_deploy_band() * tight, _mean(caught), 100.0 * _mean(frac), caught.size()])


# ── §5 CANARIES ──────────────────────────────────────────────────────────────────────────────

func _canaries(n_seeds: int) -> void:
	print("")
	print("§5  LIVENESS CANARIES — each perturbs the exact quantity above it and must see it move.")
	var seeds: int = maxi(2, n_seeds)

	# C1 — AOE BLAST RADIUS, via `Sim.aoe_blast_scale` (see `_run`). Swept in BOTH directions and
	# both are printed, but ONLY THE WIDENING ARM GATES. The burst event exists only when the
	# burst caught at least one body — an empty burst fizzles and emits nothing — so shrinking
	# CENSORS the low end and the mean is floored near 1.00 however small the ring gets. Widening
	# is the uncensored direction, so it is the one that can distinguish a live instrument from a
	# dead one. A shrink arm that RISES is not a failure; it is the caster closing further.
	var by_mult := {}
	for mult in [0.25, 1.0, 2.5]:
		var acc: Array = []
		for s in seeds:
			for pair in [["aoe", "melee"], ["aoe", "ranged"]]:
				var r: Dictionary = await _run(int(SEEDS[s]), str(pair[0]), str(pair[1]), {"blast_mult": mult})
				for b in _aoe_bursts(r):
					acc.append(float(b.caught))
		by_mult[mult] = acc
	var c_lo: float = _mean(by_mult[0.25])
	var c_mid: float = _mean(by_mult[1.0])
	var c_hi: float = _mean(by_mult[2.5])
	_canary("C1 aoe blast radius", c_hi > c_mid,
		"targets/burst x0.25=%.2f  x1=%.2f  x2.5=%.2f  (only x2.5 > x1 gates — shrink is censored)"
			% [c_lo, c_mid, c_hi])

	# C2 — TRADE TABLE. A mirror with one side at +25% stats: the sign test must call it.
	var wins := 0
	var n := 0
	for s in seeds:
		for arch in ["melee", "caster"]:
			var res: Dictionary = await _run(int(SEEDS[s]), arch, arch, {"stat_a": 1.25})
			if res.is_empty():
				continue
			n += 1
			if str(res.get("winner", "")) == "A":
				wins += 1
	var p: float = sign_test_p(wins, n)
	_canary("C2 trade detector", n > 0 and wins * 2 > n and p < 0.10,
		"+25%% stats wins %d/%d, sign-test p=%.3f (needs p<0.10)" % [wins, n, p])

	# C3 — ENDING. Same fights with CON x0.55: smaller HP pools must end sooner.
	var base_s: Array = []
	var thin_s: Array = []
	for s in seeds:
		for pair in [["melee", "melee"], ["caster", "melee"]]:
			var r0: Dictionary = await _run(int(SEEDS[s]), str(pair[0]), str(pair[1]))
			var r1: Dictionary = await _run(int(SEEDS[s]), str(pair[0]), str(pair[1]), {"con_mult": 0.55})
			base_s.append(float(_ending(r0).secs))
			thin_s.append(float(_ending(r1).secs))
	_canary("C3 ending detector", _mean(thin_s) < _mean(base_s) - 0.5,
		"fight length %.1fs -> %.1fs at CON x0.55" % [_mean(base_s), _mean(thin_s)])

	# C4 — DETERMINISM (in-process twin; the cross-process gate is _probe_arena_switch).
	var d0: Dictionary = await _run(int(SEEDS[0]), "aoe", "melee")
	var d1: Dictionary = await _run(int(SEEDS[0]), "aoe", "melee")
	_canary("C4 determinism", _hash(d0) == _hash(d1),
		"twin frame hash %s (in-process only — NOT the cross-process gate)" % _hash(d0))
