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
##   ordered_id  : the player-marked target id or "" (axis A `marked`). ⚠️ The sim does NOT
##                 fill this — the TREE seeds it once from tactics.ordered_id on the first
##                 descent (see build()), so marked orders work from the tactics dict alone.
##                 The urgent Order-void branch clears a dead mark; it is never re-seeded.
##   guard_id    : ally id for `guard` positional, or ""
##   safe_pos    : Vector2 the sim considers a genuine retreat point (allies/cover side)
##   home_pos    : Vector2 deployment anchor (axis B `hold`)
##   enemy_line_x: float — the enemy front's x, for push/dive geometry
##   capstone_ready : bool for the ability policy branch (is the big cast off cooldown?)
##   big_moment / setup_status_live : OPTIONAL force-open bools. The tree now DERIVES both
##                 when they are absent/false: hold_big's moment = target below
##                 `big_moment_frac` (0.40) OR 3+ live enemies inside `big_moment_radius`
##                 (8.0) of the target; combo's live setup = any entry in the target
##                 record's `statuses` array (sim-filled — see SIM-FILLED EXTRAS below). A
##                 true from the sim or a test always wins — derivation only ever OPENS the
##                 window.
##   focus_sticky: float >= 1.0, derived from Focus (commitment); 1.0 == `reassess`
##   nerve       : 0-100, sets how cleanly `fall back` disengages (dwell scaling)
##
## ── TACTICS (per unit; team plan supplies defaults, any axis overridable — decision #13) ─────
##   target_priority : nearest | weakest | casters | tanks | marked | threat | healers
##   positional      : push | hold | wings | dive | guard | kite   (⚠️ `kite` was already built
##                     and missing from this list — decision #39's budgeted kiting)
##                     ⚠️ EVERY POSTURE'S GEOMETRY IS BOARD-RELATIVE — see the BOARD SCALE block
##                     below. Writing a distance here as a literal is the bug that parked `hold`,
##                     `guard` and `kite` on their deploy anchors for whole 5v5 fights.
##   wing_side       : -1 | 1 (which flank for `wings`)
##   when_hurt       : fight_on | fall_back | disengage
##   hurt_at         : hp fraction that arms the when-hurt branch (data, not hardcoded)
##   ability_policy  : free | hold_big | combo
##   bull_through    : bool — decision #30: the blocking rule is a TACTIC. true (DEFAULT) =
##                     path to the ordered/priority target regardless (the swing at bodies en
##                     route is the sim's opportunism, not the tree's); false = the opt-in
##                     cautious tactic: engage whatever intercepts. An interceptor = a live
##                     enemy inside `interceptor_reach` (bb, default 6.6 = the sim's
##                     BASE_REACH) while my pick is OUT of reach, in the half-plane toward
##                     the pick. ⚠️ Default MEASURED, not assumed: engage-on-intercept as the
##                     unset rule un-dived every diver and blobbed the dive comp (see the
##                     note in _target_node).
##
## ⚠️ URGENT OVERRIDES ARE A SHORT CLOSED LIST (decision #27) and `fight_on` BEATS the
## self-preservation override (decision #28) — the player's order stays sovereign. Do not add
## overrides here without a design-doc entry; the list being short is the point.
##
## ⚠️ `fall_back` carries a MINIMUM DWELL and a real safety condition (§10) — the TFM
## flee-then-return death spiral is the named failure this guards against.
##
## ── SIM-FILLED EXTRAS (formerly the WISHLIST — sim.gd::_fill_bb fills ALL of these now; the
##    safe defaults below remain the fallback for hand-built test blackboards) ──────────────────
##   enemies[i].team_dmg : float — TOTAL recent damage MY TEAM has dealt this enemy (my team's
##                         rows of that enemy's `dmg_from` ledger, summed in unit-id order).
##                         Feeds the focus-fire assist; default 0.0 falls back to `hp < max_hp`.
##   enemies[i].casting  : bool — this enemy is committed to a cast. Fills the OPPORTUNISTIC
##                         kick (kick a caster in reach that is not my target). Default false.
##   enemies[i].threat   : float — recent damage this enemy dealt ME (`u.dmg_from[enemy]`), so
##                         the `threat` target priority means what the contract above says.
##   kick_range          : float — my interrupt's ENFORCED reach (sim INTERRUPT_REACH);
##                         default 6.0 for hand-built blackboards.
##   aggression          : 0-100 personality (§3/§9: personality weights branch selection);
##                         default 50 == every multiplier exactly 1.0.
##   enemies[i].statuses : this enemy's live AILMENTS, minimal {kind} records in apply order.
##                         Filtered SIM-SIDE by the beneficial table (the tree has no status
##                         rulebook), so "any entry" here MEANS "an ailment is live" — a buff
##                         on an enemy never reads as combo setup. Feeds the combo policy's
##                         `setup_status_live` derivation; default [] (absent) falls back to
##                         the `can_apply_setup` gate unchanged.
##   enemies[i].heal_out : float (sim wire-up pending) — recent healing OUTPUT by this enemy,
##                         a scalar `heal_done` ledger decaying exactly like `dmg_from`
##                         (×0.985/tick, ~2s half-life at 10Hz), credited with the EFFECTIVE
##                         heal (hp actually restored — overheal dribble is not visibility).
##                         Feeds the `healers` target priority; default 0.0 means "has not
##                         healed", which drops the priority to its casters fallback — see
##                         _target_node. The sim's 'heal' events already carry the amount;
##                         the ledger is the decayed mirror of them.
##
## ── SIM WISHLIST (one key — `heal_done`/`heal_out` above awaits its sim.gd wiring) ───────────
extends RefCounted

