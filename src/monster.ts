// Seed -> monster generator (§10.1 genome idea, simplified) plus derived values.
import {
  CLASSES, NORMAL_FOODS, INNATE_SECONDARY_LEVEL, LEAGUES, Monster, Move, RNG, STATS, Stat, Stats, classForStats, hashString,
  isFusionBody, isPrestigeBody, leagueForStat, mulberry32, pick, randInt, HARD_CONTROL_STATUSES,
  statScaleOf, DEFAULT_TACTICS, SECONDS_PER_TURN } from './core'
import { ALL_MOVES } from './moves'
import { CLASS_LINES } from './lines'
import { SPECIES } from './species'

const NAME_PARTS = ['Ash', 'Bru', 'Cor', 'Dra', 'Fen', 'Gru', 'Ky', 'Lo', 'Mor', 'Nyx', 'Pyr', 'Qui', 'Rho', 'Syl', 'Tho', 'Vex', 'Wyn', 'Zar']
const NAME_TAILS = ['ak', 'en', 'ix', 'or', 'us', 'a', 'eth', 'io', 'ryn', 'ok']

function randomName(rng: RNG): string {
  return pick(rng, NAME_PARTS) + pick(rng, NAME_TAILS)
}

/**
 * Spend `train` points across stats, weighted by the species' base spread so a
 * monster grows along its natural lean.
 *
 * ⚠️ `cap` DEFAULTS TO 1000 AND THAT DEFAULT WAS A HARD-CODED CEILING. League
 * caps run past it (Tamer Elite 1050, Apex 1100), so no budget could ever produce
 * a monster at the top two leagues — `tools/leagues.ts` binary-searching for cap
 * 1100 ran to a 6000-point budget and silently reported a 1000-stat Masters
 * monster as an Apex one. Every Elite/Apex balance question was unanswerable and
 * the harness did not say so; it just returned a plausible wrong number.
 *
 * Kept as a DEFAULT rather than removed: 1000 is what every existing caller and
 * every golden was generated against, so leaving it unset is byte-identical.
 */
function applyTraining(base: Stats, train: number, rng: RNG, cap = 1000): Stats {
  const stats: Stats = { ...base }
  const total = STATS.reduce((sum, k) => sum + base[k], 0)
  for (const k of STATS) {
    const weight = base[k] / total
    // jitter each stat's share ±30% so no two monsters train identically
    const jitter = 0.7 + rng() * 0.6
    stats[k] = Math.min(cap, Math.round(stats[k] + train * weight * jitter))
  }
  return stats
}

// CON safety net, NOT a target average (loosened 2026-07-21 — low CON is now a
// real archetype, not a pure downside: turn order runs off CON ascending, so a
// light/low-CON build acts first — see turnOrderCompare in battle.ts). The
// original 45%-of-cap floor was pulling the whole population toward an
// average; that fought directly against "quite low CON should be common and
// achievable." Now it's a thin backstop only — 15% of league cap, and only a
// weak 10-30% of the gap closes — so most monsters land naturally low (often
// well under the target itself, since a below-target roll only partially
// closes toward it) and only the most degenerate rolls get nudged up at all.
// Still only ever pulls upward — naturally tanky species keep whatever CON
// they earned.
const CON_LEAGUE_TARGET_FRACTION = 0.15
// ⚠️ `hardCap` is the per-stat CEILING; the local `cap` below is a league-derived
// CON *target*. Different quantities, and the first version of this parameter
// shadowed the second.
function boostConstitution(stats: Stats, rng: RNG, hardCap = 1000): Stats {
  const preBoostMax = Math.max(...STATS.map((k) => stats[k]))
  const cap = LEAGUES.find((l) => l.name === leagueForStat(preBoostMax))?.cap ?? LEAGUES[0].cap
  const target = cap * CON_LEAGUE_TARGET_FRACTION
  if (stats.CON >= target) return stats
  const pull = 0.1 + rng() * 0.2 // 10%-30% of the gap to the floor closes
  const boosted = stats.CON + (target - stats.CON) * pull
  return { ...stats, CON: Math.min(hardCap, Math.round(boosted)) }
}

// Hidden wild-instinct roll for GENERATED monsters — rivals, market offers,
// Sandbox opponents (user spec 2026-07-21). League scales it: Wood averages
// exactly the stated floor (40%), each league above trends ~6 points tamer.
// Tamer Elite is an EXCEPTION, not just the top of the curve (user spec
// 2026-07-21 follow-up: "make tamer an exception with max tameness for all
// animals, this is the elite") — every Tamer Elite monster is guaranteed 100,
// no roll, no variance; the tier is defined by total obedience. Every league
// below still rolls with variance, so it's a genuine per-individual trait
// there. Player monsters NEVER get this: `careerMonster()` builds its Monster
// by hand and simply never sets the field, so `tameness` stays undefined for
// anything the player raises — see chooseAction/wildAction in battle.ts,
// where undefined means "fully tame."
const TAMENESS_LEAGUE_BASE = 40 // Wood-league average — the spec's stated floor
const TAMENESS_LEAGUE_STEP = 6 // each league above Wood trends this much tamer
function rollTameness(maxStat: number, rng: RNG): number {
  const league = leagueForStat(maxStat)
  if (league === 'Tamer Elite') return 100
  const idx = Math.max(0, LEAGUES.findIndex((l) => l.name === league))
  const avg = TAMENESS_LEAGUE_BASE + idx * TAMENESS_LEAGUE_STEP
  return Math.max(5, Math.min(100, avg + randInt(rng, -18, 18)))
}

