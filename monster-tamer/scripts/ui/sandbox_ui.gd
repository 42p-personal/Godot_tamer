## THE SANDBOX / DEBUG ARENA — compose both teams, set tactics, run a real `SpatialSim` fight,
## then watch it with a debug overlay a player-facing screen would never show.
##
## Built per the tools-programmer brief (2026-08-04): "nobody can see whether the AI works" —
## the only ways to observe a fight were the whole career loop or a QA harness's aggregate
## numbers. This screen exists to answer, in under a minute, "does a `wings` order actually make
## that Ranger go wide?"
##
## ⚠️ THIS FILE DOES NOT REUSE `arena_3d.gd`. Two reasons, both deliberate:
##   1. Ownership — `docs/BUILD_CONTRACT.md` §3 assigns `scripts/ui/arena_3d.gd` to stream C.
##      This tool's brief is explicit: "Nothing else. If you need a change in arena_3d.gd or
##      spatial_sim.gd, describe it in your report rather than editing."
##   2. `arena_3d.gd::_resolve_teams()` hardcodes its team source to `Roster`/`Career` (falling
##      back to a fixed `Art.ROSTER[0..4]` slice at a fixed training level) and reads its tactics
##      from `TacticsScript.committed` — there is no seam to inject five arbitrary species, five
##      arbitrary training levels and independent per-side tactics without either mutating the
##      live career singletons (which would leak into the real game the moment this screen is
##      backed out of) or editing another stream's file. A flat top-down 2D debug canvas, built
##      directly against `SpatialSim`, sidesteps both problems and makes the debug overlays this
##      brief actually asks for (reach circles, heading lines, a tick stepper) trivial to draw —
##      none of which exist in the polished 3D replay, because they are not what it is for.
##
## ⚠️ THE SEED BOX CONTROLS THE SIM'S OWN COMBAT RNG ONLY — moveset assignment
## (`GameData.make_monster`'s Fisher-Yates draw) uses a FIXED rng per side, independent of the
## seed box. If the seed also reshuffled every monster's moveset, changing "one thing" (the seed,
## or a tactic) would silently also change which moves every monster knows — exactly the kind of
## confound a paired A/B tool must not introduce. Changing the seed here only perturbs the sim's
## own accuracy/crit/hit-count/tie-break rolls, so a seed sweep is a clean read on variance, and a
## tactic swap at a FIXED seed is a clean read on the tactic alone.
##
## ⚠️ HONESTY ABOUT WHAT IS AND ISN'T LIVE (found while building this, not assumed from the brief):
## `docs/AUTOBATTLER_DESIGN.md` describes four tactic axes (target priority + commitment,
## positional intent, formation, when-hurt + ability policy) as the design. `scripts/tactics.gd`
## — the file that actually drives `spatial_sim.gd` today — implements a narrower real set:
## `targetPriority` (nearest/casters/tanks/manmark), `temperament` (only `cautious` differs
## behaviourally), `manaPolicy` (normal/conserve), and `formation` (tight/loose, only felt via the
## AoE/aura coverage approximation). Positional intent (`hold`/`push`/`wings`/`dive`/`guard`) is
## authored in `tactics.gd`'s `POSITIONAL_INTENT_INFO` as forward-compatible plumbing, but
## `spatial_ai.gd`/`spatial_sim.gd` do not read it yet, and no `scripts/ai/monster_tree.gd` exists
## yet either — every unit currently runs `SpatialSim._fallback_decide()` ("nearest living enemy;
## move toward it"). This screen tells you that up front (see the on-screen notice) instead of
## silently offering a control that does nothing, which is this project's own named failure mode.
extends Control

const TacticsScript = preload("res://scripts/tactics.gd")
const Sp = preload("res://scripts/spatial.gd")
const SpatialSimScript = preload("res://scripts/spatial_sim.gd")
const ArenaLayoutScript = preload("res://scripts/arena_layout.gd")

const COLOR_A := Color(0.36, 0.62, 0.95)
const COLOR_B := Color(0.92, 0.45, 0.30)
const OBSTACLE_COLOR := {
	"soft": Color(0.55, 0.45, 0.30, 0.55),
	"hard": Color(0.55, 0.53, 0.50, 0.72),
	"blocking": Color(0.42, 0.14, 0.14, 0.88),
}
const SPEED_OPTIONS := [0.5, 1.0, 2.0, 4.0]

# ── team setup state ─────────────────────────────────────────────────────────────────────────
var team_size_a := 3
var team_size_b := 3
var plan_controls_a: Dictionary = {}
var plan_controls_b: Dictionary = {}
var slot_controls_a: Array = []
var slot_controls_b: Array = []
var _temperament_override_items: Array = []

# ── control refs ─────────────────────────────────────────────────────────────────────────────
var canvas: Control
var inspector_body: RichTextLabel
var run_btn: Button
var resolving_label: Label
var obstacles_toggle: CheckBox
var show_reach_check: CheckBox
var show_target_check: CheckBox
var show_intent_check: CheckBox
var play_btn: Button
var scrub_slider: HSlider
var time_label: Label
var verdict_label: Label
var log_view: RichTextLabel
var seed_spin: SpinBox

