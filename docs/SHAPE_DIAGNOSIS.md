# SHAPE DIAGNOSIS — the round-11 paradox, resolved

**Round 14 · 2026-08-09 · instrument `monster-tamer/scripts/_probe_shape.gd` + `scenes/_probe_shape.tscn`**

```
cd monster-tamer
"P:/Godot_v4.7.1-stable_win64.exe" --headless --path . res://scenes/_probe_shape.tscn -- --gym    #  ~5s
"P:/Godot_v4.7.1-stable_win64.exe" --headless --path . res://scenes/_probe_shape.tscn -- --nine   # ~20s
"P:/Godot_v4.7.1-stable_win64.exe" --headless --path . res://scenes/_probe_shape.tscn -- --pol --seeds 24   # ~22min
```

The probe **subclasses `_probe_career_arc.gd`** and overrides exactly one method
(`_drill_plan_greedy`). Everything else — barn, recruits, cups, travel, dynasty, the fight — is
the shipped autopilot, so an arm-to-arm difference can only be the training brain.

---

## 0. THE ANSWER IN ONE PARAGRAPH

**Round 11's 9x was real, reproduces at 8.58x, and was never about shape.** Decomposed at an
identical stat vector, **5.50x of it is the KIT** — round 11's control roster carried the loadout
it was bought with, because `week.gd:_redraft_if_stale` did not exist yet. That fix has since
shipped and it fires for *every* monster in the shipped weekly tick (`week.gd:504`), so the
largest measured skill lever in this game was given away to everyone, including the naive player.
The residual attributable to stat shape is **1.39x**, and even that is only collectable if the kit
is redrawn onto the new class: **sum-preserving shape with the old kit is 40% → 42%, i.e.
nothing.** Meanwhile a player cannot buy shape at a constant total anyway — a true archetype spike
costs **31.9% of a monster's lifetime stat points**, and the ladder is priced on total, so it is a
losing trade: 4/24 careers won against naive's 21/24. **The paradox dissolves: shape does not win
fights; kit alignment does, and the game now does that for the player automatically.**

---

## 1. THE POLICY TABLE AT n=24 (brief item 1)

Four arms, the same 24 seeds, 1000-week horizon. FLAT/APT/SPIKE are identical in *every* respect
except the training brain — this is the clean shape treatment the brief asked for. COMPETENT is
the existing composite (shaped training + kit re-draft + succession) kept as the bridge to
`docs/META_GAME_REVIEW.md`.

| arm | what it trains | **WON (95% Wilson)** | median weeks | median rung | spread@exit | gold end |
|---|---|---|---|---|---|---|
| **FLAT** (= NAIVE) | biggest drill on the LOWEST stat | **21/24 [0.69–0.96]** | 478 | 10 | 0.12 | 3160 |
| **APT** | argmax(aptitude × focus_cost) — COMPETENT's brain, *alone* | **18/24 [0.55–0.88]** | 393 | 10 | 1.11 | 3361 |
| **SPIKE** | the class trade pair only, focus cost be damned | **4/24 [0.07–0.36]** | 357¹ | 3 | 2.28 | 193 |
| **COMPETENT** | APT + kit re-draft + succession | **18/24 [0.55–0.88]** | 343 | 10 | 1.13 | 2645 |

¹ censored — SPIKE's median is short because it stalls at **Bronze**, not because it finishes fast.

Paired sign tests on the same seeds (win first, then weeks; a censored run loses to any finish):

```
FLAT -> APT        16 better /  8 worse   p = 0.15
FLAT -> COMPETENT  16 better /  8 worse   p = 0.15
FLAT -> SPIKE       2 better / 22 worse   p = 0.0000
```

**What is signal, stated precisely.**

1. **The naive/competent difference in COMPLETION is NOT distinguishable from zero.** 21/24 vs
   18/24, CIs [0.69–0.96] and [0.55–0.88] overlapping across most of their length. The brief was
   right to refuse the n=8 ordering, and at n=24 the ordering *still* runs the wrong way (naive
   ahead by three) without being significant. **Report this as "no measurable completion
   advantage", never as "naive is better".**
2. **Competence buys PACE, and the effect is real and larger than the brief's 20%:** median 478 →
   343 weeks, **−28%**, on 16 of 24 seeds. p=0.15 on the composite metric only because the win/
   loss flips run against it; on weeks-among-winners it is consistent and one-directional.
