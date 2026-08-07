# The arena blueprint

**2026-08-03, revised same day.** The blocking artefact — leash/SPREAD, deploy depth, reach,
minimum range, cover placement and the balance re-baseline are all sized from this document.
Written by the Level Designer, cross-checked against `docs/SPATIAL_MODEL.md`,
`docs/ENGAGEMENT_DESIGN.md`, `docs/ABILITY_BALANCE_REVIEW.md`, `docs/ARENA_DESIGN.md` and the
live constants in `src/tamerengine/types.ts`, `hex.ts` and `maps.ts`.

⚠️ **REVISION NOTE.** The first pass of this document put the "~4x our current largest"
instruction entirely on the VENUE and *shrank* the GROUND (the actual fighting space) to 62×42 —
smaller than the 82.45×59.5 board already shipped. **The user overrode that call: the PLAYING
SPACE itself must be substantially larger. Forget today's sizes as an anchor.** The argument that
motivated the shrink — that `LEASH_RADIUS = 12` already caps every fight to a 24-unit huddle
regardless of board size — was correct, but the conclusion ran the wrong way: **the leash is the
bug to fix, not evidence that a big ground is wasted.** SPREAD replaces it and scales with the
ground, so a bigger ground gets genuinely used rather than sitting empty around a small leashed
huddle. Everything below is re-derived on that basis. §7 (cover vocabulary) is unchanged from the
first pass and is not reproduced in full detail again; the worked numbers inside it are updated.

⚠️ **AREA vs LINEAR, resolved: LINEAR.** *"Far larger... all of them are too small"* reads as a
literal size increase in world units, not a doubled-footprint reading of "4x." The GROUND is
scaled **4× linear at 5v5** against the field the ability pool was actually tuned against
(`FIELD_W/H = 40×22`), landing at **160×88** — which is not a new number invented for this
revision; it is the exact 4x-linear figure `docs/ABILITY_BALANCE_REVIEW.md` §1.1 already
computed and flagged as the scenario to check.

---

## 0. The method changes: the ground is the primary number now

The first pass derived the ground from approach-time-at-current-speed and body-count formation
room, deliberately keeping reach out of the derivation to avoid circularity, and let the venue
absorb all of the "far larger" instruction. That is inverted here:

1. **Fix the linear scale `k` per team size directly**, anchored so `k(5) = 4.0` against the
   pool's tuning baseline (`40×22`) — the number the user has now confirmed. Smaller team sizes
   get a smaller `k`, because a duel does not need the same room a 5v5 needs, but every team size
   still grows substantially past both its current shipped size *and* the first pass's shrunk one.
2. **`GROUND(N) = k(N) × (40, 22)`** — the field keeps its baseline 40:22 (1.818) aspect at every
   team size, which is wide by construction and needs no separate aspect-ratio correction pass.
3. **Reach, then, scales by the SAME `k(5) = 4.0`** applied globally (one authored table, not one
   per league — moves are authored once) — this is no longer circular, because `k` was fixed in
   step 1 from the ground-growth instruction, not backed into from a reach target.
4. **SPREAD/leash is rebuilt on the new ground's geometry** (§4), so the fight's actual footprint
   still scales with `N` and with the tight↔loose choice — it does not simply inherit whatever the
   ground's raw size happens to be.

```
k(N) = 2.0 + 0.5 × (N − 1)          k(1)=2.0 · k(2)=2.5 · k(3)=3.0 · k(4)=3.5 · k(5)=4.0
GROUND_W(N) = k(N) × 40
GROUND_H(N) = k(N) × 22
```

---

## 1. GROUND dimensions per team size

| team | N | k | GROUND W | GROUND H | area | aspect | vs today's shipped 5v5 (82.4×59.5) | vs first-pass GROUND (62×42) |
|---|---|---|---|---|---|---|---|---|
| Wood, 1v1 | 1 | 2.0 | **80** | **44** | 3,520 | 1.82 | 72% linear | 1.9× linear |
| Copper/Tin, 2v2 | 2 | 2.5 | **100** | **55** | 5,500 | 1.82 | 90% linear | 2.2× linear |
| Bronze/Iron, 3v3 | 3 | 3.0 | **120** | **66** | 7,920 | 1.82 | 108% linear | 2.4× linear |
| Silver/Gold, 4v4 | 4 | 3.5 | **140** | **77** | 10,780 | 1.82 | 126% linear | 2.6× linear |
| **Platinum+, 5v5** | 5 | 4.0 | **160** | **88** | 14,080 | 1.82 | **145% linear, 4× area** | 2.7× linear |

