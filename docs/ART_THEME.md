# Art theme — Guild Colours

⚠️ **CORRECTED 2026-08-03 — THE "0 GENERATED" FIGURE IN THIS FILE AND IN `ART_PIPELINE.md`
WAS WRONG.** Counted from the filesystem: **30 of 390 battle sprites already exist** — the
complete Mammal group (Kongrath, Aegisox, Maneleo, Grivvel, Ursath), all six frames each. So the
pilot everyone keeps proposing has already been run once, and its output is on disk.

⚠️ **THAT IS THE SEVENTH THING THIS REVIEW HAS FOUND ALREADY BUILT WHILE DOCUMENTED AS
MISSING**, after per-unit speed, the leash, `spreadStatus`, the cohesion/predation archetype
grid, per-ability `range`, and the measurement that speed does not fix chasing. **Count the
files before believing a count in prose.**


**Read this before touching a species portrait, a battle sprite, an arena, a theme, or a
menu.** `docs/ART_DIRECTION.md` and `docs/ARENA_DESIGN.md` remain the working theory for
*arenas specifically* — this document is the layer above them: the one identity that
creatures, arenas, effects and UI all answer to, written for the move to **Godot 4.7.1,
desktop, Forward+**. Where this file and the older two disagree, THIS FILE WINS for
anything that isn't arena-layout mechanics (density law, deployment bands, mirroring) —
those stay exactly as specified.

⚠️ **Two of the three source documents are half scar tissue and this document says which
half.** `ART_DIRECTION.md`'s three axes (material/surface/grandeur) and `ARENA_DESIGN.md`'s
signature system (§4) are NOT scar tissue — they are the load-bearing part of the existing
direction and this document builds directly on them. What *is* scar tissue: the fixed
board-fitted camera, the "props can't run deep" prop-card rule, and the assumption that
grandeur must be visible *during* play. Those go. See §3.

---

## 0. The theme in one line

> **A sport built by hand, judged by trade guilds, fought by athletes who dress for the
> ring — not for war.**

Name it **Guild Colours**. Two things are doing the naming work on purpose:

- **Guild** — the Circuit is already the game's own name for its ladder (`docs/BESTIARY.md`:
  "the Tamer Circuit — the ladder of licences from Wood to Tamer Elite"). Leagues are named
  after *materials a trade guild would grade* (Wood, Copper, Tin, Bronze, Iron, Silver, Gold,
  Platinum), and the top three (Masters, Tamer Elite, Tamers Apex) are *titles a guild
  awards*, not materials — the ladder is a craft apprenticeship wearing a sports league's
  clothes. This is already true of the fiction and of `ART_DIRECTION.md`'s arena axes; this
  document extends it to creatures and UI, which currently don't know it exists.
- **Colours** — literally: every competitor wears their team's colours into the ring, the
  way a real athlete does. This is the single idea that makes the whole document cohere,
  because it is simultaneously a *readability* mechanism (§4), a *creature design*
  mechanism (§2) and a *venue dressing* mechanism (§3) — one idea, three payoffs.

### Why this suits THIS game and not a generic fantasy skin

