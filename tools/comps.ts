// THE COMPOSITIONS EVERY BALANCE MEASUREMENT IS MADE AGAINST.
//
// ⚠️ ONE DEFINITION, TWO HARNESSES. `sweep40.ts` and `ab.ts` each carried their
// own copy of a ten-composition list. Identical today, free to drift tomorrow —
// and a paired A/B that disagrees with the sweep because the two are fighting
// different teams is worse than no measurement at all.
//
// ⚠️ AND THEY ARE THE GAME'S OWN TEAM SHAPES. Both copies were hand-picked
// species triples that existed NOWHERE in the game, so every balance number was
// measured against teams no player would ever field. `src/teamTemplates.ts` was
// written to close exactly that gap, and its header already claimed to be "THE
// SWEEP'S COMPOSITIONS" — but it was imported by nothing except its own test.
// Six templates, a species picker and a full test file, all unreachable. That is
// this project's signature failure mode, committed in the same file as the
// warning about it.
import { rolesFor, speciesForTemplate, templateById } from '../src/teamTemplates'
import { generateMonster } from '../src/monster'
import { CASHABLE_STATUSES } from '../src/moves'
import { DEFAULT_TACTICS, GAMEPLANS } from '../src/core'
import type { Monster, Tactics, TeamGameplan } from '../src/core'

/**
 * ⚠️ SPANNING, NOT SAMPLING. Melee measured as hopeless (100% deaths) alone and
 * fine (81%) beside a second front-liner — same monsters, different team. So
 * these deliberately reach from all-caster to double-front rather than
 * collecting "typical" teams, because there is no typical team. The templates
 * supply that span natively: Coven is the glass cannon, Phalanx the wall.
 */
const PAIRINGS: [string, string, number][] = [
  // [template A, template B, TEAM SIZE]
  //
  // ⚠️ SIZE IS PART OF THE COMPOSITION. Every pairing used to be 3v3, so the
  // instrument measured Bronze/Iron and nothing else while the game runs 1v1
  // (Wood) to 6v6 (Tamer Elite). It was blind by construction to the only place
  // the fight clock ever binds: at 6v6 one fight in forty ran 166.9s, against a
  // 31.7s max at 3v3 — a tail that simply does not exist at small sizes. Balance
  // decisions for Tamer Elite were being made on Tin-league evidence.
  //
  // 1v1 is deliberately absent: a team of one has no composition to vary, so it
  // measures a species rather than a shape. Wood league wants its own harness if
  // it ever needs one.
  ['coven', 'coven', 2],              // all-caster mirror, Copper/Tin scale
  ['coven', 'wolfpack', 2],           // glass vs divers
  ['hammer-anvil', 'hammer-anvil', 3], // the generalist baseline
  ['phalanx', 'vanguard', 3],         // wall vs burst
  ['phalanx', 'coven', 4],            // wall vs glass
  ['wolfpack', 'choir', 4],           // divers vs support
  ['vanguard', 'choir', 5],           // burst vs attrition — the sustain question
  ['hammer-anvil', 'wolfpack', 5],
  // ⚠️ 6 -> 5 WHEN 6v6 WAS REMOVED FROM THE GAME (2026-08-01). These two were the
  // sweep's only 6v6s and existed to cover the size where the long tail lived.
  // The tail did not come from the SIZE — measured with `compAtSize`, the same
  // Phalanx mirror runs 59.7s at 5v5 and 33.1s at 6v6 at Gold. It came from the
  // SHAPE, which is preserved. A harness that keeps measuring a size the game
  // cannot field is measuring a fight nobody will ever have — the exact failure
  // this file's header was written about.
  ['phalanx', 'phalanx', 5],          // the tank mirror that grinds
  ['choir', 'coven', 5],
  // ⚠️ THE COMBO SHAPES, AND THEY COME AS A PAIR. Vivisect runs the full
  // prime->detonate loop; Contagion primes the same statuses and never cashes
  // them. Fighting them against each other is the only way to tell "the LOOP
  // paid" from "affliction paid" — without the second one, any Vivisect result
  // is confounded with simply having more status damage on the field.
  ['vivisect', 'contagion', 3],
  ['vivisect', 'phalanx', 5],   // does the loop beat a wall that outlasts its setup?
]

