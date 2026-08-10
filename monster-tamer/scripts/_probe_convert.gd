## THE CONVERSION PROBE — where does a FIGHT advantage stop being a CAREER advantage?
##
## Four consecutive rounds have ended on the same sentence — "competence buys pace, not access" —
## and none of them established WHY. This probe follows ONE advantage through every hop of the
## pipeline on the SAME seeds and reports the ratio at each:
##
##   per-round win probability -> ADVANCE per cup -> cups per rung -> weeks per rung
##     -> weeks to reach Apex -> Apex sweep probability -> Career.won_game
##
## The deliverable is the single hop at which the ratio collapses to 1.0.
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_convert.tscn -- --all
##   sections:  --fill    (cheap, ~40s)  is ADVANCE available to an UNDER-TRAINED player at all?
##              --rung    (medium)       hops 1-4, controlled: FLAT vs SHAPED at identical total
##              --career  (expensive)    hops 1-6 in situ: two career arms on the same seeds
##      flags:  --seeds N   cups per rung (--rung) / career seeds (--career)
##              --weeks N   career horizon (default 1000)
##
## ⚠️ SUBCLASSES `_probe_shape.gd` (which subclasses `_probe_career_arc.gd`) RATHER THAN COPYING
## EITHER. A second autopilot is this project's most expensive recurring failure. Everything about
## the career loop, the training brains, the team builders and the statistics helpers is inherited;
## this file adds only the tracing.
##
## ⚠️ EVERY SECTION CARRIES A LIVENESS CANARY. Round 10 measured a model against a copy of itself,
## round 11 measured a player with no moves, round 12 measured a subsidised player, round 15
## measured an instrument pinned above its own ceiling. A section whose canary fails prints VOID and
## the probe exits 1.
extends "res://scripts/_probe_shape.gd"

## The rungs the fill-response section samples. Iron is mid-ladder, Platinum is the modal stall,
## Apex is the terminal rung whose rule differs (no dropped round).
const FILL_RUNGS := [4, 7, 10]
const FILL_POINTS := [0.15, 0.25, 0.35, 0.45, 0.55]

## The hypothesis under test quotes "~65 weeks of cupping" as the whole cost of the ladder. This is
## how many weeks of training a player would have had at that point, and it is what the fill probe
## has to price.
const HYPOTHESIS_WEEKS := 65

var _fail := false
var _fights := 0


func _ready() -> void:
	_tree = get_tree()
	print("=== CONVERSION PROBE — at which hop does the advantage die? ===\n")
	var args: Array = OS.get_cmdline_user_args()
	args.append_array(OS.get_cmdline_args())
	var all: bool = "--all" in args
	if all or "--fill" in args:
		_run_fill_response()
	if all or "--rung" in args:
		_run_rung_trace(_arg_int("--seeds", 24))
	if all or "--career" in args:
		_run_career_trace(_arg_int("--seeds", 10), _arg_int("--weeks", 1000))
	print("\n  (%d fights)" % _fights)
	print("=== conversion probe: %s ===" % ("OK" if not _fail else "INSTRUMENT BROKEN"))
	_tree.quit(1 if _fail else 0)


# =============================================================================
# TEAM CONSTRUCTION — one function, two arms, so they cannot silently diverge
# =============================================================================
## FLAT is the parent's `_team_at_fill` (six stats pinned at cap x fill). SHAPED is that EXACT team
## redistributed by the shipped `roster.gd:_shape_to_class`, which is sum-preserving by
## construction, with the kit redrawn onto the class the new stats make. Round 14 measured this as
## the cleanest fight advantage in the game at an identical stat total (+20 points of ADVANCE at
## the top four rungs), which is why it is the advantage this round follows.
##
## ⚠️ `Career.league_index` MUST ALREADY BE `idx`. `_shape_to_class` clamps to `GameData.stat_cap()`
## — the league the game is STANDING IN — so shaping a Masters team while standing at Wood hands
## back six stats clamped to 100, i.e. a flat body wearing a shaped label. Two instruments have
## already been bitten by this (docs/SHAPE_DIAGNOSIS.md B2).
func _conv_team(build: String, idx: int, fill: float, salt: int) -> Array:
	var prev: int = Career.league_index
	Career.league_index = idx
	var cap: float = Career.stat_cap_for_league(idx)
	var size: int = Career.team_size_for_league(idx)
	var team: Array = _team_at_fill(size, cap, fill, salt)
	if build == "shaped":
		if absf(GameData.stat_cap() - cap) > 0.5:
			push_error("conv: cap is %.0f but rung %d wants %.0f — the shape would clamp flat"
				% [GameData.stat_cap(), idx, cap])
			_fail = true
		var rng := RandomNumberGenerator.new()
		rng.seed = 60600 + salt * 41 + idx
		for mi in team:
			mi.recompute_class()
			Roster._shape_to_class(mi, str(mi.class_name_), rng)
			mi.recompute_pools()
			mi.hp = mi.max_hp
			mi.mp = mi.max_mp
	Career.league_index = prev
	return team


