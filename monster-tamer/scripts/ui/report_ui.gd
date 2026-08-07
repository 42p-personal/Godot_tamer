## THE BATTLE REPORT — the payoff for a game where the player never intervenes. They committed
## tactics, watched the fight, and now this screen answers the one question that matters: was
## the read right? Who won, how long it took, what each creature did and took, the single
## biggest hit, a short causal line naming the turning point, and — per monster — a DECISION LOG
## that says whether what it did was an order, its own nature, or something it reacted to.
## docs/UX_LEGIBILITY.md is the spec this section implements; read its §2/§4/§7 before touching
## the decision-log code below.
##
## ── PUBLIC ENTRY POINT ─────────────────────────────────────────────────────────────────────
## A caller that already has a finished sim result (BattleSim.run() OR SpatialSim.run() — both
## shapes are handled, see _analyze()/_decision_events_by_id() below) shows this screen like so:
##
##   var report := load("res://scenes/report.tscn").instantiate()
##   report.set_battle_result(battle_result, team_a, team_b)
##   get_tree().root.add_child(report)
##   get_tree().current_scene.queue_free()
##   get_tree().current_scene = report
##
## ⚠️ `SpatialSim.run()` IS A COROUTINE (BUILD_CONTRACT.md §2, added after stream A's navmesh-sync
## finding) — a caller feeding this screen from `SpatialSim` must `await sim.run()` BEFORE calling
## `set_battle_result`/`hand_off`. This file's own entry points take a plain, already-resolved
## `Dictionary` and never await anything themselves — the awaiting is entirely the CALLER's job
## (arena3d.gd, stream C). Passing an un-awaited `GDScriptFunctionState` here would not error; it
## would silently read as an empty result (`frames`/`winner` both blank), which is exactly the
## "looks like a data bug, not a missing keyword" failure the contract note warns about.
## `BattleSimScript` (this file's own demo fallback, below) stays synchronous — nothing here needs
## to await it.
##
## `battle_result` is exactly the sim's return value. `team_a`/`team_b` are the Array[MonsterInstance]
## that were actually fielded — passed separately because the result dict's flat `log` only ever
## carries species NAMES (never a stable id) on its hit/death/etc. entries, and this screen wants
## real per-monster identity too.
##
## set_battle_result() may be called before OR after this node enters the tree; either order
## rebuilds correctly. If it is never called (e.g. running res://scenes/report.tscn standalone
## for a screenshot), _ready() runs a small self-contained demo fight using the player's own
## Roster against a generated rival team, so the screen is never blank.
## ────────────────────────────────────────────────────────────────────────────────────────────
extends Control

const BattleSimScript = preload("res://scripts/battle_sim.gd")
const TacticsScript = preload("res://scripts/tactics.gd")

var _result: Dictionary = {}
var _team_a: Array = []
var _team_b: Array = []
var _sim: BattleSimScript = null
var _content: VBoxContainer


## ⚠️ CROSS-SCENE HANDOFF, because `set_battle_result` alone cannot survive one.
## `change_scene_to_file` frees the caller before the new scene exists, so there is no instance
## to call the setter on. A static slot persists process-wide with no autoload registration —
## the same pattern `tactics.gd:commit()` already uses to hand orders to the fight. The arena
## fills this in just before navigating here; `_ready` drains it exactly once so a later manual
## visit to this scene doesn't redisplay a stale fight.
static var pending: Dictionary = {}

static func hand_off(result: Dictionary, team_a: Array, team_b: Array) -> void:
	pending = {"result": result, "teamA": team_a, "teamB": team_b}


func set_battle_result(result: Dictionary, team_a: Array, team_b: Array) -> void:
	_result = result
	_team_a = team_a
	_team_b = team_b
	if _content != null:
		_rebuild()


func _ready() -> void:
	_build_shell()
	if _result.is_empty() and not pending.is_empty():
		_result = pending.get("result", {})
		_team_a = pending.get("teamA", [])
		_team_b = pending.get("teamB", [])
		pending = {}  # drain — a real fight is shown once, not re-shown on a later visit
	if _result.is_empty():
		_run_demo_battle()
	_rebuild()


