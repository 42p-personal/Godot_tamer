// THE BALANCE SWEEPER — is every move's TOTAL value in line with what it costs?
//
// ⚠️ WHY A STATIC AUDIT AT ALL, when the sim exists. The sim answers SCALE: are
// fights the right length, is mitigation holding, does the cascade run away. It
// cannot answer CONSISTENCY, because a pool where every value is 2x too big
// produces a perfectly self-consistent sim that is simply fast. This tool answers
// the other half: given the pool's own internal references, is this move priced
// like its neighbours. Neither question substitutes for the other.
//
// ⚠️ AND IT CANNOT TELL YOU IF A NUMBER IS ABSOLUTELY RIGHT. There is no external
// truth here. Double every power in the pool and this reports zero problems. Four
// references are available, in descending order of how much they can be trusted:
//   1. the free attack (CLASS_BASIC) — closest to absolute, because it is free
//   2. same line, lower level — progression must rise; mitigation cancels exactly
//   3. same stat, same level band — a cohort median: a flag, never a verdict
//   4. the stat's DESIGNED tier — STR 42.6 · DEX 38.2 · INT 35.2 · CON 28.0 ·
//      CHA 26.8 · WIS 22.8. ⚠️ Measured against the move's OWN stat, never a
//      global mean: that asymmetry is the design, and a global mean would flag
//      all of WIS as broken and all of STR as overtuned.
//
// ⚠️ MITIGATION IS NOT MODELLED, ON PURPOSE. `strike()` computes
// `raw * (1 - mitFrac)` where mitFrac comes from the DEFENDER's CON (melee/ranged)
// or WIS (magic/voice/support). For same-channel comparisons that term is
// identical on both sides and CANCELS EXACTLY — comparing Titanfall to Scrap needs
// no mitigation model, it is algebra. Cross-channel it does not cancel, and there
// is no single right defender to assume: mitigation runs 12% on a caster (CON 150)
// to 67% on a wall (CON 1000). So cross-channel comparisons are never made.
// "Is mitigation strong enough" is a SIM question — see tools/ehp.ts, sweep40.ts.
//
// Usage: npx tsx tools/pool.ts [--stat STR] [--elite]
import { ALL_MOVES } from '../src/moves'
import { LINE_OF } from '../src/lines'
import { statScaleOf, aoeFalloff, HARD_CONTROL_STATUSES } from '../src/core'
import { CHANNEL_CAST_TIME, CHANNEL_RANGE, CLASS_BASIC, BASIC_BASE_POWER,
  BASIC_STAT_SCALE, BASIC_STAT_TIER } from '../src/tamerengine/types'
import * as fs from 'fs'
import { spatialOf } from '../src/tamerengine/spatial'
import type { Move, Stat, StatusKind } from '../src/core'

// ── The reference stat ───────────────────────────────────────────────────────
// ⚠️ EACH MOVE IS JUDGED AT ITS OWN LEARN LEVEL, not at one global stat. A
// capstone priced for an invested monster looks broken at mid and fine at elite;
// judging it anywhere but where it unlocks measures the harness, not the move.
const REF = (m: Move) => Math.max(120, m.learnLevel)

// ── What a keyword is worth ─────────────────────────────────────────────────
/**
 * ⚠️ VALUES ARE % OF THE MOVE'S OWN DAMAGE, not flat numbers — a rider on a
 * capstone is worth more than the same rider on a starter, and a flat table would
 * quietly overprice every cheap move in the game.
 *
 * ⚠️ THIS TABLE IS AN OPINION AND IS MEANT TO BE ARGUED WITH. It is the prior, not
 * the truth. Where the pool prices a keyword consistently across near-identical
 * moves, the pool's own implied price is better evidence — `--pairs` prints those.
 */
const EFFECT_VALUE: Record<string, { pct: number; why: string }> = {
  // Conditionals — discounted by how often the condition ACTUALLY holds.
  // ⚠️ bonusVsStatus connects 33% of casts (tools/combo.ts), so a x1.5 detonate is
  // worth ~1.17x in expectation. Pricing a conditional at its ceiling is how a move
  // gets overcharged for something that rarely happens.
  bonusVsStatus: { pct: 0.18, why: 'x1.5-2.6 but connects only 33% of casts' },
  execute: { pct: 0.15, why: 'only on a target already dying' },
  firstStrikeMult: { pct: 0.10, why: 'opener only — worthless after the first trade' },
  hpScale: { pct: 0.05, why: 'a wash: better at one end of the HP bar, worse at the other' },
  consumeWard: { pct: 0.06, why: 'needs the target to be holding a shield' },
  maxHpDmg: { pct: 0.20, why: 'ignores the defender curve — scales into walls' },
  pierce: { pct: 0.22, why: 'cuts the mitigation term the whole pool is divided by' },
  // Sustain and economy.
  lifesteal: { pct: 0.25, why: 'damage AND survivability from one slot' },
  manaBurn: { pct: 0.12, why: 'denies casts, but only against a caster' },
  recoil: { pct: -0.18, why: 'NEGATIVE — self-damage is a real cost, capped at 15%' },
  // Protection and support riders.
  guard: { pct: 0.20, why: 'flat DR until its next action' },
  ward: { pct: 0.25, why: 'absorb soaks before HP — the strongest defensive rider' },
  thorns: { pct: 0.12, why: 'reflect scales with how much it is attacked' },
  cleanse: { pct: 0.18, why: 'the only answer to a stacked status board' },
  // ⚠️ NOT A FLAT PERCENTAGE — see `regenOutput`. Left here only so the keyword is
  // NAMED in the printout; its value is computed from the actual HP it restores.
  hpRegenBuff: { pct: 0, why: 'healing over time — valued as real HP, see regenOutput' },
  regenBuff: { pct: 0.10, why: 'mana regen — buys casts, not survival' },
  tauntForce: { pct: 0.20, why: 'takes the enemy target choice away' },
  // Numeric buffs/debuffs — worth roughly their magnitude, per round.
  atkBuff: { pct: 0.20, why: 'team damage uplift' },
  defBuff: { pct: 0.15, why: 'mitigation uplift' },
  accBuff: { pct: 0.10, why: 'accuracy uplift' },
  dodgeBuff: { pct: 0.12, why: 'evasion uplift' },
  atkDebuff: { pct: 0.18, why: 'cuts enemy output' },
  defDebuff: { pct: 0.16, why: 'multiplies the whole TEAM damage into that target' },
  accDebuff: { pct: 0.10, why: 'makes them miss' },
  spreadStatus: { pct: 0.14, why: 'contagion — real (engine.ts:1786), punishes clumping' },
}

