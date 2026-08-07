# Ability pool balance review — larger arenas

**2026-08-03.** Requested audit: how the 141-move pool holds up under the arena-size direction
change (`docs/ENGAGEMENT_DESIGN.md`, `docs/SPATIAL_MODEL.md`). Design review only — no source
changed.

⚠️ **METHOD NOTE, READ FIRST.** This session has no shell/Bash tool available, so `npx tsx
tools/pool.ts` could not be executed directly. What follows instead: (1) the pool's own printed
distribution figure the task was seeded with (`INT` 5.9–184.0/s, 77 damage moves, 0 flags) is
taken as the measured baseline; (2) I hand-computed `totalValue` for ~20 specific moves straight
from the formulas in `tools/pool.ts` and the constants in `src/core.ts` / `src/tamerengine/
types.ts`, reading `src/moves.ts` directly for every input (power, mana, cooldown, accuracy,
learnLevel, effects, status). My Ember (≈7.1/s) and World Ender (≈195/s) land within the stated
5.9–184 band, which is the cross-check that this document's numbers are consistent with an actual
run rather than invented. **Every number below is reproducible by anyone with a shell** —
`npx tsx tools/pool.ts` and `npx tsx tools/pool.ts --stat INT` will print the real figures; treat
mine as a spot-check, not a replacement, and re-run before acting on anything here.

---

## 0. The one decision everything below depends on

`ENGAGEMENT_DESIGN.md` and `SPATIAL_MODEL.md` both already propose **two numbers, not one**: a
big decorative **venue** (stands, ornament, crowd) containing a bounded **ground** (where the
fight actually happens, sized to what the camera and the sim can hold together). Neither doc has
committed to which one the ability pool should be re-tuned against, and it is not a detail — it
inverts this entire review.

- **If the GROUND grows 2–4x** (the field the sim actually runs `FIELD_W`/`FIELD_H` at), every
  reach value in the pool, every gap-closer, the deploy distance and the leash all need
  re-deriving, because they are authored as absolute world-unit constants against the *current*
  ~40-wide field. §1 below is the sizing of that problem.
- **If only the VENUE grows** and the ground stays close to its current calibrated size (per
  `ENGAGEMENT_DESIGN.md` family C — a bounded engagement zone, a leash, cover-as-disengagement),
  then **almost nothing in this document needs to change**. The pool's reach axis was seeded
  against "a field 34–64 wide" (`tools/authorranges.ts` line 30) — i.e. up to 1.6x today's width
  — which a bounded ground could plausibly still satisfy.

⚠️ **The task brief says the ground is what's scaling** — *"a 1v1 arena is smaller than a 5v5
arena... the current field is 40x22 which is tiny"* — which reads as team-size-scaled `FIELD_W`/
`FIELD_H`, not a fixed ground with a bigger backdrop. §1 is written assuming that is the direction,
but **this should be confirmed explicitly before any pool number moves**, because the two
readings do not just differ in degree — one requires touching ~40 constants across two files and
one requires touching almost none.

---

## 1. What breaks at size

### 1.1 The throughline: every spatial constant in the pool is an absolute world-unit, tuned to a ~40-wide field

None of these scale with `FIELD_W`/`FIELD_H` today — they are hardcoded numbers that happen to
make sense on the current board:

| constant | value | what it assumes |
|---|---|---|
| `LINE_RANGE` (per line, 18 values) | 2.8–10.5 | authored "on a field 34–64 wide" (`authorranges.ts:30`) |
| `HARD` reach bounds | [2.4, 11.0] | clamps every one of the 141 authored `range` values |
| `CHANNEL_RANGE` (basic-attack bands) | melee 3.0 / ranged 8 / magic 7 / support 6 | swept and plateaued at these values on the 40x22 field (`types.ts:960`) |
| Dash `maxRange` (STR gap-closers) | 7–9 | Power Strike 7, Titanfall 9, Colossus Crash 8, Body Slam 7 |
| Blink `maxRange` (DEX/INT gap-closers) | 9–14 | Shadowstep 12, Void Lance 14, Executioner 10, Displace 12, Phase Step 9 |
| Knockback/push distance | 2.5–5 | Titanfall 2.5, Overrun/Colossus Crash/Body Slam 3, Displace 5 |
| `KNOCKBACK_SPEED` | 12 u/s | fixed travel rate for any push |
| `DEPLOY_DEPTH` | 11 | front units deploy at 8.25u from their own edge (`0.75×`) |
| `LEASH_RADIUS` | 12 | **hardcoded, not derived from `FIELD_W`/`FIELD_H` at all** |
| unit speed | `2.4 + DEX/1000 × 3.6` → 2.4–6.0 u/s | swept on the 40x22 field |

