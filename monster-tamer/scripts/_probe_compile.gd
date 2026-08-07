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
	]
	var ok := true
	for p in paths:
		var s = load(p)
		if s == null:
			print("FAIL to load: %s" % p)
			ok = false
			continue
		var inst = s.new()
		if inst == null:
			print("FAIL to instantiate: %s" % p)
			ok = false
		print("OK: %s" % p)
	print("=== compile check %s ===" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
