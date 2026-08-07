// Shared game state + the Town hub economy (§13). One gold wallet and one stable
// span all areas; the Ranch (src/game.ts) raises the active monster week by week.
import {
  ActiveCup, BodyType, ClassRole, Food, GAMEPLANS, INNATE_SECONDARY_LEVEL, LEAGUES, MatchOrders, MAX_HAPPINESS, Monster, Rival, RivalPersonality, Sex, Species, Stat, STATS, Stats, TeamGameplan, classForStats, foodDiscountGroup, hashString,
  isFusionBody, isPrestigeBody, mulberry32, roleOfClass,
  Move, StatusKind,
} from './core'
import { SPECIES } from './species'
import { GenOptions, generateMonster, maxHp, maxMana } from './monster'
import { BattleResult, simulateTeamBattle } from './battle'
import {
  Career, MAX_STAMINA, START_GOLD, WEEKS_PER_MONTH, WEEKS_PER_YEAR, WeeklyAction, ageOneWeek, applyWeek, buyFood,
  WILD_GEN1_CAP, careerMonster, careerSpanYears, forageFeed, newCareer, rollMarket, statCapFor, trainingProfileFor,
} from './game'
import { ALL_DRILLS } from './drills'
import { Signature, forgeSignature, inheritSignature, signatureName } from './signature'
import { signatureChoicesFor } from './signatureMoves'
import { learnedMoves } from './monster'

export type Area = 'town' | 'ranch'

// Licensing for exclusive monster types. v0.77: the league requirement was
// previously only COPY — the shop said "Requires Silver league" but nothing
// checked it, so a Wood player with the gold walked straight into Draconics.
// Now the rank gate is real and the price is correspondingly low: reaching the
// league IS the cost, gold is just the receipt.
// v0.89: repriced to the original design values (CLAUDE.md's Body Types section).
// v0.77 cut these to 200/600 on the reasoning that "reaching the league IS the
// cost" — but the sim showed rank arrives with gold to spare, so the gate was
// free in practice and every licensed roster went straight to all-prestige.
export const SPECIAL_LICENSE_COST = 500 // Draconic + Abyssal
export const ELITE_LICENSE_COST = 1200 // Mythical
export const SPECIAL_LICENSE_LEAGUE = 4 // Iron
export const ELITE_LICENSE_LEAGUE = 7 // Platinum

// --- Monster-market upgrades (v0.77) ---------------------------------------
// Three independent levers on the SAME market: slots = more shots per month,
// scout = aim those shots at a species you want, coach = raise the floor of
// what turns up. All applied when the market restocks (start of each month).
export const MARKET_SLOT_COSTS = [50, 100, 150] // 3 buys → base 3 offers becomes 6
export const MARKET_SLOTS_MAX = MARKET_SLOT_COSTS.length
export const marketSlotCost = (g: GameState): number | null => MARKET_SLOT_COSTS[g.marketSlots ?? 0] ?? null

export const MARKET_SCOUT_COSTS = [350, 500] // buy, then upgrade
export const SCOUT_CHANCE = [0, 0.12, 0.2] // per slot, by scout tier (v0.87: 0.15/0.25 → 0.12/0.20 — scouting stays the prestige-hunting tool but lands a touch less often)
export const scoutCost = (g: GameState): number | null => MARKET_SCOUT_COSTS[g.marketScout ?? 0] ?? null

// Prestige market scarcity (v0.87): licensed prestige bodies are rare stock —
// only this fraction of would-be prestige rolls survives (the rest re-roll to
// base species), and a surviving offer carries a price premium. First gentle
// increment, tuned against the long-haul sim.
export const PRESTIGE_MARKET_CHANCE = 0.12
export const PRESTIGE_PRICE_MULT = 1.5

// Market Coach: stock arrives already trained into a league BAND rather than
// wild. Gated on rank (Gold, then Platinum) so it can't front-run progression,
// and each tier adds a flat surcharge to the rolled price — you pay for the
// months of drills you're skipping.
export const MARKET_COACH_COSTS = [300, 750]
export const MARKET_COACH_LEAGUES = [6, 7] // Gold to buy, Platinum to upgrade
export const COACH_SURCHARGE = [0, 100, 250] // added to the rolled price, by tier
// Top-stat band each tier lands in. Tin = 200-300, Iron = 400-500 (leagueForStat
// bands); the low inset sits just inside the boundary and the draw is
// bottom-skewed, so the typical coached monster is a LOW Tin / LOW Iron
// prospect with plenty of training headroom left.
export const COACH_BANDS: [number, number][] = [[0, 0], [205, 295], [405, 495]] // [0] unused — no coach, no override
export const coachCost = (g: GameState): number | null => MARKET_COACH_COSTS[g.marketCoach ?? 0] ?? null
export const coachLeague = (g: GameState): number | null => MARKET_COACH_LEAGUES[g.marketCoach ?? 0] ?? null

export interface Tournament {
  id: string
  name: string
  month: number // 1-12
  week: number // 1-4 — the specific week within the month it's held
  league: string // Wood, Copper, Tin, etc.
  rewards: { gold: number; exp: number }
}

// Calendar (§3): drawn fresh each game year from the seed. Every league from
// Wood through Platinum is GUARANTEED at least one cup per quarter, sometimes
// two, in unpredictable months (never a fixed monthly slot) — repeating these
// is the game's financial backbone, and scarcity makes the calendar worth
// planning around. Masters and Tamer Elite deliberately run at HALF that
// density (user spec 2026-07-25: "all leagues must have a similar number of
// cups until masters. Masters + Tamer elite will have half the number of
// cups") — see ACTIVE_QUARTERS_BY_LEAGUE below. Silver through Tamer Elite
// additionally each get ONE fixed annual marquee "prestige" event (hand-
// authored lore, bigger reward) layered into their own calendar — it occupies
// one league-year slot rather than adding an extra one on top, so total cup
// counts stay comparable across leagues instead of stacking a bonus event
// onto whichever leagues happen to have one. A monster may also enter BELOW
// its league at reduced rewards (§rewardMultiplier).
export const CIRCUIT_REWARDS: Record<string, { gold: number; exp: number }> = {
  // Economy iteration (v0.71): cup gold nudged up, steepening at higher leagues
  // where the roster (and food bill) is bigger. Tuned against the long-haul sim.
  Wood: { gold: 130, exp: 65 },
  Copper: { gold: 195, exp: 98 },
  Tin: { gold: 270, exp: 135 },
  Bronze: { gold: 356, exp: 178 },
  Iron: { gold: 454, exp: 227 },
}

// The "regular" (non-marquee) cup reward for the 5 leagues that ALSO run one
// fixed annual marquee event — continues CIRCUIT_REWARDS' exact +50g/+25exp
// per league step, so a Silver pool cup feels like a natural continuation of
// the circuit ladder rather than a discontinuity. The marquee's own reward
// (PRESTIGE_EVENTS below) is deliberately bigger, so it still feels special.
export const PRESTIGE_POOL_REWARDS: Record<string, { gold: number; exp: number }> = {
  Silver: { gold: 540, exp: 270 },
  Gold: { gold: 637, exp: 319 },
  Platinum: { gold: 745, exp: 373 },
  Masters: { gold: 864, exp: 432 },
  'Tamer Elite': { gold: 994, exp: 497 },
  'Tamers Apex': { gold: 1140, exp: 570 },
}

// Event names (user spec 2026-07-20): never named after a month, unique within
// a league's year, and the tone climbs the ladder — Wood sounds like a village
// scrap ("The Sprout Cup"), Iron already sounds like a real championship.
const CIRCUIT_EVENT_NAMES: Record<string, string[]> = {
  Wood: ['The Sprout Cup', 'Twig Tussle', 'The Mulch Pit', 'Acorn Scramble', 'Sawdust Scuffle', 'The Woodshed Brawl', 'Kindling Clash', 'Stump Jamboree', 'The Knothole Open', 'Bramble Bash', 'Sapling Skirmish', 'The Splinter Scrap'],
  Copper: ['The Copper Pots', 'Kettle Cup', 'The Penny Purse', 'Scullery Scrap', 'The Green Kettle', 'Patina Punch-Up', 'Tinker Town Trophy', 'The Verdigris Vase'],
  Tin: ['Tin Daggers', 'The Tin Whistle', 'Foil Fracas', 'Canteen Clash', "The Tinsmith's Trophy", 'Pewter Mug Melee', 'Rattlecan Rumble', 'The Solder Circuit'],
  Bronze: ['The Bronze Bell', 'Statuary Showdown', "Gladiator's Gong", 'The Laurel Bout', 'Medalist Melee', "The Founder's Cast", 'Old Verdant Trophy', 'The Standard-Bearer'],
  Iron: ['The Anvil Championship', 'Hammerfall Cup', 'The Forge Trials', 'Ironclad Open', "The Smelter's Stand", 'Blackfurnace Bout', 'The Iron Gauntlet', 'Quenchfire Classic'],
}

// Pool-cup name lists for the 5 marquee-bearing leagues (2026-07-25) — same
// role as CIRCUIT_EVENT_NAMES, just for the "regular" cups that fill out the
// rest of these leagues' calendar alongside their one fixed marquee event.
// Distinct strings from the marquee names (Silver Crescent, Gilded Crown,
// etc.) so nothing ever collides in the same year.
const PRESTIGE_POOL_NAMES: Record<string, string[]> = {
  Silver: ['The Quicksilver Open', 'Sterling Cup', 'The Moonlit Melee', 'Argent Trials', 'The Hallmark Bout', 'Frostplate Championship', 'The Mercury Clash', 'The Silver Standard'],
  Gold: ['The Sovereign Cup', 'Bullion Brawl', 'The Sunforge Championship', 'Treasury Trials', 'The Gold Standard Open', 'Aurum Ascendant', 'The Ducat Clash', 'The Midas Reckoning'],
  Platinum: ['The Platinum Vanguard', 'Diamond Point Open', 'The Adamant Trials', 'Starforge Championship', 'The Prism Cup', 'Luminous Classic', 'The Zenith Brawl', 'Crystalline Clash'],
  Masters: ["The Sovereign's Gauntlet", "Champion's Reckoning", 'The Undefeated Cup', 'Legacy Trials', "The Ascendant's Bout", 'Crownless Championship', 'The Elder Circuit', 'Masterwork Melee'],
  'Tamer Elite': ['The Zenith Accord', 'Pinnacle Proving', 'The Ultimatum Cup', 'Peerless Championship', 'The Reckoning', 'Ascendancy Trials', 'The Final Word', 'The Undisputed'],
  'Tamers Apex': ['The Eternal Throne', 'Apotheosis Trials', 'The Last Ascent', 'Godsblood Classic', 'The Immortal Round', 'Dynasty Everlasting', 'The Summit Beyond', 'Firstborn Championship'],
}

// Marquee rewards bumped 2026-07-25 (were 350/400/450/500/600) to stay
// clearly bigger than PRESTIGE_POOL_REWARDS for the same league — otherwise
// a Silver pool cup and the Silver Crescent would pay identically, and the
// "marquee" framing (hand-authored lore, once-a-year) would feel hollow.
export const PRESTIGE_EVENTS: Omit<Tournament, 'id'>[] = [
  { name: 'The Silver Crescent', month: 6, week: 2, league: 'Silver', rewards: { gold: 702, exp: 351 } },
  { name: 'The Gilded Crown', month: 7, week: 2, league: 'Gold', rewards: { gold: 821, exp: 411 } },
  { name: 'The Radiant Throne', month: 8, week: 2, league: 'Platinum', rewards: { gold: 950, exp: 475 } },
  { name: "The Grandmasters' Summit", month: 9, week: 2, league: 'Masters', rewards: { gold: 1091, exp: 546 } },
  { name: 'The Apex Invitational', month: 10, week: 2, league: 'Tamer Elite', rewards: { gold: 1242, exp: 621 } },
  { name: 'The Dynasty Eternal', month: 12, week: 2, league: 'Tamers Apex', rewards: { gold: 1425, exp: 713 } },
]

// Cup lore (user spec 2026-07-22): a pre-cup preamble (prize money + a line of
// setting/lore tied to the cup's name) and a post-cup closing flavour line.
// Hybrid sourcing — hand-authored for the fixed annual prestige events (seen
// once a year, worth the writing), templated from a per-league flavour table
// for the circuit cups (Wood-Iron regenerate a new name every game-year, seen
// far more often, not worth authoring individually).
export interface CupLore { intro: string; outroFlavour: string }

const PRESTIGE_LORE: Record<string, CupLore> = {
  'The Silver Crescent': {
    intro: 'An invitational older than the town itself, held under a banner of hammered silver shaped like a waning moon. Legend says the first Crescent was fought to settle a dispute between two tamers who refused to just talk it out.',
    outroFlavour: 'The crescent banner is lowered for another year, its silver a little more tarnished, its legend a little longer.',
  },
  'The Gilded Crown': {
    intro: "The season's marquee event — every League office in the region sends a scout, and the winner's monster gets its likeness cast onto next year's entry medallion.",
    outroFlavour: 'Gold dust settles over the arena floor as the crown is presented — already, whispers of next year\'s favourites begin.',
  },
  'The Radiant Throne': {
    intro: 'A single ornate throne sits at the centre of the arena, empty until the final bout — only the realm\'s best ever get to stand beside it, let alone claim it.',
    outroFlavour: 'The throne is claimed for another year. The rest of the field files out past it, already plotting their return.',
  },
  "The Grandmasters' Summit": {
    intro: "Where every League's reigning champions finally meet on equal ground — no punching down, no easy brackets, just the best against the best.",
    outroFlavour: 'The Summit disperses, its champions scattering back to their home leagues to defend what they nearly lost here.',
  },
  'The Apex Invitational': {
    intro: 'There is nothing above this. The Apex answers only one question: of everyone who has ever climbed this far, who climbs highest.',
    outroFlavour: 'The Apex falls silent. For one team, there is nowhere left to climb — for everyone else, the climb starts again.',
  },
}

const CIRCUIT_LORE_FLAVOUR: Record<string, { setting: string; closer: string }> = {
  Wood: { setting: 'a muddy paddock behind the tannery, more scrap than sport', closer: 'The paddock empties out, mud-caked and already half-forgotten — until next quarter.' },
  Copper: { setting: 'the market square, pots and pans still rattling loose from last year\'s brawl', closer: 'Stallholders sweep up the mess and reopen for business by morning.' },
  Tin: { setting: 'a proper ring at last — canvas ropes, and a crowd that actually paid to get in', closer: 'The ropes come down for storage, already a little worse for wear.' },
  Bronze: { setting: "a real arena, cast in the town's own bronze bell-metal", closer: 'The bell-metal seats empty slowly, the bronze still warm from the crowd.' },
  Iron: { setting: "the forge-district's own championship, judged by smiths who don't impress easily", closer: 'The forge fires bank low for the night — the smiths, for once, look impressed.' },
}

// A tournament's pre-cup preamble + post-cup closing flavour.
export function cupLore(t: Tournament): CupLore {
  const authored = PRESTIGE_LORE[t.name]
  if (authored) return authored
  const f = CIRCUIT_LORE_FLAVOUR[t.league] ?? CIRCUIT_LORE_FLAVOUR.Wood
  return {
    intro: `${t.name} — ${f.setting}. On the line: ${t.rewards.gold}g and bragging rights across the ${t.league} circuit.`,
    outroFlavour: f.closer,
  }
}

// Team size per league (user spec 2026-07-21, amended 2026-07-25 and 2026-08-01):
// only Wood is a solo duel — Copper steps straight to 2v2, then the ladder climbs
// in even pairs to a ceiling of FIVE.
//
// ⚠️ 6v6 IS REMOVED FROM THE GAME (user spec 2026-08-01). It had been the summit
// leagues' exclusive spectacle. Measured with `compAtSize` — the same pairing at
// both sizes, same league, same seeds, median of 8 — a sixth body makes fights
// SHORTER, not grander:
//
//   Gold      Vanguard v Choir   5v5 42.4s   6v6 27.2s   -15.2s
//   Gold      Phalanx mirror     5v5 59.7s   6v6 33.1s   -26.6s
//   Platinum  Phalanx mirror     5v5 46.3s   6v6 34.9s   -11.4s
//   Masters   Vanguard v Choir   5v5 47.3s   6v6 41.1s    -6.2s
//
// More bodies means more damage on the field and a faster cascade once the first
// one drops. The top league's showpiece fight was its quickest.
//
// ⚠️ THE LADDER NOW PLATEAUS AT PLATINUM — Platinum, Masters, Tamer Elite and
// Tamers Apex all field 5. Progression past Platinum is stat cap and roster
// quality, no longer team size. That is a real loss of a progression axis and is
// worth replacing with something at the summit rather than leaving flat.
export const TEAM_SIZE_BY_LEAGUE: Record<string, number> = {
  Wood: 1, Copper: 2, Tin: 2, Bronze: 3, Iron: 3, Silver: 4, Gold: 4, Platinum: 5, Masters: 5, 'Tamer Elite': 5, 'Tamers Apex': 5,
}
export const teamSizeForLeague = (league: string): number => TEAM_SIZE_BY_LEAGUE[league] ?? 1

// Non-player team count per event (user's own words: "always ≥3, sometimes
// 4/5" — exact boundaries weren't specified, this is a single tunable table).
export const RIVAL_TEAM_COUNT_BY_LEAGUE: Record<string, number> = {
  Wood: 3, Copper: 3, Tin: 3, Bronze: 3, Iron: 3, Silver: 4, Gold: 4, Platinum: 5, Masters: 5, 'Tamer Elite': 5, 'Tamers Apex': 5,
}
export const rivalTeamCountForLeague = (league: string): number => RIVAL_TEAM_COUNT_BY_LEAGUE[league] ?? 3

// Round-robin reward scales by the player's FINAL PLACEMENT (replaces the old
// strict win/lose-only gate) — 4th place or worse earns nothing.
export const PLACEMENT_REWARD_FRACTION: Record<number, number> = { 1: 1, 2: 0.65, 3: 0.4 }
export const placementRewardFraction = (placement: number): number => PLACEMENT_REWARD_FRACTION[placement] ?? 0
export const placementLabel = (placement: number): string => {
  if (placement === 1) return '1st'
  if (placement === 2) return '2nd'
  if (placement === 3) return '3rd'
  return `${placement}th`
}

export const yearOfWeek = (week: number) => Math.floor(week / WEEKS_PER_YEAR)

// Every league's regular ("pool") cup reward + name list in one place, so the
// generator below doesn't need to know Wood-Iron and Silver-TamerElite are
// sourced from two historically-separate tables.
const POOL_REWARDS: Record<string, { gold: number; exp: number }> = { ...CIRCUIT_REWARDS, ...PRESTIGE_POOL_REWARDS }
const POOL_NAMES: Record<string, string[]> = { ...CIRCUIT_EVENT_NAMES, ...PRESTIGE_POOL_NAMES }

// Which of the 4 quarters actually run the "guaranteed cup" draw at all
// (user spec 2026-07-25 — Masters/Tamer Elite run at HALF the density of
// every league below them). Omitted leagues default to all 4 (full density).
// Each halved league's own marquee quarter is deliberately one of its 2
// active quarters, so the marquee doesn't land in an otherwise-dead quarter.
const ACTIVE_QUARTERS_BY_LEAGUE: Record<string, number[]> = {
  Masters: [0, 2], // Q1 + Q3 — Q3 holds the Grandmasters' Summit (month 9)
  'Tamer Elite': [1, 3], // Q2 + Q4 — Q4 holds the Apex Invitational (month 10)
  'Tamers Apex': [1, 3], // Q2 + Q4 — Q4 holds The Dynasty Eternal (month 12)
}
export const activeQuartersFor = (league: string): number[] => ACTIVE_QUARTERS_BY_LEAGUE[league] ?? [0, 1, 2, 3]

