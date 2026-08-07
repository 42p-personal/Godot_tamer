---
name: art-production-plan
description: docs/ART_PRODUCTION.md — the executable plan for Guild Colours, the carrier-mask technique it invented, and what's blocked on ARENA_BLUEPRINT.md
metadata:
  type: project
---

`docs/ART_PRODUCTION.md` (written 2026-08-03) turns [[art-theme-guild-colours]] into an
inventory, per-asset specs, generation prompts, and a sequencing order. Key things a
future session needs without re-deriving:

- **The team-colour carrier's runtime problem was unsolved in `ART_THEME.md`.** A team's
  colour is per-match/per-roster, not a fixed species property, so a single generated PNG
  can never BE team-coloured — it has to be generated with an isolable carrier region and
  recoloured at runtime. Solved here as **reserved-key masking**: generate the carrier
  object (sash/wrap/drape/etc., per body type) as pure flat `#FF00FF` magenta (or cyan
  `#00FFFF` on a per-species collision), extract a mask in post (new script, sibling to
  `tools/battle_sprite.py`), tint at runtime — multiply-blend for cloth/dye, **additive
  glow for Abyssal specifically** (bioluminescence is emissive, not dyed, so multiply
  would darken it instead of lighting it up). ⚠️ DELEGATE the runtime tinting to
  technical-artist; this doc only fixes the generation-time convention.
- **This expands the portrait-audit scope beyond what `ART_THEME.md` asked for.** That
  doc scoped the audit narrowly (war-armour register only, redirect the minority that
  fails). But NONE of the 65 existing portraits have an isolable carrier at all — the
  requirement postdates them — so even portraits that already pass the war-armour check
  (Kongrath, Aegisox, Titanrex) still need a second, separate inpaint pass adding the
  carrier region in the reserved key colour. Two audits, two different fixes, both
  needed on all 65.
- **Real counts found by reading the filesystem, not trusting either source doc**: 65/65
  portraits generated (confirmed correct); **30/390 battle sprites generated** (the full
  Mammal group), not the 0/390 both `ART_PIPELINE.md` and `ART_THEME.md` claimed — see
  [[art-theme-guild-colours]] for the correction note. Always recount before trusting a
  doc's asset table.
- **Battle-sprite production order**: don't scale straight from the (carrier-less) Mammal
  30 to the other 60 species. Run a 6-species carrier-pilot tranche first — one per
  unproven carrier category, picking the anatomically HARDEST case each time (Corvaan for
  Avian, Maelurk for Aquatic — no shell or fin to anchor a cord, Odonatra for Insectoid,
  Pyraxon for Draconic, Voidmaw for Abyssal — proves the additive-glow runtime path,
  Titanrex for Mythical). Mammal/Marsupial/Reptilian and the fusion bodies skip a
  dedicated pilot — they share the limbed-land wrap/sash carrier the Mammal 30 already
  de-risked (minus the carrier-mask part, which the pilot tranche proves separately).
- **Readability acceptance criteria — a 4-test battery, not an assertion**: 3-second team
  ID (≥90%), gaussian-blur squint test (colour clusters must separate as blobs),
  colourblind-simulation pass (≥90% using the nameplate's striped-edge tell alone, hue
  removed), HP bar rank-order test (Spearman ≥0.8 against hidden HP%). Run whenever the
  carrier, nameplate, or status-colour system changes — a regression check, not one-time
  sign-off. The "under fire" glow (highest-value proposal in `ART_THEME.md`, backed by
  `tools/focus.ts`'s 0.711 top-share) gets a 5th live-fight test once built, not folded
  into the static-frame battery; recommended colour is warm white/gold (achromatic,
  doesn't collide with team colour/HP gradient/status hues) — a recommendation for
  technical-artist to confirm, not decided unilaterally.
- **`docs/ARENA_BLUEPRINT.md` does not exist yet** (confirmed absent, 2026-08-03). All
  arena/venue-dimension work is genuinely blocked on it — this doc does not guess
  dimensions. What CAN proceed now regardless: the exterior-silhouette *checklist* (the
  list of 24 distinct building identities for the Platinum→Tamers Apex 5v5 pool) is
  dimension-agnostic and can be drafted/partially authored before the blueprint lands.
- **Fan/merch surface deliberately scoped small**: flat UI icons (~5 templates: scarf,
  banner, pennant, badge, +1 spare), reuses the carrier's tint technique, explicitly NOT
  painterly-tier or per-species/per-team unique art — it's a peripheral revenue-line
  system, not battle-critical.
