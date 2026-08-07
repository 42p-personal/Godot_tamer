// THE PER-TICK UNIT UPDATE, AS PURE FUNCTIONS.
//
// ⚠️ THE FOURTH AND LAST PORTABLE BLOCK. Everything here is arithmetic over TIME — cooldowns
// counting down, mana and health regenerating, damage-over-time draining, statuses expiring,
// the CC meter cooling, and the sudden-death clock. None of it touches geometry, so all of it
// survives the spatial rebuild intact and every engine needs it no matter how targeting or
// movement end up working.
//
// ⚠️ AND THE ORDER IS LOAD-BEARING, NOT INCIDENTAL. The engine's own comment records what it
// cost to learn: the knockback block was once placed ABOVE these timers and the duel-melee
// golden went from 15s to 91.5s, because pausing every clock during a 0.25s stagger turned a
// stagger into a fight-long stalemate. Timers tick FIRST; being shoved costs you tempo, not
// your recovery. Keep that order in any engine.
//
// ⚠️ PER THE STANDING RULE, THIS IS A STARTING POINT AND NOT A TARGET. The rates here are what
// the TypeScript does today. Reproduce them so a deliberate change is distinguishable from a
// translation bug, then change them freely.
import { StatusKind } from '../core'
import {
  DT, SECONDS_PER_ROUND, WIS_REGEN_DIVISOR, MANA_SUPPORT_PER_SEC, CC_DR_RESET,
  SUDDEN_DEATH_AT, SUDDEN_DEATH_BASE, SUDDEN_DEATH_RAMP,
} from './types'
import { FIELD_STATUS } from './status'
import { ActiveStatus } from './statusMath'

/** Only the fields the tick reads. The engine's `Mod` carries more; none of it matters here. */
export interface TickMod {
  until: number
  /** Mana per ROUND, paid per second. */
  regen?: number
  /** HP per ROUND, paid per second. */
  hpRegen?: number
}

export interface TickInput {
  /** Seconds elapsed this tick. */
  dt: number
  /** Now, in seconds. */
  now: number
  hp: number
  maxHp: number
  mp: number
  maxMp: number
  wis: number
  /** Mana role 'support' earns a flat trickle on top of WIS regen. */
  isSupport: boolean
  statuses: ActiveStatus[]
  mods: TickMod[]
  /** Move id -> seconds remaining. Not mutated. */
  cooldowns: Record<string, number>
  ccResist: number
  /** When control last touched this unit, in seconds. */
  lastCcAt: number
}

export interface TickOutcome {
  hp: number
  mp: number
  statuses: ActiveStatus[]
  mods: TickMod[]
  cooldowns: Record<string, number>
  ccResist: number
  dead: boolean
  /** Statuses that ran out this tick — the caller emits events for them. */
  expired: StatusKind[]
  /** HP lost to attrition and detonation this tick, before the death check. */
  attrition: number
}

const hasBlockHeal = (statuses: ActiveStatus[]): boolean =>
  statuses.some((s) => FIELD_STATUS[s.kind]?.blockHeal)

/**
 * Advance one unit by one tick.
 *
 * ⚠️ THE STEP ORDER IS THE CONTRACT. Cooldowns, then mana, then health regen, then the CC
 * meter, then attrition and expiry. Moving the attrition ahead of the regen would let a
 * damage-over-time out-race a heal that should have landed first.
 */
