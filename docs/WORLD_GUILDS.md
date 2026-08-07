# World Guilds — the institution behind Guild Colours

**Canon Level:** Provisional (awaiting `narrative-director` sign-off). The parts of this
document that only *restate* already-approved fact — the material ladder, the Tamer-as-
partner canon, the licence system — are **Established**; everything new here (guild names,
colours-as-fiction, the founding story, venue names) is proposed and should be read as a
first pass, not locked.

**Visible to Player:** Discoverable. None of this needs to be dumped in a tutorial. A player
should be able to finish Tamers Apex having absorbed most of it from league names, arena
names, commentary flavour, bestiary entries, and stable chatter — never a lore-dump screen.

**Source:** Written to fill the gap named in the brief — `docs/ART_THEME.md` and
`docs/ART_BIBLE_GUILD_COLOURS.md` establish the *visual* identity and assert that guilds
exist and grade things; this document is where that assertion becomes a world.

**Cross-References:** `docs/ART_THEME.md` §0 (naming logic, material ladder), `docs/ART_DIRECTION.md`
(grandeur ladder, the "alloy story" — Bronze *is* Copper and Tin), `docs/ART_BIBLE_GUILD_COLOURS.md`
§4 (the eight livery colours, canonical hex/RGB), `docs/BESTIARY.md` (Tamer-as-partner canon,
per-body-type themes), `CLAUDE.md` (class is emergent, never destiny; the ladder is the spine).

**Contradictions Check:** Cross-read against `BESTIARY.md`'s canon note (partner not owner,
nobody forced into the ring), `CLAUDE.md`'s class-is-emergent rule (no guild locks a species
or a Tamer into a role), and `ART_THEME.md`'s forbidden list (no war gear, no birthright
regalia, no elements, no destiny). No contradictions found — see §2's explicit note on guild
temperament vs. destiny, and §4's explicit note on licence-as-standing rather than
licence-as-property.

