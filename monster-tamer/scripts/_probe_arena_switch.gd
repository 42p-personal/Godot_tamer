## THE RENDERER SWITCH PROBE — does the REAL BATTLE SCREEN run on the rewritten sim?
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_arena_switch.tscn
##
## ⚠️ WHY THIS EXISTS. `arena_3d.gd:USE_NEW_SIM` flipped the battle screen from the SUPERSEDED
## `spatial_sim.gd` + `ai/monster_tree.gd` onto `scripts/sim/sim.gd` + `ai/combat_tree.gd`. Every
## other probe in the battery exercises the new sim DIRECTLY — none of them touches `arena_3d.gd`,
## so all 175 of them stayed green while the battle screen itself was unreachable: `tactics_ui.gd`
## would not compile (`deployment_board.gd` read `setup()`'s parameter `team_size_` from inside
## `_compute_zones()`), and the tournament -> tactics -> battle route is the only way in.
## A switch nobody can reach is not a switch. This probe reaches it.
##
## It boots the ACTUAL scene (`arena3d.tscn`), through the ACTUAL entry state the tactics screen
## leaves behind (`Tactics.commit()` with real teams), and reads the fight the screen itself
## resolved — not a sim this probe constructed to look like the screen's.
extends Node

const TacticsScript = preload("res://scripts/tactics.gd")
const ARENA_SCENE := "res://scenes/arena3d.tscn"

var _fails := 0


func _check(name: String, ok: bool) -> void:
	if ok:
		print("  ok  ", name)
	else:
		_fails += 1
		print("  FAIL ", name)


var _team_a: Array = []
var _team_b: Array = []


## Build the career/cup/roster state ONCE. ⚠️ Deliberately once, not per boot: `Roster.
## _generate_starting_roster()` and `CupRun.current_rival_team()` do NOT draw from the fight
## seed, so regenerating them per boot hands the screen two different rosters and the twin-run
## below would be comparing two different fights. (That is worth knowing in its own right — the
## career's own roster generation is not reproducible from career state alone — but it is a
## meta-layer question, not the renderer switch, so it is stated here and not conflated with it.)
func _setup_state(want_size: int) -> void:
	Career.reset_new_game()
	Roster.reset_to_empty()
	Roster._generate_starting_roster()
	# ⚠️ CLIMB TO A LEAGUE THAT ACTUALLY FIELDS `want_size`. A fresh career starts at Wood, which
	# is 1v1 — and a 1v1 exercises almost nothing this switch is risky for: no id-ordering across
	# a roster ("a00".."a04" sorting into slot order is what `_adapt_result` asserts), no deploy
	# spread across the board, no per-side formation. THE GAME IS A 5v5 GAME (standing rule), so
	# the switch has to be proven at 5v5, not merely at the size a new save happens to open on.
	var idx := Career.league_index
	for i in range(Career.leagues.size()):
		if Career.team_size_for_league(i) >= want_size:
			idx = i
			break
	Career.league_index = idx
	CupRun.start(idx, 3)
	CupRun.current_round = 1   # the fight seed hashes this — see arena_3d._resolve_fight
	var team_size: int = Career.team_size_for_league(idx)
	while Roster.monsters.size() < team_size:
		Roster.monsters.append(GameData.make_monster(Art.ROSTER[Roster.monsters.size() % Art.ROSTER.size()], 0.5))
	_team_a = Roster.monsters.slice(0, mini(team_size, Roster.monsters.size()))
	_team_b = CupRun.current_rival_team()
	print("-- league '%s' (idx %d), team size %d --" % [Career.current_league_name(), idx, team_size])


## Put the game in the state the tactics screen hands to the battle screen, then let the battle
## screen do its own thing. Returns the arena node once its fight has resolved.
func _boot_arena() -> Node:
	# The SAME monster objects both times — the previous fight wrote hp/mp/alive onto them
	# (`_write_back_final`), so the entry state is only identical after this reset.
	for m in _team_a + _team_b:
		m.reset_for_battle()
	var gp_id := TacticsScript.gameplan_for(_team_b.map(func(m): return m.species_name))
	TacticsScript.commit({}, TacticsScript.team_plan_for_gameplan(gp_id), {},
		TacticsScript.orders_for_gameplan(gp_id, _team_b), {}, {}, _team_a, _team_b)

	var arena = load(ARENA_SCENE).instantiate()
	add_child(arena)
	# `_ready()` awaits the fight, so the node exists long before the result does. Poll for the
	# screen's own "I am playing" flag rather than guessing a frame count.
	for _i in 3000:
		await get_tree().process_frame
		if bool(arena.get("playing")):
			break
	return arena


