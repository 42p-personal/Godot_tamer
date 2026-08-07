# UI Theme — adoption guide

**One page. Read this, then adopt.** The theme lives in `monster-tamer/scripts/ui/theme.gd`
(preload it, no autoload) plus an optional `.tres` mirror at
`monster-tamer/assets/ui/guild_theme.tres`. Review every token and builder live in
`res://scenes/theme_gallery.tscn`.

**Why this exists:** every screen was built independently, each hand-rolling its own
`StyleBoxFlat`s, colours and font sizes inline. Nothing matched, and every new screen invented
the look again. This file is the fix — call the builder instead of inventing a new one.

---

## 1. Adopt it in three lines

```gdscript
const UiTheme = preload("res://scripts/ui/theme.gd")

func _ready() -> void:
    self.theme = UiTheme.base_theme()   # Buttons/Panels/ProgressBars/Labels/LineEdits/
                                          # OptionButtons all look right now, zero extra code
```

That one line fixes every *default* control on the screen. Anything hand-built (cards, bars,
chips) uses a specific builder below.

---

## 2. Before / after (a real example, lifted from `stable_ui.gd`)

**Before** (what's live today, repeated with small variations in `stable_ui.gd`,
`tactics_ui.gd`, `arena_3d.gd`, `training_ui.gd`, `report_ui.gd`):

```gdscript
var sb := StyleBoxFlat.new()
sb.bg_color = Color(0.16, 0.16, 0.21) if selected else Color(0.12, 0.12, 0.15)
sb.border_color = accent if selected else Color(0.22, 0.22, 0.26)
sb.set_border_width_all(2 if selected else 1)
sb.set_corner_radius_all(4)
sb.content_margin_left = 8; sb.content_margin_right = 8
sb.content_margin_top = 6; sb.content_margin_bottom = 6
panel.add_theme_stylebox_override("panel", sb)
```

**After:**

```gdscript
var sb := UiTheme.panel_style("raised" if selected else "default", accent)
panel.add_theme_stylebox_override("panel", sb)
```

Same visual intent, one shared source of truth, and the next screen that needs a card gets the
*exact* same panel for free instead of a fifth slightly-different grey.

---

## 3. The tokens

### Palette

| token | value | role |
|---|---|---|
| `SURFACE` | `#14141B` | window/root background |
| `PANEL` | `#1C1C24` | card/panel background |
| `PANEL_RAISED` | `#24242E` | hover/selected panel |
| `BORDER` / `BORDER_FAINT` | `#33333D` / `#26262E` | resting border / separator |
| `TEXT_PRIMARY` | `#F0F0F4` | **16.13:1** on `SURFACE` |
| `TEXT_SECONDARY` | `#A6A6B3` | **7.03:1** on `PANEL` |
| `TEXT_MUTED` | `#8C8C99` | **5.10:1** on `PANEL` — do not darken further without re-measuring |
| `GOLD` | `#D8B859` | **9.53:1** on `SURFACE` — the fixed heading/brand ink, never team colour |
| `SAFE` / `CAUTION` / `DANGER` | `#52C25C` / `#E0B340` / `#DE3D3D` | HP threat gradient (matches `arena_3d.gd` exactly) — `DANGER` is 4.23:1 on `SURFACE`, large text/fills/icons only |
| `FOCUS` | `#66D9FF` | **10.42:1** on `PANEL` — keyboard-focus ring, never reused for anything else |

Contrast ratios are hand-computed with the WCAG relative-luminance formula (same method
`docs/ACCESSIBILITY.md` used) — see `theme.gd`'s own comments for the full reasoning per token.
⚠️ **No execution environment was available while building this** (no Godot run, no
screenshot) — these are worked calculations, not tool-measured. Confirm with a real contrast
checker before treating a borderline value as final.

### Status vocabulary (new — first time these get concrete hex)

| category | colour | shape | statuses |
|---|---|---|---|
| hard control | `#F5E6B8` pale cream | diamond | stun, sleep, fear, confusion |
| DoT — poison | `#8CC63F` | circle | poison |
| DoT — burn | `#FF8A3D` | circle | burn |
| DoT — bleed | `#E0304A` | circle | bleed |
| DoT — doom | `#4A2E52` | circle | doom |
| utility | `#8C7A99` | hexagon | blind, silence, vulnerable, knockback, healblock, charm |
| buff | `#3FA8C0` | triangle | haste |

⚠️ **Proposed, not yet run through a real colourblind simulator** (Coblis/Sim Daltonism) —
`docs/ART_BIBLE_GUILD_COLOURS.md` asks for that pass before sign-off. `status_chip()` pairs
every hue with a distinct drawn shape specifically so the shape channel survives even if a hue
turns out to collide under simulation.

### Type scale, spacing, radii

`SIZE_DISPLAY 32 · SIZE_HEADING 22 · SIZE_SUBHEADING 18 (the accessibility floor) · SIZE_BODY 16
· SIZE_CAPTION 14`. `SPACE_XS 4 · SM 8 · MD 12 · LG 16 · XL 24 · XXL 32`. `RADIUS_SM 4 · MD 6 ·
LG 10`.

