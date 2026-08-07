# Audio Direction — Guild Colours

**Status: first draft, 2026-08-04. No audio of any kind exists in this project yet — no
assets, no engine wiring, no prior doc.** This is direction, not production: it does not
touch source, does not generate audio, and does not write engine code. It is owned by
`audio-director` and should be treated the same way `ART_THEME.md` is treated for visuals —
read before any sound is authored, requested, or wired into a scene.

Built against `CLAUDE.md`'s vision section, `docs/ART_THEME.md` §0 ("Guild Colours"), and
`docs/AUTOBATTLER_DESIGN.md` (free-willed monsters under a player's plan, mixed aiming,
emergent 30s–3min fight length). Where this document proposes something that is really a
gameplay-data or engine decision (an event the sim needs to emit, a bus a system needs to
own), it is flagged for `game-designer` / `lead-programmer` rather than decided here.

---

## 0. The one constraint everything below answers to

**The player never intervenes in a fight.** They set tactics, then watch. `CLAUDE.md`:
*"An unreadable fight is not a hard fight, it is a slot machine."* In a game where watching
IS the gameplay, on a board that can be 160×88 units with ten monsters moving freely
(`AUTOBATTLER_DESIGN.md` §0/§5 — the whole point of the free-placement rework is that units
spread across the full width), the eye cannot be everywhere at once. **Sound is a second
reading channel, not an atmosphere layer** — it has to carry information the eye is
currently missing: a hit landing off-screen-of-attention, a big ability committing, a
monster going down, momentum turning. Every section below is judged against that job first,
"does it sound good" second.

---

## 1. The sonic identity, in one line

> **A trade guild's fight night: hand-struck, hide-and-timber, crowd-judged — never a
> battlefield, never a dungeon, never a dashboard.**

This is the audio translation of the art bible's *"a sport built by hand, judged by trade
guilds, fought by athletes who dress for the ring, not for war"* (`ART_THEME.md` §0). Same
mechanism as the art doc: naming what it **forbids** is doing as much work as naming what
it **is**.

**What this forbids, specifically:**

| forbidden register | why it breaks the identity | where it would sneak in |
|---|---|---|
| Orchestral "war" scoring — horns-and-choir bombast, doom drums under every fight regardless of stakes | Asserts life-or-death stakes a Wood-league bout doesn't have. The grandeur ladder is supposed to be *earned* league by league (`ART_THEME.md` §2) — if Wood already sounds apocalyptic, Tamers Apex has nowhere to go | Combat music, victory stingers |
| Horror/dungeon-synth textures (dissonant drones, jump-scare stingers) for statuses and low-HP states | A monster going down is a **sport injury**, not a horror beat — the bestiary is explicit that these are consenting professional competitors, not victims (`ART_THEME.md` §0) | Status-effect stings, death/KO sound, low-HP "danger" cue |
| Sci-fi dashboard UI (synth beeps, laser confirms, holographic swooshes) | Contradicts the UI direction's own rule — chrome follows league material, panels read timber-grain or gilt-brass, never a HUD (`ART_THEME.md` §4) | Menu/UI sounds, notification chimes |
| Generic "monster movie" roars read as *threat* | These are competitors, not monsters to fear — a roar in this game is a **crowd** sound (triumph), never a creature's threat-display sting | Creature vocalisations, ability impacts |
| Continuous underscore that never lets the crowd or the SFX breathe | If music is always loud and always present, it drowns the one channel that actually carries live information (§2, §6) | Combat music generally — see §5's recommendation to keep it sparse |

**What it IS, in texture terms:** acoustic and semi-acoustic over synthetic; hand tools and
craft materials (wood, leather, hide, forged metal, rope, canvas) over digital or magical
sheen; a **live sports broadcast** ambience (crowd, ring announcer energy, the specific
texture of a filled or half-empty venue) over a **cinematic score** ambience. Where the game
needs a genuinely arcane or magical sound (INT-channel abilities), it should still sound
*crafted* — a tuning fork, a struck bell, a resonant tool — not a synthesizer pad. This
mirrors the art direction's own rule that Abyssal bioluminescence is "worldbuilding, not
free VFX license": magic here is a guild's trade secret, not a genre convention.

---

## 2. The crowd as an instrument

