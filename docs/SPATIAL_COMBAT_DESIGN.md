# Reach, cover and flanking — the spec for the Godot rebuild

**Authored 2026-08-03.** The spatial layer is **not** being ported (see `GODOT_MIGRATION.md`
decision 3). It is being rebuilt on Godot's own navigation and physics, which means the three
mechanics below get *designed*, not transcribed.

This document is the design intent, in the user's own terms, checked against what the
TypeScript engine actually does today. ⚠️ **Two of the three do not match.** That is the whole
value of writing it down: the gap between the mental model and the code is where the rebuild
should start, not the code.

> **The framing:** *"this is how things worked previously, now we have a more powerful engine
> we can expand on all of that."*

---

## 1. Reach

> **"Reach = range or am I mistaken?"**

**Nearly — but the codebase uses two names for two different things, and collapsing them by
accident would be a regression.**

| term | what it is | scope |
|---|---|---|
| `Move.range` | how far THAT ability reaches. The cast is gated on `d <= range`. | per-ability |
| `reachOf(unit)` | the distance the unit tries to **stand at** | per-unit, derived |

`reachOf` is not "the unit's range" — it is a *positioning decision* computed from range:

- Take the range of the unit's **best damage move** — highest `power x (1 + stat/400)`, not the
  longest thing it happens to carry.
- Then take the **shorter** of that and the class's free attack (`CLASS_BASIC`).

⚠️ **BOTH OF THOSE RULES WERE PAID FOR BY A BUG.** Using the *maximum* range across the kit
quietly forbade mixed builds: give a Warrior a fireball and its reach became 7, so it stood at
5.25 and never closed — the fireball did not *add* an option, it *deleted* every melee move in
the kit. Using the minimum was no better: it dragged a Wizard who drafted one stray melee move
into contact.

⚠️ **THE ASYMMETRY IS THE WHOLE ARGUMENT, AND IT SURVIVES ANY ENGINE.** A cast is gated on
`d <= range`. Standing CLOSE never blocks a longer move; standing FAR blocks every shorter one.
So positioning should follow the weapon the monster most wants to use, and anything longer
still fires from there for free. **Stand where everything in your hands works.**

**For the rebuild:** keep the two concepts distinct. `range` is data on the ability; `reach` is
a derived standoff the AI positions around. Godot's navigation changes *how* a unit gets to its
reach, not what its reach should be.

**What Godot makes newly possible**
- Reach as a real **Area3D** rather than a float compared against a distance — so the AI can
  ask "who is in my reach" instead of looping every unit and measuring.
- Reach that is **shaped**, not circular: a cone for a breath weapon, a line for a lance, an
  arc for a sweep. The current model cannot express any of those.
- Reach that respects **elevation**, which the flat 2D field has no concept of at all.

---

## 2. Cover

> **"Cover = provides an accuracy debuff for any attacker (to simulate that cover has an
> effect)"**

⚠️ **THIS IS NOT WHAT THE ENGINE DOES TODAY, AND THE DIFFERENCE IS LARGE.**

Today cover is **binary occlusion**. `hasLineOfSight` returns false if any obstacle rectangle
intersects the straight segment between attacker and target, and the caller does this:

```ts
// engine.ts:404
if (mv.channel !== 'melee' && !hasLineOfSight(u.pos, target.pos, obstacles)) continue
```

`continue` — the move is removed from consideration entirely. So a unit behind a rock is not
*harder* to hit by ranged and magic; it is **untargetable** by them. Cover is an on/off switch.

**Consequences of the current model, all of which the described model fixes:**
- Cover is worth either everything or nothing, so positioning is a binary rather than a
  gradient — there is no such thing as *partial* cover, and no reason to prefer good cover to
  adequate cover.
- The edges are brutal: half a step sideways flips a target from immune to fully exposed.
- Melee ignores it completely (`mv.channel !== 'melee'`), so cover only ever taxes half the
  roster.
- It composes badly with the density law: more props on a board means more total occlusion,
  so arena decoration silently becomes a balance lever.

