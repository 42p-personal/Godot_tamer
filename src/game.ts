// Weekly calendar / career loop (M2, §2). A single monster you raise week by week:
// weekly actions (train drill / rest / feed / excursion), stamina, gold, aging.
import {
  BODY_MINOR, FOODS, Food, INNATE_SECONDARY_LEVEL, LEAGUES, MAX_HAPPINESS, Monster, Move, RNG, STATS, Sex, Species, Stats, Stat, Tactics, TrainingProfile,
  classForStats, feedDelta, foodDef, hashString, isFusionBody, isPrestigeBody, mulberry32,
} from './core'
import { ALL_DRILLS } from './drills'
import { GenOptions, chooseLoadout, generateMonster, learnedMoves, maxHp, maxMana } from './monster'
import { Signature, canAwaken, signatureMove, signatureName } from './signature'

export const WEEKS_PER_MONTH = 4
export const MONTHS_PER_YEAR = 12
export const WEEKS_PER_YEAR = WEEKS_PER_MONTH * MONTHS_PER_YEAR // 48
const START_AGE_WEEKS = WEEKS_PER_YEAR // start as a Teen (age 1)
export const START_GOLD = 500
export const MAX_STAMINA = 100
export const BASIC_DRILL_STAMINA = 15
export const INTENSIVE_DRILL_STAMINA = 25
export const EXTREME_DRILL_STAMINA = 35 // extreme drills (v0.6): the risk tier
export const DIVERSE_DRILL_STAMINA = 35 // diverse drills (v0.90): mirrors EXTREME — same +16 net, same 35 stamina, opposite shape
export const drillStamina = (kind: string): number =>
  kind === 'basic' ? BASIC_DRILL_STAMINA : kind === 'intensive' ? INTENSIVE_DRILL_STAMINA
    : kind === 'diverse' ? DIVERSE_DRILL_STAMINA : EXTREME_DRILL_STAMINA
const EXCURSION_COST = 25

export type Stage = 'Baby' | 'Teen' | 'Fully Grown' | 'Elder' | 'Retiree'

// Pedigree career-span bonus (v0.72): the monsters you INVEST in — fusion
// specialists, prestige-tier (Draconic/Abyssal/Mythical), and anything bred
// (gen ≥ 2) — get extra competing years, so your long-term project lines have
// the runway to reach champion level before aging out. Wild base monsters get
// nothing here, so the baseline difficulty is unchanged. Flat, not additive.
export const PEDIGREE_SPAN_BONUS = 2 // years
export function pedigreeSpanBonus(c: { species: { body: string }; generation?: number }): number {
  if (isFusionBody(c.species.body as never) || isPrestigeBody(c.species.body as never) || (c.generation ?? 1) >= 2) return PEDIGREE_SPAN_BONUS
  return 0
}

// Effective CAREER SPAN in years: the species' base competing years + the
// pedigree bonus (fusion/prestige/bred) + the stable-wide comfort set (+2mo per
// item, synced onto the career) + any Elder Tonics used. 1 month = 4 weeks.
export const careerSpanYears = (c: { species: { lifespan: number; body: string }; generation?: number; comfortWeeks?: number; tonicWeeks?: number }): number =>
  c.species.lifespan + pedigreeSpanBonus(c) + ((c.comfortWeeks ?? 0) + (c.tonicWeeks ?? 0)) / 48

// `lifespan` here is the effective career span in YEARS (careerSpanYears, a
// float). Elder/Retiree boundaries are computed in WEEKS (v0.85) so the +8-week
// comfort/tonic purchases delay aging smoothly by exactly their weeks — the old
// `ageYears >= lifespan` integer compare rounded any fraction up to a whole
// extra year, so 1 comfort item and 3 gave the same retirement. Baby/Teen stay
// keyed to whole years (year 0 / year 1) — those bands are fixed, not extendable.
export function stageInfo(ageWeeks: number, lifespan: number): { stage: Stage; trainMult: number; ageYears: number } {
  const ageYears = Math.floor(ageWeeks / WEEKS_PER_YEAR)
  const spanWeeks = Math.round(lifespan * WEEKS_PER_YEAR)
  let stage: Stage
  if (ageWeeks < WEEKS_PER_YEAR) stage = 'Baby' // year 0
  else if (ageWeeks < 2 * WEEKS_PER_YEAR) stage = 'Teen' // year 1
  else if (ageWeeks >= spanWeeks) stage = 'Retiree'
  else if (ageWeeks >= spanWeeks - WEEKS_PER_YEAR) stage = 'Elder' // final year before retirement
  else stage = 'Fully Grown'
  const trainMult = stage === 'Baby' ? 0.5 : stage === 'Teen' ? 1.35 : stage === 'Fully Grown' ? 1.15 : stage === 'Elder' ? 0.8 : 0
  return { stage, trainMult, ageYears }
}

export function dateLabel(week: number): string {
  const y = Math.floor(week / WEEKS_PER_YEAR) + 1
  const mo = Math.floor((week % WEEKS_PER_YEAR) / WEEKS_PER_MONTH) + 1
  const wk = (week % WEEKS_PER_MONTH) + 1
  return `Yr ${y} · Month ${mo} · Wk ${wk}`
}

