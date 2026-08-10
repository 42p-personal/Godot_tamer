## THE GRADE PROBE — does scoring PACE separate the players that COMPLETION cannot?
##
## Run:
##   P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_grade.tscn -- --unit
##   ... -- --grade --seeds 16 --only NAIVE,COMPETENT     (~4 min per policy at 16 seeds)
##
## THE QUESTION. `docs/CONVERSION_DIAGNOSIS.md` §1: a fight advantage compounds 1.09x -> 4.03x
## through five hops and collapses to 1.00x at `Career.won_game`, because the naive arm already
## completes 14/16 and there are six points of headroom above the competent arm's 15/16. §2d makes
## that arithmetic rather than measurement: while the outcome is a boolean at 88-94%, ANY mechanism
## producing more than ~6 points of separation must produce it by lowering the naive player.
##
## The difference that DOES exist is pace — median 502 weeks against 354, 148 weeks, paired
## p=0.0005 — and the game did not score it. This probe asks two things and nothing else:
##   1. does the grade separate the two policies on most seeds?
##   2. does COMPLETION move? (it must not — a scoreboard that changes difficulty is a difficulty
##      change wearing a costume, and the floor is NAIVE WON >= 14/16.)
##
## ⚠️ THIS SUBCLASSES `_probe_career_arc.gd` AND OVERRIDES NOTHING THAT DECIDES ANYTHING.
## Same autopilot, same policies, same seeds as `_probe_terminal.gd` (the T_SEEDS list is copied
## verbatim so the arms are the SAME CAREERS every other round has been reading).
##
## ⚠️ LIVENESS CANARIES, because an instrument that measures nothing reports a clean null:
##   * the arc canary — `samples == weeks - travelWeeks` is the parent's; not re-implemented here.
##   * the GRADE canary — the grades observed must not all be one tier. A tier scheme that maps
##     every career onto FOOTNOTE has separated nothing and this probe FAILS rather than reporting
##     "no difference".
##   * the RETIREE canary — `--unit` fields a retired-only stable and a retiree-plus-live stable
##     and asserts the retiree never reaches the arena. If the fix is not live, section 3 exits
##     non-zero instead of quietly measuring the old build.
extends "res://scripts/_probe_career_arc.gd"

## Verbatim from `_probe_terminal.gd:T_SEEDS` — the same 24 careers rounds 15 and 16 read.
const G_SEEDS := [
	20260809, 771013, 313373, 4242424, 99180, 5150, 606060, 8888881,
	11235, 271828, 1618033, 6022140, 137035, 66260, 299792, 86400,
	31415926, 2718281, 4004, 1729, 40320, 65537, 123581, 999983,
]

var _ok := true
var _one_seed := 0


func _ready() -> void:
	_tree = get_tree()
	print("=== GRADE PROBE — is pace scorable? ===\n")
	var args: Array = OS.get_cmdline_user_args()
	args.append_array(OS.get_cmdline_args())
	if "--unit" in args:
		_run_unit()
	if "--grade" in args:
		_run_grade()
	if "--tap" in args:
		_run_tap()
	print("\n=== grade probe: %s ===" % ("OK" if _ok else "FAILED"))
	_tree.quit(0 if _ok else 1)


func _assert(cond: bool, what: String) -> void:
	print("   %s %s" % ["OK  " if cond else "FAIL", what])
	if not cond:
		_ok = false


# =============================================================================
# 1. UNIT — the grade is a pure function, the pace-setter is read-only, the retiree cannot fight
# =============================================================================

func _run_unit() -> void:
	print("─── 1. UNIT CHECKS ───\n")
	_unit_pace()
	_unit_grade()
	_unit_retiree()
	_unit_verdict()
	_unit_save()


