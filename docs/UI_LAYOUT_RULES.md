# UI layout rules — the fix for clipping

**2026-08-04.** Binding on every screen. Written after the user reported: *"currently the game
clips"* — with a screenshot of The Read cut off mid-deployment-board.

---

## The diagnosis

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

## The rules

### 1. ⚠️ EVERY SCREEN'S ROOT IS SCROLLABLE
A screen is a `ScrollContainer` wrapping its content, or it clips. No exceptions, however short
the screen looks today — content grows (a roster gains monsters, a log gains lines, a stat block
gains the new personality axes) and the screen that fitted last week will not next week.

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

### 2. NOTHING CRITICAL BELOW THE FOLD WITHOUT AN AFFORDANCE
A primary action ("Commit and fight", "End Week") must be reachable without the player guessing
that a region scrolls. Either pin it outside the scroll region, or make the scroll obviously
scrollable.

### 3. NO FIXED PIXEL HEIGHTS ON CONTENT THAT GROWS
`custom_minimum_size` is a FLOOR, not a size. A list of monsters, a log, a move set — all size to
their content and let the parent scroll.

### 4. TEST AT THE SMALL SIZE, NOT THE COMFORTABLE ONE
⚠️ **Verify at 1152×648, not 1280×800.** The bug reached the user because every screenshot was
taken at the size the screen was designed for. A screen that only works at its authoring size is
not finished.

### 5. NESTED SCROLL REGIONS NEED A REASON
A scroll inside a scroll traps the wheel and is a common frustration. One outer scroll plus
genuinely independent panes (a roster list beside a detail pane) is fine; three nested is a bug.

---

## Checklist before calling a screen done

- [ ] Runs at **1152×648** with nothing cut off
- [ ] Runs at 1280×800
- [ ] Primary action reachable without scrolling, or clearly signposted
- [ ] Keyboard: `focus_mode` on everything interactive, focus ring visible, `ui_accept` works
      (⚠️ `docs/ACCESSIBILITY.md` found a P0 where mouse-only `gui_input` locked keyboard users
      out of the game entirely — do not reintroduce it)
- [ ] Degrades deliberately when `Art.*` returns null
- [ ] Text at or above the minimum sizes in `docs/ACCESSIBILITY.md`
- [ ] Uses `scripts/ui/theme.gd` tokens rather than hand-rolled `StyleBoxFlat`s
