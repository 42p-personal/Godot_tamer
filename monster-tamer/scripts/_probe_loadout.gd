extends Node
const SM = preload("res://scripts/status_math.gd")

func _ready() -> void:
	print("%-8s %-9s | %s" % ["roll", "avg stat", "of 20 monsters: carry control/debuff · carry hard-control"])
	for roll in [0.2, 0.35, 0.5, 0.7, 0.9]:
		var util := 0; var hard := 0; var stat_sum := 0.0
		var types := {}
		for i in range(20):
			var m = GameData.make_monster(Art.ROSTER[i % Art.ROSTER.size()], roll)
			for k in ["STR","DEX","CON","WIS","INT","CHA"]:
				stat_sum += float(m.stats.get(k, 0.0))
			var has_u := false; var has_h := false
			for mv in m.moveset:
				types[str(mv.get("type","?"))] = int(types.get(str(mv.get("type","?")),0)) + 1
				if str(mv.get("type","")) in ["control","debuff"]: has_u = true
				var st = mv.get("status")
				if st != null and SM.HARD_CONTROL.has(str(st.get("kind",""))): has_h = true
			if has_u: util += 1
			if has_h: hard += 1
		print("%-8s %-9.0f | %2d carry control/debuff · %2d carry HARD control   moves: %s" % [
			roll, stat_sum / (20.0*6.0), util, hard, str(types)])
	# ⚠️ THE DECISIVE TEST: force stats to the Tamers Apex ceiling. If control still never drafts,
	# it is STRUCTURALLY unreachable and the picker is wrong. If it drafts, the earlier zeroes were
	# progression gating and my measurements were simply using starter monsters.
	print("")
	print("MAXED MONSTERS (all stats 1100 — the Tamers Apex ceiling):")
	var util := 0; var hard := 0; var slots := 0
	var types := {}
	for i in range(20):
		var m = GameData.make_monster(Art.ROSTER[i % Art.ROSTER.size()], 0.5)
		for k in ["STR","DEX","CON","WIS","INT","CHA"]:
			m.stats[k] = 1100.0
		m.assign_moveset(RandomNumberGenerator.new())
		slots += m.moveset.size()
		var has_u := false; var has_h := false
		for mv in m.moveset:
			types[str(mv.get("type","?"))] = int(types.get(str(mv.get("type","?")),0)) + 1
			if str(mv.get("type","")) in ["control","debuff"]: has_u = true
			var st = mv.get("status")
			if st != null and SM.HARD_CONTROL.has(str(st.get("kind",""))): has_h = true
		if has_u: util += 1
		if has_h: hard += 1
	print("   %d/20 carry control/debuff · %d/20 carry HARD control · %.1f moves each" % [
		util, hard, float(slots) / 20.0])
	print("   move types drafted: %s" % str(types))
	get_tree().quit()