**What this document does not do:** it does not draw a map. Full regional geography — where
Gradehall sits relative to anything else, what's beyond guild territory, whether the
traversable-world work (`docs/DECISIONS_2026-08-03.md` #10b) needs towns with their own
histories — is explicitly left open for whoever picks that up next. This document authors
the *institution*, because that's what the art needed and what was missing; it does not
pre-empt a geography nobody has decided on yet.

---

## 1. The Circuit — what it actually is, and why guilds run it

The game already has the name: **the Tamer Circuit**, the ladder of licences from Wood to
Tamers Apex (`BESTIARY.md`). What it didn't have was an answer to the obvious question — a
sport run by *trade guilds* is a strange enough idea that it needs to feel inevitable, not
decorative.

### The guilds didn't invent a sport. They already had the vocabulary for one.

Before there was a Circuit, there was a market. Every one of the founding trades — stone,
hide, cast metal, glass, dye, iron, and the standing office that judged all of them — graded
its own goods on a shared tiered vocabulary, because a buyer needs to know at a glance
whether this batch of ore is "tin-grade" or "bronze-grade" without re-litigating the question
every time. **The material ladder existed first, as trade language, and the sport borrowed
it** — it did not commission it. This is the load-bearing piece of logic the brief asked for:
Wood, Copper, Tin, Bronze, Iron, Silver, Gold, Platinum were never invented to name a game.
They were already how these eight trades talked about quality, generations before anyone
fought a match in front of a crowd. `ART_DIRECTION.md` already carries the sharpest version
of this idea without naming it as guild history — Bronze *is* alloyed from Copper and Tin,
and its arenas are built from both parent leagues' stock. That is not an art department joke.
That is what an alloy grade means, and the guilds would say so.

### Where the actual sport came from: it was cheaper than a lawsuit

Guilds disagree. A batch is graded short, a delivery is late, a boundary between two trades'
claimed territory in the market is disputed — and for a long time, the guilds settled this
the expensive way, through the Assayers' arbitration hearings, which could run for a season
and cost more in fees than the dispute was worth.

At some point — the guild ledgers don't agree on exactly when, and that's in keeping with the
institution, which trusts a stamped record over a story — two guilds with a stubborn dispute
over whose material made the better *tool* (the account usually named is the Founders and the
Smiths, brass versus iron) settled it instead with a public contest between their own working
partners: the sapient monsters who already hauled stone, hauled ore, and stood alongside
guild labour every day, and who by every account *wanted* to settle it that way as much as
their guilds did. The Assayers refereed, because grading disputes were already their trade.
It was fast, it was cheap, and — this is the part every guild history agrees on — the crowd
that showed up to watch a legal hearing get settled in an afternoon liked it more than the
verdict.

Guilds kept doing it. Within a generation it stopped being an alternative to arbitration and
became its own institution, chartered jointly, with its own grounds, its own graded ladder
borrowed wholesale from the material vocabulary everyone already spoke — and its own
governing body.

### The Assay Table

The Circuit is governed by **the Assay Table** — one seat per founding guild, chaired
(historically, not by rule) by the Assayers' Guild, since grading is what they've always
done. The Table sets the ladder, licenses Tamers, charters stables, and — uniquely — is the
*only* body that can award the top three titles (§5), because no single guild's material can
claim ownership of a rank that isn't a material at all.

⚠️ **No guild owns a league.** A Wood-league stable is not "owned" by whichever guild
sponsors it any more than a journeyman's guild owns their apprentice piece. The ladder ranks
**Tamer-monster partnerships**, not trades. A guild's material name being borrowed for a
league is vocabulary, not territory — see §2 for what a guild's own colours are actually for.

---

## 2. The guilds

Eight guilds, matching the eight livery colours and eight badge glyphs already shipped in
`monster-tamer/scripts/art.gd` (`TEAM_COLOURS` / `TEAM_BADGES`) — deliberately muted,
worn-cloth-and-enamel tones, chosen so they never collide with the game's brighter status
vocabulary. Every guild below is written to fit an existing colour, not to demand a new one.

⚠️ **Guild temperament is culture, not destiny.** Everything under "tends to sponsor" is a
recruiting bias and a training-room habit, never a rule the systems enforce and never a
ceiling on what a stable can produce — the same standing rule that keeps a species' training
aptitude from being a lock (`CLAUDE.md`). A Tanners' stable that raises a brilliant caster is
a good story precisely *because* it's not what their trainers reach for first, not because
it's impossible.

| guild | trade | colour | badge | temperament | tends to sponsor |
|---|---|---|---|---|---|
| **Quarriers' Guild** | building stone, roofing slate | slate blue `(0.20, 0.38, 0.62)` | ◆ | patient, unhurried, values endurance over flash — "cut once." Literally built most of the Circuit's own stands, stone by stone, over generations | defensive, attrition-first stables; bettors on the long game |
| **Tanners' Guild** | raw hide, cured leather, dye-vats | oxblood `(0.63, 0.26, 0.28)` | ▲ | loud, unglamorous, proud of a dirty trade, quick to feel looked down on by the "cleaner" guilds — scrappy, close-knit | aggressive, attrition-based stables; the guild most likely to back a rough, unfancied newcomer nobody else would |
| **Founders' Guild** | cast metal, alloys (brass, bronze work) | brass `(0.72, 0.58, 0.28)` | ● | technical, quietly superior about it — "anyone can dig ore; we make something new from it" | tactical, combination-minded stables; most likely to fund genuine gameplan research |
| **Glaziers' Guild** | glasswork, bottled goods, batch clarity | bottle green `(0.26, 0.46, 0.36)` | ■ | vain, image-conscious, obsessed with reading clean, genuinely good at putting on a show | fast, flashy stables; the guild whose bouts commentators like best |
| **Dyers' Guild** | textile dye, colourfastness | plum `(0.45, 0.33, 0.55)` | ★ | theatrical, colourful, and — this is load-bearing, see below — the guild that actually started the custom of wearing team colours | empowering, presentation-minded stables; showmen |
| **Assayers' Guild** | grading everyone else's goods; keeps the ledgers | chalk white `(0.78, 0.78, 0.80)` | ✦ | precise, self-important, the oldest and most respected guild, and the one every other guild both needs and slightly resents. Chairs the Assay Table | rarely sponsors directly (a conflict with judging), but when it does: control and disruption stables — reading and interrupting an opponent mid-fight, the way they'd read a batch |
| **Smiths' Guild** | worked iron, tools, hardware | iron grey `(0.35, 0.33, 0.31)` | ⬟ | biggest membership by far, gruff but fair, unglamorous backbone trade — "every guild owns a hammer we made" | the most stables of any guild, sheer numbers; broad, workmanlike, no single build identity |
| **Saddlers' Guild** | sport harness — wraps, sashes, the carrier every competitor wears into the ring | tan leather `(0.55, 0.40, 0.26)` | ✚ | young, sport-native, doesn't remember a Circuit that didn't exist yet; the most commercial-minded guild, closest to a modern sports-apparel outfit | mobile, technical stables; actively recruits first-time Tamers, since more competitors means more gear sold — the guild most newcomers affiliate with first |

### Two things worth knowing about this set

**The Dyers' Guild is why "Guild Colours" is the game's own name for itself, in-fiction.** A
team sash was, originally, a walking advertisement: a dye that could survive five rounds in a
ring without fading was a dye that could survive a customer's laundry, and the Dyers made
sure everyone knew it. What started as a trade demo became the single identifying mark every
competitor still wears. This is deliberate — it means the game's visual identity has an
in-world origin story rather than being an unexplained convention, and it costs nothing to
build because the art already exists.

**The Saddlers' Guild is the youngest, and that's on purpose.** Seven guilds predate the
Circuit; the Saddlers don't — they split off from the Tanners once sport gear (as opposed to
ordinary leatherwork) became a trade big enough to charter on its own. That gives the set a
real internal history — a parent guild and its breakaway, the Saddlers touchy about being
called "leftover Tanners," the Tanners insisting they taught them everything they know — and
explains why there are eight without every guild needing equal antiquity. It also means the
Saddlers are, mechanically, the guild responsible for the literal object the art bible calls
"the team-colour carrier" (§2 of `ART_BIBLE_GUILD_COLOURS.md`) — the sash, the wrap, the
dyed leg-band, the waxed thread. In-fiction, every one of those was made by a Saddler, dyed by
a Dyer, and the colour is the Saddlers' invoice as much as it's a competitor's pride.