# ── fight state ──────────────────────────────────────────────────────────────────────────────
var sim_result: Dictionary = {}
var frames: Array = []
var team_a_units: Array = []
var team_b_units: Array = []
var all_units: Array = []
var ground_size: Vector2 = Vector2(160, 88)
var obstacles: Array = []
var _display_units: Array = []

var _used_plan_a: Dictionary = {}
var _used_plan_b: Dictionary = {}
var _used_orders: Dictionary = {}

var playing := false
var resolving := false
var frame_pos := 0.0
var speed := 1.0
var selected_idx := -1


func _ready() -> void:
	_temperament_override_items = [{
		"id": "", "icon": "—", "name": "(team default)",
		"desc": "No override — uses the team plan's temperament.",
	}]
	_temperament_override_items.append_array(TacticsScript.TEMPERAMENT_INFO)
	_build_ui()


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# UI CONSTRUCTION
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _build_ui() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0

	var bg := ColorRect.new()
	bg.color = Color(0.045, 0.045, 0.06)
	bg.anchor_right = 1.0; bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.anchor_right = 1.0; margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(outer_vbox)

	var header_row := HBoxContainer.new()
	outer_vbox.add_child(header_row)
	var title_lbl := Label.new()
	title_lbl.text = "SANDBOX / DEBUG ARENA"
	title_lbl.add_theme_font_size_override("font_size", 22)
	header_row.add_child(title_lbl)
	var subtitle := Label.new()
	subtitle.text = "   compose both teams, set tactics, run, watch, step through it"
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	header_row.add_child(subtitle)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(spacer)
	var back_btn := Button.new()
	back_btn.text = "◀ Title"
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/title.tscn"))
	header_row.add_child(back_btn)

	var notice := Label.new()
	notice.text = ("⚠ LIVE today: target priority, temperament (cautious only), mana policy, formation. " +
		"NOT yet read by the sim: positional intent (hold/push/wings/dive/guard) — recorded here " +
		"for when it lands, but expect zero behavioural difference from that axis right now. No " +
		"scripts/ai/monster_tree.gd exists yet either, so every unit runs the sim's own fallback: " +
		"nearest living enemy, close and swing.")
	notice.add_theme_font_size_override("font_size", 11)
	notice.add_theme_color_override("font_color", Color(0.85, 0.7, 0.4))
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer_vbox.add_child(notice)

	var main_row := HBoxContainer.new()
	main_row.add_theme_constant_override("separation", 10)
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(main_row)

	main_row.add_child(_build_team_panel("A"))
	main_row.add_child(_build_center_panel())
	main_row.add_child(_build_team_panel("B"))


func _build_team_panel(side: String) -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(outer)

	var header := Label.new()
	header.text = "TEAM %s" % side
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", COLOR_A if side == "A" else COLOR_B)
	outer.add_child(header)

	var size_row := HBoxContainer.new()
	outer.add_child(size_row)
	var size_lbl := Label.new()
	size_lbl.text = "Team size"
	size_row.add_child(size_lbl)
	var size_spin := SpinBox.new()
	size_spin.min_value = 1; size_spin.max_value = 5; size_spin.step = 1; size_spin.value = 3
	size_row.add_child(size_spin)

	outer.add_child(HSeparator.new())
	var plan_lbl := Label.new()
	plan_lbl.text = "Team plan"
	plan_lbl.add_theme_font_size_override("font_size", 13)
	outer.add_child(plan_lbl)

	var plan_ctrl: Dictionary = {}
	plan_ctrl["target_priority"] = _labeled_option(outer, "Target priority", TacticsScript.TARGET_PRIORITY_INFO, "")
	plan_ctrl["temperament"] = _labeled_option(outer, "Temperament", TacticsScript.TEMPERAMENT_INFO, "aggressive")
	plan_ctrl["mana_policy"] = _labeled_option(outer, "Mana policy", TacticsScript.MANA_POLICY_INFO, "normal")
	plan_ctrl["formation"] = _labeled_option(outer, "Formation", TacticsScript.FORMATION_INFO, "tight")

	outer.add_child(HSeparator.new())
	var slots_lbl := Label.new()
	slots_lbl.text = "Roster (per-monster overrides)"
	slots_lbl.add_theme_font_size_override("font_size", 13)
	outer.add_child(slots_lbl)

	var slots_vbox := VBoxContainer.new()
	slots_vbox.add_theme_constant_override("separation", 4)
	outer.add_child(slots_vbox)

	var slots: Array = []
	for i in range(5):
		slots.append(_build_slot_row(side, i, slots_vbox))

	if side == "A":
		plan_controls_a = plan_ctrl
		slot_controls_a = slots
	else:
		plan_controls_b = plan_ctrl
		slot_controls_b = slots

	size_spin.value_changed.connect(func(v: float): _on_team_size_changed(side, int(v)))
	_on_team_size_changed(side, int(size_spin.value))

	return scroll


func _labeled_option(parent: VBoxContainer, label_text: String, info_list: Array, default_id: String) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(96, 0)
	row.add_child(lbl)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ob)
	_populate_info_option(ob, info_list, default_id)
	return ob


