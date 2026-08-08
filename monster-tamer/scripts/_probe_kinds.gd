## SEED FUZZ for the layout generator. Generates every league's board across many seeds and runs
## ArenaLayout.problems() (symmetry, deploy clearance, density ceiling, no overlaps) on every one.
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . --script res://scripts/_probe_kinds.gd
##
## ⚠️ THIS PROBE WAS WRONG FOR A WHILE AND IT MATTERS WHY. It used to generate 120 layouts that
## were ALL WOOD, then fail any KIND_TABLE kind it had not seen — reporting crate, planter and
## fence "missing" while all three were placed on Tin, Iron, Gold, Platinum, Tamer Elite and Apex.
## Its premise (one board, re-lit per league) died the moment each league got its own furniture,
## and it kept passing right up until the boards got BETTER. A check whose subject has moved is
## not a check. Kind coverage is now asked across the whole LADDER, which is the right scope, and
## `_probe_layout.gd` asks the same standard at the real arena seed.
##
## What is genuinely load-bearing here and is NOT duplicated by _probe_layout: that is one board
## per league at ONE seed (the seed the battle screen uses). This is the same eleven boards across
## many seeds — the only thing in the battery that would catch a board that is valid at the
## shipping seed and self-overlapping at another.
extends SceneTree

const ArenaLayoutLib = preload("res://scripts/arena_layout.gd")

## Mirrors `_probe_layout.gd:LEAGUES` — Wood -> Tamers Apex with the team size each fields.
const LEAGUES := [
	["Wood", 1], ["Copper", 2], ["Tin", 2], ["Bronze", 3], ["Iron", 3],
	["Silver", 4], ["Gold", 4], ["Platinum", 5], ["Masters", 5],
	["Tamer Elite", 5], ["Tamers Apex", 5],
]

const SEEDS := 24


func _initialize() -> void:
	var kind_counts: Dictionary = {}
	var grade_counts: Dictionary = {}
	var per_league_drop: Dictionary = {}
	var failures := 0
	var layouts := 0

	for entry in LEAGUES:
		var league := str(entry[0])
		var team_size := int(entry[1])
		for s in range(SEEDS):
			var rng := RandomNumberGenerator.new()
			rng.seed = 1000 + s
			var layout: Dictionary = ArenaLayoutLib.generate(team_size, league, rng)
			var obstacles: Array = layout["obstacles"]
			layouts += 1
			var probs: Array = ArenaLayoutLib.problems(obstacles, team_size)
			if not probs.is_empty():
				failures += 1
				print("FAIL league=%s team_size=%d seed=%d:" % [league, team_size, 1000 + s])
				for p in probs:
					print("   ", p)
			var n := 0
			for o in obstacles:
				n += 1
				var k := str(o["kind"])
				var g := str(o["grade"])
				kind_counts[k] = int(kind_counts.get(k, 0)) + 1
				grade_counts[g] = int(grade_counts.get(g, 0)) + 1
			# Track the piece count spread across seeds: a board whose emitted count varies with
			# the seed is authoring something the overlap gate is silently dropping.
			var lo: int = int(per_league_drop.get(league + "_lo", 9999))
			var hi: int = int(per_league_drop.get(league + "_hi", 0))
			per_league_drop[league + "_lo"] = mini(lo, n)
			per_league_drop[league + "_hi"] = maxi(hi, n)

	print("layouts generated: %d over %d leagues x %d seeds   validator failures: %d"
		% [layouts, LEAGUES.size(), SEEDS, failures])
	print("grade distribution: ", grade_counts)
	print("kind distribution across the ladder:")
	var kinds := kind_counts.keys()
	kinds.sort()
	for k in kinds:
		print("   %-16s %d" % [k, kind_counts[k]])

	var missing: Array = []
	for row in ArenaLayoutLib.KIND_TABLE:
		var k := str(row["kind"])
		if not kind_counts.has(k):
			missing.append(k)
	if missing.is_empty():
		print("kind coverage: %d of %d KIND_TABLE kinds reached"
			% [kind_counts.size(), ArenaLayoutLib.KIND_TABLE.size()])
	else:
		print("MISSING KINDS (authored in KIND_TABLE, on no league board): %s" % str(missing))

	# A board that emits a different number of pieces at a different seed is dropping authored
	# elements. The boards are authored, not scattered, so this spread should be zero.
	var wobbly: Array = []
	for entry2 in LEAGUES:
		var lg := str(entry2[0])
		if int(per_league_drop[lg + "_lo"]) != int(per_league_drop[lg + "_hi"]):
			wobbly.append("%s %d..%d" % [lg, per_league_drop[lg + "_lo"], per_league_drop[lg + "_hi"]])
	if wobbly.is_empty():
		print("piece count is seed-stable on all %d boards" % LEAGUES.size())
	else:
		print("SEED-UNSTABLE PIECE COUNTS (authored elements being dropped): %s" % str(wobbly))

	var ok := failures == 0 and missing.is_empty() and wobbly.is_empty()
	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
