# Accessibility Standard — Monster Tamer

**2026-08-04.** First accessibility pass on the Godot vertical slice (`monster-tamer/`). Scope:
the live navigation loop — `title.tscn → stable.tscn → tactics.tscn → arena3d.tscn → report.tscn`
— plus `scripts/art.gd`, the asset registry and team-identity contract everything else reads.
`scenes/arena.tscn` / `scripts/ui/arena_view.gd` and `scenes/battle.tscn` / `battle_ui.gd` are
**not reachable from any menu today** (confirmed by grep — nothing calls
`change_scene_to_file("res://scenes/arena.tscn")` or `"...battle.tscn"`); they're audited only
where they reveal something the *live* screen got wrong by comparison (§3.3).

⚠️ **Standing rule for this file, same as every other design doc in the repo**: this is the
standard, not a changelog of what one session found. Update it in place as the UI is rebuilt;
don't let it drift the way `ART_THEME.md` records other docs drifting. Target: **WCAG 2.1 Level
AA**, game-specific rules layered on top per this project's `CLAUDE.md`.

**Why this project's bar is higher than usual**, stated once so every section below can assume
it: (1) the game encodes information in colour across **three systems that must never collide**
— league material, team colour, status/threat (`ART_THEME.md`, `ART_BIBLE_GUILD_COLOURS.md`) —
so a colourblind player who loses one channel loses real gameplay information, not polish; and
(2) the player **never intervenes in a fight** (`CLAUDE.md`) — watching the arena screen *is*
the entire second half of the game loop, so a readability failure there is total, not an
inconvenience. *"An unreadable fight is not a hard fight, it is a slot machine."*

---

## 0. The prioritised split, up front

Fourteen findings below; six are load-bearing (**P0/P1**), the rest are real but not urgent
(**P2**). Read this table first; the rest of the document is the evidence for it.

| # | finding | class | severity |
|---|---|---|---|
| 1 | Roster-card and rival-mark selection have **no keyboard path at all** — `PanelContainer.gui_input` mouse-only, not a `Button`, no `focus_mode` | Motor / Input | **P0 — blocking** |
| 2 | The live HP bar (arena3d.gd) encodes danger **in colour alone** — green→amber→red, no number, no icon, no pattern | Visual (colour-alone) | **P0 — blocking** |
| 3 | Nameplate name (9px) and status text (8px) are roughly **half** the 18px minimum, and the leash-radius removal (in flight) makes the whole scene sparser, not denser | Visual (text scale) | **P1 — high** |
| 4 | Three of eight `TEAM_COLOURS` (oxblood, brass, tan leather) **collapse into one indistinguishable olive-yellow hue** under deuteranopia/protanopia — simulated, see §1 | Visual (colourblind) | **P1 — high**, mitigated by the badge (see §2) |
| 5 | Crit vs. non-crit floating damage numbers are **colour-only** (gold vs. salmon), same font size, no symbol | Visual (colour-alone) | **P1 — high** |
| 6 | Iron-grey team nameplate border measures **2.60:1** against its panel background — fails SC 1.4.11 (3:1 minimum) for a non-text UI element | Contrast | **P1 — high** |
| 7 | `arena_3d.gd`'s live status label uses **one flat colour for every status kind**, differentiated only by a 4-character truncation of the raw status string at 8px | Visual / Cognitive | **P1 — high** |
| 8 | `Art.team_colour()` called without its badge at one site (`arena_3d.gd:316`, placeholder-sprite tint) | Visual (colour-alone), narrow | P2 — polish |
| 9 | Oxblood/plum team borders sit at 3.12–3.13:1 — pass, but with **no margin** | Contrast | P2 — polish |
| 10 | No reduced-motion / reduced-flash option for hit-flash and floating-number tweens | Motion / photosensitivity | P2 — polish (not currently dangerous, see §6) |
| 11 | No settings/options screen of any kind exists yet — no text scale, no colourblind filter, no remap, no volume | Structural | P2 — polish *now*, becomes P0 the moment any of §1–§7 is "fixed" by a toggle rather than a redesign |
| 12 | Audio accessibility (subtitles, volume sliders, mono) — **not applicable**, no audio system exists in this slice yet | Audio | N/A — track for when audio lands |
| 13 | Gamepad — not implemented project-wide (documented decision, `technical-preferences.md`) | Input | N/A — out of current scope, note for later |
| 14 | `Button`/`OptionButton` controls (Train, Commit, speed toggles, all order selectors) **are** correctly keyboard-operable by default | — | Pass, noted so the audit isn't read as "everything is broken" |