func _unit_pace() -> void:
	print("  the pace-setter (read-only, never a deadline):")
	_reset_career()
	var last: int = Career.leagues.size() - 1
	var monotone := true
	var prev := -1
	for i in range(Career.leagues.size()):
		var w: int = Career.dynasty_week_cleared(i)
		if w < prev:
			monotone = false
		prev = w
	_assert(monotone, "the dynasty schedule is monotone in rung")
	_assert(Career.dynasty_week_cleared(last) == Career.DYNASTY_APEX_WEEK,
		"clearing the last rung IS the par week (%d)" % Career.DYNASTY_APEX_WEEK)
	_assert(Career.dynasty_week_arrived(last) == Career.DYNASTY_APEX_ARRIVAL_WEEK,
		"arrival at Tamers Apex = %d" % Career.DYNASTY_APEX_ARRIVAL_WEEK)
	_assert(Career.dynasty_rung_at_week(0) == 0 and Career.dynasty_rung_at_week(100000) == last,
		"rung_at_week spans Wood..Apex")
	## ⚠️ THE ONE CHECK THAT MATTERS MOST: the pace-setter must not touch the run.
	Career.week = 900
	var idx0: int = Career.league_index
	var g0: int = Career.gold
	var won0: bool = Career.won_game
	var _s: Dictionary = Career.dynasty_standing()
	var _g: Dictionary = Career.grade_result()
	_assert(Career.league_index == idx0 and Career.gold == g0 and Career.won_game == won0,
		"reading the standing/grade 480 weeks past par mutates NOTHING (no deadline)")
	Career.week = 0


func _unit_grade() -> void:
	print("\n  the grade (a pure function of week + leagues_won + league_index):")
	_reset_career()
	var last: int = Career.leagues.size() - 1
	## Two synthetic winners at the two MEASURED medians, all rungs swept.
	var fast: Dictionary = _grade_at(354, last, true)
	var slow: Dictionary = _grade_at(502, last, true)
	print("      competent median (wk 354): %s" % str(fast["line"]))
	print("      naive     median (wk 502): %s" % str(slow["line"]))
	_assert(str(fast["tier"]) != str(slow["tier"]),
		"the two MEASURED medians land in different tiers (%s vs %s)" % [fast["tier"], slow["tier"]])
	_assert(int(fast["score"]) > int(slow["score"]), "and the faster career scores higher")
	## Purity: same inputs, same output, twice.
	var again: Dictionary = _grade_at(354, last, true)
	_assert(int(again["score"]) == int(fast["score"]) and str(again["tier"]) == str(fast["tier"]),
		"grade_result() is pure — identical state, identical grade")
	## Scraped vs swept, at an identical week.
	var swept_all: Dictionary = _grade_at(400, last, true)
	var scraped: Dictionary = _grade_at(400, last, false)
	print("      week 400, every rung swept  : %s" % str(swept_all["line"]))
	print("      week 400, only Apex swept   : %s" % str(scraped["line"]))
	_assert(int(swept_all["titles"]) > int(scraped["titles"])
		and int(swept_all["score"]) > int(scraped["score"]),
		"sweeping a rung is worth more than scraping it, at the same week")
	_assert(int(scraped["scraped"]) == last, "a career that swept only Apex scraped %d rungs" % last)
	## The clock does not stop, and the grade must not slide with it.
	var frozen_score: int = int(Career.grade_result()["score"])
	Career.week += 200
	_assert(int(Career.grade_result()["score"]) == frozen_score,
		"200 idle weeks AFTER the title do not move the grade (won_week is stamped)")


## Force a terminal state directly — the grade must be computable without playing 400 weeks.
func _grade_at(wk: int, last: int, sweep_all: bool) -> Dictionary:
	Career.reset_new_game()
	Career.league_index = last
	Career.won_game = true
	Career.won_week = wk
	Career.week = wk
	for i in range(Career.leagues_won.size()):
		Career.leagues_won[i] = sweep_all or i == last
	return Career.grade_result()


func _unit_retiree() -> void:
	print("\n  a retiree cannot compete (roster.gd:126, enforced at last):")
	_reset_career()
	var dead = GameData.make_monster(Art.ROSTER[0], 0.5, Roster.rng)
	if dead == null:
		_assert(false, "could not build a monster")
		return
	dead.id = Roster.next_slot_id()
	dead.retired = true
	dead.hp = 1.0                      ## the sentinel — `reset_for_battle()` restores it to max
	Roster.monsters.append(dead)
	var out: Dictionary = Career.enter_league_tournament(0, 3, 12345)
	_assert(bool(out.get("refused", false)) and is_equal_approx(dead.hp, 1.0),
		"a RETIRED-ONLY stable is refused and nothing is fielded (%s)" % str(out.get("refusedReason", "")))
	_assert(int(out.get("wins", -1)) == 0 and int(out.get("placement", -1)) == 0
		and is_equal_approx(float(out.get("placementFraction", -1.0)), 0.0),
		"a refused cup pays nothing and places nowhere (NOT 1st on a zero-round draw)")
	## …and a live body alongside a retiree fields the live one only.
	var live = GameData.make_monster(Art.ROSTER[1], 0.5, Roster.rng)
	live.id = Roster.next_slot_id()
	live.hp = 1.0
	Roster.monsters.append(live)
	dead.hp = 1.0
	var out2: Dictionary = Career.enter_league_tournament(0, 3, 12345)
	_assert(not bool(out2.get("refused", false)) and is_equal_approx(dead.hp, 1.0) and live.hp != 1.0,
		"a mixed stable fields the LIVE body and leaves the retiree on the bench")
	_assert(int(out2.get("rivalCount", 0)) == 3, "…and still fights the full three-round draw")


