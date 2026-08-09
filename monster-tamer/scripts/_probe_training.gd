## THE TRAINING DECISION PROBE — is the week a DECISION, or an obvious click?
##
## CLAUDE.md: "Training and breeding are STRATEGY, NOT MAINTENANCE. If a training week is an
## obvious click, it has failed." That is a measurable claim, and this is the instrument.
##
## Run:
##   P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_training.tscn
##
## Ten measurements. 1–6 are the original instrument; 7–10 were added in round 14 to answer the
## question the first six could not — §5 proved the optimal drill MOVES (94 switches in 120 weeks)
## without ever asking whether FOLLOWING it is worth anything.
##   1. CAREER BUDGET — total stat points a realistic monster can bank over a full career under
##      the best policy, vs the 6 x Apex-cap it would need to max EVERY stat. CLAUDE.md records
##      ~7,373 vs 6,600 from the TypeScript build; this measures the GODOT number.
##   2. POLICY DOMINANCE — every drill family run as a fixed policy over the same career, same
##      seeds. If one line is strictly best at every horizon, the choice is not a choice.
##   3. PER-WEEK SPREAD — the value of each of the 30 drills for ONE monster in ONE state. A flat
##      spread means the card the player is reading tells them nothing.
##   4. PREVIEW/APPLY LOCK-STEP — the RNG-discipline invariant, incl. the food path.
##   5. DECISION SURFACE — does the optimal drill move as the build develops.
##   6. SAFETY — a deliberate specialist must still be able to reach the ceiling.
##   7. THE PRICE OF SHAPE — is it the focus multiplier or the per-stat CEILING? (It was the
##      ceiling: 27 of ~30 points. `docs/SHAPE_DIAGNOSIS.md` §3 attributes it to the multiplier.)
##   8. WHAT SHAPE BUYS — kit reach at a sum-preserving reshape. The `learnLevel` gate is the
##      mechanism SHAPE_DIAGNOSIS §2 measured at 5.50x, so it is the honest proxy for fight value.
##   9. THE OPEN TARGET — does training toward a shape beat training the lowest stat.
##  10. BLOODLINE POTENTIAL — a standing tripwire on the one thing breeding sells, which had no
##      shipped caller at all until round 11.
extends Node

const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const WeekLib = preload("res://scripts/week.gd")

const STATS := ["STR", "DEX", "CON", "WIS", "INT", "CHA"]
const APEX_CAP := 1100.0

var _fail := 0
var _checks := 0
## Open acceptance targets — counted and printed, but they do NOT fail the run. See `_target()`.
var _targets_open := 0
var _targets := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fail += 1
	print("  %s %s" % ["[ok]  " if cond else "[FAIL]", label])


## ⚠️ AN OPEN ACCEPTANCE TARGET, NOT A REGRESSION CHECK — and the distinction is deliberate.
## §9's target ("training toward a shape must beat training the lowest stat") is FALSE on today's
## build and cannot be made true from this file alone: the fight-side half is
## `docs/SHAPE_DIAGNOSIS.md` §5 BUILDER B, in `career.gd`/`roster.gd`, which this workstream does
## not own. Asserting it as a normal check would leave the probe permanently red and hide a real
## regression in the six checks that ARE live; printing it as prose would let it be skimmed and
## forgotten, which is exactly how this project accumulates authored-but-unreached systems.
## So it is a THIRD state: loud, counted, named, and excluded from the exit code.
func _target(cond: bool, label: String) -> void:
	_targets += 1
	if not cond:
		_targets_open += 1
	print("  %s %s" % ["[met] " if cond else "[OPEN]", label])


func _make(id: String, sp_id: String = "") -> Object:
	var sid := sp_id
	if sid == "":
		sid = str(GameData.species_by_id.keys()[0])
	var sp: Dictionary = GameData.species_by_id[sid]
	var mi = MonsterInstanceScript.new()
	mi.id = id
	mi.species_id = sid
	mi.species_name = str(sp["name"])
	mi.body = str(sp["body"])
	mi.favourite_food = "meat"
	mi.hated_food = "fruit"
	mi.happiness = 5
	mi.stamina = 100.0
	mi.age_weeks = 48
	mi.lifespan_years = 8.0
	for stat in STATS:
		mi.stats[stat] = float(sp["base"].get(stat, 10.0))
	mi.recompute_class()
	mi.recompute_pools()
	mi.hp = mi.max_hp
	mi.mp = mi.max_mp
	return mi


