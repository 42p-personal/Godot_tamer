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
const FIELD_OPENER_BOTTOM := 0.28   ## round one, Wood — a team you should beat
const FIELD_OPENER_TOP := 0.50      ## round one, Tamers Apex — nothing at the summit is free
const FIELD_CHAMPION_BOTTOM := 0.55 ## the Paddock King
const FIELD_CHAMPION_TOP := 0.95    ## the Dynast
const CHAMPION_REMATCH_BUMP := 0.04 ## they train too — see `champion_fill_for()`


## How far up the ladder a league sits, 0..1. The one place the slope is computed.
func ladder_t(idx: int) -> float:
	var last: int = maxi(1, leagues.size() - 1)
	return clampf(float(clampi(idx, 0, last)) / float(last), 0.0, 1.0)


## Fill for round `round_idx` of a `rounds`-long field. Linear opener -> champion; a 3-round cup
## and a 5-round cup therefore span the same difficulty range at different granularity.
func field_fill(round_idx: int, rounds: int, idx: int = -1) -> float:
	var league: int = idx if idx >= 0 else league_index
	var r: int = maxi(1, rounds)
	if round_idx >= r - 1:
		return clampf(champion_fill_for(league), 0.05, 0.98)
	var lt: float = ladder_t(league)
	var opener: float = lerpf(FIELD_OPENER_BOTTOM, FIELD_OPENER_TOP, lt)
	var t: float = 0.0 if r <= 1 else clampf(float(round_idx) / float(r - 1), 0.0, 1.0)
	return clampf(lerpf(opener, champion_fill_for(league), t), 0.05, 0.98)


## ⚠️ THE CHAMPION REMEMBERS — within the limits of what the save file actually carries.
## `leagues_won[idx]` is persisted (`save_game.gd`), so "have you taken this title off them
## before" survives a reload and is the one piece of history this can honestly stand on: come
## back to a league you already cleared and its champion has spent the interval training.
## A per-session grudge counter would NOT survive a save/load — `save_game.gd` is not this
## workstream's file and serialises a fixed field list — so the escalation is derived from saved
## state rather than stored, deliberately.
func champion_fill_for(idx: int) -> float:
	var beaten: bool = idx >= 0 and idx < leagues_won.size() and bool(leagues_won[idx])
	var base: float = lerpf(FIELD_CHAMPION_BOTTOM, FIELD_CHAMPION_TOP, ladder_t(idx))
	return base + (CHAMPION_REMATCH_BUMP if beaten else 0.0)


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

func champion_for(idx: int) -> Dictionary:
	if idx < 0 or idx >= CHAMPIONS.size():
		return {"name": "the titleholder", "title": "", "read": ""}
	return CHAMPIONS[idx]


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
func make_league_rivals(n: int, league_idx: int = -1, fill: float = -1.0, seed_: int = -1) -> Array:
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
	var team: Array = Roster.make_rival_team(n, clampf(use_fill, 0.0, 1.0), 1.0)
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
	for r in range(n):
		var fill: float = field_fill(r, n, idx)
		var is_champ: bool = r == n - 1
		out.append({
			"team": make_league_rivals(size, idx, fill, abs(base_seed + r * 7919) % 2147483647),
			"fill": fill,
			"champion": is_champ,
			"label": "%s, %s" % [champion_for(idx).get("name", ""), champion_for(idx).get("title", "")] if is_champ
				else "Round %d of the draw" % (r + 1),
		})
	return out


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


static func placement_label(placement: int) -> String:
	match placement:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
	return "%dth" % placement


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
		var sim = BattleSimScript.new(player_team, rival_team, rng.randi())
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
	var is_frontier: bool = idx == league_index
	var placement: int = placement_for(wins, rival_count)
	## ⚠️ Read the champion flag BEFORE the sweep marks the league won — `has_beaten_champion()`
	## is derived from `leagues_won`, so asking after would always answer true.
	var first_title: bool = swept and not has_beaten_champion(idx)
	var out := {
		"leagueIndex": idx, "league": league_at(idx).get("name", ""),
		"wins": wins, "rivalCount": rival_count,
		"swept": swept, "promoted": false, "gameWon": false,
		"placement": placement,
		"placementFraction": placement_reward_fraction(placement),
		"champion": champion_for(idx),
		"championBeaten": swept,
		"firstTitle": first_title,
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
