## THE BEHAVIOUR TREE FRAMEWORK — AUTOBATTLER_DESIGN.md §9, decisions #30-33.
##
## The tree decides WHAT KIND of thing to do; utility scoring inside a node decides WHICH ONE.
## Tactics swap whole subtrees via named slots. Personality weights selection. And the tree is
## chosen for LEGIBILITY as much as behaviour: the active branch IS the explanation, so intent
## ("Combat → Engage → Path to target") and reason ("order: Break the Casters") fall out of the
## tick structurally instead of being reconstructed by the renderer after the fact.
##
## ⚠️ DETERMINISM IS A CONTRACT, NOT A HOPE (SPATIAL_HANDOFF §1, spike verdict in
## AUTOBATTLER_DESIGN §11). Nothing in here may read the clock, call randf(), or iterate an
## unordered container. All randomness arrives through the blackboard's injected RNG; ties in
## utility scoring break by CHILD ORDER, which is authored and stable.
##
## ⚠️ Inner classes + preload, never class_name — the class-name cache trap is documented in
## technical-preferences.md. Consumers: `const BT = preload("res://scripts/ai/bt.gd")`.
##
## ⚠️ IN GDSCRIPT, NOT DATA — a recorded exception to the data-driven standard (§9): the tree's
## SHAPE is code because a subtree is behaviour, but every NUMBER a node reads must come from
## the blackboard (which the sim fills from data.json), never be hardcoded in a node.
extends RefCounted

enum { FAILURE = 0, SUCCESS = 1, RUNNING = 2 }


## ── The blackboard ────────────────────────────────────────────────────────────────────────────
## Per-unit context: the sim writes world state and services in, nodes read and write scratch.
## Also the intent/reason channel: during a tick the descent path is built here, and the chain
## to the action that ran becomes the unit's intent for the frame — straight from the tree that
## made the decision (§12: the renderer derives NOTHING).
class Blackboard:
	var data: Dictionary = {}
	var rng: RandomNumberGenerator  # injected by the sim; the ONLY randomness source for nodes

	## Intent bookkeeping (framework-owned; nodes touch it through BTNode helpers only).
	var _path: Array[String] = []       # labels of the branch currently being descended
	var _intent: Array[String] = []     # the branch that produced this tick's action
	var _reason: String = ""            # why that branch won, set by the deciding node
	var _log: Array[Dictionary] = []    # the decision log: {tick, intent, reason} on CHANGE only
	var _last_logged_intent: String = ""

	func get_value(key: String, default = null):
		return data.get(key, default)

	func set_value(key: String, value) -> void:
		data[key] = value

	## The live intent label, e.g. "Combat → Engage → Path to target".
	func intent_string() -> String:
		return " → ".join(_intent)

	func reason() -> String:
		return _reason

	## The decision log records CHANGES of intent, not every tick — a 30-second fight at 10Hz
	## is 300 ticks and maybe a dozen decisions; the log is the dozen.
	func decision_log() -> Array[Dictionary]:
		return _log

	var _pending: Array[String] = []

	## Actions RECORD their branch during the descent; the TREE commits exactly once per tick,
	## with the LAST action's chain. A sequence's setup steps (mark target, choose position)
	## would otherwise each log their own "intent change" every tick and the decision log would
	## cycle A->B->C forever — one decision tick is ONE intent.
	func _record_intent() -> void:
		_pending = _path.duplicate()

	func _commit_pending(tick: int) -> void:
		if _pending.is_empty():
			return
		_intent = _pending
		var s := intent_string()
		if s != _last_logged_intent:
			_log.append({"tick": tick, "intent": s, "reason": _reason})
			_last_logged_intent = s


## ── Node base ─────────────────────────────────────────────────────────────────────────────────
class BTBase:
	var label: String = ""

	func _init(p_label: String = "") -> void:
		label = p_label

	## Override in leaves/composites. `tick` is the sim's integer tick — the only time that
	## exists in here.
	func tick(_bb: Blackboard, _tick: int) -> int:
		return FAILURE

	## Descend bookkeeping: composites and actions wrap their work in push/pop so the
	## blackboard's path always mirrors the live branch. Unlabelled nodes are structural and
	## stay out of the intent string.
	func _push(bb: Blackboard) -> void:
		if label != "":
			bb._path.append(label)

	func _pop(bb: Blackboard) -> void:
		if label != "":
			bb._path.pop_back()


## ── Composites ────────────────────────────────────────────────────────────────────────────────
## Selector: first child that doesn't FAIL wins. The order IS the priority — author it.
class Selector extends BTBase:
	var children: Array = []

	func _init(p_label: String = "", p_children: Array = []) -> void:
		super(p_label)
		children = p_children

	func tick(bb: Blackboard, t: int) -> int:
		_push(bb)
		for c in children:
			var r: int = c.tick(bb, t)
			if r != FAILURE:
				_pop(bb)
				return r
		_pop(bb)
		return FAILURE