// A past tournament entry, kept for the ranch's Tournament History panel.
// `placement` is binary for now (a tournament is one battle vs one rival) —
// becomes richer (1st/2nd/3rd/...) once multi-participant brackets land.
export interface TournamentResult {
  name: string
  league: string
  week: number // global week the tournament resolved
  placement: number // 1-based final round-robin standing (1 = champion)
  fieldSize: number // total participants that event, for a "2nd of 5" display
}

export interface Career {
  id: string
  name: string
  species: Species
  sex: Sex
  favouriteFood: Food
  hatedFood: Food
  stats: Stats
  ageWeeks: number
  hp: number // current hit points — injuries persist between weeks; only Rest heals
  mp: number // current mana — drained by battles; only Rest restores
  stamina: number
  happiness: number
  licenseIndex: number
  week: number // weeks since this monster joined the stable (age/log bookkeeping)
  retired: boolean
  fedThisWeek: boolean // only one food may be bought per week per monster
  loadout: string[] // persisted equipped-move ids (≤3); empty = auto-pick (chooseLoadout)
  activeInnate: number // 0 or 1 — which of the species' two innates is active; changed like a loadout swap
  tactics?: Tactics // standing battle orders (2026-07-25); absent = DEFAULT_TACTICS behavior
  lastFood?: Food // food fed LAST week — drives the satiety rule (repeat → halved happiness)
  truffleReady?: boolean // a Golden Truffle is banked — the next cup WON pays +50% (consumed win or lose)
  potential?: number // bloodline "star rating" (LOOP_DESIGN Phase 5): a stat-cap multiplier that climbs each breeding generation; absent = 1.0 (wild-caught)
  // Career span extensions (v0.6 economy pass). "Career span" is the years a
  // monster can COMPETE (nothing dies — retirees live on at the ranch).
  comfortWeeks?: number // stable-wide comfort-set bonus, SYNCED from GameState purchases (+8wk per owned item, like licenseIndex)
  wildCap?: number // gen-1 training ceiling, SYNCED stable-wide from the Market Coach (800 → 900 → 1000)
  // Preservation bookkeeping (v0.77) — set while this career sits in the Lab freezer.
  breedCount?: number // children parented so far (max BREED_MAX_CHILDREN)
  studBook?: boolean // a Stud Book is assigned — its record pays weekly fees
  tonicWeeks?: number // Elder Tonic uses on THIS monster (+8wk each, unlimited)
  heritageStat?: Stat // bred child: parent B's major — trains +10% faster
  signature?: Signature // the one EARNED move (annual marquee win) — inherited dormant by children, see signature.ts
  generation?: number // dynasty depth: absent/1 = wild-caught; children = max(parents)+1
  // Fusion monsters (v0.7): aptitude lives PER MONSTER, not the species — the two
  // +20% majors are INHERITED from the two fused parents' majors, plus a rolled
  // +10% minor / −10% flaw. See FUSION_DESIGN.md.
  bonusMajor1?: Stat
  bonusMajor2?: Stat
  bonusMinor?: Stat
  bonusFlaw?: Stat
  tournamentHistory: TournamentResult[]
  log: string[]
}

// Weekly food prices fluctuate around each food's base value, by tier
// (user spec 2026-07-22): basic rations swing ±60% (0.4–1.6×), while training
// and premium foods only discount 10% but can spike +50% (0.9–1.5×) — so the
// good stuff stays reliably expensive and is only occasionally on sale.
export function rollMarket(id: string, week: number): Record<Food, number> {
  const rng = mulberry32(hashString(id + ':mkt:' + week))
  const m = {} as Record<Food, number>
  for (const f of FOODS) {
    const [lo, span] = f.tier === 'normal' ? [0.4, 1.2] : [0.9, 0.6] // normal: 0.4–1.6×; training/premium: 0.9–1.5×
    m[f.id] = Math.max(1, Math.round(f.price * (lo + rng() * span)))
  }
  return m
}

export const foodName = (id: Food) => FOODS.find((f) => f.id === id)!.name

export type WeeklyAction =
  | { kind: 'train'; drillId: string }
  | { kind: 'rest' }
  | { kind: 'excursion' }
  | { kind: 'compete' } // v0.5: entered in a cup/trial — the event IS the week (no training/rest)

// Stamina malus: exp penalty scales with stamina level
export function staminaMalus(stamina: number): number {
  if (stamina > 70) return 1 // no penalty
  if (stamina > 50) return 0.95 // -5%
  if (stamina > 30) return 0.9 // -10%
  return 0.5 // -50%
}

