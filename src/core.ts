// Core types, RNG, and shared game constants for Monster Tamer.
// See docs/GAME_DESIGN.md for the design these mirror.

export type Stat = 'STR' | 'DEX' | 'CON' | 'WIS' | 'INT' | 'CHA'
export const STATS: Stat[] = ['STR', 'DEX', 'CON', 'WIS', 'INT', 'CHA']
export const STAT_NAMES: Record<Stat, string> = {
  STR: 'Strength',
  DEX: 'Dexterity',
  CON: 'Constitution',
  WIS: 'Wisdom',
  INT: 'Intelligence',
  CHA: 'Charisma',
}
export type Stats = Record<Stat, number>

export type BodyType = 'Mammal' | 'Avian' | 'Marsupial' | 'Aquatic' | 'Insectoid' | 'Reptilian' | 'Draconic' | 'Abyssal' | 'Mythical'
  | 'Saurian' | 'Tempestine' | 'Broodkin' // fusion classes (FUSION_DESIGN.md)
  | 'Primeval' // prestige fusion (v0.88): Mythical + Draconic/Abyssal

// Fusion classes (v0.7): body types that only exist as the RESULT of fusion —
// never wild, never in the market. Drives the gen-1 Platinum stat cap and the
// per-monster (not per-species) inherited majors + rolled minor/flaw. See FUSION_DESIGN.md.
export const FUSION_BODIES: BodyType[] = ['Saurian', 'Tempestine', 'Broodkin', 'Primeval']
export const isFusionBody = (b: BodyType): boolean => FUSION_BODIES.includes(b)
// The licence-gated "prestige" bodies (Special → Draconic/Abyssal, Elite →
// Mythical). Lives here so both generation and career code share one list.
export const PRESTIGE_BODIES: BodyType[] = ['Draconic', 'Abyssal', 'Mythical']
export const isPrestigeBody = (b: BodyType): boolean => PRESTIGE_BODIES.includes(b)
export type Sex = 'M' | 'F'

// Training aptitude (user spec 2026-07-23): `minor` is body-type-derived
// (BODY_MINOR below, same stat for every species of that body) — a light
// touch, not real differentiation. `major`/`flaw` are individually authored
// per species (Species.trainingProfile) — this is what actually makes two
// monsters of the same body type train differently. Every species now authors
// major/flaw (the exclusive bodies were migrated in v0.85); any future species
// left without one falls back to the legacy derivation (top/2nd/lowest base
// stat) inside game.ts:trainingProfileFor.
export interface TrainingProfile { minor: Stat; major?: Stat; flaw?: Stat }

// What a species DATA ENTRY authors — just major/flaw, never minor (that's
// always derived from the species' body type, not hand-picked). Resolved
// into a full TrainingProfile (with minor filled in) by trainingProfileFor.
export interface AuthoredAptitude { major?: Stat; flaw?: Stat }

// Body type's single minor training bonus (+10%, same for every species of
// that body — see TrainingProfile above). Only the 6 base body types are
// migrated to the new authored-aptitude system so far; the 3 exclusive body
// types intentionally have no entry here and fall back to the legacy system.
export const BODY_MINOR: Partial<Record<BodyType, Stat>> = {
  Mammal: 'STR', Avian: 'WIS', Marsupial: 'CHA', Aquatic: 'INT', Insectoid: 'CON', Reptilian: 'DEX',
  // Exclusive bodies (v0.85): each prestige group now carries a shared thematic
  // minor too, so a licensed monster trains like a designed creature, not a
  // legacy stat-block. Draconic = arcane heritage (WIS); Abyssal = eldritch
  // intellect (INT); Mythical = legendary presence (CHA).
  Draconic: 'WIS', Abyssal: 'INT', Mythical: 'CHA',
}

export type Channel = 'melee' | 'ranged' | 'magic' | 'voice' | 'support'
export type MoveType = 'damage' | 'buff' | 'debuff' | 'status' | 'control'
export type Target = 'enemy' | 'allEnemies' | 'frontRow' | 'backRow' | 'self' | 'ally' | 'team'
// Row targets (v0.91) give the formation system real weight — before these, the
// only rule rows had was "single-target melee can't reach the back".
//   frontRow — sweeps/shockwaves: fewer targets than allEnemies, so they hit harder
//   backRow  — the anti-turtle answer: reaches past the wall to the casters behind
// Both fall back to the OTHER row when their own is empty, so a move never
// fizzles for want of a target (see resolveTargets).

// AoE FALLOFF (v0.91): every extra body a move splashes costs it 5% of its
// power. Multi-target damage previously scaled perfectly linearly, so World
// Ender was worth 56 at 1v1 and 336 at 6v6 — a large part of why the top-league
// meta rewarded AoE casters. Charged per ADDITIONAL target, so a lone survivor
// takes an undiminished hit.
export const AOE_FALLOFF_PER_TARGET = 0.05

// ── HARD CONTROL ────────────────────────────────────────────────────────────
// Statuses that take a turn AWAY rather than shaving damage off it. DoTs
// (burn/poison/bleed) are deliberately excluded — they are damage, not control.
// ⚠️ Canonical here in core so BOTH the loadout picker (monster.ts, which must
// not import tamerengine) and the field engine can share one list;
// tamerengine/status.ts re-exports it as CONTROL_STATUSES.
export const HARD_CONTROL_STATUSES = new Set<StatusKind>([
  'stun', 'sleep', 'fear', 'confusion', 'charm', 'silence', 'knockback',
])
/**
 * Statuses that CONTAGION can carry from one victim to another (`spreadStatus`).
 * Afflictions only — nothing beneficial, and nothing that is a positioning fact
 * rather than a condition. Shared by both engines so the two can never disagree
 * about what is catching.
 */
export const SPREADABLE_STATUSES = new Set<StatusKind>([
  'blind', 'poison', 'burn', 'fear', 'confusion', 'stun', 'knockback', 'bleed',
  'silence', 'vulnerable', 'sleep', 'doom', 'healblock', 'charm',
])
export const aoeFalloff = (targetCount: number): number =>
  Math.max(0.4, 1 - AOE_FALLOFF_PER_TARGET * Math.max(0, targetCount - 1))

