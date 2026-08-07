# The chase problem — kiting, closing, and the camera

**2026-08-03.** How fights stay *fights* on an arena much larger than the current board, and
larger than the screen.

> *"Running to cover isn't the only option, kiting works too. Maybe we could get around this
> with melee abilities or make melee units naturally faster? ... It would be more entertaining
> to have the arena map be larger than the size of the screen with the stadium ornaments and
> crowd in stands to either side."*

⚠️ **CORRECTING MYSELF FIRST.** `SPATIAL_MODEL.md` §11.2 said cover *replaces* kiting. That was
too absolute. **Kiting is a legitimate tactic and should stay one.** The problem is not that
kiting exists — it is that kiting currently has **no cost and no end**.

---

## 0. The insight: the camera and the chase are the same problem

⚠️ **AN ARENA LARGER THAN THE SCREEN MEANS THE FIGHT MUST STAY FRAMEABLE.**

If the camera follows the action across a big stadium, a diffuse fight is not merely unreadable
— it is **unfilmable**. The camera has to either pull back until everyone is an ant, or pick a
subset and hide the rest.

**So every mechanic that keeps the fight coherent pays twice**: it fixes the chase problem *and*
it makes the shot possible. That is a strong reason to prefer solutions that hold the fight
together over solutions that merely end it.

**And it gives the arena its real shape:** a **big beautiful venue** with stands, ornament and
crowd — containing a **bounded fighting ground**. The stadium is the size of the spectacle; the
engagement is the size of the shot. Those are two different numbers and they should be.

---

## 1. What exists today

| lever | state |
|---|---|
| `KITE_MAX` 1.2s / `KITE_REFILL` 0.5 | ✅ built — bounds each kiting *episode*, not the total |
| Gap closers | ✅ built — `dash` to target (range 7–9) on STR; `blink` behind target (10–14) on DEX/INT |
| Casting roots the caster | ✅ built — *"the window a diver punishes"* |
| `ESCAPE_LOCKOUT` shared across escapes | ✅ built — commitment is real |
| `PURSUIT_PATIENCE` / `PURSUIT_PROGRESS` | ✅ built — ⚠️ **and it is the thing that produces milling at size** |
| **Per-unit movement speed** | ✅ **EXISTS, AND IT IS DEX-DERIVED** — see the correction below |
| **A leash** | ✅ **EXISTS** — `LEASH_RADIUS = 12`, see the correction below |

## ⚠️ 1.1 TWO CORRECTIONS — I WAS WRONG TWICE (2026-08-03)

Caught by the Game Designer during the ability-balance review, verified against source. Both
change the advice materially.

### Correction 1 — per-unit speed EXISTS, and it is DEX-derived

`src/tamerengine/engine.ts:198`:

```ts
// DEX drives how fast it crosses the field - the stat finally has a
// spatial meaning beyond initiative.
speed: 2.4 + (m.stats.DEX / 1000) * 3.6,
```

| DEX | speed |
|---|---|
| 0 | 2.40 |
| 300 | 3.48 |
| 500 | 4.20 |
| 1000 | 6.00 |

**A max-DEX unit moves 2.5x as fast as a zero-DEX one.** So "make melee units naturally faster"
is a **rebalance of an existing formula**, not new machinery. Cheaper than I said.

⚠️ **AND THE "DEX IS BACKWARDS" OBJECTION IS NOT HYPOTHETICAL — IT IS ALREADY SHIPPED.**
I raised deriving speed from DEX as a trap to avoid. It is the live implementation. DEX is the
Ranger, Rogue and Volley stat, so **the units that want distance are already the fastest at
keeping it.**

⚠️ **THAT IS A MECHANICAL ROOT CAUSE OF THE KITING COMPLAINT AND NOBODY HAD CONNECTED IT.**
Archers do not merely have reach — they out-run the things sent to close on them. Every other
fix in this document is downstream of that, and it may be the single highest-value change
available: one formula, and it is the formula that decides who catches whom.

### Correction 2 — a leash EXISTS, and it is hardcoded

`src/tamerengine/types.ts:73` `LEASH_RADIUS = 12`, applied in `decide.ts:521-529` to **every**
goal the decision function returns, retreat and kite included:

> *"no unit may aim to stand more than LEASH_RADIUS from the fight's centre of mass - the hard
> stop on wandering off across the map"*

So section 11.3's "we need a leash" was proposing something already built.

