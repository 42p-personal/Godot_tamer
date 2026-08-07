# Outstanding, to improve, to question

### CORRECTED: melee targeting was NOT broken

⚠️ Raised on 2026-08-03 as a live bug — *"melee units have no target selection"* — and it was
**false**. `pickTarget` applies the player's `targetPriority` filter ABOVE the melee/ranged
split (`decide.ts:250-262`), and the comment there records that the early-return bug was found
and fixed precisely because it once made the order do nothing.

Melee lacks only the AUTOMATIC value/isolation scoring, and the same comment states that is
deliberate: value-chasing across open ground is the failure the branch exists to prevent.
⚠️ **That reasoning strengthens on a larger ground.**

**Tenth entry in the already-handled list, and the first false alarm rather than a stale doc.**
Read the comment before believing the diagnosis.


**Written 2026-08-03.** A full sweep of what is unfinished, what is finished-but-weak, and what
nobody has checked. Three sections on purpose, because they need different responses: **§1 is
work**, **§2 is judgement**, **§3 is doubt** — and §3 is the one most likely to change what §1
should be.

⚠️ **READ THE STANDING RULE FIRST** (`CLAUDE.md`, top): the port is a skeleton and nearly every
system gets reworked in Godot. Several items below are only worth doing *if* they survive that
rework — flagged **[maybe moot]** where so.

---

## 1. OUTSTANDING — real work, not yet done

### ⚠️ 1.0 THE BIGGEST FINDING OF THE 2026-08-03 STUDIO REVIEW: THERE ARE TWO ENGINES, AND THE GAME PLAYS THE OTHER ONE

Verified against source:

| | engine | evidence |
|---|---|---|
| **What the player plays** | `battle.ts:simulateTeamBattle` (turn-based) | `town.ts:10,1405,2466,2595,2664` · `App.tsx:9,402,1748` |
| **What every balance tool measures** | `tamerengine:simulateFieldBattle` (continuous field) | `sweep40.ts`, `ab.ts`, `focus.ts`, `pool.ts` |
| **What the Godot port ports** | `tamerengine` | all six contracts |

⚠️ **SO EVERY NUMBER IN `docs/BALANCING.md` DESCRIBES AN ENGINE NO PLAYER HAS EVER PLAYED**,
and the port is porting the engine that is not the shipped game. The field engine is reachable
in-product only behind URL flags (`main.tsx:18-19`).

### ✅ ANSWERED 2026-08-03 — AND IT WAS NOT A PROBLEM, IT WAS A TAIL

The user: *"We can leave the current game running, but we are working on re-making the game in
the Godot engine. `tamerengine` will replace the whole game — it was originally an engine
rework, but now we will rewrite/port the game into Godot."*

So the split is **intended and terminal**, not drift:

| | disposition |
|---|---|
| `battle.ts` + the React app | **LEGACY. Keep it running. Do not invest.** |
| `tamerengine` | **the future game**, and the thing Godot receives |

⚠️ **THIS PARTLY REVERSES MY FRAMING ABOVE, AND I SHOULD SAY SO.** I called it alarming that
every balance number describes an engine no player has played. It is the opposite: the
measurements were always on the **right** engine — the one the game is becoming. `battle.ts`
is the thing that is temporary.

⚠️ **BUT ONE CONSEQUENCE GETS SHARPER, NOT SOFTER — AND IT IS NOW A PORT BLOCKER.**
If `tamerengine` becomes the WHOLE game, then everything inert on it does not merely lag; it
**dies in the transition** unless deliberately carried across:

- `INNATE_EFFECTS` — **130 entries, two per species across all 65** — zero references in
  `src/tamerengine/`
- `tameness`, `staminaDamageMult`, `happinessMultiplier` — same
- the per-stat perks (crit from DEX, echo from INT, pierce from STR, debuff from CHA) — the
  field engine uses a flat `CRIT_CHANCE = 0.08`

⚠️ **SO THE CARE LOOP AND SPECIES IDENTITY ARE CURRENTLY SCHEDULED FOR DELETION BY OMISSION.**
Feeding, resting and happiness would have no combat meaning in the shipped game, and 130
authored innates would be decoration. That directly contradicts the vision — *"the meta-game is
advanced training knowledge plus breeding the right monsters"* — and nobody has decided it.
**It needs an explicit call: wire them in, or deliberately retire them and say so.**

This is not a bug — `CLAUDE.md` records `battle.ts` as *"the turn engine `tamerengine` was
always going to replace"*, so the direction is intended. ⚠️ **The gap is that the TAKEOVER
APPEARS IN NO PLAN.** Nobody has written down when the field engine becomes the game, what has
to be true first, or what happens to saves and to the turn engine's own 12 goldens.

⚠️ **AND IT PARTLY EXPLAINS THE SUSPENDED BASELINE.** Some of the drift was not just churn —
the measurements and the product had already diverged.

