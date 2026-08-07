// ─────────────────────────────────────────────────────────────────────────────
// FIELD MOVES (v0.93) — 18 abilities that only make sense on a battlefield.
//
// ⚠️ A SEPARATE POOL, deliberately. These are NOT added to `ALL_MOVES`.
// `chooseLoadout` picks from that pool, so growing it changes what every
// generated monster learns and equips — which moves all 12 golden battles and
// invalidates the balance arc calibrated against them. Keeping these here means
// the turn-based engine and its goldens are untouched, and it is honest anyway:
// a charge and a teleport mean nothing in an engine with no space. If the field
// engine ever replaces the turn-based one, the two pools merge then.
//
// Power is calibrated against the real pool at the same learn level
// (lv200 ≈ 16-28, lv780 ≈ 10-44, lv920 ≈ 52-68), and every one of these pays
// for its mobility by sitting at or under that band — moving IS part of the
// value.
// ─────────────────────────────────────────────────────────────────────────────
import { Move, Stat } from '../core'

/** The signature movement ability for each stat — one per stat, thematic. */
export const MOVEMENT_MOVES: Move[] = [
  {
    id: 'FLD-STR-move', name: 'Charge', stat: 'STR', learnLevel: 200, type: 'damage',
    channel: 'melee', target: 'enemy', cooldown: 5.2, accuracy: 90, power: 20,
    range: 1.8, castTime: 0.2,
    spatial: { move: { kind: 'dash', to: 'target', maxRange: 9 }, push: 2 },
    desc: 'Barrel across the ground into a foe, driving it back a step.',
  },
  {
    // ⚠️ cd 5 -> 12 -> 19. An escape must be PREMIUM, not FREQUENT — and
    // "premium" means ONCE A FIGHT. A ~20s fight against a 12s cooldown still
    // bought two, which is a rhythm rather than a decision. At 5s this fired
    // three or four times a fight against Fall Back's one, and the sweep fell
    // 39/40 -> 34/40 with fights +7.4s — escapes so cheap that nothing could be
    // committed to. Better, further and cover-ignoring is the premium; more
    // often is just the §5 failure.
    id: 'FLD-DEX-move', name: 'Backstep', stat: 'DEX', learnLevel: 200, type: 'buff',
    channel: 'support', target: 'self', cooldown: 24.7, accuracy: 100, power: 0,
    range: 6, castTime: 0.1,
    spatial: { move: { kind: 'dash', to: 'awayFromTarget', maxRange: 7 } },
    desc: 'Break away from whatever is on you and reset the distance.',
  },
  {
    id: 'FLD-CON-move', name: 'Bulwark Leap', stat: 'CON', learnLevel: 200, type: 'damage',
    channel: 'melee', target: 'enemy', cooldown: 6.5, accuracy: 90, power: 17,
    range: 2, castTime: 0.35,
    spatial: {
      move: { kind: 'dash', to: 'target', maxRange: 8 }, push: 3,
      area: { shape: 'circle', centre: 'self', radius: 3.4 },
    },
    desc: 'Land in the middle of them and scatter the ones you crush.',
  },
  {
    // cd 7 -> 13. Dropping off the radar is an escape by another route.
    id: 'FLD-WIS-move', name: 'Fade', stat: 'WIS', learnLevel: 200, type: 'buff',
    channel: 'support', target: 'self', cooldown: 27.3, accuracy: 100, power: 0,
    range: 6, castTime: 0.2,
    spatial: { fade: { duration: 2.5 } },
    desc: 'Slip out of notice. Attackers look for someone else.',
  },
  {
    // ⚠️ cd 6 -> 16 -> 26, the LONGEST of the set by a wide margin — longer than
    // most fights, so drafting Blink buys ONE guaranteed unanswerable escape. Blink ignores cover, so cut-off
    // pursuit — the thing that makes any escape budget a real bound — simply
    // does not apply to it. It is the one escape that cannot be answered by
    // geometry, so it is priced hardest. See docs/PATHFINDING_DESIGN.md §5.
    id: 'FLD-INT-move', name: 'Blink', stat: 'INT', learnLevel: 200, type: 'buff',
    channel: 'magic', target: 'self', cooldown: 33.8, accuracy: 100, power: 0,
    range: 12, castTime: 0.25,
    spatial: { move: { kind: 'blink', to: 'awayFromTarget', maxRange: 10 } },
    desc: 'Step out of the world and back into it, somewhere safer.',
  },
  {
    // ⚠️ The six stats needed six abilities and only five were specified —
    // CHA had none. Charisma's movement is not its OWN: it moves everyone
    // ELSE. Hauling an ally out of trouble is the one repositioning tool no
    // other stat has, and it pairs with the protect order.
    // cd 6 -> 11: hauling an ally clear is an escape granted to someone else.
    id: 'FLD-CHA-move', name: 'Beckon', stat: 'CHA', learnLevel: 200, type: 'buff',
    channel: 'voice', target: 'ally', cooldown: 22.1, accuracy: 100, power: 0,
    range: 10, castTime: 0.3,
    spatial: { haulAlly: 8 },
    desc: 'Call a struggling ally back to your side, whether it likes it or not.',
  },
]

