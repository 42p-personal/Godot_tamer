// Targeting split (Step 1): melee targets the NEAREST enemy (so a front-liner
// screens the back row); ranged/magic keep free value-and-priority choice.
import { describe, it, expect } from 'vitest'
import { generateMonster } from '../monster'
import { isMelee, pickTarget, traitsFor } from './decide'
import { simulateFieldBattle } from './engine'
import { FieldUnit, FieldSide, Vec2 } from './types'
import { Monster } from '../core'
import { ALL_MOVES } from '../moves'

// A minimal FieldUnit wrapper — only the fields pickTarget/isMelee read need to
// be real; the rest are inert defaults.
function unit(m: Monster, side: FieldSide, pos: Vec2, hp = 500, maxHp = 500): FieldUnit {
  return {
    id: `${side}${pos.x}_${pos.y}`, side, slot: 0, m, pos, deployPos: { ...pos }, comboCashes: [], comboPrimes: [], openerQueue: [], vel: { x: 0, y: 0 },
    radius: 0.9, speed: 4, hp, maxHp, mp: 100, maxMp: 100, traits: traitsFor(m),
    targetId: null, retargetIn: 0, cooldowns: {}, castingFor: 0, castMoveId: null,
    castTargetId: null, statuses: [], mods: [], forcedTargetId: null, forcedUntil: 0,
    rootedFor: 0, fadedUntil: 0, slowMult: 1, slowFor: 0, disengageFor: 0, kiteFor: 99, blockingUntil: 0, ward: 0, ccResist: 0, lastCcAt: -999, ccImmuneUntil: 0, hasAttacked: false, chaseFor: 0, chaseBest: Infinity, gaveUp: {}, fallBackAt: 0, fallBackUntil: 0, fallBackTo: null, shoveTo: null, shoveUntil: 0, dashTo: null, dashUntil: 0, escapeLockUntil: 0, dead: false,
  }
}
// ⚠️ Both PIN their loadout instead of trusting whatever chooseLoadout happens to
// draft. Reach derives from the damage moves in the kit, so a pool change can
// silently turn the "ranged" fixture melee — which is exactly what happened on
// the P4 loadout-ranking pass: grivvel drafted Power Strike + Body Slam, reach
// fell 8 -> 1.6, and `isMelee` short-circuited the very branch under test. What
// is being tested here is the reach SPLIT, so reach must be the fixture, not an
// emergent property of the current pool.
const moveNamed = (n: string) => ALL_MOVES.find((m) => m.name === n)!
const melee = (seed: string) => ({
  ...generateMonster(seed, { speciesId: 'aegisox', train: 700 }),
  loadout: [moveNamed('Power Strike')], // Duelist line -> reach ~3
}) as Monster
// ⚠️ AND NOW THE CLASS TOO, not just the loadout. `reachOf` takes the SHORTER of
// the best weapon and the class's authored free attack (CLASS_BASIC), so reach
// is no longer a property of the kit alone. grivvel derives ROGUE, whose band is
// melee 3.0 — handing it a bow made a "ranged" fixture that classified as melee,
// which is correct behaviour and a broken fixture. sylvaglide derives RANGER,
// whose band is 8.0, so the reach split is pinned by class AND kit agreeing.
//
// ⚠️ A RANGER, NOT A STALKER. pinguox is also in the ranged band but derives
// Stalker (DEX/WIS), whose traits lean support and which does not reliably pick
// the wounded back-liner — the behaviour the second test is about. Ranger
// (DEX/INT) is the archetypal ranged damage dealer, so it is the honest fixture
// for "reach past the front line", not merely the one that goes green.
const ranged = (seed: string) => ({
  ...generateMonster(seed, { speciesId: 'mantaris', train: 700 }),
  loadout: [moveNamed('Piercing Shot')], // Volley-band reach 9, Ranger band 8
}) as Monster

describe('tamerengine — targeting split', () => {
  it('classifies reach correctly (melee vs ranged)', () => {
    expect(isMelee(unit(melee('m'), 'A', { x: 5, y: 11 }))).toBe(true)
    expect(isMelee(unit(ranged('r'), 'A', { x: 5, y: 11 }))).toBe(false)
  })

  it('a melee unit attacks the NEAREST enemy, not the juicy one behind it', () => {
    // Enemy front-liner (tank, low value) is close; a squishy ranged unit (high
    // value) sits further back. A melee attacker must engage the near tank.
    const self = unit(melee('self'), 'A', { x: 10, y: 11 })
    const nearTank = unit(melee('etank'), 'B', { x: 13, y: 11 })   // 3 units away
    const backRanged = unit(ranged('emage'), 'B', { x: 22, y: 11 }) // 12 units away, high value
    const pick = pickTarget(self, [nearTank, backRanged], [])
    expect(pick?.id).toBe(nearTank.id)
  })

  it('a ranged unit is free to reach past the front line to a high-value target', () => {
    // Same board, but the attacker is ranged: it may choose the valuable back
    // unit over the nearer tank — that reach is its whole advantage.
    const self = unit(ranged('self'), 'A', { x: 10, y: 11 })
    const nearTank = unit(melee('etank'), 'B', { x: 13, y: 11 })
    const backRanged = unit(ranged('emage'), 'B', { x: 20, y: 11 }, 120, 300) // wounded + squishy
    const pick = pickTarget(self, [nearTank, backRanged], [])
    // Not forced to the nearest: it reaches the wounded high-value target.
    expect(pick?.id).toBe(backRanged.id)
  })
})

// ── FLANKING (P6) ────────────────────────────────────────────────────────────
// Outnumbered AND unsupported is what gets punished. The bonus is accuracy
// POINTS on attacks against such a defender, so it is measured through hit rate.
describe('tamerengine — flanking', () => {
  const OB: never[] = []
  // Two attackers on one lone defender vs the same two with a friend beside it.
  const run = (supported: boolean) => {
    const foe = ranged('fk-def')
    const teamB = supported ? [foe, melee('fk-friend')] : [foe]
    const r = simulateFieldBattle({
      seed: 'flank', teamA: [melee('fk-a1'), melee('fk-a2')], teamB,
      obstacles: OB,
      placeA: [{ x: 19, y: 11 }, { x: 19, y: 12 }],
      placeB: supported ? [{ x: 21, y: 11 }, { x: 21.6, y: 12 }] : [{ x: 21, y: 11 }],
    })
    const onDef = r.events.filter((e) =>
      (e.kind === 'hit' || e.kind === 'miss') && e.targetId === 'B0')
    const hits = onDef.filter((e) => e.kind === 'hit').length
    return { rate: onDef.length ? hits / onDef.length : 0, n: onDef.length }
  }
  it('a lone defender under two attackers is hit MORE often than a supported one', () => {
    const alone = run(false)
    const helped = run(true)
    expect(alone.n).toBeGreaterThan(5)   // enough swings to mean something
    expect(helped.n).toBeGreaterThan(5)
    expect(alone.rate).toBeGreaterThan(helped.rate)
  })
})
