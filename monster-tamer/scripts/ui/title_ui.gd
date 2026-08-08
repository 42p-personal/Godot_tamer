## THE TITLE SCREEN — the game's front door. New Career / Continue / Quit, over the generated
## key art. Falls back to a Guild Colours gradient + wordmark when the art hasn't landed yet
## (see Art.title_texture()'s documented null contract) — this screen must look deliberate and
## finished either way, and light up the moment res://assets/ui/title.jpg exists.
##
## `Career` and `SaveGame` are live autoloads (career.gd / save_game.gd). Calls to them still go
## through has_node("/root/...") guards — cheap, and it means this screen keeps degrading
## gracefully if it's ever run as a truly standalone scene outside the full project's autoload
## list, which is the only case those guards would actually trip today.
##
## Both New Career and Continue now land in **scenes/town.tscn**, not the stable directly
## (docs/CORE_LOOP_PORT.md §2 — Town is the hub; the stable/market/tournament are destinations
## FROM it, not the game's front door). New Career also empties the roster
## (`Roster.reset_to_empty()`) alongside resetting the run (`Career.reset_new_game()`) — the
## correct opening state is owning NOTHING yet, see CORE_LOOP_PORT.md §1.
extends Control

var continue_btn: Button


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var art_tex := Art.title_texture()
	if art_tex != null:
		var bg_rect := TextureRect.new()
		bg_rect.anchor_right = 1; bg_rect.anchor_bottom = 1
		bg_rect.texture = art_tex
		bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(bg_rect)
	else:
		add_child(_fallback_background())

	# Scrim so the wordmark and menu read over ANY background, painted or fallback.
	var scrim := ColorRect.new()
	scrim.color = Color(0.03, 0.03, 0.05, 0.4)
	scrim.anchor_right = 1; scrim.anchor_bottom = 1
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var margin := MarginContainer.new()
	margin.anchor_right = 1; margin.anchor_bottom = 1
	margin.add_theme_constant_override("margin_left", 56)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_right", 56)
	margin.add_theme_constant_override("margin_bottom", 48)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.alignment = BoxContainer.ALIGNMENT_END
	margin.add_child(vbox)

	var word := Label.new()
	word.text = "MONSTER TAMER"
	word.add_theme_font_size_override("font_size", 56)
	word.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97))
	vbox.add_child(word)

	var tagline := Label.new()
	tagline.text = "You run the stable. The stable fights."
	tagline.add_theme_font_size_override("font_size", 16)
	# A fixed warm gold, not Art.team_colour() — team colour is now a semantic "who plays for
	# whom" channel (art.gd), and the title screen has no team context to attach it to.
	tagline.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35))
	vbox.add_child(tagline)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(spacer)

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", 10)
	menu.custom_minimum_size = Vector2(260, 0)
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(menu)

	var new_btn := Button.new()
	new_btn.text = "New Career"
	new_btn.custom_minimum_size = Vector2(0, 44)
	new_btn.pressed.connect(_on_new_career)
	menu.add_child(new_btn)

	continue_btn = Button.new()
	continue_btn.text = "Continue"
	continue_btn.custom_minimum_size = Vector2(0, 44)
	continue_btn.disabled = not _has_save()
	if continue_btn.disabled:
		continue_btn.tooltip_text = "No save found yet."
	continue_btn.pressed.connect(_on_continue)
	menu.add_child(continue_btn)

	# ⚠️ A DEV COMMAND IS NOT A FEATURE. The first version of this shipped as a
	# `godot --path . scenes/watch.tscn` line in chat, which is not something anyone should have to
	# keep, remember or type to look at their own game. If a thing is worth watching it belongs on
	# the screen the game opens on.
	var watch_btn := Button.new()
	watch_btn.text = "Watch a Battle"
	watch_btn.custom_minimum_size = Vector2(0, 44)
	watch_btn.tooltip_text = "A 5v5 exhibition on the four_pillar arena — no career, no saving."
	watch_btn.focus_mode = Control.FOCUS_ALL
	watch_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/watch.tscn"))
	menu.add_child(watch_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.custom_minimum_size = Vector2(0, 44)
	quit_btn.pressed.connect(func(): get_tree().quit())
	menu.add_child(quit_btn)


## Guild Colours gradient — dark charcoal to a warm guild-gold corner — so the screen still
## reads as THIS game's front door with zero art present, not a placeholder grey box.
func _fallback_background() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0.10, 0.10, 0.15))
	g.set_color(1, Color(0.38, 0.27, 0.10))
	var grad := GradientTexture2D.new()
	grad.gradient = g
	grad.fill = GradientTexture2D.FILL_LINEAR
	grad.fill_from = Vector2(0.1, 0.0)
	grad.fill_to = Vector2(0.9, 1.0)
	grad.width = 16
	grad.height = 16
	var rect := TextureRect.new()
	rect.anchor_right = 1; rect.anchor_bottom = 1
	rect.texture = grad
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	return rect


func _has_save() -> bool:
	if not has_node("/root/SaveGame"):
		return false
	return SaveGame.has_save()


## Resets the LADDER/run state (league, gold, week, barn capacity) via Career.reset_new_game(),
## AND empties the stable via Roster.reset_to_empty() — together these are the real new-game
## state: week 0, 500 gold, a 2-slot barn, and zero monsters (docs/CORE_LOOP_PORT.md §1). Lands in
## the Town, not the stable — acquiring the first monster is the player's first real decision, and
## that decision is made at the Market, reached from the Town.
func _on_new_career() -> void:
	if has_node("/root/Career"):
		Career.reset_new_game()
	if has_node("/root/Roster"):
		Roster.reset_to_empty()
	get_tree().change_scene_to_file("res://scenes/town.tscn")


## ⚠️ A REFUSED LOAD MUST NOT DROP THE PLAYER SOMEWHERE UNDEFINED. `load_game()` deliberately
## returns false without mutating anything when the file is corrupt, truncated or from a species
## table that no longer has the saved monsters (save_game.gd documents that contract) — and this
## used to ignore the return value and walk into the Town regardless, on whatever Career/Roster
## state happened to be in memory. Falling back to a clean new career is the honest outcome:
## the same place New Career lands, rather than a half-loaded run.
func _on_continue() -> void:
	var loaded := false
	if has_node("/root/SaveGame"):
		loaded = SaveGame.load_game()
	if not loaded:
		push_warning("Continue: no usable save — starting a fresh career instead")
		if has_node("/root/Career"):
			Career.reset_new_game()
		if has_node("/root/Roster"):
			Roster.reset_to_empty()
	get_tree().change_scene_to_file("res://scenes/town.tscn")
