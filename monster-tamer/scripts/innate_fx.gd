## INNATE EFFECTS ON THE FIELD — the care loop's teeth.
##
## Computes a unit's ACTIVE innate effect dict, scaled by CARE POTENCY, for `spatial_sim.gd` to
## consume. This is the file that makes raising a monster matter in a fight: the user's decision
## (2026-08-06) is "care powers the innate" — happiness scales innate strength, and fighting on
## empty stamina adds a small, visible weariness.
##
## ⚠️ EVERY EFFECT APPLIES OUTSIDE THE CONTRACTED MATHS. `damage.gd`/`derive.gd`/`status_math.gd`
## are pinned by exact-equality contracts and are NEVER edited for this. Innate numbers travel
## through `resolve_strike`'s own INPUTS (`atkMult`, `accMod`, `dodgeMod`, move-fx pierce) or are
## applied before/after it (flatDR, lifesteal), exactly the pattern `facing_mult` established.
##
## ⚠️ POTENCY IS THE CARE LOOP. potency = 0.5 + happiness × 0.05 — a neglected monster (0
## happiness) fights with its gift at HALF strength; a beloved one (10) at full. Scaling rules
## per field shape: additive numbers scale linearly; multipliers scale their DISTANCE FROM 1.0
## (a 1.15 mult at potency 0.5 is 1.075, not 0.575 — the naive scale would turn a bonus into a
## catastrophic malus); "replacement" values (fleetfoot's backpedal mult, rearArcDeg) LERP from
## the engine default to the authored value, so low care degrades toward vanilla, never below it.
##
## ⚠️ ONE INNATE IS ACTIVE AT A TIME (TS rule, `Monster.activeInnate`): the first, unless the
## second is unlocked (any stat ≥ INNATE_SECONDARY_LEVEL) and the monster's `active_innate`
## selects it. The balance rule that follows — a self-only field must outnumber its aura twin —
## is authored TS-side and travels in the data.
class_name InnateFx
extends RefCounted

const Sp = preload("res://scripts/spatial.gd")

const INNATE_SECONDARY_LEVEL := 300.0

# ── care thresholds ───────────────────────────────────────────────────────────────────────────
const WEARY_STAMINA := 30.0     # below this, a monster fights weary
const WEARY_ACC := 8.0          # accuracy shaved off every weary attack
const WEARY_SPEED := 0.92       # weary movement multiplier

# ── spatial hook constants (board-derived, like every other spatial constant) ────────────────
const AURA_RADIUS := 9.0 * Sp.REACH_SCALE          # TS TEAM_AURA_RADIUS, lifted to the new ground
const CHARGE_RUN_DIST := 25.0                       # sustained-run distance that arms chargeDmg
const BRACE_TICKS := 10                             # 1s standing still arms braceDmg
const DUEL_RADIUS := 7.0 * Sp.GEOMETRY_SCALE        # "nobody else near" for duelDmg
const PACK_WINDOW_TICKS := 10                       # ally hit within 1s arms packDmg
const HOME_RADIUS := 14.0 * Sp.GEOMETRY_SCALE       # "near your station" for homeGround


static func potency(happiness: int) -> float:
	return 0.5 + clampf(float(happiness), 0.0, 10.0) * 0.05


## Which of the monster's innates is active. Mirrors the TS rule: second unlocks at 300 in any
## stat; `active_innate` (if the instance carries one) picks among unlocked, else the first.
static func active_innate_name(m) -> String:
	var innates: Array = m.get("innate") if m.get("innate") != null else []
	if innates.is_empty():
		return ""
	var idx := 0
	var wants: int = int(m.get("active_innate")) if m.get("active_innate") != null else 0
	if wants == 1 and innates.size() > 1:
		for stat in m.stats:
			if float(m.stats[stat]) >= INNATE_SECONDARY_LEVEL:
				idx = 1
				break
	var entry = innates[idx]
	return str(entry.get("name", "")) if entry is Dictionary else str(entry)


# Fields whose value REPLACES an engine default — they lerp default→authored by potency.
const _REPLACEMENTS := {
	"fleetfoot": -1.0,       # default filled at runtime from Sp.BACKPEDAL_MULT
	"rearArcDeg": 120.0,     # default rear arc
	"windupMult": 1.0,
	"auraEnemySlow": 1.0,
	"kbResist": 1.0,         # ⚠️ AUTHORED BUT DORMANT — knockback is not yet implemented in the
	                          # spatial sim, so this field has no consumer. Recorded honestly so
	                          # nobody reads its presence here as "wired". Wire it WITH knockback.
}

# Multiplier fields ≥ 1 — scale distance from 1.0.
const _MULTS := ["dmgMult", "firstHitMult", "lowHpDmgMult", "highHpDmgMult", "magicDmgMult",
	"executeMult", "auraDmgMult", "chargeDmg", "predatorDmg", "braceDmg", "duelDmg", "packDmg",
	"openFieldDmg"]


## The unit's full innate effect dict, potency-scaled. Ready for the sim to read directly.
static func compute(m, innate_table: Dictionary) -> Dictionary:
	var name := active_innate_name(m)
	if name == "" or not innate_table.has(name):
		return {}
	var raw: Dictionary = innate_table[name]
	var p := potency(int(m.happiness) if m.get("happiness") != null else 5)
	var out := {"_name": name, "_potency": p}
	for k in raw:
		var v = raw[k]
		if k == "statusOnHit":
			if v is Dictionary:
				var s: Dictionary = (v as Dictionary).duplicate()
				s["chance"] = float(s.get("chance", 0.0)) * p
				out[k] = s
			continue
		if not (v is float or v is int):
			out[k] = v
			continue
		var f := float(v)
		if k in _MULTS:
			out[k] = 1.0 + (f - 1.0) * p
		elif _REPLACEMENTS.has(k):
			var def := float(_REPLACEMENTS[k])
			if k == "fleetfoot":
				def = Sp.BACKPEDAL_MULT
			out[k] = lerpf(def, f, p)
		else:
			out[k] = f * p    # additive numbers: acc, dodge, crit, flatDR, regen, pierce, ...
	return out


## Sum a field across every LIVING carrier within AURA_RADIUS of `pos` — the spatial answer to
## the range question the TS side explicitly left open ("global, unconditional" would reintroduce
## the position-blindness bug the field engine fixed once already for cast team buffs).
static func aura_sum(field: String, pos: Vector2, carriers: Array, states: Dictionary) -> float:
	var total := 0.0
	for c in carriers:
		if not c.alive:
			continue
		var st: Dictionary = states.get(c, {})
		var fx: Dictionary = st.get("fx", {})
		if not fx.has(field):
			continue
		if (st["pos"] as Vector2).distance_to(pos) > AURA_RADIUS:
			continue
		total += float(fx[field])
	return total


## Multiplicative aura fold (auraDmgMult): 1.0 when nothing applies.
static func aura_mult(field: String, pos: Vector2, carriers: Array, states: Dictionary) -> float:
	var total := 1.0
	for c in carriers:
		if not c.alive:
			continue
		var st: Dictionary = states.get(c, {})
		var fx: Dictionary = st.get("fx", {})
		if not fx.has(field):
			continue
		if (st["pos"] as Vector2).distance_to(pos) > AURA_RADIUS:
			continue
		total *= float(fx[field])
	return total
