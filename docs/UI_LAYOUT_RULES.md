# UI layout rules — and the probe that enforces them

**2026-08-04, extended 2026-08-11.** Binding on every screen. Written after the user reported:
*"currently the game clips"* — with a screenshot of The Read cut off mid-deployment-board.

⚠️ **THE 2026-08-11 ADDITION IS NOT A NEW RULE, IT IS TEETH.** Every rule below was prose, and
prose decays — this project has watched a dozen invariants rot for exactly that reason
(`CLAUDE.md`'s signature failure: authored and unreached, 11+ instances). `scripts/_probe_house.gd`
now walks all thirteen player-facing screens and MEASURES the mechanical rules. What it found on
its first run is in §3, and it is not a clean sheet.

```
P:/Godot_v4.7.1-stable_win64.exe --path . res://scenes/_probe_house.tscn
```

⚠️ **RUN IT WITH A WINDOW, NEVER `--headless`.** The dummy renderer returns blank images, so a
headless run saves black rectangles and "passes".

---

## 1. The diagnosis

⚠️ **The clipping was not one screen's bug. It was systemic, and it had two causes.**

1. **`project.godot` set NO window size at all.** Godot launched at its own default (~1159×687
   in the reported case) while every screen was authored assuming 1280×800. Fixed — the base
   viewport is now explicit.
2. ⚠️ **Almost no screen scrolls.** They were each built by a different agent, laid out as if the
   window were guaranteed to fit the content. `training_ui.gd` had **zero** `ScrollContainer`s.

**Fixing (1) alone is not enough and must not be mistaken for a fix** — it moves the clipping to
anyone with a smaller monitor, a scaled display, or a resized window. The window size is a
default, never a guarantee.

---

## 2. The rules

### R1. ⚠️ EVERY SCREEN'S ROOT IS SCROLLABLE
A screen is a `ScrollContainer` wrapping its content, or it clips. However short the screen looks
today — content grows (a roster gains monsters, a log gains lines, a stat block gains the new
personality axes) and the screen that fitted last week will not next week.

**ONE CARVE-OUT, ADDED IN ROUND 18: a screen whose content is a FIXED, AUTHORED set of controls
that cannot grow from game state is exempt.** Today that is exactly `title_ui` — four buttons
written in the file, answerable to no roster, no week and no league. The rule's whole warrant is
"content grows"; where nothing can grow, the rule is asserting a cost with no hazard behind it,
and `_probe_house.gd` was reporting a screen as failing for being correctly simple. If a menu
ever starts listing save slots or mods, it grows and the exemption lapses — the test is *can game
state add a row*, not *does it look short*.

```gdscript
# root
var scroll := ScrollContainer.new()
scroll.anchor_right = 1; scroll.anchor_bottom = 1
scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED  # vertical only, normally
add_child(scroll)
var body := VBoxContainer.new()
body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
scroll.add_child(body)
```

### R2. NOTHING CRITICAL BELOW THE FOLD WITHOUT AN AFFORDANCE
A primary action ("Commit and fight", "End Week") must be reachable without the player guessing
that a region scrolls. Either pin it outside the scroll region, or make the scroll obviously
scrollable.

⚠️ **THERE IS NOW A COMPONENT THAT CANNOT GET THIS WRONG.** `UiTheme.commit_bar()` is a footer
that states what is being committed and carries the primary button. Add it as a **sibling** of
the `ScrollContainer`, never inside it:

```gdscript
var bar := UiTheme.commit_bar("5 monsters · 4 have a plan · costs 0g and 80 stamina", "Advance Week")
root_vbox.add_child(bar)                                  # sibling of the scroll, last child
UiTheme.commit_bar_button(bar).pressed.connect(_on_advance)
UiTheme.commit_bar_set(bar, "…", false, "Two of five have no plan")   # disables AND says why
```

The summary line is not flavour. This game asks the player to commit and then WATCH; that line
is the last chance to state what they are committing to, and it must be re-read from source
every time it changes — a stale summary above a live commit button is a rule-(1) lie in the
most expensive place on the screen.

### R3. NEVER A DEAD CONTROL WITH NO EXPLANATION
A disabled button must say why.

⚠️ **THE REASON IS NOW A REQUIRED ARGUMENT, NOT A DISCIPLINE.** `btn.disabled = true` is one
token and remembering the tooltip is a matter of memory nobody has consistently had. Use:

```gdscript
UiTheme.disable_with_reason(btn, "Locked — reach Iron league (you are Bronze)", true)
UiTheme.enable_control(btn)     # the inverse — clears the reason, so a stale one cannot survive
```

⚠️ **THE LABEL BEATS THE TOOLTIP, AND ROUND 18's PROBE SCORED THAT BACKWARDS.** `shop_ui.gd`
puts the reason in the visible text; the earlier probe read only `tooltip_text` and flagged its
two best buttons as violations. A keyboard user never hovers. `in_label = true` is the preferred
form. `_probe_house.gd` now counts the two channels **separately** and reports the label channel
as `maybe`, never as a pass — "the label states the reason" is a semantic question and a probe
cannot answer it. A row with a high `maybe` needs a human to read the capture; folding a guess
into a green number is how a guard stops being believed.

### R4. NO FIXED PIXEL HEIGHTS ON CONTENT THAT GROWS
`custom_minimum_size` is a FLOOR, not a size. A list of monsters, a log, a move set — all size to
their content and let the parent scroll.

### R5. TEST AT THE SMALL SIZE, NOT THE COMFORTABLE ONE
⚠️ **Verify at 1152×648, not 1280×800.** The bug reached the user because every screenshot was
taken at the size the screen was designed for.

⚠️ **AND THE WINDOW IS NOT THE VIEWPORT — `_probe_screens.gd` LEARNED THIS EXPENSIVELY.**
`project.godot` sets a 1920×1080 base viewport with `stretch/mode="canvas_items"`, so shrinking
the WINDOW scales the whole canvas: layout still happens at the base size. Its first run reported
every screen's content height as exactly 1080 and flagged all thirteen as clipping — the
instrument lying, not thirteen broken screens. Measure overflow against the **base viewport**.
The small-window question is a LEGIBILITY one and only a capture answers it.

### R6. NESTED SCROLL REGIONS NEED A REASON
A scroll inside a scroll traps the wheel and is a common frustration. One outer scroll plus
genuinely independent panes (a roster list beside a detail pane) is fine; three nested is a bug.

### R7. ⚠️ NEW — TYPE AND COLOUR COME FROM THE TOKENS, NOT FROM THE KEYBOARD
Every font size is one of `UiTheme.TOKEN_FONT_SIZES` (14 · 16 · 18 · 22 · 32). Every text colour
is one of `UiTheme.TOKEN_TEXT_COLOURS` (15 entries). Both arrays are published from `theme.gd`
**specifically so the probe can check them without keeping a second copy of the list** — a guard
with its own copy of the truth drifts from the truth it guards.

⚠️ **WIDENING THOSE ARRAYS WIDENS WHAT THE PROBE PERMITS.** Adding a token to make a red line go
away is not a fix; it is deleting the measurement.

---

## 3. What the probe found on 2026-08-11 (first run, all thirteen screens)

Fixture: one mid-career Bronze career, week 130, five monsters — the same one `_probe_screens.gd`
uses, on purpose, so the rows line up.

| rule | result |
|---|---|
| **R1** scrollable root | **1 screen fails — `title_ui`** (12 of 13 pass) |
| **R2** action reachable unscrolled | **1 screen fails — `report_ui`** |
| **R3** dead control with no reason | **0 silent** · 2 explained by label only (`shop_ui`, correctly) |
| **R6** nested scrolls | **0** — clean |
| **R7** off-scale font sizes | ⚠️ **135 labels**, and **118 of them are BELOW 14px** |
| **R7** off-token text colours | ⚠️ **111 labels across 29 invented colours** |

⚠️ **R7 IS THE FINDING.** The layout rules have essentially held; the house STYLE has not.
Concentrated almost entirely in the three screens that never adopted the theme —
`report_ui` (49 + 49), `tactics_ui` (42 + 28), `market_ui` (42 + 17).

**The sizes in use that the theme does not hand out:** 9px ×4 · 10px ×5 · 11px ×25 · 12px ×83 ·
13px ×1 · 15px ×11 · 24 · 26 · 30 · 34 · 40 · 56. `docs/ACCESSIBILITY.md` names 18px as the floor
for list-primary text; there are **83 labels at 12px**.

**The colours** cluster into near-duplicates of tokens that already exist: six greys within Δ0.15
of `TEXT_SECONDARY`/`TEXT_MUTED`, four warm ambers within Δ0.28 of `GOLD`. Nobody chose a new
palette; five authors each reached for "a grey" without a shared one to reach for.

⚠️ **ONE INSTABILITY, RECORDED HONESTLY.** The probe's very first (cold-import) run reported
`10_tournament` as failing R1 and R2; three subsequent runs report it passing, identically. Treat
a single anomalous row as a cold-cache artefact and re-run before acting on it.

---

## 4. Checklist before calling a screen done

- [ ] `_probe_house.gd` shows **yes / yes / 0 SILENT / nest 1 / 0 / 0** on its row
- [ ] Runs at **1152×648** with nothing cut off
- [ ] Runs at 1280×800
- [ ] Primary action reachable without scrolling — `UiTheme.commit_bar()` outside the scroll
- [ ] Every disabled control went through `UiTheme.disable_with_reason()`
- [ ] Keyboard: `focus_mode` on everything interactive, focus ring visible, `ui_accept` works
      (⚠️ `docs/ACCESSIBILITY.md` found a P0 where mouse-only `gui_input` locked keyboard users
      out of the game entirely — do not reintroduce it)
- [ ] Degrades deliberately when `Art.*` returns null — `UiTheme.portrait()` does this for you
- [ ] Uses `scripts/ui/theme.gd` tokens and components rather than hand-rolled `StyleBoxFlat`s
- [ ] **A capture was read back.** A screen reported "improved" without one has reported nothing.