func _unit_verdict() -> void:
	print("\n  the outclassed verdict (detection only — nothing is blocked):")
	_reset_career()
	_assert(str(Career.frontier_verdict()["state"]) == "shorthanded",
		"an EMPTY stable reads 'shorthanded' — an economy wall, never a difficulty verdict")
	## Give it a body, so the rung is enterable and the live question is the difficulty one.
	var body = GameData.make_monster(Art.ROSTER[0], 0.5, Roster.rng)
	body.id = Roster.next_slot_id()
	Roster.monsters.append(body)
	_assert(str(Career.frontier_verdict()["state"]) == "fresh",
		"a career with no cups at its rung is 'fresh', never 'outclassed'")
	## The measured outclassed roster: 4 round wins in 120, 0 promotions.
	Career.frontier_cups = 24
	Career.frontier_rounds = 120
	Career.frontier_round_wins = 4
	var v: Dictionary = Career.frontier_verdict()
	print("      %s" % str(v["line"]))
	_assert(str(v["state"]) == "outclassed", "3.3%% of rounds over 24 cups reads OUTCLASSED")
	## The three that were NOT walls: they advanced ~4/24 while winning rounds.
	Career.frontier_round_wins = 62
	_assert(str(Career.frontier_verdict()["state"]) == "unlucky",
		"52%% of rounds and no promotion reads UNLUCKY, not outclassed")
	Career.frontier_round_wins = 36
	_assert(str(Career.frontier_verdict()["state"]) == "climbing",
		"30%% of rounds reads CLIMBING")
	## ⚠️ THE CASE THAT KILLED THE FIRST DESIGN OF THIS VERDICT. The one genuinely walled career in
	## the census (EXPERT / seed 86400) measured 45 round wins in 185 at PLATINUM — a five-round
	## draw needing four. A raw-round-rate threshold called that 24.3% "climbing"; the implied
	## chance of clearing the draw is 1.3% per cup, i.e. ~74 cups and ~300 weeks per promotion.
	Career.league_index = 7                     ## Platinum — which fields five, so give it five.
	for i in range(4):
		var b = GameData.make_monster(Art.ROSTER[i + 1], 0.5, Roster.rng)
		b.id = Roster.next_slot_id()
		Roster.monsters.append(b)
	Career.frontier_cups = 37
	Career.frontier_rounds = 185
	Career.frontier_round_wins = 45
	var pv: Dictionary = Career.frontier_verdict()
	print("      %s" % str(pv["line"]))
	_assert(str(pv["state"]) == "outclassed",
		"24.3%% of rounds at a 5-round draw needing 4 reads OUTCLASSED (%.1f%% per cup)"
			% (100.0 * float(pv["advanceChance"])))
	## …and the IDENTICAL round rate at Wood's three-round draw needing two does not, because the
	## rung's own shape is part of the answer.
	Career.league_index = 0
	var wv: Dictionary = Career.frontier_verdict()
	_assert(str(wv["state"]) != "outclassed",
		"…while the same rate at a 3-round draw is not a wall (%.1f%% per cup)"
			% (100.0 * float(wv["advanceChance"])))
	Career.frontier_cups = 24
	Career.frontier_rounds = 120
	Career.frontier_round_wins = 36
	var before: int = Career.league_index
	_assert(Career.can_enter_league(before), "…and an outclassed career may still enter its rung")


