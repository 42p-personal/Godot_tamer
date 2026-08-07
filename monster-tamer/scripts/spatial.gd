## THE SPATIAL CONTRACT — geometry, constants and pure helpers for the real field simulation.
##
## ⚠️ THIS FILE EXISTS BECAUSE A STANDING RULE WAS DELIBERATELY REVERSED (2026-08-04).
## `CLAUDE.md` said: "Do not port what is being redesigned. Arenas, the spatial layer, the camera
## and target selection are all explicitly out." That rule was correct while the spatial model was
## still an open question. The user has now directed that the game BE a real simulation, so the
## layer gets built. The rule is superseded, not forgotten — everything below is built to the
## design the docs already settled on, rather than invented fresh.
##
## ⚠️ DETERMINISM IS THE CONTRACT AND IT CONSTRAINS EVERY CHOICE HERE.
## `docs/SPATIAL_MODEL.md` is explicit that Godot physics and navigation are NOT deterministic by
## default, and four systems depend on the current guarantee. Therefore:
##   · fixed timestep (DT), never `delta`
##   · ALL randomness from an injected seeded RNG, never `randf()`/`Math.random()`
##   · NO RigidBody/CharacterBody/NavigationAgent/physics queries anywhere in the sim
##   · integer-stable ordering — iterate units in a fixed order, never a Dictionary's hash order
## A sim that desyncs cannot be balanced, replayed or contract-tested. This is not negotiable.
##
## Sources for every number below (none are invented here):
##   `docs/ARENA_BLUEPRINT.md`  — ground sizes, deploy separation, reach scale, SPREAD/leash, auras
##   `docs/ENGAGEMENT_DESIGN.md` — the chase problem and BACKPEDAL_MULT
##   `docs/SPATIAL_COMBAT_DESIGN.md` — cover as accuracy debuff, flanking on melee engagement
class_name Spatial
extends RefCounted

# ═══════════════════════════════════════════════════════════════════════════════════════════════
# THE GROUND  (ARENA_BLUEPRINT §0-1)
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## `k(N) = 2.0 + 0.5 × (N − 1)`, anchored so 5v5 lands at 4× the pool's tuning baseline (40×22).
static func ground_scale(team_size: int) -> float:
	return 2.0 + 0.5 * (float(maxi(1, team_size)) - 1.0)

## ⚠️ THE BOARD IS SIZED IN BODY-WIDTHS, NOT IN ABSTRACT UNITS. Both numbers below were authored
## when a unit was a billboarded sprite roughly 1.8 units across; real geometry arrived at ~4
## units across, so every distance in the game silently became half as big in body-widths as it
## was designed to be. The board did not change — the things standing on it did.
##
## `GEOMETRY_SCALE` is that correction, applied once here so the ground and the body radius move
## together. Splitting them is how the fight ended up in a 10-unit bubble on a 160-unit board:
## the sim was correctly keeping bodies 1.8 units apart while the renderer drew them inside each
## other, so the sim saw a formation and the player saw a pile.
##
## 5v5 goes 160×88 -> 352×194. ⚠️ AND THE WALK DOES NOT GET LONGER: `DEPLOY_SEPARATION` below is
## deliberately independent of ground width (ARENA_BLUEPRINT §2), because deriving it from W once
## measured a tank crossing 143.5 units in 52s against a ~23s median fight — it spent the whole
## fight walking and never arrived. A bigger board buys ROOM TO MANOEUVRE, not a longer approach.
const GEOMETRY_SCALE := 2.2

## ⚠️ THE GROUND BASE IS ONE CONSTANT, SHARED WITH REF_SEPARATION. It was a literal 40 in two
## places; scaling one without the other detaches unit speeds from the board (the fifth-scale-bug
## shape, again). 50×28 (was 40×22, user call 2026-08-06: "more space for the monsters") — bodies
## and reach stay fixed, so the ARENA grows relative to everything that fights in it, and speeds
## rise automatically to hold TARGET_CLOSE_SECONDS.
const GROUND_BASE := Vector2(50.0, 28.0)

static func ground_size(team_size: int) -> Vector2:
	var k := ground_scale(team_size)
	return Vector2(k * GROUND_BASE.x * GEOMETRY_SCALE, k * GROUND_BASE.y * GEOMETRY_SCALE)

## ⚠️ DEPLOY SEPARATION IS INDEPENDENT OF GROUND WIDTH — the decision recorded in
## ARENA_BLUEPRINT §2. Deriving it from `W` made a 4× wider board a 4× longer walk, and measured
## a tank crossing 143.5 units in 52s against a ~23s median fight: it would have spent the entire
## fight walking and never arrived. Sized from closing TIME instead, flat at every team size.
## ⚠️ THIS IS SIZED FROM TIME, SO IT ONLY STAYS CORRECT IF SPEED SCALES WITH THE BOARD TOO.
## `SLOW_UNIT_SPEED` is a speed, and speeds below carry `GEOMETRY_SCALE`, so the product stays a
## 12-second walk on a board 2.2x larger. Scaling the ground and leaving this alone put the two
## deploy bands 33 units apart on a 352-unit board — the teams used 9% of the width and the rest
## of the arena was scenery they never visited. Making the board bigger did not give them room to
## fight in; it gave them ground they never reach.
## ⚠️ REVERSED 2026-08-05 ON THE STUDIO OWNER'S CALL: "the deployment zones must be at either end
## of the arena." Separation is now derived FROM THE BOARD — the two lines stand a deploy-depth in
## from opposite ends — and the SPEED is derived from the separation so the approach still takes
## `TARGET_CLOSE_SECONDS`.
##
## ⚠️ THIS IS THE EXACT ARRANGEMENT ARENA_BLUEPRINT §2 REJECTED, AND THE REASON IT REJECTED IT NO
## LONGER APPLIES. It measured a tank crossing 143.5 units in 52s against a ~23s fight and
## concluded a width-derived separation makes units walk instead of fight. That was true because
## SPEED was held fixed while the distance grew. Deriving speed from the distance removes the
## failure entirely: the walk is 12 seconds at any board size, by construction. The old rule was
## right about the SYMPTOM and wrong to blame the separation rather than the coupling.
static func deploy_separation(team_size: int) -> float:
	return maxf(20.0, ground_size(team_size).x - 2.0 * deploy_depth(team_size) * GEOMETRY_SCALE)