// Training aptitude for a species (user spec 2026-07-23): the 6 base body
// types are migrated to the new authored system — `minor` comes from
// BODY_MINOR (same stat for every species of that body), `major`/`flaw` are
// individually authored per species (Species.trainingProfile). Species
// without an authored profile (the exclusive body types, not yet migrated)
// fall back to the legacy derivation from their base stat spread, reshaped
// into the same {minor, major, flaw} shape (secondary -> minor, primary ->
// major, weakness -> flaw) so every other function only needs one shape.
export function trainingProfileFor(species: Species): TrainingProfile {
  if (species.trainingProfile) {
    return { minor: BODY_MINOR[species.body], ...species.trainingProfile } as TrainingProfile
  }
  const ordered = [...STATS].sort((a, b) => species.base[b] - species.base[a])
  return { major: ordered[0], minor: ordered[1], flaw: ordered[STATS.length - 1] }
}

// Stat training bonus: major +20%, minor +10%, flaw -20%. Fusion species carry
// a SECOND major (major2, also +20%) — their dual-major training identity.
// Prestige bodies (Draconic/Abyssal) get only a GENTLE -5% flaw (v0.85) — a
// legendary creature has no true weak stat; Mythical carry no flaw at all
// (authored with major only), so this branch never fires for them.
export const PRESTIGE_FLAW_PENALTY = 0.95
export function statTrainingBonus(species: Species, stat: Stat): number {
  const prof = trainingProfileFor(species)
  if (stat === prof.major) return 1.2
  if (stat === prof.minor) return 1.1
  if (stat === prof.flaw) return isPrestigeBody(species.body) ? PRESTIGE_FLAW_PENALTY : 0.8
  return 1
}

// Intensive drills' paired malus hits harder when it lands on the species'
// training FLAW (user spec 2026-07-22, term renamed 2026-07-23): flaw stats
// already train 20% slower, so losing one to a malus should sting more too,
// not just gain less. Major/minor/neutral maluses are unaffected.
export function statMalusMultiplier(species: Species, stat: Stat): number {
  if (stat !== trainingProfileFor(species).flaw) return 1
  return isPrestigeBody(species.body) ? 1 : 1.5 // prestige flaws are gentle — no amplified malus
}

// Excursion gold ceiling per league. Deliberately kept BELOW cup 1st-place gold
// (which was raised further in v0.71) so downtime income never rivals real
// competition — this table is now tuned independently of the cup rewards, and
// nudged up slightly per league (v0.71) as part of the small economy pass.
export const LEAGUE_TOP_GOLD: Record<string, number> = {
  Wood: 110, Copper: 165, Tin: 220, Bronze: 280, Iron: 340,
  Silver: 520, Gold: 580, Platinum: 640, Masters: 700, 'Tamer Elite': 760, 'Tamers Apex': 820,
}
const EXCURSION_CAP_FRACTION = 0.4 // 1/3 → 0.4 (v0.71): a very slight downtime-income bump

// Excursion purse: scales by the monster's current league, skewed toward the
// bottom of its range (squared roll — "more likely to give the bottom end",
// a placeholder for a future excursion minigame per user spec 2026-07-22).
// Single rng() draw, same call-order contract as previewWeekEffects.
export function excursionGold(rng: RNG, licenseIndex: number): number {
  const league = LEAGUES[licenseIndex]?.name ?? 'Wood'
  const cap = Math.max(10, Math.round((LEAGUE_TOP_GOLD[league] ?? LEAGUE_TOP_GOLD.Wood) * EXCURSION_CAP_FRACTION))
  const floor = Math.max(5, Math.round(cap * 0.15))
  return floor + Math.round(rng() * rng() * (cap - floor))
}

export interface WeekPreview {
  happinessDelta: number // feedDelta if food chosen, else the -1 unfed penalty
  statDeltas: Partial<Record<Stat, number>> // per-stat gain (+) or drill malus (-)
  staminaDelta: number // rest gain (+) or drill/excursion cost (-), clamped to [0, MAX]
  goldDelta: number // excursion purse — 0 for every other activity
  hpDelta: number // rest healing (30-70% of max, capped) — 0 for other activities
  mpDelta: number // rest mana recovery (25-80% of max, capped) — 0 for other activities
}

// A drill's positive gain is a happiness-weighted random roll, not a flat
// number (user spec 2026-07-19): the roll ranges ±1/3 of the drill's base
// gain, and `happiness` skews it toward the top of that range — 0 happiness
// rolls uniformly, 10 happiness leans hard toward the ceiling. Combined with
// the existing aptitude multiplier (statTrainingBonus, applied after this
// roll), a favoured stat at high happiness can exceed the old flat number —
// intentionally not advertised as a stated max anywhere in the UI. Malus
// values stay flat/unscaled, as before — only positive gains roll.
// Deterministic per (monster, week) via the caller's seeded `rng`, so the
// review screen's preview can show the EXACT roll, not just an estimate.
function rollDrillGain(rng: RNG, base: number, happiness: number): number {
  const range = Math.round(base / 3)
  const skew = 1 / (1 + happiness / 5) // 1 = uniform (happiness 0) → 1/3 = top-skewed (happiness 10)
  const t = Math.pow(rng(), skew)
  return base - range + Math.round(t * range * 2)
}

