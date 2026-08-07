// CAN A DAMAGE CLASS ACTUALLY KILL A TANK?
//
// ⚠️ THIS IS THE ACCEPTANCE TEST, not fight duration. Tank-vs-tank grinding is
// fine flavour — two walls SHOULD take a while. What is not fine is a Warrior
// who cannot break a Wall, because that makes the CON tier strictly dominant
// against the very classes built to answer it.
//
// The 40-matchup sweep cannot see this: it measures whole 3v3 fights, where a
// tank's survival is confounded with its team's, its healer's, and positioning.
// This isolates the question — one damage dealer, one tank, no help, no cover.
//
// ⚠️ Read the WIN RATE first and the time second. A 55s win and a 55s loss look
// identical on duration but are opposite answers.
//
// Usage: npx tsx tools/breakwall.ts
import { generateMonster } from '../src/monster'
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { classForStats } from '../src/core'

const mk = (id: string, sp: string, train = 850) => generateMonster(id, { speciesId: sp, train }) as never

/** One representative of each damage identity, plus two support tiers for contrast. */
const ATTACKERS = [
  { sp: 'kongrath', tag: 'STR bruiser' },
  { sp: 'maneleo', tag: 'STR duelist' },
  { sp: 'grivvel', tag: 'DEX assassin' },
  { sp: 'pinguox', tag: 'DEX marksman' },
  { sp: 'archmage-aleph', tag: 'INT caster' },
  { sp: 'maelurk', tag: 'INT mage' },
  { sp: 'strixil', tag: 'WIS support' },
  { sp: 'larkessa', tag: 'CHA support' },
]
/** The walls. */
const TANKS = ['aegisox', 'tortavos', 'nautilux', 'crocmaw']
const SEEDS = ['s1', 's2', 's3', 's4', 'q1', 'q2']

interface Res { tag: string; cls: string; wins: number; n: number; ttk: number[]; dur: number[] }
const out = new Map<string, Res>()

for (const atk of ATTACKERS) for (const tank of TANKS) for (const sd of SEEDS) {
  const A = [mk(`${sd}${atk.sp}A`, atk.sp)]
  const B = [mk(`${sd}${tank}B`, tank)]
  // No obstacles: cover would let a marksman kite forever and a bruiser never
  // arrive, which measures the map rather than the matchup.
  const r = simulateFieldBattle({ seed: sd + atk.sp + tank, teamA: A, teamB: B, obstacles: [],
    placeA: [{ x: 8, y: 11 }], placeB: [{ x: 32, y: 11 }] })
  const cls = classForStats((A[0] as never as { stats: never }).stats)
  const key = atk.tag
  const rec = out.get(key) ?? { tag: atk.tag, cls, wins: 0, n: 0, ttk: [], dur: [] }
  rec.n++
  rec.dur.push(r.duration)
  if (r.winner === 'A') { rec.wins++; rec.ttk.push(r.duration) }
  out.set(key, rec)
}

const mean = (a: number[]) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : NaN)
console.log(`BREAKING THE WALL — 1v1, ${ATTACKERS.length} attackers x ${TANKS.length} tanks x ${SEEDS.length} seeds, train 850\n`)
console.log('attacker            class          wins    win%   avg kill time   avg fight')
for (const r of [...out.values()].sort((a, b) => b.wins / b.n - a.wins / a.n)) {
  const wr = r.wins / r.n
  console.log(
    r.tag.padEnd(20) + r.cls.padEnd(14)
    + `${r.wins}/${r.n}`.padStart(6)
    + (wr * 100).toFixed(0).padStart(7) + '%'
    + (r.ttk.length ? mean(r.ttk).toFixed(1) + 's' : '—').padStart(14)
    + (mean(r.dur).toFixed(1) + 's').padStart(12)
    + (wr < 0.5 ? '   <- cannot break the wall' : ''))
}
const dmg = [...out.values()].filter((r) => !r.tag.includes('support'))
console.log(`\nDAMAGE CLASSES vs tanks: ${dmg.reduce((n, r) => n + r.wins, 0)}/${dmg.reduce((n, r) => n + r.n, 0)}`
  + ` = ${(dmg.reduce((n, r) => n + r.wins, 0) / dmg.reduce((n, r) => n + r.n, 0) * 100).toFixed(0)}% win rate.`)
console.log('The bar: a damage class should beat a tank most of the time 1v1. Supports')
console.log('are expected to lose — that is the trade they are paid for in utility.')
