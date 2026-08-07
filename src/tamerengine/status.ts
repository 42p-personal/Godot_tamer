// ─────────────────────────────────────────────────────────────────────────────
// FIELD STATUSES (v0.93) — what each of the 15 afflictions MEANS in space.
//
// ⚠️ Until now the field engine applied NO statuses at all. `FieldUnit.statuses`
// was initialised to `[]` and nothing ever wrote to it, so every `Move.status`
// in the game — every burn, stun, fear — was silently inert on the field. Moves
// whose entire value is their rider (Glacial Prison, Lullaby, Screech) were
// paying their cooldown for nothing. This table is what makes them real.
//
// The translation is the interesting part. A turn-based status is a COUNTER on
// a body: "confused, 2 turns" means a chance to hit the wrong thing. On a field
// the same word can mean something with GEOMETRY, and three of them get one:
//
//   • fear      — the victim actually FLEES, away from whoever frightened it.
//   • confusion — it walks the WRONG WAY, veering off its intended heading.
//   • charm     — it turns and fights its own side.
//
// That is why every status records `from`: fear needs to know what to run from,
// and charm lurches toward whoever enthralled it. A counter alone cannot
// express either.
//
// UNITS: moves author `duration` in ROUNDS (the turn engine's clock). Field time
// is seconds, so every duration is multiplied by SECONDS_PER_ROUND exactly once,
// at application. Damage-over-time is likewise stated PER SECOND here and scaled
// by DT each tick — the turn engine's "5% of maxHp per round" becomes 2.5%/s.
// ─────────────────────────────────────────────────────────────────────────────
import { StatusKind, HARD_CONTROL_STATUSES } from '../core'

/** How a status hijacks where its carrier walks. */
export type Steer =
  | 'flee'      // directly away from `from`
  | 'toSource'  // directly toward `from`
  | 'veer'      // off its own heading by a fixed angle — not random, so replays match

export interface FieldStatusRule {
  /** Cannot act and cannot travel. The hardest form of control. */
  incapacitates?: boolean
  /** Damage broke it — sleep only. */
  breaksOnDamage?: boolean
  /** Skills locked out; the free basic attack still works. */
  noSkills?: boolean
  /** Cannot attack at all, but still moves (fear is a rout, not a stun). */
  noAttack?: boolean
  /** Accuracy points subtracted from every cast. */
  accPenalty?: number
  /** Multiplier on damage this carrier TAKES. */
  damageTakenMult?: number
  /** Multiplier on move speed. */
  speedMult?: number
  /** Healing (zones included) does nothing. */
  blockHeal?: boolean
  /** Fraction of maxHp lost per second. */
  hpPerSec?: number
  /** Fraction of maxMp lost per second. */
  mpPerSec?: number
  /** Fraction of maxHp dealt once, when the status EXPIRES. */
  detonate?: number
  /** Hijacks movement. */
  steer?: Steer
  /** Targets its own side instead of the enemy. */
  turncoat?: boolean
  /** A ONE-OFF drag toward whoever applied it, in world units, at the moment it
   *  lands. Distinct from `steer`, which would hold the unit there for the whole
   *  duration — and which for charm would fight its own targeting. */
  lurchToSource?: number
  /** Stacks rather than refreshing, up to this many. */
  maxStacks?: number
}

// ⚠️ Magnitudes are ported from the turn engine (`battle.ts:tickStatuses`,
// VULNERABLE_MULT, the blind −25 accuracy) and divided by SECONDS_PER_ROUND
// where they were per-round, so a status is worth the SAME over its lifetime in
// either engine. Do not retune one without the other.
export const FIELD_STATUS: Record<StatusKind, FieldStatusRule> = {
  // ── hard control ──────────────────────────────────────────────────────────
  stun: { incapacitates: true },
  sleep: { incapacitates: true, breaksOnDamage: true },
  silence: { noSkills: true },
  // A knockback already threw the body; the lingering part is the stumble.
  knockback: { speedMult: 0.6 },

  // ── the three that gained geometry ────────────────────────────────────────
  // Routed. It runs, and it cannot bring itself to strike back while running.
  fear: { steer: 'flee', noAttack: true, speedMult: 1.15 },
  // Disoriented. It still fights, it just cannot walk a straight line.
  confusion: { steer: 'veer', accPenalty: 15 },
  // Enthralled — the only status that can get a monster killed by its friends.
  //
  // ⚠️ It does NOT hold a `steer: 'toSource'`. A first cut had one, and the two
  // halves of charm fought each other: the victim was walked toward the charmer
  // while trying to attack an ally in the opposite direction, so it drifted
  // between them and struck nobody. The move's own text — "a charmed foe turns
  // on its own team" — says targeting is the point, so targeting wins and the
  // pull becomes a single lurch at the moment of enthralment.
  charm: { turncoat: true, lurchToSource: 2.5 },

  // ── attrition ─────────────────────────────────────────────────────────────
  burn: { hpPerSec: 0.05 / 2 },          // 5% of maxHp per round
  bleed: { hpPerSec: 0.02 / 2, maxStacks: 3 }, // the one stacking status
  poison: { mpPerSec: 0.15 / 2 },        // drains mana, not health
  doom: { detonate: 0.25 },              // pays out all at once, at the end

  // ── modifiers ─────────────────────────────────────────────────────────────
  blind: { accPenalty: 25 },
  vulnerable: { damageTakenMult: 1.2 },
  healblock: { blockHeal: true },
  haste: { speedMult: 1.35 },
}

/** Statuses that help their carrier — never applied to enemies by mistake. */
export const BENEFICIAL = new Set<StatusKind>(['haste'])

/**
 * CONTROL statuses — the ones that stop or hijack a monster's actions, and so the
 * ones subject to diminishing returns (see CC_DR_STEP in types.ts).
 *
 * ⚠️ Deliberately NOT every debuff. poison/burn/bleed/vulnerable/doom/healblock
 * hurt you but leave you playing the game, so putting them on the DR meter would
 * let a damage-over-time kit burn away the protection that is meant to guard
 * against LOCKOUT — the exact thing DR exists to cap.
 */
// Single source of truth lives in core.ts, so the loadout picker (which must not
// import tamerengine) and this engine cannot drift apart.
export const CONTROL_STATUSES = HARD_CONTROL_STATUSES

// How far off its heading a confused monster veers, in radians. Fixed, not
// rolled: the field engine's contract is that a replay reproduces exactly, and
// alternating the sign per application is enough to stop it reading as a
// constant drift in one direction.
export const CONFUSION_VEER = 1.15