// Draw the year's tournament calendar. Deterministic per (seed, year): every
// league Wood through Platinum gets 1 cup per active quarter (all 4 of them),
// ~40% chance of a second — Masters/Tamer Elite only have 2 active quarters,
// giving them roughly half as many cups a year as everyone below them. The 5
// marquee-bearing leagues (Silver+) slot their one fixed annual event into
// its own quarter as THAT quarter's guaranteed cup (not an addition on top),
// so total yearly cup counts stay comparable across every league.
// The calendar is a pure function of (seed, year) but the generator is not free
// (per-league RNG loops + the ≥2-cups/month filler pass + a sort), and the UI
// asks for it several times per render across three screens. A tiny memo keyed
// on the last few (seed, year) pairs makes repeat calls O(1). Entries are
// treated as immutable by every caller, so sharing one array is safe.
const CALENDAR_CACHE = new Map<string, Tournament[]>()
export function tournamentCalendarFor(seed: string, year: number): Tournament[] {
  const cacheKey = seed + ':' + year
  const hit = CALENDAR_CACHE.get(cacheKey)
  if (hit) return hit
  const out: Tournament[] = []
  const marqueeByLeague = new Map(PRESTIGE_EVENTS.map((p) => [p.league, p]))
  for (const league of Object.keys(POOL_REWARDS)) {
    const rng = mulberry32(hashString(seed + ':calendar:' + year + ':' + league))
    const names = [...POOL_NAMES[league]]
    const takeName = () => names.length ? names.splice(Math.floor(rng() * names.length), 1)[0] : `${league} Open`
    const marquee = marqueeByLeague.get(league)
    const marqueeQuarter = marquee ? Math.floor((marquee.month - 1) / 3) : -1
    if (marquee) out.push({ ...marquee, id: `${league.toLowerCase().replace(' ', '-')}-y${year}-m${marquee.month}` })
    for (const q of activeQuartersFor(league)) {
      const months = [q * 3 + 1, q * 3 + 2, q * 3 + 3].filter((m) => m !== marquee?.month)
      // The marquee IS this quarter's guaranteed cup — only roll the ~40%
      // bonus slot here, not a second guaranteed one (else Silver etc. would
      // out-pace Wood-Iron instead of matching them).
      const guaranteed = q === marqueeQuarter ? 0 : 1
      const count = guaranteed + (rng() < 0.4 ? 1 : 0)
      for (let i = 0; i < count && months.length; i++) {
        // Always consume an rng draw for the month pick, but force Wood's Q1
        // guaranteed cup to Month 1 (user spec): a new player must have a Wood
        // cup in the first month to get competing straight away.
        const roll = Math.floor(rng() * months.length)
        const forceMonth1 = league === 'Wood' && q === 0 && i === 0 && months.includes(1)
        const month = months.splice(forceMonth1 ? months.indexOf(1) : roll, 1)[0]
        // Rank-up trials are DE-CALENDARIZED (v0.5) — on-demand challenges, not
        // scheduled weeks — so cups may land in any week of any month.
        const week = 1 + Math.floor(rng() * WEEKS_PER_MONTH)
        out.push({
          id: `${league.toLowerCase().replace(' ', '-')}-y${year}-m${month}`,
          name: takeName(), month, week, league,
          rewards: POOL_REWARDS[league],
        })
      }
    }
  }
  // Guarantee ≥2 cups EVERY month (user spec 2026-07-XX) — top up any sparse
  // month with filler cups, while keeping each league ≤2 cups per quarter and
  // half-density leagues (Masters / Tamer Elite) out of their inactive quarters
  // (the validate.ts invariants). Deterministic per (seed, year, quarter).
  const allLeagues = Object.keys(POOL_REWARDS)
  const usedNames = new Set(out.map((t) => t.name))
  const fillerName = (league: string): string => {
    let name = POOL_NAMES[league].find((n) => !usedNames.has(n)) ?? `The ${league} Contest`
    for (let k = 2; usedNames.has(name); k++) name = `The ${league} Contest ${k}`
    usedNames.add(name)
    return name
  }
  for (let q = 0; q < 4; q++) {
    const frng = mulberry32(hashString(seed + ':monthfill:' + year + ':q' + q))
    for (const month of [q * 3 + 1, q * 3 + 2, q * 3 + 3]) {
      while (out.filter((t) => t.month === month).length < 2) {
        const inMonth = new Set(out.filter((t) => t.month === month).map((t) => t.league))
        const candidates = allLeagues.filter((l) => activeQuartersFor(l).includes(q) // half-density only in its active quarters
          && !inMonth.has(l) // one cup per league per month keeps ids unique
          && out.filter((t) => t.league === l && Math.floor((t.month - 1) / 3) === q).length < 2) // ≤2/quarter
        if (!candidates.length) break // no room without breaking an invariant (never happens with 8 full-density leagues)
        const league = candidates[Math.floor(frng() * candidates.length)]
        out.push({
          id: `${league.toLowerCase().replace(' ', '-')}-y${year}-m${month}`,
          name: fillerName(league), month, week: 1 + Math.floor(frng() * WEEKS_PER_MONTH), league, rewards: POOL_REWARDS[league],
        })
      }
    }
  }
  out.sort((a, b) => a.month - b.month || a.week - b.week || leagueIndexOf(a.league) - leagueIndexOf(b.league))
  if (CALENDAR_CACHE.size > 8) CALENDAR_CACHE.clear() // a handful of (seed, year) pairs is all any session touches
  CALENDAR_CACHE.set(cacheKey, out)
  return out
}

export const leagueIndexOf = (league: string): number => LEAGUES.findIndex((l) => l.name === league)

// Rank-up trials were DE-CALENDARIZED in v0.5 — see startTrial/trialStatus.
// The old scheduled trial weeks (months 4/8/12, week 4) are gone: the gate is
// now skill (beat the league champion) + gold (buy the license), not the clock.

// Competing below your league pays less: same league 100%, one league above the
// event 50%, two or more above 10%. (You can never enter above your license.)
export function rewardMultiplier(monsterLeagueIndex: number, tournamentLeague: string): number {
  const d = monsterLeagueIndex - leagueIndexOf(tournamentLeague)
  if (d <= 0) return 1
  if (d === 1) return 0.5
  return 0.1 // steepened 0.2 → 0.1 (v0.5): deep punch-downs are near-worthless — and a farmed cup now costs the WEEK too (compete is the weekly action)
}

// A banked genome: enough of a monster to restore it (thaw) or fuse it later.
export interface Frozen {
  id: string
  name: string
  species: Species
  sex: Sex
  stats: Stats
  favouriteFood: Food
  hatedFood: Food
  licenseIndex: number
  potential?: number // bloodline star rating, banked so breeding can inherit it (Phase 5)
  podiums?: number // decoration captured at freeze time — top-3 finishes (drives stud income)
  champs?: number // 1st-place finishes at freeze time
  breedCount?: number // children parented (max BREED_MAX_CHILDREN)
  generation?: number // dynasty depth carried into children
  studBook?: boolean // a Stud Book is assigned — earns uncapped stud income weekly
}

// One Market listing: a deterministic seed (so the preview == what you buy) + price.
export interface MarketOffer {
  seed: string
  price: number
  // Generation overrides baked in at restock time (v0.77) so the card you see
  // and the career you buy are generated from the SAME inputs — boostConstitution
  // consumes rng conditionally, so differing opts would yield a different name.
  speciesId?: string // Market Scout forced this slot to a species
  targetTop?: number // Market Coach trained this slot into a league band
  scouted?: boolean // display only: this slot came from a scout pick
}

// (Tournament entry fee removed 2026-07-XX — cups are free; the weekly compete
// action is the real cost.)

// A tournament entry locked in for this week; resolved during advanceWeek.
// `monsterIds` length must equal teamSizeForLeague(tournament's league).
// `feePaid` is refunded by cancelSignUp.
export interface PendingTournament {
  tournamentId: string
  monsterIds: string[]
  feePaid: number
  // protect/mark orders moved to the per-fight MatchOrders (v0.81) — they're now
  // chosen on the pre-fight tactics screen, per matchup, not at sign-up.
}

// One resolved match within a round-robin event (§2e resolveTournament).
export interface EventMatch {
  aLabel: string
  bLabel: string
  teamA: Monster[]
  teamB: Monster[]
  result: BattleResult
  involvesPlayer: boolean
}

// One participant's final standing in a round-robin event.
export interface EventStanding {
  label: string
  isPlayer: boolean
  wins: number
  draws: number
  losses: number
  hpFracSum: number // tie-break metric: summed average remaining HP fraction across a team's own matches
  placement: number // 1-based, after sort
}

// The most recent tournament EVENT, kept for the battle screen. A full
// round-robin among every participant (the player's team + every rival team).
export interface LastBattle {
  tournamentId: string
  tournamentName: string
  league: string
  teamSize: number
  matches: EventMatch[] // full round robin, in resolution order
  standings: EventStanding[] // sorted by placement ascending
  playerPlacement: number
  fieldSize: number // rivalTeamCount + 1
  goldReward: number
  expNote: string
  isTrial?: boolean // v0.5: a rank-up trial (single champion match), not a cup
}

export interface GameState {
  seed: string
  trainerName: string
  tutorialEnabled: boolean
  tutorialDismissed: boolean // player closed the welcome-tips banner
  // Guided first-run tutorial (v0.86) — a small state machine, first game only:
  // 'buy' (greet + buy 2 at market) → 'raise' (bought, go to town) → 'howto'
  // (town explainer) → 'final' (ranch highlight + closing note) → cleared.
  tutorialStep?: 'buy' | 'raise' | 'howto' | 'final'
  gold: number
  week: number // the global calendar — one clock for market, tournaments, and stable
  stable: Career[]
  activeId: string
  frozen?: Frozen[] // LEGACY (pre-v0.77 stud farm) — migrated into labFrozen on load
  barnCapacity: number
  pantryContract: boolean // Ranch Shop: 20% off NORMAL foods
  grandLarder: boolean // Ranch Shop: 20% off PREMIUM foods (training + fruits + truffle)
  specialLicense: boolean // Iron rank: unlock Draconic + Abyssal
  eliteLicense: boolean // Platinum rank: unlock Mythical
  // --- Monster-market upgrades (v0.77) -------------------------------------
  marketSlots: number // extra market offers bought, 0-3 (base 3 → up to 6)
  marketScout: number // 0 none · 1 base (15%/slot) · 2 upgraded (25%/slot + a 2nd pick)
  scoutPickA: string | null // species id the scout prioritises
  scoutPickB: string | null // 2nd species id — upgraded scout only, may stay null
  marketCoach: number // 0 none · 1 Tin-band stock · 2 Iron-band stock
  area: Area
  market: MarketOffer[] // monster market; restocks at the start of each month
  foodMarket: Record<Food, number> // this week's town food prices (shared by all monsters)
  nextId: number // monotonic id counter, survives save/load
  pendingTournament: PendingTournament | null
  // A staged-but-unresolved event (v0.81): once the player advances a week with a
  // sign-up or trial pending, it becomes an activeCup and is fought interactively
  // (pick tactics → fight, per match) before rewards are finalized. null = no
  // event in flight. Mutually exclusive with pendingTournament/pendingTrial.
  activeCup: ActiveCup | null
  lastBattle: LastBattle | null
  enteredThisMonth: string[] // tournament ids already competed in this month (one entry per event)
  // This week's per-monster plans (activity + food). Lives in GameState (not
  // component state) so plans survive navigating away and reloading; the
  // weekly tick consumes them and carries each ACTIVITY into the new week
  // (food resets — it's bought fresh weekly).
  weekPlans: Record<string, WeekPlanEntry>
  // Digest of what the last weekly tick did (per-monster deltas + tournament
  // result), shown once on the next feeding screen so results aren't buried
  // in per-monster logs.
  lastWeek: string[]
  // Contextual tutorial tips already dismissed (only shown while
  // tutorialEnabled): 'signup' | 'injury' | 'rankup' so far.
  tipsSeen: string[]
  // A weekly incident awaiting the player's decision, rolled by the last tick
  // for the NEW week and shown on the feeding screen. null = quiet week.
  pendingEvent: PendingEvent | null
  // Rival trainers (LOOP_DESIGN Phase 2) — a recurring named face on the ladder
  // with a tracked head-to-head. One primary rival for now; the array leaves
  // room for a circuit later.
  rivals: Rival[]
  // --- v0.6 economy pass ---
  comfortOwned: string[] // comfort-set item ids owned (stable-wide +2mo career span each)
  trainingGear: Partial<Record<Stat, number>> // peddler gear tier owned per stat (0-5, +5% training each)
  tonics: number // Elder Tonics in inventory (use on a monster: +2mo career span)
  studBooks: number // Stud Books in inventory (assign to a frozen legacy: uncapped stud income)
  studSlots?: number // LEGACY (pre-v0.77) — the Lab's labSlots is now the only capacity
  labTechLoan: boolean // lab-tech loan event taken → freeze upkeep 5→3g/wk
  extremeUnlocked: boolean // Extreme Training Manual bought → extreme drill row open
  diverseUnlocked: boolean // Diverse Training Manual bought → the pair-training drills open
  battleAnalyst: boolean // Ranch Shop: unlocks the deep post-fight read (gameplan + advice)
  // Lab freezer (v0.7, FUSION_DESIGN.md) — SEPARATE from the breeding stud farm.
  // Monsters frozen here are in stasis (aging paused): preserve one until you can
  // afford an Elder Tonic, or fuse two into a new fusion species.
  labFrozen: Career[] // full monsters in stasis
  labSlots: number // lab freezer slots (base 2, expandable from the Ranch Shop)
  // Trainer XP (LOOP_DESIGN Phase 5) — the persistent meta character. Earned by
  // podium cup finishes and raising monsters to retirement; the derived level
  // grants extra barn capacity. The ranch is the account; monsters are the runs.
  trainerXp: number
  // Per-PLAYER licensing (v0.5, user spec 2026-07-22): the license belongs to
  // the trainer, not the monster — recruiting for a 5v5 shouldn't mean
  // re-climbing the ladder with every new member. Every stable Career's own
  // licenseIndex is kept SYNCED to this value (one invariant, enforced at every
  // career-creation/​license-change funnel) so the many per-career consumers
  // (stat caps, fees, exp clamps) keep working unchanged.
  licenseIndex: number
  // Highest license EARNED via a rank-up trial win but possibly not yet BOUGHT —
  // the trial unlocks the license in the Ranch Shop; paying activates it.
  licenseEarned: number
  // An on-demand rank-up trial signed up for THIS week (consumes the entered
  // monsters' weekly action, like a cup). Resolved in advanceWeek.
  pendingTrial: { monsterIds: string[] } | null
  pendingRite: { monsterIds: string[] } | null
  riteReward: { monsterIds: string[]; league: string } | null // won the rite, signature not yet chosen — the player picks the monster AND the move // Signature Rite (v0.91) — on-demand, WHOLE roster, annual, unlocks at trainer LV6
  riteCooldownUntil: number
  // Week gate after a FAILED trial — no re-attempt until g.week >= this.
  trialCooldownUntil: number
}

// Calendar helpers off the global week clock.
export const monthOfWeek = (week: number) => Math.floor((week % WEEKS_PER_YEAR) / WEEKS_PER_MONTH) + 1
export const weekOfMonth = (week: number) => (week % WEEKS_PER_MONTH) + 1

// League visibility (user spec 2026-07-19): the calendar shows Wood→Silver
// until Silver is COMPLETED (a monster promoted past it), then up to Masters;
// Tamer Elite appears only once a monster has REACHED Masters. Progress counts
// the stable AND frozen genomes, so retiring/freezing a champion never hides
// leagues the player has already earned sight of.
export function visibleLeagueCount(g: GameState): number {
  const silverIdx = leagueIndexOf('Silver')
  const mastersIdx = leagueIndexOf('Masters')
  const maxIdx = g.licenseIndex // per-player license (v0.5)
  if (maxIdx >= mastersIdx) return LEAGUES.length
  if (maxIdx > silverIdx) return mastersIdx + 1
  return silverIdx + 1
}

// --- Economy constants (§13.3) ---
// Weekly upkeep per preserved monster. 8→5 (v0.6) →3 (v0.77): the Lab stopped
// being a luxury parking bay and became the ONLY route to breeding and fusion,
// so it can no longer be priced like an optional extra. The lab-tech loan takes
// it to 2.
export const RENTAL_PER_FROZEN = 3
export const MARKET_BASE = 150 // base monster price; fluctuates ±60%
export const PANTRY_CONTRACT_COST = 400 // Ranch Shop: 20% off normal foods
export const GRAND_LARDER_COST = 1500 // Ranch Shop: 20% off premium foods — a serious late-game investment
// Per-food discount given the player's owned contracts (2026-07-25): normal
// foods key off the Pantry Contract, everything premium off the Grand Larder.
export function foodDiscountFor(g: GameState, food: Food): number {
  const owned = foodDiscountGroup(food) === 'normal' ? g.pantryContract : g.grandLarder
  return owned ? 0.8 : 1
}
export const FUSION_PENALTY = 0.9 // average of parents − 10% (§10.2)
export const START_BARN = 2

export function newGame(seed = 'start', opts?: { trainerName?: string; tutorialEnabled?: boolean }): GameState {
  return {
    seed,
    trainerName: opts?.trainerName?.trim() || 'Tamer',
    tutorialEnabled: opts?.tutorialEnabled ?? true,
    tutorialDismissed: false,
    tutorialStep: (opts?.tutorialEnabled ?? true) ? 'buy' : undefined,
    gold: START_GOLD,
    week: 0,
    stable: [],
    activeId: '',
    barnCapacity: START_BARN,
    pantryContract: false,
    grandLarder: false,
    specialLicense: false,
    eliteLicense: false,
    marketSlots: 0,
    marketScout: 0,
    scoutPickA: null,
    scoutPickB: null,
    marketCoach: 0,
    area: 'town',
    market: rollMarketOffers(seed, 0),
    foodMarket: rollMarket(seed, 0),
    nextId: 0,
    pendingTournament: null,
    activeCup: null,
    lastBattle: null,
    enteredThisMonth: [],
    weekPlans: {},
    lastWeek: [],
    tipsSeen: [],
    pendingEvent: null,
    rivals: [generateRival(seed, 0)],
    trainerXp: 0,
    licenseIndex: 0,
    licenseEarned: 0,
    pendingTrial: null,
    trialCooldownUntil: 0,
    pendingRite: null,
    riteReward: null,
    riteCooldownUntil: 0,
    comfortOwned: [],
    trainingGear: {},
    tonics: 0,
    studBooks: 0,
    labTechLoan: false,
    extremeUnlocked: false,
    diverseUnlocked: false,
    battleAnalyst: false,
    labFrozen: [],
    labSlots: LAB_SLOTS_BASE,
  }
}

// --- v0.6 economy pass: constants + purchases -------------------------------
// Cup roster stipend: appearance fees per fielded monster beyond the first —
// income finally scales (gently, additively) with how many mouths a league
// makes you feed. Tunable single knob.
export const CUP_ROSTER_STIPEND = 20
// Comfort set (town store, STABLE-WIDE permanent): each item adds +2 months
// (+8wk) of career span to every monster, present and future.
export const COMFORT_ITEMS = [
  { id: 'bedding', name: 'Plush Bedding', icon: '🛏️', price: 300 },
  { id: 'spring', name: 'Hot Spring Pass', icon: '♨️', price: 500 },
  { id: 'massage', name: 'Monster Massages', icon: '💆', price: 1000 },
] as const
export const COMFORT_WEEKS_PER_ITEM = 8
export const comfortWeeksFor = (g: GameState): number => (g.comfortOwned?.length ?? 0) * COMFORT_WEEKS_PER_ITEM
const syncComfort = (c: Career, g: GameState): Career => ({ ...c, comfortWeeks: comfortWeeksFor(g) })
// Gen-1 training ceiling, stable-wide (v0.77). Wild/market monsters wall at 800;
// each Market Coach tier lifts it, so the Coach is not just better STARTING
// stats but a higher ROOF on everything you buy. Synced onto every career the
// same way comfort and licences are.
export const COACH_CAP_LIFT = [0, 100, 200] // by marketCoach tier → 800 / 900 / 1000
export const wildCapFor = (g: GameState): number => WILD_GEN1_CAP + (COACH_CAP_LIFT[g.marketCoach ?? 0] ?? 0)
export const syncWildCap = (c: Career, g: GameState): Career => ({ ...c, wildCap: wildCapFor(g) })
export function buyComfortItem(g: GameState, id: string): GameState {
  const item = COMFORT_ITEMS.find((x) => x.id === id)
  if (!item || g.comfortOwned.includes(id) || g.gold < item.price) return g
  const comfortOwned = [...g.comfortOwned, id]
  const next = { ...g, gold: g.gold - item.price, comfortOwned }
  return { ...next, stable: g.stable.map((c) => syncComfort(c, next)) }
}
// Training gear (PEDDLER-ONLY): one line per stat, 5 tiers of +5% each, next
// tier revealed only once the previous is owned. Steep escalation by design.
export const GEAR_TIER_PRICES = [200, 500, 750, 1000, 1250]
export const GEAR_NAMES: Record<Stat, string[]> = {
  STR: ['Dumbbells', 'Barbells', 'Iron Yoke', 'Titan Press', 'Colossus Rig'],
  DEX: ['Skipping Rope', 'Agility Poles', 'Balance Beam', 'Wind Harness', 'Phantom Treads'],
  CON: ['Sandbag Vest', 'Training Yoke', 'Granite Pack', 'Juggernaut Plate', 'Mountain Harness'],
  WIS: ['Prayer Beads', 'Incense Set', 'Meditation Mat', 'Oracle Chimes', 'Sage’s Altar'],
  INT: ['Puzzle Box', 'Rune Slate', 'Tome Stand', 'Arcane Orrery', 'Grand Athenaeum'],
  CHA: ['Hand Mirror', 'Stage Costume', 'Golden Megaphone', 'Spotlight Rig', 'Royal Regalia'],
}
export function buyGear(g: GameState, stat: Stat): GameState {
  const tier = g.trainingGear[stat] ?? 0
  if (tier >= 5) return g
  const price = GEAR_TIER_PRICES[tier]
  if (g.gold < price) return g
  return { ...g, gold: g.gold - price, trainingGear: { ...g.trainingGear, [stat]: tier + 1 } }
}
// Elder Tonic (peddler, 500g, unlimited): +2 months to ONE monster per use.
export const TONIC_COST = 500
export const TONIC_WEEKS = 8
export function useTonic(g: GameState, careerId: string): GameState {
  if ((g.tonics ?? 0) < 1) return g
  const bump = (c: Career): Career => {
    const nc: Career = { ...c, tonicWeeks: (c.tonicWeeks ?? 0) + TONIC_WEEKS, log: [...c.log, `🧪 Elder Tonic — career span +2 months.`].slice(-40) }
    // a freshly-extended span can un-retire a monster whose age is back under it
    return { ...nc, retired: Math.floor(nc.ageWeeks / WEEKS_PER_YEAR) >= careerSpanYears(nc) }
  }
  // Usable on an active/retired stable monster OR a lab-frozen one (v0.7).
  if (g.stable.some((x) => x.id === careerId))
    return { ...g, tonics: g.tonics - 1, stable: g.stable.map((x) => (x.id === careerId ? bump(x) : x)) }
  if (g.labFrozen?.some((x) => x.id === careerId))
    return { ...g, tonics: g.tonics - 1, labFrozen: g.labFrozen.map((x) => (x.id === careerId ? bump(x) : x)) }
  return g
}
// Stud Book (peddler, 750g): assign to a FROZEN legacy — it earns UNCAPPED
// stud income from its record (1g/podium + 3g/championship per week).
export const STUDBOOK_COST = 750
export function applyStudBook(g: GameState, frozenId: string): GameState {
  if ((g.studBooks ?? 0) < 1) return g
  const fr = (g.labFrozen ?? []).find((x) => x.id === frozenId)
  if (!fr || fr.studBook) return g
  return { ...g, studBooks: g.studBooks - 1, labFrozen: g.labFrozen.map((x) => (x.id === frozenId ? { ...x, studBook: true } : x)) }
}
// Podium/championship record, read straight off a preserved career.
export const podiumsOf = (c: Career): number => c.tournamentHistory.filter((h) => h.placement <= 3).length
export const champsOf = (c: Career): number => c.tournamentHistory.filter((h) => h.placement === 1).length
export const studIncome = (c: { studBook?: boolean; tournamentHistory?: { placement: number }[] }): number => {
  if (!c.studBook || !c.tournamentHistory) return 0
  const h = c.tournamentHistory
  return h.filter((x) => x.placement <= 3).length + h.filter((x) => x.placement === 1).length * 3
}
// v0.77: the retiree PENSION is gone. It was the single largest income in the
// game — a perpetual, uncapped, per-retiree weekly payment that only ever grew
// (retirees never leave), worth ~45% of a 25-year run's gross gold while cup
// prizes were ~7%. The Retirement Ranch is now a HALL OF FAME: honours only, no
// income, unlimited room. Breeding a retiree still means freezing it into the
// (still limited) stud farm — that's the real cost of a dynasty now.
// Extreme Training Manual (town store): unlocks the extreme drill row.
export const EXTREME_MANUAL_COST = 800
export const buyExtremeManual = (g: GameState): GameState =>
  g.extremeUnlocked || g.gold < EXTREME_MANUAL_COST ? g : { ...g, gold: g.gold - EXTREME_MANUAL_COST, extremeUnlocked: true }