// ── STAT SCALING (ability rework) ───────────────────────────────────────────
// Damage is `power × (1 + stat × statScale)`. Every move used to share one flat
// 1/320, which is why the pool's throughput ran flat-to-INVERTED against learn
// level: lvl-90 Power Strike (15.4 DPS) beat the lvl-920 capstone Titanfall
// (12.3), so training a stat to 920 could leave a monster with a worse attack
// than it had at 90.
//
// A higher-level move should GENERALLY scale better, so progression pays twice —
// a better-scaling move AND the trained stat. That also keeps low-league fights
// sane: a capstone is close to a starter on an untrained monster and only pulls
// away on an invested one.
//
// ⚠️ A SEED, NOT A LAW. `Move.statScale` is authored per ability; this only
// supplies the default when a move does not state one.
// ⚠️ LOW is pinned at the OLD flat 1/320 on purpose, so this change only ever
// ADDS. A first cut used 1/420, which quietly NERFED every low/mid move — and
// since `learnedMoves` gates by stat, a mid-game monster can only equip low/mid
// moves, so the whole mid-game got weaker (sim: damage/fight 28.9k → 27.3k).
// Progression should pay by lifting the top, not by lowering the bottom.
export const STAT_SCALE_LOW = 1 / 320  // ~lvl 40 — unchanged from the old flat value
// ⚠️ 1/270 WAS TRIED AND REVERTED. It was committed on a 12-fight sweep reading
// 10/12 vs 9/12 — inside that sweep's own noise band (sd 0.7). A paired A/B over
// 40 identical matchups then measured it properly: 23 fights faster, 16 slower,
// sign test p = 0.34, resolved delta ZERO, damage/fight -57. It does nothing.
// ⚠️ Contrast STAT_SCALE_HIGH below, which was tried the same way and KEPT:
// 19 faster / 5 slower, p = 0.0066. Both looked 'not significant' on a mean CI;
// only the sign test separated them, because a few fights swing 20-30s when they
// tip from timeout to a kill and those outliers swamp the mean.
export const STAT_SCALE_HIGH = 1 / 130 // ~lvl 920
// ⚠️ 1/150 -> 1/130 was raised on a sign test (p = 0.0066) when the problem was
// fights not RESOLVING.
//
// ⚠️ TRIMMED ~10% AND THEN PUT BACK. The trim (LOW 1/360, HIGH 1/145) did lift
// the mid sweep 18.8s -> 26.1s, but it was doing the job the wrong way round: it
// bought duration by making every monster hit softer, which is felt on every
// swing, to fix a problem that lives in the mop-up phase. A SECOND trim then
// moved the mid MEDIAN by 0.1s, which is what exposed it — damage scaling moves
// the TAILS, not the middle. The duration it bought is now held by levers aimed
// at the actual cause: OPENING_MIT_BONUS (delays first blood), MIT_SOFT (elite
// durability) and COOLDOWN_MULT (slows the mop-up itself).
//
// Do not reach for this to lengthen fights. It is the progression axis.
// (+3 fights resolved, +44 damage/fight over 40 paired matchups). ⚠️ This end of
// the band only reaches CAPSTONES: a train-850 monster has stats near 300 and
// cannot LEARN a lv920 move, which is why raising HIGH alone once moved measured
// field damage by 0.1%. It pays off at high training, not in the mid-game.
export const defaultStatScale = (learnLevel: number): number => {
  const t = Math.min(1, Math.max(0, (learnLevel - 40) / (920 - 40)))
  return STAT_SCALE_LOW + (STAT_SCALE_HIGH - STAT_SCALE_LOW) * t
}
/** The coefficient a move actually uses — its authored value, else the seed. */
export const statScaleOf = (mv: Move): number =>
  mv.statScale ?? defaultStatScale(mv.learnLevel)

// ── DAMAGE RANGE ────────────────────────────────────────────────────────────
// `power` is the MID-POINT of a range, not a fixed number. ⚠️ 0.15 is not an
// arbitrary default: it is exactly the flat `0.85 + rng()*0.3` the turn engine
// has always rolled, so every unauthored move keeps its existing behaviour and
// the goldens cannot move on this change alone.
//
// ⚠️ The FIELD engine had NO variance at all — only an 8% crit — so the two
// engines disagreed about something this basic. This is what brings them level.
export const DEFAULT_VARIANCE = 0.15
export const varianceOf = (mv: Move): number => mv.variance ?? DEFAULT_VARIANCE
/** Roll the multiplier for one hit. Consumes exactly one rng draw. */
export const rollVariance = (mv: Move, rng: RNG): number => {
  const v = varianceOf(mv)
  return 1 - v + rng() * 2 * v
}
export type StatusKind = 'blind' | 'poison' | 'burn' | 'fear' | 'confusion' | 'stun' | 'knockback' | 'bleed' | 'silence' | 'vulnerable'
  | 'sleep' | 'doom' | 'healblock' | 'haste' | 'charm'


export type Food =
  | 'vegetables' | 'fruit' | 'meat' | 'sweet treats' // normal (taste-based)
  | 'prime cut' | 'scholars tea' | 'sprinters mix'   // training boosters
  | 'vigor melon' | 'bliss berry' | 'golden truffle'  // premium specials
export type FoodTier = 'normal' | 'training' | 'premium'

export interface MoveStatus { kind: StatusKind; chance: number; duration: number }

// Mechanical effects a skill can carry (battle.ts implements each). Mixing these
// with statuses, elements, targets, cooldowns, and MP costs is where skill
// variety and strategy comes from.
export interface MoveEffects {
  pierce?: number // 0..1 — fraction of the target's mitigation ignored
  lifesteal?: number // 0..1 — fraction of damage dealt returned as HP
  recoil?: number // 0..1 — fraction of damage dealt taken by the user (max 0.15 in practice)
  hits?: [number, number] // multi-hit: strikes N times; `power` is per hit
  // RESOURCE STRIKES (v0.91): spend a defensive buff the CASTER is holding to
  // power the blow. Both are consumed on cast, once, however many targets the
  // move fans to — the bonus is a multiplier so an AoE cannot launder one ward
  // into six full-value hits. A tank's shield becomes ammunition.
  consumeWard?: number // +this much damage multiplier PER POINT of the caster's remaining ward, then the ward is spent (0.012 x ward 45 = +54%)
  consumeThorns?: number // as consumeWard, but spends the caster's thorns buffs (0.05 x thorns 9 = +45%)
  // VIGOR / DESPERATION (v0.91): damage scales continuously with the CASTER's
  // remaining HP, lerped by hp fraction. atFull 1.6 / atEmpty 0.7 rewards
  // fighting fresh; reverse the two for a last-stand move. The innate system had
  // this as a cliff (Frenzy below 30%, Statue Stance above 70%) — this is the
  // smooth, per-move version.
  hpScale?: { atFull: number; atEmpty: number }
  // DISPLACE (v0.91): drag a target to the FRONT of its line or shove it to the
  // BACK. The formation rules make this bite — melee is walled to the front two
  // (three at 6v6), and frontRow/backRow moves cut at one rank — so pulling a
  // sheltered caster forward or shoving a tank out of the way is real counterplay
  // against a turtled line, not just a debuff. Instantaneous, so it is an effect
  // rather than a StatusKind.
  displace?: { toRow: 'front' | 'back'; chance: number }
  spreadStatus?: { kind?: StatusKind; targets: number; chance: number } // CONTAGION (v0.91): when this move lands, a hostile status the victim is CARRYING jumps to `targets` other living enemies at `chance`% each. Omit `kind` to spread whatever it already has — so one move interacts with every setter in the game, pool or signature. Gated: no pool move sets it, so the engine's rng order is untouched.
  randomTargets?: boolean // with `hits`: each strike picks a LIVING ENEMY AT RANDOM (re-rolled per hit, repeats allowed) and resolves as its own independent attack, instead of `hits` multiplying damage onto one target. Signature-move effect (v0.91) — no pool move sets it, so the engine's existing rng call order is untouched.
  execute?: number // 0..1 — 1.5× damage when target HP is below this fraction
  manaBurn?: number // flat MP burned off the target
  guard?: number // flat damage reduction on EVERY hit taken until the user's next action
  ward?: number // absorb shield (HP pool) that soaks damage before health — CON-exclusive
  cleanse?: boolean // remove negative statuses (self, or the whole team if target is 'team')
  tauntForce?: boolean // forces the target's single-target hostile actions onto the caster for `duration` rounds; cast via target 'allEnemies' it taunts the WHOLE enemy team onto one monster
  // --- Synergy/framework effects (2026-07-25 framework pass — engine support
  // built first, moves adopt them in a later pass) ---
  maxHpDmg?: number // 0..1 — bonus damage equal to this fraction of the TARGET's max HP ("giant-killer" tools)
  bonusVsStatus?: { kind: StatusKind; mult: number; consume?: boolean } // setup→payoff combos: extra damage vs a target carrying `kind`; consume removes the status when cashed
  thorns?: number // timed buff: attackers take this much flat damage per hit landed on the wearer (lasts `duration` rounds)
  hpRegenBuff?: number // timed buff: +flat HP regen per turn (lasts `duration` rounds)
  firstStrikeMult?: number // damage multiplier if the TARGET hasn't yet acted this round (attacker moved first in the initiative order) — rewards investing in speed (DEX/haste/knockback) rather than being a status
  // Timed modifiers — ALL of the below last `duration` rounds, then expire and are
  // removed entirely (no more "for the fight" effects). Re-casting the same move
  // refreshes its remaining duration rather than stacking a second copy.
  duration?: number // rounds this move's buff/debuff fields below remain active
  atkBuff?: number // +% damage dealt (0.2 = +20%)
  defBuff?: number // +flat mitigation — CON-exclusive ("armour")
  dodgeBuff?: number // +% dodge
  accBuff?: number // +% accuracy
  regenBuff?: number // +flat mana regen per turn
  atkDebuff?: number // on target: −% damage dealt
  defDebuff?: number // on target: −flat mitigation (armour shred)
  accDebuff?: number // on target: −% accuracy
}

