# THE CONVERSION TRACE — where a fight advantage stops being a career advantage

**Round 16 · 2026-08-10 · instrument `monster-tamer/scripts/_probe_convert.gd` + `scenes/_probe_convert.tscn`**

```
cd monster-tamer
"P:/Godot_v4.7.1-stable_win64.exe" --headless --path . res://scenes/_probe_convert.tscn -- --fill              # ~2 min
"P:/Godot_v4.7.1-stable_win64.exe" --headless --path . res://scenes/_probe_convert.tscn -- --rung --seeds 24   # ~6 min
"P:/Godot_v4.7.1-stable_win64.exe" --headless --path . res://scenes/_probe_convert.tscn -- --career --seeds 12 # ~25 min
```

The probe **subclasses `_probe_shape.gd`** (which subclasses `_probe_career_arc.gd`). No second
autopilot, no second training brain, no second team builder. It adds only the tracing.

⚠️ **NOTHING SHIPPED WAS EDITED THIS ROUND.** `./run_contract.sh` PASSES.

---

## 0. THE ANSWER IN ONE PARAGRAPH

**The ratio collapses at hop 6 and at no hop before it.** Following the round-14 shape advantage
(`roster.gd:_shape_to_class`, sum-preserving, kit redrawn) through a real career on identical
seeds, the SHAPED/FLAT ratio reads **1.09x → 1.33x → 1.36x → 1.39x → 1.45x → 4.03x → 1.00x**. It
is not merely alive at every intermediate hop, it *amplifies*: a 9% edge per round becomes a
**4.03x edge on Apex sweep probability** (10 sweeps in 29 Apex cups against 10 in 117). Then it
buys nothing, because **`Career.won_game` is at a ceiling: the naive arm already completes 10 of
12 careers.** The user's hypothesis is **CONFIRMED at the terminal hop and REFUTED in its
arithmetic**: a rung is indeed only ever paid for, never failed — but the price is denominated in
**training weeks, not cups**, and it is ~458 weeks for FLAT and ~330 for SHAPED, not the 65 weeks
the hypothesis computed. The reason is §1: **ADVANCE is a step function of roster fill** — 0%
below fill ≈ 0.40, 83–100% above ≈ 0.45 — so cups cannot be traded for the ladder at all. And the
greppable fact under all of it: **there is no losing condition anywhere in the shipped code.**

---

## 1. THE HYPOTHESIS'S ARITHMETIC IS WRONG BY ~7x — AND WHY (`--fill`)

The hypothesis: at the shipped ADVANCE rates the expected cups to clear eleven rungs is 32.3, at
~2 weeks each ≈ **65 weeks of cupping**, against measured careers of 322–502. If that slack is
real, ADVANCE cannot gate completion.

**The assumption inside it:** those eleven ADVANCE rates are measured against a player already at
`expected_climber_fill` — a player who has *already spent the weeks*. Measured, that assumption is
load-bearing and it fails:

```
after 65 weeks of the best-known training, ONE monster carries 1128 stat points.

  league           cap  fill@65w   expected_climber_fill
  Iron             500     0.376   0.420
  Platinum         900     0.209   0.390
  Tamers Apex     1100     0.171   0.370
```

ADVANCE % by player fill — flat build, the REAL drawn field (`make_cup_field`, archetypes, plans),
the REAL promotion rule (`wins_needed_to_advance`), n=12 cups per cell (±14 points):

| league | 0.15 | 0.25 | 0.35 | 0.45 | 0.55 | at the climber fill |
|---|---|---|---|---|---|---|
| Iron | 0% | 0% | 0% | **92%** | 92% | 75% @ 0.42 |
| Platinum | 0% | 0% | 0% | **92%** | 100% | 58% @ 0.39 |
| Tamers Apex | 0% | 0% | 8% | **83%** | 100% | 8% @ 0.37 |

