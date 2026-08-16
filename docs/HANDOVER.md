# Handover — state at 2026-08-14

**Read this first in a fresh session, then `CLAUDE.md`.** Everything below is committed and
pushed. HEAD is `2823e67`.

⚠️ **THE REPO MOVED.** Work happens in `G:/p42.uk/monster-tamer-3d` on **`main`**, remote
`https://github.com/42p-personal/Godot_tamer`. The old tree at `G:/p42.uk/Monster-Tamer`
(branch `3doverhal`) is an archive — the previous handover pointed there and was eleven days
stale by the time anyone noticed. The TypeScript tree still lives inside the new repo at
`src/`, because `data/*.json` is generated from it and `run_contract.sh` copies from it.

---

## 1. The one-minute version

A stable-management autobattler. **You run a stable; the stable produces a party; the party
fights without you.** The player commits tactics and then *watches* — they never intervene.
Winning is completing Tamers Apex, the eleventh and last league.

Both halves now exist end to end and are polished: title → town → market → stable → training →
feeding → advance week → tournament → scout → tactics → arena → report → climb → ending. Every
screen is in one visual register, in a packaged font, with zero red probes.

**Nobody has ever played it.** That is the largest open item and it is item 1 in §6.

---

## 2. Verify the build in four commands

```bash
cd G:/p42.uk/monster-tamer-3d/monster-tamer
./run_contract.sh                                                   # exit code is the result
"P:/Godot_v4.7.1-stable_win64.exe" --headless --path . --script res://scripts/_probe_compile.gd
"P:/Godot_v4.7.1-stable_win64.exe" --headless --path . scenes/_probe_career_loop.tscn
"P:/Godot_v4.7.1-stable_win64.exe" --path . scenes/_probe_house.tscn      # NOTE: no --headless
```

Contracts: 62 combat + 46 derive + 31 status + 34 tick + 46 classify cases and 17 data tables,
exact equality against TypeScript. `_probe_career_loop` walks the real player route (173 checks)
and is the probe most likely to break on a UI round.

### ⚠️ Three traps that have each cost a round

**1. Window-only probes must NOT be run `--headless`.** The dummy renderer returns blank frames,
so a headless run saves black rectangles and *passes*. These nine say so in their own headers:
`_probe_house` `_probe_screens` `_probe_watch` `_probe_watch_scrub` `_probe_report_graded`
`_probe_clock` `_probe_ending` `_probe_econ` `_probe_read_shot`. Two "red probes" reported in
round 21 were headless invocations of these.

**2. Check the timestamp of any capture you read.** `_probe_screens` writes to
`user://screens/<fixture>/` (`A_comfortable`, `B_thin`). Round 20 spent three attempts "fixing"
an already-fixed bug while reading a stale PNG at a path nothing writes to any more. The probe
now sweeps its own root, but the habit is the real protection.

**3. A tree-less probe must `extends SceneTree`, not `Node`.** A Node script run with `--script`
pops a **blocking modal** that hangs an automated run instead of failing it. The inverse also
holds: anything needing a navmesh or a rendered frame must run as a SCENE. Which way a probe runs
is decided by what it needs, not by taste.

---

## 3. The fight

Rewritten clean in GDScript, WoW-arena as the explicit reference. `scripts/sim/sim.gd` +
`scripts/ai/bt.gd` + `combat_tree.gd` are canon; `scripts/ai/monster_tree.gd` carries a
SUPERSEDED banner and is dead code.

**Determinism is an absolute contract.** Fixed step `DT 0.1`, one injected RNG consumed in
unit-id order, no `randf()` or clock in `scripts/sim/*` or `scripts/ai/*`, dict keys sorted
before decision-relevant iteration. Same seed → byte-identical frames, **verified across three
separate processes** (`_probe_arena_switch`; in-process checks cannot catch hash-order
dependencies). `_probe_sim_quality` prints a per-fight frame hash so runs are diffable.

### Where it stands (rounds 23–24)

| | was | now |
|---|---|---|
| dead air inside the fight | 26.0s / 25% | 2.0s / 4% |
| enemy overlap at rest | ~40% | ~8% |
| watch scene fps | 31 | 144 |
| draw calls | 3,008 | 330 |

