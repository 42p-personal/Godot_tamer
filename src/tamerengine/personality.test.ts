// Personality (v0.93) — who a monster IS. The load-bearing property is that it
// costs NO generation rng, so the 12 golden battles cannot move.
import { describe, it, expect } from 'vitest'
import { generateMonster } from '../monster'
import { basePersonality, coachedValue, panicThreshold, personalityOf, resolvePersonality } from './personality'
import { DEFAULT_TACTICS, Monster, Personality } from '../core'
import { SPECIES } from '../species'

const mk = (seed: string, over: Partial<Monster> = {}): Monster =>
  ({ ...generateMonster(seed, { train: 900 }), tactics: { ...DEFAULT_TACTICS }, ...over }) as Monster

const AXES: (keyof Personality)[] = ['aggression', 'teamplay', 'mental', 'temperament', 'awareness', 'patience']

describe('personality is derived, not rolled', () => {
  it('is stable for the same monster', () => {
    const sp = SPECIES[0]
    expect(basePersonality('abc', sp)).toEqual(basePersonality('abc', sp))
  })

  it('gives different individuals different characters', () => {
    const sp = SPECIES[0]
    const many = ['s1', 's2', 's3', 's4', 's5', 's6'].map((s) => basePersonality(s, sp))
    for (const axis of AXES) {
      expect(new Set(many.map((p) => p[axis])).size).toBeGreaterThan(1)
    }
  })

  it('stays in 0..100 across every species', () => {
    for (const sp of SPECIES) {
      for (const s of ['a', 'b', 'c']) {
        const p = basePersonality(sp.id + s, sp)
        for (const axis of AXES) {
          expect(p[axis]).toBeGreaterThanOrEqual(0)
          expect(p[axis]).toBeLessThanOrEqual(100)
        }
      }
    }
  })

  it('species have distinguishable dispositions', () => {
    // Averaged over many individuals, a species' character should show through
    // the individual variation.
    const avg = (id: string, axis: keyof Personality) => {
      const sp = SPECIES.find((s) => s.id === id)!
      const n = 40
      let sum = 0
      for (let i = 0; i < n; i++) sum += basePersonality(id + ':' + i, sp)[axis]
      return sum / n
    }
    // Tortavos: ancient tortoise, CON major. Tazzik: Tasmanian devil, DEX major.
    expect(avg('tortavos', 'mental')).toBeGreaterThan(avg('tazzik', 'mental'))
    expect(avg('tazzik', 'aggression')).toBeGreaterThan(avg('tortavos', 'aggression'))
  })

  it('applies earned drift on top of the innate block', () => {
    const m = mk('drift')
    const before = personalityOf(m)
    const after = personalityOf({ ...m, personality: { temperament: 20 } })
    expect(after.temperament).toBe(Math.min(100, before.temperament + 20))
    expect(after.aggression).toBe(before.aggression) // untouched axes stay put
  })
})

describe('coaching is gated by temperament', () => {
  it('a biddable monster obeys the order exactly', () => {
    expect(coachedValue(0.1, 0.9, 100)).toBeCloseTo(0.9)
  })

  it('a wilful monster ignores the order and plays to its nature', () => {
    expect(coachedValue(0.1, 0.9, 0)).toBeCloseTo(0.1)
  })

  it('a middling temperament lands in between', () => {
    const half = coachedValue(0.1, 0.9, 50)
    expect(half).toBeGreaterThan(0.1)
    expect(half).toBeLessThan(0.9)
  })

  it('with no order, nature applies unchanged', () => {
    expect(coachedValue(0.42, undefined, 100)).toBe(0.42)
  })

  it('THE POINT: the same order produces different behaviour on different monsters', () => {
    // Two monsters with the same innate aggression but opposite temperament,
    // both told to hold back. The biddable one complies; the wild one does not.
    const wild = { aggression: 90, teamplay: 50, mental: 50, temperament: 5 }
    const pro = { aggression: 90, teamplay: 50, mental: 50, temperament: 95 }
    const order = 0.15 // "cautious"
    const wildOut = coachedValue(wild.aggression / 100, order, wild.temperament)
    const proOut = coachedValue(pro.aggression / 100, order, pro.temperament)
    expect(wildOut).toBeGreaterThan(0.8) // still charging
    expect(proOut).toBeLessThan(0.25) // actually held back
  })
})

describe('mental decides when a monster breaks', () => {
  it('steadier monsters hold on longer', () => {
    const steady = panicThreshold({ aggression: 50, teamplay: 50, mental: 100, temperament: 50, awareness: 50, patience: 50, focus: 50 })
    const flighty = panicThreshold({ aggression: 50, teamplay: 50, mental: 0, temperament: 50, awareness: 50, patience: 50, focus: 50 })
    expect(steady).toBeLessThan(flighty)
    expect(steady).toBeGreaterThanOrEqual(0)
    expect(flighty).toBeLessThanOrEqual(0.5)
  })
})

describe('resolvePersonality feeds the field AI', () => {
  it('returns coached 0..1 values plus the raw block', () => {
    const r = resolvePersonality(mk('r1', { tactics: { ...DEFAULT_TACTICS, temperament: 'aggressive' } }))
    expect(r.aggression).toBeGreaterThanOrEqual(0)
    expect(r.aggression).toBeLessThanOrEqual(1)
    expect(r.teamplay).toBeGreaterThanOrEqual(0)
    expect(r.teamplay).toBeLessThanOrEqual(1)
    for (const axis of AXES) expect(typeof r.p[axis]).toBe('number')
  })

  it('an aggressive order raises aggression on a biddable monster', () => {
    const m = mk('r2', { personality: { temperament: 100 } })
    const calm = resolvePersonality({ ...m, tactics: { ...DEFAULT_TACTICS, temperament: 'cautious' } })
    const angry = resolvePersonality({ ...m, tactics: { ...DEFAULT_TACTICS, temperament: 'aggressive' } })
    expect(angry.aggression).toBeGreaterThan(calm.aggression)
  })
})
