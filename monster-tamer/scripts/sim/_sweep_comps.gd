## THE COMPOSITION SWEEP — the balance harness the rewritten sim has never had.
##
## WHY IT EXISTS: the rewritten stack has a QUALITY probe (does a fight resolve, is it legible,
## does anything teleport) and a MECHANICS probe (does each layer fire), but nothing that says
## whether the archetypes are in a healthy relationship with each other. The one balance finding
## on record was a side effect of building a demo roster — a MIRROR sustain comp grinding to
## 1345 ticks near the 1800 cap (docs/COMBAT_SPATIAL_LOG.md, 2026-08-08). A finding that
## expensive should not depend on somebody happening to notice it while doing something else.
##
## WHAT IT DOES: four archetypes — SUSTAIN, PRESSURE, CONTROL, BALANCED — each five-a-side, on
## REAL authored kits from data.json (kit.gd builds them; a retuned move changes this sweep
## without an edit here). Every archetype fights every archetype, mirrors included, over several
## seeds, and the run prints one row per matchup: mean fight length, win rate, deaths, events per
## second, damage and healing per second, and the healers' mana floor.
##
## Run: godot --headless --path . res://scenes/_sweep_comps.tscn
##      godot --headless --path . res://scenes/_sweep_comps.tscn -- --seeds=5
## Exit code 0 always unless a fight fails to build — this is an INSTRUMENT, not a gate. The
## gate is _probe_sim_quality.gd, which pins the invariants this instrument informs.
##
## ⚠️ DETERMINISM: the sweep draws no rng of its own. Every fight is `Sim.setup(seed, ...)` with
## a seed from the fixed SEEDS list, so the whole table is reproducible run to run; two runs of
## this file print byte-identical numbers or something in the sim moved.
extends Node3D

const Sim = preload("res://scripts/sim/sim.gd")
const Kit = preload("res://scripts/sim/kit.gd")

const GROUND := Vector2(110, 62)
const OBSTACLES := [{"rect": Rect2(-4, -4, 8, 8)}]  # central pillar — same board as the probes
const SEEDS := [101, 2027, 31337, 44449, 5150]      # the first N are used; N = --seeds (default 3)
const DEPLOY_X := 38.0
const ROW_SPACING := 7.0

## Role stat blocks. Deliberately CLEAN archetypes rather than species draws: the sweep is asking
## about the SHAPE of a composition, and a species roll would put noise on the axis under test.
const ROLE_STATS := {
	"tank":    {"STR": 55.0, "DEX": 30.0, "CON": 80.0, "WIS": 30.0, "INT": 15.0, "CHA": 25.0},
	"bruiser": {"STR": 75.0, "DEX": 55.0, "CON": 50.0, "WIS": 20.0, "INT": 15.0, "CHA": 20.0},
	"diver":   {"STR": 75.0, "DEX": 70.0, "CON": 40.0, "WIS": 20.0, "INT": 15.0, "CHA": 20.0},
	"caster":  {"STR": 15.0, "DEX": 35.0, "CON": 40.0, "WIS": 50.0, "INT": 80.0, "CHA": 25.0},
	"healer":  {"STR": 12.0, "DEX": 30.0, "CON": 60.0, "WIS": 80.0, "INT": 30.0, "CHA": 55.0},
	"control": {"STR": 20.0, "DEX": 45.0, "CON": 45.0, "WIS": 75.0, "INT": 55.0, "CHA": 65.0},
}

