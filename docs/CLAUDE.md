# Docs Directory

When authoring or editing files in this directory, follow these standards.

## ⚠️ There are no ADRs and no `docs/architecture/`

**The section below describes a workflow this project does not use.** The decisions of record
live in prose — `GODOT_MIGRATION.md`, `SPATIAL_COMBAT_DESIGN.md`, `TACTICS_DESIGN.md`,
`TACTICS_BRAINSTORM.md`, `OUTSTANDING.md`, `CLAUDE.md`, `version.md` — and those are CURRENT,
which stub ADRs would not be. See the decisions table in
`.claude/docs/technical-preferences.md`.

Kept for reference in case the studio later wants the formal trail. **Do not create ADR stubs
that then rot**, and do not treat `/architecture-review` or the TR registry as gates — neither
has ever run here.

## Architecture Decision Records (`docs/architecture/`) — NOT IN USE

Use the ADR template: `.claude/docs/templates/architecture-decision-record.md`

**Required sections:** Title, Status, Context, Decision, Consequences,
ADR Dependencies, Engine Compatibility, GDD Requirements Addressed

**Status lifecycle:** `Proposed` → `Accepted` → `Superseded`
- Never skip `Accepted` — stories referencing a `Proposed` ADR are auto-blocked
- Use `/architecture-decision` to create ADRs through the guided flow

**TR Registry:** `docs/architecture/tr-registry.yaml`
- Stable requirement IDs (e.g. `TR-MOV-001`) that link GDD requirements to stories
- Never renumber existing IDs — only append new ones
- Updated by `/architecture-review` Phase 8

**Control Manifest:** `docs/architecture/control-manifest.md`
- Flat programmer rules sheet: Required / Forbidden / Guardrails per layer
- Date-stamped `Manifest Version:` in header
- Stories embed this version; `/story-done` checks for staleness

**Validation:** Run `/architecture-review` after completing a set of ADRs.

## Engine Reference (`docs/engine-reference/`)

Version-pinned engine API snapshots. **Always check here before using any
engine API** — the LLM's training data predates the pinned engine version.

Current engine: **Godot 4.7.1**. See `docs/engine-reference/godot/VERSION.md` — ⚠️ but check
the binary, not the doc; the pin was a minor version behind for six months.
