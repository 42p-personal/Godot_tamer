# The determinism spike — does `NavigationServer3D.map_get_path()` reproduce?

**2026-08-04. Owner: engine-programmer.** Answers the question posed in
`docs/AUTOBATTLER_DESIGN.md` §11 and the constraint stated in `docs/SPATIAL_HANDOFF.md` §1.
This is the gate for the whole next phase — the tree AI, the spatial rewrite and the "real
pathfinding" decision (§8 #21 in `AUTOBATTLER_DESIGN.md`) all wait on the verdict below.

---

## Verdict

**YES — reproducible.** `NavigationServer3D.map_get_path()`, for a baked static navmesh queried
through the plain region API (no avoidance, no agents), returned **byte-identical output across
every process invocation tested** — 5 separate `godot --headless` processes, same seed-free fixed
geometry, same fixed query set, zero divergence.

**Recommendation: (a) Godot navmesh queries + our own collision.** Not a close call — see
§4. The news that arrived after this spike started (the leash's removal, meaning full-board
traversal becomes the common case, not the rare one) makes the case for (a) *stronger*, not
weaker: see §5.

**What I could not rule out is real and stated plainly in §6** — this is a single-machine,
single-OS, single-geometry-source result. Read that section before treating this as a closed
question for platforms or content types this spike didn't touch.

---

## 1. What was built

`monster-tamer/scripts/_spike_determinism.gd` (SceneTree script, no `.tscn` needed):

- A fixed 160×88 arena (matches `Spatial.ground_size(5)`) with **20 fixed box obstacles**,
  positioned as literal constants — no RNG anywhere, per `docs/SPATIAL_HANDOFF.md` §1. Three
  obstacles straddle the z=44 midline specifically so the long east–west queries have to detour
  around real cover, not just skim past it.
- Geometry is built directly as triangle soup (`NavigationMeshSourceGeometryData3D.add_faces`),
  **not** parsed from scene-tree `MeshInstance3D`/`CollisionShape3D` nodes. This isolates exactly
  the surface under test — `NavigationMeshGenerator` + `NavigationServer3D` — from rendering/
  physics-server geometry parsing, which is a separate question (see §6).
- The navmesh is baked twice, independently, from two freshly-built geometry objects (`nm_a`,
  `nm_b`) — this is the "bake twice" check the brief asked for.
- Two independent `NavigationServer3D` maps/regions are built, one per bake.
- **20 fixed (start, end) query pairs** — long corner-to-corner diagonals, straight sweeps that
  must round the z=44 obstacle wall, two very short local hops next to a single obstacle, and one
  **degenerate same-point query** (start == end) as an edge case.
- Each pair is queried **10 times** = **200 total queries**, matching the brief.
- Every path's raw `PackedVector3Array` is hashed via `PackedVector3Array.to_byte_array()` fed
  into `HashingContext.HASH_SHA256` — a byte hash, not a text comparison, so no float-formatting
  rounding can hide a real divergence.
- ⚠️ **Deliberately scoped to the static-region API only** — `map_create` / `region_create` /
  `map_get_path`. No `agent_create`, `obstacle_create`, `NavigationAgent3D`, or anything from the
  avoidance system. `AUTOBATTLER_DESIGN.md` §11 already corrects an earlier over-broad worry: the
  real risk it names is Godot's *threaded avoidance*, not static path queries, so this spike is
  built to measure precisely the surface the sim would actually call.
- A fixed 40-frame wait (`SYNC_FRAMES`) lets `NavigationServer3D` sync both maps before any query
  runs. This was empirically necessary — see the operational finding in §6.

## 2. The evidence

**Cross-process (the actual test):** run 5 times as five separate `godot --headless --script`
process invocations (not in-process loops):

| run | `FRAME_HASH` (SHA-256 of all 200 path byte-arrays, in order) |
|---|---|
| 1 | `575542a573a12e2412717fe4a8d229be341fec535c0a1d7bc95e182b8521642d` |
| 2 | `575542a573a12e2412717fe4a8d229be341fec535c0a1d7bc95e182b8521642d` |
| 3 | `575542a573a12e2412717fe4a8d229be341fec535c0a1d7bc95e182b8521642d` |
| 4 (after a delay before launch) | `575542a573a12e2412717fe4a8d229be341fec535c0a1d7bc95e182b8521642d` |
| 5 | `575542a573a12e2412717fe4a8d229be341fec535c0a1d7bc95e182b8521642d` |

