## THE SIM, REWRITTEN — decision #32: from scratch, around the combat tree; never evolved from
## the flat-scoring sim that produced the blob.
##
## Architecture: DECIDE / EXECUTE / EMIT, fixed-step.
##   DECIDE  — every DECISION_EVERY ticks each unit's combat tree runs over a blackboard the
##             sim fills (the contract at the top of combat_tree.gd). The tree writes REQUESTS.
##   EXECUTE — the sim carries requests out under the movement rules: NavigationServer paths
##             (spike-proven deterministic), per-unit speed, solid enemy bodies (#10, allies
##             passable #22), strikes through the CONTRACTED damage maths — resolve_strike is
##             the one formula; this file must never grow a second one.
##   EMIT    — one frame per tick, the REDESIGNED stream (#33): pos/hp/state plus INTENT and
##             REASON straight from each unit's tree, and the per-unit decision log at the end.
##             The renderer derives NOTHING.
##
## ⚠️ DETERMINISM CONTRACT: one injected RNG consumed in unit-id order, integer ticks, no clock,
## no engine physics. Same seed + same inputs -> byte-identical frames. The probe hashes it.
##
## ⚠️ SCOPE, STATED HONESTLY: movement, targeting, basic-attack strikes, casts/kicks, deaths,
## victory — and now FIELD STATUSES: application through the contracted StatusMath (DR, CON
## floor, refresh/stacking), per-tick behaviour through the contracted Tick (DoT attrition,
## doom detonate, CC-meter decay), hard control (stun/sleep freeze everything, silence blocks
## casts, fear blocks swings), and the table-driven passives (speedMult, accPenalty,
## damageTakenMult, breaksOnDamage, bonusVsStatus detonation) — and THE SUPPORT LAYER:
## friendly casts (heal/ward/guard/timed atk-def-acc-dodge mods/cleanse, targets self/ally/team),
## timed MODS living on the unit and expiring through the contracted Tick, wards as absorb pools
## consumed by resolve_strike's defWard input, and enemy stat debuffs (defDebuff/atkDebuff/
## accDebuff) applied as timed mods on a landed hit — and PROJECTILES (#34): ranged/magic
## hostile casts launch a shot on completion and their outcome APPLIES on arrival (see the
## note below) — and THE AOE LAYER (## AOE LAYER marks): allEnemies AoE geometry (a BURST
## resolved per living enemy within the move's authored range of the CASTER), tauntForce
## compulsion feeding the tree's Taunted branch, and thorns' flat melee reflect. Still layering
## on next: innate auras, charm's turncoat, confusion's veer steering, knockback displacement
## (its speedMult ticks; the SHOVE needs the flight machinery), spreadStatus contagion.
##
## ⚠️ STATUS RNG DRAW ORDER (part of the determinism contract): a cast completion draws
## acc/crit/variance as before, then — ONLY when the move carries a `status` block AND the
## accuracy roll hit — ONE further draw for the status chance. Same accuracy gate for damage
## and status (no double jeopardy); a miss draws nothing extra. Reordering or
## unconditionalising that draw changes every fight that follows it.
## ⚠️ FRIENDLY CASTS DRAW ZERO RNG. A heal/buff/cleanse on your own side cannot miss and cannot
## crit (matching the legacy team-effect path, which rolled nothing), so completing one consumes
## no draws — every fight without support in play is byte-identical to before the layer existed.
## ⚠️ PROJECTILES (#34/#20) DO NOT CHANGE THE DRAW ORDER. A ranged/magic hostile cast still
## draws acc/crit/variance at CAST COMPLETION (now the LAUNCH), and the conditional status draw
## (the 4th, hit-gated) is taken IMMEDIATELY after, at that same completion tick — the identical
## stream positions the instant path always used. What moves is APPLICATION TIMING only: the
## fully resolved outcome rides the projectile and lands at ARRIVAL. Accuracy is AIM QUALITY
## (decision #20, no double jeopardy): the acc roll resolves at launch — a failed roll launches
## a shot aimed at where the target STOOD at launch, so the viewer watches it sail through empty
## ground; a passed roll homes and hits on arrival. Projectile advancement draws ZERO rng.
## ⚠️ PER-MOVE PROJECTILES AND PIERCE DRAW ZERO RNG EITHER. The authored {speed, width, pierce}
## block (kit.gd, from `tools/authorprojectiles.ts`) changes only how FAST and how WIDE a shot
## flies. A shot that passes through a body re-resolves against that body's own armour using the
## SAME acc/crit/variance the shot was loosed with — carried on the projectile, not re-rolled —
## because a per-body draw would insert a geometry-dependent number of draws into the stream,
## which is the one thing this contract cannot absorb. `pierce` defaults to 0 and an unauthored
## move falls back to the verbatim channel constant, so the axis is inert until data turns it on.
## ⚠️ AOE LAYER RNG CONTRACT (allEnemies casts): a completed allEnemies cast is a BURST from the
## caster — it never takes the projectile branch (a burst has no single flight path) — and it
## draws PER TARGET, in unit-id order (`units` is id-sorted): acc/crit/variance for that
## target's strike, then — only when the move authors a `status` block AND that target's acc
## roll hit — the one status-chance draw, i.e. the standard 3(+1) block repeated per target.
## The falloff input to resolve_strike is aoe_falloff(N) where N is the count of living enemies
## inside the move's authored range of the CASTER at resolution time (the legacy gate,
## spatial_sim.gd:1077-1086: an AoE reaches only what the move's own range covers, measured
## from the caster). Fights without an allEnemies cast draw exactly as before the layer landed.
## tauntForce application and thorns reflect draw ZERO rng.
## ⚠️ THE SUSTAIN BRAKES DRAW ZERO RNG AND CHANGE NO DRAW ORDER. `dampening()` is a pure
## function of the tick counter, and the stagnation ratchet's second arm signal is a pure
## comparison of two tick counters — neither touches the stream, so every fight that resolves
## inside DAMPEN_ARM_TICKS with kills landing is byte-identical to before they existed
## (verified: nine of sixteen matchups in _sweep_comps.gd are unchanged to the tick).
extends RefCounted

const BT = preload("res://scripts/ai/bt.gd")
const CombatTree = preload("res://scripts/ai/combat_tree.gd")
const NavService = preload("res://scripts/sim/nav_service.gd")
const Sp = preload("res://scripts/spatial.gd")      # constants only — the sim never calls its movement
const KitLib = preload("res://scripts/sim/kit.gd")  # constants only — see KIT_RANGE_LIFT
const Damage = preload("res://scripts/damage.gd")
const Derive = preload("res://scripts/derive.gd")
const StatusMathLib = preload("res://scripts/status_math.gd")  # the ONE status rulebook
const TickLib = preload("res://scripts/tick.gd")               # the ONE per-tick rulebook

const DT := 0.1                 # fixed step, matches Sp.DT — never frame delta
const DECISION_EVERY := 5       # decision tick = 0.5s; movement executes every tick
const BODY_RADIUS := 2.65       # agreed with the renderer (spatial.gd) — MUST equal Sp.BODY_RADIUS
## ⚠️ "AGREED WITH THE RENDERER" IS NO LONGER TRUE, AND THE GAP IS WHY A 5v5 SCRUM IS A PILE.
## Measured 2026-08-09 (round 13, `docs/WATCH_AUDIT.md` §0 is the symptom): enemies stand at
## `BODY_RADIUS * 2` = 4.4 ground units = **1.50 world units** at `arena_3d.WORLD_SCALE` 0.34,
## while a creature is drawn `UNIT_HEIGHT` 4.4 world units tall and roughly 2.3–2.6 wide. Bodies
## therefore interpenetrate by ~40% of their drawn width BY CONSTRUCTION, and no camera, plate or
## colour work can separate them — round 13 tried all three.
##
## ⚠️ AND THE OBVIOUS FIX DOES NOT FIT, WHICH IS THE ACTUAL FINDING. Focus fire (the sim's own
## preferred behaviour, and now named on the scoreboard) rings N attackers around one target at
## that radius. Ringing five bodies of drawn width w without overlap needs a radius of about
## 0.85w ≈ 2.0 world units ≈ **5.9 ground units** — but `BASE_REACH`, the melee basic, is **6.6**.
## Separation and reach are within 12% of each other, so there is no value for one that does not
## either keep the pile or push melee out of its own swing range. **The pair has to move
## together** (`GEOMETRY_SCALE`), or the drawn bodies have to shrink. Either is a balance change
## with a spatial-probe re-baseline behind it, not a renderer edit.
##
## MEASURED NEGATIVE, so nobody pays for it twice: raising `ALLY_MIN_SEP` alone from `*2.0` to
## `*3.2` moved nothing a viewer can see (fight footprint 166x74 → 152x69, units in frame 71% →
## 74%, and the scrum capture is visually identical). The pile is made of ENEMIES converging on
## one body, not of allies crowding each other. Reverted.
##
## ⚠️ RESOLVED ROUND 24, AND THE "OBVIOUS FIX DOES NOT FIT" READING ABOVE WAS THE ANSWER, NOT THE
## OBSTACLE. It said separation and reach are within 12% of each other so no value for one works
## alone, and **the pair has to move together**. They did, in one edit: BODY_RADIUS 2.2 -> 2.65
## (both files), SLOT_RADIUS 4.8 -> 5.6, BASE_REACH 6.6 -> 7.95. The ratios that make the geometry
## coherent are PRESERVED rather than tuned — every one of them is the same number it was:
##   body ring 2*BODY_RADIUS   4.40 -> 5.30    SLOT_RADIUS / body ring    1.091 -> 1.057
##   SLOT_RADIUS               4.80 -> 5.60    SLOT_RADIUS / BASE_REACH   0.727 -> 0.704
##   BASE_REACH                6.60 -> 7.95    BASE_REACH / body ring     1.500 -> 1.500
## and `SLOT_RADIUS < BASE_REACH * 0.95` — the constraint that keeps a body AT its slot inside its
## own swing — goes from 0.67u of margin to 1.95u. `docs/SPATIAL_BALANCE.md` §5 names G4 (melee vs
## ranged must not invert) as the row where a thin margin there would show up as a lost matchup;
## lifting BASE_REACH with the body is what buys that margin back.
##
## ⚠️ BASE_REACH IS **NOT** LIFTED TO THE FULL CHANNEL_RANGE MELEE (26.4), AND THAT IS A DESIGN
## CALL WITH A REASON, NOT AN OVERSIGHT. Round 23's own note says melee closing ALL THE WAY while
## ranged stands off at 74-96u "is precisely the engagement stagger the middle needs". A melee
## basic that reaches 26.4 stops the charge 26 units out, deletes the scrum, and destroys the one
## shape the round-23 lift was built to create. Melee reach is a BODY geometry — it scales with
## the body (x1.205, exactly), not with the board's separations.
const MAX_TICKS := 1800         # 3 min hard stop (fight length is emergent, #11)
const BASE_REACH := 7.95        # melee basic: 1.5x the body ring, lifted with BODY_RADIUS (r24)
const BASIC_COOLDOWN := 12      # ticks between basic attacks (1.2s)

## Healing multiplier when the target is healblocked — `src/battle.ts:430` (via battle_sim.gd).
## The heal itself is the field heal rule from the same line: round(power * 1.2 * mult).
const HEALBLOCK_MULT := 0.4

## §2A addendum (docs/AUTOBATTLER_DESIGN.md): healing feeds the THREAT ledger at this fraction,
## so a healer becomes VISIBLE to the `threat` priority without out-shouting the damage dealers.
## WoW's answer to the same problem; explicitly a tuning knob, not a derived number.
const HEAL_THREAT_MULT := 0.5

## MOVEMENT FEEL — the constants that make the fight read as bodies, not sliding chips.
const SLOT_COUNT := 6           # surround slots per target, 60° apart: the chord of a hexagonal
								#  ring EQUALS its radius, so 5.6 — above ALLY_MIN_SEP (5.30), so
								#  a full ring never fights the ally soft-avoid
const SLOT_RADIUS := 5.6        # where an attacker stands: above the enemy body ring (2*2.65=5.3)
								#  so the push-out never fights the slot, below BASE_REACH*0.95
								#  (7.55) so a unit AT its slot is always in reach. Lifted 4.8 ->
								#  5.6 with BODY_RADIUS in round 24 — see the ⚠️ block above.
const SLOT_SETTLE := 1.2        # close enough to the slot to stop strafing and stand
const MAX_ACCEL := 30.0         # u/s² — rest to full speed in ~3 ticks; kills the zigzag without
								#  making starts feel drunk
const TURN_RATE := 5.0          # rad/s turn cap while far from the aim point: paths render as
								#  curves. ⚠️ NEVER make this unconditional —
const TURN_RELAX_DIST := 6.0    #  — inside this of the aim point the cap LIFTS. The old sim's
								#  fixed turn cap at speed orbited the target forever.
const WAYPOINT_RADIUS := 1.5    # advance the path index when this close; the velocity model
								#  rounds corners instead of snapping exactly onto waypoints
const ENEMY_PUSH_MAX := 0.9     # max enemy-overlap resolved per tick — deep overlaps resolve
								#  over a few ticks instead of one teleport
const ALLY_MIN_SEP := BODY_RADIUS * 2.0  # allies are PASSABLE (#22) but drift apart to this —
								#  engages at the same ring as enemies so crossing paths still
								#  read as two bodies, but the FORCE below stays soft
