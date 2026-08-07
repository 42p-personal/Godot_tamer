## Single-child wrapper base for `BTInverter` / `BTSucceeder` / `BTCondition` / `BTCooldown` /
## `BTUntilFail`.
extends "res://scripts/ai/bt_node.gd"
class_name BTDecorator

var child: Object = null


func _init(p_name: String = "Decorator", p_child: Object = null) -> void:
	super(p_name)
	child = p_child


func _bt_children() -> Array:
	return [] if child == null else [child]
