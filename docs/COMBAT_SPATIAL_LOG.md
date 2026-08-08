# The combat & spatial rebuild — a running log

**Started 2026-08-05.** A chronological record of what was changed, what was measured, and what
was found — kept because this work produced more findings than code, and the findings are the
part worth keeping. Newest section at the bottom.

⚠️ **THIS IS A LOG, NOT A SPEC.** Where it disagrees with `spatial.gd`, `arena_layout.gd` or
`monster_tree.gd`, the code is right and this is stale. Its job is to say *why* something is the
way it is, and what was already tried.

**Companion documents**, each of which owns a topic this log only references:
`WOW_ARENA_REFERENCE.md` (the 16 maps) · `ARENA_ETHOS_REVIEW.md` (our ethos vs theirs) ·
`ARENA_REVIEW_PER_MAP.md` (each map, with verdicts) · `ARENA_SCALE_COMPARISON.md` (ratios) ·
`ROADMAP_TO_SHIP.md` (the plan) · `WOW_ARENA_COMBAT.md` (combat mechanics — in progress).

---

## 1. Art: the models got into the game

The low-poly spike, the animation set, and then the pivot to CC0 assets.

| finding | detail |
|---|---|
| Clips were all misnamed | All ten. `kongrath_dead.glb` contained a BLOCK animation. Cause: a download loop moved each file before fetching the next. Fixed by reading each GLB's own internal clip name. ⚠️ Caught only because a keyframe count looked wrong for its name |
| Skeleton "morphing" | Limb lengths changed up to **16.22%** between clips. NOT retargeting — the skeletons were identical. It was track COVERAGE: each clip carried position tracks for a different subset of bones, and Godot leaves an untracked property wherever the last clip left it. Fixed by allowing only the ROOT to translate |
| `get_aabb()` lies for skinned meshes | Wrong by **104×**. It reports bind-pose bounds in mesh space; a skinned vertex is placed by `bone_pose * bind_pose`. Scaling by it produced a creature ~150× too large that filled the frame as a white wall |
| Scale must go on `self` | Meshy clips animate the imported root's transform, so a scale written there is overwritten on the first frame of playback. The probe passed because it measured before playback |
| ⚠️ **The pivot** | 45 CC0 rigged+animated creatures, 15 MB total, complete clip sets, no attribution required — against ~62 credits per creature and a bind pose so poor every animation deformed. The studio owner's instinct to look for free assets was correct and I had been over-investing in generation |

⚠️ **Transferable lesson, and it recurred all week:** a headless probe reporting PASS proves the
wiring, never the look. Two of three art bugs shipped with a green probe.

---

## 2. The arena: eight scale bugs, all the same bug

Real geometry replaced billboarded sprites, so the body went from a 1.8-unit diameter to 4.4.
**Every world distance written as a bare number was silently wrong**, and they were found one at a
time as symptoms surfaced:

| # | constant | symptom |
|---|---|---|
| 1 | `BODY_RADIUS` 0.9 | the "huddle" — sim kept bodies 1.8 apart while the renderer drew them inside each other |
| 2 | `REACH_SCALE` | scaling the ground without it made every ability proportionally shorter |
| 3 | `SPEED_MIN/MAX` | units proportionally sluggish on a bigger board |
| 4 | `DEPLOY_SEPARATION` | teams 33 units apart on a 352-unit board — 9% of the width |
| 5 | deploy band `team_size × 6` | five units in 30 units of a 193-deep field |
| 6 | `WING_OFFSET` 14 | a 14-unit flank arc on a 352-unit board is a sidestep |
| 7 | `HOLD_SLACK` | same |
| 8 | obstacle footprints | eight of nine kinds became **narrower than a monster** — a "blocking" pillar at 0.64 body diameters |

⚠️ **The lesson is the pattern, not the eight fixes.** `GEOMETRY_SCALE` should have been the only
place a world distance is written. It is now the constant everything else derives from — anything
added in world units must carry it.

