## WHEN DOES THE TEAM COLLAPSE INTO A BLOB, AND BY HOW MUCH? Reports, per frame bucket:
##   spread    — mean distance from a team's own centroid (how wide the team stands)
##   nn        — mean distance to the NEAREST teammate (how packed the bodies are)
##   sep       — distance between the two team centroids (how far apart the sides are)
## Deployment spreads them over a 30-unit band, so any collapse happens during the fight.
extends Node

const Sp = preload("res://scripts/spatial.gd")
var _units_ref: Array = []
var _reach_ref: Array = []

func _ready() -> void:
	var Sim = load("res://scripts/spatial_sim.gd")
	var GD = load("res://scripts/game_data.gd")
	var team_a: Array = []
	var team_b: Array = []
	for i in range(5):
		team_a.append(GameData.make_monster(Art.ROSTER[i], 0.3))
		team_b.append(GameData.make_monster(Art.ROSTER[i + 5], 0.3))
	var Tree = load("res://scripts/ai/monster_tree.gd")
	_units_ref = team_a + team_b
	for u in _units_ref:
		_reach_ref.append(Tree._unit_best_reach(u))
	var sim = Sim.new(team_a, team_b, 20260804, {}, {}, {}, [])
	var res: Dictionary = await sim.run()
	var frames: Array = res.get("frames", [])
	var g: Vector2 = res.get("groundSize", Vector2(1, 1))
	print("frames: %d   ground: %s   deploy separation: %.1f" % [frames.size(), g, Sp.deploy_separation(5)])

	# ⚠️ DO THEY USE THE SPACE? Spread says how wide they STAND; these say where they WENT.
	#   lateral   — total |dz| travelled, i.e. movement ACROSS the arena rather than straight at
	#               the enemy. A team that only ever advances scores ~0 here no matter how far
	#               apart it stands.
	#   footprint — fraction of the ground's area inside the bounding box of every position ever
	#               visited. "The arena is bigger" means nothing if this does not move with it.
	var lateral := 0.0
	var along := 0.0
	var prev: Array = []
	var lo := Vector2(1e9, 1e9); var hi := Vector2(-1e9, -1e9)
	for f in range(frames.size()):
		var us: Array = frames[f].get("units", [])
		for i in range(us.size()):
			if not bool(us[i].get("alive", true)): continue
			var q: Vector2 = us[i]["pos"]
			lo = lo.min(q); hi = hi.max(q)
			if f > 0 and i < prev.size():
				lateral += absf(q.y - (prev[i] as Vector2).y)
				along += absf(q.x - (prev[i] as Vector2).x)
		prev = us.map(func(u): return u["pos"] as Vector2)
	var box := hi - lo
	print("travel: lateral %.0f   along %.0f   lateral share %.0f%%" % [
		lateral, along, 100.0 * lateral / maxf(1.0, lateral + along)])
	print("footprint visited: %.0f x %.0f  =  %.0f%% of the %.0f x %.0f ground" % [
		box.x, box.y, 100.0 * (box.x * box.y) / maxf(1.0, g.x * g.y), g.x, g.y])
	# ⚠️ DID THE REACTIONS ACTUALLY FIRE? Every reactive system found this session was BUILT and
	# UNREACHABLE — flanking, both retreat modes — so "it is implemented" proves nothing. Count the
	# ticks each reactive intent actually occupied, and print a sample reason so the text a player
	# would read is checked too, not just the branch name.
	var react := {}
	var samples := {}
	for f in frames:
		for u in f.get("units", []):
			var it := str(u.get("intent", ""))
			if it in ["peeling", "bailing out", "falling back", "disengaging", "withdrawing",
					  "re-engaging", "breaking off"]:
				react[it] = int(react.get(it, 0)) + 1
				if not samples.has(it): samples[it] = str(u.get("reason", ""))
	print("REACTIONS (unit-ticks):")
	if react.is_empty():
		print("  none fired — the reactive branches are unreachable again")
	for k in react.keys():
		print("  %-14s %5d   e.g. %s" % [k, react[k], samples[k]])
	print("")

	# Which branch did each unit actually run? The frame stream carries the tree's own `intent`.
	var by_unit := {}
	for f in frames:
		var us: Array = f.get("units", [])
		for i in range(us.size()):
			var it := str(us[i].get("intent", ""))
			if it == "": continue
			if not by_unit.has(i): by_unit[i] = {}
			by_unit[i][it] = int(by_unit[i].get(it, 0)) + 1
	# ⚠️ DID EVERY UNIT ACTUALLY MOVE? A dominant intent of "returning to post" looks healthy in a
	# tally and can mean a unit stood at spawn for the whole fight — which is exactly what happened
	# to the long-reach kits, and only WATCHING caught it. Distance travelled cannot be faked.
	var travelled := {}
	var lastp := {}
	for f in frames:
		var us: Array = f.get("units", [])
		for i in range(us.size()):
			if not bool(us[i].get("alive", true)): continue
			if lastp.has(i):
				travelled[i] = float(travelled.get(i, 0.0)) + (us[i]["pos"] as Vector2).distance_to(lastp[i])
			lastp[i] = us[i]["pos"]
	for i in range(by_unit.size()):
		var d: Dictionary = by_unit.get(i, {})
		var best := ""; var n := 0
		for k in d.keys():
			if int(d[k]) > n: n = int(d[k]); best = str(k)
		var moved: float = float(travelled.get(i, 0.0))
		print("  unit %d  DEX %4d  reach %5.1f  travelled %6.0f  -> %s%s" % [i,
			int(_units_ref[i].stats.get("DEX", 0)), _reach_ref[i], moved, best,
			"   ⚠️ NEVER MOVED" if moved < 5.0 else ""])
	print("")
	print("%6s %8s %8s %8s %8s %8s" % ["frame", "A_spread", "B_spread", "A_nn", "B_nn", "sep"])
	for f in range(0, frames.size(), maxi(1, frames.size() / 12)):
		var us: Array = frames[f].get("units", [])
		var pa: Array = []; var pb: Array = []
		for i in range(us.size()):
			if not bool(us[i].get("alive", true)): continue
			(pa if i < 5 else pb).append(us[i]["pos"])
		print("%6d %8s %8s %8s %8s %8.1f" % [f, _spread(pa), _spread(pb), _nn(pa), _nn(pb),
			(_centroid(pa) - _centroid(pb)).length()])

func _centroid(p: Array) -> Vector2:
	if p.is_empty(): return Vector2.ZERO
	var c := Vector2.ZERO
	for v in p: c += v
	return c / float(p.size())

func _spread(p: Array) -> String:
	if p.size() < 2: return "-"
	var c := _centroid(p); var t := 0.0
	for v in p: t += (v - c).length()
	return "%.1f" % (t / float(p.size()))

func _nn(p: Array) -> String:
	if p.size() < 2: return "-"
	var t := 0.0
	for i in range(p.size()):
		var best := 1e9
		for j in range(p.size()):
			if i != j: best = minf(best, (p[i] - p[j]).length())
		t += best
	return "%.1f" % (t / float(p.size()))