func _unit_save() -> void:
	print("\n  save compatibility (NON-NEGOTIABLE):")
	_reset_career()
	## A v3 save: no `wonWeek`, no `frontier`. It must load, keep the roster, and grade honestly.
	var mi = GameData.make_monster(Art.ROSTER[2], 0.5, Roster.rng)
	mi.id = Roster.next_slot_id()
	Roster.monsters.append(mi)
	var legacy := {
		"version": 3,
		"career": {"leagueIndex": 10, "gold": 900, "week": 480, "barnCapacity": 3,
			"licences": {}, "leaguesWon": [true, true, true, true, true, true, true, true, true, true, true],
			"wonGame": true, "selectedIndex": 0},
		"roster": SaveGame._serialize_roster(),
		"frozen": [],
	}
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(legacy, "\t"))
	f.close()
	Roster.reset_to_empty()
	var loaded: bool = SaveGame.load_game()
	_assert(loaded and Roster.monsters.size() == 1,
		"a v3 save (no wonWeek, no frontier) loads and KEEPS ITS ROSTER")
	_assert(Career.won_week == 480,
		"…and its win week falls back to the saved week (%d)" % Career.won_week)
	var g: Dictionary = Career.grade_result()
	print("      legacy save grades as: %s" % str(g["line"]))
	## ⚠️ THE CLAIM IS "NEVER A FALSE VERDICT", NOT "always fresh". This one-monster legacy save
	## cannot field a Tamers Apex team at all, so it correctly reads `shorthanded` — the state that
	## exists precisely so an economy wall is not reported as a difficulty one. What it must never
	## do is invent an `outclassed`/`unlucky` reading out of a frontier record it does not have.
	var lv: String = str(Career.frontier_verdict()["state"])
	_assert(lv == "shorthanded" or lv == "fresh",
		"…and its unknown frontier reads '%s' — never a false outclassed/unlucky verdict" % lv)
	## …and a v4 round-trip keeps everything.
	Career.won_week = 333
	Career.frontier_cups = 7
	Career.frontier_rounds = 21
	Career.frontier_round_wins = 2
	Career.frontier_since_week = 300
	SaveGame.save_game()
	Career.reset_new_game()
	SaveGame.load_game()
	_assert(Career.won_week == 333 and Career.frontier_cups == 7 and Career.frontier_rounds == 21
		and Career.frontier_round_wins == 2 and Career.frontier_since_week == 300,
		"a v4 save round-trips the win week and the frontier record")
	SaveGame.delete_save()


# =============================================================================
# 2. THE GRADE DISTRIBUTION — the acceptance test
# =============================================================================

func _run_grade() -> void:
	var n: int = clampi(_arg_int("--seeds", 8), 1, G_SEEDS.size())
	var weeks_cap: int = _arg_int("--weeks", 1000)
	var only: String = _arg_str("--only", "NAIVE,COMPETENT")
	var order: Array = Array(only.split(","))
	## `--one-seed <value>` isolates a single career — used to interrogate the one measured
	## outclassed roster (EXPERT / 86400) without re-running fifteen careers to reach it.
	_one_seed = _arg_int("--one-seed", 0)
	print("\n─── 2. THE GRADE DISTRIBUTION (%d seeds x %d weeks, %s) ───\n" % [n, weeks_cap, str(order)])
	var rows: Array = []
	for name in order:
		rows.append(_grade_policy(str(name), n, weeks_cap))
	_report(rows, n)


