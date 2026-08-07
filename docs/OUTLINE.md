# Monster Tamer — Rough Development Outline

A rough, staged plan derived from [GAME_DESIGN.md](./GAME_DESIGN.md). Each milestone is meant to
be independently runnable in the browser so the concept can be validated early.

## Proposed tech stack
- **React + TypeScript + Vite** — management/sim UI (stable, training calendar, breeding, tournaments).
- **PixiJS or Canvas** — **pixel-art** monster rendering and the auto-battle viewer (2D; no 3D needed).
- **Zustand** — game state.
- **Deterministic tick engine** — the calendar/aging/training clock, kept separate from rendering.
- **Seeded RNG** (e.g. `mulberry32`) — reproducible genomes, breeding, ability milestones, and battle sims.
- **IndexedDB** (via localForage) — local-first saves; no backend required to ship.

## Core data model (the spine)
```
Monster {
  id, name, species (1 of 20 base), breed, bodyType, sex
  genome                 // seed/parts driving appearance + inheritance + ability milestones
  stats { STR, DEX, CON, WIS, INT, CHA }   // 0–999, capped by license
  license                // Wood…Tamer Elite -> stat cap
  class                  // derived label from top stat priorities (see design §6)
  traits[]
  innateAbilities[]      // from species/breed
  learnedAbilities[]     // unlocked by crossing randomised per-stat milestones
  abilityMilestones[]    // { stat, threshold } rolled from genome (deterministic)
  age, lifespanYears (from breed), condition/fatigue/injury
  appearanceParts[]      // pixel-art parts keyed to genome; swapped during fusion
  role: competitor | expertTrainer | frozen | breeding
}
```
Everything else (class, breeding, fusion, appearance, ability unlocks, retirement) derives from
this structure.

## Class & ability rules (data-driven)
- **Classes:** 11 labels (Tank, Warrior, Rogue, Ranger, Sage, Wizard, Spellsword, Spellshield,
  Captain, Orator, Bard), each a `{ primaryStat, secondaryStat }` pair. Default: class is **emergent**
  from a monster's two highest-priority stats and re-labels as it trains (confirm vs. intrinsic).
- **Abilities:** `innate` come from species; `learned` unlock when a stat crosses a `{stat, threshold}`
  milestone rolled from the genome — so same-breed monsters diverge based on how they're trained.

---

## Milestones

### M0 — Project scaffold
Vite + React + TS project, state store, save/load stub, basic screen routing.

### M1 — Monster model + generator *(prove the hook first)*
- Implement the `Monster` data model and stat block.
- Deterministic **seed → genome → monster** generator (type input, get a monster + starting stats).
- Derive **class** from stat priorities; roll **ability milestones** from the genome.
- Render a placeholder pixel-art monster from its parts.

### M2 — Calendar & weekly actions ✅ *(first pass built — `src/game.ts`, Career tab)*
- Week/month/year clock (§2) — one week per action.
- Weekly actions: **Training** (basic + intensive drills, per-stat gains), **Rest**, **Feeding**
  (costs gold, moves happiness), **Excursions** (earn gold).
- **Stamina** (0–100), **gold** (start 200 + weekly allowance), **aging** through life stages with the
  training malus, and **retirement** at lifespan.
- Enforce **license stat caps** (§3/§5); **ability unlocks** logged as stats cross learn levels.
- *Placeholder:* a simple **Rank-up** button (eligible near cap) stands in for the real knockout
  rank-up tournaments (M4).

### M3 — Auto-battle sim (1v1)
- Damage channels from stats: melee, ranged, elemental, voice; defence/dodge/HP/mana.
- Innate + learned **abilities** participate in the sim.
- Deterministic tick resolution; a simple pixel-art battle viewer.
- No player control mid-fight (Teamfight Manager style).

### M4 — Tournaments & leagues
- Sign-up by month; **round-robin 1v1**; standings and prizes.
- **Knockout rank-up** tournaments gating promotion between leagues.
- **League rulesets as data** — random modifier from the league's pool.

### M5 — Lifespan & retirement
- Aging toward breed lifespan; forced retirement.
- Retirement options: **Sell / Freeze / Expert Trainer / Breeding Pen** (§6).
- Expert Trainer XP bonus tied to highest league attained.

### M6 — Breeding & fusion
- **Breeding pen:** same body type + opposite sex → combined egg → inherited offspring.
- **Fusion:** merge parts/traits/abilities between monsters; combine/drop traits; change appearance.
- Frozen genomes feed fusion.

### M7 — Progression content
- Additional formats: **2v2, 3v3, 4v4, 1v1v1v1**.
- **Tactics & formations** layer, unlocked alongside team formats — pre-fight positioning/orders
  that feed the sim.
- More league rulesets and tournament types; economy & difficulty tuning.

### M8 — Content & polish
- The **20 base species** + pixel-art **part sets** that combine into the **100 launch varieties**.
- Full ability/trait library; art pass, audio, UX, balance, save-management, onboarding.

---

## Suggested first step
Build **M0 + M1** together: scaffold the project and ship the seed-to-monster generator, so there is
something interactive in the browser on day one and the core data model is locked in early.
