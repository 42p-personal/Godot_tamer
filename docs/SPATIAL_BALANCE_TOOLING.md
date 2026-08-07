# Instrumenting the anti-blob rework — the measurement, not the fix

**2026-08-04.** Owner: `performance-analyst`. This document designs how we will know whether
the behaviour-tree AI (`docs/AUTOBATTLER_DESIGN.md`) actually fixes the blob. **It ships no
code and changes no tuning.** The balance baseline is suspended (`CLAUDE.md`) and this is not
an exception to that — it is the instrument that will make a *future* re-baseline honest.

⚠️ **A metric that cannot distinguish anything is worse than none, because it looks like
evidence.** `resolved` is already documented at ceiling (sd 0.00, `CLAUDE.md`); this project
has form on shipping a dead gauge and reading it as a working one. Every metric below is rated
for exactly that risk before it is recommended.

---

## 0. What "the blob" is, precisely, so we measure the right thing

`docs/AUTOBATTLER_DESIGN.md` §5 names five causes. Nothing here should be read as "the blob
metric" singular — it is five separate failure modes, and a fix for one can leave the others
untouched while an unweighted average hides that.

| # | cause (§5) | primary instrument below | ships today? |
|---|---|---|---|
| 1 | every unit runs the same utility function | branch-entropy (§3.1) | ⚠️ no — needs the tree's `intent` field |
| 2 | all converge on one shared focus | target-sharing rate, target-switch rate (§3.2) | ✅ yes — `targetId` is in the frame stream today |
| 3 | no lateral goals | polarization, normalized pairwise distance, hull area (§2) | ✅ yes — positions are in the frame stream today |
| 4 | no reason to hold ground | contact-time spread, advance/retreat state mix (§2.4) | ⚠️ partially — state exists, but is a movement *fallback* today, not a `hold`/`guard` decision |
| 5 | deployment is a narrow line near centre | deploy-band width used | ⚠️ no — current deploy is a fixed formula, no player/AI decision to measure yet |

Two of five causes (branch entropy, deploy width) cannot be measured until later pieces of the
rework ship. That is stated honestly in §6, not smoothed over — building the other three now is
still worth doing, and doing it now against the **current, pre-rewrite** sim gives the rework a
real "before" number instead of a second suspended baseline.

### The approach/engaged split — read this before any metric below

The complaint is specifically about **monsters moving to a central area**. That is an
*approach-phase* phenomenon. Every spatial metric below must be reported in **two windows**,
never pooled:

- **Approach**: deploy (`t=0`) → first contact (first `shots` entry in the frame stream, i.e.
  first attempted hit/cast between opposing sides — use `shots`, not the text `log`, see the
  trap noted in §2.5).
- **Engaged**: first contact → end of fight (or first death, per metric — noted individually).

Pooling the two hides exactly the thing being tested. A tree AI that spreads out beautifully
during combat but still marches to the board's centre as one mass before the first swing would
score "fixed" on a pooled number and "not fixed" on the approach window alone — and the approach
window is the one the user's own words describe.

---

## 1. Data source

Everything below reads the frame stream defined in `docs/SPATIAL_HANDOFF.md` §3 (current) /
`docs/AUTOBATTLER_DESIGN.md` §12 (the redesigned successor, additive — `intent`/`reason`/
`projectiles` are new fields, not replacements). Concretely, per fight:

```
result.frames[i] = { t, units: [{id, pos, facing, hp, mp, alive, state, statuses, targetId}, ...],
                      shots: [{fromId, toId, kind, hit, dmg, crit, move}, ...] }
```

⚠️ **Prefer `frames[i].shots` over `result.log` for identity.** The text log
(`spatial_sim.gd:_log_event`) keys attacker/target by `species_name` — which collides the
instant a composition fields two of the same species, a real possibility in this game's
5v5 rosters. `shots` already carries stable numeric `fromId`/`toId`. Any instrument built
against the log instead of `shots` will silently mis-attribute contact events on mirror or
near-mirror comps, and nobody will notice until a comp with a duplicated species produces a
nonsense number.

