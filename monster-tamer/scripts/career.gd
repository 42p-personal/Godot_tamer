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
	_check_climber_curve()   ## ⚠️ after _load_ladder — `ladder_shape()` needs `leagues.size()`


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
## ⚠️ THE QUALIFIER CEILING IS THE ONE AUTHORED CURVE; THE OPENER IS DERIVED FROM IT.
## It used to be two independent lerps — opener 0.80->0.90 and ceiling 0.95->1.00 — and the SHAPE
## OF A CUP was therefore an accident of four endpoints, exactly like the champion band was. What a
## designer actually wants to say about a draw is two things: how hard its hardest qualifier is,
## and how much the first round ramps up to it. So that is what is authored.
## ⚠️ AND THE TOP CAME UP HARD (1.00 -> 1.20) BECAUSE THE MID-LADDER MEASURED AS A WALKOVER.
## At 1.00 the qualifying rounds of Bronze..Tamer Elite ran at a 0.75-0.92 win rate against the
## climber — a draw you clear by turning up. The old value was set when the field also carried
## `tactics.gd:FILL_MULT` (see `FIELD_KIND_PARITY_APPLIED`) and against a climber table 15-25%
## higher in the mid-game; both of those propped it up, and both are now gone.
const FIELD_QUAL_RATIO_BOTTOM := 0.95     ## the last qualifying round, Wood
const FIELD_QUAL_RATIO_TOP := 1.08        ## the last qualifying round, Tamers Apex

