## THE TOWN — the hub between the title screen and everywhere else. A backdrop, the player's
## career context (guild badge, league, gold, week, stable size), and a map of locations.
##
## Three locations are REAL destinations: the Market (scenes/market.tscn), the Stable
## (scenes/stable.tscn), and a Tournament (scenes/tactics.tscn). The rest of the guild town
## described in docs/WORLD_GUILDS.md — the Ranch Shop, the Lab, the Breeding Ranch, the Hall of
## Fame — do not have a Godot-side system behind them yet (docs/META_GAME_DISPOSITION.md §5: still
## TypeScript-only in town.ts/game.ts, not ported). Four full screens that open and either do
## nothing or fake a transaction would be worse than not being there at all — so those doors are
## shown LOCKED instead: visible, named, tooltipped with why, never clickable. "A visibly-not-yet-
## implemented door is fine; a button that lies is not."
##
## Reached from the title screen: New Career / Continue both land here (title_ui.gd), per
## docs/CORE_LOOP_PORT.md §2 — the town is the hub, the stable/market/tournament are destinations
## FROM it, not the game's front door.
##
## ⚠️ A NEW CAREER STARTS WITH AN EMPTY STABLE, ON PURPOSE (docs/CORE_LOOP_PORT.md §1). That's the
## single biggest fix this file makes over the previous build, which handed the player a
## pre-made six-monster team and deleted the game's opening decision. Two things follow from an
## empty stable being the correct state, not a bug: an honest callout pointing at the Market
## (`_empty_stable_banner`), and the Tournament door staying VISIBLE and marked "real" (it IS
## built) while being DISABLED with a stated reason until there's a team to field
## (`_make_location_button`'s `forced_disabled` — never a silent dead end).
##
## UI built entirely in code, matching stable_ui.gd/training_ui.gd's established house style —
## dynamic content (career numbers, roster count, locked/unlocked/waiting state) means a
## hand-authored .tscn would just be a template this script overwrites on the first frame anyway.
## Styled via scripts/ui/theme.gd tokens (docs/UI_LAYOUT_RULES.md's "never hand-roll a
## StyleBoxFlat" rule) rather than the inline Color()/StyleBoxFlat literals this file used before.
extends Control

const UiTheme = preload("res://scripts/ui/theme.gd")
## The pace model and the ending screen are the same file on purpose — one definition of par, read
## by the hub, the battle report and the ending alike. See `scripts/ui/ending_ui.gd`'s header.
const Pace = preload("res://scripts/ui/ending_ui.gd")
## The tick's own life-stage rule. ⚠️ READ, NEVER RESTATED — round 15 shipped a stable screen
## promising ceilings the tick did not apply, and the fix is always the same one: ask the function
## that decides rather than writing a second copy of what it decides.
const WeekLib = preload("res://scripts/week.gd")

const GRID_COLUMNS := 4

## Guild-town locations, in grid reading order (left-to-right, top-to-bottom). `real` locations
## navigate to a working scene; locked ones say why not rather than pretending. "The Stable" is
## the Ranch of docs/CORE_LOOP_PORT.md's loop diagram — training, feeding-preview and the roster
## all live there.
const LOCATIONS := [
	{"icon": "🛒", "title": "The Market", "desc": "recruit new partners, release old ones", "real": true, "scene": "res://scenes/market.tscn"},
	{"icon": "🏟", "title": "The Stable", "desc": "train and manage your monsters", "real": true, "scene": "res://scenes/stable.tscn"},
	{"icon": "🥊", "title": "Tournament", "desc": "enter the Circuit", "real": true, "scene": "res://scenes/tournament.tscn"},
	{"icon": "🏗️", "title": "Ranch Shop", "desc": "licences and barn upgrades", "real": true, "scene": "res://scenes/shop.tscn"},
	{"icon": "🧪", "title": "Lab", "desc": "cryo storage for the bloodline", "real": true, "scene": "res://scenes/lab.tscn"},
	{"icon": "🐎", "title": "Breeding Ranch", "desc": "raise the next generation", "real": true, "scene": "res://scenes/breeding.tscn"},
	# ⚠️ THIS DOOR SAID `"real": false` — "not yet built" — WHILE THE FEATURE WAS SHIPPED, and it is
	# `CLAUDE.md`'s named signature failure with the sign flipped. `lab_ui.gd`'s own header states
	# *"IT IS ALSO THE HALL OF FAME, DELIBERATELY, AND NOT A TROPHY CASE"*: a retired champion is
	# preserved (its stats, potential and heirloom stay available to every future foal, enshrined
	# FREE because it can never race again) or released. That IS the hall of fame, and it is a
	# standing decision rather than a display case. So the door opens on the Lab rather than a
	# second screen showing the same list — a trophy room next to it would be the duplicate, not
	# the feature. Renamed with it so the destination is not a surprise.
	{"icon": "🏛", "title": "Hall of Fame", "desc": "champions enshrined — at the Lab", "real": true, "scene": "res://scenes/lab.tscn"},
]

const LOCKED_TOOLTIP := "Not yet built in Godot — the logic still lives in the TypeScript build (docs/META_GAME_DISPOSITION.md §5). Shown so the town reads whole; wired up once it's ported."
const NO_TEAM_TOOLTIP := "Recruit a monster at the Market first — a tournament needs a team to field."

var accent: Color
var badge: String
var header_label: Label
var loc_buttons: Array = []  # PanelContainer per location, LOCATIONS order


func _ready() -> void:
	self.theme = UiTheme.base_theme()
	# ⚠️ THE ONLY ROUTE TO THE ENDING THAT THIS FILE OWNS. `Career.won_game` was set at
	# `career.gd:1220` and read by no screen in the project (`grep won_game scripts/ui/` returned
	# nothing before round 17). The town is the hub every screen returns to, so routing from here
	# means the ending is reachable without editing a file this stream does not own.
	# INTEGRATOR: the better route is one line in `tournament_ui.gd` — see the handover notes; this
	# check then becomes the belt-and-braces path for a save loaded after the fact.
	if _should_show_ending():
		call_deferred("_go_to_ending")
		return
	var identity: Dictionary = Art.team_identity(0)
	badge = identity["badge"]
	accent = UiTheme.team_border_color(0)
	_build_ui()
	# Arriving at the hub is the checkpoint — see `_autosave()`. Every other screen's exit lands
	# here, so one call covers all of them.
	_autosave()


