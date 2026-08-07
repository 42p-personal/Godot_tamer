# Interaction Pattern Library — Monster Tamer (Godot rebuild)

**2026-08-04.** Phase 1a of the UI team's audit pipeline. This document is reverse-engineered
from the 18 Godot screens that already exist and work (`monster-tamer/scripts/ui/*.gd`), not
authored from theory. Its purpose: give the audit phase that follows a pattern library to check
consistency against. Where a screen deviates from a pattern every other screen follows, that is
logged in the Appendix, not silently fixed here.

Source of truth for every token cited below: `monster-tamer/scripts/ui/theme.gd` ("UiTheme").
Binding layout rules: `docs/UI_LAYOUT_RULES.md`. Accessibility floor: `docs/ACCESSIBILITY.md`.

---

## 1. Design tokens

All from `theme.gd`, never hand-picked per screen:

- **Colour** — `SURFACE`/`PANEL`/`PANEL_RAISED`/`BORDER` (chrome), `TEXT_PRIMARY`/`SECONDARY`/
  `MUTED` (three text tiers, each with a measured contrast ratio in the source comments), `GOLD`
  (brand ink, NOT team colour), `SAFE`/`CAUTION`/`DANGER` (threat gradient), the status
  vocabulary block, `FOCUS` (its own hue, never reused for selection or status).
- **Type scale** — `SIZE_DISPLAY`(32) → `SIZE_CAPTION`(14), with `SIZE_SUBHEADING`(18) marked
  explicitly as the accessibility floor. Any inline `add_theme_font_size_override` with a number
  not on this list is a magic number and should be treated as drift.
- **Spacing/radii** — `SPACE_XS`(4) → `SPACE_XXL`(32), `RADIUS_SM/MD/LG`.

**Use these constants, not literals.** A screen that writes `add_theme_constant_override
("separation", 10)` instead of `UiTheme.SPACE_SM` (8) or `SPACE_MD` (12) has invented a value
that matches nothing and cannot be swept when the token changes.

---

## 2. Panel / card pattern

`UiTheme.panel_style(variant, accent)` — `"default"` (resting card), `"raised"` (hover/selected,
wider border + lighter fill), `"flat"` (no border, full-bleed background).

**Canonical example:** `stable_ui.gd` roster cards. **Correct use elsewhere:** `breeding_ui.gd`,
`tournament_ui.gd`. **Drift:** several screens build their own `StyleBoxFlat` for what is
functionally the same card — see Appendix §A.2.

---

## 3. Sticky action rail

The primary action for a screen (Advance Week, Commit and fight, Enter tournament) is pinned
**outside** the scroll region, never inside it — `docs/UI_LAYOUT_RULES.md` rule 2 ("nothing
critical below the fold without an affordance") is the origin of this rule.

**Canonical example:** `stable_ui.gd`, literally commented `# ── sticky action rail: rule 2 —
the primary action is pinned OUTSIDE the scroll ───`. The "Advance Week" button and its cost
label sit after the scroll container, always visible. **Also correct:** `training_ui.gd`,
`tournament_ui.gd`, `tactics_ui.gd` (commit button + lock state).

**Rule of thumb:** if a screen has exactly one action that ends the screen's purpose (advance,
commit, confirm), that action is a sticky rail candidate. A screen with several equally-weighted
actions (a shop, a market) does not need one.

---

## 4. Disabled-button-with-reason

**Never a dead button with no explanation.** When a button is disabled, its own label text is
rewritten to state *why*, not just greyed out silently.

Confirmed at every one of these sites — `.disabled = true` is always paired with a `.text`
rewrite in the same branch:

| screen | condition | button text |
|---|---|---|
| `tournament_ui.gd:138-141` | not enough monsters | `"Need %d monsters — you have %d"` |
| `shop_ui.gd:111-119` | barn at cap / can't afford | `"Barn is at its largest (%d)"` / `"...need %d more)"` |
| `shop_ui.gd:147-159` | already owned / league-locked / can't afford | `"✓ Held"` / `"Locked — reach %s league..."` |
| `training_ui.gd:149-156` | chosen / can't afford | `"✓ %s"` / `"%s — can't afford"` |
| `training_ui.gd:278-284` | not allowed / already booked | reads the note's own reason string / `"✓ Booked for this week"` |
| `breeding_ui.gd:157-213` | retired from stud book / barn full / can't afford / self-pairing | four distinct reasons, each spelled out |