// Preview what applyWeek would do THIS week, without mutating state — mirrors
// its training + feeding math exactly (same seeded rng as applyWeek, so the
// roll shown IS the roll that will land) so the Ranch screen can show the
// happiness swing and exact stat gains/maluses before the player commits.
// Training gear (v0.6, peddler-sold): +5% per owned tier of that stat's gear
// line, up to +25%. Heritage stat (bred children): +10% on parent B's major.
// One shared multiplier so applyWeek and the preview can never drift.
export type GearTiers = Partial<Record<Stat, number>>
export function gearHeritageMult(c: { heritageStat?: Stat; bonusMajor1?: Stat; bonusMajor2?: Stat; bonusMinor?: Stat; bonusFlaw?: Stat }, gear: GearTiers, stat: Stat): number {
  return (1 + 0.05 * (gear[stat] ?? 0)) // peddler training gear (+5%/tier)
    * (c.heritageStat === stat ? 1.1 : 1) // bred child heritage (+10%)
    * (c.bonusMajor1 === stat ? 1.2 : 1) // fusion inherited major from parent A (+20%)
    * (c.bonusMajor2 === stat ? 1.2 : 1) // fusion inherited major from parent B (+20%)
    * (c.bonusMinor === stat ? 1.1 : 1) // fusion per-monster minor (+10%)
    * (c.bonusFlaw === stat ? 0.9 : 1) // fusion per-monster flaw (−10%)
}

export function previewWeekEffects(c: Career, activity: string, food: Food | '', forage = false, gear: GearTiers = {}): WeekPreview {
  // Food resolves BEFORE the activity in the real tick (buyFood/forageFeed run
  // first), so the preview establishes post-feed happiness + stamina baselines,
  // then runs the activity off them — matching applyWeek exactly. Forage is the
  // free fallback: fixed stamina + happiness cost, no training boost.
  const fed = forage || !!food
  const foodHap = forage ? -FORAGE_HAPPINESS_COST : food ? foodHappinessDelta(c, food) : -1 // -1 = the unfed hunger penalty
  const foodStam = forage ? -FORAGE_STAMINA_COST : food ? foodStaminaDelta(food) : 0
  let happinessDelta = foodHap
  const statDeltas: Partial<Record<Stat, number>> = {}
  let staminaDelta = foodStam !== 0 ? Math.max(0, Math.min(MAX_STAMINA, c.stamina + foodStam)) - c.stamina : 0
  let goldDelta = 0
  let hpDelta = 0
  let mpDelta = 0
  if (c.retired) return { happinessDelta, statDeltas, staminaDelta, goldDelta, hpDelta, mpDelta }
  const startStam = Math.max(0, Math.min(MAX_STAMINA, c.stamina + foodStam)) // stamina the activity starts from
  const postFeedHappiness = fed ? Math.max(0, Math.min(MAX_HAPPINESS, c.happiness + foodHap)) : c.happiness
  const rng = mulberry32(hashString(c.id + ':' + c.week))
  const drill = ALL_DRILLS.find((d) => d.id === activity)
  if (drill) {
    const cap = statCapFor(c) // bloodline potential lifts the training ceiling (Phase 5)
    const { trainMult } = stageInfo(c.ageWeeks, careerSpanYears(c))
    // stamina malus reads the POST-feed stamina (a Vigor Melon can lift you out
    // of the fatigue bracket before you train)
    const eff = trainMult * staminaMalus(startStam)
    for (const [stat, delta] of Object.entries(drill.gains) as [Stat, number][]) {
      const applied = delta > 0
        ? Math.round(rollDrillGain(rng, delta, postFeedHappiness) * eff * statTrainingBonus(c.species, stat) * foodTrainMult(food, stat) * gearHeritageMult(c, gear, stat))
        : Math.round(delta * statMalusMultiplier(c.species, stat))
      const nv = Math.max(1, Math.min(cap, c.stats[stat] + applied))
      const real = nv - c.stats[stat]
      if (real !== 0) statDeltas[stat] = real
    }
    const stamCost = drillStamina(drill.kind)
    staminaDelta = Math.max(0, startStam - stamCost) - c.stamina
    // Mirror applyWeek's growth top-up exactly (2026-07-25): raised max HP/MP
    // raises current by the same amount; a malus that SHRINKS max clamps
    // current down — same formula both sides, so the preview stays exact.
    const newStats = { ...c.stats }
    for (const [stat, d] of Object.entries(statDeltas) as [Stat, number][]) newStats[stat] += d
    hpDelta = Math.max(1, Math.min(c.hp + Math.max(0, maxHp(newStats) - maxHp(c.stats)), maxHp(newStats))) - c.hp
    mpDelta = Math.max(0, Math.min(c.mp + Math.max(0, maxMana(newStats) - maxMana(c.stats)), maxMana(newStats))) - c.mp
  } else if (activity === 'rest') {
    // same rng call ORDER as applyWeek's rest branch: stamina, then heal, then mana
    const restMin = Math.round(0.3 * MAX_STAMINA)
    const restMax = Math.round(1 * MAX_STAMINA)
    const restAmount = restMin + Math.floor(rng() * ((restMax - restMin) / 5 + 1)) * 5
    staminaDelta = Math.min(MAX_STAMINA, startStam + restAmount) - c.stamina
    const healAmt = Math.round(maxHp(c.stats) * (0.3 + rng() * 0.4))
    const mpAmt = Math.round(maxMana(c.stats) * (0.25 + rng() * 0.55))
    hpDelta = Math.min(maxHp(c.stats), c.hp + healAmt) - c.hp
    mpDelta = Math.min(maxMana(c.stats), c.mp + mpAmt) - c.mp
  } else if (activity === 'excursion') {
    staminaDelta = Math.max(0, startStam - EXCURSION_COST) - c.stamina
    goldDelta = excursionGold(rng, c.licenseIndex)
    // mirror applyWeek's +1 happiness exactly, including the cap (feeding
    // resolves first, so the bonus applies on top of the post-feed value)
    const afterFood = postFeedHappiness
    happinessDelta += Math.min(MAX_HAPPINESS, afterFood + 1) - afterFood
  }
  return { happinessDelta, statDeltas, staminaDelta, goldDelta, hpDelta, mpDelta }
}

