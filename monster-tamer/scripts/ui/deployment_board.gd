## THE DEPLOYMENT BOARD — free placement, saved formations, and the spacing trade-off made
## visible. Implements `docs/UX_DEPLOYMENT.md` for `tactics_ui.gd`'s "YOUR TEAM" column, replacing
## the old team-wide Formation: Tight/Loose dropdown.
##
## ⚠️ HONESTY NOTE, READ BEFORE TRUSTING WHAT THIS WIDGET "DOES": as of this build,
## `spatial_sim.gd::_deploy()` always computes starting positions from `Spatial.deploy_positions()`
## and has no hook to accept custom ones, and `spatial_ai.gd` only reads `tactics.formation`
## ("tight"/"loose") — it has no concept of per-monster POSITIONAL INTENT or a real starting
## coordinate. So: dragging a chip here does NOT yet move that monster's actual starting position
## in a fight. What DOES reach the sim, today, through the existing `tactics.gd` plumbing
## (`aura_coverage`/`aoe_coverage`, and `spatial_ai.gd`'s own leash-radius read of `formation`) is
## the derived TIGHT/LOOSE bucket this board computes live from your placement. So arranging a
## wide spread genuinely does something real (a looser aura/AoE trade), while the exact shape you
## draw is a planning tool and a forward-compatible save format, not yet a literal battle
## start point. See the report for the two integration hooks (`spatial_sim._deploy`,
## `spatial_ai.desired_position`) that would need extending to make free placement and positional
## intent fully real — NOT this stream's file to change (build-contract ownership).
extends VBoxContainer

const Sp = preload("res://scripts/spatial.gd")
const TacticsScript = preload("res://scripts/tactics.gd")
const FormationsScript = preload("res://scripts/formations.gd")
## ⚠️ ROUND 19: THIS FILE WAS 100% OF THE PROJECT'S REMAINING BELOW-FLOOR TYPE. After round 18 and
## the round-19 restyle of market/tactics/report, `_probe_house.gd` counted 16 off-scale labels in
## the whole game — 14 of them here (9px chip names, 10px legend and hint, 11px x3, 12px x2), which
## is `META_UI_DIRECTION` C6's "the legend is ~8px, below the accessibility floor". The board is
## instanced INSIDE the tactics screen, so those fourteen were scored against `11_tactics` and read
## as the tactics screen's debt when they were never its file. Every LABEL below now takes a
## `UiTheme` size and a token colour.
##
## ⚠️ THE `draw_string` CALLS ARE A DIFFERENT PROBLEM AND ARE DELIBERATELY LEFT. They paint into a
## canvas, not the label tree, so no probe scores them and none of them is a Label a screen reader
## or a font-scale setting can reach. Sizing them off tokens would look tidy and would fix nothing
## measurable; the real fix is that the chips stop being drawn text, and that is board surgery.
const UiTheme = preload("res://scripts/ui/theme.gd")

signal changed

const GRID_SNAP := 0.5
const FINE_SNAP := 0.1
## ⚠️ PLACEHOLDER, not an authored figure — `docs/UX_DEPLOYMENT.md` §4.3 flags this exactly:
## no per-ability AoE blast radius exists in this port to anchor a real cluster-warning radius to.
## Standing in on the same reasoning UX_DEPLOYMENT used: the nearest existing spatial constant in
## the same family is `CONTAGION_RADIUS` (5.5, status-spread range, explicitly UNSCALED per
## `ARENA_BLUEPRINT.md` §3 — "body spacing doesn't change because the world did"). Do not ship a
## real balance reading off this number; it is a legibility placeholder pending an authored figure.
const CLUSTER_RADIUS := 5.5
const CHIP_SIZE := 24.0
const FLASH_MS := 260

var team_a: Array = []
var team_size: int = 5
var ground: Vector2 = Vector2.ZERO
var zone_a: Rect2 = Rect2()
var zone_b: Rect2 = Rect2()
var enemy_ghost: Array = []       # Array[Vector2] — rival auto-arrange preview, world coords

var placements: Dictionary = {}   # MonsterInstance -> Vector2 (world, only DEPLOYED monsters)
var intents: Dictionary = {}      # MonsterInstance -> String, only OVERRIDDEN chips
var guard_target: Dictionary = {} # MonsterInstance -> MonsterInstance, only when intent == "guard"
var aura_flags: Dictionary = {}   # MonsterInstance -> bool
var team_default_intent: String = "hold"

var _covered: Dictionary = {}     # MonsterInstance -> bool (inside at least one aura ring)
var _clusters: Array = []         # Array[[MonsterInstance, MonsterInstance]]
var _low_confidence: Dictionary = {}  # MonsterInstance -> bool, from the last formation load
var _flash_until: Dictionary = {} # MonsterInstance -> ticks_msec

var _chip_nodes: Dictionary = {}  # MonsterInstance -> Control
var _tray_buttons: Dictionary = {} # MonsterInstance -> Button
var _drag_monster = null
var _reduce_motion: bool = false
var _pulse_phase: float = 0.0

