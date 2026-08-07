## PROOF that the weekly tick (scripts/week.gd) fixes "I can still train infinitely."
## Throwaway probe — delete freely. Needs GameData/Career autoloads, hence a SCENE, not
## `--headless --script` (autoloads don't exist under that mode).
##
## Run:
##   P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_week.tscn
extends Node

const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const WeekLib = preload("res://scripts/week.gd")


func _make_monster(id: String) -> Object:
	var sp_id: String = GameData.species_by_id.keys()[0]
	var sp: Dictionary = GameData.species_by_id[sp_id]
	var mi = MonsterInstanceScript.new()
	mi.id = id
	mi.species_id = sp_id
	mi.species_name = sp["name"]
	mi.body = sp["body"]
	mi.favourite_food = "meat"
	mi.hated_food = "fruit"
	for stat in Classify.STATS:
		mi.stats[stat] = float(sp["base"].get(stat, 10.0))
	mi.recompute_class()
	mi.recompute_pools()
	mi.hp = mi.max_hp
	mi.mp = mi.max_mp
	return mi


func _ready() -> void:
	print("=== WEEKLY TICK PROBE (docs/CORE_LOOP_PORT.md §3) ===\n")
	var cap: float = 900.0  # a league cap, standing in for Career.current_stat_cap()
	var league := "Wood"

	# ── 1. 20 weeks of nothing but intensive drills — stamina must hit the floor and gains
	#        must stop responding to stamina malus (the infinite-training bug is dead). ────
	print("--- (1) 20 weeks of INTENSIVE training only (drill: powerlift, STR+/DEX-) ---")
	var mon = _make_monster("probe-1")
	var str_before: float = mon.stats["STR"]
	print("  week | stamina | STR gain this wk | STR total")
	var any_zero_gain_from_stamina := false
	for wk in range(1, 21):
		var pre_str: float = mon.stats["STR"]
		var pre_stamina: float = mon.stamina
		var action := {"kind": "train", "drillId": "powerlift"}
		WeekLib.apply_activity(mon, action, 0, cap, league)
		var gained: float = mon.stats["STR"] - pre_str
		print("  %4d | %7.1f | %17.1f | %9.1f" % [wk, mon.stamina, gained, mon.stats["STR"]])
		if pre_stamina <= 30.0 and gained < 4.0:
			any_zero_gain_from_stamina = true
	print("  stamina floored at 0 and stayed there under repeated intensive drills: %s" % ("YES" if mon.stamina == 0.0 else "NO (%.1f)" % mon.stamina))
	print("  stamina malus visibly suppressed later gains: %s" % ("YES" if any_zero_gain_from_stamina else "NO"))
	print("  total STR gained over 20 weeks: %.1f (would be unbounded under the old free-button bug)\n" % (mon.stats["STR"] - str_before))

	# ── 2. preview vs apply, 50 (monster, week) pairs — must be EXACT. ──────────────────────
	print("--- (2) preview_week vs apply_week — 50 (monster, week) pairs, exact-equality assert ---")
	var mismatches := 0
	for i in range(50):
		var m = _make_monster("probe-2-%d" % i)
		m.career_week = i  # vary the RNG seed key across pairs
		m.happiness = i % 11
		m.stamina = float(20 + (i * 7) % 80)
		var drill_ids := ["weights", "powerlift", "deepmed", "showmanship", "runic"]
		var action := {"kind": "train", "drillId": drill_ids[i % drill_ids.size()]}
		if i % 5 == 0:
			action = {"kind": "rest"}
		elif i % 7 == 0:
			action = {"kind": "excursion"}

		var preview: Dictionary = WeekLib.preview_week(m, action, 100, 0, "", false, 0, cap, league)

		var before_stats: Dictionary = m.stats.duplicate()
		var before_stamina: float = m.stamina
		var before_happiness: int = m.happiness
		var before_gold := 100
		var new_gold: int = WeekLib.apply_week(m, action, before_gold, 0, "", false, 0, cap, league)

		var ok := true
		for stat in before_stats:
			var real_delta: float = m.stats[stat] - before_stats[stat]
			var prev_delta: float = float(preview["statDeltas"].get(stat, 0.0))
			if abs(real_delta - prev_delta) > 0.0001:
				ok = false
				print("  MISMATCH pair %d stat %s: preview %.3f apply %.3f" % [i, stat, prev_delta, real_delta])
		if abs((m.stamina - before_stamina) - float(preview["staminaDelta"])) > 0.0001:
			ok = false
			print("  MISMATCH pair %d stamina: preview %.3f apply %.3f" % [i, float(preview["staminaDelta"]), m.stamina - before_stamina])
		if (m.happiness - before_happiness) != int(preview["happinessDelta"]):
			ok = false
			print("  MISMATCH pair %d happiness: preview %d apply %d" % [i, int(preview["happinessDelta"]), m.happiness - before_happiness])
		if (new_gold - before_gold) != int(preview["goldDelta"]):
			ok = false
			print("  MISMATCH pair %d gold: preview %d apply %d" % [i, int(preview["goldDelta"]), new_gold - before_gold])
		if not ok:
			mismatches += 1
	print("  pairs checked: 50   mismatches: %d   -> %s\n" % [mismatches, "PASS — preview mirrors apply exactly" if mismatches == 0 else "FAIL"])

	# ── 3. gold decreasing with paid food; forage free but costs stamina + happiness ────────
	print("--- (3) feeding: paid food costs gold, forage is free but costs stamina + happiness ---")
	var m3 = _make_monster("probe-3")
	var gold := 100
	var g_before := gold
	gold = WeekLib.apply_week(m3, {"kind": "rest"}, gold, 0, "meat", false, 10, cap, league)
	print("  paid food (meat, 10g): gold %d -> %d  (spent %d)" % [g_before, gold, g_before - gold])

	var m4 = _make_monster("probe-4")
	var stam_before: float = m4.stamina
	var hap_before: int = m4.happiness
	var g4 := 100
	g4 = WeekLib.apply_week(m4, {"kind": "rest"}, g4, 0, "", true, 0, cap, league)
	print("  forage: gold %d -> %d (unchanged: %s)   stamina %.1f -> %.1f   happiness %d -> %d" % [
		100, g4, str(g4 == 100), stam_before, m4.stamina, hap_before, m4.happiness])
	# rest also restores stamina, so isolate forage's cost by comparing against a fed monster resting
	var m5 = _make_monster("probe-5")
	var g5 := 100
	g5 = WeekLib.apply_week(m5, {"kind": "rest"}, g5, 0, "vegetables", false, 10, cap, league)
	print("  (control) fed + rest: happiness %d, stamina %.1f  vs  forage + rest: happiness %d, stamina %.1f" % [
		m5.happiness, m5.stamina, m4.happiness, m4.stamina])
	print("  forage costs stamina+happiness relative to a fed monster: %s" % ("YES" if m4.happiness < m5.happiness and m4.stamina < m5.stamina else "NO"))

	print("\n=== DONE ===")
	get_tree().quit(0)
