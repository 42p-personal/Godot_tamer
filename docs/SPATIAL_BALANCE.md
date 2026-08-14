# Spatial balance — the instrument, and the first baseline it produced

**2026-08-14, round 24.** Owner: the Balancing discipline. Instrument:
`monster-tamer/scripts/_probe_balance.gd` + `scenes/_probe_balance.tscn`.

```
P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_balance.tscn -- --seeds=5
```

Exit code is the **canary** result, never the balance result. The numbers below are an
instrument reading; the exit code only says whether the instrument was awake.

---

## 0. The gap this closes, and the one it does not

This project has two balance harnesses — `tools/sweep40.ts` and `tools/ab.ts` — and **both
target the TypeScript engine**. Task #32, "spatial balance instrumentation", had been pending
for twenty rounds. `_probe_sim_quality.gd` measures pacing and shape on the spatial sim and is
good at it; it cannot answer *is AoE now dominant* or *did melee get worse*.

⚠️ **AND IT STILL DOES NOT CLOSE THE TWO-ENGINE GAP.** `career.gd:22` preloads `battle_sim.gd`;
nothing in the ladder's dependency chain loads `sim/sim.gd`. Every number in this document
describes **the fight the player watches**, and the ladder that prices the whole game models
that fight on a different engine. Round 23 widened that gap; this instrument measures one side
of it and cannot see the other.

⚠️ **THE BASELINE IS FORMALLY SUSPENDED** (`CLAUDE.md`). Nothing here is measured against an old
target. §2–§4 are **a baseline being established**, so the geometry agent can move one thing and
see it move. §5 is **judgement** and is labelled as such.

---

## 1. ⚠️ THE ROUND'S CENTRAL CLAIM ABOUT AoE IS REFUTED. Here is the number.

The brief states: *"At a 79-unit self-centred burst on a 5v5, an AoE catches ALL FIVE every
time, so falloff-at-5 is the normal case and the entire AoE half of the pool is mispriced."*

**Measured, 574 bursts across 80 fights on the real 440×246 board:**

| | |
|---|---|
| targets caught per burst | **1.43 ± 0.02** (sd 0.59) |
| bursts catching exactly 1 | **353 of 574 — 61%** |
| bursts catching ≥ 3, *the case the pool is audited at* | **23 of 574 — 4%** |
| bursts catching 5 | **0** |
| catch fraction of *living* enemies | 48% ± 1% |
| AoE's share of all damage dealt | **24%** (single-target casts 60%, free attacks 16%) |

> ⚠️ **ROUND 24 SUPERSEDED THE FIRST HALF OF THE PARAGRAPH BELOW, AND ONLY THE FIRST HALF.**
> `_resolve_aoe` no longer uses `_entry_reach` as the blast radius. The two jobs were separated
> via route (c) — `Sim.aoe_blast_radius`, seeded per LINE, lifted by `GEOMETRY_SCALE` (a blast
> covers ground) not `REACH_SCALE` (which scales separations), and centred on the TARGET for
> channels that fly, on the CASTER for those that do not. There is still **no `area` field**:
> recommendation 1 below was followed, not reversed. The `§1` census now prints `cast r` and
> `blast r` as separate columns, and it is the blast column that §2's "radius actually fielded"
> reports.
>
> **The measurement below stands and was vindicated.** Post-change, at the same `--seeds=5`:
> targets caught per burst **1.43 → 1.51**, radius fielded **55.7 → 18.0**, radius needed to
> catch 3 **89.4 → 77.5**, AoE share of damage **24% → 23%**. The ring shrank 3.1x and the catch
> went *up*, because a small ring placed on an enemy beats a huge ring centred on yourself.
> ⚠️ One thing that did move and is worth watching: the **tail is gone**. Bursts catching ≥3 fell
> from 4% (23 of 574) to **0.2% (1 of 523)**, so the pool priced at three now never reaches three
> under the shipped deploy spread — it reaches it only when the enemy piles (§2B, 2.74 at a 44u
> band). That is arguably the design rule expressed correctly, but it is a structural change to
> the AoE half of the pool and it was not the change anyone set out to make.

