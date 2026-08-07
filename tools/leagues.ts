// SWEEP THE WHOLE PROGRESSION — one 40-matchup run per league ceiling.
//
// ⚠️ `train` IS A BUDGET, NOT A STAT, so a league's cap cannot be passed in
// directly. This binary-searches the budget whose top trained stat lands on each
// cap, then runs the standard sweep there. That mapping is the only reason the
// rows are comparable to each other at all.
// ⚠️ TWO FINDINGS FROM ITS FIRST RUN, BOTH RECORDED HERE SO THEY ARE NOT REDISCOVERED:
//
// 1. FIXED — `generateMonster` used to clamp every stat at 1000 regardless of
//    budget, so the top two leagues could not be simulated and this tool reported
//    a 1000-stat Masters monster as an Apex one WITHOUT SAYING SO. `GenOptions
//    .statCap` now carries the ceiling; it still defaults to 1000, so every other
//    caller and every golden is byte-identical. topStat now lands on the cap for
//    all eleven rows, which is what makes them comparable.
//
// 2. ⚠️ WOOD WAS THE OUTLIER, AND THIS ENTRY'S EXPLANATION OF IT WAS WRONG — kept
//    as written so the mistake is not made twice. It asserted "the flat +40 in
//    maxHp and a move's base power dominate" as established fact. Both were later
//    MEASURED: removing 75% of the flat +40 buys 5.4s of a 17s gap, and raising
//    the free attack's base buys 4.4s. Neither is the driver.
//    The driver was flat `guard` DR — authored in the same units as `power`, which
//    scales with stat while guard does not, so one authored 6 removed 72% of every
//    hit at Wood and 6% at Masters. See GUARD_MAX_FRACTION and docs/BALANCING.md.
//    Half the gap was not in the engine at all: this tool ran 2v2..5v5 at every
//    league, and WOOD IS 1v1. Wood now reads 18.5s beside Copper's 17.3s.
//    ⚠️ The lesson is the shape of the error, not the constant: a plausible cause
//    written into a tool's header becomes fact by repetition. Measure, then write.
import { generateMonster } from '../src/monster'
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { FIELD_H, FIELD_W, SUDDEN_DEATH_AT } from '../src/tamerengine/types'
import { LEAGUES, STATS } from '../src/core'
import { SPECIES } from '../src/species'
import { COMPS, compAtSize, teamFor } from './comps'
import { teamSizeForLeague } from '../src/town'