var _loaded_formation: Dictionary = {}   # {} if nothing loaded (pure auto-arrange state)
var _loaded_name: String = ""

var _board_area: Control
var _tray_box: HBoxContainer
var _readout_label: Label
var _gallery_box: HBoxContainer
var _name_edit: LineEdit
var _summary_label: Label
var _px_scale: float = 1.0
var _px_origin: Vector2 = Vector2.ZERO

var _header_buttons: Array = []   # Buttons/LineEdit disabled together on `set_locked(true)`
var _locked: bool = false


## ⚠️ `setup()` MAY BE CALLED BEFORE THIS NODE ENTERS THE TREE.
## `tactics_ui.gd:_build_team_column` constructs the board and calls `setup()` while building its
## own layout — i.e. before `_ready()` has run, so none of the child controls exist yet and
## `_rebuild_tray()` crashed on a null `_tray_box`. Rather than demand every caller add the node
## first (a rule that would be silently broken again), the widget makes its own construction
## order safe: `setup()` stores its arguments and defers the UI work if the tree isn't built,
## and `_ready()` replays it.
var _pending_setup: Dictionary = {}
var _ui_built := false


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_build_header_row()
	_build_gallery_row()
	_build_board_area()
	_build_tray_row()
	_build_readout_row()
	_build_legend_row()
	_ui_built = true
	set_process(true)
	# Replay a setup() that arrived before the controls existed.
	if not _pending_setup.is_empty():
		var p := _pending_setup
		_pending_setup = {}
		setup(p["team"], p["team_size"])


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# SETUP
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## Call once with the fielded team. Loads the last-used formation for this team size if one
## exists (docs/UX_DEPLOYMENT.md §7 #1 — "the screen opens with the last-used formation already
## loaded"); otherwise auto-arranges. `rival_preview` is the ghost-zone dot set (already-scouted,
## per this mockup's standing "rival is fully scouted" assumption).
func setup(team: Array, team_size_: int) -> void:
	# See the note on `_ready()` — a caller may legitimately reach us before the controls exist.
	if not _ui_built:
		_pending_setup = {"team": team, "team_size": team_size_}
		return
	team_a = team
	team_size = maxi(1, team_size_)
	ground = Sp.ground_size(team_size)
	enemy_ghost = Sp.deploy_positions(team_size, "B")
	_compute_zones()
	_compute_aura_flags()
	_rebuild_tray()

	var last := _find_last_used_for_size(team_size)
	if not last.is_empty():
		apply_formation(last, team_a)
	else:
		auto_arrange()

	_recompute()


## Freezes every interactive part of the board — called once, at commit, mirroring
## `tactics_ui.gd`'s "no take-backs" rule for the rest of the screen. Not folded into that
## screen's generic `_interactive` disable loop because this is a container, not a `BaseButton`.
func set_locked(locked: bool) -> void:
	_locked = locked
	for b in _header_buttons:
		if b is LineEdit:
			b.editable = not locked
		elif b is BaseButton:
			b.disabled = locked
	for m in _tray_buttons:
		_tray_buttons[m].disabled = locked
	for m in _chip_nodes:
		var chip: Control = _chip_nodes[m]
		chip.focus_mode = Control.FOCUS_NONE if locked else Control.FOCUS_ALL
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE if locked else Control.MOUSE_FILTER_STOP
	for c in _gallery_box.get_children():
		if c is BaseButton:
			c.disabled = locked


func _find_last_used_for_size(size_: int) -> Dictionary:
	for f in FormationsScript.all():
		if int(f.get("teamSize", -1)) == size_:
			return f
	return {}


func _compute_zones() -> void:
	# ⚠️ Shared definition with the sim — see Spatial.deploy_zone. This used to be an inline copy.
	# ⚠️ AND IT READ `team_size_` — `setup()`'s PARAMETER — from in here, where it is out of
	# scope. That is a hard parse error, so `deployment_board.gd` has never compiled, and it took
	# `tactics_ui.gd` down with it ("Failed to compile depended scripts"): the tactics screen is
	# the only route from the tournament screen to the battle screen, so the cup path has been
	# dead since the initial commit. Nothing caught it because `_probe_compile.gd` only tests
	# `load(...) == null`, and a failed load still returns a non-null broken Script — see the
	# probe, which now checks `can_instantiate()` instead. The member below is assigned from that
	# same parameter one line before this is called, so the values are identical.
	zone_a = Sp.deploy_zone(team_size, "A")
	zone_b = Sp.deploy_zone(team_size, "B")