func _build_shell() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.1)
	bg.anchor_right = 1; bg.anchor_bottom = 1
	add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1; scroll.anchor_bottom = 1
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	scroll.add_child(margin)

	_content = VBoxContainer.new()
	_content.add_theme_constant_override("separation", 14)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_content)


## Self-contained default so this scene is screenshot-able standalone — same pattern battle_ui.gd
## uses for its own demo team_a/team_b, so a fresh report and a fresh battle look consistent.
## Also synthesizes a plausible standing-orders record into `Tactics.committed`, so the Orders
## Summary block (§2/§11 of UX_LEGIBILITY.md) has real ORDER-vs-NATURE content to show even when
## this scene is opened with no tactics screen having run first — normally that dict is populated
## by tactics_ui.gd before the fight.
func _run_demo_battle() -> void:
	var team_a: Array = Roster.monsters.slice(0, mini(5, Roster.monsters.size()))
	var team_b: Array = Roster.make_rival_team(team_a.size(), 0.3)

	var plan_a := {"targetPriority": "casters"}
	var orders_a := {}
	for i in range(team_a.size()):
		orders_a[team_a[i]] = {"temperament": "aggressive"} if i == 0 else {"temperament": "balanced"}
	var gp_id := TacticsScript.gameplan_for(team_b.map(func(m): return m.species_name))
	var plan_b := TacticsScript.team_plan_for_gameplan(gp_id)
	var orders_b := TacticsScript.orders_for_gameplan(gp_id, team_b)
	TacticsScript.commit(plan_a, plan_b, orders_a, orders_b)

	var merged_orders: Dictionary = {}
	for k in orders_a:
		merged_orders[k] = orders_a[k]
	for k in orders_b:
		merged_orders[k] = orders_b[k]

	_sim = BattleSimScript.new(team_a, team_b, 20260804, plan_a, plan_b, merged_orders)
	_team_a = team_a
	_team_b = team_b
	_result = _sim.run()


func _rebuild() -> void:
	for c in _content.get_children():
		c.queue_free()
	if _result.is_empty():
		return

	var frames: Array = _result.get("frames", [])
	var built := _build_roster_and_ids(_team_a, _team_b)
	var roster: Array = built["roster"]
	var id_of: Dictionary = built["id_of"]
	var applies: bool = _tactics_applies(id_of)

	var analysis := _analyze(_result.get("log", []), _team_a, _team_b, frames, id_of, roster)
	var dec := _decision_events_by_id(_result.get("log", []), frames)

	_content.add_child(_banner())
	_content.add_child(HSeparator.new())
	_content.add_child(_teams_row(analysis, id_of, dec, applies))
	_content.add_child(HSeparator.new())

	var big_hit: Dictionary = analysis.get("biggest_hit", {})
	if int(big_hit.get("dmg", -1)) >= 0:
		var crit_tag := " (CRIT)" if big_hit.get("crit", false) else ""
		_content.add_child(_line(
			"Biggest hit: %s's %s on %s for %d%s" % [big_hit["attacker"], big_hit["move"], big_hit["target"], int(big_hit["dmg"]), crit_tag],
			15, Color(1.0, 0.8, 0.4)))

	var narrative := _narrative(analysis, dec, id_of, roster)
	if narrative != "":
		_content.add_child(_line(narrative, 14, Color(0.8, 0.8, 0.85)))

	var back := Button.new()
	back.text = "Back to the Stable"
	back.custom_minimum_size = Vector2(0, 40)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/stable.tscn"))
	_content.add_child(back)


func _banner() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var winner: String = _result.get("winner", "draw")
	var headline_text := "DRAW"
	var color := Color(0.7, 0.7, 0.72)
	if winner == "A":
		var id_a: Dictionary = Art.team_identity(0)
		headline_text = "%s VICTORY" % id_a["badge"]
		color = id_a["colour"]
	elif winner == "B":
		var id_b: Dictionary = Art.team_identity(1)
		headline_text = "%s DEFEAT" % id_b["badge"]
		color = id_b["colour"]

	var headline := Label.new()
	headline.text = headline_text
	headline.add_theme_font_size_override("font_size", 40)
	headline.add_theme_color_override("font_color", color)
	box.add_child(headline)

	var sub := Label.new()
	sub.text = "%.1fs — %d vs %d standing" % [float(_result.get("duration", 0.0)), int(_result.get("survivorsA", 0)), int(_result.get("survivorsB", 0))]
	sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	box.add_child(sub)
	return box


