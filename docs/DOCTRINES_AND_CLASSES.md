# Ten roles, thirty classes — derived from the line pool

## ⚠️ BERSERKER MOVES TO STR/DEX (2026-08-03) — and it resolves three things

**User:** *"Berserker shouldn't have anything to do with INT. Can we swap it for another STR/x?"*

**Checked against the line data, and it answers itself:**

```
who leads with Bloodrage (the rage / HP-spend line)?
  -> Skirmisher   (STR/DEX)   Bloodrage, Duelist, Assassin
```

⚠️ **`Skirmisher` IS THE ONLY CLASS IN THE GAME THAT LEADS WITH `Bloodrage`.** Mechanically it
is already the berserker — HP-spend aggression as its primary identity — and it is simply named
wrong. STR/INT never had a claim on the rage line; it was assigned Bloodrage as a *fourth* line
by the previous pass precisely because the pair had no natural identity of its own.

### The swap

| pair | was | becomes |
|---|---|---|
| STR/DEX | `Skirmisher` — Harrier role | **`Berserker`** — leads with Bloodrage, which is what the name means |
| STR/INT | `Berserker` — awkward, INT-flavoured | **`Warblade`** — and drops Bloodrage entirely |

**STR/INT then draws `Duelist`, `Warcry`, `Arcanist`** — a fighter whose strikes and shouts carry
an arcane edge, finishing with Arcanist's execute tools. **Decided: `Warblade`.** It's not just
the clean martial mirror of INT/STR's `Spellblade` — it repeats a naming convention the kept-18
table already uses: `Warrior` (STR/CON) pairs against `Spellsword` (INT/CON), same secondary
stat and same Duellist/Tank-lean role, STR-primary taking the mundane/martial word and
INT-primary the arcane one. `Warblade`/`Spellblade` (STR/INT ↔ INT/STR) repeats that pattern
exactly one stat pair over. The runners-up — **Runereaver** (introduces vocabulary the roster
doesn't otherwise use) and **Warcaller** (overweights the Warcry line at the expense of the
Arcanist capstone) — are kept here for the record, not carried forward.

⚠️ **Doc-only decision.** This names the STR/INT entry within this proposal; it does not touch
`CLASS_REWORK.md` or `src/core.ts` or any other source file — see the proposal-only status at
the top of this document. The 30-class expansion remains unbuilt.

### ⚠️ IT ALSO RETIRES THE `Harrier` RENAME

`Skirmisher` was renamed to `Harrier` as a ROLE only because `Skirmisher` was taken as a CLASS
name. **The class is now `Berserker`, so the collision is gone and the role can keep its own
name.** One fewer invented word, and `Skirmisher` is a clearer role label than `Harrier` was.

### ⚠️ BERSERKER IS A DUELLIST. THE TEN ROLES STAY AT TEN.

I proposed an eleventh role — `Vanguard` — on the grounds that *"wades into the front and
commits to whatever is in front of it"* was not covered. **The user overruled it in three words:
it is a Duellist.** That is correct, and the reasoning I missed is worth writing down, because
it is a rule and not a one-off.

**A Duellist is defined by COMMITMENT TO A SINGLE OPPONENT.** A berserker does exactly that. How
it fights (rage, HP-spend, short and violent) and how it selects (nearest rather than chosen)
are properties of its KIT and its TEMPO — **not of its role**.

### ⚠️ THE PRINCIPLE: ROLES ARE COARSER THAN CLASSES, ON PURPOSE

I was about to add a role because one class felt distinct in FLAVOUR. That is the same error the
original seven-doctrine set made, running the other way — **proliferating categories to capture
nuance that belongs one layer down.**

⚠️ **AND IT DOES NOT STOP AT ELEVEN.** If a role is added every time a class feels different,
the end state is thirty roles for thirty classes and **the role layer does nothing at all.** Its
entire value is being COARSER than the class layer — the thing a spectator reads at a glance,
under which many distinct kits can sit.

