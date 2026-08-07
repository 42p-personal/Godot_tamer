---
name: project-art-bible-guild-colours
description: docs/ART_BIBLE_GUILD_COLOURS.md exists — the binding spec for the Godot vertical-slice art (12-species roster, 5 painted leagues), written 2026-08-03/04 while two art-generation agents were live against style wrappers I gave them.
metadata:
  type: project
---

`docs/ART_BIBLE_GUILD_COLOURS.md` is the operational art bible for the **vertical slice**,
narrower than `docs/ART_THEME.md` (the full 65-species/three-tier doctrine). It binds:
- the 12-species `ROSTER` and 5-league `ARENA_LEAGUES` in `monster-tamer/scripts/art.gd`
- the two live style wrappers (CREATURE side-on painterly cutout; ARENA BACKDROP painterly
  matte + ARENA GROUND seamless tile)

**Why it exists:** two art agents were generating against wrappers nobody had checked
against the theme docs or against `art.gd`'s own asset contract. The bible's §7 is a
re-roll punch-list, written to be actioned *while generation is still running*.

**The three findings worth remembering across sessions** (all in §7 / §4 of the bible):
1. The CREATURE wrapper's "one team sash" instruction only fits 4 of 12 roster species
   (Mammal/Reptilian). Avian needs a leg-band/ribbon, Insectoid needs a waxed thread/pigment
   dab, and the three prestige species (Pyraxon/Draconic, Tenebrae/Abyssal, Titanrex/Mythical)
   each need a distinct carrier register per `ART_THEME.md` §1 (drape / bioluminescent glow /
   guild medallion).
2. The ARENA BACKDROP wrapper carries **no grandeur/ornament specification per league** —
   nothing stops Bronze picking up Silver's columns or Apex shipping under-decorated. The
   fix is a cumulative-ornament table keyed to the 5 painted rungs (0/3/5/7/10 of the
   11-rung ladder), reproduced in the bible §3.
3. **`TEAM_COLOURS` in `art.gd` (guild blue/red/gold/green/violet) collides 5-for-5 with
   the status-hue anchors `ART_THEME.md` §3 proposes** (blue↔buff, red↔bleed, gold↔burn,
   green↔poison, violet↔utility-debuff) — nobody cross-checked the two when each was
   written. Also: `team_colour(index) = TEAM_COLOURS[index % 5]` guarantees an EXACT
   (not just likely) collision every 5th team, stronger than what `ART_THEME.md` anticipated.
   Flagged as needing resolution before status icons are authored, and as a hard (not
   optional) requirement for `ui-programmer` to add a non-colour nameplate tell.

**How to apply:** before touching creature/venue/palette art again, read this bible first —
it is more current and more specific to what's actually shipping than `ART_THEME.md` alone.
If `TEAM_COLOURS` or the roster/league lists in `art.gd` have since changed, re-verify the
findings above still hold before citing them.
