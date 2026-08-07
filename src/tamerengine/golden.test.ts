// GOLDEN FIELD BATTLES — tamerengine's own regression pins.
//
// ⚠️ WHY THESE EXIST SEPARATELY FROM `battle.test.ts`. The turn engine's four
// goldens pin `simulateTeamBattle`, an engine tamerengine replaces at M7, and
// they say nothing about the field. They are also famously twitchy: they moved
// 22 times in a single day during the ability rework, because their teams are
// built by `generateMonster` and then DRAFT their kits from the pool. Any pool
// edit re-drafts every golden team, so all four move together — a fixture that
// moves that often is a changelog, not a regression detector.
//
// ⚠️ SO THESE PIN THEIR LOADOUTS EXPLICITLY. That is the entire design decision.
// A golden should fail when the ENGINE changes, and stay silent when the POOL
// changes. Naming each move by hand decouples them from `chooseLoadout`, from
// move powers, from line affinity, and from the draft rules — all of which moved
// repeatedly today without any engine bug being involved.
//
// Everything else is pinned for the same reason: fixed seeds, fixed species,
// fixed training, fixed placement, fixed obstacles. The only free variable left
// is the simulation itself.
//
// RECAPTURED AT STAGE 1 (visibility-graph pathfinding): two of the three moved
// again. Both moved the same way — the side that has to cross the arena arrives
// sooner and healthier, because it rounds cover instead of scraping it.
//
// RECAPTURED ONCE, DELIBERATELY, at Stage 0 of docs/PATHFINDING_DESIGN.md —
// push-out at spawn, a real escape scan, and the rejection of zero-displacement
// "moves". All three moved and two flipped their winner, which is the fix
// working: units that could not get round cover now can.
//
// ⚠️ WHEN ONE OF THESE MOVES: an intentional engine change (targeting, spacing,
// mitigation, the free attack, status rules) SHOULD move them — recapture
// deliberately, in its own commit, and say which change did it. An UNEXPLAINED
// diff is a regression. `move()` throws on an unknown name, so a rename is a
// loud failure rather than a silently different fight.
// ═══════════════════════════════════════════════════════════════════════════
// ⚠️ FROZEN 2026-08-01. These values are a REGRESSION DETECTOR again, not a
// changelog.
//
// They moved roughly ten times in a single day during the ability rework and the
// balance pass — pool reprices, a cooldown unit conversion, a tactics wave, the
// 6v6 removal. A fixture that is recaptured every commit detects nothing; it just
// records what happened. The pool is stable now (141 moves, sweep 48/48), so this
// is the moment to stop.
//
// THE RULE FROM HERE:
//   1. A golden moving is a QUESTION, not a chore. Answer it before touching this
//      file — "which change did that, and did I mean it?"
//   2. If the answer is a deliberate content or engine change, recapture and write
//      the REASON on the fixture, one ⚠️ line. Every entry below already carries
//      its history; keep that unbroken.
//   3. If you cannot name the cause, DO NOT RECAPTURE. Twice today a golden moved
//      for a reason that turned out to be a real bug — a loadout picker fed the
//      wrong unit, and a free attack silently made 30% faster. Both would have
//      been papered over by a recapture, and the second was found only because a
//      plausible-sounding float explanation was tested and REFUTED.
//   4. `npx tsx tools/regold.ts` prints current values. It is a convenience for
//      step 2, never permission to skip step 1.
// ═══════════════════════════════════════════════════════════════════════════

import { describe, it, expect } from 'vitest'
import { FieldEvent } from './types'
// ⚠️ THE FIXTURES LIVE IN `goldenFixtures.ts` so `tools/exportgoldens.ts` can emit
// the same objects as the port contract. Two copies of a regression pin is how a
// port ends up passing its own test while disagreeing with the game.
import { ALL_MOVES } from '../moves'
import { GOLDENS, run, tally } from './goldenFixtures'

describe('tamerengine golden battles', () => {
  for (const g of GOLDENS) {
    it(g.name, () => {
      const r = run(g)
      const n = tally(r.events)
      const snaps = r.events.filter((e) => e.kind === 'snapshot')
      const last = snaps[snaps.length - 1] as Extract<FieldEvent, { kind: 'snapshot' }>

      expect(r.winner).toBe(g.winner)
      expect(r.duration).toBe(g.duration)
      expect([r.survivorsA, r.survivorsB]).toEqual(g.survivors)
      // Action counts catch a change in WHAT the units did even when the result
      // is unchanged — a targeting or cooldown regression that still ends 1-0.
      expect(n.cast ?? 0).toBe(g.casts)
      expect(n.hit ?? 0).toBe(g.hits)
      expect(n.death ?? 0).toBe(g.deaths)
      // Final HP is the sharpest signal: it moves on any damage-path change.
      expect(last.units.map((u) => u.hp)).toEqual(g.finalHp)
    })
  }

  it('is deterministic — the same inputs give the same fight twice', () => {
    for (const g of GOLDENS) {
      const a = run(g)
      const b = run(g)
      expect(b.winner).toBe(a.winner)
      expect(b.duration).toBe(a.duration)
      expect(b.events.length).toBe(a.events.length)
      expect(JSON.stringify(b.events)).toBe(JSON.stringify(a.events))
    }
  })

  it('pins its own loadouts — a golden must never depend on the draft', () => {
    // The guard on the guard. If someone "simplifies" these fixtures by letting
    // generateMonster draft the kits, every pool edit starts moving them again
    // and the whole point is lost.
    for (const g of GOLDENS) {
      for (const m of [...g.a, ...g.b]) {
        expect(m.loadout.length, `${g.name}: ${m.name} has no pinned loadout`).toBeGreaterThan(0)
        for (const mv of m.loadout) expect(ALL_MOVES).toContain(mv)
      }
    }
  })
})
