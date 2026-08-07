## KIT BUILDER — real kits from data.json's 141 authored moves. The sim never invents a move:
## a kit entry CARRIES the data move verbatim (resolve_strike reads accuracy/power/variance/
## statScale/effects straight off it), and every derived number comes from the CONTRACTED
## Derive maths — cast time from the channel table, cooldown in honest seconds, field mana
## cost. One source of truth; a renamed or retuned move changes the sim without an edit here.
##
## ⚠️ SCOPE: `damage`-type moves always; debuff/control moves that CARRY A FIELD STATUS
## (status lands through the same accuracy roll as the strike — no double jeopardy); BUFF
## moves and self-targeted control moves whose payload the sim now expresses — heals
## (power-as-heal through the field heal rule), cleanse, the timed-mod keys
## (atkBuff/defBuff/accBuff/dodgeBuff/ward/guard/hpRegenBuff/regenBuff), and authored
## friendly statuses (Battle Hymn's haste, applied with no chance draw), targets
## self/ally/team; and status-less single-enemy debuffs whose keys are the mod system's
## (defDebuff/atkDebuff/accDebuff). Still skipped, loudly: `thorns` and `tauntForce` (not
## simulated — a kit accepting a taunt that never taunts would be a lie), `allEnemies`
## debuffs (AoE geometry is not built), and any move with NOTHING the sim expresses.
## A move accepted for one expressed component may still carry an unexpressed `thorns`
## alongside — that key alone never gates acceptance, only never-does-anything moves do.
extends RefCounted

const Derive = preload("res://scripts/derive.gd")

const GEOMETRY_SCALE := 2.2   # authored move.range is board units; the world is scaled (spatial.gd)

## Effect keys the sim turns into timed mods on FRIENDLY targets (sim.gd MOD_OF_EFFECT) …
const FRIENDLY_MOD_KEYS := ["atkBuff", "defBuff", "accBuff", "dodgeBuff", "ward", "guard",
	"hpRegenBuff", "regenBuff"]
## … and into timed mods on an ENEMY, applied on a landed hit (sim.gd _apply_enemy_debuffs).
const ENEMY_DEBUFF_KEYS := ["defDebuff", "atkDebuff", "accDebuff"]


## move_names -> sim kit entries. `moves` is data.json's moves array (id- or name-keyed lookup
## built here). Unknown names are a loud error — a kit that silently shrinks is the
## authored-but-unreachable failure this codebase keeps re-finding.
static func build(move_names: Array, moves: Array) -> Array:
	var out: Array = []
	var by_name := {}
	for m in moves:
		by_name[str(m.name)] = m
	for name in move_names:
		assert(by_name.has(str(name)), "kit move not in data.json: " + str(name))
		var mv: Dictionary = by_name[str(name)]
		var skip := _skip_reason(mv)
		if skip != "":
			push_warning("kit: '%s' skipped — %s" % [name, skip])
			continue
		out.append({
			"name": str(mv.name),
			"kind": "cast",
			"move": mv,                                   # the data move, verbatim
			"stat": str(mv.get("stat", "INT")),
			"channel": str(mv.get("channel", "magic")),
			"cast_time": Derive.cast_time_of(mv),
			"cooldown": Derive.cooldown_seconds(mv),
			"mana": Derive.field_mp_cost(mv),
			"range": float(mv.get("range", 6.0)) * GEOMETRY_SCALE,
			"min_range": 0.0,
		})
	return out


## "" to accept, else the loud reason naming the unexpressed effect keys.
static func _skip_reason(mv: Dictionary) -> String:
	var mtype := str(mv.get("type", ""))
	if mtype == "damage":
		return ""
	if mv.get("status") is Dictionary:
		return ""   # status-carrying debuff/control — the field-status path
	var fx = mv.get("effects")
	var fxd: Dictionary = fx if fx is Dictionary else {}
	var target := str(mv.get("target", "enemy"))
	if target in ["self", "ally", "team"]:
		# Friendly payload: heal (power-as-heal), cleanse, or any expressed mod key.
		if float(mv.get("power", 0)) > 0.0 or bool(fxd.get("cleanse", false)):
			return ""
		for k in FRIENDLY_MOD_KEYS:
			if fxd.has(k):
				return ""
		return "%s-type %s move with no expressed effect (keys: %s) — thorns/etc not simulated" \
			% [mtype, target, str(fxd.keys())]
	if fxd.has("tauntForce"):
		return "tauntForce not simulated — accepting it would cast a taunt that never taunts"
	if target == "allEnemies":
		return "allEnemies debuff — AoE geometry not built"
	for k in ENEMY_DEBUFF_KEYS:
		if fxd.has(k):
			return ""   # timed enemy debuff mods, applied on a landed hit
	return "%s-type with no field status and no expressed effect (keys: %s)" \
		% [mtype, str(fxd.keys())]


## The synthetic kick — interrupts are a CLASS feature, not one of the 141 authored moves.
static func kick() -> Dictionary:
	return {"name": "Kick", "kind": "interrupt"}
