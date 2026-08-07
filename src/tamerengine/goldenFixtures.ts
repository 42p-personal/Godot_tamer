// THE GOLDEN FIXTURES — one definition, two consumers.
//
// ⚠️ EXTRACTED FROM `golden.test.ts` SO THE PORT CONTRACT CANNOT DRIFT FROM THE TEST. The
// fixtures used to live inside the test file, which was fine while vitest was the only thing
// that read them. `tools/exportgoldens.ts` now emits them as JSON for the Godot port to diff
// against, and two copies of a regression pin is how you get a port that passes its own test
// while disagreeing with the game.
//
// The preamble explaining WHAT these pin and WHEN they may be recaptured stays on
// `golden.test.ts`, which is where somebody hitting a failure will look.
import { generateMonster } from '../monster'
import { simulateFieldBattle } from './engine'
import { ALL_MOVES } from '../moves'
import { DEFAULT_TACTICS, Monster } from '../core'
import { FieldEvent, Vec2 } from './types'

const move = (name: string) => {
  const m = ALL_MOVES.find((x) => x.name === name)
  if (!m) throw new Error(`golden references a move that no longer exists: ${name}`)
  return m
}
const mk = (seed: string, speciesId: string, kit: string[]): Monster => ({
  ...(generateMonster(seed, { speciesId, train: 850 }) as Monster),
  loadout: kit.map(move),
  tactics: { ...DEFAULT_TACTICS },
})

/** Two rocks, deliberately few — cover is a variable, not scenery. */
export const OBSTACLES = [
  { x: 19, y: 6, w: 2.2, h: 2.2 },
  { x: 13, y: 11, w: 2, h: 2 },
]

export interface Golden {
  name: string
  seed: string
  a: Monster[]
  b: Monster[]
  placeA: Vec2[]
  placeB: Vec2[]
  winner: 'A' | 'B' | 'draw'
  duration: number
  survivors: [number, number]
  casts: number
  hits: number
  deaths: number
  finalHp: number[]
}

