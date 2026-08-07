## Are the ten clip files' skeletons IDENTICAL? creature_rig.gd plays nine files' animation tracks
## on the tenth file's skeleton. If bone names, order or REST POSES differ even slightly, the mesh
## is deformed by the mismatch — which is exactly what "morphing and changing shape" looks like.
extends Node

const DIR := "res://assets/models/anim/"
const FILES := ["idle", "advance", "attack", "attack_alt", "cast", "guard", "hurt", "stunned", "dead", "victory"]

func _ready() -> void:
	var ref_names: PackedStringArray = []
	var ref_rest: Array = []
	for f in FILES:
		var p := DIR + "kongrath_%s_notex.glb" % f
		var inst: Node = (load(p) as PackedScene).instantiate()
		var sk := _find(inst, "Skeleton3D") as Skeleton3D
		var ap := _find(inst, "AnimationPlayer") as AnimationPlayer
		var names: PackedStringArray = []
		var rests: Array = []
		for b in range(sk.get_bone_count()):
			names.append(sk.get_bone_name(b))
			rests.append(sk.get_bone_rest(b))
		var anim: Animation = ap.get_animation(ap.get_animation_list()[0])
		# What KIND of tracks does the clip carry? A scale track on a mismatched rest pose is the
		# worst case — it multiplies rather than replaces.
		var kinds := {"pos": 0, "rot": 0, "scale": 0, "other": 0}
		var tracked_bones := {}
		for t in range(anim.get_track_count()):
			match anim.track_get_type(t):
				Animation.TYPE_POSITION_3D: kinds["pos"] += 1
				Animation.TYPE_ROTATION_3D: kinds["rot"] += 1
				Animation.TYPE_SCALE_3D: kinds["scale"] += 1
				_: kinds["other"] += 1
			tracked_bones[str(anim.track_get_path(t)).get_slice(":", 1)] = true

		if ref_names.is_empty():
			ref_names = names; ref_rest = rests
			print("%-11s bones=%d  REFERENCE  len=%.2fs tracks pos=%d rot=%d scale=%d  bones_animated=%d" % [
				f, names.size(), anim.length, kinds["pos"], kinds["rot"], kinds["scale"], tracked_bones.size()])
		else:
			var name_diff := names != ref_names
			var worst := 0.0
			var worst_bone := ""
			if not name_diff:
				for b in range(rests.size()):
					var d: float = (rests[b].origin - ref_rest[b].origin).length()
					var ds: float = (rests[b].basis.get_scale() - ref_rest[b].basis.get_scale()).length()
					var q: float = rests[b].basis.get_rotation_quaternion().angle_to(ref_rest[b].basis.get_rotation_quaternion())
					var tot: float = d + ds * 10.0 + q
					if tot > worst:
						worst = tot; worst_bone = names[b]
			print("%-11s bones=%d  names_differ=%s  worst_rest_delta=%.5f (%s)  len=%.2fs tracks pos=%d rot=%d scale=%d  bones_animated=%d" % [
				f, names.size(), name_diff, worst, worst_bone, anim.length,
				kinds["pos"], kinds["rot"], kinds["scale"], tracked_bones.size()])
		inst.free()
	get_tree().quit()

func _find(n: Node, c: String) -> Node:
	if n.is_class(c): return n
	for k in n.get_children():
		var r := _find(k, c)
		if r != null: return r
	return null