func _build_ui() -> void:
	var tex := Art.area_texture("town")
	if tex != null:
		var bg_rect := TextureRect.new()
		bg_rect.anchor_right = 1; bg_rect.anchor_bottom = 1
		bg_rect.texture = tex
		bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(bg_rect)
	else:
		var bg := ColorRect.new()
		bg.color = UiTheme.SURFACE
		bg.anchor_right = 1; bg.anchor_bottom = 1
		add_child(bg)

	# Scrim so text and cards read over the painted backdrop OR the flat fallback alike.
	var scrim := ColorRect.new()
	scrim.color = Color(0.04, 0.04, 0.06, 0.58)
	scrim.anchor_right = 1; scrim.anchor_bottom = 1
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var root_margin := MarginContainer.new()
	root_margin.anchor_right = 1; root_margin.anchor_bottom = 1
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		root_margin.add_theme_constant_override(side, UiTheme.SPACE_XL)
	add_child(root_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	root_margin.add_child(vbox)

	# ── header: title, guild flavour, career chip, Title button — fixed, never scrolls ─────────
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UiTheme.SPACE_LG)
	vbox.add_child(header)

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_col)

	title_col.add_child(UiTheme.heading("The Town", 1))

	var flavour := UiTheme.body_text(
		"Gradehall, seat of the Assay Table — the guilds that grade every Tamer-monster partnership on the Circuit, Wood to Tamers Apex.",
		"secondary")
	title_col.add_child(flavour)

	header.add_child(_career_chip())

	var title_btn := Button.new()
	title_btn.text = "Title"
	title_btn.focus_mode = Control.FOCUS_ALL
	title_btn.tooltip_text = "Back to the title screen."
	title_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/title.tscn"))
	header.add_child(title_btn)

	vbox.add_child(HSeparator.new())

	# ── THE CLOCK, MADE PRESENT ────────────────────────────────────────────────────────────────
	# The round-17 acceptance bar. A grade revealed after 400 weeks converts nothing; the player
	# has to be able to answer "am I doing well?" without opening a menu, on the screen they pass
	# through most. So the pace strip sits above the doors, on every visit, always.
	var pace_strip := _pace_strip()
	if pace_strip != null:
		vbox.add_child(pace_strip)

	# ── the one genuine failure mode in the game, named ────────────────────────────────────────
	var oc := _outclassed_banner()
	if oc != null:
		vbox.add_child(oc)

	# ── the opening decision: an empty stable is the CORRECT new-game state, so say so ─────────
	var stable_empty: bool = not has_node("/root/Roster") or Roster.monsters.is_empty()
	if stable_empty:
		vbox.add_child(_empty_stable_banner())

	# ── the body — doors on the left, the stable's own state on the right ──────────────────────
	# ⚠️ THE BOTTOM 52% OF THIS SCREEN WAS EMPTY BLACK (measured from `02_town.png`, round 18's
	# before-capture): seven cards, then void. The hub of a management game showed nothing whatever
	# about the stable it manages — a door menu with a good banner on top. Everything added below
	# is READ FROM THE LIVE OBJECTS at build time (`Roster.monsters`, `WeekPlan.plan_for`,
	# `WeekLib.stage_info`, `WeekPlan.rent_for`), never cached and never a second copy of a rule.
	var body_scroll := ScrollContainer.new()
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(body_scroll)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(body)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", UiTheme.SPACE_LG)
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(split)

	var doors_col := VBoxContainer.new()
	doors_col.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	doors_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doors_col.size_flags_stretch_ratio = 2.0
	split.add_child(doors_col)

	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", UiTheme.SPACE_MD)
	grid.add_theme_constant_override("v_separation", UiTheme.SPACE_MD)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doors_col.add_child(grid)

	loc_buttons.clear()
	for loc in LOCATIONS:
		var forced_disabled: bool = (loc["title"] == "Tournament") and stable_empty
		var card := _make_location_button(loc, forced_disabled, NO_TEAM_TOOLTIP)
		grid.add_child(card)
		loc_buttons.append(card)
	_wire_grid_focus(GRID_COLUMNS)

	var agenda_col := VBoxContainer.new()
	agenda_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	agenda_col.size_flags_stretch_ratio = 1.0
	split.add_child(agenda_col)
	agenda_col.add_child(_agenda_panel())

	# ⚠️ FULL WIDTH, NOT BESIDE THE DOORS. Five condition cards sharing two thirds of the page got
	# ~148px each and every line inside them wrapped — read off this round's own after-capture. The
	# strip is a ROW of comparable bodies and its whole value is that they can be read across, so it
	# gets the width and the doors keep the top.
	body.add_child(_stable_strip())

	vbox.add_child(HSeparator.new())

	# ── footer: End Week — fixed, never scrolls, so the primary action stays reachable ─────────
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	vbox.add_child(footer)

	var week_btn := Button.new()
	week_btn.text = "End Week"
	week_btn.custom_minimum_size = Vector2(0, 40)
	week_btn.focus_mode = Control.FOCUS_ALL
	week_btn.tooltip_text = "Runs the week: booked drills, feeding, stamina, ageing and the freezer's rent — the same tick the Stable's Advance Week runs."
	week_btn.pressed.connect(_on_end_week)
	footer.add_child(week_btn)

	var footer_note := UiTheme.body_text("The Market's recruits restock with each new week.", "muted")
	footer_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(footer_note)

	# Land keyboard focus on the first ENABLED door so a keyboard-only player reaches somewhere
	# useful in one Tab press, even when Tournament is temporarily disabled by an empty stable.
	for card in loc_buttons:
		var btn: Button = card.get_child(0)
		if not btn.disabled:
			btn.grab_focus()
			break


func _career_chip() -> Control:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", UiTheme.SPACE_XS)

	var badge_lbl := Label.new()
	badge_lbl.text = badge
	badge_lbl.add_theme_color_override("font_color", accent)
	badge_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBHEADING)
	chip.add_child(badge_lbl)

	header_label = Label.new()
	header_label.add_theme_color_override("font_color", accent)
	header_label.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBHEADING)
	chip.add_child(header_label)
	_refresh_header_text()

	return chip


func _refresh_header_text() -> void:
	if header_label == null:
		return
	var league_name := "?"
	var gold := 0
	var week := 0
	if has_node("/root/Career"):
		league_name = Career.current_league_name()
		gold = Career.gold
		week = Career.week
	var stable_size := Roster.monsters.size() if has_node("/root/Roster") else 0
	header_label.text = "%s league  ·  %d gold  ·  week %d  ·  %d in the stable" % [league_name, gold, week, stable_size]


