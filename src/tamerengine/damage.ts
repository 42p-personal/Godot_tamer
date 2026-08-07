// THE DAMAGE MATH, AS A PURE FUNCTION. This is the port contract's real subject.
//
// ⚠️ IT EXISTS BECAUSE THE GODOT PORT REBUILDS THE SPATIAL LAYER AND KEEPS THE MATH.
// The whole-fight goldens (`goldens.json`) pin `duration 23.2s` — a number produced by
// pathfinding, cover geometry and reach, all of which are being replaced natively rather
// than ported. Diffing a Godot engine against them would FAIL A CORRECT PORT. What must
// survive a spatial rebuild is the arithmetic: what a hit is worth, in what order the
// multipliers apply, and where the floors and ceilings sit.
//
// ⚠️ SO THE SPATIAL INPUTS ARRIVE ALREADY RESOLVED, AND THAT IS THE ENTIRE DESIGN.
// `behindMult` and `flankBonus` are the only two places the old `strike()` reached into
// geometry. They come in as scalars. Godot decides "is this unit behind that one?" with its
// own physics and its own navigation — and once it has an answer, the damage that follows
// must match this file to the integer. That is a contract a rebuilt engine can actually
// honour, which is more than the fight goldens can say.
//
// ⚠️ AND THE RNG ARRIVES AS THREE EXPLICIT DRAWS, NOT AS A GENERATOR. A function that pulls
// from a stream cannot be tabulated, so it cannot be a contract — the port would have to
// reproduce this project's `mulberry32` bit-exactly before it could compare a single number.
// The caller draws `acc`, `crit`, `variance` in that fixed order (see `strike()` in
// engine.ts, which is the ONLY reason the order is load-bearing) and passes the values.
//
// What is deliberately NOT here: lifesteal, thorns, mana-on-hit, the status rider, contagion
// and the on-target spatial rider. Those mutate two units and emit events; they are sequencing,
// not arithmetic, and they stay in the engine where the loop can see them.
import { Move, statScaleOf, varianceOf } from '../core'
import { mitigationFor, openingMitigation, MIT_CEIL, DAMAGE_MULT, BLOCK_DR, GUARD_MAX_FRACTION } from './types'

/**
 * Per-channel damage trim. Melee pays more per hit because it must close the gap and
 * stands in reach to do it; ranged pays less because distance is itself mitigation.
 *
 * ⚠️ LIVED IN `engine.ts` AS A PRIVATE CONST AND IS NOW PART OF THE CONTRACT. A port that
 * missed it would be wrong by 12% on every melee swing and 12% on every bow shot — a
 * difference small enough to look like float drift and large enough to change who wins.
 */
export const CHANNEL_DMG: Record<string, number> = {
  melee: 1.12, ranged: 0.88, magic: 0.92, voice: 1, support: 1,
}

export const CRIT_CHANCE = 0.08
export const CRIT_MULT = 1.5
/** `execute` is authored as the HP FRACTION it triggers under; the payoff is fixed. */
export const EXECUTE_MULT = 1.5

/** Everything the damage calculation reads, with geometry already answered. */
export interface StrikeInput {
  move: Move
  /** The attacker's value in `move.stat`. */
  atk: number
  /** `modAtk` — the product of the attacker's round-limited atk multipliers. */
  atkMult: number
  /** The attacker's HP fraction, for `hpScale`. Clamped internally. */
  attackerHpFrac: number
  /** The attacker's current ward, for `consumeWard`. */
  attackerWard: number
  /** Accuracy points lost to blind/confusion. */
  accPenalty: number
  /** `modAcc` — accuracy points from buffs. */
  accMod: number

  /** The defender's CON (melee/ranged) or WIS (magic/voice/support). */
  defMit: number
  defMaxHp: number
  defHpFrac: number
  defWard: number
  /** `modDodge` — accuracy points the defender removes. */
  dodgeMod: number
  /** `statusDamageTaken` — vulnerable and friends, as a multiplier. */
  defStatusDmgTaken: number
  /** `modDmgTaken` — buff-sourced damage-taken multiplier. */
  defDmgTakenMod: number
  /** `modGuard` — FLAT reduction, subtracted last and capped. */
  defGuard: number
  /** `modMitDebuff` — armour shred, in PERCENTAGE POINTS off the mitigation fraction. */
  defMitDebuff: number
  defBlocking: boolean
  /** Whether the defender has thrown a blow yet, for `firstStrikeMult`. */
  defHasAttacked: boolean
  /** Whether the defender carries the status `bonusVsStatus` is looking for. */
  defHasBonusStatus: boolean

  // ── the two spatial answers, already resolved ─────────────────────────────
  /** Backstab multiplier: the move's `backstab` if genuinely behind, else 1. */
  behindMult: number
  /** Accuracy points for attacking an outnumbered, unsupported target. */
  flankBonus: number
  /** AoE distance falloff. 1 for a single-target hit. */
  falloff: number

  /** Seconds into the fight, for the opening-mitigation ramp. */
  now: number
  /** The three draws, in the order `strike()` takes them. Each in [0, 1). */
  rolls: { acc: number; crit: number; variance: number }
}

