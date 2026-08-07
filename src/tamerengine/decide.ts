// The brain of the field engine: who do I attack, and where do I stand?
//
// Everything here is a PURE function of the units' state — no randomness, no
// mutation — so it is directly unit-testable and the tick loop stays readable.
import { Monster, Stat, roleOfClass, classForStats, TargetPriority } from '../core'
import { FieldTraits, FieldUnit, Vec2, FIELD_W, FIELD_H, CHANNEL_RANGE, LEASH_RADIUS, CLASS_BASIC, FORMATION_KEEP_PULL, MELEE_PRIORITY_SLACK, ORDER_DIVE_OVERRIDE, ORDER_REACH, COMBO_TARGET_BIAS} from './types'
import { coachedValue, panicThreshold, personalityOf, resolvePersonality, threatRadius } from './personality'

export const v = (x: number, y: number): Vec2 => ({ x, y })
export const sub = (a: Vec2, b: Vec2): Vec2 => ({ x: a.x - b.x, y: a.y - b.y })
export const add = (a: Vec2, b: Vec2): Vec2 => ({ x: a.x + b.x, y: a.y + b.y })
export const scale = (a: Vec2, k: number): Vec2 => ({ x: a.x * k, y: a.y * k })
export const len = (a: Vec2): number => Math.hypot(a.x, a.y)
export const dist = (a: Vec2, b: Vec2): number => Math.hypot(a.x - b.x, a.y - b.y)
export const norm = (a: Vec2): Vec2 => {
  const l = Math.hypot(a.x, a.y)
  return l < 1e-6 ? { x: 0, y: 0 } : { x: a.x / l, y: a.y / l }
}
const clamp01 = (n: number) => Math.min(1, Math.max(0, n))
// ⚠️ Computed PER CALL, not once at module load. As a load-time const it froze
// at whatever the field was when the module was first imported, so on any arena
// but the default the proximity term below silently used the wrong diagonal.
const fieldDiag = () => Math.hypot(FIELD_W, FIELD_H)

/** Injected clearance test — decide.ts must not import engine (engine imports it). */
export type LosFn = (a: Vec2, b: Vec2) => boolean

// ── The two new stats ───────────────────────────────────────────────────────
// Derived from the coaching the player ALREADY sets (tactics) plus the
// monster's emergent class, so the feature needs no new authored data to work.
// They are first-class fields on the unit, so they can later be authored,
// trained, or bred without changing any of the logic that consumes them.
export function traitsFor(m: Monster): FieldTraits {
  // PERSONALITY FIRST, coaching second. resolvePersonality blends the monster's
  // innate aggression/teamplay with what your Tactics are asking for, weighted
  // by its DISCIPLINE — so an untemperamentd bruiser ordered to hold back still
  // charges. These two numbers are the whole behavioural identity of the unit.
  const { aggression, teamplay } = resolvePersonality(m)
  let predation = aggression
  let cohesion = teamplay

  // Small role/order nudges on top of who it is.
  if (roleOfClass(m.className) === 'support') cohesion += 0.12
  if (m.protect) cohesion += 0.12 // told to guard someone: by definition a team player
  if (m.tactics?.targetPriority === 'tanks') predation -= 0.1 // content to grind the front

  return { cohesion: clamp01(cohesion), predation: clamp01(predation) }
}

/** Rough offensive output, used to judge how dangerous an enemy is. */
export function threatOf(m: Monster): number {
  const statOf = (s: Stat) => m.stats[s] ?? 0
  let best = 0
  for (const mv of m.loadout) {
    if (mv.type !== 'damage') continue
    best = Math.max(best, mv.power * (1 + statOf(mv.stat) / 400))
  }
  return best
}

/** How rewarding this enemy is to kill: high output, low durability. */
export function valueOf(u: FieldUnit): number {
  const out = clamp01(threatOf(u.m) / 140)
  const tough = clamp01(u.maxHp / 900)
  return clamp01(out * (1.2 - tough * 0.7))
}

/** The reach of the longest-ranged damaging move this unit can currently use. */
/**
 * The range this monster wants to FIGHT at.
 *
 * ⚠️ DAMAGE MOVES ONLY. Scanning the whole loadout meant a melee bruiser
 * carrying any support move — a war cry, a heal, a taunt, all of which reach
 * 5–6 — took its stand-off distance from that and parked outside its own
 * swinging range, never landing a blow all fight. A support move's reach
 * governs when that move can be cast (checked separately), never where the
 * monster chooses to stand.
 */
