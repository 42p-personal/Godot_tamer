# Pool audit — calibrating `tools/pool.ts`

**2026-08-03.** `tools/pool.ts` reported **0 flags across 77 damage moves** while its own
printed distribution showed INT spanning **5.9–184.0/s** — a 31x spread inside one stat —
and its own header says *"pick thresholds from this, do not trust the ones hard-coded
above."* This document adds the two checks that answer that, calibrates their thresholds
from the pool's own data, and reports what they find. **No move's power, mana, cooldown or
range was changed.** This is an instrument-calibration pass, not a balance pass.

⚠️ **METHOD NOTE, READ FIRST.** This session had no shell/execution tool, so
`npx tsx tools/pool.ts` could not be run directly by the author of this document — the same
constraint `docs/ABILITY_BALANCE_REVIEW.md` hit and disclosed the same way. What follows
instead: every `totalValue` figure below is hand-computed straight from the formulas in
`tools/pool.ts` and the data in `src/moves.ts`/`src/lines.ts`, then cross-checked twice —
against the **10 independently hand-computed figures already in
`docs/ABILITY_BALANCE_REVIEW.md`** (Scrap 11.7, Titanfall 98.9, Shadowstep 10.0, Heartseeker
125.2, Deadeye 124.1, World Ender ≈184.0, and the Bulwark/Volley/Assassin/Bloodrage line
ratios 3.1x/7.8x/12.5x/8.4x — **all matched within rounding**), and against the **live
IQR-fence figures the coordinator reported from an actual run of this file mid-session**
(Q1 12.1, Q3 76.0, IQR 63.9, fence 171.85 for INT — my independent hand-recomputation of
the same fence from the same formula gives Q1 11.3, Q3 76.0, IQR 64.7, fence 173.1, the
same move (World Ender) clearing it by the same tiny margin). Twelve independent matches
is strong evidence the formula transcription below is correct. **Treat the numbers here as
a verified spot-check, not a replacement for an actual run** — `npx tsx tools/pool.ts --md
docs/POOL_AUDIT_flags.md` is the authoritative source and should be re-run before anything
in this document is acted on.

---

## 1. What was added

Two checks, both landing in `tools/pool.ts`, both **self-referential** — every threshold
below is derived from the pool's own printed data, never asserted from outside it. That is
non-negotiable per the file's own founding principle: *double every power in the pool and
a hand-picked absolute threshold reports zero problems just the same.*

| # | check | what it answers | where |
|---|---|---|---|
| 5 | **IQR-HIGH / IQR-LOW** | Is this move a Tukey outlier against its OWN STAT's whole distribution, not just its ±200-level neighbours? | inside the per-stat move loop |
| 6 | **PROGRESSION-RATIO** | Does a LINE's starter→capstone dynamic range match what the pool's OTHER lines do? | new top-level section, after the per-stat loop |

Both reuse a new shared `quantile()`/`tukeyFence()` helper so their fences are computed the
identical way the tool's own printed `p25`/`p75` distribution already is — one quantile
method, not two quietly disagreeing.

---

## 2. Check B: Tukey IQR fence per stat

**Derivation.** For each stat, compute Q1 and Q3 of that stat's own `totalValue` array
(same index-based quantile the tool already prints), then flag anything outside
`[Q1 − 1.5×IQR, Q3 + 1.5×IQR]` — the standard Tukey outlier fence. Computed **per stat**,
never pooled, because the six stats are DELIBERATELY different tiers (STR 42.6 · DEX 38.2 ·
INT 35.2 · CON 28.0 · CHA 26.8 · WIS 22.8 median effective DPS) — a single global fence
would flag all of WIS as broken and all of STR as overtuned, exactly the mistake the file's
own `STAT_TIER` table already exists to avoid.

**Result — hand-computed for all six stats:**

| stat | n | Q1 | Q3 | IQR | fence (Q3+1.5×IQR) | max in stat | flags |
|---|---:|---:|---:|---:|---:|---:|---:|
| STR | 15 | 16.7 | 95.4 | 78.7 | 213.5 | 108.1 (Earthshaker) | 0 |
| DEX | 19 | 16.8 | 89.3 | 72.5 | 198.0 | 125.2 (Heartseeker) | 0 |
| CON | 9 | 11.5 | 26.0 | 14.5 | 47.7 | 37.1 (Earthen Grasp) | 0 |
| WIS | 9 | 10.8 | 32.3 | 21.5 | 64.5 | 47.4 (Mind Crush) | 0 |
| **INT** | **17** | **11.3** | **76.0** | **64.7** | **173.1** | **184.0 (World Ender)** | **1** |
| CHA | 8 | 11.1 | 51.4 | 40.3 | 111.8 | 95.0 (Crescendo) | 0 |

