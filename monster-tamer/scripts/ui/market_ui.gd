## THE MARKET — recruit a new partner, or release one back.
##
## A deliberately SIMPLIFIED stand-in for `town.ts`'s real market (monthly stock, market scout,
## market coach — see docs/META_GAME_DISPOSITION.md §5, none of it ported yet). Rather than fake
## that system, this does the smallest REAL version: offers are generated deterministically off
## `Career.week` (drawn from the painted twelve in `Art.ROSTER` the player doesn't already own),
## and the recruit's price reads straight off its own generated stats via `Roster.market_price` — a
## recruit that looks better costs more for a legible reason, not an opaque roll. Buying spends
## real `Career.gold` and adds a real `MonsterInstance` to `Roster.monsters`; releasing removes it
## and refunds a fraction of the same value estimate. Offers stay put across a purchase within the
## same week (buying doesn't reshuffle the rest of the stock) and only regenerate when
## `Career.week` changes — which is what ties this to the Town hub's "End Week" button.
##
## UI built entirely in code, matching stable_ui.gd/training_ui.gd's established house style.
extends Control

## ⚠️ EVERY SIZE AND EVERY TEXT COLOUR ON THIS SCREEN COMES FROM HERE, AND THAT IS ROUND 19's WHOLE
## STYLE JOB. Round 18 landed the preload and stopped; `_probe_house.gd` still measured this screen
## at **42 labels off the type scale and 17 off the colour palette** — 91 labels in the game sat at
## 12px against an 18px accessibility floor and a third of them were on this file. That is an
## accessibility failure before it is a taste one, on a game that is ENTIRELY reading.
##
## The rule from here on (docs/UI_LAYOUT_RULES.md R7): no `add_theme_font_size_override` with a
## literal, no `Color(...)` on a Label. `UiTheme.body_text()` / `UiTheme.heading()` hand out both.
const UiTheme = preload("res://scripts/ui/theme.gd")

## Fallback cap, used ONLY if the Career autoload is missing (a standalone scene run). The real
## cap is `Career.barn_capacity` — town.ts:START_BARN is 2, and CLAUDE.md/CORE_LOOP_PORT.md are
## explicit that a two-slot barn is load-bearing, not a placeholder: it's what makes the first
## recruit a real decision instead of a formality.
const FALLBACK_BARN_CAPACITY := 2
const OFFER_COUNT := 4

## ⚠️ THE OFFER RULES, THE PRICE FORMULA AND NOW THE ROSTER-GAP ANALYSIS ALL LIVE IN `roster.gd`
## AND MUST NOT COME BACK HERE. Three things buy monsters and only one of them is a screen: this
## UI, the career autopilot (`_probe_career_arc.gd`) and `_probe_recruit.gd`. While the rules lived
## in this file the other two carried hand-copied mirrors of them.
const RosterLib = preload("res://scripts/roster.gd")
const RELEASE_REFUND_FRAC := RosterLib.RELEASE_REFUND_FRAC
const WeekLib = preload("res://scripts/week.gd")

var gold_label: Label
var gaps_box: VBoxContainer
var offers_box: VBoxContainer
var release_box: VBoxContainer
var offer_rows: Array = []
var release_rows: Array = []

var offers: Array = []  # Array[Dictionary] {id, mi, price, grade, label}
var _gaps: Array = []    # Array[Dictionary] — `Roster.stable_gaps()`, re-read on every refresh
var _cached_week: int = -1


func _ready() -> void:
	_build_ui()
	_refresh()