export function reachOf(u: FieldUnit): number {
  // ⚠️ THE RANGE OF ITS BEST WEAPON, NOT THE LONGEST THING IT HAPPENS TO CARRY.
  // This returned the MAXIMUM range across the kit, which quietly forbade mixed
  // builds: give a Warrior a fireball and its reach became 7, so it stood at
  // 5.25 and never closed — the fireball did not ADD an option, it deleted every
  // melee move in the kit. Same for a Rogue handed a long shot: it stopped
  // closing for its Assassin line.
  //
  // The asymmetry is the whole argument. A cast is gated on `d <= range`, so
  // standing CLOSE never blocks a longer move, while standing FAR blocks every
  // shorter one. Positioning should therefore follow the weapon the monster most
  // wants to use; anything longer still fires from there for free.
  //
  // ⚠️ Not the MINIMUM either — that would drag a Wizard who drafted one stray
  // melee move into contact. Highest VALUE, so a stray off-stat move is simply
  // never the thing it positions around.
  let bestVal = -1
  let bestRange = 0
  for (const mv of u.m.loadout) {
    if (mv.type !== 'damage') continue
    const val = mv.power * (1 + (u.m.stats[mv.stat] ?? 0) / 400)
    if (val > bestVal) {
      bestVal = val
      bestRange = mv.range ?? CHANNEL_RANGE[mv.channel]
    }
  }
  const best = bestRange || CHANNEL_RANGE.melee
  // ⚠️ STAND WHERE EVERYTHING IN YOUR HANDS WORKS. A cast is gated on
  // `d <= range`, so closing never forbids a longer move while holding back
  // forbids every shorter one — the asymmetry argued above, applied once more.
  // The class's free attack (CLASS_BASIC) is a weapon like any other, and it is
  // the one that is ALWAYS up, so a standoff it cannot reach from leaves the
  // unit with nothing to do between cooldowns. Measured on the authored table:
  // 31.7% of monsters parked outside their own free attack, worst at Rogue
  // (67%) and Spellsword (100%) — the DEX and INT classes whose lines span both
  // a blade and a shot.
  //
  // ⚠️ This is NOT the MIN-over-the-kit rejected above. That would drag a Wizard
  // in on one stray melee move; this takes the min of exactly two things, and a
  // stray move is neither the best weapon nor the class basic.
  const basic = CLASS_BASIC[classForStats(u.m.stats)] ?? CLASS_BASIC.Generalist
  return Math.min(best, basic.range)
}

/**
 * MELEE = "can only hit what's adjacent". Its best damaging reach is short, so it
 * has no way to pick the enemy back line and therefore targets the NEAREST foe —
 * which means an enemy front-liner screens the squishies behind it for free. A
 * unit carrying a genuine ranged move (a weapon-throw, a bolt) reads as non-melee
 * and keeps free target choice, since it CAN reach past the wall. Threshold 3
 * matches archetypeOf's ranged cutoff (melee 1.6 vs voice 5.5+).
 */
export const isMelee = (u: FieldUnit): boolean => reachOf(u) <= 3

export const centroid = (us: FieldUnit[]): Vec2 => {
  if (!us.length) return v(FIELD_W / 2, FIELD_H / 2)
  let x = 0, y = 0
  for (const u of us) { x += u.pos.x; y += u.pos.y }
  return v(x / us.length, y / us.length)
}

// ── Target selection ────────────────────────────────────────────────────────
// A weighted score per enemy. The weights themselves are bent by the unit's
// traits, which is what makes an assassin and an anchor behave differently while
// running identical code.
/**
 * Is this enemy currently cut off from its own support?
 *
 * ⚠️ THE OFFENSIVE HALF OF LINE OF SIGHT, and the reason it is worth having:
 * today's focus-fire signal is `focusCount` — how many allies already committed
 * to a target — which is FOLLOW-THE-HERD and self-referential. It has no anchor
 * outside itself, so it amplifies whatever arbitrary choice happened first and
 * converges weakly. That is the likeliest reason two numeric levers against
 * FOCUS FIRE (the mitigation cap, the maxHp coefficient) both measured null.
 *
 * "Cut off from its healer" is EXOGENOUS: every attacker reads it off the same
 * geometry, independently, and agrees without watching each other. It also
 * brings timing — the window opens and shuts as the enemy healer repositions —
 * and puts the pressure on the enemy support's POSITIONING rather than its
 * health bar. This is what high-level arena players mean by capitalising on
 * someone out of line of their healer.
 *
 * ⚠️ MEASURED NULL ON ARRIVAL, AND THE REASON MATTERS. Paired A/B: 2 better /
 * 4 worse of 6 that moved, p=0.69, and 34 of 40 fights BYTE-IDENTICAL. The term
 * is not too weak — it barely fires. Only 16 of 40 teams draft a heal-capable
 * monster at all, and where one exists a unit is out of its line just 3.1% of
 * the time, so the condition is true in roughly 1% of unit-ticks.
 *
 * ⚠️ IT IS DOWNSTREAM OF THE DEFENSIVE BEHAVIOUR, which the plan had as an
 * independent item. Supports only BECOME cut off once they start running behind
 * cover to escape — so the offensive read has nothing to see until Stage 2b
 * gives it something. Kept because the rule is right and costs nothing; RE-TEST
 * IT after flee-to-cover lands, and if it is still null then, delete it rather
 * than leave a term that fires 1% of the time pretending to be a focus-fire fix.
 *
 * ⚠️ Returns 0 when the enemy team has NO healer at all. Otherwise every target
 * scores the bonus, the term is constant across candidates, and a constant added
 * to every score discriminates nothing while looking like it does something.
 */
function unsupported(e: FieldUnit, itsTeam: FieldUnit[], los: LosFn): number {
  let hasHealer = false
  for (const a of itsTeam) {
    if (a.dead || a.id === e.id) continue
    // ⚠️ Mirrors engine.ts:361's own definition of a heal — power > 0 on a
    // buff/control aimed at an ally — so the two cannot drift apart. `self` is
    // excluded on purpose: a self-heal supports nobody.
    if (!a.m.loadout.some((mv) => mv.power > 0
      && (mv.type === 'buff' || mv.type === 'control')
      && (mv.target === 'ally' || mv.target === 'team'))) continue
    hasHealer = true
    if (los(a.pos, e.pos)) return 0 // a healer can see it: supported
  }
  return hasHealer ? 1 : 0
}

