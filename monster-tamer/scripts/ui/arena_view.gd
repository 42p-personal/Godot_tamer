## THE ARENA — the showpiece screen. The player set tactics beforehand; this screen's entire
## job is to replay what happened in a way a non-intervening spectator can actually READ.
##
## ⚠️ LEGIBILITY IS THE ACCEPTANCE CRITERION (CLAUDE.md): "An unreadable fight is not a hard
## fight, it is a slot machine." At a glance a viewer must be able to tell who is on which team,
## who is hurt, who just acted, what they did, and who is winning. Every choice below is in
## service of one of those five questions.
##
## ⚠️ PURE SIM / PRESENTATION SPLIT. `BattleSim.run()` executes the WHOLE fight synchronously and
## returns a complete event log (see battle_sim.gd's header) before this screen shows a single
## frame of it. That means the underlying `MonsterInstance` fields (`hp`, `mp`, `statuses`,
## `mods`) are already at their END-OF-FIGHT values by the time replay starts — reading them
## live during playback (as the older battle_ui.gd mockup does for its bars) would show the
## FINAL state from the first event onward instead of a gradual fight. This screen instead keeps
## its own SHADOW presentation state (`shadow_hp`/`shadow_mp`/`shadow_statuses`) built up purely
## from the events replayed so far — HP syncs off `targetHpFrac`, which the log captures at the
## exact moment of that historical hit, MP is derived from the same `Derive.field_mp_cost` the
## sim itself pays. See the note on `shadow_hp` below for the one gap this doesn't close.
extends Control

const BattleSimScript = preload("res://scripts/battle_sim.gd")

const DATA_PATH := "res://data/data.json"

# ── layout ────────────────────────────────────────────────────────────────────────────────────
const GROUND_BAND_FRAC := 0.46     # bottom fraction of the arena viewport that is "floor"
                                    # ⚠️ Raised from 0.36 after looking at it: the backdrops put
                                    # their horizon near the vertical middle (the wrapper asks for
                                    # exactly that), so a 0.36 floor band left the creatures
                                    # crammed into a strip while half the frame was empty sky.
const TOKEN_WIDTH := 116.0         # per-unit LAYOUT slot width (spacing), not the creature's own width
const TOKEN_HEIGHT := 168.0        # the on-screen creature height every texture is scaled to —
                                    # ⚠️ art director flagged creature art as NOT uniformly scaled to
                                    # each other (a gorilla and an owl come back similar canvas
                                    # sizes despite very different in-fiction sizes). Per their
                                    # steer: don't fight it, pick one on-screen height and scale
                                    # every texture to it so the line-up reads evenly.
const NAMEPLATE_HEIGHT := 50.0
const CENTRE_GAP := 90.0           # no-man's-land between the two teams' nearest units

# ── playback pacing ──────────────────────────────────────────────────────────────────────────
const PLAYBACK_SECONDS := 24.0     # wall-clock to replay the whole log at 1x, regardless of log length
const SPEED_OPTIONS := [0.5, 1.0, 2.0, 4.0]
const SPEED_LABELS := ["0.5x", "1x", "2x", "4x"]

# ── the channel-colour "what's happening" language (docs/ART_THEME.md "What's happening") ─────
const CHANNEL_COLOR := {
	"melee": Color(0.92, 0.92, 0.90),
	"ranged": Color(0.88, 0.62, 0.24),
	"magic": Color(0.62, 0.40, 0.88),
	"voice": Color(0.88, 0.42, 0.65),
	"support": Color(0.30, 0.75, 0.68),
}

# ── the status-vocabulary colour language (docs/ART_THEME.md "Who's winning") ─────────────────
# Grouped by category with a distinct hue family per group; every chip also carries an
# abbreviation as text, so the read never depends on colour alone (this doubles as the
# colourblind-safe "second tell" the team-identity badge system now requires elsewhere).
# ⚠️ Kept clearly BRIGHTER/more saturated than any `Art.TEAM_COLOURS` livery tone on purpose —
# the art director's rule is "saturated = something is happening to this creature; muted = this
# is who it plays for," and status must stay on the saturated side of that line.
const STATUS_META := {
	"stun": {"abbr": "STN", "color": Color(0.95, 0.92, 0.62)},
	"sleep": {"abbr": "SLP", "color": Color(0.95, 0.92, 0.62)},
	"fear": {"abbr": "FEAR", "color": Color(0.95, 0.92, 0.62)},
	"confusion": {"abbr": "CONF", "color": Color(0.95, 0.92, 0.62)},
	"charm": {"abbr": "CHRM", "color": Color(0.95, 0.92, 0.62)},
	"silence": {"abbr": "SIL", "color": Color(0.95, 0.92, 0.62)},
	"knockback": {"abbr": "KB", "color": Color(0.95, 0.92, 0.62)},
	"poison": {"abbr": "PSN", "color": Color(0.42, 0.80, 0.36)},
	"burn": {"abbr": "BRN", "color": Color(0.92, 0.52, 0.18)},
	"bleed": {"abbr": "BLD", "color": Color(0.85, 0.24, 0.24)},
	"doom": {"abbr": "DOOM", "color": Color(0.55, 0.24, 0.62)},
	"blind": {"abbr": "BLND", "color": Color(0.62, 0.55, 0.70)},
	"vulnerable": {"abbr": "VULN", "color": Color(0.62, 0.55, 0.70)},
	"healblock": {"abbr": "HBLK", "color": Color(0.62, 0.55, 0.70)},
	"haste": {"abbr": "HASTE", "color": Color(0.35, 0.78, 0.90)},
}

