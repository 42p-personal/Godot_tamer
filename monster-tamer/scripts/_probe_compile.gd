## THROWAWAY — compile-check for scripts not exercised by run_contract.sh or _probe_cup.gd.
extends Node

func _ready() -> void:
	var paths := [
		"res://scripts/ui/tournament_ui.gd",
		"res://scripts/ui/tactics_ui.gd",
		"res://scripts/ui/arena_3d.gd",
		"res://scripts/cup_run.gd",
		"res://scripts/career.gd",
		"res://scripts/tactics.gd",
		# The tactics screen's own children — the route tournament -> tactics -> battle runs
		# through these, and a parse error in any of them takes the whole screen down.
		"res://scripts/ui/deployment_board.gd",
		"res://scripts/ui/arena_view.gd",
		"res://scripts/sim/sim.gd",
		"res://scripts/sim/kit.gd",
		"res://scripts/ai/combat_tree.gd",
	]
	var ok := true
	for p in paths:
		# ⚠️ `load()` ON A SCRIPT THAT FAILED TO COMPILE STILL RETURNS A NON-NULL Script.
		# This probe used to test only `== null`, so it printed "OK" for `tactics_ui.gd` while
		# the engine was printing "Compilation failed" two lines above — which is exactly how
		# `deployment_board.gd`'s out-of-scope `team_size_` survived from the initial commit
		# with a green probe over it. `can_instantiate()` is the check that actually asks the
		# engine whether the script compiled.
		var s = load(p)
		if s == null:
			print("FAIL to load: %s" % p)
			ok = false
			continue
		if s is Script and not (s as Script).can_instantiate():
			print("FAIL to compile: %s" % p)
			ok = false
			continue
		print("OK: %s" % p)
	print("=== compile check %s ===" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
