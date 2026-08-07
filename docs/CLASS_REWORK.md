# Class Rework — Assignable Classes with Per-Class Stat Caps

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
| `relationMult` | float | {1.00, 0.90, 0.70} | 1.00 if `stat` is the class's primary · 0.90 if secondary · 0.70 otherwise |
| `classCap` | int | ≤ `statCapFor(c)` always | the final per-stat training ceiling |

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