## ⚠️ HOW FAR ROUND ONE SITS BELOW THAT CEILING — AND IT NARROWS UP THE LADDER ON PURPOSE.
## A Wood cup should TEACH: an opener you beat, then a real one, then the titleholder. A Tamers
## Apex cup is an invitational, and there is no such thing as a warm-up round in it. Measured, the
## old constant-width ramp is why the summit's opener sat at a 94-100% win rate while its ADVANCE
## was 15% — the draw was four free rounds and a wall, which is a coin toss with ceremony, not a
## final. Narrowing the ramp is what makes the Apex draw a gauntlet instead.
const FIELD_DRAW_RAMP_BOTTOM := 0.15      ## Wood — round one is well below the last qualifier
const FIELD_DRAW_RAMP_TOP := 0.05         ## Apex — every round in the draw is a title contender
## ── THE CHAMPION BAND — A GAP OVER THE QUALIFIERS, NOT AN INDEPENDENT CURVE ──────────────────
## ⚠️ THIS IS THE FIX FOR THE LADDER'S TWO LARGEST INVERSIONS, AND THE BUG WAS STRUCTURAL RATHER
## THAN NUMERIC. The champion ratio used to be its OWN lerp (0.98 -> 1.02) sitting beside the
## qualifier lerp (0.95 -> 1.00), and nothing in the code related the two. The gap they happened
## to produce was therefore an ACCIDENT of four independently-authored endpoints: +0.03 at Wood,
## +0.02 at Apex — smaller than the depth relief that comes off the qualifiers, so at a deep rung
## the "champion" could and did land BELOW the last team in their own draw. Measured at 96 cups,
## champion p minus that cup's own qualifier mean read
##   Wood -0.05 | Copper -0.02 | Tin -0.40 | Bronze -0.27 | Iron -0.35 | SILVER +0.09 |
##   Gold -0.39 | PLATINUM +0.03 | Masters -0.39 | Elite -0.20 | Apex -0.76
## — and Silver and Platinum, the two rungs with a POSITIVE band (a titleholder easier than their
## own qualifiers), are precisely the two largest ADVANCE inversions in the ladder (Silver 70%
## after Iron 55%; Platinum 58% after Gold 36%).
##
## So the champion is now defined AS the qualifier ceiling plus an authored GAP. Two parameters,
## one shaped function, and the invariant is structural: you cannot author a soft champion without
## authoring a negative gap, and a negative gap is visible on the line that declares it.
##
## WHAT THE GAP EXPRESSES, in design terms: how much MORE the titleholder is than the hardest team
## you had to beat to reach them. Shallow at the bottom, where the ladder is teaching and a rung
## should be a lesson rather than a wall; deepening as it climbs, so the last thing between you and
## the rank becomes progressively more of the test. It is a curve in `ladder_shape`, the same
## non-linear ladder position every other field endpoint is interpolated along.
## ⚠️ AND THE ANCHOR IS THE **RELIEVED** QUALIFIER CEILING — THE HARDEST TEAM ACTUALLY IN THE DRAW,
## NOT THE UNRELIEVED CURVE. This was measured the wrong way round first and the reading is why:
## anchored to the unrelieved ceiling, the EFFECTIVE gap silently became `gap + relief`, so at
## Tamers Apex (depth relief 0.06 + summit relief) the Dynast stood 0.34 above their own draw
## instead of the authored 0.22 and took the champion round to a measured 0% win rate over 32 cups.
## A gap the code computes as "authored gap PLUS whatever relief happens to apply" is the same
## class of accident this whole section exists to remove. `field_fill()` and `champion_fill_for()`
## now share ONE `_qual_ceiling_ratio()`, so the gap is the gap at every rung.
const FIELD_CHAMPION_GAP_BOTTOM := 0.12   ## Wood — the Paddock King is a step, not a wall
const FIELD_CHAMPION_GAP_TOP := 0.18      ## Apex — the Dynast is a different question entirely
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
## ⚠️ RE-TESTED AGAINST THE MEASURED CLIMBER AND IT IS NEEDED MORE, NOT LESS. The brief for this
## round asked whether the relief could come off now the sweep lottery is gone, targeting an Apex
## opener under ~85% without ADVANCE dropping under ~20%. Measured at 64 cups: at 0.08 the opener
## falls only 94% -> 86% while ADVANCE COLLAPSES 17% -> 5% (2.2 -> 21.3 cups for the last rung).
## Both halves of the target fail at once, so the two are not in tension with each other — they are
## both in tension with the relief, and the relief wins. The opener's softness is NOT mainly the
## relief: it is that `FIELD_OPENER_RATIO_TOP = 0.90` sits on a steep transfer curve. If a harder
## Apex opener is wanted, raise that endpoint and pay for it somewhere else; do not take the relief.
## ⚠️ THAT CONSTANT NO LONGER EXISTS — the opener is now DERIVED from the qualifier ceiling by
## `FIELD_DRAW_RAMP_*`, and the paragraph above is kept only as the record of the old reading.
## Its own diagnosis is what pointed at the ramp: the Apex opener was soft because the draw's
## SHAPE was authored once for the whole ladder, not because of the relief.
##
## ⚠️ 0.18 -> 0.09 (round 12). THE READING ABOVE WAS TAKEN WITH THE OLD ACCIDENTAL CHAMPION BAND,
## AND ITS CONCLUSION DOES NOT SURVIVE THE FIX. At the time it was measured, the Apex champion sat
## at a ratio of 1.02 — barely above the qualifier line — so ADVANCE at the summit was carried
## almost entirely by the four qualifying rounds, and taking relief off them was the only term
## moving. That is why both halves of the target failed together: there was nothing else holding
## the rung up. With the champion authored as a real gap over the qualifiers, the Dynast IS the
## rung, which is what `FIELD_APEX_QUAL_RELIEF` was invented to fake. The relief therefore comes
## down to the depth relief every other 5-round rung already gets, plus a small remainder for the
## no-dropped-round rule the summit alone lives under.
## ⚠️ IT IS NOT ZERO, AND THAT IS DELIBERATE. Apex is the one rung whose result is a PRODUCT of
## five win rates with nothing forgiven; at a flat qualifier line its ADVANCE is a fifth power and
## collapses. The residual relief is what pays for the drop rule, not for a weak Dynast.
## ⚠️ AND BACK UP TO 0.19 ONCE THE QUALIFIER CEILING WAS RE-AUTHORED AT 1.20. The two numbers are
## not independent: 0.06 was measured against a 1.00 ceiling. What the summit actually needs is a
## qualifier line around a 0.82 per-round win rate — because 0.82^4 x a 0.40 Dynast is the ~18%
## ADVANCE this rung is authored for — and holding that line while the rest of the ladder's ceiling
## rose 20% means the relief rises with it. Expressed as a RATIO it is now 0.19/1.20 rather than
## 0.18/1.00: proportionally almost unchanged, which is the honest reading of what it was ever
## doing. What DID change is the ramp (`FIELD_DRAW_RAMP_TOP`), which is what makes the Apex opener
## a real round rather than the fourth free one.
const FIELD_APEX_QUAL_RELIEF := 0.09

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
## ⚠️ 0.90 -> 1.00 (round 11). THE RELIEF WAS PAYING FOR A BUG, NOT FOR THE ARCHETYPES. It was
## calibrated against a player built by `_probe_ladder_slope.gd:_player_team`, which calls
## `make_monster` WITHOUT `roster.gd:_shape_to_class` — so that player frequently classified as
## `Generalist`, and `Generalist` had no entry in `data.json:classLines`, so
## `monster_instance.gd:assign_moveset` cleared its kit and rebuilt NOTHING. The eleven-rung
## slope this constant was tuned to was measured against a player carrying no moves at all.
## With that fixed (see `monster_instance.gd:_fallback_lines`) the 0.90 relief was pure surplus:
## the ladder read 75 -> 35 ADVANCE and 15.1 cups for the whole climb, i.e. flat and half price.
## Restoring 1.00 puts it back on 26.8 cups without touching a single per-rung ratio — which is
## the coupling doing its job, and is why this stayed ONE knob.
## ⚠️ 1.00 -> 0.85 (round 12). IT IS NOW ALSO PAYING FOR THE KIND CORRECTION THIS FILE STOPPED
## APPLYING. `FIELD_KIND_PARITY_APPLIED` (below) drops `tactics.gd:FILL_MULT` from the ladder — and
## the early ladder had been quietly ENJOYING that multiplier, because `archetypes_taught_by()`
## starts as `[rushdown]` (0.856) and only reaches an average of 1.0 around Gold. Measured at 32
## cups, turning FILL_MULT off cost Wood 16 points of ADVANCE (66% -> 50%) and Copper 16 (63% ->
## 47%) while the top of the ladder barely moved — exactly the shape of the pool's own mean
## multiplier. So this single global term re-anchors the whole field, which is what it is for: the
## per-rung RATIOS are the difficulty curve and were not re-authored to absorb a units change.
const FIELD_ARCHETYPE_POWER_MULT := 0.85

