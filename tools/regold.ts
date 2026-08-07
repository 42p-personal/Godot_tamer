// Print the CURRENT values of every golden, in paste-ready form.
//
// ⚠️ A RECAPTURE TOOL IS NOT PERMISSION TO RECAPTURE. A golden that moves is a
// question — "which change did that, and did I mean it?" — and this only makes
// answering it cheap once the answer is known. During the pathfinding and draft
// work every kit in the game re-drafts on most commits, so hand-editing seven
// fixtures per change was costing more attention than the fixtures were worth.
//
// Usage: npx tsx tools/regold.ts
import { simulateTeamBattle } from '../src/battle'
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { generateMonster } from '../src/monster'
import { ALL_MOVES } from '../src/moves'
import { DEFAULT_TACTICS, Monster } from '../src/core'
import { FieldEvent } from '../src/tamerengine/types'

// ── turn engine (src/battle.test.ts) ────────────────────────────────────────
const team = (seeds: string[], train: number) => seeds.map((s) => generateMonster(s, { train }))
const TURN = [
  { name: '1v1-low', a: ['gold-a1'], b: ['gold-b1'], train: 150 },
  { name: '1v1-high', a: ['gold-a2'], b: ['gold-b2'], train: 1800 },
  { name: '2v2-mid', a: ['gold-a3', 'gold-a4'], b: ['gold-b3', 'gold-b4'], train: 700 },
  { name: '3v3-high', a: ['gold-a5', 'gold-a6', 'gold-a7'], b: ['gold-b5', 'gold-b6', 'gold-b7'], train: 2000 },
]
console.log('── src/battle.test.ts ──────────────────────────────────────────')
for (const g of TURN) {
  const r = simulateTeamBattle(team(g.a, g.train), team(g.b, g.train))
  console.log(`\n  // ${g.name}`)
  console.log(`    winner: '${r.winner}', events: ${r.events.length}, logLines: ${r.log.length},`)
  console.log('    finals: [')
  for (const f of r.finals) {
    console.log(`      { side: '${f.side}', slot: ${f.slot}, hp: ${f.hp}, mana: ${f.mana}, wasKOd: ${f.wasKOd} },`)
  }
  console.log('    ],')
}

// ── field engine (src/tamerengine/golden.test.ts) ───────────────────────────
const move = (n: string) => {
  const m = ALL_MOVES.find((x) => x.name === n)
  if (!m) throw new Error(`golden references a move that no longer exists: ${n}`)
  return m
}
const mk = (seed: string, sp: string, kit: string[]): Monster => ({
  ...(generateMonster(seed, { speciesId: sp, train: 850 }) as Monster),
  loadout: kit.map(move),
  tactics: { ...DEFAULT_TACTICS },
})
const OB = [{ x: 19, y: 6, w: 2.2, h: 2.2 }, { x: 13, y: 11, w: 2, h: 2 }]
const FIELD = [
  {
    name: 'duel-melee', seed: 'g-duel',
    a: [mk('ga1', 'kongrath', ['Power Strike', 'Cleave', 'Blood Price'])],
    b: [mk('gb1', 'aegisox', ['Body Slam', 'Seize', 'Taunt'])],
    pa: [{ x: 14, y: 11 }], pb: [{ x: 26, y: 11 }],
  },
  {
    name: 'caster-vs-brawler', seed: 'g-cast',
    a: [mk('ga2', 'archmage-aleph', ['Ember', 'Cinderburst', 'Arcane Bomb'])],
    b: [mk('gb2', 'ursath', ['Power Strike', 'Headbutt', 'Cleave'])],
    pa: [{ x: 10, y: 11 }], pb: [{ x: 30, y: 11 }],
  },
  {
    name: 'trio', seed: 'g-trio',
    a: [mk('ga3', 'aegisox', ['Body Slam', 'Taunt', 'Shield Wall']),
      mk('ga4', 'kongrath', ['Power Strike', 'Cleave', 'Blood Price']),
      mk('ga5', 'strixil', ['Mend', 'Ember', 'Mind Spike'])],
    b: [mk('gb3', 'crocmaw', ['Body Slam', 'Seize', 'Taunt']),
      mk('gb4', 'grivvel', ['Ambush', 'Twin Fangs', 'Toxin Stack']),
      mk('gb5', 'maelurk', ['Ember', 'Frost Shard', 'Rime Bind'])],
    pa: [{ x: 12, y: 8 }, { x: 12, y: 11 }, { x: 8, y: 14 }],
    pb: [{ x: 28, y: 8 }, { x: 28, y: 11 }, { x: 32, y: 14 }],
  },
]
console.log('\n── src/tamerengine/golden.test.ts ──────────────────────────────')
for (const g of FIELD) {
  const r = simulateFieldBattle({
    seed: g.seed, teamA: g.a, teamB: g.b, obstacles: OB, placeA: g.pa, placeB: g.pb,
  })
  const n: Record<string, number> = {}
  for (const e of r.events as FieldEvent[]) n[e.kind] = (n[e.kind] ?? 0) + 1
  const snaps = (r.events as FieldEvent[]).filter((e) => e.kind === 'snapshot')
  const last = snaps[snaps.length - 1] as Extract<FieldEvent, { kind: 'snapshot' }>
  console.log(`\n  // ${g.name}`)
  console.log(`    winner: '${r.winner}', duration: ${r.duration}, survivors: [${r.survivorsA}, ${r.survivorsB}],`)
  console.log(`    casts: ${n.cast ?? 0}, hits: ${n.hit ?? 0}, deaths: ${n.death ?? 0}, `
    + `finalHp: [${last.units.map((u) => u.hp).join(', ')}],`)
}