func _total(mi) -> float:
	var t := 0.0
	for s in STATS:
		t += float(mi.stats[s])
	return t


## Net points a drill is WORTH this week for this monster: sum of the applied deltas (the
## paired malus already counted), measured by running the real tick on a preview clone.
func _net_of(mi, drill_id: String, cap: float) -> float:
	var p: Dictionary = WeekLib.preview_week(mi, {"kind": "train", "drillId": drill_id},
		1000, 0, "meat", false, 10, cap, "Wood")
	var n := 0.0
	for s in p["statDeltas"]:
		n += float(p["statDeltas"][s])
	return n


## Run a full career under a fixed policy. `family` == "" means greedy-over-everything.
## Rests whenever the stamina malus would bite below `rest_below`.
func _run_career(seed_id: String, family: String, rest_below: float, cap: float) -> Dictionary:
	var mi = _make(seed_id)
	var start := _total(mi)
	var weeks := 0
	var trained := 0
	while not mi.retired and weeks < 400:
		weeks += 1
		# feed: the cheapest happiness-positive option available every week (a well-run stable)
		mi.fed_this_week = false
		if mi.stamina < rest_below:
			WeekLib.apply_week(mi, {"kind": "rest"}, 100000, 0, "meat", false, 10, cap, "Wood")
			continue
		var best_id := ""
		var best_net := -9999.0
		for d in WeekLib.DRILLS:
			if family != "" and str(d["kind"]) != family:
				continue
			var net := _net_of(mi, str(d["id"]), cap)
			if net > best_net:
				best_net = net
				best_id = str(d["id"])
		if best_id == "":
			break
		WeekLib.apply_week(mi, {"kind": "train", "drillId": best_id}, 100000, 0, "meat", false, 10,
			cap, "Wood")
		trained += 1
	var maxed := 0
	for s in STATS:
		if float(mi.stats[s]) >= cap - 0.5:
			maxed += 1
	return {
		"gained": _total(mi) - start, "weeks": weeks, "trained": trained,
		"maxed": maxed, "total": _total(mi),
	}


# =============================================================================
# THE SHAPE INSTRUMENTS (added round 14) — the brief's item 4: measure the VALUE of following
# the optimum, not whether the optimum moves. §5 already proved it moves (94 switches in 120
# weeks); what nobody had measured is whether following it BUYS anything.
# =============================================================================

## The two stats this monster is genuinely built to train — highest species/body aptitude first.
## This is what "advanced training knowledge" means in the vision's own words: the player who has
## learned the species knows which two stats it pays to commit to. Ties break on stat name so the
## answer is deterministic.
func _apt_pair(mi) -> Array:
	var ranked: Array = STATS.duplicate()
	ranked.sort_custom(func(a, b):
		var ba: float = WeekLib.stat_training_bonus(mi, str(a))
		var bb: float = WeekLib.stat_training_bonus(mi, str(b))
		if absf(ba - bb) > 0.0001:
			return ba > bb
		return str(a) < str(b))
	return [str(ranked[0]), str(ranked[1])]


## The drill that pays the most raw points into `stat` — always the extreme tier (+24/−4/−4).
func _push_drill(stat: String) -> String:
	return "x" + stat.to_lower()


