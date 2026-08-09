## THE CAREER-ARC INSTRUMENT — what does PLAYING this game actually look like, end to end?
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_career_arc.tscn
##
## ⚠️ WHY THIS EXISTS. `_probe_career_loop.gd` proves the loop is REACHABLE (149 checks, title ->
## town -> ... -> save/load). Nothing in this repo has ever asked whether the loop is WORTH
## walking: how many weeks Wood-to-Apex takes, whether gold is ever scarce, whether the climb
## walls or is monotonic, whether a monster's lifespan ever forces turnover. `docs/OUTSTANDING.md`
## §3 says the biggest unchecked assumption in the project is whether this is fun, and that there
## is not one playtest record in the repo. This is the closest a machine can get to one: an
## autopilot that plays a whole career and reports the shape of it.
##
## ⚠️ IT RUNS AS A SCENE, NEVER `--script`. It needs the Career/Roster/GameData/WeekPlan autoloads,
## which do not exist under SceneTree script mode.
##
## FIVE INSTRUMENTS, each answering one pacing question:
##   1. THE ARC       — autopilot plays Wood -> Apex; per-league weeks, gold, cups, roster churn.
##   2. THE GRIND     — how much gold is obtainable per WEEK OF GAME TIME, i.e. is gold scarce?
##   3. THE WALL      — win rate of a cap-trained team vs each league's rivals. Does it wall?
##   4. THE GYM       — weeks of training to fill a league's stat cap, against a lifespan.
##   5. THE CHOICE    — four training policies over the same weeks. Is the week a real decision?
##
## ⚠️ DETERMINISM. Every generator here is seeded; the arc is run TWICE and the two runs are
## compared, so the next round can measure its own effect on the arc and trust the difference.
##
## ⚠️ WHAT THIS PROBE MIRRORS, AND WHY THAT IS ITSELF A FINDING. The purse formula lives in
## `scripts/ui/tournament_ui.gd`, the barn prices in `shop_ui.gd`, the recruit price in
## `market_ui.gd`, the breeding rules in `breeding_ui.gd` — all of them in UI scripts, none of
## them reachable from a headless model layer. Rather than re-type those numbers (which would
## rot), this file PRELOADS those scripts and reads their constants. The economy having no
## model-layer home is reported in docs/META_GAME_REVIEW.md as finding E1.
extends Node

const WeekLib = preload("res://scripts/week.gd")
const BattleSimScript = preload("res://scripts/battle_sim.gd")
const TacticsScript = preload("res://scripts/tactics.gd")

# ⚠️ THE ECONOMY LIVES IN UI SCRIPTS. Read, never copied — see the header note.
const ShopScript = preload("res://scripts/ui/shop_ui.gd")
const TournamentScript = preload("res://scripts/ui/tournament_ui.gd")
const MarketScript = preload("res://scripts/ui/market_ui.gd")
const BreedScript = preload("res://scripts/ui/breeding_ui.gd")

# ── autopilot knobs ──────────────────────────────────────────────────────────
const SEED := 20260809
## ⚠️ RAISED FROM 600. At 600 the competent autopilot was still climbing when the budget ran out
## and the run reported "stopped at Masters", which reads like a wall and is not one — it is the
## instrument's own edge. The question this probe exists to answer is whether the ladder is
## COMPLETABLE, and a horizon that cannot contain the answer cannot report it. 1000 weeks is 20.8
## in-game years; if the climb needs that, THAT is the finding.
const MAX_WEEKS := 1000
const CUP_INTERVAL := 4          # the autopilot tries the frontier cup monthly
## ⚠️ NO LONGER A CONSTANT — kept only as the fallback for a league name this build does not know.
## `tournament_ui.gd` USED to hardcode `CupRun.start(idx, 3)`; it now passes no count at all and
## the league's own field size decides (`Career.rival_count_for_league`: 3 at the bottom, 4 at
## Silver/Gold, 5 from Platinum up). Pinning 3 here made this instrument measure a Platinum cup as
## a sweep of THREE when the player has to sweep FIVE — and a sweep is w^n, so that is not a small
## error. This is the integration seam that made the arc read byte-identical across the round.
const RIVAL_COUNT_FALLBACK := 3
const STALL_WEEKS := 150         # no promotion in this long at one league = the run has walled
const GOLD_RESERVE := 60         # keep enough to feed the stable for a few weeks
## Mean stamina a rest week returns — `week.gd:apply_activity` rolls 30..100 in steps of 5, flat,
## regardless of how much the previous weeks spent. See `_drill_plan`.
const MEAN_REST_RECOVERY := 65.0
const BREED_GOLD_FLOOR := 700    # only breed when gold is genuinely spare
const BREED_COOLDOWN := 24

## ⚠️ THE BENCH, THE FREEZER AND THE DYNASTY — the half of the game this autopilot could not play.
## Until now it recruited exactly enough bodies to field the league's team and never touched
## `Roster.preserve()`, so `Roster.breeding_stock()` (which is the FREEZER and nothing else) was
## permanently empty and `breeds` was pinned at 0 by construction, not by measurement. Every
## "breeding never fires" number this instrument has ever printed was a statement about the
## autopilot, not about the game.
##
## What a competent player does, and what these knobs now encode:
##   · keep a SPARE body so a retirement is not a forfeit  (BENCH_SIZE)
##   · put an ageing champion in the freezer while it is still good — that is the decision
##     `breeding_ui.gd` says the system is FOR: "is this line worth taking out of competition"
##     (PRESERVE_MARGIN_WEEKS)
##   · hold a small stock of founders, because the freezer bills 12g/week forever (FREEZER_TARGET)
##   · raise the potential ceiling with children, because `week.gd:stat_cap_for` is
##     `league_cap × potential` and above Gold the league cap is NOT reachable in one lifespan
const BENCH_SIZE := 1               ## spare bodies beyond the league's fielded team
const BENCH_GOLD_FLOOR := 900       ## …and only bought out of genuine surplus. See the arc loop.
const FREEZER_TARGET := 2           ## founders kept on ice; each costs RENTAL_PER_FROZEN a week
const PRESERVE_MARGIN_WEEKS := 32   ## preserve a monster this close to retiring, if cover exists

const RUN_TWICE := true          # determinism check
const DETERMINISM_WEEKS := 80    # the reproducibility check re-runs a SHORT arc, see _ready()

# ── instrument state ─────────────────────────────────────────────────────────
var _tree: SceneTree
var _notes: Array[String] = []
var _instrument_ok := true


func _ready() -> void:
	_tree = get_tree()
	print("=== CAREER ARC PROBE ===")
	print("seed %d · max %d weeks · cup attempt every %d weeks\n" % [SEED, MAX_WEEKS, CUP_INTERVAL])
	_check_mirrors()
	_check_cup_mirror()

	## ⚠️ `--gate-only` EXISTS SO THE LADDER CAN BE TUNED AT ALL. The full run is ~900 simulated
	## fights and takes many minutes; the difficulty endpoints in `career.gd` need to be nudged and
	## re-measured several times in a row, and an instrument too slow to sit in that loop does not
	## get used — the endpoints get guessed instead. This runs section 3b alone.
	if "--gate-only" in OS.get_cmdline_user_args() or "--gate-only" in OS.get_cmdline_args():
		_run_champion_gate()
		print("\n=== career arc probe (gate only): OK ===")
		_tree.quit(0)
		return

	var arc_a: Dictionary = _run_arc(MAX_WEEKS)
	_report_arc(arc_a)
	## ⚠️ READ OFF THE FULL ARC, BEFORE THE DETERMINISM CHECK OVERWRITES `arc_a` WITH AN 80-WEEK
	## ONE. The old check below asked the 80-week arc whether it had bred — which it never would
	## have, dynasty or no dynasty — so the warning it printed was about the wrong run.
	var full_breeds: int = int(arc_a.get("breeds", 0))
	var full_preserves: int = int(arc_a.get("preserves", 0))
	_first_preserve_week = int(arc_a.get("firstPreserveWeek", 0))
	_first_breed_week = int(arc_a.get("firstBreedWeek", 0))

	if RUN_TWICE:
		# ⚠️ THE DETERMINISM CHECK RUNS A SHORT ARC, NOT THE FULL ONE. Reproducibility is a
		# property of the seeded machinery, not of the week count — and a full second arc costs
		# ~450 more simulated fights, which would make this probe too slow to re-run casually.
		# A probe nobody re-runs is not an instrument.
		var arc_c: Dictionary = _run_arc(DETERMINISM_WEEKS)
		var arc_b: Dictionary = _run_arc(DETERMINISM_WEEKS)
		arc_a = arc_c
		var same: bool = (
			int(arc_a["weeks"]) == int(arc_b["weeks"])
			and int(arc_a["finalLeague"]) == int(arc_b["finalLeague"])
			and int(arc_a["goldEnd"]) == int(arc_b["goldEnd"])
			and int(arc_a["cups"]) == int(arc_b["cups"]))
		print("\n─── determinism ───")
		print("  run A: %d weeks, league %d, %dg   run B: %d weeks, league %d, %dg   -> %s" % [
			int(arc_a["weeks"]), int(arc_a["finalLeague"]), int(arc_a["goldEnd"]),
			int(arc_b["weeks"]), int(arc_b["finalLeague"]), int(arc_b["goldEnd"]),
			"IDENTICAL" if same else "DIVERGED"])
		if not same:
			_instrument_ok = false
			_notes.append("the arc is NOT reproducible — every number below is suspect")

	## ⚠️ THE AUTOPILOT NOW KEEPS A BENCH, PRESERVES FOUNDERS AND BREEDS — so a zero here is a
	## MEASUREMENT, not a blind spot. If it still comes out zero the reason is in the game (gold,
	## barn slots, the freezer rent, the `MAX_CHILDREN_PER_PARENT` limit), and that is a finding
	## about the game rather than about this file. Above Gold the league cap is not reachable in
	## one lifespan (section 4), so `potential` — which only breeding raises — is the only thing
	## that can lift the ceiling. A run that reaches the top without ever breeding is telling you
	## the dynasty is optional; a run that stalls without breeding is telling you it is not.
	if full_breeds == 0:
		_notes.append("the autopilot bred 0 times DESPITE having a preserve/breed policy "
			+ "(%d preserves). That is now a statement about the game's own gates, not about "
			% full_preserves + "the instrument — check gold, barn slots and freezer rent.")

	_run_sensitivity()
	_run_grind()
	_run_wall()
	_run_champion_gate()
	_run_gym()
	_run_choice()

	print("\n=== instrument notes ===")
	if _notes.is_empty():
		print("  (none)")
	for n in _notes:
		print("  · %s" % n)
	print("\n=== career arc probe: %s ===" % ("OK" if _instrument_ok else "INSTRUMENT BROKEN"))
	_tree.quit(0 if _instrument_ok else 1)


