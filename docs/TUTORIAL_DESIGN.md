# Tutorial — design spec for the Godot port

**2026-08-04.** Written against the user's complaint, verbatim: *"there is no tutorial, so much
of the game is missing, finish the port."*

⚠️ **THIS IS A SPEC, NOT CODE.** `scripts/ui/theme.gd`'s own header comment lists `tutorial_ui`
among "six screens being rewritten concurrently right now" (alongside `town_ui`, `sandbox_ui`,
`tactics_ui`, `arena_3d`). Another stream is already building `scripts/ui/tutorial_ui.gd`. This
document is the interface contract that stream should build to — writing the `.gd` files from
two places at once is a guaranteed collision. **Before implementing, confirm with whoever owns
that stream whether this spec supersedes or should merge with their in-progress work.**

---

## 1. Overview

The tutorial is not a scripted cutscene and not a wall of text at boot. It is a **step pointer
on game state** (`docs/CORE_LOOP_PORT.md` §1, mirroring `src/town.ts:459 tutorialStep`), rendered
as a small non-blocking banner that points at the thing the player should do next, and advances
itself when the player does it — never when the player dismisses it. A player who skips the
tutorial entirely (`tutorialEnabled = false`) sees nothing; a player who dismisses it
(`tutorialDismissed = true`) sees nothing further this game, but the underlying step pointer
keeps advancing quietly so a later re-enable (if ever added) resumes in the right place rather
than replaying from "buy."

Six steps, in order: **buy → plan → feed → advance → stamina → tournament → (done)**.

## 2. Player Fantasy

`CLAUDE.md`'s fixed point: *"the player never intervenes in a fight… preparation is the skill;
observation is the reward."* A tutorial for a game like that has exactly one job, and it is not
"show the player the buttons" — it's **make every decision legible before the first fight**,
because a player who could not have chosen differently learns nothing from watching the outcome.
Concretely: by the time the first tournament starts, the player must be able to answer "why did
I bring this team, and why is it built like this" without the game telling them. If the tutorial
produces a player who can operate the UI but couldn't answer that question, it has failed at its
actual job even if every button got clicked once.

The stamina step (§3.5) is the single highest-leverage moment in that arc — it's the one that
turns "click Advance Week" from a formality into a decision with a real opportunity cost, which
is the whole game in miniature.

## 3. Detailed Rules

### 3.1 State model

A new autoload, `Tutorial` (`scripts/tutorial.gd`), owns:

| field | type | mirrors (React) |
|---|---|---|
| `enabled` | `bool` | `tutorialEnabled` |
| `dismissed` | `bool` | `tutorialDismissed` |
| `step` | `String` — one of `"buy" \| "plan" \| "feed" \| "advance" \| "stamina" \| "tournament" \| "done"` | `tutorialStep` |
| `seen` | `Dictionary[String, bool]` | `tipsSeen` — per-step "shown once" guard, independent of `step` so a step already advanced past doesn't re-show if the player somehow revisits it |