export interface Comp {
  name: string
  a: string[]
  b: string[]
  size: number
  /** The plan each side fights to — see `TeamTemplate.gameplan`. */
  planA?: TeamGameplan
  planB?: TeamGameplan
  /** Per-slot combo assignment — see `TeamTemplate.roles`. */
  rolesA: (Tactics['comboRole'])[]
  rolesB: (Tactics['comboRole'])[]
  /** The templates behind it, so a comp can be rebuilt at a different SIZE. */
  ta: string
  tb: string
}

/**
 * The same pairing at a different team size.
 *
 * ⚠️ THE ONLY HONEST WAY TO COMPARE 5v5 WITH 6v6. Every pairing in `PAIRINGS` is
 * fixed at one size, so reading a 5v5 Vanguard-v-Choir against a 6v6 Phalanx mirror
 * measures the SHAPE and the SIZE at once and cannot separate them — and shape is
 * the bigger term: at Gold, burst-v-sustain runs 1.7x longer than divers-v-wall at
 * the same size and cap.
 *
 * ⚠️ The species are re-derived from the templates, NOT truncated. Dropping the last
 * monster off a 6v6 would remove whichever slot the pattern happened to put there;
 * `speciesForTemplate` re-cycles the pattern so a 5-slot Phalanx is still a Phalanx.
 */
export function compAtSize(c: Comp, size: number): Comp {
  const A = templateById(c.ta), B = templateById(c.tb)
  if (!A || !B) throw new Error(`compAtSize: unknown template ${c.ta}/${c.tb}`)
  const i = COMPS.indexOf(c)
  return { ...c, size,
    name: c.name.replace(/\d+v\d+$/, `${size}v${size}`),
    a: speciesForTemplate(A, size, 1000 + i * 7),
    b: speciesForTemplate(B, size, 5000 + i * 13),
    rolesA: rolesFor(A, size), rolesB: rolesFor(B, size) }
}

export const COMPS: Comp[] =
  PAIRINGS.map(([ta, tb, size], i) => {
    const A = templateById(ta)
    const B = templateById(tb)
    if (!A || !B) throw new Error(`comps: unknown template ${ta}/${tb}`)
    const label = ta === tb ? `${A.name} mirror` : `${A.name} v ${B.name}`
    return {
      name: `${label} ${size}v${size}`,
      size,
      a: speciesForTemplate(A, size, 1000 + i * 7),
      b: speciesForTemplate(B, size, 5000 + i * 13),
      planA: A.gameplan,
      planB: B.gameplan,
      rolesA: rolesFor(A, size),
      rolesB: rolesFor(B, size),
      ta, tb,
    }
  })

/** The orders one side of a composition fights under. */
export const tacticsFor = (plan?: TeamGameplan): Tactics =>
  plan ? { ...DEFAULT_TACTICS, ...GAMEPLANS[plan].tactics } : { ...DEFAULT_TACTICS }

/**
 * BUILD ONE SIDE OF A COMPOSITION — species, training AND orders.
 *
 * ⚠️ EVERY TOOL MUST COME THROUGH HERE. Each harness used to build its teams with
 * its own `generateMonster` map, which is how they all ended up measuring monsters
 * with no tactics at all: `generateMonster` set none, and nine separate call sites
 * each independently failed to add any. The sweep returned byte-identical totals
 * across five values of a live constant and nobody noticed for months.
 *
 * ⚠️ A SHAPE AND ITS PLAN TRAVEL TOGETHER. Reading `COMPS[i].a` and generating from
 * it by hand still compiles and still runs — and silently drops the gameplan,
 * putting that tool back to measuring one plan across ten shapes. If a tool needs
 * something this does not do, widen `opts`; do not fork the builder.
 */
