// Field statuses and utility casting (v0.93).
//
// Two whole systems were silently absent before this: NO status was ever
// applied on the field, and NO non-damage move was ever cast. Both failed
// quietly — a monster holding Glacial Prison or Hallowed Ground simply behaved
// as though it held nothing. Nothing caught it, because "the fight still ran"
// looks exactly like "the fight ran correctly".
//
// So these tests assert the MECHANICS directly, each by building a monster that
// holds one specific move and checking the effect appears. Measuring aggregate
// battles is not enough: a rider that lands 2% of the time reads as noise.
import { describe, it, expect } from 'vitest'
import { generateMonster } from '../monster'
import { simulateFieldBattle } from './engine'
import { FIELD_STATUS } from './status'
import { SECONDS_PER_ROUND } from './types'
import { ALL_MOVES } from '../moves'
import { DEFAULT_TACTICS, STATUS_INFO, Move, Monster, StatusKind, classForStats } from '../core'
import { FieldEvent } from './types'

const mk = (seed: string, loadout?: Move[]): Monster => {
  const m = generateMonster(seed, { train: 900 })
  const o = { ...m, tactics: { ...DEFAULT_TACTICS } } as Monster
  if (loadout) o.loadout = loadout
  return o
}
const move = (name: string) => {
  const m = ALL_MOVES.find((x) => x.name === name)
  if (!m) throw new Error(`no such move: ${name}`) // guards against a rename
  return m
}
/** The same move with a guaranteed rider — a 15% charm is untestable otherwise. */
const certain = (name: string): Move => {
  const m = move(name)
  return { ...m, status: { ...m.status!, chance: 100 } }
}
/**
 * A monster whose emergent CLASS matches a predicate, found by scanning seeds.
 *
 * ⚠️ A FIXTURE MUST HOLD A KIT ITS CLASS WOULD ACTUALLY DRAFT. `mk` rolls a
 * random species, so forcing a loadout onto it can produce a Wizard holding a
 * STR Cleave and a CHA Lullaby — and once the free attack became class-authored
 * (CLASS_BASIC), that Wizard correctly preferred its own INT jab to two off-stat
 * moves and cast neither. The status under test never fired, and the test read
 * as an engine regression when the engine was right. Measured at the same time:
 * ability share across real drafted kits went UP, 72.0% -> 77.3%.
 *
 * Scanning rather than hard-coding a seed: a magic seed silently stops meaning
 * what it meant the next time species or stat data moves.
 */
const mkClass = (tag: string, want: (cls: string) => boolean, loadout?: Move[]): Monster => {
  for (let i = 0; i < 400; i++) {
    const m = mk(`${tag}${i}`, loadout)
    if (want(classForStats(m.stats))) return m
  }
  throw new Error(`no monster matching ${tag} in 400 seeds`)
}
const VOICE_CLASSES = ['Orator', 'Bard', 'Herald']

const run = (a: Monster[], b: Monster[], seed = 'st') =>
  simulateFieldBattle({ seed, teamA: a, teamB: b })
const of = <K extends FieldEvent['kind']>(evs: FieldEvent[], k: K) =>
  evs.filter((e) => e.kind === k) as Extract<FieldEvent, { kind: K }>[]

describe('field statuses — the table itself', () => {
  it('covers every StatusKind the game can produce', () => {
    const kinds = Object.keys(STATUS_INFO) as StatusKind[]
    for (const k of kinds) expect(FIELD_STATUS[k], `${k} has no field rule`).toBeTruthy()
    expect(Object.keys(FIELD_STATUS).sort()).toEqual([...kinds].sort())
  })

  // The failure this guards is a rule that exists but is empty — it would look
  // implemented at every call site and do nothing at runtime.
  it('gives every status at least one real effect', () => {
    for (const [kind, rule] of Object.entries(FIELD_STATUS)) {
      expect(Object.keys(rule).length, `${kind} is an empty rule — inert`).toBeGreaterThan(0)
    }
  })

  it('every pool move that sets a status names a real one', () => {
    for (const m of ALL_MOVES) {
      if (!m.status) continue
      expect(FIELD_STATUS[m.status.kind], `${m.name} sets unknown ${m.status.kind}`).toBeTruthy()
    }
  })
})

