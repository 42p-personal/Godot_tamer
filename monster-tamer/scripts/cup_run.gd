## THE CUP RUN — live per-round state for a tournament in progress, carried across the scene
## changes a real cup now spans: tactics.tscn (orders) -> arena3d.tscn (the fight) -> tactics.tscn
## (next opponent) -> ... -> tournament.tscn (final standings + purse). Autoload rather than a
## static handoff like `Tactics.committed`/`ReportScript.pending` because those are single-shot
## (fill it, drain it once); a cup needs mutable state that SURVIVES several rounds — which round
## we're on, the pre-generated rival team for each round, the running win count.
##
## Wires `stable_ui.gd -> tournament.tscn -> tactics.tscn -> arena3d.tscn` into an actual loop —
## before this, "Enter the Cup" ran `career.gd:enter_league_tournament()`'s three fights headless,
## in one frame, and the player only ever saw a scoreboard. CLAUDE.md: "The player never
## intervenes in a fight. They decide their tactics and then watch how those tactics unfold."
##
## ⚠️ DOES NOT OWN THE PROMOTION RULE. `Career.apply_tournament_outcome()` is the single source of
## truth for what a win count means (sweep/promote/win-the-game) — this script only counts wins
## round by round and hands the final tally to that function once, in `finish()`. Preserves
## `career.gd:enter_league_tournament()`'s outcomes exactly: both paths call the same tail.
extends Node

var active: bool = false
var league_idx: int = -1
var team_size: int = 0
var rival_count: int = 0
var current_round: int = 0          # 0-based
var rival_teams: Array = []         # Array[Array[MonsterInstance]] — one pre-built team per round
## The drawn field, one entry per round: {"team", "fill", "champion", "label"} — see
## `career.gd:make_cup_field()`. `rival_teams` is the team column of this, kept as its own array
## because every existing caller (tactics_ui, arena_3d, the probes) indexes teams directly.
var field: Array = []
var wins: int = 0
var round_results: Array = []       # Array[bool] — this run's per-round win/loss, in order
var before_league_name: String = "" # league name at the moment this cup was entered (pre-promotion)

## Set once by `finish()`; `tournament_ui.gd` reads it on `_ready()` to render the cup's final
## card and pay the purse, then clears it — same drain-once pattern as `ReportScript.pending`.
var last_result: Dictionary = {}

## Weeks of game time this run actually charged (0 until `travel()` runs). Read by
## `tournament_ui.gd` for the result card.
var weeks_spent: int = 0
## True when this run is the league's once-a-year marquee — a deeper field and a fatter purse.
var marquee: bool = false


# ── THE COST OF TIME ─────────────────────────────────────────────────────────
## ⚠️ A CUP USED TO COST NOTHING BUT A CLICK, AND THAT BROKE THE WHOLE STABLE HALF.
## `docs/META_GAME_REVIEW.md` finding **E2**, measured: *"a Wood-capped monster entered the Wood
## cup ten times back to back for +1,100g while the clock moved 0 weeks. Nothing on the cup path
## touches `Career.week`."* So the one activity the game is about bypassed the weekly tick
## entirely — no training, no ageing, no food bill, no price reroll — and gold per week of game
## time was infinite by construction. Time is the scarcity everything else in the stable half is
## priced against; an activity that is free of it is outside the economy.
##
## A cup is now a JOURNEY: you travel, you compete, you come home, and the stable ages while you
## are away. `travel()` runs the REAL weekly tick (`WeekPlan.advance`), so those weeks are ordinary
## weeks in every respect except that nobody trains on the road.
##
## ⚠️ DELIBERATELY THE SMALL END OF THE RANGE, AND HERE IS THE ARITHMETIC THAT DECIDED IT. The
## measured winning career enters **88 cups** (`META_GAME_REVIEW.md` §2) because promotion is a
## sweep — a ~12% lottery (**L1**). Any per-cup charge is therefore multiplied by 88, and the
## review's own warning is explicit: *"making a cup cost a week while promotion is still a 12%
## lottery would turn a 319-week career into a 1,000-week one."* One week per ROUND would have
## added 349 weeks; one flat week plus one for the five-team circuits adds **117**, taking the
## measured arc from 319 to ~436 — past a monster's 336-week career, so turnover starts to exist
## (finding **G2**: a winning career currently records zero retirements) without putting the win
## out of reach. Re-tune UPWARD once promotion stops being `w^n`, not before.
const TRAVEL_WEEKS_BASE := 1        ## the meet itself — every cup, every rung
const TRAVEL_WEEKS_BIG_FIELD := 1   ## the five-team circuits are a longer trip
const BIG_FIELD_ROUNDS := 5


