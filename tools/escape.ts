// ESCAPE SUCCESS — does cover help a hunted monster, and does it help TOO much?
//
// ⚠️ THE TWO-SIDED TEST. The Stage 3 design says a fleeing support should buy a
// few seconds and then die anyway. So this reports both halves:
//   · survivedFor UP with cover      -> cover helps            (wanted)
//   · survivalRate near 1.0 with cover -> cover makes prey unkillable (the failure)
// Neither number means anything alone.
//
// Runs each arena WITH its cover and again with NONE, same teams, same seeds, so
// the ground is the only variable.
//
// Usage: npx tsx tools/escape.ts
import { generateMonster } from '../src/monster'
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { setFieldSize, FieldEvent, Obstacle } from '../src/tamerengine/types'
import { MAPS } from '../src/tamerengine/maps'
import { hunts, summarise } from '../src/tamerengine/escape'

const mk = (id: string, sp: string) => generateMonster(id, { speciesId: sp, train: 850 }) as never
const COMPS = [
  { n: 'balanced', a: ['kongrath', 'maelurk', 'larkessa'], b: ['aegisox', 'strixil', 'pinguox'] },
  { n: 'double-front', a: ['aegisox', 'kongrath', 'maelurk'], b: ['ursath', 'maneleo', 'strixil'] },
  { n: 'marksmen', a: ['pinguox', 'mantaris', 'maelurk'], b: ['kongrath', 'aegisox', 'strixil'] },
  { n: 'assassins', a: ['grivvel', 'mantevoke', 'larkessa'], b: ['aegisox', 'nautilux', 'frostwyren'] },
  { n: 'support-heavy', a: ['strixil', 'koalio', 'tortavos'], b: ['quokkade', 'carcharun', 'aegisox'] },
  { n: 'glass', a: ['archmage-aleph', 'grivvel', 'stormlerath'], b: ['lurkerss', 'balaenix', 'stellarion'] },
]
const SEEDS = ['s1', 's2', 's3', 's4']

function run(arena: { w: number; h: number }, obs: Obstacle[]) {
  setFieldSize(arena.w, arena.h)
  const all = []
  for (const c of COMPS) for (const sd of SEEDS) {
    const A = c.a.map((s, i) => mk(`${sd}${c.n}a${i}`, s))
    const B = c.b.map((s, i) => mk(`${sd}${c.n}b${i}`, s))
    const front = (m: never) => {
      const st = (m as never as { stats: Record<string, number> }).stats
      return { front: st.CON + st.STR - st.INT - st.WIS }
    }
    const r = simulateFieldBattle({
      seed: sd + c.n, teamA: A, teamB: B, obstacles: obs,
      placeA: autoDeployByRole('A', A.map(front)), placeB: autoDeployByRole('B', B.map(front)),
    })
    all.push(...hunts(r.events as FieldEvent[], (id) => id[0]))
  }
  return summarise(all)
}

console.log('arena              cover   hunts  survival  survivedFor  huntedFor  escapes/hunt')
console.log('-'.repeat(84))
for (const arena of MAPS) {
  for (const [label, obs] of [['yes', arena.obstacles], ['NONE', [] as Obstacle[]]] as const) {
    const s = run(arena, obs as Obstacle[])
    console.log(
      `${arena.name.padEnd(15)} ${label.padEnd(8)} ${String(s.hunts).padStart(5)}`
      + `  ${(s.survivalRate * 100).toFixed(0).padStart(7)}%`
      + `  ${s.meanSurvivedFor.toFixed(1).padStart(11)}s`
      + `  ${s.meanHuntedFor.toFixed(1).padStart(9)}s`
      + `  ${s.escapesPerHunt.toFixed(2).padStart(12)}`,
    )
  }
}
console.log(
  '\n  survivedFor  seconds from FIRST BEING HUNTED to death — not from first damage.'
  + '\n               ⚠️ The pursuit phase before the first blow is exactly what cover'
  + '\n               lengthens, so measuring from first damage hides the effect.'
  + '\n  survival     share of hunted units that lived. ⚠️ THE UNBOUNDED CHECK — near'
  + '\n               100% with cover means prey cannot be caught, which is the'
  + '\n               failure the escape cooldown exists to prevent.',
)
