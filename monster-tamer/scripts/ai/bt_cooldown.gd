## Blocks its child from (re-)starting for `seconds` after the child last completed with SUCCESS.
## A child already RUNNING is exempt from the gate — this decorator tracks "is my child currently
## mid-flight" separately from "how much cooldown time is left", so it can never interrupt an
## action it already let start. Cooldown starts the instant the child reports SUCCESS, whether that
## happens instantly or after however many RUNNING ticks it needed; a child that ultimately FAILS
## (including one that was RUNNING and then failed) costs no cooldown, since nothing was actually
## accomplished.
##
## ⚠️ STATE LIVES IN THE BLACKBOARD (keyed by this node's own `node_name`), NOT on the node
## instance — the same tree/node object may be ticked for many monsters, each with its own
## blackboard, without their cooldowns colliding. This is exactly why `BTNode.node_name` must be
## unique per tree; see `BTTree.validate_names()`.
extends "res://scripts/ai/bt_decorator.gd"
class_name BTCooldown

var seconds: float = 1.0


func _init(p_name: String, p_seconds: float, p_child: Object = null) -> void:
	super(p_name, p_child)
	seconds = p_seconds


func tick(ctx: Object) -> Object:
	var bb: Object = ctx.blackboard
	var key_active: String = "bt/%s/active" % node_name
	var key_remaining: String = "bt/%s/remaining" % node_name

	if bb.get_bool(key_active, false):
		if child == null:
			bb.set_value(key_active, false)
			return _mk(FAILURE, [node_name], "no child")
		var running_r: Object = child.tick(ctx)
		if running_r.status == RUNNING:
			return _wrap(RUNNING, running_r)
		bb.set_value(key_active, false)
		if running_r.status == SUCCESS:
			bb.set_value(key_remaining, seconds)
		return _wrap(running_r.status, running_r)

	var remaining: float = bb.get_float(key_remaining, 0.0)
	if remaining > 0.0:
		bb.set_value(key_remaining, maxf(0.0, remaining - ctx.dt))
		return _mk(FAILURE, [node_name], "on cooldown (%.1fs left)" % remaining)

	if child == null:
		return _mk(FAILURE, [node_name], "no child")
	var r: Object = child.tick(ctx)
	if r.status == RUNNING:
		bb.set_value(key_active, true)
		return _wrap(RUNNING, r)
	if r.status == SUCCESS:
		bb.set_value(key_remaining, seconds)
		return _wrap(SUCCESS, r)
	return _wrap(FAILURE, r)