func _compute_aura_flags() -> void:
	aura_flags.clear()
	for m in team_a:
		var has_aura := false
		for mv in m.moveset:
			if String(mv.get("target", "")) != "team":
				continue
			var fx: Dictionary = mv.get("effects", {})
			for k in ["atkBuff", "defBuff", "accBuff", "dodgeBuff", "ward", "guard", "hpRegenBuff", "regenBuff"]:
				if fx.has(k):
					has_aura = true
					break
			if has_aura:
				break
		aura_flags[m] = has_aura


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# UI — HEADER / GALLERY / TRAY / READOUT / LEGEND
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _build_header_row() -> void:
	var header := Label.new()
	header.text = "Formation — free placement, your half only"
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	header.add_theme_color_override("font_color", UiTheme.GOLD)
	add_child(header)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	add_child(row)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Formation name"
	_name_edit.custom_minimum_size = Vector2(140, 0)
	row.add_child(_name_edit)

	var save_btn := Button.new()
	save_btn.text = "Save as new"
	save_btn.tooltip_text = "Save the current arrangement as a new named formation."
	save_btn.pressed.connect(_on_save_new)
	row.add_child(save_btn)

	var update_btn := Button.new()
	update_btn.text = "Update"
	update_btn.tooltip_text = "Overwrite the loaded formation with the current arrangement."
	update_btn.pressed.connect(_on_update_loaded)
	row.add_child(update_btn)

	var auto_btn := Button.new()
	auto_btn.text = "Auto-arrange"
	auto_btn.tooltip_text = "Fill every undeployed monster into a sensible default line."
	auto_btn.pressed.connect(func(): auto_arrange(); _recompute())
	row.add_child(auto_btn)

	var reset_btn := Button.new()
	reset_btn.text = "Reset to loaded"
	reset_btn.tooltip_text = "Undo in-progress dragging — reload the formation this screen opened with."
	reset_btn.pressed.connect(reset_to_loaded)
	row.add_child(reset_btn)


func _build_gallery_row() -> void:
	var lbl := Label.new()
	lbl.text = "Saved formations (Tab to browse, Enter to load)"
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	lbl.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	add_child(lbl)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 56)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_gallery_box = HBoxContainer.new()
	_gallery_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_gallery_box)
	_refresh_gallery()


func _refresh_gallery() -> void:
	for c in _gallery_box.get_children():
		c.queue_free()
	var entries: Array = FormationsScript.starter_presets(team_size) + FormationsScript.all()
	for f in entries:
		_gallery_box.add_child(_make_gallery_entry(f))


func _make_gallery_entry(f: Dictionary) -> Control:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(78, 52)
	btn.focus_mode = Control.FOCUS_ALL
	var is_mismatch := int(f.get("teamSize", team_size)) != team_size
	var suffix := "" if not is_mismatch else " (%dv%d)" % [int(f.get("teamSize", 0)), int(f.get("teamSize", 0))]
	btn.tooltip_text = "%s%s%s" % [f.get("name", "?"), suffix, "" if not f.get("preset", false) else " — starter preset"]

	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.add_child(vb)

	var thumb := Control.new()
	thumb.custom_minimum_size = Vector2(70, 34)
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.draw.connect(func(): _draw_thumb(thumb, f))
	vb.add_child(thumb)

	var name_lbl := Label.new()
	name_lbl.text = f.get("name", "?")
	name_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	name_lbl.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(name_lbl)

	btn.pressed.connect(func():
		var summary := apply_formation(f, team_a)
		_summary_label.text = summary
		_recompute()
	)
	return btn


func _draw_thumb(thumb: Control, f: Dictionary) -> void:
	var r := Rect2(Vector2.ZERO, thumb.size)
	thumb.draw_rect(r, Color(0.1, 0.1, 0.13), true)
	thumb.draw_rect(r, Color(0.3, 0.3, 0.36), false, 1.0)
	for slot in f.get("slots", []):
		var rel: Array = slot["rel"]
		var p := Vector2(rel[0] * r.size.x, rel[1] * r.size.y)
		thumb.draw_circle(p, 2.0, Color(0.4, 0.65, 0.95))


func _build_board_area() -> void:
	_board_area = Control.new()
	_board_area.custom_minimum_size = Vector2(0, 240)
	_board_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board_area.mouse_filter = Control.MOUSE_FILTER_PASS
	_board_area.clip_contents = true
	_board_area.draw.connect(_draw_board)
	_board_area.resized.connect(_recompute_scale)
	add_child(_board_area)


func _build_tray_row() -> void:
	var lbl := Label.new()
	lbl.text = "Roster — Enter/Space to deploy, then Tab to it and use arrow keys"
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	lbl.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	add_child(lbl)
	_tray_box = HBoxContainer.new()
	_tray_box.add_theme_constant_override("separation", 4)
	add_child(_tray_box)


func _build_readout_row() -> void:
	_readout_label = Label.new()
	_readout_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_readout_label.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	_readout_label.add_theme_color_override("font_color", UiTheme.GOLD)
	add_child(_readout_label)

	_summary_label = Label.new()
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_summary_label.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	_summary_label.add_theme_color_override("font_color", UiTheme.SAFE)
	add_child(_summary_label)

	var hint := Label.new()
	hint.text = "Where you drop a chip is where that monster starts the fight — its station. Positional intent (the 5-icon strip) sets how it fights around that station."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	hint.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	add_child(hint)