const BT = preload("res://scripts/ai/bt.gd")

## Dwell base for fall_back, in decision ticks; scaled down by Nerve (a cool head disengages
## cleanly and re-reads sooner). Data-shaped constant: the sim may override via bb key
## `fallback_dwell_ticks`.
const FALLBACK_DWELL_BASE := 30


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# BOARD SCALE — ⚠️ EVERY POSITIONAL CONSTANT BELOW IS A FRACTION OF THE BOARD, NOT AN ABSOLUTE
# ═══════════════════════════════════════════════════════════════════════════════════════════════
##
## ⚠️ THIS IS THE FIFTH-SCALE-BUG SHAPE AGAIN, AND IT WAS MEASURED, NOT GUESSED.
## `_probe_sim_quality.gd` ran the same comps on the toy 110x62 board every check used and on the
## REAL `Spatial.ground_size(5)` = 440x246.4 board the game is actually played on. The toy board
## puts the two deploy lines 80 units apart; the real one puts them **391.6** apart. Advance at
## 34% into the fight, by posture, on the real board, BEFORE this block existed:
##
##     Push               0.90 .. 1.95   (of the way from its deploy line to the centre)
##     Dive the backline  1.24 .. 1.82
##     Hold the line      0.04 .. 0.05   ← parked on its deploy anchor, 390 units from the fight
##     Guard the charge   0.07           ← guarding a parked charge, therefore also parked
##     Kite               0.00           ← never moved at all, all fight
##
## A `hold` unit clamped 8.0 units from a deploy anchor at the far END of the board is not holding
## a line, it is a spectator, and its team fights 5v3. The reason nobody saw it is that the toy
## board is small enough that a body standing on its anchor is ALREADY inside reach of the centre
## (`HARD_REACH_MAX` is 96.8 against a half-separation of 40) — the posture "worked" by accident
## of scale. `wings` was the same story from the other end: an 18-unit lateral offset is a real
## flank on a 62-deep board and 7% of a 246-deep one, so the tactic §2B names as one of the TWO
## that spread a fight across the board measured a THINNER footprint than a plain brawl.
##
## The rule from here: the tree knows exactly ONE distance — the deploy separation, which it can
## read off the blackboard — and every positional constant is expressed as a fraction of it.
##
## ⚠️ THE SCALE NEVER GOES BELOW 1.0, ON PURPOSE. Hand-built test blackboards (and any future
## small board) keep the authored absolutes EXACTLY, so this block can only ever grow a distance
## on a board bigger than the one they were authored for. That is what makes it safe to add to a
## tree with a full probe battery already pinned against it.
const BOARD_REF_SPAN := 80.0   # the deploy separation the absolutes below were authored against
const WING_OFFSET_BASE := 18.0
const DIVE_DEPTH_BASE := 12.0
const KITE_GAP_BASE := 12.0
const HOLD_RADIUS_BASE := 8.0  # ⚠️ MIRRORS sim.gd's HOLD_RADIUS_BASE — its own comment says
							   #  "must match the tree's hold default". The sim publishes
							   #  `hold_radius` as BASE + stagnation_level, so the tree
							   #  subtracts BASE to recover the ratchet's contribution and
							   #  re-adds it on top of the board-derived line (see _hold_radius).
## `hold` holds a LINE, and on a board whose deploy zones are at the two ENDS the deploy point is
## not a line, it is a corner of the map. The rule that reads correctly at EVERY board size is
## REACH-RELATIVE: advance only until the enemy line is inside a working weapon's reach, and never
## past `HOLD_LINE_FRAC` of the way to the centre.
##
## ⚠️ THE FIRST VERSION OF THIS WAS PURELY CENTRE-RELATIVE (`0.9 x half-separation`) AND THE
## ANTI-BLOB CHECK CAUGHT IT — four teams on the small board collapsed past the 70% shrink floor,
## because on a 110-wide board the enemy line is 80 away while reach runs to 96.8: everything is
## ALREADY in range at deploy, so "advance to the centre" there means "pile into the scrum", which
## is the blob this whole rewrite exists to kill. The reach term makes the small board resolve to
## exactly the authored 8.0 (byte-identical to before) and the 5v5 board to ~176.
##
## `HOLD_REACH_REF` is the pool's working stand-off: `Spatial.CHANNEL_RANGE` puts magic at 61.6,
## voice at 57.2 and ranged at 70.4, with `HARD_REACH_MAX` at 96.8. ⚠️ It is a REFERENCE, not the
## unit's own reach — the blackboard does not carry that today. If the sim ever publishes a
## `my_reach` key this should read it instead; see the note in the SIM WISHLIST at the top.
const HOLD_LINE_FRAC := 0.9
const HOLD_REACH_REF := 72.0
## A kiter with nobody near it used to stand on its anchor forever (measured 0.00 advance). The
## gap is a gap in BOTH directions: past this multiple of it, take up the firing line.
const KITE_ADVANCE_SLACK := 1.3


