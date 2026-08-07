// HOW CLOSE DID THE TIMEOUT FIGHTS GET?
//
// ⚠️ WHY THIS EXISTS. Focus fire was aimed at the CON-heavy comps on the theory
// that melee spreads damage across three bodies so nobody crosses the death
// threshold. It measurably helped three OTHER comps and moved tank-mirror by
// +0.2s. Before tuning targeting harder, this asks what the timeouts actually
// look like: a fight stalled at 95% of a side removed is a small throughput
// nudge away from resolving, one stalled at 50% is a structural problem, and the
// two want opposite fixes.
//
// ⚠️ THREE MEASUREMENT TRAPS THIS FILE ALREADY FELL INTO — do not reintroduce:
//   1. Summing `hit` events undercounts damage. FIVE paths reduce HP (strike,
//      damage zones, sudden-death chip, thorns, execute) and only strike emits a
//      `hit`. Read HP off the snapshot stream instead; it is total by
//      construction.
//   2. Aggregating a per-side quantity ACROSS fights is meaningless when the
//      winner alternates — summing dmgA over four seeds mixes the winning and
//      losing side and drags every ratio under 1.0, which read as "no comp can
//      ever wipe a side" while those comps were demonstrably wiping one in 20s.
//      Everything here is computed PER FIGHT and only then averaged.
//   3. "Fraction of the enemy removed" is trivially 1.00 in any fight that
//      resolved — a wipe is the end condition. It is only informative about
//      TIMEOUTS, so that is the only place it is reported.
//
// Usage: npx tsx tools/ehp.ts
import { generateMonster } from '../src/monster'
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'

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
const SEEDS = ['s1', 's2', 's3', 's4']

interface Fight { comp: string; seed: string; dur: number; timeout: boolean
  removed: number; downed: number; standing: number; healed: number }

const fights: Fight[] = []
for (const comp of COMPS) for (const sd of SEEDS) {
  const A = comp.a.map((s, i) => mk(`${sd}${comp.name}a${i}`, s))
  const B = comp.b.map((s, i) => mk(`${sd}${comp.name}b${i}`, s))
  const front = (m: never) => { const st = (m as never as { stats: Record<string, number> }).stats
    return { front: st.CON + st.STR - st.INT - st.WIS } }
  const r = simulateFieldBattle({ seed: sd + comp.name, teamA: A, teamB: B, obstacles: OBSTACLES,
    placeA: autoDeployByRole('A', A.map(front)), placeB: autoDeployByRole('B', B.map(front)) })

  const ev = r.events as never as
    { t: number; kind: string; amount: number; units?: { id: string; hp: number }[] }[]
  const snaps = ev.filter((e) => e.kind === 'snapshot' && e.units)
  const first = snaps[0]!.units!, last = snaps[snaps.length - 1]!.units!
  const side = (u: { id: string }[], s: string) => u.filter((x) => x.id[0] === s)
  const hp = (u: { hp: number }[]) => u.reduce((n, x) => n + x.hp, 0)
  const startA = hp(side(first, 'A')), startB = hp(side(first, 'B'))
  const endA = hp(side(last, 'A')), endB = hp(side(last, 'B'))

  // Per fight: how much of the WORSE-OFF side has been removed. That is how close
  // this fight came to ending, whichever side was winning.
  // ⚠️ TRAP 4: snapshot hp is `Math.round(u.hp)`, so a unit clinging to 0.4 HP
  // reads as 0 — exactly the tail this measurement is about. Counting "hp <= 0"
  // as downed claimed 100% of a side removed in fights where three monsters were
  // still alive. The engine's own survivor counts are exact; use those.
  const removed = Math.max(1 - endA / startA, 1 - endB / startB)
  const downed = 6 - (r.survivorsA + r.survivorsB)
  let healed = 0
  for (const e of ev) if (e.kind === 'heal') healed += e.amount

  fights.push({ comp: comp.name, seed: sd, dur: r.duration, timeout: r.duration >= 55,
    removed, downed, standing: 6 - downed, healed })
}

const byComp = new Map<string, Fight[]>()
for (const f of fights) byComp.set(f.comp, [...(byComp.get(f.comp) ?? []), f])
const mean = (a: number[]) => a.reduce((x, y) => x + y, 0) / Math.max(1, a.length)

console.log('THE TIMEOUT FIGHTS — how close did they come to ending?\n')
console.log('comp             timeouts   of the losing side    still     healing   dur')
console.log('                  /4        REMOVED at the bell   standing  /fight')
const rows = [...byComp].map(([c, fs]) => {
  const to = fs.filter((f) => f.timeout)
  return { c, n: to.length, removed: mean(to.map((f) => f.removed)),
    standing: mean(to.map((f) => f.standing)), heal: mean(fs.map((f) => f.healed)),
    dur: mean(fs.map((f) => f.dur)) }
}).sort((a, b) => b.n - a.n || b.removed - a.removed)
for (const r of rows) {
  console.log(
    r.c.padEnd(16) + String(r.n).padStart(5)
    + (r.n ? (r.removed * 100).toFixed(0) + '%' : '—').padStart(21)
    + (r.n ? r.standing.toFixed(1) : '—').padStart(11)
    + r.heal.toFixed(0).padStart(10)
    + (r.dur.toFixed(1) + 's').padStart(8)
    + (r.n && r.removed > 0.85 ? '   <- one nudge from resolving' : ''))
}
const to = fights.filter((f) => f.timeout)
console.log(`\n${to.length}/40 fights timed out. Of those, the losing side had `
  + `${(mean(to.map((f) => f.removed)) * 100).toFixed(0)}% of its HP removed`)
console.log(`and ${mean(to.map((f) => f.standing)).toFixed(1)} of 6 monsters were still standing at the bell.`)
console.log('\nHIGH removed% + few standing => a throughput nudge resolves these.')
console.log('LOW removed% => something is preventing damage entirely; aim is not the lever.')

console.log('\nTHE TIMEOUT FIGHTS, INDIVIDUALLY (aggregates hid the shape of these):')
for (const f of to)
  console.log(`  ${(f.comp + '/' + f.seed).padEnd(20)} ${f.dur.toFixed(1)}s`
    + `  losing side ${(f.removed * 100).toFixed(0)}% removed`
    + `  ${f.standing} of 6 alive  healing ${f.healed.toFixed(0)}`)