## ⚠️ 0.4 -> 1.0 AND 0.5 -> 0.9, ROUND 24 — THE FORCE, NOT THE TARGET, AND THAT DISTINCTION IS THE
## WHOLE FIX. The measured negative above raised ALLY_MIN_SEP (the TARGET separation) from *2.0 to
## *3.2 and moved nothing; it was reverted, correctly. What it did not try is the other term: a
## soft-avoid that resolves 40% of an overlap per tick, capped at 0.5u, is competing every tick
## against a slot anchor and a cast anchor that pull the body straight back, and it loses the
## equilibrium. Allies were standing 24.9% inside each other's DRAWN bodies at rest (worst 54.0%,
## `_probe_watch` D2) while ENEMIES — whose push-out resolves ALL of the overlap at a 0.9 cap —
## sat at 12.1%. Same geometry, same anchors, four-times-weaker force, twice the overlap.
##
## ⚠️ AND THEY ARE STILL PASSABLE (#22). This changes how firmly two STANDING allies drift apart,
## not whether a moving ally can walk through one: the target is unchanged at ALLY_MIN_SEP and
## `crossing` overlap is motion and stays motion. MEASURED, before -> after (`_probe_watch`, same
## roster, windowed): allies at rest mean 24.9% -> 12.5%, p90 51.8% -> 22.1%; enemies at rest
## 12.1% -> 8.3%, which is the first time the "mean under ~10%" acceptance number has been met.
## ⚠️ THE WORST-CASE WENT THE OTHER WAY — one pair at 54.0% -> 75.8% — and it is ONE episode
## (Azurefin standing 0.73 world inside Grynt) rather than a distribution: the mean and the p90
## both roughly halved. A single deep pair is a body that arrived under an anchor and is being
## pushed out over the next few ticks, which is what the per-tick cap is for. Reported rather than
## smoothed away, because the round that hides its one bad number is the round nobody can audit.
const ALLY_SOFT_FRAC := 1.0     # fraction of ally overlap resolved per tick (enemy: all of it)
const ALLY_PUSH_MAX := 0.9      # cap on that drift per tick (enemy cap: 0.9 — now the same)
## ⚠️ THE ANTI-TELEPORT CEILING IS DERIVED, NEVER A LITERAL — and this constant being a literal
## was the single most expensive bug in the spatial layer. It sat at 1.8 (18.0 u/s at DT 0.1)
## while `spatial.gd`'s injected ladder runs SPEED_MIN 20.0 to SPEED_MAX 39.2: THE ENTIRE LADDER,
## FLOOR INCLUDED, SAT ABOVE THE CEILING, so every monster moved at exactly 18.0 u/s and the DEX
## speed stat bought NOTHING. spatial.gd carries the paired A/B that proved it (same seeds, same
## comps, speeds scaled +42% and +70%: fronts met at 11.5 / 11.3 / 11.2s — identical to 0.1s —
## with the realised fastest tick pinned at 1.80u), and TWO deliberate retunings of
## TARGET_CLOSE_SECONDS were measured as no-ops because of it.
##
## So the ceiling now comes from the speeds the caller actually injected, computed per fight in
## setup(). A tripwire must sit ABOVE every legal movement and below an actual teleport; deriving
## it from the fastest body plus the separation pushes guarantees the first half by construction,
## which a literal cannot do on a board whose scale keeps changing.
const TICK_MOVE_SAFETY := 1.25  # headroom over (fastest speed * DT) for the same-tick push-out
const TICK_MOVE_FLOOR := 1.8    # the historic value, kept as a lower bound for tiny-speed tests

## STAGNATION PRESSURE — the anti-turtle rule. Two hold/guard remnants out of each other's
## reach would otherwise stand at their anchors forever (measured: caster_peel/seed3333, both
## sides parked 65 units apart from tick ~285 to the cap). When NO damage lands for
## STAGNATION_ARM_TICKS, the sim GROWS the published `hold_radius` each tick.
## ⚠️ The pressure is a RATCHET: landed damage only PAUSES the growth — a DEATH resets it.
## Resetting on mere damage was tried first and produced approach-exchange-retreat oscillation
## (the leash snapped back after every exchange and the remnants disengaged again, whittling
## slower than the cap). Deaths are the one signal the fight genuinely progressed.
const HOLD_RADIUS_BASE := 8.0        # must match the tree's hold default
const STAGNATION_ARM_TICKS := 150    # 15s of silence arms the pressure
const STAGNATION_LEASH_RATE := 0.1   # leash growth per stagnant tick (1 u/s per side)

## ⚠️ THE RATCHET WAS BLIND TO HALF OF ITS OWN PROBLEM, AND THE SWEEP FOUND IT.
## The arm condition above is SILENCE. scripts/sim/_sweep_comps.gd measured a second stall
## shape it cannot see: two hold-heavy lines standing 76 units apart, trickling ranged damage
## at each other forever. Damage lands constantly, so `last_damage_tick` keeps refreshing and
## the leash never grows — but nobody is dying either. The sweep's engagement column separates
## the two cleanly (share of ticks the sides are within melee reach):
##     RESOLVING matchups   56% .. 87% engaged, 5.0 .. 8.3 deaths, 20s .. 33s
##     STALLING  matchups    3% .. 20% engaged, 2.0 .. 7.0 deaths, all at or near the cap
## Every stall in the 4x4 is a POSTURE stall first. So the ratchet arms on either signal now:
## silence, OR no DEATH for STAGNATION_NO_KILL_TICKS. That is not a new philosophy — the block
## above already states that deaths are the one signal a fight genuinely progressed; this makes
## the ARM condition agree with the RESET condition instead of using two different clocks.
const STAGNATION_NO_KILL_TICKS := 200   # 40s without a kill is not a fight, whatever is landing
										#  — deliberately the same grace as DAMPEN_ARM_TICKS, so
										#  both brakes start together and there is ONE number a
										#  reader has to hold: "40 seconds of no progress"

## ═══ DAMPENING — THE SUSTAIN BRAKE ══════════════════════════════════════════════════════════
## Healing, absorbs and HoTs lose effectiveness as a match drags. WoW arena's own answer, under
## its own name, for exactly this failure — and WoW arena is this project's stated reference.
##
## ⚠️ MEASURED, NOT ASSUMED. scripts/sim/_sweep_comps.gd (4 archetypes x 4, 3 seeds, 48 fights)
## before this constant existed:
##     sustain vs sustain   1800/1800/1800 ticks — AT CAP, ZERO deaths, heal/dmg ratio 0.98
##     sustain vs pressure   277 ticks, 6.3 deaths     pressure mirror   235 ticks, 8.0 deaths
##     sustain vs balanced   905 ticks (one seed at the cap)
## Five-a-side sustain healed EXACTLY as fast as five-a-side damage arrived, so the mirror could
## not resolve at any length. It is a STRUCTURAL draw, not a tuning miss: moderating the stat
## floors moved it barely at all (docs/COMBAT_SPATIAL_LOG.md, 2026-08-08).
##
## ⚠️ TWO CANDIDATE BRAKES WERE MEASURED AND REJECTED, so nobody re-proposes them:
##  • HEALER MANA. The sweep prints the lowest mana fraction any healer reached: **0.00** in the
##    sustain mirror. The healers were ALREADY running dry and healing anyway — regen refills
##    them fast enough that being broke is not a brake. Mana is spent, not scarce.
##  • THE EXISTING STAGNATION RATCHET. It arms on SILENCE (STAGNATION_ARM_TICKS of no landed
##    damage), and the mirror was never silent — 6.7 dmg/s landed for the full 180s. Damage was
##    landing constantly and nobody was dying. A silence clock cannot see that fight at all.
## What both misses have in common: the failure is not "no damage", it is "no PROGRESS". So the
## brake is keyed on MATCH TIME, the one clock that always runs.
##
## ⚠️ MONOTONIC IN FIGHT TIME, AND IT NEVER RESETS — deliberately unlike the stagnation ratchet,
## which resets on a death. Two reasons. (1) LEGIBILITY, which is load-bearing in a game the
## player cannot intervene in: "after 40 seconds healing gets weaker, and keeps getting weaker"
## is one sentence a viewer can hold and predict. A brake that released on every kill would make
## the back half of a long fight unpredictable. (2) A resetting brake re-stalls: the sustain
## mirror would grind to one kill, release, and grind again.
##
## The curve: nothing at all for the first DAMPEN_ARM_TICKS, then healing falls DAMPEN_RATE per
## tick to a floor of DAMPEN_FLOOR. Chosen so a HEALTHY fight is never touched — the longest
## non-degenerate fight in the pre-change sweep was 489 ticks, where the multiplier is 0.87 —
## while the degenerate ones are closed well inside the cap.
const DAMPEN_ARM_TICKS := 400    # 40s of grace; every resolving matchup in the sweep is shorter
const DAMPEN_RATE := 0.0018      # per tick past the arm point (1.8% of healing per second)
const DAMPEN_FLOOR := 0.15       # healing never reaches zero — a healer stays worth fielding
								 #  (floor reached at tick 872, i.e. 87s in)

var nav: NavService
var rng: RandomNumberGenerator
var units: Array = []           # ordered by id — the determinism order
var frames: Array = []
var tick_now := 0
var winner := ""
## Per-fight anti-teleport ceiling, derived in setup() from the injected speeds (see the
## TICK_MOVE_SAFETY block). Never read before setup() runs.
var max_tick_move := TICK_MOVE_FLOOR
var last_damage_tick := 0       # last tick any strike/cast landed — pauses stagnation growth
var stagnation_level := 0.0     # the pressure ratchet: grows in silence, resets ONLY on a death
var last_progress_tick := 0     # last tick anything DIED — the no-kill arm clock (see above)
var projectiles: Array = []     # in-flight shots (#34), in LAUNCH order (launches happen in
								#  unit-id order per tick, so append order is deterministic)

## unit: {id, team ("A"/"B"), pos: Vector2, stats: {STR..CHA}, speed, tactics: Dictionary,
##        personality: {nerve, focus_sticky}}  — everything injected, nothing global.


func setup(seed_val: int, in_units: Array, ground: Vector2, obstacles: Array) -> void:
	rng = RandomNumberGenerator.new()
	rng.seed = seed_val
	nav = NavService.new()
	nav.build(ground, obstacles, BODY_RADIUS)
	units = []
	projectiles = []
	for u in in_units:
		var stats: Dictionary = u["stats"]
		units.append({
			"id": str(u["id"]), "team": str(u["team"]),
			"pos": u["pos"], "home": u["pos"],
			"stats": stats,
			"hp": Derive.max_hp(float(stats.get("CON", 10))),
			"max_hp": Derive.max_hp(float(stats.get("CON", 10))),
			"speed": float(u.get("speed", 8.0)),
			"tactics": u.get("tactics", {}),
			"nerve": int(u.get("personality", {}).get("nerve", 50)),
			"aggression": int(u.get("personality", {}).get("aggression", 50)),
			"focus_sticky": float(u.get("personality", {}).get("focus_sticky", 1.3)),
			"tree": CombatTree.build(u.get("tactics", {})),
			"bb": _fresh_bb(),
			"path": PackedVector2Array(), "path_i": 0,
			"cooldown": 0, "has_attacked": false, "alive": true,
			"mp": Derive.max_mana(float(stats.get("WIS", 10)), float(stats.get("INT", 10))),
			"max_mp": Derive.max_mana(float(stats.get("WIS", 10)), float(stats.get("INT", 10))),
			"kit": u.get("kit", []), "cds": {}, "casting": {},
			"statuses": [], "cc_resist": 0.0, "last_cc_at": -999.0,
			"mods": [],       # timed atk/def/acc/dodge/ward/guard/regen mods — tick.gd expires them
			"dmg_from": {},   # attacker id -> decaying recent damage (the THREAT ledger)
			"heal_done": 0.0,  # recent healing OUTPUT (decays like dmg_from; feeds enemies[i].heal_out)
			"kite_ticks": int(u.get("kite_budget", 80)),  # #39: kiting ENDS - 8s default budget
			"facing": Vector2(1, 0) if str(u["team"]) == "A" else Vector2(-1, 0),
			"vel": Vector2.ZERO,          # smoothed velocity — movement feel state
			"slot_angle": 0.0, "slot_ok": false,  # this tick's surround slot, if attacking
		})
	units.sort_custom(func(a, b): return a.id < b.id)
	# Derive the anti-teleport ceiling from the fastest body actually in this fight, plus the
	# separation pushes that can land on the same tick. Ordered max over an id-sorted array —
	# deterministic, and it cannot fall below the historic floor.
	var fastest := 0.0
	for u in units:
		fastest = maxf(fastest, float(u.speed))
	max_tick_move = maxf(TICK_MOVE_FLOOR,
		fastest * DT * TICK_MOVE_SAFETY + ENEMY_PUSH_MAX + ALLY_PUSH_MAX)  # id order IS the tick order


func _fresh_bb() -> BT.Blackboard:
	var bb := BT.Blackboard.new()
	bb.rng = rng  # the ONE rng — trees must draw from the same deterministic stream
	return bb


## Run the whole fight synchronously (nav must be ready — host awaits until_ready first).
func run() -> Dictionary:
	assert(nav.is_ready(), "await nav.until_ready() before run()")
	while tick_now < MAX_TICKS and winner == "":
		_step()
	var logs := {}
	for u in units:
		logs[u.id] = u.bb.decision_log()
	return {"winner": winner, "ticks": tick_now, "frames": frames, "decision_logs": logs}


