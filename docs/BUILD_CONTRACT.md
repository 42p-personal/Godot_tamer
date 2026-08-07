# The build contract — interfaces for the spatial rebuild

**2026-08-04.** Binding on every workstream in this build. ⚠️ **Do not change a signature here
without telling the coordinator** — last round two agents coded against different versions of
`choose_target` and the sim crashed on first run. This file exists so that cannot happen again.

Design authority: `docs/AUTOBATTLER_DESIGN.md` (settled), `docs/TACTICS_TREES.md` (the subtrees),
`docs/SPIKE_DETERMINISM.md` (the pathfinding verdict).

---

## 0. The settled facts you are building against

| | |
|---|---|
| **Pathfinding** | Godot `NavigationServer3D.map_get_path()` over a **baked static navmesh**. Verified reproducible across 5 separate processes (`SPIKE_DETERMINISM.md`). ⚠️ **`map_get_path()` returns an EMPTY path with no error if the map has not synced** — the sim is a synchronous batch runner with no frame loop, so this MUST be handled explicitly or units silently get no path. |
| **Collision** | Ours, not Jolt. Solid bodies, deterministic push-apart. |
| **The leash** | ⚠️ **REMOVED.** Never reintroduce a clamp on desired position. `Spatial.engagement_radius()` still exists but is a LAYOUT helper for cover placement only. |
| **Sudden death** | Removed — was unreachable (`SUDDEN_DEATH_AT 255` vs `MAX_DURATION 180`). |
| **Speed** | Species/body **derived**, not trained or bred. |
| **Personality** | Extend the existing six axes in `src/tamerengine/personality.ts`; add `focus` **last** in the seeded stream or every existing save re-rolls. |
| **Determinism** | Fixed `Spatial.DT`, injected RNG, fixed iteration order, no `randf()`, no `Array.shuffle()`. |

---

## 1. The behaviour tree ↔ simulation interface

The sim owns the world and the clock. The tree owns the decision. **The tree never mutates world
state** — it returns an intention, and the sim decides whether it is legal.

```gdscript
# scripts/ai/monster_tree.gd
static func tick(ctx: Dictionary) -> Dictionary
```

**`ctx` (the sim builds this, the tree only reads it):**
```gdscript
{
  "unit":            <MonsterInstance>,   # untyped — cold class cache, see §4
  "unit_id":         int,                 # stable index, team A in slot order then team B
  "pos":             Vector2,
  "allies":          Array,               # living allies, EXCLUDING self, fixed order
  "ally_positions":  Array,               # parallel to `allies`
  "enemies":         Array,               # living enemies, fixed order
  "enemy_positions": Array,               # parallel to `enemies`
  "obstacles":       Array,               # [{rect: Rect2, grade: String, kind: String}]
  "tactics":         Dictionary,          # merged team plan + this unit's overrides
  "personality":     Dictionary,          # the 7 axes, 0..100
  "team_focus_id":   int,                 # index into `enemies`, -1 if none
  "now":             float,               # sim seconds
  "blackboard":      Dictionary,          # PERSISTENT per unit — the tree owns its contents
  "rng":             RandomNumberGenerator, # injected; the tree may draw from it
}
```

**Return value:**
```gdscript
{
  "action":      "move" | "attack" | "cast" | "idle",
  "desired_pos": Vector2,   # where it wants to be; the sim paths and moves it there
  "target_id":   int,       # index into ctx.enemies (or ctx.allies for support), -1 if none
  "move_name":   String,    # "" for a basic attack
  "intent":      String,    # ⚠️ REQUIRED — the live label, player vocabulary
  "reason":      String,    # ⚠️ REQUIRED — why, in player vocabulary
}
```

⚠️ **`intent`, `reason` and `attribution` are not optional and not decoration.** They are the
entire legibility layer of a game the player cannot intervene in (`AUTOBATTLER_DESIGN.md` §6).
Write intent/reason the way a player would say them — `"Falling back — your order"`, not
`"BT_RETREAT_3"`.

### ⚠️ `attribution` — ADDED 2026-08-04, and it must come from the TREE

One of exactly three values, plus empty when nothing decided:

| value | meaning |
|---|---|
| `"order"` | the player's standing order caused this |
| `"nature"` | this monster's personality default caused it |
| `"reacted"` | one of the four urgent overrides fired (taunt / target gone / about to die / unreachable) |

**Why it is a field and not inferred:** `UX_LEGIBILITY.md` makes attribution the most valuable
thing on the report screen — a player must be able to tell *"that was my order"* from *"that's
just how it is"* from *"it was taunted"*, or they cannot learn from a fight they could not
influence. Stream E correctly **refused to pattern-match the `reason` prose** for phrases like
"your order", because that is renderer-side derivation and this contract forbids it (§2). Only
the node that made the decision knows why it won, so only the tree can populate this.

⚠️ **Cheap now, expensive later.** This was added while `monster_tree.gd` was still unwritten.

---

## 2. The frame stream — simulation ↔ renderer

### ⚠️ BREAKING, ADDED 2026-08-04: `run()` IS A COROUTINE. YOU MUST `await` IT.

```gdscript
var result: Dictionary = await sim.run()     # NOT `var result := sim.run()`
```

