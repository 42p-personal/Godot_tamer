## THE TUTORIAL GUIDE — an IN-FLOW STRIP at the top of the screen it belongs to, never a floating
## panel over it.
##
## ⚠️ ROUND 19 CHANGED THE SHAPE, NOT THE CONTENT. Round 18 made this honest (each step declares
## `where` it can be followed, after a food hint rendered on the Title screen and five others) but
## left it a floating `PanelContainer` anchored to the bottom-right corner with a 168px rail
## reserve underneath it. That reserve saved the action rail and nothing else: the round-18/19
## capture of Training shows the panel sitting squarely on top of the INT column's "Arcane Study"
## Book button and the CHA column's, and the Stable capture shows the one-line pointer covering the
## Temperament bars. A reserve is a guess about where the controls are, and a guess is wrong on the
## screen nobody measured.
##
## ⚠️ SO THE FIX IS STRUCTURAL, NOT A BIGGER RESERVE. The strip is added as the FIRST CHILD of the
## host screen's page container. It occupies layout instead of covering it, so it CANNOT overlap a
## control — not on Training, not on a screen written next year, and not at a window size nobody
## captured. `_probe_tutorial.gd` asserts exactly that invariant, because a rule nothing enforces
## is a rule that decays and this project has watched that happen a dozen times.
##
## ⚠️ AND IT IS STILL ATTACHED FROM OUTSIDE. No screen script knows this exists. The strip is
## injected into a container found by SHAPE (a MarginContainer holding one VBoxContainer — the
## pattern all thirteen screens already independently converged on) rather than by a node path any
## screen would have to agree to publish. That keeps the zero-coupling property the autoload was
## built for while giving up the overlay's one bad habit.
##
## ⚠️ THE SKIP SURVIVED, AND IT HAD TO. A tutorial that cannot be dismissed is worse than one that
## covers a button. It is now a real in-flow Button in the screen's own tab order, which is
## strictly better than a button on an ignored-mouse overlay layer.
extends CanvasLayer

const UiTheme = preload("res://scripts/ui/theme.gd")

## The node name and group the strip carries, so a probe can find every guide element in a screen
## without importing this file or knowing its internals. ⚠️ `_probe_tutorial.gd` reads the GROUP —
## renaming it here without renaming it there silently disarms the overlap assertion.
const STRIP_NAME := "TutorialGuideStrip"
const STRIP_GROUP := "guide_ui"

## ⚠️ SCENES THE GUIDE MUST NEVER APPEAR ON. Without this it would draw on EVERY screen — including
## a live fight, where it once sat over the arena telling the player to go buy their first monster
## while their team was mid-battle. A hint that appears where its instruction cannot be followed is
## worse than no hint.
## ⚠️ `title` AND `ending` JOINED THIS LIST IN ROUND 18. The captures showed a full food-and-
## foraging instruction rendered over the main menu of a game that has not been started, and over
## the epilogue of one that is finished. Neither screen has a stable to feed.
const MUTED_SCENES := ["arena3d", "arena", "battle", "report", "sandbox", "tactics",
	"title", "ending", "watch"]

## The strip lives INSIDE the host screen, so it is freed when that screen is. Every use is guarded
## by `is_instance_valid()` and it is simply rebuilt on the next poll — cheaper and far more robust
## than trying to reparent it out from under a `change_scene_to_file()` nobody signals.
var _strip: PanelContainer = null
var _title: Label = null
var _body: Label = null
var _poll_accum: float = 0.0
var _warned: Dictionary = {}


func _ready() -> void:
	layer = 100
	if has_node("/root/Tutorial"):
		Tutorial.step_changed.connect(func(_id: String): _refresh())
	_refresh()


func _process(delta: float) -> void:
	# ⚠️ Polled, not signalled. The tutorial's `done` tests read live state (roster size, week, plan
	# contents) that no single screen owns and that nothing emits a signal for; and a scene CHANGE
	# fires no signal either, so the host lookup has to be re-run rather than cached.
	# 10Hz, not 4Hz: at 4Hz a freshly opened screen could stand for a quarter of a second with no
	# strip on it, which is long enough for a capture harness to photograph the wrong thing.
	_poll_accum += delta
	if _poll_accum < 0.1:
		return
	_poll_accum = 0.0
	if has_node("/root/Tutorial"):
		Tutorial.poll()
	_refresh()


## The node of the screen the player is actually looking at.
##
## ⚠️ `get_tree().current_scene` IS NOT ALWAYS IT. A capture harness instantiates a screen as a
## CHILD of itself, so `current_scene` reads `_probe_screens` and every mute/relevance test below
## silently passes — which is why round 18's captures showed the banner on Tactics, a scene that
## has been on the mute list since it was written. Falling through to the deepest non-probe scene
## in the tree makes this correct in the game AND observable in a harness, which is the only
## combination worth having.
func _active_screen_node() -> Node:
	var cur := get_tree().current_scene
	if cur != null:
		var f: String = cur.scene_file_path.get_file().get_basename()
		if f != "" and not f.begins_with("_"):
			return cur
	var found: Node = null
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var p: String = n.scene_file_path
		if p.begins_with("res://scenes/") and not p.get_file().get_basename().begins_with("_"):
			found = n
		for c in n.get_children():
			stack.append(c)
	return found


