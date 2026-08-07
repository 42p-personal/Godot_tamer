# Arena — The Circuit Grounds
## "Guild Colours": every fight is a trade-yard assay, judged, not warred

**Level type**: shared spatial template — one design, twelve leagues, up to 24 interchangeable
5v5 boards at Platinum+. Not a level in the traditional sense (no player traversal) — this
document specs the space the autobattle sim fights in and the player watches.

---

## 1. Estimated Play Time

- Single fight: 15–30s sim time (median ~23s pre-suspension baseline, unvalidated post-rebuild)
  + establishing shot (~10s) + report screen (player-paced, no timer).
- A league's round-robin cup: 3–5 fights.
- Full ladder (Wood → Tamers Apex): outside this document's scope — see `docs/FUN_ADDITIONS.md`
  for career-length findings.

---

## 2. Layout Diagram — 5v5 ground (160×88), with accessibility fixes annotated

```
                                GROUND  W=160  H=88          [VENUE begins past this frame, §6]
   Y=88 ┌────────────────────────────────────────────────────────────────────────┐
        │████████████                                              ████████████│
        │██ DEPLOY  ██          ·  ·  ·  ·  ·  ·  ·  ·  ·  ·  ·      ██ DEPLOY  ██│
        │██   A     ██        ·        LOOSE (r33.4)         ·       ██   B     ██│
        │████████████       ·   ┌───────────────────┐          ·    ████████████│
        │        ▓          ·   │  ▓ cover, annulus │  ▓        ·       ▓        │
        │            ▓     ·    │  19.4–33.4  ▓      │           ·   ▓           │
   Y=44 │  flank margin    ·    │   ·  TIGHT(r19.4) ·│  X = centroid  ·  flank   │
        │  (52.45 @ 5v5)   ·    │  ▓   (moving,     ▓│                ·  margin  │
        │                   ·   │   frame-stream)    │           ·               │
        │        ▓           · │  ▓                 ▓│         ·         ▓       │
        │            ▓         └───────────────────┘        ·                   │
        │████████████               ·  ·  ·  ·  ·  ·             ████████████│
        │██ DEPLOY  ██                                             ██ DEPLOY  ██│
        │██   A     ██                                             ██   B     ██│
        │████████████                                              ████████████│
   Y=0  └────────────────────────────────────────────────────────────────────────┘
        X=0   flank(52.45)  DEPLOY A(11)  sep(33.1)  DEPLOY B(11)  flank(52.45)  X=160

  ── ACCESSIBILITY FIXES, WHERE THEY LIVE ──
  B1 (side ID)   : per-unit floor wedge + base ring, GROUND-PLANE, drawn every frame from
                   frames[].units[].pos/facing (stream C renderer). NOT an authored obstacle —
                   invisible to ArenaLayout, the density law, and cover placement.
  B2 (tier read) : HUD chip, SCREEN-SPACE, always-on. Lives in the renderer's fixed UI layer,
                   not the 3D scene — no ground-plane footprint at all.
  B3 (status)    : fixed-screen-size icon anchored above the unit + pulsing outline ring on the
                   unit mesh itself. Screen-space icon (stream C) + material/shader property on
                   the unit (not ground-plane either).

  ── LANDMARKS (incl. Assay podium) — placement rule, corrected this pass ──
  Landmarks sit OUTSIDE the LOOSE envelope by convention (r > 33.4 @ 5v5). At Wood/Tin the
  margin between LOOSE and the ground's SHORT edge collapses to 3.28 / 4.6 units — too tight
  for an undressed podium. FIX: podium (and all landmarks) are VENUE furniture, past the ground
  boundary, at every league — not ground furniture anywhere. See §7.
```

Deploy geometry, leash/SPREAD radii and the flank-margin numbers are `docs/ARENA_BLUEPRINT.md`
§1–§4, unedited by this pass — this document does not reopen the spatial blueprint, only adds
the accessibility layer and resolves the podium question on top of it.

---

## 3. Critical Path — the mandatory sequence of a fight

Every fight is the same five beats, band-scaled by grandeur (§6):

