## THE HOUSE-STYLE PROBE — walks every player-facing screen outside the arena and MEASURES the
## mechanical rules the project has already paid for, then saves the picture.
##
## ⚠️ RUN IT WITH A WINDOW, NEVER `--headless`: the dummy renderer returns blank images, so a
## headless run saves black rectangles and "passes" (the trap `_probe_read_shot.gd` warns about).
##
##   P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/_probe_house.tscn
##
## ── WHY THIS EXISTS ───────────────────────────────────────────────────────────────────────────
## `docs/UI_LAYOUT_RULES.md` and `docs/UI_THEME.md` were paid for — the clipping fix, "never a
## dead control with no explanation", "no nested scrolls", "don't invent a fifth grey". Every one
## of them is prose, and this project has watched a dozen invariants decay for exactly that
## reason. A rule nothing enforces is a rule that decays. These are the ones a machine CAN check:
##
##   R1  every screen's root scrolls
##   R2  the primary action is reachable without scrolling (pinned outside the scroll region)
##   R3  no disabled control without a stated reason — in the TOOLTIP **or in the LABEL**
##   R5  no nested scroll regions (depth > 1)
##   T1  no font size outside `UiTheme.TOKEN_FONT_SIZES`
##   T2  no text colour outside `UiTheme.TOKEN_TEXT_COLOURS`
##   T3  no font size below the 14px floor this theme ever hands out
##   C1  measured CONTRAST floors — the AA floors and the elevation ladder            (craft round)
##   C2  interactive-state DISTINCTNESS — hover/pressed/disabled separated from rest  (craft round)
##
## ⚠️ C1/C2 WERE ADDED BECAUSE A CRAFT ROUND CAN ONLY LOSE IN WAYS T1–T3 CANNOT SEE. T1–T3 count
## labels: they answer "did someone invent a sixth grey" and "is anything under 14px". Neither can
## answer "is this still readable" — a builder chasing depth can darken a fill, keep every token
## intact, score a clean row, and ship text at 4.2:1. Prettier and less readable is a LOSS, and
## before this round nothing in the repo could detect one. These two checks are the detector.
##
## ⚠️ AND THEY TAKE THEIR NUMBERS FROM `UiTheme.elevation_report()`, NEVER FROM A COPY. The
## published figures in `UI_THEME.md` §3 were already wrong in the third decimal (5.10/4.63 against
## a live 5.098/4.628), so a tripwire holding its own copy of the truth would have failed against
## an UNCHANGED theme and reported a phantom regression on the round's first diff. The floors below
## are the only constants here, and they are the *requirements*, not the measurements.
##
## ⚠️ WHAT IT DELIBERATELY DOES NOT DO IS JUDGE. Density, hierarchy, whether a screen is any GOOD
## — none of that is measurable and a probe that pretended otherwise would be worse than nothing.
## It measures, it saves a PNG, and a human reads the PNG. That division is the same one
## `_probe_screens.gd` draws and it is not an accident.
##
## ⚠️ R3 IS SCORED ON BOTH CHANNELS BECAUSE ROUND 18's PROBE GOT IT WRONG. `_probe_screens.gd`
## looked only at `tooltip_text` and flagged `shop_ui.gd`'s two locked buttons as violations —
## they carry "Locked — reach Iron league (you are Bronze)" in the VISIBLE LABEL, which is
## strictly better than a tooltip (a keyboard user never hovers). Scoring the better answer as a
## failure is how a guard trains people to ignore it.
extends Node

const UiTheme = preload("res://scripts/ui/theme.gd")

const OUT_DIR := "user://house/"