## The deploy separation, latched ONCE on the first descent (the root seeding Condition calls
## this) from facts the blackboard already carries: my deploy anchor's x and the enemy line's x
## are exactly one separation apart at tick 0. Latched, never re-read — enemies move, boards
## do not. Falls back to the authored reference when the bb has no enemy line (hand-built bbs).
static func _latch_span(bb) -> void:
	if float(bb.get_value("_board_span", 0.0)) > 0.0:
		return
	var home: Vector2 = bb.get_value("home_pos", Vector2.ZERO)
	var elx: float = float(bb.get_value("enemy_line_x", home.x))
	bb.set_value("_board_span", maxf(BOARD_REF_SPAN, absf(elx - home.x)))


static func _span(bb) -> float:
	var v: float = float(bb.get_value("_board_span", 0.0))
	return v if v > 0.0 else BOARD_REF_SPAN


## >= 1.0 always — see the ⚠️ above.
static func _board_scale(bb) -> float:
	return maxf(1.0, _span(bb) / BOARD_REF_SPAN)


## The hold line: board-derived, and it still carries the sim's stagnation ratchet on top.
static func _hold_radius(bb) -> float:
	var published: float = float(bb.get_value("hold_radius", HOLD_RADIUS_BASE))
	var stagnation_extra: float = maxf(0.0, published - HOLD_RADIUS_BASE)
	var span: float = _span(bb)
	# Advance until the enemy line is inside a working reach — capped at the centre-line rule,
	# floored at whatever the sim published. On the 110-wide board this is exactly `published`.
	var line: float = clampf(span - HOLD_REACH_REF, published, HOLD_LINE_FRAC * span * 0.5)
	return line + stagnation_extra


static func build(tactics: Dictionary) -> BT.BehaviourTree:
	var order_slot := BT.SubtreeSlot.new()
	var mode_slot := BT.SubtreeSlot.new()  # decision #38: modes INJECT subtrees here

	var root := BT.Selector.new("", [
		# MARKED ORDERS END-TO-END: tactics.ordered_id seeds the bb ONCE, on the first descent —
		# the sim does not fill ordered_id, so the mark must work from the tactics dict alone.
		# Seeded exactly once (never re-seeded): the urgent Order-void branch releases a DEAD
		# mark by clearing the bb key, and a per-tick re-seed would resurrect the corpse-order.
		# A hand-set bb ordered_id wins over the tactics seed. Always falls through (returns
		# false) so the selector continues — this node never claims the tick.
		BT.Condition.new("", func(bb):
			# BOARD SCALE: latch the deploy separation on the same first descent (see the
			# BOARD SCALE block). Must happen HERE — at tick 0 the enemy line is still the
			# enemy's deploy line, which is the one distance the tree can measure.
			_latch_span(bb)
			if not bb.get_value("_order_seeded", false):
				bb.set_value("_order_seeded", true)
				var oid: String = str(tactics.get("ordered_id", ""))
				if oid != "" and str(bb.get_value("ordered_id", "")) == "":
					bb.set_value("ordered_id", oid)
			return false),
		_urgent_branch(tactics),
		_when_hurt_branch(tactics),
		mode_slot,
		order_slot,
		_combat_branch(tactics),
		# §10: no idle state without a reason. If nothing above ran, the unit regroups — on the
		# NEAREST LIVING ALLY when one exists (rejoin the team, not an empty patch of ground),
		# else on the deploy anchor — and SAYS SO; "wandering in circles" is the reference failure.
		BT.Action.new("Regroup", func(bb):
			var me: Dictionary = bb.get_value("self", {})
			var my_pos: Vector2 = Vector2(me.get("pos", Vector2.ZERO))
			var best_ally: Dictionary = {}
			var best_d: float = INF
			for a in bb.get_value("allies", []):
				if a.hp > 0:
					var d: float = my_pos.distance_to(a.pos)
					if d < best_d:  # strict < : ties keep the earlier, id-ordered ally
						best_d = d
						best_ally = a
			if best_ally.is_empty():
				bb.set_value("req_move_to", bb.get_value("home_pos", Vector2.ZERO))
				bb._reason = "no target, no order — regrouping on anchor"
			else:
				bb.set_value("req_move_to", Vector2(best_ally.pos))
				bb._reason = "no target, no order — regrouping on %s" % str(best_ally.id)
			return BT.RUNNING),
	])
	var tree := BT.BehaviourTree.new(root)
	tree.register_slot("order", order_slot)
	tree.register_slot("mode", mode_slot)
	return tree


