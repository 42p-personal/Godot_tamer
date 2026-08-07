## HOW MUCH DOES EACH CLIP ACTUALLY MOVE, AND WHERE DOES IT END UP? Two objective numbers:
##   travel  — total distance every bone moves over the clip, relative to the body's height.
##             A "walk" that scores like an "idle" is not a walk.
##   end_hip — hip height at the clip's final frame, as a fraction of standing height.
##             A death must END on the ground; a flinch must end standing.
extends Node3D

const RigScript = preload("res://scripts/ui/creature_rig.gd")
const CLIPS := ["advance"]

func _ready() -> void:
	var rig = RigScript.new(); add_child(rig)
	rig.build("kongrath", 2.6)
	var sk := _find(rig, "Skeleton3D") as Skeleton3D
	var ap := _find(rig, "AnimationPlayer") as AnimationPlayer
	var hip := sk.find_bone("Hips")
	var head := sk.find_bone("Head")

	print("%-9s %8s %8s %9s %9s" % ["clip", "len", "travel", "end_hip", "min_hip"])
	for c in CLIPS:
		rig.set_state(c, Vector2(0, 1))
		await get_tree().process_frame
		var length: float = ap.get_animation(ap.current_animation).length
		var prev := {}
		var travel := 0.0
		var stand := 0.0
		var end_hip := 0.0
		var min_hip := 1e9
		var steps := 48
		for s in range(steps + 1):
			ap.seek(length * (float(s) / float(steps)) * 0.999, true)
			ap.pause()
			await get_tree().process_frame
			var hy: float = sk.get_bone_global_pose(hip).origin.y
			var hdy: float = sk.get_bone_global_pose(head).origin.y
			if s == 0: stand = hy
			min_hip = minf(min_hip, hy)
			end_hip = hy
			for b in range(sk.get_bone_count()):
				var o: Vector3 = sk.get_bone_global_pose(b).origin
				if prev.has(b): travel += (o - prev[b]).length()
				prev[b] = o
			if s == 0: travel = 0.0
		ap.play()
		# normalise travel by head height so it is comparable across creatures
		var norm: float = travel / maxf(0.001, sk.get_bone_global_pose(head).origin.y) / float(steps)
		print("%-9s %7.2fs %8.3f %8.2f%% %8.2f%%" % [c, length, norm,
			end_hip / maxf(0.001, stand) * 100.0, min_hip / maxf(0.001, stand) * 100.0])
	get_tree().quit()

func _find(n: Node, c: String) -> Node:
	if n.is_class(c): return n
	for k in n.get_children():
		var r := _find(k, c)
		if r != null: return r
	return null