**This should be the next planning decision**, ahead of the spatial rework, because it decides
whether the spatial work lands in the game or beside it.

### ⚠️ 1.0c NAMING COLLISION: "innate" means two different things

Found 2026-08-03 while verifying 1.0b.

| term | what it is | where |
|---|---|---|
| **`INNATE_EFFECTS`** | the two special abilities each species carries | `battle.ts:87` — **zero references in `tamerengine`** |
| **"innate"** in personality | the four innate personality AXES a monster is born with | `personality.ts`, `decide.ts:478` — **live and working** |

⚠️ **SO `grep innate src/tamerengine/` RETURNS HITS AND MEANS NOTHING.** The engine is full of
"innate" and none of it is species innates. Anyone verifying the 1.0b finding by keyword would
conclude it is already handled.

This is the **second** collision of this shape found today, after `cohesion`
(`FieldTraits.cohesion` the per-unit trait, versus the proposed per-team spacing axis — since
renamed `SPREAD`). ⚠️ **Two in one session is a pattern, not bad luck.** When naming anything
in the rebuild, check the word is not already load-bearing somewhere else.

**Suggested disambiguation:** `speciesInnates` for the ability pair, `disposition` for the
personality axes.

### ⚠️ 1.0b Species identity is INERT on the engine being ported

`INNATE_EFFECTS` — **130 entries, two innates for each of 65 species** — has **zero references
anywhere in `src/tamerengine/`**. So do `tameness`, `staminaDamageMult` and
`happinessMultiplier`. The field engine uses a flat `CRIT_CHANCE = 0.08` (`damage.ts:41`).

⚠️ **FEEDING, RESTING AND HAPPINESS HAVE NO COMBAT EFFECT ON THE ENGINE BEING PORTED**, and
neither do species innates. That is the care loop and the species-identity system both
disconnected from the fight.

⚠️ **AND IT LANDS DIRECTLY ON THE VISION.** *"The meta-game is advanced training knowledge
plus breeding the right monsters"* — on the field engine, a large part of that currently
changes nothing. It also gives a sharper answer to "do 65 species earn their keep?" than any
design argument: **on the ported engine, mechanically, not yet.**

### 1.1 The blocker: the spatial and AI layer

| item | size | notes |
|---|---|---|
| **The new spatial model** | large | Reach, cover, flanking on Godot navigation. Spec: `SPATIAL_COMBAT_DESIGN.md`. **Everything else in the engine waits on this.** |
| **Target selection** | large | ~1,140 lines of `chooseMove` / `utilityScore` / `decide.ts`, entangled with position. Not ported, deliberately. |
| **Cover as an accuracy debuff** | medium | Today it is binary occlusion — a unit behind a rock is *untargetable* by ranged, not harder to hit. ⚠️ The damage math needs NO change; `resolveStrike` already sums accuracy in points. |
| **Flanking on melee engagement** | small | Today: +5 on a 4.0-unit radius. Intended: +10 on genuine melee contact. |
| **Facing** | medium | The engine has no concept of which way a unit looks. Adding it makes flanking, cover and backstab one coherent family instead of three rules. |

### 1.2 Godot project — what does not exist yet

Everything in `monster-tamer/` is headless arithmetic. **Nothing renders.**

- No battle scene, no unit node, no camera, no arena, no sprites, no UI, no input, no audio.
- No `.tres` resources — data is read from JSON at runtime, which is fine for the contract
  runner and probably not what the shipping game wants.
- No save/load. No meta-game (`town.ts` + `game.ts` + `monster.ts` = 4,170 lines, deferred).
- No gdUnit4. The contract runner is the only test harness, and it cannot test scenes.

### 1.3 Confirmed for rework, not started

- **CON control-resist floor** — saturates at CON 900, exactly the Platinum cap, so CON buys
  zero control resistance across the whole 5v5 band. Proposal and options in
  `SPATIAL_COMBAT_DESIGN.md` §4. **You confirmed this needs reworking; it has not been done.**
- **`tools/comps.ts` re-weighting to 5v5** — 7 of 12 compositions are not the game being
  balanced. ⚠️ **The "moves every baseline" objection has EXPIRED** — the baseline is suspended
  (`CLAUDE.md`), so this is now cheap rather than expensive. Do it as part of the re-baseline.
- **⚠️ Training aptitude is a RATE mechanic, not a CEILING mechanic** — `Math.min(cap, ...)`
  means major/minor/flaw change how fast a monster reaches its cap, never where it stops. Its
  influence decays toward the cap and is weakest in the Platinum→Apex band the game is balanced
  for. Not necessarily wrong, but **undocumented and unmeasured**; see
  `TACTICS_BRAINSTORM.md` §5.1, which is also the argument for station aptitude.