func _build_legend_row() -> void:
	# ⚠️ `HFlowContainer`, NOT `HBoxContainer`, AND THE CAPTURE IS WHY. Raising these four entries
	# off 10px onto the 14px accessibility floor widened a non-wrapping row by ~40%; an HBox reports
	# that as its minimum width, the board reported it upward, and the tactics screen's THIRD column
	# (the scouted rival) was pushed off the right edge of the viewport. Nothing failed — the house
	# probe went green on the type in the same run — and it was only visible by looking at
	# `11_tactics.png`. A legend is the one row in this widget that can wrap for free.
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 14)
	row.add_theme_constant_override("v_separation", 2)
	add_child(row)
	for entry in [
		["⛨ dashed gold ring", "your aura reach"],
		["✚ gold dot", "ally covered"],
		["⚠ pulsing orange", "AoE cluster risk"],
		["▦ hashed zone", "scouted rival"],
	]:
		var l := Label.new()
		l.text = "%s — %s" % [entry[0], entry[1]]
		l.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
		l.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
		row.add_child(l)

	var motion_toggle := CheckButton.new()
	motion_toggle.text = "Reduce motion"
	motion_toggle.tooltip_text = "Freeze the AoE cluster warning pulse to a static outline."
	motion_toggle.toggled.connect(func(on): _reduce_motion = on)
	row.add_child(motion_toggle)


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# TRAY — undeployed roster chips
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _rebuild_tray() -> void:
	for c in _tray_box.get_children():
		c.queue_free()
	_tray_buttons.clear()
	for m in team_a:
		var b := Button.new()
		b.custom_minimum_size = Vector2(CHIP_SIZE + 6, CHIP_SIZE + 6)
		b.focus_mode = Control.FOCUS_ALL
		b.text = _chip_glyph(m)
		b.tooltip_text = "%s — %s · %s. Enter/Space to deploy." % [m.species_name, m.class_name_, m.role]
		b.pressed.connect(func(): _deploy_from_tray(m))
		_tray_box.add_child(b)
		_tray_buttons[m] = b
	_refresh_tray_visibility()


func _refresh_tray_visibility() -> void:
	for m in _tray_buttons:
		_tray_buttons[m].visible = not placements.has(m)


func unplaced_monsters() -> Array:
	return team_a.filter(func(m): return not placements.has(m))


func _deploy_from_tray(m) -> void:
	if placements.has(m):
		return
	var slot := _next_open_slot()
	placements[m] = slot
	_ensure_chip(m)
	_refresh_tray_visibility()
	_recompute()
	_chip_nodes[m].grab_focus.call_deferred()


## The first `Spatial.deploy_positions()` slot (clamped into `zone_a`) not already close to an
## occupied one — a sensible default landing spot for a chip dragged/pressed straight from the
## tray, not a final answer (the player repositions from there).
func _next_open_slot() -> Vector2:
	var candidates: Array = Sp.deploy_positions(team_a.size(), "A")
	for c in candidates:
		var clamped := Vector2(
			clampf(c.x, zone_a.position.x, zone_a.position.x + zone_a.size.x),
			clampf(c.y, zone_a.position.y, zone_a.position.y + zone_a.size.y))
		var free := true
		for m in placements:
			if placements[m].distance_to(clamped) < Sp.BODY_RADIUS * 2.0:
				free = false
				break
		if free:
			return clamped
	return zone_a.get_center()


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# BOARD CHIPS — deployed monsters, mouse-drag + full keyboard equivalent
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _ensure_chip(m) -> void:
	if _chip_nodes.has(m):
		return
	var chip := Control.new()
	chip.custom_minimum_size = Vector2(CHIP_SIZE, CHIP_SIZE)
	chip.size = Vector2(CHIP_SIZE, CHIP_SIZE)
	chip.focus_mode = Control.FOCUS_ALL
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.mouse_default_cursor_shape = Control.CURSOR_MOVE
	chip.tooltip_text = "%s — %s · %s\nArrows move (Shift = fine), [ ] cycles intent, Delete undeploys." % \
		[m.species_name, m.class_name_, m.role]
	chip.draw.connect(func(): _draw_chip(chip, m))
	chip.gui_input.connect(func(ev): _on_chip_input(m, chip, ev))
	chip.focus_entered.connect(func(): chip.queue_redraw())
	chip.focus_exited.connect(func(): chip.queue_redraw())
	_board_area.add_child(chip)
	_chip_nodes[m] = chip
	_position_chip(m)


func _position_chip(m) -> void:
	if not _chip_nodes.has(m) or not placements.has(m):
		return
	var chip: Control = _chip_nodes[m]
	chip.position = _world_to_px(placements[m]) - chip.size * 0.5
	chip.queue_redraw()


func _undeploy(m) -> void:
	if not placements.has(m):
		return
	placements.erase(m)
	intents.erase(m)
	guard_target.erase(m)
	if _chip_nodes.has(m):
		_chip_nodes[m].queue_free()
		_chip_nodes.erase(m)
	_refresh_tray_visibility()
	if _tray_buttons.has(m):
		_tray_buttons[m].grab_focus.call_deferred()
	_recompute()


