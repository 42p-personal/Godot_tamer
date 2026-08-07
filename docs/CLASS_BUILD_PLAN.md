# Class Build Plan — 30 assignable classes, concrete and shovel-ready

**2026-08-04.** This document turns two proposals — `docs/CLASS_REWORK.md` (assignable classes,
the stat gate, per-class caps) and `docs/DOCTRINES_AND_CLASSES.md` (the 30-class/10-role
expansion) — into one buildable spec. Nothing here re-litigates either document's reasoning;
where they agree this is a merge, where they conflict or leave a gap this says so explicitly and
makes a call (flagged ⚠️ **PLAN CALL** so it's easy to find and overturn).

**Where this sits in the build order:** `docs/AUTOBATTLER_DESIGN.md` §12 #35 — *"Assignable
classes land right after the tree AI, so the tree is tuned against the final role set."* This
document is the plan for that slot. §7 of this document splits the work so the parts with **no**
dependency on the tree AI can land earlier as pure data (§7 Stage 0); only the role/doctrine →
`Tactics` wiring genuinely has to wait.

⚠️ **THE BALANCE BASELINE IS STILL SUSPENDED.** Every specific number in this document — the
`{1.00, 0.90, 0.70}` cap tier multipliers, the `0.20` gate floor, the reassignment gold/weeks cost
— is structure, not a measured value. They are written down so the STRUCTURE is buildable now;
the values are queued for the deliberate re-baseline per `CLAUDE.md`, one value at a time.

---

## 0. The species-lockout guarantee, stated up front

`CLAUDE.md`'s standing rule: **a SPECIES must never be locked out of a role. Aptitude may make a
path slower or shallower; it must not forbid it.**

This plan satisfies it with a proof, not a spot-check:

> **Claim:** once a monster's single highest stat has crossed the gate floor (§3.2), at least one
> class is always assignable, for any possible stat spread.
>
> **Proof:** let `P` = the monster's rank-0 (highest) stat and `S` = its rank-1 (second-highest)
> stat, tie-broken by the fixed `STATS` order (`STR, DEX, CON, WIS, INT, CHA`) exactly as
> `classForStats` already does. `rank(P) = 0 ≤ 1` and `rank(S) = 1 ≤ 2` — both gate rank
> conditions are trivially satisfied. Because the 30-class table (§1) is **every one of the 6×5
> ordered stat pairs**, there exists exactly one class `C` with `primary = P, secondary = S`. The
> only remaining gate condition is `stats[P] ≥ floor`, and `P` is the monster's LARGEST stat by
> construction, so if the monster has trained *any* stat past the floor, its top stat has too.
> Therefore `C` is always available the moment any real training has happened. ∎

This is strictly stronger than the 18-class table's guarantee, where an orphaned pair (e.g.
CON+CHA, WIS+STR) could leave a monster with **zero** eligible classes (`CLASS_REWORK.md` §2.3
Example B). At 30 classes that failure mode is **structurally impossible** — the gate can only
ever be *unmet* because of insufficient training (temporary, fixable by the player), never because
of an unmatched stat shape (permanent, unfixable). That is exactly the "slower or shallower, never
forbidden" contract the standing rule asks for, and it now holds for every species regardless of
its trained stat shape, not just the ones lucky enough to land on one of the 18 originally-mapped
pairs.

The only residual case: a **freshly generated, untrained monster** — flat stats, nothing past the
floor. It qualifies for nothing via the gate. That's fine and intentional: it isn't reassigning
anything yet, it's wearing its **species default class** (§4), which is assigned at generation and
bypasses the gate entirely (`CLASS_REWORK.md` §1.1). The gate only ever governs *reassignment*.

---

## 1. The 30 classes — concrete data, paste-ready

### 1.1 Naming and identity decided upstream, applied here

- **`Skirmisher` (STR/DEX) → `Berserker`.** Same stat pair, same `CLASS_LINES`, same
  `CLASS_BASIC` — pure rename, decided `docs/DOCTRINES_AND_CLASSES.md` (top of file, 2026-08-03).
  It is the only class that leads with the `Bloodrage` line, so the old name was simply wrong.
- **`STR/INT` → `Warblade`**, newly filled (was orphaned under the 18-class table).
- **`Generalist` is retired as an assignable class.** All 30 ordered stat pairs now have a real
  class, so there is no unmatched pair left for it to catch (`DOCTRINES_AND_CLASSES.md` §0). See
  §1.4 for what this means for the engine's defensive fallback.