## ⚠️ Hover tooltips were dropped on purpose: `OptionButton.get_popup()` is populated here while
## the whole panel is still an orphan subtree (built and returned before `main_row.add_child()`
## attaches it), and item tooltips on a not-yet-in-tree PopupMenu are not a risk worth taking for
## a nicety. Full axis descriptions already live in `tactics.gd`'s own `*_INFO` tables and in the
## Inspector's "Orders" readout, which resolves the actual value in play.
func _populate_info_option(ob: OptionButton, info_list: Array, default_id: String) -> void:
	ob.clear()
	var default_idx := 0
	for i in range(info_list.size()):
		var entry: Dictionary = info_list[i]
		ob.add_item("%s %s" % [str(entry.get("icon", "")), str(entry.get("name", ""))])
		ob.set_item_metadata(i, entry.get("id", ""))
		if str(entry.get("id", "")) == default_id:
			default_idx = i
	ob.selected = default_idx


func _populate_species_option(ob: OptionButton, default_index: int) -> void:
	ob.clear()
	for i in range(Art.ROSTER.size()):
		var sid: String = Art.ROSTER[i]
		var sp: Dictionary = GameData.species_by_id.get(sid, {})
		ob.add_item(str(sp.get("name", sid)))
		ob.set_item_metadata(i, sid)
	ob.selected = clampi(default_index, 0, Art.ROSTER.size() - 1)


func _build_slot_row(side: String, i: int, slots_vbox: VBoxContainer) -> Dictionary:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.10, 0.7)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6; sb.content_margin_right = 6
	sb.content_margin_top = 4; sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)
	slots_vbox.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 4)
	col.add_child(row1)
	var idx_lbl := Label.new()
	idx_lbl.text = "%d" % (i + 1)
	idx_lbl.custom_minimum_size = Vector2(14, 0)
	row1.add_child(idx_lbl)
	var species_btn := OptionButton.new()
	species_btn.custom_minimum_size = Vector2(140, 0)
	species_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(species_btn)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	col.add_child(row2)
	var tr_lbl := Label.new()
	tr_lbl.text = "train"
	tr_lbl.add_theme_font_size_override("font_size", 11)
	row2.add_child(tr_lbl)
	var training_slider := HSlider.new()
	training_slider.min_value = 0.0
	training_slider.max_value = 1.0
	training_slider.step = 0.01
	training_slider.value = 0.3
	training_slider.custom_minimum_size = Vector2(70, 0)
	training_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(training_slider)
	var tr_val := Label.new()
	tr_val.text = "30%"
	tr_val.custom_minimum_size = Vector2(34, 0)
	tr_val.add_theme_font_size_override("font_size", 11)
	row2.add_child(tr_val)
	training_slider.value_changed.connect(func(v: float): tr_val.text = "%d%%" % int(round(v * 100.0)))

	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 4)
	col.add_child(row3)
	var prio_lbl := Label.new()
	prio_lbl.text = "target"
	prio_lbl.add_theme_font_size_override("font_size", 10)
	row3.add_child(prio_lbl)
	var priority_override := OptionButton.new()
	priority_override.custom_minimum_size = Vector2(64, 0)
	priority_override.add_theme_font_size_override("font_size", 10)
	row3.add_child(priority_override)
	var temp_lbl := Label.new()
	temp_lbl.text = "mood"
	temp_lbl.add_theme_font_size_override("font_size", 10)
	row3.add_child(temp_lbl)
	var temperament_override := OptionButton.new()
	temperament_override.custom_minimum_size = Vector2(64, 0)
	temperament_override.add_theme_font_size_override("font_size", 10)
	row3.add_child(temperament_override)

	_populate_species_option(species_btn, (i + (0 if side == "A" else 6)) % Art.ROSTER.size())
	_populate_info_option(priority_override, TacticsScript.TARGET_PRIORITY_INFO, "")
	_populate_info_option(temperament_override, _temperament_override_items, "")

	return {
		"panel": panel, "species_btn": species_btn, "training_slider": training_slider,
		"priority_override": priority_override, "temperament_override": temperament_override,
	}


func _on_team_size_changed(side: String, v: int) -> void:
	if side == "A":
		team_size_a = v
		for i in range(slot_controls_a.size()):
			(slot_controls_a[i]["panel"] as Control).visible = i < v
	else:
		team_size_b = v
		for i in range(slot_controls_b.size()):
			(slot_controls_b[i]["panel"] as Control).visible = i < v