export function learnedMoves(stats: Stats): Move[] {
  return ALL_MOVES.filter((m) => stats[m.stat] >= m.learnLevel)
}

// Pick a 3-move loadout to MATCH the monster's class play style (user spec
// 2026-07-21: "make sure that the non player monster picks skills to match
// this play style"). With `stats`, damage moves are ranked by what this
// monster's stats can actually drive (power × the same (atk/40)^0.8 curve the
// battle sim uses, per channel), and support classes reserve slots for their
// signature utility: Tanks pack ward/guard/taunt, Sages pack heals and
// cleanses, Bards/Orators pack team buffs and enemy debuffs. Every reserved
// slot falls through to best-damage when nothing suitable is learned yet, so
// low-level monsters degrade gracefully. Without `stats` (legacy callers),
// falls back to raw-power ranking.
// ⚠️ Damage per CAST, divided by the cooldown that cast costs you — i.e. a rate,
// not a lump. It used to be `power × hits` with NO cooldown term at all, so the
// picker consistently preferred a big slow move to a better sustained one, and a
// single point of power could flip a slot no matter what it cost to use. Caught
// when a +11 power lift on Rime Bind (a lv160 move on a 3-turn cooldown) made it
// the top-scoring low INT move and the variety pass then handed it to 36% of ALL
// monsters across ten classes — a homogenised pool from one number moving.
// The divisor is cooldown alone: cast time lives in tamerengine, and monster.ts
// must not depend on the field engine.
/**
 * How much damage a move is actually worth TO THIS MONSTER.
 *
 * ⚠️ THE OLD VERSION WAS `power x hits / cooldown`, and that divisor is what
 * filled every kit with starters. It prices a move as though the monster could
 * only ever hold ONE — spam it, and a long cooldown is dead air. A monster holds
 * three or four and ROTATES: a cd-4 nuke fires at full value whenever it is up
 * while the others cover the gap. Under the divisor Scrap (14 power, cd 1, the
 * tutorial move) out-ranked Blood Price (32, cd 3) forever, which is why a
 * STR-359 Warrior drafted Scrap and a Sage with top WIS drafted three INT moves.
 * Cooldown is now a MILD discount, not a divisor.
 *
 * ⚠️ It also ignored `statScale` and read the stat off the CHANNEL rather than
 * the move — so a CON move on the melee channel (Body Slam) was scored by the
 * monster's STR. Both engines compute damage as `power x (1 + stats[mv.stat] x
 * statScale)`; the draft now ranks by that same expression, so what a monster
 * DRAFTS and what it HITS FOR finally agree, and a capstone that scales hard
 * reads as better on a trained monster instead of worse.
 */
const COOLDOWN_DISCOUNT = 0.18
const expectedOutput = (m: Move, stats?: Stats) => {
  const hits = m.effects?.hits ? (m.effects.hits[0] + m.effects.hits[1]) / 2 : 1
  const stat = stats ? (stats[m.stat] ?? 0) : 0
  const scaled = m.power * (1 + stat * statScaleOf(m)) * hits
  // ⚠️ IN TURNS, NOT SECONDS. `COOLDOWN_DISCOUNT` was calibrated against authored
  // cooldowns of 1-9; when the pool moved to seconds (1.3-11.7) feeding the raw
  // value inflated every discount and silently RE-DRAFTED EVERY KIT — which is
  // how a rename that changes no behaviour moved three field goldens. The picker
  // asks "how many casts do I give up", and that question is per turn.
  const turns = Math.max(1, m.cooldown / SECONDS_PER_TURN)
  return scaled / (1 + (turns - 1) * COOLDOWN_DISCOUNT)
}

type MovePick = (mv: Move) => boolean
const isHeal: MovePick = (mv) => mv.type !== 'damage' && mv.power > 0
// Widened 2026-07-25: was ward/guard-only, which made every defBuff-only move
// (Iron Skin/Barbed Carapace, Stone Wall) invisible even to Tank's own utility
// slot — found via the 3v3-6v6 auto-pick sweep (both were in the "never used"
// list despite being armor-flavored Tank moves).
const isWardOrGuard: MovePick = (mv) => !!(mv.effects?.ward || mv.effects?.guard || mv.effects?.defBuff || mv.effects?.thorns) && mv.type !== 'damage'
const isTaunt: MovePick = (mv) => !!mv.effects?.tauntForce
const isTeamBuff: MovePick = (mv) => mv.type !== 'damage' && mv.target === 'team'
const isEnemyDebuff: MovePick = (mv) => mv.type !== 'damage' && (mv.target === 'enemy' || mv.target === 'allEnemies')
const isCleanseOrRegen: MovePick = (mv) => !!(mv.effects?.cleanse || mv.effects?.regenBuff) && mv.type !== 'damage'
// A pure self-stat buff (atk/dodge/acc/regen on self) — matches none of the
// predicates above, so it was invisible to EVERY class, not just the 5 with a
// utility list (found via the same sweep: War Cry, Berserk, Sidestep, Focus
// Aim, Blur, Insight, Providence, Ascendance all had zero uses across 80
// battles). New universal fallback slot below, not a class-specific one.
// ⚠️ The universal fallback used `target === 'self'` ALONE, so a
// TEAM buff could never claim the fallback slot no matter how good it was —
// measured: Arcane Aegis was learnable by 53% of monsters and equipped by 0%.
// That silently blocked the whole "buffs affect all allies" rule at the loadout
// layer, one level above the engine. A team buff includes the caster, so it is
// strictly better than the equivalent self buff — hence PREFERRED here, with
// self as the fallback's fallback.
const isPersonalBuff: MovePick = (mv) => mv.type !== 'damage'
  && (mv.target === 'self' || mv.target === 'team' || mv.target === 'ally')
  && !!(mv.effects?.atkBuff || mv.effects?.dodgeBuff || mv.effects?.accBuff || mv.effects?.regenBuff)

