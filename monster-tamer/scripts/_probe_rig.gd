## Does the rigged path actually assemble, scale, animate and face? Measured, not asserted.
extends Node3D

const RigScript = preload("res://scripts/ui/creature_rig.gd")
const UNIT_HEIGHT := 2.6

func _ready() -> void:
	var rig = RigScript.new()
	add_child(rig)
	var ok: bool = rig.build("kongrath", UNIT_HEIGHT)
	print("build(kongrath) -> ", ok)
	if not ok:
		print("FAIL: rigged path did not assemble"); get_tree().quit(1); return

	var missing = RigScript.new(); add_child(missing)
	print("build(larkessa) -> ", missing.build("larkessa", UNIT_HEIGHT), "  (expected false = falls back to sprite)")

	var mi := _find(rig, "MeshInstance3D") as MeshInstance3D
	var ap := _find(rig, "AnimationPlayer") as AnimationPlayer
	var sk := _find(rig, "Skeleton3D") as Skeleton3D
	var meshes := _count(rig, "MeshInstance3D")
	var skels := _count(rig, "Skeleton3D")

	var aabb := mi.get_aabb()
	var world_h: float = aabb.size.y * mi.global_transform.basis.get_scale().y
	var foot_y: float = aabb.position.y * mi.global_transform.basis.get_scale().y + mi.global_position.y

	print("meshes=%d skeletons=%d bones=%d" % [meshes, skels, sk.get_bone_count()])
	print("height=%.3f (target %.3f)  feet_y=%+.4f" % [world_h, UNIT_HEIGHT, foot_y])
	print("clips=", ap.get_animation_list())
	print("material=", mi.material_override)

	# Drive every sim state and confirm the player actually changed clip.
	var seen := {}
	for s in ["idle", "advance", "retreat", "attack", "cast", "stunned", "dead"]:
		rig.set_state(s, Vector2(1, 0))
		await get_tree().process_frame
		seen[s] = ap.current_animation
		print("  state %-9s -> %s" % [s, ap.current_animation])

	# ⚠️ RE-MEASURE AFTER PLAYBACK. The clips animate the imported root's transform, so a height
	# taken before the first frame of animation proves nothing about what is on screen. Measuring
	# only at build time is exactly how a creature 100x too small passed this probe once.
	var h_after: float = mi.get_aabb().size.y * mi.global_transform.basis.get_scale().y
	print("height AFTER playback = %.3f (target %.3f)" % [h_after, UNIT_HEIGHT])

	rig.set_state("idle", Vector2(1, 0))
	await get_tree().process_frame
	rig.flinch()
	await get_tree().process_frame
	print("  flinch    -> ", ap.current_animation)

	rig.hit_flash()
	await get_tree().process_frame
	print("  hit_flash -> status_strength=", (mi.material_override as ShaderMaterial).get_shader_parameter("status_strength"))

	# Facing: the sim's vector must actually turn the body.
	rig.set_state("idle", Vector2(0, 1))
	for i in range(40): await get_tree().process_frame
	var yaw_a: float = rig.rotation.y
	rig.set_state("advance", Vector2(0, -1))
	for i in range(40): await get_tree().process_frame
	print("facing turn: %.2f rad -> %.2f rad (delta %.2f)" % [yaw_a, rig.rotation.y, absf(rig.rotation.y - yaw_a)])

	var distinct := {}
	for k in seen: distinct[seen[k]] = true
	var fails := []
	if meshes != 1: fails.append("expected 1 mesh, got %d" % meshes)
	if skels != 1: fails.append("expected 1 skeleton, got %d" % skels)
	if absf(world_h - UNIT_HEIGHT) > 0.05: fails.append("height off by %.3f" % absf(world_h - UNIT_HEIGHT))
	if absf(h_after - UNIT_HEIGHT) > 0.05: fails.append("height AFTER playback off by %.3f" % absf(h_after - UNIT_HEIGHT))
	if absf(foot_y) > 0.05: fails.append("feet not on ground (%.3f)" % foot_y)
	if distinct.size() < 6: fails.append("only %d distinct clips across 7 states" % distinct.size())
	if not (mi.material_override is ShaderMaterial): fails.append("shader not applied")
	print("\n", "PASS" if fails.is_empty() else "FAIL " + str(fails))
	get_tree().quit(0 if fails.is_empty() else 1)

func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls): return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null: return r
	return null

func _count(n: Node, cls: String) -> int:
	var t := 1 if n.is_class(cls) else 0
	for c in n.get_children(): t += _count(c, cls)
	return t