/**
 * Does this enemy satisfy the standing order?
 *
 * ⚠️ ONLY THE CATEGORICAL ORDERS ANSWER THIS. `casters`, `tanks` and `focus` each name a
 * SET — you either are a support or you are not — so "filter to the set, then take the
 * nearest" is exactly what the order means. `weakest` is a RANKING, not a set, and it is
 * handled separately in `ordered()`: turning it into a set needs an invented threshold,
 * and the first version of this used 50%, which made a whole team ignore everyone on the
 * field the moment one enemy dipped under half. That is not "finish the wounded", it is a
 * cliff — and it flipped a golden's winner.
 */
function obeys(p: TargetPriority, e: FieldUnit): boolean {
  if (p === 'casters') return roleOfClass(e.m.className) === 'support'
  if (p === 'tanks') return e.maxHp >= 260
  if (p === 'manmark') return !!e.m.marked
  return true
}

/**
 * Narrow the enemy list to the ones the player's order actually names.
 *
 * ⚠️ THE ORDER IS A FILTER NOW, NOT A TERM IN A SCORE — and that is the whole change.
 * As a term it was worth 0.30–0.50 against seven autonomous heuristics summing to 5.55,
 * so a player who set "hunt their casters" moved damage onto supports from 39.1% to
 * 50.1% when the ceiling is ~100%. It did SOMETHING, which is why this was never caught;
 * it just never did what it said. An order the player sets, pays scouting to read on
 * rivals, and sees in the UI should decide WHO, and let the autonomous reads decide which
 * of those.
 *
 * ⚠️ BOUNDED BY `ORDER_REACH`, OR IT IS THE CROSS-MAP HUNT AGAIN. Only matches within
 * that far of the NEAREST enemy are eligible; further ones are ignored and the unit
 * fights what is in front of it. Obedience must not cost a monster its life.
 *
 * ⚠️ AND A DIVE OVERRULES IT. See ORDER_DIVE_OVERRIDE — filtering to the order's matches
 * would otherwise drop a diving assassin off the list and hand every predator immunity.
 *
 * ⚠️ NEVER RETURNS EMPTY. No match in reach means no order, not no target: a unit that
 * cannot obey still has to fight.
 */
function ordered(self: FieldUnit, live: FieldUnit[], allies: FieldUnit[]): FieldUnit[] {
  const p = self.m.tactics?.targetPriority
  if (!p || live.length < 2) return live
  let near = Infinity
  for (const e of live) near = Math.min(near, dist(self.pos, e.pos))
  // ⚠️ EVERY REMAINING ORDER NAMES A SET, WHICH IS WHY THIS IS NOW ONE CODE PATH.
  // `weakest` was the exception — a RANKING, not a set — and carrying it forced a special
  // case that broke three different tests before it was retired: a 50% cliff flipped the
  // `trio` golden's winner, a reach gate stopped PREDATORS crossing the field for value,
  // and scaling that gate by predation broke the rule that crossing for VALUE is a trait
  // while crossing for the PLAYER'S ORDER is not. Nothing here needs to know which order
  // it holds any more; `obeys` answers that.
  const keep = live.filter((e) =>
    (obeys(p, e) && dist(self.pos, e.pos) <= near + ORDER_REACH)
    || diveThreat(self, e, allies) >= ORDER_DIVE_OVERRIDE)
  return keep.length ? keep : live
}