## ⚠️ 12 -> 26 SECONDS, because the walk is now the whole board rather than a third of it. Holding
## 12s across 304 units would need ~25 units/s — over TWELVE body-lengths per second, which reads
## as teleporting rather than charging. 26s puts the reference tank at ~2.7 body-lengths/s.
##
## ⚠️ AND THE APPROACH IS NOT DEAD TIME. Reach now runs to 96 units, so ranged and magic kits open
## fire long before the lines meet: the walk IS the opening phase of the fight, which is exactly
## the "closing under fire" shape `ENGAGEMENT_DESIGN.md` wants. `AUTOBATTLER_DESIGN.md` #11 puts
## emergent fight length at ~30s to ~3min, so a 26s approach sits inside the design, not outside.
## ⚠️ 26.0 → 21.0 → 17.0 ON 2026-08-06, both steps on the user's call that the fight reads sluggish. This is
## the RIGHT knob for "make them faster": every unit speed is derived from it, so the DEX ladder,
## the closing bonus and the backpedal all scale together and stay in proportion. Bolting a
## multiplier onto SPEED_MIN/SPEED_MAX instead would have silently decoupled speed from the board
## — which is the fifth-scale-bug failure this constant was introduced to end.
const TARGET_CLOSE_SECONDS := 17.0

## ⚠️ SPEED IS DERIVED FROM THE 5v5 BOARD, and 5v5 is the anchor by standing rule ("The game is a
## 5v5 game" — `CLAUDE.md`). Writing these as bare numbers again is precisely how five separate
## scale bugs happened this session, so the whole derivation is spelled out as a const expression:
## a reader can see where every factor comes from and nothing needs re-deriving by hand.
const REF_TEAM_SIZE := 5
const REF_SEPARATION := (2.0 + 0.5 * (REF_TEAM_SIZE - 1)) * GROUND_BASE.x * GEOMETRY_SCALE \
	- 2.0 * (6.0 + REF_TEAM_SIZE) * GEOMETRY_SCALE          # shares GROUND_BASE — never a second literal
const SLOW_REF_SPEED := REF_SEPARATION / TARGET_CLOSE_SECONDS   # ≈ 11.7 units/s

## The slowest body's speed at a given team size, sized to cross that board in the same time.
static func slow_unit_speed(team_size: int) -> float:
	return deploy_separation(team_size) / TARGET_CLOSE_SECONDS

## Deploy depth is a BODY-COUNT question, not a board-size one — it exists to fit N bodies into
## one or two ranks. Scaling it with the ground would put a 5v5 deploy zone 44 units deep for no
## mechanical reason.
static func deploy_depth(team_size: int) -> float:
	return 6.0 + float(team_size)


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# SPREAD / LEASH  (ARENA_BLUEPRINT §4 — "SPREAD and the leash are ONE KNOB. Do not build both.")
# ═══════════════════════════════════════════════════════════════════════════════════════════════

const SPREAD_TIGHT := 0.55
const SPREAD_LOOSE := 0.95

static func usable_radius(team_size: int) -> float:
	return 0.4 * ground_size(team_size).y

## ⚠️ RENAMED FROM `leash_radius` (2026-08-04). THIS IS A LAYOUT HELPER. IT MUST NEVER GATE
## MOVEMENT AGAIN.
##
## It used to be the radius of a hard clamp on every unit's desired position, anchored on the
## living centroid of both teams — which made the blob arithmetically unavoidable and has been
## deleted from `spatial_sim.gd` (see the tombstone comment there, and `AUTOBATTLER_DESIGN.md`
## #36).
##
## The function survives because it has a SECOND, unrelated and still-valid use: the annulus rule
## in `ARENA_DESIGN.md`, where cover is placed between the tight and loose radii so disengaging
## is a deliberate, reachable decision. That is a question about where to put BARRELS, not about
## where a monster is allowed to stand.
##
## The old name invited exactly the confusion that would undo the fix, so it now says what it is.
## `spread` is 0.0 (tight) .. 1.0 (loose).
static func engagement_radius(team_size: int, spread: float) -> float:
	return lerpf(SPREAD_TIGHT, SPREAD_LOOSE, clampf(spread, 0.0, 1.0)) * usable_radius(team_size)

