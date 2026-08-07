# tamerengine — the 2D battlefield engine (branch `3doverhal`)

A continuous 2D battlefield — Teamfight-Manager style — running alongside the
turn-based engine, **not replacing it**. `simulateTeamBattle` and its 12 golden
tests are untouched; nothing in `src/tamerengine/` is imported by the shipping game
loop yet.

> ⚠️ **This is a test branch.** Nothing here goes to `main` until the whole
> thing is playable and balanced.

## Shape

40×22 world units, fixed **10 Hz** tick (`DT = 0.1`), hard cap 90 s. One seeded
rng, one fixed unit order. **Determinism is the contract** — a staged cup is
saved and resumed, and standings are recomputed from stored orders, so the same
(monsters, seed, orders) must always produce the same event stream byte for
byte. That is why nothing in here calls `Math.random()` and why the confusion
veer is derived from a unit id rather than rolled.

| File | Purpose |
|---|---|
| `types.ts` | `FieldUnit`, `FieldEvent`, constants |
| `personality.ts` | the 6 personality axes, derived from a **separate** seed stream |
| `decide.ts` | pure AI — targeting, goals, spacing |
| `engine.ts` | the tick loop and every effect application |
| `status.ts` | what each of the 15 statuses MEANS in space |
| `spatial.ts` | which existing moves gain geometry |
| `fieldMoves.ts` | the 18 field-only abilities (a **separate pool**) |

## Invariants worth not rediscovering

**Personality never draws from `generateMonster`'s rng.** It derives from
`seed + ':personality:v1'`. Rolling it inline would shift every generated
monster and move all 12 goldens.

**`ALL_MOVES` stays at exactly 90.** `chooseLoadout` draws from it, so growing
the pool changes what every monster learns. The 18 field moves live in
`fieldMoves.ts` and are asserted separate by test.

**Everything the field adds is a gated optional field** the turn engine never
reads (`Move.range`, `castTime`, `spatial`, `Monster.personality`, the spatial
`Tactics` fields). Absent ⇒ no behaviour change ⇒ goldens safe by construction.

**Every authoring table gets a test that its entries name real things.** The
spatial table once carried 8 move names that were actually *innate ability*
names — all silently inert. A test caught it; nothing else would have.

## What the engine models — and what it does not

Modelled: damage, mitigation, crits, AoE geometry with falloff, line of sight,
cover, forced movement (push/pull/dash/blink), roots, slows, ground zones,
fade, ally-hauling, **all 15 statuses**, **taunt**, and timed **atk / def**
multipliers.

**Not modelled** (and therefore scored **zero** by the move chooser, so no
monster ever spends a cast on one): `ward`, `guard`, `thorns`, `cleanse`,
`dodgeBuff`, `accBuff`, `hpRegenBuff`, `spreadStatus`, `firstStrikeMult`.
Making these real is open work — but a scorer that valued them would have
monsters burning cooldowns on nothing, which is exactly the bug below.

## Bugs this system has already produced (all fixed, all silent)

Each of these ran without erroring and looked like a working fight.

**No status was ever applied.** `FieldUnit.statuses` was initialised to `[]` and
nothing wrote to it. Every burn, stun and fear in the game was inert on the
field; moves whose entire value is their rider paid their cooldown for nothing.

**No non-damage move was ever cast.** `chooseMove` filtered
`type === 'damage'`, so every support kit — and all 18 field moves, which are
mostly `buff`/`debuff` — was dead weight.

**`reachOf` scanned the whole loadout.** A melee bruiser carrying *any* support
move took its stand-off distance from that move's 5–6 reach and parked outside
its own swinging range, never landing a blow all fight. Reach must come from
**damage moves only**.

**Utility was scored against the skill, not against what the unit would
otherwise do.** When every skill was on cooldown the bar became zero, so a
near-worthless buff pre-empted even the basic attack — War Cry took 137 of 254
utility casts. The bar is now `max(UTILITY_FLOOR, whatever damage option won)`.