### ⚠️ AND THE CONSEQUENCE IS SERIOUS FOR THE WHOLE LARGE-ARENA DIRECTION

The leash is **12 world units from the battle centroid — a 24-unit fight diameter — and it does
not scale with the board.** `LEASH_RADIUS` is a bare constant; it reads neither `FIELD_W` nor
`FIELD_H`.

| board | width | fight diameter | board actually used |
|---|---|---|---|
| today | 40 | 24 | ~60% |
| 2x | 80 | 24 | ~30% |
| 4x | 160 | 24 | **~15%** |

⚠️ **SO ENLARGING THE ARENA WOULD CHANGE NOTHING ABOUT HOW THE FIGHT SPREADS.** The stated
goal — *"if the arenas are far larger the monsters have more freedom to move around"* — **cannot
happen while this constant is fixed.** The fight would stay a 24-unit huddle in the middle of a
mostly empty stadium.

⚠️ **AND IT INVERTS THE PRIORITY OF THIS ENTIRE DOCUMENT.** I have been treating the diffuse
fight as the risk of large arenas. The leash means the real risk is the opposite: **the arena
grows and the fight does not.** Cohesion, stations and formation spread all have to be
expressed *through* this constant, or they are decorative.

✅ **DECIDED 2026-08-03: the leash gets reworked and is sized from the arena.** The user:
*"Leash radius can be reworked, it will depend upon how big our arenas are."*

⚠️ **WHICH MAKES IT THE SAME KNOB AS THE SPREAD AXIS, and they should be ONE THING.** A leash
sized from the arena and a "how far apart do we fight" order are the same number arrived at from
two directions. Building both would be two systems fighting over one unit's goal position.

**What to do with it:** make it derived rather than absolute — a fraction of board size, or of
team size, or driven by the cohesion axis (`TACTICS_BRAINSTORM.md` section 10) so that "loose"
genuinely means loose. ⚠️ **It should almost certainly become the cohesion axis itself**, which
is a much better answer than adding a second wandering constraint beside it.

⚠️ **GENERAL LESSON, AND IT IS THE PROJECT'S OWN RULE ARRIVING AGAIN:** I asserted twice that
something did not exist without grepping for it. `CLAUDE.md` says an inherited value is evidence
of what happened, never evidence anyone decided it - **but the first step is finding out whether
it is there at all.** Check before claiming absence.

---

## 2. The suggestions

Grouped by what they actually do. Each with the honest cost.

### FAMILY A — let melee close

**A1. Melee moves faster** *(your suggestion)*

⚠️ **The naive version breaks ranged.** If melee is simply faster, kiting is a delay rather than
a tactic, and a ranged unit becomes a melee unit that is worse until it dies.

**The safe version: a CLOSING bonus, not a movement bonus.** A unit moves faster *while
approaching a hostile target it has committed to*, and at normal speed otherwise. Kiting then
costs the kiter ground without letting melee zip around the board.

⚠️ **CORRECTED — SPEED ALREADY COMES FROM DEX (see section 1.1).** The question below is not
"where should speed come from" but "should it keep coming from DEX", and the answer is probably
not. Candidates:
- **DEX** — backwards. DEX is the *ranged and rogue* stat; deriving speed from it makes archers
  the fastest thing on the field.
- **Body type** — plausible, but it fights "any species can train into any class".
- **⭐ The class basic's CHANNEL** — a monster whose free attack is `melee` gets the melee speed
  band. **Consistent with how reach is already decided** (`CLASS_BASIC` owns channel, reach and
  scaling stat), needs no new data, and it moves with the monster as its class changes.

**A2. Gap closers that reward commitment**

They exist but sit on cooldowns, so melee gets *one* engage and then waits — the pattern that
makes melee feel bad in every game that has it.

- **Refund the cooldown on a landed hit.** Connect and you may dive again; whiff and you wait.
  Turns a gap closer from a gamble into a rhythm.
- **A free micro-lunge in the class basic package** for melee channels — a short, low-cooldown
  step, not an ability. Melee's baseline stickiness rather than a resource it spends.

**A3. Pursuit momentum** — speed ramps the longer you chase the same target.
⚠️ **Not recommended.** Rubber-banding is hard to read and feels arbitrary, which is expensive
in a game where watching *is* the game.

---

### FAMILY B — make kiting cost something

**B1. ⭐ Minimum range on ranged abilities**

⚠️ **My strongest single recommendation, and it fits this game unusually well.**

