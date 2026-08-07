---
name: reference-balance-tooling-locations
description: Where the existing (TypeScript) and new (GDScript) balance/performance instruments live in Monster Tamer, and the ownership rule for docs/SPATIAL_BALANCE_TOOLING.md
metadata:
  type: reference
---

**TypeScript-side balance instruments** (precedent to mirror, not to touch — legacy stack):
- `tools/sweep40.ts` — 40-matchup sweep over 10 hand-picked compositions (`tools/comps.ts`),
  reports resolved/duration/kills/dmg per composition; `--noise` mode reruns across 5 seed
  batches to report each metric's own sd (the "beat 2×sd to be believable" convention).
- `tools/ab.ts` — paired A/B: same seeded fights under two settings, verdict by sign test
  (robust to outlier fights) and McNemar's test on the binary "resolved" flip, never a pooled
  mean CI alone. `--dump`/diff-two-JSON-files workflow.
- `tools/focus.ts` — damage-concentration instrument (top share / targets-per-5s / healing
  share) that REFUTED the "focus fire is broken" assumption once run — the closest precedent
  for an instrument that surprised its own designers.
- `tools/comps.ts` — the ONE composition list both sweep40 and ab.ts must share (its own header
  warns against forking a second copy — "two harnesses fighting different teams is worse than no
  measurement").

**Godot/GDScript side** (`monster-tamer/`):
- `scripts/spatial_sim.gd` / `scripts/spatial_ai.gd` / `scripts/spatial.gd` — the current
  (pre-rewrite, as of 2026-08-04) spatial combat sim, AI/targeting, and geometry-constants
  contract. Per `docs/AUTOBATTLER_DESIGN.md` decision #32/#33 these get REWRITTEN FROM SCRATCH
  along with the frame-stream contract (adding `intent`/`reason`/`projectiles` fields,
  additive to the existing `pos`/`facing`/`hp`/`state`/`targetId`/`shots` shape documented in
  `docs/SPATIAL_HANDOFF.md` §3).
- `scripts/_selftest_spatial.gd` — throwaway determinism-check script; the working example of
  running a headless GDScript harness WITHOUT depending on the `GameData` autoload (loads
  `data/data.json` directly, builds `MonsterInstance`s by hand) — `--headless --script` does not
  reliably see `project.godot` autoloads, and every contract/harness script in this repo works
  around it the same way. Also the precedent for `preload()`-not-bare-class-name (cold script
  class cache under headless boot).
- `run_contract.sh` — the pattern for invoking a headless GDScript entry point:
  `"$GODOT" --headless --script res://scripts/<x>.gd`, `GODOT` defaulting to
  `P:/Godot_v4.7.1-stable_win64.exe`.

**My deliverable**: `docs/SPATIAL_BALANCE_TOOLING.md` — the metric set + harness design for
judging whether the rewritten spatial AI actually fixes "the blob" (task from 2026-08-04). I own
this file exclusively; did not write any `.gd` harness code (that's implementation, for whoever
picks up the build — this was instrumentation DESIGN only, per the task's explicit scope).
