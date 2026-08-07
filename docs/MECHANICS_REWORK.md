# Mechanics rework — making a larger arena behave differently

## ⚠️ CORRECTION 2026-08-03 — THE MELEE TARGETING FINDING WAS WRONG

**`targetPriority` DOES reach melee units. It was already found and already fixed.**

`pickTarget` (`decide.ts:250-262`) applies `ordered(self, all, allies)` **above** the
melee/ranged split, and the code comment records exactly why:

> *"⚠️ APPLIED BEFORE THE SPLIT, SO IT REACHES BOTH BRANCHES. `decide.ts`'s own note records
> that the melee branch returning early is exactly how `targetPriority` came to do nothing on
> most of the game's classes. Filtering once, above the split, is the only version that cannot
> repeat it."*

So the player's explicit order — *"hunt their casters"* — **is honoured on a Warrior.** The
claim that melee has no target selection was **false**, and it was raised as a live bug when the
codebase had already solved it and left a comment saying so.

### What melee genuinely does not get, and why that is DELIBERATE

Only the **automatic** value / isolation / focus-fire scoring, which sits below the split. The
same comment gives the reason:

> *"⚠️ AND THE FIX IS NOT TO SCORE MELEE LIKE RANGED. Value-chasing across open ground is the
> failure this branch exists to prevent, and re-opening it would undo it wholesale."*

⚠️ **AND THAT REASONING GETS STRONGER ON A LARGER GROUND, NOT WEAKER.** Automatic value-chase
on a 40-wide board produced melee racing around the map. On a 160-wide board it would be far
worse. **The exclusion is more justified at scale, not less** — which inverts this document's
proposed "gated fix" for divers.

### What this means for the diver work

Not *"melee cannot target"*. The honest, much smaller version:

- **A melee diver whose player HAS set a target order works today.**
- **A melee diver with no order set goes nearest** — which is a sensible default, not a bug.
- The open question is narrower: **should a ROLE (Assassin) supply a default `targetPriority`
  the way `GAMEPLANS` already supplies team presets?** That is a data question — one entry in
  `ROLE_TACTICS` — not an engine change, and it composes with the existing filter rather than
  re-opening the scoring branch.

⚠️ **TENTH ENTRY IN THE ALREADY-HANDLED LIST**, and the first one that was a false alarm
rather than a stale doc: the others were real things wrongly believed missing; this was a
non-problem wrongly believed broken. **The lesson is the same in both directions — read the
comment before believing the diagnosis.**



**2026-08-03.** Specifies the mechanics changes needed so a much larger arena produces
genuinely different unit behaviour — hanging back, flanking, diving the weak — rather than
every fight collapsing to the same "close to reach, hold, retreat" shape at a bigger scale.

⚠️ **DEPENDENCY: `docs/ARENA_BLUEPRINT.md` is being revised concurrently by the Level
Designer.** This document does not author arena dimensions. Every formula below that needs
ground size takes `k(N)`, `GROUND_W(N)`, `GROUND_H(N)` and `DEPLOY_DEPTH(N)` as given, exactly
as `ARENA_BLUEPRINT.md` §0–§1 defines them:

```
k(N) = 2.0 + 0.5 × (N − 1)          k(1)=2.0 · k(2)=2.5 · k(3)=3.0 · k(4)=3.5 · k(5)=4.0
GROUND_W(N) = k(N) × 40
GROUND_H(N) = k(N) × 22
DEPLOY_DEPTH(N) = 6 + N
```

If those numbers move, every formula in this document that reads them moves too, and nothing
here needs re-deriving — only re-evaluating against the new inputs.

⚠️ **STRUCTURE, NOT TUNING.** The balance baseline is suspended (`CLAUDE.md`). Nothing below
proposes a final numeric value to ship; every proposed constant is marked as a proposal
requiring sign-off and a sim pass, distinct from the structural changes (which formula reads
which input) that are the actual content of this document.

**Determinism**: every mechanic below is specified as a pure function of unit state, team
orders and the fixed-dt tick — no wall-clock, no per-call randomness beyond the one seeded
stream `simulateFieldBattle` already owns. This is the same contract `SPATIAL_MODEL.md` §0
states for the Godot rebuild; this document's scope is the TS field engine
(`src/tamerengine/decide.ts`, `src/tamerengine/engine.ts`), which already satisfies it, so
nothing below introduces a new source of non-determinism.

**Method note on citations**: every current-state claim below is checked against source,
cited as `file:line`. Two claims made confidently by earlier docs turned out to need
correction on inspection (see §7's flagging of `MELEE_PRIORITY_SLACK`/`ORDER_REACH`/flank
radii, and §1's flagging of the leash's shared-centroid anchor) — consistent with this
project's own standing lesson that inherited constants are evidence of what happened, not of
what was decided.

---

## 1. SPREAD replacing the leash

### What exists today

`LEASH_RADIUS = 12` (`src/tamerengine/types.ts:73`) is a flat constant. It is applied inside
`desiredGoal`'s `leash()` closure (`decide.ts:525-529`) to every goal the function returns —
retreat, kite, archetype nudges, cover-sidestep, all of it (`decide.ts:729`):

```ts
const battleCentre = centroid([self, ...liveAllies, ...liveEnemies])   // decide.ts:524
const leash = (g: Vec2) => {
  const dv = sub(g, battleCentre); const L = len(dv)
  return L > LEASH_RADIUS ? add(battleCentre, scale(norm(dv), LEASH_RADIUS)) : g
}
```

⚠️ **The anchor is a COMBINED centroid of both sides** (`centroid([self, ...liveAllies,
...liveEnemies])`, `decide.ts:524`, using `centroid()` at `decide.ts:133-138`), not a
team-relative point. Every unit on the field — both teams — is bounded against the same
circle. That is fine when the circle is small and both teams are already adjacent, but it is
the wrong anchor for a per-TEAM spacing order: two teams cannot independently choose "tight"
or "loose" if they share one leash-point between them.

Separately, `Tactics.formation?: 'keep' | 'tight' | 'spread'` **already exists** as a
player-settable categorical order (`src/core.ts:534`), and it already drives one thing:
personal body-to-body spacing, via `spacingRadius()` (`decide.ts:413-419`):

```ts
export function spacingRadius(u: FieldUnit): number {
  const order = u.m.tactics?.formation
  const base = u.radius * 2
  if (!order || order === 'keep') return base
  const want = order === 'spread' ? base * 2.6 : base * 0.75
  return coachedValue(base, want, personalityOf(u.m).temperament)
}
```

