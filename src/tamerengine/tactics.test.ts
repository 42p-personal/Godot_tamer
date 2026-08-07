// Spatial orders (v0.93) — coaching that only means anything on real ground.
// Each is gated by temperament, like every other order.
import { describe, it, expect } from 'vitest'
import { generateMonster } from '../monster'
import { ALL_MOVES } from '../moves'
import { commitLimit, desiredGoal, isMelee, pickTarget, spacingRadius } from './decide'
import { chooseMove, simulateFieldBattle, hasLineOfSight, DEFAULT_OBSTACLES } from './engine'
import { DEFAULT_TACTICS, Monster, Tactics } from '../core'
import { FIELD_W, FieldUnit } from './types'

// A perfectly biddable monster, so an order lands in full and the test is
// measuring the ORDER rather than the temperament gate.
const obedient = (over: Partial<Tactics> = {}): Partial<Monster> => ({
  personality: { temperament: 100 },
  tactics: { ...DEFAULT_TACTICS, ...over },
})
const mk = (seed: string, over: Partial<Monster> = {}): Monster =>
  ({ ...generateMonster(seed, { train: 900 }), tactics: { ...DEFAULT_TACTICS }, ...over }) as Monster

const unit = (id: string, over: Partial<FieldUnit>): FieldUnit => ({
  id, side: 'A', slot: 0, m: mk(id), pos: { x: 8, y: 11 }, deployPos: over.pos ?? { x: 8, y: 11 }, comboCashes: [], comboPrimes: [], openerQueue: [], vel: { x: 0, y: 0 },
  radius: 0.9, speed: 3, hp: 500, maxHp: 500, mp: 60, maxMp: 60,
  traits: { cohesion: .5, predation: .5 }, targetId: null, retargetIn: 0,
  cooldowns: {}, castingFor: 0, castMoveId: null, castTargetId: null, statuses: [], mods: [], forcedTargetId: null, forcedUntil: 0,
  rootedFor: 0, fadedUntil: 0, slowMult: 1, slowFor: 0, disengageFor: 0, kiteFor: 99, blockingUntil: 0, ward: 0, ccResist: 0, lastCcAt: -999, ccImmuneUntil: 0, hasAttacked: false, chaseFor: 0, chaseBest: Infinity, gaveUp: {}, fallBackAt: 0, fallBackUntil: 0, fallBackTo: null, shoveTo: null, shoveUntil: 0, dashTo: null, dashUntil: 0, escapeLockUntil: 0, dead: false, ...over,
})

describe('formation', () => {
  it('spread fans out; tight clumps up; keep takes the deployed density', () => {
    const spread = unit('sp', { m: mk('sp', obedient({ formation: 'spread' })) })
    const tight = unit('ti', { m: mk('ti', obedient({ formation: 'tight' })) })
    const keep = unit('ke', { m: mk('ke', obedient({ formation: 'keep' })) })
    expect(spacingRadius(spread)).toBeGreaterThan(spacingRadius(tight))
    expect(spacingRadius(tight)).toBeLessThan(unit('d', {}).radius * 2 + 0.01)
    // ⚠️ `keep` gets the BASE radius, not a third setting. Its density is drawn
    // on the deploy screen, so a multiplier here would be a second order fighting
    // the slot the unit is simultaneously being pulled toward.
    expect(spacingRadius(keep)).toBeCloseTo(keep.radius * 2)
  })

  it('KEEP holds the slot it deployed in; the default collapses toward the blob', () => {
    // Deployed as a wedge: this unit at the BACK, two mates ahead of it, and the
    // enemy far east — so every unit's raw goal is "advance".
    const mates = [unit('m1', { pos: { x: 12, y: 8 } }), unit('m2', { pos: { x: 12, y: 14 } })]
    const foe = unit('f', { side: 'B', pos: { x: 34, y: 11 } })
    const back = { x: 6, y: 11 }
    const slotted = unit('me', { pos: { ...back }, m: mk('me', obedient({ formation: 'keep' })) })
    const blob = unit('me', { pos: { ...back }, m: mk('me', obedient()) })
    // Its slot is behind the team's centre, so keeping it means staying back;
    // the bare cohesion pull aims at the mates themselves and drags it forward.
    expect(desiredGoal(slotted, foe, mates, [foe]).x)
      .toBeLessThan(desiredGoal(blob, foe, mates, [foe]).x)
  })

  it('KEEP still ADVANCES — the slot travels with the team, it is not a pin', () => {
    // ⚠️ THE FAILURE MODE THIS PINS. Anchoring to the literal deploy point rather
    // than to `live centroid + offset` gives a formation that never leaves the
    // start line: at a 0.55 blend nothing would ever reach the enemy and every
    // fight would run to sudden death.
    const mates = [unit('m1', { pos: { x: 20, y: 8 } }), unit('m2', { pos: { x: 20, y: 14 } })]
    const foe = unit('f', { side: 'B', pos: { x: 34, y: 11 } })
    // Deployed at x=6, but the team has since advanced to x=20 — the slot moved
    // with it, so the straggler is pulled FORWARD, not back to the spawn.
    const late = unit('me', { pos: { x: 6, y: 11 }, m: mk('me', obedient({ formation: 'keep' })) })
    expect(desiredGoal(late, foe, mates, [foe]).x).toBeGreaterThan(late.pos.x)
  })
})

