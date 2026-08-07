# The spatial model — elaboration

**2026-08-03.** Expands `SPATIAL_COMBAT_DESIGN.md` (the intent) into what the system actually
has to *be* in Godot. This is the blocker: target selection, formation, stations and the arena
rebuild all wait on it.

⚠️ **NOT A SPEC.** A design elaboration with the decisions named and the constraints measured.

## ✅ DECISIONS TAKEN 2026-08-03

| # | decision | consequence |
|---|---|---|
| 1 | **NO ELEVATION — the field stays flat.** User: *"it would add problems for design and readability."* | §2's open question is closed. Cover is vertical geometry on a flat floor. Readability wins, and it is consistent with legibility being a first-class requirement. |
| 2 | **PHYSICS-BASED.** User: *"physics based would seem so much more fun."* | ⚠️ **This overrides my earlier recommendation and §0 is revised below.** It is achievable without losing the harness — but only with specific constraints. |
| 3 | **ARENAS GET MUCH LARGER**, and monsters get real freedom to move. | ⚠️ **This changes what formation IS** — see §10. Cohesion becomes the primary axis, not shape. |
| 4 | **COVER IS A TOOL FOR DISENGAGEMENT**, not only an accuracy modifier — used to break an attack or to reposition. | §4.2 extended in §11. |
| 5 | **KITING NEEDS REWORKING** so units are not *"running around the arena forever."* | ⚠️ Larger arenas make this worse, not better. §11. |
| 6 | **FACING IS IMPORTANT**, especially with flanking. | §4.3 confirmed. |

---

## 0. ⚠️ START HERE: determinism is the constraint that shapes everything

`engine.ts` opens with this, and it is not decoration:

> *"DETERMINISM IS THE CONTRACT. Everything downstream — resuming a saved cup, recomputing
> standings, the sim harness, replaying a fight in the arena — depends on
> `simulateFieldBattle` being a pure function of (monsters + placement + obstacles + seed).
> So: fixed dt, fixed unit order, one seeded rng stream, and no wall-clock or Math.random
> anywhere."*

**Four systems depend on it today:** resuming a saved tournament, recomputing standings,
`sweep40` and the balance harness, and replaying a fight in the arena.

⚠️ **AND GODOT'S PHYSICS AND NAVIGATION ARE NOT DETERMINISTIC BY DEFAULT.** This is the single
biggest technical decision in the rebuild and it must be made before anything is built:

| source of non-determinism | why it bites |
|---|---|
| **Variable frame delta** | `_process(delta)` differs run to run; movement integrated against it diverges immediately |
| **Physics solver iteration** | Jolt is reproducible on the same binary and settings, **not guaranteed across platforms or versions** |
| **Avoidance (RVO)** | multi-agent avoidance is order- and neighbour-dependent; two agents resolving in a different order give different positions |
| **Navmesh baking** | a rebaked mesh can produce different polygon ordering, so paths differ |

### The three honest resolutions

**A. Fixed-step simulation, rendering decoupled.** Run the fight in `_physics_process` at a
fixed tick, drive movement in our own code, use `NavigationServer3D` only to *query paths* —
never to move bodies. Physics is for queries (raycasts, overlaps), never for integration.

- ✅ keeps determinism, keeps replays, keeps the sim harness
- ❌ we write the movement integrator ourselves — which is what `engine.ts` already does

**B. Physics-driven, accept non-determinism, store replays as EVENT LOGS.** The fight happens
once; the replay plays back a recorded event stream rather than re-simulating.

- ✅ full use of the engine, avoidance and collision for free, likely better *feel*
- ❌ ⚠️ **the balance harness dies.** `sweep40` runs 40 fights headless and compares. Without
  reproducibility, every measurement gains a variance term we cannot separate from the effect.
  And resuming a saved cup mid-tournament becomes replay-only.

**C. Hybrid — deterministic sim, presentational physics.** The authoritative fight is
fixed-step and deterministic; physics and animation are a *view* layer that can wobble without
affecting the outcome.

- ✅ determinism where it matters, engine polish where it shows
- ❌ two representations to keep in sync, which is its own bug class

### ⚠️ REVISED RECOMMENDATION (2026-08-03) — physics IS available, with constraints

The user chose physics. **I am revising rather than defending my earlier answer, because I
over-stated the constraint** and because "more fun" is the right tiebreak on a spectator game.

