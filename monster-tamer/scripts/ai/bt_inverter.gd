## Flips SUCCESS <-> FAILURE. RUNNING passes through untouched — an in-progress action isn't
## "succeeding" or "failing" yet, so there is nothing to invert.
extends "res://scripts/ai/bt_decorator.gd"
class_name BTInverter


func tick(ctx: Object) -> Object:
	if child == null:
		return _mk(FAILURE, [node_name], "no child")
	var r: Object = child.tick(ctx)
	if r.status == RUNNING:
		return _wrap(RUNNING, r)
	var flipped: int = SUCCESS if r.status == FAILURE else FAILURE
	return _wrap(flipped, r)