func _teams_row(analysis: Dictionary, id_of: Dictionary, dec: Dictionary, tactics_apply: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.add_child(_team_col("YOUR TEAM", _team_a, analysis, Art.team_identity(0), true, id_of, dec, tactics_apply))
	row.add_child(_team_col("RIVAL TEAM", _team_b, analysis, Art.team_identity(1), false, id_of, dec, tactics_apply))
	return row


## `identity` is {colour, badge} from Art.team_identity() — always drawn together here, since
## this is exactly the "two teams side by side" case art.gd's own rule is written for.
func _team_col(label_text: String, team: Array, analysis: Dictionary, identity: Dictionary,
		is_team_a: bool, id_of: Dictionary, dec: Dictionary, tactics_apply: bool) -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)

	var tint: Color = identity["colour"]
	var header := Label.new()
	header.text = "%s  %s" % [identity["badge"], label_text]
	header.add_theme_color_override("font_color", tint)
	col.add_child(header)

	var per_unit: Dictionary = analysis.get("per_unit", {})
	var events_by_id: Dictionary = dec.get("events", {})
	for m in team:
		var uid: int = id_of.get(m, -1)
		var stats: Dictionary = per_unit.get(uid, {})
		var events: Array = events_by_id.get(uid, [])
		col.add_child(_unit_report_row(m, uid, stats, tint, is_team_a, events, bool(dec.get("rich", false)), tactics_apply))
	return col


func _unit_report_row(m, uid: int, unit_stats: Dictionary, tint: Color, is_team_a: bool,
		decision_events: Array, rich: bool, tactics_apply: bool) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.13, 0.17)
	sb.border_color = tint
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 6; sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	panel.add_child(outer)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	outer.add_child(hbox)

	hbox.add_child(_portrait(m.species_id, m.species_name, Vector2(40, 40), tint))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var survived: bool = unit_stats.get("survived", true)
	var name_lbl := Label.new()
	name_lbl.text = "%s%s" % [m.species_name, ("" if survived else "  (fallen)")]
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.93) if survived else Color(0.55, 0.5, 0.5))
	info.add_child(name_lbl)

	var dmg_lbl := Label.new()
	var collision_tag := "  ⚠ shared with a same-species ally — tally split, see note below" if unit_stats.get("collision", false) else ""
	dmg_lbl.text = "dealt %d · took %d%s" % [int(unit_stats.get("dealt", 0)), int(unit_stats.get("taken", 0)), collision_tag]
	dmg_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	dmg_lbl.add_theme_font_size_override("font_size", 12)
	dmg_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.7) if collision_tag == "" else Color(0.85, 0.65, 0.4))
	info.add_child(dmg_lbl)

	# Critical-event teaser — shown even collapsed, per UX_LEGIBILITY.md §7 item 2: the one line
	# of the decision log that matters most should never require a click to see.
	var teaser := _critical_teaser(decision_events)
	if teaser != "":
		var teaser_lbl := Label.new()
		teaser_lbl.text = teaser
		teaser_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		teaser_lbl.add_theme_font_size_override("font_size", 11)
		teaser_lbl.add_theme_color_override("font_color", Color(0.9, 0.6, 0.55))
		outer.add_child(teaser_lbl)

	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 6)
	details.visible = false

	var toggle := Button.new()
	toggle.text = "▸ Orders & decision log"
	toggle.flat = true
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.add_theme_font_size_override("font_size", 11)
	toggle.pressed.connect(func():
		details.visible = not details.visible
		toggle.text = "▾ Orders & decision log" if details.visible else "▸ Orders & decision log"
	)
	outer.add_child(toggle)
	outer.add_child(details)

	var orders_box := VBoxContainer.new()
	orders_box.add_theme_constant_override("separation", 2)
	for line in _orders_summary_lines(m, is_team_a, tactics_apply):
		orders_box.add_child(line)
	details.add_child(orders_box)
	details.add_child(HSeparator.new())
	details.add_child(_decision_log_block(decision_events, rich))

	return panel