## What a cup at `idx` costs in game time, before it is entered. Public and model-layer on
## purpose: `docs/META_GAME_REVIEW.md` finding **E1** is that the economy lives in UI scripts
## where nothing headless can read it, and the fix is not to add another one.
func weeks_for_cup(idx: int, rounds: int = -1) -> int:
	var n: int = rounds if rounds > 0 else rounds_for(idx)
	return TRAVEL_WEEKS_BASE + (TRAVEL_WEEKS_BIG_FIELD if n >= BIG_FIELD_ROUNDS else 0)


## Spend the trip. Runs the real tick so ageing, the food bill, stamina, the freezer's rent and
## the price reroll all happen — a travel week is an ordinary week you did not get to train.
##
## ⚠️ THE PLAYER'S TRAINING PLAN SURVIVES THE TRIP. `WeekPlan.advance()` clears `plans` as it
## spends them; a cup that silently ate the drills the player set up in the Stable would be a
## week stolen, not a week spent. The plan is stashed and restored, so the road is a REST week
## (and an unfed one — that is the cost) and the plan is still there when you get home.
func travel() -> int:
	var n: int = weeks_for_cup(league_idx, rival_count)
	weeks_spent = n
	if n <= 0 or not has_node("/root/Career"):
		return 0
	var wp := get_node_or_null("/root/WeekPlan")
	if wp == null or not has_node("/root/Roster") or Roster.monsters.is_empty():
		Career.advance_week(n)
		return n
	var stashed: Dictionary = wp.plans.duplicate(true)
	wp.plans = {}
	for i in range(n):
		wp.advance(Roster.monsters)
	wp.plans = stashed
	return n


# ── THE MARQUEE ──────────────────────────────────────────────────────────────
## ⚠️ THE ORIGINAL HAD A CALENDAR AND THIS BUILD HAS A QUEUE. `town.ts` drew a seeded annual
## calendar — every league guaranteed a cup per quarter, Masters/Elite at half density, and **one
## prestige marquee event per year** for Silver through Tamer Elite. None of it crossed
## (`META_GAME_REVIEW.md` §4). A full calendar is a bigger change than this workstream owns; the
## marquee is the part that pays for itself immediately, because it is the only thing in the build
## that makes one week's cup different from another week's cup.
##
## Once a game-year, at each of the five senior leagues, the cup is THE event: one extra team in
## the draw, double entry, and a purse worth the trip. It is a genuine choice rather than a bonus —
## a deeper field means a longer sweep, so the marquee is easier to place in and harder to win.
##
## ⚠️ SEEDED AND CHECKABLE BEFORE ENTRY. The month is a pure hash of league name and year, so the
## sign-up screen can bill it, it never moves under the player, and it survives a save/load with
## no new persisted state.
const MARQUEE_LEAGUES := {
	"Silver": "The Silver Assay",
	"Gold": "The Gilt Chain",
	"Platinum": "The White Circuit",
	"Masters": "The Masters' Round",
	"Tamer Elite": "The Elite Convocation",
}
const MARQUEE_EXTRA_ROUNDS := 1
const MARQUEE_PURSE_MULT := 1.75
const MARQUEE_FEE_MULT := 2.0
const WEEKS_PER_MONTH := 4
const MONTHS_PER_YEAR := 13   ## 52 weeks / 4 — the same window the cup FIELD is drawn in


func marquee_name(idx: int) -> String:
	return str(MARQUEE_LEAGUES.get(str(Career.league_at(idx).get("name", "")), ""))


## Which month of the current game-year this league's marquee falls in. Deterministic.
func marquee_month(idx: int) -> int:
	var lname: String = str(Career.league_at(idx).get("name", ""))
	var year: int = int(Career.week) / (WEEKS_PER_MONTH * MONTHS_PER_YEAR)
	return absi(hash("marquee:%s:%d" % [lname, year])) % MONTHS_PER_YEAR


## Is the cup at `idx` the marquee THIS month?
func is_marquee(idx: int) -> bool:
	if marquee_name(idx) == "":
		return false
	var into_year: int = int(Career.week) % (WEEKS_PER_MONTH * MONTHS_PER_YEAR)
	return int(into_year / WEEKS_PER_MONTH) == marquee_month(idx)


## How many rounds the cup at `idx` fields right now — the league's own field, plus the marquee's
## extra team when the marquee is in town.
func rounds_for(idx: int) -> int:
	var n: int = Career.rival_count_for_league(idx)
	return n + (MARQUEE_EXTRA_ROUNDS if is_marquee(idx) else 0)


