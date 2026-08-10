## THE SCARCITY PROBE — does the career have a FAILURE CONDITION, and would making TIME scarce
## convert a fight advantage into a career advantage?
##
## Run (all sections are opt-in; `--seeds N` sets the per-arm seed count, default 16):
##   P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_scarcity.tscn -- --ledger
##   ... -- --ledger --deadline            (deadline sweep is POST-HOC on the ledger run: FREE)
##   ... -- --verify                       (proves the post-hoc censoring == a real short horizon)
##   ... -- --life                         (regime b: a stricter lifespan)
##   ... -- --fee  --feemult 8             (regime c: rising entry costs)
##   ... -- --releg                        (regime e: a lost cup costs POSITION, not time)
##
## ⚠️ THIS FILE SHIPS NOTHING AND EDITS NOTHING. Round 16 is a diagnostic round. Every regime below
## is imposed at RUNTIME by this probe, on state that `_reset_career()` wipes at the start of every
## arc, and every one carries a LIVENESS CANARY that fails the run if the perturbation did not bite.
##
## ⚠️ IT SUBCLASSES `_probe_shape.gd` (which subclasses `_probe_career_arc.gd`). That is deliberate
## and it is the house rule: a second copy of the autopilot is this project's most expensive
## recurring failure. Subclassing the SHAPE probe rather than the arc probe additionally means the
## FLAT and COMPETENT arms here are byte-identical to the ones that produced the round-15 policy
## table, so the baseline is a REPRODUCTION and not a new measurement that has to be trusted.
##
## ── THE QUESTION ──────────────────────────────────────────────────────────────
## Four rounds have ended on "competence buys pace, not access". The round-16 hypothesis is that
## the career HAS NO FAILURE CONDITION: cups are retryable, time is abundant, so ADVANCE can only
## set how many cups a rung costs — i.e. how many WEEKS — and never whether the rung is cleared.
## If that is true, every stable-side mechanic will be absorbed as pace, and the proposed remedy is
## to make TIME genuinely scarce. This probe TESTS THE REMEDY WITHOUT BUILDING IT.
##
## ⚠️ AND IT LOOKS FIRST FOR THE FINDING THAT KILLS THE REMEDY: if a clock separates the policies
## only by pushing the NAIVE player below the on-ramp while the competent one is untouched, then
## scarcity is not converting skill into access — it is raising difficulty, which this project has
## already caught itself doing three times (round 12b champion relief, round 14 FOCUS_FLOOR,
## round 15 per-class caps). §2's `slack ledger` is the test that tells those two apart.
extends "res://scripts/_probe_shape.gd"

## The two arms the four defeated rounds have been comparing. Nothing else is run: APT and SPIKE
## are attribution arms for a question this round is not asking, and each one doubles the wall time.
const SC_ARMS := ["FLAT", "COMPETENT"]

## The horizon every baseline arc is run at. Deliberately the same 1000 the shipped table used, so
## the deadline sweep is a CENSORING of a known-good run rather than a new set of careers.
const SC_WEEKS := 1000

## The deadlines swept post-hoc. The brief asked for 250/350/450/600; the extra cells are there
## because a threshold sweep with four points cannot show whether the curve has a shoulder.
const SC_DEADLINES := [200, 250, 300, 350, 400, 450, 500, 600, 750, 1000]

var _sc_ok := true
var _sc_notes: Array[String] = []

# ── regime state (all restored; see `_restore_regimes`) ───────────────────────
var s_life_mult := 1.0        ## regime (b): multiplier applied to every monster's lifespan_years
var s_relegate := false       ## regime (e): a frontier cup with ZERO round wins costs a rung
var _life_n := 0              ## canary: how many bodies the lifespan perturbation actually touched
var _life_base := 0.0
var _life_pert := 0.0
var _releg_n := 0             ## canary: how many relegations actually fired


