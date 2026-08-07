# Pathfinding — design plan

**Status:** Stage 4a (instruments), **Stage 0 and Stage 1 SHIPPED**. Freeze lifted. Stage 3 is
DECIDED (§5: A + F on independent cooldowns + a ~5s shared lockout). Stage 2 (cover as a resource) is next. **Branch:** `3doverhal`.

The goal, in the user's words: *monsters that navigate around obstacles, use them to
their advantage, and — ideally — a support running around a pillar to escape an
assassin.*

---

## 1. What is actually wrong

`src/tamerengine/engine.ts:1533` — `stepToward()` — is the **entire** navigation
system:

```
aim straight at the goal
  → try the full step
  → else slide along x
  → else slide along y
  → else a fixed perpendicular nudge
```

No A*, no navmesh, no waypoints, and **no memory between ticks**. Every tick
re-decides from scratch, so a unit slides left, the goal vector shifts a degree, and
it slides back right. Cover is not something a monster understands; it is something it
bumps into.

### The measurement — BASELINE (`npx tsx tools/navdiag.ts`)

⚠️ **Built first, before any fix.** These are the numbers Stage 0 and Stage 1 are
graded on. `sweep40` reported Titan's Rest at an ordinary-looking 38/40 while a third
of its unit-fights were inert, so nothing here gets graded on `resolved`.

| arena | size | resolved | **deadlocked** | stuck% | of which cover | wander |
|---|---|---:|---:|---:|---:|---:|
| Dustbowl | 34×20 | 37/40 | **0**/240 | 1.3% | 100% | 2.16 |
| The Ossuary | 48×26 | 30/40 | **3**/240 | 37.6% | 100% | 2.48 |
| Titan's Rest | 64×34 | 0/40 | **80**/240 | 56.6% | 100% | 3.31 |

Three things the first hand-probe got wrong or could not see:

- **It is not two units, it is all six.** The probe read one seed and found Zarok and
  Sylix. Across 40 fights every slot on Titan's Rest deadlocks in some of them —
  A0 16×, B1 18×, A1 13×, B0 13×, A2 11×, B2 9×. It is a property of the arena, not of
  two unlucky spawns.
- **The Ossuary was hiding it.** 30/40 resolved looks merely mediocre; 37.6% of all
  movement attempts failing does not.
- **⚠️ `of which cover` is 100% on all three arenas.** Every stuck tick, everywhere, is
  against an obstacle. That is an unusually clean attribution: there is no second,
  unrelated cause to hunt, and Stages 0–1 are aimed at the whole problem rather than
  part of it.

**The two bugs separate exactly as designed.** Dustbowl has ~no deadlock (1.3% stuck)
but still wanders 2.16× — chronic without catastrophic. A single blended "navigation
health" number would have hidden that; two numbers show a map can be fine at one and
bad at the other.

### The original single-seed probe

Per-unit, from the three arena dumps. `frozen` = ticks where the unit moved < 0.02
units; `hugging` = ticks spent within 1.2 units of an obstacle; `wander` = path length
÷ net displacement.

| arena | unit | alive | frozen | hugging | path | net | wander |
|---|---|---:|---:|---:|---:|---:|---:|
| Titan's Rest | **A2 Zarok** | 750 | **100%** | **100%** | **0.0** | **0.0** | — |
| Titan's Rest | **B1 Sylix** | 750 | **100%** | **100%** | **0.0** | **0.0** | — |
| Titan's Rest | A3 Bruus | 623 | 24% | 2% | 111 | 29.4 | 3.8× |
| The Ossuary | A2 Zarok | 209 | 61% | **92%** | 11 | 8.2 | 1.3× |
| Dustbowl | A2 Zarok | 148 | 40% | 53% | 22 | 4.6 | **4.7×** |

⚠️ `frozen%` **alone is not the metric** — 40–86% is normal and healthy (casting,
standing in range, blocked by an ally). The signal is `frozen` **and** `hugging`
together.

### Two distinct bugs, not one

**Bug 1 — spawn-inside-obstacle is a permanent deadlock.** Zarok and Sylix never move
once, across all 750 ticks. `tryMove` rejects any position inside an inflated
obstacle; a unit that *starts* inside one has every candidate rejected, including the
perpendicular escape nudge. There is no push-out. Two units — one per side — are
inert dead weight for the whole fight, which is the real reason Titan's Rest resolves
0/40.

