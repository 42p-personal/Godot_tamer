# UI Theme — adoption guide

**One page. Read this, then adopt.** The theme lives in `monster-tamer/scripts/ui/theme.gd`
(preload it, no autoload) plus an optional `.tres` mirror at
`monster-tamer/assets/ui/guild_theme.tres`. Review every token and builder live in
`res://scenes/theme_gallery.tscn`.

**Why this exists:** every screen was built independently, each hand-rolling its own
`StyleBoxFlat`s, colours and font sizes inline. Nothing matched, and every new screen invented
the look again. This file is the fix — call the builder instead of inventing a new one.

---

## 0. Where adoption actually stands (measured 2026-08-11)

⚠️ **THE THEME SHIPPED AND THEN HALF THE SCREENS NEVER CALLED IT.** Not a design failure — an
adoption one, and it is measurable.

| screens | `UiTheme` references | `StyleBoxFlat.new()` |
|---|---|---|
| stable · town · ending · tournament · breeding · lab · training · feeding · shop | 18–82 each | 0–3 |
| **`tactics_ui` · `report_ui` · `market_ui` · `title_ui` · `sandbox_ui` · `battle_ui` · `arena_view`** | ⚠️ **0** | 0–7 |

`report_ui.gd` is **1,555 lines** and `tactics_ui.gd` **684** — the two screens carrying the
scouting read and the post-fight verdict, the two places the game's whole "preparation is the
skill, observation is the reward" promise is cashed, are the two that never adopted the house
style. Between them and `market_ui` they carry **62 distinct inline `Color(...)` literals**,
where the theme defines 15, and **font sizes 10/11/12/13/15/24/26/30/34** where the theme hands
out 14/16/18/22/32.

`scripts/_probe_house.gd` measures this at runtime across all thirteen screens; its first-run
numbers and the per-screen table are in `docs/UI_LAYOUT_RULES.md` §3. **111 labels are painted in
one of 29 invented colours** and **118 labels sit below 14px**.

⚠️ **THE COLOURS ARE NEAR-DUPLICATES, NOT A RIVAL PALETTE.** Six greys within Δ0.15 of
`TEXT_SECONDARY`/`TEXT_MUTED`; four ambers within Δ0.28 of `GOLD`. Nobody chose a second look —
five authors each reached for "a grey" without a shared one to reach for. That is the exact
failure §5's before/after describes, still live.

⚠️ **AND ONE CASE WHERE THE THEME IS BEING USED AGAINST ITSELF.** `town_ui.gd:644` fills a mood
bar with `UiTheme.FOCUS`, whose own comment reads *"never reused for anything else"* — a focus
ring drawn next to it is no longer the only cyan on the screen. `town_ui.gd:83` also derives the
hub's whole chrome accent from `Art.team_colour(0)`, which is the league/team/status collision
`docs/ART_THEME.md` forbids: the town's colour is currently decided by an unrelated system.
Both are in files this stream does not own — flagged for the integrator, not fixed here.

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

## 4b. The shared components (added 2026-08-11) — sections 9–14 of the gallery

⚠️ **THIS SECTION EXISTS BECAUSE FILE OWNERSHIP MANUFACTURED THE DUPLICATION, AND THE CODE SAYS
SO IN ITS OWN COMMENTS.** `market_ui.gd:445` carries the line: *"duplicated from `stable_ui.gd`'s
`_portrait` rather than shared, since that file is out of this stream's scope to edit or
refactor."* There are **five** independent `_portrait` implementations in `scripts/ui/` (stable,
market, report, tactics, ending) with **three different signatures**, and **seven** screens that
name a monster while showing no portrait at all. Every one of those authors was right about the
ownership rule; what was missing was a shared place to put it.

⚠️ **THE HARD RULE FOR ALL OF THEM: A COMPONENT RENDERS, IT NEVER DERIVES.** Nothing in §8 of
`theme.gd` reads `Career`, `Roster`, `WeekLib` or a `MonsterInstance`. Callers pass values they
have already read from the system that owns them. This is the structural form of the project's
rule (1) — *a screen must not lie about the thing it describes*: a second copy of the week's
maths cannot grow in a file that cannot see the week. The only exception is `Art` (portraits),
which is an asset lookup, not a rule.