func _build_center_panel() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var run_row := HBoxContainer.new()
	run_row.add_theme_constant_override("separation", 8)
	col.add_child(run_row)

	var seed_lbl := Label.new()
	seed_lbl.text = "Seed"
	run_row.add_child(seed_lbl)
	seed_spin = SpinBox.new()
	seed_spin.min_value = 0
	seed_spin.max_value = 999999999
	seed_spin.step = 1
	seed_spin.value = 20260804
	seed_spin.custom_minimum_size = Vector2(130, 0)
	run_row.add_child(seed_spin)

	var rand_seed_btn := Button.new()
	rand_seed_btn.text = "↺"  # was 🎲, which is not in the packaged Inter face; ↺ (reroll) is
	rand_seed_btn.tooltip_text = "Randomize the seed (UI convenience only — the sim itself stays deterministic per seed)"
	rand_seed_btn.pressed.connect(func(): seed_spin.value = randi() % 999999999)
	run_row.add_child(rand_seed_btn)

	obstacles_toggle = CheckBox.new()
	obstacles_toggle.text = "Obstacles"
	obstacles_toggle.button_pressed = true
	run_row.add_child(obstacles_toggle)

	run_btn = Button.new()
	run_btn.text = "▶ Run Fight"
	run_btn.custom_minimum_size = Vector2(140, 36)
	run_btn.pressed.connect(_on_run_pressed)
	run_row.add_child(run_btn)

	resolving_label = Label.new()
	resolving_label.text = "resolving…"
	resolving_label.visible = false
	resolving_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	run_row.add_child(resolving_label)

	var viewport_row := HBoxContainer.new()
	viewport_row.add_theme_constant_override("separation", 8)
	viewport_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(viewport_row)

	var canvas_wrap := PanelContainer.new()
	var cw_sb := StyleBoxFlat.new()
	cw_sb.bg_color = Color(0.03, 0.03, 0.04)
	cw_sb.set_border_width_all(1)
	cw_sb.border_color = Color(0.25, 0.25, 0.3)
	canvas_wrap.add_theme_stylebox_override("panel", cw_sb)
	canvas_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_row.add_child(canvas_wrap)

	canvas = Control.new()
	canvas.custom_minimum_size = Vector2(560, 380)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.draw.connect(_on_canvas_draw)
	canvas.gui_input.connect(_on_canvas_input)
	canvas.resized.connect(func(): canvas.queue_redraw())
	canvas_wrap.add_child(canvas)

	viewport_row.add_child(_build_inspector_panel())

	var overlay_row := HBoxContainer.new()
	overlay_row.add_theme_constant_override("separation", 10)
	col.add_child(overlay_row)
	show_reach_check = CheckBox.new()
	show_reach_check.text = "Reach circles"
	show_reach_check.button_pressed = true
	show_reach_check.toggled.connect(func(_v: bool): canvas.queue_redraw())
	overlay_row.add_child(show_reach_check)
	show_target_check = CheckBox.new()
	show_target_check.text = "Heading lines (straight-line approx.)"
	show_target_check.button_pressed = true
	show_target_check.toggled.connect(func(_v: bool): canvas.queue_redraw())
	overlay_row.add_child(show_target_check)
	show_intent_check = CheckBox.new()
	show_intent_check.text = "Intent labels"
	show_intent_check.button_pressed = true
	show_intent_check.toggled.connect(func(_v: bool): canvas.queue_redraw())
	overlay_row.add_child(show_intent_check)

	var playback_row := HBoxContainer.new()
	playback_row.add_theme_constant_override("separation", 6)
	col.add_child(playback_row)

	var to_start_btn := Button.new()
	to_start_btn.text = "|◀"
	to_start_btn.pressed.connect(func(): _seek(0.0))
	playback_row.add_child(to_start_btn)
	var step_back_btn := Button.new()
	step_back_btn.text = "◀ step"
	step_back_btn.pressed.connect(func(): _seek(frame_pos - 1.0))
	playback_row.add_child(step_back_btn)
	play_btn = Button.new()
	play_btn.text = "▶ Play"
	play_btn.custom_minimum_size = Vector2(84, 0)
	play_btn.pressed.connect(_on_play_pause_pressed)
	playback_row.add_child(play_btn)
	var step_fwd_btn := Button.new()
	step_fwd_btn.text = "step ▶"
	step_fwd_btn.pressed.connect(func(): _seek(frame_pos + 1.0))
	playback_row.add_child(step_fwd_btn)
	var to_end_btn := Button.new()
	to_end_btn.text = "▶|"
	to_end_btn.pressed.connect(func(): _seek(float(maxi(0, frames.size() - 1))))
	playback_row.add_child(to_end_btn)

	scrub_slider = HSlider.new()
	scrub_slider.min_value = 0; scrub_slider.max_value = 0; scrub_slider.step = 1
	scrub_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scrub_slider.editable = false
	scrub_slider.value_changed.connect(_on_scrub_changed)
	playback_row.add_child(scrub_slider)

	time_label = Label.new()
	time_label.text = "t = 0.0s"
	time_label.custom_minimum_size = Vector2(160, 0)
	playback_row.add_child(time_label)

	var speed_ob := OptionButton.new()
	for s in SPEED_OPTIONS:
		speed_ob.add_item("%sx" % str(s))
	speed_ob.selected = 1
	speed_ob.item_selected.connect(func(idx: int): speed = SPEED_OPTIONS[idx])
	playback_row.add_child(speed_ob)

	verdict_label = Label.new()
	verdict_label.text = "Run a fight to see the verdict."
	verdict_label.add_theme_font_size_override("font_size", 14)
	col.add_child(verdict_label)

	var log_scroll := ScrollContainer.new()
	log_scroll.custom_minimum_size = Vector2(0, 130)
	col.add_child(log_scroll)
	log_view = RichTextLabel.new()
	log_view.fit_content = true
	log_view.bbcode_enabled = false
	log_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(log_view)

	return col


func _build_inspector_panel() -> Control:
	var wrap := PanelContainer.new()
	wrap.custom_minimum_size = Vector2(260, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.08, 0.9)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	wrap.add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	wrap.add_child(col)
	var title := Label.new()
	title.text = "INSPECTOR"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	col.add_child(title)
	inspector_body = RichTextLabel.new()
	inspector_body.fit_content = true
	inspector_body.bbcode_enabled = true
	inspector_body.text = "Click a unit to inspect it."
	col.add_child(inspector_body)
	return wrap


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# RUNNING A FIGHT
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _on_run_pressed() -> void:
	await _run_fight()


