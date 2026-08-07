# Godot migration

**Decided 2026-08-03.** The game moves to **Godot 4.7.1**, shipped as a desktop title.
This document is the working plan and the running notes. `CLAUDE.md` stays the guide to the
TypeScript build for as long as that is the thing being run.

> **The framing, in the user's words:** *"most of the game will need to be reworked in some
> way — what we have so far is the skeleton/back end. The user will have a far richer visual
> experience when they play."*

That framing is load-bearing and it changes what a "port" means. This is not a translation of
28,000 lines. It is: **keep the combat MATH and the data, rebuild everything else.**

### Decisions taken 2026-08-03

| # | decision |
|---|---|
| 1 | **Creatures are 2D sprites in a 3D arena.** Art style to be settled later. |
| 2 | **Do NOT port the arenas, the arena rules, or how arenas work.** The 43 boards were tests and will be far improved upon. Rebuilt natively. |
| 3 | **Do NOT port the spatial layer** — hex lattice, deploy bands, navgraph, camera framing. Reworked in Godot on its native systems. |

⚠️ **AND THAT LAST ONE INVALIDATES THE WHOLE-FIGHT GOLDENS AS AN ACCEPTANCE TEST — see §2.**
They were frozen on 2026-08-03 and re-scoped the same day, which is the sequencing working
rather than failing: the contract was written before the spatial decision was made.

---

## 1. What survives, what is rewritten, what is thrown away

Measured, not estimated — line counts are `wc -l`, excluding tests.

| area | LOC | disposition |
|---|---|---|
| `tamerengine/engine.ts` | 2153 | **PORT.** The fight. Pinned by `goldens.json`. |
| `tamerengine/types.ts` | 1138 | **PORT.** Constants the engine reads — `CLASS_BASIC`, cast times, statuses. |
| `tamerengine/{status,spatial,navgraph,hex}.ts` | 732 | **PORT.** Engine support. |
| `moves.ts` + `lines.ts` + `signatureMoves.ts` | 747 | **DATA — export, do not port.** 141 moves as a resource. |
| `species.ts` + `core.ts` | 1228 | **DATA + types.** 65 species, 18 classes, tables. |
| `town.ts` + `game.ts` + `monster.ts` | 4170 | **DEFER.** Weekly tick, breeding, tournaments, economy. Not engine-bound; no reason to move it early. |
| `App.tsx` + `arena.tsx` | 4472 | **THROW AWAY.** This is the "richer visual experience" — rebuilt as Godot scenes. |
| `tamerengine/three/*` | 3943 | **THROW AWAY.** The three.js renderer. Its *design rules* survive in the docs; none of its code does. |
| `maps.ts` + `themes.ts` | 3076 | **REWORK IN GODOT.** See §4. |
| `battle.ts` | 1783 | **RETIRE.** The turn engine `tamerengine` was always going to replace. |

**Rough shape:** ~4,000 lines are a real port. ~2,000 are data that becomes resources.
~8,400 are thrown away and rebuilt. ~4,200 wait their turn.

---

## 2. The contract — how we know the port is correct

⚠️ **THE WHOLE-FIGHT GOLDENS ARE NO LONGER THE ACCEPTANCE TEST. THEY ARE A REFERENCE
RECORDING.** `duration 23.2s` is a product of pathfinding, cover geometry and reach — the
exact layer decision 3 replaces. A Godot engine running on native navigation would produce a
different number, and it *should*. Diffing against these would fail a correct port.

They keep two real uses: a **before/after reference** for how the TS game felt, and a live
regression pin on the TypeScript build for as long as it is the thing being run.

⚠️ **WHAT REPLACES THEM IS A COMBAT-MATH CONTRACT, AND IT IS BUILT** —
`src/tamerengine/combat.json`, **61 cases across 23 axes**, regenerated and diffed on every
test run by `combat.contract.test.ts`. Generate with `npx tsx tools/exportcombat.ts`.

The arithmetic came out of `engine.ts:strike()` into **`src/tamerengine/damage.ts`** as a pure
`resolveStrike()`. The whole extraction moved no golden — proof the seam is real rather than
convenient.

⚠️ **THE SEAM IS THE POINT: `behindMult` and `flankBonus` ARRIVE RESOLVED.** Those were the
only two places the damage code reached into geometry. Godot answers "is this unit behind that
one?" with its own physics and its own navigation — and once it has an answer, the arithmetic
that follows must match to the integer. That is a contract a rebuilt engine can honour.