## ⚠️ ROUND 17'S WHOLE POINT LIVES IN THIS FUNCTION, NOT IN THE ENDING SCREEN.
## `docs/CONVERSION_DIAGNOSIS.md` §5 R17-1 states the risk in its own recommendation: *"it is a
## framing change. If the player never feels the clock, it converts nothing — a scoreboard is not
## a stake."* A grade on a screen visited once cannot be the answer. This strip is the answer: the
## week, the rung, and where the Dynast's own climb had reached by this same week — on the hub, on
## every visit, next to the doors the player is about to choose between.
##
## Every value is read from `Career` through `Pace.snapshot()` at build time. Nothing is cached
## and nothing is recomputed here (the round-13 scoreboard announced a winner at frame 0 and
## disagreed with the frame in 100% of frames; the round-15 stable screen promised ceilings the
## tick never applied — both were screens holding their own copy of a fact).
func _pace_strip() -> Control:
	var snap: Dictionary = Pace.snapshot()
	if snap.is_empty():
		return null

	var panel := PanelContainer.new()
	var col_accent: Color = Pace.pace_color(snap)
	var sb := UiTheme.panel_style("raised", col_accent)
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(v)

	var line := UiTheme.body_text(Pace.pace_line(snap), "primary")
	line.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBHEADING)
	line.add_theme_color_override("font_color", col_accent)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(line)

	v.add_child(_ladder_track(int(snap["leagueIndex"]), int(snap["week"])))

	var foot := UiTheme.body_text(
		"Any stable finishes the Circuit eventually. The record is what's contested — the ending grades how fast you took it.",
		"muted")
	foot.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(foot)
	return panel


const LEAGUE_ABBREV := {
	"Wood": "Wood", "Copper": "Cop", "Tin": "Tin", "Bronze": "Brz", "Iron": "Iron",
	"Silver": "Silv", "Gold": "Gold", "Platinum": "Plat", "Masters": "Mast",
	"Tamer Elite": "Elite", "Tamers Apex": "Apex",
}


## Two rows of rungs: where YOU are, and where the Dynast's climb had reached by this same week.
## The Dynast's rung is READ FROM THE PAR CURVE at the CURRENT week — it moves as the weeks pass,
## which is what makes this a race rather than a label.
func _ladder_track(player_idx: int, week: int) -> Control:
	var leagues: Array = Career.leagues if has_node("/root/Career") else []
	var n: int = leagues.size()
	# ⚠️ ASKED, NOT DERIVED. `Career.dynasty_rung_at_week()` is the same function the grade and the
	# standing line use, so the bar cannot say the pace-setter is somewhere the sentence above it
	# disagrees with. An earlier draft of this loop recomputed it from the par curve and was one
	# off-by-one away from exactly that.
	var dynast_idx: int = Pace.par_rung_at_week(week)

	var grid := GridContainer.new()
	grid.columns = maxi(1, n)
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)

	# row 1 — names
	for i in range(n):
		var nm: String = str((leagues[i] as Dictionary).get("name", "?"))
		var l := Label.new()
		l.text = str(LEAGUE_ABBREV.get(nm, nm))
		l.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
		l.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY if i == player_idx else UiTheme.TEXT_MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(58, 0)
		l.tooltip_text = "%s — the pace-setter arrives in week %d." % [nm, Pace.par_week_for(i)]
		grid.add_child(l)

	# row 2 — YOU
	for i in range(n):
		grid.add_child(_rung_cell(i <= player_idx, i == player_idx, UiTheme.GOLD))
	# row 3 — the Dynast at this same week
	for i in range(n):
		grid.add_child(_rung_cell(i <= dynast_idx, i == dynast_idx, UiTheme.TEXT_SECONDARY))

	# Row LABELS rather than a legend underneath — the two bars are the whole comparison, and a
	# legend a few pixels below is exactly the kind of thing a player never connects to the bar.
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 3)
	rows.add_child(_track_row_label("", UiTheme.TEXT_MUTED))
	rows.add_child(_track_row_label("you", UiTheme.GOLD))
	rows.add_child(_track_row_label(_pace_setter_short(), UiTheme.TEXT_SECONDARY))

	var wrap := HBoxContainer.new()
	wrap.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	wrap.add_child(rows)
	wrap.add_child(grid)
	return wrap


## The pace-setter's surname, off `Career`'s own authored name — never a second literal.
func _pace_setter_short() -> String:
	var snap: Dictionary = Pace.snapshot()
	var tamer: String = str((snap.get("dynasty", {}) as Dictionary).get("tamer", ""))
	if tamer == "":
		return "par"
	var parts: PackedStringArray = tamer.split(" ")
	return parts[parts.size() - 1]


func _track_row_label(text: String, tint: Color) -> Control:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	l.add_theme_color_override("font_color", tint)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.custom_minimum_size = Vector2(56, 14)
	return l


func _rung_cell(filled: bool, is_head: bool, tint: Color) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(58, 14)
	var sb := StyleBoxFlat.new()
	if filled:
		sb.bg_color = Color(tint.r, tint.g, tint.b, 1.0 if is_head else 0.62)
	else:
		sb.bg_color = Color(UiTheme.BORDER_FAINT.r, UiTheme.BORDER_FAINT.g, UiTheme.BORDER_FAINT.b, 1.0)
	if is_head:
		sb.border_color = UiTheme.TEXT_PRIMARY
		sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	p.add_theme_stylebox_override("panel", sb)
	return p


