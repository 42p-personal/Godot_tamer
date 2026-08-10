# Class Rework — Assignable Classes with Per-Class Stat Caps

---

# ⚠️ ROUND 15 — THE FEATURE WAS MEASURED BEFORE IT WAS BUILT. READ THIS FIRST.

**2026-08-10 · instrument `monster-tamer/scripts/_probe_class.gd` + `scenes/_probe_class.tscn`**

```
cd monster-tamer
"P:/Godot_v4.7.1-stable_win64.exe" --headless --path . res://scenes/_probe_class.tscn -- --gym    # ~10s, exact
"P:/Godot_v4.7.1-stable_win64.exe" --headless --path . res://scenes/_probe_class.tscn -- --fight --salts 32   # ~60s
```

The probe **subclasses `_probe_shape.gd`** (which subclasses `_probe_career_arc.gd`) and overrides
exactly one method, the training brain. Everything else — the shipped weekly tick
(`week.gd:apply_activity`), the shipped kit draft (`monster_instance.gd:assign_moveset`), the
shipped rivals (`Career.make_league_rivals`) and the shipped fight (`battle_sim.gd`) — is
untouched, so an arm-to-arm difference can only be the arm.

## THE ANSWER IN ONE PARAGRAPH

**Assignable class, exactly as §1–§9 below specify it, is a DOWNSIDE-ONLY mechanic.** Measured
over 544 paired fights at four rungs, at an identical training-week budget calibrated so today's
naive player lands on `Career.expected_climber_fill`: committing to the best class and training
into it wins **73%** of rounds — against **75%** for the competent player who exists *today* and
picks nothing at all. **The feature is worth 0.97x.** Choosing between the *adjacent* classes the
gate would actually put on a player's menu is worth **0.99x**. Meanwhile committing to a bad class
costs **0.33x** and reassigning costs **0.03x**. So the mechanism as specified hands the player a
lever with no upside, a flat menu, and two ways to destroy a career — and the thing that
*genuinely* separates a good player from a bad one, the training brain, is **2.94x** and is
already available with no new mechanism whatsoever. ⚠️ **`docs/SHAPE_DIAGNOSIS.md`'s conclusion —
"assignable class is the mechanism by which the 14x becomes a decision the player makes" — does
not survive measurement, and this document is the retraction.**

## 1. THE DECISION TABLE — 544 paired fights, 32 salts, 4 rungs

