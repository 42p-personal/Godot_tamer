# Meta-game disposition — `town.ts` / `game.ts` / `monster.ts` against the 3D-ranch model

**Written 2026-08-04.** Closes open item #5 in `docs/HANDOVER.md` ("Meta-game disposition —
`town.ts`/`game.ts`/`monster.ts`, 4,170 lines, still unplanned") and gives `docs/GODOT_MIGRATION.md`
§7 step 6 ("Move the meta-game — when there is a reason to, not before") something to check against
when that reason arrives. **This is a planning document. Nothing here is built, and nothing here
authorises starting the move — it makes the seams visible for whenever it does.**

⚠️ **THE MODEL THIS DOCUMENT IS SCORED AGAINST** (`docs/DECISIONS_2026-08-03.md` #10, deferred):
*"a 3D ranch you look into, with your monsters visibly present and doing what you assigned them,
and interface over the top."* **PRESENCE, not TRAVERSAL.** The standing test for anything that
looks like more than that: **does moving/adding a thing REPLACE an interaction, or sit in front of
one?** A corridor to the same menu is worse than the menu. Every disposition below is judged against
that test, not against "would this be nice."

---

## 0. The three dispositions, and what each one means in practice

| disposition | what it means | existing precedent |
|---|---|---|
| **(a) Pure port** | The TS logic becomes GDScript with no interface change — same shape as the four combat contracts. Testable by diffing inputs/outputs, no scene, no visuals. | `scripts/damage.gd`, `derive.gd`, `status_math.gd`, `tick.gd` against `combat.json` etc. |
| **(b) New presentation layer** | The logic still ports as (a), but something in the 3D ranch scene or a battle scene must ALSO exist to satisfy "visibly present and doing what you assigned" — a node state, an animation, a placement rule. This is new work with no precedent yet. | None built. This is the gap this document exists to name. |
| **(c) UI overlay** | Stays a menu/screen drawn over the 3D backdrop — Godot `Control` nodes instead of React DOM, but functionally the same shape of interaction. No monster-presence requirement. | Implied by "interface over the top," not yet built either, but requires no new *design*, only a UI reskin. |

Several systems below are **(a) + (b)** or **(a) + (c)** — the underlying math always ports as (a);
the open question is almost always whether presentation needs (b) or can stay (c).

---

## 1. The weekly tick — `town.ts:advanceWeek()`

**(a) Pure port.** `advanceWeek` is a pure `GameState → GameState` function: seeded RNG
(`mulberry32`), no DOM, no timers, no rendering. It already reads like the tick contract
(`scripts/tick.gd`) in shape — deterministic, testable by diffing before/after state. Ports the
same way `applyWeek`/`previewWeekEffects` would.

**Presentation question — genuinely open.** Two readings of "monsters visibly present and doing
what you assigned them":

1. **State-reflects, not replays.** The tick resolves instantly (as it does today); the ranch
   scene reads the *resulting* `weekPlans[monster.id].activity` and shows each monster's sprite in
   an idle loop appropriate to that activity (training yard / feeding trough / resting pen / away
   at a cup) until the next tick. No animation of the computation itself — just a placement +
   pose that updates once per week.
2. **Tick plays out.** The week advance becomes a short visible sequence — monsters seen moving to
   their stations, training, being fed — before the results land. This is closer to a played
   cutscene than a menu action.

**Recommendation (not a decision): reading 1.** It satisfies "visibly present and doing what you
assigned" without adding a new time-cost to a week that repeats ~400 times over a career — the
1,708-match career-length finding in `docs/FUN_ADDITIONS.md` is about fights, but the same
compression logic applies to a mechanic that fires every week for the whole game. **This needs the
user's call, not an assumption** — flagged as open question 1 below.

---

## 2. Feeding — the `'feeding'` phase

**(a) Pure port.** `buyFood`, `forageFeed`, `foodHappinessDelta`, `foodStaminaDelta`,
`foodTrainMult`, `rollMarket` are all pure `Career`/`GameState` functions. The sequential
per-monster walkthrough exists in `App.tsx`'s `RanchView` because favourite/hated food differs per
monster and can't be a single bulk-feed button (`CLAUDE.md`, Weekly Tick section) — that reasoning
is presentation-layer, not engine-layer, and survives unchanged.

**(b)/(c) — open, and this is the one the "presence" test bites hardest on.** Two credible shapes:

- **(c) UI list, re-skinned.** The current per-monster feeding walkthrough becomes a Godot overlay
  screen — same interaction shape, new widget toolkit. Fast, no new design risk.
- **(b) Visible trough.** Monsters cluster at a feeding-station node in the ranch scene; assigning
  a food triggers a short eat reaction on that monster's sprite. Adds presence, costs an
  animation/reaction state per monster (or per body-type, if generalised).

**Recommendation (not a decision): keep the per-monster CHOICE as (c) — it is a deliberate,
differing-preference decision and a list is the fastest way to make ten of those in a row — but
dress the ranch backdrop with (b) as decoration**, i.e. monsters idle near a trough node while
the list interaction happens over it. This passes the presence-vs-corridor test: the list is not
replaced by walking to a trough, it sits in front of a ranch that already looks lived-in.
⚠️ **This is a judgment call, not a derivation** — see open question 1.

---

## 3. Training / drills — `src/drills.ts`, `game.ts:rollDrillGain`

**(a) Pure port.** `rollDrillGain`, `statCapFor`, `gearHeritageMult`, the 30 drill definitions
(6 basic + 12 intensive + 6 extreme + 6 diverse) — pure math and data tables, same shape as the
combat pool (`data.json`). No spatial reasoning anywhere in this code today.

**(b) New presentation layer, and it is the biggest concrete gap this document found.** Decision
10 explicitly wants monsters seen **doing** their assigned activity, and training is the single
most common weekly assignment. That requires, at minimum:

- A **station** in the ranch scene per broad activity (training yard, rest pen, feeding trough,
  away-at-cup — NOT per individual drill; 30 distinct visual stations for 30 drills would be
  authoring debt with no gameplay payoff and directly contradicts `FUN_ADDITIONS.md`'s "the
  constraint on this game is not content, it is attention").
- An **idle/loop pose** per monster per station. ⚠️ **This is gated by the still-open creature-art
  strategy** (`docs/GODOT_MIGRATION.md` §5: 2D sprites in 3D / rigged 3D / hybrid). A 2D billboard
  swapping between a handful of pose frames is cheap; a rigged animation state per species is not,
  and 65 species × even 4 ranch poses is 260 clips on top of the ~325 already flagged for battle.
- Whether the granularity is **per stat trained** (6 states: STR/DEX/CON/WIS/INT/CHA) or coarser
  still (training / resting / competing / away, 4 states) is undecided — see open question 2.

**Recommendation (not a decision):** the coarsest granularity that still reads as "doing what you
assigned" — likely 4 states, not 6 or 30 — is the right default until a playtest says otherwise,
consistent with `FUN_ADDITIONS.md`'s repeated warning against adding content ahead of legibility.

---

## 4. The stable/ranch screen — `RanchView` in `App.tsx`

**This IS the "ranch you look into."** In scope for the presence treatment by definition, not by
inference.

**What it needs from the data model that it does not have today:**

| need | today | gap |
|---|---|---|
| Which monsters are visibly IN the ranch | `game.stable.filter(c => !c.retired)` | Frozen monsters (`g.labFrozen`) are in the stable-adjacent data but conceptually stored away — should they be absent from the 3D ranch, the way "frozen" already implies? Not decided — see §5. |
| Where a monster's sprite sits / what pose it holds | Nothing — `weekPlans[id]` only carries `{ activity, food }` | A ranch scene needs SOME mapping from `activity` (drill id / `'rest'` / `'excursion'` / `'compete'`) to a station + pose. Recommend this mapping lives in Godot-side scene logic, derived from the existing `activity` string, rather than adding a new `GameState` field — no new save data, no new source of drift between `applyWeek` and `previewWeekEffects`. |
| Which monster is "away" this week | `competing` set in `advanceWeek`, and `activeCup` | Already computable; a monster entered in a cup should visibly not be on the ranch floor (or be shown departing) — cheap payoff, no new data needed. |

**What ports vs. reskins vs. gets replaced:**

- **(a) Pure port**: everything that reads `GameState`/`Career` and computes a value — training
  preview via `previewWeekEffects`, stat caps, aptitude tags, bloodline potential display math.
- **(c) UI overlay**: the stable strip, the detail panel, the training row, the sticky action
  rail — same interaction shape, redrawn in Godot `Control` nodes.
- **NOT part of the ranch at all**: `RanchView`'s `phase === 'battle'` branch (the tournament
  bracket hub, `LiveStandingsCard`, the post-cup announce screen) is currently nested inside the
  same React component as the ranch, but conceptually belongs to the tournament/battle seam (§6),
  not to the ranch-as-a-place. ⚠️ **This is a component-boundary fact about the React code, not a
  design fact** — do not carry the coupling into Godot. The ranch scene and the battle/bracket
  flow should be separate scenes connected by a transition, the way §6 describes.

---

## 5. Market / breeding / licensing / lab

Covers: `rollMarketOffers`/`buyMonster` (market), `breed`/`breedPotentialV2` (stud farm),
`freezeToLab`/`thawFromLab`/`fuse` (lab freezer), `buyLicense`/`startTrial`/`startRite`
(licensing), `buyComfortItem`/`buyGear`/barn upgrades (ranch shop).

**(a) Pure port, uniformly.** All of it is `GameState → GameState` transaction functions with no
rendering dependency — the same category as the tick.

**(c) UI overlay, by default — transactional screens over a 3D backdrop, not presence-driven.**
None of these are "watch a monster do a thing"; they are "spend gold, get a result." A market
stall prop or a lab building exterior in the town/ranch establishes *place* (consistent with
"presence" as a value generally) but does not need per-monster animation states the way training
does.

**Two real exceptions worth flagging, not resolving:**

1. **Breeding/fusion produces a new monster that should presumably APPEAR in the ranch afterward**
   — a small, cheap presence payoff (the new hatchling shows up on the ranch floor) that costs
   nothing beyond instantiating its node, and pays for itself as a "moment."
2. **The lab freezer conceptually removes a monster from the visible ranch, and thawing returns
   it.** If frozen monsters are simply absent from the ranch-floor node list, that is presence
   working correctly with zero extra design (a frozen monster genuinely isn't there); if the
   intent is ever to make the lab ITSELF a place you look into (mirroring the ranch treatment),
   that is new scope on the same shape as decision 10 and should be named as such if proposed
   later, not smuggled in as "just the lab UI."

---

## 6. Tournaments — calendar, sign-up, round-robin, rival teams

Covers: `tournamentCalendarFor`, `signUp`/`cancelSignUp`, `eligibleForTournament`,
`generateRivalTeamsForTournament`, `roundRobinSchedule`, `rewardMultiplier`, `finalizeCup`,
`gameplanForRivalTeam`.

**(a) Pure port.** Same shape as §1 and §5 — seeded generation, deterministic scheduling, no
rendering coupling. `docs/DECISIONS_2026-08-03.md` #17 ("rival class comes from rolled stats") and
the seeded-rival-team machinery already assume this.

**(c) UI overlay for everything EXCEPT the fight itself.** Sign-up, the scouting screens, the
bracket hub, `BracketGrid`/`LiveStandingsCard`/`MatchAnalysis` are all list/table presentations —
"which cups are open, who's in the field, what's my read on them, what's the standing" is
information, not spectacle, and stays a menu over a backdrop (a notice-board prop in town, or the
ranch itself, is enough to place it).

**The seam, stated explicitly:** Ranch/Town UI (sign up → scout → set tactics) → **hard scene
transition** to the arena for the fight itself (owned by `docs/ARENA_BLUEPRINT.md` and the
Godot arena rework, out of this document's scope) → **hard scene transition back** to a
results/announce UI. The fight is the ONLY part of the tournament pipeline that goes spatial;
everything either side of it is (c).

⚠️ **A dependency this document surfaces but does not resolve:** the sim actually driving
`LiveStandingsCard`/`resumeOutcomes`/`buildEventPlayerTeam` today is `simulateTeamBattle` from
`battle.ts` — the engine `CLAUDE.md` and `docs/GODOT_MIGRATION.md` both say is being retired in
favour of `tamerengine`. The tournament UI's pure-logic layer (schedule, standings, rewards) is
engine-agnostic and unaffected by that swap, but the actual match results it displays will change
source before this ever reaches Godot. Not a blocker for this document's dispositions, but worth
knowing before wiring the seam concretely.

---

## 7. Events — `rollWeeklyEvent`, `resolveEvent`, `EventModal`

**(a) Pure port.** Weighted candidate selection off seeded RNG, `bakeEvent`/`resolveEvent` as pure
state transitions — same shape as everything above.

**(c) UI overlay, and this is the one with the least ambiguity in the whole document.** A blocking
choice modal is exactly "interface over the top" as written — it interrupts the feeding screen,
presents 2-4 choices, and resolves. No presence requirement: an event is a decision, not a place.

**One cheap, optional flavour note, not a requirement:** career-scoped events (the majority — see
`ev.scope === 'global'` vs. per-`Career` in `rollWeeklyEvent`) name a specific monster. Showing
that monster's portrait or a glance at its ranch node while the modal is open is free flavour that
reinforces presence without becoming a new interaction — safe to defer indefinitely, never
load-bearing.

---

## 8. Monster generation & derived stats — `monster.ts`

Two halves, already dispositioned by `docs/GODOT_MIGRATION.md`, restated here for completeness
because the task named this file explicitly:

| half | disposition | already true |
|---|---|---|
| **Derived combat formulas** — `maxHp`, `maxMana`, `dodgeChance`, `hpRegen`, `manaRegen`, `critChance`, `mitigationPierce`, `echoChance`, `debuffReduction`, `debuffBonus`, `attackStat`, `manaCost` | **(a) Pure port — DONE.** | Contracted today via `derive.json`/`scripts/derive.gd` (46 cases) and `classify.json` (46 cases, class/role/free-attack derivation). No further work needed from this document. |
| **Generation & draft** — `generateMonster`, `chooseLoadout`, `learnedMoves`, `applyTraining`, `boostConstitution`, `rollTameness` (⚠️ tameness itself is removed per decision #1, the roll function is dead code to clean up whenever this file is touched) | **Explicitly OUT of the port, permanently**, per `docs/GODOT_MIGRATION.md` §2 ("`generateMonster`, `chooseLoadout`, `ALL_MOVES` and the draft rules are out of scope for the port, permanently. They stay in TypeScript, or get rebuilt later on their own terms.") | No presentation implication — this is generation-time math, not something a player watches happen. Restated here only so it isn't re-discovered as "missing" later, per `HANDOVER.md`'s standing warning. |

No new disposition work needed here; the split was already made correctly and this document just
carries it forward.

---

## 9. Summary table

| system | pure port (a) | new presentation (b) | UI overlay (c) | status |
|---|---|---|---|---|
| Weekly tick (`advanceWeek`) | ✅ | open question | — | needs a user call (§1) |
| Feeding | ✅ | recommended as decoration only | recommended as the interaction | judgment call, not decided (§2) |
| Training/drills | ✅ | **yes — the biggest concrete gap** | — | needs station granularity + creature-art strategy (§3) |
| Ranch/stable screen | ✅ | yes, by definition (it IS the ranch) | ✅ (the menus over it) | data-model gap named (§4) |
| Market/breeding/licensing/lab | ✅ | no, except 2 small exceptions | ✅ | low risk (§5) |
| Tournament calendar/sign-up/standings | ✅ | no (the fight itself is the exception, owned elsewhere) | ✅ | seam stated, one engine dependency flagged (§6) |
| Events | ✅ | no (optional flavour only) | ✅ | least ambiguous item in the document (§7) |
| `monster.ts` derived stats | ✅ done already | — | — | closed, restated for completeness (§8) |
| `monster.ts` generation/draft | permanently out of the port | — | — | closed, restated for completeness (§8) |

---

## 10. Open questions — need a user decision before implementation starts

1. **Does the weekly tick resolve instantly with the ranch reflecting result state, or does it
   play out as a short visible sequence?** (§1) Changes whether the tick stays a pure background
   service or needs its own timing/animation budget. Recommendation given: instant + reflect,
   because it repeats every week of a career already flagged as very long
   (`docs/FUN_ADDITIONS.md`'s 1,708-match finding is about fights, but the same volume argument
   applies to any weekly ritual).
2. **Is feeding a menu the player runs, decorated by a visible trough, or does the trough itself
   become part of the interaction** (dragging food onto a monster's ranch node, say)? (§2) The
   presence-vs-corridor test cuts against the latter unless it's demonstrably faster or more
   satisfying than the list, which nobody has playtested either way.
3. **What granularity of ranch "station + pose" does training need** — per stat (6), per broad
   activity (4), or something else — and does that answer wait on the creature-art strategy
   decision (`docs/GODOT_MIGRATION.md` §5, still open) or can it be decided independently? (§3)
4. **Should the lab freezer (and/or Hall of Fame retirement) ever become a second "place you look
   into," mirroring the ranch treatment, or do they stay pure menus permanently?** (§5) Not asked
   by decision 10 as written, but the freezer's "monster physically absent from view" framing
   sits right next to the presence idea and someone will propose it eventually — better to have
   an answer on record than to design it twice.
5. **When is "a reason to" move this code, per `GODOT_MIGRATION.md` §7 step 6?** This document
   does not create that reason — it is scoped to make the seams visible for whenever the reason
   arrives (most likely: once the creature-art strategy and the arena are far enough along that a
   ranch scene has something to render into). Worth an explicit trigger condition rather than
   leaving it as "later," so it isn't quietly skipped the way several other "later" items in this
   project have been rediscovered as done or as still-missing.
