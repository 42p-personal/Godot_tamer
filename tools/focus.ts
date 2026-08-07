// HOW CONCENTRATED IS DAMAGE? The instrument for focus fire (P6).
//
// ⚠️ THE PROBLEM NO TOTAL CAN SEE. Damage spreads evenly across a whole enemy
// side, so nobody crosses the death threshold until very late — a fight can deal
// the MOST damage in the sweep and still kill nobody. Total damage, kills and
// even duration all read that as "fine, just slow". The quantity that actually
// matters is how much of a side's output landed on ONE body.
//
// TOP SHARE, measured up to the FIRST DEATH on the receiving side. Everything
// after that is polluted by forced retargeting — when a target dies the whole
// team must pick someone new, which looks like a focus change but is not a
// decision. Perfect focus in a 3v3 is 1.00; damage split evenly across three
// bodies is 0.33.
//
// ⚠️ ALSO REPORTS `spread`: the mean number of DISTINCT enemies a side damaged
// per 5-second window. Top share alone can be flattered by a unit that happens
// to die early; two numbers disagreeing is a signal, not noise.
//
// Usage: npx tsx tools/focus.ts
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { FIELD_H, FIELD_W } from '../src/tamerengine/types'
import { COMPS, TEAM_SIZE, teamFor } from './comps'

const OBSTACLES = [
  { x: FIELD_W * (19 / 40), y: FIELD_H * (6 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (21 / 40), y: FIELD_H * (15 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (13 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
  { x: FIELD_W * (27 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
]
const mean = (a: number[]) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : 0)
const SEEDS = ['s1', 's2', 's3', 's4']
const WINDOW = 5

// ⚠️ `heal` and `ehp` were added after the first run refuted the premise. Top
// share came out at 0.711 against 0.333 for an even split — damage is ALREADY
// concentrated — yet Phalanx mirror focused at 0.66 and still took 19.7s to a
// first kill while Coven mirror focused at 0.87 and killed in 5.0s. Focus is not
// what separates them, so the table has to carry the candidates that might be:
// how much healing undoes the damage, and how much health there is to chew.
interface Acc { topShare: number[]; spread: number[]; firstKill: number[]
  heal: number[]; dmg: number[]; ehp: number[] }
const rows = new Map<string, Acc>()

for (const comp of COMPS) for (const sd of SEEDS) {
  const A = teamFor(comp, 'a', sd) as never[]
  const B = teamFor(comp, 'b', sd) as never[]
  const front = (m: never) => {
    const st = (m as never as { stats: Record<string, number> }).stats
    return { front: st.CON + st.STR - st.INT - st.WIS }
  }
  const r = simulateFieldBattle({
    seed: sd + comp.name, teamA: A, teamB: B, obstacles: OBSTACLES,
    placeA: autoDeployByRole('A', A.map(front)), placeB: autoDeployByRole('B', B.map(front)),
  })
  const ev = r.events as never as { kind: string; t: number; id: string; targetId: string; dmg: number; amount: number }[]

  // First death per side — the cut-off for the top-share window.
  const firstDeath: Record<string, number> = { A: Infinity, B: Infinity }
  for (const e of ev) {
    if (e.kind !== 'death') continue
    const s = e.id[0]
    if (e.t < firstDeath[s]) firstDeath[s] = e.t
  }

  for (const side of ['A', 'B'] as const) {
    const foe = side === 'A' ? 'B' : 'A'
    const cut = firstDeath[foe]
    const onEnemy = new Map<string, number>()
    const windows = new Map<number, Set<string>>()
    for (const e of ev) {
      if (e.kind !== 'hit' || !e.targetId) continue
      if (e.id[0] !== side || e.targetId[0] !== foe) continue // own side's damage onto theirs
      if (e.t <= cut) onEnemy.set(e.targetId, (onEnemy.get(e.targetId) ?? 0) + e.dmg)
      const w = Math.floor(e.t / WINDOW)
      if (!windows.has(w)) windows.set(w, new Set())
      windows.get(w)!.add(e.targetId)
    }
    const tot = [...onEnemy.values()].reduce((a, b) => a + b, 0)
    if (tot <= 0) continue
    // Healing RECEIVED by the side being attacked, over the same window.
    let healed = 0
    for (const e of ev) {
      if (e.kind !== 'heal' || e.t > cut) continue
      if ((e.targetId ?? e.id)[0] === foe) healed += e.amount // ⚠️ `amount`, not `dmg`
    }
    const acc = rows.get(comp.name)
      ?? { topShare: [], spread: [], firstKill: [], heal: [], dmg: [], ehp: [] }
    acc.heal.push(healed)
    acc.dmg.push(tot)
    acc.ehp.push(mean((foe === 'A' ? A : B).map((m) =>
      (m as never as { stats: Record<string, number> }).stats.CON * 2 + 40)))
    acc.topShare.push(Math.max(...onEnemy.values()) / tot)
    acc.spread.push([...windows.values()].reduce((a, s) => a + s.size, 0) / Math.max(1, windows.size))
    if (Number.isFinite(cut)) acc.firstKill.push(cut)
    rows.set(comp.name, acc)
  }
}

// ⚠️ The even-split baseline is PER COMPOSITION, because the sweep spans 2v2 to
// 6v6 — a single 1/TEAM_SIZE would quietly compare a 2v2's concentration against
// a 6v6's yardstick. The overall figure uses the mean size and says so.
const EVEN = 1 / TEAM_SIZE

console.log('FOCUS FIRE — damage concentration across the sweep (2v2-6v6)')
console.log(`perfect focus = 1.00 · even spread across ${TEAM_SIZE} = ${EVEN.toFixed(2)}\n`)
console.log('composition             top share   targets/5s   1st kill   healed/dealt   maxHp')
const all: number[] = []
const allSpread: number[] = []
for (const [n, a] of rows) {
  all.push(...a.topShare)
  allSpread.push(...a.spread)
  console.log(`  ${n.padEnd(24)}${mean(a.topShare).toFixed(2).padStart(6)}`
    + `${mean(a.spread).toFixed(2).padStart(13)}`
    + `${(a.firstKill.length ? mean(a.firstKill).toFixed(1) + 's' : 'none').padStart(11)}`
    + `${(100 * mean(a.heal) / Math.max(1, mean(a.dmg))).toFixed(0) + '%'}`.padStart(15)
    + `${mean(a.ehp).toFixed(0)}`.padStart(8))
}
console.log(`\nOVERALL top share ${mean(all).toFixed(3)} `
  + `(even would be ${EVEN.toFixed(3)}) · targets/5s ${mean(allSpread).toFixed(2)}`)