## One career under a NAMED policy, so the arms differ in the training brain and nothing else.
##   "greedy" — the drill with the best net this week (what §2/§5 already measure)
##   "lowest" — biggest drill on the LOWEST stat. The naive rule the brief is about.
##   "shape"  — biggest drill on the aptitude pair, primary until it leads the secondary by the
##              archetype's own 1.35:1.15, then the secondary. Falls through to the third-best
##              aptitude when the pair is capped (a shape player does not then flatten the body).
func _run_policy(seed_id: String, policy: String, cap: float) -> Dictionary:
	var mi = _make(seed_id)
	var start := _total(mi)
	var pair := _apt_pair(mi)
	var weeks := 0
	while not mi.retired and weeks < 400:
		weeks += 1
		mi.fed_this_week = false
		if mi.stamina < 30.0:
			WeekLib.apply_week(mi, {"kind": "rest"}, 100000, 0, "meat", false, 10, cap, "Wood")
			continue
		var pick := ""
		if policy == "greedy":
			var best_net := -9999.0
			for d in WeekLib.DRILLS:
				var net := _net_of(mi, str(d["id"]), cap)
				if net > best_net:
					best_net = net
					pick = str(d["id"])
		elif policy == "lowest":
			var lo_stat := STATS[0]
			for s in STATS:
				if float(mi.stats[s]) < float(mi.stats[lo_stat]):
					lo_stat = s
			pick = _push_drill(lo_stat)
		else:  # shape
			var own_cap := WeekLib.stat_cap_for(mi, cap)
			var pri: float = float(mi.stats[pair[0]])
			var sec: float = float(mi.stats[pair[1]])
			var want := ""
			if pri < own_cap - 0.5 and (sec >= own_cap - 0.5 or pri < sec * (1.35 / 1.15)):
				want = pair[0]
			elif sec < own_cap - 0.5:
				want = pair[1]
			elif pri < own_cap - 0.5:
				want = pair[0]
			else:
				var third := ""
				var third_s := -9999.0
				for s in STATS:
					if pair.has(s) or float(mi.stats[s]) >= own_cap - 0.5:
						continue
					var sc: float = WeekLib.stat_training_bonus(mi, s)
					if sc > third_s:
						third_s = sc
						third = s
				if third == "":
					break
				want = third
			pick = _push_drill(want)
		WeekLib.apply_week(mi, {"kind": "train", "drillId": pick}, 100000, 0, "meat", false, 10,
			cap, "Wood")
	return {"mi": mi, "gained": _total(mi) - start, "total": _total(mi), "weeks": weeks}


func _spread(mi) -> float:
	var lo := 1e9
	var hi := -1e9
	var sum := 0.0
	for s in STATS:
		var v := float(mi.stats[s])
		lo = minf(lo, v); hi = maxf(hi, v); sum += v
	return (hi - lo) / maxf(1.0, sum / 6.0)


## What KIT this stat vector can actually field. `docs/SHAPE_DIAGNOSIS.md` §2 measured that kit
## alignment — not stat spread — is the live fight variable (5.50x at a byte-identical stat
## vector), and its mechanism is `monster_instance.gd:assign_moveset`'s `learnLevel` gate. So the
## honest proxy for "what did this shape BUY" is the reach of the kit it unlocks, and it is
## computable here without touching a single sim file.
func _kit_reach(mi) -> Dictionary:
	mi.recompute_class()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(mi.id))
	mi.assign_moveset(rng)
	var top := 0.0
	var sum := 0.0
	for mv in mi.moveset:
		if mv is Dictionary:
			var ll := float(mv.get("learnLevel", 0.0))
			top = maxf(top, ll)
			sum += ll
	return {
		"moves": mi.moveset.size(),
		"top": top,
		"mean": sum / maxf(1.0, float(mi.moveset.size())),
		"class": str(mi.class_name_),
	}


## Redistribute a body's OWN total onto the archetype vector `roster.gd:_shape_to_class` builds
## (1.35 primary / 1.15 secondary / 0.875 the rest — weights that sum to 6.0, so the total is
## preserved exactly). Mutates and returns `mi`. ⚠️ Clamps to the monster's OWN ceiling, and the
## clamped remainder is reported by the caller as drift, because a reshape that quietly loses
## points is the exact bug `SHAPE_DIAGNOSIS.md` §5 B2 flags in `roster.gd`.
func _reshape_in_place(mi, pair: Array, cap: float) -> float:
	var total := _total(mi)
	var own_cap := WeekLib.stat_cap_for(mi, cap)
	for s in STATS:
		var w := 0.875
		if s == pair[0]: w = 1.35
		elif s == pair[1]: w = 1.15
		mi.stats[s] = clampf((total / 6.0) * w, 1.0, own_cap)
	return _total(mi) - total