# Fallback venue tint per league, used only when Art returns no real backdrop/ground — a cheap,
# deliberate echo of "chrome follows the league material" (ART_THEME.md §4) so even an unpainted
# arena still differentiates leagues rather than looking like one grey box.
const LEAGUE_TINTS := {
	"Wood": Color(0.42, 0.30, 0.18), "Copper": Color(0.55, 0.32, 0.18),
	"Tin": Color(0.45, 0.48, 0.52), "Bronze": Color(0.50, 0.35, 0.20),
	"Iron": Color(0.32, 0.33, 0.36), "Silver": Color(0.55, 0.57, 0.62),
	"Gold": Color(0.62, 0.50, 0.22), "Platinum": Color(0.58, 0.60, 0.62),
	"Masters": Color(0.22, 0.28, 0.45), "Tamer Elite": Color(0.42, 0.18, 0.20),
	"Tamers Apex": Color(0.28, 0.18, 0.38),
}

# ── ENTRY POINT #1 — static handoff, for callers using get_tree().change_scene_to_file() ──────
# Usage from another screen:
#   var ArenaViewScript = preload("res://scripts/ui/arena_view.gd")
#   ArenaViewScript.pending_fight = {
#       "team_a": my_team, "team_b": rival_team,
#       "league_name": "Gold", "all_leagues": the_ladder_names,   # both optional
#   }
#   get_tree().change_scene_to_file("res://scenes/arena.tscn")
# Consumed (and cleared) once in _ready(). "team_a"/"team_b" are Array[MonsterInstance].
static var pending_fight: Dictionary = {}

# ── ENTRY POINT #2 — instance handoff, for callers using PackedScene.instantiate() ────────────
# Usage: instantiate the scene, set these BEFORE add_child()-ing it (so they're set before
# _ready() runs), then add it to the tree yourself. Equivalent fields to pending_fight above.
var config_team_a: Array = []
var config_team_b: Array = []
var config_league_name: String = ""
var config_all_leagues: Array = []
var config_seed: int = 20260804

# ── result handoff back to the caller ──────────────────────────────────────────────────────────
signal fight_finished(result: Dictionary)
var last_result: Dictionary = {}

# ── resolved fight state ───────────────────────────────────────────────────────────────────────
var team_a: Array = []
var team_b: Array = []
var league_name: String = ""
var all_leagues: Array = []

var sim = null
var battle_result: Dictionary = {}
var playback_index := 0
var playback_accum := 0.0
var playing := false
var speed_mult := 1.0
var focus_unit = null  # the "under fire" unit — most recently hit, per docs/ART_THEME.md's
                        # single highest-value readability addition

# Presentation-side shadow state — see the file header. NEVER read m.hp/m.mp/m.statuses/m.mods
# directly during playback; the live MonsterInstance is already at its post-fight values.
var shadow_hp: Dictionary = {}       # MonsterInstance -> float
var shadow_mp: Dictionary = {}       # MonsterInstance -> float
var shadow_statuses: Dictionary = {} # MonsterInstance -> Array[String] of active status kinds
# ⚠️ KNOWN GAP: recoil/lifesteal change the ATTACKER's own hp on a hit they land, and enemy-facing
# debuffs (defDebuff/atkDebuff/accDebuff/manaBurn, e.g. Sunder) are applied to `target.mods`
# entirely silently — battle_sim.gd's `_resolve_hit` logs neither. Nothing here can reconstruct
# either without a field the log doesn't carry; fixing it means adding fields/events to
# battle_sim.gd, which is out of this file's ownership. Flagged for the coordinator.

var unit_nodes: Dictionary = {}   # MonsterInstance -> Dictionary of node refs + layout info
var name_index: Dictionary = {}   # "A|Kongrath" -> Array[MonsterInstance], for resolving log events

var arena_viewport: Control
var backdrop_rect: TextureRect
var ground_rect: TextureRect
var unit_layer: Control
var float_layer: Control
var result_banner: PanelContainer
var banner_button: Button
var banner_title: Label
var banner_sub: Label
var log_view: RichTextLabel
var log_scroll: ScrollContainer
var play_btn: Button
var skip_btn: Button
var speed_buttons: Array = []


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	_resolve_fight_source()
	sim = BattleSimScript.new(team_a, team_b, config_seed)
	_build_ui()
	battle_result = sim.run()
	playback_index = 0
	playback_accum = 0.0
	playing = true
	call_deferred("_layout_units")


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# FIGHT SOURCE RESOLUTION
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _resolve_fight_source() -> void:
	if not pending_fight.is_empty():
		team_a = pending_fight.get("team_a", [])
		team_b = pending_fight.get("team_b", [])
		league_name = String(pending_fight.get("league_name", ""))
		all_leagues = pending_fight.get("all_leagues", [])
		config_seed = int(pending_fight.get("seed", config_seed))
		pending_fight = {}  # consume once — a stale handoff must never leak into the next scene load
	elif not config_team_a.is_empty() and not config_team_b.is_empty():
		team_a = config_team_a
		team_b = config_team_b
		league_name = config_league_name
		all_leagues = config_all_leagues
	else:
		_build_debug_fight()

	if league_name == "":
		league_name = "Platinum"
	if all_leagues.is_empty():
		var d := _load_data()
		for entry in (d.get("leagues", []) as Array):
			all_leagues.append(String(entry.get("name", "")))
		if all_leagues.is_empty():
			all_leagues = [league_name]


