---
name: art-theme-guild-colours
description: The whole-game art theme (creatures + arenas + UI) written for the Godot port — name, key mechanisms, and where it lives
metadata:
  type: project
---

`docs/ART_THEME.md` (written 2026-08-03) is the top-level visual identity doc, above
`docs/ART_DIRECTION.md` (arena material/surface/grandeur axes — still current) and
`docs/ARENA_DESIGN.md` (arena layout/signature theory — still current). Named **"Guild
Colours"**: a sport built by hand, judged by trade guilds, fought by athletes who dress for
the ring, not for war.

Key mechanisms decided, in case later sessions need to act on them without re-deriving:

- **Three colour systems that must never collide**: league material (arena stone/lamp,
  fixed per league) / team colours (creature sash + nameplate + UI accent, per match) /
  status vocabulary (fixed game-wide). Modeled directly on the material/surface/grandeur
  collapse mistake already recorded in `ART_DIRECTION.md` — same failure shape, new axes.
- **Team-colour carrier**: every creature wears a small removable-looking team-colour
  object (wraps/sash for limbed land species, leg-band for Avians, dyed cord/painted shell
  bands for Aquatics, waxed thread or carapace pigment dab for Insectoids, a ceremonial
  drape for Draconic/Abyssal, guild medallions for Mythical) — solved per body type, never
  a recolour of the creature's own hide/fur/scale/feather.
- **Gear redirect**: current portraits lean "war armour" (Maneleo's pharaoh regalia+cape)
  which visually contradicts the standing rule that class is emergent/never destined
  (CLAUDE.md). Redirect to "athlete's kit" register (wraps, harness, earned sash) —
  targeted fix on a minority of the 65, not a full redo. A full 65-portrait audit against
  this table is still open (only 3 species were sampled while writing the doc: Kongrath and
  Aegisox already read correctly as athletes, Titanrex reads correctly, Maneleo confirmed
  needs the redirect).
- **Camera pivot**: old fixed board-fitted camera → establishing shot (grandeur, once per
  battle) + tactical follow camera (readability, during the fight). This unlocks exterior
  venue silhouette as a cheap differentiator for the 24-board interchangeable 5v5 pool
  (Platinum→Tamers Apex), which floor-signature variety alone can't carry at that count.
  See [[five-v-five-is-the-game]] in the shared project memory for why that pool exists.
- **Readability's single highest-value proposal**: an "under fire" glow/pulse on the
  current focus target, justified directly by `tools/focus.ts`'s measured top-share 0.711 —
  grounded in sim data already in the repo, not a guess.
- **Production order decided**: battle sprites FIRST (spec is `BATTLE_SPRITES.md`, 6
  frames × 65 = 390, not the stale 4-frame/260 count in `ART_PIPELINE.md`'s summary
  table), portrait audit second (targeted, not wholesale), arenas ported-then-extended
  third, UI last (depends on the battle-sprite icon "hand"). Photoreal JPEG backgrounds
  (`public/backgrounds/*.jpg`) are demoted to concept-art/mood references only — they
  cannot survive as shippable assets once a league's Godot 3D venue exists (flat
  photoreal painting behind a stylised HD-2D fight is exactly the kind of inconsistency
  the doc exists to prevent).
  ⚠️ **ART_THEME.md's own "0 of 390" was ALSO stale when written** — the filesystem
  (checked while writing `docs/ART_PRODUCTION.md`, 2026-08-03) shows **30 of 390 already
  generated**: the full Mammal group (Kongrath, Aegisox, Maneleo, Grivvel, Ursath), all 6
  frames each. But those 30 predate the team-colour-carrier requirement, so 0 of them are
  "Guild-Colours-complete" — see [[art-production-plan]] for the carrier-mask technique
  this forced (reserved key colour `#FF00FF`, isolated to a runtime-tintable mask, since a
  static PNG can't carry a per-match team colour). Always recount `public/battle/*.png`
  and `public/sprites/*.png` directly before trusting any doc's asset count — this is the
  second time in one day a "0 generated" claim in this doc set was wrong.

Existing code convention adopted as canon rather than replaced: `CHANNEL_COLOR` in
`src/tamerengine/fieldFx.ts` (melee white / ranged amber / magic purple / voice pink /
support teal) — already correctly replaced elemental VFX color after elements were removed
from the game. The ad hoc emoji status icon set (`EFFECT_ICON`, same file) was flagged for
replacement with an authored icon set matching the battle-sprite outline language.