## ── HOW MUCH OF `tactics.gd:FILL_MULT` THE LADDER APPLIES ─────────────────────────────────────
## ⚠️ THIS IS THE OTHER HALF OF THE CHAMPION-BAND FIX, AND IT IS THE TERM THAT WAS DRIVING THE
## SAWTOOTH ONCE THE GAP WAS AUTHORED. `tactics.gd:FILL_MULT` rescales a kind's fill so the six
## kinds are worth the same — measured by `_probe_archetypes` AGAINST A GENERIC 0.65 BUILD. The
## ladder does not fight a generic 0.65 build; it fights the CLIMBER. Measured at 32 cups per rung
## with the gap authored and FILL_MULT fully applied, the champion round's win rate against the
## climber read:
##   Wood rushdown .856 -> .56 | Copper bulwark 1.000 -> .34 | Tin attrition 1.231 -> .09
##   Bronze zone 1.066 -> .22  | Iron bulwark 1.000 -> .13   | Silver focusfire .769 -> .56
##   Gold control 1.192 -> .00 | Platinum focusfire .769 -> .44 | Masters control 1.192 -> .06
##   Tamer Elite rushdown .856 -> .16 | Apex zone 1.066 -> .00
## r(FILL_MULT, champion win rate) = **-0.81** over eleven rungs, and it is not merely league
## index in disguise: the two `focusfire` champions (.56 at Silver, .44 at Platinum) sit far ABOVE
## rungs whose authored ratio is LOWER (Tin .09, Iron .13). Against the climber, FILL_MULT does not
## equalise the kinds — it OVER-corrects them, by enough to swamp the entire authored difficulty
## curve. That is why Silver and Platinum, the two `focusfire` rungs, were the ladder's two soft
## champions and its two largest ADVANCE inversions.
##
## ⚠️ AND IT IS NOT `tactics.gd`'s NUMBER THAT IS WRONG — IT IS THE ASSUMPTION THAT ONE NUMBER
## ANSWERS BOTH QUESTIONS. "Are the six kinds equal against a generic build" and "are they equal
## against the climber" are different questions with different answers, and `tactics.gd`'s own
## comment already says one knob per question. So the LADDER states how much of that correction it
## applies, in its own file, as an exponent: the field is built at `fill * FILL_MULT^k`.
##   k = 1.0 — the correction in full (what shipped, and what the row above measures)
##   k = 0.0 — kinds neutral on the ladder: a cup round is worth its authored ratio, whatever kind
##             the draw hands it
## ⚠️ THIS ALSO REMOVES A DISCONTINUITY NOBODY AUTHORED. `make_cup_field()` draws each qualifying
## round's kind from `archetypes_taught_by(idx)`, a pool that GROWS at five rungs — so under k=1
## the mean difficulty of a rung's qualifiers stepped every time the pool's kind-mix changed.
## ⚠️ RE-DERIVE IT WITH `_probe_ladder_slope.tscn` SECTION 1b, NEVER BY REASONING. If a future
## change to `tactics.gd:FILL_MULT` re-calibrates it against the climber, this goes back toward 1.0
## and the champion band must be re-read.
##
## ⚠️⚠️ ROUND-12 INTEGRATION — `r = -0.81` ABOVE IS A CONFOUNDED READING, AND THE HONEST ONE IS
## WORSE FOR `FILL_MULT`, NOT BETTER. That correlation was taken over ELEVEN CHAMPION ROUNDS, one
## per rung — so "which kind" is perfectly confounded with "which rung", and every rung differs in
## fill, round depth, cap and team size. Measured properly by `_probe_sawtooth.tscn -- --kinds`
## §7 (all six kinds fought at EVERY rung's own qualifier fill, 6,288 fights, k=0 so each kind is
## built at its plain authored fill), the win rate against the climber is:
##                rushdown bulwark attrition focusfire control  zone   spread
##   POOLED         57%      78%      78%       73%      59%     77%     20
##   worst rung (Tin)  78%   84%      47%       72%       9%     81%     75
## r(FILL_MULT, pooled win rate) = **+0.15**. Not anti-correlated — UNCORRELATED. `FILL_MULT` is
## not over-correcting the kinds against the climber, it is not correcting them at all, and it
## leaves a 20-point pooled spread (75 points at Tin) that no authored ratio can see. Two of its
## six values have the wrong sign outright: `attrition` is priced 1.231 (the WEAKEST kind, needing
## 23% more fill) and measures joint-strongest at 78%; `rushdown` is priced 0.856 (strong) and
## measures weakest at 57%.
## ⚠️ SO K=0 IS THE RIGHT SETTING AND FOR A BETTER REASON THAN IT WAS SET. Applying a multiplier
## that is uncorrelated with strength adds variance to the field and removes none. It stays at 0.0
## until `tactics.gd:FILL_MULT` is re-derived from the §7 table above — and when it is, the six
## values should come from THAT instrument, at the rung's own qualifier fill, never from a fight
## against a generic 0.65 build.
const FIELD_KIND_PARITY_APPLIED := 0.0

