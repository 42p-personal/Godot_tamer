## PROBE — does `tactics.guardedAlly` measurably change the "guard" positional intent's behaviour?
##
## `deployment_board.gd::current_guard_targets()` + `tactics_ui.gd::_on_board_changed()` are the
## new producer (2026-08-04) for `orders_a[m]["guardedAlly"]`. `monster_tree.gd::_positional_guard`
## already read the key — it just had nothing writing it, so it always fell back to plain HOLD at
## the guardian's own spawn point (`_positional_hold`, anchored to `home_point`). This probe runs
## the SAME two teams and seed with the ONLY difference being whether `guardedAlly` is set, and
## measures how far the guardian STRAYS FROM ITS OWN SPAWN POINT as its charge advances (ordered
## to `push`) away from that same spawn point.
##
## ⚠️ Why "distance from own spawn" and not "distance to charge": both runs start at the same gap
## (they share a deploy layout), so a gap-based metric only diverges once the charge has moved far
## enough for the two fallback behaviours (hold-at-spawn vs. follow-the-charge) to visibly disagree
## — and a short, lethal 2v2 fight doesn't leave much time for that to build up. Distance-from-own-
## spawn is the more direct measurement of the SAME underlying fact: whether the guardian moves
## when its charge does, or not.
##
## Scene-based (NOT --script) — autoloads aren't reachable under `--script`; this file builds its
## monsters manually the same way `_probe_why.gd` does, so it needs no autoload either, but the
## brief's working pattern is scene-based and this copies it exactly.
extends Node

const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const SpatialSimScript = preload("res://scripts/spatial_sim.gd")
const ClassifyLib = preload("res://scripts/classify.gd")
const DeriveLib = preload("res://scripts/derive.gd")

var _moves: Array = []


func _load() -> void:
	var f := FileAccess.open("res://data/data.json", FileAccess.READ)
	var p = JSON.parse_string(f.get_as_text())
	f.close()
	_moves = p.get("moves", [])


func _mk(nm: String, stats: Dictionary):
	var mi = MonsterInstanceScript.new()
	mi.id = nm; mi.species_id = "test"; mi.species_name = nm; mi.body = "Mammal"
	mi.stats = stats.duplicate()
	mi.class_name_ = ClassifyLib.class_for_stats(mi.stats)
	mi.role = ClassifyLib.role_of_class(mi.class_name_)
	mi.mana_role = ClassifyLib.mana_role_of(mi.stats, mi.class_name_)
	mi.basic_attack = ClassifyLib.basic_attack_for(mi.stats)
	mi.max_hp = DeriveLib.max_hp(mi.stats.get("CON", 0.0)); mi.hp = mi.max_hp
	mi.max_mp = DeriveLib.max_mana(mi.stats.get("WIS", 0.0), mi.stats.get("INT", 0.0)); mi.mp = mi.max_mp
	var sl: Array = []
	for j in range(6):
		sl.append(_moves[j % _moves.size()])
	mi.moveset = sl
	return mi


## High CON, modest STR on both sides — a slow grind rather than a quick kill, so there's real
## TIME for the two fallback behaviours to diverge before the fight ends.
func _build_teams() -> Dictionary:
	var guardian = _mk("GUARDIAN", {"STR": 140.0, "DEX": 120.0, "CON": 600.0, "WIS": 80.0, "INT": 60.0, "CHA": 60.0})
	var charge = _mk("CHARGE", {"STR": 150.0, "DEX": 140.0, "CON": 600.0, "WIS": 60.0, "INT": 60.0, "CHA": 60.0})
	var team_a: Array = [guardian, charge]
	var team_b: Array = [
		_mk("FOE0", {"STR": 130.0, "DEX": 120.0, "CON": 600.0, "WIS": 100.0, "INT": 100.0, "CHA": 100.0}),
		_mk("FOE1", {"STR": 130.0, "DEX": 120.0, "CON": 600.0, "WIS": 100.0, "INT": 100.0, "CHA": 100.0}),
	]
	return {"guardian": guardian, "charge": charge, "team_a": team_a, "team_b": team_b}


