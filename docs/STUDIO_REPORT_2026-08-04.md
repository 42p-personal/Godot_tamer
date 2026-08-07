# Studio report — 2026-08-04

Every team's findings from one session, consolidated. Ordered by **what it changes**, not by team.

⚠️ **READ §0 FIRST.** Two of this session's most confident findings were FALSE, and both were
caught only by reading code rather than reports. That is the session's most transferable lesson.

---

## §0 — The two false findings, and why they matter

| claimed | severity claimed | actual |
|---|---|---|
| Keyboard-lockout P0 regressed at `stable_ui.gd` / `tactics_ui.gd` | **BLOCKING** | **FALSE.** Both fixed, with inline comments citing the fix. `focus_mode = FOCUS_ALL`, `ui_accept` handled, focus ring repainted on Tab. A third site (`arena_3d.gd:665`) also fine. |
| Kill-target calling (`markedUnit`) is unbuilt and should be built | "near-zero cost, highest value" | **FALSE.** Fully built. Flows `tactics_ui.gd:389` → `targetPriority "manmark"` → `monster_tree.gd:181`, returns the marked enemy with `attribution: "order"`, falls back when it dies. |

**How both happened:** pattern-matching call sites without reading handlers, then stating the
result with a severity rating. The first was relayed onward and briefed into a downstream
accessibility audit, which opened by citing it as evidence that *"this team's findings get
dropped rather than fixed"* — an inference resting entirely on a false premise.

⚠️ **This project's memory already warns about exactly this** (*"grep before believing a doc claim
that a mechanic is missing — three were false in one sweep"*). Today added two more. **A confident
wrong finding is more expensive than no finding, because it gets acted on.**

**Standing rule going forward: verify against the code before assigning a severity.**

---

## §1 — What is BUILT and MEASURED this session

The core loop went from "doesn't make sense" to playable end to end.

| system | evidence |
|---|---|
| **Weekly tick** | `week.gd` 478 lines. 10 bookings in one week: STR 100.0 → 100.0. 15 weeks of powerlift: +23, +8, then 0 forever — stopped by the Wood cap |
| **Plan-then-advance** | `week_plan.gd`. Booking spends nothing; only Advance Week moves the clock |
| **preview vs apply** | 50/50 pairs EXACT, 0 mismatches |
| **Food economy** | 6 weeks paid: 500 → 435g. 3 weeks foraging: gold held, happiness 5 → 3 → 1 → 0 |
| **New-game state** | 0 monsters, week 0, 500 gold, barn 2, lands in Town |
| **Tournaments** | 11 leagues enumerated; Wood sweep promotes to Copper, cap 100 → 200 |
| **Breeding** | dynasty climbs ×1.00 → ×2.00 over 9 generations; Apex ceiling 1100 → 2200 |
| **Lab** | 3 frozen → 36g billed weekly (500 → 356); frozen age 48 → 48, suspended |
| **Tutorial** | 6 steps, advancing off live state |
| **Behaviour tree** | orders produce distinct fights: push 5.94, wings 8.44, dive 6.63 units mean delta vs hold |
| **Contracts** | 219/219 PASS throughout |

### ⚠️ Bugs found by building, not by review
- **`run_contract.sh` named no scene** — it booted the game's title screen, printed nothing, and
  hung until the caller timed out. **An acceptance test that could not fail because it never ran.**
- **`roster.gd` generated 6 monsters at boot** — the full stable at week 1 the user reported
- **Drill penalties live inside `gains` as negatives** (`{STR:+12, DEX:−4}`) — the UI would have
  rendered `+-4 DEX`, and the cap check refused any drill whose *penalty* stat was maxed
- **The tutorial skipped its own most important step** — stamina's condition was `week >= 3`, and
  the step machine fast-forwards past anything already true

### ⚠️ Two things the session got WRONG and corrected
- **"Stamina bounds training."** False. `staminaMalus()` floors at 0.5 and never blocks a drill —
  at zero stamina you train forever at half rate, in tamergame too. **The real wall is the league
  cap.** The spec was corrected in place.
- **"The `/100` stat bars are a bug."** False. They read `Career.current_stat_cap()`, and Wood's
  cap genuinely *is* 100.

---

## §2 — Combat team

