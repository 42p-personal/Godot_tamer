## KIT BUILDER — real kits from data.json's 141 authored moves. The sim never invents a move:
## a kit entry CARRIES the data move verbatim (resolve_strike reads accuracy/power/variance/
## statScale/effects straight off it), and every derived number comes from the CONTRACTED
## Derive maths — cast time from the channel table, cooldown in honest seconds, field mana
## cost. One source of truth; a renamed or retuned move changes the sim without an edit here.
##
## ⚠️ SCOPE: `damage`-type moves always; debuff/control moves that CARRY A FIELD STATUS now
## build too — statuses are on the field, and a control move casts and lands its status through
## the same accuracy roll as any strike (no double jeopardy). Still skipped, loudly: buffs
## (ally/self targeting is not simulated — even haste would land on the wrong side), and
## status-less debuff/control (their payload is the mods system, which is not built).
extends RefCounted

const Derive = preload("res://scripts/derive.gd")

const GEOMETRY_SCALE := 2.2   # authored move.range is board units; the world is scaled (spatial.gd)


## move_names -> sim kit entries. `moves` is data.json's moves array (id- or name-keyed lookup
## built here). Unknown names are a loud error — a kit that silently shrinks is the
## authored-but-unreachable failure this codebase keeps re-finding.
static func build(move_names: Array, moves: Array) -> Array:
	var by_name := {}
	for m in moves:
		by_name[str(m.name)] = m
	var out: Array = []
	for name in move_names:
		assert(by_name.has(str(name)), "kit move not in data.json: " + str(name))
		var mv: Dictionary = by_name[str(name)]
		var mtype := str(mv.get("type", ""))
		if mtype == "buff":
			push_warning("kit: '%s' is buff-type — ally/self targeting not simulated yet, skipped" % [name])
			continue
		if mtype != "damage" and not (mv.get("status") is Dictionary):
			push_warning("kit: '%s' is %s-type with no field status — mods not simulated yet, skipped" % [name, mv.get("type")])
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


## The synthetic kick — interrupts are a CLASS feature, not one of the 141 authored moves.
static func kick() -> Dictionary:
	return {"name": "Kick", "kind": "interrupt"}