// Classes whose P3 kit contract explicitly calls for movement denial, and so get
// ONE loadout slot reserved for a hard-control move. Deliberately short: denial
// on every class would make every fight a lockout, which is what CC diminishing
// returns already exists to prevent.
/**
 * HOW MANY SLOTS OF EACH KIND A CLASS RESERVES.
 *
 * ⚠️ THE CAPS USED TO BE GLOBAL, and that is what flattened class identity. Every
 * class could spend up to TWO slots on utility — the number was hard-coded as
 * `out.length >= 2` in three separate places — so a Wizard and a Sage budgeted
 * their kit identically despite one being a damage class and the other a healer.
 * Combined with the self-buff fallback, damage classes were routinely handing two
 * of three slots to buffs and fighting with one attack.
 *
 * `utility`   — ceiling on non-damage slots (heals, wards, taunts, team buffs)
 * `control`   — reserve one DAMAGE-typed hard-control move (a stun/root rider)
 * `minDamage` — floor. A kit that cannot hurt anything is not a kit, and this is
 *               what stops a generous utility profile eating the whole loadout.
 *
 * The caps interact with `size`, which is 3 for the turn engine and 4 for the
 * field, so a class gains its extra slot where its plan says it should.
 */
interface SlotPlan { utility: number; control: boolean; minDamage: number }
const DEFAULT_SLOTS: SlotPlan = { utility: 1, control: false, minDamage: 2 }
const CLASS_SLOTS: Record<string, SlotPlan> = {
  // Protectors and healers buy the second utility slot with a damage slot.
  Tank: { utility: 2, control: true, minDamage: 1 }, // taunt + ward, and the Warden slow decides the geometry
  Spellshield: { utility: 2, control: false, minDamage: 1 },
  Sage: { utility: 2, control: false, minDamage: 1 }, // heal + cleanse: the only stat that mends an ally
  Orator: { utility: 2, control: true, minDamage: 1 }, // CHA denies; the control slot is its win condition
  Captain: { utility: 2, control: false, minDamage: 1 },
  Bard: { utility: 2, control: false, minDamage: 1 },
  // Damage classes keep their damage. ⚠️ Wizard and Ranger previously spent up to
  // two slots on utility like a healer — a Wizard is a DAMAGE class that happens
  // to own denial, so it reserves control and nothing else.
  Wizard: { utility: 1, control: true, minDamage: 2 },
  Ranger: { utility: 1, control: true, minDamage: 2 }, // a real root to hold the target
  Warrior: { utility: 1, control: false, minDamage: 2 },
  Rogue: { utility: 1, control: false, minDamage: 2 },
  Spellsword: { utility: 1, control: false, minDamage: 2 },
  Generalist: { utility: 1, control: false, minDamage: 2 },
  // The orphan-pair seven. Damage classes keep their damage; the three support
  // ones buy a second utility slot with a damage slot, exactly as Sage does.
  Evoker: { utility: 1, control: true, minDamage: 2 },       // INT denial, like the Wizard
  Skirmisher: { utility: 1, control: false, minDamage: 2 },
  Stalker: { utility: 1, control: true, minDamage: 2 },      // a hunter holds its prey
  Swashbuckler: { utility: 1, control: false, minDamage: 2 },
  Shaman: { utility: 2, control: false, minDamage: 1 },
  Mystic: { utility: 2, control: false, minDamage: 1 },
  Herald: { utility: 2, control: false, minDamage: 1 },
}
const slotsFor = (cls: string): SlotPlan => CLASS_SLOTS[cls] ?? DEFAULT_SLOTS

// Utility slots a support class fills before topping up with damage, in order.
const CLASS_UTILITY_SLOTS: Record<string, MovePick[]> = {
  Tank: [isTaunt, isWardOrGuard, isHeal],
  Spellshield: [isWardOrGuard, isHeal],
  Sage: [isHeal, isCleanseOrRegen],
  Orator: [isTeamBuff, isEnemyDebuff],
  Bard: [isTeamBuff, isEnemyDebuff],
  // ⚠️ Only 5 of the 11 classes had a utility profile, so the other 6 fell
  // through to the buff fallback and picked up whatever ranked highest. These
  // three come straight from the P3 kit table: a Captain commands (team buffs),
  // and a Wizard/Spellsword now HAS protection worth equipping (Arcane Aegis,
  // Elemental Infusion) where INT previously offered nothing but damage.
  Captain: [isTeamBuff, isEnemyDebuff],
  Wizard: [isTeamBuff, isWardOrGuard],
  Spellsword: [isWardOrGuard, isTeamBuff],
  // The orphan-pair seven — each profile follows the class's own stat pair.
  Shaman: [isHeal, isWardOrGuard],       // WIS mends, CON protects
  Mystic: [isHeal, isCleanseOrRegen],    // WIS restores, and keeps itself running
  Herald: [isTeamBuff, isEnemyDebuff],   // CHA empowers and denies
}

/**
 * ⚠️ `size` DEFAULTS TO 3 and must stay that way for the turn engine: growing it
 * changes what every generated monster equips, which moves all 12 golden battles.
 * The FIELD engine passes 4 (see FIELD_LOADOUT_SIZE) through its own call site,
 * so the two engines can disagree until the field one takes over.
 */