1. **Establishing shot** (venue exterior, ~10s at higher leagues, a cheap static pan at Wood) —
   `ART_THEME.md` §2.
2. **Deploy** — both teams appear in their bands, `separation = 33.1` apart (`ARENA_BLUEPRINT.md`
   §2), tactical camera settles to `LENS.BOARD`.
3. **Engagement** — the sim runs; camera follows the moving centroid `X`; SPREAD/leash keeps the
   fight inside the annulus (§2 diagram) regardless of team-size ground scale.
4. **Resolution** — a side is reduced to zero survivors, or `MAX_DURATION` is hit.
5. **Report** — hard cut to `report.tscn`; Assay verdict rendered (§5).

There is no player-navigable path through the arena — "critical path" here means the fixed
narrative/camera sequence above, not a traversal route.

## 4. Optional Paths

None on the ground itself (no exploration, no secrets — this is a spectator sport, not a
dungeon). The nearest equivalent is **league progression**: which leagues a player chooses to
enter, and whether they scout a rival's gameplan before committing (`CLAUDE.md` tournaments
section) — that's a meta-game choice, out of this document's scope.

---

## 5. Narrative Beats — the Assay-void rule and the per-band emotional arc

- **The Assay-void rule**: nothing on the ground narrates the fight while it's live. The Assay
  Table (`WORLD_GUILDS.md`) judges only what already happened — no live commentary geometry, no
  in-fiction hazard, no rules-lawyering prop. The arena is silent of narrative machinery *during*
  play; all narrative weight lands in the establishing shot (before) and the report (after).
