## COMBAT TREE PROBE — headless acceptance test for combat_tree.gd. Exit code is the result.
## Each check pins a DESIGN DECISION, not an implementation detail: the urgent closed list
## (#27), fight_on's sovereignty (#28), the anti-flee-return dwell (§10), the four tactic axes
## (§2), lateral geometry for wings/dive (§2B), and twin-run determinism.
extends SceneTree

const BT = preload("res://scripts/ai/bt.gd")
const CombatTree = preload("res://scripts/ai/combat_tree.gd")
const SimLib = preload("res://scripts/sim/sim.gd")   # AOE LAYER checks drive sim functions
const KitLib = preload("res://scripts/sim/kit.gd")   # directly — no nav is ever touched

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
	_test_healers_priority()
	_test_sim_taunt()
	_test_aoe_falloff()
	_test_sim_aoe()
	_test_sim_thorns()
	_test_kit_aoe_acceptance()
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


func _test_healers_priority() -> void:
	# §2A `healers`: highest recent healing OUTPUT among the living. e1 has healed hardest —
	# it wins over e2, the statistically bigger caster (int 80 + wis 70), because heal_out is
	# EVIDENCE and stats are only suspicion.
	var tree := CombatTree.build({"target_priority": "healers"})
	var bb := _bb_base()
	bb.get_value("enemies")[0].heal_out = 60.0   # e1: the working healer
	bb.get_value("enemies")[2].heal_out = 10.0   # e3: dribbled a heal once
	_tick(tree, bb, 0)
	_check("healers: highest heal_out wins", str(bb.get_value("target_id")) == "e1")
	_check("healers: the pick is legible", bb.reason() == "target: e1 (healers)")
	# DEFINED FALLBACK: nobody has healed yet -> casters scoring (a healer that has not healed
	# is still a caster). e2's int+wis carries it, exactly as the `casters` priority would.
	var tree2 := CombatTree.build({"target_priority": "healers"})
	var bb2 := _bb_base()
	_tick(tree2, bb2, 0)
	_check("healers: nobody healed yet falls back to casters scoring", str(bb2.get_value("target_id")) == "e2")
	# The same fallback when the sim-filled key is present but zero everywhere.
	var tree3 := CombatTree.build({"target_priority": "healers"})
	var bb3 := _bb_base()
	for e in bb3.get_value("enemies"):
		e.heal_out = 0.0
	_tick(tree3, bb3, 0)
	_check("healers: all-zero heal_out is the same fallback", str(bb3.get_value("target_id")) == "e2")
	# A dead healer's output is not a target: e1 healed most but is down -> e3 (the only other
	# enemy that has healed) takes the priority.
	var tree4 := CombatTree.build({"target_priority": "healers"})
	var bb4 := _bb_base()
	bb4.get_value("enemies")[0].heal_out = 60.0
	bb4.get_value("enemies")[0].hp = 0
	bb4.get_value("enemies")[2].heal_out = 10.0
	_tick(tree4, bb4, 0)
	_check("healers: a dead healer is nobody's target", str(bb4.get_value("target_id")) == "e3")


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


# ═══ AOE LAYER — sim-side scenario checks, nav-free ══════════════════════════════════════════
# These drive sim.gd's AOE-layer functions DIRECTLY on hand-built units: no setup(), no
# NavService, no scene tree needed — which is what qualifies them for this --script probe.


## A minimal sim with hand-built units — every key the driven functions read, none the nav
## needs. Mirrors setup()'s unit shape; units end id-sorted (the determinism order).
func _mk_sim(seed_val: int, specs: Array) -> RefCounted:
	var s = SimLib.new()
	s.rng = RandomNumberGenerator.new()
	s.rng.seed = seed_val
	for sp in specs:
		var bb := BT.Blackboard.new()
		bb.rng = s.rng
		s.units.append({"id": str(sp.id), "team": str(sp.team), "pos": sp.pos, "home": sp.pos,
			"stats": sp.get("stats", {"STR": 50, "CON": 30, "WIS": 20, "INT": 60}),
			"hp": 200.0, "max_hp": 200, "speed": 8.0, "tactics": {},
			"nerve": 50, "aggression": 50, "focus_sticky": 1.3, "tree": null, "bb": bb,
			"path": PackedVector2Array(), "path_i": 0, "cooldown": 0, "has_attacked": false,
			"alive": true, "mp": 100.0, "max_mp": 100, "kit": [], "cds": {},
			"casting": {}, "statuses": [], "cc_resist": 0.0, "last_cc_at": -999.0,
			"mods": sp.get("mods", []), "dmg_from": {}, "kite_ticks": 80,
			"facing": Vector2(1, 0), "vel": Vector2.ZERO, "slot_angle": 0.0, "slot_ok": false})
	s.units.sort_custom(func(a, b): return a.id < b.id)
	return s