export interface NewCareerOpts {
  id?: string // stable-unique id (defaults to the generation seed)
  ageWeeks?: number // fusion babies start at 0 (Baby)
  stats?: Stats // override seed stats (fusion averages the parents)
  licenseIndex?: number
  happiness?: number
  potential?: number // bloodline star rating (bred monsters inherit + climb it)
  gen?: GenOptions // generation overrides (market scout/coach, prestige-free strays)
}

// The effective stat ceiling for a career: the league cap, lifted by the
// monster's bloodline potential (LOOP_DESIGN Phase 5). Wild-caught monsters
// (potential absent) get the plain league cap, so nothing changes for them —
// and generation/battle never consult this, only career training does.
// Gen-1 ceilings — the v0.87 interlocking cap ladder (user spec). A monster you
// did not BREED is walled; breeding (gen 2+) is the only way past, and its
// potential then sets the ceiling. The Market Coach is now a UNIVERSAL quality
// upgrade: it lifts wild AND prestige walls (by tier), so the ladder reads
//
//                no coach   coach T1   coach T2
//   wild/market     700        800        900
//   Dra/Abyssal     800        900        950
//   Mythical        900        950       1000
//   fusion (gen 1)      1000 flat — the crafted body
//   PRIMEVAL (gen 1)    1100 flat — the prestige fusion outranks everything
//                                   gen-1, the only one above the TE league cap
//
// Only fusion and a fully-coached Mythical reach 1000, and only a Primeval goes
// past it; everything else gen-1 falls short of the Tamer Elite cap, so the top
// of the ladder still belongs to bred dynasties (league cap × potential). The
// coach tier is derived from the synced `wildCap` (700/800/900 — always
// stable-wide, re-synced on load).
export const FUSION_GEN1_CAP = 1000
export const PRIMEVAL_GEN1_CAP = 1100
export const WILD_GEN1_CAP = 700
export const PRESTIGE_GEN1_CAPS: Partial<Record<string, [number, number, number]>> = {
  Draconic: [800, 900, 950], Abyssal: [800, 900, 950], Mythical: [900, 950, 1000],
}
export function statCapFor(c: { licenseIndex: number; potential?: number; species?: Species; generation?: number; wildCap?: number }): number {
  const base = LEAGUES[c.licenseIndex].cap * (c.potential ?? 1)
  const gen1 = (c.generation ?? 1) <= 1
  if (gen1 && c.species?.body === 'Primeval') return Math.round(Math.min(base, PRIMEVAL_GEN1_CAP))
  if (gen1 && c.species && isFusionBody(c.species.body)) return Math.round(Math.min(base, FUSION_GEN1_CAP))
  if (gen1 && c.species && isPrestigeBody(c.species.body)) {
    const coachTier = Math.max(0, Math.min(2, Math.round(((c.wildCap ?? WILD_GEN1_CAP) - WILD_GEN1_CAP) / 100)))
    const caps = PRESTIGE_GEN1_CAPS[c.species.body]
    return Math.round(Math.min(base, caps ? caps[coachTier] : FUSION_GEN1_CAP))
  }
  if (gen1) return Math.round(Math.min(base, c.wildCap ?? WILD_GEN1_CAP))
  return Math.round(base)
}

// Create a raising Career. Stats/species/name come from `seed`; `opts.id` lets the
// Market give a bought monster a stable-unique id while keeping the previewed
// monster (same seed). Fusion passes ageWeeks:0 + averaged stats for a baby.
export function newCareer(seed: string, opts: NewCareerOpts = {}): Career {
  const m = generateMonster(seed, { train: 0, ...opts.gen })
  const id = opts.id ?? seed
  return {
    id,
    name: m.name,
    species: m.species,
    sex: m.sex,
    favouriteFood: m.favouriteFood,
    hatedFood: m.hatedFood,
    stats: opts.stats ? { ...opts.stats } : { ...m.stats },
    ageWeeks: opts.ageWeeks ?? START_AGE_WEEKS,
    hp: maxHp(opts.stats ?? m.stats),
    mp: maxMana(opts.stats ?? m.stats),
    stamina: MAX_STAMINA,
    happiness: opts.happiness ?? 5,
    licenseIndex: opts.licenseIndex ?? 0,
    potential: opts.potential,
    week: 0,
    retired: false,
    fedThisWeek: false,
    loadout: [],
    activeInnate: 0,
    tournamentHistory: [],
    log: [`${m.name} the ${m.species.name} (${m.sex === 'M' ? '♂' : '♀'}) joins your stable — a Wood-league hopeful.`],
  }
}

