## THROWAWAY VERIFICATION for the KIND_TABLE widening (bench/fence/boulder/shrine — see
## docs/OBSTACLE_KIND_CANDIDATES.md). Not a deliverable; delete freely.
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . --script res://scripts/_probe_kinds.gd
##
## Generates layouts across team sizes and seeds, runs ArenaLayout.problems() (the four
## brief-mandated checks: symmetry, deploy clearance, density ceiling, no overlaps) on every one,
## and prints the kind distribution so a missing/never-rolled kind is visible, not assumed.
extends SceneTree

const ArenaLayoutLib = preload("res://scripts/arena_layout.gd")


func _initialize() -> void:
	var kind_counts: Dictionary = {}
	var grade_counts: Dictionary = {}
	var failures := 0
	var layouts := 0

	for team_size in [2, 3, 5]:
		for s in range(40):
			var rng := RandomNumberGenerator.new()
			rng.seed = 1000 + s
			var layout: Dictionary = ArenaLayoutLib.generate(team_size, "Wood", rng)
			var obstacles: Array = layout["obstacles"]
			layouts += 1
			var probs: Array = ArenaLayoutLib.problems(obstacles, team_size)
			if not probs.is_empty():
				failures += 1
				print("FAIL team_size=%d seed=%d:" % [team_size, 1000 + s])
				for p in probs:
					print("   ", p)
			for o in obstacles:
				var k := str(o["kind"])
				var g := str(o["grade"])
				kind_counts[k] = int(kind_counts.get(k, 0)) + 1
				grade_counts[g] = int(grade_counts.get(g, 0)) + 1

	print("layouts generated: %d   validator failures: %d" % [layouts, failures])
	print("grade distribution: ", grade_counts)
	print("kind distribution:")
	var kinds := kind_counts.keys()
	kinds.sort()
	for k in kinds:
		print("   %-10s %d" % [k, kind_counts[k]])
	var expected := ["barrel", "crate", "planter", "low_wall", "pillar",
		"bench", "fence", "boulder", "shrine"]
	var missing: Array = []
	for k in expected:
		if not kind_counts.has(k):
			missing.append(k)
	if not missing.is_empty():
		print("MISSING KINDS (never rolled across %d layouts): %s" % [layouts, str(missing)])
	print("RESULT: ", "PASS" if failures == 0 and missing.is_empty() else "FAIL")
	quit(0 if failures == 0 and missing.is_empty() else 1)