func _step() -> void:
	var events: Array = []
	# DECIDE — on the decision tick, refill each blackboard and run the tree.
	if tick_now % DECISION_EVERY == 0:
		for u in units:
			if u.alive:
				_fill_bb(u)
				u.tree.tick(u.bb, tick_now)
	# EXECUTE — every tick: surround slots, then movement toward the requested point, then strikes.
	_assign_slots()
	for u in units:
		if not u.alive:
			continue
		if u.casting.is_empty():
			_execute_move(u)
		else:
			u.vel = Vector2.ZERO  # a cast is a full commitment — no residual drift after it ends
	for u in units:
		if not u.alive:
			continue
		for a in u.dmg_from.keys():
			u.dmg_from[a] = float(u.dmg_from[a]) * 0.985   # ~2s half-life at 10Hz
		u.heal_done = float(u.heal_done) * 0.985   # same ~2s half-life as the threat ledger
		# STATUS TICK — the CONTRACTED per-tick rulebook (tick.gd), never inlined here: mana
		# regen (same wis/200 formula the old inline line used), DoT attrition (burn/bleed
		# hpPerSec, poison mpPerSec — poison drains MANA, that is the authored table), doom's
		# detonate-on-expiry, status expiry, CC-meter decay. Cooldowns stay tick-integers on
		# this side: pass none, keep ours.
		var tout: Dictionary = TickLib.tick_unit({
			"dt": DT, "now": tick_now * DT, "statuses": u.statuses, "mods": u.mods,
			"cooldowns": {}, "wis": float(u.stats.get("WIS", 10)), "isSupport": false,
			"mp": u.mp, "maxMp": float(u.max_mp), "hp": float(u.hp), "maxHp": float(u.max_hp),
			"ccResist": u.cc_resist, "lastCcAt": u.last_cc_at,
		})
		u.hp = tout["hp"]
		u.mp = tout["mp"]
		u.statuses = tout["statuses"]
		# The contracted Tick expires mods (`now < until`) and pays their regen/hpRegen at the
		# authored per-ROUND rate divided by SECONDS_PER_ROUND — never re-derived here.
		u.mods = tout["mods"]
		u.cc_resist = tout["ccResist"]
		# ⚠️ STAGNATION CHOICE, DOCUMENTED: DoT ticks are DELIBERATELY absent from the
		# ratchet's pause list (it scans strike/cast_done only). The strike or cast that
		# APPLIED the status already paused it when it landed; a lone dot ticking on a
		# turtled remnant is not fight progress. A DoT DEATH still resets it — the death
		# pass below does not care what killed you.
		if float(tout["attrition"]) > 0.0:
			events.append({"kind": "status_tick", "to": u.id, "dmg": float(tout["attrition"])})
		for kind in tout["expired"]:
			events.append({"kind": "status_expire", "to": u.id, "status": str(kind)})
		for k in u.cds.keys():
			u.cds[k] = maxi(0, int(u.cds[k]) - 1)
		_execute_cast(u, events)
	for u in units:
		if not u.alive:
			continue
		_execute_attack(u, events)
	# PROJECTILES (#34) advance after every launch this tick, in launch order. Zero rng.
	_advance_projectiles(events)
	# Stagnation clock: a landed hit PAUSES the ratchet (miss/fizzle does not — silence is
	# silence); growth happens below only after ARM ticks of real silence. Deaths reset it
	# further down, once they are detected.
	# ⚠️ STAGNATION x HEALING, THE CHOICE DOCUMENTED: 'heal'/'buff'/'cleanse'/'ward_soak' are
	# DELIBERATELY absent from this pause list. A team sustaining itself while landing nothing
	# is not fight progress — if support casts paused the ratchet, a healer alone could hold a
	# turtled remnant unresolvable forever. Damage still pauses it and only a death resets it,
	# so a sustain-heavy fight comes under the same growing leash as any other stalemate.
	# 'cast_done' fires at the LAUNCH of a will-hit shot and 'proj_hit' when it LANDS (#34) —
	# both pause: the launch is committed damage, the arrival is the damage actually landing,
	# and the gap between them is one flight (≤ ~1s), so this only ever moves last_damage_tick
	# by flight time. Misses and fizzles pause nothing, exactly as cast_miss never did.
	for e in events:
		if str(e.kind) in ["strike", "cast_done", "proj_hit"]:
			last_damage_tick = tick_now
	# TWO ARM SIGNALS, one ratchet (see STAGNATION_NO_KILL_TICKS): no damage landing at all, or
	# damage landing with nothing to show for it. Either way the leash grows until it drags the
	# lines together; a death still releases it below.
	if (tick_now - last_damage_tick > STAGNATION_ARM_TICKS
			or tick_now - last_progress_tick > STAGNATION_NO_KILL_TICKS):
		stagnation_level += STAGNATION_LEASH_RATE
	# Deaths and victory.
	var alive_a := 0
	var alive_b := 0
	for u in units:
		if u.alive and u.hp <= 0:
			u.alive = false
			events.append({"kind": "death", "id": u.id})
			# A death IS progress, so the ratchet RELEASES — but only halfway, and that is a
			# measured correction. Zeroing it made the leash a sawtooth: the sustain mirror
			# scored 3.7 kills, each one dropped the leash to nothing, the lines drifted back
			# apart and the clock spent another 20s re-arming, so engagement never rose above
			# 14% and the fight still hit the cap. Halving keeps the release legible (a kill
			# visibly buys the survivors room) while the pressure RATCHETS — the fifth stall is
			# tighter than the first. ⚠️ Costs nothing in a healthy fight: the leash never arms
			# there, so this is 0.0 * 0.5 and every resolving matchup in the sweep is
			# byte-identical across the change.
			stagnation_level *= 0.5
			last_damage_tick = tick_now
			last_progress_tick = tick_now
		if u.alive:
			if u.team == "A":
				alive_a += 1
			else:
				alive_b += 1
	if alive_a == 0 or alive_b == 0:
		winner = "draw" if alive_a == 0 and alive_b == 0 else ("A" if alive_b == 0 else "B")
	_emit_frame(events)
	tick_now += 1


func _fill_bb(u: Dictionary) -> void:
	var bb: BT.Blackboard = u.bb
	bb.set_value("_tick_now", tick_now)
	bb.set_value("self", {"id": u.id, "pos": u.pos, "hp": u.hp, "max_hp": u.max_hp, "speed": u.speed})
	var enemies: Array = []
	var allies: Array = []
	var enemy_line_x := 0.0
	var n_enemy := 0
	for o in units:
		if o.id == u.id:
			continue
		var rec := {"id": o.id, "pos": o.pos, "hp": o.hp if o.alive else 0, "max_hp": o.max_hp,
			"int_stat": o.stats.get("INT", 0), "wis": o.stats.get("WIS", 0),
			"con": o.stats.get("CON", 0), "threat": 0.0}
		if o.team == u.team:
			allies.append(rec)
		else:
			# WISHLIST keys, now filled (contract at top of combat_tree.gd):
			#   threat   — recent damage THIS enemy dealt ME (my own ledger row);
			#   casting  — committed to a cast (feeds the opportunistic kick);
			#   team_dmg — recent damage MY TEAM dealt this enemy, summed in unit-id
			#              order (float addition order is part of determinism);
			#   statuses — this enemy's live AILMENTS as minimal {kind} records, in apply
			#              order. Filtered SIM-SIDE by the beneficial table (the tree has
			#              no status rulebook): a buff on an enemy is not combo setup.
			#              Feeds the combo policy's setup_status_live derivation. Minimal
			#              records on purpose — no timers/payloads for the tree to lean on.
			#              No rng, no new iteration order: pure read, deterministic.
			rec["threat"] = float(u.dmg_from.get(o.id, 0.0))
			#   heal_out — recent healing OUTPUT by this enemy (its own decaying ledger), so
			#              the `healers` priority can SEE a healer (§2A addendum).
			rec["heal_out"] = float(o.get("heal_done", 0.0))
			rec["casting"] = o.alive and not o.casting.is_empty()
			var team_dmg := 0.0
			for t in units:
				if t.team == u.team:
					team_dmg += float(o.dmg_from.get(t.id, 0.0))
			rec["team_dmg"] = team_dmg
			var ail: Array = []
			if o.alive:
				for s in o.statuses:
					if not (str(s["kind"]) in _beneficial_statuses()):
						ail.append({"kind": str(s["kind"])})
			rec["statuses"] = ail
			enemies.append(rec)
			if o.alive:
				enemy_line_x += o.pos.x
				n_enemy += 1
	bb.set_value("enemies", enemies)   # already id-ordered because units is
	bb.set_value("allies", allies)
	bb.set_value("home_pos", u.home)
	bb.set_value("safe_pos", u.home)   # v1: safety is the deployment anchor
	bb.set_value("enemy_line_x", enemy_line_x / maxf(1.0, float(n_enemy)))
	bb.set_value("nerve", u.nerve)
	bb.set_value("aggression", u.aggression)   # 0-100 personality; 50 = every multiplier 1.0
	bb.set_value("focus_sticky", u.focus_sticky)
	bb.set_value("kick_range", INTERRUPT_REACH)  # advertise the ENFORCED reach — never two numbers
	# Stagnation pressure (see the constants block): the ratchet grows in silence, pauses on
	# damage, releases on a death. Always SET both keys — a stale grown radius surviving a
	# reset would leak the pressure.
	bb.set_value("hold_radius", HOLD_RADIUS_BASE + stagnation_level)
	bb.set_value("stagnation_pressure", stagnation_level > 0.0)
	# Cast/interrupt context (the WoW-arena layer): is my current target committed to a cast,
	# and is my kick off cooldown? The tree decides to spend it; the sim executes.
	var tgt = _unit(str(bb.get_value("target_id", "")))
	bb.set_value("target_casting", tgt != null and tgt.alive and not tgt.casting.is_empty())
	bb.set_value("kite_ticks_left", u.kite_ticks)
	var near_d := INF
	for o2 in units:
		if o2.alive and o2.team != u.team:
			near_d = minf(near_d, u.pos.distance_to(o2.pos))
	bb.set_value("nearest_enemy_dist", near_d)
	# A status that blocks the action makes it read NOT-ready — the tree must not hold position
	# for a cast the sim will refuse (stun blocks both; silence blocks casts, not the kick).
	bb.set_value("interrupt_ready", not _incapacitated(u) and _ready_move(u, "interrupt") != "")
	bb.set_value("cast_ready", not _casts_blocked(u) and _ready_move(u, "cast") != "")
	# Guard/peel context: who is hurting my CHARGE right now? The charge's own threat ledger
	# answers it - ties break by id order (strict >), determinism as always.
	var gid: String = str(u.tactics.get("guard_ally", ""))
	bb.set_value("guard_id", gid)
	if gid != "":
		var charge = _unit(gid)
		if charge != null and charge.alive:
			bb.set_value("charge_pos", charge.pos)
			var best_att := ""
			var best_v := 0.0
			for a in _ledger_keys_sorted(charge):
				var v: float = float(charge.dmg_from[a])
				var att = _unit(str(a))
				if att != null and att.alive and att.team != u.team and v > best_v:
					best_v = v
					best_att = str(a)
			bb.set_value("charge_attacker_id", best_att)
		else:
			bb.set_value("charge_attacker_id", "")
	## AOE LAYER: tauntForce fills the tree's Urgent → Taunted branch — "" when no live taunt
	## (expired, or the taunter fell: battle.ts:982, the compulsion breaks). Zero rng, pure read.
	bb.set_value("taunted_by", _taunt_source_of(u))
	# orders arrive here when the tactics screen wires in (v1: keys absent).


## THE DAMPENING MULTIPLIER — see the DAMPEN_* block for the measurement that justifies it.
## A pure function of the tick counter: zero rng, no state, no iteration order, so it cannot
## touch determinism. `at` defaults to now; the probe calls it at chosen ticks to pin the curve.
func dampening(at: int = -1) -> float:
	var t: int = tick_now if at < 0 else at
	if t <= DAMPEN_ARM_TICKS:
		return 1.0
	return maxf(DAMPEN_FLOOR, 1.0 - DAMPEN_RATE * float(t - DAMPEN_ARM_TICKS))


## Dictionary key order is insertion order in Godot, which depends on hit history - SORT before
## iterating a ledger anywhere a decision hangs on it.
func _ledger_keys_sorted(u: Dictionary) -> Array:
	var ks: Array = u.dmg_from.keys()
	ks.sort()
	return ks


## ATTACK SLOTS / SURROUND — melee converging on one target fan out into an arc instead of
## stacking into one pixel. Each attacker of a target gets one of SLOT_COUNT ring positions,
## assigned in unit-id order (the determinism order): nearest slot to its current bearing,
## bumping outward alternately (+1,-1,+2,-2…) when taken. Runs every tick; the quantized
## bearing keeps assignments stable as units strafe into place.
func _assign_slots() -> void:
	var by_target := {}   # target id -> attackers, in unit-id order because units is
	for u in units:
		u.slot_ok = false
		if not u.alive or not u.casting.is_empty():
			continue
		var tid: String = str(u.bb.get_value("req_attack", u.bb.get_value("target_id", "")))
		if tid == "":
			continue
		var tgt = _unit(tid)
		if tgt == null or not tgt.alive:
			continue
		if not by_target.has(tid):
			by_target[tid] = []
		by_target[tid].append(u)
	var tids: Array = by_target.keys()
	tids.sort()   # Dictionary order is insertion order — sort before any decision hangs on it
	for tid in tids:
		var tgt2 = _unit(tid)
		var step: float = TAU / float(SLOT_COUNT)
		var taken := {}
		for u in by_target[tid]:
			var to_u: Vector2 = u.pos - tgt2.pos
			var bearing: float = to_u.angle() if to_u.length() > 0.001 else u.facing.angle() + PI
			var base: int = posmod(int(roundf(bearing / step)), SLOT_COUNT)
			var chosen: int = base   # >SLOT_COUNT attackers on one body: latecomers share
			for probe in [0, 1, -1, 2, -2, 3]:
				var cand: int = posmod(base + probe, SLOT_COUNT)
				if not taken.has(cand):
					chosen = cand
					break
			taken[chosen] = true
			u.slot_angle = float(chosen) * step
			u.slot_ok = true


## VELOCITY SMOOTHING — steer toward `aim` under an accel cap and a turn-rate cap, so paths
## render as curves, not zigzags. ⚠️ The turn cap RELAXES inside TURN_RELAX_DIST: the old
## sim's fixed turn cap at speed orbited the target forever — never re-tighten it near goals.
## `face_along` false = STRAFE: the caller owns facing (locked on the target) while move_dir
## follows actual motion — the two decouple on the stream exactly here.
func _steer(u: Dictionary, aim: Vector2, face_along: bool) -> void:
	# Statuses scale speed via the table (haste 1.35, fear 1.15, knockback 0.6) — read fresh
	# each tick, never cached on the unit, so expiry takes effect the tick it happens.
	var spd: float = u.speed * _speed_mult_of(u)
	var to_aim: Vector2 = aim - u.pos
	var d: float = to_aim.length()
	if d < 0.001:
		u.vel = Vector2.ZERO
		return
	var desired: Vector2 = to_aim / d * spd
	if d < spd * DT:
		desired = to_aim / DT   # arrival: ask only for the closing speed, never overshoot
	var cur: Vector2 = u.vel
	if cur.length() > 0.1 and d > TURN_RELAX_DIST:
		var max_turn: float = TURN_RATE * DT
		var ang: float = cur.angle_to(desired)
		if absf(ang) > max_turn:
			desired = cur.rotated(signf(ang) * max_turn).normalized() * spd
	var dv: Vector2 = desired - cur
	var max_dv: float = MAX_ACCEL * DT
	if dv.length() > max_dv:
		dv = dv / dv.length() * max_dv
	u.vel = cur + dv
	if u.vel.length() > spd:
		u.vel = u.vel / u.vel.length() * spd   # nothing outruns its own (status-scaled) speed
	u.pos += u.vel * DT
	if face_along and u.vel.length() > 0.05:
		u.facing = u.vel / u.vel.length()


