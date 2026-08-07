// ─────────────────────────────────────────────────────────────────────────────
// FIELD BATTLE (v0.93) — a continuous-2D autobattler engine, in the Teamfight
// Manager mould. Monsters occupy real positions, move under their own steering,
// choose their own targets, and fight until one side is gone.
//
// ⚠️ This is a SECOND engine. `battle.ts` (turn-based) is untouched and remains
// the shipping engine — the whole balance arc up to v0.92 is calibrated to it,
// and its 12 golden battles still pin it exactly. Nothing in this folder is
// imported by battle.ts, so the goldens cannot move. The two run side by side
// until this one is tuned well enough to take over.
// ─────────────────────────────────────────────────────────────────────────────
import { Channel, Monster, Stat, StatusKind } from '../core'

export interface Vec2 { x: number; y: number }

// The arena in world units. Roughly 40x22 gives a wide pitch with room for two
// deployment zones, a no-man's land, and cover in the middle.
// ⚠️ `let`, NOT `const` — arenas differ in size (see `maps.ts`), and the whole
// engine reads these as module-level bindings rather than threading dimensions
// through every call site. ES live bindings mean `setFieldSize` is seen by every
// importer, which is what makes a per-map size possible without a refactor that
// would touch ~15 clamp sites across engine.ts, decide.ts and hex.ts.
//
// The trade, stated plainly: this is MUTABLE GLOBAL STATE. It is safe only
// because the engine is synchronous and single-threaded — one battle runs to
// completion before the next starts. Do NOT interleave battles at different
// sizes, and always set the size BEFORE `simulateFieldBattle`, never during.
// The game itself never calls the setter; it is for maps and harnesses.
export let FIELD_W = 40
export let FIELD_H = 22

/** Select the arena dimensions. Returns the previous pair so a caller can restore. */
export function setFieldSize(w: number, h: number): [number, number] {
  const prev: [number, number] = [FIELD_W, FIELD_H]
  FIELD_W = w
  FIELD_H = h
  return prev
}
// A side deploys within this many units of its own edge.
export const DEPLOY_DEPTH = 11

// Simulation cadence. Fixed dt is what keeps the whole thing deterministic —
// never derive movement from wall-clock time.
export const TICK_HZ = 10
export const DT = 1 / TICK_HZ
/**
 * FIVE MINUTES — a safety net, not a design lever.
 *
 * ⚠️ RAISING THIS DOES NOT LENGTHEN FIGHTS. Measured at the 120s cap: median
 * 15.3s, p90 36.2s, max 84.3s, and 0 of 40 sweep fights reached even sudden
 * death. Going 120 -> 300 produced a byte-identical sweep. What makes a fight
 * long is DURABILITY (`maxHp`, mitigation), and the clock only ever bounds the
 * tail. Anyone reaching for this constant to change how fights feel is holding
 * the wrong one.
 *
 * The headroom is deliberate: the target is a SPREAD, not a length. A glass
 * cannon pair should still resolve in a minute while two walls grind for four,
 * and that variation is what makes a build choice mean something. A playback
 * speed control in the arena is what makes the long tail watchable.
 */
export const MAX_SECONDS = 300
export const MAX_TICKS = MAX_SECONDS * TICK_HZ
// Re-picking a target every tick makes units jitter between equal-scoring foes.
// They commit for this long unless the target dies or they are forced off it.
export const RETARGET_EVERY = 0.6 // seconds
// KITE BUDGET. A ranged unit may backpedal for at most this long before it must
// hold and fight — you cannot attack and kite. Drains while a threat is in kite
// range, refills (at KITE_REFILL× the rate) only once the unit is safe.
export const KITE_MAX = 1.2 // seconds
export const KITE_REFILL = 0.5
// LEASH. No unit may aim to stand more than this far from the fight's centre of
// mass, so nothing can wander off across the map however it is steered.
export const LEASH_RADIUS = 12

// ── GIVING UP A CHASE ───────────────────────────────────────────────────────
// ⚠️ THE COUNTERWEIGHT TO PATHFINDING. Once units route around cover properly, a
// pursuer never loses the trail — which is the opposite failure to the one that
// was just fixed, and it makes any escape budget irrelevant: a support can spend
// every cooldown it owns and still be caught. A chase has to be able to fail.
//
// ⚠️ MEASURED AS TIME WITHOUT PROGRESS, NOT TIME SPENT CHASING. A bruiser closing
// steadily from across a 64-unit arena is doing exactly what it should; abandoning
// it mid-approach because a stopwatch expired would undo the approach work
// entirely. What earns a give-up is failing to get any NEARER.
export const PURSUIT_PATIENCE = 3.0 // seconds without closing before giving up
// ⚠️ WITHOUT THIS, GIVING UP THRASHES. Drop B, take C, drop C, take B again, and
// nobody ever dies — a new way to stall a fight dressed up as a fix. A unit that
// has just been abandoned is off the menu for a while.
export const PURSUIT_IGNORE = 5.0 // seconds an abandoned target is skipped
export const PURSUIT_PROGRESS = 0.35 // world units of closing that counts as progress

// ── FALL BACK ───────────────────────────────────────────────────────────────
// The universal escape: every monster has one, on a long cooldown, so breaking
// contact is an EVENT a player can see and plan around rather than a continuous
// drift nobody can observe. A cooldown was chosen over a stamina budget for
// exactly that reason — see docs/PATHFINDING_DESIGN.md §5.
//
// ⚠️ NOT A SMALLER VERSION OF MICRO-KITING. `KITE_MAX` (1.2s) is a ranged unit
// shuffling back to hold range, continuously, every second. This is a discrete
// decision to break contact, two or three times a fight. Putting a cooldown on
// the former would walk archers into melee; they stay separate systems.
export const FALL_BACK_CD = 15 // seconds between uses
export const FALL_BACK_DUR = 2 // seconds of committed retreat
// ⚠️ ITS TEETH COME FROM SUSPENDING BACKPEDAL_MULT, not from a speed bonus.
// Giving ground normally costs 40% of your speed — that penalty is what lets a
// committed attacker ever close. Lifting it briefly is what separates a real
// retreat from a shuffle, and it needs no new speed constant.
export const FALL_BACK_HP = 0.4 // trigger: below this fraction of max HP
export const FALL_BACK_NEAR = 3.5 // trigger: a melee threat this close
// ⚠️ THE HAZARD IS NOT "TWO ESCAPES IN A FIGHT", IT IS "TWO IN TWO SECONDS".
// Two across a 45s fight is the premium build working. Two inside one window
// makes an assassin's commitment unanswerable — it lands, the support
// Disengages, it re-closes, the support instantly Falls Back, and it has spent
// eight seconds achieving nothing. No value of FALL_BACK_CD catches that,
// because the whole burst happens inside a single window, which is why this is
// a second and much SHORTER constant rather than a bigger first one.
export const ESCAPE_LOCKOUT = 5 // seconds either escape locks the other

// ⚠️ A DASH CROSSES THE GROUND. It did not: `u.pos = dest` set the destination
// in a single tick, so a 7-unit Backstep was an instantaneous 7-unit jump —
// visually a teleport with no explanation, and mechanically un-interruptible.
// The comment on `MoveSpatial.move` has always said a dash "crosses the ground
// and IS stopped by cover"; only the second half was true.
//
// A BLINK still snaps, because that is what a teleport is, and it emits its own
// event so a renderer can draw the discontinuity deliberately.
// ⚠️ 4 -> 2.2 -> 1.35, and the last step came with a change of mind about what a
// dash IS. Chasing "fast enough to feel like an ability" kept producing
// something that read as a spring backwards — because a monster crossing seven
// units in under a second is not retreating, it is being thrown.
//
// THE ESCAPE'S VALUE IS NOT RAW SPEED. It is covering ground while EXEMPT from
// the 0.6x backpedal penalty that taxes every ordinary retreat. At 1.35x a
// dashing unit still moves 2.2x a normal fleeing one (1.35 / 0.6) — the mechanic
// is untouched — while looking like a monster running away rather than recoiling
// off a spring.
export const DASH_SPEED_MULT = 1.35 // times normal speed while dashing
// Scales with the slowdown: at 1.35x a 7-unit dash needs ~1.5s, so the release
// has to sit well beyond that or the escape silently does half its job.
export const DASH_MAX_TIME = 3.0 // seconds before a dash gives up and releases
// ⚠️ FALL BACK'S SPEED CHANGE IS RAMPED, NOT SWITCHED. Lifting the 0.6x
// backpedal penalty in a single tick is a 67% instantaneous speed jump — the
// same class of discontinuity as the snapping dash, just smaller. Easing into
// it over half a second keeps the mechanic (you do outrun your pursuer) and
// removes the jolt.
export const FALL_BACK_RAMP = 0.5 // seconds to reach full retreat speed

