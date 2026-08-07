## PER-MONSTER KEYED SCRATCH STORE — what the tree remembers between ticks: current target,
## current destination, dwell timers, "am I mid-action" flags, and so on
## (docs/AUTOBATTLER_DESIGN.md §9). One blackboard belongs to ONE monster's tree instance.
##
## ⚠️ THIS IS WHERE RUNNING STATE LIVES, NEVER ON A NODE INSTANCE. A single `BTNode` object (a
## `BTAction` subclass, a `BTCooldown` decorator, ...) may be shared across a whole tree DEFINITION
## that gets ticked for many different monsters — so anything a node needs to remember from one
## tick to the next belongs here, keyed by that node's own `node_name`
## (see `BTNode.node_name`'s doc comment on why sibling names must be distinct).
##
## Plain `Dictionary` underneath, matching this codebase's established preference for Dictionaries
## over ad-hoc Resource types for loosely-structured runtime state (see `tactics.gd`). Methods are
## deliberately NOT named `get`/`set`/`has`/`erase` — those already exist as built-in `Object`
## methods for generic property access, and shadowing them on a scripted class is exactly the kind
## of footgun `.claude/docs/technical-preferences.md` already warns this project has hit before.
extends RefCounted
class_name BTBlackboard

var _data: Dictionary = {}


func set_value(key: String, value: Variant) -> void:
	_data[key] = value


func get_value(key: String, default: Variant = null) -> Variant:
	return _data.get(key, default)


func has_value(key: String) -> bool:
	return _data.has(key)


func erase_value(key: String) -> bool:
	return _data.erase(key)


func clear_all() -> void:
	_data.clear()


# ── Typed convenience getters — thin coercions over get_value, since blackboard entries are most
# often read back as a specific type (a timer as float, a flag as bool, a target id as int). ────

func get_float(key: String, default: float = 0.0) -> float:
	return float(_data.get(key, default))


func get_int(key: String, default: int = 0) -> int:
	return int(_data.get(key, default))


func get_bool(key: String, default: bool = false) -> bool:
	return bool(_data.get(key, default))


func get_string(key: String, default: String = "") -> String:
	return String(_data.get(key, default))


func get_vector2(key: String, default: Vector2 = Vector2.ZERO) -> Vector2:
	var v: Variant = _data.get(key, default)
	return v if v is Vector2 else default


func keys() -> Array:
	return _data.keys()
