// Dump ONE composition from tools/comps.ts, at either training tier, in the
// shape tools/gif5v5.py renders. ⚠️ Uses the SWEEP's obstacles and default field
// size, not a named arena — otherwise it is not the fight the sweep measured.
// Usage: npx tsx tools/dumpcomp.ts "<comp name>" <seed> <out.json> [--elite]
import * as fs from 'fs'
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { FIELD_H, FIELD_W } from '../src/tamerengine/types'
import { classForStats } from '../src/core'
import { COMPS, teamFor, trainTier } from './comps'

const want = process.argv[2], sd = process.argv[3] ?? 's1', out = process.argv[4] ?? 'comp.json'
const c = COMPS.find((x) => x.name === want)
if (!c) { console.error(`no comp "${want}" — have:\n  ${COMPS.map((x) => x.name).join('\n  ')}`); process.exit(1) }
const OB = [
  { x: FIELD_W * (19 / 40), y: FIELD_H * (6 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (21 / 40), y: FIELD_H * (15 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (13 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
  { x: FIELD_W * (27 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
]
const A = teamFor(c, 'a', sd) as never[]
const B = teamFor(c, 'b', sd) as never[]
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
  map: { id: 'sweep', name: `${c.name} — train ${trainTier()}`, brief: '', w: FIELD_W, h: FIELD_H },
  obstacles: OB, meta: Object.fromEntries(meta), frames,
}))
console.log(`${out}: ${c.name} (${sd}) train ${trainTier()} · ${frames.length} frames, `
  + `${r.duration}s, winner ${r.winner} (${r.survivorsA}v${r.survivorsB})`)
