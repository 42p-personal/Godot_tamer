## A single node's TICK OUTCOME: status + the ACTIVE PATH (root-to-here, for whichever branch
## produced this status) + an optional REASON string. Immutable once built.
##
## ⚠️ THIS IS WHY `tick()` RETURNS AN OBJECT INSTEAD OF A BARE STATUS INT. Legibility
## (docs/AUTOBATTLER_DESIGN.md §6/§9) requires the tree to hand back the live intent label
## ("Combat → Engage → Path to target") and a decision-log reason ("taunted by Aegisox") — and
## building both by pure composition of return values, rather than by mutating some shared
## "current path" on a context object, is what guarantees a Selector's REJECTED siblings can never
## leak their own reasoning into the branch that actually won. Every `BTNode.tick()` call
## constructs exactly one of these (via the inherited `_mk`/`_leaf`/`_wrap` helpers) and nothing
## else is read to explain what just happened.
##
## Zero dependencies on purpose — `BTNode` preloads THIS file (to construct results), so this file
## must never preload `bt_node.gd` back, or the two would form a preload cycle.
extends RefCounted
class_name BTResult

const SUCCESS := 0
const FAILURE := 1
const RUNNING := 2

static func status_name(status: int) -> String:
	match status:
		SUCCESS:
			return "SUCCESS"
		FAILURE:
			return "FAILURE"
		RUNNING:
			return "RUNNING"
		_:
			return "UNKNOWN(%d)" % status


var status: int
var path: Array[String]   # root-to-here, in order, for the ACTIVE branch only — never a full
                           # traversal log of every node visited, just the one that "won".
var reason: String        # "" when nothing on this branch set one


func _init(p_status: int, p_path: Array[String], p_reason: String = "") -> void:
	status = p_status
	path = p_path
	reason = p_reason


func path_string() -> String:
	return " → ".join(path)


## One-line debug/log form: `Combat → Engage → Path to target [RUNNING] (pathing (2/3))`
func describe() -> String:
	var tail: String = "" if reason == "" else "  (%s)" % reason
	return "%s [%s]%s" % [path_string(), status_name(status), tail]