// Diverse Training Manual (v0.90): unlocks the pair drills — +6 to TWO stats at
// once with no malus. Priced level with the Extreme Manual: they are siblings,
// not a ladder. Extreme rushes ONE stat at a cost; diverse builds a class pair.
export const DIVERSE_MANUAL_COST = 800
export const buyDiverseManual = (g: GameState): GameState =>
  g.diverseUnlocked || g.gold < DIVERSE_MANUAL_COST ? g : { ...g, gold: g.gold - DIVERSE_MANUAL_COST, diverseUnlocked: true }

// Battle Analyst (v0.84): a one-time hire that deepens the post-fight report —
// reads the opponent's gameplan and turns the match into concrete advice.
export const BATTLE_ANALYST_COST = 500
export const buyBattleAnalyst = (g: GameState): GameState =>
  g.battleAnalyst || g.gold < BATTLE_ANALYST_COST ? g : { ...g, gold: g.gold - BATTLE_ANALYST_COST, battleAnalyst: true }
export const LAB_LOAN_UPKEEP = 2
export const labUpkeepPerFrozen = (g: GameState): number => (g.labTechLoan ? LAB_LOAN_UPKEEP : RENTAL_PER_FROZEN)
// Breeding (v0.6, SEPARATE from fusion): two PRESERVED monsters parent a child —
// parents preserved, each good for at most 2 children. The child gets potential
// (avg +10% + championship-bloodline bonus, cap 1.5), a stat head start, parent
// B's major as a heritage stat (+10% train speed), and a generation tag.
//
// v0.77: breeding stock now comes from the LAB FREEZER, not a separate stud farm.
// The Lab is the single preservation mechanism — you must FREEZE a monster you
// intend to breed (or fuse) BEFORE it ages out. Let it retire and the genome is
// gone: the Hall of Fame is honours only. That's the real cost of a dynasty.
export const BREED_COST = 300
export const BREED_MAX_CHILDREN = 2
export const BREED_POTENTIAL_STEP = 0.10 // the WILD baseline; see BREED_STEP_BY_TIER
// Breeding climb by heritage (v0.88). A bloodline's per-generation potential
// step depends on its BEST parent's body: bought prestige climbs a little
// faster than wild stock, Mythical a little faster again, FUSED lines faster
// still, and the prestige fusion (Primeval) fastest of all. Ballpark targets
// (user spec, measured at the Tamer Elite league cap of 1000):
//   wild line     1.00 → 1.40 over FOUR breeding generations  (4 × 0.10)
//   Primeval      1.25 → 1.40 over ONE                        (1 × 0.15)
export const BREED_STEP_BY_TIER = { wild: 0.10, prestige: 0.11, mythical: 0.12, fusion: 0.13, primeval: 0.15 } as const
function breedTier(body: BodyType): keyof typeof BREED_STEP_BY_TIER {
  if (body === 'Primeval') return 'primeval'
  if (isFusionBody(body)) return 'fusion'
  if (body === 'Mythical') return 'mythical'
  if (isPrestigeBody(body)) return 'prestige'
  return 'wild'
}
// The line climbs at its BETTER parent's rate — one exceptional founder is not
// dragged down by a modest partner.
export const breedStepFor = (a: BodyType, b: BodyType): number =>
  Math.max(BREED_STEP_BY_TIER[breedTier(a)], BREED_STEP_BY_TIER[breedTier(b)])
export const BREED_HEAD_START = 0.3 // fraction of parents' avg stats a child hatches with. v0.861: 0.45→0.15→0.30 — a real head start (user spec: parents' stats SHOULD carry to the child; fusion carries none), while the climbing `potential` cap-multiplier stays the dynasty's long-run engine.
export function breedPotentialV2(a: Career, b: Career): number {
  const champBonus = Math.min(0.08, Math.floor((champsOf(a) + champsOf(b)) / 2) * 0.01)
  // Base off the BETTER parent (v0.88, was their average): a single exceptional
  // founder — a fused Primeval especially — is no longer diluted by a modest
  // partner. For same-generation pairings (the usual case) this is identical to
  // the old average, so ordinary lines climb exactly as before.
  const base = Math.max(a.potential ?? 1, b.potential ?? 1)
  const step = breedStepFor(a.species.body, b.species.body)
  return Math.min(MAX_POTENTIAL, Math.round((base + step + champBonus) * 100) / 100)
}
export function breed(g: GameState, aId: string, bId: string): GameState {
  if (aId === bId || g.gold < BREED_COST || barnFull(g)) return g
  const a = (g.labFrozen ?? []).find((x) => x.id === aId)
  const b = (g.labFrozen ?? []).find((x) => x.id === bId)
  if (!a || !b || (a.breedCount ?? 0) >= BREED_MAX_CHILDREN || (b.breedCount ?? 0) >= BREED_MAX_CHILDREN) return g
  const potential = breedPotentialV2(a, b)
  const generation = Math.max(a.generation ?? 1, b.generation ?? 1) + 1
  const babySeed = 'breed-' + a.id + '+' + b.id + ':' + g.nextId
  const baby = newCareer(babySeed, { id: 'own-breed-' + g.nextId + '-' + babySeed, ageWeeks: 0, licenseIndex: g.licenseIndex, potential })
  baby.species = a.species // parent A provides the frame/species
  // 35% stat head start from the parents' averages (never below the fresh roll)
  for (const s of STATS) baby.stats[s] = Math.max(baby.stats[s], Math.round(BREED_HEAD_START * ((a.stats[s] + b.stats[s]) / 2)))
  baby.hp = maxHp(baby.stats); baby.mp = maxMana(baby.stats)
  const bProf = b.species.trainingProfile?.major
  baby.heritageStat = bProf ?? [...STATS].sort((x, y) => b.stats[y] - b.stats[x])[0]
  baby.generation = generation
  // A signature passes down DORMANT (user spec): reduced power, rider stripped,
  // and it awakens only when the child trains the relevant stat up to whatever
  // its ancestor had on the day the move was forged. If BOTH parents hold one
  // the higher-tier marquee wins — the line carries its proudest day forward,
  // not merely the most recent. See signature.ts and the awakening in applyWeek.
  // If BOTH parents hold one, take the copy CLOSEST to its origin (lowest
  // `inherited` depth) — the line carries the freshest link to the monster that
  // actually won it, rather than a copy of a copy.
  const heirloom = [a.signature, b.signature].filter((s): s is Signature => !!s)
    .sort((x, y) => (x.inherited ?? 0) - (y.inherited ?? 0))[0]
  if (heirloom) baby.signature = inheritSignature(heirloom)
  baby.comfortWeeks = comfortWeeksFor(g)
  baby.wildCap = wildCapFor(g)
  const stars = '★'.repeat(Math.max(0, Math.round((potential - 1) / 0.05)))
  baby.log = [`${baby.name} is born — Gen ${generation} ${stars}, child of ${a.name} & ${b.name} (potential ×${potential.toFixed(2)}, heritage: ${baby.heritageStat}).`]
  if (baby.signature) baby.log.push(`  ☆ Inherits ${signatureName(baby.signature)}, dormant — ${baby.signature.forgedBy} forged it winning ${baby.signature.eventName}. Train ${baby.signature.stat} to ${baby.signature.awakenStat} to awaken it.`)
  return {
    ...g,
    gold: g.gold - BREED_COST,
    stable: [...g.stable, baby],
    labFrozen: g.labFrozen.map((x) => (x.id === aId || x.id === bId ? { ...x, breedCount: (x.breedCount ?? 0) + 1 } : x)),
    nextId: g.nextId + 1,
  }
}

// --- LAB FREEZER (v0.7, FUSION_DESIGN.md) — separate from the breeding stud farm.
// A stasis freezer: park a monster (aging paused) until you can afford an Elder
// Tonic, or FUSE two into a brand-new fusion species. Slots expand from the shop.
// 2→3 (v0.77): two slots is exactly one breeding pair, so a second bloodline
// used to demand a 400g expansion immediately. Three lets a dynasty breathe.
export const LAB_SLOTS_BASE = 3
export const LAB_EXPAND_COSTS = [250, 500, 900] // was 400/800/1600 — this is the dynasty bottleneck now
export const labExpandCost = (g: GameState): number | null => LAB_EXPAND_COSTS[(g.labSlots ?? LAB_SLOTS_BASE) - LAB_SLOTS_BASE] ?? null
export function expandLab(g: GameState): GameState {
  const cost = labExpandCost(g)
  if (cost === null || g.gold < cost) return g
  return { ...g, gold: g.gold - cost, labSlots: g.labSlots + 1 }
}
// Freeze an ACTIVE monster into stasis (removed from the stable; ages paused).
export function freezeToLab(g: GameState, id: string): GameState {
  const c = g.stable.find((x) => x.id === id)
  // v0.77: a RETIRED monster can no longer be preserved — the window closes when
  // its career ends. Commit before it ages out, or it is honours only.
  if (!c || c.retired || (g.labFrozen?.length ?? 0) >= (g.labSlots ?? LAB_SLOTS_BASE)) return g
  const stable = g.stable.filter((x) => x.id !== id)
  const activeId = g.activeId === id ? stable.find((x) => !x.retired)?.id ?? stable[0]?.id ?? '' : g.activeId
  return { ...g, stable, labFrozen: [...(g.labFrozen ?? []), { ...c, log: [...c.log, '🧊 Frozen in stasis at the Lab.'] }], activeId }
}
// Thaw a lab-frozen monster back into the active stable (resumes at the same age).
export function thawFromLab(g: GameState, id: string): GameState {
  if (barnFull(g)) return g
  const c = g.labFrozen?.find((x) => x.id === id)
  if (!c) return g
  return { ...g, labFrozen: g.labFrozen.filter((x) => x.id !== id), stable: [...g.stable, { ...c, comfortWeeks: comfortWeeksFor(g), wildCap: wildCapFor(g) }], activeId: g.activeId || c.id }
}

// --- FUSION (v0.7) — combine two LAB-FROZEN monsters into a new fusion species.
// Result: all stats start at 100; the two +20% majors are INHERITED from the two
// parents' majors; a +10% minor / −10% flaw is rolled per monster; the SPECIES
// (which of the 5) is a spinning-wheel random; gen-1 potential ×1.075 (1½★),
// Platinum-capped until bred onward. Both parents are CONSUMED. Money only —
// nothing to do with breeding legacies.
export const FUSION_COST = 1000
export const FUSION_START_STAT = 100 // every fused monster starts at 100 across the board
export const FUSION_POTENTIAL = 1.15 // 3★ (v0.73): a strong bloodline from birth — fusing is a shortcut to a high-potential line
export const FUSION_RECIPES: { bodies: [BodyType, BodyType]; classLabel: string; pool: string[]; potential?: number }[] = [
  { bodies: ['Mammal', 'Reptilian'], classLabel: 'Saurian', pool: ['grendscale', 'vipramane', 'thornhide', 'runewyrm', 'basilroar'] },
  { bodies: ['Avian', 'Aquatic'], classLabel: 'Tempestine', pool: ['thunderoc', 'galewing', 'tidecaller', 'maelstrom', 'brinehowl'] },
  { bodies: ['Marsupial', 'Insectoid'], classLabel: 'Broodkin', pool: ['chitinhop', 'broodmother', 'mantiskin', 'resinback', 'swarmherd'] },
  // Primeval (v0.88): the PRESTIGE fusion — Mythical crossed with either
  // Special-license body. Two pair-recipes feed ONE class so a Mythical is
  // fusable with whatever prestige stock the freezer holds. Higher potential
  // (1.25 vs 1.15) makes Primeval the premier founder of endgame bloodlines.
  { bodies: ['Mythical', 'Draconic'], classLabel: 'Primeval', pool: ['aeonrex', 'stellavore', 'chronoshell', 'originmage', 'worldsong'], potential: 1.25 },
  { bodies: ['Mythical', 'Abyssal'], classLabel: 'Primeval', pool: ['aeonrex', 'stellavore', 'chronoshell', 'originmage', 'worldsong'], potential: 1.25 },
]
export function fusionRecipeFor(a: BodyType, b: BodyType) {
  return FUSION_RECIPES.find((r) => (r.bodies[0] === a && r.bodies[1] === b) || (r.bodies[0] === b && r.bodies[1] === a)) ?? null
}
// A parent's primary training major — inherited into the fusion. Base species use
// their authored/derived major; a fusion parent passes its own inherited major1.
function parentMajor(c: Career): Stat {
  return c.bonusMajor1 ?? trainingProfileFor(c.species).major ?? ([...STATS].sort((x, y) => c.stats[y] - c.stats[x])[0])
}
// A fusion parent may be pulled from the ACTIVE stable OR the Lab freezer (v0.73:
// fuse straight from the stable — no need to freeze first).
const fusionParent = (g: GameState, id: string): Career | undefined =>
  g.stable.find((x) => !x.retired && x.id === id) ?? g.labFrozen?.find((x) => x.id === id)
// The spinning wheel: which of the class's 5 species this fusion lands on
// (deterministic per pairing+nextId, so the UI can animate to the real result).
export function fusionSpin(g: GameState, aId: string, bId: string): { speciesId: string; classLabel: string; pool: string[] } | null {
  const a = fusionParent(g, aId)
  const b = fusionParent(g, bId)
  if (!a || !b || a.id === b.id) return null
  const recipe = fusionRecipeFor(a.species.body, b.species.body)
  if (!recipe) return null
  const rng = mulberry32(hashString('fusewheel:' + a.id + '+' + b.id + ':' + g.nextId))
  return { speciesId: recipe.pool[Math.floor(rng() * recipe.pool.length)], classLabel: recipe.classLabel, pool: recipe.pool }
}
export function fuse(g: GameState, aId: string, bId: string): GameState {
  if (aId === bId || g.gold < FUSION_COST) return g
  const a = fusionParent(g, aId)
  const b = fusionParent(g, bId)
  const spin = fusionSpin(g, aId, bId)
  if (!a || !b || !spin) return g
  // Barn room: consuming stable parents frees slots; only labFrozen parents add net.
  const fromStable = [aId, bId].filter((id) => g.stable.some((x) => x.id === id)).length
  if (activeStableCount(g) - fromStable + 1 > effectiveBarnCap(g)) return g
  const species = SPECIES.find((s) => s.id === spin.speciesId)!
  const rng = mulberry32(hashString('fuse:' + a.id + '+' + b.id + ':' + g.nextId))
  const babySeed = 'fuse-' + a.id + '+' + b.id + ':' + g.nextId
  // Per-recipe potential (v0.88): Primeval founds at 1.25, the base three at 1.15.
  const potential = fusionRecipeFor(a.species.body, b.species.body)?.potential ?? FUSION_POTENTIAL
  const baby = newCareer(babySeed, { id: 'own-fuse-' + g.nextId + '-' + babySeed, ageWeeks: WEEKS_PER_YEAR, licenseIndex: g.licenseIndex, potential })
  baby.species = species
  baby.generation = 1 // founds a bloodline — gen-1 Platinum-capped until bred
  for (const s of STATS) baby.stats[s] = FUSION_START_STAT // all 100
  baby.hp = maxHp(baby.stats); baby.mp = maxMana(baby.stats)
  // Aptitude — EVERY fused monster gets exactly two +20% majors, one +10% minor,
  // one −10% flaw (all on distinct stats). The two majors are INHERITED from the
  // parents' majors; if the parents share a major, the second falls to parent B's
  // next-strongest DISTINCT stat so it's always TWO buffs, never one doubled.
  baby.bonusMajor1 = parentMajor(a)
  baby.bonusMajor2 = parentMajor(b)
  if (baby.bonusMajor2 === baby.bonusMajor1) {
    baby.bonusMajor2 = [...STATS].sort((x, y) => b.stats[y] - b.stats[x]).find((s) => s !== baby.bonusMajor1)!
  }
  // ...plus a rolled +10% minor / −10% flaw on two OTHER (distinct) stats.
  const others = STATS.filter((s) => s !== baby.bonusMajor1 && s !== baby.bonusMajor2)
  baby.bonusMinor = others[Math.floor(rng() * others.length)]
  const flawPool = others.filter((s) => s !== baby.bonusMinor)
  baby.bonusFlaw = flawPool[Math.floor(rng() * flawPool.length)]
  baby.comfortWeeks = comfortWeeksFor(g)
  baby.wildCap = wildCapFor(g)
  const stars = '★'.repeat(Math.round((potential - 1) / 0.05))
  baby.log = [`${baby.name} the ${species.name} is forged — a ${spin.classLabel}. Training aptitude: +20% ${baby.bonusMajor1} & +20% ${baby.bonusMajor2}, +10% ${baby.bonusMinor}, −10% ${baby.bonusFlaw}. ${stars} bloodline, Platinum-capped until bred onward.`]
  return {
    ...g,
    gold: g.gold - FUSION_COST,
    stable: [...g.stable.filter((x) => x.id !== aId && x.id !== bId), baby], // stable parents CONSUMED
    labFrozen: (g.labFrozen ?? []).filter((x) => x.id !== aId && x.id !== bId), // frozen parents CONSUMED
    activeId: (g.activeId === aId || g.activeId === bId) ? baby.id : g.activeId,
    nextId: g.nextId + 1,
  }
}

// --- Per-player licensing + rank-up trials (v0.5) ---
// Cost to BUY the license for league index i, once its trial is won. Anchored
// at 50g (user spec) and grown ~i^1.5 — each step lands around 1-1.5 cup wins
// at the tier you're leaving, so a player who can WIN the trial can afford the
// license soon after (never a doubling wall). validate.ts asserts monotonic.
// v0.87 mid-game pass: mid-tier licenses (Bronze→Gold) nudged up ~10–15% — that
// band is exactly when cup gold starts flowing, so the rank-up should cost a
// real cut of it. Still monotonic and never-doubling (validator-checked).
export const LICENSE_COSTS = [0, 50, 120, 235, 410, 610, 860, 1000, 1300, 1650, 1900]
export const nextLicenseCost = (g: GameState): number => LICENSE_COSTS[g.licenseIndex + 1] ?? Infinity
// The one sync invariant of per-player licensing: every stable career trains
// and is fee-assessed at the PLAYER's license tier.
const syncLicenses = (stable: Career[], licenseIndex: number): Career[] =>
  stable.map((c) => (c.licenseIndex === licenseIndex ? c : { ...c, licenseIndex }))
// A stable monster has hit the current cap−10 — strong enough to challenge.
export const trialReady = (g: GameState): boolean =>
  g.stable.some((c) => !c.retired && Math.max(...STATS.map((s) => c.stats[s])) >= LEAGUES[g.licenseIndex].cap - 10)