## Same walk a player takes, same fixture, same order as `_probe_screens.gd` — deliberately, so
## the two probes' rows line up and a regression can be attributed to a screen rather than to a
## difference in how it was set up.
const SCREENS := [
	{"n": "01_title",      "scene": "res://scenes/title.tscn",      "setup": ""},
	{"n": "02_town",       "scene": "res://scenes/town.tscn",       "setup": ""},
	{"n": "03_stable",     "scene": "res://scenes/stable.tscn",     "setup": ""},
	{"n": "04_training",   "scene": "res://scenes/training.tscn",   "setup": ""},
	{"n": "05_feeding",    "scene": "res://scenes/feeding.tscn",    "setup": "_setup_feeding"},
	{"n": "06_market",     "scene": "res://scenes/market.tscn",     "setup": ""},
	{"n": "07_shop",       "scene": "res://scenes/shop.tscn",       "setup": ""},
	{"n": "08_lab",        "scene": "res://scenes/lab.tscn",        "setup": "_setup_lab"},
	{"n": "09_breeding",   "scene": "res://scenes/breeding.tscn",   "setup": ""},
	{"n": "10_tournament", "scene": "res://scenes/tournament.tscn", "setup": ""},
	{"n": "11_tactics",    "scene": "res://scenes/tactics.tscn",    "setup": ""},
	{"n": "12_report",     "scene": "res://scenes/report.tscn",     "setup": ""},
	{"n": "13_ending",     "scene": "res://scenes/ending.tscn",     "setup": "_setup_ending"},
]

## ⚠️ THE WINDOW IS NOT THE VIEWPORT, AND `_probe_screens.gd` LEARNED THIS THE EXPENSIVE WAY.
## `project.godot` sets a 1920x1080 base viewport with `stretch/mode="canvas_items"`, so shrinking
## the WINDOW scales the canvas — layout still happens at the BASE size. Measure overflow against
## the base viewport; the small-window question is a LEGIBILITY one, which only a capture answers.
const WINDOW := Vector2i(1152, 648)

var _view_h: int = 1080
var _rows: Array = []
var _off_sizes: Dictionary = {}     # font size -> count, across every screen
var _off_colours: Dictionary = {}   # "r,g,b" -> count, across every screen


func _ready() -> void:
	DisplayServer.window_set_size(WINDOW)
	await get_tree().process_frame
	_view_h = int(get_viewport().get_visible_rect().size.y)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_setup_midcareer()
	for s in SCREENS:
		var setup: String = str(s["setup"])
		if setup != "":
			call(setup)
		await _capture(str(s["scene"]), str(s["n"]))

	_report()
	var craft_ok := _report_craft()
	get_tree().quit(0 if craft_ok else 1)


# ── C1/C2 — THE CRAFT TRIPWIRES ───────────────────────────────────────────────────────────────
#
# ⚠️ THE FLOORS BELOW ARE REQUIREMENTS, NOT OBSERVATIONS, AND THE DISTINCTION IS THE WHOLE POINT.
# Each is either a WCAG floor (4.5 for normal text, 3.0 for a non-text boundary) or a perceptual
# target this round committed to in `docs/POLISH_DIRECTION.md` §4.4. None was read off the theme
# and then written down as "what it happens to be" — that is a changelog, not a guard, and this
# project has already had to delete one instrument for exactly that (`UI_LAYOUT_RULES` R7).
#
# ⚠️ ONE FLOOR IS DELIBERATELY SET BELOW ITS MEASURED VALUE: `card_to_raised`. PANEL→PANEL_RAISED
# measures 1.101 and CANNOT be improved — lifting PANEL_RAISED to reach 1.16 drops TEXT_MUTED on it
# to 4.27, under the AA floor. It is listed as a WATCH rather than a floor so the number stays
# visible and nobody "fixes" it by spending the text budget. A guard that hides a known-unfixable
# number is how it gets fixed by someone who did not know.
const FLOORS := {
	# key                      floor   what it is
	"page_to_card":            1.16,  # a card must be separable from its page WITHOUT its border
	"control_on_card":         1.25,  # a button must read as a control sitting ON a card
	"btn_hover":               1.45,  # POLISH_DIRECTION §4.4
	"btn_pressed":             1.25,  # POLISH_DIRECTION §4.4 — plus the geometric check below
	"btn_disabled":            1.20,  # POLISH_DIRECTION §4.4 — a dead control must not look live
	"muted_on_panel":          4.50,  # WCAG AA, normal text
	"muted_on_raised":         4.50,  # WCAG AA — ⚠️ measures 4.628, only 0.13 of headroom
	"danger_on_surface":       4.50,  # WCAG AA — was 4.226, i.e. UNDER the floor before this round
	"border_edge":             1.30,  # the hairline must remain visible against the panel it edges
}