## ── WHAT THESE CONSTANTS ACTUALLY PRODUCE ──────────────────────────────────────────
## ⚠️ ONE CURRENT TABLE, DATED, AND EVERY SUPERSEDED ROW MARKED AS HISTORY. This block used to
## print one row and call it "MONOTONE (0 inversions at n=96)" while a DIFFERENT row four lines
## above it carried five inversions, because each round appended its reading instead of replacing
## it. Rows from different rounds describe different players AND different fields; they are not
## comparable, and stacking them is how this file came to contradict itself. Replace the CURRENT
## table when you re-measure; move the old one under HISTORY with its date and its build.
##
## ── CURRENT — 2026-08-09, round 12 ───────────────────────────────────────────────
## `scenes/_probe_ladder_slope.tscn -- --seeds 96`, 96 cups per rung against the AUTHORED climber
## curve. ADVANCE is the promotion rule; TITLE is the clean sweep; "cups" is 1/ADVANCE.
## BAND is champion win rate minus that cup's own qualifier mean — section 1b of the probe.
##
##   league       Wood Copp  Tin Bron Iron Silv Gold Plat Mast Elit Apex
##   fill          .55  .47  .45  .43  .42  .41  .40  .39  .38  .38  .37
##   ADVANCE %      66   79   45   69   65   58   42   23   34   19   13
##   TITLE   %      33   38    4   13   13   14    9    4    5    1   13
##   BAND         -.14 -.11 -.47 -.39 -.42 -.48 -.45 -.46 -.43 -.55 -.54
##   cups         1.5  1.3  2.2  1.5  1.5  1.7  2.4  4.4  2.9  5.3  8.0   = 32.7 for the climb
##
## WHAT IS FIXED: **0 of 11 rungs has a champion easier than its own qualifiers** (was 2 — Silver
## +0.09 and Platinum +0.03), the band is negative everywhere and deepens up the ladder as designed,
## Apex is no longer a binary gate (opener 94% -> 85%, qualifier mean 0.95 -> 0.82), and no rung is
## unclearable. Wood -> Apex reads 66% -> 13%.
##
## ⚠️ WHAT IS **NOT** FIXED, STATED PLAINLY: INVERSION MASS IS 49.0 AGAINST A PRE-CHANGE 54.7.
## The champion band was the diagnosed cause of the sawtooth and fixing it did NOT remove the
## sawtooth. Three up-steps remain and none of them is a champion-band inversion:
##   Copper 79 after Wood 66 (+14) — the long-standing soft rung; it read 78 after 68 before this
##       round too. Wood is documented as structurally untunable from this file (`FIELD_SHAPE_EXP`)
##       and Copper is the next-smallest dynamic range on the ladder.
##   Bronze 69 after Tin 45 (+24) — this is TIN COLLAPSING, not Bronze rising. Tin's champion round
##       measures p=0.13 where its neighbours read 0.30-0.34, and Tin is the `attrition` rung.
##   Masters 34 after Platinum 23 (+11) — Platinum's champion is `focusfire` (p=0.20), Masters'
##       is `control` (p=0.23), and Platinum's own draw is internally non-monotone (p[2]=0.49
##       against p[3]=0.65) because qualifying kinds are drawn at random from the taught pool.
## Every one of those is the ARCHETYPE KIND term, not the difficulty curve. See
## `FIELD_KIND_PARITY_APPLIED` — the ladder now applies NONE of `tactics.gd:FILL_MULT`, and the
## remaining spread is the kinds' RAW power difference against the climber, which no constant in
## this file can address. The handover note carries the recalibration brief for `tactics.gd`.
##
## ⚠️ AND THE CUP TOTAL ROSE, 26.8 -> 32.7. That is not comparable either (different player model,
## different field), but it is above the 25-28 the brief asked for and Platinum/Tamer Elite/Apex
## carry most of it (4.4 / 5.3 / 8.0). Apex at 13% ADVANCE sits just under the 15-20% target.
##
## ── HISTORY — NOT COMPARABLE TO THE ABOVE OR TO EACH OTHER ───────────────────────────
## Each row is a different (player model, field) pair. Quoting one against another is the error
## this block exists to stop.
##   round 12, pre-change (the baseline this round improved on), n=96, measured climber table,
##       accidental champion band:  68 78 66 46 55 70 36 58 33 35 15  — 26.8 cups,
##       5 inversions, INVERSION MASS 54.7, champions SOFT at Silver (+0.09) and Platinum (+0.03)
##   round 10/11, n=96, player whose kit was silently empty when it classified as `Generalist`:
##                                  66 72 72 56 60 68 46 42 26 32 15  — 26.7 cups
##   round 10, n=32, ANALYTIC climber model (a player that does not exist):
##                                  63 81 72 59 59 53 44 38 25 31 28
##
## ⚠️ AND MIND THE SAMPLE SIZE BEFORE CHASING A WOBBLE. A proportion at n=32 carries about ±9
## points and this file's verdict line counts INVERSIONS, so n=32 can manufacture one: the same
## build read Masters 38 / Tamer Elite 22 at n=32 and Masters 34 / Tamer Elite 19 at n=96.
## `-- --seeds N` exists for exactly this; use it before tuning.

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
## ⚠️ THE MODEL IS NO LONGER A FORMULA. IT IS A MEASURED TABLE, AND THE FORMULA IS RETIRED.
## What used to live here — `CLIMBER_BASE_STAT + CLIMBER_PTS_PER_WEEK * (CLIMBER_WEEKS_PER_RUNG *
## idx + warmup) / 6`, divided by the cap — was this file's largest known inaccuracy, and both of
## its inputs are now known to be fiction against the current build: `_probe_gold_wall.tscn`
## measures 60-70 weeks per rung (not 29) and an EFFECTIVE ~7.3 points per monster-CALENDAR-week
## (not 12.97) once rest, excursion and the 26% of the calendar spent travelling are counted. The
## two errors point in opposite directions, which is exactly why the formula looked plausible for
## six rungs and then diverged: it read 0.56 at Gold where the arc measures 0.48, and 0.61 at Apex
## where a career that actually REACHES Apex measures 0.43.
##
## ⚠️ AND THE ANALYTIC FIX IS BANNED, BECAUSE IT WAS TRIED AND IT FAILED. Round 10 added per-body
## join weeks (`teamSizeByLeague` puts a fresh ~23-per-stat recruit on the sheet at Copper, Bronze,
## Silver and Platinum) and a 26% road tax to the same formula; expected fill fell to 0.22-0.31
## against an arc independently measuring 0.44-0.67, the field came down with it, and the slope
## instrument reported 100% ADVANCE at ten of eleven rungs. Do not re-attempt it. A player model
## assembled from first principles is a theory; `fill@exit` is an observation.
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
## ⚠️⚠️ AND AS OF ROUND 12 THE TABLE BELOW IS AUTHORED, NOT MEASURED. THE MEASUREMENT NOW
## VALIDATES IT INSTEAD OF DEFINING IT, AND THIS IS THE SINGLE MOST CONSEQUENTIAL DECISION IN THIS
## FILE. Read the argument before changing it back.
##
## The old rule was "measure the autopilot's fill@exit, paste it here, price the field as a ratio
## to it". Its failure is not hypothetical — it has now happened twice in three rounds:
##   round 10 table (measured):  .49 .44 .49 .59 .53 .50 .48 .44 .44 .42 .43
##   round 12 re-measure (same instrument, same policy, `-- --arc-table`, n=5 per cell):
##                               .57 .36 .47 .46 .38 .38 .39 .36 .38 .38 .39
## Nothing about the ladder's DESIGN changed between those two rows. What changed was the
## autopilot's world (potential applied, kits re-drafted, the barn affordable, the bench reachable)
## — so it now climbs FASTER with a BIGGER, YOUNGER roster, and a faster climber carries LESS of
## each rung's ceiling when it leaves. Because every `FIELD_*_RATIO_*` is a ratio to this table,
## that re-authored the absolute difficulty of eight of eleven rungs by up to 22% (Bronze .59 ->
## .46) with nobody deciding anything. A difficulty curve that re-shapes itself whenever the QA
## autopilot is improved is not a difficulty curve; it is a side effect.
##
## ⚠️ AND THE ARTEFACTS GET BAKED IN PERMANENTLY. The Copper cell measures .36 against Wood's .57
## — a 21-point cliff that is pure roster mechanics (`teamSizeByLeague` puts a fresh ~23-per-stat
## recruit on the sheet at Copper) sampled on five seeds. Priced literally, Copper's whole field
## drops 21% relative to Wood's because of when a body joins. That is not a statement anyone made
## about how hard Copper should be.
##
## SO: the table is a SMOOTH AUTHORED CURVE with two parameters, and the measured row is kept
## below it as the validation record. The design statement it makes is one sentence: **the cap
## outruns the trainer — steeply as the team grows out of Wood, then slowly forever.** That is
## exactly the shape the measurement shows once its two roster-mechanics wobbles are removed, and
## it is a claim that survives the next autopilot change.
##
## ⚠️ WHAT VALIDATION MEANS HERE, SO IT DOES NOT ROT INTO A RITUAL. Re-run `-- --arc-table` after
## any training/economy/team-size change and compare it to the row below. Agreement inside ~0.05
## per rung = the authored curve still describes the player, change nothing. A SYSTEMATIC gap
## (every rung off in the same direction) = move an ENDPOINT, one at a time, and re-run the slope.
## A gap at ONE rung = investigate that rung; do NOT put a bump in the curve.
##
## ── the historical record: what has been MEASURED, and when ───────────────────────────────────
## ⚠️ THESE ROWS ARE NOT COMPARABLE TO EACH OTHER. Each describes a different autopilot on a
## different build, and quoting one against another is how this file accumulated a comment that
## contradicted itself. They are kept only so a future re-measure can see the direction of drift.
##   2026-08-08, round 10, "competent" policy, n=5 (n=3 at the top two rungs), 3 of 5 seeds
##       reached Apex:               .49 .44 .49 .59 .53 .50 .48 .44 .44 .42 .43   [SUPERSEDED]
##   2026-08-09, round 12, BEFORE this round's field changes, "competent", n=5 at every rung,
##       5 of 5 seeds reached Apex:  .57 .36 .47 .46 .38 .38 .39 .36 .38 .38 .39
##       control policy, same run:   .59 .28 .53 .58 .51 .48 .46 .44 .45 .45 .39
##       (control reached [8,7,7,10,7] — it no longer stalls at Silver, so its column is no
##        longer the fabricated-row hazard it was. It is still not the player the game intends.)
##   2026-08-09, round 12, AFTER this round's field changes — THE VALIDATION RUN:
##       competent, 5/5 seeds to Apex: .57 .46 .46 .41 .35 .35 .38 .39 .38 .40 .39   [CURRENT]
##       control,   5/5 seeds to Apex: .53 .44 .46 .41 .42 .41 .40 .41 .37 .39 .38
##       authored curve (what ships):  .55 .47 .45 .43 .42 .41 .40 .39 .38 .38 .37
## ⚠️ THE AUTHORED CURVE IS WITHIN 0.02 OF THE COMPETENT MEASUREMENT AT NINE OF ELEVEN RUNGS (worst
## 0.07, at Iron and Silver), and within 0.02 of the CONTROL column at ten of eleven. Two players
## measured independently, both landing on the authored line: that is the validation the decision
## above was betting on, and it came in.
## ⚠️ AND THE COPPER CLIFF DID NOT REPRODUCE. The pre-change run measured Copper at .36 and Wood at
## .57 — the 21-point drop that a MEASURED table would have baked into the difficulty curve
## permanently. Re-measured after the change it reads .46. It was sampling, not a property of the
## game. That single cell is the whole argument for authoring the curve, and it is why the row
## above says "measured .36" beside a shipped 0.47 rather than the other way round.
## ⚠️⚠️ ROUND-12 INTEGRATION: THE VALIDATION ABOVE WAS RUN AGAINST A SUBSIDISED PLAYER, AND HAS
## BEEN RE-RUN AGAINST A REAL ONE. `_probe_ladder_slope.gd:_arc_fills("policy_all")` — the column
## labelled "competent" in every row above — also set `v_free_bodies = true` and passed
## `{"feeMult": 0.0}`: free recruits, free barn slots, free breeding and no cup entry fee. Measured
## at 8 seeds on the round-11 ship ladder, the SAME policy completes 2/8 careers at full price
## against 8/8 subsidised. That seam is now closed (the column pays full price) and the curve was
## re-validated on 2026-08-09 by the integrator:
##       competent AT FULL PRICE, n=5:  .54 .41 .46 .39 .38 .38 .35 .39 .38 .40 .39
##       and independently, `_probe_career_arc.gd --policies --seeds 8`, COMPETENT:
##                                      .54 .41 .47 .40 .39 .39 .36 .40 .39 .40 .39
##       authored curve (what ships):   .55 .47 .45 .43 .42 .41 .40 .39 .38 .38 .37
## Two instruments, two seed sets, agreeing to 0.01 at every rung: the measurement is solid.
## ⚠️ AND IT SAYS THE CURVE IS ~0.04 HIGH THROUGH THE MID-LADDER. Copper +0.06, Bronze +0.04,
## Iron +0.04, Gold +0.05; Platinum..Apex agree to 0.02. The authored line is right at both ends
## and bows above the real player in the middle, so Copper..Gold are currently fielding a team
## built for a climber ~10% richer than the one that actually arrives. DO NOT put a bump in the
## curve to fix it — that is exactly what authoring it was for. `CLIMBER_FILL_WOOD` is right;
## the shape between the endpoints (`ladder_shape`'s exponent) is what is wrong.
## ⚠️ THE SUCCESSION CANARY WAS ASKING THE WRONG QUESTION and has been rewritten rather than
## fixed. It fired on all five seeds ("bought no successor") because `_grow_successor()` returns
## early when a spare already exists, and round 11's four-wire fix made the arc's MAINLINE recruit
## `team_need + BENCH_SIZE`. Succession is REDUNDANT, not inert. The canary now asserts
## `benchWeeks > 0` — that trained cover exists at all — and fails the run when it does not.
##
## ── the curve ─────────────────────────────────────────────────────────────────────────────────
## fill(idx) = lerp(CLIMBER_FILL_WOOD, CLIMBER_FILL_APEX, ladder_shape(idx))
## `ladder_shape` is the SAME non-linear ladder position every field endpoint uses, so the climber
## and the field it faces bend on one curve rather than two.
const CLIMBER_FILL_WOOD := 0.55   ## one monster, a cap of 100, base stats already at ~23
const CLIMBER_FILL_APEX := 0.37   ## five monsters, a cap of 1100, a career's worth of weeks
##
## ⚠️ THE OLD PROSE BELOW IS THE MEASURED ERA'S REASONING AND IS RETAINED BECAUSE ITS FINDINGS ARE
## STILL TRUE — the team-size dilution, the road tax, and why the ANALYTIC model was banned. Only
## its conclusion ("so the table is the measurement") is superseded.
## ⚠️ SO THE TABLE BELOW WAS THE MEASUREMENT, AND EVERY CELL IN IT HAD A SAMPLE COUNT.
## Source: `scenes/_probe_ladder_slope.tscn -- --arc-table`, §5. It runs the autopilot
## (`_probe_career_arc.gd`, via the ONE existing subclass in `_probe_gold_wall.gd` — no third copy
## of the career loop) over five seeds and records, per rung, the fraction of THAT rung's ceiling
## the roster carried when it left the rung. Re-run it after any training, economy or team-size
## change; it takes about a minute for ten arcs.
##
## ⚠️ WHICH CLIMBER — AND THIS IS A DESIGN DECISION, NOT A MEASUREMENT. Two were measured:
##
##   league        control fill@exit (n)     competent fill@exit (n)
##   Wood            0.57  [0.57-0.57] (5)     0.49  [0.49-0.49] (5)
##   Copper          0.54  [0.53-0.57] (5)     0.44  [0.44-0.44] (5)
##   Tin             0.67  [0.65-0.69] (5)     0.49  [0.49-0.49] (5)
##   Bronze          0.68  [0.60-0.75] (5)     0.59  [0.54-0.64] (5)
##   Iron            0.61  [0.44-0.77] (5)     0.53  [0.50-0.56] (5)
##   Silver          0.55  [0.52-0.61] (3)     0.50  [0.48-0.52] (5)
##   Gold            0.48  [0.43-0.53] (2)     0.48  [0.41-0.53] (5)
##   Platinum        0.38  [0.38-0.38] (1)     0.44  [0.39-0.48] (5)
##   Masters            —      (0)             0.44  [0.42-0.45] (5)
##   Tamer Elite        —      (0)             0.42  [0.38-0.45] (3)
##   Tamers Apex        —      (0)             0.43  [0.42-0.45] (3)
##
## CONTROL is the autopilot exactly as it plays today. It stalls — five seeds reach
## [6,4,7,4,5], median Silver — so it has ONE sample at Platinum and NONE above it. A table built
## from that column would have four fabricated rows, and a fabricated row is worse than a formula
## because it looks measured.
## COMPETENT is the same autopilot with the stable half played properly (succession, an affordable
## barn, no entry fee, shaped training, a re-drafted kit — the round-11 diagnostician's "everything
## at once"). It reaches [10,10,10,8,8]: three seeds clear Tamers Apex, so every rung has samples.
## The field is priced against COMPETENT because that is the player the game is being built to
## produce, and because it is the only column that can honestly fill the top of the ladder.
##
## ⚠️ SAMPLE COUNTS, STATED SO NOBODY QUOTES A THIN CELL AS A FACT. Wood..Masters rest on 5 arcs
## each; Tamer Elite and Tamers Apex rest on 3 (only three seeds got there). NOTHING in this table
## is extrapolated — if a future run leaves a rung at n=0, author it as the neighbour's value and
## say so on the line, do not interpolate silently.
##
## ⚠️ IT IS NOT MONOTONE, AND THAT IS REAL. Bronze (0.59) is a genuine bump: the arc lingers there
## on a 400 cap with a 3-body team before Silver's fourth mouth dilutes it, and the same shape
## appears in the control column (0.68) at twice the sample. It is not smoothed, because smoothing
## a measurement is how a measurement becomes an assumption.
##
## ⚠️ AND THE COUPLING IS THE WHOLE POINT: every `FIELD_*_RATIO_*` is a ratio TO this number, so
## correcting it re-anchors the absolute fills WITHOUT re-tuning any difficulty ratio. The field
## moves with the player. If the slope changes after a re-measure, re-tune the FIELD, never this.
##
## ⚠️ THE ARRAY BELOW IS THE CURVE, SAMPLED — NOT ELEVEN VALUES. It is stored as an array for one
## reason: `scripts/_probe_sawtooth.gd` reads `Career.CLIMBER_FILL_BY_LEAGUE` by name to run its
## counterfactual, and that file is not this workstream's to edit. `_check_climber_curve()` asserts
## at boot that every cell still equals `lerp(CLIMBER_FILL_WOOD, CLIMBER_FILL_APEX,
## ladder_shape(i))` to 0.005 and push_error()s if a hand-edit has drifted from the curve. EDIT THE
## TWO ENDPOINTS AND RE-SAMPLE; do not tune a cell.
const CLIMBER_FILL_BY_LEAGUE: Array = [
	0.55,  ## Wood         (measured .57)
	0.47,  ## Copper       (measured .36 — a roster-mechanics cliff, deliberately NOT baked in)
	0.45,  ## Tin          (measured .47)
	0.43,  ## Bronze       (measured .46)
	0.42,  ## Iron         (measured .38)
	0.41,  ## Silver       (measured .38)
	0.40,  ## Gold         (measured .39)
	0.39,  ## Platinum     (measured .36)
	0.38,  ## Masters      (measured .38)
	0.38,  ## Tamer Elite  (measured .38)
	0.37,  ## Tamers Apex  (measured .39)
]


