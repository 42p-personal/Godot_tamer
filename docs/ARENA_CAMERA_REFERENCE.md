# Arena camera — the reference the user picked

**2026-08-04.** The user supplied a screenshot of **Ludus Magnatus: Gladiator Manager Simulator**
(Steam) and said:

> *"i think our arena would look alot better in this kind of style/camera angle, maybe more zoomed
> out, bigger arena etc but for some inspiration i like this view alot for our game"*

---

## ⚠️ THIS MOSTLY CONFIRMS EXISTING DIRECTION — WHICH IS THE USEFUL FINDING

`ART_DIRECTION.md` already specifies **"Fixed camera, ~38° elevation, 26° fov (long lens — short
ones bow a 58-wide arena)"**. The reference shot is within a few degrees of that. So this is not
a change of direction; it is **proof the written direction was right and has never been built**.

Do not treat this as a new art brief. Treat it as a reason to finish the one already written.

## What the reference shows

| element | what it does | our status |
|---|---|---|
| **Elevated 3/4 view into an enclosed bowl** | you see the FAR wall and the stands wrapping behind it — the arena reads as a *place*, not a plane | `ART_DIRECTION.md` §Camera, unbuilt |
| **Zoomed OUT — units are small** | the ARENA is the subject; the fight is a pattern you read, not a set of portraits | ⚠️ **the real delta** — see below |
| **Cover as stone blocks on open sand** | scattered pillars break sightlines without breaking the read | `ARENA_DESIGN.md` density law, ours already generates these |
| **Floating nameplate + HP bar per unit** | who is who, at a glance, when bodies are 20px tall | ⚠️ **required by the zoom-out, not optional** |
| **Roster strip along the top, with power ratings** | the full cast is legible before and during the fight | we have `TEAM_BADGES` / `TEAM_COLOURS` in `art.gd`, unused here |
| **"Team A vs Team B" header with guild badges** | the sporting frame | `ART_THEME.md` "Guild Colours" — exactly this |
| **Flat sand floor, no elevation** | verticality is cover and ornament only | ⚠️ matches our **NO ELEVATION** rule precisely |

## The actual delta: zoom out, and pay for it in labels

⚠️ **Zooming out is not a camera tweak in isolation — it costs legibility and must buy it back.**
At the reference's framing a creature is a small silhouette. That game compensates with a
persistent nameplate and HP bar over *every* unit, plus a roster strip. Ours would have to do the
same, or the player loses track of which body is theirs.

That is not a cost — it is the **fix for a problem this project already measured**. `FUN_ADDITIONS.md`
found that the unit of attention in a 5v5 must be the SQUAD, not the monster. A camera that makes
individual creatures small and the formation large is the camera that expresses that finding.

⚠️ **And it interacts with a decision already taken.** `ARENA_BLUEPRINT.md` §2 fixes
`DEPLOY_SEPARATION` at ~33 units regardless of board width, so extra ground becomes *flank room*
rather than a longer walk. Measured consequence (`scripts/_probe_coverage.gd`): the fight occupies
~21% of a 160-wide board on the approach axis, and lateral span runs 34–49% depending on orders.
**So "bigger arena" must mean a bigger VENUE, not a bigger engagement** — otherwise the fight
becomes a small knot in a large empty field, which is worse on this camera, not better.
`ART_DIRECTION.md` already separates the two numbers (venue vs ground); this is why.

## What to build, in order

1. **Frame the ground, not the units** — fit the camera to the ground's bounding box plus a
   margin, at the ~38°/26° already specified.
2. **Nameplate + HP bar over every unit**, always on. Team colour AND badge (`art.gd:team_identity`)
   — ⚠️ colour alone is never sufficient ID, and `index % 8` makes collisions exact.
3. **Enclose the bowl** — far wall and wrapping stands, so the horizon is architecture.
4. **Roster strip** top-of-screen, both teams, with the intent label the tree already emits
   (`BUILD_CONTRACT.md` §2: `intent` / `reason` / `attribution`).
5. **Guild-badge VS header** — `ART_THEME.md` has the identity system authored already.

⚠️ **Nothing here needs new simulation work.** The frame stream already carries position, facing,
hp, statuses, intent and attribution per unit per tick. This is a renderer and camera task
(`scripts/ui/arena_3d.gd`, stream C in `BUILD_CONTRACT.md` §3) — the sim is not involved and must
not be edited for it.
