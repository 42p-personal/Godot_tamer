# Polish direction — the craft round

**2026-08-13.** Written from a fresh capture of all thirteen meta screens across both fixtures
(`A_comfortable`, `B_thin`), read back as PNGs, plus four instrument runs against the 4.7.1
binary. Every number below was produced this session; nothing is quoted from a previous round.

> *"lets improve the ux across the board, get the teams to fan out and improve upon what we have.
> we look like we are a prototype, lets polish this game and make it look better"* — the user

**This document sets the visual direction. It does not restyle a screen.** Four builder briefs are
in §6, each with acceptance criteria a capture or a probe can settle.

---

## 0. The one-line finding

**The screens are not flat because nobody styled them. They are flat because the entire elevation
system spans 1.08:1, the two amber inks are 1.02:1 apart, and the pressed state is 1.07:1 from
the resting state.** The house style is real, adopted and correct — it is simply drawn in a tonal
range so narrow that none of its distinctions survive being looked at.

That is good news of the same kind round 18 found: **the arrangement is wrong, not the work.**
Every number below moves by editing `theme.gd`, and thirteen screens inherit it.

⚠️ **AND ONE FINDING THE BRIEF DID NOT ANTICIPATE, WHICH OUTRANKS THE POLISH.** §2 — the game
prints 47 distinct glyphs the packaged font does not contain. They render today only because a
Windows system font is silently supplying them. Round 19's tofu bug is not a past incident; it is
live, in every screen, and it is currently invisible because we only ever look at Windows.

---

## 1. The craft audit — named screen, named element, what a shipped game does instead

### 1.1 The measured spine

Computed with the WCAG relative-luminance formula, same method `theme.gd` uses on itself:

| relationship | ratio today | what it means on screen |
|---|---|---|
| `SURFACE` → `PANEL` (page → card) | **1.083 : 1** | a card is 8% brighter than the page it sits on |
| `PANEL` → `PANEL_RAISED` (card → raised) | **1.101 : 1** | "raised" is not raised |
| button normal → **hover** | **1.363 : 1** | the only state change you can actually see |
| button normal → **pressed** | **1.069 : 1** | below any perceptual threshold — the game does not acknowledge a click |
| button normal → **disabled** | **1.102 : 1** | a dead control looks like a live one |
| `GOLD` → `CAUTION` | **1.023 : 1** | ⚠️ **two published tokens, one colour** |
| `GOLD` → the icon set's CHA hue `#E6B45A` | **1.012 : 1** | the brand ink and a stat hue are the same |

**`SURFACE → PANEL` at 1.083:1 is the number of the round.** Every panel in the game is defined
by a 1px border and nothing else. Remove the borders and thirteen screens become one unbroken
rectangle. A shipped game separates a card from its page by tone, by a shadow, or by a ground
line; this one separates it by a hairline.

### 1.2 Per screen, per element

**01 title** — the best art in the project (a full-bleed painted arena at golden hour) with
`MONSTER TAMER` set in **Open Sans SemiBold at 64px**, the engine's default face, unstyled, no
tracking, no plinth. The tagline *"You run the stable. The stable fights."* is drawn in GOLD
directly over the bright sky and is **the least legible text in the game**. Four buttons float on
the painting with no scrim under them.
*A shipped game* gives the wordmark a treatment and puts the menu on a plinth so the art can stay
bright behind it. **This is the single most valuable screen-hour in the round** — it is the first
thing anyone sees and the gap between its art and its UI is the whole "prototype" impression in
one frame.

**02 town** — the hub's seven destination cards are seven identical rectangles at identical
weight, each with a ~20px emoji at the top-left: 🛒 for The Market, 🥊 (a *pink boxing glove*) for
Tournament, 🐎 for the Breeding Ranch. Zoomed 3× these are unmistakably **Windows Segoe UI Emoji**
— a photographic-gradient icon language sitting inside a stylised HD-2D guild aesthetic. The hub
has no hierarchy: The Market and the Hall of Fame are the same size, weight and colour.
*A shipped game* makes the hub's primary destination this week visibly primary.
✅ Credit where due: the pace strip, the ladder track and the "This week" panel are genuinely
good, and `B_thin`'s red `This stable is OUTCLASSED at Silver` alert is excellent — the one place
in the game where colour, border and copy all agree.