export function pickTarget(
  self: FieldUnit, enemies: FieldUnit[], allies: FieldUnit[], now = 0,
  los: LosFn = () => true,
): FieldUnit | null {
  const all = enemies.filter((e) => !e.dead)
  if (!all.length) return null
  // ⚠️ APPLIED BEFORE THE SPLIT, SO IT REACHES BOTH BRANCHES. decide.ts's own note
  // records that the melee branch returning early is exactly how `targetPriority` came
  // to do nothing on most of the game's classes. Filtering once, above the split, is the
  // only version that cannot repeat it.
  const live = ordered(self, all, allies)

  // MELEE targets the NEAREST enemy — it cannot reach past the front line, so it
  // engages whatever is in front of it and the enemy's wall shields its back row.
  // FADE still nudges attackers off a fading unit (treated as further away) so a
  // Fade reads the same for both target modes. No value chase here: that cross-map
  // hunt is exactly what made melee race around the map.
  //
  // ⚠️ BUT THE TARGET ORDER USED TO DIE HERE TOO, and that was a bug, not the
  // design. This branch returned before the scoring loop where `priorityBias`
  // lives, so `targetPriority` did NOTHING on a melee monster — the player set
  // "hunt their casters" on a Warrior and got nearest-target regardless. Every
  // melee class in the game, which is most of them.
  //
  // ⚠️ AND THE FIX IS NOT TO SCORE MELEE LIKE RANGED. Value-chasing across open
  // ground is the failure this branch exists to prevent, and re-opening it would
  // undo it wholesale. The order arrives already applied — `ordered()` above has
  // narrowed the list to what the player asked for, within `ORDER_REACH` — so this
  // branch stays pure nearest-target and the leash is enforced by the FILTER rather
  // than by a discount. `MELEE_PRIORITY_SLACK` survives for the COMBO bias, which is
  // still a preference rather than an order and must not become one.
  if (isMelee(self)) {
    let best: FieldUnit | null = null
    let bestD = Infinity
    for (const e of live) {
      const d = dist(self.pos, e.pos) + (e.fadedUntil > now ? 6 : 0)
        - comboBias(self, e) * MELEE_PRIORITY_SLACK
      if (d < bestD) { bestD = d; best = e }
    }
    return best
  }

  const { cohesion, predation } = self.traits

  // How many allies are already committed to each enemy — the focus-fire signal.
  const focusCount = new Map<string, number>()
  for (const a of allies) {
    if (a.dead || a.id === self.id || !a.targetId) continue
    focusCount.set(a.targetId, (focusCount.get(a.targetId) ?? 0) + 1)
  }
  const allyN = Math.max(1, allies.length - 1)

  let best: FieldUnit | null = null
  let bestScore = -Infinity
  for (const e of live) {
    const d = dist(self.pos, e.pos)
    const proximity = 1 - clamp01(d / fieldDiag())
    const wounded = 1 - clamp01(e.hp / e.maxHp)
    const value = valueOf(e)
    const focus = clamp01((focusCount.get(e.id) ?? 0) / allyN)
    // ⚠️ MELEE NEVER REACHES THIS. It returned above on nearest-target, and
    // decide.ts's own note says why: "that cross-map hunt is exactly what made
    // melee race around the map". The isolation read is for ranged and casters.
    const isolated = unsupported(e, live, los)

    // A predator discounts distance (it will cross the field for the right
    // kill) and weights value heavily. A team player weights whatever its
    // allies are already hitting. An AWARE monster answers whoever is diving
    // its friends — without this term nothing ever punishes a dive, and the
    // assassin archetype has no counter at all.
    const score =
      1.00 * proximity * (1 - 0.65 * predation) +
      0.85 * wounded * (0.5 + predation) +
      0.90 * value * predation +
      0.80 * focus * cohesion +
      0.90 * isolated +
      1.10 * diveThreat(self, e, allies) +
      // ⚠️ NO CATEGORICAL ORDER TERM HERE ANY MORE — that is a FILTER now, applied
      // above. Leaving it in the score too would count it twice and let a marginal match
      // outweigh a badly wounded one among enemies that ALL obey the order. Only
      // `weakest` remains as a weight, because it is a ranking rather than a set.
      // ⚠️ NO ORDER TERM HERE — the order is a FILTER now, applied above. And note
      // `wounded` a few lines up: finishing the hurt one SURVIVES the retirement of the
      // `weakest` order, because it was always an autonomous read as well.
      comboBias(self, e)

    // FADE is the anti-taunt: while it holds, this monster is simply not worth
    // looking at, so attackers drift onto someone else. A heavy multiplier
    // rather than true untargetability, so a lone faded survivor is still
    // eventually found and the fight cannot stall.
    const faded = e.fadedUntil > now ? 0.15 : 1
    const final = score * faded
    if (final > bestScore) { bestScore = final; best = e }
  }
  return best
}

/**
 * How badly this enemy needs answering: is it bearing down on a teammate who
 * cannot survive it? Scaled by the observer's AWARENESS, so an oblivious
 * bruiser keeps hitting whatever is in front of it while an alert one turns
 * to intercept. This is the counterplay to Predation.
 */
export function diveThreat(self: FieldUnit, e: FieldUnit, allies: FieldUnit[]): number {
  const p = personalityOf(self.m)
  const radius = threatRadius(p)
  let worst = 0
  for (const a of allies) {
    if (a.dead || a.id === self.id) continue
    const d = dist(e.pos, a.pos)
    if (d > radius) continue
    // A squishy, valuable, already-hurt ally is the one worth turning for.
    const stakes = valueOf(a) * (1.3 - clamp01(a.hp / a.maxHp) * 0.6)
    worst = Math.max(worst, (1 - d / radius) * stakes)
  }
  return worst * (p.awareness / 100)
}

/**
 * COMBO ROLE — the DETONATE half: prefer an enemy already carrying a status this
 * unit can cash.
 *
 * ⚠️ THE FREE HALF, ON PURPOSE. This costs no tempo — the unit still attacks every
 * tick, it just picks a better body. The expensive half (holding the payoff for a
 * window that may never open) is deliberately NOT built yet; `manaPolicy` already
 * measured what withholding costs in this engine.
 *
 * ⚠️ AND IT MUST BE ADDED AT BOTH `pickTarget` SITES. The melee branch returns
 * before the scoring loop, which is exactly how `targetPriority` came to do nothing
 * on most of the roster for months. A detonator that is melee — Duelist, holding
 * Twist the Knife — is precisely the case this exists for.
 */
function comboBias(self: FieldUnit, e: FieldUnit): number {
  if (self.m.tactics?.comboRole !== 'detonate' || !self.comboCashes.length) return 0
  return e.statuses.some((st) => self.comboCashes.includes(st.kind)) ? COMBO_TARGET_BIAS : 0
}

/** How early a ranged monster starts giving ground — awareness buys distance. */
const kiteAt = (u: FieldUnit): number => 0.45 + (personalityOf(u.m).awareness / 100) * 0.3

/** True when a ranged unit is close enough to a threat that it WOULD backpedal —
 *  the engine spends its kite budget while this holds and refills it otherwise. */
