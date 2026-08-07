# The vertical slice — decisions taken 2026-08-04

**The user's instruction:** *"make the decisions, get a full workable game make it perfect for
what it is, i want to see artwork, i want to see arenas i want everything in some form"* — and
*"use the sprites as an idea but create your own."*

⚠️ **THIS FILE RECORDS CALLS MADE WITHOUT ASKING, ON EXPLICIT INSTRUCTION TO DECIDE.** Each one
is reversible and each one names its reasoning, so a later pass can overturn it on the merits
rather than having to reconstruct why it was made. Where a decision contradicts an existing doc,
that is called out.

---

## 1. Scope: a vertical slice, not a content dump

**Decided: twelve fully-realised creatures and five painted venues, not sixty-five and eleven.**

The instruction was "perfect for what it is" — which is an argument for *finish*, not *extent*.
Sixty-five creatures at this quality would be ~65 sequential generations through a
subscription-gated service (`docs/ART_PIPELINE.md`: 1–3 min each, "batch overnight"), and the
result would be a slice that is broad and unfinished rather than narrow and complete.

⚠️ **THE CLASS SYSTEM MAKES THE SMALL ROSTER CHEAP.** Class is emergent from a monster's two
highest CURRENT stats and is recomputed constantly — so twelve species still reach most of the
eighteen classes through training. A small roster costs variety of *silhouette*, not variety of
*play*. That is the right thing to trade.

**The twelve** (`monster-tamer/scripts/art.gd:ROSTER`) are picked for body and role spread:
Mammal (Kongrath/Warrior, Aegisox/Tank, Grivvel/Rogue) · Avian (Corvaan/Wizard, Larkessa/Bard,
Strixil/Sage) · Insectoid (Scarabrute/Tank, Mantevoke/Rogue) · Reptilian (Crocmaw/Warrior) ·
and the three prestige bodies (Pyraxon/Draconic, Tenebrae/Abyssal, Titanrex/Mythical) so the
ladder's top end has creatures that look like a reward.

**The five venues** are Wood · Bronze · Silver · Platinum · Tamers Apex — chosen to span the
ladder's whole RANGE rather than its first five rungs, so the climb visibly escalates.
Unpainted leagues fall back **downward** to the nearest painted one (`art.gd:backdrop_for`).
⚠️ Downward on purpose: an unpainted league borrowing a humbler venue reads as "not built yet",
where borrowing a grander one would misrepresent the player's actual progress.

## 2. Art: new, and in the Guild Colours direction — sport, not war

**Decided: regenerate rather than reuse, and take the pivot `ART_THEME.md` asked for.**

The user called the existing art a sketch. `docs/ART_THEME.md` had already identified the
problem independently and named it the document's *"single biggest pivot"*: the current
portraits dress competitors as **warlords and armoured beasts** (a pharaoh's cape, plate
armour), which contradicts the fiction — `BESTIARY.md`'s canon is that every competitor is a
sapient professional who *chose* to compete, and *"a Tamer is a partner, not an owner."*

So the new creature art is **athletes**: lightweight competition gear, wraps on the striking
limbs, and exactly one team sash. No armour, no weapons, no regalia.

⚠️ **THE SASH IS A MECHANISM, NOT A FLOURISH.** `ART_THEME.md`'s rule — *"Recolour the sash;
never the creature"* — is what lets a species stay recognisable in any team's colours. It makes
team identity a readable channel without costing species identity.

## 3. One image per creature, animated in code

**Decided: a single side-on full-body pose per creature, not a 6-frame sprite set.**

`docs/BATTLE_SPRITES.md` specifies 6 frames × 65 species = 390 images; 30 exist. Completing even
the twelve-species subset at 6 frames is 72 generations against 12.

The slice instead generates one pose and animates it in code — lunge, recoil, hit-flash, shake,
topple. ⚠️ **This is a real quality reduction and it is being taken deliberately**: motion
carries most of the readability, and the frames can be added later without changing anything
that consumes them. It is not presented as equivalent to the authored frame set.

## 4. Combat stays non-spatial in this slice

**Decided: do NOT build the spatial layer, and say so plainly rather than faking it.**

`CLAUDE.md` is explicit — *"Do not port what is being redesigned. Arenas, the spatial layer, the
camera and target selection are all explicitly out"* — and `docs/ARENA_BLUEPRINT.md`'s own
numbers are still conditional on unbuilt systems (Family A/B). Building a throwaway pathfinding
layer to make the demo *look* like the field engine is exactly the work that rule exists to
prevent, and it would have to be deleted.

So the arena view is **presentation over the verified event log**: real damage, real statuses,
real diminishing returns, real deaths — positions are staged for legibility, not simulated.
The 219-case contract math underneath is the genuine article and stays passing.

## 5. The ladder is the spine, and it ends

**Decided: Wood → Tamers Apex is implemented as a real, winnable progression.**

`CLAUDE.md`: *"Winning is completing Tamers Apex — the last league... A player who reaches and
clears Tamers Apex has finished the game."* The slice makes that reachable and detectable rather
than leaving the ladder open-ended, because a ship target that cannot be reached is not a ship
target. League drives **team size** (1v1 at Wood → 5v5 at Platinum+) and **stat cap** (100 →
1100), so the climb changes the game rather than only scaling it.

⚠️ **`game_data.gd`'s flat `STAT_CAP = 900` was a placeholder and is replaced by the league cap.**
Its own comment said so.

## 6. The Read is where the player plays

**Decided: build the pre-battle tactics screen as a first-class screen, not a settings panel.**

The player never intervenes. `CLAUDE.md`: *"Preparation is the skill; observation is the reward.
The fantasy is 'my read was right', never 'my reflexes were fast'."* If the pre-fight screen is
a shrug, the game has no skill expression at all — so scouting, orders and a counter-hint get a
full screen, and the tactics vocabulary is mined from the existing TS `GAMEPLANS`/`Tactics`
rather than invented (`CLAUDE.md` warns repeatedly that this codebase gets reinvented).

⚠️ **The tight/loose SPREAD trade-off from `ARENA_BLUEPRINT.md` §5 is surfaced to the player**
— tight keeps support auras live across the formation, loose gives them up. A decided trade-off
that a player cannot see is bookkeeping.

## 7. Art must be optional at runtime

**Decided: every art getter may return null and every screen degrades visibly.**

Generation is slow and serialized; the systems work cannot block on it. `art.gd` returns null
for a missing asset and screens draw a deliberate fallback. This also means a fresh clone with
no generated art still runs — which is the honest state of a project whose art is subscription-
gated and has been down twice (`ART_PIPELINE.md` records both outages).

---

## What was NOT decided here, and stays open

- **The balance baseline remains suspended** (`CLAUDE.md`). Nothing in this slice was tuned, and
  no `sweep40` figure was quoted. Training and rival-strength numbers are placeholders and are
  commented as such in code.
- **The 30-class expansion and assignable classes** stay proposals; the slice ships the live
  18-class emergent system.
- **The aura innate fields** stay design-decided and unbuilt (`docs/INNATES_ON_FIELD.md`) — the
  engine wiring they depend on does not exist yet.
- **Breeding, the market, licensing, events and the full weekly tick** are not in the slice.
  `docs/META_GAME_DISPOSITION.md` holds their port plan.