## ⚠️ Team-generation rng is FIXED per side, independent of `seed_spin` — see the file header.
func _collect_team(side: String) -> Array:
	var count: int = team_size_a if side == "A" else team_size_b
	var slots: Array = slot_controls_a if side == "A" else slot_controls_b
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 if side == "A" else 1000003
	var out: Array = []
	for i in range(count):
		var sc: Dictionary = slots[i]
		var species_ob: OptionButton = sc["species_btn"]
		var species_id := str(species_ob.get_item_metadata(species_ob.selected))
		var training_slider: HSlider = sc["training_slider"]
		var mi = GameData.make_monster(species_id, training_slider.value, rng)
		out.append(mi)
	return out


func _collect_plan(side: String) -> Dictionary:
	var ctrl: Dictionary = plan_controls_a if side == "A" else plan_controls_b
	var plan: Dictionary = {}
	var tp_ob: OptionButton = ctrl["target_priority"]
	var tp = tp_ob.get_item_metadata(tp_ob.selected)
	if str(tp) != "":
		plan["targetPriority"] = tp
	var temp_ob: OptionButton = ctrl["temperament"]
	plan["temperament"] = temp_ob.get_item_metadata(temp_ob.selected)
	var mana_ob: OptionButton = ctrl["mana_policy"]
	plan["manaPolicy"] = mana_ob.get_item_metadata(mana_ob.selected)
	var form_ob: OptionButton = ctrl["formation"]
	plan["formation"] = form_ob.get_item_metadata(form_ob.selected)
	return plan


func _collect_orders(side: String, units: Array) -> Dictionary:
	var count: int = team_size_a if side == "A" else team_size_b
	var slots: Array = slot_controls_a if side == "A" else slot_controls_b
	var orders: Dictionary = {}
	for i in range(count):
		var sc: Dictionary = slots[i]
		var m = units[i]
		var ov: Dictionary = {}
		var tp_ob: OptionButton = sc["priority_override"]
		var tp = tp_ob.get_item_metadata(tp_ob.selected)
		if str(tp) != "":
			ov["targetPriority"] = tp
		var temp_ob: OptionButton = sc["temperament_override"]
		var temp = temp_ob.get_item_metadata(temp_ob.selected)
		if str(temp) != "":
			ov["temperament"] = temp
		if not ov.is_empty():
			orders[m] = ov
	return orders


func _run_fight() -> void:
	if resolving:
		return
	resolving = true
	run_btn.disabled = true
	resolving_label.visible = true
	playing = false
	selected_idx = -1
	inspector_body.text = "Click a unit to inspect it."

	var seed_value := int(seed_spin.value)

	var team_a := _collect_team("A")
	var team_b := _collect_team("B")
	var plan_a := _collect_plan("A")
	var plan_b := _collect_plan("B")
	var orders: Dictionary = {}
	var orders_a := _collect_orders("A", team_a)
	var orders_b := _collect_orders("B", team_b)
	for k in orders_a:
		orders[k] = orders_a[k]
	for k in orders_b:
		orders[k] = orders_b[k]

	var team_sz: int = maxi(team_a.size(), team_b.size())
	var obs: Array = []
	if obstacles_toggle.button_pressed:
		var lay_rng := RandomNumberGenerator.new()
		lay_rng.seed = seed_value
		var lay: Dictionary = ArenaLayoutScript.generate(team_sz, "Wood", lay_rng)
		obs = lay.get("obstacles", [])

	var sim = SpatialSimScript.new(team_a, team_b, seed_value, plan_a, plan_b, orders, obs)
	var result: Dictionary = await sim.run()

	sim_result = result
	frames = result.get("frames", [])
	team_a_units = team_a
	team_b_units = team_b
	all_units = team_a + team_b
	ground_size = result.get("groundSize", Sp.ground_size(team_sz))
	obstacles = result.get("obstacles", obs)
	_used_plan_a = plan_a
	_used_plan_b = plan_b
	_used_orders = orders

	frame_pos = 0.0
	scrub_slider.max_value = maxf(0.0, float(frames.size() - 1))
	scrub_slider.editable = not frames.is_empty()
	_apply_display_frame()
	playing = not frames.is_empty()
	_update_play_button()
	_update_verdict()
	_update_log()

	resolving = false
	run_btn.disabled = false
	resolving_label.visible = false


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# PLAYBACK — tick stepper: pause, step, scrub, speed
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if not playing or frames.is_empty():
		return
	frame_pos += delta * speed * 10.0
	if frame_pos >= float(frames.size() - 1):
		frame_pos = float(frames.size() - 1)
		playing = false
		_update_play_button()
	_apply_display_frame()


func _seek(v: float) -> void:
	if frames.is_empty():
		return
	playing = false
	_update_play_button()
	frame_pos = clampf(v, 0.0, float(frames.size() - 1))
	_apply_display_frame()


func _on_scrub_changed(v: float) -> void:
	if frames.is_empty():
		return
	playing = false
	_update_play_button()
	frame_pos = clampf(v, 0.0, float(frames.size() - 1))
	_apply_display_frame()