A bow cannot be fired at one unit's distance. A siege spell needs room. So:

- **Melee's job becomes to STICK, not to kill quickly.** Arriving is itself the win, because
  arrival switches off the target's kit.
- **Slow closing stops being fatal.** Melee does not need a speed buff if *being there* is
  sufficient.
- **Kiting becomes PURPOSEFUL rather than evasive** — the archer is not fleeing, it is trying to
  re-establish its firing band. That is a far better story to watch.
- ⚠️ **The authoring is nearly free** because `range` is already a per-ability axis seeded **per
  LINE**. Give `Volley` a minimum band and `Assassin` none. One number per line, not per move.

**Cost:** a ranged unit pinned in melee needs *something* to do — the class basic, a shove, a
disengage. Otherwise being stuck is a death sentence rather than a disadvantage.

**B2. Enforce "you cannot attack while kiting"**

The `KITE_MAX` comment states this as the intent. ⚠️ **Worth verifying it is actually enforced**,
because if a unit can retreat *and* shoot, kiting is strictly dominant and no other fix will
hold.

If retreating means not attacking, kiting is **pure defence** — it buys time and never wins.
A stalling fight cannot happen if the staller is not accumulating advantage. Near-free.

**B3. A kite budget that does not fully refill**

Currently refills at 0.5×, so total kiting is unbounded. Make refill partial — the tenth
backpedal is shorter than the first. Makes kiting a **finite resource per fight** rather than a
renewable one.

---

### FAMILY C — let the board and the crowd end it

**C1. ⭐ A bounded engagement zone inside a much larger stadium**

The arena is big and cinematic; the *fight* happens in a defined ground within it. Leaving it is
either impossible (a boundary) or penalised (the crowd, C3).

⚠️ **This is what reconciles "arena larger than the screen" with "the fight must be readable."**
The stands, ornament and crowd give the venue its scale; the fighting ground stays framed.

**C2. Leash to station**

A unit does not abandon its station beyond a radius. The station system already provides the
anchor. Softer than a hard boundary and it composes with formation and cohesion.

**C3. ⭐ Crowd momentum — the idea your stadium description unlocks**

You described crowds in stands. **Make them a mechanic.**

A **crowd meter** that rises with action — hits, kills, big plays — and **falls during
passivity**. When it bottoms out, the arena escalates: chip damage, a shrinking ground, a
closing boundary, the lights coming up.

- ⚠️ **It punishes stalling without punishing kiting.** A kiting archer that is still landing
  shots keeps the crowd; two units milling do not. That is exactly the distinction we want and
  no positional rule captures it.
- **It is thematic** — this is a tournament, in a stadium, in front of a crowd. The crowd caring
  is the most natural mechanic this setting offers.
- **It is legible** — a visible meter is a thing the player watches and understands.
- **It arrives far earlier than `SUDDEN_DEATH_AT` (255s)**, which is a backstop rather than a
  design.
- It reuses the crowd system that is already planned to fill by team fame.

⚠️ **Cost:** a new visible system with its own balance surface, and it must never punish a
legitimately slow, grindy, tactical fight — only an *empty* one. The trigger must be **action**,
not damage, or tanks and control comps get taxed for playing correctly.

---

## 3. Recommendation

**Not one fix — a small stack, cheapest first.** Each is independently useful, so they can land
one at a time and be measured (once there is a baseline again).

| # | change | cost | why here |
|---|---|---|---|
| 1 | **Verify/enforce "no attacking while kiting"** (B2) | ~free | if this leaks, nothing else holds |
| 2 | **Minimum range per LINE** (B1) | low | one number per line; makes *arriving* the win |
| 3 | **Bounded engagement zone** (C1) | low–med | fixes the chase AND the camera |
| 4 | **Melee closing-speed bonus off the class basic channel** (A1) | med | your idea, in the version that does not break ranged |
| 5 | **Gap-closer refund on a landed hit** (A2) | low | turns diving into a rhythm |
| 6 | **Crowd momentum meter** (C3) | med–high | the flavour win, and the only anti-stall that reads |
| 7 | Partial kite refill (B3) | low | fine-tuning once 1–5 are in |

⚠️ **AND THE MEASUREMENT STILL COMES FIRST.** Before any of it: **scale the current field 2x and
4x and run `sweep40`.** If fights get longer, more diffuse and less resolved, that quantifies
the problem and gives every item above a target. If they do not, this whole document is solving
something smaller than it looks.