func _ready() -> void:
	# The switch is proven at BOTH ends of the ladder's team-size range: 1v1 (what a new save
	# opens on) and 5v5 (what the game is balanced for and shipped as).
	await _scenario(1)
	await _scenario(5)
	print("ARENA SWITCH PROBE %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _scenario(want_size: int) -> void:
	_setup_state(want_size)
	var arena := await _boot_arena()
	var res: Dictionary = arena.get("result")

	_check("[%dv%d] the battle screen resolved a fight at all" % [want_size, want_size],
		not res.is_empty())
	_check("[%dv%d] the roster really is that size (the scenario is not silently a 1v1)"
		% [want_size, want_size], _team_a.size() == want_size and _team_b.size() == want_size)
	_check("it ran the NEW sim (the switch is actually on)", bool(arena.get("USE_NEW_SIM")))
	_check("a side WINS — the screen's fight is not a draw-by-cap",
		str(res.get("winner", "")) in ["A", "B"])
	var frames: Array = res.get("frames", [])
	_check("the screen has a frame stream to play back", frames.size() > 10)

	# ⚠️ THE CAP IS THE TELL FOR THE COORDINATE BUG. Feeding corner-frame positions to a
	# centre-frame navmesh puts every unit off the mesh: nobody paths, nobody closes, and the
	# fight runs the full 1800 ticks looking exactly like a broken AI. A fight that resolves
	# well inside the cap is the evidence that the frame translation is right way round.
	_check("the fight resolves well inside the tick cap (not the off-navmesh stall)",
		frames.size() < 1500 and float(res.get("duration", 0.0)) < 150.0)

	# Everyone must deploy INSIDE the board in the renderer's own corner frame. `_adapt_result`
	# asserts this too, but asserts are debug-only — this states it as a checked fact.
	var ground: Vector2 = res.get("groundSize", Vector2.ZERO)
	var on_board := true
	for u in (frames[0].get("units", []) as Array):
		var p: Vector2 = u.get("pos", Vector2.ZERO)
		if p.x < 0.0 or p.x > ground.x or p.y < 0.0 or p.y > ground.y:
			on_board = false
	_check("every unit deploys INSIDE the board (centre-frame -> corner-frame is right way round)",
		on_board and ground.x > 0.0)

	# The translation must not lose the fight's content on the way to the screen.
	_check("the event log reached the screen (hits/deaths, not just start+end)",
		(res.get("log", []) as Array).size() > 20)
	var deaths := 0
	for e in (res.get("log", []) as Array):
		if str(e.get("kind", "")) == "death":
			deaths += 1
	_check("bodies actually died and the log says so", deaths > 0)
	_check("survivor counts agree with the winning side",
		(str(res.get("winner")) == "A" and int(res.get("survivorsA", 0)) > 0)
		or (str(res.get("winner")) == "B" and int(res.get("survivorsB", 0)) > 0))

	# ⚠️ THE WRITE-BACK. The new sim never touches the MonsterInstance objects, so the career,
	# the report screen and the topple loop would all read `alive == true` forever unless
	# `_write_back_final` runs. This is the check that the roster learned the fight happened.
	var roster_hp_moved := false
	for m in _team_a:
		if float(m.hp) < float(m.max_hp):
			roster_hp_moved = true
	_check("the result is written back onto the roster (career/report read these)",
		roster_hp_moved)

	arena.queue_free()
	await get_tree().process_frame

	# Determinism THROUGH the screen: the same committed state must produce the same fight.
	var a2 := await _boot_arena()
	var res2: Dictionary = a2.get("result")
	_check("determinism through the battle screen: same entry state, same fight",
		str(res.get("winner")) == str(res2.get("winner"))
		and (res.get("frames", []) as Array).size() == (res2.get("frames", []) as Array).size())
	a2.queue_free()
	await get_tree().process_frame