## Fight the REAL drawn field of rung `idx` once. Returns {"wins": int, "rounds": int,
## "advanced": bool, "swept": bool}. Uses `make_cup_field` (archetypes), the archetype's own plan
## and orders, and `Career.wins_needed_to_advance` — the rule the ladder actually runs on.
func _conv_cup(build: String, idx: int, fill: float, attempt: int) -> Dictionary:
	var prev_week: int = Career.week
	var prev_idx: int = Career.league_index
	Career.week = 1 + attempt * 4      ## the field seed is month-stable; move it or every attempt
	Career.league_index = idx           ## redraws the identical field
	var rounds: int = maxi(1, Career.rival_count_for_league(idx))
	var field: Array = Career.make_cup_field(idx, rounds)
	var wins := 0
	for r in range(field.size()):
		var team: Array = _conv_team(build, idx, fill, attempt * 11 + r)
		Career.league_index = idx
		var rivals: Array = field[r]["team"]
		for m in team:
			m.reset_for_battle()
		for m in rivals:
			m.reset_for_battle()
		var rng := RandomNumberGenerator.new()
		rng.seed = 41000 + idx * 313 + attempt * 17 + r
		var gid: String = String(field[r].get("archetype", ""))
		var plan_b: Dictionary = TacticsScript.team_plan_for_gameplan(gid, team) if gid != "" else {}
		var orders: Dictionary = TacticsScript.orders_for_gameplan(gid, rivals) if gid != "" else {}
		var sim = BattleSimScript.new(team, rivals, rng.randi(), {}, plan_b, orders)
		_fights += 1
		if str(sim.run().get("winner", "")) == "A":
			wins += 1
	Career.week = prev_week
	Career.league_index = prev_idx
	return {
		"wins": wins, "rounds": rounds,
		"advanced": wins >= Career.wins_needed_to_advance(idx, rounds),
		"swept": wins == rounds,
	}