## THE FOUR ARCHETYPES, five bodies each, in deploy order (row y = -14, -7, 0, 7, 14).
## `kick: true` appends the synthetic interrupt (a class feature, not one of the 141 moves).
##
## ⚠️ SUSTAIN's shape is the MEASURED one from the log: two tanks, two healers, thorns and wards
## on both. It is here to reproduce the 1345-tick grind, not to be fair. Healers sit in the
## MIDDLE rows on purpose — Mend's reach is ~18 world units and a back-row healer drifts out of
## range of its own front line (the vacuity trap _probe_sim_quality.gd's sustain comp already
## paid for once).
const ARCHETYPES := {
	"sustain": [
		{"role": "tank",   "moves": ["Taunt", "Barbed Carapace", "Bastion"],
			"tac": {"target_priority": "nearest", "positional": "hold", "when_hurt": "fight_on"}},
		{"role": "tank",   "moves": ["Interpose", "Retaliate"],
			"tac": {"target_priority": "nearest", "positional": "hold", "when_hurt": "fight_on"}},
		{"role": "healer", "moves": ["Mend", "Clarity"],
			"tac": {"target_priority": "nearest", "positional": "hold"}},
		{"role": "healer", "moves": ["Renewal", "Ward Against Ruin"],
			"tac": {"target_priority": "nearest", "positional": "hold"}},
		{"role": "caster", "moves": ["Ember", "Inferno"],
			"tac": {"target_priority": "weakest", "positional": "hold"}},
	],
	"pressure": [
		{"role": "bruiser", "moves": ["Rend", "Bonebreaker"],
			"tac": {"target_priority": "nearest", "positional": "push"}},
		{"role": "diver",   "moves": [], "kick": true,
			"tac": {"target_priority": "healers", "positional": "dive"}},
		{"role": "diver",   "moves": [], "kick": true,
			"tac": {"target_priority": "healers", "positional": "dive"}},
		{"role": "caster",  "moves": ["Cleave", "Arcane Bomb"],
			"tac": {"target_priority": "weakest", "positional": "wings", "wing_side": 1}},
		{"role": "diver",   "moves": [], "kick": true,
			"tac": {"target_priority": "casters", "positional": "push"}},
	],
	"control": [
		{"role": "tank",    "moves": ["Taunt", "Barricade"],
			"tac": {"target_priority": "nearest", "positional": "push"}},
		{"role": "control", "moves": ["Hush", "Dread Whisper"],
			"tac": {"target_priority": "healers", "positional": "hold"}},
		{"role": "control", "moves": ["Lullaby", "Dirge"],
			"tac": {"target_priority": "nearest", "positional": "hold"}},
		{"role": "caster",  "moves": ["Seismic Crush", "Fracturing Stones"],
			"tac": {"target_priority": "weakest", "positional": "hold"}},
		{"role": "diver",   "moves": [], "kick": true,
			"tac": {"target_priority": "casters", "positional": "push"}},
	],
	"balanced": [
		{"role": "tank",    "moves": ["Taunt", "Bastion"],
			"tac": {"target_priority": "nearest", "positional": "push"}},
		{"role": "healer",  "moves": ["Mend", "Clarity"],
			"tac": {"target_priority": "nearest", "positional": "hold"}},
		{"role": "caster",  "moves": ["Inferno", "Cleave"],
			"tac": {"target_priority": "weakest", "positional": "wings", "wing_side": 1}},
		{"role": "diver",   "moves": [], "kick": true,
			"tac": {"target_priority": "healers", "positional": "dive"}},
		{"role": "bruiser", "moves": ["Rend"],
			"tac": {"target_priority": "nearest", "positional": "push"}},
	],
}

const ORDER := ["sustain", "pressure", "control", "balanced"]

var _moves: Array = []
var _rows: Array = []


func _ready() -> void:
	_go()


func _seed_count() -> int:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--seeds="):
			return clampi(int(str(a).substr(8)), 1, SEEDS.size())
	return 3


## ---- roster construction ------------------------------------------------------------------

func _side(arch: String, team: String) -> Array:
	var spec: Array = ARCHETYPES[arch]
	var out: Array = []
	for i in spec.size():
		var role: Dictionary = spec[i]
		var stats: Dictionary = (ROLE_STATS[str(role.role)] as Dictionary).duplicate()
		var kit: Array = Kit.build(role.moves, _moves) if not (role.moves as Array).is_empty() else []
		if bool(role.get("kick", false)):
			kit.append(Kit.kick())
		var tac: Dictionary = (role.tac as Dictionary).duplicate()
		if team == "B" and tac.has("wing_side"):
			tac["wing_side"] = -int(tac["wing_side"])   # mirror the flank so wings do not collide
		var x: float = -DEPLOY_X if team == "A" else DEPLOY_X
		out.append({
			"id": "%s%d" % [team.to_lower(), i], "team": team,
			"pos": Vector2(x, -14.0 + ROW_SPACING * i),
			"stats": stats, "speed": 7.0 + float(stats["DEX"]) * 0.03,
			"kit": kit, "tactics": tac,
		})
	return out


