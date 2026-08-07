---
name: tournament-tactics-disconnect
description: The reachable Godot tournament path resolves fights headlessly with no arena — tactics_ui.gd/arena3d.tscn (the good screen) is unreachable from it
metadata:
  type: project
---

**As of 2026-08-04, the reachable Godot ladder path never shows a fight.**
`stable_ui.gd:174` → `tournament.tscn` → `tournament_ui.gd:_on_enter` → `career.gd:171
enter_league_tournament`, which resolves all 3 cup matches headlessly in a single `for` loop
(`BattleSimScript.new(...).run()` called 3x, discarded to a `Dictionary`) and returns to a static
WON/lost text panel. `tournament_ui.gd` has no `change_scene_to_file` call to any arena scene —
its only such call is the Back button to `stable.tscn`.

`tactics_ui.gd` ("The Read") is the good screen — a real pre-battle tactics UI (deployment board,
per-monster target-priority inherit state, gameplan tell/counter-read, keyboard-accessible
man-mark) that correctly hands off to a **live** simulated fight at `arena3d.tscn`. But it is
disconnected: it builds its own standalone demo team/rival in `_ready()` rather than reading
`Career`'s active-cup state, and **`tactics.tscn` has zero inbound references anywhere in the
live navigation graph** (confirmed by grepping every `change_scene_to_file` call in
`scripts/ui/*.gd`).

**Why:** nobody has yet wired `tournament_ui.gd`'s "Enter the Cup" to loop
`tactics.tscn → arena3d.tscn` per round (carrying win/loss state between rounds, the way React's
`RanchView` `matchIdx`/`fightOutcomes` did) instead of calling `enter_league_tournament` as one
headless batch. The pieces exist; they are just sequenced wrong.

**How to apply:** this directly contradicts `CLAUDE.md`'s core pillar — *"the player never
intervenes in a fight... commit, then observe"* — for the one system (the ladder) the whole game
is built around. Treat wiring the tournament loop through `tactics.tscn`/`arena3d.tscn` as the
single highest-leverage fix in the current build, ahead of any styling/polish work. Also:
`docs/ACCESSIBILITY.md`'s stated audit scope (*"title → stable → tactics → arena3d → report"*) is
now stale against this — `stable_ui.gd` does not route through `tactics.tscn` at all. Full
writeup: [design/ux/UI_AUDIT_2026-08-04.md](../../../design/ux/UI_AUDIT_2026-08-04.md).
