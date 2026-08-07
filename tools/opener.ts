// DOES THE SCRIPTED OPENER ACTUALLY OPEN?
//
// ⚠️ `openerIds` sat on `Tactics` with TEN UI references and was read by NOTHING in
// the field engine — a player built an opening sequence and the monster ignored it.
// Reference-counting called the tactic live (battle.ts reads it); only asking "what
// did it actually cast" catches a control that does nothing in the engine shipping.
//
// Measures the ORDER'S CONSEQUENCE: order every unit on both sides to open with its
// HIGHEST-LEVEL learned move — the least likely opener the unscripted picker would
// choose on its own, being the most expensive and longest-cooldown thing in the kit
// — and compare against the same fights with no order set.
//
// ⚠️ "OPENED WITH" IS NOT "CAST FIRST", AND MEASURING IT THAT WAY HID A WORKING
// MECHANISM. A field battle has an APPROACH: at t=0 every enemy is ~30 units away
// and the only castable thing is a team buff, so `Rallying Song` was 482 of 575
// literal-first casts no matter what the order said. An opening on a field is the
// first thing cast ONCE ENGAGED — so this scores position in the cast ORDER, within
// the same window the engine holds the order for (OPENER_WINDOW).
//
// Usage: npx tsx tools/opener.ts
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { FIELD_H, FIELD_W } from '../src/tamerengine/types'
import { COMPS, teamFor, trainTier } from './comps'
import { OPENER_WINDOW } from '../src/tamerengine/types'
import type { Monster } from '../src/core'

const OB = [
  { x: FIELD_W * (19 / 40), y: FIELD_H * (6 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (21 / 40), y: FIELD_H * (15 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (13 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
  { x: FIELD_W * (27 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
]
const SEEDS = ['s1', 's2', 's3', 's4', 'q1', 'q2', 'q3', 'q4']
const front = (m: Monster) => ({ front: m.stats.CON + m.stats.STR - m.stats.INT - m.stats.WIS })

/** The capstone of a kit — highest learnLevel, ties broken by power. */
const capstone = (m: Monster) =>
  [...m.loadout].sort((a, b) => b.learnLevel - a.learnLevel || b.power - a.power)[0]

const script = (t: Monster[]) => t.map((m) => {
  const c = capstone(m)
  return c ? { ...m, tactics: { ...m.tactics, openerIds: [c.id] } } : m
})

type Ev = { t: number; kind: string; id?: string; move?: string }
/**
 * Per unit: where the ordered move landed in its sequence of casts, counting only
 * casts inside OPENER_WINDOW. 1 = it opened with it. 0 = never cast it in the window.
 */
function ranks(events: Ev[], A: Monster[], B: Monster[]) {
  const seq = new Map<string, string[]>()
  for (const e of events) {
    if (e.kind !== 'cast' || !e.id || e.t > OPENER_WINDOW) continue
    const a = seq.get(e.id) ?? []
    a.push(e.move ?? '?')
    seq.set(e.id, a)
  }
  const out: number[] = []
  for (const [id, casts] of seq) {
    const m = (id[0] === 'A' ? A : B)[Number(id.slice(1))]
    const c = m && capstone(m)
    if (!c) continue
    out.push(casts.indexOf(c.name) + 1)
  }
  return out
}

const sR: number[] = [], pR: number[] = []
for (const c of COMPS) for (const sd of SEEDS) {
  const A = teamFor(c, 'a', sd), B = teamFor(c, 'b', sd)
  const placeA = autoDeployByRole('A', A.map(front)), placeB = autoDeployByRole('B', B.map(front))
  const run = (ta: Monster[], tb: Monster[]) =>
    simulateFieldBattle({ seed: sd + c.name, teamA: ta, teamB: tb, obstacles: OB, placeA, placeB })
  sR.push(...ranks(run(script(A), script(B)).events as never, A, B))
  pR.push(...ranks(run(A, B).events as never, A, B))
}

const pct = (a: number, b: number) => b ? ((a / b) * 100).toFixed(1) + '%' : '—'
const med = (xs: number[]) => xs.length ? [...xs].sort((a, b) => a - b)[Math.floor(xs.length / 2)] : NaN
const row = (label: string, r: number[]) => {
  const cast = r.filter((x) => x > 0)
  console.log(`  ${label.padEnd(12)} cast it ${pct(cast.length, r.length).padStart(6)}`
    + ` of the time  ·  when cast, action #${med(cast).toFixed(0)}`
    + `  ·  opened with it ${pct(r.filter((x) => x === 1).length, r.length).padStart(6)}`)
}
console.log(`openerIds — train ${trainTier()}, ${COMPS.length * SEEDS.length} fights,`
  + ` ${sR.length} engaged units, window ${OPENER_WINDOW}s
`)
row('ORDERED', sR)
row('no order', pR)
console.log(`
⚠️ Two rows that match mean the ORDER IS DECORATIVE. Neither column can`
  + `
   reach 100%: a unit that dies during the approach, is stunned through the`
  + `
   window, or never closes to its capstone's reach never gets to open at all.`)