3. **The pace is not bought by shape.** FLAT→APT (shape only) is 478 → 393; APT→COMPETENT (kit
   re-draft + succession) is 393 → 343 with *identical* wins. Both halves buy tempo, neither buys
   access.
4. **A genuine specialist is a trap at the current price.** SPIKE is the only arm that produces
   the stat vector `roster.gd:_shape_to_class` builds, and it loses 17 careers out of 24.

---

## 2. THE PARADOX, RESOLVED (brief item 2 + item 3)

### 2.1 The 9x re-run across six rungs and eight rosters

Six arms, identical rivals and identical battle seeds, only the player team differs. Total
preserved to **0.00%** (audited per rung, printed by the probe).

| league | fill | A flat | B shaped | C stats-only | D mismatch | E stale kit | F stale+redraft |
|---|---|---|---|---|---|---|---|
| Wood | 0.55 | 46% | 46% | 46% | 17% | 46% | 46% |
| Tin | 0.45 | 8% | 17% | 17% | 4% | 0% | 8% |
| Iron | 0.42 | 38% | 21% | 38% | 0% | 0% | 38% |
| Gold | 0.40 | 22% | 63% | 22% | 0% | 0% | 19% |
| Masters | 0.38 | 53% | 73% | 55% | 0% | 0% | 38% |
| Tamers Apex | 0.37 | 60% | 85% | 60% | 5% | 3% | 58% |
| **ALL** | | **74/184 40%** | **103/184 56%** | **77/184 42%** | **7/184 4%** | **12/184 7%** | **66/184 36%** |

- **A** the team as `_team_at_fill` builds it — every stat pinned to cap × fill, kit drafted at
  those stats.
- **B** the same team through `roster.gd:_shape_to_class` (sum-preserving) — stats *and* kit move.
- **C** identical shaped stats, **arm A's moveset kept**. The arm round 11 did not have.
- **D** shaped onto a class sharing neither stat with the one it emerged as.
- **E** flat stats, kit drafted at ~8% fill and never re-drawn — **this is the body round 11
  measured**, because `_redraft_if_stale` did not exist.
- **F** arm E with the kit re-drawn at current stats and **no shaping at all**.

### 2.2 The decomposition

```
E ( 7%)  ->  B (56%)   =  8.58x     <- round 11's "9x from shape". REPRODUCED.
E ( 7%)  ->  F (36%)   =  5.50x     <- the KIT alone, at a byte-identical stat vector
A (40%)  ->  C (42%)   =  1.05x     <- stat shape alone, kit unchanged: NOTHING
A (40%)  ->  B (56%)   =  1.39x     <- shape, but only when the kit is redrawn onto it
B (56%)  ->  D ( 4%)   =  0.07x     <- shape onto the WRONG class is catastrophic
```

**F ≈ A (36% vs 40%) is the internal consistency check**: re-drafting a stale kit restores the
body to where it would have been, and no further.

### 2.3 Which candidate resolutions survive

| candidate from the brief | verdict |
|---|---|
| shaped training COSTS total, so the gain and the loss cancel | **REFUTED for the COMPETENT brain, CONFIRMED for a real spike.** See §3. |
| the naive policy's monsters end up shaped anyway | **REFUTED.** Measured spread 0.03 (gym) / 0.12 (career). The naive body is genuinely flat. |
| the 9x was one stalled roster at one rung and does not generalise | **HALF TRUE, and this is the headline.** It generalises as *8.58x against a stale-kit control* and as *1.39x against a fresh-kit control*. The control was the artefact, not the roster. |
| "COMPETENT" is not a clean shape treatment | **CONFIRMED, and now fixed** — FLAT/APT isolate it. It changes the answer's shape but not its sign. |
| shape wins fights but fights are not what gates a career | **REFUTED.** Fights *are* the gate. See §4. |