## Self-contained default so this scene can run standalone with no caller — reads the real
## league ladder + team-size-by-league straight out of data.json (never hardcoded), and fields
## the player's own stable against a freshly generated rival team, same as the older battle_ui.gd
## mockup did.
func _build_debug_fight() -> void:
	var d := _load_data()
	var leagues_arr: Array = d.get("leagues", [])
	var sizes: Dictionary = d.get("teamSizeByLeague", {})
	var chosen_league := "Platinum"
	if not sizes.has(chosen_league) and not leagues_arr.is_empty():
		chosen_league = String(leagues_arr[leagues_arr.size() - 1].get("name", "Platinum"))
	var team_size: int = clampi(int(sizes.get(chosen_league, 5)), 1, 5)

	var pool: Array = Roster.monsters
	team_a = pool.slice(0, mini(team_size, pool.size()))
	team_b = Roster.make_rival_team(team_a.size(), 0.45)
	league_name = chosen_league
	all_leagues.clear()
	for entry in leagues_arr:
		all_leagues.append(String(entry.get("name", "")))
	if all_leagues.is_empty():
		all_leagues = [league_name]


func _load_data() -> Dictionary:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# UI CONSTRUCTION
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.06)
	bg.anchor_right = 1; bg.anchor_bottom = 1
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.anchor_right = 1; margin.anchor_bottom = 1
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(root_vbox)

	_build_header(root_vbox)
	_build_arena_viewport(root_vbox)
	_build_bottom_panel(root_vbox)

	_apply_arena_art()

	for i in range(team_a.size()):
		_build_unit_node(team_a[i], "A", 0, i, team_a.size())
	for i in range(team_b.size()):
		_build_unit_node(team_b[i], "B", 1, i, team_b.size())


func _build_header(root_vbox: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	root_vbox.add_child(header)
	var title := Label.new()
	title.text = "%s League" % league_name
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/stable.tscn"))
	header.add_child(back)

	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 16)
	root_vbox.add_child(legend)
	legend.add_child(_make_team_legend_chip(0, "Your Team"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.add_child(spacer)
	legend.add_child(_make_team_legend_chip(1, "Rival Team"))


func _make_team_legend_chip(team_index: int, label_text: String) -> PanelContainer:
	var ident: Dictionary = Art.team_identity(team_index)
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.12)
	sb.border_color = ident["colour"]
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 3; sb.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	chip.add_child(row)
	var badge := Label.new()
	badge.text = ident["badge"]
	badge.add_theme_color_override("font_color", ident["colour"])
	badge.add_theme_font_size_override("font_size", 14)
	row.add_child(badge)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(lbl)
	return chip


func _build_arena_viewport(root_vbox: VBoxContainer) -> void:
	arena_viewport = Control.new()
	arena_viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	arena_viewport.clip_contents = true
	arena_viewport.custom_minimum_size = Vector2(0, 340)
	root_vbox.add_child(arena_viewport)
	arena_viewport.resized.connect(_layout_units)

	backdrop_rect = TextureRect.new()
	backdrop_rect.anchor_right = 1; backdrop_rect.anchor_bottom = 1
	backdrop_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena_viewport.add_child(backdrop_rect)

	ground_rect = TextureRect.new()
	ground_rect.anchor_left = 0; ground_rect.anchor_right = 1
	ground_rect.anchor_top = 1.0 - GROUND_BAND_FRAC; ground_rect.anchor_bottom = 1.0
	ground_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena_viewport.add_child(ground_rect)

	var seam := ColorRect.new()
	seam.color = Color(0, 0, 0, 0.35)
	seam.anchor_left = 0; seam.anchor_right = 1
	seam.anchor_top = 1.0 - GROUND_BAND_FRAC; seam.anchor_bottom = 1.0 - GROUND_BAND_FRAC
	seam.offset_top = -2; seam.offset_bottom = 2
	seam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena_viewport.add_child(seam)

	unit_layer = Control.new()
	unit_layer.anchor_right = 1; unit_layer.anchor_bottom = 1
	unit_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena_viewport.add_child(unit_layer)

	float_layer = Control.new()
	float_layer.anchor_right = 1; float_layer.anchor_bottom = 1
	float_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arena_viewport.add_child(float_layer)

	result_banner = _build_result_banner()
	arena_viewport.add_child(result_banner)


func _build_result_banner() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.anchor_left = 0.26; panel.anchor_right = 0.74
	panel.anchor_top = 0.34; panel.anchor_bottom = 0.6
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.07, 0.93)
	sb.border_color = Color(0.85, 0.72, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	panel.visible = false
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vb)
	banner_title = Label.new()
	banner_title.add_theme_font_size_override("font_size", 30)
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(banner_title)
	banner_sub = Label.new()
	banner_sub.add_theme_font_size_override("font_size", 14)
	banner_sub.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(banner_sub)

	banner_button = Button.new()
	banner_button.text = "See the report  →"
	banner_button.custom_minimum_size = Vector2(0, 40)
	banner_button.visible = false
	banner_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/report.tscn"))
	vb.add_child(banner_button)
	return panel


