// The 40-matchup balance sweep. Replaces tools/dsweep.ts (12 fights) as the
// instrument every tuning decision is judged against.
//
// ⚠️ WHY IT EXISTS. A noise study on the 12-fight sweep — the same matchups re-run
// with five different seed batches — measured sd 0.7 on "resolved" and 0.9s on
// duration. That makes ±1.4 fights and ±1.8s indistinguishable from luck, and
// several tuning decisions had already been made on 1-2 fight differences. The
// STAT_SCALE_LOW pick in particular (1/320 -> 9/12, 1/270 -> 10/12, 1/230 -> 8/12)
// spanned less than the noise band and was, on that evidence, unfalsifiable.
//
// ⚠️ COMPOSITION IS A VARIABLE, NOT A CONSTANT. Melee measured as hopeless (100%
// deaths) when it fought alone and fine (81%) beside a second front-liner — the
// same monsters, a different team. So the ten compositions below deliberately
// span the range from all-caster to double-front-line rather than sampling
// "typical" teams, because there is no typical team.
//
// Usage: npx tsx tools/sweep40.ts [--noise]
//   --noise re-runs every composition across five seed batches and reports the
//   spread, so a claimed improvement can be checked against the instrument's own
//   error before it is believed.
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { FIELD_H, FIELD_W, SUDDEN_DEATH_AT } from '../src/tamerengine/types'
import { classForStats } from '../src/core'
import { COMPS, teamFor, trainTier, TRAIN_ELITE } from './comps'

