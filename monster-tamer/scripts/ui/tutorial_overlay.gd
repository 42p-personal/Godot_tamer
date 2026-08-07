## THE TUTORIAL BANNER — a non-blocking hint, pinned bottom-right, on every screen.
##
## ⚠️ IT MUST NOT EAT CLICKS. `mouse_filter = MOUSE_FILTER_IGNORE` on the full-screen root and on
## every label; only the two buttons accept input. A hint that swallows the click meant for the
## button it is pointing AT is worse than no hint — and this project has already shipped one
## overlay bug of exactly that shape (the v0.79 z-index scrim that buried every button).
##
## Added as a CanvasLayer autoload so it survives `change_scene_to_file` without every screen
## needing to know it exists — the tutorial attaches from OUTSIDE, and no screen script is
## coupled to it.
extends CanvasLayer

const UiTheme = preload("res://scripts/ui/theme.gd")

var _panel: PanelContainer
var _title: Label
var _body: Label
var _poll_accum: float = 0.0


func _ready() -> void:
	layer = 100  # above screens, below nothing that matters
	_build()
	if has_node("/root/Tutorial"):
		Tutorial.step_changed.connect(func(_id: String): _refresh())
	_refresh()


func _process(delta: float) -> void:
	# ⚠️ Polled, not signalled. The tutorial's `done` tests read live state (roster size, week,
	# plan contents) that no single screen owns and that nothing currently emits a signal for.
	# Polling 4x/second keeps this decoupled from every screen — the alternative is editing nine
	# UI files to fire notifications, which is exactly the coupling this design avoids.
	_poll_accum += delta
	if _poll_accum < 0.25:
		return
	_poll_accum = 0.0
	if has_node("/root/Tutorial"):
		Tutorial.poll()
	# The muted-scene test has to run on the poll too — `step_changed` does not fire on a scene
	# change, so without this the banner would linger from the screen the player just left.
	_refresh()


func _build() -> void:
	var root := Control.new()
	root.anchor_right = 1; root.anchor_bottom = 1
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE  # ⚠️ never intercept a click
	add_child(root)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiTheme.panel_style("raised", UiTheme.GOLD))
	_panel.anchor_left = 1; _panel.anchor_top = 1
	_panel.anchor_right = 1; _panel.anchor_bottom = 1
	_panel.offset_left = -430; _panel.offset_top = -190
	_panel.offset_right = -20; _panel.offset_bottom = -20
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(col)

	_title = UiTheme.heading("", 3)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_title)

	_body = UiTheme.body_text("", "secondary")
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(390, 0)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	col.add_child(row)

	var skip := Button.new()
	skip.text = "Skip the guide"
	skip.focus_mode = Control.FOCUS_ALL
	skip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skip.pressed.connect(func():
		if has_node("/root/Tutorial"):
			Tutorial.dismiss()
		_refresh())
	row.add_child(skip)


## ⚠️ SCENES THE HINT MUST NEVER COVER. The overlay is an autoload CanvasLayer, so without this it
## draws on EVERY screen — including a live fight, where it sat over the arena telling the player
## to go buy their first monster while their team was mid-battle. A hint that appears where its
## instruction cannot be followed is worse than no hint.
const MUTED_SCENES := ["arena3d", "arena", "battle", "report", "sandbox", "tactics"]


func _scene_is_muted() -> bool:
	var cur := get_tree().current_scene
	if cur == null:
		return false
	var f: String = cur.scene_file_path.get_file().get_basename()
	return MUTED_SCENES.has(f)


func _refresh() -> void:
	if _scene_is_muted():
		_panel.visible = false
		return
	if not has_node("/root/Tutorial") or not Tutorial.is_active():
		_panel.visible = false
		return
	var step: Dictionary = Tutorial.current()
	if step.is_empty():
		_panel.visible = false
		return
	_panel.visible = true
	_title.text = str(step.get("title", ""))
	_body.text = str(step.get("body", ""))
