# All sixteen WoW arenas, reviewed one at a time

**2026-08-05.** Companion to `ARENA_ETHOS_REVIEW.md`, which covers the aggregate patterns. This
one takes each map on its own terms and asks the only question that matters for us: **what does
this specific composition do, and is it worth stealing for a game where the player cannot
intervene?**

⚠️ **CONFIDENCE IS NOT UNIFORM AND THE SOURCE SAYS SO.** The supplied schematics badge nine maps
**TACTICAL SCHEMATIC** and seven **SIMPLIFIED / APPROX.** Those seven are almost exactly the maps
whose written geometry was also thin on the wikis — two independent sources agreeing on which
maps are less well documented. Entries below are marked accordingly; treat a `~` entry as a
sketch of a composition, not a survey of one.

Verdicts use three levels: **ADOPT** (build this shape), **ADAPT** (the idea transfers, the
mechanism does not), **SKIP** (depends on something we do not have or have banned).

---

## The Burning Crusade — the originals

### 1. Nagrand Arena / Ring of Trials ✔ tactical
**Ellipse · spawns long axis · 4 square pillars in a square · OPEN CENTRE · no elevation**

The purest statement of the form: four identical blockers, equidistant, ringing an empty middle.
Every pillar is interchangeable, so the composition asks *which* pillar, never *whether*. Symmetry
is four-fold, so it is fair under any spawn arrangement.