So today there are **two unrelated notions of "how spread out"**: a personal-space radius
driven by `formation`, and a team-envelope radius driven by the unrelated flat
`LEASH_RADIUS`. `docs/DECISIONS_2026-08-03.md` #4 is explicit that these must become one
knob: *"SPREAD and the leash are ONE KNOB. Do not build both."*

### What it becomes

`formation` stops being read only by `spacingRadius` and starts also sizing the team's
envelope — the same order, two consumers, exactly as the decision requires. `ARENA_BLUEPRINT.md`
§4 has already derived the envelope geometry from the ground; this section wires the existing
`formation` order into it and fixes the shared-centroid anchor.

**Formula 1 — spread value from the order**

```
spreadValue(order) =
  0.0   if order == 'tight'
  0.5   if order == 'keep' or unset
  1.0   if order == 'spread'
```

| Symbol | Type | Range | Description |
|---|---|---|---|
| `order` | enum | `{tight, keep, spread}` | the team's standing `formation` order (`core.ts:534`) |
| `spreadValue` | float | `[0, 1]` | how loose the team's envelope should be, 0 = tightest |

Output range: exactly `{0, 0.5, 1}` today; nothing prevents a future continuous slider using
the same downstream formula.

**Formula 2 — the envelope radius (this IS the leash, replacing `LEASH_RADIUS`)**

```
usable_radius(N)              = 0.4 × GROUND_H(N)
ENVELOPE_RADIUS(N, s)         = lerp(0.55, 0.95, s) × usable_radius(N)
```

(`s = spreadValue(order)`, both lines taken verbatim from `ARENA_BLUEPRINT.md` §4.)

| Symbol | Type | Range | Description |
|---|---|---|---|
| `N` | int | `1–5` | team size, per league (`TEAM_SIZE_BY_LEAGUE`) |
| `GROUND_H(N)` | float | derived | ground height for this team size (`ARENA_BLUEPRINT.md` §1) |
| `usable_radius(N)` | float | `17.6–35.2` at N=1..5 | half the usable ground, minus edge margin |
| `s` | float | `[0, 1]` | `spreadValue(order)` |
| `ENVELOPE_RADIUS(N, s)` | float | `9.68–33.44` at the extremes for N=5 | the team's leash radius |

Output range: bounded below by `0.55 × usable_radius(1) = 9.68` and above by `0.95 ×
usable_radius(5) = 33.44` across the whole team-size ladder — always a fraction of the ground,
never the whole thing, by construction (`ARENA_BLUEPRINT.md` §4's own point: the LOOSE
envelope never exceeds ~42% of `GROUND_W(N)` at any N).

**Worked example (5v5, N=5):** `keep`/unset (`s=0.5`) gives
`lerp(0.55,0.95,0.5)=0.75 → ENVELOPE_RADIUS = 0.75 × 35.2 = 26.4`, sitting exactly between
`ARENA_BLUEPRINT.md`'s published TIGHT (19.36) and LOOSE (33.44) radii for that team size —
consistent, since `keep` was never meant to be either extreme.

**Formula 3 — the anchor point (the fix `ARENA_BLUEPRINT.md` did not need to make, because it
was working at the geometry level, not the code level)**

```
anchor(self) = centroid(own_live_team)          // NOT centroid(own + enemy)
```

replacing `battleCentre` in `decide.ts:524` with a same-side-only centroid. This is not a new
concept in the file — `desiredGoal`'s own `formation:'keep'` branch already computes a
same-side anchor this way (`decide.ts:591-599`, `now = centroid(live)` where `live = [self,
...liveAllies]`), and `commitLimit` (`decide.ts:426-435`) already treats side A and side B
asymmetrically against `FIELD_W`. Per-team, non-shared bounds are an established pattern in
this file; the leash is the one place that never got it.

**Blend by temperament**, matching `spacingRadius`'s own pattern (`decide.ts:418`) rather than
inventing a second blending rule: a wilful monster honours its team's SPREAD order less
faithfully, exactly as it already honours `tight`/`spread` personal spacing less faithfully.

```
effectiveEnvelope(u, N, order) = coachedValue(
  ENVELOPE_RADIUS(N, 0.5),                 // base: as if 'keep'
  ENVELOPE_RADIUS(N, spreadValue(order)),  // want: what the order actually asks for
  personalityOf(u.m).temperament,
)
```

⚠️ **This stacks with, and must not replace, `FieldTraits.cohesion`** (`types.ts:418-422`,
the PER-UNIT trait from the existing cohesion×predation grid). `DECISIONS_2026-08-03.md` #2
rules this layered: *"Doctrine is the TEAM's plan; `cohesion`×`predation` is the UNIT's
fidelity to it."* SPREAD is the team's plan (this section); `self.traits.cohesion` is already
a separate pull toward the ally centroid inside `desiredGoal` (`decide.ts:585`, `pull =
self.traits.cohesion * 0.35`) and stays exactly as it is. A low-cohesion assassin under a
`spread` order drifts looser than the order alone would produce; a high-cohesion anchor under
the same order still hugs its team more than the order asks. Two independent pulls, not one
merged into the other — this is what makes personality-driven freelancing (the thing
`DECISIONS_2026-08-03.md` explicitly wants breeding-for-personality to affect) survive the
rework rather than being absorbed into a single team-level number.

### Why the anchor fix matters, concretely

Without it, a LOOSE team and a TIGHT enemy sharing one `battleCentre` would have the tight
team's own presence dragging the loose team's leash circle toward the enemy line (and vice
versa) — the envelope's centre would wander with the fight rather than with the team, so
"loose" would not reliably mean "spread out around MY own formation," it would mean "spread
out around wherever the fight's centre of mass happens to be," which drifts as units die on
either side. A same-side anchor is what makes SPREAD a property of a team's own play, legible
independent of what the enemy is doing.

### Cost

One file (`decide.ts`), the same `let`/setter treatment `FIELD_W`/`FIELD_H` already use
(`types.ts:29-38`) applied to `LEASH_RADIUS` so it can vary per team/per fight rather than be a
frozen module constant, and a change to `decide.ts:524`'s centroid call. No new data on
`Monster` or `Tactics` — `formation` already exists and is already player-facing.

---

## 2. Positional intent — stations resolved from intent, not coordinates

### What exists today