**The intended model:** cover applies an **accuracy penalty** to any attacker whose line to the
target is obstructed. Graded, not binary.

⚠️ **THE HOOK ALREADY EXISTS AND IS ALREADY IN THE PORT CONTRACT.** `resolveStrike` takes
accuracy as percentage POINTS and already sums `accuracy - accPenalty + accMod - dodgeMod +
flankBonus`. A cover penalty is one more term in that sum — the damage math needs **no change**
at all. Only the thing that computes the number is new, and that thing is spatial, which is
exactly the layer being rebuilt.

**Open design questions**
- **Is it graded by how much is blocked**, or one flat penalty for "obstructed"? Graded is more
  interesting and Godot can measure it (multi-ray coverage sampling); flat is legible.
- **Does cover ever fully block?** A solid wall probably should. Suggest a two-tier model: soft
  cover = accuracy penalty, hard cover = no shot — with the arena authoring which prop is which.
- **Does melee care?** Currently exempt. Probably still exempt, but say so deliberately.
- **Is cover directional?** A barricade should protect from one side, not all four.
- **Does taking cover cost something?** Otherwise every unit hugs a rock and the fight stalls.

**What Godot makes newly possible**
- `game_raycast` returns hit, collider path, exact position and normal — a real occlusion probe
  rather than a rectangle-segment intersection test. **Multi-ray sampling gives a coverage
  FRACTION**, which is precisely the number a graded model needs and which the current engine
  cannot produce.
- `game_debug_draw` can render cover volumes and the rays themselves, so cover becomes something
  we can *look at*. ⚠️ Every "authored but invisible" failure in this project's arena work was a
  *seeing* problem; cover has never once been visualised.
- Real geometry means cover can be a mesh, not a rectangle — pillars, arches, low walls that
  block a standing shot but not a lobbed one.

---

## 3. Flanking

> **"when multiple units are in melee combat with a LONE enemy, that enemy is flanked and is
> more likely to get hit (opponents will have +10% accuracy)"**

**The shape matches. Two details do not.**

Today (`engine.ts:854-877`):

| rule | today | the description |
|---|---|---|
| attackers needed | **2 or more** | "multiple units" ✅ |
| target must be unsupported | **no ally within 2.5 units** | "a LONE enemy" ✅ |
| the bonus | **+5 accuracy points** | **"+10%"** ⚠️ |
| what counts as "on it" | **any enemy within 4.0 units** | **"in MELEE combat with"** ⚠️ |

**Discrepancy 1 — the bonus is 5, not 10.** `FLANK_ACC_BONUS = 5`. Either it was tuned down at
some point or the +10 is the intent rather than the history. ⚠️ Worth a deliberate decision
rather than a silent restore: 5 points on a 90-accuracy move is a 5% relative swing, 10 points
is 11%, and the standing balance rule says one value at a time with the sign test.

**Discrepancy 2 — "on it" is a radius, not melee engagement.** `FLANK_ENGAGE_RADIUS = 4.0`
counts *any* living enemy inside 4.0 units, including a ranged attacker who merely happens to
be standing there. The description says *in melee combat with*. Those are different mechanics:
one rewards **proximity**, the other rewards **committing to contact**. The second is a better
game — it means a flank has to be *earned* by the units that accept the risk of being in reach.

⚠️ **AND THE TWO RADII HAVE ALREADY BEEN FIXED ONCE EACH, SO TREAT THEM AS LOAD-BEARING.**
`FLANK_ENGAGE_RADIUS` was 2.6 — *below* `CLASS_BASIC`'s melee band of 3.0 — so a melee attacker
standing at its own correct distance did not count as engaged, and the mechanic was blind to
exactly the situation it exists for. `FLANK_SUPPORT_RADIUS` was wider than engage, so a defender
counted as protected by an ally standing further away than the enemies attacking it.

**For the rebuild:** flanking should key off **melee engagement**, not distance. Godot gives a
literal answer to "is this unit in melee contact with that one" via overlapping reach areas, so
the radius fudge stops being necessary.

