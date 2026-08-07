// WHERE DOES THE FIGHT TIME ACTUALLY GO?
//
// ⚠️ WHY THIS EXISTS. Four separate levers aimed at "fights run too long" all
// measured NULL on a 200-pair paired A/B: the mitigation cap (byte-identical
// output), the maxHp coefficient (p=0.27), melee focus-fire targeting (p=0.39
// duration / p=0.23 resolved), and halving ALL healing (-0.16s, +1 fight). Four
// nulls in a row is not four unlucky guesses, it is a wrong model of the problem
// — so this stops guessing at causes and measures the budget directly.
//
// The snapshot stream already carries a per-unit visual state every tick, which
// is an action-economy budget sitting in plain sight: what fraction of its living
// seconds does a monster spend CASTING (the only state that advances the fight)
// versus MOVING, BLOCKING or IDLE?
//
// Read it by comparing the fights that end on their own against the ones that
// need sudden death to force them. Whatever differs is the real lever.
//
// Usage: npx tsx tools/timebudget.ts
import { generateMonster } from '../src/monster'
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { SUDDEN_DEATH_AT } from '../src/tamerengine/types'

const mk = (id: string, sp: string, train = 850) => generateMonster(id, { speciesId: sp, train }) as never
const OBSTACLES = [
  { x: 19, y: 6, w: 2.2, h: 2.2 }, { x: 21, y: 15, w: 2.2, h: 2.2 },
  { x: 13, y: 11, w: 2, h: 2 }, { x: 27, y: 11, w: 2, h: 2 },
]
const COMPS: { name: string; a: string[]; b: string[] }[] = [
  { name: 'balanced',      a: ['kongrath', 'maelurk', 'larkessa'],          b: ['aegisox', 'strixil', 'pinguox'] },
  { name: 'all-caster',    a: ['maelurk', 'strixil', 'archmage-aleph'],     b: ['abyssomancer', 'carcharun', 'frostwyren'] },
  { name: 'double-front',  a: ['aegisox', 'kongrath', 'maelurk'],           b: ['ursath', 'maneleo', 'strixil'] },
  { name: 'mixed-arcane',  a: ['lanterix', 'bruxaroo', 'carcharun'],        b: ['lurkerss', 'vespera', 'geckari'] },
  { name: 'assassins',     a: ['grivvel', 'mantevoke', 'larkessa'],         b: ['aegisox', 'nautilux', 'frostwyren'] },
  { name: 'support-heavy', a: ['strixil', 'koalio', 'tortavos'],            b: ['quokkade', 'carcharun', 'aegisox'] },
  { name: 'marksmen',      a: ['pinguox', 'mantaris', 'maelurk'],           b: ['kongrath', 'aegisox', 'strixil'] },
  { name: 'generalists',   a: ['corvaan', 'tazzik', 'abyssomancer'],        b: ['geckari', 'odonatra', 'sylvaglide'] },
  { name: 'tank-mirror',   a: ['aegisox', 'tortavos', 'ursath'],            b: ['vipramane', 'nautilux', 'crocmaw'] },
  { name: 'glass',         a: ['archmage-aleph', 'grivvel', 'stormlerath'], b: ['lurkerss', 'balaenix', 'stellarion'] },
]
const SEEDS = ['s1', 's2', 's3', 's4', 'q1', 'q2', 'q3', 'q4', 'z1', 'z2', 'z3', 'z4',
  'm1', 'm2', 'm3', 'm4', 'k1', 'k2', 'k3', 'k4']

interface Row { comp: string; slow: boolean; dur: number
  cast: number; move: number; block: number; idle: number; hurt: number; casts: number }

const rows: Row[] = []
for (const comp of COMPS) for (const sd of SEEDS) {
  const A = comp.a.map((s, i) => mk(`${sd}${comp.name}a${i}`, s))
  const B = comp.b.map((s, i) => mk(`${sd}${comp.name}b${i}`, s))
  const front = (m: never) => { const st = (m as never as { stats: Record<string, number> }).stats
    return { front: st.CON + st.STR - st.INT - st.WIS } }
  const r = simulateFieldBattle({ seed: sd + comp.name, teamA: A, teamB: B, obstacles: OBSTACLES,
    placeA: autoDeployByRole('A', A.map(front)), placeB: autoDeployByRole('B', B.map(front)) })

  // Count LIVING unit-ticks only. Counting dead ones would make every long fight
  // look idle purely because corpses lie still, which is the opposite of signal.
  const tally: Record<string, number> = { idle: 0, move: 0, cast: 0, hurt: 0, block: 0 }
  let casts = 0
  for (const e of r.events as never as
    { kind: string; units?: { state: string }[] }[]) {
    if (e.kind === 'cast') casts++
    if (e.kind !== 'snapshot' || !e.units) continue
    for (const u of e.units) if (u.state !== 'dead') tally[u.state] = (tally[u.state] ?? 0) + 1
  }
  const total = Object.values(tally).reduce((a, b) => a + b, 0) || 1
  rows.push({ comp: comp.name, slow: r.duration >= SUDDEN_DEATH_AT, dur: r.duration,
    cast: tally.cast / total, move: tally.move / total, block: tally.block / total,
    idle: tally.idle / total, hurt: tally.hurt / total, casts })
}

const mean = (a: number[]) => a.reduce((x, y) => x + y, 0) / Math.max(1, a.length)
const pct = (n: number) => (n * 100).toFixed(1) + '%'
const show = (label: string, rs: Row[]) => {
  if (!rs.length) return console.log(label.padEnd(22) + '  (none)')
  console.log(
    label.padEnd(22)
    + String(rs.length).padStart(4)
    + pct(mean(rs.map((r) => r.cast))).padStart(9)
    + pct(mean(rs.map((r) => r.move))).padStart(9)
    + pct(mean(rs.map((r) => r.block))).padStart(9)
    + pct(mean(rs.map((r) => r.idle))).padStart(9)
    + mean(rs.map((r) => r.casts)).toFixed(0).padStart(8)
    + (mean(rs.map((r) => r.casts / r.dur))).toFixed(2).padStart(9))
}

console.log(`ACTION-ECONOMY BUDGET — ${rows.length} fights, share of LIVING unit-time\n`)
console.log('                         n     cast     move    block     idle   casts  casts/s')
show('fights that END', rows.filter((r) => !r.slow))
show('fights needing SUDDEN DEATH', rows.filter((r) => r.slow))
console.log('')
const byComp = new Map<string, Row[]>()
for (const r of rows) byComp.set(r.comp, [...(byComp.get(r.comp) ?? []), r])
for (const [c, rs] of [...byComp].sort((a, b) => mean(a[1].map((r) => r.cast)) - mean(b[1].map((r) => r.cast))))
  show(c, rs)

const slow = rows.filter((r) => r.slow), fast = rows.filter((r) => !r.slow)
console.log(`\n${slow.length}/${rows.length} fights needed sudden death.`)
console.log(`CAST share  slow ${pct(mean(slow.map((r) => r.cast)))} vs fast ${pct(mean(fast.map((r) => r.cast)))}`)
console.log(`IDLE share  slow ${pct(mean(slow.map((r) => r.idle)))} vs fast ${pct(mean(fast.map((r) => r.idle)))}`)
console.log(`MOVE share  slow ${pct(mean(slow.map((r) => r.move)))} vs fast ${pct(mean(fast.map((r) => r.move)))}`)
console.log('\nIf slow fights show the SAME cast share as fast ones, the monsters are acting')
console.log('fine and the fight is long because each action does too little — a DAMAGE')
console.log('problem. If slow fights idle or move more, the lever is the action economy.')