# =============================================================================
# 1. THE FILL RESPONSE — is ADVANCE even AVAILABLE to an under-trained player?
# =============================================================================
## ⚠️ THIS SECTION EXISTS TO TRY TO DESTROY THE ROUND'S HYPOTHESIS, NOT TO CONFIRM IT.
## The hypothesis is: at the shipped ADVANCE rates (66 79 45 69 65 58 42 23 34 19 13) the expected
## cups to clear eleven rungs is 32.3, ~65 weeks of cupping against careers of 322-502 weeks — so
## the slack is enormous, ADVANCE cannot gate completion, and the career has no failure condition.
##
## THE ASSUMPTION HIDING INSIDE IT: those eleven ADVANCE rates are measured against a player AT
## `expected_climber_fill` for that rung — a player who has already spent the weeks. If ADVANCE
## collapses for an under-trained player, then the 65-week climb is not merely unlikely, it is
## ARITHMETICALLY UNAVAILABLE, and the gate is FILL (i.e. weeks) with the cup as its readout.
##
## Measured here: ADVANCE as a function of player fill at three rungs, plus the fill a player
## actually HAS after `HYPOTHESIS_WEEKS` of the best-known training.
func _run_fill_response() -> void:
	print("─── 1. THE FILL RESPONSE — is a fast climb arithmetically available? ───")
	Career.reset_new_game()
	Roster.reset_to_empty()
	var have: Dictionary = _fill_after_weeks(HYPOTHESIS_WEEKS)
	print("  after %d weeks of the best-known training, ONE monster carries %.0f stat points."
		% [HYPOTHESIS_WEEKS, float(have["total"])])
	print("  %-13s  %5s  %8s  %s" % ["league", "cap", "fill@65w", "expected_climber_fill"])
	for idx in FILL_RUNGS:
		var cap: float = Career.stat_cap_for_league(idx)
		print("  %-13s  %5.0f  %8.3f  %.3f" % [
			Career.league_at(idx).get("name", "?"), cap,
			float(have["total"]) / (6.0 * cap), Career.expected_climber_fill(idx)])
	print("")
	print("  ADVANCE by player fill (flat build, real drawn field, real promotion rule):")
	var head := "  %-13s" % "league"
	for f in FILL_POINTS:
		head += "  %6.2f" % f
	print(head + "   | climber")
	var n: int = 12
	var canary_low := 0.0
	var canary_high := 0.0
	for idx in FILL_RUNGS:
		var row := "  %-13s" % Career.league_at(idx).get("name", "?")
		for f in FILL_POINTS:
			var got := 0
			for a in range(n):
				if bool(_conv_cup("flat", idx, f, a)["advanced"]):
					got += 1
			row += "  %5.0f%%" % (100.0 * float(got) / float(n))
			if idx == FILL_RUNGS[FILL_RUNGS.size() - 1]:
				if absf(f - FILL_POINTS[0]) < 0.001:
					canary_low = float(got) / float(n)
				if absf(f - FILL_POINTS[FILL_POINTS.size() - 1]) < 0.001:
					canary_high = float(got) / float(n)
		var cf: float = Career.expected_climber_fill(idx)
		var cg := 0
		for a in range(n):
			if bool(_conv_cup("flat", idx, cf, a)["advanced"]):
				cg += 1
		print(row + "   | %4.0f%% @ %.2f" % [100.0 * float(cg) / float(n), cf])
	print("  (n=%d cups per cell; a proportion at n=12 carries about +/-14 points.)" % n)
	## ⚠️ LIVENESS: fill must MOVE advance at the terminal rung. If the lowest and highest fill read
	## the same, this instrument is not measuring fill and nothing above it is quotable.
	if absf(canary_high - canary_low) < 0.15:
		print("  CANARY VOID: fill %.2f -> %.2f moved ADVANCE only %.0f -> %.0f points at Apex."
			% [FILL_POINTS[0], FILL_POINTS[FILL_POINTS.size() - 1], canary_low * 100.0,
			canary_high * 100.0])
		_fail = true
	else:
		print("  canary OK: fill moves ADVANCE at the terminal rung by %.0f points."
			% (100.0 * absf(canary_high - canary_low)))


## What ONE monster's six stats total after `weeks` of the best-known training, at a cap high
## enough not to bind. Uses the SHIPPED weekly tick (`week.gd:apply_activity`) and the parent's own
## FLAT brain — no second copy of the training model, which is how round 10's probe lied.
func _fill_after_weeks(weeks: int) -> Dictionary:
	var before := s_brain
	s_brain = "flat"
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var mi = GameData.make_monster(Art.ROSTER[0], 0.0, rng)
	var cap := 1100.0
	for w in range(weeks):
		mi.happiness = 8
		mi.fed_this_week = true
		var plan: Dictionary = _drill_plan_greedy(mi, cap)
		if str(plan["mode"]) == "train":
			WeekLib.apply_activity(mi, {"kind": "train", "drillId": str(plan["id"])},
				0, cap, "Tamers Apex")
		else:
			WeekLib.apply_activity(mi, {"kind": "rest"}, 0, cap, "Tamers Apex")
	s_brain = before
	var sum := 0.0
	for s in Classify.STATS:
		sum += float(mi.stats.get(s, 0.0))
	return {"total": sum}


