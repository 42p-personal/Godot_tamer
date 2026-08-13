## TOURNAMENTS — the ladder, which is the spine of the whole game.
##
## `CLAUDE.md`: *"The ladder is the spine. Wood → Tamers Apex must be completable, paced and
## satisfying end to end."* This screen is where that climb actually happens, and until now the
## Stable's "Enter a tournament" button dropped the player onto a tactics screen with no cup
## behind it.
##
## ⚠️ A CUP IS ALL-OR-NOTHING: `career.gd:enter_league_tournament()` promotes only on a SWEEP.
## That is a deliberately hard gate, so this screen must say so BEFORE entry, not after the loss —
## a player who finds out the rule by failing has been cheated of the decision.
##
## ⚠️ YOU MAY ENTER YOUR OWN LEAGUE OR ANY BELOW IT, NEVER ABOVE (`can_enter_league`). Punching
## down pays less: `REWARD_BY_DROP` mirrors React's 100/50/20% `rewardMultiplier`, so farming a
## league you have already cleared is a safety net, not a strategy.
extends Control

const UiTheme = preload("res://scripts/ui/theme.gd")
## ⚠️ THE ARCHETYPE VOCABULARY IS READ FROM ITS OWNER, NOT RESTATED. The ladder board names each
## rung's KIND with the same icon and name `tactics_ui.gd`'s scouting panel and `report_ui.gd`'s
## counter line use — `UX_LEGIBILITY.md` §1 rule 1, one vocabulary, taken literally.
const TacticsScript = preload("res://scripts/tactics.gd")

## Base purse for sweeping a cup at each league, scaling with the ladder. ⚠️ PROPOSED, NOT
## BALANCED — `CLAUDE.md` records that the balance baseline is SUSPENDED for the Godot rebuild,
## so these exist to make the economy *function*, not to be correct. Re-tune at the re-baseline.
const BASE_PURSE := 220
const PURSE_PER_LEAGUE := 140

## ⚠️ ENTRY COSTS GOLD, AND THAT IS THE POINT. Before this, a cup was free to enter, free to lose
## and free to re-enter in the same breath — the difficulty curve could not function as pacing
## because failure cost the player nothing but a click. A fee makes a cup a COMMITMENT you weigh
## against the field you can see, which is what turns "enter" into a decision.
##
## ⚠️ "~14% OF THE PURSE" WAS THE INTENT AND IT IS NOT WHAT THE PLAYER PAYS. The fee is charged on
## every ENTRY; the purse is paid on PLACEMENT, and placement pays 0 for anything below third. A
## real career measured through `_probe_career_arc.tscn` wins 51% of its rounds and 44% of its
## cups outright, so at 30 + 22/league the fees came to **44% of all purse income over a full
## career** — three times the design figure. The arc autopilot ran 151 weeks at Platinum without
## entering a single cup: it could not simultaneously afford the fees, the fifth barn stall and a
## fifth monster, and Platinum is exactly where team size steps to five. That is a fee that stops
## the ladder rather than pricing it.
##
## Halved. It is still a real commitment (a lost Apex run costs 125g against a 1620g purse) and
## still stops free re-entry, but it is sized against the fee a LOSING player actually pays
## rather than the one a winning player notices. ⚠️ Re-measure at the deliberate re-baseline —
## this is one increment against a suspended baseline, judged on "does the ladder complete".
const BASE_FEE := 15
const FEE_PER_LEAGUE := 11

## Punching down pays less — index is how many leagues BELOW your frontier you entered.
const REWARD_BY_DROP := [1.0, 0.5, 0.2]

var _list: VBoxContainer
var _result_box: VBoxContainer
var _header: Label
var _ladder_box: VBoxContainer
var _season_box: VBoxContainer
var _gaps_box: VBoxContainer

## ⚠️ THE PACE MODEL IS READ, NEVER RE-DERIVED. `ending_ui.gd` is the ONE adapter onto
## `Career`'s par curve and the Varra stable's schedule (its own header says so, and `town_ui.gd`
## and `report_ui.gd` both already go through it). The ladder board below draws the rival marker
## from `Pace.par_rung_at_week()` for exactly that reason — a second copy of the schedule here
## would be a screen that can disagree with the ending screen about who is winning.
const Pace = preload("res://scripts/ui/ending_ui.gd")

## ⚠️ THE GAP SENTENCE IS FORMATTED IN ONE PLACE, FOR THE SAME REASON `Pace` EXISTS ABOVE. Round
## 20 put the gap panel on three more screens; the analysis is `Roster.stable_gaps()` and the
## PHRASING is `town_ui.gd:gap_sentence()`. Two screens formatting the same dictionary their own
## way is how one truth becomes two — the failure this file's own `Pace` note describes.
## Structurally it belongs on `UiTheme` beside `monster_card()`; that file was owned by another
## workstream this round, so the move is a note to the integrator, not a silent second copy.
const GapVoice = preload("res://scripts/ui/town_ui.gd")