export const GOLDENS: Golden[] = [
  {
    // A bruiser against a wall: the matchup the whole melee-reach pass was about.
    name: 'duel-melee',
    seed: 'g-duel',
    a: [mk('ga1', 'kongrath', ['Power Strike', 'Cleave', 'Blood Price'])],
    b: [mk('gb1', 'aegisox', ['Body Slam', 'Seize', 'Taunt'])],
    placeA: [{ x: 14, y: 11 }],
    placeB: [{ x: 26, y: 11 }],
    // ⚠️ 57.7s -> 14.6s at Stage 0. This golden is titled "a bruiser against a
    // wall", and that turned out to be literal: the fight ran to sudden death
    // because the melee could not get past the rock. It now resolves.
    // Stage 3a (Fall Back): 15s -> 13.1s and the winner finishes on 604 not
    // 428. A hurt unit that breaks contact for two seconds takes less on the
    // way, so the fight is shorter and the survivor healthier.
    // Stage 3b: 15.1s -> 24.2s. Both duellists now carry a movement ability,
    // so the loser keeps breaking contact and the fight takes far longer to
    // close. The clearest single illustration of what escapes cost in tempo.
    // Dashes travel now instead of snapping: 24.2s -> 21.7s, because a
    // Backstep costs half a second of ground rather than teleporting free.
    // ⚠️ PER-ABILITY RANGES + THE AUTHORED FREE ATTACK. All 137 moves now carry
    // their own reach and every class an authored basic (CLASS_BASIC), so a unit
    // stands at the shorter of its best weapon and its own free attack rather
    // than at whatever the longest thing in its kit happened to reach. Melee
    // classes close instead of standing off shooting.
    // ⚠️ Knockbacks TRAVEL now (KNOCKBACK_SPEED) instead of assigning position,
    // and cost the shoved unit control for the flight — see spatial.test.ts's
    // no-teleport tripwire.
    // ⚠️ Mitigation 1400 -> 1250 and +2 hpRegenBuff on every regen move — the
    // 'less bursty' pass. Survivors end healthier and fights run slightly longer.
    // ⚠️ Recaptured for the SUPERLINEAR CON term in maxHp (40 + CON*2 + CON^2/1600).
    // Shared by both engines, so all seven goldens moved together — intended.
    // ⚠️ Recaptured for the STAT SCALE trim (LOW 1/320->1/360, HIGH 1/130->1/145).
    // Field-only by design, which is why no battle.ts golden moved.
    // ⚠️ Recaptured for MIT_CAP 0.55 -> 0.65 (and the third mitigation mirror,
    // which had drifted to 0.55/1400). Field-only; no battle.ts golden moved.
    // ⚠️ Recaptured for the mitigation KNEE curve replacing the hard cap, and
    // for pierce now using the same shared helper. Field-only.
    // ⚠️ Recaptured for the OPENING GUARD — a global 20pp mitigation bonus that
    // holds 30s then fades over 15s. Every fight in a golden is inside the hold
    // window, so they take it at full strength throughout.
    // ⚠️ Recaptured for COOLDOWN_MULT 0.9 -> 1.3 — the global ability tempo.
    // ⚠️ Recaptured for the STAT SCALE REVERT — back to LOW 1/320, HIGH 1/130.
    // ⚠️ Recaptured for the BALANCE SWEEP pass (tools/pool.ts): 15 authored
    // values changed across 12 moves, four of them EARLY OUTLIERS cut rather than
    // raising the later moves they were beating. Deliberate content change.
    // ⚠️ Recaptured for DAMAGE_MULT 1.0 -> 0.92 and MIT_DIVISOR 1250 -> 1150 —
    // the first gentle increment of the less-bursty pass. FIELD ONLY: neither
    // constant exists in battle.ts, so the four turn goldens are untouched.
    // ⚠️ Recaptured for the FREE ATTACK cut: BASIC_STAT_SCALE 1/70 -> 1/90.
    // FIELD ONLY — battle.ts derives its own ATTACK_POWER and is untouched.
    // ⚠️ Moved by baking DAMAGE_MULT 0.92 into the 141 authored powers. Verified
    // as the INTEGER ROUNDING of that bake, not the bake itself: re-run with
    // unrounded powers this fixture is bit-identical to its frozen value.
    // ⚠️ Recaptured for the LAST-MONSTER-STANDING rule: a unit with no living
    // team-mate no longer AI-retreats. ⚠️ THIS IS A 1v1 FIXTURE, so every unit is
    // alone from t=0 and retreat is off for the WHOLE fight — which is the rule
    // working, not an overreach: in a duel there is never an ally for a chaser to
    // peel onto, which is the only thing retreat buys. `trio` (3v3) did not move.
    winner: 'B', duration: 23.2, survivors: [0, 1],
    casts: 82, hits: 57, deaths: 1, finalHp: [0, 481],
  },
  {
    // Ranged vs melee across the full width — pins approach, stand-off and the
    // line-of-sight behaviour, starting far enough apart that all three matter.
    name: 'caster-vs-brawler',
    seed: 'g-cast',
    a: [mk('ga2', 'archmage-aleph', ['Ember', 'Cinderburst', 'Arcane Bomb'])],
    b: [mk('gb2', 'ursath', ['Power Strike', 'Headbutt', 'Cleave'])],
    placeA: [{ x: 10, y: 11 }],
    placeB: [{ x: 30, y: 11 }],
    // ⚠️ WINNER FLIPPED A -> B at Stage 0, and the flip is the point: the
    // brawler now reaches the caster instead of scraping along cover on the way
    // in. Melee that can navigate beats a caster at this range — the matchup
    // working rather than breaking.
    // Stage 1 (pathfinding): 9.9s -> 6.8s and the brawler finishes on 530 not
    // 222. It now walks ROUND the rock rather than scraping along it, so it
    // arrives sooner and takes far less on the way in.
    // ⚠️ 6.8s -> 7s on the HEAL-DRAFT fix, and these goldens pin their loadouts
    // precisely so a pool/draft change CANNOT move them. It moved anyway, by one
    // tick — so the FIELD engine re-drafts its own 4-slot kit (FIELD_LOADOUT_SIZE)
    // rather than using the pinned 3. Worth knowing: the pinning is real for the
    // turn engine and only partial here.
    // Cover-seeking retreat: the caster now runs to the rock rather than
    // straight backwards, and the fight lasts longer for it.
    // ⚠️ 8.5s -> 5.8s on the TURN RATE. A unit that cannot pivot instantly also
    // cannot kite instantly — the brawler closes because the caster has to
    // commit to a heading before it can run. Natural movement is not free.
    // ⚠️ Moved by the per-ability range + authored free-attack pass — see duel-melee.
    // ⚠️ Mitigation 1400 -> 1250 and +2 hpRegenBuff on every regen move — the
    // 'less bursty' pass. Survivors end healthier and fights run slightly longer.
    // ⚠️ Recaptured for the SUPERLINEAR CON term in maxHp (40 + CON*2 + CON^2/1600).
    // Shared by both engines, so all seven goldens moved together — intended.
    // ⚠️ Recaptured for the STAT SCALE trim (LOW 1/320->1/360, HIGH 1/130->1/145).
    // Field-only by design, which is why no battle.ts golden moved.
    // ⚠️ Recaptured for MIT_CAP 0.55 -> 0.65 (and the third mitigation mirror,
    // which had drifted to 0.55/1400). Field-only; no battle.ts golden moved.
    // ⚠️ Recaptured for the mitigation KNEE curve replacing the hard cap, and
    // for pierce now using the same shared helper. Field-only.
    // ⚠️ Recaptured for the OPENING GUARD — a global 20pp mitigation bonus that
    // holds 30s then fades over 15s. Every fight in a golden is inside the hold
    // window, so they take it at full strength throughout.
    // ⚠️ Recaptured for COOLDOWN_MULT 0.9 -> 1.3 — the global ability tempo.
    // ⚠️ Recaptured for the STAT SCALE REVERT — back to LOW 1/320, HIGH 1/130.
    // ⚠️ Recaptured for the BALANCE SWEEP pass (tools/pool.ts): 15 authored
    // values changed across 12 moves, four of them EARLY OUTLIERS cut rather than
    // raising the later moves they were beating. Deliberate content change.
    // ⚠️ Recaptured for DAMAGE_MULT 1.0 -> 0.92 and MIT_DIVISOR 1250 -> 1150 —
    // the first gentle increment of the less-bursty pass. FIELD ONLY: neither
    // constant exists in battle.ts, so the four turn goldens are untouched.
    // ⚠️ Recaptured for the FREE ATTACK cut: BASIC_STAT_SCALE 1/70 -> 1/90.
    // FIELD ONLY — battle.ts derives its own ATTACK_POWER and is untouched.
    // ⚠️ Moved by baking DAMAGE_MULT 0.92 into the 141 authored powers. Verified
    // as the INTEGER ROUNDING of that bake, not the bake itself: re-run with
    // unrounded powers this fixture is bit-identical to its frozen value.
    // ⚠️ Recaptured for the LAST-MONSTER-STANDING rule: a unit with no living
    // team-mate no longer AI-retreats. ⚠️ THIS IS A 1v1 FIXTURE, so every unit is
    // alone from t=0 and retreat is off for the WHOLE fight — which is the rule
    // working, not an overreach: in a duel there is never an ally for a chaser to
    // peel onto, which is the only thing retreat buys. `trio` (3v3) did not move.
    winner: 'B', duration: 10.5, survivors: [0, 1],
    casts: 28, hits: 18, deaths: 1, finalHp: [0, 426],
  },
  {
    // Front line + damage + support on both sides: targeting, taunt, healing and
    // formation all in one fight.
    name: 'trio',
    seed: 'g-trio',
    a: [
      mk('ga3', 'aegisox', ['Body Slam', 'Taunt', 'Shield Wall']),
      mk('ga4', 'kongrath', ['Power Strike', 'Cleave', 'Blood Price']),
      mk('ga5', 'strixil', ['Mend', 'Ember', 'Mind Spike']),
    ],
    b: [
      mk('gb3', 'crocmaw', ['Body Slam', 'Seize', 'Taunt']),
      mk('gb4', 'grivvel', ['Ambush', 'Twin Fangs', 'Toxin Stack']),
      mk('gb5', 'maelurk', ['Ember', 'Frost Shard', 'Rime Bind']),
    ],
    placeA: [{ x: 12, y: 8 }, { x: 12, y: 11 }, { x: 8, y: 14 }],
    placeB: [{ x: 28, y: 8 }, { x: 28, y: 11 }, { x: 32, y: 14 }],
    // ⚠️ WINNER FLIPPED B -> A at Stage 0. Same cause: A's front line reaches
    // the fight instead of hanging on geometry, so its wall+bruiser pairing does
    // the job it was built for.
    // Stage 1: A now wins 3-0 rather than 2-0 — one fewer death on the winning
    // side, because its front line spends the approach walking instead of
    // grinding along cover.
    // Stage 2a (isolation targeting): 17.4s -> 23s. ⚠️ A term measured NULL
    // across 40 paired fights (p=0.69, 34 identical) still moved this one by
    // 5.6s — which is exactly why the sign test is the arbiter here and a
    // single golden is not. It is a fixture, not evidence.
    // Stage 2b (pursuit give-up): 17s -> 21s, and B finishes on 150/13 rather
    // than 223/215. Longer and bloodier is the mechanic working — a chase that
    // stalls now breaks off and finds someone reachable instead of following
    // one target to the end of the fight.
    // ⚠️ Stage 3a flipped this back to A, 2-0. Retreat helps whichever side is
    // losing the exchange at the moment it triggers, so a golden that was close
    // is exactly the one it can tip. The paired sweep is the arbiter, not this.
    // ⚠️ Slower escapes cost the ESCAPER, not the fight. A retreat you can watch
    // is a retreat that can be caught.
    // ⚠️ Moved by the per-ability range + authored free-attack pass — see duel-melee.
    // ⚠️ Knockbacks TRAVEL now (KNOCKBACK_SPEED) instead of assigning position,
    // and cost the shoved unit control for the flight — see spatial.test.ts's
    // no-teleport tripwire.
    // ⚠️ Mitigation 1400 -> 1250 and +2 hpRegenBuff on every regen move — the
    // 'less bursty' pass. Survivors end healthier and fights run slightly longer.
    // ⚠️ TRIAGE. Heals are now held until an ally is actually hurt, so the WIS
    // monster stops topping up a full-health team and spends the time elsewhere.
    // 14.4s -> 16.9s and the worst-off survivor ends on 303 rather than 18 —
    // the same mana buying a save instead of overheal.
    // ⚠️ Recaptured for the SUPERLINEAR CON term in maxHp (40 + CON*2 + CON^2/1600).
    // Shared by both engines, so all seven goldens moved together — intended.
    // ⚠️ Recaptured for the STAT SCALE trim (LOW 1/320->1/360, HIGH 1/130->1/145).
    // Field-only by design, which is why no battle.ts golden moved.
    // ⚠️ Recaptured for MIT_CAP 0.55 -> 0.65 (and the third mitigation mirror,
    // which had drifted to 0.55/1400). Field-only; no battle.ts golden moved.
    // ⚠️ Recaptured for the mitigation KNEE curve replacing the hard cap, and
    // for pierce now using the same shared helper. Field-only.
    // ⚠️ Recaptured for the FLANKING radii fix — engage 2.6 -> 4.0 (it sat below
    // melee reach), support 3.2 -> 2.5, bonus 10 -> 5. Fire rate 2.2% -> 17.5%.
    // ⚠️ Recaptured for the OPENING GUARD — a global 20pp mitigation bonus that
    // holds 30s then fades over 15s. Every fight in a golden is inside the hold
    // window, so they take it at full strength throughout.
    // ⚠️ Recaptured for COOLDOWN_MULT 0.9 -> 1.3 — the global ability tempo.
    // ⚠️ Recaptured for the STAT SCALE REVERT — back to LOW 1/320, HIGH 1/130.
    // ⚠️ Recaptured for the CLASS_LINES coverage pass — Wizard/Spellshield/Orator/
    // Bard each gained their primary stat's missing line, so those kits re-draft.
    // ⚠️ Recaptured for manaPolicy's spendable reserve. The move is NOT fully
    // explained — absent manaPolicy should be a no-op and this golden sets none.
    // Recaptured on instruction rather than because the cause was understood.
    // ⚠️ Recaptured for TARGET PRIORITY REACHING MELEE (27.6s -> 23.6s). This one
    // IS explained: the goldens set DEFAULT_TACTICS, whose targetPriority is
    // 'weakest', and melee used to discard that order entirely. Melee now finishes
    // a wounded body within MELEE_PRIORITY_SLACK instead of hitting the closest —
    // fewer casts (127 -> 122), fewer hits, a faster kill, and the survivors end on
    // a different HP split because a different monster took the beating.
    // ⚠️ IT IS ALSO WHY THE SWEEP SAW NOTHING: tools/comps.ts monsters carry NO
    // tactics at all, so the 40-matchup harness is blind to every order. Only the
    // goldens and tools/priority.ts fight monsters that have any.
    // ⚠️ Recaptured for the two EARLY DETONATORS (Fester lv220, Twist the Knife
    // lv360). A pool addition re-drafts every kit, and these two are drafted at
    // exactly the training levels the goldens sit at.
    // ⚠️ trio LOST A MONSTER (3 survivors -> 2, 3 deaths -> 4) and ran 5.8s
    // LONGER. Both are the intended direction: less free early damage, so the
    // cascade starts later and costs the winner something.
    // ⚠️ Recaptured for the BALANCE SWEEP pass (tools/pool.ts): 15 authored
    // values changed across 12 moves, four of them EARLY OUTLIERS cut rather than
    // raising the later moves they were beating. Deliberate content change.
    // ⚠️ trio 25.5s -> 32.2s, +6.7s on a 0.92 damage cut. The GOLDENS move far more
    // than the sweep median does (+1.6s) because a single fixed matchup has no
    // composition variance to average it away. Do not read a golden delta as the
    // size of a balance change — that is what the 48-fight sweep is for.
    // ⚠️ Recaptured for DAMAGE_MULT 1.0 -> 0.92 and MIT_DIVISOR 1250 -> 1150 —
    // the first gentle increment of the less-bursty pass. FIELD ONLY: neither
    // constant exists in battle.ts, so the four turn goldens are untouched.
    // ⚠️ trio 32.2s -> 34.8s and the last survivor ends on 14 HP. This matchup is
    // the one closest to the clock, and it is why BASIC_BASE_POWER was NOT cut:
    // one notch deeper (base 4, scale 1/105) pushed a sibling fight to 112.1s and
    // tripped status.test.ts's no-draws bound.
    // ⚠️ Recaptured for the FREE ATTACK cut: BASIC_STAT_SCALE 1/70 -> 1/90.
    // FIELD ONLY — battle.ts derives its own ATTACK_POWER and is untouched.
    // ⚠️ trio is the matchup closest to the clock — its last survivor ends on 14
    // HP. That is why BASIC_BASE_POWER was not cut: one notch deeper pushed a
    // sibling fight to 112.1s and tripped status.test.ts's no-draws bound.
    // ⚠️ Recaptured for the RETREAT FIX (decide.ts:retreatThreatOf — a unit no
    // longer flees an enemy that is itself below its panic threshold). 34.8s ->
    // 31.7s, and the last survivor goes 14 HP -> 82: less time spent backing away
    // from something that could not capitalise on it.
    // ⚠️ Moved by baking DAMAGE_MULT 0.92 into the 141 authored powers. Verified
    // as the INTEGER ROUNDING of that bake, not the bake itself: re-run with
    // unrounded powers the other two are bit-identical; THIS one still moves, because
    // `bestUtility` weighs scores against a raw `power` and UTILITY_FLOOR moved
    // with the pool (8 → 7.4). It swings 30.9s/38.6s on that constant alone.
    // ⚠️ Recaptured for GUARD_MAX_FRACTION — flat `guard` DR may no longer remove
    // more than 35% of a blow. A deliberate engine change, and this is the fixture
    // it should move: 3v3, the most casts of the three, and the only one whose kits
    // brace. `duel-melee` and `caster-vs-brawler` held. Winner flips A → B.
    // ⚠️ RECAPTURED FOR THE RETIREMENT OF `weakest`, AND THE CAUSE IS NAMED. That order
    // was the value `DEFAULT_TACTICS` shipped, so every fixture carried it; losing it
    // removes a real term — a 0.35 wounded weight in the ranged score and a distance
    // discount in the melee branch. Melee now targets purely by distance and stops
    // swapping off a body to chase a hurt one, and this fixture swings hard on that:
    // B 2-0 in 27.3s becomes A 3-0 in 18.3s.
    // ⚠️ CHECKED FOR A SYSTEMIC SHIFT BEFORE RECAPTURING, because a winner flip is the
    // one movement that deserves it: sweep40 reads 48/48, 25.4s, 233 kills against a
    // 26.4s / 232 baseline — inside the ±2.8s band. One fixture moved, the game did not.
    // ⚠️ AND `weakest`'s BEHAVIOUR SURVIVES ITS ORDER. The ranged score still carries an
    // autonomous `0.85 * wounded` term; what went is the player-facing instruction that
    // duplicated it, not finishing the hurt one.
    winner: 'A', duration: 18.3, survivors: [3, 0],
    casts: 110, hits: 84, deaths: 3, finalHp: [338, 379, 272, 0, 0, 0],
  },
]

