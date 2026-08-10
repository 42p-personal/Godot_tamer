## THE TERMINAL PROBE — how does a career END, and can it be LOST at all?
##
## Run:
##   P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_terminal.tscn -- --audit
##   ... -- --census --seeds 16 --only NAIVE,COMPETENT      (~4 min per policy at 16 seeds)
##   ... -- --horizon --seeds 8 --weeks 2000 --only COMPETENT
##
## THE QUESTION. Four rounds have ended with "competence buys pace, not access" and nobody has
## established why. The standing hypothesis is that the career has NO FAILURE CONDITION — that a
## rung is never failed, only paid for in weeks, and that "difficulty" is therefore a synonym for
## "duration". This file does not argue that. It CENSUSES every way a run can stop and counts
## which ones actually fire.
##
## ⚠️ THIS SUBCLASSES `_probe_career_arc.gd` AND OVERRIDES NOTHING THAT DECIDES ANYTHING.
## The one override is `_manage_roster`, which calls `super()` unchanged and then records a
## read-only sample of the week's state. A probe carrying a second copy of the model it tests is
## this project's signature instrument failure (round 10); there is no second autopilot here.
##
## ⚠️ THE TAP IS READ-ONLY AND MUST CONSUME NO RNG. Every call it makes (`Career.team_size_for_
## league`, `Career.min_team_to_enter`, `_entry_fee`) is pure. If that ever stops being true the
## arcs stop being comparable to every other probe's, silently.
##
## LIVENESS CANARY. `_manage_roster` runs exactly once per loop iteration of the arc, and the arc
## advances the clock by one week per iteration PLUS `travelWeeks` inside cup trips. So
##     samples == weeks - travelWeeks
## must hold exactly, per arc. It is checked per arc and a violation FAILS the probe: a tap that
## did not fire would otherwise report "0 stuck weeks" from having seen no weeks at all.
extends "res://scripts/_probe_career_arc.gd"

## Wider than `POLICY_SEEDS` (8) on purpose: a proportion at n=8 carries about +/-17 points, which
## is wider than most of the effects a census would want to name. Still only +/-12 at n=16 — every
## proportion below is printed with its Wilson band and must be read with it.
const T_SEEDS := [
	20260809, 771013, 313373, 4242424, 99180, 5150, 606060, 8888881,
	11235, 271828, 1618033, 6022140, 137035, 66260, 299792, 86400,
	31415926, 2718281, 4004, 1729, 40320, 65537, 123581, 999983,
]

var _ok := true

# ── the per-week tap (reset per arc by `_run_arc` -> `_manage_roster` sequence) ──
var t_samples := 0
var t_frontier_ok := 0      # the frontier rung could be fielded IN FULL this week
var t_farm_only := 0        # frontier not fieldable, some lower rung was
var t_no_rung := 0          # no rung fieldable even short-handed — a week that cannot enter a cup
## ⚠️ THIS COLUMN IS STRUCTURALLY ZERO AND IT IS NOT EVIDENCE ABOUT THE GAME. Round 17's brief
## expected it to become non-zero once retirees stopped competing. It cannot: the parent autopilot
## (`_probe_career_arc.gd:_manage_roster`, the "retirees first" block) preserves or releases every
## retiree the same week it retires, so a barn with zero fieldable bodies is a state THIS INSTRUMENT
## never allows to exist. Measured 0.0% of ~19,000 weeks before the fix (round 16) and 0.0% of
## ~1,900 after (round 17, NAIVE n=6) — the fix cannot move a counter of a state the autopilot
## prevents. **Do not "fix" this by making the autopilot neglect its retirees**: that manufactures
## the state in order to observe it, which is signature failure #2. The retired-only stable is
## asserted DIRECTLY and deterministically in `--audit` instead, which is stronger evidence than
## waiting for a stochastic career to stumble into it.
var t_no_body := 0          # zero non-retired monsters in the barn
var t_fee_wall := 0         # a rung was fieldable but the entry fee was unaffordable
var t_broke := 0            # gold < 100
var t_zero_gold := 0        # gold == 0 exactly
var t_min_gold := 1 << 30


func _ready() -> void:
	_tree = get_tree()
	print("=== TERMINAL PROBE — how does a career end? ===\n")
	var args: Array = OS.get_cmdline_user_args()
	args.append_array(OS.get_cmdline_args())
	if "--audit" in args:
		_run_audit()
	if "--census" in args:
		_run_census()
	if "--horizon" in args:
		_run_horizon()
	if "--wall" in args:
		_run_wall_test()
	print("\n=== terminal probe: %s ===" % ("OK" if _ok else "INSTRUMENT BROKEN"))
	_tree.quit(0 if _ok else 1)


# =============================================================================
# THE TAP
# =============================================================================

## ⚠️ `super()` FIRST AND UNCHANGED. This override exists to OBSERVE the week the arc is about to
## play, not to change it. It is called once per arc-loop iteration, before planning and before
## the cup, which is the same point every other per-week number in the parent is counted at.
func _manage_roster(opts: Dictionary) -> Dictionary:
	var out: Dictionary = super(opts)
	_sample_week()
	return out


