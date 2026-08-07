## A LIVE 5v5 WITH THE CC0 CREATURES. Samples the fight at intervals rather than at one instant —
## a single frozen frame is what made six different clips look identical, and the whole point of a
## fight is what changes between frames.
extends Node

func _ready() -> void:
	var arena: Node = (load("res://scenes/arena3d.tscn") as PackedScene).instantiate()
	add_child(arena)

	var nodes: Array = []
	for i in range(900):
		await get_tree().process_frame
		nodes = arena.get("nodes")
		if not nodes.is_empty():
			break

	var rigged := 0
	var names := []
	for i in range(nodes.size()):
		var sid: String = arena.all_units[i].species_id
		if nodes[i].get("rig") != null:
			rigged += 1
			names.append(sid + "->" + str(Art.pack_model_for(sid)))
		else:
			names.append(sid + " (sprite)")
	print("units=%d  rigged=%d  sprite=%d" % [nodes.size(), rigged, nodes.size() - rigged])
	print("  ", names)
	print("frames in stream: ", (arena.get("frames") as Array).size())
	# ⚠️ THE BATCHING IS THE WHOLE REASON THOSE PROPS WERE CHOSEN — verify it, do not assume it.
	# One MultiMeshInstance3D per KIND is the pass; one per PIECE means a multi-material model
	# slipped through and draw calls now grow with ground area.
	var mmi := 0; var inst := 0; var props := 0; var prop_pieces := 0
	for c in arena.get_children():
		if c is MultiMeshInstance3D:
			mmi += 1
			var mm: MultiMesh = c.multimesh
			inst += mm.instance_count
			var cls := mm.mesh.get_class() if mm.mesh != null else "?"
			# ⚠️ NOT every MultiMesh in the arena is an obstacle. The venue stands are boxes and the
			# unit shadows are quads, both batched the same way — calling them "fallbacks" reported
			# a failure that was not happening. Only ArrayMesh batches are imported props.
			if cls == "ArrayMesh":
				props += 1
				prop_pieces += mm.instance_count
			print("   batch %-10s x%-3d  %s" % [cls, mm.instance_count,
				"obstacle prop" if cls == "ArrayMesh" else "venue/shadow geometry"])
	print("obstacle props: %d batches (one per kind) for %d pieces; %d other batches"
		% [props, prop_pieces, mmi - props])

	# Six samples spread across the fight.
	for shot in range(6):
		for f in range(70):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://fight_%d.png" % shot)
		var states := {}
		for nd in nodes:
			var s: String = str(nd.get("last_rec", {}).get("state", "?"))
			states[s] = int(states.get(s, 0)) + 1
		# ⚠️ Measure what the SHOT actually contains: how much of the frame the units occupy. A
		# camera that is too tight shows up here as coverage approaching 1.0 — the number the
		# screenshots revealed and no earlier probe reported.
		var cam: Camera3D = arena.get("camera")
		var mn := Vector2(1e9, 1e9); var mx := Vector2(-1e9, -1e9)
		var vis := 0
		for i in range(nodes.size()):
			# ⚠️ `all_units[i].alive` is the sim's FINAL state — the sim ran to completion before the
			# replay started, so it reports who is alive at the END, not at this frame. The replayed
			# truth is the frame record the renderer last applied.
			if not bool(nodes[i].get("last_rec", {}).get("alive", true)): continue
			var h: Node3D = nodes[i]["holder"]
			for corner in [Vector3(0, 0, 0), Vector3(0, 4.4, 0)]:
				var sp: Vector2 = cam.unproject_position(h.global_position + corner)
				mn = mn.min(sp); mx = mx.max(sp)
			vis += 1
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var cov: float = ((mx.x - mn.x) / vp.x) * ((mx.y - mn.y) / vp.y)
		# Where is the fight ON SCREEN, and how big is each body? Both are what "watchable" means.
		var mid := (mn + mx) * 0.5
		var offc := Vector2((mid.x - vp.x * 0.5) / vp.x, (mid.y - vp.y * 0.5) / vp.y)
		var heights: Array = []
		for i in range(nodes.size()):
			if not bool(nodes[i].get("last_rec", {}).get("alive", true)): continue
			var hh: Node3D = nodes[i]["holder"]
			var top: Vector2 = cam.unproject_position(hh.global_position + Vector3(0, 4.4, 0))
			var bot: Vector2 = cam.unproject_position(hh.global_position)
			heights.append(absf(bot.y - top.y) / vp.y)
		heights.sort()
		print("  shot %d  span=%.1f  units=%d  cov=%.0f%%  off-centre=(%+.2f,%+.2f)  body h: min %.0f%% med %.0f%% max %.0f%%" % [
			shot, arena.get("_cam_span"), vis, cov * 100.0, offc.x, offc.y,
			heights[0] * 100.0, heights[heights.size() / 2] * 100.0, heights[-1] * 100.0])
	print("done")
	get_tree().quit()
