// DOES THE LAST MONSTER STANDING RUN AWAY FOREVER?
//
// ⚠️ THE BUG THIS MEASURES, seen in a real playback: a lone survivor below its
// panic threshold retreats, is still below it next tick, retreats again — for as
// long as the clock allows. Retreat exists so a chaser "peels onto the nearest
// ally"; with no ally left there is nobody to hand off to, so it buys nothing and
// stalls the fight. And it happens at the exact moment a player is watching most
// closely, which is why it reads so badly.
//
// ⚠️ COUNTS FALLBACKS BY A UNIT THAT IS ALONE, not fallbacks in general. A team
// falling back is ordinary tactics and must not be confused with this — an
// aggregate fallback count would have shown almost no change and called the fix a
// null. The metric has to isolate the state the bug lives in.
//
// Usage: npx tsx tools/lastone.ts
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { FIELD_H, FIELD_W } from '../src/tamerengine/types'
import { COMPS, teamFor, trainTier } from './comps'
import { ALL_FIELD_MOVES, isEscapeMove } from '../src/tamerengine/fieldMoves'
import { ALL_MOVES } from '../src/moves'
import type { Monster, Move } from '../src/core'

// ⚠️ THE CARVE-OUT, ASSERTED RATHER THAN ASSUMED. Disabling the AI's automatic
// retreat must NOT disable an authored escape — a monster that spent a loadout slot
// on Disengage or Shadowstep should still use it alone. Different code path, but
// "different code path" is exactly what was believed about the two AI retreat
// mechanics, and one of those beliefs was wrong.
const ESCAPES = new Set(([...ALL_FIELD_MOVES, ...ALL_MOVES] as Move[])
  .filter(isEscapeMove).map((m) => m.name))

const OB = [
  { x: FIELD_W * (19 / 40), y: FIELD_H * (6 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (21 / 40), y: FIELD_H * (15 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (13 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
  { x: FIELD_W * (27 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
]
const SEEDS = ['s1', 's2', 's3', 's4', 'q1', 'q2', 'q3', 'q4']
const front = (m: Monster) => ({ front: m.stats.CON + m.stats.STR - m.stats.INT - m.stats.WIS })

type Ev = { t: number; kind: string; id?: string }

let loneFallbacks = 0, teamFallbacks = 0, loneSpells = 0, loneEscapeCasts = 0
let endgameTime = 0, endgames = 0, worst = 0, worstName = ''
let dur = 0, fights = 0

for (const c of COMPS) for (const sd of SEEDS) {
  const A = teamFor(c, 'a', sd), B = teamFor(c, 'b', sd)
  const r = simulateFieldBattle({
    seed: sd + c.name, teamA: A, teamB: B, obstacles: OB,
    placeA: autoDeployByRole('A', A.map(front)), placeB: autoDeployByRole('B', B.map(front)),
  })
  fights++; dur += r.duration
  const size = { A: A.length, B: B.length }
  const dead = { A: 0, B: 0 }
  // When each side FIRST dropped to a single living monster.
  const alone: Record<string, number | null> = { A: null, B: null }

  for (const e of r.events as Ev[]) {
    if (!e.id) continue
    const side = e.id[0] as 'A' | 'B'
    if (e.kind === 'death') {
      dead[side]++
      if (size[side] - dead[side] === 1 && alone[side] === null) alone[side] = e.t
    }
    if (e.kind === 'fallback') {
      // ⚠️ `>= alone` — a fallback only counts as LONE if it happened after that
      // side was reduced to one. The same unit falling back earlier, with team-mates
      // still up, is the mechanic working.
      const t0 = alone[side]
      if (t0 !== null && e.t >= t0) loneFallbacks++
      else teamFallbacks++
    }
    if (e.kind === 'cast') {
      const t0 = alone[side]
      if (t0 !== null && e.t >= t0) {
        loneSpells++
        if (ESCAPES.has((e as { move?: string }).move ?? '')) loneEscapeCasts++
      }
    }
  }
  for (const side of ['A', 'B'] as const) {
    const t0 = alone[side]
    if (t0 === null) continue
    const span = r.duration - t0
    endgames++; endgameTime += span
    if (span > worst) { worst = span; worstName = `${c.name} (${sd}) side ${side}` }
  }
}

const f = (n: number) => n.toFixed(1)
console.log(`LAST-ONE-STANDING — train ${trainTier()}, ${fights} fights, mean ${f(dur / fights)}s\n`)
console.log(`  fallbacks while ALONE        ${loneFallbacks}`)
console.log(`  fallbacks with team-mates up ${teamFallbacks}   (ordinary tactics — must NOT go to zero)`)
console.log(`  casts while alone            ${loneSpells}`)
console.log(`  ...of which ESCAPE ABILITIES ${loneEscapeCasts}   `
  + `(the carve-out — must NOT be zero)`)
console.log(`  endgames (a side reduced to 1) ${endgames}`)
console.log(`  mean time from that point to the end ${f(endgameTime / Math.max(1, endgames))}s`)
console.log(`  longest such endgame ${f(worst)}s — ${worstName}`)
console.log(`\n⚠️ `
  + `Judge on the FIRST line against the SECOND. Driving both to zero would mean\n`
  + `   retreat had been deleted, not fixed — team fallbacks are the mechanic\n`
  + `   working and are supposed to survive untouched.`)