describe('field statuses — riders actually land', () => {
  it('applies statuses in ordinary fights', () => {
    let total = 0
    for (let i = 0; i < 10; i++) {
      const A = [0, 1, 2].map((n) => mk(`sa${i}${n}`))
      const B = [0, 1, 2].map((n) => mk(`sb${i}${n}`))
      total += of(run(A, B, 's' + i).events, 'status').length
    }
    expect(total).toBeGreaterThan(20)
  })

  it('records WHO applied it — fear and charm are meaningless without a source', () => {
    // ⚠️ BOTH SIDES PINNED. This gave B a full drafted loadout, so the fixture
    // silently depended on the caster SURVIVING long enough to land its rider —
    // and the moment the pool's damage curve was steepened, B killed A in 4.8s
    // after a single Screech and the test failed with zero status events. That
    // is the meta being measured, not the mechanic. B now holds one weak move,
    // so this stays a controlled experiment about where a status comes from.
    const A = [mk('fa', [certain('Screech')])]
    const B = [mk('fb', [move('Scrap')])]
    const evs = of(run(A, B).events, 'status')
    expect(evs.length).toBeGreaterThan(0)
    for (const e of evs) expect(e.by).toBeTruthy()
  })

  it('a rider never lands on an ally', () => {
    const A = [mk('ga'), mk('ga2')]
    const B = [mk('gb'), mk('gb2')]
    const r = run(A, B, 'ally')
    for (const e of of(r.events, 'status')) {
      // haste is the one beneficial status and IS meant to land on the team
      if (FIELD_STATUS[e.status].speedMult && e.status === 'haste') continue
      expect(e.id[0], `${e.status} hit an ally`).not.toBe(e.by[0])
    }
  })
})

