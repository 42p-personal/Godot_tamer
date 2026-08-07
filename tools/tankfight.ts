// DOES A TANK ACTUALLY DIE IN A TEAM FIGHT?
//
// ⚠️ THIS REPLACES tools/breakwall.ts AS THE BAR. Breakwall asks whether one
// damage dealer beats one tank alone, and three separate attempts to move that
// number all made the game worse. It is probably the wrong question: at equal
// training a Tank carries ~1.5x the effective HP and the damage tiers give STR
// ~1.5x the DPS, so a solo matchup is near-even BY CONSTRUCTION. A tank that
// loses 1v1 to every damage class is not a tank.
//
// The question that matters is whether a tank can be BROUGHT DOWN IN CONTEXT —
// with a team focusing it, a support healing it, and the tank unable to be
// everywhere. That is the fight the game actually plays.
//
// Read it as: tanks SHOULD survive longer and cost more damage than a squishy —
// that is what they are for — but they must not be effectively unkillable, and
// the fights they are in must still end. A death rate near zero on a class
// whose fights also run long is the failure state.
//
// Usage: npx tsx tools/tankfight.ts
import { generateMonster } from '../src/monster'
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { classForStats, roleOfClass } from '../src/core'
import { SUDDEN_DEATH_AT } from '../src/tamerengine/types'

const mk = (id: string, sp: string, train = 850) => generateMonster(id, { speciesId: sp, train }) as never
const OB = [
  { x: 19, y: 6, w: 2.2, h: 2.2 }, { x: 21, y: 15, w: 2.2, h: 2.2 },
  { x: 13, y: 11, w: 2, h: 2 }, { x: 27, y: 11, w: 2, h: 2 },
]
/** The standard ten, so this shares a population with the sweep. */
const COMPS: { name: string; a: string[]; b: string[] }[] = [
  { name: 'balanced', a: ['kongrath', 'maelurk', 'larkessa'], b: ['aegisox', 'strixil', 'pinguox'] },
  { name: 'all-caster', a: ['maelurk', 'strixil', 'archmage-aleph'], b: ['abyssomancer', 'carcharun', 'frostwyren'] },
  { name: 'double-front', a: ['aegisox', 'kongrath', 'maelurk'], b: ['ursath', 'maneleo', 'strixil'] },
  { name: 'mixed-arcane', a: ['lanterix', 'bruxaroo', 'carcharun'], b: ['lurkerss', 'vespera', 'geckari'] },
  { name: 'assassins', a: ['grivvel', 'mantevoke', 'larkessa'], b: ['aegisox', 'nautilux', 'frostwyren'] },
  { name: 'support-heavy', a: ['strixil', 'koalio', 'tortavos'], b: ['quokkade', 'carcharun', 'aegisox'] },
  { name: 'marksmen', a: ['pinguox', 'mantaris', 'maelurk'], b: ['kongrath', 'aegisox', 'strixil'] },
  { name: 'generalists', a: ['corvaan', 'tazzik', 'abyssomancer'], b: ['geckari', 'odonatra', 'sylvaglide'] },
  { name: 'tank-mirror', a: ['aegisox', 'tortavos', 'ursath'], b: ['vipramane', 'nautilux', 'crocmaw'] },
  { name: 'glass', a: ['archmage-aleph', 'grivvel', 'stormlerath'], b: ['lurkerss', 'balaenix', 'stellarion'] },
]
const SEEDS = ['s1', 's2', 's3', 's4', 'q1', 'q2', 'q3', 'q4', 'z1', 'z2', 'z3', 'z4',
  'm1', 'm2', 'm3', 'm4', 'k1', 'k2', 'k3', 'k4']

interface R { n: number; died: number; tod: number[]; dmgTaken: number; maxHp: number }
const byClass = new Map<string, R>()
const byRole = new Map<string, R>()
const get = (m: Map<string, R>, k: string): R => {
  let r = m.get(k)
  if (!r) { r = { n: 0, died: 0, tod: [], dmgTaken: 0, maxHp: 0 }; m.set(k, r) }
  return r
}

