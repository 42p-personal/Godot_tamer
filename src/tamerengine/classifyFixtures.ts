// THE CLASSIFICATION CONTRACT — class, role, mana role, and the free attack.
//
// ⚠️ THE FIFTH AND LAST PORTABLE BLOCK, and the one that decides WHAT A MONSTER IS. Nothing
// here touches geometry; all of it is stat comparison and table lookup. But it is upstream of
// almost everything else: class picks the free attack, the free attack sets reach, mana role
// decides how a unit refuels, and `CLASS_LINES` keys ability affinity off the class name.
// Get this wrong and every downstream system is subtly wrong for reasons that never point back
// here.
//
// ⚠️ NO EXTRACTION WAS NEEDED — these were already pure. `classForStats`, `roleOfClass`,
// `manaRoleOf` and `basicAttackFor` read stats and tables and nothing else. That is worth
// noticing: the systems that were hardest to port were the ones that had grown a dependency on
// position, and these never did.
import { Stats, classForStats, roleOfClass } from '../core'
import { manaRoleOf } from './decide'
import { basicAttackFor } from './engine'
import { Monster } from '../core'

const stats = (over: Partial<Stats>): Stats =>
  ({ STR: 0, DEX: 0, CON: 0, WIS: 0, INT: 0, CHA: 0, ...over }) as Stats

/** Only the fields the classifiers read. */
const mon = (s: Partial<Stats>, className?: string): Monster =>
  ({ stats: stats(s), className: className ?? classForStats(stats(s)) }) as Monster

export interface ClassifyCase { name: string; axis: string; input: any; expect: any }
const CASES: ClassifyCase[] = []

// ── class derivation ─────────────────────────────────────────────────────────
// ⚠️ CLASS IS EMERGENT AND RECOMPUTED, NEVER STORED. It comes from a monster's two CURRENT
// highest stats, so training genuinely changes what a monster IS. `Species.naturalClass` is
// only "what this species' untrained base stats derive" and is used by `validate.ts` alone.
// **Never write flavour text or UI as if a species is destined for its class.**
const CLASS_PAIRS: [string, Partial<Stats>][] = [
  ['STR primary, CON secondary', { STR: 300, CON: 200 }],
  ['STR primary, DEX secondary', { STR: 300, DEX: 200 }],
  ['DEX primary, STR secondary', { DEX: 300, STR: 200 }],
  ['DEX primary, INT secondary', { DEX: 300, INT: 200 }],
  ['CON primary, STR secondary', { CON: 300, STR: 200 }],
  ['INT primary, WIS secondary', { INT: 300, WIS: 200 }],
  ['INT primary, CON secondary', { INT: 300, CON: 200 }],
  ['WIS primary, CHA secondary', { WIS: 300, CHA: 200 }],
  ['WIS primary, INT secondary', { WIS: 300, INT: 200 }],
  ['CHA primary, STR secondary', { CHA: 300, STR: 200 }],
  ['CHA primary, WIS secondary', { CHA: 300, WIS: 200 }],
  ['CHA primary, INT secondary', { CHA: 300, INT: 200 }],
]
for (const [name, s] of CLASS_PAIRS) {
  CASES.push({ name, axis: 'classForStats', input: s, expect: classForStats(stats(s)) })
}
// ⚠️ AN UNMATCHED PAIR FALLS TO `Generalist`, which is a real class with a real free attack —
// not an error state. It is ~3% of the population since the orphan-pair seven were added.
CASES.push({
  name: 'an unmatched stat pair falls to Generalist', axis: 'classForStats',
  input: { WIS: 300, STR: 200 }, expect: classForStats(stats({ WIS: 300, STR: 200 })),
})
// ⚠️ TIES ARE BROKEN BY THE `STATS` DECLARATION ORDER, not by anything meaningful. Two equal
// stats produce a stable but arbitrary class — worth pinning so a port does not "fix" it into
// a different arbitrary answer and quietly reclassify a slice of the population.
CASES.push({
  name: 'a perfect tie resolves by declaration order', axis: 'classForStats',
  input: { STR: 300, DEX: 300 }, expect: classForStats(stats({ STR: 300, DEX: 300 })),
})
CASES.push({
  name: 'an all-zero monster still gets a class', axis: 'classForStats',
  input: {}, expect: classForStats(stats({})),
})