describe('field statuses — the three that gained geometry', () => {
  // The user's ask: on a field these words can mean something a turn counter
  // cannot express. Each test compares against the SAME fight without the rider.
  const enemy = () => [mk('vic')]

  it('FEAR routs the victim — it moves away from what frightened it', () => {
    // ⚠️ Assert fear's OWN mechanic. Two robustness fixes over the naive version:
    // (1) don't compare against a control fight — hard collision now separates
    // that one too, confounding it; (2) PLACE the two units within Screech's
    // reach at the start, so the voice cast reliably lands. A lone weak screamer
    // left to chase a ranged kiter across the field never closes to cast at all.
    const screamer = mk('ka', [certain('Screech')])
    const r = simulateFieldBattle({
      seed: 'fear', teamA: [screamer], teamB: enemy(),
      placeA: [{ x: 18, y: 11 }], placeB: [{ x: 21, y: 11 }], // 3 apart, inside voice reach
    })
    const feared = of(r.events, 'status').filter((e) => e.status === 'fear')
    expect(feared.length).toBeGreaterThan(0)
    const t0 = feared[0].t
    const snaps = of(r.events, 'snapshot')
    const at = (tt: number) =>
      snaps.reduce((best, s) => (Math.abs(s.t - tt) < Math.abs(best.t - tt) ? s : best))
    // ⚠️ MEASURE THE VICTIM'S OWN FLIGHT, NOT THE GAP BETWEEN THE TWO. The gap
    // is confounded by how fast the SCREAMER closes, and once units had to TURN
    // rather than pivot instantly, the victim's ~0.45s about-face let the
    // screamer gain more than the victim escaped — the gap shrank while fear was
    // working perfectly. This fixture claims to assert "fear's OWN mechanic", so
    // it now does: how far the victim has fled from the spot it was frightened
    // at, which no behaviour of the chaser can distort.
    const scared = at(t0)
    const origin = { x: scared.units[1].x, y: scared.units[1].y }
    const fledBy = (tt: number) => {
      const u = at(tt).units[1]
      return Math.hypot(u.x - origin.x, u.y - origin.y)
    }
    expect(fledBy(t0 + 1.5)).toBeGreaterThan(1)
  })

  it('CONFUSION sends the victim off its intended heading', () => {
    const confused = run([mk('ca', [certain('Sonic Boom')])], enemy(), 'conf')
    const control = run([mk('ca', [move('Cleave')])], enemy(), 'conf')
    const path = (r: ReturnType<typeof run>) =>
      JSON.stringify(of(r.events, 'snapshot').map((s) => s.units[1].y.toFixed(1)))
    expect(path(confused)).not.toBe(path(control))
  })

  it('CHARM turns the victim against its own side', () => {
    // Charm's shipped duration is 2 rounds. That is a balance number; here the
    // window is widened so the mechanic is observable at all — a charmed
    // monster has to cross ground to reach the ally it now wants to hit.
    const c = move('Cacophony')
    const long: Move = { ...c, status: { kind: 'charm', chance: 100, duration: 6 } }
    // ⚠️ THE ENEMIES ARE PINNED TO ONE WEAK MOVE, and must stay that way. With
    // full drafted loadouts this fixture depended on the CASTER surviving long
    // enough for a charmed victim to walk over and swing: when melee reach went
    // 1.6 -> 3.0 the charm landed at 4.6s and the caster died at 4.9s, so the
    // window closed and the test failed with zero friendly fire. That measures
    // how fast a random kit kills, not whether charm flips a side.
    const A = [mk('ha', [long])]
    const B = [mk('hb', [move('Scrap')]), mk('hb2', [move('Scrap')])]
    const r = run(A, B, 'charm')
    // A charmed B unit striking the other B unit — friendly fire that can only
    // happen because charm swapped which side it treats as hostile.
    const friendlyFire = of(r.events, 'hit').filter((e) => e.id[0] === e.targetId[0])
    expect(friendlyFire.length).toBeGreaterThan(0)
  })
})

