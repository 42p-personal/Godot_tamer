## THE READ — pre-battle tactics screen. This IS the game: the player never intervenes once a
## fight starts (CLAUDE.md's vision section), so every scrap of skill expression has to live here,
## set BEFORE the "Commit and fight" button, informed by what scouting reveals about the rival.
##
## Self-contained, like stable_ui.gd/battle_ui.gd: builds its own demo team (Roster.monsters) and
## scouted rival (Roster.make_rival_team), so it runs standalone with no prior screen required.
##
## UI is built entirely in code — same reasoning as stable_ui.gd: the roster and its orders are
## inherently dynamic, so a hand-authored scene tree would just be a template this script
## overwrites on the first frame.
extends Control

const TacticsScript = preload("res://scripts/tactics.gd")
const DeploymentBoardScript = preload("res://scripts/ui/deployment_board.gd")
## ⚠️ THE CLAIM TEXT LIVES IN THE SCREEN THAT HAS TO ANSWER IT. `report_ui.gd:build_read()` is
## the single generator for both bookends of a fight (`UX_LEGIBILITY.md` §1 rule 1) — this screen
## states the claims, that screen grades the SAME strings. Preloaded for its statics only; no
## instance of the report is ever made here.
const ReadScript = preload("res://scripts/ui/report_ui.gd")
const UiTheme = preload("res://scripts/ui/theme.gd")

const TEAM_SIZE := 5

var team_a: Array = []            # Array[MonsterInstance] — the player's fielded team
var team_b: Array = []            # Array[MonsterInstance] — the scouted rival team
var team_a_plan: Dictionary = {}  # TEAM PLAN, see tactics.gd — mutated live by the selectors below
var team_b_plan: Dictionary = {}  # built once from the rival's gameplan, never edited by the player
var orders_a: Dictionary = {}     # MonsterInstance -> per-monster orders dict
var orders_b: Dictionary = {}     # built once from the rival's gameplan
var gameplan_id: String = ""

var rival_rows: Array = []        # [{"panel": PanelContainer, "monster": <MonsterInstance>, "accent": Color}]
var deployment_board: Control     # DeploymentBoard instance — untyped, see BUILD_CONTRACT §4 on bare class_name refs
var mark_hint_label: Label
var read_box: VBoxContainer      # "YOUR READ" — the claims this fight will be graded on
var commit_btn: Button
var commit_status_label: Label
var committed: bool = false
var _interactive: Array = []      # every control that must freeze once orders are committed
var _cup                          # /root/CupRun if a live tournament round is in progress, else null


