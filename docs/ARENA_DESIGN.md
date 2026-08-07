# Arena design theory

**Read this before authoring or changing any arena layout.** `ART_DIRECTION.md` says what
the battlefield must look like; this says what an arena must *be*. Every rule here came
out of a board that was rejected, and the ones with a ⚠️ are enforced by `mapProblems` or
`arenas.test.ts` rather than by memory.

---

## 1. The density law

> ⚠️ **One piece of cover per 300 square units of floor. Hard ceiling.**
> `maps.ts:AREA_PER_PIECE` · enforced in `mapProblems`

| board | area | allowed |
|---|---|---|
| Wood, 1v1 | ~1263–1426 | **4–5** |
| Copper / Tin, 2v2 | ~1330–1970 | **4–7** |
| Bronze, 3v3 | ~1940–1970 | **6–7** |

**Why a number and not judgement.** "Cluttered" was the single most repeated note across
four leagues of review. Every time it was answered by hand — trim two here, drop a pair
there — it came back on the next board, because nothing stopped the next author filling
the floor again. A number that fails the suite does.

⚠️ **Area, not piece count, and not team size.** A flat cap would make the 1263-unit Long
Yard and the 1971-unit Blowing House equally busy, which is the mistake itself. Team size
already drives area through `arenaGridFor`, so measuring against area picks it up for free
and stays correct for the 4v4 and 5v5 boards nobody has authored yet.

⚠️ **It counts EMITTED pieces, not authored ones.** `build` mirrors, so an author typing
three obstacles ships six — and six is what the player sees, so six is what "cluttered"
means. Judging the authored list would let the rule be doubled by construction.

**Where 300 comes from:** the three Tin halls that passed review sit at 350–490 square
units per piece. The two boards that drew "cluttered" sat at 210–220. 300 is the line
between them — which is what a threshold is for, rather than a round number.

---

## 2. Every arena is one built place

⚠️ **Architecture is the default; trade is the accent.** An ore bin, an anvil, a crucible
and a sluice are things from a *working yard*. Scattered across a fighting floor with a
crowd watching, they read as objects someone left out rather than as a place built for a
contest. A wall, a colonnade, a ruin, a channel — these are what an arena is *made of*, so
they need no excuse for standing there.

**At most one or two trade pieces per board**, and only where a working yard would actually
keep them. The league still reads without them: the stone is tinted by `venue.masonry`, the
floor is the league's, and the lamp is the league's.

⚠️ **A piece must be justifiable by the building.** If you cannot say what the structure is
and why that object belongs to it, the object is decoration and the board will read as
random. Tin's furnace pair was cut for exactly this — it was earning its place by being
tall, and a pier does height honestly.

### Themes are not restricted to the league's material

A circuit named after a metal does not mean every ground on it is a foundry floor. Boards
may be built around:

| theme | built from |
|---|---|
| **halls and courts** | wall runs, colonnades, gateways |
| **ruins** | ruined walls, broken piers, tumbled coursing |
| **greenery** | ivy-grown walls, thickets, treelines — an abandoned works |
| **water** | leats, sluices, canals and moats *instead of* solid cover |

Tin's Wash Pool is the worked example: a colonnaded wash court nobody has run in years,
ivy over all of it, still unmistakably Tin from the stands, the floor and the lamp.

---

## 3. What cover is FOR

Cover exists to **create decisions**, not to fill space. Two jobs, and a piece that does
neither should not be there:

1. **Break a straight line.** A monster crossing an empty board walks the shortest path,
   and every fight on it opens identically. A piece that makes the direct route worse than
   a route around it is doing its job.
2. **Give a reason to stand somewhere.** Cover you can put at your shoulder, shoot past, or
   fall in behind turns "where do I go" into a question with an answer.

⚠️ **Fewer and larger, always.** Five small pieces give a board where nothing fully blocks a
lane and every position is about as good as every other — busy, with no decision in it. One
wall a third of the board wide is a real obstacle: you go round it, and *which end* you pick
matters. ⚠️ Titan's Rest is the standing evidence — small blocks each break a sight line
cheaply and stall the exchange; big blocks measured harmless.