func _ready() -> void:
	self.theme = UiTheme.base_theme()
	_build()
	_refresh()
	# A cup just fought live (tactics -> arena, round by round via CupRun) lands back here once
	# every round is resolved and `CupRun.finish()` has already applied promotion. Render its
	# result exactly like the old headless path did, then drain it — same "show once" pattern as
	# `ReportScript.pending`.
	var cup := get_node_or_null("/root/CupRun")
	if cup != null and not cup.last_result.is_empty():
		var out: Dictionary = cup.last_result
		cup.last_result = {}
		_show_result(out)
		_refresh()  # league_index may have changed (promotion) — the cup-card list needs it too


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.SURFACE
	bg.anchor_right = 1; bg.anchor_bottom = 1
	add_child(bg)

	var margin := MarginContainer.new()
	margin.anchor_right = 1; margin.anchor_bottom = 1
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, UiTheme.SPACE_XL)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	margin.add_child(page)

	## ⚠️ A MASTHEAD, NOT A PAGE TITLE — this is the one screen in the meta game that is a
	## COMPETITION, and it was introducing itself the same way the Ranch Shop does: a heading, a
	## grey line, a default separator. The three changes here are all typographic and none of them
	## adds a size to the scale:
	##   * the title and the state line share a ROW, so the fold gains a line and the two facts
	##     that belong together (which competition, and what you can field at it) are read together;
	##   * the title is TRACKED, which is what makes 22px read as signage rather than as a label;
	##   * the separator becomes a GOLD RULE, the same device the title screen uses under its
	##     wordmark, so the two screens agree about what "this is the top of something" looks like.
	var mast := HBoxContainer.new()
	mast.add_theme_constant_override("separation", UiTheme.SPACE_LG)
	var mast_title := UiTheme.heading("TOURNAMENTS", 1)
	mast_title.add_theme_font_override("font", UiTheme.display_font(5))
	mast.add_child(mast_title)
	_header = UiTheme.body_text("", "secondary")
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mast.add_child(_header)
	page.add_child(mast)

	var rule := ColorRect.new()
	rule.color = UiTheme.GOLD
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(rule)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	_result_box = VBoxContainer.new()
	_result_box.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	body.add_child(_result_box)

	## ⚠️ THE SHORTFALL GOES HERE, NOT AT THE GATE, AND THAT IS THE WHOLE POINT OF THIS PANEL.
	## Round 19's capture of this screen showed the header reading "2 able to compete" beside a cup
	## that fields 3, and — eleven rows further down, under the bracket — a separate warning that
	## "you will fight 2 v 3". One fact, two voices, and the one a player could act on was the
	## buried one. A shortfall discovered at the sign-up button is not a decision; it is the bill
	## for a decision that was made four weeks ago at the Market.
	##
	## So the stable's gaps are stated ABOVE the draw, in `Roster.stable_gaps()`'s own words — the
	## same words the Market, the Town and the Lab print. See THE GAP VOICE in `town_ui.gd`.
	_gaps_box = VBoxContainer.new()
	_gaps_box.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	body.add_child(_gaps_box)

	## ⚠️ THE SEASON GOES ABOVE THE FIXTURES, AND IT IS THE THING THIS SCREEN WAS MISSING.
	## `docs/META_UI_DIRECTION.md` §2 slack-point 3: "nothing accumulates between cups... this is a
	## series of disconnected fixtures". Both answers below are drawn ENTIRELY from state the game
	## already ships and no screen rendered — `Career.leagues_won`, `Career.champion_for()`,
	## `Pace.par_rung_at_week()`, `CupRun.marquee_month()`. Nothing here is invented, and nothing
	## here is a standings table: see the block comment on `_ladder_board()`.
	_ladder_box = VBoxContainer.new()
	_ladder_box.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	body.add_child(_ladder_box)

	_season_box = VBoxContainer.new()
	_season_box.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	body.add_child(_season_box)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	body.add_child(_list)

	page.add_child(HSeparator.new())
	var back := Button.new()
	back.text = "Back to the Stable"
	back.custom_minimum_size = Vector2(0, 44)
	back.focus_mode = Control.FOCUS_ALL
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/stable.tscn"))
	page.add_child(back)


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	for c in _ladder_box.get_children():
		c.queue_free()
	for c in _season_box.get_children():
		c.queue_free()
	for c in _gaps_box.get_children():
		c.queue_free()
	_ladder_board(_ladder_box)
	_season_strip(_season_box)
	## ⚠️ RE-READ ON EVERY REFRESH, NEVER CACHED. `_refresh()` runs again after a cup resolves and
	## after promotion, and both change the answer — a gap panel showing the roster you had before
	## the cup, above a cup card showing the rung you are on after it, is the same screen printing
	## two different weeks.
	_gaps_panel(_gaps_box)

	## ⚠️ COUNT WHO CAN FIGHT, NOT WHO IS IN THE BARN. `roster.gd:126` states that a retiree cannot
	## compete and nothing enforced it: this header, the short-handed warning and the entry button
	## all counted `Roster.monsters.size()`, so a stable of aged-out bodies read as a full team and
	## entered a full cup. One predicate now — `Roster.fieldable_count()` — see roster.gd.
	var have: int = Roster.fieldable_count()
	var retired: int = Roster.retirees_in_barn().size()
	_header.text = "%s league · week %d · %d gold · %d able to compete%s" % [
		Career.current_league_name(), Career.week, Career.gold, have,
		"  ·  %d retired" % retired if retired > 0 else ""]

	for idx in range(Career.league_index, -1, -1):
		_list.add_child(_cup_card(idx))


## WHAT THIS STABLE CANNOT YET DO — above the draw, in the gap vocabulary, once.
##
## ⚠️ THE ANALYSIS IS `Roster.stable_gaps()` AND NOTHING HERE RECOMPUTES ANY PART OF IT. This
## screen already owns `fieldable_count()` and `team_size_for_league()` and could trivially write
## its own "you are a body short" — which is precisely how the 400-vs-540 ceiling contradiction
## reached a third screen. One function; this panel only renders it.
##
## ⚠️ AND IT NAMES THE GAP WITHOUT NAMING THE FIX. No cup is recommended, no purchase is scored;
## the panel states what the roster lacks and leaves the wager to the player.
func _gaps_panel(parent: VBoxContainer) -> void:
	if not has_node("/root/Roster"):
		return
	var gaps: Array = Roster.stable_gaps()

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default", UiTheme.BORDER))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)
	parent.add_child(panel)

	var head := UiTheme.body_text("What your stable lacks", "primary")
	head.add_theme_color_override("font_color", UiTheme.GOLD)
	col.add_child(head)

	if gaps.is_empty():
		## ⚠️ A RESULT, NOT A BLANK — the same four questions, all four passed. Rendering nothing
		## here would let a player read the absence as "the screen has not checked".
		col.add_child(UiTheme.body_text(
			"Nothing this screen can name. You field enough bodies for this rung and the next, you "
			+ "hold damage and support, part of the answer to this league's champion, and bodies "
			+ "that can still train. Every cup below is a wager you can actually make.", "muted"))
		return

	for gv in gaps:
		var g: Dictionary = gv
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiTheme.SPACE_SM)
		col.add_child(row)

		## Severity carried by GLYPH as well as colour — never hue alone. `▲`/`•` are the two the
		## rest of the UI already renders; `▸` is not in the packaged font and falls back to tofu.
		var blocking: bool = int(g["severity"]) >= 2
		var mark := UiTheme.body_text("▲" if blocking else "•", "primary")
		mark.autowrap_mode = TextServer.AUTOWRAP_OFF
		mark.add_theme_color_override("font_color",
			UiTheme.CAUTION if blocking else UiTheme.TEXT_SECONDARY)
		row.add_child(mark)

		var line := UiTheme.body_text(GapVoice.gap_sentence(g), "secondary")
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		## ⚠️ THE SENTENCE IS NOT A SECOND AMBER. `GOLD` and `CAUTION` measure 1.023:1 apart —
		## `docs/POLISH_DIRECTION.md` §1.1 — so a blocking gap written in CAUTION was, on screen,
		## exactly the same colour as the "What your stable lacks" heading two rows above it, and
		## this screen printed amber ink 25 times against 13 greys. The severity is already carried
		## by the ▲ mark beside it (which KEEPS its CAUTION, because a mark is a mark); the sentence
		## takes the primary ink and is emphatic by being brighter than the secondary lines it sits
		## among, not by being a second heading colour.
		if blocking:
			line.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY)
		row.add_child(line)