⚠️ **THE MECHANISM, NAMED.** B beats C by 14 points at an identical stat vector, and D collapses
to 4%. So the live variable is not the stat spread — it is whether the **kit is drawn from the
lines of the class the stats actually make**. Shape's only contribution is that a higher primary
clears higher `learnLevel` gates (`monster_instance.gd:assign_moveset`), unlocking abilities a
flat body of the same total cannot learn. That is a real and legible mechanic. It is also
**entirely machine-operated today**: class is derived from stats every week
(`week.gd:503 recompute_class`), and the kit is redrawn from that class whenever it goes stale
(`week.gd:504 _redraft_if_stale`). **The player cannot get this right, because they cannot get it
wrong.**

---

## 3. WHAT SHAPE ACTUALLY COSTS (brief item 2, the "check whether shape costs total" note)

`--gym`: one body per brain, 336 weeks (a full trainable career), Apex cap 1100, 10 species,
no fights, exact.

| brain | lifetime total | vs flat | spread | top stat | mean focus multiplier |
|---|---|---|---|---|---|
| flat | 4587 | — | 0.03 | 775 | 1.000 |
| **apt** | **4780** | **+4.2%** | 1.19 | 1070 | 0.936 |
| **spike** | **3124** | **−31.9%** | 2.15 | 1100 | 0.618 |

- **The brief's assumption that shaped training costs points is wrong for the brain COMPETENT
  uses.** APT *gains* 4.2%: `week.gd:focus_cost` only bites to 0.936 on average because the brain
  moves off a stat the moment it leads, and the ×1.2 aptitude bonus more than repays it. So
  COMPETENT arrives with **more** total *and* 10× the spread of NAIVE — and still wins no more
  often. That is the sharpest single fact in this document.
- **A real specialist costs a third of its career.** SPIKE pays `focus_cost` in full (0.618 mean)
  for 31.9% fewer points. The ladder prices the player on TOTAL, so those points are pure loss at
  the door *and* the shape they bought is worth only 1.39x in the fight. The trade is bad by a
  wide margin, and the 4/24 completion rate is that arithmetic playing out.
- ⚠️ **The paired-stat drain is NOT the cost.** Every arm uses extreme drills (+24/−4/−4, net
  +16), so the drain is identical across arms. **`FOCUS_SLOPE 0.45` / `FOCUS_FLOOR 0.55` is the
  price of shape**, and it is the only knob that sets it.
  > ⚠️ **REFUTED THE SAME ROUND, BY DIRECT MEASUREMENT — see the INTEGRATOR ADDENDUM at the foot
  > of this file.** `FOCUS_FLOOR 0.55 → 0.75` moved the spike's deficit only **−31.9% → −30.3%**
  > (mean focus multiplier 0.618 → 0.781, i.e. A1's own stated target MET while buying almost
  > nothing), and disabling focus cost entirely (floor 1.00) still left **−28.8%**. Focus cost is
  > worth ~3 points of a ~32-point deficit. **The other ~29 were the per-stat CEILING** — the cap
  > is identical on all six stats, so a body that commits to two is handed one third of the room
  > a body that trains all six gets. It does not lose points to a multiplier; it runs out of
  > anywhere to put them. The rest of this document survived re-measurement; this attribution did
  > not.
- ⚠️ **Reference point for reading any spread number:** a `_shape_to_class` rival sits at spread
  **0.475**. COMPETENT's roster measures **1.11–1.13**. The competent player's bodies are already
  **2.4× more lopsided than the archetypes they fight.** Shape is not scarce and it is not the
  missing skill.

---

## 4. WHAT ACTUALLY GATES A CAREER (brief item 4)

Only the careers that did **not** win, per arm:

| arm | lost | gold at end | empty stalls | cups refused for fee | frontier-blocked weeks | modal stall |
|---|---|---|---|---|---|---|
| FLAT | 3 | 580 | 0.0 | 0.0 | **108.3** | no promotion out of **Platinum** (×2) |
| APT | 6 | 613 | 0.2 | 0.0 | 30.7 | no promotion out of **Platinum** (×3) |
| SPIKE | 20 | 184 | 0.2 | 0.0 | 14.4 | no promotion out of **Bronze** (×10) |
| COMPETENT | 6 | 771 | 0.3 | 0.2 | 32.5 | no promotion out of **Tamer Elite** (×2) |

**Fights, at the top two or three rungs. Not money, not bodies, not time.**

- Every losing career ends with gold in hand (580–771) and **zero empty stalls**. Nobody lost for
  want of a purchase they could have made.