## ⚠️ READ THROUGH THE CONSTANT MAP, NEVER AS `Script.CONST`. A bare `BreedScript.BREED_COST` is
## resolved at PARSE time, so the instant a teammate renames a constant in a UI script this whole
## probe stops loading — which is exactly what happened mid-round while `breeding_ui.gd` was being
## reworked. An instrument that four people's edits can take offline is not an instrument. Every
## fallback below is the value read on 2026-08-09; a fallback actually being used is REPORTED, so
## a silently stale number can never masquerade as a live one.
var _fell_back: Array[String] = []

func _konst(script: GDScript, name: String, fallback):
	var m: Dictionary = script.get_script_constant_map()
	if m.has(name):
		return m[name]
	_fell_back.append("%s.%s" % [script.resource_path.get_file(), name])
	return fallback

func _barn_prices() -> Array: return _konst(ShopScript, "BARN_PRICES", [0, 0, 320, 700, 1400, 2600])
func _base_purse() -> int: return int(_konst(TournamentScript, "BASE_PURSE", 220))
func _purse_step() -> int: return int(_konst(TournamentScript, "PURSE_PER_LEAGUE", 140))
func _drop_frac() -> Array: return _konst(TournamentScript, "REWARD_BY_DROP", [1.0, 0.5, 0.2])
func _offer_count() -> int: return int(_konst(MarketScript, "OFFER_COUNT", 4))
func _refund_frac() -> float: return float(_konst(MarketScript, "RELEASE_REFUND_FRAC", 0.35))
func _breed_cost() -> int: return int(_konst(BreedScript, "BREED_COST", 300))
## ⚠️ THE HEAD-START / POTENTIAL-STEP / MAX-POTENTIAL MIRRORS ARE GONE ON PURPOSE. `_try_breed`
## calls `breeding_ui.gd:_make_child` directly now, so there is nothing left to re-derive — and
## one of the three (`POTENTIAL_STEP`) had already been renamed in that file, meaning this probe
## was quietly running on a stale fallback that halved a dynasty's climb.
func _breed_max_children() -> int: return int(_konst(BreedScript, "MAX_CHILDREN_PER_PARENT", 2))
func _base_fee() -> int: return int(_konst(TournamentScript, "BASE_FEE", 30))
func _fee_step() -> int: return int(_konst(TournamentScript, "FEE_PER_LEAGUE", 22))

## How many teams a cup fields — read from the model layer, not pinned. See `RIVAL_COUNT_FALLBACK`.
func _rounds_for(idx: int) -> int:
	if Career.has_method("rival_count_for_league"):
		return maxi(1, Career.rival_count_for_league(idx))
	_fell_back.append("career.gd.rival_count_for_league")
	return RIVAL_COUNT_FALLBACK

## `tournament_ui.gd:_fee_for` — entry costs gold now, and the bottom rung waives it when the
## player cannot pay (the deliberate softlock backstop). Mirrored exactly, waiver included.
func _entry_fee(idx: int) -> int:
	var fee: int = _base_fee() + _fee_step() * idx
	if idx == 0 and Career.gold < fee:
		return 0
	return fee


## The mirrored constants must exist and be sane, or every gold figure below is fiction.
func _check_mirrors() -> void:
	print("mirrors: barn %s · purse %d+%d/league · drop %s · offers %d · breed %dg" % [
		str(_barn_prices()), _base_purse(), _purse_step(),
		str(_drop_frac()), _offer_count(), _breed_cost()])
	if not _fell_back.is_empty():
		_notes.append("⚠️ MIRROR FELL BACK to a hardcoded 2026-08-09 value for: %s" % ", ".join(_fell_back))
		print("  ⚠️ fell back (source constant moved): %s" % ", ".join(_fell_back))


# =============================================================================
# SHARED HELPERS
# =============================================================================

func _reset_career() -> void:
	Career.reset_new_game()
	Roster.reset_to_empty()
	# ⚠️ Reaching into two seeded RNGs that the game seeds once at boot. Each experiment must start
	# from the same stream or "run it again" means something different every time.
	Roster.rng.seed = SEED
	WeekPlan.plans.clear()
	WeekPlan._rng.seed = SEED
	WeekPlan.reroll_food_prices()


func _stat_total(mi) -> float:
	var t := 0.0
	for s in Classify.STATS:
		t += float(mi.stats.get(s, 0.0))
	return t


## Mean fraction of the CURRENT league cap the roster has actually filled.
func _roster_fill(monsters: Array, cap: float) -> float:
	if monsters.is_empty() or cap <= 0.0:
		return 0.0
	var acc := 0.0
	for mi in monsters:
		acc += _stat_total(mi) / (cap * float(Classify.STATS.size()))
	return acc / float(monsters.size())


## `market_ui.gd:_estimate_value` — mirrored so a recruit costs the autopilot what it costs a player.
func _offer_price(mi) -> int:
	var cap: float = GameData.stat_cap()
	var frac: float = clampf(_stat_total(mi) / maxf(1.0, cap * float(Classify.STATS.size())), 0.0, 1.0)
	return int(round(120.0 + frac * 520.0))


## `market_ui.gd:_generate_offers` — same pool, same per-week seed, same training-level band.
func _offers_this_week() -> Array:
	var owned := {}
	for m in Roster.monsters:
		owned[m.species_id] = true
	var pool: Array = Art.ROSTER.filter(func(id): return not owned.has(id))
	if pool.size() < _offer_count():
		pool = Art.ROSTER.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = Career.week * 104729
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]; pool[i] = pool[j]; pool[j] = tmp
	var out: Array = []
	for i in range(mini(_offer_count(), pool.size())):
		var t := rng.randf_range(0.05, 0.5)
		var mi = GameData.make_monster(pool[i], t, rng)
		if mi != null:
			out.append({"mi": mi, "price": _offer_price(mi)})
	return out


## `tournament_ui.gd:_purse_for` x the PLACEMENT fraction — the purse is paid in the UI, so the
## model layer cannot compute it. Mirrored here.
## ⚠️ WAS `wins / rounds` AND THAT IS NO LONGER THE GAME. `tournament_ui.gd:_show_result` now pays
## `town.ts:PLACEMENT_REWARD_FRACTION` (100/65/40/0 by final placing). The two disagree sharply at
## the shoulders — 2 wins of 3 paid 67% of the purse under the old mirror and pays 65% now, but 1
## win of 3 paid 33% and now pays NOTHING. Mid-table is worthless, near-misses still pay. Reading
## the fraction off `Career` rather than re-deriving it means this cannot drift again.
func _purse_paid(idx: int, wins: int, rounds: int) -> int:
	var drop: int = clampi(Career.league_index - idx, 0, _drop_frac().size() - 1)
	var base: int = _base_purse() + _purse_step() * idx
	var full: int = int(round(float(base) * float(_drop_frac()[drop])))
	var placement: int = Career.placement_for(wins, rounds)
	return int(round(float(full) * Career.placement_reward_fraction(placement)))


## THE TRAINING BRAIN. Scores all 30 drills by expected USEFUL stat points per stamina point,
## where "useful" means room left under the cap. This is the "advanced training knowledge" the
## vision asks the player to earn — the autopilot simply has it, which is the point: it measures
## the ceiling of good play, not the floor of bad play.
##
## Returns {"mode": "train"|"rest"|"idle", "id": drill id}. ⚠️ "idle" and "rest" are DIFFERENT
## and conflating them is an instrument bug this probe already made once: "rest" means the body
## is spent and the week buys stamina back; "idle" means every raisable stat is at the LEAGUE
## CEILING and the week buys nothing at all. Only the second one is a design problem.
## ⚠️ THE POLICY THE ARC ACTUALLY PLAYS, AND IT IS ONE LINE LONG: put the biggest drill in the
## game on whichever stat is lowest; rest when you cannot afford it. Instrument 5 measures this
## at 14.45 points/week against 11.38 for the 30-drill expected-value optimiser below — a DUMBER
## policy beating a smarter one by 27%. The arc must be judged against the best play known, not
## against a clever-looking one, so this is what it uses. That the ceiling of training skill is a
## one-liner is finding T1 in docs/META_GAME_REVIEW.md.
func _drill_plan_greedy(mi, league_cap: float) -> Dictionary:
	## ⚠️ THE CEILING IS PER MONSTER, NOT PER LEAGUE (`week.gd:stat_cap_for` = league cap ×
	## potential). Passing the raw league cap made the planner call a bred monster "capped" while
	## the tick was still happily training it — invisible while `potential` was pinned at ×1.00
	## because the autopilot never bred, and wrong the moment it does.
	var cap: float = WeekLib.stat_cap_for(mi, league_cap)
	var any_room := false
	for s in Classify.STATS:
		if float(mi.stats.get(s, 0.0)) < cap - 0.5:
			any_room = true
			break
	if not any_room:
		return {"mode": "idle", "id": ""}
	var low: String = Classify.STATS[0]
	for s in Classify.STATS:
		if float(mi.stats.get(s, 0.0)) < float(mi.stats.get(low, 0.0)):
			low = s
	if mi.stamina >= WeekLib.EXTREME_DRILL_STAMINA:
		return {"mode": "train", "id": "x" + low.to_lower()}
	return {"mode": "rest", "id": ""}


