## WATCH — boots straight into a 5v5 on the new named arena, no menus in the way.
##
## ⚠️ THIS IS A VIEWER, NOT A GAME MODE. It exists so a composition can be judged by WATCHING a
## fight on it, which is the only test that matters and the one this project has never had a
## convenient path to (`docs/OUTSTANDING.md` §3: the biggest unchecked assumption in the project
## is whether the sim is actually fun to watch, and there is not one playtest record in the repo).
##
## Controls are printed on screen because a viewer nobody knows how to drive is a viewer nobody
## uses. `arena_3d.gd` owns them; this scene only sets the fight up.
extends Node

static var _launch_count: int = 0

const ROSTER_A := ["kongrath", "aegisox", "corvaan", "balaenix", "grivvel"]
const ROSTER_B := ["crocmaw", "titanrex", "larkessa", "iguanor", "tazzik"]


func _ready() -> void:
	# A real roster on both sides, deterministic — same seed, same fight, every time you press R.
	var a: Array = []
	var b: Array = []
	for s in ROSTER_A:
		a.append(GameData.make_monster(s, 0.35))
	for s in ROSTER_B:
		b.append(GameData.make_monster(s, 0.35))

	# ⚠️ Committed through `Tactics` exactly as the real cup path does, rather than letting the
	# arena invent its own teams — otherwise this viewer would be testing a code path the game
	# never runs, which is how a scene passes while the product is broken.
	# ⚠️ CYCLES THE LAYOUT EACH TIME. Two authored compositions exist and they are the two halves of
	# the 8/8 split the WoW blueprints revealed — `four_pillar` rings an OPEN centre, `central_mass`
	# makes the centre the obstacle. Comparing them is the whole reason a second one was built, so
	# the viewer alternates rather than making anyone edit a file to see the other.
	var layouts := ["four_pillar", "central_mass", "triad", "lanes"]
	var pick: String = layouts[_launch_count % layouts.size()]
	_launch_count += 1

	var T = load("res://scripts/tactics.gd")
	T.committed = {"teamA": a, "teamB": b, "planA": {}, "planB": {}, "orders": {}, "layout": pick}
	print("[watch] arena: %s" % pick)
	# ⚠️ DEFERRED. Calling `change_scene_to_file` inside `_ready()` fires while the SceneTree is
	# still adding this node — Godot answers with "Parent node is busy adding/removing children,
	# remove_child() can't be called at this time". The swap half-happened anyway, which is worse
	# than failing outright: the arena loaded, the error scrolled past, and the entry point looked
	# like it worked. A known engine trap, and I walked into it.
	get_tree().change_scene_to_file.call_deferred("res://scenes/arena3d.tscn")