func _execute_move(u: Dictionary) -> void:
	var bb: BT.Blackboard = u.bb
	var prev_pos: Vector2 = u.pos
	# HARD CONTROL: an incapacitated body (stun/sleep, table-driven) does not steer, kite or
	# chase — but pushes still resolve, because other bodies do not stop being solid.
	if _incapacitated(u):
		u.vel = Vector2.ZERO
		_resolve_pushes(u, prev_pos)
		return
	var dest = bb.get_value("req_move_to", null)
	var tid: String = str(bb.get_value("req_attack", bb.get_value("target_id", "")))
	var tgt = _unit(tid)
	var engaged: bool = tgt != null and tgt.alive
	# Heading AT the target? Aim for the surround slot, not the target's centre — three
	# attackers arrive as an arc, not a stack. Distant destinations (wings/dive waypoints,
	# retreats) are the tree's business and pass through untouched.
	# ⚠️ attacking_dest gates the WHOLE slot/strafe layer: a unit whose tree ordered it AWAY
	# (kite, flee, escape) must never be hijacked into orbiting the enemy standing in its reach
	# — that bug locked a kiter to its chaser and the kite probe caught it.
	var attacking_dest: bool = engaged and dest != null \
		and (dest as Vector2).distance_to(tgt.pos) < BASE_REACH
	if attacking_dest and bool(u.slot_ok):
		dest = tgt.pos + Vector2.from_angle(float(u.slot_angle)) * SLOT_RADIUS
	if engaged and (dest == null or attacking_dest) \
			and u.pos.distance_to(tgt.pos) <= BASE_REACH * 0.95:
		# In reach: FACE the target no matter how we move (strafe decouples facing/move_dir).
		u.facing = (tgt.pos - u.pos).normalized() if u.pos != tgt.pos else u.facing
		var slot_pos: Vector2 = tgt.pos + Vector2.from_angle(float(u.slot_angle)) * SLOT_RADIUS
		if bool(u.slot_ok) and u.pos.distance_to(slot_pos) > SLOT_SETTLE:
			_steer(u, slot_pos, false)   # strafe into the slot, eyes on the target
		else:
			u.vel = Vector2.ZERO         # in position — stand and fight
	elif dest == null:
		u.vel = Vector2.ZERO
	else:
		# (Re)path when the goal moved meaningfully or the path ran out.
		var need_path: bool = u.path.size() == 0 or u.path_i >= u.path.size() \
			or u.path[u.path.size() - 1].distance_to(dest) > 3.0
		if need_path:
			u.path = nav.path(u.pos, dest)
			u.path_i = 0
		while u.path_i < u.path.size() and u.pos.distance_to(u.path[u.path_i]) <= WAYPOINT_RADIUS:
			u.path_i += 1
		if u.path_i < u.path.size():
			_steer(u, u.path[u.path_i], true)
		else:
			u.vel = Vector2.ZERO
	# #39: the kite budget SPENDS while genuinely kiting - moving away from the nearest
	# enemy while it is close enough to matter. Structural: no speed tuning involved.
	var nearest = null
	var nd := INF
	for o2 in units:
		if o2.alive and o2.team != u.team:
			var dd: float = u.pos.distance_to(o2.pos)
			if dd < nd:
				nd = dd
				nearest = o2
	if nearest != null and nd < 14.0:
		var before: float = float(prev_pos.distance_to(nearest.pos))
		if u.pos.distance_to(nearest.pos) > before + 0.05:
			u.kite_ticks = maxi(0, u.kite_ticks - 1)
	_resolve_pushes(u, prev_pos)


## Overlap resolution, ALWAYS run (even standing still or stunned — someone may have walked
## into us): solid ENEMY bodies (#10/#22) push out hard but capped per tick; ALLIES are
## passable but drift apart softly when overlapping — a gentler force than the enemy push-out.
func _resolve_pushes(u: Dictionary, prev_pos: Vector2) -> void:
	for o in units:
		if not o.alive or o.id == u.id:
			continue
		var delta: Vector2 = u.pos - o.pos
		var dist := delta.length()
		if dist <= 0.001:
			continue
		if o.team != u.team:
			var min_d := BODY_RADIUS * 2.0
			if dist < min_d:
				u.pos += delta / dist * minf(min_d - dist, ENEMY_PUSH_MAX)
		elif dist < ALLY_MIN_SEP:
			u.pos += delta / dist * minf((ALLY_MIN_SEP - dist) * ALLY_SOFT_FRAC, ALLY_PUSH_MAX)
	# The anti-teleport tripwire, enforced at the source: whatever movement plus pushes summed
	# to this tick, nothing displaces more than the DERIVED ceiling (see TICK_MOVE_SAFETY).
	var moved: Vector2 = u.pos - prev_pos
	if moved.length() > max_tick_move:
		u.pos = prev_pos + moved / moved.length() * max_tick_move


## First kit move of `kind` that is off cooldown, affordable and — for a FRIENDLY move — has
## something useful to do, or "". The usefulness gate is sim-side on purpose: the tree's
## `req_cast_allowed` flows unchanged, and a heal with nobody wounded simply reads not-ready,
## so the kit falls through to its next move instead of dribbling overheals.
func _ready_move(u: Dictionary, kind: String) -> String:
	for m in u.kit:
		if str(m.get("kind", "cast")) != kind:
			continue
		if int(u.cds.get(str(m.name), 0)) > 0:
			continue
		if float(u.mp) < float(m.get("mana", 0)):
			continue
		if _is_friendly_entry(m) and not _friendly_useful(u, m):
			continue
		return str(m.name)
	return ""


func _kit_move(u: Dictionary, name: String) -> Dictionary:
	for m in u.kit:
		if str(m.name) == name:
			return m
	return {}


# ═══ FRIENDLY CASTS — heals, wards, timed mods, cleanse ══════════════════════════════════════
# A buff-type kit move casts EXACTLY like any cast (same commitment, same stillness, same kick
# vulnerability, mana paid at start) but resolves against the caster's own side. No rng draws
# (see the header note). Effects become timed MODS: the shapes and the rounds->seconds
# conversion are the legacy field engine's (`battle_sim.gd:_apply_team_effect`, itself the port
# of `src/battle.ts:resolveUtilityOnTarget`), durations via the contracted
# Derive.rounds_to_seconds. Every mod carries `src` (the move name) so re-casting cannot stack
# an identical mod the target already wears.

## Mod keys the sim expresses, in the legacy engine's own names. kit.gd's acceptance list must
## stay in lock-step with this mapping.
const MOD_OF_EFFECT := {
	"atkBuff": "atkMultBonus", "defBuff": "defMitDebuff", "accBuff": "accMod",
	"dodgeBuff": "dodgeMod", "ward": "ward", "guard": "guard",
	"hpRegenBuff": "hpRegen", "regenBuff": "regen",
	"thorns": "thorns",  ## AOE LAYER: flat melee reflect, worn as a timed mod (see _reflect_thorns)
}

static var _beneficial_cache: Array = []


## ⚠️ LOADED AS DATA, NEVER TRANSCRIBED (the status_math.gd lesson): battle.ts:423 cleanses
## everything EXCEPT the beneficial set, and data.json carries that set.
static func _beneficial_statuses() -> Array:
	if _beneficial_cache.is_empty():
		var f := FileAccess.open("res://data/data.json", FileAccess.READ)
		if f == null:
			push_error("cannot open res://data/data.json — run ./run_contract.sh")
			return []
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary and parsed.has("beneficialStatuses"):
			_beneficial_cache = parsed["beneficialStatuses"]
	return _beneficial_cache


## The DATA move a kit entry carries, or an inline shape built from the entry (test kits).
func _move_of_entry(m: Dictionary) -> Dictionary:
	if m.get("move") is Dictionary:
		return m["move"]
	return {"name": str(m.get("name", "")), "power": float(m.get("power", 0)),
		"accuracy": float(m.get("accuracy", 100)), "type": str(m.get("type", "damage")),
		"channel": str(m.get("channel", "magic")), "effects": m.get("effects", {}),
		"status": m.get("status", null), "target": str(m.get("target", "enemy"))}


func _entry_target(m: Dictionary) -> String:
	return str(_move_of_entry(m).get("target", "enemy"))


func _is_friendly_entry(m: Dictionary) -> bool:
	return _entry_target(m) in ["self", "ally", "team"]


func _sum_mods(u: Dictionary, key: String) -> float:
	var t := 0.0
	for mod in u.mods:
		t += float(mod.get(key, 0.0))
	return t


func _has_mod_from(u: Dictionary, src: String) -> bool:
	for mod in u.mods:
		if str(mod.get("src", "")) == src:
			return true
	return false


func _has_cleansable(u: Dictionary) -> bool:
	for s in u.statuses:
		if not (str(s["kind"]) in _beneficial_statuses()):
			return true
	return false


## The living units a friendly entry would touch RIGHT NOW, in unit-id order (units is sorted).
## "ally" means someone ELSE where possible — the legacy resolver's rule — falling back to self.
func _friendly_recipients(u: Dictionary, m: Dictionary) -> Array:
	var reach := _entry_reach(m)   # the completed lift — see KIT_RANGE_LIFT
	match _entry_target(m):
		"self":
			return [u]
		"team":
			var team: Array = []
			for o in units:
				if o.alive and o.team == u.team and u.pos.distance_to(o.pos) <= reach:
					team.append(o)
			return team
		_:
			var best = null
			var best_frac := INF
			for o in units:
				if not o.alive or o.team != u.team or o.id == u.id:
					continue
				if u.pos.distance_to(o.pos) > reach:
					continue
				# Lowest hp-FRACTION living ally in range; id-order tiebreak (strict <, and
				# units is already id-sorted, so the first of a tie wins).
				var frac: float = float(o.hp) / float(o.max_hp)
				if frac < best_frac:
					best_frac = frac
					best = o
			return [best] if best != null else [u]


## Would this friendly cast DO anything? Any component counting: a heal with someone actually
## wounded, a cleanse with something to scrub, or a timed mod the recipient is not already
## wearing from this same move.
func _friendly_useful(u: Dictionary, m: Dictionary) -> bool:
	var mv := _move_of_entry(m)
	var fx = mv.get("effects")
	var fxd: Dictionary = fx if fx is Dictionary else {}
	var spec = mv.get("status")
	for r in _friendly_recipients(u, m):
		if float(mv.get("power", 0)) > 0.0 and float(r.hp) < float(r.max_hp) - 0.5:
			return true
		if bool(fxd.get("cleanse", false)) and _has_cleansable(r):
			return true
		for key in MOD_OF_EFFECT:
			if fxd.has(key) and not _has_mod_from(r, str(mv.get("name", ""))):
				return true
		if spec is Dictionary and not _has_status(r, str((spec as Dictionary).get("kind", ""))):
			return true
	return false


## Resolve a completed friendly cast — heal, then mods, then cleanse, per recipient. The heal is
## the field heal rule (battle.ts:430): round(power * 1.2), x HEALBLOCK_MULT under a blockHeal
## status (table-driven, never a hardcoded name). Emits 'heal' (from/to/amount — the shape
## _watch_sim.gd's scoreboard aggregates), 'buff', and 'cleanse' events.
func _resolve_friendly(u: Dictionary, kentry: Dictionary, events: Array) -> void:
	var mv := _move_of_entry(kentry)
	var fx = mv.get("effects")
	var fxd: Dictionary = fx if fx is Dictionary else {}
	var power := float(mv.get("power", 0))
	for r in _friendly_recipients(u, kentry):
		if power > 0.0:
			var mult: float = HEALBLOCK_MULT if _has_rule_flag(r, "blockHeal") else 1.0
			# DAMPENING (the sustain brake) multiplies the field heal rule's output. It stacks
			# multiplicatively with healblock — two different reasons a heal is worth less.
			var heal: float = round(power * 1.2 * mult * dampening())
			var before: float = float(r.hp)
			r.hp = minf(float(r.max_hp), float(r.hp) + heal)
			events.append({"kind": "heal", "from": u.id, "to": r.id,
				"move": str(kentry.name), "amount": int(float(r.hp) - before)})
			var healed: float = float(r.hp) - before   # EFFECTIVE heal — overheal is not visibility
			if healed > 0.0:
				u.heal_done = float(u.heal_done) + healed
				# §2A addendum: healing feeds the THREAT ledger at HEAL_THREAT_MULT, split evenly
				# across living enemies (units is id-sorted — iteration order is deterministic).
				var living_enemies: Array = units.filter(func(t): return t.alive and t.team != u.team)
				if not living_enemies.is_empty():
					var share: float = HEAL_THREAT_MULT * healed / float(living_enemies.size())
					for t in living_enemies:
						t.dmg_from[u.id] = float(t.dmg_from.get(u.id, 0.0)) + share
		var mod := {"until": tick_now * DT + Derive.rounds_to_seconds(float(fxd.get("duration", 1))),
			"src": str(mv.get("name", kentry.name))}
		var applied := false
		for key in MOD_OF_EFFECT:
			if fxd.has(key):
				# defBuff is NEGATIVE defMitDebuff (more mitigation), the legacy sign convention.
				var v := float(fxd[key])
				# DAMPENING reaches the other two forms of the SAME currency — an absorb shield
				# and a heal-over-time are healing paid in advance and healing paid in
				# instalments. Damping only the direct heal would just move the sustain comp
				# onto wards (the measured mirror already leaned on Bastion/Interpose/Ward
				# Against Ruin). ⚠️ Deliberately NOT damped: `guard` (flat damage reduction, not
				# a pool), `defBuff` (mitigation), `regenBuff` (MANA regen) — dampening is about
				# restoring HP, and widening it past that would be a second, unmeasured change.
				if key in ["ward", "hpRegenBuff"]:
					v *= dampening()
				mod[MOD_OF_EFFECT[key]] = -v if key == "defBuff" else v
				applied = true
		if applied and not _has_mod_from(r, str(mod["src"])):
			r.mods.append(mod)
			events.append({"kind": "buff", "from": u.id, "to": r.id,
				"move": str(kentry.name), "seconds": float(mod["until"]) - tick_now * DT})
		# An authored status on a FRIENDLY move (Battle Hymn's haste — the only one in the pool)
		# lands through the contracted rulebook but WITHOUT a chance draw: friendly casts draw
		# zero rng (header note), so the chance is treated as certain. ⚠️ If a future friendly
		# move authors chance < 100 this must grow a documented draw, not silently keep 100.
		var spec = _move_of_entry(kentry).get("status")
		if spec is Dictionary and r.alive:
			var sout: Dictionary = StatusMathLib.apply_status({
				"kind": str((spec as Dictionary)["kind"]), "statuses": r.statuses,
				"ccResist": r.cc_resist, "targetDead": not r.alive,
				"rounds": float((spec as Dictionary).get("duration", 1)),
				"now": tick_now * DT, "ccImmuneUntil": -999.0,
				"targetCon": float(r.stats.get("CON", 0)), "from": u.id,
			})
			if bool(sout["applied"]):
				r.statuses = sout["statuses"]
				events.append({"kind": "status_applied", "to": r.id, "from": u.id,
					"status": str((spec as Dictionary)["kind"]), "seconds": float(sout["seconds"])})
		if bool(fxd.get("cleanse", false)):
			# battle.ts:423 — a cleanse scrubs every AILMENT and keeps the beneficial set.
			var broken: Array = []
			var kept: Array = []
			for s in r.statuses:
				if str(s["kind"]) in _beneficial_statuses():
					kept.append(s)
				else:
					broken.append(str(s["kind"]))
			if not broken.is_empty():
				r.statuses = kept
				events.append({"kind": "cleanse", "from": u.id, "to": r.id,
					"move": str(kentry.name), "broke": broken})


