## THE BATTLE — 5v5, using the verified contract math. The player never intervenes: press start,
## then watch. This screen's whole job is legibility of a fight it does not let you touch.
##
## ⚠️ NON-SPATIAL MOCKUP, NOT THE FIELD ENGINE — see the header of battle_sim.gd. This is
## presentation over BattleSim's already-complete event log (run headlessly, then replayed at a
## watchable pace), the same pure-sim/presentation split `battleReport.ts` uses.
extends Control

const BattleSimScript = preload("res://scripts/battle_sim.gd")

const TEAM_SIZE := 5
const PLAYBACK_SECONDS := 22.0  # wall-clock target regardless of how many events the sim logged

var unit_rows: Dictionary = {}  # MonsterInstance -> {hp_bar, mp_bar, name_label, status_label}
var log_view: RichTextLabel
var log_scroll: ScrollContainer
var result_label: Label
var start_btn: Button
var skip_btn: Button

var sim: BattleSimScript = null
var battle_result: Dictionary = {}
var playback_index := 0
var playback_accum := 0.0
var playing := false


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.1)
	bg.anchor_right = 1; bg.anchor_bottom = 1
	add_child(bg)

	var margin := MarginContainer.new()
	margin.anchor_right = 1; margin.anchor_bottom = 1
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "5v5 — Your Stable vs. a Rival Team"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35))
	vbox.add_child(title)

	var teams_row := HBoxContainer.new()
	teams_row.add_theme_constant_override("separation", 24)
	# Deliberately NOT size_flags_vertical = EXPAND_FILL — the unit rows have a fixed natural
	# height and stretching this container to fill the window just opens a dead gap above the
	# log panel. The log is what should grow into leftover space; the roster shouldn't.
	vbox.add_child(teams_row)

	var team_a_col := VBoxContainer.new()
	team_a_col.add_theme_constant_override("separation", 6)
	team_a_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	teams_row.add_child(team_a_col)
	var a_header := Label.new()
	a_header.text = "YOUR TEAM"
	a_header.add_theme_color_override("font_color", Color(0.4, 0.65, 0.95))
	team_a_col.add_child(a_header)

	var team_b_col := VBoxContainer.new()
	team_b_col.add_theme_constant_override("separation", 6)
	team_b_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	teams_row.add_child(team_b_col)
	var b_header := Label.new()
	b_header.text = "RIVAL TEAM"
	b_header.add_theme_color_override("font_color", Color(0.9, 0.45, 0.4))
	team_b_col.add_child(b_header)

	var team_a := Roster.monsters.slice(0, mini(TEAM_SIZE, Roster.monsters.size()))
	var avg_t := 0.25
	var team_b := Roster.make_rival_team(team_a.size(), avg_t)

	for m in team_a:
		_add_unit_row(team_a_col, m, Color(0.4, 0.65, 0.95))
	for m in team_b:
		_add_unit_row(team_b_col, m, Color(0.9, 0.45, 0.4))

	sim = BattleSimScript.new(team_a, team_b, 20260804)

	var log_panel := PanelContainer.new()
	log_panel.custom_minimum_size = Vector2(0, 220)
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(log_panel)
	log_scroll = ScrollContainer.new()
	log_panel.add_child(log_scroll)
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.fit_content = true
	log_view.custom_minimum_size = Vector2(0, 220)
	log_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(log_view)

	result_label = Label.new()
	result_label.add_theme_font_size_override("font_size", 20)
	result_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	vbox.add_child(result_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	vbox.add_child(actions)

	start_btn = Button.new()
	start_btn.text = "Fight"
	start_btn.pressed.connect(_on_start)
	actions.add_child(start_btn)

	skip_btn = Button.new()
	skip_btn.text = "Skip to result"
	skip_btn.disabled = true
	skip_btn.pressed.connect(_on_skip)
	actions.add_child(skip_btn)

	var back := Button.new()
	back.text = "Back to the Stable"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/stable.tscn"))
	actions.add_child(back)


func _add_unit_row(parent: VBoxContainer, m, accent: Color) -> void:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.13, 0.17)
	sb.border_color = accent
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 4; sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)

	var name_label := Label.new()
	name_label.text = "%s (%s)" % [m.species_name, m.class_name_]
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.93))
	col.add_child(name_label)

	var hp_bar := ProgressBar.new()
	hp_bar.max_value = m.max_hp
	hp_bar.value = m.max_hp
	hp_bar.show_percentage = false
	hp_bar.custom_minimum_size = Vector2(0, 10)
	_style_bar(hp_bar, Color(0.3, 0.75, 0.35))
	col.add_child(hp_bar)

	var mp_bar := ProgressBar.new()
	mp_bar.max_value = maxi(1, m.max_mp)
	mp_bar.value = m.max_mp
	mp_bar.show_percentage = false
	mp_bar.custom_minimum_size = Vector2(0, 6)
	_style_bar(mp_bar, Color(0.35, 0.5, 0.85))
	col.add_child(mp_bar)

	var status_label := Label.new()
	status_label.text = ""
	status_label.add_theme_font_size_override("font_size", 11)
	status_label.add_theme_color_override("font_color", Color(0.85, 0.6, 0.3))
	col.add_child(status_label)

	unit_rows[m] = {"hp_bar": hp_bar, "mp_bar": mp_bar, "name_label": name_label, "status_label": status_label, "accent": accent}


