// ⚠️ CAN THE POOL BE REACHED AT THE TRAINING LEVEL WE BALANCE AT?
//
// An ability can be authored, priced, lined, range-checked and validate-clean and
// still not exist, because one number put it above what anyone reaches. That is
// how `Mending Surge` (learnLevel 400) and `Second Wind` (480) shipped drafted by
// 1 monster in 320: WIS-primary monsters measure median 281 / p90 355, so the
// gate sat above the ceiling. Repricing to 300/340 took them to 10/320.
//
// ⚠️ `train` IS A BUDGET, NOT A STAT. Across all 65 species the highest single
// stat is 455 at train 850, 482 at 1000, 706 at 1500, 904 at 2000. So a lv920
// capstone is NOT unreachable in the game — it is unreachable to a mid-game
// monster, which is the intended shape of a capstone.
//
// What this pins is therefore an INSTRUMENT fact, not a content bug: `sweep40`
// and `ab.ts` run at train 850, so a large part of the pool cannot appear in any
// balance measurement made today. That is worth knowing every time a sweep number
// is quoted, and worth failing on if it silently grows.
import { describe, it, expect } from 'vitest'
import { generateMonster } from './monster'
import { SPECIES } from './species'
import { ALL_MOVES } from './moves'
import { CLASS_LINES, LINE_OF } from './lines'
import { classForStats, Stat } from './core'

/** The two tiers the balance harnesses run at — see tools/comps.ts. */
const SWEEP_TRAIN = 850
const ELITE_TRAIN = 3200

function unreachableAt(train = SWEEP_TRAIN): string[] {
  const sample = SPECIES.map((sp) => {
    const m = generateMonster(`reach-${sp.id}-${train}`, { speciesId: sp.id, train }) as never as
      { stats: Record<string, number> }
    return { cls: classForStats(m.stats as never), stats: m.stats }
  })
  const out: string[] = []
  for (const mv of ALL_MOVES) {
    const line = LINE_OF[mv.name]
    if (!line) continue // the lineless guard in validate.ts owns this case
    const classes = Object.entries(CLASS_LINES)
      .filter(([, ls]) => (ls as string[]).includes(line)).map(([c]) => c)
    const pool = sample.filter((s) => classes.includes(s.cls))
    if (!pool.length) continue
    if (!pool.some((s) => (s.stats[mv.stat as Stat] ?? 0) >= mv.learnLevel)) out.push(mv.name)
  }
  return out
}

describe('pool reachability at the training level we balance at', () => {
  it('⚠️ records how much of the pool the sweep cannot see', () => {
    const unreachable = unreachableAt()
    // ⚠️ A TRIPWIRE, NOT A TARGET. This is not "59 bugs" — most are capstones
    // doing their job. It fails if the number MOVES, so that adding an ability
    // nobody can draft is a decision someone made on purpose rather than an
    // accident nobody noticed. Update it deliberately, and say which way.
    // 68 -> 67: Standing Ovation lv540 -> 380, so the CHA team regen is now
    // reachable and its buff can actually land. Down is the good direction.
    // 67 -> 64: Enfeeble 380->330, Lullaby 430->385, Crowd Surge 440->320,
    // Mana Leech 380->335. ⚠️ Found by `tools/effects.ts`, not by this test — the
    // count was already falling and said nothing about WHICH moves, let alone
    // that eight EFFECTS were never cast at all. A count is a tripwire; the
    // effect audit is the diagnosis.
    expect(unreachable.length, `unreachable at train ${SWEEP_TRAIN}:\n  ${unreachable.join('\n  ')}`)
      .toBe(64)
  })

  it('⚠️ and ELITE training unlocks essentially all of it', () => {
    // ⚠️ THE PAIR IS THE POINT. 67 unreachable at mid-game is PROGRESSION, not a
    // bug list — league caps run to 1200 (Tamer Elite) and 1400 (Apex), so a
    // lv920 capstone is MEANT to be a late unlock. The real defect would be a
    // move nobody can reach even at the top. This test says which is which.
    //
    // It is also why `--elite` exists on sweep40/ab: with one tier the harness
    // simulated a top stat of ~455, an Iron/Silver monster, so every capstone was
    // invisible to every balance number this project produced. Late content was
    // authored blind, and the 67 read as a bug list when most of it was working.
    const stranded = unreachableAt(ELITE_TRAIN)
    expect(stranded.length, `unreachable even at train ${ELITE_TRAIN}: ${stranded.join(', ')}`)
      .toBeLessThanOrEqual(4)
  })

  it('⚠️ every support STAT can reach a restore before its capstone', () => {
    // ⚠️ NOT "every restore is reachable" — that was the first version and it
    // flagged `Ward Against Ruin` (lv650), which calls itself "The Mender
    // capstone". A capstone being late is the point of a capstone.
    //
    // ⚠️ NOR per LINE — the second version required every line CONTAINING a
    // restore to have a reachable one, and flagged `Siphon`, whose single restore
    // is Providence (lv850). Siphon is the drain line; carrying one incidental
    // late heal is not a defect.
    //
    // Per STAT is the contract that actually exists: "CHA empowers · CON protects
    // · WIS restores". A support stat that cannot reach ANY restore at the level
    // we balance at cannot do its job. It caught `Tranquility` (lv430) on its
    // first run — a mid-line Mender heal, no capstone, that nobody could learn —
    // the same defect as the two new heals, already in the pool.
    const unreachable = new Set(unreachableAt())
    const restores = ALL_MOVES.filter((m) =>
      (m.target === 'ally' || m.target === 'team') && (m.power > 0 || m.effects?.hpRegenBuff))
    const byStat = new Map<string, typeof restores>()
    for (const r of restores) byStat.set(r.stat, [...(byStat.get(r.stat) ?? []), r])
    for (const stat of ['WIS', 'CHA', 'CON']) {
      const moves = byStat.get(stat) ?? []
      expect(moves.length, `${stat} authors no restore at all`).toBeGreaterThan(0)
      const reachable = moves.filter((m) => !unreachable.has(m.name))
      expect(reachable.length, `${stat} has no restore reachable at train ${SWEEP_TRAIN}: `
        + moves.map((m) => `${m.name} lv${m.learnLevel}`).join(', ')).toBeGreaterThan(0)
    }
  })
})