export function chooseLoadout(learned: Move[], stats?: Stats, size = 3): Move[] {
  // A learned move that's one half of a designed setup->payoff pair (the
  // OTHER half also learned) — either a bonusVsStatus combo (Bloodletter/
  // Rending Blow, Field of Doom/Mind Crush, Cinderburst/Ember, Siren's Call/
  // Screech), or CON's non-status taunt+thorns combo (Bulwark's Challenge/
  // Barbed Carapace — force the enemy team onto the wearer, punish every
  // hit). 2026-07-25 fix: without this, a debuff-type setter (Field of Doom/
  // Marked for the Pack) was invisible outside Orator/Bard, and even
  // damage-type payoffs (Bloodletter) routinely lost the "single best move
  // per stat" ranking to the monster's own capstone, so combo halves almost
  // never coexisted in a 3-move loadout.
  const isComboPiece: MovePick = (mv) => {
    if (mv.effects?.bonusVsStatus) return learned.some((s) => s !== mv && s.status?.kind === mv.effects!.bonusVsStatus!.kind)
    if (mv.status) return learned.some((p) => p !== mv && p.effects?.bonusVsStatus?.kind === mv.status!.kind)
    // Scoped to the MASS taunt specifically (target allEnemies) — the plain
    // single-target Taunt (level 90, unchanged) is learnable at CON>=90, an
    // extremely low bar almost every monster clears, so an unscoped check
    // here made this "combo" fire for nearly every monster regardless of
    // class, crowding out everything else (caught by re-running the sweep:
    // thorns/taunt usage spiked to ~19-20/20 battles, total move diversity
    // collapsed from ~55 to ~35 moves used).
    if (mv.effects?.tauntForce && mv.target === 'allEnemies') return learned.some((t) => t !== mv && !!t.effects?.thorns)
    if (mv.effects?.thorns) return learned.some((t) => t !== mv && !!t.effects?.tauntForce && t.target === 'allEnemies')
    return false
  }
  // NOT every status-carrying move is part of a designed pair (e.g. the
  // vulnerable-setters and Cacophony's charm are standalone team-fight
  // tools, not bonusVsStatus combos) — give those a smaller, unconditional
  // nudge so they can still compete against a stat's single strongest
  // pure-damage move instead of being crowded out every time.
  // ⚠️ Every status used to be worth a flat ×1.15 regardless of what it DID or how
  // often it landed, so a 55%-chance knockback scored the same as a 30% bleed.
  // That is why the control moves were dead weight: they are deliberately
  // low-power (control traded for damage), and a flat nudge could never pay that
  // trade back — Seize, Rime Bind and Frost Nova measured 0% equipped across 780
  // monsters despite being learnable by up to 38% of them.
  // Now the nudge is worth what the status is worth: HARD CONTROL takes a turn
  // away, a DoT just adds a little damage. Scaled by landing chance so a coin-flip
  // stun is not priced like a guaranteed one.
  // ⚠️ Kept deliberately modest. A big multiplier here would hand every slot to
  // whatever carries CC — the loadout-layer version of how War Cry once took 137
  // of 254 utility casts. 0.3 also keeps a 50%-chance DoT at ~1.15, i.e. exactly
  // the old value, so this is additive for control rather than a global reshuffle.
  const statusWeight = (m: Move) => {
    if (!m.status) return 1
    const chance = Math.min(100, Math.max(0, m.status.chance)) / 100
    return 1 + chance * (HARD_CONTROL_STATUSES.has(m.status.kind) ? 0.4 : 0.3)
  }
  const dmgScore = (m: Move) => {
    // ⚠️ The old channel-stat multiplier is GONE, not merely replaced: the stat
    // now enters through expectedOutput via the move's OWN stat, exactly as the
    // damage formula uses it. Keeping both would count the stat twice.
    const base = expectedOutput(m, stats)
    // proportional nudges, so neither can make a genuinely weak low-level
    // move outrank a much stronger high-level one
    if (isComboPiece(m)) return base * 1.5 * lineFit(m)
    return base * statusWeight(m) * lineFit(m)
  }
  // ── LINE AFFINITY ─────────────────────────────────────────────────────────
  // ⚠️ THE fix for the trap that swallowed three waves of authored content
  // (control moves, team buffs, defensive moves — all 0% equipped). The picker
  // used to rank the whole pool globally, so a move only ever got drafted by
  // out-scoring all 100 others; anything deliberately traded away from raw
  // numbers could never win. Now a move that expresses what this monster is FOR
  // gets a real edge over one that merely scores well. See src/lines.ts.
  //
  // ⚠️ Deliberately a MULTIPLIER, not a filter. A Wizard with a genuinely great
  // off-line move can still take it — off-line content stays reachable, which is
  // what keeps multi-classing and odd stat spreads interesting. Two earlier
  // attempts at the same problem overshot precisely because they were absolute:
  // a status weighting put one move on 36% of all monsters, and a value-based
  // support sort collapsed every kit onto the same two team buffs.
  const myLines = stats ? CLASS_LINES[classForStats(stats)] : undefined
  const lineFit = (m: Move) => (myLines && m.line && myLines.includes(m.line) ? 1.35 : 1)
  const damage = learned.filter((m) => m.type === 'damage').sort((a, b) => dmgScore(b) - dmgScore(a))
  // ⚠️ Sorted by learnLevel, i.e. LEVEL AS A PROXY FOR QUALITY. This is a known
  // weakness, not a good rule: Acrobatics (lv160, +30% dodge) loses its slot to
  // Blur (lv240, +14%) purely on level. A value-based sort was TRIED and measured
  // WORSE across the board — defensive moves equipped 33% -> 20%, defensive casts
  // 6.5% -> 5.3%, damage/fight 1859 -> 1676 — because scoring by magnitude
  // concentrates every kit onto the same two team buffs and kills variety.
  // ⚠️ Ordered by LINE AFFINITY first, then learnLevel. The old sort was
  // learnLevel alone — level as a proxy for quality — which is how Acrobatics
  // (lv160, +30% dodge) lost its slot to Blur (lv240, +14%). A value-based sort
  // was tried instead and measured WORSE across the board (defensive moves
  // equipped 33% -> 20%, casts 6.5% -> 5.3%, damage 1859 -> 1676) because ranking
  // support by raw magnitude collapses every kit onto the same two team buffs.
  // Affinity avoids that: it does not say which buff is biggest, it says which
  // buff belongs to this monster — so kits diverge by class instead of converging.
  const support = learned.filter((m) => m.type !== 'damage')
    .sort((a, b) => (lineFit(b) - lineFit(a)) || (b.learnLevel - a.learnLevel))
  const out: Move[] = []

  if (stats) {
    // Combo pairs claim slots FIRST (2026-07-25 fix, 2nd pass): appending the
    // combo/self-buff fallback to the END of a class's own utility list (the
    // first version of this fix) never actually ran for Tank/Spellshield/
    // Sage/Orator/Bard, since their OWN 2 reserved slots already hit the
    // `out.length >= 2` cap before the appended checks were ever reached —
    // confirmed by direct chooseLoadout inspection (a Sage with BOTH Field of
    // Doom and Mind Crush learned still got Tranquility+Ward Against Ruin,
    // Field of Doom never considered). A genuine learned combo now beats
    // generic class utility outright — a deliberate 2-slot commitment, same
    // spirit as "a combo costs 2 of your 3 loadout slots."
    //
    // 2026-07-25 fix, 3rd pass: a monster eligible for MULTIPLE combos at
    // once (common near max stats, since CON gets broadly boosted by
    // training + its safety floor) used to just get whichever pair's pieces
    // happened to scan first — confirmed directly: a STR-primary Titanrex
    // and a CHA-primary Vespera, both also CON-heavy enough to qualify for
    // Bulwark's Challenge+Barbed Carapace, got that combo instead of their
    // own STR-bleed/CHA-fear combo. Now every eligible pair is collected and
    // SCORED — by the monster's current value in each piece's own gating
    // stat, with a bonus when that stat is this monster's class primary/
    // secondary (from CLASSES) — and the highest-scoring pair wins, so a
    // Warrior's own STR combo beats an incidental CON one even if both
    // technically qualify.
    // The class's own slot budget — see CLASS_SLOTS. `utilityCap` can never eat
    // the damage floor, whatever the profile asks for.
    const plan = slotsFor(classForStats(stats))
    const utilityCap = Math.max(0, Math.min(plan.utility, size - plan.minDamage))
    // ⚠️ COUNT UTILITY, NOT SLOTS. The cap must look at how many NON-DAMAGE moves
    // are held, not at `out.length` — a combo pair claims its slots first and its
    // pieces are usually damage-typed, so a total-slot cap was already "full"
    // before the utility loop ran and a Sage ended up with 0.19 heals per kit.
    const utilityHeld = () => out.filter((mv) => mv.type !== 'damage').length
    const damageHeld = () => out.filter((mv) => mv.type === 'damage').length
    /**
     * ⚠️ THE SAME BUG AS `utilityHeld`, HALF-FIXED. That one stopped the CAP
     * counting slots instead of utility. The FLOOR guard beside it — written
     * `out.length >= size - plan.minDamage` — was still a raw total-slot check,
     * and it fails for exactly the same reason: a combo pair claims its slots
     * first and its pieces are damage-typed, so a Sage holding Ember +
     * Cinderburst reads as "2 of 3 slots gone, stop" and breaks out of the
     * utility loop before ever reaching `isHeal`. The damage floor was already
     * satisfied TWICE OVER at that point.
     *
     * The floor is about how many DAMAGE moves survive, not how many slots are
     * spent. There is room for one more utility move as long as the slots left
     * after it can still carry whatever damage the floor is missing.
     */
    const canAddUtility = () =>
      out.length < size
      && (size - out.length - 1) >= Math.max(0, plan.minDamage - damageHeld())

    interface ComboPair { pieces: [Move, Move]; score: number }
    const cls = CLASSES.find((c) => c.name === classForStats(stats))
    // A stable per-monster number derived from what makes it that monster.
    const statHash = Math.abs(
      Object.values(stats).reduce((h, v) => Math.imul(h ^ v, 2654435761) >>> 0, 17)) >>> 0
    const statFit = (m: Move) => (stats[m.stat] ?? 0) + (cls?.primary === m.stat ? 300 : cls?.secondary === m.stat ? 150 : 0)
    const pairs: ComboPair[] = []
    const addPair = (a: Move, b: Move) => {
      if (pairs.some((p) => p.pieces.includes(a) && p.pieces.includes(b))) return // no dupes
      pairs.push({ pieces: [a, b], score: statFit(a) + statFit(b) })
    }
    for (const mv of learned) {
      if (mv.effects?.bonusVsStatus) {
        const setup = learned.find((s) => s !== mv && s.status?.kind === mv.effects!.bonusVsStatus!.kind)
        if (setup) addPair(setup, mv)
      }
    }
    const massTaunt = learned.find((m) => m.effects?.tauntForce && m.target === 'allEnemies')
    const thornsMove = learned.find((m) => m.effects?.thorns)
    if (massTaunt && thornsMove) addPair(massTaunt, thornsMove)

    // ⚠️ THE COMBO MUST BE THE CLASS'S OWN, OR IT HOMOGENISES THE WHOLE GAME.
    // The pair is claimed BEFORE class utility and before line affinity get a
    // say, so whatever pair a monster happens to qualify for overrides its
    // identity. Ember + Cinderburst — the earliest and cheapest INT setup and
    // detonator — was drafted by 38% of EVERY monster in the game, because INT
    // is a SECONDARY stat for a great many classes: 68% of Sages carried it,
    // 80% of Rangers. Only 7% were off-class by a primary/secondary test, which
    // is why that test was not enough. There were 74 distinct loadouts across
    // 195 monsters, and 5 across 22 Sages.
    //
    // Requiring a piece on the class's PRIMARY stat keeps the mechanic doing its
    // job — a detonator still gets its setup drafted with it, so bonusVsStatus
    // is not dead content — while stopping one stat's cheap combo leaking into
    // every class that merely dabbles in it.
    const ownCombo = (p: ComboPair) =>
      !cls || p.pieces.some((mv) => mv.stat === cls.primary)
    const usable = pairs.filter(ownCombo)
    if (usable.length) {
      usable.sort((a, b) => b.score - a.score)
      for (const mv of usable[0].pieces) {
        if (out.length >= 2) break
        out.push(mv)
      }
    }
    // Class-signature utility next (existing behavior — Tanks still prefer
    // their taunt/ward, Sages their heals, etc) for whatever slots remain.
    const slots = CLASS_UTILITY_SLOTS[classForStats(stats)] ?? []
    for (const want of slots) {
      if (utilityHeld() >= utilityCap) break // the class's OWN ceiling, not a global 2
      if (!canAddUtility()) break // never starve the damage FLOOR — counted in damage moves
      // ⚠️ TAKING THE FIRST MATCH MAKES EVERY MEMBER OF A CLASS IDENTICAL. The
      // candidates are already ranked, so `find` handed all 22 Sages the same
      // heal and left 5 distinct kits between them. Class identity should say
      // WHAT KIND of move you bring, not force the exact one — two Sages ought
      // to be recognisably Sages and still different monsters.
      //
      // Picks among the top few equally-valid candidates using a hash of the
      // monster's own stats: deterministic (no rng, replays reproduce, and
      // chooseLoadout needs no new argument) and different between monsters.
      const band = support.filter((mv) => want(mv) && !out.includes(mv))
      const pick = band[statHash % Math.min(3, band.length || 1)]
      if (pick) out.push(pick)
    }
    // Self-buff fallback, available to EVERY class (previously invisible to
    // all of them — War Cry, Berserk, Blur, Insight, Providence... had zero
    // uses across 80 battles), if a utility slot is still unclaimed.
    if (utilityHeld() < utilityCap && canAddUtility()) {
      // Team-wide first (it covers the caster too and is priced for the reach),
      // then a self-only buff. See the isPersonalBuff note above.
      const pick = support.find((mv) => mv.target === 'team' && isPersonalBuff(mv) && !out.includes(mv))
        ?? support.find((mv) => isPersonalBuff(mv) && !out.includes(mv))
      if (pick) out.push(pick)
    }
    // ── ONE RESERVED CONTROL SLOT, for the classes whose kit calls for it ─────
    // ⚠️ Control moves cannot be made to WIN a damage comparison, and trying was
    // the mistake. They are deliberately low-power — control traded for damage —
    // so ranking them as damage means they either lose outright (0% equipped) or,
    // if nudged hard enough to win, they take over: a single +11 power lift put
    // Rime Bind on 36% of all monsters across ten classes. Neither is a kit.
    // So the class that NEEDS denial reserves a slot for it, exactly as Tanks
    // reserve one for a taunt. Straight from the P3 kit table: Ranger — "a real
    // root to hold the target"; Wizard — Hexer zones/denial; Tank — "decides the
    // geometry" via the Warden slow.
    // ⚠️ Drawn from `damage`, not `support`: these moves carry their control as a
    // rider on a hit (`type: 'damage'`), so no utility predicate can ever see
    // them. And it never claims the LAST slot — a kit without damage is not a kit.
    // The control move is DAMAGE-typed, so it never threatens the damage floor —
    // it only must not claim the last slot outright.
    if (plan.control && out.length < size - 1) {
      const pick = damage.find((mv) =>
        mv.status && HARD_CONTROL_STATUSES.has(mv.status.kind) && !out.includes(mv))
      if (pick) out.push(pick)
    }
  }

  // Fill remaining slots with the best damage this monster's stats can drive,
  // varied across stats where possible. `!out.includes(m)` guard added
  // 2026-07-25: previously safe to omit since `out` only ever held
  // non-damage moves at this point (support/damage are disjoint arrays) —
  // no longer true now that a combo payoff (often type 'damage') can land in
  // `out` via the priority pass above, which caused Mind Crush et al. to get
  // pushed a 2nd time here, duplicating a loadout slot.
  // ⚠️ THE ONE-MOVE-PER-STAT RULE LOOKS WRONG AND IS RIGHT — do not "fix" it.
  // It reads like a bug: it forces the last slot off-stat, so a STR-359 Warrior
  // ends up holding a DEX shot instead of a second STR move. Replacing it with a
  // soft 0.85 penalty (so a clearly better same-stat move could win) was TRIED
  // and measured WORSE on the acceptance test — damage classes beating a tank
  // 1v1 fell 44% -> 41%, and the STR bruiser specifically 63% -> 50%.
  // The reason is MITIGATION IS CHANNEL-SPLIT: melee/ranged are mitigated by the
  // target's CON, magic/voice/support by its WIS. A tank is CON-heavy and
  // WIS-light, so a monster carrying a second stat's move has a channel that
  // routes around the wall's best defence, while one stacking its own stat feeds
  // every hit into the stat the tank trained. Variety is not cosmetic here — it
  // is the counterplay to a tank, and it is why CHA support leapt 4% -> 42% when
  // it was allowed to stack voice moves.
  const seenStats = new Set<Stat>()
  for (const m of damage) {
    if (out.length >= size) break
    if (out.includes(m)) continue
    if (!seenStats.has(m.stat) || out.length < 2) { out.push(m); seenStats.add(m.stat) }
  }
  for (const m of [...damage, ...support]) {
    if (out.length >= size) break
    if (!out.includes(m)) out.push(m)
  }
  return out.slice(0, size)
}