## Every axis `tactics.gd` tracks today, tagged ORDER vs NATURE, reusing its *_INFO copy verbatim
## (UX_LEGIBILITY.md §1 rule 1 — "the vocabulary is not invented twice"). This is the §11 item 1
## "cheap interim slice": real content, buildable against today's engine, with no dependency on
## the tree AI or the frame-stream intent/reason fields at all.
func _orders_summary_lines(m, is_team_a: bool, tactics_apply: bool) -> Array:
	var committed: Dictionary = TacticsScript.committed
	var plan: Dictionary = committed.get("planA" if is_team_a else "planB", {}) if tactics_apply else {}
	var orders_all: Dictionary = committed.get("ordersA" if is_team_a else "ordersB", {}) if tactics_apply else {}
	var own: Dictionary = orders_all.get(m, {})

	# Target priority — per-monster overrides the team plan; absent everywhere = "nature" default.
	var tp_source := "nature"
	var tp_value := ""
	if own.has("targetPriority"):
		tp_value = own["targetPriority"]; tp_source = "order"
	elif plan.has("targetPriority"):
		tp_value = plan["targetPriority"]; tp_source = "order"
	var tp_info: Dictionary = TacticsScript.info_by_id(TacticsScript.TARGET_PRIORITY_INFO, tp_value)

	# Mana policy — team-only, no per-monster override (tactics.gd's own doctrine).
	var mp_source := "order" if plan.has("manaPolicy") else "nature"
	var mp_value: String = plan.get("manaPolicy", "normal")
	var mp_info: Dictionary = TacticsScript.info_by_id(TacticsScript.MANA_POLICY_INFO, mp_value)

	# Formation — team-only, no per-monster override, ever (a formation can't be held alone).
	var fo_source := "order" if plan.has("formation") else "nature"
	var fo_value: String = plan.get("formation", "tight")
	var fo_info: Dictionary = TacticsScript.info_by_id(TacticsScript.FORMATION_INFO, fo_value)

	# Temperament — per-monster only. ⚠️ `tactics_ui.gd` writes {"temperament": "balanced"} into
	# every player-team row THE MOMENT THE ROW IS BUILT, not only when the player picks it — so
	# key-presence can't tell "the player chose Balanced" from "never touched" for team_a. We
	# degrade to a value-based read: only a value that DIFFERS from that untouched default counts
	# as an explicit order. The rival side has no such ambiguity — `orders_for_gameplan` always
	# writes an explicit value straight from `GAMEPLANS`, so presence there genuinely means the
	# gameplan set it.
	var te_value: String = own.get("temperament", "balanced")
	var te_source: String = ("order" if te_value != "balanced" else "nature") if is_team_a else "order"
	var te_info: Dictionary = TacticsScript.info_by_id(TacticsScript.TEMPERAMENT_INFO, te_value)

	var rows := [
		["Target priority", tp_info, tp_source],
		["Mana policy", mp_info, mp_source],
		["Formation", fo_info, fo_source],
		["Temperament", te_info, te_source],
	]

	# UX_LEGIBILITY.md §9's polish recommendation: if the player set literally nothing, a 4-line
	# table that reads "its nature" four times in a row teaches nothing — collapse to one line.
	if is_team_a:
		var any_order := false
		for r in rows:
			if r[2] == "order":
				any_order = true
				break
		if not any_order:
			return [_summary_line("No standing orders yet — every monster is following its own nature.", Color(0.6, 0.6, 0.65))]

	var out: Array = []
	for r in rows:
		var axis_name: String = r[0]
		var info: Dictionary = r[1]
		var source: String = r[2]
		var suffix := _order_suffix(source, is_team_a)
		var icon: String = info.get("icon", "")
		var name: String = info.get("name", "?")
		out.append(_summary_line(
			"%s: %s %s %s" % [axis_name, icon, name, suffix],
			Color(0.8, 0.8, 0.85) if source == "order" else Color(0.6, 0.6, 0.65)))
	return out


