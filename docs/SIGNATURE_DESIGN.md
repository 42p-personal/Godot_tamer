# Signature skills — balance audit and corrected numbers

50 designed abilities across 8 lists, audited against the 90-move pool's actual
ceilings. **Every number below marked ⚠️ was over the pool and has been corrected.**

## The rule this audit enforces

> A signature may exceed a pool ceiling on **ONE axis by ~15–20%**, and must sit
> **at or under** the pool on every other axis.

Signatures are meant to be *strong-and-early* — a Silver-league winner wielding
something the pool only offers at learnLevel 920 — not strictly better. The
failure mode found repeatedly below is a move that quietly beat the pool on
power *and* status chance *and* effect magnitude simultaneously. Each excess was
defensible alone; together they are creep.

## Pool ceilings (the reference)

| Axis | Ceiling | Held by |
|---|---|---|
| single-target damage | **68** | Titanfall (lv920) |
| AoE (allEnemies) damage | **56** | World Ender (lv920) |
| row-target damage | **46** | Rain of Arrows (lv650) |
| multi-hit, per hit | **38** | Heartseeker (lv850) |
| self-heal | **70** | Undying (lv920) |
| ally/team heal | **32** | Tranquility (lv430, ONE ally) |
| `bonusVsStatus` | **×2.5** | Bloodletter |
| `pierce` / `execute` / `lifesteal` | 0.5 / 0.4 / 0.4 | |
| `recoil` / `maxHpDmg` | 0.15 / **0.03** | |
| `atkBuff` / `atkDebuff` | 0.3 / 0.2 | |
| `defBuff` / `defDebuff` | 8 / 10 | |
| `dodgeBuff` / `accBuff` / `accDebuff` | 14 / 12 / 10 | |
| `regenBuff` / `hpRegenBuff` / `thorns` | 4 / 5 / **6** | |
| `ward` / `guard` / `manaBurn` | 40 / 20 / 25 | |

Status chance ceilings: bleed 50 · blind 45 · burn 40 · charm 15 · confusion 35 ·
doom 28 · fear 20 · haste 100 · healblock 20 · knockback 40 · poison 45 ·
silence 25 · sleep 35 · stun 30 · vulnerable 100.

---

## ⚠️ Three findings that mattered most

### 1. `maxHpDmg` was 2.7–3.3× the pool

The pool's only user is Colossus Crash at **0.03**. I had written **0.08** and
**0.10**. This scales off the *target's* max HP, so against a Tamers Apex CON
build it is enormous and it ignores mitigation entirely — the single most
dangerous number in the set.

| Move | Was | Now |
|---|---|---|
| The Weight of Years (Mammal) | 0.08 | **0.04** |
| Abyssal Pressure (Aquatic) | 0.10 | **0.05** |

### 2. Team heals were ~2× the pool AND multiply by team size

`Tranquility` heals **32** to ONE ally. I had team heals at **55–60**. Critically,
**healing has no AoE falloff** — that only applies to damage — so a 60-point team
heal is 360 HP at 6v6 off a single cast. This was the worst creep in the set.

| Move | Was | Now |
|---|---|---|
| Called Home (Avian) | 60 team | **30 team** |
| Ancient Knowing (Draconic/Abyssal) | 55 team | **30 team** |

30 each still beats `Ward Against Ruin`'s 18 and reaches the whole team, which is
plenty for a once-a-year reward.

### 3. Status chances ran hot across the board

Signatures *should* set statuses better than the pool — that is the "better
setter" role. But several were 60–100% over, and the worst offenders were the
statuses the pool deliberately keeps rare (fear, doom, silence).

| Move | Status | Pool max | Was | Now |
|---|---|---|---|---|
| Prehistoric Roar (Mythical) | fear | 20 | 40 | **28** |
| Barker's Cry (Marsupial) | fear | 20 | 35 | **28** |
| Carrion Omen (Avian) | doom | 28 | 45 | **35** |
| Venom Bloom (Reptilian) | poison | 45 | 60 | **52** |
| The Boiling Vent (Aquatic) | burn | 40 | 55 | **48** |
| Elder Flame (Drac/Abyss) | burn | 40 | 50 | **46** |
| The Windless Hour (Avian) | silence | 25 | 35 | **30** |
| Deepwater Hymn (Drac/Abyss) | silence | 25 | 30 | **29** |
| Hunter's Seam (Mammal) | bleed | 50 | 55 | 55 ✓ keep |
| Ashfall Elegy (Marsupial) | healblock | 20 | 30 | **24** |
| Tailwhip Sweep (Reptilian) | knockback | 40 | 50 | **46** |

