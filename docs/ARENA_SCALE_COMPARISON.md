# Scale, and why the WoW layouts do not transfer as shapes

**2026-08-05.** The studio owner: *"bare in mind this is not to our scale, the characters are far
smaller to fit into that scale."* Correct, and it is the most important thing about the whole
comparison. The WoW compositions transfer as **ratios**, not as drawings — and three of our
ratios are badly off, in ways that explain every cover measurement taken this week.

⚠️ **ON THE WoW NUMBERS.** Blizzard has never published arena dimensions, so anything below in
yards is DERIVED from things that ARE known — spell ranges (melee 5 yd, most casters 30–40 yd)
and the fact that arena trades routinely happen across the map. Our figures are exact, read from
`spatial.gd`. Where a WoW figure is inferred it says so; I am not going to present a guess as a
measurement.

---

## 1. The one ratio that changes everything: reach vs board

| | reach ÷ arena width |
|---|---|
| **WoW, ranged** | ~**0.6 – 0.7** (inferred: a 40 yd cast crosses most of the arena, which is why arena play is full of cross-map trading) |
| **Ours, ranged** | **0.200** |
| **Ours, longest ability in the pool** | **0.275** |

⚠️ **IN WoW EVERYONE CAN HIT EVERYONE FROM ALMOST ANYWHERE. SO COVER IS THE ONLY SOURCE OF
SAFETY.** That single fact is why a WoW arena needs pillars at all: without them, a 40-yard cast
reaches every square of the map and there is nowhere to be safe. The pillar is not decoration, it
is the *entire* defensive layer.

**On our board, distance already provides safety.** Our longest-ranged monster covers 27% of the
arena's width. The natural state of two units on our field is *out of range of each other*. Cover
is therefore **redundant with distance** — it duplicates protection the geometry already gives
away for free.

That is the honest explanation for the measurements: cover-seeking looked like noise not because
the AI is bad, but because **there is little for cover to add on a board this size.**

Melee, by contrast, matches almost exactly — WoW's 5 yd in a ~65 yd arena is ~0.08; ours is
**0.075**. So our *melee* game is at WoW's scale and our *ranged* game is at roughly half of it.

---

## 2. The ratio the studio owner spotted: body vs board

| | body : arena width |
|---|---|
| **WoW** | ~1 : 30–40 (inferred from character height against a ~65 yd arena) |
| **Ours** | **1 : 80** |

Our monsters are **proportionally about half the size** of a WoW character on their arena. The
schematics therefore flatter us: drawn at our ratio, the pieces on those sheets would be
noticeably smaller relative to the floor than they appear.

⚠️ **AND THE CONSEQUENCE IS NOT COSMETIC — IT IS ABOUT WHO CAN HIDE.**

---

## 3. ⚠️ THE FINDING: WoW BODIES STACK, OURS CANNOT

This is the mechanical difference that matters most, and it is not about size at all:

- **In WoW, player collision is negligible.** A whole team can stack on one pillar. Five players
  can share a single blocker's shadow, which is exactly what makes a four-pillar map work — each
  pillar is a *team-sized* piece of cover.
- **In ours, bodies are solid.** `BODY_RADIUS = 2.2` and `_separate()` keeps every pair 4.4 units
  apart, deliberately (`AUTOBATTLER_DESIGN.md` #10: *"Solid bodies. Monsters block each other; a
  front line genuinely shields a back line."*).

So cover that shelters a **team** must be at least as wide as the team's frontage:

```
a 5-monster line needs 22.0 units of frontage (5 bodies, touching)

  pillar   6.2 wide  =  1.4 bodies  ->  shelters ONE monster
  wall    35.2 wide  =  8.0 bodies  ->  shelters the whole line, twice over
```

⚠️ **A NAGRAND-STYLE PILLAR IS PHYSICALLY INCAPABLE OF DOING ITS JOB IN OUR GAME.** It is 1.4
bodies wide. In WoW that same pillar hides a full team because the team occupies a point; in ours
it hides one monster and the other four stand in the open beside it.

**So swapping pillars for long walls was right for a reason I had not identified at the time.** I
justified it as "walls cast longer shadows"; the real justification is that **only a wall is wide
enough to shelter a formation whose bodies cannot overlap.** Pillars were never viable at our body
scale — the earlier 8-pillar configuration was 8 pieces that could each hide 1.4 monsters.

---

## 4. How line of sight actually behaves differently

Same `cover_between` maths, very different feel, because of piece *shape*:

| | shadow it casts |
|---|---|
| **Square/round pillar** (WoW) | **Omnidirectional.** Roughly the same shelter from every angle — a place to *stand*. Its average projected width is ~1.27 × its side. |
| **Long thin wall** (ours) | **Directional.** Enormous shelter from two sides, almost none from the other two. Its average projected width is ~0.64 × (length + thickness) — for our 35.2 × 4.0 wall that is ~25 units, about **3× a pillar's**. |

Both are legitimate, but they are different tactical objects:

- a **pillar** is a *position* — "hold behind it", and it works whoever is shooting;
- a **wall** is a *line* — it protects an approach and does nothing at all from the flank.

⚠️ **This has a direct implication for orders, which is where our game differs most.** A player
who commits *"hold the north pillar"* gets protection regardless of how the fight develops. A
player who commits *"hold behind the west wall"* has made a bet on **which direction the enemy
comes from** — and if the enemy flanks, the wall is worthless. For a game built on *commit, then
observe*, the wall is the more interesting object: it makes cover a **read**, not a safe default.

---

## 5. Where our numbers actually sit

| ratio | WoW (inferred) | ours (exact) | verdict |
|---|---|---|---|
| melee reach ÷ arena width | ~0.08 | **0.075** | ✅ matched |
| ranged reach ÷ arena width | ~0.6–0.7 | **0.200** | ⚠️ **~3× too small** — distance replaces cover |
| body ÷ arena width | ~1:30–40 | **1:80** | ⚠️ ~2× too small |
| major cover ÷ body | ~4–8 bodies (team-sized) | wall **8.0** ✅ / pillar **1.4** ❌ | walls right, pillars useless |
| major LoS pieces per map | **1 – 4** | **6 blocking of 24 total** | ⚠️ far too many, and unnamed |
| bodies can stack | **yes** | **no** | ⚠️ the difference that sizes all cover |

---

## 6. What follows

**The layouts are still worth adopting — but the pieces must be sized in BODIES, not copied in
proportion.** A Nagrand square at our scale is four blockers each ~22+ units across (five bodies
of frontage), not four 6-unit pillars. That is a much heavier-looking arena than the WoW
schematic, and it is the correct translation.

Two open questions this raises, both real decisions rather than tuning:

1. **Is the board too big for the pool's reach, or is the pool's reach too short for the board?**
   Matching WoW's ~0.6 would mean either shrinking the ground to roughly 140 wide, or roughly
   doubling reach again. ⚠️ Both are large changes and both move every balance number; the ratio
   has been 0.275 since before this week's rescale, so this is a pre-existing property of the
   design, not something recently broken.

2. **Do we want cover to be a safe default or a read?** Pillars give the first, walls the second.
   Our inability to stack bodies pushes hard toward walls, and *commit-then-observe* pushes the
   same way — but it means a player who guesses the approach wrong gets punished by terrain, and
   that has to be legible or it will read as unfairness.
