// Dump ONE composition at a LEAGUE CAP, in the shape tools/gif5v5.py renders.
//
// ⚠️ A LEAGUE IS A CAP PLUS A BUDGET, NOT JUST A BUDGET. `statCap` is the ceiling
// any single stat may reach; `train` is the points spent getting there. Dumping at
// a training tier alone (what dumpcomp.ts does) renders a monster that does not
// exist in that league — the cap is what makes a Wood monster a Wood monster.
// The budget is solved per cap the same way tools/leagues.ts does it.
//
// ⚠️ TOP TWO ARE AUTHORED. Their caps (1050/1100) sit above generateMonster's 1000
// clamp, so the binary search cannot solve them and would silently report Masters.
//
// Usage: npx tsx tools/dumpleague.ts "<league>" "<comp>" <seed> <out.json>
import * as fs from 'fs'
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { FIELD_H, FIELD_W } from '../src/tamerengine/types'
import { classForStats } from '../src/core'
import { COMPS, compAtSize, teamFor } from './comps'
import { LEAGUES, STATS } from '../src/core'
import { SPECIES } from '../src/species'
import { generateMonster } from '../src/monster'

const league = process.argv[2] ?? 'Iron'
const want = process.argv[3], sd = process.argv[4] ?? 's1', out = process.argv[5] ?? 'comp.json'
const TRAIN_OVERRIDE: Record<string, number> = { 'Tamer Elite': 2800, 'Tamers Apex': 3500 }
const lg = LEAGUES.find((l) => l.name === league)
if (!lg) { console.error(`no league "${league}"`); process.exit(1) }
const topStat = (train: number, cap: number) => {
  let mx = 0
  for (const sp of SPECIES) {
    const m = generateMonster(`cal-${sp.id}`, { speciesId: sp.id, train, statCap: cap }) as never as
      { stats: Record<string, number> }
    for (const s of STATS) mx = Math.max(mx, m.stats[s])
  }
  return mx
}
function trainForCap(cap: number): number {
  let lo = 20, hi = 6000
  for (let i = 0; i < 18; i++) {
    const mid = Math.round((lo + hi) / 2)
    if (topStat(mid, cap) < cap) lo = mid; else hi = mid
  }
  return hi
}
const TRAIN = TRAIN_OVERRIDE[league] ?? trainForCap(lg.cap)
const CAP = lg.cap
const sizeArg = process.argv.indexOf('--size')
let c = COMPS.find((x) => x.name === want)
if (!c) { console.error(`no comp "${want}" — have:\n  ${COMPS.map((x) => x.name).join('\n  ')}`); process.exit(1) }
const OB = [
  { x: FIELD_W * (19 / 40), y: FIELD_H * (6 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (21 / 40), y: FIELD_H * (15 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (13 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
  { x: FIELD_W * (27 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
]
if (c && sizeArg > 0) c = compAtSize(c, Number(process.argv[sizeArg + 1]))
const A = teamFor(c!, 'a', sd, { train: TRAIN, statCap: CAP }) as never[]
const B = teamFor(c!, 'b', sd, { train: TRAIN, statCap: CAP }) as never[]
const fr = (m: never) => {
  const st = (m as never as { stats: Record<string, number> }).stats
  return { front: st.CON + st.STR - st.INT - st.WIS }
}
const r = simulateFieldBattle({ seed: sd + c.name, teamA: A, teamB: B, obstacles: OB,
  placeA: autoDeployByRole('A', A.map(fr)), placeB: autoDeployByRole('B', B.map(fr)) })

const meta = new Map<string, { name: string; cls: string; species: string }>()
const reg = (arr: never[], side: string, sp: string[]) => arr.forEach((m, i) => {
  const mm = m as never as { name: string; stats: never }
  meta.set(side + i, { name: mm.name, cls: classForStats(mm.stats), species: sp[i] })
})
reg(A, 'A', c.a); reg(B, 'B', c.b)

interface Frame { t: number; units: unknown[]; casts: unknown[]; hits: unknown[]; deaths: string[] }
const frames: Frame[] = []
let pending = { casts: [] as unknown[], hits: [] as unknown[], deaths: [] as string[] }
for (const e of r.events as never as {
  t: number; kind: string; id: string; targetId: string; move: string; dmg: number; crit: boolean
  units?: unknown[] }[]) {
  if (e.kind === 'cast') pending.casts.push({ id: e.id, move: e.move })
  else if (e.kind === 'hit') pending.hits.push({ id: e.id, targetId: e.targetId, dmg: e.dmg, crit: e.crit })
  else if (e.kind === 'death') pending.deaths.push(e.id)
  else if (e.kind === 'snapshot' && e.units) {
    frames.push({ t: e.t, units: e.units, ...pending })
    pending = { casts: [], hits: [], deaths: [] }
  }
}
fs.writeFileSync(out, JSON.stringify({
  seed: sd, winner: r.winner, duration: r.duration,
  survivorsA: r.survivorsA, survivorsB: r.survivorsB,
  map: { id: 'sweep', name: `${league} cap ${CAP} — ${c.name}`, brief: '', w: FIELD_W, h: FIELD_H },
  obstacles: OB, meta: Object.fromEntries(meta), frames,
}))
console.log(`${out}: ${league} (cap ${CAP}, train ${TRAIN}) ${c.name} · ${frames.length} frames, `
  + `${r.duration}s, winner ${r.winner} (${r.survivorsA}v${r.survivorsB})`)