## ⚠️ THE VERDICT IS REACHED ELSEWHERE AND ONLY NAMED HERE. `Pace.frontier_verdict()` passes
## through `Career.frontier_verdict()`, which judges on the ROUND rate off a record the career
## keeps. This screen decides nothing: it renders the state and shows Career's own sentence
## verbatim. A screen cannot tell "outclassed" from "unlucky" — that distinction IS the finding
## (`docs/CONVERSION_DIAGNOSIS.md` §2c: three of four "walls" were rates, the fourth was real at
## 4 round wins in 120) — and guessing it here would make this banner the lie it exists to prevent.
##
## Two states are shown and two are not. **outclassed** is the one genuine failure mode in the
## game and it gets the loudest treatment the theme has, plus the three things that actually fix
## it. **unlucky** is shown because it is the OPPOSITE advice and a player who cannot tell them
## apart is exactly the player §2c describes. "climbing" and "fresh" stay silent — a hub that
## comments on every ordinary week is a hub nobody reads.
func _outclassed_banner() -> Control:
	var s: Dictionary = Pace.frontier_verdict()
	if s.is_empty():
		return null
	var state: String = str(s.get("state", "fresh"))
	if state != "outclassed" and state != "unlucky":
		return null

	var bad: bool = state == "outclassed"
	var accent: Color = UiTheme.DANGER if bad else UiTheme.CAUTION

	var panel := PanelContainer.new()
	var sb := UiTheme.panel_style("raised", accent)
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	panel.add_child(row)

	var icon := Label.new()
	icon.text = "⚑" if bad else "🎲"
	icon.add_theme_font_size_override("font_size", UiTheme.SIZE_HEADING)
	icon.add_theme_color_override("font_color", accent)
	row.add_child(icon)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	row.add_child(col)

	var league: String = str(s.get("league", ""))
	var head := UiTheme.body_text(
		("This stable is OUTCLASSED at %s." % league) if bad else ("You are unlucky at %s, not outmatched." % league),
		"primary")
	head.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBHEADING)
	head.add_theme_color_override("font_color", accent)
	col.add_child(head)

	# Career's own sentence, verbatim — it already carries the rounds, the wins and the rate.
	var ev := UiTheme.body_text(str(s.get("line", "")), "primary")
	ev.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(ev)

	var advice: String = (
		"The roster is the problem, not the dice. Three ways out: TRAIN the bodies you have toward this rung's ceiling, RECRUIT at the Market for the stats you are short of, or BREED for a bloodline with the potential to carry them further."
		if bad else
		"Nothing here needs fixing. Enter the next cup — this rung falls to the roster you already have.")
	var fix := UiTheme.body_text(advice, "secondary")
	fix.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(fix)
	return panel


func _should_show_ending() -> bool:
	if not has_node("/root/Career"):
		return false
	if not bool(Career.won_game):
		return false
	# Shown once per session, then the player is free to keep running the stable. `ending_ui.gd`
	# sets this the moment it opens.
	return not Career.has_meta("ending_seen")


func _go_to_ending() -> void:
	get_tree().change_scene_to_file("res://scenes/ending.tscn")


## The opening decision the player hasn't made yet. An empty stable used to be a bug in this
## build; now it's the correct state on a fresh career (docs/CORE_LOOP_PORT.md §1), so the town
## says why it looks bare and points at the one real door that fixes it, rather than leaving the
## player to guess — CORE_LOOP_PORT.md §4's "never leave a dead-end screen."
func _empty_stable_banner() -> Control:
	var panel := PanelContainer.new()
	var sb := UiTheme.panel_style("raised", UiTheme.GOLD)
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	panel.add_child(row)

	var icon := Label.new()
	icon.text = "🛒"
	icon.add_theme_font_size_override("font_size", UiTheme.SIZE_HEADING)
	row.add_child(icon)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	row.add_child(col)

	col.add_child(UiTheme.body_text("Your stable is empty — that's where every career starts.", "primary"))
	var gold := Career.gold if has_node("/root/Career") else 500
	var cap := Career.barn_capacity if has_node("/root/Career") else 2
	col.add_child(UiTheme.body_text(
		"%d gold, room for %d. Recruiting your first monster at the Market is the first real decision of the game." % [gold, cap],
		"secondary"))

	var go_btn := Button.new()
	go_btn.text = "Go to the Market →"
	go_btn.focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "disabled"]:
		go_btn.add_theme_stylebox_override(state, UiTheme.button_stylebox("primary", state))
	go_btn.add_theme_stylebox_override("focus", UiTheme.button_stylebox("primary", "focus"))
	go_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/market.tscn"))
	row.add_child(go_btn)

	return panel


## ── THE STABLE, ON THE HUB ────────────────────────────────────────────────────────────────────
## ⚠️ THE LIFE ARC IS THE DRAMA AND IT WAS INVISIBLE. Monster Rancher's whole engine is that your
## best monster is dying: it is born, peaks, declines and retires and you feel all four. Every
## field needed to say so already exists on `MonsterInstance` (`age_weeks`, `lifespan_years`,
## `stamina`, `happiness`) and `week.gd:stage_info` already grades it — and before this round the
## only screen in the entire game that showed age was the ENDING screen, after the player had
## stopped playing. This strip is the cheapest possible correction: the roster, as bodies, with
## the four numbers that decide whether this week's gold goes into them.
##
## ⚠️ IT DESCRIBES, IT DOES NOT DECIDE. Stage and training multiplier come from `WeekLib`; plan
## state comes from `WeekPlan.plan_for()` — the same dictionary `advance()` will actually spend.
func _stable_strip() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	var monsters: Array = Roster.monsters if has_node("/root/Roster") else []
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	col.add_child(head)
	var h := UiTheme.heading("The stable this week", 3)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h)
	var frozen: Array = Roster.frozen if has_node("/root/Roster") else []
	if not frozen.is_empty():
		head.add_child(_nowrap(UiTheme.body_text("%d preserved · %dg/week" % [
			frozen.size(), WeekPlan.rent_for(frozen)], "muted")))

	if monsters.is_empty():
		col.add_child(UiTheme.body_text("No bodies yet.", "muted"))
		return panel

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	col.add_child(row)
	for mi in monsters:
		row.add_child(_condition_card(mi))
	return panel


## ⚠️ `UiTheme.body_text` TURNS WORD-WRAP ON, WHICH IS WRONG INSIDE ANY HORIZONTAL ROW. A wrapping
## label reports a minimum width of one character, so it collapses to a vertical strip of single
## words and takes its neighbours' space with it. It happened three times in this round across
## three files (here, `shop_ui.gd`'s tables, `lab_ui.gd`'s ledger tiles) and EVERY MECHANICAL CHECK
## PASSED ON ALL THREE FRAMES — the probe counts controls, not legibility. Only reading the capture
## caught it. Wrap off for anything that lives in a row or a grid cell.
func _nowrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