export const wantsToKite = (self: FieldUnit, target: FieldUnit): boolean =>
  reachOf(self) > 3 && dist(self.pos, target.pos) < reachOf(self) * kiteAt(self)


// ── SPATIAL ORDERS (v0.93) ──────────────────────────────────────────────────
// Coaching that only means anything on real ground. Each is applied in
// proportion to the monster's TEMPERAMENT, exactly like every other order: a
// wilful monster told to hold the line still wanders forward.



/**
 * Personal-space radius. Spread fans out against AoE; tight clumps to focus.
 *
 * ⚠️ `keep` DELIBERATELY TAKES THE BASE RADIUS. Under `keep` the density is
 * already drawn on the deploy screen — the player chose which hexes to stand on —
 * so a personal-space multiplier on top would be a second, invisible order
 * fighting the slot the unit is being pulled toward. Density is a choice only
 * when there is no slot to hold.
 */
export function spacingRadius(u: FieldUnit): number {
  const order = u.m.tactics?.formation
  const base = u.radius * 2
  if (!order || order === 'keep') return base
  const want = order === 'spread' ? base * 2.6 : base * 0.75
  return coachedValue(base, want, personalityOf(u.m).temperament)
}

/**
 * Will this monster chase past the enemy front line? A 'hold' order caps how
 * far into enemy ground it is willing to go — the answer to a team that keeps
 * over-extending into a counter-attack.
 */
export function commitLimit(u: FieldUnit): number {
  const order = u.m.tactics?.commit
  // ⚠️ The "no limit" sentinel MUST be side-aware. Side A clamps with min() and
  // side B with max(), so a single shared sentinel of FIELD_W pinned every B
  // unit to the far edge and they could never advance at all.
  if (order !== 'hold') return u.side === 'A' ? FIELD_W : 0
  // Refuse to go much past the halfway line.
  const cap = u.side === 'A' ? FIELD_W * 0.58 : FIELD_W * 0.42
  return coachedValue(u.side === 'A' ? FIELD_W : 0, cap, personalityOf(u.m).temperament)
}

/**
 * RETREAT is a TEMPORARY back-off, not a rout to the home edge. A unit below its
 * survival threshold gives ground only while a threat is still too close — a
 * ranged unit until it can shoot from safety, a melee for a few steps — then it
 * resumes. Returns the threat it is backing away from, or null if it should hold
 * and fight. The engine also reads this to briefly FADE a retreating unit so its
 * chaser peels onto the nearest ally (the ally "takes the aggro").
 */
export function retreatThreatOf(
  self: FieldUnit, liveEnemies: FieldUnit[],
  /**
   * Living team-mates, EXCLUDING self — see the last-monster rule below.
   * ⚠️ REQUIRED, deliberately. Defaulted to [] a caller that forgot it would read
   * as "no allies", which silently switches retreat OFF for that unit instead of
   * failing. Make the compiler ask the question.
   */
  liveAllies: FieldUnit[],
): FieldUnit | null {
  // ⚠️ THE LAST MONSTER STANDING DOES NOT RETREAT. Read this function's own
  // rationale two paragraphs up: retreat exists so a hurt unit can break contact
  // and its chaser "peels onto the nearest ally" — the ally takes the aggro. With
  // no ally left there is nobody to hand off to, so backing away buys nothing and
  // costs the fight: the unit is under its panic threshold, so it retreats, and it
  // is still under it next tick, so it retreats again, for as long as the clock
  // allows. A retreat loop, and the last survivor is exactly when a player is
  // watching most closely.
  //
  // ⚠️ SECOND HALF OF THE SAME BUG AS THE BROKEN-ENEMY SKIP BELOW. That one stopped
  // wounded survivors fleeing EACH OTHER; this one stops a lone survivor fleeing a
  // healthy enemy it can never escape. Both are "the fight stops because someone is
  // running", and neither is fixable by tuning a threshold.
  //
  // ⚠️ THIS IS THE AI's POSITIONAL RETREAT ONLY. An authored escape ABILITY —
  // `isEscapeMove`, anything with `spatial.move.to: 'awayFromTarget'` or a `fade` —
  // is chosen by the move system and never comes through here, so a monster that
  // brought Disengage or Shadowstep still uses it while alone. Spending a real card
  // to break contact is a decision; drifting backwards forever is not.
  if (!liveAllies.length) return null
  const hpFrac = self.hp / self.maxHp
  const preserve = self.m.tactics?.preserve ?? 'off'
  // COMPOSURE decides when it breaks; an explicit 'preserve' order raises the floor.
  const innatePanic = panicThreshold(personalityOf(self.m))
  const ordered = preserve === 'defensive' ? 0.4 : preserve === 'cautious' ? 0.25 : 0
  const retreatAt = Math.max(innatePanic, ordered)
  if (retreatAt <= 0 || hpFrac >= retreatAt || !liveEnemies.length) return null
  // ⚠️ DO NOT RETREAT FROM SOMETHING THAT IS ALSO BROKEN. Retreat exists so a hurt
  // unit can break contact with something that can still kill it. An enemy below
  // its OWN panic threshold is not that — and when every survivor is wounded, each
  // one flees the others and the fight simply stops.
  //
  // ⚠️ MEASURED, NOT THEORISED. `status.test.ts`'s 24-fight spread contained a
  // matchup that ran 256.6s against a 300s cap: three survivors at 11-18% HP, mana
  // refilling to 100%, and in the last 197 seconds FOUR hits landed — against 39
  // fallbacks, 16 abandoned chases, and 27 casts of Enrage on an already-buffed
  // self. They were not starved or out-healing; they were running away from each
  // other. It surfaced as a chaotic no-draws failure at COOLDOWN_MULT 1.03 and 1.05
  // that vanished again by 1.08, because whether all survivors dip under the
  // threshold together is exquisitely sensitive to damage rolls.
  let nearest: FieldUnit | null = null
  let nd = Infinity
  for (const e of liveEnemies) {
    if (e.hp / e.maxHp < panicThreshold(personalityOf(e.m))) continue
    const d = dist(self.pos, e.pos)
    if (d < nd) { nd = d; nearest = e }
  }
  // Safe = far enough that it is no longer under pressure: a ranged unit is safe
  // once it can shoot from range; a melee only needs a few steps of daylight.
  const safe = reachOf(self) > 3 ? reachOf(self) * 0.95 : 7
  return nearest && nd < safe ? nearest : null
}

