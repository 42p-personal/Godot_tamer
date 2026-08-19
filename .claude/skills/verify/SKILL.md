---
name: verify
description: "Run the Monster Tamer build verification battery — port contracts, compile walk, the career loop, the sim battery and the window-only probes — in the right order, and report PASS/FAIL honestly. Use before every commit, after every fan-out round lands, and any time someone asks whether the build is green. Also use when a probe reports red and you need to know whether it is a real failure or an invocation mistake."
argument-hint: "[quick | full | sim | ui]"
user-invocable: true
allowed-tools: Bash, Read, Glob, Grep
model: sonnet
---

# Verify

The standing verification battery for the Godot build. Run it before every commit.

**Engine:** `P:/Godot_v4.7.1-stable_win64.exe` · **Project:** `G:/p42.uk/monster-tamer-3d/monster-tamer`

If the binary is missing, `run_contract.sh` exits **127** and every probe fails identically.
That has happened — the binary was deleted mid-round and a whole round was written blind. Check
the binary first and say so plainly rather than reporting a battery of failures.

---

## ⚠️ THE TRAP THAT HAS COST THIS PROJECT TWICE

**Nine probes MUST run with a window. Under `--headless` the dummy renderer returns blank
frames, so they save black rectangles and either PASS on nothing or fail for the wrong reason.**

```
_probe_house  _probe_screens  _probe_watch  _probe_watch_scrub  _probe_report_graded
_probe_clock  _probe_ending   _probe_econ   _probe_read_shot
```

Each says so in its own header. Two "red probes" reported in round 21 were headless invocations
of these — the code was fine. **Before reporting any probe red, check whether it is on this list
and whether you ran it correctly.**

The inverse also holds: anything needing a navmesh or real nodes runs as a **scene**; anything
needing neither `extends SceneTree` and runs with `--script`. A `Node`-based script run with
`--script` pops a **blocking modal** that hangs an automated run rather than failing it.

---

## Modes

- `quick` — contracts + compile + career loop. ~3 min. Use while iterating.
- `full` (default) — everything below.
- `sim` — contracts + compile + the sim battery + determinism. Use after any `scripts/sim/*` or
  `scripts/ai/*` change.
- `ui` — contracts + compile + career loop + the windowed set. Use after any `scripts/ui/*` change.

---

## Phase 1 — The gates (always, in this order)

```bash
cd G:/p42.uk/monster-tamer-3d/monster-tamer
./run_contract.sh
"P:/Godot_v4.7.1-stable_win64.exe" --headless --path . --script res://scripts/_probe_compile.gd
```

`run_contract.sh` asserts **exact equality** against TypeScript: 62 combat + 46 derive + 31
status + 34 tick + 46 classify cases and 17 data tables. It is not statistical — any diff is a
real translation error.

`_probe_compile` WALKS the tree (it does not name files by hand — that version missed most of
what a round changed) and fails if the walk finds fewer than 30 files, so it cannot silently
stop seeing the project.

**If either fails, stop and report. Nothing downstream is meaningful.**

## Phase 2 — The player's route

```bash
"P:/Godot_v4.7.1-stable_win64.exe" --headless --path . scenes/_probe_career_loop.tscn
```

173 checks. It walks title → town → market → stable → training → advance week → feeding →
tournament → tactics → report → save/load, and it exists because `deployment_board.gd` had
never compiled since the initial commit while every other probe stayed green over it. **This is
the probe most likely to break on a UI round.**

## Phase 3 — The sim battery (headless is correct here)

```
_probe_sim  _probe_sim_quality  _probe_layout  _probe_arena_switch  _probe_balance
```

## Phase 4 — Determinism (only if `scripts/sim/*` or `scripts/ai/*` changed)

Determinism is an absolute contract, and **in-process checks cannot catch hash-order
dependencies** — run three SEPARATE processes and diff:

```bash
for i in 1 2 3; do
  "P:/Godot_v4.7.1-stable_win64.exe" --headless --path . scenes/_probe_sim_quality.tscn 2>&1 \
    | grep -oE "[0-9]{6,}\|[AB]" | md5sum
done
```

All three hashes must match. `_probe_arena_switch` run three times is the second receipt (it
drives the real battle screen). Ignore Godot's `ObjectDB instances were leaked at exit` warning
— that is engine teardown, not sim state.

## Phase 5 — The career battery (headless)

```
_probe_savecompat  _probe_grade  _probe_terminal  _probe_training  _probe_assign
_probe_integrate   _probe_breed  _probe_recruit   _probe_archetypes
_probe_ladder_slope  _probe_sawtooth  _probe_career_arc  _probe_gold_wall
```

⚠️ `_probe_ladder_slope` and `_probe_shape` run on **`battle_sim.gd`, not the spatial sim** —
verified by grep. A green run from them is a regression check, **not** a safety proof for a
`sim.gd` change. Say so when you report them after sim work.

## Phase 6 — The windowed set (NO `--headless`)

```bash
"P:/Godot_v4.7.1-stable_win64.exe" --path . scenes/_probe_house.tscn
"P:/Godot_v4.7.1-stable_win64.exe" --path . scenes/_probe_screens.tscn
"P:/Godot_v4.7.1-stable_win64.exe" --path . scenes/_probe_report_graded.tscn
"P:/Godot_v4.7.1-stable_win64.exe" --path . scenes/_probe_perf.tscn
```

`_probe_report_graded` is **slow, not broken** — it drives real fights and can exceed a 400s
timeout. Give it the full budget before calling it red.

`_probe_house` is the authoritative UI unit and enforces: off-scale rendered labels, off-token
colours, labels below the 14px floor, silent-disabled controls, nested scrolls, clipping, nine
craft contrast floors, and **G1 — every rendered glyph must exist in the packaged font**.

---

## Reporting

Report each probe with its exit code. Then:

- **If everything passed**, say so plainly with the headline numbers (contracts PASS, career
  loop N/0, determinism identical ×3).
- **If something failed**, quote the failing line. Do not summarise a failure as "mostly green".
- **If a probe was red because you ran it wrong**, say that — it is a different fact from a
  broken build, and this project has twice reported the first as the second.

⚠️ **Known and pre-existing:** nothing currently. The battery has no red probe. If you find one,
establish whether it is new by `git stash`-ing the working tree and re-running at HEAD before
attributing it to the current change.