export interface GenOptions {
  train?: number
  // v0.77 market systems. All three default to off, so every existing caller
  // (and every golden) generates byte-identically.
  speciesId?: string // force an exact species — the Market Scout's pick
  noPrestige?: boolean // exclude Draconic/Abyssal/Mythical — the stray event
  targetTop?: number // normalise so the HIGHEST stat lands here — the Market Coach
  /**
   * Per-stat ceiling. Defaults to 1000 — the value that was hard-coded, so every
   * existing caller and golden is unchanged. Pass a league cap to model a monster
   * trained at that licence (see LEAGUES in core.ts, tools/leagues.ts).
   */
  statCap?: number
}

// Fusion species are NEVER wild/market — they only exist as a fusion RESULT.
// (Filtering them out also keeps the generation pool — and every golden — byte-
// identical to before they were added, since they're appended at the array end.)
const GENERATABLE = SPECIES.filter((s) => !isFusionBody(s.body))
const NON_PRESTIGE = GENERATABLE.filter((s) => !isPrestigeBody(s.body))

// Scale every stat so the top one lands on `top`, preserving the species' stat
// SHAPE (and the per-monster training jitter baked in above). Used by the Market
// Coach to guarantee an offer actually sits in the promised league band — a flat
// training budget scatters far too wide to make that promise honestly.
// Market Coach quality multiplier by body (v0.852): coached PRESTIGE stock comes
// in stronger than basic stock at the same tier — the license buys a higher-grade
// monster — and Mythical (the top prestige class) always lands highest. Applied
// to the coach's target-top before normalisation, so it only affects coached
// offers (targetTop set); wild/rival/golden generation is untouched.
export const COACH_PRESTIGE_MULT: Partial<Record<string, number>> = { Draconic: 1.15, Abyssal: 1.15, Mythical: 1.3 }