⚠️ **This is the single highest-value idea in this document, and it should be treated as
close to load-bearing as the cast-tell glyph is in `ART_THEME.md` §3.** A sports crowd
reacts, and its reaction is *itself* information — a gasp at a near-death, a roar at a kill,
a murmur through a lull, a held breath in the final stretch. In a no-intervention game, the
crowd can tell the player how the fight is going **without a single UI element**, the same
way `ART_THEME.md`'s "under fire" glow is proposed to make focus-fire legible without
arithmetic. Sound gets there for free where a visual channel needs a new asset.

### Two independent variables — do not collapse them

| variable | driven by | changes | must NOT change |
|---|---|---|---|
| **Crowd fill** (how full the venue is, how big/present the ambient bed is) | **Team fame + meta modifiers** — per the standing decision already recorded in project memory (`crowd-fill-by-fame`) | per match, based on who's fighting | is never scaled to arena size or league tier alone — a low-fame team can headline a Gold arena to a half-empty house; a famous team can pack a Wood-league exhibition |
| **Crowd reactivity** (does it gasp/roar/hush on cue) | **Live fight state** — HP thresholds, kills, misses, the closing stretch | every fight, every league | is never reduced by low fill — a thin crowd still gasps, just with fewer voices in the gasp. Reactivity is the information channel; fill is the spectacle variable. Conflating them would mean a low-fame match reads as a *flatter* fight, which is untrue and actively misleading |

This split matters because it keeps the crowd honest as an instrument: fill tells the
player "how big is this match," reactivity tells them "who's winning right now." Both are
real information; they must stay on separate faders.

### Proposed reaction states (state-driven, not timeline-scripted)

