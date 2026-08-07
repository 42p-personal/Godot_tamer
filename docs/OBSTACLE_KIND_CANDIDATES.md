# Wider obstacle-kind sweep — verified candidates for growing `KIND_TABLE`

**2026-08-05.** Follow-up to `FREE_3D_ASSET_SOURCES.md` §0, which scoped the shopping list to the
five kinds already in `arena_layout.gd`'s `KIND_TABLE`. That was a snapshot, not a cap — the table
comment says outright that kinds can be added without touching placement logic, and the mirror-pair
comment (arena_layout.gd:162) flags `hard` and `blocking` as one-kind grades whose symmetric pairs
therefore always look like copies. This sweep goes wider to fill those gaps.

## Method — and why these findings are *verified*, not listed

Swept the poly.pizza API (same pipeline as `tools/poly_fetch.py`, same key) with **40 search
terms** aimed at all three grades: 802 unique models → 328 CC0+static → **183** after restricting
to the three trusted single-atlas creators (Kenney, Quaternius, Kay Lousberg) and ≤1600 tris.
**All 183 were downloaded and their GLB headers parsed** for the two constraints
`FREE_3D_ASSET_SOURCES.md` §0 warns about:

- **material/primitive count** — MultiMesh batching in `arena_3d.gd::_build_obstacles()` needs
  ONE mesh with ONE material. 111 of 183 pass; **72 fail**, including many desirable ones (see
  "near-misses"). This is the discriminator, and it is not visible on a listing page.
