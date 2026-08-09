## THE RECRUIT PROBE — is a new body AFFORDABLE, and is it USEFUL, at the team-size steps?
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_recruit.tscn
##      …                                                     -- --quick   (skip the arc matrix)
##
## ⚠️ RUNS AS A SCENE, NEVER `--script` — it needs the Career/Roster/GameData/Art autoloads.
##
## ⚠️ IT DOES NOT FORK THE AUTOPILOT. Section 3 SUBCLASSES `_probe_career_arc.gd` exactly the way
## `_probe_gold_wall.gd` does (a Node whose `_ready()` never runs because it is never added to the
## tree) and overrides nothing at all — the treatment is the LIVE game code in `market_ui.gd`,
## which the arc already mirrors through `_offer_price`/`_offers_this_week`. A second copy of the
## recruit rules here would be this project's signature failure repeated.
##
## THE QUESTION. The team grows at Copper (1->2), Bronze (2->3), Silver (3->4) and Platinum
## (4->5). At each step the player must own another body. Two things could be wrong and they want
## different fixes, so both are measured before either is touched:
##   (a) PRICE   — can the rung BELOW the step pay for the body the step demands?
##   (b) USEFULNESS — what does the body that arrives actually look like next to the ones already
##       on the sheet? A recruit far below the incumbents is dead weight for years, and it is what
##       drags `fill@exit` down at exactly the rung the team grows.
extends Node

const ArcScript = preload("res://scripts/_probe_career_arc.gd")
const MarketScript = preload("res://scripts/ui/market_ui.gd")
const TournamentScript = preload("res://scripts/ui/tournament_ui.gd")
const ShopScript = preload("res://scripts/ui/shop_ui.gd")

const SEEDS := [20260809, 771013, 313373, 4242424, 99180]
const ARC_WEEKS := 900
const SAMPLE_WEEKS := 60     ## market weeks sampled per rung in sections 1/2

var _ok := true
var _notes: Array[String] = []
var _tree: SceneTree


class ArcRun extends ArcScript:
	var v_seed: int = 20260809
	## `false` re-creates the market EXACTLY as `_probe_career_arc.gd` shipped it (the flat
	## 120 + 520*frac price and the 0.05..0.5 x 0.6 rookie band), so the control row in section 3
	## is the real before-picture and not a re-run of the treatment.
	var v_graded_market: bool = true
	var v_age_mult: float = 1.0          ## 0.0 = a graded market whose bodies arrive YOUNG
	## ⚠️ THE BUYER, NOT THE MARKET. `_probe_career_arc.gd`'s recruit loop takes the offer with the
	## highest STAT TOTAL among everything it can technically afford, with no regard to what the
	## gold was otherwise for. That is fine against a market where every body costs 255-341g and
	## is therefore not a policy at all; against a graded market it means the autopilot ALWAYS
	## buys the dearest thing on the stall. No player plays like that. >0 caps a single body at
	## this fraction of current gold, which is the smallest possible seam that turns the greedy
	## buyer into a budgeting one — and it is a POLICY row, so a win here says the market is fine
	## and the autopilot is not, exactly as the succession row did for the barn price.
	var v_budget_frac: float = 0.0

	## Injects a seed the parent pins as a const.
	func _reset_career() -> void:
		Career.reset_new_game()
		Roster.reset_to_empty()
		Roster.rng.seed = v_seed
		WeekPlan.plans.clear()
		WeekPlan._rng.seed = v_seed
		WeekPlan.reroll_food_prices()

	## ⚠️ THE TREATMENT IS NOT WRITTEN HERE — IT IS DELEGATED TO THE LIVE GAME.
	## `_probe_career_arc.gd` carries its own hand-copied mirror of the market (`_offers_this_week`
	## / `_offer_price`), written when those rules lived inside `market_ui.gd`. They now live in
	## `roster.gd`, so the mirror is a second copy that will drift — the integrator must replace
	## the parent's two functions with exactly these two lines and delete this override. Until
	## then this is the seam that lets the arc fight the shipped market.
	func _offers_this_week() -> Array:
		var out: Array = super() if not v_graded_market \
			else Roster.market_offers(Career.week, _offer_count(), -1, v_age_mult)
		if v_budget_frac <= 0.0:
			return out
		var ceiling: float = float(Career.gold) * v_budget_frac
		var afford: Array = out.filter(func(o): return float(o["price"]) <= ceiling)
		if afford.is_empty():
			# never starve the loop of every option — leave the single cheapest body standing, so
			# a budget policy can still fill a team-size step when nothing is comfortable.
			var cheapest: Dictionary = {}
			for o in out:
				if cheapest.is_empty() or int(o["price"]) < int(cheapest["price"]):
					cheapest = o
			return [] if cheapest.is_empty() else [cheapest]
		return afford

	func _offer_price(mi) -> int:
		if not v_graded_market:
			return super(mi)
		return Roster.market_price(mi)


