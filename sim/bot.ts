// Long-haul balance-sim bot (the "arbiter" from docs/BALANCING.md), rebuilt for
// the v0.81 deferred/interactive tournament flow and — v0.861 — given a full
// economy brain so it exercises EVERY mechanic a good human player would:
//
//   drills      basic + intensive + EXTREME (buys the Manual), aptitude-aware
//               stat targeting (species major/minor first), malus steered onto
//               off-build stats
//   food        training foods (+30% on the stat being drilled), Vigor Melon to
//               rescue a fatigued week, cheapest ration otherwise
//   market      restock buying to a league-sized stable, prestige preference
//               once licensed, Market Slots, Market Coach both tiers
//   shop        league licenses, Special/Elite prestige licenses, barn
//               expansion, comfort set, lab expansion, Extreme Manual, Pantry
//   care        infirmary healing instead of losing a week to rest, Elder
//               Tonics from the peddler applied to aging champions
//   dynasty     freeze at Elder, breed the best frozen pair, FUSE a spare
//               valid-recipe pair, generation climbing
//   events      buys the expensive beneficial choice when rich (peddler gear,
//               tonics), cheapest otherwise
//   fights      per-fight MatchOrders through stageCup → finalizeCup, all
//               tactics levers (temperament, priority, mana, opener sequence,
//               preserve, ccPriority, combo, formation, protect, mark)
//
//   npx tsx sim/bot.ts            # 3 seeds × 15 years, summary table
//   npx tsx sim/bot.ts 25 5       # <years> <seeds>
//
// NOT part of the app build (tsconfig `include` is ["src"]) — it drives the
// real exported game functions, so it stays in sync with the mechanics.

import { signatureChoicesFor } from '../src/signatureMoves'
import {
  GameState, advanceWeek, buyLicense, buyMonster, eligibleForTournament, finalizeCup, finalizeTrial,
  freezeToLab, breed, leagueIndexOf, monthOfWeek, newGame, nextLicenseCost, resolveEvent as resolveWeeklyEvent,
  roundRobinSchedule, signUp, startTrial, teamSizeForLeague, tournamentCalendarFor, trialStatus, weekOfMonth, yearOfWeek, WeekPlanEntry,
  finalizeRite, riteStatus, riteRoster, startRite, claimSignature, rivalBudgetMult, riteChampionMult,
  buySpecialLicense, canBuySpecialLicense, buyEliteLicense, canBuyEliteLicense,
  buyExtremeManual, EXTREME_MANUAL_COST, buyDiverseManual, DIVERSE_MANUAL_COST, buyMarketCoach, canBuyMarketCoach, coachCost,
  buyMarketSlot, marketSlotCost, buyMarketScout, scoutCost, setScoutPick, upgradeBarn, barnCost, effectiveBarnCap,
  buyComfortItem, COMFORT_ITEMS, expandLab, labExpandCost, healAtInfirmary, infirmaryFee,
  fuse, fusionRecipeFor, FUSION_COST, useTonic, buyPantryContract, offerGenOpts,
} from '../src/town'
import { Career, MAX_STAMINA, careerMonster, careerSpanYears, drillStamina, stageInfo, staminaMalus, statCapFor, statTrainingBonus } from '../src/game'
import { LEAGUES, MatchOrders, Monster, STATS, Stat, Tactics, Food, MAX_HAPPINESS, isPrestigeBody } from '../src/core'
import { maxHp, generateMonster } from '../src/monster'
import { SPECIES } from '../src/species'

