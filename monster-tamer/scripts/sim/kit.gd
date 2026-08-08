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
## self/ally/team; status-less single-enemy debuffs whose keys are the mod system's
## (defDebuff/atkDebuff/accDebuff); and — the AOE LAYER round — `thorns` (flat melee reflect,
## worn as a timed mod), `tauntForce` (the sim compels the victim; the tree's Taunted branch
## answers), and `allEnemies` moves of every type (the sim resolves them as a burst within the
## move's authored range of the caster). Still skipped, loudly: any move with NOTHING the sim
## expresses — after this round that is exactly ONE move, Firewall (self, no effects: a ground
## zone the sim has no geometry for yet).
extends RefCounted

const Derive = preload("res://scripts/derive.gd")

const GEOMETRY_SCALE := 2.2   # authored move.range is board units; the world is scaled (spatial.gd)

## ── PER-MOVE PROJECTILES (#34) ───────────────────────────────────────────────────────────────
## A shot's flight is the most visible thing about it in a game whose battle loop is WATCHING,
## and until now it was two numbers keyed by CHANNEL — the same conflation `authorranges.ts` was
## written to undo one axis earlier. DEX's channel is `ranged` whether the move is a longbow or
## a stiletto, so a thrown knife at 2.8 reach and Deadeye at 9.2 flew identically, and every INT
## spell in the pool was one 55 u/s blob. `tools/authorprojectiles.ts` now authors speed, width
## and pierce per move, seeded per LINE; this reads them.
##
## ⚠️ THE CHANNEL CONSTANTS SURVIVE AS THE FALLBACK, VERBATIM. An unauthored move gets exactly
## the numbers sim.gd used before this field existed (ranged 90 / magic 55, width 0, no pierce),
## so adding the axis cannot regress a single fight on its own.
const CHANNEL_PROJECTILE_SPEED := {"ranged": 90.0, "magic": 55.0}
## Targets whose casts never fly: sim.gd `_execute_cast` resolves friendly casts on their own
## path and RETURNS before the channel check. Touch and aura, not shots.
const FRIENDLY_TARGETS := ["self", "ally", "team"]

## Effect keys the sim turns into timed mods on FRIENDLY targets (sim.gd MOD_OF_EFFECT) …
## (`thorns` joined in the AOE LAYER round — flat melee reflect worn as a timed mod)
const FRIENDLY_MOD_KEYS := ["atkBuff", "defBuff", "accBuff", "dodgeBuff", "ward", "guard",
	"hpRegenBuff", "regenBuff", "thorns"]
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
		var entry := {
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
		}
		_attach_projectile(entry, mv)
		out.append(entry)
	return out


## Attach the authored projectile block to a kit entry — or nothing at all, when the move does
## not fly. `entry.projectile` = {speed (world u/s), width_radii (BODY RADII, so the unit is in
## the name and nobody multiplies twice), pierce (ADDITIONAL bodies passed through)}.
##
## ⚠️ THE FLIGHT GATE IS THE CHANNEL, AND IT STAYS THE CHANNEL. sim.gd takes the projectile
## branch on `PROJECTILE_SPEED.has(chan)`; this is a SECOND lock on the same door, not a
## replacement for it. A move with no `projectile` key is not "instant" by that fact — it is
## instant because its channel is melee or voice, and the two tests must agree.
##
## ⚠️ `width_radii` AND `move.effects.pierce` ARE DIFFERENT QUANTITIES THAT SHARE A WORD.
## `effects.pierce` is armour penetration as a fraction of mitigation (Void Lance 0.5) and is
## read by the CONTRACTED resolve_strike. `projectile.pierce` is how many extra bodies the shot
## flies through. They are nested apart on purpose; never merge them.
static func _attach_projectile(entry: Dictionary, mv: Dictionary) -> void:
	var chan := str(mv.get("channel", "magic"))
	if not CHANNEL_PROJECTILE_SPEED.has(chan):
		return                                        # melee / voice / support: no flight
	if str(mv.get("target", "enemy")) in FRIENDLY_TARGETS:
		return                                        # friendly casts resolve before the branch
	var authored = mv.get("projectile")
	var a: Dictionary = authored if authored is Dictionary else {}
	entry["projectile"] = {
		# Fallback is the pre-#34 channel constant, verbatim — an unauthored move flies exactly
		# as it did before, so this plumbing on its own cannot move a fight.
		"speed": float(a.get("speed", CHANNEL_PROJECTILE_SPEED[chan])),
		# 0.0 is a POINT: it only ever touches the body it homed on, which is today's behaviour.
		"width_radii": float(a.get("width", 0.0)),
		"pierce": int(a.get("pierce", 0)),
	}


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
		return "%s-type %s move with no expressed effect (keys: %s)" \
			% [mtype, target, str(fxd.keys())]
	# AOE LAYER: tauntForce compels (sim fills `taunted_by`, the tree's Urgent branch answers),
	# and allEnemies moves resolve as a caster-centred burst — both are live, neither skips.
	if fxd.has("tauntForce"):
		return ""
	for k in ENEMY_DEBUFF_KEYS:
		if fxd.has(k):
			return ""   # timed enemy debuff mods, applied on a landed hit
	return "%s-type with no field status and no expressed effect (keys: %s)" \
		% [mtype, str(fxd.keys())]


## The synthetic kick — interrupts are a CLASS feature, not one of the 141 authored moves.
static func kick() -> Dictionary:
	return {"name": "Kick", "kind": "interrupt"}
