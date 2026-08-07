## Do the CC0 pack creatures load, scale, and play every sim state? Measured, then rendered.
extends Node3D
const RigScript = preload("res://scripts/ui/creature_rig.gd")
const STATES := ["idle", "advance", "attack", "cast", "stunned", "dead"]

func _ready() -> void:
	var mf := FileAccess.open("res://assets/models/creatures/MANIFEST.json", FileAccess.READ)
	var ids := []
	if mf != null:
		for c in JSON.parse_string(mf.get_as_text()).get("creatures", []):
			if not ids.has(c["id"]): ids.append(c["id"])
	print("manifest creatures: %d" % ids.size())

	var ok := 0; var fails := []
	var missing_state := {}
	for id in ids:
		var rig = RigScript.new(); add_child(rig)
		if not rig.build(id, 2.6):
			fails.append(id); rig.queue_free(); continue
		var sk := _find(rig, "Skeleton3D") as Skeleton3D
		var mi := _find(rig, "MeshInstance3D") as MeshInstance3D
		var ap := _find(rig, "AnimationPlayer") as AnimationPlayer
		var got := []
		for s in STATES:
			rig.set_state(s, Vector2(0, 1))
			await get_tree().process_frame
			if ap.current_animation != "": got.append(s)
			else: missing_state[s] = int(missing_state.get(s, 0)) + 1
		# ⚠️ Measure the SCREEN PRESENCE, not just the height — the whole point of the extent-based
		# scale. And measure it after playback has advanced, because bounds move with the pose.
		var b: AABB = rig.call("_skinned_bounds")
		var pres: float = maxf(b.size.y, maxf(b.size.x, b.size.z) * 0.8) * rig.scale.y
		if absf(pres - 2.6) > 0.35: fails.append("%s (presence %.2f)" % [id, pres])
		else: ok += 1
		rig.queue_free()
		await get_tree().process_frame
	print("built and scaled OK: %d / %d" % [ok, ids.size()])
	if not fails.is_empty(): print("  problems: ", fails)
	print("states with no clip anywhere: ", missing_state)
	get_tree().quit()

func _find(n: Node, c: String) -> Node:
	if n.is_class(c): return n
	for k in n.get_children():
		var r := _find(k, c)
		if r != null: return r
	return null
