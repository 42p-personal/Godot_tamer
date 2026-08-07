# Low-poly creature model — the working recipe

**2026-08-05.** Produced and verified one creature end to end, on the studio owner's instruction
to take real care with the prompt. This is the recipe that worked, the two attempts that did not,
and the one requirement still unmet.

---

## The recipe

**Text-to-3D, two-step.** Preview generates untextured geometry so the silhouette is judged before
any credits go on texturing — `ART_BIBLE_LOWPOLY.md` makes silhouette the acceptance test, and
texturing a bad mesh only buys an expensive bad mesh.

```json
{ "mode": "preview",
  "model_type": "standard",        // ⚠️ NOT "lowpoly" — see failure 1
  "ai_model": "latest",
  "should_remesh": true,
  "topology": "triangle",
  "target_polycount": 1200,
  "pose_mode": "a-pose",           // ⚠️ the riggability lever
  "target_formats": ["glb"],
  "alpha_thumbnail": true }
```

Then `{"mode":"refine","preview_task_id":<id>,"prompt":<texture prompt>,"enable_pbr":false}`.

**Cost: 30 credits** (20 preview + 10 refine). **Output: 1,259 tris, 2.6 MB.**

### The geometry prompt — exactly 600 characters, the hard limit

> Low-poly faceted 3D game character. Flat shading, hard edges, chunky simplified forms, strong
> readable silhouette. A muscular gorilla ATHLETE in a neutral A-pose: arms out from the body,
> palms open, feet flat, full body visible. WEARING A SPORTS UNIFORM: white sleeveless singlet,
> white cloth wraps on both forearms, white cloth wraps on both ankles, one plain fabric sash worn
> diagonally across the chest. Desaturated charcoal-grey fur. Clean solid colours, no patterns.
> Even neutral lighting, no baked shadows. NO weapons, NO armour, NO helmet, NO blood, NO skulls,
> NO ornament, NO base or scenery.

### The texture prompt — 348 characters

⚠️ **Lead with the UNIFORM, not the creature.** The geometry is fixed by this point and cannot
change; the only open question at refine time is whether the kit appears.

> White sleeveless sports singlet, white cloth wraps on both forearms, white cloth wraps on both
> ankles, and one plain flat-colour fabric sash worn diagonally across the chest. Desaturated
> charcoal-grey gorilla fur elsewhere. Flat solid colours, crisp edges between colour regions, no
> gradients, no patterns, no logos, no baked shadows or highlights.

---

## ⚠️ Two failures worth not repeating

**1. `model_type: "lowpoly"` DOES NOT PRODUCE LOW POLY.** The docs describe it as "optimised for
cleaner polygons" and note it *ignores* `target_polycount`. Measured: **13,744 triangles** — 5.5×
the 2,500 ceiling, with no way to constrain it. `model_type: "standard"` with an explicit
`target_polycount` gave **1,259**. Use standard.

**2. THE PROMPT LIMIT IS 600 CHARACTERS AND THE API TRUNCATES SILENTLY.** The first attempt was
**755** characters. I asserted it was 528 without counting, and said "every clause is
load-bearing". The API returned `202 Accepted` and quietly dropped everything past 600 — which was
exactly the art bible's forbidden list: *"No weapons, no armour plating, no helmet, no blood, no
skulls, no fantasy ornament."* **Assert the length before sending.** `tools/meshy_lowpoly.py`
now does.

---

## Scorecard

| requirement | result |
|---|---|
| 700–1,500 tris (`ART_BIBLE_LOWPOLY.md`) | ✅ 1,259 |
| Faceted, flat colour, crisp edges | ✅ |
| A-pose, riggable | ✅ arms out, palms open |
| Full body, feet flat, nothing cropped | ✅ |
| Readable silhouette at 40px | ✅ heavy-bruiser shape, distinct |
| Sporting kit, not war gear | ✅ singlet and ankle wraps present |
| No weapons / armour / blood / skulls / base | ✅ |
| Desaturated body colour | ✅ charcoal-grey |
| File size | ✅ 2.6 MB (vs 8.4 MB image-to-3D) |
| **Diagonal chest sash as a separable region** | ❌ **merged into the singlet** |

## ⚠️ The unmet requirement, and why it is not cosmetic

`ART_BIBLE_GUILD_COLOURS.md` makes the sash **the team-colour carrier** — the one element tinted
per team at runtime, deliberately kept OFF the creature's body so that *saturated means something
is happening, muted means this is who you play for* holds.

The model produced a white shoulder strap **the same white as the singlet**. It cannot be tinted
without recolouring the entire kit, which would put team colour on the uniform rather than on a
band — exactly the collision the palette discipline exists to prevent.

**Three ways out, untested:**

1. **Name a contrasting colour for the sash** in the texture prompt so it lands as its own region.
   Cheapest — one 10-credit refine to find out. ⚠️ But a *named* colour fights the runtime tint:
   the sash must be plain enough to recolour, and a strongly-coloured one may bake in shading.
2. **Drop the sash from the model; add it in-engine** as a separate tinted quad or mesh strip.
   Full control, guaranteed tintable, a small amount of renderer work.
3. **Drop the sash entirely** and let the nameplate badge and border carry team identity alone.
   ⚠️ Weakest: `docs/ACCESSIBILITY.md` already found 3 of 8 team colours collapse under
   deuteranopia, so removing a whole identity channel makes that worse.

**Recommended: (2).** The only option that guarantees a clean tint, and it removes team colour
from the generation problem entirely — every future creature then inherits team identity for free
rather than depending on a prompt landing correctly.

---

## Not yet tested

- ⚠️ **Whether the A-pose actually improves auto-rig success.** That was the entire hypothesis
  behind `pose_mode`. The avian was refused with `422 Pose estimation failed`, and the likeliest
  reason is that our portraits are in natural poses rather than A-poses. **This is the question
  that decides the roster plan** — if A-posed generation rigs the non-humanoid bodies, skeletal
  animation covers the whole roster; if not, procedural stays the floor.
- How the flat-shaded look sits under the arena's single warm lamp (`ART_DIRECTION.md`).
- Whether ten of these hold up on screen at once.
