# Free 3D asset sources — what we can take, what we still have to make

**2026-08-05.** Research pass on free/CC0 3D assets for the low-poly battlefield. Written against
`ART_BIBLE_LOWPOLY.md` (faceted, flat-shaded, 100–400 tris per cover prop, judged at 40px),
`ART_BIBLE_GUILD_COLOURS.md` (three colour systems that must not collide) and the live renderer in
`monster-tamer/scripts/ui/arena_3d.gd`.

⚠️ **Every licence below was checked on the source's own licence page, not on a listing summary.**
Where a site mixes licences per item, that is stated explicitly and the site is demoted.

---

## 0. What the renderer actually needs — the seam already exists

`arena_layout.gd:71` says it outright: *"`kind` is a semantic tag only — the renderer picks the
mesh."* There are exactly **five kinds**, and they are the shopping list:

| kind | grade | authored footprint | current render |
|---|---|---|---|
| `barrel` | soft | 2.4 × 2.4 | `CylinderMesh`, tinted JPEG |
| `crate` | soft | 3.0 × 3.0 | `BoxMesh`, tinted JPEG |
| `planter` | soft | 3.6 × 2.2 | `BoxMesh`, tinted JPEG |
| `low_wall` | hard | 9.0 × 2.0 | `BoxMesh`, tinted JPEG |
| `pillar` | blocking | 2.8 × 2.8 | `BoxMesh`, tinted JPEG |

⚠️ **THE CONSTRAINT NOBODY SHOULD BREAK WHEN SWAPPING MESHES IN: `_build_obstacles()` batches by
kind into ONE `MultiMeshInstance3D` per kind.** That is deliberate — obstacle count scales with
ground area, so per-piece nodes would grow draw calls with team size. A `MultiMesh` takes **one
`Mesh` with one material**. So an imported prop is only a drop-in replacement if it is a
**single-surface mesh sharing one texture atlas**. Multi-material .glb props would force a
per-piece node and silently undo the batching.

✅ **This is exactly what Kenney, KayKit and Quaternius ship** — one palette atlas per kit, one
material per model. The style choice and the performance choice happen to be the same choice.

⚠️ **Second constraint: height carries the cover GRADE** (soft 1.0, hard 2.0, blocking 3.2) and is
applied as a non-uniform `Basis().scaled()`. A prop whose mesh is not authored at unit scale, or
whose proportions read wrong when squashed to 1.0 tall, will lie to the player about how much
cover it gives. **Author or re-scale props so grade height is honest**, don't just stretch them.

---

## 1. The sources, assessed

| source | licence (exact) | style fit | covers | poly range | format | URL |
|---|---|---|---|---|---|---|
| **Kenney** | **CC0 1.0 Universal**, site-wide, no exceptions. No attribution, no permission, commercial yes. Confirmed on `kenney.nl/support`. | ★★★★★ Faceted, flat, chunky, palette-atlas. This IS the target style. | **1 props ★★★★★ · 2 architecture ★★★ · 3 ornament ★★★ · 4 crowd ★★★★** | ~50–800 tris typical per prop (verify at import) | **OBJ + FBX + glTF/GLB**, plus Blend | https://kenney.nl/assets/category:3D |
| **Quaternius** | **CC0 1.0**, stated on the FAQ: *"All models are under the CC0 License."* Free/personal/commercial. | ★★★★☆ Low-poly, single gradient atlas. Slightly softer/rounder than Kenney; some packs read smooth-shaded. | **1 props ★★★★★ · 2 architecture ★★★★ · 3 ornament ★★★★ · 4 crowd ★★★** | low-poly, per-pack; 4 texture sets across 200+ models in Fantasy Props | **FBX, OBJ, glTF, .blend** | https://quaternius.com/ |
| **KayKit (Kay Lousberg)** | **CC0 1.0** on the free packs (stated per-pack, e.g. City Builder Bits). Author asks you not resell unmodified copies — a request, not a licence term. ⚠️ Paid packs (Complete KayKit $150, Mystery Monthly, Bits Bundles) are **not** CC0 — check per pack. | ★★★★★ Closest sibling to Kenney; explicitly shares the same colour-atlas convention. | **1 props ★★★★ · 2 architecture ★★★ · 3 ornament ★★★ · 4 crowd ★★★★** | low-poly, 1024² gradient atlas downsamplable to 128² | **OBJ, FBX, glTF** | https://kaylousberg.itch.io/ |
| **Poly Pizza** | ⚠️ **MIXED — CC0 1.0 *or* CC-BY 3.0, per model.** 10,600+ models. Much of it is the old Google Poly archive. Attribution required on the CC-BY half. | ★★★☆☆ Wildly variable — it is an aggregator, not a studio. Some is a perfect match, some is not. | fills **specific gaps** rather than whole categories | varies per model | GLB / OBJ per model | https://poly.pizza/ |
| **Poly Haven** | **CC0**, site-wide, explicitly *"any purpose, including commercial… no credit required."* | n/a for models — it is **HDRIs and PBR materials**, and PBR realism is the *wrong* style for props. | **0 of the four** — but the **HDRI sky/environment lighting** is genuinely useful for the venue. | n/a | HDR / EXR | https://polyhaven.com/license |
| **ambientCG** | **CC0**, site-wide, *"free to use without attribution — even in commercial circumstances."* | Same caveat: PBR realism. Useful only as a **subtle** ground/stone/timber base under flat shading. | **0 of the four** directly | n/a | PNG/JPG material sets, some 3D | https://ambientcg.com/ |
| **Sketchfab (CC0 filter)** | ⚠️ **MIXED per model.** The filter helps but **each model must be checked individually**. ⚠️ Also **declining**: the store moved to Epic's Fab, only CC-BY and Fab Standard migrated; CC0 stays downloadable "for now". | varies | opportunistic only | varies | varies | https://sketchfab.com/ |
| **OpenGameArt** | ⚠️ **MIXED and some of it is UNUSABLE for us.** CC0, CC-BY, **CC-BY-SA** and **GPL** all appear. CC-BY-SA infects derivatives; GPL art in a closed-source distributed game is a problem. Multi-licensed items let you pick one. | mostly 2D-era, thin on 3D | opportunistic only | varies | varies | https://opengameart.org/ |
| **itch.io asset packs** | ⚠️ **PER-PACK, set by the author.** Many are CC0 (Kenney and KayKit both mirror here); many are custom licences forbidding redistribution. | varies | it is a *distribution channel* for the sources above, not a source | varies | varies | https://itch.io/game-assets |
| **Godot Asset Library** | ⚠️ Per-item; mostly MIT/Apache **addons**, not art. | n/a | **0 of the four** | n/a | n/a | https://godotengine.org/asset-library/ |