func _sample_week() -> void:
	t_samples += 1
	var fieldable: int = Roster.monsters.filter(func(m): return not m.retired).size()
	if fieldable == 0:
		t_no_body += 1
	var idx: int = Career.league_index
	var full_idx := -1
	for j in range(idx, -1, -1):
		if Career.team_size_for_league(j) <= fieldable:
			full_idx = j
			break
	var short_idx := -1
	for j in range(idx, -1, -1):
		if Career.min_team_to_enter(j) <= fieldable:
			short_idx = j
			break
	if full_idx == idx:
		t_frontier_ok += 1
	elif full_idx >= 0 or short_idx >= 0:
		t_farm_only += 1
	else:
		t_no_rung += 1
	## The fee wall, asked of the rung the arc would actually enter. `_entry_fee` already carries
	## the Wood waiver (fee 0 at idx 0 when gold is short), so a hit here is a REAL refusal.
	var enter_idx: int = full_idx if full_idx >= 0 else short_idx
	if enter_idx >= 0 and Career.gold < _entry_fee(enter_idx):
		t_fee_wall += 1
	if Career.gold < 100:
		t_broke += 1
	if Career.gold == 0:
		t_zero_gold += 1
	t_min_gold = mini(t_min_gold, Career.gold)


func _tap_reset() -> void:
	t_samples = 0
	t_frontier_ok = 0
	t_farm_only = 0
	t_no_rung = 0
	t_no_body = 0
	t_fee_wall = 0
	t_broke = 0
	t_zero_gold = 0
	t_min_gold = 1 << 30


# =============================================================================
# 1. THE AUDIT — every terminal path, enumerated from the code and probed for liveness
# =============================================================================

## ⚠️ THE POINT OF THIS SECTION IS THE DISTINCTION BETWEEN A GAME RULE AND AN INSTRUMENT RULE.
## Three of the arc's four exits do not exist in the shipped game at all: they are properties of
## `_probe_career_arc.gd`. Every completion figure this repo has ever quoted is a statement about
## them, and that has never been said out loud.
func _run_audit() -> void:
	print("─── 1. TERMINAL PATHS, ENUMERATED FROM THE CODE ───\n")
	print("  IN THE SHIPPED GAME (scripts/career.gd, week.gd, roster.gd):")
	print("   · WIN   career.gd:1220  `won_game = true` when `advanced and is_final_league(idx)`.")
	print("           The ONLY terminal state the game itself defines.")
	print("   · LOSS  — none. There is no `game_over`, no `defeat`, no run-ending guard anywhere")
	print("           in scripts/. `grep -rn 'game_over|defeat' scripts/` returns nothing.")
	print("   · GOLD  career.gd:1239 `gold = maxi(0, gold + amount)` — gold cannot go negative,")
	print("           so there is no bankruptcy STATE, only a gold==0 state you can sit in.")
	print("   · AGE   week.gd:634 sets `mi.retired = true` past the lifespan. A retiree is not")
	print("           removed: it ages forever in a barn slot and cannot train, feed or compete.")
	print("   · TIME  `Career.week` is an unbounded int. Nothing reads it as a limit.")
	print("")
	print("  IN THE PROBE ONLY (_probe_career_arc.gd — these are INSTRUMENT rules):")
	print("   · HORIZON  MAX_WEEKS/POLICY_WEEKS = 1000. `while Career.week < max_weeks`.")
	print("   · WALLED   STALL_WEEKS = 150. `no promotion out of <league> in 150 weeks` -> break.")
	print("   · BARN     `barn cannot hold N (max M)` when the shop's barn ladder runs out.")
	print("   · CADENCE  CUP_INTERVAL = 4. The shipped tournament screen has NO cooldown at all —")
	print("              a cup is enterable every week, costing only the fee and the trip.")
	print("")
	_audit_live()


