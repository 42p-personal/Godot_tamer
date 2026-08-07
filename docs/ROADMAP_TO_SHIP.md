# Roadmap to ship

**2026-08-05.** The whole game, from where it stands today to something releasable.

**The ship target is already decided and it is the only one this project has ever had**
(`CLAUDE.md`): *"Winning is completing Tamers Apex — the last league. A player who reaches and
clears Tamers Apex has finished the game."* Everything below is sorted by whether it serves that
climb. Content that does not is not v1, and several things people would assume are v1 are marked
**CUT** here for exactly that reason.

---

## Where we actually are

**Built and verified:**

| | |
|---|---|
| Port contracts | **219/219** exact-equality vs TypeScript, green all session |
| Weekly tick | plan-then-advance, preview==apply, food economy, drills, stat caps |
| The ladder | 11 leagues, live cup rounds, sweep-to-promote, purse, punch-down penalty |
| Meta systems | market, shop, breeding dynasties, Lab with weekly rent, 6-step tutorial |
| Spatial sim | deterministic fixed-step, navmesh, cover, flanking, solid bodies |
| Behaviour tree | push / hold / wings / dive / guard, orders vs defaults, attribution |
| Reactions | peel, fall back, disengage, emergency bail-out, collapse |
| Creatures | 45 CC0 rigged + animated, 15 MB total, every sim state mapped to a clip |
| Arena | authored `four_pillar` layout, CC0 obstacles, drawn deploy zones |
| Watch mode | title-screen button, camera toggle, pause, replay speed |

**The honest gaps, counted:**

- **20 of 65 species** have a model mapping. 45 models exist; 45 species have nothing.
- **1 of 4** arena layouts built (`central_mass`, `triad`, `lanes` are designed, not authored).
- **`_personality_of()` returns `{}`** — every personality axis reads its default, so Discipline,
  Nerve, Aggression and Focus currently do nothing.
- **The balance baseline is SUSPENDED** and has never been re-established.
- **There is not one playtest record in the repo.**

---

## ⚠️ The three risks that should shape the order of everything else

**1. THE UNVALIDATED PILE IS THE BIGGEST TECHNICAL RISK.** `CLAUDE.md` suspended the balance
baseline for the Godot rebuild — correctly — and says: *"a long suspension accumulates a large
pile of unvalidated change, and the eventual re-baseline has to judge all of it at once... If the
pile starts feeling unmanageable, that is the signal to stop and re-baseline early."* This
session alone changed body radius, reach, speed, deploy separation, the deploy band, obstacle
sizes, the density budget, target defaults, withdrawal defaults and the engagement gate. **The
pile is now large.** Re-baselining is Phase 0, not Phase 4.

**2. NOBODY HAS EVER CONFIRMED THE FIGHT IS FUN TO WATCH.** `OUTSTANDING.md` §3 named this as the
project's biggest unchecked assumption months ago and it is still true. Until this week there was
no convenient way to look at a fight; now there is. **This is the cheapest possible de-risking and
it gates a lot of expensive work** — if a 5v5 is not enjoyable to watch, no amount of content
fixes it.

**3. THE CARE LOOP IS SCHEDULED FOR DELETION BY OMISSION.** `OUTSTANDING.md`: 130 authored species
innates, `tameness`, `staminaDamageMult` and `happinessMultiplier` have **zero references** in the
field engine. So feeding, resting and happiness currently have no combat meaning in the engine the
game is becoming — which directly contradicts the vision's *"the meta-game is advanced training
knowledge plus breeding the right monsters"*. **This needs an explicit decision, not a backlog
entry.**

---

## Phase 0 — Prove the core (before building anything else)

*Goal: know whether the thing we are making is worth making, and get a number to build against.*

| # | work | why it is first |
|---|---|---|
| 0.1 | **Playtest the watch mode.** 10 fights, written notes. Is it readable? Can you tell why a monster did something? Is it boring? | The one assumption everything rests on, and now testable in minutes |
| 0.2 | **Re-baseline.** Run a full sweep on the Godot sim; record it as the new zero | Every number quoted in the docs describes a machine that no longer exists |
| 0.3 | **Decide the care loop.** Wire innates/tameness/happiness into the field engine, or retire them and say so | 130 authored innates either matter or they do not; ambiguity is the worst state |
| 0.4 | **Fix the round-robin lie.** `tournament_ui.gd` says "three rivals" but rivals never fight each other | A ladder that misreports its own structure is a trust bug |

**GATE:** a written playtest record exists, and there is a baseline to measure against.
⚠️ *If 0.1 says the fight is not enjoyable to watch, stop and fix that before Phase 1. Everything
after this assumes the core loop is fun.*

---

## Phase 1 — Close the ladder (the actual ship requirement)

*Goal: a player can start at Wood and clear Tamers Apex without hitting a wall, a gap or a lie.*