describe('target priority reaches MELEE', () => {
  // ⚠️ THE BUG THIS PINS. `pickTarget` returns nearest-first for melee and used to
  // return BEFORE the scoring loop `priorityBias` lives in — so `targetPriority`
  // did nothing at all on a melee monster, which is most classes in the game. It
  // was set in the UI, set by three GAMEPLANS, and silently discarded.
  //
  // ⚠️ AND THE FIX IS BOUNDED ON PURPOSE. Melee picks by distance precisely
  // because value-chasing across open ground once had bruisers racing around the
  // map. The order buys a fixed number of world units of discount, never a seat in
  // a free-for-all score — so the last test here matters as much as the first.
  const brawler = (over: Partial<Tactics>) => unit('me', {
    pos: { x: 8, y: 11 },
    // Loadout PINNED melee: reach derives from the drafted kit, so a pool change
    // could otherwise turn this fixture ranged and skip the branch under test.
    m: {
      ...generateMonster('pri-melee', { speciesId: 'aegisox', train: 850 }),
      loadout: [ALL_MOVES.find((x) => x.name === 'Power Strike')!],
      personality: { temperament: 100 },
      tactics: { ...DEFAULT_TACTICS, ...over },
    } as Monster,
  })
  const foe = (id: string, x: number, marked = false) =>
    unit(id, { side: 'B', pos: { x, y: 11 }, m: mk(id, { marked }) })

  it('is MELEE — precondition, or the rest of this block tests nothing', () => {
    expect(isMelee(brawler({}))).toBe(true)
  })

  it('a melee monster steps past the nearer body to reach its marked target', () => {
    const near = foe('near', 12)
    const mark = foe('mark', 15, true)
    // No order: nearest wins, both at full HP so `weakest` discriminates nothing.
    expect(pickTarget(brawler({}), [near, mark], [])?.id).toBe('near')
    // Ordered to focus the mark: 3 units further away, but worth 5 units of slack.
    expect(pickTarget(brawler({ targetPriority: 'manmark' }), [near, mark], [])?.id).toBe('mark')
  })

  it('⚠️ but it does NOT cross the field for it — the discount is a LEASH', () => {
    const near = foe('near', 12)
    const far = foe('far', 30, true)
    expect(pickTarget(brawler({ targetPriority: 'manmark' }), [near, far], [])?.id).toBe('near')
  })
})

