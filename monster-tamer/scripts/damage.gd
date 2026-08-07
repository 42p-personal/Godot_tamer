## THE DAMAGE MATH, PORTED FROM `src/tamerengine/damage.ts`.
##
## ⚠️ THIS IS THE FIRST FILE OF THE PORT AND IT IS DELIBERATELY THE ONLY ONE.
## The whole-fight goldens pin `duration 23.2s` — a number produced by pathfinding, cover
## geometry and reach, all of which this project rebuilds natively rather than receives. A
## correct Godot engine will NOT reproduce 23.2s. What it must reproduce, to the integer, is
## the arithmetic of a landed hit: what it is worth, in what ORDER the multipliers apply, and
## where the floors, caps and ceilings sit.
##
## ⚠️ SO THE SPATIAL INPUTS ARRIVE ALREADY RESOLVED. `behind_mult` and `flank_bonus` are the
## only two places the TypeScript reached into geometry. Godot will answer "is this unit
## behind that one?" with its own physics and its own navigation — and once it has an answer,
## everything downstream must match this file. That is a contract a rebuilt engine can honour.
##
## ⚠️ AND THE RNG ARRIVES AS THREE EXPLICIT DRAWS, NOT A GENERATOR. Reproducing this project's
## `mulberry32` bit-exactly would be a second, harder port bolted to the front of the real one,
## whose failures would present as engine bugs. The caller draws acc / crit / variance in that
## fixed order and passes the values.
##
## Verified against `data/combat.json` by `scripts/contract_test.gd` — 61 cases, 23 axes.
class_name Damage
extends RefCounted

# ── Mitigation curve (types.ts) ──────────────────────────────────────────────
const MIT_DIVISOR := 1150.0
const MIT_KNEE := 0.55      ## where returns start diminishing
const MIT_SOFT := 0.5       ## rate retained above the knee
const MIT_CEIL := 0.80      ## asymptote, never reached in practice

# ── The opening guard: full, then a linear fade, then gone ───────────────────
## ⚠️ THE HOLD IS AT FULL STRENGTH, NOT A RAMP DOWN FROM t=0. The bonus is still at maximum
## at t=30 and only reaches zero at t=45. A test baseline written at `now: 30` therefore sits
## at the MAXIMUM, not past it — which is exactly the mistake the TS fixtures made first time.
const OPENING_MIT_BONUS := 0.20  ## percentage POINTS of extra reduction
const OPENING_MIT_HOLD := 30.0   ## seconds at full strength
const OPENING_MIT_FADE := 15.0   ## seconds to decay to nothing

# ── Damage constants ─────────────────────────────────────────────────────────
const DAMAGE_MULT := 1.0
const BLOCK_DR := 0.2
const GUARD_MAX_FRACTION := 0.35
const CRIT_CHANCE := 0.08
const CRIT_MULT := 1.5
const EXECUTE_MULT := 1.5
const DEFAULT_VARIANCE := 0.15

## Per-channel damage trim. Melee pays more per hit because it must close the gap and stands
## in reach to do it; ranged pays less because distance is itself mitigation.
##
## ⚠️ THIS LIVED AS A PRIVATE CONST IN `engine.ts` AND IS EASY TO MISS IN A PORT. Missing it
## is 12% wrong on every melee swing and 12% wrong on every bow shot — small enough to read as
## float drift, large enough to change who wins.
const CHANNEL_DMG := {
	"melee": 1.12, "ranged": 0.88, "magic": 0.92, "voice": 1.0, "support": 1.0,
}

# ── statScale seed band (core.ts) ────────────────────────────────────────────
const STAT_SCALE_LOW := 1.0 / 320.0   ## ~lvl 40
const STAT_SCALE_HIGH := 1.0 / 130.0  ## ~lvl 920


## The coefficient a move actually uses — its authored value, else the level-seeded default.
static func stat_scale_of(move: Dictionary) -> float:
	if move.has("statScale") and move["statScale"] != null:
		return float(move["statScale"])
	var lvl := float(move.get("learnLevel", 1))
	var t: float = clampf((lvl - 40.0) / (920.0 - 40.0), 0.0, 1.0)
	return STAT_SCALE_LOW + (STAT_SCALE_HIGH - STAT_SCALE_LOW) * t


static func variance_of(move: Dictionary) -> float:
	if move.has("variance") and move["variance"] != null:
		return float(move["variance"])
	return DEFAULT_VARIANCE


## The opening guard's value at time `t`.
static func opening_mitigation(t: float) -> float:
	if t <= OPENING_MIT_HOLD:
		return OPENING_MIT_BONUS
	var over := t - OPENING_MIT_HOLD
	if over >= OPENING_MIT_FADE:
		return 0.0
	return OPENING_MIT_BONUS * (1.0 - over / OPENING_MIT_FADE)


## The mitigation curve: linear to the knee, then half-rate, clamped at the ceiling.
static func mitigation_for(def_stat: float, pierce: float = 0.0) -> float:
	var eff := def_stat * (1.0 - clampf(pierce, 0.0, 1.0))
	var raw := maxf(0.0, eff) / MIT_DIVISOR
	if raw <= MIT_KNEE:
		return raw
	return minf(MIT_CEIL, MIT_KNEE + (raw - MIT_KNEE) * MIT_SOFT)


## Read an optional effect off a move, tolerating both an absent key and an explicit null.
static func _fx(move: Dictionary, key: String):
	var e = move.get("effects")
	if e == null or not (e is Dictionary):
		return null
	var v = e.get(key)
	return v