func _order_suffix(source: String, is_team_a: bool) -> String:
	if source == "order":
		return "— your order" if is_team_a else "— the rival's gameplan"
	return "— its nature"


func _summary_line(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", color)
	return l


## The decision log body: critical events always shown, standard shown once expanded (both are
## already inside the "Orders & decision log" toggle), minor collapsed under its own "+N more" —
## the third density lever from UX_LEGIBILITY.md §7. `rich` tells us whether these events carry a
## real `attribution` field (see _decision_events_by_id) or are a derived approximation.
func _decision_log_block(events: Array, rich: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var header := Label.new()
	header.text = "Decision log"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35))
	box.add_child(header)

	if events.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No decisions recorded for this fight." if rich else \
			"No intent data in this build yet — the tree AI (scripts/ai/monster_tree.gd) hasn't " + \
			"shipped, so there is nothing beyond the Orders Summary above to log here."
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		empty_lbl.add_theme_font_size_override("font_size", 11)
		empty_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
		box.add_child(empty_lbl)
		return box

	if not rich:
		var caveat := Label.new()
		caveat.text = "⚠ Attribution isn't available from this build's frame stream yet — showing raw intent/reason only, not ORDER/NATURE/REACTED."
		caveat.autowrap_mode = TextServer.AUTOWRAP_WORD
		caveat.add_theme_font_size_override("font_size", 10)
		caveat.add_theme_color_override("font_color", Color(0.6, 0.55, 0.4))
		box.add_child(caveat)

	var critical: Array = events.filter(func(e): return e.get("importance", "standard") == "critical")
	var standard: Array = events.filter(func(e): return e.get("importance", "standard") == "standard")
	var minor: Array = events.filter(func(e): return e.get("importance", "standard") == "minor")

	for e in critical:
		box.add_child(_decision_line(e, Color(0.95, 0.55, 0.5)))
	for e in standard:
		box.add_child(_decision_line(e, Color(0.8, 0.8, 0.85)))

	if not minor.is_empty():
		var minor_box := VBoxContainer.new()
		minor_box.visible = false
		var toggle := Button.new()
		toggle.text = "+%d more" % minor.size()
		toggle.flat = true
		toggle.focus_mode = Control.FOCUS_ALL
		toggle.add_theme_font_size_override("font_size", 10)
		toggle.pressed.connect(func():
			minor_box.visible = not minor_box.visible
			toggle.text = "Hide" if minor_box.visible else "+%d more" % minor.size()
		)
		box.add_child(toggle)
		box.add_child(minor_box)
		for e in minor:
			minor_box.add_child(_decision_line(e, Color(0.55, 0.55, 0.6)))

	return box


func _decision_line(e: Dictionary, color: Color) -> Label:
	var t: float = float(e.get("t", 0.0))
	var label_text: String = str(e.get("label", e.get("branch", "")))
	var reason: String = str(e.get("reason", ""))
	var attribution: String = str(e.get("attribution", ""))
	var suffix := ""
	if attribution == "order":
		suffix = " — your order"
	elif attribution == "nature":
		suffix = " — its nature"
	elif attribution == "reactive":
		suffix = " — reacted"
	var text := "%.1fs — %s" % [t, (label_text if label_text != "" else "(intent unavailable)")]
	if reason != "":
		text += ": %s" % reason
	text += suffix
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", color)
	return l


func _critical_teaser(events: Array) -> String:
	for e in events:
		if e.get("importance", "") == "critical":
			var t: float = float(e.get("t", 0.0))
			var reason: String = str(e.get("reason", ""))
			var label_text: String = str(e.get("label", e.get("branch", "")))
			var body := reason if reason != "" else label_text
			if body != "":
				return "%.1fs — %s" % [t, body]
	return ""