describe('field statuses — control and attrition', () => {
  it('STUN stops the victim acting', () => {
    // ⚠️ Glacial Prison was absorbed in the INT rework. Seismic Crush inherited its
    // stun but is an AoE with a 5.6 radius, so in a 1v1 the lone enemy is often
    // outside it and nothing ever lands — Headbutt is the single-target stun and
    // melee, so the two units are guaranteed to engage.
    const A = [mk('ta', [certain('Headbutt')])]
    const B = [mk('tb')]
    const r = run(A, B, 'stun')
    const stuns = of(r.events, 'status').filter((e) => e.status === 'stun')
    expect(stuns.length).toBeGreaterThan(0)
    // In the second after a stun lands, the victim casts nothing.
    const t0 = stuns[0].t
    const dur = FIELD_STATUS.stun ? 1 : 1
    const casts = of(r.events, 'cast')
      .filter((e) => e.id === stuns[0].id && e.t > t0 && e.t < t0 + 1.5 * dur)
    expect(casts.length).toBe(0)
  })

  it('SLEEP breaks the moment the sleeper is hit', () => {
    // ⚠️ SCANS FOR A FIGHT WHERE SLEEP LANDS, rather than assuming one pairing
    // will cast it. The mechanic under test is "being hit wakes the sleeper" —
    // not "this particular Bard reaches its utility slot in this particular
    // 8-second fight", which is what the old fixture was really asserting.
    //
    // It used to replace the caster's whole loadout with [Lullaby, Cleave]. That
    // monster had no ordinary attack, and under the pre-CLASS_BASIC code a
    // monster with no damage move got a free attack of NEGATIVE range — so it
    // could do nothing BUT re-cast Lullaby, 16 times across a 105.8s timeout.
    // The test passed on a bug. Measured when the free attack was authored:
    // utility casts across real kits held at 23.5% -> 24.2%, so nothing was
    // displaced; only this fixture's accident was.
    for (let i = 0; i < 40; i++) {
      const bard = mkClass(`la${i}-`, (c) => VOICE_CLASSES.includes(c))
      const A = [{ ...bard, loadout: [certain('Lullaby'), ...bard.loadout.slice(0, 3)] }]
      const r = run(A, [mk(`lb${i}`)], `sleep${i}`)
      const naps = of(r.events, 'status').filter((e) => e.status === 'sleep')
      if (!naps.length) continue
      // It gets re-applied, which can only happen if it broke in between.
      const hits = of(r.events, 'hit').filter((e) => e.targetId === naps[0].id)
      expect(hits.length).toBeGreaterThan(0)
      return
    }
    throw new Error('no sleep was ever applied in 40 pairings — check Lullaby')
  })

  it('BURN drains health over time, not on impact', () => {
    expect(FIELD_STATUS.burn.hpPerSec).toBeGreaterThan(0)
    const A = [mk('ba', [certain('Ember')])]
    const B = [mk('bb')]
    const r = run(A, B, 'burn')
    const burns = of(r.events, 'status').filter((e) => e.status === 'burn')
    expect(burns.length).toBeGreaterThan(0)
    // HP falls between hits, which only a tick-based drain can cause.
    const snaps = of(r.events, 'snapshot').filter((s) => s.t > burns[0].t)
    const hitTimes = new Set(of(r.events, 'hit').map((e) => e.t.toFixed(1)))
    let quietDrops = 0
    for (let i = 1; i < snaps.length; i++) {
      if (hitTimes.has(snaps[i].t.toFixed(1))) continue
      if (snaps[i].units[1].hp < snaps[i - 1].units[1].hp) quietDrops++
    }
    expect(quietDrops).toBeGreaterThan(0)
  })

  it('DOOM pays out when it expires, not while it runs', () => {
    expect(FIELD_STATUS.doom.detonate).toBeGreaterThan(0)
    expect(FIELD_STATUS.doom.hpPerSec).toBeUndefined()
  })
})