Every monster in this bestiary is **written as a sapient professional choosing to compete**
(`BESTIARY.md`'s canon note: "a Tamer is a *partner*, not an owner... nobody is forced into
the ring"). That is an unusual thing to say about a monster-taming game, and the art has
never caught up to it — the current portraits dress competitors as **warlords and armoured
beasts** (Maneleo in a pharaoh's cape and gilded regalia, Aegisox in plate), which reads as
"these are war-monsters" and quietly contradicts the sport-not-war fiction the writing
already committed to. ⚠️ **This is the single biggest pivot this document asks for**, and
it's a redirect, not a teardown — see §2 for exactly what changes and what doesn't.

### The three-tier rendering system is a feature, not an inconsistency

The game already renders each creature at **three different fidelities for three different
jobs**, and that split should be named and kept on purpose rather than treated as drift to
reconcile:

| tier | spec | job | keep or change |
|---|---|---|---|
| **Portrait** | 320×320 painted, one 3/4 hero pose | Ranch/Market/Bestiary/Hall of Fame — seen large, still, and often | KEEP the fidelity, REDIRECT the costuming (§2) |
| **Battle sprite** | 128×128 pixel art, strict side profile, 6 frames | the field — seen small, moving, in a crowd of ten | KEEP entirely — spec is right, just unbuilt (0 generated, see §6) |
| **Arena** | procedural 3D mesh, HD-2D lens grade | the venue the fight happens in | KEEP the system in `ART_DIRECTION.md`, RETIRE the fixed camera (§3) |

Games that do this well (Hades' painted portraits over real-time low-poly bodies; Slay the
Spire's painted cards over a flat battler) all hold one thing constant across fidelities:
**the same design reads as the same character at every zoom level.** `BATTLE_SPRITES.md`
already enforces this correctly (generate every pixel sprite by referencing its own
portrait, not a fresh description) — that discipline is the thing to protect above all
else as more tiers get built.

### Stylisation level, stated plainly

- Portraits: **painterly-readable realism** — detailed rendering, real material shading
  (fur, scale, metal), dramatic action pose. Not photoreal, not cel-shaded flat.
- Battle sprites: **bold flat pixel art**, dark clean outline, readable at 40px, limited
  palette per sprite. Per `BATTLE_SPRITES.md` — no change.
- Arenas: **stylised-industrial HD-2D** — smooth-shaded procedural primitives with
  deliberate bevels (never a raw 90° edge — `ART_DIRECTION.md`'s standing rule), warm key +
  cool bounce, house saturation ≈0.21, DoF/bloom/split-tone as a *lens* treatment over
  simple geometry, not a modelling style. No change to the recipe — change to what it's
  aimed at (§3).
- UI: **guild paperwork and ringside signage**, not a sci-fi dashboard. New direction — the
  current UI has none (§5).

### The palette discipline — three colour systems that must never collide

This is the rule every other section depends on, so it's stated once, here, first:

| system | carries | lives on | changes when |
|---|---|---|---|
| **League material** | which rung of the Circuit this is | arena stone, ground, lamp colour | never mid-match; fixed per league |
| **Team colours** | whose creature this is | sash/wrap/banner (creature), nameplate frame, UI accent | per match, per team |
| **Status vocabulary** | what condition a unit is in | status chip/icon, HP-bar tint | fixed game-wide, never reassigned |

⚠️ **These were designed as one axis once before and it went wrong** — `ART_DIRECTION.md`
records exactly this mistake for material/surface/grandeur ("collapsed once and every
league got the same bowl in a different colour"). The same failure mode is available here:
if a team's colour is allowed to recolour arena stone, or a status colour is reused as a
team colour, the player loses a reading channel to a coincidence. Keep the three systems on
three different objects, always.

---

## 1. Creature direction — "competitors, not monsters"

### What stays

- The **bipedal athlete stance** already used almost everywhere a body plan allows it
  (Kongrath's raised-fists stance, Maneleo's roar, Titanrex's braced roar) is exactly right
  and should be the *default* silhouette read across all 65: weight low, guard up, ready to
  move. Where a body plan can't take a boxer's stance (Aquatics with no legs, most
  Insectoids, a drifting Maelurk), the existing portraits already substitute a **coiled/
  poised** equivalent — keep that, it's the correct adaptation, not an exception to police
  out.
- Rendering fidelity and pipeline (`ART_PIPELINE.md` Route B, portrait→pixel reference
  chain) — unchanged.
- Individual story markers — scars, trinkets, a tangle of stolen jewellery (Corvaan), runic
  shell etching earned over centuries (Tortavos) — these are *biography*, authored per
  monster's written backstory, and they stay exactly as rich as they are.

### What changes: gear reads as SPORT, not WAR

⚠️ **A monster's gear must never claim rank, class, or destiny it hasn't earned in play.**
This isn't just an aesthetic preference — it's downstream of a standing rule already in
`CLAUDE.md`: *"Class is emergent... any species can in principle train into any class...
Never write flavour text or UI as if a species is destined for its class."* Gilded warlord
regalia on Maneleo *visually* asserts he is a king/leader-class monster from birth, which
the design explicitly forbids the *text* from asserting. Bring the art in line with the
rule the writing already follows:

| register | reads as | examples in the current set | verdict |
|---|---|---|---|
| **war armour** (plate, pauldrons, warlord cape/crown, breastplate) | born to command, built for war | Maneleo's full regalia + trailing cape | **redirect** — becomes a *worn* champion's sash/mantle (an earned title, re-drapeable, not forged-on armour) |
| **athlete's kit** (wrist/knuckle wraps, a fighter's harness or belt, tape, a sash) | trains and competes, same as the player's own tamer does | Kongrath's wrapped fists and leather harness, Aegisox's practical hide-plating | **keep as the template** — this is what "competitor" already looks like when it's not trying to be a king |
| **biography markers** (scars, trinkets, runic etching, bioluminescence) | this specific individual's history | Corvaan's stolen jewellery, Tortavos's runes | **keep, unconditionally** |

The fix for Maneleo specifically: the mane, scars, and proud bearing all stay — they're
character. The pharaoh's cape and gilded crown-like regalia become a **sash/mantle he has
personally earned on the Circuit** (visually closer to a champion's belt draped like a
cape than to a monarch's vestments) — same silhouette beat, different claim.

⚠️ **This is a targeted redirect on a minority of the 65, not a teardown.** Kongrath,
Aegisox, and Titanrex (sampled while writing this) already sit comfortably inside "athlete's
kit." Before committing art-service budget, run a full visual audit of all 65 portraits
against this table (§6, step 3) — do not assume the ratio from a 3-image sample.

### One family, 13 distinct bodies

The family resemblance across all 65 should come from **three constants**, never from a
shared costume:

1. The ready stance (above).
2. A single shared gear grammar: **wraps on the striking limb(s) + one team-colour carrier**
   (below) — present on every species in some anatomically honest form, absent nowhere.
3. The painterly rendering recipe (same light logic, same outline weight, same level of
   material detail) applied consistently across all 65, regardless of body type.

The 13 body types differentiate through **proportion and material of hide**, which the
existing portraits already do well (Mammal = grounded/heavy, Avian = long-necked/light,
Reptilian = low and wide, Insectoid = plated/angular) — keep leaning on this, it works.

### The team-colour carrier — one idea, adapted per anatomy

This is the concrete mechanism that makes "Guild Colours" real on a creature, and it has to
be solved per body type because a sash makes no sense on an octopus:

| body type | carrier | why |
|---|---|---|
| Mammal, Marsupial, Reptilian (limbed, land) | wrist/ankle wraps + a waist or chest sash | direct analogue to a real fighter's kit |
| Avian | a dyed leg-band or a ribbon threaded through flight feathers | doesn't obstruct flight silhouette |
| Aquatic | a cord of dyed kelp/cord wound through a fin or tentacle, OR painted bands on a shell (Nautilux, Maelurk) | cloth doesn't survive water; the fiction should show it knows that |
| Insectoid | a waxed thread lashed across the thorax, or a dab of pigment directly on the carapace (a "race number" read) | nothing to tie cloth to on a chitin body |
| Draconic / Abyssal (prestige) | a heraldic drape across the shoulder/back, more ceremonial in cut than the base tier's sash | licence-gated species should visibly cost more to field |
| Mythical (prestige) | worn regalia motifs — NOT a crown implying royalty-by-birth, but guild medallions/rank braid implying "this individual is renowned" | ties status to achievement, not species, matching the class-is-emergent rule |
| Fusion (bred) | inherits carrier logic from **both** parent bodies where anatomically compatible | flagged as a real design puzzle per fusion pairing, not a default — see §6 |

⚠️ **The carrier is always a small, removable-looking object — never a recolour of hide,
fur, feather or scale.** A team's colour must never touch the species' own material,
because that material is the species' fixed identity (the thing that makes Kongrath
recognisably Kongrath in any team, any league, any lighting). Recolour the sash; never the
gorilla.

### Making prestige and fusion feel special

- **Prestige** (Draconic, Abyssal, Mythical) reads as elevated primarily through the
  ceremonial *cut* of the team-colour carrier (drape vs sash) and through a per-line
  material motif distinct from the 30 base species: Draconic gets a burnished, oxide-toned
  plate-like scale sheen; Abyssal gets bioluminescent markings that *glow* in place of dye
  (a deep-world creature's version of "wearing colours" — light instead of cloth, which is
  free worldbuilding); Mythical gets the guild-medallion/rank-braid language above. None of
  this touches statScale/mana/pricing — it's presentation for species that are already
  gated behind a Special or Elite Licence in the systems.
- **Fusion** (bred, not bought) must read as a genuine hybrid silhouette, not a reskinned
  parent. ⚠️ **Flag for audit, not asserted here as already true:** verify all 20 fusion
  portraits actually combine both parent bodies' signature silhouette elements (e.g. a
  Saurian — Mammal+Reptilian — should read as neither a straight mammal nor a straight
  reptile at a glance). This wasn't sampled directly; treat it as an open production item
  (§6).

---

## 2. Arena and venue direction

Builds directly on `ART_DIRECTION.md`'s three axes (material / surface / grandeur) and
`ARENA_DESIGN.md`'s signature system (piece count, bar-vs-block ratio, mass position, depth
bands) — **both stay, unedited, for anything below the venue's rim.** What changes is
everything the new camera and new scale (§0) make possible above and around it.

### Venue vs fighting ground — a real split now, not a fiction

- **Fighting ground**: the combat-legal rectangle, sized by `arenaGridFor(teamSize)`,
  governed by the density law, deployment bands, mirror rule, cover arrangement vocabulary
  — exactly as specified in `ARENA_DESIGN.md`. **No elevation.** This is where the sim
  happens and where the readability rules in §4 are non-negotiable.
- **Venue**: everything around it — stands, crowd, colonnades, treeline, the grandeur
  ladder. Now genuinely larger than the screen and no longer required to fit inside one
  fixed camera frame.

### The camera pivot, and what it unlocks

⚠️ **The old camera FIT the board; the new camera FOLLOWS the fight.** This was a
consequence of the billboard renderer (fixed ~38° elevation, long lens, sized to the
board's aspect so nothing fell outside frame) and it is explicitly listed as scar tissue in
the task brief. The practical effect: **the venue was rarely fully visible during play even
before this change** — `ARENA_DESIGN.md` already measured that a square board leaves almost
no headroom above the far stand. That was treated as a limitation to work around. Treat it
instead as license for a proper broadcast-style structure:

1. **Establishing shot** — at the start of a replay, a slow pull-back-then-settle or a
   drone-style pass across the venue exterior. This is where grandeur is *experienced* —
   the one moment a Tamers Apex ceremonial arch or a Wood field's bare rail actually fills
   the frame. Ten seconds spent here per battle is not overhead; it's the only place the
   grandeur ladder pays off visually now that the tactical camera won't hold it.
2. **Tactical camera** — pulls in tight to the fighting ground once the fight starts,
   follows the action, keeps the readability rules in §4 satisfied above all else. The
   venue exists at the edges of frame as atmosphere (banners, crowd noise, torchlight) but
   is not the thing being read.

This is a genuine upgrade, not a compromise: a fixed-fit camera had to compress every
league's grandeur into the same frame; a following camera means Tamers Apex's establishing
shot can be enormous and Wood's can be a single static, cheap pan — the grandeur *ladder*
now has a cinematography budget to spend, where it never did before.

### Avoiding "same objects, different colour" at scale

This was named directly in the brief and it is the single most important thing this
section has to prevent, especially given the standing 5v5 rule: **Platinum through Tamers
Apex are 24 boards at one identical grid size, differentiated only by colour and material**
(`CLAUDE.md`, `ARENA_DESIGN.md` §7). `ARENA_DESIGN.md` already found and fixed one version
of this failure at floor level (the "fifteen paint jobs on one layout" incident, §4) — the
signature system it built (piece count / bar-vs-block ratio / mass position / depth bands)
is the correct fix and must be enforced on every one of the 24 5v5 boards, no exceptions.

But floor signature alone will not carry 24 boards on its own — it wasn't designed to; it
was designed for a dozen or so lower-league boards. Two NEW differentiators become
available specifically because the camera no longer needs to fit everything into one frame:

1. **Exterior silhouette.** The venue's *outside* shape — dome vs open colonnade vs
   turreted quadrant vs a plain rectangular hall — was previously invisible (camera never
   pulled back far enough to see it) and is now the primary thing the establishing shot
   shows. This is the cheapest, highest-impact axis available: a Masters venue and a Tamer
   Elite venue can be genuinely different BUILDINGS from outside even while sharing a
   floor's grid size and grandeur tier's ornament vocabulary.
2. **Real volumetric props, not prop-cards.** `GODOT_MIGRATION.md` already flags this:
   "every prop draws along X" and "depth ≤ width × sprite aspect" exist *because* props
   were billboards standing on rectangles. A real 3D mesh has neither limit. This means
   COURT and DOGLEG arrangements (§ARENA_DESIGN) can finally use a genuinely round fountain,
   a barrier that actually spans the approach, or a deep alcove — arrangements the old
   prop-card geometry could only ever fake from one angle. Revisit both retired constraints
   explicitly when porting; don't carry them into Godot out of habit.

⚠️ **Author the exterior silhouette for all 24 5v5 boards as a checklist BEFORE authoring a
single one**, the same discipline `ARENA_DESIGN.md` demanded of floor signatures ("no two
boards share a layout signature," enforced globally). A list of 24 distinct building types
is the actual deliverable; individual arenas are just executing entries on it.

### The grandeur ladder still applies, cumulative, unchanged

The eleven-rung table in `ART_DIRECTION.md` (Wood: nothing → Copper: treeline → Tin: holds →
Bronze: seat backs → Iron: balustrade + braziers → Silver: columns → Gold: planters + floor
medallion → Platinum: arches + canopy + pennants → Masters: entablature + statues +
emissive inlay → Tamer Elite: turrets + mosaic → Tamers Apex: ceremonial arch) is correct
and stays. Progression reads as progression because each rung adds one **nameable, new**
feature cumulatively, never a re-hue — that logic doesn't change with the camera; it just
finally gets a proper stage (the establishing shot) to be seen on.

### Crowd

Crowd *fill* remains a gameplay variable, not an art one — per the standing decision that
fill is driven by team fame and meta modifiers, never scaled to arena size. The art brief is
narrower: define what a **filled** seat and an **empty** seat look like at each grandeur
tier (silhouette detail, colour treatment), and leave the density hook alone. ⚠️ Current
crowd is capsule primitives (`ART_DIRECTION.md`, Open) — replacing that with genuinely
readable spectator silhouettes (even low-poly, instanced) is a real production item, listed
in §6, but it must not become an excuse to also touch the fill-amount logic, which belongs
to gameplay.

---

## 3. Readability system

⚠️ **This is the section that matters most.** The player never intervenes — they watch a
5v5, twenty possible abilities, and a shifting status board, in real time, and has to be
able to answer three questions at a glance: *who's who, what's happening, who's winning.*
Every proposal below is judged against those three questions, not against "does it look
good."

### Who's who — team identity

- **Team-colour carrier** on every creature (§1) is the primary channel: a sash, wrap-band,
  cord, or ceremonial drape in the team's colour, on the same body part across every
  species on that team, at every zoom level (portrait, battle sprite, and a further
  simplified nameplate icon in UI).
- **Nameplate/HP-bar frame** tinted with team colour, floating above each unit — this is
  the fallback for the cases where the in-fiction carrier is small or partly occluded
  (a coiled Aquatic, a unit mid-cast with limbs raised).
- ⚠️ **Reserve status hues away from likely team hues, or add a shape/pattern
  differentiator.** Two teams *will* eventually collide on a similar colour (there's no
  fixed roster of team colours implied by the design), so the nameplate frame should carry
  a secondary tell (solid vs striped edge, or a small guild-glyph) that survives a
  colourblind pass and a same-hue-team collision. This is a concrete constraint for
  whichever system generates/assigns team colours — flag to ui-programmer.

### What's happening — abilities and channels

- Keep and formalise the existing `CHANNEL_COLOR` convention already live in
  `fieldFx.ts` (melee white, ranged amber, magic purple, voice pink, support teal) as
  **the channel language** — canon, not implementation detail. It already correctly
  replaced element-based VFX after elements were removed (`⚠️ ELEMENTS REMOVED` comment in
  that file) — this document formally adopts it as the game's ability-colour system.
- Add a **cast-tell**: a small channel-coloured glyph on a unit's action indicator that
  appears the instant a cast begins (`castTime` window), so the player reading a blur of
  five units gets advance notice of *what kind* of thing is about to land, before the
  particle burst resolves. This is a genuine legibility gain in a 5v5 the player can't
  pause — cheap to build (one glyph, one colour lookup already exists), high value.

### Who's winning — health, threat, and status

- **HP fill uses a universal threat gradient (green → amber → red) independent of team
  colour.** Team colour lives on the *frame*; the fill communicates danger, and danger must
  read the same for every team, every league, every time. Don't let team colour and HP
  colour compete for the same bar.
- **"Under fire" cue.** `tools/focus.ts` already measured that a side's damage concentrates
  hard on one target (top share 0.711 — nowhere near an even 0.33 split across three
  bodies). That's not just a balance fact, it's the single most important piece of
  information in a 5v5 fight the player is only watching, and it currently has no visual
  representation. Recommend a glow/pulse on whichever unit is *currently* the focus target
  — it turns "read five health bars and do the arithmetic" into "look at the thing that's
  glowing." This is the single highest-value readability addition this document proposes,
  because it's backed directly by the sim data already in the repo, not a guess.
- **Status vocabulary**: replace the current ad hoc emoji set (`EFFECT_ICON` in
  `fieldFx.ts` — 🕶️☠️🔥😱💫💤💨🩸🤐🎯😴💀🚫⚡💞) with a small authored icon set drawn in the
  same bold dark-outline language as the battle sprites, so a status chip visually
  *belongs* to the creature wearing it instead of looking like a text-message reaction
  pasted on top. Group by category with a consistent colour family per group, distinct from
  team colours and from the HP threat gradient:
  - **hard control** (`HARD_CONTROL_STATUSES` — stun, sleep, fear, confusion): pale
    yellow/white, rendered first/leftmost — these are the ones that most change what's
    about to happen.
  - **damage-over-time** (poison, burn, bleed, doom): warm-to-cool by *kind* not severity
    (poison green, burn orange, bleed red, doom near-black/purple) — distinguished by icon
    shape as well as hue, so a colourblind read still separates them.
  - **utility debuffs** (blind, silence, vulnerable, healblock, knockback, charm):
    desaturated violet/grey family — reads as "something is wrong with this unit" without
    competing against the two categories above.
  - **buffs** (haste, atkUp, defUp): cool blue/cyan family, visually calm against the
    warmer control/DoT groups.
  - Exact hex values and the actual icon linework are a technical-artist/UI-programmer
    production task (§6) — this section fixes the grouping logic and the anchor hues,
    which is the part that must not drift asset-to-asset.

### Role readability without contradicting "classes are emergent"

Front line, caster, and support *feel* visually distinct in most team-based games through a
fixed pose language keyed to class. That shortcut is **not available here** —
`CLAUDE.md`'s standing rule is explicit: class is derived fresh every fight from current
stats, never stored, and "any species can in principle train into any class." A pose baked
into a species' battle sprite would silently violate that the day a player trains a
Warrior's stats into a caster shape.

The correct fix: **pose is chosen by current class-at-fight-time**, computed the exact same
way tactics and gameplans already are (`classForStats()`), and the battle sprite rig
selects from a small shared set of "ready" poses (front-line brace, caster coil, support
gesture) rather than each species owning one fixed pose. This is a real engine/pipeline
implication, not just an art one — flag to technical-artist as part of the battle-sprite
build (§6): the rig needs a class-keyed pose selector, not a species-keyed one.

### Camera legibility

- Default tactical framing keeps the **whole fighting ground** legible — this is
  `LENS.BOARD`'s job already and it should stay the default throughout a 5v5, not just at
  deploy.
- Reserve any tight, single-target punch-in for genuinely rare highlight beats (an execute
  landing, an ultimate-tier cast) where briefly losing sight of the other eight units is an
  acceptable trade for drama. This is a cinematography rule, not an art-asset rule — owned
  jointly with whichever system drives the camera; flagged here as a constraint it must
  respect.

---

## 4. UI direction

The current UI (`src/styles.css`) is a generic dark dashboard — system font, no material
identity, no connection to the Circuit. It should belong to the same world the arenas and
creatures do, using the **same** vocabulary rather than inventing a fourth one:

- **Chrome material follows the league.** Menu panel framing borrows the *current* league's
  material identity from `venue.masonry`/`venue.stone` — a Wood-league session's panels
  read timber-grain, a Gold-league session's read gilt-edged brass. This is nearly free
  (the palette tables already exist for arenas) and it makes the UI feel like it's *inside*
  the Circuit rather than wrapped around it.
- **Team colour is the UI accent**, not a fixed brand blue. Buttons, selection highlights
  and active-tab indicators pick up the player's current team colour — reinforces "this is
  your team's interface" the same way team colour reinforces "this is your creature" on
  the field.
- **Icons**: one authored icon set (bold, dark-outlined, matching the battle sprite
  language) replacing both the status emoji (`EFFECT_ICON`) and any ad hoc stat glyphs, so
  a status chip in the HUD and the same status's icon on a unit in the arena are visibly
  the same drawing.
- **Typography**: a sturdy slab/display face for headers and section titles (reads as
  ringside signage — a guild's hand-painted placard), a clean humanist sans (the current
  system-ui stack is fine) for dense data — stat tables, training rolls, tournament
  standings. Don't stylise the data-dense screens; stylise the frame around them.
- **Two registers, one family.** The Ranch/Market/Tournament-standings screens are a
  trainer's paperwork — dense, functional, ledger-like, closer to a guild office than a
  battle HUD. The live arena screen is a broadcast overlay — scoreboard, sash-coloured
  nameplates, minimal chrome so the fight stays legible. Both use the same material/team-
  colour/icon language (above); they differ in *density*, the way a sports game's manager
  desk differs from its match-day HUD (Teamfight Manager, already cited in
  `BATTLE_SPRITES.md`, does this split well).

---

## 5. Production plan

Grounded in `ART_PIPELINE.md`'s actual capability, not a wishlist. Route B (`codex` CLI
via the ChatGPT subscription) is the live, working generation route as of 2026-08-01; Route
A (OpenAI API) is billing-capped; Route C (procedural rig, `pixelRig.ts`) is a placeholder
only — explicitly **not** shippable quality per that document, keep it that way in planning.

⚠️ **Reconcile a real discrepancy between the two source docs before scoping this work**:
`ART_PIPELINE.md`'s asset table says battle sprites are "128×128 RGBA, side profile, **4
frames**," 0 of **260** (65 × 4). `BATTLE_SPRITES.md` — the actual spec — says **6** frames
(idle, walk1–4, strike) per species, **30 of 390** (65 × 6), and gives the explicit reasoning
for needing four walk frames over two ("a four-frame cycle gives the vertical bob that
makes it read as walking... the minimum that does"). Trust `BATTLE_SPRITES.md`: it's the
newer, more detailed spec and its reasoning is sound. `ART_PIPELINE.md`'s summary table is
### Order of work

1. **This document locked** — the theme, the team-colour-carrier mechanism, the palette
   discipline, and the readability rules are the brief everything below executes against.
2. **Battle sprites, first — not last.** This is the asset actually on screen for the vast
   majority of play (a 5v5 fight, watched not operated), it's the fully specced and
   pilot-tested asset (`BATTLE_SPRITES.md`, Mammal pilot already validated the portrait→
   pixel reference technique and the foot-anchor processing), and it's currently at **0 of
   390 generated**. Start with the Mammal group (5 species, least risk, already piloted) and
   use that batch to prove the team-colour-carrier convention (§1) in pixel form before
   scaling to all 65 — a wrap or sash has to survive being 4px wide before it's trusted at
   scale.
3. **Portrait audit, targeted, not a full redo.** Before commissioning any portrait rework,
   run a full pass of all 65 against the war-armour/athlete's-kit table in §1 (this
   document sampled 3 of 65; that is not a basis for a production estimate). Expect a
   minority to need rework (Maneleo confirmed) — redirect those specifically rather than
   regenerating a set that's mostly already correct.
4. **Fusion silhouette audit.** Verify all 20 fusion portraits read as genuine hybrids of
   their two parent bodies, not a reskinned single body (§1). This wasn't visually
   confirmed while writing this document — treat as open.
5. **Arenas, ported then extended.** Port the theory and the five leagues' worth of design
   work already done (`ARENA_DESIGN.md` Status: Wood, Copper, Tin, Bronze, Iron authored)
   into Godot's procedural-mesh system first, as the reference implementation proving the
   pipeline survives the engine change. Then author Silver → Tamers Apex (7 leagues, 33+
   boards, including the 24-board interchangeable 5v5 pool) applying the NEW
   exterior-silhouette checklist from §2 *before* individual board layout work starts.
   Delegate the Godot-side procedural mesh implementation to technical-artist; this
   document sets the brief (materials, silhouette differentiation, camera behaviour), not
   the shader/mesh code.
6. **Retire the photoreal JPEG backgrounds from shippable use.** `public/backgrounds/*.jpg`
   (10 league + 8 area + apex) are genuinely good mood paintings — Masters' golden-hour
   Byzantine banners is a strong target *feeling* for that grandeur tier — but they are
   flat, cannot support a following camera, cannot carry the per-league lamp system, and
   cannot host a live crowd or cover layout. Keep them explicitly as **concept-art / lighting
   references** pinned alongside this document; do not let them survive as in-game assets
   once the Godot 3D venue exists for a league, or the game will visibly run two
   contradictory art styles side by side (photoreal matte painting behind a stylised
   HD-2D fight) — exactly the kind of inconsistency this document exists to prevent.
7. **UI, after the battle sprite icon language exists.** The status icon set and the
   material/team-colour chrome (§4) both depend on decisions made while building the battle
   sprites (the "hand" — outline weight, palette discipline). Sequence UI visual work after
   step 2, though the *information architecture* — what must be legible, from §3 — is
   specified now so ui-programmer and ux-designer aren't blocked waiting on final art.
8. **Crowd geometry** (replacing capsule placeholders) is a real but lower-priority item —
   sequence after arenas, since crowd dressing depends on the venue geometry existing
   first. Fill amount stays gameplay-owned throughout; only the rendering treatment of a
   filled vs empty seat is in scope here.

### Explicitly out of scope for this document

No code, no shaders, no actual pixel/3D art produced here — this is direction, to be
executed by technical-artist (Godot mesh/shader implementation, exact hex values, icon
sheets) and ux-designer (interaction flow, screen layout) against the brief above. The
asset naming question (whether battle sprites should be renamed to match the studio's
stated `[category]_[name]_[variant]_[size].[ext]` convention, given the existing tooled
`public/battle/<id>-<frame>.png` pattern already works end-to-end) is flagged, not decided,
here — coordinate with technical-artist before touching working tooling for a naming
cosmetic.