// ⚠️ NOTHING TURNED. `stepToward` recomputed its heading from scratch every tick
// and applied it raw, so a unit could reverse 180 degrees between two frames —
// it never turned, it just changed which way it translated. That is the real
// source of "jolty": no escape constant could fix it, because the discontinuity
// was in every movement in the game, not in the escapes.
//
// A creature turns at a rate. 7 rad/s puts a full about-face at ~0.45s, which
// reads as an animal reacting rather than a sprite being repointed.
/**
 * KNOCKBACK — how fast a shoved unit travels, in world units per second.
 *
 * ⚠️ A SHOVE USED TO BE AN ASSIGNMENT. `applyOnTarget` wrote `target.pos = dest`,
 * so Body Slam's `push: 3` landed all three units inside one 0.1s tick — 30
 * units/second, about 7x a walk, and the single most teleport-looking thing in
 * the game. Measured on a 3v3: 1532 ticks moved <=0.5 units and nine moved
 * 1.8-3.1, with NOTHING in between, because shoves bypassed the movement step
 * entirely. Every one of those nine matched a `shove` event exactly.
 *
 * ⚠️ AND IT IS WHY TUNING THE DASH DID NOTHING. Three commits moved
 * DASH_SPEED_MULT chasing "retreats look like teleports" — but the jumps were
 * never retreats, they were knockbacks on a different code path. Measure which
 * mechanic is firing before tuning the one you assume is.
 *
 * 12 covers a 3-unit shove in 0.25s: two or three ticks, which reads as an
 * impact rather than a blink, and still clearly faster than anyone can run.
 */

/**
 * MITIGATION DIVISOR — damage reduction is `min(MIT_CAP, defStat / MIT_DIVISOR)`,
 * where defStat is CON against physical and WIS against magic/voice/support.
 *
 * ⚠️ THE LEVER WITH THE MOST REACH IN THE GAME: it touches every hit, unlike
 * healing which reaches 4% of casts. 1400 -> 1250 lifts a CON-300 monster from
 * 21.4% to 24.0% reduction. Deliberately small — one value, nudged.
 *
 * The 0.55 cap is a SECOND value and is left alone; move one at a time.
 */
export const MIT_DIVISOR = 1150

/**
 * DAMAGE REDUCTION, WITH DIMINISHING RETURNS INSTEAD OF A WALL.
 *
 * ⚠️ A HARD CAP MADE MITIGATION STOP BEING A DEFENCE. `min(cap, stat/divisor)`
 * saturated at 688 when the cap was 0.55 and at 812 at 0.65 — past that, every
 * point of CON or WIS bought exactly nothing. Measured share already at the cap:
 * 0% up to Silver, 22% at Masters, 37% at Tamer Elite, 65% at Tamers Apex. The
 * whole top of the ladder was investing in a stat that had stopped paying, which
 * is why elite fights ran SHORTER than mid-tier ones despite triple the health.
 *
 * Now: linear to the KNEE, then a reduced rate that never quite reaches CEIL. So
 * a wall always gains from more CON, but never becomes unkillable.
 *
 *   stat  688 -> 0.550   (the old cap — unchanged below here, by construction)
 *   stat 1000 -> 0.638
 *   stat 1100 -> 0.666
 *   stat 1400 -> 0.750
 *
 * ⚠️ CEIL 0.80 is a real ceiling and is meant to be approached, not hit. Past it
 * a wall stops taking meaningful damage from anything but pierce, and
 * "unkillable tank" is a worse failure than "short fight".
 */
export const MIT_KNEE = 0.55  // where returns start diminishing
// ⚠️ 0.5, RAISED FROM 0.35 TO FIX A TIER INVERSION. Elite fights were running
// SHORTER than mid-tier ones (17.7s vs 25.4s) — the leagues with the biggest
// health pools resolved fastest, because mitigation's returns above the knee
// were too thin to keep up with compounding damage. 0.5 took elite to 20.8s with
// kills unchanged at 200 and mid BYTE-IDENTICAL, since nothing below Gold
// reaches the knee at all. No golden moved.
//
// ⚠️ MIT_CEIL is now reached exactly at stat 1400 — the Apex cap, the ladder's
// maximum. That is the asymptote calibrated to the game rather than a plateau
// inside it, but it means any future cap raise re-introduces a flatline. Pierce
// still cuts it hard: 0.4 pierce against a 1400 wall gives 0.611, not 0.800.
export const MIT_SOFT = 0.5  // rate retained above the knee
export const MIT_CEIL = 0.80  // asymptote, never reached in practice

/**
 * THE ONE MITIGATION FORMULA. ⚠️ There were THREE copies of it in engine.ts —
 * `strike`, the damage estimator, and pierce valuation — and by the end of one
 * session all three had drifted apart: the estimator kept `1400` after the
 * divisor moved to 1250, and pierce kept BOTH `0.55` and `1400`. Pierce was being
 * priced against a curve the game no longer used. One function, called
 * everywhere, is the only thing that ends that.
 *
 * `pierce` is a FRACTION of the defence ignored outright (never points).
 */
/**
 * THE OPENING GUARD — a global damage reduction every monster starts with, which
 * holds and then fades. Nothing to do with stats: it is a property of the CLOCK.
 *
 * ⚠️ AIMED AT FIRST BLOOD, NOT AT DURATION DIRECTLY. Measured: 40% of a fight
 * elapses before the first death, then bodies drop at 0.41/s — one every ~2.4s,
 * near-constant regardless of team size. The cascade is what makes a fight feel
 * bursty, and it starts the moment someone dies. Delaying that first death buys
 * more than slowing the whole fight does.
 *
 * ⚠️ AND IT IS EXPECTED TO COMPRESS THE SPREAD, which is the cost. A fight that
 * ends inside the hold window gets the full benefit; one that runs past the fade
 * gets it only at the start. Short fights therefore lengthen MORE than long ones.
 * Watch max/min across compositions, not just the mean.
 */
export const OPENING_MIT_BONUS = 0.20 // percentage POINTS of extra reduction
export const OPENING_MIT_HOLD = 30    // seconds at full strength
export const OPENING_MIT_FADE = 15    // seconds to decay to nothing

/** The opening guard's value at time `t`. Full, then a linear fade, then gone. */
export function openingMitigation(t: number): number {
  if (t <= OPENING_MIT_HOLD) return OPENING_MIT_BONUS
  const over = t - OPENING_MIT_HOLD
  if (over >= OPENING_MIT_FADE) return 0
  return OPENING_MIT_BONUS * (1 - over / OPENING_MIT_FADE)
}

export function mitigationFor(defStat: number, pierce = 0): number {
  const eff = defStat * (1 - Math.min(1, Math.max(0, pierce)))
  const raw = Math.max(0, eff) / MIT_DIVISOR
  if (raw <= MIT_KNEE) return raw
  return Math.min(MIT_CEIL, MIT_KNEE + (raw - MIT_KNEE) * MIT_SOFT)
}

/**
 * TRIAGE THRESHOLD — under `healPolicy: 'triage'` a restore is held until its best
 * recipient is at or below this fraction of max HP.
 *
 * ⚠️ 0.55, not lower: a heal has a cast time and a cooldown, so waiting for 25%
 * means waiting until the ally is already dead. High enough to catch someone
 * genuinely in trouble, low enough that a full-health target is never topped up.
 */
export const TRIAGE_AT = 0.55

/**
 * Fraction of max MP a `manaPolicy: 'conserve'` unit refuses to spend below, so
 * a big move stays affordable instead of being chipped away on fillers.
 */