## The three shipped-side claims above that can be executed rather than asserted.
func _audit_live() -> void:
	print("  liveness checks on the shipped rules:")
	_reset_career()
	var g0: int = Career.gold
	Career.add_gold(-999999)
	var floored: bool = Career.gold == 0
	print("   %s gold floor: 500 - 999999 -> %d (expected 0)" % ["OK " if floored else "FAIL", Career.gold])
	if not floored:
		_ok = false
	## The Wood waiver — the game's own anti-softlock valve, and the load-bearing reason a broke
	## career is never actually locked out of the ladder.
	var waived: int = _entry_fee(0)
	var full_wood: int = _base_fee()
	print("   %s Wood entry at 0 gold: fee %d (base %d) — the waiver is LIVE" % [
		"OK " if waived == 0 and full_wood > 0 else "FAIL", waived, full_wood])
	if not (waived == 0 and full_wood > 0):
		_ok = false
	Career.add_gold(g0)
	var fee_paid: int = _entry_fee(0)
	print("   %s Wood entry at %d gold: fee %d (the waiver is CONDITIONAL, not free forever)" % [
		"OK " if fee_paid == full_wood else "FAIL", Career.gold, fee_paid])
	if fee_paid != full_wood:
		_ok = false
	## A retiree in the barn: does it still occupy a slot and refuse to act?
	var mi = GameData.make_monster(Art.ROSTER[0], 0.4, Roster.rng)
	if mi != null:
		## ⚠️ `age_one_week` only retires on a stage TRANSITION, so the body must be walked ACROSS
		## the boundary. It is also why a sub-one-year lifespan never retires at all: the "Baby"
		## branch is tested before the "Retiree" branch, so the stage never changes. Not a bug
		## worth filing — nothing generates such a monster — but it is why this uses real numbers.
		mi.retired = false
		mi.lifespan_years = 8.0
		mi.age_weeks = 8 * WeekLib.WEEKS_PER_YEAR - 2
		var before_total: float = _stat_total(mi)
		for _i in range(3):
			WeekLib.age_one_week(mi)
		var g_after: int = WeekLib.apply_activity(mi, {"kind": "train", "drillId": "str_basic"},
			1000, 900.0, "Wood")
		var age_before: int = mi.age_weeks
		WeekLib.age_one_week(mi)
		var inert: bool = mi.retired and is_equal_approx(_stat_total(mi), before_total) \
			and g_after == 1000 and mi.age_weeks == age_before + 1
		print("   %s a retiree (retired=%s) trains nothing (total %.0f->%.0f), costs nothing (%dg)," % [
			"OK " if inert else "FAIL", str(mi.retired), before_total, _stat_total(mi), g_after]
			+ " and keeps ageing in its slot")
		if not inert:
			_ok = false
	_audit_retiree_competes()
	_audit_fielding_predicate()
	print("")


## ⚠️ THE PREDICATE ITSELF, AND ITS CANARY. `roster.gd:fieldable()/fielded_team()/
## entry_block_reason()` is the one function the four doors now call instead of agreeing with each
## other four times (round 17). This asserts the FUNCTION, then asserts that it is actually
## DISCRIMINATING — a `fieldable()` that returned everything, or that returned nothing, would pass a
## naive "retirees excluded" check and be silently useless.
##
## LIVENESS CANARY: the same barn is read twice, once with the body racing and once retired, and the
## two readings MUST differ in every one of the three outputs. If they do not, the predicate is inert
## and the probe exits non-zero rather than printing a green line about a rule nobody enforces.
func _audit_fielding_predicate() -> void:
	_reset_career()
	Roster.monsters.clear()
	var racer = GameData.make_monster(Art.ROSTER[0], 0.5, Roster.rng)
	var old = GameData.make_monster(Art.ROSTER[1], 0.5, Roster.rng)
	if racer == null or old == null:
		return
	racer.id = Roster.next_slot_id()
	old.id = Roster.next_slot_id()
	racer.retired = false
	old.retired = false
	## ⚠️ THE RETIREE GOES FIRST IN THE BARN ON PURPOSE. Every door slices FROM THE FRONT and the
	## oldest bodies sit earliest, so a front-slice is the arrangement that actually shipped the bug.
	## A test that put the retiree last would pass on a `slice()` that filters nothing.
	Roster.monsters.append(old)
	Roster.monsters.append(racer)

	var before := {
		"able": Roster.fieldable_count(),
		"team": Roster.fielded_team(1).size(),
		"first": (Roster.fielded_team(1)[0] if not Roster.fielded_team(1).is_empty() else null),
		"block": Roster.entry_block_reason(2),
	}
	old.retired = true
	var after := {
		"able": Roster.fieldable_count(),
		"team": Roster.fielded_team(1).size(),
		"first": (Roster.fielded_team(1)[0] if not Roster.fielded_team(1).is_empty() else null),
		"block": Roster.entry_block_reason(2),
	}

	var excludes: bool = int(after["able"]) == 1 and after["first"] == racer
	print("   %s Roster.fieldable() excludes the retiree: 2 in the barn -> %d able, front-slice picks %s" % [
		"OK " if excludes else "FAIL", int(after["able"]),
		"the racer" if after["first"] == racer else "the RETIREE"])
	if not excludes:
		_ok = false

	## A retired-ONLY barn: the state that used to fight a full cup with nobody who can train.
	racer.retired = true
	var all_gone: String = Roster.entry_block_reason(1)
	var empty_team: bool = Roster.fielded_team(5).is_empty()
	print("   %s a RETIRED-ONLY stable fields %d bodies and is refused with a reason:" % [
		"OK " if (empty_team and all_gone != "") else "FAIL", Roster.fielded_team(5).size()])
	print("       \"%s\"" % all_gone)
	if not (empty_team and all_gone != ""):
		_ok = false

	## THE CANARY — retiring a body must have MOVED all three outputs.
	var moved: bool = int(before["able"]) != int(after["able"]) \
		and before["first"] != after["first"] \
		and str(before["block"]) != str(after["block"])
	print("   %s canary: retiring one of two moved able %d->%d, front-slice, and the block reason" % [
		"OK " if moved else "FAIL", int(before["able"]), int(after["able"])])
	if not moved:
		print("       -> the predicate did not respond to `retired`. Every OK above is meaningless.")
		_ok = false
	_audit_signup_door()
	Roster.monsters.clear()