**02 town, B_thin only** — the "The stable this week" roster strip **clips mid-row at the fold**:
Grynt's card shows `DEX 250 · STR 176` cut horizontally through the glyphs. Not a scroll failure
(the root scrolls) — a strip whose card height is authored taller than the band it sits in.

**03 stable** — six stat bars, the primary readout of a monster-taming game, drawn in **one
identical blue**. STR, DEX, CON, WIS, INT and CHA are distinguishable only by reading the
three-letter label at the left. Meanwhile 141 ability icons on disk carry a **six-hue stat
system already authored** (§3). The portrait is ~90px in a 940px-wide panel.

**04 training** — the round-20 six-column-by-stat fix landed and it works. What it exposed is the
ink problem: a drill card prints its **name in GOLD** and its **multiplier footnote in CAUTION**,
and those are 1.023:1 apart, so the name and the footnote have identical emphasis. The number the
player is actually choosing on — `→ +9 net` — is inside the gold title line with the name. Thirty
`Book` buttons are pixel-identical, and `✓ Booked` (disabled) differs from `Book` (live) by
1.10:1 of fill plus a checkmark the font does not contain.
*A shipped game* puts the payoff number in its own weight and lets the booked card read as
settled at a glance across six columns.

**05 feeding** — five rows, no portraits. This is one of the seven screens `UI_THEME.md` §4b
names as "naming a monster while showing no portrait", and it is the one where the monster is the
entire subject of the row.

**06 market** — the recruit grade tiers (`Prospect` / `Journeyman` / `Veteran`) are painted in
green / blue / orange. **Those blues are 3 of the 7 off-token colours the probe reports** — the
market invented a fourth colour system to encode grade. Portraits are up to ~48px, better than
round 18's 28px, still a thumbnail. The two card columns — recruits and your stable — are
visually identical, so the comparison the screen exists to support has no visual axis.

**07 shop · 10 tournament** — near-total amber monotone. `tournament_ui.gd` references
`GOLD`/`CAUTION` **25 times against 13 greys**; `breeding_ui.gd` **13 against 2**; `lab_ui.gd`
**9 against 1**. When the heading ink and the body ink are the same colour, there is no heading.

**09 breeding** — the clearest icon case in the game. `kit: Grand Mockery, Bravura, Sidestep,
Discord, Screech, Anthem of Iron` is a comma-separated string; "The move it is BORN knowing" is
**twelve identical grey buttons carrying ability names as text**. Every one of those twelve has a
64×64 authored icon on disk, addressed by the id the screen already holds.

**11 tactics** — dense, and the three-column split works. The deployment board is a **raw black
rectangle with 16px sprite chips** and is the least-crafted element in the meta game.
✅ `COMMIT AND FIGHT — no take-backs` is the best button in the project: gold border, filled,
stated consequence. It is proof the theme can already do this and only one screen asked it to.

**12 report** — the payoff screen of the entire design ("observation is the reward") is a wall of
one-weight text with 28px portraits. Ability names (`Capling's Pin Down`) are plain text. The
verdict marks ✓ / ✗ / ▲ are **not in the packaged font** (§2).

**13 ending** — the best-composed screen: stat tiles (`372 weeks`, `10 / 11 titles taken`) give a
genuinely different rhythm, and the climb track is excellent. But it is the climax of a 372-week
career rendered at exactly the visual temperature of the Ranch Shop. `TAMERS APEX — TAKEN` is set
at heading size, not display; there is no art, no scale change, no moment.

### 1.3 Cross-screen

**The tutorial banner appears on nine of thirteen screens saying the same two lines** — `Guide —
Decide what it eats / This one happens in Training.` It costs ~55px of a 648px viewport on the
Town, Stable, Training, Feeding, Market, Shop, Lab, Breeding and Tournament screens
simultaneously, including on screens where the instruction is not actionable. A persistent nag bar
is a prototype tell on its own.

**Every screen is the same screen.** Thirteen vertical stacks of full-width panels at one density.
Nothing distinguishes a hub from a ledger from a verdict.

---

## 2. ⚠️ THE FONT DOES NOT CONTAIN THE PICTURES — verified, and it outranks the polish

`project.godot` sets **no font at all**, so every screen renders in Godot's embedded
**Open Sans SemiBold**. Probed against that exact face on the 4.7.1 binary:

```
checked 26  packaged 5  MISSING 21
missing: U+2192 →   U+26A0 ⚠   U+25CF ●   U+2713 ✓   U+25B6 ▶   U+25B2 ▲   U+25C0 ◀
         U+25B8 ▸   U+2605 ★   U+2190 ←   U+25C6 ◆   U+2717 ✗   U+265B ♛   U+1F3AF 🎯
         U+25BE ▾   U+1F3B2 🎲  U+25BC ▼   U+2691 ⚑   U+1F6D2 🛒  U+2665 ♥   U+26A1 ⚡
packaged: U+2212 −   U+2022 •   U+00D7 ×   U+00B7 ·   U+2018 '
```

Across `scripts/ui/*.gd`: **47 distinct such glyphs, 178 occurrences, in all 15 UI files**
(`town_ui` 31 · `arena_3d` 25 · `training_ui` 15 · `tournament_ui` 14 · `report_ui` 9 …).

**They render in today's captures anyway.** Two independent sources say so — the probe says the
packaged face lacks the codepoint, the PNG shows the glyph — therefore something outside the
export is supplying it. On this machine that is a Windows system font.

⚠️ **CONSEQUENCE.** Every arrow in every training card, every ⚠ in every warning, the Report's
✓ HELD / ✗ BROKE verdict marks, and the ▲/◆ team markers are **platform-dependent accidents**.
They are one export target away from tofu. Round 19 shipped exactly this bug in one place and it
was caught by eye; it is currently live in 178 places and nobody has looked, because we only ever
capture on Windows.

**This changes the iconography question from "which icons" to "the meta UI must stop asking the
font for pictures."** See §3. It also means **no builder may add a new glyph without
`Font.has_char()` proving the packaged face carries it** — that check is now a house rule.

---

## 3. Iconography — the decision

### 3.1 What already exists, and it is good

`assets/icons/abilities/` holds **141 icons, 64×64 RGBA**, named by move id (`STR-0`, `CHA-13`).
They are a real, coherent set: a rounded-square badge, a dark stat-tinted fill, one line-drawn
glyph, and a small `+` corner mark on some. Sampled hues, one per stat:

| stat | glyph ink | badge fill |
|---|---|---|
| STR | `#DE783E` | `#312016` |
| DEX | `#78BE5A` | `#202B1B` |
| CON | `#AA9664` | `#28251C` |
| WIS | `#6EBEAA` | `#1E2B28` |
| INT | `#9678DC` | `#252030` |
| CHA | `#E6B45A` | `#322A1B` |

**This is a designed system that nobody named.** Exactly one file loads it (`arena_3d.gd:3894`).

### 3.2 The ruling

| thing | verdict | source |
|---|---|---|
| **Every ability, everywhere it is named** | **ICON** — Stable moveset, Report decision log, Tactics orders, Breeding heirloom picker, Lab kit line, Market kit line | `assets/icons/abilities/<id>.png`, already on disk |
| **The six stats** | **HUE + the three-letter code.** The letters *are* the mark; the hue is the channel | new `STAT_HUES` in `theme.gd`, lifted from the icons above |
| **Statuses** | **KEEP `status_chip()` exactly as it is** — it draws diamond / circle / hexagon / triangle **in code** | already correct; it is the only glyph system in the project that cannot tofu |
| **Verdict + severity marks** (✓ ✗ ▲ ⚠ →) | **DRAWN, not typed.** A `mark()` component drawing 6 shapes with `draw_*` | replaces 178 font-dependent occurrences |
| **Town hub destinations** | **DELETE the emoji.** Replace with a drawn mark, or — better — a real creature portrait for The Stable / Market / Breeding Ranch | 65 portraits ship and the hub uses none |
| **Classes** (18) | **STAY A WORD.** No asset exists, an 18-icon set is a production round, and the names are short and already unambiguous | — |
| **Foods** (9) | **STAY A WORD.** Chosen once a week from a labelled row; the label is the affordance | — |
| **Roles** (damage / support) | **STAY A WORD.** Two values; an icon earns nothing | — |

⚠️ **"An icon that needs a label is not an icon" cuts both ways.** The ability icons are
abstract — a player will not read `three slashes` as `Rend`. They go **beside the name, never
instead of it**, at 24px inline / 32px in a list. Their job is scanning and stat-channel colour,
not naming. Say this in the brief or a builder will helpfully drop the labels.

### 3.3 The collision, and how it is resolved