// --- Shared food-effect math (2026-07-25 overhaul) — one source of truth so
// the real weekly tick (buyFood + applyWeek) and the preview can never drift.

// Happiness a food grants THIS week. Training/premium foods carry a FIXED value
// (ignoring taste); normal foods use taste (feedDelta). Satiety: feeding the
// SAME food two weeks running halves a POSITIVE gain (floored) — a bored
// monster enjoys the repeat less. Negative/zero deltas are unaffected.
export function foodHappinessDelta(c: Career, food: Food): number {
  const def = foodDef(food)
  const raw = def.happiness !== undefined ? def.happiness : feedDelta(food, c.favouriteFood, c.hatedFood)
  if (raw > 0 && c.lastFood === food) return Math.floor(raw / 2)
  return raw
}
export const foodStaminaDelta = (food: Food): number => foodDef(food).stamina ?? 0
// Training multiplier a food applies to a drill's positive gain for `stat`
// (1 = no boost). '' (no food) is always 1.
export function foodTrainMult(food: Food | '', stat: Stat): number {
  if (!food) return 1
  const def = foodDef(food)
  return def.boostStats?.includes(stat) ? 1 + (def.boostMult ?? 0) : 1
}

// Buy one food from this week's town food market. Does NOT advance the week —
// feeding is a start-of-week choice, resolved BEFORE the weekly activity. Gold is
// game-owned, so it's passed in and returned; `discount` is the bulk-food perk.
export function buyFood(c: Career, gold: number, food: Food, market: Record<Food, number>, discount = 1): { c: Career; gold: number } {
  if (c.retired || c.fedThisWeek) return { c, gold }
  const price = Math.max(1, Math.round(market[food] * discount))
  if (gold < price) return { c: push(c, `Wk ${c.week + 1}: can't afford ${foodName(food)} (${price}g).`), gold }
  const def = foodDef(food)
  const d = foodHappinessDelta(c, food) // reads c.lastFood (the PREVIOUS food) for satiety before we overwrite it
  const happiness = Math.max(0, Math.min(MAX_HAPPINESS, c.happiness + d))
  const stamina = Math.max(0, Math.min(MAX_STAMINA, c.stamina + foodStaminaDelta(food)))
  const n: Career = {
    ...c, happiness, stamina, fedThisWeek: true, lastFood: food,
    truffleReady: def.rewardMult ? true : c.truffleReady,
    log: [...c.log],
  }
  const bits = [d !== 0 ? `Happiness ${happiness}/10${d > 0 ? ' ♥' : ' ✖'}` : '', def.stamina ? `stamina ${stamina}/${MAX_STAMINA}` : '', def.rewardMult ? '🟡 cup reward primed' : ''].filter(Boolean).join(' · ')
  return {
    c: push(n, `Wk ${c.week + 1}: fed ${foodName(food)} (−${price}g).${bits ? ' ' + bits + '.' : ''}`),
    gold: gold - price,
  }
}

// Forage (user spec): the free fallback when the player can't afford ANY food —
// the monster feeds itself for the week (satisfies the food gate, no gold spent)
// but it's tiring and joyless. Costs stamina + happiness; grants no training
// boost (like eating nothing special). Mirrored in previewWeekEffects.
export const FORAGE_STAMINA_COST = 25
export const FORAGE_HAPPINESS_COST = 2
export function forageFeed(c: Career): Career {
  if (c.retired || c.fedThisWeek) return c
  const happiness = Math.max(0, Math.min(MAX_HAPPINESS, c.happiness - FORAGE_HAPPINESS_COST))
  const stamina = Math.max(0, Math.min(MAX_STAMINA, c.stamina - FORAGE_STAMINA_COST))
  return {
    ...c, happiness, stamina, fedThisWeek: true, lastFood: undefined,
    log: [...c.log, `Wk ${c.week + 1}: foraged for the week — tiring and joyless, but fed (no gold spent).`].slice(-40),
  }
}