func _ready() -> void:
	_cup = get_node_or_null("/root/CupRun")
	if _cup != null and _cup.active:
		# ⚠️ LIVE TOURNAMENT ROUND — the fielded team and its opponent are CupRun's, not this
		# screen's own standalone demo pair. `reset_for_battle()` mirrors `career.gd:
		# enter_league_tournament()`'s per-match reset, since each cup round is an independent
		# fight (HP/MP/cooldowns must not carry over from the previous round).
		## ⚠️ `Roster.fielded_team()`, NOT `monsters.slice()` — a retiree cannot compete
		## (`roster.gd:126`, and now `roster.gd:fieldable()` which is the one place that says so).
		## Slicing the barn from the front used to put an aged-out body on the sheet, and because
		## this screen slices FROM THE FRONT it did it preferentially: the oldest monsters sit
		## earliest in the barn, so the retirees were the first bodies picked.
		team_a = Roster.fielded_team(_cup.team_size)
		for m in team_a:
			m.reset_for_battle()
		team_b = _cup.current_rival_team()
	else:
		team_a = Roster.fielded_team(TEAM_SIZE)
		team_b = Roster.make_rival_team(team_a.size(), 0.3)
	## ⚠️ THE CUP'S OWN ARCHETYPE WINS OVER THE SPECIES HASH. `gameplan_for()` derives a plan from
	## the opposing species NAMES — fine for a standalone demo pair, wrong for a drawn cup round,
	## where the team was BUILT to a class pattern by `Career.make_cup_field()`. Deriving it again
	## here would field a focus-fire roster fighting a wall's plan, which is precisely the "the
	## scouting line is a lie" failure the archetypes exist to end.
	var entry: Dictionary = _cup.current_round_entry() if (_cup != null and _cup.active) else {}
	gameplan_id = String(entry.get("archetype", ""))
	if gameplan_id == "":
		gameplan_id = TacticsScript.gameplan_for(team_b.map(func(m): return m.species_name))
	team_b_plan = TacticsScript.team_plan_for_gameplan(gameplan_id, team_a)
	orders_b = TacticsScript.orders_for_gameplan(gameplan_id, team_b)

	_build_ui()
	_refresh_mark_hint()
	_refresh_read()


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
	title.text = "The Read"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35))
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "You never intervene once the fight starts. Set your team's orders now, informed by what you've scouted — then watch how the read plays out."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD
	subtitle.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	vbox.add_child(subtitle)

	if _cup != null and _cup.active:
		var round_lbl := Label.new()
		round_lbl.text = "%s Cup — round %d of %d  ·  %d won so far" % [
			Career.league_at(_cup.league_idx).get("name", "?"), _cup.current_round + 1, _cup.rival_count, _cup.wins]
		round_lbl.add_theme_font_size_override("font_size", 14)
		round_lbl.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35))
		vbox.add_child(round_lbl)

	## ⚠️ THE ROOT SCROLLS NOW, AND THE TWO INNER SCROLLERS ARE GONE — ONE CHANGE, THREE RULES.
	## `UI_LAYOUT_RULES` rule 1 (every screen's root is scrollable) was the one this screen never
	## satisfied: it was laid out as if 1080 were a guarantee, so the moment the per-monster order
	## strip below was given the height it actually needs, the screen CLIPPED (measured: content
	## 1119 against a 1080 viewport). Rule 5 was the other half — the team column and the rival
	## column each carried their own `ScrollContainer`, and three wheel targets stacked in one
	## screen is the frustration that rule names.
	##
	## One outer scroll fixes both: the columns get their real minimum height and the page scrolls
	## if the window cannot hold them, while the inner lists become plain VBoxes that always show
	## every row. And because `bottom` stays OUTSIDE this scroll, the commit rail is pinned — rule 2,
	## on the most important button in the game.
	##
	## ⚠️ `ScrollContainer` STILL EXPANDS A CHILD SMALLER THAN ITSELF, so the columns' existing
	## `SIZE_EXPAND_FILL` behaviour is unchanged when there is room. Verified by capture, not by
	## reading the docs.
	var page_scroll := ScrollContainer.new()
	page_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(page_scroll)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_scroll.add_child(columns)

	_build_team_column(columns)
	_build_rival_column(columns)

	# ── THE COMMIT RAIL ───────────────────────────────────────────────────────────────────────
	#
	# ⚠️ THE MOST IMPORTANT BUTTON IN THE GAME WAS INVISIBLE, AND NOT FOR THE REASON ANYONE GUESSED.
	# `docs/META_UI_DIRECTION.md` C4 flagged that no commit control appears in either capture of this
	# screen at 1152×648 and asked whether it was below the fold. It is NOT below the fold — the
	# whole screen measures exactly one viewport. It was RIGHT-ALIGNED IN THE BOTTOM RAIL, and
	# `TutorialOverlay` is a `layer = 100` CanvasLayer autoload pinned bottom-right on every screen
	# in the game. Cropping the capture at (890..1150, 528..645) shows the guide panel sitting
	# precisely where "Back to the Stable" and "Commit and fight" are drawn. The button was painted
	# and then covered — the same class of failure as the v0.79 z-index bug CLAUDE.md warns about,
	# where every computed-style and hit-test check passes while the screen looks empty.
	#
	# THE FIX HERE IS THE HALF THIS FILE OWNS: the primary action LEADS the rail instead of trailing
	# it. That is also the right hierarchy independently of the overlay — the commit is the reason
	# the screen exists and "Back to the Stable" is an escape hatch — so it is not a workaround
	# waiting on someone else's file. ⚠️ The overlay itself still needs fixing (it overlaps a pinned
	# rail on five other screens and shows a food hint on the title screen); that is flagged for the
	# integrator in the round report, and it is NOT this file's to change.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	vbox.add_child(bottom)

	commit_btn = Button.new()
	commit_btn.text = "COMMIT AND FIGHT  —  no take-backs"
	commit_btn.custom_minimum_size = Vector2(300, 44)
	commit_btn.focus_mode = Control.FOCUS_ALL
	commit_btn.tooltip_text = "Locks these orders. You cannot intervene once the fight starts — the report will grade exactly the claims listed under YOUR READ."
	for state in ["normal", "hover", "pressed", "disabled"]:
		commit_btn.add_theme_stylebox_override(state, UiTheme.button_stylebox("primary", state))
	commit_btn.add_theme_stylebox_override("focus", UiTheme.button_stylebox("primary", "focus"))
	commit_btn.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	commit_btn.pressed.connect(_on_commit)
	bottom.add_child(commit_btn)

	var back_btn := Button.new()
	back_btn.text = "Back to the Stable"
	back_btn.custom_minimum_size = Vector2(0, 44)
	back_btn.focus_mode = Control.FOCUS_ALL
	back_btn.pressed.connect(func():
		if _cup != null and _cup.active:
			_cup.cancel()
		get_tree().change_scene_to_file("res://scenes/stable.tscn"))
	bottom.add_child(back_btn)
	_interactive.append(back_btn)

	commit_status_label = Label.new()
	commit_status_label.text = "Orders are live until you commit."
	commit_status_label.add_theme_font_size_override("font_size", 12)
	commit_status_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.7))
	commit_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	commit_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(commit_status_label)

	## ⚠️ THE FIELDING RULE HAS TO BE SAYABLE HERE TOO, NOT JUST AT SIGN-UP. `tournament_ui.gd`
	## refuses entry when nobody can be fielded, so the ONLY ways to arrive here with an empty sheet
	## are a save resumed mid-cup whose last body retired on the road, or this screen run standalone
	## with an empty barn. Both used to reach "Commit and fight" and hand `BattleSim` a side with no
	## units. A disabled button with no explanation is `UI_LAYOUT_RULES.md` rule 2's forbidden case,
	## so it carries `Roster.entry_block_reason()` — the same sentence the sign-up screen shows,
	## from the same function.
	if team_a.is_empty():
		commit_btn.disabled = true
		commit_status_label.text = Roster.entry_block_reason(1)
		commit_status_label.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35))
		commit_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


