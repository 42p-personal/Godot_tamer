## THE TITLE SCREEN — the game's front door, and the screen that has to answer ONE question for a
## returning player: *what am I going back to?* New Career / Continue / Watch / Quit, over the
## generated key art. Falls back to a Guild Colours gradient + wordmark when the art hasn't landed
## yet (see Art.title_texture()'s documented null contract) — this screen must look deliberate and
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
##
## ── ⚠️ WHY THE CAREER CARD READS THE SAVE FILE AND NOT `Career` (round 20) ────────────────────
## `Continue` used to be a bare grey button that said nothing about the 300-week career behind it.
## The obvious fix — call `ending_ui.gd`'s `Pace.snapshot()`, the ONE pace adapter, the way
## `town_ui.gd` and `report_ui.gd` do — IS WRONG HERE, AND WOULD HAVE SHIPPED A RULE-(1) LIE.
##
## Those two screens run INSIDE a loaded career, so `Career` is the save. This screen runs BEFORE
## the load: on a cold boot `Career` holds `reset_new_game()`'s defaults — week 0, Wood, 500 gold —
## while `user://save.json` holds week 372 at Tamers Apex. A snapshot here would have printed a
## confident, precisely-formatted description of a career that does not exist, under a button
## labelled Continue. That is exactly the 400-vs-540 failure this project has now found in three
## venues, in the one place where it would be the first thing a player ever reads.
##
## So the card reads the FILE the Continue button is about to load, and reads only what that file
## literally stores (`save_game.gd:_serialize_career`) — week, league index, gold, roster/freezer
## counts, `leaguesWon`, `wonGame`/`wonWeek`. It DERIVES NOTHING: no pace, no par, no margin, no
## grade. Those all read live `Career` state (`career.gd:pace_margin_weeks()` needs
## `frontier_since_week` and `league_index` as the run's CURRENT values), so the honest place to
## show them is the town and the ending, where the career is loaded — and they already do.
##
## ⚠️ AND THE CARD MUST NEVER GROW A ROW. `UI_LAYOUT_RULES` R1 exempts this screen from the
## scrollable-root rule on one warrant: its content is authored and cannot grow from game state.
## Reading a save is game state, so the exemption survives only because every fact below is
## SUMMARISED into a fixed three lines — counts, never a list. Do not add a per-monster row here;
## that lapses the exemption and the screen needs a ScrollContainer.
extends Control

const UiTheme = preload("res://scripts/ui/theme.gd")

## ⚠️ THE ONE DUPLICATED CONSTANT IN THIS FILE, AND IT IS DUPLICATED ON PURPOSE. `save_game.gd`
## owns the path; this screen only ever READS the file, never writes it, and preloading an autoload
## purely for a string is worse than a second copy of a literal that has never changed. If a third
## reader appears, that is the signal to add `SaveGame.peek()` — see the integrator note in the
## round-20 report.
const SAVE_PATH := "user://save.json"

var continue_btn: Button


