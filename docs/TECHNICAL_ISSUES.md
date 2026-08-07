# Technical issues — the Technical Director's sweep

**Written 2026-08-03.** A hunt for what is *silently wrong*, not a list of what is unfinished.
`docs/OUTSTANDING.md` covers the latter and this document deliberately does not repeat it.

Every claim below is sourced to a `file.ts:line`, a measurement I ran, or a reproduction. Where I
am unsure I say so — a flagged uncertainty is worth more than a confident guess.

⚠️ **THE STANDING RULES ARE HONOURED HERE.** The balance baseline is suspended, so nothing below
proposes a tuning change. The port is a skeleton, so nothing below proposes polishing something
that is about to be replaced — but several items are things being *thrown away* or *ported* that
the plan has not noticed.

---

## The headline

**Three of the top four findings are the same failure in three places: content that is authored,
priced, documented and tested, and does nothing in the engine the game is being ported to.** That
is this project's signature failure mode — it happened to control moves, to team buffs, to
defensive moves, to the 18 field moves, and it has now happened to the *species identity layer*
and to the *care loop*. The pattern is not bad luck. It is what happens when a second engine is
built beside the first and the difference is never enumerated.

**§1 is the enumeration that was never done.**

---

## 1. ⚠️ THE SHIPPING GAME AND THE MEASURED GAME ARE TWO DIFFERENT SIMULATIONS

**What it is.** Every fight the player actually plays runs `battle.ts:simulateTeamBattle` — the
turn engine. Every balance measurement ever taken runs `tamerengine:simulateFieldBattle` — the
field engine. The Godot port is porting the field engine. `battle.ts` is marked RETIRE.

**Evidence.**

| caller | engine |
|---|---|
| `src/App.tsx:402, 1748, 1752, 1827, 2113` | `battle.ts:simulateTeamBattle` |
| `src/town.ts:1405, 2466, 2595, 2664` (cups, trials, rite, skirmish) | `battle.ts:simulateTeamBattle` |
| `tools/sweep40.ts:22`, `tools/ab.ts:17`, `tools/focus.ts`, `tools/comps.ts` consumers, +14 more | `tamerengine/engine.ts:simulateFieldBattle` |

The field engine is reachable from the running product **only through a URL query flag** —
`src/main.tsx:18-19`:

```ts
const Root = window.location.search.includes('arena3d') ? Arena3DPreview
  : window.location.search.includes('tamerarena') ? TamerArenaDemo : App
```

`src/tamerengine/types.ts:6-10` states it outright: *"This is a SECOND engine. `battle.ts`
(turn-based) is untouched and remains the shipping engine … The two run side by side until this
one is tuned well enough to take over."*

**Why it matters.** This is stated in the code and I do not think it is *hidden* — but its
consequence is not stated anywhere and it is severe:

- Every number in `docs/BALANCING.md`, every sweep, every A/B, `focus.ts`'s 0.711 top share, the
  damage tiers quoted in `CLAUDE.md` (STR 42.6 · DEX 38.2 · …) — **all of it describes an engine
  no player has ever played.**
- Conversely, `battle.ts`'s 12 goldens pin an engine that is being retired.
- The takeover has no plan, no date, and no acceptance test. It is not in `GODOT_MIGRATION.md` §7
  (Sequence) and it is not in `OUTSTANDING.md` §1.
- ⚠️ **And it is the reason §2 and §3 below went unnoticed.** Nobody diffed the two engines,
  because they were never expected to be the same thing at the same time.

**Proposed solution.** Two steps, and the first is nearly free.

1. **Write the engine-difference ledger** (~half a day). One table: for every mechanic in
   `battle.ts`, does `tamerengine` implement it, implement it differently, or not at all? §2 and
   §3 are the first two rows; I doubt they are the last two. This is the missing artefact.
2. **Decide the takeover** (a decision, not code). The honest options are (a) cut `battle.ts` over
   to `simulateFieldBattle` in the TypeScript build now, so the game the player plays is the game
   being measured and ported; (b) freeze `battle.ts` and accept that the TS build is a legacy
   artefact whose fights no longer inform anything; (c) leave it, and accept two engines through
   the whole port. **I recommend (b) explicitly stated**, given the port is live — but it must be
   *stated*, because right now (c) is happening by default and it is the most expensive one.

**Confidence.** High on the facts. Medium on the recommendation — (a) may be cheap or may drag the
whole spatial layer into the TS build, and I have not costed it.

---

## 2. ⚠️ THE ENTIRE SPECIES-IDENTITY AND CARE LAYER IS DEAD ON THE FIELD ENGINE

**What it is.** 130 innate abilities, the hidden wild-instinct system, battle fatigue, the
happiness→combat link, and seven per-stat combat perks all live in `battle.ts` and have **zero
references** in `src/tamerengine/`.