- ⚠️ **bounding boxes came back unreliable** (many models author geometry at tiny local scale and
  size it via node transforms, which a header-only parse doesn't compose). Footprint/proportion
  claims below are from thumbnails and tri layout, and **must be re-measured at Godot import**
  before a `KIND_TABLE` footprint is written down.

Sweep script + full JSON: session scratchpad `prop_sweep.py` / `prop_findings.json` (183 rows).
Nothing was copied into the project; the cache is disposable.

## Recommendations by grade

Every row below is CC0 1.0, single-material single-primitive (drop-in batchable), from a trusted
creator. `polyId` feeds the existing fetch pipeline.

### `hard` — the flagged gap (only `low_wall` today)

| candidate kind | model | creator | tris | polyId | notes |
|---|---|---|---|---|---|
| **`boulder`** ★ top pick | Rock Medium | Quaternius | 244 | `KZdEP3uUpa` | Squat organic silhouette — finally a hard-grade shape that isn't a straight line. |
| `boulder` (pair variant) | Rock Medium | Quaternius | 522 | `JQxF95498B` | Second variant so mirrored pairs stop being clones — the exact fix arena_layout.gd:162 asks for. |
| `counter` | Counter Straight | Quaternius | 464 | `zpURbFzEbv` | Market-counter; guild-town flavour, chest-high. |
| `tomb` (league-flavour) | Grave / Crypt | Kay Lousberg | 323 / 952 | `znGrV0V80y` / `iV5x01FYAl` | ⚠️ Graveyard flavour won't fit every league palette — gate by theme if used. |

⚠️ `s1OJ3bBzqc` (Rock Medium, 342 tris) is **already landed as `barrel_alt`** in
`assets/models/obstacles/MANIFEST.json` — don't fetch it twice under a new name.

### `blocking` — the other one-kind grade (only `pillar` today)

| candidate kind | model | creator | tris | polyId | notes |
|---|---|---|---|---|---|
| **`shrine`** ★ top pick | Shrine | Kay Lousberg | 94 / 360 | `tFxdxO5clk` / `Qq8M5LSXQ2` | Two variants; thematically *made* for a monster-tamer guild game. |
| `pedestal` | Pedestal | Quaternius | 1182 | `wUeoDKnFBF` | Statue plinth — reads as monument even without a statue on top. ⚠️ 3x the art bible's 400-tri budget; judge at 40px before committing. |
| `dead_tree` | Dead Tree | Quaternius | 765 | `4E3IOActVF` | Organic blocking. ⚠️ Branches overhang the collision footprint — check it doesn't visually lie about the blocked rect. |
| `watertower` | Watertower | Kay Lousberg | 146 | `WGSUkExDJ4` | Distinctive silhouette; more "town outskirts" than arena — a maybe. |

### `soft` — already three kinds, but these add variety cheaply

| candidate kind | model | creator | tris | polyId | notes |
|---|---|---|---|---|---|
| **`bench`** ★ | Bench | Quaternius | 276 | `7uSlZo3n9Y` | Low, long; classic arena furniture. Variants: `nARUaxtRHA` (364), KayKit `UFhTqUnoUn` (172). |
| **`fence`** ★ | Fence | Quaternius | 188 | `e02PFKKhbr` | Long-thin soft cover — a *new silhouette class* (low_wall is hard; this is a soft line). Variant `U7g0Wxpt63` (324). |
| `sacks` | Bags | Quaternius | 912 | `gzvyAQ797z` | Grain-sack pile; single-sack `VRfAODZ0Xk` (304) as pair variant. |
| `hay` | Hay | Quaternius | 488 | `Yu8TOERkpw` | Hay bale. |
| `log_pile` | Wood | Quaternius | 420 | `ajBNpMsQ8z` | Stacked timber. |
| `urn` | Large pot | Kay Lousberg | 388 | `3qb2rGbNfn` | Round profile like barrel but distinct read; Quaternius `kXCojdgsiN` (644) as variant. |
| `rock_flat` | Rock Flat | Kenney | 214 | `CrSoV13mCU` | Low flat rock; pairs with `boulder` for an organic sub-theme. |

## Near-misses — usable with one preprocessing step

- **One material but multiple primitives** (a lossless merge in Blender or on import makes them
  batchable): Coffin (KayKit, 316), Arch Gate (KayKit, 868), Table (Kenney, 240).
- **Multi-material, worth a one-time palette-bake if wanted**: Market Stand (Quaternius, 1548,
  4 mats), Cauldron (1238, 4 mats), Guard/Watch Towers (416–1324, 2–3 mats), Logs (940, 2 mats),
  Broken Cart (1432, 3 mats). ⚠️ Each of these silently breaks MultiMesh batching if imported
  as-is — that's why they are in this section and not the tables above.

## What genuinely does not exist on poly.pizza (checked across ALL CC0 creators, not just trusted)

- **Statues: zero.** The obvious blocking-grade centrepiece isn't there.
- **Fountains: zero** (the two "hits" were an ink pen and a kitchen sink).
- **Wells: one** (Quaternius, 1870 tris — over budget).

If a statue/fountain kind is wanted, the route is the full **kit downloads** from kenney.nl
(Castle Kit / Fantasy Town Kit ship many more GLBs than are mirrored on poly.pizza) or a bespoke
prop — see `FREE_3D_ASSET_SOURCES.md` §2 for the kit recommendation order.

## Wiring reminders (what adding a kind actually touches)

1. One row in `KIND_TABLE` (`arena_layout.gd:75`) — kind, grade (one of the existing three —
   grades are load-bearing in combat, kinds are free), footprint **measured at import, not taken
   from this doc**.
2. A mesh/texture mapping in `arena_3d.gd` (`OBSTACLE_TEX` / `OBSTACLE_TINT` or the mesh path) —
   unknown kinds fall back to a tinted crate box, so the failure mode is cosmetic.
3. ⚠️ Keep footprints honestly rectangular: the sim's cover model is the `Rect2` — props with big
   notches or overhangs (dead tree branches, arch openings) lie to the player about what blocks.
4. ⚠️ Grade height is applied by non-uniform scale — props must read correctly squashed/stretched
   to 1.0 / 2.0 / 3.2 tall (`FREE_3D_ASSET_SOURCES.md` §0, second constraint).
