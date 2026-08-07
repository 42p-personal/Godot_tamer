// THE FREE ATTACK must stay a filler — it may never out-damage a real ability.
// This is an invariant, not a preference: when the basic out-DPSed every
// monster's best ability (1.2–2.3× at train 850), abilities were strictly worse
// than swinging and the ~1s swing dominated the whole action economy.
import { describe, it, expect } from 'vitest'
import { generateMonster } from '../monster'
import { basicAttackFor, fieldLoadout } from './engine'
import { CHANNEL_CAST_TIME, BASIC_STAT_TIER, CLASS_BASIC } from './types'
import { reachOf } from './decide'
import { CLASSES, Monster, Move } from '../core'

const effCd = (mv: Move) => mv.cooldown * 0.9 + (mv.castTime ?? CHANNEL_CAST_TIME[mv.channel])
const dpsOf = (mv: Move) => mv.power / effCd(mv)

const SPECIES = ['kongrath', 'aegisox', 'grivvel', 'maneleo', 'ursath']

describe('tamerengine — the free attack is a filler', () => {
  it('never out-DPSes the monster\'s best damaging ability', () => {
    for (const sp of SPECIES) {
      // ⚠️ WIDE sample: an earlier 2-seed version passed while a real monster
      // (ursath at train 850) still had a basic at 104% of its best ability.
      for (const train of [200, 400, 650, 850, 1000]) {
       for (const tag of ['', 'x', 'y', '850']) {
        const m = generateMonster(`${tag}${sp}${train}`, { speciesId: sp, train }) as Monster
        // ⚠️ THE KIT MUST BE THE FIELD'S KIT. This read `m.loadout` — the TURN
        // engine's 3 moves — while testing the FIELD's free attack, and the
        // field tops every monster up to FIELD_LOADOUT_SIZE (4). So it judged a
        // field invariant against a kit the field never fields, and flagged a
        // monster for holding one damage move when on the field it holds two.
        // A fixture must pin the variable under test.
        const abilities = fieldLoadout(m).filter((mv) => mv.type === 'damage')
        if (!abilities.length) continue // empty loadout — nothing to compare against
        const basic = basicAttackFor(m)

        // ⚠️ PER CAST is the real invariant. The question the free attack must
        // never answer "yes" to is "would I rather swing than cast this?" — and
        // in a rotation that is a per-CAST comparison, because the basic is
        // still there to fill the cooldown afterwards. An ability that hits for
        // 29 every 4s beats a 17 swing every 1.9s AT THE MOMENT IT IS UP, even
        // though its spam-DPS is lower.
        const bestPower = Math.max(...abilities.map((mv) => mv.power))
        expect(basic.power).toBeLessThan(bestPower)

        // ⚠️ AND the basic must not dominate by VOLUME either — the original bug
        // this file was written for. But the comparison is against the whole
        // KIT, not the single best move: a monster rotates through everything it
        // has and swings only in the gaps, so summing the abilities' throughput
        // is the honest model of what it does instead of swinging.
        // The old form compared the basic's spam-DPS against ONE ability's
        // spam-DPS, which is the same `power / cooldown` assumption that filled
        // every loadout with tutorial moves (see monster.ts:expectedOutput). It
        // failed the moment the draft stopped optimising for it — flagging a
        // maneleo whose one damage move was Bonebreaker, a cd-4 wall-breaker
        // that is plainly worth casting.
        const kitDps = abilities.reduce((n, mv) => n + dpsOf(mv), 0)
        expect(dpsOf(basic)).toBeLessThan(kitDps)
       }
      }
    }
  })

  it('is tiered by stat — a STR swing beats a WIS jab', () => {
    expect(BASIC_STAT_TIER.STR).toBeGreaterThan(BASIC_STAT_TIER.DEX)
    expect(BASIC_STAT_TIER.DEX).toBeGreaterThan(BASIC_STAT_TIER.INT)
    expect(BASIC_STAT_TIER.INT).toBeGreaterThan(BASIC_STAT_TIER.CON)
    expect(BASIC_STAT_TIER.CON).toBeGreaterThan(BASIC_STAT_TIER.CHA)
    expect(BASIC_STAT_TIER.CHA).toBeGreaterThan(BASIC_STAT_TIER.WIS)
  })

  it('⚠️ reaches from where the unit actually stands, for every class', () => {
    // ⚠️ THE CONTRACT INVERTED, AND THAT IS THE POINT. This used to assert the
    // basic stretched to cover the LONGEST move in the kit — which is how a
    // Warrior that drafted one Piercing Shot ended up with a ranged free attack
    // and fought at 6.4. The free attack is now authored per class
    // (CLASS_BASIC) and `reachOf` closes to meet it instead.
    //
    // Asserted against the real `reachOf`, not a copy of its arithmetic: the
    // previous version recomputed the standoff as `max(kit) * 0.75` and so could
    // only ever agree with itself.
    for (const sp of SPECIES) {
      for (const train of [200, 500, 850, 1000]) {
        const m = generateMonster(`br-${sp}-${train}`, { speciesId: sp, train }) as Monster
        const withField = { ...m, loadout: fieldLoadout(m) }
        if (!withField.loadout.some((mv) => mv.type === 'damage')) continue
        const stand = reachOf({ m: withField } as never)
        const ba = basicAttackFor(m)
        expect(ba.range ?? 0).toBeGreaterThanOrEqual(stand - 0.01)
      }
    }
  })

  it('⚠️ scales off the class PRIMARY stat, not the channel default', () => {
    // The second inference in the same function: the stat was read off the
    // channel (melee⇒STR), so a Rogue's knife scaled on STR and a Spellsword's
    // enchanted blade ignored INT entirely.
    expect(CLASS_BASIC.Rogue.channel).toBe('melee')
    expect(CLASS_BASIC.Rogue.stat).toBe('DEX')
    expect(CLASS_BASIC.Spellsword.stat).toBe('INT')
    // And DEX is why no formula can replace the table: the same stat is both
    // the knife and the bow.
    expect(CLASS_BASIC.Ranger.channel).toBe('ranged')
    expect(CLASS_BASIC.Ranger.stat).toBe('DEX')
  })

  it('every class has an authored basic', () => {
    for (const c of CLASSES) expect(CLASS_BASIC[c.name]).toBeDefined()
    expect(CLASS_BASIC.Generalist).toBeDefined()
  })
})