func _build_bottom_panel(root_vbox: VBoxContainer) -> void:
	var bottom := HBoxContainer.new()
	bottom.custom_minimum_size = Vector2(0, 190)
	bottom.add_theme_constant_override("separation", 12)
	root_vbox.add_child(bottom)

	var log_panel := PanelContainer.new()
	log_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(log_panel)
	log_scroll = ScrollContainer.new()
	log_panel.add_child(log_scroll)
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.fit_content = true
	log_view.scroll_active = false
	log_view.custom_minimum_size = Vector2(0, 180)
	log_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(log_view)

	var controls := VBoxContainer.new()
	controls.custom_minimum_size = Vector2(230, 0)
	controls.add_theme_constant_override("separation", 6)
	bottom.add_child(controls)

	play_btn = Button.new()
	play_btn.text = "Pause"
	play_btn.pressed.connect(_toggle_play)
	controls.add_child(play_btn)

	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 4)
	controls.add_child(speed_row)
	for i in range(SPEED_OPTIONS.size()):
		var s: float = SPEED_OPTIONS[i]
		var b := Button.new()
		b.text = SPEED_LABELS[i]
		b.toggle_mode = true
		b.button_pressed = (s == speed_mult)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		speed_row.add_child(b)
		speed_buttons.append(b)
	for i in range(speed_buttons.size()):
		speed_buttons[i].pressed.connect(_set_speed.bind(SPEED_OPTIONS[i], speed_buttons[i]))

	skip_btn = Button.new()
	skip_btn.text = "Skip to Result"
	skip_btn.pressed.connect(_on_skip)
	controls.add_child(skip_btn)


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# ARENA ART — backdrop/ground, degrading to a deliberate flat fallback when Art returns null
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _apply_arena_art() -> void:
	var bd: Texture2D = Art.backdrop_for(league_name, all_leagues)
	if bd != null:
		backdrop_rect.texture = bd
		backdrop_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	else:
		backdrop_rect.texture = _fallback_gradient(_league_tint(league_name))
		backdrop_rect.stretch_mode = TextureRect.STRETCH_SCALE

	var gr: Texture2D = Art.ground_for(league_name, all_leagues)
	if gr != null:
		ground_rect.texture = gr
		ground_rect.stretch_mode = TextureRect.STRETCH_TILE
	else:
		ground_rect.texture = _fallback_solid(_league_tint(league_name).darkened(0.5))
		ground_rect.stretch_mode = TextureRect.STRETCH_SCALE


func _league_tint(league: String) -> Color:
	return LEAGUE_TINTS.get(league, Color(0.30, 0.32, 0.36))


