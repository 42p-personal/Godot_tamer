# The autobattler — free-willed monsters under a player's plan

**2026-08-04.** The design settled with the user before any further code. Supersedes the ad-hoc
AI in `scripts/spatial_ai.gd`. ⚠️ **Nothing here is built yet.**

**The problem this solves, in the user's words:** *"we currently have a big blob of monsters
moving to a central area, we need more decision making and free will for the monsters, tuned by
the players input for the tactics."*

---

## 0. What the reference games actually do

| | **Teamfight Manager 1 / 2** | **Eslabong** |
|---|---|---|
| shape | manager sim wrapped around an auto-battling MOBA | mercenary-club sim wrapped around a real-time arena |
| player leverage | draft, **tactics presets**, items, training, scouting — all *around* the match | roster, market, scouting, facilities, **tactics**; optionally pilot ONE fighter live |
| in-fight control | none | optional, one fighter |
| AI basis | champion class + traits + manager's tactic presets | *"class, role and tactics"* |

**Three things worth stealing:**

1. **Tactics are named presets, not sliders.** TFM's "Closing Out: Stable / Flexible /
   Aggressive". A preset is predictable, explainable and discussable; a slider is neither.
2. **"Let player decide" is an explicit option.** TFM offers it on item slots. Delegating is a
   *choice the player makes*, not a gap in the UI.
3. **Targeting quirks live on the CHAMPION as traits.** *Despise Weakness* fixates on recently
   hit enemies; *Inattentive* re-picks unpredictably. Players complain about them by name — which
   means they are **legible**, and legible quirks are character.

⚠️ **THE MOST USEFUL FINDING IS THE COMPLAINT THREAD, NOT THE FEATURE LIST.** TFM2's "AI Is Still
A Massive Issue" names the failure modes precisely: champions *"wandering in circles"*, escaping
at low HP and *"immediately returning to die for no reason"*, abandoning a 5%-health objective to
chase someone, *"blindly following programmed strategies"*. **Every one of those is a monster
doing something the player would never have chosen and cannot explain.** That is the bar: not
"is the AI clever" but **"can the player tell why it did that, and was it their own order?"**

---

## 1. The decisions

| # | decision |
|---|---|
| 1 | **Deployment is free placement** anywhere in your own half, **saved as your own named formations**. Spacing is a property of the formation, not a separate order. |
| 2 | **Modes are pluggable.** v1 is Team Deathmatch. **King of the Hill and Capture the Flag come later, varying by cup.** Build the mode seam now, not the modes. |
| 3 | **Zero intervention stands.** Commit, then watch. |
| 4 | ⚠️ **Personality sets a monster's PREFERRED tactics — it does not cause disobedience.** A monster obeys the player's orders unless something urgent overrides. |
| 5 | ⚠️ **The AI models are themselves TACTICS.** Weighted scoring · strict priority · follow-threat · commit-vs-reassess are options the player assigns, not one implementation. Different monsters genuinely think differently. |
| 6 | **Free steering movement**, with movement style also tactic-driven. |
| 7 | **Taunt is an ABILITY effect, not a passive threat table.** Otherwise aggro is decided by positioning and targeting. |
| 8 | ⚠️ **Keep the arena massive (160×88 at 5v5) and make the AI USE it.** Scaling by mode/league is planned, but shrinking the board is *not* the fix for the blob. |
| 9 | **Mixed aiming** — some abilities auto-hit, some are aimed and can miss a moving target. |
| 10 | **Solid bodies.** Monsters block each other; a front line genuinely shields a back line. |
| 11 | **Fight length is emergent, ~30s to ~3min**, depending on who is fighting. Not a tuning target. |
| 12 | **Move to assignable classes** (`docs/CLASS_REWORK.md`). |
| 13 | **Team plan + per-monster override.** |
| 14 | **"When hurt" is a tactic**, never automatic. |
| 15 | **Legibility is both**: live intent labels during the fight *and* a per-monster decision log in the report. |
| 16 | **Personality = species + breeding.** |
| 17 | **Tactics unlock as you climb the ladder.** |
| 18 | **Four personality stats surfaced in the UI: Discipline · Nerve · Aggression · Focus.** ⚠️ Corrected 2026-08-04 — three of the four already existed as `temperament`/`mental`/`aggression` in `src/tamerengine/personality.ts`; only Focus is new. See §3. |
| 19 | **Speed becomes its own stat**, no longer derived from DEX. |

