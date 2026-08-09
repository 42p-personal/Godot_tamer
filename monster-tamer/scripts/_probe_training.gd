## THE TRAINING DECISION PROBE — is the week a DECISION, or an obvious click?
##
## CLAUDE.md: "Training and breeding are STRATEGY, NOT MAINTENANCE. If a training week is an
## obvious click, it has failed." That is a measurable claim, and this is the instrument.
##
## Run:
##   P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_training.tscn
##
## Four measurements:
##   1. CAREER BUDGET — total stat points a realistic monster can bank over a full career under
##      the best policy, vs the 6 x Apex-cap it would need to max EVERY stat. CLAUDE.md records
##      ~7,373 vs 6,600 from the TypeScript build; this measures the GODOT number.
##   2. POLICY DOMINANCE — every drill family run as a fixed policy over the same career, same
##      seeds. If one line is strictly best at every horizon, the choice is not a choice.
##   3. PER-WEEK SPREAD — the value of each of the 30 drills for ONE monster in ONE state. A flat
##      spread means the card the player is reading tells them nothing.
##   4. PREVIEW/APPLY LOCK-STEP — the RNG-discipline invariant, incl. the food path.
extends Node

const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const WeekLib = preload("res://scripts/week.gd")

const STATS := ["STR", "DEX", "CON", "WIS", "INT", "CHA"]
const APEX_CAP := 1100.0

var _fail := 0
var _checks := 0


func _ok(cond: bool, label: String) -> void:
	_checks += 1
	if not cond:
		_fail += 1
	print("  %s %s" % ["[ok]  " if cond else "[FAIL]", label])


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

	print("")
	print("=== %d checks, %d failed ===" % [_checks, _fail])
	get_tree().quit(0 if _fail == 0 else 1)