const CAST_RANGE := 30.0        # fallback for kit entries with NO authored range (hand-built
								#  test kits only — every data move authors one)

## ═══ THE RANGE-LIFT COMPLETION (round 14) — why the fight had no middle ══════════════════════
## ⚠️ MEASURED, NOT INFERRED (`_probe_sim_quality.gd`, `_reach_vs_separation` + `_opening`, on
## the real 440x246 board): first attempt, first damage and the fronts physically crossing were
## the SAME MOMENT (7.2-8.4s) in every comp, because the widest reach any kit fielded was 24.2u
## against a 391.6u deploy separation — 6% of the walk. Nothing could open fire during the
## approach, so 30-49% of every watched fight was a silent walk (`WATCH_AUDIT.md` §0) and then
## everything landed at once.
##
## THE CAUSE IS A HALF-APPLIED SCALE LIFT — the fifth-scale-bug shape, again. Authored move
## ranges live on the pool's original 40x22 board (Volley 8.4-11.0, magic ~7). The design lift
## onto the real ground is `Spatial.REACH_SCALE` = 4.0 x GEOMETRY_SCALE = x8.8 (`reach_of`,
## which the superseded spatial_sim used). `kit.gd` lifts by GEOMETRY_SCALE alone — x2.2 — so
## every authored reach arrived at a QUARTER of its designed length. This constant completes
## the lift at the point of consumption: 2.2 x 4.0 = 8.8, so Volley reaches 74-96.8u and the
## approach becomes a closing-under-fire phase — the exact shape `ENGAGEMENT_DESIGN.md` wants
## and `spatial.gd`'s TARGET_CLOSE_SECONDS note promised ("reach now runs to 96 units").
##
## ⚠️ PAID, ROUND 24 — AND THE TRAP DID NOT SPRING. The lift now lives ENTIRELY in `kit.gd`
## (`RANGE_LIFT` = Sp.REACH_SCALE, with the HARD_REACH_MAX clamp), and `_entry_reach` below was
## reduced to a plain read IN THE SAME EDIT, which is the only version of this change that is a
## no-op. Verified as one: the §1 AoE census in `docs/SPATIAL_BALANCE.md` prints every live
## radius, and all 27 were byte-identical before and after (Ricochet 78.3, median 45.8, Smoke
## Bomb 21.1), with the seven `_probe_sim_quality` frame hashes unchanged across three processes.
##
## ⚠️ THE CONSTANT BELOW IS NOW DOCUMENTATION AND AN EXTERNAL RESTATEMENT, NOT A MULTIPLIER THE
## SIM APPLIES. `_probe_balance.gd` and `_probe_sim_quality.gd` restate the arithmetic from a RAW
## data move (`range x GEOMETRY_SCALE x KIT_RANGE_LIFT`) to census the pool without building kits;
## it stays derived from `kit.gd` so the two can never drift. Nothing in `sim.gd` reads it.
##
## ⚠️ AND THE SEMANTICS OF `entry.range` CHANGED WITH IT: it is now a REAL-BOARD DISTANCE, already
## lifted and already clamped. A hand-built kit entry (probe fixtures, `_probe_sim.gd`'s support
## kits at 40.0) is therefore taken at face value instead of being quadrupled to the clamp — which
## is the honest reading and was measured to leave `_probe_sim` and `_probe_combat_tree` green.
##
## ⚠️ MELEE IS DELIBERATELY NOT TOUCHED. BASE_REACH (6.6 = 3.0 x GEOMETRY_SCALE) is on the same
## wrong scale — the design melee basic is 26.4 (CHANNEL_RANGE) — but BASE_REACH is welded to
## the surround-slot geometry (SLOT_RADIUS < BASE_REACH*0.95 > body ring) and to the scrum-pile
## finding at the top of this file: separation and melee reach must move TOGETHER, with the
## body-radius re-baseline, not as a rider on this change. Melee closing all the way while
## ranged stands off 74-96u is also precisely the engagement stagger the middle needs.
const KIT_RANGE_LIFT := KitLib.RANGE_LIFT / KitLib.GEOMETRY_SCALE   # 8.8 / 2.2 = 4.0


## The reach of a kit entry, on the REAL board's scale — A PLAIN READ since round 24: `kit.gd`
## has already applied the full lift and the HARD_REACH_MAX clamp. Entries with no range at all
## (hand-built test kits) keep the CAST_RANGE fallback verbatim.
##
## ⚠️ THE CLAMP STAYS HERE AS WELL, AND THAT IS NOT THE DEBT COMING BACK. The debt was a
## MULTIPLIER split across two files — apply it twice and every reach quadruples. A clamp is
## IDEMPOTENT: applying `min(r, HARD_REACH_MAX)` after kit.gd already applied it changes nothing,
## and it keeps the design ceiling enforced for hand-built entries that never passed through
## kit.gd (probe fixtures) and for anything that perturbs `entry.range` in place. Measured: with
## the clamp here the consolidation is byte-identical everywhere INCLUDING `_probe_balance`'s C1
## canary; without it C1's x2.5 arm read 2.59 instead of 2.44, because the perturbation had
## escaped the ceiling. That is the difference between a no-op and an almost-no-op.
func _entry_reach(m: Dictionary) -> float:
	var r := float(m.get("range", 0.0))
	if r <= 0.0:
		return CAST_RANGE
	return minf(r, Sp.HARD_REACH_MAX)

## PROJECTILE FLIGHT (#34) — speeds taken VERBATIM from the superseded spatial layer's authored
## constants (scripts/spatial.gd:301, under its "projectiles (2026-08-06)" banner): ranged 90
## ("an arrow: fast, barely dodgeable"), magic 55 ("a fireball: slower than an arrow"), in
## world-units/second. Channels absent from this table (melee / voice / support) stay INSTANT —
## a shout has no flight — and FRIENDLY casts never reach this branch at all (touch/aura, not
## shots; the friendly path resolves and returns before the channel check).
const PROJECTILE_SPEED := {"ranged": 90.0, "magic": 55.0}
const INTERRUPT_LOCKOUT := 30   # ticks (3s) the kicked school stays locked, WoW-style
const INTERRUPT_CD := 100       # ticks (10s) between kicks - a kick is a RESOURCE
const INTERRUPT_REACH := BASE_REACH * 1.4  # the kick's real reach — published to the tree as
									# bb `kick_range`; enforcement and advertisement must match


## Casts: begin when the tree allows and a kit cast is ready; complete after cast_time through
## the CONTRACTED maths; die to a kick. A casting unit stands still - the commitment is the
## legible tell the whole layer exists for.
func _execute_cast(u: Dictionary, events: Array) -> void:
	var bb: BT.Blackboard = u.bb
	if not u.casting.is_empty():
		var tgt = _unit(str(u.casting.target))
		if tgt == null or not tgt.alive:
			events.append({"kind": "fizzle", "from": u.id, "move": str(u.casting.move.name)})
			u.casting = {}
		elif tick_now >= int(u.casting.ends):
			var kentry: Dictionary = u.casting.move
			# FRIENDLY CASTS resolve on their own path: no rolls, no rng, no strike — heal,
			# mods and cleanse per recipient. Cooldown starts here like any completed cast.
			if bool(u.casting.get("friendly", false)):
				_resolve_friendly(u, kentry, events)
				u.cds[str(kentry.name)] = int(float(kentry.get("cooldown", 4.0)) / DT)
				u.casting = {}
				return
			## AOE LAYER: an allEnemies move resolves against GEOMETRY — every living enemy
			## inside the move's authored range of the CASTER — never the single anchor target,
			## and never the projectile branch (a burst has no single flight path). Per-target
			## draws in unit-id order; see the AOE LAYER rng contract in the header.
			if _entry_target(kentry) == "allEnemies":
				_resolve_aoe(u, kentry, events)
				u.cds[str(kentry.name)] = int(float(kentry.get("cooldown", 4.0)) / DT)
				u.casting = {}
				return
			# The DATA move goes into resolve_strike verbatim when this kit entry carries one
			# (kit.gd path); hand-built test kits still describe themselves inline.
			var mv: Dictionary = kentry.get("move", {"name": str(kentry.name),
				"power": float(kentry.get("power", 30)), "accuracy": float(kentry.get("accuracy", 100)),
				"type": "damage", "channel": str(kentry.get("channel", "magic")), "effects": {},
				"status": kentry.get("status", null)})
			# bonusVsStatus arms BEFORE the strike (the status it detonates is consumed after).
			var bvs_armed: bool = _bonus_status_armed(mv, tgt)
			# ⚠️ THE ROLLS ARE HOISTED INTO A LOCAL so a piercing shot can CARRY them (#34).
			# Draw order is UNCHANGED — a dictionary literal evaluates its values left to right,
			# exactly as this one statement does — so this hoist is not an rng change. What it
			# buys: a shot that passes through a second body re-resolves against that body's OWN
			# armour using these SAME three dice. One shot, one set of dice, zero new draws.
			var rolls := {"acc": rng.randf(), "crit": rng.randf(), "variance": rng.randf()}
			var out: Dictionary = Damage.resolve_strike(
				_strike_inputs(u, tgt, mv, str(kentry.get("stat", "INT")), rolls, bvs_armed))
			u.cds[str(kentry.name)] = int(float(kentry.get("cooldown", 4.0)) / DT)
			# ⚠️ THE 4TH DRAW — the hit-gated status roll, taken HERE for BOTH the instant and
			# the projectile path so its stream position never moves (see the header note).
			# -1.0 means "no draw happened": no status authored, or the acc roll missed.
			var status_roll := -1.0
			if bool(out.get("hit", false)) and mv.get("status") is Dictionary:
				status_roll = rng.randf()
			var chan := str(mv.get("channel", "magic"))
			if PROJECTILE_SPEED.has(chan):
				# PROJECTILE (#34): the resolved outcome rides the shot and APPLIES at arrival.
				# A power-0 magic/ranged control move flies too — its status rides the bolt,
				# which is the causally readable version of "the hex reached you".
				var will_hit := bool(out.get("hit", false))
				# ⚠️ THE AUTHORED BLOCK WINS, THE CHANNEL CONSTANT IS THE FALLBACK. kit.gd
				# attaches {speed, width_radii, pierce} per move; an unauthored move (or a
				# hand-built test kit, which carries no `projectile` at all) gets exactly the
				# channel number this branch used before the field existed, width 0 and pierce
				# 0 — i.e. today's behaviour, verbatim. The two gates must agree: this branch is
				# still taken on the CHANNEL, never on the presence of the block (kit.gd says so).
				var pj: Dictionary = kentry.get("projectile", {})
				projectiles.append({
					"from": u.id, "target_id": tgt.id, "pos": u.pos,
					"speed": float(pj.get("speed", PROJECTILE_SPEED[chan])),
					"kname": str(kentry.name),
					"move": mv, "out": out, "will_hit": will_hit, "aim_pos": tgt.pos,
					"bvs_armed": bvs_armed, "status_roll": status_roll,
					"launched_at": tick_now,
					# THE PIERCE STATE. `width` is in BODY RADII (kit.gd owns the unit and the
					# name says so); `pierce_left` counts ADDITIONAL bodies the shot may still
					# pass through; `hit_ids` stops one shot touching one body twice across two
					# flight ticks. All three are inert at their defaults.
					"width": float(pj.get("width_radii", 0.0)),
					"pierce_left": int(pj.get("pierce", 0)),
					"hit_ids": [],
					# Carried so the pierce path can re-resolve without a second copy of the
					# formula inputs and without a single new draw.
					"rolls": rolls, "stat": str(kentry.get("stat", "INT")),
				})
				events.append({"kind": "proj_launch", "from": u.id, "to": tgt.id,
					"move": str(kentry.name), "will_hit": will_hit})
				if will_hit:
					# cast_done stays the COMMITTED-damage event at completion (the watch
					# scoreboard aggregates its dmg); the hp actually moves on 'proj_hit'
					# at arrival — the probe pins hp-drop-tick > cast_done-tick.
					events.append({"kind": "cast_done", "from": u.id, "to": tgt.id,
						"move": str(kentry.name), "dmg": int(out.get("dmg", 0)),
						"crit": bool(out.get("crit", false))})
				# An aimed MISS (#20) says nothing at launch — its cast_miss is emitted where
				# the shot expends, so the sail-through moment IS the event's moment.
			elif bool(out.get("hit", false)):
				_apply_strike_outcome(u, tgt, mv, str(kentry.name), out, bvs_armed,
					status_roll, "cast_done", events)
			else:
				events.append({"kind": "cast_miss", "from": u.id, "to": tgt.id, "move": str(kentry.name)})
			u.casting = {}
		return
	if bool(bb.get_value("req_interrupt", false)):
		bb.set_value("req_interrupt", false)
		var iname := _ready_move(u, "interrupt")
		var tid: String = str(bb.get_value("target_id", ""))
		var tgt = _unit(tid)
		# Incapacitated blocks the kick; SILENCE does not — the kick is a boot, not a spell.
		if iname != "" and not _incapacitated(u) and tgt != null and tgt.alive \
				and not tgt.casting.is_empty() \
				and u.pos.distance_to(tgt.pos) <= INTERRUPT_REACH:
			var locked: String = str(tgt.casting.move.name)
			tgt.casting = {}
			# +1: the victim's own cooldown decrement runs later THIS SAME tick and would eat
			# one tick of the lockout - found by the probe's exact-window check (29 of 30).
			tgt.cds[locked] = maxi(int(tgt.cds.get(locked, 0)), INTERRUPT_LOCKOUT + 1)
			u.cds[iname] = INTERRUPT_CD
			events.append({"kind": "interrupt", "from": u.id, "to": tid, "locked": locked})
			return
	if bool(bb.get_value("req_cast_allowed", false)) and not _casts_blocked(u):
		var cname := _ready_move(u, "cast")
		var tid2: String = str(bb.get_value("target_id", ""))
		var tgt2 = _unit(tid2)
		var mvx: Dictionary = _kit_move(u, cname) if cname != "" else {}
		# FRIENDLY CAST START — same commitment and interruptibility as any cast, but the target
		# is our own side: the picked recipient for "ally", the caster itself for "self"/"team"
		# (a team cast anchors on the caster and fans out at RESOLUTION time). `_ready_move`
		# already guaranteed usefulness and range this same call.
		if cname != "" and _is_friendly_entry(mvx):
			var rec: Array = _friendly_recipients(u, mvx)
			var fid: String = u.id if _entry_target(mvx) in ["self", "team"] else str(rec[0].id)
			u.mp -= float(mvx.get("mana", 0))
			u.casting = {"move": mvx, "target": fid, "friendly": true,
				"started": tick_now, "ends": tick_now + int(float(mvx.get("cast_time", 1.5)) / DT)}
			events.append({"kind": "cast_start", "from": u.id, "to": fid, "move": cname})
			return
		# ⚠️ A NOVA'S USABLE RANGE IS ITS BLAST, NOT ITS CAST RANGE (round 24). `Cleave` is
		# authored at range 4.9 -> 43.1 lifted, but a melee sweep only covers 10.6 around the
		# caster: gate the decision on the cast range and a Warcry kit stands off at 40 units
		# firing bursts that catch nobody and emit `fizzle`. That is the authored-but-unreachable
		# failure in its cheapest form — the ability exists, is affordable, is off cooldown, and
		# can never land. Thrown bursts keep the cast range, which is the number that genuinely
		# limits where they can be placed.
		var cast_range: float = _usable_range(mvx) if not mvx.is_empty() else CAST_RANGE
		# Opportunism: the ordered target when in range; otherwise the nearest IN-RANGE enemy
		# (id-order tiebreak). A caster staring at a distant kill target while an enemy stands
		# on its feet is not focus, it is paralysis — you cast at what you can hit.
		if cname != "" and (tgt2 == null or not tgt2.alive
				or u.pos.distance_to(tgt2.pos) > cast_range
				or u.pos.distance_to(tgt2.pos) < float(mvx.get("min_range", 0.0))):
			var best_d: float = INF
			for o3 in units:
				if o3.alive and o3.team != u.team:
					var d3: float = u.pos.distance_to(o3.pos)
					if d3 <= cast_range and d3 >= float(mvx.get("min_range", 0.0)) and d3 < best_d:
						best_d = d3
						tgt2 = o3
						tid2 = str(o3.id)
		if cname != "" and tgt2 != null and tgt2.alive \
				and u.pos.distance_to(tgt2.pos) <= cast_range \
				and u.pos.distance_to(tgt2.pos) >= float(mvx.get("min_range", 0.0)):
			var mv2: Dictionary = _kit_move(u, cname)
			u.mp -= float(mv2.get("mana", 0))
			u.casting = {"move": mv2, "target": tid2,
				"started": tick_now, "ends": tick_now + int(float(mv2.get("cast_time", 1.5)) / DT)}
			events.append({"kind": "cast_start", "from": u.id, "to": tid2, "move": cname})