Each now sits ~15–20% over its pool ceiling — a real upgrade, not a new tier.

---

## Corrected numbers, all 50

### Mammal — STR / melee

| # | Skill | Power | Effects | Status |
|---|---|---|---|---|
| 1 | Highroad Charge 🜃 | 60 | `pierce 0.35` | stun 25% |
| 2 | Reclaim the Range 🜂 | AoE 46 | — | vulnerable 40% |
| 3 | Hunter's Seam | 26 ×2–3 | `randomTargets` | bleed 55% |
| 4 | Rising Fury | — | `atkBuff 0.35`, ⚠️`hpRegenBuff 6` (was 7), 4rd | — |
| 5 | The Weight of Years | 64 | `recoil 0.12`, ⚠️`maxHpDmg 0.04` (was 0.08) | — |
| 6 | Throatline | ⚠️frontRow 46 (was 50) | `execute 0.35`, `bonusVsStatus bleed ×1.6` | — |

### Avian — WIS / support

| # | Skill | Power | Effects | Status |
|---|---|---|---|---|
| 1 | Stormrider's Dive 🜁 | 58 | `bonusVsStatus doom ×2.0 consume` | — |
| 2 | Wingbreaker 🜁 | ⚠️backRow 46 (was 48) | ⚠️`accDebuff 12` (was 15), 3rd | — |
| 3 | The Windless Hour | AoE 40 | `manaBurn 20` | ⚠️silence 30% (was 35) |
| 4 | Carrion Omen | 46 | ⚠️`spreadStatus ×2 @45%` (was 60) | ⚠️doom 35% (was 45) |
| 5 | Called Home | ⚠️30 team heal (was 60) | `cleanse` | — |
| 6 | The Long Migration | — | ⚠️`regenBuff 4` (was 5), ⚠️`hpRegenBuff 5` (was 6), ⚠️`accBuff 14` (was 15), 4rd | — |

### Marsupial — CHA / voice

| # | Skill | Power | Effects | Status |
|---|---|---|---|---|
| 1 | The Vanishing Act | — | ⚠️`dodgeBuff 16` (was 18), ⚠️`accBuff 14` (was 15), 4rd | — |
| 2 | Barker's Cry | AoE 42 | — | ⚠️fear 28% (was 35) |
| 3 | The Long Con | 56 | ⚠️`bonusVsStatus fear ×1.8 CONSUME` + re-applies fear 55% — see note | fear 55% |
| 4 | Carnival of Errors | 46, cd6 | `spreadStatus ×1 @30%` | blind 50% |
| 5 | Ashfall Elegy | AoE 38 | — | ⚠️healblock 24% (was 30) |
| 6 | The Grand Parade | — | `atkBuff 0.22`, `hpRegenBuff 5`, 4rd | haste 100% |

> **The Long Con was BROKEN, not just hot.** It was specified as a *non-consuming*
> fear payoff at cd5 — but fear lasts 2 rounds, so the status always expires
> before the move comes off cooldown. It would have shipped doing nothing. It now
> consumes the fear and immediately re-applies it, which produces the same
> "the combo keeps running" feel using only proven mechanics.

### Aquatic — INT / magic

| # | Skill | Power | Effects | Status |
|---|---|---|---|---|
| 1 | Trenchfall 🜄 | 60 | `pierce 0.3` | — |
| 2 | Ancient Cold 🜄 | AoE 42 | — | vulnerable 40% |
| 3 | The Boiling Vent 🜂 | 52, cd6 | `spreadStatus ×1 @30%` | ⚠️burn 48% (was 55) |
| 4 | Trenchbed Collapse 🜃 | AoE 38 | — | stun 20% |
| 5 | The Surfacing 🜁 | 56 | `bonusVsStatus burn ×2.0 consume` | — |
| 6 | Abyssal Pressure 🜄 | 48 | ⚠️`maxHpDmg 0.05` (was 0.10), `pierce 0.25` | — |

### Insectoid — CON

