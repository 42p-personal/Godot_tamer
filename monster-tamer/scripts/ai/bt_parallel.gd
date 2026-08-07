## TICKS EVERY CHILD, EVERY TICK — no short-circuiting, the only composite where that's true,
## because "run several things at once" is the entire point (e.g. "keep guarding an ally" running
## alongside "decide whether anything urgent overrides that").
##
## Overall status is decided by two independent policies (`REQUIRE_ONE` / `REQUIRE_ALL`), evaluated
## FAILURE-first: if enough children have already failed to make the failure policy true, that is
## decisive regardless of how many others also succeeded. Mirrors the conventional Parallel node
## semantics used by most mainstream behaviour-tree implementations (e.g. Unreal's Parallel task).
##
## Path reporting is necessarily different from every other node here, since more than one child
## can be "active" at once: the surviving (non-FAILURE) children's own path strings are joined into
## one bracketed hop, e.g. `Parallel[Guard ally → Watch flank & Reassess threat]`. `reason` takes
## the first non-empty reason among the surviving children, in fixed child order.
extends "res://scripts/ai/bt_composite.gd"
class_name BTParallel

enum Policy { REQUIRE_ONE, REQUIRE_ALL }

var success_policy: int = Policy.REQUIRE_ALL
var failure_policy: int = Policy.REQUIRE_ONE


func _init(p_name: String = "Parallel", p_children: Array[BTNodeLib] = [],
		p_success_policy: int = Policy.REQUIRE_ALL, p_failure_policy: int = Policy.REQUIRE_ONE) -> void:
	super(p_name, p_children)
	success_policy = p_success_policy
	failure_policy = p_failure_policy


func tick(ctx: Object) -> Object:
	if children.is_empty():
		return _mk(SUCCESS, [node_name])

	var results: Array[Object] = []
	var succeeded := 0
	var failed := 0
	for child in children:
		var r: Object = child.tick(ctx)
		results.append(r)
		if r.status == SUCCESS:
			succeeded += 1
		elif r.status == FAILURE:
			failed += 1

	var overall: int
	if (failure_policy == Policy.REQUIRE_ONE and failed >= 1) \
			or (failure_policy == Policy.REQUIRE_ALL and failed == children.size()):
		overall = FAILURE
	elif (success_policy == Policy.REQUIRE_ONE and succeeded >= 1) \
			or (success_policy == Policy.REQUIRE_ALL and succeeded == children.size()):
		overall = SUCCESS
	else:
		overall = RUNNING

	var branches: Array[String] = []
	var reason := ""
	for r in results:
		if r.status != FAILURE:
			branches.append(r.path_string())
			if reason == "" and r.reason != "":
				reason = r.reason
	var summary: String = "(all failed)" if branches.is_empty() else "(" + " & ".join(branches) + ")"
	var path: Array[String] = [node_name, summary]
	return _mk(overall, path, reason)