**Evidence.** `INNATE_EFFECTS` is declared at `src/battle.ts:87` and read at `battle.ts:288, 325`
and `validate.ts:255`. It appears nowhere in `src/tamerengine/`. I verified the authoring is
complete and healthy — so this is a wiring failure, not an authoring one:

```
species: 65   innate slots: 130   distinct innate names: 130
INNATE_EFFECTS keys: 130
innates with NO effect entry (pure flavour): 0
effect keys with NO species carrier (orphan): none
```

Grep counts, `battle.ts` vs the four field-engine files that could plausibly read them
(`engine.ts`, `damage.ts`, `decide.ts`, `tickMath.ts`):

| mechanic | `battle.ts` | `tamerengine` |
|---|---|---|
| `INNATE_EFFECTS` (130 species abilities) | 3 | **0** |
| `tameness` / `wildAction` (care → obedience) | 4 | **0** |
| `staminaDamageMult` (battle fatigue, −10%…−50%) | 3 | **0** |
| `happinessMultiplier` | 3 | **0** |
| `critChance` (DEX-derived, up to 20%) | 3 | **0** |
| `dodgeChance` (DEX-derived, up to 35%) | 3 | **0** |
| `echoChance` (INT — double-cast) | 3 | **0** |
| `mitigationPierce` (STR) | 2 | **0** |
| `debuffReduction` / `debuffBonus` (CHA) | 6 | **0** |
| `manaRegen` (WIS) | 4 | **0** |
| `hpRegen` (CON) | 22 | 9 (mods only, not the CON term) |

The field engine substitutes a **flat constant** where the turn engine derives from a stat:
`src/tamerengine/damage.ts:41` — `export const CRIT_CHANCE = 0.08`. Dodge exists only as
`dodgeMod`, a buff-sourced accuracy subtraction (`damage.ts:68`), never as a DEX derivation.

`tickMath.ts:90-98` regenerates mana as `wis / WIS_REGEN_DIVISOR`, i.e. its own formula, not
`monster.ts:677`'s `2 + WIS*0.01 + floor(WIS/50)`.

Field-engine reads off the `Monster` object, exhaustively (grep of `m.*` / `.m.*` across
`src/tamerengine/*.ts`): `hp, mp, loadout, name, seed, species, stats, tactics, className,
personality`. **`species` is read at exactly one site** — `personality.ts:77`, for the disposition
bias. `innate`, `activeInnate`, `innateUnlocked`, `tameness`, `stamina` are never read.

**Why it matters.** Three separate consequences, each large:

1. **`OUTSTANDING.md` §3.4 asks "is species identity *felt*, or is a monster just a stat block
   with a portrait?"** On the field engine the answer is now determinable and it is *stat block
   with a portrait*. Elements were removed on purpose (`CLAUDE.md`) — a good call — but innates
   were the *other* half of species identity, and on this engine they do nothing. What survives
   per-species is base stats, `trainingProfile` (a meta-game rate — see §8), and a personality
   bias. That is thin for 65 designed creatures and a `BESTIARY.md`.
2. **The care loop has no combat payoff.** Feeding, resting, happiness and stamina are the weekly
   tick's entire moment-to-moment content (`game.ts:applyWeek`). On the field engine, none of them
   touch a fight. `game.ts:506-509` even documents the intent — *"a well-kept monster obeys
   perfectly … HIDDEN — never shown in any UI, only felt"* — and on the engine being ported it is
   not felt either.
3. **`INNATE_SECONDARY_LEVEL` (300) is a dead progression beat.** The second innate unlocking is
   surfaced in the Ranch UI and means nothing in the field fight.

**Proposed solution.**

- **Innates: port the effect table, not the plumbing** (medium, ~2–4 days). `INNATE_EFFECTS` is a
  flat data record keyed by name. It belongs beside `moves.ts` in `data.json` (exported, not
  transcribed — same rule the migration already applies to moves and statuses,
  `GODOT_MIGRATION.md`), with a hook in the field engine's strike and tick paths. ⚠️ **And it
  needs a contract axis and a name-key guard** — `OUTSTANDING.md` §2.5 already flags that innates
  are keyed by ability NAME with nothing enforcing it; my probe shows zero orphans *today*, which
  is exactly when a guard is cheap.
- **Stamina / happiness / tameness: a design decision before any code.** These are the
  meta-game's only mechanical channel into the fight. Either wire them into the field engine or
  delete them and replace the loop's payoff with something that does exist. **Do not port them
  silently.** ⚠️ This is a creative-director call, not mine.
