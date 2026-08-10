# ⚠️ PROVENANCE SWEEP — round 17, 2026-08-10. READ BEFORE QUOTING ANY NUMBER IN THIS FILE

**Why this banner exists:** a stale figure in `docs/SHAPE_DIAGNOSIS.md` (SPIKE 26/32) was quoted
into a round-16 brief and cost a round, and that was the *second* time — round 14 inherited a wrong
Gold/`teamSize` claim from round 10 the same way. **A number in a doc with no provenance is a trap
for the next round.** This file is the largest accumulation of quotable numbers in the repo and it
spans four rounds and at least five different trees, so every figure below now carries either a
re-measurement or the reason it cannot be trusted.

⚠️ **The single most-quoted sentence in this file is the one that no longer reproduces:**

| claim, and where | status on HEAD | the contradicting reading |
|---|---|---|
| **"the naive player now wins MORE often than the competent one"** — INTEGRATOR VERDICT, and RETRACTION 2 (NAIVE 7/8 vs COMPETENT 6/8) | ⚠️ **THE ORDERING NO LONGER HOLDS.** It has flipped back, and it was never significant in either direction | round 16 `_probe_terminal --census --seeds 16`: **NAIVE 14/16 [0.64–0.97] · COMPETENT 15/16 [0.72–0.99] · EXPERT 15/16**. Round 17 re-run, NAIVE n=6: **6/6**. NAIVE's rate (87.5%) reproduces exactly; COMPETENT's 75% does not |
| the *conclusion* drawn from it — **completion is coincident between policies, so the stable half is not load-bearing for ACCESS** | **SURVIVES, and is now the strongest finding in the repo** — fifth consecutive round | `docs/CONVERSION_DIAGNOSIS.md` §2b explains it mechanically: unlimited free retries make P(clear)=1, so only E[attempts] can move |
| **median 458 / 366 / 366 weeks** (ladder C) | **superseded, same shape** | round 16 n=16: **502 / 352 / 348**. Round 17 n=6 NAIVE: **486**. The ~30% pace separation is the durable part; the absolute weeks are not |
| **"the cup budget is already over at 32.7 against a 25–28 target"** (INTEGRATOR VERDICT) | ⚠️ **THE 32.7 IS CONDITIONAL AND WAS QUOTED UNCONDITIONALLY** | `CONVERSION_TRACE.md` §1: ADVANCE is a **step function of roster fill** (0% below ~0.40, 83–100% above ~0.45), and its eleven rates are measured at `expected_climber_fill`. Real careers enter **123–130 cups**, not 32.7. Quoting it unconditionally produced a 4–7x arithmetic error in a round-16 brief |
| **§5 item 1 — "37% of the career unable to enter the frontier"** | **CLOSED.** Superseded twice | round-11 addendum: 30% → 6% via `SHORT_ENTRY_ALLOWANCE`. Round 17 census, NAIVE n=6: frontier enterable **81.9%** of weeks, farming below **18.1%**, **NO RUNG 0.0%** |
| **§5 item 3 — "make a cup cost a week"** | **CLOSED.** A cup costs weeks (`CupRun.travel`) | round 17 census: **167.5 road weeks** per career, 3.86 weeks per cup |
| **§4 R1 — "retired monsters still fight; no team selection … SURVIVES in the game"** | ⚠️ **FIXED, ROUND 17** | the rule is one function now — `roster.gd:fieldable()/fielded_team()/entry_block_reason()` — and all four doors call it (`career.gd`, `ui/tactics_ui.gd`, `ui/tournament_ui.gd` ×2). `_probe_terminal --audit` asserts it, including against the real `tournament_ui.gd` tree, and now FAILS on regression. See below |
| **§3's re-baseline table — "STALLED at Gold after 449 weeks"** | **superseded; the arc now wins** | it already carries its own provenance warning (measured on a tree being retuned live). Round 17 NAIVE n=6 clears Tamers Apex on 6/6 |
| **B2 (first preserve wk 336 / first birth 338), B3 (2,688g freezer rent), G1, "no monster can fill a Platinum+ cap in one lifetime"** | ⚠️ **UNVERIFIED ON HEAD — not contradicted, not confirmed** | none of these were re-measured this round, and `week.gd` has since gained `SPIKE_HEADROOM`/`stat_ceiling()` (round-14 addendum), which acts directly on the last one. Treat as round-10 readings until re-run |

⚠️ **AND THE HONEST LIMIT OF THIS SWEEP.** Every completion proportion in it is n=6, n=8 or n=16 —
±40, ±35 and ±25 points. `14/16 vs 15/16` and `7/8 vs 6/8` are the *same* null read twice with the
sign flipped by noise. **The ordering is not the finding in either direction; the coincidence is.**

---

# ⚠️ THE REFERENCE PLAYER — the standing definition (2026-08-09, round 12)

**Every difficulty number this project has ever quoted is a statement about a player nobody
wrote down.** `career.gd:CLIMBER_FILL_BY_LEAGUE` is a *measurement of the autopilot*; every
`FIELD_*_RATIO_*` is a ratio to it; and the autopilot's policy was never chosen — it is whatever
`_probe_career_arc.gd`'s first draft happened to do (biggest drill on the lowest stat, kit never
re-drafted, no successor, monthly cup). That accident has been the definition of "the player"
for the entire life of the ladder.

It is now four named policies, first-class objects in the probe, each a real player: it sees only
what a player sees, pays what a player pays, and never reads a rival's stats or the RNG.

| policy | what it plays | pays |
|---|---|---|
| **NAIVE** | the autopilot exactly as it has always played: biggest drill on the LOWEST stat (a points-maximiser that builds a flat generalist), kit drafted once at purchase and never re-drafted, no successor grown, default dynasty floors | full price |
| **COMPETENT** | the stable half played properly: shaped training (lean into aptitude), the kit re-drafted as the body grows, a successor bought before the veteran retires | **full price** |
| **EXPERT** | COMPETENT + dynasty pressure — bench and breed out of a thinner surplus (500g/400g) on a 12-week cooldown, because `week.gd:stat_cap_for` is `league_cap × potential` and potential is the only thing that lifts a ceiling the top of the ladder cannot otherwise reach | full price |
| **SUBSIDISED** | ⚠️ **NOT A PLAYER.** COMPETENT with free recruits, free barn slots, free breeding and no entry fee | nothing |