**What Godot makes newly possible**
- **True flanking by ANGLE, not just count.** The real mechanic is being attacked from two
  directions at once. `isBehind` already exists for backstab; the same vector maths generalises
  to "these attackers span more than N degrees around the target". That is a much better rule
  than counting bodies, and it makes formation and facing matter.
- **Graded flanking**: 2 attackers < 3 < 4, rather than a single on/off bonus.
- **Facing.** The current engine has no concept of which way a unit is looking. With facing,
  flanking, cover and backstab all become one coherent family instead of three separate rules.

---

## 4. ⚠️ The CON control-resist floor — CONFIRMED FOR REWORK

Found while building the port contract (`status.json`, axis `conFloor`). **The user has called
this for rework.**

`statusMath.ts:applyStatus` puts a floor under the CC diminishing-returns meter so a high-CON
unit cannot be chain-controlled the way a caster can:

```ts
const conFloor = Math.min(0.3, (inp.targetCon ?? 0) / 3000)
```

⚠️ **IT SATURATES AT CON 900, WHICH IS EXACTLY THE PLATINUM CAP.** The divisor reads as though
it scales to 3000 and it does not — `0.3` is reached at 900 and never moves again.

| league | stat cap | CON floor |
|---|---|---|
| Wood → Gold | 100 – 750 | 0.033 → 0.250 — a real gradient |
| **Platinum → Tamers Apex** | **900 – 1100** | **0.300, flat** |

**So CON buys ZERO additional control resistance across the entire 5v5 band the game is
balanced for** (`CLAUDE.md`: *"The game is a 5v5 game"* — Platinum and above). The mechanic
stops differentiating precisely where the shipping game lives, and a Juggernaut trained to the
Apex cap resists control exactly as well as one that stopped at Platinum.

**Proposed fix — reuse the shape the project already uses for mitigation.** `mitigationFor`
solves the identical problem (more stat must always mean something, with diminishing returns)
using a soft knee rather than a hard cap. Applying the same idea:

```
raw = CON / 3000
floor = raw <= KNEE ? raw : min(CEIL, KNEE + (raw - KNEE) * SOFT)
```

with `KNEE ≈ 0.20`, `SOFT = 0.5`, `CEIL ≈ 0.45`, giving:

| CON | today | proposed |
|---|---|---|
| 300 | 0.100 | 0.100 |
| 600 | 0.200 | 0.200 |
| 900 (Platinum) | **0.300** | 0.250 |
| 1100 (Apex) | **0.300** | 0.283 |
| 1650 (Apex × 1.5 potential) | **0.300** | 0.375 |

Still diminishing, never flat, and consistent with how the codebase already expresses "more
stat always helps, but less and less".

⚠️ **DO NOT LAND THIS AS A DRIVE-BY.** It is a live balance change: it moves the goldens, and
`tools/sweep40.ts` is calibrated against the current spread. Two honest routes —

1. **Do it in the new engine**, where the whole control model is being rebuilt anyway and the
   numbers are being re-derived rather than preserved. Cheapest, and the change lands with its
   siblings.
2. **Do it in TypeScript now**, as its own paired A/B (`tools/ab.ts`, judged on the sign test
   per the standing rule), so the effect is measured against today's baseline before the
   rebuild scrambles the reference.

Route 2 is worth it *only* if we want the measurement; route 1 is right if the control model is
being reconsidered wholesale. **Decision outstanding.**

---

## 5. Re-auditing the abilities — what Godot does and does not give us

> **"is there anything in godot we can use to go back over the abilities to work this out?"**

**Split the question, because the two halves have different answers.**

### The NUMERIC audit already exists, in TypeScript, and it is not telling us much

`tools/pool.ts` is built and runs today. It compares every damage move against four references
in descending order of trustworthiness: the free attack, same-line lower-level moves,
same-stat/same-level cohort medians, and the designed per-stat tier.

Current output: **0 flags across 77 damage moves.** ⚠️ **That is a statement about the
THRESHOLDS, not about the pool.** Its own distribution table says so:

| stat | n | min | p25 | med | p75 | max |
|---|---|---|---|---|---|---|
| STR | 15 | 10.2 | 16.7 | 25.4 | 96.4 | 120.2 |
| DEX | 19 | 11.8 | 16.8 | 28.2 | 94.7 | 125.2 |
| CON | 9 | 10.5 | 13.2 | 19.6 | 27.6 | 40.8 |
| WIS | 9 | 7.2 | 10.8 | 16.6 | 32.3 | 47.4 |
| **INT** | 17 | **5.9** | 12.1 | 43.1 | 76.0 | **184.0** |
| CHA | 8 | 6.2 | 11.1 | 26.6 | 51.4 | 95.0 |

**INT spans 5.9 to 184.0 — a 31x spread inside one stat — and nothing flags.** A tool that
passes that is not yet an instrument. ⚠️ The tool prints *"pick thresholds from this, do not
trust the ones hard-coded above"*, which is the tool telling us it has not been calibrated.
**That is a TypeScript job and it does not need Godot at all.** Doing it in Godot would mean
porting the audit before calibrating it — work in the wrong order.

There is a live plan for exactly this (`.claude/plans/agile-conjuring-sphinx.md`). Its Step 1
(cooldowns in seconds) is **done**; Step 2 built `pool.ts`; **Step 3 — working the flagged list
together — never happened, because the list came back empty.** Calibrating the thresholds is
what unblocks it.

### The SPATIAL audit is the half that was never possible, and Godot unlocks it

Everything the numeric audit *cannot* see is geometric, and every one of these has gone
unexamined because there was no way to look at it:

| question | why it was unanswerable | what Godot gives |
|---|---|---|
| Does this AoE actually cover 3 bodies at realistic spacing? | AoE is judged at 3 targets *by assumption* | `game_debug_draw` the actual volume against a real formation |
| Is this move's `range` reachable given where its class stands? | reach is derived, range is authored, nothing compares them | overlap the reach Area3D with the range volume and look |
| Does cover ever actually block this ability in practice? | binary LOS over rectangles, never visualised | `game_raycast` with real geometry, drawn |
| Do the 18 lines have distinguishable *shapes*, not just numbers? | there is no shape — everything is a radius | shaped volumes, seen side by side |
| Which abilities are never cast because the AI can't get in position? | invisible; looks like a balance problem | run headless, log casts, screenshot the failures |

⚠️ **AND THE BIGGEST ONE IS SIMPLY THAT THE AGENT CAN SEE.** `game_screenshot` returns a PNG
directly. Every arena failure in this project's history — the victory arch built inside a stand,
the treeline invisible on 9 boards of 14, the mosaic that averaged to flat grey — was a *seeing*
problem worked around by POSTing canvas blobs to a dev-server middleware. Ability geometry has
never been looked at even once.

**Recommendation:** calibrate `pool.ts` in TypeScript (it is cheap, it is built, and it is
blocking the pool review); build the spatial audit in Godot as the new engine's geometry lands.
Do not port the numeric audit.

---

## 6. Standing note: much of this is first-draft and meant to be expanded

> **"a lot of this will need to be rewritten, we wrote a lot of this at the time and it needs
> to be expanded on."**

⚠️ **TREAT THE CURRENT SPATIAL RULES AS A PROTOTYPE, NOT AS A SPEC.** They were written against
a flat 2D field with rectangle obstacles, no facing, no elevation, and a renderer that could not
show them. Every constant in this document (4.0, 2.5, 5, 0.3, 3000) was tuned inside those
limits. When the same mechanic is expressed on a real 3D navigation mesh, the *rule* is what
carries over — the *number* has to be re-derived.

The parts genuinely worth preserving, because they came from the sim rather than from the
renderer:
- **Stand where everything in your hands works** — the reach asymmetry (§1).
- **Cover exists to break straight lines and create decisions**, not to decorate.
- **A flank must be earned**, and support must be able to answer it (§3).
- **Control needs a hard cap**, or resource-denial plus action-denial is unanswerable (§4).

Everything else is open.