- **The seven per-stat perks: decide deliberately.** The field engine has already replaced two of
  them with flat constants and no one wrote down that it was a decision. Either they are part of
  the design ("every stat does something extra") and must be ported, or the field engine's
  simplification is the design and `monster.ts:674-682` should be deleted.

**Confidence.** High that the code paths are absent. Medium on the innate port cost — I have not
read all 130 effects to see how many need engine hooks that do not exist yet.

---

## 3. ⚠️ `spreadStatus` (CONTAGION) IS BUILT AND SHIPPED ON FIVE POOL MOVES. FIVE DOCUMENTS SAY IT IS UNBUILT.

**What it is.** The one effect every roadmap lists as deliberately never built is fully
implemented in **both** engines and authored on five moves in the live pool.

**Evidence.** Implementation:

- Field engine: `src/tamerengine/engine.ts:1788-1807`, with `CONTAGION_RADIUS = 5.5`
  (`types.ts:800`) and a **per-target `rng()` draw** at `engine.ts:1802`.
- Turn engine: `src/battle.ts:1311-1322`, plus AI weighting at `battle.ts:754-757`.

Authoring — `grep -c spreadStatus src/moves.ts` → **5**:

| move | `moves.ts` | effect |
|---|---|---|
| Piercing Shot | :110 | poison → 1 target @ 20% |
| Plague Shot | :124 | poison → 2 targets @ 40% |
| Sonic Boom | :288 | confusion → 1 @ 30% |
| Lullaby | :289 | sleep → 1 @ 30% |
| Mass Hysteria | :291 | confusion → 2 @ 40% |

Documents that say the opposite:

| where | text |
|---|---|
| `CLAUDE.md` roadmap #4 | *"the one effect from P2 deliberately left unbuilt; sim it alone"* |
| `docs/OUTSTANDING.md` §1.4 | *"the one P2 effect left unbuilt"* |
| `docs/GODOT_MIGRATION.md` §8 | *"the one P2 effect left unbuilt. Sim it alone."* |
| `docs/SPATIAL_MODEL.md` §10 | *"designed specifically to punish clumping and is the one effect never built"* |
| `src/core.ts:206` | *"Gated: no pool move sets it, so the engine's rng order is untouched."* |
| `src/battle.ts:1317` | *"⚠️ Gated behind spreadStatus, which no pool move sets"* |

**Why it matters.**

- **It draws RNG.** `core.ts:206`'s guarantee that "the engine's rng order is untouched" is false
  and has been since these moves were authored. Any golden or measurement that ran a fight
  containing one of those five moves consumed a different rng stream than the docs assume.
- ⚠️ **It is in NO contract.** The 23 axes in `combat.json` and the 8 in `status.json` (I listed
  them) contain nothing for contagion. **A Godot port written against the contract would omit
  contagion entirely, and every contract case would still pass.** That is the exact shape of
  failure the contract exists to prevent.
- `SPATIAL_MODEL.md` §10 leans on contagion being unbuilt as part of the argument for a cohesion
  axis ("all three answer a question the deployment never asks"). The argument survives; the
  evidence for it needs restating.

**Proposed solution** (small, ~half a day).

1. Correct the six sources above. `core.ts:206` and `battle.ts:1317` are load-bearing comments,
   not prose — fix those first.
2. **Add a contagion axis to the status contract.** It is pure sequencing over resolved inputs
   (carried status, target list, distances, draws) — exactly the shape `status.json` already
   handles. This is the cheapest guard in this document.
3. Move the roadmap entry from "unbuilt" to "built, never measured alone" — which is a genuinely
   different piece of work and is still worth doing once there is a baseline.

**Confidence.** Very high. Reproduced by direct grep of implementation, authoring and the contract
axis lists.

---

## 4. ⚠️ PER-UNIT MOVEMENT SPEED EXISTS AND IS DEX-DERIVED. A DOCUMENT WRITTEN YESTERDAY SAYS IT DOES NOT EXIST, AND CALLS DEX "BACKWARDS".

**What it is.** `docs/ENGAGEMENT_DESIGN.md` (committed `a7ae268`, 2026-08-03) proposes adding a
speed mechanic across five design options and rejects the DEX option on principle. The mechanic is
already live and is already DEX-derived.

**Evidence.** `src/tamerengine/engine.ts:198`:

```ts
speed: 2.4 + (m.stats.DEX / 1000) * 3.6,
```

At DEX 0 → 2.4 units/s; at DEX 1000 → 6.0. **A 2.5× spread**, the widest single derived stat
effect in the field engine. The comment two lines up says so: *"DEX drives how fast it crosses the
field — the stat finally has a spatial meaning beyond initiative."*