export function tickUnit(inp: TickInput): TickOutcome {
  const dt = inp.dt

  // ── timers ────────────────────────────────────────────────────────────────
  const cooldowns: Record<string, number> = {}
  for (const k of Object.keys(inp.cooldowns)) {
    cooldowns[k] = Math.max(0, inp.cooldowns[k] - dt)
  }

  // ── MANA REGEN ────────────────────────────────────────────────────────────
  // WIS is the caster's engine and the sole regen stat. A SUPPORT earns a steady trickle on
  // top: it neither soaks nor connects reliably, so TIME is its resource.
  // ⚠️ `regen` mods are authored per ROUND and paid per SECOND — the same translation
  // `hpRegen` gets below. Both did nothing on the field engine until that was fixed.
  const modRegen = inp.mods.reduce((n, m) => n + (m.regen ?? 0), 0)
  const regen = inp.wis / WIS_REGEN_DIVISOR
    + (inp.isSupport ? MANA_SUPPORT_PER_SEC : 0)
    + modRegen / SECONDS_PER_ROUND
  let mp = Math.min(inp.maxMp, inp.mp + regen * dt)

  // ── HP REGEN ──────────────────────────────────────────────────────────────
  // Gated on `blockHeal` like every other restore, or healblock would have a hole in it.
  let hp = inp.hp
  const modHpRegen = inp.mods.reduce((n, m) => n + (m.hpRegen ?? 0), 0)
  if (modHpRegen > 0 && !hasBlockHeal(inp.statuses)) {
    hp = Math.min(inp.maxHp, hp + (modHpRegen / SECONDS_PER_ROUND) * dt)
  }

  // ── CC METER DECAY ────────────────────────────────────────────────────────
  // The meter cools once the target has been left alone for the reset window. This is the
  // other half of diminishing returns: without it, one early stun would tax every later one
  // for the rest of the fight.
  let ccResist = inp.ccResist
  if (ccResist > 0 && inp.now - inp.lastCcAt >= CC_DR_RESET) ccResist = 0

  // ── attrition, expiry, and the one status that pays out ON expiry ─────────
  const mods = inp.mods.filter((m) => inp.now < m.until)
  let attrition = 0
  let statuses = inp.statuses
  const expired: StatusKind[] = []

  if (statuses.length) {
    for (const s of statuses) {
      const rule = FIELD_STATUS[s.kind]
      if (rule?.hpPerSec) attrition += inp.maxHp * rule.hpPerSec * dt
      // ⚠️ APPLIED IMMEDIATELY AND SEQUENTIALLY, not accumulated like the HP drain, because it
      // floors at 0 — accumulating first would let two drains take a unit below empty and then
      // clamp, which is a different number.
      if (rule?.mpPerSec) mp = Math.max(0, mp - inp.maxMp * rule.mpPerSec * dt)
    }
    // ⚠️ DOOM IS A COUNTDOWN, NOT A DRIP. It does nothing until its timer runs out and then
    // hits for a quarter of the victim's health. Cleansing it or killing the caster in time is
    // the counterplay, so it MUST resolve ON EXPIRY rather than being silently dropped by the
    // filter below.
    const done = statuses.filter((s) => inp.now >= s.until)
    for (const s of done) {
      expired.push(s.kind)
      const det = FIELD_STATUS[s.kind]?.detonate
      if (det) attrition += inp.maxHp * det
    }
    if (done.length) statuses = statuses.filter((s) => inp.now < s.until)
  }

  if (attrition > 0) hp -= attrition
  let dead = false
  if (hp <= 0) { hp = 0; dead = true }

  return { hp, mp, statuses, mods, cooldowns, ccResist, dead, expired, attrition }
}

/**
 * The clock itself starts killing, harder every second, so no pair of teams can stall each
 * other past the cap.
 *
 * ⚠️ SEPARATE FROM `tickUnit` BECAUSE THE ENGINE APPLIES IT IN A SEPARATE PASS, after every
 * unit has ticked. Folding it in would change the HP a unit dies on when attrition and the
 * clock land in the same tick.
 */
export function suddenDeathLoss(now: number, maxHp: number, dt: number = DT): number {
  if (now < SUDDEN_DEATH_AT) return 0
  const rate = SUDDEN_DEATH_BASE + (now - SUDDEN_DEATH_AT) * SUDDEN_DEATH_RAMP
  return maxHp * rate * dt
}