`GOLD` and the CHA stat hue are **1.012:1** — the same colour. Resolve by **role, not by hue**:

> **GOLD is an INK and never a FILL. A stat hue is a FILL or a GLYPH and never an INK.**

They then never appear in a comparable role, and the rule is mechanically checkable. It forces
two consequences, both of which are improvements: the six stat bars stop being identical blue and
take their stat's hue; and the default `ProgressBar` fill (currently `GOLD`) moves off it.

This keeps `ART_THEME.md`'s three systems intact. **Stat hue is a fourth channel and it is
legitimate** because it never touches the three: it lives on badges and bar fills only — never on
arena stone (league material), never on a nameplate frame (team colour), never on a status chip
(status vocabulary, which owns its own hues and its own drawn shapes).

---

## 4. Depth and surface — resolved against Guild Colours

### 4.1 What the engine actually gives us — verified against the 4.7.1 binary

`StyleBoxFlat` in 4.7.1 exposes `bg_color`, per-side `border_width_*`, **one** `border_color`,
`corner_radius_*`, `skew`, and **`shadow_color` / `shadow_size` / `shadow_offset`**. There is **no
per-side border colour and no gradient.** So a two-tone bevel is not available from a single
stylebox, and any recipe that assumes one is wrong.

### 4.2 ⚠️ The obvious fix is the wrong fix, and here is the arithmetic

The instinct is to widen the tonal ladder. Measured, it does not pay:

| candidate | page→card | card→raised | `TEXT_MUTED` on raised |
|---|---|---|---|
| today `#14141B / #1C1C24 / #24242E` | 1.083 | 1.101 | **4.63** |
| lift raised to `#2A2A36` | 1.168 | 1.195 | ⚠️ **4.27 — BELOW THE 4.5 AA FLOOR** |
| lift further `#2E2E3A` | 1.209 | 1.234 | ⚠️ **4.03** |

**Buying elevation with fill tone spends contrast, and the budget is already gone.**
⚠️ **A finding nobody has recorded: `TEXT_MUTED` on `PANEL_RAISED` is already 4.63:1** — 0.13
above the floor. `body_text(…, "muted")` inside a `panel_style("raised")` card is legal today by
a margin narrower than a rounding error, and any lift of `PANEL_RAISED` breaks it.

### 4.3 The recipe

**Elevation comes from shadow and edge, which cost zero contrast. Fill tone moves only where it
is free.**

1. **`SURFACE` darkens to `#0A0A0E`.** `PANEL` and `PANEL_RAISED` **do not move at all**. This is
   free in both directions: page→card goes 1.083 → **1.168**, and *every* text ratio on the page
   background *improves* (`TEXT_PRIMARY` 16.13→17.39, `TEXT_MUTED` 5.52→5.95, `DANGER` 4.23→4.56,
   which lifts `DANGER` clear of the 4.5 floor it currently sits under).
2. **A drop shadow, and only on what is raised or interactive.** `shadow_size 6`,
   `shadow_offset (0, 3)`, `shadow_color rgba(0,0,0,0.55)`. **Elevation is information:** the
   `raised` and `interactive` variants cast; `default` and `flat` do not. A page where every panel
   floats is as flat as one where none do.
3. **A ground line instead of a bevel.** `border_width_bottom = 2` with the other three at 1. One
   colour, so it is inside `StyleBoxFlat`'s real limits, and it reads as a card sitting *on*
   something. This is `ART_DIRECTION.md`'s standing "never a raw 90° edge" rule expressed in 2D —
   the same instruction the arena meshes already follow, which is why it belongs here rather than
   being invented.
4. **Texture: none, and deliberately.** `assets/shaders/` holds two shaders and no addons are
   permitted. A panel texture is a production item with no asset behind it, and `ART_THEME.md` §4
   already sequences league-material chrome *after* more leagues have venue art to borrow from.
   **DROPPED** — see §7.

### 4.4 Interactive states

Not optional, and today three of four are invisible. Targets, all measurable by the same helper
the theme already ships (`contrast_ratio`):

| state | today | target | how |
|---|---|---|---|
| hover | 1.363 | **≥ 1.45** | lighten + the border goes to the accent |
| pressed | **1.069** | **≥ 1.25 AND geometrically distinct** | darken **and** drop the shadow to 0 with `shadow_offset (0,0)` — the card *presses in* |
| disabled | 1.102 | **≥ 1.20** | fill to `SURFACE`, border to `BORDER_FAINT`, no shadow |
| focus | 3px `FOCUS` | **unchanged** | already correct and highly visible in the captures — do not touch it |