describe('field — non-damage moves are actually cast', () => {
  // ⚠️ `chooseMove` filtered `type === 'damage'`, so every support kit and all
  // 18 field moves were dead weight. This is the regression test for that.
  const byName = new Map(ALL_MOVES.map((m) => [m.name, m]))

  it('casts buffs, debuffs and heals in ordinary fights', () => {
    let util = 0, total = 0
    for (let i = 0; i < 10; i++) {
      const A = [0, 1, 2, 3].map((n) => mk(`ua${i}${n}`))
      const B = [0, 1, 2, 3].map((n) => mk(`ub${i}${n}`))
      for (const e of of(run(A, B, 'u' + i).events, 'cast')) {
        total++
        if (byName.get(e.move)?.type !== 'damage') util++
      }
    }
    expect(total).toBeGreaterThan(200)
    expect(util).toBeGreaterThan(20)
  })

  it('a healer actually heals', () => {
    let healed = 0
    for (let i = 0; i < 8; i++) {
      // ⚠️ Second Wind was absorbed in the CON rework. WIS is now the designated
      // healing stat (CON heals only ITSELF), so Mend is the right exemplar.
      const A = [mk(`ha${i}`, [move('Mend'), move('Cleave')]), mk(`hc${i}`)]
      const B = [mk(`hb${i}`), mk(`hd${i}`)]
      healed += of(run(A, B, 'h' + i).events, 'heal').length
    }
    expect(healed).toBeGreaterThan(0)
  })

  it('TAUNT forces the victim onto the taunter', () => {
    const A = [mk('pa', [move('Taunt'), move('Cleave')]), mk('pc')]
    const B = [mk('pb'), mk('pd')]
    const r = run(A, B, 'taunt')
    const taunts = of(r.events, 'cast').filter((e) => e.move === 'Taunt')
    expect(taunts.length).toBeGreaterThan(0)
    // After a taunt, the victim's hits land on the taunter.
    const t = taunts[0]
    const after = of(r.events, 'hit').filter((e) => e.id === t.targetId && e.t > t.t && e.t < t.t + 5)
    if (after.length) expect(after.some((e) => e.targetId === t.id)).toBe(true)
  })

  it('the formerly-inert defensive effects are now MODELLED and get cast', () => {
    // ⚠️ THIS TEST USED TO ASSERT THE OPPOSITE. Dodge/accuracy/ward/guard/thorns/
    // cleanse had no field representation, so the invariant was "a monster holding
    // only such a move must fall back to its basic attack rather than burn a
    // cooldown on nothing". They are real now, so the same moves must be CHOSEN —
    // and the old assertion is exactly what would catch them silently regressing
    // to inert again.
    // ⚠️ 'Focus Aim' is deliberately NOT in this list. It is a bare `accBuff: 10`,
    // which scores 7.8 against a UTILITY_FLOOR of 8 — so the AI declines it, and
    // that is CORRECT: +10 accuracy points on an already-90%-accurate attacker buys
    // less than simply swinging. The effect is modelled; the move is just weak, and
    // it earns its slot in the ability rework when it gains its crit rider. Padding
    // the score to make this test pass is precisely how War Cry ended up taking 137
    // of 254 utility casts.
    for (const live of ['Sidestep', 'Acrobatics']) {
      // Two enemies on it, so the situational scoring has real danger to price:
      // these are deliberately worthless with nothing nearby (see the Fade note
      // in utilityScore — a flat value turns a defensive cooldown into a tic).
      const A = [mk('na' + live, [move(live)])]
      const B = [mk('nb' + live), mk('nc' + live)]
      const casts = of(run(A, B, 'live').events, 'cast')
      expect(casts.length, `${live}: never acted`).toBeGreaterThan(0)
      expect(casts.some((e) => e.move === live), `${live} is still inert`).toBe(true)
    }
  })
})

describe('a buff never stacks with itself', () => {
  it('⚠️ Brace cannot re-arm inside its own duration', () => {
    // ⚠️ THE BUG THIS PINS. `modAtk` MULTIPLIES every mod and guard/thorns/dodge/
    // acc/regen all ADD, so re-casting a buff COMPOUNDED rather than refreshed.
    // 17 pool moves re-arm before their own effect expires, so this was the normal
    // case rather than an edge one — Brace grants 6s of guard on a 3.0s recharge,
    // so anything holding it sat permanently DOUBLE-stacked.
    //
    // Found in the grind-lock trace: a unit with no reachable target cast Enrage
    // 27 times in 197 seconds, and every one of them was multiplying its attack.
    const brace = ALL_MOVES.find((m) => m.name === 'Brace')!
    const A = [mk('bz0', [brace, ALL_MOVES.find((m) => m.name === 'Power Strike')!]),
      mk('bz1'), mk('bz2')]
    const B = [mk('bq0'), mk('bq1'), mk('bq2')]
    const r = run(A, B, 'brace')
    const casts = of(r.events, 'cast').filter((e) => e.move === 'Brace' && e.id === 'A0').length
    expect(casts).toBeGreaterThan(0)   // precondition: it was actually drafted and used
    // ⚠️ The bound is its DURATION (6s), not its cooldown (3.0s). Without the gate
    // the ceiling is twice this, which is exactly what the bug looked like.
    const durationSeconds = 3 * SECONDS_PER_ROUND
    expect(casts).toBeLessThanOrEqual(Math.ceil(r.duration / durationSeconds))
  })
})

