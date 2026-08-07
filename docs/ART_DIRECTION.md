# Art direction — the battlefield

**Read this before touching an arena, a theme, a prop or the 3D scene.** It is the
standing visual direction; `docs/ART_PIPELINE.md` is how images get *made*, this is what
they must look like and why.

⚠️ **`docs/ARENA_DESIGN.md` is the companion and it comes FIRST for layouts.** This file
says what the battlefield must *look* like; that one says what an arena must *be* — the
density law, the one-built-place rule, what cover is for. Its rules are enforced by
`mapProblems`, not by memory.

---

## The style, in one line

> **A craftsman's yard after the day's work, lit by one warm working lamp.**

The leagues are named after materials, so these are *working yards*, not fantasy arenas.
Deep shadow, a single warm key, cool sky bounce, everything past the wall falling into
dark. Per-league identity falls out of the lamp's colour for free.

Lives in `src/tamerengine/three/look.ts` — every light and grade value reads from that
table. ⚠️ **Never hard-code a light in the renderer**: all ten arenas would get the same
lamp and the ladder loses a dimension.

---

## Three independent axes

An arena is decided by three things that must stay separate:

| axis | driven by | lives in |
|---|---|---|
| **material** | the league's **name** — Wood is timber, Tin is pale metal | `themes.ts` |
| **surface** | the **cup** — sand, concrete, timber, flagstone, packed earth | `themes.ts:SURFACES` |
| **size** | the league's **team size** | `maps.ts:arenaGridFor` |
| **grandeur** | the league's **rung** — scaffolding → colonnade | `three/venue.ts` |

⚠️ **They were collapsed once and every league got the same bowl in a different colour.**
Grandeur is not material: Wood's stands are wooden because the league is *called* Wood,
but sparse and unroofed because it is the bottom *rung*. Fold them together and you can
never say "a grand timber ground" or "a mean little iron one".

⚠️ **The ladder is an alloy story.** Wood → Copper → Tin → **Bronze**, and bronze *is*
copper and tin — so Bronze's yards are stocked from both parents' props and needed only a
new ground. Free flavour the naming already paid for.

### Size

`arenaGridFor(teamSize)` — grows on **both** axes, and every board stays **wider than
deep**.

| | grid | world | cells/body |
|---|---|---|---|
| 1v1 | 12×8 | 29.1 × 17.5 | 48 |
| 2v2 | 14×10 | 33.9 × 21.7 | 35 |
| 3v3 | 16×12 | 38.8 × 25.9 | 32 |
| 4v4 | 20×16 | 48.5 × 34.3 | 40 |
| 5v5 | 24×20 | 58.2 × 42.7 | 48 |

⚠️ **An earlier version grew only in DEPTH and it was wrong about the camera.** Depth is
the axis running *into* the screen: a line spread across 30 rows has its far monster tiny,
its near one huge, and the middle occluding itself — the formation the depth was bought
for becomes the one you cannot read. Depth also **saturates**: five monsters need ~12
units of rank and the Wood board already has 17.5. Width costs approach time (the Smelt at
43.65 wide clocks 4.2s to contact) and is worth paying once depth has saturated.

⚠️ 1v1 is deliberately the roomiest per body — a duel is the one fight about kiting.
Guarded in `mapProblems` at 0.78×–1.55× of target: **the lower bound is tight, the upper
loose.** Roomy costs approach time; cramped costs the whole tactical layer.

### Surface

A theme's `ground` says **which circuit**; a `SurfaceId` says what **this cup's** floor is
laid with. Five shared textures — sand, concrete, timber, flagstone, packed earth — that
any arena may claim, exactly like the shared dressed-stone furniture.

⚠️ **Layout variety is invisible in a still frame.** Six cups on Gold differ in cover and
that is the variety that matters *in play* — but two boards with the same floor, the same
props and the same stands read as the same place in a screenshot. One line of authoring
buys two venues.

⚠️ **Not every arena takes one.** The league's own ground is what a player names a circuit
from, so leave enough boards on it — the Alloy Floor keeps the alloy floor. Surfaces are
the exception that makes the rule readable.