---

## 4. What this implies for the arena

**Two numbers, not one.**

| | what it is | sized by |
|---|---|---|
| **The venue** | stands, ornament, crowd, architecture | spectacle — as large as looks good |
| **The ground** | where the fight actually happens | ⚠️ **the shot, and the fight's coherence** |

⚠️ **CORRECTED 2026-08-03.** I wrote that the current board "confused" the two. That is wrong:
**the arena was authored purely as ART.** Nobody was treating 40x22 as a balance parameter.

⚠️ **AND THAT IS WORSE, NOT BETTER — which is the actual argument for keeping the two numbers
apart.** `tools/sweep40.ts` reads `FIELD_W` and `FIELD_H` directly and places its obstacles
relative to them. So an art decision silently became a balance input that nobody was reviewing
as one. The board did not conflate the numbers; **it only ever had one number, and the sim
quietly took it.**

⚠️ **GENERAL RULE FOR THIS REPO, FROM THE USER: this was the old company, and some things may
simply be wrong.** Treat inherited numbers as evidence of what happened, never as evidence that
it was intended. When a value looks load-bearing, check whether anyone ever decided it.

The camera frames the ground and lets the venue fall off the edges — which is exactly the
"larger than the screen" feel, achieved *without* letting the fight sprawl.

---

## 6. Speed — where should it come from?

*"We could work speed into an additional stat or something else. We are open to all ideas."*

Five options. ⚠️ **The cost is not the code — it is what each one does to the systems that
already exist.**

### 6a. A seventh STAT (SPD)

⚠️ **The most expensive option by a wide margin, and the blast radius is not obvious.** Six
stats currently give 30 ordered pairs, which is where the 18 classes plus Generalist come from.
A seventh gives **42 pairs** — so the class matrix, every species training profile, the drill
set, aptitudes, the UI, breeding inheritance and `classForStats` all move at once.

- ✅ maximum expressiveness; speed becomes something you TRAIN and BREED for, which fits the
  meta-game vision directly
- ❌ it is the single largest data change available, and it lands on the one system
  (`classForStats`) that everything else keys off

### 6b. Derived from an existing stat

- **DEX** — the obvious pick and ⚠️ **backwards**: DEX is the archer and rogue stat, so
  deriving speed from it makes the units that want distance the best at keeping it.
- **CON, inversely** — mass slows you. Thematic, but it taxes tanks twice for one investment.
- ✅ free, no new data · ❌ every candidate has a design objection

### 6c. From BODY TYPE

The 13 bodies each carry a speed band. Avian quick, Aquatic laboured on land, Draconic heavy.

- ✅ **body type is the one identity axis that does NOT fight emergent class** — body is fixed,
  class is trained, so a species trait here cannot lock a monster out of a role
- ✅ gives the 13 bodies real mechanical weight beyond `BODY_MINOR` and licence gating
- ✅ answers "do 65 species earn their keep?" — a Tempestine that genuinely *moves* differently
  is a species you can feel
- ❌ a fixed trait, so it cannot be trained or bred toward

### 6d. From the CLASS BASIC's channel

`CLASS_BASIC` already authors channel, reach and scaling stat per class. Add a speed band.

- ✅ no new data, and it **changes as the monster trains**, which makes emergent class matter
  more rather than less
- ✅ directly serves "melee should be able to close"
- ❌ eighteen bands to author and balance

### 6e. ⭐ CLASS band x BODY modifier

**Both, multiplied.** Class says what the ROLE moves like; body says what the SPECIES moves
like.

```
speed = CLASS_SPEED[class] * BODY_SPEED[body]
```

- ✅ **uses two tables that already exist**, no seventh stat, no new training surface
- ✅ a Warrior is a Warrior, but an *Avian* Warrior skirmishes and a *Draconic* Warrior lumbers
- ✅ the class half is trainable, the body half is breedable — ⚠️ **which is exactly the
  meta-game vision: advanced training knowledge PLUS breeding the right monster**
- ❌ two multiplied tables is a balance surface that needs a tripwire, or extremes multiply

**Recommendation: 6e.** Fall back to 6c alone if the class half proves hard to balance. ⚠️
**Only take 6a if speed should be TRAINABLE as a first-class pursuit** — that is a real design
position, but it should be chosen deliberately, not drifted into.

---

## 7. Class creativity — melee that wants a short fight