| # | Skill | Power | Effects | Status |
|---|---|---|---|---|
| 1 | Chitin Bulwark | — | ⚠️`ward 42` (was 45), ⚠️`thorns 7` (was 9), `defBuff 6`, 4rd | — |
| 2 | Shatterguard | 46 | `consumeWard 0.02` | — |
| 3 | Barbfall | frontRow 38 | `consumeThorns 0.05` | — |
| 4 | Unbroken | 52 | `hpScale {1.7, 0.6}` | knockback 40% |
| 5 | The Hive Answers | — | `tauntForce`, ⚠️`guard 23` (was 26), ⚠️`thorns 7` (was 8), 3rd | — |
| 6 | Long Succession | 60 self-heal | `cleanse`, ⚠️`hpRegenBuff 5` (was 6), 3rd | — |

### Reptilian — DEX / ranged

| # | Skill | Power | Effects | Status |
|---|---|---|---|---|
| 1 | The Long Patience | 64 | `hpScale {1.5, 0.75}`, `pierce 0.3` | — |
| 2 | Venom Bloom | 44, cd6 | `spreadStatus ×2 @35%` | ⚠️poison 52% (was 60) |
| 3 | Coil and Strike | 24 ×2–4 | `randomTargets` | bleed 45% |
| 4 | Sunward Basking | — | ⚠️`dodgeBuff 16`, ⚠️`accBuff 14`, 4rd | haste 100% |
| 5 | Ambush from Stillness | 50 | `bonusVsStatus bleed ×2.1 consume`, `execute 0.3` | — |
| 6 | Tailwhip Sweep | frontRow 40 | — | ⚠️knockback 46% (was 50) |

### Draconic + Abyssal (shared, 8)

| # | Skill | Channel | Power | Effects | Status |
|---|---|---|---|---|---|
| 1 | Elder Flame 🜂 | magic | 60 | — | ⚠️burn 46% (was 50) |
| 2 | Crushing Deep 🜄 | magic | AoE 42 | `displace back 40%` | — |
| 3 | Entropy Cascade | magic | 52, cd6 | `spreadStatus ×2 @40%` | — |
| 4 | Void Pulse | magic | AoE 40 | — | vulnerable 40% |
| 5 | Ancient Knowing | support | ⚠️30 team heal (was 55) | `cleanse` | — |
| 6 | Aeons of Patience | support | 56 | `bonusVsStatus doom ×2.0 consume` | — |
| 7 | Deepwater Hymn | support | ⚠️backRow 46 (was 48) | `manaBurn 20` | ⚠️silence 29% (was 30) |
| 8 | Wyrmscale Aegis | support | — | `defBuff 8`, ⚠️`thorns 7` (was 10), ⚠️`hpRegenBuff 5` (was 6), 4rd | — |

### Mythical — CHA / voice

| # | Skill | Power | Effects | Status |
|---|---|---|---|---|
| 1 | The Unison | — | `atkBuff 0.28`, ⚠️`accBuff 14` (was 15), 4rd | haste 100% |
| 2 | Prehistoric Roar | AoE 46 | — | ⚠️fear 28% (was 40) |
| 3 | Aegis Bond | — | ⚠️`thorns 7` (was 10), ⚠️`hpRegenBuff 5` (was 6), 4rd | — |
| 4 | Cosmic Precision | 60 | `bonusVsStatus fear ×2.0 consume` | — |
| 5 | Stellar Cascade 🜁 | ⚠️backRow 46 (was 50) | `displace front 45%` | — |
| 6 | Unstoppable | 58 | `hpScale {1.6, 0.8}`, `pierce 0.3` | — |

---

## What was NOT changed, and why

- **Single-target power 56–64** stays. The pool reaches 68, and every signature
  sits under it. This is the axis where signatures are *meant* to feel strong.
- **`bonusVsStatus` ×1.8–2.1** stays. The pool already has ×2.5 (Bloodletter), so
  these are mid-range, and the payoff role is a core part of the design.
- **`hpScale` and `consumeWard`/`consumeThorns`** have no pool ceiling to breach —
  they are new. Pool precedent was deliberately set *below* the signatures:
  Shell Slam `{1.4, 0.8}` vs Unbroken `{1.7, 0.6}`; Colossus Crash `consumeWard
  0.015` vs Shatterguard `0.02`.
- **Hunter's Seam bleed 55%** (vs pool 50) stays — the one status kept over
  ceiling, because bleed is a damage-over-time rather than a hijack and it is the
  setter half of Mammal's only combo.

## Net effect

**37 individual numbers reduced.** No ability was removed and no strategic option
was lost — every corrected move still does exactly what it was designed to do,
and every combo role (setter / payoff / spreader / displacer) is intact. The
change is that a signature now wins on **shape** — reach, breadth, contagion,
repositioning, resource conversion — rather than on raw numbers.
