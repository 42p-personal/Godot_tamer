// ─────────────────────────────────────────────────────────────────────────────
// PERSONALITY (v0.94) — who a monster IS, as opposed to what you tell it to do.
//
// Seven innate axes, 0..100 (aggression, teamplay, mental, temperament,
// awareness, patience, focus). Your per-fight Tactics are COACHING laid on top;
// DISCIPLINE decides how much of that coaching actually sticks. Order an
// untemperamentd bruiser to hold the line and it will charge anyway — which is
// the point. Coaching becomes a negotiation with a creature, not a switch.
//
// ⚠️ DERIVED FROM THE SEED, NEVER ROLLED IN generateMonster.
// Monster generation's rng stream is load-bearing: the 12 golden battles pin
// it, and CLAUDE.md's standing warning is that anything drawing from that
// stream shifts them. So personality runs on its OWN stream keyed off the
// monster's seed. Consequences, all good:
//   • every existing monster — including ones in old saves — already HAS a
//     personality, with no migration
//   • the goldens cannot move, because generation is untouched
//   • it is stable: the same monster is always the same character
// ─────────────────────────────────────────────────────────────────────────────
import { BodyType, Monster, Personality, Species, Tactics, hashString, mulberry32 } from '../core'

export type { Personality } from '../core'

export type PersonalityAxis = keyof Personality

const clamp = (n: number) => Math.min(100, Math.max(0, Math.round(n)))

/**
 * A species' natural disposition, read off its base stats so all 65 species
 * have a sensible character without a separate authoring pass. A species may
 * override this later by declaring its own block.
 */
function speciesBias(sp: Species): Personality {
  const b = sp.base
  const total = Math.max(1, b.STR + b.DEX + b.CON + b.WIS + b.INT + b.CHA)
  const share = (n: number) => (n / total) * 6 // 1.0 == an even share
  return {
    // Brawn and speed want to be in the fight; bulk and wisdom are patient.
    aggression: 50 + (share(b.STR) + share(b.DEX) - share(b.CON) - share(b.WIS)) * 16,
    // Presence and wisdom make a team player.
    teamplay: 50 + (share(b.CHA) + share(b.WIS) - share(b.STR)) * 15,
    // Toughness and wisdom keep their head.
    mental: 50 + (share(b.CON) + share(b.WIS) - share(b.DEX)) * 15,
    // Intellect and wisdom follow a plan.
    temperament: 50 + (share(b.INT) + share(b.WIS) - share(b.STR)) * 15,
    // Quick eyes and a quick mind spot the flanker; bulk does not.
    awareness: 50 + (share(b.DEX) + share(b.INT) - share(b.CON)) * 15,
    // Deliberate and durable monsters wait for the moment; twitchy ones do not.
    patience: 50 + (share(b.CON) + share(b.WIS) - share(b.DEX)) * 15,
    // ⚠️ APPENDED LAST — see basePersonality()'s note. No RNG here (speciesBias
    // is a pure function of authored base stats), so the ordering constraint is
    // about basePersonality()'s vary() calls, not this object literal — but it
    // stays last here too, for one function that reads the same both places.
    // Brawn locks onto what it's hitting; calculated persistence asks whether
    // switching targets is worth it — both pull focus UP. Quick reflexes
    // redirect at the next opening; a showy monster's eye goes to the wider
    // spectacle of the fight — both pull it DOWN. No WIS term, deliberately:
    // every other axis has one, and this keeps focus's correlation pattern
    // distinct rather than becoming "another WIS-derived stat"
    // (docs/PERSONALITY_STATS.md §1).
    focus: 50 + (share(b.STR) + share(b.INT) - share(b.DEX) - share(b.CHA)) * 16,
  }
}

/**
 * This individual's personality: its species' disposition plus its own
 * variation. Pure and stable for a given (seed, species).
 */
