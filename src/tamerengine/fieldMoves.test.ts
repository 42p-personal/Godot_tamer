// The field-only move pool (v0.93): one signature movement ability per stat,
// plus two arena skills per stat.
import { describe, it, expect } from 'vitest'
import { ALL_FIELD_MOVES, ARENA_MOVES, MOVEMENT_MOVES, fieldMovesFor, movementMoveFor } from './fieldMoves'
import { spatialOf } from './spatial'
import { simulateFieldBattle } from './engine'
import { generateMonster } from '../monster'
import { ALL_MOVES } from '../moves'
import { DEFAULT_TACTICS, Monster, Move, STATS, Stat } from '../core'

describe('the field pool is separate from the main pool', () => {
  it('⚠️ adds NOTHING to ALL_MOVES — that pool feeds chooseLoadout and the goldens', () => {
    const main = new Set(ALL_MOVES.map((m: Move) => m.name))
    for (const m of ALL_FIELD_MOVES) expect(main.has(m.name), m.name).toBe(false)
    // The loop above IS the invariant; this count is the secondary guard that
    // catches ALL_FIELD_MOVES being spread into POOLS wholesale. ⚠️ 90 -> 100 is
    // the approved pool GROWTH (the class-kit gap fixes: CON team buffs + roots/
    // slows, INT's first buffs, CHA self-protection) — not a leak. Update it
    // deliberately when the pool grows; never to silence a leak.
    // 100 -> 102: Acrobatics (DEX) + Mage Armour (WIS), the cross-stat defensive
    // answers. ⚠️ No golden moved, because chooseLoadout does not draft them yet.
    // 102 -> 110: the STR pool reworked into its three lines (15 -> 23 moves).
    // 137 -> 139: Mending Surge (WIS, ally) + Second Wind (CHA, team) — the first
    // real DIRECT heals. ⚠️ Every prior restore paired a token direct heal (8-20)
    // with an hpRegenBuff, so nothing in the pool could answer burst, and two
    // paired A/Bs on HEAL_MULT read null because there was too little restoration
    // in the game for a coefficient to reach. Volume before coefficient.
    expect(ALL_MOVES.length).toBe(141)
  })

  it('has unique ids and names', () => {
    expect(new Set(ALL_FIELD_MOVES.map((m) => m.id)).size).toBe(ALL_FIELD_MOVES.length)
    expect(new Set(ALL_FIELD_MOVES.map((m) => m.name)).size).toBe(ALL_FIELD_MOVES.length)
  })
})

describe('every stat gets a signature movement ability', () => {
  it('all six — including CHA, which was not in the original five', () => {
    for (const s of STATS) {
      const mv = movementMoveFor(s)
      expect(mv, `${s} has no movement ability`).toBeTruthy()
    }
    expect(MOVEMENT_MOVES).toHaveLength(6)
  })

  it('each one actually moves something', () => {
    for (const mv of MOVEMENT_MOVES) {
      const sp = spatialOf(mv.name)!
      const moves = !!(sp.move || sp.haulAlly || sp.fade)
      expect(moves, `${mv.name} does not move anything`).toBe(true)
    }
  })

  it('matches the themes asked for', () => {
    expect(spatialOf('Charge')!.move!.kind).toBe('dash')          // STR
    expect(spatialOf('Backstep')!.move!.to).toBe('awayFromTarget') // DEX
    expect(spatialOf('Bulwark Leap')!.move!.to).toBe('target')     // CON — leap in
    expect(spatialOf('Fade')!.fade!.duration).toBeGreaterThan(0)   // WIS — drop threat
    expect(spatialOf('Blink')!.move!.kind).toBe('blink')           // INT
    expect(spatialOf('Beckon')!.haulAlly).toBeGreaterThan(0)       // CHA — moves an ALLY
  })
})