Every team size is now larger than its current shipped board, not just the top of the ladder —
which is what *"all of them are too small for the game we are building"* asks for. 1v1 through
3v3 pass today's shipped 5v5 board's own width; 5v5 clears it by 45% linear and lands almost
exactly at 4× its area, which is where the "4x" figure has been sitting, unremarked, in the
ability-balance review the whole time.

**Deploy depth stays small, deliberately not scaled by `k`:**

```
DEPLOY_DEPTH(N) = 6 + N
```

A monster's own collision radius (0.9) does not change because the world around it did — deploy
depth exists to fit N bodies in one or two ranks, which is a body-count question, not a
board-size one. Scaling it by `k` would put a 5v5 deploy zone 44 units deep for no mechanical
reason; keeping it at 11 means all of the ground's growth goes where it is meant to — the room
around and between the two sides, not the room each side stands in before the fight starts.

⚠️ **The "front-line separation" and "corridor" columns below are SUPERSEDED by the decision in
§2** — they described separation as derived from `W`, which is exactly what §2 stops doing.
Kept only long enough to show the replacement inline; `separation` is now the decided constant
from §2 (33.1, independent of `N`), and the flank margin is what the width growth actually buys.

| N | DEPLOY_DEPTH | separation (decided, §2) | flank margin per side (`(W − 2×depth − separation) / 2`) | deploy band width (`H − 2`) |
|---|---|---|---|---|
| 1 | 7 | 33.1 | 16.45 | 42 |
| 2 | 8 | 33.1 | 25.45 | 53 |
| 3 | 9 | 33.1 | 34.45 | 64 |
| 4 | 10 | 33.1 | 43.45 | 75 |
| 5 | 11 | 33.1 | 52.45 | 86 |

Read as: `DEPLOY_DEPTH(N)` still sizes the formation band each side stands in (unchanged, §0);
`separation` is the new independent gap between the two front lines (§2); everything left over
between the deploy bands and the ground edge is flank margin — room for the maneuvering §2's
proposal was written to buy, and it grows with `N` even though separation itself does not.

---

## 2. Why this size does not just produce a diffuse fight

This is the risk I raised in the first pass and it is real — a ground this large, with nothing
else changed, would be exactly the failure mode `docs/ENGAGEMENT_DESIGN.md` warns about. Four
things make the size affordable, and all four are either shipped already or already designed —
this blueprint does not invent a fifth:

1. **SPREAD/leash scales with the ground and stays a fraction of it (§4).** The fight's actual
   footprint — the tight↔loose envelope — never approaches the ground's full size at any setting.
   Even at LOOSE, 5v5's engagement envelope (diameter 66.9, §4) is 42% of the ground's width. The
   rest of the ground is not empty space the fight is expected to fill; it is room for flanking
   routes, cover destinations and camera grandeur that a fight bounded to a fraction of the board
   can use *selectively* rather than being forced to use *entirely*.
2. **`BACKPEDAL_MULT` (already shipped, 40% speed loss while giving ground) means a chase still
   resolves.** The size increase does not weaken this — a retreating unit is still slower than a
   pursuing one by the same fixed fraction regardless of how much ground exists to retreat across.
3. **Minimum range (`ENGAGEMENT_DESIGN.md` Family B1, not yet built, ⚠️ now load-bearing for this
   ground size)** stops a kiter from treating the whole corridor as one continuous retreat — kiting
   remains bounded per episode (`KITE_MAX`) regardless of total ground available, and a ranged unit
   pinned inside its own minimum range has to fight, not run further.
4. **Cover as a destination (§7, unchanged) gives threatened units a *chosen* place to go rather
   than an unbounded direction to flee in** — the annulus rule still places cover between the tight
   and loose envelope radii, so disengagement stays a deliberate, reachable decision at every team
   size, not a function of how big the ground happens to be.

### ⚠️ THE APPROACH PROBLEM IS WORSE THAN STATED, AND THERE IS A CLEANER FIX

**Checked independently.** The paragraph below quotes ~24s to close *"at full speed (6.0 u/s)"*
— but 6.0 u/s requires **DEX 1000**. That is a maximum-DEX archer: **the one unit that does not
want to close.** The units that must cross the field are the slow ones:

| unit | DEX | speed | time to cross 143.5 |
|---|---|---|---|
| tank | 100 | 2.76 | **52.0 s** |
| bruiser | 250 | 3.30 | **43.5 s** |
| mid | 400 | 3.84 | 37.4 s |
| archer | 700 | 4.92 | 29.2 s |

Against an old median fight of **~23.3 s**. ⚠️ **A TANK WOULD SPEND THE WHOLE FIGHT WALKING
AND NEVER ARRIVE.** No closing-speed bonus of a believable size closes a 52-second gap inside a
23-second fight.

### ⚠️ THE FIX IS TO STOP CONFLATING GROUND SIZE WITH DEPLOY SEPARATION

`DEPLOY_DEPTH(N) = 6+N` measures inward from each edge, so separation is dragged along by width:
a 4x wider ground gives a 4x longer walk. **But nothing requires that.**

**A large ground does not have to mean a long approach.** Deploy the teams closer together
inside a large field, and the space becomes what the user actually asked it for:

> *"...it will allow for classes to be more varied — some will try to hang back at the sides, or
> flank, or dive for the weak."*

**Every one of those is a MANEUVERING use of space, not an APPROACH use.** Flanking needs width
beside the fight. Hanging back needs depth behind it. Diving needs a reachable back line. **None
of them needs 143 units of empty ground between the two sides at the opening whistle.**

### ⚠️ DECIDED (2026-08-04): deploy separation is an independent constant, sized from closing time

**Deploy separation is no longer derived from `W`.** It is its own constant, sized from how long
a slow unit should take to reach contact, not from how wide the ground happens to be:

```
TARGET_CLOSE_SECONDS = 12
SLOW_UNIT_SPEED       = 2.76        (tank, DEX 100 — the slowest body that has to close, §2 table)
separation = TARGET_CLOSE_SECONDS x SLOW_UNIT_SPEED  =  12 x 2.76  =  33.1 units
```