func _drill_plan(mi, league_cap: float) -> Dictionary:
	var cap: float = WeekLib.stat_cap_for(mi, league_cap)   # see `_drill_plan_greedy`
	var best_id := ""
	var best_per := -INF
	var any_gain := false
	for d in WeekLib.DRILLS:
		var stam: float = WeekLib.drill_stamina(str(d.get("kind", "basic")))
		var score := 0.0
		for stat in d["gains"]:
			var base: float = float(d["gains"][stat])
			var cur: float = float(mi.stats.get(stat, 0.0))
			if base > 0.0:
				# expected roll is base + range/2 at high happiness; aptitude scales it
				## ⚠️ FOCUS COST IS IN THE SCORE NOW, AND WITHOUT IT T1 WAS A STRAWMAN. `week.gd`
				## gained a focus cost this round — a drill pays less into a stat the further that
				## stat already leads (`apply_activity` multiplies by `focus_cost`). An optimiser
				## blind to the game's newest mechanic is not "the sophisticated policy", it is a
				## broken one, and reporting that it loses to a one-liner would have been a
				## measurement of this file rather than of the game.
				var expected: float = ((base + roundi(base / 3.0) * 0.5)
					* WeekLib.stat_training_bonus(mi, stat) * WeekLib.focus_cost(mi, stat))
				score += minf(expected, maxf(0.0, cap - cur))
			else:
				score += base * WeekLib.stat_malus_multiplier(mi, stat)
		if score > 0.0:
			any_gain = true
		if stam > mi.stamina:
			continue
		# ⚠️ VALUE PER WEEK-CYCLE, NOT PER STAMINA POINT — and the difference is the whole story
		# of how stamina works here. `week.gd`'s rest restores a FLAT 30..100 (mean ~65) no matter
		# how much was spent, so stamina is not a currency you budget: a 35-cost drill and a
		# 15-cost drill both cost roughly one rest week eventually. Scoring per stamina (which
		# this probe did first) picks cheap basics and measures 2051 points where the naive
		# "always the biggest drill" policy measures 2889. Long-run value is
		# `gain / (1 + cost/REST)`, and under it the most expensive drill essentially always wins.
		var per := score / (1.0 + stam / MEAN_REST_RECOVERY)
		if per > best_per:
			best_per = per
			best_id = str(d["id"])
	if not any_gain:
		return {"mode": "idle", "id": ""}
	if best_id == "" or best_per <= 0.0:
		return {"mode": "rest", "id": ""}
	return {"mode": "train", "id": best_id}


# =============================================================================
# 1. THE ARC — an autopilot career, Wood toward Tamers Apex
# =============================================================================