## Ratios that are watched and printed but not enforced, with the reason stated in one line so a
## future reader does not have to reconstruct why a visibly-low number is tolerated.
const WATCH := {
	"card_to_raised": "cannot rise — lifting PANEL_RAISED drops TEXT_MUTED on it to 4.27 (under AA)",
	"primary_on_page": "the call-to-action fill against the page; informational",
}


func _report_craft() -> bool:
	var e: Dictionary = UiTheme.elevation_report()
	var ok := true
	print("")
	print("=== C1/C2 CRAFT TRIPWIRES (measured live through UiTheme.elevation_report()) ===")
	var keys: Array = FLOORS.keys()
	keys.sort()
	for k in keys:
		var got: float = float(e[k])
		var floor_v: float = float(FLOORS[k])
		var pass_v: bool = got >= floor_v - 0.0005
		if not pass_v:
			ok = false
		print("  %-20s %7.3f : 1   floor %5.2f   %s" % [k, got, floor_v, "ok" if pass_v else "FAIL"])
	for k in WATCH.keys():
		print("  %-20s %7.3f : 1   (watch)      %s" % [k, float(e[k]), WATCH[k]])

	# C2's non-tonal half. ⚠️ CONTRAST ALONE CANNOT CARRY `pressed` AND THE ARITHMETIC SAYS SO:
	# darkening the resting fill all the way to pure black tops out around 1.37:1, so a click that
	# is only a tone change is a click that is barely acknowledged. The state has to be
	# GEOMETRICALLY different too — it drops its shadow and shifts its label down — and that is a
	# structural fact a probe can check exactly, unlike a ratio it can only compare.
	var n: StyleBoxFlat = UiTheme.button_stylebox("secondary", "normal")
	var p: StyleBoxFlat = UiTheme.button_stylebox("secondary", "pressed")
	var geom_ok: bool = bool(e["pressed_loses_lift"])
	var shift_ok: bool = p.content_margin_top > n.content_margin_top
	var size_ok: bool = is_equal_approx(
		n.content_margin_top + n.content_margin_bottom,
		p.content_margin_top + p.content_margin_bottom)
	if not (geom_ok and shift_ok and size_ok):
		ok = false
	print("  %-20s %s   pressed drops its shadow (%.0f -> %.0f)" % [
		"pressed_geometry", "ok" if geom_ok else "FAIL", n.shadow_size, p.shadow_size])
	print("  %-20s %s   pressed shifts content down (%.0f -> %.0f top)" % [
		"pressed_shift", "ok" if shift_ok else "FAIL", n.content_margin_top, p.content_margin_top])
	print("  %-20s %s   and total margin is unchanged, so nothing reflows on click" % [
		"pressed_no_reflow", "ok" if size_ok else "FAIL"])

	# ⚠️ ELEVATION IS INFORMATION — assert that it is RATIONED, not just present. A page where every
	# panel floats is exactly as flat as one where none do, so "default casts no shadow" is as much
	# a requirement as "raised does". This is the check that stops the next round undoing this one
	# by making everything pretty.
	var rungs := {"flat": 0, "default": 0, "interactive": UiTheme.ELEV_INTERACTIVE, "raised": UiTheme.ELEV_RAISED}
	for variant in rungs.keys():
		var sb: StyleBoxFlat = UiTheme.panel_style(variant)
		var want: int = int(rungs[variant])
		var got_lift: int = int(sb.shadow_size)
		if got_lift != want:
			ok = false
		print("  %-20s shadow %d (want %d)   %s" % [
			"panel:" + variant, got_lift, want, "ok" if got_lift == want else "FAIL"])

	print("")
	print("CRAFT: %s" % ("all floors held" if ok else "⚠ AT LEAST ONE FLOOR BROKEN — this is a LOSS, not a trade"))
	return ok