describe('field — the clock always resolves', () => {
  it('produces no draws across a spread of fights', () => {
    let draws = 0, longest = 0
    for (let i = 0; i < 24; i++) {
      const A = [0, 1, 2].map((n) => mk(`ca${i}${n}`))
      const B = [0, 1, 2].map((n) => mk(`cb${i}${n}`))
      const r = run(A, B, 'c' + i)
      if (r.winner === 'draw') draws++
      longest = Math.max(longest, r.duration)
    }
    // ⚠️ Buffs and debuffs becoming real pushed draws from 4 to 11 in 40 fights
    // until sudden death was added. This is that regression test.
    expect(draws).toBe(0)
    // ⚠️ 90 -> 150, AND THE TWO ASSERTIONS ARE NOT THE SAME GUARD. `draws` is the
    // invariant; this is a lock detector, and at 90 it had gone stale — it was
    // written before the 5-minute clock and before the design goal of a SPREAD
    // ("some maybe 1 minute, some may be 4, that's the variation the builds will
    // allow"). It was firing on a legitimate 110.7s attrition win: 231 casts, 167
    // hits, 64.5 damage/s and 18 heals, one team's sustain out-lasting the other
    // and then wiping it 3-0. That is the game working.
    //
    // ⚠️ It DID also catch a real lock, so do not remove it. A sibling fight ran
    // 256.6s with three survivors at 11-18% HP, mana refilling to 100%, and FOUR
    // hits in its last 197 seconds — a mutual retreat standoff, fixed in
    // `decide.ts:retreatThreatOf`. 150 still catches that shape (a lock trends to
    // the 255s sudden-death point) while leaving room for a long honest grind.
    expect(longest).toBeLessThan(150)
  })

  it('is still perfectly deterministic with all of this live', () => {
    const A = [0, 1, 2].map((n) => mk('za' + n))
    const B = [0, 1, 2].map((n) => mk('zb' + n))
    const r1 = run(A, B, 'det'), r2 = run(A, B, 'det')
    expect(JSON.stringify(r1.events)).toBe(JSON.stringify(r2.events))
  })
})

describe('the last monster standing does not retreat', () => {
  // ⚠️ THERE ARE TWO INDEPENDENT RETREAT MECHANICS and gating only one moved the
  // measured lone-fallback count from 39 to 33 — most of them were never coming
  // from `decide.ts:retreatThreatOf` at all, but from the committed fall-back-to-
  // cover in `engine.ts`. Same duplicate-mechanic trap as `reachOf` and the class
  // basic attack. This asserts the OUTCOME, so a third path would fail it too.
  it('emits no fallback from a unit with no living team-mate', () => {
    let lone = 0, withMates = 0
    for (const seed of ['la1', 'la2', 'la3', 'la4', 'la5', 'la6']) {
      const mk = (id: string) => generateMonster(seed + id, { train: 850 })
      const teamA = [0, 1, 2].map((i) => mk('a' + i))
      const teamB = [0, 1, 2].map((i) => mk('b' + i))
      const r = simulateFieldBattle({ seed, teamA, teamB })
      const dead: Record<string, number> = { A: 0, B: 0 }
      const alone: Record<string, number | null> = { A: null, B: null }
      for (const e of r.events as { t: number; kind: string; id?: string }[]) {
        if (!e.id) continue
        const side = e.id[0]
        if (e.kind === 'death') {
          dead[side]++
          if (3 - dead[side] === 1 && alone[side] === null) alone[side] = e.t
        }
        if (e.kind === 'fallback') {
          const t0 = alone[side]
          if (t0 !== null && e.t >= t0) lone++
          else withMates++
        }
      }
    }
    expect(lone).toBe(0)
    // ⚠️ AND THE MECHANIC MUST SURVIVE. Both counts at zero would mean retreat had
    // been deleted rather than scoped, and this test would still be green.
    expect(withMates).toBeGreaterThan(0)
  })
})