⚠️ **AND THE RNG IS AUTHORED, NOT DRAWN.** Every case carries explicit `acc`/`crit`/`variance`
values, so the port never has to reproduce `mulberry32` before it can compare a number. Same
reasoning as the resolved inputs on the old contract: a second, harder port bolted to the front
of the real one, whose failures present as engine bugs.

⚠️ **THE FIXTURES ARE SYNTHETIC MOVES, NOT REAL ONES.** Pinning to `Scrap`'s power would make
every balance pass break the port's test — a tuning change presenting as an engine regression.
Each case isolates ONE axis with round numbers, so a diff names the mechanic, not the ability.

What it pins:

| pinned | why it survives |
|---|---|
| `maxHp = 40 + CON x 2.0`, `maxMana = WIS + floor(INT/2)` | pure stat math |
| damage = `power x (1 + stat x statScale)`, variance as a half-width band | no geometry |
| mitigation — physical vs CON + guard, magic/voice/support vs WIS | no geometry |
| mana cost = `manaCost(mv) x FIELD_MANA_COST_MULT`; regen from WIS | no geometry |
| effect resolution — pierce, multi-hit, execute, recoil (capped 15%), lifesteal, mana burn, guard, ward, thorns, `bonusVsStatus` | no geometry |
| status apply / stack / expiry, `HARD_CONTROL_STATUSES` | no geometry |
| cooldowns in SECONDS, cast times per channel | no geometry |
| `CLASS_BASIC` — the authored free attack per class | reach is spatial, the rest is not |

**A worked check on the table, so the numbers are legible:** baseline is `112` = 100 power x
1.12 melee trim, no mitigation. A 500-point guard against it caps at 35% and yields
`112 - 39.2 = 73`. The opening-mitigation ramp reads `90 / 90 / 101 / 112` at t = 0 / 30 /
37.5 / 45.

⚠️ **`OPENING_MIT_HOLD` IS 30 SECONDS AT FULL STRENGTH, THEN A 15-SECOND FADE — SO THE BONUS
IS ONLY GONE AT t=45.** The fixture baseline was first written at `now: 30`, which is the END
of the hold where the bonus is still at maximum; it silently folded 20 points of mitigation
into all 61 cases and made the case named "opening mitigation expired" a duplicate of the one
named "at full strength". Caught by reading the emitted table, not by a failing test — which
is the argument for `exportcombat.ts` printing its own summary.

⚠️ **THE SPATIAL PREDICATES ARE DELIBERATELY EXCLUDED.** `hasLineOfSight`, `isBehind`,
`reachOf`, flanking, `chooseMove`'s obstacle argument — all of it gets rebuilt on Godot
navigation and physics, and pinning today's answers would force the new engine to reproduce a
system we are replacing on purpose.

---

### The old contract, for reference only

`src/tamerengine/goldens.json`. Three fights, frozen 2026-08-03, regenerated and diffed on
every TS test run so it cannot rot.

```
duel-melee         1v1  winner B  23.2s  hp [0, 481]
caster-vs-brawler  1v1  winner B  10.5s  hp [0, 426]
trio               3v3  winner A  18.3s  hp [338, 379, 272, 0, 0, 0]
```

⚠️ **IT CARRIES RESOLVED INPUTS, NOT SEEDS, AND THAT IS THE WHOLE DESIGN.** A golden's team
is built by `generateMonster(seed)` and then hand-pinned to an explicit kit. Carrying only
the seed would force the Godot side to reproduce this project's seeded RNG bit-exactly
*before* it could begin comparing engines — a second, harder port bolted onto the front of
the real one, whose failures would present as engine bugs. Concrete stats, concrete
loadouts, concrete positions, concrete obstacles isolate the port to the **simulation**.

**`generateMonster`, `chooseLoadout`, `ALL_MOVES` and the draft rules are out of scope for
the port, permanently.** They stay in TypeScript, or get rebuilt later on their own terms.

Regenerate after any deliberate engine change: `npx tsx tools/exportgoldens.ts`

### ✅ THE PORTABLE LAYER IS DONE (2026-08-03) — 173/173 cases + data tripwires

⚠️ **AND IT IS DONE IN THE SENSE THAT NOTHING PORTABLE REMAINS, not in the sense that the
engine is finished.** What is left in `engine.ts` is ~1,140 lines of AI and decision-making
(`chooseMove`, `utilityScore`, `decide.ts`) that is *entangled* with the spatial layer — it
takes obstacles, folds in reach and line of sight, and reads positions to pick targets. Per the
standing rule in `CLAUDE.md`, that layer is being REWORKED, so porting it as-is would drag the
old spatial model in through the back door and make the rework harder than starting clean.
**The next step is design, not translation** — see `docs/SPATIAL_COMBAT_DESIGN.md`.

