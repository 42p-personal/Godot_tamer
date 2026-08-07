// HOW VARIED ARE THE KITS THE PICKER ACTUALLY BUILDS?
//
// ⚠️ THE FAILURE THIS EXISTS FOR. A pool can be large and still play small: the
// picker ranks, so if a handful of moves out-score their neighbours everyone
// drafts the same four. It has happened here before — a +11 power lift on Rime
// Bind put it in 36% of ALL monsters across ten classes, "a homogenised pool from
// one number moving". Nothing measures that today.
//
// Reports, over a wide sample of generated monsters:
//   coverage   how many of the 141 moves are drafted by ANYBODY
//   top-10     share of all drafted slots taken by the ten most-picked moves
//   HHI        Herfindahl concentration, 0 = perfectly even, 1 = one move only
//
// Usage: npx tsx tools/variety.ts [--train N]
import { generateMonster } from '../src/monster'
import { ALL_MOVES } from '../src/moves'
import { SPECIES } from '../src/species'
import type { Monster } from '../src/core'

const ti = process.argv.indexOf('--train')
const TRAIN = ti >= 0 ? Number(process.argv[ti + 1]) : 850
const N = 40 // seeds per species

const count = new Map<string, number>()
let slots = 0
for (const sp of SPECIES) for (let i = 0; i < N; i++) {
  const m = generateMonster(`v${sp.id}${i}`, { speciesId: sp.id, train: TRAIN }) as Monster
  for (const mv of m.loadout) { count.set(mv.name, (count.get(mv.name) ?? 0) + 1); slots++ }
}
const ranked = [...count.entries()].sort((a, b) => b[1] - a[1])
const top10 = ranked.slice(0, 10).reduce((n, [, c]) => n + c, 0) / slots
const hhi = ranked.reduce((n, [, c]) => n + (c / slots) ** 2, 0)

console.log(`KIT VARIETY — train ${TRAIN}, ${SPECIES.length * N} monsters, ${slots} drafted slots\n`)
console.log(`  coverage      ${count.size}/${ALL_MOVES.length} moves drafted by anybody `
  + `(${(100 * count.size / ALL_MOVES.length).toFixed(1)}%)`)
console.log(`  never drafted ${ALL_MOVES.length - count.size}`)
console.log(`  top-10 share  ${(100 * top10).toFixed(1)}% of all slots`)
console.log(`  HHI           ${hhi.toFixed(4)}  (even spread over ${count.size} moves would be ${(1 / count.size).toFixed(4)})`)
console.log('\n  most-drafted:')
for (const [n, c] of ranked.slice(0, 12)) console.log(`    ${n.padEnd(22)}${(100 * c / slots).toFixed(1)}%`)