**This is the pattern to follow for every future disabled control.** Note in Appendix §A.3: no
site currently *also* sets `tooltip_text` — worth deciding whether button-text-only is
sufficient, or whether long reason strings that could truncate at small window widths need a
tooltip as backup.

---

## 5. Stat-bar-against-a-cap

`UiTheme.stat_bar(label, value, max_value, colour, label_width)` and `UiTheme.hp_bar(current,
max)` — both **always** render the numeric value as text baked into the bar, never colour/fill
fraction alone. This is the structural fix for `ACCESSIBILITY.md` §0 finding #2 (the
colour-alone HP read).

**Canonical example:** `stable_ui.gd:301,415,419` — stat bars read against
`GameData.stat_cap()`, which is explicitly the *current league's* cap (Wood 100 → Tamers Apex
1100), not a flat placeholder. The comment at `stable_ui.gd:409` states this directly so a
future reader doesn't mistake the cap for a constant.

⚠️ **`hp_bar()` is not yet used on the live battle screen.** `arena_3d.gd` still renders HP as a
flat colour fill with no baked-in number — see Appendix §A.3 (arena_3d.gd theme adoption)
`ACCESSIBILITY.md` already flagged as P0 #2, now cross-referenced as a *pattern* violation, not
just an accessibility finding.

---

## 6. Status chip

`UiTheme.status_chip(status_name)` — pairs a category colour with a **distinct drawn shape**
(diamond/circle/hexagon/triangle) and a text abbreviation, so the read survives a CVD colour
collision on shape and text alone. `STATUS_META` maps every authored status to a category;
unknown statuses degrade to the neutral/hexagon family rather than erroring.

**Built correctly, but only in the disconnected screen:** `arena_view.gd`'s `STATUS_META` table
matches this design and predates `theme.gd` formalising it. **The live battle screen
(`arena_3d.gd`) does not use it** — its status label is one flat colour for every status kind,
differentiated only by a 4-character truncation at 8px. This is the single highest-value port
still outstanding for this pattern (see Appendix §A.3).

---

## 7. Team identity chip

`UiTheme.team_chip(team_index, label)` and `team_border_color(team_index, panel_bg)` — colour
and badge glyph **always together**, contrast-guaranteed via `ensure_contrast()`. Per
`art.gd`'s own rule: colour alone is never sufficient team identification (three of eight
liveries collapse to the same olive hue under deuteranopia/protanopia — `ACCESSIBILITY.md` §1.2).

**Correct at every site that asserts team identity**, per the `ACCESSIBILITY.md` §2 call-site
audit: `stable_ui.gd:30`, `arena_3d.gd:359` (`_make_plate`), `report_ui.gd:140,144,164,165`,
`arena_view.gd:297,506`. `title_ui.gd:60` deliberately avoids team colour with a comment
explaining why (no team context on that screen) — a model for reasoning about the exception, not
a violation of it.

**Two flagged exceptions**, carried into the Appendix: `tactics_ui.gd`'s hardcoded yours/rival
blue-red pair (not a defect today, since it's always paired with header text, but independent of
the real `TEAM_COLOURS` palette), and `arena_3d.gd:316`'s one `team_colour()`-alone call on a
placeholder sprite tint.

---

## 8. Keyboard focus & activation

Every interactive control gets `focus_mode = Control.FOCUS_ALL`; `Button`/`OptionButton` nodes
get this by default and are correctly keyboard-operable project-wide with zero extra code
(confirmed across `stable_ui.gd`, `tactics_ui.gd`, `training_ui.gd`, `arena_3d.gd`,
`report_ui.gd`, `title_ui.gd`). `UiTheme.focus_style(base)` duplicates a control's own stylebox
and overrides **only** the border to the dedicated `FOCUS` colour at 3px — focus must be visibly
distinct from a "selected" treatment, never the same border wider (`ACCESSIBILITY.md` §7, SC
2.4.7).

