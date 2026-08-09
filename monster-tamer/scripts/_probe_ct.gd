## Direct unit test of the tree's cleanse override — no sim, no navmesh.
##
## ⚠️ SceneTree, NOT Node — it needs no scene tree, so it must be runnable with `--script`.
## As a Node it popped a BLOCKING MODAL ("doesn't inherit from SceneTree or MainLoop") that
## HANGS an automated run instead of failing it. See COMBAT_SPATIAL_LOG.md, "the mirror of that
## rule". Nav-dependent probes are the opposite case and stay as scenes.
##   godot --headless --path . --script res://scripts/_probe_ct.gd
extends SceneTree
const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const MTree = preload("res://scripts/ai/monster_tree.gd")
const ClassifyLib = preload("res://scripts/classify.gd")
const DeriveLib = preload("res://scripts/derive.gd")
const DeriveMath = preload("res://scripts/derive.gd")

func _mk(nm: String, ms: Array):
	var mi = MonsterInstanceScript.new()
	mi.id = nm; mi.species_id = "test"; mi.species_name = nm; mi.body = "Mammal"
	mi.stats = {"STR": 200.0, "DEX": 200.0, "CON": 200.0, "WIS": 250.0, "INT": 200.0, "CHA": 200.0}
	mi.class_name_ = ClassifyLib.class_for_stats(mi.stats)
	mi.basic_attack = ClassifyLib.basic_attack_for(mi.stats)
	mi.max_hp = DeriveLib.max_hp(200.0); mi.hp = mi.max_hp
	mi.max_mp = DeriveLib.max_mana(250.0, 200.0); mi.mp = mi.max_mp
	mi.moveset = ms
	return mi

func _initialize() -> void:
	var f := FileAccess.open("res://data/data.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()); f.close()
	var by := {}
	for m in d.get("moves", []): by[str(m.get("name"))] = m
	var clarity = by["Clarity"]
	print("=== TREE UNIT TEST: cleanse override ===")
	print("  Clarity: mana=%s cd=%s range=%s target=%s" % [
		clarity.get("mana"), clarity.get("cooldown"), clarity.get("range"), clarity.get("target")])

	var healer = _mk("HEALER", [clarity, by["Scrap"]])
	var ally = _mk("ALLY", [by["Scrap"]])
	var foe = _mk("FOE", [by["Scrap"]])
	print("  healer mp=%.0f  field_mp_cost(Clarity)=%.1f" % [healer.mp, DeriveMath.field_mp_cost(clarity)])

	# stun the ally
	ally.statuses = [{"kind": "stun", "remaining": 3.0, "stacks": 1}]
	print("  ally statuses: %s" % str(ally.statuses))

	var ctx := {
		"unit": healer, "unit_id": 0, "pos": Vector2(10, 44),
		"allies": [ally], "ally_positions": [Vector2(12, 44)],
		"enemies": [foe], "enemy_positions": [Vector2(40, 44)],
		"obstacles": [], "tactics": {}, "personality": {},
		"team_focus_id": -1, "now": 1.0,
		"blackboard": {}, "rng": RandomNumberGenerator.new(),
	}
	var out: Dictionary = MTree.tick(ctx)
	print("\n  tree returned:")
	for k in ["action", "move_name", "target_id", "intent", "reason", "attribution"]:
		print("    %-12s %s" % [k, str(out.get(k, "<missing>"))])
	print("\n  VERDICT: %s" % ("CLEANSE REQUESTED" if str(out.get("move_name","")) == "Clarity"
		else "*** override did not fire ***"))
	quit(0)