func _fallback_gradient(base: Color) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([base.lightened(0.30), base.darkened(0.30)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 4
	tex.height = 256
	return tex


func _fallback_solid(base: Color) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([base, base.darkened(0.12)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(1, 0)
	tex.width = 256
	tex.height = 4
	return tex


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# UNIT NODES — one per combatant: nameplate (name/class/team badge+colour/HP/MP/status chips)
# over a foot-anchored creature token (real art if Art has it, a deliberate token if not).
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _build_unit_node(m, side: String, team_index: int, slot_index: int, team_count: int) -> void:
	var ident: Dictionary = Art.team_identity(team_index)

	var holder := Control.new()
	holder.custom_minimum_size = Vector2(TOKEN_WIDTH, TOKEN_HEIGHT + NAMEPLATE_HEIGHT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_layer.add_child(holder)

	# "under fire" glow — sits behind everything else, saturated alarm colour, hidden until focused
	var glow := ColorRect.new()
	glow.color = Color(1.0, 0.35, 0.18, 0.0)
	glow.size = Vector2(TOKEN_WIDTH + 24, TOKEN_HEIGHT + 24)
	glow.position = Vector2(-12, NAMEPLATE_HEIGHT - 12)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(glow)

	var sprite_area := Control.new()
	sprite_area.position = Vector2(0, NAMEPLATE_HEIGHT)
	sprite_area.size = Vector2(TOKEN_WIDTH, TOKEN_HEIGHT)
	sprite_area.pivot_offset = Vector2(TOKEN_WIDTH * 0.5, TOKEN_HEIGHT)  # feet — for the death-topple tween
	holder.add_child(sprite_area)

	var fallback := Panel.new()
	fallback.anchor_right = 1; fallback.anchor_bottom = 1
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.20, 0.21, 0.26)
	fsb.set_corner_radius_all(10)
	fsb.border_color = ident["colour"]
	fsb.set_border_width_all(2)
	fallback.add_theme_stylebox_override("panel", fsb)
	sprite_area.add_child(fallback)

	var fb_label := Label.new()
	fb_label.anchor_right = 1; fb_label.anchor_bottom = 1
	fb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fb_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fb_label.text = m.species_name.substr(0, 2).to_upper()
	fb_label.add_theme_font_size_override("font_size", 26)
	fb_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	sprite_area.add_child(fb_label)

	var facing := Label.new()
	facing.text = "▶" if side == "A" else "◀"
	facing.add_theme_font_size_override("font_size", 13)
	facing.add_theme_color_override("font_color", ident["colour"])
	facing.position = Vector2(TOKEN_WIDTH * 0.5 - 7, NAMEPLATE_HEIGHT + TOKEN_HEIGHT - 2)
	sprite_area.add_child(facing)

	var tex_rect := TextureRect.new()
	tex_rect.visible = false
	sprite_area.add_child(tex_rect)

	var tex: Texture2D = Art.creature_texture(m.species_id)
	if tex != null:
		# Scale every creature to the SAME on-screen height regardless of its native canvas size
		# (art director: creature art isn't uniformly scaled to each other yet — pick one height
		# and scale to it rather than fight it). Width follows the texture's own aspect, so a
		# wide creature is simply wider on screen, not squashed.
		var th := float(tex.get_height())
		var token_scale: float = TOKEN_HEIGHT / maxf(1.0, th)
		var w: float = float(tex.get_width()) * token_scale
		tex_rect.stretch_mode = TextureRect.STRETCH_SCALE
		# ⚠️ EXPAND_IGNORE_SIZE IS LOAD-BEARING, NOT TIDYING.
		# TextureRect's default `expand_mode` is EXPAND_KEEP_SIZE, which makes the node's MINIMUM
		# size the texture's own size. The creature art is ~512px tall, so assigning `size.y = 128`
		# below was silently clamped straight back up to 512 and every creature rendered ~4x too
		# large — cropped, overlapping its neighbours and burying the arena backdrop. Setting the
		# size without this line does nothing at all.
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.size = Vector2(w, TOKEN_HEIGHT)
		# Sit BELOW the nameplate rather than under it — the plate occupies y 0..NAMEPLATE_HEIGHT
		# in this same local space, so a creature drawn at y=0 renders behind its own label.
		tex_rect.position = Vector2(TOKEN_WIDTH * 0.5 - w * 0.5, NAMEPLATE_HEIGHT)
		tex_rect.flip_h = (side == "B")
		tex_rect.texture = tex
		tex_rect.visible = true
		fallback.visible = false
		fb_label.visible = false

	# nameplate
	var plate := PanelContainer.new()
	plate.position = Vector2(0, 0)
	plate.size = Vector2(TOKEN_WIDTH, NAMEPLATE_HEIGHT)
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.08, 0.08, 0.10, 0.90)
	psb.border_color = ident["colour"]
	psb.set_border_width_all(2)
	psb.set_corner_radius_all(4)
	psb.content_margin_left = 4; psb.content_margin_right = 4
	psb.content_margin_top = 2; psb.content_margin_bottom = 2
	plate.add_theme_stylebox_override("panel", psb)
	holder.add_child(plate)

	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 1)
	plate.add_child(pv)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 3)
	pv.add_child(name_row)
	var badge_label := Label.new()
	badge_label.text = ident["badge"]
	badge_label.add_theme_font_size_override("font_size", 10)
	badge_label.add_theme_color_override("font_color", ident["colour"])
	name_row.add_child(badge_label)
	var name_label := Label.new()
	name_label.text = m.species_name
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)

	var class_label := Label.new()
	class_label.text = m.class_name_
	class_label.add_theme_font_size_override("font_size", 9)
	class_label.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68))
	pv.add_child(class_label)

	var hp_bar := ProgressBar.new()
	hp_bar.max_value = m.max_hp
	hp_bar.value = m.hp
	hp_bar.show_percentage = false
	hp_bar.custom_minimum_size = Vector2(0, 7)
	pv.add_child(hp_bar)

	var mp_bar := ProgressBar.new()
	mp_bar.max_value = maxi(1, m.max_mp)
	mp_bar.value = m.mp
	mp_bar.show_percentage = false
	mp_bar.custom_minimum_size = Vector2(0, 4)
	_style_bar(mp_bar, Color(0.35, 0.5, 0.85))
	pv.add_child(mp_bar)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 2)
	pv.add_child(status_row)

	var dead_mark := Label.new()
	dead_mark.text = "✗"  # U+2717 is in the packaged Inter face; U+2716 ✖ is not
	dead_mark.add_theme_font_size_override("font_size", 34)
	dead_mark.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2, 0.9))
	dead_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dead_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dead_mark.visible = false
	dead_mark.position = Vector2(0, NAMEPLATE_HEIGHT)
	dead_mark.size = Vector2(TOKEN_WIDTH, TOKEN_HEIGHT)
	holder.add_child(dead_mark)

	_style_hp_bar(hp_bar, m.hp_frac())

	unit_nodes[m] = {
		"holder": holder, "glow": glow, "sprite_area": sprite_area,
		"hp_bar": hp_bar, "mp_bar": mp_bar, "name_label": name_label, "status_row": status_row,
		"dead_mark": dead_mark, "side": side, "team_index": team_index,
		"slot": slot_index, "team_count": team_count, "glow_tween": null, "base_pos": Vector2.ZERO,
	}
	shadow_hp[m] = float(m.max_hp)
	shadow_mp[m] = float(m.max_mp)
	shadow_statuses[m] = []

	var key: String = side + "|" + m.species_name
	if not name_index.has(key):
		name_index[key] = []
	name_index[key].append(m)