Field diagonal today (`hypot(40,22)`) is **45.65**. At 2x linear scale (80×44) it is **91.3**; at
4x (160×88) it is **182.6**. Every value in the table above stays exactly where it is while the
board it operates on grows 2–4x. That is the whole problem, stated once instead of eighteen
times: **distances that mattered on a 45-unit diagonal become rounding errors on a 183-unit one,
and travel time to close them explodes.**

### 1.2 ⚠️ `LEASH_RADIUS` doesn't know the arena is changing size

`LEASH_RADIUS = 12` bounds how far any unit may stand from the fight's centre of mass, and it is
a plain constant in `types.ts` — not derived from `FIELD_W`/`FIELD_H`, not set per-map. Two
readings, both concerning:

- If the ground actually grows 2–4x and `LEASH_RADIUS` does not move with it, the leash becomes a
  ~24-unit cage sitting inside a much bigger board — which, by accident, *is* roughly the bounded-
  ground concept §0 describes, except nobody decided that on purpose and nothing else (deploy
  depth, reach, gap-closers) was built to match a 24-unit fighting circle.
- If `LEASH_RADIUS` is meant to scale with the board (so a 5v5 fight really does range across more
  ground than a 1v1), it needs to be authored per team size / arena, which does not exist today.

⚠️ Per the standing project rule stated in `ENGAGEMENT_DESIGN.md` itself — *"treat inherited
numbers as evidence of what happened, never as evidence that it was intended"* — this is exactly
that situation. Nobody has looked at `LEASH_RADIUS` since it was picked for a 40-wide board, and
it is about to matter a great deal more than it did.

### 1.3 `DEPLOY_DEPTH` — the fight might not start where anyone expects

`DEPLOY_DEPTH = 11` (front units at `0.75×` = 8.25 from their own edge) puts opposing front lines
about **23.5 units apart** on the current 40-wide field. If `FIELD_W` alone quadruples to 160 and
`DEPLOY_DEPTH` does not move, that separation becomes **≈143 units** — nearly 13x the widest reach
in the game (Volley, 11.0) and around 16x a dash's `maxRange`. Every fight would open with a
multi-second dead crossing before a single ability could connect, on top of whatever closing
problems already exist. This is not a marginal tuning question; it is a constant that was never
written to be a fraction of the field and needs to become one (`DEPLOY_DEPTH = FIELD_W × k`) the
moment the ground's width is not fixed.

### 1.4 Reach, line by line