`ENGAGEMENT_DESIGN.md` §1: *"**Per-unit movement speed** | ❌ **DOES NOT EXIST.** Speed is global
with multipliers"* and *"⚠️ SO 'MAKE MELEE UNITS NATURALLY FASTER' IS A NEW MECHANIC, NOT A TUNING
CHANGE."* §6b: *"**DEX** — the obvious pick and ⚠️ **backwards**: DEX is the archer and rogue stat,
so deriving speed from it makes the units that want distance the best at keeping it."*

A second instance in the same family — `SPATIAL_MODEL.md` §11.3 lists *"**A leash.** ⚠️ Even with
cover breaks, something must stop a unit crossing the whole board"* as a requirement. It exists:
`src/tamerengine/types.ts:73`, `LEASH_RADIUS = 12`, *"No unit may aim to stand more than this far
from the fight's centre of mass."*

**Why it matters.**

- The recommendation in `ENGAGEMENT_DESIGN.md` §6 is **6e: `CLASS_SPEED[class] × BODY_SPEED[body]`**
  — two new tables. Landed as written, that either replaces or multiplies against a live DEX term,
  and nobody would be expecting the interaction. This is a design decision about to be made on a
  false premise.
- ⚠️ **More interesting: the doc's objection may be correct and the code may be the bug.** The doc
  argues DEX-speed makes archers best at keeping distance. That is exactly what
  `SPATIAL_MODEL.md` §11 and `ENGAGEMENT_DESIGN.md` describe as the kiting problem. **The
  measurement was never taken because nobody knew the term was there.** DEX is also the initiative
  stat (`battle.ts` turn order) and the dodge stat and the crit stat in the turn engine — it may
  simply be doing too much.
- The `docs/` tree is now the primary design record for a rebuild. Two documents in three days
  asserting a mechanic is absent when it is present is a *process* signal, not just two errors.

**Proposed solution.**

1. **Correct both documents today** (~1 hour). Re-open §6 with the real starting position: *speed
   exists, it is `2.4 + DEX/1000 × 3.6`, and the question is whether to replace it.*
2. **Take the measurement that was skipped** (~1 hour, uses an instrument that exists). Run
   `tools/ab.ts` with the DEX coefficient at `3.6` vs `0` — a paired A/B, sign test, exactly the
   project's standing method. That answers "is DEX-speed the kiting problem" with a number.
   ⚠️ **This is a structural question, not a tuning one**, so per the standing rule it is legitimate
   with the baseline suspended.
3. **Add a "does this already exist?" grep step to the design-doc workflow.** The three misses
   here (speed, leash, contagion) were all one `grep` away.

**Confidence.** Very high on the code. High that this changes the §6 recommendation; I have not run
the A/B, so I make no claim about which way it goes.

---

## 5. `FIELD_W` / `FIELD_H` ARE MUTABLE MODULE GLOBALS, AND THE PORT PLAN MAKES ARENAS MUCH LARGER

**What it is.** The field engine's dimensions are `export let`, set by a side-effecting global
setter. The engine's own header claims it is a pure function of (monsters + placement + obstacles
+ seed). It is not — it is also a function of module state.

**Evidence.** `src/tamerengine/types.ts:29-38`:

```ts
export let FIELD_W = 40
export let FIELD_H = 22
export function setFieldSize(w: number, h: number): [number, number] { ... }
```

The file documents the trade honestly (`types.ts:24-28`): *"this is MUTABLE GLOBAL STATE. It is
safe only because the engine is synchronous and single-threaded … Do NOT interleave battles at
different sizes."* Against `engine.ts:3-7`: *"DETERMINISM IS THE CONTRACT … a pure function of
(monsters + placement + obstacles + seed)."*

`tools/sweep40.ts:29-34` reads `FIELD_W`/`FIELD_H` directly and places its obstacles as fractions
of them. `ENGAGEMENT_DESIGN.md` §4 already caught the consequence: *"an art decision silently
became a balance input that nobody was reviewing as one."*

**Why it matters.**

- **`SPATIAL_MODEL.md` decision 3 is "ARENAS GET MUCH LARGER".** The moment arena size is a real
  variable rather than a constant, this pattern is the thing that breaks. `SPATIAL_MODEL.md` §11.4
  specifically proposes *"scale the current field 2× and 4× and run `sweep40`"* — that measurement
  runs through `setFieldSize`, and any leaked restore makes the following fights silently wrong.
- **It forecloses parallelism.** Godot's harness will want to run fights concurrently to keep a
  sweep under the current 2s (see §7). Mutable module state means it cannot.
- **It is the one piece of architecture the port must not copy.** GDScript has the same hazard
  (autoload singletons) and it is easier to reach for there, not harder.