**So: a crowded role is the layer WORKING, not failing.** `Duellist` at five or six owners means
five or six classes answer the same battlefield need in different ways — martial, arcane, fast,
patient. That is the roster having range. It is not a distribution problem to be smoothed out,
and the earlier instinct to *"relieve Duellist at 5 owners"* was wrong for the same reason as
the Vanguard proposal.

**The test for adding a role, from now on:** does it describe a genuinely different thing to DO
on the battlefield — a different place to stand, a different thing to go for — or does it just
describe a different way of doing something a role already covers? **Only the first earns a
role.**





**2026-08-03.** Supersedes the first pass at this file (kept in git history). That pass invented
30 assignments top-down; this one **derives** every new class from the same evidence the existing
18 were built on — `CLASS_LINES`/`LINE_OF` content, `CLASS_BASIC` reach bands, and the code's own
flavor comments. Where the evidence was thin, that is said outright rather than smoothed over.

> *"I don't feel like we have enough classes at home in the doctrines. I also think we need to be
> more specific with the doctrines. We need tanks, ranged, assassin types etc."*
> *"Show me some doctrines as I had mentioned, and fill out the 30 classes to fill them."*

⚠️ **A PROPOSAL, NOT A SPEC.** Structure first, names arguable. Nothing here has touched
`CLASS_REWORK.md` or any source file — a later pass folds this in.

---

## 0. Why thirty, and why it isn't padding

Six stats give exactly **30 ordered pairs** (6 primaries × 5 secondaries). The current 18 classes
cover 18 of them; twelve are orphaned — **STR/WIS, STR/INT, DEX/CON, CON/DEX, CON/INT, CON/CHA,
WIS/STR, WIS/CHA, INT/STR, INT/CHA, CHA/CON, CHA/INT.**

Under the emergent model an orphaned pair just fell to `Generalist`, quietly. Under the assignable
model with a stat gate (`CLASS_REWORK.md` §2), an orphaned pair is a **lockout** — a monster whose
top two stats are, say, CON/CHA qualifies for nothing at all. One class per pair closes that hole
completely and **retires `Generalist`** — there is no unmatched pair left for it to catch.

**The Warrior/Spellsword finding generalises.** Two classes can share an identical battlefield
role while answering it with a different power type (STR/CON physical duelist vs INT/CON magical
duelist) — that isn't redundancy, it's the roster having a martial answer and an arcane answer to
the same tactical need. Several of the twelve new classes below are exactly that pattern, mirrored
across a stat's inverse pairing (STR/CHA ↔ CHA/STR was already this; the new pairs add CON/INT ↔
INT/CON, CON/CHA ↔ CHA/CON, and INT/CHA ↔ CHA/INT). That is the argument for why 30 breathes
rather than bloats.

---

## 1. The ten roles — one renamed to close a collision

Unchanged from the prior pass, with one fix: **`Skirmisher` was both a role name and a class
name** — the same collision this project already hit with `cohesion` (formation axis vs
`FieldTraits.cohesion`) and `innate`. Class names are player-facing and came first; the role is
renamed **`Harrier`** (harries, never commits — same intent, no collision). `Herald` stays a class
name only; nothing here calls a role `Herald`.

| Role | Position | Intent | Spatial signature |
|---|---|---|---|
| **Tank** | Front line, center, holds its spot | Soak damage aimed at the team | Doesn't move; enemies cluster on it |
| **Duellist** | Locked onto one opponent — melee or ranged | Win a sustained one-on-one through attrition | Two units visibly paired off, fighting the same fight for most of the clock |
| **Assassin** | Flanks to the backline | Burst-kill an isolated, high-value target early | Peels off, vanishes, reappears next to the healer |
| **Harrier** | Roams the flank/mid-field | Opportunistic — takes what's nearest, disrupts | Never where you left it |
| **Artillery** | Max range, back of the formation | Chip/pin the whole approaching group | Stands still while everyone else moves |
| **Sweeper** | Mid-to-back, or front swinging wide | Area damage across the whole enemy side | A visibly wide effect landing on more than one body |
| **Controller** | Mid-field, LOS not adjacency | Deny/disable — silence, root, charm | The enemy stops doing things near it |
| **Protector** | Near allies, wherever the danger is | Prevent damage to OTHERS | A shield appears on an ally right before a hit lands |
| **Empowerer** | Mid-field, near the damage dealers | Make allies hit harder/faster | Buff icons pulse outward from it |
| **Healer** | Near allies, biased to whoever's lowest | Restore HP, cleanse | HP bars tick back up near it |