**The honest position: "deterministic" and "physics" are not opposites — "deterministic ACROSS
PLATFORMS" and "physics" are.** Jolt with a fixed physics tick, single-threaded, no RVO, is
reproducible **on the same binary and the same platform**. And that is the only reproducibility
the balance harness actually needs, because it runs on the dev machine, not on a build farm.

**So: option C+ — physics-driven, fixed-step, single-threaded.**

| requirement | how |
|---|---|
| Fixed simulation tick | `_physics_process`, fixed rate, never `_process(delta)` |
| Single-threaded physics | no thread-order variance |
| No RVO avoidance | separation by our own rule, as `engine.ts` does today |
| One seeded RNG stream, drawn in fixed order | already the contract |
| Navigation used to QUERY paths | pathing is a query and is deterministic per navmesh |

**What we give up, stated plainly:**
- ⚠️ **Replays may not reproduce across platforms or across Godot versions.** A 4.7.1 → 4.8
  bump can change solver behaviour.
- **Mitigation:** store replays as **event logs** as well — belt and braces. A recorded fight
  plays back identically forever; only *re-simulation* is version-sensitive.
- **Re-baseline on engine version bumps**, and record the engine version alongside every
  captured baseline.

⚠️ **THE ONE THING THAT MUST NOT SLIP: the balance harness has to keep running headless and
fast.** `sweep40` runs 40 fights. If physics ties the sim to real time, a sweep goes from
seconds to hours and the instrument dies of cost rather than of noise. **Verify early that a
fight can run headless at many times real time** — that is a spike worth doing before
committing, and it is cheap: spawn two bodies, run 1,000 physics ticks headless, time it.

---

## 1. What the model is made of

Six layers. Only the top two are what a player would call "tactics".

| # | layer | question it answers |
|---|---|---|
| 6 | **Orders** | what does the team intend? (`TACTICS_BRAINSTORM.md`) |
| 5 | **Stations** | where should this unit be, in intent? |
| 4 | **Engagement** | who is fighting whom, right now? |
| 3 | **Perception** | what can this unit see and reach? |
| 2 | **Navigation** | how does it get there? |
| 1 | **The field** | what is the ground? |

---

## 2. Layer 1 — the field

### ✅ ELEVATION — DECIDED: FLAT

*"Elevation would be interesting but I think it would add problems for design and
readability."* **Agreed, and the readability half is the stronger argument.** Legibility is a
first-class requirement in a game the player cannot intervene in, and elevation attacks it from
several directions at once: occlusion the camera has to solve, formation shapes resolving onto
uneven ground, AoE becoming volumes, and "why did that miss?" gaining a vertical answer the
player cannot see.

⚠️ **The design cost is the one people underestimate.** Every arena would need its elevation
authored *and balanced* — high ground is a real advantage, so an arena that hands one side more
of it is an unfair arena. That is a per-board balancing job across a 20-board pool.

**What we keep instead:** verticality as *decoration and cover*, not as *ground*. Props can be
tall, arches can be high, the camera can see depth — units simply do not change height.

The historical alternatives, kept for the record:

**Flat (2D positions in a 3D-looking world)** — what exists today.
- Simplest; all current maths survives; cover is vertical geometry on a flat floor.

**Elevated (real 3D ground)** — ramps, platforms, high ground.
- Cover becomes partly *height*, reach becomes 3D distance, "high ground" becomes a real
  tactical prize, and arenas gain a dimension of variety that colour and material cannot give.
- ⚠️ **Costs:** pathing gets harder, the camera has to cope, formation shapes have to resolve
  onto uneven ground, and every AoE becomes a volume rather than a circle.

**My read:** the user's *"the actual arena will be so much larger"* plus *"3D arena, 2D
creatures"* points at **modest elevation — a few tiers, not terrain.** Enough that high ground
and a raised platform mean something; not so much that it becomes a climbing game. But this is
inference and it should be an explicit call.

### Size

⚠️ Every current dimension is provisional. The 40 × 22 field, `DEPLOY_DEPTH 11`, the hex pitch
of 1.4, the density law's 300 sq units per piece — all of it was tuned for a billboard renderer
with a board-fitted camera. **The user has said the arena is a sketch and will be substantially
larger.** Do not carry these numbers forward; re-derive them from what the fight needs.