func _build_ui() -> void:
	var tex := Art.area_texture("market")
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

	# The scrim is a FILL, not text — but it is still mixed from the palette's own base rather
	# than from a fourth invented near-black.
	var scrim := ColorRect.new()
	scrim.color = Color(UiTheme.SURFACE.r, UiTheme.SURFACE.g, UiTheme.SURFACE.b, 0.72)
	scrim.anchor_right = 1; scrim.anchor_bottom = 1
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	var root_margin := MarginContainer.new()
	root_margin.anchor_right = 1; root_margin.anchor_bottom = 1
	root_margin.add_theme_constant_override("margin_left", UiTheme.SPACE_XL)
	root_margin.add_theme_constant_override("margin_top", UiTheme.SPACE_XL)
	root_margin.add_theme_constant_override("margin_right", UiTheme.SPACE_XL)
	root_margin.add_theme_constant_override("margin_bottom", UiTheme.SPACE_XL)
	add_child(root_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", UiTheme.SPACE_LG)
	root_margin.add_child(vbox)

	# ---- header ----
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UiTheme.SPACE_LG)
	vbox.add_child(header)

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_col)
	title_col.add_child(UiTheme.heading("The Market"))
	title_col.add_child(UiTheme.body_text(
		"Prospects are cheap, raw and keep their full ceiling. Veterans can play today — and never "
		+ "train past it. Choose which season you are buying for.", "secondary"))

	gold_label = UiTheme.body_text("", "primary")
	gold_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	gold_label.add_theme_color_override("font_color", UiTheme.GOLD)
	gold_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(gold_label)

	var back_btn := Button.new()
	back_btn.text = "← Town"
	back_btn.focus_mode = Control.FOCUS_ALL
	back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/town.tscn"))
	header.add_child(back_btn)

	# ---- what the stable lacks ----
	vbox.add_child(_gaps_panel())

	var hsplit := HBoxContainer.new()
	hsplit.add_theme_constant_override("separation", UiTheme.SPACE_XL)
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(hsplit)

	# ---- left: recruits ----
	var left_col := VBoxContainer.new()
	left_col.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_child(left_col)
	left_col.add_child(UiTheme.heading("This week's recruits", 2))

	var offers_scroll := ScrollContainer.new()
	offers_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	offers_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_col.add_child(offers_scroll)

	offers_box = VBoxContainer.new()
	offers_box.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	offers_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offers_scroll.add_child(offers_box)

	# ---- right: release ----
	var right_col := VBoxContainer.new()
	right_col.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_child(right_col)
	right_col.add_child(UiTheme.heading("Your stable", 2))
	right_col.add_child(UiTheme.body_text(
		"The same six lines as the recruit cards, so the trade reads across. Releasing is "
		+ "permanent and refunds %d%% of the body's value." % int(round(RELEASE_REFUND_FRAC * 100.0)),
		"muted"))

	var release_scroll := ScrollContainer.new()
	release_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	release_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_col.add_child(release_scroll)

	release_box = VBoxContainer.new()
	release_box.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	release_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	release_scroll.add_child(release_box)


func _refresh() -> void:
	var current_week := (Career.week if has_node("/root/Career") else 1)
	if offers.is_empty() or _cached_week != current_week:
		_generate_offers()
		_cached_week = current_week
	# ⚠️ RE-READ, NEVER CACHE. Buying or releasing changes the answer, and a stale gap panel above a
	# live stall is exactly the rule-(1) lie this project has now shipped three times.
	_gaps = Roster.stable_gaps() if has_node("/root/Roster") else []
	_render_gaps()
	_render_offers()
	_render_release()
	_refresh_gold()


## Deterministic per-week stock — one call, because the rules live in `roster.gd` now.
func _generate_offers() -> void:
	offers.clear()
	var week := (Career.week if has_node("/root/Career") else 1)
	for o in Roster.market_offers(week, OFFER_COUNT):
		o["id"] = o["mi"].species_id
		offers.append(o)


# =============================================================================
# WHAT YOUR STABLE LACKS
#
# ⚠️ THIS IS THE DEFECT THAT MADE THE REST OF THE SCREEN POINTLESS, AND IT WAS NOT A LAYOUT ONE.
# Both columns were already honest and already comparable (round 18's B5) — and the decision was
# still made in a vacuum, because nothing anywhere in the game told the player what their roster
# was MISSING. "Which of these four should I buy" had no anchor, so a screen full of accurate
# numbers still could not be reasoned about. CLAUDE.md: *"knowing WHICH monster to make is the
# skill"* — a market that cannot state the question is not asking for that skill, it is asking for
# a coin flip with a price tag.
#
# ⚠️ THE ANALYSIS IS `Roster.stable_gaps()`, NOT A METHOD ON THIS SCREEN. One function, so the Town
# hub's prompt line, the Tournament sign-up and the Lab can ask the same question and get the same
# answer — see the long note above it. A second copy on a second screen is precisely how the
# 400-vs-540 ceiling contradiction reached a third screen before anyone compared them.
#
# ⚠️ AND IT NAMES THE GAP WITHOUT NAMING A PURCHASE. No offer is scored, ranked, starred or
# recommended; a candidate is only ever tagged with the FACT that its class is one the gap named.
# A screen that thinks for the player fails the same test as a training week that is an obvious
# click, and it would delete the one genuinely strategic purchase in the game.
# =============================================================================

