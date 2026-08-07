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
	_test_focus_fire_assist()
	_test_execute_window()
	_test_opportunistic_kick()
	_test_aggression_shapes_engagement()
	_test_smart_regroup()
	_test_bull_through()
	_test_order_seeding()
	_test_big_moment_defined()
	_test_combo_setup_derived()
	_test_wing_variety()
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


func _test_focus_fire_assist() -> void:
	# Two near-equal candidates by score: the WOUNDED one wins (finish what the team started).
	var tree := CombatTree.build({"target_priority": "nearest"})
	var bb := _bb_base()
	bb.set_value("enemies", [
		{"id": "e1", "pos": Vector2(0, 0), "hp": 100, "max_hp": 100, "int_stat": 0, "wis": 0, "con": 0, "threat": 0.0},
		{"id": "e2", "pos": Vector2(1, 0), "hp": 40, "max_hp": 100, "int_stat": 0, "wis": 0, "con": 0, "threat": 0.0},
	])
	_tick(tree, bb, 0)
	_check("focus-fire: near-equal score, the wounded target wins", str(bb.get_value("target_id")) == "e2")
	# But NOT when the wounded one is far outside the score band — assist, not override.
	var tree2 := CombatTree.build({"target_priority": "nearest"})
	var bb2 := _bb_base()
	bb2.set_value("enemies", [
		{"id": "e1", "pos": Vector2(0, 0), "hp": 100, "max_hp": 100, "int_stat": 0, "wis": 0, "con": 0, "threat": 0.0},
		{"id": "e2", "pos": Vector2(15, 0), "hp": 40, "max_hp": 100, "int_stat": 0, "wis": 0, "con": 0, "threat": 0.0},
	])
	_tick(tree2, bb2, 0)
	_check("focus-fire: a distant wounded target does NOT hijack the pick", str(bb2.get_value("target_id")) == "e1")
	# The wishlist `team_dmg` key counts as the damaged signal when present.
	var tree3 := CombatTree.build({"target_priority": "nearest"})
	var bb3 := _bb_base()
	bb3.set_value("enemies", [
		{"id": "e1", "pos": Vector2(0, 0), "hp": 100, "max_hp": 100, "int_stat": 0, "wis": 0, "con": 0, "threat": 0.0},
		{"id": "e2", "pos": Vector2(1, 0), "hp": 90, "max_hp": 90, "team_dmg": 25.0, "int_stat": 0, "wis": 0, "con": 0, "threat": 0.0},
	])
	_tick(tree3, bb3, 0)
	_check("focus-fire: team_dmg marks a target as team-damaged", str(bb3.get_value("target_id")) == "e2")


func _test_execute_window() -> void:
	# Under `reassess` (sticky 1.0) a scorer flip normally switches — but a target below the
	# execute fraction is COMMITTED to, and the reason says "finishing X".
	var tree := CombatTree.build({"target_priority": "weakest"})
	var bb := _bb_base()
	bb.set_value("focus_sticky", 1.0)
	bb.get_value("enemies")[0].hp = 30   # e1 weakest, still ABOVE the execute window
	bb.get_value("enemies")[1].hp = 60
	bb.get_value("enemies")[2].hp = 95
	_tick(tree, bb, 0)
	_check("execute: setup targets the weakest", str(bb.get_value("target_id")) == "e1")
	# e1 drops into the execute window; e2 becomes the scorer's pick — the tree holds e1.
	bb.get_value("enemies")[0].hp = 20
	bb.get_value("enemies")[1].hp = 12
	_tick(tree, bb, 1)
	_check("execute: below 25%% the tree commits even under reassess", str(bb.get_value("target_id")) == "e1")
	_check("execute: the reason says finishing", bb.reason() == "finishing e1")
	# Healed out of the window: reassess resumes and the scorer's pick wins again.
	bb.get_value("enemies")[0].hp = 60
	_tick(tree, bb, 2)
	_check("execute: healed out of the window releases the commit", str(bb.get_value("target_id")) == "e2")


