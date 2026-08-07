## THE PER-TICK ARGUMENT BUNDLE passed down through every `BTNode.tick(ctx)` call.
##
## ⚠️ DETERMINISM LIVES HERE. `dt` is the caller-supplied FIXED simulation step — this library
## never reads a frame `delta` internally, so whoever drives the tree (the spatial sim, most
## likely `spatial_sim.gd`'s AI-decide phase) must pass `Spatial.DT`, never `Engine`/`_process`
## timing. `rng` is a caller-owned, caller-SEEDED `RandomNumberGenerator` — this library never
## calls `randf()`/`randi()` itself, and any leaf/condition that needs randomness must draw from
## `ctx.rng`, never a bare global random call. Same seed + same orders must produce the same
## traversal every tick, every run — see docs/SPATIAL_HANDOFF.md §1.
##
## `agent` is intentionally untyped (`Variant`): this library has no idea what a "monster" is, and
## must not — it's generic infrastructure the actual monster tree (a separate, later piece of
## work) builds on top of. Pass whatever bundle your leaves need (the acting unit, the enemy list,
## tactics, obstacles, whatever) and read it back with a local `as`-cast or duck typing inside your
## own `BTAction`/`BTCondition` subclasses.
extends RefCounted
class_name BTContext

const BTBlackboardLib = preload("res://scripts/ai/bt_blackboard.gd")

var blackboard: BTBlackboardLib
var dt: float = 0.0
var rng: RandomNumberGenerator = null
var agent: Variant = null


func _init(p_blackboard: BTBlackboardLib, p_dt: float = 0.0,
		p_rng: RandomNumberGenerator = null, p_agent: Variant = null) -> void:
	blackboard = p_blackboard
	dt = p_dt
	rng = p_rng
	agent = p_agent