# ── THE SHAPE OF THE DRAW ────────────────────────────────────────────────────
## ⚠️ ROUND ONE WAS FREE AT ALL ELEVEN RUNGS, SO A THREE-ROUND CUP WAS A ONE-ROUND CUP.
## Measured with `_probe_career_arc.tscn -- --gate-only` against a 65%-filled roster (the fill a
## real winning roster actually reaches): the opener won **100% at every league**, and the sweep
## column tracked the CHAMPION column within noise at every league — Wood 63/75, Tin 25/38,
## Silver 63/75. Every round before the last contributed nothing to the outcome; the whole cup
## lived in its final fight and the rest was a formality the player still had to sit through.
##
## Why it happened: `career.gd:field_fill()` interpolates LINEARLY from a deliberately soft opener
## (0.28 of the league ceiling at Wood, 0.50 at Apex) to the champion. Linear over three rounds
## puts round two at the midpoint, and the midpoint of "free" and "hard" is still free.
##
## THE FIX IS A REDISTRIBUTION, NOT AN ESCALATION. Two knobs, both applied only to the rounds
## BEFORE the title bout:
##   * `QUALIFY_LIFT` raises the first round off the floor, toward the champion.
##   * `ROUND_CURVE` < 1 makes the climb concave — the field gets serious early and then closes
##     the last of the gap slowly, so the champion still stands clearly above the draw.
##
## ⚠️ THE CHAMPION'S OWN FILL IS UNTOUCHED, AND THAT IS AN OWNERSHIP LINE, NOT AN OVERSIGHT.
## `career.gd` owns the ladder's ENDPOINTS (`FIELD_OPENER_*`, `FIELD_CHAMPION_*`, the rematch bump)
## because those are the ladder's slope; this file owns the SHAPE BETWEEN THEM, because that is
## the cup's own pacing. Both anchors are read back out of `Career` every call, so if the slope is
## re-tuned there, the draw re-shapes itself around the new endpoints with nothing to keep in sync.
##
## ⚠️ AND IT COSTS SWEEP RATE — SAY SO PLAINLY. Harder early rounds mean fewer sweeps, and
## promotion is still gated on the sweep. Measured effect is in the round report; the mitigation
## is that this is the small end of the redistribution, and the real answer is `META_GAME_REVIEW`
## item 1 (retire the `w^n` gate), which is not this file's to make.
const QUALIFY_LIFT := 0.55   ## round one, as a fraction of the way from career's floor to the champion
const ROUND_CURVE := 0.70    ## <1 = concave: the draw gets real fast, then closes slowly


## Fill for round `r` of a `rounds`-long draw at league `idx`. The champion's round is `career.gd`'s
## number verbatim; every earlier round is lifted and curved off it.
func round_fill(r: int, rounds: int, idx: int) -> float:
	var n: int = maxi(1, rounds)
	var champ: float = Career.field_fill(n - 1, n, idx)
	if r >= n - 1 or n <= 1:
		return champ
	var floor_fill: float = Career.field_fill(0, n, idx)
	var opener: float = lerpf(floor_fill, champ, QUALIFY_LIFT)
	var t: float = clampf(float(r) / float(n - 1), 0.0, 1.0)
	return clampf(lerpf(opener, champ, pow(t, ROUND_CURVE)), 0.05, 0.98)


## Begin a cup: pre-generate a rival team for every round up front (deterministic off `Roster`'s
## own seeded rng, same call `career.gd:enter_league_tournament()` makes per iteration) so
## `current_rival_team()` is stable and ready before the first tactics screen even builds.
## ⚠️ `rival_count_` DEFAULTS TO -1 = "however many teams this league fields"
## (`Career.rival_count_for_league`, ported from `town.ts:RIVAL_TEAM_COUNT_BY_LEAGUE` — 3 at the
## bottom, 5 from Platinum up). An explicit count still wins, so the probes that pass 3 are
## unaffected; only the game's own entry point asks for the league's real field.
##
## ⚠️ AND THE FIELD IS DRAWN, NOT ROLLED PER ROUND. `Career.make_cup_field()` seeds off
## `cup_field_seed()`, so the teams the sign-up screen showed you are the teams you fight —
## scouting a field that re-rolls at the door is not scouting.
func start(target_league_idx: int, rival_count_: int = -1) -> void:
	var idx: int = clampi(target_league_idx, 0, Career.league_index)
	league_idx = idx
	team_size = Career.team_size_for_league(idx)
	## ⚠️ AN EXPLICIT COUNT MEANS "A SCRIPTED RUN" AND MUST NOT PICK UP THE MARQUEE'S EXTRA TEAM —
	## the probes that pass 3 are pinning a fixture, and a run that silently became four rounds
	## because the game-year happened to land on the marquee month would be a flaky test.
	marquee = rival_count_ <= 0 and is_marquee(idx)
	rival_count = maxi(1, rival_count_) if rival_count_ > 0 else rounds_for(idx)
	current_round = 0
	wins = 0
	round_results = []
	rival_teams = []
	weeks_spent = 0
	before_league_name = Career.current_league_name()
	field = _draw_field(idx, rival_count)
	for entry in field:
		rival_teams.append(entry["team"])
	active = true