⚠️ **They must be quieter than a league ground**, because one texture has to sit under ten
palettes. Same check, same reason as below.

⚠️ **Both renderers go through `groundFor`.** The 3D scene *parses* `groundScale` to size
its tile — it was hardcoded at `H * 0.32` with a comment claiming it matched 2D, true only
while every floor happened to be authored near 32%.

### Grandeur

`venueFor(tier)`, 0 (Wood) → 10 (Tamers Apex). **Ornament arrives in steps, not on a
ramp** — a player climbing the ladder should be able to *name* what the new ground has.

⚠️ **The ladder is CUMULATIVE** — every rung keeps what the one below it had and adds its
own. Restated to the brief 2026-08-02.

| tier | league | gains |
|---|---|---|
| 0 | Wood | **nothing at all.** A field with a rail round it |
| 1 | Copper | **a treeline** behind the stands |
| 2 | Tin | — *holds*; Copper and Tin are one step together |
| 3 | Bronze | **seat backs** — without them a stand is a staircase people stand on |
| 4 | Iron | balustrade (turned balusters, plinth, capping rail) + brazier ring |
| 5 | Silver | **columns**, in the league's own colour |
| 6 | Gold | **planters** — small trees and flowers inside the barrier — + floor medallion |
| 7 | Platinum | **arches instead of columns**, canopy, base course, pennants |
| 8 | Masters | entablature, statues, emissive inlay |
| 9 | Tamer Elite | corner turrets, quadrant mosaic |
| 10 | Tamers Apex | ceremonial victory arch |

⚠️ **Columns moved 6 → 5 and arches 9 → 7.** They used to sit three rungs apart, which left
Silver — the first league a player would call *grand* — with nothing of its own.

⚠️ **`fluted` is off the ladder but not deleted.** It is a refinement of the plain order,
and with arches at 7 there is no rung between plain and arcade for it to occupy. It stays
in the union so a later pass can flute the ARCADE's own piers at the summit, which is where
it always belonged.

⚠️ **The treeline is a VENUE feature, not per-arena scenery.** Every board used to author
its own by hand — nine or ten entries each across twenty boards — and Wood got one despite
having no grandeur at all. It is a rung, so it belongs to the rung: sized off the board and
the bank depth, so all 39 unauthored arenas inherit it for nothing.

⚠️ **Planters are the ONLY greenery that may stand ringside.** The trackway is 1.6 units —
narrower than a bush — so a tub about a unit across is the largest thing that fits. That is
exactly why the treeline goes outside and this does not.

⚠️ **Ornament goes where the camera looks, which is the opposite of how a stadium is
built.** The first colonnade sat behind the top row and was invisible at every tier. The
**trackway** — the ring between floor and barrier — is the only band always in shot. The
**floor** is half the frame: a gilt border does more than four rows of unseen seating.

⚠️ **The near side takes columns but never arches, an entablature or a canopy.** Anything
spanning *above* the near trackway cuts the front rank in half.

⚠️ **Crowd FILL is not an art value — it is a gameplay one, deferred on purpose
(2026-08-02).** Today it is a flat density per tier, and because it is a density a long
board spreads the same crowd thinner: the Smelt reads as the worst-attended venue in the
game purely for being the widest. Do **not** "fix" that by scaling the count to the board.
The seats are going to be filled by MODIFIERS — team fame first, plus whatever else the
meta layer ends up carrying — so a half-empty bowl becomes information rather than a bug,
and an unknown team's first cup *should* look sparsely attended. Leave the hook alone until
that lands.

⚠️ **Rows are the expensive axis; ornament is free.** Every row pushes the camera back and
shrinks the playing surface. Crowd **fill** (0.42 → 0.97) is the cheapest grandeur there
is — one instanced mesh either way.

---

## Camera and lens

Fixed camera, ~38° elevation, 26° fov (long lens — short ones bow a 58-wide arena).
`three/scene3d.ts`.

