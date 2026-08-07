// THE COMBAT-MATH CONTRACT — the port's real acceptance test.
//
// ⚠️ IT REPLACES THE WHOLE-FIGHT GOLDENS FOR THE PORT, AND HERE IS WHY.
// `goldens.json` pins `duration 23.2s` and a final HP vector. Those numbers are produced by
// pathfinding, cover geometry, reach and target selection — every one of which Godot rebuilds
// natively rather than receiving as a port. A correct Godot engine will NOT reproduce 23.2s,
// and holding it to that would fail the port for doing exactly what was asked of it.
//
// What survives any spatial rebuild is the arithmetic: what a landed hit is worth, in what
// ORDER the multipliers apply, and where the floors, caps and ceilings sit. That is what this
// file tabulates, and a Godot engine that reproduces it is correct in the part being ported.
//
// ⚠️ THE MOVES HERE ARE SYNTHETIC, AND THAT IS DELIBERATE. Pinning the contract to `Scrap`'s
// power would make every balance pass break the port's test — a tuning change would present
// as an engine regression, which is precisely the failure mode `goldens.contract.test.ts` was
// written to prevent. Each fixture below isolates ONE axis with round numbers, so a diff names
// the mechanic that broke rather than the ability that moved.
//
// ⚠️ AND THE RNG IS AUTHORED, NOT DRAWN. Every case carries explicit `acc`/`crit`/`variance`
// rolls, so the port never has to reproduce `mulberry32` before it can compare a number. The
// seeded RNG is out of scope for the port, permanently.
import { Move, Channel, Stat } from '../core'
import { StrikeInput, StrikeOutcome, resolveStrike } from './damage'

/** A move with only the fields the damage math reads; the rest are inert filler. */
function mv(over: Partial<Move> & { power: number }): Move {
  return {
    id: 'fixture', name: 'Fixture', stat: 'STR' as Stat, learnLevel: 1,
    type: 'attack', channel: 'melee' as Channel, target: 'enemy',
    cooldown: 1, accuracy: 100, range: 3, mana: 0,
    ...over,
  } as Move
}

/**
 * A defenceless, unmodified target and a plain attacker. Every case below overrides only the
 * fields it is testing, so what a case does NOT say is as load-bearing as what it does.
 *
 * ⚠️ `defMit: 0` IS THE NEUTRAL, NOT A REALISTIC VALUE. A real defender always has CON or WIS,
 * but folding a stat into the baseline would smear the mitigation curve across every case and
 * a diff would stop naming one mechanic. Mitigation gets its own cases.
 */
const BASE: Omit<StrikeInput, 'move'> = {
  atk: 0, atkMult: 1, attackerHpFrac: 1, attackerWard: 0, accPenalty: 0, accMod: 0,
  defMit: 0, defMaxHp: 200, defHpFrac: 1, defWard: 0, dodgeMod: 0,
  defStatusDmgTaken: 1, defDmgTakenMod: 1, defGuard: 0, defMitDebuff: 0,
  defBlocking: false, defHasAttacked: true, defHasBonusStatus: false,
  behindMult: 1, flankBonus: 0, falloff: 1,
  // ⚠️ `now: 60` PUTS EVERY CASE PAST THE OPENING-MITIGATION RAMP, and the exact value is
  // load-bearing. The ramp holds at FULL strength for `OPENING_MIT_HOLD` = 30s and only then
  // fades over 15 more, so it is gone at t=45 and not a moment sooner. This baseline was
  // first written as `now: 30` — the end of the hold, where the bonus is still at its
  // maximum — which quietly folded 20 points of mitigation into all 61 cases and made the
  // case named "opening mitigation expired" a duplicate of the one named "at full". Leaving
  // it live would make every other number in the table a function of two mechanics at once.
  now: 60,
  rolls: { acc: 0, crit: 0.5, variance: 0.5 },
}

export interface CombatCase {
  name: string
  /** What this case isolates — the thing a diff here would be telling you about. */
  axis: string
  input: StrikeInput
}

const c = (name: string, axis: string, over: Partial<StrikeInput> & { move: Move }): CombatCase =>
  ({ name, axis, input: { ...BASE, ...over } })