*"We could have some melee that want to kill fast such as berserkers or assassins. The classes
need to be creative."*

⚠️ **THERE IS NO BERSERKER CLASS TODAY.** The 18 are Tank, Warrior, Rogue, Ranger, Sage,
Wizard, Spellsword, Spellshield, Captain, Orator, Bard, Evoker, Skirmisher, Stalker,
Swashbuckler, Shaman, Mystic, Herald. They are named for their stat pair and differ mechanically
in exactly ONE way: their free attack.

⚠️ **THAT IS THE REAL PROBLEM.** Eighteen names, one axis of difference. A class is currently a
*label on a stat pair* rather than a way of fighting.

### The axis worth adding: TIME PREFERENCE

Some kits want a short fight; some want a long one. Nothing expresses this today, and it is the
natural home for the classes described:

| doctrine | wants | how it shows |
|---|---|---|
| **Berserker** | a short, violent fight | ramps as its OWN health falls — already expressible, `hpScale` exists as a move effect and could be a class trait |
| **Assassin** | one isolated kill, early | huge burst on an unsupported target, poor in a scrum — ⚠️ **needs the cohesion axis to have anything to isolate** |
| **Duellist** | a long single-target fight | ramps the longer it stays on one target |
| **Anchor** | a long fight, everyone alive | value accrues by surviving |
| **Artillery** | a long fight at distance | needs the fight not to reach it |

⚠️ **AND IT IS THE HONEST ANSWER TO THE CROWD-METER RISK.** A stall penalty that punishes slow
fights would tax Anchor and Artillery for playing correctly. If time preference is an explicit
axis, the anti-stall can be written to punish INACTION rather than DURATION — because we will
have said out loud which classes are supposed to want a long fight.

### What a class could carry beyond its free attack

Its speed band (§6), a preferred station, a time preference, and **one signature quirk**. ⚠️
**One, not a kit** — eighteen classes with three traits each is 54 interacting rules and nobody
will be able to predict a fight, which breaks the no-intervention bar.

---

## 8. "Archers cannot attack and move" — it already half-exists

*"There is more to explore here, such as archers not being able to use their basic
attack/abilities and move."*

⚠️ **A COMMITTED CAST ALREADY ROOTS THE CASTER.** `engine.ts`: *"A committed cast roots the
unit — this is the window a diver punishes."* So the rule you are describing is **already the
design**; it is just too short to matter.

| channel | cast time | rooted for |
|---|---|---|
| melee | 0.15s | almost nothing |
| **ranged** | **0.30s** | ⚠️ **the archer's whole commitment** |
| magic | 0.55s | a real window |
| voice | 0.45s | a real window |
| support | 0.40s | a real window |

⚠️ **THE ARCHER IS THE LEAST COMMITTED SHOOTER IN THE GAME AND ALSO THE ONE WITH REACH.** A
magic user roots for nearly twice as long to do a comparable job. That single asymmetry may be
most of the kiting problem, and it is **one number**.

### What to explore

1. **Lengthen the ranged root** — a draw-and-loose that commits. Cheapest possible change, and
   it is a tuning value rather than new machinery.
2. **A wind-up that MOVING cancels** — start to draw, step, lose the shot. More punishing and
   more readable than a flat root: the player sees the archer *fail* to shoot.
3. **Basic attacks root too.** Currently 0.15s, effectively free. ⚠️ If the free attack does
   not commit, an archer can always chip while retreating and every other fix leaks.
4. **A moving-shot penalty instead of a root** — softer, but ⚠️ it is the version that keeps
   kiting strictly dominant, because retreating still deals damage.

**Recommendation: 1 + 3 first** — both are single numbers, both are testable the moment there is
a baseline, and together they answer "can an archer fight while running away?" with *no*.
Explore 2 afterwards for feel.

---

## 5. Open questions

1. **Is the engagement boundary hard or soft?** A wall, or a penalty for leaving?
2. **What does a ranged unit do when pinned inside its minimum range?** It needs an answer or B1
   is a death sentence rather than a trade.
3. **Does the crowd meter also do something POSITIVE at high values?** A cheer bonus, a
   momentum swing — or is it purely an anti-stall?
4. **Does the closing-speed bonus apply to pursuit only, or to any approach?** Pursuit-only is
   tighter but needs a "committed to this target" state, which `RETARGET_EVERY` already implies.
5. **How big is the ground, really?** ⚠️ Answer with the 2x/4x sweep, not by eye.