**Why, and it is not negotiable:** `NavigationServer3D` only syncs a freshly-baked navmesh on real
`SceneTree` frames. Until it has, `map_get_path()` returns an **empty path with no error** — so
every unit silently gets no route and stands still. The spike measured that **`map_force_update()`
alone does NOT force the sync**; only elapsed frames do. `SpatialSim` has no frame loop of its own,
so `run()` awaits `process_frame` a fixed number of times before its first query.

⚠️ **This was NOT in the contract when streams C and E started**, so any caller written against
the old synchronous signature is broken. A missed `await` fails in a particularly nasty way — you
get a `GDScriptFunctionState` object instead of the result dictionary, and reads of `frames` or
`winner` come back empty rather than erroring. **If your fight looks empty, check this first.**

---

`SpatialSim.run()` returns:

```gdscript
{
  "winner": "A"|"B"|"draw", "duration": float,
  "log": Array,                    # unchanged event kinds: start/hit/miss/status_apply/
                                   # status_expire/buff/death/end
  "survivorsA": int, "survivorsB": int,
  "groundSize": Vector2,
  "obstacles": Array,              # as fought
  "frames": Array,                 # below — one per tick
}
```

**Each frame:**
```gdscript
{
  "t": float,
  "units": [                       # FIXED ORDER: all team A in slot order, then all team B
    {
      "id": int, "pos": Vector2, "facing": Vector2,
      "hp": float, "mp": float, "alive": bool,
      "state": "idle"|"advance"|"retreat"|"attack"|"cast"|"stunned"|"dead",
      "statuses": Array,           # [String]
      "targetId": int,             # -1 when none
      "intent": String,            # ⚠️ NEW — straight from the tree
      "reason": String,            # ⚠️ NEW — straight from the tree
      "attribution": String,       # ⚠️ ADDED 2026-08-04 — "order" | "nature" | "reacted" | ""
    }
  ],
  "shots": [                       # transient, this tick only
    {"fromId": int, "toId": int, "kind": "melee"|"ranged"|"magic"|"support",
     "hit": bool, "dmg": int, "crit": bool, "move": String}
  ],
  "projectiles": [                 # ⚠️ NEW — in-flight aimed abilities, so a shot that MISSES
                                   # because the target moved is visible
    {"id": int, "from": Vector2, "to": Vector2, "kind": String, "progress": float}
  ],
}
```

⚠️ **THE RENDERER DERIVES NOTHING.** If it needs to know something, the sim must emit it. Any
time the renderer computes where a unit "should" be, this contract is missing a field — say so
rather than working around it.

---

## 3. Ownership — do not edit another stream's files

| stream | owns |
|---|---|
| **A · sim + AI core** | `scripts/spatial_sim.gd`, `scripts/spatial_ai.gd`, `scripts/spatial.gd` |
| **B · monster tree** | `scripts/ai/monster_tree.gd` and any new file under `scripts/ai/` |
| **C · renderer** | `scripts/ui/arena_3d.gd`, `scenes/arena3d.tscn` |
| **D · tactics + deployment UI** | `scripts/ui/tactics_ui.gd`, `scenes/tactics.tscn`, new deployment files |
| **E · report + legibility** | `scripts/ui/report_ui.gd`, `scenes/report.tscn` |
| **F · stable/training/title + accessibility** | `scripts/ui/stable_ui.gd`, `training_ui.gd`, `title_ui.gd` |
| **G · QA + determinism** | `scripts/_spatial_test.gd`, `docs/SPATIAL_QA.md` |
| **H · personality** | `src/tamerengine/personality.ts`, `scripts/personality.gd` |

`scripts/ai/bt_*.gd` (the framework) is **shared and stable** — read it, don't change it.

---

## 4. Traps already hit in this project — do not rediscover

- ⚠️ **Bare `class_name` references fail to parse** under `--headless --script` and early autoload
  boot (cold global class cache). **Use `preload()`** for every cross-file reference. Hit four
  times now.
- ⚠️ **`MonsterInstance` cannot be a type annotation** for the same reason — leave those untyped.
- ⚠️ **`var x := some_untyped_call()`** fails with "cannot infer type". Explicit type or plain `var`.
- ⚠️ **Never name a variable `log`, `name`, `size`, `tr`, or `scale`** — all shadow built-ins.
  `log`, `size` and `tr` have each already broken this codebase.
- ⚠️ **`TextureRect` defaults to `EXPAND_KEEP_SIZE`**, so its minimum size is the texture's —
  assigning a smaller `size` silently does nothing. Set `expand_mode = EXPAND_IGNORE_SIZE`.
- ⚠️ **A `Sprite3D` with `billboard` enabled cannot be rotated** — billboarding re-solves every
  frame and silently undoes it. Disable billboard before toppling a corpse.
- ⚠️ **Autoloads are NOT available under `--headless --script`.** Instantiate `game_data.gd` /
  `art.gd` manually and add them to `root` with the right node names, or drive through a scene.
- ⚠️ **`Art.*` texture getters may return null.** Every screen must look deliberate with zero art.

---

## 5. What must not regress

- `cd monster-tamer && ./run_contract.sh` → **PASS, 219 cases.** The verified maths
  (`Damage`/`Derive`/`StatusMath`/`Tick`/`Classify`) is REUSED, never rewritten. A contract move
  means something is wrong.
- `battle_sim.gd` stays as the non-spatial reference implementation. Do not delete it.
- ⚠️ **The balance baseline is SUSPENDED.** Do not tune numbers to hit a target, and do not quote
  `sweep40` figures. Getting the structure right is this pass's job.