- ⚠️ **PLAN CALL — the `Harrier`/`Skirmisher` role-name contradiction.** `DOCTRINES_AND_CLASSES.md`
  contains two conflicting statements about the *role* name for the flank/mid-field position: a
  note near the top ("IT ALSO RETIRES THE `Harrier` RENAME") says it should revert to
  `Skirmisher` now that the class collision is gone, but the document's own working body (§1's
  role table, §3's coverage recount, §6's `ROLE_TACTICS`/station table) uses `Harrier`
  throughout and was never edited to match. **This plan uses `Harrier`** — it's what every
  functional table in the source document actually uses — and flags the top note as stale
  prose that should be corrected or the body updated, whichever the team prefers. See §8.1.

### 1.2 The master table

`Role` primary is a real behavioural default (composed into `Tactics`, §5); `Role` secondary is a
**tiebreak lean only**, never a second full behaviour (`CLASS_REWORK.md` §3.1, carried forward
unchanged at 30 classes per `DOCTRINES_AND_CLASSES.md` §4). `Comp.` is the EXISTING
`ClassRole`/`roleOfClass()` axis (damage/support, composition-only) — see §1.3 for why this is
a different thing from `Role` despite the name collision.

| # | Class | Stats (P/S) | Role (P / S-lean) | `CLASS_BASIC` | `CLASS_LINES` | Comp. |
|---|---|---|---|---|---|---|
| 1 | Tank | CON/STR | Tank / Sweeper | melee·3.0·CON | Guardian, Warden, Warcry | support |
| 2 | Warrior | STR/CON | Duellist / Tank | melee·3.0·STR | Duelist, Bloodrage, Bulwark | damage |
| 3 | Rogue | DEX/STR | Assassin / Duellist | melee·3.0·DEX | Assassin, Venomcraft, Duelist | damage |
| 4 | Ranger | DEX/INT | Artillery / Sweeper | ranged·8.0·DEX | Volley, Assassin, Elementalist | damage |
| 5 | Sage | WIS/INT | Healer / Controller | support·6.0·WIS | Mender, Siphon, Hexer | support |
| 6 | Wizard | INT/WIS | Sweeper / Controller | magic·7.0·INT | Hexer, Elementalist, Arcanist, Disruptor | damage |
| 7 | Spellsword | INT/CON | Duellist / Tank | melee·3.0·INT | Arcanist, Elementalist, Bulwark | damage |
| 8 | Spellshield | CON/WIS | Protector / Healer | melee·3.0·CON | Guardian, Bulwark, Warden, Mender | support |
| 9 | Captain | STR/CHA | Sweeper / Empowerer | melee·3.0·STR | Captain, Warcry, Duelist | damage |
| 10 | Orator | CHA/WIS | Controller / Empowerer | support·6.0·CHA | Demagogue, Enchanter, Captain, Disruptor | support |
| 11 | Bard | CHA/DEX | Controller / Sweeper | support·6.0·CHA | Captain, Enchanter, Demagogue, Volley | support |
| 12 | Evoker | INT/DEX | Sweeper / — | magic·7.0·INT | Elementalist, Arcanist, Volley | damage |
| 13 | Berserker | STR/DEX | Duellist / Assassin | melee·3.0·STR | Bloodrage, Duelist, Assassin | damage |
| 14 | Stalker | DEX/WIS | Duellist⚠️ / Healer | ranged·8.0·DEX | Assassin, Venomcraft, Siphon | damage |
| 15 | Swashbuckler | DEX/CHA | Harrier / Controller | melee·3.0·DEX | Volley, Assassin, Demagogue | damage |
| 16 | Shaman | WIS/CON | Healer / Protector | support·6.0·WIS | Mender, Disruptor, Guardian | support |
| 17 | Mystic | WIS/DEX | Healer / Duellist | support·6.0·WIS | Mender, Siphon, Venomcraft | support |
| 18 | Herald | CHA/STR | Empowerer / Sweeper | support·6.0·CHA | Captain, Demagogue, Warcry | support |
| 19 | Warpriest | STR/WIS | Tank / Healer | melee·3.0·STR | Warcry, Duelist, Bloodrage, Mender | support |
| 20 | Warblade | STR/INT | Duellist / Assassin | melee·3.0·STR | Duelist, Warcry, Arcanist | damage |
| 21 | Marksman | DEX/CON | Artillery / Tank | ranged·8.0·DEX | Volley, Assassin, Venomcraft, Bulwark | damage |
| 22 | Warden | CON/DEX | Controller / Harrier | melee·3.0·CON | Warden, Guardian, Bulwark, Assassin | support |
| 23 | Runeguard | CON/INT | Tank / Duellist | melee·3.0·CON | Guardian, Warden, Bulwark, Arcanist | support |
| 24 | Paladin | CON/CHA | Protector / Empowerer | melee·3.0·CON | Guardian, Bulwark, Warden, Captain | support |
| 25 | Enforcer | WIS/STR | Controller / Tank | support·6.0·WIS | Disruptor, Mender, Siphon, Warcry | support |
| 26 | Hymnist | WIS/CHA | Healer / Empowerer | support·6.0·WIS | Mender, Siphon, Disruptor, Captain | support |
| 27 | Spellblade | INT/STR | Duellist / Assassin | melee·3.0·INT | Arcanist, Elementalist, Hexer, Duelist | damage |
| 28 | Warlock | INT/CHA | Controller / Empowerer | magic·7.0·INT | Hexer, Elementalist, Arcanist, Captain | support |
| 29 | Marshal | CHA/CON | Empowerer / Protector | support·6.0·CHA | Captain, Enchanter, Demagogue, Guardian | support |
| 30 | Virtuoso | CHA/INT | Empowerer / Controller | support·6.0·CHA | Captain, Enchanter, Demagogue, Hexer | support |

