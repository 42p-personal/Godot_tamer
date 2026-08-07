## SELF-TEST for the behaviour-tree library. Not a monster tree — a TOY tree exercising every node
## type, run headless, asserting the traversal order, the reported active path, and determinism.
##
## Run directly: P:/Godot_v4.7.1-stable_win64.exe --headless --script res://scripts/ai/bt_selftest.gd
## Exit code is the result (0 = all assertions held), matching this project's other headless
## verification scripts (`contract_test.gd`, `_selftest_spatial.gd`).
extends SceneTree

const BTResultLib = preload("res://scripts/ai/bt_result.gd")
const BTSelectorLib = preload("res://scripts/ai/bt_selector.gd")
const BTSequenceLib = preload("res://scripts/ai/bt_sequence.gd")
const BTParallelLib = preload("res://scripts/ai/bt_parallel.gd")
const BTConditionLib = preload("res://scripts/ai/bt_condition.gd")
const BTInverterLib = preload("res://scripts/ai/bt_inverter.gd")
const BTSucceederLib = preload("res://scripts/ai/bt_succeeder.gd")
const BTCooldownLib = preload("res://scripts/ai/bt_cooldown.gd")
const BTUntilFailLib = preload("res://scripts/ai/bt_until_fail.gd")
const BTActionLib = preload("res://scripts/ai/bt_action.gd")
const BTTreeLib = preload("res://scripts/ai/bt_tree.gd")
const BTBlackboardLib = preload("res://scripts/ai/bt_blackboard.gd")

var _failures: Array[String] = []


func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   - ", msg)
	else:
		print("  FAIL - ", msg)
		_failures.append(msg)


# ── Toy leaves ───────────────────────────────────────────────────────────────────────────────

## Simulates a multi-tick "walk to the target" action: RUNNING for `ticks_needed - 1` ticks, then
## SUCCESS. Progress lives on the BLACKBOARD, never on `self` — proving a single node instance is
## safe to tick for more than one monster (see bt_blackboard.gd's doc comment).
class PathToTargetAction extends BTActionLib:
	var ticks_needed: int = 3

	func tick(ctx: Object) -> Object:
		var progress: int = ctx.blackboard.get_int("path_progress", 0) + 1
		ctx.blackboard.set_value("path_progress", progress)
		if progress >= ticks_needed:
			ctx.blackboard.set_value("path_progress", 0)
			return _leaf(SUCCESS, "arrived")
		return _leaf(RUNNING, "pathing (%d/%d)" % [progress, ticks_needed])


class IdleAction extends BTActionLib:
	func tick(_ctx: Object) -> Object:
		return _leaf(SUCCESS, "nothing to do")


class DefendAllyAction extends BTActionLib:
	func tick(_ctx: Object) -> Object:
		return _leaf(SUCCESS, "")


class AlwaysSucceedAction extends BTActionLib:
	func tick(_ctx: Object) -> Object:
		return _leaf(SUCCESS, "")


class AlwaysFailAction extends BTActionLib:
	func tick(_ctx: Object) -> Object:
		return _leaf(FAILURE, "")


## Succeeds twice, then fails forever after — for exercising BTUntilFail.
class FlakyAction extends BTActionLib:
	func tick(ctx: Object) -> Object:
		var n: int = ctx.blackboard.get_int("flaky_count", 0) + 1
		ctx.blackboard.set_value("flaky_count", n)
		if n <= 2:
			return _leaf(SUCCESS, "attempt %d" % n)
		return _leaf(FAILURE, "attempt %d — gave up" % n)


# ── Tree builder — called twice (fresh nodes + fresh blackboard) for the determinism check ─────

func _build_combat_tree(bb: Object) -> Object:
	var taunt_predicate := func(ctx: Object) -> bool:
		return ctx.blackboard.get_bool("taunted", false)
	var taunt_reason := func(_ctx: Object) -> String:
		return "taunted by Aegisox"
	var has_target_predicate := func(_ctx: Object) -> bool:
		return true

	var engage_seq := BTSequenceLib.new("Engage", [
		BTConditionLib.new("Has target?", has_target_predicate),
		PathToTargetAction.new("Path to target"),
	])
	var taunt_branch := BTConditionLib.new(
		"Taunted?", taunt_predicate, DefendAllyAction.new("Defend ally"), taunt_reason)
	var root := BTSelectorLib.new("Combat", [taunt_branch, engage_seq, IdleAction.new("Idle")])
	return BTTreeLib.new(root, "TestMonster", bb)


## Ticks the standard 4-step script (engage → engage → arrive → taunt-interrupt) and returns the
## describe() string for each tick, for both the live run and the determinism-replay run.
func _run_script(tree: Object, bb: Object) -> Array[String]:
	var out: Array[String] = []
	for i in range(3):
		var r: Object = tree.tick(0.1)
		out.append(r.describe())
	bb.set_value("taunted", true)
	var r4: Object = tree.tick(0.1)
	out.append(r4.describe())
	return out