describe('comboRole — prime and detonate', () => {
  const TWIST = ALL_MOVES.find((m) => m.name === 'Twist the Knife')!   // melee, cashes bleed
  const REND = ALL_MOVES.find((m) => m.name === 'Rend')!               // melee, applies bleed
  // ⚠️ PLAIN MUST OUT-SCORE THE APPLIER AT BASELINE or the test proves nothing.
  // The first draft used Power Strike (26 power) against Rend (34) — Rend already
  // won with the order OFF, so both branches returned it and a broken bonus would
  // have passed. Whirlwind (51) loses to Rend x1.7 = 57.8 and beats it at x1.
  const PLAIN = ALL_MOVES.find((m) => m.name === 'Whirlwind')!         // melee, no rider

  const fighter = (loadout: typeof ALL_MOVES, over: Partial<Tactics>, u: Partial<FieldUnit> = {}) =>
    unit('me', {
      pos: { x: 8, y: 11 }, mp: 200, maxMp: 200, ...u,
      m: {
        ...generateMonster('combo-me', { speciesId: 'aegisox', train: 850 }),
        loadout, personality: { temperament: 100 },
        tactics: { ...DEFAULT_TACTICS, ...over },
      } as Monster,
    })
  const enemy = (id: string, x: number, bleeding = false) => unit(id, {
    side: 'B', pos: { x, y: 11 },
    statuses: bleeding ? [{ kind: 'bleed', until: 99, from: 'x', stacks: 1 } as never] : [],
  })

  it('DETONATE walks past a nearer clean target to reach a primed one', () => {
    const near = enemy('near', 12)
    const primed = enemy('primed', 15, true)
    // ⚠️ MELEE, and that is the point. `pickTarget` returns before the scoring loop
    // for melee — the bug that made `targetPriority` dead on most of the roster —
    // so the combo bias has to be applied at BOTH sites. Twist the Knife is a melee
    // detonator, so this fixture is exactly the case that would silently not work.
    const det = fighter([TWIST], { comboRole: 'detonate' }, { comboCashes: ['bleed'] })
    const off = fighter([TWIST], {}, { comboCashes: ['bleed'] })
    expect(isMelee(det)).toBe(true)
    expect(pickTarget(off, [near, primed], [])?.id).toBe('near')
    expect(pickTarget(det, [near, primed], [])?.id).toBe('primed')
  })

  it('DETONATE is still a bias, not an override — it will not cross the field', () => {
    expect(pickTarget(
      fighter([TWIST], { comboRole: 'detonate' }, { comboCashes: ['bleed'] }),
      [enemy('near', 12), enemy('far', 32, true)], [])?.id).toBe('near')
  })

  it('PRIME leads with the applier its team can cash, over a stronger plain move', () => {
    const foe = enemy('foe', 10)
    const kit = [PLAIN, REND]
    expect(chooseMove(fighter(kit, {}, { comboPrimes: ['bleed'] }), foe, [])?.name).toBe(PLAIN.name)
    expect(chooseMove(fighter(kit, { comboRole: 'prime' }, { comboPrimes: ['bleed'] }), foe, [])?.name)
      .toBe(REND.name)
  })

  it('⚠️ PRIME does NOT re-apply a status already on the target', () => {
    // Otherwise a primer spends the whole fight re-bleeding a bleeding enemy — the
    // same trap `ccPriority` had to be gated against.
    const bleeding = enemy('foe', 10, true)
    expect(chooseMove(fighter([PLAIN, REND], { comboRole: 'prime' }, { comboPrimes: ['bleed'] }),
      bleeding, [])?.name).toBe(PLAIN.name)
  })

  it('⚠️ PRIME ignores a status NOBODY on its side can cash', () => {
    // comboPrimes is the TEAM's cashable set. Applying a status no ally can collect
    // on is just a worse damage move, and the order must not make it look good.
    const foe = enemy('foe', 10)
    expect(chooseMove(fighter([PLAIN, REND], { comboRole: 'prime' }, { comboPrimes: [] }),
      foe, [])?.name).toBe(PLAIN.name)
  })
})

describe('manaPolicy — the finisher fund', () => {
  // A two-move kit with a huge cost gap: Scrap (4 MP) and Earthshaker (40 MP).
  // ⚠️ BOTH MELEE and both in range at d=3, so nothing else in `chooseMove` can
  // filter them out and the only thing under test is the mana gate.
  const CHEAP = ALL_MOVES.find((m) => m.name === 'Scrap')!
  const DEAR = ALL_MOVES.find((m) => m.name === 'Earthshaker')!
  // maxMp 40 -> reserve 12. At mp 20, Earthshaker (12.0 after FIELD_MANA_COST_MULT)
  // dips under it and Scrap (1.2) does not — the exact situation the order is about.
  const caster = (over: Partial<Tactics>) => unit('me', {
    pos: { x: 8, y: 11 }, mp: 20, maxMp: 40,
    m: {
      ...generateMonster('mana-caster', { speciesId: 'aegisox', train: 850 }),
      loadout: [CHEAP, DEAR],
      personality: { temperament: 100 },
      tactics: { ...DEFAULT_TACTICS, ...over },
    } as Monster,
  })
  const foe = (hpFrac: number) =>
    unit('foe', { side: 'B', pos: { x: 11, y: 11 }, hp: 500 * hpFrac, maxHp: 500 })

  it('CONSERVE holds the reserve while the target is healthy', () => {
    expect(chooseMove(caster({ manaPolicy: 'conserve' }), foe(1), [])?.name).toBe(CHEAP.name)
  })

  it('CONSERVE releases it on the dearest move once the target is nearly dead', () => {
    expect(chooseMove(caster({ manaPolicy: 'conserve' }), foe(0.3), [])?.name).toBe(DEAR.name)
  })

  it('BURST never holds anything back — the control', () => {
    expect(chooseMove(caster({ manaPolicy: 'burst' }), foe(1), [])?.name).toBe(DEAR.name)
  })

  it('⚠️ absent manaPolicy behaves as BURST, so no existing caller changes', () => {
    expect(chooseMove(caster({}), foe(1), [])?.name).toBe(DEAR.name)
  })

  it('⚠️ the reserve is SPENDABLE, not sacred — v1 never spent it at all', () => {
    // The first shipped version blocked ANY cast that dipped below the reserve, so
    // a conserve unit ended fights holding 30% of its pool. The finishing case
    // above is what refutes that; this pins the pair so neither can regress alone.
    const c = caster({ manaPolicy: 'conserve' })
    expect(chooseMove(c, foe(1), [])?.name).not.toBe(chooseMove(c, foe(0.3), [])?.name)
  })
})