export function trialStatus(g: GameState): { ok: boolean; reason?: string } {
  if (g.licenseIndex >= LEAGUES.length - 1) return { ok: false, reason: 'top league reached' }
  if (g.licenseEarned > g.licenseIndex) return { ok: false, reason: 'license already earned — buy it in the Ranch Shop' }
  if (g.week < g.trialCooldownUntil) return { ok: false, reason: `recovering from the last attempt — ready in ${g.trialCooldownUntil - g.week}wk` }
  if (!trialReady(g)) return { ok: false, reason: `train a monster to ${LEAGUES[g.licenseIndex].cap - 10} in a stat first` }
  if (pendingCupIsThisWeek(g)) return { ok: false, reason: 'already signed up for a cup this week' }
  return { ok: true }
}
// Sign up for the trial — an on-demand champion fight (de-calendarized, v0.5:
// the trial gate is now skill + gold, not the calendar; it consumes the entered
// monsters' week exactly like a cup).
export function startTrial(g: GameState, monsterIds: string[]): GameState {
  if (!trialStatus(g).ok || g.pendingTrial) return g
  const size = teamSizeForLeague(LEAGUES[g.licenseIndex].name)
  const unique = [...new Set(monsterIds)]
  if (unique.length !== size) return g
  if (!unique.every((id) => g.stable.some((c) => c.id === id && !c.retired))) return g
  // The trial consumes the entered monsters' week, exactly like a cup.
  const weekPlans = { ...(g.weekPlans ?? {}) }
  for (const id of unique) weekPlans[id] = { ...(weekPlans[id] ?? { activity: 'rest', food: '' as const }), activity: 'compete' }
  return { ...g, weekPlans, pendingTrial: { monsterIds: unique } }
}
export function cancelTrial(g: GameState): GameState {
  const weekPlans = { ...(g.weekPlans ?? {}) }
  for (const id of g.pendingTrial?.monsterIds ?? []) {
    if (weekPlans[id]?.activity === 'compete') weekPlans[id] = { ...weekPlans[id], activity: 'rest' }
  }
  return { ...g, weekPlans, pendingTrial: null }
}

// --- THE SIGNATURE RITE (v0.91, user spec) — the ONLY source of a signature
// skill. An on-demand special event built exactly like the rank-up trial: no
// calendar slot, it consumes the entered monster's week, and losing costs a
// cooldown rather than anything permanent.
//
// It differs from the trial in three deliberate ways:
//   • ALWAYS 1v1, at every league. The rite is one monster proving itself, not a
//     team result — which is also what makes "whose signature is this?" have a
//     single unambiguous answer.
//   • Gated on TRAINER level 6, not on the monster. Signatures are a thing an
//     experienced tamer knows how to draw out; a first-season player never sees
//     the option, so the early game stays uncluttered.
//   • Repeatable across a stable — but once per MONSTER. A monster that already
//     carries a signature (earned or inherited) has nothing left to prove.
export const SIGNATURE_RITE_LEVEL = 6 // trainer level that unlocks the rite
// ONCE A YEAR, win or lose (user spec). Unlike the trial's punitive 3-week
// cooldown, this is a scheduling constraint rather than a penalty: the rite is
// the single biggest decision of a monster's year, and making the clock run
// regardless of outcome means attempting it is itself the commitment. It also
// caps signatures at one per year per stable no matter how deep the roster.
export const RITE_COOLDOWN_WEEKS = WEEKS_PER_YEAR
// HARDER THAN THE RANK-UP TRIAL at every rung (user spec). Expressed as a delta
// over trialChampionMult so it inherits that function's summit relief — a flat
// multiplier compounds with the climbing rival budget into an unwinnable wall,
// the bug v0.89 had to fix for Tamer Elite.
// ⚠️ SIM-TUNED 0.15 -> 0.05. At +0.15 the long-haul bot went 0 for 13 across 45
// simulated years: unwinnable, not merely hard. The reason is the whole-roster
// rule — the challenger side matches the roster ONE FOR ONE at full budget, so
// entering with six monsters means your two benchwarmers face champions too,
// while your average drags. Measured roster strength peaked at 0.69 of the
// challenger budget. At +0.05 it is winnable but rare (1 in 12 for a bot that
// attempts at 60% readiness), which is the right shape for a once-a-year gamble
// a PLAYER can time better than the bot does.
export const RITE_EXTRA_MULT = 0.05
export const riteChampionMult = (leagueIndex: number): number => trialChampionMult(leagueIndex) + RITE_EXTRA_MULT
// The rite is fought by the WHOLE active roster (user spec) — not a picked team.
export const riteRoster = (g: GameState): Career[] => g.stable.filter((c) => !c.retired)
// ...but only a monster without a signature can be the one to receive it.
export const riteEligible = (g: GameState): Career[] => riteRoster(g).filter((c) => !c.signature)
export function riteStatus(g: GameState): { ok: boolean; reason?: string } {
  if (trainerLevel(g) < SIGNATURE_RITE_LEVEL) return { ok: false, reason: `unlocks at trainer level ${SIGNATURE_RITE_LEVEL} (you are ${trainerLevel(g)})` }
  if (g.week < (g.riteCooldownUntil ?? 0)) return { ok: false, reason: `held once a year — the site reopens in ${(g.riteCooldownUntil ?? 0) - g.week}wk` }
  if (riteRoster(g).length === 0) return { ok: false, reason: 'no active monsters' }
  if (riteEligible(g).length === 0) return { ok: false, reason: 'every active monster already carries a signature' }
  if (pendingCupIsThisWeek(g)) return { ok: false, reason: 'already signed up for a cup this week' }
  if (g.pendingTrial) return { ok: false, reason: 'a rank-up trial is already set for this week' }
  return { ok: true }
}
export function startRite(g: GameState): GameState {
  if (!riteStatus(g).ok || g.pendingRite) return g
  const ids = riteRoster(g).map((c) => c.id)
  // Consumes EVERY entrant's week — the whole stable is committed.
  const weekPlans = { ...(g.weekPlans ?? {}) }
  for (const id of ids) weekPlans[id] = { ...(weekPlans[id] ?? { activity: 'rest', food: '' as const }), activity: 'compete' }
  return { ...g, weekPlans, pendingRite: { monsterIds: ids } }
}
export function cancelRite(g: GameState): GameState {
  const weekPlans = { ...(g.weekPlans ?? {}) }
  for (const id of g.pendingRite?.monsterIds ?? []) {
    if (weekPlans[id]?.activity === 'compete') weekPlans[id] = { ...weekPlans[id], activity: 'rest' }
  }
  return { ...g, weekPlans, pendingRite: null }
}
// Pay for an earned license: the whole ACCOUNT advances a league.
export function buyLicense(g: GameState): GameState {
  if (g.licenseEarned <= g.licenseIndex) return g
  const cost = nextLicenseCost(g)
  if (g.gold < cost) return g
  const licenseIndex = g.licenseIndex + 1
  return { ...g, gold: g.gold - cost, licenseIndex, stable: syncLicenses(g.stable, licenseIndex) }
}

// --- Trainer level (LOOP_DESIGN Phase 5) ---
export const TRAINER_XP_PER_LEVEL = 250
export const trainerLevel = (g: GameState): number => Math.floor((g.trainerXp ?? 0) / TRAINER_XP_PER_LEVEL) + 1
// Progress within the current level, for the XP bar.
export function trainerXpProgress(g: GameState): { level: number; into: number; need: number } {
  const xp = g.trainerXp ?? 0
  return { level: Math.floor(xp / TRAINER_XP_PER_LEVEL) + 1, into: xp % TRAINER_XP_PER_LEVEL, need: TRAINER_XP_PER_LEVEL }
}
// Perk: +1 barn slot every 2 trainer levels, on top of the shop-bought capacity.
export const trainerBarnBonus = (g: GameState): number => Math.floor((trainerLevel(g) - 1) / 2)
// Perk (v0.71): a weekly gold stipend that scales with trainer level — reputation
// pays. 5g per level per week (Lv1 = 5g/wk, Lv5 = 25g/wk, Lv10 = 50g/wk).
// v0.77: was 5g/level UNCAPPED, which compounded to ~95g/wk by LV19 and ~40% of
// a long run's gross gold. Now 1g per level, FLAT from level 15 — a modest floor
// under a bad week, never a career income. Winning cups is the way you get rich.
export const TRAINER_STIPEND_PER_LEVEL = 1
export const TRAINER_STIPEND_CAP = 15 // reached at trainer level 15
export const trainerStipend = (g: GameState): number =>
  Math.min(TRAINER_STIPEND_CAP, trainerLevel(g) * TRAINER_STIPEND_PER_LEVEL)
export const effectiveBarnCap = (g: GameState): number => g.barnCapacity + trainerBarnBonus(g)
// v0.77: the barn houses COMPETITORS. Retirees moved to the Hall of Fame, which
// has unlimited room — so they no longer occupy (and eventually clog) barn
// slots. Every capacity check counts active monsters only.
export const activeStableCount = (g: GameState): number => g.stable.filter((c) => !c.retired).length
export const barnFull = (g: GameState): boolean => activeStableCount(g) >= effectiveBarnCap(g)
// XP for a cup finish (podium only) — bigger for higher placement and league.
export function cupTrainerXp(placement: number, leagueIndex: number): number {
  const base = placement === 1 ? 60 : placement === 2 ? 35 : placement === 3 ? 20 : 0
  return base > 0 ? base + leagueIndex * 10 : 0
}
export const RETIREMENT_XP = 40 // raising a monster its whole career

// --- Breeding (LOOP_DESIGN Phase 5) ---
export const BREEDING_BONUS = 0.05 // each generation adds 5% to the parents' average potential
export const MAX_POTENTIAL = 1.5 // bounded so a bloodline plateaus, not runs away
export const breedPotential = (a?: number, b?: number): number =>
  Math.min(MAX_POTENTIAL, Math.round(((((a ?? 1) + (b ?? 1)) / 2) + BREEDING_BONUS) * 100) / 100)

// --- Rivals (LOOP_DESIGN Phase 2) ---
const RIVAL_NAMES = ['Rex', 'Vera', 'Dorn', 'Mira', 'Kane', 'Sable', 'Bram', 'Nyx', 'Talia', 'Garruk', 'Odessa', 'Roan']
const RIVAL_PERSONALITIES: RivalPersonality[] = ['aggressive', 'cagey', 'flashy']
export function generateRival(seed: string, i: number): Rival {
  const rng = mulberry32(hashString(seed + ':rival:' + i))
  return {
    id: 'rival-' + i,
    name: RIVAL_NAMES[Math.floor(rng() * RIVAL_NAMES.length)],
    personality: RIVAL_PERSONALITIES[Math.floor(rng() * RIVAL_PERSONALITIES.length)],
    licenseIndex: 0,
    wins: 0,
    losses: 0,
  }
}
// Highest license the player has earned (stable + banked genomes), the target
// a rival climbs toward each week so it stays a credible, at-level threat.
export function playerMaxLicense(g: GameState): number {
  return g.licenseIndex // per-player license (v0.5)
}
// One-per-week nudge toward the player's level (never past it).
function rubberBandRivals(g: GameState): Rival[] {
  const target = playerMaxLicense(g)
  return g.rivals.map((rv) => (rv.licenseIndex < target ? { ...rv, licenseIndex: rv.licenseIndex + 1 } : rv))
}

// --- Market (§13.1) — equal-weighted base monsters; price band wider than food. ---
// Is this species legal for the player to be offered / to scout for?
export function speciesLicensed(s: Species, hasSpecial: boolean, hasElite: boolean): boolean {
  if (s.body === 'Mythical') return hasElite
  if (s.body === 'Draconic' || s.body === 'Abyssal') return hasSpecial
  return true
}

export interface MarketConfig {
  hasSpecialLicense?: boolean
  hasEliteLicense?: boolean
  slots?: number // extra bought slots on top of MARKET_BASE_SLOTS
  scout?: number // 0 | 1 | 2
  pickA?: string | null
  pickB?: string | null
  coach?: number // 0 | 1 | 2
}
export const MARKET_BASE_SLOTS = 3

export function rollMarketOffers(seed: string, roll: number, cfg: MarketConfig = {}): MarketOffer[] {
  const hasSpecial = !!cfg.hasSpecialLicense
  const hasElite = !!cfg.hasEliteLicense
  const scout = cfg.scout ?? 0
  const coach = cfg.coach ?? 0
  const want = MARKET_BASE_SLOTS + Math.max(0, Math.min(MARKET_SLOTS_MAX, cfg.slots ?? 0))

  // A scout pick only counts if it's a real species the player may actually be
  // offered — scouting a Draconic without the Special License must NOT smuggle
  // one past the rank gate, so an unlicensed pick silently falls through to a
  // random roll rather than being honoured.
  const pickOf = (id: string | null | undefined): string | null => {
    if (!id) return null
    const sp = SPECIES.find((x) => x.id === id)
    return sp && !isFusionBody(sp.body) && speciesLicensed(sp, hasSpecial, hasElite) ? sp.id : null
  }
  const pickA = scout >= 1 ? pickOf(cfg.pickA) : null
  const pickB = scout >= 2 ? pickOf(cfg.pickB) : null
  const chance = SCOUT_CHANCE[Math.max(0, Math.min(2, scout))] ?? 0

  const offers: MarketOffer[] = []
  let attemptIndex = 0
  const maxAttempts = 200 // prevent infinite loops

  while (offers.length < want && attemptIndex < maxAttempts) {
    const slot = offers.length
    const s = 'mkt-' + hashString(seed + ':' + roll + ':' + attemptIndex).toString(36)
    const rng = mulberry32(hashString(seed + ':town:' + roll + ':' + attemptIndex))
    const price = Math.max(1, Math.round(MARKET_BASE * (0.4 + rng() * 1.2))) // ±60%

    // Independent per-slot scout roll: pickA gets `chance`, pickB the next
    // `chance` band, the remainder stays a genuine random roll.
    const r = mulberry32(hashString(seed + ':scout:' + roll + ':' + slot))()
    let speciesId: string | null = null
    if (pickA && r < chance) speciesId = pickA
    else if (pickB && r < chance * 2) speciesId = pickB

    let prestigeSlot = false
    if (!speciesId) {
      // Random slot — respect the licence gates by re-rolling the seed.
      const monster = generateMonster(s)
      if (!speciesLicensed(monster.species, hasSpecial, hasElite)) { attemptIndex++; continue }
      // Prestige rarity (v0.87): licensed prestige bodies are RARE finds, not
      // regular stock — 15/45 rollable species are prestige, so without this a
      // licensed player sees one per board and the roster goes all-Draconic.
      // A separate deterministic roll lets only ~PRESTIGE_MARKET_CHANCE of
      // them through; the rest re-roll to base species. The Market Scout's
      // pick (above) deliberately bypasses this — scouting IS the hunting tool.
      if (isPrestigeBody(monster.species.body)) {
        const pr = mulberry32(hashString(seed + ':prestige:' + roll + ':' + attemptIndex))()
        if (pr > PRESTIGE_MARKET_CHANCE) { attemptIndex++; continue }
        prestigeSlot = true
      }
    } else {
      const sp = SPECIES.find((x) => x.id === speciesId)
      prestigeSlot = !!sp && isPrestigeBody(sp.body)
    }

    // Market Coach: draw this slot's top-stat target from the tier's band, so
    // every coached offer genuinely lands in the promised league. The draw is
    // BOTTOM-SKEWED (rng², same shape the excursion payout uses): staying inside
    // the league's rough stat budget is the promise, but the low end of it is
    // the norm — the coach buys a head start, not a finished competitor, so the
    // player's own training is still what makes the monster. Top-of-band happens,
    // it's just rare.
    const band = COACH_BANDS[Math.max(0, Math.min(2, coach))]
    const cr = mulberry32(hashString(seed + ':coach:' + roll + ':' + slot))()
    const targetTop = coach > 0
      ? Math.round(band[0] + cr * cr * (band[1] - band[0]))
      : undefined

    // Prestige premium (v0.87): a rare body costs like one — a gentle first
    // increment (×1.5 on the rolled price), tightened via sim evidence if the
    // license still pays for itself too fast.
    const rolledPrice = prestigeSlot ? Math.round(price * PRESTIGE_PRICE_MULT) : price
    offers.push({
      seed: s,
      price: rolledPrice + (COACH_SURCHARGE[Math.max(0, Math.min(2, coach))] ?? 0),
      ...(speciesId ? { speciesId, scouted: true } : {}),
      ...(targetTop ? { targetTop } : {}),
    })
    attemptIndex++
  }

  return offers
}

// The generation overrides an offer was rolled with — the single source both
// the market card and the purchase read, so they can never disagree.
export const offerGenOpts = (o: MarketOffer): GenOptions =>
  ({ train: 0, ...(o.speciesId ? { speciesId: o.speciesId } : {}), ...(o.targetTop ? { targetTop: o.targetTop } : {}) })

export const marketConfigOf = (g: GameState): MarketConfig => ({
  hasSpecialLicense: g.specialLicense,
  hasEliteLicense: g.eliteLicense,
  slots: g.marketSlots ?? 0,
  scout: g.marketScout ?? 0,
  pickA: g.scoutPickA ?? null,
  pickB: g.scoutPickB ?? null,
  coach: g.marketCoach ?? 0,
})

// --- Market upgrade purchases ----------------------------------------------
// A bought slot takes effect IMMEDIATELY (you paid for stock now); the scout
// and coach shape the NEXT restock, so changing a scout pick can never be used
// to re-roll the current month's board on demand.
export function buyMarketSlot(g: GameState): GameState {
  const cost = marketSlotCost(g)
  if (cost === null || g.gold < cost) return g
  const slots = (g.marketSlots ?? 0) + 1
  const ng = { ...g, gold: g.gold - cost, marketSlots: slots }
  const extra = rollMarketOffers(g.seed + ':slot' + slots, Math.floor(g.week / WEEKS_PER_MONTH), { ...marketConfigOf(ng), slots: 0 })
  return { ...ng, market: [...g.market, ...extra.slice(0, 1)] }
}

export function buyMarketScout(g: GameState): GameState {
  const cost = scoutCost(g)
  if (cost === null || g.gold < cost) return g
  return { ...g, gold: g.gold - cost, marketScout: (g.marketScout ?? 0) + 1 }
}

export function setScoutPick(g: GameState, which: 'A' | 'B', speciesId: string | null): GameState {
  if ((g.marketScout ?? 0) < (which === 'B' ? 2 : 1)) return g
  return which === 'A' ? { ...g, scoutPickA: speciesId } : { ...g, scoutPickB: speciesId }
}

export function buyMarketCoach(g: GameState): GameState {
  const cost = coachCost(g)
  const need = coachLeague(g)
  if (cost === null || need === null || g.licenseIndex < need || g.gold < cost) return g
  const next = { ...g, gold: g.gold - cost, marketCoach: (g.marketCoach ?? 0) + 1 }
  // The new roof applies to monsters you ALREADY own, not just future stock.
  return { ...next, stable: next.stable.map((c) => syncWildCap(c, next)) }
}
export const canBuyMarketCoach = (g: GameState): boolean => {
  const cost = coachCost(g); const need = coachLeague(g)
  return cost !== null && need !== null && g.licenseIndex >= need && g.gold >= cost
}
// The coach row only APPEARS once the Gold license is held (user spec).
export const coachVisible = (g: GameState): boolean =>
  g.licenseIndex >= MARKET_COACH_LEAGUES[0] || (g.marketCoach ?? 0) > 0

export const offerMonster = (o: MarketOffer) => generateMonster(o.seed, offerGenOpts(o))

export function buyMonster(g: GameState, index: number): GameState {
  const o = g.market[index]
  if (!o || g.gold < o.price || barnFull(g)) return g

  const gen = offerGenOpts(o)
  const monster = generateMonster(o.seed, gen)
  if (!speciesLicensed(monster.species, g.specialLicense, g.eliteLicense)) return g

  // Same gen opts as the card, so the monster bought IS the monster shown.
  const c = newCareer(o.seed, { id: 'own-' + g.nextId + '-' + o.seed, licenseIndex: g.licenseIndex, gen }) // recruits join at the PLAYER's license (v0.5)
  c.comfortWeeks = comfortWeeksFor(g) // stable-wide comfort set applies to newcomers too (v0.6)
  c.wildCap = wildCapFor(g)
  const market = g.market.filter((_, i) => i !== index)
  const stable = [...g.stable, c]
  // Guided tutorial: once the player owns two monsters, advance to the "now go
  // raise 'em" beat (drives the market's gold Back-to-Town cue).
  const tutorialStep = g.tutorialStep === 'buy' && stable.filter((x) => !x.retired).length >= 2 ? 'raise' as const : g.tutorialStep
  return { ...g, gold: g.gold - o.price, stable, market, activeId: g.activeId || c.id, nextId: g.nextId + 1, tutorialStep }
}

export function goto(g: GameState, area: Area): GameState {
  return { ...g, area }
}

// --- The weekly tick (§2): one canonical path that advances the whole game ---
// Per monster: feed first (start-of-week choice, at this week's prices), then the
// chosen activity. Monsters with no plan (or retired) still age. Lab rental is
// charged once. The global clock advances; food prices reroll weekly and the
// monster market restocks at the start of each month.
export interface WeekPlanEntry { activity: string; food: Food | ''; forage?: boolean } // activity: drill id | 'rest' | 'excursion'; forage = free fallback when broke

// ---------------------------------------------------------------------------
// Weekly events (LOOP_DESIGN.md Phase 1) — the connective-tissue framework.
// A weekly incident, mostly a CHOICE with a trade-off, shown on the feeding
// screen for the new week. Every effect resolves IMMEDIATELY (no next-week
// modifiers) so applyWeek / previewWeekEffects stay untouched, and the roll is
// deterministic off the seed so it's replay-safe. Later phases hang the rival
// challenge, illness cures, off-ladder teachers, etc. off this same table.
// ---------------------------------------------------------------------------
export type EventScope = 'global' | 'monster'