/** Two extra skills per stat, each built around the arena itself. */
export const ARENA_MOVES: Move[] = [
  // ── STR — brute geometry ──────────────────────────────────────────────────
  {
    id: 'FLD-STR-1', name: 'Sunder Line', stat: 'STR', learnLevel: 430, type: 'damage',
    channel: 'melee', target: 'enemy', cooldown: 6.5, accuracy: 85, power: 28,
    range: 7, castTime: 0.4,
    spatial: { area: { shape: 'line', centre: 'self', range: 7, width: 2.4 } },
    desc: 'Split the ground in a straight line and everything standing on it.',
  },
  {
    id: 'FLD-STR-2', name: 'Wrecking Arc', stat: 'STR', learnLevel: 650, type: 'damage',
    channel: 'melee', target: 'enemy', cooldown: 7.8, accuracy: 85, power: 31,
    range: 4, castTime: 0.5,
    spatial: { push: 4, area: { shape: 'cone', centre: 'self', angle: 140, range: 4.2 } },
    desc: 'A sweep wide enough to clear everything in front of you.',
  },

  // ── DEX — reach and repositioning ─────────────────────────────────────────
  {
    id: 'FLD-DEX-1', name: 'Pincer Strike', stat: 'DEX', learnLevel: 430, type: 'damage',
    channel: 'melee', target: 'enemy', cooldown: 6.5, accuracy: 90, power: 24,
    range: 2, castTime: 0.2,
    spatial: { move: { kind: 'dash', to: 'behindTarget', maxRange: 8 }, backstab: 1.4 },
    desc: 'Round behind them before they finish turning.',
  },
  {
    id: 'FLD-DEX-2', name: 'Caltrops', stat: 'DEX', learnLevel: 650, type: 'debuff',
    channel: 'ranged', target: 'enemy', cooldown: 9.1, accuracy: 100, power: 0,
    range: 9, castTime: 0.3,
    spatial: { zone: { radius: 3.6, duration: 6, effect: 'slow', power: 0.5, centre: 'target' } },
    desc: 'Scatter the ground with iron. Crossing it is slow going.',
  },

  // ── CON — holding ground ──────────────────────────────────────────────────
  {
    id: 'FLD-CON-1', name: 'Quake Stomp', stat: 'CON', learnLevel: 430, type: 'damage',
    channel: 'melee', target: 'enemy', cooldown: 7.8, accuracy: 90, power: 22,
    range: 4, castTime: 0.45,
    spatial: { root: 1.2, area: { shape: 'circle', centre: 'self', radius: 4.6 } },
    desc: 'Bring your weight down and pin everything near you in place.',
  },
  {
    id: 'FLD-CON-2', name: 'Hold the Line', stat: 'CON', learnLevel: 780, type: 'buff',
    channel: 'support', target: 'self', cooldown: 10.4, accuracy: 100, power: 0,
    range: 5, castTime: 0.5,
    spatial: { zone: { radius: 4.5, duration: 7, effect: 'heal', power: 6, centre: 'self' } },
    desc: 'Plant yourself. Anyone standing with you mends while they fight.',
  },

  // ── WIS — denial and sanctuary ────────────────────────────────────────────
  {
    id: 'FLD-WIS-1', name: 'Hallowed Ground', stat: 'WIS', learnLevel: 430, type: 'buff',
    channel: 'support', target: 'self', cooldown: 10.4, accuracy: 100, power: 0,
    range: 7, castTime: 0.5,
    spatial: { zone: { radius: 4.2, duration: 8, effect: 'heal', power: 8, centre: 'self' } },
    desc: 'Consecrate the earth beneath your team.',
  },
  {
    id: 'FLD-WIS-2', name: 'Miasma', stat: 'WIS', learnLevel: 650, type: 'debuff',
    channel: 'magic', target: 'enemy', cooldown: 9.1, accuracy: 100, power: 0,
    range: 9, castTime: 0.5,
    spatial: { zone: { radius: 4, duration: 7, effect: 'damage', power: 7, centre: 'target' } },
    desc: 'Foul the air where they stand and make them leave it.',
  },

  // ── INT — space itself ────────────────────────────────────────────────────
  {
    id: 'FLD-INT-1', name: 'Gravity Well', stat: 'INT', learnLevel: 540, type: 'debuff',
    channel: 'magic', target: 'enemy', cooldown: 9.1, accuracy: 95, power: 11,
    range: 10, castTime: 0.6,
    spatial: { pull: 4.5, area: { shape: 'circle', centre: 'target', radius: 5 } },
    desc: 'Collapse a point in space and drag everything nearby into it.',
  },
  {
    id: 'FLD-INT-2', name: 'Meteor', stat: 'INT', learnLevel: 850, type: 'damage',
    channel: 'magic', target: 'enemy', cooldown: 10.4, accuracy: 80, power: 42,
    range: 12, castTime: 1.1, // the longest wind-up in the game
    spatial: { area: { shape: 'circle', centre: 'target', radius: 5.5 } },
    desc: 'Call something enormous down. It takes a while to arrive.',
  },

  // ── CHA — moving other people ─────────────────────────────────────────────
  {
    id: 'FLD-CHA-1', name: 'Rally Point', stat: 'CHA', learnLevel: 430, type: 'buff',
    channel: 'voice', target: 'team', cooldown: 10.4, accuracy: 100, power: 0,
    range: 6, castTime: 0.5,
    spatial: { zone: { radius: 5, duration: 7, effect: 'heal', power: 6, centre: 'self' } },
    desc: 'Set your standard down. The team fights better around it.',
  },
  {
    id: 'FLD-CHA-2', name: 'Scatter', stat: 'CHA', learnLevel: 650, type: 'debuff',
    channel: 'voice', target: 'enemy', cooldown: 7.8, accuracy: 90, power: 13,
    range: 6, castTime: 0.4,
    spatial: { push: 5, area: { shape: 'circle', centre: 'self', radius: 5.5 } },
    desc: 'A shout that breaks a formation apart.',
  },
]

export const ALL_FIELD_MOVES: Move[] = [...MOVEMENT_MOVES, ...ARENA_MOVES]

/** The stat-signature movement ability, if this stat has one. */
/**
 * ⚠️ AN ESCAPE, not merely a move that travels. `Charge` and `Bulwark Leap` also
 * move the caster — toward the enemy — and must never be gated by the escape
 * lockout or spend it. What counts is breaking contact: going AWAY, or dropping
 * off the targeting radar.
 */
export const isEscapeMove = (m: Move): boolean =>
  m.spatial?.move?.to === 'awayFromTarget' || !!m.spatial?.fade

export const movementMoveFor = (stat: Stat): Move | undefined =>
  MOVEMENT_MOVES.find((m) => m.stat === stat)

/** Field moves a monster's stats qualify it to use. */
export const fieldMovesFor = (stats: Record<Stat, number>): Move[] =>
  ALL_FIELD_MOVES.filter((m) => (stats[m.stat] ?? 0) >= m.learnLevel)
