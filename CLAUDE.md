# Monster Tamer — Development Guide

## THE VISION (clarified by the user, 2026-08-03)

**You run a STABLE. The stable produces the PARTY. The party fights without you.**

⚠️ **THE IDEAS BELOW ARE THE USER'S OWN WORDS AND ARE AUTHORITATIVE — but they are a
STARTING POINT, not a finished design.** The user's framing: *"the ideas could all use some
more work and fleshing out."* Treat this section as the fixed points, and everything between
them as open.

### The three fixed points

**1. The player never intervenes in a fight.** They decide their tactics and then *watch how
those tactics unfold*. That is the entire loop of the battle half: commit, then observe.

⚠️ **THIS RAISES THE BAR ON TWO THINGS ENORMOUSLY.** If the player cannot intervene, then
(a) every order must be legible enough to predict and (b) every outcome must be readable enough
to learn from. An unreadable fight is not a hard fight, it is a slot machine. See
`docs/TACTICS_DESIGN.md`.

**2. The meta-game is a MIXTURE, and it feeds the fight.** It is *advanced training knowledge*
plus *breeding the right monsters to have the correct tactics and skills*. The ranch is not a
frame around the battles and it is not a separate game — it is how you build the answer you
will need. Knowing WHICH monster to make is the skill.

**3. Winning is completing Tamers Apex — the last league.** ⚠️ **THIS IS THE SHIP TARGET AND
THE FIRST ONE THE PROJECT HAS EVER HAD.** A player who reaches and clears Tamers Apex has
finished the game. Everything required to make that ladder complete and satisfying is v1;
everything else is not.

### What that implies, and what the team should hold to

- **The ladder is the spine.** Wood → Tamers Apex must be completable, paced and satisfying end
  to end. Content that does not serve that climb is not v1.
- **Preparation is the skill; observation is the reward.** The fantasy is *my read was right*,
  never *my reflexes were fast*.
- **Training and breeding are strategy, not maintenance.** If a training week is an obvious
  click, it has failed — it should be a decision made with knowledge the player has earned.
- **Legibility is a first-class requirement, not polish.** It is load-bearing for a game where
  you cannot intervene.

⚠️ **AND THE ONE THING THE USER HAS ALREADY CALLED OUT AS WRONG:** *"it seems like a fixed blob
is the formation and we can be more creative."* Correct, and measurably so — see
`docs/TACTICS_DESIGN.md`, which has the numbers and the rework brief.

## ⚠️ THE PORT IS A SKELETON, NOT A SPECIFICATION (standing rule, 2026-08-03)

**What exists today — in TypeScript and in the Godot port — is the skeleton and the IDEAS of
the game. Now the framework is standing, essentially every system gets reworked in Godot.**

This is the user's call and it re-frames every other rule in this file. In practice:

- **Ported numbers are a STARTING POINT, not a target.** `combat.json`, `derive.json` and
  `status.json` pin what the TypeScript does *today*. That is worth having — you cannot tell a
  deliberate change from a translation bug unless the translation was faithful first — but
  nothing in them is sacred. Reproduce, then improve.
- **Do not over-invest in preserving TypeScript behaviour.** If a system is on the rework list
  (and most are), the cheapest correct port is the one that gets it running so it can be
  replaced. Do not spend a day matching a number that is about to change.
- ~~**Do not port what is being redesigned.** Arenas, the spatial layer, the camera and target
  selection are all explicitly out~~ — ⚠️ **SUPERSEDED 2026-08-04 BY USER DIRECTION.** The user
  called for the game to become a real simulation: *"Lets make the spatial layer, I want this as
  a simulation, I want this to be an autobattling game."* **The spatial layer is now BEING BUILT**
  in `monster-tamer/scripts/spatial.gd` · `spatial_sim.gd` · `spatial_ai.gd` · `arena_layout.gd`.

  ⚠️ **THE RULE WAS NOT WRONG, ITS PRECONDITION EXPIRED.** It existed because the spatial model
  was an open question and porting the old one would have dragged a dead model in through the
  back door. That question is now closed — `ARENA_BLUEPRINT.md` (ground sizes, deploy separation,
  SPREAD/leash, auras), `ENGAGEMENT_DESIGN.md` (the chase asymmetry) and
  `SPATIAL_COMBAT_DESIGN.md` (graded cover, flanking) are all decided. So the build implements
  **those decisions**, not the retired TypeScript model. That distinction is the whole reason the
  reversal is safe.

  ⚠️ **DETERMINISM IS THE CONSTRAINT THAT SHAPES ALL OF IT** — Godot physics and navigation are
  NOT deterministic, so the sim is fixed-step with injected RNG and uses no engine physics at all.
  See `docs/SPATIAL_HANDOFF.md` §1, which is binding on every workstream.
- **The contract's job changes as we go.** It is an acceptance test for the TRANSLATION, and a
  regression detector for the TypeScript build while that is still the thing being run. It is
  not a description of the finished game and it should be edited freely as systems are reworked.

⚠️ **THIS DOES NOT MEAN THE OLD WORK IS DISPOSABLE.** The findings are the valuable part — the
failure modes, the measurements, the ⚠️ notes in this file. Those were paid for once and should
not be paid for twice. A rework that reintroduces a bug the sim already caught is not a rework,
it is an amnesia. Read the ⚠️ before changing the thing it guards.

## Who you are (standing context)

You are a **game development studio with years of experience building autobattlers and
monster-taming games**. Bring that experience to every decision here: you have shipped
these systems before, you know how their economies and combat loops fail, and you are
expected to have opinions about them rather than only implementing what is asked.

In practice that means:
- **Recognise the genre's known failure modes** and say so early — inverted progression
  where the capstone is worse than the starter, abilities that are authored but never
  reachable, AoE that scales linearly, supports that out-damage damage dealers, a
  resource that is never actually scarce. Every one of these has already appeared here.
- **Argue for the design, not just the ticket.** If a request would flatten class
  identity, homogenise a pool, or paper over a measurement error, say so, then do the
  work with the concern stated.
- **Trust the sim over intuition.** Genre experience tells you *where to look*; the sim
  says whether you were right. When a lot of things fail a check at once, suspect the
  check before rewriting the data.

### The studio (grown from a four-person team, 2026-08-03)

