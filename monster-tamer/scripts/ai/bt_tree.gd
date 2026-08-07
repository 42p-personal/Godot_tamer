## THE TREE'S FRONT DOOR — the public entry point the next stream (the actual monster tree) and
## whatever drives it (most likely `spatial_sim.gd`'s AI-decide phase) is expected to use.
##
## Owns a root `BTNode` + a per-monster `BTBlackboard`. `tick()` is the whole API surface most
## callers need: it builds this tick's `BTContext` and returns the root's `BTResult`, which already
## carries everything docs/AUTOBATTLER_DESIGN.md §6 asks for — the live intent label
## (`result.path_string()`) and the decision-log reason (`result.reason`) — with no extra
## reconstruction step, because the tree built both while it was actually deciding.
##
## ── Quick usage ──────────────────────────────────────────────────────────────────────────────
##   const BTTreeLib = preload("res://scripts/ai/bt_tree.gd")
##   var tree := BTTreeLib.new(my_root_node, "Grivvel")
##   var result := tree.tick(Spatial.DT, my_seeded_rng, my_agent_bundle)
##   print(result.path_string())   # "Combat → Engage → Path to target"
##   print(result.reason)          # "order: Break the Casters"
## ──────────────────────────────────────────────────────────────────────────────────────────────
extends RefCounted
class_name BTTree

const BTNodeLib = preload("res://scripts/ai/bt_node.gd")
const BTBlackboardLib = preload("res://scripts/ai/bt_blackboard.gd")
const BTContextLib = preload("res://scripts/ai/bt_context.gd")

var root: BTNodeLib
var blackboard: BTBlackboardLib
var tree_name: String = "Tree"


func _init(p_root: BTNodeLib, p_name: String = "Tree", p_blackboard: BTBlackboardLib = null) -> void:
	root = p_root
	tree_name = p_name
	blackboard = p_blackboard if p_blackboard != null else BTBlackboardLib.new()


## `agent` is whatever payload the tree's leaves expect (untyped — see `BTContext`). `rng` is
## caller-owned and seeded; pass the SAME `RandomNumberGenerator` every tick for a given monster if
## any leaf draws from it, so a replay reproduces byte-for-byte.
func tick(dt: float, rng: RandomNumberGenerator = null, agent: Variant = null) -> Object:
	var ctx: BTContextLib = BTContextLib.new(blackboard, dt, rng, agent)
	return root.tick(ctx)


## Walks the tree collecting every `node_name` and reports duplicates. `BTCooldown` (and any future
## node that needs per-instance scratch state) keys its blackboard entry off `node_name`, so a
## duplicate silently corrupts a sibling's state. Cheap, deterministic — run once after building a
## tree, not something the tick loop itself pays for.
func validate_names() -> Array[String]:
	var seen: Dictionary = {}
	var dupes: Array[String] = []
	_walk_names(root, seen, dupes)
	return dupes


func _walk_names(node: Object, seen: Dictionary, dupes: Array[String]) -> void:
	if node == null:
		return
	var n: String = node.node_name
	if seen.has(n):
		if not dupes.has(n):
			dupes.append(n)
	else:
		seen[n] = true
	for c in node._bt_children():
		_walk_names(c, seen, dupes)


## A readable indented dump of the tree's static shape — handy for a sanity check when a subtree
## is first wired up, and for the self-test below.
func dump() -> String:
	var lines: Array[String] = []
	_dump_node(root, 0, lines)
	return "\n".join(lines)


func _dump_node(node: Object, depth: int, lines: Array[String]) -> void:
	if node == null:
		return
	lines.append("  ".repeat(depth) + "- " + node.node_name)
	for c in node._bt_children():
		_dump_node(c, depth + 1, lines)