## `charge` is ordered to PUSH so it advances away from its own spawn point — the exact condition
## that separates "guard the charge" from "hold at your own spawn".
func _run(label: String, guardian_orders: Dictionary) -> Dictionary:
	var built := _build_teams()
	var guardian = built["guardian"]
	var charge = built["charge"]
	var guardian_spawn: Vector2 = SpatialSimScript.Sp.deploy_positions(2, "A")[0]
	var orders_a := {
		guardian: guardian_orders,
		charge: {"positionalIntent": "push"},
	}
	var sim = SpatialSimScript.new(built["team_a"], built["team_b"], 777,
		{"formation": "tight"}, {"formation": "tight"}, orders_a, [])
	var r: Dictionary = await sim.run()
	var frames: Array = r.get("frames", [])

	var sum_from_spawn := 0.0
	var max_from_spawn := 0.0
	var sum_gap := 0.0
	var last_from_spawn := 0.0
	var last_gap := 0.0
	var n := 0
	var checkpoints: Array = []
	var checkpoint_every: int = maxi(1, frames.size() / 6)
	for i in range(frames.size()):
		var units: Array = frames[i].get("units", [])
		if units.size() < 2:
			continue
		var gpos: Vector2 = units[0]["pos"]
		var cpos: Vector2 = units[1]["pos"]
		var from_spawn: float = gpos.distance_to(guardian_spawn)
		var gap: float = gpos.distance_to(cpos)
		sum_from_spawn += from_spawn
		sum_gap += gap
		max_from_spawn = maxf(max_from_spawn, from_spawn)
		last_from_spawn = from_spawn
		last_gap = gap
		n += 1
		if i % checkpoint_every == 0:
			checkpoints.append("t=%5.1f guardian-from-spawn=%6.2f  guardian-to-charge=%6.2f" % [
				float(frames[i].get("t", 0.0)), from_spawn, gap])

	var avg_from_spawn := (sum_from_spawn / n) if n > 0 else 0.0
	var avg_gap := (sum_gap / n) if n > 0 else 0.0
	print("--- %s ---" % label)
	print("  frames=%d  duration=%.1fs  winner=%s" % [frames.size(), float(r.get("duration", 0.0)), str(r.get("winner", "?"))])
	for c in checkpoints:
		print("  " + c)
	print("  avg guardian-from-own-spawn = %6.2f   max = %6.2f   final = %6.2f" % [avg_from_spawn, max_from_spawn, last_from_spawn])
	print("  avg guardian-to-charge gap  = %6.2f   final = %6.2f" % [avg_gap, last_gap])
	print("")
	return {"avg_from_spawn": avg_from_spawn, "max_from_spawn": max_from_spawn, "avg_gap": avg_gap}


func _ready() -> void:
	_load()
	print("=== PROBE: does tactics.guardedAlly change guard positioning? ===\n")

	var without := await _run("guard, guardedAlly UNSET (falls back to hold at own spawn)",
		{"positionalIntent": "guard"})

	# `guardedAlly` must be an actual MonsterInstance reference, so this run's orders are built
	# out-of-line rather than through `_run()`'s dictionary-literal call sites elsewhere in this
	# file — the charge instance doesn't exist until `_build_teams()` runs inside `_run()`.
	var built := _build_teams()
	var guardian = built["guardian"]
	var charge = built["charge"]
	var guardian_spawn: Vector2 = SpatialSimScript.Sp.deploy_positions(2, "A")[0]
	var orders_a := {
		guardian: {"positionalIntent": "guard", "guardedAlly": charge},
		charge: {"positionalIntent": "push"},
	}
	var sim = SpatialSimScript.new(built["team_a"], built["team_b"], 777,
		{"formation": "tight"}, {"formation": "tight"}, orders_a, [])
	var r: Dictionary = await sim.run()
	var frames: Array = r.get("frames", [])
	var sum_from_spawn := 0.0
	var max_from_spawn := 0.0
	var sum_gap := 0.0
	var last_from_spawn := 0.0
	var last_gap := 0.0
	var n := 0
	var checkpoints: Array = []
	var checkpoint_every: int = maxi(1, frames.size() / 6)
	for i in range(frames.size()):
		var units: Array = frames[i].get("units", [])
		if units.size() < 2:
			continue
		var gpos: Vector2 = units[0]["pos"]
		var cpos: Vector2 = units[1]["pos"]
		var from_spawn: float = gpos.distance_to(guardian_spawn)
		var gap: float = gpos.distance_to(cpos)
		sum_from_spawn += from_spawn
		sum_gap += gap
		max_from_spawn = maxf(max_from_spawn, from_spawn)
		last_from_spawn = from_spawn
		last_gap = gap
		n += 1
		if i % checkpoint_every == 0:
			checkpoints.append("t=%5.1f guardian-from-spawn=%6.2f  guardian-to-charge=%6.2f" % [
				float(frames[i].get("t", 0.0)), from_spawn, gap])
	var avg_from_spawn := (sum_from_spawn / n) if n > 0 else 0.0
	var avg_gap := (sum_gap / n) if n > 0 else 0.0
	print("--- guard, guardedAlly SET (follows its charge) ---")
	print("  frames=%d  duration=%.1fs  winner=%s" % [frames.size(), float(r.get("duration", 0.0)), str(r.get("winner", "?"))])
	for c in checkpoints:
		print("  " + c)
	print("  avg guardian-from-own-spawn = %6.2f   max = %6.2f   final = %6.2f" % [avg_from_spawn, max_from_spawn, last_from_spawn])
	print("  avg guardian-to-charge gap  = %6.2f   final = %6.2f" % [avg_gap, last_gap])

	print("\nSUMMARY")
	print("  WITHOUT guardedAlly: guardian's avg distance from ITS OWN SPAWN = %.2f (max %.2f)" % [without["avg_from_spawn"], without["max_from_spawn"]])
	print("  WITH    guardedAlly: guardian's avg distance from ITS OWN SPAWN = %.2f (max %.2f)" % [avg_from_spawn, max_from_spawn])
	print("  WITHOUT guardedAlly: guardian's avg gap to its charge = %.2f" % without["avg_gap"])
	print("  WITH    guardedAlly: guardian's avg gap to its charge = %.2f (GUARD_LEASH const = 10.0)" % avg_gap)
	get_tree().quit(0)