/**
 * ⚠️ A STATUS IS PRICED BY CHANCE x DURATION x KIND, never by presence.
 * Piercing Shot (poison 45%/3) and Toxin Stack (poison 70%/4) both read as "poison"
 * and one is worth twice the other — 1.35 expected poison-rounds against 2.80. A
 * presence check would have called that pair identical and missed the whole trade.
 */
const STATUS_VALUE: Partial<Record<StatusKind, number>> = {
  stun: 0.16, sleep: 0.15, charm: 0.20, confusion: 0.12, fear: 0.11,
  silence: 0.10, knockback: 0.07,
  poison: 0.05, burn: 0.05, bleed: 0.05,
  vulnerable: 0.07, doom: 0.06, healblock: 0.06, blind: 0.06,
  slow: 0.05, haste: 0.06,
}
/** Per expected round of the status, capped so a long weak DoT cannot run away. */
const statusValue = (m: Move): number => {
  if (!m.status) return 0
  const per = STATUS_VALUE[m.status.kind] ?? 0.05
  const rounds = (m.status.chance / 100) * (m.status.duration ?? 1)
  const hardBonus = HARD_CONTROL_STATUSES.has(m.status.kind) ? 1.5 : 1
  return Math.min(0.55, per * rounds * hardBonus)
}

const SPATIAL_VALUE: Record<string, number> = {
  move: 0.10, push: 0.06, pull: 0.08, root: 0.10, slow: 0.06,
  zone: 0.14, fade: 0.12, backstab: 0.08,
}

// ── Value ────────────────────────────────────────────────────────────────────
const castOf = (m: Move) => m.castTime ?? CHANNEL_CAST_TIME[m.channel]
const expectedHits = (m: Move) => m.effects?.hits ? (m.effects.hits[0] + m.effects.hits[1]) / 2 : 1
const isAoe = (m: Move) => !!spatialOf(m.name)?.area || m.target === 'allEnemies'
  || m.target === 'team'
/**
 * ⚠️ AoE is judged at THREE bodies, never one — CLAUDE.md's standing rule.
 *
 * ⚠️ AND `target: 'team'` COUNTS. It did not, and that is the SAME double-standard
 * that once flagged six AoE damage moves as hot: an enemy AoE was credited at three
 * bodies while a team buff covering the identical three was credited at one. It cost
 * `Ward Against Ruin` a DOMINATED flag against a single-target heal — a lv650 team
 * ward "beaten" by a lv300 burst heal that reaches one body.
 *
 * ⚠️ Team buffs take the same `aoeFalloff` as enemy AoE, which is a modelling
 * CHOICE, not a law: a heal spread over three allies is not obviously subject to the
 * same diminishing return as damage spread over three enemies. It is used here so
 * both sides of the pool are judged by one rule; if that ever looks wrong, change it
 * deliberately and say so, do not leave the two halves on different rules again.
 */
const aoeMult = (m: Move) => (isAoe(m) ? 3 * aoeFalloff(3) : 1)

/**
 * HP a regen rider actually restores over its duration, in the same units as power.
 *
 * ⚠️ IT WAS PRICED AS A FLAT +15% RIDER AND THAT IS NOT CLOSE. `Renewal` is power 11
 * with `hpRegenBuff: 10` over 4 rounds — 40 HP of regen against 11 of burst, so the
 * rider is worth 3.6x the move, not 0.15x. Undercounted that far it read as a lv260
 * heal losing to the lv40 `Mend`, and the honest fix for that flag was the tool.
 */
const regenOutput = (m: Move) => (m.effects?.hpRegenBuff ?? 0) * (m.effects?.duration ?? 1)

/** Raw damage per second, before any rider. Mitigation cancels — see the header. */
function damagePerSec(m: Move): number {
  if (m.power <= 0) return 0
  const scaled = (m.power + regenOutput(m)) * (1 + REF(m) * statScaleOf(m))
    * expectedHits(m) * aoeMult(m)
  return scaled * (m.accuracy / 100) / (m.cooldown + castOf(m))
}