func _on_chip_input(m, chip: Control, ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_drag_monster = m
			chip.grab_focus()
			_board_area.accept_event()
		elif _drag_monster == m:
			_drag_monster = null
			var settled := _settle_valid(placements[m], m)
			var moved_far := settled.distance_to(placements[m]) > 0.05
			placements[m] = settled
			_position_chip(m)
			if moved_far:
				_flash_until[m] = Time.get_ticks_msec() + FLASH_MS
				get_tree().create_timer(float(FLASH_MS) / 1000.0).timeout.connect(func(): if is_instance_valid(chip): chip.queue_redraw())
			_recompute()
			_board_area.accept_event()
	elif ev is InputEventMouseMotion and _drag_monster == m:
		var local: Vector2 = _board_area.get_local_mouse_position()
		var world := _px_to_world(local)
		placements[m] = world
		_position_chip(m)
		_recompute_light()
		_board_area.accept_event()
	elif ev is InputEventKey and ev.pressed:
		var step: float = FINE_SNAP if ev.shift_pressed else GRID_SNAP
		var delta := Vector2.ZERO
		match ev.keycode:
			KEY_LEFT: delta = Vector2(-step, 0)
			KEY_RIGHT: delta = Vector2(step, 0)
			KEY_UP: delta = Vector2(0, -step)
			KEY_DOWN: delta = Vector2(0, step)
			KEY_BRACKETLEFT:
				_cycle_intent(m, false)
				_board_area.accept_event()
				return
			KEY_BRACKETRIGHT:
				_cycle_intent(m, true)
				_board_area.accept_event()
				return
			KEY_DELETE, KEY_BACKSPACE:
				_undeploy(m)
				_board_area.accept_event()
				return
			KEY_ENTER, KEY_SPACE:
				if intents.get(m, "") == "guard":
					_cycle_guard_target(m)
					_board_area.accept_event()
				return
			_:
				return
		var np := _settle_valid(placements[m] + delta, m)
		placements[m] = np
		_position_chip(m)
		_recompute()
		_board_area.accept_event()


## Snap + clamp into `zone_a` + resolve overlap against other placed allies by pushing apart —
## `docs/UX_DEPLOYMENT.md` §2.2: an overshot drop settles at the nearest valid point instead of
## bouncing back to the tray.
func _settle_valid(p: Vector2, exclude) -> Vector2:
	var snapped := Vector2(roundf(p.x / GRID_SNAP) * GRID_SNAP, roundf(p.y / GRID_SNAP) * GRID_SNAP)
	snapped.x = clampf(snapped.x, zone_a.position.x, zone_a.position.x + zone_a.size.x)
	snapped.y = clampf(snapped.y, zone_a.position.y, zone_a.position.y + zone_a.size.y)
	var min_dist := Sp.BODY_RADIUS * 2.0
	for _pass in range(4):
		var moved := false
		for other in placements:
			if other == exclude:
				continue
			var op: Vector2 = placements[other]
			var d := snapped.distance_to(op)
			if d <= 0.0001:
				snapped += Vector2(min_dist * 0.5, 0.0)
				moved = true
			elif d < min_dist:
				snapped += (snapped - op).normalized() * (min_dist - d)
				moved = true
		snapped.x = clampf(snapped.x, zone_a.position.x, zone_a.position.x + zone_a.size.x)
		snapped.y = clampf(snapped.y, zone_a.position.y, zone_a.position.y + zone_a.size.y)
		if not moved:
			break
	return snapped


func _cycle_intent(m, forward: bool) -> void:
	var ids: Array = TacticsScript.POSITIONAL_INTENT_INFO.map(func(e): return e["id"])
	var cur: String = intents.get(m, "")
	var idx: int = ids.find(cur)  # -1 means "team default" (inherit)
	idx += (1 if forward else -1)
	if idx < -1:
		idx = ids.size() - 1
	elif idx >= ids.size():
		idx = -1
	if idx < 0:
		intents.erase(m)
	else:
		intents[m] = ids[idx]
		if ids[idx] != "guard":
			guard_target.erase(m)
	_recompute()


func _cycle_guard_target(m) -> void:
	var allies: Array = team_a.filter(func(u): return u != m and placements.has(u))
	if allies.is_empty():
		return
	var cur = guard_target.get(m)
	var idx := allies.find(cur)
	guard_target[m] = allies[(idx + 1) % allies.size()]
	_board_area.queue_redraw()


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# AUTO-ARRANGE / LOAD / RESET
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## Thin wrapper around `Spatial.deploy_positions()` — fills every UNDEPLOYED chip only, per
## `docs/UX_DEPLOYMENT.md` §2.4; already-placed chips are left where the player put them.
func auto_arrange() -> void:
	var candidates: Array = Sp.deploy_positions(team_a.size(), "A")
	var ci := 0
	for m in team_a:
		if placements.has(m):
			continue
		var p: Vector2 = candidates[ci % candidates.size()] if not candidates.is_empty() else zone_a.get_center()
		ci += 1
		p = Vector2(clampf(p.x, zone_a.position.x, zone_a.position.x + zone_a.size.x),
			clampf(p.y, zone_a.position.y, zone_a.position.y + zone_a.size.y))
		placements[m] = _settle_valid(p, m)
		_ensure_chip(m)
	_refresh_tray_visibility()
	_recompute()


func apply_formation(formation: Dictionary, roster: Array) -> String:
	var result: Dictionary = FormationsScript.resolve_for_roster(formation, zone_a, roster)
	for m in _chip_nodes.keys():
		_chip_nodes[m].queue_free()
	_chip_nodes.clear()
	placements.clear()
	intents.clear()
	guard_target.clear()
	_low_confidence.clear()
	for p in result["placements"]:
		var m = p["monster"]
		placements[m] = p["pos"]
		if String(p.get("intent", "")) != "":
			intents[m] = p["intent"]
		_ensure_chip(m)
	for m in result["low_confidence"]:
		_low_confidence[m] = true
	_loaded_formation = formation
	_loaded_name = String(formation.get("name", ""))
	_name_edit.text = _loaded_name
	if not formation.get("preset", false) and formation.has("name"):
		FormationsScript.touch_last_used(formation["name"])
	_refresh_tray_visibility()
	_recompute()
	return String(result["summary"])


func reset_to_loaded() -> void:
	if _loaded_formation.is_empty():
		auto_arrange()
	else:
		var summary := apply_formation(_loaded_formation, team_a)
		_summary_label.text = summary


func _on_save_new() -> void:
	var fname := _name_edit.text.strip_edges()
	if fname == "":
		fname = "Formation %s" % Time.get_datetime_string_from_system().replace("T", " ")
	FormationsScript.save(fname, team_size, zone_a, current_placements(), intents)
	_loaded_name = fname
	_refresh_gallery()
	_summary_label.text = "Saved \"%s\"." % fname


func _on_update_loaded() -> void:
	if _loaded_name == "" or _loaded_formation.get("preset", false):
		_on_save_new()
		return
	FormationsScript.update(_loaded_name, team_size, zone_a, current_placements(), intents)
	_refresh_gallery()
	_summary_label.text = "Updated \"%s\"." % _loaded_name


func current_placements() -> Array:
	var out: Array = []
	for m in team_a:
		if placements.has(m):
			out.append({"monster": m, "pos": placements[m]})
	return out


func current_intents() -> Dictionary:
	return intents.duplicate()


## The per-monster guard charge chosen on the board — MonsterInstance -> MonsterInstance, only
## for monsters whose intent is currently "guard". This is the producer `monster_tree.gd`'s
## `_positional_guard` was written expecting (`tactics.guardedAlly`) but nothing wrote until now —
## `guard_target` was drawn as a hint arrow on the board (`_draw_intent_hint`) but never left this
## file. Callers should only trust an entry here for a monster whose `current_intents()[m] ==
## "guard"`; a stale target left over from a since-changed intent is harmless (the tree only reads
## `guardedAlly` when it is dispatching the "guard" branch), but filtering here keeps the exported
## dictionary honest.
func current_guard_targets() -> Dictionary:
	var out := {}
	for m in guard_target:
		if intents.get(m, "") == "guard":
			out[m] = guard_target[m]
	return out


func zone_rect() -> Rect2:
	return zone_a


func set_team_default_intent(id: String) -> void:
	team_default_intent = id
	_board_area.queue_redraw()


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# THE SPACING TRADE-OFF, LIVE — docs/UX_DEPLOYMENT.md §4
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func spread_value() -> float:
	var pts: Array = placements.values()
	if pts.size() < 2:
		return 0.0
	var centroid := Vector2.ZERO
	for p in pts:
		centroid += p
	centroid /= float(pts.size())
	var sumsq := 0.0
	for p in pts:
		sumsq += p.distance_squared_to(centroid)
	var rms := sqrt(sumsq / float(pts.size()))
	var ur: float = Sp.usable_radius(team_size)
	if ur <= 0.0:
		return 0.0
	var norm: float = rms / ur
	return clampf((norm - Sp.SPREAD_TIGHT) / (Sp.SPREAD_LOOSE - Sp.SPREAD_TIGHT), 0.0, 1.0)


## The bucket `tactics.gd`'s already-wired `aura_coverage`/`aoe_coverage`/`spatial_ai.gd`'s leash
## read actually consume. This is the one part of this board with a REAL effect on a fight today.
func formation_bucket() -> String:
	return "loose" if spread_value() >= 0.5 else "tight"


func _recompute_light() -> void:
	# Cheap per-frame-during-drag update: just the rings/warnings redraw, no gallery/tray churn.
	_covered.clear()
	var radius: float = Sp.aura_radius(team_size)
	var sources: Array = []
	for m in placements:
		if aura_flags.get(m, false):
			sources.append(placements[m])
	for m in placements:
		var p: Vector2 = placements[m]
		var cov := false
		for sp in sources:
			if p.distance_to(sp) <= radius:
				cov = true
				break
		_covered[m] = cov
	_clusters = _compute_clusters()
	_update_readout()
	_board_area.queue_redraw()


func _recompute() -> void:
	_recompute_light()
	for m in placements:
		if _chip_nodes.has(m):
			_chip_nodes[m].queue_redraw()
	emit_signal("changed")


func _compute_clusters() -> Array:
	var pairs: Array = []
	var keys: Array = placements.keys()
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			if placements[keys[i]].distance_to(placements[keys[j]]) <= CLUSTER_RADIUS:
				pairs.append([keys[i], keys[j]])
	return pairs


func _covered_count() -> int:
	var n := 0
	for m in _covered:
		if _covered[m]:
			n += 1
	return n


func _update_readout() -> void:
	var t := spread_value()
	var bucket := "Loose" if t >= 0.5 else "Tight"
	var risk := "low" if t < 0.33 else ("medium" if t < 0.66 else "high")
	var covered := _covered_count()
	var total := placements.size()
	_readout_label.text = "Formation: %s — auras cover %d/%d, area damage risk %s" % [bucket, covered, total, risk]


func _process(delta: float) -> void:
	if _clusters.is_empty() or _reduce_motion:
		return
	_pulse_phase = fmod(_pulse_phase + delta * 2.2, TAU)
	_board_area.queue_redraw()


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# GEOMETRY MAPPING
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _recompute_scale() -> void:
	var sz: Vector2 = _board_area.size
	if sz.x <= 1.0 or sz.y <= 1.0 or ground.x <= 0.0 or ground.y <= 0.0:
		return
	_px_scale = minf(sz.x / ground.x, sz.y / ground.y)
	var used := ground * _px_scale
	_px_origin = (sz - used) * 0.5
	for m in placements:
		_position_chip(m)
	_board_area.queue_redraw()


func _world_to_px(p: Vector2) -> Vector2:
	return _px_origin + p * _px_scale


func _px_to_world(p: Vector2) -> Vector2:
	if _px_scale <= 0.0:
		return Vector2.ZERO
	return (p - _px_origin) / _px_scale


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# DRAWING
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _chip_glyph(m) -> String:
	return m.species_name.substr(0, 1).to_upper()


func _draw_chip(chip: Control, m) -> void:
	var r := Rect2(Vector2.ZERO, chip.size)
	chip.draw_rect(r, Color(0.14, 0.14, 0.18), true)
	var tex: Texture2D = Art.creature_texture(m.species_id)
	if tex != null:
		chip.draw_texture_rect(tex, r.grow(-2.0), false)
	else:
		chip.draw_string(ThemeDB.fallback_font, Vector2(6, chip.size.y - 6), _chip_glyph(m),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.92, 0.92, 0.95))

	var accent := Color(0.4, 0.65, 0.95)
	var border_col := accent
	var border_w := 1.5
	if int(Time.get_ticks_msec()) < int(_flash_until.get(m, 0)):
		border_col = Color(0.95, 0.25, 0.25)
		border_w = 3.0
	elif chip.has_focus():
		border_w = 3.0
	chip.draw_rect(r, border_col, false, border_w)
	if chip.has_focus():
		chip.draw_rect(r.grow(2.0), Color(1.0, 0.9, 0.3), false, 2.0)

	if aura_flags.get(m, false):
		chip.draw_circle(Vector2(chip.size.x - 5, 5), 3.0, Color(0.85, 0.72, 0.35))
	if _covered.get(m, false):
		chip.draw_circle(Vector2(5, chip.size.y - 5), 3.0, Color(0.5, 0.85, 0.6))
	if _low_confidence.get(m, false):
		chip.draw_string(ThemeDB.fallback_font, Vector2(chip.size.x - 10, chip.size.y - 2), "?",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.8, 0.3))