`Generalist` is retired (§0) — no orphaned pair survives to need it.

---

## 2. The full thirty

Primary role read off the primary stat's dominant line for THIS pairing; secondary is a lean, never
a second plan (standing guard, unchanged). ⚠️ = a class discussed in §5, weak or notably imperfect
line support.

### The 18 kept as-is
(Unchanged from `CLASS_REWORK.md` §3 — full reasoning there, not repeated.)

| Class | Stats (P/S) | Role (P/S-lean) | `CLASS_BASIC` |
|---|---|---|---|
| Tank | CON/STR | Tank / Sweeper-lean | melee·3.0·CON |
| Warrior | STR/CON | Duellist / Tank-lean | melee·3.0·STR |
| Rogue | DEX/STR | Assassin / Duellist-lean | melee·3.0·DEX |
| Ranger | DEX/INT | Artillery / Sweeper-lean | ranged·8.0·DEX |
| Sage | WIS/INT | Healer / Controller-lean | support·6.0·WIS |
| Wizard | INT/WIS | Sweeper / Controller-lean | magic·7.0·INT |
| Spellsword | INT/CON | Duellist / Tank-lean | melee·3.0·INT |
| Spellshield | CON/WIS | Protector / Healer-lean | melee·3.0·CON |
| Captain | STR/CHA | Sweeper / Empowerer-lean | melee·3.0·STR |
| Orator | CHA/WIS | Controller / Empowerer-lean | support·6.0·CHA |
| Bard | CHA/DEX | Controller / Sweeper-lean | support·6.0·CHA |
| Evoker | INT/DEX | Sweeper / — | magic·7.0·INT |
| Berserker | STR/DEX | Duellist / Assassin-lean | melee·3.0·STR |
| Stalker | DEX/WIS | Duellist / Healer-lean | ranged·8.0·DEX |
| Swashbuckler | DEX/CHA | Harrier / Controller-lean | melee·3.0·DEX |
| Shaman | WIS/CON | Healer / Protector-lean | support·6.0·WIS |
| Mystic | WIS/DEX | Healer / Duellist-lean | support·6.0·WIS |
| Herald | CHA/STR | Empowerer / Sweeper-lean | support·6.0·CHA |

### The 12 new — filling the orphaned pairs

