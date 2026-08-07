# The doc map — what each document is for, and which ones disagree

**Compiled 2026-08-04, 13:00.** ~15 agents are writing in this repo concurrently; six documents
landed *while this file was being written* and are listed in §4. Treat the status column as
"true at 13:00 on 2026-08-04", not as permanent.

⚠️ **THE MOST VALUABLE PART OF THIS FILE IS §1, NOT §2.** The map is convenient; the
contradictions are load-bearing. Several documents now give opposite instructions on the same
question because decisions moved faster than the prose. **They are named, not smoothed over.**

⚠️ **AND THE PROJECT'S OWN FAILURE MODE APPLIES TO THIS FILE TOO.** `docs/OUTSTANDING.md` records
ten things found already built while being discussed as missing; `docs/ART_PIPELINE.md` warns that
a stale *"blocked"* status is the most expensive kind of stale documentation, because it stops the
next session from attempting something that now works. **Count files and grep before believing any
status below, including mine.**

---

## 1. The contradictions — read these before you read anything else

### 1.1 ⚠️ THE SPATIAL LAYER: "do not build it" vs. IT IS BUILT

| doc | says |
|---|---|
| `CLAUDE.md` (root) | *"Do not port what is being redesigned. Arenas, the spatial layer, the camera and target selection are all explicitly out."* |
| `GODOT_MIGRATION.md` decision 3 | *"Do NOT port the spatial layer."* |
| `SLICE_DECISIONS_2026-08-04.md` §4 | *"Decided: do NOT build the spatial layer, and say so plainly rather than faking it."* |
| `SPATIAL_HANDOFF.md` §0 | *"The user has directed that the game become a real simulation, so that rule is deliberately superseded."* |
| **the repo** | `spatial.gd` (240L) · `spatial_sim.gd` (907L) · `spatial_ai.gd` (363L) · `arena_layout.gd` (353L) — **1,863 lines, on disk, parsing clean** |

**Resolution: `SPATIAL_HANDOFF.md` §0 wins.** It is the newest and it records a direct user
instruction. `CLAUDE.md`, `GODOT_MIGRATION.md` and `SLICE_DECISIONS` §4 all still carry the
superseded rule in their own words, and none of them has been amended. ⚠️ **A reader who starts
from `CLAUDE.md` and stops there will follow a reversed rule.**

### 1.2 ⚠️ PATHFINDING IS BOTH FORBIDDEN AND A KEY FEATURE — inside ONE document

`AUTOBATTLER_DESIGN.md` contradicts itself, and it is the most authoritative document in the repo:

| location | says |
|---|---|
| §7 risk 2 | *"**No pathfinding is permitted (determinism)**, so a unit whose route is blocked must have a defined behaviour"* |
| §8 #21 | *"⚠️ **REAL PATHFINDING IS WANTED AND IS A KEY FEATURE.** Not local steering alone."* |
| §8 #22 | monsters path around static cover **and enemy bodies** |
| §8 #29 / §11 | determinism: *"decide after a spike"* — measure, don't assume |
| `SPATIAL_HANDOFF.md` §1 | **NO** `NavigationAgent3D` / `PhysicsDirectSpaceState` in the sim, flatly |

**Resolution: §8 supersedes §7 (later round of decisions), and §11's spike is the tie-breaker.**
⚠️ **I RAN THE SPIKE — see `docs/HANDOVER.md` §4. It passes.** `NavigationServer3D.map_get_path()`
reproduced byte-identically across two separate process invocations. The blocker on #21 is
therefore measured-away, but `SPATIAL_HANDOFF.md` §1's blanket ban is still written as absolute
and has not been amended.

### 1.3 ⚠️ `spatial_sim.gd` / `spatial_ai.gd`: JUST LANDED, ALREADY CONDEMNED

- `SPATIAL_QA.md` (2026-08-04) opens with *"`spatial_sim.gd` (stream A), `spatial_ai.gd` (stream B)
  and `arena_layout.gd` (stream C) **do not exist yet**."* — **false as of 13:00 today.** All three
  exist. The doc was stale within hours of being written. (Its harness `_spatial_test.gd` has since
  been updated and now reports the files as present, so the **harness is ahead of its own report.**)
