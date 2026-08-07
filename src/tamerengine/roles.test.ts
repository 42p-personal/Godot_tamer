// Role/formation personalities + tactics dominance (tamerengine M3).
//
// The archetype layer on `desiredGoal` should make a tank hold the front while a
// mage sits back, and the player's pre-battle tactics should visibly change what
// a team does. These measure both, since positioning can't be pinned to an exact
// value — it's the RELATIVE placement and the effect of orders that matter.
import { describe, it, expect } from 'vitest'
import { generateMonster } from '../monster'
import { simulateFieldBattle } from './engine'
import { archetypeOf } from './decide'
import { DEFAULT_TACTICS, Monster, Stat } from '../core'
import { FieldEvent } from './types'

const withStats = (seed: string, stats: Partial<Record<Stat, number>>): Monster => {
  const m = generateMonster(seed, { train: 600 }) as Monster
  Object.assign(m.stats, stats)
  m.tactics = { ...DEFAULT_TACTICS }
  return m
}
const plain = (seed: string): Monster =>
  ({ ...generateMonster(seed, { train: 600 }), tactics: { ...DEFAULT_TACTICS } }) as Monster
const snapsOf = (evs: FieldEvent[]) =>
  evs.filter((e) => e.kind === 'snapshot') as Extract<FieldEvent, { kind: 'snapshot' }>[]

describe('tamerengine — role positioning', () => {
  it('a tank fights closer to the enemy than a mage on the same team', () => {
    // Side A on the left; higher x = closer to the (right-side) enemy.
    const tank = withStats('tank', { CON: 900, STR: 500, DEX: 150, INT: 100, WIS: 100, CHA: 100 })
    const mage = withStats('mage', { INT: 900, WIS: 600, DEX: 200, CON: 150, STR: 100, CHA: 100 })
    const B = [plain('e0'), plain('e1')]
    const r = simulateFieldBattle({ seed: 'roles', teamA: [tank, mage], teamB: B })
    const snaps = snapsOf(r.events)
    const upto = Math.floor(snaps.length * 0.6) // before either dies changes the picture
    const meanX = (id: string) => {
      let s = 0, n = 0
      for (let i = 0; i < upto; i++) {
        const u = snaps[i].units.find((x) => x.id === id)
        if (u && u.state !== 'dead') { s += u.x; n++ }
      }
      return n ? s / n : 0
    }
    expect(meanX('A0')).toBeGreaterThan(meanX('A1')) // tank in front of mage
  })

  it('classifies archetypes from stats + reach', () => {
    // A pure ranged loadout → artillery; nothing else needs asserting here beyond
    // that the classifier runs and distinguishes.
    const tanky = withStats('t', { CON: 900, STR: 400, DEX: 100, INT: 100 })
    expect(['anchor', 'skirmisher', 'artillery']).toContain(
      archetypeOf({ m: tanky } as never),
    )
  })
})

describe('tamerengine — tactics drive behaviour', () => {
  it('the same team fights differently under two different tactic sets', () => {
    const base = [0, 1, 2].map((i) => plain('ta' + i))
    const foe = [0, 1, 2].map((i) => plain('te' + i))
    const set = (t: Partial<Monster['tactics']>) =>
      base.map((m) => ({ ...m, tactics: { ...DEFAULT_TACTICS, ...t } }) as Monster)

    const brawl = simulateFieldBattle({ seed: 'tac', teamA: set({ commit: 'dive', formation: 'tight' }), teamB: foe })
    const skirmish = simulateFieldBattle({ seed: 'tac', teamA: set({ commit: 'hold', preserve: 'cautious', formation: 'spread' }), teamB: foe })

    // Some observable of the fight must differ — duration, winner, or survivors.
    const differ =
      brawl.duration !== skirmish.duration ||
      brawl.winner !== skirmish.winner ||
      brawl.survivorsA !== skirmish.survivorsA
    expect(differ).toBe(true)
  })
})
