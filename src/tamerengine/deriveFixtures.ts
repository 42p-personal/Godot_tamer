// THE DERIVATION CONTRACT — stat pools, mana pricing, regen, cooldowns and cast times.
//
// ⚠️ THESE ARE THE NUMBERS EVERY OTHER NUMBER IS RELATIVE TO. `maxHp` decides how long a fight
// lasts; `maxMana` and the cost multiplier decide how many abilities a monster gets to use at
// all. A port that is 5% wrong here is wrong about the whole game in a way no single fight
// would localise — which is exactly why they get pinned separately from the damage math rather
// than being assumed to come along for the ride.
//
// All of it is pure arithmetic over stats. None of it touches geometry, so all of it survives
// the spatial rebuild unchanged.
import { Move, Channel, Stat, Stats } from '../core'
import { maxHp, maxMana, manaCost } from '../monster'
import {
  CHANNEL_CAST_TIME, COOLDOWN_MULT, FIELD_MANA_COST_MULT,
  WIS_REGEN_DIVISOR, MANA_SUPPORT_PER_SEC, SECONDS_PER_ROUND,
} from './types'

const stats = (over: Partial<Stats>): Stats =>
  ({ STR: 0, DEX: 0, CON: 0, WIS: 0, INT: 0, CHA: 0, ...over }) as Stats

function mv(over: Partial<Move> & { power: number }): Move {
  return {
    id: 'fixture', name: 'Fixture', stat: 'STR' as Stat, learnLevel: 1,
    type: 'damage', channel: 'melee' as Channel, target: 'enemy',
    cooldown: 1, accuracy: 100, range: 3,
    ...over,
  } as Move
}

/** Seconds of lockout a move costs after being cast: its cooldown plus its own cast time. */
const cooldownSeconds = (m: Move): number =>
  m.cooldown * COOLDOWN_MULT + (m.castTime ?? CHANNEL_CAST_TIME[m.channel])

/** Mana per second from standing still. WIS is the sole regen stat. */
const regenPerSec = (wis: number, isSupport: boolean): number =>
  wis / WIS_REGEN_DIVISOR + (isSupport ? MANA_SUPPORT_PER_SEC : 0)

export interface DeriveCase { name: string; axis: string; input: any; expect: any }

const CASES: DeriveCase[] = []
const add = (axis: string, name: string, input: any, expect: any) =>
  CASES.push({ name, axis, input, expect })

// ── maxHp ────────────────────────────────────────────────────────────────────
// ⚠️ THE FORMULA IS NOT `40 + CON x 2.0`. It carries a QUADRATIC term —
// `40 + CON*2 + CON^2/1600` — which CLAUDE.md did not document. At CON 300 that is +56 HP
// (a 9% pool), at CON 500 it is +156 (a 13% pool). A port written from the documentation
// would give every high-CON monster a smaller pool and every fight a shorter clock.
for (const con of [0, 50, 100, 200, 300, 400, 500, 800]) {
  add('maxHp', `maxHp at CON ${con}`, { CON: con }, maxHp(stats({ CON: con })))
}

// ── maxMana ──────────────────────────────────────────────────────────────────
// WIS is the foundation; INT contributes HALF its value, floored. The floor matters: an odd
// INT and an even INT one below it give the same pool.
for (const [wis, int] of [[0, 0], [100, 0], [0, 100], [100, 100], [50, 51], [50, 50], [300, 200]]) {
  add('maxMana', `maxMana at WIS ${wis} INT ${int}`, { WIS: wis, INT: int },
    maxMana(stats({ WIS: wis, INT: int })))
}

// ── mana pricing ─────────────────────────────────────────────────────────────
// ⚠️ AUTHORED COST WINS OUTRIGHT. Mana prices EFFECTIVENESS, not power — a move may be
// deliberately cheap for its number because it is paid for on some other axis.
add('manaCost', 'authored cost overrides the formula',
  { mana: 10, power: 100, type: 'damage' }, manaCost(mv({ power: 100, mana: 10 })))