// What the UI renders — display text is BAKED at roll time so App.tsx needs no
// lookup back into the table (and a saved-mid-event game reloads verbatim).
export interface PendingEvent {
  id: string
  careerId?: string
  title: string
  body: string
  choices: { label: string; note?: string; cost?: number }[]
}

interface EventChoiceDef {
  label: string
  note?: (g: GameState, c?: Career) => string
  cost?: (g: GameState, c?: Career) => number // gold gate — button disables if > wallet
  apply: (g: GameState, careerId?: string) => GameState
  keepOpen?: boolean // v0.6 (peddler): after applying, REBAKE the event instead of closing — multi-purchase shops
}
interface GameEvent {
  id: string
  scope: EventScope
  weight: (g: GameState, c?: Career) => number // 0 = ineligible; higher = likelier
  title: string
  body: (g: GameState, c?: Career) => string
  choices: EventChoiceDef[]
  choicesFor?: (g: GameState) => EventChoiceDef[] // v0.6: dynamic stock (peddler tiers) — used for BOTH baking and resolution so indices always align
}

const clampStat = (v: number, cap: number) => Math.max(1, Math.min(cap, v))
const clampStam = (v: number) => Math.max(0, Math.min(MAX_STAMINA, v))
const clampHap = (v: number) => Math.max(0, Math.min(MAX_HAPPINESS, v))
// Mutate one career in the stable (no-op if the id is gone), functionally.
function updateCareer(g: GameState, id: string | undefined, fn: (c: Career) => Career): GameState {
  if (!id) return g
  return { ...g, stable: g.stable.map((c) => (c.id === id ? fn(c) : c)) }
}
// The stat an event boosts: the species' authored major, else its current best.
function boostStatOf(c: Career): Stat {
  const major = trainingProfileFor(c.species).major
  if (major) return major
  return STATS.reduce((best, s) => (c.stats[s] > c.stats[best] ? s : best), STATS[0])
}
const sponsorPurse = (c: Career) => 120 + 40 * c.licenseIndex

// Rival challenge (LOOP_DESIGN Phase 2): a self-contained off-calendar 1v1
// skirmish vs the primary rival's monster. Simulated deterministically, the
// head-to-head record updated, and the outcome CHAINED as a follow-up
// 'challenge-result' event (a single-OK modal with dynamic text) — resolveEvent
// keeps a pending event the apply sets rather than clearing it.
// The rival's challenge monster — generated deterministically for THIS week, so
// the pre-fight odds estimate and the fight itself use the exact same opponent.
function rivalChallengeMonster(g: GameState): Monster | null {
  const rival = g.rivals[0]
  if (!rival) return null
  const budget = LEAGUES[rival.licenseIndex].cap * rivalBudgetMult(rival.licenseIndex) * 0.85
  return generateRivalMonster(g.seed + ':' + g.week + ':rivalmon', budget, false)
}
// Rough pre-fight win chance (5-95%), from a stat-total logistic — a hint, not a
// promise: it ignores moves/innates/elements the real sim resolves.
function challengeWinChance(g: GameState, c: Career): number {
  const rivalMon = rivalChallengeMonster(g)
  if (!rivalMon) return 50
  const p = STATS.reduce((s, k) => s + c.stats[k], 0)
  const r = STATS.reduce((s, k) => s + rivalMon.stats[k], 0)
  const chance = 1 / (1 + Math.pow(r / Math.max(1, p), 4))
  return Math.min(95, Math.max(5, Math.round(chance * 20) * 5))
}
function runRivalChallenge(g: GameState, careerId?: string): GameState {
  const c = g.stable.find((x) => x.id === careerId)
  const rival = g.rivals[0]
  const rivalMon = rivalChallengeMonster(g)
  if (!c || !rival || !rivalMon) return g
  const playerMon = careerMonster(c)
  const res = simulateTeamBattle(
    [{ ...playerMon, hp: maxHp(playerMon.stats), mp: maxMana(playerMon.stats) }],
    [rivalMon], [c.happiness], [5],
  )
  const won = res.winner === 'A'
  const reward = 40 + 20 * rival.licenseIndex
  let ng = won ? { ...g, gold: g.gold + reward } : g
  ng = updateCareer(ng, careerId, (m) => (won
    ? { ...m, happiness: clampHap(m.happiness + 1) }
    : { ...m, happiness: clampHap(m.happiness - 1), hp: Math.max(1, Math.round(m.hp * 0.6)) }))
  ng = { ...ng, rivals: ng.rivals.map((rv, i) => (i === 0 ? { ...rv, wins: rv.wins + (won ? 1 : 0), losses: rv.losses + (won ? 0 : 1) } : rv)) }
  const r0 = ng.rivals[0]
  const result: PendingEvent = {
    id: 'challenge-result',
    careerId,
    title: won ? '🏆 You Won the Bout!' : '💢 You Lost the Bout',
    body: won
      ? `${c.name} bested ${rival.name}'s monster — +${reward}g and a prouder monster. You now lead ${rival.name} ${r0.wins}–${r0.losses}.`
      : `${rival.name}'s monster got the better of ${c.name}, which comes away bruised and sulking. ${rival.name} leads the rivalry ${r0.losses}–${r0.wins}.`,
    choices: [{ label: 'OK' }],
  }
  return { ...ng, pendingEvent: result }
}

export const EVENTS: GameEvent[] = [
  {
    id: 'rival-challenge',
    scope: 'monster',
    weight: (g, c) => (g.rivals.length > 0 && c && !c.retired ? 3 : 0),
    title: '⚔️ Rival Challenge',
    body: (g, c) => `${g.rivals[0]?.name} spots you in town and calls you out — a friendly bout, ${c!.name} against one of their monsters. Bragging rights on the line. Rough odds: ~${challengeWinChance(g, c!)}% for ${c!.name} to win.`,
    choices: [
      {
        label: 'Accept the challenge',
        note: (g, c) => `~${challengeWinChance(g, c!)}% to win · win: gold & pride · lose: bruised & sore`,
        apply: (g, id) => runRivalChallenge(g, id),
      },
      {
        label: 'Wave them off',
        note: (g) => `${g.rivals[0]?.name} smirks and moves on`,
        apply: (g) => g,
      },
    ],
  },
  // Follow-up shown after a challenge resolves — never rolls on its own
  // (weight 0); its text is baked dynamically by runRivalChallenge.
  {
    id: 'challenge-result',
    scope: 'global',
    weight: () => 0,
    title: '',
    body: () => '',
    choices: [{ label: 'OK', apply: (g) => g }],
  },
  {
    id: 'sponsor',
    scope: 'monster',
    weight: (_g, c) => (c && !c.retired ? 3 + c.licenseIndex : 0),
    title: '📣 Sponsor Appearance',
    body: (_g, c) =>
      `A travelling merchant will pay ${sponsorPurse(c!)}g to feature ${c!.name} at their stall — but a day of being poked and posed leaves it tired.`,
    choices: [
      {
        label: 'Accept the booking',
        note: (_g, c) => `+${sponsorPurse(c!)}g · −25 stamina · −1 happiness`,
        apply: (g, id) => {
          const c = g.stable.find((x) => x.id === id)
          if (!c) return g
          const purse = sponsorPurse(c)
          return updateCareer({ ...g, gold: g.gold + purse }, id, (m) => ({
            ...m, stamina: clampStam(m.stamina - 25), happiness: clampHap(m.happiness - 1),
          }))
        },
      },
      {
        label: 'Politely decline',
        note: (_g, c) => `keep ${c!.name} fresh · +1 happiness`,
        apply: (g, id) => updateCareer(g, id, (m) => ({ ...m, happiness: clampHap(m.happiness + 1) })),
      },
    ],
  },
  {
    id: 'illness',
    scope: 'monster',
    weight: (_g, c) => (c && !c.retired ? 3 : 0),
    title: '🤒 Under the Weather',
    body: (_g, c) =>
      `${c!.name} woke sluggish and off its food. A town healer can set it right for 40g, or it can shake it off on its own — the slow, uncomfortable way.`,
    choices: [
      {
        label: 'Pay for treatment',
        note: () => '−40g · restores stamina & some HP',
        cost: () => 40,
        apply: (g, id) => {
          const c = g.stable.find((x) => x.id === id)
          if (!c) return g
          return updateCareer({ ...g, gold: g.gold - 40 }, id, (m) => ({
            ...m, stamina: clampStam(m.stamina + 40), hp: Math.min(maxHp(m.stats), m.hp + Math.round(maxHp(m.stats) * 0.2)),
          }))
        },
      },
      {
        label: 'Let it pass naturally',
        note: () => '−20 stamina · −1 happiness',
        apply: (g, id) => updateCareer(g, id, (m) => ({
          ...m, stamina: clampStam(m.stamina - 20), happiness: clampHap(m.happiness - 1),
        })),
      },
    ],
  },
  {
    id: 'breakthrough',
    scope: 'monster',
    weight: (_g, c) => (c && !c.retired ? 2 : 0),
    title: '✨ Training Breakthrough',
    body: (_g, c) => `${c!.name} suddenly clicked with a technique it had been struggling on. There's momentum here — if you push it.`,
    choices: [
      {
        label: 'Channel the momentum',
        note: (_g, c) => `+8 ${boostStatOf(c!)} · −10 stamina`,
        apply: (g, id) => updateCareer(g, id, (m) => {
          const stat = boostStatOf(m)
          const cap = statCapFor(m) // bloodline potential lifts the ceiling (Phase 5)
          return { ...m, stats: { ...m.stats, [stat]: clampStat(m.stats[stat] + 8, cap) }, stamina: clampStam(m.stamina - 10) }
        }),
      },
      {
        label: 'Let it rest on the win',
        note: () => '+2 happiness',
        apply: (g, id) => updateCareer(g, id, (m) => ({ ...m, happiness: clampHap(m.happiness + 2) })),
      },
    ],
  },
  {
    id: 'festival',
    scope: 'global',
    weight: (g) => (g.stable.some((c) => !c.retired) ? 2 : 0),
    title: '🎪 Festival Week',
    body: () => "The town's seasonal festival fills the square with banners and music. Bringing your monsters along lifts everyone's spirits.",
    choices: [
      {
        label: 'Join the festivities',
        note: () => 'all monsters +1 happiness',
        apply: (g) => ({ ...g, stable: g.stable.map((c) => (c.retired ? c : { ...c, happiness: clampHap(c.happiness + 1) })) }),
      },
    ],
  },
  {
    id: 'luckyfind',
    scope: 'monster',
    // only contented monsters wander off and come back with treasure
    weight: (_g, c) => (c && !c.retired ? Math.max(0, c.happiness - 4) : 0),
    title: '🍀 Lucky Find',
    body: (_g, c) => `${c!.name} trotted back from its walk looking pleased with itself, a stray pouch of coins in its jaws. Finders keepers.`,
    choices: [
      { label: 'Pocket the coins', note: () => '+50g', apply: (g) => ({ ...g, gold: g.gold + 50 }) },
    ],
  },
  {
    id: 'restless',
    scope: 'monster',
    // unhappy monsters get fractious; the unhappier, the likelier
    weight: (_g, c) => (c && !c.retired ? Math.max(0, 5 - c.happiness) : 0),
    title: '😤 Restless Streak',
    body: (_g, c) => `${c!.name} is pacing and snappish. A calming afternoon (and a treat) would settle it — or you can let it tire itself out.`,
    choices: [
      {
        label: 'Spend time settling it',
        note: () => '−30g · +1 happiness',
        cost: () => 30,
        apply: (g, id) => updateCareer({ ...g, gold: g.gold - 30 }, id, (m) => ({ ...m, happiness: clampHap(m.happiness + 1) })),
      },
      {
        label: 'Let it burn off the energy',
        note: () => '−20 stamina',
        apply: (g, id) => updateCareer(g, id, (m) => ({ ...m, stamina: clampStam(m.stamina - 20) })),
      },
    ],
  },
  // --- v0.6 economy events ---
  {
    // The Mysterious Peddler: the ONLY source of training gear, Elder Tonics
    // and Stud Books. Visits are random — save up in case he comes around.
    id: 'peddler',
    scope: 'global',
    weight: () => 0, // NOT rolled from the random pool — scheduled ~every 5-6 months in rollWeeklyEvent
    title: '🎪 The Mysterious Peddler',
    body: () => 'A cloaked wagon creaks to a halt outside the ranch. "Wares for the discerning tamer," the peddler rasps. "Coin only. I do not linger."',
    choices: [{ label: 'Wave him off', apply: (g) => g }], // static fallback — real stock below
    choicesFor: (g) => {
      const stock: EventChoiceDef[] = []
      for (const s of STATS) {
        const tier = g.trainingGear?.[s] ?? 0
        if (tier < 5) stock.push({
          label: `${GEAR_NAMES[s][tier]} — ${s} training +${(tier + 1) * 5}%`,
          note: () => `permanent · tier ${tier + 1}/5`,
          cost: () => GEAR_TIER_PRICES[tier],
          keepOpen: true,
          apply: (gg) => buyGear(gg, s),
        })
      }
      stock.push({
        label: '🧪 Elder Tonic — +2 months career span (one monster)',
        note: () => 'use it from a monster’s panel · unlimited stock',
        cost: () => TONIC_COST,
        keepOpen: true,
        apply: (gg) => ({ ...gg, gold: gg.gold - TONIC_COST, tonics: (gg.tonics ?? 0) + 1 }),
      })
      stock.push({
        label: '📕 Stud Book — a frozen legacy earns uncapped stud fees',
        note: () => 'assign it in the Lab',
        cost: () => STUDBOOK_COST,
        keepOpen: true,
        apply: (gg) => ({ ...gg, gold: gg.gold - STUDBOOK_COST, studBooks: (gg.studBooks ?? 0) + 1 }),
      })
      stock.push({ label: 'Wave him off', apply: (gg) => gg })
      return stock
    },
  },
  {
    // Lab tech loan: once per save, needs a frozen genome — cheaper upkeep forever.
    id: 'labtech',
    scope: 'global',
    weight: (g) => ((g.labFrozen?.length ?? 0) >= 1 && !g.labTechLoan ? 2 : 0),
    title: '🧬 The Lab Tech’s Favour',
    body: () => 'The lab technician looks sheepish. "Cash-flow trouble. Lend me 300g and I’ll keep your freezers running at cost — permanently."',
    choices: [
      {
        label: 'Lend the 300g',
        note: () => `freeze upkeep ${RENTAL_PER_FROZEN}g → ${LAB_LOAN_UPKEEP}g/wk, forever`,
        cost: () => 300,
        apply: (g) => ({ ...g, gold: g.gold - 300, labTechLoan: true }),
      },
      { label: 'Money’s tight too', apply: (g) => g },
    ],
  },
  {
    // Soft-lock backstop (v0.6): with NO active monsters, a stray wanders in —
    // rollWeeklyEvent force-fires this so an empty stable is never game over.
    id: 'stray',
    scope: 'global',
    weight: (g) => (g.stable.every((c) => c.retired) || g.stable.length === 0 ? 100 : 0),
    title: '🐾 A Stray at the Gate',
    body: () => 'A scruffy young monster has been sleeping against your barn door. It looks at you, then at the empty training yard, and refuses to leave.',
    choices: [
      {
        label: 'Take it in',
        note: () => 'a free (unremarkable) recruit',
        apply: (g) => {
          // Never a prestige body — the stray is a soft-lock backstop, not a
          // free bypass of the Iron/Platinum licence gates.
          const c = newCareer('stray-' + g.week + '-' + g.nextId, { id: 'own-stray-' + g.nextId, licenseIndex: g.licenseIndex, gen: { noPrestige: true } })
          c.comfortWeeks = comfortWeeksFor(g)
          c.wildCap = wildCapFor(g)
          c.log = [`${c.name} the stray joins the ranch — scrappy, but willing.`]
          // deliberately ignores barn capacity: retirees may fill the barn, and
          // this event exists precisely to break that dead-end
          return { ...g, stable: [...g.stable, c], nextId: g.nextId + 1 }
        },
      },
    ],
  },
]

const eventById = (id: string) => EVENTS.find((e) => e.id === id)

// Flat per-week chance an eligible event fires. Kept simple/predictable for
// Phase 1; tuning knob lives here.
export const EVENT_CHANCE = 0.45
// The Mysterious Peddler visits on a SCHEDULE, not the random pool — about once
// every 5-6 months (22 weeks), with the exact week jittered per period so it
// still feels unpredictable. Rare enough that the player saves up for him.
export const PEDDLER_PERIOD = 22
export function isPeddlerWeek(g: GameState): boolean {
  if (!g.stable.some((c) => !c.retired)) return false
  const period = Math.floor(g.week / PEDDLER_PERIOD)
  const offset = hashString(g.seed + ':peddler:' + period) % PEDDLER_PERIOD
  return g.week % PEDDLER_PERIOD === offset
}

// Deterministic weekly roll — same (seed, week, stable) always yields the same
// result, so replays and reloads are stable. Returns the display-baked
// PendingEvent, or null for a quiet week.
export function rollWeeklyEvent(g: GameState): PendingEvent | null {
  // Soft-lock backstop (v0.6): an empty/all-retired stable ALWAYS draws the
  // stray — no chance roll. An unrecoverable save must not exist.
  if (g.stable.length === 0 || g.stable.every((c) => c.retired)) {
    const stray = eventById('stray')
    if (stray) return bakeEvent(stray, g)
  }
  // Mysterious Peddler (v0.62): scheduled ~every 5-6 months, force-shown on his
  // week (bypasses EVENT_CHANCE and the weighted pool) so a rare visit is never
  // missed to a coin-flip.
  if (isPeddlerWeek(g)) {
    const peddler = eventById('peddler')
    if (peddler) return bakeEvent(peddler, g)
  }
  const candidates: { ev: GameEvent; c?: Career; w: number }[] = []
  for (const ev of EVENTS) {
    if (ev.scope === 'global') {
      const w = ev.weight(g)
      if (w > 0) candidates.push({ ev, w })
    } else {
      for (const c of g.stable) {
        if (c.retired) continue
        const w = ev.weight(g, c)
        if (w > 0) candidates.push({ ev, c, w })
      }
    }
  }
  if (candidates.length === 0) return null
  const rng = mulberry32(hashString(g.seed + ':' + g.week + ':event'))
  if (rng() >= EVENT_CHANCE) return null
  const total = candidates.reduce((s, x) => s + x.w, 0)
  let r = rng() * total
  let chosen = candidates[candidates.length - 1]
  for (const x of candidates) { if (r < x.w) { chosen = x; break } r -= x.w }
  const { ev, c } = chosen
  return bakeEvent(ev, g, c)
}

// Bake an event's display shape (dynamic stock via choicesFor).
function bakeEvent(ev: GameEvent, g: GameState, c?: Career): PendingEvent {
  const defs = ev.choicesFor?.(g) ?? ev.choices
  return {
    id: ev.id,
    careerId: c?.id,
    title: ev.title,
    body: ev.body(g, c),
    choices: defs.map((ch) => ({ label: ch.label, note: ch.note?.(g, c), cost: ch.cost?.(g, c) })),
  }
}

// Apply the chosen branch and clear the pending event. Defensive: an
// unaffordable choice (the UI already disables it) leaves the event OPEN
// rather than driving gold negative, so a stray call can't corrupt state.
export function resolveEvent(g: GameState, choiceIdx: number): GameState {
  const pe = g.pendingEvent
  if (!pe) return g
  const ev = eventById(pe.id)
  const choice = (ev?.choicesFor?.(g) ?? ev?.choices)?.[choiceIdx]
  if (!ev || !choice) return { ...g, pendingEvent: null }
  const c = g.stable.find((x) => x.id === pe.careerId)
  if ((choice.cost?.(g, c) ?? 0) > g.gold) return g
  const applied = choice.apply(g, pe.careerId)
  // keepOpen (v0.6, peddler): re-bake the same event over the NEW state so the
  // player can keep shopping; a normal choice closes it. An apply may also
  // CHAIN a follow-up (e.g. challenge → result) — respect that.
  if (choice.keepOpen) return { ...applied, pendingEvent: bakeEvent(ev, applied, c) }
  return applied.pendingEvent && applied.pendingEvent !== pe ? applied : { ...applied, pendingEvent: null }
}