Everything that survives a spatial rebuild now runs in GDScript and matches TypeScript exactly.

| contract | cases | subject | GDScript |
|---|---|---|---|
| `combat.json` | 62 | damage resolution | `scripts/damage.gd` |
| `derive.json` | 46 | pools, mana, cooldowns, cast times | `scripts/derive.gd` |
| `status.json` | 31 | statuses + CC diminishing returns | `scripts/status_math.gd` |
| `tick.json` | 34 | timers, regen, attrition, expiry, sudden death | `scripts/tick.gd` |
| `data.json` | — | 141 moves, 65 species, 18 classes, the status table | loaded, not transcribed |

```bash
cd monster-tamer && ./run_contract.sh
```

⚠️ **DATA IS EXPORTED, NOT PORTED.** Rewriting 141 moves as GDScript literals would create a
second copy that drifts the first time anyone retunes a number, and the drift would present as
an engine disagreement rather than as stale data. `data.json` is regenerated and diffed by
`npm test` like the other three.

⚠️ **AND THE STATUS BEHAVIOUR TABLE HAD TO JOIN IT.** The first cut of `status_math.gd`
hardcoded `MAX_STACKS = {bleed: 3}` and `LURCH_TO_SOURCE = {charm: 2.5}` — two entries out of
fifteen, transcribed by hand because they were the only two `applyStatus` reads *today*. Add a
second stacking status and the GDScript would have silently not stacked it, with nothing
failing. Verified live by deleting `bleed.maxStacks` from the JSON: three cases fail.

---

### ⚠️ FINDINGS — what writing the contract turned up

Every one of these came from having to state a rule explicitly, not from a failing test.

**1. `maxHp` is QUADRATIC and the docs said it was linear.** `CLAUDE.md` recorded
`maxHp = 40 + CON x 2.0`. The real formula is `40 + CON*2 + CON^2/1600`.

| CON | actual | linear reading | delta |
|---|---|---|---|
| 300 | 696 | 640 | +56 (+8.8%) |
| 500 | 1196 | 1040 | +156 (+15%) |
| 800 | 2040 | 1640 | +400 (+24%) |

HP is superlinear in CON on purpose — it is what makes a wall a *wall* rather than a slightly
tougher body. A port written from the prose would have shortened every high-CON fight. Proven
by breaking the GDScript to the documented formula: 7 of 8 `maxHp` cases fail. CLAUDE.md
corrected; all eight points pinned.

**2. The CON control-resist floor saturates at CON 900 — exactly the Platinum cap.**
⚠️ **CONFIRMED FOR REWORK by the user, 2026-08-03.** Proposal, options and the reason not to
land it as a drive-by are in **`docs/SPATIAL_COMBAT_DESIGN.md` §4**.
`min(0.3, CON/3000)` reads as though it scales to 3000 and does not.

| league | cap | CON floor |
|---|---|---|
| Wood → Gold | 100–750 | 0.033 → 0.250 (a real gradient) |
| **Platinum → Tamers Apex** | **900–1100** | **0.300, flat** |

So CON buys **zero** additional control resistance across the entire 5v5 band the game is
balanced for. A cap is a cap and this may be intended — but it means the "CON resists control"
mechanic stops differentiating precisely where the shipping game lives. **Design call
outstanding**; the numbers are now visible in `status.json` (axis `conFloor`) instead of buried
inside a `min()`.

**3. There is no `heal` MoveType.** `manaCost`'s own comment labels a branch "heals";
`MoveType` is `damage | buff | debuff | status | control`, so the branch is really *any
non-damage move with positive power*. Transcribing the comment rather than the code would
misprice every restore.

**4. A bug written and caught during the extraction.** Stamping `lastCcAt` on any landed status
rather than only on hard control. A ticking damage-over-time would have kept the CC meter hot
forever, `CC_DR_RESET` would never fire, and control would stay diminished for the rest of the
fight. ⚠️ **The goldens did NOT catch it** — their fixtures never pair a DoT with chained
control. `ccMeterTouched` now carries the distinction explicitly and a test asserts only hard
control sets it. This is the clearest evidence in the project so far that whole-fight goldens
are a weak instrument for logic bugs: they only see what their three fixtures happen to do.

---

### Milestone 1 detail (2026-08-03) — 62/62 cases, 23 axes, exact