Round 23 found **the entire ranged game was authored, priced, and suppressed by one constant** —
kit ranges were lifted ×2.2 where the design scale is ×8.8, so the widest reach in the game
covered 6% of the walk and first shot, first blood and first contact were the same moment. The
lift is now complete and casts open during the approach.

Round 24 separated **blast radius from throw distance** (they were one number, self-centred on
the caster) and moved the body geometry as one: `BODY_RADIUS` 2.2 → 2.65, `SLOT_RADIUS` 4.8 →
5.6, `BASE_REACH` 6.6 → 7.95.

Verdict as it stands: *tense approach, readable exchange, ending still too fast on weak rosters*
(21.1s, first blood at 57%, five deaths in 3.7s).

---

## 4. The meta-game

Eleven leagues, team sizes 1/2/2/3/3/4/4/5/5/5/5, 65 species with real portraits and longform
bios, 141 moves in 18 lines, six rival archetypes with authored reads.

**The ladder is sloped and completable.** ADVANCE 66% → 13% across the rungs, 0 unclearable,
~27 cups for the whole climb. `CLIMBER_FILL_BY_LEAGUE` is an **authored curve** with a boot-time
drift check — not a measurement — and that decision paid for itself the day it was made.

### ⚠️ The finding that shapes every future meta round

**Access is invariant to skill by construction.** Promotion is a repeated Bernoulli trial with
unlimited free retries, so P(clear) = 1 for any p > 0, and only *weeks* can respond to how well
someone plays. There is exactly one terminal state in shipped code (`career.gd:won_game`);
`game_over` / `bankrupt` / `career_over` have zero grep hits.

Consequence: a competent player completes 94%, leaving **~6 points of headroom** — so any
mechanism producing more separation than that **must** produce it by lowering the naive player.
Six rounds of difficulty tuning were fighting arithmetic. The response was to **score pace**
(round 17): the ending is graded, a rival dynasty (the Varra stable) sets the standard, and the
clock is stated on four screens. It is stated; it does not yet *cost* anything.

---

## 5. The recurring failure modes

These are not abstractions. Each has a count.

**1. Authored, priced, documented — and does nothing.** 13+ instances. The whole 13-month season
rendered by nothing; the entire audio mixer wired only to a dev scene; `Generalist` with no
`classLines` entry so its kit was silently empty *forever*; `stat_cap_for` with no shipped caller
so bloodline potential did nothing; 141 ability icons used by one file; the entire ranged game
suppressed by one constant. **Grep before concluding something is missing, and equally before
concluding it works.**

**2. Instruments that lie.** A nav spike that passed on 400 empty paths; a slope probe carrying a
second copy of the model it tested; a probe measuring a player fighting with no moves; an
instrument pinned above the ceiling reading 100% everywhere; a capture harness that could only
ever photograph one screen empty, which manufactured a wrong brief. **Every probe needs a
liveness canary that exits non-zero if the thing it perturbed did not move.**

**3. A screen that lies about the thing it describes.** A scoreboard that announced the winner at
frame 0 and disagreed with the frame in 100% of frames; a stable screen promising stat ceilings
the tick never applied; a training preview hard-coding "+6 basic / +12 intensive" and ignoring
every multiplier; the same ceiling contradiction found in **three separate venues**. **Read every
number from its source.**

**4. A number quoted without its provenance.** A stale doc cost two rounds. The counter matrix
was measured at 12 trials — standard error ~14 points on a cell, ~18.6 on the gap between two
rows — and four of six rows disagreed with the instrument that produced them, while three screens
printed those numbers to the player as advice.

---

## 6. What is open, ranked

**1. Nobody has played it, and nobody has heard it.** Seven rounds have flagged this. The audio
is verified as *reaching* the player, never as sounding good — every judgement came from a
headless dummy driver. A second unchecked assumption sits on top: whether a scoreboard moves a
player who cannot lose. **One recorded session is worth more than another instrument.**

