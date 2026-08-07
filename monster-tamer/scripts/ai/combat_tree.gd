## THE COMBAT TREE — task #24: tactics mapped onto subtrees (AUTOBATTLER_DESIGN.md §2, §8, §9).
##
## Builds one BehaviourTree per unit from its TACTICS dict. The tree DECIDES; the sim EXECUTES:
## every leaf writes a request key to the blackboard (`req_move_to`, `req_attack`, `req_cast`,
## `req_hold`) and the sim carries it out under the movement/combat rules. That split is what
## makes the brain testable today, before the spatial_sim rewrite (decision #32) lands.
##
## ── THE BLACKBOARD CONTRACT (the sim fills these every decision tick) ─────────────────────────
##   self        : {id, pos: Vector2, hp, max_hp, speed}
##   enemies     : Array of {id, pos: Vector2, hp, max_hp, int_stat, wis, con, threat, reachable}
##                 — ORDERED BY ID; order is part of determinism.
##   allies      : Array of {id, pos: Vector2, hp, max_hp}
##   taunted_by  : enemy id or "" (taunt is an ability effect, decision #7)
##   ordered_id  : the player-marked target id or "" (axis A `marked`)
##   guard_id    : ally id for `guard` positional, or ""
##   safe_pos    : Vector2 the sim considers a genuine retreat point (allies/cover side)
##   home_pos    : Vector2 deployment anchor (axis B `hold`)
##   enemy_line_x: float — the enemy front's x, for push/dive geometry
##   capstone_ready / setup_status_live : bools for the ability policy branch
##   focus_sticky: float >= 1.0, derived from Focus (commitment); 1.0 == `reassess`
##   nerve       : 0-100, sets how cleanly `fall back` disengages (dwell scaling)
##
## ── TACTICS (per unit; team plan supplies defaults, any axis overridable — decision #13) ─────
##   target_priority : nearest | weakest | casters | tanks | marked | threat
##   positional      : push | hold | wings | dive | guard
##   wing_side       : -1 | 1 (which flank for `wings`)
##   when_hurt       : fight_on | fall_back | disengage
##   hurt_at         : hp fraction that arms the when-hurt branch (data, not hardcoded)
##   ability_policy  : free | hold_big | combo
##   bull_through    : bool — decision #30: the blocking rule is a TACTIC. true = path to the
##                     ordered target regardless; false = engage whatever intercepts.
##
## ⚠️ URGENT OVERRIDES ARE A SHORT CLOSED LIST (decision #27) and `fight_on` BEATS the
## self-preservation override (decision #28) — the player's order stays sovereign. Do not add
## overrides here without a design-doc entry; the list being short is the point.
##
## ⚠️ `fall_back` carries a MINIMUM DWELL and a real safety condition (§10) — the TFM
## flee-then-return death spiral is the named failure this guards against.
extends RefCounted

const BT = preload("res://scripts/ai/bt.gd")

## Dwell base for fall_back, in decision ticks; scaled down by Nerve (a cool head disengages
## cleanly and re-reads sooner). Data-shaped constant: the sim may override via bb key
## `fallback_dwell_ticks`.
const FALLBACK_DWELL_BASE := 30


static func build(tactics: Dictionary) -> BT.BehaviourTree:
	var order_slot := BT.SubtreeSlot.new()
	var mode_slot := BT.SubtreeSlot.new()  # decision #38: modes INJECT subtrees here

	var root := BT.Selector.new("", [
		_urgent_branch(tactics),
		_when_hurt_branch(tactics),
		mode_slot,
		order_slot,
		_combat_branch(tactics),
		# §10: no idle state without a reason. If nothing above ran, the unit regroups on its
		# anchor and SAYS SO — "wandering in circles" is the reference failure.
		BT.Action.new("Regroup", func(bb):
			bb.set_value("req_move_to", bb.get_value("home_pos", Vector2.ZERO))
			bb._reason = "no target, no order — regrouping on anchor"
			return BT.RUNNING),
	])
	var tree := BT.BehaviourTree.new(root)
	tree.register_slot("order", order_slot)
	tree.register_slot("mode", mode_slot)
	return tree