| call | what it is for | the failure it makes unrepeatable |
|---|---|---|
| `portrait(species_id, name, size, accent)` | one creature portrait, with the accent-tinted initials placeholder at the SAME footprint | five copies with three signatures; layout jumping when art lands mid-session |
| `monster_card(info, opts)` | THE "here is a monster" shape — portrait · name · subtitle · state note · chips · trailing slot | seven screens naming a monster with no portrait, while 65 real portraits ship |
| `stat_bar(label, value, ceiling, fill, label_w, hard_max)` | ⚠️ **now draws a CAP MARKER** — fill, a tick at this monster's ceiling, and the unreachable scale as a dead band | one bar showing one "max" while another screen shows a different, equally true "max" |
| `delta_chip(amount, unit, good_is_up, decimals)` | "what changed" — `▲ +9 STR`, `▼ −15 stamina`, `• no change` | a week that resolved and left no trace on screen |
| `comparison_row(label, left, right, verdict, winner)` | "which of these two", with the difference SPELLED OUT | five breeding rows all reading `potential ×1.00 · Wild stock — Gen 1` |
| `empty_state(title, body, action)` + `empty_state_button()` | what a region says when it holds nothing | the town at 52% empty black, indistinguishable from a screen that failed to load |
| `disable_with_reason(btn, reason, in_label)` / `enable_control(btn)` | the only sanctioned way to disable a control | UI_LAYOUT_RULES R3 as prose nobody could enforce |
| `commit_bar(summary, action)` + `commit_bar_button/_summary/_set()` | the pinned commitment footer, a SIBLING of the scroll | no commit button findable on the tactics screen at 1152×648 |
| `TOKEN_FONT_SIZES` / `TOKEN_TEXT_COLOURS` / `is_token_colour()` | the published token sets `_probe_house.gd` checks against | a guard keeping its own copy of the truth and drifting from it |

### The cap marker, specifically

⚠️ **A ProgressBar HAS ONE QUANTITY; A TRAINED STAT HAS THREE.** Where it is, where *this*
monster can get to, and how wide the scale runs. `stat_bar()` now draws all three: fill, a
full-height tick at `ceiling`, and everything past it as a visibly dead band.

⚠️ **AND A CORRECTION TO WHAT THIS WAS BUILT FOR.** Round 18 reported the stable reading
`115 / 540` and training reading `115 / 400` for the same stat in the same week, and read it as
two copies of the maths. It is not — `stable_ui.gd:626` and `training_ui.gd:215` both call
`WeekLib.stat_ceiling(m, Career.current_stat_cap(), stat)`, identical inputs, identical function.
The contradiction is between the flat **league cap** in a header and the **per-monster ceiling**
on a bar, both of which are true and both of which the UI called "ceiling". That is a labelling
failure, not a duplication one — and it is why the fix is a bar that shows both at once rather
than a hunt for a second implementation. **Callers must still read `ceiling` from the system that
owns it; passing a league cap because it was easier to reach is the bug, dressed differently.**

Existing two-argument callers (`stable_ui`, `training_ui`, `town_ui`) are unchanged: with
`hard_max` unset there is no dead band and no tick, exactly as before.

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
- ~~**No execution/screenshot verification this session**~~ — ✅ **CLEARED 2026-08-11.** The
  gallery was run in a real window at 1152×648, all fourteen sections captured to
  `user://house/gallery_NN.png` and read back; `./run_contract.sh` PASSES. Two defects were found
  *in the captures* and fixed there: a trailing slot on `monster_card` that wrapped over three
  lines and slid off the card edge (`body_text` sets `AUTOWRAP_WORD`, right for a paragraph and
  wrong for a price), and a `delta_chip` whose `good_is_up` semantics were documented backwards.
  Neither was findable by reading the code.
- **The un-adopted screens are still un-adopted** — §0. The components exist; `report_ui`,
  `tactics_ui` and `market_ui` do not yet call them, and that conversion is not this stream's to
  make. The measurable target is `_probe_house.gd`'s last two columns reaching zero.
- **`TutorialOverlay` overlaps the bottom action rail**, including in the theme gallery's own
  capture, where it covered the commit bar's button. Independently reproduced here; it is a
  tutorial-layer fix, not a theme one.

---

## 7. What NOT to do

- Don't hand-roll a new `StyleBoxFlat` for a panel/card/button — call the builder.
- Don't invent a new grey — `SURFACE`/`PANEL`/`PANEL_RAISED` cover every layer already in use.
- Don't draw a team colour directly for a border — use `team_border_color()`.
- Don't draw HP or any 0..max quantity as colour alone — use `hp_bar()`/`stat_bar()`.
- Don't add a new status without an entry in `UiTheme.STATUS_META` — an unlisted status falls
  back to the utility/grey family, which is a silent downgrade, not a crash, so it's easy to
  miss.
- **Don't hand-roll a portrait, a monster row, a stat bar, an empty region or a commit footer** —
  §4b. Five `_portrait`s is the evidence that "I'll just do it locally" compounds.
- **Don't write `btn.disabled = true`.** Use `disable_with_reason()`; the reason is a required
  argument precisely so it cannot be forgotten.
- **Don't widen `TOKEN_FONT_SIZES` or `TOKEN_TEXT_COLOURS` to quiet the probe.** That is deleting
  the measurement, not passing it.
- **Don't let a component derive a game number.** Pass what you read from the system that owns
  it. `theme.gd` cannot see `Career`/`Roster`/`WeekLib` and that is deliberate.