## ⚠️ A GUARD, NOT A TEST — because the whole point of an authored curve is that nobody can quietly
## turn it back into eleven hand-tuned numbers. Fires once at boot; costs nothing.
func _check_climber_curve() -> void:
	for i in range(CLIMBER_FILL_BY_LEAGUE.size()):
		var want: float = lerpf(CLIMBER_FILL_WOOD, CLIMBER_FILL_APEX, ladder_shape(i))
		if absf(float(CLIMBER_FILL_BY_LEAGUE[i]) - want) > 0.005:
			push_error(("Career: CLIMBER_FILL_BY_LEAGUE[%d] = %.3f has drifted from the authored "
				% [i, float(CLIMBER_FILL_BY_LEAGUE[i])])
				+ "curve (%.3f). Edit CLIMBER_FILL_WOOD/APEX and re-sample, never a cell." % want)


## The fraction of rung `idx`'s ceiling the climbing player can be expected to carry. A LOOKUP into
## the sampled curve — see the block above. Falls back to the nearest authored rung if the ladder
## is ever lengthened, and says so in the console rather than inventing a value.
func expected_climber_fill(idx: int) -> float:
	if CLIMBER_FILL_BY_LEAGUE.is_empty():
		return 0.45
	var i: int = clampi(idx, 0, CLIMBER_FILL_BY_LEAGUE.size() - 1)
	if idx != i:
		push_warning("Career: no measured climber fill for league %d — clamped to rung %d. "
			% [idx, i] + "Re-run `_probe_ladder_slope.tscn -- --arc-table`.")
	return clampf(float(CLIMBER_FILL_BY_LEAGUE[i]), 0.05, 1.0)


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
		return clampf(champion_fill_for(league, r), 0.05, 0.98)
	var opener: float = _opener_ratio(league, r)
	var qual_top: float = _qual_ceiling_ratio(league, r)
	# `r - 1` qualifying rounds, indices 0 .. r-2. With only one qualifier it IS the opener.
	var t: float = 0.0 if r <= 2 else clampf(float(round_idx) / float(r - 2), 0.0, 1.0)
	return clampf(lerpf(opener, qual_top, t) * expected_climber_fill(league), 0.05, 0.98)


