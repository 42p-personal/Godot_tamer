## END-TO-END CUP PROOF. Throwaway probe.
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_cup.tscn
##
## Drives a full 3-round cup through the LIVE wiring — `CupRun.start()` -> per round
## `CupRun.current_rival_team()` -> a real fight (`SpatialSim`, same engine `arena_3d.gd` uses,
## falling back to `BattleSim` only if the spatial script is missing) -> `CupRun.
## record_round_result()` -> `CupRun.finish()` -> `Career.apply_tournament_outcome()`. Proves the
## scene-to-scene handoff this session wired (tournament_ui.gd -> tactics_ui.gd -> arena_3d.gd)
## produces the same shape of result without needing three real windows.
##
## ⚠️ `SpatialSim.run()` is a COROUTINE — this script `await`s it. A missed `await` returns a
## GDScriptFunctionState, not a Dictionary, and `result.get("winner")` would silently read back
## empty rather than erroring (docs/BUILD_CONTRACT.md §2).
extends Node

const TacticsScript = preload("res://scripts/tactics.gd")
const SPATIAL_SIM_PATH := "res://scripts/spatial_sim.gd"
const BattleSimScript = preload("res://scripts/battle_sim.gd")


func _ready() -> void:
	print("=== CUP RUN PROOF (live per-round wiring) ===\n")

	Career.reset_new_game()
	Roster.reset_to_empty()
	Roster._generate_starting_roster()

	var idx: int = Career.league_index
	var team_size: int = Career.team_size_for_league(idx)
	print("league: %s (idx %d)   team size: %d   roster: %d monsters" % [
		Career.current_league_name(), idx, team_size, Roster.monsters.size()])

	CupRun.start(idx, 3)
	print("CupRun.start() — active=%s  rounds=%d  rival teams built=%d\n" % [
		CupRun.active, CupRun.rival_count, CupRun.rival_teams.size()])

	var used_spatial := ResourceLoader.exists(SPATIAL_SIM_PATH)
	var round_num := 1
	while CupRun.active and not CupRun.is_finished():
		var team_a: Array = Roster.monsters.slice(0, mini(team_size, Roster.monsters.size()))
		for m in team_a:
			m.reset_for_battle()
		var team_b: Array = CupRun.current_rival_team()
		if team_b.is_empty():
			print("  *** FAIL: round %d has no rival team ***" % round_num)
			break

		var gp_id := TacticsScript.gameplan_for(team_b.map(func(m): return m.species_name))
		var plan_b := TacticsScript.team_plan_for_gameplan(gp_id)
		var orders_b := TacticsScript.orders_for_gameplan(gp_id, team_b)
		var plan_a := {}
		var orders_a := {}
		TacticsScript.commit(plan_a, plan_b, orders_a, orders_b, {}, {}, team_a, team_b)

		var result: Dictionary
		if used_spatial:
			var SimScript = load(SPATIAL_SIM_PATH)
			var sim = SimScript.new(team_a, team_b, 20260804 + round_num, plan_a, plan_b, {}, [])
			result = await sim.run()   # ⚠️ coroutine — must await
		else:
			var sim2 = BattleSimScript.new(team_a, team_b, 20260804 + round_num, plan_a, plan_b, {})
			result = sim2.run()

		var winner: String = str(result.get("winner", "?"))
		var won: bool = winner == "A"
		print("  round %d  (engine=%s)  winner=%s  survivorsA=%d survivorsB=%d  duration=%.1fs" % [
			round_num, "spatial" if used_spatial else "battle_sim",
			winner, int(result.get("survivorsA", -1)), int(result.get("survivorsB", -1)),
			float(result.get("duration", -1.0))])
		if winner == "?" or not result.has("winner"):
			print("    *** FAIL: result dict looks empty — check for a missed `await` ***")

		CupRun.record_round_result(won)
		round_num += 1

	print("\nCupRun state before finish(): wins=%d/%d  results=%s" % [
		CupRun.wins, CupRun.rival_count, str(CupRun.round_results)])

	if not CupRun.is_finished():
		print("  *** FAIL: cup ended without reaching is_finished() ***")
		get_tree().quit(1)
		return

	var out: Dictionary = CupRun.finish()
	print("\n--- CupRun.finish() -> Career.apply_tournament_outcome() ---")
	print("  league=%s  wins=%d/%d  swept=%s  promoted=%s  gameWon=%s" % [
		out.get("league", "?"), int(out.get("wins", -1)), int(out.get("rivalCount", -1)),
		out.get("swept", null), out.get("promoted", null), out.get("gameWon", null)])
	print("  Career.league_index now: %d (%s)" % [Career.league_index, Career.current_league_name()])

	# Mirror tournament_ui.gd's own purse formula so this probe checks the exact number the
	# player would see, not just the win count.
	var base_purse := 220 + 140 * idx
	var reward_by_drop := [1.0, 0.5, 0.2]
	var drop: int = clampi(Career.league_index - idx, 0, reward_by_drop.size() - 1)
	var purse_full := int(round(float(base_purse) * float(reward_by_drop[drop])))
	var purse: int = int(round(float(purse_full) * (float(out.get("wins", 0)) / float(out.get("rivalCount", 1)))))
	print("  purse (tournament_ui.gd's own formula): %d gold" % purse)

	print("\n=== done — %d of %d rounds resolved live ===" % [round_num - 1, CupRun.round_results.size()])
	get_tree().quit(0)