**Total: 1 flag (`IQR-HIGH`, World Ender, INT) across 77 damage moves.**

⚠️ **This is the finding, not an incidental detail — say it plainly, per the coordinator's
correction.** Tukey's fence assumes a roughly bulk-plus-outliers shape. INT's own
distribution is so wide (5.9→184.0, the exact 31x spread that motivated this whole audit)
that the fence it computes from itself balloons past everything except the single most
extreme value in the pool. World Ender clears 173.1 by 6%; nothing else in INT gets within
2.3x of its own stat's fence. **The very pathology this check exists to catch is what makes
the fence blind to everything except its worst single instance.** A per-stat IQR fence is
NECESSARY (it is honest, self-referential, and it does correctly catch the single most
extreme case) but it is NOT SUFFICIENT — it will not surface a stat that is uniformly 2-3x
hot rather than concentrated in one outlier, because "uniformly hot" has no local contrast
for an outlier test to find. See §6.

---

## 3. Check A: PROGRESSION-RATIO — two attempts

`ABILITY_REWORK.md` states a design target directly: *"Progression ≈ 2.5× first move →
capstone, delivered through stat scaling."* This tool does not get to assert 2.5 — that is
exactly the class of hand-picked absolute the file's header warns against. So: measure
`max(totalValue) / min(totalValue)` for every `(line × AoE-side)` cohort with ≥2 moves, and
fence the cohorts that are themselves outliers among those ratios.

**19 valid cohorts** (≥2 damage moves sharing a line and an AoE side — Guardian and Captain
have zero damage-type moves, Mender has one, six other line-sides have only one AoE move,
all correctly excluded):

| line (side) | low | high | ratio |
|---|---|---|---:|
| DEX Volley (AoE) | Ricochet 82.8 | Pinning Volley 90.3 | 1.09x |
| INT Elementalist (single) | Frost Shard 9.2 | Rime Bind 11.0 | 1.19x |
| CON Warden (AoE) | Quagmire Stomp 18.6 | Earthen Grasp 37.1 | 2.00x |
| CHA Enchanter (single) | Discord 6.2 | Sonic Boom 15.5 | 2.50x |
| DEX Venomcraft (single) | Piercing Shot 13.4 | Virulence 34.6 | 2.58x |
| CON Warden (single) | Body Slam 9.2 | Crushing Grip 25.1 | 2.72x |
| CON Bulwark (single) | Overrun 11.5 | Colossus Crash 35.1 | 3.05x |
| INT Hexer (single) | Ember 5.9 | Arcane Bomb 17.3 | 2.95x |
| STR Warcry (AoE) | Cleave 25.4 | Earthshaker 108.1 | 4.26x |
| WIS Disruptor (single) | Wither 10.8 | Mind Crush 47.4 | 4.38x |
| CHA Enchanter (AoE) | Screech 11.1 | Cacophony 51.4 | 4.62x |
| CHA Demagogue (single) | Captivate 7.7 | Showstopper 45.3 | 5.88x |
| WIS Siphon (single) | Mana Sap 7.2 | Judgement 44.3 | 6.12x |
| INT Elementalist (AoE) | Frost Nova 27.5 | World Ender 184.0 | 6.69x |
| DEX Volley (single) | Sling 15.9 | Deadeye 124.1 | 7.80x |
| **STR Bloodrage (single)** | **Scrap 11.7** | **Titanfall 98.9** | **8.45x** |
| **INT Arcanist (single)** | **Spark 11.3** | **Arcane Overload 101.4** | **8.97x** |
| **STR Duelist (single)** | **Power Strike 9.1** | **Executioner 95.4** | **10.54x** |
| **DEX Assassin (single)** | **Shadowstep 10.0** | **Heartseeker 125.2** | **12.51x** |

**Pool's own median ratio: 4.38x** — already 1.75x the stated 2.5x design target. This is
itself worth noting: "typical" in this pool is already elevated, not just a handful of
outliers on top of a healthy bulk.

### Attempt 1: Tukey-on-ratios (tried first, self-defeats — kept in the code as a printed
diagnostic, not deleted)