func _gaps_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default", UiTheme.BORDER))
	gaps_box = VBoxContainer.new()
	gaps_box.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(gaps_box)
	return panel


func _render_gaps() -> void:
	for c in gaps_box.get_children():
		c.queue_free()

	var head := UiTheme.body_text("What your stable lacks", "primary")
	head.add_theme_color_override("font_color", UiTheme.GOLD)
	gaps_box.add_child(head)

	if _gaps.is_empty():
		# ⚠️ AN EMPTY GAP LIST IS A RESULT, NOT A BLANK. It says which four questions were asked and
		# that all four passed — manufacturing a gap to fill the panel would be the screen lying.
		gaps_box.add_child(UiTheme.body_text(
			"Nothing this screen can name. You field enough bodies for this rung and the next, you "
			+ "hold damage and support, part of the answer to this league's champion, and bodies "
			+ "that can still train. Buy for a plan of your own, or don't buy.", "muted"))
		return

	for g in _gaps:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiTheme.SPACE_SM)
		gaps_box.add_child(row)

		# Severity is carried by a GLYPH as well as the colour — docs/ACCESSIBILITY.md: never
		# encode meaning in hue alone, and CAUTION/TEXT_SECONDARY are a colour pair some players
		# cannot separate.
		# ⚠️ `▸` (U+25B8) IS NOT IN THE PACKAGED FONT AND THE FIRST CAPTURE SHOWED IT AS A TOFU DOT.
		# `▲`/`▼`/`•` are the three the rest of the UI already renders (`UiTheme.delta_chip`); a
		# glyph that falls back is a glyph that carries no meaning, which defeats the entire point
		# of pairing it with the colour.
		var blocking: bool = int(g["severity"]) >= 2
		var mark := UiTheme.body_text("▲" if blocking else "•", "primary")
		mark.autowrap_mode = TextServer.AUTOWRAP_OFF
		mark.add_theme_color_override("font_color", UiTheme.CAUTION if blocking else UiTheme.TEXT_SECONDARY)
		row.add_child(mark)

		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)

		var title := UiTheme.body_text(str(g["headline"]), "primary")
		if blocking:
			title.add_theme_color_override("font_color", UiTheme.CAUTION)
		col.add_child(title)
		col.add_child(UiTheme.body_text(str(g["detail"]), "muted"))


func _render_offers() -> void:
	for c in offers_box.get_children():
		c.queue_free()
	offer_rows.clear()

	if offers.is_empty():
		offers_box.add_child(UiTheme.empty_state("Sold out",
			"Every body on this week's stall has been bought. The stock is drawn fresh when the "
			+ "week advances — end the week at the Town hub."))
		return

	var stable_full: bool = Roster.monsters.size() >= _barn_capacity()
	for o in offers:
		var row := _offer_row(o, stable_full)
		offers_box.add_child(row)
		offer_rows.append(row)
	_wire_vertical_focus(offer_rows)