export const MANA_RESERVE = 0.30
/**
 * Score multiplier on a hard-control move under `ccPriority`. ⚠️ A multiplier,
 * not an override: control still has to be worth casting, so a 10-power stun
 * does not beat a finisher on a target that is nearly dead.
 */
export const CC_PRIORITY_BONUS = 1.8

export const KNOCKBACK_SPEED = 12
/** Floor on the stagger, so even a 1-unit nudge is legible rather than a snap. */
export const KNOCKBACK_MIN_TIME = 0.15

export const TURN_RATE = 7 // radians per second
// Move statuses author their duration in ROUNDS, a unit the field has no
// concept of. A turn-based round — everyone acting once — is worth roughly
// this many seconds here. One constant, so restating it is impossible.
export const SECONDS_PER_ROUND = 2.0

// SUDDEN DEATH. ⚠️ Without it, the moment buffs and debuffs became real on the
// field, draws went from 4 to 11 in 40 fights — two teams shaving each other's
// damage down until the 90s cap ran out. The turn engine solved this exact
// problem at round 35 with escalating %-of-maxHp chip, and for the same reason
// it must be a FRACTION of max HP: flat chip lets raw CON win the clock, which
// double-dips a stat that already buys health.
// ⚠️ THE FIGHT TIMER IS TWO MINUTES; SUDDEN DEATH STARTS AT NINETY SECONDS.
// Do not read the ~20s MEAN duration as the fight length — that is how long a
// 3v3 takes to kill itself, and it is far inside the clock. The timer bounds the
// tail: the fights that would otherwise never end.
//
// ⚠️ MAX_SECONDS AND SUDDEN_DEATH_AT MOVE TOGETHER. Sudden death needs runway to
// finish the job — 45s of ramp here (4:15 into a 5:00 cap). Raising the onset
// past the cap means it never fires at all and the fight simply stops at the
// wall.
export const SUDDEN_DEATH_AT = 255 // seconds
export const SUDDEN_DEATH_BASE = 0.010 // fraction of maxHp per second at onset
export const SUDDEN_DEATH_RAMP = 0.004 // added per further second

export type FieldSide = 'A' | 'B'

// Rectangular cover. Blocks movement AND line of sight, so a caster can shelter
// behind a rock and a melee unit has to path around it.
//
// ⚠️ `kind` IS PRESENTATION ONLY. The engine collides and traces sight against the
// rectangle and nothing else, so a haybale and a boulder of the same size play
// IDENTICALLY. Keep it that way: the moment cover behaves differently by kind, every
// arena becomes a balance surface and `mapsweep` stops comparing like with like.
export interface Obstacle { x: number; y: number; w: number; h: number; kind?: ObstacleKind }

/**
 * What a piece of cover is made of. Resolved to a sprite by `themes.ts`.
 *
 * ⚠️ A UNION, NOT A FREE STRING, so a typo in an arena is a compile error rather
 * than a silently-boulder-shaped haybale.
 */
export type ObstacleKind =
  | 'boulder' | 'rubble'
  | 'crates' | 'barrel' | 'cart' | 'sawhorse'
  | 'logstack' | 'stump' | 'palisade'
  | 'orepile' | 'ingots' | 'crucible' | 'slagheap' | 'sluice'
  | 'leat' | 'gravelbar' | 'tinblocks' | 'blowingfurnace'
  // ── ARENA FURNITURE ───────────────────────────────────────────────────────
  // ⚠️ A DIFFERENT CLASS OF OBJECT, AND THE BIG BOARDS NEED IT. Everything above is a
  // league's TRADE — barrels, ore piles, gravel bars — sized for a 29-unit Wood yard.
  // On a 58-unit 5v5 board they are specks scattered on a plain, and no arrangement of
  // them makes a fight interesting. These are the ARENA: long walls, pillars, a gate, a
  // raised dais. They take footprints an order of magnitude larger, they break sight
  // lines rather than decorate them, and being dressed stone they are shared by every
  // league and re-tinted rather than re-drawn.
  | 'wall' | 'pillar' | 'gate' | 'dais' | 'obelisk'
  // ⚠️ RUINS ARE NOT DECORATION, THEY ARE THE IRREGULAR SHAPES. Intact furniture is
  // rectangles and cylinders — every piece covers the same way, and a board built from
  // them reads as a diagram. A wall with a gap torn through it and a snapped pillar with
  // its drum on the ground give cover a SILHOUETTE: partial, asymmetric, and different
  // from every other piece on the field. They also say the ground is old, which is most
  // of what a circuit's history costs to show.
  | 'ruinedwall' | 'brokenpillar'
  // ── SCENERY ───────────────────────────────────────────────────────────────
  // A third category, and neither of the other two. A barrel says which CIRCUIT you are
  // on; a wall says it is an arena. A tree says neither — it is the same tree at Wood and
  // at Apex, which is why two sprites dress all forty boards.
  | 'tree' | 'bush'
  // ── EXPANDING THE VOCABULARY (2026-08-02) ─────────────────────────────────
  // ⚠️ THE HEAP IS BEING REPLACED, NOT REPAIRED. `orepile` and `slagheap` both build from
  // one `heap` shape — a flattened sphere with rubble stuck on it — and it reads as a blob
  // at every size on every league. A tipped pile has a slumped face, a crest and an EDGE;
  // the honest way to draw one at this camera is a timber-framed BIN with the ore heaped
  // inside, because the frame is what carries the silhouette.
  // ⚠️ AND NOT EVERY CUP HAS TO BE ABOUT THE METAL. A circuit named after a material does
  // not mean every ground on it is a working floor — an abandoned wash pool taken back by
  // moss and ivy is still Tin, and it gives the league a board that is not another shed
  // full of hot things. That is what `vinewall` is for.
  | 'anvil' | 'orebin' | 'vinewall'
  // ── A UNIT OF MASS FOR THE COLONNADE FAMILY (2026-08-03) ──────────────────
  // ⚠️ A BARE COLUMN CANNOT CARRY A BOARD, AND IT WAS MEASURED RATHER THAN GUESSED.
  // Silver's first five grounds were authored from `pillar`, `brokenpillar` and `obelisk`
  // and came out at 0.79%–1.41% of board area under cover, against 3.1%–11.2% for every
  // other league. A pillar is 2.56 square units; a wall run is about 29. Ten columns on a
  // 3100-unit 4v4 board is a rounding error, and at the camera they read as pale stubs.
  // ⚠️ AND `maxPiecesFor` DID NOT CATCH IT, because the density law counts PIECES and is
  // blind to their size — it is calibrated on the 10-to-14-unit props Bronze and Iron are
  // built from. Ten of these "filled" a board with three times an Iron ground's area.
  //
  // A colonnade is the same idea at wall scale: a stylobate, columns standing on it, an
  // architrave across the top. Wall-sized footprint and presence, and you see THROUGH the
  // gaps — which is exactly what separates it from Bronze's solid coursing (opaque) and
  // from Iron's gateway (one opening). The family keeps its identity and gains its mass.
  | 'colonnade' | 'brokencolonnade'
  // ── THE PLANTED FAMILY (2026-08-03) ───────────────────────────────────────
  // ⚠️ GOLD IS SILVER'S TWIN IN TEAM SIZE, the third repeat of a scale on the ladder, so it
  // needs its own silhouette family for the same reason Iron needed one against Bronze. The
  // contrast is deliberately OPTICAL rather than thematic: a colonnade is straight lines,
  // hard shadow and bays you can see through; a hedge is a soft mass with a clipped top and
  // no holes at all. At the shipped camera those two sort apart instantly.
  // ⚠️ AND THE FAMILY IS THE RUNG AGAIN. Tier 5 turns on `venue.columns` and Silver's floor
  // is colonnades; tier 6 turns on `venue.planters` and Gold's floor is planting. The stands
  // and the ground say the same thing, which is the cheapest identity a league can be given.
  // ⚠️ AND FOUR MORE, BECAUSE TWO KINDS COULD NOT CARRY SIX BOARDS. Gold shipped with
  // `hedge` and `urn` only — measured, 57 pieces across six grounds drawn from 2 kinds at
  // 2 distinct sizes — and the six read as one ground repeated even though their
  // arrangements were genuinely different. Layout variety is INVISIBLE when the vocabulary
  // is one word. Bronze (4 kinds / 5 sizes) and Iron (3 / 4) are the leagues that work.
  // ⚠️ CHOSEN TO SPAN SILHOUETTE CLASSES, NOT TO ADD COUNT. Another long green bar would
  // have changed nothing:
  //    arbour     PIERCED  — see and shoot THROUGH it, the only green thing that lets you
  //    flowerbed  LOW      — draws under a metre; the only cover in Gold you shoot clean over
  //    fountain   CURVED   — the one piece with no flat face; an oval, because a deep
  //                          round footprint is the one shape a billboard cannot cover
  //    topiary    UPRIGHT  — a vertical, so a board is not six horizontals
  | 'hedge' | 'urn' | 'topiary' | 'arbour' | 'flowerbed' | 'fountain'