---

## 2. Blobbiness metrics — is the team moving as one mass?

### 2.1 Polarization (trust: HIGH — see §6)

Borrowed from collective-motion / flocking literature, and the metric I'd lean on hardest of
the purely-spatial ones. At each tick with at least two living, moving allies on a side:

```
v_i = normalize(pos_i(t) - pos_i(t - DT))         # per-unit heading, this tick
P(t) = |mean_i(v_i)|                               # magnitude of the average heading, 0..1
```

`P(t) = 1.0` means every living unit on the side is walking in exactly the same direction this
tick — the herd signature named in the complaint. `P(t) → 0` means units are moving in
genuinely different directions — which is what `wings`/`dive`/`hold`/`guard` are *supposed* to
produce if they work.

Report **mean P over the approach window** as the headline number (this is precisely "moving to
a central area" made numeric) and mean P over the engaged window as a secondary read.

**Why I trust it:** it needs no arena-scale normalization (already bounded 0..1 by
construction, unlike raw distances which must be divided by a `ground_scale`-dependent
constant to be comparable across team sizes), and it is a direct read of *direction* diversity,
which is what "free will" in movement actually means — two units standing far apart but walking
in lockstep are still herding, and pairwise-distance metrics (below) cannot see that; polarization
can.

**Known blind spot:** it measures direction only, not target choice. A side can have low
polarization (everyone walking a different way) while all five have privately picked the same
target and will collide on it anyway — that is what §3 (target-sharing) is for. Read the two
together; neither substitutes for the other.

### 2.2 Normalized mean pairwise ally distance (trust: MEDIUM)

```
D(t) = mean over all living-ally pairs (i,j) of |pos_i(t) - pos_j(t)|
D_norm(t) = D(t) / Spatial.usable_radius(team_size)
```

Simple, cheap, intuitive as a headline "how spread out is the team" number, and precedented
(`tools/ab.ts`'s `travel` guard rail already tracks per-unit movement in the same spirit).
Normalizing by `usable_radius(team_size)` — not raw ground width — is required: the ground
itself scales with team size (`Spatial.ground_scale`), so an un-normalized distance would
conflate "bigger team, bigger board" with "more spread out."

**Blind spot, stated plainly:** two tight two-unit sub-clumps standing far apart score exactly
the same `D` as one loose five-unit clump if the mean works out the same — the metric is blind
to *shape*, only sees the average gap. That is what convex hull area (§2.3) is for.

### 2.3 Convex hull area (trust: MEDIUM-LOW, secondary only)

```
H(t) = area(convex_hull(living ally positions)) / (π × usable_radius(team_size)²)
```

Complements 2.2 by capturing footprint shape, not just average gap. **Recommended as a
secondary chart, not a primary gate**, for two reasons specific to this game's team sizes:

- At n≤2 living units it is degenerate (a line has zero area) — happens constantly late in a
  5v5 fight as units die, which is exactly why it must be windowed to the *approach* phase
  where team size is still full, never averaged across the whole fight.
- At n=5 it is a small-sample statistic and highly sensitive to a single outlier: one flanking
  unit inflates hull area a lot, which can misreport "4 of 5 are still clumped, 1 wandered off"
  as "team is spread out." Report alongside 2.2 so the two can be read against each other, never
  alone.

### 2.4 Contact-time spread — does the fight collide at once, or stagger in? (trust: MEDIUM)

For every cross-team pair `(i, j)` that ever appears together in a `shots` entry (either
direction), take `contact_time(i,j)` = the `t` of that pair's *first* `shots` entry. Then:

```
contact_mean = mean(contact_time over all pairs that ever fought)
contact_sd   = stdev(contact_time over all pairs that ever fought)
```

**Low `contact_sd` clustered right after a low `contact_mean`** is the literal signature of "a
wall of monsters collides in the centre all at once." **Higher `contact_sd`** means different
pairs engage at different times — staggered, which is what a spread deployment plus
`wings`/`dive` positional intents should produce (some pairs meet early on a flank, others meet
late as a diver reaches the back line).

This is the metric most directly built *for* this rework and least precedented elsewhere in the
codebase — flagged honestly as more speculative than 2.1/2.2 until it has been run once and its
own noise characterized (§6 covers why: small team sizes have few pairs, so `contact_sd` will be
a very noisy statistic at anything below 5v5).

### 2.5 Deliberately NOT recommended as a primary metric: arena-area occupancy

Candidate: discretize the usable circle into a grid, mark cells visited by any unit over the
whole fight, report `visited / total`. **Decoration, not instrument.** It is dominated by
whichever single unit travels farthest (a lone diver can inflate "coverage" while four allies
never leave the centre — the opposite of what the number would suggest), it needs an arbitrary
grid resolution choice with no principled way to pick one, and it says nothing about whether the
*team* used the space together or one straggler happened to. Worth a one-line sanity check
("did the fight leave the middle third of the map at all, yes/no") but not a tracked trend line.

### 2.6 Not yet buildable: deployment-band width used

`docs/AUTOBATTLER_DESIGN.md` §5 calls deployment width "the cheapest and most under-rated" fix.
It is not a metric this instrument can produce yet: `Spatial.deploy_positions()` is a fixed
formula (`band = min(g.y - 6, team_size * 6)`) with **no decision in it** — nothing to compare
against a "better" version until free-placement formations (decision #1) actually ship. Once
they do, this becomes a real, high-trust, cheap metric: `deploy_y_range / ground.y`, before vs.
after. Listed here so it is not forgotten, not because it is buildable today.

---

## 3. Free-will / variety metrics — do monsters actually decide differently from each other?

### 3.1 Behaviour-branch entropy (trust: HIGHEST once available — see the caveat)

`docs/AUTOBATTLER_DESIGN.md` §9 makes the active tree branch **the explanation by design** —
"`Combat → Engage → Path to target` is already a readable intent string." That means once the
redesigned frame stream ships `intent` per unit per tick (§12), this is the single most direct
read of "free will" available, because it is not a proxy for the decision, it *is* the decision:

```
# per side, per tick, over living units:
H(t) = -sum_over_distinct_intents( p(intent) * log2(p(intent)) )     # Shannon entropy, 0..log2(5)
```

`H(t) = 0` means every living unit on a side is on the identical branch this tick — one utility
function wearing five bodies, cause #1 in §5's table, made numeric. Higher entropy means units
are genuinely doing different *kinds* of things at the same moment.

A second, complementary read: **per-unit branch-visit count over the unit's whole life** —
too low (a unit that visits one branch and never leaves) says "stuck," too high/rapid says
"thrashing" (see the two-sided warning on target-switching below; the same shape of problem
applies to branches).

**⚠️ Not buildable against anything that exists today.** `spatial_sim.gd`/`spatial_ai.gd` are
explicitly being rewritten from scratch and the frame stream redesigned specifically to carry
this field (decision #33) — there is no `intent` string anywhere in the current port. This is
listed first because it will likely **obsolete or subsume** several of the positional proxies in
§2 once it exists (a `wings` branch literally being taken is a better signal than inferring
"lateral movement" from position deltas) — but until then it does not exist, and pretending a
proxy is the real thing would repeat exactly the mistake this document exists to avoid.

### 3.2 Target-sharing rate (trust: MEDIUM-HIGH, buildable today)

```
share(t) = (n - distinct_targets_at(t)) / (n - 1)     # 0 = everyone picks someone different
                                                        # 1 = everyone picked the SAME target
```
averaged over living units with a `targetId != -1`, per side, per tick, over the engaged window
(meaningless before contact — nobody has a target yet).

⚠️ **Must be reported PER TACTIC-VARIANT, never pooled.** `tactics.gd`'s `manmark`/`tanks`
priorities and the current `spatial_ai.gd`'s `team_focus()` are **designed** to pull toward a
shared target — `choose_target()`'s docstring says outright that `manmark`/`tanks` are "honoured
unconditionally, with no reachability override." A sweep that mixes those orders in with the
default read will show elevated sharing that is *working as intended*, not a bug. Bucket by
which `targetPriority` was in effect before reading this number, exactly the way `tools/ab.ts`
breaks its verdict down `byComp` rather than trusting one pooled figure.

### 3.3 Target-switch rate (trust: MEDIUM, two-sided — no target number, see below)

```
switches_per_unit = count of ticks where targetId(t) != targetId(t-1) and both != -1
```
reported as a per-unit-per-second rate, distribution (not just a mean) over the engaged window.

⚠️ **Both ends of this distribution are a failure, and I will not invent the healthy band.**
`docs/AUTOBATTLER_DESIGN.md` names both directions explicitly from the reference games' own
complaint threads: TFM's "loses interest in the healer when a tank dips low" is too-high a
switch rate (no commitment — the direct reason `sticky`/`reassess` commitment and `Focus` exist
at all); "wandering in circles" / never adapting to a dead or unreachable target is too-low a
rate (tunnel vision). Report the **full distribution**, flag the two pathological extremes by
name (0 switches while the named target is dead or off-board = tunnel-vision bug, not a
tactic; switching literally every tick = thrashing, no `sticky` behaviour at all), and do not
collapse it to a single "good" mean — there isn't a principled one to name yet.

### 3.4 Cross-kit differentiation (trust: LOW-MEDIUM, sanity check more than instrument)

Does a melee unit's mean stand-off distance actually differ from a ranged unit's? (Grouping by
`m.basic_attack.channel`, mean `distance_to_target` over the engaged window, per channel.) This
mostly checks that `reach_of`/`CHANNEL_RANGE`/the class-basic table (`docs/AUTOBATTLER_DESIGN.md`
§1 decision 8, `Spatial.CHANNEL_RANGE`) is doing its job at all — a useful smoke test that the
underlying kit data differentiates behaviour, but it is closer to a regression guard than a
"did the rework help" instrument, since this should already be true under the *current* sim.

### 3.5 Future, not buildable: personality-stat correlation

Once Discipline/Nerve/Aggression/Focus exist (`docs/AUTOBATTLER_DESIGN.md` §3), the real
acceptance test for them is causal, not descriptive: does a monster's `Focus` value actually
predict its measured switch rate (3.3)? Does `Nerve` predict clean-vs-messy disengage? This is
the same "is it reachable" question `CLAUDE.md` already asks of the ability pool — a personality
stat that is authored but has no measurable footprint on behaviour is the same bug wearing a
different hat. Not buildable until the stats exist; recorded here so it is asked when they do.

---

## 4. Does the player's input matter? — the strongest test, and the one I'd trust most

This is not a metric, it's a **methodology**, and it is the highest-value thing this instrument
can produce, because it does not ask "is this number good" — a question this document
deliberately refuses to answer with invented targets — it asks a binary, falsifiable question:
**does changing the one thing the player controls change anything at all?**

### 4.1 Design, mirroring `tools/ab.ts` exactly

1. Fix a roster pair and a seed. The sim is deterministic given a seed (per
   `docs/SPATIAL_HANDOFF.md` §1's hard constraint) — the SAME fight can be re-run under two
   different tactics dicts and compared directly, exactly as `ab.ts` does for balance constants.
2. Run it twice: once under tactics setting A, once under setting B, **everything else held
   identical** (same seed, same roster, same deploy).
3. Vary **one axis at a time**: `formation: tight` vs `loose` first (it exists today), then
   `targetPriority` (`default` vs `casters` vs `tanks`), then — once built —
   positional intent (`push`/`hold`/`wings`/`dive`/`guard`) and ability policy.
4. Measure the delta, per pair, on: outcome (winner/duration/survivors — paired, exactly like
   `ab.ts`'s `dur`/`resolved` columns) **and** every trusted spatial/variety metric from §2–§3.
5. Judge with a **sign test**, not a mean CI — the same reasoning `ab.ts` and `CLAUDE.md` already
   give: a handful of fights swing wildly when they tip from timeout to a kill, which inflates
   variance and can hide a real, consistent, smaller effect. "More fights got more spread out
   than got less spread out, at p<0.05" is the actual question, and it is immune to those
   outliers in a way a pooled mean is not.
6. Run across many roster/seed pairs, not one — a single pair is exactly the "1-fight
   difference" trap `CLAUDE.md` names as a documented past mistake. Borrow `ab.ts`'s `--wide`
   pattern (run all seed batches, not just four) once a first pass suggests a real signal worth
   confirming at higher n.

### 4.2 The finding this could produce, stated as plainly as the brief asks

⚠️ **If varying tactics under an identical seed does not move outcome or the trusted spatial
metrics by more than the instrument's own noise floor (§6), the tactics system is decorative —
full stop, regardless of what any other metric says.** This is the single most important thing
this instrument could discover, and it should be the **headline** of whatever report first runs
it, not a footnote. A rework that makes movement look more organic while the player's own orders
still do nothing has fixed the wrong half of the complaint — the user's words were "tuned by the
player's input for the tactics," and if that clause is false, nothing else here matters as much.

### 4.3 Per-axis isolation

Test each tactics axis independently (formation alone, target-priority alone, once available
positional-intent alone), not just "tactics on vs off." `tools/ab.ts`'s per-composition
breakdown exists for exactly this reason — a pooled verdict across axes could hide "formation
genuinely matters, target-priority does nothing" behind an average that reads as "sort of
works." Report per-axis, the same way `ab.ts` reports `byComp`.

---

## 5. The harness

**Godot-side, GDScript, headless.** No new TypeScript tooling — the spatial layer lives in
`monster-tamer/scripts/`, and cross-engine measurement would repeat exactly the "two engines
disagree" problem `docs/TECHNICAL_ISSUES.md` already flags.

### 5.1 The `--headless --script` autoload trap, and the existing workaround

⚠️ **`--headless --script` does not reliably see `project.godot`'s `[autoload]` singletons.**
This is not hypothetical — `scripts/_selftest_spatial.gd` already hit it (its own header notes
`project.godot`'s autoload section was empty mid-edit by a concurrent stream) and worked around
it by **never depending on an autoload at all**: it loads `data/data.json` directly via
`FileAccess` + `JSON.parse_string`, and constructs `MonsterInstance`s by hand rather than going
through any autoload-mediated factory. The harness should do the same:

1. **No dependency on a `GameData`-style autoload.** Load `data/data.json` (moves) and any
   species/stat tables directly from disk inside the harness script, exactly as
   `_selftest_spatial.gd` does.
2. **`preload()`, never a bare class name**, for every script this touches (`Spatial`,
   `SpatialSim`, `SpatialAi`, `Tactics`, `MonsterInstance`, `Classify`, `Derive`). The global
   script-class cache is cold under this execution mode and during early autoload boot — already
   documented twice in this codebase (`spatial_sim.gd`'s own header, `.claude/docs/technical-
   preferences.md`) and re-verified by an actual headless run, not by inspection, both times.
3. **Entry point is a `SceneTree`-extending script with `_initialize()`**, calling `quit()` at
   the end — the pattern `_selftest_spatial.gd` and `run_contract.sh`'s target already use.
   Without the explicit `quit()` the process hangs waiting for a render frame that a headless
   run will never produce.
4. Invoke exactly like the existing contract runner: `"$GODOT" --headless --script
   res://scripts/<harness>.gd`, `GODOT` defaulting to `P:/Godot_v4.7.1-stable_win64.exe`
   (`run_contract.sh`'s own convention).

### 5.2 Compositions — align with the TS side, don't invent a second list

`tools/comps.ts`'s own header is a direct warning against what I would otherwise be tempted to
do here: *"ONE DEFINITION, TWO HARNESSES... identical today, free to drift tomorrow — and a
[measurement] that disagrees ... because the two are fighting different teams is worse than no
measurement at all."* There is currently no GDScript port of `teamTemplates.ts` — the existing
`_selftest_spatial.gd` builds two synthetic stat blocks by hand instead.

**Recommendation:** until a GDScript species/team-template port exists, use a small, explicitly
synthetic set of archetypes spanning the same range `comps.ts` spans on purpose ("composition is
a variable, not a constant") — a melee-heavy team, a caster-heavy team, a mixed team, and at
least one mirror — **at 5v5**, per `CLAUDE.md`'s "the game is a 5v5 game" doctrine and per §6's
finding below that small team sizes are close to uninformative for these specific metrics. Label
the synthetic set clearly as a stand-in, and re-point the harness at `comps.ts`'s real
compositions the moment a GDScript team-template port lands, rather than letting two divergent
composition lists become permanent (exactly the drift `comps.ts`'s own header warns about).

### 5.3 Seeds and noise

Mirror `sweep40.ts`'s seed-batch structure: a primary batch for a normal run, and a `--noise`
mode that re-runs the same (composition × tactics-variant) set across multiple seed batches and
reports the standard deviation of every metric in §2/§3. **This is not optional** — §6 below is
only trustworthy if it is backed by an actual noise run, not an estimate.

### 5.4 Output

Two modes, mirroring the TS tools:
- **Report mode** (default): a console table per composition and pooled, in the style of
  `sweep40.ts`'s output — metric means, the approach/engaged split (§0), and (when run in
  tactics-variant mode) the sign-test verdict from §4.
- **Dump mode**: write raw per-fight metrics to a JSON file via `FileAccess`, mirroring
  `ab.ts --dump`. This is what makes a **before/after comparison across the rewrite itself**
  possible: run the harness in dump mode against the *current* `spatial_sim.gd`/`spatial_ai.gd`
  now, before the rewrite lands, then again against the new tree AI once it exists, and diff the
  two JSON files with the same paired sign-test logic `ab.ts` already uses for balance constants.
  ⚠️ **This is the recommended first action** — see §7.

---

## 6. What "better" means — and where I refuse to invent a number

### 6.1 What I will defend as an acceptance criterion

- **The methodology itself**: sign test / McNemar over paired identical-seed runs, "must beat
  the noise floor" (§5.3/§6.2) — this is *process*, directly inherited from `ab.ts`/`sweep40.ts`,
  and is defensible now because it was already earned the hard way on this project (the sd-0.7
  finding `CLAUDE.md` records).
- **The tactics-matters test (§4) is a gate, not a nice-to-have.** If varying the player's
  tactics does not move outcome or the trusted spatial metrics beyond noise, that is
  disqualifying on its own, independent of how good any other number looks — this follows
  directly from the design brief's own stated goal ("tuned by the player's input"), not from an
  invented threshold.
- **A metric must move more than 2× its own measured `--noise` standard deviation to be
  believed** — borrowing `sweep40.ts`'s own stated bar ("a change must beat ~2×sd... to be
  believable") rather than asserting a fresh absolute number.

### 6.2 What I will not invent

I am not going to hand back a table that says "mean pairwise distance must exceed N units" or
"polarization must fall below 0.4." Nobody has measured what any such value *means* for a
player's perception of "does this look like a blob," and `CLAUDE.md` is explicit and repeated
that inherited or invented unjustified numbers are this project's own recurring failure mode
("a value in the codebase is evidence of what happened, never evidence that anyone decided it").
Inventing a target now would be exactly that mistake, filed under a new document instead of an
old one.

**What I recommend instead:** capture the *current*, pre-rewrite sim's metric distributions as
the reference population (§7) — not as a "good" target, only as "what blob currently measures
as" — and require the new AI to move each trusted metric in its intended direction by more than
that population's own noise, exactly the `--noise` convention above. That gives "better" a
concrete, falsifiable meaning without anyone having to guess what number feels right.

---

## 7. Recommended build order

1. **Build the harness (§5) against the CURRENT `spatial_sim.gd`/`spatial_ai.gd` first**, before
   the rewrite lands. This captures the actual "blob" baseline as data rather than as a
   description — the same lesson `CLAUDE.md`'s suspended-baseline section already teaches
   generically ("measuring against a destroyed baseline is worse than not measuring") applies in
   reverse here: not measuring the thing you're about to replace is a wasted opportunity to get
   a real before/after, and this sim is explicitly still standing right now.
2. Run `--noise` immediately after, on the current sim, so §6.2's "beat 2×sd" bar has a real
   number behind it before anyone needs one.
3. Run the tactics-matters test (§4) against the **current** sim too. It is entirely possible
   the current `spatial_ai.gd` — which already has a `team_focus`/reachability-weighted
   targeting system — makes tactics matter *somewhat* already; knowing that now sets the right
   expectation for how much the rewrite needs to move the needle, rather than assuming today's
   number is zero.
4. Once the tree AI and the redesigned frame stream ship: re-run the identical harness (§5.4
   dump mode + diff), add §3.1 (branch entropy) the moment `intent` exists, and report the
   before/after as a paired comparison, not two independent reports.

---

## 8. Summary — trust ranking and where I expect a dead gauge

| metric | trust | buildable today? | expected ceiling/noise risk |
|---|---|---|---|
| Tactics-matters paired A/B (§4) | **Highest** | ✅ yes | Low risk *as a methodology* — but a genuinely null result here is the single most important possible finding, not a instrument failure |
| Behaviour-branch entropy (§3.1) | **Highest**, once it exists | ❌ no — needs `intent` | N/A yet |
| Polarization (§2.1) | High | ✅ yes | Undefined/noisy in the first few ticks (near-zero velocity at deploy) — must exclude the pre-movement window |
| Target-sharing rate (§3.2) | Medium-high | ✅ yes | **Will read near-ceiling (~100%) whenever `manmark`/`tanks` is in effect, by design** — must never be pooled across tactic variants, exactly like `resolved` going to ceiling when pooled across a training tier that saturates it |
| Target-switch rate (§3.3) | Medium | ✅ yes | No single "good" value exists to gate on (§6.2) — report distribution, not a mean |
| Normalized mean pairwise distance (§2.2) | Medium | ✅ yes | Meaningless unless normalized by `usable_radius(team_size)`; blind to shape (two clumps read the same as one) |
| Contact-time spread (§2.4) | Medium | ✅ yes | Very noisy at small team sizes — few pairs to measure; most informative at 5v5, least at 1v1/2v2, do not average across sizes |
| Convex hull area (§2.3) | Medium-low | ✅ yes | Degenerates at n≤2 living units (common late in a fight) — must be windowed to the approach phase; outlier-sensitive at n=5 |
| Cross-kit differentiation (§3.4) | Low-medium | ✅ yes | More a regression guard on existing reach data than a rework-quality signal |
| Arena-area occupancy (§2.5) | **Low — not recommended as tracked** | ✅ yes | Dominated by a single outlier unit; grid-resolution dependent; says nothing about the team acting together |
| Deploy-band width used (§2.6) | N/A | ❌ no — no decision exists yet in `deploy_positions()` | Will read as a constant until free-placement formations ship |
| Personality-stat correlation (§3.5) | N/A | ❌ no — stats don't exist yet | N/A yet |

**The one I'd trust most, if forced to pick one:** §4, the tactics-matters paired test. Every
other metric here answers "does the fight look different" to some degree of confidence; only §4
answers the load-bearing question the whole rework is *for* — whether the player's decision
reaches the fight at all. A rework that improves every spatial number in this document while
still leaving tactics decorative would still be reporting the wrong result as success.