⚠️ **A bare `PanelContainer` with `.gui_input` wired for mouse only would have no `focus_mode`
and no keyboard-equivalent activation at all** — the pattern's total absence, not a style choice
inside it. **No site in this codebase currently does that.** An earlier draft of this document
claimed two did; that claim was false and is retracted in Appendix §A.1. Every `gui_input` call
site here pairs the mouse path with `focus_mode = FOCUS_ALL` and a `ui_accept` branch. Keep it
that way — and verify against the handler, not the call site, before reporting otherwise.

---

## 9. Non-blocking overlay / hint pattern

`tutorial_overlay.gd` — the canonical example. A `CanvasLayer` autoload, `layer = 100`, whose
**root and every non-interactive child** set `mouse_filter = Control.MOUSE_FILTER_IGNORE`; only
the "Skip the guide" button accepts input. The file's own header comment names the failure mode
this prevents: the v0.79 z-index scrim bug that buried every button under a backdrop that
visually looked fine but silently ate every click underneath it.

**Rule for any future overlay, banner, or hint layer:** set `mouse_filter = IGNORE` on the root
and every label/decoration; opt IN only the specific controls meant to be clickable. Never the
reverse (default-clickable, opt out the decorations) — that is exactly how the original bug
shipped.

---

## 10. Scroll-root pattern

Every screen's root is a `ScrollContainer` wrapping a `VBoxContainer` body
(`docs/UI_LAYOUT_RULES.md` rule 1) — no fixed pixel heights on growing content (rule 3), verified
at 1152×648 not just the comfortable 1280×800 (rule 4), and nested scroll regions need a specific
reason, not just convenience (rule 5). `stable_ui.gd:117-145` is the reference implementation:
one outer `ScrollContainer` (vertical only) plus a genuinely independent split pane (roster list
beside detail panel) — the documented exception to "no nested scrolling," not a violation of it.

---

## 11. Empty / zero-state pattern

State the cause and the next action, never a bare "N/A" or an empty list with no explanation.

**Canonical example:** `stable_ui.gd:656` — `"No monsters yet — buy one at the Market before
advancing the week."` States what's missing (monsters) and where to fix it (the Market), and
disables the dependent action (`_advance_btn.disabled = true`) in the same branch, consistent
with §4's disabled-button-with-reason pattern.

---

## Appendix — Drift found (ranked by severity, seed for the audit phase)

### A.1 — ⚠️ WITHDRAWN: the claimed P0 regression DOES NOT EXIST

**This entry originally asserted, as BLOCKING, that the keyboard-lockout P0 had regressed at
`stable_ui.gd` and `tactics_ui.gd`. That was FALSE and is retracted. Both sites are correctly
fixed and carry comments citing the fix.** Verified by reading the code rather than the doc:

| site | what is ACTUALLY there |
|---|---|
| `stable_ui.gd:258` | `panel.focus_mode = Control.FOCUS_ALL`, `gui_input` handling **both** `InputEventMouseButton` **and** `ui_accept`/`ui_select`, plus `focus_entered`/`focus_exited` repainting the focus ring so it appears the instant Tab lands — not only after Enter |
| `tactics_ui.gd:312` | identical treatment, plus `grab_focus()` on click so mouse and keyboard converge on the same state |
| `arena_3d.gd:665` | also fine — keyboard path handled in `_unhandled_input`, documented inline |

`stable_ui.gd`'s own comment explains why these are focusable `PanelContainer`s rather than
`Button`s: **the whole card surface — portrait, name, class, chip — needs to be the hit target.**
That is a deliberate, documented choice, not drift.

⚠️ **The lesson is the reason this entry is kept rather than deleted.** The claim was generated by
pattern-matching `gui_input` call sites without reading their handlers, then stated with high
confidence and a severity rating. It was relayed onward as fact and briefed into a downstream
accessibility audit, which opened by citing it as evidence that *"this team's findings get dropped
rather than fixed"* — an inference built entirely on a false premise.

