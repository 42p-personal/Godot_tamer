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
var wins: int = 0
var round_results: Array = []       # Array[bool] — this run's per-round win/loss, in order
var before_league_name: String = "" # league name at the moment this cup was entered (pre-promotion)

## Set once by `finish()`; `tournament_ui.gd` reads it on `_ready()` to render the cup's final
## card and pay the purse, then clears it — same drain-once pattern as `ReportScript.pending`.
var last_result: Dictionary = {}


## Begin a cup: pre-generate a rival team for every round up front (deterministic off `Roster`'s
## own seeded rng, same call `career.gd:enter_league_tournament()` makes per iteration) so
## `current_rival_team()` is stable and ready before the first tactics screen even builds.
func start(target_league_idx: int, rival_count_: int = 3) -> void:
	var idx: int = clampi(target_league_idx, 0, Career.league_index)
	league_idx = idx
	team_size = Career.team_size_for_league(idx)
	rival_count = maxi(1, rival_count_)
	current_round = 0
	wins = 0
	round_results = []
	rival_teams = []
	before_league_name = Career.current_league_name()
	for i in range(rival_count):
		rival_teams.append(Career.make_league_rivals(team_size, idx))
	active = true


## The rival team for whichever round is currently being fought/ordered. Empty if the run has
## already finished (or was never started) — callers should treat that as "no cup in progress".
func current_rival_team() -> Array:
	if not active or current_round < 0 or current_round >= rival_teams.size():
		return []
	return rival_teams[current_round]


func is_last_round() -> bool:
	return current_round >= rival_count - 1


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
	out["matches"] = round_results.map(func(w): return {"won": w})
	last_result = out
	active = false
	return out


## Abandon a cup in progress (player backs out mid-run). No `Career` state is touched — no round
## result was ever applied to it — so this only clears local presentation state.
func cancel() -> void:
	active = false
	league_idx = -1
	rival_teams = []
	current_round = 0
	wins = 0
	round_results = []