## ⚠️ PROXIMITY-SIZED AURAS, sized to just clear a TIGHT formation and to fall well short of a
## LOOSE one. This is the deliberate trade: a tight team keeps its buffs across the formation, a
## loose team gives them up. The cost of board control, made visible on the field.
static func aura_radius(team_size: int) -> float:
	return 1.1 * (SPREAD_TIGHT * usable_radius(team_size))


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# REACH  (ARENA_BLUEPRINT §3 — every spatial constant scaled by k(5) = 4.0, applied globally)
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## ⚠️ REACH IS A FRACTION OF THE BOARD, AND THE BOARD JUST CHANGED. These three exist to lift the
## pool's authored ranges (written for a 40×22 field) onto the real ground, so they are meaningless
## as absolutes — what matters is reach RELATIVE to the distance between fighters. Scaling the
## ground by `GEOMETRY_SCALE` without scaling these would have made every ability proportionally
## SHORTER, which pulls units closer together: the opposite of the fix, arrived at by fixing half
## of it. Exactly the mistake `ARENA_DESIGN.md` warns about when it says an art decision silently
## became a balance input nobody was reviewing.
const REACH_SCALE := 4.0 * GEOMETRY_SCALE
const HARD_REACH_MIN := 9.6 * GEOMETRY_SCALE
const HARD_REACH_MAX := 44.0 * GEOMETRY_SCALE

## Per-channel stand-off, already scaled. ⚠️ The LINE owns the reach, not the channel — DEX's
## channel is `ranged` whether the move is a bow or a stiletto — so a move's own authored `range`
## always wins over this table. This is only the fallback for the class free attack.
## ⚠️ ALREADY EXPRESSED ON THE POST-LIFT SCALE (that is the whole point of the `is_basic` note
## below), so these carry `GEOMETRY_SCALE` directly rather than through `REACH_SCALE`.
const CHANNEL_RANGE := {
	"melee": 12.0 * GEOMETRY_SCALE, "ranged": 32.0 * GEOMETRY_SCALE,
	"magic": 28.0 * GEOMETRY_SCALE, "voice": 26.0 * GEOMETRY_SCALE,
	"support": 24.0 * GEOMETRY_SCALE,
}

## ⚠️ MINIMUM RANGE (ENGAGEMENT_DESIGN Family B1) — a ranged unit pinned inside this has to fight
## rather than run further, which is what stops a kiter treating the whole corridor as one
## continuous retreat. The class BASIC never has one; only authored ranged moves do.
static func minimum_range(move_range: float, is_basic: bool) -> float:
	if is_basic or move_range < 16.0 * GEOMETRY_SCALE:
		return 0.0
	return move_range * 0.22

## ⚠️ FIXED 2026-08-04 (SQA-001, docs/SPATIAL_QA.md). This used to read `elif not is_basic`, which
## skipped the REACH_SCALE lift for CLASS-BASIC ranges. `data.json`'s `classBasic` table authors
## melee/ranged/magic/voice/support at 3/8/7/6/6 — all on the pool's OLD 40×22 scale, exactly like
## every other authored range — but because the lift was gated on `not is_basic`, all four raw
## values landed below HARD_REACH_MIN and clamped to the SAME 9.6-unit floor. Every class's free
## attack — the one action every unit falls back to constantly — resolved to an identical stand-off
## regardless of channel. CLAUDE.md's Battle sim section already documents this exact mistake being
## made and fixed TWICE in the TypeScript engine; this was the Godot port's third copy. The fix:
## any authored range (basic or not) is on the old scale and needs the lift; only the CHANNEL_RANGE
## fallback (used when a move carries no `range` at all) is already expressed on the new scale.
static func reach_of(move: Dictionary, is_basic: bool = false) -> float:
	var r: float = float(move.get("range", 0.0))
	if r <= 0.0:
		r = float(CHANNEL_RANGE.get(move.get("channel", "melee"), 12.0))
	else:
		# Authored ranges live on the pool's ORIGINAL 40×22 scale; lift them to the new ground.
		r *= REACH_SCALE
	return clampf(r, HARD_REACH_MIN, HARD_REACH_MAX)


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# MOVEMENT
# ═══════════════════════════════════════════════════════════════════════════════════════════════

const DT := 0.1                      # the fixed simulation step. NEVER use frame delta.
## ⚠️ SPEED IS DISTANCE PER SECOND, SO IT IS A BOARD-RELATIVE QUANTITY LIKE ALL THE OTHERS.
## Scaling the ground, the bodies and the reach while leaving speed alone makes every unit
## proportionally SLUGGISH — the same class of half-fix as scaling the ground without the reach.
## `DT` is not scaled: it is real time, and time did not change.
## ⚠️ SPEED IS BOARD-DERIVED NOW. `slow_unit_speed()` is what a tank must manage to cross the
## board in TARGET_CLOSE_SECONDS, and the DEX range brackets it: the floor is a little under it,
## the ceiling a little over. Writing these as bare numbers again is how the fifth scale bug
## happened; they are ratios against the board, deliberately.
const SPEED_MIN := SLOW_REF_SPEED * 0.87    # at DEX 0 — slightly slower than the reference tank
const SPEED_MAX := SLOW_REF_SPEED * 1.70    # at DEX 1000 — fast, without reading as a teleport
## ⚠️ THIS IS THE HUDDLE, AND IT WAS NOT AN AI PROBLEM. 0.9 kept bodies 1.8 units apart — correct
## for a billboarded sprite, and roughly HALF a real creature's footprint once geometry landed
## (`UNIT_HEIGHT` is 4.4 and the bodies are ~4 units across). So `_separate()` was doing its job
## perfectly and the renderer was still drawing ten monsters inside one another.
##
## Measured before the change: the two team centroids closed from 34.9 units to **2.2**, and mean
## nearest-teammate distance fell to 4.3 — on a board 160 units wide. The whole fight happened in
## a ~10-unit bubble. Looking for a smarter AI would have found nothing wrong with it.
##
## Derived, not guessed: half of `arena_3d.gd`'s `UNIT_HEIGHT` (4.4) is the same figure the camera
## uses for `CAM_BODY_RADIUS`, so the sim and the renderer now agree about how big a monster is.
## ⚠️ Keep them in step. Two independent opinions about body size is exactly this bug.
const BODY_RADIUS := 2.2