// ── The two new stats the design calls for ──────────────────────────────────
// Together they give four readable archetypes:
//   high cohesion / low predation  → anchor: holds the line with the team
//   high cohesion / high predation → coordinated dive: team focuses one target
//   low cohesion  / low predation  → skirmisher: freelances, takes what's near
//   low cohesion  / high predation → assassin: solo-dives the enemy backline
export interface FieldTraits {
  /** 0..1 — sticks with the team, shares focus, peels for allies. */
  cohesion: number
  /** 0..1 — hunts the highest-VALUE target regardless of danger or distance. */
  predation: number
}

export interface FieldUnit {
  id: string
  side: FieldSide
  slot: number // index within its own team — identity, for events and results
  m: Monster
  pos: Vec2
  /**
   * Where this unit was DEPLOYED, after the obstacle nudge — the anchor the
   * `formation: 'keep'` order holds its slot against. Never written again.
   */
  deployPos: Vec2
  /**
   * Statuses THIS unit can cash (`bonusVsStatus` riders in its own loadout), and
   * statuses ITS WHOLE SIDE can cash. Precomputed at setup because `chooseMove`
   * has no view of the team, and recomputing a union per tick per unit to answer
   * a question whose answer never changes would be silly.
   */
  comboCashes: StatusKind[]
  comboPrimes: StatusKind[]
  /**
   * Remaining ids from `tactics.openerIds` — the scripted opening, front first.
   *
   * ⚠️ PER-UNIT STATE IS WHY THIS TOOK SO LONG TO BUILD. Every other tactic is a
   * pure function of the current situation and could be a multiplier inside
   * `chooseMove`; an opening SEQUENCE has to remember how far through it is, which
   * needs somewhere to live. It sat dead on the field engine with ten UI references
   * behind it — a player built a scripted opening and nothing happened.
   *
   * ⚠️ ONE ID IS SPENT PER ACTION, CAST OR NOT. Matching battle.ts. If a queued
   * move is on cooldown, unaffordable or out of range the id is still dropped —
   * otherwise a monster whose opener it cannot afford stands there re-trying it
   * forever, which is a stall dressed as a plan.
   */
  openerQueue: string[]
  vel: Vec2
  radius: number
  /** world units per second */
  speed: number
  hp: number
  maxHp: number
  mp: number
  maxMp: number
  traits: FieldTraits
  /** id of the unit it is currently committed to */
  targetId: string | null
  /** seconds until it may re-evaluate its target */
  retargetIn: number
  /** per-move cooldowns, keyed by move id, in seconds */
  cooldowns: Record<string, number>
  /** seconds left in a cast it has committed to (it is rooted while casting) */
  castingFor: number
  castMoveId: string | null
  /** Who the in-flight cast is aimed at. Not always the combat target — a heal
   *  or a haul aims at an ALLY while the unit is still fighting an enemy. */
  castTargetId: string | null
  /** Live afflictions. `from` is the unit that applied it — fear flees FROM it
   *  and charm is drawn TOWARD it, so the source has to be remembered. */
  statuses: { kind: StatusKind; until: number; from: string }[]
  /** Timed multipliers from buff/debuff moves. Kept as a list rather than two
   *  scalars so several can overlap and expire independently — the turn engine
   *  models these as round-limited `Combatant.mods` and this is its analogue.
   *
   *  ⚠️ EXTENDED for the previously-inert effects rather than adding six parallel
   *  timers: `guard` (flat DR), `thorns` (flat reflect per hit taken), `dodge` /
   *  `acc` (percentage POINTS — never fractions), `hpRegen` (HP per second).
   *  One list means expiry is handled in exactly one place. */
  mods: {
    /**
     * The move id that applied this mod.
     *
     * ⚠️ WITHOUT IT, A BUFF STACKS WITH ITSELF. `modAtk` MULTIPLIES every entry
     * and guard/thorns/dodge/acc/regen all ADD, so re-casting is not a wasted turn
     * — it compounds. 17 pool moves re-arm BEFORE their own effect expires (Brace
     * worst at x2.00: 6s of guard on a 3s recharge), so every one of them was
     * permanently double-stacked on anything that held it.
     */
    src?: string
    atk?: number; dmgTaken?: number
    guard?: number; thorns?: number; dodge?: number; acc?: number; hpRegen?: number
    // MANA regen, authored per ROUND by the move and paid out per second here —
    // the same translation `hpRegen` gets.
    regen?: number
    /**
     * `defDebuff` — PERCENTAGE POINTS off the target's mitigation fraction.
     *
     * ⚠️ FIRST MAPPED ONTO NEGATIVE `guard` AND THAT WAS WRONG FOR THIS ENGINE.
     * The turn engine models it as `defFlat -= defDebuff`, and `guard` is this
     * engine's defFlat, so the port looked exact — but on a field a monster's
     * defence is the MITIGATION CURVE (CON/WIS ÷ 1400), not a flat guard it
     * usually does not have. Against a bare target negative guard just added a
     * few flat damage, which is why handing every damage class a defDebuff
     * move made them WORSE at killing tanks (39% -> 35%).
     * battle.ts prints this effect as "−N mitigation"; here that is literal.
     */
    mitDebuff?: number
    until: number
  }[]
  /** WARD — an absorb shield that soaks damage BEFORE health. Not timed: it is a
   *  pool that depletes, mirroring the turn engine's `Combatant.ward`. */
  ward: number
  /** CC DIMINISHING RETURNS. Successive control on the same unit lands shorter:
   *  applied for `duration × (1 − ccResist)`, then the meter steps up. Decays back
   *  to 0 after CC_DR_RESET seconds without any control landing, so chain-CC is a
   *  timing decision rather than a dump. */
  ccResist: number
  /** When the last control effect landed — drives the reset window above. */
  lastCcAt: number
  /** Brief control IMMUNITY, granted by a cleanse. ⚠️ Deliberately does NOT reset
   *  `ccResist`: resetting it would make cleansing your own ally a DR-wipe exploit
   *  that re-opens them to a full-duration stun. */
  ccImmuneUntil: number
  /** Has this unit attacked yet? ⚠️ The field's stand-in for the turn engine's
   *  `actedThisRound`, which `firstStrikeMult` keys off — a continuous field has
   *  no rounds, so "hasn't reacted yet" becomes "hasn't thrown a blow yet". Makes
   *  first-strike bonuses an OPENING-burst reward rather than a per-round one. */
  hasAttacked: boolean
  /** Seconds spent chasing the current target without getting closer. */
  chaseFor: number
  /** Closest this unit has come to its current target — the progress yardstick. */
  chaseBest: number
  /** Targets recently given up on, and the time each becomes fair game again. */
  gaveUp: Record<string, number>
  /** Time Fall Back becomes available again. */
  fallBackAt: number
  /** While `t` is under this, the unit is in a committed retreat. */
  fallBackUntil: number
  /** Mid-dash destination, travelled over several ticks rather than snapped. */
  /** Where a knockback is carrying this unit, and until when. Control is lost
   * for the duration — being shoved is a brief stagger, not a free reposition. */
  shoveTo: Vec2 | null
  shoveUntil: number
  dashTo: Vec2 | null
  /** When the dash gives up, so a blocked dash cannot strand the unit. */
  dashUntil: number
  /** Where that retreat is heading. ⚠️ Chosen ONCE when it triggers, not
   *  re-scored per tick — a committed retreat that re-picks its destination as
   *  the threat moves oscillates on the spot instead of going anywhere. */
  fallBackTo: Vec2 | null
  /** Shared escape lockout — set by ANY escape, checked by all of them. */
  escapeLockUntil: number
  /** TAUNT. While this holds, the unit must attack the taunter — the one thing
   *  that lets a tank protect a back line it is not standing on. */
  forcedTargetId: string | null
  forcedUntil: number
  /** seconds left unable to MOVE (it may still act) — from a root */
  rootedFor: number
  /** wall-clock time until which this unit is hard to notice (a Fade) */
  fadedUntil: number
  /** speed multiplier and the time it expires — from a slow */
  slowMult: number
  slowFor: number
  /** seconds an assassin will break off and dart to safety after a strike,
   *  before diving back in — the in-and-out of the assassin archetype. */
  disengageFor: number
  /** KITE BUDGET — seconds of backpedalling a ranged unit has left before it must
   *  stand and fight. You cannot attack and kite, so kiting is a brief measure:
   *  it drains while a threat is in kite range and only refills once the unit is
   *  safe again. At 0 the unit holds ground (and uses cover) instead of running. */
  kiteFor: number
  /** BLOCKING until this time. A unit in reach of its target with nothing off
   *  cooldown BRACES rather than wandering — the free defensive action the turn
   *  engine has always had ("Attack + Block") and the field engine was missing. */
  blockingUntil: number
  dead: boolean
}