Run it: `--policies [--seeds N] [--only A,B]`. Four policies × 8 seeds is ~7 minutes.

```
cd monster-tamer && "P:/Godot_v4.7.1-stable_win64.exe" --headless --path . \
    res://scenes/_probe_career_arc.tscn -- --policies --seeds 8
```

## ⚠️ INTEGRATOR VERDICT (round 12, on the FINAL tree) — A HELD CONSTRAINT IS BROKEN

The ladder-C table below was measured mid-round on an in-flight `career.gd`. It has been
**re-run by the integrator on the shipped tree** and reproduces exactly — same fingerprint, same
8 seeds, same numbers: NAIVE **7/8**, COMPETENT **6/8**, EXPERT **7/8**, SUBSIDISED **8/8**;
median 458 / 366 / 366 / 258 weeks. This is not an artefact of a moving target.

**That is a violation of a constraint this project deliberately chose.** An earlier round
*rejected* a tuning in which the naive autopilot cleared Tamers Apex on 3 of 5 seeds, on the
grounds that a lowest-stat-training, kit-never-redrafted, no-successor policy completing the game
makes `CLAUDE.md`'s *"training and breeding are strategy, not maintenance"* **false by
measurement**. The shipped ladder is at 7 of 8 — worse than the reading that was rejected, and
the naive player now wins *more often* than the competent one (inside binomial noise at n=8, but
the ordering is certainly not the intended one).

⚠️ **It was NOT tuned out in this pass, deliberately.** The residual is the archetype spread
(`tactics.gd:FILL_MULT`, measured uncorrelated with strength at r=+0.15 — see
`career.gd:FIELD_KIND_PARITY_APPLIED`), and a blind global difficulty raise would trade this
violation for two others already held: *0 unclearable rungs* and the cup budget, which is already
over at **32.7** against a 25–28 target. Fix the kinds first, then re-read this table.

## ⚠️ RETRACTED BY NAME

**1. RETRACTED: "a competent stable policy CLEARS TAMERS APEX on 5 of 5 seeds"** (the round-12
addendum below, and the `COMPETENT fill@exit` column in `career.gd`'s
`CLIMBER_FILL_BY_LEAGUE` block). **That player did not pay for anything.** The column labelled
"competent" was run with `v_free_bodies = true` and `feeMult = 0.0` — free recruits, free barn
slots, free breeding and no cup entry fee. It is the row now called **SUBSIDISED**, and the
entire difficulty curve is currently priced against it. Measured on the same build, the same
policy at FULL PRICE reached Tamers Apex on 8 of 8 seeds but *won* on 2 of 8, against
SUBSIDISED's 8 of 8. The mislabelling was not cosmetic: it is a 4× difference in completion.

**2. RETRACTED: "the autopilot's verdicts are a *lower bound* on what a good player achieves."**
(§6, standing warning 2.) On the ladder as it stood at 17:15 on 2026-08-09 the NAIVE autopilot
**wins 7 of 8 careers**, one more than COMPETENT. A policy that wins as often as a better one is
not a lower bound on anything; it is evidence that the ladder currently asks nothing of the
stable half of the game. See the design statement below.

**3. SUPERSEDED: "reached Tamers Apex" as a completion metric.** WON is now read off
`Career.won_game` — the Apex draw SWEPT — and reported separately from `reached`. On every
ladder measured this round, reaching index 10 and winning the game differ by 0–6 seeds out of 8.
Reporting `reached` as completion is a claim this project has already had to retract once.

## The measurement, and ⚠️ WHICH LADDER IT IS ABOUT

⚠️ **THREE LADDERS WERE MEASURED IN ONE AFTERNOON BECAUSE `career.gd` WAS BEING RETUNED
UNDERNEATH THE INSTRUMENT, AND THE SWING IS LARGER THAN ANYTHING THE POLICIES DO.** This is
reported, not hidden, and it is why `_run_policies()` now prints a **ladder fingerprint** (every
`FIELD_*` constant, the climber table and the cap schedule) before any row. A policy table
without its fingerprint is unattributable and must not be quoted.

| ladder | NAIVE | COMPETENT | EXPERT | SUBSIDISED | what changed |
|---|---|---|---|---|---|
| A — `04c8c2c` (round-11 ship state) | 1/8 | 2/8 | 4/8 | 8/8 | the ladder the round-12 diagnosis was measured on |
| B — mid-edit, 17:03 | 0/8 (median league **Wood**) | 2/8 | 2/8 | 8/8 | champion band mid-rework; not a coherent state, recorded only to show the size of the swing |
| **C — 17:15, the reading below** | **7/8** | **6/8** | **7/8** | **8/8** | champion band = gap-over-qualifier, `APEX_QUAL_RELIEF` 0.18→0.09, `ARCHETYPE_POWER_MULT` 1.00→0.85, climber table lowered to 0.55→0.37 |

**Ladder C, the reading of record** (8 seeds × 1000 weeks per policy; WON is `Career.won_game`):

```
  ladder fingerprint: SHAPE_EXP=0.35 · APEX_QUAL_RELIEF=0.09 · ARCHETYPE_POWER_MULT=0.85 ·
    CHAMPION_GAP_BOTTOM=0.12 · CHAMPION_GAP_TOP=0.18 · DRAW_RAMP_BOTTOM=0.15 ·
    DRAW_RAMP_TOP=0.05 · DEPTH_RELIEF_PER_ROUND=0.03 · QUAL_RATIO_BOTTOM=0.95 · QUAL_RATIO_TOP=1.08
  climber table: [0.55, 0.47, 0.45, 0.43, 0.42, 0.41, 0.40, 0.39, 0.38, 0.38, 0.37]

  policy       WON   reached (per seed)              median wks  gold end  stat spread
  NAIVE        7/8   [10,10,10,10,10,10,10,7]              458      3160         0.12
  COMPETENT    6/8   [10, 8,10,10,10,10,10,10]             366      3107         1.14
  EXPERT       7/8   [10,10,10,10,10,10,10,10]             366      3376         1.12
  SUBSIDISED   8/8   [10,10,10,10,10,10,10,10]             258      4665         1.36
```

