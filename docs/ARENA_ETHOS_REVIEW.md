# Our arena ethos, reviewed against the WoW blueprints

**2026-08-05.** The studio owner supplied tactical schematics for all sixteen WoW arenas — which
answered the five maps `WOW_ARENA_REFERENCE.md` had to flag as "thin written geometry", and
showed several structural facts no prose source stated. This is what the blueprints say, and what
it means for `arena_layout.gd` and `ARENA_DESIGN.md`.

---

## 1. Five findings that only the drawings reveal

### ⚠️ 1.1 THE CENTRE IS EITHER OPEN OR IT IS THE OBSTACLE — and it splits 8/8

This is the cleanest pattern on the sheet and no written source mentioned it.

| open centre, cover on a ring | the centre IS the cover |
|---|---|
| Nagrand · Tol'viron · Nokhudon · Robodrome | Blade's Edge (raised bridge) · Dalaran (raised centre) |
| Maldraxxus · Ashamane's Fall · Hook Point | Ruins of Lordaeron (central tomb) · Black Rook Hold (dais) |
| Empyrean Domain (glass floor is walkable) | Mugambala (upper platform) · Enigma (static core) |
| | Cage of Carnage (metal platform) |

Eight and eight. That is not an accident, it is a **design axis** — and it decides the whole
character of a fight. An open centre means the middle is the killing ground and cover is where you
retreat TO. An occupied centre means the middle is the prize and everything happens around it.

⚠️ **We have neither.** `arena_layout.gd` samples pieces into an annulus between the tight and
loose radii, which produces "cover vaguely ringing a middle" every single time. We have one weak
version of one of the two families and no way to author the other.

### ⚠️ 1.2 OUR SYMMETRY RULE FORBIDS THREE SHIPPED WoW LAYOUTS

`arena_layout.gd` generates in **180° rotational pairs** and `ARENA_DESIGN.md` treats that as the
fairness guarantee. But the blueprints show **Robodrome (3-pillar triangle)**, **Maldraxxus
(triangular major LoS)** and **Ashamane's Fall** using layouts that are *mirror*-symmetric across
the spawn axis and **cannot** be 180°-rotationally symmetric — a triangle has no 180° partner.

Both rules are fair. They are not the same rule:

- **180° rotation** maps spawn A onto spawn B *and* flips top/bottom.
- **Mirror across the spawn axis** maps A onto B and leaves top/bottom alone.

⚠️ Mirror symmetry is the weaker constraint and it admits strictly more layouts, including every
odd-numbered arrangement. Our rule is not wrong; it is **narrower than it needs to be**, and it
excludes a third of WoW's compositions for no fairness benefit.

### ⚠️ 1.3 SPAWNS ARE NOT ALWAYS ON THE LONG AXIS

Five of sixteen spawn on the **short** axis — Blade's Edge, Black Rook Hold, Hook Point,
Maldraxxus, Cage of Carnage — with the arrows on the schematics coming from top and bottom rather
than left and right.

That matters more than it sounds, because **cover's orientation relative to the approach is the
real variable**. Blade's Edge's bridge runs *across* the teams' path: it is a wall they must go
under, over or around. The same bridge rotated 90° would be a spine they advance along. Same
geometry, opposite fight.

⚠️ We always spawn on the long axis (`deploy_positions` puts teams at ±x), so we have exactly one
of the two relationships and no way to express the other.

### ⚠️ 1.4 THERE IS A SIZE HIERARCHY — "major LoS" IS ITS OWN LEGEND ENTRY

The schematics legend distinguishes **major LoS** from everything else, and the maps use it:
Ruins of Lordaeron is *one central tomb plus smaller tombstones*; Hook Point is *four crate blocks
plus one small centre piece*; Black Rook Hold is *a central dais plus offset ruined pieces*.

So a WoW arena is typically **1 dominant piece + 2–4 secondary + a few accents** — a clear
hierarchy of importance.

⚠️ Our `KIND_TABLE` has ten kinds whose footprints span 4.4 to 35.2 units, but `_pick_spec` draws
a grade and then a kind **uniformly within it**, so a board gets a random assortment with no
dominant piece and no deliberate hierarchy. Every board is a bag of similarly-important things.

### 1.5 Ramps are first-class, and elevation is roughly a third of the roster

