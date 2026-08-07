# Formation and orders — brainstorm

**2026-08-03.** Follows `TACTICS_DESIGN.md` (the measured diagnosis) and the user's answer to
its open question:

> **Formation is set per TEAM / per MATCH. There are also TEAM tactics and PER-MONSTER tactics.**

That answer settles the architecture. This document explores what to put in the three layers.

⚠️ **A BRAINSTORM, NOT A SPEC.** Options with trade-offs, and the disciplines disagreeing where
they should. Nothing here is decided.

---

## 0. The insight that reframes the whole thing

⚠️ **FORMATION IS NOT PRIMARILY AN AGENCY FIX. IT IS THE LEGIBILITY FIX.**

`OUTSTANDING.md` §3.2 asks whether a 5v5 fight with 4-slot loadouts is readable at all. Five
monsters, twenty abilities, two innates each, statuses, all resolving in real time. The honest
answer has been "probably not" — which is why `battleReport.ts` exists, and a post-hoc report is
a patch over an unreadable fight rather than a fix.

**A named shape with a named plan gives the player a frame to interpret the chaos through.**

> *"My wedge broke their line at four seconds, but their box held the casters and my flankers
> got picked off."*

That is a story. Five independent blobs picking their own targets is noise. The same fight,
told two ways, and only one of them teaches the player anything.

**So formation earns its place three times over:** it is the agency the player can *see*, the
frame that makes the fight *readable*, and the read that makes scouting *pay*.

---

## 1. The three layers

| layer | scope | when chosen | what belongs here |
|---|---|---|---|
| **Formation** | team | **per match**, after scouting | the shape, and each monster's station in it |
| **Team tactics** | team | per match | what the team does *together* — focus, engagement, gambits |
| **Monster tactics** | monster | standing (on the monster) | how this individual fights when left to itself |

**The organising principle:** if an order only means something when *everyone obeys it at once*,
it is a team order. If it describes an individual's temperament, it belongs on the monster.

### ⚠️ 1.1 The finding this immediately produces

**Target priority is currently PER-MONSTER, and that is why focus fire is weak.**

`tools/focus.ts` measured top share at **0.711** — a side's damage landing on its single
most-damaged enemy — and 1.78 distinct enemies hit per 5s. Focus was investigated as roadmap
item P6, measured as real but the *smaller* lever, and shelved.

⚠️ **The measurement was right and the diagnosis was incomplete. Focus fire is weak for an
ARCHITECTURAL reason: five monsters each pick their own target by their own rule, so they agree
only by coincidence.** No amount of tuning a per-monster priority produces team focus, because
concentration is not a property any individual can hold.

Moving target priority to the team layer is not a buff. It is making the order *expressible*.

---

## 2. Formation — the shapes

Each shape must trade something concrete, or the player picks the strongest and the system is a
menu with one item.

| shape | gives | costs |
|---|---|---|
| **Line** | even frontage, no exposed flank | nothing concentrated anywhere |
| **Wedge** | concentrates the break-in on one point | both flanks exposed |
| **Refused flank** | forces engagement on your strong wing | cedes ground on the weak one |
| **Split** | two threats, enemy must divide | can be defeated in detail |
| **Box** | back line fully screened | slow, poor at pressing an advantage |
| **Vanguard** | one body forward as anchor and bait | that body is alone for a while |
| **Dispersed** | AoE catches one, not five | nobody supports anybody |

### 2.1 The counter web

For a read to exist, shapes must beat *some* shapes and lose to others. A first cut:

```
Wedge      beats  Line        concentration breaks even frontage
Line       beats  Split       engages both halves, defeats in detail
Split      beats  Box         a turtle must choose, and either choice is wrong
Box        beats  Wedge       a screened back line blunts the point
Dispersed  beats  AoE comps   the shape answers a KIT, not another shape
Vanguard   beats  Dispersed   nobody is close enough to help the one it dives
```

⚠️ **THE INTERESTING ROW IS `Dispersed`, BECAUSE IT COUNTERS A KIT RATHER THAN A SHAPE.** That
is what stops the web being a flat rock-paper-scissors: some shapes answer what the enemy *is*,
others answer what they *do*. Scouting already reveals both.

