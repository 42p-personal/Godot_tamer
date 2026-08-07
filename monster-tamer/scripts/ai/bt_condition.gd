## Gates a branch behind a predicate. `predicate` is `Callable(ctx) -> bool`, evaluated fresh EVERY
## tick — never cached. This is what makes an urgent override (taunted / target dead / destination
## unreachable, docs/AUTOBATTLER_DESIGN.md §8 #27) interrupt a RUNNING sibling: the enclosing
## `BTSelector` re-tries this gate every tick, and a `BTCondition` that flips to false makes it fail
## immediately without waiting for the child to finish.
##
## `reason_fn`, if given, is `Callable(ctx) -> String` and explains WHY the gate opened (e.g.
## "taunted by Aegisox"). It wins over anything the gated child itself reports — see `BTNode._wrap`
## — since the gate is usually the more meaningful explanation for a player-facing decision log.
##
## Works equally well with NO child, as a bare pass/fail leaf inside a `BTSequence` (e.g.
## `BTCondition.new("Has a living target?", predicate)`), which is the common case in practice —
## most conditions gate a `BTSequence` step rather than a whole subtree.
extends "res://scripts/ai/bt_decorator.gd"
class_name BTCondition

var predicate: Callable = Callable()
var reason_fn: Callable = Callable()


func _init(p_name: String = "Condition", p_predicate: Callable = Callable(),
		p_child: Object = null, p_reason_fn: Callable = Callable()) -> void:
	super(p_name, p_child)
	predicate = p_predicate
	reason_fn = p_reason_fn


func tick(ctx: Object) -> Object:
	var passed: bool = predicate.call(ctx) if predicate.is_valid() else false
	if not passed:
		return _mk(FAILURE, [node_name])
	var gate_reason: String = String(reason_fn.call(ctx)) if reason_fn.is_valid() else ""
	if child == null:
		return _mk(SUCCESS, [node_name], gate_reason)
	var r: Object = child.tick(ctx)
	return _wrap(r.status, r, gate_reason)