The mechanism the brief described was exactly right at the time of writing — `_resolve_aoe` used
`_entry_reach` as both the targeting radius and the emitted blast radius, there was no `area`
field, and a range-9 AoE really did blast 78.3 units. **The consequence drawn from it is
backwards.** The pool is
priced at three targets (`aoe_falloff(3) × 3 = ×2.70`) and delivers 1.43. Falloff-at-5 is not
the normal case; it is a case that **did not occur once in 574 bursts**.

### Why — and this is the number a geometry change is judged against

| measured at burst time | value |
|---|---|
| radius actually fielded | 55.7 ± 0.1 |
| radius **needed** to catch 2 | 68.2 ± 1.1 |
| radius **needed** to catch 3 | **89.4 ± 1.0** |
| radius **needed** to catch all living | 112.3 ± 1.5 |
| enemy line span at burst | 117.5 ± 2.1 |
| deploy band height (`Sp.deploy_positions`) | **147.8** on a 246-deep board |

**A 5v5 line is 118 units tall and the median AoE radius is 45.8.** The governing variable is
not the radius, it is the **spread** — and `deploy_positions` sets that spread at 147.8u by
construction (`band = max(team_size × 6 × 2.2, ground.y × 0.60)`, so on a 5v5 board the
`share_of_field` term wins and the line spans 60% of the ground).

§2B proves the causality by squeezing the target side's deploy band and changing *nothing else*:

| band height | targets/burst | catch fraction | bursts |
|---|---|---|---|
| 148u (shipped) | 1.48 | 49% | 135 |
| 89u | 1.85 | 60% | 110 |
| 44u | **2.35** | **84%** | 104 |
| 18u | 2.27 | 80% | 113 |

Catch is steeply governed by spread and saturates around a 44u band — i.e. **an AoE reaches
its authored design point only when the enemy is packed into roughly a third of its own deploy
band.** That happens in a scrum and essentially never on the approach.

⚠️ **THE HONEST CAVEAT.** These bursts come from a fixture where the AoE side is five holders
and the target side is five bodies of one archetype. A composition that genuinely piles up —
five melee converging on one focus target — would catch more. What §2B shows is the *shape of
the sensitivity*, not a claim that 1.43 is the number for every comp in the game. The number
for **this fixture on this board** is 1.43, and it is the first one anybody has.

### What this changes about the round's plan

- **Do not author an `area` field to shrink blasts.** The measurement says the blast is already
  smaller than the geometry it is priced for. Route (a) in the brief solves a problem that is
  not happening, at the cost of touching a legacy tree with 286 tests and goldens.