---

## 2. The tactic axes

Four axes. Team plan sets the default; any monster may override any axis. **Personality supplies
each monster's preferred value**, shown in the UI as its default so the player can see what the
creature *wants* to do before overriding it.

### A. Target priority
*Who do I go for?* — and, separately, *how readily do I change my mind?*

| option | behaviour |
|---|---|
| `nearest` | closest living enemy |
| `weakest` | lowest current HP |
| `casters` | highest INT/WIS — kill the back line |
| `tanks` | highest CON — break the wall first |
| `marked` | the one monster the player named (requires scouting) |
| `threat` | whoever is hurting me or my charge most |

Plus **commitment**: `sticky` (hold a target ~4s unless it dies or a taunt overrides) vs
`reassess` (re-score every decision tick).
⚠️ **Commitment is the direct fix for the TFM complaint** about losing interest in the healer
because a tank dipped low. `Focus` sets the default.

### B. Positional intent
*Where do I want to be?* — **this is the axis that makes the arena get used.**

| option | behaviour |
|---|---|
| `push` | advance on the enemy line, take ground |
| `hold` | keep the line near where I deployed |
| `wings` | work wide, approach from the flank |
| `dive` | go around/through for the enemy back line |
| `guard` | stay near a named ally and intercept threats to it |

⚠️ **`wings` and `dive` are the two that spread a fight across a 160-wide board.** Without
genuinely lateral goals, every unit's best path is the straight line to the enemy — which is
exactly the blob.

### C. Formation *(absorbs spacing)*
Free-form placement in your half, saved as named formations. The **shape carries the spacing**,
so a tight wedge keeps support auras live (`Spatial.aura_radius`) and a wide screen blunts area
damage — the trade already decided in `ARENA_BLUEPRINT.md` §5.

### D. When hurt + ability policy
| when hurt | | ability policy | |
|---|---|---|---|
| `fight on` | no retreat | `free` | spend on cooldown |
| `fall back` | withdraw toward allies, re-engage when steadied | `hold big` | save the capstone for a good moment |
| `disengage` | break off, seek cover, do not return until healed | `combo` | spend only to set up or cash in a status |

⚠️ **`fall back` MUST NOT become the TFM flee-return death spiral.** A monster that has fallen
back is committed to it for a minimum dwell time and must reach a genuine safety condition before
re-engaging. `Nerve` sets how cleanly it disengages.

---

## 3. Personality — six axes already exist; a seventh is new; four surface in the UI