### On team colour and guild colour — a note for whoever builds chartering

Today, `art.gd:team_colour(index)` assigns one of the eight liveries by **match slot**, not
by any persistent stable identity — practically necessary, and not wrong. The fiction above
is written so that a future system (a stable formally chartered under one guild, wearing that
guild's colour every match, the way a real trade apprentice wears their guild's mark) would
slot in without contradicting anything already built — it would simply give the existing
per-slot colour a persistent meaning it doesn't have yet. Flagging this as an open seam, not
proposing the mechanic; that decision belongs to `systems-designer` / `game-designer`.

---

## 3. What a Tamer is

A Tamer is an **apprentice**, in the plain trade sense, and the ladder is that apprenticeship
made visible. Nobody is born a Tamer any more than someone is born a mason; you're taken on.

- **Apprentice papers** are a Wood-tier licence, issued by whichever guild sponsors you —
  usually the Saddlers, who actively recruit newcomers, but any guild may take on a promising
  hopeful with no guild history at all. Guild membership by birth or bloodline is not a thing
  this world does; sponsorship is a decision a guild makes about a person, same as it's a
  decision a guild makes about who to admit to any other trade.
- **Journeyman standing** tracks the material ladder itself — Copper through Platinum are, in
  guild terms, exactly what they sound like: a journeyman's progress through the grades,
  proven the same way a journeyman proves it in any other trade, by producing work (here, a
  partnership) that survives being graded in public, repeatedly, against peers.
- **Reaching Masters is graduating.** Not a rank on the ladder in the same sense as the eight
  materials below it — a recognition, jointly given by the Assay Table, that this Tamer's
  partnerships are now good enough to teach from. See §5.

A Tamer's job, described plainly rather than heroically: they feed, train, and travel with
their partner; they read a partner's temperament and build a training week around it; they
decide tactics before a match and then, like every spectator in the stands, watch. That last
part is not incidental — it's the same posture the game asks of the player, and it's not a
coincidence. The Tamer *is* the player's fiction, not a separate character standing behind
them.

⚠️ **A Tamer does not own their partner.** This is not a soft aspiration — it's a hard legal
fact of the guild world, and it's the thing that makes §4 answerable at all. See below.

---

## 4. What the monsters get out of it

This is the question the whole premise depends on, so it gets a full answer rather than one
line.

The short version: **a Circuit licence is the guild world's mechanism for legal personhood,
and it was built for guildfolk, not for monsters — monsters compete to be written into a
system of standing that was never automatically theirs.**

The longer version, in five parts:

**1. Standing is earned and recorded here — for everyone, not just monsters.** This is the
single fact that makes the premise cohere: in this world, *nobody's* social standing is
automatic. A guild apprentice isn't a master until the ledgers say so; a batch of ore isn't
"gold-grade" until an Assayer stamps it; a Tamer isn't recognised until they're licensed. A
monster earning standing through competition isn't a special exception carved out for
monsterkind — it's the *same* mechanism every human tradesperson in this world lives under.
That's why it doesn't read as exploitative: the guilds didn't invent a different, lesser
system for monsters to prove themselves in. They let monsters into the *only* system there
is.

