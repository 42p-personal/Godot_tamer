# The spatial rebuild — interface contract between workstreams

**2026-08-04.** Written before the fan-out so six parallel workstreams agree on the seams.
⚠️ **Nothing here is negotiable without telling the coordinator** — every item is depended on by
at least two other agents.

---

## 0. The reversal, stated once

`CLAUDE.md` says *"Do not port what is being redesigned. Arenas, the spatial layer, the camera and
target selection are all explicitly out."* **The user has directed that the game become a real
simulation, so that rule is deliberately superseded.** It was right while the model was unsettled;
the model is now settled in `docs/ARENA_BLUEPRINT.md`, `docs/SPATIAL_MODEL.md`,
`docs/ENGAGEMENT_DESIGN.md` and `docs/SPATIAL_COMBAT_DESIGN.md`, and this build implements THOSE
rather than inventing a new one.

## 1. ⚠️ DETERMINISM IS THE HARD CONSTRAINT

`docs/SPATIAL_MODEL.md`: Godot physics and navigation are **not deterministic by default**, and
four systems depend on the current guarantee. Every workstream must honour all of:

| rule | why |
|---|---|
| Fixed step `Spatial.DT` (0.1s). **Never** frame `delta` in sim code | frame-rate independence |
| All randomness via an **injected** `RandomNumberGenerator` | replay + contract tests |
| **No** `RigidBody3D`/`CharacterBody3D`/`NavigationAgent3D`/`PhysicsDirectSpaceState` in the sim | those are the non-deterministic parts |
| Iterate units in a **fixed array order**, never Dictionary hash order | GDScript Dictionary order is insertion-based but easy to break |
| No `Array.shuffle()` — Fisher-Yates on the injected rng | `shuffle()` reseeds from global state |

**Acceptance test:** the same seed + same orders must produce a byte-identical frame stream twice.
The QA workstream owns that harness; everyone else must not break it.

## 2. Ownership map — do not edit another stream's files

| stream | owns | must not touch |
|---|---|---|
| **A · spatial core** | `scripts/spatial_sim.gd` | anything else |
| **B · AI / targeting** | `scripts/spatial_ai.gd` | `spatial_sim.gd` |
| **C · arena layout / cover** | `scripts/arena_layout.gd` | sim files |
| **D · renderer** (coordinator) | `scripts/ui/arena_3d.gd`, `scenes/arena3d.tscn` | sim files |
| **E · art: dressing** | `assets/arena/**`, `tools/gen_arena_dressing.sh` | all `scripts/` |
| **F · art: creatures** | `assets/creatures/**`, `tools/gen_creatures_slice.sh` | all `scripts/` |
| **G · QA / determinism** | `scripts/_spatial_test.gd`, `docs/SPATIAL_QA.md` | production code (report, don't patch) |

`scripts/spatial.gd` is the **shared contract**, owned by the coordinator. Read it; propose
changes rather than editing.

## 3. The frame stream — the seam between sim and renderer

⚠️ **The renderer must never re-derive positions.** The sim is the only source of truth; the
renderer replays. This is the same pure-sim/presentation split `battleReport.ts` already uses, and
it is what makes the fight reproducible AND filmable.

`SpatialSim.run()` returns:

```gdscript
{
  "winner": "A" | "B" | "draw",
  "duration": float,                # sim seconds
  "log": Array,                     # unchanged event log — same kinds battle_sim.gd emits today
  "survivorsA": int, "survivorsB": int,
  "groundSize": Vector2,            # from Spatial.ground_size(team_size)
  "obstacles": Array,               # [{rect: Rect2, grade: String, kind: String}] — as fought
  "frames": Array,                  # THE NEW PART, below
}
```

Each frame is one sampled tick:

```gdscript
{
  "t": float,                       # sim seconds
  "units": [                        # FIXED ORDER: all of team A in slot order, then all of team B
    {
      "id": int,                    # stable index; matches the order units were passed in
      "pos": Vector2,               # ground coordinates, origin at ground corner
      "facing": Vector2,            # unit vector
      "hp": float, "mp": float,
      "alive": bool,
      "state": "idle"|"advance"|"retreat"|"attack"|"cast"|"stunned"|"dead",
      "statuses": Array,            # [String]
      "targetId": int,              # -1 when none
    }, ...
  ],
  "shots": [                        # transient, this tick only — for the renderer's VFX
    {"fromId": int, "toId": int, "kind": "melee"|"ranged"|"magic"|"support",
     "hit": bool, "dmg": int, "crit": bool, "move": String}
  ]
}
```

**Sampling rate:** every tick (`DT` = 0.1s → 10 fps of simulation). A 40s fight × 10 units is
~4,000 unit records — comfortably fine in memory, and the renderer interpolates between frames for
smooth motion.

## 4. What each stream must deliver

### A · spatial core (`spatial_sim.gd`)
The fixed-step loop: deploy → per-tick { AI decide (call stream B) → move → resolve actions →
tick statuses } → result. **Reuses the verified maths untouched**: `Damage.resolve_strike`,
`Derive`, `StatusMath.apply_status`, `Tick.tick_unit`, `Classify`. Movement, reach gating,
minimum range, backpedal asymmetry and the closing bonus all come from `Spatial`.
⚠️ A unit may only act when the target is inside `Spatial.reach_of(move)` — reach gating is the
entire point of the exercise.

### B · AI / targeting (`spatial_ai.gd`)
Pure functions: `choose_target(unit, enemies, allies, tactics, obstacles) -> id` and
`desired_position(unit, target, allies, tactics, ground) -> Vector2`. Must honour the existing
`tactics.gd` vocabulary (`targetPriority`, `temperament`, `manaPolicy`, `formation`) — do NOT
invent a second one. Kiting, closing, holding the line and the leash all live here.

### C · arena layout (`arena_layout.gd`)
`generate(team_size, league, rng) -> {obstacles, theme}`. ⚠️ Two rules from
`docs/ARENA_DESIGN.md` are enforced, not optional: **180°-rotational symmetry** (neither side gets
a better board) and the **density law** (`AREA_PER_PIECE = 300` as a CEILING to check against, not
a target to author toward). Cover sits in the annulus between the tight and loose leash radii.

### D · renderer
Consumes `frames`, interpolates, draws the board at `groundSize` with `obstacles` as real geometry.

### G · QA
Determinism harness + a spatial contract file in the style of the existing six.

## 5. What must NOT regress

- **The six port contracts still pass** — `cd monster-tamer && ./run_contract.sh` → 219 cases.
  The verified maths modules are reused, not rewritten. If a contract moves, something is wrong.
- **`battle_sim.gd` stays** as the non-spatial reference implementation. Do not delete it; it is
  the control for judging whether the spatial layer changed outcomes for the right reasons.
- **The balance baseline stays suspended** (`CLAUDE.md`). Do not tune numbers to hit a target and
  do not quote `sweep40` figures. Getting the STRUCTURE right is this pass's job; re-baselining is
  a separate, later, deliberate act.