func _ready() -> void:
	_tree = get_tree()
	print("=== RECRUIT PROBE ===")
	print("  caps       %s" % str(_caps()))
	print("  team sizes %s" % str(_team_sizes()))
	print("  barn       %s" % str(_konst(ShopScript, "BARN_PRICES", [])))

	_canary()
	_section_1_offer()
	_section_2_afford()
	if not _has_arg("--quick"):
		_section_3_arcs()

	print("\n=== instrument notes ===")
	for n in _notes:
		print("  · %s" % n)
	print("\n=== recruit probe: %s ===" % ("OK" if _ok else "INSTRUMENT BROKEN"))
	_tree.quit(0 if _ok else 1)


func _has_arg(a: String) -> bool:
	return a in OS.get_cmdline_user_args() or a in OS.get_cmdline_args()


func _konst(scr: Script, name: String, dflt):
	var c: Dictionary = scr.get_script_constant_map()
	return c[name] if c.has(name) else dflt


func _caps() -> Array:
	var out: Array = []
	for i in range(Career.leagues.size()):
		out.append(int(Career.stat_cap_for_league(i)))
	return out


func _team_sizes() -> Array:
	var out: Array = []
	for i in range(Career.leagues.size()):
		out.append(Career.team_size_for_league(i))
	return out


func _lname(i: int) -> String:
	return str(Career.league_at(i).get("name", "?"))


func _mean_stat(mi) -> float:
	var t := 0.0
	for s in Classify.STATS:
		t += float(mi.stats.get(s, 0.0))
	return t / float(Classify.STATS.size())


# =============================================================================
# LIVENESS CANARY — prove the instrument can see a change before believing a number
# =============================================================================
## ⚠️ ROUND 10'S SLOPE PROBE PRINTED A CONFIDENT NUMBER FROM A DEAD MODEL. Everything below reads
## the market through `_offers_at()`, which drives the LIVE `market_ui.gd` constants. If that path
## is not actually live, every table in this file is fiction — so move the league and assert the
## offer moves with it.
func _canary() -> void:
	print("\n─── 0. LIVENESS CANARY ───")
	Career.reset_new_game()
	Roster.reset_to_empty()
	Career.league_index = 0
	var lo: float = _best_offer_mean(0, 40)
	Career.league_index = 10
	var hi: float = _best_offer_mean(10, 40)
	Career.league_index = 0
	var live: bool = hi > lo + 1.0
	print("  best market offer, mean stat/stat:  Wood %.0f   Apex %.0f   -> %s" % [
		lo, hi, "LIVE" if live else "DEAD"])
	if not live:
		_ok = false
		_notes.append("CANARY FAILED: the market offer does not respond to the league — sections 1-2 are fiction")


# =============================================================================
# 1. WHAT ARRIVES — the recruit next to the monsters already on the sheet
# =============================================================================
## The arc's own measured `fill@exit` per rung, from the control run in `_probe_gold_wall.gd`
## section 1 — quoted so the table can put the recruit NEXT TO the incumbents without paying for
## a whole arc. Section 3 re-measures the same quantity live.
const ARC_FILL_AT_EXIT := [0.44, 0.39, 0.43, 0.67, 0.56, 0.67, 0.66, 0.52, 0.63, 0.61, 0.62]

## The BEFORE column, RECORDED from this same probe run against the pre-graded market on
## 2026-08-09 — not re-derived, because a re-derivation would mean keeping a copy of the retired
## formula alive in this file forever, which is the thing the rework was for.
const OLD_BEST_OFFER := [42, 68, 89, 118, 145, 168, 206, 243, 259, 279, 285]
const OLD_BEST_PRICE := [340, 297, 274, 274, 271, 266, 263, 260, 255, 258, 255]


## ⚠️ NO MIRROR. This calls the LIVE market — `Roster.market_offers()`, the same function
## `market_ui.gd` renders — so there is nothing here that can drift away from the game. Every
## number this file prints is a statement about the shipped rules.
func _offers_at(week: int) -> Array:
	return Roster.market_offers(week, int(_konst(MarketScript, "OFFER_COUNT", 4)))