func _run_fight(seed_val: int, arch_a: String, arch_b: String) -> Dictionary:
	var us: Array = _side(arch_a, "A")
	us.append_array(_side(arch_b, "B"))
	var sim = Sim.new()
	sim.setup(seed_val, us, GROUND, OBSTACLES)
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-DEPLOY_X, 0), Vector2(DEPLOY_X, 0))
	if not ok:
		sim.nav.free_rids()
		return {}
	var res: Dictionary = sim.run()
	sim.nav.free_rids()   # every discarded sim owes this — otherwise each fight leaks ~18 RIDs
	return res


## ---- per-fight metrics --------------------------------------------------------------------

## Damage and healing are read as HP DELTAS off the frame stream, never by summing event
## payloads. ⚠️ That is deliberate: a projectile emits `cast_done` with its damage at LAUNCH and
## `proj_hit` with the same damage at ARRIVAL (sim.gd #34), so an event-sum double-counts every
## ranged hit. HP deltas cannot double-count, and they also pick up DoT attrition and thorns
## reflect, which no single event kind covers.
func _fight_metrics(res: Dictionary) -> Dictionary:
	var frames: Array = res.frames
	var ticks: int = int(res.ticks)
	var dmg := 0.0
	var heal := 0.0
	var deaths := 0
	var events := 0
	var soaked := 0.0
	var healer_ids := {}
	for i in frames.size():
		var f: Dictionary = frames[i]
		events += (f.events as Array).size()
		for e in f.events:
			match str(e.kind):
				"death":
					deaths += 1
				"ward_soak":
					soaked += float(e.get("amount", 0))
				"heal":
					healer_ids[str(e.get("from", ""))] = true
		if i == 0:
			continue
		var prev: Array = frames[i - 1].units
		var cur: Array = f.units
		for j in cur.size():
			var d: float = float(prev[j].hp) - float(cur[j].hp)
			if d > 0.0:
				dmg += d
			elif d < 0.0:
				heal += -d
	# ENGAGEMENT — the share of ticks where the two sides are actually within melee reach of each
	# other. ⚠️ This metric was ADDED after the first sweep, because the table's stall rows split
	# into two causes and mean damage alone could not tell them apart: a comp that heals through
	# the damage looks the same in `ticks` as a comp that never closes the gap. This column
	# separates them.
	var engaged := 0
	for f in frames:
		var closest := INF
		for i in f.units.size():
			var ua: Dictionary = f.units[i]
			if not bool(ua.alive) or str(ua.team) != "A":
				continue
			for j in f.units.size():
				var ub: Dictionary = f.units[j]
				if bool(ub.alive) and str(ub.team) == "B":
					closest = minf(closest, Vector2(ua.pos).distance_to(Vector2(ub.pos)))
		if closest <= Sim.BASE_REACH:
			engaged += 1
	# Healer mana floor: the lowest mp fraction any unit that ACTUALLY HEALED ever reached.
	# This is the "do healers run dry?" question, asked of the fight rather than the design doc.
	var mp_floor := 1.0
	if not healer_ids.is_empty():
		for f in frames:
			for u in f.units:
				if bool(u.alive) and healer_ids.has(str(u.id)) and float(u.max_mp) > 0.0:
					mp_floor = minf(mp_floor, float(u.mp) / float(u.max_mp))
	var secs: float = maxf(0.1, float(ticks) * Sim.DT)
	# The dampening the fight actually ENDED under (sim.gd's sustain brake). 1.00 means the
	# matchup resolved inside the grace window and the brake never touched it — which is the
	# result wanted for every healthy matchup in the table.
	var damp_end: float = float(frames[frames.size() - 1].get("dampening", 1.0)) if not frames.is_empty() else 1.0
	return {
		"ticks": ticks, "winner": str(res.winner), "deaths": deaths,
		"eps": float(events) / secs, "dps": dmg / secs, "hps": heal / secs,
		"soak": soaked, "mp_floor": mp_floor, "damp": damp_end,
		"engaged": float(engaged) / maxf(1.0, float(frames.size())),
		"capped": 1 if ticks >= Sim.MAX_TICKS or not (str(res.winner) in ["A", "B"]) else 0,
	}


func _mean(rows: Array, key: String) -> float:
	var s := 0.0
	for r in rows:
		s += float(r[key])
	return s / maxf(1.0, float(rows.size()))


## ---- the run ------------------------------------------------------------------------------

