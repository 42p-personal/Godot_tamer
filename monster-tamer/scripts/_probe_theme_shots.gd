extends Node
func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1152, 648))
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://house/"))
	var n = load("res://scenes/theme_gallery.tscn").instantiate()
	add_child(n)
	for _i in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("user://house/gallery_00.png")
	var sc := _find(n)
	if sc != null:
		var maxv: float = sc.get_v_scroll_bar().max_value
		for k in range(1, 8):
			sc.scroll_vertical = int(maxv * float(k) / 7.0)
			for _i in 5:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://house/gallery_%02d.png" % k)
		print("scroll max ", maxv)
	get_tree().quit(0)
func _find(n: Node) -> ScrollContainer:
	if n is ScrollContainer: return n
	for c in n.get_children():
		var r := _find(c)
		if r != null: return r
	return null
