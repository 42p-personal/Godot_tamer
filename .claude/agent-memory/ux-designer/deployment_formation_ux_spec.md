---
name: deployment-formation-ux-spec
description: docs/UX_DEPLOYMENT.md (2026-08-04) — the deployment/formation UX spec; key idea is role-tagged save slots, not monster-identity bindings.
metadata:
  type: project
---

Wrote `docs/UX_DEPLOYMENT.md` (2026-08-04), the UX spec for free-placement deployment against
`docs/AUTOBATTLER_DESIGN.md` §1 #1 / §2C / §5 (deployment is free placement anywhere in your own
half, saved as named formations; deployment width is a named anti-blob lever).

**The load-bearing design idea, worth remembering if this gets picked up again:** saved formations
store N numbered slots as **position + role/class tag** (captured from whichever monster occupied
the slot when saved — using the existing `m.role`/`m.class_name_` fields), never monster identity.
This is what makes a saved formation survive a roster change (swap a monster, breed a new one,
field a different five for a different league) without breaking. It's a direct one-layer-down
reuse of a finding [[doc-authoring-convention]]'s sibling doc `docs/TACTICS_BRAINSTORM.md` §2.3
already made and then set aside — "name formation slots by intent, not coordinates, because a
coordinate doesn't survive an arena change" — applied to save/load ergonomics instead of to the
live-fight mechanic (the user's free-placement decision correctly keeps raw coordinates as what
actually gets simulated).

**Why free placement is worth its complexity (my honest read, not a decision of record):**
conditionally yes — the real cost isn't the drag interaction, it's the mismatch-handling above. If
that's built well (role-tag auto-match + 4 starter presets — Line/Wedge/Box/Split — pre-populated
so day one isn't a blank canvas), the cost is paid once per matchup archetype and the other ~95%
of the ~1,708-match career (`docs/FUN_ADDITIONS.md`) is a one-click commit. Ship placement and
saved-formations together, not placement first — the gap between them is where the "90-second tax"
complaint would land.

**Open flags left for other disciplines** (see the doc's §10 for the full list): the exact "own
half" boundary (bounded by a neutral strip sized off `DEPLOY_SEPARATION = 33.1` so free placement
can't break the 12s-close guarantee in `ARENA_BLUEPRINT.md` §2), schematic-2D-vs-3D-camera board
rendering, the aura-ownership data hook, and the AoE cluster-warning radius (placeholder only,
anchored to `CONTAGION_RADIUS = 5.5`, needs a real authored figure from mechanics).
