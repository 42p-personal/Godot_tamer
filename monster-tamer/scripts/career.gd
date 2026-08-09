## THE LADDER — league progression, run state, and the "win the game" terminal condition.
##
## Autoload singleton. CLAUDE.md is explicit about the ship target: "winning the game = completing
## Tamers Apex, the last league." This script is the thing that KNOWS where the player is on that
## ladder (`league_index`), what a league demands (stat cap, team size — both read straight off
## `data.json`'s `leagues`/`teamSizeByLeague`, never hardcoded), and detects the terminal state.
##
## ⚠️ DOES NOT OWN THE STABLE. `Roster` (autoload) already owns `monsters`/`selected_index` and is
## NOT this script's file to rewrite — Career FIELDS TEAMS FROM Roster (a slice sized to the
## league's team size) rather than duplicating the roster array. One source of truth for "which
## monsters exist," a second for "where the run stands."
##
## ⚠️ THIS IS THE SKELETON'S LADDER, NOT A PORT OF `town.ts`'s TOURNAMENT SYSTEM. town.ts tracks a
## per-monster `licenseIndex`, reward-fraction placement (100/65/40/0%), calendar-seeded cups with
## marquee events, and rival `TeamGameplan`s. None of that is here. What IS here, mirroring the
## intent rather than the mechanism: a monster may compete in its league or below, never above
## (`can_enter_league`); winning promotes; rivals scale to the LEAGUE, not to the player's stats
## (`make_league_rivals`); and reaching + clearing Tamers Apex is a real, detectable ending
## (`won_game`).
extends Node

const BattleSimScript = preload("res://scripts/battle_sim.gd")
const TacticsScript = preload("res://scripts/tactics.gd")
const DATA_PATH := "res://data/data.json"
const STARTING_GOLD := 500

## The barn's starting capacity — `town.ts:START_BARN`. ⚠️ THE WHOLE POINT (docs/CORE_LOOP_PORT.md
## §1): acquiring your first monster is meant to be a real, gold-costing, room-limited decision.
## A stable that starts full or unbounded deletes that opening entirely.
const STARTING_BARN_CAPACITY := 2

signal league_swept(league_name: String)          ## fired every sweep, including replays of an
                                                   ## already-cleared league
signal promoted(from_league: String, to_league: String)
signal game_won()

var leagues: Array = []                  # Array[Dictionary] {name, cap} — Wood..Tamers Apex, ladder order
var team_size_by_league: Dictionary = {} # league name (String) -> team size (int)

var league_index: int = 0                # the league the player has REACHED — the ladder frontier
var gold: int = STARTING_GOLD
var week: int = 0                        # town.ts:newGame() starts at week 0, not week 1
var barn_capacity: int = STARTING_BARN_CAPACITY

var leagues_won: Array = []              # Array[bool], parallel to `leagues` — cleared at least once
var won_game: bool = false               # terminal: Tamers Apex swept

## Licences bought at the Ranch Shop — licence name (String) -> true. See `holds_licence()`.
var licences: Dictionary = {}


func _ready() -> void:
	_load_ladder()
	_reset_leagues_won()