# ══════════════════════════════════════════════════════════════════════════════════════════════
# THE LADDER BOARD — the season container, and the argument for why it is not a standings table
# ══════════════════════════════════════════════════════════════════════════════════════════════
#
# ⚠️ TEAMFIGHT MANAGER 2 LIVES IN ITS TABLE AND THIS GAME MUST NOT COPY IT. TFM2 is a ROUND-ROBIN:
# everyone plays everyone, rivals accumulate results whether you watch or not, and the table is
# therefore the season's true state. This game is a PROMOTION LADDER whose field is drawn FRESH
# PER CUP (`Career.make_cup_field()`, seeded off `cup_field_seed()` and rolled every game-month).
# There is no standing field to tabulate. A standings table here would have to either fabricate
# rows nobody played — which is the project's rule (1) violation, a screen lying about the thing
# it describes — or be a one-row log of your own history, which is a log, not a table.
#
# THE JOB THE TABLE DOES IS STILL REAL: persistent, named, comparative, lived-in. This game's own
# structure serves it better, and every ingredient was already shipped and unrendered:
#   * eleven rungs, each with an AUTHORED champion who has a name, a title and an archetype
#     (`Career.CHAMPIONS` × `Tactics.ARCHETYPE_BY_LEAGUE`),
#   * a live pace-setter — the Varra stable — on an authored schedule whose rung moves with the
#     week (`Career.dynasty_rung_at_week()`, read through the one `Pace` adapter),
#   * `leagues_won`, which already records every belt you hold.
#
# So: eleven rungs across the page, your marker and theirs on it, the champion named under each.
# Every cell is a fact the game already owns. Nothing on this strip is fabricated.
func _ladder_board(parent: VBoxContainer) -> void:
	var leagues: Array = Career.leagues
	var n: int = leagues.size()
	if n == 0:
		return
	var won: Array = Career.leagues_won
	var you: int = Career.league_index
	var them: int = Pace.par_rung_at_week(Career.week)

	parent.add_child(UiTheme.heading("The Ladder", 3))

	## ⚠️ THE BEST INFORMATION DESIGN ON THIS SCREEN WAS DRAWN ON THE PAGE ITSELF. Eleven rungs,
	## every titleholder named, your marker and the pace-setter's — and it sat directly on the
	## SURFACE fill with nothing around it, so the one element that is genuinely a BOARD read as
	## eleven loose columns of caption text. A panel is the whole fix: it is the same strip, given
	## an edge and a ground, and it costs one container. ELEVATION IS INFORMATION — this is the
	## screen's subject, so it is the thing that gets raised.
	var board := PanelContainer.new()
	board.add_theme_stylebox_override("panel", UiTheme.panel_style("raised", UiTheme.BORDER))
	parent.add_child(board)

	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 3)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.add_child(strip)

	for i in range(n):
		var taken: bool = i < won.size() and bool(won[i])
		var lname: String = str((leagues[i] as Dictionary).get("name", "?"))
		var champ: Dictionary = Career.champion_for(i)
		var gp: Dictionary = TacticsScript.GAMEPLANS.get(str(champ.get("archetype", "")), {})

		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 1)
		## ⚠️ RULE 3'S SPIRIT ON A NON-CONTROL: this strip is not clickable, so it owes its
		## explanation in the tooltip AND in visible text. The visible line is the champion's name;
		## the tooltip carries the read, which is the same string `tactics_ui.gd` will show when you
		## actually face them — one source (`Tactics.champion_read`), never a second copy.
		cell.tooltip_text = "%s — %s, %s\n%s %s: %s" % [lname,
			str(champ.get("name", "")), str(champ.get("title", "")),
			str(gp.get("icon", "")), str(gp.get("name", "?")), str(champ.get("read", ""))]
		strip.add_child(cell)

		cell.add_child(_ladder_cell_label(lname,
			UiTheme.GOLD if i == you else UiTheme.TEXT_SECONDARY, UiTheme.SIZE_CAPTION))

		var bar := PanelContainer.new()
		bar.custom_minimum_size = Vector2(0, 12)
		var sb := StyleBoxFlat.new()
		# Three states, and they are three different facts: a belt you hold, the rung you are
		# standing on, and a rung nobody has taken off its champion yet.
		sb.bg_color = UiTheme.GOLD if taken else (UiTheme.CAUTION.darkened(0.45) if i == you else UiTheme.BORDER_FAINT)
		sb.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("panel", sb)
		cell.add_child(bar)

		cell.add_child(_ladder_cell_label("%s %s" % [str(gp.get("icon", "")), _surname(str(champ.get("name", "")))],
			UiTheme.TEXT_PRIMARY if not taken else UiTheme.TEXT_MUTED, UiTheme.SIZE_CAPTION))

		var marks: Array = []
		if i == you:
			marks.append("▲ YOU")
		if i == them:
			marks.append("◆ VARRA")
		cell.add_child(_ladder_cell_label("  ".join(marks),
			UiTheme.SAFE if (i == you and you >= them) else UiTheme.CAUTION, UiTheme.SIZE_CAPTION))

	var legend := UiTheme.body_text(
		"A gold bar is a belt you hold. The name under each rung is its titleholder — hover for the read you will be given when you face them.",
		"muted")
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(legend)

	# The pace sentence, in `Career`'s own words via the one adapter. This is the only line on the
	# screen that says how the climb is GOING rather than what is on offer.
	var snap: Dictionary = Pace.snapshot()
	if not snap.is_empty():
		var pace := UiTheme.body_text(Pace.pace_line(snap), "primary")
		pace.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pace.add_theme_color_override("font_color", Pace.pace_color(snap))
		parent.add_child(pace)


## ⚠️ TRACKING IS NOT A SIZE — it does not touch `TOKEN_FONT_SIZES` and the probe cannot see it,
## which is the point: the display treatment this screen needed was spacing, not another number.
## It comes from `UiTheme.display_font(px)`; see the ⚠️ in `title_ui.gd` for why no screen may
## hand-roll its own again.