---

## 3. Layer 2 — navigation

**Use `NavigationServer3D` + baked `NavigationRegion3D` from the arena geometry.** This
replaces `navgraph.ts` (196 lines) and the hand-rolled visibility graph entirely.

- Paths come from `NavigationServer3D.map_get_path()` — a **query**, deterministic for a given
  navmesh.
- ⚠️ **Do NOT use `NavigationAgent3D`'s built-in avoidance for the authoritative sim.** RVO is
  neighbour-order dependent. Use our own separation rule, as `engine.ts` does today with
  `COLLISION_R_FRAC`.
- Re-path on a cadence (the existing `RETARGET_EVERY`), not every tick.

**What we gain over the current model:** real obstacle shapes instead of axis-aligned
rectangles, off-mesh links (jumps, ledges), and navmesh regions that can be tagged — *this area
is cover*, *this area is the deploy zone*, *this is high ground*.

---

## 4. Layer 3 — perception: reach and cover

### 4.1 Reach

**`Area3D` per unit, sized from `reachOf`.** Overlap answers "what is in my reach" without
looping every unit and measuring.

Keep the rule that was paid for twice: **reach is the SHORTER of the best damage move's range
and the class basic.** *Stand where everything in your hands works.*

**What becomes newly possible — shaped reach.** The current model has exactly one shape: a
circle. Godot gives cones, boxes, capsules, arcs. That is the difference between *"a breath
weapon"* and *"a breath weapon that is mechanically a circle"*.

⚠️ Shaped reach interacts with facing (§4.3) — a cone is meaningless without a forward vector.

### 4.2 Cover — the graded model

Today: `segmentHitsRect` returns a boolean and the caller does `continue`. A unit behind a rock
is **untargetable** rather than harder to hit.

**Proposed:** sample N rays from the attacker's muzzle to points across the target's silhouette
(centre, shoulders, low, high). The fraction blocked is the **coverage**.

```
coverage 0.00        clear shot          no penalty
coverage 0.01–0.75   soft cover          accuracy penalty, scaled
coverage 0.76–0.99   heavy cover         large penalty
coverage 1.00        fully occluded      no shot (hard cover only)
```

⚠️ **THE DAMAGE MATH NEEDS NO CHANGE.** `resolveStrike` already sums accuracy in points —
`accuracy - accPenalty + accMod - dodgeMod + flankBonus`. Cover is one more term. This is
already contracted and green in GDScript; only the thing that *computes* the number is new.

**Two decisions inside this:**
- **Soft vs hard cover per prop.** A hedge should tax a shot; a stone wall should stop it. The
  arena authors it. ⚠️ This makes prop choice a balance decision, so it needs a tripwire.
- **Ray count.** More rays = smoother gradient = more cost. Start at 3–5 and measure.

**Cost note:** 5 units × 5 enemies × 5 rays = 125 raycasts per evaluation. At a fixed sim tick
that is fine; at 60fps per-frame it is not. **Evaluate on the decision cadence, not per tick.**

### 4.3 Facing

The engine has no concept of which way a unit looks. Adding a forward vector unifies three
mechanics that are currently three unrelated rules:

- **Backstab** — already exists as `isBehind`, currently a pure position test
- **Flanking** — becomes angular rather than a body count (§5)
- **Directional cover** — a barricade protects from one side, not all four
- **Shaped reach** — cones and arcs need it

⚠️ **And it costs something honest:** facing means a unit can be *caught out of position*, which
means turn rate becomes a stat-like property, which means another thing to balance. `TURN_RATE`
already exists in `types.ts`, so the groundwork is there.

---

## 5. Layer 4 — engagement and flanking

**Define engagement properly:** two units are *engaged* when both are within melee reach of
each other. That is an overlap test between two `Area3D`s, not a distance threshold — which is
what lets flanking key off genuine contact rather than proximity.

**Flanking, reworked:**

```
A target is FLANKED when
  2+ enemies are ENGAGED with it (melee contact, not a radius)
  AND no ally is supporting it (within support distance)
  AND (with facing) those enemies span more than N degrees around it
→ attackers gain +10 accuracy
```