# ── THE READ — what you are committing TO ─────────────────────────────────────────────────────
#
# ⚠️ THIS IS THE HALF OF "COMMIT, THEN OBSERVE" THE SCREEN WAS MISSING. Until now the player set
# seven abstract knobs and pressed a button; nothing on this screen said what those knobs
# PREDICTED, so there was nothing for the report to be right or wrong about. `FUN_ADDITIONS.md`
# §1 is explicit that this is the single highest-value addition available: "you cannot feel
# vindicated by an outcome you never committed to in words", and "a claim tells the player where
# to look" — a 5v5 with a declared claim in it has a protagonist.
#
# ⚠️ THE CLAIMS ARE GENERATED FROM THE ORDERS, NEVER AUTHORED HERE. They update live as the
# player changes anything, so the panel is a mirror of the plan and cannot drift from it — and
# `report_ui.gd` grades the exact strings this panel showed, because both come out of the same
# `build_read()`.

func _build_read_panel(parent: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.13, 0.12)
	sb.border_color = Color(0.5, 0.85, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10; sb.content_margin_right = 10
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	read_box = VBoxContainer.new()
	read_box.add_theme_constant_override("separation", 3)
	panel.add_child(read_box)


## Rebuilt from scratch on every order change — three claims at most, so this is cheap and there
## is no partial-update path that can leave a stale sentence on screen.
func _refresh_read() -> void:
	if read_box == null:
		return
	for c in read_box.get_children():
		c.queue_free()

	var header := Label.new()
	header.text = "YOUR READ — the report will grade exactly these"
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", Color(0.5, 0.85, 0.6))
	read_box.add_child(header)

	var claims: Array = ReadScript.build_read(team_a_plan, orders_a, team_a, team_b)
	# ⚠️ THIS IS A GUARD, NOT THE "NO ORDERS" CASE, AND SAYING SO MATTERS. `build_read()` always
	# produces at least the SHAPE claim, because a formation is a real placement the player has
	# made whether or not they opened a dropdown — so the empty list only happens with an empty
	# roster. Copy that read "you have given no order" would therefore have been unreachable text
	# describing a state that cannot occur, which is how a screen ends up documenting a design
	# nobody built.
	if claims.is_empty():
		_wrapped_row(read_box,
			"No team is fielded yet, so there is nothing to claim.", 12, Color(0.75, 0.7, 0.5))
		return

	for c in claims:
		var claim: Dictionary = c
		var line := Label.new()
		line.text = "· %s" % str(claim.get("claim", ""))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD
		line.add_theme_font_size_override("font_size", 14)
		line.add_theme_color_override("font_color", Color(0.88, 0.92, 0.88))
		read_box.add_child(line)

		var gradeable: bool = bool(claim.get("gradeable", true))
		var sub := Label.new()
		sub.text = "    %s" % (str(claim.get("test", "")) if gradeable
			else "⚠ NOT SIMULATED YET — %s, so this claim cannot be graded." % str(claim.get("why_ungradeable", "")))
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD
		sub.add_theme_font_size_override("font_size", 11)
		sub.add_theme_color_override("font_color", Color(0.6, 0.62, 0.65) if gradeable else Color(0.9, 0.65, 0.4))
		read_box.add_child(sub)


# ── Your team ─────────────────────────────────────────────────────────────────────────────────

func _build_team_column(parent: HBoxContainer) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)

	var header := Label.new()
	header.text = "YOUR TEAM — STANDING ORDERS"
	header.add_theme_color_override("font_color", Color(0.4, 0.65, 0.95))
	header.add_theme_font_size_override("font_size", 14)
	col.add_child(header)

	var team_panel := PanelContainer.new()
	var team_sb := StyleBoxFlat.new()
	team_sb.bg_color = Color(0.1, 0.11, 0.15)
	team_sb.set_corner_radius_all(4)
	team_sb.content_margin_left = 10; team_sb.content_margin_right = 10
	team_sb.content_margin_top = 8; team_sb.content_margin_bottom = 8
	team_panel.add_theme_stylebox_override("panel", team_sb)
	col.add_child(team_panel)

	var team_controls := VBoxContainer.new()
	team_controls.add_theme_constant_override("separation", 8)
	team_panel.add_child(team_controls)

	_build_order_selector(team_controls, "Target priority — team default", TacticsScript.TARGET_PRIORITY_INFO, "",
		func(id):
			if id == "":
				team_a_plan.erase("targetPriority")
			else:
				team_a_plan["targetPriority"] = id
			_refresh_mark_hint()
			_refresh_read(),
		true, 260)

	_build_order_selector(team_controls, "Mana policy — team default", TacticsScript.MANA_POLICY_INFO, "normal",
		func(id): team_a_plan["manaPolicy"] = id,
		true, 260)

	_build_order_selector(team_controls, "Positional intent — team default", TacticsScript.POSITIONAL_INTENT_INFO, "hold",
		func(id):
			team_a_plan["positionalIntent"] = id
			if deployment_board != null:
				deployment_board.set_team_default_intent(id)
			_refresh_read(),
		true, 260)

	# ⚠️ "Formation" is no longer a manual dropdown — it is DERIVED, live, from the deployment
	# board below (docs/UX_DEPLOYMENT.md §8: "replacing the current Formation: Tight/Loose
	# dropdown"). `team_a_plan["formation"]` still ends up holding a plain "tight"/"loose" string,
	# so `tactics.gd`'s already-wired `aura_coverage`/`aoe_coverage` and `spatial_ai.gd`'s leash
	# read keep working unmodified — the board just computes that bucket from real placement
	# instead of asking the player to pick it blind.
	deployment_board = DeploymentBoardScript.new()
	deployment_board.setup(team_a, TEAM_SIZE)
	team_a_plan["formation"] = deployment_board.formation_bucket()
	deployment_board.changed.connect(_on_board_changed)
	team_controls.add_child(deployment_board)
	# NOT appended to `_interactive` — that array assumes every entry is a BaseButton with a
	# `.disabled` property (see `_on_commit`), and the board is a container. It gets its own
	# `set_locked()` call at commit time instead.

	## ⚠️ THIS SCROLLER SHOWED 2 OF 3 MONSTERS AND THAT IS A LIE ABOUT THE SHEET.
	## `UI_LAYOUT_RULES` rule 5 permits a nested scroll when the pane is genuinely independent, and
	## a per-monster order strip beside a formation board qualifies — but it was given whatever
	## height was left over, which at 1152×648 was two rows out of three (`META_UI_DIRECTION.md`
	## §1.11). A player who cannot see their third monster's row does not know it has orders at all.
	## The floor is sized to the roster (capped at five, the largest team any league fields), so the
	## strip asks for the room it needs and only scrolls past the cap.
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(list)
	for m in team_a:
		_add_team_monster_row(list, m)