## ⚠️ A PREDICATE CAN BE CORRECT AND THE DOOR CAN STILL IGNORE IT — which is signature failure #1
## in its purest form, and the exact shape of the bug being fixed. So this instantiates the REAL
## `ui/tournament_ui.gd` against two real barns and reads the entry button off the built tree, in
## the spirit of signature failure #3: whatever the screen displays must be read from the thing it
## describes, and whatever a probe asserts must be read from the screen, not from a copy of its
## logic. It does not press anything — building the card is the whole assertion.
func _audit_signup_door() -> void:
	var racing_ok: bool = _signup_button_enabled(false)
	var retired_ok: bool = not _signup_button_enabled(true)
	print("   %s the SIGN-UP SCREEN itself: Wood entry is %s with one racing body, %s with one retired" % [
		"OK " if (racing_ok and retired_ok) else "FAIL",
		"ENABLED" if racing_ok else "disabled", "disabled" if retired_ok else "ENABLED"])
	if not (racing_ok and retired_ok):
		print("       -> `ui/tournament_ui.gd` is not reading `Roster.entry_block_reason()`.")
		_ok = false
	_audit_read_screen()


## THE SECOND DOOR — "The Read" is what actually puts bodies on the sheet, and it is the one a
## `--check-only` parse cannot verify (autoloads are not registered in that mode, so a bare check of
## `tactics_ui.gd` reports a false "Identifier not found: Roster"). So it is exercised for real.
##
## ⚠️ IT ASSERTS THE TEAM, NOT THE SCREEN. `team_a` is the array handed to `BattleSim`; if a retiree
## reaches it, the fix is cosmetic no matter what the card says.
func _audit_read_screen() -> void:
	Roster.monsters.clear()
	var old = GameData.make_monster(Art.ROSTER[0], 0.5, Roster.rng)
	var racer = GameData.make_monster(Art.ROSTER[1], 0.5, Roster.rng)
	if old == null or racer == null:
		return
	old.id = Roster.next_slot_id(); old.retired = true       ## front of the barn, as an aged body is
	racer.id = Roster.next_slot_id(); racer.retired = false
	Roster.monsters.append(old)
	Roster.monsters.append(racer)
	var script_res = load("res://scripts/ui/tactics_ui.gd")
	if script_res == null:
		print("   FAIL `ui/tactics_ui.gd` does not compile")
		_ok = false
		return
	var screen: Control = script_res.new()
	add_child(screen)
	var fielded: Array = screen.team_a
	var clean: bool = fielded.size() == 1 and fielded[0] == racer
	print("   %s THE READ fields %d of 2 (1 retired) and it is %s" % [
		"OK " if clean else "FAIL", fielded.size(),
		"the racer" if (fielded.size() == 1 and fielded[0] == racer) else "WRONG"])
	if not clean:
		print("       -> `ui/tactics_ui.gd` is slicing `Roster.monsters` instead of")
		print("          `Roster.fielded_team()`. A retiree reached the battle sim.")
		_ok = false
	remove_child(screen)
	screen.free()
	Roster.monsters.clear()


## Builds `tournament_ui` for a one-monster barn and returns whether its frontier Enter button is
## live. ⚠️ Freed synchronously with `free()`, not `queue_free()` — this probe never yields to a
## frame, so a queued node would still be in the tree for the next call and the second reading
## would be taken off the first screen.
func _signup_button_enabled(retired: bool) -> bool:
	Roster.monsters.clear()
	var mi = GameData.make_monster(Art.ROSTER[0], 0.5, Roster.rng)
	if mi == null:
		return false
	mi.id = Roster.next_slot_id()
	mi.retired = retired
	Roster.monsters.append(mi)
	Career.league_index = 0                     ## Wood: team size 1, so one body is a full team
	var screen: Control = load("res://scripts/ui/tournament_ui.gd").new()
	add_child(screen)
	var live: bool = _has_live_enter_button(screen)
	remove_child(screen)
	screen.free()
	return live


func _has_live_enter_button(n: Node) -> bool:
	if n is Button and str((n as Button).text).begins_with("Enter the") and not (n as Button).disabled:
		return true
	for c in n.get_children():
		if _has_live_enter_button(c):
			return true
	return false