let fights = 0, slow = 0
for (const comp of COMPS) for (const sd of SEEDS) {
  const A = comp.a.map((s, i) => mk(`${sd}${comp.name}a${i}`, s))
  const B = comp.b.map((s, i) => mk(`${sd}${comp.name}b${i}`, s))
  const front = (m: never) => {
    const st = (m as never as { stats: Record<string, number> }).stats
    return { front: st.CON + st.STR - st.INT - st.WIS }
  }
  const r = simulateFieldBattle({
    seed: sd + comp.name, teamA: A, teamB: B, obstacles: OB,
    placeA: autoDeployByRole('A', A.map(front)), placeB: autoDeployByRole('B', B.map(front)),
  })
  fights++
  if (r.duration >= SUDDEN_DEATH_AT) slow++

  const info = new Map<string, { cls: string }>()
  A.forEach((m, i) => info.set('A' + i, { cls: classForStats((m as never as { stats: never }).stats) }))
  B.forEach((m, i) => info.set('B' + i, { cls: classForStats((m as never as { stats: never }).stats) }))

  const start = new Map<string, number>()
  const last = new Map<string, number>()
  const died = new Map<string, number>()
  for (const e of r.events as never as
    { t: number; kind: string; id: string; units?: { id: string; hp: number; maxHp: number }[] }[]) {
    if (e.kind === 'death' && !died.has(e.id)) died.set(e.id, e.t)
    if (e.kind !== 'snapshot' || !e.units) continue
    for (const u of e.units) {
      if (!start.has(u.id)) start.set(u.id, u.hp)
      last.set(u.id, u.hp)
    }
  }
  for (const [id, v] of info) {
    for (const m of [get(byClass, v.cls), get(byRole, roleOfClass(v.cls) ?? 'other')]) {
      m.n++
      m.maxHp += start.get(id) ?? 0
      m.dmgTaken += (start.get(id) ?? 0) - (died.has(id) ? 0 : (last.get(id) ?? 0))
      if (died.has(id)) { m.died++; m.tod.push(died.get(id)!) }
    }
  }
}

const mean = (a: number[]) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : NaN)
const show = (label: string, m: Map<string, R>) => {
  console.log('\n' + label)
  console.log('  name             n    DIED    death%   avg time of death   HP pool   dmg to kill')
  for (const [k, r] of [...m].sort((a, b) => a[1].died / a[1].n - b[1].died / b[1].n)) {
    if (r.n < 8) continue
    console.log('  ' + k.padEnd(15) + String(r.n).padStart(5) + String(r.died).padStart(8)
      + (r.died / r.n * 100).toFixed(0).padStart(9) + '%'
      + (r.tod.length ? mean(r.tod).toFixed(1) + 's' : '—').padStart(18)
      + (r.maxHp / r.n).toFixed(0).padStart(10)
      + (r.dmgTaken / r.n).toFixed(0).padStart(14))
  }
}

console.log(`TANKS IN CONTEXT — ${fights} team fights (${slow} needed sudden death)`)
show('BY CLASS', byClass)
show('BY ROLE', byRole)
const t = byClass.get('Tank')
if (t) {
  const others = [...byClass].filter(([k]) => k !== 'Tank')
  const oDeath = others.reduce((n, [, r]) => n + r.died, 0) / others.reduce((n, [, r]) => n + r.n, 0)
  console.log(`\nTank death rate ${(t.died / t.n * 100).toFixed(0)}% vs everyone else `
    + `${(oDeath * 100).toFixed(0)}%  =>  a tank is ${(oDeath / (t.died / t.n)).toFixed(2)}x harder to kill.`)
  console.log('A tank SHOULD be harder to kill. The failure state is a death rate near zero')
  console.log('while its fights also run long — that is unkillable, not durable.')
}