- `AUTOBATTLER_DESIGN.md` §12 #32: *"⚠️ **`spatial_sim.gd` AND `spatial_ai.gd` are REWRITTEN FROM
  SCRATCH.** Not evolved."*

So 1,270 lines landed and are already scheduled for deletion. **Do not invest in them, do not fix
them, and do not treat their behaviour as design intent.** `arena_layout.gd` and `spatial.gd` are
*not* on the rewrite list.

### 1.4 ⚠️ THE FRAME-STREAM CONTRACT IS "NON-NEGOTIABLE" AND ALSO SUPERSEDED

`SPATIAL_HANDOFF.md` opens *"Nothing here is negotiable without telling the coordinator"* and §3
specifies the sim→renderer frame stream in exact detail. `AUTOBATTLER_DESIGN.md` §12 #33 then says
*"the frame-stream contract is REDESIGNED too, not preserved... **The renderer is rewritten with
it**"*, adding `intent`, `reason` and `projectiles` per unit.

**Resolution: AUTOBATTLER §12 #33 wins** (later, and driven by the legibility requirement in its
§6). `SPATIAL_HANDOFF.md` §3 is now a *description of the shape that exists*, not the target.

### 1.5 ⚠️ TWO TACTICS VOCABULARIES, AND ONE DOC FORBIDS THE SECOND

`SPATIAL_HANDOFF.md` §4B: AI *"must honour the existing `tactics.gd` vocabulary
(`targetPriority`, `temperament`, `manaPolicy`, `formation`) — **do NOT invent a second one**."*

`AUTOBATTLER_DESIGN.md` §2 then defines a different four-axis vocabulary:

| built (`tactics.gd`, live) | designed (`AUTOBATTLER_DESIGN.md` §2) |
|---|---|
| `targetPriority`: casters / tanks / manmark | `targetPriority`: nearest / weakest / casters / tanks / marked / threat **+ commitment** (sticky/reassess) |
| `temperament`: aggressive / balanced / cautious | **`positional intent`**: push / hold / wings / dive / guard |
| `formation`: tight / loose (team-only) | **free-form saved named formations** |
| `manaPolicy`: normal / conserve | **`when hurt`** + **`ability policy`** |

These are not a superset — `temperament` and `manaPolicy` have no direct successor, and
`positional intent` has no predecessor. **AUTOBATTLER wins** (newest, and settled with the user),
but the migration from one vocabulary to the other is unplanned work nobody has costed.
`docs/TACTICS_TREES.md` (landed 2026-08-04) is the first document to implement the new one.

### 1.6 ⚠️ CLASSES: 18 EMERGENT (BUILT) vs 30 ASSIGNABLE (DESIGNED)

| source | claim | status |
|---|---|---|
| `data.json` / `classify.json` | **18 classes**, derived from the two highest current stats | **BUILT, and pinned by 46 contract cases** — verified passing today |
| `CLASS_REWORK.md` | classes become **assignable**, stat-gated, with per-class caps | proposal, unbuilt |
| `DOCTRINES_AND_CLASSES.md` | **30 classes, 10 roles** | proposal, unbuilt |
| `CLASS_BUILD_PLAN.md` (landed today) | the two above turned into a build plan | plan, unbuilt |
| `AUTOBATTLER_DESIGN.md` #12, #24, #35 | adopts assignable classes; **"lands right after the tree AI"** | decided, unbuilt |

⚠️ **AND THE 30-CLASS CHANGE QUIETLY INVALIDATES THE SLICE'S ROSTER ARGUMENT.**
`SLICE_DECISIONS_2026-08-04.md` §1 justifies shipping twelve creatures on the grounds that
*"class is emergent from a monster's two highest CURRENT stats... so twelve species still reach
most of the eighteen classes through training. A small roster costs variety of silhouette, not
variety of play."* Under **assignable** classes that reasoning no longer holds in the same form.
Nobody has re-argued the roster size against the new model.

### 1.7 ⚠️ SPEED: DEX-DERIVED (BUILT) vs ITS OWN STAT (DECIDED), WITH A MEASUREMENT SAYING BE CAREFUL