## Two careers under a fixed shape policy at a given bloodline `potential`. Lives in its own
## function rather than inline in `_ready` for a boring but real reason: GDScript treats a whole
## function body as ONE scope, so a loop variable named `hi` or `top` inside `_ready` collides with
## one declared 400 lines earlier and the script fails to PARSE — which is how this probe silently
## produced nothing at all for two runs.
func _potential_arm(pot: float, cap: float) -> Dictionary:
	var total := 0.0
	var top := 0.0
	for i in range(2):
		var mi = _make("pot-%d" % i)
		mi.potential = pot
		var pair := _apt_pair(mi)
		var w := 0
		while not mi.retired and w < 400:
			w += 1
			mi.fed_this_week = false
			if mi.stamina < 30.0:
				WeekLib.apply_week(mi, {"kind": "rest"}, 100000, 0, "meat", false, 10, cap, "Wood")
				continue
			var pri: float = float(mi.stats[pair[0]])
			var sec: float = float(mi.stats[pair[1]])
			var want: String = pair[0] if pri < sec * (1.35 / 1.15) else pair[1]
			WeekLib.apply_week(mi, {"kind": "train", "drillId": _push_drill(want)}, 100000, 0,
				"meat", false, 10, cap, "Wood")
		total += _total(mi)
		var hi := 0.0
		for s in STATS:
			hi = maxf(hi, float(mi.stats[s]))
		top += hi
	return {"total": total / 2.0, "top": top / 2.0}