const CC = new Set<string>(['stun', 'sleep', 'fear', 'confusion', 'silence', 'charm', 'knockback', 'blind'])
const total = (s: Record<Stat, number>) => STATS.reduce((t, k) => t + s[k], 0)
const healthy = (c: Career) => c.hp >= maxHp(c.stats) * 0.6 && !c.retired
// Goal-directed saving: while the Primeval ingredients are BOTH owned (a live
// Mythical + a live Draconic/Abyssal, stable or frozen), earmark the fusion
// cost so the weekly shopping ladder can't graze gold below it forever — the
// instrumented run showed the pair coexisting for 9 straight years while gold
// never once reached the fuse threshold at the moment it was checked.
// An EARNED licence is the single best purchase in the game (it lifts every cap
// and unlocks the next league), so a rational player stops shopping and saves for
// it. Without this the bot won Tamers Apex's trial and then spent the entrance fee
// on more monsters, every run, for 35 straight years.
function licenseEarmark(g: GameState): number {
  return g.licenseEarned > g.licenseIndex ? nextLicenseCost(g) : 0
}
function fusionEarmark(g: GameState): number {
  const pool = [...(g.labFrozen ?? []), ...g.stable.filter((c) => !c.retired && isPrestigeBody(c.species.body))]
  const hasMyth = pool.some((c) => c.species.body === 'Mythical')
  const hasMate = pool.some((c) => c.species.body === 'Draconic' || c.species.body === 'Abyssal')
  return hasMyth && hasMate ? FUSION_COST + 500 : 0
}
const WEEKS_PER_YEAR = 48
const RESERVE = 300 // gold floor kept for food/emergencies
type DrillLite = { id: string; gains: Partial<Record<Stat, number>>; kind: string }

// --- The coach AI: build one fight's orders, using every lever. -------------
function coachOrders(team: Career[], opp: Monster[]): MatchOrders {
  const favored = team.reduce((s, c) => s + total(c.stats), 0) >= opp.reduce((s, m) => s + total(m.stats), 0)
  const oppHasCaster = Math.max(...opp.map((m) => m.stats.INT + m.stats.WIS)) >= 380
  const markSlot = opp.map((m, i) => ({ i, t: total(m.stats) })).sort((a, b) => b.t - a.t)[0].i // focus their biggest
  const solo = team.length === 1
  const tactics: Record<string, Tactics> = {}
  for (const c of team) {
    const mon = careerMonster(c)
    const dmg = mon.loadout.filter((m) => m.type === 'damage')
    const buff = mon.loadout.filter((m) => m.type !== 'damage' && m.power === 0 && m.target !== 'enemy' && m.target !== 'allEnemies')
    const cc = mon.loadout.some((m) => (m.target === 'enemy' || m.target === 'allEnemies') && m.status && CC.has(m.status.kind))
    const comboReady = mon.loadout.some((p) => p.effects?.bonusVsStatus && mon.loadout.some((s) => s.status?.kind === p.effects!.bonusVsStatus!.kind))
    // Opening SEQUENCE: lead with a buff (if any), then the hardest hit — up to 2.
    const seq: string[] = []
    if (buff[0]) seq.push(buff[0].id)
    for (const d of dmg) { if (seq.length >= 2) break; if (!seq.includes(d.id)) seq.push(d.id) }
    tactics[c.id] = {
      temperament: favored ? 'aggressive' : 'cautious',
      targetPriority: oppHasCaster ? 'casters' : solo ? 'weakest' : 'focus',
      manaPolicy: favored ? 'burst' : 'conserve',
      openerIds: seq.length ? seq.slice(0, 2) : undefined,
      preserve: 'cautious',
      ccPriority: cc,
      comboDiscipline: comboReady,
    }
  }
  const byCon = [...team].sort((a, b) => b.stats.CON - a.stats.CON) // tanks to the front line
  return {
    tactics,
    formation: byCon.map((c) => c.id),
    protectId: solo ? undefined : [...team].sort((a, b) => a.stats.CON - b.stats.CON)[0].id, // guard the squishiest
    mark: solo ? undefined : markSlot,
  }
}