func _ladder_cell_label(text: String, tint: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	## ⚠️ `AUTOWRAP_OFF` + `clip_text`, AND `ending_ui.gd:_climb_cell` CARRIES THE SAME ⚠️ FOR THE
	## SAME REASON. An autowrapping Label reports a ~0 minimum width, so eleven of them in an
	## expanding row collapse on top of each other — legible in code, unreadable on screen, and
	## only ever caught by looking at the capture.
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.clip_text = true
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", tint)
	return l


## "Dunnal Bray" -> "Bray"; "The Dynast" -> "Dynast". Eleven cells across a strip cannot carry a
## full name, and a truncated first name ("Dunna…") identifies nobody.
func _surname(full: String) -> String:
	var parts: PackedStringArray = full.strip_edges().split(" ", false)
	return full if parts.size() == 0 else str(parts[parts.size() - 1])


# ══════════════════════════════════════════════════════════════════════════════════════════════
# THE SEASON — the calendar `cup_run.gd` has always shipped and no screen has ever drawn
# ══════════════════════════════════════════════════════════════════════════════════════════════
#
# ⚠️ AUTHORED AND UNREACHED, THE PROJECT'S SIGNATURE FAILURE, ELEVENTH INSTANCE. `cup_run.gd`
# ships 13 months a game-year, five NAMED marquee events (`MARQUEE_LEAGUES`), a deterministic
# month per league per year (`marquee_month()`), a 1.75× purse and a 2× fee — and until this
# strip existed the ONLY way a player could learn any of it was to happen to open the tournament
# screen in the right month and read a paragraph that had appeared from nowhere.
#
# ⚠️ AND THE DRAW'S OWN CLOCK IS ON IT TOO. `Career.cup_field_seed()` is keyed on `week / 4`, so
# the field you scout holds for exactly this game-month and is a different field next month. That
# is the rule that makes scouting mean anything ("scout it, go and train, come back to the same
# opponents") and no screen said it.
func _season_strip(parent: VBoxContainer) -> void:
	var wpm: int = CupRun.WEEKS_PER_MONTH
	var mpy: int = CupRun.MONTHS_PER_YEAR
	var year: int = int(Career.week) / (wpm * mpy)
	var month: int = int(int(Career.week) % (wpm * mpy)) / wpm

	# Which league's marquee falls in which month THIS year — only the rungs you may enter, since
	# `can_enter_league` forbids punching up and a calendar full of events you cannot attend is
	# noise dressed as content.
	var by_month: Dictionary = {}
	for idx in range(0, Career.league_index + 1):
		var mname: String = CupRun.marquee_name(idx)
		if mname == "":
			continue
		var m: int = CupRun.marquee_month(idx)
		if not by_month.has(m):
			by_month[m] = []
		(by_month[m] as Array).append({"idx": idx, "name": mname,
			"league": str(Career.league_at(idx).get("name", "?"))})

	parent.add_child(UiTheme.heading("The Season — year %d, month %d of %d" % [year + 1, month + 1, mpy], 3))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)

	for m in range(mpy):
		var events: Array = by_month.get(m, [])
		var is_now: bool = m == month
		var cell := PanelContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sb := StyleBoxFlat.new()
		sb.bg_color = UiTheme.PANEL_RAISED if is_now else UiTheme.PANEL
		sb.border_color = UiTheme.GOLD if is_now else (UiTheme.CAUTION if not events.is_empty() else UiTheme.BORDER_FAINT)
		sb.set_border_width_all(2 if is_now else 1)
		sb.set_corner_radius_all(UiTheme.RADIUS_SM)
		sb.content_margin_top = 2; sb.content_margin_bottom = 2
		cell.add_theme_stylebox_override("panel", sb)
		var tips: Array = []
		for e in events:
			tips.append("%s — the %s marquee" % [str((e as Dictionary)["name"]), str((e as Dictionary)["league"])])
		cell.tooltip_text = "Month %d of the season%s" % [m + 1,
			("\n" + "\n".join(tips)) if not tips.is_empty() else " — no marquee falls here"]
		row.add_child(cell)

		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		cell.add_child(col)
		col.add_child(_ladder_cell_label("%d" % (m + 1),
			UiTheme.GOLD if is_now else UiTheme.TEXT_MUTED, UiTheme.SIZE_CAPTION))
		# ⚠️ `UiTheme.BORDER` WAS THE INK HERE AND IT IS A BORDER TOKEN, NOT A TEXT ONE. #33333D on
		# #1E1E26 is roughly 1.2:1 — the empty-month dot was invisible rather than quiet, and it was
		# thirteen of the twenty remaining off-token colours in the whole game (one per month of the
		# season). `TEXT_MUTED` is the dimmest ink `theme.gd` publishes and it carries a measured
		# 5.10:1, so the row now reads as thirteen months with one starred rather than as one star
		# floating in nothing.
		col.add_child(_ladder_cell_label("★" if not events.is_empty() else "·",
			UiTheme.CAUTION if not events.is_empty() else UiTheme.TEXT_MUTED, UiTheme.SIZE_CAPTION))

	# ⚠️ SAY WHAT IS OPEN AND WHAT IS NOT, AND NEVER PRETEND A LOCKED THING IS COMING. The marquee
	# leagues start at Silver; a Wood-to-Iron player has no marquee at all, and copy that implies
	# one is "next" would be a screen promising something the rules forbid.
	var lines: Array = []
	for m2 in range(mpy):
		for e2 in (by_month.get(m2, []) as Array):
			var when: String = "THIS MONTH" if m2 == month else ("month %d" % (m2 + 1))
			lines.append("★ %s — the %s marquee, %s" % [str((e2 as Dictionary)["name"]),
				str((e2 as Dictionary)["league"]), when])
	if lines.is_empty():
		var none := UiTheme.body_text(
			"No marquee is open to you yet — they begin at Silver (%s). Climb to one and the year gets a fixture worth planning around: a deeper draw, double entry, and a purse worth %d%% of a normal cup."
			% [CupRun.MARQUEE_LEAGUES.get("Silver", "The Silver Assay"),
				int(round(CupRun.MARQUEE_PURSE_MULT * 100.0))], "secondary")
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(none)
	else:
		for ln in lines:
			# Primary ink, no override — see the ⚠️ in `_gaps_panel`. The ★ in the month strip above
			# is what marks a marquee; the sentence does not need to be amber to say so as well.
			var l2 := UiTheme.body_text(str(ln), "primary")
			l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			parent.add_child(l2)

	var holds_until: int = (int(int(Career.week) / wpm) + 1) * wpm
	var draw_note := UiTheme.body_text(
		"The fields below were drawn for this month and hold until week %d (%d week%s away) — scout one, go and train against it, and the same teams will still be in the draw when you come back. Next month is a new draw."
		% [holds_until, holds_until - int(Career.week), "" if holds_until - int(Career.week) == 1 else "s"], "muted")
	draw_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(draw_note)


## ⚠️ `marquee` IS PASSED IN, NOT LOOKED UP, AND THAT IS A REAL BUG AVOIDED. The marquee is a
## function of `Career.week`, and a cup now COSTS weeks — so by the time the result card is drawn
## the clock has moved and `CupRun.is_marquee()` may already have rolled past the month the player
## entered in. The purse must be paid for the cup that was ENTERED, so the flag travels with the
## run (`CupRun.finish()` puts it in the result dict) rather than being re-derived at payout.
func _purse_for(idx: int, marquee: bool = false) -> int:
	var drop: int = clampi(Career.league_index - idx, 0, REWARD_BY_DROP.size() - 1)
	var base: int = BASE_PURSE + PURSE_PER_LEAGUE * idx
	var purse: float = float(base) * float(REWARD_BY_DROP[drop])
	if marquee:
		purse *= float(CupRun.MARQUEE_PURSE_MULT)
	return int(round(purse))


## ⚠️ THE BOTTOM RUNG IS FREE TO A BROKE PLAYER, AND THAT IS A SOFTLOCK FIX, NOT CHARITY.
## Cup purses are effectively the only gold SOURCE in the build (`grep add_gold`: this screen, a
## market sell-back, a cancelled fusion refund). Charge for every entry unconditionally and a
## player with one monster and no gold has no legal move left. The Wood ring waives its fee when
## you cannot pay it — you can always get back on the ladder, and only at the bottom of it.
func _fee_for(idx: int, marquee: bool = false) -> int:
	var fee: int = BASE_FEE + FEE_PER_LEAGUE * idx
	if marquee:
		fee = int(round(float(fee) * float(CupRun.MARQUEE_FEE_MULT)))
	if idx == 0 and Career.gold < fee:
		return 0
	return fee