export interface StrikeOutcome {
  hit: boolean
  crit: boolean
  /** Total damage after every multiplier, floor and cap. 0 on a miss. */
  dmg: number
  /** How much the ward absorbed. */
  wardSoaked: number
  /** What actually came off HP. */
  toHp: number
  /** The defender's ward after soaking. */
  wardLeft: number
  /** Whether the attacker's own ward is spent (`consumeWard` on a landed hit). */
  spendsOwnWard: boolean
}

const MISS: StrikeOutcome = {
  hit: false, crit: false, dmg: 0, wardSoaked: 0, toHp: 0, wardLeft: 0, spendsOwnWard: false,
}

/**
 * Resolve one hit.
 *
 * ⚠️ THE ORDER OF THE MULTIPLIERS IS THE CONTRACT, not just the set of them. Mitigation is
 * a FRACTION and guard is FLAT, so `(raw × (1 − mit)) − guard` and `(raw − guard) × (1 − mit)`
 * differ by a lot against a tank; `maxHpDmg` is added BEFORE mitigation so a giant-killer is
 * reduced like any other damage rather than being true damage. Each of these was decided
 * once and is easy to get subtly wrong in a second language.
 */
export function resolveStrike(inp: StrikeInput): StrikeOutcome {
  const mv = inp.move
  const fx = mv.effects

  // ⚠️ accuracy figures are percentage POINTS throughout — never fractions.
  const acc = mv.accuracy - inp.accPenalty + inp.accMod - inp.dodgeMod + inp.flankBonus
  if (inp.rolls.acc * 100 > acc) return MISS

  const crit = inp.rolls.crit < CRIT_CHANCE
  // FIRST STRIKE is an OPENING reward on a continuous field: the turn engine keys it off
  // `actedThisRound`, and a field has no rounds, so it reads "hasn't attacked yet".
  const opener = fx?.firstStrikeMult && !inp.defHasAttacked ? fx.firstStrikeMult : 1
  // `power` is the MID-POINT of a range, never a fixed number.
  const v = varianceOf(mv)
  const spread = 1 - v + inp.rolls.variance * 2 * v

  let raw = opener * mv.power * (1 + inp.atk * statScaleOf(mv)) * spread
    * (crit ? CRIT_MULT : 1) * inp.behindMult * inp.falloff * inp.atkMult
    * (CHANNEL_DMG[mv.channel] ?? 1)

  // ── the conditional multipliers ──────────────────────────────────────────
  // Each is a payoff for a condition the caster had to CREATE, which is why they are worth
  // more than the flat number they replace.
  if (fx?.hpScale) {
    const f = Math.max(0, Math.min(1, inp.attackerHpFrac))
    raw *= fx.hpScale.atEmpty + (fx.hpScale.atFull - fx.hpScale.atEmpty) * f
  }
  const spendsOwnWard = !!fx?.consumeWard && inp.attackerWard > 0
  if (spendsOwnWard) raw *= 1 + fx!.consumeWard! * inp.attackerWard
  if (fx?.execute && inp.defHpFrac <= fx.execute) raw *= EXECUTE_MULT
  if (fx?.bonusVsStatus && inp.defHasBonusStatus) raw *= fx.bonusVsStatus.mult
  // MAX-HP DAMAGE is added BEFORE mitigation — it scales with the target's pool rather than
  // the attacker's stat, which is what lets a damage class threaten a wall it cannot out-grind.
  if (fx?.maxHpDmg) raw += inp.defMaxHp * fx.maxHpDmg

  // PIERCE ignores a FRACTION of the defence outright, never points.
  const mit = inp.defMit * (1 - Math.min(1, fx?.pierce ?? 0))
  // ⚠️ The opening guard is added BEFORE the ceiling clamp so it cannot push a high-CON wall
  // past MIT_CEIL and make it unkillable early; the shred comes off AFTER, in points, and is
  // floored at 0 so it can strip armour but never invert it into a bonus.
  const mitFrac = Math.max(0, Math.min(MIT_CEIL,
    mitigationFor(mit) + openingMitigation(inp.now)) - inp.defMitDebuff / 100)

  const blocked = inp.defBlocking ? 1 - BLOCK_DR : 1
  const afterMult = raw * DAMAGE_MULT * (1 - mitFrac) * inp.defStatusDmgTaken
    * inp.defDmgTakenMod * blocked
  // Guard is capped as a FRACTION of the incoming blow, so a big guard can never make a unit
  // outright immune — only very hard to chip. Floored at 1: every landed hit does something.
  const dmg = Math.max(1, Math.round(afterMult
    - Math.min(inp.defGuard, afterMult * GUARD_MAX_FRACTION)))

  // WARD soaks BEFORE health — an absorb pool that depletes, not a multiplier.
  const wardSoaked = Math.min(Math.max(0, inp.defWard), dmg)
  return {
    hit: true,
    crit,
    dmg,
    wardSoaked,
    toHp: dmg - wardSoaked,
    wardLeft: Math.max(0, inp.defWard) - wardSoaked,
    spendsOwnWard,
  }
}