// Resolve a staged event by filling in every player match's orders, then
// finalizing — the bot's equivalent of the interactive battle screen.
function resolveEvent(g: GameState): GameState {
  const ac = g.activeCup
  if (!ac) return g
  const team = ac.playerMonsterIds.map((id) => g.stable.find((c) => c.id === id)).filter((c): c is Career => !!c)
  const oppOrder = ac.kind === 'trial' || ac.kind === 'rite' ? [0]
    : roundRobinSchedule(ac.rivalTeams.length + 1).filter(([i, j]) => i === 0 || j === 0).map(([i, j]) => (i === 0 ? j : i) - 1)
  const matchOrders: Record<number, MatchOrders> = {}
  oppOrder.forEach((oi, k) => { matchOrders[k] = coachOrders(team, ac.rivalTeams[oi]) })
  const g2: GameState = { ...g, activeCup: { ...ac, matchOrders, doneThrough: oppOrder.length - 1 } }
  return ac.kind === 'rite' ? finalizeRite(g2).game : ac.kind === 'trial' ? finalizeTrial(g2).game : finalizeCup(g2)
}

// --- Training brain ----------------------------------------------------------
// The 3-stat build for a career: stats the species trains FAST (major 1.2 →
// minor 1.1 → neutral), tie-broken by what's already highest — a real class
// identity instead of self-reinforcing the starting spread.
function buildStats(c: Career): Stat[] {
  const cap = statCapFor(c)
  return [...STATS]
    .sort((a, b) => statTrainingBonus(c.species, b) - statTrainingBonus(c.species, a) || c.stats[b] - c.stats[a])
    .filter((k) => c.stats[k] < cap)
    .slice(0, 3)
}

const cheapRation = (g: GameState): Food => (Object.entries(g.foodMarket)
  .filter(([f]) => ['vegetables', 'fruit', 'meat', 'sweet treats'].includes(f))
  .sort((a, b) => a[1] - b[1])[0]?.[0] ?? 'vegetables') as Food
const TRAIN_FOOD: Record<string, Food> = { STR: 'prime cut', CON: 'prime cut', WIS: 'scholars tea', INT: 'scholars tea', DEX: 'sprinters mix', CHA: 'sprinters mix' }

function planFor(c: Career, g: GameState, drills: DrillLite[]): WeekPlanEntry {
  const spare = g.gold - RESERVE - fusionEarmark(g) - licenseEarmark(g)
  // --- Feeding brain (v0.90). The premium upkeep foods were repriced to 90g, so
  // they are routine tools now, not emergencies. Food is eaten BEFORE the drill,
  // so it sets the stamina the activity starts from. Priority:
  //   1. Vigor Melon only for the fatigue bands that genuinely cost something:
  //      <=50 (-10%) and especially <=30 (HALVED). Buying out of the -5% band is
  //      a trap — 90g to recover ~0.8 stat points. Measured: a melon-every-week
  //      policy cost 2-5 breeds, 5 of 6 fusions and most Coach purchases per run,
  //      because weekly food drains the capital the big upgrades need.
  //   2. Bliss Berry only when happiness is genuinely low — it PERSISTS, so it
  //      lifts the happiness-weighted roll on every future week, but it competes
  //      with the same capital, so the bar is high.
  //   3. Training food (+30% on the drilled pair) when its -15 stamina can be
  //      paid without dropping out of the top band.
  //   4. Otherwise the cheapest ration.
  let food: Food = cheapRation(g)
  let stamina = c.stamina
  if (spare > 800 && staminaMalus(stamina) < 0.95) { food = 'vigor melon'; stamina = Math.min(MAX_STAMINA, stamina + 30) }
  else if (spare > 1200 && c.happiness <= MAX_HAPPINESS - 6) food = 'bliss berry'
  if (c.hp < maxHp(c.stats) * 0.5 || stamina < 12) return { activity: 'rest', food }
  const targets = buildStats(c)
  if (!targets.length) return { activity: 'rest', food }
  const stat = targets[g.week % targets.length] // rotate the build
  // Pick by USEFUL yield rather than a fixed tier ladder (v0.90): score every
  // affordable drill by the points it actually adds to the build — gains on a
  // build stat count, gains on a capped stat are wasted, and losses on a build
  // stat count against it. This is what lets DIVERSE compete on merit: +8/+8
  // with no malus scores 16 when both stats are on-build, but only 8 when one
  // isn't, so the bot takes it exactly when a human would.
  const cap = statCapFor(c)
  const unlocked = (d: DrillLite) =>
    (d.kind !== 'extreme' || g.extremeUnlocked) && (d.kind !== 'diverse' || g.diverseUnlocked)
  const useful = (d: DrillLite) => STATS.reduce((sum, k) => {
    const v = d.gains[k] ?? 0
    if (v > 0) return sum + (targets.includes(k) && c.stats[k] < cap ? v : 0)
    return sum + (targets.includes(k) ? v : 0) // a malus only hurts if it lands on the build
  }, 0)
  const affordable = drills.filter((d) => unlocked(d) && drillStamina(d.kind) <= stamina)
  const scored = affordable.map((d) => ({ d, u: useful(d) })).filter((x) => x.u > 0)
    .sort((a, b) => b.u - a.u || drillStamina(a.d.kind) - drillStamina(b.d.kind))
  const drill = scored[0]?.d ?? drills.find((d) => d.kind === 'basic' && (d.gains[stat] ?? 0) > 0)
  // Training food doubles down on the drilled stat — but only if the -15 stamina
  // still leaves enough for the drill AND keeps us in the full-effectiveness
  // band. A +30% boost is worthless if it costs a 10% fatigue penalty.
  if (drill && food === cheapRation(g) && spare > 800
    && staminaMalus(stamina - 15) === 1 && stamina - 15 >= drillStamina(drill.kind)) {
    food = TRAIN_FOOD[stat]
  }
  return { activity: drill?.id ?? 'rest', food }
}

