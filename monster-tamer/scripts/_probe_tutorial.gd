## THE TUTORIAL PROBE — two things, and the second one is the new one.
##
## PART 1: THE STEP MACHINE. Drive the real flow and check each step advances on the BEHAVIOUR it
## teaches, not on a clock. The regression it guards: the stamina lesson used to be gated on
## `Career.week >= 3`, so `_advance_past_completed()` fast-forwarded straight past the single most
## important step in the tutorial for anyone who advanced three weeks before reading the banner.
##
## PART 2: THE GUIDE CANNOT COVER A CONTROL. This is the invariant that just broke — round 18's
## captures show the floating hint panel sitting on top of two Book buttons on Training — and a
## rule nothing enforces is a rule that decays. Every screen a tutorial step targets is
## instantiated, the guide is allowed to attach itself, and then EVERY interactive control on that
## screen is tested against the guide's rectangle. A hit is a FAILURE and the probe exits non-zero.
##
## ⚠️ IT ASSERTS "IN FLOW", NOT MERELY "NOT OVERLAPPING TODAY". A floating panel that happens to
## land on empty space passes an overlap test by luck and fails it the next time a screen grows a
## button — which is exactly the history here. So the probe also requires the guide element to be a
## DESCENDANT OF THE SCREEN, inside a layout container. That is the property that makes the overlap
## impossible rather than unlucky.
##
##   P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/_probe_tutorial.tscn
extends Node

## The screens a step can target (`where`) plus the ones that only ever show the pointer, so the
## rule is checked on the screens that HOST the guide and on the screens that merely mention it.
const SCREENS := [
	"res://scenes/town.tscn",
	"res://scenes/market.tscn",
	"res://scenes/training.tscn",
	"res://scenes/stable.tscn",
	"res://scenes/tournament.tscn",
	"res://scenes/feeding.tscn",
	"res://scenes/shop.tscn",
	"res://scenes/lab.tscn",
	"res://scenes/breeding.tscn",
]

var _fail := 0


func _ready() -> void:
	# ⚠️ A PROBE THAT CANNOT SEE THE GAME MUST SAY SO, NOT PASS. Run against a tree where an
	# autoload failed to compile (a concurrent edit mid-flight, most often) every call below
	# silently no-ops on a Nil base and this file printed "ALL CHECKS PASSED" under a screenful of
	# SCRIPT ERROR. That is the same failure as a blank capture, in a different medium.
	for req in ["Career", "Roster", "WeekPlan", "Tutorial", "TutorialOverlay"]:
		if not has_node("/root/%s" % req) or get_node("/root/%s" % req) == null:
			printerr("*** ABORT: autoload '%s' is missing — the tree did not load. " % req
				+ "Nothing below would have been measured.")
			get_tree().quit(2)
			return
	await _step_machine()
	await _overlap()
	print("")
	if _fail > 0:
		printerr("*** %d FAILURE(S)" % _fail)
		get_tree().quit(1)
		return
	print("=== ALL CHECKS PASSED ===")
	get_tree().quit(0)


func _step_machine() -> void:
	print("=== TUTORIAL STEP MACHINE ===\n")
	Career.reset_new_game(); Roster.reset_to_empty(); Tutorial.reset()
	print("  start                    -> %s" % Tutorial.current_id())
	Roster._generate_starting_roster()
	while Roster.monsters.size() > 1: Roster.monsters.pop_back()
	var m = Roster.monsters[0]
	Tutorial.poll(); print("  after buying             -> %s" % Tutorial.current_id())
	WeekPlan.set_food(m.id, "meat")
	Tutorial.poll(); print("  after choosing food      -> %s" % Tutorial.current_id())
	WeekPlan.set_activity(m.id, "weights")
	Tutorial.poll(); print("  after booking a drill    -> %s" % Tutorial.current_id())
	WeekPlan.advance(Roster.monsters)
	Tutorial.poll(); print("  after advancing a week   -> %s" % Tutorial.current_id())
	print("\n  --- the regression: burn 4 weeks WITHOUT ever resting ---")
	for i in range(4):
		WeekPlan.set_activity(m.id, "powerlift")
		WeekPlan.advance(Roster.monsters)
		Tutorial.poll()
	print("  week %d, stamina %.0f      -> %s" % [Career.week, m.stamina, Tutorial.current_id()])
	if Tutorial.current_id() == "stamina":
		print("  OK — the stamina lesson HELD. A week counter used to skip it entirely.")
	else:
		printerr("  *** FAIL: stamina step skipped again ***")
		_fail += 1
	WeekPlan.set_activity(m.id, "rest")
	Tutorial.poll(); print("  after booking a rest     -> %s" % Tutorial.current_id())
	await get_tree().process_frame