There is already a live, per-tick "where do I want to be" resolver — it is just narrower than
a station system. `archetypeOf()` (`decide.ts:759-783`) classifies a unit as `anchor` /
`artillery` / `assassin` / `support` / `skirmisher` from class, reach and personality, and
`desiredGoal`'s archetype switch (`decide.ts:649-683`) nudges the goal accordingly:

```ts
case 'anchor':  goal.x += enemyDir * 1.0                                   // decide.ts:659
case 'support': goal.x -= enemyDir * 1.3; blend toward the worst-hp ally   // decide.ts:662-670
case 'assassin': dart away for disengageFor seconds after a hit            // decide.ts:672-682
```

This is already "intent resolved live" in exactly the sense `SPATIAL_MODEL.md` §6 asks for —
nothing is stored, it is recomputed from `enemyDir` and live positions every call. **What it
cannot express is a lateral (cross-axis) intent.** Every nudge above moves along the forward
axis only (`enemyDir`, `±x` toward/away from the enemy). There is no mechanism today for
"stand on the left," "work the flank," or any station that is not simply "closer to" or
"further from" the enemy line. That is the concrete gap between what exists and "hang back on
the left / work the flank."

### What it becomes

Extend the same switch with a **lateral** term, resolved the same way the forward term already
is — from live geometry, never a stored coordinate, so it survives any arena shape:

**Formula — team axis and its perpendicular**

```
teamAxis(side)    = normalize(centroid(enemy_live) − centroid(own_live))
lateralAxis(side) = perpendicular(teamAxis(side))     // rotate 90°
```

| Symbol | Type | Range | Description |
|---|---|---|---|
| `teamAxis` | unit Vec2 | unit length | direction from own team toward the enemy team |
| `lateralAxis` | unit Vec2 | unit length | the cross-axis, perpendicular to `teamAxis` |

This is arena-orientation-independent by construction — it is derived from where the two
teams currently are, not from world `x`/`y`, so it is correct whether the ground is a wide
rectangle or (per `SPATIAL_MODEL.md` §8, if elevation or an asymmetric board ever ships)
something else entirely.

**Formula — which side is "the flank"**

Resolved as a query against live enemy geometry, exactly as `SPATIAL_MODEL.md` §6 specifies
for `Screen`/`Skirmish` ("a resolver can answer where the cover is; a stored `{x,y}` cannot"):

```
enemyLateralSplit = count(enemy_live where dot(pos − enemyCentroid, lateralAxis) > 0)
                    vs count(... < 0)
openSide = the sign with FEWER live enemies on it
```

| Symbol | Type | Range | Description |
|---|---|---|---|
| `enemyLateralSplit` | pair of ints | `[0, N]` each | how the live enemy team splits across the lateral axis |
| `openSide` | `{+1, −1}` | sign | which lateral half currently has fewer defenders |

**Formula — the station offset**

```
FLANK_DEPTH(N, s) = 0.5 × ENVELOPE_RADIUS(N, s)          // from §1
stationOffset(u)  = forward(u) × teamAxis + lateral(u) × lateralAxis
  where lateral(u) = openSide × FLANK_DEPTH(N, s)   if archetype == 'assassin'/'skirmisher' AND flank-intent
                    = 0                              otherwise (unchanged from today)
```

| Symbol | Type | Range | Description |
|---|---|---|---|
| `FLANK_DEPTH(N, s)` | float | half of `ENVELOPE_RADIUS` | how far laterally a flanker sits from its own team's forward line |
| `forward(u)` | float | same as today's existing per-archetype nudges | unchanged: `±1.0`/`±1.3` etc. |
| `lateral(u)` | float | `−FLANK_DEPTH..+FLANK_DEPTH` | new: signed lateral offset, zero for archetypes that do not flank |

**Worked example (5v5, `keep`, N=5):** `ENVELOPE_RADIUS(5, 0.5) = 26.4` (from §1) →
`FLANK_DEPTH = 13.2`. An assassin-archetype unit with flank-intent set and `openSide = +1`
(enemy is thinner on that lateral half) resolves a station 13.2 units off the team's forward
axis, on the side with fewer defenders — a genuinely different place to stand than the rest of
its team, recomputed fresh every retarget rather than authored once at deploy.

**"Hang back"** is the existing `support` nudge (`decide.ts:662-670`) generalized: any unit
given a hang-back intent (not only the `support` role) applies the same
`goal.x -= enemyDir * k` pull, scaled by `ENVELOPE_RADIUS` rather than the flat `1.3`, so
"hang back" means something proportional to how much room the team actually has, not a fixed
world-unit nudge that shrinks to nothing on a big board and looms too large on a small one.

### Why intent, not coordinates

Every quantity above is either a live centroid, a live split-count, or a fraction of
`ENVELOPE_RADIUS` (itself derived from `GROUND_H(N)`). Nothing is a stored `{x, y}`. Change the
arena's shape, size, or which team size is fighting, and the same intent — "flank the open
side," "hang back" — resolves to a different concrete point automatically, which is exactly
`SPATIAL_MODEL.md` §6's requirement and the reason the arena rebuild and this rework have to
ship together.

### Cost / dependency

Depends on §1 (`ENVELOPE_RADIUS` must exist to size `FLANK_DEPTH`). Adds one new field to read
(a flank-intent flag, most naturally sourced from the archetype/doctrine work already underway
per `DECISIONS_2026-08-03.md`'s doctrine set) and one new geometric helper (`lateralAxis`,
`openSide`) in `decide.ts`. No engine-side change — `desiredGoal` already returns a `Vec2` the
engine steers toward blindly.

---

## 3. Target selection for divers

### The finding this section is built on

