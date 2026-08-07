// Which existing moves gain a spatial dimension on the field (v0.93).
//
// Keyed by move NAME, exactly like arena.tsx's BESPOKE_KIND — a curated table
// rather than a data pass over all 140 moves. Anything not listed simply has no
// spatial behaviour, so this is additive and reversible, and the turn-based
// engine never reads it either way.
//
// The point of these is that positioning becomes a DECISION rather than a
// consequence. Before them, where a monster stood was only ever an output of
// the steering code; now a kit can attack the geometry itself — close a gap
// that was keeping you safe, drag a caster out from behind cover, or pin the
// assassin that just landed on your healer.
import { MoveSpatial } from '../core'
import { ALL_FIELD_MOVES } from './fieldMoves'

export const SPATIAL_MOVES: Record<string, MoveSpatial> = {
  // ── ROOTS AND SLOWS ───────────────────────────────────────────────────────
  // ⚠️ CORRECTION to the class-kit audit, which claimed "no pool move authors a
  // root or a slow". Untrue — Pin Down, Snipe, Glacial Prison, Deep Freeze,
  // Earthshaker and Static Chain all carry one further down this table. The real
  // gaps were narrower: CON had NONE (the Warden could shove and nothing else),
  // and INT's were all lv540+, so a mage had no movement denial until very late.
  // These entries fix those two, they do not introduce the category.
  //
  // ⚠️ Keys are matched by move NAME — renaming in moves.ts without renaming
  // here makes the move silently inert, exactly how 8 entries once did nothing.
  //
  // ⚠️ root/slow land in applyOnTarget, which runs only in the HIT path, so each
  // carrier must be a move that actually connects. A zone is different:
  // applySelfEffects places it at CAST time, which is why Shield Wall can be a
  // pure utility that never strikes anyone. And any `allEnemies` move needs an
  // `area` shape or it has no geometry on a continuous field.
  'Rime Bind': { root: 1.4 },                              // INT — an early single-target pin
  'Frost Nova': { slow: { mult: 0.6, duration: 2.5 },      // INT — early AoE chill
    area: { shape: 'circle', centre: 'self', radius: 5 } },
  'Seize': { pull: 2.4, root: 1.2 },                       // CON — grab and drag in
  'Quagmire Stomp': { slow: { mult: 0.55, duration: 3 },   // CON — churn the whole line's footing
    area: { shape: 'circle', centre: 'self', radius: 5.2 } },
  // Zone `power` on a slow zone is the speed MULTIPLIER, not a magnitude.
  'Shield Wall': { zone: { radius: 4.5, duration: 6, effect: 'slow', power: 0.55, centre: 'self' } },
  // CON's Warden kit. Geometry is the whole line, so nearly all of it is spatial.
  'Barricade': { zone: { radius: 5, duration: 7, effect: 'slow', power: 0.5, centre: 'self' } },
  'Zone of Control': { zone: { radius: 3.6, duration: 8, effect: 'slow', power: 0.6, centre: 'self' } },
  'Crushing Grip': { root: 2.0 },
  // WIS — a patch of dead air. The only spatial move in the stat.
  'Null Field': { zone: { radius: 4.2, duration: 7, effect: 'slow', power: 0.7, centre: 'self' } },
  // INT — teleports, ground, and the frost that holds people still.
  'Phase Step': { move: { kind: 'blink', to: 'awayFromTarget', maxRange: 9 } },
  'Firewall': { zone: { radius: 4.4, duration: 6, effect: 'damage', power: 5, centre: 'self' } },
  'Displace': { move: { kind: 'blink', to: 'behindTarget', maxRange: 12 }, push: 5, root: 1.2 },
  'Arcane Bomb': { area: { shape: 'circle', centre: 'target', radius: 3.4 } },
  'Detonate': { area: { shape: 'circle', centre: 'target', radius: 5.6 } },
  'Seismic Crush': { area: { shape: 'circle', centre: 'self', radius: 5.6 } },
  'Tremor': { slow: { mult: 0.6, duration: 2.5 }, area: { shape: 'circle', centre: 'self', radius: 5.4 } },
  'Earthen Grasp': { root: 1.8, area: { shape: 'circle', centre: 'self', radius: 5.8 } },
  'Overrun': { move: { kind: 'dash', to: 'target', maxRange: 7 }, push: 3 },

  // ── GAP CLOSERS ───────────────────────────────────────────────────────────
  // The counter to kiting. A charge crosses the ground, so cover still stops
  // it — that is what keeps it fair against a caster who positioned well.
  'Power Strike': { move: { kind: 'dash', to: 'target', maxRange: 7 } },
  'Reckless Slam': { move: { kind: 'dash', to: 'target', maxRange: 8 } },
  'Titanfall': { move: { kind: 'dash', to: 'target', maxRange: 9 }, push: 2.5 },
  'Colossus Crash': { move: { kind: 'dash', to: 'target', maxRange: 8 }, push: 3 },
  'Body Slam': { move: { kind: 'dash', to: 'target', maxRange: 7 }, push: 3 }, // already a knockback move

  // ── TELEPORTS ─────────────────────────────────────────────────────────────
  // A blink IGNORES cover, which is the entire reason to want one: it is the
  // only way to reach a caster who has correctly hidden behind a rock.
  // Paid for with a backstab that only lands if you actually arrive behind.
  'Shadowstep': { move: { kind: 'blink', to: 'behindTarget', maxRange: 12 }, backstab: 1.45 },
  'Void Lance': { move: { kind: 'blink', to: 'behindTarget', maxRange: 14 }, backstab: 1.4 },
  'Executioner': { move: { kind: 'blink', to: 'behindTarget', maxRange: 10 }, backstab: 1.6 },
  'Mana Leech': { move: { kind: 'blink', to: 'awayFromTarget', maxRange: 9 } }, // escape, not engage

  // ── FORCED MOVEMENT ───────────────────────────────────────────────────────
  // Pull is the answer to a turtled back line; push is the answer to a diver
  // standing on your healer. Both are counterplay, not just damage.
  'Pin Down': { pull: 5, root: 1.2 },
  // DEX's reworked kit. ⚠️ Every allEnemies move needs an `area` or it has no
  // geometry on a continuous field — the spatial test enforces it.
  'Hamstring': { root: 1.5 },
  'Vanish': { fade: { duration: 2.5 } },
  'Smoke Bomb': { fade: { duration: 1.6 }, area: { shape: 'circle', centre: 'self', radius: 4.5 } },
  'Ricochet': { area: { shape: 'circle', centre: 'target', radius: 4 } },
  'Pinning Volley': { root: 1.2, area: { shape: 'circle', centre: 'target', radius: 4.4 } },
  'Plague Shot': { area: { shape: 'circle', centre: 'target', radius: 4.6 } }, // crippling shot
  'Sonic Boom': { push: 4 },

  // ── MOVEMENT DENIAL ───────────────────────────────────────────────────────
  // Rooting a fast monster is worth more than damaging it — this is where DEX
  // as move speed finally has a real counter.
  'Lullaby': { slow: { mult: 0.45, duration: 2.5 } },
  'Captivate': { slow: { mult: 0.55, duration: 3 } },

  // ── AREA SHAPES ───────────────────────────────────────────────────────────
  // The 14 moves that used to target `frontRow` / `backRow` / `allEnemies`.
  // Those targets described a formation the field does not have, so they hit
  // everyone regardless of position — which made spreading out pointless and
  // AoE unavoidable. Real geometry restores the decision on both sides.
  //
  // ⚠️ CENTRE MATTERS. A shout radiates from the CASTER (you cannot aim a
  // scream at a spot); a bombardment lands on the TARGET. Getting this wrong
  // makes a support monster nuke its own feet.

  // Melee sweeps — a wedge in front of the attacker.
  'Cleave': { area: { shape: 'cone', centre: 'self', angle: 100, range: 3.6 } },

  // Shockwaves — a ring centred on the one who stamped.
  'Earthshaker': { push: 3.5, slow: { mult: 0.6, duration: 2 }, area: { shape: 'circle', centre: 'self', radius: 5.5 } },

  // Bombardments — land on a spot, so they punish clumping hardest.
  'Rain of Arrows': { push: 3, area: { shape: 'circle', centre: 'target', radius: 4.2 } },
  'Inferno': { area: { shape: 'circle', centre: 'target', radius: 5 } },
  'World Ender': { area: { shape: 'circle', centre: 'target', radius: 7 } }, // the biggest in the game

  // Chained lightning — a line that pierces everything in its path.
  'Static Chain': { slow: { mult: 0.6, duration: 2 }, area: { shape: 'line', centre: 'self', range: 9, width: 2.2 } },

  // Voice — radiates from the caster. Reaching further than a shout should is
  // the classic way a support accidentally becomes the best damage in the game,
  // so these stay deliberately tight.
  'Screech': { area: { shape: 'circle', centre: 'self', radius: 5.5 } },
  // STR's two new shouts/sweeps. ⚠️ Any allEnemies move MUST author an area or it
  // has no geometry on a continuous field — the spatial test enforces this, and
  // it is what caught Frost Nova and Quagmire Stomp earlier in this rework.
  'Intimidate': { area: { shape: 'circle', centre: 'self', radius: 6 } },   // a roar carries
  'Whirlwind': { area: { shape: 'circle', centre: 'self', radius: 3.4 } },  // only what is in reach

  'Cacophony': { area: { shape: 'circle', centre: 'self', radius: 5 } },
  // CHA's two new shouts. Crowd Surge is the defensive one — it PUSHES.
  'Mass Hysteria': { area: { shape: 'circle', centre: 'self', radius: 6.2 } },
  'Dirge': { area: { shape: 'circle', centre: 'self', radius: 5.8 } },
  'Crowd Surge': { push: 4.5, area: { shape: 'circle', centre: 'self', radius: 5.2 } },
  'Crescendo': { area: { shape: 'circle', centre: 'self', radius: 5.5 } },
  'Grand Mockery': { area: { shape: 'circle', centre: 'self', radius: 6 } },
  'Demoralize': { area: { shape: 'circle', centre: 'self', radius: 5.5 } },
  "Bulwark's Challenge": { area: { shape: 'circle', centre: 'self', radius: 6.5 } }, // a taunt must reach
}

// Field moves carry their spatial block inline (they are nothing WITHOUT it),
// so they are folded in here rather than duplicated in the table above.
const FIELD_SPATIAL: Record<string, MoveSpatial> = Object.fromEntries(
  ALL_FIELD_MOVES.filter((m) => m.spatial).map((m) => [m.name, m.spatial!]),
)

/** The spatial behaviour of a move, if it has one. */
export const spatialOf = (moveName: string): MoveSpatial | undefined =>
  SPATIAL_MOVES[moveName] ?? FIELD_SPATIAL[moveName]