**The single most important fix: #1, the keyboard lockout on monster/rival selection.**
Reasoning in §7 — it is the only finding here that is a *complete* block rather than a
*degraded* experience, and it sits upstream of every other finding: a keyboard-only or
switch-input player cannot select a monster in the Stable at all, so they never even reach the
arena screen to be affected by findings #2–#7.

---

## 1. Colourblind audit — the three colour systems, simulated

Method: the standard simplified RGB-space CVD approximation (the linear transform used by
Coblis/`daltonize`-class simulators — not a full LMS cone-response model, but reliable for
catching the collisions that matter for a design decision). All source values are the literal
floats in `scripts/art.gd` and `scripts/ui/arena_3d.gd`, converted to sRGB 0–255 before
transform. Treat the RGB triples below as indicative, not pixel-exact; re-run through a proper
simulator (Coblis, Sim Daltonism) before signing off art commissioned against these numbers.

### 1.1 The HP threat gradient — arena_3d.gd `_apply_frame`

```
danger (<25%):  Color(0.87, 0.24, 0.24)  → #DE3D3D  (222, 61, 61)
caution (<50%): Color(0.88, 0.70, 0.25)  → #E0B340  (224,179, 64)
safe (≥50%):    Color(0.32, 0.76, 0.36)  → #52C25C  ( 82,194, 92)
```

⚠️ **This is the "classic failure" the brief named, and the simulation confirms it directly.**

| condition | normal vision | **deuteranopia (sim)** | **protanopia (sim)** | **tritanopia (sim)** |
|---|---|---|---|---|
| danger | red #DE3D3D | **#A2AE3D** — olive/mustard | **#98973D** — olive/mustard | #D63D3D — unchanged red |
| caution | amber #E0B340 | **#CFD363** — pale yellow-green | **#CDCC5C** — pale yellow | **#DE7277** — shifts toward pink/salmon |
| safe | green #52C25C | **#7C7479** — grey-mauve | **#83847B** — flat grey | **#588C8C** — shifts toward teal |

**What this means, plainly:**
- **Deuteranopia and protanopia** (the two red-green forms, ~8% of men, ~0.5% of women): danger
  and caution **collapse into the same olive-yellow hue family**, separated only by lightness
  (danger ≈ 30% darker than caution). Safe becomes a flat, desaturated grey. A player with
  either condition is reading a **one-axis brightness gradient dressed up as three colours** —
  exactly the failure WCAG SC 1.4.1 (Use of Color) exists to catch, and it is on the single bar
  they check most often in the game.
- **Tritanopia** (blue-yellow, rarer): the collision runs the other way — **caution shifts
  toward red's own hue family** (pink/salmon) instead of toward green, so danger and caution
  become the pair that's hard to separate, while safe (now teal) stays distinct. Different
  collision, same outcome: the three-state gradient is not reliably three states for a
  tritanope either.
- There is currently **no number, icon, or pattern anywhere near the HP fill** (`arena_3d.gd`
  `_make_plate`/`_apply_frame`) — no `%`, no numeric HP, no notch marks. This is a pure
  colour-alone failure with no fallback channel at all. See §4, row 1.

### 1.2 `TEAM_COLOURS` — 8 liveries, `scripts/art.gd`

```
0  slate blue    #33619E  (51, 97,158)
1  oxblood       #A1424B  (161, 66, 71)
2  brass         #B89447  (184,148, 71)
3  bottle green  #42755C  ( 66,117, 92)
4  plum          #73548C  (115, 84,140)
5  chalk white   #C7C7CC  (199,199,204)
6  iron grey     #59544F  ( 89, 84, 79)
7  tan leather   #8C6642  (140,102, 66)
```

