# Innates + happiness on `tamerengine`, and the removal of `tameness` — mapping doc

**Stage 1 of the port-blocker work (`docs/DECISIONS_2026-08-03.md` #1).** Read-only audit.
No engine code has been touched yet. This is the artefact the next stage implements against.

⚠️ **Confirmed: `INNATE_EFFECTS` has ZERO references anywhere in `src/tamerengine/`.**
`grep -r INNATE_EFFECTS src/tamerengine` returns nothing. The table lives and is read entirely
inside `src/battle.ts` (the turn engine) and `src/validate.ts` (a name-key guard). Everything
below is about giving it — and happiness — a place on the field engine.

---

## 0. ⚠️ "Innate" is an overloaded word — read this before anything else

`species.innate` / `INNATE_EFFECTS` (this doc's subject) and `tamerengine/personality.ts`'s use
of "innate" are **two unrelated concepts that happen to share a name**:

| | what it means | where |
|---|---|---|
| **Species innate** (this doc) | A named passive ability (`Ability { name, desc }`), one of two per species, keyed into `INNATE_EFFECTS` for its numeric effect | `core.ts:380` (`Ability`), `core.ts:389` (`Species.innate: Ability[]`), `battle.ts:87` (`INNATE_EFFECTS`) |
| **Personality "innate"** | The monster's BASELINE value of a personality axis (aggression/teamplay/mental/temperament/awareness/patience) BEFORE the player's Tactics coaching is blended in — nothing to do with species abilities | `personality.ts:4` ("Four innate axes, 0..100"), `personality.ts:73` ("innate, plus any drift"), `personality.ts:105-114` (`coachedValue(innate01, coached01, temperament)`), `decide.ts:35` ("innate aggression/teamplay"), `decide.ts:478-480` (`innatePanic`) |

`personality.ts`'s `Personality` type (`core.ts:429`) is a completely separate struct from
`species.innate`/`activeInnate`. **Nothing in this doc touches `personality.ts` or `decide.ts`'s
"innate" fields, and nothing there should be touched by this work.** Flagging this because the
name collision is exactly the kind of thing that causes a future change to land in the wrong
file.

---

## 1. Inventory: how many distinct EFFECT KINDS

`InnateEffect` (`battle.ts:46-85`) has **30 distinct fields**, plus **one name-keyed special
case** that isn't a data field at all (Truth's Word). 130 species-innate slots across 65 species
map onto these 31 kinds via `INNATE_EFFECTS: Record<string, InnateEffect>` (`battle.ts:87-244`).

Grouped:

| group | fields | count |
|---|---|---|
| **A. Flat defensive/accuracy additions** (self) | `flatDR`, `dodge`, `acc` | 3 |
| **B. Regen** (self) | `regen` (mana), `hpRegen` | 2 |
| **C. Unconditional damage multiplier** (self) | `dmgMult` | 1 |
| **D. Conditional damage multipliers** (self, gated on a runtime condition) | `firstHitMult`, `lowHpDmgMult`, `highHpDmgMult`, `magicDmgMult`, `executeMult` | 5 |
| **E. Combat-math axes read directly by the formula** (self) | `crit`, `pierce` | 2 |
| **F. On-cast mechanic** | `echo` | 1 |
| **G. On-hit procs** (self, post-hit) | `lifesteal`, `manaSteal`, `statusOnHit` | 3 |
| **H. One-time setup** (self) | `startWard` | 1 |
| **I. Buff/debuff duration modifiers** (self, on-cast) | `buffExtend`, `debuffExtend` | 2 |
| **J. Incoming-debuff mitigation** (self, defender) | `debuffResist` | 1 |
| **K. Team-wide auras** (every living ally incl. owner) | `auraFlatDR`, `auraDodge`, `auraRegen`, `auraHpRegen`, `auraDmgMult` | 5 |
| **L. Enemy-facing debuff auras** (every living enemy) | `enemyAccDebuff`, `enemyDodgeDebuff`, `enemyRegenDebuff`, `enemyDmgDebuff` | 4 |
| **M. Name-keyed special case** (not a data field) | Truth's Word cleanse | 1 |
| **Total** | | **31** |

Supporting code in `battle.ts`: the per-unit self-total aggregator `innateEffects()`
(`battle.ts:279-321`), `currentInnate`/`activePassives`/`hasInnate` (`battle.ts:271-327`), and the
per-round aura/enemy-debuff resolver `recomputeInnateAuras()` (`battle.ts:533-555`, called once
before round 1 and once per round thereafter). Truth's Word is `truthsWordCleanse()`
(`battle.ts:408-426`), invoked once per round from the main loop (`battle.ts:1730`, gated
`round % 3 !== 0`).

---

## 2. Per-kind mapping: battle.ts application · tamerengine placement · verdict

### Group A — flat additions (self)

| kind | `battle.ts` | `tamerengine` placement | verdict |
|---|---|---|---|
| `flatDR` | Added into the flat mitigation term alongside `target.defFlat`: `battle.ts:1432` | `damage.ts:StrikeInput.defGuard` (`damage.ts:73-74`) is already a generic "FLAT reduction, subtracted last, capped" scalar, fed by `modGuard(target)` at the `strike()` call site (`engine.ts:1714`) | **Portable.** No interface change — fold into `defGuard` at the call site before invoking `resolveStrike`. |
| `dodge` | Added to `dodgeChance(stats)`: `battle.ts:1278`, `1347` | `damage.ts:StrikeInput.dodgeMod` (`damage.ts:67-68`), fed by `modDodge(target)` at `engine.ts:1711`, and separately at the pre-`resolveStrike` accuracy roll `engine.ts:1688` | **Portable.** Fold into `dodgeMod` in both places it's read. |
| `acc` | Added to `move.accuracy`: `battle.ts:1276`, `1345` | `damage.ts:StrikeInput.accMod` (`damage.ts:59-60`), fed by `modAcc(u)` at `engine.ts:1703` and `engine.ts:1688` | **Portable.** Same pattern as `dodge`. |

### Group B — regen (self)

| kind | `battle.ts` | `tamerengine` placement | verdict |
|---|---|---|---|
| `regen` (mana) | `battle.ts:1618` (real regen in `takeTurn`), also read by the AI's block-to-charge heuristic `battle.ts:1086` | `tickMath.ts:TickInput.mods[].regen` exists but is **round-limited** (from cast buffs), summed via `modRegen` (`tickMath.ts:94`). No slot for a PERMANENT per-unit bonus. | **Needs new engine surface, small.** Add an explicit `TickInput.innateRegen?: number` (or synthesize a permanent `TickMod` with `until: Infinity` — messier, reuses a concept documented as round-limited). Recommend the explicit field. **Contract: `tick.json`.** |
| `hpRegen` | `battle.ts:1620` | Same shape as `regen`, via `modHpRegen` (`tickMath.ts:103-106`) | **Needs new engine surface, small.** Add `TickInput.innateHpRegen?: number`. **Contract: `tick.json`.** |

### Group C/D — damage multipliers (self, attacker-side)

All of these are attacker-side multiplicative terms. `battle.ts` applies them directly in its
real per-hit damage function (roughly `battle.ts:1340-1470`); the field-engine equivalent,
`engine.ts:strike()` (`engine.ts:1667-1730`), already builds ONE combined `atkMult` scalar
(`modAtk(u)`, `engine.ts:1699`) and hands it to `damage.ts:StrikeInput.atkMult`
(`damage.ts:52`), which `resolveStrike` multiplies in once (`damage.ts:141-143`). Every kind
below can fold into that same scalar **at the `strike()` call site**, before `resolveStrike` is
invoked — no change to `damage.ts`'s interface.

| kind | `battle.ts` | condition available at `engine.ts:strike()`? | verdict |
|---|---|---|---|
| `dmgMult` | `battle.ts:1381` (`dmg *= attacker.innate.dmgMult * attacker.atkMod`) | unconditional | **Portable.** Fold into `atkMult`. |
| `firstHitMult` | Turn engine's `hasLandedHit` flag (self, "first landed hit of the fight") — NOT the same as move-authored `firstStrikeMult`, which keys off the TARGET's `actedThisRound`/`hasAttacked` | Field's `FieldUnit.hasAttacked` (`types.ts:536-540`) is the exact analogue, but on the ATTACKER's own flag, checked BEFORE this strike | **Portable.** `!u.hasAttacked` at the call site, fold into `atkMult`. |
| `lowHpDmgMult` / `highHpDmgMult` | `battle.ts:1383-1384`, gated on attacker's own HP fraction vs 30%/70% | `u.hp / u.maxHp` is available at the call site | **Portable.** Fold into `atkMult`. |
| `magicDmgMult` | `battle.ts:1425`, gated on `move.channel === 'magic'` | `mv.channel` is available | **Portable.** Fold into `atkMult`. |
| `executeMult` | `battle.ts:1401-1402`, gated on TARGET hp fraction < 0.3 (hardcoded, distinct from move-authored `fx.execute`, which is separately contracted) | `target.hp / target.maxHp` is available | **Portable.** Fold into `atkMult`. |

⚠️ **Nuance for the contract.** `combatFixtures.ts` already has a generic `mods` axis
(`combatFixtures.ts:184-189`, e.g. "attack buff", "every multiplier at once") that proves
`resolveStrike` handles an arbitrary `atkMult` correctly. Folding five innate kinds into that
SAME scalar needs **no new `combat.json` cases** — the arithmetic is already proven. What is
NOT contracted, and cannot be by `combat.json`'s design, is whether `engine.ts` computes the
scalar correctly upstream — but that is already true of every existing `modAtk` contributor
today (cast buffs), so this is not a new category of gap, just a wider one.

### Group E — combat-math axes read directly by the formula

| kind | `battle.ts` | `tamerengine` placement | verdict |
|---|---|---|---|
| `crit` | `battle.ts:1391` (`critChance(stats) + attacker.innate.crit`) | `damage.ts:CRIT_CHANCE = 0.08` (`damage.ts:41`) is a **module constant**, not a `StrikeInput` field — `resolveStrike` reads it directly (`damage.ts:133`). No resolved-input slot exists. | **Needs new engine surface + contract change.** Add `StrikeInput.critChanceBonus?: number`, used as `rolls.crit < CRIT_CHANCE + critChanceBonus`. **Contract: `combat.json`** (new axis). |
| `pierce` | `battle.ts:1434` (`(e?.pierce ?? 0) + attacker.innate.pierce + mitigationPierce(stats)`) | `damage.ts:161` reads `fx?.pierce ?? 0` **directly off the move**, not off any `StrikeInput` scalar. No slot for a per-unit bonus. | **Needs new engine surface + contract change.** Add `StrikeInput.pierceBonus?: number`, combined as `Math.min(1, (fx?.pierce ?? 0) + pierceBonus)`. **Contract: `combat.json`** (new axis). |

### Group F — on-cast mechanic

| kind | `battle.ts` | `tamerengine` placement | verdict |
|---|---|---|---|
| `echo` | `battle.ts:1651-1654` — after a skill resolves, rolls `echoChance(stats) + attacker.innate.echo`; on success, calls `resolveMove(...)` a second time with an extra trailing argument at that call site | **No place at all.** `resolveHit()` (`engine.ts:1642`) is invoked from exactly two sites — a channelled cast completing (`engine.ts:1070`) and an instant cast (`engine.ts:1145`) — and nothing re-invokes it. Mana and cooldown are spent BEFORE `resolveHit` runs (near `engine.ts:1135`), not inside it, which is promising (a second `resolveHit` call would plausibly be "free" the way the turn engine's echo is), but the change touches CONTROL FLOW at two call sites, needs an infinite-recursion guard (an echo must never itself echo — confirmed as the turn engine's intent by the trailing argument at `battle.ts:1653`, though I have not read `resolveMove`'s signature to confirm the guard mechanism itself), and consumes an extra `rng()` draw at a point in the sequence that does not exist today, which is order-sensitive for determinism. | **CANNOT EXPRESS without new engine surface, and it's the largest single item.** Recommend deferring to its own stage rather than folding it in with the rest. |

### Group G — on-hit procs (self, post-hit)

| kind | `battle.ts` | `tamerengine` placement | verdict |
|---|---|---|---|
| `lifesteal` | `battle.ts:1455` (`attacker.innate.lifesteal + (e?.lifesteal ?? 0)`) | `engine.ts:strike()` **already implements move-authored lifesteal** post-hit (`engine.ts:1734-1746`, reading `fx?.lifesteal ?? 0`). Adding the innate contribution is `(fx?.lifesteal ?? 0) + u.innate.lifesteal` at that existing site. | **Portable, minimal.** One-line change at an existing hook. `damage.ts`'s own header (`damage.ts:23-25`) explicitly excludes lifesteal from the pure contract ("stays in the engine where the loop can see them"), so this needs no new contract case, consistent with existing design. |
| `manaSteal` | `battle.ts:1462-1463` | **No existing hook.** `engine.ts`'s on-hit mana gain is role-based and flat (`MANA_ON_HIT_DEALT`/`MANA_ON_HIT_TAKEN`, `engine.ts:1758-1763`) — not proportional to damage, and does not drain the target. | **Needs new engine surface, small.** A new block in `strike()` mirroring the lifesteal block: drain from `target.mp` into `u.mp`. Uncontracted, same rationale as lifesteal. |
| `statusOnHit` | `battle.ts:1510` | No hook for an innate-sourced status independent of the move's own `mv.status` rider. `engine.ts:strike()` already rolls `mv.status` (`engine.ts:1774-1777`) via `applyFieldStatus()` (`engine.ts:1608`, itself calling the already-portable `statusMath.ts:applyStatus`). | **Needs new engine surface, small.** An additional independent roll + `applyFieldStatus` call in `strike()`. No new `status.json` axis needed — `applyStatus` is already generically contracted; this is just an extra caller. |

### Group H — one-time setup (self)

| kind | `battle.ts` | `tamerengine` placement | verdict |
|---|---|---|---|
| `startWard` | `battle.ts:459` (`ward: self.startWard`, in `makeCombatant`) | `FieldUnit.ward` (`types.ts:522-524`) already exists, initialised to `0` in `buildUnit`. | **Portable, trivial.** Set to `innate.startWard` at construction. No interface change. |

### Group I — buff/debuff duration modifiers (self, on-cast)

| kind | `battle.ts` | `tamerengine` placement | verdict |
|---|---|---|---|
| `buffExtend` | `battle.ts:1158` (caster's own buff cast, rolled once, `+1` round on success) | `resolveUtility()` computes `until = t2 + (fx?.duration ?? 3) * SECONDS_PER_ROUND` ONCE (`engine.ts:1503`) and reuses it for every `mods.push` in that cast (`engine.ts:1504-1534`). | **Needs new engine surface, small, contained to one function.** New `rng()` draw + condition on caster's `innate.buffExtend`, applied to `until` before the friendly-buff block. Uncontracted (mods sequencing is engine-owned, same category as lifesteal). |
| `debuffExtend` | `battle.ts:1123-1124` (attacker's innate, applied to a debuff landed ON an enemy) | Same `until` computed once, reused in the hostile (`!friendly`) branch (`engine.ts:1565-1596`) | **Needs new engine surface, small,** same function, gated on attacker's `innate.debuffExtend` instead of the caster's own buff. |

### Group J — incoming-debuff mitigation (self, defender)

| kind | `battle.ts` | `tamerengine` placement | verdict |
|---|---|---|---|
| `debuffResist` | `battle.ts:1127` (`dr = 1 - debuffReduction(stats) - target.innate.debuffResist/100`, scales `atkDebuff`/`defDebuff`/`accDebuff` MAGNITUDE before the mod is created) | The equivalent creation sites are `engine.ts:1573` (`atkDebuff`), `1578` (`defDebuff`/`mitDebuff`), `1579` (`accDebuff`), all in the hostile branch of `resolveUtility()` | **Needs new engine surface, small, contained to one function.** Scale the magnitude by `(1 - target.innate.debuffResist/100)` before the existing `Math.max(0.4, …)` floor. ⚠️ Note: the turn engine ALSO folds in a CHA-derived `debuffReduction(stats)` term that has no field-engine equivalent at all (one of the "seven per-stat perks" already flagged absent in `docs/TECHNICAL_ISSUES.md` §2) — out of scope here; only the innate term is being wired. |

### Group K/L — team-wide auras and enemy-facing debuff auras

⚠️ **DESIGN DECIDED (2026-08-04, `systems-designer`). NOT YET BUILT — do not read this as "done."**
The radius/cadence/stacking questions below are resolved. What blocks actual code is bigger than
this group: `grep -i innate src/tamerengine/engine.ts` and `types.ts` return **zero matches** —
Groups A/C/D/H/B (§5 stages 4 and 7) aren't wired at all yet, only stage 1 (data relocation to
`src/innates.ts`) has landed. Two of these nine fields (`auraRegen`, `auraHpRegen`) are additionally
hard-blocked on Group B's `TickInput.innateRegen`/`innateHpRegen` surface, which also doesn't exist.
Building K/L standalone now would mean a disconnected shim duplicating the self-only lookup Groups
A–J will need anyway — the `reachOf` second-copy mistake, at this scale. **Decision: implement K/L
as part of the full stage 2–10 batch, in the doc's existing §5 order, not as a 9-field add-on.**

| kind | `battle.ts` | `tamerengine` placement | verdict |
|---|---|---|---|
| 5 aura fields + 4 enemy-debuff fields | `recomputeInnateAuras()` (`battle.ts:533-555`): sums over the WHOLE living team / WHOLE living enemy side, unconditionally, recomputed once per round | **No equivalent, and porting `recomputeInnateAuras` verbatim would be wrong on purpose.** The field engine has an explicit, already-fixed design principle against this exact shape: `types.ts:803-823` (`TEAM_AURA_RADIUS`) documents that cast team buffs/wards/heals used to be position-blind (`units.filter(x => x.side === u.side)`, no range check) and that this was a real bug — *"Support was the only role in the game that was completely position-blind"* — fixed by range-limiting to 9 units. A GLOBAL passive aura would reintroduce that exact bug for the passive case. | **Design decided, implementation pending — see below.** |

**The decision, for a future implementation pass to build against without re-deriving it:**

1. **Range-limited: yes**, for consistency with the cast-buff fix this group would otherwise
   reintroduce the bug from.
2. **Radius: new `INNATE_AURA_RADIUS` constant in `types.ts`, set equal to the existing
   `TEAM_AURA_RADIUS` (9).** Not an alias — a separate constant, so passive and cast auras can
   diverge later if simming calls for it — but starting at the same value because `TEAM_AURA_RADIUS`
   is already the measurement-backed answer (45,842 sampled ally-pairs, `types.ts:813-821`) to the
   identical question for the identical shape of effect. Governs **both** Group K (ally filter) and
   Group L (enemy filter) — symmetric by default, no data justifying a shorter/longer debuff-aura
   reach. (`ARENA_BLUEPRINT.md` §5's `1.1 × TIGHT_leash_radius(N)` formula is the right shape for
   the *future* SPREAD rework but isn't computable today — no tight/loose axis exists in the current
   engine, only a flat `LEASH_RADIUS`. When that rework lands, `INNATE_AURA_RADIUS` and
   `TEAM_AURA_RADIUS` get re-derived together, not independently.)
3. **Cadence: live/on-demand, no cached recompute, no new cadence constant.** Evaluated fresh at
   the same call sites self-only innates fold into (`modAtk`/`modDodge`/`modAcc`/`modGuard` in
   `engine.ts:strike()`, and the future `innateRegen`/`innateHpRegen` reads in `tickMath.ts`). Cheap
   at 5v5 scale (≤4 allies/≤5 enemies per read), avoids new per-unit cache state to keep in sync, and
   removes the legacy engine's own "dies at the START of the next round" artefact — which
   `recomputeInnateAuras`'s once-per-round cadence produces but which is a round-structure
   side-effect, not a design goal, on a field engine with no rounds anywhere else.
4. **Stacking: preserves `recomputeInnateAuras`'s exact per-field operator** (`battle.ts:342-354`).
   For a reading unit, additive K fields (`auraFlatDR`/`auraDodge`/`auraRegen`/`auraHpRegen`) SUM
   across every living ally in range including the unit itself; `auraDmgMult` MULTIPLIES across the
   same set. Additive L fields (`enemyAccDebuff`/`enemyDodgeDebuff`/`enemyRegenDebuff`) SUM across
   every living enemy in range; `enemyDmgMult` compounds per source as `Π(1 − enemyDmgDebuff)`, and
   **shares the existing `Math.max(0.4, …)` floor** the hostile-debuff-magnitude code already uses
   elsewhere in `resolveUtility()`, rather than inventing a second unbounded-compounding mechanism
   for this one case. Owner-inclusion (K) and ally-exclusion (L) fall out of the range construction
   itself (`[R, ...alliesOf(R)]` vs `enemiesOf(R)`) — no special-casing needed.

### Group M — name-keyed special case

| kind | `battle.ts` | `tamerengine` placement | verdict |
|---|---|---|---|
| Truth's Word cleanse | `truthsWordCleanse()` (`battle.ts:408-426`), gated `round % 3 !== 0`, strips one random debuff mod every 3rd round | No round concept on a continuous field — needs a wall-clock translation of "every 3rd round" (e.g. `t % (3 * SECONDS_PER_ROUND) < DT`), then a scan-and-strip of one mod from `u.mods` | **Portable with a small translation decision.** Contained, new engine code (a periodic per-tick check), no pure-module change. |

---

## 3. Happiness

`battle.ts` models happiness as a **per-Combatant number, supplied at the call site**, not as a
`Monster` field:

- `Combatant.happiness: number` (`battle.ts:365`), set in `makeCombatant(m, happiness, side, slot)` (`battle.ts:439`, `469`).
- `simulateTeamBattle(teamA, teamB, happA = [], happB = [])` (`battle.ts:1688`) builds combatants via `happA[i] ?? 0` / `happB[i] ?? 0` (`battle.ts:1691-1692`) — happiness is a PARALLEL ARRAY the caller must remember to pass, defaulting to 0 (neutral-to-slightly-unhappy) when omitted.
- `happinessMultiplier(happiness) = 1 + 0.01 * happiness` (`core.ts:881`) is applied multiplicatively in the real per-hit damage function (`battle.ts:1379`) and duplicated in the AI's `estimateDamage` heuristic (`battle.ts:811`).
- Every real call site threads it through: `town.ts:1405, 2466, 2595, 2664`, `App.tsx:402, 1748, 1752, 1827, 2113` — rivals/opponents are typically passed a flat `5` (`opp.map(() => 5)`), i.e. mildly content by convention, not neutral-0.

**Where would it attach on `tamerengine`?** `FieldSetup` (`types.ts:929-937`) has **no happiness
channel at all** — `teamA`/`teamB: Monster[]`, `placeA`/`placeB`, `obstacles`. Nothing parallel
to `happA`/`happB`. Two real designs, and this is an open fork, not a decided point:

- **(A) Mirror `battle.ts` exactly** — add `happA?/happB?: number[]` to `FieldSetup`, threaded into `buildUnit(m, side, slot, pos)` (`engine.ts:179`), which would need a new parameter. Consistent with the existing turn-engine convention, but touches every `FieldSetup` construction site (`tools/sweep40.ts`, `tools/ab.ts`, `town.ts`, `App.tsx`, `tools/regold.ts`, `goldenFixtures.ts`, …) — all would need to remember to pass it or silently get neutral.
- **(B) Put `happiness?: number` directly on `Monster`** — matching how `hp`/`mp`/`stamina`/(soon-removed) `tameness` already work as "optional, resolved at fight time" fields (`core.ts:411-414`). `buildUnit` reads `m.happiness ?? DEFAULT`. Far less invasive (an optional field with a safe default vs. a new positional array every caller must remember), and it is what makes "happiness may be reworked into a richer scale" (`docs/DECISIONS_2026-08-03.md` #1) cheap later — a scale change touches one field definition, not every battle call site. The cost: it diverges from how `battle.ts` itself models the SAME concept (array, not field), so the two engines represent happiness two different ways unless `battle.ts` is later refactored to match.

**Recommend (B)**, but flagging it explicitly for confirmation rather than assuming it, per the
brief's "design for that, do not hard-code assumptions."

Once attached, `happinessMultiplier` is **portable by the exact same mechanism as Group C/D
above** — fold into `atkMult` at the `engine.ts:strike()` call site, no `damage.ts` interface
change, no new `combat.json` case (reuses the proven generic `mods` axis).

AI-heuristic parity (`battle.ts:811`'s `estimateDamage`) has two analogues on the field —
`effPowerField()` (`engine.ts:327-357`) and `engine.ts:246-252`'s kill-check `estimateDamage` —
**neither currently reads any per-unit multiplier at all** (they score by raw move power/stat,
not actual output). Folding happiness or `dmgMult` into these is a nice-to-have consistency
pass, not required for the mechanic to be live. Flagging as optional/secondary.

---

## 4. `tameness` removal — full file/line inventory

| file | lines | what |
|---|---|---|
| `core.ts` | `414` | `Monster.tameness?: number` field + its comment |
| `monster.ts` | `68-79` | Comment block explaining the mechanic. ⚠️ **This comment is already stale** — it claims `careerMonster()` "simply never sets the field" (`monster.ts:77-79`), but `game.ts:509` (below) DOES set it. Worth noting so the removal commit message doesn't repeat the stale claim. |
| `monster.ts` | `80-81` | `TAMENESS_LEAGUE_BASE` / `TAMENESS_LEAGUE_STEP` constants |
| `monster.ts` | `82-88` | `rollTameness(maxStat, rng)` function |
| `monster.ts` | `609` | `tameness: rollTameness(maxStat, rng),` in `generateMonster()` |
| `game.ts` | `505-509` | Comment + `tameness: 90 + c.happiness,` in `careerMonster()` — the ONE canonical builder for a player's real Monster (used by `town.ts` cups etc.). **This is the site the stale `monster.ts` comment missed** — player monsters DO get a tameness value, derived from happiness. |
| `battle.ts` | `1099-1104` | `wildAction(self, rng)` function definition |
| `battle.ts` | `1630-1641` | The wild-instinct branch in `takeTurn()`: comment, `const tameness = attacker.m.tameness`, and the ternary choosing `wildAction` vs `chooseAction` |
| `src/tamerengine/goldens.json` | 10 occurrences | Purely structural — full serialized `Monster` objects embedded in the port-contract fixtures (`goldenFixtures.ts` → `buildGoldenContract()`). The field engine never reads `tameness` (confirmed §1: zero references), so removing the field changes the JSON SHAPE only, not any fight outcome. Regenerate via `npx tsx tools/exportgoldens.ts`; no manual number changes needed for this file specifically. |
| `battle.test.ts` | `GOLDENS` array (4 fixtures) | **Not a `tameness` reference itself, but a consequence.** `generateMonster()`-built teams currently consume an extra `chance(rng, 100 - tameness)` roll every turn (`battle.ts:1639`) before falling through to `chooseAction`/`wildAction`. Removing that branch removes an rng draw from the PER-TURN sequence for every generated/rival monster, which will shift every subsequent roll for the rest of each fight. **These four goldens WILL move** and must be recaptured (`npx tsx tools/regold.ts`) in the same commit, with the cause named. Player-raised monsters via `careerMonster()` are unaffected in relative terms — they already had a defined `tameness` (90+happiness, not undefined) so they ALSO currently roll the wild-instinct check; removing it changes their battle rng too, but there is no golden fixture that exercises `careerMonster()` directly (goldens use `generateMonster()`), so this is observationally the same fix from one path. |
| `src/tamerengine/*` | — | **Nothing to change.** Zero references confirmed. |

One thing to verify in Stage 2, not asserted here: whether `generateMonster()`'s stat/loadout
output is unaffected by dropping the `rollTameness` call. Reasoning suggests yes — the tameness
roll is the LAST draw in `generateMonster()` (`monster.ts:609`, after stats/loadout/food are
already computed) and its result feeds nothing else in that function — but this should be
spot-checked with a determinism test before relying on it.

---

## 5. Proposed order of implementation

Cheapest and safest first; each stage should land and verify (`npx tsc --noEmit`, `npm test`)
before the next starts.

1. **Data-table relocation + contract.** Move `InnateEffect`/`INNATE_EFFECTS` out of `battle.ts`
   into a shared module (mirroring the `moves.ts`/`lines.ts` pattern — both engines import from
   it, no engine depends on the other). Update `validate.ts:17` (`import { INNATE_EFFECTS } from
   './battle'`) to the new location — its name-key guard (`validate.ts:255-268`) must keep
   working unchanged. Add `innateEffects: INNATE_EFFECTS` to `dataExport.ts`'s
   `buildDataExport()` (currently exports `species` — which carries the NAMES via
   `Species.innate: Ability[]` — but never the numeric effect table itself). **Pure refactor,
   zero behaviour change, zero goldens move.** Highest value-per-hour: this alone closes the gap
   flagged in `docs/OUTSTANDING.md` §2.5/§10 (a port could read species innate NAMES today and
   still have no idea what they numerically do).
2. **`tameness` removal.** Per §4. Turn-engine goldens move; recapture deliberately, in the same
   commit, with the cause named.
3. **Happiness attachment decision, then wiring.** Resolve the (A)/(B) fork in §3 first — it is
   a real fork, not a detail. Then: fold `happinessMultiplier` into `atkMult` at
   `engine.ts:strike()` (Group C/D mechanism, zero `damage.ts` interface change).
4. **Group A/C/D/H self-only innates that fold into existing generic scalars.** `flatDR`,
   `dodge`, `acc`, `dmgMult`, `firstHitMult`, `lowHpDmgMult`, `highHpDmgMult`, `magicDmgMult`,
   `executeMult`, `startWard` — all portable with zero contract changes, all at the
   `engine.ts:strike()`/`buildUnit()` call sites. The largest single batch, and the safest.
5. **Group G on-hit procs.** `lifesteal` (existing hook, trivial), then `manaSteal` and
   `statusOnHit` (small new code, same function, no new contract).
6. **Group E: `crit`/`pierce`.** Requires the two `combat.json`-contracted `StrikeInput`
   additions (`critChanceBonus`, `pierceBonus`). Do this once 1-5 are proven, since it is the
   first stage that touches the pure `damage.ts` contract file.
7. **Group B: `regen`/`hpRegen`.** Requires the two `tick.json`-contracted `TickInput` additions
   (`innateRegen`, `innateHpRegen`).
8. **Group I/J: `buffExtend`/`debuffExtend`/`debuffResist`.** Contained to `resolveUtility()`,
   uncontracted, but touches debuff/buff creation logic that is easy to get subtly wrong (the
   `Math.max(0.4, …)` floor interacts with resist scaling) — worth its own stage with fixtures.
9. **Group M: Truth's Word.** Small, isolated, no dependency on anything else — could move
   earlier in the order if convenient, sequenced here only because it's genuinely optional
   relative to the rest.
10. **Group K/L: auras and enemy-debuffs.** ⚠️ Design decided (radius/cadence/stacking, §2's
    Group K/L row) — no longer blocked on a design call. Still sequenced last of the portable
    groups: blocked in practice on stages 4 and 7 landing first (Groups A/C/D/H, B), since two of
    its nine fields need Group B's `TickInput` surface and the rest need the self-only
    active-innate lookup those stages build. Do this after everything self-only is proven, since
    it is the largest remaining chunk of species identity (CHA-major/Marsupial support kits lean
    on it heavily) and the one most likely to need a second pass once simmed.
11. **Group F: `echo`.** Deferred to its own stage, deliberately last — the biggest control-flow
    change, the least contained, and (per `CLAUDE.md`'s balance-suspended standing rule) not
    urgent to rush given the baseline is already suspended.

**This is bigger than one pass.** Stages 1-5 are a reasonable single implementation stage (data
relocation + tameness removal + happiness + the big portable batch + on-hit procs) — all
zero-or-near-zero contract risk. Stages 6-11 each have a real design or contract decision
attached and should be separate stages with their own review point.

---

## 6. Contract summary — what needs a new axis, in which file

| mechanism | contract file | new? |
|---|---|---|
| `INNATE_EFFECTS` table itself (name → numeric effect) | `dataExport.ts` → `data.json` | **YES, and currently missing entirely.** Species names are exported (`dataExport.ts:27`, `species: SPECIES`) but the effect table is not. |
| `crit` → `StrikeInput.critChanceBonus` | `combat.json` (`combatFixtures.ts`) | **YES**, new axis. |
| `pierce` → `StrikeInput.pierceBonus` | `combat.json` | **YES**, new axis. |
| `regen`/`hpRegen` → `TickInput.innateRegen`/`innateHpRegen` | `tick.json` (`tickFixtures.ts`) | **YES**, new axis. |
| Everything folded into existing `atkMult`/`accMod`/`dodgeMod`/`defGuard` (Groups A, C, D, H) | `combat.json` | **NO** — reuses the already-proven generic `mods` axis. |
| `lifesteal`, `manaSteal`, `statusOnHit`, `buffExtend`, `debuffExtend`, `debuffResist`, Truth's Word | none of the five arithmetic contracts | **NO** — all are engine-owned sequencing (same category `damage.ts`'s own header already excludes lifesteal/thorns/mana-on-hit/status-rider/contagion from the pure contract, `damage.ts:23-25`). Not itself a gap; consistent with existing design. |
| Team auras / enemy-debuff auras (Group K/L) | — | **Design decided, no new contract file.** Live/on-demand distance filtering stays engine-owned like the rest of Group I/J. `INNATE_AURA_RADIUS` is the new documented constant, sitting alongside `TEAM_AURA_RADIUS` (`types.ts:823`) per the decision in §2. |
| `echo` | possibly none, possibly needs its own axis once designed | **Deferred** — cannot assess until the control-flow design exists. |
| Happiness attachment point (Monster field vs `FieldSetup` array) | `derive.json`? | **Not itself a contract question** — it's a call-site/API shape decision (§3), not arithmetic. Once resolved, `happinessMultiplier`'s fold into `atkMult` needs no new contract, same as Group C/D. |

⚠️ **The single highest-value item in this whole document is the `data.json` gap.** A Godot port
today can read every species' innate NAME (`data.json` → `species[].innate`) and has genuinely
no way to know what any of them numerically do — not because the port is incomplete, but because
the export was. That is exactly the "port omits it and still passes 173/173" failure shape the
brief warns about, and it costs almost nothing to close (§5, stage 1).

---

## Summary for the coordinator

31 distinct effect kinds (30 `InnateEffect` fields + Truth's Word). Roughly **11 are portable
today with zero interface changes** (fold into existing generic `atkMult`/`accMod`/`dodgeMod`/
`defGuard`/`ward` scalars at the `engine.ts:strike()`/`buildUnit()` call sites), **6 need small,
uncontracted new engine code** (on-hit procs, buff/debuff duration, Truth's Word), **4 need small
contract additions** (`crit`/`pierce` in `combat.json`, `regen`/`hpRegen` in `tick.json`), and
**9 fields (the aura/enemy-debuff family) are now DESIGN-DECIDED but not built** (2026-08-04,
`systems-designer`): range-limited to a new `INNATE_AURA_RADIUS` constant (= `TEAM_AURA_RADIUS`,
symmetric for K and L), evaluated live/on-demand with no cadence constant, stacking exactly as
`recomputeInnateAuras` does today (sum/multiply per field, `enemyDmgMult` sharing the existing
0.4 debuff floor). Full detail in §2's Group K/L section. What actually blocks the code is
**not** this group anymore — it's that Groups A/C/D/H/B aren't wired into `engine.ts` at all yet
(confirmed by grep, zero matches for "innate" in `engine.ts`/`types.ts`), so K/L is sequenced to
land as part of the same stage 2-10 batch rather than standalone. `echo` (1 kind) is
the only one I'd call a real control-flow project rather than a wiring job — it needs a second
`resolveHit` call site with a recursion guard and a new rng draw in the sequence, which is
determinism-sensitive. Biggest single finding: `INNATE_EFFECTS` isn't just unwired on the field
engine, it isn't even in the DATA export (`dataExport.ts`) that Godot reads — species innate
NAMES travel today, their numeric effects do not, at all. That's the cheapest and highest-value
fix in the whole document. `tameness` removal touches 4 source files plus `battle.test.ts`'s
goldens (which will move and need deliberate recapture) — `tamerengine` itself needs zero
changes for the removal, confirmed zero references. Recommend splitting implementation into the
11-stage order in §5, with stages 1-5 (data relocation, tameness removal, happiness, the big
portable batch, on-hit procs) as one reviewable unit and stages 6-11 as separate follow-ups.
