// Spatial mechanics (v0.93) — the class of ability the turn-based engine could
// not express, because it had no space.
import { describe, it, expect } from 'vitest'
import { generateMonster } from '../monster'
import { simulateFieldBattle, isBehind, hasLineOfSight, DEFAULT_OBSTACLES } from './engine'
import { SPATIAL_MOVES, spatialOf } from './spatial'
import { ALL_MOVES } from '../moves'
import { DEFAULT_TACTICS, Monster, Move } from '../core'
import { FieldUnit } from './types'

const mk = (seed: string, over: Partial<Monster> = {}): Monster =>
  ({ ...generateMonster(seed, { train: 900 }), tactics: { ...DEFAULT_TACTICS }, ...over }) as Monster

const unit = (id: string, over: Partial<FieldUnit>): FieldUnit => ({
  id, side: 'A', slot: 0, m: mk(id), pos: { x: 10, y: 11 }, deployPos: over.pos ?? { x: 10, y: 11 }, comboCashes: [], comboPrimes: [], openerQueue: [], vel: { x: 0, y: 0 },
  radius: 0.9, speed: 3, hp: 500, maxHp: 500, mp: 60, maxMp: 60,
  traits: { cohesion: .5, predation: .5 }, targetId: null, retargetIn: 0,
  cooldowns: {}, castingFor: 0, castMoveId: null, castTargetId: null, statuses: [], mods: [], forcedTargetId: null, forcedUntil: 0,
  rootedFor: 0, fadedUntil: 0, slowMult: 1, slowFor: 0, disengageFor: 0, kiteFor: 99, blockingUntil: 0, ward: 0, ccResist: 0, lastCcAt: -999, ccImmuneUntil: 0, hasAttacked: false, chaseFor: 0, chaseBest: Infinity, gaveUp: {}, fallBackAt: 0, fallBackUntil: 0, fallBackTo: null, shoveTo: null, shoveUntil: 0, dashTo: null, dashUntil: 0, escapeLockUntil: 0, dead: false, ...over,
})

describe('the spatial table is honest', () => {
  it('only names moves that actually exist in the pool', () => {
    const pool = new Set(ALL_MOVES.map((m: Move) => m.name))
    const ghosts = Object.keys(SPATIAL_MOVES).filter((n) => !pool.has(n))
    expect(ghosts).toEqual([])
  })

  it('every entry does something', () => {
    for (const [name, sp] of Object.entries(SPATIAL_MOVES)) {
      // ⚠️ `zone`, `fade` and `haulAlly` were MISSING from this list, so an entry
      // whose whole job is placing a zone (Shield Wall) read as "declares
      // nothing". The check is meant to catch dead entries, not to enumerate a
      // stale subset of MoveSpatial — keep it in step with the type.
      const does = !!(sp.move || sp.pull || sp.push || sp.root || sp.slow || sp.backstab
        || sp.area || sp.zone || sp.fade || sp.haulAlly)
      expect(does, `${name} declares nothing`).toBe(true)
    }
  })

  it('a backstab is only ever paired with a way to GET behind', () => {
    // Otherwise the bonus is unreachable and the move is quietly weaker than
    // its numbers suggest.
    for (const [name, sp] of Object.entries(SPATIAL_MOVES)) {
      if (!sp.backstab) continue
      expect(sp.move?.to, `${name} has backstab but no way behind`).toBe('behindTarget')
    }
  })

  it('leaves the rest of the pool alone', () => {
    expect(spatialOf('Ember')).toBeUndefined()
    // Spatial behaviour is meant to be SPECIAL, not the default — this is the
    // ceiling that stops it being slapped on everything. Widened from 1/3 when
    // the movement-denial category (roots/slows for the mage and the Warden) was
    // authored as a deliberate group; it is still a real ceiling, not a rubber
    // stamp, so a pass that pushes past 40% should have to justify itself here.
    expect(Object.keys(SPATIAL_MOVES).length).toBeLessThan(ALL_MOVES.length * 0.4)
  })
})

describe('isBehind', () => {
  it('is true only when the attacker is past its target', () => {
    const t = unit('t', { side: 'B', pos: { x: 20, y: 11 } })
    expect(isBehind(unit('a', { side: 'A', pos: { x: 24, y: 11 } }), t)).toBe(true)
    expect(isBehind(unit('a', { side: 'A', pos: { x: 16, y: 11 } }), t)).toBe(false)
    // and it mirrors for the other side
    const t2 = unit('t2', { side: 'A', pos: { x: 20, y: 11 } })
    expect(isBehind(unit('b', { side: 'B', pos: { x: 16, y: 11 } }), t2)).toBe(true)
  })
})