// ── Positioning ─────────────────────────────────────────────────────────────
/**
 * Where this unit wants to be standing. Returns a world point; the engine
 * steers toward it and handles collision.
 */
export function desiredGoal(
  self: FieldUnit, target: FieldUnit | null, allies: FieldUnit[], enemies: FieldUnit[],
  /** injected by the engine so this file stays free of geometry imports */
  losFn?: (a: Vec2, b: Vec2) => boolean,
): Vec2 {
  const liveAllies = allies.filter((a) => !a.dead && a.id !== self.id)
  const liveEnemies = enemies.filter((e) => !e.dead)

  // LEASH: no unit may aim to stand more than LEASH_RADIUS from the fight's centre
  // of mass — the hard stop on wandering off across the map, applied to EVERY goal
  // this function returns (retreat and kite included).
  const battleCentre = centroid([self, ...liveAllies, ...liveEnemies])
  const leash = (g: Vec2): Vec2 => {
    const dv = sub(g, battleCentre)
    const L = len(dv)
    return L > LEASH_RADIUS ? add(battleCentre, scale(norm(dv), LEASH_RADIUS)) : g
  }

  // TEMPORARY retreat: back away from the NEAREST threat only, and only far
  // enough to be safe — no sprint to the home edge. Once the threat is beyond
  // safe range this returns null and the unit resumes fighting from there.
  const rThreat = retreatThreatOf(self, liveEnemies, liveAllies)
  if (rThreat) {
    const away = norm(sub(self.pos, rThreat.pos))
    return leash({
      x: Math.min(FIELD_W - 1, Math.max(1, self.pos.x + away.x * 5)),
      y: Math.min(FIELD_H - 1, Math.max(1, self.pos.y + away.y * 5)),
    })
  }

  if (!target) return centroid(liveAllies.length ? liveAllies : [self])

  const reach = reachOf(self)
  const d = dist(self.pos, target.pos)
  const toward = norm(sub(target.pos, self.pos))

  // Stand-off point: just inside reach, so a ranged unit does not walk into a
  // melee unit's face and a melee unit does close all the way.
  // ⚠️ MUST sit inside the BASIC attack's range (engine: CHANNEL_RANGE × 0.8) or
  // the unit parks where its own free attack cannot reach — which is exactly what
  // 0.85 did, leaving every monster with nothing to do between skill cooldowns.
  // ⚠️ `* engageMult(self)` REMOVED WITH THE TACTIC. That order let a player push
  // the stand-off out to 1.3x or in to 0.55x, which fought `reachOf` — the thing
  // that already decides where a monster stands, from the weapon in its hands and
  // its class basic. Two systems answering one question is how a Warrior ended up
  // holding at 6.4 with a melee kit.
  const standoff = Math.max(0.8, reach * 0.75)
  let goal: Vec2
  if (d > standoff) {
    goal = add(self.pos, scale(toward, d - standoff))
  } else if (reach > 3 && d < reach * kiteAt(self) && self.kiteFor > 0) {
    // KITING: a ranged unit backs off when something closes on it — but ONLY
    // while it has kite budget left (you cannot attack and kite). Once the budget
    // runs out it drops to the branch below and HOLDS, then fights / uses cover.
    goal = add(self.pos, scale(toward, -(reach * kiteAt(self) - d)))
  } else {
    goal = { ...self.pos }
  }

  // COHESION pulls the goal back toward the team. A high-cohesion unit will not
  // stray far from its allies even to reach a juicy target; a low-cohesion one
  // goes wherever it likes. This single blend is what makes a team look like a
  // team rather than five monsters running separate errands.
  //
  // FORMATION 'keep' aims that pull at this unit's SLOT instead of at the bare
  // centroid: the live centroid PLUS the offset it deployed at. The shape then
  // travels with the team — the wall stays in front and the healer behind for the
  // whole fight, instead of the deployment dissolving into a blob on tick 1.
  if (liveAllies.length) {
    const live = [self, ...liveAllies]
    const c = centroid(liveAllies)
    let anchor = c
    let pull = self.traits.cohesion * 0.35
    if (self.m.tactics?.formation === 'keep') {
      // ⚠️ BOTH CENTROIDS OVER THE SAME LIVE SET, and both including self — a
      // deploy centroid taken over the original team leaves survivors standing in
      // their dead's gaps, and one taken over a different set than the live
      // centroid offsets the whole formation by the difference.
      const now = centroid(live)
      const then = {
        x: live.reduce((n, u) => n + u.deployPos.x, 0) / live.length,
        y: live.reduce((n, u) => n + u.deployPos.y, 0) / live.length,
      }
      anchor = {
        x: now.x + (self.deployPos.x - then.x),
        y: now.y + (self.deployPos.y - then.y),
      }
      // An order, so it lands in proportion to TEMPERAMENT like every other
      // spatial order — a wilful monster holds a looser slot than a drilled one.
      pull = coachedValue(pull, FORMATION_KEEP_PULL, personalityOf(self.m).temperament)
    }
    goal = { x: goal.x * (1 - pull) + anchor.x * pull, y: goal.y * (1 - pull) + anchor.y * pull }
  }
  // RUN LoS / USE COVER. A ranged unit under pressure USES THE TERRAIN: when a
  // melee threat is closing, it prefers a stance that breaks that threat's line
  // to it while it keeps a shot on its own target — tuck behind a rock and peek,
  // instead of sprinting across the open (which is what read as "racing around
  // the map"). Default behaviour for ranged when pressured; the `useCover` order
  // forces it even before a threat is in its face. Melee never does this — its
  // whole job is to be in contact.
  if (reach > 3 && losFn && liveEnemies.length) {
    // the nearest MELEE bearing down on us — that is who we break line from
    let threat: FieldUnit | null = null
    let td = Infinity
    for (const e of liveEnemies) {
      if (!isMelee(e)) continue
      const d = dist(self.pos, e.pos)
      if (d < td) { td = d; threat = e }
    }
    const pressured = !!threat && td < reach * 1.3        // inside our stand-off
    const forced = self.m.tactics?.useCover
    const obey = personalityOf(self.m).temperament / 100
    if (threat && obey > 0.2 && (pressured || forced) && losFn(goal, threat.pos)) {
      let bestCover: Vec2 | null = null
      let bestScore = -Infinity
      for (let i = 0; i < 16; i++) {
        const a = (i / 16) * Math.PI * 2
        const rad = 2.6 + (i % 2) * 1.8
        const c = { x: goal.x + Math.cos(a) * rad, y: goal.y + Math.sin(a) * rad }
        if (c.x < 1 || c.x > FIELD_W - 1 || c.y < 1 || c.y > FIELD_H - 1) continue
        if (losFn(c, threat.pos)) continue            // still exposed to the threat
        if (dist(c, target.pos) > reach) continue     // out of reach of our target
        // ⚠️ AND WE MUST BE ABLE TO SEE IT. This check was missing: cover was
        // chosen on DISTANCE to the target alone, so a unit would deliberately
        // relocate behind a rock that also blocked its own shot and then stand
        // there. Measured cost: casters held line of sight only 47% of ticks
        // (rogues 20%), and a blocked unit cannot use its free attack either.
        if (!losFn(c, target.pos)) continue           // no shot from there — not cover, just hiding
        // prefer cover that stays close to where we already wanted to be (less running)
        const score = -dist(c, goal)
        if (score > bestScore) { bestScore = score; bestCover = c }
      }
      if (bestCover) goal = bestCover
    }
  }

  // ── ARCHETYPE POSITIONING ───────────────────────────────────────────────
  // On top of the reach-driven standoff/kite above, each role wants a different
  // PLACE on the field. Artillery already kites (reach > 3); this adds the other
  // three. Blended, not absolute, so the personality axes and tactics still bend
  // it — a coached 'brawl' anchor still gets in deeper than a timid one.
  const enemyDir = self.side === 'A' ? 1 : -1
  switch (archetypeOf(self)) {
    case 'anchor': {
      // Hold the FRONT of the line: nudge toward the nearest enemy so the tank
      // is the body between the team and the threat.
      goal.x += enemyDir * 1.0
      break
    }
    case 'support': {
      // Stay BEHIND the line — pull back toward home and toward the ally in the
      // most trouble, so heals land and the support isn't caught out front.
      goal.x -= enemyDir * 1.3
      if (liveAllies.length) {
        const worst = [...liveAllies].sort((a, b) => a.hp / a.maxHp - b.hp / b.maxHp)[0]
        goal = { x: goal.x * 0.7 + worst.pos.x * 0.3, y: goal.y * 0.7 + worst.pos.y * 0.3 }
      }
      break
    }
    case 'assassin': {
      // After a strike the diver breaks off — dart back toward safety for a beat
      // (`disengageFor`, set by the engine on the assassin's hit) before diving
      // again. This is the in-and-out that makes an assassin read differently
      // from a bruiser that just parks on the target.
      if (self.disengageFor > 0 && liveEnemies.length) {
        const away = norm(sub(self.pos, centroid(liveEnemies)))
        goal = { x: self.pos.x + away.x * 7, y: self.pos.y + away.y * 7 }
      }
      break
    }
  }

  // ── TAKE THE ANGLE ────────────────────────────────────────────────────────
  // ⚠️ NOTHING IN THIS ENGINE EVER MOVED TO **GAIN** A SHOT. The cover block
  // above only breaks line FROM a melee threat, and it only runs when one is
  // actually bearing down. So a ranged unit whose shot was blocked by a rock,
  // with nobody near it, simply stood there: it could cast nothing (non-melee
  // casts need line of sight) and could not even use its free attack, which is
  // gated on the same check. Measured: casters held a line only 47% of ticks,
  // rogues 20%, and both ran at ~12% of their cooldown capacity while sitting on
  // ~90% mana. They were not out of resources — they had no angle.
  //
  // So: if we cannot see the target from where we intend to stand, SIDESTEP to
  // the nearest point that can. Deliberately the LAST word on the goal, after
  // archetype positioning, because it is a hard precondition for acting at all —
  // but it never overrides the leash or the commit line below it.
  // ⚠️ ONLY WHEN ALREADY IN REACH. Sidestepping from out of range is the wrong
  // answer to the wrong problem: a unit that is simply too far away should WALK
  // IN, which usually clears the rock on its own. Letting it strafe from
  // distance cost casters their approach — in-range time fell 72% -> 53% and
  // their damage with it, while the classes that were genuinely stuck behind
  // cover (Ranger, Rogue) gained. This is a "I can reach it but not see it" fix.
  if (reach > 3 && losFn && d <= reach && !losFn(goal, target.pos)) {
    let best: Vec2 | null = null
    let bestD = Infinity
    for (let ring = 0; ring < 3; ring++) {
      const rad = 2.2 + ring * 2.0
      for (let i = 0; i < 12; i++) {
        const a = (i / 12) * Math.PI * 2
        const c = { x: goal.x + Math.cos(a) * rad, y: goal.y + Math.sin(a) * rad }
        if (c.x < 1 || c.x > FIELD_W - 1 || c.y < 1 || c.y > FIELD_H - 1) continue
        if (dist(c, target.pos) > reach) continue   // no good if we still can't reach
        if (!losFn(c, target.pos)) continue         // still blocked
        const dd = dist(c, self.pos)                // least walking wins
        if (dd < bestD) { bestD = dd; best = c }
      }
      if (best) break // nearest ring that works — don't cross the map for a better angle
    }
    if (best) goal = best
  }

  // COMMIT: a 'hold' order refuses to over-extend past the halfway line.
  const limit = commitLimit(self)
  if (self.side === 'A') goal.x = Math.min(goal.x, limit)
  else goal.x = Math.max(goal.x, limit)

  const g = leash(goal) // keep it near the fight
  return {
    x: Math.min(FIELD_W - 0.5, Math.max(0.5, g.x)),
    y: Math.min(FIELD_H - 0.5, Math.max(0.5, g.y)),
  }
}