/**
 * Reconcile the role a template ASKED for with the kit the picker actually dealt.
 *
 * ⚠️ A SLOT CANNOT PROMISE A MOVE. `speciesForTemplate` chooses a species by stat
 * affinity, and `chooseLoadout` then drafts from that stat's LINES — so which
 * status a monster ends up carrying is decided downstream of the template. Measured
 * on Vivisect, whose `detonate` slot is a front-liner: **one of eight** drafted any
 * payoff at all, while its `prime` slot kept landing Rogues holding a poison
 * applier AND its payoff — monsters told to set up for someone else when they could
 * have cashed it themselves. Bleed's connect rate fell 10.7% -> 3.0%.
 *
 * ⚠️ THAT IS THIS PROJECT'S SIGNATURE FAILURE ONE LAYER UP: an authored order the
 * system cannot reach. So the declared role is a PREFERENCE, checked against the
 * kit — a monster is never handed a job it has no move for, and never has one
 * taken away that it could do.
 */
function resolveRole(want: Tactics['comboRole'], m: Monster): Tactics['comboRole'] {
  const canDetonate = m.loadout.some((mv) => !!mv.effects?.bonusVsStatus)
  const canPrime = m.loadout.some((mv) => mv.status && CASHABLE_STATUSES.has(mv.status.kind))
  if (want === 'detonate' && canDetonate) return 'detonate'
  if (want === 'prime' && canPrime && !canDetonate) return 'prime'
  // Asked for something it cannot do — or asked to prime while holding the payoff
  // itself, which is strictly worse than cashing. Fall back to what the kit affords.
  if (canDetonate) return 'detonate'
  if (canPrime) return want ? 'prime' : undefined
  return undefined
}

export function teamFor(
  c: Comp, side: 'a' | 'b', seed: string,
  opts: { train?: number; statCap?: number } = {},
): Monster[] {
  const species = side === 'a' ? c.a : c.b
  const tactics = tacticsFor(side === 'a' ? c.planA : c.planB)
  const roles = side === 'a' ? c.rolesA : c.rolesB
  return species.map((sp, i) => {
    const m = generateMonster(`${seed}${c.name}${side}${i}`,
      { speciesId: sp, train: opts.train ?? trainTier(), statCap: opts.statCap }) as Monster
    return { ...m, tactics: { ...tactics, comboRole: resolveRole(roles[i] ?? tactics.comboRole, m) } }
  })
}

/** Mean team size across the sweep — for anything that needs a single figure. */
/**
 * THE TWO TRAINING TIERS THE HARNESSES MEASURE AT.
 *
 * ⚠️ `train` IS A BUDGET, NOT A STAT. Across all 65 species the highest single
 * stat comes out 455 at train 850, 706 at 1500, 904 at 2000, ~1000 at 2400.
 * League caps run 100 (Wood) to 1200 (Tamer Elite) and 1400 (Apex), multiplied
 * further by bloodline potential.
 *
 * ⚠️ SO ONE TIER MEASURED ONE LEAGUE. At MID the top stat is ~455, an Iron/Silver
 * monster — which means every capstone in the pool (lv650-920) was invisible to
 * every balance number this project has ever produced. Not because those moves
 * are unreachable, but because the harness never simulated a monster far enough
 * along to have unlocked them. Late content was being authored blind and a
 * reachability count of 68 read as a bug list when most of it was progression.
 *
 * ELITE puts the top stat around the Masters cap, so lv850 and lv920 capstones
 * are drafted and cast. `--elite` on sweep40/ab selects it.
 */
export const TRAIN_MID = 850
export const TRAIN_ELITE = 3200
/** Whichever tier the CLI asked for. Both harnesses read this. */
export const trainTier = () => (process.argv.includes('--elite') ? TRAIN_ELITE : TRAIN_MID)

export const TEAM_SIZE = Math.round(
  COMPS.reduce((n, c) => n + c.size, 0) / COMPS.length)