/** The uplift every rider on this move is worth, as a fraction of its damage. */
function keywordUplift(m: Move): { total: number; parts: string[] } {
  const parts: string[] = []
  let total = statusValue(m)
  if (total > 0) parts.push(`${m.status!.kind} +${(total * 100).toFixed(0)}%`)
  const fx = (m.effects ?? {}) as Record<string, unknown>
  for (const k of Object.keys(fx)) {
    // ⚠️ `hits` and AoE are ALREADY in damagePerSec (expected hits, 3-body falloff).
    // Counting them again here is the double-count that would make every multi-hit
    // move look overtuned — and multi-hit is 11 moves.
    if (k === 'hits' || k === 'duration') continue
    const e = EFFECT_VALUE[k]
    if (!e) continue
    total += e.pct
    parts.push(`${k} ${e.pct >= 0 ? '+' : ''}${(e.pct * 100).toFixed(0)}%`)
  }
  const sp = spatialOf(m.name) as unknown as Record<string, unknown> | undefined
  if (sp) for (const k of Object.keys(SPATIAL_VALUE)) {
    if (!sp[k]) continue
    total += SPATIAL_VALUE[k]
    parts.push(`${k} +${(SPATIAL_VALUE[k] * 100).toFixed(0)}%`)
  }
  if (isAoe(m)) parts.push('AoE (in dmg)')
  return { total, parts }
}

/** What the move is worth ALL IN — damage plus everything it carries. */
const totalValue = (m: Move) => damagePerSec(m) * (1 + keywordUplift(m).total)

/** The class free attack's damage per second at this move's reference stat. */
function basicDps(m: Move): number {
  const spec = Object.values(CLASS_BASIC).find((b) => b.stat === m.stat) ?? CLASS_BASIC.Generalist
  const power = BASIC_BASE_POWER + REF(m) * BASIC_STAT_SCALE * (BASIC_STAT_TIER[spec.stat] ?? 0.5)
  return power * 0.9 / (0.715 + 0.15)
}

// ── Report ───────────────────────────────────────────────────────────────────
const STATS: Stat[] = ['STR', 'DEX', 'CON', 'WIS', 'INT', 'CHA']
const only = process.argv.includes('--stat') ? process.argv[process.argv.indexOf('--stat') + 1] : null
const med = (xs: number[]) => xs.length ? [...xs].sort((a, b) => a - b)[xs.length >> 1] : 0

/**
 * Same index convention as the printed `p25`/`p75` distribution below — the two
 * NEW checks (IQR-HIGH/LOW, PROGRESSION-RATIO; see docs/POOL_AUDIT.md) reuse it
 * so their fences are computed the identical way the tool already prints,
 * rather than a second quantile method quietly disagreeing with the first.
 */
const quantile = (sortedAsc: number[], p: number): number =>
  sortedAsc.length ? sortedAsc[Math.min(sortedAsc.length - 1, Math.floor(sortedAsc.length * p))] : 0
/** Tukey's fence: [Q1 - 1.5×IQR, Q3 + 1.5×IQR], the standard outlier bound —
 * scale-invariant per input array, so it works identically on WIS's low
 * absolute numbers and STR's high ones, and on ratios instead of raw values. */
function tukeyFence(values: number[]): { lo: number; hi: number; q1: number; q3: number; iqr: number } {
  const sorted = [...values].sort((a, b) => a - b)
  const q1 = quantile(sorted, 0.25)
  const q3 = quantile(sorted, 0.75)
  const iqr = q3 - q1
  return { lo: q1 - 1.5 * iqr, hi: q3 + 1.5 * iqr, q1, q3, iqr }
}

/**
 * ⚠️ DAMAGE AND RESTORES ARE SEPARATE COHORTS. `power > 0` catches heals too —
 * Mend, Tranquility, Mending Surge all carry power — and comparing a heal's output
 * to the free ATTACK is nonsense. The first run of this tool did exactly that.
 */
const dmg = ALL_MOVES.filter((m) => m.type === 'damage' && m.power > 0)
const restore = ALL_MOVES.filter((m) => m.type !== 'damage' && m.power > 0)

/**
 * The cohort a move is judged against: same stat, within LEVEL_BAND levels.
 *
 * ⚠️ A WHOLE-STAT MEDIAN IS USELESS AND THE FIRST VERSION USED ONE. Every move is
 * judged at its OWN learn level, so a lv920 capstone (high power AND high
 * statScale AND a high stat) dwarfs a lv40 starter by construction — STR's p75 came
 * out 4x its median. That spread is learn level, not balance, and flagging on it
 * would have condemned every early move in the game.
 */
/**
 * How much better a move must be before it counts as DOMINATING another.
 *
 * ⚠️ A TOOL CANNOT RESOLVE FINER THAN THE DATA IT READS. `power` is an authored
 * INTEGER — one step on a power-40 move is 2.5% — so a "dominated" verdict on a
 * 0.4% gap is a rounding artefact wearing a verdict's clothes. Without this,
 * `Gambler's Volley` (24.9 vs 25.0/s) and `Rend` (25.3 vs 25.5/s) were both
 * reported as broken and both "fixes" were a single point of power that would have
 * flipped the flag onto the other move. 5% is one authoring step with room to spare.
 */