export function basePersonality(seed: string, sp: Species): Personality {
  const rng = mulberry32(hashString(seed + ':personality:v1'))
  const bias = speciesBias(sp)
  // ±18 of individual character, so two Tortavos are recognisably the same
  // species and still distinct animals.
  const vary = () => (rng() * 2 - 1) * 18
  return {
    aggression: clamp(bias.aggression + vary()),
    teamplay: clamp(bias.teamplay + vary()),
    mental: clamp(bias.mental + vary()),
    temperament: clamp(bias.temperament + vary()),
    awareness: clamp(bias.awareness + vary()),
    patience: clamp(bias.patience + vary()),
    // ⚠️ MUST STAY LAST. The rng stream is consumed strictly in object-literal
    // evaluation order — six draws above, unchanged since v0.93. This 7th
    // draw extends the stream by one step without moving any of the six
    // existing draws' position, so every existing save's aggression/teamplay/
    // mental/temperament/awareness/patience is byte-identical to before this
    // axis existed. Inserting it anywhere earlier (e.g. alphabetically)
    // would silently re-roll every later axis for every existing save — see
    // docs/PERSONALITY_STATS.md §1/§11.
    focus: clamp(bias.focus + vary()),
  }
}

/**
 * The personality actually in play: innate, plus any drift earned through
 * training, care or breeding (stored on the monster when present).
 */
export function personalityOf(m: Monster): Personality {
  const base = basePersonality(m.seed, m.species)
  const drift = m.personality
  if (!drift) return base
  return {
    aggression: clamp(base.aggression + (drift.aggression ?? 0)),
    teamplay: clamp(base.teamplay + (drift.teamplay ?? 0)),
    mental: clamp(base.mental + (drift.mental ?? 0)),
    temperament: clamp(base.temperament + (drift.temperament ?? 0)),
    awareness: clamp(base.awareness + (drift.awareness ?? 0)),
    patience: clamp(base.patience + (drift.patience ?? 0)),
    focus: clamp(base.focus + (drift.focus ?? 0)),
  }
}

// ── Coaching ────────────────────────────────────────────────────────────────
/** What the player's orders are ASKING for, as 0..1 targets. */
function coachingTargets(t: Tactics | undefined): { aggression?: number; teamplay?: number } {
  if (!t) return {}
  const out: { aggression?: number; teamplay?: number } = {}
  if (t.temperament === 'aggressive') out.aggression = 0.9
  if (t.temperament === 'cautious') out.aggression = 0.15
  if (t.temperament === 'balanced') out.aggression = 0.5
  if (t.targetPriority === 'manmark') out.teamplay = 0.9
  if (t.targetPriority === 'casters') out.aggression = Math.max(out.aggression ?? 0, 0.8)
  if (t.preserve && t.preserve !== 'off') out.aggression = Math.min(out.aggression ?? 1, 0.3)
  return out
}

/**
 * Blend innate disposition with coaching, weighted by DISCIPLINE.
 *
 * obey = temperament/100. At obey 1 the order lands in full; at obey 0 the
 * monster ignores you and plays to its nature. This single line is what makes
 * a stable full of individuals feel different from a stable of settings.
 */
export function coachedValue(innate01: number, coached01: number | undefined, temperament: number): number {
  if (coached01 === undefined) return innate01
  const obey = clamp(temperament) / 100
  return innate01 * (1 - obey) + coached01 * obey
}

/** How readily this monster disengages when hurt — low mental panics early. */
export function panicThreshold(p: Personality): number {
  // 0.45 at no mental down to 0.10 at full mental.
  return 0.45 - (p.mental / 100) * 0.35
}

/**
 * How reliably it picks its BEST available move rather than just something
 * that is off cooldown. Temperament is execution as well as obedience.
 */
export function executionQuality(p: Personality): number {
  return 0.55 + (p.temperament / 100) * 0.45
}

/** Everything the field engine needs, resolved once per fight. */
export function resolvePersonality(m: Monster): {
  p: Personality
  /** 0..1, post-coaching — feeds `predation` */
  aggression: number
  /** 0..1, post-coaching — feeds `cohesion` */
  teamplay: number
} {
  const p = personalityOf(m)
  const want = coachingTargets(m.tactics)
  return {
    p,
    aggression: coachedValue(p.aggression / 100, want.aggression, p.temperament),
    teamplay: coachedValue(p.teamplay / 100, want.teamplay, p.temperament),
  }
}

/**
 * How far out this monster notices a threat, in world units. An oblivious
 * monster only reacts to what is already on top of it.
 */
export const threatRadius = (p: Personality): number => 3 + (p.awareness / 100) * 7