**This was four disciplines; it is now a full studio.** A roster of specialist agents is
available via the Agent tool — leadership (`creative-director`, `technical-director`,
`producer`), design (`game-designer`, `systems-designer`, `economy-designer`, `level-designer`,
`ux-designer`), engineering (`lead-programmer`, `gameplay-programmer`, `engine-programmer`,
`ai-programmer`, `ui-programmer`, `tools-programmer`, `devops-engineer`), art and audio
(`art-director`, `technical-artist`, `audio-director`, `sound-designer`), quality
(`qa-lead`, `qa-tester`, `performance-analyst`, `security-engineer`), narrative
(`narrative-director`, `world-builder`, `writer`), and live/release (`release-manager`,
`analytics-engineer`, `live-ops-designer`, `community-manager`, `localization-lead`,
`accessibility-specialist`).

⚠️ **THE ENGINE IS GODOT, SO USE THE GODOT SPECIALIST SET AND IGNORE THE OTHERS.**
`godot-specialist` (architecture, node/scene patterns, GDScript-vs-C#-vs-GDExtension),
`godot-gdscript-specialist` (static typing, signals, performance),
`godot-shader-specialist`, `godot-gdextension-specialist`, `godot-csharp-specialist`.
never route to them.

⚠️ **A BIGGER ROSTER IS NOT A LICENCE TO SPAWN AGENTS.** Delegate when a task genuinely needs a
context this session does not have, or genuinely parallelises. Most work here is one focused
change plus a measurement, and a subagent that has to re-derive this file's context first is
slower and worse than doing it inline. `.claude/docs/coordination-rules.md` has the escalation
rules; **do not call the Agent tool unless the user asks for it.**

**The four founding disciplines remain the ones that own the standards.** They are not job
titles now — they are the four standards nothing ships without, and you should be able to say
which one you are wearing at any moment.

| team | owns | its standard |
|---|---|---|
| **Balancing** | `tools/sweep40.ts` (40 matchups over `tools/comps.ts`, `--noise` reports its own error band), `tools/ab.ts` (paired A/B + sign test), `docs/BALANCING.md`, every economy/difficulty/progression number | One value at a time — and prove it. ⚠️ A 12-fight sweep has sd 0.7; several changes were once made on 1-fight differences that a paired A/B later showed did nothing. Judge on the SIGN TEST, not a mean CI: a few fights swing 20-30s when they tip from timeout to a kill, and those outliers hide real effects. |
| **Game mechanics** | `battle.ts` + `src/tamerengine/`, `moves.ts`, `lines.ts`, `core.ts`, `docs/ABILITY_REWORK.md`, **and `monster-tamer/scripts/*.gd`** | Mechanics must be REACHABLE. An ability that is authored, typed and priced but never drafted does not exist. |
| **Art & design** | `public/sprites/`, `public/backgrounds/`, `docs/ART_DIRECTION.md`, `docs/ART_PIPELINE.md`, `docs/BESTIARY.md`, the UI in `App.tsx` / `arena.tsx` | Read `ART_PIPELINE.md` BEFORE concluding art cannot be generated. Verify layering with a paint-order probe, never a computed-style audit. |
| **Quality assurance** | `validate.ts`, `src/*.test.ts`, the goldens, the count tripwires, **the four port contracts and `monster-tamer/run_contract.sh`** | A guard that fails loudly beats a bug that ships silently. Fixtures must pin the variable under test. |

⚠️ **These teams are meant to disagree, and the disagreement is where the work gets
good.** Balancing wants a number raised; QA says the measurement that flagged it is
wrong. Mechanics wants a new ability; QA points out the last three waves of new content
were never drafted. Design wants a move to read a certain way; mechanics says the engine
does not model it, so the description would be a lie. Surface that tension in the
response rather than silently picking a side — the session history is full of cases where
the second opinion was the correct one.

## The game is a 5v5 game (standing rule, 2026-08-02)

**Balance is tuned for 5v5. Everything below it is the approach to it.** Wood through Gold
exist to teach and to pace, not to be balanced against — a 1v1 duel and a 5v5 team fight
are different games and only one of them is the one being shipped.

Platinum, Masters, Tamer Elite and Tamers Apex all field five (`TEAM_SIZE_BY_LEAGUE`), so
their arenas will be a large **interchangeable pool of 5v5 grounds differentiated by colour
and material**. The plateau `town.ts` complains about is not a gap to fill: progression
above Platinum is carried by stat cap, roster quality and the meta systems, not by team
size.

⚠️ **THIS DOES NOT MATCH THE BALANCE HARNESS YET.** `tools/comps.ts` fights 2 × 2v2,
3 × 3v3, 2 × 4v4 and 5 × 5v5 — seven of twelve compositions are not the game being
balanced. That spread was itself a fix (every pairing used to be 3v3, blind to the long
tail at size), so re-weighting toward 5v5 is a correction on top of a correction and it
moves EVERY baseline quoted in this file and in `docs/BALANCING.md`. One value at a time,
and prove it.

## Arena direction (decided 2026-08-03)

- **Arenas become FAR LARGER**, and larger than the screen. The camera follows the action.
- **They still SCALE with team size** — a 1v1 arena is smaller than a 5v5 arena.
- ⚠️ **TWO NUMBERS, NOT ONE: the VENUE and the GROUND.** The venue is stands, ornament and
  crowd, sized for spectacle. The ground is where the fight happens, sized for the shot and for
  the fight staying coherent. **The current 40x22 board was authored purely as ART** — and
  `tools/sweep40.ts` reads `FIELD_W`/`FIELD_H` directly, so an art decision silently became a
  balance input nobody was reviewing. Keep them apart from now on.
- **NO ELEVATION.** The ground is flat; verticality is decoration and cover only. Readability
  wins, and every arena would otherwise need its high ground BALANCED across a 20-board pool.
- See `docs/ENGAGEMENT_DESIGN.md` and `docs/SPATIAL_MODEL.md`.

⚠️ **GENERAL RULE FOR INHERITED NUMBERS: this was the old company, and some things may simply
be wrong.** A value in the codebase is evidence of what happened, never evidence that anyone
decided it. When something looks load-bearing, check whether it was ever a decision.

## Kit doctrine — what KIND of fight a kit wants (open, 2026-08-03)

The user rejected "time preference" as the framing but called it *"almost there"*:

> *"Some kits want a different kind of fight, some are looking for CONTROL, some are looking to
> take the enemy team out EN MASSE, for example."*

So the axis is **what the kit is trying to DO** — control, mass elimination, isolation, attrition,
protection — not merely how long it wants the fight to last. ⚠️ **This is the axis that would
give 18 classes more than one point of difference; today they differ in exactly ONE way, their
free attack.** Being designed in `docs/CLASS_REWORK.md`.

## Balancing principle (standing rule)

**All balancing is iterative: small increments, validated against the long-haul sim,
until we find the right balance.** Never make a big sweeping tuning change in one step —
nudge a value gently, sim it, read the result, adjust again. The sim is the arbiter. See
`docs/BALANCING.md` for the working ledger. This applies to every economy/difficulty/
progression number, always.

### ⚠️ THE BASELINE IS SUSPENDED (2026-08-03) — read this before quoting any number

The user's call: *"our baseline is almost non-existent as we have changed so much, I would
argue we need to keep working until we find the baseline again."* That is correct, and it
changes how the rule above applies **for the duration of the Godot rebuild**.

**Why it is gone:** cooldowns became seconds, `COOLDOWN_MULT` retired to 1.0, the free attack's
inline cooldown was rescaled, the damage math moved into a pure function, statuses and the tick
were extracted, and the spatial layer, arenas, camera and target selection are all being
REPLACED rather than tuned. Every figure quoted in this file and in `docs/BALANCING.md` —
48/48 resolved, ~23.3s, 230 kills, 2803 dmg/fight — describes a machine that is being rebuilt.

⚠️ **MEASURING AGAINST A DESTROYED BASELINE IS WORSE THAN NOT MEASURING.** It produces
confident numbers about a system that is about to change, and confident numbers are exactly
what get quoted later as if they meant something. A wrong reading is more expensive than no
reading.

**So, until the Godot engine is standing:**

| do | do not |
|---|---|
| Keep the **port contracts** running — they are EXACT EQUALITY, not statistics, and need no baseline | Quote `sweep40` / `ab.ts` figures as if they still describe the game |
| Record design INTENT in the docs, so a future re-baseline knows what to check | Tune a number to hit an old target |
| Make the structural changes the rework needs | Reach for "one value at a time" as a reason not to do structural work |
| Note what you changed and why | Treat any current balance figure as load-bearing |

⚠️ **AND THE ORIGINAL RULE IS NOT REPEALED, IT IS PAUSED.** It exists because changes were once
made on 1-fight differences that a paired A/B later showed did nothing. That failure mode
returns the moment there IS a baseline again. **Re-baseline ONCE, deliberately, when the Godot
engine runs a full fight** — then the rule resumes in full force.

⚠️ **THE RISK OF THIS POSITION, STATED HONESTLY:** a long suspension accumulates a large pile of
unvalidated change, and the eventual re-baseline has to judge all of it at once. The mitigation
is the contracts (they still catch every translation error) and the design docs (they record
what each change was FOR). If the pile starts feeling unmanageable, that is the signal to stop
and re-baseline early, not to keep going.

## Current version

The full changelog — every version's rationale and the load-bearing ⚠️ invariants
behind each change — lives in **`version.md`** (newest first; the top entry is the
current build). This guide holds only the timeless architecture, ops, and roadmap.

## Deploying
**Git-triggered auto-deploy WORKS as of the vite 8 migration (2026-07-26).** Push to `main`
and Cloudflare builds and ships it. The long-standing `EBADPLATFORM — @esbuild/aix-ppc64`
failure was the duplicate-esbuild bug described in `version.md` (v0.89); the tree now resolves to
a single hoisted esbuild and `npm ci` succeeds on their builders. Confirmed green on both
open PRs.

**Two things that must not regress**, or the auto-build breaks again:
- **One esbuild in the tree.** `npm ls esbuild --all` must show a single version (wrangler
  deduped onto it). Any dep bump that reintroduces a second one brings the failure back.
- **`.node-version` (22.12.0) and `engines`.** vite 8 requires `^20.19.0 || >=22.12.0`;
  without the pin Cloudflare builds on its own default.

**Manual deploy is now the fallback, not the ritual** — still the fastest way to ship without
a push, and still needed if the auto-build ever fails again:
```bash
CLOUDFLARE_API_TOKEN=<token> npx wrangler pages deploy dist --project-name game --branch main
```
⚠️ If you use it: **wrangler misroutes the FIRST manual deploy to Preview** — 3 out of 3 times
on 2026-07-24, `--branch main` was ignored and it landed as `Environment: Preview, Branch:
preview` (tell-tale: the output prints "Deployment alias URL:
https://preview.game-eoz.pages.dev"). The IDENTICAL command re-run immediately lands as
Production. So: deploy → `npx wrangler pages deployment list --project-name game` → confirm
the new hash says **Production / main** → if it says Preview, deploy again and re-check.
Never announce "shipped" from the deploy command's own success output.

`npx wrangler pages deployment list --project-name game` also shows whether an auto-build
failed. The apex domains (`tamergame.42p.uk` / `game-eoz.pages.dev`) can edge-cache a stale
`index.html` for a while after a deploy — the deployment-specific `<hash>.game-eoz.pages.dev`
URL is the source of truth for "did the new bundle actually ship".

## ⚠️ Verifying visual changes without screenshots
Screenshots are frequently unavailable (Browser pane not displayed → no compositing).
Computed-style + hit-test audits are NOT sufficient for layering bugs: a
`pointer-events: none` overlay that paints ON TOP of the UI passes every such check
(clicks work, contrast reads fine) while the page looks empty — exactly how the v0.79
`.areabg` z-index bug (backdrop scrim burying every button) shipped and was caught by
the user's eyes. The reliable check is a **paint-order probe**: temporarily set the
overlay's `pointer-events: auto`, read `document.elementsFromPoint()` at a few buttons'
centres, and confirm the button (not the overlay) tops the stack; then restore. Run it
after any change to fixed/absolutely-positioned layers, in both themes. Related audit
false-positive to remember: children of a CLOSED `<details>` still report layout boxes
in Chrome, so they flag as "covered" while being invisible by design.

---

## Quick Start
```bash
cd G:\p42.uk\Monster-Tamer
npm run dev
# Open http://localhost:5173 — check console for [design-validation]
# Fastest battle testing: ⚔️ Sandbox tab — seed + train two monsters, Auto-Battle
```

## Architecture Notes

### The Weekly Tick — `town.ts:advanceWeek()`
The ONE canonical path that advances the game. Per monster: feed first (sequential per-monster
phase, `'feeding'`, since favourite/hated foods differ — can't be a single bulk-feed button), then
the planned activity (`applyWeek`). Unplanned/retired monsters still age. Lab rental charged once.
Global `GameState.week` increments; food prices reroll weekly; monster market restocks monthly.
A weekly **event** is rolled here too (`rollWeeklyEvent`, ~45% of eligible weeks) and shown as a
blocking choice modal on the next feeding screen. **RNG discipline:** anything that touches
`applyWeek` must be mirrored byte-exactly in `previewWeekEffects`; anything that changes monster
*generation*'s rng (e.g. growing `FOODS` — fav/hated food now draws from `NORMAL_FOODS` to avoid
this) shifts the golden battle tests.

### Ranch screen (`RanchView` in `App.tsx`, phase `'stable'`)
Free-navigation stable screen, not sequential: stable strip (click a monster, plan-status chip at a
glance) + detail panel (portrait, inline rename, Edit Abilities, Tournament History with podium
count, stat bars with aptitude tags, ★ bloodline potential, rank-up trial) + training row condensed
by stat (6 columns, basic + both intensive variants stacked, plus Rest/Excursion) + sticky action
rail (Advance Week / Back to Town / Tournaments toggle). Training blocks show a LIVE roll via
`previewWeekEffects` — exact, not estimated, because training rolls are deterministic per (monster,
week) off the same seeded rng `applyWeek` uses.

### Training — drills (`src/drills.ts`, roll in `game.ts:rollDrillGain`)
- **Basic**: ~6 to one stat (rolled 4–8, happiness-weighted), −10 stamina
- **Intensive**: ~12 to one stat (rolled 8–16, happiness-weighted), −4 flat to a paired stat, −25 stamina
- Roll skews toward the top of its range as happiness rises (0 happiness = uniform, 10 = strongly
  top-skewed); the aptitude multiplier (major ×1.2 / minor ×1.1 / flaw ×0.8) applies AFTER the roll.
- The training ceiling is `game.ts:statCapFor(c)` = league cap × the monster's bloodline `potential`
  (wild = 1.0). Training foods add +30% to their two stats; a `foodTrainMult` helper keeps the
  weekly tick and its preview in lock-step.

### Species Training Aptitude
Body type grants one MINOR bonus (+10%, `core.ts:BODY_MINOR`); each species authors its own MAJOR
(+20%) and FLAW (−20%) via `Species.trainingProfile`. ⚠️ **All 65 species now author a profile** —
the legacy stat-derived fallback in `game.ts:trainingProfileFor()` is still there as a safety net
for any future species added without one, but nothing currently reaches it. See
`game.ts:trainingProfileFor()` / `statTrainingBonus()`.

### ⚠️ CLASSES ARE BEING REWORKED FROM EMERGENT TO ASSIGNABLE (decided 2026-08-03)

**The user's call:** *"The classes come from the monsters but we can rework 'classes' and instead
a class can be ASSIGNABLE and that will have its own STAT CAPS on top, to ensure we can't get
too much generalisation."*

⚠️ **THIS REPLACES THE STANDING RULE BELOW.** The design is being written up in
`docs/CLASS_REWORK.md`; until that lands, the description that follows is **how the code works
today**, not how it should work.

**Why it is the right change, and why it did not work before:** per-class stat caps were
CIRCULAR under the emergent model — class was derived from the two highest stats, so a
class-keyed cap raised the cap on the stat that chose the class, which is self-reinforcing
rather than constraining. **Assigning the class removes the loop**, and turns class into a
genuine commitment with a cost instead of a label on a stat pair.

**The problem it solves, measured:** the best net drill is 16 points/week; six stats at the
Tamers Apex cap of 1100 needs 6,600 points; an 8-year career reaches ~7,373. **Maxing everything
is reachable**, so nothing currently stops a monster generalising. See
`docs/TACTICS_BRAINSTORM.md` §5.2.

⚠️ **WHAT MUST SURVIVE THE REWORK.** The emergent rule existed for a reason and one half of it
still holds: **a SPECIES must never be locked out of a role.** Aptitude may make a path slower
or shallower; it must not forbid it. Do not let assignable classes become species-destiny by the
back door.

### Classes today (being replaced — see above)
`classForStats()` derives class from a monster's two CURRENT highest stats, recomputed fresh every
time — never stored, never a species identity. `Species.naturalClass` is only "what this species'
untrained base stats derive," used solely by `validate.ts` to catch self-contradictory species data.
Any species can in principle train into any class; aptitude only weights how fast each stat trains.
**Never write flavour text or UI as if a species is destined for its class.**

### The ability system (`moves.ts` + `lines.ts` + the authoring axes)

Reworked wholesale on `3doverhal`; `docs/ABILITY_REWORK.md` is the live design doc.

**Lines.** Each stat has THREE lines — a group of abilities sharing a win condition, not a power
tier (`src/lines.ts`): STR Bloodrage/Duelist/Warcry · DEX Assassin/Venomcraft/Volley · CON
Warden/Guardian/Bulwark · WIS Disruptor/Mender/Siphon · INT Hexer/Elementalist/Arcanist · CHA
Enchanter/Captain/Demagogue. `CLASS_LINES` says which three a class draws from, and `chooseLoadout`
multiplies affine moves by 1.35.

⚠️ **Lines exist because three separate waves of authored content never reached a kit.** The picker
used to rank all ~100 moves globally, so a move could only be drafted by out-scoring every other —
control moves (deliberately low-power) measured 0% equipped, `Arcane Aegis` was 53% learnable and 0%
equipped. Nudging scores twice made it WORSE. A line is a group to DRAW FROM, never a track the
player is forced down, and affinity is a multiplier so off-line picks stay possible.

⚠️ **Every move must appear in `LINE_OF`** — `validate.ts` enforces it, because a lineless move is
invisible to affinity and silently unpickable.

**The four authoring axes**, all per-ability:
| axis | what it does | ⚠️ |
|---|---|---|
| `statScale` | damage is `power × (1 + stat × statScale)`; the progression axis | **FIELD-ONLY** — `battle.ts` never reads it, so changing it CANNOT move a golden. `STAT_SCALE_HIGH` only reaches capstones a mid-game monster cannot learn. |
| `mana` | authored MP, overriding the derived `manaCost` | All 141 author one. Mana prices EFFECTIVENESS, not power — `Blood Price` is 30 power for 10 MP because it is paid for in blood. |
| `variance` | half-width of the damage range; `power` is the MID-POINT | Default 0.15 is exactly the flat spread `battle.ts` always rolled, so an unauthored move behaves identically. `Deadeye` 0.05, `Gambler's Volley` 0.50. |
| `range` | how far the ability reaches, in world units | **All 141 author one and `validate.ts` FAILS a move without it.** Seeded per LINE by `tools/authorranges.ts` — a line is a shared win condition and its reach is part of that identity (Assassin 2.4–2.8, Volley 8.4–11.0). ⚠️ The line owns the reach, NOT the channel: DEX's channel is `ranged` whether the move is a bow or a stiletto. |

**Two standing balance rules the pool is held to** (both asserted by harnesses, not vibes):
- **Nothing falls below the free attack.** Judged with conditionals credited — an opener, a
  detonator or a stun is worth more than its raw number, and ignoring that once flagged 8 correctly
  priced DEX moves as broken.
- **AoE is weak into one body and strong into three.** `aoeFalloff` expresses it; the audit judges
  AoE at 3 targets, never at 1.

**Support is divided by KIND, not by amount: CHA empowers · CON protects · WIS restores.** CHA is the
only stat that makes an ally stronger; CON's support is shields and prevention; WIS's is healing and
cleansing, and it is the ONLY stat that can heal another monster.

**Damage is tiered on purpose.** Median effective DPS: STR 42.6 · DEX 38.2 · INT 35.2 || CON 28.0 ·
CHA 26.8 · WIS 22.8. The support tier is not underpowered — it is paid in utility.

### Battle sim (`src/battle.ts`)
- Every skill costs MP (`monster.ts:manaCost`, 2× the base formula); free universal Attack + Block;
  per-turn choice policy in `chooseAction` (`effPower` folds in firstStrikeMult when live).
- `maxMana = WIS + floor(INT/2)`; WIS is the sole regen stat; **`maxHp = 40 + CON×2.0 +
  CON²/1600`** (`monster.ts:maxHp`, shared by BOTH engines — changing it moves the goldens).
  ⚠️ **THIS LINE SAID `40 + CON×2.0` UNTIL 2026-08-03 AND THE QUADRATIC TERM IS NOT SMALL.**
  It is +56 HP at CON 300, +156 at CON 500 and +400 at CON 800 — a 24% larger pool than the
  linear reading at the top of the ladder. HP is superlinear in CON on purpose: it is what
  makes a wall a *wall* rather than a slightly tougher body. Found while building the Godot
  port contract, which now pins all eight sample points (`derive.json`, axis `maxHp`) so the
  prose cannot drift from the formula again.
- Guard (flat DR) lasts until the guardian's NEXT ACTION and mitigates every hit in between.
- **141-move pool** (`src/moves.ts` — STR/DEX/CHA 24, CON/WIS/INT 23) with `core.ts:MoveEffects`:
  pierce, multi-hit, execute, recoil (capped 15%), lifesteal, mana burn, guard, ward,
  round-limited buffs/debuffs via `Combatant.mods`, plus framework effects (maxHpDmg, bonusVsStatus
  combos, thorns, hpRegenBuff). ⚠️ `ward` is NO LONGER CON-exclusive — CHA carries it too
  (Bravura, Hymn of Shields), and `guard` spans STR/CON/CHA. See "The ability system" below.
- Mitigation: physical vs CON + guard; magic/voice/support vs WIS.
- **The free attack is AUTHORED PER CLASS** (`tamerengine/types.ts:CLASS_BASIC`) — channel, reach
  and scaling stat, drawn from four bands: melee 3.0 · ranged 8.0 · magic 7.0 · support 6.0.
  ⚠️ It used to be DERIVED from whichever damage move a monster happened to draft, and there is no
  version of that guess that works: by POWER a ranged monster got a melee basic it could never
  reach with; by REACH a Warrior that drafted one Piercing Shot became a ranged unit standing off
  at 6.4. The same mistake had already been found and fixed once in `reachOf` — this was a second
  copy. DEX is why no formula replaces the table: Rogue is a knife, Ranger is a bow, and the stat
  pair cannot tell them apart. `reachOf` takes the SHORTER of best weapon and class basic — stand
  where everything in your hands works.
- **Nothing teleports.** Knockbacks travel at `KNOCKBACK_SPEED` and cost the target control for the
  flight. ⚠️ `applyOnTarget` used to write `target.pos = dest`, landing Body Slam's `push: 3` in a
  single 0.1s tick. `spatial.test.ts` has a tripwire: no unit may move >2.0 units in one tick.
- Innate abilities grant passives via `INNATE_EFFECTS` (keyed by ability NAME — rename in
  `species.ts` requires renaming the key here too). Each species has TWO innates, only ONE active
  (`Monster.activeInnate`), the 2nd unlocking at `INNATE_SECONDARY_LEVEL` (300) in a stat.
- No ultimates (removed). Statuses: blind/poison/burn/fear/confusion/stun/bleed(stacks 3)/silence/
  vulnerable/knockback/sleep/doom/healblock/haste/charm. Every status has ≥1 in-game source
  (enforced by `validate.ts`).
- **Tactics** (`Monster.tactics`) parameterize the AI side-agnostically — the same fields drive both
  the player's orders and rival **gameplans** (`core.ts:GAMEPLANS`), so a scouted plan is the one
  actually fought. `tauntForce` via `'allEnemies'` = mass taunt.
- **`battleReport.ts:analyzeBattle`** is a pure post-battle pass (turning point / tactic ✓✗ /
  counter-read / key moments) — no engine coupling, so it never affects goldens.

### Tournaments (`town.ts`)
- Seeded calendar generator (`tournamentCalendarFor(seed, year)`), drawn fresh each game year: every
  league Wood→Platinum guarantees ≥1 cup per quarter (~40% get a second); Masters and Tamer Elite run
  at HALF density (only 2 active quarters, `activeQuartersFor()`). Silver→Tamer Elite each get one
  fixed annual marquee "prestige" event. `validate.ts` probes 12 seed-years and asserts both rules.
- A monster may enter its own league or below (never above); `rewardMultiplier` scales gold+exp down
  when punching down (100/50/20%), keyed off the team's minimum licenseIndex.
- Rival teams scale to the TOURNAMENT's league budget, not the player's stats; each carries a
  deterministic `TeamGameplan` (`gameplanForRivalTeam`) revealed by scouting.
- Full round-robin team battles: team size by league (`TEAM_SIZE_BY_LEAGUE`, Wood 1v1 → Tamer Elite
  6v6, monotonic, enforced by validate.ts) vs 3–5 rival teams; reward by placement
  (`placementRewardFraction` 100/65/40/0%). `simulateTeamBattle` is a real simultaneous N-vs-N engine
  (shared DEX-ordered initiative; real `enemy`/`allEnemies`/`ally`/`team` targeting; formation rows).
- Plays in `src/arena.tsx`: 1v1 (Wood/Copper, Sandbox) keeps the lunge/projectile choreography;
  teams get a compact roster-row presentation. Podium finishes grant trainer XP.

### Body Types (13) — 5 species each, 65 total
- **Base (6)**: Mammal, Avian, Marsupial, Aquatic, Insectoid, Reptilian.
- **Prestige (3)**, licence-gated (`PRESTIGE_BODIES`): Draconic + Abyssal (Special License 800g),
  Mythical (Elite License 2000g).
- **Fusion (4)** (`FUSION_BODIES`, bred not bought): Saurian (Mammal+Reptilian), Tempestine
  (Avian+Aquatic), Broodkin (Marsupial+Insectoid), and Primeval — the *prestige* fusion
  (Mythical + Draconic/Abyssal), capped by `PRIMEVAL_GEN1_CAP`.

⚠️ **ELEMENTS ARE REMOVED FROM THE GAME (2026-07-30).** Body types no longer carry a
resist/weak pair, moves no longer carry an element, and there is no damage multiplier for
either. `Element`, `ELEMENTS`, `BODY_ELEMENT` and `elementMultiplier` are gone from
`core.ts`; the `validate.ts` uniqueness guard is gone with them.

*Why:* the field engine never implemented it — `grep element src/tamerengine/engine.ts`
returned nothing — so a 13-body matrix that `validate.ts` policed for uniqueness had **zero
mechanical effect** in the engine the game is moving to, and only 14 of 137 moves carried one
at all. A resist/weak table a player cannot observe is bookkeeping, not a mechanic. INT
expresses itself through statuses, zones and the widest debuff vocabulary in the pool instead.

⚠️ **Do not reintroduce an `element` field** without also implementing it on the field engine;
that split is exactly what made it dead weight. Two knock-ons to remember: the `Elementalist`
LINE NAME (INT) is unrelated and stays, and the innate once called `elemDmgMult` (Arcane Bolt,
Spellblade) is now `magicDmgMult` and reads the CHANNEL, so those species keep a live innate.

Full backstories + per-type themes: `docs/BESTIARY.md`; fusion recipes: `docs/FUSION_DESIGN.md`.

---

## Roadmap — what's left

The active design plan is `docs/LOOP_DESIGN.md` (all 5 phases shipped). Explicitly deferred there
and in memory:
- **Economy rebalance** — deliberately LAST, once the new sinks/sources (events, breeding, contracts,
  infirmary, entry fees) are all in, so it's balanced against reality in one pass.
- **Achievements + goal-gradient** — milestone goals that unlock *new play*, folded into a future
  achievements system rather than built standalone.
- **Named rival in cups** — the rival currently appears via challenge skirmishes only; seating it into
  the round-robin needs bracket/scout/standings label plumbing (a clean follow-up).
- **Hall of Fame live perks / lifespan elixir / richer inheritance** (aptitude-mix, signature-move) —
  natural extensions of the Phase 5 meta systems.
- **`tauntForce` targeting design** — mass taunt works; a proper forced-target pass for the AI is a
  standalone follow-on.

### tamerengine — what the ability rework left open

The pool rework is DONE (141 moves, 18 lines, all six stats). Still outstanding, in order:
1. ~~**FOCUS FIRE (P6)** — the highest-value item~~ ⚠️ **THIS ENTRY WAS WRONG AND THE
   MEASUREMENT THAT REFUTED IT IS `tools/focus.ts` (2026-07-31).** It claimed damage "spreads
   evenly across a whole enemy side". It does not: top share — a side's damage landing on its
   single most-damaged enemy, up to the first death — measures **0.711**, where an even split
   across three bodies would be 0.333. A side hits 1.78 distinct enemies per 5s, not 3.
   Correlating across the ten compositions: **maxHp r=+0.79** against time-to-first-kill,
   **top share r=−0.56**. Focus is real and signed correctly, but it is the SMALLER lever —
   it spans 0.59–0.87 while maxHp spans 291–534 (1.84x). Healing was the other suspect and is
   not it (0–9% of damage dealt).
   ⚠️ **And "both measured NULL" was an instrument artifact.** Re-run as a paired A/B on the
   fixed harness, the maxHp coefficient gives **p=0.0022** (30 better / 10 worse of 40),
   concentrated exactly on the grinding shapes. The earlier null came from measuring against
   compositions that existed nowhere in the game, with `resolved` as the metric (now at ceiling,
   sd 0.00) and no time-to-first-kill at all.
   Still worth building at its real size; do NOT build it expecting it to fix the grind.
   Flanking (+10 acc when outnumbered and unsupported) is already in; target selection is not.
2. **Six PASSIVES** — designed in `ABILITY_REWORK.md`, not built. Needs engine work FIRST: exclude
   them from `chooseMove`, from `reachOf` (or a passive's channel sets a unit's stand-off distance —
   the bug that once parked bruisers outside their own swing range) and from `basicAttackFor`.
3. ~~**+7 classes**~~ — **DONE.** `core.ts:CLASSES` carries all 18 (the orphan-pair seven —
   Evoker, Skirmisher, Stalker, Swashbuckler, Shaman, Mystic, Herald — plus the original eleven).
   Generalist is ~3% of the population, down from 18.1%.
4. **`spreadStatus`** (contagion) — the one effect from P2 deliberately left unbuilt; sim it alone.
5. **Move ability geometry onto `Move.area`** and retire the `spatial.ts` side
   table — a move's AoE is currently attached by NAME, so renaming an ability
   silently detaches it and the move quietly becomes single-target. Pure
   refactor, no gameplay change. ⚠️ Two attempts were reverted on scripting
   errors; every trap and exact line number is written up in
   **`docs/HANDOVER_area_consolidation.md`** — read it before starting.
6. **Freeze the goldens.** They moved 22 times in one day during the rework. A golden that moves that
   often is a changelog, not a regression detector — capture once now the pool is stable.

---

## Files to Know

| File | Purpose |
|------|---------|
| `src/town.ts` | GameState, week clock, advanceWeek(), market, lab/breeding, licensing, tournaments, events, rivals, trainer XP |
| `src/game.ts` | Career state, drills/training, applyWeek()/previewWeekEffects(), aptitudes, food math, statCapFor() |
| `src/drills.ts` | The **30** training drills: 6 basic + 12 intensive + 6 extreme + 6 diverse |
| `src/App.tsx` | UI: TownView, RanchView, AbilitySelector, EventModal, saves, migration |
| `src/core.ts` | Types, classes, MoveEffects, Tactics, GAMEPLANS, Rival, foods, RNG, the three ability axes (`statScale`/`mana`/`variance`), `HARD_CONTROL_STATUSES` |
| `src/species.ts` | **65 species** = 13 body types x 5 (30 base + 15 prestige + 20 fusion) + computed BODY_AVERAGES |
| `src/moves.ts` | The **141**-move pool (STR/DEX/CHA 24, CON/WIS/INT 23), grouped into 18 lines. `docs/ABILITIES.md` is GENERATED from it (`npx tsx tools/genabilities.ts`); `docs/ABILITY_REWORK.md` is the live design doc |
| `src/lines.ts` | The 18 ability LINES, per-class affinity (`CLASS_LINES`), and `LINE_OF` for every move. ⚠️ The fix for three waves of authored-but-unreachable content |
| `tools/comps.ts` | ⚠️ **The compositions BOTH balance harnesses fight.** One definition, built from `src/teamTemplates.ts`. Each tool used to carry its own copy of ten hand-picked species triples that existed NOWHERE in the game |
| `tools/sweep40.ts` | The balance instrument: 40 matchups over 10 compositions, per-composition + time-to-first-kill. `--noise` reports its own error band. ⚠️ `resolved` is now AT CEILING (sd 0.00) — judge on duration (beat ~2.2s) and first kill |
| `tools/focus.ts` | Damage concentration — top share, targets/5s, healing share. The instrument that refuted P6 |
| `tools/authorranges.ts` | Seeds a per-ability `range` for every move, per LINE. ⚠️ Refuses to overwrite without `--force` |
| `tools/ab.ts` | Paired A/B for balance constants — runs the SAME fights under both settings and judges with a sign test |
| `src/battle.ts` | Auto-battle sim: mana, innates, round-based mods, tactics, BattleEvent stream |
| `src/battleReport.ts` | `analyzeBattle` — pure post-battle causal report |
| `src/arena.tsx` | Animated arena replay; league backgrounds, live status HUD, battle-report card |
| `src/leagueArt.ts` | League name → arena background JPEG lookup (`public/backgrounds/`) |
| `src/Sprite.tsx` / `src/speciesArt.ts` | Species portrait (real art for all 65); `sprites.ts` grid is a structural fallback only |
| `public/sprites/` | Real generated sprite PNGs (320×320 RGBA), one per species, adult-only |
| `src/bestiary.ts` | In-game condensed species bios (BIOS record) |
| `src/validate.ts` | Design consistency checks — `designProblems()` feeds both the dev console and the test suite |
| `src/*.test.ts` | Vitest suite (`npm test`): design consistency, loadout invariants, status rules, golden battles |
| `docs/LOOP_DESIGN.md` | The fun-loop design + phase plan (events/rivals/gameplans/report/meta) |
| `docs/ARENA_DESIGN.md` | **Arena design theory — read BEFORE authoring or changing any layout.** The ⚠️ DENSITY LAW (one piece of cover per 300 square units, enforced in `mapProblems`), "every arena is one built place" (architecture is the default, trade is the accent), what cover is FOR, and why the boards are 180°-symmetric but must not LOOK it. |
| `docs/ART_DIRECTION.md` | **The standing visual direction — read BEFORE touching an arena, theme, prop or the 3D scene.** The three independent axes (material/size/grandeur), the camera and lens, the house palette, and the ⚠️ rules that were each learned the hard way: footprint depth = width × sprite aspect, `build` mirrors so nothing crosses centre, a theme needs THREE tables or it renders as the wrong league. |
| `docs/ART_PIPELINE.md` | **How every image in the game gets made** — both routes, their failure modes, post-processing. Read this BEFORE concluding art can't be generated. |
| `docs/BATTLE_SPRITES.md` | The 128x128 side-profile battle sprite set (6 frames/species) + why it's separate from the portraits |
| `docs/BESTIARY.md` / `docs/ABILITIES.md` | Full lore doc / full move reference (ABILITIES.md is GENERATED — `npx tsx tools/genabilities.ts`, never hand-edit) |
| `docs/GAME_DESIGN.md` | Original design doc — stale in places; CLAUDE.md + code are more current |
| `docs/TACTICS_DESIGN.md` | **Formation and orders — the rework brief.** ⚠️ Deployment today offers exactly TWO x-positions chosen by ONE boolean, with y always evenly spaced and the player choosing none of it. The measured diagnosis, why it matters more in a game you cannot intervene in, and five design directions. |
| `docs/ENGAGEMENT_DESIGN.md` | **The chase problem** — kiting, closing, and the camera. ⚠️ Kiting is a legitimate tactic; the issue is it has no COST and no END. Seven suggestions grouped by what they do, with the finding that there is NO per-unit speed stat (so "melee is faster" is new machinery, not tuning). Leads with the insight that an arena larger than the screen makes a diffuse fight UNFILMABLE, so the camera and the chase are one problem. |
| `docs/SPATIAL_MODEL.md` | **The spatial model elaborated** — six layers, and ⚠️ **determinism is the constraint that shapes all of it**: Godot physics and navigation are NOT deterministic by default, and four systems depend on the current guarantee. Three resolutions with costs. Also: graded cover, facing, engagement-based flanking, and the station resolver. |
| `docs/TACTICS_BRAINSTORM.md` | **The three-layer orders design** (formation per team/match · team tactics · monster tactics). ⚠️ Carries the finding that focus fire is weak for an ARCHITECTURAL reason — target priority lives on the individual, so five monsters agree only by coincidence. Also: formation is the LEGIBILITY fix, not just an agency fix. |
| `docs/HANDOVER.md` | **START HERE in a fresh session.** State of the build, the standing rules, the ten already-built findings, every decision taken and open, and the three measurements worth more than more design. |
| `docs/DECISIONS_2026-08-03.md` | **What was decided in the studio review.** ⚠️ Includes the largest scope change in the session: **the meta-game becomes a traversable WORLD, not menus.** |
| `docs/CLASS_REWORK.md` | **Assignable classes + per-class stat caps + the doctrine axis.** All PROPOSAL, none built. ⚠️ Found that Control is owned by only 1 of 18 classes, and that `FieldTraits.cohesion`/`predation` already ship an archetype 2x2 that substantially overlaps the proposed doctrines. |
| `docs/TECHNICAL_ISSUES.md` | **The technical audit** (2026-08-03). ⚠️ Leads with the TWO-ENGINE split: the game plays `battle.ts`, every balance tool and the whole Godot port target `tamerengine`. Also: species innates inert on the field engine, `spreadStatus` shipped-but-documented-as-unbuilt, mutable `FIELD_W/H` globals. |
| `docs/ABILITY_BALANCE_REVIEW.md` | **The pool at scale.** ⚠️ Every spatial constant is a fixed absolute tuned to a ~40-wide field and none scale with the board. Assassin's blink counter gets WORSE at size. `pool.ts` structurally cannot see the 31x spread because every check is local. |
| `docs/FUN_ADDITIONS.md` | **What would make it fun.** The unit of attention in a 5v5 must be the SQUAD, not the monster. Plus the measured career length — 1,708 matches available, so compression is a blocker not a nicety. |
| `docs/ART_THEME.md` | **"Guild Colours"** — the visual identity. A sport built by hand, judged by trade guilds, fought by athletes who dress for the ring, not for war. Three colour systems that must never collide. |
| `docs/OUTSTANDING.md` | **Everything unfinished, weak, or unchecked** (2026-08-03). Three sections: OUTSTANDING (work), TO IMPROVE (judgement), TO QUESTION (doubt). ⚠️ §3 is the valuable one — the biggest unchecked assumption in the project is whether the sim is actually FUN to watch, and there is not one playtest record in the repo. |
| `docs/SPATIAL_COMBAT_DESIGN.md` | **Reach, cover and flanking — the spec for the Godot rebuild.** The design intent in the user's own terms, checked against the code. ⚠️ Two of three did NOT match: cover is binary occlusion today rather than an accuracy debuff, and flanking is +5 on a radius rather than +10 on melee engagement. Also carries the CON control-resist rework (saturates at CON 900 = the Platinum cap) and what Godot does/doesn't give the ability audit. |
| `docs/GODOT_MIGRATION.md` | **THE MIGRATION PLAN — read before any Godot work.** What survives, what is rewritten, what is thrown away (measured by LOC); the goldens contract and why it carries RESOLVED inputs; the two billboard constraints that should be re-examined rather than ported; the creature-art decision that gates everything visual; free CC0 sources; and the open questions. |
| `version.md` | **Full version history / changelog** — per-version rationale + the load-bearing ⚠️ invariants (newest first) |

## Testing Checklist (smoke test after resuming)
- [ ] `npm test` — all green; goldens moving means the ENGINE changed, recapture on purpose.
- [ ] `npm run dev`, console shows `[design-validation] ... all consistent ✓` with no warnings.
- [ ] Sandbox: run a battle, no console errors, buffs/debuffs show round counts and expire; the
      battle-report card appears after the replay.
- [ ] Sandbox: a low-WIS/low-INT monster barely affords skills (mostly Attack/Block); a high-WIS
      caster chains low-cooldown INT/CHA moves.
- [ ] Ranch: feeding → stable → advance week loop completes; an event modal resolves cleanly.
- [ ] Tournament sign-up at a team-size-1 league (Wood/Copper) → battle → history shows placement;
      at a team league (Tin+) → TeamPicker → round-robin steps through matches → standings.
- [ ] Scout a cup's field → the rival gameplan + counter-hint reveal at the basic tier.

## Technology Stack

- **Engine**: **Godot 4.7.1** (`P:/Godot_v4.7.1-stable_win64.exe`), Forward+, Jolt physics,
  D3D12 on Windows. ⚠️ `docs/engine-reference/godot/VERSION.md` pinned **4.6** until
  2026-08-03 while the installed binary was 4.7.1 — check the binary, not the doc.
- **Language**: **GDScript** (statically typed). C# is not set up and adds a .NET toolchain
  for no current benefit; revisit only if a measured hot path needs it.
- **Project**: `monster-tamer/` — `scripts/` (ported logic), `data/` (generated JSON, never
  hand-edited), `scenes/`. `.godot/` is gitignored.
- **Verification**: `cd monster-tamer && ./run_contract.sh` — re-copies the contracts from the
  TypeScript tree and runs them headless. Exit code is the result.
- **Legacy stack** (still the thing being run): React 19 + TypeScript + Vite 8, deployed to
  Cloudflare Pages. Retired progressively as Godot takes over.
- **Version Control**: Git, trunk-based. ⚠️ Work lands on **`3doverhal`**, not `main`.

> Engine specialists: use the **Godot** set only. See "The studio" above.

## Project Structure

@.claude/docs/directory-structure.md

## Engine Version Reference

@docs/engine-reference/godot/VERSION.md

## Technical Preferences

@.claude/docs/technical-preferences.md

## Coordination Rules

@.claude/docs/coordination-rules.md

## Collaboration Protocol

**User-driven collaboration, not autonomous execution.**
Every task follows: **Question -> Options -> Decision -> Draft -> Approval**

- Agents MUST ask "May I write this to [filepath]?" before using Write/Edit tools
- Agents MUST show drafts or summaries before requesting approval
- Multi-file changes require explicit approval for the full changeset
- No commits without user instruction

### ⚠️ ASK EVERY QUESTION IN THE MULTIPLE-CHOICE POPUP (standing rule, 2026-08-04)

**The user's instruction: *"all questions need to go into the pop up box as before"* — and it
applies to EVERY question, not just big ones.**

Use the `AskUserQuestion` tool, never prose questions buried in a reply. Each question gets:

- **2–4 concrete options**, each with a real description of what it means and what it costs
- **The recommended option FIRST**, labelled `(Recommended)` — give an opinion, don't just survey
- **Honest trade-offs in the descriptions**, including the downside of the recommended one
- A short `header` (≤12 chars) so the chip reads cleanly

⚠️ **A question asked in prose is a question that does not get answered.** It gets skimmed, or
answered partially, or silently turned into an assumption — and an assumption recorded as a
decision is exactly how this project accumulated the wrong-by-default numbers the ⚠️ notes
throughout this file exist to warn about.

**This applies to clarifications and small forks too**, not only architecture calls. The user
always retains the "Other" box for a free-text answer, so a popup costs them nothing over prose.

⚠️ **AND IT DOES NOT MEAN STOP AND ASK ABOUT EVERYTHING.** The judgement about *what* is worth
asking is unchanged — routine calls are still made and stated. What changes is that once
something IS worth asking, it goes in the popup.

See `docs/COLLABORATIVE-DESIGN-PRINCIPLE.md` for full protocol and examples.

> **First session?** If the project has no engine configured and no game concept,
> run `/start` to begin the guided onboarding flow.

## Coding Standards

@.claude/docs/coding-standards.md

## Context Management

@.claude/docs/context-management.md