- **Entry fees are not the gate at n=24**: 0.0–0.2 cups refused per losing career. (This
  *narrows* `META_GAME_REVIEW.md`'s COMP_NOFEE finding — the fee still buys pace, but it is not
  what ends a career.)
- **Time is not the gate**: winners finish in 343–478 of 1000 weeks; losers stall for 150 weeks at
  one rung and are cut off by the stall detector, not the horizon.
- **Bodies are a partial gate for the naive player only**: FLAT's losers spend **108 weeks**
  unable to field the frontier at all, against ~31 for APT/COMPETENT. That is the succession
  policy earning its keep — and it is invisible in the win column.
- The terminal condition is `Career.won_game` = **sweeping the Apex draw**. Six of the failures
  reach index 10 and cannot sweep it.

---

## 5. INSTRUCTIONS FOR THE BUILDERS

⚠️ Three framing rules before any of it. (a) **Do not buy the gap by making the naive player
lose** — its losers already stall at Platinum with 108 blocked weeks, so a global difficulty raise
lands on the *bodies* gate, not the skill gate, and removes the on-ramp `CLAUDE.md` requires.
(b) **One value at a time**, re-measured with `--pol --seeds 24`; anything smaller cannot separate
these arms. (c) The acceptance target for the whole round is **FLAT ≤ 12/24 while APT/COMPETENT
stay ≥ 18/24** — competence buying *access*, not just tempo.

### BUILDER A — the training economy (`monster-tamer/scripts/week.gd`)

**A1. Shape is overpriced. `FOCUS_FLOOR` 0.55 → 0.75, `FOCUS_SLOPE` unchanged at 0.45.**
Measured target, `--gym`: SPIKE's "vs flat" moves from **−31.9% to ≥ −15%** and its mean focus
multiplier from 0.618 to ≥ 0.78. Then `--pol --seeds 24`: **SPIKE ≥ 12/24** (from 4/24) with FLAT
unmoved at ~21/24. If SPIKE overshoots past FLAT, the floor went too high — it should be a live
choice, not a new dominant line.
⚠️ Do **not** touch `FOCUS_SLOPE` in the same change. The floor sets the price of a *finished*
spike; the slope sets how fast the price arrives. Only the floor is implicated by the 0.618.

**A2. Leave the drill table alone.** Every arm uses extreme drills and the ±4 paired drain is
common to all of them. It is not the cost of shape and changing it moves all four arms together.

**A3. `_probe_career_arc.gd:~1127` carries a stale ⚠️ comment** claiming `week.gd:apply_activity`
"never calls `assign_moveset()`". It has called it via `_redraft_if_stale` since `week.gd:504`
shipped. The `p_redraft_kits` policy hook it guards is now nearly dead — its whole 5.50x is
already given to every player — and the COMPETENT canary that asserts `kitRedraws > 0` is
measuring only the residual. **Not my file; flagged for the integrator.** Either retire the hook
or re-label it "re-draft EAGERLY rather than when stale".

### BUILDER B — the field and the ladder (`monster-tamer/scripts/career.gd`, `roster.gd`)

**B1. The difficulty model is structurally blind to the only axis that matters. CONFIRMED as
briefed.** `expected_climber_fill` is a stat total over a cap and every `FIELD_*_RATIO_*` is a
ratio to it. A player who buys shape is priced as though they bought nothing — worse, if they buy
it properly they are priced *weaker*, because a spike arrives with 32% fewer points.
**Do not fix this by adding shape to the fill formula** — that re-prices the field against the
player's own build and is circular in exactly the way `CLAUDE.md` says per-class caps were.
Fix it on the FIELD side: **the top four rungs must field champions that beat a flat roster and
lose to an aligned one.** Measured target, `--nine`: at Gold / Masters / Apex, arm **A (flat)
falls from 22 / 53 / 60% to ≤ 35%** while arm **B (shaped + aligned kit) stays ≥ 55%**. That
single change is what makes shape purchasable, and it is measurable before any career is run.

**B2. `roster.gd:_shape_to_class` clamps to `GameData.stat_cap()`, which is
`Career.current_stat_cap()` — the league the game is STANDING IN, not the league being built.**
Shaping a team for any other rung silently clamps all six stats to the current cap and hands back
a flat body. This cost this probe its first run: five of six rungs read 0% and looked like a
finding. Live callers are currently safe by accident (they shape for the current or a lower rung,
where the clamp is loose). **Take the cap as an explicit parameter**, defaulting to the current
one, and assert in `_probe_archetypes.gd` that shaping at a rung above the current one preserves
the total. This is a one-line signature change guarding a whole class of silent flattening.