## Mean stat/stat of the offer the autopilot would take (highest stat total), averaged over weeks.
func _best_offer_mean(idx: int, weeks: int) -> float:
	var acc := 0.0
	var n := 0
	for w in range(1, weeks + 1):
		var best = null
		for o in _offers_at(w * 3 + idx * 7):
			if best == null or _mean_stat(o["mi"]) > _mean_stat(best):
				best = o["mi"]
		if best != null:
			acc += _mean_stat(best)
			n += 1
	return acc / maxf(1.0, float(n))


func _section_1_offer() -> void:
	print("\n─── 1. WHAT ARRIVES — the market body vs the bodies already on the sheet ───")
	print("  'incumbent' = the arc's own measured fill@exit x the rung's cap: what is already on the sheet.")
	print("  BEFORE = the ungraded market this replaced (recorded 2026-08-09, same probe).")
	print("")
	print("  league        cap  team | BEFORE best/price | prospect     journeyman    veteran      | incumbent  vet/inc  steps?")
	Career.reset_new_game()
	Roster.reset_to_empty()
	var prev_team: int = 0
	for i in range(Career.leagues.size()):
		Career.league_index = i
		var cap: float = Career.stat_cap_for_league(i)
		var team: int = Career.team_size_for_league(i)
		var acc := {"prospect": [0.0, 0.0, 0], "journeyman": [0.0, 0.0, 0], "veteran": [0.0, 0.0, 0]}
		for w in range(1, SAMPLE_WEEKS + 1):
			for o in _offers_at(w * 3 + i * 7):
				var g: String = str(o["grade"])
				acc[g][0] += _mean_stat(o["mi"])
				acc[g][1] += float(o["price"])
				acc[g][2] += 1
		var cells: Array = []
		for g in ["prospect", "journeyman", "veteran"]:
			var n: float = maxf(1.0, float(acc[g][2]))
			if int(acc[g][2]) == 0:
				cells.append("       —      ")
			else:
				cells.append("%4.0f @%5.0fg " % [acc[g][0] / n, acc[g][1] / n])
		var vet_n: float = maxf(1.0, float(acc["veteran"][2]))
		var vet_mean: float = (acc["veteran"][0] / vet_n) if int(acc["veteran"][2]) > 0 else 0.0
		var incumbent: float = ARC_FILL_AT_EXIT[i] * cap
		var step := "  <-- TEAM GROWS" if (i > 0 and team > prev_team) else ""
		prev_team = team
		print("  %-12s %4d  %4d | %5d @%5dg    | %s %s %s| %9.0f  %6.2f%s" % [
			_lname(i), int(cap), team, OLD_BEST_OFFER[i], OLD_BEST_PRICE[i],
			cells[0], cells[1], cells[2], incumbent,
			vet_mean / maxf(1.0, incumbent), step])
	Career.league_index = 0


# =============================================================================
# 2. WHAT IT COSTS — against the income of the rung BELOW the one that needs it
# =============================================================================
## ⚠️ THE RIGHT DENOMINATOR IS THE RUNG BELOW. A body demanded by the Silver step has to be bought
## with Bronze/Iron money, because it must be on the sheet BEFORE the first Silver cup. Pricing it
## against Silver's purse is pricing it against income the player cannot have yet.
func _section_2_afford() -> void:
	print("\n─── 2. WHAT IT COSTS — against the purse of the rung BELOW the step ───")
	var base_purse: int = int(_konst(TournamentScript, "BASE_PURSE", 220))
	var purse_step: int = int(_konst(TournamentScript, "PURSE_PER_LEAGUE", 140))
	var base_fee: int = int(_konst(TournamentScript, "BASE_FEE", 30))
	var fee_step: int = int(_konst(TournamentScript, "FEE_PER_LEAGUE", 22))
	var barn: Array = _konst(ShopScript, "BARN_PRICES", [])
	print("  step at        prev purse  prev fee  net win  cheapest  dearest  barn slot  floor ask  floor/win")
	var prev_team: int = 0
	Career.reset_new_game()
	Roster.reset_to_empty()
	for i in range(Career.leagues.size()):
		var team: int = Career.team_size_for_league(i)
		if i == 0 or team <= prev_team:
			prev_team = team
			continue
		prev_team = team
		var p: int = base_purse + purse_step * (i - 1)
		var f: int = base_fee + fee_step * (i - 1)
		Career.league_index = i - 1
		var lo_acc := 0.0
		var hi_acc := 0.0
		var n := 0
		for w in range(1, SAMPLE_WEEKS + 1):
			var lo := 1 << 30
			var hi := 0
			for o in _offers_at(w * 3 + i * 7):
				lo = mini(lo, int(o["price"]))
				hi = maxi(hi, int(o["price"]))
			if hi > 0:
				lo_acc += float(lo); hi_acc += float(hi); n += 1
		lo_acc /= maxf(1.0, float(n))
		hi_acc /= maxf(1.0, float(n))
		var slot: int = int(barn[team]) if team < barn.size() else -1
		# ⚠️ THE FLOOR IS WHAT DECIDES WHETHER THE STEP IS ENTERABLE AT ALL — the cheapest body on
		# the stall plus the barn slot it has to sleep in. The dearest body is a choice; the floor
		# is the gate.
		var ask: float = lo_acc + float(maxi(0, slot))
		print("  %-12s %11d  %8d  %7d  %8.0f  %7.0f  %9d  %9.0f  %9.2f" % [
			_lname(i), p, f, p - f, lo_acc, hi_acc, slot, ask, ask / maxf(1.0, float(p - f))])
	Career.league_index = 0
	print("  (a cup WON pays the full purse; 2nd pays 65%, 3rd 40%, below that nothing)")