/**
 * How soft a target has to be before a PATIENT monster will spend one of its
 * big cooldowns on it. At patience 0 it fires the moment the move is up; at
 * 100 it waits until the target is at half health (a guaranteed kill always
 * overrides this — see worthSpending).
 */
export const spendAbove = (p: Personality): number => 1 - (p.patience / 100) * 0.5

/**
 * The same threshold, after the player's `burst` order. 'steady' says fire it as
 * soon as it is up (threshold 1 — always worth spending); 'nuke' says hold it
 * for something worth finishing. Absent, the monster's own patience decides,
 * exactly as before.
 */
export const spendAboveFor = (m: Monster, p: Personality): number => {
  const order = m.tactics?.burst
  if (order === 'steady') return 1
  if (order === 'nuke') return Math.min(spendAbove(p), 0.5)
  return spendAbove(p)
}

// ─────────────────────────────────────────────────────────────────────────────
// SPEED — derived from species/body ONLY. NOT a stat, not stored, not
// trainable, not bred (docs/AUTOBATTLER_DESIGN.md #41, reversing #19/#23; the
// "5th coach-trainable axis" plan in docs/PERSONALITY_STATS.md §6 is VOID).
// This reinstates docs/ENGAGEMENT_DESIGN.md §6e, which recommended a derived
// speed model before either later decision existed.
//
// Pure function of species identity — no rng, no per-individual jitter, no
// drift field. Two individuals of the same species always move at the same
// speed. Nothing here touches the personality rng stream above.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * World units/second the field sim already spans (`engine.ts`/`Spatial.gd`).
 * Re-declared here as the target envelope for `derivedSpeed()` — NOT a change
 * to the sim's own constants, which stay exactly where they are so nothing
 * else spatially tuned against them (`BACKPEDAL_MULT`, `CLOSING_BONUS`,
 * `DEPLOY_SEPARATION`...) needs retuning. Only which input feeds the speed
 * formula changes; the output range does not.
 */
export const SPEED_MIN = 2.4
export const SPEED_MAX = 6.0

// Same partial-record + fallback pattern as core.ts:BODY_MINOR — only bodies
// with a clear thematic lean are authored (ENGAGEMENT_DESIGN.md §6c: "Avian
// quick, Aquatic laboured on land, Draconic heavy"); everything else,
// including the 4 fusion bodies, defaults to 0 (no lean) rather than
// guessing at an unauthored identity.
const BODY_SPEED_LEAN: Partial<Record<BodyType, number>> = {
  Avian: 18,
  Insectoid: 8,
  Marsupial: 4,
  Mammal: 0,
  Mythical: 6,
  Reptilian: -6,
  Abyssal: -4,
  Aquatic: -14,
  Draconic: -16,
}

/**
 * A 0..100 "quickness" lean: the same share()-of-base-stats shape as
 * speciesBias() above (DEX pulls up, CON pulls down), plus the species'
 * body-type lean. This IS the value — there is nothing individual to roll,
 * nothing to train, nothing to breed toward.
 */
function speciesSpeedBias(sp: Species): number {
  const b = sp.base
  const total = Math.max(1, b.STR + b.DEX + b.CON + b.WIS + b.INT + b.CHA)
  const share = (n: number) => (n / total) * 6
  const lean = BODY_SPEED_LEAN[sp.body] ?? 0
  return 50 + (share(b.DEX) - share(b.CON)) * 20 + lean
}

/**
 * Movement speed in world units/second, mapped onto the sim's existing
 * SPEED_MIN..SPEED_MAX envelope. Replaces the inline
 * `2.4 + (DEX/1000) * 3.6` formula at `engine.ts:198` / the equivalent in
 * `Spatial.gd` — swapping that formula's input from DEX to this function is
 * a separate, later integration step (docs/PERSONALITY_STATS.md §6.4,
 * §12 step 7) and is explicitly OUT of scope here; this is the pure function
 * for whoever picks that up.
 *
 * ⚠️ Species/body only, per docs/AUTOBATTLER_DESIGN.md #41. Not read from
 * `Monster.speed` (no such field exists) and never will under this model.
 */
export function derivedSpeed(sp: Species): number {
  const spd = clamp(speciesSpeedBias(sp))
  return SPEED_MIN + (SPEED_MAX - SPEED_MIN) * (spd / 100)
}
