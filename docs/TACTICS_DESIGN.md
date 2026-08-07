# Formation and orders — the rework brief

**Written 2026-08-03**, prompted by the user: *"it seems like a fixed blob is the formation and
we can be more creative."*

That is correct, and it is worse than "blob" suggests. This document measures what deployment
actually does today, argues why it matters more than it looks, and lays out design directions.

⚠️ **THIS IS A BRIEF, NOT A SPEC.** The vision's fixed points are in `CLAUDE.md`; everything
here is open for argument. Nothing below should be built before the shape is agreed.

---

## 1. What formation does today — measured

All of `autoPlace` (`engine.ts:118`):

```ts
const front = m.stats.CON + m.stats.STR >= m.stats.INT + m.stats.WIS
const depth = front ? DEPLOY_DEPTH * 0.75 : DEPLOY_DEPTH * 0.3
```

On a 40 × 22 field with `DEPLOY_DEPTH = 11`:

| what | value |
|---|---|
| x-positions a unit can EVER deploy to | **exactly two** — `8.25` or `3.3` |
| what decides which | **one boolean**, `CON+STR >= INT+WIS` |
| y positions, n=5 | `3.0, 7.0, 11.0, 15.0, 19.0` — **always evenly spaced** |
| y positions, n=3 | `6.2, 11.0, 15.8` — **always evenly spaced** |
| rank separation | 4.95 units |
| **how much of this the player chooses** | **none of it** |

⚠️ **SO A 5v5 DEPLOYS AS A COMB: five units on one of two vertical lines, evenly spaced, with
the split decided by a stat sum the player never sees.** "Fixed blob" is generous.

### Three specific consequences

**a. There is no shape, so there is no shape to counter.** Every team of the same composition
deploys identically. Scouting tells you the opponent's gameplan and kit, and then their
positions are a foregone conclusion — half the value of scouting is spent on nothing.

**b. The front/back test is a stat sum, not a role.** A Tank and a Warrior both go front; a
Sage and a Wizard both go back. It cannot express *"this Warden screens the left while the
Ranger holds the right"* because it has no vocabulary for left or right, or for screening.

**c. Even spacing is the worst case for AoE and the best case for nothing.** Five bodies on a
line at fixed 4-unit intervals is a predictable shape for an area move to catch, and the player
has no way to spread against a caster or clump against a duellist. ⚠️ `spacing` exists as a
tactic and `spreadStatus` was designed to punish clumping — **both are answering a question the
deployment never asks.**

### What the player CAN currently order

`Tactics` is not thin — temperament, `targetPriority`, `manaPolicy`, `comboRole`, `openerIds`,
`preserve`, `ccPriority`, plus the spatial orders. ⚠️ **The problem is not a lack of knobs. It
is that none of them are POSITION**, and position is the one thing a spectator can actually see
working or failing.

⚠️ **AND THERE IS A LEGIBILITY DEBT IN THE EXISTING ORDERS.** `comboRole` is documented as
meaningless on ~32% of monsters — the ones whose kit holds neither an applier nor a payoff. A
live control that does nothing is this project's signature failure mode, and it is already
present in the panel the player uses most.

---

## 2. Why this matters more than it looks

⚠️ **THE PLAYER CANNOT INTERVENE.** That is a fixed point of the vision, and it changes the job
of every pre-fight decision. Orders are not conveniences — they are *the whole input*. The
fight is the output.

For that loop to be satisfying, an order must be:

1. **Predictable** — the player can imagine what it will do before committing.
2. **Visible** — they can SEE it happening during the watch.
3. **Diagnosable** — when it fails, they can tell that it failed and why.

**Position scores well on all three and nothing else in `Tactics` does.** A player can watch a
flank land. They cannot watch a `manaPolicy`. This is why formation is the highest-value
target in the orders system, not a cosmetic one.

⚠️ **It is also the honest answer to "does the player have enough agency?"** They have a lot of
knobs and very little that they can watch pay off. Formation converts abstract preparation into
something observable.

---

## 3. Design directions

Not mutually exclusive; roughly increasing in ambition. Each notes what it costs.

### A. Player-authored deployment — the baseline

