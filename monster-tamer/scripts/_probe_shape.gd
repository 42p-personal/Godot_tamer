## THE SHAPE PROBE — does buying SHAPE pay, and does the 9x generalise?
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_shape.tscn -- --all
##   sections:  --gym    (cheap, no fights)   what does shaped training COST in stat points?
##              --nine   (medium)             does round 11's 9x sum-preserving shape gain hold?
##              --pol    (expensive)          the policy table at a seed count that can separate
##      flags:  --seeds N   how many career seeds per policy arm (default 8)
##              --weeks N   career horizon (default 1000)
##
## ⚠️ THIS FILE SUBCLASSES `_probe_career_arc.gd` RATHER THAN COPYING IT. A second autopilot is
## this project's most expensive recurring failure (`_probe_gold_wall.gd` says so at the top). The
## only thing overridden is the TRAINING BRAIN, which is the variable under test.
##
## THE PARADOX THIS EXISTS TO RESOLVE. Round 11 measured, paired and sum-preserving, that shaping a
## stalled roster took it from 4/80 rounds to 36/80 — a 9x fight advantage at identical stat total.
## Yet the career policy that spends its weeks buying shape gains only PACE. Both cannot be the
## whole story, and the difference between them is what this file measures.
extends "res://scripts/_probe_career_arc.gd"

## The three training brains. FLAT and APT already exist on the parent (`_drill_plan_greedy` /
## `_drill_plan_shaped`); SPIKE is new and is the point — it is the only one that builds the kind
## of body `roster.gd:_shape_to_class` builds, because it ignores `week.gd:focus_cost` entirely.
##   flat  — biggest drill on the LOWEST stat. The naive autopilot. Maximises TOTAL.
##   apt   — biggest drill on argmax(aptitude x focus_cost). The COMPETENT autopilot.
##   spike — biggest drill on the monster's TRADE pair only, focus cost be damned.
var s_brain := "flat"

## The extra seeds. `POLICY_SEEDS` carries 8 and 8 cannot separate two proportions; a proportion at
## n=8 has a +/-17-point error band, which is wider than any effect this round could plausibly find.
const MORE_SEEDS := [
	20260809, 771013, 313373, 4242424, 99180, 5150, 606060, 8888881,
	11235, 271828, 1618033, 6022140, 137035, 66260, 299792, 86400,
	31415926, 2718281, 4004, 1729, 40320, 65537, 123581, 999983,
	7777, 24601, 90210, 314159, 8675309, 101010, 555555, 121212,
]

var _ok := true


func _ready() -> void:
	_tree = get_tree()
	print("=== SHAPE PROBE — does buying shape pay? ===\n")
	var args: Array = OS.get_cmdline_user_args()
	args.append_array(OS.get_cmdline_args())
	var all: bool = "--all" in args
	if all or "--gym" in args:
		_run_shape_gym()
	if all or "--nine" in args:
		_run_nine()
	if all or "--pol" in args:
		_run_policy_table()
	print("\n=== shape probe: %s ===" % ("OK" if _ok else "INSTRUMENT BROKEN"))
	_tree.quit(0 if _ok else 1)


# =============================================================================
# THE TRAINING BRAINS
# =============================================================================

## ⚠️ THE ONLY OVERRIDE IN THIS FILE. Everything else — the barn, the recruits, the cups, the
## travel weeks, the dynasty — is the parent's autopilot, unchanged, so an arm-to-arm difference
## can only be the training brain.
func _drill_plan_greedy(mi, league_cap: float) -> Dictionary:
	if s_brain == "spike":
		return _drill_plan_spike(mi, league_cap)
	p_shaped_training = (s_brain == "apt")
	return super(mi, league_cap)