func _style_bar(bar: ProgressBar, color: Color) -> void:
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(2)
	var bg2 := StyleBoxFlat.new()
	bg2.bg_color = Color(0.05, 0.05, 0.06)
	bg2.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fg)
	bar.add_theme_stylebox_override("background", bg2)


func _on_start() -> void:
	start_btn.disabled = true
	log_view.clear()
	battle_result = sim.run()
	playback_index = 0
	playback_accum = 0.0
	playing = true
	skip_btn.disabled = false
	result_label.text = "Fighting..."


func _on_skip() -> void:
	while playback_index < battle_result["log"].size():
		_apply_event(battle_result["log"][playback_index])
		playback_index += 1
	playing = false
	skip_btn.disabled = true
	_show_final()


func _process(delta: float) -> void:
	if not playing:
		return
	var events: Array = battle_result.get("log", [])
	if events.is_empty():
		playing = false
		return
	var per_event: float = PLAYBACK_SECONDS / maxf(1.0, float(events.size()))
	playback_accum += delta
	while playback_accum >= per_event and playback_index < events.size():
		_apply_event(events[playback_index])
		playback_index += 1
		playback_accum -= per_event
	if playback_index >= events.size():
		playing = false
		skip_btn.disabled = true
		_show_final()


func _apply_event(e: Dictionary) -> void:
	match e["kind"]:
		"start":
			log_view.append_text("[color=#d9b957]The fight begins.[/color]\n")
		"hit":
			var color := "#e0e0e6" if e["crit"] == false else "#ffcf5c"
			var tag := " (CRIT)" if e["crit"] else ""
			log_view.append_text("[color=%s]%s uses %s on %s for %d%s[/color]\n" % [color, e["attacker"], e["move"], e["target"], e["dmg"], tag])
			_sync_bars_for_name(e["target"])
			_sync_bars_for_name(e["attacker"])
		"miss":
			log_view.append_text("[color=#888]%s's %s missed %s[/color]\n" % [e["attacker"], e["move"], e["target"]])
		"status_apply":
			log_view.append_text("[color=#c98a3a]%s is now %s (from %s)[/color]\n" % [e["unit"], e["status"], e["from"]])
			_sync_status_for_name(e["unit"])
		"status_expire":
			log_view.append_text("[color=#777]%s's %s wears off[/color]\n" % [e["unit"], e["status"]])
			_sync_status_for_name(e["unit"])
		"buff":
			log_view.append_text("[color=#7fd0a0]%s's %s affects %s[/color]\n" % [e["caster"], e["move"], e["unit"]])
		"death":
			log_view.append_text("[color=#ff5c5c]%s falls![/color]\n" % e["unit"])
			_sync_bars_for_name(e["unit"])
		"end":
			var who := "Your team" if e["winner"] == "A" else ("The rival team" if e["winner"] == "B" else "Nobody")
			log_view.append_text("[color=#d9b957]%s wins, at %.1fs.[/color]\n" % [who, e["duration"]])
	# `RichTextLabel.scroll_to_line` is unreliable inside a ScrollContainer whose own scroll
	# extents haven't recalculated for this frame's new content yet — snap the CONTAINER's
	# scrollbar to its max instead, deferred one frame so the layout pass has already run.
	call_deferred("_snap_log_to_bottom")


func _snap_log_to_bottom() -> void:
	var bar := log_scroll.get_v_scroll_bar()
	if bar != null:
		log_scroll.scroll_vertical = int(bar.max_value)


func _sync_bars_for_name(species_name: String) -> void:
	for m in unit_rows:
		if m.species_name == species_name:
			var row: Dictionary = unit_rows[m]
			row["hp_bar"].value = m.hp
			row["mp_bar"].value = m.mp
			var frac: float = m.hp_frac()
			var c := Color(0.3, 0.75, 0.35)
			if frac < 0.25:
				c = Color(0.85, 0.25, 0.25)
			elif frac < 0.5:
				c = Color(0.85, 0.7, 0.25)
			_style_bar(row["hp_bar"], c)
			if not m.alive:
				row["name_label"].add_theme_color_override("font_color", Color(0.4, 0.4, 0.42))


func _sync_status_for_name(species_name: String) -> void:
	for m in unit_rows:
		if m.species_name == species_name:
			var row: Dictionary = unit_rows[m]
			var kinds: Array = []
			for s in m.statuses:
				kinds.append(s["kind"])
			row["status_label"].text = ", ".join(kinds)


func _show_final() -> void:
	var winner: String = battle_result.get("winner", "draw")
	var who := "You win." if winner == "A" else ("The rival wins." if winner == "B" else "Draw.")
	result_label.text = "%s  (%d vs %d standing, %.1fs)" % [who, battle_result["survivorsA"], battle_result["survivorsB"], battle_result["duration"]]
