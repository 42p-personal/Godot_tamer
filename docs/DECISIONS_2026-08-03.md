# Decisions log — 2026-08-03 studio review

Answers given by the user against the consolidated decision list. **This is the record of what
was DECIDED**; the reasoning lives in the linked design docs.

⚠️ **NOTHING BELOW IS BUILT.** The balance baseline is suspended and the Godot rebuild is
where these land.

---

## Settled

| # | decision |
|---|---|
| 1 | **`tameness` is REMOVED.** **Innates and happiness are KEPT** and must be wired into `tamerengine`, which currently references neither. Happiness may be reworked into a more interesting scale; the food dynamic can be reworked with it. |
| 3 | **Arena scale: the largest is ~4x our current largest.** ⚠️ No firmer number exists without authoring an arena or agreeing a space on a blueprint. **That blueprint is now a blocking artefact** — the leash, deploy depth, reach and every spatial constant are sized from it. |
| 7 | **Lengthen the ranged root; make the basic attack commit.** Numbers TBD. |
| 11 | **Sprites get redesigned** against the new art style. |
| 14 | **The crowd becomes FANS.** Fans give bonuses; merchandise is a revenue line; it extends Guild Colours into the meta-game. Replaces the punitive crowd-meter framing. |
| 15 | **The Read: YES**, enhanced by scouting. **The Chalkboard: NO.** **The Broadcast: YES** — and it may be *how you watch the game* rather than a mode. **Training programme: keep a repeat-training mechanism** rather than the full programme rework. |
| 16 | **Props carry semantic tags.** Low walls = soft cover. |
| 17 | **Rival class comes from rolled stats**, reworkable later. |
| 19 | **Re-weight `tools/comps.ts` to 5v5.** |
| 21 | **Re-baseline when the arena is at the right size.** |
| 22 | **Playtest once arenas work** and the game is in a better state. |
| 10a | **Guild Colours is APPROVED** as the visual identity. |

## Settled, with a consequence that needs building

**10b — THE META-GAME BECOMES A WORLD, NOT MENUS.** The user: *"I am looking to remake the game
into a world where you would move a character rather than interacting with menus."*

⚠️ **THIS IS THE LARGEST SINGLE SCOPE CHANGE IN THE SESSION** and it is not an art decision —
it replaces `TownView` and `RanchView` (the bulk of `App.tsx`'s 4,472 lines) with a traversable
space. See `docs/WORLD_DESIGN.md` for the treatment and the risk.

## Answered by finding it already built

| # | question | answer |
|---|---|---|
| 5 | how do we stop archers kiting if speed is DEX-derived? | ⚠️ **SPEED IS THE WRONG LEVER AND IT HAS ALREADY BEEN MEASURED AS SUCH.** `BACKPEDAL_MULT` already costs a retreating unit 40% of its speed, and its comment records the measurement: without it *"a chase NEVER resolves - a pursuit equilibrium that left units out of range 76% of the fight regardless of field size or speed (both measured, both invariant)"*. The fix was an ASYMMETRY between advancing and retreating, not a speed number. |

## Settled in the second pass

| # | decision |
|---|---|
| 2 | **LAYERED.** Doctrine is the TEAM's plan; `cohesion`x`predation` is the UNIT's fidelity to it. A low-cohesion monster under a Control plan keeps freelancing off-plan — a feature, and it makes breeding for personality mechanically meaningful. **Do not build a second archetype system beside the existing grid.** |
| 4 | **The formation axis is renamed `SPREAD`.** ⚠️ And since the leash is sized from the arena, **`SPREAD` and the leash are ONE KNOB.** Do not build both. |
| 6 | **Minimum range accepted.** Guards: the class basic never has one, the value is modest, and it is authored per line. ⚠️ **AND `range` IS ALREADY PER-ABILITY** — all 141 moves author one and `validate.ts` fails a move without it. So a per-ability minimum is available for free if a line-wide value proves too blunt. |
| 9 | **Species aptitude = RATE. Class cap = CEILING.** Separate axes, no collision. ⚠️ **And with class caps in, DROP the earlier proposal to also make aptitude a ceiling modifier** (`TACTICS_BRAINSTORM.md` §5.2 option D). One ceiling system is enough; two would over-constrain and be unreadable. |
| 12 | **Doctrines MAY overlap — one PRIMARY plus one SECONDARY per class**, mirroring the primary/secondary stat pair that already defines a class. ⚠️ The secondary is a LEAN, never a second full plan. |
| 18 | **CON control-resist gets the soft-knee curve** so it never flattens. |
| 20 | **`pool.ts` gains a per-line progression bound and a Tukey IQR fence**, both derived from the tool's own distribution rather than hand-picked absolutes. |

### ⚠️ Why doctrines had to be allowed to overlap

The Systems Designer flagged **6 of 18 classes as ambiguous** (Ranger, Wizard, Spellsword,
Stalker, Bard, Swashbuckler) when forced into a single doctrine. **A third of the roster not
fitting the model is evidence against the model, not against those classes.**

Primary + secondary resolves most of it and costs nothing structurally, because **it is the same
shape the class system already uses** — a class IS a primary/secondary stat pair, so a
primary/secondary doctrine reads identically and needs no new mental model.

⚠️ **THE GUARD: the secondary must be a TIEBREAK WEIGHT, not a second behaviour.** If both
fire with equal force you get contradictory intent, which is the exact failure the
no-intervention rule cannot tolerate. Two rules per class, not three.

**With the support split folded in, the doctrine set becomes seven:**
Control · Sweep · Strike · Anchor · Empower · Protect · Restore — where the last three are the
game's existing, already-designed support division (**CHA empowers · CON protects · WIS
restores**) rather than new taxonomy.