export const run = (g: Golden) => simulateFieldBattle({
  seed: g.seed, teamA: g.a, teamB: g.b,
  obstacles: OBSTACLES, placeA: g.placeA, placeB: g.placeB,
})

export const tally = (events: FieldEvent[]) => {
  const n: Record<string, number> = {}
  for (const e of events) n[e.kind] = (n[e.kind] ?? 0) + 1
  return n
}

/**
 * The port contract: fully RESOLVED inputs plus the expected outputs.
 *
 * ⚠️ RESOLVED, NOT SEEDED, AND THAT IS THE POINT. Every monster here is emitted with its
 * concrete stats and its concrete loadout, so a ported engine never has to reproduce
 * `generateMonster`'s seeded RNG, `chooseLoadout`'s draft, or the 141-move pool before it can
 * be compared. The port's job is `engine.ts` and nothing else.
 *
 * ⚠️ AND IT SERIALISES THE MONSTER OBJECT WHOLE rather than picking fields. A hand-picked
 * subset is a guess about what the engine reads, and the engine reads more of a Monster than
 * is obvious (innates, aptitudes, tactics, bloodline potential). Whole-object export cannot
 * silently omit the field that turns out to matter.
 */
export interface GoldenContract {
  schema: number
  engine: string
  note: string
  obstacles: typeof OBSTACLES
  fights: {
    name: string
    seed: string
    teamA: Monster[]
    teamB: Monster[]
    placeA: Vec2[]
    placeB: Vec2[]
    expect: {
      winner: 'A' | 'B' | 'draw'
      duration: number
      survivors: [number, number]
      casts: number
      hits: number
      deaths: number
      finalHp: number[]
    }
  }[]
}

export function buildGoldenContract(): GoldenContract {
  return {
    schema: 1,
    engine: 'tamerengine/engine.ts',
    note: 'Resolved inputs + expected outputs. A ported engine must reproduce `expect` '
      + 'exactly from these inputs. Regenerate with `npx tsx tools/exportgoldens.ts`.',
    obstacles: OBSTACLES,
    fights: GOLDENS.map((g) => ({
      name: g.name,
      seed: g.seed,
      teamA: g.a,
      teamB: g.b,
      placeA: g.placeA,
      placeB: g.placeB,
      expect: {
        winner: g.winner,
        duration: g.duration,
        survivors: g.survivors,
        casts: g.casts,
        hits: g.hits,
        deaths: g.deaths,
        finalHp: g.finalHp,
      },
    })),
  }
}