⚠️ **ADVANCE IS NOT A PROBABILITY YOU CAN PAY DOWN WITH RETRIES. IT IS A STEP.** Below fill ≈0.40
it is *zero at every rung sampled* — not 13%, not 8%, zero, so no number of cups clears it. Above
≈0.45 it is 83–100%, so one or two cups clear it. The entire dynamic range of the ladder lives in
a fill band roughly 0.35→0.45 wide, which is ~10% of a cap and therefore a few dozen training
weeks.

**So the 32.3-cup climb is arithmetically unavailable**, and the slack is not 65/1000 = 15x. It is
458/1000 = **2.2x for FLAT and 3.0x for SHAPED** (§3). The hypothesis's *conclusion* survives; its
*number* does not, and the difference matters — 2.2x of slack is a design that could be closed by
a horizon, 15x is one that could not.

Canary: fill moved Apex ADVANCE by 100 points across the sampled range. The instrument is reading
fill.

---

## 2. THE CONTROLLED TRACE — hops 1–4 at an identical stat total (`--rung --seeds 24`)

Two arms, same six numbers arranged two ways, same rivals, same battle seeds, all eleven rungs,
2,064 fights. Audit @ Platinum: **stat total 10530 → 10530 (+0.00%), spread 0.00 → 1.09.**

| league | fill | hop1 round win F/S | hop2 ADVANCE F/S | hop3 cups F/S | hop4 cup-weeks F/S |
|---|---|---|---|---|---|
| Wood | 0.55 | 56% / 35% | 63% / 33% | 1.6 / 3.0 | 1.6 / 3.0 |
| Copper | 0.47 | 29% / 49% | 8% / 46% | 12.0 / 2.2 | 12.0 / 2.2 |
| Tin | 0.45 | 19% / 14% | 8% / 0% | 12.0 / 50.0 | 12.0 / 50.0 |
| Bronze | 0.43 | 7% / 32% | 0% / 13% | 50.0 / 8.0 | 50.0 / 8.0 |
| Iron | 0.42 | 65% / 60% | 71% / 63% | 1.4 / 1.6 | 1.4 / 1.6 |
| Silver | 0.41 | 66% / 75% | 54% / 71% | 1.8 / 1.4 | 1.8 / 1.4 |
| Gold | 0.40 | 46% / 71% | 25% / 63% | 4.0 / 1.6 | 4.0 / 1.6 |
| Platinum | 0.39 | 65% / 68% | 46% / 54% | 2.2 / 1.8 | 4.4 / 3.7 |
| Masters | 0.38 | 61% / 71% | 38% / 58% | 2.7 / 1.7 | 5.3 / 3.4 |
| Tamer Elite | 0.38 | 59% / 73% | 21% / 63% | 4.8 / 1.6 | 9.6 / 3.2 |
| **Tamers Apex** | 0.37 | 73% / 83% | **8% / 29%** | 12.0 / 3.4 | 24.0 / 6.9 |

```
POOLED  hop1 round win  FLAT 544/1032 [0.50-0.56]   SHAPED 629/1032 [0.58-0.64]   ratio 1.16x
POOLED  hop2 ADVANCE    FLAT  82/264  [0.26-0.37]   SHAPED 118/264  [0.39-0.51]   ratio 1.44x
SUMMED  hop4 CUP-WEEKS for the whole climb   FLAT 126   SHAPED 85    ratio 0.67x
```

Both pooled bands are **disjoint** — this is signal, not noise.

**The structural point of this table, which is why hops 2–4 cannot be where the collapse is:**
hop 3 is hop 2 inverted, and hop 4 multiplies hop 3 by `CupRun.weeks_for_cup`, a constant that is
identical in both arms. So *any* ratio surviving hop 1→2 survives algebraically to hop 4. A
collapse must therefore be **either at hop 1→2, or after hop 4.** It is after.

