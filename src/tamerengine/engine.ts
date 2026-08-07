// The field engine's simulation loop.
//
// DETERMINISM IS THE CONTRACT. Everything downstream — resuming a saved cup,
// recomputing standings, the sim harness, replaying a fight in the arena —
// depends on `simulateFieldBattle` being a pure function of
// (monsters + placement + obstacles + seed). So: fixed dt, fixed unit order,
// one seeded rng stream, and no wall-clock or Math.random anywhere.
import { Monster, Move, MoveArea, MoveSpatial, Stat, aoeFalloff, statScaleOf, mulberry32, hashString, StatusKind, SPREADABLE_STATUSES, classForStats, DEFAULT_TACTICS, HARD_CONTROL_STATUSES} from '../core'
import { chooseLoadout, learnedMoves, manaCost, maxHp, maxMana } from '../monster'
import {
  DT, FIELD_H, FIELD_W, FieldEvent, FieldResult, FieldSetup, FieldSide, FieldUnit,
  PURSUIT_PATIENCE, PURSUIT_IGNORE, PURSUIT_PROGRESS, DASH_SPEED_MULT, DASH_MAX_TIME,
  FALL_BACK_RAMP, TURN_RATE,
  FALL_BACK_CD, FALL_BACK_DUR, FALL_BACK_HP, FALL_BACK_NEAR, ESCAPE_LOCKOUT,
  MAX_TICKS, Obstacle, RETARGET_EVERY, UnitVisState, Vec2, CONTAGION_RADIUS, TEAM_AURA_RADIUS,
  CHANNEL_CAST_TIME, CHANNEL_RANGE, DEPLOY_DEPTH, SECONDS_PER_ROUND,
  SUDDEN_DEATH_AT, KITE_MAX, KITE_REFILL,
  BASIC_STAT_TIER, BASIC_BASE_POWER, BASIC_STAT_SCALE,
  MANA_ON_HIT_TAKEN, MANA_ON_HIT_DEALT, FIELD_MANA_COST_MULT, OPENER_WINDOW,
  FIELD_LOADOUT_SIZE, CLEANSE_CC_IMMUNITY, CLASS_BASIC, KNOCKBACK_SPEED, KNOCKBACK_MIN_TIME, mitigationFor, COOLDOWN_MULT, TRIAGE_AT, MANA_RESERVE, FINISHER_AT, CC_PRIORITY_BONUS, COMBO_PRIME_BONUS} from './types'
import { archetypeOf, desiredGoal, dist, isMelee, manaRoleOf, norm, pickTarget, reachOf, spacingRadius, sub, threatOf, traitsFor, wantsToKite } from './decide'
import { personalityOf, spendAboveFor } from './personality'
import { spatialOf } from './spatial'
import { resolveStrike } from './damage'
import { applyStatus } from './statusMath'
import { tickUnit, suddenDeathLoss } from './tickMath'
import { FIELD_STATUS, BENEFICIAL, CONFUSION_VEER } from './status'

// ── Geometry helpers ────────────────────────────────────────────────────────
const insideObstacle = (p: Vec2, o: Obstacle, pad = 0) =>
  p.x > o.x - pad && p.x < o.x + o.w + pad && p.y > o.y - pad && p.y < o.y + o.h + pad

/** Does the segment a→b cross this rectangle? Used for line of sight. */
function segmentHitsRect(a: Vec2, b: Vec2, o: Obstacle): boolean {
  // Cheap reject on bounding boxes first.
  if (Math.max(a.x, b.x) < o.x || Math.min(a.x, b.x) > o.x + o.w) return false
  if (Math.max(a.y, b.y) < o.y || Math.min(a.y, b.y) > o.y + o.h) return false
  // Sample the segment — at these scales this is both accurate enough and
  // completely predictable, which matters more here than elegance.
  const steps = Math.max(4, Math.ceil(dist(a, b) * 2))
  for (let i = 1; i < steps; i++) {
    const t = i / steps
    const p = { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t }
    if (insideObstacle(p, o)) return true
  }
  return false
}

/** Is the attacker on the far side of the target from its own goal line? */
export const isBehind = (attacker: FieldUnit, target: FieldUnit): boolean =>
  attacker.side === 'A' ? attacker.pos.x > target.pos.x : attacker.pos.x < target.pos.x

const clampToField = (p: Vec2): Vec2 => ({
  x: Math.min(FIELD_W - 0.5, Math.max(0.5, p.x)),
  y: Math.min(FIELD_H - 0.5, Math.max(0.5, p.y)),
})

export const hasLineOfSight = (a: Vec2, b: Vec2, obstacles: Obstacle[]): boolean =>
  !obstacles.some((o) => segmentHitsRect(a, b, o))

// Non-overlap uses this fraction of the sum of visual radii, so two monsters
// settle ~1.19 units apart (0.66 × 1.8) — inside the 2.40 basic-melee reach, so
// melee still connects, but far enough that the sprites read as adjacent, never
// stacked. Must stay below (CHANNEL_RANGE.melee × 0.8) / (2 × radius) = 0.71.
const COLLISION_R_FRAC = 0.66

// Field-only DAMAGE-by-delivery. Range is worth paying for: a ranged unit hits
// the back line and fights from cover, so it trades raw punch for that reach;
// melee, walled to what's adjacent and divable, hits harder. FIELD-ONLY —
// battle.ts and its 12 goldens never read this, so it cannot move them. Small on
// purpose, and sim-tuned per the balancing rule; nudge gently.
// ⚠️ CHANNEL_DMG now lives in `damage.ts` — it is part of the port contract, not a
// private tuning knob. A port that missed it would be 12% wrong on every melee swing.

// Fraction of its speed a unit keeps while moving AWAY from the nearest enemy.
// See the note in stepToward: this is what breaks the pursuit equilibrium.
const BACKPEDAL_MULT = 0.6

/**
 * The nearest point outside every obstacle.
 *
 * ⚠️ THE FIX FOR THE WORST BUG IN THE ENGINE. `tryMove` rejects any position
 * inside an inflated obstacle, so a unit that STARTS inside one has every
 * candidate rejected — the full step, both axis slides, and the escape nudge.
 * It never moves again. On Titan's Rest that was 80 of 240 unit-fights welded
 * in place for the entire battle, and `resolved` could not see it: an inert
 * unit is still present, alive and targetable.
 *
 * Deterministic by construction — fixed ring radii, fixed angles, no rng — so
 * it cannot desync a replay. Rings grow outward so the unit ends up just
 * outside the face it was inside rather than teleported across the arena.
 */
function pushOutOfObstacles(p: Vec2, obs: Obstacle[], radius: number): Vec2 {
  const pad = radius * 0.6
  const blocked = (q: Vec2) => obs.some((o) => insideObstacle(q, o, pad))
  if (!blocked(p)) return p
  for (let r = 0.4; r <= 14; r += 0.4) {
    for (let k = 0; k < 16; k++) {
      const a = (k / 16) * Math.PI * 2
      const q = clampToField({ x: p.x + Math.cos(a) * r, y: p.y + Math.sin(a) * r })
      if (!blocked(q)) return q
    }
  }
  return p // nowhere free within 14 units: the arena is pathological, not the unit
}

import { buildNavGraph, nextWaypoint, bestCoverPoint, NavGraph } from './navgraph'
import { isEscapeMove, movementMoveFor } from './fieldMoves'

// ── Setup ───────────────────────────────────────────────────────────────────
/** Default cover: a symmetric pair of blocks so neither side is advantaged. */
export const DEFAULT_OBSTACLES: Obstacle[] = [
  { x: FIELD_W / 2 - 1.2, y: 3.5, w: 2.4, h: 4.5 },
  { x: FIELD_W / 2 - 1.2, y: FIELD_H - 8, w: 2.4, h: 4.5 },
]

/** Auto-deployment when the player has not placed anyone: a front arc and a back line. */
function autoPlace(team: Monster[], side: FieldSide): Vec2[] {
  const n = team.length
  return team.map((m, i) => {
    // Sturdier monsters take the front; casters and healers sit behind.
    const front = m.stats.CON + m.stats.STR >= m.stats.INT + m.stats.WIS
    const depth = front ? DEPLOY_DEPTH * 0.75 : DEPLOY_DEPTH * 0.3
    const x = side === 'A' ? depth : FIELD_W - depth
    const spread = Math.min(FIELD_H - 4, n * 3.2)
    const y = n === 1 ? FIELD_H / 2 : FIELD_H / 2 - spread / 2 + (i * spread) / Math.max(1, n - 1)
    return { x, y }
  })
}

/**
 * The FIELD equips FIELD_LOADOUT_SIZE (4) abilities, not the turn engine's 3.
 *
 * ⚠️ ADDITIVE, not a re-pick: whatever the monster already has equipped is kept
 * (that may be the player's own choice, or an awakened signature move), and the
 * extra slot is filled with the best learnable move it is not already carrying.
 * Deterministic — `chooseLoadout` is a pure ranking over the learned pool, no rng
 * — so a replay reproduces.
 */
/** The monster's own best stat — which movement ability it has trained into. */
function topStat(stats: Record<string, number>): Stat {
  return (['STR', 'DEX', 'CON', 'WIS', 'INT', 'CHA'] as Stat[])
    .reduce((a, b) => ((stats[b] ?? 0) > (stats[a] ?? 0) ? b : a))
}

export function fieldLoadout(m: Monster): Move[] {
  // ⚠️ Only top up a STANDARD FULL KIT. A monster handed a deliberately narrow
  // loadout (a scenario, or a test isolating one move) means it — padding that
  // dilutes the construction and the pinned move stops being chosen.
  if (m.loadout.length < 3 || m.loadout.length >= FIELD_LOADOUT_SIZE) return m.loadout
  // ⚠️ THE 18 FIELD MOVES WERE UNREACHABLE. `learnedMoves` filters ALL_MOVES
  // only, and `ALL_FIELD_MOVES` appeared nowhere in production code outside its
  // own file — Charge, Backstep, Blink, Fade, Beckon, Meteor and the rest were
  // authored, priced, spatially wired and TESTED, and no monster could ever
  // equip one. The same failure as the control moves before LINES and the heals
  // before the draft fix, at the largest scale yet.
  //
  // The FIELD's extra slot is now that movement ability, chosen by the stat the
  // monster actually trained. ⚠️ Granted rather than drafted, deliberately: a
  // zero-power utility move cannot out-rank a damage move on `expectedOutput`,
  // so leaving it to the draft is how it stayed at zero uses. The trade is that
  // it is universal rather than a build choice — worth revisiting once the
  // escape tier is proven, but reachability first.
  const extra = chooseLoadout(learnedMoves(m.stats), m.stats, FIELD_LOADOUT_SIZE)
    .filter((mv) => !m.loadout.some((x) => x.id === mv.id))
  const drafted = [...m.loadout, ...extra].slice(0, FIELD_LOADOUT_SIZE)
  // ⚠️ ITS OWN SLOT, NOT ONE TAKEN FROM THE DRAFT. Appending the mover INSIDE
  // the 4 displaced the 4th pick — which is the best remaining DAMAGE move — and
  // `basicAttack.test.ts` caught the consequence immediately: for a weak kit the
  // free attack started out-DPSing everything the monster owned (11.38 vs
  // 10.53). Movement is what the FIELD adds to a turn-engine kit, so it is an
  // extra slot rather than a sacrifice.
  const mover = movementMoveFor(topStat(m.stats))
  const granted = mover && (m.stats[mover.stat] ?? 0) >= mover.learnLevel
    && !drafted.some((x) => x.id === mover.id) ? [mover] : []
  return [...drafted, ...granted]
}

function buildUnit(m0: Monster, side: FieldSide, slot: number, pos: Vec2): FieldUnit {
  const m: Monster = { ...m0, loadout: fieldLoadout(m0) }
  const hp = Math.min(m.hp ?? maxHp(m.stats), maxHp(m.stats))
  const mp = Math.min(m.mp ?? maxMana(m.stats), maxMana(m.stats))
  return {
    id: side + slot,
    side, slot, m,
    pos: { ...pos },
    deployPos: { ...pos },
    // Statuses this unit can cash. `comboPrimes` (what its SIDE can cash) is
    // filled in below, once both teams exist.
    comboCashes: [...new Set(m.loadout
      .map((mv) => mv.effects?.bonusVsStatus?.kind).filter((k): k is StatusKind => !!k))],
    comboPrimes: [],
    openerQueue: (m.tactics?.openerIds ?? []).slice(0, 2),
    vel: { x: 0, y: 0 },
    radius: 0.9,
    // DEX drives how fast it crosses the field — the stat finally has a
    // spatial meaning beyond initiative.
    speed: 2.4 + (m.stats.DEX / 1000) * 3.6,
    hp, maxHp: maxHp(m.stats),
    mp, maxMp: maxMana(m.stats),
    traits: traitsFor(m),
    targetId: null,
    retargetIn: 0,
    cooldowns: {},
    castingFor: 0,
    castMoveId: null,
    castTargetId: null,
    statuses: [],
    mods: [],
    forcedTargetId: null,
    forcedUntil: 0,
    rootedFor: 0,
    fadedUntil: 0,
    slowMult: 1,
    slowFor: 0,
    disengageFor: 0,
    kiteFor: KITE_MAX,
    blockingUntil: 0,
    ward: 0,
    ccResist: 0,
    lastCcAt: -999,
    ccImmuneUntil: 0,
    hasAttacked: false,
    chaseFor: 0,
    chaseBest: Infinity,
    gaveUp: {},
    fallBackAt: 0,
    fallBackUntil: 0,
    fallBackTo: null,
    shoveTo: null,
    shoveUntil: 0,
    dashTo: null,
    dashUntil: 0,
    escapeLockUntil: 0,
    dead: false,
  }
}

// ── Move selection ──────────────────────────────────────────────────────────
/** FIELD mana cost — undoes monster.ts's turn-engine 2× (see FIELD_MANA_COST_MULT). */
const mpCost = (mv: Move) => manaCost(mv) * FIELD_MANA_COST_MULT
const rangeOf = (mv: Move) => mv.range ?? CHANNEL_RANGE[mv.channel]
const castOf = (mv: Move) => mv.castTime ?? CHANNEL_CAST_TIME[mv.channel]

/** Rough damage this move would do to this target — for kill checks only. */
function estimateDamage(u: FieldUnit, mv: Move, target: FieldUnit): number {
  const atk = u.m.stats[mv.stat] ?? 0
  const mit = mv.channel === 'melee' || mv.channel === 'ranged' ? target.m.stats.CON : target.m.stats.WIS
  // ⚠️ Must mirror strike()'s formula, or kill-checks (and therefore `worthSpending`
  // and the finish-it override) misjudge whether a cast would land a kill.
  return Math.max(1, Math.round(mv.power * (1 + atk * statScaleOf(mv)) * (1 - mitigationFor(mit))))
}

