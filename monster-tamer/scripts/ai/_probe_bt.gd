## BT FRAMEWORK PROBE — headless acceptance test for bt.gd. Exit code is the result.
## Asserts the properties the AI build stands on: priority order, sequence gating, utility
## stickiness, deterministic tie-breaks, subtree swapping, intent/reason emission, and
## bit-identical decisions across two fresh runs.
extends SceneTree

const BT = preload("res://scripts/ai/bt.gd")

var _fails := 0


func _check(name: String, ok: bool) -> void:
	if ok:
		print("  ok  ", name)
	else:
		_fails += 1
		print("  FAIL ", name)


func _init() -> void:
	_test_selector_priority()
	_test_sequence_gating()
	_test_intent_and_log()
	_test_utility_sticky()
	_test_subtree_swap()
	_test_determinism()
	print("BT PROBE %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(1 if _fails > 0 else 0)


func _bb() -> BT.Blackboard:
	var bb := BT.Blackboard.new()
	bb.rng = RandomNumberGenerator.new()
	bb.rng.seed = 7
	return bb


func _act(label: String, result: int, hits: Array) -> BT.Action:
	return BT.Action.new(label, func(_bb):
		hits.append(label)
		return result)


func _test_selector_priority() -> void:
	var hits: Array = []
	var tree := BT.BehaviourTree.new(BT.Selector.new("Root", [
		BT.Sequence.new("Urgent", [
			BT.Condition.new("threatened?", func(bb): return bb.get_value("threat", false)),
			_act("Flee", BT.SUCCESS, hits),
		]),
		_act("Fight", BT.SUCCESS, hits),
	]))
	var bb := _bb()
	tree.tick(bb, 0)
	_check("selector: default branch when condition false", hits == ["Fight"])
	bb.set_value("threat", true)
	hits.clear()
	tree.tick(bb, 1)
	_check("selector: priority branch preempts when condition flips", hits == ["Flee"])


func _test_sequence_gating() -> void:
	var hits: Array = []
	var tree := BT.BehaviourTree.new(BT.Sequence.new("Combo", [
		_act("StepA", BT.SUCCESS, hits),
		_act("StepB", BT.RUNNING, hits),
		_act("StepC", BT.SUCCESS, hits),
	]))
	var r := tree.tick(_bb(), 0)
	_check("sequence: RUNNING child holds the sequence", r == BT.RUNNING and hits == ["StepA", "StepB"])


func _test_intent_and_log() -> void:
	var hits: Array = []
	var tree := BT.BehaviourTree.new(BT.Selector.new("Combat", [
		BT.Sequence.new("Engage", [
			BT.Condition.new("", func(bb): return bb.get_value("enemy", true)),
			_act("Path to target", BT.RUNNING, hits),
		]),
	]))
	var bb := _bb()
	for t in 5:
		tree.tick(bb, t)
	_check("intent: the active branch is the label chain",
		bb.intent_string() == "Combat → Engage → Path to target")
	_check("log: repeated identical intent logs ONCE", bb.decision_log().size() == 1)
	bb.set_value("enemy", false)
	tree.tick(bb, 5)
	_check("intent survives a tick with no successful action (last committed stands)",
		bb.intent_string() == "Combat → Engage → Path to target")


func _test_utility_sticky() -> void:
	var hits: Array = []
	# Two targets with data-driven scores; incumbent keeps the pick while within stickiness.
	var bb := _bb()
	bb.set_value("score_a", 1.0)
	bb.set_value("score_b", 0.8)
	bb.set_value("focus_sticky", 1.5)
	var util := BT.UtilitySelector.new("Target", [
		_act("A", BT.SUCCESS, hits),
		_act("B", BT.SUCCESS, hits),
	], [
		func(b): return b.get_value("score_a", 0.0),
		func(b): return b.get_value("score_b", 0.0),
	], "focus_sticky")
	var tree := BT.BehaviourTree.new(util)
	tree.tick(bb, 0)
	_check("utility: highest score wins", hits == ["A"])
	# B edges ahead, but not past the incumbent's stickiness (1.1 < 1.0 * 1.5).
	bb.set_value("score_b", 1.1)
	hits.clear()
	tree.tick(bb, 1)
	_check("utility: stickiness holds the incumbent against a small edge", hits == ["A"])
	# B far ahead — past stickiness, the switch happens and the reason says so.
	bb.set_value("score_b", 2.0)
	hits.clear()
	tree.tick(bb, 2)
	_check("utility: a real lead beats stickiness", hits == ["B"])
	_check("reason: the switch is explained", bb.reason().begins_with("Target: B"))


func _test_subtree_swap() -> void:
	var hits: Array = []
	var slot := BT.SubtreeSlot.new()
	var tree := BT.BehaviourTree.new(BT.Selector.new("Root", [
		slot,
		_act("Default", BT.SUCCESS, hits),
	]))
	tree.register_slot("approach", slot)
	tree.tick(_bb(), 0)
	_check("slot: empty slot falls through to default", hits == ["Default"])
	tree.mount("approach", _act("Dive the backline", BT.SUCCESS, hits))
	hits.clear()
	tree.tick(_bb(), 1)
	_check("slot: mounted tactic subtree preempts default", hits == ["Dive the backline"])
	tree.mount("approach", _act("Hold the line", BT.SUCCESS, hits))
	hits.clear()
	tree.tick(_bb(), 2)
	_check("slot: remount swaps behaviour in place", hits == ["Hold the line"])


## Two fresh trees, same seeded inputs drifting over 200 ticks -> identical decision logs.
func _run_for_log(seed_val: int) -> String:
	var bb := _bb()
	bb.rng.seed = seed_val
	var hits: Array = []
	var util := BT.UtilitySelector.new("Target", [
		_act("A", BT.SUCCESS, hits), _act("B", BT.SUCCESS, hits), _act("C", BT.SUCCESS, hits),
	], [
		func(b): return b.get_value("sa", 0.0),
		func(b): return b.get_value("sb", 0.0),
		func(b): return b.get_value("sc", 0.0),
	], "sticky")
	var tree := BT.BehaviourTree.new(BT.Selector.new("Combat", [util]))
	bb.set_value("sticky", 1.3)
	for t in 200:
		bb.set_value("sa", bb.rng.randf())
		bb.set_value("sb", bb.rng.randf())
		bb.set_value("sc", bb.rng.randf())
		tree.tick(bb, t)
	return JSON.stringify(bb.decision_log())


func _test_determinism() -> void:
	var a := _run_for_log(1234)
	var b := _run_for_log(1234)
	var c := _run_for_log(4321)
	_check("determinism: same seed, two fresh runs, identical decision log", a == b)
	_check("determinism guard: different seed actually diverges (probe not vacuous)", a != c)
