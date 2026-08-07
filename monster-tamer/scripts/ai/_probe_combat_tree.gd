## COMBAT TREE PROBE — headless acceptance test for combat_tree.gd. Exit code is the result.
## Each check pins a DESIGN DECISION, not an implementation detail: the urgent closed list
## (#27), fight_on's sovereignty (#28), the anti-flee-return dwell (§10), the four tactic axes
## (§2), lateral geometry for wings/dive (§2B), and twin-run determinism.
extends SceneTree

const BT = preload("res://scripts/ai/bt.gd")
const CombatTree = preload("res://scripts/ai/combat_tree.gd")

var _fails := 0


func _check(name: String, ok: bool) -> void:
	if ok:
		print("  ok  ", name)
	else:
		_fails += 1
		print("  FAIL ", name)


func _bb_base() -> BT.Blackboard:
	var bb := BT.Blackboard.new()
	bb.rng = RandomNumberGenerator.new()
	bb.rng.seed = 11
	bb.set_value("self", {"id": "me", "pos": Vector2(-20, 0), "hp": 100, "max_hp": 100, "speed": 4.0})
	bb.set_value("enemies", [
		{"id": "e1", "pos": Vector2(10, -5), "hp": 80, "max_hp": 100, "int_stat": 10, "wis": 10, "con": 60, "threat": 5.0},
		{"id": "e2", "pos": Vector2(14, 3), "hp": 30, "max_hp": 100, "int_stat": 80, "wis": 70, "con": 20, "threat": 1.0},
		{"id": "e3", "pos": Vector2(5, 1), "hp": 95, "max_hp": 100, "int_stat": 20, "wis": 15, "con": 90, "threat": 9.0},
	])
	bb.set_value("allies", [{"id": "a1", "pos": Vector2(-18, 4), "hp": 90, "max_hp": 100}])
	bb.set_value("home_pos", Vector2(-22, 0))
	bb.set_value("safe_pos", Vector2(-30, 0))
	bb.set_value("enemy_line_x", 12.0)
	return bb


func _tick(tree: BT.BehaviourTree, bb: BT.Blackboard, t: int) -> int:
	bb.set_value("_tick_now", t)
	return tree.tick(bb, t)