# =============================================================================
# 2. THE RUNG TRACE — hops 1-4, controlled
# =============================================================================
## Two arms at an IDENTICAL stat total, the same rivals, the same battle seeds. Per rung:
##   hop 1  per-ROUND win probability
##   hop 2  ADVANCE per cup
##   hop 3  cups needed per rung = 1 / ADVANCE
##   hop 4  weeks per rung = cups x (travel weeks + the cadence a player waits between cups)
## The ratio SHAPED/FLAT is printed at every hop. Hops 2->3 are algebraically the same quantity
## inverted, and 3->4 multiplies by a constant that is identical in both arms — so if the ratio
## survives hop 1 it MUST survive to hop 4. That is the point: any collapse before the career must
## therefore be at hop 1->2, and any collapse after hop 4 cannot be about the cup at all.
func _run_rung_trace(n: int) -> void:
	print("\n─── 2. THE RUNG TRACE — hops 1-4 at an identical stat total (%d cups/rung) ───" % n)
	Career.reset_new_game()
	Roster.reset_to_empty()
	_shape_audit()
	print("  %-13s %5s | %-13s | %-13s | %-13s | %s" % [
		"league", "fill", "hop1 round win", "hop2 ADVANCE", "hop3 cups", "hop4 cup-weeks"])
	var acc := {"flat": [0, 0, 0], "shaped": [0, 0, 0]}   ## [round wins, rounds, advances]
	var cups := 0
	var wk_f := 0.0
	var wk_s := 0.0
	for idx in range(Career.leagues.size()):
		var fill: float = Career.expected_climber_fill(idx)
		var r: Dictionary = {}
		for build in ["flat", "shaped"]:
			var rw := 0
			var rn := 0
			var adv := 0
			for a in range(n):
				var c: Dictionary = _conv_cup(build, idx, fill, a)
				rw += int(c["wins"])
				rn += int(c["rounds"])
				if bool(c["advanced"]):
					adv += 1
			r[build] = {"rw": rw, "rn": rn, "adv": adv}
			acc[build][0] += rw
			acc[build][1] += rn
			acc[build][2] += adv
		cups += n
		var pf: float = float(r["flat"]["rw"]) / maxf(1.0, float(r["flat"]["rn"]))
		var ps: float = float(r["shaped"]["rw"]) / maxf(1.0, float(r["shaped"]["rn"]))
		var af: float = float(r["flat"]["adv"]) / float(n)
		var as_: float = float(r["shaped"]["adv"]) / float(n)
		var cf: float = 1.0 / maxf(0.02, af)
		var cs: float = 1.0 / maxf(0.02, as_)
		var wpc: float = float(CupRun.weeks_for_cup(idx, Career.rival_count_for_league(idx)))
		wk_f += cf * wpc
		wk_s += cs * wpc
		print("  %-13s %5.2f | %5.0f%% %5.0f%% | %5.0f%% %5.0f%% | %5.1f %5.1f | %5.1f %5.1f" % [
			Career.league_at(idx).get("name", "?"), fill,
			pf * 100.0, ps * 100.0, af * 100.0, as_ * 100.0, cf, cs, cf * wpc, cs * wpc])
	print("")
	var PF: float = float(acc["flat"][0]) / maxf(1.0, float(acc["flat"][1]))
	var PS: float = float(acc["shaped"][0]) / maxf(1.0, float(acc["shaped"][1]))
	var AF: float = float(acc["flat"][2]) / maxf(1.0, float(cups))
	var AS: float = float(acc["shaped"][2]) / maxf(1.0, float(cups))
	print("  POOLED  hop1 round win  FLAT %s   SHAPED %s   ratio %.2fx"
		% [_wilson(acc["flat"][0], acc["flat"][1]), _wilson(acc["shaped"][0], acc["shaped"][1]),
		PS / maxf(0.001, PF)])
	print("  POOLED  hop2 ADVANCE    FLAT %s   SHAPED %s   ratio %.2fx"
		% [_wilson(acc["flat"][2], cups), _wilson(acc["shaped"][2], cups), AS / maxf(0.001, AF)])
	print("  SUMMED  hop4 CUP-WEEKS for the whole climb  FLAT %.0f   SHAPED %.0f   ratio %.2fx"
		% [wk_f, wk_s, wk_s / maxf(0.001, wk_f)])
	## ⚠️ LIVENESS: the two arms must be the same points arranged two ways. If the totals differ the
	## comparison is not sum-preserving and every ratio above is a statement about strength.
	if not _shape_audit_ok:
		print("  CANARY VOID: the two arms do not carry the same stat total.")
		_fail = true


var _shape_audit_ok := false

## Prints, and asserts, that SHAPED is FLAT rearranged: same total, much bigger spread, kit moved.
func _shape_audit() -> void:
	var idx := 7
	Career.league_index = idx
	var a: Array = _conv_team("flat", idx, Career.expected_climber_fill(idx), 3)
	var b: Array = _conv_team("shaped", idx, Career.expected_climber_fill(idx), 3)
	var ta := 0.0
	var tb := 0.0
	var sa := 0.0
	var sb := 0.0
	for i in range(mini(a.size(), b.size())):
		var hia := -INF
		var loa := INF
		var hib := -INF
		var lob := INF
		for s in Classify.STATS:
			var va: float = float(a[i].stats.get(s, 0.0))
			var vb: float = float(b[i].stats.get(s, 0.0))
			ta += va
			tb += vb
			hia = maxf(hia, va); loa = minf(loa, va)
			hib = maxf(hib, vb); lob = minf(lob, vb)
		sa += (hia - loa) / maxf(1.0, ta / 6.0)
		sb += (hib - lob) / maxf(1.0, tb / 6.0)
	Career.league_index = 0
	var drift: float = 100.0 * (tb / maxf(1.0, ta) - 1.0)
	print("  audit @ Platinum: stat total %.0f -> %.0f (%+.2f%%) · spread %.2f -> %.2f"
		% [ta, tb, drift, sa, sb])
	_shape_audit_ok = absf(drift) < 1.0 and sb > sa * 2.0