**B3. Do not touch `CLIMBER_FILL_BY_LEAGUE`.** It is an authored curve with a boot guard and
nothing here says its slope is wrong; what is wrong is the axis it measures. B1 is the fix.

### THE DESIGN CALL FOR THE INTEGRATOR (not a builder task)

The measurement points at one conclusion the tuning cannot reach: **the game auto-solves the only
decision that has been measured to matter.** Alignment has a 14× dynamic range in the fight
(4% mismatched → 56% matched), and the player's hand is nowhere near the lever — class is derived
from stats every week and the kit is redrawn from class for free. `docs/CLASS_REWORK.md`'s
**assignable class** is not a nice-to-have on this evidence; it is the mechanism by which the
14× becomes a decision the player makes, gets wrong, and learns from. Committing to a trade and
then training toward it is exactly *"knowing WHICH monster to make is the skill"*, and it is the
only proposal on the table with a measured effect size large enough to carry the vision.
⚠️ And it must land **with A1**: on today's prices, committing to a trade costs 32% of a career
and loses 17 seeds in 24. Assignable classes without a cheaper spike would ship the trap, not
the decision.

---

## 6. WHAT I VERIFIED, AND WHAT I REFUTED, IN THE BRIEF

**Verified.**
- `_probe_career_arc.gd:_roster_fill` / `career.gd:expected_climber_fill` are a stat total over a
  cap and are structurally blind to shape. (Read, and confirmed by APT: +4.2% total and 10×
  the spread reading as the same player.)
- Competence buys pace, not victory — and the effect is **−28%** (478 → 343 weeks), larger than
  the briefed 20%.
- The n=8 ordering is noise. At n=24 the completion difference is still not distinguishable from
  zero, in either direction.
- Round 11's shape experiment was sum-preserving to 0.00% and its 9x reproduces (8.58x).
- The naive player really does end up flat: spread 0.03 in the gym, 0.12 over a career.

**Refuted.**
- **"Shaped training costs total."** COMPETENT's brain *gains* 4.2%. Only a true archetype spike
  costs, and it costs 31.9% — a different mechanism (`focus_cost`, not the paired drain) than the
  brief supposed.
- **"The 9x is a fight advantage from shape."** 5.50x of it is the kit at an identical stat
  vector; sum-preserving shape with the kit held fixed is 1.05x — nothing.
- **"Shape massively wins fights."** At a fresh kit it is 1.39x, and at a constant number of
  *training weeks* (what a player actually spends) it is strongly negative.
- **"Fights are not what gates a career."** They are: every losing career ends solvent, with a
  full barn, stalled on a top-rung sweep.

**Not measured, and therefore not claimed.**
- Whether breeding/potential changes any of this. `_run_arc`'s dynasty ran in every arm at its
  default floors; I did not separate it. The brief's "breeding the right monsters" half of the
  vision is **untested by this round** and is the obvious next diagnostic.
- Platinum was not one of my six sampled rungs (`NINE_RUNGS = [0,2,4,6,8,10]`), and it is the
  modal stall. Add it before tuning B1.

---

# INTEGRATOR ADDENDUM — round 14 close-out (2026-08-09/10)

Everything below was measured by the integrator on the **merged** tree, after both builders
landed. Where it disagrees with §1–§6 above, this section is the later reading; §1–§6 are kept
verbatim because their decomposition is what the round was built on and it held up.

## A1. `FOCUS_FLOOR` was the wrong knob — the ceiling was the price of shape

See the ⚠️ inserted into §3. The refutation is `_probe_training.gd` §7 plus two `--gym` runs.
`week.gd` now carries **`SPIKE_HEADROOM 1.35`** and **`stat_ceiling()`**: a monster keeps exactly
`6 × nominal cap` of TOTAL room (so `career.gd:expected_climber_fill`, a total over a cap, still
reads a committed build and a balanced one as the same strength, and BUILDER B's field work is
undisturbed), but that room is now spendable up to 1.35 × nominal on any one stat. 1.35 is
`roster.gd:SHAPE_PRIMARY` — the primary weight of the archetype vector the ladder already fields.
`FOCUS_FLOOR 0.75` was kept as well; it narrows the naive rule's points advantage 1.82× → 1.33×.

