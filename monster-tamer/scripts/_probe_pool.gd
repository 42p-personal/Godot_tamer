## POOL AUDIT: which of the 141 moves can NEVER be drafted? All 65 species x 4 training tiers
## x 8 seeds — the union of every kit. Also: which moves are learnable by nobody at maxed stats
## (a data gap, not a picker gap).
extends Node
func _ready() -> void:
	var drafted := {}
	var learnable := {}
	for sp in GameData.species:
		for tier in [0.2, 0.5, 0.9]:
			for seed_i in range(8):
				var rng := RandomNumberGenerator.new(); rng.seed = hash([sp["id"], tier, seed_i])
				var m = GameData.make_monster(sp["id"], tier, rng)
				for mv in m.moveset:
					drafted[mv["name"]] = true
		# maxed: every stat at the Tamers Apex ceiling
		for seed_i in range(8):
			var rng2 := RandomNumberGenerator.new(); rng2.seed = hash([sp["id"], "max", seed_i])
			var mm = GameData.make_monster(sp["id"], 1.0, rng2)
			for stat in mm.stats:
				mm.stats[stat] = 1100.0
			mm.assign_moveset(rng2)
			for mv in mm.moveset:
				drafted[mv["name"]] = true
			# learnability at ceiling (union across classes via class_lines)
			var lines: Array = GameData.class_lines.get(mm.class_name_, [])
			for line in lines:
				for lm in GameData.moves_by_line.get(line, []):
					learnable[lm["name"]] = true
	var never: Array = []
	for mv in GameData.moves:
		if not drafted.has(mv["name"]):
			never.append(mv)
	print("drafted %d of %d moves across 65 species x 4 tiers x 8 seeds" % [drafted.size(), GameData.moves.size()])
	print("NEVER DRAFTED (%d):" % never.size())
	never.sort_custom(func(a,b): return str(a["line"]) < str(b["line"]))
	for mv in never:
		print("  %-24s line %-12s type %-8s learnLevel %-4d stat %s%s" % [
			mv["name"], mv["line"], mv["type"], int(mv["learnLevel"]), mv["stat"],
			"" if learnable.has(mv["name"]) else "   <- NOT EVEN LEARNABLE (no class draws its line?)"])
	get_tree().quit()
