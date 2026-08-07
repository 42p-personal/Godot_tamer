# Deployment and formation — the UX spec

**2026-08-04. Draft, written to spec against the settled design — not yet reviewed by
mechanics/art/programming.** Answers the brief: design the placement interface, saved
formations, trade-off legibility, placement × positional-intent composition, scouting
integration and speed-of-use for `docs/AUTOBATTLER_DESIGN.md` §1 #1 / §2C / §5.

Every number below is **derived from the live constants in `monster-tamer/scripts/spatial.gd`**,
not invented — where I had to make a genuinely new UX call (grid snap increment, AoE-warning
radius placeholder, save-slot cap) it's marked ⚠️ and flagged for sign-off. Nothing here edits
`spatial.gd`, `tactics.gd` or `tactics_ui.gd` — this is the spec those files get built against.

---

## 0. Scope and assumptions

- **This screen positions an already-chosen roster of N monsters.** Picking *which* N monsters
  make the team (TeamPicker) is a separate flow and out of scope here — this doc assumes that
  selection already happened and hands this screen exactly `TEAM_SIZE_BY_LEAGUE` monsters.
- **This screen replaces `tactics_ui.gd`'s `Formation: Tight/Loose` team-wide dropdown**, and I'm
  recommending it lives *inside* The Read rather than as a separate screen (§8) — both for speed
  and because orders and placement are meant to compose (§5).
- **Target priority / mana policy / temperament stay exactly as built.** Nothing here touches
  those controls; this doc only adds the formation layer next to them.

---

## 1. The deployment zone — geometry, derived from `spatial.gd`

`AUTOBATTLER_DESIGN.md` §5 says the zone must span the **full ground height**, and the brief
says placement is free **anywhere in your own half**. "Half" needs a precise edge, because
`ARENA_BLUEPRINT.md` §2 fixed `DEPLOY_SEPARATION = 33.1` (flat, every team size) specifically so
the slowest unit closes in ≤12s — a player placing into that gap would quietly break the
guarantee the whole ground size argument depends on.

**Reading, flagged for the spatial owner to confirm:** your deployable zone is your side of the
ground, short of a neutral strip half the separation wide, centred on the midline:

```
center_x = GROUND_W(N) / 2
half_sep = DEPLOY_SEPARATION / 2        (16.55, constant)

Team A zone:  x ∈ [BODY_RADIUS, center_x − half_sep]     y ∈ [BODY_RADIUS, GROUND_H − BODY_RADIUS]
Team B zone:  x ∈ [center_x + half_sep, GROUND_W − BODY_RADIUS]      (mirrored)
```

| N | GROUND (W×H) | zone width | zone height | zone area | zone width as % of true half |
|---|---|---|---|---|---|
| 1 | 80 × 44 | 22.55 | 42.2 | 952 | 56% |
| 2 | 100 × 55 | 32.55 | 53.2 | 1,732 | 65% |
| 3 | 120 × 66 | 42.55 | 64.2 | 2,732 | 71% |
| 4 | 140 × 77 | 52.55 | 75.2 | 3,952 | 75% |
| 5 | 160 × 88 | 62.55 | 86.2 | 5,392 | 78% |

Worth noting on its own: because the neutral strip is a flat width, it eats a *bigger* share of
the zone at small `N` and a smaller share at large `N`. Placement freedom is proportionally
*most* expressive at 5v5 — exactly the team size where the blob problem is worst and where
`AUTOBATTLER_DESIGN.md` §5 most wants it fixed. That's not a coincidence I engineered; it falls
out of §2's constant already being flat.

**Minimum body clearance** between any two placed monsters (own side or, incidentally, the
opposing ghost zone if visible) is `2 × BODY_RADIUS = 1.8` units — the UI must never allow a drop
that overlaps another placed body.

---

## 2. The placement interface

### 2.1 Board rendering — my recommendation, flagged as an open call

**Recommend: a flat, top-down 2D schematic, not the 3D arena camera.** At 5v5 the zone is
62.55 × 86.2 world units; even filling a 1920px-wide panel that's ~25 px/unit, and a body radius
of 0.9 is an 18px-wide token — workable for dragging, but only if the view is a clean orthographic
top-down, not a perspective 3D camera where foreshortening makes the back of the zone harder to
place into precisely than the front. `tactics_ui.gd` is already built this way (flat panels, no
3D), so a schematic board is also the smaller integration step, not a new rendering mode.