**The disabled state keeps its reason in the label.** `disable_with_reason(btn, …, in_label=true)`
is the house form and the shop already does it right (`Locked — reach Iron league (you are
Bronze)`). Nothing in this round may weaken it.

### 4.5 Guild Colours compliance

| `ART_THEME.md` system | carried by | untouched by this round? |
|---|---|---|
| League material | arena stone, ground, lamps | ✅ not touched |
| Team colours | nameplate frame, team chip, livery accent | ✅ still the only sanctioned off-token colours |
| Status vocabulary | `status_chip()` hue **+ drawn shape** | ✅ not touched |
| *(new)* Stat hue | ability badge + stat-bar fill **only** | ✅ never on stone, frame or status |

---

## 5. The ranked change list

**A polish round fails by spreading one unit of effort across thirteen screens.** These are ranked
by *screens lifted per hour*, and the first three are shared changes in one file.

### C1 — Give elevation and state a real range · `theme.gd` only · **lifts all 13 screens**
§4.3 and §4.4. `panel_style()` and `button_stylebox()` grow a shadow, a ground line and separable
states; `SURFACE` darkens. **Every screen already calls these builders, so no screen is edited.**
This is the highest-leverage change available and it is close to a one-file diff.

### C2 — Split the amber, and give the six stats a colour · `theme.gd` + call sites
`GOLD` and `CAUTION` are one colour (1.023:1). Retire `CAUTION` as a **text** ink — it survives as
a fill and a mark. Publish `STAT_HUES` from the icon set. The monotone on shop / tournament /
breeding / lab breaks, and `STR 158 · DEX 172 · CON 159 · WIS 164 · INT 117 · CHA 224` becomes
scannable in one pass instead of six reads.

### C3 — Take the icons out of the folder, and stop asking the font for pictures · §2, §3
`ability_icon()`, `stat_hue()`, `mark()`. Replaces 178 font-dependent glyph occurrences with
drawn shapes and 141 authored PNGs. **This is both the cheapest visual upgrade in the project and
the fix for a live cross-platform defect** — it is the only item here that is a bug fix as well as
a polish item.

### C4 — Three registers, not one · per-screen, mostly spacing
**HUB** (title · town · ending) — large, sparse, art-forward, one obvious primary.
**LEDGER** (stable · training · feeding · market · shop · lab · breeding · tournament) — dense,
tabular, quiet; the register it already has, done on purpose.
**POSTER** (report · tactics) — the commit and the verdict; wide, high-contrast, few elements
large. Cheap, because it is heading scale, column width and panel rhythm, not new components.

### C5 — DEFERRED, NOT DROPPED: package a display face
The wordmark, every heading and every screen title currently render in **the engine's default
font**, and that is the most direct cause of "this looks like a prototype". `heading()` is written
so that **one function changes and all thirteen screens pick it up**. It is deferred only because
sourcing and licensing an OFL slab face is a studio decision and there is no font file anywhere in
the tree or on this machine. ⚠️ **If the studio can approve one face, this jumps to rank 2** — it
would do more for the "prototype" impression than C4.

---

## 6. Builder briefs

Ownership as assigned. Anything outside your files: describe it for the integrator, do not edit it.

### Builder 1 — the surface · owns `scripts/ui/theme.gd` (§1–7 only)
Implement C1 and C4's shared half.

- `SURFACE` → `#0A0A0E`. **`PANEL` and `PANEL_RAISED` must not move** — §4.2 has the arithmetic.
- `panel_style()` gains variants `raised` and `interactive` that cast the §4.3 shadow;
  `default` and `flat` must **not** cast. Ground line: `border_width_bottom = 2`, others 1.
- `button_stylebox()` hits the §4.4 targets. Pressed must lose its shadow, not just darken.
- Add `elevation_report() -> Dictionary` returning the seven §1.1 ratios, so the gallery prints
  them and the next round cannot re-derive them by hand.

**Acceptance, settleable by probe + capture:**
- `contrast_ratio(SURFACE, PANEL) ≥ 1.16` · `(normal, hover) ≥ 1.45` · `(normal, pressed) ≥ 1.25`
  · `(normal, disabled) ≥ 1.20`.
