# Art production plan — Guild Colours

**Executes `docs/ART_THEME.md`.** That document is the brief (name, three-colour-system
discipline, creature/venue/UI direction, readability rules). This document turns it into
an inventory, specs, prompts, and an order of work. Where a number here disagrees with
`ART_THEME.md` or `ART_PIPELINE.md`, **this document is the corrected one** — see §0.

Everything here obeys `.claude/docs/coordination-rules.md`: this is direction and
specification, not code, shaders, or pixels. Generation is executed by whoever runs the
`image-gen-codex` skill; engine-side work (tinting, masks, VFX, mesh) is delegated to
`technical-artist` at each point marked ⚠️ **DELEGATE**.

---

## 0. Corrections to the source documents (found by reading the filesystem, not the docs)

Both source documents' battle-sprite counts are stale, and the correction changes the
plan, not just the number:

| document | claimed | actual (`public/battle/*.png`, counted 2026-08-03) |
|---|---|---|
| `ART_PIPELINE.md` summary table | 0 of 260 (4 frames) | wrong spec AND wrong count |
| `ART_THEME.md` §5 | 0 of 390 (6 frames) | **wrong count** — the spec (390/6) is right |
| **Actual** | — | **30 of 390 generated**: all 5 Mammal species (Kongrath, Aegisox, Maneleo, Grivvel, Ursath), full 6-frame set each |

⚠️ **This is more than a housekeeping fix.** The Mammal group ART_THEME.md recommends
starting with is *already done* — but it was generated before the team-colour-carrier
convention existed as a requirement, so none of those 30 images can carry a team colour
yet (see §4). "30 done" and "0 Guild-Colours-complete" are both true simultaneously, and
the plan below is sequenced around the second number, not the first. **Recommend fixing
`ART_PIPELINE.md`'s stale 260/4 row the next time anyone touches that file** — not done
here, out of this document's scope.

Portraits are confirmed **65 of 65 generated** (`public/sprites/*.png`, all present) —
`ART_PIPELINE.md`'s count for that row is correct.

---

## 1. Asset inventory and order

Real counts, sequenced by dependency. "Blocked" means genuinely blocked on a decision or
artefact outside this document, not merely un-started.

| # | asset class | count | status | blocked on |
|---|---|---|---|---|
| 1 | Species portraits | 65 | 65/65 generated, **0/65 audited** against §1/§4 of `ART_THEME.md` | nothing — start now |
| 2 | Fusion silhouette audit | 20 (subset of the 65) | 0/20 audited | nothing — start now |
| 3 | Team-colour carrier retrofit on portraits | 65 | 0/65 | audit (1) must run first to know which portraits get a redirect vs a patch-only carrier pass |
| 4 | Battle sprites | 390 (65 × 6) | 30/390 generated, **0/390 carrier-complete** | carrier-pilot tranche (§3) before scaling past Mammal |
| 5 | Status/mod icon set | 18 (15 statuses + 3 mods) | 0/18 | battle-sprite outline language (needs the "hand" established by (4)) |
| 6 | Channel cast-tell glyphs | 5 (melee/ranged/magic/voice/support) | 0/5 | same as (5) |
| 7 | Nameplate frame + striped-edge tell | 2 base variants (tintable) | 0/2, technique undecided | ⚠️ DELEGATE to technical-artist for the tint/mask implementation; spec is §2 |
| 8 | Fan/merch icon set | ~5 templates (scarf, banner, pennant, badge, +1 spare) | 0/5 | icon language from (5)/(6) |
| 9 | UI chrome (league-material panel skins) | up to 10 (one per league material) | 0/10 | icon language from (5)/(6); sequenced last per `ART_THEME.md` §5 step 7 |
| 10 | Exterior-silhouette checklist (24 5v5-pool boards) | 1 checklist, 24 entries | 0/24 | **dimension-agnostic — can draft now**, reconcile against `ARENA_BLUEPRINT.md` when it lands |
| 11 | Arena/venue 3D assets (materials, props, board layout) | unknown until blueprint | not started | ⚠️ **BLOCKED — `docs/ARENA_BLUEPRINT.md` does not exist yet** (confirmed absent). Another team owns it. This document does not spec dimensions. |
| 12 | Crowd/fan geometry (filled/empty seat per grandeur tier) | 11 grandeur rungs × 2 states = 22 looks | 0/22 | (11) — needs venue geometry to dress |
| 13 | Photoreal JPEG backgrounds | 18 (10 league + 8 area) | 18/18 exist, retirement not started | retires per-league, tied to (11)'s build cadence — not a single cutover |

