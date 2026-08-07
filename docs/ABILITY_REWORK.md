# Ability rework (branch `3doverhal`) — design, decisions, and state

The working document for the tamerengine ability pass. Supersedes the scratch notes; the
per-move listing lives in `docs/ABILITIES.md` and the engine's own notes in `docs/TAMERENGINE.md`.

> **Where this sits.** tamerengine's *positioning* is solved (out-of-range 76%→37%, travel/unit
> 119→28, tanks hold a front line, fights stopped being a race). What remained was the **ability
> pool** — both its numbers and its content. This is that work.

---

## 1. What the audit found

Measured over the 90-move pool, with DPS as `power × avg(hits) / (cooldown×0.9 + castTime)`:

| problem | evidence |
|---|---|
| **Progression didn't pay** | In **all 6 stats** the lvl-920 capstone lost to something far earlier: lvl 90 Power Strike **15.4** beat lvl 920 Titanfall **12.3**; lvl 40 Sling 12.5 beat lvl 920 Deadeye 9.1. Training a stat to 920 could leave a monster *worse* than at 90. |
| **Floor below the free attack** | Mana Sap 3.6, Screech 4.4, Discord 4.9 vs a stat-tiered basic at 6.0–8.8. CHA/voice was the weakest damage tier overall. |
| **Keywords were free** | Heartseeker (multi-hit + `execute`) a **60% outlier** at 24.4 DPS vs 15.4 next. |
| **Dead content** | **11 moves did literally nothing**; 29 inert effect instances in the pool, **26 more** across the 50 signatures. Of CON's 15 moves — the TANK stat — three were fully inert and six more had their signature effect dead. |
| **Redundancy** | 4× `regenBuff` (WIS), 4× `manaBurn`, 4× `pierce` (INT), 2× `atkBuff` + 2× `atkDebuff` (CHA). ~10 slots on duplicate ideas. |
| **Unused axes** | **0 of 90** moves authored `range` or `castTime`; every move shared one flat stat coefficient (`/320`). |
| **Mana starvation** | `maxMana = WIS + INT/2` with WIS-only regen starved every physical class — 4–6 ability casts per *whole fight*, and **76% of all casts were the free attack**. |

---

## 2. Decisions taken (user)

- **Progression ≈ 2.5×** first move → capstone, delivered through **stat scaling**, not a flat curve.
- **Re-price `moves.ts` globally** (single source of truth), **deliberately recapturing the 12 goldens**.
- **The pool may GROW** — nothing off the table.
- ⚠️ **Class design is the ONLY hard rule.** Damage, stat scaling, cooldown, mana, range, keywords
  and status are all **per-ability design axes**, traded creatively and judged by sim. No global
  formula derives the pool; formulas only seed a starting point.
- **AoE is strongest into many bodies and weak into one** — not exempt from costing, just
  conditional on target count.
- **Mana is a trading axis**: a move may be stronger somewhere and simply cost more MP.
- **Nothing falls below the free attack** (peaks 8.8 DPS) — the one hard rule beyond class design.
- **Hybrid class model**: class stays emergent from stats; a player-chosen **battle role** drives
  positioning/personality.
- **Flanking**: +10% accuracy vs a target engaged by **2+ enemies with no adjacent ally**.
- **Passive abilities** may be taken instead of an active.
- **CC diminishing returns**, arena-style; **cleanse grants brief CC immunity** as compensation.
- **Three playstyle LINES per stat**, one of them a **flagship** with a real loop.
- **~24 per stat (144 total)**, built in **two passes**.

---

## 3. The design

### Three lines per stat, for multi-classing

A class emerges from the top **two** stats, so 3 lines per stat gives **3 × 3 = 9 build identities
per stat pair** — on the order of **80 recognisably different builds**. Multi-classing becomes
"which two *lines* am I combining", not "which two stats are highest".

**Shape: 3 lines × 8 = 24 per stat**, each line ~7 actives + **1 passive that is the payoff for
committing to it**.