## `Career.make_cup_field()` draws the field — the seeds, the labels, the champion flag and the
## rematch bump all stay its business — and this re-rolls the pre-title rounds at `round_fill()`'s
## reshaped strength. Same seed per round as career used, so the draw is still reproducible and
## still stable for the game-month the player scouted it in.
func _draw_field(idx: int, rounds: int) -> Array:
	var out: Array = Career.make_cup_field(idx, rounds)
	var size: int = Career.team_size_for_league(idx)
	var base_seed: int = Career.cup_field_seed(idx)
	for r in range(out.size()):
		if bool(out[r].get("champion", false)):
			continue
		var want: float = round_fill(r, rounds, idx)
		if absf(want - float(out[r].get("fill", 0.0))) < 0.005:
			continue
		## ⚠️ THE ARCHETYPE MUST SURVIVE THE RE-ROLL. `make_cup_field` assigns each round a KIND;
		## re-drawing without passing it back turned every reshaped qualifier into a generic team
		## and silently undid the archetype workstream on the live path only.
		out[r]["team"] = Career.make_league_rivals(size, idx, want,
			absi(base_seed + r * 7919) % 2147483647, String(out[r].get("archetype", "")))
		out[r]["fill"] = want
	return out


## The rival team for whichever round is currently being fought/ordered. Empty if the run has
## already finished (or was never started) — callers should treat that as "no cup in progress".
func current_rival_team() -> Array:
	if not active or current_round < 0 or current_round >= rival_teams.size():
		return []
	return rival_teams[current_round]


func is_last_round() -> bool:
	return current_round >= rival_count - 1


## The drawn-field entry for the current round, or {} if the run is over. Lets the presentation
## layer say WHO this round is — "Round 2 of the draw" vs "Ysolde Ferrum, the Anvil" — which is
## the whole point of seating a named champion in the bracket rather than in a side skirmish.
func current_round_entry() -> Dictionary:
	if not active or current_round < 0 or current_round >= field.size():
		return {}
	return field[current_round]


## True when the round about to be fought is the league's titleholder — always the last round.
func is_champion_round() -> bool:
	return bool(current_round_entry().get("champion", false))


## A one-line billing for the current round, for any screen that wants it.
func current_round_label() -> String:
	var e := current_round_entry()
	if e.is_empty():
		return ""
	return str(e.get("label", ""))


func is_finished() -> bool:
	return current_round >= rival_count


## Called once per fought round (arena_3d.gd, after a fight resolves). Advances the round
## pointer — `current_rival_team()` then returns the NEXT round's opponent.
func record_round_result(won: bool) -> void:
	if not active:
		return
	round_results.append(won)
	if won:
		wins += 1
	current_round += 1


## Wraps up a finished cup: applies career.gd's sweep/promotion rule exactly once, stashes a
## result dict shaped like `enter_league_tournament()`'s return (so `tournament_ui.gd` renders
## both paths with the same code), and deactivates. Safe to call only once `is_finished()`.
func finish() -> Dictionary:
	var out: Dictionary = Career.apply_tournament_outcome(league_idx, wins, rival_count)
	out["beforeLeague"] = before_league_name
	var results: Array = []
	for i in range(round_results.size()):
		var champ: bool = i < field.size() and bool(field[i].get("champion", false))
		results.append({"won": bool(round_results[i]), "champion": champ,
			"label": str(field[i].get("label", "")) if i < field.size() else ""})
	out["matches"] = results
	out["weeks"] = weeks_spent
	out["marquee"] = marquee
	out["marqueeName"] = marquee_name(league_idx) if marquee else ""
	last_result = out
	active = false
	return out


## Abandon a cup in progress (player backs out mid-run). No `Career` state is touched — no round
## result was ever applied to it — so this only clears local presentation state.
func cancel() -> void:
	active = false
	league_idx = -1
	rival_teams = []
	field = []
	current_round = 0
	wins = 0
	round_results = []
	weeks_spent = 0
	marquee = false