**fill@exit per rung — the row `CLIMBER_FILL_BY_LEAGUE` should be built from.** Mean [min–max]
(n arcs that stood on that rung). ⚠️ A cell with n=0 is not a measurement.

| league | NAIVE | COMPETENT | EXPERT |
|---|---|---|---|
| Wood | 0.53 [0.52–0.53] (8) | 0.54 [0.52–0.55] (8) | 0.54 (8) |
| Copper | 0.43 [0.35–0.51] (8) | 0.41 [0.38–0.42] (8) | 0.41 (8) |
| Tin | 0.48 [0.39–0.54] (8) | 0.47 [0.38–0.48] (8) | 0.47 (8) |
| Bronze | 0.42 [0.34–0.51] (8) | 0.40 [0.38–0.43] (8) | 0.40 (8) |
| Iron | 0.42 [0.39–0.45] (8) | 0.39 [0.35–0.44] (8) | 0.39 (8) |
| Silver | 0.42 [0.40–0.45] (8) | 0.39 [0.32–0.45] (8) | 0.39 (8) |
| Gold | 0.40 [0.35–0.44] (8) | 0.36 [0.30–0.39] (8) | 0.36 (8) |
| Platinum | 0.40 [0.38–0.43] (8) | 0.40 [0.34–0.44] (8) | 0.40 (8) |
| Masters | 0.38 [0.36–0.42] (7) | 0.39 [0.34–0.42] (8) | 0.39 (8) |
| Tamer Elite | 0.40 [0.38–0.41] (7) | 0.40 [0.35–0.43] (7) | 0.40 (8) |
| Tamers Apex | 0.38 [0.34–0.43] (7) | 0.39 [0.34–0.43] (7) | 0.39 (8) |

**Paste-ready COMPETENT row (ladder C):**
`[0.54, 0.41, 0.47, 0.40, 0.39, 0.39, 0.36, 0.40, 0.39, 0.40, 0.39]`

⚠️ **AND THE MOST INFORMATIVE THING IN THAT TABLE IS THAT THE THREE COLUMNS AGREE.** COMPETENT's
fill@exit is within 0.01–0.04 of NAIVE's at every rung, and *below* it at six of eleven. Shaped
training deliberately makes fewer points — it spends the same weeks buying a SHAPE (stat spread
1.14 against 0.12) — and `expected_climber_fill` is a stat total over a cap, so **the model the
whole field is priced against is structurally blind to the axis that separates the two players.**
A competent stable does not look stronger to `career.gd`. It just wins 92 weeks faster.

## Is the gap SKILL or BUDGET? (brief item 4)

The hypothesis was: if the naive career ends rich with empty stalls, the difference is
information, not difficulty. **Measured, that specific hypothesis is FALSE, and what replaces it
is sharper.**

| policy | gold end | gold peak | empty stalls | barn/roster | recruits | bench monster-weeks |
|---|---|---|---|---|---|---|
| NAIVE | 3160 | 3531 | **0.0** | 5.8/5.8 | 7.4 | 4 |
| COMPETENT | 3107 | 3107 | **0.0** | 5.6/5.6 | 5.5 | 17 |
| EXPERT | 3376 | 3376 | 0.0 | 5.6/5.6 | 5.9 | 17 |
| SUBSIDISED | 4665 | 4665 | 0.0 | 6.0/6.0 | 6.0 | 110 |

- **Nobody ends with an empty stall.** Every policy fills its barn. The naive player is not
  sitting on money it does not know how to spend; the barn is full and the gold is spent.
- **But money still decides more than policy does.** On ladder A the *same* policy went 2/8 at
  full price and 8/8 free — six completions bought by the budget alone, against one completion
  (1/8→2/8) bought by the policy. On ladder C the ladder is soft enough that everything wins, so
  the effect is only visible in PACE: SUBSIDISED finishes in 258 weeks against COMPETENT's 366.
- **Money is scarce early and worthless late.** On ladder A the naive career peaked at 1031g
  while a fifth barn stall cost more than that, and the competent one *ended* with 14,062g
  unspent. The economy has a shape problem, not a level problem: the sink that matters (bodies
  and stalls) is priced above early income and irrelevant to late income.

**Splitting the subsidy in half gives the finding an address** (`--only
COMPETENT,COMP_NOFEE,COMP_FREEBODY`, same 8 seeds, same ladder-C fingerprint):

```
  COMPETENT       6/8   median 366 weeks   full price
  COMP_NOFEE      8/8   median 302 weeks   entry fee waived, bodies at full price
  COMP_FREEBODY   8/8   median 254 weeks   recruits/stalls/breeding free, fee at full price
```

**Each half of the subsidy, alone, is worth as much as the whole**: either one takes completion
from 6/8 to 8/8 and cuts 64–112 weeks off the climb. Neither price is a rounding error and
neither is the sole culprit — the stable is squeezed from both ends at once. `BASE_FEE +
FEE_PER_LEAGUE` and `BARN_PRICES`/recruit pricing should be re-derived **together**, against the
income the *previous* rung actually pays, and re-measured with these three rows.

**So the redirect for round 13 is not "tell the player what to buy".** It is: *the early economy
gates the stable, and the late economy has no sink at all.* That is an economy-shape finding
(and `E2`/`B3` in this document already point at it), not a legibility one.

## ⚠️ THE DESIGN STATEMENT — how large SHOULD the gap be? (brief item 3)

This is a design decision, not a measurement, and the measurement above is why it has to be made
now: **on the current ladder the answer is "zero", and zero is the one value the vision rules
out.** `CLAUDE.md` is explicit that *knowing WHICH monster to make is the skill*, and a ladder a
naive autopilot clears 7 times in 8 makes the entire stable half of the game optional.

**Proposed target spread, in `WON` out of 8 seeds at 1000 weeks:**