func _add_team_monster_row(parent: VBoxContainer, m) -> void:
	orders_a[m] = {"temperament": "balanced"}

	var accent := Color(0.4, 0.65, 0.95)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.13, 0.17)
	sb.border_color = accent
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 6; sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)
	parent.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	row.add_child(_creature_visual(m.species_id, accent))

	var info_col := VBoxContainer.new()
	info_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_col.custom_minimum_size = Vector2(120, 0)
	row.add_child(info_col)
	var name_lbl := Label.new()
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.text = m.species_name
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
	info_col.add_child(name_lbl)
	var class_lbl := Label.new()
	class_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	class_lbl.text = "%s · %s" % [m.class_name_, m.role]
	class_lbl.add_theme_font_size_override("font_size", 11)
	class_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.68))
	info_col.add_child(class_lbl)

	_build_order_selector(row, "Temperament", TacticsScript.TEMPERAMENT_INFO, "balanced",
		func(id):
			orders_a[m]["temperament"] = id
			_refresh_read(),
		false, 150)

	# A THIRD state ("Team default") that isn't in Tactics.TARGET_PRIORITY_INFO — inheriting the
	# team plan means NOT WRITING the key at all, which is different from explicitly choosing ""
	# (force lowest-HP even if the team plan says otherwise). Prepending it here, in the UI, keeps
	# that inherit/override distinction out of the engine-facing vocabulary in tactics.gd.
	var per_monster_priority: Array = [{"id": "__inherit__", "icon": "↕", "name": "Team default", "desc": ""}] + TacticsScript.TARGET_PRIORITY_INFO
	_build_order_selector(row, "Target", per_monster_priority, "__inherit__",
		func(id):
			if id == "__inherit__":
				orders_a[m].erase("targetPriority")
			else:
				orders_a[m]["targetPriority"] = id
			_refresh_mark_hint()
			_refresh_read(),
		false, 170)