Full-vision spread is genuinely good (the file's own comment is correct about this). Under
**deuteranopia simulation**, though:

| team | normal | deuteranopia (sim) |
|---|---|---|
| 1 oxblood | #A1424B | **#7D8546** — olive |
| 2 brass | #B89447 | **#ABAD5E** — olive/mustard |
| 7 tan leather | #8C6642 | **#7E814D** — olive |
| 3 bottle green | #42755C | #555164 — grey-mauve (safe, distinct) |
| 4 plum | #73548C | #676A7B — blue-grey (close to HP-safe-sim, see below) |
| 6 iron grey | #59544F | #575851 — dark grey (distinct by darkness) |
| 0 slate blue, 5 chalk white | — | largely unchanged, safe |

⚠️ **Three of eight team liveries — oxblood, brass, tan leather — land in essentially the same
olive-yellow-green cluster under deuteranopia, and that cluster is the same one the HP danger
and caution fills collapse into (§1.1).** A deuteranope watching a brass-team creature at low
HP is looking at three nearly-identical olive patches at once (nameplate border, danger fill,
caution fill) with only brightness to sort them by. Separately, **plum's simulated colour
(#676A7B) sits close to the HP-safe green's simulated colour (#7C7479)** — both land in
grey-mauve territory, distance small enough to be a real, if lower-priority, confusion risk.

**This is exactly why the badge glyph (`TEAM_BADGES`, ◆▲●■★✦⬟✚) is load-bearing, not optional
polish** — art.gd's own comment says so, and this simulation is the concrete evidence for it:
without the badge, 3 of 8 team liveries are not reliably separable from each other, or from the
threat gradient, for a deuteranope or protanope. **Verify the badge is drawn everywhere team
identity matters — see §2.**

⚠️ **One caveat to the mitigation as currently built.** `ART_BIBLE_GUILD_COLOURS.md` proposes
solving the team-vs-status collision by *rendering register*, not hue alone — "saturated ==
something is happening; muted == who plays for whom," cloth vs. glowing chip. That distinction
only survives a CVD simulation if it is realised as an actual **material/shape** difference. The
current implementation (`arena_3d.gd`) draws **both** systems as flat `StyleBoxFlat` colour
fills / flat `Label` font colours — a muted flat rectangle and a saturated flat rectangle differ
in *lightness*, which is exactly the one channel CVD simulation shows is already overloaded on
this screen (§1.1). The register-difference strategy is sound; it isn't implemented yet, and
until it is, treat the hue collision above as live, not theoretical.

### 1.3 Status vocabulary — a second, separate finding

Two different status systems exist in the codebase and only one is live:

- `scripts/ui/arena_view.gd` (**not in the navigation graph**, see header) has a real
  `STATUS_META` table: 5 hue families (hard control / DoT-by-kind / utility / buff), each paired
  with a 3–5 letter abbreviation, matching `ART_THEME.md` §3's design.
- `scripts/ui/arena_3d.gd` (**the live battle screen**) has none of that. Its status label is a
  single hardcoded colour, `Color(0.92, 0.66, 0.30)`, applied to *every* status regardless of
  kind, with the only differentiation being `str(s).substr(0, 4)` — a 4-character truncation of
  the raw status name, at 8px font.

So the live screen currently has **no colour-collision risk for statuses** (there's only one
status colour), but it also has **no status taxonomy at all** — a player cannot tell stun from
sleep from silence except by reading a 4-letter truncated string at 8px in real time, during a
fight they cannot pause or replay a second time without restarting it. This is closer to a
Cognitive/legibility finding than a colourblind one — folded into §4 and §5.

---

## 2. `Art.team_identity(i)` call-site audit

Explicit ask from the brief: does every place team identity is *drawn* use `team_identity()`
(colour + badge), and where is `team_colour()` used alone?

| file : line | call | verdict |
|---|---|---|
| `stable_ui.gd:30` | `Art.team_identity(0)` | ✅ correct — badge shown once in header, colour reused as UI accent per its own comment |
| `tactics_ui.gd` | does **not** call either — uses fixed hardcoded `Color(0.4,0.65,0.95)` "yours" / `Color(0.9,0.45,0.4)` "rival" | not a defect: this is a 2-way yours-vs-theirs accent, always paired with a text header ("YOUR TEAM" / "SCOUTED — RIVAL TEAM"), so it's colour+text, not colour-alone. Worth a note only because it means this screen's colours are **independent of** `TEAM_COLOURS` and won't visually match the roster's actual team swatch later in a tournament context — flag to ui-programmer as a consistency question, not an accessibility defect. |
| `arena_3d.gd:359` (`_make_plate`) | `Art.team_identity(0 if side=="A" else 1)` | ✅ correct — badge drawn in the nameplate label text (`nm.text = "%s %s" % [ident["badge"], m.species_name]`) |
| **`arena_3d.gd:316`** | **`Art.team_colour(0 if side=="A" else 1)`** | ⚠️ **the one genuine `team_colour()`-alone call site.** Used only as a `modulate` tint on the fallback `PlaceholderTexture2D` when no creature art has generated yet. **Not currently a hard failure** — every unit's own nameplate (built two lines later, same function) *does* carry the badge, so a badge is always on-screen adjacent to this tint. But it is a latent risk: if a "minimal HUD" or "hide nameplates" option is ever added (a reasonable ask under §5's density pressure), this fallback tint becomes colour-alone with nothing nearby to back it up. **Recommendation**: change line 316 to read `Art.team_identity(...)["colour"]` for no functional difference today, so the call site is future-proofed the moment nameplates become toggleable. |
| `report_ui.gd:140,144,164,165` | `Art.team_identity(0/1)` | ✅ correct, badge+colour always drawn together (`_team_col`) |
| `arena_view.gd:297,506` (not live) | `Art.team_identity(team_index)` | ✅ correct, for the record |
| `title_ui.gd:60` | explicitly avoids `Art.team_colour()`, uses a fixed gold instead, **with a comment explaining why** ("no team context on this screen") | ✅ correct and self-documenting — a model for how to reason about this |

**Verdict: the contract is respected everywhere identity is actually asserted.** One narrow,
low-risk gap at `arena_3d.gd:316`, fix is a one-line change, not urgent.

---

## 3. WCAG 2.1 AA contrast — measured, not estimated

Method: WCAG relative-luminance formula on the literal `Color(...)` floats in the scripts,
converted through the sRGB→linear transform, ratio = (L₁+0.05)/(L₂+0.05). All backgrounds below
are the actual panel/plate background the text or border sits on in the same function.

| # | element | file : line | foreground | background | **ratio** | required | verdict |
|---|---|---|---|---|---|---|---|
| 1 | Nameplate status text | `arena_3d.gd:390` | `#EBA84D` on | `#0D0D12` panel | **9.48:1** | 4.5:1 (normal text) | ✅ pass — contrast is fine, the failure here is size (§5), not colour |
| 2 | Nameplate name text | `arena_3d.gd:377` | `#F2F2F7` on | `#0D0D12` panel | ~19:1 | 4.5:1 | ✅ pass |
| 3 | Nameplate border, team 0 (slate blue) | `arena_3d.gd:363` | #33619E on #0D0D12 | | 3.09:1 | 3:1 (SC 1.4.11 non-text) | ✅ pass, **no margin** |
| 4 | Nameplate border, team 1 (oxblood) | same | #A1424B on #0D0D12 | | 3.13:1 | 3:1 | ✅ pass, **no margin** |
| 5 | Nameplate border, team 4 (plum) | same | #73548C on #0D0D12 | | 3.12:1 | 3:1 | ✅ pass, **no margin** |
| **6** | **Nameplate border, team 6 (iron grey)** | same | **#59544F on #0D0D12** | | **2.60:1** | 3:1 | **❌ FAIL — SC 1.4.11 Non-text Contrast** |
| 7 | "Fallen" label, report screen | `report_ui.gd:212` | #8C8080 on #12121A-ish | | 4.66:1 | 4.5:1 (12px = normal text) | ✅ pass, **no margin** |
| 8 | Secondary/help text (subtitles, hints) | `stable_ui.gd`, `tactics_ui.gd`, multiple | #A6A6B3 on ~#17171F | | 7.4:1 | 4.5:1 | ✅ pass, comfortably |

**Finding, formatted per the standard checklist:**

| Finding | WCAG Criterion | Severity | Recommendation |
|---|---|---|---|
| Iron-grey team's nameplate border measures 2.60:1 against the plate background, below the 3:1 floor for non-text UI components | SC 1.4.11 Non-text Contrast | **BLOCKING** for that team's matches | Lighten iron grey (e.g. toward `#6E6862`, ~3.4:1) or darken the plate background further; re-check all 8 after any palette pass, not just the one that failed |
| Slate blue, oxblood and plum borders pass at 3.09–3.13:1 — technically compliant but effectively zero margin (a single anti-aliasing or blend-mode change could tip them under) | SC 1.4.11 | HIGH | Treat 3:1 as a floor to clear by a visible margin (target ≥3.5:1), not a target to land on exactly, next time this palette is touched |

Everything else measured (text-on-panel contrast throughout the live screens) passes AA with
real margin — the studio is not making a contrast mistake broadly, the failure is narrow and
named above.

---

## 4. The no-colour-alone rule, applied concretely

Per location, what currently carries meaning in colour only, and what the second channel should
be:

| where | what's colour-only today | required secondary channel |
|---|---|---|
| HP fill, `arena_3d.gd` `_apply_frame` | green/amber/red threat, no other channel | Add the numeric value (`"%d/%d"` or `"%d%%"`) to the plate — it's already computed as `frac`, just never rendered as text. This is the highest-value single fix in this document (see §0, finding #2). |
| Crit vs. normal hit, floating damage numbers, `arena_3d.gd:_draw_shot` | gold (#FFD65C) vs. salmon (#FF9485), same size/weight | Append a symbol or suffix on crit (`"142!"` or a small star glyph) rather than relying on the colour shift alone |
| Team identity | ✅ already correct almost everywhere (badge + colour, §2) — the one gap is narrow and noted | n/a, already the model to follow |
| Live status, `arena_3d.gd` | single flat colour, differentiated only by truncated text — not a colour-collision risk today (§1.3) but also not carrying a taxonomy | If/when the richer `STATUS_META` grouping (already built, in the disconnected `arena_view.gd`) is ported to the live screen, keep its **abbreviation-as-text** approach — that already satisfies this rule — but add a distinct **icon shape** per category as `ART_THEME.md` §3 specifies, so severity reads even faster than the abbreviation alone |
| Selected roster card / marked rival, `stable_ui.gd` `_restyle_cards`, `tactics_ui.gd` `_style_rival_panel` | border colour + width change (`2px` selected vs `1px`, and a bg tint) | This one is fine as-is — border *width* changing is a shape cue, not colour alone; keep it when this UI is rebuilt |
| Channel colour (melee/ranged/magic/voice/support) — proposed in `ART_THEME.md`, not yet built on the live screen | n/a yet | When built, pair the channel colour with the existing tracer-vs-no-tracer behaviour already in `_draw_shot` (melee has no tracer line, everything else does) — that's a free non-colour differentiator already half-implemented, just extend it: distinct tracer *dash pattern* per channel, not just colour |

---

## 5. Text and scale

**Current measured sizes, live screen only (`arena_3d.gd`):**

| element | size | vs. 18px minimum |
|---|---|---|
| Nameplate name (`nm`, incl. badge) | 9px | **50% of minimum** |
| Nameplate status text (`st`) | 8px | **44% of minimum** |
| Floating damage number (`Label3D`, world-space) | 96 world units × `pixel_size 0.0075` ≈ scales with camera distance, not directly comparable — needs a live screenshot check, not a formula | unmeasured |
| Report screen unit rows | 12–14px body text | below minimum but on a static, unpaused, scrollable screen — much lower stakes than the live fight |

⚠️ **The leash-radius removal makes this worse, not just "already bad."** `arena_3d.gd`'s camera
today frames the *engagement envelope* (~42% of the 160×88 ground, `AUTOBATTLER_DESIGN.md` /
`ARENA_BLUEPRINT.md`), not the full board — the code comment at `_build_world()` says so
explicitly ("Framing the whole board therefore renders the actual combat as a speck in an empty
white field"). Once the leash is removed and units genuinely spread across the full 160×88
(`AUTOBATTLER_DESIGN.md` decision #8, "keep the arena massive... make the AI use it"), the
camera has two options, both of which hurt this section:

1. **Keep the tight envelope framing** — units now regularly fight outside frame, which is a
   readability failure on its own (not this document's problem to solve, flagged to whoever owns
   the camera).
2. **Pull back to frame the full board** — creature sprites shrink, nameplates (fixed at 9px/8px
   regardless of camera distance, since they're drawn via `unproject_position` on a `CanvasLayer`
   overlay, not billboarded 3D text) get **further apart on screen** and harder to visually
   associate with their now-smaller creature. The absolute text size does not get smaller than it
   already is — but density and association do, and 9px was already half the minimum.

**Recommendation, concrete:** nameplate text needs to at least double (18px name / 16px status,
i.e., actually hit the stated minimum) *before* the leash change ships, not after — retrofitting
size onto a UI built around today's cramped 80×26px plate is a bigger job once density has
already gotten worse. A text-scale option (100/125/150%) satisfying "scalable up to 200%" is a
separate, later item — get the *floor* right first.

---

## 6. Motion and photosensitivity

**What exists today, live screen:**
- Hit flash: sprite `modulate` tweens to `Color(1.7, 0.55, 0.55)` (bright red, over-driven above
  1.0) for 0.05s, back to normal over 0.18s, per hit landed (`_draw_shot`).
- Floating damage numbers: fade/rise tween, 0.8s / speed multiplier.
- Tracer lines for ranged/magic hits: 0.22s fade.
- Speed control already exists (0.5×/1×/2×/4×, `SPEED_OPTIONS`) — **this is a genuine
  accessibility positive already in the game**, worth naming as a pass: a player who finds the
  pace overwhelming can already slow it down, and one who wants to skip entirely has "Skip to
  result."

**Assessment:** at 5v5 with multiple simultaneous hits, the aggregate of several 0.05s red
sprite-flashes per tick is a mild rapid-flash pattern, but each individual flash is localized to
one ~small sprite, not full-screen, and 0.05s single-frame-ish flashes at typical hit cadence are
below the WCAG 2.3.1 general-flash danger threshold (3 flashes/second, full-field). **Not
currently a seizure-risk finding** — but there is no reduced-motion toggle, and the moment a
"focus target glow/pulse" effect is built (`ART_THEME.md`'s proposed "under fire" cue, not yet
implemented) that risk profile should be re-checked, since a pulsing highlight sustained across
a whole fight is a different hazard class than a one-shot flash.

**Recommendation:** low priority today given the above, but bank it as a requirement for the
eventual settings screen (§0 #11) rather than the arena renderer itself — a "reduce flash
intensity" toggle that dampens the modulate multiplier (e.g. cap at 1.2 instead of 1.7) and
disables the tracer/pulse effects, satisfying the photosensitivity guidance without touching game
logic.

---

## 7. Input — keyboard navigability (the load-bearing finding)

**What works today**, confirmed by reading the actual node construction: every `Button` and
`OptionButton` in `stable_ui.gd`, `tactics_ui.gd`, `training_ui.gd`, `arena_3d.gd`, `report_ui.gd`
and `title_ui.gd` is a real Godot `Button`/`OptionButton` node. These are keyboard-focusable and
keyboard-operable by default (Tab to focus, Enter/Space to activate, arrow keys inside an
`OptionButton`'s popup) — **no code anywhere disables this**. So: Train, Enter a tournament,
Commit and fight, Back, the four playback-speed buttons, Skip to result, and all four order
selectors (target priority, mana policy, formation, temperament) are already keyboard-operable
with zero extra work. That's a real, positive finding worth stating plainly.

**What does not work**, confirmed the same way:

| location | control | mechanism | keyboard path |
|---|---|---|---|
| `stable_ui.gd:174–178`, `_make_card` | roster monster card (select a monster) | `PanelContainer` + `panel.gui_input.connect(...)`, checks `InputEventMouseButton` only | **none** — `PanelContainer` has no default `focus_mode`, is never Tab-reachable, has no keyboard-equivalent activation |
| `tactics_ui.gd:311–314`, `_add_rival_row` | mark a rival as the "man mark" target | identical pattern — `panel.gui_input`, mouse-button check only | **none** |

Grep across `scripts/ui/*.gd` for `focus_mode` returns exactly zero results project-wide — no
control anywhere has had focus behaviour explicitly configured, which is fine for the `Button`
nodes (correct by default) but means nothing was ever done to *add* keyboard support to the two
`PanelContainer` interactions above; they were simply never wired for anything but a mouse.

**Why this is the P0, and why it outranks the colour-alone HP bar:** every other finding in this
document describes a *degraded* experience — readable with effort, or readable via a workaround,
or readable for most but not all players. This one is a **complete block**. A keyboard-only
player (motor disability, no mouse, or using a switch/adaptive-controller setup mapped to
keyboard events) literally cannot select which monster to view or train in the Stable, and
literally cannot mark a rival target in Tactics. They cannot proceed past the first interactive
screen of the game. It is also upstream of every other finding here — a player who is locked out
at the Stable never reaches the arena screen to be affected by the HP-bar colour issue, the
nameplate size issue, or anything else in this document.

| Finding | WCAG Criterion | Severity | Recommendation |
|---|---|---|---|
| Roster card selection has no keyboard equivalent | SC 2.1.1 Keyboard | **BLOCKING** | Convert the card's outer `PanelContainer` to wrap a `Button`-derived control (e.g. a borderless `Button` with the existing card content as its child via `add_theme_stylebox_override`, or set `focus_mode = FOCUS_ALL` and handle `ui_accept`/`ui_select` in an input handler alongside the existing mouse check) |
| Rival-mark selection has no keyboard equivalent | SC 2.1.1 Keyboard | **BLOCKING** | Same fix, applied to `_add_rival_row`'s panel |
| No visible focus indicator is defined anywhere (default Godot theme only) | SC 2.4.7 Focus Visible | HIGH, once the above is fixed | Once cards/rows are focusable, add an explicit focus stylebox (e.g. reuse the existing "selected" border treatment) so keyboard focus is visually distinguishable from mouse hover/selection |

**Not evaluated / explicitly out of scope for this pass:** gamepad support (project-wide,
documented as "not yet" in `technical-preferences.md`) and Xbox Adaptive Controller support,
which depends on gamepad support existing first. Both should inherit correctly once the keyboard
path above exists, since XAC and most switch setups map through the standard input system the
same way keyboard does — worth re-confirming once gamepad lands, not a new design problem.

---

## 8. Summary for the team

**Do first (P0/P1, in order of leverage):**
1. Keyboard path for roster-card and rival-mark selection (§7) — the only total block in this
   audit, fix before anything else in this list.
2. Numeric value on the HP fill (§4, §1.1) — smallest fix in this document, removes the classic
   green-red failure from the single most-watched element in the game.
3. Nameplate text size, 9px/8px → ≥16–18px (§5) — do this *before* the leash-radius removal
   ships, not after.
4. Fix iron-grey team's nameplate border contrast, 2.60:1 → ≥3.5:1 (§3).
5. Non-colour tell for crit vs. non-crit floating damage (§4).
6. Status taxonomy on the live screen — port `arena_view.gd`'s `STATUS_META` grouping + icon
   shapes rather than leaving the live screen's single-colour truncated-text status label (§1.3,
   §4).

**Polish, real but not urgent (P2):** the narrow `team_colour()`-alone call site (§2), the
zero-margin contrast passes worth a buffer next palette touch (§3), a reduced-flash toggle (§6),
and the settings screen everything above will eventually want a home in (§0 #11).

**Not applicable yet, tracked for later:** audio accessibility (no audio system exists),
gamepad/XAC (no gamepad support exists project-wide).

**The single most important fix**, restated: **wire keyboard focus and activation onto the
roster-card and rival-mark selection panels in `stable_ui.gd` and `tactics_ui.gd`.** Everything
else in this document is a legibility or contrast improvement for players who can already reach
the screen in question. This one determines whether a keyboard-only player can play the game at
all.
