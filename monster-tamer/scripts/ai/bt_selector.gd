## FIRST CHILD THAT DOES NOT FAIL WINS — re-evaluated from index 0 EVERY TICK. No persisted
## "currently running child" memory.
##
## ⚠️ THIS IS A DELIBERATE CHOICE, NOT AN OVERSIGHT. It is what gives the tree its reactivity for
## free: a higher-priority branch (a taunt condition, "is my ordered target dead") pre-empts
## whatever a lower-priority branch was doing mid-RUNNING, the instant it becomes true, with zero
## extra interrupt machinery. This is exactly the mechanism `docs/AUTOBATTLER_DESIGN.md` §8 #27-28
## needs for its short, closed list of urgent overrides (taunted / ordered target dead / about to
## die with an escape / destination unreachable) and §10's "every tick resolves to a named branch;
## no idle state without a reason". A lower-priority multi-tick action resumes its own progress via
## whatever it stored in the BLACKBOARD (see `BTBlackboard`), never via anything this node
## remembers — so re-entering that branch later picks up exactly where it left off.
##
## Empty `children` returns FAILURE (the standard "OR of nothing" convention).
extends "res://scripts/ai/bt_composite.gd"
class_name BTSelector


func tick(ctx: Object) -> Object:
	for child in children:
		var r: Object = child.tick(ctx)
		if r.status != FAILURE:
			return _wrap(r.status, r)
	return _mk(FAILURE, [node_name])