## 10 — THE WORLD, deferred with a cheaper path identified

The user: *"We can look back at this idea later. Maybe the town and other areas displays the
character, or maybe we can have menus over the 3D world?"*

⚠️ **DEFERRED — and the middle path is probably the right answer permanently, not just for
now.**

The value being chased is **PRESENCE** — the ranch feeling like a real place, seeing your
monsters in it — not **TRAVERSAL**. Traversal is the expensive half *and* the half that rots:
walking to the feeding trough is charming once and tedious across a ~400-week career, in a loop
already flagged as a chore risk.

**So: keep the presence, skip the walking.** A 3D ranch you look into, with your monsters
visibly present and doing what you assigned them, and interface over the top. Most of the
feeling, a fraction of the cost, and none of the tedium risk.

⚠️ **The test for any later version: does moving the character REPLACE an interaction, or sit
in front of one?** If walking is a corridor to the same menu, it is strictly worse than the
menu.

## Third pass

| # | decision |
|---|---|
| Arena | **THE PLAYING SPACE GETS SUBSTANTIALLY BIGGER.** ⚠️ **This OVERRIDES the blueprint's first call**, which put the 4x on the venue and shrank the ground to 62x42 — smaller than the shipped board. The user: *"the arena's playing space should be bigger... all of them at the moment are too small for the game we are building. Forget about the current size, but make a far larger arena."* |
| Auras | **PROXIMITY-SIZED**, not team-wide. Closes the 9-field question from the innate audit. |

### ⚠️ Why the blueprint was wrong, and why its argument still matters

It reasoned that `LEASH_RADIUS = 12` caps a fight to a 24-unit diameter regardless of board
size, so today's 82x55 board is already mostly unused — therefore a bigger ground buys nothing.

**The observation is correct and the conclusion was backwards. The leash is the BUG, not the
evidence.** SPREAD replaces it and scales with the ground, so the fight genuinely uses the
space.

⚠️ **BUT THE RISK IT IDENTIFIED IS REAL AND NOW HAS TO BE ANSWERED BY DESIGN.** A ground large
enough to fight in is also large enough to get lost in. Four things already exist or are decided
that make a big ground safe, and the blueprint must lean on all of them rather than on a small
board:

1. **SPREAD** scales with the ground — the team's own cohesion is the leash.
2. **Minimum range** — arriving switches off a ranged kit, so closing is worth doing.
3. **`BACKPEDAL_MULT`** — already shipped: giving ground costs 40% speed, and its own comment
   records that without it *"a chase NEVER resolves... regardless of field size or speed"*.
4. **Cover as a destination** — props are somewhere to go, not scenery to cross.

**The ground can be large precisely BECAUSE those exist.** Without them it could not be.

### ⚠️ Auras being proximity-sized has a consequence worth stating

It makes **SPREAD a genuine trade rather than a preference**. A tight team gets its auras and
eats the AoE; a loose team spreads the AoE and gives the auras up. That is exactly the kind of
two-sided choice the formation system needed, and it arrives free from a decision made for a
different reason.

⚠️ **It also unblocks the 9 innate fields** the audit held back — all five team-auras and four
enemy-debuff-auras. They get a radius rather than being global, which is what stops them
reintroducing the position-blindness bug the field engine already fixed once.

## Still open — carried forward

| # | question | why it is still open |
|---|---|---|
| 8 | assign class **gated by stats** rather than freely? | user's counter-proposal, and it is better than free assignment |
| 13 | abilities matched better to classes | follows 12 |
