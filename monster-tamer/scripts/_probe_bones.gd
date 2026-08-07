## What do the pack skeletons actually give us? A torso-twist strafe needs a spine-ish bone
## between the hips and the head. If the naming is inconsistent across packs, that route is dead.
extends Node
const PACK_DIR := "res://assets/models/creatures/"
func _ready() -> void:
	var d := DirAccess.open(PACK_DIR)
	var files: Array[String] = []
	if d != null:
		for f in d.get_files():
			if f.ends_with(".glb"):
				files.append(f)
	files.sort()
	print("packs: %d" % files.size())
	var with_spine := 0
	var legged := 0
	var buckets := {}
	for f in files:
		var sc: PackedScene = load(PACK_DIR + f)
		if sc == null: continue
		var inst := sc.instantiate()
		var sk := _find(inst, "Skeleton3D") as Skeleton3D
		if sk == null:
			print("  %-26s NO SKELETON" % f)
			inst.free(); continue
		var names: Array[String] = []
		for i in range(sk.get_bone_count()):
			names.append(sk.get_bone_name(i))
		var spine := ""
		for n in names:
			var l := n.to_lower()
			if "spine" in l or "chest" in l or "torso" in l or "body" in l or "neck" in l:
				spine = n; break
		if spine != "": with_spine += 1
		var has_legs := false
		for n in names:
			var l := n.to_lower()
			if "leg" in l or "foot" in l or "thigh" in l or "shin" in l or "knee" in l:
				has_legs = true; break
		if has_legs: legged += 1
		buckets[sk.get_bone_count()] = int(buckets.get(sk.get_bone_count(), 0)) + 1
		inst.free()
	print("with a spine-ish bone: %d of %d" % [with_spine, files.size()])
	print("WITH LEG BONES (a strafe clip is meaningful): %d of %d" % [legged, files.size()])
	var ks := buckets.keys(); ks.sort()
	for k in ks:
		print("   %3d bones : %d models" % [k, buckets[k]])
	get_tree().quit()

func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls): return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null: return r
	return null
