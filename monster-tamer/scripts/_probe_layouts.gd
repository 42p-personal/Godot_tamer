## Render both authored compositions side by side, with real teams on them.
extends Node
const T = preload("res://scripts/tactics.gd")

func _ready() -> void:
	for layout in ["four_pillar", "central_mass"]:
		var a: Array = []; var b: Array = []
		for i in range(5):
			a.append(GameData.make_monster(Art.ROSTER[i], 0.35))
			b.append(GameData.make_monster(Art.ROSTER[i + 5], 0.35))
		T.committed = {"teamA": a, "teamB": b, "planA": {}, "planB": {}, "orders": {}, "layout": layout}
		var arena: Node = (load("res://scenes/arena3d.tscn") as PackedScene).instantiate()
		add_child(arena)
		var nodes: Array = []
		for i in range(900):
			await get_tree().process_frame
			nodes = arena.get("nodes")
			if nodes != null and not nodes.is_empty(): break
		for f in range(100):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://layout_%s.png" % layout)
		print("%s -> %d pieces, %d units" % [layout, (arena.get("_obstacles") as Array).size(), nodes.size()])
		arena.queue_free()
		await get_tree().process_frame
	print("done -> ", ProjectSettings.globalize_path("user://"))
	get_tree().quit()
