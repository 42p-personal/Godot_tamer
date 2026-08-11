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

## ⚠️ THE BOTTOM OF EVERY SCREEN BELONGS TO THAT SCREEN'S ACTION RAIL, NOT TO THE HINT.
## `UI_LAYOUT_RULES` R2 requires the primary action to be reachable without scrolling, so every
## dynamic screen pins a rail across the bottom — and this panel sat 20px off the bottom edge,
## directly on top of it. Round 18's captures show it covering the right end of the Stable's
## "Advance Week", the Town's footer, part of Training's CHA column, and — measured by crop, not
## guessed — the exact region the Tactics screen's COMMIT AND FIGHT button draws into. An overlay
## that hides the single most important button in the game is not a hint.
const RAIL_RESERVE := 168  # base-viewport px kept clear at the bottom for the screen's own rail

var _panel: PanelContainer
var _title: Label
var _body: Label
var _pointer: PanelContainer
var _pointer_label: Label
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
	_panel.offset_left = -430; _panel.offset_top = -(190 + RAIL_RESERVE)
	_panel.offset_right = -20; _panel.offset_bottom = -RAIL_RESERVE
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

	# ── THE POINTER ───────────────────────────────────────────────────────────────────────────
	# What a screen shows when the step is real but belongs SOMEWHERE ELSE. One line, naming the
	# step and the room it lives in. The alternative considered and rejected was to hide the hint
	# entirely off-screen: a new player who wanders into the Town mid-step would then lose the
	# thread with nothing to pick it back up. Wayfinding is honest; instructing is not.
	_pointer = PanelContainer.new()
	_pointer.add_theme_stylebox_override("panel", UiTheme.panel_style("raised", UiTheme.GOLD))
	_pointer.anchor_left = 1; _pointer.anchor_top = 1
	_pointer.anchor_right = 1; _pointer.anchor_bottom = 1
	_pointer.offset_left = -430; _pointer.offset_top = -(52 + RAIL_RESERVE)
	_pointer.offset_right = -20; _pointer.offset_bottom = -RAIL_RESERVE
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_pointer)

	_pointer_label = UiTheme.body_text("", "secondary")
	_pointer_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_pointer_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pointer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pointer.add_child(_pointer_label)


## ⚠️ SCENES THE HINT MUST NEVER COVER. The overlay is an autoload CanvasLayer, so without this it
## draws on EVERY screen — including a live fight, where it sat over the arena telling the player
## to go buy their first monster while their team was mid-battle. A hint that appears where its
## instruction cannot be followed is worse than no hint.
## ⚠️ `title` AND `ending` JOINED THIS LIST IN ROUND 18. The captures show a full food-and-foraging
## instruction rendered over the main menu of a game that has not been started, and over the
## epilogue of one that is finished. Neither screen has a stable to feed.
const MUTED_SCENES := ["arena3d", "arena", "battle", "report", "sandbox", "tactics",
	"title", "ending", "watch"]


## The basename of the screen the player is actually looking at.
##
## ⚠️ `get_tree().current_scene` IS NOT ALWAYS IT. A capture harness instantiates a screen as a
## CHILD of itself, so `current_scene` reads `_probe_screens` and every mute/relevance test below
## silently passes — which is exactly why round 18's captures showed this banner on Tactics, a
## scene that has been on the mute list since it was written. The harness was not lying about the
## overlap (that was real and measured); it was lying about WHICH screens the overlay appears on.
## Falling through to the deepest non-probe scene in the tree makes the overlay correct in the
## game and observable in a harness, which is the only combination worth having.
func _active_screen() -> String:
	var cur := get_tree().current_scene
	var f: String = "" if cur == null else cur.scene_file_path.get_file().get_basename()
	if f != "" and not f.begins_with("_"):
		return f
	var found := ""
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var p: String = n.scene_file_path
		if p.begins_with("res://scenes/"):
			var b: String = p.get_file().get_basename()
			if not b.begins_with("_"):
				found = b
		for c in n.get_children():
			stack.append(c)
	return found


func _scene_is_muted() -> bool:
	var f := _active_screen()
	return f == "" or MUTED_SCENES.has(f)


## Does this step's instruction describe something the player can do on THIS screen?
## A step with no `where` is treated as universal, so an unauthored step degrades to the old
## behaviour rather than vanishing.
func _step_is_actionable(step: Dictionary) -> bool:
	var where: Array = step.get("where", [])
	if where.is_empty():
		return true
	return where.has(_active_screen())


func _hide_all() -> void:
	_panel.visible = false
	_pointer.visible = false


func _refresh() -> void:
	if _scene_is_muted():
		_hide_all()
		return
	if not has_node("/root/Tutorial") or not Tutorial.is_active():
		_hide_all()
		return
	var step: Dictionary = Tutorial.current()
	if step.is_empty():
		_hide_all()
		return

	if _step_is_actionable(step):
		_pointer.visible = false
		_panel.visible = true
		_title.text = str(step.get("title", ""))
		_body.text = str(step.get("body", ""))
		return

	# Real step, wrong room: point at the right one instead of instructing here.
	_panel.visible = false
	_pointer.visible = true
	var at := str(step.get("at", ""))
	_pointer_label.text = ("Guide: %s — in %s" % [str(step.get("title", "")), at]) if at != "" \
		else "Guide: %s" % str(step.get("title", ""))