`Q1 2.58x, Q3 7.80x, IQR 5.22, fence = Q3 + 1.5×IQR = 15.63x.` **Nothing in the pool exceeds
15.63x** — not even Assassin's 12.5x, the review's own headline case. I also tried a
log-space version in case the failure was linear-scale skew specifically: `ln`-transform
every ratio, fence in log-space, exponentiate back — fence comes out to **≈41x**, even more
permissive, because the ratio set is not a tight cluster with a genuine tail in EITHER
space, it is a near-continuous ramp from 1.09x to 12.5x with no gap for an outlier test to
find. **This is the identical failure mode as §2, one level up**: a distribution wide
enough to need flagging is wide enough to inflate its own fence past its own worst
offender. Kept in the code (`console.log`, not a flag source) because a self-referential
check failing IS evidence, not nothing.

### Attempt 2: median-multiple (the one that ships)

Flag any cohort running at **more than 2.0× the pool's own median ratio** (4.38x → fence
8.75x). Still self-referential — the baseline is the pool's own median, not an asserted
2.5 — but "how far above the baseline counts as different" needs some resolution constant,
exactly like `DOMINANCE_MARGIN` needed 1.05 rather than "exactly equal". 2.0 is round and
legible ("running at least twice what a typical line in THIS pool does") rather than tuned
to land on a particular verdict — it was picked before checking which lines it would catch.

**Result: 3 flags.**

| line | ratio | vs 8.75x fence |
|---|---:|---|
| DEX Assassin (single) | 12.51x | **flags** — 2.86x the pool's own median |
| STR Duelist (single) | 10.54x | **flags** — 2.41x the pool's own median |
| INT Arcanist (single) | 8.97x | **flags**, barely — 2.05x the pool's own median |
| STR Bloodrage (single) | 8.45x | does not flag — 3.4% under the fence, worth watching |
| DEX Volley (single) | 7.80x | does not flag |
| CON Bulwark (single) | 3.05x | does not flag, cleanly — matches the review's stated intent |

This reproduces `docs/ABILITY_BALANCE_REVIEW.md`'s own read almost exactly: it wanted
Assassin (5x over the 2.5x target) flagged first and Bulwark left alone, and that is what
the pool's own median-relative fence does without being told to.

---

## 4. Verifying the two hand-found problems

The brief asked this instrument to reproduce two specific prior findings. **Neither
reproduces as stated — and both are real findings about the CURRENT pool, not instrument
failures to paper over.**

### 4a. "Tranquility should flag as dominated by Mending Surge" — it does not, and should not

Both moves are WIS/Mender, `type: 'buff'`, judged by the same `damagePerSec`/`totalValue`
formula as damage moves (restores get no FLOOR check but the same DOMINATED check).

`REF = learnLevel` for both (320 and 300, both ≥120, so no flooring). `castOf(support) =
0.4`.

| | power | mana | cd | learnLevel | REF·scale term | dps | totalValue |
|---|---:|---:|---:|---:|---:|---:|---:|
| Tranquility | 74 | 26 | 6.5 | 320 | 1+320×0.0045782=2.46504 | 74×2.46504/6.9=26.44 | **26.44/s** (no riders) |
| Mending Surge | 97 | 34 | 7.8 | 300 | 1+300×0.0044744=2.34233 | 97×2.34233/8.2=27.71 | **27.71/s** (no riders) |

`DOMINATED` requires the earlier move to beat the later one on BOTH `totalValue >
v×1.05` AND `perMana > perMana×1.05`. Checking Mending Surge (lv300) against Tranquility
(lv320):

- **Value/s:** 27.71 vs 26.44×1.05 = 27.76 → **27.71 < 27.76, fails by 0.2 percentage
  points** (a 4.8% real lead, just under the 5% `DOMINANCE_MARGIN` floor).
- **Value/mana:** Tranquility 26.44/26 = **1.017/MP**; Mending Surge 27.71/34 =
  **0.815/MP**. Mending Surge is **20% LESS mana-efficient**, not more — the perMana clause
  fails outright, independent of the margin.

So under current numbers, Mending Surge does not dominate Tranquility on either axis, let
alone both. The in-code comment claiming it did (`tools/pool.ts`, DOMINATED section) was
describing an **earlier version of Tranquility that no longer exists**: `docs/BALANCING.md`
records *"`Tranquility` (lv430) — caught by the new guard on its first run"* and
`docs/SIGNATURE_DESIGN.md` records *"`Tranquility` heals **32** to ONE ally"* — both at odds
with the current `lv320, power 74`. Tranquility was rebalanced (cheaper level, much higher
power) at some point after that comment was written, and the rebalance moved it out of the
dominated relationship the comment describes. **This document updates that stale comment**
(`tools/pool.ts`, DOMINATED section) to state the current, correct relationship instead of
repeating a claim about data that no longer exists.