**Board:** 160×88 → **352×194**, deploy separation 33 → **303.6** (ends of the arena, on the
studio owner's call), closing time 12s → 26s.

---

## 3. Movement, targeting and reactions

| built | measured |
|---|---|
| Role-based defaults — long reach holds, fastest short-reach flanks, rest push | all "closing" → 4 flanking / 3 holding / 3 pushing |
| Peel, fall back, disengage, emergency bail-out, collapse | peeling 171 ticks, falling back 179, bailing out 95 |
| Arena footprint used | 31% → **63%** |

⚠️ **THE ENGAGEMENT GATE RAN BEFORE THE BRANCH, SO NOTHING COULD FLANK.** The gate closes toward
the target's own position, so a unit whose intent was `wings` walked straight at the enemy until
already inside reach, then began its arc. Every positional intent collapsed into "advance in a
line".

⚠️ **AND FIXING IT BROKE SOMETHING ELSE, WHICH THE STUDIO OWNER CAUGHT BY WATCHING.** Making the
gate a backstop gated on `action != "move"` exempted `hold` — which returns action "move" toward
its own home point. Long-reach kits therefore held their DEPLOY position 303 units away with a
70–97 unit reach: **Corvaan and Larkessa never moved for an entire fight.** The gate now fires
when the branch is *not closing the distance*, which is the property that actually matters.

⚠️ **Two reaction systems were BUILT AND UNREACHABLE.** `fallback` and `disengage` were fully
implemented, but `whenHurt` defaulted to the literal `"fightOn"` — so no monster in any fight had
ever withdrawn from anything. That was the **fourth** time the bug was "the default makes the
feature unreachable" rather than "the feature is missing".

⚠️ **And an honesty bug they exposed:** both withdrawal branches hard-coded *"your order:"* into
their reason text. The first run printed *"Balaenix fell back (your order: When hurt → Fall back)"*
for an order no player had given. `AUTOBATTLER_DESIGN.md` sets the bar as *"can the player tell
why it did that, **and was it their own order?**"* — attribution IS the feature.

---

## 4. Arenas: from scatter to composition

The WoW blueprint research (see companion docs) produced one governing finding: **sixteen shipped
arenas reduce to four compositions plus art**, and every one is describable in a sentence. Ours was
describable only as "twenty-four things".

**Built:** `four_pillar` (open centre — Nagrand family) and `central_mass` (occupied centre —
Lordaeron family). Authored in normalised coordinates, mirrored about the **spawn axis** rather
than rotated 180° (mirror admits odd counts like the Robodrome triad; rotation forbids them).

⚠️ **Pieces are sized in BODIES, not copied in proportion.** In WoW, collision is negligible so a
whole team stacks behind one pillar — a pillar is team-sized cover. Ours are solid by design, so a
5-monster line needs 22 units of frontage and a Nagrand-proportioned pillar would shelter one
monster while four stand in the open. `MAJOR_MIN_BODIES` is that rule written down; raised 5 → 9
when the studio owner said the objects were too small.

⚠️ **The grade mix was an accident of table length.** Adding a tenth kind silently halved
LOS-blocking cover (8 pieces → 4, blocked lines 17.8% → 1.4%) because the generator picked
uniformly from `KIND_TABLE`. It now draws a grade first, then a kind within it.

---

## 5. Cover: the mechanic that did not work, and why

The longest thread of the week, and the most instructive.

**Measured with a chance baseline** — teleport each unit to a random legal spot, same threats,
same moment, same board, and compare:

| stage | four_pillar | central_mass |
|---|---|---|
| binary occlusion (as shipped) | **0.22×** avoiding | 0.74× avoiding |
| cover as a debuff | 0.24× | 0.89× |
| obsolete override retired | 0.33× | 0.94× |
| asymmetries built | **0.57×** (ranged 39.7%) | **0.98×** (ranged 42.1%) |

⚠️ **THE UNITS WERE NOT FAILING TO USE COVER — THEY WERE CORRECTLY REFUSING A BAD DEAL.**
`SPATIAL_COMBAT_DESIGN.md` §2 decided cover should be *"an accuracy debuff for any attacker"* and
recorded that the engine did binary occlusion instead: *"a unit behind a rock is not HARDER to hit;
it is UNTARGETABLE."* So standing in cover meant **you could not attack**. Ranged kits avoided it
hardest because they had the most shooting to lose.

⚠️ **AND HALF-FIXING IT WAS WORSE THAN NOT FIXING IT.** With shots allowed through cover but
`_clear_line_override` still fleeing it, units optimised against a rule that had just been deleted
— four_pillar ranged sat at **zero shelter across 522 threat-instances** against 34% by chance.

**The three asymmetries** (chosen by the studio owner from four options):
1. **Outnumbered** — 3 enemies shooting you while you shoot one makes a symmetric penalty a 3:1 win
2. **Support** — a kit whose moves target allies pays nothing for cover; counted from the moveset,
   not a class name
3. **`shelter` order** — reachable as a default when cover pays, and as an explicit order

⚠️ **CAST INTERRUPTION DEADLOCKED THE GAME.** Interrupting any blocked cast let both sides hide
behind the same mass and break each other's casts forever — `central_mass` hit MAX_DURATION at
**1801 frames with 881 interrupts and nobody dead**. Fixed by requiring the line to have been
CLEAR WHEN THE CAST BEGAN, which rewards moving into cover during a windup and never punishes
choosing to fight from cover. That is also the actual WoW behaviour.

### ⚠️ 5.1 The finding that outranks all of the above

Interruption now fires **zero times**, and the reason is a gap in the game rather than a bug in
the mechanic:

> **Every move in the pool has a cast time, but the longest is 0.6 SECONDS against a 0.1s tick.**
> A unit covers ~6.6 units during the longest cast in the game, against cover pieces ~40 units
> wide. **There is no window to duck into.**

So the game has **no telegraphed heavy abilities**, and nothing that depends on "during a cast"
can work — not interruption, not counterplay, not a readable burst window. `CLAUDE.md` removed
ultimates and nothing replaced the telegraph they provided.

⚠️ **Deliberately not tuned into looking like it works.** Shortening cover or stretching every
cast to force a non-zero number would have hidden the finding.

---

## 6. Facing

The studio owner's proposal, built: front / side / rear arcs off the `facing` vector that had been
in the frame stream since the spatial layer was built and that **nothing had ever read**. Rear
costs +15% damage; side and rear both carry the accuracy bonus.

It **replaces** the old flanking rather than stacking on it — `is_flanking()` meant "outnumbering
an unsupported target", which awarded the bonus to a unit standing directly in FRONT of its victim.

⚠️ **The design claim held under measurement.** A unit faces what it moves toward, and it moves
toward its own target — so you can only be hit from behind by someone who is **not** your target:

| | front | side | rear | rear hits by a THIRD party |
|---|---|---|---|---|
| four_pillar | 66% | 13% | 21% | **35 of 45** |
| central_mass | 59% | 17% | 24% | **33 of 44** |

**~77% of backstabs need someone else holding the victim's attention.** Backstabbing is inherently
a team mechanic, which makes peel and guard matter and gives `wings` a payoff.

⚠️ **+15% is a big lever.** Crit is 8% at 1.5× — about 4% expected damage across all hits. A flat
+15% from behind is ~3.75× the entire crit system. Acceptable as a starting value only because the
baseline is being remade from scratch.

⚠️ Applied **outside** `damage.gd`: that file is under an exact-equality port contract (62 cases),
and adding a term inside would break all of them and claim the TypeScript does something it does
not.

---

## 7. Standing decisions taken during this work

| decision | who |
|---|---|
| Deployment zones at either END of the arena | studio owner |
| Obstacles bigger; texturing deferred | studio owner |
| Baselines to be remade wholesale — **after** mechanics and abilities, not before | studio owner |
| Playtest deferred until the build is further along | studio owner |
| **The care loop (innates/tameness/happiness) WILL be added to the game** | studio owner |
| Facing arcs with a rear damage bonus | studio owner |
| Cover asymmetries: outnumbered + support + order. **Not** asymmetric-by-grade | studio owner |
| Elevation stays banned | `ARENA_DESIGN.md`, unchallenged |
| Dynamic/moving cover stays out — ⚠️ WoW shipped it twice and killed it twice | evidence-based |

---

## 8. Open, and what each is waiting on

- **Windup tier** — the gap in §5.1. Options being put to the studio owner.
- **Care loop wiring** — 130 authored innates, `tameness`, `happinessMultiplier` still have **zero
  references** in the field engine.
- **Two more layouts** — `triad` and `lanes` are designed; the placement code is done.
- **45 of 65 species** have no model mapping.
- **Cover-seeking above 1.0×** on `four_pillar` — though an open-centre composition arguably
  *should* fight in the open, so this may be correct rather than missing.
- **Re-baseline** — deferred by decision, and the pile is large.

## Loadout reachability — the fifth built-but-unreachable feature (2026-08-06)

⚠️ **THE INTERRUPT MECHANIC WAS NEVER BROKEN. NOTHING COULD DRAFT A MOVE TO INTERRUPT WITH.**

`assign_moveset()` drafted, per class line, the **top 2 moves by `learnLevel`**. `learnLevel`
is a POWER PROXY, and **control moves are deliberately low-power** — so the picker ranked every
line by the one axis control was authored to lose on.

Measured before the fix:

| stat level | moves per kit | carries hard control | `type: control` drafted |
|---|---|---|---|
| starter (avg 32–65) | **1.3** of 6 | 0/20 | 0 |
| maxed (all stats 1100) | 5.7 | 12/20 | **0 of 114** |

Two independent gates, both real:

1. **The floor.** The pool's lowest `learnLevel` is 40; a fresh monster averages ~32. A starter
   qualified for NOTHING in most lines, so **the entire early game ran on basic attacks.**
2. **The ranking.** Top-2-by-`learnLevel` kept low-power utility unreachable *even at the
   Tamers Apex ceiling* — 0 control moves across 114 drafted slots.

**The fix:** draft by ROLE. Each line contributes its strongest move (a kit needs teeth), and
utility is bucketed separately with **two of six slots reserved** for it. Plus a floor: a line
with nothing learnable still offers its cheapest move — deliberately not a general relaxation,
so the kit still grows with the monster.

| | before | after |
|---|---|---|
| starter moves per kit | 1.3 | **3.3** |
| starter carries hard control | 0/20 | **5/20** |
| maxed `type: control` drafted | 0 of 114 | **6** |
| maxed carries control/debuff | 6/20 | **19/20** |
| maxed carries hard control | 12/20 | **8/20** ⚠️ |

⚠️ **THE LAST ROW IS A REAL REGRESSION, RECORDED HONESTLY.** Reserved utility slots displace
high-power damage moves that carried stuns as riders. The trade is still right — hard control at
the level fights actually run at went 0 → 5 — but it is a cost, not a free win.

**Interrupts now fire in live fights**, and each layout produced a different path:
`four_pillar` a control interrupt (silence cut a cast), `central_mass` a cover interrupt (lost
LOS mid-cast). Contracts 219/219 exact.

⚠️ **THIS IS THE FIFTH FEATURE FOUND BUILT-AND-UNREACHABLE** (after flanking, both withdrawal
modes, and cover-seeking). **"The default makes the feature unreachable" is this codebase's most
common failure shape** — and it is the same failure `lines.ts` was created to fix, reproduced in
the port. Lines fixed WHERE a kit draws from; they never fixed the ranking INSIDE a line.
**Before building a mechanic, measure whether anything can reach it.**

### Open, and NOT changed silently — a balance decision for the user

Control's `learnLevel` spread is **240 / 400 / 820** (min/median/max) against damage's **40 /
380 / 920**. Control's *minimum* is six times damage's, so crowd control is progression-gated
out of every early league by data, not by the picker. That may be deliberate pacing. It is a
balance call and is left as authored.

## The wobble, and the speed (2026-08-06)

User's report: *"the monsters look like they wobble around the enemies"* and *"can we increase
the speed a little?"*. `_probe_wobble.gd` puts numbers on the first — mean heading change per
0.1s tick, share of ticks that REVERSE (>90°), and directness (net displacement ÷ distance
walked).

| | before | after |
|---|---|---|
| heading change/tick — `four_pillar` | 9.2° | **6.7°** |
| heading change/tick — `central_mass` | 14.0° | **8.2°** |
| reversals >90° — `four_pillar` | 4.6% | **0.4%** |
| reversals >90° — `central_mass` | 7.4% | **1.0%** |
| mean speed | 11.8 / 12.2 u/s | **14.7 / 13.9 u/s** |

14° per tick is **140°/second of turning**, with a >90° flip roughly every 1.4s, and directness
as low as 0.57 — nearly half the distance walked was going nowhere. ⚠️ **None of it was the AI.**
Three mechanical causes:

1. **No momentum.** Heading was whatever the latest decision pointed at, applied whole in one
   tick. Now STEERED at ≤300°/s (`Spatial.steer`). Deliberately generous: normal steering is
   untouched, only snaps are filtered.
2. **Micro-shuffle.** No arrival deadzone — a unit whose goal sat 0.3 units away stepped 0.3,
   then stepped back when the goal drifted. Sub-body-radius stepping is invisible as travel and
   unmistakable as jitter. `ARRIVE_EPS = BODY_RADIUS * 0.5`.
3. **Separation ping-pong.** `_separate()` applied the FULL overlap correction to both bodies
   every tick, so a crowded pair over-corrected, re-overlapped and pushed back. `SEPARATION_DAMP
   = 0.5` converges just as surely without overshoot.

**Speed was raised via `TARGET_CLOSE_SECONDS` 26.0 → 21.0, not via a multiplier on
`SPEED_MIN`/`SPEED_MAX`.** Every unit speed derives from that constant, so the DEX ladder, the
closing bonus and the backpedal all scale together. A bolt-on multiplier would have decoupled
speed from the board — the exact failure the board-derived constants were introduced to end.

⚠️ **THE FIRST ATTEMPT MADE IT WORSE — 9.2° → 15.7° and 14.0° → 27.2%.** The turn limit shipped
with an anti-orbiting escape hatch: a unit that had not moved on the PREVIOUS tick could turn
freely. But the new arrival deadzone made not-moving common, so nearly every unit qualified for
a snap nearly every tick. **An escape hatch keyed on a condition that another part of the same
change made frequent.** Fixed by requiring a SUSTAINED stop (5 ticks / 0.5s). Worth remembering
as a general shape, not just this bug.

Verified after: contracts 219/219 exact, fights resolve (260 / 556 frames), nav routing 100%,
no orbiting. ⚠️ Interrupt counts moved around on the fixed seed (four_pillar 1 → 0, central_mass
1 → 2) — expected, since changing movement changes who is where when, but it means the interrupt
probe is a single-seed spot check and NOT a rate. Do not read it as one.

### Second speed raise — and the turn cap had to become a turn RADIUS (2026-08-06)

`TARGET_CLOSE_SECONDS` 21.0 → 17.0. The first attempt kept the fixed 300°/s turn cap and **the
predicted orbiting failure arrived immediately**:

| | 21s, fixed cap | 17s, fixed cap | 17s, radius-derived |
|---|---|---|---|
| mean speed | 14.7 / 13.9 | 17.6 / 16.6 | **16.8 / 16.2** |
| heading change/tick | 6.7° / 8.2° | 10.9° / 11.0° | **8.3° / 10.5°** |
| reversals >90° | 0.4% / 1.0% | 0.4% / 2.2% | **1.0% / 1.9%** |
| `central_mass` frames | 556 | **1167** | **495** |

⚠️ **A FIXED ANGULAR RATE MEANS "THE FASTER YOU GO, THE WIDER YOU MUST ARC"** — turning circle is
speed ÷ angular rate. At 17 u/s units could no longer turn tightly enough to reach their goals
and circled them instead, more than doubling `central_mass` fight length. The cap is now derived
from `TURN_RADIUS = BODY_RADIUS * 1.4` (ω = v ÷ r), so the turning circle is a constant of the
BODY and survives any future speed change. Board-derived, like every other spatial constant.

⚠️ **AND THE ESCAPE-HATCH MISTAKE HAPPENED A SECOND TIME IN THE SAME CHANGE.** A goal inside the
turning circle genuinely cannot be arced onto, so the first guard was "within 2r, turn freely" —
a 1.1–6.2 unit band that units sit in constantly. Reversals went 0.4%/1.0% → 2.3%/4.5%. Replaced
with a SMOOTH relaxation (`cap *= max(1, TURN_RADIUS / goal_dist)`).

**The general lesson, now paid for twice in one session: an escape hatch keyed on a condition
that is common — or that another part of the same change MAKES common — silently becomes the
default path and undoes the fix it was guarding.** Both times the probe caught it and neither
would have been visible by reading the diff.

Net across both raises: speed **11.8/12.2 → 16.8/16.2 u/s (+40%)**, reversals **4.6%/7.4% →
1.0%/1.9%**, fights resolve in 337/495 frames. ⚠️ Directness is 0.62/0.58 against 0.78/0.57
originally — bounded turning means arcs, not straight lines. Accepted deliberately: arcs are what
momentum LOOKS like, and the reversal count is the number that tracks the user's complaint.
Contracts 219/219 exact; nav routing 100%.

## Facing is not travel — backpedalling and sidestepping (2026-08-06)

User: *"how many directions can our monsters move in? when they move, they look like they have to
turn their whole body to move in that direction. can we allow backpedalling and side stepping"*

**Movement was already continuous** — positions are `Vector2`, so any angle, never 4 or 8
directions. ⚠️ **The problem was that FACING WAS WELDED TO TRAVEL**: `_move_phase` assigned
`st["facing"] = dir` from the movement vector, so a body physically rotated to point wherever it
walked.

⚠️ **AND THE SIM ALREADY ASSUMED OTHERWISE.** `BACKPEDAL_MULT` (0.60) has always slowed units
moving while not advancing, and the renderer has always carried a `retreat` state with its own
clip slot. The model was right; one assignment was welding the two together. **This is the sixth
time a feature turned out to be built and unreachable rather than missing.**

Facing now steers toward the current target within `FACE_TARGET_DIST` (88 units — beyond that a
unit is marching, not fighting, and facing its travel is correct), bounded by the same `steer()`
so heads swing rather than snap. Travel direction is published separately as `moveDir` on every
unit frame; the rig plays the walk clip in REVERSE when travel opposes facing.

Measured share of moving ticks:

| | forward | sidestep | backpedal |
|---|---|---|---|
| `four_pillar` (open centre) | 90.2% | 4.4% | 5.4% |
| `central_mass` (occupied centre) | 58.5% | 5.5% | **36.1%** |

The split is the layouts doing their job: an occupied centre gives units something to reposition
around, so they spend a third of their movement backing off rather than marching.

⚠️ **THIS CHANGES A LIVE MECHANIC AND THE CHANGE IS INTENDED, NOT INCIDENTAL.** `facing_arc()`
grants +15% rear damage and a flanking accuracy bonus on the sides. A unit that keeps its front
to its target while withdrawing no longer hands an assassin a free back — **turning to run is now
what exposes you**, which is the correct reading and the one WoW arena play is built on. It does
make the rear bonus harder to land than it was yesterday. That is a balance consequence to watch
when the re-baseline happens, not a silent side effect.

⚠️ **THERE ARE NO STRAFE CLIPS IN THE PACKS.** A pure sidestep plays the forward walk while the
body faces its target — the feet are wrong. That is the compromise every game without strafe
animation makes and it reads far better than spinning a whole body to travel sideways, but the
honest fix is authoring real strafe clips, and that is a CONTENT job, not a code one. Recorded so
nobody later reads the sidestep figure as "done".

Also: **a dead unit loses its health bar** (the whole bar row, since the bar and its `%` label are
siblings). An empty red trough over a corpse reads as "still fighting, nearly gone" — the opposite
of what happened — and it competes for attention with the units still alive.

### The sidestep: an upper/lower body split, not new clips (2026-08-06)

There are no strafe clips in the packs, and retargeting external ones onto these bespoke skeletons
is exactly what produced the 16% limb-length morphing earlier in this session. So the legs orient
to TRAVEL — the walk clip is then honest about where the feet are going — and the torso
counter-rotates back toward the TARGET. Standard trick for strafing without strafe animation.

⚠️ **IT ONLY MAKES SENSE ON A LEGGED RIG, AND MOST OF THE ROSTER IS NOT ONE.** Measured across all
45 pack models:

| bones | models | what they are |
|---|---|---|
| 4–13 | **28** | blobs, birds, wing-only rigs — no legs to cross; facing the target is already correct |
| 38–58 | **17** | proper legged rigs — the only ones a strafe means anything for |

`_has_legs` gates the whole thing. Do not "fix" it by applying the twist everywhere.

Verified (`_probe_twist.gd`), body rotated 53° toward travel:

| model | legs | modifier | spine | body yaw | torso NET angle | twist driven |
|---|---|---|---|---|---|---|
| dino | ✓ | ✓ | Torso | +52.7° | **0.3°** | −51.0° |
| blue_demon | ✓ | ✓ | Torso | +53.0° | **0.9°** | −51.5° |
| cat / birb / dragon | ✗ | ✗ | — | 0° | 0° | 0° |

The torso's net world angle stays at ~0° while the body turns 53° — the chest keeps pointing at
the target. `MAX_TWIST_DEG = 55`, so a full 90° sidestep puts the legs 55° toward travel and
leaves 35° unaccounted; past that the body has to genuinely turn.

Two implementation notes that are load-bearing:

⚠️ **A `SkeletonModifier3D`, NOT a `_process()` write.** Bone poses are overwritten by the
AnimationPlayer every frame, so anything set in `_process` fights the animation and wins only by
accident of node ordering. `_process_modification()` runs after the skeleton is posed.

⚠️ **The twist is applied in SKELETON space about its up axis, never about the bone's own local
axes.** GLTF bone axes vary per exporter and per rig, so local-axis maths works on some packs and
quietly corkscrews others.

⚠️ **AND THE FIRST MEASUREMENT SAID IT WAS BROKEN WHEN IT WASN'T.** The probe read the torso angle
with `basis.get_euler().y` and reported −5° for a 51° twist. A quadruped's spine lies HORIZONTAL,
which is precisely where euler decomposition gimbals. Measuring a projected axis instead gave the
right answer. **Suspect the instrument before the code** — the same lesson as the "14× collapse"
and the cover-seeking metric earlier in this rebuild.

Backpedal deliberately does NOT twist: the reversed walk clip already reads correctly with the
body square on to its target, and twisting on top would fight it.

⚠️ **THIS PROVES WIRING, NEVER LOOK.** A rig can twist by exactly the right number of degrees
about a subtly wrong axis and corkscrew. Eyes are the only check that matters here.

## The wall clip — and the two bugs underneath it (2026-08-06)

User WATCHED a monster walk through an obstacle. The review found three bugs, one of them in the
project's own foundations.

**1. Nothing enforced obstacle collision on the final position — structural, not a tuning slip.**
The navmesh only shapes PATH TARGETS; momentum steering arcs off the path (the turn-radius change
made corner-cutting routine) and `_separate()` shoves bodies sideways, and neither result was ever
checked against a wall. Measured: `central_mass` had units inside blocking obstacles on **3.95% of
unit-ticks, up to 15.9 units deep**; the A/B without the fix counted 3,770 penetration ticks
across 20 fights. `_resolve_obstacles()` now runs after separation and the ground clamp on the
position that is actually written: push out of any blocking rect along the axis of least
penetration, two passes, fixed order, no rng. Only "blocking" grade collides — soft/hard cover is
stood IN, that is what it is for. Margin is HALF the body radius: the navmesh already carves at
full radius so honest pathing never hugs walls, and a full-radius margin would make the
`central_mass` gaps narrower than the resolver believes, which is a permanent push-fight.

**2. `make_monster`'s rng fallback was ENTROPY-SEEDED — a determinism-contract violation in the
foundations.** Any caller not passing an rng got a different moveset every process. Found the
expensive way: the "same" probe timed out at 1801 frames in one run and resolved in 435 the next,
and a half-day of seed-to-seed comparisons had quietly been comparing DIFFERENT MONSTERS. The
fallback now seeds from `hash(species_id) + training_level` — same inputs, same monster, every
process. Variety is the caller's job; pass an rng for it. ⚠️ Every earlier single-seed probe
figure in this log (interrupt counts especially) carries this noise.

**3. The epsilon sandwich — the resolver's timeouts were MY OWN DEADZONE from this morning.**
With determinism restored, 2 of 10 `central_mass` fights froze: three survivors at wall corners,
0.0 movement over 20s, all reporting "closing to where it can fight". The resolver parks a body
~1.1 from a wall — inside the navmesh's 2.2 carve — so the path's first waypoint sits clamped
nearby, and a waypoint 1.0–1.1 away is too far to advance past (`WAYPOINT_EPS` 1.0) yet too close
to step toward (`ARRIVE_EPS` 1.1). Frozen, permanently. **The deadzone now applies only to the
FINAL goal: a waypoint is somewhere you pass through, not somewhere you stop.**

After all three, the 10-seed sweep: **0 timeouts, 0 penetration ticks in both layouts**, and mean
frames fell to 242/268 (from 352/702) — the deadzone had been silently braking waypoint traversal
in every fight, not just the frozen ones. Wobble held (reversals 1.9%/1.4%), directness recovered
to 0.80 on `four_pillar`, backpedal/sidestep intact (11–15%/6–8%), nav routing 100%, contracts
219/219 exact.

⚠️ **The general lesson is the compounding one: a fix that parks bodies in a place the pathfinder
considers illegal must be checked against every epsilon that reasons about distance.** And the
probe's first version read obstacle keys that do not exist (`pos`/`w`/`h` for `rect`), reported a
clean 0.00% while testing nothing, and nearly ended the review right there. A probe that cannot
fail is not a probe — force it to fail once before trusting its pass.

## Completing the loop I: deployment is real, and the orders key that never existed (2026-08-06)

Survey for "complete the gameplay loop" found the skeleton FULLY WIRED — new game → market →
feed → train → advance week → tournament → tactics → watched spatial fight per round →
standings → promotion → Tamers Apex `game_won` — but three player decisions never reached the
fight. Two are now fixed; the care loop (feeding/tameness/innates → fight performance, 130
innates with zero field-engine references) is next, by the user's priority call.

**1. `committed.get("orders", {})` — A KEY THAT HAS NEVER EXISTED.** `Tactics.commit` stores
`ordersA`/`ordersB`; `arena_3d._resolve_fight` read `orders`. Every per-monster order the tactics
screen sold — temperament, target priority, positional intent, guard — silently fell to `{}` in
the career path. The player's side did everything right; the consumer dropped it. **The seventh
feature found built-and-unreachable**, and the quietest: the screen worked, the commit worked,
and the fight simply never listened.

**2. A dragged chip is now a real start position.** `deployment_board` placements flow through
`committed.deployA` into each monster's own orders as `deployPos`; `spatial_sim._deploy()`
consumes them. Validated SIM-SIDE, not trusted: clamped into the side's legal `deploy_zone`,
then obstacle-resolved — the sim owns what is legal, so no UI bug or stale save can start a unit
in the enemy zone. `monster_tree.gd` already treats first-tick position as the station, so a
custom start IS a custom station with zero extra plumbing. The board's honesty header and hint
text are updated — they truthfully said placement did nothing; leaving them would have been a lie
in the other direction.

**3. `Spatial.deploy_zone()` is THE one definition.** The board computed its own inline copy of
the legal rectangle — two opinions about where a monster may start, the exact "two opinions about
body size" shape that caused the huddle. Board and sim now share it.

**4. The fight seed derives from the career.** It was the literal `20260804` — every fight in
every cup rolled the same sim rng. Now `hash([week, league_index, cup_round])`: replaying a round
reproduces it exactly; the next round differs.

Proof (`_probe_deploy.gd`): legal drop starts exactly where placed; a drop deep in ENEMY
territory clamps back into our zone; `temperament` reaches `unit_orders`. ⚠️ The probe's first
version compared against frame 0, which is emitted POST-TICK — both units had already walked ~2
units toward the enemy and exact-equality "failed" on motion that was correct. Measure the deploy
state, not the first frame. Instrument-before-code, again.

Battery after: 10-seed sweep 0 timeouts / 0 penetration, loop proof 0 failures, contracts
219/219 exact.

## Completing the loop II: the care loop, 16 spatial innates — and the cosmetic rear bonus (2026-08-06)

**The user's decisions:** care powers the innate (happiness scales potency; low stamina fights
weary); and before wiring the existing 30 fields, GROW the vocabulary with spatial innates the
old engine could not express. All 15 proposed fields approved with two tweaks: **magnitudes
pulled down one notch across the slate**, and **castSteady made chance-based** (50% to shrug off
a control interrupt; LOS breaks always land).

