## ALL CHILDREN MUST SUCCEED, evaluated in fixed order. Like `BTSelector`, this is REACTIVE /
## memoryless — every tick restarts from child 0 rather than resuming a remembered index. A
## `BTCondition` placed early in a sequence is therefore genuinely re-checked every tick (e.g. "is
## my target still alive?" before "path to it"), which is what makes an ordered-target-died urgent
## override fall naturally out of the tree's SHAPE instead of needing bespoke handling anywhere.
##
## ⚠️ THE TRADE-OFF, STATED HONESTLY. A non-idempotent, INSTANT (SUCCESS-in-one-tick) action placed
## BEFORE a later RUNNING sibling will re-run every tick while that sibling is still in progress.
## Authors of the actual monster tree should keep any step before a RUNNING sibling either
## idempotent (safe to repeat) or gated behind a `BTCondition`/`BTCooldown` so repetition is
## harmless. This mirrors the trade every reactive priority-selector game AI makes — the
## alternative (a memory-based sequence that remembers its running index) would also need its own
## reset story for the moment a `BTSelector` above it interrupts and later re-enters this branch,
## which is materially more machinery than a foundational library should own on day one. Build a
## memory-based variant later if a real branch in the monster tree genuinely needs it.
##
## Empty `children` returns SUCCESS (the standard "AND of nothing" convention).
extends "res://scripts/ai/bt_composite.gd"
class_name BTSequence


func tick(ctx: Object) -> Object:
	if children.is_empty():
		return _mk(SUCCESS, [node_name])
	var last: Object = null
	for child in children:
		last = child.tick(ctx)
		if last.status != SUCCESS:
			return _wrap(last.status, last)
	return _wrap(SUCCESS, last)
