# The legibility layer — why my monster did what it did

**2026-08-04.** UX spec for `docs/AUTOBATTLER_DESIGN.md` §6/§8 decision 15: *"Legibility is
both: live intent labels during the fight and a per-monster decision log in the report."*
⚠️ **Nothing here is built.** This is a target design, written mostly against the tree-AI
engine `AUTOBATTLER_DESIGN.md` describes (also not built) — §11 below is explicit about what,
if anything, is worth building **before** that engine lands.

> *"If the player cannot intervene, then (a) every order must be legible enough to predict and
> (b) every outcome must be readable enough to learn from. An unreadable fight is not a hard
> fight, it is a slot machine."* — `CLAUDE.md`

> *"Every one of those is a monster doing something the player would never have chosen and
> cannot explain. That is the bar: not 'is the AI clever' but 'can the player tell why it did
> that, and was it their own order?'"* — `AUTOBATTLER_DESIGN.md` §0

---

## 0. Where this sits among work already decided

Three adjacent systems already exist in design docs. This layer is not a fourth — it is the
substrate underneath two of them, plus a new deliverable neither of them owns.

| system | status | granularity | owns |
|---|---|---|---|
| **The Read** (`FUN_ADDITIONS.md` §1.1) | decided IN | squad/claim — *"Vex reaches their Mender"* | pre-fight declared claims, post-fight ✓/✗ grading |
| **The Broadcast** (`FUN_ADDITIONS.md` §3) | decided IN | squad/shape — *"the wedge is through on the left"* | camera director, commentator, highlights |
| **The Chalkboard** | decided OUT | — | (re-simulating with a changed order — explicitly rejected; not proposed here) |
| **This layer** | this doc | **individual** — *"why did Aegisox fall back"* | live intent labels, per-monster decision log |

⚠️ **The Read cannot be graded, and the Broadcast cannot be commentated, without this layer.**
`FUN_ADDITIONS.md` says The Read's claim-grading "machinery mostly exists" in
`battleReport.ts:analyzeBattle`'s `tacticOutcomes`/`counterRead` — but grading *"Vex reaches
their Mender"* means checking Vex's own decision history: did it lock onto the Mender, when,
and did anything override that. That history **is** the Decision Event stream this doc
specifies (§2). Likewise the Broadcast's commentator needs attributable events to template
sentences from. **Build the stream once; three systems read it.** This doc does not re-litigate
Read or Broadcast — it specifies the shared primitive and the two things that are this layer's
own: the live per-monster label and the post-fight per-monster log.

`docs/TACTICS_DISCLOSURE.md` already named this exact gap and deferred it:

> *"Reflecting orders back in battle... This is the trust half of the design review... disclosure
> makes tactics discoverable; feedback makes them believable."*

This doc is that deferred work. §9 below extends `TACTICS_DISCLOSURE.md`'s reveal map directly
rather than inventing a second disclosure system.

---

## 1. Principles

1. **The vocabulary is not invented twice.** `tactics.gd`'s `TARGET_PRIORITY_INFO` /
   `TEMPERAMENT_INFO` / `MANA_POLICY_INFO` / `FORMATION_INFO` tables (and their future
   `AUTOBATTLER_DESIGN.md` §2 equivalents) are the single source of every name, icon and
   description shown anywhere. A player who chose "🧙 Hunt the casters" before the fight must
   see "🧙 Hunt the casters" in the log — never a paraphrase. `TACTICS_DISCLOSURE.md` already
   states this rule for the editor; this doc extends it to the live layer and the report.
2. **Log the transition, never the tick.** A 90-second fight at 10Hz is ~900 ticks per unit.
   The behaviour tree's active branch only changes a handful of times per fight
   (`AUTOBATTLER_DESIGN.md` §9: *"the branch history is already a decision log"*) — so the
   entire volume problem in the brief is solved by emitting one event per branch change, not
   one per frame. This is the load-bearing decision in this document; everything about density
   downstream depends on it.