const DOMINANCE_MARGIN = 1.05

const LEVEL_BAND = 200

/**
 * The DESIGNED damage tier per stat — CLAUDE.md's median effective DPS. Support is
 * not underpowered; it is paid in utility.
 *
 * ⚠️ THIS IS WHAT MAKES A CROSS-STAT COMPARISON LEGAL. Comparing a WIS move to an
 * STR move at the same level without it would flag all of WIS as broken and all of
 * STR as overtuned — which is the design working. Normalising by tier asks the
 * right question instead: is this move in line with its LEVEL, given what its stat
 * is supposed to be worth.
 */
const STAT_TIER: Record<string, number> = {
  STR: 42.6, DEX: 38.2, INT: 35.2, CON: 28.0, CHA: 26.8, WIS: 22.8,
}
const TIER_MEAN = Object.values(STAT_TIER).reduce((a, b) => a + b, 0) / 6

/**
 * The same-LEVEL cohort, across every stat, tier-normalised.
 *
 * ⚠️ Answers a different question from `cohort()`, and both are needed. `cohort`
 * asks "is this in line with its own stat's neighbours"; this asks "is a lv330 move
 * worth what a lv330 move should be worth". A move can pass one and fail the other,
 * and which it fails tells you whether the problem is the move or the line.
 */
function levelCohort(m: Move, pool: Move[]): number[] {
  return pool
    .filter((o) => Math.abs(o.learnLevel - m.learnLevel) <= LEVEL_BAND)
    // ⚠️ AoE IS COMPARED ONLY TO AoE. Damage is judged at THREE bodies (x2.70) per
    // the standing rule, so measuring an AoE move against a mostly single-target
    // cohort double-counts its area and condemns it for being area. The first run
    // flagged SIX moves HOT-FOR-LEVEL and every single one was AoE — Ricochet,
    // Frost Nova, Static Chain, Arcane Bomb, Inferno, World Ender. Six moves
    // failing one check together is the check being wrong, not the pool.
    .filter((o) => isAoe(o) === isAoe(m))
    .map((o) => totalValue(o) * (TIER_MEAN / (STAT_TIER[o.stat] ?? TIER_MEAN)))
}
function cohort(m: Move, pool: Move[]): Move[] {
  const same = pool.filter((o) => o.stat === m.stat)
  const near = same.filter((o) => Math.abs(o.learnLevel - m.learnLevel) <= LEVEL_BAND
    && isAoe(o) === isAoe(m))   // ⚠️ like-for-like on area — see levelCohort
  if (near.length >= 4) return near
  // Too thin a band — take the nearest 5 by level rather than inventing a verdict.
  return [...same].sort((a, b) =>
    Math.abs(a.learnLevel - m.learnLevel) - Math.abs(b.learnLevel - m.learnLevel)).slice(0, 5)
}

interface Flag { move: Move; kind: string; detail: string; advice: string }
const flags: Flag[] = []