## ONE CUP, AS A ROW THAT CAN BE COMPARED WITH THE ROW ABOVE IT.
##
## ⚠️ THIS CARD USED TO BE A COLUMN OF ELEVEN FULL-WIDTH SENTENCES AND THAT WAS THE WHOLE PROBLEM.
## Every fact on it was true, sourced and worth knowing — and three of them stacked ran 1,300px, so
## answering "which of these three cups is worth my week" meant reading forty lines and holding six
## numbers in your head. `docs/META_UI_DIRECTION.md` C2: *"three tall text blocks cannot be
## compared"*. NOTHING WAS DELETED HERE. The same values are laid out so the eye can run DOWN a
## column of cups and compare one field at a time, which is what a management screen is for.
func _cup_card(idx: int) -> Control:
	var is_frontier: bool = idx == Career.league_index
	## ⚠️ A CLEARED RUNG IS A DIFFERENT DECISION AND IT GETS A DIFFERENT AMOUNT OF SCREEN.
	## `REWARD_BY_DROP` pays a cleared league 50% and one below that 20% — this file's own header
	## says it plainly: *"farming a league you have already cleared is a safety net, not a
	## strategy."* Rendering the safety net at the same size as the frontier cup pushed the frontier
	## cup and its bracket off the fold, which inverted the screen: the decision you cannot make
	## anywhere else got the same weight as the one you make when the real one is out of reach.
	## The collapsed row still carries every number the fallback decision needs — size, entry,
	## purse, the punch-down rate, the week cost and who holds it — so nothing is hidden, only
	## ranked. See `_cleared_cup_row()`.
	if not is_frontier:
		return _cleared_cup_row(idx)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("raised", UiTheme.GOLD))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	var lname: String = Career.league_at(idx).get("name", "?")
	var team_size: int = Career.team_size_for_league(idx)
	var marquee: bool = CupRun.is_marquee(idx)
	var rounds: int = CupRun.rounds_for(idx)
	var cap: int = int(Career.stat_cap_for_league(idx))
	var have: int = Roster.fieldable_count()   ## ⚠️ fieldable, not present — see _refresh()
	var fee: int = _fee_for(idx, marquee)
	var weeks: int = CupRun.weeks_for_cup(idx, rounds)
	var purse: int = _purse_for(idx, marquee)

	# ── TITLE ROW ─────────────────────────────────────────────────────────────
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	col.add_child(title_row)
	title_row.add_child(UiTheme.heading("%s Cup" % lname, 3))
	## ⚠️ `AUTOWRAP_OFF` ON ANYTHING PUT IN AN HBOX. `UiTheme.body_text()` autowraps by default,
	## which gives a Label a ~0 minimum width — in a row it then wraps to two or three lines and
	## drags the whole card taller. "your league" rendered as "your / league" in the first capture
	## of this rework. `ending_ui.gd:_climb_cell` and `_ladder_cell_label()` above carry the same ⚠️.
	var yours := UiTheme.body_text("· your league · the only rung that promotes you", "secondary")
	yours.autowrap_mode = TextServer.AUTOWRAP_OFF
	yours.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(yours)

	# ── THE MARQUEE — the one week a year this rung is an EVENT ───────────────
	# ⚠️ The build had no calendar at all: every cup at every rung was identical and available
	# forever, so "which cup, and when" was never a question. Once a year, at each senior league,
	# it is. See `cup_run.gd:MARQUEE_LEAGUES` — and `_season_strip()` above, which is where a
	# player now learns the event exists BEFORE the month it lands in.
	if marquee:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_row.add_child(spacer)
		# `heading()` is already GOLD. The override to CAUTION made this the only heading on the
		# screen in a DIFFERENT amber that measures 1.023:1 from the one every other heading uses —
		# a distinction nobody can see, costing the screen its one heading ink.
		var m := UiTheme.heading("★ %s — THIS MONTH ONLY" % CupRun.marquee_name(idx), 3)
		m.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		title_row.add_child(m)

	# ── THE TERMS, IN ONE COMPARABLE LINE ─────────────────────────────────────
	# ⚠️ THE STANDINGS ARE HALF THE WAGER (`career.gd:PLACEMENT_REWARD_FRACTION` pays 100/65/40/0)
	# and they used to be a separate sentence below the bracket. Placement money and the winner's
	# purse are the same decision, so they are the same line.
	var pays: Array = []
	for place in [1, 2, 3]:
		if place > rounds + 1:
			break
		pays.append("%s %dg" % [Career.placement_label(place),
			int(round(float(purse) * Career.placement_reward_fraction(place)))])
	# ⚠️ THE TRIP IS THE PRICE AND IT MUST BE ON THE CARD. `docs/META_GAME_REVIEW.md` E2: the cup
	# path never touched `Career.week`, so gold per week of game time was infinite and the weekly
	# tick — the entire stable half — could be skipped by the one activity the game is about. It
	# now sits IN the terms rather than in its own paragraph, and is repeated on the button and its
	# tooltip, because it is the cost players systematically fail to price.
	col.add_child(UiTheme.body_text(
		"%dv%d  ·  %d rounds  ·  stat ceiling %d  ·  entry %dg  ·  %s  ·  anything lower pays nothing  ·  costs %d week%s of your stable's life"
		% [team_size, team_size, rounds, cap, fee, "  ·  ".join(pays),
			weeks, "" if weeks == 1 else "s"], "secondary"))

	# ── THE DRAW, ROUND BY ROUND, SIDE BY SIDE ────────────────────────────────
	# ⚠️ THIS IS THE DECISION. `CLAUDE.md`: "Preparation is the skill; observation is the reward".
	# None of that is true if the player cannot see what they are training FOR. The field is drawn
	# off `Career.cup_field_seed()` — stable for the game-month — so the arc shown here is the arc
	# actually fought: scout it, go and train, come back to the same opponents.
	#
	# ⚠️ AND IT IS A BRACKET, NOT A HEADLINE. This used to print the opener and the final and
	# nothing between, an honest summary of a cup whose middle rounds did not matter: measured at a
	# 65%-filled roster, round one won 100% at all eleven leagues. `CupRun.round_fill` redistributes
	# the draw so every round is a fight; showing every round is what makes that legible.
	#
	# ⚠️ HORIZONTAL, AND THE FILLS ARE A DRAWN BAR NOW. `[##·-]` was an ASCII chart, which is a
	# chart that lies about its precision — five buckets rendered as if they were a measurement.
	var drawn: Array = Career.make_cup_field(idx, rounds)
	var bracket := HBoxContainer.new()
	bracket.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	col.add_child(bracket)
	for r in range(rounds):
		bracket.add_child(_round_chip(r, rounds, idx, lname, drawn))

	# ── WHO HOLDS IT ──────────────────────────────────────────────────────────
	var champ: Dictionary = Career.champion_for(idx)
	var beaten: bool = Career.has_beaten_champion(idx)
	var gp: Dictionary = TacticsScript.GAMEPLANS.get(str(champ.get("archetype", "")), {})
	var champ_line := UiTheme.body_text("%s %s, %s — %s. %s%s" % [
		"↺" if beaten else "❖",  # ❖ (U+2756) is in the packaged Inter face; ♛ is not
		str(champ.get("name", "")), str(champ.get("title", "")), str(gp.get("name", "?")),
		str(champ.get("read", "")),
		"  (you have taken this title off them before — they have trained since)" if beaten else ""],
		"primary")
	## ⚠️ GOLD IS THE CARD'S TITLE INK, AND A CARD WITH FIVE GOLD LINES HAS NO TITLE. The champion
	## read and the promotion rule are both BODY — the most important body on the card, so they take
	## the primary ink — and gold is left to do one job here: the cup's name and its entry button.
	## This is the "amber monotone" `docs/POLISH_DIRECTION.md` §1.2 measured on this exact screen.
	champ_line.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY if not beaten else UiTheme.TEXT_SECONDARY)
	champ_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(champ_line)

	# ⚠️ SHORT-HANDED ENTRY MUST BE BILLED, NOT DISCOVERED. Entering a body down is allowed
	# (`Career.SHORT_ENTRY_ALLOWANCE`) because being locked out was an invisible economy wall, but a
	# penalty the player only meets in the arena is not a decision — it is an ambush.
	## ⚠️ ONLY WHEN ENTRY IS ACTUALLY POSSIBLE. Below the minimum the card already carries
	## `entry_block_reason()`, and "you will fight 0 v 5" underneath "every monster has retired" is
	## two sentences competing to explain one state — the player reads the weaker one.
	## ⚠️ AND IT IS THE TERMS OF *THIS ENTRY*, NOT A SECOND DIAGNOSIS. Round 19's capture had this
	## line stating "a body down" eleven rows under a header that had already counted the bodies,
	## and it read as the screen arguing with itself. The SHORTFALL is now named once, up top, in
	## the gap panel's words; what belongs on the ticket is what the ticket buys — the shape of
	## the sheet you are entering with. Same arithmetic, one source (`fieldable_count()` ×
	## `team_size_for_league()`, which is what `stable_gaps()` reads too), two different facts.
	if have < team_size and have >= Career.min_team_to_enter(idx) and have > 0:
		var short_line := UiTheme.body_text(
			"⚠ Entering short-handed: you field %d against %d, every round. The draw does not shrink to match you."
			% [mini(have, team_size), team_size], "primary")
		short_line.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY)
		short_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(short_line)

	# ⚠️ State the sweep rule BEFORE entry. Promotion is a hard gate and the player must be able to
	# weigh it, not discover it by losing.
	## ⚠️ SAY THE NUMBER BEFORE THE FEE, NOT AFTER THE LOSS. This card used to promise "beat all
	## N", which was the old sweep gate; the rank and the title separated and a sign-up screen
	## that states the wrong gate is worse than one that states none — the player prices the
	## wager wrong and reads a promotion they DID earn as luck. Read from
	## `Career.wins_needed_to_advance()`, the same function the outcome uses.
	var need: int = Career.wins_needed_to_advance(idx, rounds)
	var promo_text: String = "Beat all %d and the title — and the rank — are yours." % rounds if need >= rounds \
		else "Win %d of the %d rounds and the RANK is yours; take all %d and so is the TITLE." % [need, rounds, rounds]
	var promo := UiTheme.body_text(promo_text + " Fall short and you place, and are paid to place.", "primary")
	promo.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY)
	promo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(promo)

	## ⚠️ A LOCKED DOOR MUST SAY WHY, AND "you have 4" WHEN THE PLAYER CAN SEE FOUR MONSTERS IS A
	## LIE. `UI_LAYOUT_RULES.md` rule 2 forbids a dead control with no explanation, and the retiree
	## case is precisely the one where the old copy was actively misleading — the stable screen shows
	## four bodies and this button would have said "you have 0". `Roster.entry_block_reason()` is the
	## one function that names the cause and the move, shared with `tactics_ui.gd`.
	var blocked: String = Roster.entry_block_reason(Career.min_team_to_enter(idx))
	if blocked != "":
		var why := UiTheme.body_text(blocked, "primary")
		why.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(why)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 38)
	btn.focus_mode = Control.FOCUS_ALL
	# The full sentence the card no longer spends four lines on lives here, where it is read at the
	# exact moment it is paid.
	btn.tooltip_text = ("Entering costs %dg and %d week%s of game time. Your stable ages, eats and rests on the road, "
		+ "but nobody trains. The field is the one shown above — it will not re-roll at the door.") % [
			fee, weeks, "" if weeks == 1 else "s"]
	if blocked != "":
		btn.disabled = true
		btn.text = "Cannot enter — %d of %d can still compete" % [have, Roster.monsters.size()]
	elif Career.gold < fee:
		btn.disabled = true
		btn.text = "Entry is %dg — you have %dg" % [fee, Career.gold]
	elif fee <= 0:
		btn.text = "Enter the %s Cup  ·  entry waived  ·  costs %d week%s of your stable's life" % [
			lname, weeks, "" if weeks == 1 else "s"]
		btn.pressed.connect(_on_enter.bind(idx))
	else:
		btn.text = "Enter the %s Cup  ·  %dg  ·  costs %d week%s of your stable's life" % [
			lname, fee, weeks, "" if weeks == 1 else "s"]
		btn.pressed.connect(_on_enter.bind(idx))
	if is_frontier and not btn.disabled:
		for state in ["normal", "hover", "pressed", "disabled"]:
			btn.add_theme_stylebox_override(state, UiTheme.button_stylebox("primary", state))
		btn.add_theme_stylebox_override("focus", UiTheme.button_stylebox("primary", "focus"))
	col.add_child(btn)
	return panel