func _active_screen() -> String:
	var n := _active_screen_node()
	return "" if n == null else n.scene_file_path.get_file().get_basename()


func _scene_is_muted() -> bool:
	var f := _active_screen()
	return f == "" or MUTED_SCENES.has(f)


## THE HOST SLOT — found by SHAPE, not by an agreed node path.
##
## Every screen in this project builds the same skeleton: a background, then a MarginContainer
## anchored to the full rect, holding exactly one VBoxContainer that is the page. That convergence
## is what makes an in-flow strip possible without editing thirteen files owned by other streams.
## Returning null (rather than falling back to a floating panel) is deliberate: a screen that grows
## a different skeleton should lose the guide LOUDLY, not silently regain the bug this replaced.
func _host_slot(screen: Node) -> VBoxContainer:
	# A scene whose root is not a Control is not a screen — `scenes/contract_test.tscn` is a
	# headless arithmetic runner and it matched every path test here, so the first contract run
	# after this change printed a guide warning in the middle of a PASS. A loud message in a place
	# it does not belong is how people learn to skim past loud messages.
	if screen == null or not (screen is Control):
		return null
	var stack: Array = [screen]
	while not stack.is_empty():
		var n: Node = stack.pop_front()
		if n is MarginContainer:
			for c in n.get_children():
				if c is VBoxContainer:
					return c as VBoxContainer
		for c in n.get_children():
			stack.append(c)
	return null


func _drop_strip() -> void:
	if is_instance_valid(_strip):
		_strip.queue_free()
	_strip = null
	_title = null
	_body = null


func _build_strip(host: VBoxContainer) -> void:
	_strip = PanelContainer.new()
	_strip.name = STRIP_NAME
	_strip.add_to_group(STRIP_GROUP)
	_strip.add_theme_stylebox_override("panel", UiTheme.panel_style("raised", UiTheme.GOLD))
	_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_LG)
	_strip.add_child(row)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)

	# Both lines come from the theme's published scale: SIZE_SUBHEADING (18, the accessibility
	# floor) and SIZE_BODY (16). No font size or colour is hand-set anywhere in this file.
	_title = UiTheme.heading("", 2)
	col.add_child(_title)

	_body = UiTheme.body_text("", "secondary")
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_body)

	var skip := Button.new()
	skip.text = "Skip the guide"
	skip.focus_mode = Control.FOCUS_ALL
	skip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	skip.custom_minimum_size = Vector2(180, 0)
	skip.pressed.connect(func():
		if has_node("/root/Tutorial"):
			Tutorial.dismiss()
		_drop_strip())
	row.add_child(skip)

	host.add_child(_strip)
	host.move_child(_strip, 0)


func _refresh() -> void:
	if _scene_is_muted() or not has_node("/root/Tutorial") or not Tutorial.is_active():
		_drop_strip()
		return
	var step: Dictionary = Tutorial.current()
	if step.is_empty():
		_drop_strip()
		return

	var screen := _active_screen_node()
	if not (screen is Control):
		_drop_strip()
		return
	var host := _host_slot(screen)
	if host == null:
		_drop_strip()
		var key := _active_screen()
		if key != "" and not _warned.has(key):
			_warned[key] = true
			printerr("tutorial_overlay: no MarginContainer>VBoxContainer page on '%s' — "
				% key + "the guide cannot be shown in flow there. Give the screen the standard "
				+ "page skeleton rather than restoring a floating panel.")
		return

	if not is_instance_valid(_strip) or _strip.get_parent() != host:
		_drop_strip()
		_build_strip(host)

	if _step_is_actionable(step):
		_title.text = str(step.get("title", ""))
		_body.text = str(step.get("body", ""))
	else:
		# Real step, wrong room: point at the right one instead of instructing here. The full
		# instruction is deliberately NOT printed — that is round 18's honesty fix and it stands.
		var at := str(step.get("at", ""))
		_title.text = "Guide — %s" % str(step.get("title", ""))
		_body.text = ("This one happens in %s." % at) if at != "" else "Not on this screen."


## Does this step's instruction describe something the player can do on THIS screen?
## A step with no `where` is treated as universal, so an unauthored step degrades to the old
## behaviour rather than vanishing.
func _step_is_actionable(step: Dictionary) -> bool:
	var where: Array = step.get("where", [])
	if where.is_empty():
		return true
	return where.has(_active_screen())
