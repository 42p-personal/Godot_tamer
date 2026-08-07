# Technical Preferences

**Filled in 2026-08-03.** This file sat on `[TO BE CONFIGURED]` for months while the engine
decision, the port and three contracts all landed — `/setup-engine` was never formally run
because the work went ahead without it. What follows is the state as BUILT, not as planned.

## Engine & Language

- **Engine**: **Godot 4.7.1** — `P:/Godot_v4.7.1-stable_win64.exe` (`4.7.1.stable.official.a13da4feb`)
- **Language**: **GDScript**, statically typed. ⚠️ C# is deliberately not set up: it adds a
  .NET toolchain and a second build step for no benefit the project can currently name.
  Revisit only if a *measured* hot path needs it — not on principle.
- **Rendering**: Forward+ (`config/features` in `project.godot`), D3D12 on Windows
- **Physics**: **Jolt** — the 4.6 default, already set in `project.godot`
- **Project root**: `monster-tamer/`

⚠️ **THE VERSION PIN WAS A MINOR VERSION BEHIND THE BINARY UNTIL 2026-08-03.**
`docs/engine-reference/godot/VERSION.md` said 4.6. Check the binary, not the doc. And note
**4.7 is beyond every migration source in the reference directory** — treat any 4.7-specific
API suggestion as unverified until checked against live docs.

## Project layout (`monster-tamer/`)

| path | holds | rule |
|---|---|---|
| `scripts/` | ported logic — `damage.gd`, `derive.gd`, `status_math.gd` | pure functions, no scene coupling |
| `data/` | `combat.json`, `derive.json`, `status.json`, `data.json` | ⚠️ **GENERATED. Never hand-edit.** `run_contract.sh` re-copies from the TS tree every run |
| `scenes/` | `.tscn` files | |
| `.godot/` | editor cache | gitignored |

## Input & Platform

- **Target platform**: **Desktop** (Windows first). The browser build is the legacy React app,
  not a Godot target.
- **Primary input**: Keyboard + mouse. This is an autobattler — the player commands and
  watches; there is no twitch input to tune.
- **Gamepad**: not yet; plausible later given the genre. **Touch**: no.

## Naming Conventions

Godot/GDScript house style — the engine's own conventions, not invented ones.

- **Classes**: `PascalCase` (`class_name Damage`)
- **Functions / variables**: `snake_case`
- **Constants / enums**: `SCREAMING_SNAKE_CASE`
- **Signals**: past-tense `snake_case` (`hit_landed`, `unit_died`)
- **Private members**: leading underscore (`_field_status`, `_rule()`)
- **Files**: `snake_case.gd`, `snake_case.tscn`
- ⚠️ **JSON keys keep the TypeScript's `camelCase`** (`maxHpDmg`, `ccMeterTouched`). They are
  generated from TS types; renaming them on the Godot side would mean a translation layer that
  can drift. Read them as-authored.

## Performance Budgets

⚠️ **PROPOSED, NOT MEASURED — do not cite these as decided.** Nothing has been profiled; the
Godot project currently runs headless arithmetic and renders nothing. Making numbers up and
recording them as budgets is exactly the failure this project's balancing rule exists to stop.
Set them properly with `performance-analyst` once a battle scene renders.

- Target framerate: 60fps desktop (the only figure with a real basis — it is the genre norm)
- Frame budget / draw calls / memory ceiling: **unset, pending first profile**

## Testing

- **Framework**: custom headless contract runner — `monster-tamer/run_contract.sh`, exit code
  is the result. ⚠️ gdUnit4 is NOT installed; the CI command in `coding-standards.md` refers to
  a `tests/gdunit4_runner.gd` that does not exist. Adopt gdUnit4 when scene-level tests are
  needed; the arithmetic contracts do not need it.
- **TypeScript side**: `npm test` (vitest) — 286 tests, and it regenerates and diffs all four
  port contracts so they cannot go stale.
- **Required tests**: combat math, stat derivations, status rules. All three are contracted.

## Forbidden Patterns

- ⚠️ **Never hand-transcribe a data table into GDScript.** `status_math.gd` first hardcoded 2 of
  15 status rules; adding a stacking status would have silently not stacked it. Tables travel
  as `data.json`. This has already been caught once.
- ⚠️ **Never use `class_name` in a script you also want `validate_script` to check alone** —
  the class cache is cold and it reports a false "not declared". Use `preload()`.
- ⚠️ **Never `round()` on a value that can be negative** and expect JS parity. JS rounds half
  toward +infinity; GDScript rounds half away from zero.
- **No `Math.random()`/`randf()` in simulation.** Determinism is the contract; RNG is injected.
- **Do not port the spatial layer, arenas, or the camera.** See `docs/GODOT_MIGRATION.md`.

## Allowed Libraries / Addons

- **None.** No Godot addons installed. Keep it that way until one earns its place — an addon
  is a dependency the port contract cannot verify.

## Architecture Decisions Log

No formal ADRs yet. The decisions of record live in prose, and that is where to read them:

| decision | where |
|---|---|
| Godot, and desktop rather than browser | `docs/GODOT_MIGRATION.md` |
| What ports, what is rebuilt, what is thrown away | `docs/GODOT_MIGRATION.md` §1 |
| Contracts replace whole-fight goldens as the acceptance test | `docs/GODOT_MIGRATION.md` §2 |
| 2D creatures in a 3D arena | `docs/GODOT_MIGRATION.md` decisions table |
| Reach, cover and flanking for the rebuild | `docs/SPATIAL_COMBAT_DESIGN.md` |
| The port is a skeleton; every system gets reworked | `CLAUDE.md`, top of file |

⚠️ Worth retro-fitting as ADRs via `/architecture-decision` if the studio wants the formal
trail — but the prose is current and the ADRs would not be, so **do not** convert them into
stubs that then rot.

## Engine Specialists

- **Primary**: `godot-specialist` — node/scene architecture, GDScript-vs-C# calls, engine idiom
- **Language/code**: `godot-gdscript-specialist` — static typing, signals, performance
- **Shader**: `godot-shader-specialist`
- **Native**: `godot-gdextension-specialist` (not expected to be needed)
- **Routing note**: ⚠️ **this is a GODOT STUDIO — there are no other engine specialists.** The
  definitions for other engines were deleted from `.claude/agents/` on 2026-08-03 along with
  their reference trees. If something asks you to pick an engine, the answer is already made.

### File Extension Routing

| File / type | Specialist |
|---|---|
| `*.gd` | `godot-gdscript-specialist` |
| `*.gdshader`, materials | `godot-shader-specialist` |
| `*.tscn`, `*.tres` | `godot-specialist` |
| `*.ts`, `*.tsx` (legacy React/sim) | `gameplay-programmer` / `lead-programmer` |
| Balance data + tools | the Balancing discipline — see `CLAUDE.md` |
| General architecture review | `technical-director` |