**Brief:** *"more like world of warcraft arena, but open to your ideas."*

**The constraint that shapes everything:** the player never intervenes. WoW Arena is real-time
player-controlled; ours has no mid-fight input. So "more like WoW Arena" cannot mean its controls.

**What transfers:** CC as an economy (DR chains), cooldown alignment creating a readable burst
window, peeling as an assignable *role*.

**What does not:** trinket timing, mid-fight juking, moment-to-moment information reads. Faking
these as "auto-trinket AI" would be hollow.

| direction | status |
|---|---|
| **B. Kill-target calling** | ⚠️ **ALREADY BUILT** — see §0. Works, but effect is small: 33 unit-ticks of ~10,800 changed target |
| **A. CC-chain doctrine** | chosen, **unbuilt** |
| **C. Peel role** | chosen, **unbuilt** |
| **D. 3v3 tier** | not chosen — collides with the standing "5v5 is the game" rule |
| **F. Conditional defensive break** | ⚠️ **unpicked, and I think the design agent was wrong to dismiss it.** It called trinket timing untransferable because it's reflex. But a *pre-committed condition* ("break when stunned below 40% HP") is not reflex — it is exactly this game's fantasy, and it makes CC chains two-sided |
| **E. Scouting → counter-picking** | unpicked. Plumbing exists (`gameplanForRivalTeam`) |
| **G. Rehearsed opener** | unpicked |

---

## §3 — Narrative team — COMPLETE (Phases 1-2)

**Premise chosen:** Origin A+C — a **parent's** failed Circuit run left a debt; apprentice papers
are the honest road to clearing it. The player chooses to finish something that was never theirs.
**Not** bloodline destiny. A story beat at **every** league, not just the ends.

⚠️ **An unprompted consistency win:** the world-builder and art-director, working in parallel with
no visibility into each other, **independently placed the debt at the Assayers' Guild** — because
it was the only guild whose established role (*keeps the ledgers*) fit. A third agent then
independently made the Assayers the arena's referee body.

**Files:** `docs/LORE_TAMER_ORIGIN.md` · `design/gdd/DIALOGUE_TAMER_ORIGIN.md` ·
`docs/ART_TAMER_ORIGIN_CAST.md`

- Creditor is a **private stable (Hidebound)**, not a guild — no guild in this canon is ever an
  antagonist, and making one would contradict `WORLD_GUILDS.md` on day one
- The debt-holder is designed **against the villain trap**: chalk-white and well-lit, ledger and
  stamp not menace, *tired precision*
- Opening lines describe the literal start screen — *"Two stalls. Five hundred coin."*

**Open:** Phase 4 consistency review never ran. All canon is **Provisional**.

---

## §4 — Level team — Steps 1-4 complete

**File:** `design/levels/arena.md`

### ⚠️ The measured finding that changed the design
Margin between the LOOSE envelope and the ground's **short** edge is **3.28 units at Wood, 4.6 at
Tin** — computed against `arena_layout.gd`'s real values, not assumed. Too tight for an Assay
podium. **Resolution: the podium is VENUE furniture at every league**, not ground furniture —
structural, rather than adding a special-case exclusion zone to the generator.

### The other verified answer
Cover obstacles are authored **once** into `obstacles[]` and checked against the density law.
Per-unit accessibility indicators are **per-frame paint** from the frame stream and never enter
that array. **Different pipelines — so the fix cannot violate the density law.** Verified by
reading the generator.

### Asset manifest — 6 meshes, not 66
Ring inlay, banner pole, podium-undressed, podium-dressed, stand fascia, booth. Reused across all
11 tiers; escalation is **material-only** across 4 bands. ⚠️ This matters because **no 3D pipeline
has ever been run here** — six meshes is provable with one spike; sixty-six is not.

### Systems findings
- Assay verdict is **cosmetic** — must source from `report_ui.gd:_narrative()`, never a parallel
  description
- **No per-league hazards.** The player reads rather than acts; per-league rule variance is new
  legibility surface for no gameplay the ladder lacks
- **Debt garnish real at `DEBT_RATE = 0.10`** (user chose lower than the 0.15 proposed) — one
  multiplier at `tournament_ui.gd`'s existing purse choke point

