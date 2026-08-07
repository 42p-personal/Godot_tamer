// ⚠️ THESE TEST THE INSTRUMENT, NOT THE ENGINE. The engine is known broken here
// (Titan's Rest deadlocks two units), so an assertion about engine behaviour
// would be red from the moment it was written — a broken window, not a guard.
// The variable under test at this stage is the MEASUREMENT: it has to separate a
// unit wedged against cover from one calmly standing in range, because the whole
// reason these metrics exist is that the previous ones could not.
import { describe, it, expect } from 'vitest'
import {
  DEADLOCK_FRAC, distanceToObstacle, navStats, navSummary, touchingCover,
} from './navmetrics'
import type { FieldEvent, Obstacle, UnitVisState } from './types'

/** One unit's trace as (x, y, state) triples, one per tick. */
function trace(id: string, steps: [number, number, UnitVisState][]): FieldEvent[] {
  return steps.map(([x, y, state], i) => ({
    t: i * 0.1,
    kind: 'snapshot' as const,
    units: [{
      id, x, y, facing: 0, state, targetId: null,
      hp: 100, maxHp: 100, mp: 10, maxMp: 10, buffs: [], debuffs: [],
    }],
  }))
}

const WALL: Obstacle = { x: 10, y: 10, w: 4, h: 4 }

describe('distanceToObstacle', () => {
  it('is zero inside the box', () => {
    expect(distanceToObstacle({ x: 12, y: 12 }, WALL)).toBe(0)
  })

  it('measures to the nearest FACE, not the centre', () => {
    // ⚠️ The bug this pins: a long wall's centre can be far away while the unit
    // is pressed against it. Centre-distance would report a unit scraping along
    // the Ossuary's 12-unit walls as nowhere near cover.
    const longWall: Obstacle = { x: 0, y: 10, w: 24, h: 1 }
    expect(distanceToObstacle({ x: 1, y: 10.5 }, longWall)).toBe(0)
    expect(distanceToObstacle({ x: 1, y: 12 }, longWall)).toBeCloseTo(1, 5)
  })

  it('measures diagonally past a corner', () => {
    expect(distanceToObstacle({ x: 7, y: 6 }, WALL)).toBeCloseTo(5, 5)
  })

  it('touchingCover respects the margin', () => {
    expect(touchingCover({ x: 15, y: 12 }, [WALL], 1.2)).toBe(true) // 1.0 away
    expect(touchingCover({ x: 16, y: 12 }, [WALL], 1.2)).toBe(false) // 2.0 away
  })
})

describe('navStats', () => {
  it('flags a unit that WANTS to move but cannot, and blames geometry', () => {
    const ev = trace('a', Array.from({ length: 40 }, () => [9, 12, 'move'] as [number, number, UnitVisState]))
    const [s] = navStats(ev, [WALL])
    expect(s.stuckFrac).toBe(1)
    expect(s.deadlocked).toBe(true)
    expect(s.blocked).toBe(s.stuck) // pressed against the wall the whole time
    expect(s.net).toBe(0)
  })

  it('⚠️ does NOT flag a unit standing still while casting', () => {
    // The precise false positive that made the old "frozen%" metric useless:
    // it ran at 40-86% for healthy units because casting and holding range both
    // look identical to standing in a wall.
    const ev = trace('a', Array.from({ length: 40 }, () => [9, 12, 'cast'] as [number, number, UnitVisState]))
    const [s] = navStats(ev, [WALL])
    expect(s.moveTicks).toBe(0)
    expect(s.stuck).toBe(0)
    expect(s.deadlocked).toBe(false)
  })

  it('a unit walking a straight line is clean', () => {
    const ev = trace('a', Array.from({ length: 30 },
      (_, i) => [1 + i * 0.5, 2, 'move'] as [number, number, UnitVisState]))
    const [s] = navStats(ev, [WALL])
    expect(s.stuck).toBe(0)
    expect(s.wander).toBeCloseTo(1, 2)
    expect(s.deadlocked).toBe(false)
  })

  it('scraping around cover shows up as wander, not as stuck', () => {
    // Moves the whole time — never stuck — but travels far more than it gains.
    // This is the CHRONIC failure, distinct from the catastrophic one, and the
    // two must not collapse into a single number.
    const steps: [number, number, UnitVisState][] = []
    for (let i = 0; i < 20; i++) steps.push([2 + i * 0.4, 2 + (i % 2) * 1.6, 'move'])
    const [s] = navStats(trace('a', steps), [WALL])
    expect(s.stuck).toBe(0)
    expect(s.wander).toBeGreaterThan(1.5)
  })

  it('⚠️ a never-moving unit gets finite wander, not Infinity', () => {
    // path/net with net 0 is Infinity, which sorts to the top of a "worst
    // wander" table and buries every unit with a real, finite problem.
    const ev = trace('a', Array.from({ length: 20 }, () => [9, 12, 'move'] as [number, number, UnitVisState]))
    const [s] = navStats(ev, [WALL])
    expect(Number.isFinite(s.wander)).toBe(true)
  })

  it('ignores the dead', () => {
    const ev = trace('a', Array.from({ length: 20 }, () => [9, 12, 'move'] as [number, number, UnitVisState]))
    for (const e of ev) if (e.kind === 'snapshot') e.units[0].hp = 0
    expect(navStats(ev, [WALL])).toEqual([])
  })

  it('needs enough evidence before calling a deadlock', () => {
    // Three stuck ticks is a doorway shuffle, not dead weight.
    const ev = trace('a', Array.from({ length: 4 }, () => [9, 12, 'move'] as [number, number, UnitVisState]))
    const [s] = navStats(ev, [WALL])
    expect(s.stuckFrac).toBeGreaterThanOrEqual(DEADLOCK_FRAC)
    expect(s.deadlocked).toBe(false)
  })
})

describe('navSummary', () => {
  it('separates how much is stuck from how much of that is geometry', () => {
    const stuckOnWall = navStats(
      trace('a', Array.from({ length: 40 }, () => [9, 12, 'move'] as [number, number, UnitVisState])),
      [WALL],
    )
    const stuckInTheOpen = navStats(
      trace('b', Array.from({ length: 40 }, () => [30, 30, 'move'] as [number, number, UnitVisState])),
      [WALL],
    )
    const sum = navSummary([...stuckOnWall, ...stuckInTheOpen])
    expect(sum.deadlocked).toBe(2)
    expect(sum.stuckPct).toBe(100)
    // Half the stuck ticks are next to cover — the other half are some other
    // bug, and the split is what says which one to go and fix.
    expect(sum.blockedPct).toBeCloseTo(50, 0)
  })
})
