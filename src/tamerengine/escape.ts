// ESCAPE METRICS — how long a hunted monster lasts, and whether cover is why.
//
// ⚠️ THE ACCEPTANCE TEST FOR THE WHOLE STAGE 3 DESIGN, and no outcome metric can
// answer it. `resolved` and `duration` cannot tell "the support escaped" from
// "the support was never chased" — both look like a fight that ended. The design
// asks for something specific and two-sided:
//
//     a fleeing support should buy a FEW SECONDS and then die anyway.
//
// A retreat that always works is the same bug as one that never works: the first
// stalls fights forever (the 0/40 this whole line of work started from), the
// second makes escape cooldowns pointless. So the measure has to show BOTH that
// cover helps and that it does not save you.
//
// Pure observation over the event stream — reads `targetId` from snapshots and
// `giveup` events, touches no engine state, and cannot alter a fight.
import type { FieldEvent } from './types'

export interface Hunt {
  /** The hunted unit. */
  preyId: string
  /** First moment any enemy had it as its target. */
  firstHuntedAt: number
  /** Seconds during which at least one enemy was hunting it. */
  huntedFor: number
  /** Highest number of simultaneous hunters — being dived by three is not one chase. */
  peakHunters: number
  /** When it died, or null if it survived. */
  diedAt: number | null
  /** Pursuers that gave up on it. The literal count of successful escapes. */
  escapes: number
  /**
   * Seconds from first being hunted to dying. Null if it survived.
   * ⚠️ This is the number the design is about, and it is NOT time-to-kill from
   * first damage — the pursuit phase before the first blow is exactly what cover
   * is supposed to lengthen, so measuring from first damage would hide the whole
   * effect being tested.
   */
  survivedFor: number | null
}

export interface EscapeSummary {
  hunts: number
  /** Share of hunted units that lived to the end. ⚠️ The UNBOUNDED check. */
  survivalRate: number
  /** Mean seconds a hunted unit lasted before dying (the ones that died). */
  meanSurvivedFor: number
  /** Mean seconds spent under pursuit, whether or not it ended in a death. */
  meanHuntedFor: number
  /** Give-ups per hunt. */
  escapesPerHunt: number
}

/** Per-unit hunt records for one finished battle. */
export function hunts(events: FieldEvent[], sideOf: (id: string) => string): Hunt[] {
  const rec = new Map<string, Hunt>()
  const get = (id: string, t: number): Hunt => {
    let h = rec.get(id)
    if (!h) {
      h = {
        preyId: id, firstHuntedAt: t, huntedFor: 0, peakHunters: 0,
        diedAt: null, escapes: 0, survivedFor: null,
      }
      rec.set(id, h)
    }
    return h
  }

  let prevT: number | null = null
  for (const e of events) {
    if (e.kind === 'giveup') {
      // A give-up only counts once the unit is actually being hunted; the record
      // is created by the snapshot pass, so a stray event cannot invent a hunt.
      const h = rec.get(e.targetId)
      if (h) h.escapes++
      continue
    }
    if (e.kind !== 'snapshot') continue
    const dt = prevT === null ? 0 : e.t - prevT
    prevT = e.t

    const hunters = new Map<string, number>()
    for (const u of e.units) {
      if (u.hp <= 0 || !u.targetId) continue
      // Only an ENEMY counts as a hunter. Charm flips sides mid-fight, so this
      // has to be asked per tick rather than assumed from the roster.
      if (sideOf(u.id) === sideOf(u.targetId)) continue
      hunters.set(u.targetId, (hunters.get(u.targetId) ?? 0) + 1)
    }
    for (const [preyId, n] of hunters) {
      const h = get(preyId, e.t)
      h.huntedFor += dt
      h.peakHunters = Math.max(h.peakHunters, n)
    }
    for (const u of e.units) {
      if (u.hp > 0) continue
      const h = rec.get(u.id)
      if (h && h.diedAt === null) {
        h.diedAt = e.t
        h.survivedFor = +(e.t - h.firstHuntedAt).toFixed(2)
      }
    }
  }
  // ⚠️ A unit hunted for a fraction of a second is noise, not a chase.
  return [...rec.values()].filter((h) => h.huntedFor >= 0.5)
}

export function summarise(all: Hunt[]): EscapeSummary {
  if (!all.length) {
    return { hunts: 0, survivalRate: 0, meanSurvivedFor: 0, meanHuntedFor: 0, escapesPerHunt: 0 }
  }
  const died = all.filter((h) => h.diedAt !== null)
  return {
    hunts: all.length,
    survivalRate: (all.length - died.length) / all.length,
    meanSurvivedFor: died.length
      ? died.reduce((s, h) => s + (h.survivedFor ?? 0), 0) / died.length
      : 0,
    meanHuntedFor: all.reduce((s, h) => s + h.huntedFor, 0) / all.length,
    escapesPerHunt: all.reduce((s, h) => s + h.escapes, 0) / all.length,
  }
}