# =============================================================================
# 3. THE CAREER TRACE — hops 1-6 in situ, on the same seeds
# =============================================================================
## ⚠️ THE CONTROLLED TRACE ABOVE MEASURES THE ADVANTAGE AT A FIXED RUNG AND A FIXED FILL. A real
## career holds NEITHER fixed: a stronger player promotes sooner, and the field is priced by RUNG,
## so it stands against a harder field at every calendar week. This section measures whether the
## advantage SURVIVES that — the same two training brains, played through the shipped autopilot on
## identical seeds, with the realised per-round win rate read out of the career itself.
##
## If the in-career round win rate is the same in both arms while the weeks differ, the advantage
## is being spent on POSITION rather than banked as MARGIN, and that is the whole answer.
func _run_career_trace(n: int, weeks: int) -> void:
	print("\n─── 3. THE CAREER TRACE — hops 1-6 in situ (%d seeds x %d weeks) ───" % [n, weeks])
	var arms := {"FLAT": "flat", "SHAPED": "apt", "SPIKE": "spike"}
	var order := ["FLAT", "SHAPED", "SPIKE"]
	var res := {}
	for arm in order:
		res[arm] = _career_arm(arm, String(arms[arm]), n, weeks)
	print("")
	print("  %-8s  %-14s  %-9s  %-9s  %-9s  %-9s  %-8s  %s" % [
		"arm", "hop1 round win", "hop2 prom/cup", "hop3 cups/car", "hop4 wks", "hop4 ->Apex",
		"hop5 Apex", "hop6 WON"])
	for arm in order:
		var r: Dictionary = res[arm]
		print("  %-8s  %-14s  %-8.0f%%  %-9.1f  %-9d  %-9s  %-8s  %s" % [
			arm, "%.0f%% (n=%d)" % [100.0 * float(r["roundWin"]), int(r["rounds"])],
			100.0 * float(r["advance"]), float(r["cups"]), int(r["medWeeks"]),
			("%d" % int(r["medToApex"])) if int(r["reachedApex"]) > 0 else "—",
			"%d/%d" % [int(r["apexSweeps"]), int(r["apexCups"])],
			_wilson(int(r["won"]), n)])
	print("")
	var f: Dictionary = res["FLAT"]
	for arm in ["SHAPED", "SPIKE"]:
		var s: Dictionary = res[arm]
		print("  ── THE RATIO AT EVERY HOP (%s / FLAT) ──" % arm)
		_hop("hop1  per-round win probability", float(s["roundWin"]), float(f["roundWin"]))
		_hop("hop2  promotions per cup entered", float(s["advance"]), float(f["advance"]))
		_hop("hop3  cups per career (lower is better)", float(f["cups"]), float(s["cups"]))
		_hop("hop4  weeks to finish (lower is better)", float(f["medWeeks"]), float(s["medWeeks"]))
		_hop("hop4b weeks to REACH Apex (lower is better)",
			float(f["medToApex"]), float(s["medToApex"]))
		_hop("hop5  Apex sweep probability",
			float(s["apexSweeps"]) / maxf(1.0, float(s["apexCups"])),
			float(f["apexSweeps"]) / maxf(1.0, float(f["apexCups"])))
		_hop("hop6  Career.won_game", float(s["won"]), maxf(0.001, float(f["won"])))
		_paired(f, s, "FLAT", arm, n)
		print("")
	var s: Dictionary = res["SHAPED"]
	print("  ── what ENDED the careers that did not win ──")
	for arm in order:
		var r: Dictionary = res[arm]
		print("  %-8s  lost %d/%d · median gold %d · empty stalls %.1f · blocked wks %.1f · %s"
			% [arm, n - int(r["won"]), n, int(r["lostGold"]), float(r["lostEmpty"]),
			float(r["lostBlocked"]), str(r["stall"])])
	## ⚠️ LIVENESS: the two arms must actually be different players. Round 14 measured FLAT at a
	## stat spread of 0.12 and the shaped brain at 1.10; if they land together the arm did nothing.
	if float(s["spread"]) < float(f["spread"]) * 3.0:
		print("  CANARY VOID: shaped spread %.2f vs flat %.2f — the training brain did not bite."
			% [float(s["spread"]), float(f["spread"])])
		_fail = true
	else:
		print("  canary OK: stat spread FLAT %.2f vs SHAPED %.2f — the arms are different players."
			% [float(f["spread"]), float(s["spread"])])