`enabled` defaults `true` for New Career and `false` for a save with no prior tutorial state
(mirrors `App.tsx:3161`'s "already playing → skip tips by default" migration rule). `step`
defaults `"buy"` when `enabled`, else unset.

**`step` only ever moves forward.** There is no back-transition and no branch — this is
deliberately simpler than React's tree (which had `raise`/`howto`/`final` as near-siblings); six
linear steps read cleanly as "the first session," which is the entire scope here.

### 3.2 The attach-from-outside mechanism

⚠️ **This is the load-bearing design decision, and it is why this system needs zero cooperation
from `town_ui`/`market_ui`/`shop_ui`/`stable_ui`/`training_ui`/`feeding_ui`/`week`/`economy`/
`career` — every one of which is explicitly off-limits to edit.**

`Tutorial` never waits for another screen to call it. It advances by **observing state that
already exists independent of any UI**:

- **Scene identity** — watch `get_tree().tree_changed` (or poll `current_scene.scene_file_path`
  in `_process`, throttled) to know which screen the player is on. This needs nothing from
  `town_ui.gd` etc. — it reads the scene tree, not the script.
- **Roster/Career/MonsterInstance state** — `Roster.monsters`, `Career.week`, `Career.gold`,
  `MonsterInstance.stamina` are all plain autoload/RefCounted state, readable without the owning
  screen doing anything on purpose.

`TutorialUi` (the overlay) polls `Tutorial.current_hint()` once per second (not per frame — this
is a hint banner, not a HUD) and redraws only when the returned hint dictionary changes.

**Two steps cannot be observed this way, and that is stated honestly rather than faked:**

- **`plan`** — "set a drill, nothing is spent yet" is a fact about `stable_ui`/`training_ui`'s
  *local, unsaved* selection state. Nothing external can see "the player has picked a drill" until
  that selection is committed by Advance Week. Until those screens expose a readable
  signal or property, `plan` is a **scene-entry callout** (shown once on first entry to the
  Stable with ≥1 monster owned), not an action-confirmed step. See §7 for the upgrade path.
- **`feed`** — same limitation, same treatment, gated on first entry to whatever screen becomes
  the feeding phase.

The other four (`buy`, `advance`, `stamina`, `tournament`) are true action-confirmed triggers —
see §3.3–3.6.

### 3.3 Step: `buy`

- **Shown when:** `step == "buy"`, on the Market scene, `Roster.monsters.size() < BUY_TARGET`.
- **Advances when:** `Roster.monsters.size() >= BUY_TARGET` (see §6 for the constant and why it
  isn't hardcoded to React's barn-of-2 without a caveat).
- **Copy:**
  > *"Welcome to the guild. Every partnership starts empty — the Market is where that changes.
  > Sign your first partners; the barn holds [N]. Choose with intent, not just budget."*

### 3.4 Step: `plan`

- **Shown when:** `step == "plan"`, first entry to the Stable/Training scene with ≥1 monster
  owned. Scene-entry callout (§3.2 caveat).
- **Advances when:** the player reaches the Advance Week scene/action at least once (i.e. folds
  into `advance`'s trigger — see §7 for why this is a deliberate, temporary compromise, not an
  oversight).
- **Copy:**
  > *"Set a drill here and nothing leaves your pocket. Planning is free — the week itself is
  > what costs you."*

### 3.5 Step: `feed`

- **Shown when:** `step == "feed"`, first entry to the feeding phase/screen.
- **Advances when:** same fold-into-`advance` compromise as `plan` (§7).
- **Copy:**
  > *"Bought feed costs gold. Forage costs nothing at the till — but it costs stamina and
  > happiness instead. Hunger is never free. You're only ever choosing which coin you pay it in."*

### 3.6 Step: `advance`

- **Shown when:** `step == "advance"`, anywhere, until the first Advance Week fires.
- **Advances when:** `Career.week` increases by ≥1 from its value when this step began (store the
  starting value on entering the step, not a hardcoded `1`, so this is correct even if Advance
  Week is ever called with `n > 1`).
- **Copy:**
  > *"Nothing you've planned happens until you press Advance Week. That's the only thing in this
  > game that moves the clock."*

### 3.7 Step: `stamina` — ⚠️ the one that matters most

The user's loudest, most specific complaint: *"i can still train infintely."* This step's entire
job is to make stamina register as a **wall**, not a number that happened to go down. Get this
step wrong and the tutorial has failed at its one indispensable task regardless of how the other
five read.

- **Best trigger (preferred):** the first time a training attempt is refused for insufficient
  stamina. This requires `training_ui`/`week` to expose *something* observable — even just
  writing a refusal reason to a place `Tutorial` can poll (`Career.last_training_refusal` or
  similar) is enough; it does not require them to call into `Tutorial` directly. Flag this as a
  **coordination ask**, not a hard requirement — see §7.
- **Fallback trigger (works today, needs nothing from anyone):** poll every owned monster's
  `stamina` each check; fire the first time any drops **below `STAMINA_WARN_THRESHOLD`**
  (see §6 — set below the cost of an intensive drill so the warning is provably true the moment
  it appears: the next intensive drill on that monster WILL be refused or short-changed).
- **Advances when:** shown once (one-shot via `seen["stamina"]`), then falls through to
  `tournament` — this step does not gate on a further action, because the lesson is the
  observation itself, not a follow-up click.
- **Copy** (uses the monster's name if `Roster` exposes one for the affected slot, else generic):
  > *"[Monster] is out of legs. That last drill spent stamina it doesn't have back yet — the
  > next one will be refused or half of what you'd hoped. Rest it, or work someone else. You
  > cannot train everyone, every week, forever — that's not a bug, that's the season."*

### 3.8 Step: `tournament`

- **Shown when:** `step == "tournament"`, on first entry to the Tactics/tournament scene
  (`scenes/tactics.tscn`, detected purely by scene path — no cooperation from `tactics_ui.gd`
  needed).
- **Advances when:** the player leaves that scene having triggered a tournament run at least
  once (poll for a `Career`-level signal already exposed — `league_swept` fires post-match, which
  is sufficient to know a fight happened even though it fires slightly late; documented as a
  known lag in §5, not silently accepted as correct).
- **Copy:**
  > *"The cup is set. Once it starts, you're a guild master in the stands, not a hand on the
  > field — your orders are already given. Everything that happens now is what your preparation
  > earned you. Watch for it."*
- On advancing past this step, `step = "done"`; the overlay never shows again this game.

## 4. Formulas

No numeric formulas — this system has no math of its own, only thresholds (see §6, Tuning
Knobs). Documented here per the standard so the "no formulas" absence is a deliberate statement,
not a skipped section: the tutorial reads existing derived values (stamina, week, roster size);
it computes nothing new.

## 5. Edge Cases

- **`tutorialEnabled = false`:** `TutorialUi` must not instantiate at all — not "instantiate and
  hide," actually skip creation, so it costs nothing at runtime for a player who opted out at New
  Career.
- **`tutorialDismissed = true` mid-flow:** `step` keeps advancing on its normal triggers (cost is
  near-zero — it's just state reads), but `TutorialUi` renders nothing. This means a player who
  dismisses at `buy` and later somehow re-enables tutorials (a future settings toggle, say) does
  not replay from the start.
- **Save/load:** `step`, `enabled`, `dismissed`, and `seen` must round-trip through
  `save_game.gd`. That file is not on the do-not-edit list — add a `_serialize_tutorial` /
  `_deserialize_tutorial` pair alongside the existing career/roster ones, defaulting to `"buy"`/
  `true`/`false`/`{}` for any save written before this system existed (the existing
  `_deserialize_career` pattern of `d.get(key, default)` already handles this correctly for new
  fields on old saves — follow it exactly).
- **A monster is bought, then released, dropping `Roster.monsters.size()` back below
  `BUY_TARGET` after `buy` already advanced:** do not regress `step` backward. `step` is
  monotonic by design (§3.1) — a player who un-does progress is not un-taught.
- **Player reaches the Tactics scene before ever buying a monster** (e.g. via a debug shortcut, a
  future direct-navigation feature): `Tutorial` should not crash or show `tournament` copy out of
  order — clamp displayed hints to "the step the pointer says," never to "the scene implies," so
  a skip-ahead never produces contradictory advice.
- **Two monsters both cross the stamina threshold in the same check:** fire once, for the first
  one found; do not queue a second stamina hint later — `seen["stamina"]` is a single flag, not
  per-monster.
- **`stamina`/`happiness` are not yet persisted by `save_game.gd`** (confirmed by reading the
  file — `_serialize_monster` only writes `speciesId`/`stats`). This means the stamina fallback
  trigger (§3.7) can only ever fire within a single play session today; a save/reload silently
  resets every monster's stamina to `100.0`. **This is a real, separate gap outside tutorial
  scope** — flagging it here because it directly weakens the stamina step's reliability, and
  whoever owns `career.gd`/`monster_instance.gd`/`save_game.gd` should know the tutorial depends
  on stamina persisting once it does.

## 6. Dependencies

**Reads only, never writes, and never edits:**
`Roster` (`monsters`, size), `Career` (`week`, `gold`, signals `league_swept`/`promoted`/
`game_won`), `MonsterInstance` (`stamina`, `happiness`), `get_tree().current_scene` (scene
identity), `scripts/ui/theme.gd` (panel/heading/color tokens for the overlay — reuse
`panel_style()`/`heading()`; there is no existing banner/callout builder in `theme.gd`, so the
overlay authors its own small `PanelContainer`+`Label`+close-button composition from those
tokens rather than inventing new styling).

**Explicitly does not edit:** `town_ui.gd`, `market_ui.gd`, `shop_ui.gd`, `stable_ui.gd`,
`training_ui.gd`, `feeding_ui.gd`, `week.gd`, `economy.gd`, `career.gd`.

**May edit:** `save_game.gd` (add the tutorial serialize/deserialize pair — not on the
do-not-edit list), plus the two new files this spec describes.

**Provides to others:** nothing — this is a leaf system. No other system should ever need to
query `Tutorial` for gameplay logic; if one does, that's a sign the tutorial has grown a gameplay
dependency it shouldn't have.

## 7. Tuning Knobs

| knob | category | proposed value | rationale |
|---|---|---|---|
| `BUY_TARGET` | gate | `2` | Mirrors React's barn-of-2 (`START_BARN`). ⚠️ **Not fully confirmed** — `market_ui.gd:19` currently implements its own "soft cap on stable size" independent of any ported barn economy. Confirm this matches whatever `market_ui`/`shop_ui` land on before shipping; do not silently assume 2 forever. |
| `STAMINA_WARN_THRESHOLD` | gate | `24.0` | Set just below the intensive drill's stamina cost (`docs/CORE_LOOP_PORT.md` §3: intensive is −25). Below this, the next intensive drill is provably unaffordable — the warning is never a false alarm. |
| `POLL_INTERVAL_SEC` | feel | `1.0` | The overlay is a hint, not a HUD; per-frame polling of Roster/Career state for a banner that changes maybe six times in a session is wasted cycles for zero perceptible benefit. |
| Copy strings | — | see §3 | All six live in `Tutorial` as a `Dictionary[String, String]`, not scattered `print`/inline literals, so a later localization pass has one place to look (this project has a `localization-lead` role in the studio roster; do not pre-empt that pass, but do not make its job harder either). |

## 8. Acceptance Criteria

**Functional:**
- [ ] New Career starts with `Tutorial.step == "buy"`, `enabled == true`, `dismissed == false`
- [ ] `tutorialEnabled == false` produces a `TutorialUi` that is never instantiated (verify via a
      probe, not eyeballing — e.g. assert the node is absent from the tree)
- [ ] Save → quit → load preserves `step`/`enabled`/`dismissed`/`seen` exactly
- [ ] Buying a 2nd monster (or whatever `BUY_TARGET` resolves to) advances `step` to `"plan"`
      without any click on the tutorial banner itself
- [ ] The `stamina` hint fires the first time any owned monster's stamina crosses below
      `STAMINA_WARN_THRESHOLD`, and only once per game (not once per monster)
- [ ] `./run_contract.sh` still passes — this system touches no contract math and must not
      regress any of the 219 cases

**Experiential (playtest-validated, not just functionally true):**
- [ ] A first-time player can articulate, unprompted, why they cannot "just keep training" —
      this is the test the entire stamina step exists to pass
- [ ] The banner never blocks a click on the control it's pointing at — verify with the same
      paint-order technique `CLAUDE.md` mandates for layering bugs (`elementsFromPoint`-equivalent
      hit-test at the pointed-to button's center, confirm the real button tops the stack)
- [ ] Dismissing the banner takes exactly one click, never a confirm dialog
- [ ] A player who never engages with the tutorial at all (`tutorialEnabled == false` from New
      Career) can still complete the buy → tournament loop with the game's existing UI alone —
      the tutorial teaches, it does not gate

---

## Appendix: Implementation interface (pseudocode — not compilable, not for me to finalize)

This is the contract the eventual implementer should code against. It is intentionally not
full GDScript — signatures and responsibilities only, so the actual typing/`preload()`/
`has_method()` guard details are the implementing programmer's call, per this studio's own
Godot conventions (`.claude/docs/technical-preferences.md`).

```
# scripts/tutorial.gd — autoload
# NOT class_name (see technical-preferences.md forbidden-pattern note); autoload entry instead.

var enabled: bool
var dismissed: bool
var step: String            # "buy" | "plan" | "feed" | "advance" | "stamina" | "tournament" | "done"
var seen: Dictionary         # step name -> bool, one-shot guard independent of `step`

func start_new_career() -> void
    # enabled = true, dismissed = false, step = "buy", seen = {}

func load_from_save(d: Dictionary) -> void
    # duck-typed d.get(key, default) reads, mirrors save_game.gd's existing pattern

func dismiss() -> void
    # dismissed = true — does NOT touch `step`

func current_hint() -> Dictionary
    # returns {} if nothing to show (enabled==false, dismissed==true, or step=="done"/no trigger
    # met yet). Otherwise {"step": step, "text": <copy>, "anchor_hint": <optional target scene
    # node path or screen-relative point, for tutorial_ui to position the callout near>}.
    # Pure function of current Roster/Career/scene state plus `seen` — called by tutorial_ui on
    # its own poll timer, never pushed.

func _check_advance() -> void
    # called on the same poll timer; contains the six trigger checks from §3.3-3.8, each
    # guarded so a missing autoload/method degrades to "don't advance yet", never a crash.
```

```
# scripts/ui/tutorial_ui.gd — a CanvasLayer added once, sibling to the current scene, NOT a
# child of any screen (so it survives scene changes without any screen's cooperation).

# root: CanvasLayer, layer = high (above normal UI, below true system modals if any exist)
#   -> PanelContainer (mouse_filter = STOP — this is the ONLY input-eating node)
#        built from UiTheme.panel_style() + UiTheme.heading(), per docs/UI_LAYOUT_RULES.md
#        positioned to avoid covering the control it references (anchor_hint from current_hint())
#        contains: Label (the copy), a small "x" dismiss Button (focus_mode = ALL, per
#        UI_LAYOUT_RULES.md checklist item 4)
#   -> everything else in the CanvasLayer (if any) stays mouse_filter = IGNORE

func _ready() -> void
    # poll Tutorial.current_hint() every Tutorial.POLL_INTERVAL_SEC via a Timer, not _process

func _on_hint_changed(hint: Dictionary) -> void
    # rebuild or hide the panel; no-op (skip rebuild) if hint is unchanged from last poll

func _on_dismiss_pressed() -> void
    # Tutorial.dismiss(); hide the panel immediately
```

**Verification the implementer owes, per this project's standing rule
(`CLAUDE.md` "Verifying visual changes without screenshots"):** run at 1152×648, screenshot the
`buy` and `stamina` states, and run the paint-order probe (temporarily flip the panel's
`mouse_filter` to `STOP` is already the design — the check needed is the *inverse*: confirm
`elementsFromPoint`-equivalent at the pointed-to button's center resolves to the real button, not
the CanvasLayer, proving the 99% of the overlay that is `IGNORE` truly passes clicks through).