## `opts` is how this instrument is PERTURBED, and section 6 exists to prove each knob moves the
## arc. Defaults reproduce the autopilot's best-known play:
##   breed      : bool  — run the bench/freezer/dynasty policy at all
##   policy     : "greedy" | "optimiser" — which training brain plans the week
##   feeMult    : float — scales the cup entry fee
##   rivalMult  : float — scales every rival team's fill (see `_fight_cup`)
func _run_arc(max_weeks: int, opts: Dictionary = {}) -> Dictionary:
	_reset_career()

	var per_league: Array = []
	for i in range(Career.leagues.size()):
		per_league.append({
			"weeks": 0, "goldIn": 0, "goldOut": 0, "cups": 0, "rounds": 0, "roundWins": 0,
			"recruits": 0, "barnBuys": 0, "breeds": 0, "retirements": 0,
			"fillAtExit": 0.0, "brokeWeeks": 0,
		})

	var last_cup_week := -CUP_INTERVAL
	var last_breed_week := -BREED_COOLDOWN
	var league_start_week := 0
	var stall_reason := ""
	var gold_peak: int = Career.gold
	var train_weeks := 0
	var rest_weeks := 0
	var capped_weeks := 0            # weeks a monster had nothing left to train — the league ceiling
	var excursion_weeks := 0
	var decisions := 0               # every point at which a player would have to choose something
	var blocked_recruit := 0
	var fees_paid := 0               # total entry fees — the ladder's first real gold sink
	var cups_refused_by_fee := 0     # cups the autopilot could not afford to enter
	var preserves := 0               # monsters moved into the freezer (the only breeding stock)
	var releases := 0                # monsters let go for the refund
	var rent_paid := 0               # freezer rent — the standing cost of running a dynasty
	var travel_weeks := 0            # weeks of game time spent ON THE ROAD to cups (see below)
	var greedy: bool = str(opts.get("policy", "greedy")) == "greedy"
	var bench_weeks := 0             # monster-weeks spent by bodies outside the fielded team
	var frontier_blocked_weeks := 0  # weeks the frontier cup was unenterable for want of BODIES
	var first_preserve_week := 0     # when the generational half of the game first does anything
	var first_breed_week := 0

	while Career.week < max_weeks and not Career.won_game:
		var idx: int = Career.league_index
		var cap: float = Career.current_stat_cap()
		var L: Dictionary = per_league[idx]

		# ── recruit / barn, so the frontier cup is enterable at all ──────────
		# ⚠️ THE LADDER COMES FIRST AND THE BENCH COMES OUT OF SURPLUS — measured, not assumed.
		# The first version of this bought a bench body as eagerly as a starter, and the arc got
		# WORSE: gold that should have bought barn slots and cup entries went on a spare mouth,
		# recruiting was blocked 18 times, and the run stalled a whole league lower than the
		# benchless autopilot. A bench is correct play; buying one you cannot afford is not.
		# So: the BARN is only ever bought for the team, and the spare body only when gold is
		# genuinely spare and there is already a slot standing empty.
		var team_need: int = Career.current_team_size()
		var need: int = team_need
		if bool(opts.get("breed", true)) and Career.gold >= BENCH_GOLD_FLOOR \
				and Career.barn_capacity > team_need:
			need = team_need + BENCH_SIZE
		## ⚠️ THE BENCH WAS UNREACHABLE BY CONSTRUCTION AND EVERY "the autopilot never bred /
		## never benched" NUMBER IN META_GAME_REVIEW RESTS ON THIS LOOP. The guard above asks for
		## `barn_capacity > team_need`, and this loop grew the barn only UP TO `team_need` — so the
		## condition was false at every rung above Wood, forever. Measured: benchWeeks = 0 over a
		## 483-week career, and `_try_breed`'s own `monsters.size() >= barn_capacity` refusal meant
		## breeds = 0 and best potential x1.00 in every arc ever run. BENCH_SIZE, FREEZER_TARGET and
		## PRESERVE_MARGIN_WEEKS were all dead knobs downstream of it.
		##
		## The fix is the smallest one that opens the loop: the barn is still bought for the team
		## first and unconditionally, and the extra stall only out of genuine surplus. The finding in
		## the comment above — that buying a bench BODY eagerly made the arc worse — is untouched:
		## this buys the ROOM, and the body is still gated on a slot already standing empty.
		var barn_goal: int = team_need
		if bool(opts.get("breed", true)) and Career.gold >= BENCH_GOLD_FLOOR:
			barn_goal = team_need + BENCH_SIZE
		while Career.barn_capacity < barn_goal:
			var nxt: int = Career.barn_capacity + 1
			if nxt >= _barn_prices().size():
				if Career.barn_capacity < team_need:
					stall_reason = "barn cannot hold %d (max %d)" % [team_need, _barn_prices().size() - 1]
				break
			var bprice: int = _barn_prices()[nxt]
			## The team's own stalls are bought down to GOLD_RESERVE; the bench stall only out of
			## surplus, so a stable never starves its cup entries to buy a spare room.
			var bfloor: int = GOLD_RESERVE if nxt <= team_need else BENCH_GOLD_FLOOR
			if Career.gold < bprice + bfloor:
				break
			Career.spend_gold(bprice)
			L["goldOut"] = int(L["goldOut"]) + bprice
			Career.barn_capacity = nxt
			L["barnBuys"] = int(L["barnBuys"]) + 1
			decisions += 1
		## Re-asked AFTER the barn has grown: the pre-loop test could only ever see LAST week's
		## capacity, which is the other half of why the bench never filled.
		if bool(opts.get("breed", true)) and Career.gold >= BENCH_GOLD_FLOOR \
				and Career.barn_capacity > team_need:
			need = team_need + BENCH_SIZE
		while Roster.monsters.size() < need and Roster.monsters.size() < Career.barn_capacity:
			var offers: Array = _offers_this_week()
			var pick: Dictionary = {}
			for o in offers:
				if int(o["price"]) + GOLD_RESERVE > Career.gold:
					continue
				if pick.is_empty() or _stat_total(o["mi"]) > _stat_total(pick["mi"]):
					pick = o
			if pick.is_empty():
				blocked_recruit += 1
				break
			Career.spend_gold(int(pick["price"]))
			L["goldOut"] = int(L["goldOut"]) + int(pick["price"])
			pick["mi"].id = Roster.next_slot_id()
			Roster.monsters.append(pick["mi"])
			L["recruits"] = int(L["recruits"]) + 1
			decisions += 1

		# ── the bench, the freezer and the dynasty ───────────────────────────
		var mopts: Dictionary = {
			"preserve": bool(opts.get("breed", true)),
			"breed": bool(opts.get("breed", true)) and Career.week - last_breed_week >= BREED_COOLDOWN,
		}
		var churn: Dictionary = _manage_roster(mopts)
		if int(churn["bred"]) > 0:
			last_breed_week = Career.week
			if first_breed_week == 0:
				first_breed_week = Career.week
		if int(churn["preserved"]) > 0 and first_preserve_week == 0:
			first_preserve_week = Career.week
		L["goldOut"] = int(L["goldOut"]) + int(churn["breedGold"])
		L["breeds"] = int(L["breeds"]) + int(churn["bred"])
		preserves += int(churn["preserved"])
		releases += int(churn["released"])
		decisions += int(churn["preserved"]) + int(churn["released"]) + int(churn["bred"])

		# ── plan the week for every monster ─────────────────────────────────
		for mi in Roster.monsters:
			if mi.retired:
				continue
			decisions += 2  # an activity and a feeding choice, per monster, per week
			var fav_price: int = WeekPlan.price_of(mi.favourite_food)
			if fav_price > 0 and Career.gold >= fav_price + GOLD_RESERVE:
				WeekPlan.set_food(mi.id, mi.favourite_food)
			# ⚠️ NEVER FORAGE. forage_feed costs 25 stamina AND 2 happiness; going unfed costs
			# 1 happiness and nothing else. Foraging is strictly dominated by doing nothing —
			# see docs/META_GAME_REVIEW.md finding D3. The autopilot plays correctly, not
			# charitably.
			var plan := _drill_plan_greedy(mi, cap) if greedy else _drill_plan(mi, cap)
			# ⚠️ EXCURSION IS THE ONLY GOLD SOURCE THE WEEKLY CLOCK HAS. A monster with nothing
			# left to train, or a stable that cannot afford its next recruit, sends it out to
			# earn. Without this the autopilot deadlocks at Copper with 1 monster and 61 gold —
			# which is a real reachable state, reported as finding E3.
			var broke: bool = Career.gold < GOLD_RESERVE * 3
			if str(plan["mode"]) == "idle" or (broke and mi.stamina >= WeekLib.EXCURSION_COST):
				if mi.stamina >= WeekLib.EXCURSION_COST:
					WeekPlan.set_activity(mi.id, "excursion")
					excursion_weeks += 1
				else:
					WeekPlan.set_activity(mi.id, "rest")
					rest_weeks += 1
				if str(plan["mode"]) == "idle":
					capped_weeks += 1
			elif str(plan["mode"]) == "rest":
				WeekPlan.set_activity(mi.id, "rest")
				rest_weeks += 1
			else:
				WeekPlan.set_activity(mi.id, str(plan["id"]))
				train_weeks += 1

		var gold_before: int = Career.gold
		bench_weeks += maxi(0, Roster.monsters.size() - Career.current_team_size())
		rent_paid += int(WeekPlan.rent_for(Roster.frozen))
		WeekPlan.advance(Roster.monsters)
		var delta: int = Career.gold - gold_before
		if delta >= 0:
			L["goldIn"] = int(L["goldIn"]) + delta
		else:
			L["goldOut"] = int(L["goldOut"]) - delta
		L["weeks"] = int(L["weeks"]) + 1
		if Career.gold < 100:
			L["brokeWeeks"] = int(L["brokeWeeks"]) + 1
		gold_peak = maxi(gold_peak, Career.gold)

		# ── retirements: COUNTED here, DISPOSED OF by `_manage_roster` at the top of next week ──
		# ⚠️ It used to release every retiree on the spot for the refund, which threw away the one
		# thing a retiree is still good for: it is breeding stock. A champion that raced until it
		# dropped is exactly the founder a dynasty wants (`roster.gd:breeding_stock`), and the
		# freezer is the only place `breeding_ui.gd` will look for a parent.
		for mi in Roster.monsters:
			if mi.retired and not bool(mi.get_meta("arc_counted_retirement", false)):
				mi.set_meta("arc_counted_retirement", true)
				L["retirements"] = int(L["retirements"]) + 1

		# ── the frontier cup ────────────────────────────────────────────────
		# ⚠️ IF THE FRONTIER IS NOT FIELDABLE, FARM THE HIGHEST LEAGUE THAT IS. A cleared league
		# still pays 50%/20% and a cup costs no week, so a player short of a recruit grinds the
		# rung below rather than sitting still. Modelling that is what stops the autopilot from
		# reporting a soft-lock that a real player would simply play around.
		# ⚠️ FIELD YOUR BEST, AND COUNT ONLY WHAT CAN FIGHT. `career.gd:enter_league_tournament`
		# slices `Roster.monsters` from the FRONT — barn order IS the team sheet. With no bench
		# that was a distinction without a difference; with a bench and a foal in the barn,
		# leaving it unsorted fields the newborn and benches the champion. Sorting here is the
		# autopilot doing what the player does when they pick a squad.
		_sort_roster_best_first()
		var fieldable: int = Roster.monsters.filter(func(m): return not m.retired).size()
		var enter_idx: int = -1
		## ⚠️ A FULL SIDE FIRST, ALWAYS — SHORT ENTRY IS AN ESCAPE HATCH, NOT A DEFAULT, AND THE
		## DIFFERENCE IS TWO WHOLE LEAGUES. `Career.SHORT_ENTRY_ALLOWANCE` lets a stable enter a
		## body down (it exists to break the poverty trap where the frontier is locked behind a
		## monster the rung below cannot pay for). Measured with the autopilot taking that option
		## whenever it was legal, it entered 4v5 every month, won 30 of 354 rounds (8%), spent 41%
		## of its purse income on entry fees and stalled a rung LOWER than before the option
		## existed. Taking the highest rung it can field FULLY, and going short only when no rung
		## can be filled, is what a competent player does — and it is the policy this instrument
		## is supposed to model. The lesson generalises: a new option measured with a policy that
		## does not know when to use it measures the policy, not the option.
		var full_idx: int = -1
		for j in range(Career.league_index, -1, -1):
			if Career.team_size_for_league(j) <= fieldable:
				full_idx = j
				break
		if full_idx == Career.league_index:
			enter_idx = full_idx
		else:
			## ⚠️ COUNTED, BECAUSE THE ARC HAS ALREADY HIT THIS AND IT WAS INVISIBLE. A run spent
			## 151 weeks at Platinum entering ZERO cups at that rung and farming Gold instead —
			## the per-league table showed "Platinum 151 wks, 0 cups" and nothing said why. The
			## frontier is not always gated on strength; it can be gated on not owning five
			## bodies, which is an ECONOMY problem wearing a difficulty problem's clothes.
			frontier_blocked_weeks += 1
			## The escape hatch: if there is no rung at all it can field in full, go short at the
			## highest rung the allowance permits rather than sitting out the ladder entirely.
			enter_idx = full_idx
			if full_idx < 0:
				for j in range(Career.league_index, -1, -1):
					if Career.min_team_to_enter(j) <= fieldable:
						enter_idx = j
						break
		# ⚠️ ENTRY COSTS GOLD NOW. A cup the player cannot pay for is a cup they do not enter, so
		# the autopilot must be refused too — otherwise the instrument reports a bankroll the game
		# would never have let it build. The Wood waiver is mirrored in `_entry_fee`, so the
		# frontier can always be re-approached from zero gold at the bottom rung.
		var cup_fee: int = int(round(_entry_fee(enter_idx) * float(opts.get("feeMult", 1.0)))) if enter_idx >= 0 else 0
		if enter_idx >= 0 and Career.gold < cup_fee:
			cups_refused_by_fee += 1
			enter_idx = -1
		if enter_idx >= 0 and Career.week - last_cup_week >= CUP_INTERVAL:
			last_cup_week = Career.week
			decisions += 1
			var before_idx: int = enter_idx
			var rounds: int = _rounds_for(before_idx)
			Career.spend_gold(cup_fee)
			fees_paid += cup_fee
			var out: Dictionary = _fight_cup(before_idx, rounds, Career.week * 31 + before_idx,
				float(opts.get("rivalMult", 1.0)))
			## ⚠️ THE TRIP IS PART OF THE CUP, AND THIS PROBE COULD NOT SEE IT. `CupRun.travel()`
			## charges real weeks on the LIVE path; this autopilot drives
			## `Career.enter_league_tournament` directly, so for one round the arc reported "the
			## clock moved 0 weeks" about a game where it no longer does — precisely the class of
			## artifact §2 of this probe exists to prevent. Charged AFTER the fight because the
			## field seed is a function of the week: travelling first would fight a different
			## draw from the one entered. The road is a rest week, so the plan is stashed.
			var trip: int = int(CupRun.weeks_for_cup(before_idx, rounds))
			if trip > 0:
				var stashed: Dictionary = WeekPlan.plans.duplicate(true)
				WeekPlan.plans = {}
				for _t in range(trip):
					rent_paid += int(WeekPlan.rent_for(Roster.frozen))
					WeekPlan.advance(Roster.monsters)
				WeekPlan.plans = stashed
				travel_weeks += trip
			var wins: int = int(out.get("wins", 0))
			var purse: int = _purse_paid(before_idx, wins, rounds)
			Career.add_gold(purse)
			var LL: Dictionary = per_league[before_idx]
			LL["cups"] = int(LL["cups"]) + 1
			LL["goldOut"] = int(LL["goldOut"]) + cup_fee
			LL["rounds"] = int(LL["rounds"]) + rounds
			LL["roundWins"] = int(LL["roundWins"]) + wins
			LL["goldIn"] = int(LL["goldIn"]) + purse
			gold_peak = maxi(gold_peak, Career.gold)
			if bool(out.get("promoted", false)) or bool(out.get("gameWon", false)):
				LL["fillAtExit"] = _roster_fill(Roster.monsters, Career.stat_cap_for_league(before_idx))
				if max_weeks >= MAX_WEEKS:
					print("    wk %4d  cleared %-12s after %d cups · roster %d · %dg" % [
						Career.week, Career.league_at(before_idx).get("name", "?"),
						int(LL["cups"]), Roster.monsters.size(), Career.gold])
				league_start_week = Career.week
				last_cup_week = -CUP_INTERVAL   # a fresh league may be entered immediately

		if stall_reason == "" and Career.week - league_start_week > STALL_WEEKS:
			stall_reason = "no promotion out of %s in %d weeks" % [Career.current_league_name(), STALL_WEEKS]
		if stall_reason != "":
			break

	if per_league[Career.league_index]["fillAtExit"] == 0.0:
		per_league[Career.league_index]["fillAtExit"] = _roster_fill(Roster.monsters, Career.current_stat_cap())

	return {
		"weeks": Career.week, "finalLeague": Career.league_index, "won": Career.won_game,
		"goldEnd": Career.gold, "goldPeak": gold_peak, "perLeague": per_league,
		"stall": stall_reason, "trainWeeks": train_weeks, "restWeeks": rest_weeks,
		"cappedWeeks": capped_weeks, "excursionWeeks": excursion_weeks,
		"decisions": decisions, "blockedRecruit": blocked_recruit,
		"feesPaid": fees_paid, "cupsRefusedByFee": cups_refused_by_fee,
		"travelWeeks": travel_weeks,
		"cups": _sum_field(per_league, "cups"), "rounds": _sum_field(per_league, "rounds"),
		"roundWins": _sum_field(per_league, "roundWins"),
		"recruits": _sum_field(per_league, "recruits"),
		"retirements": _sum_field(per_league, "retirements"),
		"breeds": _sum_field(per_league, "breeds"),
		"bestPotential": _best_potential(),
		"preserves": preserves, "releases": releases, "rentPaid": rent_paid,
		"frozen": Roster.frozen.size(), "bestGeneration": _best_generation(),
		"benchWeeks": bench_weeks,
		"firstPreserveWeek": first_preserve_week, "firstBreedWeek": first_breed_week,
		"frontierBlockedWeeks": frontier_blocked_weeks,
	}