## ⚠️ THE ASYMMETRY THAT MAKES CHASES RESOLVE, AND IT IS ALREADY MEASURED.
## `ENGAGEMENT_DESIGN.md` records that without it "a chase NEVER resolves — a pursuit equilibrium
## that left units out of range 76% of the fight regardless of field size or speed (both measured,
## both invariant)". The fix was never a speed number; it was costing the RETREATING unit. Do not
## replace this with a speed buff to melee.
## ⚠️ THE WOBBLE. Measured 2026-08-06 on the user's report that "monsters wobble around the
## enemies": mean heading change per 0.1s tick was 9.2° (four_pillar) and 14.0° (central_mass) —
## up to 140°/second of turning — with a >90° REVERSAL on 4.6–7.4% of moving ticks, and path
## directness (net displacement / distance walked) as low as 0.57. Nearly half the distance
## walked was going nowhere.
##
## Two independent causes, both fixed here, neither of them the AI:
##
## 1. **No momentum.** A unit's heading was whatever its latest decision pointed at, applied whole
##    in one tick. A body cannot pivot 180° instantly and it does not read as one when it does.
##    The heading now STEERS at a bounded rate. 300°/s is deliberately generous — normal steering
##    (9–14°/tick) is untouched and only the snaps get smoothed, so this filters jitter without
##    making anything feel like it is on rails. A genuine reversal still happens, it just takes
##    ~0.6s, which is also more readable than an instant flip.
##
## 2. **Micro-shuffle.** There was no arrival deadzone: a unit whose goal sat 0.3 units away took
##    a 0.3-unit step, and next tick the goal had drifted slightly the other way, so it stepped
##    back. Sub-body-radius stepping is invisible as travel and unmistakable as a jitter. Below
##    ARRIVE_EPS a unit now simply stands still.
##
## ⚠️ AND THE FIRST VERSION OF THE ORBITING GUARD MADE THE WOBBLE WORSE, NOT BETTER — 9.2° → 15.7°
## and 14.0° → 27.2°. It granted a free turn whenever the unit had not moved on the PREVIOUS tick,
## and the new arrival deadzone made not-moving common, so almost every unit qualified for a snap
## almost every tick. The guard has to require a SUSTAINED stop (STATIONARY_TICKS_FOR_FREE_TURN),
## not an instantaneous one. Recorded because the mistake is a general one: an escape hatch keyed
## on a condition that another part of the same change made frequent.
const STATIONARY_TICKS_FOR_FREE_TURN := 5   # 0.5s — genuinely stopped, not merely between steps

## ⚠️ THE KNOWN RISK OF A TURN LIMIT IS ORBITING — a unit that cannot turn tightly enough circles
## its goal forever. Guarded two ways: the rate is far above normal steering, and a unit that has
## been stopped for STATIONARY_TICKS_FOR_FREE_TURN may turn freely (it has no momentum to
## conserve), so nothing can get stuck facing the wrong way with no way to recover.
## ⚠️ A TURN RADIUS, NOT A TURN RATE — AND THE DIFFERENCE IS NOT COSMETIC. This was a fixed
## 300°/s, which silently means "the faster you go, the wider you must arc": turning circle is
## speed ÷ angular rate. Raising the speed a second time (TARGET_CLOSE_SECONDS 21 → 17) exposed it
## immediately — heading change per tick went UP 6.7° → 10.9°, directness fell 0.74 → 0.62, and
## `central_mass` fights ran 556 → 1167 frames as units circled goals they could no longer turn
## tightly enough to reach. That is the orbiting failure the turn limit was warned about, arriving
## exactly as predicted and for exactly this reason.
##
## Deriving the cap from a RADIUS makes the turning circle a constant of the body instead of a
## consequence of the speed, so the same steering behaviour survives any future speed change.
## Board-derived like every other spatial constant — see the GEOMETRY_SCALE note at the top.
const TURN_RADIUS := BODY_RADIUS * 1.4

## How close an enemy must be before a unit keeps its FRONT to it rather than to its travel
## direction. Beyond this it is marching, not fighting, and facing where you are going is correct.
## ── knockback (2026-08-06, the third pool-audit fix) ─────────────────────────────────────────
## ⚠️ NOTHING TELEPORTS — the standing rule. A knockback is a FLIGHT: the victim travels at
## KNOCKBACK_SPEED and has no control until the distance is spent. The distance is board-scaled
## exactly as the old engine's was: Body Slam's push 3 was 7.5% of the 40-wide board, and
## 3 × REACH_SCALE is the same fraction of this one. Speed stays under the anti-teleport
## tripwire (no unit may move >4 units in one tick).
## ── projectiles (2026-08-06, user decision: MECHANICAL — damage lands on arrival) ─────────────
## Speeds are world units/second. Ranged is an arrow: fast, barely dodgeable. Magic is a
## fireball: slower than an arrow, faster than any monster (SPEED_MAX ≈ 30), so nothing simply
## outruns one flat — but a long-range fireball is ~1.5s in the air, and cover, facing and death
## all genuinely change under it. Voice/support/melee stay instant: a shout has no flight.
const PROJECTILE_SPEED := {"ranged": 90.0, "magic": 55.0}