⚠️ **Check it with the sim, not the eye.** `npx tsx tools/mapsweep.ts` — every board must
resolve 40/40. Cover that stalls fights is a balance bug wearing an art change's clothes.

---

## 4. The constraints an author cannot argue with

All enforced; all learned from a board that shipped wrong.

| rule | why | where |
|---|---|---|
| Nothing in a deployment band | a monster spawning on a stump reads as clipping | `mapProblems` |
| Nothing crosses the centre line | `build` mirrors; a piece at `x` reappears at `w−x−width` and overlaps itself | `mapProblems` |
| A centrepiece sits at exactly `(w − size) / 2` | it is its own 180° partner and is emitted once; off by a hair and you get two | `mirror` |
| Footprint depth ≤ width × sprite aspect | otherwise the sprite draws shorter than the ground it blocks | `arenas.test.ts` |
| Drawn height < 3.4 (cover) / 7.0 (upright architecture) | cover you shoot **over** must not hide the fight; a pillar you shoot **past** should be tall | `arenas.test.ts` |
| Scenery lives fully outside the field | decoration on the pitch is cover the player sees and the engine cannot path round | `mapProblems` |
| Aspect ratio ≥ ~1.5, and wider is better | below it the camera shows no venue at all — see below | judgement, not yet a guard |
| No two boards share a LAYOUT SIGNATURE | fifteen boards once shared one shape between them | `maps.test.ts` |
| Exactly one board in the game is bare | one is a statement; two is a board somebody forgot | `maps.test.ts` |

⚠️ **NEVER REUSE A PLACEMENT OR A SIZE. THE POOL WAS ONCE FIFTEEN PAINT JOBS ON ONE
LAYOUT AND EVERY GUARD PASSED.** Areas were distinct, floors were distinct, every piece was
individually legal, the density law was satisfied — and measured across the 5v5 pool:

| symptom | before |
|---|---|
| boards with exactly **six long bars and zero chunky pieces** | **11 of 15** |
| boards carrying 12–14 pieces | 13 of 15 |
| cover sitting in the middle third of X | **65–100% on 13 of 15** |

Colour and arrangement *names* were doing all the differentiating. Nothing asked whether two
boards were the same SHAPE, because below Platinum a league has three to six grounds and an
author holds them all in their head. At twenty, nobody does.

**Two causes, and only one of them is forced.** The deploy band bans the outer 24% of each
end and no piece may cross the centre line, so every authored piece lives in a strip from
`w × 0.24 + 1.5` to `w / 2` — about a quarter of the width. That much is structural. What is
NOT structural is authoring in the *middle* of that strip every time instead of using both
its edges, and reaching for two long horizontal runs as the mass on almost every board.

**So every board must declare a signature no other board has**, and `maps.test.ts` enforces
it globally — across leagues, not just within a pool, because Copper's Smelt and Tin's
Blowing House once matched exactly and nobody would ever have noticed, the two circuits never
being seen side by side. The five numbers are what an eye sorts on before it reads any detail:

| axis | range now in use |
|---|---|
| how MANY pieces | 3 → 22 |
| how many are long **bars** | 0 → 7 |
| how many are **chunky** blocks — gateways, arbours, snapped piers | 0 → 8 |
| how far the mass sits from centre in **X** | hard against the band → hard against the centre line |
| ...and in **Y** | one depth band → every piece at its own depth |

Concrete moves that change a signature, in rough order of how much they change the picture:
- **swap the mass from bars to blocks.** Four gateways read nothing like two colonnades. This
  is the single biggest lever and it was almost unused for fifteen boards.
- **change the piece COUNT hard.** Eight big pieces and twenty-two small ones are different
  places, not the same place at different densities.
- **push the mass to one edge of the legal strip.** Hard against the deployment band gives the
  largest empty middle in the pool; hard against the centre line gives a spine.
- **break the depth bands.** Most boards put a run near the top edge and its mirror near the
  bottom. A board where no two pieces share a depth hides the mirror entirely.
- **use the mirror instead of fighting it.** A stepped diagonal continues under 180° rotation,
  so four short walls become an eight-piece stagger that is perfectly fair and looks nothing
  like a mirrored layout.