- `spatial.gd:speed_of(dex)` is live: `SPEED_MIN 2.4` → `SPEED_MAX 6.0` across DEX 0–1000.
- `AUTOBATTLER_DESIGN.md` #19 / #23: **Speed becomes its own 0–100 stat.**
- `ENGAGEMENT_DESIGN.md` and `DECISIONS_2026-08-03.md` open-q5 both record the *measurement* that
  speed is **not** the lever that fixes kiting — *"a chase NEVER resolves... regardless of field
  size or speed (both measured, both invariant)"*.
- `AUTOBATTLER_DESIGN.md` §4 correctly carries that warning forward: a Speed stat is fine as a
  design axis, *"it must never be used to solve kiting"*, and `BACKPEDAL_MULT` stays.

Not a contradiction — a live unbuilt change with a guard attached. **Named here because the guard
is easy to lose in a refactor**, and `spatial.gd`'s comment on `BACKPEDAL_MULT` is currently the
only place in the Godot tree that carries it.

### 1.8 ⚠️ `OUTSTANDING.md` §1.2 IS THE MOST DANGEROUS STALE SECTION IN THE REPO

It says, in full: *"Everything in `monster-tamer/` is headless arithmetic. **Nothing renders.** No
battle scene, no unit node, no camera, no arena, no sprites, no UI, no input, no audio... No
save/load. No meta-game."*

**Every clause of that is now false** except audio. Verified today: 9 `.tscn` scenes, 8 UI scripts
(3,000+ lines), `save_game.gd`, `career.gd`, `roster.gd`, 19 creature PNGs, 65 portraits, 30 battle
sprites, 5 painted leagues, 41 ground textures. This is exactly the *"stale 'blocked' status"*
failure `ART_PIPELINE.md` warns about. The rest of `OUTSTANDING.md` is still good.

### 1.9 ⚠️ `PATHFINDING_DESIGN.md` SAYS "SHIPPED" ABOUT A DIFFERENT ENGINE

Its header reads *"Status: Stage 4a (instruments), **Stage 0 and Stage 1 SHIPPED**"*. That is true
of the **TypeScript** `src/tamerengine/` and false of Godot, where **no pathfinding of any kind
exists.** The document never says which engine in its header. A reader arriving from
`AUTOBATTLER_DESIGN.md` #21 ("real pathfinding is wanted") will read "shipped" and conclude the
work is done. It is not.

### 1.10 The art documents disagree about how many tiers and how many frames

| doc | says |
|---|---|
| `ART_THEME.md` | three-tier rendering system, 65 species |
| `BATTLE_SPRITES.md` | **6 frames × 65 species = 390** battle sprites |
| `SLICE_DECISIONS` §3 | **one** pose per creature, animated in code — *"a real quality reduction... being taken deliberately"* |
| `ART_BIBLE_GUILD_COLOURS.md` | the slice *"compresses `ART_THEME.md`'s three-tier rendering system into two tiers"* — self-aware, and the correct reading |
| `ART_PRODUCTION.md` §0 | declares itself the corrected numbers where it disagrees with `ART_THEME.md` / `ART_PIPELINE.md` |

**Resolution: `ART_BIBLE_GUILD_COLOURS.md` for the slice, `ART_THEME.md` for the destination.**
Not really a conflict — but three documents give three different sprite counts and only one of
them says which scope it applies to.

### 1.11 Roster size: 12 decided, 12 wired, 19 on disk

`SLICE_DECISIONS` §1 decides twelve creatures. `art.gd:ROSTER` lists exactly those twelve.
**`assets/creatures/` holds 19 PNGs** — `arachnyx`, `balaenix`, `bruxaroo`, `iguanor`, `nautilux`,
`pinguox`, `tazzik`, `ursath` are generated and **not referenced by any code**. The art stream has
outrun the roster constant. Harmless today; a trap if someone counts files and concludes the
roster is 19.

---

## 2. The map

