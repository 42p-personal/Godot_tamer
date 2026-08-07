## Repeats its child, returning RUNNING, until the child finally reports FAILURE — at which point
## `BTUntilFail` itself reports SUCCESS ("I kept doing this until it stopped working"). Useful for
## framing a repeated behaviour as a loop rather than a re-entrant Condition+Action pair, e.g. "keep
## kiting while I still out-range them".
extends "res://scripts/ai/bt_decorator.gd"
class_name BTUntilFail


func tick(ctx: Object) -> Object:
	if child == null:
		return _mk(SUCCESS, [node_name])
	var r: Object = child.tick(ctx)
	if r.status == FAILURE:
		return _wrap(SUCCESS, r)
	return _wrap(RUNNING, r)
