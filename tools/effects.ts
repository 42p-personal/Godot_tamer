// EFFECT REACHABILITY — which authored mechanics actually happen in a fight?
//
// ⚠️ THE FAILURE MODE THIS EXISTS FOR. Content can be authored, priced, lined,
// range-checked and validate-clean and still not exist, because one number put it
// above what anyone reaches or one radius stopped it firing. Six instances turned
// up in a single session (2026-08-01):
//
//   basicAttackFor derived its channel from the kit   Warriors shot from 6.4
//   92 moves' `range` partitioned by channel          Assassin knives reached 5.6
//   Mending Surge lv400 / Second Wind lv480           1 monster in 320 drafted one
//   Tranquility lv430                                 nobody could learn it
//   flanking's ENGAGE radius 2.6 < melee reach 3.0    fired on 2.2% of attacks
//   HEAL_MULT                                         four A/Bs, four nulls
//
// Every one was invisible to `validate.ts`, to the goldens, and to the sweep.
// They were only found by asking "does this ever actually fire?" — so that
// question gets a permanent instrument rather than a throwaway probe each time.
//
// ⚠️ WHAT THIS MEASURES, AND WHAT IT DOES NOT. It reports how often a move
// CARRYING an effect is cast. That catches the whole drafting/pricing class of
// failure. It does NOT catch an effect that is cast but then does nothing inside
// the engine (a rider whose condition never holds — flanking's radii were that
// shape, and needed engine instrumentation to find). A high cast share here means
// "reachable", not "working".
//
// Usage: npx tsx tools/effects.ts [--elite]
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { FIELD_H, FIELD_W } from '../src/tamerengine/types'
import { ALL_MOVES } from '../src/moves'
import { COMPS, teamFor, trainTier } from './comps'
import type { Move } from '../src/core'

const OB = [
  { x: FIELD_W * (19 / 40), y: FIELD_H * (6 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (21 / 40), y: FIELD_H * (15 / 22), w: 2.2, h: 2.2 },
  { x: FIELD_W * (13 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
  { x: FIELD_W * (27 / 40), y: FIELD_H * (11 / 22), w: 2, h: 2 },
]
const SEEDS = ['s1', 's2', 's3', 's4', 'q1', 'q2', 'q3', 'q4']

/** Every effect key any move authors, plus the status kinds they apply. */
function keysOf(mv: Move): string[] {
  const out: string[] = []
  for (const [k, v] of Object.entries(mv.effects ?? {})) {
    if (v === undefined || v === false || v === 0) continue
    out.push(k)
  }
  if (mv.status) out.push(`status:${mv.status.kind}`)
  return out
}

const byMove = new Map<string, string[]>()
for (const mv of ALL_MOVES) byMove.set(mv.name, keysOf(mv))

const authored = new Map<string, number>()   // moves carrying it
for (const ks of byMove.values()) for (const k of ks) authored.set(k, (authored.get(k) ?? 0) + 1)

const drafted = new Map<string, number>()    // monsters that drafted one
const cast = new Map<string, number>()       // casts of a move carrying it
let monsters = 0
let casts = 0

for (const c of COMPS) for (const sd of SEEDS) {
  const mk = (id: string, sp: string) =>
    generateMonster(id, { speciesId: sp, train: trainTier() }) as never
  const A = teamFor(c, 'a', sd) as never[]
  const B = teamFor(c, 'b', sd) as never[]
  for (const m of [...A, ...B]) {
    monsters++
    const seen = new Set<string>()
    for (const mv of (m as never as { loadout: { name: string }[] }).loadout)
      for (const k of byMove.get(mv.name) ?? []) seen.add(k)
    for (const k of seen) drafted.set(k, (drafted.get(k) ?? 0) + 1)
  }
  const fr = (m: never) => {
    const st = (m as never as { stats: Record<string, number> }).stats
    return { front: st.CON + st.STR - st.INT - st.WIS }
  }
  const r = simulateFieldBattle({ seed: sd + c.name, teamA: A, teamB: B, obstacles: OB,
    placeA: autoDeployByRole('A', A.map(fr)), placeB: autoDeployByRole('B', B.map(fr)) })
  for (const e of r.events as never as { kind: string; move: string }[]) {
    if (e.kind !== 'cast') continue
    casts++
    for (const k of byMove.get(e.move) ?? []) cast.set(k, (cast.get(k) ?? 0) + 1)
  }
}

const rows = [...authored.keys()].map((k) => ({
  k,
  moves: authored.get(k) ?? 0,
  draft: drafted.get(k) ?? 0,
  casts: cast.get(k) ?? 0,
  share: (cast.get(k) ?? 0) / Math.max(1, casts),
})).sort((a, b) => a.share - b.share)

console.log(`EFFECT REACHABILITY — train ${trainTier()}, ${COMPS.length * SEEDS.length} fights, `
  + `${monsters} monsters, ${casts} casts\n`)
console.log('effect                    moves   drafted/     casts   % of casts')
for (const r of rows) {
  // ⚠️ The flag is the POINT of the tool. 1% is where the isolation term and
  // flanking both sat, and both turned out to be doing nothing at all.
  const flag = r.casts === 0 ? '  ← NEVER CAST' : r.share < 0.01 ? '  ← under 1%' : ''
  console.log(`  ${r.k.padEnd(24)}${String(r.moves).padStart(4)}`
    + `${(r.draft + '/' + monsters).padStart(12)}${String(r.casts).padStart(10)}`
    + `${(100 * r.share).toFixed(2).padStart(9)}%${flag}`)
}
const dead = rows.filter((r) => r.casts === 0)
console.log(`\n${dead.length} of ${rows.length} effects are NEVER CAST at this tier`
  + (dead.length ? `: ${dead.map((r) => r.k).join(', ')}` : ''))
