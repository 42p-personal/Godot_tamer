## ⚠️ SUPERSEDED (2026-08-07, user decision): the AI is being REWRITTEN CLEAN on
## scripts/ai/bt.gd + combat_tree.gd + scripts/sim/sim.gd, with WoW-arena as the explicit
## reference. the bt_* library stays LIVE (spatial_sim.gd still drives the game screens) until the
## rewrite reaches parity and the renderer switches streams — then delete it. Mine it for
## proven logic (dwells, peel, sticky holds); do not extend it.
## THE BEHAVIOUR-TREE LIBRARY — base node type + tick machinery. Generic infrastructure only:
## composites, decorators, leaves and the plumbing that makes them legible. The actual monster
## tree (which branches exist, what they mean tactically) is a separate, later piece of work built
## ON TOP of this file — see docs/AUTOBATTLER_DESIGN.md §9/§12.
##
## ⚠️ LEGIBILITY IS STRUCTURAL, NOT BOLTED ON. Every `tick()` returns a `BTResult` carrying the
## ACTIVE PATH (node names from root to whichever leaf actually ran/succeeded this tick) and an
## optional REASON any node on that path may set. `_wrap()` builds this by prepending a node's own
## name to whatever its WINNING child reported — pure composition of return values, never shared
## mutable state — so a rejected sibling can never leak its reasoning into the branch that won.
## `docs/AUTOBATTLER_DESIGN.md` §9 is explicit that this is *why* a behaviour tree was chosen over
## a flat utility scorer: the active branch IS the explanation, and bolting that on after the fact
## (reconstructing intent from scores) is exactly the failure mode being avoided.
##
## ⚠️ DETERMINISM: no `randf()`, no frame `delta`, anywhere in this library. `BTContext.dt` is the
## caller-supplied fixed step; `BTContext.rng` is caller-injected. Composites iterate `children` in
## the fixed array order they were built in.
##
## ⚠️ CROSS-FILE REFERENCES USE `preload()`, NEVER A BARE `class_name` LOOKUP, and every subclass
## in this library `extends` its parent BY RES PATH (e.g. `extends "res://scripts/ai/bt_node.gd"`)
## rather than `extends BTNode`. This project's global script-class cache is COLD under
## `--headless --script` and during early autoload boot, so a bare class-name reference fails to
## parse in that state — already hit more than once elsewhere in this codebase (see
## `.claude/docs/technical-preferences.md`). Two specific patterns used throughout this library —
## aliasing a constant from a preloaded script (`const SUCCESS := BTResultLib.SUCCESS`) and a
## typed array of a preloaded custom class (`Array[BTNodeLib]`) — were verified to parse and run
## correctly against this exact Godot 4.7.1 binary via a throwaway headless probe before being
## relied on here, rather than assumed to work from memory of older Godot versions.
extends RefCounted
class_name BTNode

const BTResultLib = preload("res://scripts/ai/bt_result.gd")

const SUCCESS := BTResultLib.SUCCESS
const FAILURE := BTResultLib.FAILURE
const RUNNING := BTResultLib.RUNNING


## Human-readable, and LOAD-BEARING, not cosmetic: this is what appears in the active-path
## breadcrumb and the decision log. It also doubles as the blackboard-key prefix any node uses for
## its own scratch state (see `BTCooldown`) — so **sibling nodes within one tree must be given
## distinct names**. `BTTree.validate_names()` checks this and reports duplicates.
var node_name: String = "Node"


func _init(p_name: String = "Node") -> void:
	node_name = p_name


## Every subclass overrides this. Must return a `BTResult` — build one with `_mk`/`_leaf`/`_wrap`
## below, never `BTResultLib.new()` directly, so the path/reason composition rules stay uniform
## across the whole tree.
func tick(_ctx: Object) -> Object:
	return _mk(FAILURE, [node_name], "tick() not implemented on " + node_name)


## Structural children, for TOOLING ONLY (name-uniqueness validation, tree dumps) — never consulted
## by `tick()` itself, which always walks `children`/`child` directly. Leaves return empty;
## `BTComposite`/`BTDecorator` override it.
func _bt_children() -> Array:
	return []


func _mk(status: int, path: Array[String], reason: String = "") -> Object:
	return BTResultLib.new(status, path, reason)


## For LEAVES: the path is exactly this node's own name — a leaf never has children to prepend.
func _leaf(status: int, reason: String = "") -> Object:
	return _mk(status, [node_name], reason)


## For COMPOSITES/DECORATORS: prepend this node's name to whichever child result is the winning/
## deciding one this tick. `reason_override`, if non-empty, wins over the child's own reason — e.g.
## a `BTCondition` gate reports ITS reason ("taunted by Aegisox") ahead of whatever the gated child
## itself says, since the gate is usually the more meaningful explanation for a decision log.
func _wrap(status: int, child_result: Object, reason_override: String = "") -> Object:
	var path: Array[String] = [node_name]
	path.append_array(child_result.path)
	var reason: String = reason_override if reason_override != "" else child_result.reason
	return _mk(status, path, reason)
