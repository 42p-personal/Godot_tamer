# Art Bible — Guild Colours (Godot vertical slice)

**Binding spec for the assets in flight right now.** `docs/ART_THEME.md` is the approved
identity and the fuller doctrine (65-species, three-tier rendering, full 3D venue system);
`docs/ART_DIRECTION.md` and `docs/ARENA_DESIGN.md` are the arena theory it builds on. This
document is narrower and more operational: it binds the **12-species roster** and **5
painted leagues** actually shipping in `monster-tamer/scripts/art.gd`, against the **two
style wrappers currently generating art**. Where this file repeats those three, it is
because the wrappers need the rule stated at the point of use, not because it disagrees.

⚠️ **The vertical slice compresses ART_THEME.md's three-tier rendering system into two
tiers.** `art.gd`'s `creature_texture()` is one painterly side-on full-body PNG per
species — there is no separate 320×320 3/4-portrait tier and no pixel-art battle-sprite
tier yet. Everything in §2 below is written for that compression. This is a scope
decision, not a mistake, and should be named as one rather than silently drift from the
full doctrine.

---

## 1. The identity, and what it forbids

> **A sport built by hand, judged by trade guilds, fought by athletes who dress for the
> ring — not for war.**

Concretely, an asset fails on sight if it shows any of the following — this is the
one-line test a reviewer applies before reading further:

| forbidden | why | reject on sight if you see |
|---|---|---|
| War gear | Every monster is a sapient professional *choosing* to compete (`BESTIARY.md`); armour plate visually asserts "built for war," which the fiction explicitly denies | breastplate, pauldrons, shield, forged weapon, war banner |
| Birthright regalia | `CLAUDE.md`: class is emergent, never destiny — "never write... as if a species is destined for its class" | crown, throne, royal cape, anything implying rank by birth rather than earned title |
| Element colour-coding | Elements are removed from the game (`CLAUDE.md`, 2026-07-30) | glowing elemental aura, fire/ice/lightning motif tied to species identity |
| Recoloured hide | The creature's own material is its fixed identity across every team it's ever fielded on (§2) | fur/scale/feather tinted to a team colour instead of the removable carrier |
| A flat "asset viewer" render | HD-2D is a lens treatment, not a modelling style (`ART_DIRECTION.md`) — applies to venues; creatures get the equivalent warning below | perfectly even lighting with no material shading (fur, scale, metal) at all |
| Table-trap architecture | A horizontal member spanning a structure's full width reads as furniture, not architecture, from this camera (`ART_DIRECTION.md`) — see §7 | a lintel/canopy/capping course running unbroken across two supports |

---

## 2. Creature spec

**One asset per species: painterly, side-on, full body, transparent background.** This
single image stands in for both "portrait" and "in-battle actor" for the slice — it will
be seen large and still (bestiary/roster) and small and moving (a composited fight), so it
has to survive both jobs without a second tier to fall back on.

### Camera and framing

| rule | value | why |
|---|---|---|
| Angle | strict side-on, eye level | matches the arena backdrop's "low spectator-level... looking straight across the field" — creature and venue must share a camera height or the composite reads as two different renders glued together |
| Foot baseline | feet touch the same fixed baseline row (e.g. bottom N px) on **every** species regardless of body proportions | this is the load-bearing production detail that makes compositing onto the ground plane a paste, not a per-asset manual offset. `ARENA_DESIGN.md`'s footprint-depth lesson is the prop-side version of this same failure — get it right here for the same reason |
| Background | pure white, no cast shadow | clean alpha extraction |
| Light | warm, even, non-directional | must relight cleanly under whichever league's lamp colour it's composited into (`ART_DIRECTION.md`: per-league identity lives in the lamp) — a creature painted with a strong directional key will look pasted-in on every league whose lamp doesn't match it |
| Pose | one **ready** stance: bipedal-braced default, coiled/poised for a body plan that can't take a boxer's stance (`ART_THEME.md` §1, "what stays") | ⚠️ a single static pose per species cannot honour ART_THEME.md's class-keyed pose doctrine (§3 there) — that needs multiple rig poses this tier doesn't have. Accept the deviation for the slice, but the one pose must read as **neutral-ready**, never a class-suggestive action (no mid-cast, no mid-swing) — a fixed "casting" pose on a species a player later trains into a bruiser build would be a visible lie the same way a stored class would be |

### Gear grammar