func _condition_card(mi) -> Control:
	var info: Dictionary = WeekLib.stage_info(mi.age_weeks, mi.lifespan_years)
	var stage: String = str(info["stage"])
	# The stage is the story, so it carries the card's colour — and the WORD is always present
	# beside it (docs/ACCESSIBILITY.md: never encode meaning in hue alone).
	var tint: Color = UiTheme.TEXT_SECONDARY
	match stage:
		# ⚠️ NOT `FOCUS`. That cyan is the keyboard-focus ring and theme.gd's own comment says it is
		# "never reused for anything else" — the moment a life stage and a mood bar also draw in it,
		# a focus ring stops being identifiable as one. STATUS_BUFF is the teal the palette keeps
		# deliberately clear of it, and the stage WORD is always beside the colour anyway.
		"Baby": tint = UiTheme.STATUS_BUFF
		"Teen": tint = UiTheme.SAFE
		"Fully Grown": tint = UiTheme.GOLD
		"Elder": tint = UiTheme.CAUTION
		"Retiree": tint = UiTheme.DANGER

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("raised", tint))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	col.add_child(top)
	top.add_child(_portrait(mi.species_id, mi.species_name, Vector2(52, 52)))

	var name_col := VBoxContainer.new()
	name_col.add_theme_constant_override("separation", 0)
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_col)
	var nm := UiTheme.body_text(mi.species_name, "primary")
	nm.autowrap_mode = TextServer.AUTOWRAP_OFF
	nm.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	name_col.add_child(nm)
	name_col.add_child(_nowrap(UiTheme.body_text(mi.class_name_, "muted")))

	# ⚠️ THE AGE, IN THE UNITS THE PLAYER THINKS IN. `x.x of y.y yrs` is the whole life arc in one
	# string, and the training multiplier beside the stage is WHY it matters this week rather than
	# some week later — an Elder at ×0.80 is losing value every week it is not spent.
	var years: float = float(mi.age_weeks) / float(WeekLib.WEEKS_PER_YEAR)
	var st := _nowrap(UiTheme.body_text("%s  %.1f/%.1fy  train ×%.2f" % [
		stage, years, mi.lifespan_years, float(info["trainMult"])], "secondary"))
	st.add_theme_color_override("font_color", tint)
	col.add_child(st)

	# The two stats this body actually has — the one-line answer to "what is it FOR", and the thing
	# the class name only gestures at.
	col.add_child(_nowrap(UiTheme.body_text(_top_stats_line(mi), "secondary")))

	# ⚠️ AUTHORED AND UNREACHED, FIXED HERE. Every monster carries a `favourite_food` and a
	# `hated_food` (`game_data.gd:_pick_food_prefs`) and `docs/META_UI_DIRECTION.md` §2 slack-point 2
	# records that NO screen in the game showed either — so the food step has been a chore with a
	# hidden right answer since it was built. Naming the preference here costs one line and turns
	# it into a small real choice.
	if str(mi.favourite_food) != "":
		col.add_child(_nowrap(UiTheme.body_text("♥ %s" % _food_name(str(mi.favourite_food)), "muted")))

	col.add_child(UiTheme.stat_bar("stam", mi.stamina, WeekLib.MAX_STAMINA,
		UiTheme.SAFE if mi.stamina > 50.0 else (UiTheme.CAUTION if mi.stamina > 30.0 else UiTheme.DANGER), 34))
	col.add_child(UiTheme.stat_bar("mood", float(mi.happiness), float(WeekLib.MAX_HAPPINESS), UiTheme.STATUS_BUFF, 34))

	# The plan, in the words the Stable screen uses for it. `chosen` distinguishes "the player
	# rested it" from "the player has not looked at it" — see `week_plan.gd:set_activity`'s ⚠️.
	var plan_line := "—"
	var plan_tier := "muted"
	if mi.retired:
		plan_line = "retired — decide at the Lab"
		plan_tier = "primary"
	elif has_node("/root/WeekPlan"):
		var p: Dictionary = WeekPlan.plan_for(mi.id)
		var act: String = str(p.get("activity", "rest"))
		if not bool(p.get("chosen", false)):
			plan_line = "◇ no plan booked"
			plan_tier = "primary"
		elif act == "rest":
			plan_line = "● resting"
		else:
			plan_line = "● %s" % str(WeekLib.drill_by_id(act).get("name", act))
	var pl := _nowrap(UiTheme.body_text(plan_line, plan_tier))
	if plan_tier == "primary" and not mi.retired:
		pl.add_theme_color_override("font_color", UiTheme.CAUTION)
	elif mi.retired:
		pl.add_theme_color_override("font_color", UiTheme.DANGER)
	col.add_child(pl)
	return panel


## The two highest stats, named and valued. Read straight off `mi.stats` — six floats, no table.
func _top_stats_line(mi) -> String:
	var pairs: Array = []
	for s in mi.stats.keys():
		pairs.append([str(s), float(mi.stats[s])])
	pairs.sort_custom(func(x, y): return float(x[1]) > float(y[1]))
	if pairs.size() < 2:
		return ""
	return "%s %d · %s %d" % [pairs[0][0], int(pairs[0][1]), pairs[1][0], int(pairs[1][1])]


## `week.gd:food_by_id` owns the table — never a second copy of it here (the forbidden pattern in
## `.claude/docs/technical-preferences.md`).
func _food_name(food_id: String) -> String:
	return str(WeekLib.food_by_id(food_id).get("name", food_id))


## Real portrait if `Art` has one, otherwise the species' initials at the SAME footprint. Local to
## this file on purpose — `stable_ui.gd`/`market_ui.gd` each carry their own for the same reason
## (they belong to other workstreams), and a shared one is a refactor, not this round's job.
func _portrait(species_id: String, species_name: String, size_px: Vector2) -> Control:
	var tex: Texture2D = Art.creature_texture(species_id)
	if tex != null:
		var t := TextureRect.new()
		t.texture = tex
		t.custom_minimum_size = size_px
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		return t
	var p := PanelContainer.new()
	p.custom_minimum_size = size_px
	p.add_theme_stylebox_override("panel", UiTheme.panel_style("default", accent))
	var l := Label.new()
	l.text = species_name.substr(0, 2).to_upper()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", accent)
	l.add_theme_font_size_override("font_size", int(size_px.y * 0.35))
	p.add_child(l)
	return p