**2. The licence is the actual mechanism, and it's already a game term.** `PRESTIGE_BODIES`
gates Draconic/Abyssal species behind a Special Licence and Mythical behind an Elite Licence
— that's not just an economy gate, in-fiction it's the guild world's citizenship apparatus.
A licensed monster has a documented history, a name on record with the Assay Table, and the
travel and lodging rights that come with recognised standing in guild territory — the same
practical rights a chartered tradesperson has and an unlicensed stranger doesn't. An unlicensed
monster is not property and not an outlaw; it's simply *unrecorded*, the way an unlicensed
craftsperson is unrecorded, with all the friction that implies. Competing on the Circuit is
how that gets fixed, publicly, on the guilds' own terms — which is also why it's compelling
enough to choose.

**3. Craft pride is a real, sufficient motive on its own — the game already writes it that
way.** `BESTIARY.md` doesn't reach for standing or citizenship to explain why Kongrath fights;
it's simpler than that — he wants something worth guarding again. That's the same reason a
journeyman enters a guild contest: not survival, not coercion, just wanting to find out, in
public, whether the thing you've built yourself into is actually good. Every one of the 65
species already has an individual reason like this authored in the bestiary. This document
doesn't replace those; it gives them an institution to want something *from*.

**4. There's real material comfort in it, and the game already models the mechanism.** A
better-resourced stable feeds better food, affords the infirmary, and trains with better
knowledge — all things a monster can want and a Tamer can provide, without either side owning
the other. Climbing the ladder is climbing toward a materially better life, the same
unglamorous reason a real journeyman keeps working toward their master's papers: better
conditions, not just prestige.

**5. Consent runs all the way through, including into the next generation.** Breeding is
something a monster is asked about, not something done to it — a Hall-of-Famer's say in its
own retirement and in whether (and with whom) it produces the next generation is not a
mechanic to invent from scratch; it's the natural extension of "partner, not owner" into the
one place a lesser fiction would quietly drop it. A legendary competitor's name entering the
Hall of Fame is the monster's own legacy, not its Tamer's trophy.

⚠️ **What this deliberately does not do:** it does not claim monsters compete because they're
naturally warlike, because of a prophecy, or because a species is destined for the ring. Every
motive above is occupational and chosen — the same categories a human tradesperson would list
if you asked them why they do their job. That's the point.

---

## 5. The three title leagues

Where the eight material leagues are **grades**, Masters, Tamer Elite, and Tamers Apex are
**titles** — awarded, not measured, and only the Assay Table can award them, because by this
point no single guild's material vocabulary is doing the naming any more.

### Masters

Awarded jointly by the Assay Table to a Tamer-monster partnership whose record through Wood→
Platinum is judged, in guild language, **master work** — the same word a guild uses for the
piece a journeyman submits to stop being a journeyman. It is not a harder version of
Platinum; it's a different kind of recognition entirely: the Table is saying this partnership
is now good enough that other guildfolk should be able to point to it and know what
"excellent" looks like. A Masters win is recorded permanently in the guild ledgers — not the
Tamer's private trophy case, the actual shared record every guild consults.

### Tamer Elite

A further, rarer invitation: a Masters-titled Tamer is asked to sit alongside the Assayers on
actual grading matters — their read of a match, a build, a partnership, now counts toward how
the guilds judge *other* competitors. This is a title of authority as much as of skill, which
is why the game fields it at half the density of the leagues below (`town.ts:
activeQuartersFor()`) — it isn't diluted by being rare, it's *defined* by being rare. Very
few Tamers are ever asked to judge.

### Tamers Apex

The single highest title the Circuit awards, and — per `CLAUDE.md`'s standing rule — the
game's actual ending. What it means, stated plainly: **the guilds jointly declare this
partnership to be the Standard.** Not a champion in the sense of "strongest right now" — the
literal reference example, cited in grading manuals and training halls across every guild,
against which the *next* generation's work is measured, until a new Apex is crowned.

This is deliberately the same shape of reward the whole institution has been offering since
§1 — a world built around grading gives its ultimate prize as *becoming the thing everything
else gets graded against*. It's not a crown, it's not a prophecy fulfilled, and it doesn't
need to be — a craft world's highest honour is to be the measure other craftsmen use, and
that's exactly earned, never destined, in a way a throne never could be.

