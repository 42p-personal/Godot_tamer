// HITS-TO-KILL AT ANY POINT ON THE LADDER — the pacing number behind "duration".
//
// ⚠️ Wood is the outlier of the whole progression and TWO plausible explanations
// have already been measured and refuted: the flat +40 in `maxHp` (cutting it 75%
// buys 5.4s of a 19s gap) and the free attack's base power. `tools/leagues.ts`'s own
// header asserted the first one for weeks. This dumps the fight instead of theorising
// about it — kit size, what is affordable, and where the damage actually comes from.
//
// Usage: npx tsx tools/pacing.ts [cap] [train] [size]
import { generateMonster, maxHp, maxMana, manaCost } from '../src/monster'
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { FIELD_MANA_COST_MULT } from '../src/tamerengine/types'
import { COMPS, compAtSize, teamFor } from './comps'
import type { Monster } from '../src/core'

const cap = Number(process.argv[2] ?? 100)
const train = Number(process.argv[3] ?? 86)
const size = Number(process.argv[4] ?? 1)

const byMove: Record<string, { casts: number; dmg: number; hits: number }> = {}
let dur = 0, fights = 0, kitTotal = 0, afford = 0, units = 0

for (const c0 of COMPS) for (const sd of ['s1', 's2', 's3', 's4']) {
  const c = compAtSize(c0, size)
  const A = teamFor(c, 'a', sd, { train, statCap: cap }) as Monster[]
  const B = teamFor(c, 'b', sd, { train, statCap: cap }) as Monster[]
  for (const m of [...A, ...B]) {
    units++; kitTotal += m.loadout.length
    afford += m.loadout.filter((mv) => maxMana(m.stats) >= manaCost(mv) * FIELD_MANA_COST_MULT).length
  }
  const r = simulateFieldBattle({ seed: sd + c.name, teamA: A, teamB: B })
  dur += r.duration; fights++
  for (const e of r.events as { kind: string; move?: string; dmg?: number }[]) {
    if (e.kind !== 'hit' && e.kind !== 'cast') continue
    const k = e.move ?? '?'
    byMove[k] ??= { casts: 0, dmg: 0, hits: 0 }
    if (e.kind === 'cast') byMove[k].casts++
    else { byMove[k].dmg += e.dmg ?? 0; byMove[k].hits++ }
  }
}

const sample = generateMonster('probe', { train, statCap: cap })
const totalDmg = Object.values(byMove).reduce((a, x) => a + x.dmg, 0)
const rows = Object.entries(byMove).sort((a, b) => b[1].dmg - a[1].dmg)
const basic = rows.filter(([k]) => /attack|strike|swing|bolt|jab/i.test(k))

console.log(`cap ${cap} · train ${train} · ${size}v${size} · ${fights} fights, ${(dur / fights).toFixed(1)}s mean\n`)
console.log(`sample monster: maxHp ${maxHp(sample.stats)}, maxMana ${maxMana(sample.stats)}, `
  + `stats ${Object.entries(sample.stats).map(([k, v]) => k + ' ' + v).join(' ')}`)
console.log(`kits: ${(kitTotal / units).toFixed(2)} moves equipped, `
  + `${(afford / units).toFixed(2)} of them affordable on a FULL mana bar\n`)
console.log('  move                       casts    hits       dmg   /hit    share')
for (const [k, v] of rows.slice(0, 8))
  console.log(`  ${k.padEnd(24)}${String(v.casts).padStart(7)}${String(v.hits).padStart(8)}`
    + `${v.dmg.toFixed(0).padStart(10)}${(v.hits ? v.dmg / v.hits : 0).toFixed(1).padStart(7)}`
    + `${((v.dmg / totalDmg) * 100).toFixed(1).padStart(8)}%`)

// ⚠️ THE PACING NUMBER. Duration is a consequence of how many landed blows a body
// absorbs; comparing seconds across leagues without it cannot say WHY one is slower.
const hits = rows.reduce((a, [, v]) => a + v.hits, 0)
const perHit = totalDmg / Math.max(1, hits)
console.log(`
  damage per landed hit ${perHit.toFixed(1)} against ${maxHp(sample.stats)} HP`
  + `  =>  ${(maxHp(sample.stats) / perHit).toFixed(1)} HITS TO KILL`)
console.log(`  casts that dealt no damage: `
  + `${(100 * (1 - hits / rows.reduce((a, [, v]) => a + v.casts, 0))).toFixed(0)}%`)
console.log(`\n  free-attack-ish share: ${((basic.reduce((a, [, v]) => a + v.dmg, 0) / totalDmg) * 100).toFixed(1)}%`)