func _ready() -> void:
	_tree = get_tree()
	var args: Array = OS.get_cmdline_user_args()
	args.append_array(OS.get_cmdline_args())
	var n: int = clampi(_arg_int("--seeds", 16), 2, MORE_SEEDS.size())
	print("=== SCARCITY PROBE — does the career have a failure condition? ===")
	print("arms %s · %d seeds · horizon %d weeks\n" % [str(SC_ARMS), n, SC_WEEKS])

	## §1 is the spine: everything else either reads its rows or is compared against them.
	var base := {}
	var want_base: bool = ("--ledger" in args) or ("--deadline" in args) or ("--all" in args) \
		or ("--life" in args) or ("--fee" in args) or ("--releg" in args)
	if want_base:
		base = _run_baseline(n)
		_report_ledger(base, n)
	if ("--deadline" in args) or ("--all" in args):
		_report_deadline(base, n)
		_report_rival(base, n)
	if ("--verify" in args) or ("--all" in args):
		_verify_censoring(base, n)
	if ("--life" in args) or ("--all" in args):
		_run_life(base, n, float(_arg_int("--lifepct", 60)) / 100.0)
	if ("--fee" in args) or ("--all" in args):
		_run_fee(base, n, float(_arg_int("--feemult", 8)))
	if ("--releg" in args) or ("--all" in args):
		_run_releg(base, n)

	if not _sc_notes.is_empty():
		print("\n── notes ──")
		for t in _sc_notes:
			print("  " + t)
	print("\n=== scarcity probe: %s ===" % ("OK" if _sc_ok else "CANARY FAILED / INSTRUMENT BROKEN"))
	_tree.quit(0 if _sc_ok else 1)


# =============================================================================
# THE ARM RUNNER
# =============================================================================
## One arm, `n` seeds, returning the raw `_run_arc` dictionaries. The arm definitions are exactly
## `_probe_shape.gd:_run_arm`'s: FLAT = naive brain + NAIVE policy, COMPETENT = apt brain +
## COMPETENT policy. Kept in one place so a regime can never quietly become a second variable.
func _arc_arm(arm: String, n: int, weeks: int, feemult: float = 1.0) -> Array:
	match arm:
		"FLAT":
			s_brain = "flat"
			apply_policy("NAIVE")
		"COMPETENT":
			s_brain = "apt"
			apply_policy("COMPETENT")
		_:
			push_error("_probe_scarcity: unknown arm %s" % arm)
	var rows: Array = []
	for s in range(n):
		p_seed = int(MORE_SEEDS[s])
		var opts := {}
		if not is_equal_approx(feemult, 1.0):
			opts["feeMult"] = feemult
		var a: Dictionary = _run_arc(weeks, opts)
		rows.append(a)
	s_brain = "flat"
	apply_policy("NAIVE")
	return rows


func _won_flags(rows: Array, deadline: int = 1 << 30) -> Array:
	var out: Array = []
	for a in rows:
		out.append(bool(a.get("won", false)) and int(a.get("weeks", 0)) <= deadline)
	return out


func _count(flags: Array) -> int:
	var k := 0
	for f in flags:
		if bool(f):
			k += 1
	return k


func _mean(rows: Array, key: String) -> float:
	if rows.is_empty():
		return 0.0
	var acc := 0.0
	for a in rows:
		acc += float(a.get(key, 0))
	return acc / float(rows.size())


## Paired sign test on two BINARY outcome vectors on the same seeds.
func _paired_bin(a: Array, b: Array) -> String:
	var better := 0
	var worse := 0
	for i in range(a.size()):
		if bool(b[i]) and not bool(a[i]):
			better += 1
		elif bool(a[i]) and not bool(b[i]):
			worse += 1
	var m: int = better + worse
	return "%d b / %d w  p=%s" % [better, worse, ("n/a" if m == 0 else "%.4f" % _sign_p(better, m))]


# =============================================================================
# 1. THE BASELINE AND THE SLACK LEDGER
# =============================================================================
## ⚠️ THE LEDGER IS THE MEASUREMENT THAT DISTINGUISHES THE TWO OUTCOMES THE BRIEF SAYS LOOK
## IDENTICAL IN A SUMMARY TABLE. If a naive career's weeks are almost all TRAINING weeks it had to
## spend, a deadline is unanswerable by any decision the naive player can make and is a pure
## difficulty raise. If a large share of them are weeks the career did not have to spend — waiting
## out a cup cadence, capped with nothing left to train, blocked out of the frontier for want of
## bodies, foraging for gold — then a deadline creates a real decision and the remedy is live.
func _run_baseline(n: int) -> Dictionary:
	print("─── 1. BASELINE — the shipped game, horizon %d ───" % SC_WEEKS)
	var out := {}
	for arm in SC_ARMS:
		out[arm] = _arc_arm(arm, n, SC_WEEKS)
	return out