### 1.4 Long-deferred, still true

| item | why deferred |
|---|---|
| **Six passives** | designed in `ABILITY_REWORK.md`, never built. Needs engine work first — exclude from `chooseMove`, from `reachOf`, from `basicAttackFor` |
| ~~`spreadStatus` (contagion)~~ | ⚠️ **IT IS BUILT AND SHIPPED** — `engine.ts:1788`, `battle.ts:1311`, live on 5 pool moves. Five documents and two code comments say otherwise, and I repeated the claim here without checking. It is in NO contract, so a Godot port omits it and still passes 173/173. **Contract it.** |
| **`Move.area` consolidation** | AoE is attached by NAME, so renaming a move silently makes it single-target. Two attempts reverted; traps in `HANDOVER_area_consolidation.md` **[maybe moot]** |
| **`tauntForce` targeting** | mass taunt works; forced-target AI is a standalone pass |
| **Economy rebalance** | deliberately last, once all sinks/sources are in |
| **Achievements + goal gradient** | fold into a future achievements system |
| **Named rival in cups** | needs bracket/scout/standings plumbing |
| **Hall of Fame perks, lifespan elixir, richer inheritance** | Phase 5 extensions |

### 1.5 Small and real

- **`docs/ABILITIES.md` regeneration** — generated from `moves.ts`; check it is current.
- **Four remaining grand-circuit arenas** (16 of 20) — **[likely moot]**, arenas are being
  rebuilt.
- **`my-game/`** — a clone of the CCGS template sitting in-tree. Gitignored now. Delete it if
  it is not wanted; it is not ours to bin unasked.
- **`CCGS Skill Testing Framework/`** — 127 tracked files of template tooling, unrelated to the
  game. Same question.

---

## 2. TO IMPROVE — exists, works, is weak

### 2.1 ⚠️ `tools/pool.ts` is not calibrated, and it is telling us so

Reports **0 flags across 77 damage moves**. Its own distribution table:

| stat | n | min | med | max | spread |
|---|---|---|---|---|---|
| STR | 15 | 10.2 | 25.4 | 120.2 | 12x |
| DEX | 19 | 11.8 | 28.2 | 125.2 | 11x |
| **INT** | 17 | **5.9** | 43.1 | **184.0** | **31x** |
| WIS | 9 | 7.2 | 16.6 | 47.4 | 7x |

**A 31x spread inside one stat and nothing flags.** That is a statement about the thresholds,
not the pool. The tool prints *"pick thresholds from this, do not trust the ones hard-coded
above"* — it knows. Calibrating it unblocks Step 3 of the ability-pool plan, which never
happened because the list came back empty.

### 2.2 The whole-fight goldens

Kept as a reference recording. ⚠️ **They demonstrably miss logic bugs** — the `lastCcAt` bug
during the port extraction (a DoT would have kept the CC meter hot forever) passed all of them,
because the three fixtures never pair a damage-over-time with chained control. Either broaden
the fixtures or retire them once Godot is the engine.

### 2.3 Performance budgets are unset

Marked "proposed, unmeasured" in `technical-preferences.md`. Correct for now — inventing them
would be the exact failure the balancing rule exists to stop — but they stay wrong until
something renders.

### 2.4 Documentation debt

- **`GAME_DESIGN.md`** is stale in places; `CLAUDE.md` and the code are more current.
- **`ARENA_DESIGN.md`** is scar tissue from a billboard renderer with a board-fitted camera.
  Read it for reasoning, not rules — half its constraints stop existing in Godot.
- **`docs/engine-reference/godot/`** stops at 4.6. We run 4.7.1. Nothing has broken because the
  port is pure arithmetic; that ends at scenes and navigation.
- **No ADRs.** Deliberate — the prose is current, stubs would rot. Revisit if the studio wants
  the formal trail.

### 2.5 Contract coverage gaps

219 cases across six contracts, but not everything pure is covered:

- `resolveUtility` — heals, shields, buffs, cleanse. **Not contracted.** Mostly non-spatial.
- `aoeFalloff`, `rollVariance` edge cases, innate effects (`INNATE_EFFECTS`), `spendWeight`.
- ⚠️ **Innates are keyed by ability NAME** — renaming in `species.ts` silently detaches the
  effect. That deserves a guard.

---

## 3. TO QUESTION — nobody has checked these

The most valuable section. Each is a real doubt, not a rhetorical one.

### 3.1 Is the sim actually fun?

⚠️ **THE BIGGEST UNCHECKED ASSUMPTION IN THE PROJECT.** Everything is measured — fight length,
damage tiers, focus share, connect rate — and *nothing measures whether a fight is enjoyable to
watch*. An autobattler is a spectator game. The sim could be perfectly balanced and dull.

**There is no playtest record in the repo.** Not one `playtest-report`. Every balance decision
has been made against the sim, and the sim cannot answer this.