for (const st of STATS) {
  if (only && st !== only) continue
  const ms = dmg.filter((m) => m.stat === st)
  // ⚠️ NEW — Tukey fence over THIS STAT'S OWN totalValue distribution. Every
  // check above is local (same line, same ±200-level band); none of them can
  // see a move that towers over EVERY move near it, because a run of locally-
  // reasonable comparisons is exactly how a 31x whole-stat spread hides — see
  // docs/POOL_AUDIT.md §2. `Q3 + 1.5×IQR` is computed PER STAT (never pooled
  // across stats) so WIS's low absolute numbers and STR's high ones each get
  // their own fence, per the file's own standing rule that a global comparison
  // would flag all of WIS as broken and all of STR as overtuned.
  const statFence = tukeyFence(ms.map(totalValue))

  for (const m of ms) {
    const v = totalValue(m), d = damagePerSec(m), up = keywordUplift(m)
    const basic = basicDps(m)

    // 1. FLOOR — below the free attack even with every rider credited.
    if (v < basic) flags.push({ move: m, kind: 'FLOOR', detail: `value ${v.toFixed(1)}/s < free attack ${basic.toFixed(1)}/s`,
      advice: `raise power to ~${Math.ceil(m.power * (basic / v))}` })

    // 2. DOMINATED — a same-line move at an EQUAL OR LOWER level that is better on
    // value AND cheaper in mana. ⚠️ Same line means same channel, so mitigation
    // cancels and this comparison is exact.
    // ⚠️ BETTER ON BOTH RATES, not on raw mana — a move that costs MORE mana can
    // still be un-dominated if it is more EFFICIENT per mana, and that is a real
    // design trade (burst vs economy), not a defect the check should paper over.
    // ⚠️ TRANQUILITY/MENDING SURGE WAS THE WORKED EXAMPLE HERE, AND IT NO LONGER
    // HOLDS. It described an EARLIER Tranquility (lv430, power ~32 — see
    // docs/BALANCING.md "caught by the new guard", docs/SIGNATURE_DESIGN.md "heals
    // 32"); at current values (lv320, power 74) neither rate clears
    // DOMINANCE_MARGIN — 27.7 vs 26.4/s is 4.8%, just UNDER the 5% floor, and
    // Tranquility is actually the MORE mana-efficient of the two (1.02 vs 0.81
    // value/MP) — so it is correctly left unflagged as a legitimate burst-vs-
    // economy pair, not a stale miss. Full arithmetic in docs/POOL_AUDIT.md §4.
    const perMana = (x: Move) => totalValue(x) / Math.max(1, x.mana ?? 10)
    // ⚠️ `isAoe(o) === isAoe(m)` — the FOURTH place this double-standard turned up,
    // after the OVERBUDGET cohort, the restore cohort and the PROGRESSION ladder. An
    // `allEnemies` move is credited at three bodies by the standing rule, so it
    // "dominates" every single-target move in its line by construction. Unsplit, this
    // condemned `Mana Leech` for losing to `Static Chain` — a comparison between a
    // sniper and a chain lightning that no repricing could ever satisfy.
    const better = ms.filter((o) => o !== m && LINE_OF[o.name] === LINE_OF[m.name]
      && isAoe(o) === isAoe(m) && o.learnLevel <= m.learnLevel
      && totalValue(o) > v * DOMINANCE_MARGIN && perMana(o) > perMana(m) * DOMINANCE_MARGIN)
    if (better.length) {
      const b = better.sort((x, y) => totalValue(y) - totalValue(x))[0]
      // ⚠️ WHICH ONE IS WRONG DEPENDS ON WHICH IS EARLIER. If a much EARLIER move is
      // the dominator, raising the later one inflates the whole line and the early
      // move stays an outlier everything else has to clear. Cut the outlier instead.
      const gap = m.learnLevel - b.learnLevel
      const advice = gap >= 90
        ? `⚠️ lv${b.learnLevel} ${b.name} is ${gap} levels EARLIER — cut ITS power `
          + `${b.power} -> ~${Math.floor(b.power * v / totalValue(b))} rather than inflating this line`
        : `raise power ${m.power} -> ~${Math.ceil(m.power * (totalValue(b) / v) * 1.1)}, `
          + `or cut mana ${m.mana} -> ~${Math.floor((m.mana ?? 10) * perMana(m) / perMana(b))}`
      flags.push({ move: m, kind: 'DOMINATED', detail: `lv${b.learnLevel} ${b.name} beats it on BOTH rates `
        + `(${totalValue(b).toFixed(1)} vs ${v.toFixed(1)}/s; ${perMana(b).toFixed(2)} vs ${perMana(m).toFixed(2)} per MP)`,
        advice })
    }

    // 3. OVERBUDGET — carries far more total value than its stat's cohort.
    // ⚠️ ADVISES CUTTING DAMAGE, NEVER THE KEYWORD. Riders are the move's identity;
    // power, mana and cooldown are the dials.
    const bandMed = med(cohort(m, dmg).map(totalValue))
    const ratio = bandMed > 0 ? v / bandMed : 1
    // The same-LEVEL, all-stat view — tier-normalised so the designed asymmetry
    // between STR and WIS is not mistaken for a fault.
    const lvlMed = med(levelCohort(m, dmg))
    const myNorm = v * (TIER_MEAN / (STAT_TIER[m.stat] ?? TIER_MEAN))
    const lvlRatio = lvlMed > 0 ? myNorm / lvlMed : 1
    if (lvlRatio > 1.7) flags.push({ move: m, kind: 'HOT-FOR-LEVEL',
      detail: `${lvlRatio.toFixed(2)}x what a lv${m.learnLevel}±${LEVEL_BAND} move is worth across ALL stats `
        + `(tier-normalised ${myNorm.toFixed(1)} vs ${lvlMed.toFixed(1)}/s)`,
      advice: `KEEP the riders — cut power ${m.power} -> ~${Math.floor(m.power / lvlRatio * 1.3)}` })
    if (ratio > 1.6 && up.total > 0.25) {
      const target = Math.floor(m.power / ratio * 1.25)
      flags.push({ move: m, kind: 'OVERBUDGET', detail: `${ratio.toFixed(2)}x its lv${m.learnLevel}±${LEVEL_BAND} ${st} cohort `
        + `(${v.toFixed(1)} vs ${bandMed.toFixed(1)}/s); riders alone +${(up.total * 100).toFixed(0)}%`,
        advice: `KEEP the riders — cut power ${m.power} -> ~${target}, `
          + `or mana ${m.mana} -> ~${Math.ceil((m.mana ?? 10) * ratio)}, or cd ${m.cooldown} -> ${(m.cooldown * ratio).toFixed(1)}s` })
    }

    // 5. IQR-HIGH / IQR-LOW — a Tukey outlier against the WHOLE of this move's
    // own stat, not a ±200-level slice of it. ⚠️ THIS IS THE CHECK THAT ANSWERS
    // THE 31x QUESTION. OVERBUDGET and HOT-FOR-LEVEL both stop at a level band,
    // so a line that ramps 12x from lv120 to lv850 can pass every LOCAL check
    // along the way — each adjacent comparison is fine, and the whole-stat
    // spread is invisible until something looks at the stat's own quartiles.
    // The fence is derived from the stat's OWN p25/p75 (`statFence` above, once
    // per stat), never a hand-picked multiple — doubling the whole pool moves
    // Q1/Q3 together and the fence moves with them, so this cannot be defeated
    // by the same trick that makes every other absolute threshold a lie here.
    if (statFence.iqr > 0 && v > statFence.hi) flags.push({ move: m, kind: 'IQR-HIGH',
      detail: `${v.toFixed(1)}/s clears the ${st} Tukey fence (Q3 ${statFence.q3.toFixed(1)} + 1.5×IQR `
        + `${statFence.iqr.toFixed(1)} = ${statFence.hi.toFixed(1)}) — a QUESTION for the whole line/level this sits at, not just its neighbours`,
      advice: `cut power ${m.power} -> ~${Math.max(1, Math.floor(m.power * statFence.hi / v))}, `
        + `or check whether the rest of ${LINE_OF[m.name] ?? 'its line'} needs to come up to meet it instead` })
    if (statFence.iqr > 0 && v > 0 && v < statFence.lo) flags.push({ move: m, kind: 'IQR-LOW',
      detail: `${v.toFixed(1)}/s falls below the ${st} Tukey fence (Q1 ${statFence.q1.toFixed(1)} - 1.5×IQR `
        + `${statFence.iqr.toFixed(1)} = ${Math.max(0, statFence.lo).toFixed(1)})`,
      advice: `raise power ${m.power} -> ~${Math.ceil(m.power * statFence.lo / Math.max(0.01, v))}, `
        + `or check whether this move is priced for a job (opener, conditional) the raw number does not show` })
  }

  // 4. PROGRESSION — within a line, does total value rise with learn level?
  //
  // ⚠️ SPLIT BY AoE, and this is the THIRD place the same double-standard turned up.
  // AoE is credited at three bodies by the standing rule, so an `allEnemies` move
  // out-scores every single-target move in its line by construction. Unsplit, this
  // check reported `Mana Leech` (lv335, single target, 32.7/s) as failing to progress
  // past `Static Chain` (lv330, allEnemies, 43.1/s) — and then CONTRADICTED itself by
  // flagging the same move as HOT-FOR-LEVEL. Two flags, opposite advice, one cause.
  // A line is a shared win condition, not a promise that its AoE and its single-target
  // options are interchangeable; they progress on separate ladders.
  for (const line of [...new Set(ms.map((m) => LINE_OF[m.name]))]) {
  for (const aoeSide of [true, false]) {
    const lm = ms.filter((m) => LINE_OF[m.name] === line && isAoe(m) === aoeSide)
      .sort((a, b) => a.learnLevel - b.learnLevel)
    for (let i = 1; i < lm.length; i++) {
      const prev = lm.slice(0, i).reduce((best, x) => totalValue(x) > totalValue(best) ? x : best, lm[0])
      if (totalValue(lm[i]) < totalValue(prev) * 0.9) {
        flags.push({ move: lm[i], kind: 'PROGRESSION',
          detail: `lv${lm[i].learnLevel} worth ${totalValue(lm[i]).toFixed(1)}/s but lv${prev.learnLevel} `
            + `${prev.name} is ${totalValue(prev).toFixed(1)}/s`,
          advice: `raise power to ~${Math.ceil(lm[i].power * (totalValue(prev) / totalValue(lm[i])) * 1.05)}` })
      }
    }
  }
  }
}