## ── PART 2 ────────────────────────────────────────────────────────────────────────────────────
func _overlap() -> void:
	print("\n=== THE GUIDE MUST NOT COVER A CONTROL ===")
	# A career the guide is actually live in: the tutorial must be ACTIVE or every screen below
	# passes trivially by having no guide on it at all — the check that measures nothing.
	Career.reset_new_game(); Roster.reset_to_empty(); Tutorial.reset()
	Roster._generate_starting_roster()
	Tutorial.poll()
	if not Tutorial.is_active():
		printerr("  *** FAIL: tutorial inactive — this check would measure nothing.")
		_fail += 1
		return
	print("  live step: '%s'\n" % Tutorial.current_id())
	print("  screen        guide  in-flow  controls  overlaps")

	for path in SCREENS:
		var packed := load(path) as PackedScene
		if packed == null:
			printerr("  MISSING SCENE: %s" % path)
			_fail += 1
			continue
		var node := packed.instantiate()
		add_child(node)
		# The overlay attaches on its own 10Hz poll and the containers then have to lay out; a
		# rectangle read before that is a rectangle of nothing.
		for _i in 24:
			await get_tree().process_frame

		var guides: Array = []
		_collect_guides(node, guides)
		# A guide element parented OUTSIDE the screen is the failure mode this replaced, so look
		# for one there too rather than reporting "no guide" and passing.
		var stray: Array = []
		_collect_guides(get_tree().root, stray)
		for g in stray:
			if not guides.has(g):
				guides.append(g)

		var controls: Array = []
		_collect_controls(node, controls)

		var in_flow := true
		var hits: Array = []
		for g in guides:
			var gc := g as Control
			if not node.is_ancestor_of(gc):
				in_flow = false
			var gr: Rect2 = gc.get_global_rect()
			for c in controls:
				var cc := c as Control
				if gc.is_ancestor_of(cc) or cc.is_ancestor_of(gc):
					continue  # the guide's own Skip button
				if not cc.is_visible_in_tree() or cc.size.x <= 0.0 or cc.size.y <= 0.0:
					continue
				if gr.intersects(cc.get_global_rect()):
					hits.append("%s '%s'" % [cc.get_class(), _label_of(cc)])

		var scr: String = path.get_file().get_basename()
		print("  %-13s %5d %8s %9d %9d" % [scr, guides.size(),
			("yes" if in_flow else "NO") if not guides.is_empty() else "-",
			controls.size(), hits.size()])
		if not guides.is_empty() and not in_flow:
			printerr("  *** FAIL %s: a guide element is not a descendant of the screen — it is "
				% scr + "floating over it, so it can cover a control the moment the layout moves.")
			_fail += 1
		for h in hits:
			printerr("  *** FAIL %s: the guide covers %s" % [scr, h])
		_fail += hits.size()

		node.queue_free()
		await get_tree().process_frame


func _collect_guides(n: Node, out: Array) -> void:
	if n is Control and n.is_in_group("guide_ui"):
		out.append(n)
		return  # its children are part of the guide, not separate elements
	for c in n.get_children():
		_collect_guides(c, out)


## Interactive controls only — a Label cannot be "covered" in the sense this rule cares about, and
## counting them would drown the real finding in noise.
func _collect_controls(n: Node, out: Array) -> void:
	if n is BaseButton or n is LineEdit or n is Slider or n is OptionButton or n is ItemList:
		out.append(n)
	for c in n.get_children():
		_collect_controls(c, out)


func _label_of(c: Control) -> String:
	if c is Button:
		return (c as Button).text
	return c.name