## ── Urgent (decision #27: taunted · ordered target gone · about to die · unreachable) ─────────
static func _urgent_branch(tactics: Dictionary) -> BT.BTBase:
	var when_hurt: String = str(tactics.get("when_hurt", "fight_on"))
	var children: Array = [
		# Taunted: answer it. Taunt is an ability effect and it wins over every priority.
		# The sim fills `taunted_by` when a tauntForce move lands (AOE LAYER); the compulsion
		# is the WHOLE decision: swap the working target and CLOSE on the taunter — a taunt
		# that only redirects the swing while the body walks elsewhere is half a taunt.
		BT.Sequence.new("Taunted", [
			BT.Condition.new("", func(bb): return str(bb.get_value("taunted_by", "")) != ""),
			BT.Action.new("Answer the taunt", func(bb):
				var tid: String = str(bb.get_value("taunted_by", ""))
				bb.set_value("req_attack", tid)
				bb.set_value("target_id", tid)
				# Enemy record for the position; a hand-built bb without one keeps its
				# current destination (the swing still swaps — that is the tested contract).
				for e in bb.get_value("enemies", []):
					if str(e.id) == tid:
						bb.set_value("target_pos", Vector2(e.pos))
						bb.set_value("req_move_to", Vector2(e.pos))
						break
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
static func _when_hurt_branch(tactics: Dictionary) -> BT.BTBase:
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
			# Aggression shapes the arming point (§9: personality weights branch selection):
			# an aggressive monster fights deeper into its HP bar before the branch arms, a
			# timid one arms early. 50 == exactly the authored hurt_at; small multiplier only.
			var armed: bool = frac <= float(tactics.get("hurt_at", 0.35)) * (1.25 - 0.5 * _aggr(bb))
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
static func _combat_branch(tactics: Dictionary) -> BT.BTBase:
	return BT.Sequence.new("Combat", [
		_target_node(tactics),
		_positional_node(tactics),
		_act_node(tactics),
	])


## Axis A: one scorer per priority, chosen by tactics; commitment via UtilitySelector
## stickiness keyed on focus_sticky (`reassess` == the sim sets it to 1.0).
##
## Two layers on top of the raw scorer, both data-shaped and both defaulting inert:
##   FOCUS-FIRE ASSIST — among candidates CLOSE in score, prefer the one the team has already
##   damaged (lowest hp fraction). Five monsters agreeing by coincidence was the measured
##   focus-fire failure (TACTICS_BRAINSTORM: priority lives on the individual); the shared
##   "finish what someone started" signal is the cheap coordination that fixes it.
##   EXECUTE WINDOW — a target below execute_frac is a kill about to happen: the tree commits
##   even under `reassess`, and the reason says "finishing X". Never overrides a live player
##   mark — the order stays sovereign.
static func _target_node(tactics: Dictionary) -> BT.BTBase:
	var mode: String = str(tactics.get("target_priority", "nearest"))
	return BT.Action.new("Mark " + mode, func(bb):
		var enemies: Array = bb.get_value("enemies", [])
		var live: Array = enemies.filter(func(e): return e.hp > 0)
		if live.is_empty():
			return BT.FAILURE
		var me: Dictionary = bb.get_value("self", {})
		var pick: Dictionary = {}
		var scorer := Callable()
		match mode:
			"marked":
				var oid: String = str(bb.get_value("ordered_id", ""))
				for e in live:
					if str(e.id) == oid:
						pick = e  # the player's mark: no assist, no scorer — the order is the pick
						break
				if pick.is_empty():
					scorer = func(e): return -Vector2(me.pos).distance_to(e.pos)
			"weakest":
				scorer = func(e): return -float(e.hp)
			"casters":
				scorer = func(e): return float(e.get("int_stat", 0)) + float(e.get("wis", 0))
			"tanks":
				scorer = func(e): return float(e.get("con", 0))
			"threat":
				scorer = func(e): return float(e.get("threat", 0.0))
			"healers":
				# KILL THE HEALER (§2A addendum): highest recent healing output among the living.
				# `heal_out` is sim-filled (wire-up pending — see the contract above); until an
				# enemy has actually healed, every heal_out is 0.0 and the priority DEFINEDLY
				# falls back to the casters scoring — a healer that has not healed yet is still
				# a caster, and a zero-score tie degenerating to array order would make the
				# priority mean "nearest by id", which is not a priority at all.
				var any_heal := false
				for e in live:
					if float(e.get("heal_out", 0.0)) > 0.0:
						any_heal = true
						break
				if any_heal:
					scorer = func(e): return float(e.get("heal_out", 0.0))
				else:
					scorer = func(e): return float(e.get("int_stat", 0)) + float(e.get("wis", 0))
			_:
				scorer = func(e): return -Vector2(me.pos).distance_to(e.pos)
		if pick.is_empty():
			pick = _best(live, scorer)
			# FOCUS-FIRE ASSIST: within the score band of the best, take the most-wounded
			# already-damaged candidate. Band is relative (|best|+1 keeps it sane for the
			# negative distance scores); strict < ties keep the earlier, id-ordered enemy.
			var best_s: float = float(scorer.call(pick))
			var band: float = float(bb.get_value("focus_assist_band", 0.15)) * (absf(best_s) + 1.0)
			var assist: Dictionary = pick
			# An untouched pick concedes to ANY team-damaged candidate in band (INF sentinel);
			# a damaged pick only concedes to a strictly MORE wounded one.
			var assist_frac: float = _hp_frac(pick) if _team_damaged(pick) else INF
			for e in live:
				if float(scorer.call(e)) >= best_s - band and _team_damaged(e):
					var f: float = _hp_frac(e)
					if f < assist_frac:
						assist = e
						assist_frac = f
			if _team_damaged(assist) and str(assist.id) != str(pick.id):
				pick = assist
		# Commitment: the incumbent survives unless the new pick beats it by the Focus margin.
		var sticky: float = maxf(1.0, float(bb.get_value("focus_sticky", 1.0)))
		var cur: String = str(bb.get_value("target_id", ""))
		# An opportunistic kick borrowed target_id for a tick; the pre-kick incumbent resumes.
		var kick_return: String = str(bb.get_value("_kick_return_id", ""))
		if kick_return != "":
			cur = kick_return
			bb.set_value("_kick_return_id", "")
		var exec_frac: float = float(bb.get_value("execute_frac", 0.25))
		if cur != "" and cur != str(pick.id):
			for e in live:
				if str(e.id) == cur:
					# EXECUTE WINDOW beats even `reassess`; plain stickiness needs sticky > 1.
					# A live player mark is never held against (decision #28's spirit: the
					# order is sovereign) — only scored picks yield to the execute commit.
					var marked_pick: bool = str(pick.id) == str(bb.get_value("ordered_id", ""))
					if (_hp_frac(e) <= exec_frac and not marked_pick) or sticky > 1.0:
						pick = e  # hold the incumbent; scorer margins are the sim's re-open signal
					break
		# BULL-THROUGH (decision #30): the blocking rule is a TACTIC. An INTERCEPTOR is a live
		# enemy that is not my pick, standing inside my reach while my pick is still OUT of
		# reach, and in the half-plane TOWARD the pick (a body behind me is not "in the way").
		# bull_through=true (THE DEFAULT) keeps the pick — the march continues and the sim's
		# opportunism handles any swing en route; false is the opt-in cautious tactic that
		# engages the blocker instead.
		# ⚠️ WHY THE DEFAULT IS TRUE, MEASURED: with false as the default, the quality probe's
		# dive/seed44444 comp collapsed — five divers engaged the enemy front's interceptors
		# instead of going around, and team A huddled to 5.6u at tick 100 (the §2B anti-blob
		# check). Engage-on-intercept as the unset behaviour un-dives every diver; it must be
		# a choice, never the ambient rule.
		# ⚠️ The false-path swap runs AFTER stickiness and the execute window on purpose:
		# for a unit that CHOSE caution, blocked is blocked — commitment to a target you
		# cannot path past is paralysis, not focus.
		var reach_i: float = float(bb.get_value("interceptor_reach", 6.6))
		var intercept_reason := ""
		if Vector2(me.pos).distance_to(pick.pos) > reach_i:
			var to_pick: Vector2 = (Vector2(pick.pos) - Vector2(me.pos)).normalized()
			var interceptor: Dictionary = {}
			var int_d: float = INF
			for e in live:
				if str(e.id) == str(pick.id):
					continue
				var d_e: float = Vector2(me.pos).distance_to(e.pos)
				if d_e > reach_i:
					continue
				var dir_e: Vector2 = (Vector2(e.pos) - Vector2(me.pos)).normalized() if d_e > 0.001 else to_pick
				if dir_e.dot(to_pick) <= 0.0:
					continue
				if d_e < int_d:  # strict < : ties keep the earlier, id-ordered enemy
					int_d = d_e
					interceptor = e
			if not interceptor.is_empty():
				if bool(tactics.get("bull_through", true)):
					# Hold course; log the decision ONCE per blocker, not per tick.
					if str(bb.get_value("_bull_id", "")) != str(interceptor.id):
						bb.set_value("_bull_id", str(interceptor.id))
						intercept_reason = "bulling through %s to %s" % [str(interceptor.id), str(pick.id)]
				else:
					if str(bb.get_value("_intercepted_id", "")) != str(interceptor.id):
						bb.set_value("_intercepted_id", str(interceptor.id))
						intercept_reason = "intercepted — engaging %s" % str(interceptor.id)
					pick = interceptor
			else:
				bb.set_value("_bull_id", "")
				bb.set_value("_intercepted_id", "")
		else:
			bb.set_value("_bull_id", "")
			bb.set_value("_intercepted_id", "")
		# The execute state is a decision worth logging ONCE per entry, not per tick.
		var finishing: String = str(pick.id) if _hp_frac(pick) <= exec_frac else ""
		if str(pick.id) != cur:
			bb._reason = "target: %s (%s)" % [str(pick.id), mode]
		if intercept_reason != "":
			bb._reason = intercept_reason
		if finishing != str(bb.get_value("_finishing_id", "")):
			bb.set_value("_finishing_id", finishing)
			if finishing != "":
				bb._reason = "finishing %s" % finishing
		bb.set_value("target_id", str(pick.id))
		bb.set_value("target_pos", pick.pos)
		return BT.SUCCESS)


## The bb enemy record for an id, or {} — enemies is id-ordered, first hit is the only hit.
static func _enemy_rec(bb, id: String) -> Dictionary:
	for e in bb.get_value("enemies", []):
		if str(e.id) == id:
			return e
	return {}


## HP fraction of an enemy record; the wounded-target currency both new layers trade in.
static func _hp_frac(e: Dictionary) -> float:
	return float(e.hp) / maxf(1.0, float(e.get("max_hp", 1)))


## "My team already started on this one." Prefers `team_dmg` (recent damage from MY team —
## sim-filled, see the contract above); missing HP is the stand-in for hand-built blackboards.
static func _team_damaged(e: Dictionary) -> bool:
	if float(e.get("team_dmg", 0.0)) > 0.0:
		return true
	return float(e.hp) < float(e.get("max_hp", e.hp))


## Aggression as a 0-1 multiplier input; 50 (the default) must always mean "exactly authored".
static func _aggr(bb) -> float:
	return clampf(float(bb.get_value("aggression", 50)) / 100.0, 0.0, 1.0)


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
static func _positional_node(tactics: Dictionary) -> BT.BTBase:
	var mode: String = str(tactics.get("positional", "push"))
	var wing: float = float(tactics.get("wing_side", 1))
	match mode:
		"hold":
			return BT.Action.new("Hold the line", func(bb):
				bb.set_value("posture", "Hold the line")
				var home: Vector2 = bb.get_value("home_pos", Vector2.ZERO)
				var tp: Vector2 = bb.get_value("target_pos", home)
				# Stand the line: meet the target only within the hold radius of home.
				# Low Aggression = tighter discipline (shorter leash); 50 = exactly authored.
				# The sim GROWS hold_radius under stagnation pressure (nothing landing for 15s)
				# so two turtled remnants cannot stand off forever — log the shift ONCE.
				# ⚠️ THE RADIUS IS THE BOARD'S, NOT A LITERAL 8.0 — see the BOARD SCALE block.
				# Measured: the literal parked every holder 390 units from its own fight.
				var hold_r: float = _hold_radius(bb) * (0.75 + 0.5 * _aggr(bb))
				var pressed: bool = bool(bb.get_value("stagnation_pressure", false))
				if pressed != bool(bb.get_value("_hold_pressed", false)):
					bb.set_value("_hold_pressed", pressed)
					if pressed:
						bb._reason = "nothing to hold against — pressing forward"
				var want: Vector2 = home + (tp - home).limit_length(hold_r)
				bb.set_value("req_move_to", want)
				return BT.SUCCESS)
		"wings":
			return BT.Action.new("Work the wing", func(bb):
				bb.set_value("posture", "Work the wing")
				var tp: Vector2 = bb.get_value("target_pos", Vector2.ZERO)
				# WING VARIETY: Aggression scales the WIDTH (§9) — bolder swings wider; 50 =
				# exactly the authored offset, the personality invariant everywhere in this file.
				# ⚠️ BOARD-SCALED (see the BOARD SCALE block): a flat 18 is a real flank on the
				# board this was authored for and 7% of the height of a 5v5 ground, which made
				# the anti-blob axis measure a THINNER footprint than a plain brawl.
				var lateral: float = float(bb.get_value("wing_offset", WING_OFFSET_BASE * _board_scale(bb))) \
					* wing * (0.7 + 0.6 * _aggr(bb))
				var axis_y: bool = bool(bb.get_value("wing_axis_y", true))
				var wp: Vector2 = Vector2(tp.x, tp.y + lateral) if axis_y else Vector2(tp.x + lateral, tp.y)
				# CROWDED WING: 2+ live enemies nearer MY wing point than the target means the
				# flank is already occupied — flip to the far side. Pure position reads, no rng;
				# the flip is a decision worth logging ONCE, not per tick.
				var crowd := 0
				for e in bb.get_value("enemies", []):
					if e.hp > 0 and Vector2(e.pos).distance_to(wp) < Vector2(e.pos).distance_to(tp):
						crowd += 1
				var flipped: bool = crowd >= 2
				if flipped:
					wp = Vector2(tp.x, tp.y - lateral) if axis_y else Vector2(tp.x - lateral, tp.y)
				if flipped != bool(bb.get_value("_wing_flipped", false)):
					bb.set_value("_wing_flipped", flipped)
					if flipped:
						bb._reason = "wing crowded — swinging to the other side"
				bb.set_value("req_move_to", wp)
				return BT.SUCCESS)
		"dive":
			return BT.Action.new("Dive the backline", func(bb):
				bb.set_value("posture", "Dive the backline")
				# Aim BEHIND the enemy line, not at the nearest body — the approach goes
				# around, which is the whole identity of the tactic.
				var tp: Vector2 = bb.get_value("target_pos", Vector2.ZERO)
				# High Aggression dives DEEPER behind the line; 50 = exactly the authored depth.
				var depth: float = float(bb.get_value("dive_depth", DIVE_DEPTH_BASE * _board_scale(bb))) \
					* (0.8 + 0.4 * _aggr(bb))
				var behind_x: float = float(bb.get_value("enemy_line_x", tp.x)) + depth * signf(tp.x - float(bb.get_value("self", {}).get("pos", Vector2.ZERO).x) + 0.001)
				bb.set_value("req_move_to", Vector2(behind_x, tp.y))
				return BT.SUCCESS)
		"kite":
			return BT.Action.new("Kite", func(bb):
				bb.set_value("posture", "Kite")
				var tp: Vector2 = bb.get_value("target_pos", Vector2.ZERO)
				var me: Dictionary = bb.get_value("self", {})
				var gap: float = float(bb.get_value("kite_gap", KITE_GAP_BASE * _board_scale(bb)))
				var near: float = float(bb.get_value("nearest_enemy_dist", INF))
				var back: float = 8.0 * _board_scale(bb)   # one backpedal step, board-relative
				var budget: int = int(bb.get_value("kite_ticks_left", 0))
				# #39: kiting has an END. Budget spent -> stand and fight, and say so.
				if budget <= 0:
					if str(bb.get_value("_kite_state", "")) != "spent":
						bb._reason = "kite budget spent — standing to fight"
						bb.set_value("_kite_state", "spent")
					bb.set_value("req_move_to", Vector2(me.pos))
					return BT.SUCCESS
				if near < gap:
					var away: Vector2 = (Vector2(me.pos) - tp).normalized() if Vector2(me.pos) != tp else Vector2(1, 0)
					if str(bb.get_value("_kite_state", "")) != "kiting":
						bb._reason = "kiting — keeping the gap"
						bb.set_value("_kite_state", "kiting")
					bb.set_value("req_move_to", Vector2(me.pos) + away * back)
					return BT.SUCCESS
				# ⚠️ THE GAP IS A GAP IN BOTH DIRECTIONS. A kiter with nobody near it used to
				# stand on its deploy anchor for the entire fight (MEASURED: advance 0.00 at
				# every sample on the real board, while its team fought 3v5). "Kite" is a
				# firing posture, not a refusal to take part: past KITE_ADVANCE_SLACK of the
				# gap, close to the edge of the gap and shoot from there.
				if near > gap * KITE_ADVANCE_SLACK:
					var to_t: Vector2 = Vector2(tp) - Vector2(me.pos)
					if to_t.length() > gap:
						if str(bb.get_value("_kite_state", "")) != "closing":
							bb._reason = "taking the firing line"
							bb.set_value("_kite_state", "closing")
						bb.set_value("req_move_to", Vector2(tp) - to_t.normalized() * gap)
						return BT.SUCCESS
				bb.set_value("_kite_state", "")
				bb.set_value("req_move_to", Vector2(me.pos))
				return BT.SUCCESS)
		"guard":
			return BT.Action.new("Guard the charge", func(bb):
				bb.set_value("posture", "Guard the charge")
				var gid: String = str(bb.get_value("guard_id", ""))
				# ⚠️ LIVING charge only — the allies list carries dead allies at hp 0, and an
				# unchecked lookup had a guard standing over its charge's corpse to the cap.
				var charge_pos = null
				for a in bb.get_value("allies", []):
					if str(a.id) == gid and a.hp > 0:
						charge_pos = a.pos
				if charge_pos == null:
					# Nothing left to guard: join the fight as push, and say so ONCE.
					if str(bb.get_value("_guard_state", "")) != "charge_gone":
						bb.set_value("_guard_state", "charge_gone")
						bb._reason = "charge %s is gone — joining the fight" % gid
					bb.set_value("posture", "Push")
					bb.set_value("req_move_to", bb.get_value("target_pos", Vector2.ZERO))
					return BT.SUCCESS
				# THE PEEL (WoW-arena): someone is on my charge - swap to them and stand in
				# the line between attacker and charge, so the body-block is literal.
				var att: String = str(bb.get_value("charge_attacker_id", ""))
				if att != "":
					for e in bb.get_value("enemies", []):
						if str(e.id) == att and e.hp > 0:
							if str(bb.get_value("target_id", "")) != att:
								bb._reason = "peel %s off %s" % [att, gid]
							bb.set_value("target_id", att)
							bb.set_value("target_pos", e.pos)
							bb.set_value("req_move_to", charge_pos.lerp(Vector2(e.pos), 0.6))
							return BT.SUCCESS
				# Nobody on the charge: station beside it, stay boring on purpose.
				bb.set_value("req_move_to", charge_pos)
				return BT.SUCCESS)
		_:
			return BT.Action.new("Push", func(bb):
				bb.set_value("posture", "Push")
				bb.set_value("req_move_to", bb.get_value("target_pos", Vector2.ZERO))
				return BT.SUCCESS)


## Axis D ability policy: free spends on cooldown; hold_big banks the capstone for the moment;
## combo spends only to set up or cash in a status. The sim supplies the booleans; the tree
## supplies the discipline.
static func _act_node(tactics: Dictionary) -> BT.BTBase:
	var policy: String = str(tactics.get("ability_policy", "free"))
	return BT.Action.new("Engage", func(bb):
		var tid: String = str(bb.get_value("target_id", ""))
		if tid == "":
			return BT.FAILURE
		# THE KICK (WoW-arena essence): the target is committed to a cast and my interrupt is
		# up - spend it. A kick is a resource; the sim enforces range and cooldown.
		if bb.get_value("target_casting", false) and bb.get_value("interrupt_ready", false):
			bb.set_value("req_interrupt", true)
			bb.set_value("req_attack", tid)
			bb._reason = "kick the cast on %s" % tid
			return BT.RUNNING
		# THE OPPORTUNISTIC KICK: my target is not casting, but SOMEONE in reach is, and my
		# interrupt is up — a kick wasted on nobody is worse than one lent off-target. The sim
		# executes interrupts against target_id, so borrow it for this tick; _target_node
		# restores the pre-kick incumbent via _kick_return_id next descent. Runs off the
		# sim-filled per-enemy `casting` key (default false keeps hand-built blackboards
		# inert). Id order = the deterministic tie-break, as everywhere.
		if bb.get_value("interrupt_ready", false):
			var me: Dictionary = bb.get_value("self", {})
			var kick_r: float = float(bb.get_value("kick_range", 6.0))
			for e in bb.get_value("enemies", []):
				if e.hp > 0 and bool(e.get("casting", false)) and str(e.id) != tid \
						and Vector2(me.get("pos", Vector2.ZERO)).distance_to(e.pos) <= kick_r:
					bb.set_value("_kick_return_id", tid)
					bb.set_value("target_id", str(e.id))
					bb.set_value("req_interrupt", true)
					bb.set_value("req_attack", str(e.id))
					bb._reason = "kick the cast on %s (off-target)" % str(e.id)
					return BT.RUNNING
		var cast_ok := true
		match policy:
			"hold_big":
				# HOLD_BIG'S MOMENT, DEFINED IN THE TREE from facts the bb already carries — the
				# sim needs no edit. The moment is: my target below big_moment_frac (a kill about
				# to be sealed) OR 3+ live enemies packed within big_moment_radius of the target
				# (the AoE payoff). Both authored, both bb-overridable. A sim/hand-set
				# `big_moment` true still forces it — the derived check only ever OPENS the
				# window, never closes a forced one.
				var moment: bool = bool(bb.get_value("big_moment", false))
				if not moment:
					var trec: Dictionary = _enemy_rec(bb, tid)
					if not trec.is_empty() and trec.hp > 0:
						if _hp_frac(trec) <= float(bb.get_value("big_moment_frac", 0.40)):
							moment = true
						else:
							var packed := 0
							var r_m: float = float(bb.get_value("big_moment_radius", 8.0))
							for e in bb.get_value("enemies", []):
								if e.hp > 0 and Vector2(trec.pos).distance_to(e.pos) <= r_m:
									packed += 1   # the target counts itself — 3+ bodies bunched
							moment = packed >= 3
				# The moment ARRIVING is a decision worth logging ONCE, not per tick.
				if moment != bool(bb.get_value("_big_moment", false)):
					bb.set_value("_big_moment", moment)
					if moment and bb.get_value("capstone_ready", false):
						bb._reason = "the moment — spending the capstone on %s" % tid
				cast_ok = not bb.get_value("capstone_ready", false) or moment
			"combo":
				# COMBO POLICY: `setup_status_live` — a sim/hand-set true wins; otherwise derive
				# from the target's published `statuses` array. The sim fills it AILMENTS-ONLY
				# (filtered by the beneficial table sim-side — see SIM-FILLED EXTRAS in the
				# header), so any entry means live setup. Hand-built bbs without the key still
				# fall back to the can_apply_setup gate unchanged.
				var setup_live: bool = bool(bb.get_value("setup_status_live", false))
				if not setup_live:
					var trec2: Dictionary = _enemy_rec(bb, tid)
					if not trec2.is_empty():
						setup_live = not (trec2.get("statuses", []) as Array).is_empty()
				cast_ok = setup_live or bb.get_value("can_apply_setup", true)
		bb.set_value("req_attack", tid)
		bb.set_value("req_cast_allowed", cast_ok)
		return BT.RUNNING)