## ── WHAT IS WORTH DOING THIS WEEK ─────────────────────────────────────────────────────────────
## The acceptance bar for this screen is: *from the town, a player can name the single best thing
## to do this week.* A row of doors cannot answer that — it lists where you may go, never what is
## waiting there. So every prompt below is DERIVED FROM LIVE STATE and ranked, the top one gets
## the button, and when nothing is wrong the panel says so rather than inventing urgency.
##
## ⚠️ NOTHING HERE MAY BE A GUESS. Each rule reads the same object the acting screen reads, so a
## prompt that says "3 have no plan" is counting the exact dictionaries `WeekPlan.advance()` will
## spend. A hub that nags about a state the destination screen disagrees with is the round-13
## scoreboard again.
func _agenda_panel() -> Control:
	var panel := PanelContainer.new()
	var items: Array = _agenda_items()
	var top_tint: Color = items[0]["tint"] if not items.is_empty() else UiTheme.BORDER
	var sb := UiTheme.panel_style("raised", top_tint)
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)
	col.add_child(UiTheme.heading("This week", 3))
	col.add_child(UiTheme.body_text(_calendar_line(), "muted"))
	col.add_child(HSeparator.new())

	for i in range(items.size()):
		var it: Dictionary = items[i]
		var line := UiTheme.body_text(("➤ " if i == 0 else "· ") + str(it["text"]),
			"primary" if i == 0 else "secondary")
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		## ⚠️ RANK IS THE EMPHASIS CHANNEL HERE AND IT STAYS THAT WAY — only the top prompt is
		## tinted, or the panel becomes a wall of amber and the ranking stops meaning anything.
		## `emphasise` is the one deliberate exception: the gap row is appended LAST on purpose
		## (it is about the stable's shape, not about this week) but a BLOCKING gap still has to
		## be visible from the doorway. It is the only key that sets it, and it never sets it for
		## a severity-1 gap — see `_agenda_items()` item 7 and THE GAP VOICE below it.
		if i == 0 or bool(it.get("emphasise", false)):
			line.add_theme_color_override("font_color", it["tint"])
		col.add_child(line)
		# Only the top prompt gets a button. Five buttons is a second navigation grid, and the
		# panel's job is to RANK, not to duplicate the doors two columns to its left.
		if i == 0 and str(it.get("scene", "")) != "":
			var b := Button.new()
			b.text = str(it["action"])
			b.custom_minimum_size = Vector2(0, 34)
			b.focus_mode = Control.FOCUS_ALL
			for state in ["normal", "hover", "pressed", "disabled"]:
				b.add_theme_stylebox_override(state, UiTheme.button_stylebox("primary", state))
			b.add_theme_stylebox_override("focus", UiTheme.button_stylebox("primary", "focus"))
			var target: String = str(it["scene"])
			b.pressed.connect(func(): get_tree().change_scene_to_file(target))
			col.add_child(b)

	col.add_child(HSeparator.new())
	col.add_child(UiTheme.body_text(_purse_line(), "secondary"))
	return panel


## The game-year clock `cup_run.gd` already keeps — 13 months of 4 weeks — plus the marquee if one
## falls in this month at or below the player's rung. ⚠️ ASKED, NOT RECOMPUTED: `CupRun.is_marquee`
## and `CupRun.marquee_name` are the same calls the tournament screen and the purse multiplier use,
## so the hub cannot advertise an event the cup screen does not run.
func _calendar_line() -> String:
	if not has_node("/root/CupRun") or not has_node("/root/Career"):
		return ""
	var wpm: int = CupRun.WEEKS_PER_MONTH
	var mpy: int = CupRun.MONTHS_PER_YEAR
	var year: int = int(Career.week) / (wpm * mpy) + 1
	var month: int = (int(Career.week) % (wpm * mpy)) / wpm + 1
	var out := "Year %d, month %d of %d" % [year, month, mpy]
	for i in range(Career.league_index + 1):
		if CupRun.is_marquee(i):
			out += "  ·  ★ %s is on" % CupRun.marquee_name(i)
			break
	return out


func _purse_line() -> String:
	var gold: int = Career.gold if has_node("/root/Career") else 0
	var bill: int = 0
	if has_node("/root/WeekPlan") and has_node("/root/Roster"):
		bill = WeekPlan.rent_for(Roster.frozen)
	var planned: Dictionary = {}
	if has_node("/root/WeekPlan") and has_node("/root/Roster"):
		planned = WeekPlan.projected_cost(Roster.monsters)
	var food: int = int(planned.get("gold", 0))
	return "%dg in hand · this week costs %dg food + %dg freezer" % [gold, food, bill]