| line | reach | what changes at 4x ground | verdict |
|---|---|---|---|
| **Assassin** (DEX) | 2.4–2.8, gap-closers (blink) 9–14 | tightest native reach in the pool; its *entire counter-play* to a spread ("loose") enemy per `SPATIAL_MODEL.md` §10 is a blink that crosses 26% of today's diagonal (12/45.65) but only **6.6%** of a 4x diagonal (12/182.6) | ⚠️ **gets WORSE at exactly the job it was just given.** §10 names the assassin as "the answer to a loose enemy" on a large board — but a fixed-distance blink is the one thing in the kit that does not get proportionally better at reaching a spread-out target; it gets worse |
| **Volley** (DEX) | 8.4–11.0, the longest in the game | 11.0/45.65 = 24% of the diagonal today, 11.0/182.6 = **6%** at 4x. Combined with kiting being time-bounded per episode but *not* bounded in total distance (`ENGAGEMENT_DESIGN.md` §11.1, ⚠️ already flagged as "worse at size, not better") | more room to run the shuffle-and-refill kite pattern before hitting a board edge or the leash — the exact "diffuse fight" failure mode both design docs are trying to prevent, and it lands hardest on the line built to stand off |
| **Mender** (WIS) | 7.3–8.5, "must out-reach the front line or it cannot heal it" | depends entirely on formation depth, which `SPATIAL_MODEL.md` §10 is about to make a real player choice (loose vs tight). A loose team stretched over more of a larger ground can put its front line further than 8.5 from a backline healer | the stated invariant ("Mender must out-reach the front line") was true on a fixed 4-unit comb spacing; it is not guaranteed once cohesion is a real axis, independent of arena size — **and gets easier to violate as the ground grows** |
| **STR dash gap-closers** | maxRange 7–9 | same shrinkage as Assassin's blinks, and STR is *already* the worst-realized stat on the field (§3) because melee dies before it acts; a gap-closer that stops reliably closing the gap removes the one lever STR has to fix that | compounds an existing, measured problem rather than a new one |
| **AoE** (all stats, `aoeFalloff` judged at 3 targets) | reach is *discounted* 15% by `authorranges.ts` to "pay" for hitting 3 bodies | `aoeFalloff`'s 3-target assumption is a bet on the enemy being clumped. `SPATIAL_MODEL.md` §10 makes "loose" a first-class, board-control-rewarding choice once there is room to do it — and a larger ground makes loose cheaper to hold | AoE's *priced* value (2.7x a single target, per `aoeFalloff(3)`) does not change, but its *realized* value should fall as boards grow, because the precondition (3 bodies in one blast radius) gets rarer. This is a sim question, not a pricing one — see §5 |
| **Root/slow effects** (Rime Bind, Seize, Displace's 1.2s root) | time-based, not distance-based | unaffected by board size directly | ⚠️ **the one category of control that gets relatively STRONGER at scale** — denying movement matters more when movement itself is expensive (bigger board, same speed stat). Worth remembering when re-tuning everything else down |
| **Knockback/push** (Titanfall 2.5, Overrun/Body Slam/Colossus Crash 3, Displace 5) | fixed distance, fixed `KNOCKBACK_SPEED` (12 u/s) | a 3-unit shove is 6.6% of today's diagonal, **1.6%** of a 4x one | positional value of a shove shrinks toward irrelevant; only the CC-adjacent side-effects (interrupting a cast, breaking an engagement) still matter, which argues for pricing push distance separately from push as denial |

### 1.5 Unit speed and the six-tier hierarchy interact badly with distance

`speed = 2.4 + DEX/1000 × 3.6` (2.4–6.0 u/s) is itself an absolute rate, swept and fixed against
the current board. It was **not mentioned as existing at all** in `ENGAGEMENT_DESIGN.md` §1
("per-unit movement speed DOES NOT EXIST. Speed is global with multipliers") — but it plainly is
in `engine.ts:198`, keyed off DEX, dated the same day as that doc.

⚠️ **This is a live disagreement between two same-day documents and the actual code, and it should
be surfaced rather than quietly resolved one way.** `ENGAGEMENT_DESIGN.md` §6 spends four options
weighing where speed should come from (a 7th stat, an existing stat, body type, class basic,
class×body) and flags DEX as "the obvious pick and ⚠️ backwards" — precisely because DEX is the
archer/rogue stat, so deriving speed from it makes the units that most want distance the fastest
at keeping it. **That is exactly what `engine.ts` already does.** Whoever owns the spatial rework
next needs to know this is not a hypothetical to design around; it shipped, on the branch, before
the doc arguing against it was written.

Melee's realized damage problem (§3) is a *time-in-state* problem, not a raw-power one (P6,
`ABILITY_REWORK.md` §6b: melee dies at 1.7x the rate ranged does, and dead units cast nothing).
Every extra second of travel time added by a larger board is a second STR/melee classes are
neither attacking nor being attacked *productively* — they are closing, at a speed the DEX-tiered
archer/rogue kit already out-runs. Scale makes this gap worse, not better, unless closing speed or
minimum-range mechanics (`ENGAGEMENT_DESIGN.md` Families A/B) land first.

---

## 2. `tools/pool.ts` is uncalibrated — concrete thresholds

### 2.1 Why the tool reports 0 flags on a 31x spread

Every check in `tools/pool.ts` is **relative**, and each one is relative to a narrow, local
comparison set:

| check | compares against | why it cannot see a whole-pool 31x spread |
|---|---|---|
| FLOOR | the class free attack (a fixed low bar) | passes trivially for anything above ~7–16 DPS; says nothing about the *top* of the range |
| DOMINATED | same LINE, **equal-or-lower learnLevel** | Ember (lv40) and World Ender (lv920) are never compared — they aren't in the same line, and even within a line the check only looks at moves at or below the candidate's own level |
| OVERBUDGET / HOT-FOR-LEVEL | cohort within `LEVEL_BAND = ±200` levels | a lv40 move's cohort tops out around lv240; a lv920 capstone is never in the same comparison. The ±200 window is *why* two ends of an 880-level ladder can each look locally reasonable while being 10-30x apart |
| PROGRESSION | previous-best-in-line, checked for **non-decrease only** (`< prev × 0.9` is the fail condition) | this asks "does it go up", never "does it go up by a *sane amount*". A line can pass PROGRESSION by going up 12x and the check has nothing to say about it |

**Every one of these is deliberately local, for good documented reasons** (a global mean would
flag all of WIS as broken and all of STR as overtuned — the file says so, correctly). But the
consequence is that **no check in the tool currently answers "is the overall dynamic range of
this stat's pool the size the design intended"** — and `ABILITY_REWORK.md` §2 states that
intent explicitly: *"Progression ≈ 2.5× first move → capstone, delivered through stat scaling."*

### 2.2 Measured: individual lines run 3x–12.5x, not ~2.5x

Hand-computed straight from `totalValue = damagePerSec × (1 + keywordUplift)`, starter vs
capstone, same line, single-target where both ends are single-target:

| line | starter → capstone | total value | ratio |
|---|---|---|---|
| DEX Assassin | Shadowstep (lv120) → Heartseeker (lv850) | 10.0 → 125.2 | **12.5x** |
| STR Bloodrage | Scrap (lv40) → Titanfall (lv920) | 11.7 → 98.9 | **8.4x** |
| DEX Volley | Sling (lv40) → Deadeye (lv920) | 15.9 → 124.1 | **7.8x** |
| CON Bulwark | Overrun (lv280) → Colossus Crash (lv850) | 11.2 → 35.1 | 3.1x |

⚠️ **The spread is uneven across lines, which matters more than the average.** Bulwark is close
to on-target; Assassin overshoots the stated design intent by very nearly 5x. A single global
correction (e.g. "cut every capstone 20%") would over-correct Bulwark and barely touch Assassin.
This is exactly the standing balancing principle already in `CLAUDE.md` — one value at a time,
measured, not a sweeping pass — and it argues for line-by-line remediation once a check exists
that can see the problem at all.

⚠️ **Why Assassin specifically is worth flagging first**: it is the line `SPATIAL_MODEL.md` §10
is about to lean on hardest ("the assassin wants the enemy loose, and is the answer to a loose
enemy"). A line that already runs 5x hotter than its own design target, layered under a mechanic
(isolating a loose backline target) that is about to become more reliable, is the least safe place
in the pool to be quietly over-provisioned.

### 2.3 Proposed thresholds, derived from the tool's own distribution

Two additions, both self-referential (no hand-picked absolute number, so they don't repeat the
mistake the cross-stat `STAT_TIER` table was built to avoid):

**A. A per-line progression-ratio bound.** For each (line × AoE-side) cohort — the same split
`PROGRESSION` already uses — compute `max(totalValue) / min(totalValue)` among single-target,
no-major-rider moves and flag if it falls outside **[1.8x, 4.0x]** (a band centred on the ≈2.5x
target with margin either side for legitimate riders). This is one new report section, reusing
data the tool already computes; it would have caught Assassin (12.5x) and Bloodrage (8.4x)
immediately, and left Bulwark (3.1x) alone.

**B. An IQR outlier fence, replacing the fixed 1.6x/1.7x multipliers.** `OVERBUDGET` (1.6x) and
`HOT-FOR-LEVEL` (1.7x) are hand-picked constants tuned, by the file's own comments, to avoid an
early false-positive storm — not derived from the pool's shape. The tool already prints
`p25`/`med`/`p75` per stat (`--md` output). Use them: flag a move if
`totalValue > p75 + 3 × (p75 − p25)`, the standard Tukey outlier fence. This is scale-invariant
per stat (works identically for WIS's low absolute numbers and STR's high ones) and, unlike a
fixed multiple of the median, tightens or loosens automatically with how spread-out the stat's
own cohort actually is.

**What this would NOT do**: neither addition second-guesses `aoeFalloff`, `EFFECT_VALUE`, or
`STATUS_VALUE` — those are the pool's priced *opinions*, arguable on their own terms (the file
says so). Both additions only ask "does the pool's own measured output match the pool's own
stated progression target," which is a gap in the harness, not a re-litigation of its pricing
model.