// ── 6. PROGRESSION-RATIO — does a LINE's whole dynamic range match the pool's
// own, not a hand-picked target? ─────────────────────────────────────────────
//
// ⚠️ WHY THIS EXISTS, docs/POOL_AUDIT.md §1-2. PROGRESSION (above) only asks "did
// value go up" (`< prev × 0.9` is the only failure) — it has nothing to say about
// HOW MUCH it goes up by, so a line that climbs 12.5x from starter to capstone
// passes it exactly as cleanly as one that climbs 2x, because every ADJACENT step
// was fine. `ABILITY_REWORK.md` states a design target directly ("progression ≈
// 2.5x first move -> capstone"), but this tool does not get to ASSERT 2.5 — that
// is exactly the class of hand-picked absolute the header warns about (double
// every power and a fixed constant reports zero problems just the same).
//
// So: measure max(totalValue)/min(totalValue) for EVERY (line x AoE-side) cohort
// that has enough moves to mean anything. The pool's own line-to-line spread
// decides what "too much spread" means — no designer's number required.
interface LineRatio { line: string; aoeSide: boolean; ratio: number; lo: Move; hi: Move }
const lineRatios: LineRatio[] = []
for (const line of [...new Set(Object.values(LINE_OF))]) {
  for (const aoeSide of [true, false]) {
    const cohort = dmg.filter((m) => LINE_OF[m.name] === line && isAoe(m) === aoeSide)
    if (cohort.length < 2) continue // ratio of one thing to itself is not a measurement
    const byValue = [...cohort].sort((a, b) => totalValue(a) - totalValue(b))
    const lo = byValue[0], hi = byValue[byValue.length - 1]
    if (totalValue(lo) <= 0) continue
    lineRatios.push({ line, aoeSide, ratio: totalValue(hi) / totalValue(lo), lo, hi })
  }
}
// ⚠️ NEEDS A REAL SAMPLE TO FENCE. Under ~4 cohorts any statistic over the ratio
// set is noise — this tool does not resolve finer than its data any more here
// than DOMINANCE_MARGIN lets it resolve a 0.4% power step elsewhere.
if (lineRatios.length >= 4) {
  const ratios = lineRatios.map((r) => r.ratio)
  const { hi: rHi, q1: rQ1, q3: rQ3, iqr: rIqr } = tukeyFence(ratios)
  const ratioMedian = med(ratios)
  // ⚠️ TUKEY-ON-RATIOS WAS TRIED FIRST, AND MEASURED TO SELF-DEFEAT — see
  // docs/POOL_AUDIT.md §3 for the arithmetic. The line-ratio set is not
  // bulk-plus-outliers, it is a near-continuous ramp from ~1.1x to ~12.5x, so
  // Q3+1.5×IQR lands ABOVE every ratio in the pool (hand-computed: fence ~15.6x
  // against a max of ~12.5x) and the check that would have caught Assassin
  // fires on NOTHING — the identical failure mode the per-stat IQR-HIGH check
  // hit on INT, one level up: a distribution wide enough to need flagging is
  // wide enough to inflate its own fence past its own worst offender.
  // Printed anyway, not deleted, because IT IS EVIDENCE: it shows the naive
  // self-referential answer and shows it failing, which is itself the finding.
  console.log(`\nPROGRESSION-RATIO diagnostic — Tukey-on-ratios: Q1 ${rQ1.toFixed(1)}x Q3 ${rQ3.toFixed(1)}x `
    + `IQR ${rIqr.toFixed(1)} -> fence ${rHi.toFixed(1)}x (${lineRatios.length} cohorts). `
    + `Pool median ratio ${ratioMedian.toFixed(1)}x.`)
  // ⚠️ THE CHECK THAT ACTUALLY BITES: flag a cohort running at MORE THAN DOUBLE
  // the pool's OWN median line-ratio. Still self-referential — the baseline
  // (`ratioMedian`) comes from the pool, not an asserted "2.5x" — but the "how
  // far above baseline counts as different" question needs SOME resolution
  // constant, same as DOMINANCE_MARGIN needed 1.05 rather than "exactly equal".
  // 2.0x is round and legible ("running at least twice what a typical line in
  // THIS pool does") rather than picked to land on a particular verdict.
  const RATIO_FLAG_MULT = 2.0
  const ratioFence = ratioMedian * RATIO_FLAG_MULT
  for (const r of lineRatios) {
    if (r.ratio <= ratioFence) continue
    flags.push({ move: r.hi, kind: 'PROGRESSION-RATIO',
      detail: `${r.line}${r.aoeSide ? ' (AoE)' : ''} runs ${r.ratio.toFixed(1)}x low-to-high `
        + `(lv${r.lo.learnLevel} ${r.lo.name} ${totalValue(r.lo).toFixed(1)}/s -> lv${r.hi.learnLevel} ${r.hi.name} `
        + `${totalValue(r.hi).toFixed(1)}/s) — over ${RATIO_FLAG_MULT}x the pool's own median line-ratio `
        + `(${ratioMedian.toFixed(1)}x, across ${lineRatios.length} cohorts)`,
      advice: `⚠️ WHICH END IS WRONG IS A SEPARATE QUESTION FROM WHETHER ONE IS — `
        + `check ${r.hi.name} against OVERBUDGET/IQR-HIGH first (the capstone may simply be hot); `
        + `if it isn't, ${r.lo.name} may be the one underpriced, not ${r.hi.name} overpriced` })
  }
}