func _report() -> void:
	print("")
	print("=== HOUSE STYLE (window %dx%d, base viewport %d tall) ===" % [WINDOW.x, WINDOW.y, _view_h])
	print("                     R1     R2   |------- R3 disabled -------|   R5      T1/T3     T2      C3")
	print("screen             scroll pinned  n  tooltip  maybe  SILENT   nest   off-scale off-token  lifted")
	var tot := {"r1": 0, "r2": 0, "r3": 0, "maybe": 0, "r5": 0, "t1": 0, "t2": 0, "lift": 0, "lift_max": 0}
	for r in _rows:
		if not r["scrolls"]:
			tot["r1"] += 1
		if not r["pinned_action"]:
			tot["r2"] += 1
		tot["r3"] += int(r["silent_disabled"])
		tot["maybe"] += int(r["reason_maybe"])
		if int(r["max_nest"]) > 1:
			tot["r5"] += 1
		tot["t1"] += int(r["off_size"])
		tot["t2"] += int(r["off_colour"])
		tot["lift"] += int(r["lifted"])
		tot["lift_max"] = maxi(int(tot["lift_max"]), int(r["lifted"]))
		print("%-18s %5s %6s %4d %6d %7d %7d %6d %9d %8d %7d" % [
			r["n"],
			"yes" if r["scrolls"] else "NO",
			"yes" if r["pinned_action"] else "NO",
			int(r["disabled"]), int(r["reason_tip"]), int(r["reason_maybe"]),
			int(r["silent_disabled"]),
			int(r["max_nest"]),
			int(r["off_size"]),
			int(r["off_colour"]),
			int(r["lifted"]),
		])
	print("")
	print("TOTALS  R1 screens that do not scroll: %d · R2 screens with no pinned action: %d"
		% [tot["r1"], tot["r2"]])
	print("        R3 disabled with NO reason at all: %d · reason only guessed from the label: %d"
		% [tot["r3"], tot["maybe"]])
	print("        R5 screens with nested scrolls: %d" % tot["r5"])
	print("        T1/T3 labels at an off-scale size: %d · T2 labels at an off-token colour: %d"
		% [tot["t1"], tot["t2"]])
	# ⚠️ REPORTED, NEVER FAILED — see the C3 note in `_walk`. A screen at 1 is using the ladder as
	# intended; a screen at 5+ is claiming five primary things and needs a human to read its capture.
	print("        C3 panels claiming top elevation (\"raised\"): %d across %d screens · max on one screen: %d"
		% [tot["lift"], _rows.size(), tot["lift_max"]])

	print("")
	print("--- OFF-SCALE FONT SIZES (theme hands out %s) ---" % [UiTheme.TOKEN_FONT_SIZES])
	var sizes: Array = _off_sizes.keys()
	sizes.sort()
	for s in sizes:
		print("   %2dpx  x%-4d %s" % [int(s), int(_off_sizes[s]),
			"⚠ BELOW THE 14px FLOOR" if int(s) < UiTheme.SIZE_CAPTION else ""])

	print("")
	print("--- OFF-TOKEN TEXT COLOURS (theme publishes %d) ---" % UiTheme.TOKEN_TEXT_COLOURS.size())
	var pairs: Array = []
	for k in _off_colours.keys():
		pairs.append([int(_off_colours[k]), str(k)])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	print("   %d distinct invented colours in use" % pairs.size())
	for i in range(mini(20, pairs.size())):
		print("   x%-4d %s   (nearest token %s)" % [pairs[i][0], pairs[i][1], _nearest_token(pairs[i][1])])
	print("")
	print("captures: %s" % ProjectSettings.globalize_path(OUT_DIR))


func _nearest_token(key: String) -> String:
	var parts := key.split(",")
	if parts.size() < 3:
		return "?"
	var c := Color(float(parts[0]), float(parts[1]), float(parts[2]))
	var names := ["TEXT_PRIMARY", "TEXT_SECONDARY", "TEXT_MUTED", "GOLD", "SAFE", "CAUTION",
		"DANGER", "FOCUS", "STATUS_HARD_CONTROL", "STATUS_POISON", "STATUS_BURN", "STATUS_BLEED",
		"STATUS_DOOM", "STATUS_UTILITY", "STATUS_BUFF"]
	var best := ""
	var best_d := 9999.0
	for i in range(UiTheme.TOKEN_TEXT_COLOURS.size()):
		var t: Color = UiTheme.TOKEN_TEXT_COLOURS[i]
		var d: float = absf(t.r - c.r) + absf(t.g - c.g) + absf(t.b - c.b)
		if d < best_d:
			best_d = d
			best = names[i] if i < names.size() else "?"
	return "%s  Δ%.2f" % [best, best_d]


