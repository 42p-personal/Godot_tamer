# CONVERSION DIAGNOSIS — where a fight advantage goes, and why the career never notices

**Round 16 synthesis · 2026-08-10 · SHIPS NOTHING.** No shipped game file was changed by any of
the three lenses or by this synthesis (`git status` shows only `docs/` and `scripts/_probe_*.gd` /
`scenes/_probe_*.tscn` as new). Every number below was produced by a probe, and every number
attributed to a lens that I re-ran myself is marked **[VERIFIED]**.

---

## 0. THE ONE-PARAGRAPH ANSWER

**A fight advantage does not go anywhere. It compounds all the way to the last hop and then meets a
boolean that is already 88% true for the player who has no advantage at all.** Follow the round-14
shape edge through the pipeline and the ratio *grows* at every hop — 1.09x on per-round win, 1.33x
on promotions per cup, 1.36x on cups per career, 1.39x on weeks-to-finish, **4.03x on the
probability of sweeping an Apex cup** — and then collapses to **1.00x** at `Career.won_game`,
because the naive arm already completes 14/16 and there are only six points of headroom above the
competent arm's 15/16. Four rounds looked for a leak; there is no leak. The hypothesis in the brief
— *a rung is never failed, only paid for* — is **CONFIRMED, and the code confirms it harder than
the argument did**: there is no losing condition anywhere in `monster-tamer/scripts/` (zero grep
hits for `game_over`, `game_lost`, `bankrupt`, `career_over`), gold is floored at 0
(`career.gd:1239`), the shipped tournament screen has no cup cooldown, the Wood entry fee waives
itself when the player is broke, and retired monsters still count as bodies and still fight. But
**the hypothesis's arithmetic is wrong by roughly 4x and the correction is the most useful thing
this round produced**: ADVANCE is not a per-cup probability you can pay down with retries, it is a
**step function of roster fill** — measured 0% at every rung sampled below fill ~0.40 and 83-100%
above ~0.45 **[VERIFIED, exact reproduction]** — so the ladder is bought in *training weeks*, not in
cups. Real careers enter 100-130 cups over 354-502 weeks, not 32.7 cups over 65 weeks. The slack
against the 1000-week probe horizon is ~2x, not ~15x — and **0 of 48 careers ever reached that
horizon**, so the horizon has never been load-bearing on any completion figure this repo has
quoted.

---

## 1. THE VERIFIED RATIO TABLE

SHAPED/FLAT, twelve identical seeds, 1000-week horizon, from `_probe_convert.gd` (lens 1). The
"controlled" column is the same manipulation run at fixed rung and fixed fill, 2064 fights, stat
total preserved to +0.00%.

| hop | quantity | career ratio | controlled | error bands |
|---|---|---|---|---|
| 1 | per-round win rate | **1.09x** | 1.16x | controlled CIs **disjoint** (0.50-0.56 vs 0.58-0.64) |
| 2 | promotions per cup (ADVANCE) | **1.33x** | 1.44x | controlled CIs **disjoint** (0.26-0.37 vs 0.39-0.51) |
| 3 | cups per career | **1.36x** | — | algebraically hop 2 inverted |
| 4 | weeks to finish | **1.39x** | 0.67x cup-weeks | — |
| 4b | weeks to reach Apex | **1.45x** | — | 206 wks vs 299 wks |
| 5 | P(sweep an Apex cup) | **4.03x** | — | **disjoint**: 10/117 = 8.5% [4.7-15.0] vs 10/29 = 34.5% [19.9-52.7] |
| 6 | `Career.won_game` | **1.00x** | — | **coincident**: both 10/12 [0.55-0.95] |

**The collapse is at hop 6 and at no hop before it.** Two structural facts make that inevitable
rather than surprising: hop 3 is hop 2 inverted, and hop 4 multiplies hop 3 by
`CupRun.weeks_for_cup`, a constant identical in both arms — so **any ratio surviving hop 1→2
survives algebraically through hop 4**. A collapse could only occur at hop 1→2 or after hop 4. It is
after.

**And hop 5 is the finding that reframes the whole question.** Apex is where the advantage is
*largest*, not where it dies. FLAT needs a median ~11.7 Apex cups to land its sweep and SHAPED needs
~2.9 — a 4x edge — and **both get one**, because 117 Apex cups cost about 47 calendar weeks out of a
1000-week budget the player never approaches. The 4x is spent entirely on a clock that is not
scarce. This is a *ceiling*, not a terminal filter, and the two call for opposite fixes.