### The specific packs worth downloading

| pack | source | what it gives us | licence |
|---|---|---|---|
| **Fantasy Town Kit 2.0** (160 assets) | Kenney | timber/stone buildings, walls, market-stall pieces, awnings, signage, barrels/crates. The single best match for guild-town flavour. | CC0 |
| **Castle Kit 2.0** (75 assets) | Kenney | dressed-stone walls, towers, gates, banner-bearing structures. Feeds **`low_wall`, `pillar`** and venue architecture. | CC0 |
| **Survival Kit 2.0** (70+ models) | Kenney | crates, barrels, planks, fences, rope, campfire/brazier-adjacent. Feeds **`crate`, `barrel`**. | CC0 |
| **Mini Arena** (20 models) | Kenney | ⚠️ **Roman-arena themed** — soldiers and weapons, not stands. Useful for *barrier* and *ground furniture* silhouettes; **not** a stadium solution. | CC0 |
| **Mini Characters** (12 characters, 32 anims each) | Kenney | **crowd.** Rigged, tiny, cheap. At 20–40px in the stands they are more than enough. | CC0 |
| **Medieval Village MegaKit** (300+ models, grid-snapping) | Quaternius | modular walls/floors/stairs/roofs/doors. The **tiered seating bank** problem is closest to solved here — stairs + modular walls stack into stands. | CC0 |
| **Fantasy Props MegaKit** (200+ models, 4 texture sets) | Quaternius | barrels, crates, chests, market stalls, braziers, breakables. Feeds **`crate`, `barrel`, `planter`** and ornament. | CC0 |
| **Modular Medieval Building Pack** | Quaternius | timber-frame architecture for the venue shell. | CC0 |
| **City Builder Bits** (32+ models) | KayKit | planters, benches, street furniture — the **`planter`** kind's best match. | CC0 |
| **Medieval Hexagon Pack / Medieval Builder (legacy)** | KayKit | tiles and buildings; secondary to the above. | CC0 |

---

## 2. Recommendation — use three, in this order

### 1. Kenney (primary)
CC0 with zero ambiguity, ships **GLB** natively so Godot 4.7 import is a drag-and-drop, one atlas
per kit so it batches into the existing `MultiMesh`, and the faceted style is the art bible almost
verbatim. **Fantasy Town Kit + Castle Kit + Survival Kit + Mini Characters** is the core order.

### 2. Quaternius (fills what Kenney lacks)
Also unambiguous CC0, also glTF. Brings **modular grid-snapping architecture** (Kenney's kits are
more prop-shaped than modular) and a 200-model prop library. This is where the **venue shell** and
any attempt at tiered stands comes from.

### 3. KayKit (targeted top-up)
Same convention, same formats. Take **City Builder Bits** for planters and street furniture; skip
the paid tiers. ⚠️ Verify per pack — the free/paid split is real and the paid ones are not CC0.

**Deliberately NOT recommended as art sources:** Poly Haven and ambientCG (right licence, wrong
style — but do take a Poly Haven **HDRI** for venue lighting); Sketchfab and OpenGameArt (mixed
licences, per-model verification cost exceeds the value at our volume, and OGA carries CC-BY-SA and
GPL items that are actively dangerous for a commercial ship).