/**
 * Seconds of recharge that one TURN of `battle.ts` is worth.
 *
 * ⚠️ THE UNIT BRIDGE, and it lives here rather than in either engine because BOTH
 * non-field consumers need it: `battle.ts` counts rounds, and `monster.ts`'s
 * loadout picker prices a cooldown as a mild discount whose constant
 * (`COOLDOWN_DISCOUNT`) was calibrated against turns.
 *
 * ⚠️ 1.3 IS THE OLD `COOLDOWN_MULT`. Every authored cooldown was multiplied by it
 * when the pool moved to seconds, so dividing by it here recovers the original
 * integers exactly and both consumers behave as they did before the rename.
 */
export const SECONDS_PER_TURN = 1.3

export interface Move {
  id: string
  name: string
  stat: Stat // which stat pool gates it
  learnLevel: number
  type: MoveType
  channel: Channel
  target: Target
  /**
   * Recharge time in SECONDS.
   *
   * ⚠️ IT USED TO MEAN TWO DIFFERENT THINGS AT ONCE. `battle.ts` decremented it
   * once per round and documented it as "turns remaining"; the field engine did
   * `cooldown * COOLDOWN_MULT + castTime` and decremented it by `DT` — seconds.
   * Worse, two authored files disagreed INSIDE the field engine: `moves.ts` and
   * `signatureMoves.ts` wrote 1-9 (turns) while `tamerengine/fieldMoves.ts` wrote
   * 4-26 (seconds), and both went through the same multiply. `Disengage` at 26
   * became 33.8s on a field whose median fight is 23.3s — once a fight, or never.
   *
   * Seconds is the unit the game is moving to (M7 retires `simulateTeamBattle`),
   * so the field engine now reads this directly and the TURN engine converts, via
   * `battle.ts:SECONDS_PER_TURN` — the inverse of the constant the values were
   * scaled by, so both engines behave exactly as they did before the rename.
   */
  cooldown: number
  accuracy: number // 0..100
  power: number // damage / heal scale; 0 for pure utility
  status?: MoveStatus
  effects?: MoveEffects
  // ── Per-ability authoring axes (ability rework) ───────────────────────────
  /**
   * How hard this move scales with its stat, as the coefficient in
   * `power × (1 + stat × statScale)`.
   *
   * ⚠️ THIS IS A DESIGN AXIS, NOT A DERIVED VALUE. Every move used to share one
   * flat `1/320`, which is why the pool's throughput was flat-to-INVERTED against
   * learn level — a lvl-90 Power Strike out-damaged the lvl-920 capstone. Authored
   * per ability so a move can deliberately scale hard or flat; `defaultStatScale`
   * below only seeds a sensible starting point from `learnLevel`.
   *
   * Higher-level moves should GENERALLY scale better, so progression pays twice
   * (a better-scaling move AND the trained stat) — a guideline, not a law.
   */
  statScale?: number
  /**
   * Which of its stat's three LINES this move belongs to (see `src/lines.ts`).
   * Attached when `ALL_MOVES` is built, from the one lookup table there, rather
   * than hand-written on every row — the grouping is a design statement and is
   * far easier to check when it can be read in one place.
   *
   * ⚠️ A line is a group to DRAW FROM, not a track to commit to. It only tells
   * the auto-picker what a monster is for; the player's own choices are free.
   */
  line?: string
  /**
   * Half-width of this ability's DAMAGE RANGE, as a fraction of power. `0.15`
   * means power is the mid-point of a ±15% spread. Authored per ability, because
   * how *reliable* a move is is part of its character: a duellist's strike lands
   * where it was aimed (±8%), a gambler's volley does not (±50%), and a capstone
   * marksman shot stops gambling altogether (±5%).
   *
   * ⚠️ Omitted means DEFAULT_VARIANCE, which is exactly the flat ±15% the turn
   * engine already rolled — so leaving it unset changes nothing anywhere.
   */
  variance?: number
  /**
   * Authored MP cost, overriding the derived `monster.ts:manaCost`. Mana is a
   * trading axis: a move may be stronger in some dimension and simply cost more.
   */
  mana?: number
  // ── Spatial fields (v0.93, field engine only) ────────────────────────────
  // The turn-based engine in battle.ts NEVER reads these, so adding them cannot
  // move a golden. Both are OPTIONAL and fall back to a channel-derived default
  // (tamerengine/types.ts CHANNEL_RANGE / CHANNEL_CAST_TIME), which is what lets the
  // field engine run against all 140 existing moves without a blocking data
  // pass — author them per-move to refine reach as balance demands.
  range?: number // world units the move can reach
  castTime?: number // seconds the caster is rooted committing to it
  spatial?: MoveSpatial // field-engine-only movement mechanics (v0.93)
  /**
   * How this move TRAVELS, when it travels at all (decision #34). Authored by
   * `tools/authorprojectiles.ts`, seeded per LINE. Field engine only — battle.ts
   * never reads it, so it cannot move a golden.
   *
   * ⚠️ Omitted means the CHANNEL DEFAULT the field sim already used (ranged 90,
   * magic 55, width 0, no pierce), so an unauthored move behaves exactly as it
   * did before this field existed. Present only on `ranged`/`magic` moves —
   * melee and voice are instant and author nothing.
   */
  projectile?: MoveProjectile
  desc: string
}

/**
 * A shot's physical character. See `tools/authorprojectiles.ts` for the per-line
 * seeds and the reasoning behind each.
 */
export interface MoveProjectile {
  /** World units per second. Directly comparable to the channel constants 90/55. */
  speed: number
  /**
   * The shot's own radius, in BODY RADII (a monster is 1.0). Added to a body's
   * radius for the clip test, so width is what lets a shot hit someone it was
   * not aimed at. 0 is a point — exactly the pre-#34 behaviour.
   */
  width: number
  /**
   * How many ADDITIONAL bodies the shot passes through before expending.
   *
   * ⚠️ NOT `MoveEffects.pierce`, which is armour penetration as a fraction of
   * mitigation (Void Lance 0.5). Same word, different quantity; they are nested
   * apart deliberately and must never be merged.
   */
  pierce: number
}