- **Per-band emotional arc**: Wood is a bare field, a first assay with nothing at stake but
  standing; the arc climbs through Copper→Gold's guild-material grandeur ladder
  (`ART_DIRECTION.md`'s eleven-rung table) to Platinum+'s interchangeable "grand circuit" pool,
  where the emotional register shifts from *proving* to *performing* — the fight itself doesn't
  change shape, but the venue around it insists the stakes have.
- **Officials**: a centralised Assayer officiates every match (not a per-league cast) — consistent
  with `WORLD_GUILDS.md`'s Assay Table being the one body that chairs grading across every guild.
  An Announcer role exists for presentation (crowd-facing) but is not a rules authority — the
  Assayer is.
- **Gong, not bell**: the start-of-fight cue is a struck gong (trade-yard signal register, not a
  sporting bell) — ties the world's "guild-built trade-yard" origin (§6) into something the
  player actually hears at the one moment per fight that matters for pacing.

## 6. World Lore — guild-built trade-yards

The arenas are, in-fiction, **guild-built trade-yards** repurposed as competition grounds, judged
by a centralised Assayer body rather than any single guild — this is why the material identity
per league (`ART_THEME.md`'s league-material system) reads as *what a trade guild would grade*
(Wood, Copper, Tin, Bronze, Iron, Silver, Gold, Platinum), not as generic fantasy dressing. The
ground itself is always the same shape (this document's job); the guild colours worn by
competitors and the material the yard is built from are what change.

---

## 7. Spatial Layout — ring inlay, banner poles, podium, tier-reading mechanism

- **Ring inlay**: a static floor decoration concentric with the ground's centre, marking where
  the fight is *meant* to happen (roughly the TIGHT/LOOSE annulus). Lowest render layer — the
  per-unit B1 indicators (§2) draw on top of it as part of normal unit rendering, same as they'd
  draw over bare ground; no z-fighting or occlusion risk, since the inlay carries no collision
  and B1 indicators are UI-adjacent geometry, not physical props.
- **Banner poles**: two per side, VENUE-side (past the ground boundary, §2 diagram), carrying
  team-colour banners — reinforces "who's who" (`ART_THEME.md` §3) from the establishing shot
  without adding ground-plane clutter.
- **Assay podium**: **moved to VENUE furniture at every league**, resolving the Wood/Tin
  collision found in this pass. Undressed at Wood/Tin (bare stone block), dressed progressively
  per the grandeur ladder at higher leagues — consistent with "Assay-void" (§5): the podium is
  where the verdict is READ, after the fight, never a live in-ground fixture.

  ⚠️ **The measured collision this decision is answering — keep verbatim, someone will ask why
  the podium isn't on the ground.** Read directly from `arena_layout.gd`: the cover annulus and
  the "landmarks sit beyond LOOSE" convention are both radii measured from ground centre, and
  the ground is far narrower in Y than X at small team sizes (`usable_radius = 0.4 × H`, and `H`
  is only 44/55 at Wood/Tin vs. 88 at 5v5). The margin between the LOOSE envelope and the
  ground's short (Y) edge works out to **3.28 units at Wood (N=1: usable_radius 17.6, loose_r
  16.72, half-H−EDGE_MARGIN 20.0) and 4.6 units at Tin (N=2: usable_radius 22.0, loose_r 20.9,
  half-H−EDGE_MARGIN 25.5)** — an order of magnitude tighter than the long-axis flank margin at
  the same leagues (16.45 / 25.45). No undressed podium of any real footprint fits there without
  either overlapping the cover-placement annulus (where `ArenaLayout.generate()` actively rolls
  obstacles) or breaching `EDGE_MARGIN`. Moving the podium to the venue side of the ground
  boundary resolves this by construction, matching `ARENA_BLUEPRINT.md` §6 ("the VENUE begins
  past the ground entirely") and `ART_THEME.md` §2's fighting-ground/venue split — no new
  exclusion-zone logic was added to `arena_layout.gd` for a single fixture.
- **Tier-reading mechanism**: two independent channels, deliberately not one dressed up as two
  (per `ACCESSIBILITY.md` finding #4/B2) —
  1. Lamp temperature 2700K→4200K + banner-pole material, existing weak-but-real in-fiction cue.
  2. **NEW, this pass: an always-on HUD chip naming the league**, screen-space, comparison-free —
     the accessible primary channel; the lamp/material pairing becomes flavour, not the only read.

---

## 8. Accessibility — the three blocking fixes, integrated

### B1 — side identification at 20–40px (was: colour-only, 3/8 team liveries collapse under CVD)
- **Fix**: persistent ground-plane per-unit indicator — a facing wedge + base ring, shape/orient
  distinct per side (e.g. wedge points toward the enemy front line; ring shape or dash pattern
  differs A vs. B, not just colour).
- **Owner**: renderer (stream C, `arena_3d.gd`) — reads `frames[].units[].pos`/`.facing`, both
  already emitted (`BUILD_CONTRACT.md` §2). **No sim change required.**
- **Nice-to-have**: put the `TEAM_BADGES` glyph (`art.gd`) on the indicator itself, so it carries
  side AND team identity in one read, at the camera distance that actually matters (not the 9px
  nameplate).
- **Spatial-rule check, measured, keep verbatim.** `ArenaLayout.generate()` places cover as
  *static, authored-once* obstacles, tracked in a fixed `obstacles` array that both the density
  law (`AREA_PER_PIECE = 300`, `DENSITY_SAFETY_FACTOR`) and the 180° symmetry check enforce
  against. The proposed side indicators are *per-unit, per-frame* draws sourced from
  `frames[].units[].pos/facing` — a different pipeline entirely (stream C's live renderer, not
  stream C's one-time layout generator). They never get appended to `obstacles`, so they never
  count against the density ceiling, never need a symmetry partner, and can't be "cover" in any
  sense `spatial_sim.gd`/`spatial_ai.gd` reads as blocking or occluding — they're paint, not
  collision. No rule violation, and no code path exists by which one could occur later without
  someone deliberately wiring a per-frame draw into the `obstacles` array, which nothing in this
  design calls for.

### B2 — colourblind venue-tier read (was: lamp temperature, one weak perceptual channel)
- **Fix**: discrete HUD chip naming the league, always on screen, comparison-free (§7). Backup
  cue (lamp/banner material) stays as flavour.
- **Owner**: renderer, screen-space UI layer. **No ground-plane footprint, no sim change.**

### B3 — status legibility at silhouette scale (was: flat colour + 4-char text at 8px)
- **Fix**: pulsing outline ring on the unit mesh (shape/motion, not colour-alone) + a status icon
  anchored above the creature at **fixed screen size** (does not shrink with camera pull-back).
- **Reuse, not reinvent**: `ART_THEME.md` §3's status icon-shape/hue-family grouping (hard
  control / DoT-by-kind / utility / buff) is the spec; `arena_view.gd`'s `STATUS_META` table
  (hue + abbreviation, already built in the disconnected view) is the base data to port onto the
  live screen, per the finding in `ACCESSIBILITY.md` §1.3/§8 item 6.
- **Owner**: renderer, reads `frames[].units[].statuses` (already emitted). **No sim change.**

**On the sim change question, stated explicitly per the brief's requirement**: none of the three
fixes need a new field from `BUILD_CONTRACT.md` §2. `pos`, `facing`, `hp`, `statuses`, `intent`,
`reason`, `attribution` already cover every input B1–B3 need. The contract is deliberately hard
to change and nothing here justifies reopening it.

---

## 9. Systems Findings

- **Assay verdict is COSMETIC.** It must source its text from `report_ui.gd`'s existing
  `_narrative(analysis, dec, id_of, roster)` (turning-point / first-death causal string) — never
  a parallel, separately-authored description. Two descriptions of the same fight is exactly the
  kind of drift `ACCESSIBILITY.md`'s own opening warns against generally, applied here to
  narrative text instead of colour.
- **No per-league hazards.** Confirmed consistent with the Assay-void rule (§5) — the ground
  never narrates or interferes live; `arena_layout.gd`'s `KIND_TABLE` stays cover-only
  (barrel/crate/planter/low_wall/pillar), no hazard kind to be added.
- **Iron debt garnish is real**, `DEBT_RATE = 0.10` — the studio owner's chosen rate, lower than
  the 0.15 originally proposed. Economy-owned constant; this document notes it only because it's
  the one systemic consequence a player can feel tied to a specific league band (Iron), same as
  the grandeur ladder ties visual escalation to band.

---

## 10. Asset Manifest

**Six base meshes × four material bands + eight guild decals** — NOT eleven tier variants. The
four material bands cover all twelve leagues by grouping (per-league table in
`arena_layout.gd`'s `LEAGUE_MATERIAL` for Wood–Gold, shared `GRAND_CIRCUIT_PALETTES` pool for
Platinum+). Guild decals (8, one per founding guild, `WORLD_GUILDS.md`) carry team/guild identity
independent of league material — never mixed into the same texture channel as league material or
status colour (`ART_THEME.md`'s three-systems-never-collide rule, §0).

---

## 11. Pacing Chart

```
intensity
  high │                    ╱‾‾‾╲___resolution
       │                  ╱          ╲
  med  │        engagement            ╲__report (player-paced)
       │       ╱                         
  low  │established─deploy                        
       └────────────────────────────────────────────────► sim time
        0s      10s        ~12s(melee contact)    15-30s   report
```

- **Establishing shot** (0–10s): low intensity, grandeur payoff, no combat.
- **Deploy** (~10s): low, teams appear, gong (§5).
- **Opening close** (10–~22s from whistle, ≤12s worst case per `ARENA_BLUEPRINT.md` §2): rising —
  reach-≥33.1 lines already engaged at deploy, melee closing.
- **Engagement** (variable): the fight's real intensity curve — owned by the sim/balance
  discipline, not this document; `OPENING_MIT_BONUS` (flat +20%, 30s hold/15s fade) delays the
  first-blood spike per `ARENA_BLUEPRINT.md` §2/§10.
- **Resolution → Report**: hard drop to player-paced review.

## 12. Music/Audio Cues

- Gong strike at deploy → engagement start (§5).
- No live narrative audio during the fight (Assay-void rule, §5) — ambient crowd/venue only,
  scaled by the grandeur ladder.
- Report screen: no time pressure, ambient only.

---

## 13. Cross-Level Dependencies

- `design/levels/town.md` — **UNRESOLVED.** The Town lives in
  `monster-tamer/scripts/ui/town_ui.gd`, not a level document, and nobody has designed it as a
  level. The Town→Arena transition is a **hard cut** (confirmed elsewhere in the studio's
  decisions) — this document does not invent Town content to fill that gap.
