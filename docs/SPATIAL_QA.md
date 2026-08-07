# Spatial QA — stream G findings

**2026-08-04.** Stream G · QA / determinism, per `docs/SPATIAL_HANDOFF.md`. Owns
`monster-tamer/scripts/_spatial_test.gd` and this file only — **findings are reported here, not
patched in production code.**

Run the harness: `P:/Godot_v4.7.1-stable_win64.exe --headless --script res://scripts/_spatial_test.gd`
(from `monster-tamer/`). Exit code is the result, same convention as `run_contract.sh`.

---

## State of the fan-out at time of this pass

Of the six streams in the handoff, **only `scripts/spatial.gd` (the shared contract, owned by
the coordinator) has landed.** `spatial_sim.gd` (stream A), `spatial_ai.gd` (stream B) and
`arena_layout.gd` (stream C) do not exist yet. `scripts/ui/arena_3d.gd` and `scenes/arena3d.tscn`
(stream D) exist but were out of scope for this pass — they consume the frame stream, which
nothing produces yet.

This QA pass is therefore **Tier 1 and Tier 2 only** — everything that can be verified against
what has actually landed. Tier 3 (determinism, full-fight invariants, the out-of-reach-ticks
measurement, spatial-vs-non-spatial comparison) is written, wired to detect its own dependencies,
and reports **SKIPPED** rather than being silently omitted. **Re-run this harness the moment
`spatial_sim.gd` lands — Tier 3 is the headline test and it has not run yet.**

---

## 1. Determinism verdict: NOT YET TESTABLE

There is no `SpatialSim.run()` to test — determinism is a property of the fixed-step simulation
loop, and that loop does not exist yet. `spatial.gd` itself is trivially deterministic (every
function is pure, no RNG, no I/O), which the Tier 1 pass confirms indirectly (same inputs
produced the same outputs across two separate process invocations, incidentally, since the whole
harness was run twice during this pass).

**What Tier 3 will do the moment `spatial_sim.gd` lands**, already built and waiting in
`_spatial_test.gd`:
- Run the same seed + same orders twice **in-process**, compare the full `frames` array with
  `frames_equal_strict()` — bit-exact, not `is_equal_approx`. The self-test
  `frames_equal_strict: epsilon drift is NOT tolerated` (Tier 2) proves this comparison actually
  rejects sub-epsilon drift rather than silently passing it, which a naive `==` on floats loaded
  from two independent runs would not.
- Run it again **across two separate `godot --headless` process invocations** (self-invoke via
  `OS.execute`, hash or directly diff the two `frames` dumps) — the cross-process half of the
  acceptance test HANDOFF §1 specifies. Not yet wired; the exact dump/compare mechanism is a
  five-minute addition once there's a real `frames` array to dump.

## 2. Existing contracts: PASS, unmoved

```
cd monster-tamer && ./run_contract.sh
```

`combat(62) derive(46) status(31) tick(34) classify(46)` = **219/219**, plus `data.json`'s 16
structural checks. Confirmed passing at the start of this QA pass (before `_spatial_test.gd` was
written) and the tree has had no production-code changes since — nobody has touched the six
contract-owning modules. **Re-run after every stream lands**; this file does not re-run it
automatically because it is a separate acceptance test with its own script, and conflating the
two would make a spatial-layer failure look like a contract regression or vice versa.

## 3. Spatial invariants — Tier 1 (spatial.gd pure functions): 1 failure, 15 pass

All sixteen checks are in `_spatial_test.gd`'s `_tier1_pure_invariants()`. Full run:

```
── TIER 1: spatial.gd pure-function invariants ──
  ok    ground_scale anchors
  ok    ground_size ratio constant 40:22
  ok    ground_size monotonic in team_size
  ok    deploy separation independent of ground width
  ok    deploy positions stay in ground bounds
  ok    clamp_to_ground never escapes bounds
  ok    reach_of respects hard min/max
  ok    reach_of scales authored (non-basic) ranges by REACH_SCALE
  FAIL  ⚠️ DEFECT: class-basic reach differentiates by channel
  ok    minimum_range: zero for basics and short ranges
  ok    step_len: backpedal strictly slower than advance
  ok    step_len: closing bonus only applies advancing + out of reach + far
  ok    cover_between: grade -> penalty / blocked mapping
  ok    cover_between: blocking wins regardless of obstacle order
  ok    is_flanking: requires both an engager and melee range
  ok    segment_hits_rect: basic geometry sanity
```