export function advanceWeek(g: GameState, plansOverride?: Record<string, WeekPlanEntry>): GameState {
  const plans = plansOverride ?? g.weekPlans ?? {}
  // Competing IS the weekly action (v0.5): monsters entered in a cup or the
  // rank-up trial fight instead of training — enforced here at the data layer
  // regardless of what the stored plan says (the UI locks it too).
  // ⚠️ A cup entry only consumes the week when the event IS this week — sign-ups
  // may be placed a week early (SIGNUP_LEAD_WEEKS) and that reservation week is
  // still a normal training week.
  const cupWasThisWeek = pendingCupIsThisWeek(g)
  const competing = new Set([...(cupWasThisWeek ? g.pendingTournament!.monsterIds : []), ...(g.pendingTrial?.monsterIds ?? []), ...(g.pendingRite?.monsterIds ?? [])])
  let gold = g.gold
  let rentalDue = (g.labFrozen?.length ?? 0) * labUpkeepPerFrozen(g)
  const stable = g.stable.map((c) => {
    if (c.retired) return ageOneWeek(c)
    // A monster with NO plan rests by default — this is what the UI has always
    // promised ("This week's plan — Rest" preview); previously the engine
    // silently did nothing (age only, no stamina/HP/MP recovery).
    const plan = plans[c.id] ?? { activity: 'rest', food: '' as const }
    let cur = c
    if (plan.food) {
      const fed = buyFood(cur, gold, plan.food, g.foodMarket, foodDiscountFor(g, plan.food))
      cur = fed.c
      gold = fed.gold
    } else if (plan.forage) {
      cur = forageFeed(cur) // free fallback — costs stamina + happiness, no gold
    }
    const planDrill = ALL_DRILLS.find((d) => d.id === plan.activity)
    const action: WeeklyAction = competing.has(c.id)
      ? { kind: 'compete' }
      : plan.activity === 'rest' || plan.activity === 'compete' ? { kind: 'rest' } // stale 'compete' with no live entry falls back to rest
        : plan.activity === 'excursion' ? { kind: 'excursion' }
          : planDrill?.kind === 'extreme' && !g.extremeUnlocked ? { kind: 'rest' } // extreme row locked behind the Manual
          : planDrill?.kind === 'diverse' && !g.diverseUnlocked ? { kind: 'rest' } // diverse row locked behind its Manual
            : { kind: 'train', drillId: plan.activity }
    // Pass the food ONLY if it was actually bought (buyFood sets fedThisWeek) —
    // an unaffordable food must not grant its training boost.
    const r = applyWeek(cur, action, gold, rentalDue, cur.fedThisWeek ? plan.food : '', g.trainingGear ?? {})
    rentalDue = 0 // charged once per week, not per monster
    gold = r.gold
    return r.c
  })
  if (rentalDue > 0) gold = Math.max(0, gold - rentalDue) // no monster processed the charge (all retired) — never below zero

  // Stud income (v0.6): a Stud Book turns a frozen champion's record into
  // weekly fees. (The retiree pension was removed in v0.77 — see pensionFor's
  // former home above.)
  const studGold = (g.labFrozen ?? []).reduce((s, fr) => s + studIncome(fr), 0)
  // Trainer stipend (v0.71, capped v0.77): a small weekly sponsorship that grows
  // with the trainer's level and then FLATTENS — it's a floor under a bad run,
  // not a career income.
  const stipendGold = trainerStipend(g)
  gold += studGold + stipendGold

  // Snapshot post-activity state for the per-monster digest below.
  const afterActivities = stable.map((c) => ({ stats: { ...c.stats }, hp: c.hp, mp: c.mp, stamina: c.stamina }))

  // Stage a signed-up cup or trial (v0.81): advanceWeek no longer RESOLVES the
  // event — it hands an ActiveCup to the interactive battle flow, which fights
  // each player match (picking per-fight tactics) and calls finalizeCup/
  // finalizeTrial to apply rewards / injury / exp / standings once the last
  // match ends. So lastBattle stays null through the tick, and the tournament
  // digest / seated-rival / license-earned logic all move to finalize.
  let activeCup: ActiveCup | null = null
  let enteredCupId: string | null = null
  const stagedCup = stageCup(g, stable)
  if (stagedCup) { activeCup = stagedCup.activeCup; enteredCupId = stagedCup.enteredId }
  if (!activeCup && g.pendingTrial) {
    const stagedTrial = stageTrial(g, stable)
    if (stagedTrial) activeCup = stagedTrial.activeCup
  }
  // One arena event per week: the rite only stages if no cup or trial claimed it.
  if (!activeCup && g.pendingRite) {
    const stagedRite = stageRite(g, stable)
    if (stagedRite) activeCup = stagedRite.activeCup
  }
  const lastBattle: LastBattle | null = null // resolved later, in finalizeCup/Trial
  const licenseEarned = g.licenseEarned // set by finalizeTrial on a trial win
  const trialCooldownUntil = g.trialCooldownUntil // set by finalizeTrial on a trial loss
  const riteCooldownUntil = g.riteCooldownUntil ?? 0 // set by finalizeRite on a rite loss
  // Trainer XP (Phase 5): retirements this week (cup podium XP is added in finalize).
  const retiredThisWeek = stable.filter((c, i) => c.retired && !g.stable[i].retired).length
  const trainerXp = (g.trainerXp ?? 0) + retiredThisWeek * RETIREMENT_XP
  // A staged cup counts as ENTERED this month immediately (the player committed),
  // so it can't be re-entered even before it's fought out.
  const entered = enteredCupId
    ? [...(g.enteredThisMonth ?? []), enteredCupId]
    : (g.enteredThisMonth ?? [])

  // "Last week" digest: per-monster deltas + activity + tournament result,
  // surfaced once on the next feeding screen (results otherwise live only in
  // per-monster logs).
  const lastWeek: string[] = []
  for (let i = 0; i < g.stable.length; i++) {
    const before = g.stable[i]
    const mid = afterActivities[i] // post-activity, pre-tournament — the activity's OWN effects
    const after = stable[i]
    if (before.retired) continue
    const plan = plans[before.id]
    const drill = plan ? ALL_DRILLS.find((d) => d.id === plan.activity) : undefined
    const actName = competing.has(before.id) ? (g.pendingTrial ? '🎖 rank-up trial' : '🏟 competed')
      : !plan ? 'rested (no plan set)'
        : plan.activity === 'rest' ? 'rested'
          : plan.activity === 'excursion' ? 'excursion'
            : drill?.name ?? plan.activity
    const bits: string[] = []
    for (const k of STATS) {
      const d = mid.stats[k] - before.stats[k]
      if (d !== 0) bits.push(`${k} ${d > 0 ? '+' : ''}${d}`)
    }
    const hpD = mid.hp - before.hp
    const mpD = mid.mp - before.mp
    const stD = mid.stamina - before.stamina
    if (hpD !== 0) bits.push(`HP ${hpD > 0 ? '+' : ''}${hpD}`)
    if (mpD !== 0) bits.push(`MP ${mpD > 0 ? '+' : ''}${mpD}`)
    if (stD !== 0) bits.push(`stamina ${stD > 0 ? '+' : ''}${stD}`)
    lastWeek.push(`${before.name} — ${actName}${bits.length ? ': ' + bits.join(', ') : ''}`)
    if (after.retired && !before.retired) lastWeek.push(`🏁 ${before.name} has retired.`)
  }
  // (v0.81) The tournament result is no longer known at tick time — it's fought
  // interactively and finalized afterwards, so its digest lines / injury summary
  // are shown on the announce screen (finalizeCup/Trial), not folded in here.
  if (studGold + stipendGold > 0) {
    const bits = [stipendGold > 0 ? `stipend +${stipendGold}g` : '', studGold > 0 ? `stud fees +${studGold}g` : ''].filter(Boolean)
    lastWeek.push(`🏛 Ranch income: ${bits.join(' · ')}`)
  }

  // Trainer level-up notice (Phase 5): crossing a level threshold this week.
  if (Math.floor(trainerXp / TRAINER_XP_PER_LEVEL) > Math.floor((g.trainerXp ?? 0) / TRAINER_XP_PER_LEVEL)) {
    const lvl = Math.floor(trainerXp / TRAINER_XP_PER_LEVEL) + 1
    lastWeek.push(`🎓 Trainer level ${lvl}!${lvl % 2 === 1 ? ' (+1 barn slot)' : ''}`)
  }

  // Seated-rival head-to-head moves in finalizeCup now (v0.81) — the cup result
  // isn't known at tick time.
  const rivals = g.rivals

  const week = g.week + 1
  const monthTurned = week % WEEKS_PER_MONTH === 0
  const base: GameState = {
    ...g,
    stable,
    gold,
    week,
    foodMarket: rollMarket(g.seed, week),
    market: monthTurned
      ? rollMarketOffers(g.seed, week / WEEKS_PER_MONTH, marketConfigOf(g))
      : g.market,
    // ⚠️ A cup entry is only spent once its event week has actually been ticked
    // through. A reservation placed a week early (SIGNUP_LEAD_WEEKS) must SURVIVE
    // this tick, or the entry silently evaporates before the event it booked.
    pendingTournament: cupWasThisWeek ? null : g.pendingTournament,
    pendingTrial: null,
    pendingRite: null,
    activeCup, // staged event handed to the interactive battle flow (v0.81)
    licenseEarned,
    trialCooldownUntil,
    riteCooldownUntil,
    lastBattle,
    enteredThisMonth: monthTurned ? [] : entered,
    // carry each monster's planned ACTIVITY into the new week; food resets, and
    // a locked 'compete' activity resets to rest (the event is over)
    weekPlans: Object.fromEntries(Object.entries(plans).map(([id, p]) => [id, { activity: p.activity === 'compete' ? 'rest' : p.activity, food: '' as const }])),
    lastWeek,
    pendingEvent: null,
    // rivals climb toward the player's level each week (LOOP_DESIGN Phase 2)
    rivals: rubberBandRivals({ ...g, rivals, stable }),
    trainerXp,
  }
  // Roll the new week's incident off the POST-tick state the player will see.
  return { ...base, pendingEvent: rollWeeklyEvent(base) }
}

// promoteMonster is GONE (v0.5): promotion = win the on-demand trial
// (startTrial → advanceWeek resolves it) then buyLicense in the Ranch Shop.

export function renameMonster(g: GameState, id: string, name: string): GameState {
  const trimmed = name.trim().slice(0, 24)
  if (!trimmed) return g
  return { ...g, stable: g.stable.map((c) => (c.id === id ? { ...c, name: trimmed } : c)) }
}

// Ability Selection UI (§1b): free any time EXCEPT the week a monster is
// signed up for a tournament (can't reroll abilities mid-entry). `moveIds`
// must all be moves the monster has actually learned; an empty array resets
// to auto-pick (careerMonster falls back to chooseLoadout).
export function setLoadout(g: GameState, id: string, moveIds: string[]): GameState {
  if (g.pendingTournament?.monsterIds.includes(id)) return g
  const c = g.stable.find((x) => x.id === id)
  if (!c) return g
  const learnedIds = new Set(learnedMoves(c.stats).map((mv) => mv.id))
  const valid = moveIds.filter((mid) => learnedIds.has(mid)).slice(0, 3)
  return { ...g, stable: g.stable.map((x) => (x.id === id ? { ...x, loadout: valid } : x)) }
}

// Innate choice is swapped the same way loadout moves are (user spec
// 2026-07-25): free any time except mid tournament-entry; the 2nd choice can
// only be selected once actually unlocked (INNATE_SECONDARY_LEVEL in a stat).
export function setActiveInnate(g: GameState, id: string, index: number): GameState {
  if (g.pendingTournament?.monsterIds.includes(id)) return g
  const c = g.stable.find((x) => x.id === id)
  if (!c) return g
  if (index !== 0 && index !== 1) return g
  if (index === 1 && Math.max(...STATS.map((s) => c.stats[s])) < INNATE_SECONDARY_LEVEL) return g
  return { ...g, stable: g.stable.map((x) => (x.id === id ? { ...x, activeInnate: index } : x)) }
}

// Tactics (2026-07-25): standing battle orders, editable ANY time — unlike
// loadout/innate swaps they stay open while signed up, since adjusting the
// game plan after scouting the field is exactly what they're for.
// (v0.81) Standing-orders setters are gone — tactics, protect, and mark are all
// chosen per-fight now (see MatchOrders / the pre-fight tactics screen), not
// stored on the career or the sign-up.

// Multi-combatant tactics gate (2026-07-25): target-priority orders only
// mean anything with multiple combatants on the field, so they stay locked
// until the player has a monster licensed for the first TEAM league —
// derived from TEAM_SIZE_BY_LEAGUE (currently Copper, 2v2) so this can never
// drift from the team-size table. Same stable+frozen progress convention as
// visibleLeagueCount.
export const firstTeamLeagueIndex = (): number => LEAGUES.findIndex((lg) => teamSizeForLeague(lg.name) > 1)
export function teamTacticsUnlocked(g: GameState): boolean {
  const idx = firstTeamLeagueIndex()
  return g.licenseIndex >= idx // per-player license (v0.5)
}


// --- Tournaments (§3): sign up in the review phase, battle resolves on the weekly tick ---
// A monster may enter its own league's events (full rewards) or any league BELOW
// it (reduced rewards via rewardMultiplier) — never above its license, EXCEPT
// as a licensed leader's guest (2026-07-25, the Copper-2v2 gate fix): in a
// TEAM event, as long as at least one member holds the event's league license
// (the "leader" — they vouch for the team), the other members may be up to ONE
// league below it. 1v1 events collapse to the old rule (the sole member IS the
// leader). Reward punch-down still keys off the team's minimum licenseIndex,
// and entering at-or-above your license is never penalized, so a guest never
// reduces the payout.
export function eligibleForTournament(g: GameState, t: Tournament): Career[] {
  const tIdx = leagueIndexOf(t.league)
  const floor = teamSizeForLeague(t.league) > 1 ? tIdx - 1 : tIdx
  return g.stable.filter((c) => !c.retired && c.licenseIndex >= floor)
}

// Does this roster satisfy the licensed-leader rule for the event?
export function teamHasLicensedLeader(g: GameState, t: Tournament, monsterIds: string[]): boolean {
  const tIdx = leagueIndexOf(t.league)
  return monsterIds.some((id) => (g.stable.find((x) => x.id === id)?.licenseIndex ?? -1) >= tIdx)
}

// A tournament's ABSOLUTE week on the game clock, for the year `g.week` is in.
// month/week are 1-based; the clock is 0-based.
export const tournamentAbsWeek = (g: GameState, t: Tournament): number =>
  yearOfWeek(g.week) * WEEKS_PER_YEAR + (t.month - 1) * WEEKS_PER_MONTH + (t.week - 1)

// SIGN-UP WINDOW (v0.92): the event week, or the week BEFORE it.
// Training is now chosen inside the weekly feed-and-train walkthrough, which
// runs at the START of a week — so entering a cup that same week would overwrite
// a plan the player had just set. Entering a week early makes the roster known
// BEFORE that window opens, and the walkthrough shows "competing" instead of
// offering drills it is about to discard.
export const SIGNUP_LEAD_WEEKS = 1
export function signUpWindowFor(g: GameState, t: Tournament): { opensAbs: number; eventAbs: number } {
  const eventAbs = tournamentAbsWeek(g, t)
  return { opensAbs: eventAbs - SIGNUP_LEAD_WEEKS, eventAbs }
}
export const isSignUpOpen = (g: GameState, t: Tournament): boolean => {
  const { opensAbs, eventAbs } = signUpWindowFor(g, t)
  return g.week >= opensAbs && g.week <= eventAbs
}

// Is a standing cup entry for THIS week? A week-early reservation is NOT — the
// roster still trains normally until the event week comes round. Everything
// that treats a sign-up as "competing now" must ask this, not just whether a
// pendingTournament exists.
export function pendingCupIsThisWeek(g: GameState): boolean {
  const p = g.pendingTournament
  if (!p) return false
  const t = tournamentCalendarFor(g.seed, yearOfWeek(g.week)).find((x) => x.id === p.tournamentId)
  return !!t && tournamentAbsWeek(g, t) === g.week
}

export function signUp(g: GameState, tournamentId: string, monsterIds: string[]): GameState {
  const t = tournamentCalendarFor(g.seed, yearOfWeek(g.week)).find((x) => x.id === tournamentId)
  if (!t || !isSignUpOpen(g, t)) return g
  if ((g.enteredThisMonth ?? []).includes(tournamentId)) return g // one entry per event
  const needed = teamSizeForLeague(t.league)
  if (monsterIds.length !== needed) return g
  if (new Set(monsterIds).size !== monsterIds.length) return g // no duplicate roster slots
  const tIdx = leagueIndexOf(t.league)
  const floor = needed > 1 ? tIdx - 1 : tIdx
  const ok = monsterIds.every((id) => {
    const c = g.stable.find((x) => x.id === id)
    return !!c && !c.retired && c.licenseIndex >= floor
  })
  if (!ok) return g
  if (g.pendingTrial) return g // one arena event per week (v0.5) — cancel the trial first
  if (g.pendingRite) return g // ditto for the Signature Rite (v0.91)
  // Cups are FREE to enter (entry fee removed 2026-07-XX) — the weekly action is
  // the real cost. Competing IS the weekly action (v0.5): entered monsters' plans
  // lock to 'compete' (advanceWeek enforces it at the data layer regardless).
  // ⚠️ ONLY when the event is THIS week. A week-early reservation must leave the
  // roster free to train the week in between — that lead time is the whole point,
  // and locking it here would just move the cost forward a week.
  const weekPlans = { ...(g.weekPlans ?? {}) }
  if (tournamentAbsWeek(g, t) === g.week) {
    for (const id of monsterIds) weekPlans[id] = { ...(weekPlans[id] ?? { activity: 'rest', food: '' as const }), activity: 'compete' }
  }
  return { ...g, weekPlans, pendingTournament: { tournamentId, monsterIds, feePaid: 0 } }
}

// Cancelling before the weekly tick frees the entered monsters' locked 'compete'
// week back to rest (cups are free, so there's no fee to refund).
export function cancelSignUp(g: GameState): GameState {
  const weekPlans = { ...(g.weekPlans ?? {}) }
  for (const id of g.pendingTournament?.monsterIds ?? []) {
    if (weekPlans[id]?.activity === 'compete') weekPlans[id] = { ...weekPlans[id], activity: 'rest' }
  }
  return { ...g, gold: g.gold + (g.pendingTournament?.feePaid ?? 0), weekPlans, pendingTournament: null }
}

// League strength band (user spec 2026-07-21: "a wood cup should always stay
// capped to its league limit" — the league is a FIXED standard, independent of
// the player): every rival team rolls its strength somewhere in 60-100% of the
// league's budget (cap × 3.5), from the event seed. A fresh entrant faces the
// weak end of genuine league competition and grows into (then out of) the cup;
// the same cup is always the same strength, which is also what makes scouting
// and placements meaningful. Replaces the old min(playerTotal, budget)
// rubber-banding.
export const RIVAL_BAND_MIN = 0.65 // v0.87 mid-game pass: 0.6 → 0.65 — fewer rolled-weak teams padding round-robin placements
export const RIVAL_BAND_MAX = 1.0
// Per-rival-monster stat budget = cap × this × band (2026-07-22 balance): was
// 3.5, which put every rival ~3-4 stats near cap — far beyond what a player can
// train in a monster's lifespan, so a just-ranked-up player placed dead last at
// every league. 2.0 is a strong-but-reachable well-rounded monster (2-3 stats
// near cap), so a dedicated player is genuinely competitive at-league.
export const RIVAL_BUDGET_MULT = 1.8

// Difficulty escalation (v0.75): the flat 1.8 was a CONSTANT ratio of the league
// cap, but the player's power compounds (economy + breeding buffs + longer life)
// faster than a fixed ratio, so late leagues became walkovers. rivalBudgetMult()
// nudges the ratio up gently by league so difficulty keeps pace with the player's
// growth — constant challenge across the whole ladder. Deliberately SHALLOW per the
// "small increments, sim-validated" rule: Wood 1.8 → Tamer Elite ~1.98 (no extreme
// Masters spike). Tune the step from the long-haul sim, not by feel.
export const RIVAL_BUDGET_STEP = 0.03 // v0.87 mid-game pass: 0.02 → 0.03 (the increment v0.75's ledger entry prescribed) — Wood 1.8 → Tamer Elite ~2.07
export function rivalBudgetMult(leagueIndex: number): number {
  return RIVAL_BUDGET_MULT + Math.max(0, leagueIndex) * RIVAL_BUDGET_STEP
}

// Rival team composition (user spec 2026-07-21): "a mixture of support and
// damage dealing classes, with more damage dealing classes in the case of an
// odd number" — even sizes split 50/50, odd sizes lean damage.
export function compositionTemplate(teamSize: number, plan?: TeamGameplan): ClassRole[] {
  // Without a plan this is the historical half-and-half split (kept so any
  // caller that has no archetype still gets a sane team).
  if (!plan) {
    const damage = Math.ceil(teamSize / 2)
    return Array.from({ length: teamSize }, (_, i): ClassRole => (i < damage ? 'damage' : 'support'))
  }
  // ARCHETYPE-DRIVEN (v0.91). The gameplan used to be rolled AFTER the team was
  // built and simply stamped on top, so 'bulwark' regularly described a roster
  // with no tanks and 'attrition' one with no sustain. The plan now decides the
  // roster it is going to run, which is what makes a scouted tell honest.
  const { mix } = GAMEPLANS[plan]
  const total = mix.damage + mix.support
  // At least one of each whenever the team is big enough to hold both, so a
  // rushdown still has someone to keep it standing and a bulwark still has a
  // carry to protect — an archetype with no win condition is just a worse team.
  let dmg = Math.round((teamSize * mix.damage) / total)
  // ⚠️ A SOLO monster has no team to support, so it must be able to fight:
  // bulwark's 2/4 mix rounds to ZERO damage at teamSize 1, which fielded a
  // Wood/Copper rival holding only Mend + Focus — no damage move at all, able
  // to use nothing but the free Attack. The plan still reads through its
  // TACTICS at 1v1 (a solo bulwark guards, a solo rushdown charges).
  dmg = teamSize === 1 ? 1 : Math.max(1, Math.min(teamSize - 1, dmg))
  return Array.from({ length: teamSize }, (_, i): ClassRole => (i < dmg ? 'damage' : 'support'))
}