| Class | Stats (P/S) | Role (P/S-lean) | `CLASS_BASIC` | `CLASS_LINES` | Evidence |
|---|---|---|---|---|---|
| **Warpriest** | STR/WIS | Tank / Healer-lean | melee·3.0·STR | Warcry, Duelist, Bloodrage, Mender | Warcry's OTHER half — Guard, Challenge, Intimidate, Bracer — is threat/soak content, not just the Cleave/Whirlwind Captain draws on. Mender gives it battlefield healing. |
| **Warblade** | STR/INT | Duellist / Assassin-lean | melee·3.0·STR | Duelist, Warcry, Arcanist | Named 2026-08-03 (see the swap note at the top of this doc) — a fighter whose strikes and shouts carry an arcane edge, finishing with Arcanist's execute tools. The Bloodrage mismatch flagged in the original §5 finding no longer applies here: Bloodrage moved to `Berserker` (STR/DEX) with the swap. |
| **Marksman** | DEX/CON | Artillery / Tank-lean | ranged·8.0·DEX | Volley, Assassin, Venomcraft, Bulwark | A suppressor tough enough to hold its firing line when charged — Bulwark(self-fortify) reads better against Volley(stand and pin) than against Assassin(dive and vanish). See §5 for the swap. |
| **Warden** | CON/DEX | Controller / Harrier-lean | melee·3.0·CON | Warden, Guardian, Bulwark, Assassin | The CON line named Warden — Seize, Earthen Grasp, Zone of Control, Tremor — has never been a class's dominant line before (Tank draws Guardian first). DEX gives it the mobility to relocate its zone. Same precedent as `Captain` (class name = line name). |
| **Runeguard** | CON/INT | Tank / Duellist-lean | melee·3.0·CON | Guardian, Warden, Bulwark, Arcanist | Mirrors Spellsword (INT/CON, Duellist/Tank-lean) exactly inverted — the arcane answer to Tank, the way Spellsword is the arcane answer to Warrior. |
| **Paladin** | CON/CHA | Protector / Empowerer-lean | melee·3.0·CON | Guardian, Bulwark, Warden, Captain | Guardian(ally-shield) + CHA's Captain-line(rally) — the shield-and-inspire knight. Mirrors Marshal (below). |
| **Enforcer** | WIS/STR | Controller / Tank-lean | support·6.0·WIS | Disruptor, Mender, Siphon, Warcry | ⚠️ **Disruptor's first primary home.** All three existing WIS classes (Sage/Shaman/Mystic) lead with Mender or Siphon and never draw Disruptor at all — 1/3 of WIS's own line pool was undrafted as a primary anywhere. STR's Warcry(Guard/Challenge facet) backs the denial up physically. |
| **Hymnist** | WIS/CHA | Healer / Empowerer-lean | support·6.0·WIS | Mender, Siphon, Disruptor, Captain | Matches the Sage/Shaman/Mystic pattern (WIS-primary → Healer, secondary stat picks the lean) exactly — CHA's Captain-line is the one lean the existing three hadn't used. |
| **Spellblade** | INT/STR | Duellist / Assassin-lean | melee·3.0·INT | Arcanist, Elementalist, Hexer, Duelist | Arcanist's execute tools, precise rather than reckless — the controlled counterpart to Warblade. STR's Duelist-line (finishers, not Bloodrage) gives the burst option. |
| **Warlock** | INT/CHA | Controller / Empowerer-lean | magic·7.0·INT | Hexer, Elementalist, Arcanist, Captain | ⚠️ **Hexer's first primary home**, same gap as Enforcer/Disruptor — Wizard leads Elementalist, Spellsword/Evoker lead Arcanist/Elementalist; Hexer had never been anyone's dominant line. CHA reinforces with its own Enchanter/Demagogue control flavor, but the lean draws the CHA-minority Captain line instead, so Controller isn't doubled from both stats. Mirrors Virtuoso. |
| **Marshal** | CHA/CON | Empowerer / Protector-lean | support·6.0·CHA | Captain, Enchanter, Demagogue, Guardian | Mirrors Paladin (CON/CHA) inverted — the rallying commander whose CHA leads, backed by CON shields instead of leading with them. |
| **Virtuoso** | CHA/INT | Empowerer / Controller-lean | support·6.0·CHA | Captain, Enchanter, Demagogue, Hexer | Mirrors Warlock (INT/CHA) inverted. The third CHA-primary Empowerer (with Herald, Marshal) — consistent with CHA being the stat CLAUDE.md already names as the sole "empowers" stat; each is differentiated by which secondary stat supplies the lean. |

---

## 3. Coverage recount at 30

| Role | Primary owners | Count |
|---|---|---|
| Duellist | Warrior, Spellsword, Stalker, Warblade, Spellblade, Berserker | 6 |
| Controller | Orator, Bard, Warden, Enforcer, Warlock | 5 |
| Tank | Tank, Warpriest, Runeguard | 3 |
| Sweeper | Wizard, Captain, Evoker | 3 |
| Empowerer | Herald, Marshal, Virtuoso | 3 |
| Healer | Sage, Shaman, Mystic, Hymnist | 4 |
| Harrier | Swashbuckler | 1 |
| Artillery | Ranger, Marksman | 2 |
| Protector | Spellshield, Paladin | 2 |
| **Assassin** | **Rogue** | **1** ⚠️ |

Sums to 30. **Every role has at least one primary owner — zero repeats the old Anchor failure
nowhere.** Artillery, thin at 1/18 in the 18-class pass, gained a second owner (Marksman) exactly
as predicted. **Assassin did not** — see §5, this is reported rather than forced.

