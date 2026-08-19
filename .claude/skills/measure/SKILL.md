---
name: measure
description: "Measure a Monster Tamer balance or design claim properly before acting on it — paired seeds, sign test, error bands, a liveness canary, and enough power to separate the thing you are claiming. Use before tuning any constant, before quoting any figure from a doc, when a mechanic 'should' matter but reads as noise, and when deciding whether a difference is real. This project has twice changed constants on differences a later paired A/B showed did nothing."
argument-hint: "[the claim to test]"
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep, Write
model: sonnet
---

# Measure

The Balancing discipline's rules, which were all paid for. **The sim is the arbiter; genre
intuition tells you where to look, not what is true.**

---

## Before anything: is there already a number, and where did it come from?

**A number in a doc with no provenance is a trap.** A stale doc has cost this project two rounds:
`SHAPE_DIAGNOSIS.md`'s headline (`SPIKE 4/24 → 26/32, p=0.0070`) did not reproduce — 3/8 and 3/12
on two independent instruments — because the very next commit changed the arm's definition. It
was a stale document, not a lying instrument, and the distinction took a round to establish.

So: find the figure, find the run that produced it, and check nothing since has changed what it
measured. If you cannot, treat it as unmeasured.

---

## 1. Judge on a paired sign test, not a mean with a CI

Run the **same fights** under both settings and count better/worse. A few fights swing wildly when
they tip from a timeout to a kill, and those outliers hide real effects inside a confidence
interval. The sign test is robust to them; the mean is not.

`_probe_balance` (spatial sim) and `tools/ab.ts` (TypeScript engine) both do this. **Know which
engine you are on** — see §5.

## 2. Report an error band on every proportion, and say what survives it

| n | approximate band on a proportion |
|---|---|
| 8 | ±17 points |
| 12 | ±14 |
| 16 | ±12 |
| 32 | ±9 |
| 96 | ±5 |

**7/8 versus 6/8 is one seed.** It was reported as "naive beats competent", and it is noise — the
95% CI on 7/8 runs roughly 0.47–0.997. The real finding was the one that survived the band: *both*
complete, so a naive policy finishes the game.

⚠️ **And check that the difference you want to call is bigger than the band before you spend the
fights.** The counter matrix was measured at 12 trials/cell — SE ~14 on a cell, **~18.6 on the gap
between two rows**, which is the quantity every screen actually quotes — and four of six rows
disagreed with the instrument that produced them. Separating an 8-point gap there needs **251
trials/cell ≈ 10,542 fights**. The honest outcome was to delete the numbers, not to re-run at 48.

## 3. Every instrument needs a liveness canary

**A probe that cannot demonstrate it MOVES will report success on nothing.** Exit non-zero if the
perturbation did not bite.

- a nav spike passed on **400 empty paths** (they hash identically)
- a slope probe carried **a second copy of the model it tested**, so the field moved and the
  player did not, and it read 100% ADVANCE at ten of eleven rungs
- an instrument pinned **above the ceiling** read 100% everywhere
- a probe measured a player that **fought with no moves**
- ⚠️ **sweep the canary in both directions when the metric is censored.** Shrinking an AoE radius
  makes empty bursts fizzle and emit no event, so the mean cannot fall below 1 — a one-sided
  shrink canary looks nearly dead on a perfectly working instrument.

## 4. Change ONE thing, measure, then the next

Not a rule of taste — an attribution requirement. A round that lands three interacting changes as
one blob cannot tell you which did what, and this project has a standing rule about it. When a
change is genuinely coupled (body radius, melee reach and separation must move together), say so
and measure the *combination* against a stated prediction.

## 5. ⚠️ Know which engine your instrument runs on

**Two engines, and they disagree.** The player's watched cup fights resolve on
`scripts/sim/sim.gd`; the ladder that prices the entire game models them on `battle_sim.gd`.
`_probe_ladder_slope` and `_probe_shape` **cannot see a spatial change** — verified by grep on the
dependency chain. A green run from them after a `sim.gd` edit is a regression check, **not a
safety proof**, and reporting it as one is a mistake I made in a brief.

`_probe_balance` is the only balance harness that targets the spatial sim.

## 6. The baseline is formally suspended — say what you are measuring against

Per `CLAUDE.md`, there is no standing baseline during the rebuild, and **measuring against a
destroyed one is worse than not measuring**: it produces confident numbers about a machine that
has changed, and confident numbers get quoted later as if they meant something.

So state plainly which of your figures are a **new baseline** and which are a **judgement**. The
port contracts are exempt — they are exact equality, not statistics, and need no baseline.

---

## Two traps specific to this game

**Difficulty separation is capped by arithmetic.** A competent player completes 94%, so **~6
points of headroom exist**. Any mechanism producing more separation than that *must* produce it
by lowering the naive player — and this project has three times "separated the policies" by
pushing the weak player below the on-ramp and nearly called it success. **Always report the naive
arm's floor alongside the gap.**

**An acceptance target needs a floor, not just a ceiling.** One inherited target read "FLAT ≤
12/24 while SHAPED ≥ 18/24" — and was **satisfied by FLAT = 0**, because it bounded the naive arm
from above and never from below.

---

## Reporting

Give the table, the error bands, and one sentence naming which findings survive them. Then say
what you did **not** measure — that honesty has repeatedly been worth more than another table.