- `contrast_ratio(TEXT_MUTED, PANEL) ≥ 5.09` and `(TEXT_MUTED, PANEL_RAISED) ≥ 4.62` — **neither
  may fall.** These are the round's regression tripwires.
  ⚠️ **THESE ARE 5.09 / 4.62, NOT the 5.10 / 4.63 published in `UI_THEME.md` §3.** Measured live
  by gallery §16 against the untouched theme they are **5.098** and **4.628**; the published
  figures were rounded up, so a tripwire set at the published value fails on an unchanged theme
  and would have reported a phantom regression on the first builder diff of the round. Caught by
  the gallery's own first capture — which is the whole argument for §16 existing.
- `_probe_house.gd` still reports **off-scale 1 · off-token 7 · 0 SILENT · 0 nested**.
- `./run_contract.sh` PASSES.

### Builder 2 — the ink and the stats · owns `theme.gd` §3 tokens + `stat_bar()` + call sites in `stable_ui.gd`, `training_ui.gd`, `tournament_ui.gd`, `shop_ui.gd`, `lab_ui.gd`, `breeding_ui.gd`
Implement C2.

- Publish `STAT_HUES := {STR:…, DEX:…, CON:…, WIS:…, INT:…, CHA:…}` with the §3.1 values.
- **Rule to enforce at every call site: GOLD is an ink, never a fill; a stat hue is a fill or a
  glyph, never an ink.** `stat_bar()`'s default fill stops being `GOLD`; the six bars take six
  hues. The default `ProgressBar` fill moves off `GOLD`.
- `CAUTION` is removed from every **text** call site in the six files named. It stays as a fill
  and as a mark colour. Where a warning needs *text* emphasis it uses `TEXT_PRIMARY` with weight
  and a drawn ⚠ mark, not a second amber.
- Target: no screen references `GOLD`/`CAUTION` as text more than **twice as often** as it
  references the greys. Today `tournament_ui` is 25:13, `breeding_ui` 13:2, `lab_ui` 9:1.

**Acceptance:** the six stable bars are six colours in the capture · `07_shop` and `10_tournament`
are no longer monotone by eye · off-token count **does not rise above 7** · `TEXT_MUTED` ratios
unchanged · `./run_contract.sh` PASSES.

### Builder 3 — the marks · owns `theme.gd` §8 components + `scripts/ui/*.gd` glyph strings
Implement C3. **This is a bug fix; treat it as one.**

- `ability_icon(move_id: String, px: int = 24) -> TextureRect`, degrading to a stat-hued blank
  badge at the same footprint when the file is missing (the `portrait()` pattern — never a layout
  jump).
- `mark(kind: String, px: int = 14) -> Control` **drawing**: `check` · `cross` · `warn` ·
  `arrow` · `up` · `diamond` · `dot`. Code-drawn, like `status_chip()` already is. No font
  dependency, no asset.
- Replace all 178 occurrences across `scripts/ui/`. Delete the town hub's emoji entirely.
- Wire `ability_icon` into: Stable moveset · Report decision log · Tactics orders · **Breeding's
  twelve heirloom buttons** (the clearest case) · Lab and Market kit lines.
- ⚠️ **Icons go beside names, never instead of them.**

**Acceptance:** a probe asserting `Font.has_char()` for every codepoint above U+00FF remaining in
`scripts/ui/*.gd` — **must reach zero misses**, and that probe becomes permanent · the Breeding
capture shows twelve icons · off-scale/off-token counts unchanged · `./run_contract.sh` PASSES.

### Builder 4 — the three registers · owns `title_ui.gd`, `town_ui.gd`, `ending_ui.gd`, `report_ui.gd`, `tactics_ui.gd`
Implement C4's per-screen half. **Ranked — do them in this order and stop when the round ends.**

1. **`title_ui`** — the highest-value hour in the round. Wordmark treatment; a plinth under the
   menu so the tagline clears **≥ 4.5:1 against what is actually behind it** (it does not today);
   `Continue` becomes the one primary and carries the career it resumes.
2. **`town_ui`** — hierarchy across the seven cards; kill the emoji; **fix the `B_thin` roster
   strip clipping mid-row**; give the week's most urgent destination visible primacy.