func _layout_units() -> void:
	var vp_size: Vector2 = arena_viewport.size
	if vp_size.x <= 0 or vp_size.y <= 0:
		return
	var ground_top: float = vp_size.y * (1.0 - GROUND_BAND_FRAC)
	var ground_y: float = ground_top + (vp_size.y - ground_top) * 0.62
	var half_w: float = vp_size.x * 0.5
	var margin: float = 60.0
	var lane_w: float = maxf(40.0, half_w - margin - CENTRE_GAP * 0.5)

	for m in unit_nodes:
		var info: Dictionary = unit_nodes[m]
		var side: String = info["side"]
		var slot: int = info["slot"]
		var count: int = info["team_count"]
		var step: float = lane_w / maxf(1.0, float(count))
		var x: float
		if side == "A":
			x = margin + step * (slot + 0.5)
		else:
			x = vp_size.x - margin - step * (slot + 0.5)
		var holder: Control = info["holder"]
		# Foot-anchor: the creature's feet land on `ground_y`. The holder's local space is
		# [nameplate | creature], so the holder top sits a full nameplate + creature height above
		# the groundline.
		var pos := Vector2(x - TOKEN_WIDTH * 0.5, ground_y - TOKEN_HEIGHT - NAMEPLATE_HEIGHT)
		holder.position = pos
		info["base_pos"] = pos


func _style_bar(bar: ProgressBar, color: Color) -> void:
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(2)
	var bgb := StyleBoxFlat.new()
	bgb.bg_color = Color(0.05, 0.05, 0.06)
	bgb.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fg)
	bar.add_theme_stylebox_override("background", bgb)


## Universal threat gradient, independent of team colour (docs/ART_THEME.md "Who's winning") —
## danger must read the same for every team, every league, every time.
func _style_hp_bar(bar: ProgressBar, frac: float) -> void:
	var c := Color(0.30, 0.75, 0.35)
	if frac < 0.25:
		c = Color(0.85, 0.22, 0.22)
	elif frac < 0.5:
		c = Color(0.88, 0.68, 0.22)
	_style_bar(bar, c)