func _sum_field(rows: Array, key: String) -> int:
	var t := 0
	for r in rows:
		t += int(r[key])
	return t


func _best_potential() -> float:
	var best := 0.0
	for mi in _all_monsters():
		best = maxf(best, float(mi.potential))
	return best


func _best_generation() -> int:
	var best := 1
	for mi in _all_monsters():
		best = maxi(best, int(mi.generation))
	return best


## ⚠️ NOT A MIRROR ANY MORE — THIS DRIVES THE REAL BUILDER, AND THE OLD COPY WAS WRONG ON EVERY
## AXIS THAT MATTERS. `breeding_ui.gd:_make_child` is the single function the preview card and the
## commit both call, and it is reachable from a probe because a Control that is never added to the
## tree never runs `_ready()`. The hand-written copy that used to live here:
##   · drew its parents from the BARN — the game draws them from `Roster.breeding_stock()`, which
##     is the FREEZER and nothing else, so the copy simulated a rule the player does not have;
##   · climbed potential by `POTENTIAL_STEP`, a constant that no longer exists in `breeding_ui.gd`
##     (it is `BREED_STEP_BY_TIER`, 0.10–0.15 by heritage) — so the mirror had been silently
##     running on its 0.06 fallback, understating a dynasty's climb by up to 2.5x per generation;
##   · applied no species-base floor, no emphasis, no heirloom and no generation counter.
## A mirror of a system that is being reworked by someone else is a liability. Call the real one.
func _try_breed():
	if Roster.monsters.size() >= Career.barn_capacity or Career.gold < _breed_cost():
		return null
	var a = null
	var b = null
	for mi in Roster.breeding_stock():
		if int(mi.get_meta("children", 0)) >= _breed_max_children():
			continue
		if a == null or mi.potential > a.potential:
			b = a
			a = mi
		elif b == null or mi.potential > b.potential:
			b = mi
	if a == null or b == null or a == b:
		return null

	var ui = BreedScript.new()
	ui._line_from_b = _stat_total(b) > _stat_total(a)
	ui._emphasis = _breed_emphasis(a, b)
	# The bequest is free upside, so a competent player always takes the biggest one going.
	var best_at := -1.0
	for opt in ui._heirloom_options(a, b):
		if float(opt["at"]) > best_at:
			best_at = float(opt["at"])
			ui._heirloom_id = str(opt["id"])
	if not Career.spend_gold(_breed_cost()):
		ui.free()
		return null
	var child = ui._make_child(a, b, Roster.next_slot_id())
	ui.free()
	if child == null:
		return null
	a.set_meta("children", int(a.get_meta("children", 0)) + 1)
	b.set_meta("children", int(b.get_meta("children", 0)) + 1)
	Roster.monsters.append(child)
	return child


## Which stat to aim the child at. `EMPHASIS_TAX` is zero-sum, so this chooses the child's SHAPE
## and therefore its class — the vision's "knowing WHICH monster to make". Doubling down on what
## the line is already best at is the simplest defensible policy; it is a POLICY, not a law, and
## a better one is exactly the kind of thing a real player would discover.
func _breed_emphasis(a, b) -> String:
	var best: String = Classify.STATS[0]
	var best_v := -1.0
	for s in Classify.STATS:
		var v: float = float(a.stats.get(s, 0.0)) + float(b.stats.get(s, 0.0))
		if v > best_v:
			best_v = v
			best = s
	return best


## Barn order IS the team sheet (`career.gd:enter_league_tournament` slices from the front), so
## the autopilot sorts it: anything that can still fight, strongest first.
func _sort_roster_best_first() -> void:
	Roster.monsters.sort_custom(func(a, b):
		if a.retired != b.retired:
			return b.retired
		return _stat_total(a) > _stat_total(b))
	Roster.selected_index = 0


## A cup, with a knob on how strong the field is. At `mult == 1.0` this IS
## `Career.enter_league_tournament` — called directly, so the arc is fought against the real
## thing. Any other multiplier rebuilds the same field at scaled fill and hands the win count to
## `Career.apply_tournament_outcome`, the documented SHARED TAIL both the headless and the live
## cup paths use. ⚠️ `_check_cup_mirror()` asserts the two agree at 1.0; a perturbation harness
## that has quietly stopped matching the thing it perturbs is worse than no harness.
func _fight_cup(idx: int, rounds: int, seed_: int, mult: float = 1.0) -> Dictionary:
	if is_equal_approx(mult, 1.0):
		return Career.enter_league_tournament(idx, rounds, seed_)
	return _fight_cup_scaled(idx, rounds, seed_, mult)


func _fight_cup_scaled(idx: int, rounds: int, seed_: int, mult: float) -> Dictionary:
	var size: int = Career.team_size_for_league(idx)
	var player_team: Array = Roster.monsters.slice(0, mini(size, Roster.monsters.size()))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var base_seed: int = Career.cup_field_seed(idx)
	var wins := 0
	## ⚠️ THE MIRROR MUST DRAW THE SAME KIND OF TEAM, NOT JUST THE SAME STRENGTH. A cup round now
	## carries an ARCHETYPE (`Career.make_cup_field`), the rival is BUILT to it, and it fights with
	## its own plan and orders. Re-deriving the field here from `field_fill()` alone rebuilt every
	## round as a generic team fighting no plan — and `_check_cup_mirror()` caught it immediately
	## (2 wins vs 1), which is exactly the job it was written for. Take the archetype from the real
	## drawn field rather than recomputing the draw rule, so there is one source of the pairing.
	var drawn: Array = Career.make_cup_field(idx, rounds)
	for r in range(rounds):
		var fill: float = clampf(Career.field_fill(r, rounds, idx) * mult, 0.05, 0.98)
		var gid: String = String(drawn[r].get("archetype", "")) if r < drawn.size() else ""
		var rivals: Array = drawn[r]["team"] if (r < drawn.size() and is_equal_approx(mult, 1.0)) \
			else Career.make_league_rivals(size, idx, fill,
				abs(base_seed + r * 7919) % 2147483647, gid)
		for m in player_team:
			m.reset_for_battle()   # exactly what the real path resets, and nothing more
		for m in rivals:
			m.reset_for_battle()
		var plan_b: Dictionary = TacticsScript.team_plan_for_gameplan(gid, player_team) if gid != "" else {}
		var orders: Dictionary = TacticsScript.orders_for_gameplan(gid, rivals) if gid != "" else {}
		var sim = BattleSimScript.new(player_team, rivals, rng.randi(), {}, plan_b, orders)
		if str(sim.run().get("winner", "")) == "A":
			wins += 1
	return Career.apply_tournament_outcome(idx, wins, rounds)


## ⚠️ THE PERTURBATION HARNESS MUST AGREE WITH THE THING IT PERTURBS. Same career state, same
## seed, same league: the real `enter_league_tournament` and `_fight_cup_scaled(..., 1.0)` must
## return the same win count. If they diverge, every sensitivity reading in section 6 is measuring
## the mirror's own drift instead of the game's.
func _check_cup_mirror() -> void:
	var wins_real := 0
	var wins_mirror := 0
	for pass_ in range(2):
		_reset_career()
		var team: Array = _team_at_fill(Career.team_size_for_league(0),
			Career.stat_cap_for_league(0), 0.55, 77)
		for m in team:
			m.id = Roster.next_slot_id()
			Roster.monsters.append(m)
		Career.week = 12
		var rounds: int = _rounds_for(0)
		if pass_ == 0:
			wins_real = int(Career.enter_league_tournament(0, rounds, 909090).get("wins", -1))
		else:
			wins_mirror = int(_fight_cup_scaled(0, rounds, 909090, 1.0).get("wins", -2))
	if wins_real != wins_mirror:
		_instrument_ok = false
		_notes.append("⚠️ the cup mirror DISAGREES with career.gd (%d wins vs %d) — section 6 is void"
			% [wins_real, wins_mirror])
	else:
		print("  cup mirror agrees with career.gd at mult 1.0 (%d/%d wins)" % [wins_real, _rounds_for(0)])


## Everything the dynasty owns — the barn AND the freezer. A founder on ice still carries the
## line's potential, and reporting only the barn hid it.
func _all_monsters() -> Array:
	var out: Array = []
	out.append_array(Roster.monsters)
	out.append_array(Roster.frozen)
	return out


## Weeks until this monster stops being able to train at all (`week.gd:stage_info`, Retiree).
func _weeks_left(mi) -> int:
	return int(round(mi.lifespan_years * WeekLib.WEEKS_PER_YEAR)) - mi.age_weeks