**Proposed solution** (medium, ~1 day in TS; ~free if done at the start of the Godot rebuild).
Thread the arena bounds through `FieldSetup` — the struct already carries `obstacles` and
`placeA`/`placeB`, so bounds belong beside them. In Godot, the arena *node* owns its bounds and the
sim reads them off the setup resource; **no autoload for anything the sim reads.** Write that down
as the port's first architectural rule.

**Confidence.** High. The hazard is documented in the file itself; what is new here is that the
"much larger arenas" decision converts a tolerable wart into a live risk.

---

## 6. PERSONALITY: A LIVE, INVISIBLE SYSTEM THAT SILENTLY DILUTES THE PLAYER'S ORDERS

**What it is.** `src/tamerengine/personality.ts` (173 lines) gives every monster six hidden 0–100
axes and makes the player's tactics a *negotiation* rather than an instruction. It is undocumented
in `CLAUDE.md` and invisible in every UI.

**Evidence.** `personality.ts:111-115`:

```ts
export function coachedValue(innate01, coached01, temperament) {
  if (coached01 === undefined) return innate01
  const obey = clamp(temperament) / 100
  return innate01 * (1 - obey) + coached01 * obey
}
```

`temperament` comes from `basePersonality(seed, species)` — a hash of the monster's seed plus a
derivation off species base stats (`personality.ts:32-49, 56-70`). It drives `panicThreshold`
(:118), `executionQuality` (:127 — *"how reliably it picks its BEST available move"*),
`threatRadius` (:152) and `spendAbove` (:160), all consumed in `decide.ts:478-480` and
`engine.ts:22`.

`grep -il personality CLAUDE.md docs/*.md` returns `ABILITY_REWORK.md`,
`COLLABORATIVE-DESIGN-PRINCIPLE.md`, `LOOP_DESIGN.md`, `TAMERENGINE.md` — **not `CLAUDE.md`, not
`OUTSTANDING.md`, not `SPATIAL_MODEL.md`, not `TACTICS_BRAINSTORM.md`, not `GODOT_MIGRATION.md`.**
Every `personality` hit in `App.tsx` (:682, :1920, :2928, :2931) and `town.ts` (:1106, :2267) is
the **rival's** `RivalPersonality` — a different, unrelated type in `core.ts:894`. The monster's
own `Personality` (`core.ts:429`) is surfaced nowhere.

**Why it matters.** ⚠️ **It sits directly across the project's newest and firmest design bar.**
`OUTSTANDING.md` §3.3: *"The player never intervenes … If orders are the whole input, every order
must be predictable, visible and diagnosable."* Measured against that bar:

- An order is applied at strength `temperament/100`. A low-temperament monster ignores most of what
  the player asked for.
- The number is invisible, unnamed in the UI, and derived from a seed hash the player cannot see or
  influence.
- `executionQuality` means the same monster also picks worse moves, invisibly.
- So a player whose plan fails cannot tell whether the plan was wrong or the monster ignored it.
  `battleReport.ts:analyzeBattle` reads the tactics, not the coached values, so the report cannot
  tell them either.

I want to be careful here: **this may be a good design.** *"Coaching becomes a negotiation with a
creature, not a switch"* (`personality.ts:6-7`) is a real and appealing idea for a monster-taming
game, and it is a genuine answer to "do 65 species earn their keep". The problem is not the
mechanic — it is that it is **hidden, undocumented, and in direct tension with a bar set later**,
and nobody is currently choosing between them.

**Proposed solution.**

1. **Document it in `CLAUDE.md`** (~1 hour). It is a first-class combat system and the guide does
   not mention it. This is the smallest and most valuable item in this document.
2. **Escalate the design question to the creative director**: *is personality a visible stat the
   player breeds and trains toward, or a hidden texture?* The no-intervention bar pushes hard
   toward visible. It also makes personality a natural fit for the meta-game vision already
   confirmed in `OUTSTANDING.md` §3.6 — *"breeding the right monsters to have the correct tactics
   and skills"*.
3. **Whichever way it goes, `analyzeBattle` should report the coached value, not the ordered one.**
   Otherwise the diagnostic layer lies.

**Confidence.** High on the code and the invisibility. **This is a design conflict I am surfacing,
not a bug I am asserting** — the call is not mine.

---

## 7. THE HARNESS COSTS 2.0 SECONDS FOR 40 FIGHTS. A PHYSICS-BASED GODOT SIM HAS TO MATCH THAT.

**What it is.** `SPATIAL_MODEL.md` §0 correctly identifies "the harness must keep running headless
and fast" as the thing that must not slip, and asks for a spike. Here is the number the spike has
to beat.

**Evidence.** Measured just now, cold, on the dev machine:

```
$ time npx tsx tools/sweep40.ts
...
real    0m2.054s
```

40 fights, ten compositions, including TypeScript compilation. Per-fight budget: **~50 ms**, and
much of the 2.0s is `tsx` startup, so the true simulation cost is lower still.

