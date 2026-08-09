## Compile-check for scripts not exercised by run_contract.sh or _probe_cup.gd.
##
## ⚠️ RUN IT WITH `--script`, AND THAT IS WHY IT EXTENDS SceneTree.
## It used to `extends Node`, which works only through a scene wrapper — and running a Node
## script the obvious way (`--headless --script res://scripts/_probe_compile.gd`) makes Godot
## pop a BLOCKING MODAL: "doesn't inherit from SceneTree or MainLoop". In an automated run that
## HANGS the run instead of failing it, which is strictly worse than an error. Two separate
## agents hit this dialog on this repo. A probe that needs no scene tree should extend
## SceneTree so the obvious command works.
##   cd monster-tamer && godot --headless --path . --script res://scripts/_probe_compile.gd
## ⚠️ The sibling rule still stands and is the OPPOSITE for nav-dependent probes: anything that
## needs a baked navmesh must run as a SCENE, because a --script SceneTree has no main loop to
## sync the NavigationServer. Which way a probe runs is decided by what it needs, not by taste.
extends SceneTree

func _initialize() -> void:
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
	quit(0 if ok else 1)