// --- Shopping brain ----------------------------------------------------------
function shop(g: GameState): GameState {
  const spare = () => g.gold - RESERVE - fusionEarmark(g) - licenseEarmark(g)
  // League progression always comes first.
  if (g.licenseEarned > g.licenseIndex && g.gold >= nextLicenseCost(g)) g = buyLicense(g)
  // Prestige licenses are cheap gates to strictly better bodies.
  if (canBuySpecialLicense(g)) g = buySpecialLicense(g)
  if (canBuyEliteLicense(g)) g = buyEliteLicense(g)
  // Market Scout: the prestige-hunting tool (scout picks BYPASS market
  // rarity) — bought EARLY once licensed (it was starving at the bottom of
  // this ladder: the bigger purchases above drained gold below its threshold
  // every week for 25 straight years). Aim it at the Primeval ingredients —
  // a Mythical first (Elite), else a Draconic (Special).
  const sCost = scoutCost(g)
  if (sCost !== null && (g.specialLicense || g.eliteLicense) && spare() >= sCost + 300) g = buyMarketScout(g)
  if ((g.marketScout ?? 0) >= 1) {
    const own = [...g.stable, ...(g.labFrozen ?? [])]
    const hasMyth = own.some((c) => c.species.body === 'Mythical')
    const wantBody = g.eliteLicense && !hasMyth ? 'Mythical' : 'Draconic'
    const pick = SPECIES.find((sp) => sp.body === wantBody)?.id ?? null
    if (g.scoutPickA !== pick) g = setScoutPick(g, 'A', pick)
  }
  // Market Coach: THE ceiling lift (wildCap 800 → 900 → 1000) — top big-ticket.
  if (canBuyMarketCoach(g) && spare() >= (coachCost(g) ?? Infinity) + 400) g = buyMarketCoach(g)
  // Extreme Manual unlocks the top drill tier.
  if (!g.extremeUnlocked && spare() >= EXTREME_MANUAL_COST + 600) g = buyExtremeManual(g)
  // The diverse tier matches extreme's output with no malus — worth the same 800g.
  if (!g.diverseUnlocked && spare() >= DIVERSE_MANUAL_COST + 600) g = buyDiverseManual(g)
  // Barn: room for a league-sized team + a growing baby.
  const desired = Math.max(3, teamSizeForLeague(LEAGUES[g.licenseIndex].name) + 1)
  if (effectiveBarnCap(g) < desired + 1 && spare() >= barnCost(g) + 400) g = upgradeBarn(g)
  // Comfort set: +8wk of adult career per item, stable-wide.
  const nextComfort = COMFORT_ITEMS.find((i) => !(g.comfortOwned ?? []).includes(i.id))
  if (nextComfort && spare() >= nextComfort.price + 1200) g = buyComfortItem(g, nextComfort.id)
  // Lab: expand when the freezer is the bottleneck.
  const labCost = labExpandCost(g)
  if (labCost !== null && (g.labFrozen ?? []).length >= (g.labSlots ?? 3) && spare() >= labCost + 800) g = expandLab(g)
  // Market slots: more shots per restock, cheap.
  const slotCost = marketSlotCost(g)
  if (slotCost !== null && spare() >= slotCost + 1500) g = buyMarketSlot(g)
  if (!g.pantryContract && spare() >= 1800) g = buyPantryContract(g)
  return g
}

