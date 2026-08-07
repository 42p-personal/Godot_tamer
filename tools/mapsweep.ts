// Run the standard 40-matchup sweep on EVERY arena and print them side by side.
//
// The teams, seeds and compositions are identical across arenas — the ground is
// the only variable — so the columns are directly comparable. That is the whole
// point of having named maps rather than ad-hoc obstacle arrays: a result is
// attributable to a map you can name and re-run.
//
// ⚠️ setFieldSize BEFORE autoDeployByRole, once per arena. The deployment bands
// are computed from the field, so seating a team against the previous arena's
// size starts the fight in the wrong half.
//
// Usage: npx tsx tools/mapsweep.ts
import { generateMonster } from '../src/monster'
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { setFieldSize, SUDDEN_DEATH_AT } from '../src/tamerengine/types'
import { MAPS, mapProblems } from '../src/tamerengine/maps'

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

console.log(
  'arena'.padEnd(14) + 'size'.padEnd(10) + 'cover'.padEnd(8)
  + 'resolved'.padEnd(11) + 'dur'.padEnd(9) + 'contact'.padEnd(10) + 'travel/unit',
)
console.log('-'.repeat(72))

for (const arena of MAPS) {
  const bad = mapProblems(arena)
  if (bad.length) { console.error(bad.join('\n')); process.exit(1) }
  setFieldSize(arena.w, arena.h)

  let resolved = 0, dur = 0, contact = 0, travel = 0, n = 0
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
    const evs = r.events as never as
      { kind: string; t: number; units?: { id: string; x: number; y: number }[] }[]
    const first = evs.find((e) => e.kind === 'hit')
    let tr = 0, units = 0
    let prev: Map<string, { x: number; y: number }> | null = null
    for (const e of evs) {
      if (e.kind === 'snapshot' && e.units) {
        units = Math.max(units, e.units.length)
        if (prev) for (const u of e.units) {
          const p = prev.get(u.id)
          if (p) tr += Math.hypot(u.x - p.x, u.y - p.y)
        }
        prev = new Map(e.units.map((u) => [u.id, { x: u.x, y: u.y }]))
      }
    }
    resolved += r.duration < SUDDEN_DEATH_AT ? 1 : 0
    dur += r.duration
    contact += first?.t ?? 0
    travel += tr / Math.max(1, units)
    n++
  }
  const area = arena.w * arena.h
  const coverPct = arena.obstacles.reduce((s, o) => s + o.w * o.h, 0) / area * 100
  console.log(
    arena.name.padEnd(14)
    + `${arena.w}x${arena.h}`.padEnd(10)
    + `${coverPct.toFixed(1)}%`.padEnd(8)
    + `${resolved}/${n}`.padEnd(11)
    + `${(dur / n).toFixed(1)}s`.padEnd(9)
    + `${(contact / n).toFixed(1)}s`.padEnd(10)
    + `${(travel / n).toFixed(1)}`,
  )
}
