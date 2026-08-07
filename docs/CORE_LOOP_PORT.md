# The core loop — what the Godot build must become

**2026-08-04. Binding.** Written after the user reported the Godot new-game screen is wrong:

> *"the initial screen once ive hit new game is already wrong. port what we have in tamergame and
> improve upon it... at the moment it does not make sense compared to what we have."*

They are right, and the Godot stable screen's own footer was already confessing it: *"Breeding,
the Lab, feeding and the full weekly tick still live in the TypeScript build, not here yet."*

---

## 1. ⚠️ THE NEW-GAME STATE IS WRONG IN EVERY PARTICULAR

`src/town.ts:582 newGame()` is the authority. Read it before arguing with this table.

| | React (correct) | Godot (as shipped) |
|---|---|---|
| **stable** | `[]` — **you own NO monsters** | six pre-made monsters |
| **week** | `0` | `1` |
| **area** | `'town'` | the stable |
| **gold** | `500` (`START_GOLD`) | 500 ✓ |
| **barn capacity** | `2` (`START_BARN`) | unbounded |
| **tutorial** | `tutorialStep: 'buy'` | none |

⚠️ **The single biggest error: the Godot build GIVES you a team.** In the real game acquiring
your first monster is the first decision you ever make, it costs gold you cannot spare, and the
barn holds **two**. Handing the player six finished monsters deletes the opening of the game and
is why the screen "doesn't make sense" — there is nothing left to decide.

⚠️ **Stats must not read `/100`.** The ceiling is `game.ts:statCapFor(c)` = **league cap ×
bloodline potential**. Showing `69 / 100` invents a scale the game does not have and hides the
single most important progression fact: *you are at the Wood ceiling, win promotion to go higher*.

---

## 2. The shape of the loop

Two **areas** (`town.ts:20  Area = 'town' | 'ranch'`) and three ranch **phases**
(`App.tsx:1841  'feeding' | 'stable' | 'battle'`).

```
TOWN ──────────────────────────────────────────────────────────┐
  market (buy monsters)   shop (food, licences, barn, manuals)  │
  lab / breeding          tournaments sign-up                   │
        │ go to ranch                                           │
        v                                                       │
RANCH                                                           │
  phase 'stable'   plan each monster's week — drill / rest /     │
                   excursion — and pick its food. NOTHING is     │
                   spent yet. Then: Advance Week.                │
        │                                                       │
        v                                                       │
  phase 'feeding'  sequential, one monster at a time (fav and    │
                   hated foods differ per monster, so this       │
                   cannot be one bulk button). Weekly event      │
                   modal resolves here.                          │
        │                                                       │
        v                                                       │
  phase 'battle'   tournaments — round robin, placement rewards ─┘
```

---

## 3. The weekly tick — `town.ts:1757 advanceWeek()`

**The ONE canonical path that advances the game.** Per monster, in this order:

1. **Feed** — paid food via `buyFood` (costs gold), or `forageFeed` as the free fallback
   (⚠️ costs stamina and happiness instead — hunger is never free, it is only ever *paid
   differently*)
2. **The planned activity** via `applyWeek` — `train` (drill id) / `rest` / `excursion` /
   `compete`
3. **Age one week**, retired monsters age too
4. **Lab rental** charged **once per week**, not per monster (`rentalDue = 0` after the first)

Then globally: `week++`, food prices reroll, market restocks monthly, a weekly **event** rolls
(~45% of eligible weeks) and shows as a blocking choice on the next feeding screen.

**Constants** (`game.ts`): `MAX_STAMINA 100` · `WEEKS_PER_MONTH 4` · `WEEKS_PER_YEAR 48` ·
`START_GOLD 500` · `START_BARN 2`.

**Drills** (`src/drills.ts`, 30 of them): basic ~6 to one stat, −10 stamina · intensive ~12 to
one stat, −4 flat to a paired stat, −25 stamina · plus extreme and diverse rows, each locked
behind a Manual bought in the shop. The roll skews toward the top of its range as happiness
rises; the aptitude multiplier (major ×1.2 / minor ×1.1 / flaw ×0.8) applies **after** the roll.