3. **`ending_ui`** — the climax of 372 weeks must not read at Ranch Shop temperature.
   `TAMERS APEX — TAKEN` goes to `SIZE_DISPLAY`. It is already the best-composed screen; it needs
   scale, not restructuring.
4. **`report_ui` / `tactics_ui`** — poster register: fewer, larger elements; the verdict line and
   the commit bar carry the screen.

**Acceptance:** captured at **both** fixtures and **both** sizes · title tagline measured ≥4.5:1
against its actual backdrop · no clipped row in `B_thin/02_town.png` · every screen still passes
`_probe_house.gd` on its row · `./run_contract.sh` PASSES.

### For the integrator — changes I could not make, in files nobody in this round owns

- **`tutorial_overlay.gd`** — the guide banner renders on 9 of 13 screens with the same two lines,
  costing ~55px of a 648px viewport. It should show on the screen where its step is *actionable*
  and be a one-line strip elsewhere.
- **`town_ui.gd:83`** derives the hub's chrome accent from `Art.team_colour(0)` and
  **`town_ui.gd:644`** fills a mood bar with `FOCUS`, whose own comment reads *"never reused for
  anything else."* Both were flagged in `UI_THEME.md` §0 and are still live. Both are Guild
  Colours violations, not style preferences.
- **`market_ui.gd`** paints grade tiers in invented blues — **3 of the 7 off-token colours**. Either
  promote grade to a published token set or render grade as weight, not hue.
- **`project.godot` has no font entry.** Whoever lands C5 sets it there, once.

---

## 7. What I dropped, and why

| dropped | why |
|---|---|
| **Panel textures / material shaders** | Two shaders exist, no addons permitted, no asset behind it. `ART_THEME.md` §4 already sequences league-material chrome *after* venue art. Cost is high, and §4.3's shadow + ground line buys most of the perceived depth for none of it. |
| **Screen-transition motion** | The brief's own rule — *"a transition that delays a decision is worse than none"* — and this is a game whose loop is clicked hundreds of times. The **only** motion sanctioned this round is the ≤120ms button state change in C1, which is feedback, not transition. |
| **Animating the stat bars / number roll-ups** | Same reason, plus it would put motion on the exact element C2 is making legible. Legibility first; a bar that animates while you are trying to compare six is a loss. |
| **An 18-icon class set and a 9-icon food set** | No assets exist, both would be a production round, and both are short unambiguous words today. §3.2. |
| **A bespoke redesign of all thirteen screens** | This is precisely how a polish round fails. C1–C3 are three shared changes that lift thirteen screens; C4 touches five, ranked, and is explicitly stop-when-time-runs-out. |
| **Widening `TOKEN_FONT_SIZES` / `TOKEN_TEXT_COLOURS`** | Non-negotiable. `UI_LAYOUT_RULES` R7: that is deleting the measurement, not passing it. |
| **Anything in `arena_3d.gd`, the camera, audio, pacing or the sim** | Out of scope by instruction. Note that C3's `ability_icon()` is a *move* of behaviour `arena_3d.gd` already has into the shared theme — the arena keeps working, it stops being the only caller. |

---

## 8. The regression tripwires — this round is a LOSS if any of these move

Rounds 18–20 bought these and none may be spent on prettiness.

| invariant | value that must hold |
|---|---|
| off-scale rendered labels | **≤ 1** (the 64px title wordmark; goes to 0 if C5 lands) |
| off-token rendered colours | **≤ 7** (the team liveries — the only legitimate ones) |
| labels below 14px | **0** |
| disabled controls with no reason | **0 SILENT** |
| nested scroll regions | **0** |
| screens with no pinned action | **0** |
| `contrast_ratio(TEXT_MUTED, PANEL)` | **≥ 5.09** (measures 5.098 today) |
| `contrast_ratio(TEXT_MUTED, PANEL_RAISED)` | **≥ 4.62** (measures 4.628) ⚠️ only 0.13 above the AA floor |
| `contrast_ratio(DANGER, SURFACE)` | **must RISE** — 4.226 today, i.e. **already under the 4.5 floor**; C1's `SURFACE` darkening takes it to ~4.56 |
| `SAVE_VERSION` | **4**, and saves load |
| `./run_contract.sh` | **PASSES** |

**Prettier and less readable is a loss.** Measure with `_probe_house.gd` before and after, read a
capture you produced yourself, and check its timestamp.