⚠️ **The pool grows for AVAILABILITY, not variety.** `learnedMoves` gates by stat, so at 6 per line
a mid-game monster reaches only 3–4 of its chosen line — barely a loadout and no choice, meaning
**lines would only exist at endgame**. Aim ~5 of each line's 8 learnable by stat ~450.

⚠️ **Two passes**: rework the existing 90 into the 3-line structure first (~18/stat), sim it,
confirm lines read as distinct — *then* deepen to 24. Authoring 54 new moves before knowing the
structure works would repeat how the pool got 11 dead moves and four duplicate `regenBuff`s.

⚠️ Passives must stay *situationally* strong. The moment one is strictly better than an active, the
4-slot decision collapses.

### One flagship per stat

The test is whether the line has **its own win condition or resource loop**, not flavour:

| stat | flagship | loop | other two lines |
|---|---|---|---|
| **STR** | **Berserker** | **HP is a resource** — recoil hurts you, missing health *is* the damage buff; you spend life and race the clock | Duelist (precision/finish) · Wrestler (grab/push/stun) |
| **CON** | **Warden** | **Decide the geometry** — Seize drags a diver in, Shield Wall denies the crossing, Zone of Control slows adjacent | Guardian (protect others) · Juggernaut (retaliate, remaining-HP) |
| **DEX** | **Assassin** | **Stealth → burst → vanish** — every piece needs the one before it | Marksman (precision) · Volleyer (volume/variance) |
| **INT** | **Hexer** | **Stack, then detonate** — burn, vulnerable, a ticking bomb, then Cinderburst cashes it in | Artillery (single-target) · Elementalist (AoE/zones) |
| **WIS** | **Disruptor** | **Resource denial** — steal, silence, zone them out; the enemy never casts | Battery (feed team mana) · Mender (sustain) |
| **CHA** | **Enchanter** | **Action denial** — charm turns them on each other, sleep gives one free hit, fear routs | Captain (team buffs) · Demagogue (debuff/punish) |

Six ways to win — self-damage economy, spatial control, burst-and-escape, status detonation,
resource denial, action denial. **None is "deal more damage."**

### Per-stat notes

