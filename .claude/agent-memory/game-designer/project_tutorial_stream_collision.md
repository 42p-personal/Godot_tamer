---
name: project-tutorial-stream-collision
description: scripts/ui/tutorial_ui.gd is being built by a concurrent stream — check before implementing the tutorial spec
metadata:
  type: project
---

`scripts/ui/theme.gd`'s own header comment (as of 2026-08-04) lists `tutorial_ui` among "six
screens being rewritten concurrently right now" (with `town_ui`, `sandbox_ui`, `tactics_ui`,
`arena_3d`). `scripts/ui/tutorial_ui.gd` did not exist on disk when checked (2026-08-04), but
another agent/stream was actively working on it at that time per that comment.

**Why:** a game-designer task asked me to write `scripts/tutorial.gd` +
`scripts/ui/tutorial_ui.gd` directly (see `docs/TUTORIAL_DESIGN.md`, which I wrote as a spec
instead of code — writing implementation code is outside this agent's role). Two independent
streams targeting the same file path is a guaranteed collision (one overwrites the other, or
they diverge on the interface).

**How to apply:** before any future session implements the tutorial `.gd` files, check
`git log --all -- monster-tamer/scripts/ui/tutorial_ui.gd` and `git status` for that path first,
and check whether `docs/TUTORIAL_DESIGN.md`'s interface contract was already reconciled with
whatever the other stream produced. Do not assume the spec in `docs/TUTORIAL_DESIGN.md` is
unclaimed just because the file didn't exist on 2026-08-04 — it may have landed since. See also
[monster-tamer-doc-drift] — this project has a repeated pattern of docs/task-briefs claiming a
system "does not exist" when it partially does (here: `monster_instance.gd` already carries
`stamina`/`happiness` fields ahead of `week.gd` landing, contradicting the tutorial task brief's
assumption that stamina doesn't exist yet).