// A rival monster appropriate to a target stat total AND a battle role: scaled
// via generateMonster's train-points system with a random 0.85-1.15x jitter,
// rejecting exclusive bodies (Draconic/Abyssal/Mythical) unless the tournament
// allows them (Silver+), and rejecting candidates whose TRAINED class doesn't
// match the requested role — so a "support" slot really does field a
// Tank/Sage/Bard/Orator/Spellshield, loadout and AI included.
const EXCLUSIVE_BODIES = ['Draconic', 'Abyssal', 'Mythical']
function generateRivalMonster(seedBase: string, targetTotal: number, allowExclusive: boolean, role?: ClassRole): Monster {
  let fallback: Monster | null = null
  for (let i = 0; i < 50; i++) {
    const seed = 'rival-' + hashString(seedBase + ':' + i).toString(36)
    const preview = generateMonster(seed, { train: 0 })
    if (!allowExclusive && EXCLUSIVE_BODIES.includes(preview.species.body)) continue
    const baseTotal = STATS.reduce((sum, k) => sum + preview.stats[k], 0)
    const rng = mulberry32(hashString(seed + ':scale'))
    const train = Math.max(0, Math.round((targetTotal - baseTotal) * (0.85 + rng() * 0.3)))
    const candidate = generateMonster(seed, { train })
    fallback = fallback ?? candidate
    if (role && roleOfClass(classForStats(candidate.stats)) !== role) continue
    return candidate
  }
  // 50 tries without a role match — take the first legal candidate rather than none.
  return fallback ?? generateMonster('rival-fallback-' + seedBase, { train: 0 })
}

// A full rival TEAM: role slots from the composition template, each member
// independently scaled to the same per-monster budget.
function generateRivalTeam(seedBase: string, teamSize: number, targetTotal: number, allowExclusive: boolean, plan?: TeamGameplan): Monster[] {
  const team = compositionTemplate(teamSize, plan).map((role, i) => generateRivalMonster(seedBase + ':m' + i, targetTotal, allowExclusive, role))
  if (plan) equipForPlan(team, plan)
  // Formation (wave 2): roster order is the formation (front half = front
  // line), so rivals sort sturdiest-first — walls up front, casters shielded
  // behind them — instead of the arbitrary generation order. Deterministic
  // (stable sort on CON), so scouting still previews the exact real team.
  return team.sort((a, b) => b.stats.CON - a.stats.CON)
}

// Bend each member's LOADOUT toward the team's win condition (v0.91). Rival
// loadouts are auto-picked by chooseLoadout, which ranks by raw output and knows
// nothing about what the team is trying to do — so an 'attrition' team would
// field zero poison and a 'focusfire' team no way to actually mark a target.
//
// This swaps at most ONE slot per monster, and only for a move that monster has
// genuinely learned, so a rival never fields something a player of the same
// stats could not. The weakest existing move makes way.
function equipForPlan(team: Monster[], plan: TeamGameplan): void {
  const wants = GAMEPLANS[plan].wants
  if (!wants) return
  const used = new Set<Monster>() // at most ONE swapped slot per monster
  const swapIn = (m: Monster, pick: (mv: Move) => boolean): boolean => {
    if (m.loadout.some(pick)) return true // already covered — costs no slot
    if (used.has(m)) return false
    const candidate = m.learned.filter(pick).sort((a, b) => b.power - a.power)[0]
    if (!candidate) return false
    const worst = [...m.loadout].sort((a, b) => a.power - b.power)[0]
    m.loadout = m.loadout.map((mv) => (mv === worst ? candidate : mv))
    used.add(m)
    return true
  }
  const isSetter = (kind: StatusKind) => (mv: Move) => mv.status?.kind === kind
  const isPayoff = (kind: StatusKind) => (mv: Move) => mv.effects?.bonusVsStatus?.kind === kind

  // The plan's flavour status — attrition poisons, zone burns — placed first so
  // a scouted plan reads true even when no finisher for it exists.
  let setterOn: Monster | null = null
  if (wants.status) {
    for (const m of team) if (swapIn(m, isSetter(wants.status))) { setterOn = m; break }
  }

  // ⚠️ The setup→payoff combo is searched, not assumed. Only bleed/doom/burn/fear
  // have `bonusVsStatus` finishers in the pool — poison and vulnerable have NONE
  // — so a plan naming one of those could never assemble the combo it promised.
  // Instead: find a status this team can genuinely BOTH set and cash, on two
  // different members, preferring the plan's own status when it qualifies.
  if (wants.payoff) {
    const kinds: StatusKind[] = []
    for (const m of team) for (const mv of m.learned) {
      const k = mv.effects?.bonusVsStatus?.kind
      if (k && !kinds.includes(k)) kinds.push(k)
    }
    if (wants.status && kinds.includes(wants.status)) kinds.sort((a) => (a === wants.status ? -1 : 0))
    outer: for (const kind of kinds) {
      for (const payer of team) {
        if (!payer.learned.some(isPayoff(kind))) continue
        // a DIFFERENT member has to be able to apply it, or the finisher is inert
        const setter = setterOn?.loadout.some(isSetter(kind)) ? setterOn
          : team.find((m) => m !== payer && (m.loadout.some(isSetter(kind)) || m.learned.some(isSetter(kind))))
        if (!setter || setter === payer) continue
        if (swapIn(setter, isSetter(kind)) && swapIn(payer, isPayoff(kind))) break outer
      }
    }
  }
  // Someone brings a team buff, so the roster fights as a unit rather than five
  // individuals who happen to share a side.
  if (wants.teamBuff) {
    for (const m of team) if (swapIn(m, (mv) => mv.target === 'team' && mv.type === 'buff')) break
  }
  // Zone teams actually bring area damage.
  if (wants.aoe) {
    for (const m of team) if (swapIn(m, (mv) => mv.type === 'damage' && (mv.target === 'allEnemies' || mv.target === 'frontRow' || mv.target === 'backRow'))) break
  }
}

// Every rival team a tournament will field, purely a function of (seed, week,
// tournament id) — deterministic and side-effect-free, so it can be called
// ahead of resolution (scouting reports, the bracket preview screen) and
// reproduce byte-identical teams to what resolveTournament actually fights.
// A rival team's gameplan (LOOP_DESIGN Phase 3): deterministic per
// (seed, week, tournament, team index), so scouting and resolution agree and a
// scouted plan is the one actually fought.
const ALL_GAMEPLANS: TeamGameplan[] = ['rushdown', 'bulwark', 'attrition', 'focusfire', 'zone']
export function gameplanForRivalTeam(seed: string, week: number, tId: string, r: number): TeamGameplan {
  const rng = mulberry32(hashString(seed + ':' + week + ':' + tId + ':gameplan:r' + r))
  return ALL_GAMEPLANS[Math.floor(rng() * ALL_GAMEPLANS.length)]
}
// Stamp a gameplan's standing orders onto a rival team — the SAME Tactics the
// player uses, consumed side-agnostically by the engine (personalityFor /
// pickEnemyTargetFor / protect all read m.tactics/m.protect). Bulwark also
// guards its top damage dealer.
function applyGameplan(team: Monster[], gp: TeamGameplan): Monster[] {
  const info = GAMEPLANS[gp]
  const dmgStat = (m: Monster) => Math.max(m.stats.STR, m.stats.DEX, m.stats.INT, m.stats.CHA)
  const carryIdx = info.protectCarry && team.length > 1
    ? team.reduce((best, m, i) => (dmgStat(m) > dmgStat(team[best]) ? i : best), 0)
    : -1
  return team.map((m, i) => ({ ...m, tactics: info.tactics, protect: i === carryIdx ? true : m.protect }))
}

// The named rival seated into a cup's field (v0.5): at the player's own league,
// the rival appears in ~1/3 of regular cups and is GUARANTEED at the annual
// marquee events — a recurring face, not an everywhere face. Deterministic per
// event (seed+week+id), so scouting, resolution, and the record all agree.
// Returns the rival-team index they occupy, or null.
export const RIVAL_PERSONALITY_GAMEPLAN: Record<RivalPersonality, TeamGameplan> = {
  aggressive: 'rushdown', cagey: 'bulwark', flashy: 'focusfire',
}
export const isMarqueeEvent = (t: Tournament): boolean => PRESTIGE_EVENTS.some((p) => p.name === t.name)
export function seatedRivalTeamIndex(g: GameState, t: Tournament, week = g.week): number | null {
  const rival = g.rivals?.[0]
  if (!rival || rival.licenseIndex !== leagueIndexOf(t.league)) return null
  if (isMarqueeEvent(t)) return 0
  const rng = mulberry32(hashString(g.seed + ':' + week + ':' + t.id + ':rivalseat'))
  return rng() < 1 / 3 ? 0 : null
}

export function generateRivalTeamsForTournament(g: GameState, t: Tournament): Monster[][] {
  const teamSize = teamSizeForLeague(t.league)
  const rivalCount = rivalTeamCountForLeague(t.league)
  const allowExclusive = leagueIndexOf(t.league) >= leagueIndexOf('Silver')
  const leagueBudget = LEAGUES[leagueIndexOf(t.league)].cap * rivalBudgetMult(leagueIndexOf(t.league))
  const seated = seatedRivalTeamIndex(g, t)
  return Array.from({ length: rivalCount }, (_, r) => {
    const bandRng = mulberry32(hashString(g.seed + ':' + g.week + ':' + t.id + ':band:r' + r))
    const teamBudget = leagueBudget * (RIVAL_BAND_MIN + bandRng() * (RIVAL_BAND_MAX - RIVAL_BAND_MIN))
    // ⚠️ The plan is chosen BEFORE the team is generated, so it can shape the
    // roster and the loadouts. It used to be rolled afterwards and stamped on.
    const gp = r === seated ? RIVAL_PERSONALITY_GAMEPLAN[g.rivals[0].personality] : gameplanForRivalTeam(g.seed, g.week, t.id, r)
    const team = generateRivalTeam(g.seed + ':' + g.week + ':' + t.id + ':r' + r, teamSize, teamBudget, allowExclusive, gp)
    return applyGameplan(team, gp)
  })
}

// Scouting fee (user spec 2026-07-22): pay to see an upcoming rival team
// before the fight — cheap reveals class + loadout, pricier also reveals raw
// stats. Both scale with league, same shape as entryFee.
export const scoutFee = (league: string, tier: 'basic' | 'full'): number =>
  (leagueIndexOf(league) + 1) * (tier === 'basic' ? 5 : 15)

// Standard circle-method round-robin schedule: every participant plays exactly
// once per scheduling round, so injuries accrue at the SAME rate for everyone
// (the old player-plays-all-matches-first ordering systematically fed the
// player's damaged team to fresh rivals). Returns ordered index pairs.
export function roundRobinSchedule(n: number): [number, number][] {
  const teams = [...Array(n).keys()]
  if (teams.length % 2 === 1) teams.push(-1) // bye slot for odd fields
  const rounds = teams.length - 1
  const half = teams.length / 2
  const out: [number, number][] = []
  let rest = teams.slice(1)
  for (let r = 0; r < rounds; r++) {
    const ring = [teams[0], ...rest]
    for (let i = 0; i < half; i++) {
      const a = ring[i]
      const b = ring[ring.length - 1 - i]
      if (a !== -1 && b !== -1) out.push([Math.min(a, b), Math.max(a, b)])
    }
    rest = [rest[rest.length - 1], ...rest.slice(0, rest.length - 1)]
  }
  return out
}

// Resolve a signed-up tournament using the post-week stable. Mutates `stable`
// in place (called from advanceWeek on its freshly-built array). A full
// round-robin: the player's team + `rivalTeamCountForLeague` generated rival
// teams, every pair fights exactly once (circle-method schedule). EVERY
// participant fights EVERY match at full HP/MP (user spec 2026-07-22: "we
// want a monster to heal to full health inbetween each fight, they do not
// carry injuries throughout the tournament") — no mid-event carry-forward.
// Rival strength is a FIXED league standard (60-100% of the league budget,
// rolled per team from the event seed) — independent of the player's own
// power. Reward scales by final placement. Injury is assessed ONCE, when the
// team returns home: a flat random 0-50% of max HP/MP regardless of how the
// event went — "only injured when they return to the ranch... must rest
// before they train again."
// --- Per-fight tactics (v0.81) --------------------------------------------
// The event is now STAGED by advanceWeek (stageCup/stageTrial) and fought
// interactively: the player picks MatchOrders before each of their matches, and
// only when the last player match ends is the event FINALIZED (rewards / injury
// / standings). See core.ts:ActiveCup.

// Build the player's fielded team as Monster[] for one match, applying that
// match's orders (per-member tactics, formation row order, protect). Full HP/MP
// — matches always start fresh. Shared by the live fight (App) and finalize, so
// both reproduce the exact same battle from the same orders.
export function buildEventPlayerTeam(playerCareers: Career[], orders?: MatchOrders): { team: Monster[]; happiness: number[] } {
  // Formation = roster order. Honour orders.formation where given; append any
  // member it omits (stale order) so the team is never silently short-handed.
  const byId = new Map(playerCareers.map((c) => [c.id, c]))
  const ordered: Career[] = []
  for (const id of orders?.formation ?? []) { const c = byId.get(id); if (c && !ordered.includes(c)) ordered.push(c) }
  for (const c of playerCareers) if (!ordered.includes(c)) ordered.push(c)
  const team = ordered.map((c) => {
    const m = careerMonster(c)
    return { ...m, hp: maxHp(m.stats), mp: maxMana(m.stats), tactics: orders?.tactics?.[c.id] ?? m.tactics, protect: c.id === orders?.protectId || undefined }
  })
  return { team, happiness: ordered.map((c) => c.happiness) }
}

// Apply the player's kill-order mark to the opposing team (a single focused
// slot). No-op when unmarked. The mark is the player's order, so it only ever
// tags the opponent in the player's OWN match.
export function applyMarkToOpponent(team: Monster[], mark?: number): Monster[] {
  return mark === undefined ? team : team.map((m, k) => (k === mark ? { ...m, marked: true } : m))
}

// Stage a signed-up cup: validate + build the fixed field (player ids + rival
// teams generated once, at THIS week's seed), but simulate nothing. Returns the
// ActiveCup for advanceWeek to hand to the interactive battle flow.
function stageCup(g: GameState, stable: Career[]): { activeCup: ActiveCup; enteredId: string } | null {
  const pending = g.pendingTournament
  if (!pending) return null
  // A reservation placed a week early must NOT fire early — it waits for its week.
  if (!pendingCupIsThisWeek(g)) return null
  const t = tournamentCalendarFor(g.seed, yearOfWeek(g.week)).find((x) => x.id === pending.tournamentId)
  const careers = pending.monsterIds.map((id) => stable.find((x) => x.id === id))
  if (!t || careers.some((c) => !c || c.retired)) return null
  const teamSize = teamSizeForLeague(t.league)
  // Oversized sign-up (pre-team-size-change save): bench the extras.
  const ids = pending.monsterIds.length > teamSize ? pending.monsterIds.slice(0, teamSize) : pending.monsterIds
  const rivalTeams = generateRivalTeamsForTournament(g, t)
  return { activeCup: { kind: 'cup', tournamentId: t.id, week: g.week, playerMonsterIds: ids, rivalTeams, matchOrders: {}, doneThrough: -1 }, enteredId: t.id }
}

// Stage the Signature Rite: one monster, one challenger, built now and fought
// later — the same deferred shape as a cup or trial so the battle phase needs no
// special case beyond routing finalize.
function stageRite(g: GameState, stable: Career[]): { activeCup: ActiveCup } | null {
  const pending = g.pendingRite
  if (!pending) return null
  const careers = pending.monsterIds.map((id) => stable.find((x) => x.id === id))
  if (careers.some((c) => !c || c.retired)) return null
  const size = pending.monsterIds.length
  if (size === 0) return null
  // ⚠️ The challenger side is capped at the LEAGUE's team size, not the roster's.
  // Matching the roster one-for-one was tried and is a trap: it makes a deep
  // stable strictly worse, because your two benchwarmers are forced in against
  // champions while your average drags. The long-haul bot went 0 for 13 that way.
  // Capping the opposition means a full roster is what it should be — an
  // advantage you earned — while each individual challenger stays harder than a
  // rank-up champion, which is the part the spec actually asked for.
  const foeSize = Math.min(size, teamSizeForLeague(LEAGUES[g.licenseIndex].name))
  const budget = LEAGUES[g.licenseIndex].cap * rivalBudgetMult(g.licenseIndex) * riteChampionMult(g.licenseIndex)
  const ritePlan = gameplanForRivalTeam(g.seed, g.week, 'rite-' + g.licenseIndex, 0)
  const raw = generateRivalTeam(g.seed + ':' + g.week + ':rite:' + g.licenseIndex, foeSize, budget, g.licenseIndex >= leagueIndexOf('Silver'), ritePlan)
  const team = applyGameplan(raw, ritePlan)
  return { activeCup: { kind: 'rite', tournamentId: 'rite-' + g.licenseIndex + '-' + g.week, week: g.week, playerMonsterIds: pending.monsterIds, rivalTeams: [team], matchOrders: {}, doneThrough: -1 } }
}

// Stage a rank-up trial: build the single champion team now; fight it later.
function stageTrial(g: GameState, stable: Career[]): { activeCup: ActiveCup } | null {
  const pending = g.pendingTrial
  if (!pending || g.licenseIndex >= LEAGUES.length - 1) return null
  const careers = pending.monsterIds.map((id) => stable.find((x) => x.id === id))
  if (careers.some((c) => !c || c.retired)) return null
  const league = LEAGUES[g.licenseIndex].name
  const teamSize = teamSizeForLeague(league)
  const ids = pending.monsterIds.slice(0, teamSize)
  const champBudget = LEAGUES[g.licenseIndex].cap * rivalBudgetMult(g.licenseIndex) * trialChampionMult(g.licenseIndex)
  const trialPlan = gameplanForRivalTeam(g.seed, g.week, 'trial-' + g.licenseIndex, 0)
  const champRaw = generateRivalTeam(g.seed + ':' + g.week + ':trial:' + g.licenseIndex, teamSize, champBudget, g.licenseIndex >= leagueIndexOf('Silver'), trialPlan)
  const champTeam = applyGameplan(champRaw, trialPlan)
  return { activeCup: { kind: 'trial', tournamentId: 'trial-' + g.licenseIndex, week: g.week, playerMonsterIds: ids, rivalTeams: [champTeam], matchOrders: {}, doneThrough: -1 } }
}

