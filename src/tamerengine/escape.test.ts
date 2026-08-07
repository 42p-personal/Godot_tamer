// Tests the INSTRUMENT. What matters is that it can tell a chase that failed
// from one that never happened — the distinction no outcome metric can make.
import { describe, it, expect } from 'vitest'
import { hunts, summarise } from './escape'
import type { FieldEvent } from './types'

type U = { id: string; hp: number; targetId?: string | null }
/** Snapshots at 1s intervals; `side` is the first character of an id. */
const stream = (ticks: U[][], extra: FieldEvent[] = []): FieldEvent[] => {
  const snaps: FieldEvent[] = ticks.map((us, i) => ({
    t: i, kind: 'snapshot' as const,
    units: us.map((u) => ({
      id: u.id, x: 0, y: 0, facing: 0, state: 'idle' as const,
      targetId: u.targetId ?? null,
      hp: u.hp, maxHp: 100, mp: 0, maxMp: 0, buffs: [], debuffs: [],
    })),
  }))
  return [...snaps, ...extra].sort((a, b) => a.t - b.t)
}
const side = (id: string) => id[0]

describe('hunts', () => {
  it('records a chase that ends in a kill', () => {
    const h = hunts(stream([
      [{ id: 'A1', hp: 100, targetId: 'B1' }, { id: 'B1', hp: 100 }],
      [{ id: 'A1', hp: 100, targetId: 'B1' }, { id: 'B1', hp: 50 }],
      [{ id: 'A1', hp: 100, targetId: 'B1' }, { id: 'B1', hp: 0 }],
    ]), side)
    expect(h).toHaveLength(1)
    expect(h[0].preyId).toBe('B1')
    expect(h[0].diedAt).toBe(2)
    expect(h[0].survivedFor).toBe(2)
  })

  it('⚠️ measures from FIRST HUNTED, not from first damage', () => {
    // The pursuit phase before the first blow is exactly what cover lengthens.
    // Timing from first damage would hide the entire effect under test.
    const h = hunts(stream([
      [{ id: 'A1', hp: 100, targetId: 'B1' }, { id: 'B1', hp: 100 }], // chased, untouched
      [{ id: 'A1', hp: 100, targetId: 'B1' }, { id: 'B1', hp: 100 }],
      [{ id: 'A1', hp: 100, targetId: 'B1' }, { id: 'B1', hp: 100 }],
      [{ id: 'A1', hp: 100, targetId: 'B1' }, { id: 'B1', hp: 0 }], // first blow kills
    ]), side)
    expect(h[0].survivedFor).toBe(3) // not 0
  })

  it('leaves survivedFor null for a unit that lived', () => {
    const h = hunts(stream([
      [{ id: 'A1', hp: 100, targetId: 'B1' }, { id: 'B1', hp: 100 }],
      [{ id: 'A1', hp: 100, targetId: 'B1' }, { id: 'B1', hp: 40 }],
    ]), side)
    expect(h[0].diedAt).toBeNull()
    expect(h[0].survivedFor).toBeNull()
  })

  it('⚠️ does not count an ALLY as a hunter', () => {
    // Charm flips which side is hostile mid-fight, so the question has to be
    // asked per tick rather than assumed from the roster.
    const h = hunts(stream([
      [{ id: 'A1', hp: 100, targetId: 'A2' }, { id: 'A2', hp: 100 }],
      [{ id: 'A1', hp: 100, targetId: 'A2' }, { id: 'A2', hp: 100 }],
    ]), side)
    expect(h).toEqual([])
  })

  it('counts simultaneous hunters — a 3-on-1 dive is not one chase', () => {
    const pack = [
      { id: 'A1', hp: 100, targetId: 'B1' },
      { id: 'A2', hp: 100, targetId: 'B1' },
      { id: 'A3', hp: 100, targetId: 'B1' },
      { id: 'B1', hp: 100 },
    ]
    const h = hunts(stream([pack, pack]), side)
    expect(h[0].peakHunters).toBe(3)
  })

  it('counts give-ups as escapes', () => {
    const h = hunts(stream(
      [
        [{ id: 'A1', hp: 100, targetId: 'B1' }, { id: 'B1', hp: 100 }],
        [{ id: 'A1', hp: 100, targetId: 'B1' }, { id: 'B1', hp: 100 }],
      ],
      [{ t: 1, kind: 'giveup', id: 'A1', targetId: 'B1' }],
    ), side)
    expect(h[0].escapes).toBe(1)
  })

  it('⚠️ ignores a glance — a fraction of a second is not a chase', () => {
    const h = hunts(stream([
      [{ id: 'A1', hp: 100, targetId: 'B1' }, { id: 'B1', hp: 100 }],
    ]), side)
    expect(h).toEqual([]) // one tick, no elapsed time
  })

  it('a give-up naming an unhunted unit cannot invent a hunt', () => {
    const h = hunts(stream(
      [[{ id: 'A1', hp: 100 }, { id: 'B9', hp: 100 }]],
      [{ t: 0, kind: 'giveup', id: 'A1', targetId: 'B9' }],
    ), side)
    expect(h).toEqual([])
  })
})

describe('summarise', () => {
  it('⚠️ reports survival and duration separately — both halves of the test', () => {
    // "Cover helps" and "cover makes prey unkillable" are different findings and
    // a single number cannot carry both. A retreat that always works is the same
    // bug as one that never works.
    const died = hunts(stream([
      [{ id: 'A1', hp: 100, targetId: 'B1' }, { id: 'B1', hp: 100 }],
      [{ id: 'A1', hp: 100, targetId: 'B1' }, { id: 'B1', hp: 0 }],
    ]), side)
    const lived = hunts(stream([
      [{ id: 'A1', hp: 100, targetId: 'B2' }, { id: 'B2', hp: 100 }],
      [{ id: 'A1', hp: 100, targetId: 'B2' }, { id: 'B2', hp: 90 }],
    ]), side)
    const s = summarise([...died, ...lived])
    expect(s.hunts).toBe(2)
    expect(s.survivalRate).toBe(0.5)
    expect(s.meanSurvivedFor).toBe(1) // only the one that died contributes
  })

  it('is safe on an empty set', () => {
    expect(summarise([]).hunts).toBe(0)
  })
})