## Apply a resolved hostile-cast outcome to its target — shared VERBATIM by the instant path
## (melee/voice channels, applied at cast completion) and the projectile path (applied at
## ARRIVAL, with the rolls that were drawn at launch). `evt_kind` is the damage event emitted
## ("cast_done" for instant, "proj_hit" for arrival). Draws zero rng — the status roll arrives
## pre-drawn (-1.0 = no draw happened, so nothing to apply).
## THE CONTRACTED FORMULA'S INPUT BLOCK, BUILT IN ONE PLACE. Every caller hands the same shape
## to `Damage.resolve_strike` — the ONE damage formula — so the pierce path cannot drift into a
## second, subtly-different copy of it. Pure: reads state, draws no rng (`rolls` arrive already
## drawn, by the caller, in the documented stream position).
##
## Mitigation follows the CHANNEL rule: physical (melee/ranged) vs CON, everything else vs WIS —
## the documented split, not a per-move choice. Timed mods feed the contracted inputs:
## atkMultBonus/accMod on the attacker, defMitDebuff/dodgeMod/guard/ward on the defender.
func _strike_inputs(u: Dictionary, tgt: Dictionary, mv: Dictionary, stat: String,
		rolls: Dictionary, bvs_armed: bool) -> Dictionary:
	var phys: bool = str(mv.get("channel", "magic")) in ["melee", "ranged"]
	var def_stat: float = float(tgt.stats.get("CON", 10)) if phys else float(tgt.stats.get("WIS", 10))
	return {
		"move": mv,
		"rolls": rolls,
		"now": tick_now * DT,
		"atk": float(u.stats.get(stat, 10)),
		"atkMult": 1.0 + _sum_mods(u, "atkMultBonus"),
		"attackerHpFrac": float(u.hp) / float(u.max_hp),
		"attackerWard": _sum_mods(u, "ward"),
		"accPenalty": _acc_penalty_of(u), "accMod": _sum_mods(u, "accMod"),
		"dodgeMod": _sum_mods(tgt, "dodgeMod"), "flankBonus": 0.0, "behindMult": 1.0,
		"falloff": 1.0,
		"defMit": Damage.mitigation_for(def_stat),
		"defMitDebuff": _sum_mods(tgt, "defMitDebuff"), "defDmgTakenMod": 1.0,
		"defStatusDmgTaken": _dmg_taken_of(tgt),
		"defGuard": _sum_mods(tgt, "guard"), "defWard": _sum_mods(tgt, "ward"),
		"defBlocking": false, "defHasAttacked": tgt.has_attacked,
		"defHasBonusStatus": bvs_armed, "defHpFrac": float(tgt.hp) / float(tgt.max_hp),
		"defMaxHp": tgt.max_hp,
	}


func _apply_strike_outcome(u: Dictionary, tgt: Dictionary, mv: Dictionary, kname: String,
		out: Dictionary, bvs_armed: bool, status_roll: float, evt_kind: String, events: Array) -> void:
	tgt.hp -= int(out.get("toHp", 0))
	_drain_ward(u, tgt, out, events)
	# Threat credits the FULL blow — a soaked hit still marks the attacker as the
	# problem (identical to before when no wards exist: toHp == dmg then).
	tgt.dmg_from[u.id] = float(tgt.dmg_from.get(u.id, 0.0)) + float(out.get("dmg", 0))
	events.append({"kind": evt_kind, "from": u.id, "to": tgt.id,
		"move": kname, "dmg": int(out.get("dmg", 0)), "crit": bool(out.get("crit", false))})
	if int(out.get("toHp", 0)) > 0:
		_break_on_damage(tgt, events)
	if bvs_armed:
		_consume_bonus_status(mv, tgt, events)
	_apply_enemy_debuffs(u, tgt, mv, events)
	_apply_taunt(u, tgt, mv, events)         ## AOE LAYER: tauntForce lands here — zero rng
	_reflect_thorns(u, tgt, mv, out, events)  ## AOE LAYER: melee-only flat reflect — zero rng
	if status_roll >= 0.0:
		_apply_status_rolled(u, tgt, mv, events, status_roll)


# ═══ PROJECTILES (#34) ═══════════════════════════════════════════════════════════════════════
# The shot is state, not a node: {from, target_id, pos, speed, move, out, will_hit, aim_pos,
# bvs_armed, status_roll, launched_at}. A will-hit shot HOMES on its target's CURRENT position
# (the autobattler standard — nothing outruns a fireball); an aimed MISS flies to `aim_pos`,
# the target's position AT LAUNCH, and expends in empty ground where the target used to be
# (#20: the miss is visible and causal). Advancement draws zero rng and iterates in launch
# order, which is deterministic because launches happen in unit-id order.


## Advance every in-flight shot one tick and land the ones that arrive. A shot skips its launch
## tick (it spends that tick leaving the caster), so flight is always >= 1 tick and damage can
## never land on the cast_done tick itself.
func _advance_projectiles(events: Array) -> void:
	var kept: Array = []
	for p in projectiles:
		if int(p.launched_at) == tick_now:
			kept.append(p)
			continue
		var tgt = _unit(str(p.target_id))
		# Homing reads the target's CURRENT pos — for a corpse that is its last position, so a
		# shot whose mark died mid-flight still completes its arc there (and fizzles on landing).
		var aim: Vector2 = tgt.pos if bool(p.will_hit) else Vector2(p.aim_pos)
		var step: float = float(p.speed) * DT
		var from_pos: Vector2 = Vector2(p.pos)
		var to_aim: Vector2 = aim - from_pos
		if to_aim.length() <= step:
			p.pos = aim
			# The bodies ON THE WAY resolve before the mark does — they are physically first.
			_pierce_sweep(p, from_pos, aim, events)
			_projectile_land(p, tgt, events)
		else:
			p.pos = from_pos + to_aim / to_aim.length() * step
			_pierce_sweep(p, from_pos, Vector2(p.pos), events)
			kept.append(p)
	projectiles = kept


## PIERCE (#34): the bodies a wide shot passes THROUGH on its way to the mark.
##
## ⚠️ THIS DRAWS ZERO RNG, AND THAT IS THE WHOLE DESIGN, NOT AN OPTIMISATION. The alternative —
## rolling fresh accuracy/crit/variance per incidental body — would insert a variable number of
## draws into the stream at a position that depends on the geometry of the fight, which is the
## one thing the determinism contract cannot absorb. Instead the shot CARRIES the three dice it
## was loosed with and each body it passes applies its OWN armour to them. That is also the more
## honest fiction: one arrow, one release, three sets of ribs.
##
## Two deliberate limits, both so a shot stays legible:
##  • ONLY A WILL-HIT SHOT PIERCES. An aimed miss (#20) missed — it sails through empty ground
##    to where the target used to be, and a shot that failed to find its mark spraying the line
##    behind it would make a miss read like a reward.
##  • ONE BODY, ONCE, EVER (`hit_ids`). Flight spans several ticks and the segments abut, so a
##    body sitting near the line would otherwise be clipped on two consecutive ticks.
## `pierce_left` counts ADDITIONAL bodies, so the default 0 means the sweep does nothing at all
## and every unauthored shot behaves exactly as it did before this function existed.
func _pierce_sweep(p: Dictionary, seg_a: Vector2, seg_b: Vector2, events: Array) -> void:
	if int(p.get("pierce_left", 0)) <= 0 or not bool(p.will_hit):
		return
	var shooter = _unit(str(p.from))
	if shooter == null:
		return
	# The shot's own half-width (authored in BODY RADII) plus the body's radius: the standard
	# capsule-vs-circle test, so "width 0" is a POINT that only ever touches what it homed on.
	var reach: float = float(p.get("width", 0.0)) * BODY_RADIUS + BODY_RADIUS
	var seen: Array = p.hit_ids
	# `units` is id-ordered — the determinism order — so incidental bodies resolve in a fixed
	# sequence regardless of where they happen to stand.
	for other in units:
		if int(p.pierce_left) <= 0:
			break
		if not other.alive or str(other.team) == str(shooter.team):
			continue
		if str(other.id) == str(p.target_id) or seen.has(str(other.id)):
			continue
		if Geometry2D.get_closest_point_to_segment(other.pos, seg_a, seg_b).distance_to(other.pos) > reach:
			continue
		seen.append(str(other.id))
		p.pierce_left = int(p.pierce_left) - 1
		var bvs: bool = _bonus_status_armed(p.move, other)
		var out2: Dictionary = Damage.resolve_strike(
			_strike_inputs(shooter, other, p.move, str(p.stat), p.rolls, bvs))
		if bool(out2.get("hit", false)):
			_apply_strike_outcome(shooter, other, p.move, str(p.kname), out2, bvs,
				float(p.status_roll), "proj_hit", events)
		else:
			# The same dice that beat the mark can still be short of a dodgier body on the way.
			events.append({"kind": "cast_miss", "from": str(p.from), "to": str(other.id),
				"move": str(p.kname)})


## Landing: an aimed miss expends in empty ground (cast_miss, HERE, where the sail-through is
## visible); a will-hit shot whose target died mid-flight expends on the corpse (proj_fizzle);
## a live hit applies the outcome resolved at launch (proj_hit + all its consequences).
func _projectile_land(p: Dictionary, tgt: Dictionary, events: Array) -> void:
	if not bool(p.will_hit):
		events.append({"kind": "cast_miss", "from": str(p.from), "to": str(p.target_id),
			"move": str(p.kname)})
		return
	if tgt == null or not tgt.alive:
		events.append({"kind": "proj_fizzle", "from": str(p.from), "to": str(p.target_id),
			"move": str(p.kname)})
		return
	# The shooter may itself be dead by now — a loosed arrow does not care. _unit still returns
	# the body, whose mods/id are all the application needs.
	var shooter = _unit(str(p.from))
	_apply_strike_outcome(shooter, tgt, p.move, str(p.kname), p.out, bool(p.bvs_armed),
		float(p.status_roll), "proj_hit", events)