// Finalize a fought-out cup: replay the full round robin (player matches carry
// their per-match MatchOrders; rival-vs-rival are deterministic), score
// standings, and apply rewards / injury / exp / trainer XP. Called from the UI
// once the last player match ends. `stable` is a fresh array we write back into.
// EVERY participant fights EVERY match at full HP/MP (no mid-event carry-forward);
// rival strength is the FIXED league standard; reward scales by final placement;
// injury is a flat post-event 0-50% roll.
export function finalizeCup(g: GameState): GameState {
  const ac = g.activeCup
  if (!ac || ac.kind !== 'cup') return g
  const t = tournamentCalendarFor(g.seed, yearOfWeek(ac.week)).find((x) => x.id === ac.tournamentId)
  const stable = g.stable.map((c) => c)
  const idxs = ac.playerMonsterIds.map((id) => stable.findIndex((x) => x.id === id))
  if (!t || idxs.some((i) => i < 0 || stable[i].retired)) return { ...g, activeCup: null }
  const teamSize = teamSizeForLeague(t.league)
  const playerCareers = idxs.map((i) => stable[i])
  const rivalTeams = ac.rivalTeams

  const standings = [
    { label: 'Your Team', isPlayer: true, wins: 0, draws: 0, losses: 0, hpFracSum: 0 },
    ...rivalTeams.map((_, r) => ({ label: `Rival Team ${r + 1}`, isPlayer: false, wins: 0, draws: 0, losses: 0, hpFracSum: 0 })),
  ]
  const participants = standings // player is index 0; rival r is index r+1
  const matches: EventMatch[] = []

  let playerMatchIdx = 0
  for (const [i, j] of roundRobinSchedule(participants.length)) {
    const iIsPlayer = i === 0, jIsPlayer = j === 0
    let teamA: Monster[], teamB: Monster[], happA: number[], happB: number[]
    if (iIsPlayer || jIsPlayer) {
      const orders = ac.matchOrders[playerMatchIdx++]
      const built = buildEventPlayerTeam(playerCareers, orders)
      const oppTeam = applyMarkToOpponent(rivalTeams[(iIsPlayer ? j : i) - 1], orders?.mark)
      if (iIsPlayer) { teamA = built.team; happA = built.happiness; teamB = oppTeam; happB = oppTeam.map(() => 5) }
      else { teamA = oppTeam; happA = oppTeam.map(() => 5); teamB = built.team; happB = built.happiness }
    } else {
      teamA = rivalTeams[i - 1]; happA = teamA.map(() => 5); teamB = rivalTeams[j - 1]; happB = teamB.map(() => 5)
    }
    const result = simulateTeamBattle(teamA, teamB, happA, happB)
    matches.push({ aLabel: standings[i].label, bLabel: standings[j].label, teamA, teamB, result, involvesPlayer: iIsPlayer || jIsPlayer })

    const aHpFrac = result.finals.filter((f) => f.side === 'A').reduce((s, f) => s + f.hp / maxHp(teamA[f.slot].stats), 0) / teamSize
    const bHpFrac = result.finals.filter((f) => f.side === 'B').reduce((s, f) => s + f.hp / maxHp(teamB[f.slot].stats), 0) / teamSize
    standings[i].hpFracSum += aHpFrac
    standings[j].hpFracSum += bHpFrac
    if (result.winner === 'A') { standings[i].wins++; standings[j].losses++ }
    else if (result.winner === 'B') { standings[j].wins++; standings[i].losses++ }
    else { standings[i].draws++; standings[j].draws++ }
  }

  const sorted = [...standings].sort((a, b) => b.wins - a.wins || b.hpFracSum - a.hpFracSum)
  const withPlacement: EventStanding[] = sorted.map((s, i) => ({ ...s, placement: i + 1 }))
  const playerPlacement = withPlacement.find((s) => s.isPlayer)!.placement
  const fieldSize = participants.length

  // Punching-down reduction only applies if the WHOLE team is above the
  // tournament's league (team's minimum licenseIndex) — a mixed-league roster
  // is judged by its least-decorated member.
  const teamMinLicense = Math.min(...playerCareers.map((c) => c.licenseIndex))
  const leagueMult = rewardMultiplier(teamMinLicense, t.league)
  const placeFrac = placementRewardFraction(playerPlacement)
  const mult = placeFrac * leagueMult
  // Golden Truffle (2026-07-25): a monster that banked one and then WINS the cup
  // (1st place) earns +50% gold & exp. The flag is consumed either way (a loss
  // wastes the gamble) — cleared on every entrant below.
  const truffleWin = playerPlacement === 1 && playerCareers.some((c) => c.truffleReady)
  const truffleMult = truffleWin ? 1.5 : 1
  const goldPrize = Math.round((t.rewards.gold + CUP_ROSTER_STIPEND * (teamSize - 1)) * mult * truffleMult)
  // Participation exp (2026-07-25 playtest fix): 4th+ used to earn NOTHING —
  // a new player's first cup is a near-guaranteed sweep against the fixed
  // league standard, and going home with zero on top of the injury + entry fee
  // read as pure punishment. Hard lessons are still lessons: a small exp
  // trickle (no gold) softens the floor without touching the podium's value.
  const PARTICIPATION_EXP_FRACTION = 0.15
  const expMult = mult > 0 ? mult : PARTICIPATION_EXP_FRACTION * leagueMult

  let expNote = ''
  const updatedCareers = playerCareers.map((c) => {
    // Consume any banked Golden Truffle on every entrant (win or lose).
    const nc: Career = { ...c, stats: { ...c.stats }, log: [...c.log], tournamentHistory: [...c.tournamentHistory], truffleReady: false }
    if (truffleWin && c.truffleReady) nc.log.push(`  ↳ 🟡 Golden Truffle paid off — cup reward boosted +50%!`)
    if (expMult > 0) {
      const prof = trainingProfileFor(c.species)
      const pts = Math.max(1, Math.round((t.rewards.exp * expMult * truffleMult) / 10))
      const cap = statCapFor(c) // bloodline potential lifts the ceiling (Phase 5)
      if (prof.major) {
        // 60/40 split between the individually-authored major and the
        // body-derived minor — a "vanilla" species (no authored major) puts
        // the full reward into its minor instead (see the else branch).
        const p1 = Math.ceil(pts * 0.6)
        const p2 = pts - p1
        nc.stats[prof.major] = Math.min(cap, nc.stats[prof.major] + p1)
        nc.stats[prof.minor] = Math.min(cap, nc.stats[prof.minor] + p2)
        expNote = p2 > 0 ? `${prof.major} +${p1} · ${prof.minor} +${p2}` : `${prof.major} +${p1}`
      } else {
        nc.stats[prof.minor] = Math.min(cap, nc.stats[prof.minor] + pts)
        expNote = `${prof.minor} +${pts}`
      }
    }
    // Injury is a flat post-event roll (user spec 2026-07-22), independent of
    // placement or how any individual match went: every monster comes home at
    // a random 0-50% of max HP/MP, needing rest before training again.
    const injRng = mulberry32(hashString(g.seed + ':' + ac.week + ':' + t.id + ':injury:' + c.id))
    nc.hp = Math.max(1, Math.round(maxHp(nc.stats) * injRng() * 0.5))
    nc.mp = Math.round(maxMana(nc.stats) * injRng() * 0.5)
    nc.log.push(`  ↳ ${c.name} comes home from the tournament needing rest.`)
    nc.log.push(`🏟 ${t.name}: finished ${placementLabel(playerPlacement)} of ${fieldSize}` + (goldPrize > 0 ? ` — +${goldPrize}g` : ' — no reward'))
    nc.tournamentHistory.push({ name: t.name, league: t.league, week: ac.week, placement: playerPlacement, fieldSize })
    return nc
  })
  updatedCareers.forEach((nc, k) => { stable[idxs[k]] = nc })

  // Seated-rival head-to-head (v0.5, moved here from advanceWeek with the
  // deferred resolution): if the named rival's team was seated in this cup and
  // the player's match against it was decisive, the grudge record moves.
  let rivals = g.rivals
  const seat = seatedRivalTeamIndex(g, t, ac.week)
  if (seat !== null) {
    const label = `Rival Team ${seat + 1}`
    const m = matches.find((mm) => mm.involvesPlayer && (mm.aLabel === label || mm.bLabel === label))
    if (m && m.result.winner !== 'draw') {
      const playerWon = (m.aLabel === 'Your Team') === (m.result.winner === 'A')
      rivals = rivals.map((rv, i) => (i === 0 ? { ...rv, wins: rv.wins + (playerWon ? 1 : 0), losses: rv.losses + (playerWon ? 0 : 1) } : rv))
    }
  }

  return {
    ...g,
    stable,
    gold: g.gold + goldPrize,
    trainerXp: (g.trainerXp ?? 0) + cupTrainerXp(playerPlacement, leagueIndexOf(t.league)),
    rivals,
    activeCup: null,
    lastBattle: {
      tournamentId: t.id, tournamentName: t.name, league: t.league, teamSize, matches, standings: withPlacement,
      playerPlacement, fieldSize, goldReward: goldPrize, expNote,
    },
  }
}

export const TRIAL_CHAMPION_MULT = 1.25
// Champion multiplier by rung (v0.89):
//   Bronze→Gold  1.30  — the v0.87 mid-game bump; rank-ups stop being a surf-through
//   Wood→Iron / Platinum / Masters  1.25 — the baseline
//   Tamer Elite / Tamers Apex  1.15 — the SUMMIT relief. The champion budget is
//     `league cap × rivalBudgetMult × this`, and both of those already climb, so a
//     flat 1.25 up here compounded into a wall: the 25y×6 sim never once won the
//     Tamer Elite trial, leaving Tamers Apex unreachable by construction. The last
//     two gates stay the hardest on the ladder, just no longer impossible.
export const trialChampionMult = (leagueIndex: number): number =>
  leagueIndex >= 9 ? 1.15 : leagueIndex >= 3 && leagueIndex <= 6 ? 1.3 : TRIAL_CHAMPION_MULT
export const TRIAL_COOLDOWN_WEEKS = 3
// Finalize a fought-out rank-up trial (v0.81): the single champion match, fought
// with the player's chosen orders, then license-unlock / cooldown / injury. The
// champion team was built at stage time and stored on the ActiveCup.
export function finalizeTrial(g: GameState): { game: GameState; won: boolean } {
  const ac = g.activeCup
  if (!ac || ac.kind !== 'trial' || g.licenseIndex >= LEAGUES.length - 1) return { game: { ...g, activeCup: null }, won: false }
  const stable = g.stable.map((c) => c)
  const idxs = ac.playerMonsterIds.map((id) => stable.findIndex((x) => x.id === id))
  if (idxs.some((i) => i < 0 || stable[i].retired)) return { game: { ...g, activeCup: null }, won: false }
  const league = LEAGUES[g.licenseIndex].name
  const teamSize = teamSizeForLeague(league)
  const playerCareers = idxs.map((i) => stable[i])
  const built = buildEventPlayerTeam(playerCareers, ac.matchOrders[0])
  const playerTeam = built.team
  const champTeam = applyMarkToOpponent(ac.rivalTeams[0], ac.matchOrders[0]?.mark)
  const result = simulateTeamBattle(playerTeam, champTeam, built.happiness, champTeam.map(() => 5))
  const won = result.winner === 'A' // a draw is NOT good enough to dethrone the champion
  const hpFrac = (team: Monster[], side: 'A' | 'B') =>
    result.finals.filter((f) => f.side === side).reduce((s, f) => s + f.hp / maxHp(team[f.slot].stats), 0) / teamSize
  const standings: EventStanding[] = [
    { label: 'Your Team', isPlayer: true, wins: won ? 1 : 0, draws: result.winner === 'draw' ? 1 : 0, losses: won || result.winner === 'draw' ? 0 : 1, hpFracSum: hpFrac(playerTeam, 'A'), placement: won ? 1 : 2 },
    { label: 'League Champion', isPlayer: false, wins: won ? 0 : result.winner === 'draw' ? 0 : 1, draws: result.winner === 'draw' ? 1 : 0, losses: won ? 1 : 0, hpFracSum: hpFrac(champTeam, 'B'), placement: won ? 2 : 1 },
  ].sort((a, b) => a.placement - b.placement)
  const nextLeague = LEAGUES[g.licenseIndex + 1].name
  const updated = playerCareers.map((c) => {
    const nc: Career = { ...c, log: [...c.log] }
    const injRng = mulberry32(hashString(g.seed + ':' + ac.week + ':trial:injury:' + c.id))
    nc.hp = Math.max(1, Math.round(maxHp(nc.stats) * injRng() * 0.5))
    nc.mp = Math.round(maxMana(nc.stats) * injRng() * 0.5)
    nc.log.push(won
      ? `🏆 Defeated the ${league} Champion! The ${nextLeague} license is available in the Ranch Shop.`
      : `💢 Fell to the ${league} Champion — recover, train, and challenge again in ${TRIAL_COOLDOWN_WEEKS} weeks.`)
    nc.log = nc.log.slice(-40)
    return nc
  })
  updated.forEach((nc, k) => { stable[idxs[k]] = nc })
  // Beating the champion pays a purse worth HALF of a cup's 1st-place gold at
  // this league (a rank-up trial is de-calendarized, so this is its reward).
  const goldReward = won ? Math.round((POOL_REWARDS[league]?.gold ?? 0) * 0.5) : 0
  const lastBattle: LastBattle = {
    tournamentId: 'trial-' + g.licenseIndex, tournamentName: `Rank-up Trial — the ${league} Champion`, league, teamSize,
    matches: [{ aLabel: 'Your Team', bLabel: 'League Champion', teamA: playerTeam, teamB: champTeam, result, involvesPlayer: true }],
    standings, playerPlacement: won ? 1 : 2, fieldSize: 2, goldReward, expNote: '', isTrial: true,
  }
  const game: GameState = {
    ...g, stable, activeCup: null, lastBattle, gold: g.gold + goldReward,
    licenseEarned: won ? g.licenseIndex + 1 : g.licenseEarned,
    // g.week is already the post-tick week here (finalize runs after advanceWeek),
    // so this matches the old `g.week + 1 + COOLDOWN` computed pre-increment.
    trialCooldownUntil: won ? g.trialCooldownUntil : g.week + TRIAL_COOLDOWN_WEEKS,
    trainerXp: (g.trainerXp ?? 0) + (won ? 50 : 0),
  }
  return { game, won }
}

// --- Infirmary (2026-07-25 playtest addition): pay to restore a monster's
// HP/MP RIGHT NOW instead of spending a week resting — agency after a rough
// tournament, and a recurring gold sink that scales with league. Fee scales
// with how much is actually missing (min 5g), so topping up a scratch is
// cheap and a full revive after a sweep costs real money. Stamina is NOT
// restored — only Rest recovers fatigue; the infirmary mends wounds.
export function infirmaryFee(c: Career): number {
  const missingHp = 1 - c.hp / maxHp(c.stats)
  const missingMp = maxMana(c.stats) > 0 ? 1 - c.mp / maxMana(c.stats) : 0
  if (missingHp <= 0 && missingMp <= 0) return 0
  return Math.max(5, Math.ceil((missingHp + missingMp) * (c.licenseIndex + 1) * 12))
}

// Resolve the Signature Rite. Win and the move is forged, themed on the
// monster's own best stat and tiered by the player's league; that stat's CURRENT
// value becomes the bar every heir must clear to awaken its inherited copy.
// Lose and it costs a cooldown and the week — nothing permanent.
export function finalizeRite(g: GameState): { game: GameState; won: boolean } {
  const ac = g.activeCup
  if (!ac || ac.kind !== 'rite') return { game: { ...g, activeCup: null }, won: false }
  const stable = g.stable.map((c) => c)
  const idxs = ac.playerMonsterIds.map((id) => stable.findIndex((x) => x.id === id))
  if (idxs.some((i) => i < 0 || stable[i].retired)) return { game: { ...g, activeCup: null }, won: false }
  const league = LEAGUES[g.licenseIndex].name
  const teamSize = ac.playerMonsterIds.length
  const playerCareers = idxs.map((i) => stable[i])
  const built = buildEventPlayerTeam(playerCareers, ac.matchOrders[0])
  const playerTeam = built.team
  const foeTeam = applyMarkToOpponent(ac.rivalTeams[0], ac.matchOrders[0]?.mark)
  const result = simulateTeamBattle(playerTeam, foeTeam, built.happiness, foeTeam.map(() => 5))
  const won = result.winner === 'A' // a draw proves nothing
  const hpFrac = (team: Monster[], side: 'A' | 'B') =>
    result.finals.filter((f) => f.side === side).reduce((s, f) => s + f.hp / maxHp(team[f.slot].stats), 0) / teamSize
  const standings: EventStanding[] = [
    { label: 'Your Stable', isPlayer: true, wins: won ? 1 : 0, draws: result.winner === 'draw' ? 1 : 0, losses: won || result.winner === 'draw' ? 0 : 1, hpFracSum: hpFrac(playerTeam, 'A'), placement: won ? 1 : 2 },
    { label: 'The Rite Challengers', isPlayer: false, wins: won ? 0 : result.winner === 'draw' ? 0 : 1, draws: result.winner === 'draw' ? 1 : 0, losses: won ? 1 : 0, hpFracSum: hpFrac(foeTeam, 'B'), placement: won ? 2 : 1 },
  ].sort((a, b) => a.placement - b.placement)

  // The whole stable fights, but ONE signature is forged: the entrant without
  // one that has the highest total stats — deterministic, and it reads as the
  // stable's champion stepping forward. Monsters that already carry a signature
  // are excluded rather than overwritten, so a deep legacy is never lost.
  // A WIN does not forge anything here. The player chooses which monster steps
  // forward AND which of its body's signature moves it takes (user spec), so the
  // reward is BANKED on GameState and claimed from the UI via claimSignature.
  const updated = playerCareers.map((c) => ({ ...c, stats: { ...c.stats }, log: [...c.log] }))
  updated.forEach((nc) => {
    if (!won) nc.log.push(`  ✖ The rite goes unanswered — the challengers hold. The site reopens next year.`)
    else nc.log.push(`  ★ The stable passes the rite — one of you will carry a signature.`)
    const injRng = mulberry32(hashString(g.seed + ':' + ac.week + ':rite:injury:' + nc.id))
    nc.hp = Math.max(1, Math.round(maxHp(nc.stats) * injRng() * 0.5))
    nc.mp = Math.round(maxMana(nc.stats) * injRng() * 0.5)
    nc.log = nc.log.slice(-40)
  })
  updated.forEach((nc, k) => { stable[idxs[k]] = nc })

  const lastBattle: LastBattle = {
    tournamentId: ac.tournamentId, tournamentName: `The Signature Rite — ${league}`, league, teamSize,
    matches: [{ aLabel: 'Your Stable', bLabel: 'The Rite Challengers', teamA: playerTeam, teamB: foeTeam, result, involvesPlayer: true }],
    standings, playerPlacement: won ? 1 : 2, fieldSize: 2, goldReward: 0, expNote: '', isTrial: true,
  }
  const game: GameState = {
    ...g, stable, activeCup: null, lastBattle,
    // The clock runs WIN OR LOSE — the rite is an annual event, not a
    // retry-until-it-lands grind.
    riteCooldownUntil: g.week + RITE_COOLDOWN_WEEKS,
    riteReward: won ? { monsterIds: ac.playerMonsterIds, league } : null,
    trainerXp: (g.trainerXp ?? 0) + (won ? 40 : 0),
  }
  return { game, won }
}

// Claim the rite prize: the chosen monster forges the chosen move. Its CURRENT
// value in that move's stat becomes the bar every heir must clear to awaken an
// inherited copy, so a signature earned late is a harder legacy to live up to.
export function claimSignature(g: GameState, monsterId: string, moveId: string): GameState {
  const reward = g.riteReward
  if (!reward || !reward.monsterIds.includes(monsterId)) return g
  const idx = g.stable.findIndex((c) => c.id === monsterId)
  if (idx < 0 || g.stable[idx].retired || g.stable[idx].signature) return g
  const c = g.stable[idx]
  const move = signatureChoicesFor(c.species.body).find((m) => m.id === moveId)
  if (!move) return g // not a move this body may take
  const nc: Career = { ...c, log: [...c.log] }
  nc.signature = forgeSignature({
    moveId,
    stat: move.stat,
    atStat: c.stats[move.stat],
    eventName: `the Signature Rite (${reward.league})`,
    forgedBy: c.name,
  })
  nc.log = [...nc.log, `  ★ SIGNATURE FORGED — ${c.name} takes ${move.name}. Heirs inherit it dormant and awaken it at ${nc.signature.awakenStat} ${move.stat}.`].slice(-40)
  const stable = g.stable.map((x, i) => (i === idx ? nc : x))
  return { ...g, stable, riteReward: null }
}

export function healAtInfirmary(g: GameState, id: string): GameState {
  const c = g.stable.find((x) => x.id === id)
  if (!c) return g
  const fee = infirmaryFee(c)
  if (fee <= 0 || g.gold < fee) return g
  const nc: Career = { ...c, hp: maxHp(c.stats), mp: maxMana(c.stats), log: [...c.log, `⛑ Infirmary visit — fully mended (−${fee}g).`].slice(-40) }
  return { ...g, gold: g.gold - fee, stable: g.stable.map((x) => (x.id === id ? nc : x)) }
}

// --- Lab (§13.1): freeze / thaw / fuse ---
// Freeze = banking a FINISHED legacy (v0.6): retirees only — a monster's
// competing years end before its genome enters the bank. Capacity-limited
// (the bank is a curated collection). Decoration is captured for stud income
// and championship-bloodline breeding bonuses.


export const fusionRoom = (g: GameState): boolean => !barnFull(g)

// Does the player currently hold a fusable pair? (v0.89 UX nudge.) The balance
// sim only ever started fusing once the bot EARMARKED the cost — with both
// parents alive the 1000g is perpetually spent on something else, so a player
// needs telling that the pair they're holding is a fusion waiting to happen.
export function fusablePairIn(g: GameState): { a: Career; b: Career; label: string } | null {
  const pool = [...g.stable.filter((c) => !c.retired), ...(g.labFrozen ?? [])]
  for (let i = 0; i < pool.length; i++) {
    for (let j = i + 1; j < pool.length; j++) {
      const recipe = fusionRecipeFor(pool[i].species.body, pool[j].species.body)
      if (recipe) return { a: pool[i], b: pool[j], label: recipe.classLabel }
    }
  }
  return null
}

// Kept for the v0.77 save migration: rebuild a Career from a legacy stud record.
export function careerFromFrozen(fr: Frozen, id: string): Career {
  // Restore a raising shell from a banked genome, preserving stats + league. The
  // monster returns at Teen age (its prior calendar position isn't banked).
  const c = newCareer(fr.id, { id, stats: fr.stats, licenseIndex: fr.licenseIndex, potential: fr.potential })
  c.name = fr.name
  c.species = fr.species
  c.sex = fr.sex
  c.favouriteFood = fr.favouriteFood
  c.hatedFood = fr.hatedFood
  c.log = [`${fr.name} the ${fr.species.name} is thawed and back in your stable.`]
  return c
}

// --- Ranch Shop (§13.1): barn capacity + bulk-food upgrades ---
export const barnCost = (g: GameState): number => 120 * g.barnCapacity

export function upgradeBarn(g: GameState): GameState {
  const cost = barnCost(g)
  if (g.gold < cost) return g
  return { ...g, gold: g.gold - cost, barnCapacity: g.barnCapacity + 1 }
}

export function buyPantryContract(g: GameState): GameState {
  if (g.pantryContract || g.gold < PANTRY_CONTRACT_COST) return g
  return { ...g, gold: g.gold - PANTRY_CONTRACT_COST, pantryContract: true }
}
export function buyGrandLarder(g: GameState): GameState {
  if (g.grandLarder || g.gold < GRAND_LARDER_COST) return g
  return { ...g, gold: g.gold - GRAND_LARDER_COST, grandLarder: true }
}

// Both gates are enforced HERE (the data layer), not just in the shop's
// disabled state — the rank requirement is the real gate, gold is secondary.
export const canBuySpecialLicense = (g: GameState): boolean =>
  !g.specialLicense && g.licenseIndex >= SPECIAL_LICENSE_LEAGUE && g.gold >= SPECIAL_LICENSE_COST
export const canBuyEliteLicense = (g: GameState): boolean =>
  !g.eliteLicense && g.licenseIndex >= ELITE_LICENSE_LEAGUE && g.gold >= ELITE_LICENSE_COST

export function buySpecialLicense(g: GameState): GameState {
  if (!canBuySpecialLicense(g)) return g
  return { ...g, gold: g.gold - SPECIAL_LICENSE_COST, specialLicense: true }
}

export function buyEliteLicense(g: GameState): GameState {
  if (!canBuyEliteLicense(g)) return g
  return { ...g, gold: g.gold - ELITE_LICENSE_COST, eliteLicense: true }
}
