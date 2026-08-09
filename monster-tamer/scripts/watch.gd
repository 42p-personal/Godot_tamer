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

## ⚠️ THE ROSTER IS THE FIX, NOT MORE RENDERER CODE — and this file was the last place it had not
## landed. `docs/WATCH_AUDIT.md` §4 measured it: on the PRODUCTION watch path, `heal`, `cleanse`,
## `thorns`, `ward_soak`, `status_tick`, `status_break` and `proj_fizzle` fired ZERO times in every
## fight, because the ten monsters here drafted their kits from their movesets and every one of
## the ten came out damage-and-self-buffs. Four rounds of support-layer work — the buff grammar,
## the ward soak cue, the cleanse presentation — were invisible on the path the player takes, and
## no amount of presentation work could be judged against a fight that cannot produce the mechanic.
## `COMBAT_SPATIAL_LOG.md` recorded this same lesson on 2026-08-08 and fixed it for the DEV scene
## (`scripts/sim/_watch_sim.gd`); the production path never inherited it. This is that inheritance.
##
## ⚠️ AND IT IS STILL THE REAL PATH. The kit is built by the same `KitLib.build(names, moves)` the
## career fight uses (`arena_3d.gd:_new_sim_inputs`) — only the move NAMES differ, so this viewer
## still exercises the code the game runs. What it does not do is exercise the DRAFT
## (`assign_moveset`), and that is the honest limitation: the draft is what produced the
## all-damage kits in the first place, and whether a career roster can field a healer is a
## question for the draft, not for the viewer. Recorded rather than papered over.
const ROLES_A := [
	# tank — taunt (the forced target change), thorns, a ward
	{"i": 1, "moves": ["Taunt", "Barbed Carapace", "Bastion"], "floor": {"CON": 70.0, "STR": 55.0}},
	# healer — the only source of `heal` and `cleanse` there is
	{"i": 3, "moves": ["Mend", "Clarity"], "floor": {"WIS": 70.0, "CHA": 50.0}},
	# caster — the AoE, so the burst ring and its falloff have something to draw
	{"i": 2, "moves": ["Hush", "Cleave", "Arcane Bomb"], "floor": {"INT": 75.0, "WIS": 45.0}},
	{"i": 0, "moves": [], "floor": {"STR": 75.0, "DEX": 65.0}},
	{"i": 4, "moves": [], "floor": {"STR": 75.0, "DEX": 65.0}},
]
## Team B: PRESSURE against A's SUSTAIN — the asymmetry `_watch_sim.gd` measured its way to. A
## mirror of the support comp ground to 134 seconds of two sides healing through each other.
const ROLES_B := [
	{"i": 1, "moves": ["Barbed Carapace", "Fortify"], "floor": {"CON": 65.0, "STR": 60.0}},
	{"i": 2, "moves": ["Hush", "Cleave", "Arcane Bomb"], "floor": {"INT": 75.0, "WIS": 45.0}},
	{"i": 0, "moves": [], "floor": {"STR": 80.0, "DEX": 70.0}},
	{"i": 3, "moves": [], "floor": {"STR": 80.0, "DEX": 70.0}},
	{"i": 4, "moves": [], "floor": {"STR": 80.0, "DEX": 70.0}},
]


## Apply a role to a made monster: floor the stats the role needs to FUNCTION (a healer with 12
## WIS heals for nothing and the fight shows an empty mechanic), then overwrite the drafted
## moveset with the authored kit. An empty `moves` list leaves the draft alone — those are the
## bodies, and they should fight with whatever the draft gave them.
static func _cast_role(m, role: Dictionary) -> void:
	if m == null:
		return
	for k in (role.get("floor", {}) as Dictionary).keys():
		m.stats[k] = maxf(float(m.stats.get(k, 10.0)), float(role["floor"][k]))
	var names: Array = role.get("moves", [])
	if names.is_empty():
		return
	var by_name := {}
	for mv in GameData.moves:
		by_name[str((mv as Dictionary).get("name", ""))] = mv
	var kit: Array = []
	for n in names:
		if by_name.has(str(n)):
			kit.append(by_name[str(n)])
		else:
			# Loud, not silent: a renamed move must not quietly turn a healer back into a body.
			push_warning("[watch] role move not in data.json: %s" % str(n))
	if not kit.is_empty():
		m.moveset = kit


func _ready() -> void:
	# A real roster on both sides, deterministic — same seed, same fight, every time you press R.
	var a: Array = []
	var b: Array = []
	for s in ROSTER_A:
		a.append(GameData.make_monster(s, 0.35))
	for s in ROSTER_B:
		b.append(GameData.make_monster(s, 0.35))
	for role in ROLES_A:
		_cast_role(a[int(role["i"])], role)
	for role in ROLES_B:
		_cast_role(b[int(role["i"])], role)

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

	# ⚠️ THE VIEWER COMMITS A REAL PLAN, BECAUSE A VIEWER THAT COMMITS NOTHING CANNOT SHOW THE
	# LOOP IT EXISTS TO TEST. With empty plans the report's lead line reads "You committed no claim
	# this fight" — so the one surface built to answer *was my read right*, the payoff of the whole
	# commit-then-observe design, was dark on the only path anyone uses to watch a fight.
	# ⚠️ AND IT DELIBERATELY ORDERS `manmark`, the axis wired this round: it is the single order
	# that asks the player to do scouting work, and the viewer is where a wiring regression would
	# be seen. The mark is team B's AoE caster (`ROLES_B` index 2) — "kill their bomb" is a claim
	# with a visible answer, which is what a graded claim has to be.
	var plan_a := {"targetPriority": "manmark", "markedUnit": b[2],
		"positionalIntent": "push", "temperament": "balanced", "formation": "tight"}
	var plan_b := {"targetPriority": "tanks", "positionalIntent": "dive",
		"temperament": "aggressive", "formation": "loose"}
	var T = load("res://scripts/tactics.gd")
	T.committed = {"teamA": a, "teamB": b, "planA": plan_a, "planB": plan_b,
		"orders": {}, "ordersA": {}, "ordersB": {}, "layout": pick}
	print("[watch] arena: %s" % pick)
	# ⚠️ DEFERRED. Calling `change_scene_to_file` inside `_ready()` fires while the SceneTree is
	# still adding this node — Godot answers with "Parent node is busy adding/removing children,
	# remove_child() can't be called at this time". The swap half-happened anyway, which is worse
	# than failing outright: the arena loaded, the error scrolled past, and the entry point looked
	# like it worked. A known engine trap, and I walked into it.
	get_tree().change_scene_to_file.call_deferred("res://scenes/arena3d.tscn")