⚠️ **The angular term is what makes it a real mechanic rather than a counter.** Two attackers
stacked on the same side is not a flank; two attackers on opposite sides is. Without facing and
angle, "flanking" is just "outnumbering", which the damage advantage already models.

**Graded:** 2 attackers < 3 < 4, rather than a single on/off bonus.

---

## 6. Layers 5–6 — stations and orders

Covered in `TACTICS_BRAINSTORM.md`. The spatial half of it:

**A station is resolved, not stored.** `Anchor` / `Screen` / `Skirmish` / `Support` / `Free`
are intents. At deploy, a resolver picks an actual position by asking the arena:

- *Anchor* → the most forward navmesh point that holds the line
- *Screen* → between the enemy's likely approach and our back line
- *Support* → behind, **with cover** — the first station that genuinely needs §4.2
- *Skirmish* → a flank approach with a path that is not the main axis

⚠️ **THIS IS WHY STATIONS MUST BE INTENT AND NOT COORDINATES.** A resolver can answer "where is
the cover on this board"; a stored `{x, y}` cannot. And it is why the arena rebuild and the
spatial model have to be designed together — **the arena has to be able to answer these
questions**, which means props and regions need semantic tags, not just meshes.

---

## 7. What Godot gives, concretely

Verified against a live 4.7.1 project during the port.

| tool | use |
|---|---|
| `NavigationServer3D` / `NavigationRegion3D` | pathing, replaces `navgraph.ts` |
| `Area3D` | reach, engagement, deploy zones, cover volumes |
| `RayCast3D` / `ShapeCast3D` | cover sampling, line of sight |
| `game_raycast` (MCP) | **hit, collider path, exact position, normal** — a real LOS instrument |
| `game_debug_draw` (MCP) | ⚠️ **draw reach, cover, flank arcs and SEE them** |
| `game_screenshot` (MCP) | the agent can look at the result directly |
| `game_navigate_path` (MCP) | probe a path without running the game |

⚠️ **THE DEBUG-DRAW AND SCREENSHOT PAIR IS THE REAL UNLOCK.** Every arena failure in this
project's history — the victory arch built inside a stand, the treeline invisible on 9 boards of
14 — was a *seeing* problem. **Ability and combat geometry has never once been looked at.**

---

## 8. Build order

| # | step | why here |
|---|---|---|
| 0 | **Decide determinism (§0) and elevation (§2)** | everything else is downstream of both |
| 1 | Flat navmesh + fixed-step movement | the smallest thing that moves a unit correctly |
| 2 | Reach as `Area3D`, engagement as overlap | unblocks melee and flanking |
| 3 | Cover as graded raycast → accuracy points | the damage math already accepts it |
| 4 | Facing | unifies backstab, flanking, directional cover |
| 5 | Flanking on engagement + angle | needs 2 and 4 |
| 6 | Station resolver | needs a navmesh that can answer questions |
| 7 | Team focus + formation | `TACTICS_BRAINSTORM.md` |
| 8 | Elevation, if chosen | last — it touches everything before it |

⚠️ **Each step needs a `game_debug_draw` probe before it is called done.** The lesson from the
arena work is not "measure more", it is **"look at it"**.

---

## 10. Large arenas change what FORMATION IS

> *"If the arenas are far larger the monsters have more freedom to move around, they dont have
> to conform to a narrow arena. Therefore with a larger arena we can have tactics to stick
> together or to split apart - this will enhance play for assassins."*

**This is a better idea than the seven named shapes and it partly supersedes them.**

### ⚠️ NAME COLLISION — AND A SYSTEM THAT ALREADY HALF-EXISTS (found 2026-08-03)

Flagged by the Systems Designer, verified in source.

**`FieldTraits.cohesion` ALREADY EXISTS** (`tamerengine/types.ts:420`) and it is **a different
concept wearing the same name**: a PER-UNIT personality trait — how much this individual sticks
with its team — not a per-team spacing order.

⚠️ **TWO THINGS CALLED COHESION MEANING DIFFERENT THINGS IS EXACTLY THE TRAP THIS PROJECT
KEEPS HITTING.** Rename the formation axis before either is built. Candidates: **SPREAD**,
**SPACING** (already a tactic name — avoid), **FRONTAGE**, or **DISPERSAL**.

⚠️ **AND THE BIGGER FINDING: THE ARCHETYPE GRID IS ALREADY BUILT.** `types.ts:414-417`
crosses the existing `cohesion` and `predation` traits into a 2x2:

```
high cohesion / low  predation  -> anchor:           holds the line with the team
high cohesion / high predation  -> coordinated dive: team focuses one target
low  cohesion / low  predation  -> skirmisher:       freelances, takes what is near
low  cohesion / high predation  -> assassin:         solo-dives the enemy backline
```

**That is substantially the doctrine axis, already shipped, at the per-unit layer.** Before
authoring Control / Sweep / Strike / Anchor as a new class-level system, decide whether it
should instead be a **team-level layer over the existing per-unit grid** — which would be
cheaper, would not duplicate a working mechanism, and would give the two layers a clean
relationship (the team says what the plan is; the unit says how faithfully it follows it).

⚠️ **DO NOT BUILD A SECOND ARCHETYPE SYSTEM BESIDE THIS ONE WITHOUT DELIBERATELY DECIDING TO.**

### The reframe: COHESION is the primary axis, shape is secondary

On a cramped 40x22 board, formation can only be a shape, because there is nowhere else to be.
Give the team real room and the first and most consequential decision becomes **how far apart
do we fight**:

```
        TIGHT  <-------------------------------->  LOOSE
   mutual support                           board control
   heals and auras reach                    flanks and cutoffs open
   one AoE catches everyone                 nobody can help anybody
```

⚠️ **AND IT IS ALREADY A REAL TRADE-OFF IN THE ENGINE, WITH NOTHING TO EXPRESS IT.** `spacing`
exists as a tactic. `aoeFalloff` judges AoE at three targets. `spreadStatus` (contagion) was
designed specifically to punish clumping and is the one effect never built. **All three answer a
question the deployment never asks** - the comb spaces everyone at a fixed 4-unit interval
regardless.

### Why it enhances assassins specifically

The instinct is right and the mechanism is worth naming. An assassin needs to reach something
squishy. Today it crosses a 4.95-unit gap into a line where everything sits 4 units from
everything else - **there is no isolated target because nothing is ever isolated.**

On a large board with a cohesion axis, **isolation becomes a real state**. A loose enemy has
reachable back-liners; a tight enemy does not. So:

- The **assassin** wants the enemy loose, and is the answer to a loose enemy.
- The **AoE caster** wants the enemy tight, and is the answer to a tight enemy.

⚠️ **That is a counter-pair between two ARCHETYPES rather than between two shapes** - stronger
than the shape web in `TACTICS_BRAINSTORM.md` §2.1, because it makes the choice about the
roster you built rather than a menu you picked from.

**And it gives `Dispersed` from that web its proper home:** it was the one entry that countered
a *kit* rather than a *shape*, which is exactly what a cohesion axis is.

### What this does to the named shapes

They survive as **presets on top of the axis**, not instead of it. `Wedge` is *tight and
forward*; `Split` is *loose with two anchors*; `Box` is *tight and screened*. ⚠️ **Fewer named
shapes than the seven proposed** - the axis does most of the work and the presets are shorthand
a player can name.

### Open: is cohesion static or reactive?

Static is a setting. Reactive - *"open loose, tighten when the caster starts casting"* - is the
parked dynamic-formation idea arriving through a different and more natural door. ⚠️ **Still
parked**, but a cohesion axis makes it far cheaper than swapping whole shapes.

---

## 11. Cover as a VERB, and the kiting rework

> *"Cover needs to be reworked... we want cover to be used to run away to break the enemies
> attack if needed, or for kiting (we need to rework kiting so that they arent running around
> the arena forever)."*

These are the same problem and they have one answer.

### 11.1 What kiting does today, measured

It is **already bounded**, so the complaint is about something else:

| constant | value | meaning |
|---|---|---|
| `KITE_MAX` | 1.2s | a ranged unit may backpedal for at most this long |
| `KITE_REFILL` | 0.5 | refills at half rate, and only once safe |
| `ESCAPE_LOCKOUT` | shared | escape abilities spend a common lockout, so commitment is real |
| `PURSUIT_PATIENCE` / `PURSUIT_PROGRESS` | - | a chaser gives up if it stops closing |

⚠️ **THE BUDGET BOUNDS EACH EPISODE, NOT THE TOTAL.** Backpedal 1.2s, hold, refill, repeat. On
a cramped board that hits a wall almost immediately. **On a much larger board it does not** - the
pattern repeats across the whole arena and the fight drifts.