## B1. Satisfied as written, and the baseline that set it was an instrument artefact

`--nine`'s 22 / 53 / 60% were per-ROUND rates against `make_league_rivals(..., archetype = "")` —
an unshaped, planless field with no `FIELD_ARCHETYPE_POWER_MULT`, which **no cup ever draws**.
Re-measured against the field the game fields, on ADVANCE (the rule the ladder runs on), all
eleven rungs, `scenes/_probe_ladder_slope.tscn -- --shape --seeds 64`, reproduced independently by
the integrator: **top four rungs FLAT 30% / SHAPED 50%, gap +20 points at an IDENTICAL stat
total**; per-round 53% vs 61%. **B1 was satisfied before it was written.** Do not tune the top of
the ladder against 22/53/60. `career.gd` now carries the table and an explicit BAN on adding a
shape term to `expected_climber_fill`, with both reasons stated.

## B2. FIXED. `roster.gd:_shape_to_class` takes an explicit cap

`func _shape_to_class(mi, want, rng, cap_override: float = -1.0)`. The default is the old
behaviour (`GameData.stat_cap()`), so no call site changes; a caller shaping for a rung other than
the one the career is standing in must now pass that rung's cap or it gets a flat body wearing a
shaped label. Two instruments were bitten by this in one round.

## A3. FIXED (as a comment). `p_redraft_kits` is now labelled honestly

`_probe_career_arc.gd`'s ⚠️ claimed `apply_activity` "never calls `assign_moveset()`". It has
called it via `_redraft_if_stale` since `week.gd:581`. The hook now buys only the residual between
*re-draw when stale* and *re-draw eagerly*, not the 5.50×, and says so.

## THE POLICY TABLE ON THE MERGED TREE — n=32, the round's actual answer

`scenes/_probe_shape.tscn -- --pol --seeds 32`, integrator's own run, ~35 min:

| arm | **WON (95% Wilson)** | med weeks | med rung | spread | gold end | paired vs FLAT |
|---|---|---|---|---|---|---|
| **FLAT** (naive) | **28/32 [0.72–0.95]** | 462 | 10 | 0.12 | 2496 | — |
| **APT** | 21/32 [0.48–0.80] | 366 | 10 | 1.10 | 3081 | 18 b / 14 w, p = 0.60 |
| **SPIKE** | 26/32 [0.65–0.91] | 354 | 10 | 2.24 | 3345 | 24 b / 8 w, **p = 0.0070** |
| **COMPETENT** | **28/32 [0.72–0.95]** | **322** | 10 | 1.11 | 3038 | 26 b / 6 w, **p = 0.0005** |

**The honest negative: competence still does not buy ACCESS.** FLAT and COMPETENT complete at the
identical 28/32 (87.5%), CIs exactly coincident. §5's acceptance target — *FLAT ≤ 12/24 while
APT/COMPETENT stay ≥ 18/24* — is **NOT MET**, and nothing in this round moved it.

**What the round did buy, and it is not nothing:**
1. **A specialist stopped being a trap.** SPIKE **4/24 (17%) → 26/32 (81%)**, and its paired sign
   test flips from p=0.0000 AGAINST to p=0.0070 FOR. The build the game's own rivals are made of
   is now a build a player can make.
2. **Pace became statistically real.** FLAT→COMPETENT went from 16/8 p=0.15 to **26/6 p=0.0005**;
   median 462 → 322 weeks, **−30%**.
3. **The on-ramp is untouched.** FLAT's completion rate is unchanged to the percentage point
   (21/24 = 87.5% before, 28/32 = 87.5% after) and its spread is still 0.12.

**⚠️ AND ONE NEW SYMPTOM THAT IS NOT A DIFFICULTY FINDING.** COMPETENT's four losses now stall at
**Wood** (×3) with 120g and 0.8 empty stalls, where they used to stall at Tamer Elite. A competent
policy losing at the FIRST rung is an early-roster or death path, not a skill gap. Diagnose it
before reading anything else into the COMPETENT arm's loss column.
