## LOOK AT THE WHOLE META-GAME AT ONCE — every player-facing screen outside the arena, driven
## into ONE representative mid-career state, captured as a PNG.
##
## ⚠️ RUN IT WITH A WINDOW, NEVER `--headless`: the dummy renderer returns blank images, so a
## headless run saves black rectangles and "passes" (the trap `_probe_read_shot.gd` warns about).
##
##   P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/_probe_screens.tscn
##
## Writes user://screens/NN_<name>.png, one per screen, plus a printed inventory per screen:
## control count, label count, button count, how many buttons are DISABLED, how many disabled
## buttons carry a tooltip (UI_LAYOUT_RULES rule 3 — a dead control must say why), whether the
## root scrolls (rule 1), and the tallest content height against the viewport (rule 4, clipping).
##
## ── WHY A SINGLE SHARED STATE ─────────────────────────────────────────────────────────────────
## Every one of these screens has been built by a different stream against a different fixture.
## Capturing them under ONE career — same week, same gold, same five monsters, same league — is
## the only way to ask the question this round is actually about: does the meta-game read as one
## game, or as thirteen screens that happen to share an autoload?
##
## ⚠️ THE HARNESS ASSERTS NOTHING ABOUT TASTE. It measures the three mechanical rules the project
## has already paid for (scrollable root, no dead control without a reason, fits at the small
## size) and then SAVES THE PICTURE. The judgement is made by reading the pictures back, not by
## this file.
extends Node

const OUT_DIR := "user://screens/"

## Every player-facing screen outside the arena, in loop order — the walk a player actually takes.
## `setup` names a method on this node run immediately before the scene is instantiated, so a
## screen that needs a particular career shape (a live cup, a full barn) gets it without the
## other screens inheriting it.
const SCREENS := [
	{"n": "01_title",      "scene": "res://scenes/title.tscn",      "setup": ""},
	{"n": "02_town",       "scene": "res://scenes/town.tscn",       "setup": ""},
	{"n": "03_stable",     "scene": "res://scenes/stable.tscn",     "setup": ""},
	{"n": "04_training",   "scene": "res://scenes/training.tscn",   "setup": ""},
	{"n": "05_feeding",    "scene": "res://scenes/feeding.tscn",    "setup": "_setup_feeding"},
	{"n": "06_market",     "scene": "res://scenes/market.tscn",     "setup": ""},
	{"n": "07_shop",       "scene": "res://scenes/shop.tscn",       "setup": ""},
	{"n": "08_lab",        "scene": "res://scenes/lab.tscn",        "setup": "_setup_lab"},
	{"n": "09_breeding",   "scene": "res://scenes/breeding.tscn",   "setup": "",
		"post": "_pick_pair"},
	{"n": "10_tournament", "scene": "res://scenes/tournament.tscn", "setup": ""},
	{"n": "11_tactics",    "scene": "res://scenes/tactics.tscn",    "setup": ""},
	{"n": "12_report",     "scene": "res://scenes/report.tscn",     "setup": ""},
	{"n": "13_ending",     "scene": "res://scenes/ending.tscn",     "setup": "_setup_ending"},
]

## ⚠️ THE WINDOW IS NOT THE VIEWPORT HERE, AND THE FIRST RUN OF THIS PROBE GOT IT WRONG.
## `project.godot` sets a 1920x1080 base viewport with `stretch/mode="canvas_items"`, so shrinking
## the WINDOW to 1152x648 scales the whole canvas down — every screen reported content height
## exactly 1080 and every screen was flagged "CLIPS", which is the instrument lying, not thirteen
## broken screens. Layout happens at the BASE viewport size regardless of the window, so that is
## what a content-height overflow must be measured against. The small-size check
## (`UI_LAYOUT_RULES` rule 4) survives as a legibility question — text gets 60% smaller — not as a
## clipping one, and a probe cannot judge legibility. That is what the captures are for.
const WINDOW := Vector2i(1152, 648)