## The monster's TRADE: the class whose [primary, secondary] its aptitudes best support. Cached on
## the instance, because a trade that moves every week is not a trade. This is the "assignable
## class" of docs/CLASS_REWORK.md, chosen the only way a player could choose it — off aptitude.
func _trade_pair(mi) -> Array:
	if mi.has_meta("shape_trade"):
		return mi.get_meta("shape_trade")
	var best: Array = []
	var best_s := -INF
	for c in GameData.classes:
		var p: String = str(c.get("primary", ""))
		var s: String = str(c.get("secondary", ""))
		if p == "" or s == "" or p == s:
			continue
		var score: float = (WeekLib.stat_training_bonus(mi, p) * 1.35
			+ WeekLib.stat_training_bonus(mi, s) * 1.15)
		if score > best_s:
			best_s = score
			best = [p, s]
	if best.is_empty():
		best = ["STR", "CON"]
	mi.set_meta("shape_trade", best)
	return best


## SPIKE: drive the trade pair and nothing else. Primary first while it leads by less than the
## archetype's own ratio (1.35 : 1.15 — `roster.gd:SHAPE_PRIMARY` / `SHAPE_SECONDARY`), otherwise
## the secondary. Never trains the other four, so it pays `focus_cost` in full and buys the exact
## stat vector a rival archetype is built to.
func _drill_plan_spike(mi, league_cap: float) -> Dictionary:
	var cap: float = WeekLib.stat_cap_for(mi, league_cap)
	var pair: Array = _trade_pair(mi)
	var pri: float = float(mi.stats.get(pair[0], 0.0))
	var sec: float = float(mi.stats.get(pair[1], 0.0))
	var want := ""
	var pri_room: bool = pri < cap - 0.5
	var sec_room: bool = sec < cap - 0.5
	if pri_room and (not sec_room or pri < sec * (Roster.SHAPE_PRIMARY / Roster.SHAPE_SECONDARY)):
		want = str(pair[0])
	elif sec_room:
		want = str(pair[1])
	elif pri_room:
		want = str(pair[0])
	else:
		## The trade is capped. A spike player does NOT then flatten the body — it takes the
		## third-best stat, which is what keeps the shape while still using the week.
		var third := ""
		var third_s := -INF
		for s in Classify.STATS:
			if pair.has(s) or float(mi.stats.get(s, 0.0)) >= cap - 0.5:
				continue
			var sc: float = WeekLib.stat_training_bonus(mi, s)
			if sc > third_s:
				third_s = sc
				third = s
		if third == "":
			return {"mode": "idle", "id": ""}
		want = third
	if mi.stamina >= WeekLib.EXTREME_DRILL_STAMINA:
		return {"mode": "train", "id": "x" + want.to_lower()}
	return {"mode": "rest", "id": ""}


# =============================================================================
# 1. THE GYM — what does SHAPE cost in points? (no fights, exact, seconds)
# =============================================================================
## ⚠️ THIS IS THE FIRST QUESTION AND IT WAS NEVER ASKED. `career.gd:expected_climber_fill` is a
## stat TOTAL over a cap. If a shaped body arrives with a smaller total, the game prices it as a
## WEAKER player and hands it a harder field — so shape would have to beat the fight by more than
## it loses at the door. Measured here per training brain, on the same bodies and the same weeks.
const GYM_WEEKS := 336            ## a monster's whole trainable career (brief's constant)
const GYM_CAP := 1100.0           ## Tamers Apex
const GYM_SPECIES := 10

func _run_shape_gym() -> void:
	print("─── 1. THE GYM — what does shaped training COST? (%d weeks, cap %.0f) ───" % [
		GYM_WEEKS, GYM_CAP])
	Career.reset_new_game()
	Roster.reset_to_empty()
	print("  %-6s  %9s  %9s  %7s  %7s  %-16s  %s" % [
		"brain", "total", "vs flat", "spread", "top", "class@exit", "focus mult (mean)"])
	var totals := {}
	for brain in ["flat", "apt", "spike"]:
		var tot := 0.0
		var spread := 0.0
		var top := 0.0
		var focus := 0.0
		var n := 0
		var classes := {}
		for si in range(GYM_SPECIES):
			var r: Dictionary = _gym_one(brain, si)
			tot += float(r["total"])
			spread += float(r["spread"])
			top += float(r["top"])
			focus += float(r["focus"])
			classes[str(r["class"])] = int(classes.get(str(r["class"]), 0)) + 1
			n += 1
		totals[brain] = tot / float(n)
		var rel: String = "—" if brain == "flat" else "%+.1f%%" % (
			100.0 * (tot / float(n) / float(totals["flat"]) - 1.0))
		print("  %-6s  %9.0f  %9s  %7.2f  %7.0f  %-16s  %.3f" % [
			brain, tot / float(n), rel, spread / float(n), top / float(n),
			"%d distinct" % classes.size(), focus / float(n)])
	print("  (spread = (max-min)/mean, the arc's own `_shape_spread`. A `_shape_to_class` rival")
	print("   sits at (1.35-0.875)/1.0 = 0.475, so a body ABOVE that is more lopsided than the")
	print("   archetypes the ladder fields.)")