## How much the qualifying rounds of an `r`-round draw at `idx` come down. See
## `FIELD_DEPTH_RELIEF_PER_ROUND` and `FIELD_APEX_QUAL_RELIEF`.
func _qual_relief(idx: int, rounds: int) -> float:
	var relief: float = float(maxi(0, maxi(1, rounds) - 3)) * FIELD_DEPTH_RELIEF_PER_ROUND
	if is_final_league(idx):
		relief += FIELD_APEX_QUAL_RELIEF
	return relief


func _opener_ratio(idx: int, rounds: int) -> float:
	return _qual_ceiling_ratio(idx, rounds) \
		- lerpf(FIELD_DRAW_RAMP_BOTTOM, FIELD_DRAW_RAMP_TOP, ladder_shape(idx))


## THE HARDEST TEAM IN THE DRAW THAT IS NOT THE TITLEHOLDER — the champion's anchor.
## ⚠️ ONE FUNCTION, TWO CALLERS, DELIBERATELY. The champion used to be an independent lerp beside
## this one and the gap between them was whatever four unrelated endpoints happened to produce.
func _qual_ceiling_ratio(idx: int, rounds: int) -> float:
	return lerpf(FIELD_QUAL_RATIO_BOTTOM, FIELD_QUAL_RATIO_TOP, ladder_shape(idx)) \
		- _qual_relief(idx, rounds)


