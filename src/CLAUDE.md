# Source Directory

When writing or editing game code in this directory, follow these standards.

## Engine Version Warning

The LLM's training data predates the pinned engine version.
**Always check `docs/engine-reference/` before using any engine API.**
Do not guess at post-cutoff API signatures — look them up first.

## Coding Standards

- All public APIs require doc comments
- Gameplay values must be **data-driven** (external config files), never hardcoded
- Prefer dependency injection over singletons for testability
- ⚠️ **There are no ADRs and no `docs/architecture/`.** The decisions of record live in prose —
  `docs/GODOT_MIGRATION.md`, `docs/SPATIAL_COMBAT_DESIGN.md`, `CLAUDE.md`, `version.md` — and
  those are CURRENT, which stub ADRs would not be. See the decisions table in
  `.claude/docs/technical-preferences.md`. Do not create ADR stubs that then rot.
- Commits reference the design document or the measurement, not a story ID — this project has
  no story tracker.

## File Routing

Match the engine-specialist agent to the file type being written.
See `CLAUDE.md` → Technical Preferences → Engine Specialists → File Extension Routing.

When in doubt, use the primary engine specialist configured in `CLAUDE.md`.

## Tests

⚠️ **THIS FILE SAID TESTS LIVE IN `tests/` AND THEY DO NOT.** They are colocated vitest specs —
`src/**/*.test.ts`, 289 of them — which is the idiom for this stack and is not changing.
`/test-setup` would scaffold a `tests/` tree nothing runs; do not run it.

Every gameplay system should have unit tests covering its formulas and edge cases.

**The Godot side has its own harness**, not vitest and not gdUnit4:
`cd monster-tamer && ./run_contract.sh` — five contracts, 173 cases, exit code is the result.

## Verification-Driven Development

Write tests first when adding gameplay systems.
For UI changes, verify with screenshots.
Compare expected output to actual output before marking work complete.