/**
 * ⚠️ RESTORES ARE SCANNED SEPARATELY AND THE FIRST VERSION FORGOT TO SCAN THEM AT
 * ALL — the `restore` pool was built and never read, so `Tranquility`, the
 * clearest dominated move in the game, went unexamined by the tool written to find
 * it. Heals get no FLOOR check (there is no free heal to fall below) and are
 * compared only to other heals.
 */
for (const st of STATS) {
  if (only && st !== only) continue
  const rs = restore.filter((m) => m.stat === st)
  const perMana = (x: Move) => totalValue(x) / Math.max(1, x.mana ?? 10)
  for (const m of rs) {
    const v = totalValue(m)
    const better = rs.filter((o) => o !== m && LINE_OF[o.name] === LINE_OF[m.name]
      && o.learnLevel <= m.learnLevel
      && totalValue(o) > v * DOMINANCE_MARGIN && perMana(o) > perMana(m) * DOMINANCE_MARGIN)
    if (!better.length) continue
    const b = better.sort((x, y) => totalValue(y) - totalValue(x))[0]
    flags.push({ move: m, kind: 'DOMINATED', detail: `restore — lv${b.learnLevel} ${b.name} beats it on BOTH rates `
      + `(${totalValue(b).toFixed(1)} vs ${v.toFixed(1)}/s; ${perMana(b).toFixed(2)} vs ${perMana(m).toFixed(2)} per MP)`,
      advice: `raise power ${m.power} -> ~${Math.ceil(m.power * (totalValue(b) / v) * 1.1)}, `
        + `or cut mana ${m.mana} -> ~${Math.floor((m.mana ?? 10) * perMana(m) / perMana(b))}` })
  }
}