function normaliseTop(stats: Stats, top: number): Stats {
  const cur = Math.max(...STATS.map((k) => stats[k]))
  if (cur <= 0) return stats
  const k = top / cur
  const out = { ...stats }
  for (const s of STATS) out[s] = Math.max(1, Math.min(1000, Math.round(stats[s] * k)))
  return out
}

export function generateMonster(seed: string, opts: GenOptions = {}): Monster {
  const rng = mulberry32(hashString(seed || 'egg'))
  const pool = opts.noPrestige ? NON_PRESTIGE : GENERATABLE
  const species = (opts.speciesId ? GENERATABLE.find((s) => s.id === opts.speciesId) : undefined)
    ?? pool[hashString(seed || 'egg') % pool.length]
  const sex = rng() < 0.5 ? 'M' : 'F'

  // Individual variance (±5), order-preserving: jittered values are re-assigned
  // largest-to-largest along the species' base ranking, so siblings differ in
  // magnitude but a species' stat hierarchy (and thus its class) never flips.
  const base: Stats = { ...species.base }
  const jittered = STATS.map((k) => Math.max(1, species.base[k] + randInt(rng, -5, 5))).sort((a, b) => b - a)
  const ranked = [...STATS].sort((a, b) => species.base[b] - species.base[a])
  ranked.forEach((k, i) => { base[k] = jittered[i] })

  const cap = opts.statCap ?? 1000
  const trained = boostConstitution(applyTraining(base, opts.train ?? 0, rng, cap), rng, cap)
  const effTop = opts.targetTop ? Math.round(opts.targetTop * (COACH_PRESTIGE_MULT[species.body] ?? 1)) : undefined
  const stats = effTop ? normaliseTop(trained, effTop) : trained
  const learned = learnedMoves(stats)
  const loadout = chooseLoadout(learned, stats)
  const maxStat = Math.max(...STATS.map((k) => stats[k]))

  const favouriteFood = pick(rng, NORMAL_FOODS).id
  let hatedFood = pick(rng, NORMAL_FOODS).id
  while (hatedFood === favouriteFood) hatedFood = pick(rng, NORMAL_FOODS).id

  return {
    seed,
    name: randomName(rng),
    species,
    sex,
    stats,
    className: classForStats(stats),
    league: leagueForStat(maxStat),
    learned,
    loadout,
    innateUnlocked: maxStat >= INNATE_SECONDARY_LEVEL,
    activeInnate: 0,
    favouriteFood,
    hatedFood,
    tameness: rollTameness(maxStat, rng),
    /**
     * ⚠️ NEUTRAL STANDING ORDERS, NOT "no orders". Absent `tactics` and
     * DEFAULT_TACTICS are NOT the same thing to either engine — absent means
     * `targetPriority` is undefined and `priorityBias` returns 0, so a monster
     * without this field fights with a piece of the AI switched off.
     *
     * ⚠️ THAT IS WHY THIS IS SET HERE AND NOT IN THE HARNESS. Every balance tool
     * in the project — sweep40, ab, effects, focus, leagues — builds its teams
     * from `generateMonster`, and every one of them was therefore measuring
     * monsters with EVERY TACTIC DISABLED. The 40-matchup sweep returned
     * byte-identical totals (23.9s / 188 kills / 2781 dmg) across five different
     * values of MELEE_PRIORITY_SLACK, which is what exposed it. Patching
     * `tools/comps.ts` would have fixed the four tools that exist and left the
     * trap set for the fifth.
     *
     * The real game overwrites this anyway — the pre-fight orders screen and
     * `GAMEPLANS` both assign tactics before a fight — so this is the FLOOR, and
     * its job is to make "no one set orders" mean the same thing everywhere.
     */
    tactics: { ...DEFAULT_TACTICS },
  }
}