const OB = [
  { x: FIELD_W * (19 / 40), y: FIELD_H * (6 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (21 / 40), y: FIELD_H * (15 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (13 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
  { x: FIELD_W * (27 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
]
const topStat = (train: number, cap = 1000) => {
  let mx = 0
  for (const sp of SPECIES) {
    const m = generateMonster(`cal-${sp.id}`, { speciesId: sp.id, train, statCap: cap }) as never as
      { stats: Record<string, number> }
    for (const s of STATS) mx = Math.max(mx, m.stats[s])
  }
  return mx
}
/** Budget whose top trained stat lands nearest `cap`. */
function trainForCap(cap: number): number {
  let lo = 20, hi = 6000
  for (let i = 0; i < 18; i++) {
    const mid = Math.round((lo + hi) / 2)
    if (topStat(mid, cap) < cap) lo = mid; else hi = mid
  }
  return hi
}

/**
 * ⚠️ AUTHORED BUDGETS FOR THE TOP TWO. Their caps (1050/1100) sit above the
 * 1000 clamp in `generateMonster`, so the binary search cannot solve for them —
 * it would run to its ceiling and silently report a Masters monster. These are
 * the budgets the design says a monster at that league has been trained with.
 */
const TRAIN_OVERRIDE: Record<string, number> = { 'Tamer Elite': 2800, 'Tamers Apex': 3500 }
interface Batch { fights: number; pre: number; dur: number; kills: number
  dmg: number; fk: number; fkn: number; worst: number; worstName: string }

/**
 * ⚠️ EACH LEAGUE IS FOUGHT AT THE TEAM SIZE IT ACTUALLY USES. It was not, and that
 * made the headline finding of this tool an artefact: Wood is **1v1** in the game
 * (`TEAM_SIZE_BY_LEAGUE`), but every row ran the standard 2v2..5v5 compositions, so
 * "Wood is the outlier of the whole progression at 41.2s" described a five-a-side
 * brawl between cap-100 monsters that no Wood player can ever enter.
 *
 * ⚠️ Same family as the ten hand-picked species triples that existed nowhere in the
 * game, and `tools/comps.ts:compAtSize` was built to fix that one. A league is a cap,
 * a BUDGET and a TEAM SIZE; two out of three is a different game.
 *
 * ⚠️ The rows are no longer strictly comparable to each other on duration, and that
 * is correct rather than a regression — Wood v Apex differs by size as well as by
 * stats, because the GAME differs by size. Read each row against the experience it
 * models, not against its neighbour.
 */
function runBatch(train: number, cap: number, seeds: string[], size: number): Batch {
  const b: Batch = { fights: 0, pre: 0, dur: 0, kills: 0, dmg: 0, fk: 0, fkn: 0, worst: 0, worstName: '' }
  for (const c0 of COMPS) for (const sd of seeds) {
    const c = compAtSize(c0, size)
    const mk = (id: string, sp: string) =>
      generateMonster(id, { speciesId: sp, train, statCap: cap }) as never
    const A = teamFor(c, 'a', sd, { train, statCap: cap }) as never[]
    const B = teamFor(c, 'b', sd, { train, statCap: cap }) as never[]
    const fr = (m: never) => {
      const st = (m as never as { stats: Record<string, number> }).stats
      return { front: st.CON + st.STR - st.INT - st.WIS }
    }
    const r = simulateFieldBattle({ seed: sd + c.name, teamA: A, teamB: B, obstacles: OB,
      placeA: autoDeployByRole('A', A.map(fr)), placeB: autoDeployByRole('B', B.map(fr)) })
    b.fights++; b.dur += r.duration
    if (r.duration < SUDDEN_DEATH_AT) b.pre++
    if (r.duration > b.worst) { b.worst = r.duration; b.worstName = `${c.name} (${sd})` }
    const ev = r.events as never as { kind: string; t: number; dmg: number }[]
    const first = ev.find((e) => e.kind === 'death')
    if (first) { b.fk += first.t; b.fkn++ }
    for (const e of ev) { if (e.kind === 'death') b.kills++; if (e.kind === 'hit') b.dmg += e.dmg }
  }
  return b
}

/** The same five seed batches sweep40 uses, so the two studies are comparable. */
const SEED_BATCHES = [
  ['s1', 's2', 's3', 's4'], ['q1', 'q2', 'q3', 'q4'], ['z1', 'z2', 'z3', 'z4'],
  ['m1', 'm2', 'm3', 'm4'], ['k1', 'k2', 'k3', 'k4'],
]

const noise = process.argv.includes('--noise')
const only = process.argv.find((a, i) => process.argv[i - 1] === '--league')
const WANT = LEAGUES.map((l) => l.name).filter((n) => !only || n === only)
if (only && !WANT.length) { console.error(`no league named "${only}"`); process.exit(1) }

if (noise) {
  // ⚠️ WHY THIS EXISTS. A single batch showed Tamer Elite at 39/40 and 22.5s
  // against a 17-20s band elsewhere, which read as a lategame problem. Five
  // batches showed it was ONE fight in 200 — a 256s generalist mirror that
  // sudden death closed correctly — and the other four batches sat at 17.2-18.0s.
  // The apparent effect was entirely one seed. A per-league claim needs the
  // spread, not a run.
  // ⚠️ 200 fights per league. Use `--league "<name>"` unless you want all eleven.
  console.log(`NOISE STUDY — ${SEED_BATCHES.length} seed batches x 40 matchups per league
`)
  for (const name of WANT) {
    const L = LEAGUES.find((l) => l.name === name)!
    const train = TRAIN_OVERRIDE[name] ?? trainForCap(L.cap)
    const runs = SEED_BATCHES.map((seeds) => runBatch(train, L.cap, seeds, teamSizeForLeague(name)))
    const durs = runs.map((b) => b.dur / b.fights)
    const mean = durs.reduce((a, x) => a + x, 0) / durs.length
    const sd = Math.sqrt(durs.reduce((a, d) => a + (d - mean) ** 2, 0) / (durs.length - 1))
    const reachedSD = runs.reduce((a, b) => a + (b.fights - b.pre), 0)
    console.log(`${name} (cap ${L.cap}, train ${train})`)
    runs.forEach((b, i) => console.log(`  ${SEED_BATCHES[i][0].padEnd(4)}`
      + `${(b.pre + '/' + b.fights).padStart(8)}${(b.dur / b.fights).toFixed(1).padStart(8)}s`
      + `   longest ${b.worst.toFixed(0)}s ${b.worstName}`))
    console.log(`  => mean ${mean.toFixed(1)}s  sd ${sd.toFixed(2)}s  ·  `
      + `${reachedSD} of ${runs.length * 40} fights reached sudden death`)
    console.log(`  => a change must beat ~${(2 * sd).toFixed(1)}s to be believable
`)
  }
  process.exit(0)
}

console.log('league        cap  train  size  topStat  resolved    dur   kills  dmg/fight  1st kill')
for (const name of WANT) {
  const L = LEAGUES.find((l) => l.name === name)!
  const train = TRAIN_OVERRIDE[name] ?? trainForCap(L.cap)
  const b = runBatch(train, L.cap, ['s1', 's2', 's3', 's4'], teamSizeForLeague(name))
  console.log(`${name.padEnd(12)}${String(L.cap).padStart(5)}${String(train).padStart(7)}`
    + `${String(topStat(train, L.cap)).padStart(9)}${(b.pre + '/' + b.fights).padStart(10)}`
    + `${(b.dur / b.fights).toFixed(1) + 's'}`.padStart(8) + String(b.kills).padStart(8)
    + (b.dmg / b.fights).toFixed(0).padStart(11)
    + `${b.fkn ? (b.fk / b.fkn).toFixed(1) + 's' : '-'}`.padStart(10))
}