func _draw_board() -> void:
	var sz: Vector2 = _board_area.size
	_board_area.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.05, 0.06, 0.08), true)
	if _px_scale <= 0.0:
		return

	# Ruler grid every 4 world units — reference only, not a hard snap (UX_DEPLOYMENT §2.2).
	var gx := 0.0
	while gx <= ground.x:
		var x := _world_to_px(Vector2(gx, 0)).x
		_board_area.draw_line(Vector2(x, _px_origin.y), Vector2(x, _px_origin.y + ground.y * _px_scale),
			Color(1, 1, 1, 0.04), 1.0)
		gx += 4.0
	var gy := 0.0
	while gy <= ground.y:
		var y := _world_to_px(Vector2(0, gy)).y
		_board_area.draw_line(Vector2(_px_origin.x, y), Vector2(_px_origin.x + ground.x * _px_scale, y),
			Color(1, 1, 1, 0.04), 1.0)
		gy += 4.0

	# Your deployable zone.
	var za := Rect2(_world_to_px(zone_a.position), zone_a.size * _px_scale)
	_board_area.draw_rect(za, Color(0.4, 0.65, 0.95, 0.08), true)
	_board_area.draw_rect(za, Color(0.4, 0.65, 0.95, 0.5), false, 1.5)

	# Neutral strip — the corridor between the zones, off limits.
	var strip_l := _world_to_px(Vector2(zone_a.position.x + zone_a.size.x, 0)).x
	var strip_r := _world_to_px(Vector2(zone_b.position.x, 0)).x
	_board_area.draw_rect(Rect2(Vector2(strip_l, _px_origin.y), Vector2(strip_r - strip_l, ground.y * _px_scale)),
		Color(1, 1, 1, 0.03), true)

	# Scouted rival ghost zone — diagonal hash fill, per this mockup's standing "fully scouted"
	# assumption. Not colour-alone: the hash pattern itself is the tell (UX_DEPLOYMENT §4.5).
	var zb := Rect2(_world_to_px(zone_b.position), zone_b.size * _px_scale)
	_board_area.draw_rect(zb, Color(0.9, 0.45, 0.4, 0.05), true)
	_board_area.draw_rect(zb, Color(0.9, 0.45, 0.4, 0.35), false, 1.0)
	var hash_step := 10.0
	var hx := zb.position.x - zb.size.y
	while hx < zb.position.x + zb.size.x:
		var p1 := Vector2(hx, zb.position.y)
		var p2 := Vector2(hx + zb.size.y, zb.position.y + zb.size.y)
		_board_area.draw_line(_clip_to_rect(p1, p2, zb, 0), _clip_to_rect(p1, p2, zb, 1),
			Color(0.9, 0.45, 0.4, 0.18), 1.0)
		hx += hash_step
	for gp in enemy_ghost:
		_board_area.draw_circle(_world_to_px(gp), 4.0, Color(0.9, 0.45, 0.4, 0.55))

	# Aura rings — dashed gold, radius Spatial.aura_radius(team_size), one per aura source.
	var aura_r_px: float = Sp.aura_radius(team_size) * _px_scale
	for m in placements:
		if aura_flags.get(m, false):
			_draw_dashed_circle(_world_to_px(placements[m]), aura_r_px, Color(0.85, 0.72, 0.35, 0.7))

	# AoE cluster warning — pulsing orange line + burst glyph at the midpoint.
	var alpha := 0.55 if _reduce_motion else (0.35 + 0.35 * (0.5 + 0.5 * sin(_pulse_phase)))
	for pair in _clusters:
		var pa := _world_to_px(placements[pair[0]])
		var pb := _world_to_px(placements[pair[1]])
		_board_area.draw_line(pa, pb, Color(0.95, 0.55, 0.2, alpha), 2.0)
		var mid := (pa + pb) * 0.5
		_board_area.draw_string(ThemeDB.fallback_font, mid + Vector2(-4, 4), "⚠",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.95, 0.6, 0.25, alpha + 0.3))

	# Positional-intent hint arrows (illustrative only — see the caption under the board).
	var enemy_centre_px := _world_to_px(zone_b.get_center())
	for m in placements:
		var intent: String = intents.get(m, team_default_intent)
		_draw_intent_hint(m, intent)