**Refreshing a running effect was scored at full value.** Overhealing was
already discounted; buffs and debuffs were not. Anything already active now
scores 0.1×.

**Taunt was cast 86 times for zero effect** before taunt existed on the field.
This is the failure mode that justifies the "score unmodelled effects at zero"
rule above.

**Charm's two halves fought each other.** It carried both a `steer: 'toSource'`
(walk toward the charmer) and `turncoat` (attack your own side) — pulling the
victim in one direction while it tried to hit something in the other, so it
drifted between them and struck nobody. Targeting won; the pull became a
one-off lurch at the moment of enthralment.

**Buffs and debuffs becoming real pushed draws from 4 to 11 in 40 fights.** Two
teams shaving each other's damage until the 90 s cap expired. Fixed with
sudden death from 55 s — and as a **fraction of max HP**, for the same reason
the turn engine's round-35 chip is: flat chip lets raw CON win the clock, which
double-dips a stat that already buys health.

## The three statuses that gained geometry

The point of a spatial engine is that some of these words can mean something a
turn counter cannot express:

- **fear** — the victim actually *flees*, away from whoever frightened it, and
  cannot bring itself to strike back while running.
- **confusion** — it walks the *wrong way*, veering off its intended heading.
- **charm** — it turns and fights its own side.

This is why every status records `from`. A counter alone cannot express either
"run from" or "lurch toward".

## Units

Moves author status `duration` in **rounds**; the field runs in seconds.
`SECONDS_PER_ROUND = 2.0`, applied in exactly one place (`applyFieldStatus`).
Damage-over-time is stated per second in `FIELD_STATUS` and scaled by `DT`, so
the turn engine's "5% of maxHp per round" is `0.05 / 2` here — a status is worth
the same over its lifetime in either engine.

⚠️ And the standing project rule: `atkBuff`/`pierce`/`execute` are **fractions**;
`dodgeBuff`/`accBuff`/`accDebuff`/`defBuff` are percentage **points**.

## Current measurements

3v3, 40 fights, generated monsters at `train: 900`:

| | |
|---|---|
| result spread | 23 A / 17 B / **0 draws** |
| duration | median 26.4 s, max 70 s (cap 90 s) |
| casts | 2142, of which **10.6% non-damage** |
| healing | 34 heals, 507 HP restored |
| statuses | ~135 applications per 20 fights, every fight sees some |

Tests: `src/tamerengine/status.test.ts` (19), plus `field.test.ts`, `spatial.test.ts`,
`tactics.test.ts`. Whole suite 112/112 including all 12 goldens.

## Battlefield art (v0.94)

Pixel-art field assets in `public/field/`, matched to the battle sprites:
- `arena-grass.jpg` — detailed 16-bit grassy ground, tiled across the field.
- `boulder.png` — a mossy pixel boulder, drawn at each `Obstacle` box.

Both are codex-generated (see `docs/CODEX_IMAGE_GEN.md`). The preview renderer
draws the ground tiled, a boulder per obstacle, the battle sprites walking the
`public/battle` cycles, and — off the engine's own `cast`/`hit` events — ranged
arrows and magic bolts flying to their targets with impact sparks on landing.

## The M0–M5 build (v0.94 → the mounted engine)

Everything from here down is the pass that turned the prototype into a real,
mounted system named **tamerengine** — the eventual replacement for the turn-based
battle engine (swapped in only once complete; see M7 below). All standalone,
reachable at the `?tamerarena` dev route (branched in `main.tsx`), NOT wired into
the game loop yet.

### Snapshot (M1) — what the renderer gets
The per-tick snapshot unit now carries `hp/maxHp`, `mp/maxMp`, and split
`buffs`/`debuffs` icon-key lists (derived by `effectIcons()` in `engine.ts`:
`BENEFICIAL` statuses → buff, the rest → debuff; the timed `mods` → `atkUp` /
`atkDown` / `defUp`). `maxHp`/`maxMp` drive the 100-HP / 50-MP notches.