## The champion's ratio to the expected climber: the draw's own ceiling, plus the authored gap.
## Public because the scouting screen and every instrument should read the gap rather than infer it.
func champion_gap(idx: int) -> float:
	return lerpf(FIELD_CHAMPION_GAP_BOTTOM, FIELD_CHAMPION_GAP_TOP, ladder_shape(idx))


func champion_ratio_for(idx: int, rounds: int = -1) -> float:
	var r: int = rounds if rounds > 0 else rival_count_for_league(idx)
	return _qual_ceiling_ratio(idx, r) + champion_gap(idx)


## ⚠️ THE CHAMPION REMEMBERS — within the limits of what the save file actually carries.
## `leagues_won[idx]` is persisted (`save_game.gd`), so "have you taken this title off them
## before" survives a reload and is the one piece of history this can honestly stand on: come
## back to a league you already cleared and its champion has spent the interval training.
## A per-session grudge counter would NOT survive a save/load — `save_game.gd` is not this
## workstream's file and serialises a fixed field list — so the escalation is derived from saved
## state rather than stored, deliberately.
func champion_fill_for(idx: int, rounds: int = -1) -> float:
	var beaten: bool = idx >= 0 and idx < leagues_won.size() and bool(leagues_won[idx])
	var base: float = champion_ratio_for(idx, rounds) * expected_climber_fill(idx)
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
		## ⚠️ UNDO `(1 - k)` OF `tactics.gd:FILL_MULT` BEFORE THE GENERATOR APPLIES IT. `roster.gd:
		## make_rival_team` multiplies by `Tactics.archetype_fill(gid, fill)`, so passing
		## `fill / m^(1-k)` lands the team at `fill * m^k`. The multiplier is READ from
		## `archetype_fill(gid, 1.0)` rather than copied out of `FILL_MULT` — a second copy of that
		## table is precisely this project's most expensive recurring bug.
		## See `FIELD_KIND_PARITY_APPLIED` for the measurement that forced this.
		var m: float = maxf(0.01, TacticsScript.archetype_fill(archetype, 1.0))
		use_fill /= pow(m, 1.0 - FIELD_KIND_PARITY_APPLIED)
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