// What the renderer consumes. Positions are sampled once per tick so the view
// can interpolate; discrete beats (a hit landing, a death) are their own events.
export type FieldEvent =
  | {
      t: number; kind: 'snapshot'
      units: {
        id: string; x: number; y: number; facing: number; state: UnitVisState
        /** ⚠️ WHO THIS UNIT IS HUNTING. Added for the escape instrument: without
         *  it a "chase" can only be inferred from damage, which misses the whole
         *  pursuit phase — precisely the part cover is meant to extend. Also what
         *  a renderer needs to draw a threat line. */
        targetId: string | null
        hp: number; maxHp: number; mp: number; maxMp: number
        // Active-effect icon keys, split by sign so the renderer draws its two
        // rows (debuffs above buffs, above the HP bar) directly. Usually 0–3.
        buffs: string[]; debuffs: string[]
      }[]
    }
  | { t: number; kind: 'cast'; id: string; targetId: string | null; move: string; channel: Channel }
  | { t: number; kind: 'hit'; id: string; targetId: string; move: string; channel: Channel; dmg: number; crit: boolean }
  | { t: number; kind: 'miss'; id: string; targetId: string; move: string }
  /** ⚠️ A CHASE THAT FAILED — emitted, not merely tallied, because the whole
   *  point of a give-up is that a watcher can SEE the assassin break off. It is
   *  also the only way to tell "the support escaped" from "the support was never
   *  chased", which no outcome metric can distinguish. */
  | { t: number; kind: 'giveup'; id: string; targetId: string }
  /** A committed retreat began. Visible so a player can see the break, and so
   *  the escape instrument can tell a retreat from a rout. */
  | { t: number; kind: 'fallback'; id: string }
  | { t: number; kind: 'heal'; id: string; targetId: string; move: string; amount: number }
  | { t: number; kind: 'status'; id: string; by: string; status: StatusKind }
  | { t: number; kind: 'blink'; id: string; fromX: number; fromY: number; toX: number; toY: number }
  | { t: number; kind: 'shove'; id: string; by: string; kind2: 'pull' | 'push' }
  | { t: number; kind: 'death'; id: string }
  | { t: number; kind: 'end'; winner: FieldSide | 'draw' }

/** Coarse pose for the renderer — drives which animation a sprite plays. */
export type UnitVisState = 'idle' | 'move' | 'cast' | 'hurt' | 'block' | 'dead'
/** Damage a blocking unit shrugs off. The free defensive action's whole value. */
export const BLOCK_DR = 0.2

// ── CC DIMINISHING RETURNS ──────────────────────────────────────────────────
// Arena-style: control on the same target lands shorter each time, resetting
// after a quiet window. 100% → 75% → 50% → 25% → immune.
//
// ⚠️ This is the hard cap on the lockout build (WIS Disruptor + CHA Enchanter:
// resource denial stacked on action denial). It must exist BEFORE both of those
// ability lines do, or that pairing has no counterplay at all.
//
// Global rather than per-category on purpose: mixing a silence with a charm gets
// no discount, which is exactly what caps the lockout. Per-category would reward
// varied CC kits but loosen that cap — revisit only if chain-CC feels
// over-punished in sim.
export const CC_DR_STEP = 0.25
export const CC_DR_RESET = 3.0 // seconds without control before the meter clears
/** Seconds of control immunity a cleanse grants. Compensation for NOT resetting
 *  the DR meter — a real window to act, without the DR-wipe exploit. */
export const CLEANSE_CC_IMMUNITY = 1.2

// ── THE FREE ATTACK ─────────────────────────────────────────────────────────
// ⚠️ It must never out-damage a real ability. It did: at train 850 the basic
// out-DPSed every monster's BEST ability by 1.2–2.3×, so abilities were strictly
// worse than just swinging, and the ~1s swing dominated the action economy.
//
// Base damage keys off the STAT — never off the monster's own abilities, which
// is gameable in both directions — on a deliberate hierarchy: a STR bruiser's
// swing is a real blow, a caster's is a feeble jab so it must spend abilities.
// The basic's stat follows its channel (melee STR / ranged DEX / magic INT /
// voice CHA / support WIS), so this table IS part of the class identity.
// An EVEN ramp 0.70 → 0.35, one step (0.07) per rung. ⚠️ The first cut of this
// table ran 1.00 → 0.35, which let a STR bruiser's free swing hit far too hard
// for a move that costs nothing; compressing the top keeps the hierarchy while
// stopping STR from carrying a fight on autos alone.
export const BASIC_STAT_TIER: Record<string, number> = {
  STR: 0.70, DEX: 0.63, INT: 0.56, CON: 0.49, CHA: 0.42, WIS: 0.35,
}
/**
 * Flat floor, so an untrained monster can still swing for something.
 *
 * ⚠️ HELD AT 5 — CUTTING IT PRODUCED A DRAW. `4` with scale 1/105 (a -26% free
 * attack) pushed a fight to 112.1s against status.test.ts's 90s bound and dropped
 * elite to 47/48. The free attack is the FILLER: take enough of it away and a
 * grinding matchup has nothing left to close with. The flat floor is also what the
 * WEAKEST monsters lean on — a Wood-league kit is mostly this swing — so it is the
 * wrong half of the formula to cut.
 *
 * `BASIC_STAT_SCALE` carries the reduction instead: it is the progressive half,
 * biting hardest exactly where abilities are strong enough to cover the slack.
 */
export const BASIC_BASE_POWER = 4.6
/**
 * Stat → power, kept well under the authored pool's scaling.
 *
 * ⚠️ 1/70 -> 1/90, and the SCALE rather than the floor because this half is
 * PROGRESSIVE: -4% at Wood, -11% at mid, -15% at Apex. Abilities scale with the
 * stat too, so the trained end can absorb the loss and the untrained end — which
 * has almost nothing but this swing — barely feels it.
 *
 * ⚠️ THE FREE ATTACK IS NOT A DURATION LEVER, measured. Across base 5 -> 2 the
 * damage share fell 14.7% -> 9.6% while the sweep clock sat at 26.2 / 26.1 / 25.1 /
 * 25.6s — noise. What it moves is the SHARE: less of a fight decided by the filler
 * and more by what the monster actually drafted. That is the reason to touch it.
 */
export const BASIC_STAT_SCALE = 1 / 98