func _test_sim_taunt() -> void:
	# A landed tauntForce compels the victim onto the caster; the tree's Urgent → Taunted
	# branch answers off the sim-filled bb key with NO tree edit; the compulsion expires with
	# its authored duration and breaks the moment the taunter falls (battle.ts:944-946, 982).
	var s = _mk_sim(5, [{"id": "a1", "team": "A", "pos": Vector2(0, 0)},
		{"id": "b1", "team": "B", "pos": Vector2(10, 0)}])
	var a1 = s._unit("a1")
	var b1 = s._unit("b1")
	var ev: Array = []
	s._apply_taunt(a1, b1, {"effects": {"tauntForce": true, "duration": 2}}, ev)
	_check("taunt: a landed tauntForce emits 'taunted' with its duration",
		ev.size() == 1 and str(ev[0].kind) == "taunted" and float(ev[0].seconds) > 0.0
		and str(ev[0].from) == "a1" and str(ev[0].to) == "b1")
	_check("taunt: the victim is compelled onto the caster", s._taunt_source_of(b1) == "a1")
	s._fill_bb(b1)
	_check("taunt: the sim fills the tree's `taunted_by` key",
		str(b1.bb.get_value("taunted_by")) == "a1")
	var tree := CombatTree.build({"target_priority": "nearest"})
	tree.tick(b1.bb, 0)
	_check("taunt: the tree swaps the swing onto the taunter (no tree edit needed)",
		str(b1.bb.get_value("req_attack")) == "a1" and str(b1.bb.get_value("target_id")) == "a1")
	_check("taunt: the compelled unit CLOSES on the taunter",
		Vector2(b1.bb.get_value("req_move_to")) == Vector2(0, 0))
	# Expiry by time…
	var until: float = float(b1.taunt.until)
	s.tick_now = int(until / 0.1) + 1
	_check("taunt: the compulsion expires with its authored duration", s._taunt_source_of(b1) == "")
	# …and by the taunter falling (battle.ts:982 — compulsion breaks).
	s.tick_now = 0
	a1.alive = false
	_check("taunt: the taunter falling breaks the compulsion", s._taunt_source_of(b1) == "")


func _test_aoe_falloff() -> void:
	# The falloff FORMULA, pinned to core.ts:74/95: 1 body x1.00, 3 bodies x0.90 each (total
	# x2.70 — "weak into one body, strong into three"), floored at 0.40 however wide the pack.
	_check("aoe falloff: one body takes the full hit", is_equal_approx(SimLib.aoe_falloff(1), 1.0))
	_check("aoe falloff: three bodies take x0.90 each (x2.70 total, never x3)",
		is_equal_approx(SimLib.aoe_falloff(3), 0.9))
	_check("aoe falloff: the floor holds at 0.40 into any pack",
		is_equal_approx(SimLib.aoe_falloff(15), 0.4) and is_equal_approx(SimLib.aoe_falloff(100), 0.4))


func _mk_nova() -> Dictionary:
	# An inline allEnemies test move: variance 0 so per-hit damage is exact; accuracy 100 so
	# nothing ever misses (acc roll <= 1.0 always passes) — crits stay the only rng effect.
	return {"name": "Nova", "kind": "cast", "stat": "INT", "channel": "magic",
		"move": {"name": "Nova", "power": 40, "accuracy": 100, "type": "damage",
			"channel": "magic", "target": "allEnemies", "variance": 0.0},
		"range": 12.0, "cooldown": 4.0, "mana": 0.0, "cast_time": 1.0, "min_range": 0.0}


func _run_aoe(specs: Array) -> Array:
	var s = _mk_sim(9, specs)
	var ev: Array = []
	s._resolve_aoe(s._unit("a1"), _mk_nova(), ev)
	return ev