## THE ROSTER BRAIN — bench, freezer and dynasty, run once a week before the week is planned.
## ⚠️ ORDER MATTERS AND IS THE PLAYER'S OWN: cover first (never preserve your only body), then
## preserve the ageing, then breed off what is on ice. Returns a tally.
func _manage_roster(opts: Dictionary) -> Dictionary:
	var out := {"preserved": 0, "released": 0, "bred": 0, "breedGold": 0}
	var team: int = Career.current_team_size()

	# ── retirees first: a retired body occupies a barn slot and can do nothing with it ──
	for mi in Roster.monsters.duplicate():
		if not mi.retired:
			continue
		## ⚠️ GATED ON THE DYNASTY POLICY, and it was not at first — which quietly made the
		## "no bench, no breeding" control preserve its retirees anyway, pay the same freezer rent
		## as the dynasty run, and come out byte-identical. The harness correctly reported a dead
		## input; the deadness was in this branch, not in the game. A stable that is not running a
		## dynasty sells the retiree.
		if bool(opts.get("preserve", true)) and Roster.frozen.size() < FREEZER_TARGET \
				and int(mi.get_meta("children", 0)) < _breed_max_children():
			if Roster.preserve(mi):
				out["preserved"] += 1
				continue
		if Roster.release(mi):
			Career.add_gold(int(round(_offer_price(mi) * _refund_frac())))
			out["released"] += 1

	# ── preserve an ageing champion WHILE IT IS STILL GOOD, if there is cover to field ──
	# This is the decision `breeding_ui.gd` says the whole system exists to ask. It is only
	# available to a stable that kept a bench, which is why BENCH_SIZE and FREEZER_TARGET are
	# one policy and not two.
	## ⚠️ NEVER OUT OF THE FIELDED TEAM. The first cut of this preserved the STRONGEST ageing
	## monster the moment it entered its last stretch, and that is the one body the cup needs:
	## the arc stalled a league lower than an autopilot with no dynasty at all. A player retires a
	## veteran when the replacement is ready, not before. `_sort_roster_best_first` has already
	## put the team sheet in order, so "not in the top `team`" is exactly "has been replaced".
	if bool(opts.get("preserve", true)) and Roster.frozen.size() < FREEZER_TARGET:
		_sort_roster_best_first()
		var best = null
		for i in range(Roster.monsters.size()):
			if i < team:
				continue   # still on the team sheet — it fights, it does not sit in a freezer
			var mi = Roster.monsters[i]
			if mi.retired or _weeks_left(mi) > PRESERVE_MARGIN_WEEKS:
				continue
			if best == null or _stat_total(mi) > _stat_total(best):
				best = mi
		if best != null and Roster.preserve(best):
			out["preserved"] += 1

	# ── breed, when the freezer holds a pair and gold is genuinely spare ──
	if bool(opts.get("breed", true)) and Roster.breeding_stock().size() >= 2 and Career.gold >= BREED_GOLD_FLOOR:
		if _try_breed() != null:
			out["bred"] += 1
			out["breedGold"] += _breed_cost()
	return out


func _report_arc(a: Dictionary) -> void:
	print("\n─── 1. THE ARC ───")
	var rows: Array = a["perLeague"]
	print("  league        wks  cups  rounds  won   gold in  gold out    fill@exit")
	for i in range(rows.size()):
		var r: Dictionary = rows[i]
		if int(r["weeks"]) == 0 and int(r["cups"]) == 0:
			continue
		print("  %-12s %4d  %4d  %6d  %3d  %8d  %8d      %4.0f%%" % [
			Career.league_at(i).get("name", "?"), int(r["weeks"]), int(r["cups"]),
			int(r["rounds"]), int(r["roundWins"]), int(r["goldIn"]), int(r["goldOut"]),
			float(r["fillAtExit"]) * 100.0])
	print("")
	print("  finished:        %s at %s after %d weeks (%.1f in-game years)" % [
		"WON THE GAME" if bool(a["won"]) else "stopped",
		Career.league_at(int(a["finalLeague"])).get("name", "?"),
		int(a["weeks"]), int(a["weeks"]) / 48.0])
	if str(a["stall"]) != "":
		print("  STALLED:         %s" % str(a["stall"]))
	print("  cups entered:    %d  (%d rounds, %d won = %.0f%%)" % [
		int(a["cups"]), int(a["rounds"]), int(a["roundWins"]),
		100.0 * float(a["roundWins"]) / maxf(1.0, float(a["rounds"]))])
	print("  gold:            ended %d, peaked %d" % [int(a["goldEnd"]), int(a["goldPeak"])])
	print("  weeks broke:     %d of %d  (gold under 100)" % [
		_sum_field(rows, "brokeWeeks"), int(a["weeks"])])
	var mweeks: int = int(a["trainWeeks"]) + int(a["restWeeks"]) + int(a["excursionWeeks"])
	print("  monster weeks:   %d trained · %d rested · %d excursion  (of %d)" % [
		int(a["trainWeeks"]), int(a["restWeeks"]), int(a["excursionWeeks"]), mweeks])
	print("  weeks with NOTHING to train (every stat at the league ceiling): %d  (%.0f%% of all monster weeks)" % [
		int(a["cappedWeeks"]), 100.0 * float(a["cappedWeeks"]) / maxf(1.0, float(mweeks))])
	print("  roster churn:    %d recruited · %d retired · %d preserved · %d released · %d bred" % [
		int(a["recruits"]), int(a["retirements"]), int(a.get("preserves", 0)),
		int(a.get("releases", 0)), int(a["breeds"])])
	print("  the dynasty:     best potential x%.2f · best generation %d · %d on ice at the end · %dg of freezer rent" % [
		float(a["bestPotential"]), int(a.get("bestGeneration", 1)),
		int(a.get("frozen", 0)), int(a.get("rentPaid", 0))])
	print("  bench:           %d monster-weeks spent outside the fielded team" % int(a.get("benchWeeks", 0)))
	print("  recruit blocked by gold: %d times" % int(a["blockedRecruit"]))
	print("  weeks ON THE ROAD: %d of %d (%.0f%%) — cup travel, ticked in full but never trained" % [
		int(a.get("travelWeeks", 0)), int(a["weeks"]),
		100.0 * float(a.get("travelWeeks", 0)) / maxf(1.0, float(a["weeks"]))])
	print("  frontier cup UNENTERABLE for want of bodies: %d weeks of %d (%.0f%%) — the stable could" % [
		int(a.get("frontierBlockedWeeks", 0)), int(a["weeks"]),
		100.0 * float(a.get("frontierBlockedWeeks", 0)) / maxf(1.0, float(a["weeks"]))])
	print("                   not field the league's team size and farmed the rung below instead.")
	print("  ⚠️ WEEKS are booked to the FRONTIER league; CUPS are booked to the league ENTERED.")
	print("     A row reading 'many weeks, no cups' is a stable stuck below its own frontier.")
	print("  entry fees paid: %dg over %d cups (%.0f%% of all purse income) · %d cups refused for want of the fee" % [
		int(a["feesPaid"]), int(a["cups"]),
		100.0 * float(a["feesPaid"]) / maxf(1.0, float(_sum_field(rows, "goldIn"))),
		int(a["cupsRefusedByFee"])])
	print("  DECISION POINTS: %d" % int(a["decisions"]))
	print("                   at 4s per decision that is %.0f minutes of menu time," % (
		int(a["decisions"]) * 4.0 / 60.0))
	print("                   plus %d fights to watch (at 25s each, %.0f minutes)." % [
		int(a["rounds"]), int(a["rounds"]) * 25.0 / 60.0])


# =============================================================================
# 6. SENSITIVITY — DOES THIS INSTRUMENT MOVE WHEN ITS INPUTS MOVE?
# =============================================================================
## ⚠️ THIS SECTION EXISTS BECAUSE THIS PROBE ONCE REPORTED BYTE-IDENTICAL RESULTS AFTER REAL
## SYSTEM CHANGES AND THAT WAS READ AS STABILITY. It was not: the instrument had pinned the rival
## count at 3 when leagues field 3/4/5, paid purses by win-fraction rather than by placement, and
## charged no entry fee — so it was reporting confidently about a game nobody was playing. The
## defence against repeating that is not more care, it is a MEASUREMENT: perturb every input that
## should matter and require the arc to answer differently. An input that changes nothing is
## either dead in the game or dead in this file, and both are findings.
##
## A perturbation that leaves the signature untouched FAILS the probe. That is deliberate — a
## silent instrument is the expensive failure, a noisy one is a five-minute investigation.
const SENS_WEEKS := 200
const SENS_WEEKS_LONG := 400   ## long enough for a first retirement, i.e. for a freezer to exist

## Weeks at which the dynasty first did anything on the FULL arc; 0 = never. Reported by
## section 6 because "the knob is dead at 200 weeks" is only interpretable next to them.
var _first_preserve_week := 0
var _first_breed_week := 0

func _run_sensitivity() -> void:
	print("\n─── 6. SENSITIVITY (does the instrument move when its input moves?) ───")
	print("  %d-week arcs. Each row perturbs ONE input; the signature must differ from control." % SENS_WEEKS)
	var controls := {}
	controls[SENS_WEEKS] = _run_arc(SENS_WEEKS)
	print("  %-26s %-40s" % ["perturbation", "league / gold / cups / round wins / bred"])
	print("  %-26s %-40s  (control, %dw)" % ["—", _sig(controls[SENS_WEEKS]), SENS_WEEKS])
	## ⚠️ THE DYNASTY CASE NEEDS A LONGER ARC AND THAT IS ITSELF THE FINDING. Measured at 200
	## weeks, breeding-on and breeding-off are BYTE-IDENTICAL — not because the harness is blind
	## but because nothing has retired yet, so the freezer is empty and there is no stock to breed
	## from. The whole generational half of the game is inert for the first four in-game years.
	## It is tested at `SENS_WEEKS_LONG` so the knob can be shown to work at all; the 200-week
	## null is reported next to it rather than hidden by the longer run.
	var cases: Array = [
		{"name": "rivals x0.85 (weaker)", "opts": {"rivalMult": 0.85}},
		{"name": "rivals x1.15 (stronger)", "opts": {"rivalMult": 1.15}},
		{"name": "entry fee waived", "opts": {"feeMult": 0.0}},
		{"name": "entry fee x6", "opts": {"feeMult": 6.0}},
		{"name": "optimiser training", "opts": {"policy": "optimiser"}},
		{"name": "no bench/breed (200w)", "opts": {"breed": false}, "expectNull": true},
		{"name": "no bench/breed (%dw)" % SENS_WEEKS_LONG, "opts": {"breed": false},
			"weeks": SENS_WEEKS_LONG, "needsDynasty": true},
	]
	var dead: Array[String] = []
	for c in cases:
		var w: int = int(c.get("weeks", SENS_WEEKS))
		if not controls.has(w):
			controls[w] = _run_arc(w)
			print("  %-26s %-40s  (control, %dw)" % ["—", _sig(controls[w]), w])
		var r: Dictionary = _run_arc(w, c["opts"])
		var sig: String = _sig(r)
		var moved: bool = sig != _sig(controls[w])
		## ⚠️ DEAD IS NOT THE SAME AS UNEXERCISED, AND CONFLATING THEM WOULD MAKE THIS HARNESS CRY
		## WOLF. "Dead" means the input fired and changed nothing — an instrument fault, and the
		## thing this section exists to catch. "Unexercised" means the control run never reached
		## the state the input acts on (the dynasty needs a retirement, which needs a career that
		## survives ~330 weeks); that is a finding about the GAME and must not be reported as a
		## broken probe. The difference is measured off the control's own counters, not assumed.
		var ctl: Dictionary = controls[w]
		var unexercised: bool = bool(c.get("needsDynasty", false)) \
			and int(ctl.get("preserves", 0)) + int(ctl.get("breeds", 0)) == 0
		var verdict := "moved"
		if not moved:
			if bool(c.get("expectNull", false)):
				verdict = "no change — EXPECTED, see note"
			elif unexercised:
				verdict = "NOT EXERCISED — the control never bred"
			else:
				verdict = "*** DEAD INPUT ***"
		print("  %-26s %-40s  %s" % [str(c["name"]), sig, verdict])
		if not moved and unexercised:
			_notes.append("the dynasty knob could not be exercised at %dw — the control arc never "
				% w + "reached a retirement, so nothing was ever preserved. Not an instrument "
				+ "fault; it means the ladder now stalls before the generational half exists.")
		if not moved and not bool(c.get("expectNull", false)) and not unexercised:
			dead.append(str(c["name"]))
	print("  ⚠️ the dynasty first acts at week %d (first preserve) / %d (first birth) of the full arc —" % [
		_first_preserve_week, _first_breed_week])
	print("     before that, breeding-on and breeding-off are the same game.")
	if dead.is_empty():
		print("  -> every input moves the arc. The instrument is live.")
	else:
		_instrument_ok = false
		_notes.append("⚠️ DEAD INPUT(S): %s — the arc does not respond, so any conclusion drawn "
			% ", ".join(dead) + "about them is unsupported. Fix before trusting section 1.")


