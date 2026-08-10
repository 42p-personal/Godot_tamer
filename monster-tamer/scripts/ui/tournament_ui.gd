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

	page.add_child(UiTheme.heading("Tournaments", 1))
	_header = UiTheme.body_text("", "secondary")
	page.add_child(_header)
	page.add_child(HSeparator.new())

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


func _cup_card(idx: int) -> Control:
	var panel := PanelContainer.new()
	var is_frontier: bool = idx == Career.league_index
	panel.add_theme_stylebox_override("panel",
		UiTheme.panel_style("raised", UiTheme.GOLD) if is_frontier else UiTheme.panel_style("default"))

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

	col.add_child(UiTheme.heading("%s Cup%s" % [lname, "  ·  your league" if is_frontier else ""], 3))

	# ── THE MARQUEE — the one week a year this rung is an EVENT ───────────────
	# ⚠️ The build had no calendar at all: every cup at every rung was identical and available
	# forever, so "which cup, and when" was never a question. Once a year, at each senior league,
	# it is. See `cup_run.gd:MARQUEE_LEAGUES`.
	if marquee:
		var m := UiTheme.heading("%s — the marquee, this month only" % CupRun.marquee_name(idx), 3)
		m.add_theme_color_override("font_color", UiTheme.GOLD)
		col.add_child(m)
		col.add_child(UiTheme.body_text(
			"A deeper draw (%d teams, one more than usual) and a purse worth %d%% of a normal cup. "
			% [rounds, int(round(CupRun.MARQUEE_PURSE_MULT * 100.0))]
			+ "Double entry, and one more team to sweep — the placing money is easier, the title is harder.",
			"secondary"))

	col.add_child(UiTheme.body_text(
		"%dv%d  ·  %d teams in the draw  ·  stat ceiling %d  ·  entry %dg  ·  winner's purse %dg" % [
			team_size, team_size, rounds, cap, fee, _purse_for(idx, marquee)], "secondary"))

	# ⚠️ SHORT-HANDED ENTRY MUST BE BILLED, NOT DISCOVERED. Entering a body down is now allowed
	# (`Career.SHORT_ENTRY_ALLOWANCE`) because being locked out was an invisible economy wall, but
	# a penalty the player only meets in the arena is not a decision — it is an ambush.
	## ⚠️ ONLY WHEN ENTRY IS ACTUALLY POSSIBLE. Below the minimum the card already carries
	## `entry_block_reason()`, and "you will fight 0 v 5" underneath "every monster has retired" is
	## two sentences competing to explain one state — the player reads the weaker one.
	if have < team_size and have >= Career.min_team_to_enter(idx) and have > 0:
		var short_line := UiTheme.body_text(
			"You will fight %d v %d — a body down, and outnumbered every round. The draw does not shrink to match you."
			% [mini(have, team_size), team_size], "primary")
		short_line.add_theme_color_override("font_color", UiTheme.CAUTION)
		short_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(short_line)

	# ⚠️ THE TRIP IS THE PRICE, AND IT MUST BE ON THE CARD. `docs/META_GAME_REVIEW.md` E2: the cup
	# path never touched `Career.week`, so gold per week of game time was infinite and the weekly
	# tick — the entire stable half — could be skipped by the one activity the game is about. A
	# cup now costs weeks, and a cost the player cannot see before paying is not a decision.
	var trip := UiTheme.body_text(
		"The trip costs %d week%s of game time — your stable ages, eats and rests on the road, but nobody trains."
		% [weeks, "" if weeks == 1 else "s"], "primary")
	trip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(trip)

	# ── THE SCOUT REPORT — THE BRACKET, ROUND BY ROUND ────────────────────────
	# ⚠️ THIS IS THE DECISION. `CLAUDE.md`: "Preparation is the skill; observation is the reward"
	# and "training and breeding are strategy, not maintenance". None of that is true if the
	# player cannot see what they are training FOR. The field is drawn off `Career.cup_field_seed()`
	# — stable for the game-month — so the arc shown here is the arc actually fought: scout it, go
	# and train against it, come back to the same opponents.
	#
	# ⚠️ AND IT IS A BRACKET NOW, NOT A HEADLINE. This used to print the opener and the final and
	# nothing between, which was an honest summary of a cup whose middle rounds did not matter:
	# measured at a 65%-filled roster, round one won 100% at all eleven leagues. `CupRun.round_fill`
	# redistributes the draw so every round is a fight; showing every round is what makes that
	# redistribution legible instead of merely true.
	# ⚠️ AND THE BRACKET NOW SAYS WHAT KIND OF TEAM EACH ROUND IS, NOT JUST HOW STRONG. Until this
	# round every rival came out of one generator and differed only by a fill fraction, so the
	# eleven authored champion reads were decoration and "knowing WHICH monster to make" had one
	# answer. A drawn field carries an archetype per round now (`Career.make_cup_field`), and the
	# strength bar alone would hide the only new information on the card.
	var drawn: Array = Career.make_cup_field(idx, rounds)
	for r in range(rounds):
		var f: float = CupRun.round_fill(r, rounds, idx)
		var is_last: bool = r == rounds - 1
		var who: String = "THE TITLE BOUT" if is_last else "Round %d" % (r + 1)
		var kind: String = String(drawn[r].get("archetype", "")) if r < drawn.size() else ""
		var line := UiTheme.body_text("   %-14s  %-9s  %3d%% of the %s ceiling   %s" % [
			who, kind, int(round(f * 100.0)), lname, _strength_bar(f)], "secondary")
		if is_last:
			line.add_theme_color_override("font_color", UiTheme.GOLD)
		col.add_child(line)

	var champ: Dictionary = Career.champion_for(idx)
	var beaten: bool = Career.has_beaten_champion(idx)
	var champ_line := UiTheme.body_text("Title held by %s, %s. %s" % [
		str(champ.get("name", "")), str(champ.get("title", "")), str(champ.get("read", ""))], "primary")
	champ_line.add_theme_color_override("font_color", UiTheme.GOLD if not beaten else UiTheme.TEXT_SECONDARY)
	champ_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(champ_line)
	if beaten:
		col.add_child(UiTheme.body_text(
			"You have taken this title off them before — they have trained since.", "muted"))

	# ⚠️ THE STANDINGS ARE THE OTHER HALF OF THE WAGER. Placement pays 100/65/40/0 (`career.gd:
	# PLACEMENT_REWARD_FRACTION`) and the screen never said so before entry, so a player weighing a
	# cup could only see the win. Now that entry costs gold AND weeks, "what does second pay" is
	# part of the decision, not a surprise on the way out.
	var ladder: Array = []
	for place in [1, 2, 3]:
		if place > rounds + 1:
			break
		ladder.append("%s %dg" % [Career.placement_label(place),
			int(round(float(_purse_for(idx, marquee)) * Career.placement_reward_fraction(place)))])
	col.add_child(UiTheme.body_text(
		"Standings pay: %s  ·  anything lower pays nothing." % "  ·  ".join(ladder), "secondary"))

	# ⚠️ State the sweep rule BEFORE entry. Promotion on a sweep is a hard gate and the player
	# must be able to weigh it, not discover it by losing.
	if is_frontier:
		## ⚠️ SAY THE NUMBER BEFORE THE FEE, NOT AFTER THE LOSS. This card used to promise "beat
		## all N", which was the old sweep gate; the rank and the title separated this round and a
		## sign-up screen that states the wrong gate is worse than one that states none — the
		## player prices the wager wrong and reads a promotion they DID earn as luck. Read from
		## `Career.wins_needed_to_advance()`, the same function the outcome uses, so there is one
		## rule and no copy of it.
		var need: int = Career.wins_needed_to_advance(idx, rounds)
		var promo_text: String = "Beat all %d and the title — and the rank — are yours." % rounds if need >= rounds \
			else "Win %d of the %d rounds and the RANK is yours; take all %d and so is the TITLE." % [need, rounds, rounds]
		var promo := UiTheme.body_text(
			promo_text + " Fall short and you place, and are paid to place.", "primary")
		promo.add_theme_color_override("font_color", UiTheme.GOLD)
		promo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(promo)
	else:
		col.add_child(UiTheme.body_text(
			"Already cleared — pays %d%% for punching down." % int(REWARD_BY_DROP[
				clampi(Career.league_index - idx, 0, REWARD_BY_DROP.size() - 1)] * 100.0), "muted"))

	## ⚠️ A LOCKED DOOR MUST SAY WHY, AND "you have 4" WHEN THE PLAYER CAN SEE FOUR MONSTERS IS A
	## LIE. `UI_LAYOUT_RULES.md` rule 2 forbids a dead control with no explanation, and the retiree
	## case is precisely the one where the old copy was actively misleading — the stable screen shows
	## four bodies and this button would have said "you have 0". `Roster.entry_block_reason()` is the
	## one function that names the cause and the move, shared with `tactics_ui.gd`.
	var blocked: String = Roster.entry_block_reason(Career.min_team_to_enter(idx))
	if blocked != "":
		var why := UiTheme.body_text(blocked, "primary")
		why.add_theme_color_override("font_color", UiTheme.CAUTION)
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(why)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 38)
	btn.focus_mode = Control.FOCUS_ALL
	if blocked != "":
		btn.disabled = true
		btn.text = "Cannot enter — %d of %d can still compete" % [have, Roster.monsters.size()]
	elif Career.gold < fee:
		btn.disabled = true
		btn.text = "Entry is %dg — you have %dg" % [fee, Career.gold]
	elif fee <= 0:
		btn.text = "Enter the %s Cup  ·  entry waived  ·  %d week%s" % [lname, weeks, "" if weeks == 1 else "s"]
		btn.pressed.connect(_on_enter.bind(idx))
	else:
		btn.text = "Enter the %s Cup  ·  %dg  ·  %d week%s" % [lname, fee, weeks, "" if weeks == 1 else "s"]
		btn.pressed.connect(_on_enter.bind(idx))
	col.add_child(btn)
	return panel


## A five-cell bar so the bracket reads as a shape at a glance, not as seven percentages. Scaled
## against the ceiling the fills are already expressed in, so it needs no second unit.
func _strength_bar(fill: float) -> String:
	var cells: int = clampi(int(round(fill * 5.0)), 1, 5)
	return "[%s%s]" % ["#".repeat(cells), "·".repeat(5 - cells)]


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