## `Tactics.committed` is a process-wide static slot (same pattern as this file's own `pending`
## handoff) — it can outlive the fight it described. Guard against showing a STALE plan for a
## different roster: only trust it if at least one of ITS committed orders keys to a monster
## actually fielded in this fight (both `orders_a`/`orders_for_gameplan` always write one entry
## per fielded monster in the real flow, so a real, matching commit always passes this check).
func _tactics_applies(id_of: Dictionary) -> bool:
	var committed: Dictionary = TacticsScript.committed
	if committed.is_empty():
		return false
	var orders_all: Dictionary = {}
	for k in committed.get("ordersA", {}):
		orders_all[k] = true
	for k in committed.get("ordersB", {}):
		orders_all[k] = true
	for m in id_of:
		if orders_all.has(m):
			return true
	return false


func _build_roster_and_ids(team_a: Array, team_b: Array) -> Dictionary:
	var roster: Array = team_a + team_b
	var id_of: Dictionary = {}
	for i in range(roster.size()):
		id_of[roster[i]] = i
	return {"roster": roster, "id_of": id_of}


## Pure post-battle pass: per-unit damage dealt/taken/survival, the single biggest hit, and the
## first death (used by _narrative below) — now keyed by a stable per-fight `id`, not species
## NAME. Two paths:
##
## 1. FRAME STREAM PRESENT (BUILD_CONTRACT.md §2, SpatialSim.run()'s `frames[].shots[]`) — the
##    contract-precise path. `shots` already carries true `fromId`/`toId`, so there is NO
##    same-species collision risk here at all; the bug this file's comment used to flag cannot
##    occur on this path.
## 2. NO FRAME STREAM (today's battle_sim.gd demo path) — the flat `log` only ever carries
##    species NAME + side on its events, never an id. We narrow the old collision risk from "any
##    same-species pair anywhere" to "same species AND same side" by keying on both, and — unlike
##    the old silent behaviour — make a real collision VISIBLE: damage is split across the tied
##    candidates and a `collision` flag is set, surfaced as a caveat in the unit row.
func _analyze(battle_log: Array, team_a: Array, team_b: Array, frames: Array, id_of: Dictionary, roster: Array) -> Dictionary:
	var per_unit: Dictionary = {}
	for i in range(roster.size()):
		per_unit[i] = {"dealt": 0, "taken": 0, "survived": true, "collision": false}

	var biggest: Dictionary = {"dmg": -1}
	var first_death = null

	if not frames.is_empty():
		var alive_now: Dictionary = {}
		for f in frames:
			for u in f.get("units", []):
				var uid2: int = int(u.get("id", -1))
				if uid2 < 0 or not per_unit.has(uid2):
					continue
				var was_alive: bool = alive_now.get(uid2, true)
				var is_alive: bool = bool(u.get("alive", true))
				if was_alive and not is_alive:
					per_unit[uid2]["survived"] = false
					if first_death == null:
						var killer_name := ""
						var killer_dmg := -1
						for shot in f.get("shots", []):
							if int(shot.get("toId", -1)) == uid2 and bool(shot.get("hit", false)):
								var sdmg: int = int(shot.get("dmg", 0))
								if sdmg > killer_dmg:
									killer_dmg = sdmg
									var from_id: int = int(shot.get("fromId", -1))
									killer_name = roster[from_id].species_name if from_id >= 0 and from_id < roster.size() else ""
						first_death = {"t": float(f.get("t", 0.0)), "unit": roster[uid2].species_name, "killer": killer_name}
				alive_now[uid2] = is_alive
			for shot in f.get("shots", []):
				var from_id2: int = int(shot.get("fromId", -1))
				var to_id2: int = int(shot.get("toId", -1))
				var dmg: int = int(shot.get("dmg", 0))
				if per_unit.has(from_id2):
					per_unit[from_id2]["dealt"] += dmg
				if per_unit.has(to_id2):
					per_unit[to_id2]["taken"] += dmg
				if dmg > int(biggest.get("dmg", -1)) and to_id2 >= 0 and to_id2 < roster.size() and from_id2 >= 0 and from_id2 < roster.size():
					biggest = {
						"dmg": dmg, "attacker": roster[from_id2].species_name, "target": roster[to_id2].species_name,
						"move": str(shot.get("move", "Attack")), "crit": bool(shot.get("crit", false)), "t": float(f.get("t", 0.0)),
					}
		return {"per_unit": per_unit, "biggest_hit": biggest, "first_death": first_death}

	# ── Fallback: no frame stream (battle_sim.gd) ──────────────────────────────────────────────
	var name_side_to_ids: Dictionary = {}
	for m in team_a:
		var key := "%s|A" % m.species_name
		if not name_side_to_ids.has(key):
			name_side_to_ids[key] = []
		name_side_to_ids[key].append(id_of[m])
	for m in team_b:
		var key2 := "%s|B" % m.species_name
		if not name_side_to_ids.has(key2):
			name_side_to_ids[key2] = []
		name_side_to_ids[key2].append(id_of[m])

	for e in battle_log:
		var kind: String = e.get("kind", "")
		if kind == "hit":
			var dmg2 := int(e.get("dmg", 0))
			var att_ids: Array = name_side_to_ids.get("%s|%s" % [e.get("attacker", ""), e.get("attackerSide", "")], [])
			var tgt_ids: Array = name_side_to_ids.get("%s|%s" % [e.get("target", ""), e.get("targetSide", "")], [])
			_credit(per_unit, att_ids, "dealt", dmg2)
			_credit(per_unit, tgt_ids, "taken", dmg2)
			if dmg2 > int(biggest.get("dmg", -1)):
				biggest = {
					"dmg": dmg2, "attacker": e.get("attacker", "?"), "target": e.get("target", "?"),
					"move": e.get("move", "Attack"), "crit": e.get("crit", false), "t": e.get("t", 0.0),
				}
		elif kind == "death":
			var d_ids: Array = name_side_to_ids.get("%s|%s" % [e.get("unit", ""), e.get("side", "")], [])
			for did in d_ids:
				if per_unit.has(did):
					per_unit[did]["survived"] = false
					if d_ids.size() > 1:
						per_unit[did]["collision"] = true
			if first_death == null:
				first_death = e

	return {"per_unit": per_unit, "biggest_hit": biggest, "first_death": first_death}