- **One number doing two jobs is still a real defect**, and it should still be fixed — but for
  the reason the *renderer* cares about, not the balance reason. A melee `Cleave` painting a
  43.1-unit ring while the melee basic reaches 6.6 is a **screen that lies about the thing it
  describes** (signature failure #3), and it is a lie the player watches every fight.
- **The cheap correct fix is route (b) or (c)** — derive or seed the blast in Godot, decoupled
  from cast range — and the acceptance target for it is now a measured number rather than an
  intuition: see §5.

---

## 2. What the instrument can and cannot see

### Can

- **AoE geometry, statically** (§1 census). Every allEnemies move's live radius after
  `min(range × 8.8, HARD_REACH_MAX)`, against melee reach and deploy separation. This section
  cannot be wrong about the sim because it only restates `sim.gd:_entry_reach`'s arithmetic.
- **AoE in play** (§2). Targets caught per burst, catch fraction of *living* enemies (never of
  team size — scoring the back half of a fight against 5 would dilute the finding), the needed-
  radius budget, and AoE's damage share.
- **AoE sensitivity to spread** (§2B), which is the discriminator between "the radius is too
  small" and "the enemy is too spread for any radius the pool authors".
- **Whether two kit archetypes trade fairly** (§3), at equal stat totals, both sides, paired
  seeds, judged on a two-sided exact **sign test** — never a mean with a CI, because a few
  fights swing wildly when they tip from a timeout to a kill and those outliers hide real
  effects.
- **How a fight ends** (§4), with an error band at n=80.

### Cannot

- **Composition.** Every archetype is five identical bodies with one kit axis changed. That is
  deliberate — a mixed comp puts noise on the axis under test — but it means this probe says
  nothing about whether tank/healer/caster mixes are healthy. `_sweep_comps.gd` owns that
  question and should keep it.
- **The ladder.** See §0. A green run here is **not** evidence that a ladder-facing change is
  safe, and a green `_probe_ladder_slope` is not evidence that a spatial change is safe. The two
  instruments are blind to each other by construction.
- **Melee reach vs body geometry.** `BASE_REACH`, `BODY_RADIUS`, `SLOT_RADIUS` are read, never
  swept — a geometry sweep needs sim edits this probe does not own. It measures the *outcome* of
  a geometry change, which is what the geometry agent needs.
- **Support, control and status kits.** All four archetypes are damage kits. Whether a healer or
  a hard-control line trades fairly is unmeasured here.
- **Whether it is fun.** Nothing numeric answers that; `docs/OUTSTANDING.md` §3 stands.

### ⚠️ The liveness canaries, and why every one of them exists

Signature failure #2: instruments that lie. Round 10's nav spike "passed" on 400 empty paths;
round 15's instrument read 100% everywhere because it was pinned above the ceiling. Every
measurable here has a perturbation that must move it, and the probe **exits non-zero** if it
does not.

| canary | perturbation | measured |
|---|---|---|
| **C1** AoE radius | every kit `range` × 0.25 / × 1 / × 2.5 | 1.30 → 1.48 → **2.44** targets/burst, monotone |
| **C2** trade detector | mirror with one side at +25% stats | buffed side **10/10**, sign-test p = 0.002 |
| **C3** ending detector | CON × 0.55 on both sides | 21.0s → **17.2s** |
| **C4** determinism | same seed twice, in-process | identical frame hash |

C1 is swept in **both** directions on purpose. Shrinking the radius *censors* the distribution —
an empty burst fizzles and emits no `aoe` event at all, so the mean cannot fall below 1 and a
one-sided shrink canary would look nearly dead even on a working instrument. Widening is the
uncensored direction and it is where the movement has to be convincing.

C1 perturbs `entry.range` on the kit dictionaries this probe builds, which is exactly what
`sim.gd:_entry_reach` reads. **No sim edit, no second code path, no fixture that only the canary
exercises.**

⚠️ **C4 IS WEAKER THAN IT LOOKS AND SAYS SO IN ITS OWN OUTPUT.** An in-process twin cannot catch
a hash-order dependency, which is the entire reason `_probe_arena_switch` runs three separate
processes. C4 is a smoke test that *this probe's roster construction draws no rng*; it is not
the determinism gate and must never be cited as one.

*(Incidentally observed, not asserted: C4's hash was `3956467652` in three separate probe
processes launched with different flags — `--quick`, `--seeds=3`, `--seeds=5`. That is a
cross-process agreement and it is encouraging. It is **not** the cross-process determinism
check, because those runs did not vary the arena, which is the axis `_probe_arena_switch`
exists to perturb.)*

---

## 3. THE BASELINE — archetype trade (n = 5 seeds, 80 fights, real 5v5 board)

Four archetypes, **equal stat totals (250/body, 1250/side)**. `_sweep_comps.gd`'s role blocks
run 235 to 305, which is fine for asking about composition shape and useless for asking whether
two kits trade fairly — a 30% stat-budget gap would swamp the axis.

⚠️ **`caster` IS POWER-MATCHED TO `aoe`, MOVE BY MOVE.** Same stat block byte-for-byte, same
`magic` channel, same authored power to the nearest available move. **The only difference is
`target: enemy` vs `target: allEnemies`.** Any gap between those two rows is the price of the
AoE axis, isolated. Picking the caster kit alphabetically would have put a power difference on
the axis and the result would have meant nothing.

| kit | mean power | mean live reach | moves |
|---|---|---|---|
| melee | 29.4 | 27.1 | Blood Fury, Blood Price, Bloodletter, Body Slam, Bonebreaker |
| ranged | 51.0 | 61.4 | Ambush, Deadeye, Fester, Gambler's Volley, Hamstring |
| caster | 38.4 | 62.1 | Displace, Mana Leech, Arcane Bomb, Cinderburst, Rime Bind |
| aoe | 43.6 | 55.3 | Detonate, Frost Nova, Inferno, Seismic Crush, Static Chain |

| X | Y | n | X wins | p | mean length | verdict |
|---|---|---|---|---|---|---|
| melee | melee | 5 | 1/5 | 0.375 | 23.4 ± 1.8 | mirror |
| melee | ranged | 10 | 8/10 | 0.109 | 22.7 ± 0.7 | no call |
| melee | caster | 10 | **10/10** | **0.002** | 18.1 ± 0.6 | **melee favoured** |
| melee | aoe | 10 | 8/10 | 0.109 | 20.6 ± 0.4 | no call |
| ranged | ranged | 5 | 4/5 | 0.375 | **101.2 ± 12.8** | mirror |
| ranged | caster | 10 | 2/10 | 0.109 | 65.0 ± 3.0 | no call |
| ranged | aoe | 10 | **0/10** | **0.002** | 70.7 ± 5.7 | **aoe favoured** |
| caster | caster | 5 | 4/5 | 0.375 | 36.8 ± 1.1 | mirror |
| caster | aoe | 10 | 5/10 | 1.000 | 40.1 ± 1.6 | no call |
| aoe | aoe | 5 | 0/5 | 0.063 | 36.6 ± 7.0 | mirror |

**Reading it:**

- **Melee is not broken by the range lift.** It is the strongest archetype in the table: unbeaten
  against caster, 8/10 against both ranged and aoe. Round 23's ranged lift did not cost melee the
  matchup — melee closes and wins. This is the check round 23 could not have run, and the answer
  is the reassuring one.
- **AoE beats ranged 10/10 but does not beat its power-matched caster (5/10, p = 1.000).**
  Taken together with §1: the AoE axis is *not* free damage. It buys a ~50% catch fraction on
  1.43 bodies, and against an equal-power single-target kit that is a wash. **AoE is priced
  about right for the geometry it actually meets, and mispriced only against the geometry it was
  authored for.**
- ⚠️ **`ranged vs ranged` at 101.2s ± 12.8 is the outlier and it is a stall, not a fight.** Two
  hold lines at 61.4 reach trading fire; the stagnation ratchet arms on the no-kill clock and
  drags them together, but slowly. This is the same POSTURE-stall shape `_sweep_comps.gd`
  documents, reproduced on the real board.
- ⚠️ **`aoe vs aoe` went 0/5 to side B.** At n=5 that is p = 0.063 — suggestive, not a call, and
  the other three mirrors do not agree with it (1/5, 4/5, 4/5). It also carries the table's
  largest length sem (± 7.0). **Do not read a side bias from this row**; re-run the mirrors at
  higher seed counts before anyone acts on it.
- ⚠️ **"No call" is not "balanced".** At n=10 the smallest reachable p is 0.002 and only a clean
  sweep clears 0.10. Three of the six cross-pairs are `no call` at 8/10 or 2/10 — genuinely
  suggestive splits the sample cannot resolve. Raise `--seeds` before quoting any of them as
  evidence of health.

---

## 4. THE BASELINE — ending shape (n = 80 fights, 79 resolved)

| | value | round 23's n=1 reading |
|---|---|---|
| resolved inside the 1800-tick cap | 79 / 80 (99%) | — |
| fight length | **42.2s ± 3.0** (sd 26.6) | 17.4s |
| first blood | **11.1s ± 0.4** = **36% ± 2%** of the fight | 72% of the fight |
| collapse window (first death → last death) | **31.0s ± 3.0** | ~5s for six deaths |
| deaths per fight | 7.7 ± 0.1 | 6 |
| longest matchup | ranged vs ranged, 101.2s | — |

⚠️ **THIS IS NOT A REFUTATION OF ROUND 23 AND MUST NOT BE QUOTED AS ONE.** Round 23 measured a
*low-fill weak roster*; this fixture is four clean archetypes at equal, healthy stat totals. Two
different fixtures, two different answers, and both can be true: **the sim ends far too fast on
weak rosters and lands in a good band on strong ones.** What this establishes is that
"ending too fast" is a *roster-strength-dependent* failure, not a property of the sim's shape —
which narrows where the geometry agent should look and is worth more than either number alone.

On this fixture the shape is healthy on its own terms: first blood at 36% means roughly a third
of the fight is the closing phase (exactly the "closing under fire" shape `ENGAGEMENT_DESIGN.md`
asks for), and a 31s collapse window means the fight *whittles* rather than detonating. The
27-second sd is dominated by one matchup (ranged mirror at 101s); excluding it the spread is far
tighter.

---

## 5. ⚠️ ACCEPTANCE TARGETS FOR THE GEOMETRY AGENT — this is JUDGEMENT, not baseline

Everything above is measurement. Everything below is my recommendation, and I own being wrong
about it. Each target names the exact probe line that reads it.

**The geometry change on the table** (`BODY_RADIUS` 2.2 → 2.65, `SLOT_RADIUS` 4.8 → ~5.6, the
renderer cap auto-lifting 1.66 → 2.00) makes bodies **bigger and further apart**. Every number
in this document moves in a predictable direction, so the acceptance test is a set of signed
predictions, not a set of "must stay green" gates.

| # | line | today | after the geometry lift | why |
|---|---|---|---|---|
| **G1** | §2 `targets caught per burst` | 1.43 ± 0.02 | **must not fall below 1.30** | a wider surround ring spreads a scrum further, so AoE catch falls. A drop past 1.30 means the geometry change has quietly nerfed the entire AoE half of the pool, which nobody proposed. |
| **G2** | §2 `radius NEEDED to catch 3` | 89.4 ± 1.0 | **must not exceed 100** | this is the budget the pool's 45.8 median is measured against. It rising is the same nerf as G1 seen from the other end, and it is the more sensitive of the two. |
| **G3** | §2B the four-row sweep | 1.48 → 2.35 across the band squeeze | **must stay monotone and still reach ≥ 2.0 at a 44u band** | if the ring is so wide that even a tight comp cannot be caught, "AoE is strong into three" has become unreachable at any spread and the design rule is dead rather than mispriced. |
| **G4** | §3 `melee vs ranged` | 8/10, p = 0.109 | **must not invert to ≤ 3/10** | the geometry lift pushes melee's swing range and its standing position apart. This row is the melee-got-worse detector round 23 named and could not run. An inversion here is the change failing. |
| **G5** | §3 `melee vs caster` | 10/10, p = 0.002 | **must stay ≥ 7/10** | the strongest signal in the table; if the geometry lift can flip a p = 0.002 sweep, it is a bigger change than "one value at a time" permits and should be split. |
| **G6** | §4 `fight length` | 42.2s ± 3.0 | **stay within 30–60s** | wider bodies mean a longer walk into reach. The band is `AUTOBATTLER_DESIGN.md` #11's own (~30s to ~3min) narrowed to what this fixture actually produces. |
| **G7** | §4 `first blood` | 36% ± 2% | **stay in 25–50%** | below 25% the approach has stopped being a phase; above 50% the fight is a walk with an ending, which is the round-23 complaint returning. |
| **G8** | §4 `resolved` | 79/80 | **must stay ≥ 76/80** | a geometry change that pushes fights into the cap has broken resolution, and resolution is not negotiable. |
| **G9** | C1–C4 | all ok | **all four must still pass** | a canary failure invalidates every row above it, including the ones that look green. |

**The one I would watch hardest is G4.** `BASE_REACH` 6.6 vs `SLOT_RADIUS` 4.8 is a 27% margin;
moving `SLOT_RADIUS` to 5.6 without moving `BASE_REACH` leaves 15%, and `sim.gd`'s own comment
requires `SLOT_RADIUS < BASE_REACH × 0.95` = 6.27. It fits, but only just, and a melee body
standing at its slot with 0.67u of margin is one push-out away from being out of its own swing
range. **G4 is the row that would show that as a lost matchup rather than as a comment nobody
re-read.**

### Two things I recommend the round does NOT do

1. **Do not author an `area` field.** §1 says the blast is already smaller than its price. Route
   (a) costs a cross-tree change into a legacy suite with goldens, to fix a direction the
   measurement does not support.
2. **Do not tune AoE power or falloff this round.** `caster vs aoe` is 5/10 at p = 1.000 —
   the flattest row in the table. There is nothing to correct, and correcting it would be a
   change made on no signal, which is the exact failure the Balancing standard exists to stop.

### What I recommend instead, in order

1. **Land the geometry lift, then re-run this probe at `--seeds=5` and diff G1–G9.** That is 81
   seconds of wall time for the whole table.
2. **Fix the renderer's blast ring** so it stops drawing a 43.1-unit circle for a melee `Cleave`.
   Decouple the emitted `radius` from `_entry_reach` (route b/c) — a presentation-truth fix, not
   a balance one, and the balance risk is now measured at approximately zero.
   ⚠️ **DONE IN ROUND 24, AND IT BROKE C1 — WHICH IS THE INSTRUMENT WORKING, NOT FAILING.** C1
   perturbed `entry.range` and called the result "aoe radius". That identity was the very defect
   the fix removed, so the canary was left pointing at the throw while §2 measured the blast:
   it read x0.25 = **1.63**, *above* the unperturbed 1.47, because a shorter throw makes a caster
   close further and land in a tighter cluster. Real behaviour, wrong instrument. C1 now sets
   `Sim.aoe_blast_scale` (a public instance var, default 1.0, drawing no rng, read only by
   `aoe_blast_radius`) and reads **1.00 / 1.47 / 1.64**. It gates on the **widening arm only**:
   an empty burst fizzles and emits no event, so shrinking censors the distribution and the mean
   is floored at exactly 1.00 however small the ring gets — visible in that very row.
3. **Consolidate `KIT_RANGE_LIFT` into `kit.gd` in one commit** (finding 3). Nothing in this
   document changes if the same product arrives from one file instead of two — and this probe is
   the regression detector for that commit: §1's census and C1 both read `_entry_reach`'s output,
   so a botched consolidation that doubled every reach would show up as an §1 census where every
   live radius is clamped at 96.8 and a C1 that has gone flat.
4. **Re-run the mirrors at higher seeds** before anyone reads the `aoe vs aoe` 0/5 as side bias.
5. **The ally-overlap finding (28.7% mean, 58.9% worst) has no line in this instrument**, and I
   did not add one — it is a *rendering/feel* defect and this probe measures outcomes. If the
   geometry agent wants it gated, it belongs in `_probe_sim_quality.gd` beside the blob verdicts.

---

## 6. Determinism, and what was and was not touched

- The probe draws **no rng of its own**. Every roster is name-sorted pool slices and constant
  stat blocks; every fight is `Sim.setup(seed, ...)` off the fixed `SEEDS` list. Two runs print
  identical numbers or something in the sim moved.
- **No shared file was edited.** `_probe_balance.gd` and `_probe_balance.tscn` are new; nothing
  in `scripts/sim/`, `scripts/ai/`, `spatial.gd` or `data/` was touched. `./run_contract.sh`
  **PASSES** (62 + 46 + 31 + 34 + 46 cases, 17 tables). `_probe_ladder_slope` and `_probe_shape`
  cannot have moved and were not re-run — nothing this round is in their dependency chain, and
  a green run from them would not have been evidence of anything either way (round 23's
  correction).
- `SAVE_VERSION` untouched. No addons. `data/*.json` read-only.
