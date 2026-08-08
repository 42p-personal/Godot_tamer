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
func current_stat_cap() -> float:
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


# ── rivals ────────────────────────────────────────────────────────────────

## Build `n` rival monsters scaled to a LEAGUE's cap, not to the player's own stats — an existing,
## deliberate design rule (see `roster.gd:make_rival_team` for the player-relative equivalent this
## extends rather than replaces). Delegates species/pool selection to `Roster.make_rival_team`;
## this function's only job is picking a fair `avg_training_level` for the target league.
##
## ⚠️ Accurate for the common case — generating rivals for the league you are ACTUALLY entering
## right now (`enter_league_tournament` always calls it this way). `GameData.make_monster()`'s
## training_level nudge targets `Career.current_stat_cap()`, which reads `league_index` (the
## player's CURRENT league) — not whatever `league_idx` is passed here. Scouting rivals for a
## league other than the current one is therefore an approximation, not a supported exact case, in
## this skeleton.
func make_league_rivals(n: int, league_idx: int = -1) -> Array:
	var idx := league_index if league_idx < 0 else league_idx
	var league_cap: float = stat_cap_for_league(idx)
	var top_cap: float = stat_cap_for_league(leagues.size() - 1)
	var fill: float = clampf(league_cap / maxf(1.0, top_cap), 0.08, 0.95)
	return Roster.make_rival_team(n, fill)


# ── tournaments / promotion ──────────────────────────────────────────────────

## Run a full round-robin: the player's roster (sliced to the target league's team size) against
## `rival_count` league-scaled rival teams, one headless `BattleSim` fight each. Sweeping every
## match wins the league; if the league fought was the ladder FRONTIER (not a replay of an
## already-cleared league below it), a sweep also PROMOTES — or, at Tamers Apex, wins the game.
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
func enter_league_tournament(target_league_idx: int = -1, rival_count: int = 3, seed_: int = -1) -> Dictionary:
	var idx := league_index if target_league_idx < 0 else clampi(target_league_idx, 0, league_index)
	var team_size := team_size_for_league(idx)
	var player_team: Array = Roster.monsters.slice(0, mini(team_size, Roster.monsters.size()))

	var use_seed := seed_ if seed_ >= 0 else (week * 97 + idx * 13 + rival_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = use_seed

	var matches: Array = []
	var wins := 0
	for i in range(rival_count):
		for m in player_team:
			m.reset_for_battle()
		var rival_team: Array = make_league_rivals(team_size, idx)
		var sim = BattleSimScript.new(player_team, rival_team, rng.randi())
		var result: Dictionary = sim.run()
		var won_match: bool = result.get("winner", "") == "A"
		if won_match:
			wins += 1
		matches.append({"result": result, "won": won_match})

	var out := apply_tournament_outcome(idx, wins, rival_count)
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
	var is_frontier: bool = idx == league_index
	var out := {
		"leagueIndex": idx, "league": league_at(idx).get("name", ""),
		"wins": wins, "rivalCount": rival_count,
		"swept": swept, "promoted": false, "gameWon": false,
	}

	if swept:
		if leagues_won.size() > idx:
			leagues_won[idx] = true
		league_swept.emit(league_at(idx).get("name", ""))
		if is_frontier:
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