func _go() -> void:
	_moves = JSON.parse_string(FileAccess.get_file_as_string("res://data/data.json"))["moves"]
	var n_seeds := _seed_count()
	var t0 := Time.get_ticks_msec()
	var aborted := false
	for a in ORDER:
		for b in ORDER:
			var fights: Array = []
			for s in n_seeds:
				var res: Dictionary = await _run_fight(int(SEEDS[s]), a, b)
				if res.is_empty():
					print("  ABORT: nav never became ready for %s vs %s seed %d" % [a, b, int(SEEDS[s])])
					aborted = true
					break
				fights.append(_fight_metrics(res))
			if aborted:
				break
			var a_wins := 0
			for f in fights:
				if str(f.winner) == "A":
					a_wins += 1
			_rows.append({
				"a": a, "b": b, "n": fights.size(),
				"ticks": _mean(fights, "ticks"), "awin": float(a_wins) / float(fights.size()),
				"deaths": _mean(fights, "deaths"), "eps": _mean(fights, "eps"),
				"dps": _mean(fights, "dps"), "hps": _mean(fights, "hps"),
				"mp_floor": _mean(fights, "mp_floor"), "capped": _mean(fights, "capped"),
				"damp": _mean(fights, "damp"), "engaged": _mean(fights, "engaged"),
				"lengths": fights.map(func(f): return int(f.ticks)),
			})
		if aborted:
			break
	_print_table(n_seeds, Time.get_ticks_msec() - t0)
	get_tree().quit(1 if aborted else 0)


func _print_table(n_seeds: int, wall_ms: int) -> void:
	print("")
	print("COMPOSITION SWEEP — %d archetypes x %d, %d seeds each (%d fights, %.1fs wall)"
		% [ORDER.size(), ORDER.size(), n_seeds, _rows.size() * n_seeds, wall_ms / 1000.0])
	print("  ticks = mean fight length (x0.1 = seconds, cap %d) | A win = share won by the LEFT comp" % Sim.MAX_TICKS)
	print("  dmg/s, heal/s = HP moved per second across both sides | ev/s = events per second")
	print("  mp = lowest mana fraction any healer reached (1.00 = never spent below full)")
	print("  damp = dampening (sim.gd's sustain brake) at the final tick; 1.00 = never bit")
	print("  eng% = share of ticks the two sides were within melee reach — a LOW value on a long")
	print("         fight means the sides never closed, which is a POSTURE stall, not a heal stall")
	print("")
	print("  %-9s %-9s %7s %7s %6s %6s %7s %7s %6s %6s %6s %6s  %s"
		% ["A comp", "B comp", "ticks", "sec", "A win", "deaths", "dmg/s", "heal/s", "ev/s", "mp", "damp", "eng%", "lengths"])
	print("  " + "-".repeat(118))
	for r in _rows:
		var flag := "  <-- AT CAP" if float(r.capped) > 0.0 else ""
		print("  %-9s %-9s %7.0f %7.1f %5.0f%% %6.1f %7.1f %7.1f %6.1f %6.2f %6.2f %5.0f%%  %s%s"
			% [r.a, r.b, float(r.ticks), float(r.ticks) * Sim.DT, float(r.awin) * 100.0,
				float(r.deaths), float(r.dps), float(r.hps), float(r.eps),
				float(r.mp_floor), float(r.damp), float(r.engaged) * 100.0, str(r.lengths), flag])
	print("")
	# The two summary reads the table exists to answer.
	var mirrors: Array = _rows.filter(func(r): return str(r.a) == str(r.b))
	print("  MIRRORS (the stalemate risk — a comp against itself):")
	for r in mirrors:
		print("    %-9s %6.0f ticks (%.0fs)  heal/dmg %.2f  deaths %.1f  engaged %.0f%%"
			% [r.a, float(r.ticks), float(r.ticks) * Sim.DT,
				float(r.hps) / maxf(0.001, float(r.dps)), float(r.deaths), float(r.engaged) * 100.0])
	var slow: Array = _rows.filter(func(r): return float(r.ticks) >= 900.0)
	print("  MATCHUPS OVER 90s: %d of %d" % [slow.size(), _rows.size()])
	for r in slow:
		print("    %s vs %s — %.0f ticks" % [r.a, r.b, float(r.ticks)])
	print("SWEEP DONE")