## A RUNG YOU HAVE ALREADY TAKEN — the fallback, priced in one row.
##
## ⚠️ NOTHING IS HIDDEN, ONLY RANKED. Every number that decides "should I farm this instead" is on
## the row: the field size, the entry, what first pays after the punch-down multiplier, the week
## cost and who still holds the belt. What is dropped is the per-round bracket and the counter-read
## — the scouting apparatus, which exists to help you beat a rung you have NOT beaten. Keeping it
## here cost 220px per cleared league and pushed the frontier cup's own bracket below the fold.
func _cleared_cup_row(idx: int) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)

	var lname: String = Career.league_at(idx).get("name", "?")
	var team_size: int = Career.team_size_for_league(idx)
	var marquee: bool = CupRun.is_marquee(idx)
	var rounds: int = CupRun.rounds_for(idx)
	var fee: int = _fee_for(idx, marquee)
	var weeks: int = CupRun.weeks_for_cup(idx, rounds)
	var purse: int = _purse_for(idx, marquee)
	var drop_pct: int = int(REWARD_BY_DROP[
		clampi(Career.league_index - idx, 0, REWARD_BY_DROP.size() - 1)] * 100.0)
	var champ: Dictionary = Career.champion_for(idx)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	col.add_child(row)

	var name_lbl := UiTheme.body_text("%s Cup" % lname, "primary")
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_lbl.custom_minimum_size = Vector2(150, 0)
	name_lbl.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	row.add_child(name_lbl)

	var terms := UiTheme.body_text(
		"cleared — pays %d%%  ·  %dv%d  ·  %d rounds  ·  entry %dg  ·  1st %dg  ·  %d week%s  ·  ❖ %s"
		% [drop_pct, team_size, team_size, rounds, fee, purse, weeks,
			"" if weeks == 1 else "s", str(champ.get("name", ""))], "muted")
	terms.autowrap_mode = TextServer.AUTOWRAP_OFF
	terms.clip_text = true
	terms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(terms)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(230, 32)
	btn.focus_mode = Control.FOCUS_ALL
	btn.tooltip_text = ("A rung you have already taken. It cannot promote you and it pays %d%% of its own purse, "
		+ "but it still costs %dg and %d week%s. %s still holds the belt and has trained since you took it.") % [
			drop_pct, fee, weeks, "" if weeks == 1 else "s", str(champ.get("name", ""))]
	var blocked: String = Roster.entry_block_reason(Career.min_team_to_enter(idx))
	if blocked != "":
		btn.disabled = true
		## ⚠️ THE REASON GOES ON ITS OWN WRAPPED LINE, NOT INSIDE A 230px BUTTON. `entry_block_reason`
		## returns a whole sentence; Godot's Button clips text with no ellipsis, so putting it in the
		## label would have produced a dead control whose explanation was cut off mid-word — rule 3
		## satisfied on paper and broken on screen. The button says the state, the line says why, and
		## the tooltip carries it too for anyone hovering.
		btn.text = "Cannot enter"
		btn.tooltip_text = blocked
		var why := UiTheme.body_text(blocked, "primary")
		why.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(why)
	elif Career.gold < fee:
		btn.disabled = true
		btn.text = "Entry is %dg — you have %dg" % [fee, Career.gold]
		btn.tooltip_text = "You cannot afford this rung's entry fee."
	else:
		btn.text = "Farm the %s Cup  ·  %dg" % [lname, fee]
		btn.pressed.connect(_on_enter.bind(idx))
	row.add_child(btn)
	return panel


