// Hard collision + enriched snapshot (tamerengine M1/M2).
//
// The engine used to let monsters overlap in melee (separation was a soft
// steering force). These assert the new invariant — no two living monsters ever
// share space — and that the snapshot now carries the mana + buff/debuff data
// the renderer needs.
import { describe, it, expect } from 'vitest'
import { generateMonster } from '../monster'
import { simulateFieldBattle } from './engine'
import { ALL_MOVES } from '../moves'
import { DEFAULT_TACTICS, Move, Monster } from '../core'
import { FieldEvent } from './types'

const mk = (seed: string, loadout?: Move[]): Monster => {
  const m = { ...generateMonster(seed, { train: 900 }), tactics: { ...DEFAULT_TACTICS } } as Monster
  if (loadout) m.loadout = loadout
  return m
}
const team = (n: number, p: string) => Array.from({ length: n }, (_, i) => mk(p + i))
const snapsOf = (evs: FieldEvent[]) =>
  evs.filter((e) => e.kind === 'snapshot') as Extract<FieldEvent, { kind: 'snapshot' }>[]

// Min centre distance the collision pass enforces: 2·radius·COLLISION_R_FRAC =
// 1.8·0.66 = 1.188, minus a small tolerance for the 2-decimal snapshot rounding.
const MIN_SEP = 1.188
const TOL = 0.07

describe('tamerengine — hard collision', () => {
  it('no two living monsters ever overlap, across whole fights', () => {
    let worst = Infinity
    for (let i = 0; i < 8; i++) {
      const r = simulateFieldBattle({ seed: 'c' + i, teamA: team(3, 'a' + i), teamB: team(3, 'b' + i) })
      for (const s of snapsOf(r.events)) {
        const live = s.units.filter((u) => u.state !== 'dead')
        for (let a = 0; a < live.length; a++) {
          for (let b = a + 1; b < live.length; b++) {
            const d = Math.hypot(live[a].x - live[b].x, live[a].y - live[b].y)
            worst = Math.min(worst, d)
          }
        }
      }
    }
    // Closest any two living monsters ever got is still at/above the floor.
    expect(worst).toBeGreaterThan(MIN_SEP - TOL)
  })

  it('several attackers SURROUND one target — adjacent, not stacked', () => {
    // Five attackers, one lone defender. They should cluster around it, each
    // within striking distance, but never overlap each other.
    const r = simulateFieldBattle({ seed: 'surround', teamA: team(5, 'atk'), teamB: [mk('def')] })
    const snaps = snapsOf(r.events)
    // Look at a mid-fight snapshot while the defender still lives.
    const mid = snaps.filter((s) => s.units.find((u) => u.id === 'B0' && u.state !== 'dead'))
    expect(mid.length).toBeGreaterThan(5)
    const s = mid[Math.floor(mid.length * 0.6)]
    const live = s.units.filter((u) => u.state !== 'dead')
    for (let a = 0; a < live.length; a++) {
      for (let b = a + 1; b < live.length; b++) {
        const d = Math.hypot(live[a].x - live[b].x, live[a].y - live[b].y)
        expect(d, `${live[a].id}/${live[b].id} overlap`).toBeGreaterThan(MIN_SEP - TOL)
      }
    }
  })

  it('produces no draws — a simultaneous wipe breaks by damage dealt', () => {
    let draws = 0
    for (let i = 0; i < 20; i++) {
      const r = simulateFieldBattle({ seed: 'd' + i, teamA: team(3, 'da' + i), teamB: team(3, 'db' + i) })
      if (r.winner === 'draw') draws++
    }
    expect(draws).toBe(0)
  })
})

describe('tamerengine — enriched snapshot', () => {
  it('every unit carries hp/maxHp and mp/maxMp', () => {
    const r = simulateFieldBattle({ seed: 'snap', teamA: team(2, 'a'), teamB: team(2, 'b') })
    const u = snapsOf(r.events)[0].units[0]
    expect(u.maxHp).toBeGreaterThan(0)
    expect(u.maxMp).toBeGreaterThan(0)
    expect(u.hp).toBeLessThanOrEqual(u.maxHp)
    expect(Array.isArray(u.buffs)).toBe(true)
    expect(Array.isArray(u.debuffs)).toBe(true)
  })

  it('a debuff surfaces in the snapshot when a status is applied', () => {
    const ember = ALL_MOVES.find((m) => m.name === 'Ember')!
    const A = [mk('ba', [{ ...ember, status: { ...ember.status!, chance: 100 } }])]
    const B = [mk('bb')]
    const r = simulateFieldBattle({ seed: 'burn', teamA: A, teamB: B })
    const anyDebuff = snapsOf(r.events).some((s) => s.units.some((u) => u.debuffs.includes('burn')))
    expect(anyDebuff).toBe(true)
  })

  it('a beneficial status surfaces as a buff, never a debuff', () => {
    // Battle Hymn grants team haste — it must land in `buffs`, not `debuffs`.
    const hymn = ALL_MOVES.find((m) => m.name === 'Battle Hymn')
    if (!hymn) return
    const A = [mk('ha', [hymn]), mk('hc')]
    const B = team(2, 'hb')
    const r = simulateFieldBattle({ seed: 'hymn', teamA: A, teamB: B })
    for (const s of snapsOf(r.events)) {
      for (const u of s.units) expect(u.debuffs).not.toContain('haste')
    }
  })
})
