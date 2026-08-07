## BASE CLASS FOR LEAVES — the atomic things a tree actually does ("path to target", "cast
## fireball", "hold position"). Subclasses override `tick(ctx)` and return a result built with the
## inherited `_leaf(status, reason)` helper (never `_mk`/`_wrap` directly — a leaf's path is always
## exactly its own name, and `_leaf` is what guarantees that).
##
## This is where RUNNING earns its keep: a leaf mid-multi-tick action (e.g. walking across a
## 160-wide arena) returns RUNNING every tick until it is actually done, storing whatever progress
## it needs to remember (current destination, a dwell timer) on `ctx.blackboard` — NEVER on `self`,
## since one `BTAction` instance may be ticked for many different monsters sharing the same tree
## definition (see `BTBlackboard`'s doc comment).
extends "res://scripts/ai/bt_node.gd"
class_name BTAction


func tick(_ctx: Object) -> Object:
	push_error("BTAction subclass '%s' did not override tick(ctx)" % node_name)
	return _leaf(FAILURE, "unimplemented action")
