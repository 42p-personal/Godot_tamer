## THE TOWN AND THE ECONOMY — capture the five screens of round 18's Builder B brief in the states
## that actually exercise them.
##
## ⚠️ WHY THIS EXISTS ALONGSIDE `_probe_screens.gd` RATHER THAN INSTEAD OF IT. The shared probe
## drives ONE career through all thirteen screens, which is the right instrument for "does the
## meta-game read as one game". But its `_setup_lab()` preserves exactly ONE monster — so the
## Breeding Ranch was captured in a state where a pairing is structurally impossible, the bequest
## card and the foal preview could not render at all, and `docs/META_UI_DIRECTION.md` read that
## capture as *"no preview of the foal"*. The preview was there; the fixture could not reach it.
##
## ⚠️ THAT IS THE GENERAL TRAP AND IT IS WORTH STATING ONCE: A SCREEN CAPTURED IN ITS EMPTY STATE
## LOOKS LIKE A SCREEN WITH NOTHING ON IT. Every fixture here is built to reach the DENSE state —
## two preserved parents, a retiree, a full barn, a mid-career purse — because the empty state is
## not what a player spends the game looking at.
##
## Run it with a window, NEVER `--headless` (the dummy renderer saves black rectangles and
## "passes" — the trap `_probe_screens.gd` documents):
##
##   P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/_probe_econ.tscn
##
## Writes user://econ/NN_<name>.png plus _end.png for anything past the fold, and prints the same
## three mechanical checks the shared probe measures (scrollable root, disabled controls that
## explain themselves, tallest content height).
extends Node

const OUT_DIR := "user://econ/"
const WINDOW := Vector2i(1152, 648)

const SCREENS := [
	{"n": "02_town",     "scene": "res://scenes/town.tscn"},
	{"n": "06_market",   "scene": "res://scenes/market.tscn"},
	{"n": "07_shop",     "scene": "res://scenes/shop.tscn"},
	{"n": "08_lab",      "scene": "res://scenes/lab.tscn"},
	# ⚠️ `post` DRIVES THE SCREEN INTO THE STATE IT EXISTS FOR BEFORE THE SHUTTER OPENS. A breeding
	# screen with no pairing selected is a stud book and nothing else — the bequest, the three
	# choices and the foal comparison are all downstream of picking two parents, and capturing the
	# unpicked state is what made the previous round conclude the preview did not exist.
	{"n": "09_breeding", "scene": "res://scenes/breeding.tscn", "post": "_pick_pair"},
]

var _view_h: int = 1080
var _rows: Array = []


func _ready() -> void:
	DisplayServer.window_set_size(WINDOW)
	await get_tree().process_frame
	_view_h = int(get_viewport().get_visible_rect().size.y)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	_setup()
	for s in SCREENS:
		await _capture(str(s["scene"]), str(s["n"]), str(s.get("post", "")))

	print("")
	print("=== TOWN/ECONOMY INVENTORY (window %dx%d, base viewport height %d) ==="
		% [WINDOW.x, WINDOW.y, _view_h])
	print("screen             ctrl  lbl  btn  disabled  no-reason  scrolls  content-h")
	for r in _rows:
		print("%-18s %4d %4d %4d %9d %10d %8s %10d" % [
			r["n"], r["controls"], r["labels"], r["buttons"], r["disabled"],
			r["silent_disabled"], "yes" if r["scrolls"] else "NO", r["content_h"]])
	print("")
	print("captures: %s" % ProjectSettings.globalize_path(OUT_DIR))
	get_tree().quit(0)


