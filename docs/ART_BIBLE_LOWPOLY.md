# The low-poly art bible — the battlefield

**Decided 2026-08-04 by the user.** The battlefield becomes **low-poly 3D**. The UI keeps its
**painterly 2D**. Model work begins **after the core loop is finished** — this document exists so
the decision is settled and specified now, not so anyone starts modelling today.

> *"i think a low poly art style could look good for our game"* — the user

---

## 1. Why — and the argument is the CAMERA, not taste

The user's chosen arena framing (`ARENA_CAMERA_REFERENCE.md`) pulls the camera **out**, so a
creature on the board is a **20–40px silhouette**. Painterly illustration is the article's *High*
cost band; at 40px almost none of that detail survives. **We were paying the most expensive rate
for information the player cannot see.**

Three further reasons, in order of weight:

1. ⚠️ **It removes the pipeline's biggest risk.** Generated 2D art is a fresh roll of the dice per
   asset, and `ART_STYLE_CONFORMANCE.md` had to admit consistency "is judged by eye or not at
   all". That is a bad position with 65 species. **Authored models make consistency structural** —
   one material palette, inherited by everything.
2. ⚠️ **It unblocks data the sim already emits and the renderer cannot use.** `BUILD_CONTRACT.md`
   §4: *"a `Sprite3D` with billboard enabled cannot be rotated — billboarding re-solves every frame
   and silently undoes it."* So today we cannot turn a unit to face its movement, topple a corpse,
   or take an honest shadow. The frame stream has carried `facing` per unit per tick the whole
   time. Geometry spends it.
3. **Animation cost collapses.** 6 frames × 65 species × every action is unaffordable as sprite
   sheets. One rigged skeleton retargets across the roster.

### ⚠️ What this OVERTURNS, and why that is legitimate

`ART_DIRECTION.md` says *"`flatShading` is a low-poly STYLE and fights 'high definition'. Smooth
by default."* **That rule is superseded, not violated.** Its precondition was a mixed frame —
low-poly props sharing the screen with painterly sprites. If the battlefield is uniformly
low-poly there is no contradiction left to prevent. Same shape of reasoning as the spatial layer's
reversal: the rule was right, its precondition expired.

⚠️ **The lighting direction SURVIVES INTACT.** *"A craftsman's yard after the day's work, lit by
one warm working lamp"* is a lighting and mood statement, not a modelling one — one warm key, cool
sky bounce, deep shadow, per-league lamp colour. **Low-poly renders that better than billboards
do**, because real geometry actually receives the key light.

---

## 2. The split — each style where it wins

| surface | style | why |
|---|---|---|
| **Battlefield creatures** | low-poly 3D | seen at 20–40px, in motion, needing facing and shadow |
| **Battlefield arena** | low-poly 3D | same frame; must match the creatures |
| **Stable / market / report portraits** | **keep painterly 2D** | seen at 320px with full attention — this is where the existing art *wins* |
| **Arena backdrop / sky / distant venue** | **keep painterly 2D** | a painted backdrop behind low-poly geometry is a legitimate, cheap depth trick |
| **Title, area art, UI** | keep painterly 2D | unchanged |

⚠️ **NOTHING ON DISK IS WASTED BY THIS DECISION.** The 12 creature portraits, 5 venue backdrops
and title screen all keep their jobs. Only the **battlefield representation** changes. The 30
battle sprites (Mammal group, 6 frames each) are the one casualty — they were the 2D
battlefield's asset class, and they are superseded.

---

## 3. The style, specified

### Silhouette is the whole game
⚠️ **Judge every model at 40px tall, in flat black, before judging it at any other size.** If two
species are not tellable apart as black shapes, the model has failed regardless of how it looks in
the viewport. This is the same test `ART_STYLE_CONFORMANCE.md` §5 sets for sprites and it matters
more here, not less.

