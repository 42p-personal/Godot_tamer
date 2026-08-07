---
name: project-suspended-balance-baseline
description: Monster Tamer's balance baseline is suspended during the Godot rebuild — do not quote sweep40/ab.ts figures as current, but new instrumentation/measurement work is still welcome
metadata:
  type: project
---

As of 2026-08-03/04, `CLAUDE.md` declares the TypeScript-side balance baseline (sweep40 figures:
48/48 resolved, ~23.3s, 230 kills, 2803 dmg/fight) suspended for the duration of the Godot
rebuild — cooldowns, damage math, statuses, and the whole spatial/arena/camera/targeting layer
are being replaced, not tuned. Do not cite those figures as describing the current game.

**Why:** measuring against a baseline mid-replacement produces confident numbers about a system
about to change, which is worse than not measuring — they get quoted later as if they meant
something.

**How to apply:** this does NOT mean stop building instruments. `performance-analyst` was asked
(2026-08-04) to design `docs/SPATIAL_BALANCE_TOOLING.md`, a full metric suite + harness for
judging the anti-blob AI rework (`docs/AUTOBATTLER_DESIGN.md`), explicitly as measurement
infrastructure rather than tuning. The right move in that situation: build the harness, capture
the *current* pre-rewrite spatial sim's numbers as a reference population (not a "good" target),
and require the rework to beat that population's own noise floor — never invent an absolute
target. Re-baseline happens once, deliberately, when the Godot engine runs a full fight
end-to-end; the standing "one value at a time" tuning rule resumes in full force only then. See
[[feedback-no-invented-numbers]].