// ── team-composition role ────────────────────────────────────────────────────
// ⚠️ TANKS COUNT AS SUPPORT HERE. It is a COMPOSITION label — a Tank is not a damage pick —
// and it drives rival-team templates. Spatially a Tank is a front-line anchor, which is a
// different question answered by `archetypeOf`. Two labels, two purposes, easy to conflate.
for (const c of ['Warrior', 'Rogue', 'Ranger', 'Wizard', 'Spellsword', 'Captain', 'Tank',
  'Spellshield', 'Sage', 'Orator', 'Bard', 'Evoker', 'Skirmisher', 'Stalker', 'Swashbuckler',
  'Shaman', 'Mystic', 'Herald', 'Generalist']) {
  CASES.push({ name: `role of ${c}`, axis: 'roleOfClass', input: { className: c }, expect: roleOfClass(c) })
}

// ── mana role ────────────────────────────────────────────────────────────────
// ⚠️ MANA BY ROLE IS THE FIX FOR PHYSICAL CLASSES BEING UNABLE TO AFFORD THEIR OWN KIT.
// A damage dealer is paid for CONNECTING, a tank for SOAKING, a support by TIME. Each fuels
// itself by doing its actual job.
const MANA_ROLE: [string, Partial<Stats>, string | undefined][] = [
  ['an explicit Tank is a tank', { STR: 300 }, 'Tank'],
  ['a support class is a support', { WIS: 300 }, 'Sage'],
  ['CON-topped stats make a tank even off-class', { CON: 400, STR: 100 }, 'Warrior'],
  ['STR-topped damage class is damage', { STR: 400, DEX: 100 }, 'Warrior'],
  ['INT-topped damage class is damage', { INT: 400, WIS: 100 }, 'Wizard'],
]
for (const [name, s, cls] of MANA_ROLE) {
  CASES.push({
    name, axis: 'manaRoleOf', input: { stats: stats(s), className: cls },
    expect: manaRoleOf(mon(s, cls)),
  })
}

// ── the free attack ──────────────────────────────────────────────────────────
// ⚠️ AUTHORED PER CLASS, NEVER DERIVED FROM THE LOADOUT. Every attempt to infer it produced a
// monster fighting at the wrong range: by POWER a ranged monster got a melee basic it could
// never reach with; by REACH a Warrior that drafted one Piercing Shot became a ranged unit
// standing off at 6.4. DEX is why no formula replaces the table — Rogue is a knife, Ranger is
// a bow, and the stat pair cannot tell them apart.
const BASIC: [string, Partial<Stats>][] = [
  ['basic for a STR/CON build', { STR: 359, CON: 200 }],
  ['basic for a DEX/STR build', { DEX: 359, STR: 200 }],
  ['basic for an INT/WIS build', { INT: 359, WIS: 200 }],
  ['basic for a CHA/WIS build', { CHA: 359, WIS: 200 }],
  ['basic for a CON/STR build', { CON: 359, STR: 200 }],
  ['basic at zero stats takes the flat floor', {}],
  ['basic scales with the class stat, not the highest stat', { INT: 900, WIS: 500 }],
]
for (const [name, s] of BASIC) {
  const b = basicAttackFor(mon(s))
  CASES.push({
    name, axis: 'basicAttackFor', input: { stats: stats(s) },
    // ⚠️ POWER, CHANNEL, STAT, RANGE AND COOLDOWN ARE THE FIVE THAT MATTER. The cooldown is
    // 0.715 and is a FOURTH authored cooldown in a fourth place — inline in `basicAttackFor`,
    // not in any of the three pool files. It was already in seconds while still being fed
    // through `* COOLDOWN_MULT`; retiring that multiplier without scaling this made the
    // single highest-frequency action in the game 30% faster and moved three goldens by up to
    // 5.4s. It read as a balance change and was a missed conversion.
    expect: {
      channel: b.channel, stat: b.stat, power: b.power,
      range: b.range, cooldown: b.cooldown, accuracy: b.accuracy, castTime: b.castTime,
    },
  })
}

export const CLASSIFY_CASES = CASES

export function buildClassifyContract() {
  return {
    schema: 1,
    subject: 'core.ts:classForStats/roleOfClass + decide.ts:manaRoleOf + engine.ts:basicAttackFor',
    note: 'What a monster IS — emergent class, composition role, mana role, and the authored '
      + 'free attack. Pure stat comparison and table lookup, no geometry. Regenerate with '
      + '`npx tsx tools/exportport.ts`.',
    cases: CASES,
  }
}