describe('teleports beat cover, charges do not', () => {
  it('cover blocks a straight line — the premise the design rests on', () => {
    const o = DEFAULT_OBSTACLES[0]
    const a = { x: o.x - 3, y: o.y + o.h / 2 }
    const b = { x: o.x + o.w + 3, y: o.y + o.h / 2 }
    expect(hasLineOfSight(a, b, DEFAULT_OBSTACLES)).toBe(false)
  })

  it('a dash is gated on line of sight; a blink is not', () => {
    const dash = spatialOf('Power Strike')!
    const blink = spatialOf('Shadowstep')!
    expect(dash.move!.kind).toBe('dash')
    expect(blink.move!.kind).toBe('blink')
    expect(blink.backstab).toBeGreaterThan(1) // priced for it
  })
})

describe('mechanics fire in a real fight', () => {
  // Give both sides the full spatial kit so the mechanics are reachable.
  const kitted = (seed: string) => {
    const m = mk(seed)
    const names = ['Power Strike', 'Web Trap', 'Sonic Boom']
    const loadout = names.map((n) => ALL_MOVES.find((x: Move) => x.name === n)).filter(Boolean) as Move[]
    return { ...m, loadout } as Monster
  }
  const r = simulateFieldBattle({
    seed: 'spatial',
    teamA: [kitted('sa0'), kitted('sa1'), kitted('sa2')],
    teamB: [kitted('sb0'), kitted('sb1'), kitted('sb2')],
  })

  it('still terminates deterministically', () => {
    const again = simulateFieldBattle({
      seed: 'spatial',
      teamA: [kitted('sa0'), kitted('sa1'), kitted('sa2')],
      teamB: [kitted('sb0'), kitted('sb1'), kitted('sb2')],
    })
    expect(JSON.stringify(r.events)).toBe(JSON.stringify(again.events))
  })

  it('forced movement actually displaces someone', () => {
    expect(r.events.some((e) => e.kind === 'shove')).toBe(true)
  })

  it('nobody is ever displaced outside the arena or into rock', () => {
    const snaps = r.events.filter((e) => e.kind === 'snapshot') as Extract<typeof r.events[number], { kind: 'snapshot' }>[]
    for (const s of snaps) {
      for (const u of s.units) {
        expect(u.x).toBeGreaterThanOrEqual(0)
        expect(u.x).toBeLessThanOrEqual(40)
        for (const o of DEFAULT_OBSTACLES) {
          expect(u.x > o.x && u.x < o.x + o.w && u.y > o.y && u.y < o.y + o.h).toBe(false)
        }
      }
    }
  })
})

describe('area shapes replace the row targets', () => {
  it('every former row / allEnemies move now has real geometry', () => {
    // These target `frontRow` / `backRow` / `allEnemies` — formations the field
    // does not have. Without a shape they would hit everyone regardless of where
    // anyone stood, which is exactly what made spacing pointless.
    // ⚠️ The count is a TRIPWIRE for exactly that: it fired when Frost Nova and
    // Quagmire Stomp were added with no geometry (14 -> 16). Any new AoE must
    // author an `area` and bump this deliberately.
    const rowMoves = ALL_MOVES.filter((m: Move) =>
      m.target === 'allEnemies' || m.target === 'frontRow' || m.target === 'backRow')
    expect(rowMoves.length).toBe(27) // +Intimidate, +Whirlwind (STR Warcry line)
    const missing = rowMoves.filter((m: Move) => !spatialOf(m.name)?.area).map((m: Move) => m.name)
    expect(missing).toEqual([])
  })

  it('a shout radiates from the CASTER, a bombardment lands on the TARGET', () => {
    // Getting this backwards makes a support nuke its own feet.
    for (const n of ['Screech', 'Cacophony', 'Crescendo', 'Grand Mockery', 'Demoralize', "Bulwark's Challenge", 'Cleave', 'Earthshaker']) {
      expect(spatialOf(n)!.area!.centre, n).toBe('self')
    }
    for (const n of ['Rain of Arrows', 'Ricochet', 'Inferno', 'Detonate', 'World Ender']) {
      expect(spatialOf(n)!.area!.centre, n).toBe('target')
    }
  })

  it('every shape carries the dimensions its kind needs', () => {
    for (const [name, sp] of Object.entries(SPATIAL_MOVES)) {
      const a = sp.area
      if (!a) continue
      if (a.shape === 'circle') expect(a.radius, name).toBeGreaterThan(0)
      if (a.shape === 'cone') { expect(a.angle, name).toBeGreaterThan(0); expect(a.range, name).toBeGreaterThan(0) }
      if (a.shape === 'line') { expect(a.width, name).toBeGreaterThan(0); expect(a.range, name).toBeGreaterThan(0) }
    }
  })

  it('World Ender is the widest blast in the game', () => {
    const radii = Object.entries(SPATIAL_MOVES)
      .filter(([, sp]) => sp.area?.shape === 'circle')
      .map(([n, sp]) => [n, sp.area!.radius!] as const)
    const biggest = radii.reduce((a, b) => (b[1] > a[1] ? b : a))
    expect(biggest[0]).toBe('World Ender')
  })

  it('POSITION now decides who an AoE catches', () => {
    // The whole point: the same cast hits fewer monsters when they spread out.
    const clumped = simulateFieldBattle({
      seed: 'aoe', teamA: [mk('qa0'), mk('qa1'), mk('qa2')], teamB: [mk('qb0'), mk('qb1'), mk('qb2')],
      placeB: [{ x: 30, y: 11 }, { x: 31, y: 11.4 }, { x: 30.5, y: 10.6 }],
    })
    const spread = simulateFieldBattle({
      seed: 'aoe', teamA: [mk('qa0'), mk('qa1'), mk('qa2')], teamB: [mk('qb0'), mk('qb1'), mk('qb2')],
      placeB: [{ x: 30, y: 3 }, { x: 31, y: 11 }, { x: 30.5, y: 19 }],
    })
    // Different formations must produce genuinely different fights.
    expect(JSON.stringify(clumped.events)).not.toBe(JSON.stringify(spread.events))
  })
})

