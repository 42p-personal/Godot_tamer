# Performance Budgets — Monster Tamer (Godot 3D arena)

**Status: first real baseline, 2026-08-04.** Supersedes the "unset, pending first profile" line in
`.claude/docs/technical-preferences.md` (that file is not mine to edit — this doc is the source,
the technical director folds the numbers in). Everything below is measured on the code and scene
that exist on disk right now. Two changes are already known to invalidate part of this baseline
before it is even read — see the ⚠️ box right after the measured section. Re-run when they land.

**How this was measured:** `monster-tamer/scripts/_perf_probe.gd`, a throwaway `SceneTree`-script
harness (mine, not part of the contract suite). Two modes:
- `-- sim`: headless, times `SpatialSim.run()` directly (`--headless --script`).
- `-- render`: windowed, boots the real `arena3d.tscn` scene, waits 10 real seconds (past the
  1.5s opening hold, into the fight), samples for 3 more seconds, reads `Performance` monitors
  plus its own `Time.get_ticks_usec()` frame timer.

**Hardware/config this baseline was captured on** (record this — a budget without it is not
comparable): Windows 11, **NVIDIA RTX 5080**, D3D12, Forward+, Godot 4.7.1, window forced to
**1280×800** via `--resolution`. ⚠️ **This is high-end desktop hardware, not a min-spec target.**
Nobody has profiled this on anything else yet — treat every render number below as "best case
observed," not "what a player's machine will do."

---

## ⚠️ Two things changed after this baseline was captured — read before using it

1. **The leash is being removed.** `spatial_sim.gd:_apply_leash()` currently pulls every unit's
   desired position inside `Sp.leash_radius(team_size, spread)` of the fight's centroid — 24-42%
   of ground width. **Every measurement below is of that clustered fight.** Once the leash is
   gone, units use the full 160×88 ground. Consequences for THIS doc, not yet measured:
   - The camera's own framing math (`arena_3d.gd:_build_world`) computes its span directly from
     `Sp.leash_radius(...)` — that formula is about to describe a leash that no longer exists.
     Not my file to fix, but worth flagging: the render numbers below assume the CURRENT
     tight framing, which may itself change.
   - Obstacle density (`arena_layout.gd`) is placed in an annulus between the tight and loose
     leash radii — same dependency, same flag.
   - Draw-distance/culling gets worse (units and cover spread over more of the frustum instead of
     sitting in a packed centre), so the draw-call/primitive numbers below are a **floor**, not a
     ceiling, for the post-leash-removal game.
2. **Real pathfinding is landing** for ~10 agents on the (now larger-feeling) traversed area. Per
   the coordinator: **the determinism spike landed on Godot's own navmesh queries, verdict
   reproducible across 5 processes** — so this is being built as real per-tick navmesh path
   queries inside `SpatialSim`, not local steering. **This cost does not exist in anything I
   profiled.** See "Headroom for pathfinding" below for what the measured baseline implies is
   actually available for it.

---

## 1. Measured baseline

### 1a. Sim-only (headless, 10 Hz fixed step, `Sp.DT = 0.1`)

8 reps per team size, `GameData.make_monster` roster monsters at training level 0.5, real
`ArenaLayout` obstacles included, wall-clock via `Time.get_ticks_usec()`:

| team size | ground | mean wall time | max wall time | mean sim-ticks | mean sim-duration | wall/tick |
|---|---|---|---|---|---|---|
| 1v1 | 80×44 | 15.4 ms | 25.0 ms | 149 | 14.9s | 0.10 ms |
| 3v3 | 120×66 | 72.7 ms | 80.0 ms | 396 | 39.6s | 0.18 ms |
| 5v5 | 160×88 | 133.3 ms | 156.2 ms | 259 | 25.9s | 0.51 ms |

**This is a loading pause, not a per-frame cost** — `arena_3d.gd:_run_sim()` runs the whole fight
to completion in `_ready()`, before any playback frame is drawn. At the durations actually rolled
in this sample (15-40s of sim time), the pause is **~15-160ms — not perceptible.**

**Worst case, extrapolated from the measured wall/tick:** `SpatialSim.MAX_DURATION = 180.0` caps
every fight at 1800 ticks regardless of team size or ground size (the cap is TIME-based, not
distance-based, so it does not scale with the leash removal or a larger board). At the measured
5v5 wall/tick of ~0.51 ms: **1800 × 0.51 ms ≈ 920 ms.** Under one second, but no longer "not
perceptible" — this is the number to watch once pathfinding adds its own per-tick cost on top.

### 1b. Frame-stream memory

**Packed-payload estimate** (hand-counted bytes per field, NOT a real measurement): ~618
bytes/frame for 10 units → ~171 KB for one 28.4s/284-tick fight. **This number is wrong and I'm
including it only to show by how much:**

**Real heap measurement** — batch of 15 5v5 fights, every `frames` array kept alive (nothing
freed), `Performance.MEMORY_STATIC` read before/after:

```
reps=15  total_frames=3745  longest_fight=391 ticks (39.1s)
MEMORY_STATIC before=63.90MB  after=108.27MB  delta=44.36MB
REAL bytes/frame (10 units, incl. Dictionary/Array overhead) = 12,421
```

**~12.4 KB/frame, ~20x the naive payload estimate.** GDScript's per-`Dictionary` hash-table
overhead dominates once you have ~10 nested dicts (one per unit) inside a dict (the frame) inside
an array (the stream), and this project's frame record is exactly that shape.

**Worst-case 3-minute (180s / 1800-tick) 5v5 fight, extrapolated from the measured real
bytes/frame:** `12,421 × 1800 ≈ 21.3 MB`. **Measured-derived, not itself measured** — no single
fight in this sample actually ran to the 180s cap (longest observed was 39.1s). Not alarming in
isolation, but every fight fought this session (career mode, tournament grinding) keeps its
`result` dict around until something frees it — worth checking whether anything currently does.

### 1c. Render (windowed, 1280×800, mid-fight sample — settled 10s past the opening hold,
sampled for 3s / 270 frames)

Frame time measured directly (`Time.get_ticks_usec()` delta per `_process` call), not via
`Performance.TIME_FPS`/`TIME_PROCESS` — those two monitors returned a single unchanging value
across an entire prior 30-frame sampling window on this custom `SceneTree` main loop (min == mean
== max, exactly), i.e. they were not refreshing per call here and would have silently reported a
false constant. `draw_calls`/`primitives`/memory monitors did vary frame to frame and are trusted.

```
frame_ms   mean=11.05ms  max=18.60ms  min=6.68ms   (n=270)  -> mean 90.5 fps
draw_calls mean=591.7    max=639.0
primitives mean=10,859   max=11,723
video_mem_mb   = 257.34
texture_mem_mb =  84.16
buffer_mem_mb  =  17.44
static_mem_mb  = 113.65
object_count = 2,601   node_count = 274
```

**Against the one already-agreed figure (60fps / 16.67ms budget):** mean frame time (11.05ms) is
comfortably under budget on this hardware, but **the max sample (18.60ms) already exceeds
16.67ms, on an RTX 5080, before pathfinding, before the leash removal spreads the board, and with
only 12 of 65 species' art loaded.** That headroom is thinner than the mean suggests.

---

## 2. Proposed budgets

**Labelled by how they were arrived at. None of these are decided — they're the analyst's
recommendation for the technical director to set or reject; see the "must NOT" list in my own
role brief.**

| budget | value | basis |
|---|---|---|
| Render frame time | **16.67ms (60fps)** | **Already agreed** — the one figure with a real basis (genre norm), not mine to propose |
| Render frame time, working target | **≤12ms mean, ≤16ms p99** | **Extrapolated** from 1a's measured mean (11.05ms) — the p99 target sits deliberately below the hard 16.67ms ceiling so a moment of extra load (a big teamfight, a status VFX flourish) doesn't blow the frame outright |
| Sim precompute (loading pause) | **≤1.5s at 1800 ticks / 5v5, including pathfinding** | **Extrapolated.** Measured baseline is ~0.92s with NO pathfinding. That leaves **~0.58s of headroom** for the new per-tick navmesh queries — see §3 for what that means per agent |
| Draw calls (Forward+, this scene shape) | **≤1,500** | **Extrapolated / rule of thumb**, not measured on min-spec hardware. Current 5v5 mid-fight measured mean is 592 — real headroom exists today, but see §5 for where most of that 592 is actually coming from |
| Video memory ceiling | **≤1.0–1.5GB** | **Extrapolated.** Measured 257MB video / 84MB texture covers 12 of 65 species and 5 of 11 leagues' art. Scaling texture memory alone by (65/12) ≈ 455MB; add geometry/buffers and 1-1.5GB is a defensible ceiling to design toward, not a measured number |
| Frame-stream memory per fight | **≤30MB, or start sampling/compressing** | **Measured-derived.** Current worst case extrapolates to ~21.3MB (§1b) — 30MB gives margin without yet forcing a redesign; if pathfinding data or per-unit intent/reason strings (`docs/AUTOBATTLER_DESIGN.md` §12, the frame-stream redesign already planned) push past it, sampling is due |

---

## 3. Headroom for pathfinding — the honest answer

**On the render side:** none of this is spent on pathfinding today. Pathfinding is a **sim-side**
cost under the current architecture (`_run_sim()` completes headlessly before any frame renders),
so it does not compete with the 60fps render budget at all — it competes with the **loading
pause** budget in §2, not the frame-time budget. This is worth stating plainly because it's easy
to assume the opposite: adding pathfinding will NOT eat into the measured 11.05ms/frame render
number, unless the design later moves toward live/interactive pathfinding during playback (it
currently doesn't — the renderer replays a frozen frame stream, per `arena_3d.gd`'s own header
comment: "THIS RENDERER DERIVES NOTHING").