Per `ART_THEME.md` §1: **a professional sport competitor, not a warrior.** Wraps on
striking limbs, a light singlet/harness, and exactly **one** brightly-coloured, obviously
removable team-colour object. Everything else on the creature — hide, fur, scale, feather —
stays in its own muted, canon material colour; the carrier is the *only* saturated thing in
frame.

### The carrier, per body type actually in the roster

⚠️ **This is the single biggest gap in the current wrapper (see §7) — "one team sash" is
correct for four of the twelve roster species and wrong or ill-fitting for the other
eight.**

| species | body type | carrier | why not a generic sash |
|---|---|---|---|
| Kongrath, Aegisox, Grivvel | Mammal | wrist/ankle wraps + waist or chest sash | direct fit — this is what the generic instruction already describes correctly |
| Crocmaw | Reptilian | wrist/ankle wraps + waist or chest sash | same, direct fit |
| Corvaan, Larkessa, Strixil | Avian | dyed leg-band, or a ribbon threaded through flight feathers | a chest sash sits wrong on a bird's silhouette and can obscure the wing line that reads "avian" at a glance |
| Scarabrute, Mantevoke | Insectoid | waxed thread lashed across the thorax, or a pigment dab directly on the carapace (a "race number" read) | nothing on a chitin body for cloth to tie to — a sash here will either float unattached or get rendered as glued-on cloth, which reads as a production error, not a design choice |
| Pyraxon (Draconic) | prestige | heraldic drape across the shoulder/back, more ceremonial in cut than the base sash | licence-gated species should visibly cost more to field (`ART_THEME.md`) |
| Tenebrae (Abyssal) | prestige | bioluminescent markings that *glow* in the team colour, in place of dyed cloth | a deep-world creature's version of "wearing colours" — light instead of fabric, and it is free worldbuilding already written into the doctrine |
| Titanrex (Mythical) | prestige | guild medallion / rank braid — status *earned*, not a crown | ties elevation to achievement, matching the class-is-emergent rule; a literal crown on the roster's one Mythical would directly contradict §1's "no birthright regalia" forbid |

**Recolour the carrier; never the creature.** A species must be identifiable as itself in
any team's colours — Kongrath in blue and Kongrath in violet are the same gorilla wearing
different cloth, not two different renders.

### Pass / fail