func _ready() -> void:
	print("\n=== TRAINING DECISION PROBE ===\n")
	var cap := APEX_CAP

	# ── 1. CAREER BUDGET ────────────────────────────────────────────────────────────────
	print("--- (1) CAREER BUDGET: can a monster max every stat? ---")
	var need := 6.0 * cap
	var sums := {"gained": 0.0, "weeks": 0.0, "trained": 0.0, "maxed": 0.0, "total": 0.0}
	var runs := 8
	for i in range(runs):
		var r := _run_career("budget-%d" % i, "", 30.0, cap)
		for k in sums:
			sums[k] += float(r[k])
	for k in sums:
		sums[k] /= float(runs)
	print("  career length          : %.0f weeks (%.1f years), %.0f of them training" % [
		sums["weeks"], sums["weeks"] / 48.0, sums["trained"]])
	print("  points banked          : %.0f" % sums["gained"])
	print("  final stat total       : %.0f" % sums["total"])
	print("  needed to max all six  : %.0f (6 x Apex cap %.0f)" % [need, cap])
	print("  stats actually maxed   : %.1f of 6" % sums["maxed"])
	print("  VERDICT: maxing everything is %s" % (
		"REACHABLE — nothing forces a choice" if sums["total"] >= need - 1.0
		else "NOT reachable (short by %.0f, %.0f%% of the requirement)" % [
			need - sums["total"], 100.0 * (need - sums["total"]) / need]))
	print("")

	# ── 2. POLICY DOMINANCE ─────────────────────────────────────────────────────────────
	print("--- (2) POLICY DOMINANCE: one drill family per career, identical seeds ---")
	print("  %-12s | %8s | %7s | %6s" % ["policy", "points", "pts/wk", "maxed"])
	var fam_pts := {}
	for family in ["basic", "intensive", "extreme", "diverse", ""]:
		var g := 0.0
		var w := 0.0
		var mx := 0.0
		for i in range(4):
			var r := _run_career("pol-%d" % i, family, 30.0, cap)
			g += float(r["gained"]); w += float(r["weeks"]); mx += float(r["maxed"])
		g /= 4.0; w /= 4.0; mx /= 4.0
		fam_pts[family] = g
		print("  %-12s | %8.0f | %7.2f | %6.2f" % [
			(family if family != "" else "greedy-all"), g, g / maxf(w, 1.0), mx])
	var best_fam := ""
	var best_v := -1.0
	var worst_v := 1e9
	for k in fam_pts:
		if float(fam_pts[k]) > best_v:
			best_v = float(fam_pts[k]); best_fam = str(k)
		worst_v = minf(worst_v, float(fam_pts[k]))
	print("  best family: %s   spread best/worst: %.2fx" % [
		(best_fam if best_fam != "" else "greedy-all"), best_v / maxf(worst_v, 1.0)])
	print("")

	# ── 3. PER-WEEK SPREAD ──────────────────────────────────────────────────────────────
	print("--- (3) PER-WEEK SPREAD: what the 30 cards are worth to ONE monster, ONE week ---")
	var m = _make("spread")
	var prof: Dictionary = WeekLib.training_profile(m)
	print("  %s (%s) — major %s / minor %s / flaw %s, happiness %d, stamina %.0f" % [
		m.species_name, m.body, prof["major"], prof["minor"], prof["flaw"], m.happiness, m.stamina])
	var by_kind := {}
	var lo := 1e9
	var hi := -1e9
	for d in WeekLib.DRILLS:
		var net := _net_of(m, str(d["id"]), cap)
		var k := str(d["kind"])
		if not by_kind.has(k):
			by_kind[k] = []
		by_kind[k].append(net)
		lo = minf(lo, net); hi = maxf(hi, net)
	for k in by_kind:
		var arr: Array = by_kind[k]
		var s := 0.0
		var kmin := 1e9
		var kmax := -1e9
		for v in arr:
			s += float(v); kmin = minf(kmin, float(v)); kmax = maxf(kmax, float(v))
		print("  %-10s mean %6.2f   range %5.1f .. %5.1f" % [k, s / arr.size(), kmin, kmax])
	print("  overall spread: %.1f .. %.1f  (a flat spread = the card tells you nothing)" % [lo, hi])
	print("")

	# ── 4. PREVIEW / APPLY LOCK-STEP ────────────────────────────────────────────────────
	print("--- (4) PREVIEW vs APPLY — the RNG-discipline invariant ---")
	var mismatch := 0
	var cases := 0
	for i in range(40):
		var a = _make("lock-%d" % i)
		a.happiness = i % 11
		a.stamina = float(10 + (i * 7) % 90)
		a.career_week = i
		var b = _make("lock-%d" % i)
		b.happiness = a.happiness
		b.stamina = a.stamina
		b.career_week = i
		var drill: String = str(WeekLib.DRILLS[i % WeekLib.DRILLS.size()]["id"])
		var food: String = str(["", "meat", "prime cut", "scholars tea"][i % 4])
		var forage: bool = (i % 5) == 0 and food == ""
		var action := {"kind": "train", "drillId": drill}
		var pv: Dictionary = WeekLib.preview_week(a, action, 500, 0, food, forage, 20, cap, "Wood")
		var before: Dictionary = b.stats.duplicate()
		WeekLib.apply_week(b, action, 500, 0, food, forage, 20, cap, "Wood")
		for s in STATS:
			cases += 1
			var real: float = float(b.stats[s]) - float(before[s])
			var shown: float = float(pv["statDeltas"].get(s, 0.0))
			if absf(real - shown) > 0.001:
				mismatch += 1
				if mismatch <= 4:
					print("    mismatch %s %s food=%s: preview %.1f, applied %.1f" % [
						a.id, s, food, shown, real])
	_ok(mismatch == 0, "preview == apply on %d stat-deltas across 40 weeks (food/forage included)" % cases)

	# food multiplier reachability — is a 75g training food worth anything at all?
	print("")
	print("--- (4b) does a TRAINING FOOD change the drill it pays for? ---")
	# ⚠️ SAME id AND SAME career_week on both, so both draw the SAME rng stream and the food is
	# the only variable. Two different ids would have compared two different rolls.
	var f1 = _make("food-same")
	var f2 = _make("food-same")
	var p_plain: Dictionary = WeekLib.preview_week(f1, {"kind": "train", "drillId": "powerlift"},
		1000, 0, "meat", false, 10, cap, "Wood")
	var p_cut: Dictionary = WeekLib.preview_week(f2, {"kind": "train", "drillId": "powerlift"},
		1000, 0, "prime cut", false, 75, cap, "Wood")
	var g_plain: float = float(p_plain["statDeltas"].get("STR", 0.0))
	var g_cut: float = float(p_cut["statDeltas"].get("STR", 0.0))
	print("  Powerlifting on Meat (10g)     : STR %+.0f" % g_plain)
	print("  Powerlifting on Prime Cut (75g): STR %+.0f   (card advertises +30%% STR/CON)" % g_cut)
	_ok(g_cut > g_plain, "the +30%% training food actually raises the drill it is sold for")


	# ── 5. THE DECISION SURFACE ──────────────────────────────────────────────
	# Does the BEST drill actually change as the build develops? If the same card is the answer at
	# every point in a career, the screen is a click no matter how many numbers it prints.
	print("")
	print("--- (5) DECISION SURFACE: does the best drill MOVE as the build develops? ---")
	var dm = _make("surface")
	var picks: Dictionary = {}
	var order: Array = []
	var last := ""
	var switches := 0
	for wk in range(120):
		var best_id := ""
		var best_net := -9999.0
		for d in WeekLib.DRILLS:
			var net := _net_of(dm, str(d["id"]), cap)
			if net > best_net:
				best_net = net; best_id = str(d["id"])
		picks[best_id] = int(picks.get(best_id, 0)) + 1
		if best_id != last:
			switches += 1
			order.append("wk%d:%s" % [wk, best_id])
			last = best_id
		dm.fed_this_week = false
		if dm.stamina < 30.0:
			WeekLib.apply_week(dm, {"kind": "rest"}, 100000, 0, "meat", false, 10, cap, "Wood")
		else:
			WeekLib.apply_week(dm, {"kind": "train", "drillId": best_id}, 100000, 0, "meat", false, 10,
				cap, "Wood")
	var top := 0
	for k in picks:
		top = maxi(top, int(picks[k]))
	print("  distinct drills that were ever optimal : %d" % picks.size())
	print("  times the optimal drill CHANGED        : %d over 120 weeks" % switches)
	print("  most-used single drill                 : %.0f%% of weeks" % (100.0 * top / 120.0))
	print("  switch trail (first 12): %s" % ", ".join(PackedStringArray(order.slice(0, 12))))
	_ok(picks.size() >= 3, "the optimal drill is not one fixed card for the whole career")
	_ok(top < 90, "no single drill is optimal in 75%+ of weeks")


	# ── 6. THE SAFETY CHECK ON FOCUS COST ──────────────────────────────────────
	# ⚠️ FOCUS COST MUST NOT FORBID A SPECIALIST. CLAUDE.md's rule that a species is never locked
	# out of a role applies to BUILDS too, and the 5v5 sim rewards specialists. A player who
	# deliberately pushes one stat, eating the diminishing returns on purpose, must still reach the
	# ceiling — the mechanic is a price, not a wall. This is the check that says so.
	print("")
	print("--- (6) SAFETY: can a DELIBERATE specialist still cap its stat? ---")
	for target in ["STR", "INT"]:
		var sm = _make("spec-%s" % target)
		var hit := -1
		var wk := 0
		while not sm.retired and wk < 400:
			wk += 1
			sm.fed_this_week = false
			if sm.stamina < 30.0:
				WeekLib.apply_week(sm, {"kind": "rest"}, 100000, 0, "meat", false, 10, cap, "Wood")
				continue
			# always the drill that pays the MOST into `target`, whatever it costs elsewhere
			var best_id := ""
			var best := -9999.0
			for d in WeekLib.DRILLS:
				var g: Dictionary = d.get("gains", {})
				if not g.has(target) or float(g[target]) <= 0.0:
					continue
				var pw: Dictionary = WeekLib.preview_week(sm, {"kind": "train", "drillId": str(d["id"])},
					100000, 0, "meat", false, 10, cap, "Wood")
				var v: float = float(pw["statDeltas"].get(target, 0.0))
				if v > best:
					best = v; best_id = str(d["id"])
			WeekLib.apply_week(sm, {"kind": "train", "drillId": best_id}, 100000, 0, "meat", false, 10,
				cap, "Wood")
			if hit < 0 and float(sm.stats[target]) >= cap - 0.5:
				hit = wk
		print("  specialist in %s: final %.0f / %.0f  — %s" % [
			target, float(sm.stats[target]), cap,
			("capped at week %d of %d" % [hit, wk]) if hit > 0 else "did NOT reach the cap in %d weeks" % wk])
		_ok(float(sm.stats[target]) >= cap * 0.85,
			"a deliberate %s specialist still gets within 15%% of the Apex ceiling" % target)


	# ── 7. WHAT SHAPE ACTUALLY COSTS, AND WHY ───────────────────────────────────
	# ⚠️ THIS SECTION EXISTS BECAUSE `docs/SHAPE_DIAGNOSIS.md` §3's ATTRIBUTION IS WRONG. It states
	# "`FOCUS_SLOPE 0.45` / `FOCUS_FLOOR 0.55` is the price of shape, and it is the only knob that
	# sets it", and prescribes raising the floor to 0.75 to take a spike's deficit from −31.9% to
	# ≥ −15%. Measured on `_probe_shape.tscn --gym`, that move takes the mean focus multiplier from
	# 0.618 to 0.781 exactly as predicted — and the deficit from −31.9% to only −30.3%. Removing
	# focus cost ENTIRELY (floor 1.0) leaves it at −28.8%. So focus cost is worth ~3 points of a
	# ~32-point deficit and the other ~29 are something else.
	#
	# That something else is the CEILING, and it is geometry, not tuning: the cap is PER STAT, so a
	# body that trains two stats has 2 x cap of usable room and a body that trains six has 6 x. A
	# spike does not lose points to a multiplier, it runs out of places to put them. This section
	# is the isolation — the same two policies at the real cap and at a ceiling nothing can reach.
	print("")
	print("--- (7) THE PRICE OF SHAPE: is it the focus multiplier, or the CEILING? ---")
	print("  %-8s | %8s | %8s | %s" % ["policy", "cap 1100", "uncapped", "note"])
	var cost_capped := {}
	var cost_free := {}
	for policy in ["lowest", "shape"]:
		var t_cap := 0.0
		var t_free := 0.0
		for i in range(3):
			t_cap += float(_run_policy("price-%d" % i, policy, cap)["total"])
			t_free += float(_run_policy("price-%d" % i, policy, 100000.0)["total"])
		cost_capped[policy] = t_cap / 3.0
		cost_free[policy] = t_free / 3.0
		print("  %-8s | %8.0f | %8.0f |" % [policy, cost_capped[policy], cost_free[policy]])
	var gap_capped: float = 100.0 * (float(cost_capped["shape"]) / maxf(1.0, float(cost_capped["lowest"])) - 1.0)
	var gap_free: float = 100.0 * (float(cost_free["shape"]) / maxf(1.0, float(cost_free["lowest"])) - 1.0)
	print("  shape vs lowest-stat, at the real ceiling : %+.1f%%" % gap_capped)
	print("  shape vs lowest-stat, ceiling removed     : %+.1f%%" % gap_free)
	# The gap between the two columns IS the ceiling's contribution. Before the headroom trade it
	# was 33.3 points (-25.7 vs +7.6); at/near zero the ceiling has stopped being the price.
	print("  => the per-stat ceiling costs a committed build %.1f points of total" % (gap_free - gap_capped))
	_ok(gap_free > gap_capped,
		"removing the per-stat ceiling makes shape cheaper — the cap IS a cost of specialising")

	# ── 8. WHAT SHAPE BUYS: the kit it unlocks ──────────────────────────────────
	# Sum-preserving, on the SAME trained body — the only variable is where the points sit.
	print("")
	print("--- (8) WHAT SHAPE BUYS: kit reach at an IDENTICAL stat total ---")
	var kit_flat_top := 0.0
	var kit_shaped_top := 0.0
	var kit_flat_moves := 0.0
	var kit_shaped_moves := 0.0
	var drift_max := 0.0
	var arms := 4
	for i in range(arms):
		var r := _run_policy("kit-%d" % i, "lowest", cap)
		var body = r["mi"]
		var pair := _apt_pair(body)
		var flat_kit := _kit_reach(body)
		var before_total := _total(body)
		var drift := _reshape_in_place(body, pair, cap)
		drift_max = maxf(drift_max, absf(drift))
		var shaped_kit := _kit_reach(body)
		kit_flat_top += float(flat_kit["top"]); kit_shaped_top += float(shaped_kit["top"])
		kit_flat_moves += float(flat_kit["moves"]); kit_shaped_moves += float(shaped_kit["moves"])
		if i == 0:
			print("  sample: total %.0f preserved to %+.1f pts" % [before_total, drift])
			print("    flat   -> %s, %d moves, top learnLevel %.0f" % [
				flat_kit["class"], int(flat_kit["moves"]), flat_kit["top"]])
			print("    shaped -> %s, %d moves, top learnLevel %.0f" % [
				shaped_kit["class"], int(shaped_kit["moves"]), shaped_kit["top"]])
	kit_flat_top /= arms; kit_shaped_top /= arms
	kit_flat_moves /= arms; kit_shaped_moves /= arms
	print("  mean top learnLevel : flat %.0f  ->  shaped %.0f  (%+.0f)" % [
		kit_flat_top, kit_shaped_top, kit_shaped_top - kit_flat_top])
	print("  mean moves carried  : flat %.1f  ->  shaped %.1f" % [kit_flat_moves, kit_shaped_moves])
	_ok(drift_max < 1.0, "the reshape is sum-preserving (max drift %.2f points)" % drift_max)
	_ok(kit_shaped_top > kit_flat_top,
		"shape unlocks a deeper kit at the same total — the learnLevel gate is what shape is FOR")

	# ── 9. THE OPEN TARGET: is the lowest-stat rule still the best rule? ─────────
	# ⚠️ THE BRIEF'S ACCEPTANCE CONDITION, AND IT IS CURRENTLY FALSE. CLAUDE.md: "if a training week
	# is an obvious click, it has failed." The naive rule — biggest drill on the lowest stat — is
	# today both the points-optimal rule AND the career-optimal one (`SHAPE_DIAGNOSIS.md` §1:
	# FLAT 21/24 vs APT 18/24), because the ladder's difficulty model prices the player on stat
	# TOTAL and is structurally blind to shape. Points cannot be the metric that fixes this: on
	# points, flat wins BY CONSTRUCTION, since it is the policy that spends every week where the
	# ceiling is furthest away. The metric that can move is what the shape is FOR — the kit.
	print("")
	print("--- (9) OPEN TARGET: does training toward a SHAPE beat training the LOWEST stat? ---")
	var pts := {}
	var reach := {}
	for policy in ["lowest", "shape", "greedy"]:
		var p_sum := 0.0
		var r_sum := 0.0
		for i in range(3):
			var r := _run_policy("target-%d" % i, policy, cap)
			p_sum += float(r["total"])
			r_sum += float(_kit_reach(r["mi"])["top"])
		pts[policy] = p_sum / 3.0
		reach[policy] = r_sum / 3.0
		print("  %-8s | total %6.0f | top learnLevel %5.0f" % [policy, pts[policy], reach[policy]])
	print("  the player who commits to a shape trades %+.1f%% of their stat total" % [
		100.0 * (float(pts["shape"]) / maxf(1.0, float(pts["lowest"])) - 1.0)])
	print("  ...and buys %+.0f learnLevel of kit reach for it." % [
		float(reach["shape"]) - float(reach["lowest"])])
	_target(float(reach["shape"]) > float(reach["lowest"]),
		"shape buys kit reach the flat body cannot reach (the mechanism)")
	_target(float(pts["shape"]) >= float(pts["lowest"]) * 0.90,
		"committing to a shape costs at most 10%% of the stat total (currently %.1f%%)" % [
			100.0 * (1.0 - float(pts["shape"]) / maxf(1.0, float(pts["lowest"])))])
	print("  ⚠️ The remaining half is NOT in this file: the field must stop pricing the player on")
	print("     stat total alone. See docs/SHAPE_DIAGNOSIS.md §5 BUILDER B (career.gd / roster.gd).")

	# ── 10. DOES BREEDING'S ONLY PRODUCT REACH THE TRAINING WEEK? ───────────────
	# ⚠️ BLOODLINE POTENTIAL IS THE ONLY THING BREEDING SELLS THAT THE MARKET SHELF CANNOT, and
	# `stat_cap_for` had NO shipped caller at all until round 11 — potential x1.00, x1.50 and x2.00
	# all finished on the same number (`_probe_breed.gd` §3b). That is this project's signature
	# failure and it has already happened to this exact value once, so it gets a standing tripwire
	# rather than a comment. It now scales the headroom ceiling too, so a bred body buys room in
	# BOTH directions: more total, and more of it spendable on one stat.
	print("")
	print("--- (10) BLOODLINE POTENTIAL: does the thing breeding sells reach the tick? ---")
	# ⚠️ Read these totals RELATIVE TO EACH OTHER ONLY. This arm's policy hammers the aptitude pair
	# and never falls through to a third stat when the pair caps, so its absolute totals are well
	# below §7/§9's "shape" and are NOT comparable to them. The variable under test is `potential`
	# and everything else is held identical, which is all this check needs.
	var pot_totals := {}
	for pot in [1.0, 1.10, 1.25]:
		var res := _potential_arm(float(pot), cap)
		pot_totals[pot] = float(res["total"])
		print("  potential x%.2f | ceiling %4.0f | career total %6.0f | top stat %5.0f" % [
			pot, cap * float(pot), res["total"], res["top"]])
	_ok(float(pot_totals[1.25]) > float(pot_totals[1.0]) + 1.0,
		"a x1.25 bloodline out-trains a wild one — potential reaches the shipped tick")

	print("")
	print("=== %d checks, %d failed  ·  %d acceptance targets, %d OPEN ===" % [
		_checks, _fail, _targets, _targets_open])
	get_tree().quit(0 if _fail == 0 else 1)