func _offer_row(o: Dictionary, stable_full: bool) -> PanelContainer:
	var mi = o["mi"]
	var panel := _card_panel()

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	panel.add_child(hbox)

	# ⚠️ ~28px OF A SIXTY-FIVE-SPECIES PAINTED ROSTER, ON THE ONE SCREEN WHERE YOU CHOOSE A BODY.
	# Round 18's before-capture measured the recruit portraits at thumbnail size beside a wall of
	# 11px text; this is `UiTheme.portrait`, the shared one, at the ending screen's footprint.
	hbox.add_child(UiTheme.portrait(mi.species_id, mi.species_name, Vector2(96, 96), UiTheme.GOLD))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(col)

	var grade := str(o.get("grade", ""))
	var title := UiTheme.body_text("%s — %s" % [mi.species_name, str(o.get("label", ""))], "primary")
	title.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBHEADING)
	title.add_theme_color_override("font_color", _grade_colour(grade))
	col.add_child(title)

	_shared_body(col, mi)

	# ⚠️ ONLY EVER A FACT, NEVER AN ENDORSEMENT. This says "your gap list named this class"; it
	# does not say buy it, and it is silent for every body that answers nothing — which on most
	# weeks is all four.
	var fills: Array = Roster.gap_classes(mi, _gaps) if has_node("/root/Roster") else []
	if not fills.is_empty():
		var tag := UiTheme.body_text("• a %s is one of the classes named above: %s"
			% [mi.class_name_, ", ".join(PackedStringArray(fills))], "primary")
		tag.add_theme_color_override("font_color", UiTheme.GOLD)
		col.add_child(tag)

	# The one-line flavour is the recruit pitch; the full bestiary story lives on the stable
	# detail once the monster is yours.
	col.add_child(UiTheme.body_text(str(mi.flavour), "muted"))

	# ⚠️ THIS RENDERED AS FLAT BORDERLESS TEXT, NOT AS A BUTTON, until it was styled through the
	# shared builder — with the engine default against this screen's dark scrim, the single commit
	# action on the screen (spending real gold on a permanent roster change) read as a caption.
	var buy_btn := Button.new()
	buy_btn.text = "Recruit · %dg" % int(o["price"])
	buy_btn.focus_mode = Control.FOCUS_ALL
	buy_btn.custom_minimum_size = Vector2(150, 38)
	buy_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for state in ["normal", "hover", "pressed", "focus"]:
		buy_btn.add_theme_stylebox_override(state, UiTheme.button_stylebox("primary", state))
	var have_gold: bool = has_node("/root/Career") and Career.gold >= int(o["price"])
	# ⚠️ THE REASON GOES IN THE LABEL, NOT THE TOOLTIP, AND `shop_ui.gd` IS THE STANDARD.
	# The before-capture of this screen had all four Recruit buttons dead with the reason hidden in
	# a hover a keyboard player never makes — four grey buttons that simply looked broken.
	#
	# ⚠️ SHORT IN THE LABEL, WHOLE IN THE TOOLTIP, AND THE FIRST CAPTURE OF THIS CHANGE IS WHY.
	# The label started as the full sentence ("Barn full (5) — release a body first"), which is a
	# ~230px button in a ~530px column: it ate the width the card's text needed, wrapped four lines
	# into eight, and pushed the fourth recruit off the screen. A reason in the label is only better
	# than a tooltip while it does not cost the card the room to state its own numbers.
	if stable_full:
		UiTheme.disable_with_reason(buy_btn, "Barn full", true)
		buy_btn.tooltip_text = ("Your barn holds %d and it is full — release a body on the right, "
			+ "or buy a slot at the Ranch Shop.") % _barn_capacity()
	elif not have_gold:
		var short: int = int(o["price"]) - (Career.gold if has_node("/root/Career") else 0)
		UiTheme.disable_with_reason(buy_btn, "%dg short" % short, true)
		buy_btn.tooltip_text = "This body asks %dg and you hold %dg." % [
			int(o["price"]), (Career.gold if has_node("/root/Career") else 0)]
	else:
		buy_btn.pressed.connect(func(): _on_buy(o))
	hbox.add_child(buy_btn)

	return panel