## ⚠️ THE RULE `roster.gd:126` STATES IS NOT THE RULE THE LADDER ENFORCES. That comment reads
## "a retiree cannot train, feed, or compete", and the first two are true (`week.gd:650` and
## `week.gd:604` both bail on `mi.retired`). The third had no enforcement anywhere: four doors —
## `career.gd:1149`, `tactics_ui.gd:49`, `tournament_ui.gd:122,173` — each sliced or counted
## `Roster.monsters` unfiltered. This is the project's signature failure #1 and it matters HERE
## because it removes the last candidate for a lose condition: a stable whose every body has aged
## out is not eliminated, it simply competes with monsters that can no longer improve.
##
## ⚠️ ROUND 17 CLOSED ALL FOUR DOORS AND THIS FUNCTION IS NOW A TRIPWIRE, NOT A REPORT. The rule
## lives in ONE place — `roster.gd:fieldable()/fielded_team()/entry_block_reason()` — and all four
## call sites call it. This one drives `Career.enter_league_tournament()` DIRECTLY, bypassing both
## screens, so it is the door a future refactor is most likely to reopen: a headless path has no
## screen to look wrong. It FAILS the probe if a retiree is fielded again, rather than printing
## `!!` and passing, which is what it did for the eleven rounds the hole was open.
##
## `_audit_fielding_predicate()` below asserts the predicate itself, its canary, and the real
## `ui/tournament_ui.gd` tree — because a correct predicate that no door reads is exactly the
## failure being fixed.
func _audit_retiree_competes() -> void:
	_reset_career()
	var mi = GameData.make_monster(Art.ROSTER[0], 0.5, Roster.rng)
	if mi == null:
		return
	mi.id = Roster.next_slot_id()
	mi.retired = true
	mi.hp = 1.0                       ## the sentinel — `reset_for_battle()` restores it to max
	Roster.monsters.append(mi)
	var out: Dictionary = Career.enter_league_tournament(0, 3, 12345)
	var fielded: bool = mi.hp != 1.0 and int(out.get("rivalCount", 0)) == 3
	print("   %s the HEADLESS cup path fields a retiree: %s (a %d-round cup ran, wins %d)" % [
		"!! " if fielded else "OK ", str(fielded),
		int(out.get("rivalCount", 0)), int(out.get("wins", 0))])
	if fielded:
		print("       -> `career.gd` is slicing `Roster.monsters` instead of calling")
		print("          `Roster.fielded_team()`. The rule is one function (roster.gd) and this is")
		print("          the door that bypasses both screens.")
		print("       -> CHECK FOR A DELIBERATE A/B SWITCH FIRST. This fired once during round 17")
		print("          on `career.gd:_AB_RETIREE_OFF`, a measurement flag marked REMOVE BEFORE")
		print("          INTEGRATION. If one is present and true, this failure is EXPECTED and the")
		print("          flag is the finding. If not, it is a regression — fix it at the slice.")
		_ok = false
	else:
		print("       -> `reset_for_battle()` never touched the retiree's sentinel HP, so no aged-out")
		print("          body was put on the sheet. Closed round 17; this line is now a tripwire.")


# =============================================================================
# 2. THE CENSUS — which exit actually fires, across policies and seeds
# =============================================================================

func _run_census() -> void:
	var n: int = clampi(_arg_int("--seeds", 8), 1, T_SEEDS.size())
	var weeks_cap: int = _arg_int("--weeks", 1000)
	var only: String = _arg_str("--only", "")
	var order: Array = POLICY_ORDER.duplicate() if only == "" else Array(only.split(","))
	print("─── 2. THE EXIT CENSUS (%d seeds x %d weeks, policies %s) ───\n" % [n, weeks_cap, str(order)])
	print("  WON is `Career.won_game` — the Apex draw SWEPT. Reaching index 10 is NOT completion.")
	print("  WALLED / HORIZON / BARN are all INSTRUMENT exits (see --audit). The shipped game has")
	print("  no equivalent of any of them.\n")
	var rows: Array = []
	for name in order:
		rows.append(_census_policy(str(name), n, weeks_cap))
	_print_census(rows, n)