⚠️ **The HD-2D look is a LENS treatment, not a modelling one.** Untreated, the same
geometry under the same lights reads as an asset viewer. `EffectComposer`: DoF → bloom →
split-tone grade → `OutputPass`. **`OutputPass` applies the tone mapping once a composer
exists** — without it the frame comes out linear.

⚠️ **`LENS.CINEMATIC` is far gentler than a real tilt-shift.** At a photographic aperture
it blurred the *monsters*: the arena is deep and the units stand at its two far edges, so
anything leaving a thin band in focus leaves the cast outside it. `LENS.BOARD` keeps
deploy legible — it is a tactical grid before it is a picture.

⚠️ **The orbit is not a gameplay feature.** It exists so a still scene can be shown moving.

---

## Objects

**Procedural meshes** (`three/props3d.ts`), not authored assets — every object the leagues
need is an industrial primitive, so lathes/boxes/cylinders describe them all with no
export pipeline and no binary blobs. Materials come from the theme's `PropPalette`.

⚠️ **Bevels, not polygon count.** A perfect 90° edge catches *no* highlight — light jumps
between face values with nothing between, and the object reads as a diagram of a box.

⚠️ **`flatShading` is a low-poly STYLE and fights "high definition".** Smooth by default;
facets only where facets are correct (rubble, fluted column shafts).

⚠️ **`roundedBox` is base-anchored by `r`, not `h/2`.** `ExtrudeGeometry` runs 0..depth
plus bevel at both ends.

### Arrangements — how cover is placed

⚠️ **An arena is built by someone, so its cover is placed, not spilled.** Reading "cover
density" as a number and scattering props to hit it gives a board where nothing fully
blocks a lane and the deployment that is correct here is correct everywhere. Every league
board is **one named arrangement**, stated in its brief:

| | the question it asks |
|---|---|
| **SPINE** | one long piece dead centre — two lanes, and you commit before contact |
| **FLANKS** | long pieces down both edges, middle bare — the fast route is the seen one |
| **CHICANE** | squat posts staggered through the middle — you may weave, not charge |
| **ECHELON** | two long pieces diagonally opposed — cover on your own side only |
| **DOGLEG** | two long pieces overlapping in depth — one short way through, and it is watched |
| **COURT** | a landmark dead centre with cover framing it — the middle is worth holding |

⚠️ **The art decides which arrangements are even possible.** Nearly every prop draws far
wider than tall, so its footprint runs along X — *the same axis as the approach*. Long
props are lane **dividers**, never walls across the run; a barrier across the approach has
to be built from the squat props (crates, crucible, furnace, stump, broken pillar) stood in
a line. Author a chicane out of log stacks and you get a spine you did not intend.

⚠️ **Piece count rises with the team; piece SIZE rises with the board.** Wood is a duel and
two pieces are a whole layout there; Bronze is 3v3 on 1.8× the area and carries five. Both
stay few — a 16-unit wall on a 51-unit board is a decision, five 2-unit heaps are texture.

⚠️ **Check it resolves.** `npx tsx tools/mapsweep.ts` — all 18 boards at 40/40, 21–27s,
cover 6–19%. Titan's Rest is the standing warning: small blocks each break a sight line
cheaply and stall the exchange, and only the sim says whether a layout did that.

### The rules that bound a layout

⚠️ **Nothing may stand in a deployment band.** An earlier guard allowed 15% of a band to
be blocked — cover near your own spawn is a *choice*, and `mirror()` makes it fair either
way. True about fairness, not about readability: a monster seated on a stump reads as
clipping, and a start line you cannot see the whole of is a worse trade than cover you
cannot have. Both arguments are kept in `mapProblems`.

⚠️ **All twelve league boards broke it the moment it was written**, which is a fact about
the *band*. `hex.ts:zoneFor` sizes it `0.24w + 1.5` — off **width**, with no idea how many
bodies must stand in it — so one Wood monster gets 15.5 units while three Bronze ones share
14.3, and the bands eat ~54% of every board. Sizing it off the **team** is the real fix and
it moves auto-deploy, so it is a separate measured decision.

