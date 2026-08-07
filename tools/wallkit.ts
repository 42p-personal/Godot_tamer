// DOES A DAMAGE MONSTER EVER DRAFT A WALL-BREAKER?
//
// Wiring the anti-tank effects into the engine moved the 1v1 win rate against
// tanks from 32% to 33% — i.e. almost nothing. An effect that works but is never
// in anyone's hand is indistinguishable from one that does not work, which is
// the SAME failure the ability lines were built to fix: authored content that no
// kit can reach.
//
// This measures reach directly: across many generated monsters, how many end up
// holding ANY tool that answers a high-CON target?
//
// Usage: npx tsx tools/wallkit.ts
import { generateMonster } from '../src/monster'
import { ALL_MOVES } from '../src/moves'
import { classForStats } from '../src/core'

const mk = (id: string, sp: string, train = 850) => generateMonster(id, { speciesId: sp, train }) as never

/** The four things that actually answer a wall of CON. */
const isWallBreaker = (mv: { effects?: Record<string, unknown> }) =>
  !!(mv.effects?.pierce || mv.effects?.execute || mv.effects?.maxHpDmg || mv.effects?.defDebuff)

const pool = ALL_MOVES as never as { name: string; stat: string; line?: string; effects?: Record<string, unknown> }[]
const breakers = pool.filter(isWallBreaker)
console.log(`THE WALL-BREAKERS IN THE POOL: ${breakers.length} of ${pool.length} moves (`
  + (breakers.length / pool.length * 100).toFixed(1) + '%)\n')
const byStat: Record<string, string[]> = {}
for (const m of breakers) (byStat[m.stat] ??= []).push(m.name)
for (const s of ['STR', 'DEX', 'CON', 'WIS', 'INT', 'CHA'])
  console.log('  ' + s.padEnd(5) + (byStat[s]?.length ?? 0) + '  ' + (byStat[s]?.join(', ') ?? '—'))

const SPECIES = ['kongrath', 'maneleo', 'grivvel', 'pinguox', 'archmage-aleph', 'maelurk',
  'ursath', 'mantevoke', 'carcharun', 'stormlerath', 'corvaan', 'tazzik', 'geckari', 'vespera',
  'lurkerss', 'balaenix', 'stellarion', 'frostwyren', 'abyssomancer', 'mantaris']

const stat = new Map<string, { held: number; n: number }>()
let held = 0, total = 0
for (const sp of SPECIES) for (let i = 0; i < 25; i++) {
  const m = mk(`${sp}-${i}`, sp) as never as
    { stats: never; loadout: { effects?: Record<string, unknown> }[] }
  const cls = classForStats(m.stats)
  const has = m.loadout.some(isWallBreaker)
  total++; if (has) held++
  const s = stat.get(cls) ?? { held: 0, n: 0 }
  s.n++; if (has) s.held++
  stat.set(cls, s)
}

console.log(`\nOF ${total} GENERATED MONSTERS, ${held} (${(held / total * 100).toFixed(0)}%) hold a wall-breaker.\n`)
console.log('class            holds one     of')
for (const [c, s] of [...stat].sort((a, b) => b[1].held / b[1].n - a[1].held / a[1].n))
  console.log('  ' + c.padEnd(15) + (s.held / s.n * 100).toFixed(0).padStart(6) + '%'
    + String(s.n).padStart(8))
console.log('\nA damage class that never draws an answer to CON cannot beat a tank however')
console.log('well the effect is implemented. Coverage in the POOL is the lever, not the engine.')