// ── MANA ECONOMY ────────────────────────────────────────────────────────────
// ⚠️ WIS regen alone STARVED every physical class. `maxMana = WIS + INT/2` and
// regen keyed off WIS, but a warrior's abilities are STR-based — so the monsters
// whose kit is physical had the least fuel to cast it. Measured: 4–6 ability
// casts for a WHOLE fight, and 76% of all casts were the free attack.
//
// So each role now EARNS mana the way it actually plays. THREE roles only —
// a "caster" is not one of them: a caster is a DAMAGE dealer if it throws spells
// and a SUPPORT if it mends, and fuels the same way anyone in that job does.
// What makes casting feel different is the WIS POOL and WIS regen, which an
// INT/WIS monster has far more of.
//   tank    — pays for its abilities by soaking (per hit TAKEN)
//   damage  — pays for them by connecting (per hit DEALT)
//   support — a steady trickle, since it neither tanks nor spikes
export const MANA_ON_HIT_TAKEN = 2   // tanks
export const MANA_ON_HIT_DEALT = 2   // STR/DEX damage dealers
export const MANA_SUPPORT_PER_SEC = 1
/** WIS → mana/sec divisor. Lowered 300 → 200 so INT/WIS casters gain real fuel. */
export const WIS_REGEN_DIVISOR = 200
/**
 * FIELD-ONLY mana cost scalar. `monster.ts:manaCost` is deliberately 2× the base
 * formula — a TURN-engine decision, where a monster acts once per ~2s round so a
 * pool stretches a long way in wall-clock terms. On a real-time field a unit can
 * act every second, so that doubling priced abilities out entirely: even WITH the
 * per-hit generation above, monsters could not afford their cheapest ability 61.5%
 * of the time. This undoes the doubling for the field only, so battle.ts and its
 * 12 goldens are untouched.
 */
// ⚠️ P5, sim-tuned 0.5 -> 0.22. The 4th field slot made mana the binding
// constraint: 66% of live unit-ticks could not afford even the CHEAPEST ability,
// so monsters fell back to the free attack and the whole authored pool went
// unused (ability share of casts was 43%). Swept one knob at a time per the
// standing rule — 0.50/0.40/0.32/0.25/0.22/0.18/0.15 — and the response is
// clean and monotonic in starvation:
//   0.50 -> 66.1% starved, 57% basic, 8/12 resolved, 45.5s
//   0.32 -> 42.2% starved, 47% basic, 10/12,        39.8s
//   0.22 -> 18.4% starved, 38% basic, 9/12,         42.4s   <- chosen
//   0.15 -> 12.3% starved, 35% basic, 10/12,        41.2s
// 0.22 is the point that clears both targets (<20% starved, >60% ability share)
// while mana is still a resource you can run out of. Below ~0.18 the returns
// flatten and mana stops being a constraint at all, which would quietly delete a
// whole axis of play — the reason not to just take the lowest number.
// ⚠️ 0.22 -> 0.18 after LINE AFFINITY landed. Coherent kits actually cast their
// abilities (ability casts 1191 -> 1851), which pushed starvation back over the
// target to 23.1%. Re-swept: 0.20 -> 21.2%, 0.18 -> 18.5%. Not a walk-back of
// the 'keep mana a real constraint' reasoning above — the constraint is the SAME
// share of ticks as before, it just costs a smaller multiplier now that the
// abilities being paid for are worth casting.
// ⚠️ 0.18 -> 0.30, re-swept against the REWORKED pool. The old value was tuned
// when abilities were weak; once every stat was reworked and damage was tiered,
// mana stopped being a constraint at all — 39.7% of live ticks sat at FULL MP
// with nothing worth spending it on. Re-swept 0.18/0.22/0.26/0.30/0.34:
//
//   mult   starved   at FULL   managing   ability share   resolved   dur
//   0.18    11.1%     39.7%      49.2%        60%          10/12    35.4s
//   0.22    12.4%     23.6%      64.1%        60%          10/12    35.4s
//   0.26    14.2%     18.4%      67.3%        59%          10/12    35.4s
//   0.30    16.6%     13.3%      70.2%        58%          10/12    35.0s  <- chosen
//   0.34    24.8%      9.9%      65.4%        55%          10/12    34.9s
//
// ⚠️ Chosen on the MANAGING column, not the ability share. 'at FULL' is the
// direct measure of mana doing nothing, and 70.2% spent actively managing MP is
// the state where the resource is a decision. That knowingly trades 2 points of
// ability share (58% vs the >60% target) — a target set back when the pool was
// weak and the free attack was genuinely competitive with it. Abilities are
// still the clear majority of casts, and some basic attacks between casts is
// correct play rather than a failure.
// ⚠️ FIELD-ONLY. battle.ts uses manaCost() raw, so the 12 goldens cannot move.
/**
 * How long a scripted `openerIds` entry is HELD waiting to become castable, in
 * seconds, before the whole opening is abandoned.
 *
 * ⚠️ THE TURN ENGINE'S RULE IS WRONG HERE, AND MEASURABLY SO. `battle.ts` spends
 * one opener id per action whether or not it fires, which is safe there because
 * every unit is always in range on its turn. On a field there is an APPROACH: at
 * t=0 the enemy is 30 units away and the only castable thing is a team buff, so
 * the ported rule burned the order on `Rallying Song` (482 of 575 misses) before
 * the unit could ever reach anything. The id is now spent only when it FIRES.
 *
 * ⚠️ It still cannot stall — holding costs nothing, because the unit keeps acting
 * normally while it waits. The window exists so that an opener which never becomes
 * castable does not fire at second 40 and get called an "opening".
 */
export const OPENER_WINDOW = 9

export const FIELD_MANA_COST_MULT = 0.30

/**
 * FIELD loadout size — 4, against the turn engine's 3. More equipped abilities
 * means more that is off cooldown at any moment, which is the direct lever on the
 * action economy: fewer dead seconds filled by the free attack, and more room for
 * counterplay in what a monster brings.
 * ⚠️ FIELD-ONLY. `chooseLoadout` still defaults to 3, so battle.ts equips exactly
 * what it always did and the 12 goldens cannot move.
 */
export const FIELD_LOADOUT_SIZE = 4

/**
 * How far CONTAGION (`spreadStatus`) can jump from its victim, in field units.
 * ~3 body-widths: it punishes a clumped line and does nothing against a spread
 * one, which is what makes the `spacing` tactic a real decision rather than
 * flavour. The turn engine has no geometry and spreads to any N enemies; on a
 * field that would be a strictly better effect for free.
 */
export const CONTAGION_RADIUS = 5.5

/**
 * How far a TEAM buff, ward or heal reaches from the caster, in field units.
 *
 * ⚠️ TEAM EFFECTS USED TO HAVE NO RANGE AT ALL — `units.filter(x => x.side ===
 * u.side)`, so a war cry reached an ally on the far side of a 40x22 field.
 * Support was the only role in the game that was completely position-blind: a
 * Bard could stand in a corner and buff as well as one standing with its line.
 * 9 covers a team that is fighting together and drops a straggler or a diving
 * assassin. Sits under LEASH_RADIUS (12) on purpose — a unit at the leash edge
 * is exactly the one that should fall out of the aura.
 *
 * ⚠️ AT 9 THIS IS A GUARD RAIL, NOT A DECISION, and that is deliberate. Measured
 * ally-to-ally spacing over 45,842 sampled pairs:
 *     radius  5 -> 15.0% of allies missed      radius  8 -> 2.3%
 *     radius  6 ->  8.8%                       radius  9 -> 0.7%
 *     radius  7 ->  5.0%                       radius 10 -> 0.7%
 * Teams fight inside 9 almost always, so this punishes only a support that has
 * genuinely wandered off — 200 paired fights moved 8 of them (p = 0.29). Drop it
 * to 6-7 to make positioning a real cost; that is a BALANCE decision with a
 * measurable price, not a tuning nicety, so it is left generous until asked for.
 */
export const TEAM_AURA_RADIUS = 9

/**
 * How hard `formation: 'keep'` pulls a unit back onto its deployed SLOT, as a
 * blend weight against the goal it would otherwise pick (its stand-off on its
 * target). The ordinary cohesion blend maxes out at 0.35 toward the bare ally
 * centroid; keeping a slot is a stronger order than merely staying near friends,
 * so it sits above that.
 *
 * ⚠️ THE ANCHOR IS RELATIVE, NOT ABSOLUTE. The slot is `live ally centroid +
 * this unit's deploy offset`, so the whole shape TRANSLATES as the team advances.
 * Pinning to the literal deploy point would be a formation that never leaves the
 * start line, and at a blend of 0.55 nothing would ever reach the enemy.
 *
 * ⚠️ AND BOTH CENTROIDS ARE TAKEN OVER THE SAME LIVE SET. Recomputing the deploy
 * centroid over survivors is what lets a shrinking team CLOSE UP: hold it over
 * the original six and a team down to two keeps standing in the gaps where its
 * dead used to be, politely spread out for an enemy that is now concentrated.
 */