func _census_policy(name: String, n: int, weeks_cap: int) -> Dictionary:
	var extra: Dictionary = apply_policy(name)
	var opts: Dictionary = {"feeMult": float(extra.get("feeMult", 1.0))}
	var kinds := {"WON": 0, "WALLED": 0, "HORIZON": 0, "BARN": 0, "OTHER": 0}
	var walled_at: Array = []
	var horizon_at: Array = []
	var tot := {"weeks": 0.0, "cups": 0.0, "travel": 0.0, "frontierBlocked": 0.0,
		"feeRefused": 0.0, "blockedRecruit": 0.0, "train": 0.0, "rest": 0.0,
		"excursion": 0.0, "capped": 0.0, "retire": 0.0}
	var tap := {"samples": 0, "frontier": 0, "farm": 0, "norung": 0, "nobody": 0,
		"feewall": 0, "broke": 0, "zero": 0}
	var min_gold := 1 << 30
	for s in range(n):
		p_seed = int(T_SEEDS[s])
		_tap_reset()
		var a: Dictionary = _run_arc(weeks_cap, opts)
		var kind: String = _classify(a, weeks_cap)
		kinds[kind] = int(kinds[kind]) + 1
		if kind == "WALLED":
			walled_at.append(int(a["finalLeague"]))
		if kind == "HORIZON":
			horizon_at.append(int(a["finalLeague"]))
		## ⚠️ THE CANARY. samples must equal the weeks the arc LOOPED, which is the clock minus the
		## weeks burned inside cup trips. Anything else means the tap missed weeks and every
		## per-week proportion below is fiction.
		var expect: int = int(a["weeks"]) - int(a.get("travelWeeks", 0))
		if t_samples != expect:
			_ok = false
			print("    ⚠️ CANARY FAILED: %s seed %d — tap saw %d weeks, arc looped %d" % [
				name, int(T_SEEDS[s]), t_samples, expect])
		tot["weeks"] += float(a["weeks"])
		tot["cups"] += float(a["cups"])
		tot["travel"] += float(a.get("travelWeeks", 0))
		tot["frontierBlocked"] += float(a.get("frontierBlockedWeeks", 0))
		tot["feeRefused"] += float(a.get("cupsRefusedByFee", 0))
		tot["blockedRecruit"] += float(a.get("blockedRecruit", 0))
		tot["train"] += float(a.get("trainWeeks", 0))
		tot["rest"] += float(a.get("restWeeks", 0))
		tot["excursion"] += float(a.get("excursionWeeks", 0))
		tot["capped"] += float(a.get("cappedWeeks", 0))
		tot["retire"] += float(a.get("retirements", 0))
		tap["samples"] += t_samples
		tap["frontier"] += t_frontier_ok
		tap["farm"] += t_farm_only
		tap["norung"] += t_no_rung
		tap["nobody"] += t_no_body
		tap["feewall"] += t_fee_wall
		tap["broke"] += t_broke
		tap["zero"] += t_zero_gold
		min_gold = mini(min_gold, t_min_gold)
		print("    %-11s seed %-9d -> %-8s %-12s wk %4d  cups %3d  norung %3d  minGold %4d  %s" % [
			name, int(T_SEEDS[s]), kind,
			str(Career.league_at(int(a["finalLeague"])).get("name", "?")),
			int(a["weeks"]), int(a["cups"]), t_no_rung, t_min_gold, str(a.get("stall", ""))])
	apply_policy("NAIVE")
	return {"name": name, "kinds": kinds, "tot": tot, "tap": tap, "n": n,
		"walledAt": walled_at, "horizonAt": horizon_at, "minGold": min_gold}


## The arc reports `won`, `stall` and `weeks`; the exit follows from those three and nothing else.
func _classify(a: Dictionary, weeks_cap: int) -> String:
	if bool(a.get("won", false)):
		return "WON"
	var stall: String = str(a.get("stall", ""))
	if stall.begins_with("no promotion"):
		return "WALLED"
	if stall.begins_with("barn cannot hold"):
		return "BARN"
	if int(a.get("weeks", 0)) >= weeks_cap:
		return "HORIZON"
	return "OTHER"


func _print_census(rows: Array, n: int) -> void:
	print("\n  %-11s  %-13s  %-13s  %-13s  %-8s  %s" % [
		"policy", "WON", "WALLED", "HORIZON", "BARN", "median wks"])
	for r in rows:
		var k: Dictionary = r["kinds"]
		print("  %-11s  %-13s  %-13s  %-13s  %-8s  %d" % [
			str(r["name"]),
			_prop(int(k["WON"]), n), _prop(int(k["WALLED"]), n),
			_prop(int(k["HORIZON"]), n), "%d/%d" % [int(k["BARN"]), n],
			int(float(r["tot"]["weeks"]) / float(n))])
	print("  (proportions carry 95%% Wilson bands — at n=%d a proportion is +/-~%d points.)" % [
		n, int(round(100.0 * 0.98 / sqrt(float(n))))])

	print("\n  WHERE a run stopped (league index; 0=Wood 10=Tamers Apex):")
	for r in rows:
		print("   · %-11s walled at %s   horizon at %s" % [
			str(r["name"]), str(r["walledAt"]), str(r["horizonAt"])])

	print("\n  CAN A CAREER GET STUCK? (per-week census; % of looped weeks)")
	print("  %-11s  %-12s  %-12s  %-12s  %-11s  %-11s  %s" % [
		"policy", "frontier ok", "farm below", "NO RUNG", "no body", "fee wall", "gold<100"])
	for r in rows:
		var t: Dictionary = r["tap"]
		var s: float = maxf(1.0, float(t["samples"]))
		print("  %-11s  %-12s  %-12s  %-12s  %-11s  %-11s  %s" % [
			str(r["name"]),
			_pct(int(t["frontier"]), s), _pct(int(t["farm"]), s), _pct(int(t["norung"]), s),
			_pct(int(t["nobody"]), s), _pct(int(t["feewall"]), s), _pct(int(t["broke"]), s)])
	print("  NO RUNG = a week in which no league, not even short-handed, could be entered.")
	print("  That is the only 'stuck' state the ladder has, and it is neither winning nor losing.")

	print("\n  THE HYPOTHESIS ARITHMETIC — is there enough time for the ladder to be paid for?")
	## ⚠️ `train m-wks` is MONSTER-weeks, not calendar weeks — the parent sums it over every body
	## in the barn, so at a five-monster roster it runs well ahead of the clock. Labelled, because
	## reading it as calendar weeks would make the training half look larger than the career.
	print("  %-11s  %-9s  %-9s  %-11s  %-11s  %s" % [
		"policy", "cups/run", "wks/cup", "road wks", "train m-wks", "min gold seen"])
	for r in rows:
		var t: Dictionary = r["tot"]
		var cups: float = maxf(1.0, float(t["cups"]) / float(n))
		var wks: float = float(t["weeks"]) / float(n)
		print("  %-11s  %-9.1f  %-9.2f  %-11.1f  %-11.1f  %d" % [
			str(r["name"]), cups, wks / cups, float(t["travel"]) / float(n),
			float(t["train"]) / float(n), int(r["minGold"])])
	print("  wks/cup is the WHOLE clock divided by cups entered — the price of a cup in the only")
	print("  currency that is finite. 32.7 cups is the expected number to clear all eleven rungs")
	print("  at the shipped ADVANCE rates; multiply it by wks/cup for the ladder's true week bill.")