## THE SIX LINES BOTH COLUMNS SHARE. ⚠️ ONE FUNCTION, DELIBERATELY — round 18 made the two sides
## carry the same fields by copying the format strings, and a copied format string is a
## contradiction with a delay on it. The actual question this screen asks is *is this recruit
## better than the body I would drop for it?*, and it is only answerable if both halves are
## rendered by the same code from the same sources.
func _shared_body(col: VBoxContainer, mi) -> void:
	# Class AND its composition role, because the gap panel above talks in roles.
	col.add_child(UiTheme.body_text("%s · %s · %s"
		% [mi.body, mi.class_name_, Classify.role_of_class(str(mi.class_name_))], "secondary"))

	# ⚠️ THE CEILING IS READ FROM `week.gd:stat_cap_for`, THE TICK'S OWN FUNCTION, NOT RE-DERIVED.
	# This screen once called the same ceiling 400 while the Stable's bars read 540 — both were
	# true of a different "max" and neither said which, which is why round 18 recorded it as a lie
	# rather than a rounding difference. `potential` MULTIPLIES the league cap, so the bloodline
	# factor is stated on the same line as the number it moves.
	# ⚠️ AND IT IS THE *CAP*, NOT THE CEILING — THE 400-vs-540 BUG SURVIVED ITS OWN FIX.
	# Round 19 moved this line onto `stat_cap_for` and called the result "ceiling 400 per stat",
	# while the Stable's bars for the same body read "/ 540". `week.gd:stat_cap_for`'s own header
	# says it in as many words: "THIS IS THE *NOMINAL* CEILING… the ceiling a drill is actually
	# clamped against is `stat_ceiling()`". So the number was right, the WORD was wrong, and the
	# contradiction the round set out to kill was still on the screen in the capture — the third
	# venue for the same bug, found by putting the two captures side by side.
	# Both numbers now appear, in the Stable's own vocabulary, so the two screens read alike.
	var cap: float = WeekLib.stat_cap_for(mi, GameData.stat_cap())
	var ceil_top: float = WeekLib.stat_ceiling(mi, GameData.stat_cap(), _top_stat(mi))
	# ⚠️ AND IT IS ONE LINE, NOT TWO. The first version spelled the trade out on the card — "may
	# push one stat to 540 by leaving the room unspent elsewhere" — which wrapped on all nine cards
	# and pushed the fourth recruit off the fold. Nine repetitions of the same explanation is not
	# nine explanations; the two NUMBERS are what the comparison needs and the sentence lives in
	# the tooltip, where it is read once.
	var cap_txt := "now %d mean · cap %d per stat (bloodline ×%.2f)" % [
		int(round(_mean_stat(mi))), int(round(cap)), mi.potential]
	if ceil_top > cap + 0.5:
		cap_txt += " · one stat to %d" % int(round(ceil_top))
	var cap_lbl := UiTheme.body_text(cap_txt, "primary")
	cap_lbl.tooltip_text = ("%d is the rung's cap on every stat, and promotion is what moves it. "
		+ "A body may push ONE stat as far as %d by leaving that room unspent on the other five — "
		+ "the same ceiling the Stable's bars are drawn against, and the one the weekly tick clamps to."
		) % [int(round(cap)), int(round(ceil_top))]
	col.add_child(cap_lbl)

	# ⚠️ WORD FOR WORD THE STABLE'S LIFE-ARC LINE (`stable_ui.gd:_condition_section`), from the
	# same `week.gd:stage_info`. It appears identically on the hub, the stable, the training header
	# and the week's ledger; the market said "6y left of 8y" instead, which was a fifth phrasing of
	# a fact four screens already agreed on. What the player is buying at this stall IS the clock.
	var info: Dictionary = WeekLib.stage_info(mi.age_weeks, mi.lifespan_years)
	var span_weeks: int = int(round(float(mi.lifespan_years) * float(WeekLib.WEEKS_PER_YEAR)))
	col.add_child(UiTheme.body_text("%s — %.1f of %.1f years · training ×%.2f · %d weeks of career left"
		% [str(info.get("stage", "?")), float(mi.age_weeks) / float(WeekLib.WEEKS_PER_YEAR),
			float(mi.lifespan_years), float(info.get("trainMult", 1.0)),
			maxi(0, span_weeks - int(mi.age_weeks))], "muted"))

	col.add_child(UiTheme.body_text(_aptitude_line(mi), "secondary"))


