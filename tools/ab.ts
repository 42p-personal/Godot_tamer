// PAIRED A/B for balance constants.
//
// ⚠️ Pooled means cannot see small effects here. The 40-matchup sweep has sd 3.04s
// on duration, because its ten compositions genuinely differ (an all-caster fight
// resolves fast, a tank mirror grinds) — that spread is real signal about the game
// but pure noise when comparing two constants.
//
// The sim is deterministic given a seed, so the SAME fight can be run under both
// settings and compared directly. Pairing removes composition variance entirely and
// leaves only the effect of the change, which is the difference between "cannot
// distinguish 1/320 from 1/270" and a clean answer.
//
// Usage: npx tsx tools/ab.ts <label-A> <label-B>
//   Requires the caller to have produced two JSON snapshots via --dump.
//   npx tsx tools/ab.ts --dump out.json     (run once per setting)
import { COMPS, teamFor, trainTier } from './comps'
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { FIELD_H, FIELD_W, SUDDEN_DEATH_AT } from '../src/tamerengine/types'
import * as fs from 'fs'

// ⚠️ POSITIONS RELATIVE, SIZES FIXED. These were absolute (19/21/13/27), which
// is centred only on a 40-wide field — so any test that resizes the field would
// have been measuring "bigger map PLUS cover shoved off to one side", two
// changes at once. Written as fractions they are byte-identical at 40x22 and
// stay symmetric at any size. Sizes stay fixed on purpose: the premise is that
// the things standing on the ground do not grow with the ground.
const OBSTACLES = [
  { x: FIELD_W * (19 / 40), y: FIELD_H * (6 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (21 / 40), y: FIELD_H * (15 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (13 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
  { x: FIELD_W * (27 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
]
// ⚠️ POWER. Four seeds gives 40 pairs, of which a targeting change may move only
// ~18 — and 13-vs-5 on 18 is p=0.10 however real the effect is. `--wide` runs all
// five of the sweep's seed batches (200 pairs) so the sign test can actually
// resolve an effect this size instead of reporting "no effect" for lack of n.
const SEEDS = process.argv.includes('--wide')
  ? ['s1', 's2', 's3', 's4', 'q1', 'q2', 'q3', 'q4', 'z1', 'z2', 'z3', 'z4',
     'm1', 'm2', 'm3', 'm4', 'k1', 'k2', 'k3', 'k4']
  : ['s1', 's2', 's3', 's4']

function collect() {
  const rows: { key: string; dur: number; resolved: number; dmg: number; travel: number }[] = []
  for (const comp of COMPS) for (const sd of SEEDS) {
    const A = teamFor(comp, 'a', sd) as never[]
    const B = teamFor(comp, 'b', sd) as never[]
    const front = (m: never) => { const st = (m as never as { stats: Record<string, number> }).stats
      return { front: st.CON + st.STR - st.INT - st.WIS } }
    const r = simulateFieldBattle({ seed: sd + comp.name, teamA: A, teamB: B, obstacles: OBSTACLES,
      placeA: autoDeployByRole('A', A.map(front)), placeB: autoDeployByRole('B', B.map(front)) })
    let dmg = 0
    // ⚠️ TRAVEL IS THE GUARD RAIL on any targeting change. Melee choosing its
    // target by anything other than proximity is what once made bruisers cross
    // the map hunting a better victim and never swing, and "resolved" alone
    // cannot see that — a hunt and a focus-fire both change fight length.
    let travel = 0
    let prev: Map<string, { x: number; y: number }> | null = null
    let units = 0
    for (const e of r.events as never as
      { kind: string; dmg: number; units?: { id: string; x: number; y: number }[] }[]) {
      if (e.kind === 'hit') dmg += e.dmg
      if (e.kind === 'snapshot' && e.units) {
        units = Math.max(units, e.units.length)
        if (prev) for (const u of e.units) {
          const p = prev.get(u.id)
          if (p) travel += Math.hypot(u.x - p.x, u.y - p.y)
        }
        prev = new Map(e.units.map((u) => [u.id, { x: u.x, y: u.y }]))
      }
    }
    rows.push({ key: comp.name + '/' + sd, dur: r.duration, resolved: r.duration < SUDDEN_DEATH_AT ? 1 : 0, dmg,
      travel: travel / Math.max(1, units) })
  }
  return rows
}

const dumpAt = process.argv.indexOf('--dump')
if (dumpAt >= 0) {
  fs.writeFileSync(process.argv[dumpAt + 1], JSON.stringify(collect()))
  console.log('dumped', process.argv[dumpAt + 1])
} else {
  const A = JSON.parse(fs.readFileSync(process.argv[2], 'utf8')) as ReturnType<typeof collect>
  const B = JSON.parse(fs.readFileSync(process.argv[3], 'utf8')) as ReturnType<typeof collect>
  const map = new Map(A.map((r) => [r.key, r]))
  let better = 0, worse = 0, same = 0, dDur = 0, dRes = 0, dDmg = 0, dTrv = 0
  const moved: string[] = []
  for (const b of B) {
    const a = map.get(b.key)!; const dd = b.dur - a.dur
    dDur += dd; dRes += b.resolved - a.resolved; dDmg += b.dmg - a.dmg; dTrv += b.travel - a.travel
    if (Math.abs(dd) < 0.05) same++; else if (dd < 0) better++; else worse++
    if (b.resolved !== a.resolved) moved.push(`${b.key} ${a.resolved ? 'resolved->timeout' : 'timeout->RESOLVED'}`)
  }
  const n = B.length
  const durs = B.map((b) => b.dur - map.get(b.key)!.dur)
  const mean = durs.reduce((x, y) => x + y, 0) / n
  const sd = Math.sqrt(durs.map((d) => (d - mean) ** 2).reduce((x, y) => x + y, 0) / n)
  const se = sd / Math.sqrt(n)
  console.log(`PAIRED A/B over ${n} identical matchups\n`)
  console.log(`  fights that got FASTER : ${better}`)
  console.log(`  fights that got SLOWER : ${worse}`)
  console.log(`  unchanged              : ${same}`)
  console.log(`\n  mean duration delta : ${mean >= 0 ? '+' : ''}${mean.toFixed(2)}s  (sd ${sd.toFixed(2)}, se ${se.toFixed(2)})`)
  console.log(`  95% CI              : ${(mean - 1.96 * se).toFixed(2)}s .. ${(mean + 1.96 * se).toFixed(2)}s`)
  console.log(`  resolved delta      : ${dRes >= 0 ? '+' : ''}${dRes} fights`)
  console.log(`  damage/fight delta  : ${dDmg / n >= 0 ? '+' : ''}${(dDmg / n).toFixed(0)}`)
  console.log(`  travel/unit delta   : ${dTrv / n >= 0 ? '+' : ''}${(dTrv / n).toFixed(1)}`
    + `  (a targeting change that RAISES this is hunting, not focusing)`)
  // ⚠️ The mean CI is the WRONG primary test here and nearly caused a good change
  // to be discarded. A handful of fights swing 20-30s (a fight that tips from
  // timeout to a kill changes wholesale), so sd is huge and the CI is wide even
  // when the change helps almost every fight. The SIGN TEST asks the robust
  // question instead — of the fights that moved at all, did more get better than
  // worse? — and is immune to those outliers.
  const moved2 = better + worse
  const logC = (n: number, k: number) => { let s = 0; for (let i = 1; i <= k; i++) s += Math.log(n - k + i) - Math.log(i); return s }
  let p = 0
  const hi = Math.max(better, worse)
  for (let k = hi; k <= moved2; k++) p += Math.exp(logC(moved2, k) + moved2 * Math.log(0.5))
  p = Math.min(1, 2 * p) // two-tailed
  // ⚠️ RESOLVED IS THE DESIGN TARGET, not duration — the goal is fights that end
  // on the monsters' own merits before sudden death has to force them. It is a
  // PAIRED BINARY outcome, so the test is McNemar's: of the fights that flipped,
  // did more flip INTO resolved than out? A net "+7 fights" means nothing without
  // it — 16 gained against 9 lost is a very different claim from 7 gained and 0
  // lost, and the totals alone cannot tell them apart.
  const gained = moved.filter((m) => m.includes('->RESOLVED')).length
  const lost = moved.length - gained
  let pRes = 0
  const hiR = Math.max(gained, lost)
  for (let k = hiR; k <= moved.length; k++) pRes += Math.exp(logC(moved.length, k) + moved.length * Math.log(0.5))
  pRes = Math.min(1, 2 * pRes)

  const meanSig = Math.abs(mean) > 1.96 * se
  console.log(`\n  mean-CI verdict : ${meanSig ? 'significant' : 'not significant (CI includes zero)'}`)
  console.log(`  SIGN TEST       : ${better} better / ${worse} worse of ${moved2} that moved,  p = ${p.toFixed(4)}`)
  // ⚠️ THE VERDICT MUST NAME THE DIRECTION. This printed "more fights improved
  // than chance allows" on ANY significant split, including one where the change
  // made 119 of 199 fights WORSE — a green-looking line under a red result is
  // exactly how a bad change gets kept.
  console.log(`  => ${p >= 0.05
    ? 'NO EFFECT — the split is what a coin would give.'
    : better > worse
      ? 'REAL EFFECT — more fights got FASTER than chance allows.'
      : 'REAL REGRESSION — more fights got SLOWER than chance allows.'}`)
  console.log(`\n  McNEMAR (resolved) : ${gained} gained / ${lost} lost of ${moved.length} flips,  p = ${pRes.toFixed(4)}`)
  console.log(`  => ${moved.length === 0 ? 'no fight changed resolution status.' : pRes >= 0.05
    ? 'NO EFFECT on resolution — the flips are a coin.'
    : gained > lost
      ? 'REAL EFFECT on the metric that matters — more fights now end on their own.'
      : 'REAL REGRESSION — fewer fights now end on their own.'}`)
  if (moved.length) console.log('\n  fights that flipped:\n   ', moved.join('\n    '))

  // Per-composition, because a pooled verdict hides WHERE a change acts. Focus
  // fire should show up on the CON-heavy comps first and barely move all-caster.
  const byComp = new Map<string, { d: number; r: number; n: number }>()
  for (const b of B) {
    const a = map.get(b.key)!
    const c = b.key.split('/')[0]
    const s = byComp.get(c) ?? { d: 0, r: 0, n: 0 }
    s.d += b.dur - a.dur; s.r += b.resolved - a.resolved; s.n++
    byComp.set(c, s)
  }
  console.log('\n  by composition (duration delta, resolved delta):')
  for (const [c, s] of [...byComp].sort((x, y) => x[1].d - y[1].d))
    console.log(`    ${c.padEnd(15)} ${(s.d / s.n >= 0 ? '+' : '') + (s.d / s.n).toFixed(1)}s`.padEnd(28)
      + `${s.r >= 0 ? '+' : ''}${s.r}`)
}