func _gym_one(brain: String, si: int) -> Dictionary:
	var before := s_brain
	s_brain = brain
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + si * 977
	var mi = GameData.make_monster(Art.ROSTER[(si * 7) % Art.ROSTER.size()], 0.0, rng)
	mi.id = "gym-%s-%d" % [brain, si]
	var focus_acc := 0.0
	var focus_n := 0
	for w in range(GYM_WEEKS):
		mi.happiness = 8
		mi.fed_this_week = true
		var plan: Dictionary = _drill_plan_greedy(mi, GYM_CAP)
		if str(plan["mode"]) == "train":
			var stat: String = str(plan["id"]).substr(1).to_upper()
			focus_acc += WeekLib.focus_cost(mi, stat)
			focus_n += 1
			WeekLib.apply_activity(mi, {"kind": "train", "drillId": str(plan["id"])},
				0, GYM_CAP, "Tamers Apex")
		else:
			WeekLib.apply_activity(mi, {"kind": "rest"}, 0, GYM_CAP, "Tamers Apex")
	s_brain = before
	var hi := -INF
	var lo := INF
	var sum := 0.0
	for s in Classify.STATS:
		var v: float = float(mi.stats.get(s, 0.0))
		hi = maxf(hi, v)
		lo = minf(lo, v)
		sum += v
	var mean: float = sum / float(Classify.STATS.size())
	mi.recompute_class()
	return {
		"total": sum, "spread": (hi - lo) / maxf(1.0, mean), "top": hi,
		"class": str(mi.class_name_), "focus": focus_acc / maxf(1.0, float(focus_n)),
	}


# =============================================================================
# 2. THE 9x — does a sum-preserving shape gain generalise across rungs and rosters?
# =============================================================================
## Round 11 shaped ONE stalled roster at ONE rung. Four arms, identical fights, paired:
##   A FLAT     the team as `_team_at_fill` builds it — every stat pinned to cap x fill
##   B SHAPED   the SAME team run through `roster.gd:_shape_to_class` (sum-preserving)
##   C STATSONLY the same shape, but arm A's MOVESET kept — separates the stat vector from the
##               kit that a higher primary unlocks. ⚠️ Round 11 could not tell these apart.
##   D MISMATCH shaped onto a class the body did NOT emerge as — is it SHAPE, or ALIGNMENT?
##   E STALE    FLAT stats, but the kit drafted at ROOKIE stats and never re-drawn. ⚠️ THIS IS
##              THE ROSTER ROUND 11 MEASURED. `week.gd:_redraft_if_stale` did not exist then, so
##              every arc body carried the loadout it was bought with for its whole career.
##   F STALEFIX arm E with the kit re-drawn at its CURRENT stats and NO shaping at all — the
##              control that says whether round 11's 9x was shape or was simply the kit.
const NINE_SALTS := 8
const NINE_RUNGS := [0, 2, 4, 6, 8, 10]