### ⚠️ SQA-001 (S2-Major) — every class's basic attack has the same reach, regardless of channel

**Repro** (also encoded as `_check_reach_basic_differentiation()` in the harness — deterministic,
seed-free, reproduces every run):

```gdscript
const Spatial = preload("res://scripts/spatial.gd")
Spatial.reach_of({"range": 3.0, "channel": "melee"},   true)  # -> 9.6
Spatial.reach_of({"range": 8.0, "channel": "ranged"},  true)  # -> 9.6
Spatial.reach_of({"range": 7.0, "channel": "magic"},   true)  # -> 9.6
Spatial.reach_of({"range": 6.0, "channel": "support"}, true)  # -> 9.6
Spatial.reach_of({"range": 6.0, "channel": "voice"},   true)  # -> 9.6
```

All five channels collapse to the identical **9.6**. For comparison, the same ranges through the
non-basic (`is_basic=false`) path — i.e. the treatment an authored move gets — correctly spread
across **12.0 / 32.0 / 28.0 / 24.0 / 24.0**.

**Root cause**, in `spatial.gd:reach_of()`:

```gdscript
static func reach_of(move: Dictionary, is_basic: bool = false) -> float:
	var r: float = float(move.get("range", 0.0))
	if r <= 0.0:
		r = float(CHANNEL_RANGE.get(move.get("channel", "melee"), 12.0))
	elif not is_basic:
		r *= REACH_SCALE          # <-- skipped when is_basic == true
	return clampf(r, HARD_REACH_MIN, HARD_REACH_MAX)
```

`data.json`'s `classBasic` table authors class-basic ranges as **3 (melee) / 6 (voice/support) /
7 (magic) / 8 (ranged)** — the same values `CLAUDE.md`'s Battle sim section documents ("melee
3.0 · ranged 8.0 · magic 7.0 · support 6.0"). Those numbers live on the **old 40×22 scale**,
exactly like every other authored range — the comment directly above the `elif` even says so
("Authored ranges live on the pool's ORIGINAL 40×22 scale; lift them to the new ground"). But the
`elif not is_basic` guard means a class-basic call (`is_basic=true`) skips that lift. All four
raw values (3/6/7/8) sit below `HARD_REACH_MIN` (9.6), so every one of them clamps to the same
floor — the channel information is destroyed before it ever reaches the caller.

**Why this matters, not just as a unit-test nit:** `docs/SPATIAL_HANDOFF.md` states plainly, "A
unit may only act when the target is inside `Spatial.reach_of(move)` — reach gating is the entire
point of the exercise." `CLAUDE.md`'s Battle sim section carries the TypeScript history of this
*exact* bug being found and fixed **twice already** — first as a general "derived from whichever
move was drafted" bug, then as a second copy in `reachOf` — with the explicit conclusion that a
ranged unit needs a ranged stand-off distance or it "got a melee basic it could never reach with."
As shipped, the Godot port has reproduced the collapsed version a third time: a Ranger's bow and a
Tank's fists resolve to the identical 9.6-unit stand-off for their free attacks. Since the free
attack is the action every unit falls back to constantly (it is the only always-available move),
this isn't an edge case — it fires on essentially every tick of every fight.

**Suggested direction** (not a decision — this belongs to the coordinator/stream A, this file
reports, it does not patch): the `elif not is_basic` guard looks like it intended to protect
against double-scaling `CHANNEL_RANGE` fallback values (which are already on the new scale), but
`classBasic`'s authored ranges are a *third* source, on the *old* scale, and the current logic
doesn't distinguish them from the fallback case. Either lift class-basic ranges the same way
authored moves are lifted, or route class-basics through `CHANNEL_RANGE` instead of trusting
`classBasic`'s raw numbers — but not the current "skip the lift because it's a basic" branch,
which discards exactly the reach differentiation `classBasic` exists to express.