⚠️ **AND CUP-WEEKS ARE A MINORITY OF A CAREER.** 126 weeks of cupping for FLAT against a measured
458-week career: **72% of the calendar is training and waiting, not competing.** That is the first
half of the dilution — a 41-week saving on the cup bill is a 9% saving on the career.

---

## 3. THE CAREER TRACE — hops 1–6 in situ (`--career --seeds 12`)

Three training brains through the shipped autopilot, same 12 seeds, 1000-week horizon. FLAT and
SHAPED are the naive and the aptitude brain; SPIKE builds the archetype vector. Canary: **stat
spread FLAT 0.11 vs SHAPED 1.10** — the arms are different players.

| arm | hop1 round win | hop2 prom/cup | hop3 cups/career | hop4 med wks | hop4b →Apex | hop5 Apex sweeps | hop6 WON (95% Wilson) |
|---|---|---|---|---|---|---|---|
| **FLAT** | 32% (n=5845) | 8% | 125.2 | 458 | 299 | **10/117** | **10/12 [0.55–0.95]** |
| **SHAPED** | 34% (n=4315) | 11% | 92.2 | 330 | 206 | **10/29** | **10/12 [0.55–0.95]** |
| SPIKE | 23% (n=3295) | 8% | 81.0 | 339 | 167 | 3/6 | 3/12 [0.09–0.53] |

### THE RATIO AT EVERY HOP — the round deliverable

| hop | SHAPED / FLAT | verdict |
|---|---|---|
| **hop1** per-round win probability | **1.09x** | alive |
| **hop2** promotions per cup entered | **1.33x** | alive |
| **hop3** cups per career | **1.36x** | alive |
| **hop4** weeks to finish | **1.39x** | alive |
| **hop4b** weeks to REACH Apex | **1.45x** | alive |
| **hop5** Apex sweep probability | **4.03x** | alive — and the largest ratio in the chain |
| **hop6** `Career.won_game` | **1.00x** | **COLLAPSED** |

`paired FLAT → SHAPED : 10 better / 1 worse / 1 tied · sign-test p = 0.0117`

**The advantage does not leak away. It survives every hop, compounds through five of them, peaks
at hop 5 — and then hits a wall that is not a wall.**

### WHY hop 5 → hop 6 is the collapse, stated mechanically

Apex sweep probability differs by 4x: FLAT needs a median ~11.7 Apex cups to land its sweep,
SHAPED needs ~2.9. **Both get one.** FLAT's 117 Apex cups cost it roughly 47 calendar weeks at
the autopilot's monthly cadence, out of a 1000-week horizon it never comes close to spending. The
4x is spent entirely on the clock, and the clock is not scarce.

⚠️ **AND hop 6 IS SATURATED, WHICH IS THE HONEST READING OF THE 1.00x.** FLAT already completes
**10/12 (83%)**. A 4x multiplier cannot be expressed on an 83% base rate — the metric has 17
points of headroom and needs 300. So this is not "the advantage was destroyed at hop 6"; it is
**"hop 6 stopped being a question before the advantage arrived"**. That distinction changes the
fix entirely (§5).

### What ended the careers that did NOT win

| arm | lost | median gold | empty stalls | frontier-blocked wks | modal stall |
|---|---|---|---|---|---|
| FLAT | 2/12 | **4316** | 0.0 | **93.5** | no promotion out of **Platinum** (×1) |
| SHAPED | 2/12 | 514 | 0.0 | 46.5 | no promotion out of **Platinum** (×2) |
| SPIKE | 9/12 | 368 | 0.0 | 41.8 | no promotion out of **Gold** (×5) |

FLAT's losers end with **4,316 gold, zero empty stalls and 93.5 weeks unable to field the
frontier at all.** That is the *bodies* gate of round 14, unchanged: not difficulty, not money,
not time — an economy shape that leaves a solvent stable unable to buy a fifth mouth at the
moment it needs one. Neither loss column is a fight-difficulty result.

---