describe('commit', () => {
  it("a 'hold' order caps how far into enemy ground a unit will go", () => {
    const holder = unit('h', { m: mk('h', obedient({ commit: 'hold' })) })
    expect(commitLimit(holder)).toBeLessThan(FIELD_W * 0.7)
  })

  it('mirrors correctly for side B', () => {
    const b = unit('hb', { side: 'B', m: mk('h', obedient({ commit: 'hold' })) })
    expect(commitLimit(b)).toBeGreaterThan(FIELD_W * 0.3)
  })

  it('⚠️ the no-order sentinel is SIDE-AWARE — a shared one pinned side B to the wall', () => {
    expect(commitLimit(unit('a', { side: 'A' }))).toBe(FIELD_W)
    expect(commitLimit(unit('b', { side: 'B' }))).toBe(0)
  })

  it("actually stops a held unit chasing across the field", () => {
    const me = unit('me', { m: mk('me', obedient({ commit: 'hold' })), pos: { x: 18, y: 11 } })
    const far = unit('far', { side: 'B', pos: { x: 38, y: 11 } })
    const goal = desiredGoal(me, far, [], [far])
    expect(goal.x).toBeLessThan(FIELD_W * 0.62)
  })
})

describe('use cover', () => {
  it('a RANGED unit runs LoS — tucks where a closing melee cannot see it', () => {
    const los = (a: { x: number; y: number }, b: { x: number; y: number }) =>
      hasLineOfSight(a, b, DEFAULT_OBSTACLES)
    const o = DEFAULT_OBSTACLES[0] // spans x 18.8-21.2, y 3.5-8.0
    const start = { x: o.x - 1.8, y: 10 }
    // Cover is a RANGED behaviour, and it breaks line from the closing MELEE
    // threat specifically (melee wants contact and never hides).
    const foe = unit('f', {
      side: 'B', pos: { x: o.x + 4, y: 10 },
      // ⚠️ The FOE is pinned melee too. Cover is triggered by a closing MELEE threat
      // specifically, so if the pool happens to hand this Tank a ranged move the
      // branch under test never runs at all.
      m: { ...generateMonster('cover-foe', { speciesId: 'aegisox', train: 700 }),
        loadout: [ALL_MOVES.find((x) => x.name === 'Power Strike')!],
        tactics: { ...DEFAULT_TACTICS } } as Monster,
    })
    expect(los(start, foe.pos)).toBe(true) // precondition: currently exposed
    const seeker = unit('m2', {
      pos: { ...start },
      // ⚠️ Loadout PINNED to a ranged move. Reach derives from the drafted damage
      // moves, so a pool change can silently turn this fixture melee — and melee
      // never hides, which short-circuits the very branch under test. Same fix as
      // targeting.test.ts. Rain of Arrows is ranged, so reach is deterministic.
      m: { ...generateMonster('cover-rg', { speciesId: 'grivvel', train: 850 }),
        loadout: [ALL_MOVES.find((x) => x.name === 'Rain of Arrows')!],
        personality: { temperament: 100 }, tactics: { ...DEFAULT_TACTICS, useCover: true } } as Monster,
    })
    // ⚠️ THE TARGET AND THE THREAT MUST BE DIFFERENT MONSTERS. This test used to
    // pass `foe` as both, then assert the seeker ended up where `foe` could not
    // see it — which, with one enemy, is the same as asserting it hides where it
    // cannot shoot. That is not cover, it is just hiding, and it was the actual
    // engine defect: cover was picked on DISTANCE to the target alone, so a unit
    // would relocate behind a rock that blocked its own line and then stand
    // there doing nothing (casters held a shot only 47% of ticks).
    // Cover means: break the DIVER's line while keeping your own on your TARGET.
    const mark = unit('mark', {
      side: 'B', pos: { x: start.x - 7, y: start.y },
      m: { ...generateMonster('cover-mark', { speciesId: 'aegisox', train: 700 }),
        loadout: [ALL_MOVES.find((x) => x.name === 'Power Strike')!],
        tactics: { ...DEFAULT_TACTICS } } as Monster,
    })
    const gSeek = desiredGoal(seeker, mark, [], [foe, mark], los)
    // THE INVARIANT: whatever stance it picks, it can still shoot what it is
    // aiming at. A position that blocks its own shot is never an improvement.
    expect(los(gSeek, mark.pos)).toBe(true)
  })

  it('is ignored by a wilful monster', () => {
    const los = (a: { x: number; y: number }, b: { x: number; y: number }) =>
      hasLineOfSight(a, b, DEFAULT_OBSTACLES)
    const o = DEFAULT_OBSTACLES[0]
    const foe = unit('f', { side: 'B', pos: { x: o.x + 5, y: 10 } })
    const start = { x: o.x - 1.8, y: 10 }
    // ⚠️ SAME seed for both, or they get different loadouts and therefore a
    // different reach — which changes the stand-off and has nothing to do with
    // cover. Only the tactics may differ.
    const wilful = unit('w', {
      pos: { ...start },
      m: mk('w', { personality: { temperament: -100 }, tactics: { ...DEFAULT_TACTICS, useCover: true } }),
    })
    const plain = unit('w', { pos: { ...start }, m: mk('w', { personality: { temperament: -100 } }) })
    expect(desiredGoal(wilful, foe, [], [foe], los)).toEqual(desiredGoal(plain, foe, [], [foe], los))
  })
})