| policy | target WON | target median weeks | what the player experiences |
|---|---|---|---|
| **NAIVE** | **0–1 / 8**, stalling at **Gold–Platinum** (index 6–7) | — | a real climb: six or seven promotions, roughly two-thirds of the ladder, and then a wall it can feel. This is the ON-RAMP, and it must be generous — a naive player should see most of the content. |
| **COMPETENT** | **5–6 / 8** | ~350–450 | the game is completable by someone who plays the stable properly, but not casually. The two lost seeds are the honest tail, not a punishment. |
| **EXPERT** | **7–8 / 8** | ~280–330, i.e. **~20% faster** | past competent, skill buys PACE and certainty, not access. |

**The load-bearing assertion: the naive/competent gap belongs at the TOP of the ladder, not
spread along it.** Wood→Gold should be clearable on training alone — that is where the player is
still learning what a stat does. Platinum→Apex should require the things only the stable half
provides: a shaped roster, a re-drafted kit, a successor ready before the veteran retires, and
above Gold a bloodline (`stat_cap_for` = `league_cap × potential`; §3 already records that no
monster can fill a Platinum-or-above cap in one lifetime).

**What that implies for where the field is priced, concretely:**

1. **The field must be priced against COMPETENT at FULL PRICE** — the row now measured, never
   SUBSIDISED. Retraction 1 above is the whole reason this sentence exists.
2. **`expected_climber_fill` cannot express the target on its own.** It is a stat total over a
   cap, and the measurement above shows COMPETENT and NAIVE differ by ≤0.04 on it while differing
   by 92 weeks and (on ladder A) by a factor of two in completion. A ladder tuned only on fill
   *cannot* make the top rungs ask for a shaped, re-drafted, succeeded roster, because it cannot
   see one. **The top-four champions need to differ in KIND** (§5 item 7) — that is the mechanism
   by which the meta-game becomes load-bearing, and it is now the highest-value item in this
   document.
3. **Do not buy the gap by lowering the naive player's ceiling.** Making Wood–Gold harder
   removes the on-ramp and hits the naive player where the design wants them comfortable.

## Re-running, and the two things to check first

```
--policies --seeds 8                      # the four-row table + fill@exit + the budget block
--policies --seeds 8 --only COMPETENT,COMP_NOFEE,COMP_FREEBODY   # split the subsidy in two
```

1. **The ladder fingerprint printed at the top.** If it does not match the ladder you mean to
   talk about, nothing below it is quotable. Three ladders in one afternoon.
2. **The canary column.** Every policy row asserts it actually did something — shaped training
   must move the stat SPREAD, succession must buy a body or hold a bench, a re-drafted kit must
   change a moveset. A row that fails prints `VOID` and the probe exits 1. This exists because
   round 11's slope probe measured a player fighting with no moves.

---

# ⚠️ ROUND 12 ADDENDUM — RETRACTIONS (2026-08-09, integrator)

Three claims in this document are withdrawn by name. All three were measured against a build
that carried four dead wires; the wires are now connected and every number below them moved.

**1. RETRACTED: "the arc collapses at Gold, exactly where `teamSizeByLeague` grows and a fresh
~23-per-stat recruit joins."** Wrong twice. `teamSizeByLeague` does not grow at Gold (Silver
3->4, Gold 4->4) — Silver is the step. And neutralising the team-size step entirely leaves the
arc's distribution unchanged ([6,4,6,4,6] against a control of [6,4,7,4,5]). Flattening the cap
schedule to eleven equal +100 steps returns a BYTE-IDENTICAL arc on all five seeds. H1 and H2
are both dead. Measured in `scripts/_probe_gold_wall.gd` §3.

**2. RETRACTED: "it stalls at Gold."** Gold was ONE seed. Over five seeds the pre-round control
stalled at Iron, Iron, Silver, Gold and Platinum — median SILVER. A single arc's stall league is
inside this instrument's own spread and must not be quoted as "the Gold wall".

**3. RETRACTED: the fill@exit row `.44 .39 .43 .67 .56 .67 .66 .52 .63 .61 .62`.** It does not
reproduce on any build since, and its top four rungs cannot have come from a stalling arc — an
arc that never reaches Platinum has no Platinum-and-above samples to report. Re-source it from
`scenes/_probe_ladder_slope.tscn -- --arc-table`, which prints n per cell.

**And the finding that replaces all three.** The career never stalled on the ladder. It stalled
on four things that were authored and connected to nothing:

| dead wire | what it did | fixed in |
|---|---|---|
| `Generalist` has no `classLines` entry | `assign_moveset` cleared the kit and rebuilt NOTHING, so a flat-statted monster fielded ZERO moves. Also hit `save_game.gd` on load. | `monster_instance.gd:_fallback_lines` |
| `week.gd:stat_cap_for` had no shipped caller | bloodline `potential` was priced, previewed and displayed on three screens and applied by nothing; x1.00 and x2.00 trained to the same 750 | `week.gd:apply_activity` |
| `BARN_PRICES` never repriced after `MAX_BARN` rose to 7 | 5,020g cumulative for a Platinum barn against 1,465g peak liquidity — the bench, succession AND breeding were all priced out at once | `ui/shop_ui.gd` |
| the arc's bench guard `barn_capacity > team_need` | the loop below it only ever grew the barn TO `team_need`, so the guard was false at every rung above Wood | `_probe_career_arc.gd` |

With those four connected and `FIELD_ARCHETYPE_POWER_MULT` restored to 1.00 (its 0.90 relief was
paying for the Generalist bug, not for the archetypes), the ladder reads 26.8 cups for the whole
climb and a competent stable policy CLEARS TAMERS APEX on 5 of 5 seeds. The ladder was never the
problem and its slope was never re-tuned.

---
# The Meta-Game Review — the stable half, measured

## ROUND 11 INTEGRATION ADDENDUM (2026-08-09, after the four workstreams landed)

Read this before §3 below: several of its numbers were measured mid-round on a moving tree and
are superseded. The four changes were integrated, wired and re-measured together.