## 4. ⚠️ TWO THINGS THAT DO NOT REPRODUCE, REPORTED BECAUSE THEY ARE LOAD-BEARING ELSEWHERE

**1. `docs/SHAPE_DIAGNOSIS.md`'s headline round-15 win — "SPIKE 4/24 → 26/32, paired p=0.0070 FOR"
— IS NOT TRUE ON THIS TREE.** I measured SPIKE at 3/12, median rung Gold. Suspecting my own
instrument, I ran the **shipped** `_probe_shape.tscn -- --pol --seeds 8 --only-arm SPIKE`, which I
did not write and did not touch:

```
  arm         WON (95% CI)      med wks   med rung   spread   goldEnd
  FLAT        7/8 [0.53-0.98]   458       10         0.12     3160
  SPIKE       3/8 [0.14-0.69]   293       6          2.45     448
  paired FLAT -> SPIKE : 3 better / 5 worse / 0 tied   sign-test p = 0.7266
  modal stall: no promotion out of Silver in 150 weeks (x2)
```

The shipped instrument agrees with mine and disagrees with the shipped document. **"A specialist
stopped being a trap" should be treated as retracted until re-measured**; on this tree a
specialist stalls at Silver–Gold and loses 5 of 8 careers. I did not diagnose the cause — it is
outside this round's scope and outside my file ownership — but nothing should be built on the
26/32 figure.

**2. THERE IS NO LOSING CONDITION IN THE SHIPPED CODE.** Grepped across all of `scripts/`
excluding probes: zero hits for `game_over`, `game_lost`, `bankrupt`, `career_over`, any horizon
constant. `Career.won_game` is the only terminal state in the file, and `save_game.gd` persists
exactly one flag. **Every career-ending event this project has ever measured was an instrument's
own stopping rule** — `_probe_career_arc.gd:STALL_WEEKS = 150` and `MAX_WEEKS = 1000` are the
probe's, not the game's. The 2/12 "losses" above are the stall detector firing, not the game
telling anybody anything. In the shipped build those two careers simply continue.

⚠️ So the sentence *"the career has no failure condition"* in the round brief is **literally true
as a code fact**, independent of any measurement.

---

## 5. WHAT THIS MEANS FOR THE NEXT ROUND — and what it rules OUT

**RULED OUT, with the number.**
- *"The advantage dissipates somewhere in the pipeline."* It does not. It compounds 1.09x → 4.03x
  across five hops. **Stop looking for a leak.**
- *"ADVANCE is a price, so the difficulty numbers have been tuning a price."* Half right and the
  wrong half is the actionable one. ADVANCE is a **step function of fill**, not a price: below the
  knee no number of cups pays it. What is priced in retries is the *last* rung only, where the
  player is parked above the knee and grinding a 8%–29% sweep.
- *"Apex is a single terminal filter that kills the advantage."* Refuted — Apex is where the
  advantage is **largest** (4.03x). The filter is real; it just cannot filter, because retries are
  free in time.
- *"Fix it by making the fight harder."* The top four rungs already read FLAT 30% / SHAPED 50%
  ADVANCE (round 14). Raising difficulty raises the fill knee for both arms equally and lands on
  the bodies gate FLAT's losers already trip at Platinum.

**WHAT THE MEASUREMENT POINTS AT.** Completion is saturated because nothing consumes the 542
unspent weeks. Three candidates, each with the acceptance test it must pass — **all are
recommendations, nothing was built:**