`isMelee(u)` is `reachOf(u) <= 3` (`decide.ts:131`). The Assassin line's authored reach is
2.4–2.8 world units today (`docs/ABILITY_BALANCE_REVIEW.md` §1.4's own table). **2.4–2.8 is
below 3.** So a unit built around the Assassin line — DEX, high predation, exactly the
archetype `SPATIAL_MODEL.md` §10 names as *"low cohesion / high predation → assassin: solo-dives
the enemy backline"* — is classified `isMelee`, and `pickTarget` routes it into the melee
branch (`decide.ts:282-291`):

```ts
if (isMelee(self)) {
  let best = null, bestD = Infinity
  for (const e of live) {
    const d = dist(self.pos, e.pos) + (faded ? 6 : 0) - comboBias(self, e) * MELEE_PRIORITY_SLACK
    if (d < bestD) { bestD = d; best = e }
  }
  return best   // NEAREST ENEMY, full stop
}
```

The scoring block that reads `predation`, `valueOf`, `unsupported` (isolation) and
`diveThreat` (`decide.ts:293-345`) is **never reached** by this unit. ⚠️ **The game's own named
assassin archetype is, today, mechanically incapable of diving the backline on purpose** —
its short native reach routes it into the exact branch built to stop value-chasing, which is
correct for a Warrior or Tank and wrong for the one archetype whose entire kit says otherwise.
This is a stronger and more specific version of the brief's "dive for the weak needs a target
rule" — it is not that the rule needs building from nothing; the rule (`valueOf` × `predation`
+ `unsupported`) already exists and already works for non-melee predators. The bug is that the
Assassin line's own reach disqualifies it from reaching that code path.

A second, smaller gap: `diveThreat` (`decide.ts:354-367`, the defensive counter — "who is
bearing down on my ally") is folded into the ranged/caster score (`decide.ts:327`) but **not**
into the melee branch's distance calc. So melee interceptors do not turn to save a diving
threat the way ranged/caster interceptors already do.

### Why the melee-nearest rule exists, and why it should not simply be removed

`decide.ts:263-281`'s own comment is explicit: melee-nearest exists so a front-liner "screens
the squishies behind it for free," and removing it wholesale reopens "the cross-map hunt" that
once had bruisers racing across open ground for a juicy target. That is correct behaviour for
a Tank or Warrior. **The fix is not to delete the rule — it is to gate it so it does not also
apply to a unit whose kit is built to defeat it.**

### The gate

```
DIVE_THRESHOLD = <proposal, needs sim — see §9's open items>
isScreened(u) = isMelee(u) AND NOT (
  self.traits.predation >= DIVE_THRESHOLD AND hasGapCloser(u)
)
```

| Symbol | Type | Range | Description |
|---|---|---|---|
| `predation` | float | `[0, 1]` | `FieldTraits.predation`, already computed (`decide.ts:33-48`) |
| `hasGapCloser(u)` | bool | — | true if the unit's `fieldLoadout` carries a `dash`/`blink` movement move (`engine.ts:146-177`, `fieldMoves.ts`) |
| `DIVE_THRESHOLD` | float | `[0, 1]` | proposal, the predation floor above which a melee-reach unit is treated as a diver, not a screened bruiser |
| `isScreened(u)` | bool | — | true = keep today's nearest-only rule; false = route into the scored branch |

A unit failing `isScreened` (i.e., a genuine diver) falls through to the **existing** scored
branch unchanged — `valueOf`, `unsupported`, `diveThreat`, `predation`-weighted proximity all
already do the right thing; they simply need to be reachable.

**Bounding it, or the cross-map hunt returns exactly as `decide.ts`'s own history warns.**
Reuse the pattern already built for player-set target orders (`ordered()`, `decide.ts:233-249`,
bounded by `ORDER_REACH`) rather than inventing a second bounding rule:

```
diveCandidates(self, live) = { e in live : dist(self, e) <= nearestEnemyDist + ORDER_REACH(N) }
                              ∪ { e : diveThreat-worthy — unchanged, dive overrides everything }
```

where `ORDER_REACH(N) = ORDER_REACH × k(N)` (see §7 — this constant is currently unscaled and
must scale with the board for exactly the reason `ABILITY_BALANCE_REVIEW.md` already argued
for `LINE_RANGE`: a fixed world-unit slack shrinks to irrelevance on a 4x board).

**Getting there physically.** No new steering is needed. `desiredGoal`'s general
"walk-toward-target-minus-standoff" logic (`decide.ts:545-559`) is not gated on reach — it
already walks any unit toward whatever `target` it was handed. And passing near a front-liner
does not force an engagement: sticky engagement keys on the unit's *current* `targetId`, not
proximity to any nearby body (`engine.ts:1013-1014`, `engaged = ... isMelee(u) && foes.includes(cur)
&& dist(u.pos, cur.pos) <= reachOf(u) + 1.5`). A diver whose `targetId` is a backliner simply
walks past a front-liner without being redirected onto it. The only friction is the
non-overlap collision rule (`COLLISION_R_FRAC`, `engine.ts:65`, `resolveCollisions`,
`engine.ts:2072`), which jostles the diver around a body rather than letting it clip through —
acceptable, and consistent with the existing `spatial.test.ts` tripwire that no unit may move
more than 2.0 units in one tick.

### Doctrine link

`DECISIONS_2026-08-03.md`'s settled seven-doctrine set (Control · Sweep · **Strike** · Anchor
· Empower · Protect · Restore) already names the doctrine this section serves. **Strike**
should be specified as: an explicit team order that raises the gate's effective `predation`
input above `DIVE_THRESHOLD` for units under it, blended by `temperament` exactly like every
other order in this engine (`coachedValue`). This gives the player a real lever — a
low-predation-personality monster coached into a Strike doctrine dives anyway, tempered by how
disciplined it is — rather than diving being purely a function of rolled personality, which
would make it unbred, unbreedable and uncoachable.

---

## 4. Pursuit and disengagement at scale

### What exists today

```
PURSUIT_PATIENCE = 3.0   // seconds without closing before giving up   (types.ts:85)
PURSUIT_PROGRESS = 0.35  // world units of closing that counts as progress (types.ts:90)
PURSUIT_IGNORE   = 5.0   // seconds an abandoned target is skipped     (types.ts:89)
```

Applied at `engine.ts:1016-1039`: distance to the current target is measured against the
*closest this unit has ever been* to it (`u.chaseBest`), not tick-to-tick, specifically to stop
a unit that is being kited in a circle from registering false "progress" on every inward arc
(`engine.ts:1017-1020`'s own comment). If `PURSUIT_PATIENCE` elapses without closing by
`PURSUIT_PROGRESS`, the target is abandoned and ignored for `PURSUIT_IGNORE` seconds, and
`pickTarget` runs again cold.

### Why this mills on a large board

The give-up condition is sound; what happens *after* give-up is the problem. On today's
24-unit leashed huddle, "abandon, re-pick, re-engage" happens inside a tiny area and reads as
brief hesitation. On a board where the fight's own envelope can legitimately be 50–67 units
across (`ARENA_BLUEPRINT.md` §4, N=3–5 LOOSE), the same cycle — chase, give up, pick a target
that is *also* not closing (because it, too, is retreating or repositioning), give up again —
becomes a visible drift across real ground: the milling failure mode the brief names, and per
`ENGAGEMENT_DESIGN.md` §0, an unfilmable one, since the camera cannot hold a coherent shot on a
unit that is not converging on anything.

### What replaces it

Two of the three constants need to scale (mechanical, cheap); the actual behavioural fix is
structural and reuses machinery this document has already specified rather than inventing a
new system.

**a) `PURSUIT_PROGRESS` scales with the board, `PURSUIT_PATIENCE` does not.**

