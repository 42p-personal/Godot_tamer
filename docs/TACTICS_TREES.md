# Tactics → behaviour tree subtrees

**2026-08-04.** Implements `docs/AUTOBATTLER_DESIGN.md` §2 (the four tactic axes), §8 #27–#28
(urgent overrides + the fight-on guard), §9 (tree architecture, utility-vs-branch division of
labour) and §12 #30 (blocking rule as a tactic). ⚠️ **Nothing here is built yet.** This is the
spec the monster's actual tree gets built from — the generic BT node library is a separate,
concurrent effort (`monster-tamer/scripts/ai/`), not authored here.

**Vocabulary discipline:** every option name below is the one already settled in
`AUTOBATTLER_DESIGN.md` §2 or already shipped in `monster-tamer/scripts/tactics.gd`. Nothing new
is invented except (a) the two `blockingPolicy` options §12 #30 asks for by name, and (b) code
identifiers for axes the source docs only named in prose (`whenHurt`, `abilityPolicy`,
`blockingPolicy` — flagged inline as proposals, not settled).

⚠️ **One real vocabulary collision found while writing this:** `tactics.gd`'s `TARGET_PRIORITY_INFO`
uses the id `"manmark"`; `AUTOBATTLER_DESIGN.md` §2A names the same option `marked`. This doc uses
`marked` (the newer, settled source) and flags the rename for whoever wires the two together.

---

## 0. Node vocabulary, leaf glossary, and the compose-time / tick-time split

### 0.1 Node types used throughout

| tag | node | semantics |
|---|---|---|
| `[Sel]` | **Selector** | tries children top to bottom, returns the first that succeeds/runs |
| `[Seq]` | **Sequence** | runs children top to bottom, fails at the first failure |
| `[Cond]` | **Condition** | leaf, evaluates true/false, no side effect |
| `[Act]` | **Action** | leaf, does something, may return `Running` across multiple ticks |
| `[Dec]` | **Decorator** | wraps one child, modifies its result or gates when it runs |
| `[Util]` | **Utility leaf** | scores a set of candidates and returns the best — not a branch |

### 0.2 Leaf actions referenced by name below

| leaf | does |
|---|---|
| `Idle` | do nothing this tick |
| `SetTarget(u)` | commit `current_target = u`, stamp the reason for the decision log |
| `Attack(u)` | resolve the free attack or a chosen skill against `u` (gated by Ability Policy, §6) |
| `MoveToward(point)` | path to `point`; wrapped by the `orNearestReachable` decorator (§0.3) on every call site — this is the ONLY movement primitive every subtree below calls |
| `PathAround(body)` | detour around a blocking body without stopping |
| `CastBestReadyMove(target, exclude=[])` | today's `battle_sim.gd` default: strongest ready move |
| `Cast(move, target)` | a specific named move |
| `EmergencyDisengage()` | the one-tick "oh shit" reflex — pop a defensive cooldown if one is ready, else take the single best immediate step out of every currently-threatening enemy's reach. Distinct from the measured `fallBack`/`disengage` withdrawal subtrees (§5) — this is a reflex, not a mode |

### 0.3 The `orNearestReachable` decorator — where "destination unreachable" actually lives

⚠️ **This is a deliberate design choice, not the obvious one, so it's stated up front.** The
brief lists "destination unreachable" as one of four co-equal urgent overrides. It is **not**
built as a fourth branch in a priority selector, because that would make every subtree above
re-check reachability before choosing a goal point — exactly the duplication this codebase's own
`CLAUDE.md` keeps finding and paying for. Instead:

```
MoveToward(point)  [Act, wraps a Navigation query]
├─ path := NavQuery(self.pos, point)
├─ if path == null OR path.length > MAX_DETOUR_MULT × straight_line(self.pos, point):
│     → this call FAILS reachable-as-ordered
│     → retries once against nearest_reachable_point_toward(point)   [best-effort substitute]
│     → decision log: "<name> couldn't reach <order> — held up short" (§10)
└─ else → MoveAlong(path), Running until arrived, then Success
```

**One leaf, one fix, every subtree inherits it for free.** `push`'s advance point, `hold`'s
home_point, `wings`'s flank waypoint, `dive`'s back-line pick, `guard`'s orbit point, and both
withdrawal subtrees in §5 all call `MoveToward` — none of them need their own unreachable-goal
handling.

### 0.4 Compose-time vs tick-time — read this before the root tree