func _report_ledger(base: Dictionary, n: int) -> void:
	print("\n  %-11s %-16s %-9s %-8s %-8s %-9s %s" % [
		"arm", "WON (95% Wilson)", "med wks", "cups", "travelWk", "cupsxCAD", "career explained by cadence"])
	for arm in SC_ARMS:
		var rows: Array = base[arm]
		var k: int = _count(_won_flags(rows))
		var wonw: Array = []
		for a in rows:
			if bool(a.get("won", false)):
				wonw.append(int(a["weeks"]))
		var cups: float = _mean(rows, "cups")
		var trav: float = _mean(rows, "travelWeeks")
		var wks: float = _mean(rows, "weeks")
		## ⚠️ THE EQUALITY THE WHOLE HYPOTHESIS TURNS ON, STATED SO IT CAN BE CHECKED RATHER THAN
		## ASSERTED. The autopilot may enter a cup once `Career.week - last_cup_week >= CUP_INTERVAL`,
		## and the TRAVEL weeks advance `Career.week` too — so the trip is spent INSIDE the interval,
		## not on top of it, and the cadence is a flat `CUP_INTERVAL` weeks per cup. If
		## `cups x CUP_INTERVAL` accounts for the whole career, then career LENGTH *is* cup COUNT,
		## and cup count is 1/ADVANCE: ADVANCE converts into weeks and into nothing else.
		var cadence: float = cups * float(CUP_INTERVAL)
		print("  %-11s %-16s %-9d %-8.1f %-8.1f %-9.0f %.0f%% of %.0f wks" % [
			arm, _wilson(k, n), _median(wonw), cups, trav, cadence,
			100.0 * cadence / maxf(1.0, wks), wks])

	print("\n  ── THE SLACK LEDGER — what the weeks were spent on ──")
	print("  ⚠️ train/rest/excursion/capped are MONSTER-weeks (the arc counts them per body per")
	print("     week); travel/blocked are CALENDAR weeks. Do not add the two kinds together.")
	print("  %-11s %-8s %-9s %-9s %-9s %-9s %-9s %-9s %s" % [
		"arm", "calWks", "trainMW", "restMW", "excurMW", "cappedMW", "travelWk", "blockedWk", "retire"])
	for arm in SC_ARMS:
		var rows: Array = base[arm]
		print("  %-11s %-8.0f %-9.0f %-9.0f %-9.0f %-9.0f %-9.1f %-9.1f %.1f" % [
			arm, _mean(rows, "weeks"), _mean(rows, "trainWeeks"), _mean(rows, "restWeeks"),
			_mean(rows, "excursionWeeks"), _mean(rows, "cappedWeeks"), _mean(rows, "travelWeeks"),
			_mean(rows, "frontierBlockedWeeks"), _mean(rows, "retirements")])
	print("\n  ── the economy, for the record (the gate SHAPE_DIAGNOSIS §4 already ruled out) ──")
	print("  %-11s %-9s %-9s %-11s %-9s %s" % [
		"arm", "goldEnd", "feesPaid", "feeRefusals", "emptyStl", "bestPotential"])
	for arm in SC_ARMS:
		var rows: Array = base[arm]
		print("  %-11s %-9.0f %-9.0f %-11.2f %-9.2f %.2f" % [
			arm, _mean(rows, "goldEnd"), _mean(rows, "feesPaid"),
			_mean(rows, "cupsRefusedByFee"), _mean(rows, "emptySlots"),
			_mean(rows, "bestPotential")])

	_report_per_league(base, n)

	## LIVENESS: the baseline must reproduce the arms it claims to be. A FLAT arm that does not
	## complete near the shipped 28/32 is not the reference player and nothing downstream means
	## anything. Deliberately a WIDE band — at n=16 a proportion carries about +/-12 points.
	var fk: int = _count(_won_flags(base["FLAT"]))
	if float(fk) / float(n) < 0.55:
		_sc_ok = false
		_sc_notes.append("⚠️ CANARY: FLAT completed %d/%d, far below the shipped 28/32 (87.5%%). The"
			% [fk, n] + " baseline is not the reference player; every regime below is unreadable.")