func _agenda_items() -> Array:
	var out: Array = []
	if not has_node("/root/Roster") or not has_node("/root/Career"):
		return out
	var monsters: Array = Roster.monsters

	if monsters.is_empty():
		out.append({"text": "The stable is empty. Nothing else can happen until there is a body in it.",
			"action": "Go to the Market →", "scene": "res://scenes/market.tscn", "tint": UiTheme.GOLD})
		return out

	# 1 — a retiree is the loudest thing in the game: it holds a barn slot and can never race again.
	var retirees: Array = Roster.retirees_in_barn()
	if not retirees.is_empty():
		out.append({"text": "%s has retired. It holds a barn slot and can never race again — enshrine it free at the Lab to keep its line, or release it." % retirees[0].species_name,
			"action": "Go to the Lab →", "scene": "res://scenes/lab.tscn", "tint": UiTheme.DANGER})

	# 2 — an unbooked week is a week spent for nothing. `chosen` is what tells "rested on purpose"
	# from "never looked at", which is exactly why `week_plan.gd` carries that flag.
	var unplanned := 0
	for mi in monsters:
		if mi.retired:
			continue
		if not bool(WeekPlan.plan_for(mi.id).get("chosen", false)):
			unplanned += 1
	if unplanned > 0:
		out.append({"text": "%d of %d have no plan booked. End the week now and they rest for free and train nothing." % [
			unplanned, monsters.size()],
			"action": "Go to the Stable →", "scene": "res://scenes/stable.tscn", "tint": UiTheme.CAUTION})

	# 3 — training below 30 stamina rolls at HALF (`week.gd:stamina_malus`). Read, not restated.
	var tired: Array = []
	for mi in monsters:
		if not mi.retired and mi.stamina <= 30.0:
			tired.append(mi.species_name)
	if not tired.is_empty():
		out.append({"text": "%s below 30 stamina — every drill rolls at ×%.2f until they rest." % [
			", ".join(PackedStringArray(tired)), WeekLib.stamina_malus(0.0)],
			"action": "Go to the Stable →", "scene": "res://scenes/stable.tscn", "tint": UiTheme.CAUTION})

	# 4 — cannot field the league you have reached. `entry_block_reason` is the tournament screen's
	# own gate, so this cannot promise an entry the cup screen refuses.
	var need: int = Career.current_team_size()
	var block: String = Roster.entry_block_reason(need)
	if block != "":
		out.append({"text": block,
			"action": "Go to the Market →", "scene": "res://scenes/market.tscn", "tint": UiTheme.CAUTION})

	# 5 — the marquee is the only 1.75x purse in the game and it is on for one month a year.
	if has_node("/root/CupRun"):
		for i in range(Career.league_index + 1):
			if CupRun.is_marquee(i):
				out.append({"text": "★ %s is on this month — a deeper field, and ×%.2f the purse. It will not come round again this year." % [
					CupRun.marquee_name(i), CupRun.MARQUEE_PURSE_MULT],
					"action": "Go to the Tournament →", "scene": "res://scenes/tournament.tscn",
					"tint": UiTheme.GOLD})
				break

	# 6 — a full barn is what blocks breeding, succession and the bench all at once (`shop_ui.gd`'s
	# long ⚠️). Only worth saying when the gold to fix it is actually in hand.
	if monsters.size() >= Career.barn_capacity:
		out.append({"text": "The barn is full at %d. No foal, no fusion and no recruit can land until there is a stall for it." % Career.barn_capacity,
			"action": "Go to the Shop →", "scene": "res://scenes/shop.tscn", "tint": UiTheme.TEXT_SECONDARY})

	if out.is_empty():
		out.append({"text": "Nothing is urgent. Every body is planned, rested and housed — this is the week to spend on the ladder.",
			"action": "Go to the Tournament →", "scene": "res://scenes/tournament.tscn", "tint": UiTheme.SAFE})

	# LAST — WHAT THIS STABLE CANNOT YET DO. Every prompt above is about THIS WEEK; this one is the
	# only line on the panel about the stable's SHAPE, and it is what makes "the single best thing
	# to do this week" an honest naming rather than a checklist of chores. `Roster.stable_gaps()` —
	# see THE GAP VOICE block below this function, and never a second copy of the analysis here.
	#
	# ⚠️ APPENDED AFTER THE EMPTY-CHECK ABOVE, AND ALWAYS. Two reasons, and the first one was found
	# by tracing the capture fixture rather than by reading the code: at the probe's mid-career
	# Bronze stable `stable_gaps()` returns EMPTY (5 fieldable against a team of 3, Iron also 3,
	# damage and support both held, two of the four rushdown classes owned, all five still
	# training), so a row that only appears when there IS a gap would have shipped invisible and
	# been captured as "no change". Second and larger: an empty gap list is a RESULT — the four
	# questions were asked and all four passed — and a panel that silently drops the question it
	# just asked leaves the player unable to tell "nothing missing" from "never checked". That is
	# the same defect as a blank capture passing for a good one.
	#
	# ⚠️ ONE FACT, ONE ROW. `block` above is the bodies shortfall said as a GATE ("this cup needs 3
	# — you have 2"); gap #1 is the same arithmetic said as a lack. Printing both is the exact
	# defect this round was sent to fix on the Tournament screen, so the gap yields to the gate.
	var gaps: Array = Roster.stable_gaps()
	var shown := false
	for gv in gaps:
		var g: Dictionary = gv
		if str(g["kind"]) == "bodies" and block != "":
			continue
		# ⚠️ THE GLYPH GOES WHERE THE COLOUR GOES, AND ONLY THERE. A blocking gap is tinted CAUTION,
		# so it carries `▲` too — hue is never the only channel. A severity-1 gap is left in the
		# panel's ordinary secondary colour, which encodes nothing, so it needs no mark.
		out.append({"text": ("▲ " if int(g["severity"]) >= 2 else "") + gap_sentence(g),
			"action": "Go to the Market →", "scene": "res://scenes/market.tscn",
			"tint": UiTheme.CAUTION if int(g["severity"]) >= 2 else UiTheme.TEXT_SECONDARY,
			"emphasise": int(g["severity"]) >= 2})
		shown = true
		break
	if not shown:
		## The Market's all-clear, word for word — the one vocabulary, taken literally. It names the
		## four questions so the answer is legible as an answer.
		out.append({"text": "Nothing your stable lacks: enough bodies for this rung and the next, damage and support both held, part of the answer to this league's champion, and every body still able to train.",
			"action": "", "scene": "", "tint": UiTheme.SAFE})
	return out


# ══════════════════════════════════════════════════════════════════════════════════════════════
# THE GAP VOICE — decided round 20, applied on FOUR screens, written down here because it was
# invented once and must not be re-invented three more times.
# ══════════════════════════════════════════════════════════════════════════════════════════════
#
# `Roster.stable_gaps()` was built screen-agnostic and called from exactly one screen (the
# Market). Three more want it, and the reason round 19 did not wire them is that each is a real
# decision about what its prompt should SAY — three screens inventing three phrasings at the end
# of an integration round is how this project ended up in four registers the round before.
#
# THE RULE, in three parts:
#
#   1. THE WORDS ARE `stable_gaps()`'s WORDS. Every screen prints `headline` VERBATIM — a noun
#      phrase naming a lack ("2 more bodies that can compete", "no support body at all"). Never a
#      paraphrase, because a paraphrase is a second copy of the analysis in prose, and never a
#      recommendation, because ⚠️ NAMING THE GAP IS THE JOB AND NAMING THE PURCHASE IS NOT — a
#      screen that thinks for the player fails the same test as a training week that is an
#      obvious click. Sentence-case is applied where a headline starts a sentence; that is
#      capitalisation, not rewording.
#   2. SEVERITY IS THE MARKET'S TWO GLYPHS, `▲` (blocks something today) and `•` (bites at the
#      next step), paired with CAUTION / TEXT_SECONDARY. Never hue alone (docs/ACCESSIBILITY.md),
#      and never `▸` — it is not in the packaged font and renders as a tofu dot. The precise rule
#      is THE GLYPH GOES WHERE THE COLOUR GOES: a list that tints both severities carries both
#      glyphs (Market, Tournament); the Town shows one gap in a ranked prompt list and tints only
#      the blocking case, so only that case is marked. An unmarked line there encodes nothing.
#   3. WHAT DIFFERS PER SCREEN IS DEPTH AND THE LEAD-IN, NEVER THE VOCABULARY:
#        Market      "What your stable lacks"   — every gap, headline + detail, the full panel.
#        Town        the TOP gap only, as one agenda prompt, behind the door that fixes it.
#        Tournament  every gap, above the draw — said ONCE, before the cup, not at the gate.
#        Lab         "The stable would then lack:" — the headlines a preservation would OPEN.
#
# ⚠️ AN EMPTY GAP LIST IS A RESULT AND MUST RENDER AS ONE. "Nothing this screen can name" is
# information; manufacturing a gap to fill a panel, or silently rendering nothing, are both the
# screen lying about the thing it describes.