- **STR** — highest single-target melee on the shortest reach, and it *commits* (heavy moves get
  real wind-up). **Power Strike** must lose ~25%: it is the game's damage ceiling at **lvl 90**.
  New: **Grapple** (pull+root), **Enrage** (atkBuff on missing HP), **Blood Fury** (damage on
  missing HP — the line's payoff *attack*, so the loop pays out through more than modifiers),
  **Sunder** (armour break — the setup STR lacks).
- **CON** — **a support stat, not a damage stat.** Only ~4 damage moves, all *conditional*:
  Body Slam, Shell Slam (`hpScale`), Colossus Crash, and new **Bulwark Breaker** (scales with
  **current** HP — a healthy tank hits, a broken one doesn't). ⚠️ **Bastion and Fortify are
  duplicate plain wards** — make Fortify a **team** ward. New: **Seize** (grab), **Shield Wall**
  (zone), **PASSIVE Bodyguard** (redirect damage aimed at your lowest-HP ally), **PASSIVE Immovable**.
- **DEX** — high accuracy, multi-hit, mobility; **variance is the flavour**. **Heartseeker** keeps
  `execute` but loses the multi-hit. The three dead moves become identity: **Sidestep** (dodge +
  dash), **Focus Aim** (accBuff + guaranteed crit), **Blur** (dodge + fade). **Pin Down** reworked
  from a limp `accDebuff` into a real **root**. New: **Shadowstep**, **Ambush**, **Throat Cut**,
  **Vanish**, **Hamstring**, **Gambler's Volley** (1–6 hits), **PASSIVE Opportunist**.
- **WIS** — wins the **resource** race, not the damage race. ⚠️ Consolidate 4× `regenBuff` → 2.
  **Mana Sap** (worst move in the game) → a true **mana steal**. New: **PASSIVE Font of Power**
  (allies gain MANA per second — categorically unlike CHA's buffs: it doesn't make allies stronger,
  it makes their abilities *affordable*), **Null Field** (zone silence), **Spirit Siphon**
  (channelled), **Foresight**.
- **INT** — two genuinely competitive builds. ⚠️ Thin 4× `pierce` → 2. **Thunderclap** (inert
  `firstStrikeMult`) → line AoE + knockback. **Static Chain** → actually chains. **Glacial Prison**
  is a bad deal (5.9 DPS for a 25% stun at lvl 540). New: **Firewall** (zone), **Frost Nova**
  (rewards being surrounded — the anti-melee tool casters lack), **Arcane Bomb** (delayed).
- **CHA** — buffs/debuffs first, only ~4 damage moves but they must clear the free attack. The
  control suite is the best-designed thing in the pool — keep it all. ⚠️ Differentiate the duplicate
  atkBuff/atkDebuff pairs into single-target-strong vs team-wide-weak. New: **PASSIVE Captain's
  Order** (aura), **Rally**, **Dirge**, **Crowd Surge** (push — a *defensive* use of a debuff stat).

### Mechanics

**Already in the engine, authored by nothing:** ground zones (`spatial.zone`), cone/line AoE
(`area.shape`), grab (`pull`), push, root, fade, blink — plus **`castTime`** (wind-up, so heavy
moves are punishable) and **`range`**, both in the `Move` type and used by **0 of 90** moves.

**Genuinely new:** **delayed detonation** (only possible because the field has continuous time, and
*dodgeable* — the first real reaction counterplay), **auras** (what makes passives interesting),
**channelled** (reuses cast-rooting), **mark** (amplify next hit — a `vulnerable` variant).

### Combos

Existing: Bloodletter ← bleed · Cinderburst ← burn · Siren's Call ← fear · Mind Crush ← doom.

New: **Shatter** (← stun/freeze) · **Defenceless** (← silence, mana-drain payoff) · **Wake-up call**
(← sleep; it breaks on hit so you get exactly one shot) · **Marked** · and **Dragged** ⭐ — Seize
pulls a target in and your melee focus it: **positional, not keyword**, the first combo the turn
engine could never have expressed.

Combos are deliberately cross-line and cross-stat, so they reward the multi-class pairs the game
already generates.

---

## 3b. Class kit table (P3 — the pass's contract)

⚠️ **This is the one thing tested strictly.** Everything else is a guideline.

### How a class gets its kit

`classForStats` takes the top **two** stats and needs an **exact (primary, secondary) match** — of
30 ordered pairs only these 11 are classes; everything else is **Generalist**. `learnedMoves` gates
by stat *value*, so a class has deeper access to its **primary** pool than its secondary. That is
what separates classes sharing a pair: **Tank (CON+STR)** and **Warrior (STR+CON)** draw on the same
two wells, but the Tank reaches further into CON and the Warrior further into STR.

### What each pool actually supplies (measured)

| stat | dmg | self-buff | **team/ally** | debuff | heals | statuses |
|---|---|---|---|---|---|---|
| STR | 11 | 4 | **0** | 0 | 0 | bleed, vulnerable, stun |
| DEX | 10 | 4 | **0** | 1 | 0 | poison, bleed, haste, vulnerable, knockback |
| CON | 3 | 10 | **0** | 2 | 5 | knockback |
| INT | **15** | **0** | **0** | **0** | **0** | burn, vulnerable, stun |
| WIS | 4 | 7 | 3 | 1 | 3 | silence, doom |
| CHA | 9 | **0** | 3 | 3 | 0 | blind, healblock, fear, confusion, sleep, charm, haste |

### The gaps this exposes

1. ⚠️ **CON has ZERO team/ally-targeted moves.** All ten of its buffs are `self`. So the Tank's and
   Spellshield's "protect others" identity is currently **impossible** — a Guardian that can only
   shield itself is not a guardian. **The single biggest hole in the pool.**
   → needs: team ward, ally-targeted guard/shield, and the **Bodyguard** damage-redirect passive.
2. ⚠️ **INT is 15/15 damage** — no buffs, debuffs, heals or team play at all. A Wizard or Spellsword
   contributes nothing but damage, and every scrap of utility must come from its secondary stat.
   → needs: the Elementalist zones and Hexer utility to carry INT's non-damage weight.
3. ⚠️ **CHA has zero self-buffs** — a Bard or Orator cannot protect itself at all, and CHA is also
   the weakest damage tier. Doubly fragile.
4. **Captain's team buffs number 3**, all from CHA — thin for a class whose whole identity is
   commanding a team.
5. ~~**No pool has a root or a slow.**~~ ⚠️ **This finding was WRONG** — corrected while fixing it.
   `Pin Down`, `Snipe`, `Glacial Prison`, `Deep Freeze`, `Earthshaker` and `Static Chain` all carry a
   root or slow in `SPATIAL_MOVES`. The real gaps were narrower: **CON had none**, and **INT's were
   all lv540+**, so a mage had no denial until very late.
6. **CON's only status is knockback**, so the Warden line has shove and nothing else for denial.

### ⚠️ Resolutions (shipped — commits `033fb90`, `3c215a3`)

Fixing these needed work at **three layers**. A move can be authored perfectly and still never reach
a single monster's kit — which is what was actually happening.

**Authoring** (`src/moves.ts`, pool **90 → 100**):

| gap | fix |
|---|---|
| 1 — CON can't protect | `Barbed Carapace`/`Fortify`/`Stone Wall` → `team`, `Steady Vigil` → `ally`, repriced via authored `mana` (24/44/48/18) |
| 2 — INT is all damage | `Arcane Aegis` (team ward), `Elemental Infusion` (team atk+acc), `Mirror Image` (self dodge) — INT's first non-damage moves ever |
| 3 — CHA can't protect itself | `Bravura` (self ward+dodge), `Hymn of Shields` (team ward+guard, covers the singer) |
| 4 — Captain thin | Captain gained a `CLASS_UTILITY_SLOTS` profile; now equips `Hymn of Shields` + `Barbed Carapace` |
| 5 — mage denial too late | `Rime Bind` (root, lv160), `Frost Nova` (AoE slow, lv280) |
| 6 — Warden has only shove | `Seize` (pull+root), `Quagmire Stomp` (AoE slow), `Shield Wall` (slow zone) |

**Engine** — *buffs are uncapped and affect ALL allies, better ones cost more*:
a team buff already **applied** to every ally, but `bestUtility` **scored** it as the single best
beneficiary, so its whole reach never entered the comparison and a team ward lost to a self ward
absorbing a sixth as much. Now valued as the **total** it delivers, with authored `mana` pricing the
better buff. Team-buff casts across the 12-fight sim: **9 → 176**.

**Loadout** — the layer that was silently discarding the rest: the universal buff fallback tested
`target === 'self'` **alone**, so a team buff could never claim the slot however good it was
(`Arcane Aegis`: 53% learnable, **0% equipped**). Team-wide is now preferred, self is the fallback.
Only 5 of 11 classes had a utility profile; Captain/Wizard/Spellsword added from the table below.

⚠️ **Second correction**: "CHA has zero self-buffs" was **partly a measurement artifact** — the audit
counted `target: 'self'` only, and CHA's three team buffs already include the caster. The genuine
lack was a *defensive* option for the weakest damage tier, which `Bravura` now supplies.

⚠️ **Two traps this pass discovered the hard way:**
- **`spatialOf` reads only the name-keyed table.** An inline `spatial` on a *pool* move is silently
  inert — the same failure mode as the 8 entries that were once innate names. Rename a move in
  `moves.ts` ⇒ rename its `SPATIAL_MOVES` key.
- **A move must carry its identity in SHARED data, not only a field-side table.** `Shield Wall` was
  first authored with no `effects` at all: inert in the turn engine, and invisible to every loadout
  predicate (they read `effects`). The four control moves needed the same treatment — their denial is
  expressed as `knockback` ("acts last") in shared data so both engines and the ranker can see it.

**Still open (the known `chooseLoadout` trap, P4):** `Seize`, `Rime Bind` and `Frost Nova` are
authored, registered and functional but score **0% equipped** — they are deliberately low-power
(control traded for damage) and `chooseLoadout` ranks on damage-per-cast, so the ×1.15 status nudge
cannot lift them. They are player-equippable via Edit Abilities; only auto-selection misses them.
This is exactly what the **line affinity** work below is for.

### Per-class contract

| class | pair | role | identity | lines it should favour | key need |
|---|---|---|---|---|---|
| **Tank** | CON+STR | support | soaks and **protects others**; decides the geometry | CON Guardian / Warden | ⚠️ team-targeted protection (gap 1) |
| **Warrior** | STR+CON | damage | front-line damage that commits and endures | STR Duelist / Berserker | armour-break setup (Sunder) |
| **Rogue** | DEX+STR | damage | gets behind you and kills one thing | DEX Assassin | Shadowstep, Ambush, Vanish |
| **Ranger** | DEX+INT | damage | **focuses the most critical enemy** at range | DEX Marksman / INT Artillery | a real root to hold the target |
| **Sage** | WIS+INT | support | sustains and cleanses; the resource anchor | WIS Mender / Battery | Font of Power aura |
| **Wizard** | INT+WIS | damage | burst or attrition, player's choice | INT Artillery / Hexer | zones; INT has no utility (gap 2) |
| **Spellsword** | INT+CON | damage | a caster that holds the line | INT Artillery + CON Juggernaut | conditional-HP damage |
| **Spellshield** | CON+WIS | support | warder — shields and dispels | CON Guardian + WIS Mender | ⚠️ team wards (gap 1) |
| **Captain** | STR+CHA | damage | fights *and* commands | CHA Captain + STR Duelist | more team buffs (gap 4) |
| **Orator** | CHA+WIS | support | debuffs, silences, breaks morale | CHA Demagogue + WIS Disruptor | ⚠️ self-protection (gap 3) |
| **Bard** | CHA+DEX | support | back line: **buffs the team AND damages** | CHA Captain / Enchanter | ⚠️ CHA damage floor + self-protection |

### Line affinity solves the loadout problem

⚠️ Declaring **which lines each class favours** (the column above) is also the fix for the
`chooseLoadout` trap in §5: the picker ranks "best per stat" and knows nothing about lines, so it
would draft one move from each of three lines and every generated monster — every rival in the game
— would read as incoherent mush. Given per-class line affinity it can instead prefer moves from the
class's affine lines, and generated monsters come out coherent. One mechanism, two problems solved.

---

## 4. Built so far

### P1 — authoring axes (commit `4fe69bf`)

- **`Move.statScale`** — per-ability coefficient in `power × (1 + stat × scale)`, replacing the flat
  `/320`. Wired into `strike()` **and** its `estimateDamage()` mirror (they must match or kill-checks
  and `worthSpending` misjudge finishers). `defaultStatScale(learnLevel)` seeds it only.
- **`Move.mana`** — authored MP cost wins over the derived formula.
- ⚠️ **`STAT_SCALE_LOW` is pinned at the OLD 1/320 so the change only ever ADDS.** A first cut used
  1/420 and silently nerfed every low/mid move — and since `learnedMoves` gates by stat, mid-game
  monsters can only equip low/mid moves, so the whole mid-game got weaker (damage/fight 28.9k→27.3k).
  **Progression must pay by lifting the top, not lowering the bottom.** HIGH is 1/150.
- ⚠️ **Field-only by nature, so goldens did NOT move**: `battle.ts` uses a different curve
  (`power × hits × (atk/40)^0.8 × 0.5`), not a linear stat coefficient. The accepted recapture comes
  when **P4 changes `power`**.

**Result — progression now pays in all six stats** (it previously failed in all six), and the gap
**widens with investment**. At stat 900, starter → capstone: STR 44→86 (1.97×) · INT 32→57 (1.81×) ·
CHA 28→53 (1.91×) · WIS 15→48 (3.28×) · DEX 48→64 (1.34×) · CON 44→52 (1.20×). **DEX/CON lag the
2.5× target — per-ability tuning in P4.**

### P2 — eight of nine inert effects + CC DR (commit `eb9bbec`)

`ward` (absorb pool, soaks before health) · `guard` (flat DR after the multipliers, floored at 1 so
never true immunity) · `thorns` (reflect per hit taken, on any hit — what makes it an answer to a
ranged focus) · `cleanse` · `dodgeBuff`/`accBuff` (percentage **points** in the accuracy roll) ·
`hpRegenBuff` · **`firstStrikeMult`** → ⚠️ keys off `actedThisRound` in the turn engine and a
continuous field has **no rounds**, so it became "target hasn't attacked yet" (`hasAttacked`) — an
*opening-burst* reward.

`mods` was **extended** rather than growing six parallel timers, so expiry stays in one place; the
new accumulators **sum** (flat/points) rather than multiply.

**CC diminishing returns** — 100/75/50/25/immune, 3s reset, **global**. Global on purpose: mixing a
silence with a charm gets no discount, which is what caps the lockout build. CON resists control
natively (a floor on the meter). Cleanse grants ~1.2s immunity but ⚠️ **does not reset the meter**,
or cleansing your own ally becomes a DR-wipe. `CONTROL_STATUSES` deliberately excludes DoTs —
poison/burn/bleed leave you playing, so metering them would let a DoT kit burn away the protection
that exists to cap *lockout*.

⚠️ **The chooser had to learn to VALUE these** — they scored zero, the actual reason nobody ever cast
one. Every score is **situational** (ward/guard/thorns/dodge scale with heat on the target): a flat
value turns a defensive cooldown into a tic, which this engine has shipped twice.

**Result: 12 of 15 formerly-dead moves now get cast.** The 3 that don't are correct — `Clarity` is a
pure cleanse with nothing to cleanse; `Insight`/`Focus Aim` are bare +10/+12 accuracy scoring **7.8
against a `UTILITY_FLOOR` of 8**. Not padded to pass a test; they earn their slots in P4 with riders.

Also: mana-by-role and the 4th slot shipped just before this pass — see §6.

---

## 5. Remaining

| phase | work |
|---|---|
| **P2b** | **`spreadStatus`** — held back deliberately. Most likely effect to spiral once AoE is real; the codebase records **Ember being rejected** as a carrier because adding a spread moved three goldens including two winner flips. Build and sim alone. |
| **P3** | **Class kit table** — per-class identity/keywords/statuses, mapped to the stat pair it emerges from, with a **have vs need** gap list. The pass's contract, and the one thing tested strictly. |
| **P4** | **Rework + author the pool** (may grow), incl. **passives** and re-authoring the 50 signatures. ⚠️ Then **recapture the 12 goldens** in their own commit. |
| **P5** | **Mana retune for four slots.** |
| **P6** | **Class identity on the field + flanking.** |
| **P7** | **Movement/displacement + per-move ranges**; merge the 18 `fieldMoves` into the pool; then Shadowstep/Disengage/Stealth. |
| **P8** | **Sweep + tests + verification.** |

### Traps already identified

- ⚠️ **`chooseLoadout` knows nothing about lines.** It ranks "best per stat", so it will draft one
  move from each of three lines and every generated monster — i.e. every rival — will read as
  incoherent mush, leaving the line structure meaningful only for hand-built player loadouts. It
  needs line-awareness ("prefer moves sharing a line with what's already picked").
- ⚠️ **Passives must be excluded** from `chooseMove`/`bestUtility`, from `reachOf` (or a passive's
  channel sets the unit's stand-off distance — the exact bug that parked bruisers outside their own
  swing), and from `basicAttackFor`'s channel pick; `validate.ts` must not count them as damage moves.
- ⚠️ **The AI must score CC by its POST-DR duration**, or monsters spend stuns on saturated targets
  for nothing.
- ⚠️ **`validate.ts:54-60` caps signature power at the pool ceiling for its shape** — re-pricing the
  pool re-caps the signatures automatically. Route signature strength through **stat scaling**, the
  axis that isn't capped.
- **Zones and delayed detonation change fight *shape*, not just damage** — they pull units off
  positions, and this engine has repeatedly shown movement changes have surprising second-order
  effects. Own sim pass.
- **Root is strong in a continuous engine** — it counters kiting, diving and grabs at once. Short
  durations, DEX/INT only.

---

## 6. Measured baselines (for tuning against)

Harness scripts live in the session scratchpad — `sweep.ts` (duration/travel/kills/resolved),
`castmix.ts` (basic vs ability share), `mpuse.ts` (mana pressure), `whymove.ts`
(cast/pace/approach/block split), plus the pool audits. 12 fights = 4 matchups × 3 seeds, `train:850`.

| stage | duration | travel/unit | resolved <55s | notes |
|---|---|---|---|---|
| pre-engagement-rework | 58.5s | 119.1 | 2/12 | out-of-range 76.3%, casting 9.9% |
| after backpedal penalty | — | 80 | — | the pursuit-equilibrium fix |
| after usable basic + Block | — | 52 | — | casting 14.2% |
| after Tank-as-anchor | 45.7s | 28.2 | **7/12** | out-of-range 41.8% |
| after stat-tiered free attack | 66.3s | 47 | 0/12 | filler correctly weak → nothing carried damage |
| after mana-by-role | 50.2s | 36.5 | 4/12 | basic share 76%→53% |
| after 4th slot | 66.9s | 37.8 | 1/12 | can't-afford-cheapest 35%→**56%** |
| **after P1 (statScale)** | 66.9s | 37.8 | 1/12 | non-regressive; progression added |
| **after P2 (effects real)** | 68.0s | 43.1 | 0/12 | ⚠️ defence being real makes fights longer |

**Acceptance targets**: resolve **≥8/12** before sudden death · duration **30–45s** · ability share
of casts **>60%** · mana starvation **<20%** · travel/unit near **28–37**.

### ⚠️⚠️ EVERY "kills" FIGURE ABOVE IS WRONG — and so was the diagnosis built on it

The sweep harness counted `e.kind === 'dead'`. **The engine emits `'death'`** (see the `FieldEvent`
union in `types.ts`). So the counter returned 0 for the entire pass, and "0 kills" was reported for
weeks. Re-measured with the right name, the same sweep has **51 kills**.

The diagnosis that grew out of it — *"56% of the HP pool is removed with zero kills, so resolution is
blocked by damage spread"* — is **retracted**. It was an artifact.

**The second, larger instrument bug: the sweep was not representative.** Its five species
(kongrath, aegisox, maneleo, grivvel, ursath) produce only **Warrior / Tank / Rogue** — STR, CON and
DEX. **No INT, WIS or CHA at all.** So every INT/WIS/CHA change in this whole rework was invisible to
it, which is why the P4 floor pass — 7 INT moves lifted — moved measured field damage by **+0.2%**.

A class-diverse sweep (`dsweep.ts`, 12 species spanning 12 classes) tells a completely different
story, and the engine is in far better shape than the table above suggests:

| sweep | resolved | duration | kills | reading |
|---|---|---|---|---|
| **class-diverse (12 classes)** | **9/12** | **42.9s** | 53 | **already meets the acceptance targets** |
| old mammal-only (Warrior/Tank/Rogue) | 1/12 | 64.2s | 51 | an all-bruiser mirror grinding on mitigation — a pathological matchup, not a baseline |

⚠️ **Use `dsweep.ts` for all further balance work.** The mammal sweep is still useful as a *worst
case* (high-CON teams with no caster), but it must never again be read as the game's baseline.

**The real finding it surfaced — STR is the weakest stat on the field**, despite the STR pool having
the highest paper DPS:

| class | dmg/fight | | class | dmg/fight |
|---|---|---|---|---|
| Wizard | 323 | | Rogue | 138 |
| Sage | 307 | | Bard | 126 |
| Generalist | 271 | | Spellsword | 113 |
| Spellshield | 154 | | **Warrior** | **57** |
| Orator | 153 | | **Captain** | **9** |

Casters free-cast from range; melee spends the fight closing and being kited. That is a **P6 class-
identity/flanking** problem, not a numbers problem — resist the urge to fix it by inflating STR power.

### After P4's floor pass (commit `bc715a4`)

Pool floor violations **12 → 0**; `Heartseeker` 137.8 → 54.4 DPS, so the capstone leads DEX again.
Field effect on the mammal sweep was negligible (+0.2% damage) for the representativeness reason
above — the fix is real, the instrument just could not see it.

---

## 6b. P4 loadout / P5 mana / P6 flanking — shipped, with the measurements

### P4 loadout ranking (`78b784a`)

**`expectedOutput` had no cooldown term**, so `chooseLoadout` ranked damage-per-CAST
rather than per second, and had always preferred a big slow move to a better sustained
one. Now divided by cooldown. Found the long way: three attempts, two wrong.

| attempt | result |
|---|---|
| weight the status nudge by what the status does (hard control 0.4 / DoT 0.3 x chance) | Rime Bind 0% -> **37%** equipped across TEN classes — homogenised |
| drop the coefficient to 0.25, BELOW the old flat 1.15 | still 36% — so the nudge was never the cause |
| divide by cooldown | overshoot gone, and control back to 0% |

⚠️ **The lesson: a control move cannot be made to WIN a damage comparison.** It is
deliberately low-power — control traded for damage. Nudge it enough to win and it takes
over; leave it and it never appears. So the class that NEEDS denial **reserves a slot**,
exactly as a Tank reserves one for its taunt. Ranger **63%** / Wizard **76%** / Tank
**80%** of kits now carry hard control, and only those three classes do.

### P5 mana (`16a7b11`) — all four targets met

`FIELD_MANA_COST_MULT` **0.5 -> 0.22**, swept one knob at a time.

| mult | starved | basic share | resolved | duration |
|---|---|---|---|---|
| 0.50 | 66.1% | 57% | 8/12 | 45.5s |
| 0.32 | 42.2% | 47% | 10/12 | 39.8s |
| **0.22** | **18.4%** | **38%** | **9/12** | **42.4s** |
| 0.15 | 12.3% | 35% | 10/12 | 41.2s |

Not the lowest value on purpose: below ~0.18 mana stops being a constraint you can run
out of, deleting an axis of play. The worst-case mammal sweep gained most: **1/12 -> 5/12**.

### P6 flanking (`ef485e8`) — and a corrected diagnosis

+10 accuracy POINTS against a defender engaged by 2+ enemies with no ally within 3.2u.
Warrior damage **57 -> 82** per fight.

⚠️ **"Melee spends the fight closing and being kited" was WRONG.** Time-in-state by reach:

| | dead | move | cast | idle |
|---|---|---|---|---|
| MELEE | **44%** | 29% | **14%** | 12% |
| RANGED | 26% | 32% | 28% | 13% |

Move time is the SAME. **Melee dies at 1.7x the rate**, and dead units cast nothing —
that is the entire 4x class-damage gap. The remedy is survivability and formation (soak,
protect, guard uptime), **not** gap-closers, per-move ranges or bigger STR numbers.
⚠️ This directly undercuts P7's premise: gap-closers would not have touched the cause.

---

## 7. Standing rules that apply

- **Balance iteratively**: nudge one value, sim, read, adjust. The sim is the arbiter (CLAUDE.md).
- **Units are not uniform**: `atkBuff`/`pierce`/`execute` are **fractions**; `dodgeBuff`/`accBuff`/
  `accDebuff`/`defBuff` are percentage **points**.
- **Everything stays on `3doverhal`.** The main game is not replaced until tamerengine is complete
  (M7). The 12 goldens move exactly once, deliberately, in P4.
