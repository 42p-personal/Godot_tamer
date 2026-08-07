// DOES `targetPriority` ACTUALLY CHANGE WHO DIES?
//
// ⚠️ THE FAILURE THIS EXISTS FOR. `targetPriority` was set in the UI, set by three
// GAMEPLANS, and read by `priorityBias` — and did NOTHING on a melee monster,
// because `pickTarget` returned nearest-first and returned BEFORE the scoring loop
// that bias lives in. Most classes in the game are melee. A tool that counts
// references would have called the tactic live; only asking "who actually died"
// catches it.
//
// So this measures the ORDER'S CONSEQUENCE, not its wiring: give one side
// `casters` and see whether the other side's support monsters die sooner. If the
// order works, they do. If the numbers are identical the order is decorative.
//
// ⚠️ MIRRORED PAIRS. Compositions are not symmetric, so every fight is run both
// ways round and the score is what happened to the ORDERED side's victims —
// otherwise this measures which template happens to own more supports.
//
// Usage: npx tsx tools/priority.ts [casters|weakest|tanks] [--elite]
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { FIELD_H, FIELD_W } from '../src/tamerengine/types'
import { DEFAULT_TACTICS, roleOfClass } from '../src/core'
import { COMPS, teamFor, trainTier } from './comps'
import type { Monster, Tactics } from '../src/core'

const OB = [
  { x: FIELD_W * (19 / 40), y: FIELD_H * (6 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (21 / 40), y: FIELD_H * (15 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (13 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
  { x: FIELD_W * (27 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
]
const SEEDS = ['s1', 's2', 's3', 's4', 'q1', 'q2', 'q3', 'q4']
const ORDER = (process.argv[2] as Tactics['targetPriority']) ?? 'casters'

const front = (m: Monster) => ({ front: m.stats.CON + m.stats.STR - m.stats.INT - m.stats.WIS })
const order = (t: Monster[], p: Tactics['targetPriority']) =>
  t.map((m) => ({ ...m, tactics: { ...DEFAULT_TACTICS, ...m.tactics, targetPriority: p } }))

/** Seconds until the first SUPPORT-role monster on `side` died; null if none did. */
function firstSupportDeath(
  events: { t: number; kind: string; id?: string }[], victims: Monster[], side: 'A' | 'B',
): number | null {
  for (const e of events) {
    if (e.kind !== 'death' || !e.id || e.id[0] !== side) continue
    const m = victims[Number(e.id.slice(1))]
    if (m && roleOfClass(m.className) === 'support') return e.t
  }
  return null
}

const withOrder: number[] = []
const without: number[] = []
let killedOrdered = 0, killedPlain = 0, pairs = 0

for (const c of COMPS) for (const sd of SEEDS) {
  const A = teamFor(c, 'a', sd)
  const B = teamFor(c, 'b', sd)
  const placeA = autoDeployByRole('A', A.map(front))
  const placeB = autoDeployByRole('B', B.map(front))
  const run = (ta: Monster[], tb: Monster[]) =>
    simulateFieldBattle({ seed: sd + c.name, teamA: ta, teamB: tb, obstacles: OB, placeA, placeB })

  // Only pairs where the VICTIM side actually fields a support are informative —
  // ⚠️ counting the rest would dilute a real effect toward zero with fights in
  // which the order had nothing to express.
  const hasSupport = (t: Monster[]) => t.some((m) => roleOfClass(m.className) === 'support')
  for (const [att, def, defSide] of [['a', 'b', 'B'], ['b', 'a', 'A']] as const) {
    const victims = defSide === 'B' ? B : A
    if (!hasSupport(victims)) continue
    pairs++
    const ordered = att === 'a' ? run(order(A, ORDER), B) : run(A, order(B, ORDER))
    const plain = run(A, B)
    const tO = firstSupportDeath(ordered.events as never, victims, defSide)
    const tP = firstSupportDeath(plain.events as never, victims, defSide)
    if (tO !== null) { killedOrdered++; withOrder.push(tO) }
    if (tP !== null) { killedPlain++; without.push(tP) }
    void def
  }
}

const med = (xs: number[]) => xs.length ? [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)] : NaN
console.log(`targetPriority: '${ORDER}' — train ${trainTier()}, ${pairs} fights where the`
  + ` defender actually fields a support\n`)
console.log(`  support DIED             ordered ${killedOrdered}/${pairs}   vs plain ${killedPlain}/${pairs}`)
console.log(`  median time to that kill ordered ${med(withOrder).toFixed(1)}s   vs plain ${med(without).toFixed(1)}s`)
console.log(`\n⚠️ Identical numbers mean the ORDER IS DECORATIVE, whatever the reference`
  + `\n   count says. That was true of every melee monster until 2026-08-01.`)