## ⚠️ WHERE THE CUPS ACTUALLY GO, AND WHAT THE PLAYER'S REALISED ADVANCE IS.
## The round-16 hypothesis budgets 32.3 cups for the whole ladder, from the ADVANCE table
## (66 79 45 69 65 58 42 23 34 19 13) measured at `expected_climber_fill`. A REAL career does not
## arrive at a rung already filled — it enters, loses, trains, enters again. So the realised
## ADVANCE (1 / cups spent at a rung) is the number that sets the career's length, and if it is far
## below the tabulated one the hypothesis's arithmetic is wrong even where its conclusion is right.
## `fillAtExit` against `expected_climber_fill` is the diagnosis of which: under-filled means the
## career is TRAINING-bound, over-filled means it is CADENCE-bound.
func _report_per_league(base: Dictionary, n: int) -> void:
	const TABLED := [66, 79, 45, 69, 65, 58, 42, 23, 34, 19, 13]
	print("\n  ── WHERE THE CUPS GO (mean over %d careers per arm) ──" % n)
	## ⚠️ `F.loopWk` IS NOT CALENDAR WEEKS. The arc attributes a week to the league it was STANDING
	## IN at the top of the loop and does not attribute TRAVEL weeks to any league at all, so these
	## sum to (career weeks − travel weeks). Cups are attributed to the league FOUGHT, which may be
	## a lower rung being farmed. The two columns are therefore not divisible into each other.
	print("  %-13s %-8s %-7s %-7s %-8s %-9s %-9s %-9s %s" % [
		"league", "F.loopWk", "F.cups", "F.adv%", "tabled%", "F.rndWin%", "F.fill@ex", "wantFill", "C.cups"])
	var nl: int = Career.leagues.size()
	for i in range(nl):
		var fw := 0.0
		var fc := 0.0
		var fr := 0.0
		var frw := 0.0
		var ff := 0.0
		var ffn := 0
		var cc := 0.0
		for a in base["FLAT"]:
			var L: Dictionary = a["perLeague"][i]
			fw += float(L["weeks"]); fc += float(L["cups"])
			fr += float(L["rounds"]); frw += float(L["roundWins"])
			if float(L["fillAtExit"]) > 0.0:
				ff += float(L["fillAtExit"]); ffn += 1
		for a in base["COMPETENT"]:
			cc += float(a["perLeague"][i]["cups"])
		var fn := float(n)
		print("  %-13s %-8.0f %-7.1f %-7.0f %-8d %-9.0f %-9.3f %-9.3f %.1f" % [
			str(Career.league_at(i).get("name", "?")), fw / fn, fc / fn,
			100.0 * fn / maxf(1.0, fc), (int(TABLED[i]) if i < TABLED.size() else 0),
			100.0 * frw / maxf(1.0, fr), ff / maxf(1.0, float(ffn)),
			Career.expected_climber_fill(i), cc / fn])
	print("  (F.adv%% is the REALISED promotion rate = careers / cups spent at that rung. Where it")
	print("   sits far below `tabled%%`, the player is arriving under-filled and the rung is being")
	print("   paid for in TRAINING weeks; where it matches, the rung is paid for in cup RETRIES.)")


## The win-week distribution is the only axis the two policies are known to differ on, so it is
## printed in full rather than as a median — every deadline result below is a threshold on it.
func _report_weeks_cdf(base: Dictionary, n: int) -> void:
	print("\n  ── the win-week distribution (the axis the deadline thresholds) ──")
	for arm in SC_ARMS:
		var w: Array = []
		for a in base[arm]:
			if bool(a.get("won", false)):
				w.append(int(a["weeks"]))
		w.sort()
		var line := ""
		for v in w:
			line += "%d " % int(v)
		print("  %-11s wins %d/%d : %s" % [arm, w.size(), n, line])