`diff` on the FULL stdout of runs 1 vs 2, 1 vs 3, 1 vs 4, 1 vs 5 (not just the hash line — every
printed sample-path coordinate at 10 decimal places) returned **exit 0, zero differences**, every
time. The delayed run (4) ruled out the most obvious non-determinism source — anything seeded off
wall-clock time — producing the identical hash.

**The three sub-questions the brief asked for, all measured inside the same run:**

| check | result |
|---|---|
| Bake twice from independent geometry → identical `NavigationMesh.get_vertices()` bytes? | **`BAKE_VERTICES_IDENTICAL: true`** (298 vertices both bakes) |
| Bake twice → identical polygon index data? | **`BAKE_POLYGONS_IDENTICAL: true`** (290 polygons both bakes) |
| Does query ORDER affect the result? (forward pass vs. reversed pass, compared per-pair) | **`QUERY_ORDER_MISMATCHES: 0`** |
| Does querying the SECOND (independently rebaked) map reproduce the first map's paths? | **`REBAKE_MISMATCHES: 0`** |
| In-process repeat consistency (10 reps of the same 20 pairs, same map) | **`IN_PROCESS_REPEAT_MISMATCHES: 0`** — noted per the brief as a sanity floor, explicitly not the real test |

None of the 200×5 = 1,000 path queries run across this spike diverged from any other, in-process
or cross-process, forward or reversed order, first bake or rebake.

## 3. Sample evidence, at full precision