const KNOCKBACK_DIST := 3.0 * REACH_SCALE
const KNOCKBACK_SPEED := 30.0

## Contagion radius (spreadStatus): the spatial reading of "spreads to other enemies" — bodies
## NEAR THE INFECTED TARGET, because contagion that jumps the whole board is not contagion.
const CONTAGION_RADIUS := 10.0 * GEOMETRY_SCALE

const FACE_TARGET_DIST := 40.0 * GEOMETRY_SCALE
## Head-turn rate, expressed as the speed `steer()` should assume. Faster than the body's own turn
## because looking at something is cheaper than driving toward it — but still bounded, so a unit
## swapping targets swings its head rather than teleporting its front.
const FACE_TURN_REF_SPEED := SPEED_MAX * 2.2
const ARRIVE_EPS := BODY_RADIUS * 0.5

## Rotate `cur` toward `want` by at most one tick's worth of turn, where "one tick's worth" is
## whatever holds TURN_RADIUS at this speed. `free_turn` bypasses the limit for a unit that was not
## moving — see the orbiting guard above.
static func steer(cur: Vector2, want: Vector2, speed: float, goal_dist: float, free_turn: bool) -> Vector2:
	if want.length_squared() < 0.000001:
		return cur
	var w := want.normalized()
	if free_turn or cur.length_squared() < 0.000001:
		return w
	var c := cur.normalized()
	var delta := c.angle_to(w)
	# ω = v / r — a constant turning circle at any speed. A goal INSIDE the circle cannot be arced
	# onto, so the cap RELAXES smoothly as the goal gets closer than the radius.
	# ⚠️ SMOOTHLY, NOT AS A SWITCH. The binary version of this — "within 2r, turn freely" — put the
	# snap back: it covered a 1.1–6.2 unit band that units sit in constantly, and reversals went
	# 0.4%/1.0% → 2.3%/4.5%. That is the SECOND time in this one change that an escape hatch keyed
	# on a common condition undid the fix it was guarding. The pattern is the lesson.
	var relax: float = 1.0 if goal_dist <= 0.0 else maxf(1.0, TURN_RADIUS / maxf(0.001, goal_dist))
	var cap := (speed / TURN_RADIUS) * relax * DT
	if absf(delta) <= cap:
		return w
	return c.rotated(cap * signf(delta))


const BACKPEDAL_MULT := 0.60

## Closing-speed bonus (ENGAGEMENT_DESIGN Family A). ⚠️ ARENA_BLUEPRINT §10 names this the
## load-bearing dependency of the whole ground size — without it the opening on a board this large
## is real dead time, not a filmable establishing shot.
const CLOSING_BONUS := 1.25          # while advancing on a distant enemy and not yet in reach
const CLOSING_ENGAGE_DIST := 18.0    # centre of the taper band — see closing_bonus_factor()

## ⚠️ AUTOBATTLER_DESIGN.md #40 — THE TAPER, REPLACING A HARD CUTOFF AT `CLOSING_ENGAGE_DIST`.
## §13.1 names the bug directly: a mid-speed chaser closing to exactly 18 lost the bonus, fell
## behind, drifted back past 18, regained it — an oscillation that would have rendered as the
## "wandering in circles" failure TFM2's players complain about. Half-width of the smooth ramp
## either side of CLOSING_ENGAGE_DIST; crossing the old cliff point now moves the bonus by a small
## continuous amount instead of flipping it on/off.
const CLOSING_TAPER_HALF := 6.0

## Smoothstep from 1.0 (no bonus, at/inside CLOSING_ENGAGE_DIST - CLOSING_TAPER_HALF) to
## CLOSING_BONUS (full bonus, at/beyond CLOSING_ENGAGE_DIST + CLOSING_TAPER_HALF). Continuous and
## monotonic in `dist_to_target` — no discontinuity anywhere for a chase to oscillate across.
static func closing_bonus_factor(dist_to_target: float) -> float:
	var band_start := CLOSING_ENGAGE_DIST - CLOSING_TAPER_HALF
	var t: float = clampf((dist_to_target - band_start) / (2.0 * CLOSING_TAPER_HALF), 0.0, 1.0)
	var smooth: float = t * t * (3.0 - 2.0 * t)
	return lerpf(1.0, CLOSING_BONUS, smooth)

static func speed_of(dex: float) -> float:
	return SPEED_MIN + (SPEED_MAX - SPEED_MIN) * clampf(dex / 1000.0, 0.0, 1.0)