3. **Attribution is exactly three buckets, always visible, never colour-only.** ORDER / ITS
   NATURE / REACTED TO. See §4. A player must be able to name which one, every time.
4. **The renderer derives nothing — same rule as `arena_3d.gd`'s existing header comment.** The
   tree decides, the tree emits `{branch, reason, attribution}`; the presentation layer only
   formats and positions it. If the presentation layer starts inferring intent from HP/position
   deltas, that is the exact bug class `SPATIAL_HANDOFF.md` §3 already guards against for
   positions, and it would be subtly wrong here the same way.
5. **Never a fourth colour system.** `ART_THEME.md`'s palette discipline reserves three channels
   (league material / team colour / status-threat) and says explicitly they *"were designed as
   one axis once before and it went wrong."* Attribution and intent use **shape and text**, not
   a new hue family — see §5.
6. **Progressive disclosure is not optional polish here — it is the difference between a
   teaching tool and a wall of jargon for a Wood-league player.** §9.
7. **Solve density with disclosure tiers, not with smaller font.** The earlier nameplate
   failure (labels covering more board than the fight) was a content-vs-space problem; the fix
   is showing less by default and more on demand, not shrinking text below the accessibility
   floor (current nameplate text is already 8–9px — see §10).

---

## 2. The shared primitive — the Decision Event

One data shape, produced once by the AI tree, consumed by the live label, the ticker, the
decision log, and eventually the Read/Broadcast systems. Proposed as a new `kind` in the
existing `log` array (`SPATIAL_HANDOFF.md` §3) — reusing the pattern already established by
`hit`/`miss`/`status_apply`/`death`, rather than a parallel channel:

```gdscript
{
  "kind": "intent_change",
  "t": float,                 # sim seconds
  "unitId": int,               # ⚠️ the frame stream's stable `id`, NOT species name — see note
  "branch": String,            # machine key: "engage" | "hold" | "flank" | "dive" | "guard" |
                                #   "fall_back" | "regroup" | "attack" | "stunned"
  "label": String,             # Tier-1 terse form, player language: "Falling Back"
  "reason": String,            # full sentence, player language — see §5 templates
  "attribution": "order" | "nature" | "reactive",
  "target": int,                # optional unitId this concerns (ally guarded, new target, blocker) — -1 if none
  "importance": "critical" | "standard" | "minor",   # §7
}
```

⚠️ **Use `unitId`, not species name.** `report_ui.gd:_analyze()` already carries a documented
risk here — its per-unit dict is keyed by `species_name`, and the comment flags that two
same-species monsters on one side would collide. That is currently a "not a risk with this
slice's roster" note; a decision log is exactly the feature that would turn it into a real bug
first, since it is the first system to want a genuinely per-monster (not per-species) identity
for authored content. Fix this at the source rather than inheriting it.

**Also produced, not part of the event stream — a static per-unit summary at fight start,**
built directly from the committed tactics dict (`Tactics.committed` today; its future
four-axis equivalent), no simulation required:

```gdscript
{
  "axis": "targetPriority" | "positionalIntent" | "whenHurt" | "abilityPolicy",
  "value": String,             # e.g. "casters"
  "source": "order" | "nature", # was this axis explicitly set, or is it a personality default?
  "info": Dictionary,           # the matching *_INFO entry — name/icon/desc, reused verbatim (§1 rule 1)
}
```

This is cheap: today's `tactics.gd` already distinguishes "key present" (an order) from "key
absent" (default) — `pick_target()`'s `tactics.get("targetPriority", "")` is exactly that check.
The ORDER-vs-NATURE split this document needs is **already the shape of the existing data**, not
new machinery.

---

## 3. Importance tiers (§1 rule 2, continued)

Not every transition carries equal narrative weight. Three tiers, assigned by the tree/AI layer
at emission time (it knows the context; the presentation layer must not have to re-derive it):

| tier | examples | shown |
|---|---|---|
| **critical** | death, the branch active at time of death, `fight on` overriding a death escape, a `disengage` that never returns | always, even collapsed |
| **standard** | target switch, positional-intent trigger (push→dive), when-hurt trigger (healthy→fall back) | shown on expand |
| **minor** | a reactive re-route around an obstacle, a brief blocked-and-intercept moment | collapsed under "+N more" |