// ── SPATIAL MECHANICS (v0.93, field engine only) ────────────────────────────
// A whole class of ability the turn-based engine could not express, because it
// had no space: closing the gap, teleporting behind someone, yanking a caster
// out of cover, pinning a diver in place.
//
// ⚠️ GATED like every other engine addition here — battle.ts NEVER reads this,
// so authoring it cannot move a golden. Absent = the move behaves as it always
// has.
export interface MoveSpatial {
  // Travel as part of the cast. `dash` crosses the ground and IS blocked by
  // cover; `blink` is instantaneous and ignores it — that difference is the
  // whole reason to want a blink.
  move?: { kind: 'dash' | 'blink'; to: 'target' | 'behindTarget' | 'awayFromTarget' | 'ally'; maxRange: number }
  pull?: number // drag the target this many world units TOWARD the caster
  push?: number // shove the target this many world units AWAY
  root?: number // seconds the target cannot move (it may still act)
  slow?: { mult: number; duration: number } // multiply the target's speed
  backstab?: number // damage multiplier when striking from BEHIND the target
  area?: MoveArea // real geometry instead of "hits everyone"
  /** Leave a persistent patch of ground behind. The arena's own contribution to
   *  tactics: a zone denies SPACE rather than damaging a body, so it is worth
   *  most against a team that has to hold a position. */
  zone?: { radius: number; duration: number; effect: 'damage' | 'slow' | 'heal'; power: number; centre?: 'self' | 'target' }
  /** Drop off the enemy's radar for a moment — the anti-taunt. While faded, a
   *  monster scores far lower as a target, so attackers look elsewhere. */
  fade?: { duration: number }
  /** Haul an ALLY to the caster, in world units — a rescue, not an attack. */
  haulAlly?: number
}

// ── AREA SHAPES (v0.93) ─────────────────────────────────────────────────────
// `allEnemies` / `frontRow` / `backRow` were written for an engine with rows.
// The field has none, so those targets are meaningless on it — a move tagged
// "hits everyone" ignored where anybody was standing, which made the `spacing`
// order pointless and AoE unavoidable.
//
// Real shapes fix both: an AoE now catches whoever is actually inside it, so
// spreading out is a genuine answer and clumping is a genuine risk.
export interface MoveArea {
  shape: 'circle' | 'cone' | 'line'
  /** Where the shape originates. A shout radiates from the CASTER; a meteor
   *  lands on the TARGET. Defaults to 'target'. */
  centre?: 'self' | 'target'
  radius?: number // circle
  angle?: number // cone, total degrees of the wedge
  range?: number // cone / line reach
  width?: number // line thickness
}

export interface Ability { name: string; desc: string }

export interface Species {
  id: string
  name: string
  body: BodyType
  naturalClass: string
  base: Stats
  lifespan: number // retiree age in years
  innate: Ability[]
  flavour: string
  // Authored major/flaw for the new per-species aptitude system (2026-07-23).
  // DEFINED (even as `{}` for a "vanilla, minor-only" species) => opts into
  // the new system; UNDEFINED => legacy top/2nd/lowest-base-stat derivation.
  trainingProfile?: AuthoredAptitude
}

export interface Monster {
  seed: string
  name: string
  species: Species
  sex: Sex
  stats: Stats
  className: string
  league: string
  learned: Move[]
  loadout: Move[]
  innateUnlocked: boolean // 2nd innate choice available (highest stat >= INNATE_SECONDARY_LEVEL)
  activeInnate: number // 0 or 1 — index into species.innate; only one is ever active
  favouriteFood: Food
  hatedFood: Food
  stamina?: number // 0-100 at fight time; absent = fresh (rivals, sandbox) — see staminaDamageMult
  hp?: number // current HP at fight time — injuries persist; absent = full (rivals, sandbox)
  mp?: number // current MP at fight time — absent = full (rivals, sandbox)
  tameness?: number // 0-100, HIDDEN wild-instinct roll — absent = fully tame (player monsters)
  tactics?: Tactics // standing battle orders (2026-07-25); absent = DEFAULT_TACTICS (rivals, legacy saves)
  protect?: boolean // team-event "protect target" designation — allies guard/heal this monster first
  marked?: boolean // team-event kill order on an ENEMY monster (set via scouting) — the whole opposing team strikes it first while reachable
  // PERSONALITY DRIFT (v0.93). The innate block is DERIVED from `seed` (see
  // tamerengine/personality.ts) so it costs no generation rng and every existing save
  // already has one. This optional field is only the drift earned afterwards
  // through training, care or breeding — absent means "still exactly as born".
  personality?: Partial<Personality>
}

// Who a monster IS, as opposed to what you tell it to do (v0.93). 0..100 each.
// Tactics are COACHING applied on top of this; `temperament` decides how much of
// that coaching actually sticks. Read by the field engine only — the
// turn-based engine in battle.ts never looks at it, so goldens are unaffected.
export interface Personality {
  aggression: number // how early and how deep it commits
  teamplay: number // fights as a unit — shares focus, stays with the group
  mental: number // holds together under pressure; low panics and chases bait
  temperament: number // biddable — how much of your coaching actually sticks
  awareness: number // notices threats: a diver on the backline, an ally in trouble
  patience: number // holds its big cooldowns for the right moment instead of dumping them
  // Target commitment (v0.94, docs/PERSONALITY_STATS.md §1): sticky vs reassess.
  // ⚠️ Appended LAST on purpose — see personality.ts's stream-order note.
  focus: number
}

// --- Tactics (2026-07-25): pre-battle standing orders, Teamfight-Manager
// style — the player is a coach, not a puppeteer. Each tactic parameterizes
// the EXISTING battle AI (class personality thresholds, target picking);
// the defaults reproduce the untuned AI exactly, so a monster with no
// tactics set fights precisely as it always has. ---
export type Temperament = 'aggressive' | 'balanced' | 'cautious'
/**
 * The player's standing target order. OPTIONAL — no order means the monster fights
 * whatever is nearest, which `decide.ts` handles natively.
 *
 * ⚠️ `weakest` IS GONE, AND IT WAS THE DEFAULT. It said "finish the wounded", which the
 * engine already does on its own: the ranged score carries a `0.85 * wounded` term
 * independent of any order, so removing the ORDER does not remove the BEHAVIOUR. As an
 * order it was the one option that could never become a filter — a ranking, not a set —
 * and it forced the whole system to carry a special case for the sake of an instruction
 * that duplicated an autonomous heuristic.
 *
 * ⚠️ `focus` IS NOW `manmark`, AND THE RENAME IS A BUG FIX. Its UI description read
 * "Pile onto whichever enemy a teammate struck last" while the code read `e.m.marked` —
 * i.e. it was never focus-fire at all, it was the man-mark, wired end to end and
 * described as something else. The mark picker, `MatchOrders.mark` and
 * `applyMarkToOpponent` all already existed; only the name lied.
 */