### 2.2 Dynamic formation — the idea worth stealing

A formation with a **second state** it collapses to under losses.

> *Open in **Wedge**. At two down, collapse to **Box**.*

- It is a genuine plan rather than a pose, and it makes the mid-fight turn something the player
  **predicted** rather than merely watched.
- It gives the battle report a real beat to narrate.
- It is cheap: one extra shape and one trigger.

⚠️ **And it is the closest thing to intervention that does not break the no-intervention rule.**
The player is not reacting — they *pre-committed to a reaction*, which is exactly the fantasy of
"watch how my tactics unfold".

### 2.3 Stations — where each monster stands in the shape

The shape defines slots; the player assigns monsters to them. Named by intent, not coordinates:

**Anchor** (holds the point) · **Screen** (bodies between them and the back line) ·
**Skirmish** (works the flank) · **Support** (behind, in cover) · **Free** (goes where it wants)

⚠️ **INTENT, NOT COORDINATES, AND THIS IS THE LOAD-BEARING CHOICE.** A station survives an arena
of a different shape; a coordinate does not. Godot arenas will not be flat rectangles, so any
system that stores `{x, y}` is authored against a field that is being replaced.

---

## 3. Team tactics

Candidates for the team layer:

| order | options | why team-level |
|---|---|---|
| **Focus** | kill the *healer* / *weakest* / *nearest* / *most dangerous* / spread | concentration is only real if everyone agrees |
| **Engagement** | press · hold the line · receive | a team that half-charges is worse than either |
| **Opening gambit** | alpha strike · probe · turtle the first N seconds | coordinated by definition |
| **Protection** | who screens whom | relational; cannot live on one monster |
| **Regroup** | trigger for the dynamic formation | see §2.2 |

⚠️ **`targetPriority` MOVES UP HERE and this is a real behaviour change**, not a refactor. It
will move every balance baseline. Sim it alone, per the standing rule.

---

## 4. Monster tactics — what remains

With focus and protection promoted, the monster layer becomes coherent: **how this individual
behaves when the team plan does not say otherwise.**

Keep: `temperament` · `manaPolicy` · `preserve` · `openerIds` · `comboRole`
Add: **station affinity** (which slot it prefers, if the player has not assigned one)

### ⚠️ 4.1 Fix `comboRole` while touching this

Documented as meaningless on **~32% of monsters** — those whose kit holds neither an applier nor
a payoff. A live control that does nothing is this project's named signature failure mode, and
it is sitting in the panel the player uses most. Gate it on the kit, or drop it.

---

## 5. The meta-game hook

The vision says the meta-game is *"breeding the right monsters to have the correct tactics and
skills"*. That implies tactics are partly **inherited**, and there is a clean way to do it:

**Station APTITUDE, mirroring training aptitude.** A bloodline is naturally suited to Anchor or
to Skirmish — a bonus when played in that station, a penalty out of it. Breeding for a team
means breeding *for the shape you intend to run*.

- It connects the ranch to the battle exactly as the vision describes.
- It gives breeding a second axis beyond raw stats and signature moves.
- ⚠️ **It must be an APTITUDE, never a LOCK.** The same rule as classes: emergent, not
  species-destiny. A monster played out of station should be *worse*, never *forbidden* —
  otherwise it contradicts "any species can train into any class".

### ⚠️ 5.2 CLASS CAPS — the user's proposal, and what the budget actually says

> *"I would maybe like to add class caps instead so a monster can't be 1000 in all stats."*

**Measured, and the concern is real at long careers.** Best net drill is `Titan Regimen` at
**16 points/week**; six stats at the Tamers Apex cap of 1100 needs **6,600** points:

| career | net points | % of all-six | stats effectively capped |
|---|---|---|---|
| 4 years | ~3,686 | 56% | ~3.4 |
| 6 years | ~5,530 | 84% | ~5.0 |
| **8 years** | **~7,373** | **112%** | **~6.7** |

⚠️ **AT AN EIGHT-YEAR CAREER THE BUDGET EXCEEDS SIX CAPPED STATS.** The "generalist blob"
outcome is reachable, not theoretical.