func _credit(per_unit: Dictionary, ids: Array, field: String, dmg: int) -> void:
	if ids.is_empty():
		return
	if ids.size() == 1:
		if per_unit.has(ids[0]):
			per_unit[ids[0]][field] += dmg
		return
	var share := int(round(float(dmg) / float(ids.size())))
	for uid in ids:
		if per_unit.has(uid):
			per_unit[uid][field] += share
			per_unit[uid]["collision"] = true


## The shared Decision Event stream (UX_LEGIBILITY.md §2), grouped by unitId. Two sources, richest
## first:
##
## 1. `battle_log` entries with `kind == "intent_change"` — the full shape UX_LEGIBILITY.md §2
##    proposes (label/reason/attribution/importance/target), if a sim ever emits it directly onto
##    the flat log. Nothing here is derived from it; it's read as-authored.
## 2. Otherwise, derived by DETECTING TRANSITIONS in `frames[].units[].intent`/`.reason`
##    (BUILD_CONTRACT.md §2's actual, current shape) — the load-bearing density fix from
##    UX_LEGIBILITY.md §1 rule 2: log the transition, never the tick. ⚠️ This path has no
##    `attribution` to read (BUILD_CONTRACT §2's frame shape carries only `intent`/`reason` prose,
##    not a structured attribution enum) — we do NOT infer one by pattern-matching the reason
##    string, because that is exactly the kind of renderer-side derivation both docs forbid
##    ("the renderer derives nothing"). See this stream's final report for what's missing.
func _decision_events_by_id(battle_log: Array, frames: Array) -> Dictionary:
	var by_id: Dictionary = {}
	var rich_found := false
	for e in battle_log:
		if e.get("kind", "") == "intent_change":
			rich_found = true
			var uid := int(e.get("unitId", -1))
			if uid < 0:
				continue
			if not by_id.has(uid):
				by_id[uid] = []
			by_id[uid].append(e)
	if rich_found:
		for uid in by_id:
			var arr: Array = by_id[uid]
			arr.sort_custom(func(a, b): return float(a.get("t", 0.0)) < float(b.get("t", 0.0)))
		return {"events": by_id, "rich": true}

	var prev: Dictionary = {}  # id -> [intent, reason]
	for f in frames:
		var t: float = float(f.get("t", 0.0))
		for u in f.get("units", []):
			var uid2: int = int(u.get("id", -1))
			if uid2 < 0:
				continue
			var intent: String = str(u.get("intent", ""))
			var reason: String = str(u.get("reason", ""))
			var key: Array = [intent, reason]
			var prev_key: Array = prev.get(uid2, ["", ""])
			if key != prev_key and (intent != "" or reason != ""):
				if not by_id.has(uid2):
					by_id[uid2] = []
				by_id[uid2].append({
					"t": t, "label": intent, "reason": reason,
					"attribution": "", "importance": "standard", "kind": "derived",
				})
			prev[uid2] = key

	# Best-effort tiering with no real importance signal available: the unit's FINAL recorded
	# transition is the branch it died (or ended) on — mark that one critical, per the tier table.
	for uid3 in by_id:
		var evs: Array = by_id[uid3]
		if not evs.is_empty():
			evs[evs.size() - 1]["importance"] = "critical"

	return {"events": by_id, "rich": false}