## Per-tick step length, folding in the advance/retreat asymmetry and the closing bonus.
## ⚠️ `in_reach` still gates the bonus outright (once a hit is possible, closing further isn't the
## point) but distance no longer does so with a cliff — see `closing_bonus_factor`.
static func step_len(dex: float, advancing: bool, dist_to_target: float, in_reach: bool) -> float:
	var s := speed_of(dex)
	if not advancing:
		s *= BACKPEDAL_MULT
	elif not in_reach:
		s *= closing_bonus_factor(dist_to_target)
	return s * DT


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# COVER & LINE OF SIGHT  (SPATIAL_COMBAT_DESIGN)
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## ⚠️ COVER IS AN ACCURACY DEBUFF, NOT BINARY OCCLUSION — this is one of TWO findings where the
## shipped code did NOT match the stated design intent. Binary occlusion makes a shot either free
## or impossible, which reads as a bug to a player who cannot see the ray. Graded cover reads as
## "that was a hard shot".
const COVER_SOFT_ACC := 12.0         # accuracy POINTS subtracted (accuracy is points, never a fraction)
const COVER_HARD_ACC := 25.0
const COVER_BLOCKS_LOS_GRADE := "blocking"   # the heaviest grade; also the only one that carves nav

## ⚠️ COVER IS AN ACCURACY DEBUFF, NOT AN ON/OFF SWITCH — implementing what
## `SPATIAL_COMBAT_DESIGN.md` §2 decided and the engine never did. That doc recorded the mismatch
## plainly: *"a unit behind a rock is not HARDER to hit by ranged and magic; it is UNTARGETABLE.
## Cover is an on/off switch."*
##
## ⚠️ AND THE MISMATCH WAS MEASURABLY BACKFIRING. With blocking cover as a hard block, a unit
## standing in shelter CANNOT ATTACK — so avoiding cover is the rational play, and the units were
## doing exactly that: measured at 0.22x and 0.74x of a random-position baseline, i.e. actively
## AVOIDING cover rather than failing to seek it. Ranged kits avoided it hardest (0-18% sheltered
## against 34-55% by chance) because they have the most shooting to lose.
##
## Turning it into a heavy penalty makes cover a TRADE instead of a cliff: you are much harder to
## hit and much worse at hitting, which is a decision a kit can actually want. `blocked` survives
## in the return value for the two things that are genuinely binary — navmesh carving, and the
## break-line-of-sight behaviour a WITHDRAWING unit uses, where refusing to fight is the point.
const COVER_BLOCK_ACC := 45.0

## ⚠️ FLANKING IS +10 ON MELEE ENGAGEMENT, not +5 on a radius — the second design/code mismatch.
const FLANK_ACC_BONUS := 10.0
const FLANK_MELEE_RANGE := 14.0

## Segment-vs-AABB test. Deterministic slab method, no physics query — see the determinism note
## at the top of this file.
static func segment_hits_rect(a: Vector2, b: Vector2, r: Rect2) -> bool:
	var d := b - a
	var tmin := 0.0
	var tmax := 1.0
	for axis in 2:
		var da: float = d.x if axis == 0 else d.y
		var aa: float = a.x if axis == 0 else a.y
		var lo: float = r.position.x if axis == 0 else r.position.y
		var hi: float = lo + (r.size.x if axis == 0 else r.size.y)
		if absf(da) < 0.000001:
			if aa < lo or aa > hi:
				return false
			continue
		var t1 := (lo - aa) / da
		var t2 := (hi - aa) / da
		if t1 > t2:
			var tmp := t1; t1 = t2; t2 = tmp
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return false
	return true


## Accuracy modifier from whatever cover sits between shooter and target.
## Returns {"blocked": bool, "accPenalty": float}. `obstacles` is an Array of
## {rect: Rect2, grade: "soft"|"hard"|"blocking"}.
static func cover_between(from: Vector2, to: Vector2, obstacles: Array) -> Dictionary:
	var penalty := 0.0
	var blocked := false
	for o in obstacles:
		if not segment_hits_rect(from, to, o["rect"]):
			continue
		var grade: String = str(o.get("grade", "soft"))
		if grade == COVER_BLOCKS_LOS_GRADE:
			blocked = true
			penalty = maxf(penalty, COVER_BLOCK_ACC)
		elif grade == "hard":
			penalty = maxf(penalty, COVER_HARD_ACC)
		else:
			penalty = maxf(penalty, COVER_SOFT_ACC)
	return {"blocked": blocked, "accPenalty": penalty}