⚠️ **Recommend, don't require:** the Tamers Apex *league* is (per the standing 5v5 rule) one
interchangeable pool of grounds like every top league — but the Apex *title bout*, the match
that actually crowns a new Standard, reads better as staged at one singular, named venue
rather than any pool ground (§6 proposes **the Keystone**). This is a naming proposal, not a
mechanic — flag to `level-designer`/`systems-designer` if a distinct capstone venue is worth
building; this document doesn't decide that on its own.

---

## 6. Names and flavour

### Arena naming

Every league fields a *pool* of grounds, not one venue each (`ARENA_DESIGN.md`), so what
follows is a naming **pattern** plus a starter bank per league — material vocabulary first,
guild vocabulary where it fits, always grounded (a name a commentator would actually say on
air, never a name that reads like a spell).

**Pattern:** `[material/guild word] + [plain venue noun]` — Yard, Ring, Court, Hall, Gate,
Works, Common, Row. Avoid anything that reads as a fortress or a temple; these are venues, not
strongholds.

| league | starter bank |
|---|---|
| Wood | Fallow Field · Railside Common · The Green Yard |
| Copper | Coppergate · The Treeline Court · Coppersmith Row |
| Tin | The Tinworks · Solder Yard · Pale Court |
| Bronze | The Foundry Ring · Alloy Court · Castgate |
| Iron | Ironhold · The Forge Yard · Rivet Court |
| Silver | The Assay Court · Silvergate · The Weighing Yard |
| Gold | The Gilt Yard · Goldhall · Ledger Court |
| Platinum | The White Colonnade · Platinum Gate · The Canopy Court |
| Masters | The Masters' Chapter House · Mastergate · The Entablature |
| Tamer Elite | The Elect Bastion · Mosaic Court · Turret Gate |
| Tamers Apex | **The Keystone** (proposed singular capstone venue, see §5) |

### Guild names and colours (recap for quick reference)

| guild | colour swatch | badge |
|---|---|---|
| Quarriers' Guild | slate blue | ◆ |
| Tanners' Guild | oxblood | ▲ |
| Founders' Guild | brass | ● |
| Glaziers' Guild | bottle green | ■ |
| Dyers' Guild | plum | ★ |
| Assayers' Guild | chalk white | ✦ |
| Smiths' Guild | iron grey | ⬟ |
| Saddlers' Guild | tan leather | ✚ |

### The Circuit's seat

The Assay Table convenes at **the Ledger House**, in a city named here only provisionally as
**Gradehall** — enough to give the institution a home without pre-empting the wider geography
this document deliberately leaves open (see the note at the top of this file).

### Stable/team name bank

Generator-ready, loosely guild-flavoured but never guild-locked — any Tamer can name a stable
anything; these are drawn from the trades' own vocabulary the way real amateur teams borrow
from a local industry.

**Stone/Quarriers-flavoured:** Slateback · Quarry Row · The Cut Stone · Graniteside

**Hide/Tanners-flavoured:** Oxblood & Co · The Tannery · Rawhide Row · Hidebound

**Metal/Founders- & Smiths-flavoured:** Brassworks · Ironhand · The Cast Line · Rivet & Bar ·
Anvil Chorus

**Glass/Glaziers-flavoured:** Clearpane · Bottlegreen · The Batch · Kiln Light

**Dye/Saddlers-flavoured:** Plum & Thread · Fast Colour · The Wrap Line · Sash & Sinew ·
Dyeworks Eleven

**Assay/ledger-flavoured:** The Standard Bearers · Full Grade · Ledgerside · True Weight

**Generic / guild-neutral (the majority of real stables, since most aren't guild-chartered at
all):** Fallowfield Regulars · The Long Yard · Ring Eleven · Common Measure · Second Sons ·
The Apprentice Line · Weekday Circuit · No Guild in Particular (a real, deliberately wry name
a proudly unaffiliated stable might actually use)

---

## 7. Open items for narrative-director / future passes

- **Guild names, colours-as-fiction, and the founding story are new invention** and should be
  reviewed against any narrative-director material this document didn't have access to.
- **The Tamers Apex "Keystone" singular venue is a proposal**, not a decision — needs
  `level-designer`/`systems-designer` buy-in before anyone builds it.
- **Guild chartering as a persistent stable mechanic** (§2's closing note) is a flagged seam,
  not a request — surface to `systems-designer`/`game-designer` if a future meta-game pass
  wants team colour to mean something persistent rather than per-match.
- **Wider geography** (where Gradehall sits, what's beyond guild territory, how this meets
  the traversable-world work in `docs/DECISIONS_2026-08-03.md` #10b) is explicitly out of
  scope here and open for whoever picks it up.