**Authoring (TS-side, one source of truth):** `InnateEffect` gained 16 fields (homeGround split
into DR/Acc). **33 entries whose NAMES were already spatial identities trapped in arithmetic
bodies** — Ambush, Statue Stance, Immovable, Drowsy Aura, Time Dilation, Burrow, Hive Mind... —
were reassigned wholesale. The fields are live on the Godot field engine and dormant on legacy
`battle.ts` BY DESIGN (the reverse of the removed `element`: live on the destination). Three
legacy goldens recaptured with the cause named per protocol; 292/292 TS tests green.

**The Godot side (`innate_fx.gd` + hooks through `spatial_sim.gd`):**
- **Potency** = 0.5 + happiness × 0.05. Additive numbers scale linearly; multipliers scale their
  DISTANCE from 1.0 (naive scaling would turn a 1.15 bonus into a 0.575 catastrophe); replacement
  values (fleetfoot, rearArcDeg, windupMult) LERP from the engine default — low care degrades
  toward vanilla, never below it.
- **Weary** (stamina < 30): −8 acc, ×0.92 speed, emitted per-frame for the renderer.
- **Auras got the radius the TS side left as an open question** — `AURA_RADIUS` = TS
  TEAM_AURA_RADIUS lifted by REACH_SCALE; enemy-slow auras use the OWNER'S REACH (the zoner
  identity). Global-unconditional was explicitly rejected TS-side as position-blind.