Every other Tier 1 check passed, including the deploy-separation invariant that the design
explicitly calls out as previously-broken-and-fixed (`ARENA_BLUEPRINT §2` — separation is flat at
33.1 units across every team size, confirmed for 1 through 6), the backpedal asymmetry
(`BACKPEDAL_MULT` = 0.60, confirmed as a strict ratio, not just "slower"), and cover-grade
resolution (blocking beats hard beats soft, order-independent).

## 4. The invariant-checker library — proven before trusted (Tier 2)

Six checkers are built and ready to point at real `SpatialSim.run()` output the moment it exists:
`check_ground_bounds`, `check_no_teleport` (the 2.0-unit-per-tick tripwire, with the TS
`spatial.test.ts` teleport precedent named directly in the code comment), `check_body_separation`,
`check_hp_mp_bounds`, `check_termination`, and `frames_equal_strict` (the determinism comparator).

Per this project's own QA doctrine — "fixtures must pin the variable under test" — each checker
has a paired synthetic fixture: one clean fixture that must pass, one broken fixture built to trip
*exactly* that checker and no other. All twelve Tier 2 self-tests passed, meaning: when
`spatial_sim.gd` lands, these checkers can be trusted to fire on a real violation and stay quiet
on a clean run, rather than that trust being asserted for the first time against production code.

## 5. Not yet measurable: out-of-reach-ticks, reach-gating, spatial-vs-non-spatial

Three things the task explicitly asked for could not be produced this pass, because all three
need a running `SpatialSim`:

- **The out-of-reach-ticks fraction** — the direct evidence for whether the chase problem
  (`ENGAGEMENT_DESIGN.md`'s measured 76%-out-of-range pursuit equilibrium) is solved by
  `BACKPEDAL_MULT`/`CLOSING_BONUS`. Cannot be measured without a fought match to sample frames
  from.
- **Reach-gating verification** — confirming no shot's `fromId`/`toId` distance in the frame
  stream exceeds `Spatial.reach_of()` for the move used. Same blocker. Once `spatial_sim.gd`
  lands, note that SQA-001 above will make this check nearly meaningless for basic attacks
  specifically — every basic will "pass" a 9.6-unit gate uniformly, which is not the same as the
  gate being *correct*. Fix SQA-001 first or this check will rubber-stamp the bug.
- **Spatial vs. non-spatial outcome comparison** (`battle_sim.gd` as control) — needs a spatial
  fight to run alongside the existing non-spatial one. Per the standing rule, this comparison is
  **not pass/fail** — the balance baseline is suspended and outcomes are expected to differ now
  that reach and movement exist. It will be reported as a measurement for a future re-baseline,
  not a verdict.

## 6. Summary for the next QA pass

| item | verdict |
|---|---|
| Determinism (frames, in-process) | NOT YET TESTABLE — `spatial_sim.gd` missing |
| Determinism (frames, cross-process) | NOT YET TESTABLE — same |
| Existing 219-case contract | PASS, unmoved |
| `spatial.gd` pure-function invariants | 15/16 pass — **SQA-001 open (S2)** |
| Invariant-checker library | built + self-tested, 12/12, ready |
| Ground bounds / no-teleport / body separation / HP-MP bounds / termination on a real fight | NOT YET TESTABLE |
| Out-of-reach-ticks measurement | NOT YET TESTABLE |
| Reach-gating on real shots | NOT YET TESTABLE (and will be compromised by SQA-001 until fixed) |
| Spatial vs. non-spatial outcome comparison | NOT YET TESTABLE |

**Re-run `_spatial_test.gd` as soon as any of `spatial_sim.gd` / `spatial_ai.gd` /
`arena_layout.gd` land — do not wait for all three.** Tier 3's dependency check reports each
missing file by name, so partial landings will show partial SKIP lists rather than an all-or-
nothing gate.