Identical rivals and identical battle seeds in every arm. Every arm trains for the **same number
of weeks** — weeks are what a player actually spends, and `SHAPE_DIAGNOSIS.md` §3 is emphatic that
comparing at a constant stat *total* flatters the specialist by giving away the points its shape
costs. The week budget is calibrated per rung so **AUTO** (today's naive player) lands on
`Career.expected_climber_fill`, the ladder's own reference player.

| league | cap | wks | AUTO | AUTO-APT | RIGHT | NEIGHBOUR | WRONG | TRANSIT |
|---|---|---|---|---|---|---|---|---|
| Iron | 500 | 76 | 10% | 74% | 58% | 98% | 56% | 4% |
| Gold | 750 | 119 | 30% | 56% | 61% | 61% | 2% | 2% |
| Masters | 1000 | 157 | 18% | 89% | 79% | 50% | 23% | 1% |
| Tamers Apex | 1100 | 169 | 39% | 77% | 86% | 88% | 23% | 3% |
| **ALL** | | | **139/544 26%** | **408/544 75%** | **397/544 73%** | **392/544 72%** | **131/544 24%** | **12/544 2%** |

- **AUTO** — today's game, naive brain (biggest drill on the lowest stat), class DERIVED at exit,
  kit drawn from it. No caps.
- **AUTO-APT** — today's game, aptitude brain. Class still derived, kit still automatic.
  **⚠️ This arm requires no new mechanism at all. It is available to a player right now.**
- **RIGHT** — class ASSIGNED to the aptitude-best trade, per-class caps on, trained into it, kit
  drawn from the assigned class. The feature, used perfectly.
- **NEIGHBOUR** — assigned to a class sharing the primary stat but not the secondary: the adjacent
  entry on §2.2's own gate menu (its worked example opens Warrior/Skirmisher/Rogue at once).
- **WRONG** — assigned to a class sharing neither stat with the aptitude-best trade, then trained
  into it *honestly*. Stats and kit AGREE; the only cost is a body fighting its own aptitudes.
- **TRANSIT** — trained into the RIGHT class exactly as arm RIGHT, then reassigned. Kit redrawn
  from a class the body has none of the stats for. **This is `SHAPE_DIAGNOSIS.md` arm D reached by
  a route a player can actually take**, and the only place the 14x lives.

```
AUTO     -> AUTO-APT  = 2.94x    TODAY's competent player. No new mechanism.
AUTO     -> RIGHT     = 2.86x    the assigned build vs today's naive one
AUTO-APT -> RIGHT     = 0.97x    <- ⚠️ THE ONLY NUMBER THAT PRICES THE FEATURE
RIGHT    -> NEIGHBOUR = 0.99x    the spread ACROSS the menu the gate offers
RIGHT    -> WRONG     = 0.33x    committing to a class the body fights
RIGHT    -> TRANSIT   = 0.03x    reassignment, on the day it is made
```

⚠️ **`AUTO -> RIGHT = 2.86x` IS THE NUMBER THAT WOULD HAVE SOLD THIS FEATURE, AND IT IS A
CONFOUND.** It is not the class assignment: it is the training brain, and `AUTO -> AUTO-APT` is
2.94x for the same reason with nothing built. Every point of RIGHT's advantage over AUTO is
purchasable today by training the stat the monster is good at. **Do not quote 2.86x.**

⚠️ **NEIGHBOUR is flat in aggregate (0.99x) but swings 0.63x–1.7x per rung with no consistent
direction** (98% at Iron, 50% at Masters). That is worse than a flat menu, not better: it means
the choice between two adjacent classes *does* change the outcome, but not in a direction the
player can learn. A coin flip wearing a decision's clothes is the exact failure `CLAUDE.md` names
— *"an unreadable fight is not a hard fight, it is a slot machine."*

## 2. THE CAP TABLE — per-class caps are INERT where the game is won

`--gym`, exact, no fights: 10 bodies, 336 weeks (a full trainable career), swept across the
ladder's own caps. `spread` is `(max−min)/mean`; a `_shape_to_class` rival — the body every rival
on the ladder is built as — sits at **0.475**.

| rung (cap) | arm | total | vs naive | spread |
|---|---|---|---|---|
| **Iron (500)** | naive, no caps | 2994 | — | 0.01 |
| | naive + TIGHT `{1.00/0.90/0.70}` | 2426 | **−19.0%** | **0.40** |
| | naive + ARCHETYPE `{1.35/1.15/0.70}` | 2716 | −9.3% | **0.70** |
| **Gold (750)** | naive, no caps | 4480 | — | 0.02 |
| | naive + TIGHT | 3613 | **−19.4%** | **0.39** |
| | naive + ARCHETYPE | 4038 | −9.9% | **0.72** |
| **Masters (1000)** | naive, no caps | 4567 | — | 0.03 |
| | naive + TIGHT | 4575 | **+0.2%** | 0.23 |
| | naive + ARCHETYPE | 4579 | +0.2% | 0.22 |
| **Tamers Apex (1100)** | naive, no caps | 4567 | — | 0.03 |
| | naive + TIGHT | 4568 | **+0.0%** | **0.04** |
| | naive + ARCHETYPE | 4568 | +0.0% | **0.04** |

⚠️ **THE CONSTRAINT INVERTS ALONG THE LADDER, AND THIS IS THE SINGLE MOST IMPORTANT STRUCTURAL
FINDING IN THE ROUND.** Per-class caps expressed as a *fraction of the league cap* bite hard at
Iron and Gold — where they cost the naive player a fifth of its points and force a spread of 0.40
— and **do literally nothing at Masters and Tamers Apex**, the rungs where careers are actually
decided (`SHAPE_DIAGNOSIS.md` §4: every losing career stalls at Platinum or above).

The mechanism is arithmetic, not tuning. A full career banks ~4,450 points
(`_probe_training.gd` §1); six stats at the Apex cap of 1100 is 6,600. **A naive body at Apex
reaches 761/stat against an off-class ceiling of 770 — the cap misses by nine points.** It is not
a ceiling; it is a ceiling painted on the sky. `week.gd`'s own round-14 comment already said so —
*"the total budget does not bind today, deliberately… If a future career ever reaches it, that is
the moment `docs/CLASS_REWORK.md`'s per-class caps become load-bearing rather than optional"* —
and this is the measurement of that sentence. **The moment has not arrived.**

⚠️ **This is CLAUDE.md's named genre failure — inverted progression, where the capstone asks less
than the starter.** Shipping §4.1 as written would put the game's only anti-generalisation
constraint on Wood-through-Gold, the rungs that exist *to teach and to pace*, and remove it from
Masters-through-Apex, the ship target.

⚠️ **AND `TIGHT {1.00 / 0.90 / 0.70}` — §4.1 EXACTLY AS WRITTEN — WOULD PARTLY UNDO ROUND 14.**
`week.gd:stat_ceiling` (shipped 2026-08-09) lets a committed body push one stat to
`SPIKE_HEADROOM 1.35 × nominal` out of a shared `6 × nominal` budget. That change is what took a
real specialist from **4/24 careers to 26/32** — from a trap to a build. A primary tier of 1.00
hands the headroom straight back. **If per-class caps ship at all, the primary/secondary tiers
must be `{1.35, 1.15}` — `roster.gd:SHAPE_PRIMARY` / `SHAPE_SECONDARY`, the exact archetype vector
every rival is already built from — with the restriction landing where the rework actually wants
it: on the four OFF-class stats.** Measured, ARCHETYPE preserves nearly twice as much of a naive
player's points as TIGHT (−9.3% vs −19.0%) while forcing nearly twice the spread (0.70 vs 0.40).
It is better on both axes; TIGHT is dominated.

## 3. WHAT I VERIFIED AND WHAT I REFUTED IN THE ROUND BRIEF

**Verified.**
- `monster_instance.gd:recompute_class()` overwrites all four derived fields unconditionally, and
  `week.gd:580` calls it inside `apply_activity` **every week on the shipped path**. A stored
  choice put anywhere near it is erased before the player sees it. The probe had to re-stamp the
  class after every single simulated week to keep it alive — that is not a workaround, it is the
  finding.
- `class_for_stats` is under contract: `data/classify.json`, 46 cases, 4 axes, exact equality.
- `Generalist` is the 19th class, is absent from `GameData.classes` (18), is `class_name_`'s own
  default, and its kitless bug is guarded by `_probe_career_loop.gd:_phase_every_class_can_arm`
  which rolls call off **`classBasic`**, not off `GameData.classes`.
- "No species is locked out of a role" is a live, tested claim:
  `_probe_archetypes.gd:128`, which shapes **every species into every archetype class** and
  asserts zero misses plus <0.5% stat-total drift.

**Refuted.**
- ⚠️ **"KIT ALIGNMENT IS THE LARGEST LEVER IN THE GAME AND THE PLAYER CANNOT TOUCH IT."** The
  first half is true; the second half does not lead where the brief takes it. Derivation makes
  the kit follow the STATS; assignment makes it follow the CHOICE. **Either way they agree the
  moment the player trains toward the class they picked.** Misalignment — the 4%, the 14x —
  requires stats and kit to *disagree*, which under assignment happens only in TRANSIT. The 14x is
  therefore not an upside the feature unlocks; it is a **cliff the feature installs**.
- ⚠️ **"The one proposal with an effect size large enough to carry *knowing WHICH monster to make
  is the skill*."** Measured at 0.97x over a player who chooses nothing. The effect size is zero.
- **"Putting the commitment in the player's hand"** does not produce a skill gap, because the gap
  it would produce already exists and the ladder does not convert it: today's fight already
  discriminates **2.94x** between the naive and the competent training brain, and
  `SHAPE_DIAGNOSIS.md` measures both completing careers at an identical **87.5%**. ⚠️ **A
  mechanism that widens a fight-level gap the career converts to zero will also convert to zero.
  The bottleneck is the LADDER'S CONVERSION, not the availability of the lever.** That is the
  round's most actionable sentence and it is not about classes at all.

**Not measured, and therefore not claimed.**
- **Careers.** Everything above is round win-rate at a fixed rung, not `Career.won_game`. The
  cheap sections were run first precisely so the round could stop before paying for the expensive
  one. Given the 0.97x, a career run would be measuring noise.
- **Legibility and agency.** A player who *chooses* their monster's trade may enjoy the game more
  at an identical win rate. That is real, it is `CLAUDE.md`'s stated fantasy, and **no probe in
  this repository can measure it** — `docs/OUTSTANDING.md` §3 already names the absence of a
  single playtest record as the project's biggest unchecked assumption. See §11.
- Whether a redesigned gate offering *genuinely different* classes (rather than adjacent ones)
  would produce a real menu. NEIGHBOUR says adjacency does not; nothing here says a wider menu
  could not.

## 4. THE VERDICT, AND WHAT SHOULD HAPPEN INSTEAD

**Do not build §1–§9 as specified.** Three named reasons, in order of size:

1. **There is no upside to buy** (0.97x), and the confound that looks like one (2.86x) is the
   training brain, free today.
2. **The caps are inert exactly where the game is won** and punitive exactly where it is taught —
   an inverted difficulty gradient (§2).
3. **The downside is career-ending and arrives by accident**, not by a bad strategic read:
   TRANSIT at 0.03x is what a player gets for pressing "reassign" on a trained monster.

⚠️ **BUT THE USER'S DECISION OF RECORD IS NOT REFUTED — ITS MECHANISM IS.** *"A class can be
ASSIGNABLE and that will have its own STAT CAPS on top, to ensure we can't get too much
generalisation"* is a statement about **generalisation**, and generalisation is real and
measurable: the naive player's spread is **0.03**, against **0.475** for every rival on the
ladder, and that player completes the game 87.5% of the time. The finding is that
**assignment is the wrong lever for it and the cap is aimed at the wrong number.** §10 is what to
build instead, in the order the evidence supports.

---

**2026-08-03, revised same day.** First pass was a systems design proposal written for the
coordinator; this revision turns it into a **buildable specification**, incorporating the
decisions recorded in `docs/DECISIONS_2026-08-03.md`. Everything marked ⭐ PROPOSAL or with an
explicit number is still unmeasured — the balance baseline is suspended — but the STRUCTURE
below is no longer "my recommended default, alternatives kept alongside": it is what the
Godot rebuild should implement, with any remaining open calls marked ⚠️ and listed in §9.

⚠️ **THIS REPLACES A STANDING RULE.** `CLAUDE.md` currently says *"Classes are emergent, not
species-locked … `classForStats()` derives class from a monster's two CURRENT highest stats,
recomputed fresh every time — never stored, never a species identity."* That rule bought real
plasticity: "any species can train into any class" is a tested claim in this game, not flavour
text. This document does not discard the reason that rule existed — it changes the *mechanism*
class identity runs on, from a live derivation to a stored, player-chosen field, gated by
current stats rather than freely picked (§2), so a cap can be hung off it without becoming
self-reinforcing (§0).

⚠️ **THE BALANCE BASELINE IS SUSPENDED.** Per `CLAUDE.md`, this document specifies *structure*.
Every number here (cap multipliers, gate thresholds, floor fractions) is unmeasured and must be
simmed against `tools/sweep40.ts` at the deliberate re-baseline, one value at a time, per the
standing balancing rule — not before.

⚠️ **This lands in Godot.** File:line references below are to the CURRENT TypeScript engine —
they anchor the spec in something concrete and buildable today, and double as the map of what
the Godot port needs to carry over conceptually. They are not a constraint on the Godot
implementation's actual file layout.

---

## 0. Why this is safe now — resolving a known objection

`docs/TACTICS_BRAINSTORM.md` §5.2 already investigated per-class stat caps and rejected the
naive version as **circular**: class is derived from the two highest stats, so training STR
raises STR's own cap by making the monster a Warrior — self-reinforcing, not constraining. That
document's own fix was Option D (species aptitude as a ceiling modifier, not just a rate one) —
**superseded below.** Decision (`DECISIONS_2026-08-03.md` #9): *"Species aptitude = RATE. Class
cap = CEILING. Separate axes, no collision. DROP the earlier proposal to also make aptitude a
ceiling modifier — one ceiling system is enough; two would over-constrain and be unreadable."*
§4's cap formula is therefore the ONLY ceiling multiplier stat training passes through, besides
the existing league/potential/gen-1 stack.

Making class a **stored, assignable** field rather than a live derivation means a cap keyed to
it no longer feeds back into itself: assigning "Warrior" doesn't change what a monster's stats
*are*, so there is nothing for the cap to reinforce. The **stat gate** (§2) adds a second,
independent reason this is safe: a monster cannot simply assign its way into a cap it hasn't
earned any shape toward — the gate requires the stats to already look roughly like the class
before the class can be chosen, so "assign Tank to a glass cannon" (CLAUDE.md's own genre
failure-mode language) is structurally blocked, not just discouraged.

---

## 1. The model — how a class is assigned

### 1.1 CONFIRMED: species default + paid reassignment, gated by current stats (A1 + gate)

- Every species keeps a default class at generation — today's `naturalClass`, repurposed from "a
  fact `validate.ts` checks against base stats" into "the class a wild-generated monster of this
  species starts with." A Mammal still generates looking like a Warrior by default; the flavour
  signal 65 species currently carry for free is not lost. **Default assignment bypasses the gate
  entirely** — it is not a player choice, so there is nothing to gate.
- The player may **reassign** a monster's class at any time thereafter, for a **gold cost — left
  as TBD**, chosen only from the classes the monster's CURRENT stats qualify it for (§2). ⚠️
  Inventing a reassignment price here would be worse than an honest gap: `CLAUDE.md`'s roadmap
  explicitly defers the economy rebalance until every sink/source is in, "so it's balanced
  against reality in one pass." A reassignment price belongs in that pass.
- **Reassignment never retroactively shrinks a trained stat.** If a stat is already above the new
  class's cap for it, it freezes there — no further gain in that stat until the class changes
  again or the monster's bloodline potential rises — but it is never reduced. Respec-punishment is
  a well-worn RPG failure mode and there is no reason to import it here.
- **Losing gate-eligibility for your OWN currently-assigned class does not un-assign it.** Stats
  only grow, never shrink, so a monster CAN eventually train a third stat past its assigned
  class's primary and technically fail the gate test if re-evaluated — this is never checked
  retroactively. The gate fires once, at the moment of a NEW assignment or reassignment, never as
  a standing condition. (See §2.4 for why this can't be exploited.)

### 1.2 Alternatives considered (unchanged from the first pass, still on file for the record)

| option | mechanism | trade-off |
|---|---|---|
| **A2 — no default, mandatory Class Trial** | Every new monster is `Unclassed` (= today's Generalist) until the player deliberately assigns a class via an event mirroring the existing rank-up trial. | Makes the choice explicit from turn one. Costs the species-flavour signal — a Mammal no longer *looks* like anything until assigned. |
| **A3 — fixed at birth, no reassignment** | Class is chosen once at generation (or inherited at breeding) and never changes. | Simplest possible cap math, no respec economy to design. But "assignable" implies *re*-assignable — this reads as a smaller change than what was asked for. |

**A1 stands, now WITH the gate** — it preserves the flavour value of the current system, makes
the choice a real one bounded by what the monster's stats actually support, and turns
reassignment into a legitimate future economy sink.

### 1.3 What happens to a monster already trained

Nothing changes about the STATS themselves on migration or reassignment — only the ceiling above
them moves. A monster with STR 950 reassigned into a class whose cap on STR is 886 keeps its 950
and simply cannot gain further STR until that changes. This is deliberate: converting an existing
save's stat block into "wasted" investment the day this ships would be a worse first impression
than any amount of design purity.

---

## 2. The stat gate

**Decision (`DECISIONS_2026-08-03.md`, carried forward as #8):** *"assign class gated by stats
rather than freely — the user's own counter-proposal, and it is better than free assignment."*
The mechanism below is new in this revision; it did not exist in the first pass.

### 2.1 What the gate has to do

Three requirements, all stated directly by the coordinator's framing of the decision:

1. **Keep agency** — the player still chooses; the gate narrows the menu, it does not replace
   the choice with a single forced answer (that would just be `classForStats()` wearing a UI).
2. **Keep stats meaningful** — a class should not be assignable to a monster whose stats bear no
   resemblance to it. Assigning Tank to a glass cannon must be impossible, not merely a bad idea.
3. **Give training a goal** — a stat that isn't yet prominent enough to unlock a class is a
   concrete, legible thing to train toward. This is the one requirement with no equivalent in the
   old emergent system, where "the class" was just whatever fell out passively.

### 2.2 ⭐ PROPOSAL: rank-and-floor gate

> ⚠️ **ROUND 15 MEASURED THE MENU THIS GATE PRODUCES AND IT IS FLAT.** The gate's own worked
> example (§2.3) opens Warrior / Skirmisher / Rogue on one body — adjacent classes sharing a stat.
> Measured over 544 paired fights, choosing between adjacent classes is worth **0.99x**, and
> per-rung it swings 0.63x–1.7x with no learnable direction. The gate is buildable exactly as
> written (§10.3) and `GATE_FLOOR = 0.20` is measurably too low, but **a gate that offers a menu
> of interchangeable options is a menu, not a decision.** §11.2 is the prerequisite.

**A monster qualifies for class `C` (primary stat `P`, secondary stat `S`, from `CLASSES`) iff
ALL of:**

1. `rank(P)` ≤ 1 (0-indexed) — **`P` is one of the monster's two highest current stats.**
2. `rank(S)` ≤ 2 (0-indexed) — **`S` is one of the monster's three highest current stats.**
3. `stats[P] ≥ GATE_FLOOR × statCapFor(career)` — **`P` isn't just relatively prominent, it's
   absolutely trained.** Proposed `GATE_FLOOR = 0.20`.

Ties are broken by fixed stat priority, matching the array order `STATS` already uses everywhere
else in the codebase (`STR, DEX, CON, WIS, INT, CHA`) — the same order `classForStats()`'s sort
already relies on for stability, so this needs no new convention.

**Pseudocode** (implementable directly from this block — no hand-waving):

```
function classesAvailableFor(stats: Stats, career: Career): string[] {
  const ranked = [...STATS].sort((a, b) => stats[b] - stats[a])   // descending, stable on ties
  const rank = (s: Stat) => ranked.indexOf(s)                      // 0 = highest
  const floor = GATE_FLOOR * statCapFor(career)
  return CLASSES
    .filter(c => rank(c.primary) <= 1 && rank(c.secondary) <= 2 && stats[c.primary] >= floor)
    .map(c => c.name)
  // Generalist carries no ClassDef entry and is never gated — it is offered
  // separately in the UI as the always-available, honestly-worse fallback (§8).
}
```

**Why "top-2 primary / top-3 secondary" and not an exact ordered-pair match:** an exact match
(`rank(P)=0 AND rank(S)=1`, i.e. today's `classForStats()` test) reduces to "the monster
qualifies for exactly the one class it would have emergently become, or none" — that's `A2`
wearing a costume, not a gated CHOICE. Loosening `P` to top-2 (either rank 0 or 1) and `S` to
top-3 means a monster whose top three stats are, say, STR/DEX/CON typically opens **several**
adjacent classes at once (§2.3, worked example A) — the menu the coordinator asked for.

**Why a floor at all:** without it, a Wood-league monster minutes after generation, whose six
stats are all in the teens with no real separation, could still satisfy the RANK test trivially
(some stat is always "top-2" of six, however flat the spread). The floor requires that stat to
already represent real investment relative to the league's own ceiling, which is what makes
"train toward a class" a genuine mid-game goal rather than a technicality that's already true on
day one.

**All three constants (`0.20` floor, top-2/top-3 rank thresholds) are GATE knobs** in the
project's existing feel/curve/gate taxonomy (`CLAUDE.md` tuning-knob methodology) — they set
pacing, not moment-to-moment feel or a progression curve's shape, and belong in the same
external-data-file discipline as every other exposed number. **Unmeasured, proposals only** —
queued for the re-baseline alongside the cap multipliers (§4.5).

### 2.3 Worked examples

**Example A — qualifies for several.** A Bronze-league monster (`statCapFor` = 400, potential
1.0, floor = 0.20×400 = 80) with `STR 380, DEX 340, CON 210, WIS 90, INT 70, CHA 60`
(ranks: STR=0, DEX=1, CON=2, WIS=3, INT=4, CHA=5):

| class | primary/secondary | rank(P) | rank(S) | `stats[P]` ≥ 80? | qualifies? |
|---|---|---|---|---|---|
| Warrior | STR/CON | 0 ✓ | 2 ✓ | 380 ✓ | **yes** |
| Skirmisher | STR/DEX | 0 ✓ | 1 ✓ | 380 ✓ | **yes** |
| Rogue | DEX/STR | 1 ✓ | 0 ✓ | 340 ✓ | **yes** |
| Captain | STR/CHA | 0 ✓ | 5 ✗ | — | no |
| Ranger | DEX/INT | 1 ✓ | 4 ✗ | — | no |
| Tank | CON/STR | 2 ✗ | — | — | no |

This monster — trained hard into STR and DEX, with CON as a distant third — opens **Warrior,
Skirmisher and Rogue**: three real, meaningfully different choices (Strike/Protect vs pure Strike
vs pure Strike with a different pairing — see §3), all earned by the same training path. That is
the "training has a goal, and the goal opens a real menu" behaviour the gate exists to produce.

**Example B — qualifies for none.** An Iron-league monster (`statCapFor` = 500, potential 1.0,
floor = 0.20×500 = 100) trained broadly toward `CON 320, CHA 300, INT 260, STR 150, WIS 140,
DEX 110` (ranks: CON=0, CHA=1, INT=2, STR=3, WIS=4, DEX=5) — a CON/CHA/INT hybrid, deliberately
picked because **no class in the 18-entry table pairs CON with CHA in either order** (checked
against the full `CLASSES` table in §3):

Every one of the 18 classes fails at least one gate condition for this stat spread — CON-primary
classes (Tank, Spellshield) need STR or WIS in the top three and get neither; CHA-primary classes
(Orator, Bard, Herald) need WIS, DEX or STR in the top three and get none of them; INT-primary
classes (Wizard, Spellsword, Evoker) need INT itself to be top-2 and it's rank 2. **This monster
qualifies for zero of the 18 — only Generalist is available**, until further training either
pushes CON/STR together (Tank) or CHA/WIS together (Orator) or similar.

This is not a contrived edge case to pad the spec — it's a genuine finding: **the 18-class table
has no CON+CHA class**, the same kind of coverage gap the "orphan-pair seven" pass (`core.ts`
comment, 2026-07-30) already found and partly fixed for other pairings. Not fixed here — flagged
for §9, since adding a 19th class is a bigger call than this document is scoped to make alone.

### 2.4 Can the gate be gamed?

Training is monotonic (stats only rise) and the gate is evaluated fresh at each
assignment/reassignment attempt, so there's no sequencing exploit: a player cannot "gate into"
a class early and then let other stats overtake it to dodge some later restriction, because the
gate check only ever runs at the moment of a NEW choice, never continuously (§1.1). The floor
(§2.2, condition 3) is the one place a player *could* try to game the number by training a stat
just past `0.20 × statCapFor` and no further purely to unlock a class cheaply — this is an
accepted, intended use of the gate (it IS "training toward a class"), not an exploit.

---

## 3. Doctrine — the seven-doctrine palette and the full 18-class table

### 3.1 Why doctrine needed a bigger palette

The first pass used four doctrines (Control/Sweep/Strike/Anchor), built entirely from existing
`Tactics`/`FieldTraits` levers with no new engine surface — that mechanism is unchanged and still
the right shape (§5). But forcing every class into ONE of four tags flagged six classes as
genuinely ambiguous (Ranger, Wizard, Spellsword, Stalker, Bard, Swashbuckler) and left Control
owned by exactly one class. **Decision (`DECISIONS_2026-08-03.md`):** *"A third of the roster not
fitting the model is evidence against the model, not against those classes."*

The fix has two parts, both already decided:

1. **Primary + secondary doctrine per class**, mirroring the primary/secondary STAT pair the
   class system already uses — "the same shape the class system already uses," costs nothing
   structurally. ⚠️ **The secondary is a TIEBREAK WEIGHT, never a second full behaviour** — two
   rules per class, not three, per the no-intervention requirement.
2. **The support division folds in as three more doctrines**, not new taxonomy: `CLAUDE.md`
   already states *"Support is divided by KIND, not by amount: CHA empowers · CON protects · WIS
   restores."* Naming these **Empower / Protect / Restore** and adding them to the doctrine set
   gives every support-flavoured class (currently forced into a vague "Anchor") a precise home.

**The seven doctrines:** Control · Sweep · Strike · Anchor · Empower · Protect · Restore.

| doctrine | wants | expressed via (existing levers only) |
|---|---|---|
| **Control** | deny the enemy's actions | `ccPriority: true`; denial-line affinity (Disruptor, Warden, Enchanter, Demagogue, Hexer) |
| **Sweep** | hit/afflict the WHOLE enemy side | loadout-pick weighted toward `allEnemies`/`frontRow`/`backRow`; `targetPriority` left unset |
| **Strike** | remove ONE target fast | `comboRole: 'detonate'`; `burst: 'nuke'`; high `predation` bias |
| **Anchor** | outlast — survive and grind, unaffiliated with any support kind | `preserve` bias toward `cautious`/`defensive`; high `cohesion`, low `predation` |
| **Empower** | make an ALLY stronger | CHA's kind of support — the Captain line, buffs |
| **Protect** | shields and prevention | CON's kind of support — the Guardian/Bulwark lines |
| **Restore** | healing and cleansing | WIS's kind of support — the Mender/Siphon lines |

### 3.2 The line→doctrine mapping (the evidence base for every class row below)

Each of the 18 ability lines (`src/lines.ts`) is assigned exactly one doctrine, based on its
actual move content (cited in `lines.ts`'s own comments and `CLAUDE.md`'s findings, not
re-guessed here):

| stat | line | doctrine | why |
|---|---|---|---|
| STR | Bloodrage | Strike | HP-spend berserker, single-target aggression |
| STR | Duelist | Strike | single-target finishers |
| STR | Warcry | Sweep | Cleave/Whirlwind/Earthshaker are AoE; the line's other moves (Guard/Intimidate) are threat, not denial |
| DEX | Assassin | Strike | single-target burst/backstab, by name |
| DEX | Venomcraft | Strike ⚠️ *flagged* | patient poison-stacking — doesn't cleanly mean "fast"; see §3.5's known gap |
| DEX | Volley | Sweep | multi-hit/pin, confirmed AoE-leaning by `focus.ts`'s own top-share measurement |
| CON | Warden | Control | zone denial — Seize, Earthen Grasp, Zone of Control, knockback |
| CON | Guardian | Protect | team shields/taunt/thorns — the flagship mass-taunt+thorns combo |
| CON | Bulwark | Protect | self-fortify (Brace, Bastion, Fortify, Retaliate) |
| WIS | Disruptor | Control | silence/debuff/denial, the line built specifically to fix Control's starvation |
| WIS | Mender | Restore | heal, by name |
| WIS | Siphon | Restore | drain/life-transfer — sustain through transfer |
| INT | Hexer | Control | curses/debuffs |
| INT | Elementalist | Sweep | **5-of-7 moves area-effect** — CLAUDE.md's own cited finding, the most AoE-saturated line in the pool |
| INT | Arcanist | Strike | single-target execute tools (Void Lance, Unmake) |
| CHA | Enchanter | Control | mass debuff/charm |
| CHA | Captain | Empower | team buffs, by name |
| CHA | Demagogue | Control | mass debuff/provocation (Mass Hysteria, Crowd Surge) |

### 3.3 The full 18-class table

**Doctrine PRIMARY is read off the class's PRIMARY stat's lines** (dominant by content, or by
`CLASS_LINES`' own authored order where a stat's lines split evenly — that array order is
hand-curated per class, not auto-generated, so it carries real signal). **Doctrine SECONDARY is
read off the class's SECONDARY stat's line**, when it differs from primary; where the secondary
stat's line duplicates the primary tag, the secondary slot is either left empty (doctrine-pure)
or, in two cases (Orator, Swashbuckler shares don't apply — see notes), filled from a minority
line within the primary stat where that's demonstrably where the real ambiguity lived. Every
non-mechanical judgement call is called out in the Notes column.

| class | stats (P/S) | doctrine (P/S) | `CLASS_BASIC` (channel·range·stat) | `CLASS_LINES` | notes |
|---|---|---|---|---|---|
| **Tank** | CON/STR | **Protect / Sweep** | melee·3.0·CON | Guardian, Warden, Warcry | Guardian(Protect) listed first among CON lines; Warden(Control) is a real minority flavour not captured by the 2-slot model — flagged, not lost. |
| **Warrior** | STR/CON | **Strike / Protect** | melee·3.0·STR | Duelist, Bloodrage, Bulwark | Unanimous Strike from both STR lines; Bulwark(CON) gives Protect cleanly. |
| **Rogue** | DEX/STR | **Strike / —** | melee·3.0·DEX | Assassin, Venomcraft, Duelist | All three lines tag Strike (Venomcraft flagged, §3.5) — doctrine-pure by name, per the first pass's own reading. |
| **Ranger** | DEX/INT | **Sweep / Strike** | ranged·8.0·DEX | Volley, Assassin, Elementalist | Volley (listed first, dominant DEX line) → Sweep; Assassin (DEX minority) → Strike. Resolves the flagged ambiguity exactly as anticipated — the tension was WITHIN DEX, not between stats. |
| **Sage** | WIS/INT | **Restore / Control** | support·6.0·WIS | Mender, Siphon, Hexer | Mender+Siphon unanimous Restore; Hexer(INT) → Control. |
| **Wizard** | INT/WIS | **Sweep / Control** | magic·7.0·INT | Hexer, Elementalist, Arcanist, Disruptor | Elementalist's 5-of-7 AoE share makes it the dominant INT line despite Hexer being listed first; Disruptor(WIS) → Control. Resolves the flagged Sweep-vs-Control tension. |
| **Spellsword** | INT/CON | **Strike / Protect** | melee·3.0·INT | Arcanist, Elementalist, Bulwark | Arcanist's single-target execute tools read as precision strike over Elementalist's AoE; Bulwark(CON) → Protect. Protect is a strictly more precise replacement for the vague "Anchor" pull the first pass flagged here. |
| **Spellshield** | CON/WIS | **Protect / Restore** | melee·3.0·CON | Guardian, Bulwark, Warden, Mender | Guardian dominant CON line → Protect; Mender(WIS) → Restore. "Spellshield" reads literally as shield+heal. |
| **Captain** | STR/CHA | **Sweep / Empower** | melee·3.0·STR | Captain, Warcry, Duelist | Warcry is the PRIMARY stat's (STR) dominant line → Sweep; the eponymous Captain line is the SECONDARY stat's (CHA) contribution → Empower. |
| **Orator** | CHA/WIS | **Control / Empower** | support·6.0·CHA | Demagogue, Enchanter, Captain, Disruptor | 2-of-3 CHA lines (Demagogue, Enchanter) → Control, the clearest Control class in the pool; WIS's Disruptor duplicates Control, so the secondary slot draws from the CHA-minority Captain line instead → Empower. |
| **Bard** | CHA/DEX | **Control / Sweep** | support·6.0·CHA | Captain, Enchanter, Demagogue, Volley | Same CHA majority as Orator (2-of-3 Control) → Control; DEX's Volley → Sweep. Bard and Orator share a primary but differ in secondary exactly where their 4th line differs — resolves the flagged ambiguity precisely. |
| **Evoker** | INT/DEX | **Sweep / —** | magic·7.0·INT | Elementalist, Arcanist, Volley | Elementalist dominant → Sweep; Volley(DEX) duplicates Sweep → doctrine-pure, "no ambiguity" per the first pass. |
| **Skirmisher** | STR/DEX | **Strike / —** | melee·3.0·STR | Bloodrage, Duelist, Assassin | Unanimous Strike across all three lines. |
| **Stalker** | DEX/WIS | **Strike ⚠️ / Restore** | ranged·8.0·DEX | Assassin, Venomcraft, Siphon | ⚠️ **The least comfortable primary tag in the table** — neither Assassin(burst) nor Venomcraft(patient) is cleanly "fast." Siphon(WIS) → Restore, matching the class's own code comment: "the patient hunter, poisons and drain." See §3.5. |
| **Swashbuckler** | DEX/CHA | **Sweep / Control** | melee·3.0·DEX | Volley, Assassin, Demagogue | Volley (listed first) dominant DEX line → Sweep; Demagogue(CHA) → Control. Note: the first pass folded Demagogue into reinforcing Sweep ("provocation… outweigh Assassin") — this revision gives Demagogue its own correct home (Control) instead, which the 7-doctrine palette makes possible. "Flash and provocation" (the line file's own flavour text) now reads as a literal Sweep/Control match. |
| **Shaman** | WIS/CON | **Restore / Protect** | support·6.0·WIS | Mender, Disruptor, Guardian | Mender dominant WIS line → Restore; Guardian(CON) → Protect. Matches the class's own code comment: "the healer that also holds ground." |
| **Mystic** | WIS/DEX | **Restore / Strike ⚠️** | support·6.0·WIS | Mender, Siphon, Venomcraft | Mender+Siphon unanimous Restore; Venomcraft(DEX) → Strike, flagged (§3.5) same as Rogue/Stalker. |
| **Herald** | CHA/STR | **Empower / Sweep** | support·6.0·CHA | Captain, Demagogue, Warcry | Captain (listed first) dominant CHA line → Empower; Warcry(STR) → Sweep. **Deliberate mirror of Captain** (Sweep/Empower ↔ Empower/Sweep) — Herald and Captain are the CHA/STR ↔ STR/CHA inverse pair and their doctrine order mirrors it exactly, matching the code's own "leads from the front" comment. |
| **Generalist** | — | **none / none** | melee·3.0·STR | none | No kit identity by definition — the deliberate, honestly-worse, ungated fallback (§8). |

⚠️ **Anchor is authored in the palette but assigned to ZERO of the 18 classes.** Every kit that
would have read "outlast" under the old 4-doctrine model resolves more precisely once the
Empower/Protect/Restore split exists — Tank reads Protect, Spellshield reads Protect/Restore,
Shaman/Mystic read Restore(+Protect/Strike). **This is a genuine finding, not an oversight**, and
it's flagged rather than quietly patched over: §9 asks whether Anchor should be retired from the
palette, or kept as reserved capacity for a future 19th class or an NPC archetype that doesn't map
to the 18 (e.g. a rival-only "the wall" template with no support output at all).

### 3.4 Recount — is Control still thin?

The first pass's finding: **Control owned by exactly 1 of 18 classes (Orator), at the primary
tier, under the old 4-doctrine model.** Re-tallying under the 7-doctrine table with secondaries:

| doctrine | primary count | secondary count | touches (primary OR secondary) |
|---|---|---|---|
| Strike | 5 (Warrior, Rogue, Spellsword, Skirmisher, Stalker⚠️) | 2 (Ranger, Mystic⚠️) | 7 / 18 |
| Sweep | 5 (Ranger, Wizard, Evoker, Swashbuckler, Captain) | 3 (Tank, Bard, Herald) | 8 / 18 |
| Control | 2 (Orator, Bard) | 3 (Sage, Wizard, Swashbuckler) | **5 / 18** |
| Protect | 2 (Tank, Spellshield) | 3 (Warrior, Spellsword, Shaman) | 5 / 18 |
| Restore | 3 (Sage, Shaman, Mystic) | 2 (Spellshield, Stalker) | 5 / 18 |
| Empower | 1 (Herald) | 2 (Captain, Orator) | 3 / 18 |
| Anchor | 0 | 0 | **0 / 18** |
| none (Generalist) | — | — | 1 / 18 |

**Control's primary-tier count barely moves (1 → 2)** — it's still the thinnest doctrine at the
top tier, tied with Protect. But **its total footprint (primary-or-secondary) goes from 1/18
(5.6%) to 5/18 (27.8%)** — Sage, Wizard and Swashbuckler now all carry a genuine Control lean as
their secondary, so a player who wants denial-flavoured play has real choices beyond Orator/Bard
even though only those two OWN it outright. **This substantially answers the first pass's own
finding (§4.5 there)** without moving Shaman or Wizard's primary identity, which was the
trade-off flagged and left unresolved last time. Whether 2-of-18 at the primary tier is still too
thin is a genuine remaining call — flagged in §9, not resolved by this recount alone.

### 3.5 ⚠️ Known gap, carried forward: the patient single-target archetype

Unchanged from the first pass, and now visible in THREE places instead of one: Rogue, Stalker and
Mystic all draw the Venomcraft line, and in every case it's been pragmatically tagged **Strike**
because it isolates a single target — but its actual win condition (patient poison-stacking) is
the opposite of Strike's "fast" framing. Stalker is the worst fit (Venomcraft supplies its
PRIMARY tag, not just a flagged secondary). This is the same "Duellist" gap the first pass
identified in `docs/ENGAGEMENT_DESIGN.md` §7: **a kit that commits to one target and wins slowly
has no clean home in a seven-doctrine palette built around Control/Sweep/Strike plus the three
support kinds.** If a fifth combat doctrine is ever added ("Grind" or similar — wins by attrition
on a single target), Stalker is the first class that should move to it, very likely keeping
Restore as its secondary.

---

## 4. Per-class stat caps

### 4.1 CONFIRMED for this pass: the 3-tier formula

> ⚠️ **THE TIER VALUES BELOW WERE MEASURED IN ROUND 15 AND ARE REFUTED — see §0.2.** `{1.00, 0.90,
> 0.70}` is DOMINATED by `{1.35, 1.15, 0.70}` on both axes (it preserves half as much of a naive
> player's points while forcing half the spread) and it hands back the `SPIKE_HEADROOM 1.35` that
> round 14 bought to take a specialist from 4/24 careers to 26/32. Worse, **as a fraction of the
> LEAGUE cap the whole scheme is inert at Masters and Tamers Apex** — a naive body reaches 761/stat
> against a 770 off-class ceiling. The 3-TIER STRUCTURE survives; the values and the quantity they
> are a fraction of do not. §10.1 is the replacement.

**Decision:** *"Caps: 3-tier (primary 1.00 / secondary 0.90 / other 0.70) as the working
proposal"* — adopted for this draft. The multiplier VALUES remain unmeasured proposals (§4.5);
the 3-TIER STRUCTURE (vs. a 2-tier primary/everything-else scheme) is the part now settled.

**`classCap(stat, class, c) = statCapFor(c) × relationMult(stat, class)`**

| Symbol | Type | Range | Description |
|---|---|---|---|
| `stat` | Stat | {STR,DEX,CON,WIS,INT,CHA} | the stat being capped |
| `class` | string | one of 18 + Generalist | the monster's currently assigned class |
| `c` | Career-like | — | carries `licenseIndex`, `potential`, `species`, `generation` |
| `statCapFor(c)` | int | existing formula, unchanged | league cap × bloodline `potential`, gen-1 clamped |
| `relationMult` | float | ⚠️ SHIPPED: **{1.35, 1.15, 0.875}** (this row's {1.00, 0.90, 0.70} is refuted — see §0 and the note below) | primary · secondary · otherwise |
| `classCap` | int | ≤ `statCapFor(c)` always | the final per-stat training ceiling |

⚠️ **THE "OUTPUT RANGE" PARAGRAPH BELOW IS FALSE ON THE SHIPPED BUILD AND THE DIFFERENCE IS THE
POINT.** It was written when `relationMult` never exceeded 1.00, so committing could only ever
TIGHTEN a ceiling — which makes assignment a pure cost and an uncommitted monster strictly
dominant. What shipped LIFTS the primary to 1.35× nominal and retires the free spike for the
uncommitted state (`week.gd:UNASSIGNED_HEADROOM 1.00`), so a committed primary out-reaches
anything an uncommitted body can touch by 385 points at Apex, for all 18 classes. Assignment
redistributes room; it does not confiscate it. Read the paragraph as the ORIGINAL proposal.

**Output range:** strictly ≤ `statCapFor(c)`, since `relationMult` never exceeds 1.00 — this
formula only ever *tightens* the existing ceiling, never loosens it. A class's primary stat is
mathematically unchanged from today (mult 1.00); the restriction lands entirely on the four
off-class stats (0.70) and lightly on the secondary (0.90).

**Integration point, deliberately:** `classCap` multiplies the *output* of the existing
`statCapFor(c)`, not its inputs. Every gen-1 clamp (`WILD_GEN1_CAP`, `FUSION_GEN1_CAP`,
`PRESTIGE_GEN1_CAPS`, `PRIMEVAL_GEN1_CAP`) keeps working exactly as authored; the class multiplier
is a second, independent restriction layered on top.

### 4.2 Worked example A — Wood league

Fresh Wood-league monster (`LEAGUES[0].cap = 100`), any class, potential 1.0:

```
statCapFor(c) = 100 × 1.0            = 100
primary cap                          = 100
secondary cap                        = 90
other four                           = 70  (each)
```

⚠️ Even at Wood the shape is visible immediately — a new player can feel their monster's class
identity from week one, not just at the endgame where the caps in isolation start to bite.

### 4.3 Worked example B — Platinum league

Platinum-league Wizard (`LEAGUES[8].cap = 900`, INT primary / WIS secondary, §3), potential 1.05,
not gen-1:

```
statCapFor(c) = 900 × 1.05           = 945
INT  cap = 945 × 1.00                = 945
WIS  cap = 945 × 0.90                = 851   (rounded)
STR/DEX/CON/CHA cap = 945 × 0.70     = 662   (each, rounded)
```

A Platinum Wizard can push INT all the way to the league-adjusted ceiling and WIS most of the
way there, but its melee/physical stats sit meaningfully behind — exactly the "can't be
everything" shape the cap system exists to produce, visible well before the top of the ladder.

### 4.4 Worked example C — Tamers Apex, gen-1 wild clamp interaction

The same class pairing (STR primary/CON secondary, e.g. Warrior), but gen-1 wild
(`WILD_GEN1_CAP` = 700) at Masters (`LEAGUES[9].cap` = 1000), potential 1.0:

```
statCapFor(c) = min(1000 × 1.0, 700) = 700   (the wild clamp is already binding)
STR  cap = 700 × 1.00                = 700
CON  cap = 700 × 0.90                = 630
DEX/WIS/INT/CHA cap = 700 × 0.70     = 490   (each)
```

The class multiplier bites *harder* on a wild gen-1 monster, since it multiplies an already-lower
number — a wild-caught Warrior is both stat-capped by its origin AND shape-capped by its role,
and the two stack rather than fight. A bred dynasty at the true Tamers Apex ceiling
(`LEAGUES[10].cap` = 1100, potential up to whatever breeding has produced, no gen-1 clamp) shows
the full spread: at potential 1.15 the primary stat can approach ~1265 while the four off-class
stats sit near 886 — a gap of roughly 380 points, entirely a function of the class chosen.

### 4.5 ⚠️ Unmeasured, and cannot be measured yet

The `{1.00, 0.90, 0.70}` multipliers and the gate constants in §2.2 (`0.20` floor, top-2/top-3
ranks) are proposals, not findings. `tools/sweep40.ts` cannot currently tell you whether any of
them are right, because **the balance baseline is suspended** — the 5v5 re-weighting alone moves
every quoted number in `CLAUDE.md` and `docs/BALANCING.md`, and stacking untested class-cap and
gate constants on top of an already-untested baseline is exactly the "several changes at once,
can't tell which one did what" trap `CLAUDE.md` names by name. All of these go in the queue for
the deliberate re-baseline, nudged one at a time, per the standing rule — not simmed today.

---

## 5. How doctrine layers over `cohesion` × `predation` — the mechanism

**Decision:** *"LAYERED, not parallel. Doctrine is the TEAM's plan; `cohesion`×`predation` is the
UNIT's fidelity to it. A low-cohesion monster under a Control plan keeps freelancing off-plan — a
feature, and it makes breeding for personality mechanically meaningful. Do not build a second
archetype system beside the existing grid."*

### 5.1 The existing plumbing this reuses

`GAMEPLANS` (`core.ts:698`) already does exactly this pattern one layer up — a small curated set
of named plans (`rushdown`/`bulwark`/`attrition`/`focusfire`/`zone`), each carrying a
`tactics: Tactics` preset applied to a rival TEAM, expressed entirely through existing `Tactics`
fields. `FieldTraits.cohesion`/`.predation` (`tamerengine/types.ts:418`) are computed by
`traitsFor()` (`tamerengine/decide.ts:33`) as a **pure function of personality + coached
Tactics**: `resolvePersonality()` blends each monster's innate `aggression`/`teamplay`
(`personality.ts`) with whatever the current `Tactics` are ASKING for
(`coachingTargets()`), weighted by the monster's own `temperament` — its DISCIPLINE, i.e. how
much of any coaching actually sticks (`coachedValue()`, `personality.ts:111`).

**Doctrine slots into this stack in exactly the place `GAMEPLANS.tactics` already occupies for
teams — as a `Partial<Tactics>` preset, keyed by class instead of by team plan:**

```
DOCTRINE_TACTICS: Record<Doctrine, Partial<Tactics>>
  Control  → { ccPriority: true }
  Sweep    → { targetPriority: undefined }              // deliberately unset — never narrows to one enemy
  Strike   → { comboRole: 'detonate', burst: 'nuke' }
  Anchor   → { preserve: 'cautious', healPolicy: 'triage' }   // authored, currently unassigned (§3.3)
  Empower  → { healPolicy: 'steady' }                    // buffs land best applied early and often, not held
  Protect  → { formation: 'keep' }                        // holds its slot to keep its shields in range
  Restore  → { healPolicy: 'triage' }                     // matches the measured default (§ current code comment on TRIAGE_AT)
```

**Precedence, highest wins per-field** (mirrors how `GAMEPLANS` already composes with a rival
team's individually-scouted behaviour, just extended one tier finer):

1. Player's explicit per-fight orders (`MatchOrders`) or the team's rolled `GAMEPLANS.tactics`
   for rivals — highest precedence, unchanged from today.
2. This monster's own standing `Monster.tactics`, if the player has set one.
3. **Class doctrine's default Tactics** (primary doctrine's fields; secondary only fills any
   field primary left unset — this is the literal implementation of "the secondary is a tiebreak
   weight, never a second full behaviour," §3.1).
4. `DEFAULT_TACTICS` (global fallback) — lowest precedence, unchanged from today.

**No new engine surface.** Once the composed `Tactics` object exists, it feeds
`coachingTargets()` → `resolvePersonality()` → `traitsFor()` completely unchanged — `cohesion` and
`predation` are still the same pure function of personality and coaching they are today, just
receiving a doctrine-flavoured `Tactics` as input for monsters that haven't overridden it
themselves.

### 5.2 What a Control doctrine actually does to a low-cohesion, assassin-flavoured unit

Concretely: a monster whose FieldTraits quadrant reads "low cohesion / high predation" (the
engine's own documented "assassin: solo-dives the enemy backline" archetype,
`tamerengine/types.ts:414-417`) gets assigned to Orator (Control primary). Orator's doctrine
preset sets `ccPriority: true` and (via `coachingTargets()`) implicitly leans `teamplay` upward
through whatever `targetPriority` the doctrine table also carries.

- **The part that demonstrably degrades under low personality-fit today:** any doctrine field that
  routes through `coachingTargets()` (i.e. `targetPriority`-driven `teamplay`/`aggression`
  targets) is blended via `coachedValue(innate, target, temperament)` — a monster with low
  `temperament` (low discipline) only partially adopts the doctrine's implied teamplay lean,
  reverting toward its own innate low-teamplay reading. **This is the literal mechanism behind
  "keeps freelancing off-plan"** — it already exists, unmodified, for exactly this class of field.
- **⚠️ The part that does NOT degrade today, and is an open engine question:** `ccPriority` itself
  is read as a hard boolean directly by `engine.ts:410` — it is NOT blended through
  `coachedValue()`. As implemented today, a monster under a Control doctrine would apply the
  `ccPriority` scoring bonus in full regardless of its personality, even while its
  teamplay/aggression readings are freelancing. The same is true of `comboRole`, `formation`, and
  several other fields, which are read directly at various points in `decide.ts`/`engine.ts`
  rather than uniformly gated by discipline.

**This is flagged honestly rather than asserted away.** The "fidelity" story the decision
describes is TRUE for the subset of Tactics that already routes through personality (teamplay/
aggression), and NOT yet true for the rest. Making it fully true for every doctrine-sourced field
— so a low-discipline monster freelances off ANY part of its class doctrine, not just the
teamplay-routed half — is an ENGINE CHANGE (gating `ccPriority`, `comboRole`, `formation` etc. by
`temperament` specifically when their SOURCE is a doctrine default rather than an explicit player
order), not something this document can resolve by naming a data table. Flagged for §9, in the
same spirit `FieldTraits` composition was already flagged as open in the first pass.

---

## 6. What a class carries — confirmed scope (unchanged)

**Confirmed, no further sign-off needed:** this rework adds exactly one new mechanical trait to a
class — doctrine (§3). `docs/ENGAGEMENT_DESIGN.md` §7 already states the discipline this follows:
*"One, not a kit — eighteen classes with three traits each is 54 interacting rules and nobody will
be able to predict a fight."*

**Explicitly OUT OF SCOPE here, cross-referenced rather than built:**

- **Speed band** — `docs/ENGAGEMENT_DESIGN.md` §6 proposes deriving movement speed from the class
  basic's channel. Not decided there yet. Not added here.
- **Preferred station** — `docs/TACTICS_BRAINSTORM.md` §2.3/§5 proposes station aptitude as a
  bloodline-inherited trait, explicitly required to be an aptitude and never a lock. Not added
  here.

**Unchanged, already exists, keeps working once class becomes a stored field instead of a live
derivation:**

- **The free attack** (`CLASS_BASIC` — channel, reach, scaling stat per class, tabulated in §3.3).
- **Line affinity** (`CLASS_LINES` — tabulated in §3.3). Nothing about `lines.ts` needs to change;
  it is keyed by class NAME today and stays keyed by class name, just a more reliable one (§7).

---

## 7. Migration

### 7.1 Data model changes

- **`Career`** (`src/game.ts`) needs a new persisted field, e.g. `assignedClass?: string` —
  absent means "still on the species default," so existing saves need no migration script, only a
  fallback read.
- **`Species.naturalClass`** (`src/core.ts:386`) is repurposed from "a fact validated against base
  stats" to "the default class assigned at generation." Recommend renaming to `defaultClass` for
  clarity, since "natural" implied a derivation that no longer exists.
- **`classForStats()`** (`src/core.ts:812`) — keep, but demote to a generation-time convenience
  helper. **Decision confirms it stays alive for exactly this purpose:** *"Rival class comes from
  rolled stats"* (`DECISIONS_2026-08-03.md` #17) — rivals and wild monsters are generated via
  `generateMonster` and get `classForStats(stats)` as their class exactly as today, no gate, no
  doctrine-vs-gameplan decision needed. It is no longer called for any PLAYER monster after
  generation.
- **New field on `ClassDef`:** `doctrine?: { primary: Doctrine; secondary?: Doctrine }` (per §3.3;
  `undefined` for Generalist). `Doctrine = 'control' | 'sweep' | 'strike' | 'anchor' | 'empower' |
  'protect' | 'restore'`.
- **New table:** `DOCTRINE_TACTICS: Record<Doctrine, Partial<Tactics>>` (§5.1) — the doctrine
  preset lookup, same shape as `GAMEPLANS[x].tactics`.
- **New function:** `classesAvailableFor(stats, career): string[]` (§2.2) — the gate.
- **New constants:** `GATE_FLOOR = 0.20` (or wherever tuned), the rank thresholds (currently
  hardcoded as top-2/top-3 in the pseudocode, should live alongside the cap multipliers as
  external data per `CLAUDE.md`'s "gameplay values must be data-driven" rule).

### 7.2 Call sites that must change (file:line, as of this read — 2026-08-03)

| file | line(s) | what it does today | what it needs to do |
|---|---|---|---|
| `src/game.ts` | ~491 (`careerMonster`) | `className: classForStats(c.stats)` | `className: c.assignedClass ?? defaultClassFor(c.species)` |
| `src/game.ts` | ~378 (`newCareer`) | no class assignment at generation | assign `assignedClass` (or leave undefined = species default) |
| `src/game.ts` | 361 (`statCapFor`) | one cap per monster, no per-stat variance | needs a sibling `classCapFor(c, stat)` wrapping it with `relationMult` |
| `src/game.ts` | 280, 554 (`previewWeekEffects`, `applyWeek`) | `const cap = statCapFor(c)` hoisted once per monster | must call `classCapFor(c, stat)` **per stat inside the loop** — this is the one call-site change that is not mechanical, since today's `cap` is a scalar hoisted outside the per-stat loop |
| `src/monster.ts` | 601 (`generateMonster`) | `className: classForStats(stats)` | reads the assigned/default class instead, for PLAYER monsters; unchanged for rivals/wild (§7.1) |
| `src/monster.ts` | 325, 372, 399, 445 (`chooseLoadout` internals) | four separate calls to `classForStats(stats)` to re-derive class | all four take an authoritative `className` parameter instead — the largest code-shape change in this migration |
| `src/App.tsx` | 721, 2288 | UI display badges recompute `classForStats(c.stats)` live | read `c.className` (the stored field) directly — simpler than today, not harder |
| `src/App.tsx` | 1608, 1627 | team-picker pool recomputes `classForStats(c.stats)` for display + role lookup | same — reads stored `className` |
| `src/App.tsx` | (new) | — | new interactive "Assign / Reassign Class" control on the Ranch detail panel, gated by `classesAvailableFor()` (§2.2), showing which stats are currently frozen by the incoming cap before the player commits (§1.1's non-punitive promise needs to be VISIBLE, not just true) |
| `src/validate.ts` | 161-166 | asserts `classForStats(sp.base) === sp.naturalClass` for all 65 species | retired outright — replacement guard in §7.3 |
| `src/lines.ts` | — | `CLASS_LINES`/`LINE_OF`, keyed by class name string | **unchanged** — works correctly the moment `className` is a reliable stored value |
| `src/tamerengine/decide.ts` | `traitsFor()`, line 33 | `FieldTraits` built purely from `personalityOf`/`resolvePersonality` + a small role/order nudge | unchanged internally; the INPUT `Tactics` it reads now includes the doctrine-composed value from §5.1's precedence stack, resolved upstream before `traitsFor` is ever called |
| `src/town.ts` | rival generation path | rivals generated via `generateMonster`, inherit whatever lands in `monster.ts` | confirmed: no change beyond what `monster.ts` already does for rivals (classForStats stays, §7.1) |

### 7.3 `validate.ts` replacement guard

The retired check (`naturalClass` must match `classForStats(base)`) protected against a real class
of bug: a species whose authored data silently drifted from its declared identity. Replacement,
cheap and still load-bearing:

- Every species' `defaultClass` must be a valid entry in `CLASSES` (typo/rename guard).
- Every entry in `CLASSES` must have a `doctrine.primary` set (or be explicitly `Generalist`, the
  one documented exception) — the same failure mode `validate.ts` already polices for `LINE_OF`
  coverage, applied one level up.
- **New:** every `doctrine.primary`/`doctrine.secondary` value must be one of the 7 `Doctrine`
  strings, and `DOCTRINE_TACTICS` must have an entry for all 7 (including `anchor`, even though
  it's currently unassigned — §3.3's "reserved capacity" reading requires the table entry to exist
  and be inert-but-valid, not simply absent).

### 7.4 Documentation updates needed

- `CLAUDE.md`'s "Classes are emergent, not species-locked" section needs a full rewrite reflecting
  this document, once the remaining §9 items are settled.
- `docs/TACTICS_BRAINSTORM.md` §5.2 should get a pointer added ("superseded/extended by
  `CLASS_REWORK.md`") rather than being edited in place.
- `docs/ABILITY_REWORK.md` and `docs/GODOT_MIGRATION.md` likely reference the emergent-class model
  in passing; flagged for a grep-and-update pass, not audited line-by-line here.

---

## 8. What this breaks

- **Loadout drafting (`monster.ts:chooseLoadout`).** The real refactor in this whole proposal —
  four internal call sites re-derive class from stats today, and all four need to take an
  authoritative `className` instead. Mechanically bounded (§7.2) but not small.
- **The UI.** `m.className` is currently a read-only badge. This proposal requires an actual
  interactive control — pick at generation, reassign later through the gate, show the cap
  consequences before committing. Real scope, not a data-plumbing exercise.
- **Generalist.** Under the old emergent system, Generalist was a *leftover bucket* that
  `CLAUDE.md` notes "came out as the TOP damage class in the sweep, which is absurd for a
  fallback" — a direct result of no line affinity while still fighting with a full unrestricted
  stat spread. Under this proposal, Generalist becomes a **deliberate, ungated choice**:
  `relationMult = 0.70` on *all six* stats (no stat gets favoured treatment), no doctrine, no line
  affinity. A player can still choose it for a genuinely flexible monster, but it is now honestly
  worse at everything rather than accidentally best at something.
- **Species aptitude vs assigned class disagreeing.** Explicitly ALLOWED, and this is what keeps
  "any species can train into any class" alive: a WIS-major Mammal assigned to Warrior (if the
  gate lets it — §2 requires STR/CON to already be prominent, so this specific example may not
  clear the gate until well-trained) trains STR/CON at the normal class-cap rate, just slower than
  a STR-major species would via the separate aptitude-RATE multiplier
  (`statTrainingBonus`, unchanged, untouched by this document — decision #9 keeps the two axes
  fully separate). The two systems disagreeing is a feature, not a bug to reconcile.
- **`FieldTraits` composition.** §5.2 spells out exactly what's solved (teamplay/aggression-routed
  fields already blend by discipline) and what's open (ccPriority, comboRole, formation are hard
  reads today) — carried forward to §9, not resolved by this document alone.

---

## 9. What is still unknown — for the re-baseline

Everything the first pass listed as a decision has now been made (recapped below for the record).
What remains is genuinely open, not a re-ask of settled ground:

### 9.1 Resolved since the first pass (recap, not re-litigated)

| # | question | resolution |
|---|---|---|
| §1 | assignment model | A1 (species default + paid reassignment), now gated by current stats (§2) |
| §2.1 | 3-tier vs 2-tier caps | 3-tier `{1.00, 0.90, 0.70}` adopted for this draft — values still unmeasured |
| §4.5 (old) | Control's thin representation | Recounted at 5/18 total footprint once secondaries exist (§3.4) — the primary-tier count barely moved and may still be a live concern (§9.2) |
| §4.6 (old) | Duellist/patient-single-target gap | Acknowledged as a known limitation, carried forward (§3.5), not solved |
| §6 (old) | rival class assignment | Confirmed: tracks rolled stats via `classForStats()`, not team gameplan |
| new | is doctrine per-class or per-team? | Layered: doctrine (per-class) supplies a Tactics preset at the same tier `GAMEPLANS` occupies; `cohesion`/`predation` remain the unit's unmodified fidelity computation (§5) |
| new | doctrine overlap | Primary + secondary per class, secondary as tiebreak weight only (§3) |
| new | doctrine set | Seven: Control/Sweep/Strike/Anchor/Empower/Protect/Restore — the last three ARE the existing CHA/CON/WIS support division, not new taxonomy (§3.1) |

### 9.2 Genuinely open, needs a decision or a measurement

1. **Is 2-of-18 at the primary Control tier (Orator, Bard) still too thin, even with the
   secondary footprint at 5/18?** (§3.4) Not resolved by the recount alone — a judgement call
   about whether "own it outright" matters more than "have access to it."
2. **Anchor: retire from the palette, or keep as reserved capacity?** (§3.3) Zero of 18 classes
   use it. Keeping it costs nothing (one inert `DOCTRINE_TACTICS` entry) but an unused category in
   a shipped enum is exactly the kind of thing `validate.ts` usually exists to catch drifting.
3. **The CON+CHA coverage gap** (§2.3, Example B) — no class in the 18 pairs those two stats.
   Worth a 19th class, or an acceptable gap (Generalist exists precisely to catch this)?
4. **Extending discipline-gating to non-personality-routed Tactics fields** (§5.2) — `ccPriority`,
   `comboRole`, `formation` etc. are hard reads today, not blended by `temperament` the way
   `targetPriority`'s effect on teamplay/aggression already is. Making "a low-discipline monster
   freelances off ANY part of its doctrine" fully true (not just the teamplay-routed half) is an
   engine change, not a data change — needs its own scoping pass.
5. **Reassignment gold cost** (§1.1) — explicitly deferred to the economy rebalance pass per
   `CLAUDE.md`'s roadmap; do not invent a number in isolation.
6. **The cap multipliers, gate floor and rank thresholds** (§4.5, §2.2) — all unmeasured, all
   queued for the deliberate re-baseline once the 5v5 re-weighting lands, one value at a time.
7. **`Species.naturalClass` → `defaultClass` rename** (§7.1) — a small call, but touches every
   species entry and any doc referencing the old name; worth batching into one pass rather than
   doing piecemeal.
8. **UI flow for the gate** — does an ineligible class show greyed-out with "why" (e.g. "needs DEX
   in your top 3"), or simply not appear in the list at all? Affects whether the gate teaches its
   own training goal (§2.1's third requirement) or just silently narrows a menu. Recommend
   greyed-out-with-reason on legibility/competence grounds (SDT), but this is a UX-designer call,
   not a game-designer one — flagged for that handoff.

---

# 10. THE GODOT BUILD SPEC — what is buildable, and in what order

⚠️ Everything in §1–§9 above was written against the **TypeScript** tree on 2026-08-03 and is
kept for its reasoning. This section is the Godot reality as of 2026-08-10, and where the two
disagree, this one is later. **§0's verdict governs: item 10.1 is the only part with measured
support. 10.2 and 10.3 are conditional on decisions only the user can make.**

## 10.1 BUILD THIS FIRST, AND IT IS NOT CLASSES — re-aim the cap at the career, not the league

**The measured problem (§2): the anti-generalisation constraint is inert above Gold.** Fix the
number it is a fraction *of*, and the class question does not even have to be answered yet.

`week.gd:stat_ceiling()` already carries the right SHAPE — a shared `6 × nominal` budget with
`SPIKE_HEADROOM 1.35` on any one stat — and its own comment says the budget "does not bind today,
deliberately". Measured, a full career banks **~4,450 points against 6,600**, i.e. the budget is
**48% larger than any career can spend**. It is not a guard, it is a decoration.

- **File:** `monster-tamer/scripts/week.gd`, `stat_ceiling()` only. One constant, one line.
- **Change:** the budget term `6.0 * nominal` becomes `TOTAL_BUDGET_MULT * nominal` with
  `TOTAL_BUDGET_MULT` authored **below 6.0**. At 5.30 (= `1.35 + 1.15 + 4 × 0.70`, the archetype
  vector's own sum) it removes 12% of the notional room; the honest starting point given the
  measured 4,450/6,600 is nearer **4.2**, which is where it first binds on a full career.
- ⚠️ **THIS IS A SHAPED FUNCTION, NOT A FIT.** Author ONE multiplier. Do not derive eleven
  per-rung constants — round 12b baked instrument noise into the game permanently that way and
  `career.gd` carries the scar.
- **Acceptance, `_probe_class.tscn -- --gym`:** the naive arm's **spread rises above 0.20 at
  Masters AND at Tamers Apex** (today 0.03 / 0.03) while its **total falls by no more than 10%**.
  ⚠️ And the guard that makes this safe: **`_probe_shape.tscn -- --pol --seeds 32` must keep
  FLAT ≥ 24/32.** `SHAPE_DIAGNOSIS.md` §5(a) is explicit — do not buy the gap by making the naive
  player lose; its losers already stall with 108 blocked weeks and removing the on-ramp violates
  `CLAUDE.md`.
- ⚠️ **Do NOT touch `SPIKE_HEADROOM 1.35` or `FOCUS_FLOOR 0.75` in the same change.** Round 14
  bought the specialist's viability with those two (4/24 → 26/32) and this round's ARCHETYPE
  reading depends on them holding. One value at a time.

## 10.2 IF ASSIGNABLE CLASS SHIPS ANYWAY — the overwrite-site table

**This is the section that decides whether the feature does anything at all.** A stored player
choice in this codebase is erased by default: `recompute_class()` writes all four derived fields
unconditionally, and one of its callers runs **every week**.

⚠️ **THE BRIEF SAID SIX CALLERS OF `recompute_class()`. THERE ARE FIVE, AND THAT UNDERCOUNT IS
THE LESS DANGEROUS HALF OF THE ERROR — TWO SHIPPED FILES OVERWRITE THE DERIVED FIELDS WITHOUT
CALLING `recompute_class()` AT ALL.** `breeding_ui.gd` and `lab_ui.gd` assign `class_name_`,
`role` and `mana_role` inline. A fix applied only to `recompute_class()` would leave every bred
and every lab-produced monster silently un-assigned — which is precisely this project's signature
failure, and it would land on the two screens the meta-game is *built around*.

| # | file:line | what it does today | required behaviour once class is STORED |
|---|---|---|---|
| 1 | `week.gd:579-581` (`apply_activity`) | `class_before = class_name_` → `recompute_class()` → `_redraft_if_stale(mi, class_before)`. **Runs every week for every monster.** | ⚠️ **THE CRITICAL ONE.** Must recompute `mana_role` / `basic_attack` / `max_hp` / `max_mp` from the new stats but **must NOT touch `class_name_` or `role`**. `_redraft_if_stale`'s `class_before` comparison then never fires on a stored class, which is correct: an assigned monster's kit goes stale on `learnLevel` alone, never on drift. |
| 2 | `game_data.gd:209` (`make_monster`) | `recompute_class()` at generation | Correct as-is for *generation*: this is where `defaultClass` is decided. Should write the derived answer INTO the stored field once, not leave it derived. |
| 3 | `game_data.gd:252` (`train`) | `recompute_class()` + unconditional `assign_moveset()` | ⚠️ **DEAD CODE — verified 2026-08-10.** `grep -rn "\.train("` returns only two ⚠️ comments describing its retirement (`monster_instance.gd:72`, `training_ui.gd:3`); the stable screen writes a PLAN and the tick resolves it. **Delete it rather than porting the change into it.** |
| 4 | `roster.gd:365` (`_shape_to_class`) | `recompute_class()` + `assign_moveset(rng)` after reshaping stats | Must take the target class as authoritative — it already has it as the `want` parameter. Replace `recompute_class()` with a stamp of `want`. ⚠️ `roster.gd:531` calls it as `_shape_to_class(mi, mi.class_name_, …)` for market grades, which under a stored class becomes *shape this body toward the class it was sold as* — correct, and better than today. |
| 5 | `save_game.gd:214` (`_deserialize_roster`) | `recompute_class()` on load, because derived fields are deliberately never persisted | ⚠️ **THE SAVE-COMPAT SITE.** See 10.4. Must read the stored class if the save has one and fall back to `class_for_stats` if it does not. |
| 6 | `ui/breeding_ui.gd:306-308` | **INLINE** `child.class_name_ = ClassifyLib.class_for_stats(...)`, `.role`, `.mana_role` — bypasses `recompute_class()` entirely | Must set the child's stored class. ⚠️ **Design question this forces, and it is not small: does a bred child INHERIT a parent's assigned class, or is it born unassigned?** Inheritance makes breeding a way to pass down a trade (which is the vision); unassigned makes every child a fresh decision. Not answered here. |
| 7 | `ui/lab_ui.gd:273-275` | **INLINE**, same three fields | Same as 6. |
| 8 | `monster_instance.gd:153-156` (`_set_id`) | Re-drafts the kit when a lineage token arrives after a moveset exists | Unchanged, but the re-draft now draws from the STORED class. Verify the heirloom reserved slot still survives — `_probe_breed` covers it. |
| 9 | `ui/stable_ui.gd:669,693` (`_class_after`) | Previews *"would this week's training tip me into a different class?"* on the training card | ⚠️ **This label becomes a LIE the day class is stored, and it is currently described in its own comment as "the single most decision-relevant line on the card".** It must be replaced, not deleted: under assignment the useful preview is *"this week's gain would qualify you for Skirmisher"* — the gate teaching its own training goal (§2.1 requirement 3). |
| 10 | `formations.gd:130,273` | Reads `class_name_` to match a monster to a formation slot | Unchanged, and **strictly better**: a formation keyed to a stored class survives training, which is exactly what the comment at the top of that file wants. |
| 11 | `_probe_career_loop.gd:126`, `_probe_ladder_slope.gd:264,306`, `_probe_shape.gd`, `_probe_training.gd`, `_probe_week.gd`, `_probe_archetypes.gd` | Probes that stamp `class_name_` or call `recompute_class()` directly | Must be swept in the same change. ⚠️ **`_probe_archetypes.gd:128` is the "no species is locked out of a role" test — see 10.3. It must keep passing or the change is wrong.** |

**The rule, stated once so it can be checked mechanically:** after this change, `class_name_` and
`role` are written in exactly **four** places — generation (2), reassignment (the new UI action),
deserialisation (5), and the sum-preserving shaper (4). Anywhere else that assigns them is a bug.
A cheap guard: make `class_name_` a `set`-guarded property that `push_error`s when written outside
an explicit `assign_class()` call, and run `_probe_career_loop` — the error surfaces immediately.

## 10.3 THE MECHANISM, PINNED

Answering the round brief's item 3 as buildable detail. **All of it is conditional on 10.1's
verdict; none of it is worth building at 0.97x.**

**WHEN, and can it change.** Assigned at generation from `defaultClass` (§1.1). Reassignable at
any time from the stable screen. ⚠️ **The cost is not gold, and §1.1's "TBD gold cost" is the
wrong currency** — measured, reassignment already costs **0.03x** on the day it is made (TRANSIT),
because the kit is redrawn onto a body that has none of the new class's stats. **That is the
price, it is enormous, and it is paid in weeks of retraining.** Adding gold on top would be
double-charging. What the build owes the player is not a fee but a **warning**: the reassign
dialog must show the new kit and the stats it will not be able to use, before committing.

**WHAT GATES IT.** §2.2's rank-and-floor gate, unchanged and buildable as written: `rank(P) ≤ 1`,
`rank(S) ≤ 2`, `stats[P] ≥ GATE_FLOOR × stat_cap_for(mi, league_cap)`. Ties by `Classify.STATS`
order — the same total order `_top_two()` already relies on, so no new convention. Godot home:
`classify.gd` as a new `static func classes_available_for(stats, nominal_cap) -> Array`, sitting
*beside* `class_for_stats` and never replacing it.
⚠️ **`GATE_FLOOR = 0.20` IS UNMEASURED AND MEASURABLY TOO LOW.** At Iron (cap 500) it is 100, and
a naive body reaches 500/stat — every class the rank test allows is open from very early. Author
it as a shaped function of the same quantity 10.1 fixes (a fraction of what a career can BANK, not
of the league ceiling) or it inherits §2's inversion exactly.

**THE CAPS.** ⚠️ **`{1.00 / 0.90 / 0.70}` is refuted (§2): dominated by `{1.35 / 1.15 / 0.70}` on
both total preserved and spread forced, and it undoes round 14's `SPIKE_HEADROOM`.** If caps ship,
ship the archetype tiers. **Why assignment breaks the circularity, stated plainly and unchanged:**
under derivation, class is a *function of* the stats, so a class-keyed cap raises the ceiling on
the very stat that selected the class — the cap feeds its own input. A stored class is an
*input*, not an output: nothing the player trains changes which cap applies, so there is no loop
to close. The stat gate is the second, independent guard — a class cannot be assigned to a body
whose stats bear no resemblance to it, so the cap can never be bought by declaration alone.

**GENERALIST.** ⚠️ **It is the UNASSIGNED STATE and it must remain a real, armed class.** It is
absent from `GameData.classes` (18) but present in `data.json:classBasic` (19) and it is
`class_name_`'s own default. `monster_instance.gd:_fallback_lines()` gives it a derived kit off
its two highest stats — that fallback is what stopped it shipping weaponless a second time and it
**must not be removed**, because it is also the safety net for any future class added without a
`classLines` entry. Under assignment it becomes honest rather than accidental: *"this monster has
not committed to a trade"*, ungated, always available, with `relationMult` uniform on all six
stats. `_probe_career_loop.gd:_phase_every_class_can_arm` rolls call off `classBasic` and must
keep passing at 171/171.

**THE NON-NEGOTIABLE — no species locked out of a role.** The test exists:
**`_probe_archetypes.gd:128`**, which shapes every species into every archetype class and asserts
zero misses. It survives assignment untouched, because assignment does not consult species at all.
⚠️ **The thing that could break it is the GATE, not the cap**, and the check must be extended to
say so: **for every species and every class, there must exist a reachable stat vector under the
class caps for which `classes_available_for()` contains that class.** Because the gate is a rank
test and rank is relative, and species aptitude is a RATE (never a ceiling — decision #9), the
proof is constructive: any species can train any stat to the top of its own spread, only slower.
**Assert it rather than argue it** — add the loop to `_probe_archetypes.gd` and let it fail loudly
if a future aptitude change makes some path unreachable in a lifetime.

## 10.4 SAVE MIGRATION

`save_game.gd` is `SAVE_VERSION 2` and persists a **fixed field list** —
`speciesId/stats/id/stamina/happiness/ageWeeks/careerWeek/retired/potential/lifespanYears/foods/
children`. Derived fields are deliberately never stored (`save_game.gd:7-9`).

- **The migration is a fallback read, not a script.** `assignedClass` absent → call
  `class_for_stats(stats)` exactly as today. Every existing save loads with every monster keeping
  the class it has always had, and **no player loses a roster.** Bump to `SAVE_VERSION 3` on write
  only.
- ⚠️ **There is a precedent for NOT adding a field, and it should be resisted here.** Lineage
  rides on the `id` string as an appended `#gen,emph,...` token, specifically because
  `save_game.gd` was another workstream's file. **Do not do that for class.** The lineage token is
  safe only because *every field in it is fixed at birth* — `week.gd` seeds the training roll off
  `mi.id`, so a mutable token would silently re-roll a monster's entire remaining career the
  moment the player reassigned. A stored class is mutable by definition. It needs a real field.
- **What the player is told:** nothing, on load — their monsters keep their classes. The first
  time they open the stable, the class badge becomes an interactive control and the reassign
  dialog explains itself. A migration the player has to be told about is a migration that took
  something away.

## 11. WHAT WOULD ACTUALLY CHANGE THE ANSWER

Three things, none of which this round could measure and all of which are cheaper than building
§1–§9:

1. ⚠️ **THE LADDER'S CONVERSION, WHICH IS THE REAL BLOCKER AND IS NOT ABOUT CLASSES.** The fight
   already separates naive from competent by **2.94x** and the career converts it to **zero**
   (87.5% vs 87.5%, `SHAPE_DIAGNOSIS.md` n=32). Until that conversion works, *no* new stable-side
   mechanic can produce a skill gap — it will be absorbed the same way. **This is the highest-value
   diagnostic in the project right now** and it needs a probe that asks where a 2.94x round
   advantage goes between the fight and `Career.won_game`.
2. **A menu of genuinely DIFFERENT classes.** NEIGHBOUR (0.99x) says adjacent classes are
   interchangeable — which is the same finding `CLAUDE.md` already states another way: *"today
   they differ in exactly ONE way, their free attack."* §3's doctrine work is the fix for that,
   and it is **prior** to assignment, not part of it. Assigning between eighteen classes that
   play alike is assigning between one class.
3. **A playtest.** The one claim in favour of assignable class that survives this round entirely
   intact is that a player may want to *choose*, at an identical win rate. `docs/OUTSTANDING.md`
   §3 names the absence of a single playtest record as the project's biggest unchecked assumption.
   ⚠️ **If the user's answer is "I want the choice because it is the game I want to play", that is
   a legitimate and sufficient reason and this document does not override it** — but it should be
   taken as a *design* decision made in full view of a 0.97x, not as a *balance* decision the
   evidence supports.

---

# ⚠️ §12 — ROUND 15 INTEGRATION: THE FEATURE IS SAFE, THE CEILING CHANGE IS NOT

**2026-08-10 · integrator · instruments `scripts/_probe_integrate.gd` (new, 30 checks) and
`scripts/_probe_shape.gd --pol --only-arm --nocommit` (new attribution flags).**

## 12.1 The mechanism works and nothing overwrites the choice

`./run_contract.sh` PASS (all six, 46 classify cases exact). `_probe_integrate` **30/30** — the
player's commitment survives all seven writers of the derived fields (weekly tick, save round
trip, a class-flipping stat change, `make_monster`, `_shape_to_class`, `_make_child`,
`market_offers`), the **kit follows the ASSIGNMENT** and survives 14 weeks of off-class training
and `_redraft_if_stale`, no species is locked out (1170 species x class pairs, 0 gate misses, 0
cap misses, 0 disarmed kits), and the circularity is broken (headroom is a function of the choice
only; `week.gd` makes no live call to `class_for_stats`).

## 12.2 THE REGRESSION, ATTRIBUTED TO ONE CONSTANT

16 career seeds, paired, identical seeds in every row. FLAT is the control and is **14/16 in every
single row** — the naive on-ramp is untouched, exactly as the builders measured.

| build | SPIKE (the committed specialist this round exists to sell) |
|---|---|
| HEAD / round 14 | **13/16** |
| round 15 code, `UNASSIGNED_HEADROOM` put back to 1.35, no commit | **12/16** |
| round 15 code as shipped (1.00), no commit | **4/16** |
| round 15 code as shipped, committing through the shipped gate | **5/16** |
| round 15 code, secondary 1.15 -> 1.35 and off 0.875 -> 0.825, committing | **6/16** |

⚠️ **RETIRING THE FREE SPIKE COSTS THE SPECIALIST 8 CAREERS IN 16, AND COMMITTING BUYS BACK ONE.**
The tier values are not the lever — raising the secondary all the way to the primary's 1.35 moves
it 5 -> 6. **The binder is the OFF-CLASS ceiling.** A spike brain never *asks* for its four
off-class stats, but every intensive and diverse drill raises them incidentally, and at 1.35 those
incidental points bank into the stat TOTAL. Clipped at 0.875 they do not — which is precisely the
measured -13.7% of lifetime total — and `career.gd:expected_climber_fill` prices difficulty on
total and is structurally blind to shape. The committed build is therefore punished on the one
axis the ladder can see.

## 12.3 What this means for the decision in §0

Round 15's verdict (assignment is 0.97x) is **unchanged and unrefuted** by the build. What the
build adds is that the *ceiling* half of the design — not the assignment half — carries a live
cost: as shipped, a player who specialises goes from 13/16 to 5/16 while the player who does
nothing stays at 14/16. **That is an inverted incentive, and it is the round-14 trap rebuilt
through a different door.** Three ways out, none of them tuning:

1. **Ship assignment, drop the caps** (`UNASSIGNED_HEADROOM` back to `SPIKE_HEADROOM`, class
   headroom retired). Assignment is then purely a kit/identity commitment, measured at 0.97x on
   the fight and 14/16 -> 14/16 on the career: **inert, honest, and safe**. The caps' stated job —
   stopping generalisation — does not bind at Masters or Apex anyway (§0.3, and `_probe_training`
   §1: a career banks ~4,450 of 6,600).
2. **Keep the caps and give the ladder a shape term.** Explicitly BANNED by round 14/15. That ban
   and these caps are incompatible; one of them has to go, and it is a user decision.
3. **Keep the caps and raise the off-class ceiling above what a career reaches** (~0.95+ at Apex),
   which makes them decorative at the ship target and load-bearing only at Iron/Gold — the
   inverted progression §0.3 already flagged.

## 12.4 Instrument debt this round created

- `_probe_career_arc.gd:_drill_plan_shaped` never commits and targets the nominal cap, so its
  COMPETENT/EXPERT rows now measure the price of shape with none of its upside (`--policies`
  reads NAIVE 5/5 vs COMPETENT 3/5, n=5). A ⚠️ block is on the function; the fix is to lift
  `_probe_shape.gd:_commit_to_trade` into the parent, and it needs its own measurement.
- `_probe_training.gd` §9's two acceptance targets are OPEN (13.7% vs a 10% budget; top
  learnLevel 573 vs the flat body's 613). Both are downstream of 12.2.