```
PURSUIT_PROGRESS(N) = 0.35 × k(N)
PURSUIT_PATIENCE     = 3.0                    // unchanged — a TIME constant
```

| Symbol | Type | Range | Description |
|---|---|---|---|
| `PURSUIT_PROGRESS(N)` | float | `0.70–1.40` at N=1..5 | world units of closing per `PURSUIT_PATIENCE` window that counts as real progress |
| `k(N)` | float | `2.0–4.0` | the shared linear ground-scale factor (`ARENA_BLUEPRINT.md` §0) |

Reasoning: "closing" must mean the same *fraction* of the board at every size — the same logic
`ABILITY_BALANCE_REVIEW.md` already applies to every reach/gap-closer constant. `PURSUIT_PATIENCE`
stays flat because it is a duration, and `ARENA_BLUEPRINT.md` §3 already states the governing
principle for this whole rework: *"rates and durations are not spatial."*

**b) On give-up, regroup at the station before re-picking — reusing the `formation:'keep'`
anchor mechanism, not new steering.**

```
if (justAbandoned(u)) desiredGoal(u) = anchor(u)   for RECOVER_FOR seconds,
                                        via the SAME blend `formation:'keep'` already uses
                                        (decide.ts:581-604), regardless of the unit's own
                                        formation order
then resume normal pickTarget / desiredGoal
```