| check | pass | fail |
|---|---|---|
| Silhouette | reads as the same species across the whole roster's varied builds, at a glance | generic "fighter" body shape overrides the species' own proportions |
| Saturation | exactly one saturated object (the carrier); hide/fur/scale muted | tinted hide, or a second saturated prop (a coloured weapon, a bright eye glow unrelated to Abyssal's doctrine) |
| Gear register | athlete's kit only | any plate, forged weapon, or regalia that reads as rank-by-birth |
| Carrier fit | matches the body-type table above | a sash physically implausible on the anatomy (tied around a bird's throat, glued to a beetle's carapace with no thread) |
| Baseline | feet land on the shared baseline row | floating, or a foot below/above the row (breaks every future composite) |
| Pose | neutral-ready or the coiled equivalent | mid-action, class-suggestive |

---

## 3. Venue spec

**Two assets per painted league: a 16:9 painterly backdrop and a seamless top-down ground
tile.** `art.gd`'s `ARENA_LEAGUES = ["Wood", "Bronze", "Silver", "Platinum", "Tamers
Apex"]` — five of eleven leagues painted, every other league falls back **downward** to the
nearest painted one below it (deliberate: an unpainted high league borrowing a humbler
venue reads as "not built yet"; borrowing a grander one would misrepresent the player's
progress).

### Why these five, and why it still works

The grandeur ladder (`ART_DIRECTION.md`) is **cumulative** — every rung keeps what the rung
below had and adds its own. That means the five chosen leagues (rungs 0, 3, 5, 7, 10 of the
eleven-rung ladder) lose no rung's feature: each painted backdrop simply has to contain
*every* rung's addition up to and including its own. This table is the one the generating
agent needs and does not currently have (§7):

| league | rung | must show (cumulative, nothing above this line) |
|---|---|---|
| Wood | 0 | nothing — a field with a rail round it |
| *(Copper, Tin fall back to Wood)* | 1–2 | — |
| Bronze | 3 | + seat backs |
| *(Iron falls back to Bronze)* | 4 | — |
| Silver | 5 | + balustrade, brazier ring, columns |
| *(Gold falls back to Silver)* | 6 | — |
| Platinum | 7 | + planters, floor medallion, arches (replacing columns), canopy, pennants |
| *(Masters, Tamer Elite fall back to Platinum)* | 8–9 | — |
| Tamers Apex | 10 | + entablature, statues, emissive inlay, turrets, mosaic, ceremonial victory arch |

⚠️ **This is the load-bearing constraint of the whole venue spec and the wrappers do not
carry it.** Without it, a generation pass can plausibly over-decorate Bronze (giving it
Silver's columns) or under-decorate Apex (missing half its cumulative ornament) and nobody
would catch it by eye — the whole point of a stepped ladder is that a player can *name*
what's new, and that only survives if each painted league shows exactly its own cumulative
set, no more, no less.

### The three axes, and what the slice simplifies

- **Material** (`themes.ts`) — the league's name: Wood is timber, Silver is pale stone,
  Platinum is white metal and glass. Carries through unchanged; the five per-venue prompts
  already encode this correctly (parish ring / foundry town / civic hall / modern coliseum
  / open-to-sky capstone).
- **Grandeur** — the cumulative ladder above. **Currently unspecified in the wrapper — the
  single highest-priority fix in §7.**
- **Surface** — normally a *per-cup* floor choice independent of league material (sand,
  concrete, timber, flagstone, packed earth). ⚠️ **The slice collapses this**: one ground
  texture per league, standing in for that league's *own* signature surface (its "alloy
  floor" in `ARENA_DESIGN.md`'s language), not the multi-surface variety system. This is a
  correct simplification for five boards; note it so nobody later mistakes one ground
  texture for the finished surface system.

### What the backdrop is explicitly *not* responsible for

- **Cover/obstacles.** The floor stays empty in the painting; density-law cover
  (`ARENA_DESIGN.md`) is a separate layer, composited or built by whatever system owns the
  Godot fighting-ground. Do not let a generation pass invent benches, statues, or braziers
  standing *on* the floor — anything ornamental belongs to the stands/architecture, not the
  playing surface.
- **Crowd fill.** Fill is a gameplay variable (team fame + meta modifiers), never an art
  one (`ART_DIRECTION.md`). A static painted backdrop cannot host a *live* crowd at all —
  this is the same structural limit `ART_THEME.md` names for the legacy JPEG backgrounds it
  ordered retired. Treat every painted crowd as fixed at a generic "moderately attended"
  read and do not try to solve live fill on this asset type; it is an accepted interim
  limit, not a bug to chase.
- **Layout/arrangement signature** (SPINE/FLANKS/CHICANE/etc.) — floor-level, not
  backdrop-level; out of scope here.

### Camera note

⚠️ **A single static backdrop is, by construction, the "old" fixed camera** ART_THEME.md
retires for the full 3D venue system (establishing shot + a following tactical camera).
That's fine for a vertical slice — it is explicitly the interim tier ART_THEME.md names and
says to keep only until a real Godot venue exists for that league — but it must be
understood as interim, and these backdrops must not survive as shippable art once a full 3D
venue is built for the same league, for exactly the reason ART_THEME.md gives: two
contradictory art styles running side by side.

### Pass / fail

| check | pass | fail |
|---|---|---|
| Grandeur | exactly this league's cumulative set (table above) | any ornament from a higher rung, or a missing lower-rung feature |
| Composition | 16:9, floor fully empty, horizon near mid-frame | cluttered floor, cropped/skewed aspect |
| Architecture | no unbroken horizontal span across a structure's top | a lintel/canopy/capping course reading as a table (`ART_DIRECTION.md`'s named, three-times-rebuilt failure) |
| Fire/emissive | dim warm ember glow only | hot white bloom (measured failure — read as a headlight/lens flare against a muted palette) |
| Saturation | muted, consistent beside the other four painted backdrops | one league blazing noticeably louder than its neighbours (the exact Bronze-ground incident already on record) |
| Ground tile | seamless, fine grain, no baked one-off centrepiece | a floor medallion or gilt border baked into a *repeating* tile (structurally wrong — a one-off feature cannot live in a seamless texture) |

---

## 4. Palette discipline

Three systems, on three different objects, never allowed to collide (`ART_THEME.md`):

| system | carries | lives on | changes when |
|---|---|---|---|
| League material | which rung of the Circuit this is | arena stone, ground, lamp colour | never mid-match; fixed per league |
| Team colour | whose creature this is | sash/wrap/carrier, nameplate frame, UI accent | per match, per team |
| Status vocabulary | what condition a unit is in | status chip/icon, HP-bar tint | fixed game-wide, never reassigned |

### Critique of the shipped `TEAM_COLOURS` (`art.gd`)

```
guild blue   (0.24, 0.51, 0.85)
guild red    (0.83, 0.29, 0.26)
guild gold   (0.94, 0.72, 0.20)
guild green  (0.30, 0.66, 0.42)
guild violet (0.60, 0.36, 0.72)
```

**Mutual distinguishability, full-vision:** the five hues are reasonably spread (roughly
4°/45°/140°/215°/285° round the wheel) — no complaint here for a typical viewer at a glance.

⚠️ **Finding 1 — every team colour sits directly on a proposed status hue anchor.**
`ART_THEME.md` §3 proposes: hard control = pale yellow/white, DoT = poison green / burn
orange / bleed red / doom near-black-purple, utility debuffs = desaturated violet/grey,
buffs = cool blue/cyan. Laid against `TEAM_COLOURS`:

| team colour | collides with |
|---|---|
| guild blue | buff family (cool blue/cyan) |
| guild red | bleed (DoT-red) |
| guild gold | burn (DoT-orange) / hard-control pale-yellow family |
| guild green | poison (DoT-green) |
| guild violet | utility-debuff family (desaturated violet) |

That's five for five. Nobody cross-checked the team roster against the status proposal when
each was written, and the "three systems must never collide" rule these two documents both
state is currently violated by construction, not by accident. **This needs a fix before
status icons are authored, or every status chip in the game will read as "which team is
this" first and "what condition is this" second.**

Recommended direction (exact hex is a technical-artist production task, not this
document's): shift team colours into a **worn-fabric / dye register** — mid-tone, slightly
desaturated relative to the punchier, more saturated icon-glow register status chips should
use — so the *rendering treatment* (cloth sash vs glowing chip), not just the hue, does the
separating. Where a hue must be shared with a status family regardless, lean the team colour
away from that family's exact anchor (e.g. a green team should read teal-leaning, clearly
cooler than poison's leaf-green; a red team should read crimson/magenta-leaning, clearly
warmer than bleed's flat red).

⚠️ **Finding 2 — a 6th team is a guaranteed, not coincidental, collision.**
`team_colour(index) = TEAM_COLOURS[index % 5]` means team 6 is pixel-identical to team 1,
every time, by construction — this is stronger than the risk `ART_THEME.md` names ("two
teams *will* eventually collide on a similar colour," implying coincidence over a large
roster). Here it's exact and periodic. **The secondary, non-colour nameplate
differentiator `ART_THEME.md` already asks for (solid vs striped frame edge, or a small
guild-glyph) is not optional polish — it's required the moment a 6th concurrent team is
possible**, which for round-robin tournament fields is not a rare case. Flag to
`ui-programmer` as a hard requirement, not a nice-to-have.

⚠️ **Finding 3 — lower-priority, worth a note.** Guild green sits close to Bronze's
verdigris patina, and guild gold sits close to Platinum/Apex's white-metal-and-gilt
register. A green-team creature fighting at Bronze, or a gold-team creature at Apex, risks
its carrier blending into the architecture behind it. Lower priority than Findings 1–2
because scale and context (small foreground sash vs large background masonry) partially
protect it, but worth a visual check once both venue and creature art exist together.

**Recommendation:** do not ship the status-icon colour set (`ART_THEME.md` §3) against the
current `TEAM_COLOURS` without resolving Finding 1 — run both through a colourblind
simulator (deuteranopia/protanopia at minimum) before either is finalised, since red/green
is exactly the collision this palette risks twice over (guild red vs guild green directly,
and both against the DoT family).

---

## 5. UI direction

Only one UI asset exists in the current contract (`art.gd`: `title_texture()`), so this
section states the direction to build toward rather than critiquing an asset in flight.

- **Chrome material follows the league.** Once panel framing exists, it borrows the
  *current* league's material register from the venue tables above — a Wood-session panel
  reads timber-grain, a Platinum-session reads brushed white metal. Deferred until more than
  Wood/Bronze/Silver/Platinum/Apex have art to borrow from; the other six leagues fall back
  the same way the venues do.
- **Team colour is the UI accent**, not a fixed brand colour — buttons, active-tab
  indicators, and selection highlights pick up the player's current team colour. Reinforces
  "this is your team's interface" the same way the carrier reinforces "this is your
  creature" on the field.
- **Icons** — one authored set, bold and dark-outlined, shared between status chips in the
  HUD and (eventually) the equivalent battle-sprite icon. Sequenced after the creature
  "hand" (outline weight, palette discipline) is settled by the roster pass, not before.
- **Typography** — a sturdy display face for headers (ringside signage register), a clean
  sans for dense data (stat tables, standings). Stylise the frame, not the numbers.
- Do not build UI chrome against `TEAM_COLOURS` values that haven't cleared §4's Finding 1 —
  an accent colour that collides with a status hue in the HUD is a worse failure than the
  same collision on a creature, because the HUD is where the player is deliberately trying
  to read state fast.

---

## 6. Acceptance checklist

Run this against any single new asset in under a minute.

**Creature:**
- [ ] Side-on, full body, feet on the shared baseline row, clean alpha
- [ ] Exactly one saturated object (the team carrier); hide/fur/scale muted and unchanged from its canon description
- [ ] Carrier matches this species' body-type row (§2 table) — not a generic sash if the species is Avian/Insectoid/prestige
- [ ] No armour plate, forged weapon, or birthright regalia
- [ ] Neutral-ready pose (or coiled equivalent), not mid-action
- [ ] Same species recognisable if you mentally swap the carrier colour

**Venue (backdrop + ground):**
- [ ] 16:9, floor empty, horizon near mid-frame
- [ ] Ornament matches this league's row in the cumulative table (§3) exactly — nothing from a higher rung, nothing missing from a lower one
- [ ] No unbroken horizontal span across a structure's top (table-trap)
- [ ] Any fire/brazier element is dim warm, never hot white
- [ ] Saturation reads even beside the other four painted backdrops
- [ ] Ground tile is genuinely seamless and carries no one-off centrepiece motif

**Palette (any asset touching team colour):**
- [ ] Team colour distinguishable from the other four team colours at a glance
- [ ] Team colour distinguishable from every status-chip hue at a glance (currently: it isn't — see §4 Finding 1, do not treat this box as checkable until that's resolved)
- [ ] Nameplate/UI carries a non-colour secondary tell (pattern, glyph) wherever team colour alone identifies a team

---

## 7. ⚠️ What the in-flight wrappers get wrong

Highest-value section — act on this while generation is still running, before a full batch
needs re-rolling.

### CREATURE wrapper

1. **"Exactly ONE brightly coloured team sash" is a single, undifferentiated instruction
   for all twelve species, and it is wrong for eight of them.** Per §2's table: Avian
   (Corvaan, Larkessa, Strixil) needs a leg-band or ribbon, not a chest sash; Insectoid
   (Scarabrute, Mantevoke) needs a waxed thread or carapace pigment dab, not cloth with
   nothing to tie to; the three prestige species (Pyraxon/Draconic, Tenebrae/Abyssal,
   Titanrex/Mythical) each need a *distinct* carrier register (ceremonial drape,
   bioluminescent glow-not-dye, guild medallion/braid) that a generic sash instruction
   cannot produce and that materially matters — an Abyssal species dyed instead of glowing
   loses the one piece of free worldbuilding the doctrine gives it.
   **Re-roll instruction:** split the wrapper into body-type variants before generating the
   remaining 8 of 12 (Kongrath/Aegisox/Grivvel/Crocmaw are already correctly served by the
   sash instruction as written). Use the exact carrier language from §2's table per species.
2. **No shared foot-baseline instruction.** "Feet on the bottom edge" is directional, not a
   pinned row. Without a fixed baseline shared across all twelve renders, every asset needs
   a manual per-species Y-offset before it composites onto the ground plane — exactly the
   class of bug `ARENA_DESIGN.md` already paid for once on prop footprints.
   **Re-roll instruction:** add an explicit instruction — "feet touch the canvas's bottom N
   pixels on every image, regardless of the creature's proportions" — and spot-check two
   already-generated species side by side at the same canvas size before trusting the rest
   of the batch.
3. **No scale-consistency instruction across wildly different body sizes.** Kongrath (a
   gorilla) and Strixil (an owl) and Titanrex (a mythical apex species) have enormously
   different in-fiction sizes; "eye level" framing alone doesn't say whether each creature
   should fill the canvas consistently (letting gameplay scale them) or render at
   relative true scale (which would make Strixil nearly invisible next to Titanrex).
   **Re-roll instruction:** pin one explicit rule before generating further — recommend
   "each creature fills a consistent fraction of canvas height regardless of true size;
   relative battlefield scale is a compositing/gameplay concern, not an art one" — and
   confirm it's the rule actually being used on what's already generated.
4. **"Warm even studio light" isn't checked against the five leagues' lamp colours**, some
   of which (per `ART_DIRECTION.md`'s broader ladder, e.g. Tin's deliberately cold/colourless
   register) would clash with a uniformly warm-lit creature. Lower priority than 1–3 because
   none of the five *painted* leagues in this slice are the cold-register ones — but flag it
   now so it isn't rediscovered when a sixth painted league is added later.

### ARENA BACKDROP wrapper

1. **⚠️ Carries no grandeur/ornament specification at all — the single highest-priority
   fix in this document.** The wrapper is a generic camera-and-mood recipe ("painterly
   matte... tiered stands... muted desaturated palette") plus one evocative sentence per
   league. Neither source states *which specific cumulative features* belong on each of the
   five painted leagues (§3's table). Without it, there is nothing stopping Bronze from
   picking up Silver's columns, or Apex shipping without half its cumulative ornament — and
   nobody would catch it by eye, because the wrapper gives the generator nothing to check
   itself against.
   **Re-roll instruction:** append §3's cumulative table to the backdrop prompt, per league,
   explicitly — e.g. for Bronze: "seat backs behind the stands; nothing more — no columns,
   no arches, no statues." Do this before generating (or re-check) Silver, Platinum and
   Apex, which have the most cumulative ornament to get right.
2. **No table-trap warning**, and this is exactly the asset type most likely to trigger it —
   Platinum's canopy and Apex's ceremonial arch are both horizontal-over-vertical-supports
   structures, the precise shape `ART_DIRECTION.md` names as reading like a table from this
   camera angle three separate times.
   **Re-roll instruction:** add "no horizontal member may span unbroken across the top of a
   structure — break it at the supports, or crown each support separately" to the Platinum
   and Apex prompts specifically.
3. **No fire/emissive colour discipline.** Bronze's "brazier light" is exactly the element
   `ART_DIRECTION.md` already caught rendering as a blown-out white headlight against a
   muted palette.
   **Re-roll instruction:** add "any brazier/fire element renders as a dim warm ember glow,
   never a bright or white light source" to the Bronze prompt, and check it on generation.
4. **No explicit near-side exclusion.** "Entire foreground floor empty" implies the near
   stand is behind or absent from camera, but doesn't say so — an ambiguity worth closing so
   a generation doesn't accidentally paint a near-side stand with grandeur ornament that
   `ART_DIRECTION.md` reserves for the far side only (arches/entablature/canopy must never
   span the near trackway).
   **Re-roll instruction:** add "no stand or ornament visible in the near foreground; camera
   stands where the near stand would be" explicitly.

### ARENA GROUND wrapper

1. **"Muted" has no numeric anchor, and this exact failure has already shipped once** —
   `ART_DIRECTION.md` records Bronze's ground coming back at 3× house saturation and
   swallowing the cover on it, caught only by a procedural check (`check_ground_palette`)
   that doesn't exist for this generation route.
   **Re-roll instruction:** hold all five grounds side by side before accepting any of them;
   if one reads visibly punchier than its neighbours, it's the wrong one, not a stylistic
   choice — this is the same lesson, paid for once already, don't re-pay it.
2. **⚠️ A seamless tile structurally cannot carry a one-off cumulative feature, and Platinum's
   floor medallion (§3, rung 6/7) is exactly such a feature.** If "floor medallion" gets
   folded into the *ground texture itself* rather than treated as a separate decal, a
   seamless tile will repeat it across the entire floor, which is visibly wrong — a medallion
   is one object at one place, not a print.
   **Re-roll instruction:** the ground-tile wrapper must NOT attempt to include the floor
   medallion (or any other one-off cumulative floor feature); either omit it from this asset
   entirely for now, or explicitly split it out as a separate non-tiling decal for whoever
   builds the Godot floor layer. Do not let a generation pass "solve" this by baking a
   medallion into a tile — check the Platinum ground specifically for this once generated.
3. **No fire-colour discipline carried through** to any ground that might render brazier/ember
   glow directly in the texture (same fix as backdrop finding 3, applied here if relevant).

### Not a wrapper, but flag it now anyway

**`TEAM_COLOURS` (§4, Finding 1) should be resolved before the status-icon set is authored** —
both are early enough in the pipeline that fixing the team palette now is far cheaper than
discovering, after status icons ship, that every chip reads as "which team" before "what
condition." This isn't blocking the two art streams in flight, but it is blocking correctly
whatever authors status icons next.