**What the integration cost, and it was not free.** Wiring the archetypes into
`Career.make_cup_field()` — class-shaped rivals, fighting with their own plans — made the field
materially stronger at *identical authored fills*. The eleven-rung ADVANCE column fell from
`66 66 72 59 63 56 47 47 19 50 22` to `50 47 50 22 25 47 16 9 0 16 9`, and Masters became a rung
the modelled climber could not clear. Nothing about the ladder's difficulty design had changed;
only the KIND of team had. Corrected with one measured constant,
`career.gd:FIELD_ARCHETYPE_POWER_MULT = 0.90`, which is a unit conversion between two ways of
spending the same stat budget, not a nerf.

⚠️ **AND IT MUST NOT LIVE IN `tactics.gd`.** Applying it inside `archetype_fill()` blew the
archetype probe's kind-parity band from 29 to 42 points, because the two instruments use
different reference opponents (`_probe_archetypes` fights a generic build, `_probe_ladder_slope`
fights the modelled climber). One knob per question.

**The ladder, after integration** (`scenes/_probe_ladder_slope.tscn`, 32 cups/rung):

```
  league       Wood Copp  Tin Bron Iron Silv Gold Plat Mast Elit Apex
  ADVANCE %      63   81   72   59   59   53   44   38   25   31   28
  cups          1.6  1.2  1.4  1.7  1.7  1.9  2.3  2.7  4.0  3.2  3.6
```

Sloped 63% → 28%, headroom −0.05 → −0.14, **0 rungs unclearable**, ~25 cups for the whole ladder.
The single inversion is Wood→Copper, and `career.gd:FIELD_SHAPE_EXP` already documents Wood as
structurally untunable (a 1v1 at a cap of 100 decided by species matchup).

**Three findings this round produced that were not on anyone's brief:**

1. **The one-monster climber model is this file's largest known inaccuracy.** The arc's roster
   fill tracks `expected_climber_fill()` to Iron (57/55/68/70/68 measured vs 40/52/55/57/58
   modelled) and then collapses to **43% at Gold**, exactly where `teamSizeByLeague` grows and a
   fresh ~23-per-stat recruit joins. An analytic correction (per-body join weeks + the 26% road
   tax) was written and **reverted in the same session** — it drove expected fill to 0.22–0.31
   against a measured 0.44–0.67. ⚠️ **Do not re-attempt the analytic version. Measure the
   `fill@exit` table from a winning arc and interpolate that.**
2. **A new option measured with a policy that does not know when to use it measures the policy.**
   `Career.SHORT_ENTRY_ALLOWANCE` (enter a body down rather than be locked out) took frontier-
   blocked weeks from 30% to 6% — item 1 of §5 below, achieved. But with the autopilot taking it
   *whenever legal*, it entered 4v5 monthly, won 8% of rounds and stalled a rung **lower**. Made
   an escape hatch rather than a default, the arc returns to its unmodified result.
3. **The travel cost interacts with cup cadence, hard.** The autopilot cups monthly and each cup
   costs 1–2 weeks, so **26% of its career is spent on the road, untrained**. Slowing the cadence
   to 10 weeks did not help — it merely moved the wall to Bronze at 48% frontier-blocked. Cup
   frequency is now a real strategic axis and nothing in the game teaches it.