### Accessibility — 3 BLOCKING, ⚠️ ALL UNVERIFIED
They share one root cause: **every legibility mechanism assumes a closer camera than the one
approved.** Pulling out to 20–40px silhouettes invalidated the nameplate, the status label and the
team-colour patch at once.

1. Own vs enemy units indistinguishable without colour → ground-plane facing wedge
2. Colourblind players can't read the tier (colour temperature is one weak channel) → league HUD chip
3. Status invisible at silhouette scale (8px text) → screen-space icon anchored above the unit

⚠️ **All three need verifying before action.** The audit that produced them opened by citing the
false keyboard-lockout claim as evidence. **Its premise was wrong; its conclusions are untested.**
All three would need **zero** frame-stream contract changes — `pos`/`facing`/`statuses` already
carry it.

**UNRESOLVED:** `design/levels/town.md` does not exist. The Town lives in `town_ui.gd`.

---

## §5 — UI team — pattern library only; the audit never ran

**File:** `design/ux/interaction-patterns.md` — 11 patterns reverse-engineered from 19 built screens.

**Verified real drift:**
- ⚠️ **`arena_3d.gd` uses ZERO `UiTheme` helpers and ZERO `status_chip()`/`hp_bar()` calls** while
  every other screen uses them. **The live arena has worse status legibility than the disconnected
  screen it replaced.** Highest-leverage single fix on the board.
- `tactics_ui.gd` hardcodes colours that exist as theme tokens
- 140 hand-rolled `StyleBoxFlat` across 12 of 19 files (2 are dead paths)

**Verified consistent:** the sticky action rail; the disabled-button-with-reason pattern (11+ call
sites, every one rewriting button text to explain itself); `tutorial_overlay.gd`'s `mouse_filter`
discipline citing the v0.79 scrim bug it prevents.

**Not done:** the actual audit against tamergame. The phase was spent disproving the library's own
headline finding.

---

## §6 — Art

**Decided:** **low-poly battlefield, painterly 2D for UI** (`docs/ART_BIBLE_LOWPOLY.md`).

The argument is the **camera**, not taste: at 20–40px silhouettes we were paying the *High* cost
band for detail nobody sees. Supporting: authored models make consistency structural rather than
judged-by-eye; geometry unblocks `facing` data the frame stream has always carried but billboards
cannot use; animation collapses from 6 frames × 65 species to one retargeted skeleton.

⚠️ **`ART_DIRECTION.md`'s "flatShading fights high definition" is SUPERSEDED, not violated** — its
precondition was a mixed frame. The lighting doctrine survives intact and renders *better* on real
geometry.

⚠️ **THE BIGGEST UNVALIDATED ASSUMPTION IN THE PROJECT:** both art routes produce **2D images**. No
3D generator has ever run here. If it cannot hold consistency across 65 creatures, **the main
argument for the change collapses.** One creature, end to end, before any roster work.

---

## §7 — The open finding nothing should be built on top of

⚠️ **A 3v3 ran 180 seconds twice with ZERO deaths — both draws.**

**Not a probe artifact:** 4 of the 6 moves every unit carried deal damage (Reckless Slam 58 power,
Blood Fury 42) against SQUISHY's 162 HP. The 5v5 coverage probe **did** resolve (16.7s, winner B),
so the sim *can* end fights — something about this configuration does not.

**Why this outranks everything in §2:** every combat option assumes fights end. You cannot tell
whether marking a target helped if nobody dies either way.

**Next step:** re-run with a short `MAX_DURATION` so the probe returns fast enough to iterate.

---

## §8 — Recommended order

1. **Chase the non-resolving fight** (§7) — blocks all combat work
2. **`arena_3d.gd` theme adoption** (§5) — verified, mechanical, highest-leverage UI fix
3. **Verify the 3 accessibility blockers** (§4) before acting on any
4. **Build A and C** (§2) — genuinely unbuilt, unlike B
5. **Low-poly one-creature spike** (§6) — a negative result overturns a live decision
6. Finish: narrative Phase 4, level Step 5, the UI audit that never ran

**Balance note:** every number added this session is a placeholder. `CLAUDE.md` records the
baseline as **SUSPENDED** — there is nothing to tune against until a deliberate re-baseline.