// Buy toward a league-sized stable; prefer prestige bodies once licensed
// (higher base totals, gentle/no flaws, long careers, fusion-parity ceiling).
function recruit(g: GameState): GameState {
  const desired = Math.min(effectiveBarnCap(g), Math.max(3, teamSizeForLeague(LEAGUES[g.licenseIndex].name) + 1))
  if (g.stable.filter((c) => !c.retired).length >= desired) return g
  const offers = g.market.map((o, i) => {
    const m = generateMonster(o.seed, offerGenOpts(o))
    return { i, price: o.price, prestige: isPrestigeBody(m.species.body), total: total(m.stats) }
  }).filter((o) => o.price <= Math.max(0, g.gold - RESERVE - fusionEarmark(g) - licenseEarmark(g)) * 0.6)
  const pick = offers.sort((a, b) => Number(b.prestige) - Number(a.prestige) || b.total / b.price - a.total / a.price)[0]
  return pick ? buyMonster(g, pick.i) : g
}

// --- Dynasty brain: freeze the aging, breed the best, fuse the spare. --------
function dynasty(g: GameState): GameState {
  // Freeze Elders (strongest first) while there's freezer room.
  const elders = g.stable
    .filter((c) => !c.retired && stageInfo(c.ageWeeks, careerSpanYears(c)).stage === 'Elder')
    .sort((a, b) => total(b.stats) - total(a.stats))
  for (const c of elders) {
    if ((g.labFrozen ?? []).length >= (g.labSlots ?? 3)) break
    g = freezeToLab(g, c.id)
  }
  const active = () => g.stable.filter((c) => !c.retired).length
  const desired = Math.min(effectiveBarnCap(g), Math.max(3, teamSizeForLeague(LEAGUES[g.licenseIndex].name) + 1))
  // Breed: best available pair by combined stats (parents stay frozen).
  const breedable = (g.labFrozen ?? []).filter((f) => (f.breedCount ?? 0) < 2).sort((a, b) => total(b.stats) - total(a.stats))
  if (breedable.length >= 2 && active() < desired && g.gold >= 300 + RESERVE) g = breed(g, breedable[0].id, breedable[1].id)
  // Fuse — two tiers of ambition:
  // 1) PRESTIGE fusion (Primeval, 1.25× potential): the endgame founder. Worth
  //    spending prestige stock on deliberately — consider ALL frozen monsters
  //    plus AGING (Elder+) stable prestige, since fuse() pulls from both pools.
  // 2) A spare base-body pair among frozen stock (keep the two best as
  //    breeding parents), as before.
  const frozen = g.labFrozen ?? []
  if (g.gold >= FUSION_COST + RESERVE + 500) {
    // A human building a Primeval doesn't wait for retirement age — the pair's
    // Elder windows never line up (the Mythical arrives ~a decade later). Buy
    // the ingredients and fuse them YOUNG: any age, weakest of each body first
    // so the fusion doesn't eat the current cup team's carries.
    const pool = [...frozen, ...g.stable.filter((c) => !c.retired && isPrestigeBody(c.species.body))]
    const weakest = (body: (b: string) => boolean) =>
      pool.filter((c) => body(c.species.body)).sort((a, b) => total(a.stats) - total(b.stats))[0]
    const myth = weakest((b) => b === 'Mythical')
    const mate = weakest((b) => b === 'Draconic' || b === 'Abyssal')
    if (myth && mate) g = fuse(g, myth.id, mate.id)
  }
  if (frozen.length >= 3 && active() < effectiveBarnCap(g) && g.gold >= FUSION_COST + RESERVE + 500) {
    const spareStock = [...(g.labFrozen ?? [])].sort((a, b) => total(b.stats) - total(a.stats)).slice(2)
    outer2: for (let a = 0; a < spareStock.length; a++) {
      for (let b = a + 1; b < spareStock.length; b++) {
        if (fusionRecipeFor(spareStock[a].species.body, spareStock[b].species.body)) {
          g = fuse(g, spareStock[a].id, spareStock[b].id)
          break outer2
        }
      }
    }
  }
  return g
}