/**
 * PATIENCE: is this the moment to spend a big cooldown?
 *
 * Before this the engine simply fired the highest-power move that was off
 * cooldown, so a signature move was a rotation rather than a decision — and
 * dumping it into a full-health tank cost nothing. A patient monster holds it
 * until the target is softened; an impulsive one fires the instant it is up.
 * A guaranteed KILL always overrides the wait.
 */
/**
 * How much a unit wants to spend its BIGGEST move right now — a weighting in
 * 0..1, never a veto.
 *
 * ⚠️ THIS USED TO REFUSE THE MOVE OUTRIGHT. A patient monster would decline its
 * best ability until the target dropped below a threshold that, in a fight it
 * was losing, never arrived — so it stood on its strongest tool and poked. As a
 * player-facing order (`burst`) a hard veto is worse still: "hold your nuke"
 * must not mean "never attack". Discounted instead, so a held-back nuke still
 * wins when nothing better is off cooldown.
 */
/** How far a held-back nuke is discounted. Not zero — see spendWeight. */
const HOLD_BACK_DISCOUNT = 0.55

/**
 * Would this monster rather cover up than throw its free attack?
 *
 * ⚠️ BRACING IS FOR EVERY CLASS, not just anchors. The block branch was reachable
 * only when a unit had NOTHING else to do, and once the free attack's cooldown
 * dropped to 0.55s that state effectively stopped existing — so nothing outside
 * the anchor archetype ever braced. A real skill still always wins; this only
 * ever declines the FILLER, and only when covering up is plainly worth more than
 * a ~9-power poke: hurt, and with two or more bodies on you.
 *
 * `preserve` tunes the threshold, and an unordered monster still flinches at
 * 30% — instinct, not coaching. That is the "every class can brace" floor;
 * richer tactical control over it is a separate pass.
 */
function wouldBrace(u: FieldUnit, foes: FieldUnit[], now: number): boolean {
  const pres = u.m.tactics?.preserve ?? 'off'
  const at = pres === 'defensive' ? 0.25 : pres === 'cautious' ? 0.4 : 0.3
  if (u.hp / u.maxHp >= at) return false
  let onMe = 0
  for (const e of foes) {
    if (e.dead) continue
    if (dist(u.pos, e.pos) <= reachOf(e) + 1.0) onMe++
  }
  void now
  return onMe >= 2
}

function spendWeight(u: FieldUnit, mv: Move, target: FieldUnit, avgPower: number): number {
  const isBig = mv.power > avgPower * 1.25
  if (!isBig) return 1
  if (estimateDamage(u, mv, target) >= target.hp) return 1 // it would finish them — always
  const at = spendAboveFor(u.m, personalityOf(u.m))
  return target.hp / target.maxHp <= at ? 1 : HOLD_BACK_DISCOUNT
}

/** The best move this unit can actually land on its target right now. */
/**
 * What a damage move is actually worth AGAINST THIS TARGET, right now.
 *
 * ⚠️ THE SCORE USED TO BE `mv.power` AND NOTHING ELSE. Wiring an effect into
 * `strike` is only half of making it real — if the picker cannot see it, the
 * move is still never chosen at the moment it would pay. With a flat power
 * score a Warrior would never prefer Executioner against a dying target, a
 * giant-killer would never be aimed at the giant, a detonator would never fire
 * while its status was up, and a 3-hit move ranked as though it hit once.
 *
 * Mirrors `battle.ts:effPower` so the two engines rank a move the same way.
 * Every term is SITUATIONAL: it reads live state, so the same move scores
 * differently from one second to the next, which is the whole point.
 */
function effPowerField(u: FieldUnit, mv: Move, target: FieldUnit): number {
  const e = mv.effects
  // Multi-hit: `power` is per hit, so a 2-4 hit move is worth ~3x its number.
  const avgHits = e?.hits ? (e.hits[0] + e.hits[1]) / 2 : 1
  let p = mv.power * avgHits
  if (e?.execute && target.hp / target.maxHp <= e.execute) p *= 1.5
  if (e?.bonusVsStatus && hasStatus(target, e.bonusVsStatus.kind)) p *= e.bonusVsStatus.mult
  if (e?.maxHpDmg) p += target.maxHp * e.maxHpDmg
  if (e?.firstStrikeMult && !target.hasAttacked) p *= e.firstStrikeMult
  // PIERCE is worth exactly the mitigation it skips, so it ranks itself up
  // against a wall of CON and adds nothing against a squishy — the giant-killer
  // aims itself without a bespoke rule.
  if (e?.pierce) {
    const mit = mv.channel === 'melee' || mv.channel === 'ranged' ? target.m.stats.CON : target.m.stats.WIS
    // ⚠️ THE SAME CONSTANTS `strike()` USES. This is the THIRD mirror of the
    // mitigation curve in this file and it had drifted on BOTH values — still
    // 0.55/1400 after MIT_DIVISOR went to 1250 and MIT_CAP to 0.65 — so pierce
    // was being priced against a curve the game no longer used.
    const full = mitigationFor(mit)
    const kept = mitigationFor(mit, e.pierce)
    p *= (1 - kept) / Math.max(0.01, 1 - full)
  }
  // Resource strikes are worth what the caster is HOLDING — nothing with the
  // shield down, so the AI waits until it has something to shatter.
  if (e?.consumeWard) p *= 1 + e.consumeWard * u.ward
  if (e?.hpScale) {
    const f = Math.max(0, Math.min(1, u.hp / u.maxHp))
    p *= e.hpScale.atEmpty + (e.hpScale.atFull - e.hpScale.atEmpty) * f
  }
  return p
}

/**
 * ⚠️ EXPORTED FOR TESTING, and only for that. `manaPolicy` shipped wrong twice and
 * both times the evidence was statistical — a sweep that could not distinguish
 * "the order fired and did little" from "the order never fired". The gate is a
 * three-way condition (reserve / target HP / dearest move); asserting it directly
 * is the difference between knowing and inferring.
 */
export function chooseMove(u: FieldUnit, target: FieldUnit, obstacles: Obstacle[]): Move | null {
  const d = dist(u.pos, target.pos)
  const dmgMoves = u.m.loadout.filter((mv) => mv.type === 'damage')
  const avgPower = dmgMoves.length
    ? dmgMoves.reduce((n, mv) => n + mv.power, 0) / dmgMoves.length
    : 0
  let best: Move | null = null
  let bestScore = -Infinity
  for (const mv of dmgMoves) {
    if ((u.cooldowns[mv.id] ?? 0) > 0) continue
    // ⚠️ MANA POLICY — 'conserve' is a FINISHER FUND. Hold MANA_RESERVE of the
    // pool through the healthy phase of a fight, then release it, on the kit's
    // dearest move, once the target is under FINISHER_AT and the spell can
    // actually end something. 'burst' (and absent) spend straight to the floor.
    //
    // ⚠️ TWO WRONG VERSIONS SHIPPED BEFORE THIS ONE, and they are the same mistake
    // from opposite ends. The FIRST blocked any cast that dipped below the reserve,
    // so a 'conserve' unit never spent the 30% at all and ended fights holding
    // mana. The SECOND let it through for the dearest move with NO condition on the
    // target, so the reserve went the moment the dearest move was simply the
    // dearest move — a fund that empties itself on a full-health enemy is not a
    // fund. A reserve is neither untouchable nor free: it is saved FOR A MOMENT,
    // and the moment has to be in the code.
    //
    // ⚠️ DEAREST BY MP, NOT BY POWER, and that is deliberate. The gate only ever
    // bites on a move the unit cannot otherwise afford, so the fund exists to keep
    // the EXPENSIVE option live; a cheap hard-hitter never trips it and needs no
    // help. Mana prices effectiveness in this pool, so cost is the honest anchor.
    const pol = u.m.tactics?.manaPolicy
    if (pol === 'conserve') {
      const cost = mpCost(mv)
      if (u.mp - cost < u.maxMp * MANA_RESERVE) {
        const dear = Math.max(...dmgMoves.map((x) => mpCost(x)))
        const finishing = target.hp / target.maxHp < FINISHER_AT
        if (!finishing || cost < dear) continue
      }
    }
    if (d > rangeOf(mv)) continue
    // Ranged and magic need to actually SEE the target — cover is real.
    if (mv.channel !== 'melee' && !hasLineOfSight(u.pos, target.pos, obstacles)) continue
    // ⚠️ CC PRIORITY. Lead with hard control before committing to damage — but
    // only while the target is NOT already under it, or the order would spend
    // every stun re-stunning someone helpless. Ten UI references set this and
    // the field engine read none of them.
    const cc = u.m.tactics?.ccPriority
      && mv.status && HARD_CONTROL_STATUSES.has(mv.status.kind)
      && !target.statuses.some((s) => HARD_CONTROL_STATUSES.has(s.kind))
      ? CC_PRIORITY_BONUS : 1
    // ⚠️ COMBO ROLE — the PRIME half. Weight a move that applies a status this
    // unit's SIDE can cash, and only while the target does not already carry it —
    // otherwise a primer spends the whole fight re-poisoning a poisoned enemy,
    // which is the same trap `ccPriority` had to be gated against.
    const prime = u.m.tactics?.comboRole === 'prime'
      && mv.status && u.comboPrimes.includes(mv.status.kind)
      && !target.statuses.some((st) => st.kind === mv.status!.kind)
      ? COMBO_PRIME_BONUS : 1
    const score = effPowerField(u, mv, target) * spendWeight(u, mv, target, avgPower) * cc * prime
    if (score > bestScore) { bestScore = score; best = mv }
  }
  return best
}

/**
 * ⚠️ NON-DAMAGE MOVES USED TO BE DEAD WEIGHT. `chooseMove` filtered
 * `type === 'damage'`, so a monster holding Mend, Bastion, Hallowed Ground or
 * any of the six movement abilities simply never cast them — the whole field
 * move set, and every support kit in the game, was inert on the field. This is
 * the half of move selection that was missing.
 *
 * The score is expressed on the SAME scale as damage (a move's `power`, roughly
 * 12–68 across the pool), so utility and damage compete honestly in one
 * comparison rather than needing a priority order. A utility cast wins when the
 * situation makes it genuinely worth more than hitting something.
 *
 * ⚠️ It returns 0 — never cast — for effects the field engine does not model:
 * ward, guard, thorns and the round-based stat buffs have no representation
 * here. Scoring them anyway would have monsters spending casts on nothing.
 * Making them real is a separate piece of work, not something to fake.
 */
interface UtilityAim { mv: Move; aim: FieldUnit; score: number }

/** Below this an effect is not worth a cast, a cooldown, or the mana. */
// ⚠️ IN POWER UNITS — it is weighed against a raw `power` one line below, so it
// moved with the pool when DAMAGE_MULT was baked in (8 → 7.4). Left at 8 it would
// silently mean 8% MORE than it used to, and utility would beat damage more often
// than it did before a refactor that was supposed to change nothing.
//
// ⚠️ CHOSEN ON UNITS, NOT ON THE SIM — the sweep cannot separate the two values
// (27.1s/233 kills at 7.4 against 27.4s/234 at 8, a 0.3s gap inside a 2.8s noise
// band). It is not cosmetic either: `trio` swings 30.9s to 38.6s on it. One
// fixture is not evidence; the 48-fight sweep is, and it says the choice is free.
//
// ⚠️ AND SCALING IT DOES NOT RESTORE THE PRE-BAKE FIGHT, which is worth knowing
// before reaching for it as a tuning knob: `bestUtility` scores mix power-derived
// terms with HP-derived ones, and HP did not move. No single scalar on this
// constant can neutralise a pool-wide power change. Two drafts of this comment
// claimed otherwise before the runs were actually diffed.
const UTILITY_FLOOR = 7.4