> **ADOPT — this is our `four_pillar` layout.** It is the single most-copied arena in the game
> (Tol'viron is explicitly a reskin of it, Nokhudon and Empyrean are variants), it needs no
> elevation, and "hold the north-west pillar" is an order a player can give and read back.

### 2. Blade's Edge Arena / Circle of Blood ✔ tactical
**Rectangle · spawns SHORT axis · raised bridge across the middle, 2 lower pillars beneath, 6 ramps · OCCUPIED CENTRE · elevation central**

The most three-dimensional map in the game. The bridge runs **perpendicular to the approach**, so
it is a wall both teams must resolve; the pit beneath is a second, lower arena with its own two
pillars. Six ramps exist purely so the elevation never becomes a trap.

> **SKIP the elevation, ADOPT the orientation.** `ARENA_DESIGN.md` bans high ground and that
> reasoning holds. But the *bridge-across-the-approach* idea survives flattened: a long wall
> perpendicular to the spawn axis, with gaps, is the same decision without the Z. ⚠️ And note the
> six ramps — WoW's answer to "elevation is unfair" was **more access**, not less height.

### 3. Ruins of Lordaeron ✔ tactical
**Ellipse · spawns long axis · one large central tomb + 2 small tombstones + a slime pool with 2 more small LoS · OCCUPIED CENTRE**

The clearest example of the **size hierarchy**: one dominant piece that defines the map, then
four accents that only matter once you are committed. The slime pool adds a soft hazard zone
without blocking anything.

> **ADOPT — this is our `central_mass` layout**, and it is the one that most directly fixes our
> "twenty-four equally-unimportant things" problem. One landmark you can name, plus texture.

---

## Wrath of the Lich King

### 4. Dalaran Arena / Sewers ✔ tactical
**Rectangle · spawns long axis · raised central square with stairs, crates on its edges, a water pipe in the middle · OCCUPIED CENTRE · elevation central**

The raised square *is* the map. Crates on its lip give cover to whoever holds the high ground; the
pipe intermittently blocks LoS on a timer, which is the only surviving dynamic blocker in WoW.

> **ADAPT.** The timed blocker is genuinely interesting for us *because* we cannot intervene — a
> periodic LoS break is something a player can plan around in advance, which is exactly our
> fantasy. ⚠️ But it is also the mechanic whose more ambitious cousin got Ring of Valor deleted.
> Worth a proposal, not a default.

### 5. Ring of Valor ⚠️ REMOVED
**Oval · 4 rising/lowering platforms, moving pillars, spike traps, intermittent fire walls**

The most dynamic arena Blizzard ever shipped, and the only one they removed.

> **SKIP, and treat as a warning.** Every element here is a moving obstacle, and the map lasted
> three years. ⚠️ For an autobattler this is doubly disqualifying: geometry that changes during a
> fight makes a pre-committed order unreadable — the player's plan is invalidated by furniture.

---

## Mists of Pandaria

### 6. Tol'viron Arena ✔ tactical
**Ellipse · spawns long axis · 4 pillars in a square · OPEN CENTRE · no elevation**

Self-described as *"based on the simplistic Nagrand Arena — the only difference is art style and
the direction of the pillars."*

> **ADOPT as evidence, not as a separate layout.** ⚠️ This is the single most useful map on the
> sheet for us, because it proves Blizzard's own reuse policy: **one composition, two art
> treatments, shipped as two arenas.** That is exactly what `CLAUDE.md` plans for Platinum and
> above — "an interchangeable pool of 5v5 grounds differentiated by colour and material." Tol'viron
> is the proof that players accept it.

### 7. The Tiger's Peak ✔ tactical
**Rectangle · spawns long axis · 2 statue pillars centre + 2 full-width raised platforms flanking · OCCUPIED CENTRE · elevation flanking**

Verticality as the *main* tool: the platforms run the full width above and below, reached by
outer stairs, so the map is three lanes stacked in Z.

> **SKIP.** Almost everything this map does is elevation, and flattened it becomes two statues in
> an empty box. Nothing left worth taking.

---

## Legion

### 8. Ashamane's Fall ~ simplified
**Octagon · spawns long axis · 2 small diamonds + 1 rectangle + 2 circles, "open cross-lanes" · OPEN CENTRE**

Five blockers of three different shapes and sizes, arranged to create diagonal lanes rather than a
ring. Mirror-symmetric about the spawn axis; **not** 180°-rotational.

> **ADAPT.** The valuable idea is **cross-lanes** — cover placed so it creates diagonal sightlines
> rather than a doughnut. Our annulus sampling structurally cannot make a lane. ⚠️ And this is one
> of the three maps our 180° rule forbids outright.

### 9. Black Rook Hold Arena ~ simplified
**Ellipse · spawns SHORT axis · one central raised dais + 2 offset irregular ruins · OCCUPIED CENTRE**

The minimal case: **one** major blocker. The two ruined pieces are deliberately *offset* — not a
mirrored pair, but placed so each team meets one on its approach.

> **ADOPT the count.** One dominant piece is a legitimate whole arena. ⚠️ It is also the strongest
> argument against our density law: WoW will ship a competitive map with a single major blocker,
> and we generate twenty-four pieces.

---

## Battle for Azeroth

### 10. Hook Point ~ simplified
**Rectangle · spawns SHORT axis · 4 crate blocks in a rough square + 1 small centre piece · "compact dockyard lanes"**

Tight, boxy, urban. The blocks make corridors rather than a ring; the small centre piece breaks
the middle corridor.

> **ADAPT — this is our `spine`/lanes layout.** ⚠️ Note it is *compact*: the schematic reads as
> the smallest playable area on the sheet. Blizzard's own taxonomy sorts maps by "size (large and
> small)", and we currently have exactly one size.

### 11. The Mugambala ~ simplified
**Hexagon · spawns long axis · raised central platform + lower outer ring + 2 offset blocks · OCCUPIED CENTRE · elevation central**

Three separate wide-open areas with minimal pillars — and a standing *"Remove Mugambala"* thread
on the official forums.

> **SKIP, and learn from it.** ⚠️ The most disliked map in the pool is the one with the least
> cover in the largest space. That is *precisely* the shape our 352×194 ground with 0.909%
> LOS-blocking cover currently is. This map is a warning about the arena we have already built.

### 12. The Robodrome ✔ tactical
**Ellipse · spawns long axis · 3 rectangular pillars in a triangle, one of them ramped · OPEN CENTRE**

Odd-numbered cover. One apex piece, two base pieces, mirror-symmetric about the spawn axis.