> ⚠️ **This was self-inflicted, and the lesson is worth more than the bug.** The first
> `mapProblems` rejected any obstacle inside a deployment band. All three maps failed,
> and that was read as a miscalibrated check ("cover near spawn is a design choice,
> and `mirror()` already guarantees fairness") — so it was relaxed to a 15% crowding
> threshold. The *conclusion* was wrong because the *hazard* was misidentified: the
> danger was never fairness, it was spawn-deadlock. **"When many things fail a check,
> suspect the check" is a heuristic, not a law** — it says look at the check, not
> assume it is wrong. Restore the strict guard.

**Bug 2 — no pathfinding.** Chronic rather than catastrophic: 4.7× wander on
Dustbowl, 92% cover-hugging on Ossuary. Units reach their goal eventually, by
scraping along geometry.

### What this reverses

An earlier commit (`a27f774`) attributed Titan's 0/40 to *small obstacles breaking
line of sight, so a shooter re-acquires forever*. That was a plausible story fitted to
an isolation table, and it is **wrong**. The isolation result itself still holds —
rubble breaks the map, the massif does not — but the mechanism is spawn-deadlock plus
wall-scraping, not a LoS dance. The small blocks are lethal because they are small
enough to sit **inside a deployment band**; the massif is harmless because it is dead
centre where nobody spawns.

---

## 2. Stage 0 — bugs, not features

Cheapest work, largest single win, and it is all correctness.

- **Push-out at spawn.** Any unit initialised inside an inflated obstacle is moved to
  the nearest free point before tick 1.
- ~~**Restore the strict deployment-band guard** as a hard error.~~ ⚠️ **REVERSED ON
  IMPLEMENTATION.** Push-out fixes the *cause*, and once a unit spawned in cover is
  simply nudged clear, cover inside a spawn band stops being a deadlock and goes back
  to being a legitimate design choice — WoW arenas have pillars near starting
  positions. Both earlier positions were half-right: the original strict check was
  reading a real hazard, the relaxation was right that fairness was not it, and
  *neither* spotted that the engine was missing a push-out. Fix the cause, keep the
  freedom. The crowding check (>15% of a band blocked) stays, since that one is about
  whether a team can seat at all.
- **No terminal blocked state.** "All four `tryMove` candidates rejected" must be
  impossible to remain in — escalate to a scan of headings rather than one fixed
  perpendicular.

**Acceptance:** `deadlocked` → 0 on all three arenas (`npx tsx tools/navdiag.ts`).

### ✅ SHIPPED — and it was THREE bugs, not two

| arena | resolved | deadlocked | stuck% | wander |
|---|---|---|---|---|
| Dustbowl | 37 → **38**/40 | 0 → 0 | 1.3% → **0.0%** | 2.16 → 2.06 |
| The Ossuary | 30 → **35**/40 | 3 → **0** | 37.6% → **0.1%** | 2.48 → 2.61 |
| Titan's Rest | 0 → **39**/40 | 80 → **0** | 56.6% → **0.1%** | 3.31 → 2.45 |

⚠️ **BUG 3, WHICH THE PLAN DID NOT PREDICT — a "move" that succeeds at moving
nothing.** Push-out and the escape scan fixed Titan's Rest (0 → 37/40) and left
Dustbowl and Ossuary *byte-identical*. A change that moves one arena and leaves two
unchanged to the decimal is not a partial success, it is a signal the code path is
never reached.

The cause: `tryMove(nx, u.pos.y)` — the x-slide. Walk straight at a horizontal wall and
`dir.x` is ~0, so the slide's destination **is the current position**. It is not inside
the obstacle, so `tryMove` returned **true**. The unit travelled zero distance, and
because the `&&` chain short-circuits on that success, the escape fallback never ran.
1180 of 1219 stuck ticks on The Ossuary were exactly this — units pressed against
cover, "succeeding" at standing still, every tick, forever.

Rejecting any candidate that displaces less than `step × 0.25` fixed all three arenas
at once.

**How it was found matters more than the fix.** Three hypotheses were tested and
discarded before it: that the metric was over-reporting (killed by running the same
fights with **no obstacles** — 24.5% stuck with cover, **0.2%** without, so the ticks
really were geometry); that the collision-separation pass was shoving units into rocks
(it already checks obstacles); and that units were wedged *inside* the pad (only 21 of
1219 were — the rest sat a median 0.66 out from it, pad 0.54). Each probe eliminated a
class of cause, and the last one pointed straight at "blocked while outside the pad",
which is only possible if a move candidate was being accepted without moving.

**Wander is unchanged (~2.1–2.6), exactly as the plan wanted.** Catastrophic fixed,
chronic untouched — that is Bug 2, and it is Stage 1's job.

⚠️ **The three field goldens were recaptured**, deliberately, in the same commit. Two
flipped their winner, and the flips are the fix working: `duel-melee` went 57.7s → 14.6s
(a golden literally titled *"a bruiser against a wall"* had been running to sudden death
because the melee could not get past the rock), and in both flips the melee side now
reaches the fight instead of hanging on geometry.

---

## 3. Stage 1 — real pathfinding

Obstacles are axis-aligned boxes and they never move: the easy case. **The shortest
path in a box world only ever bends at box corners.**

**Recommended: visibility graph + A*.**

- Build once per battle from the arena's obstacles (they are static), so it is not
  per-tick work.
- Nodes = obstacle corners inflated by unit radius, plus start and goal.
- 3–7 obstacles ≈ 28 nodes. Trivial to search.
- Hand `stepToward` the **next waypoint** instead of the raw goal.

The layering is the point: a **global path layer** picks the waypoint; the **existing
local steering layer** keeps doing separation, backpedal and collision-slide. No
rewrite of what already works.

### ✅ SHIPPED — `src/tamerengine/navgraph.ts`

| arena | resolved | stuck% | **wander** |
|---|---|---|---|
| Dustbowl | 38 → **39**/40 | 0.3% | 2.06 → 2.10 |
| The Ossuary | 35 → **39**/40 | 0.3% | 2.61 → **1.69** |
| Titan's Rest | 39 → **40**/40 | 0.0% | 2.45 → **1.61** |

`sweep40` **38/40 @ 20.8s → 39/40 @ 18.8s**. Every arena now resolves, and Titan's Rest
— which was 0/40 two commits ago — is perfect.

Built as designed: static graph, inflated corners, A* with index-order tie-breaks for
determinism, and **one changed line in the engine** — `stepToward` receives
`nextWaypoint(...)` instead of the raw goal. The local steering layer is untouched, so
every behaviour tuned into it (separation, backpedal, the escape scan, the
zero-displacement rejection) still applies.

⚠️ **Wander barely moved on Dustbowl (2.06 → 2.10), and that is correct, not a
shortfall.** Dustbowl is 1.9% cover — there is almost nothing to route around, so its
wander was never pathfinding waste. It is kiting and repositioning, which is movement
we WANT. The plan's "< 1.5 everywhere" target was wrong: it assumed all wander is
waste. On the cover-heavy arenas, where the metric does measure routing, it fell by
~35%. **Wander is only a pathfinding metric in proportion to how much cover a map has.**

⚠️ **A test fixture failed and the CODE was right.** The first "drops a swallowed
corner" case used two equal-height blocks side by side — which swallows nothing, since
every seam corner sits above or below both blocks and is genuinely standable. Replaced
with a small block against the face of a bigger one, which buries exactly two corners.
Fixtures must pin the variable they claim to test.

**Cheaper first cut, not taken:** commit-to-a-side wall-following with hysteresis —
when blocked, choose the tangent nearer the goal **once** and hold it for K ticks or
until the goal is in line of sight. That kills the oscillation, which is the actual
failure mode, without a graph. ⚠️ But it does **not** unlock Stage 2 — you cannot ask
"where should I stand so the assassin cannot see me" without a path cost to candidate
points.

---

## 4. Stage 2 — cover as a resource

Only reachable once Stage 1 exists.

- **Break LoS to flee.** A hurt support scores candidate points around nearby cover on
  *does this block the threat's line to me*, not merely *is this away from them*. That
  is running around a pillar.
- **Peek.** Ranged units prefer standing where they hold LoS to the target while the
  nearest melee threat has no *short path* to them. Path length, not straight-line
  distance — this is why it needs Stage 1.
- **Cut-off pursuit.** The assassin paths to the interception point around the pillar
  rather than chasing the support's current position. ⚠️ **This is the single change
  that makes the behaviour read as intelligent rather than as a conga line** — and see
  §5, it is also what makes the retreat budget a real bound.

### The two arena rules (from high-level WoW arena play)

Arena LoS has two halves, and the plan originally only had the defensive one.

**Offensive — the isolation targeting term.** *Capitalising on players who are out of
line of their healers.* Non-melee target scoring gains a term for **"this enemy has no
living support in line of it"**.

⚠️ **This is a candidate fix for FOCUS FIRE (P6)**, the top unsolved item on the
tamerengine list, where two numeric levers (the mitigation cap, the maxHp coefficient)
both measured null. The reason they failed is visible in `decide.ts:147`: today's
focus-fire signal is `focusCount` — *how many allies are already committed to each
enemy*. That is **follow-the-herd**, and it is self-referential. It has no anchor
outside itself, so it amplifies whatever arbitrary choice happened first and converges
weakly.

"Is this enemy cut off from its support?" is **exogenous**: every attacker reads it off
the same geometry, independently, and agrees without watching each other. That is a
real convergence mechanism rather than a social one — and it brings timing with it,
because the window opens and shuts as the enemy healer repositions. It also puts the
pressure on the enemy support's POSITIONING rather than its health bar, which is what
makes the whole board matter.

⚠️ **Melee must keep targeting NEAREST.** `decide.ts:130` is explicit: *"No
value/priority chase here: that cross-map hunt is exactly what made melee race around
the map."* The isolation term is for ranged and casters only, or a fixed bug returns.

**Defensive — threat-type-aware cover.** Breaking LoS means different things depending
on who is chasing, and one rule for both gives a support that hides pointlessly from a
warrior while standing in the open against an archer:

| chased by | what cover does | what to score |
|---|---|---|
| **ranged / caster** | genuinely hides you — they cannot cast | block their **sight line** |
| **melee** | does *not* hide you (melee is LoS-exempt, correctly — it is adjacent) | block their **dash line** (a charge needs LoS to its destination, `engine.ts:1477`) and **lengthen their path** |

⚠️ **The organic bound only covers the ranged case.** Because every non-melee channel
including `support` requires LoS (`engine.ts:284`), a monster hiding behind a pillar
**cannot heal** — hiding costs you your own output, which is exactly why pillar-hugging
is not degenerate in WoW. But that self-limiting property does **not** apply against a
melee assassin, which is the scenario §5's cooldown exists for. Measure the two
separately: the ranged case may already be taxed enough by the LoS symmetry, and
applying the same 15s to both could be double-charging.

---

## 5. Stage 3 — bounding retreat (the open decision)

⚠️ **"A support escapes the assassin" and "fights resolve" are in direct tension.** If
breaking LoS is free, a support kites forever and the sim returns to 0/40 — the same
symptom as today with a brand-new cause, which will read as a regression of the thing
Stage 0 just fixed. **Decide the cost before building the behaviour.**

### ⚠️ First: two behaviours, not one

| | what it is | cadence | current mechanism |
|---|---|---|---|
| **Micro-kiting** | a ranged unit shuffling back to hold range | continuous | `KITE_MAX` 1.2s / `KITE_REFILL` 0.5 + 0.6× backpedal |
| **Retreat** | a discrete break of contact and reposition | 2–3 per fight | **does not exist** |

A cooldown belongs on **retreat**. Putting one on micro-kiting makes archers walk into
melee. The existing 1.2s budget is not a small version of retreat — it is a different
system, and it stays as it is.

### The options

| | mechanism | tune cost | legibility | risk |
|---|---|---|---|---|
| **A. Cooldown** | one Fall Back per N seconds | **1 number** | high — a visible event | binary; can be spent early |
| **B. Stamina** | drain while retreating, refill when safe | 2 numbers | low — invisible continuous state | is what produced the pursuit equilibrium that needed the backpedal hack |
| **C. Charges per fight** | N retreats, no refill | 1 number | highest | nothing left late in a long fight |
| **D. Escalating cost** | each retreat costs more | 2 numbers | medium | elegant, opaque |
| **E. Diminishing effect** | each retreat moves you less | 2 numbers | low | reads as the unit silently degrading |
| **F. Make it an ability** | Disengage / Shadowstep: MP + slot + cooldown | **0 new systems** | high | only monsters that drafted it can do it |

### ✅ SHIPPED — 3a, Fall Back

`FALL_BACK_CD` 15s · `FALL_BACK_DUR` 2s · `ESCAPE_LOCKOUT` 5s · triggers at
`FALL_BACK_HP` 40% or a melee threat inside `FALL_BACK_NEAR` 3.5 (anchors excepted —
a tank holding a line is not supposed to leave it).

**Acceptance, both halves, measured:**

| | before 3a | after 3a |
|---|---|---|
| survival rate of hunted units | 33–39% | **36–40%** |
| mean `survivedFor` | 9.4–11.5s | **9.8–12.0s** |
| `sweep40` | 40/40 @ 17.8s | **40/40 @ 19.3s** |
| min gap between one unit's fall-backs | — | **15.00s** (exactly the cooldown) |

✅ Positive — hunted units last longer. ✅ Bounded — survival rose ~3 points and is
nowhere near 1.0; prey still dies ~60% of the time. ✅ Fights still resolve, 40/40, at
a cost of 1.5s.

Fires ~4.8 times per fight across six units, i.e. **about once each** — all a 15s
cooldown allows in a ~19s fight — and appears in 23–24 of every 24 fights. The min-gap
floor confirms the cooldown is real rather than nominal.

⚠️ **AND IT WEAKENED THE THING IT WAS MEANT TO SUPPORT.** Cover's contribution to
survival was +13%/+17% on the two cover-heavy arenas before 3a; now Dustbowl and
Titan's Rest read *slightly negative* and only Ossuary stays positive. A universal
escape that works anywhere makes the ground matter less — which is the opposite of the
arena play this whole line of work is for. Not a bug, a genuine design tension, and an
argument for keeping Fall Back weak and letting the ABILITY tier (3b) be the one that
uses cover properly.

### ✅ SHIPPED — cover-seeking retreat (Fall Back picks a DESTINATION)

⚠️ **3a made cover worse, and this is the fix.** A universal escape that works
anywhere makes the ground irrelevant: Fall Back retreated to `position + away × 10`,
a straight line, so cover only helped when a rock happened to lie in it.

Fall Back now keeps its speed (the suspended backpedal) but **chooses where to run** —
scored over the nav graph's corner nodes, which already are the "around the pillar"
points. Cover's contribution to survival:

| arena | with cover | none | delta | *(at 3a)* |
|---|---:|---:|---:|---:|
| Dustbowl | 9.6s | 10.1s | −5% | −3% |
| **The Ossuary** | **12.6s** | 11.1s | **+14%** | +4% |
| **Titan's Rest** | **13.0s** | 12.0s | **+8%** | −2% |

Survival 35–38%: still inside the 35–45% band, so **bounded**. `sweep40` 39/40 @ 19.4s.

⚠️ **THE MAP DOES THE BALANCING, NOT A CONSTANT.** When no candidate beats running
away, Fall Back degrades to exactly its old straight-line behaviour — which on a bare
arena is every time. An arena with pillars makes retreat strong; an empty one does not.
That is why Fall Back needed no weakening to stop competing with cover.

Three details that each prevent a specific failure:

- **Destination chosen ONCE, at trigger.** Re-scoring per tick as the threat moves
  makes a "committed" retreat oscillate on the spot instead of going anywhere.
- **Never retreat INTO the threat.** A corner can break line of sight while sitting
  *closer* to the attacker — a hiding place you die in.
- **Prefer corners still in sight of the team.** LoS is symmetric, so a support that
  cannot see its allies cannot heal them; a corner that abandons the fight is worth
  less than one that merely breaks the chase.

### ✅ SHIPPED — 3b, the escape abilities (and the cooldown that makes them premium)

⚠️ **They already existed and nothing could equip them.** All 18 field moves were
unreachable — `learnedMoves` filters `ALL_MOVES` only. Backstep *is* Disengage, Blink
*is* Teleport, Fade is the fourth flavour. 3b was wiring, not authoring.

**The cooldown was the whole design, and it took three passes to price:**

| | authored | first fix | final | result |
|---|---:|---:|---:|---|
| Backstep | 5 | 12 | **19** | |
| Fade | 7 | 13 | **21** | |
| Beckon | 6 | 11 | **17** | |
| Blink | 6 | 16 | **26** | longest — it ignores cover |
| `sweep40` | 34/40 @ 26.8s | 37/40 @ 20.2s | **38/40 @ 20.3s** | |
| escapes/hunt | ~1.2 | ~1.2 | **~0.7** | |

⚠️ **"PREMIUM" MEANS ONCE A FIGHT, NOT MERELY RARER.** At 12s against a ~20s fight an
escape still bought two uses — a rhythm rather than a decision, and fights sagged to
26.8s with cover's contribution *inverted*. At ~19–21s a monster gets exactly one, and
drafting Blink buys ONE guaranteed unanswerable escape.

**And that is what finally made cover a strong mechanic — on every arena:**

| arena | with cover | none | delta |
|---|---:|---:|---:|
| Dustbowl | 11.7s | 10.1s | **+16%** |
| The Ossuary | 12.8s | 11.0s | **+16%** |
| Titan's Rest | 13.3s | 11.4s | **+17%** |

Survival 31–38%, still inside the band — on Ossuary cover pairs with a *lower* rate
than no cover (31% vs 37%), which is exactly right: **cover buys time, not immunity.**

⚠️ The lesson generalises past this feature: **a cheap escape does not make escaping
matter, it makes committing impossible.** Every earlier number moved the wrong way
until the ability became a once-per-fight decision.

### DECIDED — **A and F, on independent cooldowns**

Both tiers ship. A monster therefore has **two escapes**, and the ability does *not*
consume the baseline cooldown. That is deliberate: it creates the two-beat moment
(*caught → Disengage → still caught → Fall Back*) and keeps the ability strictly
premium rather than a sidegrade.

- **A — Fall Back.** Universal, ~15s cooldown, trigger-gated. Ordinary movement speed.
- **F — an ability.** Own cooldown, MP cost, occupies a loadout slot. **Faster to its
  destination**, which is the whole reason to draft it.

**Suggested mechanic for Fall Back, using a lever that already exists:** for its ~2s
duration it **suspends the 0.6× `BACKPEDAL_MULT` penalty**. That is what separates a
retreat from ordinary kiting — the unit genuinely outruns its pursuer for two seconds
— and it needs no new speed constant.

#### The three ability flavours map onto vocabulary the engine already has

`core.ts:300` already carries the exact distinction, and its comment already states
it: *"`dash` crosses the ground and IS blocked by cover; `blink` is instantaneous and
ignores it — that difference is the whole reason to want a blink."*

```ts
move?: { kind: 'dash' | 'blink'; to: 'target' | 'behindTarget' | 'awayFromTarget' | 'ally'; maxRange: number }
```

| flavour | encoding | respects geometry? | range | needs Stage 1? |
|---|---|---|---|---|
| **Disengage** | `dash`, `awayFromTarget`, short `maxRange` | yes | shortest | **no** — short enough for a straight-line check |
| **Dash** | `dash`, longer `maxRange` | yes — blocked by cover | medium | **YES** — must follow a path or it runs into a wall |
| **Teleport** | `blink` | **no** — ignores cover entirely | longest | **no** — ignores geometry by definition |

⚠️ **This inverts the obvious build order.** Disengage and Teleport need no
pathfinding at all and could ship before Stage 1; **Dash is the one that depends on
it**, because a ground-crossing leap without a path just accelerates into the nearest
obstacle. `sp.move` is already implemented (`engine.ts:432`), so the ability tier is
closer to working than the baseline tier is.

`fade` (drop off the targeting radar, `core.ts:313`) is a **fourth** escape flavour
that is not movement at all, and it composes: fade + reposition is a genuine vanish.
Worth holding back as a later tier rather than shipping alongside these.

#### ⚠️ Teleport is the one that can break the bound

Cut-off pursuit (§4) is what converts a cooldown into a real limit — and **it does not
apply to `blink`**, which ignores the geometry the interception is computed over. A
blink with generous range and a modest cooldown produces an unkillable support, which
is the §5 failure in its purest form. Price it hardest: longest cooldown, highest MP,
and consider a cast time so it can be reacted to. Do not let its `maxRange` be tuned
casually.

#### DECIDED — a short shared **escape lockout**

The two cooldowns stay independent, **plus** using either escape puts the other on a
short lockout. One symmetric constant, **4–6s**, starting at 5.

⚠️ **The hazard was never "two escapes in a fight" — it is "two escapes in two
seconds".** Two escapes across a 45s fight is the premium build working as intended.
Two inside one window is what makes an assassin's commitment unanswerable: it lands,
the support Disengages, it re-closes, the support instantly Falls Back, and it has
spent eight seconds achieving nothing. **No value of the 15s cooldown catches that**,
because the whole burst happens inside a single window — which is exactly why a second,
much shorter constant is the right shape rather than a bigger version of the first.

Sizing: a Disengage buys ~2s of separation and an assassin needs ~2s to re-close and
land, so ~5s lets roughly one full exchange resolve between escapes. Under ~3s it is
decorative; over ~8s it collapses the two tiers into one and the ability stops being a
separate system.

It also improves the drama rather than taxing it. `Disengage → instantly Fall Back` is
a double-tap that reads as the support shrugging off the engagement. `Disengage →
assassin re-closes → Fall Back` is a chase with a middle, and the lockout is what
creates the middle.

⚠️ **Symmetric, and one number, to start.** The tempting refinement is for Fall Back to
impose a shorter lockout than the ability does, since Fall Back is the weaker option.
That is probably right eventually, but it is two numbers interacting with two cooldowns
and a trigger — and the standing rule is one value at a time. Start symmetric, sim,
split only if the data asks.

#### ⚠️ Sim the combined budget, not the baseline

Two independent cooldowns means the escape budget per fight is *baseline + ability*.
The acceptance run must use a support **with the ability drafted** — testing baseline
Fall Back alone will look fine and ship an unkillable premium build.

### Why A, and why F (recorded rationale)

**A** because a cooldown is the only option on that list the **player can see and plan
around**, and it reuses a concept the game already teaches on every ability. One
number to sim-tune. Retreat becomes an event in the battle report rather than a
continuous drift nobody can observe.

**F** on top because it costs no new machinery: `spatial.ts` already carries `fade`,
`dash` and `blink`, and *Shadowstep / Disengage / Stealth* is already on the roadmap.
Those become the **good** retreat — further, cheaper, or off-cooldown — bought with MP
and a loadout slot. Escape becomes a **build decision** rather than a universal
entitlement, which is a far healthier place for it to live, and it gives the ability
pool a real reason to carry movement.

**Gate on a trigger, not only a timer** — HP under ~40%, or a melee threat within ~3
units while in a back-line role. Without a trigger, units burn the cooldown wandering
at full health.

**Starting numbers**, to be moved one at a time against the sim:

- retreat cooldown **15–20s** (≈2 uses in a 45s fight)
- committed retreat duration **~2s**
- keep the 0.6× backpedal penalty and `KITE_MAX` exactly as they are

### ✅ SHIPPED — the pursuit give-up (the counterweight)

⚠️ **Pathfinding created this problem.** Once units route around cover properly a
pursuer never loses the trail, which makes any escape budget irrelevant: a support can
spend every cooldown it owns and still be caught. A chase has to be able to fail.

Three constants, and each guards a specific failure:

| | | why |
|---|---|---|
| `PURSUIT_PATIENCE` | 3.0s | time **without progress**, not time chasing — a bruiser closing steadily across a 64-unit arena is doing its job, and a stopwatch would abandon it mid-approach |
| `PURSUIT_IGNORE` | 5.0s | ⚠️ without it, giving up **thrashes**: drop B, take C, drop C, take B, and nobody dies — a new way to stall dressed as a fix |
| `PURSUIT_PROGRESS` | 0.35 | measured against the **closest ever approach**, not last tick, or a unit kited in a circle registers progress on every inward arc and chases forever |

⚠️ **Never abandon the last living enemy.** With nobody else to turn to, giving up is
just refusing to fight.

**It fires, and not too much:** ~4 give-ups per fight across 24 fights per arena, in
19–22 of them — about 0.67 per unit, so most units never break off and some do once.
`sweep40` holds at **40/40 @ 17.8s**; per-arena resolution 24/24, 23/24, 24/24.

⚠️ **Emitted as a `giveup` EVENT, not merely tallied.** A give-up you cannot see is
indistinguishable from a unit wandering off, and it is the only way to tell *"the
support escaped"* from *"the support was never chased"* — which no outcome metric can
separate. It also feeds the battle report.

### ✅ SHIPPED — the escape instrument, and the test already passes

`src/tamerengine/escape.ts` + `npx tsx tools/escape.ts`. Each arena run with its cover
and again with **none**, same teams, same seeds.

| arena | cover | hunts | survival | survivedFor | escapes/hunt |
|---|---|---:|---:|---:|---:|
| Dustbowl | yes | 136 | 35% | 9.5s | 0.54 |
| Dustbowl | **none** | 134 | 37% | 9.4s | 0.52 |
| The Ossuary | yes | 138 | 33% | **11.4s** | 0.55 |
| The Ossuary | **none** | 139 | 37% | 10.1s | 0.53 |
| Titan's Rest | yes | 140 | 39% | **11.5s** | 0.58 |
| Titan's Rest | **none** | 137 | 39% | 9.8s | 0.53 |

**Both halves pass, today, before Fall Back or any escape ability exists:**

- **Positive.** Cover lengthens survival on the arenas that have any — Ossuary 10.1 →
  11.4s (+13%), Titan's Rest 9.8 → 11.5s (+17%). Dustbowl is flat (9.4 → 9.5s) and
  that is the control working: at 1.9% cover there is nothing to hide behind.
- **Bounded.** Survival rate sits at 33–39% and cover does **not** raise it. Prey still
  dies about two thirds of the time. On Ossuary cover even coincides with a *lower*
  rate (37% → 33%) — small sample, not a claim, but certainly no sign of prey becoming
  uncatchable.

⚠️ **THIS IS NOW A BASELINE TO PROTECT, NOT A BOX TICKED.** When Stage 3's Fall Back
and the escape abilities land, `survivedFor` should rise further — and `survivalRate`
must NOT approach 1.0. That pair is the acceptance test, and it is the only thing that
can distinguish an escape that works from one that works too well.

⚠️ **Required an engine change to be measurable at all:** snapshots now carry
`targetId`. Without it a chase can only be inferred from damage, which misses the
entire pursuit phase — exactly the part cover is supposed to lengthen, so the effect
under test would have been invisible. It also gives a renderer what it needs to draw a
threat line.

### ⚠️ The pursuer must be allowed to win

A cooldown alone does **not** guarantee resolution. If the assassin follows the
support's current position rather than cutting it off, the support wins every lap
whatever its budget. Stage 2's cut-off pathing is what converts the cooldown into a
real bound.

**The acceptance test is therefore not "can the support escape".** It is: *does the
support buy ~4 seconds and then die anyway?* A retreat that always works is the same
bug as a retreat that never works.

---

## 6. Stage 4 — measurement

⚠️ **None of the current instruments can see any of this.** `sweep40` reported a
healthy 38/40 while two units were frozen solid for an entire fight. New metrics
first, then changes.

- **`stuck%`** — frozen **and** hugging cover. Target ~0. The Stage 0 gate.
- **`wander`** — path ÷ net displacement. Target < ~1.5 on all three arenas.
- **`escape success`** — seconds a fleeing support survives with cover available vs
  without. Must be **positive but bounded**; unbounded is the §5 failure.
- **`min escape gap`** — the shortest interval between two escapes by the same unit.
  ⚠️ Sharper than "escapes per fight", which is blunt: it is the BACK-TO-BACK pair that
  breaks a fight, not the total. The lockout puts a floor under this directly, so the
  metric and the mechanism check each other.
- **per-arena resolved** — `tools/mapsweep.ts` already does this.

The three arenas become the regression suite. **Titan's Rest is the gate:** it is kept
deliberately broken and it is the sharpest reproduction of the problem — do not fix it
by deleting the rubble.

⚠️ The **field goldens will move**, deliberately, and should be recaptured in their own
commit once Stage 1 lands.

---

## 7. Order of work

| stage | content | gate |
|---|---|---|
| **0** | push-out, strict band guard, no terminal block | `stuck%` → ~0 |
| **4a** | `stuck%` + `wander` instruments | must precede 0 to prove it |
| **1** | visibility graph + A*, waypoints into `stepToward` | `wander` < 1.5; goldens recaptured |
| **2** | LoS-break flight, peek, cut-off pursuit | escape success positive |
| **3a** | Fall Back: ~15s cooldown, trigger, backpedal suspended, ~5s shared lockout | resolved ≥ baseline; `min escape gap` ≥ lockout |
| **3b** | Disengage + Teleport (no Stage 1 dependency) | escape bounded **with the ability drafted** |
| **3c** | Dash (needs Stage 1) | wander unchanged; no dashing into cover |

**Stage 4a genuinely comes first.** Building Stage 0 without the instrument means
grading the fix on `resolved`, which is exactly the number that already hid the bug.

## 8. Knock-ons

- Map geometry becomes a real design surface — chokepoints and pillars start meaning
  something, which makes the arena set content rather than scenery.
- Stage 1 is the **prerequisite** for the deferred `spatial.ts` movement abilities;
  Shadowstep and Disengage cannot be built sensibly on wall-sliding.
- `FIELD_W`/`FIELD_H` are already `let` with `setFieldSize`, so per-arena work is
  unblocked.

---

## 9. Postscript — what the movement work actually turned out to be (2026-07-31)

⚠️ **The thing that looked like a bad retreat was never a retreat.** Three commits
tuned `DASH_SPEED_MULT` (4 → 2.2 → 1.35) against the complaint "the retreats look
like teleports". They could not have worked: **not one of the jumps was a dash or
a Fall Back.**

Measuring per-tick displacement in an actual 3v3 dump settled it in one pass:

```
1532 ticks moved <=0.5 units      (walking)
   9 ticks moved  1.8-3.1 units   (the "teleports")
   0 ticks in between
```

A bimodal distribution with a hole in it. Speed-limited movement produces a
continuum; a gap like that means something skipped the movement step entirely. All
nine matched a `shove` event exactly — knockbacks and one ally-pull, applied by
`applyOnTarget` writing `target.pos = dest`. Body Slam's `push: 3` landed three
units inside one 0.1s tick: 30 units/second, about 7x a walk.

**Lessons that generalise past this bug:**

1. **Measure which mechanic is FIRING before tuning the one you assume is.** The
   dash constants were changed three times against a fight in which no dash ever
   fired, and against a GIF that was playing at 4.5x real time. Both were checkable
   in one command.
2. **A bimodal displacement histogram is the tell.** It is now a permanent guard:
   `spatial.test.ts` fails if any unit moves >2.0 units in one tick, across four
   seeded 3v3s. Deliberately a TELEPORT detector rather than a speed limit — legal
   travel stacks unit speed, `DASH_SPEED_MULT`, the Fall Back ramp and haste, and
   the fastest legal step observed is 1.58. A first version asserted a *derived*
   maximum and failed on correct dash movement; a tripwire that fires on legal
   behaviour gets weakened until it fires on nothing.
3. **Where a control-loss gate sits in the tick is load-bearing.** Knockback now
   costs the target control for the flight. Placed ABOVE the per-unit timers it also
   froze cooldowns, mana, regen and status durations — a stealth stun that paused
   recovery — and `duel-melee` went 15s → **91.5s**. After the timers, before the
   decision.

### Still open from this plan

- **Stage 3c (Dash)** — the escape that needs Stage 1 pathfinding. Not built.
- **`DASH_SPEED_MULT` (1.35) and `TURN_RATE` (7) have never been honestly judged.**
  Both were set against the 4.5x GIF and a dashless fight. The renderer now defaults
  to real time and labels any fast-forward, so a fight where dashes actually fire
  would settle them in one pass.
- **Second cover lever** — pursuer patience draining faster while out of line of
  sight. Designed, not built.
- **Re-test the isolation term** (`d0dbd62`) now that healers are drafted. It fires
  in ~1% of unit-ticks. ⚠️ If it is still null, DELETE it rather than leaving a term
  that reads as a mechanic and is not one.