# ── Scouted rival ─────────────────────────────────────────────────────────────────────────────

func _build_rival_column(parent: HBoxContainer) -> void:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)

	var header := Label.new()
	header.text = "SCOUTED — RIVAL TEAM"
	header.add_theme_color_override("font_color", Color(0.9, 0.45, 0.4))
	header.add_theme_font_size_override("font_size", 14)
	col.add_child(header)

	var gp: Dictionary = TacticsScript.GAMEPLANS.get(gameplan_id, {})
	var gp_panel := PanelContainer.new()
	var gp_sb := StyleBoxFlat.new()
	gp_sb.bg_color = Color(0.16, 0.12, 0.1)
	gp_sb.border_color = Color(0.85, 0.6, 0.3)
	gp_sb.set_border_width_all(1)
	gp_sb.set_corner_radius_all(4)
	gp_sb.content_margin_left = 10; gp_sb.content_margin_right = 10
	gp_sb.content_margin_top = 8; gp_sb.content_margin_bottom = 8
	gp_panel.add_theme_stylebox_override("panel", gp_sb)
	col.add_child(gp_panel)

	var gp_box := VBoxContainer.new()
	gp_box.add_theme_constant_override("separation", 4)
	gp_panel.add_child(gp_box)
	# ⚠️ WHO, EXACTLY. `_cup.current_round_entry()` carries the drawn field's own `label` — "Round 2
	# of the draw", or the titleholder by name for the last round — and this screen never said it.
	# A player arriving here from the sign-up screen scouted a NAMED opponent per round; landing on
	# a panel that says only "Gameplan: Bulwark" loses the identity between the two screens.
	var entry2: Dictionary = _cup.current_round_entry() if (_cup != null and _cup.active) else {}
	if not entry2.is_empty():
		var who := Label.new()
		who.text = "%s%s" % ["♛  " if bool(entry2.get("champion", false)) else "",
			str(entry2.get("label", ""))]
		who.autowrap_mode = TextServer.AUTOWRAP_WORD
		who.add_theme_font_size_override("font_size", 15)
		who.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5) if bool(entry2.get("champion", false)) else Color(0.85, 0.85, 0.9))
		gp_box.add_child(who)

	var gp_title := Label.new()
	gp_title.text = "%s  Gameplan: %s" % [gp.get("icon", "?"), gp.get("name", "Unknown")]
	gp_title.add_theme_font_size_override("font_size", 15)
	gp_title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.4))
	gp_box.add_child(gp_title)
	_wrapped_row(gp_box, gp.get("tell", ""), 12, Color(0.8, 0.8, 0.85))
	_wrapped_row(gp_box, "Win condition: %s" % gp.get("winCon", ""), 12, Color(0.7, 0.75, 0.7))
	# ⚠️ `signature` WAS AUTHORED FOR ALL SIX ARCHETYPES AND RENDERED BY NOTHING. `grep signature
	# scripts/ui/` returned no hits before this line: six one-sentence descriptions of *what the
	# fight will LOOK like* — "the highest damage-per-second of any archetype, and the shortest
	# fights", "far more landed statuses than any other archetype" — sitting unread in
	# `tactics.gd:GAMEPLANS`. That is the project's signature failure (authored and unreached, 11+
	# instances) landing on the one screen whose entire job is telling the player what is coming.
	if str(gp.get("signature", "")) != "":
		_wrapped_row(gp_box, "What it will look like: %s." % str(gp.get("signature", "")),
			12, Color(0.78, 0.76, 0.86))

	# ⚠️ "WAS IT ME OR WAS IT THEM" IS ASKED AFTER THE LOSS AND ANSWERABLE BEFORE IT.
	# `report_ui.gd:_strength_line()` already quotes this exact number in the right-and-lost case —
	# the most instructive result in the game and the one most likely to be misread as unfairness.
	# Quoting it BEFORE the commit is what makes the difference between "the game cheated" and "I
	# knew I was 12% short and gambled". Same function, `ReadScript.roster_power()`, so the two
	# bookends cannot disagree.
	var strength := _strength_row(team_a, team_b)
	if strength != "":
		var s_lbl := Label.new()
		s_lbl.text = strength
		s_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		s_lbl.add_theme_font_size_override("font_size", 12)
		s_lbl.add_theme_color_override("font_color", _strength_colour(team_a, team_b))
		gp_box.add_child(s_lbl)

	gp_box.add_child(HSeparator.new())
	var counter_title := Label.new()
	counter_title.text = "Counter-read"
	counter_title.add_theme_font_size_override("font_size", 12)
	counter_title.add_theme_color_override("font_color", Color(0.5, 0.85, 0.6))
	gp_box.add_child(counter_title)
	_wrapped_row(gp_box, gp.get("counter", ""), 12, Color(0.75, 0.9, 0.78))

	mark_hint_label = Label.new()
	mark_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	mark_hint_label.add_theme_font_size_override("font_size", 12)
	mark_hint_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	mark_hint_label.visible = false
	col.add_child(mark_hint_label)

	## Plain VBox, not a scroller — see the root-scroll ⚠️ in `_build_ui()`. A five-body rival sheet
	## is the largest any league fields, and it must be readable in one look: this is the thing the
	## player is scouting.
	var rival_list := VBoxContainer.new()
	rival_list.add_theme_constant_override("separation", 6)
	rival_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(rival_list)

	for m in team_b:
		_add_rival_row(rival_list, m)

	# ⚠️ THE READ SITS UNDER THE SCOUTING, NOT UNDER THE WHOLE SCREEN, AND THAT IS A MEASURED FIX.
	# Placed full-width below both columns it stole ~130px of height from a shared HBox, and the
	# per-monster order rows — the screen's only per-monster control — collapsed to one visible
	# row inside their scroller (seen in scripts/_probe_read_shot.gd's capture). The rival column
	# has dead space below its five entries and this is also where the claim BELONGS: it is the
	# answer to the gameplan and counter-read directly above it.
	_build_read_panel(col)


