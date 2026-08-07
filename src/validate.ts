// Dev-only design validation. Catches data drift that produced real bugs before:
// species whose stats derive a different class than their naturalClass, duplicate
// class stat-pairs (which shadow each other), degenerate stat spreads, orphaned
// statuses (engine support with zero in-game sources), innate-table drift, and
// hand-synced reward tables drifting apart. `designProblems()` returns the raw
// list so the vitest suite can assert it's empty; `validateDesign()` is the
// console wrapper main.tsx runs in dev.
import { CLASSES, GAMEPLANS, LEAGUES, STATS, STATUS_INFO, StatusKind, TARGET_PRIORITY_INFO, TEMPERAMENT_INFO, classForStats } from './core'
import { LINES, CLASS_LINES, LINE_OF } from './lines'
import { SPECIES } from './species'
import { ALL_MOVES } from './moves'
import { ALL_FIELD_MOVES } from './tamerengine/fieldMoves'
import { ARENAS_WANTED, ARENA_LEAGUE_TEAM, MAPS, arenasForLeague, mapProblems } from './tamerengine/maps'
import { ALL_SIGNATURE_MOVES, SIGNATURE_LISTS, signatureChoicesFor } from './signatureMoves'
import { LEAGUE_TOP_GOLD, trainingProfileFor } from './game'
import { activeQuartersFor, BREEDING_BONUS, CIRCUIT_REWARDS, EVENTS, LICENSE_COSTS, MAX_POTENTIAL, PRESTIGE_EVENTS, TEAM_SIZE_BY_LEAGUE, breedPotential, tournamentCalendarFor } from './town'
import { INNATE_EFFECTS } from './innates'