// Derive a display Monster from the career's current state. Uses the
// player's persisted `loadout` (Ability Selection UI) when set and still
// valid; falls back to auto-pick (chooseLoadout) otherwise — including the
// edge case where a drill malus dropped a stat below a move's learnLevel,
// silently shrinking the persisted loadout below 3.
export function careerMonster(c: Career): Monster {
  // A signature joins the learned pool rather than sitting beside it, so it
  // competes for one of the three loadout slots exactly like a pool move (user
  // spec) — and every downstream consumer (ability selector, auto-pick, the
  // battle engine) needs no knowledge of signatures at all.
  const sigMove = c.signature ? signatureMove(c.signature) : null
  const learned = sigMove ? [...learnedMoves(c.stats), sigMove] : learnedMoves(c.stats)
  const persisted = c.loadout
    .map((id) => learned.find((mv) => mv.id === id))
    .filter((mv): mv is Move => !!mv)
  const loadout = persisted.length > 0 ? persisted : chooseLoadout(learned, c.stats)
  const maxStat = Math.max(...STATS.map((s) => c.stats[s]))
  const innateUnlocked = maxStat >= INNATE_SECONDARY_LEVEL
  return {
    seed: c.id,
    name: c.name,
    species: c.species,
    sex: c.sex,
    stats: c.stats,
    className: classForStats(c.stats),
    league: LEAGUES[c.licenseIndex].name,
    learned,
    loadout,
    innateUnlocked,
    // 2nd choice reverts to the 1st if its unlock stat was since trained down
    // (an intensive-drill malus, say) — same shrink-safety as the loadout.
    activeInnate: innateUnlocked ? c.activeInnate : 0,
    tactics: c.tactics,
    favouriteFood: c.favouriteFood,
    hatedFood: c.hatedFood,
    stamina: c.stamina,
    hp: Math.min(c.hp, maxHp(c.stats)),
    mp: Math.min(c.mp, maxMana(c.stats)),
    // Care-derived instinct (roadmap item, player half): a well-kept monster
    // obeys perfectly (happiness 10 → tameness 100, zero wild actions); a
    // neglected one gets flighty (happiness 0 → 90 → 10% chance per turn of a
    // random action in battle). HIDDEN — never shown in any UI, only felt.
    tameness: 90 + c.happiness,
  }
}

export function canRankUp(c: Career): boolean {
  if (c.licenseIndex >= LEAGUES.length - 1) return false
  const cap = LEAGUES[c.licenseIndex].cap
  return Math.max(...STATS.map((s) => c.stats[s])) >= cap - 10
}

// rankUpFee/rankUp are GONE (v0.5): promotion is per-PLAYER — win the on-demand
// trial (town.ts:startTrial) then buy the license (town.ts:buyLicense).
// canRankUp (above) survives as the per-monster "champion-ready" indicator.

function push(c: Career, line: string): Career {
  return { ...c, log: [...c.log, line].slice(-40) }
}

// Log a life-stage transition (shared by applyWeek and ageOneWeek). Mutates `n`.
function applyStageTransition(n: Career, beforeStage: Stage): void {
  const nowStage = stageInfo(n.ageWeeks, careerSpanYears(n)).stage
  if (nowStage === beforeStage) return
  if (nowStage === 'Retiree') {
    n.retired = true
    n.log.push(`🏁 ${n.name} has reached retirement age and can no longer compete.`)
  } else {
    n.log.push(`  ↳ ${n.name} is now ${nowStage}${nowStage === 'Elder' ? ' (−20% training)' : nowStage === 'Fully Grown' ? ' (−5% training)' : ''}.`)
  }
}

// Advance the calendar for a monster that took no weekly action (retired, or no
// plan submitted) — it still ages.
export function ageOneWeek(c: Career): Career {
  const before = stageInfo(c.ageWeeks, careerSpanYears(c)).stage
  const n: Career = { ...c, week: c.week + 1, ageWeeks: c.ageWeeks + 1, fedThisWeek: false, log: [...c.log] }
  applyStageTransition(n, before)
  n.log = n.log.slice(-40)
  return n
}