## ── Urgent (decision #27: taunted · ordered target gone · about to die · unreachable) ─────────
static func _urgent_branch(tactics: Dictionary) -> BT.BTNode:
	var when_hurt: String = str(tactics.get("when_hurt", "fight_on"))
	var children: Array = [
		# Taunted: answer it. Taunt is an ability effect and it wins over every priority.
		BT.Sequence.new("Taunted", [
			BT.Condition.new("", func(bb): return str(bb.get_value("taunted_by", "")) != ""),
			BT.Action.new("Answer the taunt", func(bb):
				var tid: String = str(bb.get_value("taunted_by", ""))
				bb.set_value("req_attack", tid)
				bb._reason = "taunted by %s" % tid
				return BT.RUNNING),
		]),
		# Ordered target gone: drop the mark so axis-A targeting takes over next descent.
		BT.Sequence.new("Order void", [
			BT.Condition.new("", func(bb):
				var oid: String = str(bb.get_value("ordered_id", ""))
				if oid == "":
					return false
				for e in bb.get_value("enemies", []):
					if str(e.id) == oid and e.hp > 0:
						return false
				return true),
			BT.Action.new("Release the order", func(bb):
				bb._reason = "ordered target %s is gone" % str(bb.get_value("ordered_id", ""))
				bb.set_value("ordered_id", "")
				return BT.SUCCESS),
		]),
	]
	# About to die WITH an escape — decision #28: applies ONLY on fall_back/disengage. A
	# monster ordered to fight on dies fighting; the branch simply does not exist for it.
	if when_hurt != "fight_on":
		children.append(BT.Sequence.new("Death's door", [
			BT.Condition.new("", func(bb):
				var me: Dictionary = bb.get_value("self", {})
				var frac: float = float(me.get("hp", 1)) / maxf(1.0, float(me.get("max_hp", 1)))
				return frac <= float(bb.get_value("deathdoor_frac", 0.12)) \
					and bb.get_value("escape_open", false)),
			BT.Action.new("Escape", func(bb):
				bb.set_value("req_move_to", bb.get_value("safe_pos", Vector2.ZERO))
				bb._reason = "about to die, escape is open"
				return BT.RUNNING),
		]))
	# Destination unreachable: fall back to the nearest reachable stand-in the sim proposes.
	children.append(BT.Sequence.new("Unreachable", [
		BT.Condition.new("", func(bb): return bb.get_value("dest_unreachable", false)),
		BT.Action.new("Repath", func(bb):
			bb.set_value("req_move_to", bb.get_value("reachable_alt", bb.get_value("home_pos", Vector2.ZERO)))
			bb._reason = "destination unreachable — taking the reachable stand-in"
			return BT.RUNNING),
	]))
	return BT.Selector.new("Urgent", children)