⚠️ **BUT THE FIGURES ARE AN UPPER BOUND AND SHOULD NOT BE QUOTED AS THE REAL BUDGET.** They
assume the best drill every single week with a x1.2 aptitude on every stat — no rest weeks, no
excursions, unlimited stamina (basic costs 10, intensive 25), and a major aptitude on all six,
which is impossible since a species authors ONE major. The true budget is materially lower.
**The direction is right; the number needs a proper sim before anyone tunes against it.**

### The options, and one that fixes three problems at once

**A. Per-class stat caps.** ⚠️ **CIRCULAR — flag before anyone builds it.** Class is EMERGENT
from the two highest stats (`classForStats`, recomputed every time). A cap keyed to class means
training STR makes you a Warrior which raises your STR cap which keeps you a Warrior. It is
self-reinforcing rather than constraining, and it quietly converts "any species can train into
any class" into "your first two hundred points choose your class forever".

**B. A total stat BUDGET.** One pool across all six; raising one means the others cannot also
max. Clean, no circularity, and it makes *distribution* the decision. ⚠️ Needs a UI that shows
the budget or it is an invisible wall.

**C. Species or body-type caps.** Per-stat ceilings from the species. ⚠️ Directly weakens the
emergent-class rule, which is a load-bearing design principle here.

**D. ⭐ APTITUDE AS A CEILING MODIFIER, not just a rate one.** The species profile already
authors major / minor / flaw. Today those scale the training ROLL. Make them scale the CAP too:

```
major   cap x 1.00      minor  cap x 0.95
neutral cap x 0.85      flaw   cap x 0.70
```

**This fixes three separate problems with one change:**
1. **A monster cannot max everything** — the flaw stat tops out ~30% lower. Your concern.
2. **Aptitude stops evaporating at cap** (§5.1) — it becomes a permanent identity, not just a
   speed bonus that stops mattering the moment you arrive.
3. **Species identity becomes FELT** — `OUTSTANDING.md` §3.4 asks whether 65 species earn their
   keep. A species whose flaw genuinely caps lower is a species you can feel.

⚠️ **And it composes with station aptitude rather than competing with it.** Same machinery, same
mental model for the player: *what this bloodline is good at*. **D is my recommendation**, with
B as the fallback if per-stat ceilings feel too restrictive.

⚠️ **DO NOT BUILD IT YET.** It re-shapes every monster in the game and the baseline is
suspended. It belongs in the deliberate re-baseline, not before it.

### ⚠️ 5.1 The caps are the argument for it — CONFIRMED 2026-08-03

The user's reason: *"station aptitude would make sense, especially with the caps we are using."*
That is right, and the mechanism is worth writing down.

**Training aptitude is a RATE mechanic, not a CEILING mechanic.** `game.ts` clamps every gain
with `Math.min(cap, ...)`, so `statTrainingBonus` (major x1.2 / minor x1.1 / flaw x0.8) changes
how FAST a monster arrives at its cap and never where it stops. Two monsters with opposite
aptitudes, both trained to cap in the same stat, are identical in that stat.

Rough reach for a focused single-stat build:

| career | flaw x0.8 | none | major x1.2 |
|---|---|---|---|
| 4 years | ~922 | ~1152 | ~1382 |
| 6 years | ~1382 | ~1728 | ~2074 |

Against caps of Platinum 900 → Tamers Apex 1100: **even the worst aptitude on the shortest
career caps a focused stat.** So aptitude's influence DECAYS as a monster approaches its
ceiling, and it is weakest exactly in the Platinum-and-above band the game is balanced for.

⚠️ **CAVEAT, AND IT MATTERS: that is a FOCUSED build.** A monster spreading across four stats
never caps them all, so aptitude keeps biting there. The honest claim is *"aptitude's value
decays toward the cap"*, not *"aptitude is worthless"*. **Worth measuring properly before it is
quoted as fact.**

**Why that supports station aptitude:** at endgame the differentiators that survive are
bloodline potential (it multiplies the cap), species innates, class, and kit. Stats converge.
Station aptitude adds an axis that **does not wash out at cap** — which is precisely what a
5v5 endgame band needs.

---

## 6. Where the disciplines disagree

Per `CLAUDE.md`, this is where the work gets good.