func _init() -> void:
	_test_axis_a_priorities()
	_test_commitment()
	_test_urgent_taunt()
	_test_order_void()
	_test_fight_on_sovereignty()
	_test_fallback_dwell()
	_test_positional_geometry()
	_test_ability_policy()
	_test_mode_and_order_slots()
	_test_no_idle_without_reason()
	_test_determinism()
	print("COMBAT TREE PROBE %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(1 if _fails > 0 else 0)


func _test_axis_a_priorities() -> void:
	for expect in [["nearest", "e3"], ["weakest", "e2"], ["casters", "e2"], ["tanks", "e3"], ["threat", "e3"]]:
		var tree := CombatTree.build({"target_priority": expect[0]})
		var bb := _bb_base()
		_tick(tree, bb, 0)
		_check("axis A: %s -> %s" % [expect[0], expect[1]], str(bb.get_value("target_id")) == str(expect[1]))


func _test_commitment() -> void:
	# sticky: incumbent holds when the scorer would switch; reassess (1.0) switches freely.
	var tree := CombatTree.build({"target_priority": "weakest"})
	var bb := _bb_base()
	bb.set_value("focus_sticky", 1.5)
	_tick(tree, bb, 0)
	var first: String = str(bb.get_value("target_id"))
	# e1 becomes the weakest now — but the incumbent should hold under stickiness.
	bb.get_value("enemies")[0].hp = 10
	_tick(tree, bb, 1)
	_check("commitment: sticky holds the incumbent", str(bb.get_value("target_id")) == first)
	bb.set_value("focus_sticky", 1.0)
	_tick(tree, bb, 2)
	_check("commitment: reassess switches to the new weakest", str(bb.get_value("target_id")) == "e1")


func _test_urgent_taunt() -> void:
	var tree := CombatTree.build({"target_priority": "casters"})
	var bb := _bb_base()
	bb.set_value("taunted_by", "e3")
	_tick(tree, bb, 0)
	_check("urgent: taunt overrides target priority", str(bb.get_value("req_attack")) == "e3")
	_check("urgent: taunt intent is legible", bb.intent_string() == "Urgent → Taunted → Answer the taunt")
	_check("urgent: taunt reason names the taunter", bb.reason() == "taunted by e3")


func _test_order_void() -> void:
	var tree := CombatTree.build({"target_priority": "marked"})
	var bb := _bb_base()
	bb.set_value("ordered_id", "e2")
	_tick(tree, bb, 0)
	_check("axis A: marked follows the order", str(bb.get_value("target_id")) == "e2")
	# The ordered target dies: the urgent branch releases the mark, combat retargets next tick.
	bb.get_value("enemies")[1].hp = 0
	_tick(tree, bb, 1)
	_check("urgent: dead order is released", str(bb.get_value("ordered_id")) == "")
	_tick(tree, bb, 2)
	_check("combat resumes on a live target after release", str(bb.get_value("target_id")) != "e2")


func _test_fight_on_sovereignty() -> void:
	# Decision #28: fight_on has NO death-door branch — at 5% HP with an escape open, it fights.
	var tree := CombatTree.build({"when_hurt": "fight_on", "target_priority": "nearest"})
	var bb := _bb_base()
	bb.get_value("self").hp = 5
	bb.set_value("escape_open", true)
	_tick(tree, bb, 0)
	_check("#28: fight_on ignores death's door — the order is sovereign",
		str(bb.get_value("req_attack", "")) != "" and bb.get_value("req_move_to", null) != bb.get_value("safe_pos"))
	# And the same state on fall_back DOES take the escape.
	var tree2 := CombatTree.build({"when_hurt": "fall_back", "target_priority": "nearest"})
	var bb2 := _bb_base()
	bb2.get_value("self").hp = 5
	bb2.set_value("escape_open", true)
	_tick(tree2, bb2, 0)
	_check("#28: fall_back at death's door takes the escape",
		bb2.get_value("req_move_to") == bb2.get_value("safe_pos"))


func _test_fallback_dwell() -> void:
	var tree := CombatTree.build({"when_hurt": "fall_back", "hurt_at": 0.35, "target_priority": "nearest"})
	var bb := _bb_base()
	bb.set_value("nerve", 50)
	bb.set_value("fallback_dwell_ticks", 10)
	bb.get_value("self").hp = 30
	_tick(tree, bb, 0)
	_check("fall back arms at the hurt threshold", bb.intent_string().begins_with("Fall back"))
	# Healed above threshold mid-dwell: MUST keep falling back (anti flee-return).
	bb.get_value("self").hp = 60
	_tick(tree, bb, 3)
	_check("dwell: healing mid-dwell does not flip it back into the fight",
		bb.intent_string().begins_with("Fall back"))
	# Dwell over but not steadied: still out.
	_tick(tree, bb, 30)
	_check("dwell over but not steadied: stays out", bb.intent_string().begins_with("Fall back"))
	# Steadied after dwell: re-engages.
	bb.set_value("steadied", true)
	_tick(tree, bb, 31)
	_check("steadied after dwell: re-engages", bb.intent_string().begins_with("Combat"))


func _test_positional_geometry() -> void:
	# push aims at the target; wings aims LATERALLY off it; dive aims BEHIND the enemy line.
	var bbp := _bb_base()
	_tick(CombatTree.build({"positional": "push", "target_priority": "nearest"}), bbp, 0)
	var push_dest: Vector2 = bbp.get_value("req_move_to")
	var bbw := _bb_base()
	_tick(CombatTree.build({"positional": "wings", "wing_side": 1, "target_priority": "nearest"}), bbw, 0)
	var wing_dest: Vector2 = bbw.get_value("req_move_to")
	var bbd := _bb_base()
	_tick(CombatTree.build({"positional": "dive", "target_priority": "nearest"}), bbd, 0)
	var dive_dest: Vector2 = bbd.get_value("req_move_to")
	_check("push: straight at the target", push_dest == bbp.get_value("target_pos"))
	_check("wings: genuinely lateral (the anti-blob axis)", absf(wing_dest.y - push_dest.y) >= 15.0)
	_check("dive: lands BEHIND the enemy line", dive_dest.x > bbd.get_value("enemy_line_x"))
	var bbh := _bb_base()
	_tick(CombatTree.build({"positional": "hold", "target_priority": "nearest"}), bbh, 0)
	var hold_dest: Vector2 = bbh.get_value("req_move_to")
	_check("hold: never strays past the hold radius of home",
		hold_dest.distance_to(bbh.get_value("home_pos")) <= 8.01)
	var bbg := _bb_base()
	bbg.set_value("guard_id", "a1")
	_tick(CombatTree.build({"positional": "guard", "target_priority": "nearest"}), bbg, 0)
	_check("guard: stations on the charge", bbg.get_value("req_move_to") == Vector2(-18, 4))


func _test_ability_policy() -> void:
	var bb := _bb_base()
	bb.set_value("capstone_ready", true)
	_tick(CombatTree.build({"ability_policy": "hold_big", "target_priority": "nearest"}), bb, 0)
	_check("hold_big: banks the capstone outside the moment", bb.get_value("req_cast_allowed") == false)
	bb.set_value("big_moment", true)
	_tick(CombatTree.build({"ability_policy": "hold_big", "target_priority": "nearest"}), bb, 1)
	_check("hold_big: spends when the moment comes", bb.get_value("req_cast_allowed") == true)


func _test_mode_and_order_slots() -> void:
	var tree := CombatTree.build({"target_priority": "nearest"})
	var bb := _bb_base()
	tree.mount("order", BT.Action.new("Break the casters", func(b):
		b.set_value("req_attack", "e2")
		b._reason = "order: Break the Casters"
		return BT.RUNNING))
	_tick(tree, bb, 0)
	_check("order slot: a mounted order preempts default combat", str(bb.get_value("req_attack")) == "e2")
	_check("order slot: the reason is the order", bb.reason() == "order: Break the Casters")
	# Mode slot outranks the order slot (decision #38: modes inject subtrees above orders).
	tree.mount("mode", BT.Action.new("Hold the hill", func(_b): return BT.RUNNING))
	_tick(tree, bb, 1)
	_check("mode slot: outranks the order", bb.intent_string() == "Hold the hill")


func _test_no_idle_without_reason() -> void:
	var tree := CombatTree.build({"target_priority": "nearest"})
	var bb := _bb_base()
	bb.set_value("enemies", [])
	_tick(tree, bb, 0)
	_check("§10: no enemies still resolves to a NAMED branch", bb.intent_string() == "Regroup")
	_check("§10: and the reason says why", bb.reason().begins_with("no target"))


func _run_scenario() -> String:
	var tree := CombatTree.build({"target_priority": "weakest", "when_hurt": "fall_back",
		"positional": "wings", "wing_side": -1, "ability_policy": "combo", "hurt_at": 0.35})
	var bb := _bb_base()
	bb.set_value("focus_sticky", 1.3)
	bb.set_value("nerve", 70)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for t in 300:
		# A drifting fight: hp wobbles, an enemy dies, a taunt lands and lifts.
		bb.get_value("self").hp = clampi(int(bb.get_value("self").hp) + rng.randi_range(-4, 3), 1, 100)
		var es: Array = bb.get_value("enemies")
		for e in es:
			e.hp = clampi(int(e.hp) + rng.randi_range(-3, 2), 0, 100)
		bb.set_value("taunted_by", "e3" if t % 97 == 40 else "")
		bb.set_value("steadied", rng.randf() < 0.1)
		_tick(tree, bb, t)
	return JSON.stringify(bb.decision_log())


func _test_determinism() -> void:
	var a := _run_scenario()
	var b := _run_scenario()
	_check("determinism: 300-tick scenario, twin runs, identical decision log", a == b)
	_check("probe not vacuous: the scenario produced real decisions", a.length() > 100)
