---
name: project-arena-blueprint
description: docs/ARENA_BLUEPRINT.md exists and is the blocking spatial spec for the Godot rebuild — GROUND scales 4x linear (not the venue alone), SPREAD/leash and aura formulas, load-bearing dependencies
metadata:
  type: project
---

Wrote `docs/ARENA_BLUEPRINT.md` (2026-08-03, revised same day) as the blocking artefact
`docs/DECISIONS_2026-08-03.md` #3 called for — everything spatial (leash/SPREAD, deploy depth,
reach, cover placement, the balance re-baseline) is sized from it.

⚠️ **CORRECTED BY THE USER, ON RECORD, DO NOT REPEAT THE FIRST READING.** The first pass put the
"~4x our current largest" instruction entirely on the VENUE and *shrank* the GROUND (the actual
fighting space) to 62×42 — smaller than the 82.45×59.5 board already shipped. The user overrode
this explicitly: *"The arena's PLAYING SPACE should be bigger... forget about the current size,
but make a far larger arena."* **The GROUND itself must scale up substantially — not just the
venue.** The corrected doc lands the 5v5 GROUND at **160×88** (a literal 4x-linear scale of the
`40×22` field the ability pool is tuned against — this exact number was already sitting,
unremarked, in `docs/ABILITY_BALANCE_REVIEW.md` §1.1's own worked table).

**Why the first reading was wrong, for future judgment calls:** the supporting argument (that
`LEASH_RADIUS=12` caps every fight to a 24-unit huddle regardless of board size, so a bigger board
alone buys nothing) was CORRECT, but the conclusion ran backwards — **the leash is the bug to fix,
not evidence a big ground is wasted.** SPREAD replaces the leash and scales WITH the ground, so a
bigger ground gets genuinely used. Don't re-derive "keep the ground small" from a correct
observation about a mechanic that's about to be replaced.

**Key formulas in the corrected doc (§0–§6):**
- `k(N) = 2.0 + 0.5×(N−1)`, hits `k(5)=4.0` exactly. `GROUND(N) = k(N) × (40,22)` — keeps the
  40:22 (1.82) aspect at every size, wide by construction.
- SPREAD/leash: `usable_radius(N) = 0.4×GROUND_H(N)`, `LEASH_RADIUS(N,spread) =
  lerp(0.55,0.95,spread) × usable_radius(N)`. Holds at a constant ~42% of ground width at every N
  by construction (both terms linear in `k`) — the engagement envelope is always a fraction of
  the ground, which is the actual answer to "won't a bigger ground be diffuse?"
- Reach rescaled by the SAME `k(5)=4.0`, applied globally (one authored table for every league,
  since the game balances at 5v5). Volley: 10.5→42.0. `HARD` clamp: [2.4,11.0]→[9.6,44.0].
- **Auras are now proximity-sized** (decided after the first pass): `AURA_RADIUS(N) =
  1.1×TIGHT_leash_radius(N)` — deliberately covers a tight formation, deliberately falls short of
  a loose one. This is the mechanism that makes CHA/CON/WIS support prefer tight and DEX/assassin
  kits prefer loose, for a reason a player can see on the field.
- `DEPLOY_DEPTH(N) = 6+N` unchanged from the first pass — deliberately NOT scaled by `k` (body
  size doesn't change because the world did).
- VENUE is now just a margin: `VENUE(N) = 1.35 × GROUND(N)` (down from the first pass's separate
  2x-arenaGridFor multiplier, since the ground now carries the "4x" growth itself).

⚠️ **The whole revision's pacing argument is CONDITIONAL and stated as such in the doc (§2, §9):**
front-line separation at 5v5 is 143.5 units; a straight uncontested close takes ~24s at max speed,
longer than the median fight (15.3s). The doc argues this is survivable ONLY if
`docs/ENGAGEMENT_DESIGN.md`'s Family A (closing-speed bonus / gap-closer refund) and Family B
(minimum range) land alongside this ground size — flagged explicitly as a load-bearing dependency,
not hidden in a footnote. If those don't land, the honest fallback is a smaller `k(N)` curve, not
shipping these numbers as-is.

⚠️ **AREA vs LINEAR is now resolved: LINEAR**, per the user's own wording ("far larger... all of
them are too small" reads as literal size, not footprint-doubling). Don't reopen this — it was the
first pass's other open flag and the coordinator closed it explicitly in the same correction.

Also carried over unchanged from the first pass (§7): cover semantic tags (`blocking` /
`coverGrade: soft|hard` / `breaksLOS`), which reverse the standing `types.ts` invariant "kind is
presentation only" — deliberate per decisions #16, but needs an explicit authored field/lookup
table, never inferred from a prop's sprite name.

See [[decisions-2026-08-03-log]] for the source decision list and [[spatial-model-godot]] for the
six-layer spatial model this blueprint feeds into.

**Not yet done:** none of this has been run through `sweep40`/`mapsweep` — §9 of the blueprint is
the measurement checklist, now centred on confirming Family A/B actually fix the opening-pacing
risk at this ground size. Treat every number in the doc as "derived, not yet validated."
