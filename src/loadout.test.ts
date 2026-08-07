// chooseLoadout invariants, property-style across many seeds and training
// levels. The duplicate-move guard is here because the combo-priority pass
// really did ship a duplicate-loadout bug once (2026-07-25, iteration 2 of the
// auto-pick rework) — this locks the fix in permanently.
import { describe, expect, it } from 'vitest'
import { generateMonster } from './monster'

describe('chooseLoadout invariants', () => {
  const TRAINS = [0, 300, 700, 1200, 1800, 2400]

  it('never duplicates a move, never exceeds 3 slots, only equips learned moves', () => {
    for (let i = 0; i < 60; i++) {
      for (const train of TRAINS) {
        const m = generateMonster(`loadout-inv-${i}`, { train })
        expect(m.loadout.length).toBeLessThanOrEqual(3)
        const ids = m.loadout.map((mv) => mv.id)
        expect(new Set(ids).size).toBe(ids.length)
        for (const mv of m.loadout) expect(m.learned).toContain(mv)
      }
    }
  })

  it('always equips at least one damage move once any is learned', () => {
    for (let i = 0; i < 60; i++) {
      const m = generateMonster(`loadout-dmg-${i}`, { train: 900 })
      if (m.learned.some((mv) => mv.type === 'damage')) {
        expect(m.loadout.some((mv) => mv.type === 'damage')).toBe(true)
      }
    }
  })
})