func _make_chip(text: String, color: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 3; sb.content_margin_right = 3
	sb.content_margin_top = 0; sb.content_margin_bottom = 0
	chip.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", Color(0.05, 0.05, 0.06))
	chip.add_child(lbl)
	return chip


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# PLAYBACK
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if not playing:
		return
	var events: Array = battle_result.get("log", [])
	if events.is_empty():
		playing = false
		return
	var per_event: float = (PLAYBACK_SECONDS / maxf(0.1, speed_mult)) / maxf(1.0, float(events.size()))
	playback_accum += delta
	while playback_accum >= per_event and playback_index < events.size():
		_apply_event(events[playback_index], true)
		playback_index += 1
		playback_accum -= per_event
	if playback_index >= events.size():
		playing = false


func _toggle_play() -> void:
	if playback_index >= battle_result.get("log", []).size():
		return
	playing = not playing
	play_btn.text = "Pause" if playing else "Play"


func _set_speed(s: float, btn: Button) -> void:
	speed_mult = s
	for b in speed_buttons:
		b.button_pressed = false
	btn.button_pressed = true


func _on_skip() -> void:
	var events: Array = battle_result.get("log", [])
	while playback_index < events.size():
		_apply_event(events[playback_index], false)
		playback_index += 1
	playing = false
	play_btn.disabled = true
	skip_btn.disabled = true


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# EVENT APPLICATION — text log + shadow-state sync + (when animate) the visible "moment"
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _apply_event(e: Dictionary, animate: bool) -> void:
	match e["kind"]:
		"start":
			log_view.append_text("[color=#d9b957]The fight begins.[/color]\n")
		"hit":
			_apply_hit(e, animate)
		"miss":
			_apply_miss(e, animate)
		"status_apply":
			_apply_status_apply(e, animate)
		"status_expire":
			_apply_status_expire(e)
		"buff":
			_apply_buff(e, animate)
		"death":
			_apply_death(e, animate)
		"end":
			_apply_end(e)
	call_deferred("_snap_log_to_bottom")


func _apply_hit(e: Dictionary, animate: bool) -> void:
	var attacker_m = _find_by_name(e["attackerSide"], e["attacker"])
	var target_m = _find_by_name(e["targetSide"], e["target"])
	var crit: bool = e["crit"]
	var color := "#ffcf5c" if crit else "#e0e0e6"
	var tag := " (CRIT)" if crit else ""
	log_view.append_text("[color=%s]%s uses %s on %s for %d%s[/color]\n" % [color, e["attacker"], e["move"], e["target"], e["dmg"], tag])

	if target_m != null:
		shadow_hp[target_m] = float(e["targetHpFrac"]) * float(target_m.max_hp)
		_sync_bars(target_m)
		if animate:
			_flash_hit(target_m, crit)
			_spawn_floater(target_m, str(e["dmg"]) + ("!" if crit else ""), Color(1, 0.82, 0.35) if crit else Color(1, 0.92, 0.9), crit)
		_set_focus(target_m)

	if attacker_m != null:
		_deduct_mana_for_move(attacker_m, e["move"])
		_sync_bars(attacker_m)
		if animate:
			_lunge(attacker_m)
			_spawn_move_tag(attacker_m, e["move"])


func _apply_miss(e: Dictionary, animate: bool) -> void:
	log_view.append_text("[color=#888]%s's %s missed %s[/color]\n" % [e["attacker"], e["move"], e["target"]])
	var attacker_m = _find_by_name(e["attackerSide"], e["attacker"])
	var target_m = _find_by_name(e["targetSide"], e["target"])
	if attacker_m != null:
		_deduct_mana_for_move(attacker_m, e["move"])
		_sync_bars(attacker_m)
		if animate:
			_lunge(attacker_m)
			_spawn_move_tag(attacker_m, e["move"])
	if animate and target_m != null:
		_spawn_floater(target_m, "MISS", Color(0.6, 0.6, 0.62))


func _apply_status_apply(e: Dictionary, animate: bool) -> void:
	var label := _status_label(e["status"])
	log_view.append_text("[color=#c98a3a]%s is now %s (from %s)[/color]\n" % [e["unit"], label, e["from"]])
	var m = _find_by_name(e["side"], e["unit"])
	if m == null:
		return
	var arr: Array = shadow_statuses.get(m, [])
	arr.append(String(e["status"]))
	shadow_statuses[m] = arr
	_sync_status(m)
	if animate:
		var meta: Dictionary = STATUS_META.get(e["status"], {"color": Color(0.7, 0.7, 0.7)})
		_spawn_floater(m, "+" + label, meta.get("color", Color(0.7, 0.7, 0.7)))


func _apply_status_expire(e: Dictionary) -> void:
	log_view.append_text("[color=#777]%s's %s wears off[/color]\n" % [e["unit"], _status_label(e["status"])])
	var m = _find_by_name(e["side"], e["unit"])
	if m == null:
		return
	var arr: Array = shadow_statuses.get(m, [])
	var idx := arr.find(String(e["status"]))
	if idx >= 0:
		arr.remove_at(idx)
	shadow_statuses[m] = arr
	_sync_status(m)


func _apply_buff(e: Dictionary, animate: bool) -> void:
	log_view.append_text("[color=#7fd0a0]%s's %s affects %s[/color]\n" % [e["caster"], e["move"], e["unit"]])
	var m = _find_by_name(e["side"], e["unit"])
	if m == null or not animate:
		return
	_spawn_floater(m, "+" + String(e["move"]), Color(0.5, 0.85, 0.65))


func _apply_death(e: Dictionary, animate: bool) -> void:
	var killer_txt := " (%s)" % e["killer"] if e.has("killer") else ""
	log_view.append_text("[color=#ff5c5c]%s falls!%s[/color]\n" % [e["unit"], killer_txt])
	var m = _find_by_name(e["side"], e["unit"])
	if m == null:
		return
	shadow_hp[m] = 0.0
	_sync_bars(m)
	var info: Dictionary = unit_nodes[m]
	info["name_label"].add_theme_color_override("font_color", Color(0.45, 0.45, 0.48))
	info["dead_mark"].visible = true
	if focus_unit == m:
		_clear_glow(m)
		focus_unit = null
	var area: Control = info["sprite_area"]
	var topple_deg := 84.0 if info["side"] == "A" else -84.0
	if animate:
		var tw := create_tween()
		tw.tween_property(area, "modulate", Color(0.4, 0.4, 0.4, 0.55), 0.5)
		tw.parallel().tween_property(area, "rotation_degrees", topple_deg, 0.5).set_trans(Tween.TRANS_SINE)
	else:
		area.modulate = Color(0.4, 0.4, 0.4, 0.55)
		area.rotation_degrees = topple_deg


func _apply_end(e: Dictionary) -> void:
	var who := "Your team wins!" if e["winner"] == "A" else ("The rival wins." if e["winner"] == "B" else "Draw.")
	log_view.append_text("[color=#d9b957]%s (%.1fs)[/color]\n" % [who, e["duration"]])
	playing = false
	skip_btn.disabled = true
	play_btn.disabled = true
	last_result = battle_result
	fight_finished.emit(battle_result)
	banner_title.text = who
	banner_sub.text = "%d vs %d standing — %.1fs" % [battle_result.get("survivorsA", 0), battle_result.get("survivorsB", 0), battle_result.get("duration", 0.0)]
	result_banner.visible = true

	# Hand the finished fight to the report screen and offer the way through. ⚠️ The player could
	# not intervene, so the REPORT is where they find out whether their read was right — it is the
	# payoff for the whole no-intervention design, not an optional extra screen. The banner button
	# is therefore the primary action here; "Back" remains as an escape hatch.
	var ReportScript = load("res://scripts/ui/report_ui.gd")
	ReportScript.hand_off(battle_result, team_a, team_b)
	if banner_button != null:
		banner_button.visible = true


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# SHADOW-STATE HELPERS
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _find_by_name(side: String, species_name: String):
	var key := side + "|" + species_name
	var arr: Array = name_index.get(key, [])
	if arr.is_empty():
		return null
	if arr.size() == 1:
		return arr[0]
	for m in arr:
		if m.alive:
			return m
	return arr[0]


func _lookup_move(m, move_name: String) -> Dictionary:
	for mv in m.moveset:
		if mv["name"] == move_name:
			return mv
	return {}


## The sim pays `Derive.field_mp_cost(move)` per cast regardless of hit/miss (the free attack
## never reaches here — it's free). Reusing the same pure Derive function the sim itself calls,
## rather than hand-transcribing a price, keeps this in lock-step with the real cost.
func _deduct_mana_for_move(m, move_name: String) -> void:
	if move_name == "Attack":
		return
	var mv := _lookup_move(m, move_name)
	if mv.is_empty():
		return
	var cost: float = Derive.field_mp_cost(mv)
	var cur: float = shadow_mp.get(m, float(m.max_mp))
	shadow_mp[m] = maxf(0.0, cur - cost)


func _sync_bars(m) -> void:
	var info: Dictionary = unit_nodes.get(m)
	if info == null:
		return
	var hp_bar: ProgressBar = info["hp_bar"]
	var mp_bar: ProgressBar = info["mp_bar"]
	var hp: float = shadow_hp.get(m, float(m.max_hp))
	var mp: float = shadow_mp.get(m, float(m.max_mp))
	hp_bar.value = hp
	mp_bar.value = mp
	var frac: float = 0.0 if m.max_hp <= 0 else clampf(hp / float(m.max_hp), 0.0, 1.0)
	_style_hp_bar(hp_bar, frac)


func _sync_status(m) -> void:
	var info: Dictionary = unit_nodes.get(m)
	if info == null:
		return
	var row: HBoxContainer = info["status_row"]
	for c in row.get_children():
		c.queue_free()
	for kind in shadow_statuses.get(m, []):
		var meta: Dictionary = STATUS_META.get(kind, {"abbr": String(kind).substr(0, 4).to_upper(), "color": Color(0.6, 0.6, 0.6)})
		row.add_child(_make_chip(meta.get("abbr", "?"), meta.get("color", Color(0.6, 0.6, 0.6))))


func _status_label(kind: String) -> String:
	return String(kind).capitalize()


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# ANIMATION — the "moment" of every hit/miss/death, and the standing "under fire" tell
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _flash_hit(m, crit: bool) -> void:
	var info: Dictionary = unit_nodes.get(m)
	if info == null:
		return
	var area: Control = info["sprite_area"]
	var holder: Control = info["holder"]
	var base_pos: Vector2 = info["base_pos"]
	var flash_color := Color(1, 0.85, 0.4) if crit else Color(1, 1, 1)
	var flash_tw := create_tween()
	flash_tw.tween_property(area, "modulate", flash_color, 0.03)
	flash_tw.tween_property(area, "modulate", Color(1, 1, 1), 0.18)

	var mag := 6.0 if crit else 3.0
	var shake_tw := create_tween()
	for i in range(4):
		var dx := mag if i % 2 == 0 else -mag
		shake_tw.tween_property(holder, "position:x", base_pos.x + dx, 0.03)
	shake_tw.tween_property(holder, "position:x", base_pos.x, 0.03)


func _lunge(m) -> void:
	var info: Dictionary = unit_nodes.get(m)
	if info == null:
		return
	var holder: Control = info["holder"]
	var base_pos: Vector2 = info["base_pos"]
	var dir := 1.0 if info["side"] == "A" else -1.0
	var tw := create_tween()
	tw.tween_property(holder, "position:x", base_pos.x + dir * 22.0, 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(holder, "position:x", base_pos.x, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _spawn_floater(m, text: String, color: Color, big: bool = false) -> void:
	var info: Dictionary = unit_nodes.get(m)
	if info == null:
		return
	var holder: Control = info["holder"]
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22 if big else 16)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.position = holder.position + Vector2(TOKEN_WIDTH * 0.5 - 10, NAMEPLATE_HEIGHT - 6)
	float_layer.add_child(lbl)
	var tw := create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 34.0, 0.9)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.65).set_delay(0.25)
	tw.tween_callback(lbl.queue_free)