⚠️ **Measurement fixtures are exempt.** Titan's Rest is the whole evidence for "small
blocks stall a fight"; moving its rubble for a presentation rule would silently invalidate
every number taken on it.

### Scenery

Trees and bushes, shared by every league and **never re-tinted** — colour is the one thing
about a tree that is the same at Wood and at Apex. Two sprites dress all forty boards.

⚠️ **Its own list, not `obstacles`.** Everything in `obstacles` is cover the engine paths
around; drawing scenery from it would add cover to every board that got prettier — a
balance change disguised as an art change. `mapProblems` asserts scenery is fully outside
the field.

⚠️ **The trackway is 1.6 units wide** (`stadium.ts:GAP`) — narrower than a bush. Nothing
can stand ringside. Trees go **behind** the far bank and clear it on height (8.3 against a
seven-row bank's 4.3); shrubs tried the same and rendered invisible, so they belong **on
the pitch** as low cover. Anything ornamental must clear what it stands behind.

⚠️ **Nothing on the near side** — the camera looks *over* that bank, so anything behind it
sits between the lens and the board.

⚠️ **Scenery sits past the wall, so it takes the value of what it stands behind.** The
first foliage was a daylight green and became the brightest thing in a dim warm frame.

⚠️ **A shared kit used identically everywhere is worse than not using it.** Wood's two
boards both had a matching pair of shrubs and read as one layout twice — stump, bush,
spine, bush, stump is a shape you can predict from the far end. One board keeps them.

### Authoring cover (2D footprints)

⚠️ **Footprint depth = width × the sprite's own aspect.** These props are far wider than
tall — slag heap **0.242** deep per unit width, gravel bar **0.195**, crucible 0.773. Sized
by eye, the sprite draws shorter than the ground it blocks and you see walkable floor
inside solid cover. *Every* Bronze footprint was wrong on the first pass.

⚠️ **Nothing may reach the centre line, because `build` mirrors.** A piece at `x`
reappears at `w−x−width`; anything crossing halfway overlaps its own reflection.

⚠️ **Multiple cups run per arena, so shapes must differ, not just layouts.** Give a league
a square, a deep, a long and a wide — a deployment correct on every board is not a
decision. Bronze's Long Cast is the deliberate *inverse* of Wood's Long Yard.

⚠️ **Coverage means FEWER AND LARGER, not more.** Five small pieces scattered over a 4v4
board give a field where nothing fully blocks a lane and every position is about as good
as every other — busy, and no decision in it. One ruined wall a third of the board wide is
a real obstacle: you go round it, and *which end* you pick matters. Author the big pieces
first and add small ones only to break their edges.

⚠️ **A centrepiece must sit at exactly `(w − size) / 2`, because `mirror` emits it once.**
Off by a hair and the arena grows two obelisks — the helper matches partners on position.

### The furniture, and the one that keeps going wrong

Ruins carry the irregular silhouettes. Intact furniture is rectangles and cylinders, every
piece covering the same way; a wall with its top torn off and a gap through it gives cover
that *differs along its own length*, which is what makes where you stand behind it matter.

⚠️ **Nothing may span a piece's full width across the top.** The gate was rebuilt three
times and read as a **table** every time — because from a 38° camera a horizontal slab over
two legs *is* a table, whatever the arch beneath it is doing. Thinning the slab does not
help; removing it does. The piers stand proud above the crown with their own copings and
the masonry between them stops lower, so the highest points of the silhouette are its two
ends. The same trap waits for any lintel, canopy or capping course.

⚠️ **Trim is an accent and belongs on the smallest parts.** In the venue's gilt, a
full-width architrave read as brass; a fallen column drum read as a barrel someone had
rolled in. A fracture does not change what the rock is made of.

⚠️ **Watch the aspect ratios — masonry is heavy.** An obelisk at 8:1 is a lamp post; at 3:1
it is a monolith. A ruin's courses need depth ≈ 0.8 × height or the blocks read as floor
tiles someone dropped.

---

⚠️ **A prop's aspect sets its MAXIMUM width too, not just its depth.** Drawn height is
`width / aspect`: it must reach the footprint's depth *and* stay under 3.4 (a battle
sprite's height). So a sluice may run 18 units and a crate stack may not exceed 3.6.
Author from the envelope, never by eye.

⚠️ **In 3D the footprint is the truth, and it was not.** Every procedural shape invents its
own depth from its width — the authored depth only ever reached it as an input to the
height — so a channel drew `0.47 × w` deep whatever rectangle the map reserved. At an
8-unit leat those agreed by luck; at 20 units the trough drew 9.4 deep on a 3.1-deep
footprint and covered a fifth of the board in water nothing collided with. `buildProp` now
squeezes the built group in Z to the authored depth — the same invariant the 2D renderer
has always had.

⚠️ **The stands climb the material ladder; the arena's own masonry does not.** `venue.stone`
starts at raw timber because Wood's *seating* is timber — floor furniture borrowing it drew
Bronze's ruined walls in a near-black brown that read as charred wood, with a black capping
course over a grey body. `venue.masonry` / `masonryTrim` are a separate grey ladder: stone
at every rung, better dressed as you climb, gilt still arriving at Gold.

⚠️ **Fire is the same colour in every league.** A furnace mouth taking the theme's `inner`
came out white on Tin's deliberately colourless palette and bloomed into a headlight
pointed at the camera. Dim warm emissive instead.

## Textures

⚠️ **House saturation is ~0.21.** Bronze's first ground came back at **0.57** — nearly
three times as punchy as any other floor — and blazed orange in the 3D scene, swallowing
the cover on it. It looked fine on its own; a texture only reads as wrong *beside the
others*. `proc_arena_art.py:check_ground_palette` runs that comparison.

⚠️ **It flags the LOUD side only, and as a question.** Tin is *designed* cold and nearly
colourless (0.01–0.05). Flagging the quiet ones would mean "fixing" a league's identity on
a number.

---

## Two renderers, three tables

The 2D DOM renderer ships; `?arena3d` is the 3D prototype (see
[[renderer-roadmap-3d-godot]] — Godot + desktop is the endgame, after the sim freezes).

⚠️ **A theme must be authored in THREE places or it renders as the wrong league.** Bronze
shipped with `themes.ts` only: the 2D board was right while the 3D scene fell back to
*grass lighting* and *timber prop colours*. `arenas.test.ts` now asserts every `THEMES`
key has a `LOOKS` and a `PALETTES` entry.

---

## Workflow

1. `tools/gen_<league>_arena.sh` → raw art
2. `python3 tools/proc_arena_art.py` → convert, cut alpha, **and check the ground palette**
3. Author theme (all three tables), then arenas — different shapes, different object mixes
4. `npm test` — the guards catch footprint depth, mirror overlap, size band, missing tables
5. **Render in the 3D scene** (`?arena3d` + the `/__shot` capture route), not `drawboard.py`

⚠️ `drawboard.py` is the *2D* board preview. Judging arenas from it after the direction
moved to 3D is a regression in the screenshots, not the game.

---

## Status

Done: **Wood 2** (signed off), Copper 3, Tin 3, Bronze 4 — the last three are legal under
the deployment rule but only mechanically, and get designed properly at their league's turn.
Left: Iron 4, Silver 5, Gold 6, Platinum 6, Masters 6, Tamer Elite 6, Tamers Apex 6.

⚠️ **Wood went 4 → 3 → 2 in one day, and every step was a design call.** It is the league a
player passes through fastest and it has the smallest prop vocabulary in the game, so each
extra board was another arrangement of the same four objects rather than another place.
What the cuts cost, written down so it stays a choice: Wood has **no near-square board**
(its two run 2.68 and 1.82, both wide), so its contact-time spread fell from 2.5x to 1.3x,
and it no longer uses the CHICANE arrangement, the `timber` surface or the `plankyard`
theme. All three are still authored; if Wood ever wants a third, **the square is the shape
that is missing**.

Open: PBR ground materials and ambient occlusion are the biggest remaining quality jump;
sprites are still front-on portraits not drawn for this camera; the crowd are capsules.
