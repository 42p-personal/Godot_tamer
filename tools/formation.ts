// IS `formation: 'keep'` A REAL OPTION OR A TRAP?
//
// ⚠️ MIRRORED PAIRS, NOT A WIN RATE AGAINST A FIXED FOE. The compositions are not
// symmetric (coven v wolfpack is a matchup, not a mirror), so "team A on keep won
// 60%" would mostly be measuring whether template A beats template B. Every fight
// is therefore run BOTH ways round — keep on A, then keep on B — and the score is
// how often the KEEPING side won, which cancels the matchup out.
//
// Judged on the SIGN TEST over fights, per the standing rule: a mean duration CI
// is worthless here because a fight that tips from timeout to a kill swings 20-30s.
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { FIELD_H, FIELD_W } from '../src/tamerengine/types'
import { DEFAULT_TACTICS } from '../src/core'
import { COMPS, teamFor, trainTier } from './comps'
import type { Monster, Tactics } from '../src/core'
//
// Usage: npx tsx tools/formation.ts [keep|tight|spread] [--elite]

const OB = [
  { x: FIELD_W * (19 / 40), y: FIELD_H * (6 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (21 / 40), y: FIELD_H * (15 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (13 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
  { x: FIELD_W * (27 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
]
const SEEDS = ['s1', 's2', 's3', 's4', 'q1', 'q2', 'q3', 'q4']
const ORDER = (process.argv[2] as Tactics['formation']) ?? 'keep'

const front = (m: Monster) => ({ front: m.stats.CON + m.stats.STR - m.stats.INT - m.stats.WIS })
const withOrder = (t: Monster[], f: Tactics['formation']) =>
  t.map((m) => ({ ...m, tactics: { ...DEFAULT_TACTICS, ...m.tactics, formation: f } }))

let win = 0, loss = 0, draw = 0
const durOrder: number[] = []
const durPlain: number[] = []

for (const c of COMPS) for (const sd of SEEDS) {
  const A = teamFor(c, 'a', sd)
  const B = teamFor(c, 'b', sd)
  const placeA = autoDeployByRole('A', A.map(front))
  const placeB = autoDeployByRole('B', B.map(front))
  // Same seed, same bodies, same deployment — ONE field differs.
  const run = (ta: Monster[], tb: Monster[]) =>
    simulateFieldBattle({ seed: sd + c.name, teamA: ta, teamB: tb, obstacles: OB, placeA, placeB })
  const aKeeps = run(withOrder(A, ORDER), B)
  const bKeeps = run(A, withOrder(B, ORDER))
  const base = run(A, B)
  durPlain.push(base.duration)
  durOrder.push(aKeeps.duration, bKeeps.duration)
  for (const [r, side] of [[aKeeps, 'A'], [bKeeps, 'B']] as const) {
    if (r.winner === 'draw') draw++
    else if (r.winner === side) win++
    else loss++
  }
}

const med = (xs: number[]) => [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)]
const n = win + loss
// Normal approximation to the sign test — n is 160, comfortably large enough.
const z = n ? (win - n / 2) / Math.sqrt(n / 4) : 0
const p = 2 * (1 - 0.5 * (1 + erf(Math.abs(z) / Math.SQRT2)))
function erf(x: number): number {
  const t = 1 / (1 + 0.3275911 * x)
  const y = 1 - ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t + 0.254829592) * t * Math.exp(-x * x)
  return y
}

console.log(`formation: '${ORDER}' — train ${trainTier()}, ${COMPS.length * SEEDS.length} pairs, both sides each\n`)
console.log(`  ordered side WON   ${win}`)
console.log(`  ordered side LOST  ${loss}`)
console.log(`  draws              ${draw}`)
console.log(`  sign test          z=${z.toFixed(2)}  p=${p.toFixed(4)}` +
  (p < 0.05 ? (win > loss ? '   ← ORDER IS A REAL EDGE' : '   ← ORDER IS A REAL PENALTY') : '   ← no measurable effect'))
console.log(`\n  median duration    ordered ${med(durOrder).toFixed(1)}s   vs plain ${med(durPlain).toFixed(1)}s`)
console.log(`  duration range     ordered ${Math.min(...durOrder).toFixed(1)}-${Math.max(...durOrder).toFixed(1)}s`
  + `   vs plain ${Math.min(...durPlain).toFixed(1)}-${Math.max(...durPlain).toFixed(1)}s`)