`monster-tamer/` is a real Godot 4.7.1 project and the combat math runs in GDScript:

| file | what it is |
|---|---|
| `scripts/damage.gd` | the port of `damage.ts:resolveStrike` |
| `scripts/contract_test.gd` | loads `data/combat.json`, runs every case, diffs 7 fields each |
| `scenes/contract_test.tscn` | the main scene, so a headless run IS the test |
| `run_contract.sh` | re-copies the contract from the TS tree, then runs headless |

```bash
cd monster-tamer && ./run_contract.sh
```

⚠️ **AND THE HARNESS WAS PROVEN TO FAIL BEFORE IT WAS TRUSTED.** A test that cannot fail is
worthless as a regression detector, and this one is the port's whole acceptance criterion.
Changing the melee channel trim from 1.12 to 1.0 in the GDScript produced 30+ named failures
(`dmg: got 100 want 112.0`) and exit code 1. Restored, it is green again. The exit code is the
result — a headless run that prints FAIL and exits 0 is a green CI light on a broken port.

⚠️ **FLOAT DETERMINISM: ANSWERED FOR THE PER-HIT MATH, AND STILL OPEN FOR ACCUMULATION.** All
62 cases match to the integer, so JS and GDScript agree on this arithmetic — the mitigation
curve, the multiplier chain, the rounding, the caps. What this does NOT prove is that they
would still agree after hundreds of ticks of compounding, which is what the old whole-fight
goldens depended on. We no longer depend on it, which is the point; do not read this result as
license to re-pin durations.

⚠️ **`data/combat.json` IS A COPY AND COPIES GO STALE.** The TS side cannot rot — the fixtures
are regenerated and diffed on every `npm test` — but this project holds a duplicate. That is
why `run_contract.sh` re-copies it every run rather than trusting what is on disk.

**Two GDScript traps worth writing down**, both hit during this milestone:
- **`class_name` is invisible to `validate_script`.** It resolves only once the project's class
  cache is warm, so validating a single file reports a perfectly good global class as
  "not declared in the current scope". Use `preload()` in scripts you want to validate alone.
- **`JSON.parse_string` returns every number as a float.** An integer `dmg` of 112 arrives as
  `112.0`, so a strict comparison fails every numeric case for no real reason. Compare bools
  strictly and numbers by value — see `_same()`.

### The first milestone, and it is deliberately small

Port `damage.ts:resolveStrike` to GDScript and diff it against `combat.json`. **No
visuals, no arenas, no navigation, no sprites — just identical damage numbers out of two
languages.** If it lands, everything after is downhill. If it does not, we find out in a day
rather than a month.

⚠️ **DO NOT PORT `simulateFieldBattle` WHOLE.** It interleaves the math with the spatial layer
— `chooseMove` takes `obstacles`, `estimateDamage` and `effPowerField` fold in reach and line
of sight, `isBehind` sits in the damage path. Porting it whole drags in the system we decided
to rebuild. The math comes across; the tick loop, the movement and the target selection get
written fresh against Godot's own navigation.

⚠️ **Float determinism is the risk nobody has checked yet.** The engine is float-heavy and
the goldens pin `duration` to 0.1s and HP to the integer. GDScript floats are 64-bit like
JS, so this *should* hold — but "should" is not a measurement, and if it does not, the fix is
a tolerance band on `duration` and exact match on winner/HP, decided once and written here.

---

## 3. What Godot gives us that the browser did not

Verified 2026-08-03 against a live project, not read off a README.

- **`game_screenshot` returns a PNG the agent can see directly.** All the arena work was done
  by POSTing canvas blobs to a dev-server middleware because screenshots are unavailable in
  this environment. Every "authored but invisible" failure — the victory arch built inside a
  stand, the treeline on 9 boards of 14, the mosaic that averaged to flat — was a *seeing*
  problem. This removes it.
- **`game_eval`** runs arbitrary GDScript in the running game with return values.
- **`game_raycast`** returns hit, collider path, exact position and normal. With
  `game_debug_draw`, that is a real line-of-sight instrument.
- **Editor-side tools work headless** — scenes, scripts, resources, validation, export.

⚠️ **The MCP splits into two halves with a hard boundary.** Editor tools spawn headless Godot
per call and work any time. `game_*` tools need `run_project` first — it injects
`mcp_interaction_server.gd` and opens TCP on 127.0.0.1:9090. The injected file removes itself
on `stop_project`.

