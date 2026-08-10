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
	## ⚠️ THE LIST WAS THE HOLE. This probe used to name eleven files, so a parse error in any
	## other shipped script — `stable_ui.gd`, `training_ui.gd`, `save_game.gd` — was invisible to
	## it. That matters more than it sounds: in Godot a script that fails to PARSE makes its scene
	## silently script-less, so a probe over it does not fail, it HANGS (two ten-minute timeouts in
	## round 17 integration, both from one bad assignment). It now walks every shipped script and
	## excludes only the probes themselves, so the check cannot fall behind the tree again.
	var paths := _shipped_scripts()
	if paths.size() < 30:
		print("FAIL: the walk found only %d scripts — it is not seeing the tree" % paths.size())
		quit(1)
		return
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


## Every shipped `.gd` under `res://scripts/`, probes excluded. ⚠️ A probe IS allowed to be
## broken-by-omission here (they are instruments, not the game) but nothing else is.
func _shipped_scripts() -> Array:
	var out: Array = []
	var stack: Array = ["res://scripts"]
	while not stack.is_empty():
		var dir_path: String = str(stack.pop_back())
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		d.list_dir_begin()
		var f := d.get_next()
		while f != "":
			if d.current_is_dir():
				if not f.begins_with("."):
					stack.append(dir_path + "/" + f)
			## ⚠️ LEADING UNDERSCORE = INSTRUMENT, NOT GAME. Probes, harnesses and fixtures are
			## excluded — but note the walk found `_shader_verify.gd` BROKEN (a parse error dating
			## to the initial commit, caught the first time this list stopped being hand-written).
			## An instrument that cannot parse is dead weight; it is out of round 17's scope to
			## fix, and it is recorded here rather than quietly skipped.
			elif f.ends_with(".gd") and not f.begins_with("_"):
				out.append(dir_path + "/" + f)
			f = d.get_next()
		d.list_dir_end()
	out.sort()
	return out