func _initialize() -> void:
	print("=== Behaviour tree self-test ===\n")

	# ── 1. Build + dump the toy "Combat" tree ───────────────────────────────────────────────
	var bb_a := BTBlackboardLib.new()
	var tree_a := _build_combat_tree(bb_a)
	print("Tree shape:")
	print(tree_a.dump())
	print("")

	var dupes: Array[String] = tree_a.validate_names()
	_check(dupes.is_empty(), "no duplicate node names in the toy tree (found: %s)" % [dupes])

	# ── 2. Traversal + active path across a 4-tick script ───────────────────────────────────
	var r1: Object = tree_a.tick(0.1)
	print("tick 1: ", r1.describe())
	_check(r1.status == BTResultLib.RUNNING, "tick1 status is RUNNING (still pathing)")
	_check(r1.path == ["Combat", "Engage", "Path to target"],
		"tick1 active path is Combat -> Engage -> Path to target")

	var r2: Object = tree_a.tick(0.1)
	print("tick 2: ", r2.describe())
	_check(r2.status == BTResultLib.RUNNING, "tick2 status is RUNNING (still pathing)")

	var r3: Object = tree_a.tick(0.1)
	print("tick 3: ", r3.describe())
	_check(r3.status == BTResultLib.SUCCESS, "tick3 status is SUCCESS (arrived, Engage completes)")
	_check(r3.path == ["Combat", "Engage", "Path to target"], "tick3 active path unchanged")
	_check(r3.reason == "arrived", "tick3 reason bubbles up from the leaf")

	bb_a.set_value("taunted", true)
	var r4: Object = tree_a.tick(0.1)
	print("tick 4: ", r4.describe())
	_check(r4.status == BTResultLib.SUCCESS, "tick4 status is SUCCESS (defend)")
	_check(r4.path == ["Combat", "Taunted?", "Defend ally"],
		"tick4 pre-empted to the taunt branch — proves reactive interrupt with zero extra machinery")
	_check(r4.reason == "taunted by Aegisox",
		"tick4 reason is the CONDITION's reason, not the leaf's empty one")
	print("")

	# ── 3. Determinism: same inputs, same traversal, byte for byte ─────────────────────────
	var bb_b := BTBlackboardLib.new()
	var tree_b := _build_combat_tree(bb_b)
	# Replay the identical 3-tick-then-taunt script against a fully independent tree/blackboard.
	var replay: Array[String] = []
	for i in range(3):
		replay.append(tree_b.tick(0.1).describe())
	bb_b.set_value("taunted", true)
	replay.append(tree_b.tick(0.1).describe())

	var live: Array[String] = [r1.describe(), r2.describe(), r3.describe(), r4.describe()]
	_check(replay == live, "determinism: independent tree + blackboard reproduces the exact same traversal")
	print("")

	# ── 4. BTCooldown ────────────────────────────────────────────────────────────────────────
	var bb_c := BTBlackboardLib.new()
	var cd_root := BTCooldownLib.new("Fire cooldown", 0.25, AlwaysSucceedAction.new("Fire"))
	var cd_tree := BTTreeLib.new(cd_root, "CooldownTest", bb_c)
	var cd_statuses: Array[String] = []
	for i in range(6):
		var r: Object = cd_tree.tick(0.1)
		cd_statuses.append(BTResultLib.status_name(r.status))
	print("cooldown sequence (0.25s cd, 0.1s dt, 6 ticks): ", cd_statuses)
	_check(cd_statuses == ["SUCCESS", "FAILURE", "FAILURE", "FAILURE", "SUCCESS", "FAILURE"],
		"cooldown blocks re-fire until it elapses, then fires again")
	print("")

	# ── 5. BTUntilFail ───────────────────────────────────────────────────────────────────────
	var bb_d := BTBlackboardLib.new()
	var uf_root := BTUntilFailLib.new("Retry until it stops working", FlakyAction.new("Flaky"))
	var uf_tree := BTTreeLib.new(uf_root, "UntilFailTest", bb_d)
	var uf_statuses: Array[String] = []
	for i in range(3):
		uf_statuses.append(BTResultLib.status_name(uf_tree.tick(0.1).status))
	print("until-fail sequence: ", uf_statuses)
	_check(uf_statuses == ["RUNNING", "RUNNING", "SUCCESS"],
		"BTUntilFail runs while the child succeeds, then reports SUCCESS the tick it finally fails")
	print("")

	# ── 6. BTParallel ────────────────────────────────────────────────────────────────────────
	var bb_e := BTBlackboardLib.new()
	var slow := PathToTargetAction.new("Slow task")
	slow.ticks_needed = 2
	var par_root := BTParallelLib.new("Both", [AlwaysSucceedAction.new("Fast task"), slow],
		BTParallelLib.Policy.REQUIRE_ALL, BTParallelLib.Policy.REQUIRE_ONE)
	var par_tree := BTTreeLib.new(par_root, "ParallelTest", bb_e)
	var p1: Object = par_tree.tick(0.1)
	print("parallel tick1: ", p1.describe())
	_check(p1.status == BTResultLib.RUNNING, "parallel tick1 RUNNING (slow task still going, all-success not yet met)")
	var p2: Object = par_tree.tick(0.1)
	print("parallel tick2: ", p2.describe())
	_check(p2.status == BTResultLib.SUCCESS, "parallel tick2 SUCCESS (both children now succeeded)")
	print("")

	# ── 7. BTInverter / BTSucceeder ─────────────────────────────────────────────────────────
	var bb_f := BTBlackboardLib.new()
	var inv_tree := BTTreeLib.new(BTInverterLib.new("Not", AlwaysSucceedAction.new("Always ok")), "InvertTest", bb_f)
	_check(inv_tree.tick(0.1).status == BTResultLib.FAILURE, "BTInverter flips a SUCCESS child to FAILURE")

	var bb_g := BTBlackboardLib.new()
	var suc_tree := BTTreeLib.new(BTSucceederLib.new("Force ok", AlwaysFailAction.new("Always bad")), "SucceedTest", bb_g)
	_check(suc_tree.tick(0.1).status == BTResultLib.SUCCESS, "BTSucceeder forces a FAILURE child to SUCCESS")
	print("")

	# ── Verdict ──────────────────────────────────────────────────────────────────────────────
	if _failures.is_empty():
		print("PASS  all behaviour-tree self-test assertions held")
	else:
		print("FAIL  %d assertion(s) failed:" % _failures.size())
		for f in _failures:
			print("  - ", f)
	quit(0 if _failures.is_empty() else 1)