export type TargetPriority = 'casters' | 'tanks' | 'manmark'
export type ManaPolicy = 'normal' | 'conserve' | 'burst'
export type Preserve = 'off' | 'cautious' | 'defensive'
export interface Tactics {
  temperament: Temperament
  targetPriority?: TargetPriority
  manaPolicy?: ManaPolicy // absent = 'normal' (inert)
  /**
   * COMBO ROLE — which half of a prime/detonate pair this monster plays.
   *
   *   'prime'     weight APPLYING a status the team can cash; give up damage for it
   *   'detonate'  prefer TARGETS already carrying a status this monster can cash
   *   absent      fire whatever scores best
   *
   * ⚠️ REPLACED `comboDiscipline: boolean`, which had no wrong answer and so was
   * not a decision. "Hold the payoff for its window" is either strictly right or a
   * pure tempo loss depending on whether the setup lands — which the player does
   * not choose, they only watch. Split across the two HALVES of a combo it becomes
   * role assignment, and both extremes fail: an all-prime team never converts, an
   * all-detonate team stalls because nobody applies anything.
   *
   * ⚠️ NAMED prime/detonate, NOT start/finish. `manaPolicy`'s reserve is already
   * "the finisher fund" (FINISHER_AT), `openerIds` already owns "opener", and the
   * scouting flag already owns "mark". The pool also contains a move literally
   * called Detonate, so the game speaks this vocabulary already.
   *
   * ⚠️ MEANINGLESS ON ~32% OF MONSTERS — the ones whose loadout holds neither an
   * applier nor a payoff. The UI must gate the row on the kit or it is a live
   * control that does nothing, which is this project's signature failure mode.
   */
  comboRole?: 'prime' | 'detonate'
  /**
   * Scripted opening SEQUENCE: up to 2 equipped move ids, played in order on the
   * monster's first actions.
   *
   * ⚠️ `engageRange` AND THE LEGACY `openerId` WERE REMOVED ALONGSIDE THIS (2026-
   * 08-01). `engageRange` was superseded by `CLASS_BASIC` — reach is now decided by
   * what a monster is holding, and `reachOf` takes the shorter of best weapon and
   * class basic, so an order telling it where to stand fought the thing that
   * already knew. `openerId` was a single-id predecessor kept as a fallback that
   * no save has written since v0.81.
   */
  openerIds?: string[]
  preserve?: Preserve // absent = 'off' — below the threshold, play to survive (block, drop self-harm moves)
  ccPriority?: boolean // lead with a hard control status (stun/sleep/silence/…) before committing to damage
  // ── SPATIAL ORDERS (v0.93, field engine only) ────────────────────────────
  // Orders that only mean anything once monsters occupy real ground. All
  // optional and read ONLY by src/field — battle.ts ignores them, so adding
  // them cannot move a golden. Like every other order they are COACHING: how
  // much of each actually lands is gated by the monster's temperament.
  /**
   * FORMATION — how much of the deployed shape this monster holds onto.
   *
   *   'keep'    hold the SLOT it deployed in, relative to the team as it advances
   *   'tight'   no slot; drift with the team and clump up (focus-fire, AoE bait)
   *   'spread'  no slot; drift with the team but fan out (AoE insurance)
   *
   * ⚠️ REPLACED `spacing`, which was never formation. `spacingRadius` is a
   * personal-space radius — how close allies stand — and nothing else. The thing
   * that actually held a team together was the cohesion pull toward the LIVE ALLY
   * CENTROID: a blob that drifts, not a shape. So the deploy screen let a player
   * place a wall in front and a healer behind, and the first second of the fight
   * dissolved it. 'keep' is the option that makes deployment mean something for
   * longer than tick 1.
   *
   * ⚠️ NO 'break' OPTION, DELIBERATELY. A monster ordered to ignore the team and
   * hunt the enemy back line was designed and rejected: it re-creates by order the
   * single shape this engine balances worst (melee measured 100% deaths alone
   * against 81% beside a second front-liner), and it would have needed the melee
   * nearest-target early return in `decide.ts:pickTarget` opened up — the guard
   * whose own comment records that value-chasing "is exactly what made melee race
   * around the map". Do not re-add it without solving that first.
   */
  formation?: 'keep' | 'tight' | 'spread'
  useCover?: boolean // prefer ground where an obstacle breaks enemy line of sight
  commit?: 'dive' | 'hold' // chase past the enemy front line, or refuse to over-extend
  /**
   * WHEN a restore is spent. 'triage' holds it until an ally is actually hurt;
   * 'steady' fires it whenever it is up.
   *
   * ⚠️ TRIAGE IS THE DEFAULT, AND IT IS A MEASURED CHOICE. Three paired A/Bs on
   * HEAL_MULT (1.3, 2.5, 1.3 on a richer pool) all read NULL, and every one
   * showed support-heavy sides getting FASTER with stronger healing — Vanguard v
   * Choir -18.3s at 2.5x. Healing was acting as a tempo multiplier rather than an
   * attrition brake, and the leading explanation is that heals were scored
   * alongside buffs and fired at full health, which is wasted throughput.
   * 'steady' keeps that behaviour for anyone who wants it.
   */
  healPolicy?: 'steady' | 'triage'
  /**
   * How the monster spends its BIGGEST move. 'nuke' holds it for a target worth
   * finishing; 'steady' fires it the moment it is up.
   * ⚠️ This was a HIDDEN stat. It is derived from CON+WIS-DEX as `patience` in
   * personality.ts and silently decided whether a monster would use its best
   * ability at all — a player could train a monster that simply refused to open
   * with its capstone and had no way to see why, let alone change it. Coaching
   * bends it exactly like every other order here, gated by temperament.
   */
  burst?: 'nuke' | 'steady'
}
export const DEFAULT_TACTICS: Tactics = {
  temperament: 'balanced', healPolicy: 'triage',
}

// --- Per-fight orders (v0.81): tactics are chosen fresh before EACH battle the
// player fights (like abilities are chosen before a tournament), not stored as a
// monster's standing trait. One MatchOrders per player-match captures the whole
// pre-fight screen: each member's Tactics (by monster id), the formation (member
// row order), a protect order, and an optional kill-order mark (opponent slot).
export interface MatchOrders {
  tactics: Record<string, Tactics> // by player-monster id
  formation: string[] // player-monster ids, in row order (first half = front line)
  protectId?: string // the member ordered to guard its allies
  mark?: number // opponent slot the whole team focuses first
}

// A tournament (or trial) that advanceWeek has STAGED but not resolved: the
// player fights each of their matches interactively, picking MatchOrders before
// each, and the event is finalized (rewards/injury/standings) only when the last
// player match ends. Serializable so an in-flight event survives save/reload.
export interface ActiveCup {
  kind: 'cup' | 'trial' | 'rite' // 'rite' = the Signature Rite (v0.91), a 1v1 on-demand challenge
  tournamentId: string
  week: number // the tournament's week (advanceWeek increments g.week, so this is stored for calendar/reward/injury lookups)
  playerMonsterIds: string[] // the fielded team, fixed for the event
  rivalTeams: Monster[][] // the field, generated once at stage time (with gameplans applied)
  matchOrders: Record<number, MatchOrders> // by player-match index (0-based)
  doneThrough: number // highest player-match index already fought (-1 = none yet)
}

// Formation (wave 2): roster ORDER is the formation — the first half of a
// team fights in the front line, the rest in the back line. Single-target
// MELEE attacks (including a melee-channel basic Attack) can only reach the
// front line while it stands; ranged/magic/voice ignore rows entirely, and
// AoE always hits everyone. A solo team is all front line.
// The front line is the first TWO monsters in roster order — THREE at 6v6
// (user spec 2026-07-27). It was ceil(teamSize/2), which made "front row" mean
// something different in every league; pinning it makes formation a legible,
// near-constant decision, with the top league widening the wall by one because
// six bodies behind two shields left the back far too safe.
//
// ⚠️ Rows are LIVE, not fixed at setup: a combatant's row is its index among its
// STILL-LIVING teammates, so when a front-liner falls the rank behind steps up
// (see rowOfLiving in battle.ts). This function answers "how wide is the front
// line for a team of this many SURVIVORS".
//
// What the front line gates: single-target MELEE can only reach it while it
// stands. Melee AoE (allEnemies) and melee scattering strikes (randomTargets)
// deliberately IGNORE it and can hit anyone — that exemption is what makes those
// moves the answer to a turtled back line.
// ⚠️ THE `>= 6` BRANCH IS NOW DEAD — 6v6 was removed 2026-08-01 and
// TEAM_SIZE_BY_LEAGUE caps at 5. Kept rather than deleted because it is the only
// record of WHY the wall ever widened ("six bodies behind two shields left the
// back far too safe"); if a bigger fight is ever reintroduced, that reasoning
// applies again and this is where it lives.
export const frontRowCount = (teamSize: number) => (teamSize >= 6 ? 3 : Math.min(2, teamSize))
export const rowOfSlot = (slot: number, teamSize: number): 'front' | 'back' =>
  slot < frontRowCount(teamSize) ? 'front' : 'back'