func _test_sim_aoe() -> void:
	# One isolated body vs three bunched — same caster, same seed. The burst is range-gated
	# from the CASTER (the legacy spatial_sim.gd:1077-1086 rule): the two far bodies in the
	# first roster are never touched.
	var lone: Array = [{"id": "a1", "team": "A", "pos": Vector2.ZERO},
		{"id": "b1", "team": "B", "pos": Vector2(6, 0)},
		{"id": "b2", "team": "B", "pos": Vector2(40, 0)},
		{"id": "b3", "team": "B", "pos": Vector2(40, 5)}]
	var packed: Array = [{"id": "a1", "team": "A", "pos": Vector2.ZERO},
		{"id": "b1", "team": "B", "pos": Vector2(6, 0)},
		{"id": "b2", "team": "B", "pos": Vector2(6, 3)},
		{"id": "b3", "team": "B", "pos": Vector2(6, -3)}]
	var ev1 := _run_aoe(lone)
	var ev3 := _run_aoe(packed)
	var hits1: Array = ev1.filter(func(e): return str(e.kind) == "cast_done")
	var hits3: Array = ev3.filter(func(e): return str(e.kind) == "cast_done")
	_check("aoe: bodies outside the authored range are never touched (caster-range gate)",
		hits1.size() == 1 and ev1.filter(func(e): return str(e.get("to", "")) in ["b2", "b3"]).is_empty())
	_check("aoe: three bunched bodies are ALL hit", hits3.size() == 3)
	var total1 := 0
	for e in hits1:
		total1 += int(e.dmg)
	var total3 := 0
	for e in hits3:
		total3 += int(e.dmg)
	_check("aoe: three bunched bodies take MORE in total than one isolated (%d > %d)" % [total3, total1],
		total3 > total1)
	# Falloff visible per hit: compare non-crit hits only (crit is the one rng left in play).
	var nc1: Array = hits1.filter(func(e): return not bool(e.crit))
	var nc3: Array = hits3.filter(func(e): return not bool(e.crit))
	var per_hit_ok := not nc1.is_empty() and not nc3.is_empty()
	if per_hit_ok:
		for e in nc3:
			if int(e.dmg) >= int(nc1[0].dmg):
				per_hit_ok = false
	_check("aoe: falloff visible — each of three takes LESS than the lone target", per_hit_ok)
	# Twin runs, same seed: identical event streams (per-target draws in unit-id order).
	_check("aoe determinism: twin runs are byte-identical",
		JSON.stringify(_run_aoe(packed)) == JSON.stringify(ev3))


func _test_sim_thorns() -> void:
	# A thorny defender punishes a landed melee basic with FLAT reflect through a REFLECT
	# event — never a second resolve_strike — so thorny-vs-thorny cannot loop (battle.ts:
	# 1281-1284: `attacker.hp -= target.thornsFlat`, flat and unmitigated).
	var s = _mk_sim(3, [
		{"id": "a1", "team": "A", "pos": Vector2(0, 0),
			"mods": [{"thorns": 8.0, "until": 999.0, "src": "Riposte"}]},
		{"id": "b1", "team": "B", "pos": Vector2(4, 0),
			"mods": [{"thorns": 16.0, "until": 999.0, "src": "Retaliate"}]}])
	var a1 = s._unit("a1")
	var b1 = s._unit("b1")
	a1.bb.set_value("req_attack", "b1")
	var ev: Array = []
	for i in 10:   # 95-acc basic: swing until one lands (cooldown reset by hand)
		a1.cooldown = 0
		s._execute_attack(a1, ev)
		if not ev.filter(func(e): return str(e.kind) == "strike").is_empty():
			break
	var strikes: Array = ev.filter(func(e): return str(e.kind) == "strike")
	var reflects: Array = ev.filter(func(e): return str(e.kind) == "thorns")
	_check("thorns: a landed melee hit reflects the authored FLAT damage (16, b1 -> a1)",
		strikes.size() == 1 and reflects.size() == 1 and int(reflects[0].dmg) == 16
		and str(reflects[0].from) == "b1" and str(reflects[0].to) == "a1")
	_check("thorns: the reflect comes straight off hp — unmitigated, no second strike",
		is_equal_approx(float(a1.hp), 200.0 - 16.0))
	_check("thorns: thorny-vs-thorny cannot chain — ONE reflect per landed hit, ever",
		reflects.size() == 1)
	# Non-melee hits do not prick themselves on armour they never touch (melee-gated).
	var ev2: Array = []
	s._reflect_thorns(a1, b1, {"channel": "magic"}, {"hit": true, "dmg": 10}, ev2)
	_check("thorns: a non-melee hit does not reflect", ev2.is_empty())


func _test_kit_aoe_acceptance() -> void:
	# The AOE LAYER's kit round: tauntForce, thorns self-buffs and allEnemies moves all build
	# from data.json; the remaining loud skip is exactly the one genuinely inexpressible move.
	var moves: Array = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/data.json"))["moves"]
	_check("kit: tauntForce builds (Taunt — the sim compels, the tree answers)",
		KitLib.build(["Taunt"], moves).size() == 1)
	_check("kit: the taunting wall builds (Bulwark's Challenge — allEnemies + tauntForce + guard)",
		KitLib.build(["Bulwark's Challenge"], moves).size() == 1)
	_check("kit: allEnemies damage builds (Cleave)", KitLib.build(["Cleave"], moves).size() == 1)
	_check("kit: thorns self/control buffs build (Retaliate, Zone of Control)",
		KitLib.build(["Retaliate", "Zone of Control"], moves).size() == 2)
	_check("kit: allEnemies debuff builds (Demoralize — AoE geometry is live)",
		KitLib.build(["Demoralize"], moves).size() == 1)
	_check("kit: the one genuinely inexpressible move still skips loudly (Firewall)",
		KitLib.build(["Firewall"], moves).size() == 0)