func _add_rival_row(parent: VBoxContainer, m) -> void:
	var accent := Color(0.9, 0.45, 0.4)
	var panel := PanelContainer.new()
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# ⚠️ P0 ACCESSIBILITY FIX (docs/ACCESSIBILITY.md §0 #1 / §7) — this panel used to be
	# mouse-only: `gui_input` checked only `InputEventMouseButton`, and `PanelContainer` has no
	# default `focus_mode`, so it was never Tab-reachable and had no keyboard activation at all. A
	# keyboard-only player could not mark a rival for the `manmark` order, i.e. could not complete
	# one of this screen's four tactic axes. Fixed the same way the doc recommends: real keyboard
	# focus plus `ui_accept` (Enter/Space) doing exactly what a click does, with a focus ring drawn
	# independently of the "marked" gold border so the two states never look the same.
	panel.focus_mode = Control.FOCUS_ALL
	panel.focus_entered.connect(func(): _style_rival_panel(panel, accent, team_a_plan.get("markedUnit") == m))
	panel.focus_exited.connect(func(): _style_rival_panel(panel, accent, team_a_plan.get("markedUnit") == m))
	parent.add_child(panel)
	_style_rival_panel(panel, accent, false)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	row.add_child(_creature_visual(m.species_id, accent))

	var info_col := VBoxContainer.new()
	info_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info_col)
	var name_lbl := Label.new()
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.text = m.species_name
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.92, 0.92, 0.95))
	info_col.add_child(name_lbl)
	var class_lbl := Label.new()
	class_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	class_lbl.text = "%s · %s" % [m.class_name_, m.role]
	class_lbl.add_theme_font_size_override("font_size", 11)
	class_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.68))
	info_col.add_child(class_lbl)

	panel.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			panel.grab_focus()
			_on_mark_rival(m)
		elif event.is_action_pressed("ui_accept"):
			_on_mark_rival(m)
			panel.accept_event()
	)
	rival_rows.append({"panel": panel, "monster": m, "accent": accent})