func _sig(a: Dictionary) -> String:
	return "L%d / %dg / %d cups / %d wins / %d bred" % [
		int(a["finalLeague"]), int(a["goldEnd"]), int(a["cups"]), int(a["roundWins"]),
		int(a["breeds"])]


# =============================================================================
# 2. THE GRIND — is gold ever scarce?
# =============================================================================
# ⚠️ ENTERING A CUP COSTS NOTHING: no entry fee, no week, no injury, no stamina. Nothing in
# `tournament_ui.gd` / `cup_run.gd` / `career.gd` advances `Career.week`. So the question "how
# much gold per week" has a degenerate answer, and this measures how degenerate.

func _run_grind() -> void:
	print("\n─── 2. THE GRIND (is gold ever scarce?) ───")
	_reset_career()
	# A stable that has actually trained: one monster filled to the Wood ceiling.
	var team: Array = _team_at_fill(1, Career.stat_cap_for_league(0), 1.0, 1)
	for m in team:
		m.id = Roster.next_slot_id()
		Roster.monsters.append(m)

	var week_before: int = Career.week
	var gold_before: int = Career.gold
	var gold_gained := 0
	var attempts := 10
	var sweeps := 0
	var fees := 0
	var rounds0: int = _rounds_for(0)
	for i in range(attempts):
		fees += _entry_fee(0)
		Career.spend_gold(_entry_fee(0))
		var out: Dictionary = Career.enter_league_tournament(0, rounds0, 4242 + i)
		## ⚠️ AND THE TRIP. `Career.enter_league_tournament` is the HEADLESS path and does not
		## charge it; `CupRun.travel()` does, on the live path, off the same public
		## `weeks_for_cup()`. Mirroring it here is what makes this section measure the game the
		## player plays — without it the probe would keep reporting "the clock moved 0 weeks"
		## about a build where a cup costs one to two weeks of everything.
		Career.advance_week(CupRun.weeks_for_cup(0, rounds0))
		var got: int = _purse_paid(0, int(out.get("wins", 0)), rounds0)
		gold_gained += got
		Career.add_gold(got)
		if bool(out.get("swept", false)):
			sweeps += 1
	print("  a Wood-capped monster enters the Wood cup %d times back to back:" % attempts)
	print("    +%dg purse, -%dg fees = %+dg net; %d sweeps of %d; the clock moved %d weeks (gold %d -> %d)." % [
		gold_gained, fees, gold_gained - fees, sweeps, attempts,
		Career.week - week_before, gold_before, Career.gold])
	## ⚠️ FINDING E2 IS NOW CLOSED, AND THIS IS THE LINE THAT PROVES IT. A cup costs BOTH a price
	## and a clock: `CupRun.weeks_for_cup()` charges 1 week (2 for a five-team draw), spent
	## through the real weekly tick, so gold per week of GAME TIME is finite for the first time
	## and the weekly tick can no longer be skipped by the one activity the game is about.
	var wk_moved: int = Career.week - week_before
	print("  -> a cup costs %dg at Wood (%dg at Apex) AND %d week%s of game time; %d cups moved the" % [
		_base_fee(), _base_fee() + _fee_step() * (Career.leagues.size() - 1),
		CupRun.weeks_for_cup(0, rounds0), "" if CupRun.weeks_for_cup(0, rounds0) == 1 else "s",
		attempts])
	print("     clock %d weeks, so the faucet is now %.0fg per week of game time, not per click." % [
		wk_moved, float(gold_gained - fees) / maxf(1.0, float(wk_moved))])

	# what does a week actually cost to run?
	var food_bill := 0
	for f in WeekLib.FOODS:
		if str(f.get("tier", "")) == "normal":
			food_bill += WeekPlan.price_of(str(f["id"]))
	var avg_food: float = float(food_bill) / 4.0
	print("  a monster-week of upkeep is one ration: ~%.0fg. A 5-stable week: ~%.0fg." % [
		avg_food, avg_food * 5.0])
	print("  one Wood sweep (%dg) pays for %.0f stable-weeks; one Apex sweep (%dg) pays for %.0f." % [
		_purse_for_league(0), _purse_for_league(0) / maxf(1.0, avg_food * 5.0),
		_purse_for_league(10), _purse_for_league(10) / maxf(1.0, avg_food * 5.0)])
	print("  total permanent sinks in the whole game: barn %dg + licences 2800g + breeding %dg/child." % [
		_barn_total(), _breed_cost()])


func _purse_for_league(idx: int) -> int:
	return _base_purse() + _purse_step() * idx


func _barn_total() -> int:
	var t := 0
	for p in _barn_prices():
		t += int(p)
	return t


# =============================================================================
# 3. THE WALL — does the climb get harder?
# =============================================================================
# A team trained EXACTLY to the league cap, fought against that league's own rivals. If the win
# rate is flat and high, the ladder is a time gate, not a difficulty curve.

## ⚠️ THE MID-FIELD IS NOT THE GATE ANY MORE, AND MEASURING ONLY IT IS HOW THIS INSTRUMENT
## REPORTED "100% AT ALL ELEVEN LEAGUES" WHILE THE LADDER REWORK WAS LANDING. `make_league_rivals`
## with no fill returns a MID-FIELD team; promotion needs a SWEEP, and the last round of every cup
## is now the league's champion at 0.80..0.97 of its own ceiling. So the number that decides the
## climb is P(sweep the drawn field), and the number that decides whether the climb is monotonic
## is P(beat the champion). Both are measured below, against the real field the player fights.
## ⚠️ AND "CAP-TRAINED" IS A TEAM THAT DOES NOT EXIST. `_team_at_fill(..., 1.0)` puts ALL SIX
## stats on the ceiling; instrument 1 measures a real winning roster leaving each league at
## 52-68% fill, and instrument 4 says even one perfectly-drilled monster RETIRES before filling
## the Platinum cap. Measuring only the impossible team is why this section read a flat 100%
## while the ladder rework was landing — a reference point above the game's own ceiling cannot
## register a difficulty curve. So the gate is measured twice: at the theoretical maximum, and at
## the fill the arc actually reaches. The second row is the one that describes the game.
const GATE_REAL_FILL := 0.65   ## the arc's measured roster fill on leaving a league

func _run_champion_gate() -> void:
	_champion_gate_at(1.0, "cap-trained — theoretical, never reached in play")
	_champion_gate_at(GATE_REAL_FILL, "at the fill a real winning roster actually has")


func _champion_gate_at(fill: float, why: String) -> void:
	print("\n─── 3b. THE GATE vs the FIELD it actually draws — team at %.0f%% of cap ───" % (fill * 100.0))
	print("      (%s)" % why)
	print("  league        opener  champion   sweep   field   champion")
	_reset_career()
	var attempts := 8
	for idx in range(Career.leagues.size()):
		Career.league_index = idx
		var cap: float = Career.stat_cap_for_league(idx)
		var size: int = Career.team_size_for_league(idx)
		var rounds: int = _rounds_for(idx)
		var opener_wins := 0
		var champ_wins := 0
		var sweeps := 0
		for f in range(attempts):
			# ⚠️ The field is seeded off the game WEEK, so it must be moved between attempts or all
			# eight draws are the same three teams and the measurement is one sample repeated.
			Career.week = 1 + f * 4
			var field: Array = Career.make_cup_field(idx, rounds)
			var swept := true
			for r in range(field.size()):
				var rng := RandomNumberGenerator.new()
				rng.seed = 31000 + idx * 131 + f * 7 + r
				var capped: Array = _team_at_fill(size, cap, fill, idx * 31 + f)
				var rivals: Array = field[r]["team"]
				for m in capped:
					m.reset_for_battle()
				for m in rivals:
					m.reset_for_battle()
				var sim = BattleSimScript.new(capped, rivals, rng.randi())
				var won: bool = str(sim.run().get("winner", "")) == "A"
				if not won:
					swept = false
				if r == 0:
					opener_wins += 1 if won else 0
				if bool(field[r].get("champion", false)):
					champ_wins += 1 if won else 0
			if swept:
				sweeps += 1
		Career.week = 1
		print("  %-12s  %4d%%    %4d%%    %4d%%   %d rounds  %s" % [
			Career.league_at(idx).get("name", "?"),
			int(round(100.0 * opener_wins / float(attempts))),
			int(round(100.0 * champ_wins / float(attempts))),
			int(round(100.0 * sweeps / float(attempts))),
			rounds, Career.champion_for(idx).get("name", "?")])
	print("  (promotion needs the SWEEP column. A flat 100%% there is a time gate, not a climb.)")