export const COMBAT_CASES: CombatCase[] = [
  // ── the baseline, and the one number everything else is relative to ───────
  c('flat 100 power, no modifiers', 'baseline',
    { move: mv({ power: 100 }) }),

  // ── channel trim: the private constant a port would silently miss ─────────
  c('melee channel trim', 'channel', { move: mv({ power: 100, channel: 'melee' }) }),
  c('ranged channel trim', 'channel', { move: mv({ power: 100, channel: 'ranged' }) }),
  c('magic channel trim', 'channel', { move: mv({ power: 100, channel: 'magic' }) }),
  c('voice channel trim', 'channel', { move: mv({ power: 100, channel: 'voice' }) }),
  c('support channel trim', 'channel', { move: mv({ power: 100, channel: 'support' }) }),

  // ── the stat axis ────────────────────────────────────────────────────────
  c('statScale at 0 stat', 'statScale', { move: mv({ power: 100, statScale: 0.002 }), atk: 0 }),
  c('statScale at 200 stat', 'statScale', { move: mv({ power: 100, statScale: 0.002 }), atk: 200 }),
  c('statScale at 500 stat', 'statScale', { move: mv({ power: 100, statScale: 0.002 }), atk: 500 }),

  // ── variance: `power` is the MID-POINT of a range, never a fixed number ───
  c('variance floor roll', 'variance',
    { move: mv({ power: 100, variance: 0.5 }), rolls: { acc: 0, crit: 0.5, variance: 0 } }),
  c('variance ceiling roll', 'variance',
    { move: mv({ power: 100, variance: 0.5 }), rolls: { acc: 0, crit: 0.5, variance: 0.999999 } }),
  c('default variance, mid roll', 'variance', { move: mv({ power: 100 }) }),

  // ── accuracy: the miss path, and the two spatial inputs that feed it ──────
  c('roll exactly on the accuracy line', 'accuracy',
    { move: mv({ power: 100, accuracy: 80 }), rolls: { acc: 0.8, crit: 0.5, variance: 0.5 } }),
  c('roll just over the accuracy line is a miss', 'accuracy',
    { move: mv({ power: 100, accuracy: 80 }), rolls: { acc: 0.801, crit: 0.5, variance: 0.5 } }),
  c('blind penalty turns a hit into a miss', 'accuracy',
    { move: mv({ power: 100, accuracy: 80 }), accPenalty: 30, rolls: { acc: 0.6, crit: 0.5, variance: 0.5 } }),
  c('flank bonus turns a miss into a hit', 'accuracy',
    { move: mv({ power: 100, accuracy: 70 }), flankBonus: 10, rolls: { acc: 0.75, crit: 0.5, variance: 0.5 } }),
  c('dodge mod turns a hit into a miss', 'accuracy',
    { move: mv({ power: 100, accuracy: 90 }), dodgeMod: 20, rolls: { acc: 0.75, crit: 0.5, variance: 0.5 } }),

  // ── crit ─────────────────────────────────────────────────────────────────
  c('crit lands', 'crit', { move: mv({ power: 100 }), rolls: { acc: 0, crit: 0.0, variance: 0.5 } }),
  c('crit just misses its window', 'crit',
    { move: mv({ power: 100 }), rolls: { acc: 0, crit: 0.08, variance: 0.5 } }),

  // ── mitigation: the curve, its ceiling, pierce, and the shred ────────────
  c('mitigation at 100 defence', 'mitigation', { move: mv({ power: 100 }), defMit: 100 }),
  c('mitigation at 400 defence', 'mitigation', { move: mv({ power: 100 }), defMit: 400 }),
  c('mitigation at 2000 defence tests the ceiling', 'mitigation', { move: mv({ power: 100 }), defMit: 2000 }),
  c('magic channel mitigates against WIS not CON', 'mitigation',
    { move: mv({ power: 100, channel: 'magic' }), defMit: 400 }),
  c('half pierce through 400 defence', 'pierce',
    { move: mv({ power: 100, effects: { pierce: 0.5 } }), defMit: 400 }),
  c('full pierce ignores defence entirely', 'pierce',
    { move: mv({ power: 100, effects: { pierce: 1 } }), defMit: 400 }),
  c('over-full pierce clamps at 1', 'pierce',
    { move: mv({ power: 100, effects: { pierce: 2 } }), defMit: 400 }),
  c('armour shred takes points off the fraction', 'mitDebuff',
    { move: mv({ power: 100 }), defMit: 400, defMitDebuff: 12 }),
  c('shred cannot invert mitigation into a bonus', 'mitDebuff',
    { move: mv({ power: 100 }), defMit: 100, defMitDebuff: 90 }),

  // ── the opening-mitigation ramp ──────────────────────────────────────────
  c('opening mitigation at t=0, full strength', 'openingMitigation', { move: mv({ power: 100 }), now: 0 }),
  c('opening mitigation at the end of the hold', 'openingMitigation', { move: mv({ power: 100 }), now: 30 }),
  c('opening mitigation halfway through the fade', 'openingMitigation', { move: mv({ power: 100 }), now: 37.5 }),
  c('opening mitigation expired', 'openingMitigation', { move: mv({ power: 100 }), now: 45 }),
  c('opening guard cannot push a wall past the ceiling', 'openingMitigation',
    { move: mv({ power: 100 }), defMit: 2000, now: 0 }),

  // ── guard: FLAT, subtracted last, capped as a fraction of the blow ───────
  c('guard subtracts flat', 'guard', { move: mv({ power: 100 }), defGuard: 10 }),
  c('guard is capped as a fraction of the blow', 'guard', { move: mv({ power: 100 }), defGuard: 500 }),
  c('guard cannot reduce a hit below 1', 'guard', { move: mv({ power: 2 }), defGuard: 500 }),

  // ── block ────────────────────────────────────────────────────────────────
  c('blocking target', 'block', { move: mv({ power: 100 }), defBlocking: true }),
  c('block stacks with mitigation', 'block', { move: mv({ power: 100 }), defBlocking: true, defMit: 400 }),

  // ── ward: an absorb pool, soaked BEFORE health ───────────────────────────
  c('ward soaks the whole blow', 'ward', { move: mv({ power: 100 }), defWard: 500 }),
  c('ward partially soaks', 'ward', { move: mv({ power: 100 }), defWard: 40 }),
  c('ward exactly covers the blow', 'ward', { move: mv({ power: 100 }), defWard: 112 }), // 100 x 1.12 melee

  // ── the conditional multipliers ──────────────────────────────────────────
  c('execute under the threshold', 'execute',
    { move: mv({ power: 100, effects: { execute: 0.25 } }), defHpFrac: 0.2 }),
  c('execute exactly on the threshold', 'execute',
    { move: mv({ power: 100, effects: { execute: 0.25 } }), defHpFrac: 0.25 }),
  c('execute above the threshold does nothing', 'execute',
    { move: mv({ power: 100, effects: { execute: 0.25 } }), defHpFrac: 0.26 }),
  c('first strike against a target that has not swung', 'firstStrike',
    { move: mv({ power: 100, effects: { firstStrikeMult: 1.5 } }), defHasAttacked: false }),
  c('first strike against a target that already swung', 'firstStrike',
    { move: mv({ power: 100, effects: { firstStrikeMult: 1.5 } }), defHasAttacked: true }),
  c('hpScale at full health', 'hpScale',
    { move: mv({ power: 100, effects: { hpScale: { atEmpty: 2, atFull: 0.5 } } }), attackerHpFrac: 1 }),
  c('hpScale at empty', 'hpScale',
    { move: mv({ power: 100, effects: { hpScale: { atEmpty: 2, atFull: 0.5 } } }), attackerHpFrac: 0 }),
  c('hpScale halfway', 'hpScale',
    { move: mv({ power: 100, effects: { hpScale: { atEmpty: 2, atFull: 0.5 } } }), attackerHpFrac: 0.5 }),
  c('bonusVsStatus with the status present', 'bonusVsStatus',
    { move: mv({ power: 100, effects: { bonusVsStatus: { kind: 'burn', mult: 1.6 } } }), defHasBonusStatus: true }),
  c('bonusVsStatus without it', 'bonusVsStatus',
    { move: mv({ power: 100, effects: { bonusVsStatus: { kind: 'burn', mult: 1.6 } } }), defHasBonusStatus: false }),
  c('consumeWard shatters the attacker shield', 'consumeWard',
    { move: mv({ power: 100, effects: { consumeWard: 0.01 } }), attackerWard: 50 }),
  c('consumeWard with no ward to spend', 'consumeWard',
    { move: mv({ power: 100, effects: { consumeWard: 0.01 } }), attackerWard: 0 }),
  c('maxHpDmg is added before mitigation', 'maxHpDmg',
    { move: mv({ power: 100, effects: { maxHpDmg: 0.1 } }), defMaxHp: 400, defMit: 400 }),
  c('maxHpDmg with no mitigation', 'maxHpDmg',
    { move: mv({ power: 100, effects: { maxHpDmg: 0.1 } }), defMaxHp: 400 }),

  // ── the two resolved spatial inputs ──────────────────────────────────────
  c('backstab multiplier', 'behind', { move: mv({ power: 100 }), behindMult: 1.5 }),
  c('aoe falloff at the edge', 'falloff', { move: mv({ power: 100 }), falloff: 0.5 }),

  // ── the buff/debuff multipliers ──────────────────────────────────────────
  c('attack buff', 'mods', { move: mv({ power: 100 }), atkMult: 1.3 }),
  c('vulnerable status', 'mods', { move: mv({ power: 100 }), defStatusDmgTaken: 1.25 }),
  c('damage-taken debuff', 'mods', { move: mv({ power: 100 }), defDmgTakenMod: 1.2 }),
  c('every multiplier at once', 'mods',
    { move: mv({ power: 100 }), atkMult: 1.3, defStatusDmgTaken: 1.25, defDmgTakenMod: 1.2 }),

  // ── the floor rule ───────────────────────────────────────────────────────
  c('a landed hit always does at least 1', 'floor',
    { move: mv({ power: 1 }), defMit: 2000, falloff: 0.1 }),
]

export interface CombatContract {
  schema: number
  subject: string
  note: string
  cases: { name: string; axis: string; input: StrikeInput; expect: StrikeOutcome }[]
}

export function buildCombatContract(): CombatContract {
  return {
    schema: 1,
    subject: 'tamerengine/damage.ts:resolveStrike',
    note: 'The port contract for the COMBAT MATH. Spatial inputs (behindMult, flankBonus, '
      + 'falloff) arrive resolved, and the three rng draws are authored, so a ported engine '
      + 'reproduces `expect` from `input` with no geometry and no seeded RNG. Regenerate with '
      + '`npx tsx tools/exportcombat.ts`.',
    cases: COMBAT_CASES.map((k) => ({ ...k, expect: resolveStrike(k.input) })),
  }
}