---

## 3. The six stat tiers at size

`STR 42.6 / DEX 38.2 / INT 35.2 / CON 28.0 / CHA 26.8 / WIS 22.8` (`CLAUDE.md`, `pool.ts`'s
`STAT_TIER`) is a **per-cast paper DPS budget** — what a move is worth *if cast*. It says nothing
about how often each stat's kit actually gets to cast, and `ABILITY_REWORK.md` §6b already
measured that the two diverge badly:

> *Wizard 323 dmg/fight, Sage 307 ... Warrior 57, Captain 9.* STR has the **highest** paper tier
> and one of the **lowest** realized outputs, because melee dies at 1.7x the rate ranged does
> (44% of time-in-state dead vs 26%), and a dead unit casts nothing.

That finding was made on the *current* 40x22 board. Two things about it get worse, not better, as
the board grows:

1. **Time-to-close increases with board size, at a fixed speed stat.** Every extra second spent
   approaching is a second not spent attacking *or* being attacked productively — but it is a
   second melee spends *exposed while closing*, which is exactly the state the 44%-dead figure was
   measured in. A bigger board lengthens the exposure window before melee ever reaches its own
   reach band.
2. **The realization gap is structural, not incidental** — casters "free-cast from range" (the
   same doc's words) precisely because their reach already exceeds the threat radius around them.
   A bigger board does not change that relationship; it just gives ranged/support kits more room
   to exploit it (§1.4, Volley) while giving melee more ground to cross to deny it.

⚠️ **The tier table's ordering (STR highest, WIS lowest) was authored as a paper-value hierarchy
and was already not the realized hierarchy before any size change.** It should not be read as a
target to re-hit by inflating STR's numbers — `ABILITY_REWORK.md` says this explicitly ("resist
the urge to fix it by inflating STR power") and P6's flanking fix (Warrior 57→82 dmg/fight) came
from survivability and formation work, not damage. The same logic applies here, more so: a larger
board is a survivability/closing problem first, and no amount of retuning `STAT_TIER`'s numbers
touches the actual bottleneck (time spent alive and in reach).

**What to measure before touching any stat's numbers**: re-run the time-in-state split (dead /
move / cast / idle, by reach class) at 2x and 4x board size. If melee's dead-time share rises
further, that is the size change making the existing, already-diagnosed problem worse — exactly
the kind of result `ENGAGEMENT_DESIGN.md` §3 already asks for (scale the field, run `sweep40`,
see if fights get longer/more diffuse) but applied to the class-diverse sweep (`dsweep.ts`) rather
than the non-representative mammal-only one, per the ⚠️ already on record in `ABILITY_REWORK.md`.

---

## 4. Reach as a balance axis — is it priced right for size?

**Short answer: it is priced right for a field that stops existing under the stated direction.**

`tools/authorranges.ts`'s own header comment states the calibration explicitly: *"The reach each
LINE fights at, in world units, **on a field 34–64 wide**."* That is a real, if implicit,
acknowledgment that the tool's author already expected some variance in field size — but 34–64 is
**1.6x**, not the 2–4x this review was asked to check. Every one of the 141 `range` values, the
`HARD` clamp `[2.4, 11.0]`, and the four `CHANNEL_RANGE` bands were seeded and hand-checked inside
that 1.6x envelope.