// ── NOTHING TELEPORTS ────────────────────────────────────────────────────────
describe('tamerengine — every displacement travels', () => {
  it('⚠️ no unit moves further in one tick than a knockback can carry it', () => {
    // ⚠️ THE TRIPWIRE FOR AN ENTIRE BUG FAMILY. `applyOnTarget` used to write
    // `target.pos = dest`, so Body Slam's `push: 3` landed three units inside
    // one 0.1s tick — 30 units/second, and the most teleport-looking thing in
    // the game. Measured on a 3v3 before the fix: 1532 ticks moved <=0.5 units
    // and nine moved 1.8-3.1 with NOTHING in between, because shoves bypassed
    // the movement step. `haulAlly` did the same.
    //
    // This does not test the shove specifically — it tests that NO mechanism
    // moves a unit faster than the fastest legal one. Any future code that
    // assigns a position directly trips it, which is the point: the bug was
    // never in one function, it was in the habit.
    // ⚠️ THIS IS A TELEPORT DETECTOR, NOT A SPEED LIMIT. The bound is deliberately
    // loose. Legal travel stacks several multipliers — unit speed
    // (2.4 + DEX/1000*3.6), DASH_SPEED_MULT, the Fall Back ramp, haste's
    // `speedMult` — and the fastest observed legal step is 1.58 units/tick. I
    // could not enumerate every combination with confidence, so rather than
    // assert a derived maximum I have not verified, the ceiling is set above the
    // fastest observed movement and below an instant reposition, and says so.
    //
    // The bug it exists for is not "slightly too fast" — it is `target.pos =
    // dest`, which put Body Slam's `push: 3` on the board in a single tick at
    // 3.0 units, nearly double this. Anything that assigns position still trips.
    //
    // ⚠️ A first version tried `max(KNOCKBACK_SPEED, MAX_SPEED * DASH_SPEED_MULT)`
    // and failed at 1.58 on legal dash movement. A tripwire that fires on correct
    // behaviour gets weakened until it fires on nothing — better an honest loose
    // bound than a tight one nobody trusts.
    const CEIL = 2.0
    for (const seed of ['tp0', 'tp1', 'tp2', 'tp3']) {
      const r = simulateFieldBattle({
        seed,
        teamA: [mk(`${seed}a0`), mk(`${seed}a1`), mk(`${seed}a2`)],
        teamB: [mk(`${seed}b0`), mk(`${seed}b1`), mk(`${seed}b2`)],
      })
      // ⚠️ A BLINK IS A TELEPORT AND IS EXEMPT, BY DESIGN. `Shadowstep` snaps, and
      // the engine emits a `blink` event on that exact tick precisely so a renderer
      // can draw the discontinuity deliberately — the constant's own comment says a
      // blink "still snaps, because that is what a teleport is". The tripwire never
      // excluded them, so it read a correct 4.15-unit Shadowstep as the very bug it
      // exists to catch (`target.pos = dest`). It only surfaced when a pool reprice
      // changed which moves that seed's monsters drafted.
      const blinked = new Set<string>()
      for (const e of r.events) {
        if (e.kind === 'blink') blinked.add(`${e.t.toFixed(1)}:${e.id}`)
      }
      const prev = new Map<string, { x: number; y: number }>()
      for (const e of r.events) {
        if (e.kind !== 'snapshot') continue
        for (const u of e.units) {
          const p = prev.get(u.id)
          if (p && !blinked.has(`${e.t.toFixed(1)}:${u.id}`)) {
            const d = Math.hypot(u.x - p.x, u.y - p.y)
            expect(
              d,
              `${u.id} moved ${d.toFixed(2)} units in one tick at t=${e.t} (seed ${seed})`,
            ).toBeLessThanOrEqual(CEIL)
          }
          prev.set(u.id, { x: u.x, y: u.y })
        }
      }
    }
  })
})