func _ready() -> void:
	self.theme = UiTheme.base_theme()
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
	## ⚠️ DERIVED FROM THE TOKEN, NOT TYPED AS A LITERAL — and it is still off the published scale,
	## which is stated rather than hidden. `UiTheme.SIZE_DISPLAY` is 32, and 32 is a *panel* display
	## size: at the 1920x1080 base viewport a 1152x648 window scales every label by 0.6, so 32
	## renders at 19px — a caption, not a wordmark, on the best art in the project. This screen and
	## the ending's grade tier are the project's only two poster-register labels, and the honest fix
	## is a `SIZE_POSTER` token in theme.gd (integrator note, round 20) rather than a keyboard
	## number here. Until that lands: one multiple of one token, so a probe reading 64 can see a
	## decision and not a fifth invented size.
	word.add_theme_font_size_override("font_size", UiTheme.SIZE_DISPLAY * 2)
	word.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY)
	_ink_over_art(word)
	vbox.add_child(word)

	var tagline := Label.new()
	tagline.text = "You run the stable. The stable fights."
	tagline.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	# GOLD, not Art.team_colour() — team colour is a semantic "who plays for whom" channel
	# (art.gd), and the title screen has no team context to attach it to. This is the same warm
	# gold, now taken from the shared token instead of a second hand-picked copy of it.
	tagline.add_theme_color_override("font_color", UiTheme.GOLD)
	_ink_over_art(tagline)
	vbox.add_child(tagline)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, UiTheme.SPACE_XL)
	vbox.add_child(spacer)

	var saved: Dictionary = _peek_save()

	var card := _career_card(saved)
	if card != null:
		vbox.add_child(card)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, UiTheme.SPACE_MD)
		vbox.add_child(gap)

	var menu := VBoxContainer.new()
	menu.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	menu.custom_minimum_size = Vector2(340, 0)
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(menu)

	## ⚠️ THE RETURNING PLAYER'S BUTTON COMES FIRST AND IS THE PRIMARY ONE. Four identical grey
	## plates made the two most different actions in the game — resume a 300-week career, and
	## delete-by-omission and start again — look like the same decision. Order and emphasis follow
	## the save: with one, Continue leads; without one, New Career leads and Continue says why it
	## cannot.
	var has_save: bool = not saved.is_empty()

	continue_btn = _menu_button(_continue_label(saved), has_save)
	continue_btn.pressed.connect(_on_continue)
	var new_btn := _menu_button("New Career", not has_save)
	new_btn.pressed.connect(_on_new_career)

	if has_save:
		menu.add_child(continue_btn)
		menu.add_child(new_btn)
	else:
		menu.add_child(new_btn)
		menu.add_child(continue_btn)
		# R3: a dead control states its reason IN THE LABEL, not only in a tooltip — a keyboard
		# user never hovers (UI_LAYOUT_RULES R3, shop_ui.gd is the house example).
		UiTheme.disable_with_reason(continue_btn, "no career saved yet", true)

	# ⚠️ A DEV COMMAND IS NOT A FEATURE. The first version of this shipped as a
	# `godot --path . scenes/watch.tscn` line in chat, which is not something anyone should have to
	# keep, remember or type to look at their own game. If a thing is worth watching it belongs on
	# the screen the game opens on.
	var watch_btn := _menu_button("Watch a Battle", false)
	watch_btn.tooltip_text = "A 5v5 exhibition on the four_pillar arena — no career, no saving."
	watch_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/watch.tscn"))
	menu.add_child(watch_btn)

	var quit_btn := _menu_button("Quit", false)
	quit_btn.pressed.connect(func(): get_tree().quit())
	menu.add_child(quit_btn)

	# Keyboard first: focus lands on the action the save implies, so `ui_accept` alone resumes a
	# career or starts one (docs/ACCESSIBILITY.md — a mouse-only front door locked keyboard users
	# out of the game entirely once already).
	var first: Button = continue_btn if has_save else new_btn
	first.call_deferred("grab_focus")


## Every menu button, one shape. `primary` is the gold call-to-action register from theme.gd —
## exactly the styling the ending's "Back to the Town" already uses, so the two screens that
## bookend the game agree about what a primary action looks like.
func _menu_button(label: String, primary: bool) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 44)
	btn.focus_mode = Control.FOCUS_ALL
	btn.clip_text = true
	var kind: String = "primary" if primary else "secondary"
	for state in ["normal", "hover", "pressed", "disabled"]:
		btn.add_theme_stylebox_override(state, UiTheme.button_stylebox(kind, state))
	btn.add_theme_stylebox_override("focus", UiTheme.button_stylebox(kind, "focus"))
	return btn


## The identity on the CONTROL, not only in a panel above it — "Continue — Bronze, week 130" is
## the house standard ("Recruit · 173g · Barn full"): the reason and the subject live in the label.
func _continue_label(save: Dictionary) -> String:
	if save.is_empty():
		return "Continue"
	return "Continue — %s, week %d" % [_league_name(int(save["leagueIndex"])), int(save["week"])]


## THE CAREER CARD — three fixed lines, or nothing at all. Returns null when there is no save,
## because an empty card is a region that failed to load as far as the player can tell
## (`UiTheme.empty_state` exists for regions that must persist; a front door does not).
##
## ⚠️ EVERY NUMBER HERE IS A FIELD OF `user://save.json`, READ BACK VERBATIM. Nothing is computed
## from another number, and nothing is read from the live `Career` except the league NAME, which is
## the static ladder table (`career.gd:_load_ladder()` fills it at `_ready`, from data.json — it is
## not run state and a cold boot has it).
func _career_card(save: Dictionary) -> Control:
	if save.is_empty():
		return null

	var panel := PanelContainer.new()
	var sb := UiTheme.panel_style("raised", UiTheme.GOLD)
	sb.bg_color = Color(UiTheme.PANEL.r, UiTheme.PANEL.g, UiTheme.PANEL.b, 0.88)
	sb.content_margin_left = UiTheme.SPACE_LG
	sb.content_margin_right = UiTheme.SPACE_LG
	sb.content_margin_top = UiTheme.SPACE_MD
	sb.content_margin_bottom = UiTheme.SPACE_MD
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(340, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)

	var head := Label.new()
	head.text = "%s · week %d" % [_league_name(int(save["leagueIndex"])), int(save["week"])]
	head.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBHEADING)
	head.add_theme_color_override("font_color", UiTheme.GOLD)
	col.add_child(head)

	var barn: int = int(save["monsters"])
	var kept: int = int(save["frozen"])
	var stock := "%d in the barn" % barn
	if kept > 0:
		stock += " · %d preserved" % kept
	stock += " · %d gold" % int(save["gold"])
	col.add_child(_card_line(stock, UiTheme.TEXT_PRIMARY))

	## ⚠️ `rungs` IS `leaguesWon.size()`, THE LENGTH OF THE SAVED ARRAY — never `Career.leagues.size()`.
	## They are the same today; if the ladder ever gains a rung, an old save's array is shorter, and
	## printing "3 of 12" against an array of 11 would be this screen inventing a denominator its own
	## source does not have.
	var titles: int = int(save["titles"])
	var rungs: int = int(save["rungs"])
	var third := "%d titles taken" % titles
	if rungs > 0:
		third = "%d of %d titles taken" % [titles, rungs]
	var third_col: Color = UiTheme.TEXT_SECONDARY
	if bool(save["wonGame"]):
		# The terminal state, in the save's own words. `wonWeek` is what `save_game.gd` v4 added
		# precisely so the week the title landed survives a reload — so it is quoted, not recomputed
		# from `week`, which keeps ticking after the title.
		var ww: int = int(save["wonWeek"])
		third = "Tamers Apex taken" + ("" if ww < 0 else " in week %d" % ww) + " · %s" % third
		third_col = UiTheme.GOLD
	col.add_child(_card_line(third, third_col))

	return panel