⚠️ **AND THE DENSITY LAW HAD TO BE FIXED BEFORE ANY OF THAT WAS LEGAL.** `AREA_PER_PIECE` was
measured off Tin and Bronze boards where everything is a 10-to-14 unit wall, so the number
encodes *one WALL per 300 square units* while the code read *one OBJECT per 300*. A 1.6-unit
standard is a fifteenth of a wall's footprint and cost the same allowance — which made a
thicket of standards illegal and a row of walls fine on the same ground, and is the same rule
that let Silver ship at 0.79% cover. `pieceCost` now weights each obstacle against a
12-square-unit reference, floored at 0.3 (fifty urns is still clutter) and capped at 1.0 (a
long run is one decision, not two).

⚠️ **EXACTLY ONE BOARD IN THE GAME IS BARE** — `grand-thelevel`, and the count is pinned. Every
rule on this page is about what cover is FOR; a pool of twenty should contain one ground that
asks what happens when none of it exists. Five a side on open sand is the purest test of a
roster the game can set. A *second* bare board is indistinguishable from one somebody forgot
to finish, which is exactly how it would arrive.

⚠️ **A BOARD'S ASPECT RATIO DECIDES HOW MUCH OF ITS STADIUM IS EVER SEEN,** which is not
obvious and cost four separate ornaments before it was measured. `scene3d.ts` fits the
camera to the **board**, so the frame's spare room goes wherever the board is not: a wide
shallow ground leaves headroom above the far stand, a square one leaves none. Projecting
the exact fitted camera gives the highest world-y still inside the frame at the treeline's
depth:

| board | aspect | bank top | frame ceiling behind the far bank |
|---|---|---|---|
| `bronze-longcast` | 2.51 | 6.2 | **12.5** — four units of tree visible |
| `iron-anvilyard` | 1.81 | 6.8 | 7.7 — a fringe |
| `copper-washfloor` | 1.51 | 5.0 | 6.4 — a fringe |
| `iron-quenchpool` | 1.19 | 6.8 | 3.7 — **below the bank**: nothing behind it can be seen |
| `copper-ingotyard` | 1.13 | 5.0 | 3.2 — same |

Two knock-ons for anyone authoring the remaining boards:
- **Prefer wide.** A 2.4-aspect ground shows its treeline, its far colonnade and its arch;
  a 1.1-aspect ground of the same area shows a floor and two rows of seats. Square boards
  are not banned — Bronze's Bell Pit is 0.97 and reads fine — but they spend their venue.
- **The sides always have room.** The frame is 16:9 and the board's width binds it, so the
  left and right edges have 12–22 units of headroom against the same 5–7 unit banks. Any
  ornament that must be seen on *every* board belongs beside the ground, not behind it.

⚠️ **The replay lens pulls back and the deploy lens does not** (`LENS.fit`, 0.86 vs 0.998).
The screen the player OPERATES keeps the board at full size; the screen they WATCH is
framed wide enough to show the ground it is being fought in. Judge grandeur on the replay
framing and cover legibility on the deploy one.

⚠️ **The art decides which arrangements are possible.** Nearly every prop draws far wider
than tall, so its footprint runs along X — *the same axis as the approach*. Long props are
lane **dividers**, never walls across the run; a barrier across the approach must be built
from squat props stood in a line. Author a chicane out of log stacks and you get a spine.

---

## 5. Symmetry

⚠️ **The boards are 180°-symmetric because fairness requires it**, and that is not
negotiable — an arena that favours a side biases every measurement taken on it. It also
means every piece has a twin at matching distance on the opposite diagonal, which is why
"too symmetrical" kept recurring through three leagues of review.

**It is broken in the renderer instead**, where it costs nothing: the engine knows
rectangles, so inside one the mesh is turned and resized by a hash of its world position.
Both twins collide identically; the objects standing in them are visibly not the same
object, and the triplanar projection means they do not even share a grain pattern.

⚠️ **Prefer odd arrangements to even ones.** A centred piece sits *on* the mirror axis and
is the most symmetric shape a board can make — row / stone / row flattened the very
diagonal the Smelt's echelon existed for. Both Wood's Timberyard and Copper's Smelt improved
by removing the piece on the axis.

---

## 6. The prop library, and what is deliberately unused

⚠️ **Fourteen prop kinds have art and no board using them**, and that is a resource, not a
bug — but it has to be said out loud, because "authored, priced and unreachable" is a
failure this project has shipped three times in other systems.