func _execute_attack(u: Dictionary, events: Array) -> void:
	if not u.casting.is_empty():
		return  # committed - the stillness and silence ARE the cast
	if u.cooldown > 0:
		u.cooldown -= 1
		return
	# Cooldown ticks FIRST, gate second: being controlled costs tempo, never recovery — the
	# tick.gd lesson (a stagger that pauses every clock becomes a fight-long stalemate).
	# incapacitates (stun/sleep) and noAttack (fear) both stop the swing, per the table.
	if _attack_blocked(u):
		return
	var tid: String = str(u.bb.get_value("req_attack", ""))
	if tid == "":
		return
	var tgt = _unit(tid)
	if tgt == null or not tgt.alive or u.pos.distance_to(tgt.pos) > BASE_REACH:
		return
	# ⚠️ THE ONE FORMULA: the contracted resolve_strike, with the basic-attack move shape.
	# Rolls come from the shared rng IN THIS CALL ORDER — reordering them changes every fight.
	var out: Dictionary = Damage.resolve_strike({
		"move": {"name": "Strike", "power": 12, "accuracy": 95.0, "type": "attack", "channel": "melee", "fx": {}},
		"rolls": {"acc": rng.randf(), "crit": rng.randf(), "variance": rng.randf()},
		"now": tick_now * DT,
		"atk": float(u.stats.get("STR", 10)),
		"atkMult": 1.0 + _sum_mods(u, "atkMultBonus"),
		"attackerHpFrac": float(u.hp) / float(u.max_hp), "attackerWard": 0,
		"accPenalty": _acc_penalty_of(u), "accMod": _sum_mods(u, "accMod"),
		"dodgeMod": _sum_mods(tgt, "dodgeMod"), "flankBonus": 0.0, "behindMult": 1.0,
		"falloff": 1.0,
		"defMit": Damage.mitigation_for(float(tgt.stats.get("CON", 10))),
		"defMitDebuff": _sum_mods(tgt, "defMitDebuff"), "defDmgTakenMod": 1.0,
		"defStatusDmgTaken": _dmg_taken_of(tgt),
		"defGuard": _sum_mods(tgt, "guard"), "defWard": _sum_mods(tgt, "ward"),
		"defBlocking": false, "defHasAttacked": tgt.has_attacked,
		"defHasBonusStatus": false, "defHpFrac": float(tgt.hp) / float(tgt.max_hp),
		"defMaxHp": tgt.max_hp,
	})
	u.cooldown = BASIC_COOLDOWN
	u.has_attacked = true
	u.facing = (tgt.pos - u.pos).normalized() if u.pos != tgt.pos else u.facing
	if bool(out.get("hit", false)):
		tgt.hp -= int(out.get("toHp", 0))
		_drain_ward(u, tgt, out, events)
		tgt.dmg_from[u.id] = float(tgt.dmg_from.get(u.id, 0.0)) + float(out.get("dmg", 0))
		events.append({"kind": "strike", "from": u.id, "to": tid,
			"dmg": int(out.get("dmg", 0)), "crit": bool(out.get("crit", false))})
		if int(out.get("toHp", 0)) > 0:
			_break_on_damage(tgt, events)   # sleep (breaksOnDamage, table-driven) wakes here too
		## AOE LAYER: the basic is melee — a thorny defender punishes it with flat reflect.
		_reflect_thorns(u, tgt, {"channel": "melee"}, out, events)
	else:
		events.append({"kind": "miss", "from": u.id, "to": tid})


func _unit(id: String):
	for o in units:
		if o.id == id:
			return o
	return null


# ═══ FIELD STATUSES ══════════════════════════════════════════════════════════════════════════
# Application goes through the CONTRACTED StatusMath.apply_status (DR, CON floor, refresh takes
# the longer, stacks); per-tick behaviour through the CONTRACTED Tick.tick_unit (in _step).
# ⚠️ EVERYTHING BELOW READS THE fieldStatus TABLE — never a hardcoded status name outside the
# rulebook's own HARD_CONTROL list. Hand-transcribing table rows is the forbidden pattern that
# already bit status_math.gd once.


func _has_status(u: Dictionary, kind: String) -> bool:
	for s in u.statuses:
		if str(s["kind"]) == kind:
			return true
	return false


## Any active status whose table rule sets `flag` truthy (incapacitates / noSkills / noAttack).
func _has_rule_flag(u: Dictionary, flag: String) -> bool:
	for s in u.statuses:
		if bool(StatusMathLib._rule(str(s["kind"])).get(flag, false)):
			return true
	return false


func _incapacitated(u: Dictionary) -> bool:
	return _has_rule_flag(u, "incapacitates")        # stun, sleep


func _casts_blocked(u: Dictionary) -> bool:
	return _incapacitated(u) or _has_rule_flag(u, "noSkills")   # + silence


func _attack_blocked(u: Dictionary) -> bool:
	return _incapacitated(u) or _has_rule_flag(u, "noAttack")   # + fear


func _speed_mult_of(u: Dictionary) -> float:
	var m := 1.0
	for s in u.statuses:
		m *= float(StatusMathLib._rule(str(s["kind"])).get("speedMult", 1.0))
	return m


## Attacker-side accuracy loss (blind 25, confusion 15 — percentage POINTS, per the table).
func _acc_penalty_of(u: Dictionary) -> float:
	var p := 0.0
	for s in u.statuses:
		p += float(StatusMathLib._rule(str(s["kind"])).get("accPenalty", 0.0))
	return p


## Defender-side damage-taken multiplier (vulnerable 1.2) — feeds defStatusDmgTaken.
func _dmg_taken_of(u: Dictionary) -> float:
	var m := 1.0
	for s in u.statuses:
		m *= float(StatusMathLib._rule(str(s["kind"])).get("damageTakenMult", 1.0))
	return m


## WARDS DEPLETE. resolve_strike reported what the target's absorb pool soaked; spend it off
## the target's ward mods in append order, and emit the event so the soak is visible ("viewer-
## facing facts ride the frame stream"). A consumeWard attacker (spendsOwnWard) burns its own
## pool for the bonus it just cashed — the payoff has a cost, matching the legacy engine.
func _drain_ward(u: Dictionary, tgt: Dictionary, out: Dictionary, events: Array) -> void:
	var soaked := int(out.get("wardSoaked", 0))
	if soaked > 0:
		var remaining := float(soaked)
		for mod in tgt.mods:
			if remaining <= 0.0:
				break
			if float(mod.get("ward", 0.0)) > 0.0:
				var take: float = minf(float(mod["ward"]), remaining)
				mod["ward"] = float(mod["ward"]) - take
				remaining -= take
		events.append({"kind": "ward_soak", "from": u.id, "to": tgt.id, "amount": soaked})
	if bool(out.get("spendsOwnWard", false)):
		for mod in u.mods:
			if mod.has("ward"):
				mod["ward"] = 0.0


## Statless enemy debuffs (defDebuff/atkDebuff/accDebuff) become timed mods on a LANDED hit —
## the legacy `_resolve_hit` debuff path, same names, same signs, durations through the
## contracted rounds->seconds. `src` tags them like every mod, so a spammed debuff refreshes
## nothing while its twin is live (the cooldown is the real throttle; this stops double-stack).
func _apply_enemy_debuffs(u: Dictionary, tgt: Dictionary, mv: Dictionary, events: Array) -> void:
	var fx = mv.get("effects")
	if not (fx is Dictionary):
		return
	var fxd: Dictionary = fx
	var mod := {}
	if fxd.has("defDebuff"):
		mod["defMitDebuff"] = float(fxd["defDebuff"])
	if fxd.has("atkDebuff"):
		mod["atkMultBonus"] = -float(fxd["atkDebuff"])
	if fxd.has("accDebuff"):
		mod["accMod"] = -float(fxd["accDebuff"])
	if mod.is_empty():
		return
	var src := str(mv.get("name", ""))
	if _has_mod_from(tgt, src):
		return
	mod["until"] = tick_now * DT + Derive.rounds_to_seconds(float(fxd.get("duration", 1)))
	mod["src"] = src
	tgt.mods.append(mod)
	events.append({"kind": "debuff", "from": u.id, "to": tgt.id, "move": src,
		"seconds": float(mod["until"]) - tick_now * DT})


## Is the move's bonusVsStatus detonator armed — does the target carry the fuel status?
func _bonus_status_armed(mv: Dictionary, tgt: Dictionary) -> bool:
	var e = mv.get("effects")
	if not (e is Dictionary):
		return false
	var bvs = (e as Dictionary).get("bonusVsStatus")
	if not (bvs is Dictionary):
		return false
	return _has_status(tgt, str((bvs as Dictionary).get("kind", "")))


## The detonator SPENDS its fuel: landing a bonusVsStatus hit removes the status it cashed in
## (all of that kind, matching the old sim), so one poison pays out once.
func _consume_bonus_status(mv: Dictionary, tgt: Dictionary, events: Array) -> void:
	var kind := str(((mv.get("effects") as Dictionary).get("bonusVsStatus") as Dictionary).get("kind", ""))
	var kept: Array = []
	for s in tgt.statuses:
		if str(s["kind"]) != kind:
			kept.append(s)
	if kept.size() != tgt.statuses.size():
		tgt.statuses = kept
		events.append({"kind": "status_break", "to": tgt.id, "status": kind, "cause": "consumed"})


## breaksOnDamage (sleep, per the table): any landed hit that reached HP wakes the target.
## ⚠️ DoT ticks do NOT break it — the contracted Tick does not, so neither do we.
func _break_on_damage(tgt: Dictionary, events: Array) -> void:
	if (tgt.statuses as Array).is_empty():
		return
	var kept: Array = []
	for s in tgt.statuses:
		if bool(StatusMathLib._rule(str(s["kind"])).get("breaksOnDamage", false)):
			events.append({"kind": "status_break", "to": tgt.id, "status": str(s["kind"]), "cause": "damage"})
		else:
			kept.append(s)
	tgt.statuses = kept


## Apply the move's authored status using a PRE-DRAWN chance roll (the documented 4th draw —
## taken by _execute_cast at completion, so the projectile path's delayed application never
## moves the draw's stream position). Called ONLY on a landed hit — same accuracy gate as the
## damage, no double jeopardy (#20 analogue).
func _apply_status_rolled(u: Dictionary, tgt: Dictionary, mv: Dictionary, events: Array,
		roll: float) -> void:
	var spec = mv.get("status")
	if not (spec is Dictionary) or not tgt.alive:
		return
	if roll * 100.0 >= float((spec as Dictionary).get("chance", 100.0)):
		return
	var kind := str((spec as Dictionary)["kind"])
	var out: Dictionary = StatusMathLib.apply_status({
		"kind": kind, "statuses": tgt.statuses, "ccResist": tgt.cc_resist,
		"targetDead": not tgt.alive, "rounds": float((spec as Dictionary).get("duration", 1)),
		"now": tick_now * DT, "ccImmuneUntil": -999.0,
		"targetCon": float(tgt.stats.get("CON", 0)), "from": u.id,
	})
	# ⚠️ The DR meter advances even on a REFUSED (fullyDiminished) attempt — that is what stops
	# spam-until-it-sticks being free. Persist the meter before checking `applied`.
	tgt.cc_resist = float(out["ccResist"])
	if bool(out["ccMeterTouched"]):
		tgt.last_cc_at = tick_now * DT
	if not bool(out["applied"]):
		return
	tgt.statuses = out["statuses"]
	events.append({"kind": "status_applied", "to": tgt.id, "from": u.id,
		"status": kind, "seconds": float(out["seconds"])})
	# HARD CONTROL BREAKS A COMMITTED CAST — `status_break`, deliberately DISTINCT from the
	# kick's `interrupt`: no school lockout, no kick cooldown spent, the cast is simply lost.
	if StatusMathLib.HARD_CONTROL.has(kind) and not tgt.casting.is_empty():
		events.append({"kind": "status_break", "to": tgt.id, "from": u.id,
			"move": str(tgt.casting.move.name), "status": kind, "cause": "control"})
		tgt.casting = {}


## The redesigned stream (#33): intent and reason come FROM THE TREE, per unit, per frame.
func _emit_frame(events: Array) -> void:
	var us: Array = []
	for u in units:
		# Renderer-grade state: the stream is the ONLY thing the renderer reads (#33).
		var state := "idle"
		if not u.alive:
			state = "dead"
		elif not u.casting.is_empty():
			state = "cast"
		elif u.pos.distance_to(u.get("prev_pos", u.pos)) > 0.02:
			state = "advance"
		# Statuses ride the frame as kind + remaining SECONDS — the renderer derives nothing,
		# so the countdown it shows is computed here, not there.
		var sts: Array = []
		for s in u.statuses:
			sts.append({"kind": str(s["kind"]), "left": maxf(0.0, float(s["until"]) - tick_now * DT)})
		us.append({
			# hp is float once DoTs tick; the stream shows ceil so a unit at 0.4 reads 1, never
			# a dead-looking 0 that is still fighting.
			"id": u.id, "team": u.team, "pos": u.pos, "hp": int(ceilf(maxf(0.0, float(u.hp)))),
			"alive": u.alive, "statuses": sts,
			"max_hp": u.max_hp, "mp": u.mp, "max_mp": u.max_mp, "state": state,
			"move_dir": (u.pos - u.get("prev_pos", u.pos)).normalized() if u.pos != u.get("prev_pos", u.pos) else Vector2.ZERO,
			"facing": u.facing,
			"posture": str(u.bb.get_value("posture", "")) if u.alive else "",
			"intent": u.bb.intent_string() if u.alive else "",
			"reason": u.bb.reason() if u.alive else "",
			"castMove": str(u.casting.move.name) if not u.casting.is_empty() else "",
			"castFrac": clampf(float(tick_now - int(u.casting.started)) / maxf(1.0, float(int(u.casting.ends) - int(u.casting.started))), 0.0, 1.0) if not u.casting.is_empty() else 0.0,
		})
	# PROJECTILES ride the frame (#34): everything the renderer needs to draw a shot travelling
	# — and `will_hit`, so a doomed shot can read differently in flight if the renderer wants.
	# `aim` is the point the shot is flying at RIGHT NOW: the target's live position for a
	# homing hit (or its corpse), the frozen launch-time position for an aimed miss. Computed
	# here, never derived by the renderer.
	var pr: Array = []
	for p in projectiles:
		var ptgt = _unit(str(p.target_id))
		pr.append({"from": str(p.from), "target_id": str(p.target_id), "pos": p.pos,
			"move": str(p.kname), "will_hit": bool(p.will_hit),
			"aim": ptgt.pos if bool(p.will_hit) else Vector2(p.aim_pos)})
	# `dampening` rides the frame as STATE, not an event: it is a continuously-varying global
	# condition, and the renderer must never re-derive it from the tick counter (rule 3 — the
	# renderer derives NOTHING). 1.0 for the whole of a normal-length fight, so a presentation
	# layer can simply hide the read until it drops below 1.
	frames.append({"tick": tick_now, "units": us, "events": events, "projectiles": pr,
		"dampening": dampening()})
	for u in units:
		u["prev_pos"] = u.pos


# ═══ AOE LAYER — allEnemies geometry, tauntForce, thorns ═════════════════════════════════════
# Purely additive functions plus the marked call-site hooks above (and kit.gd's acceptance
# list). RNG contract: see the ⚠️ AOE LAYER note in the file header — per-target draws in
# unit-id order for allEnemies bursts; taunt and thorns draw nothing.

const AOE_FALLOFF_PER_TARGET := 0.05  # core.ts:74 — every extra body shaves 5% off each hit …
const AOE_FALLOFF_FLOOR := 0.4        # … floored at 40% (core.ts:95-96, aoeFalloff)