var _view_h: int = 1080
var _rows: Array = []


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
		await _capture(str(s["scene"]), str(s["n"]), str(s.get("post", "")))

	print("")
	print("=== SCREEN INVENTORY (window %dx%d, base viewport height %d) ==="
		% [WINDOW.x, WINDOW.y, _view_h])
	print("screen             ctrl  lbl  btn  disabled  no-reason  scrolls  content-h  clips")
	for r in _rows:
		print("%-18s %4d %4d %4d %9d %10d %8s %10d %6s" % [
			r["n"], r["controls"], r["labels"], r["buttons"], r["disabled"],
			r["silent_disabled"], "yes" if r["scrolls"] else "NO",
			r["content_h"], "CLIPS" if r["clips"] else "-"])
	print("")
	print("captures: %s" % ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit(0)


## ── THE FIXTURE ───────────────────────────────────────────────────────────────────────────────
## Mid-career: Bronze league (index 3), week 130, five monsters at mixed ages so the life arc is
## visible, one retired, one frozen, a plan booked, real gold. Deliberately NOT a fresh career —
## a new game hides every screen's density problem behind an empty roster.
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
		# ⚠️ THE FIXTURE MUST ASSIGN THE SLOT ID, AND THE FIRST RUN OF THIS PROBE DID NOT.
		# `GameData.make_monster()` returns a monster with `id == ""`; every shipped path that adds
		# one (market_ui, breeding_ui, lab_ui, save_game, roster.gd:109) assigns
		# `Roster.next_slot_id()` immediately, and roster.gd:109 carries the ⚠️ saying why. Skipping
		# it gave five monsters the SAME empty id, so `WeekPlan.advance()`'s per-monster `before`
		# dict — keyed by id — collapsed to one entry and the feeding screen reported every
		# monster's week diffed against a different monster's stats (a −119 DEX on a rest week).
		# That was the harness lying, not the game: the shipped paths are all correct. Recorded here
		# because the capture was read as a game bug for ten minutes, and the next person will too.
		m.id = Roster.next_slot_id()
		m.age_weeks = ages[i]
		m.career_week = 40 + 12 * i
		m.stamina = 100.0 - 14.0 * i
		m.happiness = 7 - i
		Roster.monsters.append(m)
	Roster.selected_index = 0

	# A booked week, so the Stable and Training screens are captured with a plan on them rather
	# than in their empty state — the empty state is not what a player spends the game looking at.
	if has_node("/root/WeekPlan"):
		# Real drill ids (week.gd:DRILLS). ⚠️ `drill_by_id()` falls back to DRILLS[0] for an
		# unknown id rather than failing, so a typo here silently books Weight Training.
		var booked := ["weights", "acrobatics", "meditation", "rest", "showmanship"]
		for i in range(Roster.monsters.size()):
			WeekPlan.set_activity(Roster.monsters[i].id, booked[i])


func _setup_feeding() -> void:
	# The feeding screen narrates a report the tick already produced — so run the real tick rather
	# than hand-building a report dict, or the capture shows a shape the game never emits.
	var report: Dictionary = WeekPlan.advance(Roster.monsters)
	WeekPlan.set_meta("last_report", report)


func _setup_lab() -> void:
	# One retiree in the barn and TWO bodies already preserved, so both halves of the Lab render AND
	# the breeding screen that follows has a legal pairing.
	#
	# ⚠️ THIS PRESERVED ONE UNTIL ROUND 18 AND THAT ONE-LINE FIXTURE BUG PRODUCED A WRONG BRIEF.
	# A pairing needs TWO preserved parents, so with one the breeding screen could only ever be
	# captured in its empty state — no pairing, no bequest, no foal preview. The round-18 direction
	# doc read that empty capture as "breeding shows no foal preview" and a whole builder brief was
	# written on it. The preview has existed all along. THE HARNESS MUST DRIVE A SCREEN INTO ITS
	# DENSE STATE, NOT ITS DEFAULT ONE — the empty state is not what a player looks at, and
	# capturing it produces confident findings about a screen nobody has seen.
	Roster.monsters[3].retired = true
	if Roster.monsters.size() > 4:
		Roster.preserve(Roster.monsters[4])
	if Roster.monsters.size() > 2:
		Roster.preserve(Roster.monsters[2])


func _setup_ending() -> void:
	Career.league_index = Career.leagues.size() - 1
	for i in range(Career.leagues_won.size()):
		Career.leagues_won[i] = true
	Career.leagues_won[4] = false
	Career.won_game = true
	Career.won_week = 372
	Career.week = 372
	Career.remove_meta("ending_seen")


## The Breeding Ranch's whole payload — the bequest card, the parent/parent/foal comparison, the
## emphasis tax — is downstream of a SELECTION. Captured unselected it is a stud book and nothing
## else, which is precisely the empty state that produced a wrong brief last round.
func _pick_pair(node) -> void:
	var stock: Array = Roster.breeding_stock()
	if stock.size() < 2:
		printerr("_pick_pair: only %d preserved — check _setup_lab()" % stock.size())
		return
	node._pick_a = stock[0]
	node._pick_b = stock[1]
	node._emphasis = "CON"
	node._refresh()


## ── CAPTURE + INVENTORY ───────────────────────────────────────────────────────────────────────
## `post` runs against the LIVE instantiated screen, after it has built itself, so a screen whose
## payload is gated behind a selection can be driven into that state before the shutter opens.
func _capture(scene_path: String, name: String, post: String = "") -> void:
	var packed = load(scene_path) as PackedScene
	if packed == null:
		printerr("MISSING SCENE: %s" % scene_path)
		return
	var node := packed.instantiate()
	add_child(node)
	await get_tree().process_frame
	if post != "":
		call(post, node)
	for _i in 14:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + name + ".png")
	_rows.append(_inventory(node, name))

	# ⚠️ THE FOLD IS WHERE THE ARGUMENT IS. A screen whose content is three viewports tall is not
	# judged by its first viewport — what got pushed below the fold IS the layout decision. So every
	# scrolling screen gets a second capture with its tallest scroll region run to the bottom.
	var sc := _tallest_scroll(node)
	# ⚠️ TOP AND END ARE NOT ENOUGH ON A SCREEN THREE VIEWPORTS TALL — the middle is exactly where
	# Breeding's parent/parent/foal comparison lives, and top-and-end would have missed it the same
	# way the one-preserved-parent fixture missed the preview altogether.
	if sc != null and sc.get_v_scroll_bar().max_value > sc.size.y * 1.5:
		for frac in [0.33, 0.66]:
			sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value * frac)
			for _i in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				OUT_DIR + "%s_mid%d.png" % [name, int(frac * 100)])
	if sc != null and sc.get_v_scroll_bar().max_value > sc.size.y + 8:
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
		for _i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OUT_DIR + name + "_end.png")

	node.queue_free()
	await get_tree().process_frame