# ── THE FIXTURE ───────────────────────────────────────────────────────────────────────────────
# Identical to `_probe_screens.gd`'s, on purpose (see SCREENS above). Mid-career Bronze, week 130,
# five monsters at mixed ages — a fresh career hides every screen's density problem behind an
# empty roster.
func _setup_midcareer() -> void:
	Career.reset_new_game()
	Roster.reset_to_empty()
	Career.league_index = 3
	Career.week = 130
	Career.gold = 2400
	Career.barn_capacity = 5
	Career.leagues_won[0] = true
	Career.leagues_won[1] = true
	Career.leagues_won[2] = true
	Career.frontier_since_week = 108
	Career.frontier_cups = 3
	Career.frontier_rounds = 11
	Career.frontier_round_wins = 5

	var species := ["aegisox", "corvaan", "grivvel", "larkessa", "titanrex"]
	var ages := [2 * 48, 4 * 48, 5 * 48, 7 * 48, 1 * 48]
	for i in range(species.size()):
		var m = GameData.make_monster(species[i], 0.45 + 0.06 * i)
		# ⚠️ THE SLOT ID IS NOT OPTIONAL — `_probe_screens.gd` carries the full write-up. Skipping
		# it gives every monster the same empty key and the weekly report collapses to one entry.
		m.id = Roster.next_slot_id()
		m.age_weeks = ages[i]
		m.career_week = 40 + 12 * i
		m.stamina = 100.0 - 14.0 * i
		m.happiness = 7 - i
		Roster.monsters.append(m)
	Roster.selected_index = 0

	if has_node("/root/WeekPlan"):
		var booked := ["weights", "acrobatics", "meditation", "rest", "showmanship"]
		for i in range(Roster.monsters.size()):
			WeekPlan.set_activity(Roster.monsters[i].id, booked[i])


func _setup_feeding() -> void:
	var report: Dictionary = WeekPlan.advance(Roster.monsters)
	WeekPlan.set_meta("last_report", report)


func _setup_lab() -> void:
	Roster.monsters[3].retired = true
	if Roster.monsters.size() > 4:
		Roster.preserve(Roster.monsters[4])


func _setup_ending() -> void:
	Career.league_index = Career.leagues.size() - 1
	for i in range(Career.leagues_won.size()):
		Career.leagues_won[i] = true
	Career.leagues_won[4] = false
	Career.won_game = true
	Career.won_week = 372
	Career.week = 372
	Career.remove_meta("ending_seen")


# ── CAPTURE + MEASURE ─────────────────────────────────────────────────────────────────────────
func _capture(scene_path: String, screen_name: String) -> void:
	var packed = load(scene_path) as PackedScene
	if packed == null:
		printerr("MISSING SCENE: %s" % scene_path)
		return
	var node := packed.instantiate()
	add_child(node)
	for _i in 14:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR + screen_name + ".png")

	var r := {
		"n": screen_name, "scrolls": false, "pinned_action": false,
		"disabled": 0, "reason_tip": 0, "reason_maybe": 0, "silent_disabled": 0,
		"max_nest": 0, "off_size": 0, "off_colour": 0, "lifted": 0,
	}
	_walk(node, r, 0)
	_rows.append(r)

	node.queue_free()
	await get_tree().process_frame