func _on_play_pause_pressed() -> void:
	if frames.is_empty():
		return
	playing = not playing
	_update_play_button()


func _update_play_button() -> void:
	if play_btn != null:
		play_btn.text = "Pause" if playing else "▶ Play"  # ⏸ is not in the packaged Inter face


func _apply_display_frame() -> void:
	if frames.is_empty():
		_display_units = []
		canvas.queue_redraw()
		return
	var i: int = clampi(int(floor(frame_pos)), 0, frames.size() - 1)
	var j: int = mini(i + 1, frames.size() - 1)
	var t: float = frame_pos - float(i)
	var fa: Dictionary = frames[i]
	var fb: Dictionary = frames[j]
	var ua: Array = fa.get("units", [])
	var ub: Array = fb.get("units", [])
	var out: Array = []
	for k in range(ua.size()):
		var ra: Dictionary = ua[k]
		var rb: Dictionary = ub[k] if k < ub.size() else ra
		var pa: Vector2 = ra.get("pos", Vector2.ZERO)
		var pb: Vector2 = rb.get("pos", pa)
		var merged: Dictionary = ra.duplicate()
		merged["pos"] = pa.lerp(pb, t)
		out.append(merged)
	_display_units = out
	scrub_slider.set_value_no_signal(frame_pos)
	time_label.text = "t = %.1fs   frame %d / %d" % [float(fa.get("t", 0.0)), i, maxi(0, frames.size() - 1)]
	if selected_idx >= 0:
		_refresh_inspector()
	canvas.queue_redraw()


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# CANVAS — top-down debug view. Draws only what the frame stream gave us, plus two derived
# overlays computed HERE (not in spatial_sim.gd — see the file header on ownership):
##   · reach circles, from `Sp.reach_of` over each unit's own moveset (a pure, shared helper)
##   · heading lines, a straight line from unit to its current `targetId` — an HONEST
##     approximation of "where a unit is heading", since the frame contract does not (yet) carry
##     the navmesh waypoint path. Flagged in the checkbox label and in the report, not hidden.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _canvas_transform() -> Dictionary:
	var csize: Vector2 = canvas.size
	var pad := 12.0
	var avail := Vector2(maxf(csize.x - pad * 2.0, 1.0), maxf(csize.y - pad * 2.0, 1.0))
	var gx := maxf(ground_size.x, 1.0)
	var gy := maxf(ground_size.y, 1.0)
	var px_scale: float = minf(avail.x / gx, avail.y / gy)
	var offset: Vector2 = (csize - ground_size * px_scale) * 0.5
	return {"scale": px_scale, "offset": offset}


func _on_canvas_draw() -> void:
	var xf := _canvas_transform()
	var px_scale: float = xf["scale"]
	var offset: Vector2 = xf["offset"]

	canvas.draw_rect(Rect2(offset, ground_size * px_scale), Color(0.09, 0.13, 0.09))

	for o in obstacles:
		var r: Rect2 = o.get("rect", Rect2())
		var grade := str(o.get("grade", "soft"))
		var col: Color = OBSTACLE_COLOR.get(grade, Color(0.5, 0.5, 0.5, 0.5))
		canvas.draw_rect(Rect2(offset + r.position * px_scale, r.size * px_scale), col)

	var font := canvas.get_theme_default_font()
	var fsize := canvas.get_theme_default_font_size()

	if _display_units.is_empty():
		canvas.draw_string(font, offset + ground_size * px_scale * 0.5 - Vector2(140, 0),
			"Set up both teams and press ▶ Run Fight.", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize,
			Color(0.6, 0.6, 0.65))
		return

	if show_target_check.button_pressed:
		for k in range(_display_units.size()):
			var rec: Dictionary = _display_units[k]
			if not bool(rec.get("alive", false)):
				continue
			var tid := int(rec.get("targetId", -1))
			if tid < 0 or tid >= _display_units.size():
				continue
			var trec: Dictionary = _display_units[tid]
			var p1: Vector2 = offset + (rec.get("pos", Vector2.ZERO) as Vector2) * px_scale
			var p2: Vector2 = offset + (trec.get("pos", Vector2.ZERO) as Vector2) * px_scale
			var lcol: Color = COLOR_A if k < team_a_units.size() else COLOR_B
			lcol.a = 0.32
			canvas.draw_line(p1, p2, lcol, 1.5)

	if show_reach_check.button_pressed:
		for k in range(_display_units.size()):
			var rec2: Dictionary = _display_units[k]
			if not bool(rec2.get("alive", false)) or k >= all_units.size():
				continue
			var m = all_units[k]
			var reach := _unit_reach(m)
			var center: Vector2 = offset + (rec2.get("pos", Vector2.ZERO) as Vector2) * px_scale
			var rad := reach * px_scale
			var rcol: Color = COLOR_A if k < team_a_units.size() else COLOR_B
			rcol.a = 0.55 if k == selected_idx else 0.14
			_draw_circle_outline(center, rad, rcol, 1.5 if k == selected_idx else 1.0)

	for k in range(_display_units.size()):
		var rec3: Dictionary = _display_units[k]
		var pos: Vector2 = offset + (rec3.get("pos", Vector2.ZERO) as Vector2) * px_scale
		var alive3: bool = bool(rec3.get("alive", false))
		var side_a3: bool = k < team_a_units.size()
		var base_col: Color = COLOR_A if side_a3 else COLOR_B
		var col3: Color = base_col if alive3 else base_col.darkened(0.65)
		var r3 := 7.0 if k == selected_idx else 5.0
		if side_a3:
			canvas.draw_circle(pos, r3, col3)
		else:
			canvas.draw_rect(Rect2(pos - Vector2(r3, r3), Vector2(r3, r3) * 2.0), col3)
		if k == selected_idx:
			_draw_circle_outline(pos, r3 + 3.0, Color(1, 1, 1, 0.9), 2.0)
		if not alive3:
			continue
		if k < all_units.size():
			canvas.draw_string(font, pos + Vector2(-14, -10), (all_units[k].species_name as String).left(10),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col3)
		if show_intent_check.button_pressed:
			var intent := str(rec3.get("intent", ""))
			if intent != "":
				var tid2 := int(rec3.get("targetId", -1))
				var tname := ""
				if tid2 >= 0 and tid2 < all_units.size():
					tname = " → " + all_units[tid2].species_name
				canvas.draw_string(font, pos + Vector2(-14, 20), (intent + tname).left(30),
					HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.85, 0.85, 0.88))