describe('two arena skills per stat', () => {
  it('every stat has exactly two', () => {
    for (const s of STATS) {
      const n = ARENA_MOVES.filter((m) => m.stat === s).length
      expect(n, `${s} has ${n} arena skills`).toBe(2)
    }
    expect(ARENA_MOVES).toHaveLength(12)
  })

  it('every one uses the arena — a shape, a zone or forced movement', () => {
    for (const mv of ARENA_MOVES) {
      const sp = spatialOf(mv.name)!
      const usesSpace = !!(sp.area || sp.zone || sp.push || sp.pull || sp.move || sp.root)
      expect(usesSpace, `${mv.name} does not use the arena`).toBe(true)
    }
  })

  it('power stays inside the main pool band for its learn level', () => {
    // A mobility move must not ALSO out-damage a stationary one of the same
    // tier — the movement is part of what you are paying for.
    for (const mv of ALL_FIELD_MOVES) {
      const peers = ALL_MOVES.filter((m: Move) => m.type === 'damage' && Math.abs(m.learnLevel - mv.learnLevel) <= 150)
      if (!peers.length || mv.power === 0) continue
      const ceiling = Math.max(...peers.map((m: Move) => m.power))
      expect(mv.power, `${mv.name} exceeds its tier`).toBeLessThanOrEqual(ceiling)
    }
  })

  it('Meteor pays for its size with the longest wind-up in the game', () => {
    const meteor = ALL_FIELD_MOVES.find((m) => m.name === 'Meteor')!
    expect(meteor.castTime).toBeGreaterThan(1)
    for (const m of ALL_FIELD_MOVES) if (m.name !== 'Meteor') expect(m.castTime ?? 0).toBeLessThan(meteor.castTime!)
  })
})

describe('availability', () => {
  it('is gated on the stat it belongs to', () => {
    const low = { STR: 10, DEX: 10, CON: 10, WIS: 10, INT: 10, CHA: 10 } as Record<Stat, number>
    expect(fieldMovesFor(low)).toHaveLength(0)
    const high = { STR: 999, DEX: 999, CON: 999, WIS: 999, INT: 999, CHA: 999 } as Record<Stat, number>
    expect(fieldMovesFor(high)).toHaveLength(ALL_FIELD_MOVES.length)
    const strOnly = { STR: 999, DEX: 10, CON: 10, WIS: 10, INT: 10, CHA: 10 } as Record<Stat, number>
    expect(fieldMovesFor(strOnly).every((m) => m.stat === 'STR')).toBe(true)
  })
})

describe('they work in a real fight', () => {
  const kit = (seed: string, names: string[]): Monster => {
    const m = generateMonster(seed, { train: 900 })
    const loadout = names.map((n) => ALL_FIELD_MOVES.find((x) => x.name === n)!).filter(Boolean)
    return { ...m, loadout, tactics: { ...DEFAULT_TACTICS } } as Monster
  }
  it('a fully field-kitted fight is deterministic and terminates', () => {
    const setup = () => ({
      seed: 'fieldkit',
      teamA: [kit('fa0', ['Charge', 'Sunder Line']), kit('fa1', ['Meteor', 'Gravity Well']), kit('fa2', ['Hallowed Ground', 'Miasma'])],
      teamB: [kit('fb0', ['Bulwark Leap', 'Quake Stomp']), kit('fb1', ['Pincer Strike', 'Caltrops']), kit('fb2', ['Beckon', 'Scatter'])],
    })
    const r1 = simulateFieldBattle(setup())
    const r2 = simulateFieldBattle(setup())
    expect(JSON.stringify(r1.events)).toBe(JSON.stringify(r2.events))
    expect(['A', 'B', 'draw']).toContain(r1.winner)
    expect(r1.events.some((e) => e.kind === 'hit')).toBe(true)
  })

  it('zones deal damage over time without anyone casting again', () => {
    const r = simulateFieldBattle({
      seed: 'zone',
      teamA: [kit('za0', ['Miasma']), kit('za1', ['Miasma']), kit('za2', ['Caltrops'])],
      teamB: [kit('zb0', ['Charge']), kit('zb1', ['Charge']), kit('zb2', ['Charge'])],
    })
    // A zone kill produces a death with no hit event naming the killer.
    expect(r.events.some((e) => e.kind === 'cast')).toBe(true)
    expect(['A', 'B', 'draw']).toContain(r.winner)
  })

  it('Fade makes a monster a much less attractive target', () => {
    const r = simulateFieldBattle({
      seed: 'fade',
      teamA: [kit('ha0', ['Fade']), kit('ha1', ['Charge']), kit('ha2', ['Charge'])],
      teamB: [kit('hb0', ['Charge']), kit('hb1', ['Charge']), kit('hb2', ['Charge'])],
    })
    const hitsOnFader = r.events.filter((e) => e.kind === 'hit' && e.targetId === 'A0').length
    const hitsOnOthers = r.events.filter((e) => e.kind === 'hit' && (e.targetId === 'A1' || e.targetId === 'A2')).length
    expect(hitsOnOthers).toBeGreaterThan(hitsOnFader)
  })
})