| Symbol | Type | Range | Description |
|---|---|---|---|
| `justAbandoned(u)` | bool | — | true for `RECOVER_FOR` seconds after a give-up event (`engine.ts:1035`'s existing `giveup` event) |
| `RECOVER_FOR` | float (s) | proposal, `1.0–1.5` | how long the unit regroups before re-engaging; needs sim |
| `anchor(u)` | Vec2 | — | the same same-side-team anchor point defined in §1 |

This is the structural fix for **thrash** specifically (as opposed to §8's fixes, which are
mostly about honest, slow convergence). Instead of launching straight back into `pickTarget`'s
full scoring pass from the same exposed position — which, against a kiting target, frequently
re-selects the *same kind* of unreachable target — the unit visibly pulls back toward its own
team first. That is legible on camera (a unit disengages and reforms, matching the "a plan the
player can watch unfold" standard `SPATIAL_MODEL.md` §11.2 sets for cover) and it changes the
geometry of the next `pickTarget` call: a unit that has moved toward its own team is very
often now closer to a *different*, more reachable enemy when it re-engages, which is what
actually breaks the cycle rather than merely renaming it.

**c) `PURSUIT_IGNORE` is flagged, not resolved.** It should plausibly scale with
`ENVELOPE_RADIUS(N, s)` rather than staying a flat 5.0s — "how long to avoid re-picking the
same target" should relate to how far that target could plausibly have moved within the
fight's own envelope, not to a board-agnostic clock — but no formula is asserted here without
measurement. Candidate: `PURSUIT_IGNORE(N,s) = 5.0 × ENVELOPE_RADIUS(N,s) / ENVELOPE_RADIUS(5,
0.0)`, flagged for the sweep, not proposed for adoption.

### Dependency

This section assumes `ENGAGEMENT_DESIGN.md`'s Family A (closing-speed bonus) and Family B
(minimum range) land, per `ARENA_BLUEPRINT.md` §2's own stated load-bearing dependency — with
them, a chase that is genuinely converging converges fast enough that `PURSUIT_PATIENCE` rarely
fires on an honest pursuit, which is what makes it safe to treat every remaining give-up as a
real stall worth regrouping from, rather than tuning the patience window itself as a workaround.

---

## 5. Speed — class band × body modifier

### What exists today

```ts
speed: 2.4 + (m.stats.DEX / 1000) * 3.6,   // engine.ts:198, comment at engine.ts:196-197:
                                            // "DEX drives how fast it crosses the field"
```

Range 2.4–6.0 u/s (DEX 0–1000). ⚠️ **This is backwards, and it is not hypothetical** —
`ENGAGEMENT_DESIGN.md`'s Correction 1 (confirmed, cited in the task brief) already establishes
that DEX is the Ranger/Rogue/Volley stat: the units built to keep distance are, today, the
fastest at keeping it. `ABILITY_BALANCE_REVIEW.md` §1.5 measures this getting worse, not
better, at scale — a bigger board is more room to out-run a pursuer at the same 2.5x speed
ratio.

### What it becomes

```
speed(u) = CLASS_SPEED_BAND[band(u.class)] × BODY_SPEED[bodyType(u)]
```

`band(u.class)` reuses the **same four-band table `CLASS_BASIC` already keys off**
(`types.ts:1003-1034`, `BASIC_BANDS` = melee/ranged/magic/support, `CLASS_BAND` maps all 18
classes onto them) — no new data surface, no new authoring pass on the class side.

| Symbol | Type | Range | Description |
|---|---|---|---|
| `band(u.class)` | enum | `{melee, ranged, magic, support}` | the class's existing basic-attack band (`types.ts:1013-1034`) |
| `CLASS_SPEED_BAND[band]` | float (u/s) | proposal | base speed for that band |
| `bodyType(u)` | enum | one of 13 | the monster's body type |
| `BODY_SPEED[body]` | float, multiplier | proposal | speed modifier for that body |
| `speed(u)` | float (u/s) | derived, see worked range below | the unit's movement speed |

**Proposed tables** (both proposals — need user sign-off; the body table specifically is a
species/body-identity call, not a systems-design call, and should go to whoever owns
`docs/BESTIARY.md`):

```
CLASS_SPEED_BAND = { melee: 4.2, ranged: 3.4, magic: 3.0, support: 3.2 }   // u/s
BODY_SPEED       = { swift: 1.15, standard: 1.00, laboured: 0.85 }         // multiplier
```

Reasoning for the band ordering: melee fastest, because it must close and this directly
reverses the archer-outruns-its-chaser bug; magic slowest, because it roots longest to cast and
(once `ENGAGEMENT_DESIGN.md` Family B lands) wants distance least, since arriving is what
switches off a caster's kit; ranged and support sit between, still permitted some standoff
mobility, just no longer class-leading.

**Worked example — the resulting range:**

```
min: magic × laboured   = 3.0 × 0.85 = 2.55 u/s
max: melee × swift      = 4.2 × 1.15 = 4.83 u/s
```

⚠️ **This range (2.55–4.83) is narrower than today's (2.4–6.0), and that is intentional, not
an oversight.** Differentiation moves from "who is the single fastest unit on the field" to
"who gets a closing-speed bonus and does not need to run" (`ENGAGEMENT_DESIGN.md` Family A) —
a narrower raw-speed band is consistent with that shift. If the sim later shows this
under-differentiates positioning, the fix is to widen `CLASS_SPEED_BAND`'s spread first
(structure unchanged); reaching for DEX again is explicitly the wrong lever, per the
correction this whole section exists to act on.

### What happens to DEX

`engine.ts:198`'s formula and its comment are removed from `buildUnit` (`engine.ts:180-220`)
and replaced with the call above at the same site. DEX is **not devalued** — it keeps every
other job it already has: accuracy/crit contributions, DEX-scaled ability power for the
Rogue/Ranger/Assassin/Volley lines, and its role in `CLASS_BAND`'s stat-scaling table for the
classes that use it. Only its accidental, undocumented-until-`ENGAGEMENT_DESIGN.md` spatial
meaning is retired.

`BACKPEDAL_MULT` (0.6, `engine.ts:77`) and `DASH_SPEED_MULT` (1.35, `types.ts:137`) are
unaffected — both are multiplicative layers applied on top of whatever `u.speed` resolves to,
and neither reads DEX or the speed formula directly.

---

## 6. Proximity auras

### What exists today, and what is already decided

`TEAM_AURA_RADIUS = 9` (`types.ts:823`), flat and team-wide, applied at `engine.ts:1395-1402`
to gate which allies a team buff/ward/heal reaches. `DECISIONS_2026-08-03.md` ("Auras —
PROXIMITY-SIZED, not team-wide") and `ARENA_BLUEPRINT.md` §5 have already retired it and
supplied the replacement formula:

```
AURA_RADIUS(N) = 1.1 × TIGHT_leash_radius(N)
```

with the published table (N=1: 10.6 · N=2: 13.3 · N=3: 16.0 · N=4: 18.6 · N=5: 21.3).

### The nuance this section adds: which reference point

⚠️ **`AURA_RADIUS` must be pinned to the TIGHT end of the SPREAD knob specifically, not to
whatever spread value the team currently has selected.** With §1's `ENVELOPE_RADIUS(N, s)`
now the general form, `TIGHT_leash_radius(N)` in the blueprint's formula is precisely
`ENVELOPE_RADIUS(N, 0)` — spread value 0, the tight end — held fixed:

```
AURA_RADIUS(N) = 1.1 × ENVELOPE_RADIUS(N, 0)          ← fixed reference, NOT ENVELOPE_RADIUS(N, s_current)
```

This distinction is easy to get wrong and would silently erase the trade if it were: if
`AURA_RADIUS` instead tracked the team's *current* spread order, a loose team's aura would grow
to match its own looseness and it would never actually lose its auras — which defeats the
entire point `DECISIONS_2026-08-03.md` states explicitly: *"a TIGHT team keeps its auras... a
LOOSE team gives them up almost entirely."* The aura radius has to be a fixed yardstick a team
either fits inside (by choosing tight) or does not (by choosing loose); it cannot itself be a
function of the choice being measured.

### Interaction — one lever, three effects, reviewed together

Three mechanisms now push in the same direction against tight play, and none of them should be
retuned independently of the other two:

| mechanism | punishes tight play by | value |
|---|---|---|
| `aoeFalloff` (judged at 3 targets) | rewarding an enemy that stays clumped | already priced, `tools/pool.ts` |
| `CONTAGION_RADIUS` (5.5, `types.ts:800`, unscaled per `ARENA_BLUEPRINT.md` §3 — body-spacing, not board-spacing) | spreading a status between clumped allies | designed, not yet built (`spreadStatus`, roadmap item) |
| `AURA_RADIUS(N)` (this section) | rewards tight play, the counterweight | proposal above |

This is the mechanism that makes SPREAD "a genuine trade rather than a preference"
(`DECISIONS_2026-08-03.md`'s own words): a tight team keeps its auras but concentrates its
exposure to AoE and (once built) contagion; a loose team disperses both but loses proximity
support. **Whenever any one of these three is retuned in future, the other two should be
re-checked in the same pass** — they are one lever (tightness) with three effects, not three
levers that happen to agree today.

### Coverage to the "5 team-auras / 4 enemy-debuff-auras"

`DECISIONS_2026-08-03.md` records these as unblocked by proximity-sizing (the innate audit's 9
held-back fields). ⚠️ **Not verified in this session** — they were not part of the required
reading and were not grepped for; before wiring them to `AURA_RADIUS(N)`, confirm their
location (likely `core.ts` `INNATE_EFFECTS`, per `CLAUDE.md`'s note that `tamerengine`
currently references neither innates nor happiness) and confirm whether an enemy-debuff aura
should use the *caster's own team's* tight reference or the *enemy's* — the natural answer is
the caster's own (an aura radiates from where the caster stands, regardless of whose side is
affected), which is `AURA_RADIUS(N)` unchanged, but this should be confirmed against the actual
fields before implementation rather than assumed here.

---

## 7. Every constant that must become derived rather than absolute

Constants already covered by `ARENA_BLUEPRINT.md` are cited, not re-derived. Constants **not**
in that document's checklist but found spatial during this review are marked ⚠️ **NEW**.

| constant | current | file:line | becomes |
|---|---|---|---|
| `LEASH_RADIUS` | `12` | `types.ts:73` | `ENVELOPE_RADIUS(N, spread)` — §1 |
| `TEAM_AURA_RADIUS` | `9` | `types.ts:823` | `AURA_RADIUS(N)` — §6 |
| `PURSUIT_PROGRESS` | `0.35` | `types.ts:90` | `× k(N)` — §4 |
| `PURSUIT_IGNORE` | `5.0` | `types.ts:89` | candidate `× ENVELOPE_RADIUS` ratio — §4, unmeasured |
| `FIELD_W` / `FIELD_H` | `40` / `22` | `types.ts:29-30` | `GROUND_W(N)` / `GROUND_H(N)` — `ARENA_BLUEPRINT.md` §1 |
| `LINE_RANGE`, `HARD` clamp, `CHANNEL_RANGE`, dash/blink `maxRange`, knockback distance, `KNOCKBACK_SPEED` | various | `types.ts:963-969` + `authorranges.ts` | `× k(N)` — `ARENA_BLUEPRINT.md` §3 |
| `DEPLOY_DEPTH` | `11`, `const` | `types.ts:40` | `6 + N`, but ⚠️ **NEW: must become `let` + a setter**, the same pattern `FIELD_W`/`FIELD_H` already use (`types.ts:29-38`). It is currently declared `const`, so `ARENA_BLUEPRINT.md`'s per-N formula cannot be applied at runtime without this change — the pattern exists, it is just not yet extended to this constant. |
| `MELEE_PRIORITY_SLACK` | `10` | `types.ts:860` | ⚠️ **NEW, not in `ARENA_BLUEPRINT.md`'s checklist.** A world-unit slack for how far past the nearest body a melee unit obeys a target order (`decide.ts:282-291`'s `comboBias × MELEE_PRIORITY_SLACK` term). Spatial, must scale `× k(N)` for the same reason `LINE_RANGE` does — fixed at 10, it is 1.7 deploy-hexes of slack today and a rounding error on a 4x board. |
| `ORDER_REACH` | `12` | `types.ts:876` | ⚠️ **NEW.** Bounds how far past the nearest enemy a `targetPriority` order (and, per §3, a diver's gate) may reach. Same argument as above — must scale `× k(N)`, and §3's diver bounding depends on this scaling landing correctly. |
| `FLANK_ENGAGE_RADIUS` | `4.0` | `engine.ts:859` | ⚠️ **NEW, and high-severity.** Anchored explicitly to melee reach plus a step (`engine.ts:854-858`'s own comment: *"ENGAGE MUST COVER MELEE REACH OR IT CANNOT SEE A MELEE FIGHT"* — this is a bug that was already found and fixed once). Since `CHANNEL_RANGE.melee` scales to `12.0` at `k=4` (`ARENA_BLUEPRINT.md` §3), `FLANK_ENGAGE_RADIUS` must scale identically or flanking goes blind to melee again — the exact same failure mode recurring if this row is missed. |
| `FLANK_SUPPORT_RADIUS` | `2.5` | `engine.ts:863` | ⚠️ **NEW**, same reasoning as above — must track `FLANK_ENGAGE_RADIUS`'s scale so "supported" stays meaningful relative to the new engage radius. |
| `FLANK_ACC_BONUS` | `5` | `engine.ts:853` | **No change** — a flat accuracy-points bonus, not a distance. |
| `fieldDiag()` term in `pickTarget`'s `proximity` score | — | `decide.ts:23`, used `decide.ts:307` | **Already correct**, no change needed. Computed per-call from live `FIELD_W`/`FIELD_H` specifically because an earlier version cached it at module load and silently used the wrong diagonal on any non-default arena (`decide.ts:20-22`'s own comment) — cited here as the one place this class of bug was already fixed once, evidence for treating every other bare constant with equal suspicion. |
| `spacingRadius`'s `u.radius * 2` base | `0.9` (radius) | `engine.ts:195` | **No change.** Body-collision size does not change because the world did — same principle as `DEPLOY_DEPTH`/`CONTAGION_RADIUS` staying fixed per `ARENA_BLUEPRINT.md` §3. |
| `speed`, `BACKPEDAL_MULT`, `DASH_SPEED_MULT`, `KITE_MAX`, `KITE_REFILL`, `ESCAPE_LOCKOUT`, `PURSUIT_PATIENCE`, cast times, cooldowns | various | `types.ts` throughout | **No change** — time/rate constants, not spatial. `ARENA_BLUEPRINT.md` §3's own principle, restated once more because it is the thing most likely to be mis-applied by a future pass: not every constant in these files is a distance. |

---

## 8. What stops a large field becoming a diffuse fight

The brief names four: SPREAD, minimum range, `BACKPEDAL_MULT`, cover as a destination. Each
closes a *different* piece of the failure mode; none of them, alone, is the whole answer, and
this document adds a fifth.

| mechanism | status | closes |
|---|---|---|
| **SPREAD** (§1) | this document specifies it | how far apart a TEAM's own units get — bounds cohesion, says nothing about the gap *between* the two teams |
| **Minimum range** (`ENGAGEMENT_DESIGN.md` B1) | ⚠️ **not built**, external dependency | stops a retreating unit treating the whole ground as one continuous retreat — bounds kiting's *total* distance, not just per-episode (`KITE_MAX` already bounds the episode) |
| **`BACKPEDAL_MULT`** (0.6, `engine.ts:77`) | ✅ shipped | guarantees a committed pursuer eventually closes *any* finite gap — an asymmetry, not a distance bound. Its own comment (`engine.ts:1955-1959`) records the measurement without it: *"a chase NEVER resolves... regardless of field size or speed."* Necessary, not sufficient alone: it guarantees convergence given enough time, not that the time is short enough to be watchable |
| **Cover as destination** (`SPATIAL_MODEL.md` §11.2) | ⚠️ **partially built** — see below | converts "run forever" into "run to a place, then re-engage or lose the engagement" |
| **Pursuit/regroup rework** (§4, this document) | this document specifies it | the failure mode NONE of the above four addresses: dishonest, thrashing pursuit (chase → give up → re-pick something equally unreachable → repeat), as distinct from honest-but-slow convergence |

**Cover's real state today**: `desiredGoal`'s `useCover` block (`decide.ts:606-647`) already
does the *defensive* half — a ranged unit under pressure sidesteps to a point that breaks line
of sight from the nearest melee threat while keeping a shot on its own target. It does **not**
yet do the *offensive* half `SPATIAL_MODEL.md` §11.3 specifies: arriving at cover does not
interrupt the attacker's cast or reset the engagement, and there is no queryable "nearest point
that breaks LOS to a specific attacker" — today's cover-seeking is a 16-point ring-sample
around the unit's own goal (`decide.ts:628-644`), not a directed query. **This is a real gap
against the design, not a nuance** — cover today is a positioning aid, not the
interrupt-and-reset mechanic the diffuse-fight argument depends on.

### Verdict

The four (plus this document's fifth) are **sufficient in principle** — together they cover
team cohesion, retreat distance, chase convergence, and disengagement legibility, which is
every distinct way a large board can fail to resolve a fight. But two are not yet real:
minimum range does not exist at all (correctly named as a blocker by `ARENA_BLUEPRINT.md` §2
and §9 already), and cover-as-destination exists only in its defensive form. **This document's
own structural changes (SPREAD's anchor fix, the pursuit/regroup reuse of the `formation:'keep'`
mechanism) do not depend on either gap closing first** — they are independently valid — but the
diffuse-fight *verdict as a whole* does, and should not be treated as settled until both land
and the board is re-measured.

The measurement dependency stands as stated in `SPATIAL_MODEL.md` §11.4 and
`ARENA_BLUEPRINT.md` §9: scale the field 2x/4x and run `sweep40` before treating any of this as
confirmed. This section is a structural argument for why the design *should* hold, not a
substitute for that data.

---

## 9. Implementation order — cheapest and least risky first

| # | step | depends on | why here |
|---|---|---|---|
| 1 | `DEPLOY_DEPTH` → `let` + setter (§7) | — | mechanical, zero behaviour change alone; a prerequisite for `ARENA_BLUEPRINT.md`'s per-N deploy formula to be usable at all |
| 2 | Scale `MELEE_PRIORITY_SLACK`, `ORDER_REACH`, `FLANK_ENGAGE_RADIUS`, `FLANK_SUPPORT_RADIUS` by `k(N)` alongside `ARENA_BLUEPRINT.md` §3's existing list (§7) | — | cheap, mechanical, no new logic — but must land **before** reach/`CHANNEL_RANGE` scale, or flanking and order-following silently go blind again (the exact bug `engine.ts:854`'s comment already records once) |
| 3 | Replace `LEASH_RADIUS` with SPREAD / `ENVELOPE_RADIUS(N, spread)`, same-side anchor (§1) | — | the single highest-value structural change; everything downstream that depends on the fight actually using the ground waits on this. Reuses the existing `formation` order (`core.ts:534`) and the `coachedValue` blending pattern already proven at `decide.ts:418` |
| 4 | `AURA_RADIUS(N)` off the fixed TIGHT reference (§6) | 3 | cheap once 3 exists — one constant, one call-site swap (`engine.ts:1402`) |
| 5 | Speed formula swap, class band × body (§5) | — | independent of 1–4, can land in parallel. Touches one call site (`engine.ts:198`) plus two small proposed tables. Needs its own sim pass, before and after — it changes who wins every chase in the game |
| 6 | `pickTarget` diver gating (§3) | 3, 5 | structurally independent, but only meaningfully testable once approach speed (5) and formation looseness (3) are both real — sequencing it earlier risks measuring against the wrong baseline |
| 7 | Station / flank lateral resolver (§2) | 3, benefits from 6 | needs `ENVELOPE_RADIUS` to size `FLANK_DEPTH`; more useful once diving (6) gives the flank order something to justify. Largest net-new logic in this document, so latest and most validated |
| 8 | Pursuit / regroup rework (§4) | 3 (station anchor); ideally after `ENGAGEMENT_DESIGN.md` Family A | "give up" should be measuring genuine unreachability, not a still-too-slow approach — sequence last of the structural items |
| 9 | *(external)* Cover interrupt-and-reset, `SPATIAL_MODEL.md` §11.3 | — | not authored by this document — listed only because §8's verdict and §3's diver-diving-into-cover interactions are both weaker without it landing around the same time |
| 10 | Re-run the 2x/4x scaled-field `sweep40` (`SPATIAL_MODEL.md` §11.4 / `ARENA_BLUEPRINT.md` §9) | 1–8 | the gate that turns every formula above from "structurally sound" into "actually balanced," and the point at which the suspended baseline can be reconsidered |

---

## Open items carried forward (not resolved by this document)

- Exact `spreadValue` mapping for `tight`/`keep`/`spread` (`0 / 0.5 / 1`) — plausible, not
  measured.
- `CLASS_SPEED_BAND` and `BODY_SPEED` numeric tables (§5) — proposals; the body table
  specifically needs sign-off from whoever owns body-type identity (`docs/BESTIARY.md`).
- `PURSUIT_IGNORE` scaling formula (§4c) — flagged, not proposed for adoption.
- `DIVE_THRESHOLD` for §3's `isScreened` gate — needs a sim pass, not asserted here.
- `RECOVER_FOR` duration for §4's regroup window — needs a sim pass.
- Whether flank-lateral resolution (§2) should be fixed at deploy or reactive every retarget —
  the same open question `SPATIAL_MODEL.md` §9 Q8 already carries for cohesion generally
  (static vs reactive); inherited here rather than re-opened.
- The five team-auras and four enemy-debuff-auras referenced in `DECISIONS_2026-08-03.md`'s
  innate audit — not verified against source in this session; confirm file:line and caster-vs-
  target reference frame before wiring `AURA_RADIUS(N)` to them (§6).

---

## Cross-system facts this document proposes

Consistent with this project's practice of decisions living in prose docs rather than a
separate registry (`docs/CLAUDE.md`: *"there are no ADRs... the decisions of record live in
prose"*), the constants and formulas above are proposed for adoption into `ARENA_BLUEPRINT.md`
and `ENGAGEMENT_DESIGN.md` directly, not a separate ledger. The load-bearing new facts, for
whoever reconciles the three documents:

- **`ENVELOPE_RADIUS(N, spread)` replaces `LEASH_RADIUS` as the one SPREAD/leash knob**
  (§1) — `ARENA_BLUEPRINT.md` §4 already derived its geometry; this document specifies how
  `Tactics.formation` drives it and fixes its anchor.
- **`AURA_RADIUS(N)` is pinned to `ENVELOPE_RADIUS(N, 0)`** (the tight end), not to whatever
  spread value is currently active (§6) — a nuance `ARENA_BLUEPRINT.md` §5 states the formula
  for but does not explicitly guard against mis-deriving from the wrong reference.
- **`MELEE_PRIORITY_SLACK`, `ORDER_REACH`, `FLANK_ENGAGE_RADIUS`, `FLANK_SUPPORT_RADIUS`
  are spatial constants missing from `ARENA_BLUEPRINT.md` §3's rescale checklist** (§7) — all
  four need to join it before that document's numbers ship.