export const TEMPERAMENT_INFO: { id: Temperament; icon: string; name: string; desc: string }[] = [
  { id: 'aggressive', icon: '⚔', name: 'Aggressive', desc: 'Keeps swinging even when hurt — blocks, parries and heals late, spends MP freely.' },
  { id: 'balanced', icon: '⚖', name: 'Balanced', desc: "Fights on its class's natural instincts." },
  { id: 'cautious', icon: '🛡', name: 'Cautious', desc: 'Guards early and heals early — takes fewer risks, deals less pressure.' },
]
export const TARGET_PRIORITY_INFO: { id: TargetPriority; icon: string; name: string; desc: string }[] = [
  { id: 'casters', icon: '🧙', name: 'Hunt the casters', desc: "Go for the enemy's supports — silence the heals before they undo your damage." },
  // ⚠️ ITS LOW LIFT OVER BLIND TARGETING IS NOT A FAULT, AND THIS NOTE EXISTS SO NOBODY
  // "FIXES" IT ON THAT NUMBER. `tools/targeting.ts` reads 96.3% of damage on high-HP
  // enemies with the order against an 83.3% blind baseline — a +13pp lift where casters
  // gets +24pp — because tanks stand in front and untargeted melee already hits them.
  // Judging the order by its lift measures HOW MUCH IT CHANGES BEHAVIOUR, not how much
  // it is worth, and those are different questions:
  //   • It is the COMMITMENT order, not a redirection one. Casters and manmark both send
  //     monsters PAST the front line; this is the only one that says stay on it, so a
  //     team holding it will not peel onto a squishy that wanders into reach. A high
  //     blind baseline means it is cheap and reliable to obey.
  //   • And it aims at the game's dominant grind lever. `tools/focus.ts` measured maxHp
  //     at r=+0.79 against time-to-first-kill — the strongest correlate it found, 1.84x
  //     the span of focus itself. The remaining 16.7pp was being sprayed off the one
  //     body that takes longest to kill.
  { id: 'tanks', icon: '🐘', name: 'Break the tank', desc: 'Go for the highest-CON wall and stay on it — your team will not peel off onto softer targets.' },
  // ⚠️ THE ONLY ORDER THAT NAMES A SPECIFIC MONSTER, AND THE ONLY ONE SCOUTING PAYS FOR.
  // The other two describe a KIND of enemy and can be set blind; this one requires
  // knowing who is actually in the opposing team, which is what the scout sells.
  { id: 'manmark', icon: '🎯', name: 'Man mark', desc: 'Hunt the one monster you marked — set the mark below. Requires scouting.' },
]
export const MANA_POLICY_INFO: { id: ManaPolicy; icon: string; name: string; desc: string }[] = [
  { id: 'burst', icon: '💥', name: 'Opening burst', desc: 'Spend MP freely and early — hit hard before the enemy settles in.' },
  { id: 'normal', icon: '💠', name: 'As needed', desc: "Spend MP on the class's own judgement." },
  { id: 'conserve', icon: '💧', name: 'Conserve', desc: 'Save MP for clearly worthwhile skills — charge up rather than waste casts.' },
]
export const COMBO_INFO: { id: Tactics['comboRole']; icon: string; name: string; desc: string }[] = [
  { id: undefined, icon: '🎲', name: 'Free play', desc: 'Casts whatever ranks best each turn.' },
  { id: 'prime', icon: '🧪', name: 'Prime', desc: 'Leads with the status its team can cash — trades its own damage to set the kill up.' },
  { id: 'detonate', icon: '💥', name: 'Detonate', desc: 'Hunts whoever is already primed, so its payoff move actually collects.' },
]
// Preserve (v0.81): a survival floor — below the threshold, guard a real
// incoming hit instead of trading to the death, and stop throwing self-harm
// (recoil) moves. 'off' is inert (golden-safe).
export const PRESERVE_INFO: { id: Preserve; icon: string; name: string; desc: string }[] = [
  { id: 'off', icon: '🔥', name: 'To the end', desc: 'Never plays safe — fights at full aggression down to 1 HP.' },
  { id: 'cautious', icon: '🛡', name: 'Guard at 40%', desc: 'Below 40% HP: blocks incoming hits and avoids self-harm moves.' },
  { id: 'defensive', icon: '🐢', name: 'Guard at 25%', desc: 'Below 25% HP: turtles up hard to survive.' },
]
// CC priority (v0.81): lead with a hard control status before damage.
export const CC_INFO: { id: boolean; icon: string; name: string; desc: string }[] = [
  { id: false, icon: '🎲', name: 'Off', desc: 'Weighs control moves alongside everything else.' },
  { id: true, icon: '🕸', name: 'Control first', desc: 'Opens by landing a stun / sleep / silence / fear etc. before committing to damage.' },
]

// --- Rival team gameplans (LOOP_DESIGN.md Phase 3) ---
// A rival team's standing orders, expressed through the SAME Tactics the player
// uses (no separate rival AI). Scouting reveals the archetype + a counter-hint,
// closing the scout → adapt → win loop. `tell` is the composition flavour shown
// once scouted; `counter` is the actionable hint.
export type TeamGameplan = 'rushdown' | 'bulwark' | 'attrition' | 'focusfire' | 'zone'
export interface GameplanInfo {
  name: string
  icon: string
  tell: string
  counter: string
  tactics: Tactics
  protectCarry?: boolean // guard the team's top damage dealer (bulwark)
  // --- TEAM BUILDING (v0.91). Before this, a gameplan was picked at random and
  // STAMPED ON a team that had already been generated half-damage/half-support —
  // so 'bulwark' regularly landed on a roster with no tanks and 'attrition' on
  // one with no sustain. The plan never shaped the roster it was supposedly
  // describing. These fields make the archetype BUILD the team.
  winCon: string // the plain-English thing this team is trying to do — shown when scouted
  mix: { damage: number; support: number } // relative weights for the role split
  wants?: {
    status?: StatusKind // a status the team actively tries to apply and build on
    payoff?: boolean // reserve a slot for a bonusVsStatus finisher that cashes `status`
    teamBuff?: boolean // reserve a slot for a team-target buff on at least one member
    aoe?: boolean // prefer multi-target damage over single-target
  }
}
export const GAMEPLANS: Record<TeamGameplan, GameplanInfo> = {
  rushdown: {
    name: 'Rushdown', icon: '🔥',
    tell: 'Fast, aggressive, no support — all pressure.',
    counter: "They rush your softest monster and spend big early. Put a tank up front, or burst them before they snowball.",
    tactics: { temperament: 'aggressive', manaPolicy: 'burst', healPolicy: 'steady' },
    winCon: 'Kill something in the first three rounds and snowball the numbers advantage.',
    mix: { damage: 5, support: 1 },
  },
  bulwark: {
    name: 'Bulwark', icon: '🛡',
    tell: 'Tanks and guardians around a protected carry.',
    counter: "They turtle and guard one damage dealer. Grind the wall down, or focus the protected monster before its guards react.",
    tactics: { temperament: 'cautious', manaPolicy: 'conserve' },
    protectCarry: true,
    winCon: 'Keep one carry alive behind a wall until it out-damages everything you have left.',
    mix: { damage: 1, support: 3 },
    wants: { teamBuff: true },
  },
  attrition: {
    name: 'Attrition', icon: '☠',
    tell: 'Poison, bleed and stall — out-lasts you.',
    counter: "They drag the fight long and out-sustain you. End it fast, or bring cleanse and healing to weather it.",
    tactics: { temperament: 'cautious', manaPolicy: 'conserve', comboRole: 'detonate' },
    winCon: 'Stack poison on everything and outlive the clock.',
    mix: { damage: 2, support: 2 },
    wants: { status: 'poison', payoff: true, teamBuff: true },
  },
  focusfire: {
    name: 'Focus-Fire', icon: '🎯',
    tell: 'High burst — the whole team piles on one target.',
    counter: "They assassinate one of your monsters early. Protect your carry, or spread durability so no single loss breaks you.",
    tactics: { temperament: 'aggressive', targetPriority: 'manmark' },
    winCon: 'Mark one monster Vulnerable and delete it before it acts twice.',
    mix: { damage: 3, support: 2 },
    wants: { status: 'vulnerable', payoff: true },
  },
  zone: {
    name: 'Zone', icon: '🌩',
    tell: 'Back-row casters hunting your fragile monsters.',
    counter: "They hunt your casters. Shield your back line, or lead with a durable front they have to chew through first.",
    tactics: { temperament: 'balanced', targetPriority: 'casters' },
    winCon: 'Blanket the whole team in area damage and burn, and never trade one-for-one.',
    mix: { damage: 3, support: 2 },
    wants: { status: 'burn', aoe: true },
  },
}