## ONE ROUND OF THE DRAW: which round, what KIND of team, and how filled it is — three facts
## stacked in a fixed-width chip so the whole bracket reads left to right as an escalation.
##
## ⚠️ THE KIND IS THE NEW INFORMATION AND IT MUST NOT BE HIDDEN BEHIND THE BAR. Until the archetype
## workstream every rival came out of one generator and differed only by a fill fraction, so the
## eleven authored champion reads were decoration and "knowing WHICH monster to make" had one
## answer. A drawn field carries an archetype per round now (`Career.make_cup_field`), and a
## strength bar alone would show only the half that was already there.
func _round_chip(r: int, rounds: int, idx: int, lname: String, drawn: Array) -> Control:
	var f: float = CupRun.round_fill(r, rounds, idx)
	var is_last: bool = r == rounds - 1
	var kind: String = String(drawn[r].get("archetype", "")) if r < drawn.size() else ""
	var gp: Dictionary = TacticsScript.GAMEPLANS.get(kind, {})

	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.PANEL_RAISED if is_last else UiTheme.PANEL
	sb.border_color = UiTheme.GOLD if is_last else UiTheme.BORDER_FAINT
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(UiTheme.RADIUS_SM)
	sb.content_margin_left = UiTheme.SPACE_SM; sb.content_margin_right = UiTheme.SPACE_SM
	sb.content_margin_top = 3; sb.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", sb)
	## The read the player will be handed on the tactics screen when they meet this team — same
	## string, same source (`Tactics.read_for` / `champion_read`), so the scout and the fight cannot
	## describe the opponent differently.
	chip.tooltip_text = "%s\n%s\n\nCounter-read: %s" % [
		str(drawn[r].get("label", "")) if r < drawn.size() else "",
		str(drawn[r].get("read", "")) if r < drawn.size() else "",
		TacticsScript.counter_for(kind)]

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	chip.add_child(v)

	var who := Label.new()
	who.text = "THE TITLE BOUT" if is_last else "Round %d" % (r + 1)
	who.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	who.add_theme_color_override("font_color", UiTheme.GOLD if is_last else UiTheme.TEXT_SECONDARY)
	v.add_child(who)

	var what := Label.new()
	what.text = "%s %s" % [str(gp.get("icon", "")), str(gp.get("name", kind))]
	what.clip_text = true
	what.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	what.add_theme_color_override("font_color", UiTheme.TEXT_PRIMARY)
	v.add_child(what)

	v.add_child(_fill_bar(f, lname))
	return chip


## A drawn strength bar with its number printed on the row — never fill colour alone
## (`theme.gd`'s own standing rule, and `docs/ACCESSIBILITY.md` §0 finding #2).
func _fill_bar(f: float, lname: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_XS)

	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(f, 0.0, 1.0)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fg := StyleBoxFlat.new()
	fg.bg_color = UiTheme.CAUTION if f >= 0.75 else UiTheme.GOLD
	fg.set_corner_radius_all(2)
	var bg := StyleBoxFlat.new()
	bg.bg_color = UiTheme.SURFACE
	bg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fg)
	bar.add_theme_stylebox_override("background", bg)
	bar.tooltip_text = "%d%% of the %s stat ceiling" % [int(round(f * 100.0)), lname]
	row.add_child(bar)

	var pct := Label.new()
	pct.text = "%d%%" % int(round(f * 100.0))
	pct.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	pct.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	row.add_child(pct)
	return row



## Starts a LIVE cup: `CupRun` pre-generates each round's rival team, then this screen hands off
## to "The Read" for round 1. No fight happens here anymore — the player watches every round play
## out (tactics -> arena3d, `rival_count` times) before landing back on this screen. The three
## fights headless-in-a-for-loop that used to happen here now only happen via
## `Career.enter_league_tournament()` directly, which the QA harness and sandbox still call.
## ⚠️ THE FEE IS CHARGED HERE AND IS NOT REFUNDED. The button is disabled when it is unaffordable,
## so the only caller that can reach this without the gold is a direct scripted call (the probes);
## `spend_gold()` refuses rather than going negative, and the warning makes that loud instead of
## silent. `rival_count` is NOT passed — the league's own field size is the default now.
## ⚠️ AND THE TRIP IS CHARGED HERE, AFTER THE FIELD IS DRAWN, NEVER BEFORE. `Career.cup_field_seed()`
## is a function of the game WEEK (stable for four weeks), so advancing the clock first would draw
## a DIFFERENT field from the one the card just scouted — the exact failure the drawn-field rule
## exists to prevent. Draw, then travel: you fight the teams that entered, and your stable arrives
## a fortnight older than it left.
func _on_enter(idx: int) -> void:
	var marquee: bool = CupRun.is_marquee(idx)
	var fee: int = _fee_for(idx, marquee)
	if not Career.spend_gold(fee):
		push_warning("tournament: entered the %s Cup without paying the %dg fee (gold %d)" % [
			Career.league_at(idx).get("name", "?"), fee, Career.gold])
	CupRun.start(idx)
	CupRun.travel()
	get_tree().change_scene_to_file("res://scenes/tactics.tscn")