## The per-hit falloff FACTOR for an N-target burst: "AoE is weak into one body and strong into
## three" (the standing rule) is priced exactly here — each of N targets takes aoe_falloff(N)
## of the single-target hit, so 1 body is x1.00 and 3 bodies total x2.70, never x3.
static func aoe_falloff(target_count: int) -> float:
	return maxf(AOE_FALLOFF_FLOOR, 1.0 - AOE_FALLOFF_PER_TARGET * float(maxi(0, target_count - 1)))


## ═══ BLAST RADIUS IS NOT THROW DISTANCE (round 24) ═══════════════════════════════════════════
## ⚠️ ONE NUMBER WAS DOING TWO JOBS. `_resolve_aoe` used `_entry_reach` — the CAST RANGE — as the
## targeting radius AND as the ring published to the renderer, self-centred on the caster. So an
## AoE was a nova whose size equalled how far you could throw it, and after round 23's lift a
## range-9 `Ricochet` painted a 78.3-unit circle while a range-4.9 melee `Cleave` painted 43.1
## against a melee basic that reaches 6.6. That is signature failure #3, a screen that lies about
## the thing it describes, and the player watches it every fight.
##
## ⚠️ AND IT IS A PRESENTATION FIX, NOT A NERF — the brief's premise was REFUTED BEFORE THIS CODE
## WAS WRITTEN. `docs/SPATIAL_BALANCE.md` §1 measured 574 bursts on the real board: 1.43 targets
## caught per burst, 61% catching exactly one, 4% catching the three the pool is PRICED at, and
## not one burst in 574 catching five. The blast was already delivering less than its price. So
## the correction here is not "shrink the blast"; it is "put the blast where the mechanic says it
## is, at a size a viewer can believe, WITHOUT moving what it catches". G1 (>= 1.30 caught) is the
## gate that keeps that promise honest.
##
## TWO AXES, BOTH DERIVED IN GODOT FROM FIELDS THAT ALREADY EXIST — route (c) of the brief, and
## deliberately NOT route (a):
##
## 1. SIZE, seeded PER LINE, exactly as `tools/authorranges.ts` seeded reach per line, and for the
##    same stated reason: a line is a shared win condition and its geometry is part of that
##    identity. An `area` field would have cost a cross-tree change into the legacy suite (286
##    tests + goldens) to fix a direction the measurement does not support. Board units, lifted by
##    `GEOMETRY_SCALE` and NOT by `REACH_SCALE`: a blast covers GROUND, so it scales like a body,
##    where reach scales like a separation. That distinction is the whole bug in one sentence.
##
## 2. CENTRE, decided by CHANNEL — and it is the SAME DOOR as `PROJECTILE_SPEED`, not a second
##    one. A burst that FLIES (ranged/magic) lands on what it was aimed at; a burst that does not
##    (melee sweep, voice shout, support aura) happens where the caster stands. Modelling every
##    AoE as a self-centred nova was the other half of the lie: a thrown bomb and a war cry are
##    different mechanics and only the nova was ever implemented.
##
## ⚠️ MELEE NOVAS ARE TIED TO `BASE_REACH`, NOT TO THE LINE TABLE, so the truth constraint is
## STRUCTURAL rather than a comment nobody re-reads: a sweep is your reach plus a step, and when
## the geometry lift moves `BASE_REACH` the melee blast follows it in the same edit. Warcry holds
## both `Cleave` (melee) and `Intimidate` (voice), so size cannot key on line alone.
const AOE_BLAST_BOARD := {
	"Elementalist": 9.0,   # the big spell — the widest blast the pool authors
	"Volley": 8.0,         # a beaten zone dropped at distance
	"Demagogue": 8.0,      # a shout carries
	"Arcanist": 7.0,       # a chaining arc
	"Venomcraft": 7.0,     # a cloud
	"Enchanter": 7.0,      # a shout
	"Guardian": 7.0,       # a challenge aura
	"Warcry": 6.0,         # a roar (its MELEE moves take the BASE_REACH rule below)
	"Warden": 6.0,         # ground at your feet
	"Hexer": 6.0,          # a detonation on a cursed body
	"Assassin": 5.0,       # a smoke pot
}
const AOE_BLAST_DEFAULT := 6.0        # an unlisted line behaves as the median — never zero
const MELEE_BLAST_REACH_MULT := 1.6   # a sweep is BASE_REACH plus a step
## The channels whose bursts do NOT fly, and therefore centre on the caster. Deliberately the
## complement of `PROJECTILE_SPEED`'s keys — two tests, one door, and they must agree.
const AOE_NOVA_CHANNELS := ["melee", "voice", "support"]


## ⚠️ THE LIVENESS SEAM, AND IT EXISTS BECAUSE THIS CHANGE BROKE A CANARY. `_probe_balance.gd`'s
## C1 perturbs `entry.range` and calls the result "aoe radius" — true while one number did both
## jobs, false the moment they were separated, and it FAILED on this change for that reason and
## no other (see the report: x0.25 read 1.76, ABOVE the unperturbed 1.48, because shrinking the
## CAST range makes a caster close further before firing and land in a tighter cluster — real
## behaviour, wrong instrument). An instrument cannot be re-pointed at a knob that does not
## exist, so the knob is provided here: default 1.0, drawn from nothing, read only by the
## function below. Set it on a Sim instance and the blast geometry scales; leave it and this is
## dead weight that cannot move a fight.
var aoe_blast_scale := 1.0


## The blast radius of an AoE move, in real board units — decoupled from its cast range.
func aoe_blast_radius(mv: Dictionary) -> float:
	if str(mv.get("channel", "magic")) == "melee":
		return BASE_REACH * MELEE_BLAST_REACH_MULT * aoe_blast_scale
	var board: float = float(AOE_BLAST_BOARD.get(str(mv.get("line", "")), AOE_BLAST_DEFAULT))
	return board * KitLib.GEOMETRY_SCALE * aoe_blast_scale


## The range at which a move is DECIDED and gated — the cast range for everything that is thrown,
## the BLAST for a nova, because a nova cannot reach past its own burst. See the ⚠️ at the call
## site in the cast decision.
func _usable_range(m: Dictionary) -> float:
	var mv := _move_of_entry(m)
	if str(mv.get("target", "enemy")) == "allEnemies" \
			and str(mv.get("channel", "magic")) in AOE_NOVA_CHANNELS:
		return aoe_blast_radius(mv)
	return _entry_reach(m)


## Where a thrown burst lands: the caster's own target if it is a living enemy inside cast range,
## else the nearest living enemy inside cast range, else null (the burst fizzles — nothing to aim
## at). Unit-id order throughout, so ties break the same way in every process.
func _aoe_focus(u: Dictionary, reach: float):
	var bb: BT.Blackboard = u.bb
	var tid: String = str(bb.get_value("req_attack", bb.get_value("target_id", "")))
	var t = _unit(tid)
	if t != null and t.alive and t.team != u.team and u.pos.distance_to(t.pos) <= reach:
		return t
	var best = null
	var bd := INF
	for o in units:  # unit-id order — the determinism order, as everywhere
		if o.alive and o.team != u.team:
			var d: float = u.pos.distance_to(o.pos)
			if d <= reach and d < bd:
				bd = d
				best = o
	return best


## Resolve a completed allEnemies cast: a BURST against every living enemy within the move's
## BLAST RADIUS of the burst's CENTRE — see the block above for why those are now two numbers
## and not one. The legacy gate survives intact as the CAST RANGE (spatial_sim.gd:1077-1086: an
## AoE reaches only what the move's own range covers; the position-blind fan-out it replaced hit
## covered bodies 250 units away and the VFX tracer exposed it) — a nova still cannot touch what
## is outside its own reach, and a thrown burst still cannot be placed beyond it. Each target
## goes through the ONE contracted resolve_strike with the shared falloff input, then the same
## application path every other hit uses (_apply_strike_outcome: ward drain, threat, debuffs,
## taunt, thorns, status via its per-target pre-drawn roll).
func _resolve_aoe(u: Dictionary, kentry: Dictionary, events: Array) -> void:
	var mv := _move_of_entry(kentry)
	var reach := _entry_reach(kentry)          # CAST RANGE — how far it can be placed
	var blast := aoe_blast_radius(mv)          # BLAST RADIUS — how much ground it covers
	var centre: Vector2 = u.pos
	if not (str(mv.get("channel", "magic")) in AOE_NOVA_CHANNELS):
		var focus = _aoe_focus(u, reach)
		if focus == null:
			events.append({"kind": "fizzle", "from": u.id, "move": str(kentry.name)})
			return
		centre = focus.pos
	var targets: Array = []
	for o in units:  # unit-id order — the determinism order, as everywhere
		if o.alive and o.team != u.team and centre.distance_to(o.pos) <= blast:
			targets.append(o)
	if targets.is_empty():
		events.append({"kind": "fizzle", "from": u.id, "move": str(kentry.name)})
		return
	var falloff := aoe_falloff(targets.size())
	# ⚠️ THE BURST MUST BE VISIBLE OR IT IS NOT A MECHANIC. An allEnemies move hitting three
	# bodies at once with nothing on screen showing an AREA reads as three unrelated hits, and
	# the whole falloff design ("weak into one body, strong into three") becomes invisible.
	# The renderer draws this ring; it derives nothing — centre, radius and count come from here.
	events.append({"kind": "aoe", "from": u.id, "move": str(kentry.name),
		"centre": centre, "radius": blast, "targets": targets.size(), "falloff": falloff})
	var phys: bool = str(mv.get("channel", "magic")) in ["melee", "ranged"]
	for tgt in targets:
		var def_stat: float = float(tgt.stats.get("CON", 10)) if phys else float(tgt.stats.get("WIS", 10))
		var bvs_armed: bool = _bonus_status_armed(mv, tgt)
		var out: Dictionary = Damage.resolve_strike({
			"move": mv,
			"rolls": {"acc": rng.randf(), "crit": rng.randf(), "variance": rng.randf()},
			"now": tick_now * DT,
			"atk": float(u.stats.get(str(kentry.get("stat", "INT")), 10)),
			"atkMult": 1.0 + _sum_mods(u, "atkMultBonus"),
			"attackerHpFrac": float(u.hp) / float(u.max_hp),
			"attackerWard": _sum_mods(u, "ward"),
			"accPenalty": _acc_penalty_of(u), "accMod": _sum_mods(u, "accMod"),
			"dodgeMod": _sum_mods(tgt, "dodgeMod"), "flankBonus": 0.0, "behindMult": 1.0,
			"falloff": falloff,
			"defMit": Damage.mitigation_for(def_stat),
			"defMitDebuff": _sum_mods(tgt, "defMitDebuff"), "defDmgTakenMod": 1.0,
			"defStatusDmgTaken": _dmg_taken_of(tgt),
			"defGuard": _sum_mods(tgt, "guard"), "defWard": _sum_mods(tgt, "ward"),
			"defBlocking": false, "defHasAttacked": tgt.has_attacked,
			"defHasBonusStatus": bvs_armed, "defHpFrac": float(tgt.hp) / float(tgt.max_hp),
			"defMaxHp": tgt.max_hp,
		})
		if bool(out.get("hit", false)):
			# The 4th draw stays hit-gated and PER TARGET — drawn here, applied through the
			# same pre-rolled path the projectile layer uses, so the stream position is fixed.
			var status_roll := -1.0
			if mv.get("status") is Dictionary:
				status_roll = rng.randf()
			_apply_strike_outcome(u, tgt, mv, str(kentry.name), out, bvs_armed,
				status_roll, "cast_done", events)
		else:
			events.append({"kind": "cast_miss", "from": u.id, "to": tgt.id, "move": str(kentry.name)})


## TAUNTFORCE — a landed tauntForce move compels the victim onto the caster for the authored
## duration (rounds -> seconds via the contracted Derive). Mirrors battle.ts:944-946: on a
## landed debuff, `target.tauntedBy = {side, slot, turnsLeft: duration}`. The sim stores the
## compulsion on the unit; _fill_bb publishes it as bb `taunted_by` and the tree's Urgent →
## Taunted branch answers it with NO tree edit. Emits 'taunted'. Zero rng.
func _apply_taunt(u: Dictionary, tgt: Dictionary, mv: Dictionary, events: Array) -> void:
	var fx = mv.get("effects")
	if not (fx is Dictionary) or not bool((fx as Dictionary).get("tauntForce", false)):
		return
	var secs: float = Derive.rounds_to_seconds(float((fx as Dictionary).get("duration", 1)))
	tgt["taunt"] = {"by": u.id, "until": tick_now * DT + secs}
	events.append({"kind": "taunted", "from": u.id, "to": tgt.id, "seconds": secs})


## The live compeller of a taunted unit, or "". Expires by time; the compulsion also breaks
## the moment the taunter falls (battle.ts:982 — "taunter fell — compulsion breaks").
func _taunt_source_of(u: Dictionary) -> String:
	var t = u.get("taunt")
	if not (t is Dictionary):
		return ""
	if tick_now * DT >= float((t as Dictionary)["until"]):
		return ""
	var src = _unit(str((t as Dictionary)["by"]))
	if src == null or not src.alive:
		return ""
	return str((t as Dictionary)["by"])


## THORNS — flat reflect per MELEE hit taken, worn as a timed `thorns` mod (a self/team buff
## from the wearer's OWN kit, via MOD_OF_EFFECT). A REFLECT EVENT, never a second
## resolve_strike: battle.ts:1281-1284 subtracts `target.thornsFlat` straight off the
## attacker's hp — flat, unmitigated, no accuracy, no crit — so a reflect can never trigger
## the attacker's own thorns: thorny-vs-thorny cannot chain, structurally.
## ⚠️ The authored numbers are FLAT damage (Riposte 10, Retaliate 16), not fractions — the
## legacy field name `thornsFlat` says so, and 6-16 read as fractions would exceed 100%.
## ⚠️ MELEE-GATED BY DESIGN BRIEF (legacy reflected every channel): thorns punish the bodies
## standing in reach; an archer or caster does not prick itself on armour it never touches.
func _reflect_thorns(attacker: Dictionary, defender: Dictionary, mv: Dictionary,
		out: Dictionary, events: Array) -> void:
	if not bool(out.get("hit", false)) or int(out.get("dmg", 0)) <= 0:
		return
	if str(mv.get("channel", "magic")) != "melee":
		return
	var flat: float = _sum_mods(defender, "thorns")
	if flat <= 0.0:
		return
	attacker.hp = float(attacker.hp) - flat
	events.append({"kind": "thorns", "from": defender.id, "to": attacker.id, "dmg": int(flat)})