## Is `attacker` flanking `target`? True when the target is engaged in melee by someone else and
## this attacker is also inside melee engagement range — i.e. outnumbered and unsupported, which
## is the condition the design actually names.
static func is_flanking(attacker_pos: Vector2, target_pos: Vector2, other_engagers: int) -> bool:
	return other_engagers > 0 and attacker_pos.distance_to(target_pos) <= FLANK_MELEE_RANGE


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# WINDUP  (studio owner, 2026-08-06)
# ═══════════════════════════════════════════════════════════════════════════════════════════════
#
## ⚠️ THE GAME HAD NO TELEGRAPHS AND THAT BLOCKED A WHOLE CLASS OF MECHANIC. Measured: every move
## in the 141-move pool has a cast time, but the LONGEST IS 0.6 SECONDS against a 0.1s tick — a
## six-tick windup, during which a unit covers ~6.6 units against cover pieces ~40 units wide.
## Nothing that depends on "during a cast" could work: not interruption, not ducking behind cover,
## not a readable burst window. `CLAUDE.md` removed ultimates and nothing replaced the telegraph
## they had provided.
##
## ⚠️ VERIFIED WoW ANCHORS, not recalled ones (checked 2026-08-06 against warcraft.wiki.gg and
## live search; the studio's own combat researcher had no web access and self-flagged its numbers):
##   · Polymorph / Fear / Cyclone cast in ~1.7s — CC is deliberately the telegraphed band
##   · melee interrupts run ~15s cooldown with a ~3s school lockout
##   · INSTANT CASTS CANNOT BE INTERRUPTED — having no cast time is itself the defence
## The transferable shape is that a telegraphed cast lasts a little longer than the time an
## opponent needs to respond, so the response is a real decision rather than a coin toss.
##
## ⚠️ WHY THIS LIVES HERE AND NOT IN `derive.gd`. `Derive.cast_time_of` is under the derive.json
## port contract, whose five castTime cases pin the per-CHANNEL fallback. And `data/data.json` is
## GENERATED — `run_contract.sh` re-copies it every run, so authoring a `castTime` per move there
## would be overwritten. The windup is therefore a spatial-layer rule, exactly like facing: the
## port stays faithful and the new mechanic sits beside it.
##
## Tiers follow the studio owner's direction: "AOE and channel abilities should generally be a bit
## longer, but we can use cast time as a balance mechanic for our spells too."
const WINDUP_CONTROL := 1.5        ## CC is the telegraph, as in WoW
const WINDUP_AOE := 1.2            ## hitting everyone should be seen coming
const WINDUP_HEAVY := 2.5          ## the biggest single hits in the pool
const WINDUP_STRONG := 1.0
## Power thresholds, taken from the pool's own distribution (n=88 damaging moves):
## p50 34 · p80 51 · p95 89 · max 168. Using percentiles rather than invented constants means the
## tiering follows the pool if the pool is rebalanced.
const POWER_HEAVY := 89.0
const POWER_STRONG := 51.0

## Seconds of windup before a move resolves. Falls through to the ported per-channel value for
## everything that is not deliberately telegraphed, so the fast majority of the pool is unchanged.
static func windup_of(move: Dictionary, ported_default: float) -> float:
	var power := float(move.get("power", 0.0))
	var is_aoe: bool = str(move.get("target", "enemy")) == "allEnemies"
	var is_control: bool = str(move.get("type", "damage")) == "control"

	# ⚠️ Order matters and is a design statement: CONTROL telegraphs even when it is weak, because
	# the counterplay to being crowd-controlled is the whole point of seeing it coming.
	if is_control:
		return maxf(ported_default, WINDUP_CONTROL)
	if power >= POWER_HEAVY:
		return maxf(ported_default, WINDUP_HEAVY)
	if is_aoe:
		# AoE scales with its own power — a big area move is the most telegraphed thing on the field.
		return maxf(ported_default, WINDUP_AOE + (WINDUP_HEAVY - WINDUP_AOE) * clampf(
			(power - POWER_STRONG) / maxf(1.0, POWER_HEAVY - POWER_STRONG), 0.0, 1.0))
	if power >= POWER_STRONG:
		return maxf(ported_default, WINDUP_STRONG)
	return ported_default


## ⚠️ An instant is UNINTERRUPTIBLE, and that is a real defensive property rather than an
## oversight — it is exactly WoW's rule ("instant cast non-channeled spells cannot be interrupted,
## as they have no cast time"). A kit built on fast cheap moves is buying immunity to interruption
## with its damage ceiling, which is a trade worth having in the game.
static func is_interruptible(windup: float) -> bool:
	return windup >= WINDUP_STRONG


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# FACING  (studio owner, 2026-08-05)
# ═══════════════════════════════════════════════════════════════════════════════════════════════
#
## ⚠️ WHICH WAY A MONSTER IS LOOKING NOW MATTERS. `facing` has been in the frame stream and updated
## on every move since the spatial layer was built (`spatial_sim.gd:597`), and nothing read it —
## geometry unblocked it and no mechanic used it. This is that mechanic.
##
## ⚠️ AND IT REPLACES THE OLD FLANKING RATHER THAN STACKING ON IT. `is_flanking()` above answers
## "is this attacker outnumbering an unsupported target", which is a real idea but has NOTHING to
## do with where the attacker is standing — a unit directly in front of its target scored the
## bonus. Two systems both called flanking, one facing-blind, would be a coin-flip about which
## explanation a player believes.
##
## ⚠️ THE CONSEQUENCE WORTH DESIGNING AROUND: a unit faces whatever it is moving toward, and it
## moves toward its own target. So YOU CAN ONLY BE HIT FROM BEHIND BY SOMEONE WHO IS NOT YOUR
## TARGET. Backstabs are therefore inherently a TEAM mechanic — somebody has to hold the victim's
## attention while somebody else gets round. That makes peel and guard matter, gives the `wings`
## branch a payoff it did not have, and means a lone assassin achieves nothing. Emergent, and
## exactly the shape a 5v5 wants.
const FACING_SIDE_DEG := 60.0     ## half-angle of the FRONT arc: within 60 deg of facing is front
const FACING_REAR_DEG := 120.0    ## beyond 120 deg from facing is rear; between the two is side

## ⚠️ REAR DAMAGE IS A BIG LEVER, NOT A GARNISH. For scale, crit is an 8% chance at 1.5x — about
## 4% expected damage across all hits. A flat +15% from behind is roughly 3.75x the entire crit
## system's contribution. That is fine as a STARTING value (the balance baseline is being remade
## from scratch by the studio owner's decision) but it must be re-measured, not assumed.
const REAR_DAMAGE_BONUS := 0.15