### What I re-ran myself

| claim | lens | my reproduction | verdict |
|---|---|---|---|
| ADVANCE vs fill step function | 1 | `_probe_convert.tscn -- --fill`, 936 fights | **exact, digit for digit** |
| FLAT career: median wks / cups | 1 (458 / 125.2, n=12) | `_probe_scarcity` FLAT, n=8: **458 / 123.5**; n=16: **502 / 130.1** | consistent, nested seed subsets |
| no loss condition in shipped code | 2 | grep across `scripts/` excluding probes | **confirmed, zero hits** |
| gold floors at 0 | 2 | `career.gd:1239 gold = maxi(0, gold + amount)` | confirmed |
| retirees can still compete | 2 | `career.gd:1149` slices `Roster.monsters` unfiltered; `ui/tournament_ui.gd:122,173` count `Roster.monsters.size()`; `ui/tactics_ui.gd` has no `retired` reference at all — against `roster.gd:126` which *documents* the rule | **confirmed — signature failure #1 again** |
| hop6 coincidence | all | n=8 **7/8 vs 8/8**; n=16 **14/16 [0.64-0.97] vs 15/16 [0.72-0.99]** | fifth consecutive round |
| SPIKE 26/32 (`SHAPE_DIAGNOSIS.md`) | 1 (reads 3/8) | see §4 | **stale document, diagnosed** |

**The measured fill table, reproduced exactly:**

```
league           0.15    0.25    0.35    0.45    0.55   | climber
Iron               0%      0%      0%     92%     92%   |   75% @ 0.42
Platinum           0%      0%      0%     92%    100%   |   58% @ 0.39
Tamers Apex        0%      0%      8%     83%    100%   |    8% @ 0.37
(n=12 cups per cell; ±14 points. canary: fill moves terminal ADVANCE by 100 points.)
```

65 weeks of best-known training banks 1128 stat points = fill **0.376 / 0.209 / 0.171** at
Iron / Platinum / Apex. The brief's 32-cups-in-65-weeks climb is **arithmetically unavailable** —
that player is below the knee at every rung above Iron and would advance 0% forever. The whole
dynamic range of the ladder lives in a fill band about 0.35→0.45 wide.

⚠️ **MEASURED-CONSTANT CORRECTION FOR EVERY FUTURE BRIEF.** The ADVANCE row
`66 79 45 69 65 58 42 23 34 19 13` is **conditional on `expected_climber_fill`**. Quoted
unconditionally it produced this round's 4-7x arithmetic error. Never compute a cups-to-clear figure
from it without stating that condition. The *realised* rates a real career sees are far lower —
4-13% per cup at most rungs — because the player arrives under-filled and pays in training weeks.

---

## 2. CAN THIS GAME BE LOST?

**Essentially no, and the honest version is worse than "no": it cannot be made losable for the
naive player only.**

### 2a. The census

48 careers, three policies x 16 seeds, 1000-week horizon (`_probe_terminal.gd`, lens 2):