add('manaCost', 'derived damage cost',
  { power: 100, type: 'damage' }, manaCost(mv({ power: 100 })))
add('manaCost', 'derived damage cost, tiny power hits the floor',
  { power: 1, type: 'damage' }, manaCost(mv({ power: 1 })))
add('manaCost', 'derived damage cost folds expected hits',
  { power: 20, type: 'damage', hits: [1, 6] },
  manaCost(mv({ power: 20, effects: { hits: [1, 6] } })))
// ⚠️ THERE IS NO `heal` MoveType. `MoveType` is damage/buff/debuff/status/control, so the
// branch the source comments call "heals" is really "any NON-damage move with positive power".
// A port that transcribed the comment rather than the code would price every restore wrong.
add('manaCost', 'non-damage move with power takes the heal branch',
  { power: 100, type: 'buff' }, manaCost(mv({ power: 100, type: 'buff' })))
add('manaCost', 'the heal branch has its own floor',
  { power: 1, type: 'buff' }, manaCost(mv({ power: 1, type: 'buff' })))
add('manaCost', 'zero-power utility takes the flat price',
  { power: 0, type: 'control' }, manaCost(mv({ power: 0, type: 'control' })))

// ── the field's cost multiplier ──────────────────────────────────────────────
// ⚠️ THE FIELD ENGINE PAYS 30% OF THE AUTHORED PRICE. The turn engine charges the full amount
// once per ROUND; a continuous field lets a unit cast far more often, so the same sticker price
// would starve every kit. A port that misses this can afford roughly a third of its abilities.
for (const p of [10, 30, 60]) {
  add('fieldMpCost', `field cost of a ${p}-mana move`, { mana: p },
    manaCost(mv({ power: 1, mana: p })) * FIELD_MANA_COST_MULT)
}

// ── regen ────────────────────────────────────────────────────────────────────
for (const wis of [0, 100, 200, 400]) {
  add('regen', `regen at WIS ${wis}`, { WIS: wis, support: false }, regenPerSec(wis, false))
  add('regen', `regen at WIS ${wis}, support role`, { WIS: wis, support: true }, regenPerSec(wis, true))
}

// ── cooldowns and cast times ─────────────────────────────────────────────────
// ⚠️ `cooldown` IS SECONDS, and it used to mean two different things at once — `battle.ts`
// decremented it per ROUND while the field engine multiplied it and decremented by dt. The
// unit is now honest; a port must not reintroduce the ambiguity.
const CHANNELS: Channel[] = ['melee', 'ranged', 'magic', 'voice', 'support']
for (const ch of CHANNELS) {
  add('castTime', `cast time for ${ch}`, { channel: ch }, CHANNEL_CAST_TIME[ch])
  add('cooldown', `cooldown of a 4s ${ch} move`, { cooldown: 4, channel: ch },
    cooldownSeconds(mv({ power: 1, cooldown: 4, channel: ch })))
}
add('cooldown', 'an authored castTime overrides the channel default',
  { cooldown: 4, channel: 'magic', castTime: 0.1 },
  cooldownSeconds(mv({ power: 1, cooldown: 4, channel: 'magic', castTime: 0.1 })))

// ── the rounds/seconds bridge ────────────────────────────────────────────────
// Status durations are authored in ROUNDS and lived in SECONDS. One constant joins them, and
// it is the reason a status is worth the same over its lifetime in either engine.
add('roundsToSeconds', 'one round in seconds', { rounds: 1 }, SECONDS_PER_ROUND)
add('roundsToSeconds', 'three rounds in seconds', { rounds: 3 }, 3 * SECONDS_PER_ROUND)

export const DERIVE_CASES = CASES

export function buildDeriveContract() {
  return {
    schema: 1,
    subject: 'monster.ts stat derivations + tamerengine/types.ts pacing constants',
    note: 'Pure arithmetic over stats — pools, mana pricing, regen, cooldowns, cast times. '
      + 'No geometry, so all of it survives the spatial rebuild. Regenerate with '
      + '`npx tsx tools/exportport.ts`.',
    cases: CASES,
  }
}