### Hard collision (M2)
`resolveCollisions()` runs once after every unit has moved (and once at setup):
overlapping living pairs are pushed apart, six iterations, deterministic. No two
monsters ever share space — they settle adjacent and surround a target.
- ⚠️ **Collision radius < visual radius** (`COLLISION_R_FRAC = 0.66`). Two full
  radii (1.8) exceed the basic melee reach (1.28), so a full-radius floor would
  stop melee ever connecting. Units settle ~1.19 apart — inside reach, clearly
  adjacent. Must stay below `(CHANNEL_RANGE.melee × 0.8) / (2 × radius) = 0.71`.

### Role personalities + forced engagement (M3)
`archetypeOf()` in `decide.ts` classifies each unit and biases `desiredGoal`:
anchor holds the front, artillery kites the back (⚠️ **voice reach does NOT count
as artillery** — a self-centred AoE wants to be among enemies), assassin dives
then breaks off (`disengageFor`), support holds behind near the hurt ally.
- ⚠️ **Sudden death forces the fight.** Collision + spacing let two distance-
  wanting teams stand off until the chip wiped both the same tick — a
  zero-engagement draw. Once the clock turns lethal, kiting/spacing are overridden
  and every un-steered unit drives at its target. Draws also break by total
  damage dealt, then last aggressor.

### Renderer (M4) — `TamerArena.tsx`
Plays a `FieldResult` back on the pixel field: notched HP/MP bars (debuff · buff ·
HP · MP, top→bottom), per-ability animations (`fieldFx.ts` ports the arena's
`BESPOKE_KIND` vocabulary; a canvas overlay draws travelling arrows/bolts and
bursts off the cast/hit stream), timer toggles (pause · 0.25–4×), death topple,
depth-sort, winner banner.
- ⚠️ Driven **imperatively** (one rAF loop mutating the DOM), not per-frame React
  state, so a dozen sprites don't thrash the tree.
- ⚠️ The clock accumulates **rAF dt**, not `now − mountTime`: rAF pauses when the
  tab is hidden while `performance.now()` runs on, so a component mounted
  off-screen would jump straight to the end on first paint.

### Hex deployment (M5) — `hex.ts` + `Deploy.tsx`
Both teams deploy on a pointy-top axial hex grid over their back band (cells
spaced past the collision floor, so a placed formation never starts overlapping).
Click a tray monster, click a hex; the enemy auto-deploys by role (sturdiest
front). The chosen cells feed `FieldSetup.placeA` / `placeB`.

Tests: `collision.test.ts`, `roles.test.ts`, `hex.test.ts` on top of the existing
suite — **136/136 green**, turn engine and its 12 goldens untouched.

## Open work

- **M7 (deferred): replace the main battle engine.** Only once the above is proven
  — stage cups/trials onto tamerengine, run the fight through `TamerArena` in the
  `App.tsx` battle phase, produce the reward/injury/exp the cup loop consumes,
  then retire `simulateTeamBattle`.
- ~~Tactics controls on the deploy screen~~ **DONE (Step 1).** `Deploy.tsx` is now
  the planning phase: place on hexes **and** set each monster's orders
  (`TacticsPanel.tsx` — the 7 Tactics fields the field decider reads:
  temperament, target, engage, spacing, commit, cover, survival), then **FIGHT**
  fades the hex grid out and hands (placement + tactics) to the sim. The grid is
  deployment-only, gone in the fight. A differential sim confirms the orders bite
  (same teams/placement: defensive 68s/1-survivor vs aggressive 31s/3).
- Ward / guard / thorns / cleanse / dodge / accuracy have no field representation.
- Per-cup arenas: backdrop + obstacle set keyed to the tournament.
- Battle sprites for the other 60 species — explicitly *after* the engine works.
- A full balance pass against a long-haul sim, per the standing rule in
  `CLAUDE.md`. The numbers above are engine health checks, not balance.