## Renders a finished cup's result exactly as the old headless `_on_enter` did — reused for the
## live path (`out` from `CupRun.finish()`) so the two paths share one rendering code path.
## ⚠️ The purse is paid HERE, not in career.gd/cup_run.gd. `enter_league_tournament` (and, by
## extension, the promotion rule `CupRun.finish()` shares with it) is also driven by the QA
## harness and the sandbox; paying gold inside either would make those runs mutate the player's
## economy as a side effect of measuring something else.
func _show_result(out: Dictionary) -> void:
	var idx: int = int(out.get("leagueIndex", 0))
	var before_league: String = str(out.get("beforeLeague", Career.current_league_name()))

	var wins: int = int(out.get("wins", 0))
	var rival_count: int = maxi(1, int(out.get("rivalCount", 3)))
	## ⚠️ PAID BY PLACEMENT (100/65/40/0), not by win fraction — `town.ts:PLACEMENT_REWARD_FRACTION`,
	## which never crossed into the port. It is the difference between a cup being a coin-flip on
	## the whole purse and a cup being a result you can be NEARLY good enough for: losing only to
	## the champion still pays for the trip, finishing mid-table pays nothing.
	var placement: int = int(out.get("placement", Career.placement_for(wins, rival_count)))
	var frac: float = float(out.get("placementFraction", Career.placement_reward_fraction(placement)))
	var was_marquee: bool = bool(out.get("marquee", false))
	var purse: int = int(round(float(_purse_for(idx, was_marquee)) * frac))
	Career.add_gold(purse)

	for c in _result_box.get_children():
		c.queue_free()

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("raised", UiTheme.GOLD))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	col.add_child(UiTheme.heading("%s%s — %s, %d of %d" % [
		"%s · " % str(out.get("marqueeName", "")) if was_marquee else "",
		"%s Cup" % str(out.get("league", "")),
		Career.placement_label(placement), wins, rival_count], 2))

	var matches: Array = out.get("matches", [])
	for i in range(matches.size()):
		var won: bool = bool(matches[i].get("won", false))
		var was_champ: bool = bool(matches[i].get("champion", false))
		var who: String = str(matches[i].get("label", ""))
		var line := UiTheme.body_text("%s%s — %s" % [
			"THE TITLE BOUT · " if was_champ else "Round %d · " % (i + 1),
			who if who != "" else "the draw", "WON" if won else "lost"], "primary")
		line.add_theme_color_override("font_color", UiTheme.SAFE if won else UiTheme.TEXT_SECONDARY)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(line)

	# ⚠️ The named champion is the point of the climb, so say what happened to them BEFORE the
	# money. A first title reads differently from a defence, and both read differently from a loss.
	var champ: Dictionary = out.get("champion", {})
	if not champ.is_empty():
		var champ_msg := ""
		if bool(out.get("firstTitle", false)):
			champ_msg = "You have taken the title off %s, %s." % [str(champ.get("name", "")), str(champ.get("title", ""))]
		elif bool(out.get("championBeaten", false)):
			champ_msg = "%s falls again. The title stays with you." % str(champ.get("name", ""))
		else:
			champ_msg = "%s keeps the title. Come back when you can answer them." % str(champ.get("name", ""))
		var cl := UiTheme.body_text(champ_msg, "primary")
		cl.add_theme_color_override("font_color",
			UiTheme.GOLD if bool(out.get("championBeaten", false)) else UiTheme.TEXT_SECONDARY)
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(cl)

	# ⚠️ Say what the trip cost next to what it paid. A cup is now the most expensive single
	# action in the game in the currency that matters — weeks — and a player who cannot see the
	# bill cannot learn to weigh it.
	var weeks: int = int(out.get("weeks", 0))
	if weeks > 0:
		col.add_child(UiTheme.body_text(
			"%d week%s on the road. It is now week %d." % [weeks, "" if weeks == 1 else "s", Career.week],
			"secondary"))

	var purse_line := UiTheme.body_text("Purse: %d gold  (%s pays %d%%)" % [
		purse, Career.placement_label(placement), int(round(frac * 100.0))], "primary")
	purse_line.add_theme_color_override("font_color", UiTheme.GOLD)
	col.add_child(purse_line)

	if bool(out.get("gameWon", false)):
		var w := UiTheme.heading("TAMERS APEX TAKEN — you have finished the Circuit.", 2)
		w.add_theme_color_override("font_color", UiTheme.GOLD)
		col.add_child(w)
		## ⚠️ THE ROUTE TO THE ENDING, AND IT IS A BUTTON RATHER THAN A JUMP. Before round 17 the
		## ship target of this project ended by setting a bool no screen read (`career.gd:1220`;
		## `won_game` had zero readers in `scripts/ui/`). It ends on a screen now — but the cup
		## panel this sits in is the account of the fight that won it, so navigating automatically
		## would delete the thing the player is reading. `town_ui.gd`'s arrival check remains the
		## fallback for a save loaded after the fact.
		if ResourceLoader.exists("res://scenes/ending.tscn"):
			var end_btn := Button.new()
			end_btn.text = "See how you finished →"
			end_btn.tooltip_text = "Your graded result: how fast you took the Circuit, and against whose pace."
			end_btn.focus_mode = Control.FOCUS_ALL
			end_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ending.tscn"))
			col.add_child(end_btn)
	elif bool(out.get("promoted", false)):
		var p := UiTheme.heading("PROMOTED — %s to %s" % [before_league, Career.current_league_name()], 3)
		p.add_theme_color_override("font_color", UiTheme.GOLD)
		col.add_child(p)
		col.add_child(UiTheme.body_text(
			"Your stat ceiling rises to %d. Everything you trained to the old cap can grow again."
			% int(Career.current_stat_cap()), "secondary"))
	elif not bool(out.get("swept", false)):
		## ⚠️ THIS LINE USED TO SAY "the title, and the rank, need the whole draw", WHICH IS NOW
		## TRUE ONLY AT TAMERS APEX. The rank and the title separated this round: everywhere else
		## you may drop one round of the draw and still be promoted. Copy that describes a rule the
		## game no longer has is worse than no copy at all — it teaches the player to read a loss
		## as a lottery, which is the exact thing splitting the rule was meant to end. It now says
		## the number out loud, from the outcome dict rather than from a second copy of the rule.
		var need: int = int(out.get("winsNeeded", Career.wins_needed_to_advance(idx, rival_count)))
		if need >= rival_count:
			col.add_child(UiTheme.body_text(
				"No promotion — nothing but the whole draw takes this title. Train, then come back.",
				"secondary"))
		else:
			col.add_child(UiTheme.body_text(
				"No promotion — the rank needs %d of %d rounds (you won %d); the title needs all %d. Train, then come back."
				% [need, rival_count, wins, rival_count], "secondary"))

	_result_box.add_child(panel)

	# ⚠️ Checkpoint AFTER the purse and the promotion have been applied. A cup is the longest
	# uninterruptible stretch in the game (three fights, three tactics screens); losing it to a
	# crash or a close would cost the player more than any other single action.
	if has_node("/root/SaveGame"):
		SaveGame.save_game()


