// NAVIGATION DIAGNOSTIC — per-arena pathfinding health.
//
// ⚠️ THE INSTRUMENT sweep40 SHOULD HAVE BEEN. sweep40 reported Titan's Rest at a
// perfectly ordinary 38/40 while two units were welded in place for 750 ticks.
// Outcome metrics cannot see an inert unit; this can.
//
// Runs the standard 40 matchups on every arena — teams and seeds held constant,
// the ground the only variable — and reports what units DID rather than how the
// fight ended. Exit code 1 if any unit deadlocks, so it can gate later.
//
// Usage: npx tsx tools/navdiag.ts [--units]     (--units lists worst offenders)
import { generateMonster } from '../src/monster'
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { setFieldSize, SUDDEN_DEATH_AT, FieldEvent } from '../src/tamerengine/types'
import { MAPS, mapProblems } from '../src/tamerengine/maps'
import { navStats, navSummary, NavStats } from '../src/tamerengine/navmetrics'

const SHOW_UNITS = process.argv.includes('--units')
const mk = (id: string, sp: string) => generateMonster(id, { speciesId: sp, train: 850 }) as never

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
const SEEDS = ['s1', 's2', 's3', 's4']

console.log('arena'.padEnd(14) + 'size'.padEnd(9) + 'resolved'.padEnd(11)
  + 'DEADLOCKED'.padEnd(13) + 'stuck%'.padEnd(9) + 'of which cover'.padEnd(16) + 'wander')
console.log('-'.repeat(78))

let anyDeadlock = 0
const worst: { arena: string; comp: string; s: NavStats }[] = []

for (const arena of MAPS) {
  const bad = mapProblems(arena)
  if (bad.length) { console.error(bad.join('\n')); process.exit(1) }
  setFieldSize(arena.w, arena.h)

  const all: NavStats[] = []
  let resolved = 0, n = 0
  for (const comp of COMPS) for (const sd of SEEDS) {
    const A = comp.a.map((s, i) => mk(`${sd}${comp.name}a${i}`, s))
    const B = comp.b.map((s, i) => mk(`${sd}${comp.name}b${i}`, s))
    const front = (m: never) => {
      const st = (m as never as { stats: Record<string, number> }).stats
      return { front: st.CON + st.STR - st.INT - st.WIS }
    }
    const r = simulateFieldBattle({
      seed: sd + comp.name, teamA: A, teamB: B, obstacles: arena.obstacles,
      placeA: autoDeployByRole('A', A.map(front)), placeB: autoDeployByRole('B', B.map(front)),
    })
    const stats = navStats(r.events as FieldEvent[], arena.obstacles)
    all.push(...stats)
    for (const s of stats) if (s.deadlocked) worst.push({ arena: arena.name, comp: comp.name + '/' + sd, s })
    resolved += r.duration < SUDDEN_DEATH_AT ? 1 : 0
    n++
  }

  const sum = navSummary(all)
  anyDeadlock += sum.deadlocked
  console.log(
    arena.name.padEnd(14)
    + `${arena.w}x${arena.h}`.padEnd(9)
    + `${resolved}/${n}`.padEnd(11)
    + `${sum.deadlocked}/${sum.units}`.padEnd(13)
    + `${sum.stuckPct.toFixed(1)}%`.padEnd(9)
    + `${sum.blockedPct.toFixed(0)}%`.padEnd(16)
    + sum.wander.toFixed(2),
  )
}

if (SHOW_UNITS && worst.length) {
  console.log(`\nDEADLOCKED UNITS (stuck ≥90% of the ticks they tried to move):`)
  const seen = new Map<string, number>()
  for (const w of worst) seen.set(`${w.arena}  ${w.s.id}`, (seen.get(`${w.arena}  ${w.s.id}`) ?? 0) + 1)
  for (const [k, count] of [...seen].sort((a, b) => b[1] - a[1]).slice(0, 15)) {
    console.log(`  ${k.padEnd(26)} in ${count} of ${COMPS.length * SEEDS.length} fights`)
  }
}

console.log(
  `\n  stuck%  = share of MOVE ticks where the unit did not move.`
  + `\n            ⚠️ Keyed off the engine's own 'move' state, so casting and`
  + `\n            holding range do not count — the flaw that made a raw`
  + `\n            "frozen%" read 40-86% for perfectly healthy units.`
  + `\n  cover   = share of those stuck ticks spent touching an obstacle, i.e.`
  + `\n            how much of the problem is geometry rather than something else.`
  + `\n  wander  = path / net displacement. 1.00 is a straight line.`,
)

if (anyDeadlock > 0) {
  console.log(`\n⚠️ ${anyDeadlock} DEADLOCKED unit-fights. Stage 0 target is zero.`)
  process.exit(1)
}