# =============================================================================
# 2. REGIME (a) — A HARD CAREER DEADLINE, SWEPT POST-HOC
# =============================================================================
## ⚠️ POST-HOC CENSORING IS EXACT HERE, NOT AN APPROXIMATION, AND `--verify` PROVES IT.
## `_run_arc`'s horizon appears in exactly one place — the `while Career.week < max_weeks` guard —
## and the arc is deterministic in `p_seed`. So "would this career have won by week D" is
## `won and weeks <= D`, and one 1000-week run answers the whole sweep for free.
##
## ⚠️ WHAT POST-HOC CENSORING CANNOT SEE, STATED BEFORE THE NUMBERS. A real deadline would change
## how the player PLAYS — a naive player facing a clock might cup harder, train less, buy earlier.
## This measures the deadline against a player who does not adapt. That is the correct NULL (it is
## what the shipped autopilots would do), and it is the CEILING of the deadline's separating power
## for a non-adapting player — but it is not a claim about a player who learns.
func _report_deadline(base: Dictionary, n: int) -> void:
	print("\n─── 2. REGIME (a) — A HARD CAREER DEADLINE (post-hoc censoring, exact) ───")
	_report_weeks_cdf(base, n)
	print("")
	print("  %-8s  %-18s  %-18s  %-8s  %s" % [
		"deadline", "FLAT (95% Wilson)", "COMPETENT (Wilson)", "gap pts", "paired sign test"])
	var moved := false
	var f0: int = _count(_won_flags(base["FLAT"]))
	for d in SC_DEADLINES:
		var ff: Array = _won_flags(base["FLAT"], int(d))
		var cf: Array = _won_flags(base["COMPETENT"], int(d))
		var fk: int = _count(ff)
		var ck: int = _count(cf)
		if fk != f0:
			moved = true
		var onramp: String = ""
		if float(fk) / float(n) < 0.5:
			onramp = "  <- NAIVE BELOW 50%: ON-RAMP GONE"
		print("  %-8d  %-18s  %-18s  %-8s  %s%s" % [
			int(d), _wilson(fk, n), _wilson(ck, n),
			"%+.0f" % (100.0 * float(ck - fk) / float(n)), _paired_bin(ff, cf), onramp])
	## LIVENESS: a sweep in which no deadline ever changes an outcome measured nothing.
	if not moved:
		_sc_ok = false
		_sc_notes.append("⚠️ CANARY: no deadline in the sweep changed FLAT's completion count. The"
			+ " perturbation did not bite — every career finished inside the shortest deadline.")
	_report_shift(base, n)


## ⚠️ THE TEST THAT TELLS "SCARCITY BOUGHT ACCESS" FROM "SCARCITY RAISED DIFFICULTY" APART.
## The two policies are known to differ in exactly ONE measured way: weeks-to-finish. If the whole
## deadline effect is reproduced by taking FLAT's OWN win-week distribution and sliding it left by
## the median pace difference, then the deadline is a threshold on the one axis where the arms
## already differed, and it has discovered nothing — it has priced the naive player out.
## The counter-evidence would be re-ORDERING: seeds where COMPETENT finishes and FLAT does not for
## a reason other than the constant shift, i.e. a spread difference, not a location difference.
func _report_shift(base: Dictionary, n: int) -> void:
	var fw: Array = []
	var cw: Array = []
	for i in range(n):
		var a: Dictionary = base["FLAT"][i]
		var b: Dictionary = base["COMPETENT"][i]
		if bool(a.get("won", false)):
			fw.append(int(a["weeks"]))
		if bool(b.get("won", false)):
			cw.append(int(b["weeks"]))
	var shift: int = _median(fw) - _median(cw)
	print("\n  ── is the deadline a DISCOVERY or a THRESHOLD? ──")
	print("  median win week: FLAT %d · COMPETENT %d · shift %d weeks" % [
		_median(fw), _median(cw), shift])
	print("  %-8s  %-12s  %-12s  %-14s  %s" % [
		"deadline", "FLAT k/n", "COMP k/n", "FLAT@(D+shift)", "does the shift explain it?"])
	for d in SC_DEADLINES:
		var fk: int = _count(_won_flags(base["FLAT"], int(d)))
		var ck: int = _count(_won_flags(base["COMPETENT"], int(d)))
		## FLAT evaluated at a deadline LENGTHENED by the pace shift. If that reproduces
		## COMPETENT's count, COMPETENT is a FLAT player with more weeks and nothing else.
		var fs: int = _count(_won_flags(base["FLAT"], int(d) + shift))
		var verdict: String = "shift explains it" if absi(fs - ck) <= 1 else "RESIDUAL %+d" % (ck - fs)
		print("  %-8d  %-12s  %-12s  %-14s  %s" % [
			int(d), "%d/%d" % [fk, n], "%d/%d" % [ck, n], "%d/%d" % [fs, n], verdict])