// ── Markdown table, for line-by-line review ─────────────────────────────────
const mdIdx = process.argv.indexOf('--md')
if (mdIdx >= 0) {
  const out = process.argv[mdIdx + 1]
  const L: string[] = []
  L.push('# Balance sweep — every recommendation')
  L.push('')
  L.push('Generated by `npx tsx tools/pool.ts --md <path>`. **Nothing here is applied.**')
  L.push('')
  L.push('⚠️ **A flag is a QUESTION, not a defect.** The pool is internally referenced —')
  L.push('double every power and this reports zero problems. Scale belongs to the sim.')
  L.push('')
  L.push('⚠️ **Every verdict adjusts POWER / MANA / COOLDOWN.** Keywords are never the fix;')
  L.push('they are what the move IS.')
  L.push('')
  L.push('| ✓ | stat | lv | ability | line | flag | why | recommendation |')
  L.push('|---|---|---:|---|---|---|---|---|')
  for (const f of [...flags].sort((a, b) =>
    a.move.stat.localeCompare(b.move.stat) || a.move.learnLevel - b.move.learnLevel)) {
    const m = f.move
    L.push(`| ☐ | ${m.stat} | ${m.learnLevel} | **${m.name}** | ${LINE_OF[m.name] ?? '—'} `
      + `| ${f.kind} | ${f.detail} | ${f.advice} |`)
  }
  L.push('')
  L.push('## Current numbers for every flagged move')
  L.push('')
  L.push('| ability | pwr | mana | cd (s) | acc | dmg/s | riders | uplift | total/s |')
  L.push('|---|---:|---:|---:|---:|---:|---|---:|---:|')
  for (const m of [...new Set(flags.map((f) => f.move))].sort((a, b) =>
    a.stat.localeCompare(b.stat) || a.learnLevel - b.learnLevel)) {
    const up = keywordUplift(m)
    L.push(`| ${m.stat} lv${m.learnLevel} **${m.name}** | ${m.power} | ${m.mana} | ${m.cooldown} `
      + `| ${m.accuracy} | ${damagePerSec(m).toFixed(1)} | ${up.parts.join(', ') || '—'} `
      + `| +${(up.total * 100).toFixed(0)}% | ${totalValue(m).toFixed(1)} |`)
  }
  L.push('')
  L.push('## Cohort distribution')
  L.push('')
  L.push('| stat | n | min | p25 | med | p75 | max |')
  L.push('|---|---:|---:|---:|---:|---:|---:|')
  for (const st of STATS) {
    const v = dmg.filter((m) => m.stat === st).map(totalValue).sort((a, b) => a - b)
    if (!v.length) continue
    const q = (x: number) => v[Math.min(v.length - 1, Math.floor(v.length * x))].toFixed(1)
    L.push(`| ${st} | ${v.length} | ${q(0)} | ${q(.25)} | ${q(.5)} | ${q(.75)} | ${q(.99)} |`)
  }
  L.push('')
  fs.writeFileSync(out, L.join('\n') + '\n')
  console.log(`\nwrote ${out} — ${flags.length} recommendations`)
}

// ── Output ───────────────────────────────────────────────────────────────────
console.log('BALANCE SWEEP — total value = damage/s x (1 + keyword uplift), judged at each')
console.log('move\'s own learn level. Mitigation cancels within a line and is NOT modelled.\n')
console.log('⚠️ Every verdict adjusts POWER / MANA / COOLDOWN. Keywords are never the fix —')
console.log('   they are what the move IS.\n')

for (const st of STATS) {
  if (only && st !== only) continue
  const f = flags.filter((x) => x.move.stat === st)
  const ms = dmg.filter((m) => m.stat === st)
  console.log(`\n══ ${st} — ${ms.length} damage moves, cohort median ${med(ms.map(totalValue)).toFixed(1)}/s`
    + `, ${f.length} flag${f.length === 1 ? '' : 's'}`)
  for (const x of f.sort((a, b) => a.move.learnLevel - b.move.learnLevel)) {
    console.log(`  ${x.kind.padEnd(12)} lv${String(x.move.learnLevel).padStart(3)} ${x.move.name}`)
    console.log(`               ${x.detail}`)
    console.log(`               → ${x.advice}`)
  }
}

console.log(`\n\nDISTRIBUTION — pick thresholds from this, do not trust the ones hard-coded above.`)
console.log('stat   n   min    p25    med    p75    max   (total value /s)')
for (const st of STATS) {
  const v = dmg.filter((m) => m.stat === st).map(totalValue).sort((a, b) => a - b)
  if (!v.length) continue
  const q = (p: number) => v[Math.min(v.length - 1, Math.floor(v.length * p))]
  console.log(`  ${st}  ${String(v.length).padStart(3)}  ${q(0).toFixed(1).padStart(5)}  ${q(.25).toFixed(1).padStart(5)}`
    + `  ${q(.5).toFixed(1).padStart(5)}  ${q(.75).toFixed(1).padStart(5)}  ${q(.99).toFixed(1).padStart(5)}`)
}
console.log(`\n${flags.length} flags across ${dmg.length} damage moves.`)
console.log('⚠️ A flag is a QUESTION, not a defect. The pool is internally referenced: double')
console.log('   every power and this reports zero problems. Scale is the sim\'s job.')