Distinguish by **proportion and profile** — head-to-body ratio, limb length, stance, spine curve,
one strong feature (horn, crest, tail, hunch). **Not** by surface detail, which is invisible at
size.

### Poly budget
| asset | target | ceiling |
|---|---|---|
| creature | 700–1,500 tris | 2,500 |
| cover prop | 100–400 tris | 800 |
| arena shell (walls, stands) | 3,000–8,000 tris | — |

⚠️ **These are PROPOSED, not measured.** `technical-preferences.md` records that nothing in this
project has been profiled and that inventing budgets is exactly the failure its balancing rule
exists to stop. Set them properly with `performance-analyst` once a battle scene renders. **Ten
creatures on screen is the load case**, not one.

### Surfaces
- **Flat / faceted shading is the point** — no normal maps, no PBR metalness workflow.
- **Untextured or single flat colour per material.** Colour comes from the palette, not from maps.
- ⚠️ **A vertex-colour or small gradient palette texture is the ONLY texturing permitted.** The
  moment a creature carries a painted texture map, we are back to per-asset consistency-by-eye,
  which is the problem this whole change solves.
- **Hard edges kept hard.** Faceting is the style; smoothing groups that hide it defeat it.

### Palette — ⚠️ THE THREE-SYSTEM RULE IS UNCHANGED AND STILL LOAD-BEARING
`ART_THEME.md`'s discipline carries over exactly:

| system | rule |
|---|---|
| **League material** | in the arena's stone, sand and timber — **never on a creature** |
| **Team colour** | **sash and nameplate only** — desaturated livery tones (`art.gd:TEAM_COLOURS`) |
| **Status / threat** | **the brightest thing in frame**, always |

⚠️ **Saturated = something is HAPPENING. Muted = this is WHO YOU ARE.** Creature bodies stay in
natural desaturated material colours. A creature modelled in saturated red reads as *on fire*
mid-fight. This has already been caught once, when the first team palette was pixel-for-pixel the
proposed status hues.

⚠️ **Colour is never sufficient identification.** `index % 8` makes team-colour collisions exact,
not merely likely, and a colourblind player loses the channel entirely. The **badge**
(`art.gd:team_badge`) ships alongside the colour, always.

### It is a sport, not a war
Unchanged from `ART_THEME.md` and it constrains modelling as much as it did painting: **straps,
wraps, guards, a team sash. No weapons of war, no armour plate, no gore, no skulls.** An athlete
dressed for the ring.

---

## 4. Pipeline — the genuinely open question

⚠️ **We do not currently have one.** `ART_PIPELINE.md` describes two routes that both produce
**2D images**. Low-poly needs 3D models, and that is a different tool (Meshy or similar) that has
never been run here.

⚠️ **This is the real risk in the decision, and it should be tested EARLY and SMALL** — one
creature, end to end, from generation through import to standing in the Godot arena at the real
camera distance. Do not commission a roster before that round-trip has been proven once.

Open questions to answer during that pilot:
- Can the generator produce a **rigged** model, or does rigging have to be authored?
- Does it honour a poly budget, or does it need decimation as a post-step?
- Is it consistent enough across runs that ten creatures look like one roster?
- Can one skeleton retarget across wildly different bodies (Avian, Aquatic, Insectoid, Draconic)?

⚠️ **If the answer to the last two is no, the consistency argument in §1 collapses** and the
honest response is to say so and reconsider — not to push on because the decision is written down.

---

## 5. When

**After the core loop.** The standing project decision (memory: *renderer roadmap*) is that 3D art
is a **renderer swap at the end**, so art never blocks systems work. The loop — shop, food in
planning, tutorial, tournaments — comes first.

⚠️ **The sim is NOT involved in any of this.** The frame stream already carries position, facing,
hp, statuses, intent and attribution per unit per tick. This is `arena_3d.gd` and asset work only
(stream C in `BUILD_CONTRACT.md` §3). **Do not edit `spatial_sim.gd` for an art change.**