The current tick budget: `TICK_HZ = 10` (`types.ts:44`), `MAX_SECONDS = 300`, so `MAX_TICKS = 3000`
(`types.ts:62`). Typical fights run 20–45 s of sim time (the sweep output above), i.e. 200–450
ticks, 5–10 units.

**Why it matters.** `SPATIAL_MODEL.md` §0 has already committed to **physics-driven, fixed-step,
single-threaded (option C+)**. That decision is defensible, but it converts a 50 ms fight into
however long Godot takes to step a Jolt world 300–450 times with 10 bodies, plus navmesh queries,
plus cover raycasts. §4.2 of the same document budgets *"5 units × 5 enemies × 5 rays = 125
raycasts per evaluation"* on the decision cadence (`RETARGET_EVERY = 0.6 s`) — that is ~75
evaluations per fight, ~9,400 raycasts per fight, ~375,000 per sweep.

If a sweep goes from 2 seconds to 20 minutes, the instrument does not get slower — **it stops being
used**, which is how this project has previously lost measurements (`sweep40.ts:1-9` exists because
a 12-fight sweep's noise band was too wide to trust).

**Proposed solution** (small, ~half a day, and it should happen *before* the spatial build starts).

Run the spike `SPATIAL_MODEL.md` §0 already asks for, but with a **pass/fail number attached**:

- Headless Godot, 10 `CharacterBody3D`s on a baked navmesh, `_physics_process` at 10 Hz, 450 ticks,
  125 `ShapeCast3D` queries every 6 ticks. Time it.
- **Budget: ≤ 250 ms per fight** (5× today's, 10 s for a 40-fight sweep). That is generous and
  still keeps the instrument in the "run it before you believe yourself" band the balancing rule
  depends on.
- If it misses: the fallback is *sim without physics integration for the harness* — Godot's
  navigation queries are pure functions and can run without a physics world. That is option A from
  §0, kept in the back pocket as a **harness-only** mode rather than a reversal of the design.

⚠️ **And record the engine version with the result.** `SPATIAL_MODEL.md` already flags that a
4.7 → 4.8 bump can change solver behaviour; a perf number without a version is not reproducible
either.

**Confidence.** High on the measurement. **I have not run the Godot spike** — the 250 ms budget is
my proposal, not a measured feasibility claim.

---

## 8. THE META-GAME: 26 OF 65 SPECIES HAVE NO TRAINING MAJOR AND NO FLAW

**What it is.** `CLAUDE.md` states *"All 65 species now author a profile — the legacy stat-derived
fallback in `game.ts:trainingProfileFor()` is still there as a safety net … but nothing currently
reaches it."* The first half is true only in the sense that the *field exists*. 26 species author
`trainingProfile: {}` — an empty object — which is truthy, so it takes the authored branch and
yields a profile with **no major and no flaw**.

**Evidence.** `src/game.ts:165-171`:

```ts
export function trainingProfileFor(species: Species): TrainingProfile {
  if (species.trainingProfile) {
    return { minor: BODY_MINOR[species.body], ...species.trainingProfile } as TrainingProfile
  }
  ...
}
```

`{}` passes `if (species.trainingProfile)`. Measured across all 65:

```
no trainingProfile field at all (hits legacy fallback): 0
trainingProfile present but EMPTY {} (no major, no flaw): 26
no major authored: 26        no flaw authored: 33
 Kongrath:  profile={"minor":"STR"}  bonuses= STR:1.1 DEX:1 CON:1 WIS:1 INT:1 CHA:1
 Corvaan:   profile={"minor":"WIS"}  bonuses= STR:1 DEX:1 CON:1 WIS:1.1 INT:1 CHA:1
 Quokkade:  profile={"minor":"CHA"}  bonuses= STR:1 DEX:1 CON:1 WIS:1 INT:1 CHA:1.1
```

The 26 break into two clean groups:

| group | species | likely intent |
|---|---|---|
| **All 20 fusion species** — Saurian ×5, Tempestine ×5, Broodkin ×5, Primeval ×5 | Grendscale…Worldsong | ✅ **Almost certainly correct.** `CLAUDE.md` and `FUSION_DESIGN.md` say fusion aptitude is per-MONSTER (`bonusMajor1/2` inherited from parents), not per-species. |
| **Exactly one per base body type** — Kongrath (Mammal), Corvaan (Avian), Quokkade (Marsupial), Maelurk (Aquatic), Scarabrute (Insectoid), Geckari (Reptilian) | 6 species | ⚠️ **Looks like a skipped authoring pass.** One per body, six for six, is not a pattern intent produces. |

**Why it matters.**

- Those six species have **no MAJOR and no FLAW** — the only per-species mechanical differentiator
  the meta-game owns. Combined with §2 (innates dead on the field engine) and elements removed,
  Kongrath and Corvaan are distinguishable from other Mammals/Avians by base stats and a portrait
  and nothing else.
- ⚠️ **`validate.ts` does not catch it.** An empty-object profile is structurally valid. This is
  the same shape as every prior failure in this project: authored-looking content that is inert.
- The prose in `CLAUDE.md` is wrong in a way that would survive a reading of the code, because the
  fallback genuinely is unreached — the claim it supports just is not the claim that matters.

**Proposed solution** (small).

1. **Add a `validate.ts` tripwire** (~1 hour): a non-fusion species must author a `major`. Make
   fusion bodies the explicit exemption, so the rule states the design instead of hiding it.
2. **Author the six missing profiles** — a design task, not an engineering one; hand it to whoever
   owns `BESTIARY.md`. ⚠️ Do this *after* the tripwire, so the tripwire is proven to fail first
   (`GODOT_MIGRATION.md`'s own standard: *"the harness was proven to fail before it was trusted"*).
3. **Correct the `CLAUDE.md` sentence** to say what is true: 45 of 65 author a major; the 20 fusion
   bodies carry theirs per-monster.

**Confidence.** Very high on the measurement. **Medium on the intent split** — the fusion exemption
is inferred from `FUSION_DESIGN.md` and the per-monster `bonusMajor1/2` fields in `game.ts:116-121`;
someone who authored those 26 should confirm the six base-body ones are an oversight rather than a
deliberate "no strong aptitude" design.

---

## 9. THE PLAYER PICKS 3 ABILITIES OF A 5-SLOT FIELD KIT, AND CHOOSES NEITHER OF THE OTHER TWO

**What it is.** The ability-selection UI and the persisted career loadout are 3 slots. The field
engine fights with 4 drafted slots plus 1 granted movement ability. The extra two are chosen by
code the player cannot see or influence.

**Evidence.** `src/game.ts:99` — `loadout: string[] // persisted equipped-move ids (≤3)`.
`careerMonster` (`game.ts:482`) calls `chooseLoadout(learned, c.stats)` with `size` defaulting to 3
(`monster.ts:253`). `FIELD_LOADOUT_SIZE = 4` (`types.ts:791`). `engine.ts:146-177`:

```ts
if (m.loadout.length < 3 || m.loadout.length >= FIELD_LOADOUT_SIZE) return m.loadout
const extra = chooseLoadout(learnedMoves(m.stats), m.stats, FIELD_LOADOUT_SIZE)...
const mover = movementMoveFor(topStat(m.stats))
return [...drafted, ...granted]      // 4 + 1
```

The movement ability is **granted, not drafted**, and is chosen solely by the monster's single
highest stat (`engine.ts:141-144, 173-175`). The comment says so and flags the trade:
*"it is universal rather than a build choice — worth revisiting once the escape tier is proven, but
reachability first."*

**Why it matters.** This is a straightforward consequence of §1 (two engines, two slot counts) and
it lands squarely on the no-intervention bar. If loadout is one of only two inputs the player has —
orders and kit — then 40% of the kit being chosen for them is a real dilution of the only agency in
the game. The 4th slot in particular is *the best remaining damage move*, i.e. the pick most likely
to change how a fight reads.

Note the movement grant is a **good** decision made for a good reason (it is the fix that made 18
authored field moves reachable at all). The problem is only that it is invisible.

**Proposed solution** (part of the Godot UI rebuild, so near-free if scheduled now, expensive if
retrofitted). Make the field kit the *authored* kit: 4 player-chosen slots plus a **visible**
movement slot the player picks from what the monster has trained into. The data already supports it
— `ALL_FIELD_MOVES` has 18 entries gated by `learnLevel` (`engine.ts:174`). ⚠️ **Do not ship the
Godot ability screen at 3 slots**; that is the retrofit.

**Confidence.** High on the mechanism. Medium on the severity — 4 vs 5 visible slots may be a fine
answer; what is not fine is it being an accident of two engines disagreeing.

---

## 10. WHAT CAN BREAK WITH NOTHING FAILING — the instrument gaps

Collected, since each is small on its own.

| gap | evidence | consequence | fix |
|---|---|---|---|
| **Contagion is in no contract** | 23 `combat.json` axes + 8 `status.json` axes, none for `spreadStatus`; implementation at `engine.ts:1788` | a Godot port omits it and passes 173/173 | add a `contagion` axis to `status.json` (~2 h) — **the highest value-per-hour item in this document** |
| **Innates are in no contract and keyed by NAME** | `INNATE_EFFECTS` at `battle.ts:87`; already flagged in `OUTSTANDING.md` §2.5 | rename in `species.ts` silently detaches the effect; port omits all 130 | name-key guard in `validate.ts` (~1 h) + contract axis when §2 is resolved |
| **`trainingProfile: {}` is structurally valid** | §8 | 26 species author nothing and validate clean | `validate.ts` rule (~1 h) |
| **Field engine has no test that the two engines agree on anything** | §1 | every divergence in §2 accumulated silently | not worth building — supersede with the §1 ledger |
| **`SPATIAL_MOVES` name-keying** | `spatial.ts:1-20`, 54 keys | ⚠️ **I checked: 0 orphans today.** The trap is real, the drift has not happened yet | a guard now, while it is free (`validate.ts`, ~1 h) |
| **15 `team`-target moves carry no area shape** | measured: 15 of 42 `allEnemies`/`team` moves | ⚠️ probably fine — team buffs use `TEAM_AURA_RADIUS`, not geometry. **Flagging as unverified, not as a bug** | confirm during the spatial rebuild |

---

## What I checked and found HEALTHY

Recording these so they are not re-investigated, and because two of them answer open questions.

- **All 18 classes are reachable in natural generation.** `OUTSTANDING.md` §3.4 asks whether "a
  handful dominate because of how stats train". Measured over N=4,000 generated monsters at each of
  five training budgets (0 / 400 / 1200 / 2400 / 3600, cap 1100): **all 18 named classes plus
  Generalist appear at every budget above 0**; at train 0 only Herald is absent. The top five
  (Wizard, Sage, Rogue, Ranger, Warrior) hold **55%** at train 3600, and the rarest (Herald 0.8%,
  Shaman 1.9%, Spellsword 1.8%) are rare but real. Generalist is 3.8–5.0% at high training, matching
  `CLAUDE.md`'s ~3% claim closely enough. **This is not a crisis and does not need work.**
  ⚠️ Caveat: `tools/sweep40.ts` fights hand-built `teamTemplates.ts` compositions where five classes
  take 66% of appearances — that is a property of the *harness*, not the game.
- **Innate authoring is complete and consistent** — 130 slots, 130 distinct names, 130 effect
  entries, zero orphans in either direction. The problem in §2 is wiring, not content.
- **`SPATIAL_MOVES` has zero orphaned keys** across 54 entries.
- **No `Math.random`, `Date.now` or `performance.now` anywhere in the sim** —
  `src/tamerengine/*.ts`, `battle.ts`, `town.ts`, `game.ts`, `monster.ts`, `core.ts`. The
  determinism claim holds on that axis. (§5 is a separate axis.)
- **`applyWeek` / `previewWeekEffects` rng lock-step appears intact** — I read both
  (`game.ts:260-321` vs `549-651`) and the call orders match branch for branch, including the
  signature-awakening path which deliberately consumes no rng (`game.ts:642`).

---

## Suggested order

Ranked by (impact × likelihood ÷ cost), not by size.

| # | item | cost | why here |
|---|---|---|---|
| 1 | **Add the contagion contract axis** (§3, §10) | ~2 h | the port is live *now* and would omit a shipped mechanic while passing every test |
| 2 | **Correct the six documents** (§3, §4, §8) | ~2 h | `SPATIAL_MODEL.md`/`ENGAGEMENT_DESIGN.md` are the spec the rebuild is being written from |
| 3 | **Write the engine-difference ledger** (§1) | ~4 h | the missing artefact that would have caught §2 and §3 |
| 4 | **Document personality in `CLAUDE.md`, then escalate the design question** (§6) | ~1 h + a decision | a live combat system the guide does not mention, sitting across the newest design bar |
| 5 | **Three `validate.ts` tripwires** — innate names, `SPATIAL_MOVES` keys, empty `trainingProfile` (§8, §10) | ~3 h | all three are free today and expensive after drift |
| 6 | **The DEX-speed A/B** (§4) | ~1 h | may change the `ENGAGEMENT_DESIGN.md` §6 recommendation before it is built |
| 7 | **The Godot headless perf spike with a pass/fail budget** (§7) | ~4 h | must land before the spatial build, not after |
| 8 | **Decide the fate of innates / stamina / happiness on the field engine** (§2) | a decision, then days | the largest item, and it is a creative call first |
| 9 | **Thread field bounds through `FieldSetup`; no autoloads in the Godot sim** (§5) | ~1 day TS, free in Godot | write the rule down before the rebuild starts |
| 10 | **Do not ship the Godot ability screen at 3 slots** (§9) | free now | pure scheduling |

⚠️ **Items 1–6 are eleven hours of work and they are the whole top of this list.** That is not a
coincidence — the expensive findings in this document are expensive because they were allowed to
sit, and the cheap ones are cheap because they were caught while still cheap.