## The species' authored training profile, plus the class its aptitude pair points at. ⚠️ Read from
## `week.gd:training_profile`/`stat_training_bonus` — the tick's own functions — so this row can
## never disagree with the drills it is advising about.
##
## ⚠️ THE CLASS DECISION IS MADE AT THE MARKET, NOT AT THE STABLE, and it was invisible here until
## round 18. Two recruits with identical stats and identical prices can be a 1.20x and a 0.80x on
## the same stat, and the player found out weeks later. The class NAME is a suggestion from
## aptitude, never a lock — any species can train into any class.
func _aptitude_line(mi) -> String:
	var prof: Dictionary = WeekLib.training_profile(mi)
	var major := str(prof.get("major", ""))
	var minor := str(prof.get("minor", ""))
	var flaw := str(prof.get("flaw", ""))
	var parts: Array = []
	if major != "":
		parts.append("%s ×%.2f" % [major, WeekLib.stat_training_bonus(mi, major)])
	if minor != "" and minor != major:
		parts.append("%s ×%.2f" % [minor, WeekLib.stat_training_bonus(mi, minor)])
	if flaw != "":
		parts.append("%s ×%.2f" % [flaw, WeekLib.stat_training_bonus(mi, flaw)])
	var suits := _class_for_pair(major, minor)
	if suits == "":
		suits = _class_for_pair(minor, major)
	var tail := ("  →  trains toward %s" % suits) if suits != "" else ""
	if parts.is_empty():
		return "no authored training aptitude"
	return "trains: %s%s" % [", ".join(PackedStringArray(parts)), tail]


func _class_for_pair(primary: String, secondary: String) -> String:
	if primary == "" or secondary == "" or primary == secondary:
		return ""
	for c in GameData.classes:
		if str(c.get("primary", "")) == primary and str(c.get("secondary", "")) == secondary:
			return str(c.get("name", ""))
	return ""


func _barn_capacity() -> int:
	return Career.barn_capacity if has_node("/root/Career") else FALLBACK_BARN_CAPACITY


## Removes the bought offer from the CURRENT session's list rather than regenerating the whole
## stock — buying one recruit shouldn't reshuffle everyone else standing next to it. The full list
## only regenerates once `Career.week` actually advances (see `_refresh`).
func _on_buy(o: Dictionary) -> void:
	if not has_node("/root/Career") or not has_node("/root/Roster"):
		return
	if Roster.monsters.size() >= _barn_capacity():
		return
	if not Career.spend_gold(int(o["price"])):
		return
	# ⚠️ A RECRUIT NEEDS A CAREER-SLOT ID BEFORE IT ENTERS THE STABLE. `GameData.make_monster()`
	# leaves `id` empty, and `week_plan.gd` keys every plan by it while `week.gd` seeds the
	# training roll off it — so two market recruits with the same empty id shared one plan slot
	# and one RNG stream. See `roster.gd:next_slot_id()`.
	o["mi"].id = Roster.next_slot_id()
	Roster.monsters.append(o["mi"])
	offers.erase(o)
	_refresh()


## Grade colour, from the PALETTE rather than from three invented hues (the veteran orange was
## Δ0.18 off GOLD, the journeyman blue Δ0.35 off TEXT_PRIMARY — near enough to read as mistakes,
## far enough to be a fourth and fifth accent nothing else in the game used).
##
## ⚠️ Hue is a SECOND channel here, never the only one — the grade is spelled out in the title row
## as well (docs/ACCESSIBILITY.md: never encode meaning in colour alone). The mapping is not
## arbitrary either: SAFE is the body with everything ahead of it, CAUTION the one with a spent
## clock and a cut ceiling, STATUS_BUFF the one in between.
func _grade_colour(grade: String) -> Color:
	match grade:
		"veteran": return UiTheme.CAUTION
		"journeyman": return UiTheme.STATUS_BUFF
		_: return UiTheme.SAFE


## The body's leading stat — the one the spike ceiling is worth quoting against, because
## `week.gd:stat_ceiling` is per-stat and only the top one is anywhere near it.
func _top_stat(mi) -> String:
	var best := str(Classify.STATS[0])
	for s in Classify.STATS:
		if float(mi.stats.get(s, 0.0)) > float(mi.stats.get(best, 0.0)):
			best = str(s)
	return best


func _mean_stat(mi) -> float:
	var t := 0.0
	for s in Classify.STATS:
		t += float(mi.stats.get(s, 0.0))
	return t / float(Classify.STATS.size())