export function applyWeek(c: Career, action: WeeklyAction, gold: number, rental = 0, food: Food | '' = '', gear: GearTiers = {}): { c: Career; gold: number } {
  if (c.retired) return { c, gold }
  let g = gold
  const n: Career = { ...c, stats: { ...c.stats }, log: [...c.log] }
  const rng = mulberry32(hashString(c.id + ':' + c.week))
  const cap = statCapFor(c) // bloodline potential lifts the training ceiling (Phase 5)
  const { stage, trainMult } = stageInfo(c.ageWeeks, careerSpanYears(c))
  const beforeMoves = learnedMoves(c.stats).length
  const wk = c.week + 1

  if (action.kind === 'train') {
    const drill = ALL_DRILLS.find((d) => d.id === action.drillId) ?? ALL_DRILLS[0]
    const stamCost = drillStamina(drill.kind)
    const malus = staminaMalus(n.stamina)
    const eff = trainMult * malus
    const changes: string[] = []
    for (const [stat, delta] of Object.entries(drill.gains) as [Stat, number][]) {
      // positive gains roll (happiness-weighted, see rollDrillGain), then scale by
      // life stage, stamina, and species aptitude; drill maluses apply flat
      // Training foods (2026-07-25) multiply the positive gain for their
      // stat-pair (foodTrainMult); maluses are unaffected.
      const applied = delta > 0
        ? Math.round(rollDrillGain(rng, delta, n.happiness) * eff * statTrainingBonus(c.species, stat) * foodTrainMult(food, stat) * gearHeritageMult(c, gear, stat))
        : Math.round(delta * statMalusMultiplier(c.species, stat))
      const nv = Math.max(1, Math.min(cap, n.stats[stat] + applied))
      const real = nv - n.stats[stat]
      n.stats[stat] = nv
      if (real !== 0) changes.push(`${stat} ${real > 0 ? '+' : ''}${real}`)
    }
    n.stamina = Math.max(0, n.stamina - stamCost)
    n.log.push(`Wk ${wk}: ${drill.name} — ${changes.length > 0 ? changes.join(', ') : 'no gain (capped)'}.`)
  } else if (action.kind === 'compete') {
    // Competing IS the week (v0.5): no training, no rest recovery — the cup or
    // trial (resolved after activities in advanceWeek) is what this week was for.
    n.log.push(`Wk ${wk}: competed in the arena.`)
  } else if (action.kind === 'rest') {
    const restMin = Math.round(0.3 * MAX_STAMINA)
    const restMax = Math.round(1 * MAX_STAMINA)
    const restAmount = restMin + Math.floor(rng() * ((restMax - restMin) / 5 + 1)) * 5
    n.stamina = Math.min(MAX_STAMINA, n.stamina + restAmount)
    // Rest is also the ONLY way injuries mend: heal 30-70% of max HP and
    // recover 25-80% of max MP (user spec 2026-07-19). Rolls share applyWeek's
    // seeded rng so previewWeekEffects can show the exact numbers.
    const healAmt = Math.round(maxHp(n.stats) * (0.3 + rng() * 0.4))
    const mpAmt = Math.round(maxMana(n.stats) * (0.25 + rng() * 0.55))
    n.hp = Math.min(maxHp(n.stats), n.hp + healAmt)
    n.mp = Math.min(maxMana(n.stats), n.mp + mpAmt)
    n.log.push(`Wk ${wk}: rested. Stamina ${n.stamina}/${MAX_STAMINA} · HP ${n.hp}/${maxHp(n.stats)} · MP ${n.mp}/${maxMana(n.stats)}.`)
  } else {
    n.stamina = Math.max(0, n.stamina - EXCURSION_COST)
    const purse = excursionGold(rng, n.licenseIndex)
    g += purse
    // An outing is fun regardless of the haul (2026-07-25 playtest fix): the
    // bottom-skewed purse made low-league excursions read as a pure trap
    // (+6g for −25 stamina). +1 happiness makes it a deliberate morale tool —
    // the gold stays deliberately modest per the standing "not hugely
    // profitable" spec.
    n.happiness = Math.min(MAX_HAPPINESS, n.happiness + 1)
    n.log.push(`Wk ${wk}: excursion — returned with ${purse}g, spirits high (happiness ${n.happiness}/10).`)
  }

  // hunger: a monster that wasn't fed this week loses a little happiness
  if (!n.fedThisWeek) {
    n.happiness = Math.max(0, n.happiness - 1)
    n.log.push(`  ↳ ${n.name} went unfed — happiness ${n.happiness}/10.`)
  }

  // lab upkeep, advance the calendar, age the monster
  if (rental > 0) {
    g = Math.max(0, g - rental) // upkeep can zero the wallet but never indebt it (v0.6)
    n.log.push(`  ↳ lab upkeep −${rental}g (frozen genomes).`)
  }
  n.week += 1
  n.ageWeeks += 1
  n.fedThisWeek = false
  // Growth heals with it (2026-07-25 playtest fix): when training raises max
  // HP/MP (CON/WIS/INT gains), current rises by the same amount — a monster
  // that just got TOUGHER shouldn't come out of training looking injured
  // (168/220 HP without ever fighting). Stat DROPS still clamp current down.
  const hpMaxGrow = maxHp(n.stats) - maxHp(c.stats)
  const mpMaxGrow = maxMana(n.stats) - maxMana(c.stats)
  if (hpMaxGrow > 0) n.hp += hpMaxGrow
  if (mpMaxGrow > 0) n.mp += mpMaxGrow
  n.hp = Math.max(1, Math.min(n.hp, maxHp(n.stats)))
  n.mp = Math.max(0, Math.min(n.mp, maxMana(n.stats)))

  const afterMoves = learnedMoves(n.stats).length
  if (afterMoves > beforeMoves) n.log.push(`  ↳ learned ${afterMoves - beforeMoves} new move(s)!`)

  // An inherited signature awakens the week its heir finally matches the stat
  // its ancestor had when the move was forged. Consumes NO rng, so applyWeek and
  // previewWeekEffects stay byte-identical — the invariant that keeps the weekly
  // preview exact (see the RNG discipline note in CLAUDE.md).
  if (n.signature && canAwaken(n.signature, n.stats)) {
    n.signature = { ...n.signature, awakened: true }
    n.log.push(`  ★ ${signatureName(n.signature)} AWAKENS — ${n.name} matches ${n.signature.forgedBy}'s ${n.signature.stat} and the bloodline's signature is theirs in full.`)
  }

  applyStageTransition(n, stage)

  n.log = n.log.slice(-40)
  return { c: n, gold: g }
}