**This is the failure mode `CLAUDE.md` and this project's own memory already warn about:** *grep
before believing a doc claim that a mechanic is missing — three were false in one sweep.* A
confident wrong finding is more expensive than no finding, because it gets acted on. **Verify a
claim against the code before assigning it a severity.**

### A.2 — Consistency debt: hand-rolled `StyleBoxFlat` / magic-number spacing instead of `UiTheme`

140 occurrences of inline `StyleBoxFlat.new()` or a hardcoded `add_theme_constant_override
("separation", N)` across 12 of 19 UI files, despite `theme.gd` existing specifically to
centralise this. None of these lock anyone out — they are style/consistency debt, the kind the
studio owner's brief calls "make this look polished," not the kind that blocks play. Sequence a
follow-up pass by this ranking, worst first:

| file | occurrences | reachable from a menu today? | priority for a follow-up pass |
|---|---|---|---|
| `arena_view.gd` | 23 | **No** (`ACCESSIBILITY.md` confirms nothing calls `change_scene_to_file` to it) | Low — dead code path until reconnected |
| `tactics_ui.gd` | 20 | Yes, live | **High** — live screen, second-highest count |
| `arena_3d.gd` | 19 | Yes, live — the most-watched screen in the game | **Highest** — live, highest-traffic screen with a real count |
| `sandbox_ui.gd` | 18 | Yes (dev/testing screen) | Medium — lower player-facing stakes |
| `report_ui.gd` | 13 | Yes, live | High |
| `market_ui.gd` | 13 | Yes, live | High |
| `battle_ui.gd` | 12 | **No** (same non-reachable status as `arena_view.gd`) | Low |
| `deployment_board.gd` | 5 | Yes, live | Medium |
| `stable_ui.gd` | 4 | Yes, live | Low — small count, already the pattern's own reference implementation elsewhere in this doc |
| `title_ui.gd` | 2 | Yes, live | Low |
| `theme_gallery.gd` | 3 | Dev-only demo screen | N/A — expected to hand-roll for comparison purposes |
| `theme.gd` | 8 | — | N/A — this *is* the builder source; these are its own internals, not drift |

**Recommended sequencing:** `arena_3d.gd` and `tactics_ui.gd` first (live + highest counts),
`report_ui.gd`/`market_ui.gd` next, then `deployment_board.gd`. Leave `arena_view.gd`/
`battle_ui.gd` until (or unless) they're reconnected to the navigation graph — consolidating a
dead screen's styling is wasted effort until it's live again.

### A.3 — Minor: disabled-button-with-reason has no secondary channel

No site in §4 pairs its rewritten button text with a `tooltip_text`. Not a failure today (the
text itself is always visible, satisfying the no-colour-alone spirit of the rule) — flagged
because a long reason string at a small window width could truncate before a player reads the
reason, and a tooltip is the cheap backstop. Low priority; revisit if truncation is ever observed
at the 1152×648 floor `UI_LAYOUT_RULES.md` mandates testing at.

### A.4 — Minor: team-identity exceptions

`tactics_ui.gd`'s hardcoded yours/rival colour pair is independent of `Art.TEAM_COLOURS` and
won't visually match a team's real livery once tournament seating uses this screen in a team
context — not an accessibility defect (always paired with header text), but a visual-consistency
question for `art-director`/`ui-programmer`. `arena_3d.gd:316` is the one `team_colour()`-alone
call site (placeholder sprite tint); harmless today since the adjacent nameplate always carries
the badge, but becomes colour-alone the moment nameplates become toggleable. One-line fix
(`team_identity(...)["colour"]`), not urgent.

### A.5 — Not drift, but load-bearing to say: the status-chip pattern (§6) and the hp_bar numeric-value pattern (§5) are both *built correctly* but **not yet deployed on the live battle screen**, `arena_3d.gd`. This is the same screen flagged worst in §A.2, which makes it the single highest-leverage screen for the audit phase to prioritise across every pattern in this document, not just the stylebox count.