func _load_ladder() -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("Career: cannot open %s — run ./run_contract.sh first to populate data/" % DATA_PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("Career: data.json did not parse to a Dictionary")
		return
	leagues = parsed.get("leagues", [])
	team_size_by_league = parsed.get("teamSizeByLeague", {})


func _reset_leagues_won() -> void:
	leagues_won.resize(leagues.size())
	leagues_won.fill(false)


## Wipe run state back to the very start of the ladder (Wood, week 0, starting gold, a
## two-monster barn). Does NOT touch `Roster` — town.ts's `newGame()` starts with an EMPTY stable
## (`stable: []`), so a true new game must ALSO call `Roster.reset_to_empty()`
## (title_ui.gd:_on_new_career() does both together). A save load is the other path back into
## Roster and legitimately restores whatever stable was saved, not an empty one.
func reset_new_game() -> void:
	league_index = 0
	gold = STARTING_GOLD
	week = 0
	barn_capacity = STARTING_BARN_CAPACITY
	won_game = false
	licences.clear()
	_reset_leagues_won()


## ⚠️ THIS IS A REAL FIELD BECAUSE `set_meta()` SILENTLY REFUSED THE OLD ONE. `shop_ui.gd` stored
## a bought licence as `Career.set_meta("Special License", true)` — and Godot rejects a metadata
## identifier containing a space ("Invalid metadata identifier"), so the write failed, `get_meta`
## kept returning false, and the shop took 800 gold, left the button reading "Buy — 800g", and let
## the player buy the same licence again and again. The error only ever appeared in the console.
##
## A licence is career state, not an annotation: it belongs in a field the save format can see.
func holds_licence(licence_name: String) -> bool:
	return bool(licences.get(licence_name, false))


func grant_licence(licence_name: String) -> void:
	licences[licence_name] = true


## True once the stable is as full as the barn allows — the single source of truth for "can I buy
## another monster", so the Market (and anything else that adds to the stable later) all enforce
## the SAME capacity instead of each hand-rolling its own placeholder ceiling.
func barn_is_full(current_stable_size: int) -> bool:
	return current_stable_size >= barn_capacity


# ── league lookups ───────────────────────────────────────────────────────────

func league_at(idx: int) -> Dictionary:
	if leagues.is_empty():
		return {}
	return leagues[clampi(idx, 0, leagues.size() - 1)]


func stat_cap_for_league(idx: int) -> float:
	return float(league_at(idx).get("cap", 900.0))


func team_size_for_league(idx: int) -> int:
	var league_name: String = league_at(idx).get("name", "")
	return int(team_size_by_league.get(league_name, 1))


func current_league() -> Dictionary:
	return league_at(league_index)


func current_league_name() -> String:
	return current_league().get("name", "")


## The league cap that training should respect right now. `game_data.gd:make_monster()` and
## `game_data.gd:train()` both currently nudge stats toward a hardcoded `STAT_CAP := 900.0` — see
## the handover report for the exact two call sites that need to read this instead.
## ⚠️ THE OVERRIDE EXISTS BECAUSE RIVAL GENERATION READ THE WRONG CAP, AND IT WAS MEASURED.
## `GameData.make_monster()` nudges a rolled monster toward `GameData.stat_cap()`, which is this
## function — the PLAYER's cap. So generating a Tin rival while standing at Tamers Apex produced
## a "Tin" monster with a 335 top stat against a Tin ceiling of 300 (instrument, 2026-08-09:
## Tin 335/300, Bronze 430/400, Iron 463/500 — three of the eleven cups were fielding monsters
## that would be ILLEGAL in the league whose name was on the door). `make_league_rivals()` scopes
## this to the league actually being fought, so a cup's field belongs to that cup.
var _cap_override: float = -1.0


func current_stat_cap() -> float:
	if _cap_override > 0.0:
		return _cap_override
	return stat_cap_for_league(league_index)


func current_team_size() -> int:
	return team_size_for_league(league_index)


func is_final_league(idx: int = -1) -> bool:
	var check_idx := league_index if idx < 0 else idx
	return leagues.is_empty() or check_idx >= leagues.size() - 1


## A monster/team may compete in the league the player has REACHED, or any league below it —
## never one it hasn't unlocked yet. Mirrors the intent of town.ts's per-monster licenseIndex rule
## ("own league or below") at run granularity rather than per-monster.
func can_enter_league(idx: int) -> bool:
	return idx >= 0 and idx <= league_index and idx < leagues.size()


# ── the field: how many rivals, how strong, and who runs the league ───────────

## Rival TEAMS per cup, by league — `town.ts:RIVAL_TEAM_COUNT_BY_LEAGUE`, which never made the
## crossing (every cup at every rung was hardcoded to three). The bigger leagues run a bigger
## field, so a Platinum cup is a longer, more expensive commitment than a Wood one even before
## the opponents get harder. ⚠️ Reads by league NAME, like `team_size_by_league`, so it cannot
## silently mis-index if the ladder is ever reordered.
const RIVAL_COUNT_BY_LEAGUE := {
	"Wood": 3, "Copper": 3, "Tin": 3, "Bronze": 3, "Iron": 3,
	"Silver": 4, "Gold": 4, "Platinum": 5, "Masters": 5, "Tamer Elite": 5, "Tamers Apex": 5,
}

func rival_count_for_league(idx: int) -> int:
	return int(RIVAL_COUNT_BY_LEAGUE.get(league_at(idx).get("name", ""), 3))


## ⚠️ THE SHAPE OF A CUP, AND THE MEASUREMENT THAT FORCED IT. Rival strength used to be
## `league_cap / top_league_cap` — one flat number for the whole cup, and one that made the
## bottom of the ladder a walkover: a Copper rival was filled to 18% of the ceiling while the
## player stood at 100% of the same ceiling. Instrumented over 24 fights per rung (player trained
## to their own cap), the old curve read
##
##   Wood .83 | Copper 1.00 | Tin 1.00 | Bronze 1.00 | Iron .96 | Silver 1.00 | Gold .92
##   Platinum .83 | Masters .58 | Tamer Elite .79 | Tamers Apex .54
##
## — six rungs at or within noise of a 100% win rate, then a wall, and NOT MONOTONIC (Tamer Elite
## easier than Masters). That is not a difficulty curve; it is a corridor with a door at the end.
##
## A cup now has an ARC instead: the field is drawn from OPENER to CHAMPION, so every league —
## Wood included — asks the same question in its own terms. Round one is a team you should beat;
## the last round is the league's titleholder, filled near their own ceiling. The player can see
## the whole field before paying the entry fee, which is what makes "am I ready" a decision made
## with knowledge rather than a coin toss.
## ⚠️ AND THE ARC ITSELF STEEPENS UP THE LADDER, which the old model could not express at all.
## Fill is a fraction of the league's OWN ceiling, and the player is measured against that same
## ceiling — so a constant fill makes every rung equally hard no matter how high the cap climbs.
## Instrumented at a fully-trained player (16 fights per round per rung), a flat 0.86 champion
## gave P(sweep) 0.35 at Wood and 0.88 at Masters: the ladder got EASIER as it went up, which is
## the inverted-progression failure this studio has hit before. The endpoints below slope it the
## right way; they are a first increment, not a balanced number (the baseline is suspended).
## ⚠️ THESE FOUR WERE AUTHORED AGAINST A GENERATOR THAT SILENTLY DAMPED THEM BY 0.6, AND THE
## DAMPING IS NOW GONE (`game_data.gd:make_monster:room_mult`). The old values were commented as
## "0.80..0.93 of its own ceiling" and reached the arena at 0.48..0.56; taken literally after the
## fix, a 65%-filled roster — which is what a real winning roster measures at — beat the Wood
## champion 38% of the time and swept the Wood cup 13%, and the arc autopilot stalled at Silver
## and never finished the game. The numbers below restore a beatable bottom rung at the corrected
## semantics, measured with `_probe_career_arc.tscn -- --gate-only` (14s per reading).
## ⚠️ AND THE FOUR ENDPOINTS BELOW ARE NOW READ OFF A MEASURED TRANSFER FUNCTION, NOT CHOSEN.
## `scenes/_probe_ladder_slope.tscn -- --response` prints, per rung, the win rate a REAL climbing
## player has against one rival team at each fill. It is steep and it is nearly the same curve at
## every rung: ~90% at fill .40, ~80% at .50, ~50% at .60, ~25% at .70, ~6% at .85. So the old
## `FIELD_CHAMPION_TOP = 0.95` was not a hard champion, it was an UNBEATABLE one (~6%), and the
## reason the previous round did not see that is in the next warning.
## ⚠️ THE OLD READING WAS TAKEN AGAINST A PLAYER WHO DOES NOT EXIST. `_probe_career_arc.gd`
## measures every rung against a team pinned at 65% of that rung's cap with all six stats FLAT —
## a build no training system can produce (it dumps nothing, so it carries a maximal CON, and
## `maxHp` is superlinear in CON). Section 4 of the slope probe measures both builds on the same
## field: the flat build sweeps far more often than a generator-built team at the identical fill.
## Every ladder number in this project is a statement about the team that was assumed.
##
## ⚠️ AND THE LAST REWRITE: THE FIELD IS PRICED AGAINST THE CLIMBER, NOT AGAINST THE CAP.
## Measured at 32 cups per rung, a cap-relative field produced this advance curve —
##   Wood 53 | Copper 84 | Tin 94 | Bronze 84 | Iron 94 | Silver 78 | Gold 59
##   Platinum 19 | Masters 44 | Tamer Elite 63 | Apex 28
## — and Platinum is not an outlier by accident. The player's stat budget grows LINEARLY in time
## (a measured 14.45 points per monster-week) while the cap schedule steps unevenly: +100 a rung
## to Iron, then +150 at Gold, +150 at Platinum, then +100, +50, +50. So the player's fraction of
## the ceiling DIPS exactly where the cap jumps (Platinum .59, the lowest of the top block) and
## recovers at the top (Apex .67). A field priced as a fraction of the CAP therefore presses
## hardest precisely where the player is relatively weakest, and the ladder's difficulty ends up
## an artefact of `data.json`'s cap table — a table nobody ever wrote as a difficulty curve.
##
## So the endpoints below are RATIOS TO THE EXPECTED CLIMBER, not fractions of the ceiling.
## 1.00 means "a team as filled as the player should be at this rung"; 1.10 means "10% ahead of
## where you should be". The cap schedule can now be re-authored without silently re-authoring
## the difficulty of the whole ladder along with it.
##
## Measured response of that ratio (the calibration these were read off, `-- --response`):
##   ratio .80 -> ~90% win  |  .95 -> ~72%  |  1.05 -> ~55%  |  1.15 -> ~35%  |  1.25 -> ~22%
const FIELD_OPENER_RATIO_BOTTOM := 0.80   ## round one, Wood — winnable, never free
const FIELD_OPENER_RATIO_TOP := 0.90      ## round one, Tamers Apex
const FIELD_QUAL_RATIO_BOTTOM := 0.95     ## the last qualifying round, Wood
const FIELD_QUAL_RATIO_TOP := 1.00        ## the last qualifying round, Tamers Apex
const FIELD_CHAMPION_RATIO_BOTTOM := 1.02 ## the Paddock King
const FIELD_CHAMPION_RATIO_TOP := 1.06    ## the Dynast — the hardest single opponent in the game
const CHAMPION_REMATCH_BUMP := 0.04       ## they train too — see `champion_fill_for()`

## ⚠️ A DEEPER DRAW IS HARDER AT EQUAL TEAM STRENGTH, AND THE RULE ALONE CANNOT ABSORB IT. A cup
## result is a product of its rounds: at an identical ratio band the 3-round rungs measured 84-94%
## advance and the 5-round rungs 19-44%. Round count is thus the strongest single term in the
## ladder's slope — and it is monotone in league (3,3,3,3,3,4,4,5,5,5,5), which is exactly the
## backbone a climb wants. What it must not do is swamp everything else, so a deeper draw's
## QUALIFIERS come down slightly: the depth is still felt, but the rung stays on curve.
const FIELD_DEPTH_RELIEF_PER_ROUND := 0.03   ## ratio units per round beyond the third

## ⚠️ THE SUMMIT'S QUALIFYING FIELD IS DELIBERATELY THINNER, AND THIS IS THE HONEST TRADE.
## Tamers Apex is the one rung that grants no dropped round (`dropped_rounds_allowed`), so its
## result is a PRODUCT of five win rates. At the ratios the rest of the top of the ladder uses,
## that product is ~2-6% — forty cups for the ending of the game, which is not a test, it is a
## queue. Something has to give, and the choice is between a weak Dynast and a thin draw. The
## Dynast stays the hardest single opponent in the game; the four teams before them come down
## instead. That is also the right story: the Apex circuit is an invitational, and the test of it
## is the titleholder, not the depth of the field.
const FIELD_APEX_QUAL_RELIEF := 0.18

## ⚠️ THE LADDER IS NOT LINEAR IN ITS OWN INDEX, AND WOOD IS WHY. Measured (`-- --response`),
## the fill -> win-rate curve is the same shape at every rung EXCEPT Wood, where it is nearly
## flat: a Wood player at 42% of a 100 cap wins 63% against a 0.30-fill field and still 44%
## against a 0.60-fill one, where every other rung spans 100% -> 56% over the same range. The
## reason is structural, not tuning: Wood is a 1v1 at a cap of 100 with base stats already at ~23,
## so the whole dynamic range is ~30 stat points and the fight is decided by species matchup.
## ⚠️ **WOOD'S DIFFICULTY IS THEREFORE NOT TUNABLE FROM THIS FILE** — it sits at ~55-65% advance
## whatever the field is filled to. That is reported, not hidden, and it is the one rung this
## workstream could not slope. Interpolating the other ten rungs LINEARLY out of Wood's endpoints
## made Copper..Silver walkovers, so the interpolation is shaped: it lifts the field out of Wood
## quickly and then climbs steadily, which is what a ladder wants.
const FIELD_SHAPE_EXP := 0.35

## ⚠️ A SHAPED TEAM IS NOT WORTH THE SAME AS A FLAT ONE AT THE SAME FILL, AND THE UNCORRECTED GAP
## COST THE LADDER 25 POINTS OF ADVANCE RATE AND MADE MASTERS UNCLEARABLE.
## Every `FIELD_*_RATIO_*` above was calibrated against the OLD flat generator. The moment the
## archetypes were wired into `make_cup_field()` — a class-shaped roster that spends its stat
## budget on the stats its kit uses, fighting with its own team plan — the eleven-rung ADVANCE
## column fell, at IDENTICAL authored fills and against the IDENTICAL modelled climber, from
##   66 66 72 59 63 56 47 47 19 50 22   to   50 47 50 22 25 47 16  9  0 16  9
## and `_probe_ladder_slope` reported a WALL at Masters. Nothing about the ladder's difficulty
## DESIGN had changed; only the kind of team had.
##
## So this is a UNIT CONVERSION, not a nerf: it says a shaped, ordered team at 0.90 of a flat
## build's fill is the same opponent. It lives here, not in `tactics.gd:archetype_fill`, because
## `tactics.gd` answers a different question (are the six KINDS equal to each other, measured
## against a generic reference in `_probe_archetypes`) and folding the two together made both
## instruments disagree with themselves — the archetype probe's kind-parity band blew out to 42
## points the moment this value was applied there. One knob per question.
## ⚠️ RE-DERIVE IT WITH `scenes/_probe_ladder_slope.tscn`, NOT BY REASONING. At 1.00 the ladder
## has a wall; at 0.90 it reads 63 -> 25 with zero unclearable rungs. Any future change to
## `roster.gd:_shape_to_class` or to `battle_sim`'s plan handling moves it.
const FIELD_ARCHETYPE_POWER_MULT := 0.90

## ── WHAT THESE CONSTANTS ACTUALLY PRODUCE (record it, or the next round re-derives it) ───────
## `scenes/_probe_ladder_slope.tscn`, 32 cups per rung against the modelled climber. ADVANCE is
## the promotion rule; TITLE is the clean sweep; "cups" is 1/ADVANCE, i.e. attempts per rung.
##
##   league       Wood Copp  Tin Bron Iron Silv Gold Plat Mast Elit Apex
##   ADVANCE %      66   66   72   59   63   56   47   47   19   50   22
##   TITLE   %      19   19   28   19   16   13    3   13    0   16   22
##   cups          1.5  1.5  1.4  1.7  1.6  1.8  2.1  2.1  5.3  2.0  4.6
##
## Wood -> Apex: 66% -> 22%, headroom +0.15 -> -0.04, 0 rungs the climber cannot clear, ~26 cups
## for the whole ladder. Before this round: a flat 63/63/25/63/38/63/50 with promotion gated on a
## 5-round sweep, measured at 88 cups for 11 rungs (docs/META_GAME_REVIEW.md §2).
## ⚠️ THE RESIDUAL WOBBLE (Masters 19 vs Tamer Elite 50) IS INSIDE THE INSTRUMENT'S OWN NOISE —
## 32 samples of a proportion carries about ±9 points. Do not chase it with another tuning pass;
## raise `seeds_climb` first and see whether it survives. That is this project's oldest lesson.

# ── the expected climber (a difficulty curve needs a model of the player) ───────────────
## ⚠️ PUTTING A PLAYER MODEL IN THE LADDER FILE IS DELIBERATE. A difficulty curve is a statement
## about a PLAYER; a file that only knows the field can only produce numbers whose meaning depends
## on an assumption made somewhere else — which is exactly how `_probe_career_arc.gd`'s flat-65%
## team quietly became this project's definition of "the player". These constants are measured,
## not invented: docs/META_GAME_REVIEW.md §T1 (14.45 stat points per monster-week under the
## best-known training policy) and §2 (a winning career of 319 weeks across 11 rungs).
## ⚠️ THEY WILL DRIFT, AND THAT IS THE MAINTENANCE COST OF DOING THIS HONESTLY. Re-run
## `_probe_career_arc.tscn` after any training-system change and bring these back in line with its
## measured weeks-per-rung and points-per-week; `_probe_ladder_slope.tscn` prints the model it is
## using on every run, so the two can be compared at a glance.
## ⚠️ 12.97, NOT THE REVIEW'S 14.45, AND THE DIFFERENCE IS THIS ROUND'S OWN WORK.
## docs/META_GAME_REVIEW.md §T1 measured 14.45 against the training system as it stood BEFORE the
## focus-cost rework; `scenes/_probe_training.tscn` §2 measures the system as it stands now and
## reports 12.97 points/week for the best drill family (and a 336-week career banking 4,345 points
## for a final stat total of 4,479 — an average of 746 per stat, i.e. 0.68 of the Apex ceiling,
## which is the number `expected_climber_fill` has to reproduce). Always prefer the probe that
## measures the CURRENT build over a document that measured an older one.
## ⚠️ AND BECAUSE THE FIELD IS AUTHORED AS A RATIO TO THIS, CORRECTING IT DOES NOT RE-TUNE THE
## LADDER — it re-anchors the absolute fills and leaves every difficulty ratio intact. That is the
## whole point of pricing the field against the climber instead of against the cap.
const CLIMBER_PTS_PER_WEEK := 12.97
const CLIMBER_WEEKS_PER_RUNG := 29.0
const CLIMBER_WARMUP_WEEKS := 8.0     ## nobody enters a cup the week they arrive at a rung
const CLIMBER_BASE_STAT := 23.0       ## mean base stat of a fresh recruit across the roster
const STAT_COUNT := 6.0


## ⚠️ A CUP IS FOUGHT BY A TEAM, AND THE TEAM GROWS — SO THE ROSTER'S FILL IS DILUTED EVERY TIME
## THE LADDER ASKS FOR ANOTHER BODY. This model originally assumed one monster that had trained
## since week zero, and then divided by the league cap. `teamSizeByLeague` is 1,2,2,3,3,4,4,5,5,5,5:
## a stable arriving at Silver must buy a FOURTH monster, and that monster starts at a fresh
## recruit's ~23 per stat with no history at all. Measured on `_probe_career_arc.tscn`, the
## autopilot's roster fill tracked the old model within a few points to Iron (57/55/68/70/68 vs
## 40/52/55/57/58) and then fell off a cliff exactly where the team grew — Silver 61%, Gold 43%
## against a model saying 0.59 and 0.56 — and Gold is where the arc stalls. The field was
## therefore being priced against a stable that does not exist above Iron.
##
## ⚠️ AND THE ROAD IS NOT FREE EITHER. A cup now spends real weeks (`CupRun.weeks_for_cup`) and
## nobody trains on them: the same arc spent 124 of 483 weeks travelling, 26%. A model of "points
## per week" that ignores a quarter of the calendar is a model of a player who never enters a cup.
##
## Both terms are measured, and both are the kind of thing that used to be a silent assumption in
## a comment. Re-derive them from `_probe_career_arc.tscn`'s `fill@exit` column and its `weeks ON
## THE ROAD` line whenever training, travel or team size changes.
## ⚠️ AND IT IS STILL A ONE-MONSTER MODEL, WHICH IS THIS FILE'S LARGEST KNOWN INACCURACY.
## An attempt to correct it landed and was REVERTED in the same session, and the failure is worth
## more than the attempt: modelling each body's own join week (`teamSizeByLeague` is
## 1,2,2,3,3,4,4,5,5,5,5, so a fresh ~23-per-stat recruit joins at Copper, Bronze, Silver and
## Platinum) and taxing the calendar by the 26% of weeks the arc measured as TRAVEL drove the
## expected fill to 0.22-0.31 against an arc that independently measures 0.44-0.67. The direction
## is certainly right — the arc's roster fill tracks this model to Iron and then collapses to 0.43
## at Gold, exactly where the team grows — but the magnitude is not, and a difficulty curve priced
## against a player half as strong as the real one is worse than one priced against a player who
## does not exist in a known direction.
## ⚠️ SO THE NEXT ROUND'S JOB IS TO MEASURE THE TABLE, NOT TO THEORISE IT: take `fill@exit` per
## rung from a winning `_probe_career_arc.tscn` run and interpolate THAT, instead of deriving a
## fill from first principles at all. Do not re-attempt the analytic version.
func expected_climber_fill(idx: int) -> float:
	var weeks: float = CLIMBER_WEEKS_PER_RUNG * float(maxi(0, idx)) + CLIMBER_WARMUP_WEEKS
	var per_stat: float = CLIMBER_BASE_STAT + CLIMBER_PTS_PER_WEEK * weeks / STAT_COUNT
	return clampf(per_stat / maxf(1.0, stat_cap_for_league(idx)), 0.05, 1.0)


## How far up the ladder a league sits, 0..1. The one place the slope is computed.
func ladder_t(idx: int) -> float:
	var last: int = maxi(1, leagues.size() - 1)
	return clampf(float(clampi(idx, 0, last)) / float(last), 0.0, 1.0)


## `ladder_t` shaped by `FIELD_SHAPE_EXP` — the curve every field endpoint is interpolated along.
## See the note on `FIELD_SHAPE_EXP`: rises fast out of Wood, then climbs steadily.
func ladder_shape(idx: int) -> float:
	return pow(ladder_t(idx), FIELD_SHAPE_EXP)


## Fill for round `round_idx` of a `rounds`-long field. TWO SEGMENTS, not one line: the qualifying
## rounds ramp opener -> qualifier-ceiling, and the last round is the champion, a step above them.
## A 3-round cup and a 5-round cup therefore ask the same question (beat the draw, then beat the
## titleholder) at different length, instead of a 5-round cup being a 3-round cup squared.
func field_fill(round_idx: int, rounds: int, idx: int = -1) -> float:
	var league: int = idx if idx >= 0 else league_index
	var r: int = maxi(1, rounds)
	if round_idx >= r - 1:
		return clampf(champion_fill_for(league), 0.05, 0.98)
	var lt: float = ladder_shape(league)
	var relief: float = float(maxi(0, r - 3)) * FIELD_DEPTH_RELIEF_PER_ROUND
	if is_final_league(league):
		relief += FIELD_APEX_QUAL_RELIEF
	var opener: float = lerpf(FIELD_OPENER_RATIO_BOTTOM, FIELD_OPENER_RATIO_TOP, lt) - relief
	var qual_top: float = lerpf(FIELD_QUAL_RATIO_BOTTOM, FIELD_QUAL_RATIO_TOP, lt) - relief
	# `r - 1` qualifying rounds, indices 0 .. r-2. With only one qualifier it IS the opener.
	var t: float = 0.0 if r <= 2 else clampf(float(round_idx) / float(r - 2), 0.0, 1.0)
	return clampf(lerpf(opener, qual_top, t) * expected_climber_fill(league), 0.05, 0.98)


## ⚠️ THE CHAMPION REMEMBERS — within the limits of what the save file actually carries.
## `leagues_won[idx]` is persisted (`save_game.gd`), so "have you taken this title off them
## before" survives a reload and is the one piece of history this can honestly stand on: come
## back to a league you already cleared and its champion has spent the interval training.
## A per-session grudge counter would NOT survive a save/load — `save_game.gd` is not this
## workstream's file and serialises a fixed field list — so the escalation is derived from saved
## state rather than stored, deliberately.
func champion_fill_for(idx: int) -> float:
	var beaten: bool = idx >= 0 and idx < leagues_won.size() and bool(leagues_won[idx])
	var ratio: float = lerpf(FIELD_CHAMPION_RATIO_BOTTOM, FIELD_CHAMPION_RATIO_TOP, ladder_shape(idx))
	var base: float = ratio * expected_climber_fill(idx)
	return clampf(base + (CHAMPION_REMATCH_BUMP if beaten else 0.0), 0.05, 0.98)


## THE ELEVEN FACES OF THE LADDER. `CLAUDE.md` lists "named rival in cups" as a known gap — the
## rival existed only as a challenge skirmish, so the climb was eleven anonymous brackets. One
## titleholder per rung, fixed (not rolled), is the cheapest version that actually pays: the
## player learns a name, loses to it, trains for it, and takes it. The `read` line is the scouting
## payoff — it says what that champion's team is trying to DO, which is the axis CLAUDE.md's kit
## doctrine section asks for.
const CHAMPIONS := [
	{"name": "Otta Vance", "title": "the Paddock King", "read": "Comes straight down the middle and hits first. Nothing clever."},
	{"name": "Merrin Kell", "title": "the Kettle Queen", "read": "Two bodies that never separate — peel one and the other is already on you."},
	{"name": "Sable Roke", "title": "the Tinsmith", "read": "Stalls. Wins on the clock unless you make the fight happen."},
	{"name": "Dunnal Bray", "title": "Bellfounder", "read": "Opens wide, then collapses the flanks. Punishes a spread deployment."},
	{"name": "Ysolde Ferrum", "title": "the Anvil", "read": "Will not break. Brings guards and expects you to run out of patience."},
	{"name": "Cassia Vane", "title": "the Quicksilver", "read": "Refuses to stand still. Kites the slowest thing you field all day."},
	{"name": "Auric Halloway", "title": "the Sovereign", "read": "Buys tempo with buffs and cashes it in one round. Survive the spike."},
	{"name": "Perrin Adamant", "title": "the Vanguard", "read": "Focuses one target down and moves on. Your weakest body dies first."},
	{"name": "Ianthe Corvo", "title": "the Crownless", "read": "Controls. You will be stunned, silenced, and out of position on purpose."},
	{"name": "Marek Thule", "title": "the Undisputed", "read": "No weakness to find. Beats you with execution, not with a trick."},
	{"name": "The Dynast", "title": "Apex incumbent", "read": "Everything above, at once, by a team that has never lost the title."},
]

## ⚠️ THE NAME AND TITLE ARE AUTHORED HERE; THE `read` IS NOT. The eleven lines in `CHAMPIONS`
## were written before any champion differed by more than a fill fraction, and two of them
## ("collapses the flanks", "kites the slowest thing you field") describe SPATIAL behaviour that
## `battle_sim.gd` — which has no positions — structurally cannot produce. A scouting line the
## engine cannot honour is a lie told to the player in the one place the game asks them to
## prepare. So the read is served from `tactics.gd`, where every line is asserted against the
## event log by `scenes/_probe_archetypes.tscn`. The strings below are kept only as the record of
## what was once claimed.
func champion_for(idx: int) -> Dictionary:
	if idx < 0 or idx >= CHAMPIONS.size():
		return {"name": "the titleholder", "title": "", "read": "", "archetype": ""}
	var c: Dictionary = CHAMPIONS[idx].duplicate()
	c["archetype"] = TacticsScript.archetype_for_league(idx)
	c["read"] = TacticsScript.champion_read(idx)
	c["counter"] = TacticsScript.champion_counter(idx)
	return c


func has_beaten_champion(idx: int) -> bool:
	return idx >= 0 and idx < leagues_won.size() and bool(leagues_won[idx])


## The seed a cup's FIELD is drawn from. Stable for a whole game-month (4 weeks) so the player can
## scout a field, go and train, and come back to the same opponents — scouting that the calendar
## re-rolls under you is not scouting. Rolls over between months, so a cup re-entered a month
## later is a genuinely new draw rather than the same three teams forever.
func cup_field_seed(idx: int) -> int:
	return hash("cup:%d:%d:%d" % [idx, int(week) / 4, league_index])


# ── rivals ────────────────────────────────────────────────────────────────

## Build `n` rival monsters belonging to a LEAGUE — never to the player's own stats.
##
## `fill` is how completely this team has filled THAT LEAGUE's ceiling (see `field_fill()`);
## passing < 0 asks for a mid-field team, which is what a caller that does not care about the
## cup's arc gets. `seed_` makes the draw reproducible so the same field can be shown on the
## sign-up screen and then fought.
##
## ⚠️ Scopes `_cap_override` for the duration: `GameData.make_monster()` reads the player's cap
## through `current_stat_cap()`, and without this a punch-down cup fields over-cap monsters (see
## the note on `_cap_override`). Always restored, including on the early-out path.
func make_league_rivals(n: int, league_idx: int = -1, fill: float = -1.0, seed_: int = -1,
		archetype: String = "") -> Array:
	var idx := league_index if league_idx < 0 else league_idx
	var use_fill: float = fill
	if use_fill < 0.0:
		var rounds := rival_count_for_league(idx)
		use_fill = field_fill(rounds / 2, rounds, idx)
	if seed_ >= 0:
		Roster.rng.seed = seed_
	var prev := _cap_override
	_cap_override = stat_cap_for_league(idx)
	## ⚠️ `room_mult = 1.0` — the cup field is the ONE caller whose number is a fraction of the
	## league ceiling rather than a hand-chosen feel value, so it must not be damped. See
	## `game_data.gd:make_monster`. Without this, `FIELD_CHAMPION_TOP = 0.93` reached the arena at
	## ~0.56 and a 65%-filled player team swept all eleven leagues.
	if archetype != "":
		use_fill *= FIELD_ARCHETYPE_POWER_MULT
	var team: Array = Roster.make_rival_team(n, clampf(use_fill, 0.0, 1.0), 1.0, archetype)
	_cap_override = prev
	return team


## The whole field of a cup, in fighting order — one entry per round:
##   {"team": Array[MonsterInstance], "fill": float, "champion": bool, "label": String}
## Drawn off `cup_field_seed()` so the sign-up screen and the live run see the SAME opponents.
func make_cup_field(idx: int, rounds: int = -1) -> Array:
	var n: int = rounds if rounds > 0 else rival_count_for_league(idx)
	var size: int = team_size_for_league(idx)
	var base_seed: int = cup_field_seed(idx)
	var out: Array = []
	var learned: Array = archetypes_taught_by(idx)
	for r in range(n):
		var fill: float = field_fill(r, n, idx)
		var is_champ: bool = r == n - 1
		## ⚠️ THE DRAW ONLY EVER POSES PROBLEMS THE LADDER HAS ALREADY TAUGHT. The champion is this
		## rung's authored kind; every qualifying round draws from the kinds introduced at or below
		## it, deterministically off the same field seed. That is what makes the climb a vocabulary
		## rather than eleven anonymous brackets — a Wood player never meets a control team, and by
		## Apex every kind in the game is in the draw.
		var gid: String = TacticsScript.archetype_for_league(idx) if is_champ \
			else String(learned[abs(base_seed + r * 31) % maxi(1, learned.size())])
		out.append({
			"team": make_league_rivals(size, idx, fill, abs(base_seed + r * 7919) % 2147483647, gid),
			"fill": fill,
			"champion": is_champ,
			"archetype": gid,
			"read": TacticsScript.champion_read(idx) if is_champ else TacticsScript.read_for(gid),
			"label": "%s, %s" % [champion_for(idx).get("name", ""), champion_for(idx).get("title", "")] if is_champ
				else "Round %d of the draw" % (r + 1),
		})
	return out


## The archetypes the ladder has introduced at or below `idx`, in the order it introduced them.
## Public because the sign-up and scouting screens want to say "you have seen this before".
func archetypes_taught_by(idx: int) -> Array:
	var seen: Array = []
	for l in range(0, clampi(idx, 0, leagues.size() - 1) + 1):
		var g: String = TacticsScript.archetype_for_league(l)
		if g != "" and not seen.has(g):
			seen.append(g)
	if seen.is_empty():
		seen.append("rushdown")
	return seen


## Round-robin reward by FINAL PLACEMENT — `town.ts:PLACEMENT_REWARD_FRACTION` (100/65/40/0),
## which did not make the crossing either. It matters because it is the difference between a cup
## being a coin-flip on the whole purse and a cup being a result you can be *nearly* good enough
## for: losing only to the champion still pays for the trip.
const PLACEMENT_REWARD_FRACTION := {1: 1.0, 2: 0.65, 3: 0.4}

func placement_reward_fraction(placement: int) -> float:
	return float(PLACEMENT_REWARD_FRACTION.get(placement, 0.0))


## Placement from a win count: every team you beat is a team you finish above.
func placement_for(wins: int, rival_count: int) -> int:
	return maxi(1, rival_count - wins + 1)


# ── the rank and the title are two different things ──────────────────────────
## ⚠️ THE SWEEP GATE WAS THE LOTTERY, AND THE ARITHMETIC IS UNARGUABLE. Promotion used to require
## winning EVERY round. A per-round win rate of w gives w^n, and n is 5 from Platinum up: at a
## measured 49% per round (META_GAME_REVIEW §L1) that is a 3% chance per cup. The player cannot
## tell "my stable is wrong" (go and train — the whole loop) from "three coins have not landed"
## (press the button again), which is CLAUDE.md's own definition of a slot machine applied to the
## ladder instead of the fight.
##
## So the RANK and the TITLE are now separate results of the same cup:
##   * **the rank** (promotion) — win the draw, dropping at most `DROPPED_ROUNDS_ALLOWED`.
##   * **the title** (`swept`, `leagues_won`, `championBeaten`, the rematch bump, and the terminal
##     Apex win) — still the whole draw, champion included, with nothing dropped.
##
## That keeps the named champion as the thing the climb is ABOUT — you can be promoted on the
## standings while Ianthe Corvo keeps her title, and the result screen already says exactly that
## (`tournament_ui.gd:_show_result` reads `championBeaten`, which stays sweep-only) — while making
## the rung itself a test of preparation rather than of variance.
##
## ⚠️ AND TAMERS APEX DOES NOT GRANT THE DROP. There is no rank above it: the only thing left to
## win is the title, which has always meant the clean sweep. "Nothing but the whole draw takes the
## Dynast's title" is both the rule and the flavour, and it is what makes the last rung a real
## test without making the other ten a lottery.
##
## ⚠️ A PURE FUNCTION OF THE WIN COUNT, DELIBERATELY. `CupRun.finish()` (not this workstream's
## file) hands `apply_tournament_outcome()` a win count and nothing else, so any rule that needed
## to know WHICH rounds were won — "you must beat the champion, but may drop a qualifier" — would
## have to be evaluated differently on the live path than on the headless one. Two paths, one
## rule: that is worth more than the extra expressiveness.
const DROPPED_ROUNDS_ALLOWED := 1

func dropped_rounds_allowed(idx: int) -> int:
	return 0 if is_final_league(idx) else DROPPED_ROUNDS_ALLOWED


## Wins needed to take the RANK (promotion) at `idx` out of a `rival_count`-round cup. Public
## because the sign-up screen should be able to say it out loud, and because the slope instrument
## measures the real rule rather than a copy of it.
func wins_needed_to_advance(idx: int, rival_count: int) -> int:
	return maxi(1, rival_count - dropped_rounds_allowed(idx))


## ⚠️ THE FRONTIER'S REAL WALL WAS NEVER ITS DIFFICULTY — IT WAS OWNING FIVE BODIES.
## `docs/META_GAME_REVIEW.md` §5 item 1, and this round's arc confirms it at two cadences: the
## autopilot spent 10% of a 483-week career (and 48% of a slower-cupping variant, 137 weeks of
## 288 with ZERO cups entered at Bronze) unable to enter the frontier cup FOR WANT OF BODIES,
## farming the rung below at 50% reward while its round win rate sat at 65%. That is a poverty
## trap wearing difficulty's clothes: the rung is beatable, the stable simply cannot buy the
## fifth mouth out of the income the fourth rung pays, and nothing on screen says so.
##
## The engine never required a full team — `enter_league_tournament()` has always sliced
## `min(team_size, roster)` and fought short. Only the SIGN-UP SCREEN forbade it. So this is not
## a new mechanic; it is the removal of a lock the simulation never had, and it converts an
## invisible economy wall into a visible, priced decision: enter a body down and fight
## outnumbered, or go and earn the recruit. Being outnumbered is a real and sufficient penalty —
## `spatial.gd`'s flanking bonus is granted precisely to the side with the extra body — so no
## additional handicap is authored on top of it.
##
## ⚠️ ONE BODY, NOT ANY NUMBER. A 3v5 is not a decision, it is a formality with an entry fee, and
## the ladder's difficulty model assumes a full side. The allowance is deliberately the smallest
## thing that unlocks the trap.
const SHORT_ENTRY_ALLOWANCE := 1

## The smallest roster that may enter a cup at `idx`. Public so the sign-up screen, the autopilot
## and the arc instrument all read ONE rule instead of three copies of it.
func min_team_to_enter(idx: int) -> int:
	return maxi(1, team_size_for_league(idx) - SHORT_ENTRY_ALLOWANCE)


static func placement_label(placement: int) -> String:
	match placement:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
	return "%dth" % placement


# ── tournaments / promotion ──────────────────────────────────────────────────

## Run a full round-robin: the player's roster (sliced to the target league's team size) against
## `rival_count` league-scaled rival teams, one headless `BattleSim` fight each. Winning the draw
## (at most `dropped_rounds_allowed()` losses) takes the RANK and PROMOTES if the league fought was
## the ladder FRONTIER; sweeping the whole draw additionally takes the TITLE off the named
## champion. At Tamers Apex the two coincide, and the title is the end of the game.
##
## `target_league_idx` defaults to the player's current frontier league; passing a lower index
## re-fights an already-unlocked league (for gold/grinding) without disturbing ladder position.
##
## ⚠️ HEADLESS BATCH — fights all `rival_count` matches in one frame with `BattleSim` (the
## non-spatial reference engine), never touching the screen. This is what the QA harness and
## sandbox drive, and its outcome (sweep/promotion/game-won) is EXACTLY what `apply_tournament_
## outcome()` below computes — this function is now a thin wrapper: play `rival_count` fights,
## then hand the win count to the same tail the LIVE per-round path (`CupRun` autoload) uses, so
## the two paths can never silently diverge on what counts as a win.
## ⚠️ `rival_count` DEFAULTS TO -1 = "whatever this league fields" (`rival_count_for_league`).
## An explicit count is still honoured — the existing probes pass 3 — but the ladder's own shape
## is now the default rather than a hardcoded three at every rung.
func enter_league_tournament(target_league_idx: int = -1, rival_count: int = -1, seed_: int = -1) -> Dictionary:
	var idx := league_index if target_league_idx < 0 else clampi(target_league_idx, 0, league_index)
	var rounds: int = rival_count if rival_count > 0 else rival_count_for_league(idx)
	var team_size := team_size_for_league(idx)
	var player_team: Array = Roster.monsters.slice(0, mini(team_size, Roster.monsters.size()))

	var use_seed := seed_ if seed_ >= 0 else (week * 97 + idx * 13 + rounds)
	var rng := RandomNumberGenerator.new()
	rng.seed = use_seed

	var field: Array = make_cup_field(idx, rounds)
	var matches: Array = []
	var wins := 0
	for i in range(rounds):
		for m in player_team:
			m.reset_for_battle()
		var rival_team: Array = field[i]["team"]
		## ⚠️ THE ARCHETYPE'S TACTICS HAVE TO REACH THE FIGHT OR THE ARCHETYPE IS A COSTUME. This
		## path built the sim with NO plans, so a focus-fire field fell through to the lowest-HP
		## default and fought identically to a wall. `player_team` is load-bearing — it is what
		## makes the man-mark real (`Tactics.softest_body`).
		var gid: String = String(field[i].get("archetype", ""))
		var plan_b: Dictionary = TacticsScript.team_plan_for_gameplan(gid, player_team) if gid != "" else {}
		var orders: Dictionary = TacticsScript.orders_for_gameplan(gid, rival_team) if gid != "" else {}
		var sim = BattleSimScript.new(player_team, rival_team, rng.randi(), {}, plan_b, orders)
		var result: Dictionary = sim.run()
		var won_match: bool = result.get("winner", "") == "A"
		if won_match:
			wins += 1
		matches.append({"result": result, "won": won_match, "champion": bool(field[i]["champion"])})

	var out := apply_tournament_outcome(idx, wins, rounds)
	out["teamSize"] = team_size
	out["matches"] = matches
	return out


## THE SHARED TAIL — sweep check, promotion, terminal win. Extracted so both
## `enter_league_tournament()` (headless batch, above — QA harness/sandbox) and `CupRun`
## (autoload; the live per-round tactics→arena presentation) apply the IDENTICAL rule for what a
## win count means. ⚠️ Do not duplicate this logic anywhere else — a second copy is exactly how
## the two paths would drift apart on a promotion edge case nobody meant to change.
func apply_tournament_outcome(idx: int, wins: int, rival_count: int) -> Dictionary:
	var swept: bool = rival_count > 0 and wins == rival_count
	## The RANK — see `wins_needed_to_advance()`. A sweep always clears it; at the final league the
	## two are the same thing on purpose.
	var advanced: bool = rival_count > 0 and wins >= wins_needed_to_advance(idx, rival_count)
	var is_frontier: bool = idx == league_index
	var placement: int = placement_for(wins, rival_count)
	## ⚠️ Read the champion flag BEFORE the sweep marks the league won — `has_beaten_champion()`
	## is derived from `leagues_won`, so asking after would always answer true.
	var first_title: bool = swept and not has_beaten_champion(idx)
	var out := {
		"leagueIndex": idx, "league": league_at(idx).get("name", ""),
		"wins": wins, "rivalCount": rival_count,
		"swept": swept, "promoted": false, "gameWon": false,
		"advanced": advanced,
		"winsNeeded": wins_needed_to_advance(idx, rival_count),
		"placement": placement,
		"placementFraction": placement_reward_fraction(placement),
		"champion": champion_for(idx),
		"championBeaten": swept,
		"firstTitle": first_title,
	}

	## THE TITLE — the whole draw, nothing dropped. Marks the league cleared, so the champion
	## remembers (`champion_fill_for`) and the result screen can say a title changed hands.
	if swept:
		if leagues_won.size() > idx:
			leagues_won[idx] = true
		league_swept.emit(league_at(idx).get("name", ""))

	## THE RANK — the ladder moves on `advanced`, which at the final league IS the sweep.
	if advanced and is_frontier:
		if is_final_league(idx):
			won_game = true
			out["gameWon"] = true
			game_won.emit()
		else:
			var from_name: String = current_league_name()
			league_index += 1
			out["promoted"] = true
			promoted.emit(from_name, current_league_name())

	return out


# ── run economy / clock ──────────────────────────────────────────────────────

func advance_week(n: int = 1) -> void:
	week += maxi(1, n)


func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)


## Returns false (spending nothing) if `amount` exceeds current gold.
func spend_gold(amount: int) -> bool:
	if amount <= 0:
		return true
	if amount > gold:
		return false
	gold -= amount
	return true
