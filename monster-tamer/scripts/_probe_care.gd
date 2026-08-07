## THE CARE LOOP'S PROOF. Four checks:
## 1. potency scaling obeys its three rules (additive / mult-distance / replacement-lerp)
## 2. every authored innate field is carried by at least one of the 65 species (reachability!)
## 3. A/B: the same fight at happiness 0 vs 10 produces a different outcome — care MATTERS
## 4. weary: a monster at 10 stamina is flagged weary in the frame stream
extends Node
const Innates = preload("res://scripts/innate_fx.gd")
func _ready() -> void:
	# 1 — scaling rules
	var dummy = GameData.make_monster(GameData.species[0]["id"], 0.5)
	dummy.happiness = 5   # potency 0.75
	var table := {"X": {"flatDR": 4.0, "dmgMult": 1.2, "windupMult": 0.8}}
	dummy.innate = [{"name": "X"}]
	var fx: Dictionary = Innates.compute(dummy, table)
	var ok1: bool = absf(float(fx["flatDR"]) - 3.0) < 0.001 \
		and absf(float(fx["dmgMult"]) - 1.15) < 0.001 \
		and absf(float(fx["windupMult"]) - 0.85) < 0.001
	print("scaling rules      : %s  (flatDR 4->%.2f, dmgMult 1.2->%.3f, windup 0.8->%.3f)" % [
		"OK" if ok1 else "*** FAIL", fx["flatDR"], fx["dmgMult"], fx["windupMult"]])
	# 2 — field coverage across all species (data-level reachability)
	var carried := {}
	for sp in GameData.species:
		for inn in sp.get("innate", []):
			var eff: Dictionary = GameData.innate_effects.get(str(inn.get("name","")), {})
			for k in eff:
				carried[k] = true
	var authored := {}
	for nm in GameData.innate_effects:
		for k in GameData.innate_effects[nm]:
			authored[k] = true
	var orphans: Array = []
	for k in authored:
		if not carried.has(k):
			orphans.append(k)
	print("field coverage     : %d fields authored, %d carried by species, orphans: %s" % [
		authored.size(), carried.size(), "NONE - OK" if orphans.is_empty() else str(orphans) + " *** FAIL"])
	# 3 — care A/B. ⚠️ First: is fx even reaching the units, and does potency move it?
	var probe_m = GameData.make_monster(Art.ROSTER[0], 0.35)
	probe_m.happiness = 0
	var fx0: Dictionary = Innates.compute(probe_m, GameData.innate_effects)
	probe_m.happiness = 10
	var fx10: Dictionary = Innates.compute(probe_m, GameData.innate_effects)
	print("fx sanity          : %s innate=%s  hap0=%s  hap10=%s" % [
		Art.ROSTER[0], str(fx0.get("_name","(none)")), str(fx0), str(fx10)])
	# A/B with a HIGH-leverage innate forced onto team A, so a potency change must cross
	# integer-damage thresholds: Chest Beat = duelDmg 1.15 + firstHitMult 1.2.
	var results: Array = []
	for hap in [0, 10]:
		var Sim = load("res://scripts/spatial_sim.gd")
		var mrng := RandomNumberGenerator.new(); mrng.seed = 11
		var a: Array = []; var b: Array = []
		for i in range(5):
			var ma = GameData.make_monster(Art.ROSTER[i], 0.35, mrng)
			ma.happiness = hap
			ma.innate = [{"name": "Chest Beat"}]
			a.append(ma)
			b.append(GameData.make_monster(Art.ROSTER[i + 5], 0.35, mrng))
		var sim = Sim.new(a, b, 11, {}, {}, {}, [])
		var res: Dictionary = await sim.run()
		# ⚠️ Measure BOTH sides' surviving hp — the first version measured only team A, which was
		# wiped in both runs, so 0 == 0 "proved" care did nothing while proving nothing.
		var a_alive := 0
		var total_hp := 0.0
		for u in a + b:
			if u in a and u.alive: a_alive += 1
			total_hp += maxf(0.0, u.hp)
		results.append({"frames": (res["frames"] as Array).size(), "a_alive": a_alive, "a_hp": total_hp})
	var differs: bool = results[0]["frames"] != results[1]["frames"] or results[0]["a_hp"] != results[1]["a_hp"]
	print("care A/B           : hap0 {frames %d, A alive %d, A hp %.0f} vs hap10 {frames %d, A alive %d, A hp %.0f}  %s" % [
		results[0]["frames"], results[0]["a_alive"], results[0]["a_hp"],
		results[1]["frames"], results[1]["a_alive"], results[1]["a_hp"],
		"OK - care changes the fight" if differs else "*** FAIL - identical"])
	# 4 — weary
	var Sim2 = load("res://scripts/spatial_sim.gd")
	var mrng2 := RandomNumberGenerator.new(); mrng2.seed = 12
	var a2: Array = []; var b2: Array = []
	for i in range(2):
		var m2 = GameData.make_monster(Art.ROSTER[i], 0.35, mrng2)
		m2.stamina = 10.0
		a2.append(m2)
		b2.append(GameData.make_monster(Art.ROSTER[i + 5], 0.35, mrng2))
	var sim2 = Sim2.new(a2, b2, 12, {}, {}, {}, [])
	var res2: Dictionary = await sim2.run()
	var weary_seen := false
	for u in ((res2["frames"] as Array)[0] as Dictionary)["units"]:
		if bool(u.get("weary", false)): weary_seen = true
	print("weary flag         : %s" % ("OK - emitted in frames" if weary_seen else "*** FAIL"))
	get_tree().quit()