// --- Leagues (license -> stat cap), §3 ---
export interface League { name: string; cap: number }
export const LEAGUES: League[] = [
  { name: 'Wood', cap: 100 },
  { name: 'Copper', cap: 200 },
  { name: 'Tin', cap: 300 },
  { name: 'Bronze', cap: 400 },
  { name: 'Iron', cap: 500 },
  { name: 'Silver', cap: 600 },
  // v0.88: the top of the curve steepens — the last four rungs pull away from
  // the flat +100/league of the lower circuit, so each late promotion is a real
  // jump. A gen-1 monster (walled at 700–1100) cannot compete at the top: only a
  // bred dynasty reaches those ceilings.
  //
  // ⚠️ THE TOP RUNGS TIGHTEN, THEY DO NOT EXPLODE (v0.93). Tamer Elite 1200 ->
  // 1050 and Apex 1400 -> 1100. The ceiling barely moves past Masters; what
  // separates the top three leagues is the TRAINING INVESTED to approach it, not
  // a bigger number to reach for. See LEAGUE_TRAIN in tools/leagues.ts — Masters
  // is simulated at a 2195 budget, Elite at 2800 and Apex at 3500 against caps
  // only 50 and 100 apart, so the last stretch is grinding the final points out
  // of a nearly-flat ceiling rather than chasing a receding one.
  { name: 'Gold', cap: 750 },
  { name: 'Platinum', cap: 900 },
  { name: 'Masters', cap: 1000 },
  { name: 'Tamer Elite', cap: 1050 },
  { name: 'Tamers Apex', cap: 1100 },
]

export function leagueForStat(maxStat: number): string {
  for (const l of LEAGUES) if (maxStat <= l.cap) return l.name
  return 'Tamers Apex'
}

// --- Classes (primary/secondary), balanced table §6 ---
export interface ClassDef { name: string; primary: Stat; secondary: Stat }
export const CLASSES: ClassDef[] = [
  { name: 'Tank', primary: 'CON', secondary: 'STR' },
  { name: 'Warrior', primary: 'STR', secondary: 'CON' },
  { name: 'Rogue', primary: 'DEX', secondary: 'STR' },
  { name: 'Ranger', primary: 'DEX', secondary: 'INT' },
  { name: 'Sage', primary: 'WIS', secondary: 'INT' },
  { name: 'Wizard', primary: 'INT', secondary: 'WIS' },
  { name: 'Spellsword', primary: 'INT', secondary: 'CON' },
  { name: 'Spellshield', primary: 'CON', secondary: 'WIS' },
  { name: 'Captain', primary: 'STR', secondary: 'CHA' },
  { name: 'Orator', primary: 'CHA', secondary: 'WIS' },
  { name: 'Bard', primary: 'CHA', secondary: 'DEX' },
  // ── The orphan-pair seven (2026-07-30) ────────────────────────────────────
  // ⚠️ Six stats give THIRTY ordered pairs and only eleven were mapped, so the
  // other nineteen all fell through to Generalist — 18.1% of every monster
  // generated across all 65 species and three training levels. A Generalist has
  // no CLASS_LINES affinity, no utility profile and no slot plan, so nearly a
  // fifth of the population had no kit identity at all. Worse, Generalist came
  // out as the TOP damage class in the sweep, which is absurd for a fallback.
  // These seven are the most COMMON orphan pairs, measured rather than guessed;
  // together they cover 15.0% of the population and take Generalist to ~3%.
  { name: 'Evoker', primary: 'INT', secondary: 'DEX' },        // 3.79%
  { name: 'Skirmisher', primary: 'STR', secondary: 'DEX' },    // 3.03%
  { name: 'Stalker', primary: 'DEX', secondary: 'WIS' },       // 2.14%
  { name: 'Swashbuckler', primary: 'DEX', secondary: 'CHA' },  // 2.00%
  { name: 'Shaman', primary: 'WIS', secondary: 'CON' },        // 1.50%
  { name: 'Mystic', primary: 'WIS', secondary: 'DEX' },        // 1.42%
  { name: 'Herald', primary: 'CHA', secondary: 'STR' },        // 1.09%
]

// Emergent class from the two highest stats (§6.2). Falls back to Generalist.
export function classForStats(stats: Stats): string {
  const ordered = [...STATS].sort((a, b) => stats[b] - stats[a])
  const [p, s] = ordered
  const hit = CLASSES.find((c) => c.primary === p && c.secondary === s)
  return hit ? hit.name : 'Generalist'
}

// Battle role per class (user spec 2026-07-21): drives rival-team composition
// templates ("a mixture of support and damage dealing classes") and class-aware
// loadout/AI behavior. Tanks count as support — they enable, not carry, damage.
export type ClassRole = 'damage' | 'support'
export const CLASS_ROLES: Record<string, ClassRole> = {
  Warrior: 'damage', Rogue: 'damage', Ranger: 'damage', Wizard: 'damage',
  Spellsword: 'damage', Captain: 'damage',
  Tank: 'support', Spellshield: 'support', Sage: 'support', Orator: 'support', Bard: 'support',
  // The orphan-pair seven. WIS finally has primaries other than Sage — it had
  // exactly ONE class to its name while STR, DEX and INT had three each.
  Evoker: 'damage', Skirmisher: 'damage', Stalker: 'damage', Swashbuckler: 'damage',
  Shaman: 'support', Mystic: 'support', Herald: 'support',
}
export const roleOfClass = (className: string): ClassRole => CLASS_ROLES[className] ?? 'damage'

// Body-type averages + species signatures moved to species.ts — they're computed
// from the actual SPECIES data so they can never drift out of sync again.