| # | work |
|---|---|
| 1.1 | **Play the full ladder end to end.** Wood → Apex, start to finish, recording where it stalls. Nobody has done this |
| 1.2 | **Difficulty curve across 11 leagues** — rival budgets, stat caps, purse, entry costs, tuned against 0.2's baseline |
| 1.3 | **Economy pass** — deliberately deferred until every sink and source existed. They now do |
| 1.4 | **Career length** — `FUN_ADDITIONS.md` measured **1,708 matches available**. That is far too many; compression is a blocker, not a nicety |
| 1.5 | **Save/load robustness** across the whole loop, plus migration |
| 1.6 | **The three remaining arena layouts** (`central_mass`, `triad`, `lanes`) so the pool is not one composition |
| 1.7 | **Free placement actually sets battle start positions** — today the board you draw is a planning tool the sim ignores |

**GATE:** one person completes a full career, Wood to Apex, and it is paced.

---

## Phase 2 — Make it deep (the reason to replay)

*Goal: preparation is genuinely the skill, as the vision states.*

| # | work |
|---|---|
| 2.1 | **Personality stats live** — `_personality_of()` returns `{}` today, so Discipline/Nerve/Aggression/Focus are inert and every default is a fallback |
| 2.2 | **Assignable classes + per-class stat caps** — designed in `CLASS_REWORK.md`, prevents the measured "max everything in 8 years" problem |
| 2.3 | **Named targeting traits** — the Eslabong lesson: quirks players complain about *by name*. Chosen, unbuilt |
| 2.4 | **Speed as its own stat** (decision #19, still derived from DEX) |
| 2.5 | **Six passives** designed in `ABILITY_REWORK.md` — needs engine work first (exclude from `chooseMove`, `reachOf`, `basicAttackFor`) |
| 2.6 | **Kit doctrine** — the axis that would give 18 classes more than one point of difference |

**GATE:** two different stables built for the same league play measurably differently.

---

## Phase 3 — Make it look and sound like a game

| # | work |
|---|---|
| 3.1 | **Species → model coverage.** 20 of 65 mapped. Either map the remaining 45 onto the CC0 set, cut the roster to what exists, or generate the gap |
| 3.2 | **Audio — there is none.** Music, hits, UI, crowd. `AUDIO_DIRECTION.md` exists; nothing is implemented |
| 3.3 | **Projectile authoring** for the 141-move pool — `projectiles` is always `[]` in the frame stream |
| 3.4 | **UI audit vs tamergame** — the phase that was spent disproving its own headline finding and never ran |
| 3.5 | **Arena art pass** — materials and palettes per league, on the authored layouts |
| 3.6 | **Narrative Phase 4** — all canon is still marked *Provisional*; no consistency review has run |

**GATE:** a stranger can watch a fight and a career screen and know what game this is.

---

## Phase 4 — Ship readiness

| # | work |
|---|---|
| 4.1 | **Accessibility** — 3 flagged blockers, ⚠️ all still **unverified**, plus colourblind checks (3 of 8 team colours collapse under deuteranopia) |
| 4.2 | **Performance budgets** — currently *unset*; `technical-preferences.md` says making numbers up is the failure this project's rules exist to stop |
| 4.3 | **Full-loop QA + regression suite**, and freeze the goldens |
| 4.4 | **Build, package, store presence, release checklist** |
| 4.5 | **Retire the React app** or make an explicit call to keep it |

---

## ⚠️ Explicitly CUT from v1

Not because they are bad, but because they do not serve the Wood → Apex climb:

- **Game modes** (King of the Hill, Capture the Flag) — `AUTOBATTLER_DESIGN.md` #2 already says build
  the *seam*, not the modes
- **Elevation in arenas** — banned by `ARENA_DESIGN.md`; revisit post-ship
- **Dynamic/moving cover** — ⚠️ WoW shipped it twice and killed it twice (Ring of Valor removed,
  Enigma Crucible's switch cut in testing). Strong prior against
- **`spreadStatus` contagion**, live Hall of Fame perks, lifespan elixirs, richer inheritance
- **Named rival seated in the round-robin** — needs bracket/scout/standings plumbing
- **Achievements** — folds into a post-ship system

---

## The shape of it

```
Phase 0  prove the core          ~ small, and it gates everything
Phase 1  close the ladder        ~ the actual ship requirement
Phase 2  make it deep            ~ the reason to replay
Phase 3  look and sound          ~ the largest content block
Phase 4  ship readiness
```

⚠️ **No dates.** This project has no velocity data, and inventing a schedule would be the same
error as inventing a performance budget — a confident number about something nobody has measured.
The *order* is the useful part, and the gates are what make it real.

⚠️ **And the ordering principle, stated once:** Phase 0 exists because every later phase costs
more if the core is wrong, and Phase 1 is the ship requirement while Phases 2–3 are what make it
*good*. If time runs short, a shipped game is Phase 0 + 1 + the minimum of 3 that makes it
presentable. Phase 2 is where the game becomes worth recommending.
