// Battlefield geometry (v0.93). The arena's visual layer can't be asserted in
// CI, but the maths that places every combatant CAN be — and it is the part
// that has to stay in lockstep with the engine's formation rule.
import { describe, it, expect } from 'vitest'
import { fieldPostFor, FIELD_LANES } from './arena'
import { frontRowCount } from './core'

const allAlive = (n: number) => Array.from({ length: n }, (_, i) => i)

describe('fieldPostFor', () => {
  it('splits a full team into the engine\'s front/back rows', () => {
    // 3v3: frontRowCount(3) === 2, so slots 0,1 are front and slot 2 is back.
    expect(frontRowCount(3)).toBe(2)
    expect(fieldPostFor('A', 0, allAlive(3), 3).x).toBe(FIELD_LANES.frontA)
    expect(fieldPostFor('A', 1, allAlive(3), 3).x).toBe(FIELD_LANES.frontA)
    expect(fieldPostFor('A', 2, allAlive(3), 3).x).toBe(FIELD_LANES.backA)
  })

  it('mirrors side B across the field', () => {
    expect(fieldPostFor('B', 0, allAlive(3), 3).x).toBe(FIELD_LANES.frontB)
    expect(fieldPostFor('B', 2, allAlive(3), 3).x).toBe(FIELD_LANES.backB)
    // The two sides face each other rather than overlapping.
    expect(fieldPostFor('A', 0, allAlive(3), 3).x).toBeLessThan(fieldPostFor('B', 0, allAlive(3), 3).x)
  })

  it('PROMOTES the back line when a front-liner falls', () => {
    // Slot 2 starts in the back row...
    expect(fieldPostFor('A', 2, allAlive(3), 3).x).toBe(FIELD_LANES.backA)
    // ...and once slot 0 is dead, the living order is [1,2]: frontRowCount(2)
    // is 2, so slot 2 is now a FRONT-liner and walks up into the gap.
    expect(fieldPostFor('A', 2, [1, 2], 3).x).toBe(FIELD_LANES.frontA)
  })

  it('leaves a KO\'d monster on the post it died on', () => {
    // Slot 0 is dead — it must not be re-ranked into someone else's place.
    const dead = fieldPostFor('A', 0, [1, 2], 3)
    expect(dead.x).toBe(FIELD_LANES.frontA)
  })

  it('centres a lone occupant and spreads a shared row', () => {
    expect(fieldPostFor('A', 0, [0], 1).y).toBe(50)
    const a = fieldPostFor('A', 0, allAlive(2), 2).y
    const b = fieldPostFor('A', 1, allAlive(2), 2).y
    expect(a).toBeLessThan(b)
    expect((a + b) / 2).toBeCloseTo(50) // symmetric about the centre line
  })

  it('keeps every post inside the field at every team size', () => {
    for (let n = 1; n <= 6; n++) {
      for (const side of ['A', 'B'] as const) {
        for (let slot = 0; slot < n; slot++) {
          const p = fieldPostFor(side, slot, allAlive(n), n)
          expect(p.x).toBeGreaterThan(0)
          expect(p.x).toBeLessThan(100)
          expect(p.y).toBeGreaterThan(0)
          expect(p.y).toBeLessThan(100)
        }
      }
    }
  })

  it('never puts two living teammates on the same post', () => {
    for (let n = 2; n <= 6; n++) {
      const posts = allAlive(n).map((slot) => {
        const p = fieldPostFor('A', slot, allAlive(n), n)
        return `${p.x},${p.y.toFixed(2)}`
      })
      expect(new Set(posts).size).toBe(n)
    }
  })
})