---

## 4. Reconciling with `FieldTraits.cohesion × predation` — unchanged mechanism, same read

Nothing about the layering changes at 30 classes — role still supplies a `Partial<Tactics>` preset
at the tier `GAMEPLANS.tactics` already occupies; the grid remains the unmodified per-unit fidelity
measure. The quadrant mapping from the 18-class pass holds without modification:

| Quadrant | Roles that default there |
|---|---|
| High cohesion / low predation ("anchor") | Tank, Protector, Empowerer, Healer, Sweeper, Controller |
| Low cohesion / high predation ("assassin") | Assassin |
| Low cohesion / low predation ("skirmisher") | Harrier |
| High cohesion / high predation ("coordinated dive") | *(team-level, via `GAMEPLANS`, not a role default)* |
| ⚠️ Imperfect fit | Artillery (needs neither trait cleanly), Duellist (commitment ≠ predation's target-selection) |

The `retargetIn` fix proposed for Duellist in the 18-class pass (lengthen it so a Duellist resists
switching off its current target) is unchanged and still the one net-new lever this whole exercise
asks for — confirmed live at `tamerengine/types.ts:471`, default `RETARGET_EVERY = 0.6`.

---

## 5. Honest findings — weak line support, not forced

**⚠️ SUPERSEDED 2026-08-03 — see the swap note at the top of this document.** This finding was
originally about the STR/INT pair, then named `Berserker`: Bloodrage's own flavor — ramps as its
OWN health falls, wants a short violent fight — is `docs/ENGAGEMENT_DESIGN.md` §7's own named
"Berserker" archetype, and folding it into Duellist (this document's "commit and grind,
sustained") was a real mismatch. **The swap resolves it on both ends.** Bloodrage moved to
STR/DEX, which now correctly carries the `Berserker` name and the Duellist role — and per
"BERSERKER IS A DUELLIST" (top of doc), the apparent Duellist/short-fight tension was never a
role problem in the first place: commitment to a single opponent is what the role means; rage,
HP-spend and short-fight tempo are properties of the KIT, not the role. STR/INT, meanwhile, lost
Bloodrage entirely and is now named `Warblade`, drawing `Duelist`/`Warcry`/`Arcanist` — a clean
Duellist fit with no borrowed archetype to misrepresent. **The "time preference" doctrine-axis
idea is not needed to close this particular finding**, though it may still be worth exploring on
its own merits.

**Assassin stays at 1/30 even after filling every pair.** None of the twelve orphaned pairs had
strong flank-and-dive evidence. The closest candidate, DEX/CON, was tried both ways: Assassin-lean
reads as "an assassin built to survive being caught," which undercuts the fragile-but-lethal
fantasy the role is built on; Artillery-lean reads as "a suppressor tough enough to hold its line,"
which is a clean fit with no tension. **Taking the swap is the honest call, not the convenient
one** — it says something real: Assassin's population isn't capped by pair-coverage, it's capped
by DEX itself being spread thin across Harrier, Artillery and Duellist already having strong claims
on DEX's other two lines (Volley, Venomcraft). A 31st class wouldn't fix this; DEX doesn't have a
fourth line to draw a second Assassin from.

---

## 6. `ROLE_TACTICS` and station mapping — unchanged from the 18-class pass

No new engine surface at 30 — every new class reuses one of the ten `ROLE_TACTICS` presets and one
of the five existing stations (`Anchor`/`Screen`/`Skirmish`/`Support`/`Free`) already defined for
the 18-class version. Carried forward without modification:

```
ROLE_TACTICS: Record<Role, Partial<Tactics>>
  Tank        → { formation: 'keep', preserve: 'cautious' }
  Duellist    → { comboRole: 'detonate', retargetIn: LONG }
  Assassin    → { comboRole: 'detonate', burst: 'nuke' }
  Harrier     → { targetPriority: undefined }
  Artillery   → { targetPriority: undefined, formation: 'keep' }
  Sweeper     → { targetPriority: undefined }
  Controller  → { ccPriority: true }
  Protector   → { formation: 'keep', healPolicy: 'steady' }
  Empowerer   → { healPolicy: 'steady' }
  Healer      → { healPolicy: 'triage' }
```

Station: Tank→Anchor · Duellist→Anchor(melee: Warrior/Spellsword/Warpriest-adjacent/Runeguard) or
Screen(ranged: Stalker) · Assassin/Harrier→Skirmish · Artillery/Sweeper→Screen ·
Controller/Protector/Empowerer/Healer→Support. The 4-roles-on-one-station gap flagged in the
18-class pass is unchanged and unresolved by adding classes — it's a station-vocabulary
granularity question, independent of class count.

Aura carriers (proximity-sized, per decision): Protector/Empowerer/Healer for team auras,
Controller for enemy-debuff auras — unchanged, now with more classes per role to draw the aura
kit from (e.g. Paladin and Marshal both plausibly want the Protector/Empowerer aura pair).

---

## 7. What's different from the superseded draft, and why

- **11 roles → 10, one renamed.** The prior draft's Bulwark/Vanguard split reads as two flavors of
  Tank rather than two roles with different spatial signatures from the stands — both are "stands
  at the front." This document keeps Tank singular and lets the STAT PAIR (Tank vs Warpriest vs
  Runeguard) carry the flavor difference instead, consistent with the Warrior/Spellsword argument
  in §0. The prior draft's `Warden`(role)/`Mender`(role) are folded into this document's
  `Protector`/`Healer`, which already existed and already had the CLAUDE.md CHA/CON/WIS evidence
  behind them.
- **Every new class is traced to a `CLASS_LINES` entry, not asserted.** The prior draft named
  classes and doctrines together with no line evidence shown; this one shows the line, and where
  the line evidence was weak (Berserker — the STR/INT pair, since renamed Warblade) or pointed the other way from the first guess
  (Marksman/DEX-CON), that's stated rather than smoothed over (§5).
- **The collision fix differs.** The prior draft flagged `Skirmisher`/`Herald` colliding with role
  names and left the choice open. This document only had one real collision (`Skirmisher`, renamed
  to `Harrier`) because it never used `Herald` as a role name in the first place — Herald's role is
  `Empowerer`.
- **Kept from the prior draft, credited:** the framing that three roles (Artillery, Harrier,
  and the aura-carrying support roles) only exist BECAUSE of decisions already taken — arena depth,
  arena width, and proximity auras respectively. That observation is correct and carries over
  unchanged.

---

## 8. Open questions — carried forward, not resolved here

1. ~~**Berserker's fit (§5).**~~ **Resolved 2026-08-03** by the STR/DEX ↔ STR/INT swap at the top
   of this document — see §5's superseded note. `Berserker` (STR/DEX) now correctly carries
   Bloodrage and is confirmed a Duellist; `Warblade` (STR/INT) drops Bloodrage and has a clean
   line fit. The "time preference" doctrine-axis idea remains unexplored but is no longer needed
   to close this specific finding.
2. **Is Assassin at 1/30 a problem?** Argued in §5 that it's a finding about DEX's line pool, not
   a gap to force-fill. Worth a second opinion before treating it as settled.
3. **Do the 12 new classes need new `LINE_OF` content**, or is drafting from the existing 141-move
   pool via the lines above sufficient? This document assumes the latter — every new class's
   `CLASS_LINES` row draws only from the 18 lines that already exist. Not verified against
   population/equip-rate the way the original `CLASS_LINES` table was (that required simulation
   this document hasn't run).
4. **Everything already open in `CLASS_REWORK.md` §9** (CON+CHA gate-floor gap — now moot, since
   Paladin/Marshal fill it — plus discipline-gating for hard-read Tactics fields, reassignment
   gold cost, the cap multipliers, `naturalClass`→`defaultClass`, gate UI flow) is untouched by
   this document and still open.
5. **`Doctrine` → `Role` rename: approved and used throughout this document.** Not yet applied to
   `CLASS_REWORK.md` itself — that file still says `Doctrine` and uses the 7-entry abstract
   palette; folding this document in is explicitly deferred, per the instruction that produced
   this file.