function utilityScore(
  u: FieldUnit, mv: Move, mates: FieldUnit[], foes: FieldUnit[],
): UtilityAim | null {
  const sp = spatialOf(mv.name)
  const live = (xs: FieldUnit[]) => xs.filter((x) => !x.dead)
  const allies = [u, ...live(mates).filter((x) => x.id !== u.id)]
  const enemies = live(foes)
  if (!enemies.length) return null

  let best: UtilityAim | null = null
  const offer = (score: number, aim: FieldUnit) => {
    if (score > 0 && (!best || score > best.score)) best = { mv, aim, score }
  }

  // ── HEALING ───────────────────────────────────────────────────────────────
  // Worth what it actually restores, not its printed number: a 60-point heal on
  // someone missing 10 HP is worth 10. Same rule as `battle.ts:healValue`, so
  // the two engines agree about when a Sage should heal.
  if (mv.power > 0 && (mv.type === 'buff' || mv.type === 'control')
      && (mv.target === 'self' || mv.target === 'ally' || mv.target === 'team')) {
    const pool = mv.target === 'self' ? [u] : allies
    const patient = [...pool].sort((a, b) => a.hp / a.maxHp - b.hp / b.maxHp)[0]
    if (patient) {
      const restored = mv.target === 'team'
        ? pool.reduce((n, c) => n + Math.min(mv.power, c.maxHp - c.hp), 0)
        : Math.min(mv.power, patient.maxHp - patient.hp)
      // Face value is what it restores, but a heal is worth MORE than its
      // number when it denies a kill — scored flat, healing simply never won a
      // comparison against damage and no monster ever healed anyone.
      const urgency = 1 + (1 - patient.hp / patient.maxHp) * 1.5
      offer(restored * urgency, patient)
    }
  }

  // ── THE NINE FORMERLY-INERT EFFECTS ──────────────────────────────────────
  // ⚠️ These scored ZERO, which is the whole reason no monster had ever cast one
  // — 11 moves were literally unplayable. Every score below is SITUATIONAL, for
  // the reason the Fade note gives: a flat value turns a defensive cooldown into
  // a tic. This engine has twice shipped that bug (taunt cast 86 times before
  // taunt existed; War Cry taking 137 of 254 utility casts for almost nothing).
  {
    const fx = mv.effects
    const pool = mv.target === 'team' ? allies : mv.target === 'self' ? [u] : allies
    // How much heat is actually on a candidate — defence is worth the danger.
    const heatOn = (v: FieldUnit) => enemies.filter((e) => dist(v.pos, e.pos) < 6).length
    // ⚠️ A team buff LANDS ON EVERY ALLY (see the crowd loop in resolveHit) but
    // was VALUED as if it hit one — the best single beneficiary. So the whole
    // reach a team buff is paid for in mana never entered the comparison, and a
    // team ward lost to a self ward that absorbed a sixth as much. Team buffs are
    // uncapped by design: value them as the TOTAL they deliver, and let the
    // authored `Move.mana` be the thing that prices the better buff.
    // `atkBuff`/`defBuff` already did this via their own `reach` multiplier.
    const pick = (score: (v: FieldUnit) => number) => {
      if (mv.target === 'team') {
        const total = pool.reduce((n, v) => n + score(v), 0)
        const focus = [...pool].sort((a, b) => score(b) - score(a))[0]
        if (focus) offer(total, focus) // aim is cosmetic for a team cast
        return
      }
      for (const v of pool) offer(score(v), v)
    }
    // WARD / GUARD — worth what they will actually absorb, so they are cast when
    // a monster is under fire and never on an idle walk-up.
    if (fx?.ward) pick((v) => (heatOn(v) > 0 ? fx.ward! * (0.5 + heatOn(v) * 0.4) : 0))
    if (fx?.guard) pick((v) => heatOn(v) * fx.guard! * 2.5)
    // THORNS — worth the hits it will reflect, i.e. how many are on that body.
    if (fx?.thorns) pick((v) => heatOn(v) * fx.thorns! * 3)
    // DODGE — avoided damage, so again a function of attackers.
    if (fx?.dodgeBuff) pick((v) => heatOn(v) * fx.dodgeBuff! * 0.8)
    // ACCURACY — worth more landed damage, judged on the holder's own output.
    if (fx?.accBuff) pick((v) => fx.accBuff! * 0.6 * (1 + threatOf(v.m) / 120))
    // HP REGEN — a slow heal: worth what it can actually restore.
    if (fx?.hpRegenBuff) {
      const rounds = fx.duration ?? 3
      pick((v) => Math.min(fx.hpRegenBuff! * rounds, v.maxHp - v.hp) * 0.9)
    }
    // CLEANSE — the statuses it strips, plus real value in the CC immunity it
    // now grants (so it is worth pre-casting on someone being chain-controlled).
    if (fx?.cleanse) {
      pick((v) => {
        const bad = v.statuses.filter((st) => !BENEFICIAL.has(st.kind)).length
        const chained = v.ccResist > 0 ? 12 : 0
        return bad * 18 + chained
      })
    }
    // MANA REGEN — worth what the holder can actually spend it on. A monster
    // with a cheap kit and a full pool gains nothing; one that is dry and
    // holding expensive abilities gains a lot. Without the emptiness term this
    // becomes a walk-up tic, the exact failure the note above records.
    if (fx?.regenBuff) {
      const rounds = fx.duration ?? 3
      pick((v) => {
        const empty = 1 - v.mp / Math.max(1, v.maxMp)
        return fx.regenBuff! * rounds * (0.3 + empty * 1.4)
      })
    }
    // ── HOSTILE UTILITY ──────────────────────────────────────────────────────
    // Debuffs are scored against the ENEMY they would land on, not an ally, so
    // they need their own pass rather than the `pick` helper above.
    const hostile = (score: (v: FieldUnit) => number) => {
      for (const e2 of enemies) offer(score(e2), e2)
    }
    // DEFENCE DOWN — worth the extra damage it opens up, so it is cast on the
    // wall that is actually being hit rather than on whoever is nearest.
    if (fx?.defDebuff) hostile((v) => fx.defDebuff! * 1.6 * (1 + allies.filter((a) => !a.dead && dist(a.pos, v.pos) < 7).length * 0.4))
    // ACCURACY DOWN — worth the damage it makes MISS, judged on that enemy's
    // own output. Blinding a healer is close to worthless; blinding the bruiser
    // beating on your front line is not.
    if (fx?.accDebuff) hostile((v) => fx.accDebuff! * 0.7 * (1 + threatOf(v.m) / 120))
    // MANA BURN — worth what it actually takes. A dry caster cannot be drained,
    // so this stops being cast the moment it has done its job.
    if (fx?.manaBurn) hostile((v) => Math.min(fx.manaBurn!, v.mp) * 0.8)
  }

  if (sp) {
    // ── ESCAPE ──────────────────────────────────────────────────────────────
    // Fading or dashing clear is worth exactly as much as the danger you are
    // in. With nothing near, both score zero, so a healthy monster never wastes
    // the cooldown — the cost of getting this wrong is that Fade becomes a tic.
    if (sp.fade || sp.move?.to === 'awayFromTarget') {
      const near = enemies.filter((e) => dist(u.pos, e.pos) < 5).length
      const hurt = 1 - u.hp / u.maxHp
      offer(near * 16 + hurt * 40 - 10, u)
    }

    // ── ZONES ───────────────────────────────────────────────────────────────
    // A patch of ground is worth the bodies standing on it. Aimed zones look at
    // the best enemy cluster; self-centred ones at who is already beside you.
    if (sp.zone) {
      const z = sp.zone
      const hostile = z.effect !== 'heal'
      const crowd = hostile ? enemies : allies
      const rate = z.power * z.duration * (hostile ? 0.5 : 0.35)
      if (z.centre === 'target') {
        for (const c of enemies) {
          const caught = crowd.filter((x) => dist(c.pos, x.pos) <= z.radius).length
          if (dist(u.pos, c.pos) <= rangeOf(mv)) offer(caught * rate * 0.5, c)
        }
      } else {
        const caught = crowd.filter((x) => dist(u.pos, x.pos) <= z.radius
          && (hostile || x.hp < x.maxHp)).length
        offer(caught * rate * 0.5, u)
      }
    }

    // ── HAULING AN ALLY OUT ─────────────────────────────────────────────────
    // Only worth a cast when someone is genuinely in trouble AND far enough
    // away that dragging them changes anything.
    if (sp.haulAlly) {
      const worst = allies.filter((a) => a.id !== u.id)
        .sort((a, b) => a.hp / a.maxHp - b.hp / b.maxHp)[0]
      if (worst && worst.hp / worst.maxHp < 0.5 && dist(worst.pos, u.pos) > 4) {
        offer((1 - worst.hp / worst.maxHp) * 60, worst)
      }
    }
  }

  // ── CONTROL AND DEBUFFS ───────────────────────────────────────────────────
  // ⚠️ ONLY what the field genuinely implements. A first cut scored every
  // `type: 'debuff'` move, and the AI immediately spent 86 casts on Taunt
  // across 25 fights back when taunt did nothing — the exact "spending casts on
  // nothing" failure this scorer exists to avoid. Anything unmodelled (cleanse,
  // accuracy and dodge mods, ward, thorns) must score zero until it is real.
  const fx = mv.effects
  const modelled = !!(mv.status || sp?.root || sp?.slow || sp?.pull || sp?.push
    || fx?.atkDebuff || fx?.tauntForce)
  if (modelled) {
    const chance = (mv.status?.chance ?? 100) / 100
    for (const e of enemies) {
      if (dist(u.pos, e.pos) > rangeOf(mv)) continue
      // ⚠️ REFRESHING SOMETHING ALREADY RUNNING IS NEARLY WORTHLESS. Without
      // this the AI re-cast the same debuff the instant its cooldown returned —
      // War Cry alone took 129 of 242 utility casts, most of them onto a buff
      // that had not expired. Same principle as overhealing being wasted.
      const already = (mv.status && e.statuses.some((st) => st.kind === mv.status!.kind))
        || (fx?.atkDebuff && e.mods.some((m) => (m.atk ?? 1) < 1))
        || (fx?.tauntForce && e.forcedTargetId === u.id)
      // Control is worth most on whoever is most dangerous and least dead —
      // stunning something about to die wastes it.
      offer(34 * chance * (e.hp / e.maxHp) * (already ? 0.1 : 1), e)
    }
  }

  // ── SELF AND TEAM BUFFS ───────────────────────────────────────────────────
  // Only the two the field reads. A flat worth, discounted so a buff never
  // outbids a real nuke, and scaled by how many allies it actually reaches.
  if ((fx?.atkBuff || fx?.defBuff) && (mv.target === 'self' || mv.target === 'ally' || mv.target === 'team')) {
    const reach = mv.target === 'team' ? allies.length : 1
    const running = (fx.atkBuff && u.mods.some((m) => (m.atk ?? 1) > 1))
      || (fx.defBuff && u.mods.some((m) => (m.dmgTaken ?? 1) < 1))
    offer(((fx.atkBuff ?? 0) * 55 * reach + (fx.defBuff ?? 0) * 1.5 * reach) * (running ? 0.1 : 1), u)
  }

  return best
}

/**
 * The free universal attack. Every unit needs one it can use AT ITS OWN REACH:
 * a first pass gave everyone a melee-only swing, so an archer whose skills were
 * all on cooldown simply stood at range doing nothing — 6 units managed one hit
 * every ~6 seconds and the fight read as passive. A basic attack matched to the
 * unit's natural range keeps everyone contributing between cooldowns.
 */
export function basicAttackFor(m: Monster): Move {
  // Fight at the range this monster is built for — AUTHORED, not inferred.
  // See CLASS_BASIC in types.ts for why every attempt to derive this from the
  // loadout produced a monster fighting at the wrong range.
  const spec = CLASS_BASIC[classForStats(m.stats)] ?? CLASS_BASIC.Generalist
  const { channel, stat } = spec
  return {
    id: 'basic', name: 'Attack', stat, learnLevel: 0, type: 'damage',
    channel, target: 'enemy',
    // Deliberately weak and fast — it fills the gaps between real skills, it
    // does not replace them.
    // ⚠️ COOLDOWN 0.55, NOT 0.9. At 0.9 the free attack re-armed every 0.96s
    // while its swing occupied only its 0.15s cast, so a monster with everything
    // else on cooldown read as ~84% IDLE — it was not stuck, it was waiting on
    // the filler itself. The filler should not be the thing you wait for. The
    // damage is deliberately NOT raised to compensate: this buys presence
    // between casts, not throughput.
    // ⚠️ Floor is set by basicAttack.test.ts — the basic must stay under the
    // kit both per cast and by volume. At STR 359 this is ~13.3 power/s against
    // a reachable ability's ~45/s, so there is real headroom, but drop the
    // cooldown much further and the invariant starts to bind.
    // ⚠️ 0.55 -> 0.715 (x1.3) WHEN COOLDOWNS BECAME SECONDS. This is a FOURTH
    // authored cooldown in a fourth place — inline here, not in any of the three
    // pool files — and it was already written in seconds while still being fed
    // through `* COOLDOWN_MULT`. Retiring that multiplier to 1.0 without scaling
    // this made the free attack 30% faster, which is the single highest-frequency
    // action in the game: three field goldens moved by up to 5.4s and it read as
    // a balance change rather than the missed conversion it was.
    cooldown: 0.715, accuracy: 90,
    // Stat-tiered: physical swings hit, caster jabs do not (see BASIC_STAT_TIER).
    power: BASIC_BASE_POWER + (m.stats[stat] ?? 0) * BASIC_STAT_SCALE * (BASIC_STAT_TIER[stat] ?? 0.5),
    // ⚠️ KEYED TO THE UNIT'S ACTUAL REACH, not the channel default. `bestRange`
    // is computed above from the loadout and was IDENTICAL to the channel
    // default while no move authored its own range — the moment moves did, a
    // Volley user (reach 10.4) stood at 7.8 holding a free attack that reached
    // 6.4 and could never swing. Which is precisely the failure this move's own
    // comment describes, arriving by a different door.
    range: spec.range,
    castTime: 0.15,
    desc: 'A basic strike.',
  }
}

// ── Status accessors ────────────────────────────────────────────────────────
// A unit can carry several afflictions at once, so every query is an aggregate
// over the whole list rather than a lookup of one. Flags OR together, penalties
// add, multipliers multiply — stating that once here is what stops each call
// site inventing its own stacking rule.
const hasStatus = (u: FieldUnit, k: StatusKind) => u.statuses.some((s) => s.kind === k)

/**
 * The unit's active effects, split into buff/debuff icon keys for the renderer's
 * two rows. Statuses map by sign (`BENEFICIAL` → buff, the rest → debuff); the
 * timed `mods` become `atkUp`/`atkDown`/`defUp`. De-duped so a stack of the same
 * kind shows one icon. Active-only, so both lists are usually 0–3.
 */
function effectIcons(u: FieldUnit): { buffs: string[]; debuffs: string[] } {
  const buffs = new Set<string>()
  const debuffs = new Set<string>()
  for (const s of u.statuses) (BENEFICIAL.has(s.kind) ? buffs : debuffs).add(s.kind)
  for (const m of u.mods) {
    if (m.atk && m.atk > 1) buffs.add('atkUp')
    else if (m.atk && m.atk < 1) debuffs.add('atkDown')
    if (m.dmgTaken && m.dmgTaken < 1) buffs.add('defUp')
  }
  return { buffs: [...buffs], debuffs: [...debuffs] }
}

type StatusFlag = 'incapacitates' | 'noSkills' | 'noAttack' | 'blockHeal' | 'turncoat'
const statusFlag = (u: FieldUnit, key: StatusFlag) =>
  u.statuses.some((s) => FIELD_STATUS[s.kind][key])

const statusAccPenalty = (u: FieldUnit) =>
  u.statuses.reduce((n, s) => n + (FIELD_STATUS[s.kind].accPenalty ?? 0), 0)

const statusSpeedMult = (u: FieldUnit) =>
  u.statuses.reduce((n, s) => n * (FIELD_STATUS[s.kind].speedMult ?? 1), 1)

const statusDamageTaken = (u: FieldUnit) =>
  u.statuses.reduce((n, s) => n * (FIELD_STATUS[s.kind].damageTakenMult ?? 1), 1)

const modAtk = (u: FieldUnit) => u.mods.reduce((n, m) => n * (m.atk ?? 1), 1)
const modDmgTaken = (u: FieldUnit) => u.mods.reduce((n, m) => n * (m.dmgTaken ?? 1), 1)
// The previously-inert defensive/accuracy effects. These SUM (they are flat
// amounts or percentage POINTS), unlike atk/dmgTaken which multiply.
const modGuard = (u: FieldUnit) => u.mods.reduce((n, m) => n + (m.guard ?? 0), 0)
const modThorns = (u: FieldUnit) => u.mods.reduce((n, m) => n + (m.thorns ?? 0), 0)
const modDodge = (u: FieldUnit) => u.mods.reduce((n, m) => n + (m.dodge ?? 0), 0)
const modAcc = (u: FieldUnit) => u.mods.reduce((n, m) => n + (m.acc ?? 0), 0)
/** defDebuff, in PERCENTAGE POINTS off the mitigation fraction. */
const modMitDebuff = (u: FieldUnit) => u.mods.reduce((n, m) => n + (m.mitDebuff ?? 0), 0)

/** The affliction currently driving this unit's feet, if any. First wins. */
const steeringStatus = (u: FieldUnit) => {
  for (const s of u.statuses) {
    const st = FIELD_STATUS[s.kind].steer
    if (st) return { steer: st, from: s.from }
  }
  return null
}