Whether Tranquility SHOULD be un-dominated is a balance question, not an instrument one —
but as a balance observation: it now reads as a legitimate burst-vs-economy pair (Mending
Surge trades worse mana efficiency for more raw output; Tranquility is the cheaper, more
efficient option), which is a defensible design shape, not obviously a bug. ⚠️ It sits
**4.8% under the DOMINANCE_MARGIN floor on value/s alone** — close enough that any future
buff to Mending Surge's power (or nerf to Tranquility's) should be checked against this
pairing specifically before it ships.

### 4b. "Gambler's Volley should flag against the lv40 Sling" — there is no dominance
relationship here in either direction

Both DEX/Volley, `channel: ranged` (`castOf = 0.3`), both `type: 'damage'`.

| | power | mana | cd | learnLevel | REF | hits | term | dps | totalValue |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Sling | 13 | 5 | 1.3 | 40 | **120** (floored) | [1,2]→1.5 | 1+120×0.003125=1.375 | 13×1.375×1.5×0.95/1.6 | **15.92/s** |
| Gambler's Volley | 10 | 20 | 3.9 | 470 | 470 | [1,6]→3.5 | 1+470×0.005357=3.518 | 10×3.518×3.5×0.85/4.2 | **24.92/s** |

⚠️ Note the REF-vs-scale distinction that matters here: `statScaleOf` reads the ACTUAL
`learnLevel` (40 for Sling — `t=0`, so `scale = STAT_SCALE_LOW` exactly), but the
`1+REF×scale` term multiplies by `REF = max(120, learnLevel)`, i.e. 120 for Sling. Getting
this backwards (using 120 for both) understates Sling and was corrected during this audit;
the corrected figure (15.92) matches `ABILITY_BALANCE_REVIEW.md`'s independent "15.9" almost
exactly.

**Gambler's Volley (24.92/s) is 57% AHEAD of Sling (15.92/s), not behind.** For DOMINATED
to fire on this pair in either direction, either (a) Sling would need to beat GV on both
rates while being level ≤ GV's — it does not, its raw value is far lower — or (b) GV would
need to beat an EARLIER Sling — which is exactly what it does, correctly, and is why no flag
fires: this is progression working as intended, not a miss.

