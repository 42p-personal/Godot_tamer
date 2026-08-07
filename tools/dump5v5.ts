// Dump a 5v5 field battle as JSON frames, for the GIF renderer in tools/gif5v5.py.
//
// The engine already emits a positional snapshot every tick (10 Hz) for exactly
// this purpose — the renderer interpolates them. Nothing here is bespoke to the
// GIF: it is the same event stream TamerArena consumes.
//
// Usage: npx tsx tools/dump5v5.ts <out.json> [seed]
import * as fs from 'fs'
import { generateMonster } from '../src/monster'
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { classForStats } from '../src/core'

const out = process.argv[2] ?? 'fight.json'
const seed = process.argv[3] ?? 'gif5'

const mk = (id: string, sp: string, train = 850) =>
  generateMonster(id, { speciesId: sp, train }) as never

// A deliberately READABLE 5v5: two front-liners, a skirmisher, and two back-line
// per side, so the formation reads on screen rather than being a scrum.
const A = ['aegisox', 'kongrath', 'grivvel', 'maelurk', 'strixil']
const B = ['ursath', 'crocmaw', 'mantevoke', 'archmage-aleph', 'larkessa']
const OBSTACLES = [
  { x: 19, y: 6, w: 2.2, h: 2.2 }, { x: 21, y: 15, w: 2.2, h: 2.2 },
  { x: 13, y: 11, w: 2, h: 2 }, { x: 27, y: 11, w: 2, h: 2 },
]

const teamA = A.map((s, i) => mk(`${seed}a${i}`, s))
const teamB = B.map((s, i) => mk(`${seed}b${i}`, s))
const front = (m: never) => {
  const st = (m as never as { stats: Record<string, number> }).stats
  return { front: st.CON + st.STR - st.INT - st.WIS }
}
const r = simulateFieldBattle({
  seed, teamA, teamB, obstacles: OBSTACLES,
  placeA: autoDeployByRole('A', teamA.map(front)),
  placeB: autoDeployByRole('B', teamB.map(front)),
})

const meta = new Map<string, { name: string; cls: string; species: string }>()
const reg = (arr: never[], side: string, sp: string[]) => arr.forEach((m, i) => {
  const mm = m as never as { name: string; stats: never }
  meta.set(side + i, { name: mm.name, cls: classForStats(mm.stats), species: sp[i] })
})
reg(teamA, 'A', A); reg(teamB, 'B', B)

interface Frame {
  t: number
  units: { id: string; x: number; y: number; hp: number; maxHp: number; state: string }[]
  casts: { id: string; move: string }[]
  hits: { id: string; targetId: string; dmg: number; crit: boolean }[]
  deaths: string[]
}
const frames: Frame[] = []
let pending = { casts: [] as Frame['casts'], hits: [] as Frame['hits'], deaths: [] as string[] }

for (const e of r.events as never as {
  t: number; kind: string; id: string; targetId: string; move: string; dmg: number; crit: boolean
  units?: { id: string; x: number; y: number; hp: number; maxHp: number; state: string }[]
}[]) {
  if (e.kind === 'cast') pending.casts.push({ id: e.id, move: e.move })
  else if (e.kind === 'hit') pending.hits.push({ id: e.id, targetId: e.targetId, dmg: e.dmg, crit: e.crit })
  else if (e.kind === 'death') pending.deaths.push(e.id)
  else if (e.kind === 'snapshot' && e.units) {
    frames.push({ t: e.t, units: e.units, ...pending })
    pending = { casts: [], hits: [], deaths: [] }
  }
}

fs.writeFileSync(out, JSON.stringify({
  seed, winner: r.winner, duration: r.duration,
  survivorsA: r.survivorsA, survivorsB: r.survivorsB,
  obstacles: OBSTACLES,
  meta: Object.fromEntries(meta),
  frames,
}))
console.log(`${out}: ${frames.length} frames, ${r.duration}s, winner ${r.winner} `
  + `(${r.survivorsA}v${r.survivorsB} standing)`)
for (const [id, m] of meta) console.log(`  ${id}  ${m.name.padEnd(10)} ${m.cls.padEnd(12)} ${m.species}`)