**2. The two-engine divergence, now measured and widening.** The player's watched cup fights
resolve on `sim.gd`; the ladder that prices the entire game models them on `battle_sim.gd`.
Rounds 23 and 24 each widened the gap. `_probe_ladder_slope` and `_probe_shape` **cannot see**
spatial changes — a green run from them is a regression check, not a safety proof. Converging the
engines is a design decision nobody has taken.

**3. The low-fill collapse.** 21.1s with first blood at 57% and five deaths in 3.7 seconds.
Improved from 17.4s/72%, not fixed.

**4. AoE's upside is gone, and two half-signals disagree about it.** Bursts catching ≥3 fell from
4% to 0.2%. The power-matched `caster` vs `aoe` row (identical stats, channel and powers,
differing only in `target`) drifted 5/10 → 2/10 while `melee vs aoe` drifted 8/10 → 10/10.
**Raise seeds before anyone touches AoE power** — n=10 is the sample size that has burned this
project before.

**5. The counter matrix is unmeasured.** The unsupported numbers were deleted from the prose, but
separating an 8-point gap needs 251 trials/cell ≈ 10,542 fights. The screens name a kind with no
number behind it, which is honest but incomplete.

**6. Breeding has never been measured as a design.** Flagged in round 15, still open. Best
bloodline potential reaches ×1.10, and above Gold potential is the only thing that lifts the
training ceiling.

**7. Presentation tail.** The deployment board is not yet the hero of its own screen; nameplates
orphan at 16%; the busiest second still carries 21–29 log lines; the arena's own string literals
carry uncovered glyphs (the meta UI is clean and guarded by the G1 tripwire, the arena is not
walked by it).

---

## 7. Lessons about how to run a round here

**My briefs were wrong in most rounds, and each time the agent that caught it was worth more than
the one that complied.** Recorded so the next session budgets for it:

- I said the ladder is calibrated against the spatial sim. **It is not** — the probes run on the
  other engine entirely.
- I said AoE was catching whole teams. **It catches 1.43** — the mechanism was right and the
  consequence was backwards.
- I claimed 32 cups clears the ladder. **Off by ~4×** — ADVANCE is a step function of roster
  fill, not a retryable price.
- I quoted source call-sites where the probe scores rendered labels. **They differ by 4–5×.**
- I gave a guard of "inversion mass ≤ 38.5" taken from a different instrument's metric.
- I said `recompute_class()` had six callers; there were five, **plus two files that overwrote
  the field without calling it at all**.

**So:** state where each number came from, mark the ones you did not measure yourself, and tell
agents explicitly that refuting the brief is the highest-value thing they can do. It works — it
has produced the best finding in at least five rounds.

Two structural things that also work: **a diagnosis phase that gates the builders** (it has twice
recommended stopping a round, correctly), and **one owner per file** with cross-file needs routed
through the integrator.

---

## 8. Files to know

| path | what |
|---|---|
| `monster-tamer/scripts/sim/sim.gd` | the fight — DECIDE/EXECUTE/EMIT, the determinism contract |
| `monster-tamer/scripts/ai/combat_tree.gd` | the behaviour tree; the active branch IS the explanation |
| `monster-tamer/scripts/career.gd` | ladder, field pricing, the grade, the pace-setter |
| `monster-tamer/scripts/week.gd` | the weekly tick — the one canonical path |
| `monster-tamer/scripts/ui/theme.gd` | the component library and the measured contrast floors |
| `monster-tamer/scripts/ui/arena_3d.gd` | the watch screen (5,859 lines) |
| `monster-tamer/scripts/_probe_balance.gd` | the spatial balance harness (task #32, round 24) |
| `docs/SPATIAL_BALANCE.md` | its baseline and what it can and cannot see |
| `docs/CONVERSION_DIAGNOSIS.md` | why a fight advantage does not become a career advantage |
| `docs/WATCH_AUDIT.md` | the only playtest-shaped record in the repo |
| `docs/POLISH_DIRECTION.md` | the visual craft audit and its measured floors |
| `docs/COMBAT_SPATIAL_LOG.md` | the running engineering log — read the ⚠️ before changing what it guards |