# =============================================================================
# 3. THE ARC — five seeds, live game code, before/after is the diff of two runs of this
# =============================================================================
## ⚠️ PAIRED, AND THE CONTROL IS RUN IN THE SAME PROCESS AS THE TREATMENT. Same seeds, same
## autopilot, same everything — the ONLY difference is `v_graded_market`. Reporting a treatment
## against a control measured in a different session on a different build is how this project has
## twice convinced itself of a change that did nothing.
func _section_3_arcs() -> void:
	print("\n─── 3. THE ARC — %d seeds, paired: ungraded market vs graded market ───" % SEEDS.size())
	var arms := {
		"control": _arc_arm(false, 1.0, 0.0, "CONTROL (ungraded market — the shipped 0.05..0.5 rookie band, flat price)"),
		"graded": _arc_arm(true, 1.0, 0.0, "GRADED (prospect/journeyman/veteran, priced off the cap)"),
		"graded+budget": _arc_arm(true, 1.0, 0.40, "GRADED + BUDGETING BUYER (no body may cost >40%% of gold — a POLICY row)"),
	}
	print("\n  ── paired verdict (n=%d seeds, same seeds, same process, same career.gd) ──" % SEEDS.size())
	for arm in ["graded", "graded+budget"]:
		var better := 0
		var worse := 0
		var tie := 0
		for i in range(SEEDS.size()):
			var d: int = int(arms[arm][i]["reached"]) - int(arms["control"][i]["reached"])
			if d > 0: better += 1
			elif d < 0: worse += 1
			else: tie += 1
		print("  %-14s vs control on `reached`:  %d better · %d worse · %d tie" % [arm, better, worse, tie])
		if better <= worse:
			_notes.append("section 3: `%s` did NOT beat the control on `reached` (%d better / %d worse) — report the null, do not re-tune to it" % [arm, better, worse])
	for key in ["reached", "weeks", "recruits", "blocked", "frontierBlocked"]:
		print("  %s" % key)
		for arm in ["control", "graded", "graded+budget"]:
			var v: Array = []
			for i in range(SEEDS.size()):
				v.append(int(arms[arm][i][key]))
			var s: Array = v.duplicate(); s.sort()
			print("    %-14s %-24s med %d" % [arm, str(v), s[s.size() / 2]])


func _arc_arm(graded: bool, age_mult: float, budget_frac: float, label: String) -> Array:
	print("\n  %s" % label)
	print("  seed        reached          wks  recruits  blockedRecruit  frontierBlockedWks  fill@exit")
	var out: Array = []
	for s in SEEDS:
		var v := ArcRun.new()
		v.v_seed = s
		v.v_graded_market = graded
		v.v_age_mult = age_mult
		v.v_budget_frac = budget_frac
		var a: Dictionary = v._run_arc(ARC_WEEKS, {})
		var idx: int = int(a["finalLeague"])
		var fills: Array = []
		for r in a["perLeague"]:
			if int(r["weeks"]) > 0 or int(r["cups"]) > 0:
				fills.append("%.0f" % (float(r["fillAtExit"]) * 100.0))
		print("  %-10d  %-14s %5d  %8d  %14d  %18d  %s" % [
			s, _lname(idx), int(a["weeks"]), int(a["recruits"]),
			int(a["blockedRecruit"]), int(a.get("frontierBlockedWeeks", 0)), "/".join(fills)])
		out.append({
			"reached": idx, "weeks": int(a["weeks"]), "recruits": int(a["recruits"]),
			"blocked": int(a["blockedRecruit"]),
			"frontierBlocked": int(a.get("frontierBlockedWeeks", 0)),
		})
		v.free()
	return out
