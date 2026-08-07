---
name: reference-perf-probe-harness
description: Where the Godot performance-probe harness lives, what it can do, and the --script/autoload compile-order trap it exists to work around
metadata:
  type: reference
---

`monster-tamer/scripts/_perf_probe.gd` is a throwaway `SceneTree`-script harness for measuring
the Godot side (not part of `run_contract.sh`'s contract suite). Two modes, both verified working
2026-08-04:

- `-- sim` (headless): `P:/Godot_v4.7.1-stable_win64.exe --headless --path monster-tamer --script res://scripts/_perf_probe.gd -- sim`
  — times `SpatialSim.run()` directly across team sizes, plus a real-heap frame-stream memory
  measurement (batch of fights, `Performance.MEMORY_STATIC` delta with all `frames` arrays kept
  alive).
- `-- render` (windowed, needs a real GPU/display — worked fine headfully on this dev box):
  `P:/Godot_v4.7.1-stable_win64.exe --path monster-tamer --resolution 1280x800 --script res://scripts/_perf_probe.gd -- render`
  — boots the real `arena3d.tscn`, waits 10 real seconds past the opening hold, samples frame
  time/draw calls/primitives/VRAM for 3 more seconds.

**The trap the harness's header comment documents in full:** under `--script`, the engine's
normal autoload boot (Art/GameData/Career/Roster/SaveGame) DOES still run and DOES add nodes to
`/root` — but a **script-level** `const X = preload(...)` of anything that bare-references an
autoload (`monster_instance.gd`'s `assign_moveset()` calls `GameData.class_lines`) compiles too
early, before those autoloads are registered as GDScript globals, and fails with "Identifier not
found: GameData". This is a genuine ordering race specific to `--script` mode, confirmed
empirically (not just per the existing note in `.claude/docs/technical-preferences.md`, which only
says autoloads are "not available" without explaining why one probe — `_selftest_spatial.gd` —
appears to get away with preloading `monster_instance.gd` directly: it never calls
`assign_moveset()`, so the broken code path is never hit).

**The fix, proven working:** never top-level-`preload()` `monster_instance.gd`/`spatial_sim.gd`
if anything downstream calls `assign_moveset()`. Instead `load()` them from inside a function,
deferred to `_process()` frame 2 or later (by which point the real autoload boot has completed),
and reach other autoloads via `root.get_node_or_null("/root/GameData")` (a runtime path lookup)
rather than a bare identifier.

**Also found:** `Performance.TIME_FPS`/`TIME_PROCESS` do not refresh per-frame on this custom
`SceneTree` main loop — they returned one constant value across an entire sampling window.
Measure frame time yourself via `Time.get_ticks_usec()` deltas between `_process` calls instead;
`RENDER_TOTAL_DRAW_CALLS_IN_FRAME`/primitives/memory monitors were fine.

See `docs/PERFORMANCE_BUDGETS.md` for the numbers this harness produced.