## One gap as one sentence — the Town's and the Tournament's shared form. The headline is
## sentence-cased for its position and otherwise untouched; the detail follows it whole.
static func gap_sentence(g: Dictionary) -> String:
	var head: String = str(g.get("headline", ""))
	if head == "":
		return str(g.get("detail", ""))
	return "%s%s. %s" % [head.substr(0, 1).to_upper(), head.substr(1), str(g.get("detail", ""))]


## `forced_disabled`/`forced_reason` let a location that IS built (e.g. Tournament) be temporarily
## unavailable for a stated reason — distinct from `loc["real"] == false`, which means "not built
## at all". Both end in a disabled button with a tooltip; neither is ever a silent dead end.
func _make_location_button(loc: Dictionary, forced_disabled: bool = false, forced_reason: String = "") -> PanelContainer:
	var authored_real: bool = loc["real"]
	var clickable: bool = authored_real and not forced_disabled

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(210, 112)

	var base_sb: StyleBoxFlat = UiTheme.panel_style("default", accent if clickable else UiTheme.BORDER_FAINT)
	if clickable:
		base_sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", base_sb)

	var btn := Button.new()
	btn.flat = true
	btn.focus_mode = Control.FOCUS_ALL
	btn.disabled = not clickable
	btn.anchor_right = 1; btn.anchor_bottom = 1
	if not authored_real:
		btn.tooltip_text = LOCKED_TOOLTIP
	elif forced_disabled:
		btn.tooltip_text = forced_reason
	else:
		btn.tooltip_text = "%s — select" % loc["title"]
	if clickable:
		var target: String = loc["scene"]
		btn.pressed.connect(func(): get_tree().change_scene_to_file(target))
	panel.add_child(btn)

	# Repaint the card's border on focus so the focus ring is visible for EVERY card — a keyboard
	# user tabbing past a locked or temporarily-disabled door should still see where focus landed,
	# even though activating it does nothing (docs/ACCESSIBILITY.md §7, SC 2.4.7).
	btn.focus_entered.connect(func(): panel.add_theme_stylebox_override("panel", UiTheme.focus_style(base_sb)))
	btn.focus_exited.connect(func(): panel.add_theme_stylebox_override("panel", base_sb))

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.anchor_right = 1; content.anchor_bottom = 1
	content.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(content)

	var icon_row := HBoxContainer.new()
	icon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(icon_row)

	var icon_lbl := Label.new()
	icon_lbl.text = loc["icon"]
	icon_lbl.add_theme_font_size_override("font_size", 22)
	icon_row.add_child(icon_lbl)

	if not authored_real:
		var lock_lbl := Label.new()
		lock_lbl.text = " 🔒"
		lock_lbl.add_theme_font_size_override("font_size", 16)
		lock_lbl.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
		icon_row.add_child(lock_lbl)
	elif forced_disabled:
		var wait_lbl := Label.new()
		wait_lbl.text = " ⏳"
		wait_lbl.add_theme_font_size_override("font_size", 16)
		wait_lbl.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
		icon_row.add_child(wait_lbl)

	var title_lbl := Label.new()
	title_lbl.text = loc["title"]
	title_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBHEADING)
	title_lbl.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY if clickable else UiTheme.TEXT_MUTED)
	content.add_child(title_lbl)

	var desc_lbl := Label.new()
	if not authored_real:
		desc_lbl.text = "not yet built"
	elif forced_disabled:
		desc_lbl.text = forced_reason
	else:
		desc_lbl.text = loc["desc"]
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc_lbl.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	desc_lbl.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY if clickable else UiTheme.TEXT_MUTED)
	content.add_child(desc_lbl)

	return panel


## Explicit grid focus neighbours (docs/ACCESSIBILITY.md #1 pattern, reused from stable_ui.gd's
## roster-list wiring) rather than trusting automatic spatial search across a grid that mixes
## real, locked and temporarily-disabled cards.
func _wire_grid_focus(columns: int) -> void:
	var n := loc_buttons.size()
	for i in range(n):
		var btn: Button = loc_buttons[i].get_child(0)
		if i % columns != 0:
			btn.focus_neighbor_left = btn.get_path_to(loc_buttons[i - 1].get_child(0))
		if i % columns != columns - 1 and i + 1 < n:
			btn.focus_neighbor_right = btn.get_path_to(loc_buttons[i + 1].get_child(0))
		if i - columns >= 0:
			btn.focus_neighbor_top = btn.get_path_to(loc_buttons[i - columns].get_child(0))
		if i + columns < n:
			btn.focus_neighbor_bottom = btn.get_path_to(loc_buttons[i + columns].get_child(0))


## ⚠️ THERE MUST BE EXACTLY ONE WEEK. This used to call `Career.advance_week(1)` and nothing else,
## while the Stable's Advance Week ran the real tick (`WeekPlan.advance()` — training, feeding,
## stamina, ageing, the food-price reroll, the freezer's rent). Two buttons named for the same
## action did two different things, and the cheap one was the one on the hub screen: a player who
## planned a week of drills in the Stable, walked back to the Town and pressed End Week burned the
## week, paid nothing, trained nothing — and left the plan sitting in `WeekPlan.plans` to be spent
## against a LATER week instead. Both buttons now run the same tick and land on the same feeding
## screen; this one only falls back to bumping the counter when there is no stable to tick.
func _on_end_week() -> void:
	if not has_node("/root/Career"):
		return
	if not has_node("/root/Roster") or Roster.monsters.is_empty():
		# Nothing to feed, train or age — an empty stable still lets the clock run so the Market
		# restocks, which is the one reason to end a week before owning anything.
		Career.advance_week(1)
		_autosave()
		_refresh_header_text()
		return
	var report: Dictionary = WeekPlan.advance(Roster.monsters)
	WeekPlan.set_meta("last_report", report)
	_autosave()
	get_tree().change_scene_to_file("res://scenes/feeding.tscn")


## ⚠️ THE GAME NEVER SAVED. `SaveGame.save_game()` was called from NOWHERE in the whole project —
## `title_ui.gd` read `has_save()` and `load_game()`, so Continue existed, was permanently
## disabled, and every career died with the process. The Town is the natural checkpoint: it is the
## hub every other screen returns to, so autosaving on arrival and on the week turning covers the
## market, the shop, the lab, the breeding ranch and the training week without any of those
## screens needing to know a save format exists.
func _autosave() -> void:
	if has_node("/root/SaveGame"):
		SaveGame.save_game()