# =============================================================================
# 3. REGIME (d) — A RIVAL DYNASTY THAT CAN TAKE THE TITLE FIRST
# =============================================================================
## ⚠️ NOT A NEW MECHANIC — ARITHMETICALLY A DEADLINE WITH JITTER, AND THAT IS THE FINDING.
## A rival that climbs on its own schedule and takes Apex at week R ends the player's career at R.
## If R is fixed, this IS regime (a). If R varies (the rival's own climb is stochastic, or the
## player can slow it), it is a deadline convolved with that spread — and convolving a threshold
## with noise can only FLATTEN it. Measured here by averaging the censoring over R ~ U(D-j, D+j).
func _report_rival(base: Dictionary, n: int) -> void:
	print("\n─── 3. REGIME (d) — A RIVAL DYNASTY = a deadline convolved with the rival's own spread ───")
	print("  %-8s  %-7s  %-14s  %-14s  %s" % ["target D", "jitter", "FLAT E[k]/n", "COMP E[k]/n", "gap pts"])
	for d in [300, 350, 450, 600]:
		for j in [0, 75, 150]:
			var fa := 0.0
			var ca := 0.0
			var m := 0
			for r in range(-j, j + 1, maxi(1, j / 8)):
				fa += float(_count(_won_flags(base["FLAT"], d + r)))
				ca += float(_count(_won_flags(base["COMPETENT"], d + r)))
				m += 1
				if j == 0:
					break
			fa /= float(m)
			ca /= float(m)
			print("  %-8d  %-7d  %-14s  %-14s  %+.0f" % [
				d, j, "%.1f/%d" % [fa, n], "%.1f/%d" % [ca, n], 100.0 * (ca - fa) / float(n)])


# =============================================================================
# 4. THE CENSORING VERIFICATION — the instrument checking itself
# =============================================================================
## ⚠️ ROUND 16 IS ALLOWED EXACTLY ONE ASSUMPTION AND THIS IS IT, SO IT IS CHECKED RATHER THAN
## ASSUMED. Re-runs both arms at a REAL 350-week horizon and asserts the won-flags equal the
## post-hoc censoring of the 1000-week run at 350. If they differ, every number in §2 is fiction.
func _verify_censoring(base: Dictionary, n: int) -> void:
	var vn: int = mini(n, 8)
	print("\n─── 4. VERIFY — real short horizon vs post-hoc censoring (n=%d) ───" % vn)
	var d := 350
	for arm in SC_ARMS:
		## The long rows are the BASELINE's own rows — the same seeds in the same order — so this
		## verifies the exact data §2 reports on rather than a fresh run that merely resembles it.
		var long_rows: Array = (base[arm] as Array).slice(0, vn)
		var short_rows: Array = _arc_arm(arm, vn, d)
		var a: Array = _won_flags(long_rows, d)
		var b: Array = _won_flags(short_rows)
		var mism := 0
		for i in range(vn):
			if bool(a[i]) != bool(b[i]):
				mism += 1
		print("  %-11s censored %d/%d · real-horizon %d/%d · mismatches %d %s" % [
			arm, _count(a), vn, _count(b), vn, mism, "OK" if mism == 0 else "<- FAIL"])
		if mism != 0:
			_sc_ok = false
			_sc_notes.append("⚠️ CANARY: post-hoc censoring disagrees with a real horizon on %s."
				% arm + " §2 is invalid.")


# =============================================================================
# 5. REGIME (b) — A STRICTER LIFESPAN
# =============================================================================
## The perturbation is applied on the ONE seam this probe owns: the training-brain override, which
## the arc calls for every living body every week. The first time a body is seen its lifespan is
## scaled; the flag lives on the instance, which `_reset_career` discards. Nothing global moves.
func _drill_plan_greedy(mi, league_cap: float) -> Dictionary:
	if not is_equal_approx(s_life_mult, 1.0) and mi != null and not mi.has_meta("sc_life"):
		mi.set_meta("sc_life", true)
		_life_base += float(mi.lifespan_years)
		## Floored at 3.0 years: below that a body cannot leave the Baby/Teen stages before
		## retiring and the regime stops being "a shorter career" and becomes "no career".
		mi.lifespan_years = maxf(3.0, float(mi.lifespan_years) * s_life_mult)
		_life_pert += float(mi.lifespan_years)
		_life_n += 1
	return super(mi, league_cap)