func _run_nine() -> void:
	print("\n─── 2. THE 9x — sum-preserving shape across rungs and rosters ───")
	Career.reset_new_game()
	Roster.reset_to_empty()
	print("  %-12s %5s  %-11s  %-11s  %-11s  %-11s  %-11s  %-11s  %s" % [
		"league", "fill", "A flat", "B shaped", "C stats-only", "D mismatch",
		"E stale kit", "F stale+redraft", "B/A"])
	var tA := 0
	var tB := 0
	var tC := 0
	var tD := 0
	var tE := 0
	var tF := 0
	var tN := 0
	for idx in NINE_RUNGS:
		## ⚠️ LOAD-BEARING, AND IT COST THIS PROBE ITS FIRST RUN. `roster.gd:_shape_to_class`
		## clamps every shaped stat to `GameData.stat_cap()`, which is
		## `Career.current_stat_cap()` — the CURRENT league's ceiling, not the rung being built.
		## Without this line every rung above Wood was shaped against a cap of 100 and came out
		## with six identical stats, and the arm read 0% at five of six rungs. That is a real
		## sharp edge in the shipped code, not only in this file: anything that shapes a team for
		## a league it is not standing in silently flattens it.
		Career.league_index = idx
		var size: int = Career.team_size_for_league(idx)
		var cap: float = Career.stat_cap_for_league(idx)
		var fill: float = Career.expected_climber_fill(idx)
		var rounds: int = maxi(1, Career.rival_count_for_league(idx))
		var wA := 0
		var wB := 0
		var wC := 0
		var wD := 0
		var wE := 0
		var wF := 0
		var n := 0
		for salt in range(NINE_SALTS):
			for r in range(rounds):
				var rf: float = Career.field_fill(r, rounds, idx)
				var rseed: int = abs(770000 + idx * 7919 + salt * 131 + r * 17) % 2147483647
				var bseed: int = 5150 + idx * 313 + salt * 29 + r
				if _nine_fight("flat", idx, size, cap, fill, salt, rf, rseed, bseed): wA += 1
				if _nine_fight("shaped", idx, size, cap, fill, salt, rf, rseed, bseed): wB += 1
				if _nine_fight("statsonly", idx, size, cap, fill, salt, rf, rseed, bseed): wC += 1
				if _nine_fight("mismatch", idx, size, cap, fill, salt, rf, rseed, bseed): wD += 1
				if _nine_fight("stale", idx, size, cap, fill, salt, rf, rseed, bseed): wE += 1
				if _nine_fight("staleredraft", idx, size, cap, fill, salt, rf, rseed, bseed): wF += 1
				n += 1
		_nine_audit(idx, size, cap, fill)
		tA += wA; tB += wB; tC += wC; tD += wD; tE += wE; tF += wF; tN += n
		var ratio: String = "%.1fx" % (float(wB) / maxf(1.0, float(wA))) if wA > 0 else "  inf"
		print("  %-12s %5.2f  %-11s  %-11s  %-11s  %-11s  %-11s  %-11s  %s" % [
			Career.league_at(idx).get("name", "?"), fill,
			_frac(wA, n), _frac(wB, n), _frac(wC, n), _frac(wD, n),
			_frac(wE, n), _frac(wF, n), ratio])
	print("  %-12s %5s  %-11s  %-11s  %-11s  %-11s  %-11s  %-11s  %s" % [
		"ALL", "", _frac(tA, tN), _frac(tB, tN), _frac(tC, tN), _frac(tD, tN),
		_frac(tE, tN), _frac(tF, tN), "%.2fx" % (float(tB) / maxf(1.0, float(tA)))])
	print("  round-11's setup is arm E; its 'shaped' arm is arm B. E -> B = %.2fx." % (
		float(tB) / maxf(1.0, float(tE))))
	print("  the KIT-ONLY half of that is E -> F = %.2fx, at an IDENTICAL stat vector." % (
		float(tF) / maxf(1.0, float(tE))))
	print("  (identical rivals and identical battle seeds in every arm; the ONLY difference is the")
	print("   player team's stat vector, at a stat total preserved to within the cap clamp.)")