export const FORMATION_KEEP_PULL = 0.55

/**
 * How far a MELEE monster will look past the nearest body to obey its
 * `targetPriority`, expressed as world units of discount at full bias.
 *
 * ⚠️ THIS IS A LEASH, NOT A WEIGHT. Melee picks its target by pure distance
 * precisely because value-chasing across open ground is what once had bruisers
 * racing around the map instead of fighting. So the order is spent as a bounded
 * discount — a prioritised enemy counts as up to this many units nearer than it
 * really is — and never as a term in a free-for-all score.
 *
 * `priorityBias` peaks at 0.50 (`focus`) and 0.30-0.35 for the rest, so the real
 * discount runs 3.0-5.0 units. Deploy hexes are 2.6 apart: that is one to two
 * ranks, enough to step around a front-liner onto the marked healer behind it and
 * not nearly enough to cross a 40-unit field. Raising it past ~8 starts to
 * re-create the original bug.
 */
export const MELEE_PRIORITY_SLACK = 10

/**
 * How far a monster will walk PAST a nearer enemy to obey its target order.
 *
 * ⚠️ THIS IS WHAT MAKES THE ORDER AN ORDER RATHER THAN A NUDGE, and it is a LEASH for
 * exactly the same reason `MELEE_PRIORITY_SLACK` is. The order now FILTERS the candidate
 * list — a unit told to hunt casters considers only casters — and distance decides among
 * what is left. But an unbounded filter sends a bruiser across a 58-unit board to reach a
 * healer while three enemies hit it in the back, which is the cross-map hunt this engine
 * has already had to fix once.
 *
 * So: an ordered enemy is only a candidate if it is within this far of the NEAREST enemy.
 * At 12 that is four to five deploy hexes — through a front line and onto the rank behind
 * it, never across the field. Past ~20 and a 5v5 board starts to permit the suicide walk.
 */
export const ORDER_REACH = 12

/**
 * How urgent a dive has to be before it overrules a standing order.
 *
 * ⚠️ WITHOUT THIS THE FILTER DELETES THE ONLY COUNTER TO ASSASSINS. `diveThreat` is
 * documented in decide.ts as "the counterplay to Predation — without this term nothing
 * ever punishes a dive, and the assassin archetype has no counter at all". Filtering the
 * candidate list down to the order's matches would drop the diving assassin off it
 * entirely, and the order would have quietly bought immunity for every predator in the
 * game. An ally about to die outranks a standing order, which is also what a real handler
 * would do.
 */
export const ORDER_DIVE_OVERRIDE = 0.55

/**
 * The target-HP fraction at which `manaPolicy: 'conserve'` unlocks its reserve.
 *
 * ⚠️ THIS IS THE CONDITION THE ORDER WAS MISSING. Without it "hold 30% back" has
 * no moment to be held FOR — the reserve is either never spent (v1) or spent on
 * the first expensive cast against a full-health enemy (v2). Both are the same bug:
 * a fund with no release rule.
 *
 * At 0.50 the fund opens when the target is halfway down, which is roughly when a
 * big spell can actually END something rather than merely hurt it. Lower it and
 * `conserve` starts to hoard through fights it could have closed; raise it and it
 * stops being distinguishable from `burst`.
 */
export const FINISHER_AT = 0.50

/**
 * How much a PRIMER over-values a move that applies a status its side can cash.
 *
 * ⚠️ A MULTIPLIER, NOT AN OVERRIDE, like `CC_PRIORITY_BONUS`. A primer that always
 * casts the setup regardless of score is a monster that opens every fight applying
 * poison to a target already poisoned; the order should tilt the choice, not seize
 * it. The engine's own status logic still refuses to stack what is already on.
 */
export const COMBO_PRIME_BONUS = 1.7

/**
 * How hard a DETONATOR prefers an enemy already carrying a status it can cash,
 * on the same scale as `priorityBias` (which peaks at 0.50).
 *
 * ⚠️ THIS IS THE FREE HALF OF `comboRole` AND IT WAS BUILT FIRST DELIBERATELY.
 * Preferring a target costs nothing — the unit still attacks every tick. HOLDING a
 * payoff for a window that may never open costs tempo, and this engine has already
 * measured what withholding costs: `manaPolicy`'s finisher fund is correct and
 * still ~3 kills behind spending freely. Measure what the free half buys before
 * paying for the expensive one.
 */
export const COMBO_TARGET_BIAS = 0.45

export interface FieldSetup {
  seed: string
  teamA: Monster[]
  teamB: Monster[]
  /** Optional explicit deployment. Omit a side to auto-deploy it. */
  placeA?: Vec2[]
  placeB?: Vec2[]
  obstacles?: Obstacle[]
}

export interface FieldResult {
  winner: FieldSide | 'draw'
  events: FieldEvent[]
  /** seconds the fight lasted */
  duration: number
  survivorsA: number
  survivorsB: number
}

// ── Reach ───────────────────────────────────────────────────────────────────
// The 140 authored moves carry no range (they were written for a turn-based
// engine that had no space). Rather than a blocking data pass over all of them,
// reach DERIVES from the channel and can be overridden per-move later — so the
// engine runs today and authoring can refine it incrementally.
// ⚠️ MELEE WAS 1.6 AND THAT IS SMALLER THAN TWO MONSTERS. Unit radius is 0.9, so
// two bodies in contact sit 1.8 apart centre-to-centre — further than melee could
// reach. COLLISION_R_FRAC exists solely to shrink the collision floor to 1.19 so
// a swing connects at all, which left melee an operating window of 1.19..1.60:
// a 0.41-unit band on a 40-unit field, about 20x less positional tolerance than
// ranged. Measured consequence: melee units were in range of their best move 9%
// of ticks and melee was 6.5% of all damage in the game.
// 3.0 is arm's reach plus a step. Swept 2.2/2.6/3.0/3.4/3.8 — the gain plateaus
// by 3.0 (37/40 resolved @ 23.2s vs 34/40 @ 27.0s) and everything past it buys
// almost nothing while blurring melee against ranged 8 / magic 7.
export const CHANNEL_RANGE: Record<Channel, number> = {
  melee: 3.0,
  ranged: 8,
  magic: 7,
  voice: 5.5,
  support: 6,
}
/**
 * THE FREE ATTACK, AUTHORED PER CLASS — channel, reach and scaling stat.
 *
 * ⚠️ THIS REPLACES AN INFERENCE, AND THE INFERENCE IS THE BUG. `basicAttackFor`
 * used to reconstruct a monster's fighting range from whichever damage move it
 * happened to draft, and there is no version of that guess that works:
 *   - by POWER, a ranged monster got a MELEE basic it could never reach with;
 *   - by REACH, a Warrior that drafted one stray Piercing Shot became a RANGED
 *     unit — STR 348 kongrath stood off at 6.4 and shot, which is what a player
 *     watching a replay spotted, because it looks exactly as wrong as it is.
 * Both are the same mistake: a unit's IDENTITY was being derived from its
 * INVENTORY. The same mistake had already been found and fixed once in
 * `reachOf`; this was the second copy. Authoring it ends the family.
 *
 * ⚠️ THE STAT IS AUTHORED TOO. It was derived from the channel (melee⇒STR,
 * ranged⇒DEX, ...), so a Rogue — DEX primary, knife in hand — swung a basic that
 * scaled off STR, and a Spellsword's enchanted blade ignored INT. The free
 * attack now scales off the class's PRIMARY stat: what you are best at is what
 * you hit with.
 *
 * ⚠️ DEX IS WHY THIS CANNOT BE DERIVED FROM THE STAT PAIR EITHER. DEX covers
 * both the knife and the bow — Rogue (DEX/STR) is melee, Ranger (DEX/INT) is a
 * shot, and no formula over the pair tells them apart. Only authoring does.
 */