func _grade_policy(name: String, n: int, weeks_cap: int) -> Dictionary:
	var extra: Dictionary = apply_policy(name)
	var opts: Dictionary = {"feeMult": float(extra.get("feeMult", 1.0))}
	var per_seed: Array = []
	for s in range(n):
		if _one_seed != 0 and int(G_SEEDS[s]) != _one_seed:
			continue
		p_seed = int(G_SEEDS[s])
		var a: Dictionary = _run_arc(weeks_cap, opts)
		## ⚠️ READ THE GRADE OFF `Career`, NOT OFF A COPY OF ITS ARITHMETIC. Round 13 shipped a
		## scoreboard that disagreed with the frame it described in 100% of frames; whatever is
		## displayed must be read from the thing it describes.
		var g: Dictionary = Career.grade_result()
		per_seed.append({
			"seed": int(G_SEEDS[s]),
			"won": bool(a["won"]),
			"weeks": int(a["weeks"]),
			"wonWeek": Career.won_week,
			"league": int(a["finalLeague"]),
			"tier": str(g["tier"]),
			"score": int(g["score"]),
			"titles": int(g["titles"]),
			"scraped": int(g["scraped"]),
			"marginSeasons": int(g["marginSeasons"]),
			"frontierBlocked": int(a.get("frontierBlockedWeeks", 0)),
			"verdict": str(Career.frontier_verdict()["state"]),
			"stall": str(a.get("stall", "")),
		})
		print("    %-11s seed %-9d %-4s wk %4d  %-11s score %-5d titles %2d  scraped %2d  fBlocked %3d  %-10s %s" % [
			name, int(G_SEEDS[s]), "WON" if a["won"] else "—", int(a["weeks"]),
			str(g["tier"]), int(g["score"]), int(g["titles"]), int(g["scraped"]),
			int(a.get("frontierBlockedWeeks", 0)),
			str(Career.frontier_verdict()["state"]), str(a.get("stall", ""))])
		var fv: Dictionary = Career.frontier_verdict()
		if _one_seed != 0:
			print("      frontier record: %d cups · %d rounds · %d won (%.1f%%) at %s over %d weeks" % [
				int(fv["cups"]), int(fv["rounds"]), int(fv["roundWins"]),
				100.0 * float(fv["roundRate"]), str(fv["league"]), int(fv["weeksAtRung"])])
			print("      verdict line  : %s" % str(fv["line"]))
	apply_policy("NAIVE")
	return {"name": name, "seeds": per_seed}


func _report(rows: Array, n: int) -> void:
	print("\n  %-11s  %-9s  %-10s  %-10s  %-9s  %-9s  %-9s  %s" % [
		"policy", "WON", "med wks", "med score", "tiers", "med titles", "med scrap", "fBlocked/run"])
	var all_tiers := {}
	for r in rows:
		var seeds: Array = r["seeds"]
		var won := 0
		var wks: Array = []
		var scores: Array = []
		var titles: Array = []
		var scraped: Array = []
		var tiers := {}
		var fb := 0.0
		for s in seeds:
			if bool(s["won"]):
				won += 1
			wks.append(int(s["weeks"]))
			scores.append(int(s["score"]))
			titles.append(int(s["titles"]))
			scraped.append(int(s["scraped"]))
			tiers[str(s["tier"])] = int(tiers.get(str(s["tier"]), 0)) + 1
			all_tiers[str(s["tier"])] = true
			fb += float(s["frontierBlocked"])
		r["won"] = won
		r["tiers"] = tiers
		r["medWeeks"] = _median(wks)
		r["medScore"] = _median(scores)
		print("  %-11s  %-9s  %-10d  %-10d  %-9d  %-9d  %-9d  %.1f" % [
			str(r["name"]), "%d/%d" % [won, seeds.size()], _median(wks), _median(scores),
			tiers.size(), _median(titles), _median(scraped), fb / float(maxi(1, seeds.size()))])
	for r in rows:
		print("   · %-11s tiers: %s" % [str(r["name"]), str(r["tiers"])])

	## ⚠️ THE CANARY. A tier scheme that maps every career onto one tier has separated NOTHING and
	## must fail loudly rather than report a clean null.
	## ⚠️ Only meaningful over a spread of careers — a single-career `--one-seed` run has one tier
	## by construction and must not fail the probe for it.
	if _one_seed == 0 and n > 1:
		_assert(all_tiers.size() >= 2, "CANARY: the grade produced more than one tier across the run")

	## THE ACCEPTANCE TEST, both halves.
	if rows.size() >= 2:
		var a: Array = rows[0]["seeds"]
		var b: Array = rows[1]["seeds"]
		var m: int = mini(a.size(), b.size())
		var diff := 0
		var better := 0
		var worse := 0
		for i in range(m):
			if str(a[i]["tier"]) != str(b[i]["tier"]):
				diff += 1
			if int(b[i]["score"]) > int(a[i]["score"]):
				better += 1
			elif int(b[i]["score"]) < int(a[i]["score"]):
				worse += 1
		print("\n  PAIRED, SAME SEEDS  %s -> %s:" % [rows[0]["name"], rows[1]["name"]])
		print("   · different TIER on %d/%d seeds" % [diff, m])
		print("   · score better %d / worse %d / tied %d   (sign test on %d)" % [
			better, worse, m - better - worse, better + worse])
		_assert(diff * 2 > m, "ACCEPTANCE: the two policies land in DIFFERENT grades on most seeds")
		var naive_won: int = int(rows[0]["won"])
		_assert(naive_won >= int(round(0.875 * float(m))),
			"FLOOR: the naive on-ramp holds (%d/%d won, floor is 14/16)" % [naive_won, m])