## "front" | "side" | "rear" — where `attacker_pos` stands relative to what `target_facing` looks at.
## `rear_deg_override` > 0 narrows the TARGET's own rear arc (the rearArcDeg innate — a veteran
## that is harder to backstab). 0 means the standard FACING_REAR_DEG.
static func facing_arc(attacker_pos: Vector2, target_pos: Vector2, target_facing: Vector2,
		rear_deg_override: float = 0.0) -> String:
	if target_facing.length_squared() < 0.0001:
		return "front"                      # no facing yet — never award a bonus on missing data
	var to_attacker := attacker_pos - target_pos
	if to_attacker.length_squared() < 0.0001:
		return "front"
	var deg := rad_to_deg(target_facing.normalized().angle_to(to_attacker.normalized()))
	var a := absf(deg)
	# A narrower rear arc means the attacker must be MORE directly behind: the rear threshold
	# rises from the standard 120 toward 180 minus half the authored arc.
	var rear_from := FACING_REAR_DEG if rear_deg_override <= 0.0 else 180.0 - rear_deg_override * 0.5
	if a <= FACING_SIDE_DEG:
		return "front"
	if a >= rear_from:
		return "rear"
	return "side"


## Damage multiplier for an arc. Front is unmodified; side pays in ACCURACY (below), not damage,
## so that a partial flank is a real but lesser reward than getting all the way round.
static func facing_damage_mult(arc: String) -> float:
	return 1.0 + REAR_DAMAGE_BONUS if arc == "rear" else 1.0


## Side and rear both count as "flanked" for the accuracy bonus the old system awarded — so the
## bonus survives, it just now depends on where the attacker actually IS.
static func facing_acc_bonus(arc: String) -> float:
	return FLANK_ACC_BONUS if arc != "front" else 0.0


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# DEPLOYMENT
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## Starting positions. Teams face each other across `DEPLOY_SEPARATION` at the ground's centre —
## NOT at the board edges, so the growth of the ground goes into flank room rather than into a
## longer walk (ARENA_BLUEPRINT §2).
## The legal deployment zone per side — everything between the board edge and this side's half of
## the deploy separation, inset by a body radius. ⚠️ THE ONE DEFINITION. `deployment_board.gd`
## used to compute its own copy of this rectangle inline, which is two opinions about where a
## monster may legally start — the exact "two opinions about body size" failure the huddle bug
## came from. The board and the sim now both call this.
static func deploy_zone(team_size: int, side: String) -> Rect2:
	var g := ground_size(team_size)
	var half_sep := deploy_separation(team_size) * 0.5
	var br := BODY_RADIUS
	var cx := g.x * 0.5
	if side == "A":
		return Rect2(Vector2(br, br), Vector2(maxf(1.0, cx - half_sep - br), maxf(1.0, g.y - 2.0 * br)))
	return Rect2(Vector2(cx + half_sep, br), Vector2(maxf(1.0, g.x - br - (cx + half_sep)), maxf(1.0, g.y - 2.0 * br)))


static func deploy_positions(team_size: int, side: String) -> Array:
	var g := ground_size(team_size)
	var cx := g.x * 0.5
	var cy := g.y * 0.5
	var dir := -1.0 if side == "A" else 1.0
	var x := cx + dir * deploy_separation(team_size) * 0.5
	# ⚠️ THE DEPLOY BAND IS A DISTANCE, SO IT SCALES WITH THE BOARD. `team_size * 6.0` put five
	# units into 30 units of a 193-deep arena — a short column in the middle of an empty field,
	# which is why the two sides simply walked straight at each other with nothing else to do.
	# ⚠️ THE LINE SHOULD SPAN THE FIELD, NOT SIT IN A KNOT IN THE MIDDLE OF IT. Sizing the band
	# purely per-body (`team_size * 6`) gave five units 66 units of a 194-deep arena, so the fight
	# never touched the flanks and the measured footprint stayed at 31% of the ground however large
	# the ground was made. Now it takes whichever is WIDER: enough room per body, or a real share
	# of the field. The per-body term still governs small team sizes, where a 1v1 spread across the
	# whole width would be absurd.
	var per_body: float = float(team_size) * 6.0 * GEOMETRY_SCALE
	var share_of_field: float = g.y * 0.60 * clampf(float(team_size) / 5.0, 0.25, 1.0)
	var band: float = minf(g.y - 6.0 * GEOMETRY_SCALE, maxf(per_body, share_of_field))
	var out: Array = []
	for i in range(team_size):
		var t := 0.5 if team_size == 1 else float(i) / float(team_size - 1)
		var y := cy - band * 0.5 + band * t
		# Alternate a short rank offset so a line of five isn't a flat wall.
		# Rank offset is a distance too — see the band note above.
		var stagger := 0.0 if i % 2 == 0 else dir * 3.0 * GEOMETRY_SCALE
		out.append(Vector2(x + stagger, y))
	return out


static func clamp_to_ground(p: Vector2, team_size: int) -> Vector2:
	var g := ground_size(team_size)
	return Vector2(
		clampf(p.x, BODY_RADIUS, g.x - BODY_RADIUS),
		clampf(p.y, BODY_RADIUS, g.y - BODY_RADIUS))