func _test_opportunistic_kick() -> void:
	# My target (tanks -> e3) is not casting, but e2 is casting IN REACH and my kick is up:
	# spend it off-target, then return to the incumbent next tick.
	var tree := CombatTree.build({"target_priority": "tanks"})
	var bb := _bb_base()
	# e2 stands BEHIND me: 4.0 away (inside kick_range 6) but not en route to e3 — so the
	# bull-through interceptor rule leaves the target alone and the kick is genuinely off-target.
	bb.get_value("enemies")[1].pos = Vector2(-24, 0)
	bb.get_value("enemies")[1].casting = true
	bb.set_value("interrupt_ready", true)
	_tick(tree, bb, 0)
	_check("kick: off-target caster in reach gets the interrupt", bb.get_value("req_interrupt") == true)
	_check("kick: the interrupt is aimed at the caster", str(bb.get_value("req_attack")) == "e2")
	_check("kick: the reason names the off-target cast", bb.reason() == "kick the cast on e2 (off-target)")
	# Cast over: the pre-kick incumbent resumes without a re-acquire wobble.
	bb.get_value("enemies")[1].casting = false
	bb.set_value("interrupt_ready", false)
	_tick(tree, bb, 1)
	_check("kick: the pre-kick target resumes next tick", str(bb.get_value("target_id")) == "e3")
	# No interrupt ready -> no kick, no borrowed target.
	var tree2 := CombatTree.build({"target_priority": "tanks"})
	var bb2 := _bb_base()
	bb2.get_value("enemies")[1].pos = Vector2(-16, 0)
	bb2.get_value("enemies")[1].casting = true
	_tick(tree2, bb2, 0)
	_check("kick: no interrupt ready, no kick", bb2.get_value("req_interrupt", false) == false)
	# Caster out of reach -> the kick is not wasted on a sprint.
	var tree3 := CombatTree.build({"target_priority": "tanks"})
	var bb3 := _bb_base()
	bb3.get_value("enemies")[1].casting = true   # e2 at (14,3): ~34 away
	bb3.set_value("interrupt_ready", true)
	_tick(tree3, bb3, 0)
	_check("kick: a caster out of reach is not kicked", bb3.get_value("req_interrupt", false) == false)


func _test_aggression_shapes_engagement() -> void:
	# Arming threshold: at 30% HP a hurt_at of 0.35 arms at Aggression 50 but NOT at 100.
	var t_hi := CombatTree.build({"when_hurt": "fall_back", "hurt_at": 0.35, "target_priority": "nearest"})
	var bb_hi := _bb_base()
	bb_hi.set_value("aggression", 100)
	bb_hi.get_value("self").hp = 30
	_tick(t_hi, bb_hi, 0)
	_check("aggression 100: fights on at 30%% (threshold lowered)", bb_hi.intent_string().begins_with("Combat"))
	var t_mid := CombatTree.build({"when_hurt": "fall_back", "hurt_at": 0.35, "target_priority": "nearest"})
	var bb_mid := _bb_base()
	bb_mid.get_value("self").hp = 30
	_tick(t_mid, bb_mid, 0)
	_check("aggression default: 30%% arms fall back (authored threshold intact)",
		bb_mid.intent_string().begins_with("Fall back"))
	var t_lo := CombatTree.build({"when_hurt": "fall_back", "hurt_at": 0.35, "target_priority": "nearest"})
	var bb_lo := _bb_base()
	bb_lo.set_value("aggression", 0)
	bb_lo.get_value("self").hp = 40
	_tick(t_lo, bb_lo, 0)
	_check("aggression 0: arms EARLY at 40%% (threshold raised)", bb_lo.intent_string().begins_with("Fall back"))
	# Dive depth: aggression 100 lands deeper behind the enemy line than the default.
	var bbd := _bb_base()
	_tick(CombatTree.build({"positional": "dive", "target_priority": "nearest"}), bbd, 0)
	var bbd_hi := _bb_base()
	bbd_hi.set_value("aggression", 100)
	_tick(CombatTree.build({"positional": "dive", "target_priority": "nearest"}), bbd_hi, 0)
	_check("aggression 100: dives deeper", bbd_hi.get_value("req_move_to").x > bbd.get_value("req_move_to").x)
	# Hold: aggression 0 keeps a tighter leash than the authored radius.
	var bbh := _bb_base()
	bbh.set_value("aggression", 0)
	_tick(CombatTree.build({"positional": "hold", "target_priority": "nearest"}), bbh, 0)
	_check("aggression 0: hold discipline tightens the leash",
		bbh.get_value("req_move_to").distance_to(bbh.get_value("home_pos")) <= 6.01)