Statuses: **CURRENT** (trust it) · **CURRENT ⚠️** (trust it except a named part) ·
**SUPERSEDED** (a newer doc overrides it) · **HISTORICAL** (describes a past state; keep for the
findings, don't act on it) · **GENERATED** (never hand-edit) · **NOT-OURS** (template tooling).

### 2.1 Start here

| doc | status | for |
|---|---|---|
| `HANDOVER.md` | CURRENT | **read first.** Where the build is, verified by running it |
| `DOC_MAP.md` | CURRENT | this file — what to read and which docs fight |
| `CLAUDE.md` (root) | CURRENT ⚠️ | vision, standing rules, file map. ⚠️ **its spatial-layer rule is REVERSED — see §1.1** |
| `docs/CLAUDE.md` | CURRENT | docs-directory standards. Correctly states there are no ADRs |

### 2.2 The settled design of the game being built

| doc | status | for |
|---|---|---|
| `AUTOBATTLER_DESIGN.md` | **CURRENT — most authoritative** | the AI, tactics, personality, speed, modes, build order. ⚠️ Self-contradicts on pathfinding (§1.2); **nothing in it is built** |
| `SPATIAL_HANDOFF.md` | CURRENT ⚠️ | the interface contract between the 7 spatial streams. ⚠️ §3 superseded (§1.4), §4B superseded (§1.5) |
| `ARENA_BLUEPRINT.md` | CURRENT | ground/venue sizes, deploy separation, SPREAD/leash. **Implemented in `spatial.gd`** — the one design doc with a direct code counterpart |
| `SPATIAL_MODEL.md` | CURRENT | the six spatial layers; determinism as the shaping constraint |
| `SPATIAL_COMBAT_DESIGN.md` | CURRENT | reach, graded cover, flanking. Implemented in `spatial.gd` |
| `ENGAGEMENT_DESIGN.md` | CURRENT | the chase problem. ⚠️ **Carries the measurement that speed does not fix kiting** — do not lose it |
| `ARENA_DESIGN.md` | CURRENT | arena theory: the density law, 180° symmetry, what cover is for. Implemented in `arena_layout.gd` |
| `DECISIONS_2026-08-03.md` | CURRENT ⚠️ | the studio-review decision record. Partly overtaken by `SLICE_DECISIONS` and `AUTOBATTLER_DESIGN` |
| `SLICE_DECISIONS_2026-08-04.md` | CURRENT ⚠️ | the vertical-slice calls. ⚠️ **§4 reversed the same day (§1.1); §1's roster argument undermined (§1.6)** |
| `MECHANICS_REWORK.md` | CURRENT | what a large field needs mechanically. Carries a correction at the top — read it |
| `GAME_MODES.md` *(new)* | CURRENT | the pluggable mode seam (AUTOBATTLER #2) |
| `TACTICS_TREES.md` *(new)* | CURRENT | tactics → behaviour-tree subtrees. The first build spec for the §2 vocabulary |
| `UX_DEPLOYMENT.md` *(new)* | CURRENT, unreviewed | free-placement + saved formations UX. Self-labelled *"not yet reviewed"* |

### 2.3 Designed, not built — the proposal shelf

| doc | status | for |
|---|---|---|
| `CLASS_REWORK.md` | CURRENT proposal | assignable classes, stat gate, per-class caps |
| `DOCTRINES_AND_CLASSES.md` | CURRENT proposal | 10 roles, 30 classes, derived from line data |
| `CLASS_BUILD_PLAN.md` *(new)* | CURRENT plan | the two above made shovel-ready |
| `INNATES_ON_FIELD.md` | CURRENT | the 31 innate effect kinds + port status. ⚠️ 130 effects **are** in `data.json` (verified); no field engine reads them |
| `META_GAME_DISPOSITION.md` | CURRENT plan | `town.ts`/`game.ts`/`monster.ts` scored against the 3D-ranch model. Explicitly authorises nothing |
| `FUN_ADDITIONS.md` | CURRENT proposal | explicitly *"not a spec and not a decision"* |
| `FUSION_DESIGN.md` | CURRENT draft | breeding + fusion, meta-game, deferred |
| `TACTICS_BRAINSTORM.md` | CURRENT ⚠️ | three-layer orders; the focus-fire architectural finding. ⚠️ Vocabulary superseded by AUTOBATTLER §2 |
| `TACTICS_DESIGN.md` | CURRENT ⚠️ | the *measured* diagnosis of the deployment problem. ⚠️ Its open question is **answered** by AUTOBATTLER #1 (free placement) |
| `TACTICS_DISCLOSURE.md` | SUPERSEDED | 2026-07-25 progressive-disclosure map, TS-side, unbuilt. AUTOBATTLER #17 re-decides the unlock model |
| `SPATIAL_BALANCE_TOOLING.md` *(new)* | CURRENT | how we will *measure* whether the tree AI fixes the blob. Ships no fix |
| `AUDIO_DIRECTION.md` *(new)* | CURRENT | first audio doc. ⚠️ **Zero audio exists** — no assets, no wiring |

### 2.4 Art

| doc | status | for |
|---|---|---|
| `ART_THEME.md` | CURRENT | Guild Colours — the approved identity and the destination |
| `ART_BIBLE_GUILD_COLOURS.md` | CURRENT | the operational spec binding the **12-species / 5-league slice actually shipping** |
| `ART_DIRECTION.md` | CURRENT | the battlefield's standing visual direction |
| `ART_PRODUCTION.md` | CURRENT | inventory, specs, prompts, order of work. Self-declared corrective over the two above on numbers |
| `ART_PIPELINE.md` | CURRENT | **how images actually get made.** ⚠️ Read before concluding art can't be generated |
| `CODEX_IMAGE_GEN.md` | CURRENT | the specific route this project uses. All 65 portraits + 18 backdrops came from it |
| `ARENA_DESIGN.md` | (see §2.2) | |
| `BATTLE_SPRITES.md` | CURRENT ⚠️ | the 6-frame set spec. ⚠️ **Not what the slice ships** (§1.10). 30 of 390 exist |
| `BESTIARY.md` | CURRENT | species canon. ⚠️ Load-bearing: *"a Tamer is a partner, not an owner"* is why the art is athletes, not warlords |

### 2.5 The TypeScript side — the thing still being retired

| doc | status | for |
|---|---|---|
| `GODOT_MIGRATION.md` | CURRENT ⚠️ | what ports / is rebuilt / is thrown away, with LOC. ⚠️ **Decision 3 reversed (§1.1)** |
| `TAMERENGINE.md` | HISTORICAL | the TS field engine's own notes. Reference for what is being replaced |
| `TECHNICAL_ISSUES.md` | CURRENT | the technical audit. TS-side, every claim sourced to a line |
| `OUTSTANDING.md` | CURRENT ⚠️ | unfinished / weak / unchecked. ⚠️ **§1.2 is wholly false (§1.8)**; §3 is the valuable part |
| `PATHFINDING_DESIGN.md` | HISTORICAL ⚠️ | TS pathfinding. ⚠️ **Its "SHIPPED" is about `tamerengine`, not Godot (§1.9)** |
| `ABILITY_REWORK.md` | CURRENT | the 141-move pool design. The pool rework is done |
| `ABILITY_BALANCE_REVIEW.md` | CURRENT | the pool at arena scale. Every spatial constant is a fixed absolute |
| `POOL_AUDIT.md` | CURRENT | `tools/pool.ts` calibration — 0 flags became 4 |
| `SIGNATURE_DESIGN.md` | HISTORICAL | audited against a **90-move** pool; the pool is now 141. Numbers predate the rework |
| `TACTICS.md` | HISTORICAL ⚠️ | the TS standing-orders audit. Superseded on vocabulary by AUTOBATTLER §2 |
| `BALANCING.md` | HISTORICAL ⚠️ | *"Numbers are current as of v0.74."* ⚠️ **THE BASELINE IS SUSPENDED — do not quote any figure in here** |
| `ECONOMY_FINDINGS.md` | HISTORICAL | v0.5 full-ladder bot playtest. Empirical and still interesting; the economy has moved |
| `LOOP_DESIGN.md` | HISTORICAL | the fun-loop phase plan. All 5 phases shipped in TS |
| `HANDOVER_area_consolidation.md` | HISTORICAL | a TS refactor, two attempts reverted. ⚠️ Likely moot — `battle.ts` is being retired |
| `GAME_DESIGN.md` | HISTORICAL | the original GDD. Browser-first, pixel-art, React. **Stale in most particulars** |
| `OUTLINE.md` | HISTORICAL | the original staged plan. React + PixiJS + Zustand. Superseded by `GODOT_MIGRATION.md` |
| `DEPLOY.md` | CURRENT (legacy only) | Cloudflare Pages deploy for the React app. Not a Godot target |

### 2.6 Generated, process, and not-ours

| doc | status | note |
|---|---|---|
| `ABILITIES.md` | **GENERATED** | `npx tsx tools/genabilities.ts`. **Never hand-edit** |
| `SPATIAL_QA.md` | CURRENT ⚠️ | stream-G findings. ⚠️ **Its "state of the fan-out" section is false (§1.3)**; defect **SQA-001 is still open and still real** |
| `COLLABORATIVE-DESIGN-PRINCIPLE.md` | CURRENT | the Question → Options → Decision → Draft → Approval protocol |
| `engine-reference/godot/VERSION.md` | CURRENT | ⚠️ check the binary, not the doc — the pin was 6 months behind once |
| `WORKFLOW-GUIDE.md` | **NOT-OURS** | 1,669 lines of CCGS agent-architecture template. Not about this game |
| `examples/*` | **NOT-OURS** | 10 template session transcripts |
| `architecture/tr-registry.yaml`, `registry/architecture.yaml` | **NOT IN USE** | `docs/CLAUDE.md` says so plainly. Do not create ADR stubs |

---

## 3. Supersession chains, in one place

```
CLAUDE.md "do not build the spatial layer"
   └─► SPATIAL_HANDOFF.md §0 (user reversal)          [the layer is BUILT]

GODOT_MIGRATION.md decision 3 (same rule)
   └─► SPATIAL_HANDOFF.md §0

SLICE_DECISIONS_2026-08-04.md §4 (same rule, same day)
   └─► SPATIAL_HANDOFF.md §0

SPATIAL_HANDOFF.md §3 (frame stream)
   └─► AUTOBATTLER_DESIGN.md §12 #33  (+ intent / reason / projectiles)

SPATIAL_HANDOFF.md §4B ("do not invent a second vocabulary")
   └─► AUTOBATTLER_DESIGN.md §2       (which invents one)
        └─► TACTICS_TREES.md          (which builds it)

AUTOBATTLER_DESIGN.md §7 risk 2 ("no pathfinding permitted")
   └─► AUTOBATTLER_DESIGN.md §8 #21   ("real pathfinding IS a key feature")
        └─► §11 spike — RUN, PASSES (HANDOVER §4)

AUTOBATTLER_DESIGN.md §9 (coordinator's blocking rule)
   └─► AUTOBATTLER_DESIGN.md §12 #30  (blocking becomes a TACTIC)

TACTICS_DESIGN.md (open question: what should formation be?)
   └─► TACTICS_BRAINSTORM.md → AUTOBATTLER_DESIGN.md #1 (free placement, saved formations)
        └─► UX_DEPLOYMENT.md

CLASS_REWORK.md + DOCTRINES_AND_CLASSES.md  (two proposals)
   └─► CLASS_BUILD_PLAN.md               (one plan)
        └─► still unbuilt; 18 emergent classes ship

ART_THEME.md (65 species, three tiers)
   └─► ART_BIBLE_GUILD_COLOURS.md        (12 species, two tiers — the slice)

BATTLE_SPRITES.md (6 frames × 65)
   └─► SLICE_DECISIONS §3                (1 pose, animated in code)

OUTLINE.md + GAME_DESIGN.md (React / Pixi / browser)
   └─► GODOT_MIGRATION.md                (Godot, desktop)
```

---

## 4. ⚠️ Landed while this file was being written

Six documents and one data file appeared between 12:45 and 13:00 on 2026-08-04, all from
concurrent workstreams. They are placed in §2 above from their headers only — **I did not read
them in full and did not check them for contradictions.**

`AUDIO_DIRECTION.md` · `CLASS_BUILD_PLAN.md` · `GAME_MODES.md` · `SPATIAL_BALANCE_TOOLING.md` ·
`TACTICS_TREES.md` · `UX_DEPLOYMENT.md` · `docs/data/projectiles.json`

Also landed in code: `scripts/ai/` (`bt_blackboard.gd`, `bt_context.gd`, `bt_result.gd` — the
behaviour-tree scaffolding), `scripts/_spike_determinism.gd`, `scripts/_perf_probe.gd`.

⚠️ **More will have landed by the time you read this.** `git log` and `ls docs/` are authoritative;
this file is a snapshot.
