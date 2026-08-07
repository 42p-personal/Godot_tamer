## Does the torso twist ATTACH and actually rotate the spine? ⚠️ This proves WIRING, never LOOK —
## a rig can twist by the right number of degrees about the wrong axis and corkscrew. Eyes only.
extends Node3D
const Rig = preload("res://scripts/ui/creature_rig.gd")

## Angle of the bone's own X axis projected onto the ground plane. ⚠️ NOT `basis.get_euler().y` —
## a quadruped's spine lies HORIZONTAL, which is precisely where euler decomposition gimbals and
## reports a few degrees for a 53° twist. The first version of this probe did exactly that and the
## code looked broken when it was the measurement that was.
func _axis_angle(b: Basis) -> float:
	var v: Vector3 = b.x
	return atan2(v.x, v.z)

func _ready() -> void:
	var names := ["dino", "blue_demon", "bunny", "cat", "birb", "dragon"]
	print("%-14s legs  twist-mod  spine bone      yaw@fwd  yaw@side  torso delta" % "model")
	for n in names:
		var rig = Rig.new()
		add_child(rig)
		if not rig.build(n, 4.4):
			print("  %-12s (no pack)" % n); continue
		# forward: travel == facing
		rig.set_state("advance", Vector2(0, 1), Vector2(0, 1))
		await get_tree().process_frame
		await get_tree().process_frame
		var sk := rig._find(rig, "Skeleton3D") as Skeleton3D
		var idx: int = rig._twist_mod.bone_idx if rig._twist_mod != null else -1
		var fwd_body: float = rig.rotation.y
		var fwd_torso := 0.0
		if sk != null and idx >= 0:
			fwd_torso = _axis_angle(sk.get_bone_global_pose(idx).basis)
		# sidestep: travel 90 deg off facing
		rig.set_state("advance", Vector2(0, 1), Vector2(1, 0))
		for i in range(40):
			await get_tree().process_frame
		var side_body: float = rig.rotation.y
		var side_torso := 0.0
		if sk != null and idx >= 0:
			side_torso = _axis_angle(sk.get_bone_global_pose(idx).basis)
		print("  %-12s %-5s %-10s %-15s %6.1f  %7.1f  %8.1f  %10.1f" % [
			n, str(rig._has_legs), str(rig._twist_mod != null),
			sk.get_bone_name(idx) if idx >= 0 else "-",
			rad_to_deg(fwd_body), rad_to_deg(side_body), rad_to_deg(angle_difference(fwd_torso, side_torso)),
			rad_to_deg(rig._twist_mod.twist) if rig._twist_mod != null else 0.0])
		rig.queue_free()
	get_tree().quit()