"ramp" is its own legend symbol. Blade's Edge has **six**; Cage of Carnage has **four, one at each
corner**. Elevation appears in Blade's Edge, Tiger's Peak, Dalaran, Mugambala, Robodrome (one
ramped pillar), Cage of Carnage and Empyrean — call it 6–7 of 16.

⚠️ `ARENA_DESIGN.md` bans elevation outright: *"NO ELEVATION. The ground is flat; verticality is
decoration and cover only. Readability wins, and every arena would otherwise need its high ground
BALANCED across a 20-board pool."* **That reasoning is still sound and I am not proposing we
overturn it** — but it should be recorded honestly that it costs us a tool WoW uses on a third of
its maps, and that WoW's answer to the balance problem was *ramps everywhere*, not avoidance.

---

## 2. What our existing ethos already gets right

Worth stating, because the review is otherwise all corrections:

| our rule | verdict against WoW |
|---|---|
| Symmetric layouts guarantee fairness | ✅ **confirmed** — every WoW map is symmetric about its spawn axis |
| Cover sits between the tight and loose radii, not at the edges | ✅ **confirmed** — cover clusters near the contested middle on every map |
| Deploy zones kept clear of cover | ✅ **confirmed** — no schematic puts a blocker in a spawn |
| "Every arena is one built place" (architecture, not scattered props) | ✅ **strongly confirmed** — every map is a *place*, and none is a field of debris |
| A density ceiling exists at all | ✅ right instinct, ⚠️ wrong number — see §3 |

---

## 3. The number that is most wrong: piece count

| | major LoS pieces | total placed pieces |
|---|---|---|
| **WoW, typical** | **1–4** | ~3–7 including accents |
| **Ours, today** | 6 blocking | **24** |

Every WoW arena is legible as a sentence — *"four pillars around an open centre"*, *"a raised
bridge with six ramps"*, *"a central dais with offset ruins"*. Ours is legible as *"twenty-four
things"*.

⚠️ **This is the root of the cover measurements that have gone nowhere.** We measured
LOS-blocking cover at **0.909% of the ground** spread across six small pieces, and cover-seeking
came back as noise. A Nagrand pillar is a *landmark* — you can name it, order a monster to hold
behind it, and see the consequence. Six anonymous walls scattered by an rng are weather.

---

## 4. What I would change, in order of value

**1. Author named layouts instead of sampling positions.** Three or four to start, taken straight
from the blueprint families:
- `four_pillar` — Nagrand/Tol'viron/Nokhudon: four blockers around an open centre
- `central_mass` — Lordaeron/Black Rook Hold: one dominant central piece plus two offset accents
- `spine` — Hook Point/Blade's Edge: a long wall with gaps, across or along the approach
- `triad` — Robodrome/Maldraxxus: three blockers, mirror-symmetric about the spawn axis

Vary them by **material and palette** exactly as `CLAUDE.md` already plans for Platinum-and-above.
That converts our arenas from *random* to *composed*, which is what Blizzard means by *"eliminate
randomness as much as possible."*

**2. Relax symmetry from 180°-rotational to mirror-about-the-spawn-axis.** One-line change in
intent, unlocks every odd-count layout including the triad.

**3. Introduce a size hierarchy.** One dominant piece per board, then secondaries, then accents —
rather than a uniform draw.

**4. Make "open centre vs occupied centre" an explicit property of a layout**, since the
blueprints say it is the single biggest determinant of how a fight plays.

**5. Allow the spawn axis to be short OR long**, so cover can be authored across the approach as
well as along it.

⚠️ **Not proposed: elevation.** The readability argument in `ARENA_DESIGN.md` still holds for a
camera pulled back to 20–40px silhouettes, and it is a much larger change than the four above.
Recorded as a known, deliberate gap rather than an oversight.

---

## 5. ⚠️ The caveat that still governs everything

From `WOW_ARENA_REFERENCE.md` §4, and it does not weaken with better blueprints: **a WoW pillar
exists to be danced around in real time, and our player may never intervene.** Adopting these
shapes only pays if each one becomes something a player can *pre-commit to* — "hold the left
pillar", "spine, then flank" — and can *read afterwards* in the report.

A named layout helps with exactly that, and an anonymous scatter cannot: you cannot give an order
about a thing that has no name.
