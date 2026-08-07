## Two questions, separately:
##   A. WITHIN one clip, do limb lengths stay constant over time? (is the SOURCE animation rigid?)
##   B. ACROSS clips, does the same bone keep the same length? (is the TRANSITION rigid?)
## A pose changes joint angles; it must never change the distance from a joint to its parent.
extends Node3D

const RigScript = preload("res://scripts/ui/creature_rig.gd")
const STATES := ["advance"]

var sk: Skeleton3D
var pairs: Array = []

func _ready() -> void:
	var rig = RigScript.new(); add_child(rig)
	rig.build("kongrath", 2.6)
	sk = _find(rig, "Skeleton3D") as Skeleton3D
	for b in range(sk.get_bone_count()):
		if sk.get_bone_parent(b) >= 0:
			pairs.append(b)

	var ap := _find(rig, "AnimationPlayer") as AnimationPlayer
	print("track counts after normalisation:")
	for n in ap.get_animation_list():
		if not n.begins_with("mt/"): continue
		var a: Animation = ap.get_animation(n)
		var k := {"p": 0, "r": 0, "s": 0}
		for t in range(a.get_track_count()):
			match a.track_get_type(t):
				Animation.TYPE_POSITION_3D: k["p"] += 1
				Animation.TYPE_ROTATION_3D: k["r"] += 1
				Animation.TYPE_SCALE_3D: k["s"] += 1
		print("  %-14s pos=%d rot=%d scale=%d" % [n, k["p"], k["r"], k["s"]])

	print("\nA. WITHIN each clip (sampled over its whole length):")
	var per_state_mid := {}
	for s in STATES:
		rig.set_state(s, Vector2(0, 1))
		for i in range(20): await get_tree().process_frame
		var mins := {}; var maxs := {}
		for step in range(30):
			for i in range(3): await get_tree().process_frame
			for b in pairs:
				var d: float = _len(b)
				mins[b] = minf(mins.get(b, 1e9), d)
				maxs[b] = maxf(maxs.get(b, -1e9), d)
		var worst := 0.0; var wn := ""
		for b in pairs:
			var rel: float = (maxs[b] - mins[b]) / maxf(0.001, (maxs[b] + mins[b]) * 0.5)
			if rel > worst: worst = rel; wn = sk.get_bone_name(b)
		per_state_mid[s] = mins
		print("  %-9s worst intra-clip stretch %.2f%%  (%s)" % [s, worst * 100.0, wn])

	print("\nB. ACROSS clips (same bone, different states):")
	var worst2 := 0.0; var wn2 := ""
	for b in pairs:
		var lo := 1e9; var hi := -1e9
		for s in STATES:
			var d: float = per_state_mid[s][b]
			lo = minf(lo, d); hi = maxf(hi, d)
		var rel: float = (hi - lo) / maxf(0.001, (hi + lo) * 0.5)
		if rel > worst2: worst2 = rel; wn2 = sk.get_bone_name(b)
	print("  worst cross-clip stretch %.2f%%  (%s)" % [worst2 * 100.0, wn2])
	get_tree().quit()

func _len(b: int) -> float:
	var p: int = sk.get_bone_parent(b)
	return (sk.get_bone_global_pose(b).origin - sk.get_bone_global_pose(p).origin).length()

func _find(n: Node, c: String) -> Node:
	if n.is_class(c): return n
	for k in n.get_children():
		var r := _find(k, c)
		if r != null: return r
	return null
