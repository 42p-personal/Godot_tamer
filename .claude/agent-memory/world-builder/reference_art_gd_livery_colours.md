---
name: reference-art-gd-livery-colours
description: Where the canonical team livery colours and badge glyphs live — check before authoring any guild/team identity
metadata:
  type: reference
---

`monster-tamer/scripts/art.gd` holds the source-of-truth `TEAM_COLOURS` (8 desaturated
livery tones) and `TEAM_BADGES` (8 glyphs: ◆▲●■★✦⬟✚), assigned by `team_colour(index)` /
`team_badge(index)` keyed on match slot (`index % 8`), not on any persistent identity.

These colours were deliberately chosen to be muted/worn (cloth-and-enamel register) so they
never collide with the game's brighter, more saturated status-effect colour vocabulary
(`docs/ART_THEME.md` §3's status hue groups) — an earlier saturated palette collided exactly
with the proposed status hues and was replaced for this reason. Do not propose new team
colours without checking this file's rationale first.

Any future world-building or art work that needs "the guild colours" should read this file
directly rather than trusting a memory snapshot of the hex values, since it may be edited by
other workstreams. See [[project-world-guilds]] for the guild fiction built on top of these
eight.