### 3.2 Is 5v5 with 4-slot loadouts legible? — a candidate answer exists

⚠️ **FORMATION MAY BE THE FIX, NOT JUST AN AGENCY FEATURE.** A named shape with a named plan
gives the player a frame to interpret the chaos through — *"my wedge broke their line but their
box held the casters"* is a story; five blobs picking their own targets is noise. See
`TACTICS_BRAINSTORM.md` §0. Still unproven, but it is the first real proposal.

### 3.2 Is 5v5 with 4-slot loadouts legible?

Five monsters × 4 abilities + 2 innates + statuses + tactics, resolving in real time. Can a
player follow it? Can they tell WHY they lost? `battleReport.ts` exists because the answer was
probably no — but a post-hoc report is a patch over an unreadable fight, not a fix.

### 3.3 ~~Does the player have enough agency?~~ — ANSWERED, and it became a work item

**The player never intervenes.** Confirmed 2026-08-03: they set tactics and watch those tactics
unfold. That is the design, not a gap.

⚠️ **BUT IT RAISES THE BAR RATHER THAN CLOSING THE QUESTION.** If orders are the whole input,
every order must be predictable, visible and diagnosable. Measured against that bar, the
orders system fails on the one thing a spectator can actually see — **position**. Deployment
offers exactly two x-positions chosen by one boolean, evenly spaced, with the player choosing
none of it. Now a work item: `docs/TACTICS_DESIGN.md`.

### 3.4 Do 65 species and 18 classes earn their keep?

Class is emergent from two stats and 141 moves are gated by line affinity. Genuine question: is
species identity *felt*, or is a monster just a stat block with a portrait? ⚠️ Related and
unmeasured: with `Generalist` at ~3%, are all 18 classes actually reachable in play, or do a
handful dominate because of how stats train?

### 3.5 Is the 30-drill training loop a game or a chore?

Six basic + 12 intensive + 6 extreme + 6 diverse, per monster, per week, across a career. With
5+ monsters that is a lot of clicking for a decision that may be near-automatic once the player
knows the aptitudes.

### 3.6 The meta-game — PARTLY ANSWERED

**It is a mixture, and it feeds the fight**: advanced training knowledge plus breeding the right
monsters to have the correct tactics and skills. Confirmed 2026-08-03. It is neither a frame
around the battles nor a separate game — it is how the player builds the answer they will need.

⚠️ **STILL OPEN: what happens to the 4,170 lines.** Ported, redesigned, or left in TypeScript?
The vision raises the stakes rather than settling it — if knowing WHICH monster to make is the
skill, then training and breeding have to be *legible enough to plan with*, and nobody has
checked whether they are. See also §3.5: a training loop that is a chore is the direct enemy of
"advanced training knowledge".

### 3.7 Is desktop-only right?

Decided with the Godot move. The legacy build is a browser game that already deploys. Is
abandoning the web reach intended, or a side effect of the engine choice?

### 3.8 ~~What is the actual scope?~~ — ANSWERED

**Winning is completing Tamers Apex, the last league.** Confirmed 2026-08-03 — the project's
first ship target.

⚠️ **THE LADDER IS THE SPINE, AND THAT IS NOW A FILTER ON EVERYTHING ELSE.** Wood → Tamers Apex
must be completable, paced and satisfying end to end. Content that does not serve that climb is
not v1. Worth re-reading §1 with that filter on: several long-deferred items exist to enrich a
game that is already long enough, and the honest question for each is now *"does this make the
climb better, or just bigger?"*

### 3.9 Cheap technical doubts worth resolving

- **Float determinism over long accumulation** — proven per-hit, unproven over hundreds of
  ticks. We no longer depend on it. Confirm that stays true.
- **JSON at runtime vs `.tres` resources** — fine for the harness; is it right for shipping?
- **The 141-move pool with no passives** — six designed, zero built. Is the pool complete or
  is it 141 of 147?
- **`FIELD_LOADOUT_SIZE` is 4** of a much larger learnable set. Is four the right number, and
  has anyone tested five?

---

## Suggested order

0. ~~Answer scope~~ — **DONE. Tamers Apex is the ship target.** Re-read §1 with that filter:
   for each deferred item, *does this make the climb better, or just bigger?*
1. **Answer §3.1** — is it fun to watch. Still the biggest unchecked assumption, and now
   sharper: the player cannot intervene, so watching IS the game. One playtest would tell us
   more than another sweep.
2. **The spatial model** (§1.1) — the engine blocker.
3. **Calibrate `pool.ts`** (§2.1) — cheap, built, unblocks the pool review.
4. **The CON rework** (§1.3) — small, confirmed, needs a decision on when.
5. **A rendering battle scene** — turns verified libraries into a game, and unblocks the
   performance budgets.
