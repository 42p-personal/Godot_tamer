// Dump a 5v5 field battle on a NAMED ARENA, for tools/gif5v5.py.
//
// Same event stream as tools/dump5v5.ts — the 10 Hz positional snapshot the
// renderer and TamerArena both consume — but it selects an arena from
// `src/tamerengine/maps.ts` first and writes the field dimensions into the JSON
// so the renderer stops assuming 40x22.
//
// ⚠️ setFieldSize BEFORE building the teams. `autoDeployByRole` reads the field
// to compute its deployment bands, so calling it against the previous size
// places both teams for the wrong arena and the fight starts with everyone in
// the wrong half.
//
// Usage: npx tsx tools/dumpmap.ts <mapId> <out.json> [seed]
import * as fs from 'fs'
import { generateMonster } from '../src/monster'
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { setFieldSize } from '../src/tamerengine/types'
import { MAPS, mapById, mapProblems } from '../src/tamerengine/maps'
import { classForStats } from '../src/core'

const mapId = process.argv[2] ?? 'dustbowl'
const out = process.argv[3] ?? 'fight.json'
const seed = process.argv[4] ?? 'gif5'
const size = Number(process.argv[5] ?? 5)

const arena = mapById(mapId)
if (!arena) {
  console.error(`unknown map "${mapId}" — have: ${MAPS.map((m) => m.id).join(', ')}`)
  process.exit(1)
}
const bad = mapProblems(arena)
if (bad.length) { console.error(bad.join('\n')); process.exit(1) }

setFieldSize(arena.w, arena.h)

const mk = (id: string, sp: string, train = 850) =>
  generateMonster(id, { speciesId: sp, train }) as never

// The same readable 5v5 as dump5v5: two front-liners, a skirmisher, two back
// line per side. Held CONSTANT across the three arenas on purpose — the teams
// are the control, the ground is the variable.
// ⚠️ Sliced, not re-picked, so a 3v3 is the FRONT of the same readable roster —
// a wall, a bruiser and a skirmisher against their opposite numbers — rather
// than a different fixture that cannot be compared with the 5v5.
const A = ['aegisox', 'kongrath', 'strixil', 'maelurk', 'grivvel'].slice(0, size)
const B = ['ursath', 'crocmaw', 'larkessa', 'archmage-aleph', 'mantevoke'].slice(0, size)

const teamA = A.map((s, i) => mk(`${seed}a${i}`, s))
const teamB = B.map((s, i) => mk(`${seed}b${i}`, s))
const front = (m: never) => {
  const st = (m as never as { stats: Record<string, number> }).stats
  return { front: st.CON + st.STR - st.INT - st.WIS }
}
const r = simulateFieldBattle({
  seed, teamA, teamB, obstacles: arena.obstacles,
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
  map: { id: arena.id, name: arena.name, brief: arena.brief, w: arena.w, h: arena.h },
  obstacles: arena.obstacles,
  meta: Object.fromEntries(meta),
  frames,
}))
console.log(`${out}: ${arena.name} ${arena.w}x${arena.h} · ${frames.length} frames, `
  + `${r.duration}s, winner ${r.winner} (${r.survivorsA}v${r.survivorsB} standing)`)