This is the second density lever, independent of transition-only logging (§1 rule 2): even
within one monster's (now-short) event list, importance tiering keeps the *default* view to a
handful of lines.

---

## 4. Attribution — the three buckets

⚠️ **This is the single most valuable thing in this document**, per the brief. A player who
cannot tell which of these three happened cannot learn from the fight.

| bucket | means | example phrasing | when it fires |
|---|---|---|---|
| **ORDER** | the active branch is exactly what a tactic setting (team plan or per-monster override) requested | *"— your order: Break the Casters"* | the axis has an explicit value the player set |
| **ITS NATURE** | no order exists on this axis, so personality supplied the default; or personality is qualifying *how well* an order is being carried out | *"— its nature (Aggression 71)"* / *"(Nerve 62, clean disengage)"* | axis unset, OR a stat is materially shaping execution quality of an active order |
| **REACTED TO** | one of the short, closed list of urgent overrides fired (`AUTOBATTLER_DESIGN.md` §8 #27) | *"— reacted: taunted by Corvaan"* | taunted · ordered target gone · about to die with an escape (only if not `fight on`) · ordered destination unreachable |

**Rules that keep this from becoming a fourth catch-all:**

- Exactly one PRIMARY tag per event — never "order and reactive at once." REACTED TO always
  wins the primary slot when an urgent override fires (that is the whole point of the override:
  it is the one thing that can move the branch off what was ordered).
- ITS NATURE may still appear as a **secondary, parenthetical qualifier** on an ORDER or REACTED
  TO line (`Nerve 62, clean disengage`) — it explains execution quality without claiming the
  primary cause. This matches the two worked examples already written into
  `AUTOBATTLER_DESIGN.md` §6, both of which are primarily ORDER with a NATURE qualifier.
- `fight on` beating the self-preservation override (`AUTOBATTLER_DESIGN.md` §8 #28) must be
  visible as its own line when it matters — *"still fighting at 8% HP — your order: Fight On
  overrides the retreat"* — because that is exactly the moment a player most wants confirmation
  that their order, not a bug, kept a monster in a losing fight.
- **No new colour.** Attribution is carried by a text suffix (`"— your order"` / `"— its
  nature"` / `"— reacted to..."`) in both the live tooltip and the decision log. An icon upgrade
  is possible later (§11) but is explicitly not required for v1 — see the cost note in §12.

---

## 5. The vocabulary

### 5.1 Reuse rule, concretely

Every axis already has (or will have) an `*_INFO` table with `{id, icon, name, desc}`. The
vocabulary layer does not author new copy for the axis *value* — it only authors the sentence
**template** that wraps it. Example: `TARGET_PRIORITY_INFO`'s `casters` entry is `{"icon": "🧙",
"name": "Hunt the casters"}`; the decision-log template is:

> `"{unitName} locked onto {targetName} — your order: {icon} {name}"`
> → `"Grivvel locked onto Corvaan — your order: 🧙 Hunt the casters"`

### 5.2 Today vs the full design

⚠️ **`tactics.gd` today is a subset of `AUTOBATTLER_DESIGN.md` §2's four axes** (see §11 for
what that means for build order). Both vocabularies below, so this doc is usable either way.

**Today (`tactics.gd`, buildable now):**

| axis | values | branch/label mapping |
|---|---|---|
| `targetPriority` | weakest (default) · casters · tanks · manmark | not a branch — a target-lock event only |
| `temperament` | aggressive · balanced · cautious | `cautious` → a "refuses risky move" event when it fires; aggressive/balanced have no behavioural difference yet — **the vocabulary must say so**, not imply a distinction that doesn't exist (`tactics.gd`'s own doc comment already states this) |
| `manaPolicy` | normal · conserve | a "held back a cast" event when conserve actually withholds something |
| `formation` | tight · loose | team-level, not per-monster — no live label, shown once pre-fight |

**Full (`AUTOBATTLER_DESIGN.md` §2, the tree AI target):**

| axis | values | Tier-1 label | full-sentence template |
|---|---|---|---|
| target priority | nearest · weakest · casters · tanks · marked · threat | *(shown via target-lock events, not a standing branch)* | `"{u} locked onto {t} — {attribution}: {priority name}"` |
| — commitment | sticky · reassess | *(qualifier only — see §5.3)* | folds into the narrative, not a standing branch |
| positional intent | push · hold · wings · dive · guard | Closing / Holding / Flanking / Diving / Guarding {ally} | `"{u} {verb} — {attribution}: {intent name}"` |
| when hurt | fight on · fall back · disengage | *(no change)* / Falling Back / Disengaging → Regrouping | `"{u} fell back — {attribution}: Fall Back{nature qualifier}"` |
| ability policy | free · hold big · combo | *(qualifier only, no branch)* | folds into a `hit`/`buff` event's flavour text, not a new branch |

### 5.3 Urgent overrides — the closed list (`AUTOBATTLER_DESIGN.md` §8 #27, #28)

Exactly four, plus the blocking-rule tactic (§12 #30). **Nothing else may move a branch off an
order** — this closed-list property is what makes REACTED TO trustworthy rather than a shrug.

| trigger | label | template |
|---|---|---|
| taunted | Forced | `"{u} was pulled onto {t} — reacted: taunted"` |
| ordered target gone | Retargeting | `"{u} switched target → {t} — reacted: ordered target fell"` |
| about to die, escape available (blocked if `fight on`) | Fleeing | `"{u} broke off — reacted: about to die, took the opening"` |
| ordered destination unreachable | Rerouting | `"{u} rerouted — reacted: the ordered position was unreachable"` |
| blocked, tactic = intercept | Engaging | `"{u} engaged {blocker} instead — your tactic: Intercept"` |
| blocked, tactic = bull through | Pushing Through | `"{u} pushed past {blocker} toward {t} — your tactic: Bull Through"` |

### 5.4 Commitment (`sticky` vs `reassess`) — the direct TFM fix

This does not need its own live branch (constantly re-announcing "still committed" would be
noise) — it needs to be **visible in its absence**: when a `sticky` monster does *not* switch to
a lower-HP target, nothing happens on screen, which is correct, but it means the *only* place
this shows up is the causal narrative (§8): *"Grivvel held its target the whole fight (Focus 81:
sticky) — never distracted by [ally]'s target dipping low."* This is a case where the decision
log's absence of switching IS the story, and only the narrative layer, which looks at the whole
event list at once, can say so. Flagging it here so it is not lost when someone only reads §2–§6.

---

## 6. The live layer ("The Broadcast," individual granularity)

Three disclosure tiers over the same event stream, cheapest first. ⚠️ **Solves the named
failure directly**: an earlier pass put full content on every nameplate at all times, which is
exactly what breaks at 10–12 units. Each tier below adds *nothing* to on-screen footprint until
the player asks for it, except Tier 1's single glyph.

### Tier 1 — the intent glyph (always on, ~zero footprint)

One small glyph on the existing nameplate (`arena_3d.gd:_make_plate()`), next to the team
badge — not replacing the HP bar or name, and not growing the plate. Precedence rule, since a
unit can be several things at once:

1. `stunned` / hard-CC state (from the frame's existing `state` field) — a unit doing nothing
   because it *cannot* is the single most important "why is nothing happening" signal, and it
   overrides whatever the tree's branch says underneath.
2. `dead` — no glyph, plate already dims (`_topple()` already does this).
3. Otherwise, the current branch's glyph.

| branch | suggested glyph (placeholder, see note) |
|---|---|
| engage/closing | → |
| attacking | (no separate glyph — the existing hit/miss float-text already covers this instant) |
| holding | ▬ |
| flanking (wings) | ↗ |
| diving | ↘ |
| guarding | (reuses an existing "protect" glyph — see note) |
| falling back | ← |
| regrouping/disengaged | ⋯ |
| stunned/hard CC | ⊘ |

⚠️ **These glyphs are placeholders and not mine to lock.** `tactics.gd` already uses ⚔⚖🛡🎲🧙🐘🎯💠💧🤝↔ and the gameplan table uses 🔥🛡☠🎯🌩 — before any of these ship, someone needs to
cross-check the full glyph inventory across `tactics.gd`, `art.gd` (team badges ◆▲●■★✦⬟✚) and
the eventual status-icon set (`ART_THEME.md` §3) so nothing collides or reuses a symbol with a
different established meaning in the same screen. Flag to **ui-programmer + art-director** as a
locking pass, not a decision this document makes. Zero art budget required either way — these
are Unicode glyphs, same as every icon already in `tactics.gd`, consistent with the project's
"the game must run with zero art" doctrine (`art.gd`'s own header).

**Colour:** none. Team colour already lives on the plate border; HP threat gradient already
lives on the fill bar. The glyph is drawn in a neutral ink (the same off-white as the unit name)
so it never becomes a fourth colour channel (§1 rule 5) — shape carries the meaning, exactly like
the team badge already does.

### Tier 2 — the expanded callout (on demand, one at a time)

Selecting a unit (click, or the keyboard/gamepad focus-cycle in §10) expands a single callout
near its plate showing: the full sentence for its *current* branch (`label` + `reason` +
attribution suffix), and its Orders Summary (§2) — the 4-axis table, each row tagged ORDER or
NATURE. **Only one callout open at a time** — opening a second closes the first. This is the
mechanism that keeps Tier 2 from ever competing with Tier 1 for board space, since by
construction at most one extra block of text exists on screen.

Font size for this callout should be a normal readable size (14–16px) — it is not fighting for
nameplate real estate the way Tier 1 is, so there is no reason to inherit the nameplate's
8–9px constraint (§10 flags that constraint as already marginal).

### Tier 3 — the event ticker (always on, off the 3D scene entirely)

`arena_3d.gd` already has a scrolling text panel (`log_view`, currently fed by `_log_event()`'s
`hit`/`miss`/`status_apply`/`status_expire`/`buff`/`death` cases). Add one more case,
`intent_change`, filtered to **`standard` and `critical` importance only** (§3) — `minor` stays
out of the always-on ticker, available only inside a selected unit's Tier-2 callout or the
post-fight log. This reuses an existing, already-accessible, already-scrolling panel rather than
adding new UI surface, and it is the piece that gives an ambient "what's the story so far" read
without requiring the player to click anyone.

---

## 7. The decision log (post-fight)

Extends `report_ui.gd`'s existing per-unit row (`_unit_report_row()`), which today shows only
`dealt`/`taken`/`survived`. Each row becomes expandable (accordion, matching the Tier-2 pattern
above so the interaction vocabulary is consistent across the live screen and the report):

1. **Orders Summary** (§2's static block) — always visible on expand, 4 lines, ORDER/NATURE
   tagged, using the exact `*_INFO` copy (§1 rule 1). This alone teaches a new player what
   "personality supplies a default" means, every single fight, with zero extra authoring.
2. **Critical events** — shown unfolded even before expand (a one-line teaser on the collapsed
   row itself: *"fell at 19.1s — was diving alone, no ally in support"*, sourced from §8).
3. **Standard events**, chronological, shown on expand.
4. **Minor events**, collapsed under a `+N more` toggle inside the expanded view — the third and
   final density lever, for the rare unit whose fight was genuinely eventful.

⚠️ **Do not build one combined chronological feed for the whole fight.** Ten to twelve units'
events interleaved in one timeline is exactly the "thousands of ticks" wall of text the brief
warns against, even after transition-only logging and importance tiering — per-monster,
collapsed by default, is the structure that scales to Tamer Elite's 6v6.

---

## 8. The causal narrative

`report_ui.gd:_narrative()` already produces one sentence from the first death:
*"Turning point: {killer} brought down {victim} at {t}s, and the fight never came back level."*
This is the hook. Extend it, deliberately narrow in scope (see §12 for why this stays narrow):

**Extension 1 — attribute the death.** Look up the victim's *active* decision event at time of
death and fold its `reason` in: *"...Aegisox had been diving alone since 8.2s (your order:
Dive) with no ally in support range, and the fight never came back level."* This needs one
spatial check the frame stream already supports (`SPATIAL_HANDOFF.md`'s `pos` per unit per
frame) — is any ally within support range at the moment of death — run **only** for the one or
two deaths the existing analyzer already treats as significant (first death, the death that
decided it), never as a per-event enrichment pass over the whole log (§12, cost item 3).

**Extension 2 — surface commitment's absence** (§5.4), when it was the story: *"Grivvel held its
target the whole fight (Focus 81) — never distracted when Corvaan's target dipped low."* Detect
by: a `sticky` monster whose target-lock event list has exactly one entry, cross-referenced
against whether a *lower-HP* enemy existed and was reachable at some point mid-fight (a second
narrow, bounded check — not a general "explain everything" pass).

⚠️ **Cap the pattern list at two or three hand-authored detectors** (isolation-at-death,
commitment-paid-off/backfired). A general-purpose "explain the whole fight" narrative generator
that tries to cover every possible causal shape is the single largest scope risk in this
document — see §12 item 1.

---

## 9. Progressive disclosure

Extends `TACTICS_DISCLOSURE.md`'s existing treatment vocabulary (Always / Hidden / Lock-with-hint
/ Absent) rather than inventing a second taxonomy. **New rule this doc adds:** a live intent
label or decision-log entry for an axis must never appear before that axis's own control is
revealed in the editor — the words on screen and the words on the dial must unlock together, or
a Wood-league player sees vocabulary ("Diving") they have never been given the means to set.

| axis / label | reveal predicate (same as the editor control) | effect on this layer while hidden |
|---|---|---|
| Target-lock events | `teamTacticsUnlocked` (Copper license) | before Copper: no target-switch events logged at all — target priority is forced `weakest`, so there is nothing to attribute; the Orders Summary row for this axis is omitted, not shown-and-locked |
| Positional intent branches (push/hold/wings/dive/guard) | *(needs a predicate once the axis itself ships — likely tied to team-size leagues, since solo 1v1 has no lateral goal to speak of)* | before unlock: every monster's positional label is the single fixed default (`push`), and it is never shown as a distinguishable branch — one universal state has no information value |
| When-hurt policy | *(needs a predicate — plausibly the same license gate as target priority, since both are "team tactics")* | before unlock: `fight on` is the forced default; no fall-back/disengage vocabulary appears anywhere |
| Formation | `teamSizeForLeague(t.league) > 1` | before unlock: no per-monster label at all (formation is team-level, §5.2) |
| Attribution tags (ORDER/NATURE/REACTED) | *(scales with the above — see note)* | see below |

**Attribution complexity should itself scale.** At Wood league, where most axes are forced
defaults, almost every event is NATURE by construction — showing the three-way tag prominently
there teaches nothing yet, since the player hasn't set anything to compare against. Recommend:
the attribution suffix stays in the sentence at every tier (§1 rule 3 — never omit it, that
would break "always tell them which of the three"), but the **Orders Summary block** (§7 item 1)
only appears once the player has set at least one real order — before that, a single line
suffices: *"No standing orders yet — every monster is following its own nature."* This is a
polish recommendation, not a hard requirement; flag to game-designer/systems-designer since it
touches the same unlock predicates `TACTICS_DISCLOSURE.md` owns, not a call this document can
make alone.

**The ladder becomes a diegetic tutorial for the vocabulary itself, for free:** the first time
"Diving" can appear on a nameplate is the same tournament where the player first got to *tick*
Dive in the editor. No separate tutorial content is needed if — and only if — this reveal
coupling is honoured everywhere.

---

## 10. Accessibility pass

| checklist item | status / requirement |
|---|---|
| Keyboard only | Tier-2 expansion (§6) must have a keyboard path, not mouse-hover-only: a Tab/arrow-key cycle through living units in a fixed order (matching the frame stream's stable `id` order), Enter/Space to expand, Esc to close. The decision-log accordion (§7) is already keyboard-native (standard focus + Enter) if built with real focusable controls rather than paint-only panels. |
| Gamepad only | Same cycle as keyboard, mapped to d-pad/stick + a confirm button. Gamepad is "plausible later, not committed" per `technical-preferences.md` — this doc does not require it now, only asks that the interaction model (discrete next/previous focus, not continuous mouse position) not preclude it later. |
| Readable at minimum font size | ⚠️ **Current nameplate text is already 8–9px** (`arena_3d.gd:_make_plate()`) — likely already marginal against a real accessibility floor. Do not add to that constraint: Tier 1's glyph must be a separate small icon, never additional text sharing the cramped nameplate line. Tier 2's callout and the decision log both get normal UI text sizes (14–16px+), since neither competes for per-unit board space. |
| Not colour-only | Attribution is text-suffix, not colour (§4). Tier-1 glyph is shape-coded, not hue-coded (§6), consistent with the existing team-badge precedent in `art.gd`. |
| No flashing without warning | If a "branch just changed" highlight is added to a nameplate later, it must be a single one-shot fade, never a repeating flash — simpler and more conservative than reasoning about a specific Hz threshold, and consistent with `ART_THEME.md`'s "under fire" pulse already being a slow glow, not a strobe. |
| Subtitles | No dialogue in this layer. Note for later: if audio barks (a taunt cue, a death cry) are ever added, the event ticker (§6 Tier 3) is the natural caption channel and must carry them the moment they exist. |
| UI scales at all resolutions | Tier 1/2 reuse the existing screen-space projection pattern already in `arena_3d.gd:_update_plates()` (`camera.unproject_position`). Tier 2's callout additionally needs viewport-edge clamping (it must not run off-screen for a unit near the board's edge) — a concrete implementation note, not solved here (out of this document's lane per "do not implement UI code"). |

---

## 11. Build order — what's real today vs after the tree AI

⚠️ **The honest constraint: almost none of this has anything to attach to yet.**
`battle_sim.gd` (today's actual fighting engine, per `SPATIAL_HANDOFF.md` §5's "kept as the
reference implementation") has no positions, no behaviour tree, no branches — only a flat
per-turn move-choice policy. There is very little "intent" to report beyond a target lock and
whether `cautious` skipped a self-harm move. **The true payoff of this whole document arrives
with the tree AI**, which is itself "nothing here is built yet" per `AUTOBATTLER_DESIGN.md`'s own
header.

Given that, recommended sequencing:

1. **A cheap interim slice, buildable now, against today's `tactics.gd`.** Add the Orders
   Summary block (§2, ORDER vs NATURE) to `report_ui.gd`'s existing per-unit row, using only the
   four fields `tactics.gd` already tracks (`targetPriority`, `temperament`, `manaPolicy`,
   `formation`). No new event stream, no new sim work — purely reading data that already exists.
   **This is worth doing before the tree AI lands**, because it validates the ORDER-vs-NATURE
   framing and the "reuse the `*_INFO` copy" rule (§1) cheaply, on real screens, before betting
   the fuller design on them.
2. **The Decision Event stream + Tier 3 ticker**, once the spatial/tree AI rebuild
   (`SPATIAL_HANDOFF.md`) lands with real branches to report. This is the first point at which
   "intent" means anything beyond a target lock.
3. **Tier 1 glyphs**, once (2) exists and a handful of real fights have been watched to confirm
   the branch set (§5.2) is actually the right one to render — cheap to add, but only after the
   branches are believed stable, since re-authoring glyph mappings is wasted if the tree's
   branch set moves.
4. **Tier 2 callouts and the full decision-log accordion**, last of the four — the most
   UI-engineering-heavy piece (hit-testing, keyboard cycling, clamping) and the one most worth
   getting the content right for before investing interaction polish.
5. **The causal-narrative extensions (§8)**, in parallel with or after (2) — they are pure
   analysis over the same stream, no new UI surface.

---

## 12. Honest verdict — what's too expensive for its value

Asked directly, in order of risk:

1. **A general-purpose "explain the whole fight" narrative generator.** The single biggest scope
   risk here. §8 caps it at two or three hand-authored pattern detectors on purpose. A system
   that tries to cover every conceivable causal shape (focus-fire concentration, a healer never
   getting to act, a tank dying first, a formation collapsing) is a mini expert system, and this
   project's own balancing doctrine ("one value at a time... trust the sim over intuition")
   argues against building broad, unmeasured machinery. Start narrow; expand only against a real
   fight someone watched and found the narrative missing something specific.
2. **A bespoke icon set commissioned up front for both intent branches (~8) and attribution
   (~3).** That is 11+ new icons on top of the already-planned status-icon set (`ART_THEME.md`
   §3) and the existing team badges. §4 and §6 both specify text-first, Unicode-glyph-placeholder
   in the meantime — real art spend should wait until the mechanic is proven legible in
   placeholder form, per this project's own "must run with zero art" doctrine (`art.gd`).
3. **Spatial-correlation analysis (isolation checks, support-range checks) run over every logged
   event.** Restrict it to the one or two deaths the narrative already treats as significant
   (§8) — an O(events × frames) enrichment pass over the *entire* event list is exactly the kind
   of over-general cost that doesn't pay for itself; the existing `_narrative()` is already
   selective ("biggest hit," "turning point"), and this extension should stay that selective.
4. **A live replay scrubber** (pause and rewind to any point during playback, not just forward
   playback + a fixed post-fight log). Genuinely useful, but real UI-programmer work (seekable
   frame playback synced to a rewound ticker state) — and the post-fight decision log already
   gives "go back and check what happened," without needing to re-scrub the 3D scene. Defer to
   v2. ⚠️ Note this is **not** the rejected Chalkboard (that's re-simulating with a *changed*
   order; this is reviewing the *same* fight again) — worth stating explicitly so the two don't
   get conflated and this gets rejected for the wrong reason.
5. **Full mouse-hover polish for Tier 2** (smart disambiguation when two nameplates visually
   overlap because units are standing close together, animated open/close, etc.). Real, but an
   interaction-design edge case for **ui-programmer** to own, not something to over-specify here
   — flagged, not solved, consistent with this document's "do not implement UI code" boundary.

**What is *not* too expensive, and is the actual recommendation if only one thing ships:** the
interim slice in §11 item 1 (Orders Summary, ORDER-vs-NATURE, against today's engine) plus §11
item 2 (the Decision Event stream itself, transition-only). Everything else in this document is
presentation on top of those two — real, valuable, but strictly optional relative to them. The
event stream is the one piece three other decided systems (Read, Broadcast, this layer's own
post-fight log) all need; the presentation tiers on top of it are where this document's own
honest cost list above should guide trimming if the budget doesn't stretch to all of them.

---

## 13. Open questions / handoffs

- **`report_ui.gd`'s species-name keying should become `unitId`-keyed** before a decision log
  is built on top of it — flagged in §2, owned by whoever next touches `report_ui.gd` or
  `battle_sim.gd`'s log emission (gameplay-programmer / lead-programmer).
- **Tier-1 glyph selection needs a cross-check against every existing icon** in `tactics.gd`,
  `art.gd` and the future status-icon set before locking (§6) — ui-programmer + art-director.
- **Positional-intent and when-hurt reveal predicates** (§9) don't exist yet because the axes
  themselves don't exist yet — needs a decision from game-designer/systems-designer alongside
  building the tree AI, not from this document alone.
- **Tier-2 hit-testing when nameplates overlap** (§12 item 5) — ui-programmer.
- **This document assumes the tree AI's branch set from `AUTOBATTLER_DESIGN.md` §2 ships
  roughly as designed.** If that set changes materially, §5.2's "full" vocabulary table needs a
  pass, but §1–§4's principles (transition-only logging, three-bucket attribution, no fourth
  colour) do not depend on the exact branch list and should survive unchanged.