## The same Bronze / week-130 career the shared probe uses, so the two sets of captures are
## comparable — plus the two states it never reaches: a retiree still sitting in the barn, and TWO
## preserved parents, which is the minimum a pairing needs.
func _setup() -> void:
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

	# ⚠️ REAL IDS FROM `data/data.json` ONLY — `GameData.make_monster()` pushes an error and returns
	# null for an unknown one, and the next line then assigns `.id` on Nil. Two invented names cost
	# one run to find.
	var species := ["aegisox", "corvaan", "grivvel", "larkessa", "titanrex", "ursath", "tortavos"]
	var ages := [2 * 48, 4 * 48, 5 * 48, 7 * 48, 1 * 48, 6 * 48, 9 * 48]
	for i in range(species.size()):
		var m = GameData.make_monster(species[i], 0.45 + 0.06 * i)
		# ⚠️ THE SLOT ID IS NOT OPTIONAL — `GameData.make_monster()` returns `id == ""`, and every
		# shipped path assigns one immediately. Five monsters sharing one empty key made
		# `WeekPlan.advance()`'s per-monster snapshot report each other's numbers, and it cost the
		# previous round twenty minutes to diagnose from a capture. See `roster.gd:109`.
		m.id = Roster.next_slot_id()
		m.age_weeks = ages[i]
		m.career_week = 40 + 12 * i
		m.stamina = 100.0 - 14.0 * i
		m.happiness = 7 - i
		Roster.monsters.append(m)
	Roster.selected_index = 0

	var booked := ["weights", "acrobatics", "meditation", "rest", "showmanship"]
	for i in range(mini(booked.size(), Roster.monsters.size())):
		WeekPlan.set_activity(Roster.monsters[i].id, booked[i])

	# The last two go to the freezer — a pairing needs two, and one of them is retired so BOTH
	# billing branches (charged / enshrined free) render on the Lab.
	Roster.monsters[6].retired = true
	Roster.preserve(Roster.monsters[6])
	Roster.preserve(Roster.monsters[5])
	# And one retiree left IN the barn, which is the Lab's loudest state and the Town's top prompt.
	Roster.monsters[3].retired = true


## Select the two preserved parents and an emphasis, the way a player's clicks would — then let the
## screen rebuild itself through its own `_refresh()`. Nothing is constructed here; the capture must
## show what the screen's own code draws, not a mock of it.
func _pick_pair(node: Node) -> void:
	var stock: Array = Roster.breeding_stock()
	if stock.size() < 2:
		printerr("fixture failed: %d preserved, a pairing needs 2" % stock.size())
		return
	node._pick_a = stock[0]
	node._pick_b = stock[1]
	node._emphasis = "CON"
	node._refresh()


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
	get_viewport().get_texture().get_image().save_png(OUT_DIR + name + ".png")
	_rows.append(_inventory(node, name))

	var sc := _tallest_scroll(node)
	# ⚠️ TOP AND BOTTOM ARE NOT ENOUGH ON A SCREEN THREE VIEWPORTS TALL. The thing this round most
	# needed to look at on the Breeding Ranch — the parent/parent/foal comparison — sits in the
	# MIDDLE, so top-and-end captures would have missed it exactly the way the previous round's
	# fixture missed the preview altogether.
	if sc != null and sc.get_v_scroll_bar().max_value > sc.size.y * 1.5:
		for frac in [0.25, 0.5]:
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
	var r := {"n": name, "controls": 0, "labels": 0, "buttons": 0,
		"disabled": 0, "silent_disabled": 0, "scrolls": false, "content_h": 0}
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
			# ⚠️ WIDER THAN THE SHARED PROBE'S CHECK, ON PURPOSE. `_probe_screens.gd` counts a
			# disabled button with no TOOLTIP and flagged `shop_ui.gd`'s two licence rows — which
			# carry their reason in the LABEL (`"Locked — reach Iron league (you are Bronze)"`).
			# That is better than a tooltip, not worse, and the instrument was the thing at fault.
			# UI_LAYOUT_RULES rule 3 asks that a dead control say why, not where it says it.
			var says_why: bool = b.tooltip_text.strip_edges() != "" or b.text.length() > 24
			if not says_why:
				r["silent_disabled"] += 1
	for ch in n.get_children():
		_walk(ch, r)