**Balancing (Hollis Bergmann):** *"Seven shapes, a counter web, team focus, dynamic collapse —
that is five or six interacting changes and every one moves the baselines. `sweep40` cannot tell
me which one did what. One at a time, and prove it. Team focus alone will be a big enough
shift."*

**Game mechanics (Nadia Ferrante):** *"None of it is expressible until the spatial rework lands.
A station is a statement about ground, and cover does not mean anything yet. Build the shapes on
a model that is being replaced and we will build them twice."*

**Art & design (Saoirse Byrne):** *"Formation is the first thing here that makes an arena matter
for a reason other than colour. A refused flank against a wall reads instantly. But if shapes
are not visually distinct at the camera distance we actually use, the player cannot see the one
decision we just gave them — and I would rather have four legible shapes than seven."*

**QA (Gideon Marsh):** *"Every shape needs a tripwire that it is REACHABLE and DISTINCT. We have
shipped authored-but-undrafted content three separate times. Seven shapes where two dominate is
the same failure with a new coat. And there is no guard today that a station assignment is even
satisfiable on a given arena."*

⚠️ **All four are right, and they point at the same order:** narrow the shape list, land the
spatial model first, then add ONE lever at a time with a tripwire on each.

---

## 7. A possible order of work

| # | step | why here |
|---|---|---|
| 0 | **Fix `comboRole`'s dead rows** | independent, live today, small |
| 1 | **Team-level focus** | the biggest single win, and testable without any new geometry |
| 2 | **Spatial rework** | everything positional is blocked on it |
| 3 | **4 shapes, not 7** | Line · Wedge · Box · Split. Prove the counter web on four |
| 4 | **Stations, by intent** | needs 2 and 3 |
| 5 | ~~Dynamic collapse~~ | ⏸️ **PARKED** — the user is unsure. Revisit after 3 and 4 |
| 6 | **Counter-formation in scouting** | needs 3 and 4 to mean anything |
| 7 | **Station aptitude in breeding** | the meta hook; needs 4 |

⚠️ **STEP 1 CAN START NOW.** It needs no geometry, it is the fix for a measured weakness, and it
is the one item on this list that the spatial rework cannot invalidate.

---

## 8. Open questions — ANSWERED 2026-08-03

**1. Does the AI opponent get formations?** ✅ **Yes — formations AND tactics, per team
TEMPLATE.** They hang off `src/teamTemplates.ts`, which already exists and already drives rival
composition. A template becomes a full doctrine: composition + shape + team orders. ⚠️ **This is
what makes the counter web a real game rather than single-player theatre** — and it means
authoring a template is now a design job, not a stat roll.

**2. Does scouting reveal the shape?** ✅ **Scouting has multiple tiers and the HIGHEST tier
shows everything.** The determinism worry is handled by the existing structure: cheap scouting
gives you a hint, full scouting gives you the answer and costs accordingly. ⚠️ Shape should be
placed on the tier ladder deliberately — it is arguably the single most actionable thing a
scout can return, so it should not be the cheapest.

**3. What if a shape does not fit an arena?** ✅ **Wrong way round — the ARENAS change.** The
user: *"we will rework how arenas are made if needs be, we only have a rough design idea of how
it could look, the actual arena will be so much larger using the better engine."*

⚠️ **THIS INVERTS THE CONSTRAINT AND IT IS THE MOST IMPORTANT OF THE FOUR ANSWERS.** Do not
design shapes to fit the current boards. The boards are placeholder, they are being rebuilt,
and they will be substantially LARGER. Design the shapes the fight wants, then build arenas that
can hold them. Every dimension in `ARENA_DESIGN.md` — the 40x22 field, `DEPLOY_DEPTH 11`, the
density law, the hex pitch — is provisional.

**4. Does formation cost anything?** ✅ **No. The per-match decision is free.** So the cost of a
bad read is losing the match, not losing a resource. ⚠️ Which raises the bar on the counter web
again: if re-planning is free, shapes must be genuinely rock-paper-scissors, because a
strictly-best shape would simply always be chosen.

### Still open

- **How many stations per shape?** Fixed five, or does each shape define its own slot count?
- **Dynamic formation (§2.2)** — ⏸️ **PARKED.** The user is not sure about it. Do not build it;
  revisit once the base system exists and there is something to judge it against.