describe('orders do not break the simulation', () => {
  it('a fully-ordered team still fights deterministically and terminates', () => {
    const team = (p: string, t: Partial<Tactics>) =>
      [0, 1, 2].map((i) => mk(p + i, obedient(t)))
    const setup = () => ({
      seed: 'orders',
      teamA: team('oa', { formation: 'keep', useCover: true, commit: 'hold' }),
      teamB: team('ob', { formation: 'tight', commit: 'dive' }),
    })
    const r1 = simulateFieldBattle(setup())
    const r2 = simulateFieldBattle(setup())
    expect(JSON.stringify(r1.events)).toBe(JSON.stringify(r2.events))
    expect(['A', 'B', 'draw']).toContain(r1.winner)
    expect(r1.events.some((e) => e.kind === 'hit')).toBe(true)
  })
})

describe('openerIds', () => {
  // ⚠️ THIS TACTIC WAS DEAD ON THE FIELD ENGINE WITH TEN UI REFERENCES BEHIND IT.
  // A player built a scripted opening and the monster ignored it, and a
  // reference-counting audit called the tactic live because battle.ts reads it.
  // The guard therefore asserts the CONSEQUENCE — what got cast — not the wiring.
  const seq = (r: { events: { kind: string; id?: string; move?: string }[] }, id: string) =>
    r.events.filter((e) => e.kind === 'cast' && e.id === id).map((e) => e.move)

  const setup = (open?: string[]) => {
    const A = [0, 1, 2].map((i) => mk('opa' + i, obedient(open ? { openerIds: open } : {})))
    return { seed: 'opener', teamA: A, teamB: [0, 1, 2].map((i) => mk('opb' + i, obedient())), A }
  }

  it('an ordered monster casts the ordered move sooner than an unordered one', () => {
    // ⚠️ THE FIXTURE MUST PIN THE VARIABLE UNDER TEST. The first version ordered
    // the LAST-LEARNED move on the theory that a capstone is the least likely
    // unscripted opener — and this seed's monster opened with it anyway, so the
    // test compared 0 against 0 and would have passed with the feature ripped out.
    // Instead: read what the unit does UNORDERED, then order it to do whatever it
    // naturally left until last. That is a real difference by construction.
    const base = setup()
    const plain = seq(simulateFieldBattle(base), 'A0')
    const late = base.A[0].loadout
      .filter((mv) => plain.indexOf(mv.name) > 0)
      .sort((a, b) => plain.indexOf(b.name) - plain.indexOf(a.name))[0]
    expect(late).toBeDefined()

    const s = setup([late.id])
    const ordered = seq(simulateFieldBattle(s), 'A0')
    expect(ordered).toContain(late.name)
    expect(ordered.indexOf(late.name)).toBeLessThan(plain.indexOf(late.name))
  })

  it('an unusable opener is abandoned, never re-tried forever', () => {
    // ⚠️ THE STALL THIS GUARDS. An id that can never fire must not park the unit:
    // it keeps acting normally while the order waits, and the whole opening is
    // dropped at OPENER_WINDOW. An id not in the loadout can never become usable.
    const s = setup(['not-a-real-move-id'])
    const r = simulateFieldBattle(s)
    expect(seq(r, 'A0').length).toBeGreaterThan(0)
    expect(r.events.some((e) => e.kind === 'hit')).toBe(true)
  })
})