/**
 * How this monster EARNS mana (see the MANA ECONOMY note in types.ts).
 *
 * THREE roles only — tank, damage, support. ⚠️ There is deliberately no separate
 * "caster": a caster is a DAMAGE dealer if it throws spells and a SUPPORT if it
 * mends, so it fuels the same way anyone in that job does. What makes casting
 * feel different is the WIS mana POOL and WIS regen, which an INT/WIS monster has
 * far more of — that is the caster's edge, not a separate generation rule.
 *
 * Keyed off class first, then the dominant stat, so a high-CON Warrior fuels like
 * a tank without being the Tank *class*.
 */
export type ManaRole = 'tank' | 'damage' | 'support'
export function manaRoleOf(m: Monster): ManaRole {
  if (m.className === 'Tank') return 'tank'
  if (roleOfClass(m.className) === 'support') return 'support'
  const s = m.stats
  const top = (['STR', 'DEX', 'CON', 'INT', 'WIS', 'CHA'] as Stat[])
    .reduce((a, b) => ((s[b] ?? 0) > (s[a] ?? 0) ? b : a))
  return top === 'CON' ? 'tank' : 'damage'
}

/** Field positioning archetypes, derived from stats + reach + personality. */
export type Archetype = 'anchor' | 'artillery' | 'assassin' | 'support' | 'skirmisher'
export function archetypeOf(u: FieldUnit): Archetype {
  // ⚠️ TANK IS A FRONT-LINE ANCHOR, NOT A SUPPORT. `CLASS_ROLES` files Tank under
  // the 'support' ROLE (it is a team-composition label — a Tank is not a damage
  // pick), but spatially a Tank belongs at the FRONT soaking hits. The support
  // early-return caught it first, so every Tank-class monster positioned itself
  // BEHIND the line and never counted as an anchor — the exact opposite of the
  // job. Checked before the role test, so composition and geometry can disagree.
  if (u.m.className === 'Tank') return 'anchor'
  if (roleOfClass(u.m.className) === 'support') return 'support'
  // Artillery = a genuine RANGED or MAGIC single-target reach. ⚠️ Voice reach
  // does NOT count: a voice AoE radiates from the CASTER, so a screamer wants to
  // be AMONG the enemies, not kiting at range — treating it as artillery makes
  // it back off and whiff its own AoE.
  const longRanged = u.m.loadout.some(
    (mv) => mv.type === 'damage'
      && (mv.channel === 'ranged' || mv.channel === 'magic')
      && (mv.range ?? CHANNEL_RANGE[mv.channel]) > 3,
  )
  if (longRanged) return 'artillery'
  const s = u.m.stats
  if (s.CON >= s.STR && s.CON >= s.DEX && s.CON >= s.INT) return 'anchor' // tanky → front
  if (s.DEX >= s.STR && personalityOf(u.m).aggression > 52) return 'assassin' // fast + eager
  return 'skirmisher'
}