## ⚠️ THE ARM MUST BE WHAT IT CLAIMS TO BE. Prints, per rung, the total the shape preserved, the
## HP it moved and whether the kit changed — because "shaped" quietly meaning "clamped flat" is
## exactly the failure this probe hit on its first run.
func _nine_audit(idx: int, size: int, cap: float, fill: float) -> void:
	var a: Array = _team_at_fill(size, cap, fill, idx)
	var b: Array = _team_at_fill(size, cap, fill, idx)
	var srng := RandomNumberGenerator.new()
	srng.seed = 9090
	for mi in b:
		Roster._shape_to_class(mi, str(mi.class_name_), srng)
		mi.recompute_pools()
	var ta := 0.0
	var tb := 0.0
	var ha := 0.0
	var hb := 0.0
	var ma := 0
	var mb := 0
	for i in range(a.size()):
		for s in Classify.STATS:
			ta += float(a[i].stats.get(s, 0.0))
			tb += float(b[i].stats.get(s, 0.0))
		ha += float(a[i].max_hp)
		hb += float(b[i].max_hp)
		ma += a[i].moveset.size()
		mb += b[i].moveset.size()
	print("      audit: stat total %.0f -> %.0f (%+.2f%%) · team maxHp %.0f -> %.0f (%+.1f%%)"
		% [ta, tb, 100.0 * (tb / maxf(1.0, ta) - 1.0), ha, hb, 100.0 * (hb / maxf(1.0, ha) - 1.0)]
		+ " · moves %d -> %d · class %s" % [ma, mb, str(a[0].class_name_)])


func _frac(w: int, n: int) -> String:
	return "%d/%d %3.0f%%" % [w, n, 100.0 * float(w) / maxf(1.0, float(n))]


## One paired round. `arm` decides only what happens to the player team AFTER it is built.
func _nine_fight(arm: String, idx: int, size: int, cap: float, fill: float,
		salt: int, rival_fill: float, rseed: int, bseed: int) -> bool:
	var team: Array = _team_at_fill(size, cap, fill, salt * 61 + idx)
	## ⚠️ THE ROUND-11 BODY, RECONSTRUCTED. `_team_at_fill` drafts the kit AT the filled stats,
	## which is a body that has never existed in a career: before `week.gd:_redraft_if_stale`
	## shipped, a recruit drafted at ~23/stat carried that loadout for life. Rebuild that by
	## drafting at ROOKIE stats and then restoring the trained ones without re-drawing.
	if arm == "stale" or arm == "staleredraft":
		var krng := RandomNumberGenerator.new()
		krng.seed = 4141 + salt
		for mi in team:
			var trained := {}
			for s in Classify.STATS:
				trained[s] = float(mi.stats[s])
				mi.stats[s] = float(mi.stats[s]) * 0.08   # a fresh market body's level
			mi.recompute_class()
			mi.assign_moveset(krng)
			for s in Classify.STATS:
				mi.stats[s] = float(trained[s])
			mi.recompute_class()
			if arm == "staleredraft":
				mi.assign_moveset(krng)
			mi.recompute_pools()
	if arm == "shaped" or arm == "statsonly" or arm == "mismatch":
		var srng := RandomNumberGenerator.new()
		srng.seed = 9090 + salt
		for mi in team:
			var keep: Array = mi.moveset.duplicate(true)
			var want: String = str(mi.class_name_)
			if arm == "mismatch":
				want = _other_class(want)
			Roster._shape_to_class(mi, want, srng)
			if arm == "statsonly":
				mi.moveset = keep
			mi.recompute_pools()
			mi.hp = mi.max_hp
			mi.mp = mi.max_mp
	var rivals: Array = Career.make_league_rivals(size, idx, rival_fill, rseed)
	for m in team:
		m.reset_for_battle()
	for m in rivals:
		m.reset_for_battle()
	var sim = BattleSimScript.new(team, rivals, bseed)
	return str(sim.run().get("winner", "")) == "A"


## A class sharing NEITHER stat with `c` where possible — the mismatch arm must actually mismatch.
func _other_class(c: String) -> String:
	var pair: Array = Roster._class_pair(c)
	for other in GameData.classes:
		var nm: String = str(other.get("name", ""))
		if nm == c:
			continue
		var p: String = str(other.get("primary", ""))
		var s: String = str(other.get("secondary", ""))
		if not pair.has(p) and not pair.has(s):
			return nm
	return c