func _test_smart_regroup() -> void:
	# No enemies, allies alive: regroup on the NEAREST living ally, and say so.
	var tree := CombatTree.build({"target_priority": "nearest"})
	var bb := _bb_base()
	bb.set_value("enemies", [])
	bb.set_value("allies", [
		{"id": "a1", "pos": Vector2(30, 0), "hp": 90, "max_hp": 100},
		{"id": "a2", "pos": Vector2(-15, 2), "hp": 50, "max_hp": 100},
		{"id": "a3", "pos": Vector2(-16, 0), "hp": 0, "max_hp": 100},   # dead: never a rally point
	])
	_tick(tree, bb, 0)
	_check("regroup: rallies on the nearest LIVING ally", bb.get_value("req_move_to") == Vector2(-15, 2))
	_check("regroup: the reason names the ally", bb.reason() == "no target, no order — regrouping on a2")
	# All allies down: the anchor is the fallback, as before.
	var tree2 := CombatTree.build({"target_priority": "nearest"})
	var bb2 := _bb_base()
	bb2.set_value("enemies", [])
	bb2.set_value("allies", [{"id": "a1", "pos": Vector2(30, 0), "hp": 0, "max_hp": 100}])
	_tick(tree2, bb2, 0)
	_check("regroup: all allies down falls back to the anchor",
		bb2.get_value("req_move_to") == bb2.get_value("home_pos"))


func _test_bull_through() -> void:
	# Decision #30: the blocking rule is a TACTIC. e3 stands in reach (5 away, toward the mark);
	# the mark e1 is ~30 away. bull_through=true holds course on the mark; false engages e3.
	var t_bull := CombatTree.build({"target_priority": "marked", "ordered_id": "e1", "bull_through": true})
	var bb := _bb_base()
	bb.get_value("enemies")[2].pos = Vector2(-15, 0)   # e3: 5.0 from me, en route to e1
	_tick(t_bull, bb, 0)
	_check("#30: bull_through holds the ordered target", str(bb.get_value("target_id")) == "e1")
	_check("#30: bull_through keeps the march on the mark",
		bb.get_value("req_move_to") == bb.get_value("target_pos") and bb.get_value("target_pos") == Vector2(10, -5))
	_check("#30: bulling through is said once", bb.reason() == "bulling through e3 to e1")
	# The DEFAULT (no key) is bull_through=true — engage-on-intercept as the ambient rule
	# un-dived every diver and blobbed the quality probe's dive comp; caution is the opt-in.
	var t_def := CombatTree.build({"target_priority": "marked", "ordered_id": "e1"})
	var bbd := _bb_base()
	bbd.get_value("enemies")[2].pos = Vector2(-15, 0)
	_tick(t_def, bbd, 0)
	_check("#30: the DEFAULT bulls through (measured: engage-by-default blobs divers)",
		str(bbd.get_value("target_id")) == "e1")
	var t_block := CombatTree.build({"target_priority": "marked", "ordered_id": "e1", "bull_through": false})
	var bb2 := _bb_base()
	bb2.get_value("enemies")[2].pos = Vector2(-15, 0)
	_tick(t_block, bb2, 0)
	_check("#30: bull_through=false engages the interceptor", str(bb2.get_value("target_id")) == "e3")
	_check("#30: the interception is legible", bb2.reason() == "intercepted — engaging e3")
	# A body BEHIND me is not an interceptor — no swap, even for the cautious tactic.
	var t_back := CombatTree.build({"target_priority": "marked", "ordered_id": "e1", "bull_through": false})
	var bb3 := _bb_base()
	bb3.get_value("enemies")[2].pos = Vector2(-25, 0)   # e3: 5.0 away but behind me
	_tick(t_back, bb3, 0)
	_check("#30: a body behind me is not in the way", str(bb3.get_value("target_id")) == "e1")


func _test_order_seeding() -> void:
	# tactics.ordered_id alone drives `marked` — the sim never fills the bb key.
	var tree := CombatTree.build({"target_priority": "marked", "ordered_id": "e2"})
	var bb := _bb_base()
	_tick(tree, bb, 0)
	_check("orders: tactics.ordered_id seeds the mark end-to-end", str(bb.get_value("target_id")) == "e2")
	# The mark dies: Order-void releases it, and the seed must NOT resurrect the corpse-order.
	bb.get_value("enemies")[1].hp = 0
	_tick(tree, bb, 1)
	_check("orders: dead seeded mark is released", str(bb.get_value("ordered_id")) == "")
	_tick(tree, bb, 2)
	_check("orders: the release sticks — no re-seed next descent",
		str(bb.get_value("ordered_id")) == "" and str(bb.get_value("target_id")) != "e2")