### ⚠️ WHAT ACTUALLY BOUNDS TRAINING — I GOT THIS WRONG IN THE FIRST DRAFT

**This section originally said "stamina is the whole game" and that "you cannot train every
week". That is FALSE, and the measurement that refuted it is `scripts/_probe_week.gd`.**

`game.ts:149 staminaMalus()` is a **soft tax with a floor, not a gate**:

| stamina | multiplier |
|---|---|
| > 70 | 1.0 — no penalty |
| > 50 | 0.95 |
| > 30 | 0.9 |
| **≤ 30** | **0.5 — and that is the floor** |

⚠️ **At zero stamina you still train, at half rate, forever.** The probe measured exactly that
in the Godot port: 20 consecutive intensive drills, stamina floored at 0 by week 4, gains
falling from ~19/week to ~9/week and then continuing indefinitely. **The port is FAITHFUL here** —
it reproduces React's behaviour precisely. Anyone "fixing" this to hard-block training at 0
stamina would be introducing a divergence, not correcting one.

**The real wall is `game.ts:361 statCapFor()` = league cap × bloodline potential.** That is what
stops a monster improving, and it is why the `/100` stat bars are not a cosmetic bug: they hide
the only genuine ceiling in the game behind an invented scale.

**So the three things that actually make training a decision are:**
1. **The week clock** — one action per monster per week. The Godot build applied stats on click
   with no clock at all, so a player could click forever *within a single week*. **That, not
   stamina, is what the user meant by "I can keep on training".**
2. **The league cap** — visible as a wall, with promotion as the way through it.
3. **Stamina** — a real cost that makes rest weeks worth choosing, but never a hard stop.

⚠️ **The lesson worth keeping: a plausible mechanism was asserted here as fact and five streams
were briefed on it before anyone measured it.** The probe took ten minutes and overturned it.

### ⚠️ RNG DISCIPLINE — NON-NEGOTIABLE

`previewWeekEffects` must mirror `applyWeek` **byte-exactly**. The preview is not an estimate —
training rolls are deterministic per (monster, week) off the same seeded RNG, so the number on
the button is the number you get. If they diverge, the preview becomes a lie and the player
cannot plan, which breaks the game's central promise that *preparation is the skill*.

---

## 4. What "improve upon it" means

The user asked for better, not merely equal. Improvements that serve the loop:

- **Make the cost visible before it is paid.** The plan-then-advance structure already exists to
  allow this; show the week's total gold and stamina spend on the Advance Week button.
- **Say why a drill is good for THIS monster.** Aptitude (major/minor/flaw) is already computed
  and is invisible in the UI today.
- **Show the league cap as a wall, not a number.** A bar that stops short with "Wood ceiling —
  win promotion" teaches the progression in one glance.
- **Never leave a dead-end screen.** Every screen states what it is waiting for.

⚠️ **Do not add systems that are not in the React build.** The ask is to port and polish what
exists, not to design new mechanics. Breeding, the lab and events are ports, not inventions.

---

## 5. Acceptance — the build is done when all of these are true

- [ ] New game lands in the **TOWN**, week 0, 500 gold, **zero monsters**, tutorial says buy one
- [ ] The barn holds **2**; buying a third is refused with the reason given
- [ ] Training costs stamina; at ≤30 stamina gains halve (0.5 floor) — provable over 20 weeks.
      ⚠️ NOT a hard stop: matching React means training continues at half rate forever
- [ ] One action per monster per WEEK — the clock, not stamina, is what bounds clicking
- [ ] Feeding costs gold, and forage is free but costs stamina and happiness
- [ ] Advance Week is the only thing that moves the clock
- [ ] Stat bars read against the **league cap**, never `/100`
- [ ] `preview` and `apply` agree exactly — assert it in a probe, do not eyeball it
- [ ] `./run_contract.sh` still PASSes 219 cases