func _run_life(base: Dictionary, n: int, mult: float) -> void:
	print("\n─── 5. REGIME (b) — LIFESPAN x %.2f (monsters age out mid-climb) ───" % mult)
	_life_n = 0
	_life_base = 0.0
	_life_pert = 0.0
	s_life_mult = mult
	var res := {}
	for arm in SC_ARMS:
		res[arm] = _arc_arm(arm, n, SC_WEEKS)
	s_life_mult = 1.0
	_regime_table("LIFESPANx%.2f" % mult, base, res, n)
	## LIVENESS — three ways this could silently not bite, all checked.
	print("  canary: bodies touched %d · mean lifespan %.2f -> %.2f yr · retirements %.1f -> %.1f" % [
		_life_n, _life_base / maxf(1.0, float(_life_n)), _life_pert / maxf(1.0, float(_life_n)),
		_mean(base["FLAT"], "retirements"), _mean(res["FLAT"], "retirements")])
	if _life_n == 0 or _life_pert >= _life_base \
			or _mean(res["FLAT"], "retirements") <= _mean(base["FLAT"], "retirements"):
		_sc_ok = false
		_sc_notes.append("⚠️ CANARY: the lifespan regime did not bite (touched %d bodies, retirements"
			% _life_n + " did not rise). Its table is meaningless.")


# =============================================================================
# 6. REGIME (c) — RISING COSTS
# =============================================================================
## `_run_arc` already takes a `feeMult` and `_entry_fee` already RISES with the rung
## (`BASE_FEE + FEE_PER_LEAGUE x idx`), so "entry fees that grow with the ladder" needs no new
## machinery — only a scale on a curve that exists. ⚠️ The Wood waiver survives (`_entry_fee`
## returns 0 at idx 0 when the player cannot pay), so the bottom of the on-ramp is uncloseable by
## this regime by construction. That is a property of the regime, not a kindness of the probe.
func _run_fee(base: Dictionary, n: int, mult: float) -> void:
	print("\n─── 6. REGIME (c) — ENTRY FEES x %.1f (a cost that rises with the rungs) ───" % mult)
	var res := {}
	for arm in SC_ARMS:
		res[arm] = _arc_arm(arm, n, SC_WEEKS, mult)
	_regime_table("FEEx%.0f" % mult, base, res, n)
	print("  canary: fees paid %.0f -> %.0f g · cups refused for fee %.2f -> %.2f · goldEnd %.0f -> %.0f" % [
		_mean(base["FLAT"], "feesPaid"), _mean(res["FLAT"], "feesPaid"),
		_mean(base["FLAT"], "cupsRefusedByFee"), _mean(res["FLAT"], "cupsRefusedByFee"),
		_mean(base["FLAT"], "goldEnd"), _mean(res["FLAT"], "goldEnd")])
	## ⚠️ THE FIRST VERSION OF THIS CANARY WAS WRONG AND IT IS WORTH LEAVING THE REASON WRITTEN
	## DOWN. It asserted that total fees PAID must rise. It falls — hard: at x8 the stable cannot
	## afford the door at all, so it enters fewer cups and pays LESS in total (9299g -> 653g) while
	## being bitten far harder than a canary demanding a rise would ever have detected. "The cost
	## went up" and "more money changed hands" are not the same proposition, and a canary that
	## confuses them fails a live perturbation. The observable that actually tracks the bite is
	## REFUSALS (cups the player could not enter) or a fee bill that rose; either is sufficient.
	var bit: bool = _mean(res["FLAT"], "cupsRefusedByFee") > _mean(base["FLAT"], "cupsRefusedByFee") + 1.0 \
		or _mean(res["FLAT"], "feesPaid") > _mean(base["FLAT"], "feesPaid") * 1.5
	if not bit:
		_sc_ok = false
		_sc_notes.append("⚠️ CANARY: the fee regime did not bite — neither the fee bill nor the"
			+ " count of cups refused for want of the entry fee moved.")