func _draw_circle_outline(center: Vector2, radius: float, col: Color, width: float) -> void:
	if radius <= 0.0:
		return
	var pts := PackedVector2Array()
	var segs := 40
	for i in range(segs + 1):
		var t := TAU * float(i) / float(segs)
		pts.append(center + Vector2(cos(t), sin(t)) * radius)
	canvas.draw_polyline(pts, col, width)


func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		selected_idx = _pick_unit_at(event.position)
		_refresh_inspector()
		canvas.queue_redraw()


func _pick_unit_at(local_pos: Vector2) -> int:
	var xf := _canvas_transform()
	var px_scale: float = xf["scale"]
	var offset: Vector2 = xf["offset"]
	var best := -1
	var best_d := 16.0
	for k in range(_display_units.size()):
		var rec: Dictionary = _display_units[k]
		var p: Vector2 = offset + (rec.get("pos", Vector2.ZERO) as Vector2) * px_scale
		var d := p.distance_to(local_pos)
		if d < best_d:
			best_d = d
			best = k
	return best


## The longest reach among `m`'s ENEMY-targeted moves, basic included — the exact definition
## `spatial_sim.gd::_best_reach()` uses to gate movement/standoff, duplicated here (not imported,
## since it is a private method) so the overlay shows what the sim's own movement logic sees, not
## a guess at it.
func _unit_reach(m) -> float:
	var best: float = Sp.reach_of(m.basic_attack, true)
	for mv in m.moveset:
		if str(mv.get("target", "enemy")) != "enemy":
			continue
		var r: float = Sp.reach_of(mv, false)
		if r > best:
			best = r
	return best


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# INSPECTOR
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _refresh_inspector() -> void:
	if selected_idx < 0 or selected_idx >= _display_units.size() or selected_idx >= all_units.size():
		inspector_body.text = "Click a unit to inspect it."
		return
	var rec: Dictionary = _display_units[selected_idx]
	var m = all_units[selected_idx]
	var side := "A" if selected_idx < team_a_units.size() else "B"
	var lines: Array = []
	lines.append("[b]%s[/b]  (Team %s)" % [m.species_name, side])
	lines.append("Class: %s   Role: %s" % [m.class_name_, m.role])
	lines.append("HP %.0f / %d    MP %.0f / %d" % [float(rec.get("hp", m.hp)), m.max_hp, float(rec.get("mp", m.mp)), m.max_mp])
	lines.append("State: %s" % str(rec.get("state", "")))
	var tid := int(rec.get("targetId", -1))
	var target_name: String = "-" if (tid < 0 or tid >= all_units.size()) else all_units[tid].species_name
	lines.append("Target: %s" % target_name)
	lines.append("Intent: %s" % str(rec.get("intent", "(none reported — see the notice above)")))
	var reason := str(rec.get("reason", ""))
	if reason != "":
		lines.append("Reason: %s" % reason)
	lines.append("Best reach: %.1f units" % _unit_reach(m))
	var statuses: Array = rec.get("statuses", [])
	lines.append("Statuses: %s" % (", ".join(statuses) if not statuses.is_empty() else "none"))
	lines.append("")
	lines.append("[b]Orders[/b]")
	for row in _orders_summary(m, side):
		lines.append("%s: %s (%s)" % [row["axis"], row["value"], row["tag"]])
	inspector_body.text = "\n".join(lines)