func _walk(n: Node, r: Dictionary, scroll_depth: int) -> void:
	var depth := scroll_depth
	if n is ScrollContainer:
		r["scrolls"] = true
		# ⚠️ ONLY A SCROLL THAT COMPETES ON THE SAME AXIS IS A NESTING FAULT. R5 exists because two
		# scroll regions stacked under one cursor fight over the mouse wheel and the player cannot
		# tell which one will move. Two regions on DIFFERENT axes cannot do that — and counting
		# them anyway made this probe report a violation on `tactics_ui`, whose only inner scroller
		# is `deployment_board.gd`'s formation gallery: a horizontal strip
		# (`vertical_scroll_mode = DISABLED`) inside a vertical page (`horizontal = DISABLED`).
		# Orthogonal, unambiguous, and exactly the right control for a row of saved formations.
		#
		# Two rounds running this instrument scored a correct implementation as a fault (shop_ui's
		# in-label reasons was the other). That is how a guard stops being believed, so the check
		# is narrowed to the hazard it was written for rather than the shape it was easy to count.
		var sc := n as ScrollContainer
		if sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			depth += 1
			r["max_nest"] = maxi(int(r["max_nest"]), depth)

	if n is Button:
		var b := n as Button
		if b.disabled:
			r["disabled"] += 1
			# R3 — TWO CHANNELS, COUNTED SEPARATELY, AND NEITHER FOLDED INTO A SINGLE PASS/FAIL.
			# ⚠️ "THE LABEL STATES THE REASON" IS A SEMANTIC QUESTION AND A PROBE CANNOT ANSWER IT.
			# The tooltip check is exact — the string is either there or it is not. The label check
			# is a keyword HEURISTIC and is reported as `maybe`, never as a pass, because folding a
			# guess into a green number is precisely how a guard stops being believed. A row with a
			# high `maybe` needs a human to read the capture; that is the correct outcome, not a
			# silently clean total.
			var has_tip := b.tooltip_text.strip_edges() != ""
			var low := b.text.to_lower()
			var label_hints := low.contains("lock") or low.contains("need") \
				or low.contains("reach") or low.contains("requires") or low.contains("no ")
			if has_tip:
				r["reason_tip"] += 1
			elif label_hints:
				r["reason_maybe"] += 1
			else:
				r["silent_disabled"] += 1
		# R2 — a primary action pinned OUTSIDE every scroll region and inside the first viewport.
		# Heuristic and stated as one: a Button at scroll_depth 0 whose top edge sits above the
		# base viewport's bottom. It cannot know which button the screen considers primary, so it
		# answers the weaker, checkable question: is ANY action reachable without scrolling.
		if depth == 0 and not b.disabled and b.global_position.y < float(_view_h):
			r["pinned_action"] = true

	# C3 — HOW MANY THINGS ON THIS SCREEN CLAIM TO BE THE PRIMARY THING.
	#
	# ⚠️ THIS IS THE COUNTER-CHECK TO THE CRAFT ROUND, NOT A CELEBRATION OF IT. Elevation is
	# information: `raised` means "the one thing this page is about". A screen with seven raised
	# panels has said that seven times, which is the same as not saying it — a page where every
	# panel floats is exactly as flat as one where none do, and it is flat in a way that now also
	# costs GPU fill and visual noise. The first run of this counter found `panel_style("raised")`
	# at 32 call sites against `"interactive"` at ZERO, i.e. the four-rung ladder the theme
	# publishes is being used as two rungs, with every clickable card claiming top billing.
	#
	# It is reported, never failed. "Two raised panels" can be correct (a selected row inside a
	# selected section) and a probe cannot tell that from a mistake — this project has twice had an
	# instrument stop being believed by scoring a correct implementation as a fault. A high number
	# means READ THE CAPTURE, which is the right outcome.
	if n is Control:
		var c := n as Control
		if c.has_theme_stylebox_override("panel"):
			var sb := c.get_theme_stylebox("panel") as StyleBoxFlat
			if sb != null and sb.shadow_size >= UiTheme.ELEV_RAISED:
				r["lifted"] += 1

	if n is Label:
		var l := n as Label
		if l.has_theme_font_size_override("font_size"):
			var fs: int = l.get_theme_font_size("font_size")
			if not UiTheme.TOKEN_FONT_SIZES.has(fs):
				r["off_size"] += 1
				_off_sizes[fs] = int(_off_sizes.get(fs, 0)) + 1
		if l.has_theme_color_override("font_color"):
			var c: Color = l.get_theme_color("font_color")
			if not UiTheme.is_token_colour(c):
				r["off_colour"] += 1
				var key := "%.2f,%.2f,%.2f" % [c.r, c.g, c.b]
				_off_colours[key] = int(_off_colours.get(key, 0)) + 1

	for ch in n.get_children():
		_walk(ch, r, depth)
