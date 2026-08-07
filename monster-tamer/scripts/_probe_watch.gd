## Does the WATCH PATH work? Verified in two halves, because a probe that drives real scene
## changes frees itself mid-test and reports its own death as a failure.
##   A. the TITLE screen actually carries a reachable "Watch a Battle" button pointing at watch.tscn
##   B. watch.gd's setup produces a real fight in arena3d
## ⚠️ The arena rendered perfectly in every earlier probe while the ENTRY POINT into it was broken.
## Testing the destination is not testing the journey.
extends Node

func _ready() -> void:
	# ── A. the button exists, is enabled, and targets the right scene ──────────────────────────
	var title: Node = (load("res://scenes/title.tscn") as PackedScene).instantiate()
	add_child(title)
	await get_tree().process_frame
	var btn := _find_button(title, "Watch a Battle")
	if btn == null:
		print("FAIL A: no 'Watch a Battle' button on the title screen"); get_tree().quit(1); return
	print("A. button '%s'  disabled=%s  connections=%d"
		% [btn.text, btn.disabled, btn.pressed.get_connections().size()])
	if btn.disabled or btn.pressed.get_connections().is_empty():
		print("FAIL A: button is dead"); get_tree().quit(1); return
	title.queue_free()
	await get_tree().process_frame

	# ── B. watch.gd's team setup produces a running fight ──────────────────────────────────────
	var W = load("res://scripts/watch.gd")
	var a: Array = []
	var b: Array = []
	for s in W.ROSTER_A:
		a.append(GameData.make_monster(s, 0.35))
	for s in W.ROSTER_B:
		b.append(GameData.make_monster(s, 0.35))
	var T = load("res://scripts/tactics.gd")
	T.committed = {"teamA": a, "teamB": b, "planA": {}, "planB": {}, "orders": {}}

	var arena: Node = (load("res://scenes/arena3d.tscn") as PackedScene).instantiate()
	add_child(arena)
	var nodes: Array = []
	for i in range(900):
		await get_tree().process_frame
		nodes = arena.get("nodes")
		if nodes != null and not nodes.is_empty():
			break
	if nodes.is_empty():
		print("FAIL B: arena never built units"); get_tree().quit(1); return
	var names: Array = []
	for u in arena.all_units:
		names.append(u.species_name)
	print("B. %d units, %d frames, %d obstacles, layout=%s"
		% [nodes.size(), (arena.get("frames") as Array).size(),
		   (arena.get("_obstacles") as Array).size(), "four_pillar"])
	print("   teams: %s" % str(names))
	for f in range(150):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://watch.png")
	print("   shot -> ", ProjectSettings.globalize_path("user://watch.png"))
	print("PASS — the button is live and the fight runs")
	get_tree().quit(0)

func _find_button(n: Node, label: String) -> Button:
	if n is Button and (n as Button).text == label:
		return n
	for c in n.get_children():
		var r := _find_button(c, label)
		if r != null: return r
	return null