## Resolve one hit. `inp` is a case from the contract; the return matches `StrikeOutcome`.
##
## ⚠️ THE ORDER OF THE MULTIPLIERS IS THE CONTRACT, not merely the set of them. Mitigation is
## a FRACTION and guard is FLAT, so `(raw * (1 - mit)) - guard` and `(raw - guard) * (1 - mit)`
## differ by a lot against a tank; `maxHpDmg` is added BEFORE mitigation so a giant-killer is
## reduced like any other damage rather than being true damage.
static func resolve_strike(inp: Dictionary) -> Dictionary:
	var move: Dictionary = inp["move"]
	var rolls: Dictionary = inp["rolls"]

	# ⚠️ accuracy figures are percentage POINTS throughout — never fractions.
	var accuracy := float(move["accuracy"]) - float(inp["accPenalty"]) + float(inp["accMod"]) \
		- float(inp["dodgeMod"]) + float(inp["flankBonus"])
	if float(rolls["acc"]) * 100.0 > accuracy:
		return {
			"hit": false, "crit": false, "dmg": 0, "wardSoaked": 0,
			"toHp": 0, "wardLeft": 0, "spendsOwnWard": false,
		}

	var crit := float(rolls["crit"]) < CRIT_CHANCE
	# FIRST STRIKE is an OPENING reward on a continuous field: the turn engine keys it off
	# `actedThisRound`, and a field has no rounds, so it reads "hasn't attacked yet".
	var opener := 1.0
	var fs = _fx(move, "firstStrikeMult")
	if fs != null and not bool(inp["defHasAttacked"]):
		opener = float(fs)

	# `power` is the MID-POINT of a range, never a fixed number.
	var v := variance_of(move)
	var spread := 1.0 - v + float(rolls["variance"]) * 2.0 * v

	var raw := opener * float(move["power"]) \
		* (1.0 + float(inp["atk"]) * stat_scale_of(move)) \
		* spread \
		* (CRIT_MULT if crit else 1.0) \
		* float(inp["behindMult"]) \
		* float(inp["falloff"]) \
		* float(inp["atkMult"]) \
		* float(CHANNEL_DMG.get(move["channel"], 1.0))

	# ── the conditional multipliers ──────────────────────────────────────────
	# Each is a payoff for a condition the caster had to CREATE, which is why they are worth
	# more than the flat number they replace.
	var hp_scale = _fx(move, "hpScale")
	if hp_scale != null:
		var f: float = clampf(float(inp["attackerHpFrac"]), 0.0, 1.0)
		raw *= float(hp_scale["atEmpty"]) + (float(hp_scale["atFull"]) - float(hp_scale["atEmpty"])) * f

	var consume_ward = _fx(move, "consumeWard")
	var spends_own_ward := consume_ward != null and float(inp["attackerWard"]) > 0.0
	if spends_own_ward:
		raw *= 1.0 + float(consume_ward) * float(inp["attackerWard"])

	var execute = _fx(move, "execute")
	if execute != null and float(inp["defHpFrac"]) <= float(execute):
		raw *= EXECUTE_MULT

	var bonus_vs = _fx(move, "bonusVsStatus")
	if bonus_vs != null and bool(inp["defHasBonusStatus"]):
		raw *= float(bonus_vs["mult"])

	# MAX-HP DAMAGE is added BEFORE mitigation — it scales with the target's pool rather than
	# the attacker's stat, which is what lets a damage class threaten a wall it cannot out-grind.
	var max_hp_dmg = _fx(move, "maxHpDmg")
	if max_hp_dmg != null:
		raw += float(inp["defMaxHp"]) * float(max_hp_dmg)

	# PIERCE ignores a FRACTION of the defence outright, never points.
	var pierce = _fx(move, "pierce")
	var pierce_f := 0.0 if pierce == null else minf(1.0, float(pierce))
	var mit := float(inp["defMit"]) * (1.0 - pierce_f)

	# ⚠️ The opening guard is added BEFORE the ceiling clamp so it cannot push a high-CON wall
	# past MIT_CEIL and make it unkillable early; the shred comes off AFTER, in points, and is
	# floored at 0 so it can strip armour but never invert it into a bonus.
	var mit_frac := maxf(0.0,
		minf(MIT_CEIL, mitigation_for(mit) + opening_mitigation(float(inp["now"])))
		- float(inp["defMitDebuff"]) / 100.0)

	var blocked := (1.0 - BLOCK_DR) if bool(inp["defBlocking"]) else 1.0
	var after_mult := raw * DAMAGE_MULT * (1.0 - mit_frac) \
		* float(inp["defStatusDmgTaken"]) * float(inp["defDmgTakenMod"]) * blocked

	# Guard is capped as a FRACTION of the incoming blow, so a big guard can never make a unit
	# outright immune — only very hard to chip. Floored at 1: every landed hit does something.
	#
	# ⚠️ `round()` MATCHES JS `Math.round` ONLY FOR NON-NEGATIVE VALUES. JS rounds half toward
	# +infinity; GDScript rounds half away from zero, so they disagree at exactly -0.5. Damage
	# is floored at 1 immediately after, so the difference is unreachable here — but do not
	# copy this line into a context that can go negative.
	var dmg := int(maxf(1.0, round(after_mult
		- minf(float(inp["defGuard"]), after_mult * GUARD_MAX_FRACTION))))

	# WARD soaks BEFORE health — an absorb pool that depletes, not a multiplier.
	var def_ward := maxf(0.0, float(inp["defWard"]))
	var ward_soaked := int(minf(def_ward, float(dmg)))
	return {
		"hit": true,
		"crit": crit,
		"dmg": dmg,
		"wardSoaked": ward_soaked,
		"toHp": dmg - ward_soaked,
		"wardLeft": int(def_ward) - ward_soaked,
		"spendsOwnWard": spends_own_ward,
	}
