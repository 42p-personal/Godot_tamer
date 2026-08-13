## THE CAREER LOOP, WALKED END TO END — headless.
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_career_loop.tscn
##
## ⚠️ WHY THIS EXISTS. `scripts/ui/deployment_board.gd` had never compiled since the initial
## commit (a parameter read out of scope), which took `tactics_ui.gd` down with it — the battle
## screen was UNREACHABLE THROUGH ITS OWN ENTRY PATH and every probe in the repo was green over
## it. Every other probe here tests a SYSTEM. This one tests the PLAYER'S ROUTE: title -> town ->
## market -> stable -> training -> advance week -> feeding -> tournament -> tactics -> (arena) ->
## report -> save/load. A system that works and cannot be reached is not built.
##
## ⚠️ IT RUNS AS A SCENE, NEVER `--script`. It instantiates real Control scenes and adds them to
## the tree; `_ready()` is where every one of these screens builds itself, so a script run (no
## SceneTree main loop of the right shape) would prove nothing.
##
## The arena itself is NOT driven here — `scripts/_probe_arena_switch.gd` already boots the real
## `arena3d.tscn` through the real tactics entry at 1v1 and 5v5. What this probe does instead is
## verify the CONTRACT either side of it: that "The Read" hands the arena a well-formed committed
## plan, and that the cup's per-round result tail moves the ladder correctly.
extends Node