> **ADOPT as `triad`.** An odd count means the two teams cannot mirror each other's play piece for
> piece, which creates asymmetric decisions from a symmetric map. ⚠️ Impossible under our current
> 180° rule — a triangle has no 180° partner. This single map is the best argument for relaxing to
> mirror symmetry.

---

## Shadowlands

### 13. Empyrean Domain ✔ tactical
**Hexagon · spawns long axis · 4 pillars + a central glass floor · OPEN CENTRE (walkable)**

A Nagrand square with a marked-but-walkable centre. The glass floor is a *visual* landmark that
costs nothing mechanically.

> **ADAPT the glass floor idea specifically.** A centre that is visually distinct but mechanically
> open gives the player a shared reference point — *"they took the middle"* — for free. For a game
> read entirely by watching, a free landmark is worth more than it costs.

### 14. Maldraxxus Coliseum ~ simplified
**Ellipse · spawns SHORT axis · 3 major blocks in a triangle + a small open hub · OPEN CENTRE**

The second triad, spawning across the short axis.

> **ADOPT as a variant of `triad`.** Same composition as Robodrome with a rotated approach — which
> is itself the lesson from `ARENA_ETHOS_REVIEW.md` §1.3: **the same cover, met from a different
> angle, is a different map.** Two arenas out of one composition.

### 15. Enigma Crucible ~ simplified
**Hexagon · spawns long axis · 4 blocks around a static central core, open outer ring · OCCUPIED CENTRE**

⚠️ The design history is the valuable part: the original concept had **a switch that reconfigured
the central pillars** — cover you could create for yourself or deny to the enemy — cut in testing
*"due to pathing and line-of-sight issues."*

> **SKIP the switch, note the graveyard.** Blizzard tried player-controlled cover and could not
> ship it. ⚠️ That is the second dynamic-cover idea on this sheet that died (Ring of Valor being
> the first). Two independent failures is a strong prior against us attempting it.

### 16. Nokhudon Proving Grounds ~ simplified
**Ellipse · spawns long axis · 4 large diamond structures around an open centre · OPEN CENTRE**

Nagrand again, with bigger, rotated blockers.

> **ADOPT as evidence.** Third confirmation that four-around-an-open-centre is the workhorse. The
> diamonds are notably **large** relative to the map — closer to Blade's Edge's bridge in mass
> than to Nagrand's pillars.

---

## The War Within

### 17. Cage of Carnage ✔ tactical
**Ellipse · TRAPDOOR starts (short axis) · central metal platform + ramps at all four corners · OCCUPIED CENTRE · elevation central**

Newest map. Teams arrive through trapdoors rather than gates, and every corner has a ramp onto the
central platform.

> **ADAPT the four-corner access.** Four symmetric approach routes onto one central mass is a
> clean way to make a central obstacle contested rather than owned. Flattened, that becomes a
> central block with four clear lanes around it — buildable today.

---

## Tally

| verdict | maps |
|---|---|
| **ADOPT** | Nagrand, Lordaeron, Black Rook Hold, Robodrome, Maldraxxus, Nokhudon, Tol'viron *(as reuse evidence)* |
| **ADAPT** | Blade's Edge *(orientation only)*, Dalaran *(timed blocker)*, Ashamane's *(cross-lanes)*, Hook Point *(compact lanes)*, Empyrean *(free landmark)*, Cage of Carnage *(four-corner access)* |
| **SKIP** | Ring of Valor *(deleted; moving cover)*, Tiger's Peak *(pure elevation)*, Mugambala *(the failure mode we already have)*, Enigma's switch *(cut in testing)* |

**Four compositions cover the adopt list**, which is the whole point:

1. `four_pillar` — Nagrand, Tol'viron, Nokhudon, Empyrean
2. `central_mass` — Lordaeron, Black Rook Hold, Cage of Carnage, Dalaran
3. `triad` — Robodrome, Maldraxxus
4. `lanes` — Hook Point, Ashamane's Fall, Blade's Edge flattened

⚠️ **Sixteen shipped arenas reduce to four compositions plus art.** That is the finding that
should govern our generator, and it is exactly what `CLAUDE.md` already predicted for
Platinum-and-above without knowing WoW had proved it.
