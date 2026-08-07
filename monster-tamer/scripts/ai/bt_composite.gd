## Shared storage + fixed-order iteration for the AND/OR/parallel composites (`BTSelector`,
## `BTSequence`, `BTParallel`).
extends "res://scripts/ai/bt_node.gd"
class_name BTComposite

const BTNodeLib = preload("res://scripts/ai/bt_node.gd")

var children: Array[BTNodeLib] = []


func _init(p_name: String = "Composite", p_children: Array[BTNodeLib] = []) -> void:
	super(p_name)
	children = p_children.duplicate()


func add_child(node: BTNodeLib) -> void:
	children.append(node)


func _bt_children() -> Array:
	var out: Array = []
	for c in children:
		out.append(c)
	return out