If the ground genuinely reaches 2–4x today's width (§0), **reach is not "wrong" in the sense of
being mispriced relative to other moves — it is calibrated to a field that will no longer exist.**
The fix is not "raise every range value"; scaling every line's reach up in lockstep with the board
would reproduce the exact same relative geometry (Assassin still short, Volley still long, both
still tight melee's problem), so nothing about the pool's *internal* balance would need to move —
only the absolute numbers, and only if the ground itself is what's growing. Concretely:

- **If the ground scales**: re-run `tools/authorranges.ts` with `LINE_RANGE` base values and
  `HARD` bounds scaled by the same factor the ground grows by, and re-author. This is close to
  free (`authorranges.ts` already supports `--force` re-authoring) but it is not optional — every
  authored `range` is stale the moment `FIELD_W`/`FIELD_H` changes structurally.
- **If only the venue scales**: reach needs no change at all, and this section (along with most
  of §1) can be filed as "checked, not applicable."

⚠️ **Reach is currently under-defended as a balance axis in one specific way regardless of which
answer §0 gets**: `authorranges.ts` treats reach as something that trades against *power* (±12%,
"power buys itself with reach") and against *target count* (AoE −15%, "AoE pays in reach"), but
**never against board size**, because board size has always been fixed. Once it is not fixed, reach
needs a third dependent variable it does not have a slot for today.

---

## 5. Prioritised changes, with reasoning and what to measure

Ordered so a blocking decision comes first, then structural constants, then pool remediation —
consistent with "one value at a time, sim, read, adjust."

| # | change | reasoning | what to measure to confirm |
|---|---|---|---|
| 1 | **Resolve §0: does the GROUND scale, or only the VENUE?** | Everything below is contingent on this. It is a design decision, not a tuning pass — get it in writing in `SPATIAL_MODEL.md` or `ENGAGEMENT_DESIGN.md` before any constant moves | N/A — this is the decision, not a measurement |
| 2 | **Author `DEPLOY_DEPTH` and `LEASH_RADIUS` as fractions of `FIELD_W`/`FIELD_H` (or per-composition), not fixed constants** | §1.2–1.3: both are currently blind to arena size; one silently produces a tiny cage inside a big board, the other silently produces a 143-unit dead crossing before the fight can start | run `sweep40` at 2x/4x with these left fixed vs made proportional; compare opening-contact time and % of fights that reach sudden death |
| 3 | **If the ground scales: re-run `tools/authorranges.ts` with scaled `LINE_RANGE`/`HARD`, and scale dash/blink `maxRange` and knockback push distances by the same factor** | §1.1, §1.4: every spatial constant in the pool assumes ~40-wide; none of them scale on their own | re-check reach-as-%-of-diagonal per line before/after; target restoring each line's current ratio (e.g. Volley ≈24% of diagonal) rather than an absolute number |
| 4 | **Add the two `pool.ts` checks from §2.3** (per-line progression-ratio bound, IQR fence) | The tool currently cannot see a 31x pool-wide spread or a 12.5x single-line spread; both are real per the hand-computed spot checks in §2.2 | run `--md` output before/after adding the checks; confirm Assassin (12.5x) and Bloodrage (8.4x) now flag and Bulwark (3.1x) does not |
| 5 | **Re-measure time-in-state (dead/move/cast/idle by reach class) at 2x/4x ground size, on `dsweep.ts` (class-diverse), never the mammal-only sweep** | §3: the STR/melee realization gap is a closing-time problem that a bigger board can only widen; confirming this before touching any stat's numbers avoids repeating the "inflate STR power" mistake `ABILITY_REWORK.md` already warns against | compare melee's dead-time share at 1x/2x/4x; if it rises, the size change is the cause and the fix is closing speed / minimum range (`ENGAGEMENT_DESIGN.md` Families A/B), not damage |
| 6 | **Resolve the DEX-speed contradiction between `engine.ts:198` and `ENGAGEMENT_DESIGN.md` §6** before building anything further on top of either | §1.5: one same-day doc argues DEX-derived speed is backwards, the code already ships it. Whoever picks up the spatial rework needs one answer, not two live ones | N/A — a decision, surfaced so it isn't accidentally load-bearing by the time someone reads the code instead of the doc |
| 7 | **Once cohesion (`SPATIAL_MODEL.md` §10) exists, re-measure `aoeFalloff`'s realized value against actual formation choices, not just the priced 3-target assumption** | §1.4: a bigger board makes "loose" formation cheaper to hold, which should make AoE's *priced* 2.7x-at-3-targets value land less often in practice than it does today | once cohesion ships: measure real target-count-per-AoE-cast distribution at 1x/2x/4x ground size; compare to the 3-target assumption `aoeFalloff` is judged against |

⚠️ **Everything in this list is a "what to check," not a "what to change."** No move's `power`,
`mana`, `cooldown` or `range` should move on the strength of this document alone — every row
above ends in a measurement, per the standing rule that the sim is the arbiter and balance moves
one value at a time.