func _draw_intent_hint(m, intent: String) -> void:
	var origin := _world_to_px(placements[m])
	var col := Color(0.75, 0.9, 0.78, 0.55)
	match intent:
		"hold":
			_board_area.draw_arc(origin, 10.0, 0, TAU, 20, col, 1.0)
		"push":
			var dir := (_world_to_px(zone_b.get_center()) - origin).normalized()
			_board_area.draw_line(origin, origin + dir * 16.0, col, 1.5)
		"wings":
			var toward_edge_y := -1.0 if placements[m].y < ground.y * 0.5 else 1.0
			var p1 := origin + Vector2(0, toward_edge_y * 12.0)
			_board_area.draw_line(origin, p1, col, 1.5)
			_board_area.draw_line(p1, p1 + Vector2(10.0, 0), col, 1.5)
		"dive":
			var dir2 := (_world_to_px(zone_b.get_center()) - origin).normalized()
			_board_area.draw_line(origin, origin + dir2 * 26.0, Color(0.9, 0.5, 0.5, 0.55), 1.5)
		"guard":
			var target = guard_target.get(m)
			if target != null and placements.has(target):
				_board_area.draw_line(origin, _world_to_px(placements[target]), Color(0.4, 0.65, 0.95, 0.5), 1.5)


func _draw_dashed_circle(center: Vector2, radius: float, color: Color) -> void:
	if radius <= 0.0:
		return
	var steps := 48
	var dash_on := true
	for i in range(steps):
		if i % 2 == 0:
			dash_on = not dash_on
		if not dash_on:
			continue
		var a0 := float(i) / float(steps) * TAU
		var a1 := float(i + 1) / float(steps) * TAU
		_board_area.draw_line(center + Vector2(cos(a0), sin(a0)) * radius,
			center + Vector2(cos(a1), sin(a1)) * radius, color, 1.5)


## Trivial line-vs-rect clip for the diagonal hash pattern — returns whichever endpoint (0 or 1)
## clamped into `rect`'s horizontal span, since the hash lines are drawn at a fixed diagonal and
## only need clamping in X to stay visually inside the ghost zone.
func _clip_to_rect(p1: Vector2, p2: Vector2, rect: Rect2, which: int) -> Vector2:
	var p := p1 if which == 0 else p2
	return Vector2(clampf(p.x, rect.position.x, rect.position.x + rect.size.x), p.y)