**`separation` is a single flat constant, applied at every team size** — the same reasoning as
§3's "applied globally" for reach: the pool's classes and their closing speeds are authored once
and shared across the whole ladder, so there is no team-size argument for a different opening gap
at 1v1 than at 5v5. What changes with `N` is not `separation` but how much *flank margin* the
growing ground buys around it (table below, and §1's deploy table).

| N | GROUND_W | separation | separation as % of GROUND_W | flank margin per side |
|---|---|---|---|---|
| 1 | 80 | 33.1 | 41.4% | 16.45 |
| 2 | 100 | 33.1 | 33.1% | 25.45 |
| 3 | 120 | 33.1 | 27.6% | 34.45 |
| 4 | 140 | 33.1 | 23.6% | 43.45 |
| 5 | 160 | 33.1 | 20.7% | 52.45 |

**This is the property the decision is FOR:** separation is a constant absolute cost, so it
shrinks as a *fraction* of the ground every step up the ladder — 41% of the board at 1v1, 21% at
5v5 — meaning the larger team sizes get proportionally MORE of their (also larger) ground back
for flanking, hanging back and diving, which is exactly the "some will try to hang back at the
sides, or flank, or dive for the weak" brief §2 opened with. A derivation from `W` could never
produce that; it would keep separation as a constant *fraction*, which is the thing being fixed.

**By construction, this also directly answers the tank-never-arrives problem** (the table
earlier in this section): every team size now gives the slowest unit exactly a 12s opening walk,
never 52s, regardless of `GROUND_W(N)`. And because `separation` (33.1) is already inside the
`HARD` reach clamp's new ceiling (44.0, §3), any line with reach ≥33.1 — Warcry, Venomcraft,
Volley, Disruptor, Mender, Siphon, Hexer, Elementalist, Arcanist, Captain (§3's table) — is
already in range of *something* at the opening whistle. Combat does not wait for a walk on this
ground; it waits for whichever side's kit reaches first. Melee lines (Bloodrage 11.2, Duelist
13.6, Assassin 11.2, Warden 12.0, Bulwark 12.0) still have to close the remaining gap, but from
33.1 rather than 143.5 — single digits of seconds, not tens.

**Consequences to check, both flagged as follow-ups, neither a blocker to landing the decision:**

- **Artillery wants some opening distance to matter, so `separation` cannot go to nothing.** 12s
  was chosen to keep a real (if short) window before ranged lines within `separation` come
  online — a lower `TARGET_CLOSE_SECONDS` would compress that window further. Revisit only if
  §9's sim shows the opening reads as instant rather than short.
- ⚠️ **`OPENING_MIT_BONUS` needs a numeric follow-up pass, not a redesign.** It is a flat +20%
  mitigation that holds at full strength for `OPENING_MIT_HOLD = 30s` and fades over the next 15s
  (`src/tamerengine/types.ts`), aimed at delaying first blood because the death cascade — not the
  whole fight's pace — is what reads as bursty. It was tuned against an engine where the opening
  approach ATE INTO that 30s hold window (a 24-52s walk on the old derived separation left little
  or none of the hold still active by first contact). Under the decided 33.1-unit separation, the
  opening approach is single digits to low-teens of seconds for most kits, so first contact now
  lands well INSIDE the 30s hold rather than after it — meaning the guard is live for a much
  larger share of the early exchange than it was tuned for. This may be exactly what "delay first
  blood" wants, or it may now over-suppress the opening burst; it is a number to re-check against
  `sweep40`'s first-kill timing at the new ground size (§9), not to guess at here.

⚠️ **Superseded by the decision above.** This paragraph originally described the *opening
approach* as unsolved dead time at the old, `W`-derived separation (143.5 units, ~24s at full
speed). That problem no longer exists at 33.1-unit decided separation — the opening is now a
short, deliberately-sized close (12s worst case, §2 above), not a walk the sim has to be trusted
to shorten. **What is NOT superseded, and remains this document's load-bearing dependency, is the
REST of the fight.** `ENGAGEMENT_DESIGN.md`'s Family A (closing-speed bonus, gap-closer refund on
landed hit) and Family B (minimum range) were never only about the opening whistle — they govern
every RE-engagement after a kite, a knockback or a reposition, all of which still cross a large
ground (§2's four affordability points still stand). Deploying closer fixed the *first* close; it
does nothing for the fifth one, mid-fight, after a ranged unit has backpedalled across the venue.
Still assumed to land alongside this document; still checked at §9.

---

## 3. Reach and the pool's spatial constants, rescaled by `k(5) = 4.0`

Applied globally (one authored table for every league, per §0 — the 5v5 ground is the balanced
format `CLAUDE.md` already commits to, so it is the scale every league's monsters share).

| constant | today | new (`× 4.0`) |
|---|---|---|
| `HARD` reach clamp | [2.4, 11.0] | **[9.6, 44.0]** |
| `CHANNEL_RANGE` | melee 3.0 / ranged 8.0 / magic 7.0 / support 6.0 | melee 12.0 / ranged 32.0 / magic 28.0 / support 24.0 |
| Dash `maxRange` | 7–9 | 28–36 |
| Blink `maxRange` | 9–14 | 36–56 |
| Knockback/push distance | 2.5–5 | 10–20 |
| `KNOCKBACK_SPEED` | 12 u/s | 48 u/s |

### Full rescaled `LINE_RANGE` (× 4.0)

| line | new | line | new |
|---|---|---|---|
| Bloodrage | 11.2 | Disruptor | 28.0 |
| Duelist | 13.6 | Mender | 32.0 |
| Warcry | 26.0 | Siphon | 26.0 |
| Assassin | 11.2 | Hexer | 30.0 |
| Venomcraft | 34.0 | Elementalist | 32.0 |
| **Volley** | **42.0** | Arcanist | 28.0 |
| Warden | 12.0 | Enchanter | 26.0 |
| Guardian | 18.0 | Captain | 30.0 |
| Bulwark | 12.0 | Demagogue | 24.0 |

⚠️ **Volley's new reach (42.0) is 63% of the 5v5 LOOSE envelope's diameter (66.9, §4)** — a
materially larger *share* of the engagement envelope than today (10.5 is 44% of today's flat
24-unit leash diameter). This is not an error: reach was scaled against the pool's own tuning
baseline (`k=4.0` on `40×22`), while the leash was built fresh from the new ground's geometry
(§4) rather than forced to preserve the old ratio. It means a loosely-spread 5v5 team is
*more* exposed to a long-reach line than before, which is arguably correct — SPREAD is supposed
to cost something against reach, and this is the mechanism doing it — but it is a real shift and
belongs in the §9 sim check, not asserted as intentional without measurement.

`speed` (2.4–6.0 u/s) and every TIME constant (`KITE_MAX`, `ESCAPE_LOCKOUT`, cast times,
cooldowns) are **still unscaled** — rates and durations are not spatial, and the whole point of
§2's dependency on Family A is that the *board* has grown to a size that now genuinely needs
closing-speed help, not that speed should quietly absorb the growth instead.

`CONTAGION_RADIUS` (5.5, "~3 body-widths") stays unscaled for the same reason as `DEPLOY_DEPTH` —
body-to-body spacing does not change because the world did.

---

## 4. SPREAD / leash, rebuilt on the new ground

Unchanged principle (`docs/DECISIONS_2026-08-03.md` #4: SPREAD and the leash are one knob), new
geometry:

```
usable_radius(N) = 0.4 × GROUND_H(N)         (half of H, less a 10%-of-H edge margin)
LEASH_RADIUS(N, spread) = lerp(0.55, 0.95, spread) × usable_radius(N)
```

| N | usable_radius | TIGHT radius / diameter | LOOSE radius / diameter | LOOSE as % of GROUND_W |
|---|---|---|---|---|
| 1 | 17.6 | 9.68 / 19.4 | 16.72 / 33.4 | 42% |
| 2 | 22.0 | 12.1 / 24.2 | 20.9 / 41.8 | 42% |
| 3 | 26.4 | 14.52 / 29.0 | 25.08 / 50.2 | 42% |
| 4 | 30.8 | 16.94 / 33.9 | 29.26 / 58.5 | 42% |
| 5 | 35.2 | 19.36 / 38.7 | 33.44 / 66.9 | 42% |

⚠️ **The engagement envelope holds at a constant ~42% of ground width at every team size, by
construction** — because both `usable_radius` and `GROUND_W` are linear in `k(N)`, the ratio
cancels. That is the number to defend in §9: it says a fight, even at LOOSE, uses under half the
ground at every size, leaving the rest for flank routes, cover and camera — the "room to have
room" §2 argues for, not a target the fight is expected to fill.

Sanity checks: the LOOSE envelope fits inside the ground with margin (still holds by
construction). ⚠️ **The second check does not survive §2's decision and is flagged, not fixed,
here.** It used to read "the LOOSE diameter is smaller than front-line separation at every N
(e.g. 5v5: 66.9 vs. 143.5)" — true when separation was the `W`-derived 143.5. At the now-decided
33.1-unit separation, LOOSE diameter (66.9 at 5v5) is **more than double** the gap between the
front lines, so a fully-LOOSE engagement centred on the opening midpoint would overlap both
deploy bands at kickoff. **Why this is probably not the problem it looks like:** the leash centres
on the fight's actual, moving centroid (§8's `X`), not the static opening midpoint — nobody is
standing at LOOSE spread the instant the whistle blows, and the flank margin (§1, §2) exists
specifically to give the centroid room to drift into as the fight develops, well clear of either
deploy band. But that is an argument, not a check. **Needs verifying, not asserted:** does the
engine actually re-centre the leash on a moving centroid, or does anything anchor it to the
kickoff position long enough for this overlap to matter in the first second or two of a fight?
Added to §9/§10 as a follow-up alongside `OPENING_MIT_BONUS` — both are consequences of the same
decision and neither was checked before this revision.

---

## 5. Auras — now proximity-sized, a spatial constant like reach and SPREAD

**Decided since the first pass: auras are proximity-sized, not team-wide.** `TEAM_AURA_RADIUS = 9`
(flat, reaches the whole team almost always today) is retired. This interacts *directly* with
SPREAD, and the interaction should be a deliberate trade-off rather than an accident:

```
AURA_RADIUS(N) = 1.1 × TIGHT_leash_radius(N)
```

Sized to just clear a tight-clustered team from a roughly central source (1.1× gives a small
buffer over the tight *radius*, not diameter, since most support units cast from within their own
line rather than dead centre) — and to fall well short of a loose-spread team, on purpose.

| N | AURA_RADIUS | TIGHT diameter (covered?) | LOOSE diameter (covered?) |
|---|---|---|---|
| 1 | 10.6 | 19.4 — partial, n/a for a duel | 33.4 — n/a |
| 2 | 13.3 | 24.2 — mostly | 41.8 — no |
| 3 | 16.0 | 29.0 — mostly | 50.2 — no |
| 4 | 18.6 | 33.9 — mostly | 58.5 — no |
| 5 | 21.3 | 38.7 — mostly | 66.9 — no |

⚠️ **This is the trade the coordinator asked to be made deliberate: a TIGHT team keeps its
auras (Enchanter buffs, Guardian wards, Mender's reach) live across nearly the whole formation; a
LOOSE team gives them up almost entirely** — a source near one flank of a loose spread cannot
reach the other. That is a real, board-legible cost for board control, and it is the mechanism
that makes CHA/CON/WIS support kits (the ones whose whole value is proximity-delivered) prefer
tight play, while DEX/assassin kits (`SPATIAL_MODEL.md` §10) prefer loose — two archetypes
wanting opposite SPREAD settings for reasons a player can see on the field, not just read in a
tooltip.

---

## 6. VENUE — now a margin around an already-large ground, not the sole carrier of "4x"

With the "far larger" instruction spent on the ground, the venue's job shrinks to what it should
always have been: stands, ornament and crowd *around* the fight, not a separate spectacle number
carrying growth the ground didn't get.

```
VENUE(N) = 1.35 × GROUND(N)      (linear — a comfortable architectural margin, not a second
                                   independent multiplier)
```

| team | N | GROUND | VENUE | venue area |
|---|---|---|---|---|
| Wood, 1v1 | 1 | 80 × 44 | **108 × 59** | 6,372 |
| Copper/Tin, 2v2 | 2 | 100 × 55 | **135 × 74** | 9,990 |
| Bronze/Iron, 3v3 | 3 | 120 × 66 | **162 × 89** | 14,418 |
| Silver/Gold, 4v4 | 4 | 140 × 77 | **189 × 104** | 19,656 |
| **Platinum+, 5v5** | 5 | 160 × 88 | **216 × 119** | 25,704 |

The venue still widens the fight's presentation without changing what it plays like — the
1.35× margin is small enough that most of what a camera sees at either lens (`ARENA_DESIGN.md`'s
deploy vs. replay `LENS.fit` distinction) is genuinely playable ground, not empty stand-dressing,
which is the direct fix for the failure the leash exposed: a venue that dwarfs its own fight.

---

## 7. Cover — unchanged vocabulary, updated worked numbers

**§7's tag vocabulary and the density/placement reasoning from the first pass stand as written**
(`blocking` / `coverGrade: soft|hard` / `breaksLOS`; the reversal of the "kind is presentation
only" invariant and why that has to be an explicit authored field; the three jobs cover does; the
annulus placement rule). Only the concrete numbers change, because the annulus is defined by the
leash radii, which moved (§4):

**5v5 annulus (where most cover now sits):** between radius **19.36** (TIGHT) and **33.44**
(LOOSE) of the ground's centre — roughly double the first pass's 11.6–20.0, because the leash
itself roughly doubled in absolute terms while staying the same *fraction* of a much bigger board.

**Reference density**, `AREA_PER_PIECE = 300` against the new ground areas (§1), via `pieceCost`
weighting as before — a ceiling to check, not a target:

| N | ground area | reference max pieces |
|---|---|---|
| 1 | 3,520 | 12 |
| 2 | 5,500 | 18 |
| 3 | 7,920 | 26 |
| 4 | 10,780 | 36 |
| 5 | 14,080 | 47 |

⚠️ **These are meaningfully higher counts than the first pass (4–9) and higher than anything
authored today.** At a 5v5 ground nearly 3× the area of today's largest board, this is expected —
but 300 was measured off Tin/Bronze boards an order of magnitude smaller, and applying it
unmodified this far outside its calibration range is exactly the kind of extrapolation
`ARENA_DESIGN.md` itself warns against ("a starting reference, not a rule"). Treat 47 as a ceiling
to sanity-check against `mapsweep`, not a number to author toward directly; the annulus rule (§7,
first pass) constrains *where* cover goes far more tightly than the density law constrains *how
much*, and on a ground this size the annulus is doing most of the real work.

---

## 8. Drawn blueprint — 5v5 ground (160 × 88), schematic

```
                                        GROUND  W=160  H=88
   Y=88 ┌────────────────────────────────────────────────────────────────────────────────┐
        │████████████                                                      ████████████│
        │██  A1  A2██               .-·´¯¯¯¯¯¯¯¯¯¯¯¯¯`·-.                  ██  B2  B1██│
        │██    A3  ██           ,·´       LOOSE            `·,              ██   B3   ██│
        │██  A4  A5██        ,·´       (r 33.4, ⌀66.9)         `·,          ██  B5  B4██│
        │████████████       /        .-¯¯¯¯¯¯¯¯¯¯¯-.              \        ████████████│
        │           ▓      /      ,·´   TIGHT        `·,           \    ▓              │
        │              ▓  |     ,·´  (r 19.4, ⌀38.7)     `·,         |  ▓                │
        │                 |    |         ·  X  ·           |         |                   │
   Y=44 │  DEPLOY A       |     `·,                       ,·´        |      DEPLOY B     │
        │  (depth 11)     |        `·-,               ,-·´           |     (depth 11)    │
        │                  \            `-·.......·-´               /                    │
        │              ▓    \                                      /    ▓                │
        │           ▓         `·,                              ,·´                       │
        │████████████             `·-..                ..-·´              ████████████│
        │██  A1  A2██                   `¯¯¯¯¯¯¯¯¯¯¯¯¯´                    ██  B2  B1██│
        │██    A3  ██                                                      ██   B3   ██│
        │██  A4  A5██                                                      ██  B5  B4██│
        │████████████                                                      ████████████│
   Y=0  └────────────────────────────────────────────────────────────────────────────────┘
        X=0        11 ── DEPLOY A ──          corridor 138          ── DEPLOY B ──   149  X=160
```

⚠️ **This diagram's X-axis is now stale** — it draws deploy bands hugging the ground edges with
a 138-wide corridor, which is the pre-decision `W`-derived layout. Under the decided §2
separation (33.1, constant), the 5v5 bands sit inboard instead, each side carrying its 52.45
flank margin (§1) before the deploy band starts: `X=0 … 52.45 (flank) … 63.45 (DEPLOY A, depth
11) … 96.55 (separation 33.1, front lines here) … 107.55 (DEPLOY B, depth 11) … 160`. Not
redrawn here — the circles, cover annulus and legend below are unaffected by where the bands
sit horizontally, only the axis line and the two `██` blocks' X position need to move on the
next pass. Flagged in §10.

**Legend** (unchanged meaning from the first pass, new numbers):
- `██` deploy band, depth 11, width 86 (§1) — two ranks per side.
- `X` at centre — the fight's centroid once both sides have closed.
- Inner dashed circle — **TIGHT**, radius 19.4, diameter 38.7.
- Outer dashed circle — **LOOSE**, radius 33.4, diameter 66.9 — 42% of the ground's width (§4),
  never more, at any team size.
- `▓` — cover, mirrored 180°, placed in the annulus between the two circles (§7): radius 19.4–33.4.
- The open ground between the deploy bands and the LOOSE envelope — roughly 45 units of clear
  floor on each side at 5v5 — is deliberately not filled with cover or formation; it is the room
  §2 argues the size is *for*: flank routes, camera grandeur, a genuine sense of a large arena
  around a bounded, legible fight.
- The **VENUE** (§6, 216×119 at 5v5) begins past this frame entirely — stands, colonnades, crowd —
  and is not drawn here.

---

## 9. What must be measured to confirm this

Supersedes the first pass's list; the shape of the checklist is unchanged, the numbers to check
are not:

1. **`setFieldSize` to each GROUND value in §1 with deploy bands positioned per the decided
   `separation` (§2, not the old `W`-derived corridor), and re-run `sweep40`.** The single most
   important read now: **time to first contact for a reach ≥33.1 line** (should be ~0s — already
   in range at deploy, §2) and **time to first melee contact** (should be ≤12s by construction,
   §2) against the median-fight baseline (15.3s). If melee contact comes in noticeably over 12s,
   something in deploy placement or pathing is not honouring the decided separation — that is a
   bug against this document, not a sign Family A is needed for the OPENING specifically (Family
   A/B remain needed for mid-fight re-engagement, §2's closing paragraph).
2. **This blueprint's mid-fight pacing (kiting, re-engagement after a knockback or reposition)
   still assumes `ENGAGEMENT_DESIGN.md` Family A and Family B (minimum range) land alongside it
   (§2) — the OPENING approach no longer depends on them (decided separation fixes it directly),
   but repeated re-engagement across a large ground still does.** If Family A/B are deferred,
   check specifically for LATE-fight stalling (a kited ranged unit outrunning melee across the
   flank margin), not opening dead time — that risk is gone.
3. **Re-check `OPENING_MIT_BONUS`'s hold/fade (30s/15s, `src/tamerengine/types.ts`) against the
   new first-contact timing** (§2's decision writeup) — first blood now likely lands well inside
   the 30s hold rather than after a long walk had already burned into it. A numeric pass, not a
   redesign; flagged in §2 and §10.
4. **Re-run `tools/authorranges.ts --force`** with `k = 4.0` (§3), then re-check the Volley
   reach-vs-LOOSE-envelope ratio flagged in §3 (63% vs. today's 44%) — confirm whether that
   shift makes loose-spread ranged play feel like a real SPREAD cost or an overcorrection.
5. **Once SPREAD orders exist**, fight tight vs. loose and confirm the aura-coverage trade-off
   in §5 actually reads — a support kit should visibly lose its auras when its team spreads, not
   merely lose a stat on a sheet the player never sees.
6. **Author one real 5v5 board at 160×88 and run it through `mapsweep`**, then `game_debug_draw`
   + `game_screenshot` at both lenses — confirm the annulus cover placement (§7) reads at this
   scale and the open ground between deploy and the LOOSE envelope doesn't look empty on camera.
7. **`DASH_MAX_TIME` (3.0s, unchanged) almost certainly does not fit blink's new 56-unit
   `maxRange` at any realistic dash speed — recompute before shipping any gap-closer at these
   distances.**
8. **The 300-per-piece density ceiling (§7) is untested this far outside its calibration range** —
   validate with `mapsweep`, not by trusting the arithmetic.
9. **Redraw §8's schematic** with deploy bands positioned per the decided separation (flank
   margin → band → separation → band → flank margin, not band-at-edge → corridor → band-at-edge).

---

## 10. Open flags, gathered in one place

- ✅ **DECIDED (2026-08-04): deploy separation is independent of ground size.**
  `separation = TARGET_CLOSE_SECONDS(12) × SLOW_UNIT_SPEED(2.76) = 33.1` units, flat across every
  team size (§2). This replaces the old `W − 1.5×depth` derivation and resolves the
  tank-never-arrives opening problem directly, without depending on Family A. **Not yet
  reconciled:** §8's schematic still draws the pre-decision band placement (flagged there and in
  §9 item 9) and `sweep40` has not yet been re-run against the new deploy positions (§9 item 1).
- ⚠️ **This document's mid-fight pacing argument (§2) is still conditional on Family A/B
  landing — narrowed by the decision above.** Family A/B are no longer needed to make the
  OPENING approach work (separation fixes that directly); they are still needed for every
  RE-engagement after a kite, knockback or reposition on a ground this large. That is now the
  load-bearing dependency, restated here so it cannot be missed.
- ⚠️ **`OPENING_MIT_BONUS` (flat +20% mitigation, 30s hold / 15s fade, `src/tamerengine/
  types.ts`) needs a numeric follow-up pass, not a redesign.** It was tuned against an engine
  where the old, longer opening walk had already burned into its 30s hold by first contact;
  under the decided 33.1-unit separation, first contact lands much earlier and the guard is now
  live for a larger share of the early exchange than it was tuned for. Check against `sweep40`'s
  first-kill timing (§9 item 3) — this is a value to re-check, not a blocker to the decision above.
- ⚠️ **`TARGET_CLOSE_SECONDS = 12` is a chosen target, not a derived one** — picked to keep a
  short but real window before ranged lines with reach ≥33.1 come online (§2), and to give melee
  lines something to close rather than starting already engaged. A different value in the 10-15s
  range discussed in the original proposal is equally defensible; 12 was picked as the midpoint.
- ⚠️ **`k(N) = 2.0 + 0.5(N−1)` is a chosen ramp, not a derived one** — it was picked to (a) hit
  exactly `k(5)=4.0` and (b) grow smoothly, not to satisfy any other constraint. A different curve
  through the same endpoint is equally defensible; this one is simple and monotonic.
- ⚠️ **`usable_radius = 0.4 × H` and the 0.55/0.95 leash fractions** are unchanged design choices
  from the first pass, now applied to bigger `H` values — not re-derived, still asserted.
- ⚠️ **`AURA_RADIUS = 1.1 × TIGHT_radius`** is a new judgment call (§5), picked to make the
  tight/loose trade-off decisive rather than to hit any existing number — there is no "today's
  aura felt right at X" baseline to anchor it to, since today's aura is flat and team-wide.
- ⚠️ **`VENUE = 1.35 × GROUND`** (§6) is a new judgment call replacing the first pass's `2×
  arenaGridFor`; picked as "a comfortable stands margin" rather than derived from a camera
  measurement — `ARENA_DESIGN.md`'s aspect/framing findings should be re-checked against it once a
  board exists.
- ⚠️ **The 300-per-piece density law is now being applied roughly 3–5× outside the size range it
  was measured on** (§7) — flagged, not fixed, pending `mapsweep`.