# =============================================================================
# 3. THE POLICY TABLE — at a seed count that can actually separate two arms
# =============================================================================
## ⚠️ FOUR ARMS, AND THREE OF THEM DIFFER FROM NAIVE IN EXACTLY ONE THING. The round brief is
## right that "COMPETENT" cannot attribute anything: it changes training, kit re-drafting AND
## succession at once. FLAT / APT / SPIKE are identical in every other respect, so the difference
## between them IS the training brain. COMPETENT is kept as the bridge to the existing table.
const POL_ARMS := ["FLAT", "APT", "SPIKE", "COMPETENT"]

func _run_policy_table() -> void:
	var n: int = clampi(_arg_int("--seeds", 8), 1, MORE_SEEDS.size())
	var weeks: int = _arg_int("--weeks", POLICY_WEEKS)
	print("\n─── 3. THE POLICY TABLE (%d seeds x %d weeks x %d arms) ───" % [
		n, weeks, POL_ARMS.size()])
	var res := {}
	for arm in POL_ARMS:
		res[arm] = _run_arm(arm, n, weeks)
	print("")
	print("  %-10s  %-16s  %-8s  %-9s  %-7s  %-7s  %-7s  %s" % [
		"arm", "WON (95% CI)", "med wks", "med rung", "spread", "goldEnd", "empty", "capped wks"])
	for arm in POL_ARMS:
		var r: Dictionary = res[arm]
		print("  %-10s  %-16s  %-8d  %-9d  %-7.2f  %-7d  %-7.1f  %.0f" % [
			arm, _wilson(int(r["won"]), n), int(r["medWeeks"]), int(r["medReached"]),
			float(r["spread"]), int(r["medGold"]), float(r["empty"]), float(r["capped"])])
	print("")
	## ⚠️ PAIRED, ON THE SAME SEEDS. An unpaired comparison of two 8-seed proportions is what put
	## "NAIVE 7/8 beats COMPETENT 6/8" in the brief, and that was noise.
	for arm in ["APT", "SPIKE", "COMPETENT"]:
		_paired(res["FLAT"], res[arm], "FLAT", arm, n)
	print("")
	print("  ── what gated the careers that did NOT win ──")
	print("  %-10s  %-6s  %-9s  %-9s  %-9s  %-9s  %s" % [
		"arm", "lost", "goldEnd", "emptyStl", "fee-refus", "blockedWk", "stall reason (modal)"])
	for arm in POL_ARMS:
		var r: Dictionary = res[arm]
		print("  %-10s  %-6d  %-9d  %-9.1f  %-9.1f  %-9.1f  %s" % [
			arm, n - int(r["won"]), int(r["lostGold"]), float(r["lostEmpty"]),
			float(r["lostFee"]), float(r["lostBlocked"]), str(r["stall"])])