First query pair, `(5.0, 0, 44.0) → (155.0, 0, 44.0)` — 44 waypoints, routing around the three
obstacles straddling the z=44 midline. First and last three points, to 10 decimal places (full run
in the script's stdout, reproduced above as identical across all 5 processes):

```
5.0000000000, 0.2000000030, 44.0000000000
7.0000000000, 0.2000000030, 41.7500000000
7.7500000000, 0.2000000030, 41.0000000000
...
153.2500000000, 0.2000000030, 46.2500000000
155.0000000000, 0.2000000030, 44.0000000000
```

Two further full corner-to-corner diagonal samples are in the script's own stdout
(`SAMPLE_PATH[1]`, `SAMPLE_PATH[2]`) — reproduced identically in all 5 runs.

## 4. Recommendation: (a), Godot navmesh + our own collision

**Reasoning, weighing what this spike actually measured:**

- The determinism finding is unambiguous for the surface we'd use: static regions + `map_get_path`.
  That was the whole open question, and it closes clean.
- The navmesh IS the cheap side of this trade, not the expensive one. The baked navmesh for this
  160×88 arena with 20 obstacles is **298 vertices / 290 polygons** — Detour's path query walks a
  graph of a few hundred nodes, once per query, and the expensive part (voxelization/baking)
  happens **once per arena**, not once per query. §5 makes the size of that gap concrete against
  a hand-rolled grid.
- It keeps us off writing and maintaining our own pathfinder, funnel/string-pulling, and the many
  small correctness bugs that come with it (corner-cutting, degenerate starts, agent-radius
  clearance) — Recast/Detour has already had all of that hammered out. Our own job shrinks to
  collision (solid bodies, §10 of `AUTOBATTLER_DESIGN.md`), which is a much smaller and more
  tractable determinism surface: circle-vs-circle separation is trivial to keep out of any
  physics server.

**What "our own collision" means under recommendation (a):** simple deterministic circle
overlap resolution between unit bodies (`Spatial.BODY_RADIUS`), run as plain GDScript math inside
the fixed-step loop — no `RigidBody3D`/`CharacterBody3D`, matching `docs/SPATIAL_HANDOFF.md` §1
exactly. Units follow navmesh waypoints; collision only has to keep two bodies from overlapping
and does not itself need to be a pathfinder.

## 5. The leash's removal changes the cost side of this decision

This spike started against the description of the leash as a per-team-centroid clamp holding
every unit inside 24–42% of the board width. **That leash is being removed entirely** — units
will genuinely traverse the full 160×88 board, so:

- Long paths that round obstacle clusters (like the `SAMPLE_PATH[0-2]` examples above) become the
  **common** case, not the rare one.
- Re-pathing load goes up in both frequency (more reasons to retarget across a bigger board) and
  per-query cost (longer paths).

This cuts decisively in favour of (a), because of a number this spike actually measured: **the
navmesh's polygon graph (290 polygons) is 1–2 orders of magnitude smaller than a grid fine enough
to be geometrically correct at our body scale** (see the sketch below — a grid fine enough not to
lose `BODY_RADIUS = 0.9` clearance needs on the order of tens of thousands of cells for this same
160×88 arena). A levied-up query rate against a hand-rolled A* is exactly the wrong time to be
searching a grid 100–200× larger than the graph Detour already gives us for free. The harder the
pathfinding gets exercised, the worse the size gap between the two approaches matters — and the
leash's removal is precisely what makes it get exercised harder.

## 6. The cost sketch for (b) — our own grid A*, sized for a post-leash 160×88 arena

**This is a sketch, not a build, per the brief — no code was written for this option.**

**Grid resolution.** `Spatial.BODY_RADIUS = 0.9` (a 1.8-unit diameter body) means a grid coarser
than roughly 0.5–0.9 units risks a passage a body should fit through being misrepresented as
blocked, or vice versa. At 0.5-unit cells: `160 / 0.5 × 88 / 0.5` = **320 × 176 = 56,320 cells**.
Even a permissive 1.0-unit grid (already coarse relative to body diameter) is 160 × 88 =
**14,080 cells** — for comparison, the navmesh this spike actually baked over the *same arena* has
**290 polygons**, roughly 50–200× fewer nodes than either grid.

**Memory.** Static walkability is cheap (a packed bit per cell — ~1.8–7 KB for the two
resolutions above). The expensive part is per-query search state (g-score, came-from, open/closed
flag) — roughly 9 bytes/cell if using dense arrays, i.e. **~127 KB (1.0-unit grid) to ~500 KB
(0.5-unit grid)** live per in-flight query. Not disqualifying on its own, but every one of the
~10 concurrent agents needs its own such buffer (or a generation-stamp trick to reuse one), and
that buffer gets touched on every re-path.

**Per-query cost, sketched.** Grid A* with an admissible heuristic (octile distance) on a sparse
map (this arena's 20 obstacles cover roughly 5% of the ground) typically expands on the order of
2–10× the optimal path length in nodes for open terrain, more where a query must round a cluster.
For a corner-to-corner query (now the common case post-leash, ~170+ units, ~340+ cells at 0.5-unit
resolution) that's a rough **2,000–10,000 node expansions**, each doing 8-neighbour checks plus
binary-heap push/pop (`O(log n)` over the expansion count). That's on the order of
**~10⁵ elementary operations per query** — at GDScript's typical interpreted throughput for
branchy scalar work, a **rough** per-query cost in the **single-digit-to-low-double-digit
milliseconds**. This was NOT benchmarked (the brief asked for a sketch, and this spike measured
correctness/determinism, not wall-clock query speed on either side of the comparison — flagged
explicitly as a gap in §7, not papered over).

**Scaled to the actual load, post-leash-removal:** ~10 agents, each re-pathing "a few times a
second" (call it 2–3/s) = **20–30 path queries per simulated second**. At the sketched per-query
cost, that is roughly **0.2–0.5 real seconds of CPU per simulated second**, from pathfinding
alone, before AI utility scoring, damage resolution, or collision. For a *live* fight (targeting
real-time playback, 10 ticks/s) that is already a large fraction of, or more than, the whole frame
budget. For *offline balance sweeps* (the `sweep40`-style bulk runs this project's whole balancing
doctrine depends on — "one value at a time, iterate against the sim") the same per-query cost
multiplies across every fight in the sweep and would materially slow the turnaround time the
balancing doctrine needs to stay fast. Both consumers care, for different reasons.

**Also not included in this sketch, and each is its own cost:** dynamic re-planning around moving
allies/enemies (a static grid A* doesn't know about other units unless re-run against a
per-tick-updated obstacle mask), funnel/string-pulling to turn a cell path into a walkable line
(Detour already does this), and every correctness edge case Recast/Detour has already had shaken
out (degenerate starts, agent-radius clearance at corners, disconnected regions). None of that is
in the sketch above — it would only make (b) more expensive relative to (a), not less.

## 7. ⚠️ What I could not rule out — read before treating this as closed

Stated as plainly as the verdict, per the brief's instruction that an honest "reproduced, but—" is
more useful than false confidence:

1. **Single machine, single OS.** All 5 runs were on this Windows dev box, same binary
   (`Godot_v4.7.1-stable_win64.exe`). Cross-platform float determinism (a different CPU vendor, a
   Linux CI runner, a different compiler's FMA behaviour) is a genuinely separate risk category
   from same-machine cross-process determinism, and this spike says nothing about it. If CI or a
   second dev machine ever needs to reproduce a fight byte-for-byte, that has to be tested
   separately before it's assumed.
2. **Geometry source, not geometry parsing, was tested.** This spike builds navmesh input
   directly via `add_faces()` on hand-written triangle data — deliberately, to isolate the
   server/generator from rendering. It does **not** test the `parse_source_geometry_data(...,
   root_node)` path that reads `MeshInstance3D`/`CollisionShape3D` nodes out of a live scene tree,
   which is how a hand-authored arena scene would likely supply geometry in practice. If arena
   geometry ends up authored as scene nodes rather than generated data, that parsing step needs
   its own determinism check before being trusted on the same strength of evidence as this one.
3. **The sync mechanism has a real trap, found while building this spike, and it is worth
   carrying forward as a known integration hazard, not just a spike footnote.** `map_get_path()`
   silently returns an **empty path with no error** if the map has not yet synced — I measured
   this directly: `map_force_update()` alone (no elapsed frames) left the map's iteration ID at 0
   and the query returned zero points. Only letting real `_process()` ticks elapse (empirically,
   full sync completed by ~frame 10; I used a fixed 40-frame margin) got a real path back. A
   synchronous batch simulator with no wall-clock frame loop — which is exactly what `spatial_sim.gd`
   is expected to be, for running many fights back-to-back in a balance sweep — will need to solve
   this deliberately (e.g. confirm whether `map_force_update` behaves differently once called
   from inside an actual `_process` callback vs. cold, or explicitly drive N throwaway process
   frames before the first real query of every fight). Getting this wrong doesn't crash — it
   silently returns "no path," which is a worse failure mode than an error.
4. **Static geometry only — this spike says nothing about avoidance, and was never meant to.**
   No `NavigationAgent3D`, no `agent_create`/`obstacle_create`. That's the right scope (§11 of
   `AUTOBATTLER_DESIGN.md` already names avoidance as the real risk, not path queries), but it
   means this result cannot be cited as evidence *for* using the avoidance system — only as
   evidence that avoiding it, and using static regions + `map_get_path` instead, is a sound and
   reproducible foundation.
5. **Wall-clock performance was not measured, on either side of the recommendation.** §6's
   sketch is explicitly a sketch. Before scaling to full production load (10+ agents, whole
   board in play, sweep-style bulk fights) it would be worth a real benchmark of `map_get_path`
   query throughput on this project's actual query volume — cheap to get wrong is only true if
   someone checks.

## 8. Reproduce it

```bash
cd monster-tamer
P:/Godot_v4.7.1-stable_win64.exe --headless --path . --script res://scripts/_spike_determinism.gd
```

Run it 3+ times as separate invocations (not in a loop inside one process) and diff the
`FRAME_HASH:` line, or the full stdout, across runs.

## 9. Contract check

`cd monster-tamer && ./run_contract.sh` still prints **PASS** (219 cases across
`combat`/`derive`/`status`/`tick`/`classify`/`data`) — this spike touches only its own new file
and does not go near any contracted module.