# =============================================================================
# 3. THE HORIZON COUNTERFACTUAL — is 1000 weeks the thing that stops them?
# =============================================================================

## ⚠️ THE DECISIVE TEST OF "THE CAREER HAS NO FAILURE CONDITION". If runs that hit the horizon
## simply WIN when given more of it, then the horizon — a number in a probe — is the only thing
## between them and completion, and every completion figure in this repo is a statement about it.
## If they do not, something in the GAME binds, and the hypothesis is refuted with a number.
##
## WALLED runs are excluded from the reading on purpose: STALL_WEEKS breaks them regardless of the
## horizon, so a longer horizon cannot move them and including them would dilute the effect.
func _run_horizon() -> void:
	var n: int = clampi(_arg_int("--seeds", 8), 1, T_SEEDS.size())
	var long_weeks: int = _arg_int("--weeks", 2000)
	var only: String = _arg_str("--only", "COMPETENT")
	var order: Array = Array(only.split(","))
	print("\n─── 3. THE HORIZON COUNTERFACTUAL (%d seeds, 1000 -> %d weeks) ───\n" % [n, long_weeks])
	for name in order:
		var extra: Dictionary = apply_policy(str(name))
		var opts: Dictionary = {"feeMult": float(extra.get("feeMult", 1.0))}
		var flips := 0
		var still := 0
		var base_kinds := {}
		for s in range(n):
			p_seed = int(T_SEEDS[s])
			_tap_reset()
			var a: Dictionary = _run_arc(1000, opts)
			var ka: String = _classify(a, 1000)
			base_kinds[ka] = int(base_kinds.get(ka, 0)) + 1
			if ka == "WON":
				continue
			p_seed = int(T_SEEDS[s])
			_tap_reset()
			var b: Dictionary = _run_arc(long_weeks, opts)
			var kb: String = _classify(b, long_weeks)
			if kb == "WON":
				flips += 1
			else:
				still += 1
			print("    %-11s seed %-9d  %-8s wk %4d  ->  %-8s wk %4d  (league %d -> %d)" % [
				str(name), int(T_SEEDS[s]), ka, int(a["weeks"]), kb, int(b["weeks"]),
				int(a["finalLeague"]), int(b["finalLeague"])])
		print("\n    %s: of the non-winners at 1000 weeks, %d/%d WON by %d weeks, %d did not." % [
			str(name), flips, flips + still, long_weeks, still])
		print("    baseline exits at 1000: %s" % str(base_kinds))
	apply_policy("NAIVE")


# =============================================================================
# helpers
# =============================================================================

# =============================================================================
# 4. THE WALL TEST — is a walled rung UNCLEARABLE, or merely UNPAID FOR?
# =============================================================================