// --- Food & happiness (§2.4 / §12) ---
// Three tiers (2026-07-25 food overhaul):
//   normal   — flat 10g, taste-based ±1 happiness (feedDelta); the casual baseline.
//   training — a specialist ration: +30% to its stat-pair's drills this week,
//              paid for with −1 happiness and −15 stamina (a food "intensive drill").
//   premium  — pricey specials: raw stamina/happiness top-ups, or the Golden
//              Truffle's win-conditional reward gamble.
// All prices flow through rollMarket's weekly ±40% fluctuation automatically.
export interface FoodDef {
  id: Food
  name: string
  price: number
  tier: FoodTier
  icon: string
  desc: string
  boostStats?: Stat[] // training: drills whose primary stat is here gain boostMult
  boostMult?: number  // e.g. 0.3 → +30%
  happiness?: number  // FIXED happiness delta (training/premium ignore taste); undefined = taste via feedDelta (normal)
  stamina?: number    // flat stamina delta (+restore / −cost)
  rewardMult?: number // Golden Truffle: pending multiplier on the next cup WON
}
export const FOODS: FoodDef[] = [
  { id: 'vegetables', name: 'Vegetables', price: 10, tier: 'normal', icon: '🥬', desc: 'Basic ration — ±1 happiness by taste.' },
  { id: 'fruit', name: 'Fruit', price: 10, tier: 'normal', icon: '🍎', desc: 'Basic ration — ±1 happiness by taste.' },
  { id: 'meat', name: 'Meat', price: 10, tier: 'normal', icon: '🍖', desc: 'Basic ration — ±1 happiness by taste.' },
  { id: 'sweet treats', name: 'Sweet Treats', price: 10, tier: 'normal', icon: '🍰', desc: 'Basic ration — ±1 happiness by taste.' },
  { id: 'prime cut', name: 'Prime Cut', price: 75, tier: 'training', icon: '🥩', desc: 'STR & CON training +30% · −1 happiness · −15 stamina.', boostStats: ['STR', 'CON'], boostMult: 0.3, happiness: -1, stamina: -15 },
  { id: 'scholars tea', name: "Scholar's Tea", price: 75, tier: 'training', icon: '🌿', desc: 'WIS & INT training +30% · −1 happiness · −15 stamina.', boostStats: ['WIS', 'INT'], boostMult: 0.3, happiness: -1, stamina: -15 },
  { id: 'sprinters mix', name: "Sprinter's Mix", price: 75, tier: 'training', icon: '⚡', desc: 'DEX & CHA training +30% · −1 happiness · −15 stamina.', boostStats: ['DEX', 'CHA'], boostMult: 0.3, happiness: -1, stamina: -15 },
  { id: 'vigor melon', name: 'Vigor Melon', price: 90, tier: 'premium', icon: '🍈', desc: '+30 stamina.', stamina: 30 },
  { id: 'bliss berry', name: 'Bliss Berry', price: 90, tier: 'premium', icon: '🫐', desc: '+3 happiness.', happiness: 3 },
  { id: 'golden truffle', name: 'Golden Truffle', price: 500, tier: 'premium', icon: '🟡', desc: 'Win your next cup → +50% gold & exp. Nothing if you lose.', rewardMult: 1.5 },
]
export const foodDef = (id: Food): FoodDef => FOODS.find((f) => f.id === id)!
// The basic-taste foods a monster can have as a favourite/hated food. Kept to the
// four normal rations (a premium/training food isn't a "taste" preference) — this
// is also what monster generation draws from, so the roster can grow with new
// training/premium foods without shifting generation's RNG stream.
export const NORMAL_FOODS: FoodDef[] = FOODS.filter((f) => f.tier === 'normal')
// Discount group for the two-stage Bulk contracts: normal foods vs everything
// premium (training foods count as premium for the Grand Larder).
export const foodDiscountGroup = (id: Food): 'normal' | 'premium' => (foodDef(id).tier === 'normal' ? 'normal' : 'premium')
export const MAX_HAPPINESS = 10
// Happiness 0..10 → +1% damage per point (1.10× at 10).
export const happinessMultiplier = (happiness: number) => 1 + 0.01 * happiness
// Feeding: favourite +1 happiness, hated −1, anything else neutral.
export function feedDelta(food: Food, fav: Food, hated: Food): number {
  if (food === fav) return 1
  if (food === hated) return -1
  return 0
}

// --- Rivals (LOOP_DESIGN.md Phase 2) ---
// A named trainer who climbs the ladder alongside the player, gives the ladder
// a recurring face, and carries a tracked head-to-head grudge. Phase 2 meets
// them via off-calendar challenge skirmishes; Phase 3 seats them into cups with
// a team gameplan (the `personality` colours that + their between-match voice).
export type RivalPersonality = 'aggressive' | 'cagey' | 'flashy'
export interface Rival {
  id: string
  name: string
  personality: RivalPersonality
  licenseIndex: number // rubber-banded toward the player's highest so they stay a threat
  wins: number // player's POV: times the player beat this rival
  losses: number // player's POV: times this rival beat the player
}

// --- Status descriptions (§7.6) ---
export const STATUS_INFO: Record<StatusKind, string> = {
  blind: 'Lowers the target’s chance to hit.',
  poison: 'Ongoing mana damage.',
  burn: 'Ongoing HP damage (fire).',
  fear: 'Briefly flees; loses its action.',
  confusion: 'Next ability may hit itself (20%).',
  stun: 'Cannot act briefly.',
  knockback: 'Shoved back; acts last while it lasts.',
  bleed: 'Ongoing physical HP damage; stacks up to 3.',
  silence: 'Cannot use skills — only Attack and Block.',
  vulnerable: 'Takes 20% more damage.',
  sleep: 'Cannot act; wakes when damaged.',
  doom: 'When the countdown ends, takes a heavy burst of damage. Cleansable.',
  healblock: 'Healing, lifesteal and HP regen are 60% less effective.',
  haste: 'Acts first in the round while it lasts. (Beneficial — not removed by cleanses.)',
  charm: 'Single-target hostile actions strike its own allies.',
}

// --- Learn ladder (§7.2) ---
export const LEARN_LADDER = [40, 90, 160, 240, 330, 430, 540, 650, 780, 920]

// A species' 2nd innate is no better than the 1st — it's an ALTERNATIVE, not
// an upgrade (user spec 2026-07-25). The 1st is available from the start; the
// 2nd unlocks once the monster's highest stat reaches this level. Only ONE
// innate is ever active at a time — swapped via the same slot-click UI as
// loadout moves. (Species ultimates were REMOVED entirely 2026-07-25 — their
// descriptions promised effects the engine never delivered.)
export const INNATE_SECONDARY_LEVEL = 300

// --- Seeded RNG: mulberry32 + string hash ---
export function hashString(str: string): number {
  let h = 1779033703 ^ str.length
  for (let i = 0; i < str.length; i++) {
    h = Math.imul(h ^ str.charCodeAt(i), 3432918353)
    h = (h << 13) | (h >>> 19)
  }
  return h >>> 0
}

export function mulberry32(seed: number): () => number {
  let a = seed >>> 0
  return function () {
    a |= 0
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

export type RNG = () => number
export const randInt = (rng: RNG, min: number, max: number) => Math.floor(rng() * (max - min + 1)) + min
export const chance = (rng: RNG, pct: number) => rng() * 100 < pct
export const pick = <T>(rng: RNG, arr: T[]): T => arr[Math.floor(rng() * arr.length)]