func _run_arm(arm: String, n: int, weeks: int) -> Dictionary:
	var opts := {}
	match arm:
		"FLAT":
			s_brain = "flat"
			apply_policy("NAIVE")
		"APT":
			s_brain = "apt"
			apply_policy("NAIVE")
		"SPIKE":
			s_brain = "spike"
			apply_policy("NAIVE")
		"COMPETENT":
			s_brain = "apt"
			apply_policy("COMPETENT")
	var won := 0
	var wks: Array = []
	var reached: Array = []
	var gold: Array = []
	var spread := 0.0
	var empty := 0.0
	var capped := 0.0
	var wonflags: Array = []
	var lost_gold: Array = []
	var lost_empty := 0.0
	var lost_fee := 0.0
	var lost_blocked := 0.0
	var lost_n := 0
	var stalls := {}
	for s in range(n):
		p_seed = int(MORE_SEEDS[s])
		var a: Dictionary = _run_arc(weeks, opts)
		var w: bool = bool(a.get("won", false))
		if w:
			won += 1
		wonflags.append(w)
		wks.append(int(a["weeks"]))
		reached.append(int(a["finalLeague"]))
		gold.append(int(a["goldEnd"]))
		spread += float(a["shapeSpread"])
		empty += float(a["emptySlots"])
		capped += float(a["cappedWeeks"])
		if not w:
			lost_n += 1
			lost_gold.append(int(a["goldEnd"]))
			lost_empty += float(a["emptySlots"])
			lost_fee += float(a["cupsRefusedByFee"])
			lost_blocked += float(a["frontierBlockedWeeks"])
			var sr: String = str(a.get("stall", ""))
			if sr == "":
				sr = "ran out of weeks"
			stalls[sr] = int(stalls.get(sr, 0)) + 1
		print("    %-10s seed %-9d -> %-12s wk %4d %s %5dg  spread %.2f" % [
			arm, int(MORE_SEEDS[s]), str(Career.league_at(int(a["finalLeague"])).get("name", "?")),
			int(a["weeks"]), "WON " if w else "    ", int(a["goldEnd"]), float(a["shapeSpread"])])
	s_brain = "flat"
	apply_policy("NAIVE")
	var fn := float(n)
	var lf := maxf(1.0, float(lost_n))
	var modal := "—"
	var modal_n := 0
	for k in stalls:
		if int(stalls[k]) > modal_n:
			modal_n = int(stalls[k])
			modal = "%s (x%d)" % [k, modal_n]
	return {
		"won": won, "wonFlags": wonflags, "weeks": wks, "reached": reached,
		"medWeeks": _median(wks), "medReached": _median(reached), "medGold": _median(gold),
		"spread": spread / fn, "empty": empty / fn, "capped": capped / fn,
		"lostGold": _median(lost_gold) if lost_n > 0 else 0,
		"lostEmpty": lost_empty / lf, "lostFee": lost_fee / lf, "lostBlocked": lost_blocked / lf,
		"stall": modal,
	}


## Paired comparison on the SAME seeds: a sign test on weeks-to-finish (a censored run counts as
## worse than any finished one), plus the win-count difference. See CLAUDE.md on the sign test.
func _paired(a: Dictionary, b: Dictionary, na: String, nb: String, n: int) -> void:
	var better := 0
	var worse := 0
	var same := 0
	for i in range(n):
		var wa: bool = bool(a["wonFlags"][i])
		var wb: bool = bool(b["wonFlags"][i])
		var sa: float = float(a["weeks"][i]) if wa else 1.0e9 + float(a["reached"][i]) * -1.0
		var sb: float = float(b["weeks"][i]) if wb else 1.0e9 + float(b["reached"][i]) * -1.0
		if sb < sa - 0.5:
			better += 1
		elif sb > sa + 0.5:
			worse += 1
		else:
			same += 1
	var m: int = better + worse
	print("  paired %s -> %s : %d better / %d worse / %d tied   sign-test p = %s" % [
		na, nb, better, worse, same, ("n/a" if m == 0 else "%.4f" % _sign_p(better, m))])


## Two-sided sign test p-value, exact binomial at p=0.5.
func _sign_p(k: int, n: int) -> float:
	if n <= 0:
		return 1.0
	var lo: int = mini(k, n - k)
	var acc := 0.0
	for i in range(lo + 1):
		acc += _binom(n, i)
	return minf(1.0, 2.0 * acc / pow(2.0, float(n)))


func _binom(n: int, k: int) -> float:
	var r := 1.0
	for i in range(k):
		r = r * float(n - i) / float(i + 1)
	return r


## Wilson score interval — the honest error band on a proportion at small n.
func _wilson(k: int, n: int) -> String:
	if n <= 0:
		return "—"
	var p: float = float(k) / float(n)
	var z := 1.96
	var d: float = 1.0 + z * z / float(n)
	var c: float = p + z * z / (2.0 * float(n))
	var s: float = z * sqrt(p * (1.0 - p) / float(n) + z * z / (4.0 * float(n) * float(n)))
	return "%d/%d [%.2f-%.2f]" % [k, n, maxf(0.0, (c - s) / d), minf(1.0, (c + s) / d)]


func _median(xs: Array) -> int:
	if xs.is_empty():
		return 0
	var v: Array = xs.duplicate()
	v.sort()
	return int(v[v.size() / 2])