interface Report {
  seed: string; peak: string; peakYear: number; gold: number; gen: number; bestStat: number
  cupsEntered: number; podiums: number; wins: number; trialsWon: number
  breeds: number; fusions: number; coach: number; prestigeOwned: number
}

function playGame(seed: string, years: number, DRILLS: DrillLite[]): Report {
  let g = newGame(seed, { tutorialEnabled: false })
  let cupsEntered = 0, podiums = 0, wins = 0, trialsWon = 0, peakLicense = 0, peakYear = 0, breeds = 0, fusions = 0
  let ritesAttempted = 0, ritesWon = 0, sigsHeld = 0, sigsInherited = 0
  const seenDynasty = new Set<string>()
  const endWeek = years * WEEKS_PER_YEAR
  while (g.week < endWeek) {
    // 0) Weekly event: when rich, take the priciest affordable choice (peddler
    //    gear, tonics — the expensive options are the beneficial ones); when
    //    poor, the cheapest.
    if (g.pendingEvent) {
      const cs = g.pendingEvent.choices
      let best = 0
      const rich = g.gold > 3500
      for (let i = 1; i < cs.length; i++) {
        const cost = cs[i].cost ?? 0
        if (rich ? cost > (cs[best].cost ?? 0) && cost <= g.gold - RESERVE : cost < (cs[best].cost ?? 0)) best = i
      }
      g = resolveWeeklyEvent(g, best)
    }
    // 1) Banked Elder Tonics go to the strongest aging fighter.
    if ((g.tonics ?? 0) > 0) {
      const target = g.stable
        .filter((c) => !c.retired && stageInfo(c.ageWeeks, careerSpanYears(c)).stage === 'Elder')
        .sort((a, b) => total(b.stats) - total(a.stats))[0]
      if (target) g = useTonic(g, target.id)
    }
    // 2) Infirmary: pay to mend instead of losing a training week to rest.
    for (const c of g.stable.filter((x) => !x.retired && x.hp < maxHp(x.stats) * 0.75)) {
      const fee = infirmaryFee(c)
      if (fee > 0 && g.gold >= fee * 3 + RESERVE) g = healAtInfirmary(g, c.id)
    }
    // 3) Shop ladder + recruitment + dynasty moves.
    g = shop(g)
    g = recruit(g)
    g = dynasty(g)
    // Count new dynasty careers by id prefix — a fusion consumes two parents
    // for one baby (net -1 roster), so count-delta detection missed them.
    for (const c of g.stable) {
      if (seenDynasty.has(c.id)) continue
      if (c.id.startsWith('own-fuse-')) { seenDynasty.add(c.id); fusions++ }
      else if (c.id.startsWith('own-breed-')) { seenDynasty.add(c.id); breeds++ }
    }
    // 4) Rank-up trial FIRST when genuinely ready (best fighter near the cap).
    const readyStat = Math.max(0, ...g.stable.filter(healthy).map((c) => Math.max(...STATS.map((k) => c.stats[k]))))
    if (trialStatus(g).ok && readyStat >= LEAGUES[g.licenseIndex].cap * 0.8) {
      const size = teamSizeForLeague(LEAGUES[g.licenseIndex].name)
      const elig = g.stable.filter(healthy).sort((a, b) => total(b.stats) - total(a.stats))
      if (elig.length >= size) g = startTrial(g, elig.slice(0, size).map((c) => c.id))
    }
    // 4b) THE SIGNATURE RITE (v0.91). Once a year, whole roster, harder than a
    // rank-up champion. The bot attempts it whenever the gate is open AND the
    // stable is actually competitive — the challenger budget is
    // cap x rivalBudgetMult x riteChampionMult, so throwing an underpowered
    // stable at it burns the entire year's attempt for nothing.
    if (!g.pendingTrial && !g.pendingTournament && riteStatus(g).ok) {
      const roster = riteRoster(g)
      const avg = roster.reduce((s2, c) => s2 + total(c.stats), 0) / Math.max(1, roster.length)
      const target = LEAGUES[g.licenseIndex].cap * rivalBudgetMult(g.licenseIndex) * riteChampionMult(g.licenseIndex)
      // The rite is ANNUAL, so waiting is free — hold out for a roster worth
      // spending the year's single attempt on. 0.65 sits just under the 0.69 peak
      // the bot actually reaches, so it fires near its own best moment.
      if (roster.length > 0 && avg >= target * 0.65) { g = startRite(g); ritesAttempted++ }
    }
    // 5) Otherwise the best cup at (or one below) our league.
    if (!g.pendingTrial && !g.pendingTournament) {
      const cups = tournamentCalendarFor(g.seed, yearOfWeek(g.week))
        .filter((t) => monthOfWeek(g.week) === t.month && weekOfMonth(g.week) === t.week)
        .filter((t) => leagueIndexOf(t.league) >= g.licenseIndex - 1)
        .sort((a, b) => leagueIndexOf(b.league) - leagueIndexOf(a.league))
      for (const t of cups) {
        const size = teamSizeForLeague(t.league)
        const elig = eligibleForTournament(g, t).filter(healthy).sort((a, b) => total(b.stats) - total(a.stats))
        if (elig.length >= size && !(g.enteredThisMonth ?? []).includes(t.id)) {
          const before = g.pendingTournament
          g = signUp(g, t.id, elig.slice(0, size).map((c) => c.id))
          if (g.pendingTournament && g.pendingTournament !== before) { cupsEntered++; break }
        }
      }
    }
    // 6) Weekly plans for everyone not competing (competing is forced in advanceWeek).
    const competing = new Set([...(g.pendingTournament?.monsterIds ?? []), ...(g.pendingTrial?.monsterIds ?? []), ...(g.pendingRite?.monsterIds ?? [])])
    const weekPlans: Record<string, WeekPlanEntry> = { ...g.weekPlans }
    for (const c of g.stable) if (!c.retired && !competing.has(c.id)) weekPlans[c.id] = planFor(c, g, DRILLS)
    g = { ...g, weekPlans }

    // 7) Tick, then resolve any staged event through the coach AI.
    g = advanceWeek(g)
    if (g.activeCup) {
      g = resolveEvent(g)
      const lb = g.lastBattle
      if (lb) {
        if (lb.isTrial) { if (lb.playerPlacement === 1) trialsWon++ }
        else { if (lb.playerPlacement === 1) wins++; if (lb.playerPlacement <= 3) podiums++ }
      }
    }
    // 8) CLAIM THE RITE PRIZE (v0.91). Winning banks the reward rather than
    // forging it, so an unclaimed prize would silently sit there forever. The bot
    // gives it to the entrant with the highest total stats that has none, and
    // picks the highest-power move that monster's body offers — a crude but
    // honest proxy, and enough to prove the whole flow runs unattended.
    if (g.riteReward) {
      ritesWon++
      const cands = g.stable.filter((c) => g.riteReward!.monsterIds.includes(c.id) && !c.retired && !c.signature)
      const star = cands.sort((a, b) => total(b.stats) - total(a.stats))[0]
      if (star) {
        const choices = signatureChoicesFor(star.species.body).sort((a, b) => b.power - a.power)
        if (choices.length) g = claimSignature(g, star.id, choices[0].id)
      }
      if (g.riteReward) g = { ...g, riteReward: null } // nobody eligible — do not stall
    }
    if (g.licenseIndex > peakLicense) { peakLicense = g.licenseIndex; peakYear = Math.floor(g.week / WEEKS_PER_YEAR) + 1 }
  }
  sigsHeld = [...g.stable, ...(g.labFrozen ?? [])].filter((c) => c.signature).length
  sigsInherited = [...g.stable, ...(g.labFrozen ?? [])].filter((c) => (c.signature?.inherited ?? 0) > 0).length
  const everyone = [...g.stable, ...(g.labFrozen ?? [])]
  const gen = Math.max(1, ...everyone.map((c) => c.generation ?? 1))
  const bestStat = Math.max(0, ...everyone.map((c) => Math.max(...STATS.map((k) => c.stats[k]))))
  const prestigeOwned = everyone.filter((c) => isPrestigeBody(c.species.body)).length
  return { seed, peak: LEAGUES[peakLicense].name, peakYear, gold: g.gold, gen, bestStat, cupsEntered, podiums, wins, trialsWon, breeds, fusions, coach: g.marketCoach ?? 0, prestigeOwned, ritesAttempted, ritesWon, sigsHeld, sigsInherited }
}

