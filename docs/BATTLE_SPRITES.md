# Battle sprites — spec (v0.93)

Battle sprites are a **second, separate art set** from the painted portraits in
`public/sprites/`. Both stay.

| | Portrait set (existing) | Battle set (new) |
|---|---|---|
| Where | Ranch, Market, Bestiary, Hall of Fame | the field engine only |
| Size | 320×320 RGBA | **128×128 RGBA** |
| Pose | 3/4 hero pose, one frame | **strict side profile, 4 frames** |
| Style | painted, detailed | flat, chunky, readable at 40px |

The portraits are the best-looking thing in the game and are viewed large and
still — they are not being replaced. Battle sprites exist because *animating*
painted 320×320 art for 65 species is not affordable, and because a monster
seen at 40px on a busy field needs a bold silhouette, not detail.
Teamfight Manager does exactly this split.

## Frames

Six per species, `public/battle/<id>-<frame>.png`. The engine's own
`UnitVisState` is `idle | move | cast | hurt | dead`, and the art has to cover
the first three convincingly — a monster crossing a 40-unit field spends most
of the fight in `move`, so the walk is the frame set that carries the whole
look.

| Frame | Purpose | Direction |
|---|---|---|
| `idle` | standing, between actions | facing right |
| `walk1` | contact — near leg forward, weight down | facing right |
| `walk2` | pass — legs together, body at its highest | facing right |
| `walk3` | contact — far leg forward, weight down | facing right |
| `walk4` | pass — legs together, opposite arm lead | facing right |
| `strike` | committing an attack | facing right |

**Why four walk frames, not two.** Two alternating contacts read as a shuffle,
because the body never rises. A four-frame cycle (contact → pass → contact →
pass) gives the vertical bob that makes it read as walking, and it is still the
minimum that does. If generation cost forces a cut, drop to `walk1`/`walk3`
(the two contacts) and let code add the bob — worse, but serviceable.

Everything else is done in code rather than art:

- **facing left** — `scaleX(-1)`, so no mirrored art is generated
- **hurt** — a red tint + shake on the idle
- **run** — the walk cycle played faster; no separate art
- **KO** — rotate and fade the idle
- **cast wind-up** — hold `strike` for the move's `castTime`

## Hard rules

1. **Strict side profile, facing right.** Not 3/4. The field is viewed from the
   side and units cross it horizontally; a 3/4 pose reads as facing the camera
   and ruins the sense of direction.
2. **FOOT-ANCHORED, not bbox-centred.** Every frame is padded so the creature's
   feet sit on the same baseline and its body centre sits on the same vertical
   axis. This is the whole reason a walk cycle doesn't jitter — the existing
   portrait pipeline centres the bounding box, which would make each frame
   bounce. `tools/battle_sprite.py` handles this.
3. **Consistent scale within a species.** All four frames drawn at the same
   apparent size; the script does not rescale per frame.
4. **Bold silhouette, flat colour.** It must read at 40px against a painted
   backdrop. Detail below ~4px is wasted.
5. **No ground shadow, no scenery, no border.** The engine draws its own
   shadow so it can move with the sprite.

## Style: PIXEL ART, matched to the portrait (v0.94)

The battle set is **pixel art**, and each sprite must depict the **same
creature** as that species' painted portrait in `public/sprites/`. Those two
requirements are met by one technique, validated on the Mammal pilot:

**Generate each sprite by referencing the species' PORTRAIT (`--ref
public/sprites/<id>.png`) with an explicit pixel-art prompt.** The portrait
carries the design — colours, armour, markings, build — and the prompt converts
the rendering to pixel art. Referencing the portrait (not a fresh description)
is what makes it MATCH; the pixel-art wording is what makes it pixel art.

⚠️ **Describe the portrait's actual design, not the plain animal.** Two of the
five pilots failed the first pass because the hint fought the reference:
- **Maneleo** is an *upright anthropomorphic lion warrior in red-and-gold
  regalia*, not a naturalistic lion — "proud male lion" gave a plain lion and
  dropped the armour and bipedal stance.
- **Grivvel** is a *black honey-badger with a pale silver back-stripe*, not a
  brown wolverine — the generic hint came out brown and bear-like.
Both were fixed by describing the portrait's real design and adding a negative
("NOT brown, NOT a bear"). When in doubt, say little beyond "redraw THIS exact
creature as pixel art" and let the reference lead.

⚠️ **Downscale-to-pixelate does NOT work.** Shrinking a smooth render to 64px
and quantising gives a muddy blurry miniature, not pixel art — tested and
rejected. Generate native pixel art.

### The two reference stages
1. **Idle** — reference the PORTRAIT, prompt pixel-art side-profile. Establishes
   the pixel look and the matched design.
2. **Motion frames (walk/strike)** — reference the finished PIXEL IDLE
   (`px/<id>-idle.png`), not the portrait. This keeps BOTH the identity and the
   pixel style across the cycle; referencing the painted portrait again would
   re-introduce the smooth style.

## Style wrapper (the pixel-art prompt, appended to every subject)

> DETAILED PIXEL ART game battler sprite in STRICT SIDE PROFILE facing RIGHT,
> full body, crisp hard pixel edges, limited palette, visible square pixels,
> clean dark pixel outline, subtle dithering, retro 16-bit RPG style, bold
> readable silhouette, plain solid pure-white background, no scenery, no
> shadow, no border, no text

## Pipeline

1. `codex exec` one frame at a time (see `image-gen-codex` skill)
2. `python3 tools/battle_sprite.py <id> <idle> <walk1> <walk2> <walk3> <walk4> <strike>`
   — close sealed white gaps (see below), white→transparent, trim, ONE SHARED
   SCALE, **foot-anchor**, pad to 128×128
3. Read the output and check it against its siblings before accepting

### ⚠️ Sealed interior white — `fill_interior_white()` in the processor

The generator often renders the GAP between a creature's legs (worst in the
pass poses, `walk2`/`walk4`, where the legs gather under the body) as a **white
shape sealed inside the silhouette**. The background flood-fill removes only
white reachable from the image border, so a sealed gap survives as a bright
**hole punched in the body** — visible in the Aegisox pilot's belly.

`fill_interior_white()` runs BEFORE the background removal: it finds near-white
pixels NOT connected to the border and grows the surrounding colour inward, so a
leg-gap (bordered by dark legs) fills dark and vanishes.

**Why it doesn't eat real markings.** It only closes SMALL enclosed pockets. A
large intended white marking — Grivvel's silver back-stripe, Kongrath's silver
saddle — reaches the silhouette edge and is border-connected, so it is treated
as body and left completely alone. Verified: Grivvel's stripe survives intact
while the Aegisox leg-gap closes. If a future species ever loses a marking to
this, the fix is a size cap on what may be filled, not disabling it.

## Cost

6 frames × 65 species = **390 images**, ~1–3 min each via Route B ≈ 7–20 hours
of wall clock. Batch it in the background overnight; do not block on it. The
Mammal group alone is 5 species = 30 images ≈ 30–90 min, which is the right
first bite.

## Known risk

Each frame is generated independently, so consistency between frames is the
thing most likely to fail — colour drift, size drift, a different number of
limbs. That is exactly what the Kongrath pilot is for. If drift is bad, the
fallbacks in order are: (1) cut to the two contact frames and add the bob in
code, (2) cut to idle + strike and do all motion procedurally.