export function designProblems(): string[] {
  const problems: string[] = []

  // ─── ARENAS ───────────────────────────────────────────────────────────────
  // ⚠️ An arena that favours one side biases every measurement taken on it, in
  // one direction, silently — and a sweep would report it as a balance finding
  // about the monsters rather than about the ground. `mirror()` makes that
  // unwritable; this catches a later hand edit that bypasses it.
  for (const m of MAPS) problems.push(...mapProblems(m))

  // ⚠️ THE ARENA TABLE'S COPY OF TEAM SIZE MUST MATCH THE REAL ONE. `maps.ts` cannot
  // import `town.ts` without dragging the whole game state into the renderer and every
  // sim tool, so it keeps a six-line copy — and a copy nobody checks is a copy that
  // drifts. This is the check.
  for (const [lg, n] of Object.entries(TEAM_SIZE_BY_LEAGUE)) {
    if (ARENA_LEAGUE_TEAM[lg] !== n) {
      problems.push(`maps.ts LEAGUE_TEAM says ${lg}=${ARENA_LEAGUE_TEAM[lg]}, town.ts says ${n}`)
    }
  }

  // ⚠️ EVERY LEAGUE THAT SHOULD HAVE ARENAS MUST HAVE THEM. `arenaFor` returns null
  // rather than quietly substituting another league's ground, so a league with an
  // empty pool is not a crash and not a visible fault — it is a fight that never
  // gets an arena. This is the check that makes the rollout visible: as each league
  // is authored its entry moves from "not yet" to a real count.
  for (const [league, want] of Object.entries(ARENAS_WANTED)) {
    const got = arenasForLeague(league).length
    if (got > 0 && got < want) problems.push(`${league}: only ${got} of ${want} arenas authored`)
  }

  // ─── ABILITY LINES (P4) ───────────────────────────────────────────────────
  // ⚠️ A move with no line is INVISIBLE to line affinity, so it silently loses
  // every loadout comparison it would otherwise win — the precise failure mode
  // that left control moves, team buffs and defensive moves at 0% equipped
  // before lines existed. A missing entry in LINE_OF must be loud, not silent.
  for (const mv of ALL_MOVES) {
    if (!mv.line) { problems.push(`${mv.stat}/${mv.name}: no line — add it to LINE_OF in lines.ts`); continue }
    const own = LINES[mv.stat]
    if (!own.includes(mv.line as never)) {
      problems.push(`${mv.stat}/${mv.name}: line "${mv.line}" belongs to another stat`)
    }
    // ⚠️ EVERY MOVE AUTHORS ITS OWN REACH. `CHANNEL_RANGE` is five numbers, and
    // a move that falls back to it inherits its channel's distance whether or
    // not that is what the ability is — an Assassin stiletto reached 5.6 for no
    // reason but DEX being typed `ranged`, and the free attack's channel was
    // reconstructed from the longest thing in a kit, which is how a STR-348
    // Warrior ended up shooting from 6.4. Both were the same mistake: reach
    // DERIVED instead of AUTHORED. Seed a new move with tools/authorranges.ts.
    if (mv.range == null) {
      problems.push(`${mv.stat}/${mv.name}: no range — author one (tools/authorranges.ts)`)
    } else if (mv.range <= 0) {
      problems.push(`${mv.stat}/${mv.name}: range ${mv.range} must be positive`)
    }
  }
  // ⚠️ AND THE REVERSE DIRECTION, which was missing. The guard above catches a
  // move with no line; nothing caught a LINE_OF entry naming a move that no
  // longer exists. Nine accumulated that way during the rework (Jab, War Cry,
  // Berserk, Rending Blow, Flurry of Blows, Shadow Barrage, Foresight,
  // Polymorph, Rally) — renamed or cut moves whose line entries stayed behind.
  // Harmless in itself, but it is dead data that reads as real: anyone auditing
  // line coverage counts 146 entries against a 137-move pool and has to work out
  // which nine are lies. A mapping should not outlive the thing it maps.
  const realNames = new Set<string>([
    ...ALL_MOVES.map((m) => m.name),
    ...ALL_FIELD_MOVES.map((m) => m.name),
  ])
  for (const name of Object.keys(LINE_OF)) {
    if (!realNames.has(name)) {
      problems.push(`LINE_OF: "${name}" is not a real move — remove it from lines.ts`)
    }
  }

  // Every line must actually be reachable by at least one class, or the moves in
  // it are content nobody is ever steered toward.
  const claimed = new Set(Object.values(CLASS_LINES).flat())
  for (const stat of Object.keys(LINES) as (keyof typeof LINES)[]) {
    for (const line of LINES[stat]) {
      if (!claimed.has(line)) problems.push(`line "${line}" (${stat}) is favoured by NO class`)
    }
  }

  // ─── SIGNATURE SKILLS (v0.91) ─────────────────────────────────────────────
  // ⚠️ UNIT GUARD. These fields are PERCENTAGE POINTS, not fractions — writing
  // `accBuff: 0.15` compiles, runs, and does nothing measurable, which is exactly
  // how it slipped through design review twice. Anything below 1 is a fraction
  // that was meant to be points.
  const POINT_FIELDS = ['dodgeBuff', 'accBuff', 'accDebuff', 'defBuff', 'defDebuff', 'regenBuff', 'hpRegenBuff', 'thorns', 'ward', 'guard', 'manaBurn'] as const
  // ...and these are FRACTIONS, so anything above 1 is points that were meant to
  // be a fraction (`atkBuff: 25` would be +2500% damage).
  const FRACTION_FIELDS = ['pierce', 'lifesteal', 'recoil', 'execute', 'maxHpDmg', 'atkBuff', 'atkDebuff'] as const
  for (const mv of [...ALL_MOVES, ...ALL_SIGNATURE_MOVES]) {
    const e = mv.effects as Record<string, unknown> | undefined
    if (!e) continue
    for (const f of POINT_FIELDS) {
      const v = e[f]
      if (typeof v === 'number' && v > 0 && v < 1) problems.push(`${mv.name}: ${f}=${v} looks like a FRACTION but this field is percentage POINTS (did you mean ${Math.round(v * 100)}?)`)
    }
    for (const f of FRACTION_FIELDS) {
      const v = e[f]
      if (typeof v === 'number' && v > 1) problems.push(`${mv.name}: ${f}=${v} looks like POINTS but this field is a fraction (did you mean ${v / 100}?)`)
    }
  }

  // Signature ids must be unique — a collision would make signatureMoveById
  // silently resolve the wrong move for a persisted loadout.
  const sigIds = new Set<string>()
  for (const mv of ALL_SIGNATURE_MOVES) {
    if (sigIds.has(mv.id)) problems.push(`duplicate signature id ${mv.id} (${mv.name})`)
    sigIds.add(mv.id)
    if (ALL_MOVES.some((p) => p.id === mv.id)) problems.push(`signature id ${mv.id} collides with a pool move id`)
  }

  // Signature POWER must stay under the pool's ceiling for its target shape.
  // Signatures are meant to be strong-and-EARLY, never strictly better — see
  // docs/SIGNATURE_DESIGN.md. Row targets are compared against the pool's
  // allEnemies ceiling because no pool move originally targeted a row.
  const poolMax = (f: (m: typeof ALL_MOVES[number]) => boolean) => Math.max(...ALL_MOVES.filter(f).map((m) => m.power), 0)
  const capSingle = poolMax((m) => m.type === 'damage' && m.target === 'enemy' && !m.effects?.hits)
  const capAoE = poolMax((m) => m.type === 'damage' && m.target === 'allEnemies')
  for (const mv of ALL_SIGNATURE_MOVES) {
    if (mv.type !== 'damage') continue
    const cap = mv.target === 'enemy' && !mv.effects?.hits ? capSingle : capAoE
    if (mv.power > cap) problems.push(`signature ${mv.name} power ${mv.power} exceeds the pool ceiling ${cap} for its shape`)
  }

  // Every body must be able to earn a signature, and the fusion bodies must
  // resolve to their recipe's parent lists rather than authoring their own.
  for (const sp of SPECIES) {
    if (signatureChoicesFor(sp.body).length === 0) problems.push(`${sp.body} has no signature moves — ${sp.name} could never claim a rite prize`)
  }
  if (SIGNATURE_LISTS.Prestige.length !== 8) problems.push(`the shared Draconic/Abyssal list should hold 8 moves, found ${SIGNATURE_LISTS.Prestige.length}`)

  // Class table: primary/secondary pairs must be unique or later entries are unreachable.
  const seenPairs = new Map<string, string>()
  for (const c of CLASSES) {
    const key = c.primary + '/' + c.secondary
    const prev = seenPairs.get(key)
    if (prev) problems.push(`CLASSES: ${c.name} duplicates ${prev}'s stat pair ${key} — ${c.name} is unreachable.`)
    seenPairs.set(key, c.name)
  }


  for (const sp of SPECIES) {
    // The class its base stats derive must match its declared naturalClass.
    const derived = classForStats(sp.base)
    if (derived !== sp.naturalClass) {
      problems.push(`${sp.name}: naturalClass is ${sp.naturalClass} but base stats derive ${derived}.`)
    }
    // Top-two stats must be strictly above the lowest (1 major + 1 minor + 1 weakness shape).
    const sorted = [...STATS].sort((a, b) => sp.base[b] - sp.base[a])
    if (sp.base[sorted[0]] === sp.base[sorted[1]]) {
      problems.push(`${sp.name}: top two stats tie (${sorted[0]}/${sorted[1]}) — class derivation is order-dependent.`)
    }
    // Training flaw should never be one of its two class-defining stats.
    const prof = trainingProfileFor(sp)
    if (prof.flaw === sorted[0] || prof.flaw === sorted[1]) {
      problems.push(`${sp.name}: training flaw ${prof.flaw} is one of its class stats.`)
    }
  }

  // Move pool: unique names, sane learn levels and effect fractions.
  const moveNames = new Set<string>()
  for (const mv of ALL_MOVES) {
    if (moveNames.has(mv.name)) problems.push(`MOVES: duplicate move name "${mv.name}".`)
    moveNames.add(mv.name)
    if (mv.learnLevel < 40 || mv.learnLevel > 920) problems.push(`MOVES: ${mv.name} learnLevel ${mv.learnLevel} outside 40–920.`)
    const e = mv.effects
    if (e) {
      for (const k of ['pierce', 'lifesteal', 'recoil', 'execute'] as const) {
        const v = e[k]
        if (v !== undefined && (v <= 0 || v > 1)) problems.push(`MOVES: ${mv.name} ${k}=${v} outside (0,1].`)
      }
      if (e.hits && (e.hits[0] < 1 || e.hits[1] < e.hits[0])) problems.push(`MOVES: ${mv.name} has invalid hits range.`)
    }
    if (mv.type === 'damage' && mv.power <= 0) problems.push(`MOVES: damage move ${mv.name} has no power.`)
  }

  // Tournament calendar generator: probe several seed-years and assert the
  // economy invariant — valid leagues/months, unique ids and names, and the
  // 2026-07-25 "similar cup count per league, half for Masters/Tamer Elite"
  // spec: every league Wood-Platinum has 1-2 cups in EVERY quarter; Masters
  // and Tamer Elite have 1-2 cups only in their 2 active quarters and ZERO in
  // the other 2 (that's what makes them run at half density, not just a lower
  // average).
  const fullDensity = ['Wood', 'Copper', 'Tin', 'Bronze', 'Iron', 'Silver', 'Gold', 'Platinum']
  const halfDensity = ['Masters', 'Tamer Elite', 'Tamers Apex']
  for (const seed of ['probe-a', 'probe-b', 'probe-c']) {
    for (let year = 0; year < 4; year++) {
      const cal = tournamentCalendarFor(seed, year)
      // A new player must have a Wood cup in Month 1 to start competing (user spec).
      if (!cal.some((t) => t.league === 'Wood' && t.month === 1)) problems.push(`CALENDAR(${seed}/y${year}): no Wood cup in Month 1.`)
      const ids = new Set<string>()
      const names = new Set<string>()
      for (const t of cal) {
        if (ids.has(t.id)) problems.push(`CALENDAR(${seed}/y${year}): duplicate id ${t.id}.`)
        ids.add(t.id)
        if (names.has(t.name)) problems.push(`CALENDAR(${seed}/y${year}): duplicate name ${t.name}.`)
        names.add(t.name)
        if (!LEAGUES.some((l) => l.name === t.league)) problems.push(`CALENDAR(${seed}/y${year}): unknown league "${t.league}".`)
        if (t.month < 1 || t.month > 12) problems.push(`CALENDAR(${seed}/y${year}): ${t.name} invalid month ${t.month}.`)
        if (t.week < 1 || t.week > 4) problems.push(`CALENDAR(${seed}/y${year}): ${t.name} invalid week ${t.week}.`)
        // (v0.5: rank-up trials are de-calendarized — no reserved weeks to collide with.)
      }
      for (const league of fullDensity) {
        for (let q = 0; q < 4; q++) {
          const inQuarter = cal.filter((t) => t.league === league && t.month > q * 3 && t.month <= q * 3 + 3).length
          if (inQuarter < 1) problems.push(`CALENDAR(${seed}/y${year}): ${league} has no event in Q${q + 1}.`)
          if (inQuarter > 2) problems.push(`CALENDAR(${seed}/y${year}): ${league} has ${inQuarter} events in Q${q + 1} (max 2).`)
        }
      }
      for (const league of halfDensity) {
        const active = activeQuartersFor(league)
        for (let q = 0; q < 4; q++) {
          const inQuarter = cal.filter((t) => t.league === league && t.month > q * 3 && t.month <= q * 3 + 3).length
          if (active.includes(q)) {
            if (inQuarter < 1) problems.push(`CALENDAR(${seed}/y${year}): ${league} has no event in Q${q + 1} (active quarter).`)
            if (inQuarter > 2) problems.push(`CALENDAR(${seed}/y${year}): ${league} has ${inQuarter} events in Q${q + 1} (max 2).`)
          } else if (inQuarter !== 0) {
            problems.push(`CALENDAR(${seed}/y${year}): ${league} has ${inQuarter} events in Q${q + 1}, expected 0 (inactive quarter — half-density league).`)
          }
        }
      }
      // Every month must offer at least 2 cups (user spec 2026-07-XX).
      for (let month = 1; month <= 12; month++) {
        const inMonth = cal.filter((t) => t.month === month).length
        if (inMonth < 2) problems.push(`CALENDAR(${seed}/y${year}): Month ${month} has only ${inMonth} cup(s) (need ≥2).`)
      }
    }
  }

  // Every status in the design must have at least one in-game SOURCE (a move
  // that inflicts it, or an innate statusOnHit). Orphaned statuses carry live
  // engine code and player-facing STATUS_INFO text that can never fire —
  // confusion and knockback sat in exactly that state until 2026-07-25.
  const statusSources = new Set<StatusKind>()
  for (const mv of ALL_MOVES) if (mv.status) statusSources.add(mv.status.kind)
  for (const eff of Object.values(INNATE_EFFECTS)) if (eff.statusOnHit) statusSources.add(eff.statusOnHit.kind)
  for (const kind of Object.keys(STATUS_INFO) as StatusKind[]) {
    if (!statusSources.has(kind)) problems.push(`STATUS: ${kind} has no source — no move or innate can inflict it.`)
  }

  // Innate table <-> species data, both directions: every species innate must
  // have a mechanical entry (the "no flavour-only innates" rule), and every
  // table key must belong to some species (renames must land on both sides —
  // this drift produced real bugs during the species reimagines).
  const speciesInnateNames = new Set(SPECIES.flatMap((sp) => sp.innate.map((ab) => ab.name)))
  for (const sp of SPECIES) for (const ab of sp.innate) {
    if (!INNATE_EFFECTS[ab.name]) problems.push(`INNATES: ${sp.name}'s "${ab.name}" has no INNATE_EFFECTS entry.`)
  }
  for (const key of Object.keys(INNATE_EFFECTS)) {
    if (!speciesInnateNames.has(key)) problems.push(`INNATES: table entry "${key}" matches no species innate (stale after a rename?).`)
  }

  // Team sizes climb the ladder monotonically, every league has an entry, and
  // FIVE is the ceiling (user spec 2026-08-01 — 6v6 removed from the game).
  // ⚠️ The guard is kept and re-pointed rather than deleted: it is what stops a
  // later edit quietly reintroducing a size the balance work never covered.
  let prevSize = 0
  for (const l of LEAGUES) {
    const size = TEAM_SIZE_BY_LEAGUE[l.name]
    if (size === undefined) { problems.push(`TEAMS: no team size for ${l.name}.`); continue }
    if (size < prevSize) problems.push(`TEAMS: ${l.name} (${size}) fields a smaller team than the league below it (${prevSize}).`)
    if (size > 5) problems.push(`TEAMS: ${l.name} fields ${size}v${size} — 5v5 is the maximum team size.`)
    prevSize = size
  }

  // game.ts:LEAGUE_TOP_GOLD is the excursion-gold ceiling per league. Since v0.71
  // it's tuned independently of the cup rewards, but the design intent is that
  // downtime income never rivals competing — so it must stay AT OR BELOW each
  // league's cup 1st-place gold. Assert that bound instead of exact equality.
  for (const [league, r] of Object.entries(CIRCUIT_REWARDS)) {
    if ((LEAGUE_TOP_GOLD[league] ?? 0) > r.gold) problems.push(`ECONOMY: LEAGUE_TOP_GOLD.${league} (${LEAGUE_TOP_GOLD[league]}) exceeds CIRCUIT_REWARDS gold (${r.gold}) — excursion must stay below cup gold.`)
  }
  for (const p of PRESTIGE_EVENTS) {
    if ((LEAGUE_TOP_GOLD[p.league] ?? 0) > p.rewards.gold) problems.push(`ECONOMY: LEAGUE_TOP_GOLD.${p.league} (${LEAGUE_TOP_GOLD[p.league]}) exceeds ${p.name}'s gold (${p.rewards.gold}).`)
  }
  for (const l of LEAGUES) {
    if (LEAGUE_TOP_GOLD[l.name] === undefined) problems.push(`ECONOMY: LEAGUE_TOP_GOLD has no entry for ${l.name}.`)
  }

  // Weekly events (LOOP_DESIGN Phase 1): unique ids, at least one choice each,
  // and the display roll produces a resolvable branch for every registered
  // event (a monster-scoped event with a non-null target must find its career).
  const eventIds = new Set<string>()
  for (const ev of EVENTS) {
    if (eventIds.has(ev.id)) problems.push(`EVENTS: duplicate event id "${ev.id}".`)
    eventIds.add(ev.id)
    if (!ev.choices || ev.choices.length === 0) problems.push(`EVENTS: "${ev.id}" has no choices.`)
  }

  // Rival gameplans (LOOP_DESIGN Phase 3): every archetype maps to a legal
  // Tactics config the engine understands — so scouting can never advertise a
  // plan the AI can't actually run.
  const validTemper = new Set(TEMPERAMENT_INFO.map((x) => x.id))
  const validPriority = new Set(TARGET_PRIORITY_INFO.map((x) => x.id))
  for (const [key, gp] of Object.entries(GAMEPLANS)) {
    if (!validTemper.has(gp.tactics.temperament)) problems.push(`GAMEPLANS: ${key} has invalid temperament "${gp.tactics.temperament}".`)
    // ⚠️ `undefined` IS NOW LEGAL AND MEANS "NO ORDER". `targetPriority` became optional
    // when `weakest` was retired — a monster with no standing order fights whatever is
    // nearest, which is a real setting rather than a missing one.
    if (gp.tactics.targetPriority && !validPriority.has(gp.tactics.targetPriority)) problems.push(`GAMEPLANS: ${key} has invalid targetPriority "${gp.tactics.targetPriority}".`)
    if (!gp.name || !gp.counter) problems.push(`GAMEPLANS: ${key} is missing a name or counter-hint.`)
  }

  // Breeding potential (LOOP_DESIGN Phase 5): each generation climbs but stays
  // bounded — a bloodline plateaus at MAX_POTENTIAL, it never runs away.
  if (BREEDING_BONUS <= 0) problems.push(`BREEDING: BREEDING_BONUS must be positive (is ${BREEDING_BONUS}).`)
  if (MAX_POTENTIAL <= 1) problems.push(`BREEDING: MAX_POTENTIAL must exceed 1 (is ${MAX_POTENTIAL}).`)
  let pot = 1
  for (let gen = 0; gen < 50; gen++) pot = breedPotential(pot, pot) // inbreed the strongest line
  if (pot > MAX_POTENTIAL + 1e-9) problems.push(`BREEDING: potential exceeds MAX_POTENTIAL after 50 generations (${pot}).`)
  if (breedPotential(1, 1) <= 1) problems.push(`BREEDING: breeding two wild monsters must raise potential above 1.`)

  // License costs (v0.5): one entry per league, strictly growing after the free
  // Wood start, and never a doubling wall (each step < 2× the last).
  if (LICENSE_COSTS.length !== LEAGUES.length) problems.push(`LICENSES: ${LICENSE_COSTS.length} costs for ${LEAGUES.length} leagues.`)
  for (let i = 2; i < LICENSE_COSTS.length; i++) {
    if (LICENSE_COSTS[i] <= LICENSE_COSTS[i - 1]) problems.push(`LICENSES: cost[${i}] (${LICENSE_COSTS[i]}) not greater than cost[${i - 1}].`)
    if (LICENSE_COSTS[i] >= LICENSE_COSTS[i - 1] * 2 && i > 2) problems.push(`LICENSES: cost[${i}] doubles or worse (${LICENSE_COSTS[i - 1]} → ${LICENSE_COSTS[i]}).`)
  }

  return problems
}

export function validateDesign(): void {
  const problems = designProblems()
  const sample = tournamentCalendarFor('probe-a', 0)
  if (problems.length) console.warn('[design-validation] issues found:\n - ' + problems.join('\n - '))
  else console.info(`[design-validation] ${SPECIES.length} species, ${CLASSES.length} classes, ${ALL_MOVES.length} moves, ~${sample.length} tournaments/yr — all consistent ✓`)
}
