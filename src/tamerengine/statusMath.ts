// STATUS APPLICATION AND CC DIMINISHING RETURNS, AS PURE FUNCTIONS.
//
// ⚠️ SECOND BLOCK OF THE PORT, SAME SEAM AS `damage.ts`. `applyFieldStatus` in `engine.ts`
// does four separable things: it resolves diminishing returns, it decides stack-vs-refresh,
// it optionally drags the victim toward the caster, and it emits events. Only the drag touches
// geometry. The rest is arithmetic and bookkeeping that must survive a spatial rebuild
// unchanged, because it is what makes chain-CC a timing decision rather than a dump.
//
// The lurch stays in the engine: it is a position write, and Godot will do it with its own
// navigation and its own collision. What comes across is WHETHER a status lands and FOR HOW
// LONG — the part a player actually feels.
import { StatusKind, HARD_CONTROL_STATUSES } from '../core'
import { CC_DR_STEP, SECONDS_PER_ROUND } from './types'
import { FIELD_STATUS } from './status'

/** One live status on a unit. Mirrors the engine's shape minus the event plumbing. */
export interface ActiveStatus {
  kind: StatusKind
  until: number
  from: string
}

export interface ApplyStatusInput {
  kind: StatusKind
  /** Authored duration, in ROUNDS. Converted to seconds internally. */
  rounds: number
  /** Now, in seconds. */
  now: number
  from: string
  /** The target's live statuses, in engine order. Not mutated. */
  statuses: ActiveStatus[]
  /** The target's CC meter, 0..1. */
  ccResist: number
  /** Cleanse immunity expiry, in seconds. */
  ccImmuneUntil: number
  /** The target's CON, which resists control natively. */
  targetCon: number
  targetDead: boolean
}

export interface ApplyStatusOutcome {
  /** Whether the status actually landed. */
  applied: boolean
  /** Why it did not, when it did not — for the port to diff on, and for debugging. */
  refusedBecause: 'dead' | 'immune' | 'fullyDiminished' | 'maxStacks' | null
  /** The resulting status list. Unchanged when nothing landed. */
  statuses: ActiveStatus[]
  /** The CC meter after this application. */
  ccResist: number
  /** Seconds the status was granted, AFTER diminishing returns. 0 if it did not land. */
  seconds: number
  /** Whether this application should also drag the target — the engine does the moving. */
  lurch: number
  /**
   * Whether this application engaged the CC meter at all.
   *
   * ⚠️ THE CALLER USES THIS TO STAMP `lastCcAt`, AND GETTING IT WRONG IS SUBTLE. Only a HARD
   * CONTROL status that passed the immunity gate touches the meter. If an attrition status
   * stamped it too, `CC_DR_RESET` would never fire while a damage-over-time ticked — the meter
   * would stay hot forever and control would stay diminished for the rest of the fight. That
   * exact bug was written and caught during the port extraction; the goldens did NOT catch it,
   * because the fixtures happen not to pair a DoT with chained control.
   */
  ccMeterTouched: boolean
}

/**
 * Apply one status, resolving diminishing returns and stacking.
 *
 * ⚠️ CC DIMINISHING RETURNS ARE THE HARD CAP ON THE LOCKOUT BUILD. Control on the same target
 * lands shorter each time (100/75/50/25/immune) and the meter clears after quiet seconds. Take
 * this out and WIS Disruptor plus CHA Enchanter — resource denial stacked on action denial —
 * becomes an unanswerable chain.
 *
 * ⚠️ AND IT IS DELIBERATELY NOT EVERY DEBUFF. poison/burn/bleed/vulnerable/doom/healblock hurt
 * you but leave you playing the game. Putting them on the meter would let a damage-over-time
 * kit burn away the protection that exists to guard against LOCKOUT.
 */
export function applyStatus(inp: ApplyStatusInput): ApplyStatusOutcome {
  const unchanged = {
    statuses: inp.statuses, ccResist: inp.ccResist, seconds: 0, lurch: 0,
  }
  if (inp.targetDead) {
    return { applied: false, refusedBecause: 'dead', ccMeterTouched: false, ...unchanged }
  }

  let seconds = inp.rounds * SECONDS_PER_ROUND
  let ccResist = inp.ccResist
  let touched = false

  if (HARD_CONTROL_STATUSES.has(inp.kind)) {
    // Cleansed targets are briefly immune, so a cleanse cannot be immediately undone by the
    // next cast in the same breath.
    if (inp.now < inp.ccImmuneUntil) {
      return { applied: false, refusedBecause: 'immune', ccMeterTouched: false, ...unchanged }
    }
    // ⚠️ CON RESISTS CONTROL NATIVELY — you cannot lock a Juggernaut down the way you lock a
    // caster. It acts as a FLOOR on the meter rather than a separate roll, so a high-CON unit
    // starts partway up the DR curve instead of getting a chance to dodge it.
    const conFloor = Math.min(0.3, (inp.targetCon ?? 0) / 3000)
    const resist = Math.min(1, Math.max(inp.ccResist, conFloor))
    seconds *= 1 - resist
    ccResist = Math.min(1, Math.max(inp.ccResist, conFloor) + CC_DR_STEP)
    touched = true
    if (seconds <= 0.05) {
      // Fully diminished — the control simply fails. ⚠️ THE METER STILL ADVANCED. The attempt
      // costs the caster its cooldown either way, which is what stops a spam-until-it-sticks
      // pattern from being free.
      return { applied: false, refusedBecause: 'fullyDiminished', statuses: inp.statuses, ccResist, seconds: 0, lurch: 0, ccMeterTouched: true }
    }
  }

  const until = inp.now + seconds
  const rule = FIELD_STATUS[inp.kind]
  const next = inp.statuses.map((s) => ({ ...s }))

  if (rule.maxStacks) {
    if (next.filter((s) => s.kind === inp.kind).length >= rule.maxStacks) {
      return { applied: false, refusedBecause: 'maxStacks', statuses: inp.statuses, ccResist, seconds: 0, lurch: 0, ccMeterTouched: touched }
    }
    next.push({ kind: inp.kind, until, from: inp.from })
  } else {
    const existing = next.find((s) => s.kind === inp.kind)
    if (existing) {
      // ⚠️ REFRESH TAKES THE LONGER OF THE TWO, never the newer. A short re-application must
      // not cut a long one short.
      existing.until = Math.max(existing.until, until)
      existing.from = inp.from // whoever most recently applied it is what fear runs from
    } else {
      next.push({ kind: inp.kind, until, from: inp.from })
    }
  }

  return {
    applied: true, refusedBecause: null, statuses: next, ccResist, seconds,
    lurch: rule.lurchToSource ?? 0, ccMeterTouched: touched,
  }
}