func _test_big_moment_defined() -> void:
	# The moment, derived in-tree: target below 40% opens the capstone window...
	var bb := _bb_base()
	bb.set_value("capstone_ready", true)
	bb.get_value("enemies")[2].hp = 35   # nearest (e3) at 35% — below the 0.40 fraction
	_tick(CombatTree.build({"ability_policy": "hold_big", "target_priority": "nearest"}), bb, 0)
	_check("hold_big: a target below 40%% IS the moment (derived)", bb.get_value("req_cast_allowed") == true)
	# ...and so does a 3-body pack around a healthy target (the AoE payoff)...
	var bb2 := _bb_base()
	bb2.set_value("capstone_ready", true)
	bb2.set_value("enemies", [
		{"id": "e1", "pos": Vector2(5, 2), "hp": 100, "max_hp": 100, "int_stat": 0, "wis": 0, "con": 0, "threat": 0.0},
		{"id": "e2", "pos": Vector2(6, 0), "hp": 100, "max_hp": 100, "int_stat": 0, "wis": 0, "con": 0, "threat": 0.0},
		{"id": "e3", "pos": Vector2(5, 1), "hp": 100, "max_hp": 100, "int_stat": 0, "wis": 0, "con": 0, "threat": 0.0},
	])
	_tick(CombatTree.build({"ability_policy": "hold_big", "target_priority": "nearest"}), bb2, 0)
	_check("hold_big: 3 bodies packed on the target IS the moment (derived)",
		bb2.get_value("req_cast_allowed") == true)
	# ...but a healthy, lone-standing target still banks it (the base bb: 95% hp, 2-body pack).
	var bb3 := _bb_base()
	bb3.set_value("capstone_ready", true)
	_tick(CombatTree.build({"ability_policy": "hold_big", "target_priority": "nearest"}), bb3, 0)
	_check("hold_big: healthy and unpacked is NOT the moment", bb3.get_value("req_cast_allowed") == false)


func _test_combo_setup_derived() -> void:
	# With the setup gate closed (can_apply_setup false), combo casts ONLY on live setup —
	# derived from the target's published statuses when the record carries them.
	var bb := _bb_base()
	bb.set_value("can_apply_setup", false)
	_tick(CombatTree.build({"ability_policy": "combo", "target_priority": "nearest"}), bb, 0)
	_check("combo: no statuses on the target, no cash-in", bb.get_value("req_cast_allowed") == false)
	var bb2 := _bb_base()
	bb2.set_value("can_apply_setup", false)
	bb2.get_value("enemies")[2].statuses = [{"kind": "burn"}]   # nearest (e3) carries the setup
	_tick(CombatTree.build({"ability_policy": "combo", "target_priority": "nearest"}), bb2, 0)
	_check("combo: a status on the target reads as live setup (derived)",
		bb2.get_value("req_cast_allowed") == true)


func _test_wing_variety() -> void:
	# Aggression widens the wing: 100 swings wider than the authored default.
	var bb_def := _bb_base()
	_tick(CombatTree.build({"positional": "wings", "wing_side": 1, "target_priority": "nearest"}), bb_def, 0)
	var bb_hi := _bb_base()
	bb_hi.set_value("aggression", 100)
	_tick(CombatTree.build({"positional": "wings", "wing_side": 1, "target_priority": "nearest"}), bb_hi, 0)
	var tp_y: float = bb_def.get_value("target_pos").y
	_check("wings: aggression 100 swings wider",
		absf(bb_hi.get_value("req_move_to").y - tp_y) > absf(bb_def.get_value("req_move_to").y - tp_y))
	# Crowded wing flips: two enemies squat on the +y wing point of the target (e3 at (5,1),
	# wing point (5,19)) — the wing swings to the -y side instead, and says so.
	var bb_c := _bb_base()
	bb_c.set_value("enemies", [
		{"id": "e1", "pos": Vector2(6, 18), "hp": 100, "max_hp": 100, "int_stat": 0, "wis": 0, "con": 0, "threat": 0.0},
		{"id": "e2", "pos": Vector2(4, 20), "hp": 100, "max_hp": 100, "int_stat": 0, "wis": 0, "con": 0, "threat": 0.0},
		{"id": "e3", "pos": Vector2(5, 1), "hp": 100, "max_hp": 100, "int_stat": 0, "wis": 0, "con": 0, "threat": 0.0},
	])
	_tick(CombatTree.build({"positional": "wings", "wing_side": 1, "target_priority": "nearest"}), bb_c, 0)
	_check("wings: a crowded wing flips sides", bb_c.get_value("req_move_to").y < bb_c.get_value("target_pos").y)
	_check("wings: the flip is legible", bb_c.reason() == "wing crowded — swinging to the other side")


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