func _run_wall() -> void:
	print("\n─── 3. THE WALL (cap-trained team vs each league's MID-FIELD rivals) ───")
	print("  league        capped team   fresh recruits   rival stat fill")
	_reset_career()
	for idx in range(Career.leagues.size()):
		Career.league_index = idx
		var cap: float = Career.stat_cap_for_league(idx)
		var size: int = Career.team_size_for_league(idx)
		var capped_wins := 0
		var fresh_wins := 0
		var rival_fill := 0.0
		var fights := 8
		for f in range(fights):
			var rng := RandomNumberGenerator.new()
			rng.seed = 7000 + idx * 97 + f
			var rivals: Array = Career.make_league_rivals(size, idx)
			rival_fill += _roster_fill(rivals, cap)
			var capped: Array = _team_at_fill(size, cap, 1.0, idx * 31 + f)
			for m in capped:
				m.reset_for_battle()
			for m in rivals:
				m.reset_for_battle()
			var sim = BattleSimScript.new(capped, rivals, rng.randi())
			if str(sim.run().get("winner", "")) == "A":
				capped_wins += 1
			var rivals2: Array = Career.make_league_rivals(size, idx)
			var fresh: Array = _team_at_fill(size, cap, 0.0, idx * 31 + f)
			for m in fresh:
				m.reset_for_battle()
			for m in rivals2:
				m.reset_for_battle()
			var sim2 = BattleSimScript.new(fresh, rivals2, rng.randi())
			if str(sim2.run().get("winner", "")) == "A":
				fresh_wins += 1
		print("  %-12s   %3d%% (%d/%d)   %3d%% (%d/%d)        %4.0f%%" % [
			Career.league_at(idx).get("name", "?"),
			int(round(100.0 * capped_wins / float(fights))), capped_wins, fights,
			int(round(100.0 * fresh_wins / float(fights))), fresh_wins, fights,
			100.0 * rival_fill / float(fights)])
	print("  (a SWEEP needs 3 of 3 — a per-round win rate of w gives a sweep chance of w^3)")


## A team whose stats sit at `fill` of the league cap — the training outcome, not the market roll.
func _team_at_fill(size: int, cap: float, fill: float, salt: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91000 + salt
	var team: Array = []
	for i in range(size):
		var species: String = Art.ROSTER[(salt + i * 5) % Art.ROSTER.size()]
		var mi = GameData.make_monster(species, 0.0, rng)
		if mi == null:
			continue
		for stat in Classify.STATS:
			mi.stats[stat] = maxf(float(mi.stats[stat]), cap * fill)
		mi.recompute_class()
		mi.recompute_pools()
		mi.assign_moveset(rng)
		mi.hp = mi.max_hp
		mi.mp = mi.max_mp
		team.append(mi)
	return team


# =============================================================================
# 4. THE GYM — how many weeks does a league's ceiling take to fill?
# =============================================================================

func _run_gym() -> void:
	print("\n─── 4. THE GYM (weeks of training to fill a league's cap) ───")
	print("  ONE monster, perfectly drilled, fed every week, from a fresh recruit's base stats.")
	print("  league       cap   weeks to fill 95%   train/rest   pts/wk   verdict")
	for idx in range(Career.leagues.size()):
		var cap: float = Career.stat_cap_for_league(idx)
		var rng := RandomNumberGenerator.new()
		rng.seed = 555
		var mi = GameData.make_monster(Art.ROSTER[0], 0.0, rng)
		mi.id = "gym-%d" % idx
		mi.happiness = 8
		var start_total: float = _stat_total(mi)
		var target: float = cap * float(Classify.STATS.size()) * 0.95
		var weeks := 0
		var trained := 0
		var rested := 0
		var limit := 1200
		var died_of_age := false
		while weeks < limit and _stat_total(mi) < target:
			if mi.retired:
				died_of_age = true
				break
			var plan := _drill_plan_greedy(mi, cap)
			mi.fed_this_week = true   # assume fed; feeding is a gold question, not a time one
			if str(plan["mode"]) == "train":
				WeekLib.apply_activity(mi, {"kind": "train", "drillId": str(plan["id"])}, 0, cap, "Wood")
				trained += 1
			else:
				WeekLib.apply_activity(mi, {"kind": "rest"}, 0, cap, "Wood")
				rested += 1
				if str(plan["mode"]) == "idle":
					break   # the ceiling is genuinely reached; 95% was unreachable by rounding
			weeks += 1
		var gained: float = _stat_total(mi) - start_total
		var reached: bool = _stat_total(mi) >= target
		var verdict := "within one lifespan"
		if died_of_age:
			verdict = "RETIRED FIRST"
		elif not reached:
			verdict = "never reached"
		print("  %-11s %4d   %14s   %4d/%-4d   %5.1f    %s" % [
			Career.league_at(idx).get("name", "?"), int(cap),
			str(weeks) if reached else ("stopped at %d" % weeks),
			trained, rested, gained / maxf(1.0, float(weeks)), verdict])
	print("  (a monster starts as a Teen at 48w old and RETIRES at 8 years = 336 more weeks)")


# =============================================================================
# 5. THE CHOICE — is a training week a DECISION, or an obvious click?
# =============================================================================
# ⚠️ THIS IS THE VISION'S OWN TEST, QUOTED: "Training and breeding are STRATEGY, NOT MAINTENANCE.
# If a training week is an obvious click, it has failed." A decision only exists if the choices
# differ in outcome. This runs the SAME monster under four policies over the same 200 weeks and
# reports the spread — and then prices the one input the player is asked to manage, happiness.

func _run_choice() -> void:
	print("\n─── 5. THE CHOICE (does the weekly decision change the outcome?) ───")
	var cap: float = Career.stat_cap_for_league(7)   # Platinum, mid-ladder
	var weeks := 200
	print("  200 weeks, one monster, Platinum ceiling %d, happiness 8, fed every week:" % int(cap))
	for policy in ["optimiser", "lowest-stat extreme", "random drill", "basic drills only"]:
		var res := _policy_run(policy, cap, weeks, 8)
		print("    %-20s  %6.0f points  (%.2f/wk)  %d distinct drills used" % [
			policy, float(res["gained"]), float(res["gained"]) / float(weeks), int(res["distinct"])])
	print("  the same optimiser at different happiness (the whole point of feeding):")
	for h in [0, 5, 10]:
		var res := _policy_run("optimiser", cap, weeks, h)
		print("    happiness %-2d           %6.0f points  (%.2f/wk)" % [
			h, float(res["gained"]), float(res["gained"]) / float(weeks)])
	print("  ties: how often the best drill beats the runner-up by less than 5%")
	print("    %d%% of training weeks — a margin that thin is a coin flip, not a read." % _tie_rate(cap))


func _policy_run(policy: String, cap: float, weeks: int, happiness: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var mi = GameData.make_monster(Art.ROSTER[0], 0.0, rng)
	mi.id = "policy-%s-%d" % [policy, happiness]
	var start: float = _stat_total(mi)
	var used := {}
	for w in range(weeks):
		mi.happiness = happiness      # held fixed: this measures the policy, not the feeding drift
		mi.fed_this_week = true
		var drill := ""
		match policy:
			"optimiser":
				var p := _drill_plan(mi, cap)
				drill = str(p["id"]) if str(p["mode"]) == "train" else ""
			"lowest-stat extreme":
				var low := Classify.STATS[0]
				for s in Classify.STATS:
					if float(mi.stats[s]) < float(mi.stats[low]):
						low = s
				var want := "x" + low.to_lower()
				if mi.stamina >= WeekLib.EXTREME_DRILL_STAMINA:
					drill = want
			"random drill":
				var pool: Array = []
				for d in WeekLib.DRILLS:
					if WeekLib.drill_stamina(str(d["kind"])) <= mi.stamina:
						pool.append(str(d["id"]))
				if not pool.is_empty():
					drill = str(pool[rng.randi_range(0, pool.size() - 1)])
			_:
				var best := ""
				var best_room := -1.0
				for d in WeekLib.DRILLS:
					if str(d["kind"]) != "basic" or WeekLib.drill_stamina("basic") > mi.stamina:
						continue
					for stat in d["gains"]:
						var room: float = cap - float(mi.stats.get(stat, 0.0))
						if room > best_room:
							best_room = room
							best = str(d["id"])
				drill = best
		if drill == "":
			WeekLib.apply_activity(mi, {"kind": "rest"}, 0, cap, "Wood")
		else:
			used[drill] = true
			WeekLib.apply_activity(mi, {"kind": "train", "drillId": drill}, 0, cap, "Wood")
	return {"gained": _stat_total(mi) - start, "distinct": used.size()}


## What fraction of training weeks have a near-tie at the top of the drill ranking?
func _tie_rate(cap: float) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var mi = GameData.make_monster(Art.ROSTER[0], 0.0, rng)
	mi.id = "tie"
	mi.happiness = 8
	var ties := 0
	var samples := 0
	for w in range(200):
		mi.fed_this_week = true
		var scores: Array = []
		for d in WeekLib.DRILLS:
			var stam: float = WeekLib.drill_stamina(str(d["kind"]))
			if stam > mi.stamina:
				continue
			var score := 0.0
			for stat in d["gains"]:
				var base: float = float(d["gains"][stat])
				if base > 0.0:
					# focus cost included, for the same reason `_drill_plan` includes it
					score += minf((base + roundi(base / 3.0) * 0.5)
							* WeekLib.stat_training_bonus(mi, stat) * WeekLib.focus_cost(mi, stat),
						maxf(0.0, cap - float(mi.stats.get(stat, 0.0))))
				else:
					score += base * WeekLib.stat_malus_multiplier(mi, stat)
			scores.append(score / (1.0 + stam / MEAN_REST_RECOVERY))
		scores.sort()
		scores.reverse()
		if scores.size() >= 2 and float(scores[0]) > 0.0:
			samples += 1
			if float(scores[1]) >= float(scores[0]) * 0.95:
				ties += 1
		var p := _drill_plan(mi, cap)
		if str(p["mode"]) == "train":
			WeekLib.apply_activity(mi, {"kind": "train", "drillId": str(p["id"])}, 0, cap, "Wood")
		else:
			WeekLib.apply_activity(mi, {"kind": "rest"}, 0, cap, "Wood")
	return int(round(100.0 * float(ties) / maxf(1.0, float(samples))))