# =============================================================================
# 7. REGIME (e) — RELEGATION: a lost cup costs POSITION, not time
# =============================================================================
## ⚠️ THIS IS THE ONE REGIME THAT IS NOT A CLOCK, AND IT IS HERE BECAUSE THE BRIEF'S KILL-SHOT
## APPLIES TO ALL FOUR OF THE OTHERS. (a)/(b)/(c)/(d) all price the player in WEEKS, and weeks are
## the one axis on which the two policies are ALREADY known to differ — so any of them separates
## the arms by construction and the separation carries no information. Relegation prices the player
## in ROUND WINS, which is the axis `docs/SHAPE_DIAGNOSIS.md`'s integrator addendum measured a real
## competence gap on (top four rungs, per-round 53% flat vs 61% shaped; ADVANCE 30% vs 50%).
## If a fight advantage is ever going to become a career advantage, it has to be priced on the
## thing the fight actually produces.
##
## The rule imposed: a FRONTIER cup won with ZERO rounds gives up the rung. Nothing else changes —
## no fee, no clock, no field change. `Career.league_index` is autoload state and is restored by
## `_reset_career()` at the head of every arc, and the counter below is the canary.
func _fight_cup(idx: int, rounds: int, seed_: int, mult: float = 1.0) -> Dictionary:
	var out: Dictionary = super(idx, rounds, seed_, mult)
	if s_relegate and idx == Career.league_index and Career.league_index > 0 \
			and int(out.get("wins", 0)) == 0:
		Career.league_index -= 1
		_releg_n += 1
	return out


func _run_releg(base: Dictionary, n: int) -> void:
	print("\n─── 7. REGIME (e) — RELEGATION (a frontier cup won with 0 rounds costs the rung) ───")
	_releg_n = 0
	s_relegate = true
	var res := {}
	for arm in SC_ARMS:
		res[arm] = _arc_arm(arm, n, SC_WEEKS)
	s_relegate = false
	_regime_table("RELEG", base, res, n)
	print("  canary: relegations fired %d over %d careers" % [_releg_n, n * SC_ARMS.size()])
	if _releg_n == 0:
		_sc_ok = false
		_sc_notes.append("⚠️ CANARY: relegation never fired — no frontier cup was ever won with zero"
			+ " rounds, so the regime imposed nothing.")


# =============================================================================
# SHARED REGIME REPORT
# =============================================================================
## Every regime answers the same four questions, so they are asked in one place: does it separate
## the arms in COMPLETION, by how much, with what error band, and does the naive on-ramp survive?
func _regime_table(label: String, base: Dictionary, res: Dictionary, n: int) -> void:
	print("  %-11s %-18s %-18s %-9s %-9s %s" % [
		"arm", "WON base (Wilson)", "WON %s" % label, "med wks", "d wks", "paired base->regime"])
	for arm in SC_ARMS:
		var b: Array = base[arm]
		var r: Array = res[arm]
		var bf: Array = _won_flags(b)
		var rf: Array = _won_flags(r)
		var bw: Array = []
		var rw: Array = []
		for a in b:
			if bool(a.get("won", false)):
				bw.append(int(a["weeks"]))
		for a in r:
			if bool(a.get("won", false)):
				rw.append(int(a["weeks"]))
		print("  %-11s %-18s %-18s %-9d %-9d %s" % [
			arm, _wilson(_count(bf), n), _wilson(_count(rf), n),
			_median(rw), _median(rw) - _median(bw), _paired_bin(bf, rf)])
	var fk: int = _count(_won_flags(res["FLAT"]))
	var ck: int = _count(_won_flags(res["COMPETENT"]))
	print("  SEPARATION under %s: COMPETENT - FLAT = %+.0f points (%d/%d vs %d/%d)%s" % [
		label, 100.0 * float(ck - fk) / float(n), ck, n, fk, n,
		"   ⚠️ NAIVE ON-RAMP GONE (<50%)" if float(fk) / float(n) < 0.5 else ""])
	print("  paired FLAT->COMPETENT under %s: %s" % [
		label, _paired_bin(_won_flags(res["FLAT"]), _won_flags(res["COMPETENT"]))])