**Two different things happen at two different times, and conflating them is the single easiest
way to misread everything below:**

- **Compose-time** (once, when a monster's committed tactics are read — battle start, or
  whenever an order changes mid-fight if that's ever allowed): the monster's **Positional
  Intent** value selects which of the five subtrees in §3 gets installed as *the* positional
  branch for this unit, for this fight. This is what "tactics swap whole subtrees, not flags"
  (§9 of the source doc) means literally — there is no runtime node that chooses between push
  and dive; the tree is built once with one of them wired in. Formation resolve (§4) also runs
  here, stamping `home_point`/`station` onto each unit before tick 0.
- **Tick-time**: everything else in this document — target scoring, mode selection, movement,
  ability gating — is re-evaluated at the **decision tick** cadence.

⚠️ **The decision-tick cadence itself is not specified anywhere in the settled design and this
doc does not own the BT node library, so it cannot decide it.** Every subtree below assumes a
periodic re-evaluation (illustrative: 0.2s, distinct from the physics/render tick) with `Running`
actions continuing smoothly between decisions, mirroring `RETARGET_EVERY`'s old role. **This is
an assumption for whoever builds `monster-tamer/scripts/ai/` to confirm or correct — see §12.**

---

## 1. The root tree

```
ROOT  [Sel, reactive — re-evaluated from the top every decision tick, so a higher branch
       can interrupt a Running lower one]
│
├─ [Seq] GATE — incapacitated, dead, or feared?
│     [Cond] is_incapacitated() OR has_status("fear")   → [Act] Idle
│
├─ [Seq] EMERGENCY DISENGAGE — the reflex, not a mode        ⚠️ §8 #28 GUARD LIVES HERE
│     [Cond] aboutToDie()  AND  escapeAvailable()  AND  whenHurt != 'fightOn'
│     → [Act] EmergencyDisengage()
│
└─ [Seq] STANDING PLAN — everything the player actually ordered
      1. [Util] TARGET SELECT           (§2)   → sets current_target
      2. [Sel]  MODE SELECT             (§5)   → chooses ENGAGE | FallBack-withdrawal | Disengage-withdrawal
      3.   inside ENGAGE only:
           [subtree]  POSITIONAL INTENT (§3, one of five, installed at compose-time)
             — internally consults BLOCKING POLICY (§7) at every movement leaf
           [Dec]      ABILITY POLICY    (§6) wraps every Attack/Cast leaf reached above
```

**Why this order, and not another.** Target Select runs first because Mode Select, Positional
Intent and Ability Policy all read `current_target`. Mode Select runs before Positional Intent
because it decides whether Positional Intent runs *at all* this tick — a monster mid-withdrawal
is not also trying to push; the two are mutually exclusive per tick, not blended.

### 1.1 ⚠️ Exactly where §8 #28 lives

> *"`fight on` BEATS THE DEATH OVERRIDE... The player's order stays sovereign."*

The guard is the clause `whenHurt != 'fightOn'` in the Emergency Disengage sequence above —
**one clause, one place.** It is reinforced a second time, structurally, in §5: a `fightOn`
unit's Mode Select has no withdrawal branches to fall into at all — there is nothing for a
`fightOn` unit to transition to even if the emergency clause were somehow bypassed. **Both
places are deliberate** (belt and braces): a future edit that patches only one of them cannot
reopen the flee-then-die spiral by accident.

### 1.2 The two homes of "ordered target gone"

⚠️ **§8 #27 lists this as one override; it actually lives in two unrelated places, and that's
worth saying plainly rather than implying one generic check.** It only has meaning where an
order names a *persistent, externally chosen* target — that's exactly two spots:

| where | what "gone" means | response |
|---|---|---|
| `targetPriority == 'marked'` (§2) | the marked rival died or was never scouted | fall through to the default utility scorer (weakest), logged as a real moment |
| `positionalIntent == 'guard'` (§3) | the guarded ally died | fall back to behaving as `hold` around own `home_point`, logged |

The other four target priorities (nearest/weakest/casters/tanks/threat) and the other four
positional intents (push/hold/wings/dive) have **no persistent order to lose** — they recompute
from whoever's alive every decision tick, so this override structurally cannot apply to them.

---

## 2. Target Priority (axis A) — one shared subtree, six scoring modes

```
TARGET SELECT  [Seq, runs every decision tick]
│
├─ [Dec] COMMITMENT — sticky (hold ~N seconds) | reassess (no hold), default from Focus (§9)
│    Sticky is suspended, not consumed, while Mode Select (§5) is NOT in ENGAGE — see §12.
│
└─ [Sel]
     ├─ [Seq] TAUNTED?  → [Act] SetTarget(taunter)              reason: "taunted by <X>"
     │
     ├─ [Seq] targetPriority == 'marked' AND markedUnit alive   → [Act] SetTarget(markedUnit)
     │
     ├─ [Seq] targetPriority == 'marked' AND markedUnit NOT alive   ⚠️ §1.2 override #1
     │    → falls through to the Utility leaf below, weakest as the substitute rule
     │    reason: "<marked> is down — no standing order"
     │
     └─ [Util] score every living, targetable candidate by the configured priority, SetTarget(argmax)
```

### 2.1 Scoring per option

| option | primary score | tie-break |
|---|---|---|
| `nearest` | `-distance(self, c)` | already a total order |
| `weakest` | `-hp_current(c)` | nearer wins |
| `casters` | `max(c.INT, c.WIS)` ⚠️ *reading of "highest INT/WIS" — max, not sum, so a mono-stat healer and a mono-stat nuker both qualify equally; open to override* | nearer |
| `tanks` | `c.CON` — matches `tactics.gd:_highest_stat` exactly | nearer |
| `marked` | not scored — direct pick, §1.2 | — |
| `threat` | `threat_score(c, watched=self)` (§2.2) | nearer |

### 2.2 `threat_score` — one formula, two callers

```
threat_score(candidate, watched) = Σ damage_dealt(candidate → watched) over THREAT_WINDOW seconds
```

Used with `watched = self` for the plain `threat` priority, and reused with `watched =
guarded_ally` by Guard's own interpose logic (§3.5) — deliberately the same primitive so "who is
hurting me or my charge most" is one leaf, not two. ⚠️ **New state required:** a rolling
per-unit damage-received log, windowed at `THREAT_WINDOW` (illustrative 5.0s). Nothing today
tracks this — see §12.

### 2.3 Candidate filter (applies to every option above)

Living, not `is_incapacitated()`-irrelevant (a dead unit is never a candidate regardless), and
not currently **faded** (the "anti-taunt" innate effect noted in `core.ts` — a unit that dropped
off the radar is untargetable by priority scoring, same as it is by taunt).

---

## 3. Positional Intent (axis B) — five genuinely distinct subtrees

**This is the flagship swap.** Each option below has a structurally different **goal-point
function** and a structurally different **default behaviour when nothing is in reach** — not one
tree with five numbers plugged in. The closing table proves it.

### 3.1 `push` — advance on the enemy line, take ground

```
PUSH  [Seq]
├─ [Sel]
│    ├─ [Cond] distance(self, current_target) <= reach   → [Act] Attack(current_target)
│    └─ [Act]  MoveToward( point PUSH_LEAD_DISTANCE past current_target,
│                           on the vector from self toward current_target
│                           — or past the living enemy centroid if no target )
```

**The defining trait:** the goal point is never the target's position — it's a point *beyond*
it. A pusher that kills its target doesn't stop at the now-empty spot; next tick it keeps
advancing, because the goal point was always "further" than "here." That's what makes ground get
taken rather than merely closed.

### 3.2 `hold` — keep the line near where I deployed

```
HOLD  [Seq]
├─ home_point := this unit's Formation-resolved station (§4)
├─ [Sel]
│    ├─ [Cond] an enemy is within reach of home_point         → [Act] Attack(nearest such enemy)
│    ├─ [Cond] current_target within (reach + HOLD_SLACK) of home_point → [Act] MoveToward(current_target)
│    └─ [Act]  MoveToward(home_point)                          — return to post, nothing here justifies leaving
```

**The defining trait:** a hard anchor (`home_point`) with a bounded permitted step
(`HOLD_SLACK`, Discipline-scaled, §9). Nothing else in this axis has a fixed rearward anchor it
returns to.

### 3.3 `wings` — work wide, approach from the flank

```
WINGS  [Seq]
├─ flank_side := assigned at COMPOSE-TIME (§0.4), not recomputed per tick — see note below
├─ flank_point := lateral point offset from the straight line self→current_target, toward flank_side
├─ [Sel]
│    ├─ [Cond] distance(self, current_target) <= reach AND approach_angle >= WING_MIN_ANGLE off target's front
│    │       → [Act] Attack(current_target)
│    ├─ [Cond] at flank_point (within tolerance)               → [Act] MoveToward(current_target)   — cut in
│    └─ [Act]  MoveToward(flank_point)                          — go wide FIRST, engage SECOND
```

⚠️ **`flank_side` must be a compose-time assignment, not a reactive "nearest edge" pick.** A
reactive rule risks two `wings` units on the same starting side both picking the same flank,
re-creating the blob this axis exists to prevent. Rule: if the unit's Formation `home_point`
already sits left/right of the team's centreline, use that side; otherwise alternate L/R among
this team's `wings`-tagged units in roster order (deterministic, no RNG draw).

**The defining trait:** a mandatory waypoint gate before it will path toward a target at all.
That waypoint is what physically spreads the team across the board width — directly serving
`AUTOBATTLER_DESIGN.md` §5's anti-blob list.

### 3.4 `dive` — go around/through for the enemy back line

```
DIVE  [Seq]
├─ back_target := [Util] highest-scoring living enemy by "depth" (farthest from the diver's own
│                 deploy edge) among current candidates — this is the unit's OWN target-for-
│                 movement pick; current_target (from §2) still governs who gets ATTACKED once
│                 something is in reach. These can legally diverge — see §12.
├─ [Sel]
│    ├─ [Cond] distance(self, back_target) <= reach          → [Act] Attack(current_target)
│    ├─ [Seq] path to back_target crosses an enemy body within reach RIGHT NOW
│    │    → consult BLOCKING POLICY (§7) — this is where it plugs in
│    └─ [Act]  MoveToward(back_target)
```

**The defining trait:** the movement goal is filtered to depth, independent of whatever Target
Priority is doing for the attack roll. This is also the positional intent that makes the
Blocking Policy axis (§7) matter most — diving is exactly the situation where "something is in
my way toward an ordered destination" comes up.

### 3.5 `guard` — stay near a named ally and intercept threats to it

```
GUARD  [Seq]
├─ [Sel]
│    ├─ [Seq] guarded_ally NOT alive                            ⚠️ §1.2 override #2
│    │    → behave as HOLD around own home_point, logged: "<charge> is down — holding position"
│    └─ [Sel]
│         ├─ [Seq] an enemy is within INTERCEPT_RADIUS of guarded_ally, unclaimed by another guard
│         │    → [Act] MoveToward(intercept point between that enemy and guarded_ally), then Attack it
│         │      — this OVERRIDES §2's current_target for the duration of the interpose (§12)
│         ├─ [Cond] distance(self, guarded_ally) > GUARD_LEASH  → [Act] MoveToward(guarded_ally)
│         └─ [Act]  MoveToward(orbit point near guarded_ally)    — stay adjacent, attack current_target if in reach
```

**The defining trait:** its anchor is a *moving* point (the ally's live position), not a fixed
one, and it carries its own target override tied to `threat_score(·, watched=guarded_ally)`
(§2.2) rather than deferring purely to §2's output.

### 3.6 The proof this is five trees, not one

| positional intent | goal-point concept | with nothing in reach, it… |
|---|---|---|
| `push` | a point past the target, toward the enemy line | keeps advancing past where the enemy line was |
| `hold` | a fixed deploy-time anchor | returns to post |
| `wings` | a mandatory lateral waypoint | returns to / holds the flank waypoint |
| `dive` | the current back-line pick | keeps advancing toward the (re-scored) back line |
| `guard` | the guarded ally's live position | orbits the charge |

Five different answers to the same question. That's the structural distinctness the source
document asks for.

---

## 4. Formation (axis C) — compose-time data, not a tick-time subtree

**Honestly: this axis has no runtime branch.** Per `AUTOBATTLER_DESIGN.md` decision #1,
*"Spacing is a property of the formation, not a separate order"* — a saved formation is a set of
world offsets in the team's own half. Its only job in this tree is to seed the inputs the five
subtrees above already read:

```
FORMATION RESOLVE  [runs once, compose-time, before tick 0]
for each monster in the team's saved formation:
    home_point[monster] := formation.offset[monster]     — read by hold (§3.2), fallback branches
                                                             of guard/wings (§3.3, §3.5)
```

⚠️ **Open seam, flagged not fixed.** `TACTICS_BRAINSTORM.md` §2.3 designed named **stations**
(Anchor/Screen/Skirmish/Support/Free) as semantic slots a resolver places on the arena; the
settled `AUTOBATTLER_DESIGN.md` instead specifies raw free placement with no station labels.
This document has followed the settled doc (no station labels exist to read), but several reason
strings (§10) would read better with one — `"Aegisox holds Anchor"` beats `"Aegisox holds
position (44, 12)"`. **Whether saved formations carry an optional per-slot station label is an
open decision, not resolved here** — see §12.

---

## 5. When Hurt (axis D, part 1) — Mode Select + two withdrawal subtrees

### 5.1 Mode Select

```
MODE SELECT  [Sel, tick-time, chooses which of three modes is active]
├─ [Cond] whenHurt == 'fightOn'                                    → ENGAGE, always, no exceptions
├─ [Sel]  whenHurt == 'fallBack'
│    ├─ [Cond] hp_frac <= FALLBACK_TRIGGER  OR  already mid-withdrawal and not yet SAFE (§5.2)
│    │    → FALLBACK WITHDRAWAL (§5.2)
│    └─ default → ENGAGE
└─ [Sel]  whenHurt == 'disengage'
     ├─ [Cond] hp_frac <= DISENGAGE_TRIGGER  OR  already mid-withdrawal and not yet HEALED (§5.3)
     │    → DISENGAGE WITHDRAWAL (§5.3)
     └─ default → ENGAGE
```

**ENGAGE** is the mode that contains the whole of §3 (Positional Intent) + §7 (Blocking Policy)
+ §6 (Ability Policy). `fightOn` never leaves it. `fallBack`/`disengage` leave it only when their
HP trigger fires, and only return to it once their own exit condition (§5.2/§5.3) is met.

⚠️ **This is distinct from Emergency Disengage (§1).** Mode Select's thresholds are the
*graduated*, voluntary transition the tactic itself describes. Emergency Disengage (§1) is a
same-tick safety net for **burst damage that skips the graduated threshold entirely** — a unit
at 90% HP that eats a one-shot combo never crossed `FALLBACK_TRIGGER` on the way down. Both exist
because neither alone covers both failure modes.

### 5.2 `fallBack` — withdraw toward allies, re-engage when steadied

```
FALLBACK WITHDRAWAL  [Seq]
├─ on entry (first tick only): stamp committed_until := now + MIN_DWELL_FALLBACK
├─ [Act] MoveToward(nearest ally cluster point); Attack opportunistically ONLY if a target is
│         already in reach without turning off the retreat vector — never chases
└─ EXIT (checked every tick, returns control to Mode Select once true):
     now >= committed_until  AND  SAFE
     SAFE := hp_frac >= SAFE_HP_FRAC (Nerve-scaled, §9)  AND  ≥1 ally within a short radius of self
```

`SAFE` requires having actually rejoined support, not merely having taken one step back — the
direct fix for TFM's flee-then-immediately-return complaint (`AUTOBATTLER_DESIGN.md` §0, §10).

### 5.3 `disengage` — break off, seek cover, do not return until healed

```
DISENGAGE WITHDRAWAL  [Seq]
├─ on entry: stamp committed_until := now + MIN_DWELL_DISENGAGE   (longer than fallBack's — §9)
├─ [Sel]
│    ├─ [Cond] a cover point exists that breaks LOS to current_target   → [Act] MoveToward(cover_point)
│    └─ [Act]  MoveToward(a point toward the leash boundary, away from the fight's centroid)
└─ EXIT: now >= committed_until  AND  hp_frac >= DISENGAGE_HEAL_FRAC (Nerve-scaled, stricter than fallBack's)
```

⚠️ **Build dependency, not yet real.** The cover-seeking branch is `SPATIAL_MODEL.md` §11's
"cover as a verb" — arriving breaks the pursuer's lock/interrupts its cast. That mechanic is
**proposed, not built**: cover isn't yet a queryable disengagement location, and "breaking LOS
interrupts" doesn't exist. **Until it lands, `disengage` should degrade to its own second
branch** (retreat toward the leash boundary) unconditionally — same shape as `fallBack` but with
the stricter `DISENGAGE_HEAL_FRAC` bar and longer dwell. Flagged again in §12.

`fallBack` and `disengage` share a withdrawal *shape* (dwell → move-to-safety → exit check) but
differ in the safety-point definition, the exit bar and the dwell length — siblings, not one
tree with different numbers plugged in, because the safety-point leaf itself differs (seek-allies
vs seek-cover).

---

## 6. Ability Policy (axis D, part 2) — a decorator on every Attack leaf

Not a positional subtree — this wraps whichever `Attack`/`Cast` leaf any subtree above reaches.

```
ABILITY POLICY  [Dec, wraps the Attack leaf wherever it's called]
├─ free:
│    [Act] CastBestReadyMove(target)                       — today's battle_sim.gd default
│
├─ holdBig:
│    [Sel]
│    ├─ [Cond] the flagged capstone is ready AND GoodMomentScore(target) >= HOLD_BIG_THRESHOLD
│    │    → [Act] Cast(capstone, target)
│    └─ [Act] CastBestReadyMove(target, exclude=[capstone])  — everything else spends normally
│
└─ combo:
     [Sel]
     ├─ [Cond] an opener/applier move is ready AND target lacks the combo status
     │    → [Act] Cast(opener, target)                     — maps to core.ts comboRole 'prime'
     ├─ [Cond] target HAS the combo status AND the payoff move is ready
     │    → [Act] Cast(payoff, target)                     — maps to core.ts comboRole 'detonate'
     └─ [Act] CastBestReadyMove(target, exclude=[payoff])   — never waste the payoff on an unset target
```

`GoodMomentScore` (a utility read, §11): a composite of *would this plausibly secure a kill*
(`target hp_frac × capstone's expected damage`) and, if the capstone is an AoE, *how many enemies
sit in its footprint right now*. Not derived here — a placeholder shape, tuned once the pool is
final.

---

## 7. Blocking Policy (build decision #30) — the two named subtrees

`AUTOBATTLER_DESIGN.md` §12 #30 supersedes §9's single recommended rule: the blocking rule is now
a **tactic**, with two options. Proposed ids: `bullThrough` | `engageIntercept`.

```
BLOCKING CHECK  [consulted inside any movement leaf, whenever the path is occupied]
[Cond] an enemy body sits on/adjacent to my current path AND is within my reach right now?
├─ No  → continue the path unchanged
└─ Yes → branch by blockingPolicy:
     │
     ├─ bullThrough:
     │    [Sel]
     │    ├─ [Cond] the blocker is NOT my current ordered movement target (e.g. dive's back_target)
     │    │    → [Act] PathAround(blocker) — one incidental swing if already in reach, does not stop
     │    └─ [Cond] the blocker IS my ordered target → [Act] Attack(blocker)   (this is just arriving)
     │
     └─ engageIntercept:
          [Act] Attack(blocker); RETARGET current_target := blocker for as long as it stays alive
          and adjacent — the interceptor becomes the fight, overriding the standing order for
          that engagement's duration
```

**Where it matters most:** `dive` (§3.4), because diving toward a back-line point is the
positional intent most likely to run into an unwilling body in the way. It also applies inside
`push` and `wings` — any subtree whose movement leaf can be blocked.

**Default from Discipline** — see §9: high Discipline defaults to `bullThrough` (sticks to the
plan), low Discipline defaults to `engageIntercept` (gets drawn into whatever's in front of it),
matching Discipline's own definition, *"how tightly it holds the ordered positional intent under
pressure."*

---

## 8. Urgent overrides — consolidated

| override | condition | lives in the tree at… | response |
|---|---|---|---|
| **taunted** | `hasTaunt(self)` | §2, first branch of Target Select's Selector | forced `SetTarget(taunter)` for the taunt's duration — patches targeting only, does not touch positional intent or when-hurt |
| **ordered target gone** | `targetPriority=='marked'` and it died · **or** `positionalIntent=='guard'` and the charge died | §2 (marked) / §3.5 (guard) — two separate homes, not one generic check (§1.2) | fall through to default scoring / behave as `hold` |
| **about to die + escape available** | `aboutToDie() AND escapeAvailable() AND whenHurt != 'fightOn'` | §1, root-level, above the Standing Plan | one-tick `EmergencyDisengage()` reflex, then control returns to Mode Select next tick |
| **destination unreachable** | `MoveToward`'s own path-length check | §0.3, inside the shared movement leaf, not a top-level branch | best-effort substitute point, logged |

`aboutToDie()` and `escapeAvailable()`, defined concretely (not asserted):

```
aboutToDie()      := hp_frac <= LETHAL_RISK_FRAC
                       AND ∃ enemy E: self within E's reach AND E's average hit ≥ current HP
escapeAvailable()  := ∃ a point reachable this tick that exits every currently-threatening
                       enemy's reach   OR   a defensive/escape cooldown is ready
```

Both conditions are required together, deliberately — a merely low-HP unit that is out of every
enemy's reach is not in danger and should not trigger the reflex.

---

## 9. Personality → branch weighting

| stat | node(s) it reads | what it changes | mechanism |
|---|---|---|---|
| **Discipline** | §7 Blocking Policy default · §3.2 `HOLD_SLACK` | improvises ↔ follows the plan | `blockingPolicy` default = `bullThrough` above a threshold, else `engageIntercept`; `HOLD_SLACK = lerp(SLACK_MAX, SLACK_MIN, discipline/100)` — low Discipline tolerates more drift from the ordered station before self-correcting |
| **Nerve** | §5.2/§5.3 exit conditions and dwell timers · §2 target-scoring noise | quality of a `fallBack`/`disengage`; decision quality under pressure | `SAFE_HP_FRAC = lerp(0.65, 0.40, nerve/100)`, `DISENGAGE_HEAL_FRAC = lerp(0.90, 0.60, nerve/100)` — low Nerve needs to recover further before it trusts re-engaging. `MIN_DWELL = lerp(DWELL_MAX, DWELL_MIN, nerve/100)` — rattled units hesitate longer. Below `PANIC_HP_FRAC`, a noise term inversely scaled by Nerve perturbs §2's utility score, modelling a panicked unit occasionally picking a worse target |
| **Aggression** | §3 default positional intent · §2 default target priority · §3.1 `PUSH_LEAD_DISTANCE` · §3.2 `HOLD_SLACK` | patient ↔ eager; sets DEFAULTS the player sees before overriding | high Aggression defaults toward `push`/`dive` and `weakest`/`threat`; low Aggression defaults toward `hold`/`guard` and `tanks`/`nearest`. At execution level, high Aggression stretches `push`'s lead distance further past the line; low Aggression shrinks `hold`'s slack tighter to post |
| **Focus** | §2 Commitment decorator | distractible ↔ fixated; default commitment | default = `sticky` above a threshold else `reassess`; regardless of the player's explicit choice, `STICKY_HOLD = lerp(STICKY_MIN, STICKY_MAX, focus/100)` scales how long a sticky hold actually lasts |

⚠️ **Every constant named above and in §11 is illustrative, not tuned** — the balance baseline is
suspended (`CLAUDE.md`); getting the branch structure right is this document's job, not the
numbers.

---

## 10. Intent and reason strings — player vocabulary, not node names

| branch | live intent label | reason string template |
|---|---|---|
| §2 taunted | `taunted` | `"<name> is taunted by <taunter>"` |
| §2 marked target gone | `retargeting` | `"<marked> is down — <name> reverts to no standing order"` |
| §2 default scorer | `hunting <priority noun>` (e.g. `hunting casters`) | `"<name> switched target → <target> (your order: <priority label>)"` |
| §1 Emergency Disengage | `bailing out` | `"<name> nearly died — broke off despite orders to survive"` |
| §3.1 `push` | `pushing` | `"<name> is pressing the line (your order: Push)"` |
| §3.2 `hold` (in reach) | `holding the line` | `"<name> is holding position (your order: Hold)"` |
| §3.2 `hold` (returning) | `returning to post` | `"<name> pulled back to its station — nothing near enough to chase"` |
| §3.3 `wings` (going wide) | `flanking` | `"<name> is working the flank (your order: Wings)"` |
| §3.3 `wings` (cutting in) | `cutting in` | `"<name> cut in from the flank onto <target>"` |
| §3.4 `dive` | `diving for the back line` | `"<name> is pushing for <target> (your order: Dive)"` |
| §3.5 `guard` (interposing) | `guarding <charge>` | `"<name> stepped between <enemy> and <charge>"` |
| §3.5 `guard` (charge dead) | `holding position` | `"<charge> is down — <name> is holding position instead"` |
| §5.2 `fallBack` (withdrawing) | `falling back` | `"<name> fell back (your order: When hurt → Fall back; Nerve <n>)"` |
| §5.2 `fallBack` (re-engaging) | `re-engaging` | `"<name> steadied up and is back in the fight"` |
| §5.3 `disengage` (seeking cover) | `breaking off` | `"<name> broke off to <cover> (your order: When hurt → Disengage)"` |
| §7 `bullThrough` | `pressing on` | `"<name> pushed past <blocker> — Discipline <d> kept it on target"` |
| §7 `engageIntercept` | `engaging the interceptor` | `"<name> got drawn into <blocker> instead of its order"` |
| §0.3 unreachable destination | `held up` | `"<name> couldn't reach <order> — held up short"` |

The two worked examples in the brief map directly:
`"Falling back — your order, and Nerve 62 kept it clean"` = §5.2's template with Nerve substituted;
`"Grivvel switched target → Corvaan (your order: Break the Casters)"` = §2's default-scorer template.

---

## 11. Utility scoring vs branching — the division of labour, stated plainly

Per `AUTOBATTLER_DESIGN.md` §9: *the tree decides what kind of thing to do, utility decides
which one.* Applied concretely:

| node | type | why |
|---|---|---|
| which positional subtree runs (push/hold/wings/dive/guard) | **not runtime at all** | compose-time selection from the tactic value — §0.4 |
| which mode is active (engage/fallBack-withdraw/disengage-withdraw) | **branch** | a small closed set of named states with real threshold conditions — legible as "why" on its own |
| which enemy to attack | **utility** (§2) | six named priorities are six scoring functions over the same candidate set — a branch per enemy doesn't scale and loses nuance |
| which point to move to inside a subtree (flank waypoint side, dive's back-line pick, guard's interpose target) | **utility**, embedded inside the branch-selected subtree | picking among candidate points/enemies within an already-chosen behaviour — structure decided the "what", utility decides the specific target |
| which move to cast | **branch** (§6) — `free`/`holdBig`/`combo` are structurally different policies, not a score | a move's cost/cooldown/setup state makes this closer to "which kind of spend" than "which is biggest number" — except `GoodMomentScore` inside `holdBig`, which *is* a utility read gating one branch |
| blocking policy | **branch** (§7) | two structurally different responses to the same trigger, not a spectrum |

---

## 12. Open — flagged honestly, not quietly resolved

- ⚠️ **Decision-tick cadence is assumed, not specified.** Every subtree above presumes a
  periodic re-evaluation distinct from the render/physics tick. This doc does not own
  `monster-tamer/scripts/ai/`; the assumption needs confirming there.
- ⚠️ **`disengage`'s cover-seeking branch (§5.3) depends on unbuilt infrastructure**
  (`SPATIAL_MODEL.md` §11's cover-as-verb — queryable disengagement locations, LOS-break
  interrupting a cast). Until it lands, `disengage` should run its fallback branch
  unconditionally (retreat toward the leash boundary), which is already specified as the
  degrade path, not a new decision.
- ⚠️ **`threat_score` (§2.2) needs new per-unit state** — a rolling damage-received log. Nothing
  in the current engine (including the explicitly-non-spatial `battle_sim.gd`) tracks this today.
- ⚠️ **`dive`'s movement target and §2's attack target can legally diverge** (§3.4) — a `dive +
  tanks` combination beelines for the back line but attacks whichever tank happens to intercept
  it, unless `bullThrough` presses on regardless. This is a real, designed interaction, not a
  bug, but it means Positional Intent and Target Priority are **not fully orthogonal in
  practice**, despite being presented as independent axes in the source doc. Worth surfacing to
  the player, not just to the engineer — see the main report.
- ⚠️ **Guard's interpose target overriding §2's `current_target` (§3.5) is a second place the
  "independent axes" framing leaks.** Designed and stated explicitly here; still worth a
  dedicated QA check once built, since it's the kind of cross-axis coupling this project's own
  `comboRole` history shows is easy to leave silently dead on the wrong kit.
- ⚠️ **The Formation/Station seam (§4) is unresolved**, not fixed: does a saved formation carry
  an optional station label for legibility, or is `home_point` purely a coordinate?
- ⚠️ **Combinatorial surface.** 5 positional intents × 6 target priorities × 2 blocking policies
  × 3 ability policies × 3 when-hurt states = 540 raw per-monster combinations before personality
  is even factored in. This project's own QA doctrine (`TACTICS_BRAINSTORM.md` §6: *"every shape
  needs a tripwire that it is REACHABLE and DISTINCT"*) argues for either a reachability/sanity
  sweep across the cross product, or a curated subset surfaced in the UI rather than every
  combination being freely choosable. Not decided here — flagged for `game-designer`/`qa-lead`.
- ⚠️ **Sticky commitment (§2) during a non-ENGAGE mode.** The hold timer should almost certainly
  *pause* rather than tick down while a unit is mid-withdrawal (§5.2/§5.3), or a retreat will
  quietly burn the held target and force an unwanted reassessment the instant the unit
  re-engages. Stated as the intended behaviour in §2's decorator note; not exercised against an
  implementation yet.