func _style_rival_panel(panel: PanelContainer, accent: Color, marked: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.22, 0.17, 0.08) if marked else Color(0.13, 0.13, 0.17)
	sb.border_color = Color(0.95, 0.8, 0.25) if marked else accent
	sb.set_border_width_all(3 if marked else 1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 6; sb.content_margin_bottom = 6
	# SC 2.4.7 Focus Visible — a shadow glow independent of the "marked" gold border, so keyboard
	# focus and the man-mark selection stay visually distinguishable from each other (a focused-
	# but-unmarked row and a marked-but-unfocused row must never look the same).
	if panel.has_focus():
		sb.shadow_color = Color(0.55, 0.85, 1.0, 0.75)
		sb.shadow_size = 4
	panel.add_theme_stylebox_override("panel", sb)


## Syncs the board's live state (spread bucket + per-monster positional-intent overrides) into
## `team_a_plan`/`orders_a` so both the existing engine-consumed `formation` key and the
## forward-compatible `positionalIntent` field stay current whenever the player drags a chip.
func _on_board_changed() -> void:
	if deployment_board == null:
		return
	team_a_plan["formation"] = deployment_board.formation_bucket()
	var intents: Dictionary = deployment_board.current_intents()
	var guard_targets: Dictionary = deployment_board.current_guard_targets()
	for m in team_a:
		if not orders_a.has(m):
			orders_a[m] = {}
		if intents.has(m):
			orders_a[m]["positionalIntent"] = intents[m]
		else:
			orders_a[m].erase("positionalIntent")
		# `guardedAlly` is the producer `monster_tree.gd::_positional_guard` was written
		# expecting and never got — only meaningful when the intent itself is "guard".
		if guard_targets.has(m):
			orders_a[m]["guardedAlly"] = guard_targets[m]
		else:
			orders_a[m].erase("guardedAlly")


func _on_mark_rival(m) -> void:
	if committed:
		return
	team_a_plan["markedUnit"] = m
	for entry in rival_rows:
		_style_rival_panel(entry["panel"], entry["accent"], entry["monster"] == m)
	_refresh_mark_hint()
	_refresh_read()


## Informs the read without solving it: tells the player whether "man mark" is actually armed,
## and against whom — but never suggests WHO to mark or whether the choice is good.
func _refresh_mark_hint() -> void:
	if mark_hint_label == null:
		return
	var wants_mark: bool = team_a_plan.get("targetPriority", "") == "manmark"
	if not wants_mark:
		for m in orders_a:
			if orders_a[m].get("targetPriority", "") == "manmark":
				wants_mark = true
				break
	if not wants_mark:
		mark_hint_label.visible = false
		return
	var marked = team_a_plan.get("markedUnit")
	if marked == null:
		mark_hint_label.text = "Man mark is set but nobody's been marked yet — click a rival monster below to choose the target."
	else:
		mark_hint_label.text = "Marked: %s — your man-mark order hunts it." % marked.species_name
	mark_hint_label.visible = true


# ── Commit ────────────────────────────────────────────────────────────────────────────────────

func _on_commit() -> void:
	if committed:
		return
	committed = true
	_on_board_changed()  # final sync before the plan is frozen
	var deploy_positions := {}
	for p in deployment_board.current_placements():
		deploy_positions[p["monster"]] = p["pos"]
	TacticsScript.commit(team_a_plan, team_b_plan, orders_a, orders_b,
		deploy_positions, deployment_board.current_intents(), team_a, team_b)
	# ⚠️ THE CLAIMS TRAVEL WITH THE PLAN, AS A COPY, ON PURPOSE. `report_ui.gd` could rebuild them
	# from `planA`/`ordersA` (and does, as a fallback for older commits) — but storing the exact
	# strings the player just said yes to means the report grades the SENTENCE THEY READ, not a
	# regenerated equivalent. If the generator ever changes between two builds of a save, the copy
	# is the one that keeps the promise. Written as an extra key rather than through `commit()`'s
	# signature because `tactics.gd` is not this stream's file; the dict already carries
	# caller-added keys (`watch.gd` writes "layout" the same way).
	TacticsScript.committed["read"] = {
		"claims": ReadScript.build_read(team_a_plan, orders_a, team_a, team_b),
		"gameplan": gameplan_id,
	}
	deployment_board.set_locked(true)
	for ctl in _interactive:
		ctl.disabled = true
	commit_btn.disabled = true
	commit_btn.text = "Orders locked in"
	commit_status_label.text = "No take-backs — advancing to the fight."
	var timer := get_tree().create_timer(1.6)
	timer.timeout.connect(func(): get_tree().change_scene_to_file("res://scenes/arena3d.tscn"))


# ── Shared small builders ────────────────────────────────────────────────────────────────────

## One order row: a heading, an OptionButton populated from `info_list` (each entry
## {id, icon, name, desc}), and — unless `show_desc` is false — a live description label that
## updates on selection so every option states what it DOES, not just what it's called.
func _build_order_selector(parent: Control, heading: String, info_list: Array, default_id: String,
		on_change: Callable, show_desc: bool = true, min_width: int = 200) -> OptionButton:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	parent.add_child(box)

	var heading_lbl := Label.new()
	heading_lbl.text = heading
	heading_lbl.add_theme_font_size_override("font_size", 12)
	heading_lbl.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35))
	box.add_child(heading_lbl)

	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(min_width, 0)
	for entry in info_list:
		opt.add_item("%s %s" % [entry["icon"], entry["name"]])
	box.add_child(opt)

	var desc_lbl: Label = null
	if show_desc:
		desc_lbl = Label.new()
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_lbl.add_theme_font_size_override("font_size", 11)
		desc_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
		box.add_child(desc_lbl)

	var start_idx := 0
	for i in range(info_list.size()):
		if info_list[i]["id"] == default_id:
			start_idx = i
			break
	opt.select(start_idx)
	if desc_lbl != null:
		desc_lbl.text = info_list[start_idx]["desc"]

	opt.item_selected.connect(func(i):
		if desc_lbl != null:
			desc_lbl.text = info_list[i]["desc"]
		on_change.call(info_list[i]["id"])
	)

	_interactive.append(opt)
	return opt