**Findings closed this round:** **E2** (a cup now costs both a fee and a clock — ten Wood cups
back to back move the clock 10 weeks, so the faucet is 95g/week of game time, not per click);
**L2/L1** (the ladder slopes and promotion is no longer `wⁿ`); **L3** (the sign-up card and the
result screen both state `winsNeeded` out loud, and the bracket names each round's archetype);
**§5 item 1** (frontier-blocked 30% → 6%); **§5 item 7** (eleven champions now differ in KIND —
`_probe_archetypes` asserts nine behavioural signatures and a counter matrix with five different
roster answers).

**Still open, and the arc still does not reach Apex.** It stalls at **Gold after 483 weeks**, and
the diagnosed cause is finding 1 above plus the recruit economy — not the ladder's slope, which
the slope instrument reports as walkable end to end at every rung.

---


**Round 10 rewrite, 2026-08-09.** The previous edition of this document was written by an
instrument that could not play half the game it was reporting on. This edition is written by one
that can, and it retracts several of the previous edition's headline findings by name.

**The instrument:** `monster-tamer/scripts/_probe_career_arc.gd` + `scenes/_probe_career_arc.tscn`.

```
cd monster-tamer && "P:/Godot_v4.7.1-stable_win64.exe" --headless --path . res://scenes/_probe_career_arc.tscn
```

Deterministic, ~60s, exit 0 when the instrument is sound (**not** when the game is good — it
reports, it does not judge).

⚠️ **PROVENANCE, AND IT MATTERS MORE THAN USUAL THIS ROUND.** Every arc number below was measured
at **11:42 on 2026-08-09**, on `3doverhal` at commit `4fe6eed` **plus uncommitted in-flight edits
to `career.gd`, `roster.gd` and `tactics.gd` by three other workstreams**. `career.gd` was
rewritten twice *between consecutive runs of this probe* while this document was being written,
and the arc moved by two whole leagues across those runs. **Do not quote a single arc figure from
this document as settled.** Re-run the probe; that is what it is for. What IS stable, and what
this document is really for, is §1 (what the instrument now does), §2 (proof that it responds)
and §4 (which of last round's conclusions were artifacts).

**The observed range, same seed, same autopilot, five runs across ~40 minutes of teammate edits:**
stalls at Silver / Gold / Platinum / Masters; 324–598 weeks; round win rate 26–49%; frontier
unenterable 37–57% of weeks. That spread is the ladder being retuned live, not instrument noise —
the determinism check printed IDENTICAL on every one of those runs.

---

## 0. The verdict, in one paragraph

**The instrument was the finding.** Last round this probe reported a competent-looking career —
319 weeks, a win at Tamers Apex, 21,630 gold, "breeding never fires" — and it reported it while
pinning the wrong rival count, paying purses by the wrong rule, charging no entry fee, and, most
importantly, **never once playing the generational half of the game**. It never called
`Roster.preserve()`, which is the only way `Roster.breeding_stock()` is populated, so `breeds = 0`
was a property of the autopilot, not of the game. Corrected and taught to keep a bench, freeze a
founder, breed off it and field its best five, the same seed on the same tree now **does not win
at all** — it stalls, and where it stalls has moved between Silver, Gold, Platinum and Masters
across the last five runs as three other workstreams retune the ladder underneath it. The single
most useful thing this round produced is not a number; it is §2, a harness that **fails the probe
when an input stops moving the output**, so the next round cannot repeat the mistake that cost
this one.

---

## 1. What the instrument now does that it could not before

Six changes, each of which moved a number that had previously been reported as fact.

| # | change | what it was measuring before |
|---|---|---|
| 1 | **It plays the dynasty.** Keeps a bench, preserves an ageing monster into the freezer, breeds off the freezer, sells or freezes retirees, pays the rent. | `breeds = 0` and `retirements = 0` — presented as findings B1/G2. Both were the autopilot's own limitation. |
| 2 | **Breeding calls the REAL builder.** `_try_breed` now drives `breeding_ui.gd:_make_child` (a Control that is never added to the tree never runs `_ready`), instead of a hand-written copy. | The copy drew parents from the **barn** (the game draws only from the **freezer**), and climbed potential by `POTENTIAL_STEP` — a constant that no longer exists in that file, so it had been silently running on a 0.06 fallback against a real 0.10–0.15. |
| 3 | **The training ceiling is per-monster.** `week.gd:stat_cap_for` is `league cap × potential`; the planner was passed the raw league cap. | Harmless while potential was pinned at ×1.00 by change 1's absence. Wrong the instant a dynasty exists. |
| 4 | **The optimiser knows about focus cost.** `week.gd` gained a focus cost this round; the probe's 30-drill optimiser did not model it. | Finding **T1** — "a one-line policy beats a real optimiser by 21%, and 49% of weeks are a coin flip". Both figures were measuring a strawman. See §4. |
| 5 | **It fields its best five.** `career.gd:enter_league_tournament` slices `Roster.monsters` from the front — barn order **is** the team sheet. With no bench that was moot; with a bench and a foal it fielded the newborn. | Nothing, previously. It would have quietly corrupted every number in this round. |
| 6 | **It counts why a cup was skipped.** New: weeks in which the frontier cup was unenterable *for want of bodies*. | A run spent 151 weeks at Platinum entering **zero** cups there, farming Gold instead, and the per-league table said only "151 wks, 0 cups". |

⚠️ **AND ONE THING THE FIRST ATTEMPT GOT WRONG, RECORDED BECAUSE IT IS THE INTERESTING PART.**
The first competent autopilot was *worse* than the incompetent one — it stalled a whole league
lower. Two reasons, both now fixed and both real lessons about the game: it bought a bench body as
eagerly as a starter (gold that the ladder needed went on a spare mouth, and recruiting was
blocked 18 times), and it preserved the **strongest** ageing monster the moment it entered its
last stretch — i.e. it froze the body the cup needed. A player retires a veteran when the
replacement is ready. The autopilot now buys a bench only out of surplus and only freezes a
monster that has already dropped off the team sheet.

---

## 2. SENSITIVITY — the section that exists because this probe lied once

⚠️ **Last round this probe returned byte-identical results after real system changes, and that was
read as stability. It was an artifact.** The defence against repeating that is not more care, it
is a measurement. Section 6 of the probe perturbs every input that should matter and **fails the
run** if the arc does not answer differently.

```
  perturbation               league / gold / cups / round wins / bred
  —                          L5 / 665g / 54 cups / 50 wins / 0 bred    (control, 200w)
  rivals x0.85 (weaker)      L5 / 1002g / 54 cups / 62 wins / 0 bred   moved
  rivals x1.15 (stronger)    L3 / 487g / 53 cups / 29 wins / 0 bred    moved
  entry fee waived           L5 / 258g / 54 cups / 31 wins / 0 bred    moved
  entry fee x6               L1 / 85g / 32 cups / 38 wins / 0 bred     moved
  optimiser training         L4 / 182g / 53 cups / 46 wins / 0 bred    moved
  no bench/breed (200w)      L5 / 665g / 54 cups / 50 wins / 0 bred    no change — EXPECTED
  —                          L6 / 226g / 105 cups / 100 wins / 0 bred  (control, 400w)
  no bench/breed (400w)      L6 / 688g / 105 cups / 112 wins / 0 bred  moved
```

Three things this harness has already caught, none of which were visible any other way:

- **The dynasty knob is genuinely inert for the first 200 weeks.** Breeding-on and breeding-off
  are byte-identical for the first four in-game years, because nothing has retired yet and the
  freezer is therefore empty. Measured on the full arc: the first preservation happens at **week
  336**, the first birth at **338**. That is *finding **B2*** below, and the harness found it by
  refusing to accept the null.
- **A branch of the autopilot itself was dead.** With the dynasty switched off, the retiree
  disposal path was still freezing retirees, paying the same rent, and producing an identical run.
  The harness reported a dead input; the deadness was in the probe.
- **A perturbation harness must agree with the thing it perturbs.** `_fight_cup` at `mult = 1.0`
  calls the real `Career.enter_league_tournament`; at any other multiplier it rebuilds the field
  at scaled fill and hands the win count to `Career.apply_tournament_outcome`, the documented
  shared tail. `_check_cup_mirror()` asserts the two agree, every run, and prints the assertion.

⚠️ **"Dead" and "unexercised" are reported differently on purpose.** Dead means the input fired and
changed nothing — an instrument fault, and a hard fail. Unexercised means the control run never
reached the state the input acts on — a finding about the game. Conflating them would make this
harness cry wolf, and a harness nobody believes is worse than none.

---

## 3. The re-baseline (⚠️ measured on a moving tree — see the provenance note)

Seed 20260809, competent autopilot, one cup attempt per month, 1000-week budget.

```
  league        wks  cups  rounds  won   gold in  gold out    fill@exit
  Wood            1     2       6    4       166       378        44%
  Copper         49    12      36    4       965       974        41%
  Tin            37    29      87   36      3513      1671        47%
  Bronze         85     4      12    3      1014      2669        61%
  Iron           21    29      87   40      6048      2262        57%
  Silver        105     4      16    6      1217      5020        74%
  Gold          151    37     148    8      9001      9184        56%

  STALLED at Gold after 449 weeks (9.4 in-game years) — no promotion in 150 weeks
  cups entered:  117  (392 rounds, 101 won = 26%)
  gold:          ended 266, peaked 1582 · 4 weeks of 449 broke
  roster churn:  6 recruited · 2 retired · 2 preserved · 0 released · 0 bred
  the dynasty:   best potential x1.00 · gen 1 · 2 on ice · 2688g of freezer rent
  frontier cup UNENTERABLE for want of bodies: 166 weeks of 449 (37%)
  DECISION POINTS: 2825  → ~188 min of menus + 392 fights (~163 min at 25s)
```

⚠️ **READ THE COLUMNS CAREFULLY: weeks are booked to the FRONTIER league, cups to the league
ENTERED.** A row reading "many weeks, few cups" — Bronze 85/4, Silver 105/4, Gold 151/37 — is a
stable **stuck below its own frontier**, farming the rung beneath it because it cannot field the
team size the frontier demands.

**The three readings that survive re-running (they held across all five runs this round, at four
different stall points):**

- **The ladder does not slope.** Sweep rate at the fill a real roster actually has (65%), by rung:
  `75 · 88 · 25 · 88 · 63 · 88 · 100 · 100 · 100 · 88 · 100`. Not monotonic, and the top four rungs
  are *easier* than Tin. The brief's premise (measured last round as `63 · 63 · 25 · 63 · 38 · 63
  · 50 · …`) is confirmed in shape and has moved in level, not in slope, as the endpoints are
  retuned.
- **The opener is free at every rung.** Round one wins **100% at all eleven leagues** at both
  fills, every run. Confirmed, unchanged, and now the single most reproducible fact in this file.
- **Above Gold, no monster can fill its league's cap within one lifetime.** Platinum 900, Masters
  1000, Tamer Elite 1050, Apex 1100 all read `RETIRED FIRST` at ~13.3 points/week against a
  336-week career. `potential` — which only breeding raises — is the only mechanic that lifts that
  ceiling, and §2 shows breeding cannot act before week ~336.

---

## 4. Which of last round's findings survive a competent autopilot

This is the section to read before quoting the previous edition.

| finding | verdict |
|---|---|
| **L1** promotion is a `w³` lottery with an invisible threshold | **SURVIVES**, and is now the clearest thing in the data. Round win rate 26–49% depending on the hour; a sweep of 3–5 rounds off that is a coin-flip machine. |
| **L2** no difficulty curve; rivals are a fixed fraction of the ceiling | **PARTLY SUPERSEDED — by a teammate's work, not by mine.** `career.gd` now builds a cup as an *arc*, opener → champion, with the champion's fill sloping up the ladder. The mechanism L2 complained about is gone. **The symptom is not:** the measured sweep column is still not monotonic and still inverts at the top. |
| **L3** nothing tells the player where the line is | **SURVIVES.** Untouched. |
| **G1** the league stat cap never binds | **SURVIVES**, and is sharper: 0 of 1,349 monster-weeks had nothing left to train, *and* above Gold the cap cannot be reached at all. It is simultaneously never a gate and permanently out of reach. |
| **G2** lifespan never forces turnover | **RETRACTED — it was an artifact.** The old autopilot released every retiree on sight and never reached the horizon. The corrected one records **2 retirements and 2 preservations** in a 449-week run, with the first at week 336. Turnover is real; it is just very late. |
| **B1** breeding is structurally locked out at the top four leagues (barn maxes at 5) | **RETRACTED — the premise is false now.** `shop_ui.gd:BARN_PRICES` has **eight** entries (max capacity 7) against a largest team of 5. There is no structural lock. |
| **B2** *(new)* breeding cannot act before week ~336 | The freezer is the only breeding stock, preservation only makes sense once a body is replaceable, and a monster's career is 336 weeks. So the entire generational half of the game — the half the vision calls "knowing WHICH monster to make" — **cannot begin until the seventh in-game year**, by which time a stalling career has already been stalling for a hundred weeks. |
| **B3** *(new)* the freezer rent is a serious tax nobody has priced | Two founders on ice cost **2,688g** across a 449-week run — comparable to the entire barn upgrade path and ~30% of total purse income. `RENTAL_PER_FROZEN = 12` is flagged in `lab_ui.gd` as a placeholder; it is currently the second-largest sink in the game. |
| **E1** the economy lives in UI scripts | **SURVIVES.** This probe still preloads four UI scripts to read constants it cannot get from the model layer. |
| **E2** gold stops mattering; cups are free | **HALF RETRACTED.** An entry fee now exists (`BASE_FEE` + `FEE_PER_LEAGUE`) and it bites hard — 6,595g over 117 cups, 30% of all purse income, and the arc now ends **broke** (266g) rather than on a 21,630g pile. **But the structural half stands: `Career.week` is still never touched on the cup path.** Ten Wood cups back to back still move the clock zero weeks. The fee narrows the faucet; only a week would close it. |
| **E3** the empty stable is a dead save | **SURVIVES** as a code reading; the Wood entry-fee waiver is a partial backstop, the missing recruit is not. |
| **T1** a one-line training policy beats a real optimiser; 49% of weeks are ties | **RETRACTED AS STATED, AND THE CORRECTION CUTS BOTH WAYS.** The optimiser was blind to the focus cost that landed this round. Made focus-aware: it uses **16 distinct drills** (was 9) and its throughput rises 11.38 → 12.01/wk. **But the one-liner still wins, 14.45/wk**, so the *ceiling* of training skill is still a one-liner — and the near-tie rate went the wrong way, from 49% to **91%**. The focus cost made *which* drill is best churn constantly while making the *stakes* of choosing right almost nil. That is a real improvement in variety and a real problem in weight, and neither was visible before. |
| **T2** stamina is not a currency (rest refunds flat) | **SURVIVES.** Unchanged in `week.gd`. |
| **D1** foraging is strictly dominated | **SURVIVES.** |
| **D2** feeding is worth ~19% and is priced correctly | **SURVIVES**, now ~23% (10.10 → 12.47/wk across the happiness range). Still the healthiest number in the file. |
| **R1** retired monsters still fight; no team selection | ⚠️ **FIXED, ROUND 17 (2026-08-10)** — after surviving eleven rounds. `roster.gd:126` documented "a retiree cannot train, feed, or compete"; `week.gd:650/604` enforced the first two and **nothing enforced the third**, at four separate doors. The rule is now ONE function (`roster.gd:fieldable()` / `fielded_team()` / `entry_block_reason()`) and all four call it. The player is TOLD why rather than handed a dead button (`UI_LAYOUT_RULES.md` rule 2). `_probe_terminal --audit` asserts the predicate, its canary, the headless path and the real `ui/tournament_ui.gd` tree, and **fails** on regression. ⚠️ The probe workaround this row describes (`_probe_career_arc` counting only non-retired bodies) means **every arc number in this file was already measured under the fixed rule** — so nothing above moves, and the fix changes the shipped game only. |

---

## 5. What would most improve it — ranked

Re-ranked against the round's own target (the ladder is the spine; the meta feeds the fight).
Each names the measurement that would prove it.

**1. Give the frontier a way in that is not "own five monsters".** 37% of the measured career —
166 weeks of 449 — was spent unable to enter the frontier cup **for want of bodies**, farming the
rung below at 20–50% purse. That is not difficulty, it is an economy gate wearing difficulty's
clothes, and it is invisible to the player. Either let a short team enter at a penalty, or make
the barn/recruit cost fall inside the income the previous rung actually pays.
*Prove it:* `frontier cup UNENTERABLE` falls below ~5% of weeks.

**2. Make promotion legible — kill `w³`.** Unchanged in rank from last round, now supported by a
26–49% round win rate that swings by 20 points between runs of the same seed on different builds.
A sweep gate converts every pacing question into a variance question.
*Prove it:* cups-per-promotion falls to 1–3 and stops varying 2–37 between rungs.

**3. Make a cup cost a week.** The one remaining half of E2, and the cheapest structural fix in
the file. It also makes item 2 hurt honestly instead of hurting for free.
*Prove it:* the ten-cups-back-to-back reading in section 2 of the probe stops printing "the clock
moved 0 weeks".

**4. Bring the dynasty forward from week 336.** B2. The vision's "knowing WHICH monster to make"
currently cannot be exercised until the seventh in-game year, and G1 says it is *required* from
Platinum up. Something has to make a founder worth freezing while it is still young — a second
nursery slot, a cheap early stud, a potential step that pays before generation 3 — or the top of
the ladder is gated on a system the player structurally cannot have reached.
*Prove it:* `first preserve` and `first birth` land before week 200, and best potential exceeds
×1.00 in a run that clears Platinum.

**5. Price the freezer.** B3. 12g/week/head is 2,688g over a career — a bigger sink than licences,
set as an acknowledged placeholder, and it taxes precisely the system item 4 wants to encourage.
*Prove it:* `freezer rent` drops below the barn path in the arc's own totals.

**6. Give the weekly plan weight, not just variety.** The focus cost fixed the *monotony* half of
T1 (6 drills → 16) and made the *stakes* half worse (49% → 91% near-ties). Variety without weight
is churn. Widen the spread between the best and second-best drill — through commitment costs, not
through bigger numbers.
*Prove it:* near-tie rate falls below ~30% while distinct drills stays above 12.

**7. Make the eleven champions differ in KIND.** Not measured by this instrument and named here
because it is the round's stated biggest miss: eleven authored `read` lines describe eleven
different kinds of team, and `make_league_rivals` differs only by a fill fraction. Until a
champion's shape differs, scouting is decoration and "which monster to make" has one answer.
*Prove it:* an instrument that fields the same roster against each champion and reports different
loss profiles — not just different win rates.

---

## 6. Re-running, and what to watch

```
cd monster-tamer && "P:/Godot_v4.7.1-stable_win64.exe" --headless --path . res://scenes/_probe_career_arc.tscn
```

Exit 0 means the instrument is sound. Watch these six, in this order:

| number | at 11:42 on 2026-08-09 | what it means |
|---|---|---|
| **section 6, every row "moved"** | all live | the instrument is measuring something. **Check this first, always.** |
| **cup mirror agrees with career.gd** | agrees | the perturbation harness has not drifted from the game |
| weeks to win, or the league it stalls at | **stalls at Gold, 449w** | the spine |
| frontier UNENTERABLE weeks | **37%** | whether the wall is difficulty or economy |
| first preserve / first birth | **336 / never** | whether the generational half is reachable |
| gold at end vs peak | **266 / 1582** | whether the fee turned the faucet into a wager |
| **`--policies` WON spread** | **NAIVE 7/8 · COMPETENT 6/8 · EXPERT 7/8** | whether the meta-game is load-bearing at all. Target: 0-1 / 5-6 / 7-8. See the top of this file. |

⚠️ **THREE STANDING WARNINGS FOR WHOEVER READS THIS NEXT.**
1. **Believe section 6 before section 1.** An arc figure from an instrument that has not proved it
   responds is worth nothing, and this probe has produced exactly that class of number before.
2. **The autopilot's play is a policy, not a law.** ⚠️ **AND THE SECOND HALF OF THIS WARNING IS
   RETRACTED — see "THE REFERENCE PLAYER" at the top of this file.** The policy is now named
   (NAIVE) and measured against three others; on the ladder as it stood at 17:15 on 2026-08-09 it
   wins 7 of 8 careers, one MORE than COMPETENT, so it is not a lower bound on anything. What
   survives is the first sentence: it trains lowest-stat-first, never sets tactics, and picks a
   breeding emphasis by doubling down on the line's best stat.
3. **It still cannot tell you whether any of this is FUN.** 392 fights and 188 minutes of menus is
   a measurement of quantity. `docs/OUTSTANDING.md` §3 is still open, and there is still not one
   human playtest record in this repo.
