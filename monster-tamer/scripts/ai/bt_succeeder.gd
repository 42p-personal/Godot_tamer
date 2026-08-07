## Always reports SUCCESS once its child settles — RUNNING still passes through, so a multi-tick
## child gets to finish rather than being forced to a false SUCCESS mid-flight. Useful for "attempt
## this, but a failed attempt shouldn't fail the whole branch" (an optional flourish nobody should
## care if it whiffs).
extends "res://scripts/ai/bt_decorator.gd"
class_name BTSucceeder


func tick(ctx: Object) -> Object:
	if child == null:
		return _mk(SUCCESS, [node_name])
	var r: Object = child.tick(ctx)
	if r.status == RUNNING:
		return _wrap(RUNNING, r)
	return _wrap(SUCCESS, r)