30 rows, all 30 ordered stat pairs, zero collisions, zero gaps — mechanically checkable against
`STATS × (STATS \ {primary})`.

⚠️ Rows 1–18 are the existing 18, ported unchanged from `CLASS_REWORK.md` §3.3 (cross-checked
against the LIVE `src/lines.ts` and `src/tamerengine/types.ts:CLASS_BAND` — identical) except the
row-13 rename and the role-terminology fold-in (§1.3). Rows 19–30 are new, sourced verbatim from
`DOCTRINES_AND_CLASSES.md` §2's "12 new" table.

### 1.3 ⚠️ PLAN CALL — resolving the `Role`/`Role` name collision

`DOCTRINES_AND_CLASSES.md` renamed `CLASS_REWORK.md`'s 7-value `Doctrine` axis to a 10-value
**`Role`** axis (Tank/Duellist/Assassin/Harrier/Artillery/Sweeper/Controller/Protector/
Empowerer/Healer) in its design prose. But the codebase **already has** an unrelated `Role`
concept: `src/core.ts`'s `ClassRole = 'damage' | 'support'`, `CLASS_ROLES`, `roleOfClass()` — the
team-COMPOSITION axis, used by rival-team templates and `manaRoleOf`. Naming both concepts `Role`
in code would be exactly the kind of collision this project has hit before (`cohesion`,
`innate`, `Skirmisher`).

**This plan keeps `Doctrine` as the CODE identifier** (`ClassDef.doctrine: { primary: Doctrine;
secondary?: Doctrine }`, matching `CLASS_REWORK.md` §7.1's original naming, just with the 10-value
enum instead of 7) **and reserves "Role" for design prose and UI-facing copy only** — the master
table above uses "Role" as a column header for readability, but the field that ships in `core.ts`
is `doctrine`. The existing `ClassRole`/`CLASS_ROLES`/`roleOfClass` stay exactly as named.

This is a judgement call, not a fact pulled from either source doc — flag it for confirmation
before implementation (§8.2).

### 1.4 Generalist — retired, but kept as an inert engine fallback

`Generalist` is removed from the 30-class table and is never assignable, never gated, never a
species default. But `classify.gd`'s `basic_attack_for()` already defends against an unrecognized
class name via `table.get(cls, table.get("Generalist"))` — **recommend keeping one dead
`Generalist` entry in `CLASS_BASIC`/`CLASS_ROLES`** (melee·3.0·STR / damage, unchanged from today)
purely as that safety net. It should never be reachable through legitimate play; `validate.ts`
should assert exactly that (§6).

### 1.5 Composition role (`CLASS_ROLES`) for the 12 new classes — derived, not guessed

Cross-checking the existing 18 `CLASS_ROLES` entries against their primary `Doctrine` in the
master table turns up an exact, exception-free rule:

> **`roleOfClass(c) === 'support'` iff `c`'s primary doctrine ∈ {Tank, Controller, Protector,
> Empowerer, Healer}; otherwise `'damage'`.**

Verified against all 18 existing entries with zero exceptions (e.g. Wizard is Sweeper-primary →
damage even though it's INT-primary and "feels" caster-support-adjacent; Swashbuckler is
Harrier-primary → damage). Applying the same rule to the 12 new classes rather than assigning by
feel:

| Class | Primary doctrine | Comp. role |
|---|---|---|
| Warpriest | Tank | support |
| Warblade | Duellist | damage |
| Marksman | Artillery | damage |
| Warden | Controller | support |
| Runeguard | Tank | support |
| Paladin | Protector | support |
| Enforcer | Controller | support |
| Hymnist | Healer | support |
| Spellblade | Duellist | damage |
| Warlock | Controller | support |
| Marshal | Empowerer | support |
| Virtuoso | Empowerer | support |

Result: 13 damage / 17 support across the 30 (was 10/8 across the 18 before Generalist's removal).
Already folded into §1.2's table.

### 1.6 `ROLE_TACTICS` (code name `DOCTRINE_TACTICS`) and station mapping

Unchanged shape at 30 classes, per `DOCTRINES_AND_CLASSES.md` §4/§6 — reused verbatim, ten
entries instead of seven:

```
DOCTRINE_TACTICS: Record<Doctrine, Partial<Tactics>>
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

Precedence (unchanged from `CLASS_REWORK.md` §5.1, still the right shape): player's explicit
per-fight orders / rival `GAMEPLANS.tactics` → monster's own standing `Monster.tactics` → class
doctrine's default (primary fills first, secondary fills only fields primary left unset) →
`DEFAULT_TACTICS`.

Station: Tank→Anchor · Duellist→Anchor (melee: Warrior/Spellsword/Warpriest/Runeguard/Warblade/
Spellblade) or Screen (ranged: Stalker) · Assassin/Harrier→Skirmish · Artillery/Sweeper→Screen ·
Controller/Protector/Empowerer/Healer→Support. This is a station-vocabulary granularity gap
(4 roles sharing one station) that predates this plan and is out of scope here.

**⚠️ This entire section (§1.6) is Stage 1 in the build order (§7) — it depends on the tree AI
existing**, per `AUTOBATTLER_DESIGN.md` #35's ordering. Everything in §1.1–§1.5 does not.

---

## 2. The stat-cap model — how it composes with league caps

**One ceiling system stacks on top of another; they never fight.** `statCapFor(c)` (existing,
unchanged) already folds together league cap × bloodline `potential` × gen-1 clamps
(`WILD_GEN1_CAP`, `FUSION_GEN1_CAP`, `PRESTIGE_GEN1_CAPS`, `PRIMEVAL_GEN1_CAP`) into one scalar.
The class cap **multiplies that scalar's output**, never its inputs:

```
classCap(stat, class, c) = statCapFor(c) × relationMult(stat, class)

relationMult(stat, class) =
  1.00  if stat is class.primary
  0.90  if stat is class.secondary
  0.70  otherwise (the four off-class stats)
```

Because `relationMult` never exceeds 1.00, `classCap` only ever **tightens** the existing ceiling,
never loosens it — a class's primary stat is mathematically identical to today's uncapped
behaviour; the restriction lands entirely on the four off-class stats (0.70) and lightly on the
secondary (0.90). This is the full composition — there is no second place a cap gets applied, and
no interaction to reconcile beyond "multiply the existing number."

**Worked example (Platinum Wizard, INT/WIS, potential 1.05, not gen-1):**
```
statCapFor(c) = 900 × 1.05 = 945
INT cap (primary)   = 945 × 1.00 = 945
WIS cap (secondary)  = 945 × 0.90 = 851
STR/DEX/CON/CHA cap  = 945 × 0.70 = 662  (each)
```

Full worked examples for Wood, Masters-with-gen1-clamp, and Tamers Apex are in `CLASS_REWORK.md`
§4.2–4.4 and are unchanged by moving from 18 to 30 classes — the formula doesn't know how many
classes exist, only which two stats the ASSIGNED class names.

**The `{1.00, 0.90, 0.70}` values are unmeasured** (§ intro) — the 3-tier STRUCTURE is settled,
the multipliers are queued for the re-baseline, one value at a time, exactly as `CLASS_REWORK.md`
§4.5 already states.

---

## 3. Assignment rules

### 3.1 When a class is first assigned

- **At generation, every monster gets a species DEFAULT class**, bypassing the gate entirely — no
  player choice, so nothing to gate. This is `Species.naturalClass`, repurposed and renamed
  `Species.defaultClass` (§4.1) to stop implying a derivation that no longer exists.
- **Rivals and wild-generated monsters are unaffected.** They keep using `classForStats(stats)`
  live at generation time, exactly as today (`CLASS_REWORK.md` §7.1, `DECISIONS_2026-08-03.md`
  #17) — this whole plan only changes what happens to a PLAYER monster after it exists.

### 3.2 The stat gate (`classesAvailableFor`)

Unchanged mechanism from `CLASS_REWORK.md` §2.2, now evaluated against the 30-class table:

```
function classesAvailableFor(stats: Stats, career: Career): string[] {
  const ranked = [...STATS].sort((a, b) => stats[b] - stats[a])   // descending, stable on ties
  const rank = (s: Stat) => ranked.indexOf(s)                      // 0 = highest
  const floor = GATE_FLOOR * statCapFor(career)                    // proposed GATE_FLOOR = 0.20
  return CLASSES
    .filter(c => rank(c.primary) <= 1 && rank(c.secondary) <= 2 && stats[c.primary] >= floor)
    .map(c => c.name)
  // No Generalist branch needed — every ordered pair has a real class (§0's proof).
}
```

**The CON+CHA gap `CLASS_REWORK.md` §2.3 Example B flagged as unresolved is now closed** —
`Paladin` (CON/CHA) and `Marshal` (CHA/CON) both exist. Re-running that example's exact stat
spread (`CON 320, CHA 300, INT 260, STR 150, WIS 140, DEX 110`) against the 30-class table:
`rank(CON)=0, rank(CHA)=1` → `Paladin` (CON primary, CHA secondary) qualifies outright, alongside
whatever else the top-3 spread opens. Zero classes is no longer a reachable outcome for any stat
shape once the floor is met (§0).

### 3.3 Reassignment cost — gold AND weeks, not gold alone

⚠️ **`CLASS_REWORK.md` §1.1 is out of date here** — it only specifies a gold cost (left TBD). The
governing decision is `AUTOBATTLER_DESIGN.md` §8 #24: *"Class is re-assignable at a real cost
(gold + retraining weeks)."* This plan carries the weeks component forward as a real mechanical
requirement, not just a gold sink:

- **Reassignment is not instant.** Choosing a new (gate-eligible) class starts a **retraining**
  activity, occupying the monster's weekly activity slot — the same slot `Rest`/`Excursion`
  already occupy — for **N weeks (TBD, unmeasured)**. The monster cannot train stats during this
  window; the new class and its caps take effect the week retraining completes.
- **Gold cost (TBD, unmeasured)** is paid up front, when retraining is confirmed.
- **Both numbers are explicitly deferred** to the economy rebalance pass, per `CLAUDE.md`'s
  roadmap ("deliberately LAST, once the new sinks/sources... are all in, so it's balanced against
  reality in one pass") and `CLASS_REWORK.md` §9.2 item 5. This plan lands the MECHANICAL HOOK
  (an activity type + a cost parameter) with placeholder values clearly marked TBD; it does not
  invent numbers.

### 3.4 Non-punitive guarantee (unchanged from `CLASS_REWORK.md` §1.1)

- **Reassignment never retroactively shrinks a trained stat.** A stat already above the new
  class's cap for it freezes — no further gain until the class changes again or bloodline
  `potential` rises — but it is never reduced.
- **Losing gate-eligibility for your own current class never un-assigns it.** The gate fires only
  at the moment of a NEW assignment/reassignment attempt, never as a standing condition — training
  is monotonic, so there's no sequencing exploit (`CLASS_REWORK.md` §2.4).

---

## 4. Migration — what happens to a monster that already exists

`CLASS_REWORK.md` §7.1 says "absent [`assignedClass`] means still on the species default" without
separately addressing monsters that already have real trained stats at the moment this ships. That
ambiguity matters: defaulting an already-trained, non-default-shaped monster to its SPECIES
default the instant the update lands could retroactively reclassify it into something its owner
never chose and never trained toward — precisely the kind of surprise `CLASS_REWORK.md` §1.3
already promises not to inflict ("converting an existing save's stat block into 'wasted'
investment... would be a worse first impression than any amount of design purity").

**⚠️ PLAN CALL, resolving the ambiguity:** on first load after this ships, run a **one-time
migration pass**: for every existing player monster, compute its CURRENT emergent class via
`classForStats(currentStats)` and snapshot that into `assignedClass`. This is not a new rule — it
is the literal reading of "don't retroactively punish," applied to the one case
`CLASS_REWORK.md` didn't spell out:

- The monster's observable identity does not change the instant the patch lands (it keeps
  whatever class it would have emergently been).
- The per-stat cap becomes active immediately afterward. Any stat already trained above ITS new
  class-relative cap freezes exactly per §3.4 — no reduction, ever.
- Freshly generated monsters (post-migration) get the species-default behaviour of §3.1 as
  normal — this migration pass only runs once, against the save as it exists at patch time.
- Rivals/wild monsters need no migration — they were never stored, §3.1.

**Also required, batched into this same pass:** `Species.naturalClass` → `Species.defaultClass`
rename across all 65 species entries (`CLASS_REWORK.md` §9.2 item 7) — mechanical, but touches
every species row plus any doc referencing the old name (`grep -rl naturalClass`).

---

## 5. Contract recapture — exactly what moves in `classify.json`

`monster-tamer/data/classify.json` is generated by `npx tsx tools/exportport.ts` from
`src/tamerengine/classifyFixtures.ts` — **never hand-edit the JSON**; every change below is a
change to `classifyFixtures.ts` (and, for the two new pure functions, a new fixtures file), then
regenerate.

### 5.1 `classForStats` axis (15 existing cases)

| case | old expect | new expect | why |
|---|---|---|---|
| STR primary, DEX secondary | Skirmisher | **Berserker** | rename only, same pair |
| WIS primary, CHA secondary | Generalist | **Hymnist** | pair filled |
| CHA primary, INT secondary | Generalist | **Virtuoso** | pair filled |
| "an unmatched stat pair falls to Generalist" (WIS/STR input) | Generalist | **Enforcer** | pair filled — **and the case's premise is now false: no pair is unmatched.** Must be renamed/repurposed, not just re-valued (see below) |
| a perfect tie resolves by declaration order (STR/DEX) | Skirmisher | **Berserker** | rename only |
| an all-zero monster still gets a class | Skirmisher | **Berserker** | rename only |
| *(remaining 9 cases: STR/CON→Warrior, DEX/STR→Rogue, DEX/INT→Ranger, CON/STR→Tank, INT/WIS→Wizard, INT/CON→Spellsword, WIS/INT→Sage, CHA/STR→Herald, CHA/WIS→Orator)* | unchanged | unchanged | pair already existed in the 18-class table |

**The "falls to Generalist" case must be replaced, not edited in place** — its own name asserts a
behaviour (Generalist fallback) that no longer exists anywhere in the system. Recommend replacing
it with a case that asserts the NEW invariant instead: `"classForStats never returns Generalist
once all 30 pairs are mapped"`, iterating all 30 ordered pairs and asserting none resolve to
`'Generalist'`.

**Recommend adding 9 new dedicated cases** for the new pairs not already incidentally covered by
the 3 repurposed cases above: STR/WIS→Warpriest, STR/INT→Warblade, DEX/CON→Marksman,
CON/DEX→Warden, CON/INT→Runeguard, CON/CHA→Paladin, INT/STR→Spellblade, INT/CHA→Warlock,
CHA/CON→Marshal — bringing every one of the 12 new classes under explicit test, matching how the
original 11 + orphan-7 were each individually tested.

### 5.2 `roleOfClass` axis (19 existing cases)

- `"role of Skirmisher"` → rename to `"role of Berserker"`, same expected value (`damage`).
- `"role of Generalist"` → reframe rather than delete: assert the DEFENSIVE fallback still
  resolves (`damage`, per §1.4) while noting in the case name that it's unreachable through normal
  play (e.g. `"Generalist remains a safe fallback, never assigned"`).
- **Add 12 new cases**, one per new class, using the derived table in §1.5 (`"role of Warpriest"`
  → `support`, `"role of Warblade"` → `damage`, … `"role of Virtuoso"` → `support`).
- The other 17 existing cases are unchanged.

### 5.3 `manaRoleOf` axis (5 existing cases)

No existing case references a renamed or newly-filled pair (`Tank`, `Sage`, `Warrior` ×2,
`Wizard` are all untouched by this rework) — **zero forced changes**. Recommend ADDING 1–2 cases
exercising a new class on each side of the role split (e.g. `Hymnist` as WIS-primary-support,
`Warpriest` as STR-primary-but-CON-topped-tank) so the new classes get at least one pass through
this axis, but this is a coverage improvement, not a correction.

### 5.4 `basicAttackFor` axis (7 existing cases)

**Zero expected VALUES change.** None of the 7 test inputs resolve to a renamed or newly-filled
class except the "zero stats" case, whose underlying class flips `Skirmisher → Berserker`
internally — but `basicAttackFor`'s output (channel/stat/power/range/cooldown/accuracy/castTime)
never exposes the class NAME, so the asserted JSON is byte-identical. Worth a one-line comment
update in the fixture noting the identity change, not a value change. Recommend adding one case
exercising a new class's `CLASS_BASIC` row for coverage, though every band×stat combination the
new 12 classes use (melee·STR/DEX/CON/INT, ranged·DEX, magic·INT, support·WIS/CHA) is already
exercised by at least one existing class in the current 7 cases.

### 5.5 New axes needed — a new contract file, not a bigger `classify.json`

`classesAvailableFor` (§3.2) and `classCapFor` (§2) are genuinely new pure functions, not
variations on the four `classify.json` already contracts. `classify.json`'s own header names its
subject precisely as those four existing functions — folding two structurally new ones in would
make that header a lie. **Recommend a new file, `monster-tamer/data/classgate.json`**, built the
same way (`classGateFixtures.ts` → `exportport.ts` → Godot `classgate.gd`), covering:

- `classesAvailableFor` — the worked examples in `CLASS_REWORK.md` §2.3 (now re-run against 30
  classes; Example B's "qualifies for zero" no longer occurs, replace it with a case demonstrating
  the floor-not-met scenario instead, which is the only remaining reason for an empty result)
  plus at least one case demonstrating the §0 proof directly (top-2 stats always yield ≥1 class).
- `classCapFor` — the three worked examples in `CLASS_REWORK.md` §4.2–4.4, re-run per class.

### 5.6 Net effect on the 46 count

Exact final count is whatever `classifyFixtures.ts` regenerates to (never hand-count into the
JSON) — but the shape of the change is: 46 existing cases, ~5 re-valued in place, 1 restructured,
~22 new cases added across the four existing axes (9 `classForStats` + 13 `roleOfClass` +
~2 `manaRoleOf` + ~1 `basicAttackFor`), plus a new `classgate.json` file with its own case count
for the two new functions. `run_contract.sh` is the ground truth once regenerated.

---

## 6. `validate.ts` guard changes

- **Retire** the check that `classForStats(sp.base) === sp.naturalClass` for all 65 species
  (`src/validate.ts:161-166`) — `naturalClass`/`defaultClass` is no longer required to match a
  live derivation once it's a stored default (`CLASS_REWORK.md` §7.3).
- **Add:** every species' `defaultClass` is a valid entry in the 30-class `CLASSES` table.
- **Add:** every entry in `CLASSES` has `doctrine.primary` set; `DOCTRINE_TACTICS` has all 10
  `Doctrine` values present (no silently-unused enum member).
- **Add:** `Generalist` is NOT present in `CLASSES` (retirement is enforced, not just documented).
- **Add — the five-new-stats tripwire the task calls out explicitly:** `STATS.length === 6`, and
  none of `Discipline/Nerve/Aggression/Focus/Speed` appear in `STATS`. These five personality/speed
  fields live on an entirely separate structure (`AUTOBATTLER_DESIGN.md` §3/§4) and never touch
  `classForStats`/`classesAvailableFor`/`classCapFor` today by construction — this guard exists so
  a *future* refactor that merges the two structures fails loudly instead of silently reclassifying
  the population, which is exactly the risk the task flagged.

---

## 7. Staged build order

Split so the parts with no AI dependency can land independently, per `AUTOBATTLER_DESIGN.md`
#31/#35's ordering (`spike → tree AI → assignable classes → art/modes`).

### Stage 0 — Class taxonomy expansion (no tree-AI dependency, can land any time)
Pure data: add the 12 new `ClassDef` entries, rename `Skirmisher`→`Berserker`, retire
`Generalist` from `CLASSES` (keep the defensive fallback, §1.4), extend `CLASS_LINES`/`LINE_OF`/
`CLASS_BASIC`/`CLASS_ROLES` to 30. `classForStats()` stays live/emergent for everyone exactly as
today — this stage changes *what it can return* (30 outcomes, never Generalist), not *who calls
it*. Recapture `classify.json` per §5. Update `classify.gd`/`data.json` regen. Update
`validate.ts` per §6 (except the doctrine/`DOCTRINE_TACTICS` checks, which wait for Stage 1).
**This alone already fixes the "Generalist measured as the top damage class" absurdity
(`CLAUDE.md`) and the "7 of 18 lines never a primary" gap (`docs/HANDOVER.md` §8) — real value
before assignability exists at all.**

### Stage 1 — Doctrine/Role + `DOCTRINE_TACTICS` (waits for the tree AI)
Add `ClassDef.doctrine`, the 10-value `Doctrine` enum, `DOCTRINE_TACTICS` (§1.6), and wire it into
the tree AI's `Tactics` precedence stack. Depends on the tree AI existing to tune against — this
is the one piece `AUTOBATTLER_DESIGN.md` #35 is actually gating.

### Stage 2 — Gate + cap as pure functions (parallelizable with Stage 1)
Build `classesAvailableFor` and `classCapFor` (§2, §3.2) as pure functions with no UI or
data-model dependency. New `classgate.json` contract (§5.5) and unit tests off the worked
examples. Can be built and verified in complete isolation from Stage 1.

### Stage 3 — Data model + call-site migration
`Career.assignedClass` field; `careerMonster`/`newCareer` read it (falling back to
`Species.defaultClass`); `statCapFor` → `classCapFor` per-stat inside the `applyWeek`/
`previewWeekEffects` training loop (the one non-mechanical call-site change,
`CLASS_REWORK.md` §7.2); the four `chooseLoadout` call sites in `monster.ts` take an authoritative
`className` parameter instead of re-deriving it; the one-time migration pass (§4).

### Stage 4 — UI
Ranch detail panel: Assign/Reassign control gated by `classesAvailableFor()`, showing which stats
freeze under the incoming cap before the player commits (§3.4's promise has to be VISIBLE, not
just true). Badge displays across `App.tsx` switch from live `classForStats(c.stats)` to the
stored `c.className` (simpler than today, per `CLASS_REWORK.md` §7.2).

### Stage 5 — Reassignment economy
Land the mechanical hook (retraining activity type + gold cost parameter) with values marked TBD;
actual numbers wait for the deliberate economy rebalance pass (§3.3).

### Stage 6 — Godot port
Mirror each of Stages 0–3 into `monster-tamer/scripts/` (`classify.gd` extension,
`classgate.gd`), regenerating contracts at each stage rather than in one final dump — keeps the
port honest against a moving TypeScript target instead of translating a frozen snapshot.

---

## 8. What I think is wrong, or unresolved, in the source documents

### 8.1 The `Harrier`/`Skirmisher` role-name contradiction (§1.1)
`DOCTRINES_AND_CLASSES.md` asserts in one place that the role name should revert to `Skirmisher`
now that the class-name collision is gone, then uses `Harrier` throughout every functional table
that follows. This reads like a note added after a rename decision was reversed, without the body
being updated to match. Needs a deliberate pick — this plan picked `Harrier` because it's what
every load-bearing table actually uses, but that's a default, not a re-affirmed decision.

### 8.2 The `Doctrine`/`ClassRole` naming collision (§1.3)
Neither source document notices that "Role" is already a taken name in the live codebase
(`ClassRole`, composition damage/support). This plan resolves it by keeping `Doctrine` as the code
identifier and treating "Role" as design-prose-only — worth an explicit sign-off since it means
the design docs' vocabulary and the code's vocabulary will diverge on purpose.

### 8.3 `CLASS_REWORK.md` §1.1 is silent on retraining time
It specifies a gold cost (TBD) for reassignment and nothing else. `AUTOBATTLER_DESIGN.md` #24
(the newer, authoritative decision per the task) adds a weeks-based retraining cost.
`CLASS_REWORK.md` should get a short addendum noting #24 supersedes its gold-only framing, so a
future reader of `CLASS_REWORK.md` alone doesn't miss the weeks component.

### 8.4 Migration wasn't actually specified for already-trained monsters
`CLASS_REWORK.md` §7.1's "absent means still on species default" reads as sufficient but only
cleanly covers monsters with little or no training investment. §4 of this plan proposes a
one-time snapshot-to-current-emergent-class migration instead — consistent with the document's
own non-punitive philosophy, but it's an addition this plan is making, not a restatement.

### 8.5 `Doctrine`/`Role` value-set migration wasn't flagged as a breaking contract change
`CLASS_REWORK.md` §7.1 defines `Doctrine` as 7 values; `DOCTRINES_AND_CLASSES.md` §1 effectively
replaces it with 10 without ever saying so explicitly — it just starts using different names
(`Anchor` disappears, `Tank`/`Duellist`/`Assassin`/`Harrier`/`Artillery` appear). Anyone
implementing from `CLASS_REWORK.md` §5 alone without also reading `DOCTRINES_AND_CLASSES.md`
would build the wrong enum. This document is the fix for that gap, but the two source docs
should cross-reference each other explicitly (`CLASS_REWORK.md` §7.4 already lists this as a
planned pass — recommend doing it now that this plan exists to point to).

### 8.6 The Control-thinness question is still open, and arguably answered differently at 30
`CLASS_REWORK.md` §9.2 #1 asks whether 2-of-18 at the primary Control tier is too thin. At 30
classes, `Controller` (the renamed/expanded Control doctrine) has 5 primary owners (Orator, Bard,
Warden, Enforcer, Warlock) — a real improvement worth noting back into that open question, since
the 30-class expansion answers it more completely than `DOCTRINES_AND_CLASSES.md` §3.4's own
recount (which was computed against the OLD 18-class table before the new classes existed).