func _hop(label: String, num: float, den: float) -> void:
	var ratio: float = num / maxf(0.0001, den)
	var verdict := "COLLAPSED to 1.0" if absf(ratio - 1.0) < 0.06 else (
		"alive" if ratio > 1.0 else "REVERSED")
	print("  %-44s %6.2fx   %s" % [label, ratio, verdict])


func _career_arm(arm: String, brain: String, n: int, weeks: int) -> Dictionary:
	s_brain = brain
	apply_policy("NAIVE")
	var won := 0
	var wks: Array = []
	var to_apex: Array = []
	var reached_apex := 0
	var rounds := 0
	var round_wins := 0
	var cups := 0
	var advances := 0
	var apex_cups := 0
	var apex_sweeps := 0
	var spread := 0.0
	var wonflags: Array = []
	var reached: Array = []
	var lost_gold: Array = []
	var lost_empty := 0.0
	var lost_blocked := 0.0
	var lost_n := 0
	var stalls := {}
	for si in range(n):
		p_seed = int(MORE_SEEDS[si % MORE_SEEDS.size()])
		var a: Dictionary = _run_arc(weeks, {})
		var w: bool = bool(a.get("won", false))
		if w:
			won += 1
		wonflags.append(w)
		wks.append(int(a["weeks"]))
		reached.append(int(a["finalLeague"]))
		spread += float(a["shapeSpread"])
		rounds += int(a["rounds"])
		round_wins += int(a["roundWins"])
		cups += int(a["cups"])
		## Promotions are the ADVANCEs that mattered — one per rung cleared, plus the terminal win.
		advances += int(a["finalLeague"]) + (1 if w else 0)
		var pl: Array = a["perLeague"]
		## weeks to REACH Apex: every week booked below the final rung. Travel weeks are counted
		## against the career total, not against a rung, so this is training/idle weeks only —
		## comparable between arms, which is all a RATIO needs.
		var below := 0
		for i in range(mini(10, pl.size())):
			below += int(pl[i]["weeks"])
		if int(a["finalLeague"]) >= 10:
			reached_apex += 1
			to_apex.append(below)
			apex_cups += int(pl[10]["cups"])
			if w:
				apex_sweeps += 1
		if not w:
			lost_n += 1
			lost_gold.append(int(a["goldEnd"]))
			lost_empty += float(a["emptySlots"])
			lost_blocked += float(a["frontierBlockedWeeks"])
			var sr: String = str(a.get("stall", ""))
			if sr == "":
				sr = "ran out of weeks"
			stalls[sr] = int(stalls.get(sr, 0)) + 1
		print("    %-8s seed %-9d -> %-12s wk %4d %s  rounds %d/%d  cups %d  spread %.2f" % [
			arm, p_seed, str(Career.league_at(int(a["finalLeague"])).get("name", "?")),
			int(a["weeks"]), "WON " if w else "    ",
			int(a["roundWins"]), int(a["rounds"]), int(a["cups"]), float(a["shapeSpread"])])
	s_brain = "flat"
	apply_policy("NAIVE")
	var modal := "—"
	var modal_n := 0
	for k in stalls:
		if int(stalls[k]) > modal_n:
			modal_n = int(stalls[k])
			modal = "%s (x%d)" % [k, modal_n]
	return {
		"won": won, "wonFlags": wonflags, "weeks": wks, "reached": reached,
		"medWeeks": _median(wks), "medToApex": _median(to_apex), "reachedApex": reached_apex,
		"roundWin": float(round_wins) / maxf(1.0, float(rounds)), "rounds": rounds,
		"advance": float(advances) / maxf(1.0, float(cups)),
		"cups": float(cups) / float(n),
		"apexCups": apex_cups, "apexSweeps": apex_sweeps,
		"spread": spread / float(n),
		"lostGold": _median(lost_gold) if lost_n > 0 else 0,
		"lostEmpty": lost_empty / maxf(1.0, float(lost_n)),
		"lostBlocked": lost_blocked / maxf(1.0, float(lost_n)),
		"stall": modal,
	}