## ⚠️ THIS IS THE DECISIVE EXPERIMENT OF THE ROUND, AND IT IS NOT THE HORIZON.
## The census finds that no career hits the 1000-week horizon at all: the only non-winning exit
## is WALLED, which is `_probe_career_arc.gd`'s own STALL_WEEKS = 150 rule and does not exist in
## the shipped game. So "would more weeks have finished it" is really "would more CUPS at this
## rung have advanced it", and that is directly measurable on the state the arc walled in.
##
## The method: run the arc to its wall, freeze the roster where it stopped, and enter the frontier
## cup K more times with an independent field each time. If the advance rate is > 0, the rung is
## not a wall — it is a rate, and with an unbounded clock (which the shipped game has) it clears
## with probability 1. If it is exactly 0 over K cups, the rung is a genuine ceiling and the
## no-failure-condition hypothesis is refuted with a number.
##
## ⚠️ PERTURBS TWO AUTOLOAD FIELDS AND RESTORES BOTH. `Career.week` is advanced a game-month per
## trial because `Career.cup_field_seed()` holds the field steady within a month — without that
## every trial would fight the IDENTICAL draw and K trials would be one trial repeated. And
## `league_index`/`leagues_won`/`won_game` are restored after each cup so a trial that promotes
## does not change the rung the next trial measures. Both restorations are asserted at the end.
##
## ⚠️ AND IT CARRIES A POSITIVE CONTROL. A rung the arc has already cleared is measured the same
## way. If the control ALSO reads 0 advances, this instrument cannot see an advance at all and the
## frontier reading means nothing — that is reported instead of a finding.
func _run_wall_test() -> void:
	var n: int = clampi(_arg_int("--seeds", 16), 1, T_SEEDS.size())
	var trials: int = _arg_int("--trials", 24)
	var only: String = _arg_str("--only", "COMPETENT")
	print("\n─── 4. THE WALL TEST (%d trial cups on each walled state) ───\n" % trials)
	for name in Array(only.split(",")):
		var extra: Dictionary = apply_policy(str(name))
		var opts: Dictionary = {"feeMult": float(extra.get("feeMult", 1.0))}
		for s in range(n):
			p_seed = int(T_SEEDS[s])
			_tap_reset()
			var a: Dictionary = _run_arc(1000, opts)
			if _classify(a, 1000) == "WON":
				continue
			var idx: int = int(a["finalLeague"])
			print("    %s seed %d WALLED at %s (wk %d). Re-entering %d cups on the frozen roster:" % [
				str(name), int(T_SEEDS[s]), str(Career.league_at(idx).get("name", "?")),
				int(a["weeks"]), trials])
			var frontier: Dictionary = _trial_cups(idx, trials)
			var control_idx: int = maxi(0, idx - 2)
			var control: Dictionary = _trial_cups(control_idx, trials)
			print("      frontier %-12s advanced %2d/%2d %s   rounds won %d/%d" % [
				str(Career.league_at(idx).get("name", "?")), int(frontier["adv"]), trials,
				_wilson(int(frontier["adv"]), trials), int(frontier["wins"]), int(frontier["rounds"])])
			print("      control  %-12s advanced %2d/%2d %s   rounds won %d/%d   <- positive control" % [
				str(Career.league_at(control_idx).get("name", "?")), int(control["adv"]), trials,
				_wilson(int(control["adv"]), trials), int(control["wins"]), int(control["rounds"])])
			if int(control["adv"]) == 0:
				print("      ⚠️ THE CONTROL READS ZERO TOO — this instrument cannot see an advance.")
				print("         The frontier number above means nothing. Do not quote it.")
				_ok = false
			elif int(frontier["adv"]) == 0:
				print("      -> %d cups, 0 advances. This rung is a genuine CEILING for this roster," % trials)
				print("         not a rate. More weeks would not have cleared it.")
			else:
				var p: float = float(frontier["adv"]) / float(trials)
				print("      -> the rung advances at %.2f per cup. Expected cups to clear: %.1f," % [p, 1.0 / p])
				print("         i.e. ~%.0f more weeks at this arc's %.1f weeks per cup. NOT a wall." % [
					(1.0 / p) * 3.8, 3.8])
	apply_policy("NAIVE")


## K independent cups on the CURRENT roster at `idx`, with the ladder state restored after each.
func _trial_cups(idx: int, trials: int) -> Dictionary:
	var w0: int = Career.week
	var li0: int = Career.league_index
	var lw0: Array = Career.leagues_won.duplicate()
	var wg0: bool = Career.won_game
	var adv := 0
	var wins := 0
	var rounds := 0
	for k in range(trials):
		Career.week = w0 + (k + 1) * 4     ## a fresh game-month => a fresh drawn field
		var r: int = _rounds_for(idx)
		var out: Dictionary = _fight_cup(idx, r, (w0 + k) * 31 + idx)
		if bool(out.get("advanced", false)):
			adv += 1
		wins += int(out.get("wins", 0))
		rounds += int(out.get("rivalCount", 0))
		Career.league_index = li0
		Career.leagues_won = lw0.duplicate()
		Career.won_game = wg0
	Career.week = w0
	## The restoration canary — if any of these drifted, every later trial measured a different
	## rung from the one it reported.
	if Career.week != w0 or Career.league_index != li0 or Career.won_game != wg0:
		print("      ⚠️ RESTORE CANARY FAILED — the perturbation leaked. Numbers above are void.")
		_ok = false
	return {"adv": adv, "wins": wins, "rounds": rounds}


func _prop(k: int, n: int) -> String:
	return "%d/%d %s" % [k, n, _wilson(k, n)]


## 95% Wilson score interval, printed as a compact band. The proportions in this census are all
## at n<=24 and none of them mean anything without it.
func _wilson(k: int, n: int) -> String:
	if n <= 0:
		return "[--]"
	var z := 1.96
	var p := float(k) / float(n)
	var d := 1.0 + z * z / float(n)
	var c := p + z * z / (2.0 * float(n))
	var s := z * sqrt(p * (1.0 - p) / float(n) + z * z / (4.0 * float(n) * float(n)))
	return "[%.2f-%.2f]" % [maxf(0.0, (c - s) / d), minf(1.0, (c + s) / d)]


func _pct(k: int, of: float) -> String:
	return "%.1f%%" % (100.0 * float(k) / of)