**Config** (user scope, `~/.claude.json`) — both paths were wrong for a day because the
example text got pasted verbatim:
```json
"command": "node",
"args": ["C:/Users/P/godot-mcp/build/index.js"],
"env": { "GODOT_PATH": "P:/Godot_v4.7.1-stable_win64.exe" }
```
Godot is a **portable extract on `P:`** with no registry entry, which is why auto-detection
guesses `C:\Program Files\Godot\Godot.exe` and fails.

---

## 4. Arenas — examples, not content

⚠️ **THE 43 AUTHORED ARENAS ARE ART-DIRECTION EXAMPLES AND WILL BE REWORKED IN GODOT.** This
is the user's explicit call and it resolves what would otherwise be a serious problem:
`arenaFor()` has **zero production callers** — only tests. Every board, ground and prop is
currently unreachable from an actual fight. Wiring them up in TypeScript would be work thrown
away twice.

⚠️ **AND THE RULES ARE NOT PORTED EITHER — THEY ARE RE-DERIVED.** The user's call, and it is
the right one: `ARENA_DESIGN.md` is a record of what went wrong on a BILLBOARD renderer with a
board-fitted camera, and a good half of it is scar tissue from constraints that stop existing.
Read it for the reasoning, not for the rules. Nothing in it is authority in Godot.

What is worth carrying is the handful of findings that are about FIGHTS rather than about
sprites — cover exists to break straight lines and create decisions; few and large beats many
and small; a board every league can be told apart from needs its own silhouette. Those came
from the sim, not the renderer.

The rest is explicitly suspect:

- the **density law**, now weighted by footprint (`pieceCost`) rather than counting heads
- **no two boards share a layout signature** — count / bars / chunky / x-spread / y-spread
- **exactly one board is bare**, and the count is pinned
- **aspect ratio decides how much stadium is ever seen** — measured, with the numbers
- deployment bands, centre-line mirroring, footprint-vs-sprite-height envelopes

⚠️ **Two of those constraints are artefacts of the billboard renderer and should be
RE-EXAMINED, not ported.** "Every prop draws along X" and "a prop may not be deeper than it
draws tall" exist because props are cards standing on rectangles. Real 3D meshes have neither
limit — which means a barrier *across* the approach, a genuinely round fountain and a deep
portrait footprint all become possible. Several boards were shaped by working around those
rules; some of those shapes stop being necessary.

`docs/ART_DIRECTION.md` holds the three independent axes (material / size / grandeur), the
camera and lens, and the **cumulative grandeur ladder** — eleven rungs from a bare Wood field
to the Apex victory arch. That ladder is a design asset and should survive the move intact.

---

## 5. Assets

**On disk now**, generated through `tools/proc_arena_art.py` (see `docs/ART_PIPELINE.md`):

| kind | count |
|---|---|
| species portraits (320×320 RGBA) | 65 |
| battle sprites (128×128, 6 frames) | 30 |
| arena grounds (1254² JPEG) | 34 |
| props (≤256px RGBA, alpha-trimmed) | 36 |
| league backdrops | 19 |

⚠️ **THE PIPELINE'S CORRECTION TABLES ARE THE VALUABLE PART, NOT THE IMAGES.** Three knobs,
each added because a generated texture shipped wrong: `SURFACE_EXPOSURE` (pale prompts come
back near paper — sand at 193, alabaster at 220, travertine at 201), `SURFACE_SATURATION`
(ochre and gilt come back at 0.52), and `SURFACE_CONTRAST` (onyx banding outshouted the props
and neither of the other two knobs could reach it). Any new art route needs the same
measurement discipline or it will make the same three mistakes.

**Free CC0 sources** — verify licences at download:

| source | what for |
|---|---|
| **ambientCG**, **Poly Haven** | PBR materials, HDRIs. Highest value per unit of effort. |
| **Kenney.nl** | Low-poly kits, UI, audio. Consistent style, genuinely CC0. |
| **Quaternius** | Low-poly kits **including rigged animated creatures**. |
| **Godot asset library** | Addons; check licence per item, they vary. |

⚠️ **THE CREATURE ART IS THE SCHEDULE, AND IT ALWAYS WAS.** ~65 species × ~5 animation
states is ~325 clips. That number does not care which engine renders it, and it dwarfs the
engine work. **Decide the creature strategy before building anything that depends on it:**

1. **Keep 2D sprites in a 3D world** (the current Octopath approach). Cheapest by an order of
   magnitude. The existing 65 portraits and 30 battle sprites carry straight over.