- All hooks OUTSIDE the contracted maths: multipliers fold into `resolve_strike`'s own inputs
  or wrap its output — the `facing_mult` pattern. Innate pierce rides the move's fx channel.
- ⚠️ `kbResist` is authored but DORMANT — knockback is not yet implemented spatially. Recorded so
  nobody reads presence as wired. Wire it WITH knockback.

**⚠️ THE BIG FIND: THE REAR-FACING DAMAGE BONUS HAS BEEN COSMETIC SINCE IT SHIPPED.** The care
A/B refused to budge even under an absurd 5× test innate, and the trail led to the HP
subtraction: it reads `out["toHp"]`, while `facing_mult` (and now `imult`) multiplied
`out["dmg"]` — the LOGGED number. The +15% rear bonus changed the float text and never the
health bar. Every post-maths multiplier now rescales `toHp` (ward keeps what it soaked).
**An absurd-magnitude test value is the instrument that catches this class of bug — a plausible
1.15 would have vanished into fight chaos and the wiring would have "worked" forever.**

**Proof (`_probe_care.gd`):** scaling rules exact; **45 fields authored, 45 carried, zero
orphans** (the reachability lesson, applied at authoring time); care A/B — the same fight at
happiness 0 vs 10 diverges (204 vs 243 frames); weary emitted. ⚠️ The A/B's first version
measured only team A's surviving HP — which was zero in both runs, "proving" nothing twice.
Then full battery: 10-seed sweep 0 timeouts / 0 penetration, deploy probe green, contracts
219/219 exact.

**What raising a monster now means in a fight:** its innate at full strength vs half, its
stamina deciding whether it arrives weary, its station (player-placed) arming homeGround, its
happiness rolled into every training week AND every fight. The stable and the arena are finally
one game.

## The full pool audit — picked, cast, and working (2026-08-06)

User: *"check all abilities. tell me which abilities arent picked, and which abilities dont work."*

**Picked: ALL 141.** Across 65 species × 4 training tiers (incl. every stat at the Apex ceiling)
× 8 seeds, every move in the pool appears in at least one kit — the role-based loadout fix closed
the pool completely (it was 4 of 24 control/debuff reachable this morning). And **everything
drafted gets cast**: across 12 full fights, zero moves sat in a kit unused.

**Don't work — three finds, one fixed on the spot:**