The player places each monster within their deploy band before the fight. Positions are saved
per team.

- **For:** total agency; makes scouting pay off; trivially legible; the obvious floor.
- **Against:** fiddly at 5v5 across many cups; risks becoming a chore — which is exactly the
  charge already open against the 30-drill training loop.
- **Note:** ⚠️ needs a sensible default or it is a wall for a new player. `autoPlace` becomes
  the suggestion rather than the law.

### B. Formation presets with real mechanical identity

The player picks a named shape; monsters fill stations by role. Each shape trades something
concrete.

| shape | what it does | pays for it with |
|---|---|---|
| **Line** | even frontage, no flank exposed | nothing concentrated |
| **Wedge** | concentrates the charge, breaks a line | exposed flanks |
| **Refused flank** | one wing held back, forces engagement on the other | gives up ground |
| **Split** | two groups, forces the enemy to choose | can be defeated in detail |
| **Box** | back line fully screened | slow, poor at pressing |

- **For:** legible, thematic, low click-cost, and it makes scouting a real read — you counter a
  wedge differently than a box.
- **Against:** presets can collapse to one dominant answer; needs the sim to prove they don't.

### C. Per-monster station orders

Rather than absolute positions: `anchor` / `screen` / `skirmish` / `hold back` / `flank`.
Resolved into positions at deploy time against the arena and the enemy.

- **For:** composes with B; expresses intent rather than coordinates, so it survives arenas of
  different shapes; ⚠️ **it is the version that keeps working when arenas stop being flat
  rectangles**, which they will in Godot.
- **Against:** the resolver is real work and can surprise the player — the exact failure
  `reachOf` hit twice.

### D. Counter-formation as the scouting payoff

Scouting already reveals the rival gameplan. Extend it to reveal their SHAPE, and let the
player answer it. Formation becomes a read rather than a setting.

- **For:** gives scouting a second job; creates a genuine rock-paper-scissors layer that is
  strategic rather than random.
- **Against:** only works if B or C exists first, and only if shapes genuinely counter each
  other rather than one being best.

### E. Terrain-aware deployment

Once arenas are real 3D spaces with cover, deployment should care about it — hold the high
ground, put the back line behind hard cover, deny the choke.

- **For:** it is the reason to have arenas at all, and it makes the arena pool matter beyond
  colour.
- **Against:** ⚠️ **blocked on the spatial rework** (`SPATIAL_COMBAT_DESIGN.md`). Do not design
  this until cover means something.

---

## 4. Recommendation

**B + C together, then D once they are proven.**

Presets give legibility and low click-cost; station orders give expressiveness and survive the
move to real arenas; counter-formation then turns the pair into a read rather than a
preference. A is worth keeping as an *advanced override* for players who want it, not as the
primary interface — at 5v5 across a full ladder it would become the chore.

⚠️ **AND HOLD IT ALL BEHIND THE SPATIAL REWORK.** Formation is a statement about ground. Until
cover, reach and flanking are settled (`SPATIAL_COMBAT_DESIGN.md`), a formation system would be
authored against a model that is being replaced — the same mistake as porting the arenas.

**What can be done NOW, before that lands:**
- Decide the shape vocabulary on paper — it is a design conversation, not code.
- ⚠️ **Fix the `comboRole` legibility hole**, or gate it in the UI. It is live today and does
  nothing on a third of monsters.
- Answer the open question below, because it changes everything above.

---

## 5. ⚠️ The open question this rework depends on

**Is formation set per TEAM, per MONSTER, or per MATCH?**

- **Per team** — one shape for the roster you enter. Cheapest, least expressive.
- **Per monster** — each carries a standing order, like the rest of `Tactics`. Consistent with
  how orders already work, but no single monster can express a team shape.
- **Per match** — chosen after scouting, against this specific opponent. ⚠️ **The most
  interesting and the most work**, and the only one that makes D possible.

The vision says the player *"decides their tactics and watches how their tactics unfold"* —
which reads as per-match to me, because a tactic chosen against a known opponent is a decision,
and a tactic set once and forgotten is a preference. **But that is an inference, not something
the user has said, and it is the hinge the rest of this document turns on.**