`docs/BALANCING.md` records a real historical near-miss for Gambler's Volley — *"`Gambler's
Volley` 24.9 vs 25.0/s"*, a **0.4% gap**, which is exactly what `DOMINANCE_MARGIN = 1.05` was
added to suppress. But the move it was 0.4% away from is not identifiable as Sling from
current data (Sling now measures 15.9, nowhere near 24.9-25.0) — that comparison was almost
certainly against a different Volley-line move, or against pre-rebalance numbers, and has
since drifted apart. **As stated, this test case does not hold against the current pool**,
and the honest instrument-calibration answer is to say so rather than force a flag that
does not reflect the data.

**Neither miss reflects a defect in the two new checks or in the un-modified DOMINATED
logic** — both are the checks correctly reporting that the specific pairing the brief named
no longer exists in the shape it once did. The comment claiming Tranquility is dominated
has been corrected in-code; no code behaviour changed for either pairing, and no move
numbers were touched.

---

## 5. Full flagged list

Combining the pool's already-established baseline (0 flags from FLOOR / DOMINATED /
OVERBUDGET / HOT-FOR-LEVEL / PROGRESSION on the 77-move damage pool, per the brief) with
the two new checks:

### High severity — the pool's own outlier tests both agree on this

| ✓ | move | line | flag | detail |
|---|---|---|---|---|
| ☐ | **World Ender** (INT, lv920) | Elementalist | IQR-HIGH | 184.0/s clears the INT Tukey fence (Q3 76.0 + 1.5×IQR 64.7 = 173.1) |

### Medium severity — PROGRESSION-RATIO, a line running away from the pool's own typical spread

| ✓ | move | line | flag | detail |
|---|---|---|---|---|
| ☐ | **Heartseeker** (DEX, lv850) | Assassin | PROGRESSION-RATIO | line runs 12.5x low-to-high (Shadowstep 10.0 → Heartseeker 125.2) — 2.9x the pool's own 4.4x median line-ratio |
| ☐ | **Executioner** (STR, lv850) | Duelist | PROGRESSION-RATIO | line runs 10.5x low-to-high (Power Strike 9.1 → Executioner 95.4) — 2.4x the pool's own median |
| ☐ | **Arcane Overload** (INT, lv850) | Arcanist | PROGRESSION-RATIO | line runs 9.0x low-to-high (Spark 11.3 → Arcane Overload 101.4), barely over the fence — 2.05x the pool's own median |

### Worth watching, not flagged — close to the fence on either check

| line | ratio | why it's close |
|---|---:|---|
| STR Bloodrage | 8.45x | 3.4% under the PROGRESSION-RATIO fence (8.75x) |
| WIS Tranquility vs Mending Surge | — | 4.8% under DOMINANCE_MARGIN on value/s; see §4a |

**Total: 4 new flags** (1 IQR-HIGH, 3 PROGRESSION-RATIO) across 77 damage moves — up from
0, without touching a single move's numbers. That is a real, if modest, improvement in what
the tool can see; §6 is honest about how much it still cannot.

---

## 6. What this tool still cannot see

⚠️ A flag is a QUESTION, not a defect — the tool's own words, and every line below inherits
that framing.

- **A uniformly-hot stat produces zero outlier flags, by construction.** §2's finding in
  full: Tukey fencing only catches a move that stands out from ITS OWN neighbours. If an
  entire stat's pool is authored 2-3x hotter than it should be, but internally consistent,
  every move looks locally normal and nothing fires — the exact shape of problem this audit
  was commissioned to find (a 31x whole-pool spread) is, structurally, close to invisible to
  an outlier test unless one single value is extreme enough to clear its own inflated fence,
  which is what happened to World Ender and nothing else.
- **PROGRESSION-RATIO answers "is this line unusual among lines", not "is 4.4x itself the
  right median."** The check found the pool's OWN typical line already runs 4.38x, 75% over
  the stated 2.5x design target, and has no way to flag that fact — only lines further above
  THAT elevated baseline. If the whole pool needs to come down, this check will keep saying
  "looks normal for this pool" all the way down to the last line, because "normal for this
  pool" is exactly what it measures.
- **Neither new check touches restores, buffs, debuffs or control moves.** Both are scoped
  to `dmg` (type `'damage'`, power > 0), matching the existing FLOOR/OVERBUDGET/HOT-FOR-LEVEL
  checks. The `restore` pool (heals) still only gets the original DOMINATED check.
- **A pre-existing pool-membership gap, found but not fixed (out of scope for this pass):**
  `restore = ALL_MOVES.filter(type !== 'damage' && power > 0)` catches every `debuff`/`buff`
  move with positive `power`, not just heals — e.g. `Sunder` (STR, `type: 'debuff'`, `power:
  15`) is enemy-targeted armour-shred, not a heal, but it is compared against Mend/Tranquility
  in the restore cohort rather than against Power Strike in the damage cohort. It never
  surfaced a flag in this pass, but the membership test is measuring the wrong thing for it.
  Flagging for a future pass, not fixed here (fixing it changes which cohort several moves
  are judged against, which could move existing DOMINATED verdicts — outside "add, don't
  replace").
- **Neither check models mitigation, action economy, or realized-vs-paper output.**
  `ABILITY_REWORK.md` §6b already measured that STR's paper tier (highest) and realized tier
  (one of the lowest) diverge because melee dies before it can cast — no static audit of
  `power`/`mana`/`cooldown` can see that; it is a sim question (`tools/sweep40.ts`,
  `tools/focus.ts`), not a pool-consistency one, and this file's own header says so.
- **This document's own numbers are a hand-computed spot-check, not a machine run** (see the
  METHOD NOTE above) — high-confidence given twelve independent cross-checks, but
  `npx tsx tools/pool.ts --md docs/POOL_AUDIT_flags.md` is the number that should actually be
  acted on.

---

## 7. Files touched

- `tools/pool.ts` — added `quantile()`/`tukeyFence()` helpers, the per-stat IQR-HIGH/IQR-LOW
  check (§2), the PROGRESSION-RATIO check (§3, median-multiple fence plus a printed
  Tukey-on-ratios diagnostic), and corrected the stale DOMINATED comment (§4a). No existing
  check's logic was changed; no move's `power`/`mana`/`cooldown`/`range` was touched anywhere
  in `src/moves.ts`.
- `docs/POOL_AUDIT.md` — this document.