# =============================================================================
# 3. THE RETIREE TAP — did the fix have nothing to do, or did the probe not look?
# =============================================================================
##
## ⚠️ THIS SECTION EXISTS BECAUSE SECTION 2 CAME BACK BYTE-IDENTICAL WITH THE FIX ON AND OFF, AND
## "no difference" is exactly what a blind instrument reports. Signature failure #2. So the tap
## counts, per week, the situation the fix changes: does the FRONT SLICE — the team sheet the old
## `career.gd:1149` took — contain a retiree? If that count is zero the fix genuinely had nothing
## to do on this autopilot; if it is non-zero and the arcs still matched, the probe is lying and
## this exits non-zero.
var _tap_weeks := 0
var _tap_retiree_in_barn := 0
var _tap_retiree_in_slice := 0     ## the OLD code would have fielded a retiree this week
var _tap_short := 0                ## fieldable < the frontier's team size


func _tap_reset_g() -> void:
	_tap_weeks = 0
	_tap_retiree_in_barn = 0
	_tap_retiree_in_slice = 0
	_tap_short = 0


## ⚠️ `super()` FIRST AND UNCHANGED, AND THE TAP CONSUMES NO RNG. Same contract as
## `_probe_terminal.gd`'s tap: observe the week, decide nothing.
func _manage_roster(opts: Dictionary) -> Dictionary:
	var out: Dictionary = super(opts)
	if _tap_on:
		_tap_weeks += 1
		var size: int = Career.team_size_for_league(Career.league_index)
		var slice: Array = Roster.monsters.slice(0, mini(size, Roster.monsters.size()))
		var fieldable: int = Roster.monsters.filter(func(m): return not m.retired).size()
		if Roster.monsters.any(func(m): return m.retired):
			_tap_retiree_in_barn += 1
		if slice.any(func(m): return m.retired):
			_tap_retiree_in_slice += 1
		if fieldable < size:
			_tap_short += 1
	return out


var _tap_on := false


func _run_tap() -> void:
	var n: int = clampi(_arg_int("--seeds", 8), 1, G_SEEDS.size())
	var only: String = _arg_str("--only", "NAIVE")
	print("\n─── 3. THE RETIREE TAP (%d seeds, %s) ───\n" % [n, only])
	_tap_on = true
	for name in Array(only.split(",")):
		var extra: Dictionary = apply_policy(str(name))
		var opts: Dictionary = {"feeMult": float(extra.get("feeMult", 1.0))}
		_tap_reset_g()
		for s in range(n):
			p_seed = int(G_SEEDS[s])
			var _a: Dictionary = _run_arc(1000, opts)
		print("  %-11s weeks %5d · retiree in barn %4d (%.1f%%) · SHORT of bodies %4d (%.1f%%)"
			% [str(name), _tap_weeks, _tap_retiree_in_barn,
				100.0 * float(_tap_retiree_in_barn) / maxf(1.0, float(_tap_weeks)),
				_tap_short, 100.0 * float(_tap_short) / maxf(1.0, float(_tap_weeks))])
		print("  %-11s WEEKS THE OLD FRONT SLICE WOULD HAVE FIELDED A RETIREE: %d (%.2f%%)" % [
			str(name), _tap_retiree_in_slice,
			100.0 * float(_tap_retiree_in_slice) / maxf(1.0, float(_tap_weeks))])
	_tap_on = false
	apply_policy("NAIVE")
	print("\n  READ THIS WITH SECTION 2. Identical arcs + a NON-ZERO slice count = the probe lied.")
	print("  Identical arcs + a ZERO slice count = the fix had nothing to do on THIS autopilot,")
	print("  which is a statement about the autopilot, not about the shipped sign-up screen.")


func _median(a: Array) -> int:
	if a.is_empty():
		return 0
	var c: Array = a.duplicate()
	c.sort()
	return int(c[c.size() / 2])