// --- Derived combat values (§11) ---
// Battle fatigue (user spec 2026-07-19): entering a fight below full stamina
// debuffs ALL damage that monster deals. 76+ is rested (no penalty), then
// tiers: ≤75 → −10%, ≤50 → −20%, ≤40 → −30%, ≤25 → −50%. Rivals and sandbox
// monsters have no stamina tracked and always fight fresh.
export function staminaDamageMult(stamina: number): number {
  if (stamina >= 76) return 1
  if (stamina > 50) return 0.9
  if (stamina > 40) return 0.8
  if (stamina > 25) return 0.7
  return 0.5
}

/**
 * ⚠️ SUPERLINEAR IN CON, deliberately. The linear `40 + CON*2` meant durability
 * grew at a fixed rate while damage compounds — every damage move carries
 * `power * (1 + stat * statScale)` AND is cast by a monster whose stat also grew.
 * Measured on the ELITE tier (train 3200, top stat ~1000): damage per fight went
 * 2771 -> 9186, a 3.3x jump, while fights got FASTER (18.8s -> 14.1s) on the same
 * kill count. Offence was outrunning defence at exactly the leagues where CON is
 * supposed to be a real investment.
 *
 * The quadratic term is negligible early and material late, so a Wood-league
 * monster is unaffected and a Masters wall is genuinely a wall:
 *   CON  100 ->  246 (was  240, +2%)
 *   CON  300 ->  696 (was  640, +9%)
 *   CON  600 -> 1465 (was 1240, +18%)
 *   CON 1000 -> 2665 (was 2040, +31%)
 *
 * ⚠️ SHARED BY BOTH ENGINES — battle.ts and tamerengine both call this, so it
 * moves every golden in the project. That is the intended blast radius, not a
 * regression.
 */