func _card_line(text: String, tint: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.clip_text = true
	l.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	l.add_theme_color_override("font_color", tint)
	return l


## A dark outline so the poster type survives ANY key art, painted or regenerated. The scrim above
## is a fixed 40% and the art is not — a bright sunset behind the wordmark is a legibility failure
## the scrim alone cannot promise away. Same treatment `UiTheme.hp_bar()` uses for the same reason.
func _ink_over_art(l: Label) -> void:
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)


## Rung index -> the ladder's own name for it. `Career.leagues` is the static table loaded from
## data.json at autoload `_ready`; it is not run state, so it is correct on a cold boot with no
## save loaded. Degrades to the bare index rather than guessing a name.
func _league_name(idx: int) -> String:
	if not has_node("/root/Career"):
		return "rung %d" % idx
	var leagues: Array = Career.leagues
	if idx < 0 or idx >= leagues.size():
		return "rung %d" % idx
	return str((leagues[idx] as Dictionary).get("name", "rung %d" % idx))


## ⚠️ A READ-ONLY PEEK AT THE FILE `Continue` IS ABOUT TO LOAD. Returns {} for "no usable save" —
## missing, unopenable, unparseable, or missing the `career` block — which is the SAME set of
## conditions `save_game.gd:load_game()` refuses on, so this card cannot promise a career that
## `Continue` will then decline to load. It deliberately does NOT validate the roster the way
## `load_game()` does (a save whose species table moved on is refused there); that check needs
## `GameData` and rebuilding every monster, and the failure path is already honest — `_on_continue`
## falls back to a clean new career and says so.
func _peek_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var root: Dictionary = parsed
	var career = root.get("career")
	if not (career is Dictionary):
		return {}
	var c: Dictionary = career

	var roster_n := 0
	var roster = root.get("roster", [])
	if roster is Array:
		roster_n = (roster as Array).size()
	var frozen_n := 0
	var frozen = root.get("frozen", [])
	if frozen is Array:
		frozen_n = (frozen as Array).size()

	var won: Array = []
	var lw = c.get("leaguesWon", [])
	if lw is Array:
		won = lw
	var titles := 0
	for w in won:
		if bool(w):
			titles += 1

	return {
		"week": maxi(0, int(c.get("week", 0))),
		"leagueIndex": maxi(0, int(c.get("leagueIndex", 0))),
		"gold": int(c.get("gold", 0)),
		"monsters": roster_n,
		"frozen": frozen_n,
		"titles": titles,
		"rungs": won.size(),
		"wonGame": bool(c.get("wonGame", false)),
		"wonWeek": int(c.get("wonWeek", -1)),
	}


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


## Resets the LADDER/run state (league, gold, week, barn capacity) via Career.reset_new_game(),
## AND empties the stable via Roster.reset_to_empty() — together these are the real new-game
## state: week 0, 500 gold, a 2-slot barn, and zero monsters (docs/CORE_LOOP_PORT.md §1). Lands in
## the Town, not the stable — acquiring the first monster is the player's first real decision, and
## that decision is made at the Market, reached from the Town.
##
## ⚠️ IT DOES NOT DELETE THE SAVE FILE, AND THAT IS NOT AN OVERSIGHT — nothing here writes
## `user://save.json`, so the previous career survives on disk until the new one saves over it.
## Deleting it would be a destructive action taken from a button labelled "New Career", with no
## confirmation, on the game's front door.
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
