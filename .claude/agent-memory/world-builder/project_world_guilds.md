---
name: project-world-guilds
description: WORLD_GUILDS.md created 2026-08-04 — the eight-guild Circuit institution behind Guild Colours, and the key decisions inside it
metadata:
  type: project
---

`docs/WORLD_GUILDS.md` (owned exclusively by world-builder) authors the institution behind
the "Guild Colours" art identity: eight trade guilds who jointly run the Tamer Circuit.

**Why it exists:** `docs/ART_THEME.md` and `docs/ART_BIBLE_GUILD_COLOURS.md` asserted that
trade guilds grade the leagues and run the sport, but no one had written who the guilds are
or why. Requested by a parent agent (likely `creative-director` or `narrative-director`)
alongside ~15 other agents working the repo concurrently — file ownership was exclusive,
other agents were told not to touch it.

**Key decisions baked into the doc, useful to remember before extending it:**
- Eight guilds, one per the eight livery colours/badges already shipped in
  `monster-tamer/scripts/art.gd` (`TEAM_COLOURS`/`TEAM_BADGES`): Quarriers (slate blue ◆),
  Tanners (oxblood ▲), Founders (brass ●), Glaziers (bottle green ■), Dyers (plum ★),
  Assayers (chalk white ✦), Smiths (iron grey ⬟), Saddlers (tan leather ✚, youngest guild,
  split off from Tanners, makes the literal sash/wrap "team-colour carrier").
- Founding logic: the material ladder (Wood→Platinum) is guild TRADE vocabulary the sport
  borrowed, not vocabulary invented for the sport — guilds already graded goods this way
  before there was a Circuit. The sport itself started as a cheaper alternative to guild
  arbitration hearings (a dispute settled by a public contest between the guilds' own
  working monster-partners, refereed by the Assayers).
- The hardest question — what monsters get out of competing given they choose freely,
  per `BESTIARY.md` canon — answered as: a Circuit licence is this world's mechanism for
  legal personhood/standing, and it's the SAME mechanism every human tradesperson lives
  under (nothing is automatic here — a batch isn't graded, an apprentice isn't a master,
  a Tamer isn't licensed, until the record says so). Monsters aren't given a lesser
  separate system — they're let into the only system there is. Backed up by craft pride,
  material comfort, and consent-based breeding/Hall of Fame legacy.
- Tamers Apex win = the guilds declare the winning partnership "the Standard" — literally
  the reference everyone else gets graded against. Ties the game's ending to the grading
  theme rather than a generic "champion" framing.
- Proposed (not decided): a singular capstone venue "the Keystone" for the actual Apex
  title bout, distinct from the interchangeable Tamers-Apex-league grounds pool.
- Explicitly left open: wider geography (no map authored), guild chartering as a
  persistent stable mechanic (currently team colour is per-match-slot in `art.gd`, not
  persistent — flagged as a seam for `systems-designer`, not decided here).

See [[reference-art-gd-livery-colours]] for where the source-of-truth colours/badges live.