1. **`bonusVsStatus` — 10 moves, FIXED.** The sim passed `defHasBonusStatus: false` as a literal,
   so every detonator (Twist the Knife, Bloodletter, Executioner, Fester, Virulence, Mind Crush,
   Cinderburst, Arcane Bomb, Detonate, Siren's Call) shipped without its entire mechanic — a
   combo payoff that never paid. Now armed from `target.has_status(kind)`, and `consume: true`
   is honoured: the detonation SPENDS the status (logged as a `detonate` event). The ninth
   built-but-not-working find.

2. **`spreadStatus` — 5 moves, KNOWN-DELIBERATE, still absent.** Piercing Shot, Plague Shot,
   Sonic Boom, Lullaby, Mass Hysteria author a contagion that has zero consumers. The roadmap
   (tamerengine #4) deliberately deferred it ("sim it alone"). The moves otherwise work; the
   rider is silently missing.

3. **`tauntForce` — 3 moves, NOT PORTED.** Challenge, Taunt, Bulwark's Challenge author a forced-
   target effect with zero consumers in the spatial sim. Mass taunt worked on the legacy engine;
   the spatial AI's targeting has no forced-target concept yet (the same gap the roadmap's
   "tauntForce targeting design" entry names). Needs an AI-side design, not a one-line wire.

Related, already recorded: `kbResist` (innate) is dormant because **knockback displacement itself
is not implemented spatially** — the status ticks (stun-like) but nobody moves. One design pass
should land knockback + kbResist + standFirm's identity together.

Verified after the fix: 10-seed sweep 0 timeouts / 0 penetration, contracts 219/219 exact.

## The three pool-audit fixes, one by one (2026-08-06)

**1. tauntForce — WIRED, and it was the tenth built-and-unreachable find.** `monster_tree.gd`'s
target selection has carried a COMPLETE taunt override since the tree was built — marked
"currently unreachable" in its own comment — waiting for a producer that never existed. The
producer now lives in the debuff block of `_resolve_hit`: a landed tauntForce move appends a
`taunt` entry (with `from` = taunter name, the key `_find_taunter` resolves) to the victim's
statuses. ⚠️ Sim-side state, NOT a fieldStatus kind — the contracted status table is untouched;
`has_status` scans the array and the tick expires anything carrying an `until`. Proof: 61
victim-frames carrying taunt, 40 of them locked onto the taunter.

**2. spreadStatus (contagion) — PORTED from battle.ts semantics, given a radius.** From the
target's carried spreadable statuses, the first spreads to up to `targets` other enemies **within
`CONTAGION_RADIUS` of the infected body** (22 units — contagion that jumps the whole board is not
contagion), independent chance each, copy inherits the source's REMAINING duration. Runs after
the move's own status so a cast can create the very status it spreads.
⚠️ **THE PROBE'S FIRST VERSION READ "BROKEN" OFF A SATURATED FIELD**: five Plague Shooters
poisoned every enemy DIRECTLY, leaving contagion nobody to infect — 0 events, all rejections
"already has poison". One carrier: 2 contagion events across 6 fights. Contagion is rare by
design at these chances (40%, radius-bound) — a re-baseline knob, not a bug.

**3. Knockback DISPLACES — and `kbResist` wakes up.** The status previously ticked (0.6 speed)
but nobody moved. ⚠️ NOTHING TELEPORTS: a landed knockback arms a FLIGHT — `KNOCKBACK_DIST` =
3 × REACH_SCALE (the same board fraction as the old engine's push 3 on its 40-wide board),
paid out at `KNOCKBACK_SPEED` 30 u/s (3 u/tick, under the 4-unit anti-teleport tripwire), control
lost for the ride, resolver still forbids walls. `kbResist` (Immovable/Unstoppable, potency-
scaled) multiplies the distance — the innate that was dormant until displacement existed.
Proof: 136 flight ticks at 3.03 max (the .03 is the separation nudge riding on top).

⚠️ One scripted-edit trap for the file's history: a `str.replace` of a common anchor landed the
knockback block in TWO functions; the second had no `new_positions` and broke the parse. Anchors
must be unique or counted — the same class of error as the innates.ts one-per-line assumption.

Battery after all three: sweep 0 timeouts / 0 penetration (227/284 mean frames), taunt/care/weary
probes green, contracts 219/219 exact.

## The legibility pass — everything the sim gained today, now visible (2026-08-06)

The day added ~a dozen mechanics the renderer never showed, and the vision doc is explicit that
legibility is load-bearing in a game you cannot intervene in. ⚠️ **The interrupt event — built
YESTERDAY — was never in the log dispatch either**: interrupts fired, logged sim-side, and no
line ever appeared. The heal/cleanse lesson ("an effect with no line in the log did not happen
as far as the player is concerned") repeated within 24 hours of being written down.

Now surfaced in `arena_3d.gd`:
- **Floats on the body**: INTERRUPTED (orange), STEADY (gold — castSteady shrugging one off),
  DETONATED (ember), INFECTED (sickly green — contagion), TAUNTED (orange), LAUNCHED (violet —
  knockback flight).
- **Log lines** for interrupt / cast_steady / detonate / contagion, same colour families.
- **Status chips**: `taunt` and `weary` join STATUS_META. ⚠️ Both are SIM-SIDE states, not
  fieldStatus kinds — weary is injected as a pseudo-status from the frame's own `weary` flag.
- **The innate line on every plate**: "✦ Ambush · 75%" — name and care potency, text dimmed at
  low potency so a neglected monster visibly carries a dimmed gift. The care loop's entire
  output was invisible without this.

Not yet surfaced (honest gaps): charge/brace arming (no frame field carries them), aura radii
(would need ground decals), and the taunt "taunted by" reason line (overwritten by later
decisions — the chip covers the read). These are the next legibility slice, not omissions.

## Dead plates gone, and the VFX slice (2026-08-06)

**Dead monsters lose their whole nameplate** (user call — the earlier fix hid only the HP row).
⚠️ The declutter pass (`_update_plates`) sets `visible = true` on every plate it places EVERY
FRAME, so the naive hide was silently resurrected one frame later — invisible to any headless
probe, obvious on screen. The pass now skips the dead. A hide that fights a per-frame show is a
shape worth remembering.

**VFX: procedural GPUParticles3D + Kenney CC0 sprites** (user's pick). 12 curated textures from
the Particle Pack (CC0, licence in `assets/vfx/kenney/`), driven ENTIRELY by the event stream —
the renderer derives nothing, these are visual echoes of events the sim already emitted:

| event | effect |
|---|---|
| landed hit | channel-coloured burst (slash sprite for melee, star for the rest); crit = bigger + gold sparks |
| casting | rising glow at the caster's feet for the whole windup — THE TELEGRAPH, visible at any zoom |
| death | grey smoke puff at the topple |
| interrupt | orange twirl fizzle |
| castSteady | gold circle pulse |
| detonate | ember flare + scorch |
| contagion | sickly green smoke on the infected |
| knockback | dust kicked up at launch |

⚠️ **COLOUR DISCIPLINE HELD**: effects colour by CHANNEL (melee amber / ranged steel / magic
violet / support green) — the same hue families the log already uses — never by team. No fourth
colour system.

⚠️ **A POOL, NOT PER-EVENT NODES**: 24 emitters round-robin; a 5v5 lands several hits a second
and per-hit node allocation would stutter exactly when the fight is busiest. Additive blend, so
effects read as light on any ground.

⚠️ New textures need `--import` run once headless before a headless/exported build sees them —
done; `.import` files are committed alongside.

## play_ability — the VFX map made executable (2026-08-06)

`vfx.gd::play_ability(move, caster, victim, crit)` implements `docs/VFX_ABILITY_MAP.md` as a
running dispatch: **name override → line flavour → type/channel rules**, the same cascade the
map documents. ⚠️ The map is the SPEC — when the two disagree, fix the dispatch.

- 27 name overrides (Chain Lightning arcs victim-to-victim, Blood Price bleeds the CASTER first,
  Doom marks with a shrinking black-violet circle, taunts ring orange...).
- Line flavour where the channel lies about identity: Assassin is a knife-flash in dark smoke
  (never a bolt), Venomcraft spits, Siphon threads.
- **The buff grammar is live**: the sim emits one buff event PER AFFECTED UNIT, so
  `aura_pulse` — a channel/status-coloured ring rising under the monster for ~1s, charge sheet
  on the caster — rings exactly who a team buff touched, and only them. Heals rise green with
  the same ring.
- Beams/chains/siphons are a particle march along the caster→victim line — a billboard flipbook
  cannot lie along a 3D line, but a march of small bursts reads as one.
- Three more sheets joined from the user's own bundle: lightstreaks, blood_impact, cloud (frost).

Proof (`_probe_vfx.gd`): **all 141 moves dispatched twice (normal + crit) without error**,
24 recipes in use, none dead, 11/11 flipbooks loaded. Distribution: 39 aura_buff · 21 melee ·
14 magic · 13 debuff · 7 voice · 6 ranged · 6 venom · 5 shadow_knife · 5 siphon · 4 heal ·
the rest hand-authored singles.

## The Larkessa line — a tracer that exposed one bug and mislabelled another (2026-08-06)

User: *"look at the line coming from larkessa. why is this."* Two causes, one real fix each:

**1. The AoE fan-out was POSITION-BLIND — a real sim bug, fixed.** `_spatially_legal` range-gates
the PRIMARY target, but the `allEnemies` branch then hit every enemy `aoe_coverage` returned —
a formation-based fraction with no distance term (roadmap item 5's known abstraction) — so a
voice AoE at reach 53 was landing on bodies 250 units away. The fan-out now skips anything
beyond the MOVE's own authored reach from the caster. Probe after: **0 of 543 shots from
`allEnemies` moves land beyond reach** (the 3 residual `enemy` overshoots are windup drift —
legality is checked at cast START and a target can walk ~50 units during a 2.5s windup, which
is the interrupt gamble working as designed).

**2. Larkessa's actual line was a SUPPORT TRACER to a distant ALLY — mechanics intended, visual
wrong.** Team buffs cover by formation fraction BY DESIGN (the deployment board's aura/AoE
trade), so buffing a far ally is legitimate; drawing an attack-yellow LASER to them is the lie.
Friendly casts no longer draw tracers — the aura_pulse ring already marks every recipient, which
is the grammar built for exactly this. Attacks keep their tracers.

⚠️ The pattern worth keeping: **the VFX made two sim abstractions visible within an hour of
existing.** Legibility work is not polish here — it is an instrument, and it just out-performed
the probes on a bug class (position-blindness) this log has caught three times before.

## The AoE telegraph, and emission-proofing every animation (2026-08-06)

**AoE moves now show their area during the windup.** While an `allEnemies` move winds up, a
channel-coloured torus ring sits on the ground around the caster at the MOVE'S OWN AUTHORED
REACH — the same number the fan-out now enforces, so the ring never lies about what it will hit.
This is the WoW grammar completed: windup (cast bar + glow) + AREA (the ring) + counterplay
(walk out of it, and the fan-out gate honours the walk). The sim now emits `castMove` per
casting unit — "the renderer derives nothing" means the sim must SAY what is being wound up.
Proof: 231 telegraphable AoE windup frames across 4 fights.

**Every animation is now EMISSION-proofed, not dispatch-proofed.** The probe previously proved
`play_ability` never crashed; a recipe that matched but played nothing (missing texture, empty
flipbook) would still have passed. It now counts emitters actually firing after every one of the
141 moves: **every move emits at least one effect**, 11/11 flipbooks loaded. The
dispatch-vs-emission distinction is the same wiring-vs-look lesson at a smaller scale.

## Mechanical projectiles — damage lands on arrival (2026-08-06)

User decision: **mechanical, not cosmetic** — ranged and magic single-target casts launch a real
projectile after the windup, and the hit resolves when it ARRIVES, with ARRIVAL-TIME geometry.
Cover walked behind during the flight, a back turned, a weary stagger — all of it counts at the
moment of impact, not the moment of release. Melee and voice stay instant: a sword has no flight
and a shout arrives at the speed of sound.

- Speeds: ranged 90 u/s (an arrow — barely dodgeable), magic 55 u/s (a fireball — faster than any
  monster's ~30, so nothing outruns one flat, but a long-range fireball is >1s in the air and the
  world genuinely changes under it).
- **Homing** — the autobattler standard: the projectile tracks its mark; "dodging" is what the
  accuracy/cover/facing inputs are for, recomputed at arrival. A target that dies mid-flight
  fizzles the shot; a caster that dies does NOT recall the arrow — it was loosed.
- The frame stream's `projectiles` array — defined in BUILD_CONTRACT §2, empty since the day it
  was written — now carries real flights, and the renderer's waiting `_sync_projectiles` (and the
  fireball built this afternoon) consumes them with zero renderer changes. `from` is the sim's
  own per-tick position with progress 0, so the stream stays authoritative and nothing
  extrapolates.
- Impact VFX, floats, HP and the shot tracer all move to arrival automatically — they were always
  driven by `_resolve_hit`, which now runs at arrival.

Proof: 35 distinct projectiles in one fight, longest flight 13 ticks. Sweep 0 timeouts / 0
penetration (mean 253/279 — slightly longer, damage arrives later, expected), care A/B still
diverges, contracts 219/219 exact.

⚠️ This is a real mechanics change logged BEFORE the re-baseline, per the suspended-baseline
rules: intent recorded (projectile flight = the last layer of the telegraph game), numbers are
starting points.

## The game-feel pass (2026-08-06)

All renderer-side, all decaying, the sim never notices:

- **Hit-stop**: playback dips (×0.55 on heavy hits, ×0.45 on death) and recovers in ~0.15s. It
  multiplies the PLAYBACK, never `speed` — the user's chosen speed is not overwritten, the
  moment just lands heavier.
- **Camera punch**: a small decaying offset applied AFTER the follow logic positions the camera,
  so the two never fight. Pseudo-random from playback time — render-only.
- **Victim scale-pop**: 1.0 → 1.12 → 1.0 in 0.17s on big hits — the body visibly TAKES it.
- **Oomph — effect size scales with the WOUND, not the move**: damage as a fraction of the
  victim's pool multiplies the impact effects (0.8×–2.0×). A 5-damage poke on a wall stays a
  tick; the same number on a dying wisp is a blow. Threaded through `play_ability` into every
  burst and flipbook.
- Triggers: crits and hits ≥18% of the victim's pool punch + pop; deaths are the heaviest beat.

⚠️ Feel numbers are SUBJECTIVE and these are first guesses — the watch-and-adjust round with the
user is the actual tuning instrument. Every knob is a single constant.

## The quality tier — the full particle system, per the Godot docs (2026-08-06)

User: *"lets use the vfx team we have to make some very high quality particle and spell effects...
fully use the particle system... this has to be totally flawless and perfect."* Every API below
was VERIFIED against the live 4.7 docs before use (the engine-reference rule — 4.7 is beyond the
migration notes): `color_ramp`, `scale_curve`, `turbulence_enabled`, ring emission,
`trail_enabled`/`trail_lifetime` + `RibbonTrailMesh` + `use_particle_trails`, `sub_emitter`.

**What separates "particles" from "fire":**
- **Colour over lifetime** (`color_ramp`): fire is WHITE at birth, gold in its prime, deep red
  dying, smoke at the end. Five shared ramps (fire/smoke/magic/heal/spark), applied per burst
  ROLE. A flat-tinted particle is a moving decal.
- **Scale curves**: impacts snap in and shrink (POP); smoke swells (GROW).
- **Turbulence** on smoke/magic/glow — organic drift instead of ballistic straight lines.
- **Ribbon-trailed debris sparks** (`trail_enabled` + RibbonTrailMesh): the streaking debris
  every real explosion has — the single biggest "pro" tell in particle work. Pooled ×6.
- **Pooled light flashes** (8 shadowless OmniLight3D): an explosion that does not LIGHT the
  arena floor reads as a sticker on the screen. Explosions flash orange, heals glow green, and
  the fireball CARRIES its own travelling light — the floor glows as it passes.
- **The layered explosion** (`explosion_pro`): flash + fire sheet + trailed debris + turbulent
  smoke plume rising after — five layers at five timescales is what makes it read as an EVENT.
- **Cast glow rebuilt**: ring emission + tangential acceleration — the classic "power
  converging" swirl — with the magic ramp.

⚠️ **Pooled emitters MUST reset their finish**: role finishing (ramp/curve/turbulence) is
cleared and re-applied per burst, or a smoke ramp leaks onto a slash once a minute in a way
nobody can reproduce.

⚠️ **The `_ramp` helper's first draft had the add/remove-point dance** — Gradient ships with two
default stops and interleaved removal can silently eat your own first stops. Arrays are now set
whole; a probe asserts every ramp kept all its stops (5/4/3/3/3 verified).

Probes: ramps verified, pools live, explosion_pro fires clean, 141/141 moves still emit.

## The border hunt, and the identity shapes (2026-08-06)

**The hit-flash border**: "has an alpha channel" and "has a CLEAN alpha channel" are different
claims, and the audit that checked only alpha RANGE missed both failure modes:
1. **Full-cell frames** — big_hit's opening flash fills its entire sheet cell, so the quad
   renders as a hard-edged rectangle. No alpha audit catches this; the frame IS opaque to its
   edge by authorship.
2. **Additive haze** — lightstreaks carries alpha ~53 across its background; under ADD blending
   the whole cell glows faintly.

**The fix is structural, not per-sheet**: every sheet now passes through a cleaner that applies
a PER-CELL edge vignette (no frame may touch its own rectangle edge — fade over the outer 12%)
plus a luminance-keyed alpha scrub. All 11 sheets → `*_clean.png`; originals kept. Any future
sheet import must run the same cleaner — it is in the scratchpad generator.

**Five more identity shapes from our own generator** (pure math, no licence): `slash_arc` (a
crescent — melee hits now sweep instead of splat), `bolt` (streak with a bright head — ranged
impacts), `droplet` (venom's teardrop), `note` (Lullaby drifts real music notes), `skull`
(Doom's mark is a skull, readable at 16px). Wired: slash/impact roles overridden; venom, sleep
and doom recipes now carry shapes nothing stock provided.

Probes: 141/141 emit, 11/11 clean flipbooks load, explosion_pro clean.

## The shader tier completes: tether, shockwave, dome (2026-08-06)

Six pure-shader effects now, all variants of two rigs (the crossed-quad beam, the ground quad):

| effect | character | used by |
|---|---|---|
| lightning | jagged, re-strikes 24/s | Chain Lightning, Static Chain |
| siphon beam | smooth, pulses flow TOWARD caster | all five drains, tinted per move |
| doom tether | slow, heavy, pulses flow toward VICTIM (the curse being fed) | Doom |
| static ring | radius crawls with fbm, sparks orbit | control, taunts (orange), lightning landings |
| shockwave | clean expanding pressure ring, thins as it grows | stomps, Sonic Boom |
| ward dome | fresnel hemisphere, bright rim, shimmer | all wards |

Design notes worth keeping: **additive black is invisible**, so Doom's darkness is a bright
violet with slow dread-pulses, not dark pixels. The tether and siphon are the same rig with
OPPOSITE pulse directions — theft flows to the caster, a curse flows to the victim — direction
as identity. A pressure wave is smooth where electricity crawls: the shockwave has no jitter on
purpose. `_beam_rig` extracted so every future beam is a shader + one call.

Probes: 3 beam holders + 2 ground quads + 1 dome build clean; 141/141 moves emit.

## Seen with our own eyes: the border killed on screen, and the crowd arrives (2026-08-06)

**The screenshot loop closed.** The Godot MCP (run_project + game_screenshot) let the studio SEE
its own build for the first time — and the first inspection caught what every probe had missed:
the explosion sheet's late SMOKE frames fill their cell edge-to-edge, and a 12% edge fade cannot
save a frame that is 100% full. The fix is a RADIAL mask — every cell's alpha multiplied by a
smoothstep circle (0.60→0.97 of the half-min dimension) — because **a corner cannot survive a
circle**. Verified on screen after: the smoke is a round organic blob. ⚠️ Slow-mo via
Engine.time_scale does NOT slow GPUParticles (they run their own clock) — the stagger-fire
stage is the way to catch birth frames.

**The crowd (spectators.gd).** No CC0 seated-character models exist on Poly Pizza (30 CC0 hits,
all chairs) — but the pack models we OWN carry Wave/Yes/Jump/Dance clips. So the league is
watched by MONSTERS: pack creatures at 0.55 scale in two stepped rows along each apron, idling
desynced (a crowd breathing in unison reads as an army), one fidgeting every few seconds, and
REACTING to the fight — deaths bring 70% of the house up, crits a quarter. Render-side rng only.

⚠️ **FILL IS A PARAMETER BECAUSE FAME DRIVES IT** (the standing memory: seats fill from team
fame, never from arena size). Default 0.5 until the fame meta lands — do not "fix" a half-empty
stand by raising the default; wire fame.

## The crowd is HUMAN and truly seated; the zone tells land (2026-08-06)

**The user's bundle was a near-miss that led to the real answer.** The Low-Poly Characters
Bundle's 7 CC0 humans are STATIC MESHES (2 nodes, no rig) — nothing can pose them. But a sweep
of Poly Pizza's animated CC0 humans, reading each GLB's actual clip list, found **six Quaternius
humans every one carrying a REAL `Sitting` clip** — plus `Clapping` and `Jump`. The crowd now:
SITS at rest (desynced), CLAPS on crits, LEAPS on kills — and because the cheer clips are
standing, the house literally RISES for a kill, which is correct stadium behaviour for free.
Verified on screen: the post-kill frame shows both rows up with arms raised. All CC0, manifest
written. The 7 static fighters stay on disk as future townsfolk.

**Innate zone tells** (the remaining effects from the honest-gaps list): a zoner
(`auraEnemySlow`) carries a faint cold-blue ring at reach — the slow field made visible; a
territorial (`homeGroundDR`) gets a fixed earthy ring at its STATION. Innate identity is static
monster data — the same data the nameplate's innate line already renders — so the renderer
computing it breaks no contract. ⚠️ Brace/charge arming glints still need sim-side frame flags:
deferred WITH this note.

## Crowd v2 — every seat, every side, and the ripple (2026-08-06)

User direction, implemented and screenshot-verified:
- **All four sides, three stepped rows**, seat count derived from edge length — every step of
  the apron holds a body at fill = 1.0.
- **Per-instance colour variance**: duplicated materials with a subtle hue tint — six models
  no longer read as a clone army. ⚠️ Deliberately NOT team colours; the crowd must never join
  either side's colour system.
- **Sitting is the ONLY default.** No ambient fidget. The crowd cheers on exactly two triggers:
  camera punches (any shake rolls a small per-model chance) and deaths (a larger roll).
- **⚠️ THE RIPPLE IS THE POINT**: each reacting spectator waits a private random 0–0.7s before
  standing. A crowd that reacts on the same frame reads as an animatronic display; one that
  RIPPLES reads as people. The verification frame (post-kill) shows exactly that — some up,
  some rising, some seated.
- Fill stays a parameter; 1.0 is the demo value, FAME takes it over.

## Plater plates, edge-to-edge zones, the standing count (2026-08-06)

User direction, all screenshot-verified:
- **Deploy zones paint the WHOLE legal rect** — edge to separation line, full height, drawn from
  `Spatial.deploy_zone` itself. The thin strip only marked the default spawn band; the paint
  must cover exactly what the sim permits, or "did they hold their zone?" is unanswerable.
- **Standing count HUD** ("Team A N monsters remaining"), top centre, live per frame.
- **The Plater grammar** (after WoW's Plater addon, the user's reference): compact dark plate,
  tiny name, slim HP bar with % INSIDE, hair-thin mana bar always visible, and a CAST BAR that
  appears below only while casting — filling with `castFrac` (sim-emitted) and naming the
  ability. Ability icons join the cast bar when the icon set exists. The innate line and large
  chips are gone — minimalist is the spec; the innate is still on the orders panel.
- Crowd fill: user confirmed the future FAME mechanic owns it.

## More space, more stadium, and the UI scale pass (2026-08-06)

User: *"make the arena larger (more space for the monsters) and the stadium bigger, then get the
UI team to work on the scale of everything."*

**The ground base is now ONE constant** — `Spatial.GROUND_BASE = (50, 28)`, was 40×22 written as
a literal in TWO places (`ground_size` and `REF_SEPARATION`). Scaling one without the other
detaches speeds from the board — the fifth-scale-bug shape, pre-empted this time. Bodies and
reach stay fixed, so the arena grows RELATIVE to everything that fights in it (+25% per axis),
and speeds rise automatically to hold `TARGET_CLOSE_SECONDS`. Measured: mean fight length moved
only 239/268 → 259/275 frames on a 25% bigger board — the time-derived speed design working
exactly as built. 0 timeouts, 0 penetration, contracts 219/219.

**The stadium:** five stepped rows per side (was three), seat count still derived from edge
length, so the longer perimeter adds seats twice over. Fill still belongs to FAME.

**The UI scale pass:** `canvas_items` stretch at a 1920×1080 design resolution — the UI now
scales proportionally on ANY display instead of rendering fixed pixels (tiny at 4K, chunky on
laptops). Plates re-tuned for the design res: bars 120px wide, name/intent 12px, HP% 10px,
taller bars throughout, chips 9px. One grammar, every screen.

## The UI team's three fix-packs (2026-08-06, /team-ui adapted pipeline)

Three specialists (ux-designer, art-director, accessibility-specialist) evaluated the arena in
parallel; user approved all three fix-packs. The two headline finds were both FALSE READS:

**Pack 1 — false reads + core legibility:**
- ⚠️ **The default camera was the wrong one** (UX #1): every fight booted into the wide
  "instrument" shot — bodies ~4% of frame height, every plate element illegible — while the
  tuned follow camera sat behind an undiscovered `C`. One-line flip; transforms the frame. The
  wide shot remains on `C` as the instrument it is.
- ⚠️ **The cast telegraph lied about channel** (AD #1): `cast_glow` hardcoded magic-violet for
  EVERY caster — a melee windup telegraphed as a spell. Now channel-true, neutral grey-white
  when the move is unknown (never a wrong colour).
- Mana bar: was 6px colour-only — the exact failure the HP bar had, on the sibling bar. Now
  12px with an outlined % readout.
- Status colour families: seven statuses shared ONE gold. Now body-lock gold / mental
  pink-violet / silence blue-grey / knockback warm neutral.
- Float-text fan: same-moment hits on one body fanned in world space instead of smearing.
- Text floor: name/intent 18px, HP%/cast 16px, chips 13 (⚠️ deliberate deviation below the 16
  floor — 16px chips overflow the plate; the icon-shape pass is the real fix, still owed).
- Status overflow: 4 chips + "+N".

**Pack 2 — attribution + colour discipline:**
- Melee hits draw a subdued attribution flick (alpha 0.35, 0.12s — attribution, not reach), so
  a scrum finally says who hit whom.
- Damage numbers speak the CHANNEL palette (lightened), ending the fourth colour system; crit
  keeps "!" plus a gold LEAN as a modifier; BACK stays text.

**Pack 3 — Guild Colours identity:**
- Plate warmed toward timber/leather (layout and a11y untouched).
- The wizard metaphors reskinned: Doom is a FORFEIT BRAND (iron-orange + scorch, skull shape
  kept for 16px readability), wards shimmer BRASS (riveted guild plate), drains are a TAUT
  LEASH (rope-tan; Mana Burn steel-blue), the tether is a branding-iron.
- Fallback primitive obstacles get RIM LIGHTING — the cheap stand-in for bevels until every
  kind has a GLB ("a 90° edge that catches no highlight reads as a diagram").

Deferred with notes: live intent tags (blocked behind tree-AI per UX_LEGIBILITY §11), status
chip icon-shapes (owed), settings/text-scale surface (needs a settings screen), crowd craft.

## Content scale: four arenas, 65 species bodied, 141 icons (2026-08-06)

**Arenas.** `triad` (Robodrome/Maldraxxus — three diagonal pillars, no straight lane survives
the middle) and `lanes` (Hook Point/Enigma Crucible — two long walls making a centre lane and
two duel wings) join `four_pillar` and `central_mass`. Probed: 0 timeouts, 0 penetration,
fight lengths in family (312/305 mean frames). The watch cycle runs all four.

**Species.** All 65 species now map to a pack body — the 45 unmapped ones assigned by
SILHOUETTE per the standing rule (never by name), 46 models covering 65 species with deliberate
reuse (shared bodies get per-instance tints later). ⚠️ Found in passing: `scarabrute` mapped to
`"goleling"`, which does not exist on disk — a fight fielding it would have had no body.
Fixed to `goleling_evolved`.

**Icons.** 141 ability icons GENERATED (PIL, licence-free, regenerable): the LINE owns the
glyph shape (a line is a shared win condition — its icons read as kin), the STAT owns the tint,
the TYPE owns a corner badge (+/−/ring). Wired into the cast bar's waiting slot — a windup now
shows icon + name + filling bar. Same generator philosophy as the particle textures: any future
move gets its icon by regeneration, not by asset request.

## The gallery review: no evolutions, five new bodies, and the bind-pose lie (2026-08-06)

The species gallery (all 65 in a labelled grid — a dev scene worth keeping) earned its build
cost in one screenshot:

- **User rule: NO *_evolved variants** — they read as duplicate species. A fresh Poly Pizza sweep
  found five NEW complete-clip CC0 bodies (wolf, husky, fox, spider, fish — the aquatic gap
  finally filled), and every evolved usage (11 species across 5 evolved models) was remapped to
  distinct bases or the new bodies. Bonus recastings: brinehowl (a HOWLER) finally gets the
  wolf; balaenix/carcharun get real fish bodies.
- ⚠️ **THE BIND-POSE LIE**: squidle and ghost rendered 3-4x their neighbours. Their bind poses
  are COMPACT (tentacles curled, arms tucked), so `_skinned_bounds` under-measures and the
  normaliser over-scales — the bounds are honest about the bind pose and wrong about the
  creature on screen. Fixed with a SHORT outlier table (squidle 0.5, ghost 0.55), eye-tuned
  against the gallery. Kept deliberately short: an exception list for models whose bind pose
  lies, never a per-species tuning table (that warning stands). Sampling every clip's every
  frame would be the "correct" fix and is over-engineered for 3 outliers.
- My first read of the giant models ("it's just perspective") was HALF wrong — front-row
  perspective was real, but the same-row sprawl was the genuine bug. The gallery's labelled
  same-row comparison is what separated the two.


## The tenth 'already built' instance, and the clean-rewrite decision (2026-08-07)

Asked to start the tree framework and sim rewrite, this session built both - and then
discovered scripts/ai/ already carried a COMPLETE prior build (bt_* library, 1,469-line
monster_tree.gd, 224-line selftest) with spatial_sim.gd already rebuilt as its Stream A,
coordinated via docs/BUILD_CONTRACT.md. Even the determinism spike existed
(docs/SPIKE_DETERMINISM.md) - this session re-derived the identical verdict, traps included.
The task list said #22-24 pending; the tree said otherwise. ⚠️ LIST THE DIRECTORY BEFORE
TRUSTING THE TASK LIST - the log's own rule, ignored at cost.

**The user's call: rewrite clean anyway** - "now we've had practice and know what works",
with **WoW arena as the explicit reference** (focus targets, peels, interrupts, cooldown
trading, burst windows, kiting with real costs). So: the NEW stack (bt.gd + combat_tree.gd +
sim/sim.gd + sim/nav_service.gd) is canon; the legacy streams carry SUPERSEDED banners, stay
live for the game screens until the renderer switches over at parity, and serve as the mine
for proven logic. All three new probes green: framework 15/15, combat tree 33/33, sim 8/8
(fights resolve, wings spread laterally, twin-seed runs byte-identical).

Two lessons paid for this session: a --script SceneTree cannot sync a navmesh (no main loop -
probes that need nav run as SCENES); and one decision tick is ONE intent - per-action commits
made the decision log cycle Mark->Move->Engage forever until the tree committed once per tick.

## The legibility audit, and what a demo roster is FOR (2026-08-08)

Two findings from wiring the renderer to the rewritten sim's event stream.

**1. The renderer presented 5 of 21 event kinds.** Heals, ward soaks, taunts, thorns
reflects, status applications, cast-severing control, cleanses, buffs and DoT ticks were all
emitted by the sim and silently dropped. In a game whose entire loop is WATCHING, an
unpresented event is a mechanic that does not exist for the player — the same
"authored but unreachable" failure this log keeps recording, one layer further out. All nine
significant kinds now have a read (misses stay silent on purpose: absence of impact IS the
read, and a projectile miss is already visible in flight).

**2. ⚠️ A DEMO ROSTER THAT CANNOT PRODUCE A MECHANIC IS A DEMO THAT HIDES IT.** The watch
scene assigned kits by stat threshold — damage moves and kicks only — so the heal, ward,
taunt, thorns, AoE and status layers built over four rounds could never appear on screen no
matter how good the presentation was. The fix is the ROSTER, not more renderer code: the demo
now fields a real arena composition, and a permanent `WATCH vocabulary —` line prints which
event kinds the fight actually produced. That line is the tripwire; if a mechanic stops
appearing, the demo says so.

**And the roster measured a real balance finding.** A MIRROR of the sustain comp (two
healers, two tanks, thorns, wards both sides) ground to **1345 ticks — 134 seconds**, near
the 1800 cap: five-a-side sustain outlasts the damage a five-stack brings, and both sides
simply healed through each other. Moderating the stat floors moved it barely at all; the
structure was the cause, not the numbers. Asymmetry fixed it — SUSTAIN vs PRESSURE, the
actual arena question, resolves in **254 ticks (25s)** with seven deaths and sixteen event
kinds firing. Worth remembering when the balance pass comes: with the support layer live,
defensive stacking is strong enough that mirror comps stall, and that is a design question
(does sustain need a brake?) rather than a bug.

## Integration round: the renderer switch, and what it uncovered (2026-08-08)

Four parallel workstreams landed together (audio, renderer switch, balance sweep, per-move
projectiles). All four arrived with their own probes green. Integrating them found three
things none of those probes could see.

**1. ⚠️ THE BATTLE SCREEN HAS NEVER COMPILED, AND 175 GREEN CHECKS SAID NOTHING.**
`deployment_board.gd:_compute_zones()` read `team_size_` — the *parameter* of `setup()` — from
a scope it does not exist in. That is a hard parse error, and it took `tactics_ui.gd` down with
it ("Failed to compile depended scripts"). Tournament → tactics → battle is the only route to
the battle screen, so the cup path has been dead **since the initial commit**.

It survived because every probe in the battery exercises the sim *directly* and none of them
touches `arena_3d.gd`; and because `_probe_compile.gd` tested `load(path) == null`, while a
script that fails to compile still returns a **non-null broken `Script`**. The probe printed
`OK:` on the same line the engine printed `Compilation failed`. It now checks
`can_instantiate()`, which is the question it always meant to ask.

⚠️ **The general lesson, and it is the expensive one: a probe that tests the sim is not a probe
that tests the GAME.** `scripts/_probe_arena_switch.gd` (new) boots the real `arena3d.tscn`
through the real entry state the tactics screen leaves behind, at **both 1v1 and 5v5** — the
5v5 case deliberately, because the game is a 5v5 game and a 1v1 exercises none of the id
ordering (`a00`..`a04` sorting into roster order) or deploy spread the switch is risky for.

**2. The renderer switch itself is sound, and its own ⚠️ was the real one.** The two engines use
different coordinate origins (legacy corner-frame `[0,W]`, new sim centre-frame `[-W/2,W/2]`).
Getting that backwards puts every unit off the navmesh, nobody paths, and the fight runs to the
1800-tick cap *looking exactly like broken AI*. The probe pins the tell directly: a fight that
resolves well inside the cap, with every unit deploying inside the board.

**3. The authored projectile axis was inert — kit.gd wrote it, sim.gd never read it.**
`kit.gd` attached `{speed, width_radii, pierce}` per move while `sim.gd` still keyed flight off
its own channel table, so 40 authored moves flew at the old flat 90/55. Now consumed.

⚠️ **PIERCE DRAWS ZERO RNG, AND THAT IS THE DESIGN, NOT AN OPTIMISATION.** Rolling fresh dice per
incidental body would insert a *geometry-dependent* number of draws into the stream — the one
thing the determinism contract cannot absorb. Instead the shot carries the three dice it was
loosed with and each body it passes applies its own armour to them. One arrow, one release,
three sets of ribs. Verified by a twin-run with piercing shots in play.

**And the sweep moved, for a reason worth writing down.** 9 of 16 matchups stayed
byte-identical; 7 lengthened or shortened. Cause: **25 of the 40 authored moves are SLOWER than
the flat channel constant they replaced** (11/20 ranged, 14/20 magic), so damage arrives later
and ranged-leaning comps stretch. Largest single shift was pressure vs balanced, 202 → 328
ticks. This is the authored content doing its job, not a regression — and critically, the stall
picture is unchanged: still **4 of 16 matchups over 90s, and the same four** (both sustain and
both control mirrors/crossings). The dampening and no-kill-ratchet findings stand as recorded.

## What the superseded engine taught us (2026-08-08, legacy deletion round)

Parity was reached last round (`arena_3d.gd` runs `sim/sim.gd` behind `USE_NEW_SIM`), so the
superseded engine can start coming out. **The code goes; the findings do not.** This section is
the extraction — everything still true that lived only as a comment in a file being deleted, or
in a file queued for deletion. The project standard it serves: *"a rework that reintroduces a bug
the sim already caught is not a rework, it is an amnesia."*

### Deleted this round: the OLD `bt_*` behaviour-tree library (17 files, ~850 LOC)

`bt_node · bt_action · bt_selector · bt_sequence · bt_composite · bt_condition · bt_context ·
bt_blackboard · bt_result · bt_decorator · bt_inverter · bt_succeeder · bt_parallel · bt_cooldown ·
bt_until_fail · bt_tree · bt_selftest`. Superseded by `scripts/ai/bt.gd` + `combat_tree.gd`.
It was already a **closed island** — nothing outside the library referenced any of it, by path or
by global class name, in any script or scene. Four lessons were paid for once and are kept here.

**1. Legibility is a property of the RETURN VALUE, not a debug feature bolted on afterwards.**
The old library's `tick()` returned a `BTResult` object rather than a bare status int, carrying
the ACTIVE PATH (root-to-leaf node names) plus an optional reason. The path was built by *pure
composition* — each node prepends its own name to whatever its WINNING child reported — never by
mutating a shared "current path" on the context. ⚠️ **That is what structurally guarantees a
Selector's REJECTED siblings cannot leak their reasoning into the branch that actually won.**
This is the stated reason a behaviour tree was chosen over a flat utility scorer at all: the
active branch *is* the explanation, and reconstructing intent from scores after the fact is the
failure mode being avoided. `bt.gd` must keep this property; if a future refactor makes intent a
side-channel written during traversal, that guarantee is gone and nothing will announce it.

**2. Running state belongs on a per-monster blackboard, NEVER on a node instance.** One node
object may be shared across a whole tree *definition* ticked for many different monsters, so
anything remembered between ticks (current target, destination, dwell timers, mid-action flags)
must be keyed by the node's own name in a per-monster store. A tree that stashes state on `self`
looks correct at 1v1 and silently cross-talks at 5v5 — the bug does not appear until team size
grows, which is exactly when it is hardest to see.

**3. Two GDScript traps this project hit more than once, re-confirmed against 4.7.1.**
⚠️ Cross-file references used `preload()` and subclasses used `extends "res://..."` by path, never
`extends BTNode` — **the global script-class cache is COLD under `--headless --script` and during
early autoload boot**, so a bare class-name reference fails to *parse* in exactly the state every
probe runs in. And ⚠️ methods were deliberately named `set_value`/`get_value`, not `set`/`get`/
`has`/`erase`, because those already exist as built-in `Object` methods and shadowing them on a
scripted class is a live footgun.

**4. Determinism was enforced at the context boundary, and that shape was right.** `dt` was a
caller-supplied fixed step (never a frame `delta`) and `rng` was a caller-owned seeded generator
(the library never called `randf()` itself); composites iterated children in fixed array order.
Putting both on the context object rather than trusting each leaf to behave makes the rule
*checkable in one place* instead of auditable across every node.

### Not deleted, and why — the legacy trio is still on a live path

`spatial_sim.gd` (1852 LOC), `spatial_ai.gd` (116) and `ai/monster_tree.gd` (1474) **stay this
round.** `arena_3d.gd` no longer needs them (its legacy branch is a guarded `ResourceLoader.exists`
fallback), but **`scripts/ui/sandbox_ui.gd:47` hard-`preload`s `spatial_sim.gd`** and constructs it
at line 645. A `preload` of a missing path is a parse error, not a graceful degrade, so deleting
the sim would break the sandbox screen outright.

⚠️ **AND THE TRIO MUST GO ATOMICALLY, NOT PIECEMEAL.** `spatial_sim.gd` loads the other two by
path with an `exists`-guard and falls back silently: without `monster_tree.gd` every unit degrades
to "walk at the nearest living enemy", and without `spatial_ai.gd` team focus fire disappears.
Deleting two of three would leave a screen that still *runs* while being quietly lobotomised —
the exact half-state that costs this project debug rounds. One move, or none.

### The findings the trio still holds — extracted now, while the context is in hand

**The blob had an ARITHMETIC cause, not an AI cause.** `_apply_leash` clamped every unit's desired
position into a circle around the living centroid of *both* teams (24% of board width at tight,
42% at loose). It was self-reinforcing: the anchor was wherever everyone already was, so units
could never spread, so the centroid never moved, so units still could not spread. ⚠️ **No amount
of AI work could have fixed the user's "big blob of monsters" complaint while that ran** — it was
a hard geometric bound on every fight, not a tuning problem. Shape must come from positional
intent, formations and objectives; never from a positional clamp. *(This lesson is already
safe — it is preserved in `spatial.gd`'s `engagement_radius()` tombstone, which is a LAYOUT-ONLY
helper and must never gate movement again.)*

**A default that returns one answer for every unit is not a decision, it is the absence of one.**
Positional intent defaulted to `hold` below aggression 66; `personality` was a stub returning `{}`
so aggression was 50 for everyone — all ten units on the field took the same branch. "Ten units
walking in a straight line at each other was not an AI that had decided to; it was an AI with one
option." ⚠️ **A team's default must be a FORMATION OF ROLES, not one behaviour repeated five
times**, derived from what the sim already knows: long reach → HOLD (ground is its advantage),
fast + short → WINGS (it can pay for the arc), otherwise → PUSH.

**The engagement gate: a fight that could not end.** Measured — a 3v3 ran the full 180s cap twice
with ZERO deaths, the gap between sides pinned at 33.1 units (exactly `DEPLOY_SEPARATION`) for all
1801 ticks, while every weapon in the game reaches 3–11. Both teams stood at spawn because `hold`
anchors to `home_point` and nothing owned closing the distance. ⚠️ **WHY IT WENT UNCAUGHT IS THE
transferable part:** `push`, `wings` and `dive` each closed as a *side effect* of their own logic,
so engagement was incidental to three subtrees rather than owned by the root — the two that did
not implement it were silently broken, and every probe written to that point passed an explicit
intent, so the DEFAULT path (the one every real fight takes) was the broken one. **When a
capability is an emergent side effect of several branches, the branches that lack it fail
silently, and the untested default is where it bites.**

**Symmetric cover is worth nothing, and the AI avoiding it was CORRECT.** A blocking piece costs
both sides the same accuracy, so standing behind one is a wash. Cover becomes profitable only
where the trade stops being even: when OUTNUMBERED (a symmetric penalty against 3:1 fire is a
trade in your favour) or for a SUPPORT kit (whose moves target allies, so it pays nothing for
cover between itself and the enemy). ⚠️ A universal "seek cover" drive would replace one wrong
behaviour with another — a duelling melee kit gains nothing from a wall.

**Team focus fire had to be computed for the TEAM, once.** Target priority used to live
per-monster, so five monsters "agreeing" on a target was coincidence. Computing one focus per side
per decision cycle and passing it down as *advisory* — the unit still weighs whether following it
is worth the walk — is what turns coincidence into coordination without turning a team into a
single mind.