---

## 4. The builders

| call | returns | replaces |
|---|---|---|
| `UiTheme.base_theme()` | `Theme` | assign to a screen root once; styles every default control |
| `UiTheme.panel_style(variant, accent)` | `StyleBoxFlat` | every hand-rolled card/panel stylebox |
| `UiTheme.focus_style(base)` | `StyleBoxFlat` | a duplicate of `base` with the focus-ring border only |
| `UiTheme.heading(text, level)` | `Label` | section titles (was: a `Label` + two `add_theme_*_override` calls, repeated per screen) |
| `UiTheme.body_text(text, tier)` | `Label` | primary/secondary/muted body copy |
| `UiTheme.button_stylebox(kind, state)` | `StyleBoxFlat` | per-state button styling (primary/secondary/danger × normal/hover/pressed/disabled/focus) |
| `UiTheme.stat_bar(label, value, max, colour)` | `Control` | the STR/DEX/... bars in `stable_ui.gd` |
| `UiTheme.hp_bar(current, max)` | `Control` | **the arena HP fill — bakes the numeric value into the bar, fixes the colour-alone P0** |
| `UiTheme.team_chip(team_index, label)` | `Control` | badge + colour, contrast-guaranteed |
| `UiTheme.team_border_color(team_index, panel_bg)` | `Color` | **the iron-grey 2.60:1 border fail — this always clears 3:1** |
| `UiTheme.status_chip(status_name)` | `Control` | the arena's single-colour truncated status label |
| `UiTheme.ensure_contrast(fg, bg, min_ratio)` | `Color` | any caller-supplied colour (team colour, most often) drawn on a background this file doesn't control |
| `UiTheme.contrast_ratio(a, b)` | `float` | ad hoc contrast checks, e.g. in a gallery/test scene |

---

## 5. Two concrete accessibility fixes this unlocks

1. **`arena_3d.gd`'s HP bar is colour-only today** (`docs/ACCESSIBILITY.md` finding #2, the
   single highest-value item in that audit). Swap its fill-drawing for `UiTheme.hp_bar()` and
   the numeric value is baked in structurally — it cannot be colour-only again.
2. **The iron-grey team's nameplate border measures 2.60:1**, below the SC 1.4.11 floor
   (`docs/ACCESSIBILITY.md` finding #6). Replace a raw `Art.team_colour(i)` border with
   `UiTheme.team_border_color(i, panel_bg)` and every one of the 8 liveries is guaranteed ≥3:1
   against whatever panel it's drawn on, without editing `art.gd`'s shared palette.

Neither fix requires touching `art.gd` or any screen script directly from this stream — they're
one-line swaps for whichever stream owns `arena_3d.gd` to make.

---

## 6. What's still missing (flagged, not solved here)

- **No display/slab font is packaged yet.** `heading()` approximates "ringside signage"
  (`docs/ART_THEME.md` §4) with the built-in font at larger size + `GOLD` ink. Drop an OFL slab
  face (e.g. Bitter, Zilla Slab, Spectral) into `assets/ui/fonts/` and change `heading()`'s
  `Label` to use a `FontFile` — every screen's headings pick it up at once.
  This is only stated to be "next" — the actual sourcing/licensing choice is a decision the
  studio should make deliberately, not one to smuggle in as a side effect of this file. Flagged
  as an open follow-up, not decided here.
- **No league-material chrome yet** (`docs/ART_BIBLE_GUILD_COLOURS.md` §5: panel framing should
  eventually borrow the *current* league's material register — timber grain at Wood, brushed
  white metal at Platinum). Deferred until more leagues have venue art to borrow from, per that
  document's own sequencing.
- **`status_chip()`'s icon is a flat geometric placeholder**, not the authored icon set
  `docs/ART_THEME.md` §3 calls for. The grouping/shape/colour *logic* is correct and ready;
  swapping in real linework later needs no call-site changes.
- **No colourblind-simulator pass on the new status hues** — see §3 above.
- **No execution/screenshot verification this session** — no Godot run, no `game_screenshot`,
  no `run_contract.sh` were available in this session's toolset. Everything here is built and
  hand-reviewed but not run. Run `theme_gallery.tscn` and `run_contract.sh` before trusting this
  in a shipped scene.

---

## 7. What NOT to do

- Don't hand-roll a new `StyleBoxFlat` for a panel/card/button — call the builder.
- Don't invent a new grey — `SURFACE`/`PANEL`/`PANEL_RAISED` cover every layer already in use.
- Don't draw a team colour directly for a border — use `team_border_color()`.
- Don't draw HP or any 0..max quantity as colour alone — use `hp_bar()`/`stat_bar()`.
- Don't add a new status without an entry in `UiTheme.STATUS_META` — an unlisted status falls
  back to the utility/grey family, which is a silent downgrade, not a crash, so it's easy to
  miss.