**On the sim side, the number that matters:** measured baseline ≈0.92s for a full 1800-tick 5v5
fight with the current nearest-enemy fallback AI. Proposed loading-pause ceiling in §2 is 1.5s.
That leaves **≈0.58s of headroom, for 10 agents, over 1800 ticks** — worked out, not measured:

```
0.58s / 1800 ticks / 10 agents ≈ 32 microseconds per agent per tick
```

That is the actual budget a navmesh query (or a re-path decision) has to fit inside, if the
loading pause is to stay under 1.5s at the worst-case fight length. **I have no measurement of
what a `NavigationServer3D.map_get_path()` query costs per call in this project** — nobody has
built the pathfinding yet, so there's nothing to profile. 32µs/agent/tick is a tight budget for a
navmesh query if one is issued every tick; it gets much easier if paths are cached and only
re-queried on a slower cadence (every N ticks, or on a real state change) rather than every 0.1s.
**This is the single most important unmeasured number in this document** — the moment pathfinding
exists in any form, re-run `-- sim` mode and update this section before trusting the 1.5s figure.

**Leash removal's effect on this specific number:** none directly — `MAX_DURATION` and tick count
are time-based, not distance-based, so a bigger board doesn't add ticks. It does mean each
navmesh query is now over a larger navigable area (more polygons to search), which is a real but
currently unquantified cost on top of the 32µs figure above.

---

## 4. Scaling — where this falls over

- **Team size is pinned at 5v5 maximum by design** (`CLAUDE.md`: "the game is a 5v5 game"), so
  unit-count-driven costs (10 sprites, 10 shadows, 10 nameplates, 10 HP bars) are flat forever
  under the current ruleset — that part of the render cost does not grow.
- **Board area does not scale with team size beyond 5v5**, but modes CAN put a fixed 5v5 team on
  a bigger neutral map (KotH/CTF, per `docs/AUTOBATTLER_DESIGN.md` §1). Where that breaks
  something specific: `ArenaLayout`'s obstacle count target scales with ground **area**
  (`area / (AREA_PER_PIECE × DENSITY_SAFETY_FACTOR)`), and area scales with the ground-scale
  factor **squared**. A board twice as wide and twice as deep is 4x the obstacle count, for the
  same 10 units — that's where obstacle-driven draw calls (§5) stop being a rounding error.
- **Species/league art coverage.** Video memory today (257MB) covers 12/65 species and 5/11
  leagues. That is the single most direct, load-bearing number for a VRAM ceiling and it scales
  close to linearly with content added — see §2's extrapolation.

---

## 5. The single biggest current cost — named specifically

**The venue's own static geometry — walls, the 5-tier stands, and cover obstacles — is built as
dozens of individual `MeshInstance3D` nodes, each with its own `material_override`, and none of
it is batched or instanced**, despite being the least "gamey," most repetitive part of the scene.

From reading `arena_3d.gd:_build_world()`/`_build_obstacles()` directly (not itself re-measured
per-node — `Performance` doesn't break draw calls down by node, so this is source-level reasoning
paired with the measured aggregate, not a second independent measurement):

- 4 wall boxes (`_add_box`, one call each)
- 5 stand tiers × 4 sides = **20 stand boxes**, all sharing one `stand_mat` — a textbook
  `MultiMeshInstance3D` candidate (same mesh, same material, only the transform differs) that is
  instead 20 separate draw calls
- obstacles: scales with ground area (§4) — at 5v5 today, roughly a dozen-plus boxes, each its
  own node with its own material
- per unit (×10): 1 shadow quad + 1 `Sprite3D` = 20 more
- transient: tracers and floating damage numbers each spawn their own `MeshInstance3D`/`Label3D`
  for the duration of their tween, adding to the max (639) without adding to the mean

**That accounts for the bulk of the measured 592 mean draw calls without a single ability effect,
particle, or piece of actual combat VFX on screen yet.** Converting the stand tiers (and, once the
leash removal is in and obstacle density is re-measured, the obstacles) to `MultiMeshInstance3D`
is the highest-value, lowest-risk optimization available — it changes nothing about gameplay or
the frame stream contract, it only changes how already-decided geometry gets submitted to the
GPU. **Recommending this to `engine-programmer`/`godot-specialist`, not implementing it myself.**

---

## 6. What is NOT measured yet, stated plainly

- **Any hardware below an RTX 5080.** Every render number in §1c is a best case.
- **Pathfinding's actual per-query cost** — nothing to profile until it's built (§3).
- **The post-leash-removal fight** — everything in §1c is of the current clustered engagement.
- **A worst-case 180s/1800-tick fight actually played to completion in the renderer** — §1b/§1c's
  worst-case figures are extrapolated from shorter real fights, not observed end to end.
- **Audio.** Not yet a system in this project; §2's render budget reserves nothing for it because
  there's nothing to reserve against yet.
- **Per-system frame breakdown** (how much of the 11.05ms is sprites vs. UI plates vs. shadows vs.
  environment) — `Performance` monitors give aggregates only; a RenderDoc/Godot profiler capture
  would be needed to break this down further, and hasn't been done.