## One legible causal sentence, not a highlight reel — the whole point of this screen is telling
## the player WHY the fight went the way it did, in terms they can check their read against.
## ⚠️ Deliberately ONE hand-authored detector (turning point), per UX_LEGIBILITY.md §8/§12 —
## folding in the victim's own last recorded reason (when decision data exists) is an enrichment
## of this SAME detector, not a second one; the isolation-at-death and commitment-absence
## detectors §8 also describes are explicitly not built here (they need spatial support-range
## checks this pass doesn't have reliable data for yet — see the final report).
func _narrative(analysis: Dictionary, dec: Dictionary, id_of: Dictionary, roster: Array) -> String:
	var fd = analysis.get("first_death")
	if fd == null:
		return ""
	var when: float = float(fd.get("t", 0.0))
	var killer: String = fd.get("killer", "")
	var victim: String = fd.get("unit", "?")
	var reason := _reason_at_death(dec, id_of, roster, victim, when)

	if killer != "":
		if reason != "":
			return "Turning point: %s brought down %s at %.1fs — %s and the fight never came back level." % [killer, victim, when, reason]
		return "Turning point: %s brought down %s at %.1fs, and the fight never came back level." % [killer, victim, when]
	return "%s fell at %.1fs to sustained damage, without a single blow finishing it." % [victim, when]


## Best-effort lookup of what the victim was doing when it died, from the decision-event stream —
## only produces text once real intent/reason data exists (see _decision_events_by_id); a no-op
## today. Matches by species name (prose enrichment only, not a stats-integrity path — the id-keyed
## per_unit dict above is what damage/survival numbers rely on).
func _reason_at_death(dec: Dictionary, id_of: Dictionary, roster: Array, victim_name: String, death_t: float) -> String:
	var events_by_id: Dictionary = dec.get("events", {})
	for m in id_of:
		if m.species_name != victim_name:
			continue
		var uid: int = id_of[m]
		var events: Array = events_by_id.get(uid, [])
		var best := ""
		for e in events:
			if float(e.get("t", 0.0)) <= death_t:
				var r := str(e.get("reason", ""))
				if r != "":
					best = r
		return best
	return ""


func _portrait(species_id: String, species_name: String, portrait_size: Vector2, tint: Color) -> Control:
	var tex := Art.creature_texture(species_id)
	if tex != null:
		var t := TextureRect.new()
		t.texture = tex
		t.custom_minimum_size = portrait_size
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		return t
	var panel := PanelContainer.new()
	panel.custom_minimum_size = portrait_size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(tint.r, tint.g, tint.b, 0.18)
	sb.border_color = tint
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = species_name.substr(0, 2).to_upper()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", tint)
	lbl.add_theme_font_size_override("font_size", int(portrait_size.y * 0.4))
	panel.add_child(lbl)
	return panel


func _line(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