// Positions relative, sizes fixed — identical at 40x22, symmetric at any size.
// See the same note in tools/ab.ts.
const OBSTACLES = [
  { x: FIELD_W * (19 / 40), y: FIELD_H * (6 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (21 / 40), y: FIELD_H * (15 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (13 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
  { x: FIELD_W * (27 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
]

const SEED_BATCHES = [
  ['s1', 's2', 's3', 's4'], ['q1', 'q2', 'q3', 'q4'], ['z1', 'z2', 'z3', 'z4'],
  ['m1', 'm2', 'm3', 'm4'], ['k1', 'k2', 'k3', 'k4'],
]

interface Run { resolved: number; fights: number; dur: number; kills: number; dmg: number
  byClass: Map<string, { dmg: number; casts: number; n: number }>
  // ⚠️ PER-COMPOSITION, because "composition is a variable" is the instrument's
  // founding claim and it could not be READ from the output — only the total was
  // reported, so a shape that grinds while the rest resolve was invisible. That
  // is exactly the signal focus fire has to be judged on.
  byComp: Map<string, { resolved: number; fights: number; dur: number; kills: number
    firstKill: number; firstKills: number }> }

function runBatch(seeds: string[], train = trainTier()): Run {
  const out: Run = { resolved: 0, fights: 0, dur: 0, kills: 0, dmg: 0, byClass: new Map(), byComp: new Map() }
  for (const comp of COMPS) for (const sd of seeds) {
    const A = teamFor(comp, 'a', sd, { train }) as never[]
    const B = teamFor(comp, 'b', sd, { train }) as never[]
    const front = (m: never) => ({ front: (m as never as { stats: Record<string, number> }).stats.CON
      + (m as never as { stats: Record<string, number> }).stats.STR
      - (m as never as { stats: Record<string, number> }).stats.INT
      - (m as never as { stats: Record<string, number> }).stats.WIS })
    const r = simulateFieldBattle({ seed: sd + comp.name, teamA: A, teamB: B,
      obstacles: OBSTACLES, placeA: autoDeployByRole('A', A.map(front)), placeB: autoDeployByRole('B', B.map(front)) })
    out.fights++; out.dur += r.duration
    if (r.duration < SUDDEN_DEATH_AT) out.resolved++
    const cs = out.byComp.get(comp.name)
      ?? { resolved: 0, fights: 0, dur: 0, kills: 0, firstKill: 0, firstKills: 0 }
    cs.fights++; cs.dur += r.duration
    if (r.duration < SUDDEN_DEATH_AT) cs.resolved++
    // ⚠️ TIME TO FIRST KILL is the focus-fire metric. Damage spread evenly over a
    // whole side means nobody crosses the death threshold until very late, and
    // total damage cannot see that — a fight can deal the MOST damage in the
    // sweep and still kill nobody until the clock runs down.
    const fk = (r.events as never as { kind: string; t: number }[]).find((e) => e.kind === 'death')
    if (fk) { cs.firstKill += fk.t; cs.firstKills++ }
    out.byComp.set(comp.name, cs)
    const cls = new Map<string, string>()
    A.forEach((m, i) => cls.set('A' + i, classForStats((m as never as { stats: never }).stats)))
    B.forEach((m, i) => cls.set('B' + i, classForStats((m as never as { stats: never }).stats)))
    for (const [, c] of cls) {
      const s = out.byClass.get(c) ?? { dmg: 0, casts: 0, n: 0 }; s.n++; out.byClass.set(c, s)
    }
    for (const e of r.events as never as { kind: string; id: string; dmg: number }[]) {
      if (e.kind === 'death') { out.kills++; cs.kills++ }
      if (e.kind === 'hit') { out.dmg += e.dmg
        const c = cls.get(e.id); if (c) { const s = out.byClass.get(c)!; s.dmg += e.dmg } }
      if (e.kind === 'cast') { const c = cls.get(e.id); if (c) { const s = out.byClass.get(c)!; s.casts++ } }
    }
  }
  return out
}

const line = (label: string, r: Run) =>
  `${label.padEnd(12)} ${String(r.resolved) + '/' + r.fights}`.padEnd(26)
  + `${(r.dur / r.fights).toFixed(1)}s`.padStart(7)
  + String(r.kills).padStart(8) + (r.dmg / r.fights).toFixed(0).padStart(11)

const noise = process.argv.includes('--noise')
if (!noise) {
  const r = runBatch(SEED_BATCHES[0])
  console.log(`${COMPS.length * SEED_BATCHES[0].length}-MATCHUP SWEEP — ${COMPS.length} compositions (${Math.min(...COMPS.map((c) => c.size))}v${Math.min(...COMPS.map((c) => c.size))}..${Math.max(...COMPS.map((c) => c.size))}v${Math.max(...COMPS.map((c) => c.size))}) x ${SEED_BATCHES[0].length} seeds, train ${trainTier()}${trainTier() === TRAIN_ELITE ? ' — ELITE, capstones unlocked' : ' — mid-game'}\n`)
  console.log('               resolved       dur   kills  dmg/fight')
  console.log(line('total', r))
  console.log('')
  console.log('by composition        resolved   dur   kills   1st kill')
  for (const [n, c] of r.byComp) {
    console.log(`  ${n.padEnd(22)}${(c.resolved + '/' + c.fights).padStart(5)}`
      + `${(c.dur / c.fights).toFixed(1)}s`.padStart(8)
      + String(c.kills).padStart(7)
      + `${c.firstKills ? (c.firstKill / c.firstKills).toFixed(1) + 's' : 'none'}`.padStart(11))
  }
  console.log('\ndamage by class (per fight):')
  for (const [c, s] of [...r.byClass].sort((a, b) => b[1].dmg - a[1].dmg))
    console.log('  ', c.padEnd(13), 'dmg', String(Math.round(s.dmg / r.fights)).padStart(5),
      ' casts', String(Math.round(s.casts / r.fights)).padStart(4), ' appearances', s.n)
} else {
  console.log('NOISE STUDY — same 40 matchups, five seed batches\n')
  console.log('               resolved       dur   kills  dmg/fight')
  const res: number[] = [], dur: number[] = []
  for (const seeds of SEED_BATCHES) {
    const r = runBatch(seeds); res.push(r.resolved); dur.push(r.dur / r.fights)
    console.log(line(seeds[0], r))
  }
  const mean = (a: number[]) => a.reduce((x, y) => x + y, 0) / a.length
  const sd = (a: number[]) => Math.sqrt(mean(a.map((x) => (x - mean(a)) ** 2)))
  console.log(`\nresolved: mean ${mean(res).toFixed(1)}/40  sd ${sd(res).toFixed(2)}  range ${Math.min(...res)}-${Math.max(...res)}`)
  console.log(`duration: mean ${mean(dur).toFixed(2)}s  sd ${sd(dur).toFixed(2)}s`)
  console.log(`\n=> a change must beat ~${(2 * sd(res)).toFixed(1)} fights or ~${(2 * sd(dur)).toFixed(1)}s to be believable.`)
}
