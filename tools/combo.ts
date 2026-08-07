// DOES THE COMBO EVER ACTUALLY CONNECT?
//
// A `bonusVsStatus` move pays a premium — reduced base damage, or a cooldown, or
// mana — for a multiplier that only exists while its setup status is on the
// target. `tools/effects.ts` already says the payoffs are REACHABLE (8 moves,
// 175/640 monsters draft one, 5.1% of all casts). Reachable is not the question
// here.
//
// ⚠️ THE QUESTION IS WHETHER THE PREMIUM IS EVER COLLECTED. A payoff cast at a
// target with no setup on it is strictly a worse move than the plain attack it was
// priced against — the player paid for a conditional and got the condition's
// downside. That is invisible to every existing instrument: `effects.ts` counts the
// cast, the sweep counts the damage, and neither knows the rider did nothing.
//
// So this reports, per status: how many payoff casts LANDED IN THE WINDOW.
//
// ⚠️ THE WINDOW IS AN APPROXIMATION AND IT IS GENEROUS. Statuses are tracked from
// their `status` event for COMBO_WINDOW seconds; the event stream carries no expiry
// or cleanse, so a status that was dispelled early still counts as live here. That
// biases the connect rate UP. Read a low number as certainly low; read a high one
// with suspicion.
//
// `--roles` re-runs with `comboRole` assigned the way a player would: a monster
// holding a payoff DETONATES, one holding only an applier PRIMES. That is the
// tactic's best case, and the gap between the two runs is what the tactic is worth.
//
// Usage: npx tsx tools/combo.ts [--roles] [--elite]
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { FIELD_H, FIELD_W } from '../src/tamerengine/types'
import { ALL_MOVES } from '../src/moves'
import { CASHABLE_STATUSES } from '../src/moves'
import { COMPS, teamFor, trainTier } from './comps'
import type { Monster, StatusKind } from '../src/core'

const OB = [
  { x: FIELD_W * (19 / 40), y: FIELD_H * (6 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (21 / 40), y: FIELD_H * (15 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (13 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
  { x: FIELD_W * (27 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
]
const SEEDS = ['s1', 's2', 's3', 's4', 'q1', 'q2', 'q3', 'q4']
/** Seconds a status is assumed live after it is applied. Deliberately generous. */
const COMBO_WINDOW = 8

/** move name -> the status its bonusVsStatus rider needs. */
const NEEDS = new Map<string, StatusKind>()
for (const mv of ALL_MOVES) {
  const b = mv.effects?.bonusVsStatus
  if (b) NEEDS.set(mv.name, b.kind)
}

type Ev = { t: number; kind: string; id?: string; targetId?: string | null; move?: string; status?: string }

const hit = new Map<StatusKind, number>()
const miss = new Map<StatusKind, number>()
const bump = (m: Map<StatusKind, number>, k: StatusKind) => m.set(k, (m.get(k) ?? 0) + 1)

const ROLES = process.argv.includes('--roles')
/** Assign each monster the half of the combo its kit can actually play. */
const cast = (t: Monster[]): Monster[] => !ROLES ? t : t.map((m) => {
  const detonate = m.loadout.some((mv) => !!mv.effects?.bonusVsStatus)
  const prime = m.loadout.some((mv) => mv.status && CASHABLE_STATUSES.has(mv.status.kind))
  const comboRole = detonate ? 'detonate' as const : prime ? 'prime' as const : undefined
  return { ...m, tactics: { ...m.tactics, comboRole } }
})

for (const c of COMPS) for (const sd of SEEDS) {
  const A = cast(teamFor(c, 'a', sd))
  const B = cast(teamFor(c, 'b', sd))
  const front = (m: Monster) => ({ front: m.stats.CON + m.stats.STR - m.stats.INT - m.stats.WIS })
  const r = simulateFieldBattle({
    seed: sd + c.name, teamA: A, teamB: B, obstacles: OB,
    placeA: autoDeployByRole('A', A.map(front)), placeB: autoDeployByRole('B', B.map(front)),
  })
  // unit id -> status kind -> time it was last applied
  const applied = new Map<string, Map<string, number>>()
  for (const e of r.events as never as Ev[]) {
    if (e.kind === 'status' && e.id && e.status) {
      const m = applied.get(e.id) ?? new Map<string, number>()
      m.set(e.status, e.t)
      applied.set(e.id, m)
      continue
    }
    if (e.kind !== 'cast' || !e.move || !e.targetId) continue
    const need = NEEDS.get(e.move)
    if (!need) continue
    const at = applied.get(e.targetId)?.get(need)
    if (at !== undefined && e.t - at <= COMBO_WINDOW) bump(hit, need)
    else bump(miss, need)
  }
}

const kinds = [...new Set([...hit.keys(), ...miss.keys()])]
  .sort((a, b) => (hit.get(b) ?? 0) + (miss.get(b) ?? 0) - (hit.get(a) ?? 0) - (miss.get(a) ?? 0))
let H = 0, M = 0
console.log(`COMBO CONNECT RATE — train ${trainTier()}, ${COMPS.length * SEEDS.length} fights, `
  + `${COMBO_WINDOW}s window\n`)
console.log('setup status        payoff casts   connected   rate')
for (const k of kinds) {
  const h = hit.get(k) ?? 0
  const m = miss.get(k) ?? 0
  H += h; M += m
  console.log(`  ${k.padEnd(18)}${String(h + m).padStart(8)}${String(h).padStart(12)}`
    + `${(100 * h / Math.max(1, h + m)).toFixed(1).padStart(8)}%`
    + (h === 0 ? '   ← NEVER CONNECTS' : h / (h + m) < 0.25 ? '   ← mostly wasted' : ''))
}
console.log(`\n  ${'TOTAL'.padEnd(18)}${String(H + M).padStart(8)}${String(H).padStart(12)}`
  + `${(100 * H / Math.max(1, H + M)).toFixed(1).padStart(8)}%`)
console.log(`\n⚠️ A payoff cast OUTSIDE its window is worse than the plain attack it was`
  + `\n   priced against — the player paid for a conditional and got only the cost.`)