export const maxHp = (s: Stats) => Math.round(40 + s.CON * 2.0 + (s.CON * s.CON) / 1600)
// WIS is the mana FOUNDATION (and stays the sole regen stat); INT contributes
// half its value to the pool (2026-07-25 review fix: maxMana = WIS alone
// starved INT-primary classes — a Spellsword's whole chain-caster identity
// died on a tiny MP pool because its class stats are INT/CON, not WIS).
export const maxMana = (s: Stats) => s.WIS + Math.floor(s.INT / 2)
export const dodgeChance = (s: Stats) => Math.min(35, s.DEX * 0.06)

// Per-turn regen + proc chances derived from stats (user spec 2026-07-19) —
// every stat contributes a small battle bonus beyond its main role:
export const hpRegen = (s: Stats) => Math.floor(s.CON / 25) // +1 HP/turn per 25 CON
export const manaRegen = (s: Stats) => Math.round(2 + s.WIS * 0.01) + Math.floor(s.WIS / 50) // base + 1/turn per 50 WIS
export const critChance = (s: Stats) => Math.floor(s.DEX / 50) // % chance to deal double damage, per 50 DEX
export const mitigationPierce = (s: Stats) => Math.floor(s.STR / 100) * 0.01 // fraction of mitigation ignored, 1% per 100 STR
export const echoChance = (s: Stats) => Math.floor(s.INT / 100) // % chance a skill casts twice, per 100 INT
export const debuffReduction = (s: Stats) => Math.floor(s.CHA / 50) * 0.01 // incoming debuff magnitude cut, 1% per 50 CHA
export const debuffBonus = (s: Stats) => Math.floor(s.CHA / 50) // % added to own status-proc chance, per 50 CHA — MAY exceed the 50% design cap

export function attackStat(s: Stats, channel: Move['channel']): number {
  switch (channel) {
    case 'melee': return s.STR
    case 'ranged': return s.DEX
    case 'magic': return s.INT
    case 'voice': return s.CHA
    case 'support': return s.WIS
  }
}

// Mana cost per skill (battle-choice design): EVERY skill costs MP, whatever its
// channel — if a monster can't afford any equipped skill it must Attack or Block.
// The universal Attack/Block actions (battle.ts) are the only free options.
// Multi-hit skills pay for their expected total output, not the per-hit power.
// Costs are 2× the base formula (user spec 2026-07-20: "increase all spell costs by 100%").
export function manaCost(m: Move): number {
  // AUTHORED cost wins. Mana is a design axis, not just a formula output: a move
  // may be deliberately stronger on some other axis and simply cost more MP.
  if (m.mana !== undefined) return m.mana
  const avgHits = m.effects?.hits ? (m.effects.hits[0] + m.effects.hits[1]) / 2 : 1
  const base = m.type === 'damage' ? Math.max(4, Math.round(m.power * avgHits * 0.45))
    : m.power > 0 ? Math.max(6, Math.round(m.power * 0.4)) // heals
    : 6 // buffs / control / utility
  return base * 2
}