⚠️ **CORRECTED 2026-08-04 — THE EIGHTH INSTANCE OF THIS PROJECT'S "ALREADY BUILT WHILE
DOCUMENTED AS MISSING" PATTERN**, after per-unit speed, the leash, `spreadStatus`, the
cohesion/predation archetype grid, per-ability `range`, the measurement that speed doesn't fix
chasing, and 30 battle sprites on disk (`docs/HANDOVER.md`). This section originally proposed
"four NEW personality stats" as fresh work, written without grepping for the personality system
that already ships. **It is not fresh.** `src/tamerengine/personality.ts` (v0.93, documented in
`docs/TAMERENGINE.md`) already has **six** axes — `aggression`, `teamplay`, `mental`,
`temperament`, `awareness`, `patience` — generated off their own seeded stream
(`seed + ':personality:v1'`, never touching `generateMonster`'s rng, so every existing save
already has one with zero migration), already carrying a species bias (`speciesBias()`,
read off base combat stats — the same shape as `trainingProfile`), already wired live into
`decide.ts` (`coachedValue` = the obey/coaching blend, `panicThreshold`, `spendAbove`,
`threatRadius`, archetype tagging), and covered by `tactics.test.ts`/`field.test.ts`. It even
already has the drift field the "trainable bred band" idea (§8 #25) needs:
`Monster.personality?: Partial<Personality>`.

**The full generation/breeding/coach/UI/Speed spec is `docs/PERSONALITY_STATS.md` — read that,
not the rest of this section, for the buildable design.** Grep `personality.ts` before touching
this system again.

Not combat stats. **They govern DEFAULTS and EXECUTION, never raw damage.**

| UI-facing name | internal field | low ↔ high | what it already does |
|---|---|---|---|
| **Aggression** | `aggression` | patient ↔ eager | default positional intent & target priority; feeds `FieldTraits.predation` |
| **Discipline** | `temperament` | improvises ↔ follows the plan | the `obey` weight in `coachedValue()` — how much of the player's order actually lands vs. the monster's own instinct |
| **Nerve** | `mental` | rattles ↔ steady | `panicThreshold()` — whether being hurt/outnumbered degrades decisions and triggers an early fall back |
| **Focus** *(new)* | `focus` *(new)* | distractible ↔ fixated | target commitment (`sticky` vs `reassess`) — genuinely new; nothing today drives per-monster retarget cadence |
| *(hidden)* | `teamplay` | lone ↔ unit | feeds `FieldTraits.cohesion` — no per-monster tactic exists to set it directly yet, so it stays unexposed |
| *(hidden)* | `patience` | impulsive ↔ deliberate | `spendAbove()` — holds big cooldowns for the right moment; the natural driver of §2D's ability-policy default, which is otherwise unassigned to any stat |

⚠️ **RENAMING NOTE.** "Discipline" and "Nerve" are UI labels for the existing `temperament` and
`mental` fields — the internal field names do **not** change, no migration, no fork. "Aggression"
is a straight passthrough (same name both places). Only `focus` is new code, and it must be
appended LAST in both `speciesBias()`'s returned object and the `vary()` call sequence in
`basePersonality()` — the six existing axes' rolled values are a function of RNG-stream call
*order*, and appending after `patience` guarantees their values do not move. See
`docs/PERSONALITY_STATS.md` §11 for the full safety argument.

⚠️ **THESE MUST BE EXCLUDED FROM `classForStats`, AND ALREADY ARE, BY CONSTRUCTION.**
`Personality` is a wholly separate TypeScript interface from `Stats` — `classForStats` (and its
assignable-class successor in `CLASS_REWORK.md`) only ever reads the six combat stats in
`STATS`/`Stats`; `Personality` is never merged into that type anywhere in the codebase. Adding
`focus`, or exposing Speed as its own stat, does not touch this boundary — there is no new guard
to write, the type system already enforces the separation.

⚠️ **"Obeys unless something urgent happens" needs an explicit, short list of what counts as
urgent** — otherwise it becomes a licence for the AI to do anything and blame instinct. Proposed
and needing sign-off: *taunted* · *about to die with an escape available* · *ordered target is
dead* · *ordered destination is unreachable*. **Nothing else.**

---

## 4. Speed as its own stat

⚠️ **THIS IS A REAL CHANGE AND IT CARRIES A LOAD-BEARING WARNING.**
`docs/ENGAGEMENT_DESIGN.md` records a **measurement**: speed is *not* the lever that fixes
chasing. Without the advance/retreat asymmetry, *"a chase NEVER resolves — a pursuit equilibrium
that left units out of range 76% of the fight regardless of field size or speed (both measured,
both invariant)"*.

So: **a Speed stat is fine as a design axis; it must never be used to solve kiting.**
`Spatial.BACKPEDAL_MULT` stays exactly as it is.

Consequences to build: replaces `Spatial.speed_of(dex)`; needs a range, a training path,
breeding inheritance, a per-league cap, and a `data.json` extension. DEX keeps dodge and
initiative.

---

## 5. Making the arena get used — the actual anti-blob list

The blob has **five** causes, and only fixing all of them works:

| cause | fix |
|---|---|
| every unit runs the same utility function | per-monster tactics + personality defaults ⇒ genuine variance |
| all converge on one shared focus | `sticky` commitment + per-unit reachability weighting |
| no lateral goals | `wings` / `dive` positional intents |
| no reason to hold ground | `hold` / `guard` intents, and later KotH/CTF objectives |
| deployment is a narrow line near the centre | **free placement across the full width of your half** |

⚠️ **Deployment width is the cheapest and most under-rated of these.** Deploy separation is a
flat ~33 units on a 160-wide board (`ARENA_BLUEPRINT` §2, deliberately independent of board
width), so both sides start clustered mid-board. If the deployment ZONE spans the full ground
height, a player can start monsters genuinely wide — and the fight opens spread instead of
converging from a point.

---

## 6. Legibility — both layers

**Live:** each monster shows its current intent (`closing`, `holding range`, `flanking`,
`falling back`, `guarding Aegisox`).
**Post-fight:** a per-monster decision log giving the *reason*, in the player's own vocabulary —
> `12.4s — Grivvel switched target → Corvaan (your order: Break the Casters)`
> `19.1s — Aegisox fell back (your order: When hurt → Fall back; Nerve 62, clean disengage)`

⚠️ **This is not polish; it is the load-bearing feature of a no-intervention game.** It converts
"the AI did something stupid" into "my order did that" — the single difference between the TFM
complaint thread and a game where losing teaches you something.

---

## 7. Consequences and risks, stated honestly

1. ⚠️ **More axes = more ways to look stupid.** Every new tactic is a new failure mode. The
   mitigation is §6, and §6 must ship *with* the axes, not after them.
2. ⚠️ **Solid bodies need a blocked-unit rule.** No pathfinding is permitted (determinism), so a
   unit whose route is blocked must have a defined behaviour — squeeze, wait, or reroute — or it
   will jitter against an ally forever. This is the classic local-avoidance deadlock.
3. ⚠️ **Mixed aiming has an unresolved interaction with the damage contract.** Today accuracy is
   a stat roll. For an aimed ability, does it roll accuracy *and* have to connect geometrically
   (double jeopardy), or is geometry the only test? **Needs a decision.**
4. **Assignable classes must not lock a species out of a role** — the one rule that has to
   survive the rework (`CLASS_REWORK.md`).
5. **Five new stats** (4 personality + speed) touch generation, breeding, training, the market,
   save format and `data.json`.
6. **The balance baseline stays suspended.** None of this is tuned; getting the structure right
   is the job.

---

## 8. Resolved — the second round of decisions

| # | decision |
|---|---|
| 20 | **Aimed abilities: accuracy = AIM QUALITY.** Geometry decides the hit; the accuracy stat governs how well the monster leads a moving target. ⚠️ **No double jeopardy** — an aimed ability does not also roll to miss, or it would be strictly worse than an auto-hit one. |
| 21 | ⚠️ **REAL PATHFINDING IS WANTED AND IS A KEY FEATURE.** Not local steering alone. |
| 22 | **Monsters path around static cover AND enemy bodies**; allies are passable. ⚠️ **But the ORDERED TARGET is never a blocker** — it is a destination. |
| 23 | **Speed is a 0–100 stat**, like personality — not on the 0–1000 combat scale. |
| 24 | **Class is re-assignable at a real cost** (gold + retraining weeks). |
| 25 | **Personality is trainable within a bred band.** Breeding sets the range; a **dedicated background coach works one stat per week**, upgradable to more. It does NOT compete with combat training. |
| 26 | **Personality stats are 0–100, uncapped by league.** ⚠️ Corrected 2026-08-04 — "always visible" applies to the four exposed in §3 (Aggression/Discipline/Nerve/Focus); `teamplay`/`patience` stay hidden and unexposed. |
| 27 | **Urgent overrides: all four apply** — taunted · ordered target gone · about to die with an escape · destination unreachable. |
| 28 | ⚠️ **BUT `fight on` BEATS THE DEATH OVERRIDE.** A monster explicitly ordered to fight on dies fighting. The self-preservation override applies only to monsters on `fall back` or `disengage`. **The player's order stays sovereign** — this is the specific guard against TFM's flee-then-return spiral. |
| 29 | **Determinism: decide after a spike.** Build a small test of the middle path and MEASURE whether Godot's navmesh queries reproduce, rather than assuming. See §11. |

---

## 9. The AI architecture — a behaviour tree with utility nodes

**Decided: behaviour tree, with utility scoring inside specific nodes. Tactics swap whole
subtrees. Written in GDScript.**

⚠️ **THE TREE IS CHOSEN FOR LEGIBILITY AS MUCH AS FOR BEHAVIOUR, AND THAT IS THE POINT.**
§6 requires live intent labels and a per-monster decision log. In a behaviour tree **the active
branch IS the explanation** — `Combat → Engage → Path to target` is already a readable intent
string, and the branch history is already a decision log. A utility-only AI would have forced us
to reconstruct intent from scores after the fact, and "0.73 beat 0.71" is not an explanation a
player can learn from.

**The division of labour:**
- **The tree** decides *what kind of thing to do* — engage, hold, fall back, guard, dive.
- **Utility scoring inside a node** decides *which one* — which enemy, which position, which
  ability. Nuance lives here, structure lives in the tree.

**Tactics swap subtrees, not flags.** `Dive` plugs in a different approach branch than `Hold the
line`. Behaviours stay genuinely distinct rather than being one tree with different numbers, and
a new tactic is a new subtree rather than a new conditional threaded through everything.

**Personality weights branch selection.** Discipline/Nerve/Aggression/Focus tune which branch
wins under pressure — no new machinery, and it makes temperament visible in behaviour.

**In GDScript, not data.** Faster to write, type-checked, debuggable. ⚠️ Note this is a
deliberate exception to the project's "gameplay values must be data-driven" standard
(`.claude/docs/coding-standards.md`) — recorded here so it is a known trade, not a drift. The
*numbers* the tree reads should still come from data even though the *shape* is code.

### The blocking rule, as a tree branch
⚠️ **Stated as my recommendation — the user asked for tree-based free thinking rather than
picking a fixed rule, so this is the coordinator's call and is open to override.**

```
Is an enemy blocking my path?
├─ Is it within my reach?  → ATTACK IT (and keep pressing toward my ordered target)
└─ Otherwise               → PATH AROUND IT
```
This gets all three properties at once: front lines genuinely wall people off, the player's
target order is still obeyed, and **a monster never stands being punched while staring into the
distance** — because anything blocking you is by definition within reach.

---

## 10. What the reference games teach, applied

| their failure | our guard |
|---|---|
| "wandering in circles" | every tick resolves to a named branch; no idle state without a reason |
| flee at low HP then return to die | `fall back` has a minimum dwell + a real safety condition; `fight on` overrides self-preservation entirely (§8 #28) |
| loses interest in the healer when a tank dips low | `sticky` commitment, defaulted from **Focus** |
| "blindly following programmed strategies" | urgent overrides (§8 #27), deliberately a SHORT closed list |
| player can't tell why | live intent + decision log, which the tree gives us structurally (§9) |

---

## 11. ⚠️ The determinism spike — do this FIRST

**Question:** does `NavigationServer3D.map_get_path()` return byte-identical paths across runs
for a baked static navmesh?

**Why it matters:** determinism buys paired A/B balance testing (this project's core balancing
doctrine — same fights, two settings, sign test), seed-replayable fights, and reproducible bugs.
It costs us writing our own pathfinding and collision.

⚠️ **AND THE EARLIER FRAMING OF THIS WAS TOO ALARMIST — CORRECTED HERE.** The 219 contract cases
test PURE MATH (`damage`/`derive`/`status`/`tick`/`classify`) and stay deterministic regardless
of what the spatial layer does. Dropping spatial determinism would NOT break the existing suite.
What is genuinely at risk is *spatial* balance measurement and replays — narrower than first
stated.

**The spike:** bake a navmesh, run N identical path queries across separate processes, diff.
Then decide on evidence. Report the result before building either way.

### ⚠️ RESULT (2026-08-07): DETERMINISTIC — the AI build may use NavigationServer3D.

`scenes/_spike_navdeterminism.tscn` bakes an arena-shaped navmesh (50x28 floor, four pillars)
fully server-side and hashes 400 seeded path queries at FULL BIT PRECISION (float bytes, never
printed decimals). **Five separate processes: one SHA-256, 400/400 paths non-empty.** The hash
covers the bake AND the queries, so both are deterministic on this platform.

Three traps the spike ate before it measured anything — all binding on the sim build:

1. **The scene-node bake path is a headless trap.** `NavigationRegion3D.bake_navigation_mesh`
   parsed, baked, reported polygons — and every query returned empty. Go fully server-side:
   procedural `add_faces` source geometry, explicit `map_create`/`region_create`/
   `region_set_navigation_mesh`. That is also the shape the deterministic sim wants anyway
   (injected geometry, no scene magic).
2. **`map_get_iteration_id > 0` is NOT "the map is ready".** The region's mesh landed at
   iteration 2, three frames in; waiting for iteration 1 exits early onto an empty map. Wait
   until a known-good probe query returns a path, bounded.
3. **A vacuous pass is the failure mode to fear.** 400 empty paths hash identically across any
   number of runs. The spike now FAILS LOUDLY if every path is empty — any future determinism
   harness must do the same.

Caveats, stated honestly: this proves same-binary/same-machine determinism, which is what
paired A/B and seeded replays need. Cross-platform bit-parity was not measured and nothing
currently requires it. `map_set_use_async_iterations(false)` is set in the spike; keep it in
the sim so sync timing can never smuggle in frame-order dependence.

---

## 12. The build plan — third round of decisions

| # | decision |
|---|---|
| 30 | ⚠️ **The blocking rule becomes a TACTIC, not a fixed rule.** Some monsters bull through toward their ordered target; others engage whatever intercepts them. The tree branches on it. Supersedes the coordinator's call in §9. |
| 31 | **Build order: spike → tree AI → assignable classes → art/modes.** |
| 32 | ⚠️ **`spatial_sim.gd` AND `spatial_ai.gd` are REWRITTEN FROM SCRATCH.** Not evolved. The flat-scoring structure is what produces the blob, and it survives incremental refactors. |
| 33 | ⚠️ **The frame-stream contract is REDESIGNED too**, not preserved. Now that intent and decision logging are first-class, the sim should emit them per unit rather than have the renderer infer them. **The renderer is rewritten with it.** |
| 34 | **Full projectile data per ability** — not just aimed/auto-hit, but speed, width and pierce. A lobbed boulder and a snap bolt genuinely differ. 141 moves to author. |
| 35 | **Assignable classes land right after the tree AI**, so the tree is tuned against the final role set. |

### What the redesigned frame stream needs to carry
Beyond position/HP/state, each unit record now wants:
- **`intent`** — the active behaviour-tree branch as a readable string (`Engage → Path to target`).
  This is the live label, straight from the tree.
- **`reason`** — why this branch won (`order: Break the Casters`, `taunted by Aegisox`,
  `Nerve 62: clean disengage`). This is the decision log.
- **`projectiles`** — in-flight aimed abilities, so the renderer can draw them travelling and
  a viewer can see a shot that *misses because the target moved*.

⚠️ **The renderer must still derive NOTHING.** The reason the contract is being redesigned rather
than extended is precisely so intent and reason come from the tree that made the decision, instead
of being reconstructed after the fact by the presentation layer — which is what would make them
subtly wrong.

### Restore point
`9d51388` — the playable slice, all art, the old spatial layer and every design doc, committed
before the rewrite begins.

---

## 13. Fourth round — the movement decisions, and one reversal

| # | decision |
|---|---|
| 36 | ⚠️ **THE LEASH IS REMOVED ENTIRELY.** It clamped every unit into a circle around the living centroid of BOTH teams — **24% of board width at tight, 42% at loose** — and was self-reinforcing, because the centroid is wherever everyone already is. `ARENA_BLUEPRINT.md` §4 asserts this as intentional; that intent is **superseded**. Positional intent, formations and objectives hold the fight's shape instead. |
| 37 | **Sudden death is removed.** `SUDDEN_DEATH_AT = 255.0` against `MAX_DURATION = 180.0` meant `sudden_death_loss()` returned 0.0 on every call in both engines — dead code on a per-unit-per-tick path. ⚠️ Moves 4 cases in `tick.json`; a deliberate recapture. |
| 38 | **Modes INJECT SUBTREES.** ⚠️ Chosen against the modes stream's recommendation of goal-supply — recorded because the reasoning against it is real and will resurface: injection creates an N×M merge between every tactic and every mode. See §13.1. |
| 39 | **The kite fix is STRUCTURAL: minimum range + a kite-episode cap.** Not a speed number, not a harsher penalty. |
| 40 | **The closing bonus tapers smoothly** with distance instead of switching off at 18 units. |
| 41 | ⚠️ **SPEED IS SPECIES/BODY DERIVED ONLY — not a trained or bred stat.** This REVERSES decisions #19/#23 and reinstates `ENGAGEMENT_DESIGN.md` §6e, which recommended exactly this before either was written. |
| 42 | **Personality bred band: flat ±15** around the bred value. |

### 13.1 ⚠️ The infinite-kite hole that was live in the constants

A chase resolves only when the chaser's effective speed beats the kiter's retreat speed. With
`SPEED_MIN 2.4` · `SPEED_MAX 6.0` · `BACKPEDAL_MULT 0.60` · `CLOSING_BONUS 1.25`:

```
fastest kiter retreating   6.0 × 0.60 = 3.60 u/s
slowest chaser closing     2.4 × 1.25 = 3.00 u/s   ← loses ground, permanently
```

**The governing constraint is `SPEED_MIN > SPEED_MAX × BACKPEDAL_MULT`, and it does not hold.**
Break-even sits near Speed 13 with the closing bonus and Speed 33 without it, so roughly the
bottom third of the speed range could never catch the top third.

⚠️ **A second, subtler bug: the closing bonus cut off at 18 units.** A mid-speed chaser closed to
18, lost the bonus, fell behind, drifted back past 18, regained it — an oscillation that would
have rendered as precisely the *"wandering in circles"* behaviour TFM2's players complain about
(§0). Fixed by decision #40's smooth taper.

**Why the fix is structural rather than numeric:** `ENGAGEMENT_DESIGN.md` already measured that
*"a chase NEVER resolves ... regardless of field size or speed (both measured, both invariant)"*.
Speed was never the lever. Minimum range (a kiter pinned inside its own minimum range must fight)
and a kite-episode cap bound the behaviour **without constraining the speed spread at all** —
which is what lets speed stay a genuine design axis.

### 13.2 ⚠️ Speed reverses to derived — and the earlier doc was right

Decisions #19/#23 made Speed a trainable, breedable 0–100 stat, and `PERSONALITY_STATS.md` §6 was
written to that. **Superseded.** Speed is now derived from species and body only — a property of
what a monster IS, not what it trained.

⚠️ **This reinstates `ENGAGEMENT_DESIGN.md` §6e verbatim, which had recommended a derived
`CLASS_SPEED × BODY_SPEED` model before any of this round was written.** The intervening
"supersession" note added to that document should itself be reverted. Recorded here rather than
quietly corrected, because the lesson is the recurring one: **the existing doc had already done
this reasoning, and a round trip was spent rediscovering it.**

**Consequence:** `PERSONALITY_STATS.md` now covers four axes plus the new `focus`, and its §6
(Speed as a trainable stat) is void. No speed breeding, no speed coaching, no new stat surface in
the save format.