## ── When hurt (axis D) — armed by hp fraction, never automatic (decision #14) ─────────────────
static func _when_hurt_branch(tactics: Dictionary) -> BT.BTNode:
	var mode: String = str(tactics.get("when_hurt", "fight_on"))
	if mode == "fight_on":
		# No branch at all: fight_on is the absence of self-preservation, not a check that
		# always fails — the tree shape itself documents the order's sovereignty.
		return BT.Condition.new("", func(_bb): return false)
	var label := "Fall back" if mode == "fall_back" else "Disengage"
	return BT.Sequence.new(label, [
		BT.Condition.new("", func(bb):
			var me: Dictionary = bb.get_value("self", {})
			var frac: float = float(me.get("hp", 1)) / maxf(1.0, float(me.get("max_hp", 1)))
			var armed: bool = frac <= float(tactics.get("hurt_at", 0.35))
			var t: int = int(bb.get_value("_tick_now", 0))
			var until: int = int(bb.get_value("fallback_until", -1))
			# ⚠️ The dwell: once falling back, KEEP falling back until the dwell expires AND
			# the safety condition holds — this is the anti-flee-return guard, in the tree.
			if until >= 0 and t < until:
				return true
			if until >= 0 and t >= until:
				if bb.get_value("steadied", false):
					bb.set_value("fallback_until", -1)
					return false
				return true
			if armed:
				var dwell: int = int(bb.get_value("fallback_dwell_ticks", FALLBACK_DWELL_BASE))
				var nerve: float = clampf(float(bb.get_value("nerve", 50)) / 100.0, 0.0, 1.0)
				bb.set_value("fallback_until", t + int(dwell * (1.4 - 0.8 * nerve)))
				return true
			return false),
		BT.Action.new("Withdraw to safety", func(bb):
			bb.set_value("req_move_to", bb.get_value("safe_pos", Vector2.ZERO))
			bb._reason = "%s at %.0f%% HP (Nerve %d)" % [
				"falling back" if mode == "fall_back" else "disengaging",
				100.0 * float(bb.get_value("self", {}).get("hp", 0)) / maxf(1.0, float(bb.get_value("self", {}).get("max_hp", 1))),
				int(bb.get_value("nerve", 50))]
			return BT.RUNNING),
	])


## ── Combat: Target (axis A) → Move (axis B) → Act (axis D policy) ────────────────────────────
static func _combat_branch(tactics: Dictionary) -> BT.BTNode:
	return BT.Sequence.new("Combat", [
		_target_node(tactics),
		_positional_node(tactics),
		_act_node(tactics),
	])


## Axis A: one scorer per priority, chosen by tactics; commitment via UtilitySelector
## stickiness keyed on focus_sticky (`reassess` == the sim sets it to 1.0).
static func _target_node(tactics: Dictionary) -> BT.BTNode:
	var mode: String = str(tactics.get("target_priority", "nearest"))
	return BT.Action.new("Mark " + mode, func(bb):
		var enemies: Array = bb.get_value("enemies", [])
		var live: Array = enemies.filter(func(e): return e.hp > 0)
		if live.is_empty():
			return BT.FAILURE
		var me: Dictionary = bb.get_value("self", {})
		var pick: Dictionary = {}
		match mode:
			"marked":
				var oid: String = str(bb.get_value("ordered_id", ""))
				for e in live:
					if str(e.id) == oid:
						pick = e
						break
				if pick.is_empty():
					pick = _best(live, func(e): return -Vector2(me.pos).distance_to(e.pos))
			"weakest":
				pick = _best(live, func(e): return -float(e.hp))
			"casters":
				pick = _best(live, func(e): return float(e.get("int_stat", 0)) + float(e.get("wis", 0)))
			"tanks":
				pick = _best(live, func(e): return float(e.get("con", 0)))
			"threat":
				pick = _best(live, func(e): return float(e.get("threat", 0.0)))
			_:
				pick = _best(live, func(e): return -Vector2(me.pos).distance_to(e.pos))
		# Commitment: the incumbent survives unless the new pick beats it by the Focus margin.
		var sticky: float = maxf(1.0, float(bb.get_value("focus_sticky", 1.0)))
		var cur: String = str(bb.get_value("target_id", ""))
		if cur != "" and cur != str(pick.id) and sticky > 1.0:
			for e in live:
				if str(e.id) == cur:
					pick = e  # hold the incumbent; scorer margins are the sim's re-open signal
					break
		if str(pick.id) != cur:
			bb._reason = "target: %s (%s)" % [str(pick.id), mode]
		bb.set_value("target_id", str(pick.id))
		bb.set_value("target_pos", pick.pos)
		return BT.SUCCESS)