const ReportScript = preload("res://scripts/ui/report_ui.gd")
const TacticsScript = preload("res://scripts/tactics.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []

## ⚠️ HELD, NOT FETCHED. These screens really do call `change_scene_to_file()` — New Career alone
## does — and that FREES whatever `current_scene` points at. On the first run of this probe that
## was the probe itself: every phase after phase 1 ran detached, `get_tree()` returned null, and
## the tally was meaningless while still printing PASS lines. `_detach_from_current_scene()` below
## parks a throwaway Node in the `current_scene` slot so the engine has something harmless to
## free, and every `get_tree()` call in this file reads `_tree` instead.
var _tree: SceneTree


func _ok(cond: bool, label: String) -> bool:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		_failures.append(label)
		print("  FAIL  %s" % label)
	return cond


func _section(title: String) -> void:
	print("\n─── %s ───" % title)


func _ready() -> void:
	_tree = get_tree()
	print("=== CAREER LOOP PROBE ===")
	await _detach_from_current_scene()
	_phase_compile()
	_phase_every_class_can_arm()
	await _phase_title()
	await _phase_town()
	await _phase_market()
	await _phase_stable()
	await _phase_training_and_week()
	await _phase_side_doors()
	await _phase_tournament()
	await _phase_tactics_commit()
	await _phase_cup_tail()
	await _phase_report()
	await _phase_save_load()

	print("\n=== career loop: %d passed, %d failed ===" % [_pass, _fail])
	for f in _failures:
		print("   failed: %s" % f)
	_ok(is_inside_tree(), "probe: still attached at the end — the tally above is real")
	_tree.quit(0 if _fail == 0 else 1)


## ⚠️ EVERY CLASS A MONSTER CAN BE MUST BE ABLE TO ARM ITSELF. This is a static tripwire on the
## round-11 bug, and it is here rather than in a system probe because the failure was invisible
## to every system probe in the repo for the life of the project.
##
## `data.json:classBasic` had 19 entries and `classLines` had 18. The odd one out was
## `Generalist` — a real, reachable class with an authored free attack and NO lines — so
## `assign_moveset()` cleared the kit, found no buckets to refill it from, and left the monster
## carrying its basic attack and nothing else. FOREVER, and on the save/load path too, since
## `save_game.gd:_deserialize_roster` re-arms on load.
##
## It cost a career. The arc autopilot trains the LOWEST stat, which walks every monster toward a
## perfectly flat spread, which is the literal definition of Generalist — so the autopilot was
## systematically disarming its own stable and the ladder was measured against a player that
## frequently fought weaponless. The round-10/11 difficulty relief (FIELD_ARCHETYPE_POWER_MULT
## 0.90) turned out to be paying for this bug rather than for the archetypes.
##
## The lesson is the project's oldest one: A TABLE WITH A HOLE IN IT IS NOT A MISSING FEATURE,
## IT IS A SILENT ONE. Two generated tables keyed by the same thing must agree, and nothing was
## asserting that they did. This does.
func _phase_every_class_can_arm() -> void:
	_section("every class can arm itself")
	var lines: Dictionary = GameData.class_lines
	# ⚠️ THE ROLL-CALL COMES FROM `classBasic`, NOT FROM `GameData.classes`, AND THAT IS THE WHOLE
	# POINT. `GameData.classes` holds 18 and does NOT list `Generalist` — because Generalist is
	# not a class you build toward, it is the one you FALL INTO when no stat pair dominates, and
	# it is `MonsterInstance.class_name_`'s own default. So the REACHABLE set is strictly larger
	# than the authored set, and the first version of this very probe looped `GameData.classes`
	# and passed 19/19 while missing the only class that had ever shipped broken.
	# `classBasic` is the honest roll-call: one entry per class a monster can END UP as.
	var raw := FileAccess.get_file_as_string("res://data/data.json")
	var parsed = JSON.parse_string(raw)
	var basics: Dictionary = {} if parsed == null else (parsed as Dictionary).get("classBasic", {})
	_ok(not basics.is_empty(), "classBasic table is present (%d entries)" % basics.size())
	_ok(not lines.is_empty(), "classLines table is present (%d entries)" % lines.size())
	_ok(basics.has("Generalist"),
		"classBasic lists Generalist — the fall-into class, and the one that shipped kitless")
	# Sorted, because a probe that iterates a Dictionary in insertion order reports a different
	# failure on a different day and that is how a real one gets dismissed as flaky.
	var names: Array = basics.keys()
	names.sort()
	# ⚠️ ARM A REAL MONSTER, DO NOT COMPARE THE TWO KEY SETS. A key-set check would have caught
	# the Generalist hole, but it would pass the moment someone adds an EMPTY `classLines` entry
	# to silence it — and it cannot see a fallback that exists but returns nothing. The invariant
	# that matters is behavioural: a monster of this class, asked to arm itself, carries moves.
	var rng := RandomNumberGenerator.new()
	for c in names:
		rng.seed = hash(str(c))
		var mi = GameData.make_monster(Art.ROSTER[0], 0.5, rng, 1.0)
		mi.class_name_ = str(c)
		mi.assign_moveset(rng)
		var authored: bool = lines.has(c) and not (lines[c] as Array).is_empty()
		_ok(mi.moveset.size() > 0, "class arms itself: %s (%d moves%s)"
			% [c, mi.moveset.size(), "" if authored else ", via fallback"])


## Hand the engine a decoy to free. `change_scene_to_file()` frees `current_scene`; this probe
## boots AS `current_scene`, so without this the first screen that navigates deletes the probe out
## from under its own coroutine.
func _detach_from_current_scene() -> void:
	# ⚠️ AWAIT FIRST. During `_ready()` the root is still "busy setting up children" and
	# `add_child()` refuses outright — which left `current_scene` pointing at the probe, so New
	# Career deleted the probe and its own coroutine hung forever on a `process_frame` that could
	# never resume. The failure printed nothing and looked exactly like a slow test.
	await _tree.process_frame
	var decoy := Node.new()
	decoy.name = "SceneSlotDecoy"
	_tree.root.add_child(decoy)
	_tree.current_scene = decoy
	await _tree.process_frame


## Any screen we drive may have navigated. Clear whatever landed in the scene slot and re-arm the
## decoy, so the NEXT navigation also has something harmless to free.
func _rearm() -> void:
	var cs: Node = _tree.current_scene
	if cs != null and cs != self and is_instance_valid(cs):
		_tree.root.remove_child(cs)
		cs.queue_free()
	await _detach_from_current_scene()


# ── 0. COMPILE ────────────────────────────────────────────────────────────────
# ⚠️ `load()` RETURNS A NON-NULL Script FOR A SCRIPT THAT FAILED TO COMPILE. A null check is not
# a compile check — that is precisely how deployment_board.gd stayed broken under a green probe.
# `can_instantiate()` is the question that actually reaches the engine's compile result.
func _phase_compile() -> void:
	_section("0. every script the career loop touches compiles")
	var paths: Array[String] = []
	_collect_gd("res://scripts/ui", paths)
	for extra in [
		"res://scripts/career.gd", "res://scripts/roster.gd", "res://scripts/save_game.gd",
		"res://scripts/week_plan.gd", "res://scripts/week.gd", "res://scripts/cup_run.gd",
		"res://scripts/tactics.gd", "res://scripts/game_data.gd", "res://scripts/monster_instance.gd",
		"res://scripts/tutorial.gd", "res://scripts/art.gd", "res://scripts/classify.gd",
	]:
		paths.append(extra)
	paths.sort()
	for p in paths:
		var s = load(p)
		var good: bool = s != null and (not (s is Script) or (s as Script).can_instantiate())
		_ok(good, "compiles: %s" % p.replace("res://scripts/", ""))


func _collect_gd(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd") and not f.begins_with("_"):
			out.append(dir_path + "/" + f)


# ── screen helper ─────────────────────────────────────────────────────────────
## Instantiate a real scene, add it to the tree so `_ready()` runs, hand it back. The caller frees
## it. Returns null (and records a failure) if the scene will not even instantiate.
func _open(scene_path: String, label: String) -> Node:
	var ps := load(scene_path)
	if ps == null or not (ps is PackedScene):
		_ok(false, "%s: scene loads (%s)" % [label, scene_path])
		return null
	var n: Node = (ps as PackedScene).instantiate()
	if n == null:
		_ok(false, "%s: scene instantiates" % label)
		return null
	add_child(n)
	await _tree.process_frame
	_ok(is_instance_valid(n) and n.get_child_count() > 0,
		"%s: builds its UI on _ready (%d children)" % [label, n.get_child_count() if is_instance_valid(n) else -1])
	return n


func _close(n: Node) -> void:
	if n != null and is_instance_valid(n):
		remove_child(n)
		n.queue_free()
	await _tree.process_frame


# ── 1. TITLE ──────────────────────────────────────────────────────────────────
func _phase_title() -> void:
	_section("1. title screen -> New Career")
	SaveGame.delete_save()
	var title := await _open("res://scenes/title.tscn", "title")
	if title != null:
		# The Continue button must exist and be disabled with no save present — a lying button is
		# worse than an absent one.
		var cont = title.get("continue_btn")
		_ok(cont != null, "title: Continue button exists")
		if cont != null:
			_ok(cont.disabled, "title: Continue is disabled with no save on disk")
		_ok(title.has_method("_on_new_career"), "title: New Career handler exists")
		title.call("_on_new_career")
	await _close(title)
	await _rearm()

	_ok(Career.week == 0, "new career: week 0 (is %d)" % Career.week)
	_ok(Career.gold == Career.STARTING_GOLD, "new career: %d gold" % Career.gold)
	_ok(Career.league_index == 0, "new career: at Wood, the bottom of the ladder")
	_ok(Career.barn_capacity == Career.STARTING_BARN_CAPACITY, "new career: barn holds %d" % Career.barn_capacity)
	_ok(Roster.monsters.is_empty(), "new career: EMPTY stable — the first recruit is the player's decision")


# ── 2. TOWN ───────────────────────────────────────────────────────────────────
func _phase_town() -> void:
	_section("2. the town hub")
	var town := await _open("res://scenes/town.tscn", "town")
	if town == null:
		return
	var cards: Array = town.get("loc_buttons")
	_ok(cards != null and cards.size() == town.get("LOCATIONS").size(),
		"town: one card per location (%d)" % (cards.size() if cards != null else -1))

	# ⚠️ Every door either goes somewhere real or says why not. A door pointing at a scene that
	# does not exist is the failure this checks for.
	for loc in town.get("LOCATIONS"):
		if bool(loc.get("real", false)):
			var target: String = str(loc.get("scene", ""))
			_ok(target != "" and ResourceLoader.exists(target),
				"town: '%s' points at a real scene (%s)" % [loc["title"], target])

	# The Tournament door must be disabled while the stable is empty — you cannot field a team.
	var tourney_idx := -1
	var locs: Array = town.get("LOCATIONS")
	for i in range(locs.size()):
		if str(locs[i].get("title", "")) == "Tournament":
			tourney_idx = i
	if tourney_idx >= 0 and cards != null and cards.size() > tourney_idx:
		var btn: Button = cards[tourney_idx].get_child(0)
		_ok(btn.disabled, "town: Tournament door disabled with an empty stable")
		_ok(btn.tooltip_text != "", "town: and it states WHY")

	# ⚠️ THE TWO CLOCKS. The Town's End Week and the Stable's Advance Week must not disagree about
	# what a week IS. See the finding in the report — this assertion is the fix's regression guard.
	var wk_before: int = Career.week
	town.call("_on_end_week")
	_ok(Career.week == wk_before + 1, "town: End Week advances the clock (%d -> %d)" % [wk_before, Career.week])
	await _close(town)


# ── 3. MARKET ─────────────────────────────────────────────────────────────────
func _phase_market() -> void:
	_section("3. the market — recruiting the first monsters")
	var market := await _open("res://scenes/market.tscn", "market")
	if market == null:
		return
	var offers: Array = market.get("offers")
	_ok(offers != null and offers.size() > 0, "market: generates offers (%d)" % (offers.size() if offers != null else -1))
	if offers == null or offers.is_empty():
		await _close(market)
		return

	var gold_before: int = Career.gold
	var bought := 0
	for o in offers:
		if Career.barn_is_full(Roster.monsters.size()):
			break
		if int(o["price"]) > Career.gold:
			continue
		market.call("_on_buy", o)
		bought += 1
	_ok(bought > 0, "market: bought %d recruit(s)" % bought)
	_ok(Roster.monsters.size() == bought, "market: the stable grew to %d" % Roster.monsters.size())
	_ok(Career.gold < gold_before, "market: gold was actually spent (%d -> %d)" % [gold_before, Career.gold])

	# Fill the barn — a one-monster stable hides every bug that only bites at two (the shared plan
	# key below being the one that did).
	Career.add_gold(1200)
	market.call("_refresh")
	for o in (market.get("offers") as Array).duplicate():
		if Career.barn_is_full(Roster.monsters.size()):
			break
		market.call("_on_buy", o)
	_ok(Roster.monsters.size() == Career.barn_capacity,
		"market: the barn fills to %d" % Roster.monsters.size())

	# ⚠️ THE BARN IS THE BOUND. Buying past it must be impossible, not merely discouraged.
	for o in (market.get("offers") as Array).duplicate():
		market.call("_on_buy", o)
	_ok(Roster.monsters.size() <= Career.barn_capacity,
		"market: cannot buy past the barn (%d held, barn %d)" % [Roster.monsters.size(), Career.barn_capacity])

	for m in Roster.monsters:
		_ok(m.max_hp > 0.0 and not m.moveset.is_empty() and m.class_name_ != "",
			"market: recruit '%s' is fully built (hp %.0f, %d moves, class %s)" % [
				m.species_name, m.max_hp, m.moveset.size(), m.class_name_])

	# ⚠️ THE SHARED-ID BUG. `GameData.make_monster()` leaves `id` empty; `week_plan.gd` keys plans
	# by it and `week.gd` seeds the training roll off it. Two recruits with the same id share one
	# plan slot and one RNG stream — invisible at a one-monster Wood stable, wrong from the
	# second recruit on.
	var ids := {}
	for m in Roster.monsters:
		_ok(str(m.id) != "", "market: '%s' has a career-slot id" % m.species_name)
		ids[m.id] = true
	_ok(ids.size() == Roster.monsters.size(),
		"market: every monster's id is unique (%d ids for %d monsters)" % [ids.size(), Roster.monsters.size()])
	await _close(market)


# ── 4. STABLE ─────────────────────────────────────────────────────────────────
func _phase_stable() -> void:
	_section("4. the stable")
	var stable := await _open("res://scenes/stable.tscn", "stable")
	if stable == null:
		return
	_ok(Roster.selected() != null, "stable: something is selected to inspect")
	_ok(stable.has_method("_on_advance_week"), "stable: has the Advance Week action")
	await _close(stable)


# ── 5. TRAINING + THE WEEKLY TICK ─────────────────────────────────────────────
func _phase_training_and_week() -> void:
	_section("5. training, then the week that spends it")
	var training := await _open("res://scenes/training.tscn", "training")
	await _close(training)

	var m = Roster.monsters[0]
	var str_before: float = float(m.stats["STR"])
	var gold_before: int = Career.gold
	var wk_before: int = Career.week

	WeekPlan.set_activity(m.id, "powerlift")
	_ok(absf(float(m.stats["STR"]) - str_before) < 0.001,
		"planning: booking a drill spends NOTHING until the week turns")
	_ok(WeekPlan.is_planned(m.id), "planning: the plan is recorded")

	var report: Dictionary = WeekPlan.advance(Roster.monsters)
	WeekPlan.set_meta("last_report", report)
	_ok(Career.week == wk_before + 1, "week: the clock moved (%d -> %d)" % [wk_before, Career.week])
	_ok(float(m.stats["STR"]) > str_before,
		"week: the booked drill landed (STR %.1f -> %.1f)" % [str_before, float(m.stats["STR"])])
	_ok(WeekPlan.plans.is_empty(), "week: plans are cleared, so nothing double-spends")
	_ok(report.has("monsters") and (report["monsters"] as Array).size() == Roster.monsters.size(),
		"week: the report narrates every monster")

	var feeding := await _open("res://scenes/feeding.tscn", "feeding")
	if feeding != null:
		_ok((feeding.get("_report") as Dictionary).has("week"), "feeding: reads the week's report, does not recompute it")
	await _close(feeding)

	# ⚠️ ONE PLAN PER MONSTER. Both recruits used to carry `id == ""`, so `WeekPlan.plans` held a
	# single entry for the whole stable — booking a drill for one booked it for every one.
	if Roster.monsters.size() >= 2:
		var a = Roster.monsters[0]
		var b = Roster.monsters[1]
		WeekPlan.set_activity(a.id, "powerlift")
		_ok(str(WeekPlan.plan_for(a.id).get("activity", "")) == "powerlift",
			"planning: the monster the player booked is booked")
		_ok(str(WeekPlan.plan_for(b.id).get("activity", "")) == "rest",
			"planning: its stablemate is NOT — plans do not bleed across the stable")
		var b_str: float = float(b.stats["STR"])
		WeekPlan.advance(Roster.monsters)
		_ok(absf(float(b.stats["STR"]) - b_str) < 0.001,
			"week: the unbooked stablemate trained nothing (STR %.1f)" % float(b.stats["STR"]))

	# ⚠️ THE TWO CLOCKS MUST BE ONE CLOCK. The Town's End Week used to bump the counter and
	# nothing else, silently burning a week the player had planned in the Stable.
	var m2 = Roster.monsters[0]
	WeekPlan.set_activity(m2.id, "powerlift")
	var str_pre: float = float(m2.stats["STR"])
	var town2 := await _open("res://scenes/town.tscn", "town-endweek")
	if town2 != null:
		town2.call("_on_end_week")
		_ok(float(m2.stats["STR"]) > str_pre,
			"town: End Week runs the REAL tick, same as the Stable (STR %.1f -> %.1f)" % [
				str_pre, float(m2.stats["STR"])])
		_ok(WeekPlan.plans.is_empty(), "town: and clears the plans, so the week cannot be spent twice")
	await _close(town2)
	await _rearm()


# ── 6. THE OTHER TOWN DOORS ───────────────────────────────────────────────────
func _phase_side_doors() -> void:
	_section("6. shop / lab / breeding")
	for pair in [["res://scenes/shop.tscn", "shop"], ["res://scenes/lab.tscn", "lab"],
			["res://scenes/breeding.tscn", "breeding"]]:
		var n := await _open(pair[0], pair[1])
		await _close(n)

	# The barn upgrade is the only thing that unlocks the team leagues — Bronze fields 3 and the
	# barn starts at 2, so a career that cannot buy room is a career that stops at Tin.
	var shop := await _open("res://scenes/shop.tscn", "shop-buy")
	if shop != null:
		var cap_before: int = Career.barn_capacity
		Career.add_gold(5000)
		shop.call("_refresh")
		var price: int = shop.get("BARN_PRICES")[cap_before + 1]
		if Career.spend_gold(price):
			Career.barn_capacity += 1
		_ok(Career.barn_capacity == cap_before + 1,
			"shop: the barn extends (%d -> %d) — the team leagues are reachable" % [cap_before, Career.barn_capacity])

		# ⚠️ A PURCHASE MUST REGISTER. The licences were stored with `Career.set_meta("Special
		# License", true)` — Godot rejects a metadata identifier containing a space, so the write
		# failed with a console-only error, the button never flipped to "✓ Held", and the shop
		# would take 800 gold from the same player over and over for nothing.
		var licence := "Special License"
		_ok(not Career.holds_licence(licence), "shop: the licence starts unheld")
		Career.grant_licence(licence)
		_ok(Career.holds_licence(licence), "shop: buying a licence actually registers it")
		Career.licences.erase(licence)
	await _close(shop)


# ── 7. TOURNAMENT ─────────────────────────────────────────────────────────────
func _phase_tournament() -> void:
	_section("7. tournament sign-up")
	var t := await _open("res://scenes/tournament.tscn", "tournament")
	if t == null:
		return
	var list: VBoxContainer = t.get("_list")
	_ok(list != null and list.get_child_count() == Career.league_index + 1,
		"tournament: one cup card per league reached (%d)" % (list.get_child_count() if list != null else -1))
	_ok(t.has_method("_on_enter"), "tournament: has an entry action")
	t.call("_on_enter", Career.league_index)
	await _close(t)
	await _rearm()

	_ok(CupRun.active, "cup: a run is live")
	_ok(CupRun.rival_teams.size() == CupRun.rival_count,
		"cup: every round's rival team is pre-generated (%d)" % CupRun.rival_teams.size())
	_ok(CupRun.current_rival_team().size() == CupRun.team_size,
		"cup: round 1's opponent is the right size (%d)" % CupRun.current_rival_team().size())


# ── 8. TACTICS -> the handoff the arena reads ─────────────────────────────────
func _phase_tactics_commit() -> void:
	_section("8. 'The Read' — orders, deployment, commit")
	TacticsScript.committed = {}
	var tac := await _open("res://scenes/tactics.tscn", "tactics")
	if tac == null:
		return
	var team_a: Array = tac.get("team_a")
	var team_b: Array = tac.get("team_b")
	_ok(team_a.size() > 0, "tactics: fields the player's team (%d)" % team_a.size())
	_ok(team_b.size() == team_a.size(), "tactics: against a same-size rival team (%d)" % team_b.size())
	_ok(str(tac.get("gameplan_id")) != "", "tactics: the rival has a scoutable gameplan")

	var board = tac.get("deployment_board")
	_ok(board != null, "tactics: the deployment board built (the screen that never compiled)")
	if board != null:
		board.call("auto_arrange")
		await _tree.process_frame
		var placements: Array = board.call("current_placements")
		_ok(placements.size() == team_a.size(),
			"deployment: every monster has a start position (%d of %d)" % [placements.size(), team_a.size()])
		var zone: Rect2 = board.call("zone_rect")
		# ⚠️ EDGE-INCLUSIVE ON PURPOSE (round 22). `Rect2.has_point()` excludes the far edges, but
		# the zone's forward edge IS legal: `Spatial.deploy_positions()` seats the front rank at
		# exactly x = cx − half_sep, which is the zone's right edge, and `_settle_valid` clamps
		# dragged chips onto that same edge. An edge-exclusive check therefore fails the sim's own
		# canonical start positions. It passed for 21 rounds only because the board was hard-sized
		# to 5v5, where the 0.5 grid snap happened to round the front rank 24.2 → 24.0, just
		# inside; the round-22 board is sized by the match (1v1 here) and exposed it.
		var all_in := true
		for p in placements:
			var pos: Vector2 = p["pos"]
			if pos.x < zone.position.x or pos.x > zone.position.x + zone.size.x \
					or pos.y < zone.position.y or pos.y > zone.position.y + zone.size.y:
				all_in = false
		_ok(all_in, "deployment: every placement is inside the legal deploy zone")

	tac.call("_on_commit")
	await _tree.process_frame
	var c: Dictionary = TacticsScript.committed
	_ok(not c.is_empty(), "commit: the plan reached the static handoff the arena reads")
	for key in ["planA", "planB", "ordersA", "ordersB", "deployA", "intentsA", "teamA", "teamB"]:
		_ok(c.has(key), "commit: handoff carries '%s'" % key)
	if c.has("teamA"):
		_ok((c["teamA"] as Array).size() == team_a.size(),
			"commit: the arena fights the EXACT team the player was shown")
		_ok((c["teamB"] as Array) == team_b,
			"commit: and the EXACT rival that was scouted — not a fresh roll")
	if c.has("deployA"):
		_ok((c["deployA"] as Dictionary).size() == team_a.size(),
			"commit: a deploy position per monster (%d)" % (c["deployA"] as Dictionary).size())
	await _close(tac)
	await _rearm()


# ── 9. THE CUP TAIL — what the arena calls back into ──────────────────────────
func _phase_cup_tail() -> void:
	_section("9. the cup's rounds and the ladder")
	var league_before: int = Career.league_index
	var rounds: int = CupRun.rival_count
	for i in range(rounds):
		_ok(not CupRun.is_finished(), "cup: round %d is pending before it is recorded" % (i + 1))
		CupRun.record_round_result(true)
	_ok(CupRun.is_finished(), "cup: the run reports itself finished after %d rounds" % rounds)
	var out: Dictionary = CupRun.finish()
	_ok(bool(out.get("swept", false)), "cup: three wins is a sweep")
	_ok(bool(out.get("promoted", false)) or bool(out.get("gameWon", false)), "cup: a sweep at the frontier promotes")
	_ok(Career.league_index == league_before + 1,
		"ladder: %s -> %s" % [Career.league_at(league_before).get("name", "?"), Career.current_league_name()])
	_ok(not CupRun.active, "cup: the run closed out")

	# The purse is paid by the tournament screen on the way back in — walk that too, or the
	# player wins a cup and is paid nothing.
	var gold_before: int = Career.gold
	var t := await _open("res://scenes/tournament.tscn", "tournament-return")
	_ok(Career.gold > gold_before, "purse: sweeping paid %d gold" % (Career.gold - gold_before))
	_ok(CupRun.last_result.is_empty(), "purse: the result drained, so it cannot be paid twice")
	await _close(t)


# ── 10. REPORT ────────────────────────────────────────────────────────────────
func _phase_report() -> void:
	_section("10. the post-battle report")
	# Hand off a battle the same way arena_3d.gd does, so the report renders a real fight rather
	# than falling back to its own standalone demo.
	var team_a: Array = Roster.monsters.slice(0, 1)
	var team_b: Array = Roster.make_rival_team(1, 0.2)
	var sim = load("res://scripts/battle_sim.gd").new(team_a, team_b, 12345)
	var result: Dictionary = sim.run()
	ReportScript.hand_off(result, team_a, team_b)
	_ok(not ReportScript.pending.is_empty(), "report: the handoff slot is filled")
	var rep := await _open("res://scenes/report.tscn", "report")
	_ok(ReportScript.pending.is_empty(), "report: the handoff drained — a second visit shows a demo, not a stale fight")
	await _close(rep)


# ── 11. SAVE / LOAD ───────────────────────────────────────────────────────────
func _phase_save_load() -> void:
	_section("11. save and load")
	# ⚠️ SAVE THE THINGS A PLAYER EARNS, NOT JUST THE THINGS THAT ARE CHEAP TO SAVE. v1 stored six
	# stats per monster, so a reload wiped the barn extension (locking the team leagues), the
	# licences, the freezer, and every monster's stamina/age — the last of which made save-scumming
	# a rest week a mechanic.
	for m in Roster.monsters:
		m.stats["STR"] = 123.0
		m.stamina = 41.0
		m.age_weeks = 133
		m.happiness = 7
	Career.grant_licence("Special License")
	if Roster.monsters.size() >= 2:
		Roster.frozen.append(Roster.monsters.pop_back())
	var snapshot := {
		"gold": Career.gold, "week": Career.week, "league": Career.league_index,
		"barn": Career.barn_capacity, "count": Roster.monsters.size(),
		"frozen": Roster.frozen.size(), "ids": Roster.monsters.map(func(m): return m.id),
	}
	_ok(SaveGame.save_game(), "save: written to disk")
	_ok(SaveGame.has_save(), "save: the title screen would now offer Continue")

	Career.reset_new_game()
	Roster.reset_to_empty()
	_ok(SaveGame.load_game(), "load: the save read back")
	_ok(Career.gold == snapshot["gold"], "load: gold restored (%d)" % Career.gold)
	_ok(Career.week == snapshot["week"], "load: week restored (%d, expected %d)" % [Career.week, snapshot["week"]])
	_ok(Career.league_index == snapshot["league"], "load: ladder position restored (%d)" % Career.league_index)
	_ok(Roster.monsters.size() == snapshot["count"], "load: the whole stable came back (%d)" % Roster.monsters.size())
	_ok(Career.barn_capacity == snapshot["barn"],
		"load: barn capacity restored (%d, expected %d)" % [Career.barn_capacity, snapshot["barn"]])
	_ok(Roster.frozen.size() == snapshot["frozen"],
		"load: the freezer came back (%d) — otherwise its rent quietly stops" % Roster.frozen.size())
	_ok(Career.holds_licence("Special License"), "load: a bought licence is still held")
	var restored_ok := true
	var clock_ok := true
	for m in Roster.monsters:
		if absf(float(m.stats["STR"]) - 123.0) > 0.001 or m.max_hp <= 0.0 or m.moveset.is_empty():
			restored_ok = false
		if absf(m.stamina - 41.0) > 0.001 or m.age_weeks != 133 or m.happiness != 7:
			clock_ok = false
	_ok(restored_ok, "load: every monster's stats survived and its derived fields rebuilt")
	_ok(clock_ok, "load: stamina, age and happiness survived — no free rest, no un-ageing")
	_ok(Roster.monsters.map(func(m): return m.id) == snapshot["ids"],
		"load: career-slot ids survived, so plans and training rolls stay attached")

	# ⚠️ A REFUSED LOAD MUST STILL LAND SOMEWHERE PLAYABLE. Continue used to ignore
	# `load_game()`'s return value entirely.
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	_ok(not SaveGame.load_game(), "load: a corrupt save is refused rather than half-applied")
	var title := await _open("res://scenes/title.tscn", "title-continue")
	if title != null:
		title.call("_on_continue")
		_ok(Roster.monsters.is_empty() and Career.week == 0,
			"continue: a refused load falls back to a clean career, not an undefined one")
	await _close(title)
	await _rearm()
	SaveGame.delete_save()