---

## 3. ⚠️ The gaps — what free assets do NOT solve

**Be honest about this: the free packs solve category 1 almost completely and category 2 barely at
all.**

| gap | why free assets miss it | what it costs us |
|---|---|---|
| **Stadium seating banks / tiered stands** | ⚠️ **The single biggest gap.** Nobody ships a low-poly CC0 *sports stadium*. Kenney's "Mini Arena" is a Roman gladiator set, not seating. Quaternius' modular stairs+walls can be *assembled* into tiers, but that is level-building work, not an asset download. | **Build modular ourselves.** Good news: the current renderer already draws stands as **20 boxes in a MultiMesh** (`arena_3d.gd:384`) — a single authored tier segment, instanced, replaces that directly. This is one model, not a kit. |
| **Guild-specific ornament** | Banners, pennants and signage exist in the packs but carry *generic fantasy* heraldry. `ART_THEME.md`'s guild colours are ours. | Take the **geometry** (poles, cloth, brackets) and **retexture**. The single-atlas convention makes this one image, not one edit per model. |
| **Palette collision** | ⚠️ **Kenney and Quaternius kits ship saturated primaries** — red roofs, green awnings. `ART_BIBLE_GUILD_COLOURS.md` reserves the brightest thing in frame for the **status-threat channel**, and league material owns the venue. An off-the-shelf saturated prop **fights the status channel**. | **Cheap to fix, and this is the key finding:** every model in a Kenney/KayKit/Quaternius kit UV-maps into **one shared colour atlas**. Repainting the whole kit to the house palette is **ONE texture edit**, not 160. Do this once per kit, at import, before anything is authored against it. |
| **Braziers, rope, awning cloth** | Present but scattered across packs; no single pack covers ornament coherently. | Assemble from Fantasy Props MegaKit + Survival Kit; accept a mixed provenance (all CC0, so no attribution bookkeeping). |
| **Crowd at density** | Mini Characters gives 12 rigged bodies. A full stand needs hundreds. | ⚠️ Do **not** instance 12 rigged skeletons ×500. At 20–40px a crowd should be **billboards or a MultiMesh of static low-poly bodies with a shader wobble**. `crowd-fill-by-fame` (memory) already says fill scales with fame, not arena size — so the count is a design input, not a rendering one. |

### When to generate instead of download

⚠️ **A prop is a much simpler Meshy prompt than a creature**, and `LOWPOLY_MODEL_SPEC.md`'s recipe
transfers directly (`model_type: "standard"`, explicit `target_polycount`, 600-char limit, assert
the length). A barrel has no A-pose, no rig, no silhouette-distinguishability requirement across 65
species — the two failure modes that made the creature spike expensive **do not apply**.

**But generation is the wrong first move for props anyway**, for a reason that has nothing to do
with cost: ⚠️ **generated props are a fresh roll of the dice per asset, and a downloaded kit is
internally consistent by construction.** That is the exact argument `ART_BIBLE_LOWPOLY.md` §1 makes
for authored models over generated 2D. Five cover props from one Kenney kit will look like
siblings; five Meshy props will not.

**So: download the kit, generate only the gaps.** The generation list is short —
**tiered seating segment, guild banner, brazier** — and each is one prompt.

---

## 4. Immediate action list

1. Download **Kenney Fantasy Town Kit 2.0, Castle Kit 2.0, Survival Kit 2.0, Mini Characters**
   (all CC0, all GLB). Extract to `monster-tamer/assets/models/props/`.
2. Download **Quaternius Fantasy Props MegaKit + Medieval Village MegaKit** (CC0, glTF).
3. **Repaint each kit's atlas once** to the guild palette before anything references it —
   desaturate the primaries so nothing competes with the status-threat channel.
4. Pick **one mesh per `kind`** (barrel, crate, planter, low_wall, pillar) that is single-surface
   and unit-scaled, and swap it into `_build_obstacles()` **keeping the per-kind `MultiMesh`**.
5. Author **one tiered-stand segment** ourselves and instance it in place of the 20 stand boxes.
6. Record the provenance of anything non-Kenney in this file. ⚠️ Everything recommended here is
   CC0 so **no attribution file is legally required** — but record it anyway, because the moment
   one CC-BY model sneaks in from Poly Pizza, the absence of a record is how it ships unattributed.

---

## 5. Licence summary for the ship

| verdict | sources |
|---|---|
| ✅ **Use freely, commercial, no attribution** | Kenney, Quaternius, KayKit (free packs), Poly Haven, ambientCG |
| ⚠️ **Usable, but per-item check + attribution bookkeeping** | Poly Pizza (CC-BY half), Sketchfab CC0 filter |
| ⛔ **Do not use without a deliberate decision** | OpenGameArt CC-BY-SA items (viral), OpenGameArt GPL items (closed-source distribution problem), KayKit paid packs, any itch.io pack with a custom licence |