| exit | count | proportion |
|---|---|---|
| **WON** (`Career.won_game`, Apex swept) | 44/48 | 0.917 |
| WALLED (the *probe's* `STALL_WEEKS = 150` rule) | 4/48 | 0.083 |
| **HORIZON** (`MAX_WEEKS = 1000`) | **0/48** | **0.000 [0.00-0.074]** |
| BARN exhausted | 0/48 | 0.000 |

Per policy: NAIVE 14/16 [0.64-0.97] · COMPETENT 15/16 [0.72-0.99] · EXPERT 15/16 [0.72-0.99].
Median career 502 / 352 / 348 weeks. **Coincident completion, 30% separation on pace — the same
result for the fifth round running.**

The shipped game defines **exactly one terminal state**: `career.gd:1220 won_game = true` when
`advanced and is_final_league(idx)`. Everything else this project has ever called a "loss" was an
instrument stopping rule. Four mechanisms keep the retry channel open and none of them can close:
no cup cooldown in `tournament_ui.gd`; the Wood entry fee self-waives when unaffordable
(`tournament_ui.gd:153`); gold floors at 0; retirees still field. Across ~19,000 sampled
career-weeks: weeks with **no rung enterable at all = 0.0%**, weeks with zero non-retired bodies =
**0.0%**, lowest gold ever observed = **21** (never 0).

### 2b. The mechanism, stated properly

Promotion is a **repeated Bernoulli trial with unlimited, unexhaustible retries**. P(eventually
clear) = 1 for any p > 0. So **access is invariant to skill by construction**, and only
E[attempts] = 1/p — i.e. weeks — can respond. The signature is visible in the raw data: COMPETENT
clears Platinum in `2, 2, 2, 3, 5, 5, 5, 7, 8, 8, 9, 9, 10, 17, 20, 36` cups across 16 seeds. An 18x
spread on one rung is what a geometric distribution looks like; it is not what a difficulty gate
looks like.

**"Competence buys pace, not access" should be retired as a mystery and restated as a mechanism:
competence buys pace; pace is not scarce; therefore access is saturated.** The sentence was never
describing a leak.

### 2c. The one genuine failure mode, and the fact that the game never says so

Lens 2's wall test froze each of the 4 walled careers and re-entered 24 more cups at its frontier
with an independent field per trial and a positive control two rungs below. **Three of four were not
walls** — they advanced 4/24, 4/24 and 5/24 (p ≈ 0.17-0.21, i.e. about 5-6 more cups, about 20 more
weeks), with controls at 24/24, 24/24, 17/24. `STALL_WEEKS = 150` declared a wall where the game had
a rate. **The fourth is real**: EXPERT / seed 86400 at Platinum advanced **0/24 [0.00-0.14]** and won
**4 rounds of 120 (3.3%)** against a Silver control of 19/24. That roster is not losing a lottery,
it is outclassed — caused by *roster decay* (bodies age out and are replaced by weaker ones, so
career strength is not monotone), not by the ladder.

**It fires at 1/48 = 2.1% [0.00-0.11] and the game renders it identically to bad luck.** No screen,
no message, no name. Note the sample honestly: 1/48 cannot be distinguished from 0 or from 5%.

### 2d. THE ARITHMETIC CEILING — why six rounds of difficulty tuning failed and will keep failing

This is the finding I would put in front of the creative director.

> COMPETENT completes **15/16 = 94%**. There are **six points of headroom above it.**
> Therefore **any mechanism producing more than ~6 points of policy separation must produce it by
> lowering the naive player.** Separation and the on-ramp are in direct arithmetic conflict for as
> long as the outcome is a boolean sitting at 88-94%.

That is not a measurement, it is arithmetic on measurements, and it explains every result in this
document. It also names the project's thrice-committed failure precisely: *"separating the
policies" by pushing the weak player below the on-ramp is raising difficulty, and in a summary table
it looks identical to rewarding skill.*

`CLAUDE.md`'s ship target is "completing Tamers Apex". **92% of careers complete it, on autopilot,
with the naive training brain.** A target with no failure state and a 92% pass rate is a checklist,
not a game. The ladder is currently a **duration**, not a difficulty.

---

## 3. THE SCARCITY COUNTERFACTUAL — RECOVERED, AND IT KILLS THE OBVIOUS FIX

⚠️ **The third lens reported nothing usable** (its four fields read `Test / a / b / c`). **Its probe
works.** `scripts/_probe_scarcity.gd` is a correct, canaried, `_probe_shape.gd` subclass and its
output was sitting on disk. I re-ran it myself and recovered its data. *A lens that produces data
and no report is indistinguishable from a lens that failed, and this round nearly lost its most
decisive table to that.*

The probe imposes five scarcity regimes at runtime, each with a liveness canary, restoring
everything afterwards. **All five results, n=16 unless stated:**

| regime | FLAT completes | COMPETENT completes | separation | on-ramp |
|---|---|---|---|---|
| baseline (shipped) | 14/16 [0.64-0.97] | 15/16 [0.72-0.99] | +6 pts | intact |
| **(a) hard deadline 400 wks** | **1/16** | 10/16 | +56 pts | **GONE** |
| (a) hard deadline 450 wks | 3/16 | 13/16 | +63 pts | **GONE** |
| (a) hard deadline 500 wks | 7/16 (44%) | 14/16 | +44 pts, p=0.039 | **GONE** (just) |
| (a) hard deadline 600 wks | 11/16 (69%) | 15/16 | +25 pts, **p=0.22 n.s.** | intact |
| (d) rival dynasty D=600, jitter 150 | 11.1/16 | 14.6/16 | +22 pts | intact |
| **(b) lifespan x0.60** | **1/16** | 4/16 | +19 pts | **GONE** |
| **(c) entry fees x8** | **0/16** | **0/16** | **+0 pts** | **GONE** |
| **(e) relegation** (a frontier cup won with 0 rounds costs the rung) | **16/16** | **16/16** | **+0 pts** | intact — *and the game got EASIER* |

Canaries all bit: lifespan touched 354 bodies (mean 7.63 → 4.58 yr, retirements 0.8 → 4.9); fees
drove cup refusals 0.00 → 138.19 per career and end gold 3764 → 77; relegation fired 631 times over
32 careers. A separate `--verify` pass proved the post-hoc deadline censoring is **exactly** a real
short horizon (0 mismatches at n=8) — the instrument is honest.

**Three things follow, and each one closes a door.**

1. **The deadline is a threshold, not a discovery.** The probe's own residual test asks whether
   FLAT-at-(D + median shift) reproduces COMPETENT-at-D. At **9 of 10 deadlines it does** ("shift
   explains it"). A clock does not let competence express anything new; it censors a distribution
   that competence had already shifted 148 weeks. And the *spread* of FLAT's own win weeks
   (370 → 618, 248 weeks) dwarfs any single design choice — a deadline set 50 weeks wrong flips the
   on-ramp from 69% to 44%.
2. **There is no deadline that separates AND keeps the naive on-ramp.** The only cell in the entire
   sweep with FLAT above 50% is D=600, and there the gap is +25 points at **p=0.22 — not
   significant at n=16.** Adding rival jitter softens the cliff but trades the separation away
   one-for-one (D=450: jitter 0 → +63 pts with FLAT at 3/16; jitter 150 → +39 pts with FLAT at
   4.6/16).
3. **Pricing the retry in POSITION rather than time makes the game easier and separates by zero.**
   Relegation was the one non-clock lever and the one with the best theory behind it — it prices the
   player in *round wins*, the axis competence actually moves. Measured: FLAT 14/16 → **16/16**,
   median 502 → **404 weeks (−98)**; COMPETENT 15/16 → 16/16, 354 → 337. Total saturation, +0
   separation. The yo-yo hands the player easy rungs to farm and re-fills them before they re-climb.
   **Do not build this.**

**So the counterfactual's answer is NO.** Making time scarce does not convert skill into access by
any of the five levers tested. Every one of them either separates by deleting the naive player or
fails to separate at all — which is exactly what §2d's arithmetic ceiling predicts.

---

## 4. DO THE THREE LENSES AGREE? (and the one contradiction, diagnosed)

**They agree about the same career.** Verified from source, not from the reports:

- Same seed list — `_probe_shape.gd:MORE_SEEDS` and `_probe_terminal.gd:T_SEEDS` are identical for
  the first 24 entries; the n=8 / n=12 / n=16 runs are **nested subsets**, not different draws.
- Same horizon (1000), same cup cadence (`CUP_INTERVAL = 4`), same completion definition
  (`Career.won_game`, never "reached index 10").
- Same arms: `_probe_shape.gd:_run_arm` shows `FLAT` = brain `flat` + policy `NAIVE`, and lens 2's
  `NAIVE` is that same policy on the shared `_probe_career_arc.gd` parent. Lens 1's `FLAT` 10/12,
  my n=8 `7/8` and lens 2's `NAIVE` 14/16 are one distribution read at three sample sizes.
- Cups per career: 125.2 (lens 1) / 130.1 (lens 2) / 123.5 (mine). Weeks of total clock per cup:
  3.86 (lens 2) / 476÷123.5 = **3.85** (mine). Independent probes, same number.

**The one contradiction is `docs/SHAPE_DIAGNOSIS.md`'s SPIKE headline, and it is a stale document,
not a lying instrument.** The doc claims *"a specialist stopped being a trap — SPIKE 4/24 → 26/32,
paired p=0.0070 FOR"*. Lens 1 read 3/12 on its own probe and **3/8 on the shipped
`_probe_shape.tscn --pol --only-arm SPIKE`, which it did not write or touch**. I diagnosed why via
git rather than re-running it:

- `SHAPE_DIAGNOSIS.md` was last written at **f39163f**.
- The very next commit, **3b6da1b "assignment ships, its stat caps do not"**, changed
  `week.gd` (+172), `_probe_shape.gd` (+96 — including the new `s_nocommit` flag and the comment
  *"a SHAPED arm that never assigns is measuring a player who does not exist"*, i.e. **the SPIKE
  arm's definition changed**), `_probe_career_arc.gd`, `monster_instance.gd`, `roster.gd`,
  `classify.gd` and `week_plan.gd`.
- That commit's own message records the direction: *"a committed specialist won 13/16 careers under
  round 14 and 5/16 with the caps live"*.

**26/32 and 3/8 are measurements of different arms on different trees.** The correct action is to
mark the claim stale in `SHAPE_DIAGNOSIS.md`, not to accuse either instrument. **Nothing should be
built on "a specialist stopped being a trap" until it is re-measured on HEAD at n ≥ 24.**

---

## 5. ROUND 17, RANKED — each with its acceptance test and its risk

> ⚠️ **The ranking is driven by §2d.** While the outcome is a boolean at 88-94%, every
> difficulty-side option is fighting arithmetic. The top recommendation is the only one that isn't.

### R17-1 (RECOMMENDED) — GRADE THE ENDING. Make pace the score.

`Career.won_game` is a single bool (`career.gd:46`, persisted as one flag in `save_game.gd:129`).
Every ratio in §1 survives to hop 4 and dies at that bool. **Give the terminal state a grade** — the
week it landed, the season count, a rank against a named rival dynasty — and read it in the win
screen, the save file and the standings. This changes no difficulty number, no field, no economy
value and no fight.

- **Why it is first:** it converts an *already measured, already significant* difference (FLAT median
  502 weeks vs COMPETENT 354, n=16, distributions disjoint over most of their mass) into the game's
  actual outcome, at zero risk to the on-ramp — by construction, since nobody's completion changes.
- **ACCEPTANCE TEST:** `_probe_terminal.tscn -- --census --seeds 16` reports an outcome distribution
  with ≥ 8 distinct grades per policy **while NAIVE's WON stays ≥ 14/16**, and the NAIVE↔COMPETENT
  grade difference is significant on a paired sign test (it already is on weeks: 148-week median
  shift).
- **RISK, stated honestly:** it is a framing change. If the player never feels the clock, it converts
  nothing — a scoreboard is not a stake. Mitigate by pairing it with R17-2's *visible* rival, which
  is already instrumented and costs no new measurement.

### R17-2 — A SOFT RIVAL DEADLINE, AND ONLY AT D ≥ 600

If a clock is wanted, the measurement says exactly one cell is admissible: **D = 600**, FLAT 11/16
(69%), COMPETENT 15/16 (94%), +25 points, on-ramp intact. Jitter (a rival with its own spread)
softens the cliff at a one-for-one cost in separation.

- **ACCEPTANCE TEST:** `_probe_scarcity.tscn -- --deadline --seeds 32` gives **FLAT ≥ 20/32 (≥62%)**
  AND **COMPETENT − FLAT ≥ 20 points** AND the paired sign test reaches p < 0.05. *It does not reach
  significance at n=16 today (p=0.22) — that is the gate, and it must be cleared before anything is
  built.*
- **RISK:** the win-week spread (248 weeks for FLAT) is ~1.7x the policy shift (148), so a deadline
  converts a lot of luck along with the skill. And per §5's residual test, it discovers nothing —
  it only censors.

### R17-3 — FIX THE THREE THINGS THAT ARE PLAINLY BROKEN (no design risk, do these regardless)

1. **Retirees can compete.** `roster.gd:126` *documents* "a retiree cannot train, feed, or compete".
   Training (`week.gd:650`) and feeding (`week.gd:604`) are enforced; **competing is not**, at
   `career.gd:1149`, `ui/tactics_ui.gd:49` and `ui/tournament_ui.gd:122,173`. Probed by lens 2: a
   stable containing only a retired monster enters and fights a full 3-round cup. Signature failure
   #1, eleventh instance.
   **ACCEPTANCE:** a retired-only stable cannot enter; `_probe_terminal --audit` flips its
   retired-only line from `!!` to `OK`; the census's "no body" column becomes non-zero on ≥1 seed.
2. **Name the outclassed state.** 1 career in 48 sat at a rung it won 3.3% of rounds at, forever,
   with no signal distinguishing it from bad luck.
   **ACCEPTANCE:** that state produces a distinguishable message (scout verdict / standings line)
   that `_probe_terminal --wall` can assert alongside the 0/24 advance reading.
3. **Mark `SHAPE_DIAGNOSIS.md`'s SPIKE 26/32 as stale** with the commit that invalidated it
   (3b6da1b), or re-measure at n ≥ 24 on HEAD. Two independent instruments read 3/8 and 3/12.

### R17-4 (DO NOT BUILD AS SPECIFIED) — the hard 350-400 week horizon

Lens 1's leading recommendation. **Measured refutation:** at D=400 FLAT completes **1/16 (6%)**; at
D=350, **0/16**. Its acceptance test — "FLAT ≤ 12/24 while SHAPED ≥ 18/24", inherited from
`SHAPE_DIAGNOSIS.md` §5 — **is satisfied by FLAT = 0**, because it specifies a ceiling on the naive
arm and no floor. That is the project's thrice-committed failure written into a test.
**Any horizon proposal must carry a FLOOR on the naive arm.** If a horizon is built at all, build
R17-2's.

### R17-5 (RULED OUT BY MEASUREMENT — do not spend a round on these)

- **Relegation / position-priced retries:** FLAT 14/16 → 16/16, median −98 weeks, separation +0. It
  makes the game *easier*.
- **Escalating entry fees (x8):** 0/16 for both arms. A cliff, not a slope.
- **Shorter lifespan (x0.60):** 1/16 vs 4/16. Separation +19 with the on-ramp destroyed.
- **Raising fight difficulty:** ruled out independently by lens 1 — the fill knee moves for both arms
  together and the raise lands on the bodies gate that already accounts for every losing career.

---

## 6. WHAT WAS NOT MEASURED — read this before quoting anything above

1. **Breeding.** Flagged untested by round 15's design lock; still untested. It is the largest
   unmeasured stable-side lever and §2d predicts it will also be absorbed as pace — *predicts*, not
   measures.
2. **`CUP_INTERVAL = 4` is an instrument policy, not a game rule.** The shipped `tournament_ui.gd`
   has **no cooldown** — a real player can enter a cup every week. Every calendar figure in this
   document (3.86 weeks per cup, 26-30% road tax, the 500-week career) is conditional on a cadence
   the game does not enforce. **Nobody has measured the career at cadence 1.** This could move
   everything and it is cheap to test.
3. **Hops 2, 3 and 5 were not independently re-run by me.** I verified hop 6, the fill table and the
   FLAT career constants. The hop 1→2 and hop 5 ratios rest on lens 1's single instrument (though
   its controlled CIs are disjoint and its canaries bit).
4. **The economy as a live constraint.** `feeRefusals` is 0.00 and end gold is ~3.5k in every
   baseline career; the only economy perturbation tested was fee x8, which is a cliff. The slope
   between 1x and 8x is unmeasured.
5. **EXPERT vs COMPETENT.** Lens 2 measured EXPERT once (15/16, 348 wks); nothing separates it from
   COMPETENT, and the roster-decay mechanism behind the only genuine loss appeared *on* EXPERT. A
   policy that churns its roster may be actively worse. n=16, unexplored.
6. **Whether any of this is fun to watch.** `docs/OUTSTANDING.md` §3 has said for four rounds that
   the biggest unchecked assumption in the project is whether the sim is enjoyable to observe, and
   there is still not one playtest record in the repo. Six rounds of measurement have not touched it.
7. **Sample sizes.** Every completion proportion here is n=8, n=12, n=16 or n=48 — roughly ±35, ±28,
   ±25 and ±14 points. The findings that survive their error bands are: the fill step function
   (disjoint by 83-100 points), the hop-5 sweep ratio (disjoint CIs), the hop-6 coincidence at every
   n tried, the 0/48 horizon reading, the 4/120 outclassed round-win rate, and the relegation
   saturation (16/16 in both arms). **Everything else in the deadline sweep is directional only.**

---

## 7. THE SENTENCE THIS ROUND REPLACES

> *"Competence buys pace, not access."* — four rounds, unexplained.

> **"Promotion is a repeated trial with unlimited free retries, so P(clear) = 1 and only E[attempts]
> can move. Pace is the only thing skill CAN buy. And pace is not scored."**

The bug was never in the pipeline. It is in the outcome space.