2. **Rigged 3D creatures.** The expensive path. Free rigged libraries (Quaternius) will not
   cover 65 designed species, so it means either commissioning, generating, or cutting the
   roster.
3. **Hybrid** — 3D for the arena and props, 2D billboards for creatures. This is what the
   three.js build already does and it looked right.

---

## 6. Targeting — the thing Godot is expected to improve

The user's stated interest. ⚠️ **Treat it as a hypothesis to TEST, not a given.**

The measurement that exists: `tools/focus.ts` puts top share — a side's damage landing on its
single most-damaged enemy — at **0.711**, where an even split across three bodies would be
0.333. A side hits **1.78** distinct enemies per 5s. Correlated across ten compositions,
**maxHp r=+0.79** against time-to-first-kill and **top share r=−0.56**. Focus is real and
signed correctly, but it is the *smaller* lever.

⚠️ **The targeting logic is OURS, not the engine's.** Porting it unchanged ports the same
0.711. What Godot actually buys is better *instruments*: `focus.ts` infers concentration from
damage events after the fact, where a real physics world can be queried for line of sight
directly and the result drawn on screen. That is the difference between measuring targeting
and being able to watch it.

Flanking (+10 acc when outnumbered and unsupported) exists. **Target selection does not.**

---

## 7. Sequence

1. **Freeze the goldens.** ✅ Done 2026-08-03 — `goldens.json`, 269 tests green.
2. **Port `engine.ts` to GDScript.** Diff against the contract. No visuals.
3. **Decide the creature strategy** (§5). Everything visual depends on it.
4. **Rebuild the battle presentation** in Godot — arena, camera, lens, the grandeur ladder.
5. **Rework the arenas** natively, against `ARENA_DESIGN.md` minus the billboard constraints.
6. **Move the meta-game** — `town.ts`, `game.ts` — when there is a reason to, not before.
7. **Economy rebalance, last**, against the finished sinks and sources in one pass.

⚠️ **STEPS 2 AND 4 ARE SEPARATE ON PURPOSE.** A verified simulation with no graphics is a
checkpoint. A half-ported simulation inside a half-built renderer is a debugging problem with
two unknowns and no way to bisect them.

---

## 8. Deferred, and still true

Carried from `CLAUDE.md` — none of it is engine-bound, all of it survives the move:

- **`tools/comps.ts` re-weighting toward 5v5.** It fights 2×2v2, 3×3v3, 2×4v4, 5×5v5 — seven
  of twelve compositions are not the game being balanced. The standing rule says 5v5 **is**
  the game. This moves every baseline in `CLAUDE.md` and `docs/BALANCING.md`, so it is done
  deliberately and alone.
- **Six passives**, designed in `ABILITY_REWORK.md`, not built. Needs engine work first:
  exclude from `chooseMove`, from `reachOf`, from `basicAttackFor`.
- **`spreadStatus`** (contagion) — the one P2 effect left unbuilt. Sim it alone.
- **`Move.area` consolidation** — AoE is attached by NAME, so renaming an ability silently
  makes it single-target. Two attempts reverted; every trap is in
  `docs/HANDOVER_area_consolidation.md`.
- **`tauntForce`** — mass taunt works; a proper forced-target pass does not exist.
- Achievements + goal-gradient · named rival in cups · Hall of Fame perks, lifespan elixir,
  richer inheritance.

---

## 9. Open questions

~~1. Creature strategy~~ — **ANSWERED: 2D sprites in a 3D arena.** Art style still open.
~~2. Hex lattice~~ — **ANSWERED: not ported. Rebuilt on Godot navigation.**
~~4. Camera framing~~ — **ANSWERED: reworked in Godot.**

3. **Does the meta-game stay in TypeScript long-term**, or is Godot the whole thing
   eventually? Changes whether `town.ts` gets maintained or frozen.
~~5. Float determinism~~ — **ANSWERED for the per-hit math: 62/62 exact.** Still unmeasured
   for long accumulation, and we no longer depend on it.
~~6. What is the new spatial model?~~ — **SPECIFIED. See `docs/SPATIAL_COMBAT_DESIGN.md`**,
   which pins reach, cover and flanking in the user's own terms and records where the current
   code disagrees with them. ⚠️ Two of the three did NOT match: **cover is binary occlusion
   today, not an accuracy debuff**, and **flanking is +5 on a 4.0-unit radius, not +10 on melee
   engagement**. The remaining open questions are listed there, not here.
7. **The art style for the 2D creatures** — the existing 65 portraits and 30 battle sprites
   are a starting point, not a commitment.