func _render_release() -> void:
	for c in release_box.get_children():
		c.queue_free()
	release_rows.clear()

	if not has_node("/root/Roster") or Roster.monsters.is_empty():
		release_box.add_child(UiTheme.empty_state("An empty barn",
			"You own no monsters yet. The stall on the left is the only way in — a body bought "
			+ "here is the first thing your stable ever fields."))
		return

	for mi in Roster.monsters:
		var row := _release_row(mi)
		release_box.add_child(row)
		release_rows.append(row)
	_wire_vertical_focus(release_rows)


func _release_row(mi) -> PanelContainer:
	var panel := _card_panel()

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	panel.add_child(hbox)

	hbox.add_child(UiTheme.portrait(mi.species_id, mi.species_name, Vector2(96, 96), UiTheme.GOLD))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(col)

	var title := UiTheme.body_text(str(mi.species_name), "primary")
	title.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBHEADING)
	col.add_child(title)

	_shared_body(col, mi)

	# ⚠️ THE COST OF RELEASING IS A GAP YOU MIGHT BE OPENING, and the first version of this line
	# COULD NOT FIRE. It asked `gap_classes()` — "is this body's class one of the missing ones?" —
	# which is false for every body you own by construction, because a gap only ever names classes
	# the stable owns none of. Authored and unreachable, in the round that quotes that failure.
	# `gaps_opened_by_releasing()` asks the counterfactual instead, which is the real question.
	var opens: Array = Roster.gaps_opened_by_releasing(mi)
	if not opens.is_empty():
		var warn := UiTheme.body_text("▲ releasing this body opens: %s"
			% ", ".join(PackedStringArray(opens)), "primary")
		warn.add_theme_color_override("font_color", UiTheme.CAUTION)
		col.add_child(warn)

	var refund := int(round(Roster.market_price(mi) * RELEASE_REFUND_FRAC))
	# The mirror of the Recruit button, and deliberately NOT "primary": releasing is the
	# irreversible half of the trade and should not compete for the eye with recruiting.
	var release_btn := Button.new()
	release_btn.text = "Release · +%dg" % refund
	release_btn.focus_mode = Control.FOCUS_ALL
	release_btn.custom_minimum_size = Vector2(150, 38)
	release_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for state in ["normal", "hover", "pressed", "focus"]:
		release_btn.add_theme_stylebox_override(state, UiTheme.button_stylebox("default", state))
	release_btn.tooltip_text = "%s leaves the stable for good." % mi.species_name
	release_btn.pressed.connect(func(): _on_release(mi, refund))
	hbox.add_child(release_btn)

	return panel


func _on_release(mi, refund: int) -> void:
	if not has_node("/root/Roster"):
		return
	Roster.monsters.erase(mi)
	if Roster.selected_index >= Roster.monsters.size():
		Roster.selected_index = maxi(0, Roster.monsters.size() - 1)
	if has_node("/root/Career"):
		Career.add_gold(refund)
	_refresh()


func _refresh_gold() -> void:
	if gold_label == null:
		return
	gold_label.text = "%d gold" % (Career.gold if has_node("/root/Career") else 0)


## ⚠️ ACCESSIBILITY (docs/ACCESSIBILITY.md #1 pattern, reused from stable_ui.gd) — explicit
## up/down focus neighbours between consecutive rows in a scrolled list, rather than trusting
## Godot's automatic spatial-neighbour search inside a ScrollContainer.
##
## ⚠️ IT FINDS THE BUTTON BY TYPE NOW, NOT BY CHILD INDEX. The old version read
## `row.get_child(0).get_child(count - 1)` and cast it — one extra line appended to a card's text
## column would have crashed the screen with a failed cast, which is a poor thing to leave under a
## file whose whole job this round was adding lines to cards.
func _wire_vertical_focus(rows: Array) -> void:
	var btns: Array = []
	for r in rows:
		var b := _row_button(r)
		if b != null:
			btns.append(b)
	for i in range(btns.size()):
		var btn: Button = btns[i]
		if i > 0:
			btn.focus_neighbor_top = btn.get_path_to(btns[i - 1])
		if i < btns.size() - 1:
			btn.focus_neighbor_bottom = btn.get_path_to(btns[i + 1])


func _row_button(row: Node) -> Button:
	for c in row.get_child(0).get_children():
		if c is Button:
			return c as Button
	return null


func _card_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default", UiTheme.BORDER))
	return panel