⚠️ **AND THE PURSUIT RULES MAKE IT WORSE AT SIZE, NOT BETTER.** A chaser that gives up when it
stops closing is correct on a small board and produces *milling* on a large one: chase, give up,
re-acquire, chase. **The real risk of large arenas is not endless kiting - it is a DIFFUSE FIGHT
where engagements are rare and nothing resolves.**

### 11.2 Cover as an ALTERNATIVE to kiting

⚠️ **CORRECTED 2026-08-03 — THIS SECTION ORIGINALLY SAID COVER *REPLACES* KITING AND THAT WAS
TOO ABSOLUTE.** Kiting is a legitimate tactic and stays one. Cover is a second option with a
different shape, not a substitute. The full treatment of the chase problem — including melee
gap-closers, closing speed, minimum range and the crowd meter — is in
`docs/ENGAGEMENT_DESIGN.md`.



Instead of backing away continuously, a unit that wants out **breaks line of sight**.

```
Threatened -> path to the nearest cover that breaks LOS to its attacker
           -> arriving BREAKS the attack (interrupts the cast, drops the lock)
           -> the engagement RESETS: the attacker must re-acquire or reposition
```

| | continuous kiting | cover break |
|---|---|---|
| **Readable?** | a drift, hard to see as a decision | ⚠️ a unit RUNS TO A ROCK. Unmistakable |
| **Finite?** | bounded per episode, unbounded in total | finite - cover is a place, and there are only so many |
| **Uses the arena?** | no; open ground is as good as anywhere | ⚠️ **yes - this is what makes props matter** |
| **Counterable?** | outrun it | flank the cover, or take the angle before they arrive |
| **Fits the vision?** | a drift nobody ordered | a plan the player can watch unfold |

⚠️ **AND IT MAKES THE ARENA A PARTICIPANT.** The biggest risk of "much larger arenas" is that
they become empty space units cross. Cover-as-disengagement makes props **destinations** - the
reason to have a board at all rather than a field.

### 11.3 What that requires

- **Cover must be a queryable LOCATION, not just an occluder.** The navmesh needs to answer
  *"where is the nearest position that breaks LOS to that unit?"* ⚠️ Which is the same thing
  the station resolver needs (§6) - **semantic tags on props, not just meshes.** Two
  systems now want it, so it is a real arena-format constraint.
- **Breaking LOS must INTERRUPT**, or cover is cosmetic. A cast whose target vanishes should
  fizzle or require re-acquisition.
- **A cost**, or breaking is strictly better than fighting. The shared escape lockout is the
  natural place to charge it.
- **A leash.** ⚠️ Even with cover breaks, something must stop a unit crossing the whole board.
  The station system (§6) already provides the anchor to leash against.

### 11.4 The measurement to take FIRST

Before designing any of this, measure the failure it is meant to fix. **Scale the current field
2x and 4x and run `sweep40`.** If fights get longer, more diffuse and less resolved, that
quantifies the diffuse-fight risk and gives the rework a target. If they do not, the problem is
smaller than assumed and the fix can be lighter.

Cheap, uses an instrument that already exists, and exactly the kind of check this project has
repeatedly been glad it ran. ⚠️ **Do it before the baseline is re-established** - it is a
structural question, not a tuning one.

---

## 9. Open decisions

~~1. Determinism model~~ - ✅: **physics-driven, fixed-step, single-threaded (C+).**
~~2. Elevation~~ - ✅: **flat.**

3. **How much larger, exactly?** ⚠️ Answer with §11.4 rather than by taste.
4. **Do props carry semantic tags** (soft cover / hard cover / breaks-LOS / blocking)? ⚠️
   **Now required by TWO systems** - the station resolver and cover-as-disengagement - so it is
   an arena-format decision, not a nice-to-have.
5. **Turn rate** - global constant, per-body-type, or DEX-derived?
6. **Ray count for cover sampling**, and whether coverage maps linearly or on a curve.
7. **Does reach stay a circle at first?** Shaped reach is a large content job - 141 moves would
   each want a shape.
8. **Is cohesion static or reactive?** (§10)
9. **What is the leash?** (§11.3) Station radius, team centroid, or arena zone?