**Order of execution** (dependency-first, not the order in the table above):

1. Portrait audit (war-armour register + carrier-isolability) + fusion silhouette audit — cheap, unblocks everything downstream, no generation required yet.
2. Carrier-pilot tranche on battle sprites — 6 species, one per unproven carrier category (§3).
3. Portrait carrier retrofit — scoped by what (1) found.
4. Battle sprites at scale — remaining 60 species minus the 6 pilots, grouped by carrier category.
5. Status/glyph/nameplate/merch icon sets.
6. UI chrome.
7. Exterior-silhouette checklist (can run in parallel with 2–6; genuinely independent).
8. Arena/venue assets — waits on `ARENA_BLUEPRINT.md`.
9. Crowd geometry, then JPEG retirement — both wait on (8).

---

## 2. Per-asset-class specifications

### Species portrait (existing, unchanged spec)
- **Dimensions**: 320×320 RGBA PNG, transparent background.
- **Framing**: 3/4 hero pose, one frame, adult-only.
- **Style**: painterly-readable realism — real material shading, not photoreal, not cel-flat.
- **Naming**: `public/sprites/<species-id>.png` (existing convention; does **not** follow the studio's `[category]_[name]_[variant]_[size]` pattern — flagged, not changed, per `ART_THEME.md` §5's open naming question).
- **New requirement (this document)**: must carry an **isolable carrier object** in a reserved key colour — see §4. This is additive to the existing spec, not a respec.

### Battle sprite (existing spec, `BATTLE_SPRITES.md` — authoritative, unchanged)
- **Dimensions**: 128×128 RGBA PNG. **Display size ≈40px** in a live 5v5 — this is the size every readability judgement in §5 is made at, not the 128px source.
- **Frames**: 6 — `idle`, `walk1–4`, `strike`. Strict side profile, facing right. Foot-anchored, one shared scale per species (never bbox-centred — see `ART_PIPELINE.md`).
- **Style**: pixel art, matched to the species' own portrait via `--ref`, not a fresh description. Bold silhouette, flat colour, dark outline, no shadow/scenery/border.
- **Naming**: `public/battle/<species-id>-<frame>.png` (existing, unchanged).
- **New requirement (this document)**: carrier object in the same reserved key colour as the portrait's — see §4.

### Status / mod icon (new)
- **Dimensions**: 32×32 RGBA PNG, authored at source resolution (not downscaled from a larger render — pixel work, same discipline as battle sprites).
- **Style**: bold, dark-outlined, flat — the battle-sprite "hand," not a photoreal or emoji register. Replaces `EFFECT_ICON`'s emoji set in `src/tamerengine/fieldFx.ts`.
- **Colour grouping** (fixed, from `ART_THEME.md` §3 — restated here as the spec, not re-derived):
  | group | members (18 total) | anchor hue family |
  |---|---|---|
  | hard control | stun, sleep, fear, confusion | pale yellow/white |
  | damage-over-time | poison (green), burn (orange), bleed (red), doom (near-black/purple) | warm-to-cool by kind, distinct icon shape per kind |
  | utility debuff | blind, silence, vulnerable, healblock, knockback, charm | desaturated violet/grey |
  | buff | haste, atkUp, defUp | cool blue/cyan |
- **Naming**: `ui_status_<name>_32.png` (new class — canonical convention applies, no legacy pattern to preserve).

