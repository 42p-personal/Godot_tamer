extends Node3D
const Rig = preload("res://scripts/ui/creature_rig.gd")
func _ready() -> void:
	for model in ["dragon", "ghost", "bunny", "fish", "wolf", "giant", "mushroom_king"]:
		var rig = Rig.new()
		add_child(rig)
		var ok: bool = rig.build(model, 4.0)
		await get_tree().process_frame
		var b: AABB = rig._skinned_bounds()
		print("%-14s build=%s scale=%.3f bounds=%.2f x %.2f x %.2f" % [model, str(ok), rig.scale.x, b.size.x, b.size.y, b.size.z])
		rig.queue_free()
	get_tree().quit()