Fights are emergent length, ~30s to ~3min (`AUTOBATTLER_DESIGN.md` #11) — **a scripted cue
sheet cannot work here.** The crowd must be a state machine reacting to sim events, not a
composed piece with a runtime. Proposed states, each triggered off an event the sim likely
already has or can cheaply expose:

| state | trigger | sound |
|---|---|---|
| **Base murmur** | idle / no recent event | a continuous low bed, texture and size set by fill (§ above), pitched down and thinned for a sparse Wood crowd, full and warm for a packed Apex house |
| **Ripple** | a clean hit lands, a status cast connects | a small, quick swell in the murmur — not a full stinger, just enough life that the bed doesn't feel static during a normal exchange |
| **Gasp** | a monster crosses a low-HP threshold (candidate: the same threshold that would trigger a visual "danger" state, if `game-designer` defines one) | a sharp intake, cuts through the mix briefly |
| **Groan / whistle** | an aimed ability misses (`AUTOBATTLER_DESIGN.md` #9, §8 #20 — misses are now a real, geometry-driven outcome) | a distinct "oof, so close" sound — this is the audio side of making a miss feel like a *read event*, not a wasted turn |
| **Roar** | a kill | the biggest single crowd cue in the vocabulary — should be unmistakable even under combat SFX |
| **Hush** | the fight enters its decisive stretch (candidate: last two monsters standing on one or both sides) | the bed drops in volume and density — the sports-broadcast "you can hear a pin drop" moment before a finish, which also has the practical mixing benefit of clearing headroom for the final exchange's SFX |
| **Ovation** | match end / victory | full crowd swell, the release after Hush |

⚠️ **Every trigger above is a proposal, not a decision** — the exact HP threshold, whether
"decisive stretch" is monster-count-based or something else, and whether these hook off
existing `BattleEvent`/frame-stream fields or need new ones, are `game-designer` /
`lead-programmer` calls. What this document is fixing is the **vocabulary and the principle**
(state-driven, fill ≠ reactivity, crowd is a reading channel) so that whoever wires it has a
brief instead of a blank page.

### What this needs from the sim, honestly

The crowd system needs event hooks it may not currently have wired to audio: HP-threshold
crossings, kill events, miss resolution, and some notion of "how close to over is this
fight." Most of these likely already exist as `BattleEvent`s for the visual layer (float
text, status icons) — the audio system should **subscribe to the same event stream**, not
duplicate game-state reasoning. This is worth flagging to `lead-programmer` early: cheap if
the events already exist, a real ask if they don't.

---

## 3. Combat SFX taxonomy

### By channel — reuse the game's own five-channel language, don't invent a sixth

`ART_THEME.md` §3 already canonises `CHANNEL_COLOR` (`fieldFx.ts`) as the ability-colour
system: **melee (white), ranged (amber), magic (purple), voice (pink), support (teal)**.
Audio should be keyed to the exact same five channels, so a player who's learned "purple =
magic" from the VFX gets the same read from the timbre. This also means sound design and
VFX can be commissioned/reviewed against one shared taxonomy instead of two.

| channel | material language | rough sonic character |
|---|---|---|
| **Melee** | hand tools, hide, forged metal | dry, percussive, close-mic'd thuds and cracks — a boxing-ring sound, not a sword-and-board fantasy clang |
| **Ranged** | drawn wood, fletching, taut cord | a release-and-flight-and-impact shape — snap, air, thock |
| **Magic (INT)** | struck resonant tools — tuning forks, bells, glass, not synth pads | a chime/resonance family, pitched, with a "crafted" attack transient rather than a swell |
| **Voice (CHA)** | a ring announcer, a horn, a chant | vocal-adjacent or brass-adjacent textures — this is the channel most likely to carry an actual "voice" sound without becoming literal dialogue |
| **Support (WIS/CON)** | cloth, warm wood, a healer's kit | soft, warm, sustained textures — the deliberate opposite of melee's dryness |

### By outcome — the taxonomy that actually needs to be distinct under load

⚠️ **The real test is not "does each sound good alone" — it's "can a watcher tell five of
these apart when they happen in the same half-second on a 5v5 board."** That means outcome
variants within a channel should differ in **transient shape and pitch**, not just loudness,
because loudness collapses the moment two events overlap.

| outcome | design note |
|---|---|
| **Hit** | the channel's base impact sound |
| **Crit** | same family as hit, sharper attack + a brief higher tail — a variation on the hit, never a wholly different sound (keeps the "what channel was that" read intact even at a glance) |
| **Miss** | a whoosh/no-connect shape, distinctly NOT an impact — pairs with the crowd's Groan (§2). This is a new outcome the mixed-aiming rework (`AUTOBATTLER_DESIGN.md` #9, §8 #20) makes newly important: a miss used to not exist as a legible event and now it's one the player should be able to read as "that was a real dodge/lead-miss," not "nothing happened" |
| **Blocked** | a parry/guard thunk — must read as categorically different from Hit (defensive success is different information from an attack landing) |
| **Warded** | a shimmer/break cue layered over the underlying hit — communicates "the damage happened but something absorbed it," distinct from Blocked's flat negation |
| **Status apply** | grouped, not per-status (see below) |

### Status stings — grouped exactly the way `ART_THEME.md` §3 groups the icon set

That document already solved the "18 statuses is too many to make individually legible"
problem for the eye by grouping into four families with shared hues. Audio should reuse the
**same four groups**, so an icon and its sound are always the same category:

| group | statuses | sonic family |
|---|---|---|
| **Hard control** (`HARD_CONTROL_STATUSES`: stun, sleep, fear, confusion) | one shared "your turn is being taken from you" sting — highest-priority family, since this is the one that most changes what's about to happen | a sharp, arresting cue — the closest thing to an alarm this vocabulary allows |
| **Damage-over-time** (poison, burn, bleed, doom) | one shared apply-sting + a distinct **ambient tick** per kind for as long as it's active (poison a soft hiss, burn a low crackle, bleed a wet-adjacent pulse, doom a near-silent low tone) — the tick is what lets four different DoTs on four different monsters stay tellable apart in a lull | the tick matters more than the apply-sting here, because DoT is read continuously, not once |
| **Utility debuff** (blind, silence, vulnerable, healblock, knockback, charm) | one shared "something is wrong with this unit" sting, deliberately less alarming than hard control | a duller, discordant cue |
| **Buff** (haste, atkUp, defUp) | one shared warm/rising cue | the deliberate opposite of the debuff families — should read as good news at a glance-listen |

This keeps the **status vocabulary at four sounds plus four DoT ticks**, not eighteen —
directly answering the "minimal viable set" goal in §7 while staying legible.

### Priority under load

When more events happen in one tick than can be voiced clearly, some must be dropped or
simplified rather than all playing at once and mudding into noise. See §6 for the concrete
ducking/priority order — the taxonomy above is designed so the highest-priority tier (kill,
hard control, crit) is also the most sonically distinct tier, on purpose.

---

## 4. Ability tells

`AUTOBATTLER_DESIGN.md` #9 and `ART_THEME.md` §3 both establish the same principle from two
different directions: **a committed cast has a windup the caster is rooted through, and the
watcher needs advance notice of it to have any chance of predicting the outcome.** The art
doc proposes a visual cast-tell glyph, channel-coloured, appearing the instant a cast begins.
Audio's job is to give that glyph a sound, because on a wide board the glyph may not be
where the player's eye currently is — the ear covers the whole board at once, the eye
doesn't.

- **Cast-tell sting**: fires the instant `castTime` begins, channel-timbred per §3's table
  (so a magic cast-tell and a melee cast-tell are already distinguishable before the player
  even looks). Short, rising, unmistakably "something is starting" — this is the sound
  equivalent of a boxer winding up a haymaker, not a subtle whisper.
- **Charge-up tail (for longer windups only)**: if a cast has a windup long enough to matter
  tactically, a held tone or building texture through the windup gives a *second* chance to
  notice, for a player whose attention was elsewhere when the initial tell fired. Cheap to
  build as a looped stem that starts on the tell and stops on release/interrupt.
- **Capstone/big-ability tell**: reserved for the genuinely rare highlight beats
  `ART_THEME.md` §3 already reserves the tight camera punch-in for. This is the one tell
  that should be loud enough to **duck everything else** (§6) — a horn/bell hit big enough
  that a player looking at the wrong side of a 160-wide board still knows something large is
  about to land.
- **Interrupt/cancel**: if a cast can be broken (stunned mid-windup, target dies, etc.), that
  needs its own short "cut off" cue distinct from a normal release — otherwise a broken cast
  and a landed cast sound identical, which is exactly the kind of unreadable outcome this
  whole document exists to prevent.

⚠️ Whether interrupts are currently a real state the engine can hit is a `gameplay-programmer`
question, not an audio one — flagged here so the sound isn't designed for a state that
doesn't exist, and so it isn't forgotten if the state gets added later.

---

## 5. Music

### Per-league progression — the grandeur ladder gets an ear as well as an eye

`ART_THEME.md` §2 specifies an eleven-rung *cumulative* grandeur ladder for arenas (Wood:
nothing → ... → Tamers Apex: ceremonial arch), where each rung adds one nameable feature and
never just re-hues the last. Music should follow the identical discipline: each league adds
an **instrument or a texture**, never just gets "more epic" as a blanket intensity dial.

| stage | instrumentation idea | why |
|---|---|---|
| Wood / Copper | a single hand instrument — a fiddle, a hand drum, maybe just the crowd itself with no composed music at all | a village-fete-not-colosseum read, matching "Wood: nothing" in the arena ladder |
| Tin / Bronze / Iron | add sparse rhythm — a second hand drum, a struck idiophone (bell, block) | craft-guild materials, still small |
| Silver / Gold | a small ensemble — strings or winds joining the percussion, first sense of "occasion" | matches columns/planters/floor-medallion entering the visual ladder here |
| Platinum / Masters | fuller ensemble, a genuine melodic theme emerges | matches arches/canopy/pennants, entablature/statues |
| Tamer Elite / Tamers Apex | the fullest instrumentation the palette allows, but still acoustic/semi-acoustic — never crosses into the forbidden orchestral-war register from §1 | the ceremonial-arch tier; this is where the sport is at its most prestigious, not its most violent |

⚠️ **This is a texture ladder, not a volume ladder.** Wood should sound *smaller*, not
*quieter-but-otherwise-identical* — the instrumentation itself should be sparse, the same
way a Wood arena has fewer physical objects rather than the same objects at low opacity.

### Ranch vs arena — two registers, matching the UI split `ART_THEME.md` §4 already made

- **Ranch/Market/Tournament-standings**: functional, calm, guild-office register — closer to
  ambient background than "music" in the cinematic sense. Should be able to loop for long,
  low-attention stretches (feeding, training screens) without fatiguing. This matches the UI
  doc's own "ledger, not battle HUD" framing for these screens.
- **Arena**: broadcast-live register. **Recommend the crowd (§2) carries most of the
  emotional weight here, with music kept deliberately sparse** — stems/stingers rather than a
  continuous score. This is a direct consequence of §0: if music is loud and continuous, it
  competes with the crowd and the SFX for the exact bandwidth that's supposed to carry
  information. A quiet, sparse arena bed with the crowd doing the heavy lifting is not a
  compromise — it's the correct hierarchy for a game about watching a fight, not scoring one.

### Handling a fight that might be 30 seconds or 3 minutes

A composed, fixed-length cue cannot work against an emergent-length fight
(`AUTOBATTLER_DESIGN.md` #11: *"fight length is emergent... not a tuning target"*).
**Recommend an adaptive layered-stem approach**: a small number of loopable stems (a low bed,
a rhythm layer, a melodic layer) that the audio system can add or drop based on fight state
(opening exchange / mid-fight / decisive stretch — the same three-state read the crowd's
Hush trigger uses in §2), so the music never has to "run out" or loop awkwardly mid-fight.
This is deliberately the same adaptive-by-state principle as the crowd system, not a second
unrelated mechanism — one state machine, two instruments (crowd + music stems) reading it.

⚠️ **Three options exist here and the choice is a real one, not obvious** — worth a decision
before any music is commissioned:

1. **No combat music at all, ever** — crowd + SFX carry 100% of the emotional read. Cheapest,
   most in-genre with real sports broadcasts, lowest risk of ever competing with legibility.
2. **Sparse adaptive stems** (recommended above) — a light musical presence that breathes
   with the fight state, never a wall of sound.
3. **Full adaptive score**, closer to a traditional game combat music system (Wwise/FMOD-style
   layered intensity) — highest production cost, highest risk of drowning the crowd/SFX
   information channel if not disciplined, but the most conventionally "produced" feel.

This document's recommendation is **2**, with **1** as the fallback if production capacity
(§8) can't support even sparse stems — never **3** without a real mix-priority proof that it
doesn't bury §2/§3.

---

## 6. Mix priorities

**Information beats spectacle — this is the one sentence the whole mix strategy answers to.**
In a no-intervention game, a sound that's merely satisfying but tells the player nothing new
is lower priority than a plain sound that tells them something they couldn't otherwise know.

### Priority order (highest ducks/wins over lowest when the mix is busy)

1. **Kill / KO** — the single most important event in the fight; never buried
2. **Hard-control status apply** (§3) — changes what's about to happen
3. **Capstone/big-ability tell** (§4) — the rare highlight beat, allowed to duck everything below it briefly
4. **Crit / miss** — the outcomes that most change the reading of an exchange
5. **Cast-tell** (regular abilities) — advance notice, needs to cut through but not dominate
6. **Crowd reaction stingers** (gasp/groan/roar) — information, but secondary to the direct combat read
7. **Hit / blocked / warded / other status applies** — the steady-state combat texture
8. **DoT ticks, crowd base murmur** — ambient/continuous, always audible but always underneath
9. **Music stems** — present but subordinate to everything above, per §5
10. **UI** — lowest priority during an active fight (largely irrelevant mid-replay anyway,
    since the player isn't clicking)

### Ducking rules

- **Crowd base murmur ducks under every combat SFX transient** — it's a bed, not a
  competitor for attention.
- **Music ducks under crowd reaction stingers and under tiers 1–4** — reinforces §5's
  "crowd carries the emotional weight, music stays sparse" call.
- **When more simultaneous SFX are triggered than can be voiced clearly** (the actual 5v5
  problem — ten monsters, multiple actions resolving close together), **cull from the bottom
  of the priority list first**, not by simple polyphony limits alone. A voice-stealing
  algorithm that just kills the oldest-playing sound risks cutting a kill sound to make room
  for a footstep-tier event; priority-based stealing avoids that specific failure.
- **Player-facing volume**: standard per-bus sliders (Music / SFX / Crowd / UI) in options,
  matching the sound-bible template's baseline accessibility rule — no bus should be
  un-mutable, since a player who wants pure crowd-and-SFX (arguably the "purest" way to watch
  this specific game) should be able to have it.

⚠️ This section describes **behaviour**, not implementation — the actual bus graph, priority
queue and voice-stealing logic are `lead-programmer`/`gameplay-programmer` work once a scene
exists to hang `AudioStreamPlayer` nodes on. `docs/engine-reference/godot/modules/audio.md`
already has the baseline Godot pattern (bus-per-category, pooled `AudioStreamPlayer`s) this
should be built on — nothing exotic needed.

---

## 7. Minimal viable set

The point of this list is that a fight can become **readable** — not spectacular, readable —
with a small, honest number of sounds. Everything above is the ceiling; this is the floor to
build toward first.

| # | sound | covers |
|---|---|---|
| 1–5 | **Hit impact, one per channel** (melee/ranged/magic/voice/support) | the base combat read |
| 6 | **Crit variant** (pitch/transient tweak, can be one shared processing rule applied to all 5 rather than 5 separate assets) | "that one mattered more" |
| 7 | **Miss** (universal whoosh) | the new mixed-aiming outcome |
| 8 | **Blocked** | defensive success |
| 9 | **Warded** | absorbed-not-blocked |
| 10 | **Cast-tell** (can start as ONE sound, channel-pitched, before investing in five distinct timbres) | advance notice — arguably the single highest-value sound on this whole list given §0 |
| 11 | **Kill/KO** | the most important single event in a fight |
| 12–15 | **Status stings, one per group** (hard control / DoT / utility / buff — §3) | status legibility without 18 assets |
| 16 | **Crowd base murmur** (one loop, fine to start with a single fill-level rather than a fame-scaled set) | the ambient bed |
| 17 | **Crowd gasp** | near-death read |
| 18 | **Crowd roar** | kill read (pairs with #11) |
| 19 | **Crowd groan** | pairs with #7 |
| 20 | **Match end / ovation** | closure |
| 21–24 | **UI: click, confirm, back, error** | baseline menu feedback, since the ranch/tournament screens exist today with zero sound |
| 25 | **One ranch ambient loop** | §5, cheapest possible version |
| 26 | **One arena ambient bed** | §5, cheapest possible version — can literally just be the crowd murmur (#16) doing double duty at first |

**~24–26 sounds** gets a fight from silent to legible: every outcome in the taxonomy has a
distinct cue, the crowd is reacting, casts are telegraphed, and both non-arena screens have
baseline feedback. Everything past this (per-channel crit variants, per-status DoT ticks,
fame-tiered crowd sizes, league-tiered music) is real and valuable but is depth, not floor.

---

## 8. Production route — stated honestly

⚠️ **There is no audio-equivalent of the image pipeline.** `ART_PIPELINE.md` documents two
live routes for pixel/painted art (OpenAI API, and the `codex` CLI riding the ChatGPT
subscription) plus a code-drawn fallback (`pixelRig.ts`). **None of these produce audio, and
nothing in this repo currently generates, records, or synthesises sound.** Saying otherwise
would be exactly the kind of confident-but-wrong claim `CLAUDE.md`'s standing rules warn
against repeatedly. What follows is what's actually obtainable, not a wishlist.

### Route A — CC0/CC-BY sourced libraries (realistic, start here)

The genuinely fast, genuinely free route for the bulk of §7's list:

- **Kenney.nl** — CC0, no attribution required, already stylistically close to a clean
  arcade/sport register rather than a AAA cinematic one; has impact/UI/interface packs that
  cover a meaningful chunk of §7 (UI sounds, generic impacts) essentially for free.
- **Freesound.org** — huge CC0/CC-BY library, but needs real curation time per sound (license
  varies per upload, quality varies wildly) — workable for one-off specific sounds (a
  specific creak, a specific crowd texture) but not a drop-in set.
- **Sonniss GDC bundles** — free yearly royalty-free SFX bundles, professional quality,
  genuinely useful for impact/whoosh/ambience layers; less useful for anything bespoke to
  this game's specific fiction (a "guild sport crowd" is not a standard bundle category).

**Honest limitation**: the taxonomy in §3 (five channels × outcomes, grouped status stings)
and the crowd states in §2 are this game's own invented vocabulary — no library ships
"guild-sport crowd gasp, distinct from generic sports crowd gasp." Expect to find generic
building blocks (a good punch, a good crowd murmur, a good UI click) and assemble/layer them
to the taxonomy, not to find the taxonomy pre-made. That assembly work is real effort even
though the raw material is free.

### Route B — procedural/synthesised SFX (a fallback worth building, not yet built)

Godot's `AudioStreamGenerator` can synthesise simple tones and noise bursts at runtime — the
audio equivalent of `pixelRig.ts` drawing a creature from parts instead of a generated image.
This is realistic for the **simplest, most mechanical** tier of §7 (a generic hit thump, a UI
click, a cast-tell sting as a pitched sine sweep) using something like a lightweight
sfxr/bfxr-style retro-synthesis approach. **It is not realistic for the crowd** (§2) — a
convincing crowd needs recorded human voices or a well-made sample library; synthesis cannot
fake that at low effort, the way it can fake a simple impact. Flag as a genuine build item if
Route A search comes up short on the mechanical tier, not as a first choice.

### Route C — a dedicated audio-gen tool (unbuilt, unverified — do not assume it exists)

There may be a codex/ChatGPT-adjacent or other AI audio-generation path analogous to Route B
of the art pipeline, but **this has not been investigated and nothing should be planned
against it existing** until someone actually checks. If a technical-director or tools-
programmer wants to spend time on this, the right first step mirrors `ART_PIPELINE.md`'s own
history: check what the existing subscription/API access actually offers for audio before
assuming a gap needs a whole new paid tool.

### Recommendation, in order

1. **§7's minimal viable set, sourced from Kenney/Sonniss/Freesound (Route A)** — get a fight
   from silent to legible using free, license-clean material. This is achievable now, by
   whoever is delegated the actual sourcing (`sound-designer`), without waiting on any new
   tooling.
2. **Route B (synthesis) as a fallback** for any mechanical sound Route A can't cover cleanly
   — worth a small tools-programmer spike, not a big investment, once §7 is being sourced and
   specific gaps are known rather than guessed.
3. **Music (§5) is the one category genuinely worth flagging as needing either a composer
   collaborator or real investigation of Route C** — CC0 loops rarely nail a specific,
   evolving, per-league adaptive system, and this document's own recommendation (§5, option 2:
   sparse adaptive stems) is bespoke by nature. This can wait; it's explicitly not on the
   minimal viable list.
4. **Crowd (§2) sits between A and "needs real search effort"** — generic sports-crowd beds
   exist in most SFX libraries; the specific reaction states (gasp/roar/groan/hush as
   *discrete, triggerable* cues rather than one long ambient loop) will need real curation
   time to assemble from raw crowd recordings, not a single asset pack.

### What this document does NOT do

No sound is generated, sourced, licensed, or wired into a scene here. The actual sourcing
(Route A curation) delegates to `sound-designer`; the actual `AudioStreamPlayer`/bus
implementation in Godot delegates to `lead-programmer`/`gameplay-programmer`; any procedural-
synthesis tool (Route B) delegates to a tools-programmer spike. This document's job ends at
"here is the brief they should build against."

---

## Open questions for the studio

Flagged rather than decided, because each belongs to a different discipline:

1. **HP-threshold values for the crowd Gasp state and the visual "danger" cue** (§2) —
   `game-designer` should set one shared threshold so audio and visuals agree on what "near
   death" means, rather than each guessing independently.
2. **Whether "decisive stretch" (crowd Hush) is monster-count-based or something richer**
   (total HP remaining, momentum) — needs a definition the sim can cheaply evaluate.
3. **Does the frame-stream/`BattleEvent` system already carry everything §2/§3/§4 need
   (kills, miss resolution, cast-start), or does audio need new event types added?** — worth
   an early conversation with `lead-programmer`, since `AUTOBATTLER_DESIGN.md` §12 already
   has the frame-stream contract under active redesign for intent/reason logging; audio's
   needs should be scoped into that redesign rather than bolted on after.
3a. Music option 1 vs 2 vs 3 (§5) — a real creative-director-level call on how much of the
    emotional work music should do versus the crowd.
4. **Whether Route C (an AI audio-gen path) is worth investigating at all**, and if so, by
   whom — a `technical-director`/`tools-programmer` scoping question, not an audio-direction
   one.