⚠️ **`gate` and `dais` are no longer among them, and freeing them was what saved Iron.**
Iron's first draft used wall runs, ruins and piers in the same quantities as Bronze and
read as Bronze at other sizes — different dimensions were not enough, because an eye sorts
on **silhouette family**, not measurements. Two circuits at one team size have to be split
by what they are BUILT OUT OF:

| | family |
|---|---|
| **Bronze** | horizontal masonry — wall runs, collapsed runs, ruined coursing; low and long |
| **Iron** | things you pass THROUGH and stand ON — gateways and stepped daises; upright and blocky |

Both are dressed stone off `venue.masonry`, so the ladder still climbs. Reserved still:
`obelisk` (ceremonial, for the summit).
Trade kits with no current home: `anvil` · `orebin` · `blowingfurnace` · `ingots` ·
`crucible` · `slagheap` · `orepile` · `logstack` · `crates` · `barrel` · `cart` ·
`sawhorse` · `stump` · `palisade`.

⚠️ **`anvil` and `orebin` were built and orphaned in the same day**, which is worth
recording as a caution rather than hidden. They were drawn to replace the `heap` blob, used
on Tin, and then removed one pass later when the boards moved to architecture. The work was
not wasted — `orebin` is the answer whenever a board *should* have a working yard in it —
but the sequencing was wrong: the theory should have been settled before new trade props
were commissioned.

⚠️ **`slagheap` and `orepile` are now unused everywhere and should stay that way** unless
the `heap` shape is redrawn. Both build from one flattened sphere with rubble stuck on it
and read as a blob at every size, on every league.

---

## 7. The game is a 5v5 game

⚠️ **Standing design decision (2026-08-02). Balance is tuned for 5v5; everything below it
is the approach to it.** Wood through Gold exist to teach and to pace, not to be balanced
against — a 1v1 duel and a 5v5 team fight are different games, and only one of them is the
one being shipped.

⚠️ **Platinum upward is one board size, and that is deliberate rather than a gap.**
Platinum, Masters, Tamer Elite and Tamers Apex all field five, so their arenas are a large
interchangeable pool of 5v5 grounds differentiated by **colour and material** — the same
geometry re-dressed. `town.ts` flags the plateau as "a real loss of a progression axis";
the answer is that **progression above Platinum is carried elsewhere** (stat cap, roster
quality, meta systems), not by growing the team.

⚠️ **This means an interchangeable pool needs the density law and the arrangement
vocabulary MORE, not less.** Twenty-four boards at 82.5 × 59.5 that differ only in palette
will read as one arena in twenty-four colours unless each is a distinct built place with a
distinct arrangement. Colour is the cheapest axis and the least memorable.

⚠️ **And it points at the balance harness.** `tools/comps.ts` currently fights 2 × 2v2,
3 × 3v3, 2 × 4v4 and 5 × 5v5 — so **seven of twelve compositions are not the game being
balanced**. That spread was itself a fix (everything used to be 3v3 and was blind to the
long tail); re-weighting it toward 5v5 is the next correction, and it moves every baseline
figure quoted in `CLAUDE.md` and `docs/BALANCING.md`. Do it as its own measured change,
never folded into another.

---

## Status

⚠️ **Two leagues at one team size must be pulled apart deliberately.** Iron and Bronze both
field three, so `arenaGridFor` hands both the same 22×17 target — and reaching for the
obvious grids gave Iron's Anvil Yard and Furnace Row areas *byte-identical* to Bronze's
Alloy Floor and Slag Yard. Nothing about that is visible in a render; the size tripwire in
`maps.test.ts` counted 18 distinct areas across 20 maps and said so. Every board in the
game now has its own area, and the same trap waits at Silver/Gold (both 4v4) and across all
four 5v5 leagues.

## Status

Authored to this theory: **Wood 2, Copper 3, Tin 3, Bronze 4, Iron 4 — every board that
exists.**
Every one is 0 trade kinds, inside the density law, with a treeline, and its league shows
no floor twice.
Left: Iron 4, Silver 5, Gold 6, Platinum 6, Masters 6, Tamer Elite 6, Tamers Apex 6.