func _orders_summary(m, side: String) -> Array:
	var plan: Dictionary = _used_plan_a if side == "A" else _used_plan_b
	var own: Dictionary = _used_orders.get(m, {})
	var out: Array = []

	var tp_has := own.has("targetPriority")
	var tp_val = own.get("targetPriority", plan.get("targetPriority", ""))
	var tp_info: Dictionary = TacticsScript.info_by_id(TacticsScript.TARGET_PRIORITY_INFO, tp_val)
	if tp_info.is_empty():
		tp_info = TacticsScript.TARGET_PRIORITY_INFO[0]
	out.append({
		"axis": "Target priority", "value": str(tp_info.get("name", "")),
		"tag": "your override" if tp_has else ("team plan" if plan.has("targetPriority") else "engine default"),
	})

	var temp_has := own.has("temperament")
	var temp_val := str(own.get("temperament", plan.get("temperament", "aggressive")))
	var temp_info: Dictionary = TacticsScript.info_by_id(TacticsScript.TEMPERAMENT_INFO, temp_val)
	out.append({
		"axis": "Temperament", "value": str(temp_info.get("name", temp_val)),
		"tag": "your override" if temp_has else "team plan",
	})

	var mana_val := str(plan.get("manaPolicy", "normal"))
	var mana_info: Dictionary = TacticsScript.info_by_id(TacticsScript.MANA_POLICY_INFO, mana_val)
	out.append({"axis": "Mana policy", "value": str(mana_info.get("name", mana_val)), "tag": "team plan"})

	var form_val := str(plan.get("formation", "tight"))
	var form_info: Dictionary = TacticsScript.info_by_id(TacticsScript.FORMATION_INFO, form_val)
	out.append({"axis": "Formation", "value": str(form_info.get("name", form_val)), "tag": "team plan"})

	return out


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# VERDICT — duration, survivors, board coverage (the anti-blob number)
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _coverage_at_frame(frame: Dictionary) -> float:
	var pts: Array = []
	for rec in frame.get("units", []):
		if bool(rec.get("alive", false)):
			pts.append(rec.get("pos", Vector2.ZERO) as Vector2)
	if pts.size() < 2:
		return 0.0
	var mn: Vector2 = pts[0]
	var mx: Vector2 = pts[0]
	for p in pts:
		mn.x = minf(mn.x, p.x); mn.y = minf(mn.y, p.y)
		mx.x = maxf(mx.x, p.x); mx.y = maxf(mx.y, p.y)
	var area := (mx.x - mn.x) * (mx.y - mn.y)
	var ground_area := ground_size.x * ground_size.y
	return 0.0 if ground_area <= 0.0 else clampf(area / ground_area, 0.0, 1.0)


## `peak` (widest the living bounding box ever got) is the anti-blob read: a persistently low
## peak across a whole fight means the AI never used the board's width regardless of how it ends.
## `mid`/`final` are cheap extra context (a fight that starts spread and collapses to a 1v1 will
## show peak high, final near zero — expected, not a bug).
func _compute_coverage_summary() -> Dictionary:
	if frames.is_empty():
		return {"peak": 0.0, "mid": 0.0, "final": 0.0}
	var peak := 0.0
	for f in frames:
		var c := _coverage_at_frame(f)
		if c > peak:
			peak = c
	var mid_idx := int(frames.size() / 2)
	return {
		"peak": peak, "mid": _coverage_at_frame(frames[mid_idx]),
		"final": _coverage_at_frame(frames[frames.size() - 1]),
	}


func _update_verdict() -> void:
	var w := str(sim_result.get("winner", "?"))
	var dur := float(sim_result.get("duration", 0.0))
	var sa := int(sim_result.get("survivorsA", 0))
	var sb := int(sim_result.get("survivorsB", 0))
	var cov := _compute_coverage_summary()
	verdict_label.text = ("Winner: %s    Duration: %.1fs    Survivors A/B: %d/%d    " +
		"Board coverage — peak %d%%  mid %d%%  final %d%%") % [
		w, dur, sa, sb,
		int(round(float(cov["peak"]) * 100.0)), int(round(float(cov["mid"]) * 100.0)),
		int(round(float(cov["final"]) * 100.0)),
	]


func _update_log() -> void:
	var lines: Array = []
	for e in sim_result.get("log", []):
		lines.append(_format_log_entry(e))
	log_view.text = "\n".join(lines)


func _format_log_entry(e: Dictionary) -> String:
	var t := float(e.get("t", 0.0))
	var kind := str(e.get("kind", ""))
	match kind:
		"start":
			var ta: Array = e.get("teamA", [])
			var tb: Array = e.get("teamB", [])
			return "%.1fs  Fight begins — %s  vs  %s" % [t, ", ".join(ta), ", ".join(tb)]
		"hit":
			return "%.1fs  %s uses %s on %s — %d dmg%s" % [
				t, e.get("attacker", ""), e.get("move", ""), e.get("target", ""),
				int(e.get("dmg", 0)), (" (crit)" if e.get("crit", false) else "")]
		"miss":
			return "%.1fs  %s uses %s on %s — miss" % [t, e.get("attacker", ""), e.get("move", ""), e.get("target", "")]
		"status_apply":
			return "%.1fs  %s afflicted with %s (from %s)" % [t, e.get("unit", ""), e.get("status", ""), e.get("from", "")]
		"status_expire":
			return "%.1fs  %s's %s expires" % [t, e.get("unit", ""), e.get("status", "")]
		"buff":
			return "%.1fs  %s casts %s on %s" % [t, e.get("caster", ""), e.get("move", ""), e.get("unit", "")]
		"death":
			var killer := str(e.get("killer", ""))
			return "%.1fs  %s dies%s" % [t, e.get("unit", ""), (" — killed by %s" % killer) if killer != "" else ""]
		"end":
			return "%.1fs  Fight ends — winner %s" % [t, e.get("winner", "")]
		_:
			return "%.1fs  %s" % [t, kind]