### Channel cast-tell glyph (new)
- **Dimensions**: 16×16 RGBA PNG (small — sits on a unit's action indicator, not a standalone HUD element).
- **Colour**: locked to the existing `CHANNEL_COLOR` table (`fieldFx.ts`) — melee `#f0f0f0`, ranged `#ffd54f`, magic `#ba68c8`, voice `#f48fb1`, support `#80cbc4`. **Do not re-derive these hues** — they are canon per `ART_THEME.md` §3.
- **Naming**: `ui_glyph_channel_<name>_16.png`.

### Nameplate frame (new — ⚠️ DELEGATE the implementation)
- **Spec, not implementation**: two edge variants (solid, striped) as a **tintable alpha mask**, not baked colour — team colour is applied at runtime so one asset serves every team. Exact pixel dimensions depend on the HUD layout `ui-programmer` owns; this document fixes the *technique* (mask + runtime tint) and the *requirement* (a colourblind-safe secondary tell alongside hue), not the box size.
- **Naming**: `ui_frame_nameplate_solid.png` / `ui_frame_nameplate_striped.png`, size suffix once ui-programmer confirms layout.

### Merch/fan icon (new)
- **Dimensions**: 64×64 RGBA PNG.
- **Style**: flat UI icon language (matches status icons), **not** painterly — this is a peripheral revenue-UI surface, budget accordingly (§6).
- **Naming**: `ui_merch_<item>_64.png`.

### League-material UI chrome (new)
- **Spec**: 9-slice panel textures reading the same material palette arenas already use (`themes.ts`) — timber grain for Wood, gilt brass for Gold, etc. Exact slice dimensions are `ui-programmer`'s call; this document fixes the *palette source* (reuse `themes.ts`, do not author a second palette) and the *count ceiling* (≤10, one per league material, not per league — Bronze reuses Copper+Tin's material story per `ART_DIRECTION.md`'s alloy note, so it may not need its own panel skin; confirm during implementation).

---

## 3. Generation prompts and method — first tranche

Route B (`codex` CLI, ChatGPT-subscription-backed) per `ART_PIPELINE.md`; run
`python3 tools/codex_check.py` before starting a session — if it reports the subscription
lapsed, that is the known failure mode, not a prompt problem. Route A is billing-capped;
do not attempt it first. Route C (`pixelRig.ts`) is placeholder-only — never ship it.

### ⚠️ The gap this tranche exists to close: no generated asset has a tintable carrier yet

`BATTLE_SPRITES.md`'s style wrapper and the Mammal pilot prompts describe *the creature*,
never a team-colour object in a reserved key colour. Scaling straight to 60 more species
on the existing wrapper would produce 360 more images with the same gap the Mammal 30
already have. **Before scaling, run one pilot per unproven carrier category** — 6 species,
36 images — to prove the masking technique survives generation and pixelisation the way
the Mammal pilot proved portrait-matching survived it.

**Pilot species** (pick the anatomically hardest case in each category, since an easy case
proving nothing is wasted pilot budget):
| category | pilot species | why this one |
|---|---|---|
| Avian | Corvaan (raven) | smallest body, least surface for a leg-band or ribbon to read at 40px |
| Aquatic | Maelurk (octopus) | no shell, no fin — hardest anchor point in the whole roster |
| Insectoid | Odonatra (dragonfly) | thinnest thorax of the five, worst case for a lashed thread |
| Draconic | Pyraxon | baseline drape case, establishes the technique before Abyssal's harder variant |
| Abyssal | Voidmaw | ⚠️ different technique (additive glow, not colour-key — see §4); pilot this one specifically to prove the runtime path, not just the art |
| Mythical | Titanrex | confirmed already reads as "athlete" (`ART_THEME.md` sample) — isolates the medallion/braid question without also fighting a war-armour redirect |

Mammal, Marsupial, Reptilian, and the fusion bodies are **not** piloted separately — they
share the limbed-land wrap/sash carrier already proven low-risk by the (un-tinted) Mammal
30, so they go straight to batch once the carrier-mask technique itself is proven on the
6 above.

### Generation prompt template (portrait-referenced idle frame)

```
codex exec --skip-git-repo-check \
  "Generate exactly one image and do nothing else. Image: redraw THIS exact creature
  [--ref public/sprites/<id>.png] as pixel art. <CARRIER CLAUSE — see §4 table for the
  exact object per body type>, rendered as a SOLID FLAT #FF00FF magenta with no shading,
  no gradient, no blending into the surrounding material — a pure flat colour key, not a
  dyed object. Do not use magenta anywhere else in the image. <BATTLE_SPRITES.md STYLE
  WRAPPER, verbatim>."
```

- Motion frames (`walk1–4`, `strike`) reference the finished **pixel idle**, not the
  portrait — unchanged from `BATTLE_SPRITES.md`, and the magenta carrier must be
  re-described in each motion-frame prompt too (referencing the idle keeps the pixel
  *style*, it does not guarantee the carrier survives at its new pose/angle without being
  told to redraw it).
- **Key-colour collision check before generating**: if a species' own portrait already
  contains magenta/hot-pink (checked visually, or via the same histogram approach
  `tools/sample_ramp.py` already uses for ramp extraction), switch the reserved key to
  cyan `#00FFFF` for that species and record which key was used per species — the
  post-processor needs to know which key to mask on.

### When generation fails in the ways `ART_PIPELINE.md` documents

| failure | what it looks like | fix |
|---|---|---|
| `billing_hard_limit_reached` (Route A) | hard account cap | switch to Route B, don't retry Route A with smaller params |
| `403 Forbidden` (Route B) | codex agent responds but image tool refuses | run `python3 tools/codex_check.py` — if it reports the ChatGPT subscription lapsed, that's the cause; nothing in-repo needs to change, renewal fixes it immediately |
| sealed interior white (pixel frames) | a bright hole punched in the body, worst on `walk2`/`walk4` | `fill_interior_white()` in `tools/battle_sprite.py` — already handles small enclosed pockets; do not disable it if a real marking is ever lost, add a size cap instead (documented risk in `BATTLE_SPRITES.md`) |
| downscale-to-pixelate temptation | muddy blurry miniature | do not do this — tested and rejected; always generate native pixel art |
| carrier colour drifts off the reserved key (this document's new failure mode) | masking script finds 0 or too few key pixels | reject the frame, do not accept a "close enough" hue — a partial mask produces a partial team-colour object at runtime, which is worse than none; regenerate with a more explicit "PURE flat #FF00FF, no shading" clause |
| generic-hint drift (Grivvel/Maneleo-class failure) | portrait's actual design gets ignored, output reverts to the plain animal | describe the portrait's real design + a negative ("NOT brown, NOT a bear"), per the two documented pilot failures in `BATTLE_SPRITES.md` |

---

## 4. The team-colour carrier — production rule

This is the mechanism that makes "Guild Colours" real on 65 species without hand-authoring
per-team art, and it has two parts: **what object carries the colour** (per body type,
`ART_THEME.md` §1 already decided this) and **how that object survives being recoloured
at runtime without being regenerated per team** (undecided in the source docs — this
document's main technical contribution).

### The runtime problem, stated plainly

A team's colour is a per-match or per-roster value, not a fixed property of a species. A
single flat PNG cannot be "team-coloured" at generation time — there is no fixed set of
team colours to generate against. The carrier must therefore be generated as an **isolable
region** and recoloured **after** generation, at runtime, not baked in.

### The technique: reserved-key masking

1. **At generation time**, the carrier object is rendered in a pure, flat, reserved key
   colour (`#FF00FF` magenta by default, `#00FFFF` cyan on collision — see §3) with an
   explicit "no shading, no gradient" instruction, because AA/shading on the key colour
   breaks a clean mask.
2. **Post-processing** (new script, sibling to `tools/battle_sprite.py` / the portrait
   `process.py`) extracts a single-channel mask from the key-colour pixels (colour distance
   threshold, not exact match, to tolerate minor AA at the edge) and produces two outputs:
   the base image with the key colour flood-filled to a neutral mid-tone placeholder, and
   a separate mask PNG.
3. **At runtime** (⚠️ DELEGATE to technical-artist), the mask is composited over the base
   with the team's actual colour — multiply-tint for cloth/dye carriers, **additive-glow
   tint for Abyssal's bioluminescent carrier specifically**, because "glow" is emissive
   light, not dyed material, and a multiply blend on a dark deep-sea body would darken
   rather than illuminate it. This is the one carrier category that needs a genuinely
   different runtime blend mode, not just a different mask shape.

### Per-body-type carrier table (the concrete mechanism, per species group)

| carrier category | bodies (species count) | carrier object | generation clause | runtime blend |
|---|---|---|---|---|
| Limbed land | Mammal, Marsupial, Reptilian (15) | wrist/ankle wraps + waist or chest sash | "solid flat magenta cloth wrap around both wrists/ankles and a magenta sash across the chest/waist" | multiply-tint |
| Avian | Avian (5) | dyed leg-band, or a ribbon threaded through 2–3 flight feathers | pick per species — a wading/ground bird (Balaenix) reads a leg-band, a flighted one (Larkessa) reads a feather-ribbon better; not a fixed template | multiply-tint |
| Aquatic | Aquatic (5) | dyed cord/painted shell bands | per species — Nautilux/Maelurk have a shell or mantle to paint bands on; Carcharun, Mantaris, Lanterix have neither and need a cord through a fin — **a genuine per-species judgement call**, not a fill-in-the-blank; flag each choice in the audit | multiply-tint |
| Insectoid | Insectoid (5) | waxed thread lashed across the thorax, or a pigment dab on the carapace | "small solid magenta pigment mark on the carapace" reads more reliably at 40px than a thread on a species with a narrow thorax (Odonatra) — pilot (§3) settles which | multiply-tint; ⚠️ smallest carrier in the roster, verify the mask survives at 32px status-icon scale too if this carrier is ever echoed there |
| Draconic | Draconic (5) | heraldic drape, shoulder/back, more ceremonial in cut than the base sash | "magenta ceremonial drape across one shoulder and down the back" | multiply-tint |
| Abyssal | Abyssal (5) | bioluminescent markings — light instead of dye | "magenta bioluminescent marking pattern" — generation clause is the same colour-key trick, but see runtime column | **additive glow**, not multiply — different shader path, flag to technical-artist explicitly |
| Mythical | Mythical (5) | guild medallions / rank braid — achievement, not birthright | "a magenta medallion on a cord" or "a magenta braided cord" — never a crown | multiply-tint |
| Fusion | Saurian, Tempestine, Broodkin, Primeval (20) | inherits from **both** parent bodies where anatomically compatible | per-species: Saurian (Mammal+Reptilian) defaults to the shared limbed-land wrap/sash since both parents already use it; Tempestine (Avian+Aquatic) and Broodkin (Marsupial+Insectoid) each need a real per-species call between their two parents' carriers; Primeval (Mythical+Draconic/Abyssal) likely combines medallion + drape | mixed — inherits its resolved parent's blend mode; **audit all 20 individually, this is real design work** (`ART_THEME.md` already flagged fusion silhouette as open, this is the carrier half of that same audit) |

⚠️ **The carrier is never a recolour of hide/fur/feather/scale/shell.** The key-colour
technique enforces this by construction — the mask only ever touches pixels the generator
was told to render in the reserved key, so it is structurally impossible for the mask to
bleed onto the species' own material *if the generation followed the clause*. This is an
argument for the technique, not just a restated rule: a reviewer checking a rejected frame
in §3 ("carrier colour drifts off the reserved key") is the same check that catches a
carrier accidentally painted onto the wrong region.

### Why this expands the portrait-audit scope beyond what `ART_THEME.md` §5 step 3 asked for

`ART_THEME.md` scoped the portrait audit narrowly: check the war-armour/athlete's-kit
table, redirect the minority that fails (Maneleo confirmed, ratio unknown). **That audit
alone under-scopes the work once tinting is accounted for**: none of the 65 existing
portraits were generated with an isolable key-colour carrier, because the requirement
didn't exist yet when they were made. So even a portrait that already passes the
war-armour check (Kongrath, Aegisox, Titanrex — all confirmed fine) still needs a **second,
separate pass**: an inpaint/patch generation that adds an isolable magenta carrier object
onto the existing approved portrait, using the same `--ref` technique battle sprites use
to stay on-model. Two audits, two different fixes:

| finding | fix | scope |
|---|---|---|
| fails war-armour register (Maneleo-class) | full portrait regeneration with the redirected costume | targeted minority, ratio TBD by audit |
| passes war-armour but has no isolable carrier (everyone, by default) | inpaint-only patch adding the carrier region in the reserved key colour | **all 65**, unless the audit finds some already have an isolable object by accident |

---

## 5. Readability acceptance criteria — a testable battery, not an assertion

Four concrete checks, each with an artefact and a pass threshold, run against a captured
frame from a live 5v5 (`arena.tsx` team-battle view), not a curated screenshot. Run the
battery whenever the carrier convention, the nameplate frame, or the HP/status colour
system changes — it is a regression check, not a one-time sign-off.

| # | test | artefact | what it isolates | pass threshold |
|---|---|---|---|---|
| 1 | **3-second team ID** | live frame shown for exactly 3s, then hidden | "who's who" — does the carrier + nameplate frame read fast enough under time pressure | ≥90% correct team-side identification across all 10 units, tester naive to which team is which beforehand |
| 2 | **Squint/blur test** | same frame, gaussian blur (≈12–20px, tuned to match the 40px display size dropping to a blob) | whether team colour carries enough *area*, not just correct hue, to separate into two legible clusters at a glance | two colour clusters visually separable by a fresh viewer with no other context |
| 3 | **Colourblind pass** | same frame, protanopia/deuteranopia simulation filter | whether the nameplate's solid-vs-striped secondary tell (not hue alone) still carries team identity | ≥90% correct team-side ID using edge pattern only, hue removed |
| 4 | **HP rank-order test** | frozen mid-fight frame, HP numbers/percentages hidden, only bar fill visible | "who's winning" — does the green→amber→red threat gradient communicate relative danger without arithmetic | tester's guessed HP rank-order across the 10 units correlates with actual rank at ≥0.8 (Spearman), or every unit ranked within ±1 position |

⚠️ **"Under fire" glow** (the highest-value proposal in `ART_THEME.md` §3, backed by
`tools/focus.ts`'s measured 0.711 top-share) needs its own fifth check once built — "point
at the unit taking damage" during a live, unpaused fight — but that is a VFX/engine
feature (⚠️ DELEGATE to technical-artist), not a static-frame art check, so it is listed
here as a follow-on to the battery rather than folded into it. Recommend the pulse use a
**warm white/gold**, achromatic enough not to collide with team colour (varies), HP
gradient (green/amber/red), or any status-icon family (§2) — and it ties back to the
arena's "one warm working lamp" motif for free. This is a recommendation for
technical-artist to confirm, not decided here.

---

## 6. The fan/merch surface

Scoped deliberately small — this is a peripheral, low-screen-time system (crowd sits at
the edge of frame per `ART_THEME.md` §2's camera pivot; merch is a shop-screen revenue
line, not a battle-critical read) and should not receive painted-portrait-tier budget.

- **Fan blocks (crowd)**: covered under crowd geometry (inventory item 12) — instanced
  low-poly spectator silhouettes, coloured in team blocks by tint (same multiply-tint
  technique as the nameplate frame, reusing rather than inventing a new mechanism). No
  per-fan detail; readability at the venue's peripheral role doesn't need it. Fill amount
  stays gameplay-owned (fame/meta modifiers) — art only defines the filled/empty *look*
  per grandeur tier (11 rungs × 2 states, item 12).
- **Banners**: a tintable pennant/banner mesh or decal, same mask+tint technique. One or
  two shape templates (a hanging banner, a raised pennant), not per-league bespoke art —
  the league's *material* (already handled by venue theming) plus the *team's* tint on a
  shared shape is enough differentiation.
- **Merch icons**: flat UI icons for the shop/revenue screen — scarf, banner, pennant,
  badge, plus one spare category (~5 templates total, §2 spec: 64×64, flat, tintable via
  the same key-colour technique so one drawn "scarf" serves every team colour without
  redrawing it per team).

**Explicitly not in scope for this surface**: unique per-species merch, unique per-team
painted art, or any painterly-tier rendering. If the fan/merch system grows into something
players spend real screen time on, revisit the fidelity budget then — don't front-load it
now against a system that's currently a numbers-and-icons revenue line.

---

## 7. Sequencing against the Godot rebuild

**Can be made now, survives the arena rework regardless of final dimensions:**
- Portrait audit + fusion audit (inventory 1–2)
- Carrier-mask technique + pilot tranche (inventory 3–4, §3–4) — this is a 2D raster
  technique, engine-agnostic; the *runtime tint* implementation is Godot-side work for
  technical-artist, but the *asset* doesn't change when the engine does
- Battle sprites at scale (inventory 4) — same reasoning; battle sprites are the field
  engine's asset regardless of which engine renders the field
- Status/glyph/nameplate/merch icon sets (inventory 5–8) — UI-layer, not arena-layer
- The exterior-silhouette **checklist** (inventory 10) — the *list of 24 distinct building
  identities* is a naming/design exercise that doesn't require knowing exact metres; it
  can be drafted and even partially authored (which league gets a dome vs a colonnade vs
  a turreted quadrant) before the blueprint fixes numbers, then reconciled

**Must wait on `docs/ARENA_BLUEPRINT.md`** (confirmed not to exist yet — this is a hard
dependency, not a soft one):
- Any arena/venue 3D asset with a real dimension: board layout, prop placement and scale,
  camera distances for the establishing shot vs tactical follow, exterior silhouette
  *authoring* (as opposed to the checklist's naming pass above)
- Crowd/fan geometry placement (needs venue geometry to sit in)
- Photoreal JPEG retirement — ties 1:1 to when each league's Godot venue actually lands,
  not a single cutover date; a league keeps its JPEG as the live asset until its own
  venue is built, then the JPEG demotes to the concept-art reference folder

⚠️ **This document does not spec arena dimensions, board counts beyond the already-known
24, or camera distances** — those are `ARENA_BLUEPRINT.md`'s job. Where `ART_THEME.md`
§2 describes the establishing-shot/tactical-camera split and the exterior-silhouette
differentiator, this document treats both as confirmed *direction* to build the checklist
against, not as licence to invent the numbers the blueprint owns.

---

## Open items requiring a decision (not guessed here)

1. **Reserved key colour collisions per species** — needs a pass (extend
   `tools/sample_ramp.py` or equivalent) before generation starts, not caught ad hoc.
2. **Asset naming convention for `public/sprites/` and `public/battle/`** — flagged in
   `ART_THEME.md` §5, still unresolved; new asset classes in this document (icons, merch,
   nameplate frames) use the canonical `[category]_[name]_[variant]_[size]` pattern since
   they have no legacy pattern to break.
3. **Nameplate frame and UI-chrome exact pixel dimensions** — layout-dependent,
   `ui-programmer`'s call; this document fixes technique and palette source only.
4. **Aquatic and fusion carrier choices per species** — genuinely can't be templated;
   listed as an audit task, not resolved here.
5. **`ARENA_BLUEPRINT.md`** — does not exist yet. All arena/venue/crowd work in this
   document is blocked on it by design.
