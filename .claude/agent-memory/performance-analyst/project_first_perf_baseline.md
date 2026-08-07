---
name: project-first-perf-baseline
description: The first real Godot performance baseline exists (2026-08-04) — what it covers, and the two changes already known to invalidate parts of it
metadata:
  type: project
---

`docs/PERFORMANCE_BUDGETS.md` (2026-08-04) is the first MEASURED performance baseline for the
Godot arena — before this, `.claude/docs/technical-preferences.md` explicitly said budgets were
"unset, pending first profile." Measured on Windows 11 / RTX 5080 / D3D12 / Forward+ / Godot 4.7.1
at 1280×800, using `_perf_probe.gd` ([[reference-perf-probe-harness]]).

**Headline measured numbers** (see the doc for full detail and the measured-vs-extrapolated
split): sim-only 5v5 wall time ~133ms mean over a real fight (15-40s of sim time observed); real
heap frame-stream cost ~12.4 KB/frame (not the naive ~600 byte payload guess — GDScript
Dictionary/hash overhead dominates); render mid-fight mean 11.05ms/frame (90.5fps), draw calls
mean 592/max 639, video mem 257MB / texture mem 84MB, covering only 12 of 65 species and 5 of 11
leagues' art.

**Why this baseline will go stale fast, and what to check before trusting it again:**
1. **The leash (`spatial_sim.gd:_apply_leash`) is being removed** — every number above is of the
   CURRENT clustered fight (units pulled to 24-42% of board width). Once units use the full
   160×88 ground, draw-distance/culling/camera-framing all get worse, and this baseline
   understates it.
2. **Real pathfinding is landing** (~10 agents, per-tick navmesh queries — the determinism spike
   landed on Godot's own navmesh, reproducible across 5 processes per the coordinator). This is a
   SIM-side cost (the sim runs headlessly to completion before playback starts), so it eats into
   the loading-pause budget (proposed ≤1.5s at the 1800-tick worst case, ~0.58s of headroom over
   the measured baseline), not the 60fps render budget. Nothing has measured what a navmesh query
   actually costs yet — that's the single biggest open unknown in the doc.

**Named finding, not yet fixed by me (recommended to `engine-programmer`):** the biggest current
render cost is the venue's own static geometry (4 walls + 20 stand-tier boxes + obstacles) built
as unbatched individual `MeshInstance3D` nodes with per-node `material_override` — a
`MultiMeshInstance3D` candidate that would cut draw calls without touching gameplay.

Re-run `_perf_probe.gd` and update the doc once the leash removal and pathfinding land — do not
quote these numbers as current after either ships.