⚠️ **Flagged for `art-director` / `ui-programmer`, not decided here:** an alternative is a locked
top-down orthographic camera on the real 3D scene (Total War-style deployment phase), which would
let the deployment screen show real creature models instead of icon chips. That's a nicer look and
a bigger build. My vote is schematic-first for the initial ship (precision and speed over
spectacle at a screen the player sees ~1,700 times), revisit once art wants a hero moment here.

### 2.2 The board

- **A faint ruler grid every 4 units** (visual reference only, not a hard snap) so a player can
  eyeball "my line is even" without measuring.
- **Drag-snap to 0.5-unit increments** while dragging — precise enough that two players' formations
  don't look sloppy, coarse enough that dragging doesn't jitter at screen-pixel resolution.
- ⚠️ **Optional alignment magnet** (my addition, flag to confirm it's wanted): while dragging within
  ~1.5 units of another placed ally's x or y, snap-align to it. Makes a clean line trivial to build
  by hand, which matters because a clean line is also the easiest shape to read on the board later.
- **Invalid-drop feedback**: a drop inside the neutral strip, outside the zone, or overlapping
  another body's clearance shows a red outline on the dragged chip and does not release it there —
  it settles at the nearest valid point instead of snapping back to the tray, so a slightly
  overshot drag never has to be redone from scratch.

### 2.3 The roster tray

A row of N portrait chips (same creature-visual pattern already built in `tactics_ui.gd`'s
`_creature_visual`) beside the board. Drag a chip onto the board to deploy it; drag a deployed
chip back onto the tray (or press Delete while it's selected) to undeploy it. Re-dragging an
already-placed chip repositions it — there's no separate "pick up" step.

### 2.4 Auto-arrange

A single **"Auto-arrange"** button fills every undeployed chip into a sensible default line —
this is a direct, thin wrapper around `Spatial.deploy_positions()`, which already computes exactly
this (evenly spaced across a band, staggered so it isn't a flat wall). It stops being the *only*
deployment mode and becomes the one-click fallback for a player who doesn't want to think about
it, which most of the 1,708 matches will want (§7).

### 2.5 Reading at every team size

The same board-and-tray widget at every size; only the zone dimensions and chip count change. At
1v1 the zone is small enough that the "line" almost degenerates to a single meaningful axis
(depth vs. the enemy — y placement barely matters with one body), and that's fine: a 1v1 deploy
step should feel appropriately trivial, one drag or one click of Auto-arrange, not padded out to
look as involved as a 5v5 read. The camera/view should fit the *current* zone plus a fixed margin
of context (the neutral strip and a sliver of the enemy zone), not a fixed pixel window that makes
a 1v1 zone look lost in empty space or a 5v5 zone feel cramped.

---

## 3. Saved formations

### 3.1 What gets saved, and why it isn't raw coordinates

⚠️ **The fiddly case the brief calls out — this is the section that matters most.**

A naive save (record `{monster_instance: (x,y)}`) breaks the instant the roster changes at all —
retire one monster, breed a replacement, or just field a different five for a different league,
and the formation silently has nothing to say about the new body. That's the trap: it looks like
it works because most saves get reloaded against the *same* roster, until the day it doesn't.

**Save a formation as N numbered slots, each carrying a position *and* a soft role tag captured
from whichever monster occupied it when saved** — not the monster's identity, its **role +
class** at save time (fields the game already computes per monster: `m.role`, `m.class_name_`).
A slot remembers "this was an Anchor/tank position," not "this was Aegisox."

This is a direct, one-layer-down reuse of a finding the project already made and then set aside:
`docs/TACTICS_BRAINSTORM.md` §2.3 argued formation slots should be named by **intent, not
coordinates**, because a coordinate doesn't survive an arena change. The user's later call (free
placement, raw coordinates) is right for the thing that gets *simulated* — but the insight isn't
wasted, it just moves down one layer: coordinates are what the fight uses, **roles are what the
save/load system uses to reattach a formation to a roster that has changed.** Best of both: the
mechanic stays simple (a formation IS a set of positions), the ergonomics get the station system's
real benefit (a formation survives a roster change) without reintroducing stations as a mechanic.

### 3.2 Save flow

- **"Save as new"** with a name field (free text, suggested default like `"Wedge — vs Bulwark"` or
  a timestamp if left blank) plus **"Update [current name]"** if a loaded formation was modified.
- ⚠️ Cap saved formations at a reasonable number (recommend **12** — enough for a distinct answer
  per rival gameplan tell plus a couple of house favourites, without becoming an unscrollable
  list) with rename/delete. Not a hard number, just needs *a* number so the gallery stays scannable.
- The gallery shows each formation as a small top-down thumbnail (the actual dot pattern, not just
  a name) plus the team size it was saved at and last-used date — so a player can tell at a glance
  "this was a 5v5 shape" before loading it into a 3v3 match and hitting the mismatch case below.

### 3.3 Load flow — the mismatch case, worked through

**Case A — same roster, same team size.** Trivial: positions load exactly, no matching needed.

**Case B — same team size, different roster (a swap).** Auto-assign by best-fit matching: for
each slot, find the available monster whose current role/class most closely matches the tag the
slot was saved with (highest-CON monster → the Anchor-tagged slot, etc.), preferring an unused
monster over a repeat. Show a one-line summary — `"4/5 slots matched by role, 1 reassigned"` — and
highlight any slot whose match is a low-confidence guess (no clear tank in the new roster) with a
small `?` marker. **Every auto-assignment stays fully drag-to-reassign before commit** — this is
an assist, never a lock.

**Case C — smaller team size (a 5-slot formation loaded into a 3v3 match).** Trim to N slots
rather than asking the player to manually pick every time (speed, §7): keep the slots nearest the
formation's own centroid first — this preserves the *shape's* character (a wedge stays a wedge,
just a smaller one) better than keeping front-line slots only, which would silently turn every
trimmed formation into a flat line. Show the trim (`"Loaded 3 of 5 slots — dropped the two
support positions furthest from centre"`) and let the player swap which slots survived before
committing.

**Case D — larger roster than slots.** Shouldn't occur under this doc's scope assumption (§0) —
team size is fixed by league before this screen opens, so the roster handed in is always exactly
N. Noted so a future roster-selection screen doesn't reintroduce it by surprise.

### 3.4 Starter presets

⚠️ **My addition, not in the brief — recommend building it, flagged for sign-off.** A blank canvas
is a bad day-one experience, and it undercuts the exact argument for free placement (§11's honest
answer). Ship **4 pre-authored starter formations** — Line, Wedge, Box, Split, the same four
`docs/TACTICS_BRAINSTORM.md` §7 already narrowed a "named shapes" system down to — as formations
that exist in every new save's gallery from the start, loadable and editable like any other. This
costs nothing extra to build (same save/load system, §3.1's role-tag machinery handles them like
any other saved formation) and gives new players a vocabulary — "I loaded Wedge and tweaked it" is
a much easier first formation-building session than "arrange five dots in an empty box."

---

## 4. Making the trade-off visible

The design already decided the trade (aura reach vs. AoE exposure, `ARENA_BLUEPRINT.md` §5) —
the job here is putting it on the board where a placement decision is being made, not in a
tooltip read once and forgotten.

### 4.1 Aura rings

Each placed monster carrying a team-support ability draws a **dashed ring** at
`Spatial.aura_radius(N)` (21.3 at 5v5) around its position, in a shared "support" colour distinct
from team-accent colours already in use (`tactics_ui.gd` uses blue for the player's side and red
for the rival — recommend gold, already used for headers/legibility text in that screen). Every
other placed ally currently inside at least one ring gets a small shield-tick glyph on its chip.
**Drag a monster out of the ring and watch the glyph disappear live** — the mechanic is the
demonstration, nothing has to be read to understand it.

⚠️ **Integration dependency, not mine to resolve:** this needs a data hook — "does this monster's
current loadout include a team-radius aura effect" — exposed per monster. Flag for
`ui-programmer`/gameplay to confirm what's queryable at deploy time (loadouts may not be finalised
until this screen, depending on build order).

### 4.2 Live spread readout

A single labelled bar beneath the board: **Formation: Tight ↔ Loose**, computed live from the
actual placed positions (RMS distance of each placed monster from the team's own centroid,
normalised against `Spatial.usable_radius(N)`, calibrated against the already-defined
`SPREAD_TIGHT (0.55)` / `SPREAD_LOOSE (0.95)` reference points as the bar's two ends) — plus a
one-line plain-language readout tied to the number: `"Formation: Tight — auras cover 5/5, area
damage risk high"` vs `"Formation: Loose — auras cover 2/5, area damage risk low."`

⚠️ **Flagged, not decided here:** whether the live sim's actual leash parameter is literally this
same computed value, or something the spatial layer derives independently once the fight starts,
is a mechanics call. The UX needs *some* live number so a shape reads as meaningful while the
player is still dragging; I've anchored it to constants that already exist so there's a real
chance it matches what the sim uses, but confirming that match is `godot-gdscript-specialist`'s
job once the deploy-to-leash handoff is built.

### 4.3 AoE cluster warning

When 2+ monsters land within a shared danger radius of each other, draw a **pulsing orange ring**
(slow pulse, motion-reduce-able, see §9) connecting them with a small burst glyph — not a colour
alone (§9 colourblind requirement).

⚠️ **The radius itself is a placeholder, not mine to set.** I don't have an authored "typical AoE
blast radius" from the ability pool to anchor this to. The nearest existing spatial constant in
the same family is `CONTAGION_RADIUS = 5.5` (status-spread range, explicitly unscaled — "body
spacing doesn't change because the world did," `ARENA_BLUEPRINT.md` §3), which is at least a
reasonable stand-in order of magnitude until game-designer/mechanics authors a real figure. Do not
ship the visual threshold without their sign-off.

### 4.4 Scouted ghost zone

Covered together with scouting in §6 — same visual system (dashed/hashed overlay, not colour
alone), placed on the mirrored far side of the board.

### 4.5 Legend, and the accessibility constraint that shapes all of §4

Every overlay above uses a **distinct line style or icon**, not colour alone:

| overlay | shape/pattern | icon |
|---|---|---|
| your aura reach | dashed gold ring | small shield-tick |
| AoE cluster warning | pulsing orange ring (slow, toggle-off) | burst glyph |
| scouted rival zone | diagonal hash fill | — |
| invalid drop | solid red outline on the chip itself | — |

A small always-visible legend strip (icon + one-word label, not a hover tooltip) sits under the
board so a first-time player doesn't have to guess what a dashed ring means.

---

## 5. Placement × positional intent — how they compose on screen

`AUTOBATTLER_DESIGN.md` §2B's five positional intents (`push` / `hold` / `wings` / `dive` /
`guard`) are a separate axis from where a monster starts (§2C). The brief asks how the screen
shows they compose — a monster deployed wide reads differently under each.

**Weld the intent picker to the board marker, not to a separate list.** Each deployed chip carries
a small 5-icon strip directly on it (same visual language as `tactics_ui.gd`'s existing per-order
selector, scaled down) — clicking cycles the five intents. Selecting `guard` prompts picking an
ally to guard, reusing the exact click-to-target interaction already built for `manmark` in
`_on_mark_rival`.

**Draw a predictive hint arrow from each deployed position, driven by (placement × intent)
together, updating live as either changes:**

| intent | on-board hint |
|---|---|
| `hold` | a small anchor glyph fixed at the deploy point, faint radius showing "stays near here" |
| `push` | a short arrow pointing straight at the enemy zone's centre |
| `wings` | an arrow curving out toward the nearer board edge, then forward |
| `dive` | a longer arrow piercing straight through toward the far (support) side of the enemy zone |
| `guard` | a line drawn from this chip to the guarded ally's chip |

Label this clearly as **illustrative, not simulated** — a short caption under the board
("hint, not a guarantee — a monster may still be overridden by an urgent event") — so it doesn't
imply more precision than `AUTOBATTLER_DESIGN.md` §3's "obeys unless something urgent overrides"
rule actually promises.

**Team default + per-monster override**, carrying forward the exact pattern already built for
target priority in `tactics_ui.gd` (a first `"__inherit__"`-style option meaning "use the team
plan," distinct from explicitly choosing a value): a team-wide default positional intent lives in
the same team-plan panel as Target Priority/Mana Policy, and each chip's 5-icon strip defaults to
"team default" until clicked, exactly mirroring the existing `per_monster_priority` prepend
pattern in `_add_team_monster_row`.

---

## 6. Scouting integration

Reuses the existing `GAMEPLANS` scouting read (`tactics.gd`) already surfaced in the "SCOUTED —
RIVAL TEAM" column, extended to place-specific information as scouting depth increases
(`docs/TACTICS_BRAINSTORM.md` §8's answered question: scouting has tiers, the top tier shows
everything):

| scouting depth | what shows on the board |
|---|---|
| none / low | nothing — rival roster chips only, exactly as `tactics_ui.gd` does today |
| mid | gameplan icon + tell text next to the board (already built), no positions |
| full | a dashed-hash **ghost zone** mirrored on the far side, showing the rival's likely opening shape |

At full scouting, extend each `GAMEPLANS` entry's existing `counter` text (already written, e.g.
*"Shield your back line, or lead with a durable front"*) with a **placement-specific line** shown
directly beside the board while the player drags — e.g. Zone's counter becomes *"...or spread
your line — Zone blankets clustered targets."* This is copy work on an existing data table, not a
new system: `GAMEPLANS` already carries `tell`/`counter`/`winCon` strings per entry.

Clicking a visible ghost-zone rival (or their portrait chip, as today) continues to set
`markedUnit` for the `manmark` order — no new interaction, same one carried over unchanged.

---

## 7. Speed of use across a ~1,708-match career

The single hardest constraint (`docs/FUN_ADDITIONS.md`'s measured career length). The whole
design above only earns its complexity if the *common* path is fast:

1. **The screen opens with the last-used formation for this team size already loaded and
   role-matched** (§3.3 Case A/B running automatically, not on request) — a returning player sees
   their team already arranged.
2. **Commit is available immediately, zero interaction required**, exactly as `tactics_ui.gd`
   already works (one "Commit and fight" button). A repeat matchup with an unchanged roster is a
   single click.
3. Only opening the formation gallery, dragging by hand, or reading the scouting overlay in depth
   is the "long path" — and it's opt-in, not the default flow, so the ~5-10 second common case and
   the occasional 30-60 second deliberate re-plan both exist without either taxing the other.
4. **"Reset to loaded formation"** undoes in-progress fiddling in one click, so a player who starts
   adjusting and changes their mind isn't punished for exploring.

---

## 8. Screen integration — this lives inside The Read

**Recommend merging into `tactics_ui.gd`'s existing screen** as a new panel (the board + tray +
saved-formations gallery) replacing the current `Formation: Tight/Loose` dropdown in the team
column, rather than a separate screen requiring extra navigation. Reasoning:

- Speed (§7) — one screen, one commit button, matches the flow already built.
- `AUTOBATTLER_DESIGN.md` §2C already frames formation as one of four tactic axes alongside
  target priority, mana policy and positional intent — it belongs where the others live.
- The scouting column is already adjacent (§6) — the board should sit where it can see that
  column, not on a separate screen the player has to remember and flip back to.

⚠️ Flagged for `ui-programmer`: this is a layout change to a script that already exists and works
(`tactics_ui.gd`'s `_build_team_column`), not a new screen — scoping and sequencing that edit is
their call, not mine to make unilaterally.

---

## 9. Accessibility pass

| requirement | how this design meets it |
|---|---|
| Keyboard only | Tab cycles roster chips; arrow keys move the selected chip (grid-snap increment, Shift+arrow for fine 0.1-unit adjust); Enter/Space picks up or drops; a bracket key cycles positional intent per chip; Enter on Commit fires the match. Saved-formation gallery is a standard focusable list. |
| Gamepad only | D-pad/left-stick moves a board cursor; A picks up/places the selected chip; shoulder buttons cycle roster and positional intent; Start commits. Gallery navigable by D-pad + A, same as any other list screen. |
| Readable at minimum font size | Formation names, role tags, the Tight/Loose readout and the legend (§4.5) are all text labels, never icon-only — font size follows the same scaling already used elsewhere in this screen. |
| Functional without colour alone | §4.5's table — every overlay uses a distinct line style or icon, not hue alone. Player-vs-rival distinction (currently blue/red in `tactics_ui.gd`) should also carry a shape or border-weight difference for this screen specifically, since it's the one screen where the two sides' territories are spatially adjacent and colour-only confusion is costliest here. |
| No flashing content without warning | The AoE cluster pulse (§4.3) is slow and must have a "reduce motion" toggle that switches it to a static outline. No other element flashes. |
| Subtitles | N/A — no dialogue on this screen. Any audio feedback (e.g. an invalid-drop sound) must be paired with the visual red-outline cue (§2.2), never audio-only. |
| UI scales at all resolutions | Board-to-pixel mapping recalculates on resize rather than being pixel-fixed, consistent with `tactics_ui.gd`'s existing anchor-based layout (`anchor_right = 1` etc.) — the board is a viewport onto world-unit coordinates, not a fixed-size image. |

---

## 10. Open flags — gathered in one place

- ⚠️ **"Own half" boundary (§1)** is my reading of the brief against `ARENA_BLUEPRINT.md` §2's
  separation guarantee, not a decision of record. Needs confirmation from whoever implements the
  deployment zone in `spatial.gd`.
- ⚠️ **Board rendering: schematic 2D vs. locked-camera 3D (§2.1)** — recommendation given, decision
  deferred to `art-director`/`ui-programmer`.
- ⚠️ **Alignment magnet snap (§2.2)** and **12-formation save cap (§3.2)** are new UX judgement
  calls with no prior anchor — flagged, not load-bearing, easy to change later.
- ⚠️ **Aura data hook (§4.1)** — needs a queryable "has team-aura effect" flag per monster at
  deploy time; sequencing depends on when loadouts are finalised relative to this screen.
- ⚠️ **Live spread-readout calibration (§4.2)** — anchored to existing constants for a plausible
  match to the real sim leash parameter, but that match is unconfirmed; needs
  `godot-gdscript-specialist` sign-off once deploy-to-leash handoff exists.
- ⚠️ **AoE cluster radius (§4.3)** is a placeholder (`CONTAGION_RADIUS`-adjacent, 5.5) standing in
  for a real authored figure. Do not ship without game-designer/mechanics providing one.
- ⚠️ **Starter presets (§3.4)** is my addition, not in the brief — recommended, not decided.
- ⚠️ **Screen merge into `tactics_ui.gd` (§8)** is a recommendation on an existing, working file —
  scoping that edit is `ui-programmer`'s call.

---

## 11. Report back

**Spec summary.** A schematic top-down board sits inside The Read (replacing the current
Tight/Loose dropdown), showing a deployable zone bounded by the ground's edges and a neutral strip
sized off `DEPLOY_SEPARATION` so free placement can't break the 12-second-close guarantee. Players
drag roster chips from a tray onto the board (0.5-unit snap, ruler grid, invalid-drop feedback,
one-click Auto-arrange). Positions save as named formations — but as **role-tagged slots**, not
raw monster bindings, so they survive a roster change. Each chip also carries its positional
intent (push/hold/wings/dive/guard), shown as a predictive hint arrow that updates live with the
placement.

**How the spacing trade-off is made visible.** Three live, on-board readouts, not tooltips: dashed
aura rings around support monsters (with a glyph on every ally currently covered, disappearing the
moment you drag them out), a live Tight↔Loose bar with a plain-language line ("auras cover 5/5,
area risk high"), and a pulsing cluster warning when monsters bunch inside a danger radius. All
three update as the player drags, so the trade-off is something you *watch happen*, not something
you read once.

**The saved-formation-mismatch answer.** Save role + class per slot, not monster identity.
Same-roster loads are exact; a changed roster gets auto-matched by best-fit role with a visible
confidence summary and full manual override; a smaller team size trims to the slots nearest the
formation's own centroid (preserving the shape rather than flattening it) and shows what was
dropped. This is the one design choice I'd call the load-bearing idea in this doc — it's a direct,
one-layer-down reuse of `TACTICS_BRAINSTORM.md`'s "intent survives, coordinates don't" finding,
applied to save/load ergonomics instead of to the mechanic itself.

**Is free placement worth it versus presets — honestly.** Yes, but conditionally, not
unconditionally. Free placement's real cost isn't the drag interaction (that's cheap) — it's
exactly the mismatch problem in §3.3, and if that's built badly, free placement genuinely is the
90-second tax the brief worries about, every one of ~1,700 matches. Built well (role-tagged slots,
auto-match, starter presets so day one isn't a blank canvas), the cost gets paid once per matchup
archetype during an occasional formation-building session, and the other ~95% of matches cost one
click. The thing that makes free placement worth its complexity is not the placement system
itself — it's the saved-formation system sitting under it. Ship them together, not placement
first and formations later, or the complaint the brief is trying to avoid will land in the gap
between the two.

**Files.** New: `G:\p42.uk\Monster-Tamer\docs\UX_DEPLOYMENT.md` (this doc). No source files
touched — spec only, per the task's ownership boundary.