func _spawn_move_tag(m, move_name: String) -> void:
	var info: Dictionary = unit_nodes.get(m)
	if info == null:
		return
	var channel := "melee"
	if move_name == "Attack":
		channel = m.basic_attack.get("channel", "melee")
	else:
		var mv := _lookup_move(m, move_name)
		if not mv.is_empty():
			channel = mv.get("channel", "melee")
	var color: Color = CHANNEL_COLOR.get(channel, Color(0.8, 0.8, 0.8))
	var holder: Control = info["holder"]
	var lbl := Label.new()
	lbl.text = move_name
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 2)
	lbl.position = holder.position + Vector2(TOKEN_WIDTH * 0.5 - 24, NAMEPLATE_HEIGHT - 16)
	float_layer.add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.4)
	tw.tween_callback(lbl.queue_free)


## The single highest-value readability addition per docs/ART_THEME.md's own measurement (a
## side's damage concentrates hard on one target — top share 0.711, nowhere near an even split).
## Approximated here as "whoever was hit most recently," which is cheap and, because focus fire IS
## real and concentrated, usually correct — a persistent frequency-weighted version would need
## sliding-window bookkeeping this file doesn't currently keep.
func _set_focus(m) -> void:
	if focus_unit == m:
		return
	if focus_unit != null and unit_nodes.has(focus_unit):
		_clear_glow(focus_unit)
	focus_unit = m
	var info: Dictionary = unit_nodes.get(m)
	if info == null:
		return
	var glow: ColorRect = info["glow"]
	if info["glow_tween"] != null:
		info["glow_tween"].kill()
	var tw := create_tween()
	tw.set_loops()
	tw.tween_property(glow, "color:a", 0.35, 0.4)
	tw.tween_property(glow, "color:a", 0.08, 0.4)
	info["glow_tween"] = tw


func _clear_glow(m) -> void:
	var info: Dictionary = unit_nodes.get(m)
	if info == null:
		return
	if info["glow_tween"] != null:
		info["glow_tween"].kill()
		info["glow_tween"] = null
	var glow: ColorRect = info["glow"]
	glow.color.a = 0.0


func _snap_log_to_bottom() -> void:
	var bar := log_scroll.get_v_scroll_bar()
	if bar != null:
		log_scroll.scroll_vertical = int(bar.max_value)