// A confused monster veers consistently for the whole fight rather than
// jittering: which way it leans is derived from its id, so a replay of the same
// battle traces the same wrong path. Randomising it here would spend rng draws
// and break the determinism the field contract rests on.
const veerSign = (u: FieldUnit) => (hashString(u.id) % 2 === 0 ? 1 : -1)

// ── The loop ────────────────────────────────────────────────────────────────
export function simulateFieldBattle(setup: FieldSetup): FieldResult {
  const rng = mulberry32(hashString(
    setup.seed + ':' + setup.teamA.map((m) => m.seed).join(',') + '|' + setup.teamB.map((m) => m.seed).join(','),
  ))
  const obstacles = setup.obstacles ?? DEFAULT_OBSTACLES
  const placeA = setup.placeA ?? autoPlace(setup.teamA, 'A')
  const placeB = setup.placeB ?? autoPlace(setup.teamB, 'B')
  const units: FieldUnit[] = [
    ...setup.teamA.map((m, i) => buildUnit(m, 'A', i, placeA[i] ?? autoPlace(setup.teamA, 'A')[i])),
    ...setup.teamB.map((m, i) => buildUnit(m, 'B', i, placeB[i] ?? autoPlace(setup.teamB, 'B')[i])),
  ]
  // ⚠️ BEFORE TICK 1. Deployment is chosen by hex zones and formation rules that
  // know nothing about cover, so a legal-looking placement can land on a rock.
  // Nudging here — rather than banning cover near spawns — keeps arenas free to
  // put a pillar by the start line, which is a real design tool.
  // ⚠️ `deployPos` is re-stamped AFTER the nudge, not before. It is the anchor
  // `formation: 'keep'` holds a slot against, and a slot inside a rock is one the
  // unit spends the whole fight failing to stand on.
  for (const u of units) {
    u.pos = pushOutOfObstacles(u.pos, setup.obstacles ?? [], u.radius)
    u.deployPos = { ...u.pos }
  }
  // ⚠️ WHAT A PRIMER PRIMES FOR IS A TEAM FACT, and `chooseMove` never sees the
  // team. Resolved once here rather than threading allies through the whole
  // decision path: a primer applies a status because SOMEONE on its side can cash
  // it, which is exactly what makes prime/detonate a division of labour instead of
  // two settings on one monster.
  for (const side of ['A', 'B'] as FieldSide[]) {
    const mine = units.filter((u) => u.side === side)
    const canCash = [...new Set(mine.flatMap((u) => u.comboCashes))]
    for (const u of mine) u.comboPrimes = canCash
  }

  // ⚠️ BUILT ONCE. Obstacles never move, so the visibility graph is a constant
  // of the arena — the per-tick cost is the two attach passes in nextWaypoint,
  // and even those only run when the goal is NOT directly visible, which is most
  // ticks. `navPad` must EXCEED tryMove's `radius * 0.6` inflation or every
  // corner is somewhere the unit is forbidden to stand and each path aims at an
  // unreachable point.
  const navPad = Math.max(...units.map((u) => u.radius), 0.9) * 0.6 + 0.25
  const navLos: (a: Vec2, b: Vec2) => boolean = (a, b) => hasLineOfSight(a, b, obstacles)
  const navGraph: NavGraph = buildNavGraph(obstacles, navPad, navLos, { w: FIELD_W, h: FIELD_H })

  const byId = new Map(units.map((u) => [u.id, u]))
  const events: FieldEvent[] = []
  // Persistent patches of ground. The arena's own contribution to tactics: a
  // zone denies SPACE rather than damaging a body.
  const zones: { x: number; y: number; r: number; until: number; effect: 'damage' | 'slow' | 'heal'; power: number; side: FieldSide }[] = []

  // ── FLANKING ──────────────────────────────────────────────────────────────
  // Being OUTNUMBERED and UNSUPPORTED is what gets punished — not merely being
  // attacked. A defender with two enemies on it but a friend at its shoulder is
  // fighting a normal fight; the same defender alone is surrounded.
  // ⚠️ Deliberately keyed off the DEFENDER's situation, not the attacker's
  // facing. A true positional backstab already exists as a per-move `backstab`
  // rider, and duplicating it here would double-pay the same idea.
  // Accuracy POINTS, not a fraction (the standing units rule), and it favours
  // melee for free: melee is what actually stacks two bodies onto one target,
  // which is the STR/Warrior identity the class-damage table showed was weakest.
  // ⚠️ THE RADII WERE WHY THIS DID NOTHING, NOT THE BONUS. It fired on 2.2% of
  // attacks (86 of 3865) and zeroing the bonus moved nothing at either tier.
  // ENGAGE 2.6 sat BELOW melee reach 3.0, so a melee attacker at its own proper
  // distance did not register as "on" the target — the mechanic was blind to the
  // exact situation it exists for — while SUPPORT 3.2 was WIDER than ENGAGE, so
  // a defender counted as protected by an ally standing further off than the
  // enemies hitting it. Fixed: 4.0 / 2.5, and the fire rate went 2.2% -> 17.5%.
  //
  // ⚠️ AND THEN IT AMPLIFIED THE CASCADE EXACTLY AS ORIGINALLY THEORISED. At the
  // old +10 with working radii, mid ran 26.1s -> 20.0s and elite 19.5s -> 17.2s:
  // a real mechanic, pointed at the side already losing, and directly against the
  // goal of longer fights with a wider spread. Halved to 5, which keeps it live
  // at 17.5% for a cost inside the noise band (mid 25.4s, elite 17.7s).
  //
  // ⚠️ So the earlier retraction was half right. "Flanking amplifies the cascade"
  // was a correct THEORY measured against a broken implementation; the 2.2%
  // reading refuted the code, not the idea. Both readings are kept here because
  // the difference between them is the lesson.
  const FLANK_ACC_BONUS = 5
  // ⚠️ ENGAGE MUST COVER MELEE REACH OR IT CANNOT SEE A MELEE FIGHT. At 2.6 it
  // sat BELOW CLASS_BASIC's melee band (3.0), so a melee attacker standing at
  // its own proper distance did not count as "on" the target — the mechanic was
  // blind to precisely the situation it exists for. 4.0 is melee reach plus the
  // separation an ally is pushed out to.
  const FLANK_ENGAGE_RADIUS = 4.0   // "on" the defender
  // ⚠️ AND SUPPORT WAS WIDER THAN ENGAGE, so a defender counted as protected by
  // an ally standing further away than the enemies attacking it. Tightened to
  // 2.5: to cover someone you have to be genuinely beside them.
  const FLANK_SUPPORT_RADIUS = 2.5  // "at its shoulder"
  const flankBonus = (target: FieldUnit): number => {
    let onIt = 0
    for (const e of units) {
      if (e.dead || e.side === target.side) continue
      if (dist(e.pos, target.pos) <= FLANK_ENGAGE_RADIUS) onIt++
    }
    if (onIt < 2) return 0
    for (const a of units) {
      if (a.dead || a.side !== target.side || a.id === target.id) continue
      if (dist(a.pos, target.pos) <= FLANK_SUPPORT_RADIUS) return 0 // supported
    }
    return FLANK_ACC_BONUS
  }
  const vis = new Map<string, UnitVisState>(units.map((u) => [u.id, 'idle']))
  // Total damage each side has dealt, and the side that landed the most recent
  // blow — the fair, deterministic tiebreaks when a fight ends in a simultaneous
  // double-death (both sides' last unit dying the same tick, which hard collision
  // made more likely by keeping fights closer). Damage decides first; a perfect
  // damage tie falls to whoever struck last (hits resolve in unit order, so this
  // is always well-defined and effectively never ties).
  const dmgDealt = { A: 0, B: 0 }
  let lastAggressor: FieldSide | null = null

  const living = (side: FieldSide) => units.filter((u) => u.side === side && !u.dead)
  let tick = 0
  let winner: FieldSide | 'draw' = 'draw'

  // Enforce non-overlap at SETUP too: a custom placement (hex deployment) or a
  // tight auto-placement must not start two monsters on the same spot.
  resolveCollisions()

  for (; tick < MAX_TICKS; tick++) {
    const t = +(tick * DT).toFixed(2)

    if (!living('A').length || !living('B').length) {
      winner = living('A').length ? 'A' : living('B').length ? 'B' : 'draw'
      break
    }

    for (const u of units) {
      if (u.dead) { vis.set(u.id, 'dead'); continue }


      // ── TIMERS AND ATTRITION ──────────────────────────────────────────────
      // ⚠️ THE ARITHMETIC LIVES IN `tickMath.ts:tickUnit` and is pinned by the port contract.
      // What stays here is what a pure function cannot own: the engine's own steering timers,
      // the forced-target link (it needs the unit index to see whether its victim died), and
      // the death EVENT.
      //
      // ⚠️ AND THIS BLOCK RUNS BEFORE THE KNOCKBACK BLOCK, WHICH IS LOAD-BEARING. Placing the
      // shove above these timers once took the duel-melee golden from 15s to 91.5s: pausing
      // every clock for a 0.25s stagger turned a stagger into a fight-long stalemate. Being
      // shoved costs you tempo, never your recovery.
      u.retargetIn -= DT
      u.rootedFor = Math.max(0, u.rootedFor - DT)
      u.slowFor = Math.max(0, u.slowFor - DT)
      u.disengageFor = Math.max(0, u.disengageFor - DT)
      if (u.slowFor <= 0) u.slowMult = 1
      if (u.forcedTargetId && (t >= u.forcedUntil || byId.get(u.forcedTargetId)?.dead)) {
        u.forcedTargetId = null
      }
      const tick0 = tickUnit({
        dt: DT, now: t, hp: u.hp, maxHp: u.maxHp, mp: u.mp, maxMp: u.maxMp,
        wis: u.m.stats.WIS ?? 0, isSupport: manaRoleOf(u.m) === 'support',
        statuses: u.statuses, mods: u.mods, cooldowns: u.cooldowns,
        ccResist: u.ccResist, lastCcAt: u.lastCcAt,
      })
      u.cooldowns = tick0.cooldowns
      u.mp = tick0.mp
      u.hp = tick0.hp
      u.statuses = tick0.statuses
      u.mods = tick0.mods as typeof u.mods
      u.ccResist = tick0.ccResist
      if (tick0.dead) {
        u.dead = true
        vis.set(u.id, 'dead')
        events.push({ t, kind: 'death', id: u.id })
      }
      if (u.dead) { vis.set(u.id, 'dead'); continue }

      // ── KNOCKBACK ─────────────────────────────────────────────────────────
      // ⚠️ AFTER THE TIMERS, BEFORE THE DECISION — and the order is load-bearing
      // in both directions. Being shoved is a brief loss of control: no casting,
      // no steering, no retreat decision, the unit is travelling and that is all.
      // But it is NOT a stun: cooldowns, mana, HP regen and status durations all
      // tick first, so a stagger costs you tempo without also freezing your
      // recovery. This block was first placed ABOVE the timers and the duel-melee
      // golden went 15s -> 91.5s — knockbacks are frequent enough that pausing
      // every clock turned a 0.25s stagger into a fight-long stalemate.
      if (u.shoveTo && t < u.shoveUntil) {
        const left = dist(u.pos, u.shoveTo)
        if (left > 0.05) {
          const step = Math.min(left, KNOCKBACK_SPEED * DT)
          const dir = norm(sub(u.shoveTo, u.pos))
          const cand = clampToField({ x: u.pos.x + dir.x * step, y: u.pos.y + dir.y * step })
          // ⚠️ A SHOVE COLLIDES. Assigning the destination let a knockback post a
          // unit straight through a pillar; a body slammed into a wall now stops
          // at the wall, which is both correct and what makes cover feel solid.
          if (obstacles.some((o) => insideObstacle(cand, o, u.radius * 0.6))) {
            u.shoveTo = null
          } else {
            u.pos = cand
          }
          u.castMoveId = null
          u.castTargetId = null
          u.castingFor = 0
          vis.set(u.id, 'hurt')
          continue
        }
        u.shoveTo = null
      }
      if (u.shoveTo && t >= u.shoveUntil) u.shoveTo = null

      // HARD CONTROL. A stun does not merely stop the next action — it BREAKS
      // the cast in progress, which is the whole counterplay to a long wind-up
      // like Meteor. Without the interrupt, control would be strictly worse
      // against the moves it most needs to answer.
      if (statusFlag(u, 'incapacitates')) {
        u.castingFor = 0
        u.castMoveId = null
        vis.set(u.id, 'idle')
        continue
      }

      // CHARM turns a monster on its own side: the list it treats as hostile is
      // swapped wholesale, so targeting, steering and threat all follow without
      // any of them needing to know charm exists.
      const charmed = statusFlag(u, 'turncoat')
      const own = units.filter((x) => x.side === u.side)
      const opp = units.filter((x) => x.side !== u.side)
      const foes = charmed ? own.filter((x) => x.id !== u.id) : opp
      const mates = charmed ? opp : own

      // Commit to a target for RETARGET_EVERY, unless it died.
      // ── STICKY ENGAGEMENT ──────────────────────────────────────────────────
      // A melee unit that is already ON its target does not go target-shopping
      // when the window elapses — it stays and trades until the target falls (or
      // a taunt/charm/fear forces it off). This is what turns the fight from a
      // churn of re-picked targets into a committed brawl. Non-melee, and any
      // unit not yet in contact, re-evaluate normally.
      const cur = u.targetId ? byId.get(u.targetId) : null
      // ⚠️ YOU CANNOT BE "ENGAGED" WITH SOMEONE WHO IS NO LONGER YOUR ENEMY.
      // Sticky engagement stops a melee unit jittering between equidistant foes,
      // but it keyed only on distance — so a CHARMED monster stayed locked on the
      // target it had before its allegiance flipped and never re-picked. Charm
      // silently did nothing to a melee unit already in contact.
      // Latent since sticky engagement landed, and exposed by melee reach going
      // 1.6 -> 3.0: the window is `reach + 1.5`, so it widened from 3.1 to 4.5
      // units and swallowed the re-target that used to rescue this by accident.
      const engaged = !!cur && !cur.dead && isMelee(u) && foes.includes(cur)
        && dist(u.pos, cur.pos) <= reachOf(u) + 1.5

      // ── GIVING UP A CHASE ─────────────────────────────────────────────────
      // Progress is measured against the CLOSEST this unit has ever come to
      // this target, not against last tick — otherwise a pursuer that is being
      // kited in a circle registers "progress" on every inward arc and chases
      // forever, which is the exact behaviour this exists to stop.
      let abandoned = false
      if (cur && !cur.dead && !engaged) {
        const d = dist(u.pos, cur.pos)
        if (d < u.chaseBest - PURSUIT_PROGRESS) { u.chaseBest = d; u.chaseFor = 0 }
        else u.chaseFor += DT
        if (u.chaseFor >= PURSUIT_PATIENCE) {
          // ⚠️ NEVER ABANDON THE LAST ONE. With nobody else to turn to, giving
          // up is just refusing to fight, and the battle runs to sudden death.
          const others = foes.filter((f) => !f.dead && f.id !== cur.id
            && (u.gaveUp[f.id] ?? 0) <= t)
          if (others.length) {
            u.gaveUp[cur.id] = t + PURSUIT_IGNORE
            u.targetId = null
            abandoned = true
            events.push({ t: +t.toFixed(2), kind: 'giveup', id: u.id, targetId: cur.id })
          }
          u.chaseFor = 0
        }
      }

      if (!cur || cur.dead || abandoned || (u.retargetIn <= 0 && !engaged)) {
        // A taunt still overrides this below; the ignore list only filters the
        // unit's OWN judgement.
        const open = foes.filter((f) => (u.gaveUp[f.id] ?? 0) <= t)
        const pick = pickTarget(u, open.length ? open : foes, mates, t, navLos)
        if (pick?.id !== u.targetId) { u.chaseFor = 0; u.chaseBest = Infinity }
        u.targetId = pick?.id ?? null
        u.retargetIn = RETARGET_EVERY
      }
      // A TAUNT outranks the unit's own judgement — that is the whole point of
      // one. Charm wins over it, because charm already swapped which side
      // counts as hostile and a taunter on the far team is no longer reachable.
      const forced = u.forcedTargetId ? byId.get(u.forcedTargetId) : null
      if (forced && !forced.dead && foes.includes(forced)) u.targetId = forced.id
      const target = u.targetId ? byId.get(u.targetId) ?? null : null

      // KITE BUDGET. Drains while a threat is in kite range (whether or not the
      // unit actually gives ground this tick), refills once it is clear — so a
      // ranged unit backpedals briefly, then must plant and fight (or use cover).
      u.kiteFor = target && wantsToKite(u, target)
        ? Math.max(0, u.kiteFor - DT)
        : Math.min(KITE_MAX, u.kiteFor + DT * KITE_REFILL)

      // A committed cast roots the unit — this is the window a diver punishes.
      if (u.castingFor > 0) {
        u.castingFor -= DT
        vis.set(u.id, 'cast')
        if (u.castingFor <= 0 && u.castMoveId) {
          const aim = byId.get(u.castTargetId ?? '') ?? target
          if (aim && !aim.dead) resolveHit(u, aim, u.castMoveId)
          else { u.castMoveId = null; u.castTargetId = null }
        }
        continue
      }

      if (!target) { vis.set(u.id, 'idle'); continue }

      // Act if something is in range; otherwise reposition.
      // real skill first, else the basic attack if the target is within ITS reach
      // FEAR is a rout, not a stun: the victim keeps moving — away — but cannot
      // bring itself to turn and fight. SILENCE locks the skills only, leaving
      // the free attack, so a silenced monster is diminished rather than absent.
      const routed = statusFlag(u, 'noAttack')
      const silenced = statusFlag(u, 'noSkills')
      // Settle the DAMAGE option first — best skill, else the free attack —
      // then let utility try to beat it. ⚠️ Scoring utility against the skill
      // alone made the bar zero whenever every skill was on cooldown, so a
      // near-worthless buff pre-empted the basic attack and War Cry took 137 of
      // 254 utility casts. The bar is whatever the unit would otherwise DO.
      let mv: Move | null = routed || silenced ? null : chooseMove(u, target, obstacles)
      if (!mv && !routed) {
        const ba = basicAttackFor(u.m)
        const inReach = dist(u.pos, target.pos) <= (ba.range ?? CHANNEL_RANGE.melee)
        const canSee = ba.channel === 'melee' || hasLineOfSight(u.pos, target.pos, obstacles)
        if (inReach && canSee && (u.cooldowns.basic ?? 0) <= 0) mv = ba
      }
      // ⚠️ BRACING MUST BE ABLE TO BEAT THE FREE ATTACK, or it can never happen:
      // the basic re-arms every 0.55s, so "nothing else to do" — the only state
      // that used to reach the brace branch — effectively stopped existing when
      // that cooldown dropped. A real SKILL still always wins; it is only the
      // filler that a hurt, swarmed monster should decline in favour of covering
      // up. Available to EVERY class, not just anchors: `preserve` tunes when,
      // and a badly hurt monster braces on instinct even with no order set.
      if (mv && mv.id === 'basic' && wouldBrace(u, foes, t)) mv = null

      let aim: FieldUnit = target
      if (!routed && !silenced) {
        // Utility competes with damage on the SAME scale, so the better answer
        // to the situation wins outright — no priority order to get wrong. The
        // floor stops a unit with nothing better to do burning cooldowns on
        // effects worth almost nothing.
        const best = bestUtility(u, target, mates, foes, obstacles, t)
        if (best && best.score > Math.max(UTILITY_FLOOR, mv?.power ?? 0)) { mv = best.mv; aim = best.aim }
      }
      // ⚠️ THE SCRIPTED OPENER WINS OUTRIGHT, and only for its first actions. It is
      // an explicit instruction — "open with this" — so it must beat both pickers
      // rather than compete with them on score; a nudge would be indistinguishable
      // from not having set one. It sits BELOW the utility block for that reason.
      let openerFired = false
      if (u.openerQueue.length && t > OPENER_WINDOW) u.openerQueue.length = 0
      if (!routed && !silenced && u.openerQueue.length) {
        const om = u.m.loadout.find((x) => x.id === u.openerQueue[0])
        if (om && (u.cooldowns[om.id] ?? 0) <= 0 && u.mp >= mpCost(om)
          && dist(u.pos, target.pos) <= rangeOf(om)
          && (om.channel === 'melee' || hasLineOfSight(u.pos, target.pos, obstacles))
        ) { mv = om; aim = target; openerFired = true }
      }
      if (mv) {
        // ⚠️ AN ID IS SPENT ONLY WHEN IT FIRES — see OPENER_WINDOW for why the
        // turn engine's spend-per-action rule cannot be ported. Two earlier
        // builds both measured bit-identical to having no order set: one spent an
        // id per decision TICK (queue empty 0.2s in, mid-walk), the next spent one
        // per cast (burned on the t=0 team buff every ranged unit opens with).
        if (openerFired) u.openerQueue.shift()
        u.castingFor = castOf(mv)
        u.castMoveId = mv.id
        u.castTargetId = aim.id
        u.cooldowns[mv.id] = mv.cooldown * COOLDOWN_MULT + castOf(mv)
        u.mp = Math.max(0, u.mp - mpCost(mv))
        events.push({ t, kind: 'cast', id: u.id, targetId: aim.id, move: mv.name, channel: mv.channel })
        applyCasterMovement(u, aim, mv, t, obstacles)
        applySelfEffects(u, aim, mv, t)
        vis.set(u.id, 'cast')
        // Instant moves land the same tick they are cast.
        if (u.castingFor <= 0) { resolveHit(u, aim, mv.id); u.castMoveId = null; u.castTargetId = null }
        continue
      }

      // MOVE. Steer toward the goal, slide off obstacles, keep off allies.
      // A ROOTED unit may still act — it simply cannot travel, which is what
      // makes a root a genuine answer to a fast diver rather than a stun.
      if (u.rootedFor > 0) { vis.set(u.id, 'idle'); continue }

      // ── FALL BACK ─────────────────────────────────────────────────────────
      // ⚠️ GATED ON A TRIGGER, NOT JUST A TIMER. With a bare cooldown a unit
      // burns it wandering at full health and has nothing left when it is
      // actually being killed, which is the one moment it exists for.
      const nearestFoeD = foes.reduce((m, f) =>
        f.dead ? m : Math.min(m, dist(u.pos, f.pos)), Infinity)
      // ⚠️ THE LAST MONSTER STANDING DOES NOT FALL BACK. A lone survivor under
      // FALL_BACK_HP falls back to cover, waits out FALL_BACK_CD, and — still under
      // the threshold, because nothing healed it — falls back again, for the rest of
      // the fight. That is the retreat loop a player sees at the exact moment they
      // are watching most closely, and it cannot resolve on its own: the condition
      // that triggers it is the condition it leaves you in.
      //
      // ⚠️ THIS IS THE SECOND OF TWO INDEPENDENT RETREAT MECHANICS and gating only
      // the other one was NOT ENOUGH — measured, 39 → 33 lone fallbacks, because
      // most of them were never coming from `decide.ts:retreatThreatOf` at all. The
      // same duplicate-mechanic trap as `reachOf` and the class basic attack: fixing
      // the copy you happened to find first looks like a fix and is not one. If a
      // third retreat path is ever added, it needs this rule too.
      //
      // ⚠️ AI RETREAT ONLY. An escape ABILITY is chosen by the move system and never
      // reaches here, so a monster that brought Disengage or Shadowstep still uses it
      // while alone — and now MORE readily, because a lone unit no longer burns the
      // SHARED `escapeLockUntil` on an automatic fallback it was never going to
      // benefit from. Spending a real card to break contact is a decision; drifting
      // backwards on a timer is not.
      const hasAlly = mates.some((a) => !a.dead && a.id !== u.id)
      const wantsOut = hasAlly && (u.hp / u.maxHp < FALL_BACK_HP
        || (nearestFoeD <= FALL_BACK_NEAR && archetypeOf(u) !== 'anchor'))
      if (wantsOut && t >= u.fallBackAt && t >= u.escapeLockUntil
        && u.fallBackUntil <= t && Number.isFinite(nearestFoeD)) {
        u.fallBackUntil = t + FALL_BACK_DUR
        u.fallBackAt = t + FALL_BACK_CD
        // ⚠️ The lockout is SHARED. An escape ABILITY will set the same field,
        // so the two tiers cannot be spent in the same breath — see §5.
        u.escapeLockUntil = t + ESCAPE_LOCKOUT
        // ⚠️ THE DESTINATION IS CHOSEN HERE, ONCE. Re-scoring it every tick as
        // the threat moves makes a "committed" retreat oscillate on the spot.
        const near = foes.filter((f) => !f.dead)
          .sort((a, b) => dist(u.pos, a.pos) - dist(u.pos, b.pos))[0]
        u.fallBackTo = near
          ? bestCoverPoint(
            u.pos, near.pos, u.speed * FALL_BACK_DUR * 1.4, navGraph, navLos,
            mates.filter((a) => !a.dead && a.id !== u.id).map((a) => a.pos))
          : null
        events.push({ t: +t.toFixed(2), kind: 'fallback', id: u.id })
      }

      // A dash in flight owns the unit's movement until it lands or times out.
      if (u.dashTo && t < u.dashUntil && dist(u.pos, u.dashTo) > 0.4) {
        stepToward(u, u.dashTo, mates, obstacles, t)
        vis.set(u.id, 'move')
        continue
      }
      u.dashTo = null

      let goal = desiredGoal(u, target, mates, foes, (a, b) => hasLineOfSight(a, b, obstacles))
      // A committed retreat overrides the ordinary goal: get away from whatever
      // is closest, for as long as it lasts.
      if (u.fallBackUntil > t) {
        if (u.fallBackTo) {
          // Round the pillar rather than away from the attacker.
          goal = u.fallBackTo
        } else {
          // ⚠️ No cover worth taking — degrade to the old straight-line retreat.
          // On a bare arena this is every time, which is the point: the ground
          // decides how strong a retreat is, not a constant.
          const near = foes.filter((f) => !f.dead)
            .sort((a, b) => dist(u.pos, a.pos) - dist(u.pos, b.pos))[0]
          if (near) {
            const away = norm(sub(u.pos, near.pos))
            goal = clampToField({ x: u.pos.x + away.x * 10, y: u.pos.y + away.y * 10 })
          }
        }
      }
      // THE THREE SPATIAL STATUSES. On the field these words can mean something
      // a turn counter cannot express, so they hijack the goal outright rather
      // than rolling a chance to misbehave.
      const steer = steeringStatus(u)
      if (steer) {
        const src = byId.get(steer.from)
        if (steer.steer === 'flee' && src) {
          // Run. Straight away from whatever frightened it, to the field edge.
          const away = norm(sub(u.pos, src.pos))
          goal = clampToField({ x: u.pos.x + away.x * FIELD_W, y: u.pos.y + away.y * FIELD_W })
        } else if (steer.steer === 'toSource' && src) {
          goal = { ...src.pos }
        } else if (steer.steer === 'veer') {
          // Walk the wrong way: the heading is rotated, so it still travels
          // with purpose — it is simply mistaken about where it is going.
          const d = sub(goal, u.pos)
          const a = CONFUSION_VEER * veerSign(u)
          const rx = d.x * Math.cos(a) - d.y * Math.sin(a)
          const ry = d.x * Math.sin(a) + d.y * Math.cos(a)
          goal = clampToField({ x: u.pos.x + rx, y: u.pos.y + ry })
        }
      }
      // SUDDEN DEATH FORCES THE FIGHT. Once the clock turns lethal, kiting and
      // archetype spacing are overridden — every unit (not being steered by a
      // status) drives straight at its target. Without this, two teams that both
      // want distance can stand off until the chip wipes them simultaneously — a
      // zero-engagement draw no tiebreak can resolve. The walls close in.
      if (t >= SUDDEN_DEATH_AT && target && !steer) {
        goal = { ...target.pos }
      }

      // BLOCK — the free defensive action, the half of "Attack + Block" the field
      // engine never had. A unit already in reach of its target with nothing off
      // cooldown BRACES instead of walking off, which is what it used to do for
      // want of any other option (13.8% of all unit-ticks measured pacing in
      // range). Holding position IS the fix; the damage reduction is the reward.
      // ⚠️ Never overrides a STEERING status (a feared monster must still run) and
      // never applies once SUDDEN DEATH is forcing the fight — both of those exist
      // to stop stand-offs, and blocking through them stalls fights into draws.
      // ⚠️ Also requires LINE OF SIGHT: a ranged unit whose shot is blocked by a
      // rock cannot cast, and if it braced on that it would stand behind cover
      // forever instead of stepping out for an angle. Brace only when you could
      // genuinely fight from here and are merely waiting on a cooldown.
      if (!routed && !steer && t < SUDDEN_DEATH_AT && target
        // ⚠️ NO slack on the range: bracing even slightly outside what it can
        // actually cast at deadlocks the unit — it holds just out of its own
        // reach and never closes the last step.
        && dist(u.pos, target.pos) <= reachOf(u)
        && (isMelee(u) || hasLineOfSight(u.pos, target.pos, obstacles))) {
        // ⚠️ HOLDING and BLOCKING are different things. Any unit that is in reach
        // and merely waiting on a cooldown HOLDS its ground (that is what stops
        // the pacing) — but the damage reduction is EARNED, not free: only an
        // anchor/tank, or a monster whose `preserve` order has actually tripped
        // at its current HP, braces. Everything else simply stands ready to swing.
        const pres = u.m.tactics?.preserve ?? 'off'
        const presAt = pres === 'defensive' ? 0.25 : pres === 'cautious' ? 0.4 : 0
        const guarding = archetypeOf(u) === 'anchor' || (presAt > 0 && u.hp / u.maxHp < presAt)
        if (guarding) { u.blockingUntil = t + DT * 2; vis.set(u.id, 'block') }
        else vis.set(u.id, 'idle')
        continue
      }
      // ⚠️ THE ONLY LINE THAT CHANGES FOR PATHFINDING. The global layer picks
      // which way round the cover; the local layer below still owns separation,
      // backpedal, collision-slide and the escape scan. Everything tuned into
      // stepToward survives untouched.
      stepToward(u, nextWaypoint(u.pos, goal, navGraph, navLos), mates, obstacles, t)
      vis.set(u.id, 'move')
    }

    // HARD COLLISION. `stepToward`'s separation is only a soft steering force, so
    // units still overlap when they converge. This pass runs once everyone has
    // moved and pushes overlapping pairs apart until no two share space — a
    // monster pinned by several attackers settles adjacent to all of them.
    resolveCollisions()

    // ZONES tick on everyone standing in them, friend or foe as appropriate.
    for (let i = zones.length - 1; i >= 0; i--) {
      const z = zones[i]
      if (t >= z.until) { zones.splice(i, 1); continue }
      for (const u of units) {
        if (u.dead || dist(u.pos, z) > z.r + u.radius) continue
        if (z.effect === 'heal') {
          if (u.side !== z.side) continue
          if (statusFlag(u, 'blockHeal')) continue
          u.hp = Math.min(u.maxHp, u.hp + z.power * DT)
        } else if (z.effect === 'slow') {
          if (u.side === z.side) continue
          u.slowMult = Math.min(u.slowMult, z.power)
          u.slowFor = Math.max(u.slowFor, 0.4)
        } else {
          if (u.side === z.side) continue
          u.hp -= z.power * DT
          if (u.hp <= 0) {
            u.hp = 0; u.dead = true; vis.set(u.id, 'dead')
            events.push({ t, kind: 'death', id: u.id })
          }
        }
      }
    }

    // SUDDEN DEATH — the clock itself starts killing, harder every second, so
    // no pair of teams can stall each other past the cap.
    if (t >= SUDDEN_DEATH_AT) {
      for (const u of units) {
        if (u.dead) continue
        u.hp -= suddenDeathLoss(t, u.maxHp, DT)
        if (u.hp <= 0) {
          u.hp = 0; u.dead = true; vis.set(u.id, 'dead')
          events.push({ t, kind: 'death', id: u.id })
        }
      }
    }

    // One positional snapshot per tick for the renderer to interpolate.
    events.push({
      t, kind: 'snapshot',
      units: units.map((u) => {
        const fx = effectIcons(u)
        return {
          id: u.id, x: +u.pos.x.toFixed(2), y: +u.pos.y.toFixed(2),
          // ⚠️ Was a CONSTANT per side, so a monster always faced the same way
          // however it moved — a retreating unit was drawn facing its attacker
          // while sliding backwards, which is most of what "springing backwards"
          // actually was. Still ±1 (the renderer flips the sprite), but now taken
          // from travel; a unit that is not moving keeps its side's default.
          facing: Math.abs(u.vel.x) > 1e-3
            ? (u.vel.x > 0 ? 1 : -1)
            : (u.side === 'A' ? 1 : -1),
          state: vis.get(u.id) ?? 'idle',
          targetId: u.targetId ?? null,
          hp: Math.round(u.hp), maxHp: Math.round(u.maxHp),
          mp: Math.round(u.mp), maxMp: Math.round(u.maxMp),
          buffs: fx.buffs, debuffs: fx.debuffs,
        }
      }),
    })
  }

  if (winner === 'draw' && living('A').length !== living('B').length) {
    winner = living('A').length > living('B').length ? 'A' : 'B'
  }
  // Still a draw = a genuine simultaneous wipe. Break it by who dealt more total
  // damage — the side that was fighting harder takes it. Deterministic, and only
  // a perfect damage tie (vanishingly rare) stays a draw.
  if (winner === 'draw' && dmgDealt.A !== dmgDealt.B) {
    winner = dmgDealt.A > dmgDealt.B ? 'A' : 'B'
  }
  // Last resort — a perfect damage tie: the side that landed the final blow.
  if (winner === 'draw' && lastAggressor) winner = lastAggressor
  events.push({ t: +(tick * DT).toFixed(2), kind: 'end', winner })

  return {
    winner, events,
    duration: +(tick * DT).toFixed(2),
    survivorsA: living('A').length,
    survivorsB: living('B').length,
  }

  // ── inner helpers (close over rng/events/units) ───────────────────────────
  /**
   * Everyone an AREA move actually catches, in fixed unit order so the result
   * stays deterministic. A shape centred on 'self' radiates from the caster (a
   * scream cannot be aimed at a spot); one centred on 'target' lands where the
   * victim is standing, which is what makes clumping dangerous.
   */
  /**
   * Everyone a TEAM effect actually reaches: allies within TEAM_AURA_RADIUS of
   * the caster. Replaces four identical `x.side === u.side` filters that had no
   * distance term at all, so an aura crossed the whole field.
   */
  function teamCrowd(u: FieldUnit, mv: Move, aim: FieldUnit): FieldUnit[] {
    if (mv.target !== 'team') return [aim]
    return units.filter((x) => x.side === u.side && !x.dead
      && dist(u.pos, x.pos) <= TEAM_AURA_RADIUS)
  }

  function areaVictims(u: FieldUnit, target: FieldUnit, area: MoveArea): FieldUnit[] {
    const origin = area.centre === 'self' ? u.pos : target.pos
    // ⚠️ SIDE-AWARE. This hard-coded `x.side !== u.side`, so a friendly area
    // effect — a group heal, a ward zone — had no geometry and simply could not
    // exist. A shape does not care whose side it is on; who it CATCHES does.
    const friendly = u.side === target.side
    const foes = units.filter((x) => (friendly ? x.side === u.side : x.side !== u.side) && !x.dead)
    if (area.shape === 'circle') {
      const r = area.radius ?? 4
      return foes.filter((f) => dist(origin, f.pos) <= r + f.radius)
    }
    if (area.shape === 'cone') {
      const reach = area.range ?? 4
      const half = ((area.angle ?? 90) / 2) * (Math.PI / 180)
      const facing = norm(sub(target.pos, u.pos))
      return foes.filter((f) => {
        const d = dist(origin, f.pos)
        if (d > reach + f.radius || d < 1e-6) return false
        const to = norm(sub(f.pos, origin))
        return Math.acos(Math.max(-1, Math.min(1, to.x * facing.x + to.y * facing.y))) <= half
      })
    }
    // line: everything within `width` of the segment from the caster outward.
    const reach = area.range ?? 8
    const halfW = (area.width ?? 2) / 2
    const dir = norm(sub(target.pos, u.pos))
    return foes.filter((f) => {
      const rel = sub(f.pos, u.pos)
      const along = rel.x * dir.x + rel.y * dir.y
      if (along < 0 || along > reach) return false
      const perp = Math.abs(rel.x * -dir.y + rel.y * dir.x)
      return perp <= halfW + f.radius
    })
  }

  /** The best utility cast available to this unit right now, if any. */
  /**
   * A move that puts HP back — direct (`power` on a friendly) or over time.
   * ⚠️ A `function`, not a `const` arrow: `bestUtility` is hoisted and called
   * from the tick loop far above this line, so an arrow here is in its temporal
   * dead zone and throws on the first utility cast of the first fight.
   */
  function isRestore(mv: Move) {
    return (mv.target === 'ally' || mv.target === 'team' || mv.target === 'self')
      && ((mv.power ?? 0) > 0 || !!mv.effects?.hpRegenBuff)
  }

  function bestUtility(u: FieldUnit, target: FieldUnit, mates: FieldUnit[], foes: FieldUnit[], obs: Obstacle[], tNow: number) {
    let best: { mv: Move; aim: FieldUnit; score: number } | null = null
    for (const mv of u.m.loadout) {
      if (mv.type === 'damage') continue
      if ((u.cooldowns[mv.id] ?? 0) > 0) continue
      if (u.mp < mpCost(mv)) continue
      // ⚠️ THE LOCKOUT MUST BLOCK AS WELL AS BE SPENT, or it is one-directional:
      // Fall Back would lock the ability but the ability could still be fired
      // the instant after a Fall Back, which is the exact two-in-two-seconds
      // burst the constant exists to prevent.
      if (isEscapeMove(mv) && u.escapeLockUntil > tNow) continue
      const got = utilityScore(u, mv, mates, foes)
      if (!got) continue
      // ⚠️ TRIAGE. A restore is held until someone actually needs it. Heals used
      // to be scored alongside buffs and fired at full health, which is wasted
      // throughput — the leading explanation for why three HEAL_MULT A/Bs all
      // read null while support sides got FASTER with stronger healing. Gated
      // here rather than in `utilityScore` because the recipient is only known
      // once a target has been chosen. `healPolicy: 'steady'` opts out.
      if ((u.m.tactics?.healPolicy ?? DEFAULT_TACTICS.healPolicy) === 'triage'
        && isRestore(mv) && got.aim.side === u.side
        && got.aim.hp / got.aim.maxHp > TRIAGE_AT) continue
      // Same reach and cover rules as a damage cast — a support cannot heal
      // through a rock any more than a mage can burn through one.
      // ⚠️ DO NOT RE-APPLY AN EFFECT THAT IS STILL RUNNING. `modAtk` multiplies and
      // the rest add, so a re-cast COMPOUNDS rather than refreshing — and 17 pool
      // moves re-arm before their own duration ends, so this was not an edge case:
      // Brace (6s guard, 3.0s recharge) sat permanently double-stacked. Caught in
      // the grind-lock trace, where a unit with no reachable target cast Enrage 27
      // times in 197 seconds.
      //
      // ⚠️ KEYED ON THE MOVE, NOT THE EFFECT. Two DIFFERENT moves granting atk are
      // meant to stack — that is what makes a Captain worth fielding beside a
      // Warcry. Only a move re-applying its own live mod is blocked.
      if (got.aim.mods.some((md) => md.src === mv.id && md.until > tNow)) continue
      if (dist(u.pos, got.aim.pos) > rangeOf(mv)) continue
      if (mv.channel !== 'melee' && got.aim.id !== u.id && !hasLineOfSight(u.pos, got.aim.pos, obs)) continue
      if (!best || got.score > best.score) best = got
    }
    void target
    return best
  }

  /** How a non-damage cast lands: healing, then its spatial and status riders. */
  function resolveUtility(u: FieldUnit, aim: FieldUnit, mv: Move, t2: number) {
    const sp = spatialOf(mv.name)
    const friendly = aim.side === u.side
    const fx = mv.effects
    // ⚠️ UNITS ARE NOT UNIFORM (see CLAUDE.md): `atkBuff`/`atkDebuff` are
    // FRACTIONS, `defBuff` is percentage POINTS. Reading either as the other
    // compiles, runs, and is wrong by a factor of a hundred.
    const until = t2 + (fx?.duration ?? 3) * SECONDS_PER_ROUND
    if (fx?.atkBuff && friendly) {
      const crowd = teamCrowd(u, mv, aim)
      for (const v of crowd) v.mods.push({ src: mv.id, atk: 1 + fx.atkBuff, until })
    }
    if (fx?.defBuff && friendly) {
      const crowd = teamCrowd(u, mv, aim)
      for (const v of crowd) v.mods.push({ src: mv.id, dmgTaken: Math.max(0.4, 1 - fx.defBuff / 100), until })
    }
    // ── THE PREVIOUSLY-INERT DEFENSIVE / ACCURACY EFFECTS ────────────────────
    // ⚠️ These nine keys existed on 29 pool moves and 26 signature moves and did
    // NOTHING on the field — 11 moves were entirely inert, which is why a Tank
    // could not tank. Ported from the turn engine's `applyBuffTo`.
    if (friendly) {
      const crowd = teamCrowd(u, mv, aim)
      for (const v of crowd) {
        if (fx?.ward) v.ward += fx.ward // an absorb POOL, not a timed mod
        if (fx?.guard) v.mods.push({ src: mv.id, guard: fx.guard, until })
        if (fx?.thorns) v.mods.push({ src: mv.id, thorns: fx.thorns, until })
        if (fx?.dodgeBuff) v.mods.push({ src: mv.id, dodge: fx.dodgeBuff, until })   // POINTS
        if (fx?.accBuff) v.mods.push({ src: mv.id, acc: fx.accBuff, until })         // POINTS
        // ⚠️ SCALED BY THE CASTER'S STAT, exactly as the direct heal above is.
        // The two halves of a restore must move together: when only `power`
        // scaled, Renewal (power 8, regen 10) barely improved with WIS while
        // Tranquility (power 34, no regen) tripled — the regen-led moves in a
        // line quietly fell behind their own siblings. That split was where a
        // change happened to stop, not a design choice.
        if (fx?.hpRegenBuff) {
          const scaled = fx.hpRegenBuff * (1 + (u.m.stats[mv.stat] ?? 0) * statScaleOf(mv))
          v.mods.push({ src: mv.id, hpRegen: scaled, until })
        }
        if (fx?.regenBuff) v.mods.push({ src: mv.id, regen: fx.regenBuff, until })
        // CLEANSE strips every non-beneficial status AND grants a short control
        // immunity. ⚠️ It must NOT reset `ccResist` — doing so would make
        // cleansing your own ally a DR-wipe that re-opens them to a full stun.
        // The immunity is the compensation: a real window to act, no exploit.
        if (fx?.cleanse) {
          v.statuses = v.statuses.filter((st) => BENEFICIAL.has(st.kind))
          v.ccImmuneUntil = Math.max(v.ccImmuneUntil, t2 + CLEANSE_CC_IMMUNITY)
        }
      }
    }
    if (friendly && mv.power > 0 && !statusFlag(aim, 'blockHeal')) {
      // ⚠️ A HEAL SCALES WITH ITS STAT, exactly as damage does — same helper,
      // same shape: `power * (1 + stat * statScaleOf(mv))`. It did NOT before,
      // and that was a progression hole rather than a balance choice: a WIS 400
      // healer restored precisely as much as a WIS 100 one, so training WIS
      // bought mana and regen but never a bigger heal. Every damage move in the
      // game had this axis and every heal was flat.
      //
      // ⚠️ NOT A FLAT MULTIPLIER. `HEAL_MULT` was one and was A/B'd FOUR times —
      // 1.3, 2.5, 1.3 on a richer pool, 1.3 under triage — for four nulls
      // (p = 1.00, 0.38, 0.18, 1.00), with the count of fights it could touch
      // falling 40 -> 21 -> 14 -> 12. Flat inflation could not reach; this is
      // conditional on investment, which is the difference.
      const heal = mv.power * (1 + (u.m.stats[mv.stat] ?? 0) * statScaleOf(mv))
      const healed = Math.min(heal, aim.maxHp - aim.hp)
      if (healed > 0) {
        aim.hp += healed
        events.push({ t: t2, kind: 'heal', id: u.id, targetId: aim.id, move: mv.name, amount: Math.round(healed) })
      }
    }
    if (!friendly) {
      // Debuffs respect their area shape exactly as damage does, so a shout
      // that should catch a cluster does, and a single-target root does not.
      const victims = sp?.area ? areaVictims(u, aim, sp.area)
        : mv.target === 'allEnemies' ? units.filter((x) => x.side !== u.side && !x.dead)
        : [aim]
      for (const v of victims) {
        if (v.dead) continue
        if (fx?.atkDebuff) v.mods.push({ src: mv.id, atk: Math.max(0.4, 1 - fx.atkDebuff), until })
        // ⚠️ UNITS. atkDebuff is a FRACTION (above); defDebuff and accDebuff are
        // percentage POINTS and are subtracted directly — the standing rule in
        // CLAUDE.md. defDebuff rides the `guard` mod negatively because guard IS
        // this engine's defFlat, the same quantity the turn engine decrements.
        if (fx?.defDebuff) v.mods.push({ src: mv.id, mitDebuff: fx.defDebuff, until })
        if (fx?.accDebuff) v.mods.push({ src: mv.id, acc: -fx.accDebuff, until })
        // MANA BURN — the WIS answer to a caster. Drains what is there and no
        // more, so it is never a negative pool.
        if (fx?.manaBurn) v.mp = Math.max(0, v.mp - fx.manaBurn)
        // TAUNT: forced onto the taunter, which is what makes a tank able to
        // defend a back line it is not physically standing in front of.
        if (fx?.tauntForce) { v.forcedTargetId = u.id; v.forcedUntil = until }
        if (sp) applyOnTarget(u, v, sp, t2)
        if (mv.status && !BENEFICIAL.has(mv.status.kind) && rng() * 100 < mv.status.chance) {
          applyFieldStatus(u, v, mv.status.kind, mv.status.duration, t2)
        }
      }
    } else if (mv.status && BENEFICIAL.has(mv.status.kind)) {
      // The pool's two haste moves are team buffs — the only way haste is ever
      // handed out, so without this branch the status would never once appear.
      const crowd = teamCrowd(u, mv, aim)
      for (const v of crowd) applyFieldStatus(u, v, mv.status.kind, mv.status.duration, t2)
    }
  }

  /**
   * Land an affliction. Duration is authored in ROUNDS by every move in the
   * game; this is the ONE place it becomes seconds, so the conversion can never
   * be restated inconsistently elsewhere.
   *
   * Bleed stacks (up to 3, each ticking its own damage) — everything else
   * refreshes, exactly as `battle.ts:applyStatus` does. Two engines disagreeing
   * on whether a status stacks would be a genuine balance divergence.
   */
  function applyFieldStatus(from: FieldUnit, target: FieldUnit, kind: StatusKind, rounds: number, t: number) {
    // ⚠️ THE DECISION LIVES IN `statusMath.ts`; ONLY THE MOVEMENT LIVES HERE. Whether a status
    // lands and for how long is arithmetic — diminishing returns, the CON floor, stack vs
    // refresh — and it must survive the spatial rebuild unchanged. The lurch is a position
    // write, so Godot will do it with its own navigation and its own collision.
    const out = applyStatus({
      kind, rounds, now: t, from: from.id,
      statuses: target.statuses,
      ccResist: target.ccResist,
      ccImmuneUntil: target.ccImmuneUntil,
      targetCon: target.m.stats.CON ?? 0,
      targetDead: target.dead,
    })
    // ⚠️ THE METER ADVANCES EVEN WHEN THE CONTROL FAILS, so this is written back before the
    // early return. A fully-diminished stun still costs the caster its cooldown, which is what
    // stops spam-until-it-sticks from being free.
    target.ccResist = out.ccResist
    if (out.ccMeterTouched) target.lastCcAt = t
    if (!out.applied) return
    target.statuses = out.statuses

    if (out.lurch) {
      const dir = norm(sub(from.pos, target.pos))
      const step = Math.min(out.lurch, Math.max(0, dist(from.pos, target.pos) - 1.6))
      const dest = clampToField({ x: target.pos.x + dir.x * step, y: target.pos.y + dir.y * step })
      if (step > 0 && !obstacles.some((o) => insideObstacle(dest, o, target.radius * 0.6))) {
        target.pos = dest
        events.push({ t, kind: 'shove', id: target.id, by: from.id, kind2: 'pull' })
      }
    }
    events.push({ t, kind: 'status', id: target.id, by: from.id, status: kind })
  }


  function resolveHit(u: FieldUnit, target: FieldUnit, moveId: string) {
    const mv = u.m.loadout.find((x) => x.id === moveId) ?? basicAttackFor(u.m)
    u.castMoveId = null
    u.castTargetId = null
    const t2 = +(tick * DT).toFixed(2)
    // A NON-DAMAGE move does not go through `strike` at all — it would roll
    // accuracy and mitigation against a friend. It restores, or it controls.
    if (mv.type !== 'damage') { resolveUtility(u, target, mv, t2); return }
    // AREA MOVES fan out to whoever is genuinely inside the shape, each hit
    // discounted by the existing AoE falloff so splashing six bodies is not
    // six times a single-target cast.
    const areaSpec = spatialOf(mv.name)?.area
    if (areaSpec) {
      const victims = areaVictims(u, target, areaSpec)
      if (!victims.length) {
        events.push({ t: t2, kind: 'miss', id: u.id, targetId: target.id, move: mv.name })
        return
      }
      const falloff = aoeFalloff(victims.length)
      for (const v of victims) strike(u, v, mv, t2, falloff)
      return
    }
    strike(u, target, mv, t2, 1)
  }

  function strike(u: FieldUnit, target: FieldUnit, mv: Move, t2: number, falloff: number) {
    if (target.dead) return
    // Out of range by the time it lands (the target walked away) — a real
    // miss. Area moves already resolved their own geometry, so they skip this.
    if (falloff === 1 && dist(u.pos, target.pos) > rangeOf(mv) * 1.25) {
      events.push({ t: t2, kind: 'miss', id: u.id, targetId: target.id, move: mv.name })
      return
    }
    // ⚠️ THE ARITHMETIC LIVES IN `damage.ts` AND THIS IS DELIBERATE. Godot rebuilds the
    // spatial layer natively, so the whole-fight goldens cannot be the port's acceptance
    // test — the damage MATH can, and only if it is separable from the geometry. The two
    // places this code reached into space (`isBehind`, `flankBonus`) are resolved to
    // scalars here and handed over; everything past that point is portable arithmetic.
    //
    // ⚠️ THE RNG IS DRAWN LAZILY, IN THE ORDER IT ALWAYS WAS, AND THAT IS LOAD-BEARING.
    // A miss used to return before the crit and variance draws, so drawing all three
    // eagerly would advance the shared stream on every whiff and move every golden. Draw
    // accuracy, bail on a miss exactly as before, and only then draw the other two.
    const accRoll = rng()
    const fx = mv.effects
    const sp = spatialOf(mv.name)
    const accuracy = mv.accuracy - statusAccPenalty(u) + modAcc(u) - modDodge(target)
      + flankBonus(target)
    if (accRoll * 100 > accuracy) {
      events.push({ t: t2, kind: 'miss', id: u.id, targetId: target.id, move: mv.name })
      return
    }
    const critRoll = rng()
    const varRoll = rng()
    const out = resolveStrike({
      move: mv,
      atk: u.m.stats[mv.stat] ?? 0,
      atkMult: modAtk(u),
      attackerHpFrac: u.hp / u.maxHp,
      attackerWard: u.ward,
      accPenalty: statusAccPenalty(u),
      accMod: modAcc(u),
      // Mitigation is CON against a body blow and WIS against everything else — the split
      // that makes a trained wall and a trained mind two different kinds of tough.
      defMit: mv.channel === 'melee' || mv.channel === 'ranged'
        ? target.m.stats.CON : target.m.stats.WIS,
      defMaxHp: target.maxHp,
      defHpFrac: target.hp / target.maxHp,
      defWard: target.ward,
      dodgeMod: modDodge(target),
      defStatusDmgTaken: statusDamageTaken(target),
      defDmgTakenMod: modDmgTaken(target),
      defGuard: modGuard(target),
      defMitDebuff: modMitDebuff(target),
      defBlocking: target.blockingUntil > tick * DT,
      defHasAttacked: target.hasAttacked,
      defHasBonusStatus: !!fx?.bonusVsStatus && hasStatus(target, fx.bonusVsStatus.kind),
      // BACKSTAB: the payoff for arriving behind someone, and the reason a blink is worth a
      // slot. It only pays if the caster is genuinely on the far side.
      behindMult: sp?.backstab && isBehind(u, target) ? sp.backstab : 1,
      flankBonus: flankBonus(target),
      falloff,
      now: t2,
      rolls: { acc: accRoll, crit: critRoll, variance: varRoll },
    })
    const { dmg, crit } = out
    target.ward = out.wardLeft
    target.hp -= out.toHp
    u.hasAttacked = true // drives firstStrikeMult (see damage.ts)
    // The ward is spent only now, on a blow that connected: losing a 45-point ward to a
    // whiff reads as a bug rather than as risk, which is exactly how the turn engine found it.
    if (out.spendsOwnWard) u.ward = 0
    // LIFESTEAL — WIS/CHA sustain that costs the enemy rather than a heal slot.
    // Gated on the same blockHeal flag as every other heal in this engine, so
    // healblock shuts off drain too; otherwise it would be the strictly better
    // heal and there would be no reason to run a real one.
    const steal = fx?.lifesteal ?? 0
    if (steal > 0 && dmg > 0 && !statusFlag(u, 'blockHeal')) {
      const stolen = Math.max(1, Math.round(dmg * steal))
      const gained = Math.min(stolen, u.maxHp - u.hp)
      if (gained > 0) {
        u.hp += gained
        events.push({ t: t2, kind: 'heal', id: u.id, targetId: u.id, move: mv.name, amount: gained })
      }
    }
    dmgDealt[u.side] += dmg
    lastAggressor = u.side
    // THORNS — flat damage reflected onto the attacker per hit TAKEN. Melee-range
    // only would be the alternative, but the turn engine reflects on any hit and
    // that is what makes thorns a real answer to a ranged focus. Cannot kill via
    // reflect chains: it never reflects onto a reflect.
    const thorns = modThorns(target)
    if (thorns > 0 && !u.dead && u.side !== target.side) {
      u.hp -= Math.max(1, Math.round(thorns))
      if (u.hp <= 0) { u.hp = 0; u.dead = true; events.push({ t: t2, kind: 'death', id: u.id }) }
    }
    // MANA BY ROLE (see types.ts). A damage dealer is paid for CONNECTING and a
    // tank for SOAKING, so each fuels its kit by doing its actual job — the fix
    // for physical classes having no way to afford their own physical abilities.
    // ⚠️ On the LANDED hit only, so whiffing earns nothing.
    if (manaRoleOf(u.m) === 'damage') u.mp = Math.min(u.maxMp, u.mp + MANA_ON_HIT_DEALT)
    if (manaRoleOf(target.m) === 'tank') target.mp = Math.min(target.maxMp, target.mp + MANA_ON_HIT_TAKEN)
    // An assassin breaks off after landing a blow (melee only — a ranged unit
    // is already at distance and kites by its own reach). This is the state the
    // 'assassin' archetype reads to dart back out before diving again.
    if (mv.channel === 'melee' && archetypeOf(u) === 'assassin') u.disengageFor = 1.4
    events.push({ t: t2, kind: 'hit', id: u.id, targetId: target.id, move: mv.name, channel: mv.channel, dmg, crit })
    // SLEEP breaks the moment it is hit — otherwise it would be a stun with a
    // longer duration and no drawback, and there would be no reason to run one.
    if (hasStatus(target, 'sleep')) target.statuses = target.statuses.filter((st) => st.kind !== 'sleep')
    // The move's own rider. Rolled AFTER the hit lands, so a miss applies
    // nothing — and never onto an ally, since a few statuses are beneficial.
    if (mv.status && u.side !== target.side && !BENEFICIAL.has(mv.status.kind)
        && rng() * 100 < mv.status.chance) {
      applyFieldStatus(u, target, mv.status.kind, mv.status.duration, t2)
    }
    // ── CONTAGION ────────────────────────────────────────────────────────────
    // The last of the twelve effects that did nothing on this engine, held back
    // deliberately so it could be simmed on its own.
    // ⚠️ ON A FIELD, CONTAGION IS A PROXIMITY MECHANIC. The turn engine spreads
    // to any N enemies because it has no geometry; here it jumps to the NEAREST
    // ones and only within CONTAGION_RADIUS, which is the whole point — it
    // punishes a clumped enemy line and does nothing against a spread one, so
    // the `spacing` tactic finally has something real to answer.
    // Rolled after the move's own status, so a cast that APPLIES the affliction
    // can spread it in the same beat.
    const spr = fx?.spreadStatus
    if (spr) {
      const carried = target.statuses.filter((st) =>
        SPREADABLE_STATUSES.has(st.kind) && (!spr.kind || st.kind === spr.kind))
      if (carried.length) {
        const picked = carried[0]
        const left = Math.max(0, picked.until - t2) / SECONDS_PER_ROUND
        const near = units
          .filter((x) => x.side !== u.side && !x.dead && x.id !== target.id
            && !hasStatus(x, picked.kind) && dist(target.pos, x.pos) <= CONTAGION_RADIUS)
          .sort((a, b) => dist(target.pos, a.pos) - dist(target.pos, b.pos))
        let jumped = 0
        for (const v of near) {
          if (jumped >= spr.targets) break
          if (rng() * 100 >= spr.chance) continue
          applyFieldStatus(u, v, picked.kind, left, t2)
          jumped++
        }
      }
    }
    if (sp) applyOnTarget(u, target, sp, t2)
    if (target.hp <= 0) {
      target.hp = 0
      target.dead = true
      vis.set(target.id, 'dead')
      events.push({ t: t2, kind: 'death', id: target.id })
    }
  }


  /**
   * Move the CASTER as part of its cast — a charge or a teleport.
   *
   * The difference between them is the whole design: a `dash` crosses the
   * ground and IS stopped by cover, so good positioning still protects you; a
   * `blink` ignores cover, which is the only way to reach a caster who has
   * correctly hidden behind a rock. That is what a teleport is FOR — and why
   * it is priced with a backstab that only pays if you actually arrive behind.
   */
  function applyCasterMovement(u: FieldUnit, target: FieldUnit, mv: Move, t: number, obs: Obstacle[]) {
    const sp = spatialOf(mv.name)
    // ⚠️ AN ESCAPE ABILITY SPENDS THE SHARED LOCKOUT, exactly as Fall Back does.
    // Independent cooldowns are the design; what must not happen is both being
    // spent in the same breath, which is what makes an assassin's commitment
    // unanswerable. See docs/PATHFINDING_DESIGN.md §5.
    if (isEscapeMove(mv)) u.escapeLockUntil = Math.max(u.escapeLockUntil, t + ESCAPE_LOCKOUT)
    if (!sp?.move) return
    const from = { ...u.pos }
    const dir = norm(sub(target.pos, u.pos))
    let dest: Vec2
    if (sp.move.to === 'behindTarget') {
      dest = { x: target.pos.x + dir.x * 1.6, y: target.pos.y + dir.y * 1.6 }
    } else if (sp.move.to === 'awayFromTarget') {
      dest = { x: u.pos.x - dir.x * sp.move.maxRange, y: u.pos.y - dir.y * sp.move.maxRange }
    } else {
      dest = { x: target.pos.x - dir.x * 1.4, y: target.pos.y - dir.y * 1.4 }
    }
    const d = dist(from, dest)
    if (d > sp.move.maxRange) {
      const k = sp.move.maxRange / d
      dest = { x: from.x + (dest.x - from.x) * k, y: from.y + (dest.y - from.y) * k }
    }
    dest = clampToField(dest)
    if (obs.some((o) => insideObstacle(dest, o, u.radius * 0.6))) return // never land inside rock
    if (sp.move.kind === 'dash' && !hasLineOfSight(from, dest, obs)) return // a charge is blocked by cover
    if (sp.move.kind === 'dash') {
      // ⚠️ TRAVEL, DO NOT SNAP. The destination is handed to the movement step
      // and crossed over ~0.2-0.5s at DASH_SPEED_MULT. Fast enough to read as a
      // lunge, slow enough to be a movement rather than a jump cut.
      u.dashTo = dest
      u.dashUntil = t + DASH_MAX_TIME
      return
    }
    u.pos = dest
    if (sp.move.kind === 'blink') {
      events.push({ t, kind: 'blink', id: u.id,
        fromX: +from.x.toFixed(2), fromY: +from.y.toFixed(2),
        toX: +dest.x.toFixed(2), toY: +dest.y.toFixed(2) })
    }
  }

  /**
   * Effects that land on the CASTER or its own side the instant it commits —
   * fading from notice, hauling an ally clear, dropping a zone.
   */
  function applySelfEffects(u: FieldUnit, target: FieldUnit, mv: Move, t: number) {
    const sp = spatialOf(mv.name)
    if (!sp) return
    if (sp.fade) u.fadedUntil = t + sp.fade.duration
    if (sp.zone) {
      const c = sp.zone.centre === 'target' ? target.pos : u.pos
      zones.push({ x: c.x, y: c.y, r: sp.zone.radius, until: t + sp.zone.duration,
        effect: sp.zone.effect, power: sp.zone.power, side: u.side })
    }
    if (sp.haulAlly) {
      // Pull the ally in the worst trouble — lowest HP fraction — to the caster.
      const mates = units.filter((x) => x.side === u.side && !x.dead && x.id !== u.id)
      const worst = mates.sort((a, b) => a.hp / a.maxHp - b.hp / b.maxHp)[0]
      if (worst && dist(worst.pos, u.pos) > 2) {
        const dir = norm(sub(u.pos, worst.pos))
        const step = Math.min(sp.haulAlly, dist(worst.pos, u.pos) - 1.6)
        const dest = clampToField({ x: worst.pos.x + dir.x * step, y: worst.pos.y + dir.y * step })
        if (!obstacles.some((o) => insideObstacle(dest, o, worst.radius * 0.6))) {
          worst.shoveTo = dest
          worst.shoveUntil = t + Math.max(KNOCKBACK_MIN_TIME, step / KNOCKBACK_SPEED)
          events.push({ t, kind: 'shove', id: worst.id, by: u.id, kind2: 'pull' })
        }
      }
    }
  }

  /** Forced movement and movement denial, landed on the target. */
  function applyOnTarget(u: FieldUnit, target: FieldUnit, sp: MoveSpatial, t: number) {
    if (sp.pull || sp.push) {
      const away = norm(sub(target.pos, u.pos))
      const shift = (sp.push ?? 0) - (sp.pull ?? 0)
      const dest = clampToField({ x: target.pos.x + away.x * shift, y: target.pos.y + away.y * shift })
      if (!obstacles.some((o) => insideObstacle(dest, o, target.radius * 0.6))) {
        // ⚠️ A DESTINATION AND A DEADLINE, never `target.pos = dest`. See
        // KNOCKBACK_SPEED in types.ts for the measurement that forced this.
        target.shoveTo = dest
        target.shoveUntil = t + Math.max(KNOCKBACK_MIN_TIME, Math.abs(shift) / KNOCKBACK_SPEED)
        events.push({ t, kind: 'shove', id: target.id, by: u.id, kind2: sp.push ? 'push' : 'pull' })
      }
    }
    if (sp.root) target.rootedFor = Math.max(target.rootedFor, sp.root)
    if (sp.slow) {
      target.slowMult = Math.min(target.slowMult, sp.slow.mult)
      target.slowFor = Math.max(target.slowFor, sp.slow.duration)
    }
  }

  function stepToward(u: FieldUnit, goal: Vec2, mates: FieldUnit[], obs: Obstacle[], now: number) {
    let dir = norm(sub(goal, u.pos))
    // Separation: don't pile into the same square metre as an ally. The
    // SPACING order widens (spread, vs AoE) or tightens (focus-fire) this.
    const personal = spacingRadius(u)
    for (const a of mates) {
      if (a.dead || a.id === u.id) continue
      const d = dist(u.pos, a.pos)
      if (d < personal && d > 1e-6) {
        const push = norm(sub(u.pos, a.pos))
        dir = { x: dir.x + push.x * 0.9, y: dir.y + push.y * 0.9 }
      }
    }
    dir = norm(dir)
    // ⚠️ TURN, DO NOT SNAP. Clamp how far the heading may swing in one tick
    // against the direction actually being travelled. Without this a unit that
    // changes its mind — a retreat triggering, a target dying, a waypoint
    // switching — pivots instantly, and instant pivots are what read as jolt.
    // A stationary unit is unclamped so it can set off in any direction.
    {
      const pm = Math.hypot(u.vel.x, u.vel.y)
      if (pm > 1e-6) {
        const cur = Math.atan2(u.vel.y, u.vel.x)
        const want = Math.atan2(dir.y, dir.x)
        let d = want - cur
        while (d > Math.PI) d -= Math.PI * 2
        while (d < -Math.PI) d += Math.PI * 2
        const max = TURN_RATE * DT
        if (Math.abs(d) > max) {
          const a = cur + Math.sign(d) * max
          dir = { x: Math.cos(a), y: Math.sin(a) }
        }
      }
    }

    // BACKPEDAL PENALTY. ⚠️ Giving ground costs speed. Without this, a fleeing
    // unit runs as fast as its pursuer, so a chase NEVER resolves — a pursuit
    // equilibrium that left units out of range 76% of the fight regardless of
    // field size or speed (both measured, both invariant). Retreating at a
    // fraction of advance speed is what lets a committed attacker actually close.
    let backpedal = 1
    {
      let nd = Infinity, nearest: FieldUnit | null = null
      for (const e of units) {
        if (e.dead || e.side === u.side) continue
        const d = dist(u.pos, e.pos)
        if (d < nd) { nd = d; nearest = e }
      }
      if (nearest) {
        const toFoe = norm(sub(nearest.pos, u.pos))
        // ⚠️ FALL BACK'S ENTIRE EFFECT IS HERE. Giving ground normally costs 40%
        // of your speed, and that penalty is what lets a committed attacker ever
        // close — without it a chase never resolves. Lifting it for two seconds
        // is what makes a retreat a retreat rather than a shuffle, and it adds
        // no new speed constant to tune.
        if (dir.x * toFoe.x + dir.y * toFoe.y < -0.25) {
          if (u.fallBackUntil <= now) backpedal = BACKPEDAL_MULT
          else {
            // Ease from the penalty up to full speed over FALL_BACK_RAMP, so a
            // retreat accelerates away rather than snapping to a sprint.
            const since = FALL_BACK_DUR - (u.fallBackUntil - now)
            const k = Math.min(1, Math.max(0, since / FALL_BACK_RAMP))
            backpedal = BACKPEDAL_MULT + (1 - BACKPEDAL_MULT) * k
          }
        }
      }
    }
    // ⚠️ A dash ignores the backpedal penalty as well as being faster: it is a
    // committed leap, not giving ground, and halving it would make Backstep
    // travel less than a walk.
    const dashing = !!u.dashTo && now < u.dashUntil
    const step = u.speed * (dashing ? DASH_SPEED_MULT : backpedal)
      * u.slowMult * statusSpeedMult(u) * DT
    const tryMove = (nx: number, ny: number) => {
      const p = { x: nx, y: ny }
      // ⚠️ A CANDIDATE THAT DOES NOT MOVE IS NOT A MOVE. Walk straight at a
      // horizontal wall and `dir.x` is ~0, so the x-slide's destination IS the
      // current position — outside the obstacle, so this returned TRUE. The unit
      // travelled zero distance AND the `&&` chain short-circuited on that
      // success, so the escape fallback below never ran. 1180 of 1219 stuck
      // ticks on The Ossuary were this: units pressed against cover (median 0.66
      // from it, pad 0.54), "succeeding" at standing still, every tick, forever.
      // The full step is unaffected — `dir` is normalised, so it always displaces
      // by `step` unless the field edge clamps it, and being clamped at the edge
      // is itself a reason to try another heading.
      if (Math.hypot(nx - u.pos.x, ny - u.pos.y) < step * 0.25) return false
      if (obs.some((o) => insideObstacle(p, o, u.radius * 0.6))) return false
      u.pos = p
      return true
    }
    const nx = Math.min(FIELD_W - 0.5, Math.max(0.5, u.pos.x + dir.x * step))
    const ny = Math.min(FIELD_H - 0.5, Math.max(0.5, u.pos.y + dir.y * step))
    // Try the full step, then slide along each axis so units round cover
    // instead of sticking to it.
    if (!tryMove(nx, ny) && !tryMove(nx, u.pos.y) && !tryMove(u.pos.x, ny)) {
      // ⚠️ FULLY BLOCKED. The old fallback was ONE perpendicular nudge with a
      // fixed handedness, so whether a unit escaped depended on which way it
      // happened to approach — and when that one attempt failed there was no
      // next one. Scan headings outward from the desired direction, alternating
      // sides, and take the first that actually moves: the unit still prefers
      // the way it wanted to go, but always has somewhere to put its feet.
      for (let k = 1; k <= 8; k++) {
        const a = (k * Math.PI) / 8
        const c = Math.cos(a)
        const sn = Math.sin(a)
        // +a then -a: rotate the desired heading, nearest angles first.
        const cands: Vec2[] = [
          { x: dir.x * c - dir.y * sn, y: dir.x * sn + dir.y * c },
          { x: dir.x * c + dir.y * sn, y: -dir.x * sn + dir.y * c },
        ]
        let moved = false
        for (const d of cands) {
          const cx = Math.min(FIELD_W - 0.5, Math.max(0.5, u.pos.x + d.x * step))
          const cy = Math.min(FIELD_H - 0.5, Math.max(0.5, u.pos.y + d.y * step))
          if (tryMove(cx, cy)) { moved = true; break }
        }
        if (moved) break
      }
    }
    u.vel = { x: dir.x * step, y: dir.y * step }
  }

  /**
   * HARD NON-OVERLAP. After every unit has moved, push apart any pair closer
   * than the sum of their radii, half the overlap each, a few iterations for
   * stability. No two living monsters may share space — they end up adjacent,
   * and several attackers converging on one target settle around it (surround)
   * rather than stacking on top of it.
   *
   * ⚠️ Deterministic: fixed unit order, no rng. The exact-overlap case (two units
   * on the same point) is separated along a FIXED axis derived from id order, so
   * a replay reproduces. A push that would land inside an obstacle is skipped for
   * that unit — the next iteration resolves it from the other side.
   */
  function resolveCollisions() {
    const live = units.filter((u) => !u.dead)
    // ⚠️ 10 iterations, not 6: sticky nearest-targeting makes several melee
    // converge and SURROUND one enemy, a tighter pack than the old churn ever
    // produced. Six passes left a squeezed pair ~1.00 apart (inside the 1.19
    // floor); ten fully separates the crowd. Still O(n²·iter), trivial at ≤12.
    for (let iter = 0; iter < 10; iter++) {
      for (let i = 0; i < live.length; i++) {
        for (let j = i + 1; j < live.length; j++) {
          const a = live[i], b = live[j]
          // ⚠️ COLLISION RADIUS < VISUAL RADIUS. A monster's `radius` (0.9) is its
          // steering/footprint size, but the sum of two full radii (1.8) once
          // exceeded the basic MELEE reach (it was 1.28 when melee was 1.6) — so if
          // collision kept them 1.8 apart, melee attackers could NEVER close to
          // hit and every melee fight would stall. Non-overlap uses a smaller
          // physical radius so units settle just inside melee reach: adjacent,
          // touching, never stacked, and still able to swing. Must stay below
          // half the basic melee reach.
          const min = (a.radius + b.radius) * COLLISION_R_FRAC
          let dx = b.pos.x - a.pos.x, dy = b.pos.y - a.pos.y
          let d = Math.hypot(dx, dy)
          if (d >= min) continue
          if (d < 1e-6) { dx = 1; dy = 0; d = 1 } // exact overlap → fixed axis
          const push = (min - d) / 2
          const nx = dx / d, ny = dy / d
          const aDest = clampToField({ x: a.pos.x - nx * push, y: a.pos.y - ny * push })
          const bDest = clampToField({ x: b.pos.x + nx * push, y: b.pos.y + ny * push })
          if (!obstacles.some((o) => insideObstacle(aDest, o, a.radius * 0.6))) a.pos = aDest
          if (!obstacles.some((o) => insideObstacle(bDest, o, b.radius * 0.6))) b.pos = bDest
        }
      }
    }
  }
}