**R1 — Give the career a real horizon, and make it the binding constraint.**
The single change with the measured size to matter. A horizon of ~350–400 weeks converts the
existing hop-4 ratio (SHAPED reaches Apex in 206 weeks against FLAT's 299) directly into
completion. It changes nothing about the fight, the field or the economy — it stops paying for
retries with a currency nobody spends.
*Acceptance:* re-run `--career --seeds 24` at the new horizon; **FLAT ≤ 12/24 while SHAPED ≥
18/24**, i.e. `SHAPE_DIAGNOSIS.md` §5's four-round-old target, finally met. And check the on-ramp
separately: FLAT must still *reach* index 8–10, so the naive player still sees the content.

**R2 — Price the retry, not the fight.** A cup at the top rungs costs 2 weeks. FLAT spends 117
Apex cups; if a failed sweep at a rung already cleared cost meaningfully more (a longer trip, a
cooldown, a fatigue cost), the 4x at hop 5 would become a 4x in weeks rather than in patience.
*Acceptance:* FLAT's Apex cups-per-sweep falls from ~11.7 while SHAPED's ~2.9 is unmoved; the
weeks ratio at hop 4 widens past 1.45x.
⚠️ **Do this only if R1 is rejected.** Two costs stacked on the same slack is a difficulty raise
in disguise, and §3's loss column says the ladder cannot afford one.

**R3 — Diagnose the bodies gate before either.** FLAT's losers end with 4,316 gold and 93.5
frontier-blocked weeks. That is the one measured failure mode in the data and it is an economy
shape, not a difficulty. It has now been named in four consecutive rounds
(`META_GAME_REVIEW.md` §5 item 1, `SHAPE_DIAGNOSIS.md` §4, and twice here) and never fixed.
*Acceptance:* `frontierBlockedWeeks` for the losing arms falls below ~10 without any recruit
becoming free.

---

## 6. SAMPLE SIZES, AND WHICH FINDINGS SURVIVE THEM

| finding | n | band | survives? |
|---|---|---|---|
| ADVANCE is 0% below fill 0.40 at three rungs | 12 cups/cell | ±14 pts | **YES** — 0/12 at nine consecutive cells is not a ±14 artefact |
| controlled hop1 1.16x | 1032 rounds/arm | [0.50–0.56] vs [0.58–0.64] | **YES**, disjoint |
| controlled hop2 1.44x | 264 cups/arm | [0.26–0.37] vs [0.39–0.51] | **YES**, disjoint |
| career hop1 1.09x | 5845 / 4315 rounds | ±1.3 pts | **YES**, but it is a *small* effect in situ — see below |
| career hop5 4.03x | 117 / 29 Apex cups | 8.5% [4.7–15.0] vs 34.5% [19.9–52.7] | **YES**, disjoint |
| career hop6 1.00x | 12 seeds/arm | both [0.55–0.95] | **inconclusive as a null** — see below |
| SPIKE does not reproduce at 26/32 | 12 + 8 seeds, two instruments | [0.09–0.53], [0.14–0.69] | **YES** as a failure to reproduce; the two runs agree with each other and not with the doc |

⚠️ **THE hop6 1.00x IS NOT A PROVEN NULL AND MUST NOT BE QUOTED AS ONE.** At n=12 the band is
[0.55–0.95] in both arms; this design could not have detected anything smaller than roughly a
2x difference in completion. What it *can* say, and what the argument actually rests on, is
structural rather than statistical: **FLAT is at 83% and the advantage is 4x, so there is no room
for it to land regardless of n.** Raising n would tighten the band; it would not create headroom.

⚠️ **AND ONE HONEST DEFLATION OF MY OWN HEADLINE.** The in-career hop-1 ratio is **1.09x**, where
the controlled harness at a fixed rung and fixed fill reads **1.16x**. The career player therefore
realises only about half the fight advantage it holds — because it promotes sooner and stands
against a field priced by *rung*, so part of the edge is immediately re-spent on a harder
opponent. That is a genuine (if partial) self-levelling effect and it is worth its own round: it
means fight advantage is converted into *position* before it can be banked as *margin*.

**Not measured, and therefore not claimed:** whether removing `STALL_WEEKS` lets the 2 losing
seeds finish (it requires editing the parent probe's `_run_arc`, which this round could not do);
whether R1's horizon lands on the on-ramp; and anything at all about breeding or potential, which
ran at default floors in every arm and was not separated.