## Creature portrait or a null-safe fallback. `Art.creature_texture()` returns null while art is
## still generating (or for species outside the painted set) — never crash, draw the team-colour
## swatch instead so the row still reads at a glance.
func _creature_visual(species_id: String, accent: Color) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(40, 40)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex: Texture2D = Art.creature_texture(species_id)
	if tex != null:
		var tex_rect := TextureRect.new()
		tex_rect.texture = tex
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex_rect.anchor_right = 1; tex_rect.anchor_bottom = 1
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(tex_rect)
	else:
		var swatch := ColorRect.new()
		swatch.color = accent
		swatch.anchor_right = 1; swatch.anchor_bottom = 1
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(swatch)
	return box


## The trained-stat gap between the two sheets, in the report's own words and off the report's own
## function. ⚠️ NOT A POWER RATING AND IT MUST NOT READ AS ONE — it is the flat sum of six trained
## stats, which is exactly the thing the ladder's `field_fill` dial moves and the one number a
## player can act on by training. It does not know about kits, orders or the archetype correction
## (`Tactics.FILL_MULT`), and the copy says so rather than implying a prediction.
func _strength_row(a: Array, b: Array) -> String:
	var pa: float = ReadScript.roster_power(a)
	var pb: float = ReadScript.roster_power(b)
	if pa <= 0.0 or pb <= 0.0:
		return ""
	var pct: float = (pb / pa - 1.0) * 100.0
	if pct >= 8.0:
		return "Trained stat: they carry %.0f%% more than you. Orders will not close that on their own — a right read here buys you a close fight, not a free one." % pct
	if pct <= -8.0:
		return "Trained stat: you carry %.0f%% more than they do. This is yours to lose on orders." % absf(pct)
	return "Trained stat: within %.0f%% of each other. The rosters will not decide this — the orders will." % absf(pct)


func _strength_colour(a: Array, b: Array) -> Color:
	var pa: float = ReadScript.roster_power(a)
	var pb: float = ReadScript.roster_power(b)
	if pa <= 0.0 or pb <= 0.0:
		return Color(0.7, 0.7, 0.75)
	var pct: float = (pb / pa - 1.0) * 100.0
	if pct >= 8.0:
		return Color(0.95, 0.6, 0.45)
	if pct <= -8.0:
		return Color(0.55, 0.88, 0.6)
	return Color(0.85, 0.85, 0.9)


func _wrapped_row(parent: Node, text: String, font_size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