/**
 * The FOUR BANDS every class's free attack is drawn from. Channel and reach
 * together — a band is a way of fighting, not a number.
 *
 * ⚠️ `support` uses the VOICE channel, not `support`. Both are mitigated by WIS
 * so the defensive maths is identical, but `support` is the channel of heals and
 * shields and a free attack is neither. Voice reads correctly for the whole
 * band: an Orator's jibe and a Shaman's chant are the same kind of act.
 */
export const BASIC_BANDS = {
  melee:   { channel: 'melee'  as Channel, range: 3.0 },
  ranged:  { channel: 'ranged' as Channel, range: 8.0 },
  magic:   { channel: 'magic'  as Channel, range: 7.0 },
  support: { channel: 'voice'  as Channel, range: 6.0 },
}
export type BasicBand = keyof typeof BASIC_BANDS
export interface BasicAttackSpec { channel: Channel; range: number; stat: Stat }

/** class → which band it fights in, and the stat its free attack scales on. */
const CLASS_BAND: Record<string, { band: BasicBand; stat: Stat }> = {
  Tank:         { band: 'melee',   stat: 'CON' },
  Warrior:      { band: 'melee',   stat: 'STR' },
  Rogue:        { band: 'melee',   stat: 'DEX' },
  Ranger:       { band: 'ranged',  stat: 'DEX' },
  Sage:         { band: 'support', stat: 'WIS' },
  Wizard:       { band: 'magic',   stat: 'INT' },
  Spellsword:   { band: 'melee',   stat: 'INT' },
  Spellshield:  { band: 'melee',   stat: 'CON' },
  Captain:      { band: 'melee',   stat: 'STR' },
  Orator:       { band: 'support', stat: 'CHA' },
  Bard:         { band: 'support', stat: 'CHA' },
  Evoker:       { band: 'magic',   stat: 'INT' },
  Skirmisher:   { band: 'melee',   stat: 'STR' },
  Stalker:      { band: 'ranged',  stat: 'DEX' },
  Swashbuckler: { band: 'melee',   stat: 'DEX' },
  Shaman:       { band: 'support', stat: 'WIS' },
  Mystic:       { band: 'support', stat: 'WIS' },
  Herald:       { band: 'support', stat: 'CHA' },
  // The fallback is a fist. A Generalist has no kit identity by definition.
  Generalist:   { band: 'melee',   stat: 'STR' },
}

export const CLASS_BASIC: Record<string, BasicAttackSpec> = Object.fromEntries(
  Object.entries(CLASS_BAND).map(([cls, { band, stat }]) =>
    [cls, { ...BASIC_BANDS[band], stat }]),
)

// Heavier casts root the caster briefly — that wind-up is what gives a dive a
// window to punish a caster, and makes positioning matter.
/**
 * GLOBAL COOLDOWN MULTIPLIER on every ability's authored cooldown.
 *
 * ⚠️ THE ONLY LEVER THAT SLOWS THE MOP-UP. 60% of a fight elapses AFTER first
 * blood, at ~0.41 deaths/s, and that phase is set by the numbers advantage
 * rather than by per-hit damage — which is why a second 10% statScale trim moved
 * the mid median by 0.1s while shifting both tails. Cooldowns are the one axis
 * that slows the whole fight including the cascade, without making anyone
 * tankier or any hit weaker.
 *
 * ⚠️ Watch the CAST MIX when moving this, not just duration. Longer cooldowns
 * mean more time on the free attack, and a fight that is longer because monsters
 * are idling is worse than a short one.
 */
/**
 * ⚠️ 1.3 -> 1.0 WHEN COOLDOWNS BECAME SECONDS. Every authored cooldown was
 * multiplied by 1.3 in the same commit, so the effective recharge is unchanged to
 * the tick — this constant simply stopped being the place the unit conversion
 * secretly happened.
 *
 * KEPT, NOT DELETED, because it is still the global tempo dial described above and
 * `docs/BALANCING.md` records it as the one lever that slows the whole fight
 * including the cascade. It is now honestly a multiplier ON seconds rather than a
 * turns-to-seconds fudge wearing a tuning constant's name.
 */
/**
 * Global damage dial, applied in `strike()`.
 *
 * ⚠️ HELD AT 1.0 — THE 0.92 IT CARRIED IS NOW BAKED INTO THE DATA. The constant
 * stays because `docs/BALANCING.md` records it as a measured lever, and the same
 * treatment COOLDOWN_MULT got: bake the settled value, keep the dial at neutral.
 * Left live it made every authored power a lie — `docs/ABILITIES.md` would print
 * numbers the engine does not use, which is the exact failure the generated doc
 * exists to prevent. This project has been burned once already by a constant that
 * silently redefined authored data (cooldowns, turns vs seconds); one standing
 * multiplier over a hand-tuned pool is one too many.
 *
 * The bake was 141 authored powers rounded to integers (worst single-move error
 * 2.7%, on a power-19 move) plus BASIC_BASE_POWER and BASIC_STAT_SCALE, which are
 * COMPUTED rather than authored and so took the multiplier exactly, unrounded.
 *
 * ✅ It scales the FREE ATTACK too — the basic resolves through `strike()` — so
 * both had to be baked or the free-attack floor would have shifted under the pool.
 * ⚠️ An earlier draft of this comment claimed the opposite and warned NOT to touch
 * `BASIC_BASE_POWER`; acting on it would have left the basic 8% hot against a
 * freshly-cut pool. If a future edit moves the multiplier out of `strike()`, that
 * coupling breaks and both sites need revisiting.
 */
export const DAMAGE_MULT = 1.0

/**
 * The most of a single blow that flat `guard` DR may remove.
 *
 * ⚠️ WITHOUT IT, GUARD IS NEAR-IMMUNITY AT THE BOTTOM OF THE LADDER AND ROUNDING AT
 * THE TOP. `guard` is authored as a flat number in the same units as `power`, but
 * power is multiplied by `(1 + stat x statScale)` and guard is not — so a `Brace`
 * worth 6 removes **72% of every hit at Wood and 6% at Masters**. Measured by
 * zeroing `modGuard`: Wood 36.5s -> 15.3s and 37.6 hits-to-kill -> 10.7, while
 * Masters moved 17.8 -> 16.8. One constant, a 16x swing in what it is worth.
 *
 * ⚠️ THE TURN ENGINE NEVER HAD THIS. `battle.ts` scales guard by CON and folds it
 * into mitigation; only the field engine subtracts the raw authored number. Same
 * shape as DAMAGE_MULT living in one engine and not the other — two engines, one
 * design document, and the divergence found by measurement rather than by reading.
 *
 * ⚠️ A CAP, NOT A CONVERSION TO PERCENTAGE. Guard is flat DR on purpose — that is
 * what makes it strong against chip and weak against a nuke, and a percentage would
 * delete that identity. This only bites where the flat number was eating most of the
 * blow, which is exactly the case it was never calibrated for.
 */
export const GUARD_MAX_FRACTION = 0.35

export const COOLDOWN_MULT = 1.0
// ⚠️ HELD AT 1.0. A 1.02 step was applied and REVERTED: it bought nothing
// measurable, and the sweep that produced it uncovered a grind-lock that has to be
// understood before this constant is worth moving. Swept gradually,
// the no-draws bound in status.test.ts trips at 1.03 (longest fight 110.7s) and at
// 1.05 (256.6s, against a 300s engine cap) — then PASSES again at 1.08 and 1.10.
// A single fixture flips between resolving normally and grinding almost to the
// clock on a 1% parameter change. That is not a tuning threshold, it is a
// GRIND-LOCK: some matchup reaches a state where neither side can close, and which
// constants trigger it is chaotic.
//
// ⚠️ CHASE THE GRIND-LOCK BEFORE TUNING THIS FURTHER. The usable range is currently
// pocked with values that look fine on the sweep median and blow one fight out to
// four minutes. Elite is where this lever actually works — 30.3s at 1.0 rising to
// 36.3s at 1.20, the only reading in this whole session that clears the +/-3.9s
// band — so there is real value here once the landmines are gone.

export const CHANNEL_CAST_TIME: Record<Channel, number> = {
  melee: 0.15,
  ranged: 0.3,
  magic: 0.55,
  voice: 0.45,
  support: 0.4,
}