// --- Runner -----------------------------------------------------------------
async function main() {
  const years = Number(process.argv[2]) || 15
  const seeds = Number(process.argv[3]) || 3
  const { ALL_DRILLS } = await import('../src/drills')
  const DRILLS: DrillLite[] = ALL_DRILLS.map((d) => ({ id: d.id, gains: d.gains, kind: d.kind }))
  console.log(`Long-haul bot — ${seeds} seeds × ${years} years (full economy brain: all drills, foods, shop, market, care, dynasty, fusion)\n`)
  const rows: Report[] = []
  for (let s = 0; s < seeds; s++) rows.push(playGame('bot-seed-' + s, years, DRILLS))
  const pad = (v: unknown, n: number) => String(v).padEnd(n)
  console.log(pad('seed', 14) + pad('peak', 12) + pad('@yr', 5) + pad('gold', 8) + pad('best', 6) + pad('gen', 4) + pad('cups', 6) + pad('1st', 5) + pad('trials', 7) + pad('breed', 6) + pad('fuse', 5) + pad('rite', 6) + pad('sigs', 6) + pad('coach', 6) + 'prestige')
  for (const r of rows) console.log(pad(r.seed, 14) + pad(r.peak, 12) + pad(r.peakYear, 5) + pad(r.gold, 8) + pad(r.bestStat, 6) + pad(r.gen, 4) + pad(r.cupsEntered, 6) + pad(r.wins, 5) + pad(r.trialsWon, 7) + pad(r.breeds, 6) + pad(r.fusions, 5) + pad(r.ritesWon + '/' + r.ritesAttempted, 6) + pad(r.sigsHeld + '+' + r.sigsInherited, 6) + pad(r.coach, 6) + r.prestigeOwned)
  const peakIdx = rows.map((r) => LEAGUES.findIndex((l) => l.name === r.peak))
  console.log(`\npeak leagues: ${rows.map((r) => r.peak).join(' / ')}  (best ${LEAGUES[Math.max(...peakIdx)].name})`)
  const sum = (f: (r: Report) => number) => rows.reduce((a, r) => a + f(r), 0)
  console.log(`rites: ${sum((r) => r.ritesWon)} won of ${sum((r) => r.ritesAttempted)} attempted · signatures ${sum((r) => r.sigsHeld)} held (${sum((r) => r.sigsInherited)} inherited)`)
}
main()