func _tallest_scroll(n: Node) -> ScrollContainer:
	var best: ScrollContainer = null
	var stack: Array = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is ScrollContainer:
			var s := cur as ScrollContainer
			if best == null or s.get_v_scroll_bar().max_value > best.get_v_scroll_bar().max_value:
				best = s
		for c in cur.get_children():
			stack.append(c)
	return best


func _inventory(root: Node, name: String) -> Dictionary:
	var r := {
		"n": name, "controls": 0, "labels": 0, "buttons": 0,
		"disabled": 0, "silent_disabled": 0, "scrolls": false,
		"content_h": 0, "clips": false,
	}
	_walk(root, r)
	return r


func _walk(n: Node, r: Dictionary) -> void:
	if n is Control:
		r["controls"] += 1
		var c := n as Control
		r["content_h"] = maxi(int(r["content_h"]), int(c.position.y + c.size.y))
	if n is Label:
		r["labels"] += 1
	if n is ScrollContainer:
		r["scrolls"] = true
	if n is Button:
		r["buttons"] += 1
		var b := n as Button
		if b.disabled:
			r["disabled"] += 1
			# UI_LAYOUT_RULES rule 3: a disabled control must say why. There are TWO honest channels
			# and this check counted only one until round 18.
			#
			# ⚠️ IT SCORED THE BEST IMPLEMENTATION IN THE PROJECT AS A VIOLATION. shop_ui's licence
			# rows read "Locked — reach Iron league (you are Bronze)" in the BUTTON LABEL, which is
			# strictly better than a tooltip (a tooltip needs a hover the player has no reason to
			# make). Two rounds running, a builder had to explain that its cleanest screen was a
			# false positive. A guard that flags the right answer trains people to ignore the guard.
			#
			# So: a tooltip passes exactly; a label long enough to be a sentence passes as a GUESS.
			# The guess is not folded into the same number — `_probe_house.gd` reports it as `maybe`
			# and that is the right shape. Here we only need it not to lie, so a label carrying a
			# reason-word counts.
			var says_why := b.tooltip_text.strip_edges() != ""
			if not says_why:
				var t := b.text.to_lower()
				for w in ["locked", "reach", "need", "requires", "full", "not enough",
						"cannot", "can't", "no ", "already", "too "]:
					if t.contains(w):
						says_why = true
						break
			if not says_why:
				r["silent_disabled"] += 1
	if n is Control:
		var c2 := n as Control
		if c2.size.y > _view_h + 4 and not _has_scroll_ancestor(c2):
			r["clips"] = true
	for ch in n.get_children():
		_walk(ch, r)


func _has_scroll_ancestor(c: Control) -> bool:
	var p := c.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false