## Sequence: every child must SUCCEED; a RUNNING child holds the sequence there.
class Sequence extends BTBase:
	var children: Array = []

	func _init(p_label: String = "", p_children: Array = []) -> void:
		super(p_label)
		children = p_children

	func tick(bb: Blackboard, t: int) -> int:
		_push(bb)
		for c in children:
			var r: int = c.tick(bb, t)
			if r != SUCCESS:
				_pop(bb)
				return r
		_pop(bb)
		return SUCCESS


## ── Leaves ────────────────────────────────────────────────────────────────────────────────────
## Condition: a pure predicate over the blackboard. Never mutates, never RUNNING.
class Condition extends BTBase:
	var fn: Callable

	func _init(p_label: String, p_fn: Callable) -> void:
		super(p_label)
		fn = p_fn

	func tick(bb: Blackboard, _t: int) -> int:
		return SUCCESS if fn.call(bb) else FAILURE


## Action: does the thing. Its label completes the intent string, and a successful or running
## action COMMITS the current branch as this tick's intent.
class Action extends BTBase:
	var fn: Callable  # func(bb) -> int status

	func _init(p_label: String, p_fn: Callable) -> void:
		super(p_label)
		fn = p_fn

	func tick(bb: Blackboard, _t: int) -> int:
		_push(bb)
		var r: int = fn.call(bb)
		if r != FAILURE:
			bb._record_intent()
		_pop(bb)
		return r


## ── Utility selection ─────────────────────────────────────────────────────────────────────────
## Picks the best-scoring child, with STICKINESS: the incumbent's score is multiplied by a
## commitment bonus so the unit doesn't oscillate between near-equal options — §10's "loses
## interest in the healer" guard, defaulted from Focus by the sim when it builds the bb.
##
## ⚠️ Ties break by CHILD ORDER (strict >), never by rng — determinism and authorability in one
## rule. The winning choice and its score are written as the tick's REASON.
class UtilitySelector extends BTBase:
	var children: Array = []          # BTNode
	var scorers: Array = []           # Callable(bb) -> float, parallel to children
	var sticky_key: String = ""       # bb key holding the stickiness multiplier (>= 1.0)
	var _incumbent: int = -1

	func _init(p_label: String, p_children: Array, p_scorers: Array, p_sticky_key: String = "") -> void:
		super(p_label)
		children = p_children
		scorers = p_scorers
		sticky_key = p_sticky_key
		assert(children.size() == scorers.size())

	func tick(bb: Blackboard, t: int) -> int:
		_push(bb)
		var sticky: float = 1.0
		if sticky_key != "":
			sticky = maxf(1.0, float(bb.get_value(sticky_key, 1.0)))
		var best := -1
		var best_score := -INF
		for i in children.size():
			var s: float = float(scorers[i].call(bb))
			if i == _incumbent:
				s *= sticky
			if s > best_score:
				best_score = s
				best = i
		if best < 0 or best_score <= 0.0:
			_pop(bb)
			return FAILURE
		if best != _incumbent:
			bb._reason = "%s: %s (%.2f)" % [label if label != "" else "chose", children[best].label, best_score]
		_incumbent = best
		var r: int = children[best].tick(bb, t)
		if r == FAILURE:
			_incumbent = -1  # a choice that cannot run must not stay incumbent
		_pop(bb)
		return r


## ── Subtree slots — how tactics plug in ───────────────────────────────────────────────────────
## A named mount point. `Dive` and `Hold the line` are different subtrees mounted into the same
## slot; swapping is O(1) and the rest of the tree never knows. An empty slot FAILS, so a
## Selector above it falls through to the default branch.
class SubtreeSlot extends BTBase:
	var subtree: BTBase = null

	func mount(p_subtree: BTBase) -> void:
		subtree = p_subtree

	func tick(bb: Blackboard, t: int) -> int:
		if subtree == null:
			return FAILURE
		_push(bb)
		var r: int = subtree.tick(bb, t)
		_pop(bb)
		return r


## ── The tree ──────────────────────────────────────────────────────────────────────────────────
## Owns the root and the slot registry. One tree per unit; the blackboard is per-unit too.
class BehaviourTree:
	var root: BTBase
	var _slots: Dictionary = {}  # name -> SubtreeSlot

	func _init(p_root: BTBase) -> void:
		root = p_root

	func register_slot(slot_name: String, slot: SubtreeSlot) -> void:
		_slots[slot_name] = slot

	## Tactics call this: mount a tactic's subtree into a named slot.
	func mount(slot_name: String, subtree: BTBase) -> void:
		assert(_slots.has(slot_name), "unknown slot: " + slot_name)
		(_slots[slot_name] as SubtreeSlot).mount(subtree)

	func tick(bb: Blackboard, t: int) -> int:
		bb._path.clear()
		bb._pending = []
		var r: int = root.tick(bb, t)
		bb._commit_pending(t)
		return r