static func _best(arr: Array, score: Callable) -> Dictionary:
	var best: Dictionary = arr[0]
	var best_s: float = score.call(arr[0])
	for i in range(1, arr.size()):
		var s: float = score.call(arr[i])
		if s > best_s:  # strict > : ties break by ARRAY ORDER, which is id-sorted — determinism
			best_s = s
			best = arr[i]
	return best


## Axis B: where do I want to be? `wings` and `dive` carry LATERAL geometry — they are the two
## options that spread a fight across a 160-wide board (§2B); do not straighten them.
static func _positional_node(tactics: Dictionary) -> BT.BTNode:
	var mode: String = str(tactics.get("positional", "push"))
	var wing: float = float(tactics.get("wing_side", 1))
	match mode:
		"hold":
			return BT.Action.new("Hold the line", func(bb):
				var home: Vector2 = bb.get_value("home_pos", Vector2.ZERO)
				var tp: Vector2 = bb.get_value("target_pos", home)
				# Stand the line: meet the target only within the hold radius of home.
				var hold_r: float = float(bb.get_value("hold_radius", 8.0))
				var want: Vector2 = home + (tp - home).limit_length(hold_r)
				bb.set_value("req_move_to", want)
				return BT.SUCCESS)
		"wings":
			return BT.Action.new("Work the wing", func(bb):
				var tp: Vector2 = bb.get_value("target_pos", Vector2.ZERO)
				var lateral: float = float(bb.get_value("wing_offset", 18.0)) * wing
				bb.set_value("req_move_to", Vector2(tp.x, tp.y + lateral) if bb.get_value("wing_axis_y", true) else Vector2(tp.x + lateral, tp.y))
				return BT.SUCCESS)
		"dive":
			return BT.Action.new("Dive the backline", func(bb):
				# Aim BEHIND the enemy line, not at the nearest body — the approach goes
				# around, which is the whole identity of the tactic.
				var tp: Vector2 = bb.get_value("target_pos", Vector2.ZERO)
				var behind_x: float = float(bb.get_value("enemy_line_x", tp.x)) + float(bb.get_value("dive_depth", 12.0)) * signf(tp.x - float(bb.get_value("self", {}).get("pos", Vector2.ZERO).x) + 0.001)
				bb.set_value("req_move_to", Vector2(behind_x, tp.y))
				return BT.SUCCESS)
		"guard":
			return BT.Action.new("Guard the charge", func(bb):
				var gid: String = str(bb.get_value("guard_id", ""))
				for a in bb.get_value("allies", []):
					if str(a.id) == gid:
						bb.set_value("req_move_to", a.pos)
						return BT.SUCCESS
				return BT.FAILURE)
		_:
			return BT.Action.new("Push", func(bb):
				bb.set_value("req_move_to", bb.get_value("target_pos", Vector2.ZERO))
				return BT.SUCCESS)
	return BT.Action.new("Push", func(bb):
		bb.set_value("req_move_to", bb.get_value("target_pos", Vector2.ZERO))
		return BT.SUCCESS)


## Axis D ability policy: free spends on cooldown; hold_big banks the capstone for the moment;
## combo spends only to set up or cash in a status. The sim supplies the booleans; the tree
## supplies the discipline.
static func _act_node(tactics: Dictionary) -> BT.BTNode:
	var policy: String = str(tactics.get("ability_policy", "free"))
	return BT.Action.new("Engage", func(bb):
		var tid: String = str(bb.get_value("target_id", ""))
		if tid == "":
			return BT.FAILURE
		var cast_ok := true
		match policy:
			"hold_big":
				cast_ok = not bb.get_value("capstone_ready", false) or bb.get_value("big_moment", false)
			"combo":
				cast_ok = bb.get_value("setup_status_live", false) or bb.get_value("can_apply_setup", true)
		bb.set_value("req_attack", tid)
		bb.set_value("req_cast_allowed", cast_ok)
		return BT.RUNNING)
