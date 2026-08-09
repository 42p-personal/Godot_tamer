## THE BATTLEFIELD — replays a real spatial simulation.
##
## ⚠️ THIS RENDERER DERIVES NOTHING. It plays back the frame stream the simulation produced
## (`docs/BUILD_CONTRACT.md` §2): positions, facings, states, HP, shots, intent/reason and
## projectiles are all read, never invented. The one thing this file computes for itself is the
## CAMERA's own framing — which world-space box to look at — and that is explicitly a rendering
## decision, built only from positions the stream already gave us, never a guess about where a
## unit "should" be.
##
## The rule to keep: **if the renderer wants to know something about the FIGHT, it asks the frame
## stream.** Any time this file starts computing where a unit "should" be, or what it is doing,
## the spatial layer is missing a field — say so rather than working around it.
##
## ⚠️ THE CAMERA IS THE OTHER HALF OF THE DESIGN, AND TWO PASSES GOT IT WRONG.
## A side-on, eye-level camera renders two ranks facing each other — the visual grammar of
## turn-based combat — no matter how real the simulation behind it is. Looking DOWN at a bounded
## floor is what makes it read as an autobattler board. This pass adds a second requirement on top
## of that: the leash that used to keep every fight inside 24-42% of the board is GONE
## (`docs/BUILD_CONTRACT.md` §0), so a camera that frames the deploy zone alone now regularly
## misses the fight. The camera below FOLLOWS the living units' own spread — center and zoom both
## re-fit every frame from their actual positions — rather than fitting a static formula.
##
## ⚠️ SUPERSEDED 2026-08-08 — THE RENDERER SWITCH LANDED. This paragraph used to say the screen
## ran standalone while `spatial_sim.gd` was mid-rewrite, with `intent`/`reason` and `projectiles`
## promised but unpopulated. All three are now real: this screen runs `scripts/sim/sim.gd` with the
## `combat_tree` brains, which emit intent, reason, posture and in-flight projectiles every tick.
## The guarded `.get(..., default)` reads stay — they are still the correct shape for a stream
## that will keep growing — but they are no longer papering over an absent producer.
extends Node3D

const TacticsScript = preload("res://scripts/tactics.gd")
const Sp = preload("res://scripts/spatial.gd")
## Procedural per-creature animation — see docs/MESHY_SPIKE_RESULT.md's follow-up section.
const CreatureAnimScript = preload("res://scripts/ui/creature_anim.gd")
const CreatureRigScript = preload("res://scripts/ui/creature_rig.gd")
const ARENA_LAYOUT_PATH := "res://scripts/arena_layout.gd"

## ── THE RENDERER SWITCH (2026-08-08) ────────────────────────────────────────────────────────
## This screen ran `spatial_sim.gd` + `ai/monster_tree.gd` — both carrying SUPERSEDED banners —
## while the rewritten stack (`scripts/sim/`, `scripts/ai/combat_tree.gd`) only ever ran in the
## watch scene and the probes. `USE_NEW_SIM` closes that gap; it is a SEAM, not a deletion, so
## the legacy engine stays one constant away for as long as the comparison is worth having.
##
## ⚠️ THE NEW SIM DOES NOT SPEAK THE OLD FRAME CONTRACT, so the switch is a sim swap PLUS a
## translation (`_adapt_result`). Everything below the translation — 2000 lines of nameplates,
## cast bars, VFX, camera and log — is untouched and still reads the legacy field names.
## The translation is a pure RE-KEYING of what the stream already states: string unit ids become
## the array indices this file addresses nodes by, ticks become seconds, status records become
## their kinds, and the event list becomes the flat log. It invents no fact about the fight.
##
## ── THE SEAM IS GONE (2026-08-08, integration round) ────────────────────────────────────────
## `USE_NEW_SIM` and the two legacy branches below it (`spatial_sim.gd`, then `battle_sim.gd`)
## were deleted once the full probe battery stayed green without them. This screen now has ONE
## engine and no way to silently run another.
##
## ⚠️ WHY A DEAD BRANCH WAS WORTH DELETING RATHER THAN LEAVING GUARDED. Both fallbacks were
## reached through `ResourceLoader.exists()`, so the screen would have DEGRADED SILENTLY to a
## superseded engine if a path ever went missing — no error, just a different fight, which is the
## single most expensive failure shape this project has recorded. A missing `preload` is a parse
## error you find in one second; a live `exists`-guarded fallback is a debug round.
##
## ⚠️ `spatial_sim.gd` / `spatial_ai.gd` / `monster_tree.gd` STILL EXIST ON DISK and that is
## deliberate: `scripts/ui/sandbox_ui.gd` hard-`preload`s the sim. They must be deleted as ONE
## atomic move (the trio loads each other by path with `exists`-guards and degrades quietly when
## partially present) once the sandbox is moved across. That is the next round's job, not this
## file's problem — nothing here references them any more.
const NewSim = preload("res://scripts/sim/sim.gd")
const KitLib = preload("res://scripts/sim/kit.gd")

## ⚠️ GROUND UNITS ARE NOT WORLD UNITS, DELIBERATELY.
## `ARENA_BLUEPRINT` sizes a 5v5 ground at 160x88 — realistic for a stadium, and far too large to
## read when the fighters are ~2 units tall. Autobattlers in this genre exaggerate unit scale
## against the board so the pieces stay legible. We render the ground shrunk and the creatures
## enlarged; the SIM is unaffected, because this factor is applied only on the way to the screen.
const WORLD_SCALE := 0.34
## ⚠️ AND THIS IS WHY TWO WORKSTREAMS QUOTED PROP SIZES THAT DIFFERED BY EXACTLY 3x, BOTH CORRECT.
## `arena_layout.gd` authors a pillar at 4.2 * GEOMETRY_SCALE = 9.24 SIM units and documents it as
## "2.1 bodies", against a sim body diameter of `2 * Sp.BODY_RADIUS` = 4.4. `_probe_venue.gd`
## measures the same pillar at 0.71 bodies, against `UNIT_HEIGHT` = 4.4. The two denominators are
## the same number; the two NUMERATORS are not, because the sim rect reaches the screen multiplied
## by WORLD_SCALE while the creature is drawn at a fixed `UNIT_HEIGHT`. 2.1 x 0.34 = 0.71, and
## 1 / 0.34 = 2.94 is the whole of the "3x" disagreement.
##
## ⚠️ IT IS A UNIT MISMATCH, NOT A BUG, AND THE RENDERER IS NOT WRONG — but the consequence is
## real and it is the round's finding 1. Creatures are deliberately drawn ~2.94x oversized against
## the board, so ANYTHING sized in sim units is drawn at a third of its footprint relative to the
## monster standing beside it. A prop authored as "two bodies wide" so it would read as
## architecture arrives on screen 0.7 creatures wide. Growing a prop in `arena_layout.gd` buys
## only a third of what its comment promises, and the layout side cannot see that from its own
## instrument.
##
## ⚠️ THE OBVIOUS FIX IS WRONG. Drawing props at the creature's exaggeration would put the drawn
## silhouette ~3x outside the sim's rect, so cover would visually block sightlines it does not
## sim-block and bodies would clip through it — the renderer would start asserting something about
## the fight, which is the one thing it must never do. The axis that IS free is HEIGHT: nothing in
## the sim reads prop height, so `PROP_HEIGHT_BODIES` can make a piece read as a pier without
## moving one number the sim uses. That is where the next round's accent-layer work should go.
const UNIT_HEIGHT := 4.4
const WALL_H := 1.4
const STAND_TIERS := 5

## ── HOW DARK THE VENUE SHELL IS ALLOWED TO BE ───────────────────────────────────────────────
## Multipliers on the league's `ground` tone for the barrier and the stands. They exist because the
## shell used to be the LIGHTEST large shape in frame and the value ladder wants it under the
## floor; they are named constants now because the round that measured the frame ROW BY ROW found
## they had been pushed past "subordinate" into "absent".
##
## ⚠️ 0.85 / 0.62 MADE 37-47% OF EVERY HERO FRAME CARRY NO CONTENT, AND NO CHECK COULD SEE IT.
## `_probe_frame.gd` counted pixels at or under 0.045 luma — literal black — and reported 2-9%, a
## comfortable 11/11 green, while the integrator looking at the same frames called nearly half the
## picture empty. Both were right. A dead band is not black; it is a band with nothing readable in
## it, and at 0.85/0.62 the stands measured 0.054-0.090 luma and the barrier 0.060-0.132 against a
## floor at 0.147-0.268. The shell was three to four times darker than the ground it rings, which
## is not "falling into dark" — it is not being drawn.
##
## ⚠️ THE CONSTRAINT THAT SETS THESE NUMBERS IS THE VALUE LADDER, NOT TASTE. `_probe_venue.gd`
## requires stands < walls < floor < cover < creatures, so the shell CANNOT simply be lifted to
## where the eye stops calling it empty — it has to be lifted as a GROUP, keeping the order, and
## it has to stop below the floor.
##
## ⚠️ AND THE FIRST ATTEMPT WAS A FLAT MULTIPLIER PAIR (1.30 / 1.15) AND IT BROKE THE LADDER FROM
## 9/11 TO 4/11 IN ONE STEP. The reason is worth keeping, because it is the same shape of mistake
## three other constants in this file carry a warning about: THE FLOORS ARE NOT THE SAME VALUE.
## They run 0.147 (Masters) to 0.269 (Tin) — nearly two to one — so one multiplier that lands the
## shell comfortably under Tin's floor lands it ON TOP of Copper's and Iron's. Measured: Copper
## walls 0.175 against a floor of 0.149, Iron 0.216 against 0.183. A constant cannot express
## "under the floor" when the floor is a variable.
##
## So the shell is authored as a RATIO OF ITS OWN LEAGUE'S FLOOR, resolved at build time from
## `_floor_average()` (the ground art times the league tone — the thing actually drawn, which is
## neither the texture nor the tint alone). Under the floor is then true by construction at every
## league, and the residual dead band at the dark-floored leagues is correctly attributed to the
## FLOOR being dark rather than hidden inside a shell constant.
##
## ⚠️ THE RATIOS BUY BACK MOST OF THE DEAD BAND AND DELIBERATELY NOT ALL OF IT. At Platinum and
## Tamer Elite the floor itself sits at 0.157-0.185, so a shell strictly beneath it cannot clear
## the 0.12 the eye needs; those two leagues stay flagged, and the honest lever for them is the
## cast light `_probe_venue.gd` already names, not another shell nudge.
## ⚠️ THESE ARE ALBEDO RATIOS AND THE FRAME DOES NOT RENDER THEM ONE-FOR-ONE — measured, not
## assumed. The first pass reasoned that "both sides are albedo, both are lit by the same lamps, so
## the albedo ratio is the rendered ratio", set 0.72 / 0.60, and the frame came back at 0.52-0.58
## of the floor: the ladder was safe and the dead band was barely bought back. The shell's surfaces
## are VERTICAL and the key rakes at -40 elevation, so they collect materially less of it than the
## horizontal floor does. Measured across Wood / Copper / Tin the gap is a consistent ~1.35x, which
## is why these are set 1.35x above the rendered targets (walls ~0.70 of floor, stands ~0.58) rather
## than at them. If the key's elevation ever moves, this pair has to be re-measured, not re-derived.
const WALL_FLOOR_RATIO := 0.96
const STAND_FLOOR_RATIO := 0.80
## Bounds on the resolved multiplier, so a league with no readable ground art (where the floor
## average falls back to a formula) can never drive the shell to black or to white.
const SHELL_TONE_MIN := 0.55
const SHELL_TONE_MAX := 2.20

## ── PROP PROPORTION: THE CREATURE IS THE YARDSTICK ─────────────────────────────────────────────
##
## ⚠️ COVER HEIGHT USED TO BE THREE BARE NUMBERS (1.0 / 2.0 / 3.2) WHILE `UNIT_HEIGHT` IS 4.4, so
## every grade was authored against nothing at all. Measured consequence on a 5v5 board, where a
## blocking major is `ArenaLayout.MAJOR_MIN_BODIES` = 9 bodies of frontage = 39.6 ground units =
## 13.5 world units: the piece was drawn 13.5 long and 3.2 tall — a **4.2 : 1 slab, three
## creature-heights long and knee-high on the creature standing beside it**. That is the "brick
## loaf" complaint exactly, and it is a PROPORTION fault, not a texture one.
##
## ⚠️ THE FOOTPRINT IS NOT OURS TO CHANGE. `Spatial.cover_between` tests that rectangle and the
## renderer must not lie about where cover is (the invariant the `_try_prop_multimesh` header
## defends). HEIGHT is the only free axis, so height is expressed in CREATURE HEIGHTS and the
## cover GRADE is what picks the ratio:
##
##   soft     0.42 — mid-thigh. You crouch behind it and shots pass over. A crate reads as a crate
##                   beside a monster (2.24 wide x 1.85 tall = 1.2 : 1) instead of as a loaf
##                   (2.24 x 1.0 = 2.2 : 1).
##   hard     0.80 — shoulder. You stand behind it and only your head is exposed.
##   blocking 1.18 — over the head. This grade means "breaks the line of sight", so it has to be
##                   taller than the thing whose line of sight it breaks or the picture is a lie.
##                   A 9-body major now reads 13.5 x 5.19 = 2.6 : 1 — a wall, not a loaf.
##
## ⚠️ AND THE CEILING IS NOT INVENTED EITHER. `ARENA_DESIGN.md` §4 caps drawn cover at 3.4 against
## a body that was ~2.0 units when the rule was written — i.e. **1.7 creature-heights**. 1.18 sits
## comfortably under it, so blocking cover still cannot hide the fight from a 38-degree camera: it
## occludes `h / tan(38°)` ≈ 1.28 h of floor behind it, which is precisely the cover shadow the sim
## is already charging for.
##
## ⚠️ A GRADE WITH NO ENTRY FALLS TO `soft`, NEVER TO ZERO. A future layout stream may add a grade
## name before this table hears about it; a piece drawn flat on the floor is invisible cover, which
## is the worst possible failure mode in a game the player cannot intervene in.
const PROP_HEIGHT_BODIES := {"soft": 0.42, "hard": 0.80, "blocking": 1.18}
const PROP_HEIGHT_DEFAULT := 0.42

## The drawn height of a cover piece, in world units. ⚠️ `_probe_venue.gd` reads this rather than
## re-deriving it, so the instrument and the renderer can never disagree about what was drawn.
static func prop_height(grade: String) -> float:
	return UNIT_HEIGHT * float(PROP_HEIGHT_BODIES.get(grade, PROP_HEIGHT_DEFAULT))


## ── THE VENUE SCALES WITH THE BOARD; THE CROWD DOES NOT ────────────────────────────────────────
##
## ⚠️ THE STANDS WERE A FIXED RING ON A BOARD THAT DOUBLES. Five tiers of 0.8 rise and 1.6 depth
## give a bank 5.4 world units tall whatever the ground is, while `Spatial.ground_size` runs from
## 74.8 x 41.9 world units at 1v1 to 149.6 x 83.8 at 5v5 — exactly 2.0x — and the camera pulls back
## in proportion. So the venue subtends HALF the angle at the leagues that are supposed to feel
## grandest, which is the "stands cropped to a thin band" report, and it is arithmetic rather than
## taste.
##
## ⚠️ THE FIX IS MORE TIERS, NOT BIGGER ONES BELOW ROW 5, AND THAT IS A HARD CONSTRAINT.
## `spectators.gd` seats its crowd on rows 0-4 at its own hard-coded step (`off = 4.5 + row*3.5`,
## `lift = 1.6 + row*1.4` in GROUND units) and it is another workstream's file. Changing the first
## five steps would float or bury every spectator in the venue. So rows 0-4 are byte-identical to
## before and the growth is entirely in tiers ABOVE the crowd — which is also how a real ground
## grows, and it obeys the standing rule that the crowd fills by FAME and is *never* scaled to the
## arena (`spectators.gd` header; memory `crowd-fill-by-fame`).
const STAND_TIERS_MAX := 12
const STAND_STEP_H := 0.8
const STAND_STEP_OUT := 1.6

const SPEED_OPTIONS := [0.5, 1.0, 2.0, 4.0]
const OPENING_HOLD := 1.5

# ═══════════════════════════════════════════════════════════════════════════════════════════════
# THE LAMP TABLE — one entry per league, because the LOOK is a rung of the ladder
# ═══════════════════════════════════════════════════════════════════════════════════════════════
#
# ⚠️ `ART_DIRECTION.md` §"The style, in one line" states the rule this table exists to satisfy:
# *"Never hard-code a light in the renderer: all ten arenas would get the same lamp and the ladder
# loses a dimension."* Until now `_build_world` did exactly that — one sun, one ambient colour,
# every league — so Wood and Tamers Apex were the same room.
#
# ⚠️ AND `ground` IS THE FIX FOR THE COMPLAINT THAT STARTED THIS PASS: **the floor was blinding.**
# Measured off the source art, the authored grounds run luma 0.24 (Iron) to 0.52 (Tin) in sRGB —
# a 2.2x spread — and the renderer multiplied every one of them by the same white albedo under an
# ambient term of 1.25. Platinum's marble (0.50) and Tin's (0.52) therefore rendered at or above
# the value of the creatures standing on them. `ground` is a per-league MULTIPLIER on the floor's
# albedo, authored to pull each league's floor down UNDER its cast: the brighter the source
# texture, the harder it is knocked back, so the ladder keeps its material identity while the
# creatures keep the top of the value range.
#
# ⚠️ THE ONE RULE THAT OUTRANKS EVERY ENTRY BELOW: the creatures must be the brightest things on
# screen. `scripts/_probe_venue.gd` measures exactly that from a rendered frame (body luminance vs
# floor luminance) and is the arbiter — if a lamp here is retuned, re-run it, do not eyeball it.
#
# `key`     — the warm working lamp's colour. Per-league identity falls out of it for free.
# `key_e`   — its energy.
# `amb`     — the cool sky bounce. NEVER near-white: that is what flattened the whole venue.
# `amb_e`   — its energy. Anything above ~0.5 erases the key light's form entirely.
# `fog`     — the colour distance fades toward; also the backdrop the venue is cut out against.
# `ground`  — albedo multiplier on the floor (see above).
# `fill`    — the cool fill/rim colour that separates a silhouette from the floor behind it.
const LEAGUE_LOOK := {
	"Wood":        {"key": Color(1.00, 0.86, 0.62), "key_e": 2.0, "amb": Color(0.34, 0.40, 0.52), "amb_e": 0.34, "fog": Color(0.15, 0.16, 0.19), "ground": Color(0.62, 0.58, 0.52), "fill": Color(0.52, 0.64, 0.92)},
	"Copper":      {"key": Color(1.00, 0.80, 0.58), "key_e": 2.0, "amb": Color(0.32, 0.42, 0.50), "amb_e": 0.34, "fog": Color(0.13, 0.16, 0.17), "ground": Color(0.80, 0.72, 0.62), "fill": Color(0.50, 0.66, 0.90)},
	"Tin":         {"key": Color(0.96, 0.92, 0.86), "key_e": 1.9, "amb": Color(0.34, 0.40, 0.50), "amb_e": 0.32, "fog": Color(0.15, 0.17, 0.20), "ground": Color(0.52, 0.53, 0.57), "fill": Color(0.56, 0.68, 0.94)},
	"Bronze":      {"key": Color(1.00, 0.83, 0.55), "key_e": 2.1, "amb": Color(0.32, 0.38, 0.50), "amb_e": 0.32, "fog": Color(0.15, 0.14, 0.16), "ground": Color(0.66, 0.60, 0.52), "fill": Color(0.52, 0.64, 0.92)},
	"Iron":        {"key": Color(1.00, 0.78, 0.52), "key_e": 2.2, "amb": Color(0.28, 0.33, 0.44), "amb_e": 0.28, "fog": Color(0.10, 0.11, 0.13), "ground": Color(0.92, 0.88, 0.84), "fill": Color(0.48, 0.60, 0.92)},
	"Silver":      {"key": Color(0.98, 0.90, 0.76), "key_e": 1.9, "amb": Color(0.34, 0.40, 0.52), "amb_e": 0.32, "fog": Color(0.14, 0.16, 0.20), "ground": Color(0.52, 0.53, 0.56), "fill": Color(0.56, 0.68, 0.96)},
	"Gold":        {"key": Color(1.00, 0.88, 0.62), "key_e": 2.0, "amb": Color(0.34, 0.38, 0.50), "amb_e": 0.30, "fog": Color(0.16, 0.14, 0.14), "ground": Color(0.58, 0.54, 0.47), "fill": Color(0.52, 0.64, 0.92)},
	# ⚠️ THE FOUR GRAND-CIRCUIT GROUNDS WERE TONED DOWN HARD ON 2026-08-08 (Platinum x0.50,
	# Masters x0.61, Tamer Elite x0.58, Tamers Apex x0.67). Every one of them FAILED the value
	# check — the floor out-valued the creatures standing on it (ratios 0.68 / 0.82 / 0.79 / 0.90,
	# where 1.12 is the pass mark). Factors are derived from the measured floor and body luminance,
	# not guessed, and each keeps its colour's RATIOS so the league's material identity survives a
	# change that is purely value. See the "TONE-DOWN" note in `_build_world`.
	#
	# ⚠️ AND THE DIAGNOSIS, BECAUSE THE OBVIOUS READING IS WRONG: this is not "high leagues use big
	# multipliers". IRON RUNS 0.92 — the largest in this table — AND PASSES AT 2.04, while Masters
	# runs the same 0.92 and failed at 0.82. The multiplier is not the variable; the GROUND ART's
	# own brightness is (Iron is near-colourless forge stone, Masters is pale marble), and this
	# column is what compensates for it. So a new ground texture ALWAYS needs a fresh measurement —
	# you cannot infer its tone-down from a neighbouring league's.
	# ⚠️ PLATINUM 0.36 -> 0.335 ON 2026-08-08, AND IT IS THE MARGINAL CASE IN THIS TABLE, not a clean
	# one. It measured 1.12 / 1.14 / 1.12 / 1.07 / 1.07 across five integration runs against a 1.12
	# pass mark: the FLOOR term is steady (0.200-0.201) and the BODY term is what moves (0.214-0.228),
	# because the check samples whichever creature is standing in the sampling ring at a wall-clock
	# frame. So this nudge buys margin against an instrument that wobbles, and the real fix is to pin
	# the probe's sample to a sim tick. ⚠️ DO NOT KEEP CUTTING THIS ROW IF IT FAILS AGAIN: Platinum
	# already has the darkest floor AND the darkest frame (0.158) of the eleven, and the honest
	# diagnosis is that its CAST is dark, not that its ground is bright. The next move here is a
	# stronger `fill` (which lifts a silhouette off the floor without lifting the floor), not more
	# tone-down — past this point darkening the ground is fixing the ratio by ruining the venue.
	"Platinum":    {"key": Color(0.98, 0.91, 0.80), "key_e": 2.0, "amb": Color(0.33, 0.39, 0.53), "amb_e": 0.30, "fog": Color(0.13, 0.15, 0.19), "ground": Color(0.335, 0.344, 0.363), "fill": Color(0.58, 0.70, 0.98)},
	"Masters":     {"key": Color(1.00, 0.86, 0.68), "key_e": 2.1, "amb": Color(0.30, 0.36, 0.50), "amb_e": 0.28, "fog": Color(0.12, 0.12, 0.16), "ground": Color(0.56, 0.53, 0.49), "fill": Color(0.54, 0.66, 0.96)},
	# ⚠️ TAMER ELITE 0.52 -> 0.458 ON 2026-08-08. It was the last league still failing the value check
	# and it failed on BOTH runs of the integration pass (1.05 twice, against a 1.12 pass mark),
	# where Platinum's neighbouring failure moved to 1.12/1.14 between runs and is therefore noise,
	# not a defect. Factor is the measured shortfall (0.214/0.229) with margin for the ±0.1 of
	# run-to-run variance the check carries, keeping the colour's RATIOS so the league's pale-stone
	# identity survives a change that is purely value.
	"Tamer Elite": {"key": Color(1.00, 0.84, 0.64), "key_e": 2.1, "amb": Color(0.30, 0.35, 0.50), "amb_e": 0.28, "fog": Color(0.11, 0.12, 0.16), "ground": Color(0.458, 0.440, 0.440), "fill": Color(0.54, 0.66, 0.96)},
	"Tamers Apex": {"key": Color(1.00, 0.87, 0.66), "key_e": 2.2, "amb": Color(0.31, 0.36, 0.52), "amb_e": 0.28, "fog": Color(0.12, 0.11, 0.15), "ground": Color(0.52, 0.49, 0.44), "fill": Color(0.56, 0.68, 0.98)},
}
## The lamp a league with no entry gets. Neutral on purpose: a missing league should read as an
## unfinished VENUE, never as a broken renderer.
const DEFAULT_LOOK := {
	"key": Color(1.00, 0.86, 0.64), "key_e": 2.0, "amb": Color(0.32, 0.38, 0.50), "amb_e": 0.32,
	"fog": Color(0.13, 0.14, 0.18), "ground": Color(0.58, 0.55, 0.50), "fill": Color(0.54, 0.66, 0.94),
}


func _look() -> Dictionary:
	return LEAGUE_LOOK.get(league_name, DEFAULT_LOOK)


## The extra visual layer every unit's geometry is placed on, so one directional light can reach
## the cast and nothing else. Bit 2 (value 2); layer 1 stays set, so the venue's own lamps still
## light the creatures normally — this ADDS, it never replaces.
const CAST_LIGHT_LAYER := 2


## Put `n` and everything under it on the cast-light layer as well as its own.
func _add_to_cast_layer(n: Node) -> void:
	if n is VisualInstance3D:
		var v := n as VisualInstance3D
		v.layers = v.layers | CAST_LIGHT_LAYER
	for c in n.get_children():
		_add_to_cast_layer(c)

# ── Camera — steep, dynamic, never the static leash-radius formula that no longer exists. ──────
## ⚠️ RE-FRAMED 2026-08-05 TO THE DIRECTION THAT WAS WRITTEN AND NEVER BUILT.
## Was 58 degrees / 40 fov, chosen so "looking DOWN at a bounded floor reads as an autobattler
## board". That is a defensible instinct, but it is not the direction on file: `ART_DIRECTION.md`
## §Camera and `ARENA_CAMERA_REFERENCE.md` both specify **~38 degrees elevation, 26 fov (long
## lens)** — and the studio owner picked that framing explicitly off a reference image, asking for
## "more zoomed out, bigger arena".
##
## ⚠️ WHAT THE TRADE ACTUALLY IS, so the next person can reverse it knowingly: at 58 you see the
## FLOOR and the fight reads as a board. At 38 you see the VENUE — the far wall, the stands, the
## horizon — and it reads as a place with a crowd in it. The old value優 optimises for tactical
## clarity; this one optimises for spectacle and for the "sport, not war" identity in
## `ART_BIBLE_GUILD_COLOURS.md`. Both are coherent. This one is the one that was decided.
##
## ⚠️ A LONG LENS PUSHES THE CAMERA BACK, IT DOES NOT SHRINK THE SUBJECT. `_apply_camera_now`
## solves `r = span / tan(fov/2)`, so dropping fov 40 -> 26 roughly doubles the camera distance
## for the same framing. That is the point — a short lens bows a wide arena (`ART_DIRECTION.md`),
## and the bow is exactly what made the old framing feel like a diorama rather than a stadium.
const CAM_PITCH_DEG := 38.0     # degrees below horizontal — ART_DIRECTION.md §Camera
const CAM_FOV := 26.0           # long lens; short ones bow a wide arena
## ⚠️ THE CAMERA USED TO FRAME POINTS, AND UNITS ARE NOT POINTS. `_camera_target()` measured the
## bounding box of unit POSITIONS and multiplied it by `CAM_PADDING`. That was survivable while
## every unit was a billboarded sprite, because a multiplier on a spread is roughly a body-width
## when the spread is large. It stopped being survivable the moment real geometry arrived: ten
## bodies converging into a scrum have a near-ZERO positional spread, a multiplier on near-zero is
## near-zero, so the span collapsed to the floor and two creatures filled the screen while the
## fight happened inside them.
##
## The floor was 9.0 world units against creatures 4.4 units tall — barely two bodies wide. The
## three fixes below are independent and all three were needed:
##   1. a BODY RADIUS added to the bounding box, so the frame contains volumes not points
##   2. an ADDITIVE headroom term rather than only a multiplier, so padding survives a scrum
##   3. a floor derived from `UNIT_HEIGHT` rather than a bare number, so it cannot drift out of
##      step with the creatures again
##
## ⚠️ AND NO PROBE WOULD HAVE CAUGHT THIS. Every unit built, every clip resolved, the sim ran and
## the frame stream was intact — the numbers were all green and the fight was still unwatchable.
## It took looking at six sampled frames. Legibility is a first-class requirement here
## (`CLAUDE.md`) precisely because the player cannot intervene, so "the camera is too tight" is a
## defect, not polish.
## ⚠️ TUNED AGAINST A MEASURED TARGET, NOT A GUESS. `span` is the half-extent that fills the
## vertical FOV, so a creature occupies `UNIT_HEIGHT / (2*span)` of frame height. At the old floor
## of 9.0 that was 24% PER CREATURE and ten of them buried the fight; the first correction to 5.5x
## overshot to 9% and the fight became ants on a table. 3.0x puts one creature at ~17% of frame
## height — big enough to read its animation, small enough that ten fit with the venue behind.
const CAM_MIN_SPAN := UNIT_HEIGHT * 2.6   # ~11 units — one creature reads at ~19% of frame height
const CAM_PADDING := 1.18       # multiplier on the spread; small now that headroom is additive
const CAM_HEADROOM := 2.0       # world units added regardless of spread — survives a scrum
## Half a creature's footprint, added on every side so the frame holds BODIES rather than the
## points they stand on. Derived from `UNIT_HEIGHT` so it tracks the creature scale automatically.
const CAM_BODY_RADIUS := UNIT_HEIGHT * 0.5
## A unit's height eats vertical screen space that a ground-plane bounding box knows nothing
## about. At a 38-degree pitch a body of height H covers roughly H*cos(38) of the vertical
## extent, so the span has to allow for it or heads leave the frame in a tight shot.
const CAM_HEIGHT_ALLOWANCE := UNIT_HEIGHT * 0.8
## Nameplate declutter — see `_update_plates`.
const PLATE_MAX_LIFT := 12      # bigger plates stack taller before giving up
const PLATE_GAP := 3.0          # pixels between stacked plates

const CAM_FOLLOW_RATE := 2.4    # exponential smoothing rate/second for center+zoom

# ── THE DIRECTOR (ACTION mode). ⚠️ FITTING IS NOT FILMING. Framing the bounding box of every
# living unit means the more spread the fight, the further the camera pulls back — so the one
# moment the shot most needs to be tight (a 5v5 strung out across a 440x246 ground) is the moment
# it is widest. `docs/ENGAGEMENT_DESIGN.md` records the same insight from the other side: an arena
# larger than the screen makes a diffuse fight unfilmable, so the camera and the chase are one
# problem. ACTION mode therefore picks a SUBJECT and frames its engagement.
#
# ⚠️ THE STICKINESS RULE, STATED, because a cut that lands on the wrong thing is worse than no
# cut: the camera holds its subject for CAM_DWELL playback seconds no matter what. After that it
# only changes subject if the challenger's interest exceeds the incumbent's by CAM_SWITCH_MARGIN.
# The single override is death — when the subject falls the shot holds it for CAM_DEATH_HOLD (so
# the kill reads) and is then free to move immediately. Nothing else can jump the shot.
const CAM_DWELL := 2.2            # playback seconds a subject is held unconditionally
const CAM_SWITCH_MARGIN := 1.5    # challenger must be this much more interesting to take the shot
const CAM_DEATH_HOLD := 1.1       # seconds the shot stays on a subject that just died
const CAM_ENGAGE_R := 26.0        # ground units around the subject that count as "this fight"
const CAM_HIT_MEMORY := 0.7       # seconds a landed hit keeps a unit interesting
const CAM_SNAP_SPANS := 3.0       # a subject change further than this many spans CUTS, not eases

var _cam_subject: int = -1
var _cam_subject_since: float = -999.0
var _hit_at: Dictionary = {}      # unit idx -> playback seconds of its last landed hit taken
var _death_at: Dictionary = {}    # unit idx -> playback seconds it fell
var _cam_want_snap := false
## The enemy half of the approach shot's closest-pair — framed WITH the subject so the gap is the
## thing on screen. -1 outside the approach shot.
var _cam_partner: int = -1
const CAM_APPROACH_R := 90.0     # ground units: past this the two lines get their own shot

## ⚠️ TWO TEMPORARY OBSERVATION SWITCHES (studio owner, 2026-08-05): "lets remove the objects from
## the arena for now... lets make a large arena with clear deployment zones and see how the
## monsters move and interact. the camera should be able to cover the arena."
##
## Both are deliberately named and flagged rather than done by deleting code, because both remove
## something the design actually wants back:
##
##   SHOW_OBSTACLES  — cover is not decoration. `ARENA_DESIGN.md`'s DENSITY LAW (one piece per 300
##                     square units) and `SPATIAL_COMBAT_DESIGN.md`'s graded cover are load-bearing
##                     mechanics, and `arena_layout.gd` still GENERATES the obstacles either way —
##                     this only stops them being drawn and handed to the sim. Turning it back on
##                     restores the whole system with no other change.
##
##   The ARENA camera mode — a fixed wide shot that never moves is the only way to judge MOVEMENT, which
##                     is the entire question being asked. A camera that follows the action hides
##                     exactly the thing under test: whether the monsters use the space at all.
##                     ⚠️ It is not the shipping camera — at 352x194 the bodies fall to ~4% of
##                     frame height, well under the 12-13% the follow camera holds. This is an
##                     instrument, not a decision.
const SHOW_OBSTACLES := true
## ⚠️ Now the STARTING value of a runtime toggle (`C`), not a fixed constant — see `_unhandled_input`.

# ── Tier-1 glyph — from the frame's own `state` enum, never a guess at the tree's branch name.
## `docs/UX_LEGIBILITY.md` §6 Tier 1 wants a branch glyph (engage/hold/flank/dive/...), but the
## frame contract does not promise a `branch` key, only the enumerated `state` field
## ("idle"|"advance"|"retreat"|"attack"|"cast"|"stunned"|"dead") — which the sim DOES guarantee
## today. Using `state` for the always-on glyph and reserving the free-text `intent`/`reason` for
## the on-demand callout (Tier 2) means Tier 1 never has to guess at vocabulary that isn't there
## yet. "attack" gets no separate glyph — the hit/miss float-text already covers that instant,
## exactly as `UX_LEGIBILITY.md` specifies. `stunned` naturally wins precedence because the sim's
## own `_record_frame` already checks incapacitation before movement/casting.
const STATE_GLYPH := {
	"advance": "→", "retreat": "←", "cast": "⚡", "stunned": "⊘",
}

## Status taxonomy, ported from `arena_view.gd`'s (disconnected) `STATUS_META` table per
## `docs/UX_LEGIBILITY.md` §1 rule 1 / `docs/ACCESSIBILITY.md` §1.3's explicit recommendation —
## same abbreviations, same hue families, so a status reads identically wherever it is drawn.
const STATUS_META := {
	# ⚠️ `taunt` and `weary` are SIM-SIDE states, not fieldStatus kinds — taunt is the forced-
	# target entry the 2026-08-06 wiring appends, weary is the care loop's low-stamina flag
	# injected as a pseudo-status below. They still get real chips: a forced target and a tired
	# fighter are exactly the reads a player who cannot intervene needs to see.
	"taunt": {"abbr": "TAUNT", "color": Color(0.92, 0.55, 0.30)},
	"weary": {"abbr": "WEARY", "color": Color(0.58, 0.64, 0.74)},
	# ⚠️ COLOUR FAMILIES (UI team 2026-08-06): seven statuses shared ONE gold, leaving 11px
	# abbreviations as the sole differentiator. Families now: body-lock gold (stun/sleep),
	# mental pink-violet (fear/confusion/charm), silence cool blue-grey (a resource lock, not a
	# body lock), knockback warm neutral (displacement, not control).
	"stun": {"abbr": "STN", "color": Color(0.95, 0.92, 0.62)},
	"sleep": {"abbr": "SLP", "color": Color(0.88, 0.82, 0.55)},
	"fear": {"abbr": "FEAR", "color": Color(0.72, 0.45, 0.85)},
	"confusion": {"abbr": "CONF", "color": Color(0.90, 0.52, 0.78)},
	"charm": {"abbr": "CHRM", "color": Color(0.95, 0.62, 0.68)},
	"silence": {"abbr": "SIL", "color": Color(0.60, 0.74, 0.88)},
	"knockback": {"abbr": "KB", "color": Color(0.74, 0.69, 0.58)},
	"poison": {"abbr": "PSN", "color": Color(0.42, 0.80, 0.36)},
	"burn": {"abbr": "BRN", "color": Color(0.92, 0.52, 0.18)},
	"bleed": {"abbr": "BLD", "color": Color(0.85, 0.24, 0.24)},
	"doom": {"abbr": "DOOM", "color": Color(0.55, 0.24, 0.62)},
	"blind": {"abbr": "BLND", "color": Color(0.62, 0.55, 0.70)},
	"vulnerable": {"abbr": "VULN", "color": Color(0.62, 0.55, 0.70)},
	"healblock": {"abbr": "HBLK", "color": Color(0.62, 0.55, 0.70)},
	"haste": {"abbr": "HASTE", "color": Color(0.35, 0.78, 0.90)},
}

## Obstacle dressing — `kind` (from `arena_layout.gd`'s `KIND_TABLE`) picks the mesh/texture,
## `grade` (already handled below) picks the height, exactly as the brief specifies: what a
## player sees matches what the sim applies.
const OBSTACLE_TEX := {
	"barrel": "res://assets/arena/barrel-wood.jpg",
	"crate": "res://assets/arena/crate-wood.jpg",
	"planter": "res://assets/arena/planter-soil.jpg",
	"low_wall": "res://assets/arena/low-wall-brick.jpg",
	"low_wall_border": "res://assets/arena/stone-block.jpg",
	"pillar": "res://assets/arena/pillar-stone.jpg",
	"bench": "res://assets/arena/bench-wood.jpg",
	"fence": "res://assets/arena/fence-timber.jpg",
	"boulder": "res://assets/arena/boulder-rock.jpg",
	"shrine": "res://assets/arena/shrine-marble.jpg",
}
## Kinds without an authored texture of their own are tinted (StandardMaterial3D.albedo_color
## multiplies albedo_texture) so each still reads as distinct rather than silently reusing an
## unrelated kind's look — planter vs crate, fence vs low_wall, boulder/shrine vs pillar.
## ⚠️ THE BLOCKING KINDS NEEDED ONE AND DID NOT HAVE ONE, AND THAT SHOWED THE MOMENT THE IMPORTED
## `metallic = 0.4` WAS CORRECTED. Those two models carry a near-white region of their atlas, so
## with the fake metal removed they rendered at nearly full diffuse — four large WHITE slabs, which
## is a worse version of the original complaint: the majors are the biggest objects on the board
## and they became the brightest things in frame, above the creatures. Dressed stone here, so they
## sit below the cast and above the floor, which is the order the value ladder needs.
## ⚠️ REBALANCED 2026-08-08 FROM MEASURED FRAMES, NOT FROM TASTE, AND THE MEASUREMENT SAID EVERY
## SINGLE KIND WAS WRONG. `_probe_venue.gd`'s per-kind pass samples each prop's lit top face out of
## the rendered frame and compares it with the floor and with the creatures. Before this change,
## against a floor of 0.325 and a cast of 0.337:
##
##     pillar 2.03x floor · barrel 1.84 · fence 1.81 · boulder 1.73 · low_wall_border 1.55
##     crate 1.47 · low_wall 1.29 · bench 1.03 · planter 0.75          (0 of 9 kinds correct)
##
## Six kinds were drawn between 1.4x and 2.0x THE VALUE OF THE CREATURES STANDING AMONG THEM. On a
## board now carrying a hundred pieces that is not a subtle fault: the eye lands on the furniture.
##
## ⚠️ AND THE CAUSE WAS STRUCTURAL, NOT A BAD COLOUR. The floor takes `LEAGUE_LOOK.ground` (0.36 at
## Platinum, 0.92 at Iron — a 2.6x spread), the barrier takes it, the stands take it, and the props
## took NOTHING. So last round's grand-circuit tone-down darkened the ground out from under a set of
## props that stayed exactly where they were, and the prop/floor relationship became a different
## number in every league. The fix is that props now take the league tone too (see `_prop_material`)
## — the ladder then holds by construction rather than by eleven separate strokes of luck.
##
## The values below are therefore the kind's own MATERIAL identity at a reference ground of 1.0.
## Each was moved by the ratio the probe measured, targeting ~1.20x the floor: an object standing on
## the ground reads a little above it, and stays far under the cast.
##
## ⚠️ RE-RUN THE PROBE AFTER TOUCHING ANY ROW HERE. Albedo is not luminance — the league tone, the
## FILMIC curve and the model's own texture all sit between this number and the pixel, which is
## exactly why the previous set of hand-picked values measured 0 for 9.
## ⚠️ SECOND PASS, SAME METHOD: the first correction landed every kind at 1.5x the floor against a
## 1.25 target and left `crate` at 2.00, so each row is multiplied by (target / measured) again.
## Two passes rather than one because the response is not linear — the FILMIC curve compresses the
## top end, so a tint change moves the pixel by less than itself up there. Iterating a measurement
## is cheap; guessing a curve is not.
##
## ⚠️ AND `low_wall_border` CARRIES A SECOND, SEPARATE CORRECTION FOR CHROMA. Its art
## (`low-wall-brick.jpg`) is a saturated red-orange, and it stayed the loudest thing in frame at a
## luminance that measured perfectly in band — because VALUE IS NOT THE ONLY CHANNEL THE EYE SORTS
## ON. `ART_BIBLE_GUILD_COLOURS.md` reserves saturation for the team and status channels and asks
## the venue to be muted; three saturated orange slabs on a brown floor break that on their own.
## The tint pulls red down relative to green and blue, which desaturates the brick toward the
## league's masonry without repainting the texture.
const OBSTACLE_TINT := {
	# ⚠️ `planter` REPORTS "SINKS INTO FLOOR" AND THAT REPORT IS NOT TRUSTWORTHY — DO NOT TUNE THIS
	# ROW. It has the same signature as `crate` below: raised x1.27 (to 1.65/2.03/1.40) on 2026-08-08
	# and the probe returned luma 0.243, ratio 1.02, sat 0.085 — IDENTICAL TO THREE DECIMALS to the
	# run before. A number that does not move when you change what produces it is not measuring that
	# thing, and that is now TWO kinds behaving this way, which makes it an instrument fault rather
	# than a coincidence. Both are small props (0.61 and 0.44 bodies); the per-kind sampler almost
	# certainly misses them at whole-venue framing. The change was REVERTED to this measured-neutral
	# value rather than shipped blind. Fix the sampler first, then re-measure this row.
	"planter": Color(1.30, 1.60, 1.10),
	"fence": Color(0.70, 0.64, 0.53),
	"boulder": Color(0.62, 0.57, 0.51),
	"shrine": Color(0.56, 0.52, 0.42),
	"low_wall": Color(0.60, 0.56, 0.52),
	"low_wall_border": Color(0.38, 0.44, 0.46),
	"pillar": Color(0.45, 0.43, 0.41),
	# ⚠️ `crate` IS SET BY ANALOGY, NOT BY MEASUREMENT, AND THAT IS DELIBERATE — ITS MEASUREMENT IS
	# NOT TRUSTWORTHY. Across FOUR runs with three different tints (0.96 -> 0.60 -> 0.37) the probe
	# returned 0.477 every time, to three decimals, while all eight other kinds tracked their factor
	# within a few percent. A number that will not move when you change the thing that produces it
	# is not measuring that thing. The standing suspicion is the sample point: a 0.44-body crate is
	# a few screen pixels at whole-venue framing and eleven guild banners hang at y≈3.0 across the
	# far barrier, so an unprojected crate top near that end can land on a banner instead. UNTIL
	# THAT IS RESOLVED, DO NOT KEEP CUTTING THIS ROW TO CHASE THE NUMBER — three more halvings would
	# have left crates black on the evidence of an instrument fault. It is set to match `barrel`,
	# which shares the wood art AND measures correctly (1.36x floor, 0.74x cast).
	"crate": Color(0.72, 0.66, 0.55),
	"barrel": Color(0.75, 0.69, 0.60),
	"bench": Color(1.26, 1.19, 1.07),
}
## ⚠️ AN UNLISTED KIND IS NOT WHITE ANY MORE. `barrel` and `bench` fell through to Color(1,1,1) and
## measured 1.84x and 1.03x the floor — the un-tinted default was itself one of the brightest things
## on the board. A teammate is adding kinds; a kind nobody has tuned yet should arrive slightly
## under-lit and quiet, never as the loudest object in the venue.
const PROP_TINT_DEFAULT := Color(0.64, 0.61, 0.56)
## How far above its league's FLOOR a cover piece is drawn. ⚠️ >1 on purpose and the direction
## matters: cover reading BELOW the floor stops being an object standing on the ground and becomes
## a stain on it (measured: `planter` at 0.75x, which is what that looks like). Calibrated so the
## kind set averages ~1.2x the floor once the league tone is applied.
## ⚠️ 1.28 -> 1.38 after the second measurement. At 1.28 the kind set landed at 1.20-1.34x the
## floor, which is the target — but the leagues with the PALEST ground art (Tin 0.309, Silver
## 0.277, Platinum 0.210) had their cover reading level with or under their floor, because a prop
## takes the league's `ground` MULTIPLIER but never sees how bright that league's ground TEXTURE
## is. The lift is the blunt instrument that keeps the darkest case above water; the sharp one
## would be a per-league prop factor measured off each ground, which is worth doing the next time
## the ground art moves and is not worth doing speculatively now.
const PROP_LIFT := 1.38
const OBSTACLE_FALLBACK := {
	"barrel": Color(0.44, 0.32, 0.20), "crate": Color(0.50, 0.38, 0.24),
	"planter": Color(0.40, 0.52, 0.34), "low_wall": Color(0.55, 0.53, 0.50),
	"low_wall_border": Color(0.52, 0.50, 0.47), "pillar": Color(0.50, 0.48, 0.45),
	"bench": Color(0.52, 0.40, 0.26), "fence": Color(0.58, 0.47, 0.32),
	"boulder": Color(0.46, 0.43, 0.38), "shrine": Color(0.56, 0.50, 0.38),
}

## Kinds whose PRIMITIVE fallback is a cylinder rather than a box. ⚠️ A LIST, NOT AN `if kind ==`
## CHAIN, because a teammate is adding kinds: an unlisted kind falls to a box, which is a plausible
## object, where the old inline test silently made every new round thing square.
const ROUND_KINDS := ["barrel", "boulder", "urn", "brazier", "cairn"]

const PROJECTILE_COLOUR := {
	"ranged": Color(0.95, 0.85, 0.45), "magic": Color(0.55, 0.62, 0.95),
	"support": Color(0.55, 0.90, 0.65), "melee": Color(0.90, 0.90, 0.92),
}

var camera: Camera3D
var overlay: CanvasLayer
var plates_root: Control
var log_view: RichTextLabel
var log_scroll: ScrollContainer
var banner: PanelContainer
var banner_box: VBoxContainer
var banner_title: Label
var banner_sub: Label
var callout: PanelContainer
var callout_title: Label
var callout_body: RichTextLabel
var mode_label: Label
var resolving_label: Label

var team_a: Array = []
var team_b: Array = []
var all_units: Array = []          # fixed order: A then B — matches frame `id`
var nodes: Array = []              # parallel to all_units: {holder, sprite, plate, hp_fill, ...}
var league_name := "Platinum"

var result: Dictionary = {}
var frames: Array = []
var ground_size := Vector2(160, 88)
var frame_pos := 0.0               # fractional frame index — we interpolate between ticks
var playing := false
var speed := 1.0
var opening_timer := 0.0
var logged_upto := 0
var event_log: Array = []

var selected_idx := -1             # Tier-2 disclosure — one unit's callout open at a time
var shadow_mm: MultiMesh
var vfx = null   # BattleVfx — untyped, BUILD_CONTRACT §4 on bare class_name refs
var spectators = null   # the crowd (spectators.gd)
var _move_by_name := {}   # ability name -> move dict, for play_ability dispatch = null
var _projectile_nodes: Dictionary = {}   # projectile id -> MeshInstance3D
var _seen_tick := -1
var _last_intent: Dictionary = {}        # unit id -> last-seen intent string (transition-only log)

var _cam_max_span := 30.0
var _cam_center := Vector3.ZERO
var _cam_span := 30.0
## Camera modes (user direction 2026-08-06). TEAM is the default — the fight framed from YOUR
## side's point of view (the old all-units follow collapsed onto lone survivors and read as
## "stuck to one monster"). ACTION is that all-units follow, ARENA the wide instrument, FREE is
## manual: hold LMB to pan, wheel to zoom — any mouse camera input enters FREE; C returns.
enum CamMode { TEAM, ACTION, ARENA, FREE }
# ⚠️ ACTION IS THE DEFAULT NOW. It used to be indistinguishable from TEAM — both fitted the
# bounding box of the units `_write_back_final` had already marked as the fight's survivors, so
# `docs/WATCH_AUDIT.md` measured the two modes returning BYTE-IDENTICAL framing and pressing `C`
# between them doing nothing. ACTION is a director (`_director_target`); TEAM is the owner's box
# seat over your own line; ARENA is the whole ground. Three genuinely different shots.
var _audio: Node = null            # battle_audio.gd, or null — an OPTIONAL dependency (see _ready)
var _audio_speed := -1.0           # last value pushed to the mixer; only changes are pushed
var _audio_muted := false
var _cam_mode: int = CamMode.ACTION
var _free_center: Vector3 = Vector3.ZERO
var _free_span: float = 60.0
var _panning := false
var _layout_name: String = "four_pillar"


func _ready() -> void:
	# ⚠️ ORDER MATTERS, AND IT CHANGED (2026-08-04): `SpatialSim.run()` is now a COROUTINE —
	# `NavigationServer3D` only syncs a freshly-baked navmesh on real `SceneTree` frames, so the
	# sim awaits `process_frame` before its first pathfinding query. `_ready()` cannot block on
	# that, so the build order is: resolve teams -> build the overlay (so a "resolving" state has
	# somewhere to show) -> prepare the LAYOUT synchronously (obstacles + ground size, both
	# deterministic from team size alone, no positions needed yet) -> build the static world from
	# that layout -> THEN await the fight -> THEN build the units and start playback. A frozen
	# first frame while a coroutine silently runs is worse than a deliberate "resolving…" label.
	_resolve_teams()
	_build_overlay()
	_prepare_layout()
	var VfxScript = load("res://scripts/ui/vfx.gd")
	vfx = VfxScript.new()
	add_child(vfx)
	# THE CROWD — monster spectators on the apron, reacting to the fight's beats. fill is a
	# parameter because FAME drives attendance (standing rule), not arena size.
	var SpecScript = load("res://scripts/ui/spectators.gd")
	spectators = SpecScript.new()
	add_child(spectators)
	spectators.build(ground_size, _to_world, 1.0)   # full house for the demo; FAME takes this over
	# ── AUDIO ─────────────────────────────────────────────────────────────────────────────────
	# ⚠️ 700 LINES OF MIX ENGINEERING REACHED ONLY THE DEV SCENE UNTIL NOW. `docs/WATCH_AUDIT.md`
	# §5: `battle_audio.gd` + `cues.gd` handle all 22 sim event kinds, and the production 5v5
	# behind "Watch a Battle" played in total silence because nothing here called them. It is an
	# OPTIONAL dependency exactly as it is in `_watch_sim.gd` — a missing file or a bank that will
	# not render leaves `_audio` null and the fight silent, which is the game we already had,
	# rather than taking the watch scene down.
	if ResourceLoader.exists("res://scripts/audio/battle_audio.gd"):
		var audio_script = load("res://scripts/audio/battle_audio.gd")
		if audio_script != null:
			_audio = audio_script.new()
			add_child(_audio)
	for gmv in GameData.moves:
		_move_by_name[str(gmv["name"])] = gmv
	_build_world()
	_show_resolving(true)
	await _resolve_fight()
	_show_resolving(false)
	_update_mode_label()
	_build_units()
	_build_innate_tells()
	playing = true


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# SIM
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _resolve_teams() -> void:
	var career := get_node_or_null("/root/Career")
	var size := 5
	var from_career: bool = career != null and not TacticsScript.committed.is_empty()
	if from_career:
		league_name = career.current_league_name()
		size = career.current_team_size()

	var cup := get_node_or_null("/root/CupRun")
	if cup != null and cup.league_idx >= 0 and career != null:
		# The cup may be fighting a league BELOW the player's current frontier (punching down) —
		# the arena's league art/cap label must reflect the cup being fought, not the frontier.
		league_name = career.league_at(cup.league_idx).get("name", league_name)

	# ⚠️ PREFER THE EXACT TEAMS "The Read" SHOWED THE PLAYER. `Tactics.commit()` now carries
	# `teamA`/`teamB` verbatim — regenerating a fresh rival team here (the old behaviour) could
	# silently fight a DIFFERENT roster than the one that was scouted and ordered against. See
	# `tactics.gd:commit()`'s own doc comment for the finding.
	var committed_team_a: Array = TacticsScript.committed.get("teamA", [])
	var committed_team_b: Array = TacticsScript.committed.get("teamB", [])
	if not committed_team_a.is_empty() and not committed_team_b.is_empty():
		team_a = committed_team_a
		team_b = committed_team_b
	else:
		var roster := get_node_or_null("/root/Roster")
		if from_career and roster != null and not roster.monsters.is_empty():
			team_a = roster.monsters.slice(0, mini(size, roster.monsters.size()))
			team_b = roster.make_rival_team(team_a.size(), 0.3)
		else:
			for i in range(size):
				team_a.append(GameData.make_monster(Art.ROSTER[i % Art.ROSTER.size()], 0.3))
				team_b.append(GameData.make_monster(Art.ROSTER[(i + 5) % Art.ROSTER.size()], 0.3))
	all_units = team_a + team_b


## SYNCHRONOUS. Ground size and cover are both deterministic from team size + a seed alone — the
## exact formula `SpatialSim` uses internally too (`Sp.ground_size`) — so the static world (floor,
## walls, stands, obstacles, camera max-zoom) can be built before the fight itself has run.
func _prepare_layout() -> void:
	var team_size: int = maxi(team_a.size(), team_b.size())
	ground_size = Sp.ground_size(team_size)
	_obstacles = []
	# ⚠️ THE SIM MUST SEE THE SAME WORLD THE PLAYER DOES. Suppressing obstacles in the renderer
	# while still handing them to `SpatialSim` would leave units pathing around, and taking cover
	# behind, barrels that are not on screen — the fight would look irrational for reasons nothing
	# visible could explain. So the switch has to cut here, before generation, not at draw time.
	if not SHOW_OBSTACLES:
		return
	if ResourceLoader.exists(ARENA_LAYOUT_PATH):
		var LayoutScript = load(ARENA_LAYOUT_PATH)
		if LayoutScript != null and LayoutScript.has_method("generate"):
			var rng := RandomNumberGenerator.new()
			rng.seed = 20260804
			# The committed orders carry which composition to fight on, so the same screen serves
			# the cup, the sandbox and the viewer without any of them special-casing the others.
			var want_layout: String = str(TacticsScript.committed.get("layout", "four_pillar"))
			var lay: Dictionary = LayoutScript.generate(team_a.size(), league_name, rng, want_layout)
			_layout_name = str(lay.get("layout", want_layout))
			_obstacles = lay.get("obstacles", [])


## ASYNC. ⚠️ `SpatialSim.run()` is a coroutine (2026-08-04) — `NavigationServer3D.map_get_path()`
## returns an empty path with no error until a freshly-baked navmesh has synced across a real
## `SceneTree` frame, and `SpatialSim` has no frame loop of its own, so it awaits `process_frame`
## before its first query. Missing the `await` here does not error — it hands back a
## `GDScriptFunctionState` instead of the result Dictionary, so `frames`/`winner` silently come
## back empty and the arena renders nothing, which looks exactly like a rendering bug and isn't
## one. If this screen ever goes blank, check this line first.
func _resolve_fight() -> void:
	var committed: Dictionary = TacticsScript.committed
	# ⚠️ Prefer the spatial sim; fall back to the non-spatial one if it hasn't landed. The fallback
	# is NOT a shrug — `battle_sim.gd` is deliberately kept as the reference implementation so
	# there is always a control to judge the spatial layer against, and so this screen still runs
	# while the spatial streams are mid-flight.
	# ⚠️ THE COMMIT STORES `ordersA`/`ordersB`; THIS READ SAID `orders` — A KEY THAT HAS NEVER
	# EXISTED. Every per-monster order the tactics screen sold (temperament, target priority,
	# positional intent, guard) silently fell to `{}` in the career path, making the entire
	# per-monster column cosmetic. The seventh feature found built-and-unreachable. Both sides'
	# orders merge into one dict — the sim looks units up by instance, so the keys never collide.
	var orders: Dictionary = {}
	for k in (committed.get("ordersA", {}) as Dictionary):
		orders[k] = committed["ordersA"][k]
	for k in (committed.get("ordersB", {}) as Dictionary):
		orders[k] = committed["ordersB"][k]
	# A dragged chip becomes a real start: inject the committed placement into that monster's own
	# orders, where `spatial_sim._deploy()` now reads it (validated sim-side against the shared
	# deploy_zone — the sim, not the UI, owns what is legal).
	for m in (committed.get("deployA", {}) as Dictionary):
		if not orders.has(m):
			orders[m] = {}
		orders[m]["deployPos"] = committed["deployA"][m]
	# ⚠️ DETERMINISTIC PER FIGHT, DIFFERENT ACROSS FIGHTS. This was the literal 20260804 — every
	# fight in every cup rolled the same sim rng. Career fights now derive from where the career
	# actually is; replaying the same round reproduces it exactly, the next round does not.
	var fight_seed := 20260804
	var career2 := get_node_or_null("/root/Career")
	var cup2 := get_node_or_null("/root/CupRun")
	if career2 != null and not committed.is_empty():
		fight_seed = hash([int(career2.week), int(career2.league_index),
			int(cup2.current_round) if cup2 != null else 0])
	# ⚠️ NO BRANCH, NO FALLBACK — the seam came out 2026-08-08. See the header note above.
	result = await _run_new_sim(fight_seed)

	event_log = result.get("log", [])
	frames = result.get("frames", [])
	# Overwrite with the stream's own authoritative value, per "the renderer derives nothing" —
	# `_prepare_layout()`'s copy is the same formula and only exists so the world could be built
	# before the fight resolved; this is the one that actually came from the sim.
	ground_size = result.get("groundSize", ground_size)
	if result.has("obstacles"):
		_obstacles = result["obstacles"]


var _obstacles: Array = []


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# THE NEW STACK — build it, run it, translate its stream into the contract this screen speaks
# ═══════════════════════════════════════════════════════════════════════════════════════════════
#
# ⚠️ THE TWO CONTRACTS, WRITTEN DOWN, because the whole switch hangs on the differences:
#
#   field            legacy (`spatial_sim.gd:_record_frame`)  new (`sim/sim.gd:_emit_frame`)
#   ───────────────  ──────────────────────────────────────  ─────────────────────────────────
#   frame clock      `t`, seconds                            `tick`, int  (× `Sim.DT`)
#   unit key         `id`, int index into `all_units`         `id`, String ("a00"/"b03")
#   statuses         [String]                                 [{kind, left}]   ← RICHER
#   movement         `moveDir`                                `move_dir`
#   states           idle/advance/retreat/attack/stunned/cast  idle/advance/cast/dead
#   per-unit extras  targetId, weary                           team, max_hp, max_mp, posture
#   shots            `shots` (impact records)                  `events` (17 kinds)
#   projectiles      {id, from, to, progress, kind}            {from, target_id, pos, move,
#                                                               will_hit, aim}   ← RICHER
#   result           winner/duration/log/survivors/ground      winner/ticks/frames/decision_logs
#
# WHERE THE NEW STREAM IS RICHER (follow-up wins, none taken this pass so the switch stays one
# change): per-status REMAINING SECONDS (the plate could count a stun down instead of showing a
# bare chip); `posture` (the tree's own words for what it is doing, which is a better ticker line
# than `intent`); `will_hit` on a projectile in flight (a doomed shot could read differently
# BEFORE it lands — the single most legible thing an autobattler can show); `max_hp`/`max_mp` on
# the frame itself, which would retire this file's one honest read of static roster data.
#
# WHERE THE NEW STREAM IS MISSING SOMETHING THIS SCREEN USED — stated, never worked around:
#   • `weary` — the care loop (`innate_fx.gd`: potency-scaled innates, the weary flag, startWard)
#     is NOT wired into `sim/sim.gd` at all. The pseudo-status chip now never lights. Raising a
#     monster once again changes its numbers and nothing else on the field.
#   • GRADED COVER — `sim/sim.gd` hands obstacles to navigation and nothing else. The soft/hard
#     accuracy debuff (`Spatial.cover_between`) has no consumer, so cover is currently pathing
#     furniture only. `SPATIAL_COMBAT_DESIGN.md`'s graded cover is unbuilt on the new stack.
#   • `targetId` — absent. Nothing reads it here, so nothing broke; noted so a future focus-line
#     overlay knows it must be added sim-side rather than guessed at.
#   • ~~`manmark`~~ — WIRED 2026-08-09. `combat_tree.build()` seeds `ordered_id` from the tactics
#     dict itself on the first descent, so the mark never needed the sim to fill a blackboard key.
#     `_new_sim_tactics` now sends `target_priority: "marked"` + `ordered_id`. See there.
#
# ⚠️⚠️ AND THE ONE THAT COSTS A WHOLE FIGHT IF YOU MISS IT: THE TWO ENGINES USE DIFFERENT
# COORDINATE ORIGINS. `Spatial.deploy_positions`/`deploy_zone`/`clamp_to_ground` — and therefore
# this file's `_to_world`, the deployment board and every obstacle rect — put the board's CORNER
# at (0,0) and span [0,W]x[0,H]. `sim/nav_service.build()` lays its floor CENTRED on the origin,
# spanning [-W/2,W/2]x[-H/2,H/2] (`_watch_sim.gd` deploys at x=±38 on a 110-wide ground, which is
# what makes it visible). Feeding corner-frame positions to the new sim puts every unit clean off
# the navmesh: `map_get_path` returns empty, nobody moves, and the fight runs to the 1800-tick cap
# looking exactly like a broken AI. MEASURED HERE: the first run of this switch produced 1800
# frames (the cap) instead of the legacy 252. The offset below is the entire fix — sim-side is
# centred, renderer-side is corner, and the translation happens on the boundary in both directions.


## Build, run and translate. Returns a LEGACY-shaped result dict so `_resolve_fight` and every
## consumer below it (playback, report_ui, cup continuation) need no change.
func _run_new_sim(fight_seed: int) -> Dictionary:
	var us: Array = _new_sim_inputs()
	# ⚠️ ONLY `blocking`-grade obstacles carve the navmesh. `nav_service.build()` carves EVERY
	# rect it is handed, and the graded-cover design is explicit that soft/hard pieces are
	# furniture you walk through and shoot worse across — carving them would make five barrels
	# into five walls. The legacy sim made the same split at its own bake; it has to be made
	# HERE now because the new sim takes the list as given.
	var off: Vector2 = ground_size * 0.5
	var nav_obstacles: Array = []
	for ob in _obstacles:
		if str((ob as Dictionary).get("grade", "blocking")) == Sp.COVER_BLOCKS_LOS_GRADE:
			var r: Rect2 = (ob as Dictionary)["rect"]
			nav_obstacles.append({"rect": Rect2(r.position - off, r.size)})
	var sim = NewSim.new()
	sim.setup(fight_seed, us, ground_size, nav_obstacles)
	# The probe pair spans the board along the deploy axis — the same shape `_watch_sim.gd` uses.
	var half_x: float = ground_size.x * 0.5 - 4.0
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-half_x, 0), Vector2(half_x, 0))
	if not ok:
		# Honest failure: a navmesh that never synced would otherwise produce a fight where every
		# unit stands still, which reads as a rendering bug and is not one.
		push_error("arena_3d: navigation never became ready — the fight cannot resolve")
		return {"winner": "draw", "duration": 0.0, "log": [], "frames": [],
			"survivorsA": team_a.size(), "survivorsB": team_b.size(),
			"groundSize": ground_size, "obstacles": _obstacles}
	var raw: Dictionary = sim.run()
	sim.nav.free_rids()   # the teardown every discarded sim owes (nav_service.gd)
	var adapted: Dictionary = _adapt_result(raw)
	# ⚠️ ONE LINE THAT WOULD HAVE CAUGHT THE COORDINATE BUG IMMEDIATELY. A fight that runs to the
	# 1800-tick cap with an empty log is a sim that never engaged; a headless probe reading only
	# `frames.size()` cannot tell that from a long fight. Mirrors `_watch_sim.gd`'s own WATCH line.
	print("ARENA: winner=%s ticks=%d frames=%d events=%d survivors=%d/%d" % [
		str(adapted.winner), int(raw.get("ticks", 0)), (adapted.frames as Array).size(),
		(adapted.log as Array).size(), int(adapted.survivorsA), int(adapted.survivorsB)])
	return adapted


## `all_units` order IS the address space of this whole file — `nodes[k]`, `all_units[k]` and
## every frame record share the index. The new sim sorts its units by STRING id, so the ids are
## authored `a00…`/`b00…` with zero padding so that sort reproduces exactly this order. The
## assert in `_adapt_result` proves it rather than trusting it.
func _new_sim_inputs() -> Array:
	var committed: Dictionary = TacticsScript.committed
	var team_size: int = maxi(team_a.size(), team_b.size())
	var pos_a: Array = Sp.deploy_positions(team_size, "A")
	var pos_b: Array = Sp.deploy_positions(team_size, "B")
	var deploy_a: Dictionary = committed.get("deployA", {})
	var off: Vector2 = ground_size * 0.5   # corner-frame -> centre-frame (see the ⚠️⚠️ above)
	var out: Array = []
	for k in range(all_units.size()):
		var m = all_units[k]
		var side := "A" if k < team_a.size() else "B"
		var slot: int = k if side == "A" else k - team_a.size()
		var src: Array = pos_a if side == "A" else pos_b
		var p: Vector2 = src[slot] if slot < src.size() else src[src.size() - 1]
		if side == "A" and deploy_a.has(m):
			# The dragged chip is a real start — clamped to the legal zone by the SAME rule the
			# legacy sim enforced sim-side (`Sp.deploy_zone` owns what is legal, not the board).
			var zone: Rect2 = Sp.deploy_zone(team_size, "A")
			var want: Vector2 = deploy_a[m]
			p = Vector2(clampf(want.x, zone.position.x, zone.position.x + zone.size.x),
				clampf(want.y, zone.position.y, zone.position.y + zone.size.y))
		var names: Array = []
		for mv in m.moveset:
			names.append(str((mv as Dictionary).get("name", "")))
		out.append({
			"id": ("a%02d" % slot) if side == "A" else ("b%02d" % slot),
			"team": side,
			"pos": p - off,
			"stats": m.stats,
			# `Sp.speed_of` is the arena's own scale-aware speed curve — the same one the legacy
			# sim moved bodies with, so the fight closes at the pace the board was sized for.
			"speed": Sp.speed_of(float(m.stats.get("DEX", 10.0))),
			"kit": KitLib.build(names, GameData.moves),
			"tactics": _new_sim_tactics(m, side),
		})
	return out


## THE ORDERS TRANSLATION. `tactics.gd`'s vocabulary is camelCase and mirrors `core.ts`; the
## tree's is snake_case. ⚠️ THIS IS WHERE THE POSITIONAL INTENT FINALLY BECOMES REAL — the
## deployment board has stored `positionalIntent` (hold/push/wings/dive/guard) and `guardedAlly`
## for months against a sim that read neither (`tactics.gd`'s own header says so). `combat_tree`
## takes exactly those five values, so the switch turns the eighth built-and-unreachable feature
## on by wiring rather than by writing anything new.
func _new_sim_tactics(m, side: String) -> Dictionary:
	var committed: Dictionary = TacticsScript.committed
	var plan: Dictionary = committed.get("planA" if side == "A" else "planB", {})
	var orders: Dictionary = committed.get("ordersA" if side == "A" else "ordersB", {})
	var own: Dictionary = orders.get(m, {})
	var t: Dictionary = {}

	var tp := str(own.get("targetPriority", plan.get("targetPriority", "")))
	match tp:
		"casters": t["target_priority"] = "casters"
		"tanks": t["target_priority"] = "tanks"
		"manmark":
			# ⚠️ THIS WAS THE NINTH BUILT-AND-UNREACHABLE FEATURE. The comment above used to say
			# `manmark` "has no live consumer"; it has one — `combat_tree.build()` takes
			# `target_priority == "marked"`, seeds `ordered_id` from the tactics dict on its first
			# descent, releases a dead mark and holds it against the execute-window steal, and
			# `_probe_combat_tree.gd` asserts the whole path. Man mark is the ONE order that asks
			# the player to do scouting work, and until now it was a gold border on a portrait.
			# A mark with nobody marked is the documented fall-through (`tactics.gd` §pick_target).
			var mark = plan.get("markedUnit")
			var mi_k: int = all_units.find(mark) if mark != null else -1
			if mi_k >= team_a.size():
				t["target_priority"] = "marked"
				t["ordered_id"] = "b%02d" % (mi_k - team_a.size())
			elif mi_k >= 0:
				t["target_priority"] = "marked"
				t["ordered_id"] = "a%02d" % mi_k
			else:
				t["target_priority"] = "weakest"
		_: t["target_priority"] = "weakest"

	var intent := str(own.get("positionalIntent", plan.get("positionalIntent", "")))
	t["positional"] = intent if intent in ["hold", "push", "wings", "dive", "guard"] else "push"
	if t["positional"] == "guard":
		var charge = own.get("guardedAlly")
		var ci: int = all_units.find(charge) if charge != null else -1
		if ci >= 0 and ci < team_a.size():
			t["guard_ally"] = "a%02d" % ci
		elif ci >= team_a.size():
			t["guard_ally"] = "b%02d" % (ci - team_a.size())
		else:
			# A guard with nobody to guard is a posture with no meaning — fall to holding the
			# line, which is what "stay near where you deployed" already means.
			t["positional"] = "hold"

	# `cautious` is `tactics.gd`'s compressed stand-in for the preserve axis; the tree's own
	# survival axis is `when_hurt`, and falling back IS what refusing to trade down looks like
	# on a field with positions. aggressive/balanced remain the engine default, as the UI says.
	t["when_hurt"] = "fall_back" if str(own.get("temperament", "balanced")) == "cautious" else "fight_on"
	# Mirror the flank so the two sides' wings do not converge on the same corner.
	t["wing_side"] = 1.0 if side == "A" else -1.0
	return t


## ── THE TRANSLATION ────────────────────────────────────────────────────────────────────────
## Pure re-keying of the new stream into the legacy contract. Every value below is READ from the
## stream; the only computed things are index-from-id, seconds-from-ticks, and the legacy state
## words `attack`/`stunned`, both of which the stream states as facts (a strike event with this
## unit as `from`; an `incapacitates` status in its own list) and neither of which is a guess
## about the fight.
func _adapt_result(raw: Dictionary) -> Dictionary:
	var off: Vector2 = ground_size * 0.5   # centre-frame -> corner-frame (see the ⚠️⚠️ above)
	var idx_of: Dictionary = {}
	for k in range(all_units.size()):
		var side := "A" if k < team_a.size() else "B"
		var slot: int = k if side == "A" else k - team_a.size()
		idx_of[("a%02d" % slot) if side == "A" else ("b%02d" % slot)] = k

	var raw_frames: Array = raw.get("frames", [])
	# ⚠️ PROVE THE ADDRESS SPACE, DO NOT ASSUME IT. `nodes[k]`, `all_units[k]` and every frame
	# record must share one index. The sim sorts by string id, so this holds only while the
	# zero-padded ids sort into roster order — an eleventh monster on a side ("a10" vs "a9")
	# is exactly the kind of thing that would break it silently, which is why it is padded AND
	# checked rather than either alone.
	if not raw_frames.is_empty():
		var first: Array = raw_frames[0].get("units", [])
		assert(first.size() == all_units.size(),
			"sim returned %d units for a roster of %d" % [first.size(), all_units.size()])
		for i in range(first.size()):
			assert(int(idx_of.get(str(first[i].get("id", "")), -1)) == i,
				"sim unit order does not match the roster order at index %d" % i)
			# ⚠️ AND PROVE THE FRAME. Corner-frame positions must land inside [0,W]x[0,H]; the
			# centre/corner mix-up above is invisible to every "did it run" check and produces a
			# fight rendered off the edge of the board, so it gets a tripwire of its own.
			var fp: Vector2 = (first[i].get("pos", Vector2.ZERO) as Vector2) + off
			assert(fp.x >= 0.0 and fp.x <= ground_size.x and fp.y >= 0.0 and fp.y <= ground_size.y,
				"unit %d deploys off the board at %s (ground %s)" % [i, fp, ground_size])
	var out_frames: Array = []
	var log: Array = [{"kind": "start", "t": 0.0}]
	var last_alive_a := team_a.size()
	var last_alive_b := team_b.size()

	for rf in raw_frames:
		var t: float = float(int(rf.get("tick", 0))) * NewSim.DT
		var events: Array = rf.get("events", [])
		# Who STRUCK this tick — the legacy `attack` state, taken from the event list rather
		# than derived from motion.
		var struck: Dictionary = {}
		for e in events:
			if str(e.get("kind", "")) in ["strike", "cast_done", "proj_hit", "miss", "cast_miss"]:
				struck[str(e.get("from", ""))] = true

		var units_out: Array = []
		var alive_a := 0
		var alive_b := 0
		for rec in (rf.get("units", []) as Array):
			var uid := str(rec.get("id", ""))
			var k: int = int(idx_of.get(uid, -1))
			var alive: bool = bool(rec.get("alive", true))
			if alive:
				if uid.begins_with("a"):
					alive_a += 1
				else:
					alive_b += 1
			var kinds: Array = []
			var incap := false
			for s in (rec.get("statuses", []) as Array):
				var kind := str((s as Dictionary).get("kind", ""))
				kinds.append(kind)
				if bool((GameData.field_status.get(kind, {}) as Dictionary).get("incapacitates", false)):
					incap = true
			var state := str(rec.get("state", "idle"))
			if alive:
				if incap:
					state = "stunned"
				elif state != "cast" and struck.has(uid):
					state = "attack"
			units_out.append({
				# centre-frame -> corner-frame; facing/move_dir are DIRECTIONS and never shift.
				"id": k, "pos": (rec.get("pos", Vector2.ZERO) as Vector2) + off,
				"facing": rec.get("facing", Vector2(1, 0)),
				"moveDir": rec.get("move_dir", Vector2.ZERO),
				# `weary` is not on the new stream at all (see the contract note) — emitted false
				# so the chip is honestly absent rather than randomly present.
				"weary": false,
				"castMove": str(rec.get("castMove", "")),
				"castFrac": float(rec.get("castFrac", 0.0)),
				"hp": float(rec.get("hp", 0)), "mp": float(rec.get("mp", 0)),
				"alive": alive, "state": state, "statuses": kinds,
				"targetId": -1,
				"intent": str(rec.get("intent", "")), "reason": str(rec.get("reason", "")),
			})
		last_alive_a = alive_a
		last_alive_b = alive_b

		var shots: Array = []
		# A projectile move emits `proj_launch` AND `cast_done` on the same tick — the damage is
		# committed at launch but ARRIVES later, so only the arrival (`proj_hit`) may draw an
		# impact. Without this the shot would flash twice: once in the shooter's face.
		var launched: Dictionary = {}
		for e in events:
			if str(e.get("kind", "")) == "proj_launch":
				launched["%s|%s" % [str(e.get("from", "")), str(e.get("move", ""))]] = true
		for e in events:
			var kind := str(e.get("kind", ""))
			var from_i: int = int(idx_of.get(str(e.get("from", "")), -1))
			var to_i: int = int(idx_of.get(str(e.get("to", "")), -1))
			match kind:
				"strike", "miss":
					shots.append({"fromId": from_i, "toId": to_i, "kind": "melee",
						"hit": kind == "strike", "dmg": int(e.get("dmg", 0)),
						"crit": bool(e.get("crit", false)), "move": "Attack", "arc": "front"})
				"cast_done", "proj_hit", "cast_miss":
					var mvn := str(e.get("move", ""))
					if kind == "cast_done" and launched.has("%s|%s" % [str(e.get("from", "")), mvn]):
						continue
					shots.append({"fromId": from_i, "toId": to_i,
						"kind": _shot_kind_of(mvn),
						"hit": kind != "cast_miss", "dmg": int(e.get("dmg", 0)),
						"crit": bool(e.get("crit", false)), "move": mvn, "arc": "front"})
			var le := _adapt_event(e, t)
			if not le.is_empty():
				log.append(le)

		var projs: Array = []
		for p in (rf.get("projectiles", []) as Array):
			var pd: Dictionary = p
			# The new stream carries no projectile id, so one is MINTED from the shot's own
			# identity (shooter + target + move) — stable across frames, which is all
			# `_find_projectile` needs to interpolate a streak between two frames.
			var pid: int = hash("%s>%s|%s" % [str(pd.get("from", "")), str(pd.get("target_id", "")),
				str(pd.get("move", ""))])
			projs.append({"id": pid, "from": (pd.get("pos", Vector2.ZERO) as Vector2) + off,
				"to": (pd.get("aim", pd.get("pos", Vector2.ZERO)) as Vector2) + off,
				"progress": 0.0,
				"kind": _shot_kind_of(str(pd.get("move", "")))})

		# ⚠️ THE RAW EVENT ARRAY TRAVELS WITH THE FRAME, UNTRANSLATED. `_adapt_event` renames
		# `strike` to `hit`, drops `from`, and returns {} for twelve kinds — feeding THAT to the
		# audio layer would silence most of the mix while looking correctly wired, which is this
		# project's signature failure in a new costume. The audio interface speaks the SIM's
		# vocabulary on purpose (`docs/WATCH_AUDIT.md` §5), so the sim's own events are kept
		# alongside the adapted log rather than reconstructed from it.
		out_frames.append({"t": t, "units": units_out, "shots": shots, "projectiles": projs,
			"events": events})

	var duration: float = float(int(raw.get("ticks", 0))) * NewSim.DT
	var winner := str(raw.get("winner", ""))
	if winner == "":
		winner = "draw"
	log.append({"kind": "end", "winner": winner, "duration": duration, "t": duration})
	# ⚠️ THE WRITE-BACK USED TO HAPPEN HERE AND IT SPOILED THE ENTIRE FIGHT. See
	# `_write_back_final`'s own comment: stamping the FINAL state onto the monster objects before
	# playback begins made `MonsterInstance.alive` the ANSWER rather than the current state, and
	# three systems read it — the scoreboard, the camera and the topple pass. It now runs in
	# `_finish()`, after the last frame has been shown. `docs/WATCH_AUDIT.md` §1.
	return {"winner": winner, "duration": duration, "log": log,
		"survivorsA": last_alive_a, "survivorsB": last_alive_b,
		"groundSize": ground_size, "obstacles": _obstacles, "frames": out_frames,
		"decisionLogs": raw.get("decision_logs", {})}


## A move's CHANNEL is what the VFX and projectile art key off. It comes from the authored move
## (already loaded into `_move_by_name` for the ability-VFX cascade), never from a guess.
func _shot_kind_of(move_name: String) -> String:
	var mv: Dictionary = _move_by_name.get(move_name, {})
	return str(mv.get("channel", "melee"))


## Event → legacy log record. The log dispatch (`_log_event`) addresses monsters by SPECIES NAME,
## so ids are resolved through `all_units` here — the one place the two vocabularies meet.
func _adapt_event(e: Dictionary, t: float) -> Dictionary:
	var from_n := _name_of_sim_id(str(e.get("from", "")))
	var to_n := _name_of_sim_id(str(e.get("to", "")))
	match str(e.get("kind", "")):
		"strike":
			return {"kind": "hit", "attacker": from_n, "target": to_n, "move": "Attack",
				"dmg": int(e.get("dmg", 0)), "crit": bool(e.get("crit", false)), "t": t}
		"cast_done", "proj_hit":
			return {"kind": "hit", "attacker": from_n, "target": to_n,
				"move": str(e.get("move", "")), "dmg": int(e.get("dmg", 0)),
				"crit": bool(e.get("crit", false)), "t": t}
		"miss":
			return {"kind": "miss", "attacker": from_n, "target": to_n, "move": "Attack", "t": t}
		"cast_miss":
			return {"kind": "miss", "attacker": from_n, "target": to_n,
				"move": str(e.get("move", "")), "t": t}
		"status_applied":
			return {"kind": "status_apply", "unit": to_n, "status": str(e.get("status", "")), "t": t}
		"status_expire":
			return {"kind": "status_expire", "unit": to_n, "status": str(e.get("status", "")), "t": t}
		"heal":
			return {"kind": "heal", "caster": from_n, "unit": to_n, "move": str(e.get("move", "")),
				"amount": int(e.get("amount", 0)), "t": t}
		"buff":
			return {"kind": "buff", "caster": from_n, "unit": to_n,
				"move": str(e.get("move", "")), "t": t}
		"cleanse":
			return {"kind": "cleanse", "by": from_n, "unit": to_n, "move": str(e.get("move", "")),
				"broke": e.get("broke", []), "t": t}
		"interrupt":
			# ⚠️ The new `interrupt` event names the KICKER and the victim but not the cast it
			# denied. The log line says so rather than inventing a move name.
			return {"kind": "interrupt", "unit": to_n, "move": "its cast",
				"reason": "%s kicked it" % from_n, "t": t}
		"death":
			return {"kind": "death", "unit": _name_of_sim_id(str(e.get("id", ""))), "t": t}
		# ── THE FOUR THAT WERE SILENT. `docs/WATCH_AUDIT.md` §4 ranked them by what their absence
		# costs the viewer; this is that order. Everything here is carried by the event itself —
		# the renderer resolves ids to names and centre-frame to corner-frame, and invents nothing.
		"taunted":
			# ⚠️ #1, and the reason it stayed invisible for so long is worth keeping written down:
			# `_log_event` had a branch that floated "TAUNTED" when a `status_applied` arrived with
			# `status == "taunt"`, and that branch could NEVER FIRE — taunt is not one of the
			# fifteen `fieldStatus` kinds, the sim stores it as `tgt["taunt"]` and announces it
			# with its own `taunted` event. Code that looks like it handles a mechanic is how a
			# mechanic goes missing. A forced target change is the single most important thing a
			# tank does and the single most inexplicable thing to watch unexplained.
			return {"kind": "taunted", "by": from_n, "unit": to_n,
				"seconds": float(e.get("seconds", 0.0)), "t": t}
		"aoe":
			# ⚠️ #2, and the sim wrote the spec: "THE BURST MUST BE VISIBLE OR IT IS NOT A
			# MECHANIC… The renderer draws this ring; it derives nothing — centre, radius and
			# count come from here" (`sim.gd:1585`). The whole "AoE is weak into one body and
			# strong into three" design is invisible without it.
			return {"kind": "aoe", "caster": from_n, "move": str(e.get("move", "")),
				"centre": (e.get("centre", Vector2.ZERO) as Vector2) + ground_size * 0.5,
				"radius": float(e.get("radius", 0.0)), "targets": int(e.get("targets", 0)),
				"falloff": float(e.get("falloff", 1.0)), "t": t}
		"fizzle":
			# ⚠️ #3 is the ambiguity the interrupt fix already ruled unacceptable: a cast bar that
			# silently disappears reads as "finished?" or "cancelled?" with no way to tell. Same
			# ambiguity, same fix — grey the bar and say why.
			return {"kind": "fizzle", "unit": from_n, "move": str(e.get("move", "")), "t": t}
		"debuff":
			# ⚠️ #4 is an ASYMMETRY the player will read as a rule. `buff` has a full grammar —
			# ring under the target, charge on the caster, green log line — and `debuff` had
			# nothing, so a viewer watched their own team visibly strengthen and never once saw an
			# enemy weakened. That teaches a false lesson about what the kits do.
			return {"kind": "debuff", "by": from_n, "unit": to_n, "move": str(e.get("move", "")),
				"seconds": float(e.get("seconds", 0.0)), "t": t}
		# ── AND THE TWO THAT ONLY BECAME MEASURABLE ONCE THE ROSTER COULD PRODUCE THEM.
		# ⚠️ `docs/WATCH_AUDIT.md` §4 listed `thorns` and `ward_soak` as "never fired, and that is
		# its own finding" — they were unrankable because the production roster had no thorns body
		# and no ward. With `watch.gd`'s composition fixed they fire 13 and 3 times in one fight,
		# and they are the two most confusing unexplained numbers on the board: HP that comes off
		# the ATTACKER, and damage that lands and does nothing.
		"thorns":
			# The reflect is a DEFENDER's mechanic that hurts the ATTACKER — the one event whose
			# damage travels backwards along the arrow the viewer just watched.
			return {"kind": "thorns", "by": from_n, "unit": to_n,
				"dmg": int(e.get("dmg", 0)), "t": t}
		"ward_soak":
			# `cues.gd` names the soak as one of the three contrasts the whole cue sheet exists to
			# carry. Silently eating a hit is indistinguishable from a miss on screen.
			return {"kind": "ward_soak", "by": from_n, "unit": to_n,
				"amount": int(e.get("amount", 0)), "t": t}
	return {}


func _name_of_sim_id(sim_id: String) -> String:
	if sim_id == "":
		return "?"
	var slot: int = sim_id.substr(1).to_int()
	var k: int = slot if sim_id.begins_with("a") else team_a.size() + slot
	return str(all_units[k].species_name) if k >= 0 and k < all_units.size() else "?"


## ⚠️ THE NEW SIM DOES NOT TOUCH THE MONSTER OBJECTS — it works entirely on its own dicts, which
## is correct (injected state, nothing global) but leaves every `MonsterInstance.alive` reading
## true forever. `_skip()`'s topple loop, the report screen and the career all read those, so the
## final frame is written back once here. This is bookkeeping the OLD sim did as a side effect of
## mutating the roster; doing it explicitly is the honest version of the same thing.
func _write_back_final(out_frames: Array) -> void:
	if out_frames.is_empty():
		return
	for rec in (out_frames[out_frames.size() - 1].get("units", []) as Array):
		var k: int = int(rec.get("id", -1))
		if k < 0 or k >= all_units.size():
			continue
		var m = all_units[k]
		m.hp = maxf(0.0, float(rec.get("hp", 0.0)))
		m.mp = float(rec.get("mp", 0.0))
		m.alive = bool(rec.get("alive", false))


## ⚠️ IS THIS UNIT STANDING **IN THE FRAME THE PLAYER IS LOOKING AT**? Every watch-surface
## question about aliveness must come through here, never from `all_units[k].alive` — that field
## is the fight's RESULT (written back by `_write_back_final` once playback ends) and reading it
## during the replay is how the scoreboard came to announce the winner at frame zero and the
## camera came to follow the eventual survivors from the opening walk (`docs/WATCH_AUDIT.md` §1,
## measured at 100% of frames disagreeing with the screen).
##
## `last_rec` is written by `_apply_frame` for the frame currently displayed, so this is the
## displayed truth by construction. Before the first frame is applied it is empty and everyone
## reads as standing, which is correct: nobody has died yet.
func _alive_now(k: int) -> bool:
	if k < 0 or k >= nodes.size():
		return false
	var rec: Dictionary = (nodes[k] as Dictionary).get("last_rec", {})
	if rec.is_empty():
		return true
	return bool(rec.get("alive", true))


func _show_resolving(v: bool) -> void:
	if resolving_label != null:
		resolving_label.visible = v


func _update_mode_label() -> void:
	if mode_label == null:
		return
	# ⚠️ Reports what is ON THE FIELD, not what the generator produced. With SHOW_OBSTACLES off
	# `_obstacles` is empty and the header said "124 obstacles" over an empty board — a HUD that
	# describes a world the player is not looking at is worse than no HUD.
	#
	# The "non-spatial fallback" arm of this label went with the seam: there is one engine now, so
	# a label that could announce a second one would only ever be able to lie.
	mode_label.text = "%s · %d frames · ground %d×%d · %d obstacles" % [
		_layout_name, frames.size(), int(ground_size.x), int(ground_size.y), _obstacles.size()]


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# WORLD
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## Ground coordinates (origin at a corner, +y = "north") -> world (origin at board centre, X/Z).
func _to_world(p: Vector2) -> Vector3:
	return Vector3(
		(p.x - ground_size.x * 0.5) * WORLD_SCALE,
		0.0,
		(p.y - ground_size.y * 0.5) * WORLD_SCALE)


func _build_world() -> void:
	var bw := ground_size.x * WORLD_SCALE
	var bd := ground_size.y * WORLD_SCALE

	# ── THE VENUE'S LIGHT. Three lamps, not one. ────────────────────────────────────────────────
	#
	# ⚠️ WHAT WAS HERE AND WHY IT READ AS UNFINISHED, stated so it cannot be reverted by accident:
	# ONE directional light at energy 1.0, against an ambient term of colour (0.68,0.70,0.76) at
	# energy 1.25. Ambient is direction-free by definition, so an ambient that strong is a flat
	# wash applied equally to every surface in the scene — the floor, the walls, the stands, the
	# top of a crate and its side all received roughly the same light, and the key had ~40% of the
	# total to shape anything with. The measured result (`_probe_venue.gd`) was a frame where the
	# creatures read at 0.85-1.04x the luminance of the floor they stood on, i.e. no value
	# separation at all, at every league. A fight the player cannot intervene in has to be legible
	# above everything else, so that is a design failure, not a polish one.
	#
	# The replacement is the standard three-lamp setup the direction already describes
	# (`ART_DIRECTION.md`: "a single warm key, cool sky bounce, everything past the wall falling
	# into dark"):
	#   KEY  — warm, strong, the only shadow-caster. Gives every object a lit face and a dark face.
	#   FILL — cool, weak, from the opposite side. Keeps shadow SIDES from going to black mush.
	#   RIM  — cool, from behind the far side, no shadow. Puts a cold edge on every silhouette so a
	#          body separates from the floor even when the two are the same value.
	# All three take their colours from `LEAGUE_LOOK`, so the ladder keeps a per-league lamp.
	var look := _look()

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = look["fog"]
	_apply_backdrop(e, look)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = look["amb"]
	e.ambient_light_energy = float(look["amb_e"])

	# ⚠️ TONEMAPPING, WHICH THE SCENE HAD NONE OF. Godot's default is LINEAR — highlights clip flat
	# and the whole frame sits in a narrow band, which is half of "washed". FILMIC rolls the top end
	# off so a lit face can be bright without becoming a white hole, and it is what lets the key
	# light run at 2.0 without blowing the floor out.
	# ⚠️ `tonemap_white` STAYS AT 1.0. It was tried at 1.6 — which maps 1.6 down to white and
	# therefore pulls every midtone with it — and the measured frame luminance fell to 0.09-0.14.
	# The brief was that the ground is BLINDING, not that the venue should become a cave; a frame
	# nobody can see is the same legibility failure wearing the opposite sign.
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_white = 1.0
	# ⚠️ THE VENUE IS GLOBALLY UNDER-EXPOSED AND EXPOSURE IS THE ONLY HONEST LEVER FOR IT. This was
	# 1.0, and four separate checks were failing on the same underlying fact: 37-47% of every hero
	# frame carried rows with a mean under 0.12 luma; the venue shell could not be lifted out of
	# that band without crossing the floor in the value ladder; four leagues' creatures failed to
	# out-value their ground; and the majors' new cast shadows read as holes rather than shade.
	#
	# ⚠️ AND THE DIAGNOSIS CAME FROM A CONTRADICTION, NOT FROM TASTE. Lifting the shell with a flat
	# multiplier bought the dead band back (0/11 -> 9/11) and broke the ladder (9/11 -> 4/11);
	# re-deriving the shell as a ratio of each league's own floor restored the ladder (9/11) and
	# gave most of the dead band back (0/11 -> 4/11). The two checks trade one-for-one, which is
	# the signature of a scale problem rather than a balance problem: no redistribution of a fixed
	# amount of light can satisfy both, because the ladder constrains RATIOS and the dead band
	# constrains ABSOLUTE values.
	#
	# Exposure is the one control that moves the absolute values while leaving every ratio alone.
	# The ladder, body-vs-floor, cover relief and contact shadow are all ratios or log-ratios, so
	# they are invariant to it by construction; only `dead-rows%`, `void%` and the `floor <= 0.62`
	# ceiling respond. That invariance is a PREDICTION and it is checked — if a ratio column moves
	# when this constant moves, the FILMIC curve is compressing the top end and the number is too
	# high, which is the failure to watch for rather than a bright frame.
	#
	# ⚠️ DO NOT REACH FOR `tonemap_white` INSTEAD. It was tried at 1.6 (see the note above) and it
	# maps 1.6 down to white, i.e. it changes the CURVE, which does move the ratios.
	e.tonemap_exposure = 1.28

	# Contact shadow and crevice darkening. `ART_DIRECTION.md` §Status names ambient occlusion as
	# one of the two biggest remaining quality jumps; this is it. It is also what stops a prop
	# looking like it is hovering — an object with no dark seam where it meets the ground reads as
	# pasted on, which is a large part of "the cover looks unfinished".
	e.ssao_enabled = true
	e.ssao_radius = 1.4
	e.ssao_intensity = 1.2
	e.ssao_power = 1.3
	e.ssao_light_affect = 0.1

	# ⚠️ FOG IS A DEPTH CUE HERE, NOT A GREY WASH — and it was being used as one. At density 0.004
	# with `fog_sky_affect` at its default of 1.0, the background colour itself was fogged, so the
	# near-black backdrop rendered as the same mid-slate as the board and the venue had no
	# silhouette against anything. Density comes down, sky affect goes to 0 (the backdrop already
	# IS the fog colour), and aerial perspective stays off because there is no sky to sample.
	#
	# ⚠️ AND THE DENSITY IS SCALED TO THE BOARD, WHICH IT WAS NOT. Fog density is a per-world-unit
	# absolute; the grounds are not the same size. A 1v1 board is ~40 world units across and a 5v5
	# is ~150, and the camera pulls back in proportion, so one fixed density meant Wood got almost
	# no fog and Platinum got its ENTIRE FLOOR blended ~40% toward the fog colour. That is what made
	# the big leagues read as a flat uniform slate with black props on it while the small ones
	# looked fine — measured frame luminance 0.180 at Bronze against 0.102 at Platinum off the same
	# lamp values. Expressed as "how much fog at the far edge of THIS board", it is scale-free, and
	# every league gets the same amount of depth cue. This is the same class of bug
	# `docs/ABILITY_BALANCE_REVIEW.md` records for the spatial constants — a bare world distance
	# that the board grew out from under.
	var diag: float = maxf(30.0, Vector2(bw, bd).length())
	e.fog_enabled = true
	e.fog_light_color = look["fog"]
	e.fog_density = 0.085 / diag
	# ⚠️ SET AFTER `_apply_backdrop`, AND THE ORDER IS LOAD-BEARING. This line used to be a bare
	# `0.0` and it was correct then: the background was a flat fill of the fog colour, so fogging it
	# only re-fogged what it already was. With a painted sky behind the venue, 0.0 would leave the
	# painting sitting in a hole in the middle of the depth cue — sharp and near, with a fogged
	# stadium in front of it. The backdrop declares what it needs; a league without one keeps 0.0.
	e.fog_sky_affect = BACKDROP_FOG_AFFECT if e.background_mode == Environment.BG_SKY else 0.0
	e.fog_aerial_perspective = 0.0

	# ⚠️ NO `adjustment_enabled`. It was tried and it is a TRAP in 4.7: switching it on without an
	# `adjustment_color_correction` texture leaves the post-process shader sampling a binding that
	# was never supplied — the log fills with "Uniforms supplied for set (3) are not the same format
	# as required by the pipeline shader" and the whole frame comes back tinted magenta. The grade
	# it would have applied (a little more contrast and saturation) is instead built into the lamp
	# colours and `LEAGUE_LOOK` above, which costs nothing and cannot break the pipeline.
	env.environment = e
	add_child(env)

	var key := DirectionalLight3D.new()
	# ── ⚠️ THE LAMP GEOMETRY IS WHY COVER READ AS "A FLAT PASTED RECTANGLE", AND IT IS MEASURED.
	#
	# The report was that a cover piece shows the player essentially only its TOP FACE, so a
	# 1.18-body wall reads as paint on the floor. `_probe_frame.gd` puts a number on it: RELIEF, the
	# ratio between a piece's camera-facing face and its top face in the rendered frame. Before this
	# change **56 of 76 league/kind groups measured under 0.20 stops** — i.e. the two faces were the
	# same value and the edge between them was invisible. A vertical luminance profile straight
	# through a Wood major confirmed it with no interpretation at all: 0.29 on the top, 0.29 on the
	# front, 0.29 on the floor beyond. One flat field of colour.
	#
	# ⚠️ AND THE CAUSE WAS THE LAMP GEOMETRY, NOT THE MESHES OR THE TEXTURES. Three separate faults
	# stacked, all of them here:
	#
	#   1. THE KEY WAS ALMOST OVERHEAD (52 degrees). A near-overhead lamp gives a horizontal face
	#      sin(52) = 0.79 of its light and a vertical one at best cos(52) = 0.62 — so every TOP in
	#      the scene, including the floor, was the brightest plane in the picture and every wall was
	#      dimmer than the ground it stood on. That is the definition of "no relief".
	#   2. ITS SHADOWS FELL AWAY FROM THE CAMERA AND HID BEHIND THE OBJECTS THAT CAST THEM. At
	#      rotation (-52, -34) the light travels (+0.34, -0.79, -0.51): the -Z component points at
	#      the far wall, which is exactly where the camera cannot see. Every prop in the venue was
	#      casting a correct shadow into its own occluded footprint. A short shadow is a weak
	#      contact cue; an INVISIBLE one is no cue at all, and it is why nothing looked like it was
	#      standing ON anything.
	#   3. THE FILL AND THE RIM BOTH LIT THE FAR HEMISPHERE. Fill sat at yaw 148 and rim at 196 —
	#      both behind the subject — so the whole camera-facing side of every object in the arena
	#      received the KEY AND THE AMBIENT AND NOTHING ELSE, while every top face collected all
	#      four lamps. The two faces the eye compares were being lit by different numbers of lights.
	#
	# The replacement is the standard architectural raking setup, and each number answers one of the
	# three faults above:
	#   KEY  40 degrees elevation, yaw -70 — low enough that a WALL (0.72) out-values the FLOOR
	#        (0.64) and the camera-facing face (0.26) falls clearly below both, which is the
	#        three-value read that makes a box look like a box. Shadows lengthen from 0.78h to
	#        1.19h and now travel to screen RIGHT, in full view.
	#   FILL from the camera's own side (yaw 41, low) — the lamp that was missing entirely. It is
	#        what keeps the camera-facing faces off black now the key has moved off them.
	#   RIM  unchanged at yaw 196: it was the one lamp already doing its job.
	#
	# ⚠️ AND IT WAS A/B'd AGAINST THE PROJECT'S OWN PRIMARY METRIC BEFORE IT SHIPPED, because moving
	# the key is the single most invasive change available in this file and "it looks better" is not
	# evidence. `_probe_venue.gd`'s VALUE pass (body luminance against floor luminance, the number
	# three previous rounds were tuned to) was run over all eleven leagues under the OLD rotations
	# and the NEW ones, same seed, same fights:
	#
	#   Wood 1.68->1.91 · Copper 2.17->2.44 · Tin 1.69->1.77 · Bronze 1.40->1.57 · Iron 1.92->2.06
	#   Silver 0.86->0.97 · Gold 0.96->1.03 · Platinum 1.25->1.36 · Masters 1.47->1.65
	#   Tamer Elite 0.92->1.05 · Tamers Apex 0.82->0.93
	#
	# **Eleven leagues out of eleven improved**, which is what a raking key predicts: the floor is a
	# horizontal plane and loses the most when the lamp comes down, while a creature is nearly
	# vertical and loses the least.
	#
	# ⚠️ FOUR LEAGUES STILL FAIL THAT CHECK (Silver, Gold, Tamer Elite, Tamers Apex) AND THEY FAILED
	# IT BEFORE THIS CHANGE TOO — 0.86 / 0.96 / 0.92 / 0.82 under the old lamps. Do not attribute
	# them here. The `LEAGUE_LOOK` Platinum note already names the real diagnosis and it is borne out
	# by the probe's own body column: those leagues' CASTS are dark (0.157-0.244 against Wood's
	# 0.482), not their grounds bright, and the lever is `fill`/the cast light, not another
	# tone-down.
	#
	# ⚠️ DO NOT RAISE THE KEY BACK TOWARD OVERHEAD TO BRIGHTEN THE FRAME. The floor is a horizontal
	# plane covering a third of the picture, so elevation is very nearly a floor-brightness control
	# — and the floor being the brightest plane in the venue is the exact fault three rounds of
	# `LEAGUE_LOOK.ground` tone-downs were compensating for. Reach for `ground` or the cast light.
	key.rotation_degrees = Vector3(-40, -70, 0)
	key.light_color = look["key"]
	key.light_energy = float(look["key_e"])
	# ⚠️ SPECULAR IS KEPT LOW ON EVERY DIRECTIONAL LIGHT IN THIS SCENE, AND THE FLOOR IS WHY. The
	# ground is a single unbroken plane tens of units across, so a directional specular lobe on it
	# is not a highlight — it is a soft-edged wash covering a third of the frame, and it was
	# measurably the BRIGHTEST thing in the picture. (Caught with `rim.light_specular = 0.6`: a
	# large blue sheen across the left of the board that out-valued every creature on it.)
	key.light_specular = 0.12
	key.shadow_enabled = true
	# ⚠️ THE SHADOW RANGE IS SIZED TO THE BOARD, NOT LEFT AT THE DEFAULT 100 — a 5v5 ground is ~150
	# world units across, so the default ended before the far half of the arena and cover there cast
	# nothing.
	# ⚠️ AND BIAS MUST SCALE WITH THE SHADOW RANGE, AND THIS IS MEASURED, NOT THEORETICAL. With
	# a fixed `shadow_bias = 0.04` over a range sized to the board, the 5v5 grounds acne'd across
	# their whole surface — every texel partially self-shadowing — and the symptom was not speckle
	# but a uniformly DARK, formless board: floor luminance 0.188 with shadows on against 0.267
	# with them off, at Platinum, from the same lamps. (Bronze, on a board less than half as long,
	# was unaffected — which is exactly why this looked like a per-league art problem and was not.)
	# Shadow-map texel size grows with range, so the depth offset that hides acne has to grow with
	# it too.
	# ⚠️ AND THE RANGE IS MEASURED FROM THE CAMERA, NOT ACROSS THE BOARD — WHICH IS WHY MOST OF THE
	# ARENA HAD NO SHADOWS AT ALL. `directional_shadow_max_distance` is a distance from the CAMERA's
	# own position, and this camera is a 26-degree long lens: `_apply_camera_now` solves
	# `r = span / tan(fov/2)`, i.e. `tan(13°) = 0.231`, so it sits **four and a half times the span
	# away from what it is looking at**. On Wood that is ~76 units back for a board 29 units across.
	# Sizing the range to the board's own diagonal therefore ended the shadow map BEFORE THE BOARD
	# EVEN STARTED at every league (Wood clamped to 80 against a nearest-corner distance of ~65 and a
	# far corner past 100), and the symptom is exactly the round's complaint: props with no contact
	# shadow, sitting on the floor like stickers. It was invisible in review because the number
	# looked principled — it was scaled to the board, it just was not scaled to the thing the engine
	# measures from.
	#
	# ⚠️ AND NO PROBE CAUGHT IT EITHER, because every instrument so far sampled the props and the
	# floor and compared them with each other. A missing shadow is not a property of any surface —
	# it is the ABSENCE of a dark shape on a third one. It took looking at a key-light-only frame
	# and asking why nothing threw anything.
	#
	# The honest range is "how far can the far edge of the board be from the camera": the maximum
	# camera pullback plus the board's own half-diagonal, with a margin.
	var diag_w: float = Vector2(bw, bd).length()
	var cam_back: float = (diag_w * 0.5 * 1.05) / tan(deg_to_rad(CAM_FOV * 0.5))
	var shadow_range: float = clampf((cam_back + diag_w) * 1.15, 80.0, 600.0)
	key.directional_shadow_max_distance = shadow_range
	# ⚠️ ONE ORTHOGONAL SPLIT, NOT FOUR PARALLEL ONES — and this is a consequence of the camera,
	# not a preference. Cascaded splits give the near cascade most of the resolution, which is
	# correct for a first-person camera where the subject is at your feet and the horizon is far.
	# This camera is a long lens ~200 units back looking down at a board: EVERYTHING in shot sits
	# in a narrow distance band, and with 4 splits that band fell almost entirely into the coarsest
	# cascade. One orthogonal split spends the whole map on the same band, so texel size is uniform
	# and the bias that hides acne is a single knowable number.
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	# Bias tracks texel size, which tracks the range. ~2 texels of depth offset at 4096.
	key.shadow_bias = maxf(0.06, shadow_range / 4096.0 * 2.6)
	key.shadow_normal_bias = 1.0
	key.shadow_blur = 1.1
	# ⚠️ SHADOWS WERE READING AS HOLES IN THE FLOOR, NOT AS SHADE — and this is a NEW fault, created
	# by the fix that gave the arena shadows at all. The shadow fill in this scene is the ambient
	# term alone (`amb` at `amb_e` ~0.30, a dark blue), so a raking key at energy 2.0 put the lit
	# floor 1.3-1.7 STOPS above the shadowed floor. That is 2.5-3.2x, and against a warm board it
	# does not read as a cast shadow — it reads as a black rectangle cut out of the ground, which
	# is exactly how the majors' long new shadows looked in the hero frames.
	#
	# ⚠️ AND THIS IS THE RIGHT KNOB RATHER THAN RAISING THE AMBIENT, WHICH WAS THE OBVIOUS MOVE.
	# Ambient lifts every unlit surface in the venue INCLUDING THE FLOOR'S LIT SIDE, so it moves
	# `floor` in the value ladder and re-opens three rounds of `LEAGUE_LOOK.ground` tuning.
	# `shadow_opacity` touches only pixels the shadow map darkens: the lit frame is bit-identical,
	# the value ladder cannot move, and only the contact-shadow column in `_probe_frame.gd`
	# responds. One lever, one column.
	#
	# 0.78 is set from the measurement, not from taste: majors measured 1.31-1.71 stops of contact
	# shadow and the probe's bar for "this object is standing on something" is 0.22. Multiplying the
	# shadow's darkening by 0.78 lands them at ~0.75-0.95 — still three to four times the bar, so
	# nothing that passed stops passing, and the shape reads as shade instead of as a pit.
	key.shadow_opacity = 0.78
	add_child(key)

	var fill := DirectionalLight3D.new()
	# ⚠️ FROM THE CAMERA'S SIDE, WHICH IS THE WHOLE POINT AND WHERE IT WAS NOT. See fault 3 in the
	# key's header: at yaw 148 this lamp lit the far hemisphere alongside the rim, so no light in
	# the venue except the key ever touched a surface the player was looking at. Yaw 41 puts it
	# opposite the key horizontally AND on the near side, so it lifts both the +X faces the key
	# leaves black and the +Z faces the camera actually sees. Energy up a little because it is now
	# doing real work rather than adding a second highlight to the tops.
	fill.rotation_degrees = Vector3(-24, 41, 0)
	fill.light_color = look["fill"]
	fill.light_energy = 0.50
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	add_child(fill)

	var rim := DirectionalLight3D.new()
	# From behind the far wall and low, so it catches the tops and back edges of bodies and props —
	# the edge that makes a silhouette readable against a floor of the same value.
	rim.rotation_degrees = Vector3(-14, 196, 0)
	rim.light_color = look["fill"]
	rim.light_energy = 0.75
	rim.light_specular = 0.0
	rim.shadow_enabled = false
	add_child(rim)

	# ── THE CAST LIGHT. The one lamp that only the creatures can see. ───────────────────────────
	#
	# ⚠️ THIS IS THE LEVER THAT ACTUALLY SATISFIES "THE CREATURES MUST BE THE BRIGHTEST THINGS ON
	# SCREEN", and nothing else does. Tuning the venue's own lamps moves the floor and the cast
	# TOGETHER — their ratio is set by their albedos, so a brighter key brightens the marble by
	# exactly as much as it brightens the monster standing on it. A light with a cull mask breaks
	# that coupling: it is +energy on the cast alone, at zero cost to the ground, and it is the only
	# control in the scene that moves body value WITHOUT moving floor value.
	#
	# ⚠️ AND IT IS NOT A CHEAT — it is how the genre lights a board. The alternative is to keep
	# darkening every floor until the contrast appears, which destroys the per-league material
	# identity the ground art exists to carry (`ART_DIRECTION.md`'s material axis). This keeps the
	# floors readable AS FLOORS and puts the value where the design needs it.
	#
	# `CAST_LIGHT_LAYER` is the visual layer `_build_units` adds to every unit's geometry; this
	# light's cull mask is that layer and nothing else.
	var cast := DirectionalLight3D.new()
	cast.rotation_degrees = Vector3(-42, 22, 0)
	cast.light_color = Color(1.0, 0.95, 0.88)
	cast.light_energy = 1.5
	cast.light_specular = 0.25
	cast.shadow_enabled = false
	cast.light_cull_mask = CAST_LIGHT_LAYER
	add_child(cast)

	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(bw, bd)
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new()
	var gtex: Texture2D = Art.ground_for(league_name, _league_names())
	if gtex != null:
		fm.albedo_texture = gtex
		fm.uv1_scale = Vector3(bw / 6.0, bd / 6.0, 1.0)
		# ⚠️ THE TONE-DOWN. `albedo_color` MULTIPLIES `albedo_texture`, so this darkens the league's
		# own floor art without replacing it — the material identity survives, the blinding does not.
		fm.albedo_color = look["ground"]
	else:
		# A missing ground still degrades to a decent tinted floor rather than a grey plane, and it
		# takes the same per-league tone so an unpainted league is quiet rather than bright.
		var g: Color = look["ground"]
		fm.albedo_color = Color(0.55 * g.r, 0.50 * g.g, 0.43 * g.b)
	fm.roughness = 0.96
	fm.metallic = 0.0
	fm.metallic_specular = 0.08
	floor_mesh.material_override = fm
	# ⚠️ THE GROUND MUST NOT CAST. This one line is worth more than every lamp value above it.
	# `MeshInstance3D` casts shadows by default, so the floor plane was casting a shadow onto
	# ITSELF — coincident geometry at y=0, which a shadow map resolves by texel size, so the larger
	# the board the larger the shadow range, the coarser the texel and the more of the floor that
	# fell inside its own shadow. That is why the 5v5 grounds rendered as a flat dark slate while
	# Bronze, on a board less than half as long, looked correct off IDENTICAL lighting code — and
	# why it read as a per-league art fault for three rounds of tuning. Nothing below the fight
	# needs to cast: see the same setting on the zone paint and the centre line.
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Named so `_probe_venue.gd` can toggle one layer of the venue at a time and measure its exact
	# screen coverage by difference — a classification-free way to ask "how much of this frame is
	# venue and how much is empty floor".
	floor_mesh.name = "Ground"
	add_child(floor_mesh)

	_build_venue(bw, bd)
	_build_deploy_zones(bw, bd)
	if SHOW_OBSTACLES:
		_build_obstacles()
	_build_banners(bw, bd)
	_build_vignette()

	camera = Camera3D.new()
	camera.fov = CAM_FOV
	add_child(camera)
	# ⚠️ NOT `Sp.leash_radius(...)`. That function was renamed to `engagement_radius` and
	# re-scoped to a LAYOUT helper for cover placement only — `spatial.gd`'s own header says it
	# "must never gate movement again", and using it here would re-couple the camera to the exact
	# concept that was just removed. The camera's initial and ongoing framing comes only from the
	# board's own size and, every frame after, from where the living units actually are
	# (`_camera_target()`) — never from a formula about where a fight is "supposed" to cluster.
	_cam_max_span = Vector2(bw, bd).length() * 0.5 * 1.05
	_cam_center = Vector3.ZERO
	_cam_span = _cam_max_span
	_apply_camera_now()


## One MultiMeshInstance3D for the 4 wall boxes and one for the 20 stand-tier boxes — instead of
## 24 individual `MeshInstance3D` nodes each with their own `material_override`.
## `docs/PERFORMANCE_BUDGETS.md` §5 names this exact pattern as "the single biggest current cost":
## same mesh, same material, only the transform differs per instance — a textbook MultiMesh case.
## THE DEPLOYMENT ZONES, drawn flat on the ground — the band each side actually spawns into, from
## `Spatial.deploy_positions`/`deploy_depth` rather than a shape invented here. With the obstacles
## off, these are the only landmarks on the field, and without landmarks "did they use the space?"
## is unanswerable: every position looks like every other position.
##
## ⚠️ TEAM COLOUR, NOT NEW COLOUR. `ART_BIBLE_GUILD_COLOURS.md` allows exactly three colour
## systems and forbids a fourth, so these take `Art.team_identity()`'s own hues at low alpha —
## they read as "this is A's ground" without competing with the status channel, which the bible
## reserves as the brightest thing in frame.
func _build_deploy_zones(bw: float, bd: float) -> void:
	var team_size: int = maxi(team_a.size(), team_b.size())
	var depth: float = Sp.deploy_depth(team_size) * WORLD_SCALE
	var sep: float = Sp.deploy_separation(team_size) * WORLD_SCALE
	for side in range(2):
		var dir := -1.0 if side == 0 else 1.0
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		# ⚠️ Sized from the SIM's own deploy band, not from a fraction of the board. The zone is
		# only useful as a landmark if it is where units actually spawn — a decorative rectangle
		# near the right area would make "did they hold their zone?" unanswerable.
		# ⚠️ THE WHOLE LEGAL ZONE, EDGE TO SEPARATION LINE (user call 2026-08-06). The thin strip
		# only marked the default spawn band; the deployment board lets a chip stand anywhere in
		# `Spatial.deploy_zone`, so the paint must cover exactly what the sim permits.
		var zone: Rect2 = Sp.deploy_zone(team_size, "A" if side == 0 else "B")
		pm.size = Vector2(zone.size.x * WORLD_SCALE, bd)
		mi.mesh = pm
		var m := StandardMaterial3D.new()
		var col: Color = Art.team_identity(side)["colour"]
		# ⚠️ 0.42 -> 0.14, PLUS A PAINTED EDGE. A flood fill at 0.42 covered roughly half the board
		# in flat unshaded colour, which did two bad things at once: it erased the ground's own
		# material identity across most of the frame, and — being unshaded — it was immune to the
		# lighting, so it flattened the value structure the new lamps exist to create. A sports
		# ground marks a zone with a LINE and a wash, not a coat of paint; the line is the landmark,
		# the wash only says which side of it you are on.
		m.albedo_color = Color(col.r, col.g, col.b, 0.14)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
		# Lifted a hair off the floor so it does not z-fight with the ground texture.
		var zone2: Rect2 = Sp.deploy_zone(team_size, "A" if side == 0 else "B")
		var cx_w: float = (zone2.position.x + zone2.size.x * 0.5 - Sp.ground_size(team_size).x * 0.5) * WORLD_SCALE
		mi.position = Vector3(cx_w, 0.02, 0.0)
		# Paint on the floor, 2cm above it. It must not cast a shadow — an unshaded transparent
		# plane still casts an OPAQUE one, and this covers a third of the board.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)

		# The zone's inner boundary — the line a monster is not deployed past. Drawn brighter than
		# the wash so it survives at a distance, and offset by half its own width so it sits ON the
		# edge rather than straddling it.
		var edge := MeshInstance3D.new()
		var em := PlaneMesh.new()
		em.size = Vector2(0.5, bd)
		edge.mesh = em
		var emat := StandardMaterial3D.new()
		emat.albedo_color = Color(col.r, col.g, col.b, 0.85).lightened(0.25)
		emat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		emat.cull_mode = BaseMaterial3D.CULL_DISABLED
		edge.material_override = emat
		var inner_x: float = zone2.position.x + (zone2.size.x if side == 0 else 0.0)
		edge.position = Vector3(
			(inner_x - Sp.ground_size(team_size).x * 0.5) * WORLD_SCALE - dir * 0.25, 0.04, 0.0)
		edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(edge)

	# The centre line — the thing both sides are walking toward, and the only way to see at a
	# glance which side has taken ground.
	var line := MeshInstance3D.new()
	var lm := PlaneMesh.new()
	lm.size = Vector2(0.6, bd * 0.88)
	line.mesh = lm
	var lmat := StandardMaterial3D.new()
	# ⚠️ 0.22 -> 0.13 AND OFF PURE WHITE. Unshaded white at 0.22 over a floor that is now properly
	# dark rendered as a solid bright bar running the depth of the board — a piece of line marking
	# out-valuing the competitors. It is a landmark, not a light source.
	# ⚠️ 0.10 -> 0.040 ON 2026-08-08, AND THIS TIME IT WAS MEASURED OFF THE FRAME RATHER THAN
	# REASONED ABOUT. The note above cut 0.22 -> 0.13 -> 0.10 on the correct diagnosis and stopped
	# short: sampling the shipped Platinum hero frame across three rows, the stripe rendered at
	# 0.413 / 0.436 / 0.417 luma against a floor of 0.219 — 1.9x the ground, and ABOVE the creatures
	# themselves (0.351-0.363 in the same frame). A piece of line marking was still the brightest
	# object on the board. ⚠️ AND THE AUTHORED NUMBER DOES NOT PREDICT THE RENDERED ONE: alpha 0.10
	# over a 0.22 floor should blend to ~0.26 and it blends to ~0.42, roughly 3x the expected lift,
	# because this is an UNSHADED plane going through the same FILMIC tonemap as everything else.
	# So do not re-derive this value arithmetically — sample the frame. Target is a landmark that
	# sits between the floor and the cast, not above both.
	lmat.albedo_color = Color(0.86, 0.88, 0.92, 0.040)
	lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	line.material_override = lmat
	line.position = Vector3(0, 0.03, 0)
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line)


## ═══════════════════════════════════════════════════════════════════════════════════════════════
## THE BACKDROP — the eleven painted venues the 3D arena had never once drawn
## ═══════════════════════════════════════════════════════════════════════════════════════════════
##
## ⚠️ THE REPORT WAS "~45% OF THE HERO FRAME IS BLACK VOID", and measured honestly it is close
## enough to true to act on. Counting only pixels at or under 0.045 luma the figure is 9-15%, so
## the frame is not literally black — but taking the rows whose mean luminance is under 0.12 (the
## band that carries nothing a player can read) it is **28-44% of frame height**, split ~16-24%
## above the venue and ~12-20% below it, and 38-45% of all pixels sit under 0.09 luma. The integrator
## was describing what the eye does, and the eye is right.
##
## ⚠️ AND THE CAUSE IS ARITHMETIC, NOT ART DIRECTION. `_camera_target()`'s ARENA framing solves for
## whichever of the board's width and depth needs the wider shot. A 5v5 ground is 54 x 30 world
## units and the camera's 38-degree pitch foreshortens the depth by sin(38) = 0.62, so the board
## covers about 18 units of vertical extent inside a frame sized to fit 54 units of WIDTH on a 16:9
## screen — which needs 35 units of vertical. Slightly over half the frame is board; the rest is
## whatever is behind and beyond it, and until now that was `BG_COLOR`, a flat fill of `look.fog`.
##
## ⚠️ THE ART ALREADY EXISTED AND NOTHING WAS DRAWING IT. `assets/arenas/` holds eleven painted
## 1400x788 venue backdrops, one per league, and `Art.backdrop_for()` has always returned them —
## `grep backdrop scripts/` finds exactly one consumer, `arena_view.gd`, the RETIRED 2D arena. The
## 3D venue was built without ever being wired to them.
##
## As a panorama sky rather than a quad, for three reasons:
##   - it fills the void ABOVE and BELOW the venue in one change, where a backdrop wall behind the
##     stands only ever fixes the top;
##   - it needs no radius, no height and no per-board sizing, so it cannot fall out of step with a
##     ground that has already changed size twice this project;
##   - it is behind everything by construction, so it can never occlude the fight — the failure
##     mode a near-side backdrop wall has and the one that would be least forgivable here.
##
## ⚠️ IT MUST NOT LIGHT ANYTHING AND IT MUST NOT COMPETE. `ambient_light_source` stays
## `AMBIENT_SOURCE_COLOR`, so adding a sky changes zero lamps and cannot move a single value the
## previous rounds measured. `BACKDROP_ENERGY` holds it well under the board, and `fog_sky_affect`
## — deliberately 0.0 while the background was a flat colour that already WAS the fog colour — now
## pulls the painting toward the league's own distance colour so it sits behind the venue rather
## than behind a window. If it ever reads as a poster, that pair is the control, in that order.
##
## ⚠️ AN EQUIRECTANGULAR MAPPING OF A 16:9 PAINTING IS A STRETCH AND THAT IS ACCEPTED. It is soft,
## far away, fogged and never in focus; the alternative is authoring eleven true panoramas, which is
## an art request and not a renderer change. If those are ever painted, only the asset changes.
const BACKDROP_ENERGY := 0.30
const BACKDROP_FOG_AFFECT := 0.62


func _apply_backdrop(e: Environment, look: Dictionary) -> void:
	var tex: Texture2D = Art.backdrop_for(league_name, _league_names())
	if tex == null:
		# ⚠️ A LEAGUE WITH NO BACKDROP KEEPS THE FLAT FILL, WHICH IS THE HONEST DEGRADE. An
		# unpainted venue should read as unfinished, never as another league's stadium.
		return
	var sm := PanoramaSkyMaterial.new()
	sm.panorama = tex
	sm.energy_multiplier = BACKDROP_ENERGY
	var sky := Sky.new()
	sky.sky_material = sm
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.fog_sky_affect = BACKDROP_FOG_AFFECT


func _build_venue(bw: float, bd: float) -> void:
	var wall_mat := StandardMaterial3D.new()
	var wtex: Texture2D = Art.load_or_null("res://assets/arena/wall-timber.jpg")
	if wtex != null:
		wall_mat.albedo_texture = wtex
		wall_mat.uv1_scale = Vector3(bw / 5.0, 1.0, 1.0)
	else:
		wall_mat.albedo_color = Color(0.30, 0.24, 0.19)
	wall_mat.roughness = 0.9
	wall_mat.metallic = 0.0
	# ⚠️ THE VENUE MUST SIT UNDER THE FLOOR, WHICH SITS UNDER THE CREATURES. One shared timber
	# texture dressed every league's barrier at full brightness, so the ring of wall around the
	# board was often the lightest large shape in frame. Taking the same per-league tone-down the
	# ground takes (a touch darker still) keeps the value ladder in the right order.
	var lk := _look()
	var gt: Color = lk["ground"]
	# The barrier as it would be drawn at a multiplier of 1.0 — its own texture average (or its
	# fallback colour) times the league tone. Solved against the FLOOR, never against a constant:
	# see the WALL_FLOOR_RATIO header for the flat-multiplier attempt that broke the ladder.
	var wall_base: Color = Color(gt.r, gt.g, gt.b)
	if wtex == null:
		wall_base = Color(wall_mat.albedo_color.r * gt.r, wall_mat.albedo_color.g * gt.g,
			wall_mat.albedo_color.b * gt.b)
	else:
		var wavg: Color = _tex_average("res://assets/arena/wall-timber.jpg")
		if wavg.a >= 0.5:
			wall_base = Color(wavg.r * gt.r, wavg.g * gt.g, wavg.b * gt.b)
	var wall_k: float = _shell_tone(wall_base, WALL_FLOOR_RATIO)
	wall_mat.albedo_color = Color(
		wall_mat.albedo_color.r * gt.r * wall_k,
		wall_mat.albedo_color.g * gt.g * wall_k,
		wall_mat.albedo_color.b * gt.b * wall_k) if wtex == null \
		else Color(gt.r * wall_k, gt.g * wall_k, gt.b * wall_k)

	var wall_xforms: Array = [
		_box_xform(Vector3(0, WALL_H * 0.5, -bd * 0.5 - 0.4), Vector3(bw + 1.6, WALL_H, 0.8)),
		_box_xform(Vector3(0, WALL_H * 0.5, bd * 0.5 + 0.4), Vector3(bw + 1.6, WALL_H, 0.8)),
		_box_xform(Vector3(-bw * 0.5 - 0.4, WALL_H * 0.5, 0), Vector3(0.8, WALL_H, bd + 1.6)),
		_box_xform(Vector3(bw * 0.5 + 0.4, WALL_H * 0.5, 0), Vector3(0.8, WALL_H, bd + 1.6)),
	]
	var wall_node := _multimesh_boxes(wall_xforms, wall_mat)
	wall_node.name = "VenueWalls"
	add_child(wall_node)

	var stand_mat := StandardMaterial3D.new()
	var ctex: Texture2D = Art.load_or_null("res://assets/arena/stands-crowd.jpg")
	if ctex != null:
		stand_mat.albedo_texture = ctex
		stand_mat.uv1_scale = Vector3(bw / 8.0, 1.0, 1.0)
	else:
		stand_mat.albedo_color = Color(0.24, 0.21, 0.18)
	stand_mat.roughness = 0.95
	stand_mat.metallic = 0.0
	# Darker again than the barrier: the stands are the outermost ring and the furthest thing from
	# the fight, so they are where "everything past the wall falling into dark" (ART_DIRECTION.md)
	# actually happens.
	if ctex != null:
		var cavg: Color = _tex_average("res://assets/arena/stands-crowd.jpg")
		var stand_base: Color = Color(gt.r, gt.g, gt.b)
		if cavg.a >= 0.5:
			stand_base = Color(cavg.r * gt.r, cavg.g * gt.g, cavg.b * gt.b)
		# Below the barrier by construction (STAND_FLOOR_RATIO < WALL_FLOOR_RATIO), so the outer
		# ring stays the darkest band in the ladder without a second constant to keep in step.
		var stand_k: float = _shell_tone(stand_base, STAND_FLOOR_RATIO)
		# The +6% on blue is unchanged: the crowd sits in the venue's own cool shadow, and it is a
		# hue nudge at constant value, not a lift.
		stand_mat.albedo_color = Color(gt.r * stand_k, gt.g * stand_k, gt.b * stand_k * 1.06)

	# ⚠️ TIER COUNT SCALES WITH THE BOARD, THE FIRST FIVE STEPS DO NOT — see `STAND_TIERS_MAX`.
	# Rows 0-4 keep the exact rise/depth `spectators.gd` seats its crowd against; rows 5+ are the
	# upper bank and step at the venue's own scale, so a 5v5 ground gets a stand roughly 3 creature
	# heights tall instead of 1.2 and the spectacle is actually in frame.
	var vs := _venue_scale(bw, bd)
	var tiers: int = clampi(int(round(float(STAND_TIERS) * vs)), STAND_TIERS, STAND_TIERS_MAX)
	var stand_xforms: Array = []
	var h := WALL_H
	var out := 1.1 - STAND_STEP_OUT
	for tier in range(tiers):
		# Below the crowd line the step is fixed; above it, it grows with the venue.
		var step: float = 1.0 if tier < STAND_TIERS else vs
		h += STAND_STEP_H * step
		out += STAND_STEP_OUT * step
		var depth: float = STAND_STEP_OUT * step
		stand_xforms.append(_box_xform(Vector3(0, h * 0.5, -bd * 0.5 - out), Vector3(bw + 2.0 + out * 2.0, h, depth)))
		stand_xforms.append(_box_xform(Vector3(0, h * 0.5, bd * 0.5 + out), Vector3(bw + 2.0 + out * 2.0, h, depth)))
		stand_xforms.append(_box_xform(Vector3(-bw * 0.5 - out, h * 0.5, 0), Vector3(depth, h, bd + 2.0 + out * 2.0)))
		stand_xforms.append(_box_xform(Vector3(bw * 0.5 + out, h * 0.5, 0), Vector3(depth, h, bd + 2.0 + out * 2.0)))
	var stand_node := _multimesh_boxes(stand_xforms, stand_mat)
	stand_node.name = "VenueStands"
	add_child(stand_node)


## How much bigger this board is than the smallest one in the game. 1.0 at 1v1, 2.0 at 5v5.
## ⚠️ DERIVED FROM `Spatial.ground_size(1)`, NEVER A LITERAL — the board base has already moved
## twice this project (40x22 -> 50x28, then x2.2 for `GEOMETRY_SCALE`) and a hard-coded reference
## diagonal would have silently stopped meaning "the smallest board" on the first of those.
func _venue_scale(bw: float, bd: float) -> float:
	var ref: float = maxf(1.0, (Sp.ground_size(1) * WORLD_SCALE).length())
	return clampf(Vector2(bw, bd).length() / ref, 1.0, 3.0)


## A handful of guild banners on the near wall — real dressing, not a grey box venue. Skipped
## entirely (not a placeholder colour) when the art hasn't generated yet; a missing banner is not
## worth a fallback rectangle the way a missing wall/ground texture is.
func _build_banners(bw: float, bd: float) -> void:
	var tex: Texture2D = Art.load_or_null("res://assets/arena/banner-guild.png")
	if tex == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# ⚠️ NOT `SHADING_MODE_UNSHADED`. An unshaded banner ignores the venue's lamps entirely, so it
	# rendered at full texture brightness against a dim wall — three bright rectangles that read as
	# stickers rather than cloth, and (being brighter than the creatures) they competed for the eye
	# with the one thing that must always win it. Lit, they sit in the venue.
	mat.roughness = 0.95
	mat.metallic = 0.0
	# ⚠️ SIZED OFF THE BOARD, NOT FIXED AT 1.6 UNITS. The near wall is ~150 world units long on a
	# 5v5 ground, so a 1.6-unit banner was roughly one percent of it — invisible, which is why the
	# venue read as undressed despite the art existing. Count scales too, so the spacing between
	# them stays even at every team size instead of three lonely marks on a huge wall.
	# ⚠️ THE ART IS A TALL BANNER (750x1221), SO IT CANNOT LIVE ON THE BARRIER. `WALL_H` is 1.4 —
	# a banner drawn to that height is 0.86 wide on a wall ~150 long, which is the invisible thing
	# that was already happening. They are hung from the barrier's top rail instead and rise in
	# FRONT of the lower stand rows, which is both where a real ground hangs them and the only
	# place they can be a monster-height object. Height is pinned to `UNIT_HEIGHT * 0.78` so a
	# banner always reads as "about as tall as a competitor" at every board size.
	var h := UNIT_HEIGHT * 0.78
	var w := h * 0.614          # the source art's own aspect; a squashed banner reads as a poster
	var span := bw * 0.90
	var count: int = clampi(int(round(span / (w * 6.0))), 3, 13)
	for i in range(count):
		var t: float = (float(i) + 0.5) / float(count)
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(w, h)
		q.mesh = qm
		# The far barrier's INNER face is at `-bd*0.5` (the box spans back from there), so a banner
		# in shot sits a hair on the camera side of it. The old value put them behind the wall.
		q.position = Vector3(-span * 0.5 + span * t, WALL_H + h * 0.5 - 0.15, -bd * 0.5 + 0.06)
		q.material_override = mat
		add_child(q)


## A soft corner darkening over the whole frame. ⚠️ NOT DECORATION — it is the cheapest available
## answer to the readability requirement in `ART_THEME.md` §3 ("who's who, what's happening, who's
## winning, at a glance"): the fight is always near the middle of frame and the stands, the far
## crowd and the empty corners are always at the edges, so pulling the edges down puts the eye on
## the board without moving the camera or hiding anything.
##
## ⚠️ ITS OWN `CanvasLayer` AT LAYER 0, BENEATH THE HUD (`overlay` is layer 1). A vignette drawn
## over the nameplates would dim the one channel that carries whose creature is whose — which is
## the exact failure the vignette is supposed to help with. And `MOUSE_FILTER_IGNORE`, because a
## full-screen Control that eats clicks would silently kill the arena's own drag-to-pan.
func _build_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([
		Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.10), Color(0.02, 0.02, 0.04, 0.62)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 512
	tex.height = 512
	var rect := TextureRect.new()
	rect.texture = tex
	rect.anchor_right = 1
	rect.anchor_bottom = 1
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)


func _box_xform(pos: Vector3, box_size: Vector3) -> Transform3D:
	return Transform3D(Basis().scaled(box_size), pos)


## Fallback primitives get RIM LIGHTING (AD: "a perfect 90° edge catches no highlight... reads
## as a diagram of a box"). Rim is the cheap stand-in for bevels until every kind has a GLB —
## the edge catches light, so an undressed obstacle no longer reads cruder than its neighbour.
func _rim(mat: Material) -> Material:
	if mat is StandardMaterial3D:
		var m2 := (mat as StandardMaterial3D).duplicate()
		m2.rim_enabled = true
		m2.rim = 0.55
		m2.rim_tint = 0.6
		return m2
	return mat


func _multimesh_boxes(xforms: Array, mat: Material) -> MultiMeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bm
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	return mmi


func _multimesh_cylinders(xforms: Array, mat: Material) -> MultiMeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.5
	cm.height = 1.0
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cm
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	return mmi


## Obstacles grouped by `kind` — one MultiMeshInstance3D per kind present, instead of one node per
## piece. Count scales with ground AREA (`arena_layout.gd`), so this is where draw calls would
## otherwise grow with team size; grouped instancing keeps it flat at "number of kinds", not
## "number of pieces".
func _build_obstacles() -> void:
	var box_groups: Dictionary = {}     # kind -> Array[Transform3D]
	var cyl_groups: Dictionary = {}     # kind -> Array[Transform3D]  (the round kinds below)
	var coping: Array = []              # the crown course — see `_cover_architecture`
	var piers: Array = []               # the vertical members that break the skyline
	for o in _obstacles:
		var kind: String = str(o.get("kind", "crate"))
		var r: Rect2 = o["rect"]
		var grade: String = str(o.get("grade", "soft"))
		var centre := _to_world(r.position + r.size * 0.5)
		var w := maxf(r.size.x * WORLD_SCALE, 0.6)
		var d := maxf(r.size.y * WORLD_SCALE, 0.6)
		# Height carries the cover GRADE, so what a player sees matches what the sim applies —
		# and it is now measured in CREATURE HEIGHTS rather than in bare numbers. See
		# `PROP_HEIGHT_BODIES` for why the three constants that used to live here were the whole
		# "brick loaf" defect.
		var h := prop_height(grade)
		var xf := Transform3D(Basis().scaled(Vector3(w, h, d)), centre + Vector3(0, h * 0.5, 0))
		_cover_architecture(kind, grade, centre, w, d, h, coping, piers)
		if kind in ROUND_KINDS:
			if not cyl_groups.has(kind):
				cyl_groups[kind] = []
			cyl_groups[kind].append(xf)
		else:
			if not box_groups.has(kind):
				box_groups[kind] = []
			box_groups[kind].append(xf)

	# ⚠️ REAL MESHES FIRST, PRIMITIVES AS THE FALLBACK. A kind with no model on disk still renders
	# as a tinted box or cylinder exactly as before, so a missing file is a plainer arena rather
	# than an empty one.
	for kind in box_groups.keys():
		if not _try_prop_multimesh(kind, box_groups[kind]):
			var n := _multimesh_boxes(box_groups[kind], _rim(_obstacle_material(kind)))
			n.name = "Prop_%s_box" % kind
			add_child(n)
	for kind in cyl_groups.keys():
		if not _try_prop_multimesh(kind, cyl_groups[kind]):
			var n2 := _multimesh_cylinders(cyl_groups[kind], _rim(_obstacle_material(kind)))
			n2.name = "Prop_%s_cyl" % kind
			add_child(n2)

	# ⚠️ TWO BATCHES FOR THE WHOLE BOARD, NOT TWO PER PIECE. Both are `Prop_`-prefixed so
	# `_probe_venue.gd`'s layer diff counts them as cover rather than as a new unmeasured layer —
	# an addition the instruments cannot see is an addition nobody can defend.
	if not coping.is_empty():
		var cn := _multimesh_boxes(coping, _masonry_material(COPING_TINT))
		cn.name = "Prop_coping"
		cn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(cn)
	if not piers.is_empty():
		var pn := _multimesh_boxes(piers, _masonry_material(PIER_TINT))
		pn.name = "Prop_pier"
		pn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(pn)


## ═══════════════════════════════════════════════════════════════════════════════════════════════
## COVER AS ARCHITECTURE — a crown course and vertical members, on top of the kind's own model
## ═══════════════════════════════════════════════════════════════════════════════════════════════
##
## ⚠️ THE COMPLAINT WAS "THE MAJORS READ AS FLAT PASTED RECTANGLES", AND THE HONEST FINDING IS THAT
## HALF OF IT WAS A LIGHTING FAULT AND HALF OF IT IS A GEOMETRY ONE. The lighting half is fixed
## above (shadows were being clipped before they reached the board — see the key's shadow-range
## note) and it is the larger half by far: with contact shadows landing, `_probe_frame.gd` scores
## every kind on the Wood board between 0.48 and 1.71 stops of shadow separation where it previously
## had none at all.
##
## ⚠️ BUT THE FACE-AGAINST-FACE NUMBER DID NOT MOVE, AND THAT PART IS REAL. Measured on a
## key-light-only frame — no ambient, no fill, no rim, so nothing could be blamed on a wash — a
## Wood major renders 0.276 on its top face and 0.257 on the face pointed at the camera: **0.10
## stops, where the lamp geometry alone predicts 1.3**. Whatever the renderer is doing between the
## N·L term and the pixel (FILMIC, the fog term, the material's own rim) collapses face-to-face
## contrast to almost nothing at this scale. That is worth knowing and it is not worth fighting: a
## value step you cannot get from a lamp you can simply BUILD.
##
## So the piece gets the two members that make masonry read as masonry from any angle and under any
## light, because they are geometry and not shading:
##
##   COPING — a crown course capping the piece, a hair proud of it. It puts a hard horizontal edge
##            exactly where the top face meets the front face (the seam that was invisible), it is
##            tinted a step off the wall's own value, and it throws its own small shadow down the
##            face beneath it.
##   PIERS  — vertical members standing a fifth taller than the wall, at its ends and along its run.
##            These are what break the FLOOR PLANE: a silhouette that steps up and down cannot read
##            as paint, and it is the difference between "a rectangle" and "a built thing".
##
## ⚠️ NEITHER MAY LIE ABOUT WHERE COVER IS, and the two are constrained differently:
##   PIERS are strictly INSET — they are placed inside the sim's own rect on both axes, so the
##     drawn silhouette never leaves the rectangle `Spatial.cover_between` tests.
##   COPING overhangs by `COPING_OVERHANG`. That is deliberate (a flush cap reads as a stripe, not
##     a cap) and it is the same 2-4% order as the section overlap `_prop_batch` already uses, far
##     below the precision the cover test resolves.
##   HEIGHT is the free axis — `PROP_HEIGHT_BODIES` says so, and a pier at `PIER_RISE` x the grade
##     height still lands under the 1.7-creature ceiling `ARENA_DESIGN.md` §4 sets for drawn cover.
##
## ⚠️ AND ROUND KINDS GET NEITHER. A square cap on a boulder is not architecture, it is a mistake —
## and `ROUND_KINDS` is the list a teammate adds new round props to, so this degrades correctly for
## kinds that do not exist yet.
## ⚠️ SMALL SOFT DEBRIS GETS NEITHER EITHER. A crate with a coping stone is a joke; the accent layer
## reads as a rash for reasons this cannot fix (its own note is in `_prop_variation`).
const COPING_OVERHANG := 1.035   # how far proud of the wall the crown course sits
const COPING_DEPTH := 0.13       # fraction of the piece's height the course occupies
const PIER_RISE := 1.20          # pier height as a multiple of the piece's own
const PIER_SPACING_BODIES := 1.6  # one pier per this many creature-widths of run
## Crown catches the light, so it sits a step ABOVE the kind's own value; the piers are in the
## wall's shade and sit a step below. Both are taken into the league's tone by `_masonry_material`,
## so they cannot drift out of the value ladder the way the untinted kinds once did.
const COPING_TINT := Color(0.82, 0.79, 0.72)
const PIER_TINT := Color(0.55, 0.53, 0.50)
## A piece shorter than this along its longest axis is furniture, not architecture.
const ARCH_MIN_BODIES := 1.15


func _cover_architecture(kind: String, grade: String, centre: Vector3, w: float, d: float,
		h: float, coping: Array, piers: Array) -> void:
	if kind in ROUND_KINDS:
		return
	var span: float = maxf(w, d)
	if span < UNIT_HEIGHT * ARCH_MIN_BODIES:
		return
	# Soft cover is knee-high scatter; dressing it up would make the board read as more built than
	# it is and would bury the grade distinction the player has to be able to see.
	if grade == "soft":
		return

	var cap_h: float = maxf(0.16, h * COPING_DEPTH)
	coping.append(_box_xform(
		Vector3(centre.x, h - cap_h * 0.5, centre.z),
		Vector3(w * COPING_OVERHANG, cap_h, d * COPING_OVERHANG)))

	var along_x: bool = w >= d
	var thick: float = minf(w, d)
	var pier_w: float = clampf(thick * 1.15, UNIT_HEIGHT * 0.18, UNIT_HEIGHT * 0.40)
	# ⚠️ THE PIER CANNOT BE WIDER THAN THE RUN IT STANDS IN. A short piece with a thick footprint
	# would otherwise place two piers that overlap into one block, which reads as the piece simply
	# having grown — the opposite of a broken silhouette.
	pier_w = minf(pier_w, span * 0.30)
	var count: int = clampi(int(round(span / (UNIT_HEIGHT * PIER_SPACING_BODIES))) + 1, 2, 7)
	var pier_h: float = h * PIER_RISE
	for i in range(count):
		var t: float = (float(i) / float(count - 1)) - 0.5
		var off: float = t * (span - pier_w)     # inset: the end piers stop at the footprint edge
		var p := Vector3(
			centre.x + (off if along_x else 0.0),
			pier_h * 0.5,
			centre.z + (0.0 if along_x else off))
		piers.append(_box_xform(p, Vector3(
			pier_w if along_x else thick, pier_h, thick if along_x else pier_w)))


## Dressed stone for the members `_cover_architecture` adds. Takes the league's own ground tone the
## same way `_prop_tint` does, so a crown course can never become the brightest object in a venue
## the way the untinted `barrel` and `bench` once did.
func _masonry_material(tint: Color) -> StandardMaterial3D:
	var g: Color = _look()["ground"]
	var gv: float = (g.r + g.g + g.b) / 3.0
	var m := StandardMaterial3D.new()
	var tex: Texture2D = Art.load_or_null("res://assets/arena/stone-block.jpg")
	if tex != null:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(0.45, 0.45, 0.45)
	m.albedo_color = Color(tint.r * gv * PROP_LIFT, tint.g * gv * PROP_LIFT, tint.b * gv * PROP_LIFT)
	m.metallic = 0.0
	m.metallic_specular = 0.18
	m.roughness = 0.88
	m.rim_enabled = true
	m.rim = 0.4
	m.rim_tint = 0.5
	return m


## ═══════════════════════════════════════════════════════════════════════════════════════════════
## WHY COVER USED TO RENDER AS GREY SLABS — three causes, all real, all fixed here
## ═══════════════════════════════════════════════════════════════════════════════════════════════
##
## The complaint was "the cover is grey slabs, and `assets/arena/` already holds barrel-wood.jpg,
## crate-wood.jpg, wall-stone.jpg, wall-timber.jpg". The textures were not the problem and neither
## was `KIND_TABLE` — `kind` is set correctly on every piece and every kind has a real CC0 model in
## `assets/models/obstacles/`. Measured causes, in order of how much each contributed:
##
## 1. ⚠️ **EVERY IMPORTED PROP MATERIAL CARRIES `metallic = 0.40`.** Six of the ten kinds
##    (crate, planter, boulder, pillar, shrine, low_wall, low_wall_border) import from glTF with a
##    metallic factor of 0.4 on what are wood and stone objects. A metal has no diffuse response —
##    it only reflects its environment — and this scene has no reflection probe and no sky, so 40%
##    of every prop's shading was being taken away and given to a reflection of nothing. That is
##    what "grey slab" actually was: a correctly textured wooden crate with nearly half its diffuse
##    term deleted. Forced to 0 below; these are dielectrics.
## 2. ⚠️ **THE PROP WAS STRETCHED TO THE COVER RECT ON EVERY AXIS.** A blocking major is
##    `MAJOR_MIN_BODIES` wide — tens of world units — and it was drawn by scaling ONE small wall
##    model to that width. Its texture atlas therefore spanned the whole piece in a handful of
##    texels, i.e. a flat colour. `_segment_counts` below tiles the model along its long axes
##    instead, so a long wall is drawn as a RUN of wall sections at roughly their natural
##    proportions. The union of the sections is still exactly the sim's rect, so the picture keeps
##    telling the truth about where cover is — which is the invariant the old comment defended and
##    it is not weakened by this change, only the stretch is.
## 3. ⚠️ **`OBSTACLE_TEX` / `OBSTACLE_TINT` WERE DEAD CODE FOR EVERY KIND WITH A MODEL**, which is
##    all of them — `_obstacle_material()` is only reached on the primitive fallback path. So the
##    authored arena textures genuinely were not being used. They are now the source for any kind
##    whose model ships WITHOUT its own texture (barrel, bench, fence today), mapped triplanar so
##    they survive the section scaling, and the tint applies on both paths.
##
## `MAX_SEGMENTS_PER_AXIS` bounds the instance count a single huge piece can add. 6x6 is far more
## than any authored layout needs; it exists so a future outsized rect cannot quietly cost 400
## instances.
## ⚠️ 6 -> 3 ON 2026-08-08, AND THE REASON IS THAT SIX IS WHAT A COMB LOOKS LIKE. The 4% section
## overlap closed the SEAM, but a strip model repeated six times across one rect still reads as a
## row of merlons rather than as one wall — repetition at that count is perceived as a pattern, and
## a pattern is decoration, not mass. `ARENA_DESIGN.md` §4 asks for "fewer and larger, always", and
## that applies inside a piece as much as across a board. Three sections is the most that still
## reads as one object. It also strictly lowers the instance budget the note below is guarding, so
## nothing downstream needs re-checking. Piece FOOTPRINTS are unchanged — `Spatial.cover_between`
## tests the rect, not the sections — so this cannot move a fight.
const MAX_SEGMENTS_PER_AXIS := 3


const PROP_DIR := "res://assets/models/obstacles/"

## One `MultiMeshInstance3D` per kind, drawing the CC0 prop instead of a primitive.
##
## ⚠️ THE SINGLE-MESH / SINGLE-MATERIAL RULE IS WHY THESE PARTICULAR PROPS WERE CHOSEN. A
## `MultiMesh` takes ONE mesh with ONE material, and obstacle count scales with ground area — so a
## multi-material prop does not merely look different, it forces a node per piece and grows draw
## calls with team size. 28 of the 70 CC0 models inspected failed that test
## (`docs/OBSTACLE_KIND_CANDIDATES.md`); every file here passed it.
##
## ⚠️ AND THE FIT IS PER-AXIS, WHICH IS A DELIBERATE TRADE. The sim's cover rect is authoritative:
## `Spatial.cover_between` tests that rectangle, and the grade is carried by height. Fitting the
## prop to it exactly means the player sees precisely the cover the sim applies — at the cost of
## stretching a prop whose proportions differ from its kind's footprint. The alternative, a
## uniform scale, looks better and LIES: a barrel drawn narrower than its rect gives cover from a
## spot that looks open. In a game the player cannot intervene in, being able to trust the picture
## outranks the picture being pretty.
## ═══════════════════════════════════════════════════════════════════════════════════════════════
## BREAKING THE MIRROR IN THE RENDERER — where `ARENA_DESIGN.md` §5 says it belongs
## ═══════════════════════════════════════════════════════════════════════════════════════════════
##
## ⚠️ THE REPORT WAS "EVERY GRAND-CIRCUIT LEAGUE IS THE SAME BOARD, PERFECTLY MIRRORED LEFT TO
## RIGHT", and half of that is not a layout bug — it is REQUIRED. `ARENA_DESIGN.md` §5: the boards
## are symmetric because fairness demands it ("an arena that favours a side biases every
## measurement taken on it"), and the doc's own answer is explicit: *"It is broken in the RENDERER
## instead, where it costs nothing: the engine knows rectangles, so inside one the mesh is turned
## and resized by a hash of its world position."* That was never built here. It is now.
##
## ⚠️ WHAT MAY VARY AND WHAT MAY NOT, because the picture must not lie about cover:
##   MAY   180-degree yaw          — the footprint is identical under it, so the sim's rect holds
##   MAY   a per-section variant mesh (`<kind>_alt.glb`) — different object, same box
##   MAY   +-4% height             — coursing irregularity, far inside the grade's own band
##   MAY   a 90-degree yaw ON A SQUARE SECTION ONLY — ⚠️ THIS RULE READ "NEVER 90-degree yaw" AND
##         THE ABSOLUTE FORM WAS TOO STRONG. The reason behind it is sound and unchanged: a quarter
##         turn swaps a rectangle's drawn extents, which moves the silhouette off the rect the sim
##         is testing. When the two extents are EQUAL the swap is the identity, so the footprint is
##         preserved exactly while the mesh inside it turns — and the accent layer, the one the
##         mirror was failing to vary, is almost entirely square. The test is measured per section
##         at the point of use, never assumed per kind.
##   NEVER  a 90-degree yaw on a non-square section, non-uniform rescale, or a nudged origin — each
##         of those does move the drawn silhouette off `Spatial.cover_between`'s rectangle
##
## Deterministic by construction: the seed is the section's own world position, so two runs of the
## same fight draw the same board (`SPATIAL_HANDOFF.md` §1 covers the sim; the renderer has no
## such obligation, but a board that reshuffles between replays of ONE fight is a legibility bug).
static func _piece_hash(p: Vector3) -> int:
	return abs(hash(Vector3i(int(round(p.x * 4.0)), int(round(p.y * 4.0)), int(round(p.z * 4.0)))))


## Split a kind's pieces between its base mesh and its `_alt` mesh, when one exists on disk. Ten of
## the kinds ship an alt today and none of them were ever drawn — a second silhouette per kind is
## the cheapest possible answer to "the two halves of the board are the same objects".
func _try_prop_multimesh(kind: String, xforms: Array) -> bool:
	var alt_path := PROP_DIR + kind + "_alt.glb"
	if xforms.size() >= 2 and ResourceLoader.exists(alt_path):
		var base_set: Array = []
		var alt_set: Array = []
		for xf in xforms:
			if _piece_hash((xf as Transform3D).origin) % 2 == 0:
				base_set.append(xf)
			else:
				alt_set.append(xf)
		# ⚠️ A SPLIT THAT LANDS EVERYTHING ON ONE SIDE IS NOT A SPLIT — fall through to the single
		# batch rather than emitting an empty MultiMesh (instance_count 0 renders nothing but still
		# costs a node, and it hid a real "no props drawn" bug the first time it happened).
		if not base_set.is_empty() and not alt_set.is_empty():
			var a := _prop_batch(kind, PROP_DIR + kind + ".glb", base_set, "")
			var b := _prop_batch(kind, alt_path, alt_set, "alt")
			if a and b:
				return true
			# Partial success means one mesh failed to load; redraw the whole kind as one batch so
			# half the pieces cannot silently vanish.
			for c in get_children():
				if c is MultiMeshInstance3D and str(c.name).begins_with("Prop_%s" % kind):
					remove_child(c)
					c.queue_free()
	return _prop_batch(kind, PROP_DIR + kind + ".glb", xforms, "")


func _prop_batch(kind: String, path: String, xforms: Array, suffix: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var scn := load(path) as PackedScene
	if scn == null:
		return false
	var inst: Node = scn.instantiate()
	var mi := _first_mesh(inst) as MeshInstance3D
	if mi == null or mi.mesh == null:
		inst.free()
		return false

	# Bounds in the INSTANCE's own space — the glTF importer parks its own scale between the scene
	# root and the mesh, and it differs per export, so the raw local AABB is in the wrong units.
	#
	# ⚠️ WALKED BY HAND, NOT VIA `global_transform`. This scene is never added to the tree — it is
	# instantiated only to harvest its mesh — and `global_transform` on a node outside the tree
	# returns identity while spamming "Condition !is_inside_tree() is true". Adding it to the tree
	# just to measure it would be a node built and freed per kind, per fight.
	var ab: AABB = _chain_from(inst, mi) * mi.get_aabb()
	var mesh: Mesh = mi.mesh
	var mat: Material = mi.get_active_material(0)
	inst.free()
	if ab.size.x <= 0.0001 or ab.size.y <= 0.0001 or ab.size.z <= 0.0001:
		return false

	# ⚠️ THE SEGMENT CAP FALLS AS THE PIECE COUNT RISES, and that is a scaling guard, not a taste
	# call. A teammate is rewriting `arena_layout.gd` to place MANY more pieces per board; at 6x6
	# per piece, forty pieces would be 1,440 instances of one kind. The budget below keeps a kind's
	# batch bounded whatever count arrives, and degrades in the right direction — with more objects
	# on the board, each one needs less internal detail to stop the board reading as empty.
	var seg_cap: int = MAX_SEGMENTS_PER_AXIS
	if xforms.size() > 48:
		seg_cap = 2
	elif xforms.size() > 16:
		seg_cap = 3

	# Build every section's transform first — the instance count is no longer one-per-piece.
	var placed: Array = []
	for i in range(xforms.size()):
		# `xf` already encodes the target box: basis scale is (w, h, d) and the origin sits at the
		# box's CENTRE. Convert that into "fill this box with sections of this prop".
		var xf: Transform3D = xforms[i]
		var want: Vector3 = xf.basis.get_scale()
		var counts: Vector2i = _segment_counts(want, ab.size, seg_cap)
		var seg := Vector3(want.x / float(counts.x), want.y, want.z / float(counts.y))
		var s := Vector3(seg.x / ab.size.x, seg.y / ab.size.y, seg.z / ab.size.z)
		var foot: float = xf.origin.y - want.y * 0.5
		# ⚠️ SECTIONS OVERLAP SLIGHTLY, AND THIS IS THE OTHER HALF OF THE "COMB" DEFECT. A run of
		# abutting sections shows the model's own end profile at every seam, so a wall drawn as six
		# sections rendered as six crenellations — the exact thing reported. Growing each section a
		# few percent about its own centre closes the seam. It pushes the drawn silhouette past the
		# sim's rect by half the overlap at the two OUTER ends only: 2% of one section, i.e. 0.3% of
		# a six-section wall, which is far below the sub-unit precision the cover test resolves.
		var lap: float = 1.04 if (counts.x > 1 or counts.y > 1) else 1.0
		for cx in range(counts.x):
			for cz in range(counts.y):
				var ox: float = xf.origin.x - want.x * 0.5 + seg.x * (float(cx) + 0.5)
				var oz: float = xf.origin.z - want.z * 0.5 + seg.z * (float(cz) + 0.5)
				var hsh: int = _piece_hash(Vector3(ox, 0.0, oz))
				# ── ⚠️ THE VARIETY THE MIRROR WAS SUPPOSED TO PROVIDE AND DID NOT.
				#
				# The report: "103 pillars at 0.48 bodies and 51 boulders at 0.54 read as a rash of
				# near-identical small shapes — and a 180-degree yaw on a near-symmetric small prop
				# is INVISIBLE, so the mirror does nothing for variety either." That is exactly
				# right, and it is a straightforward consequence of the rule above this function:
				# only a half-turn was allowed, because a quarter-turn moves a rectangle's drawn
				# silhouette off the sim's own rect.
				#
				# ⚠️ BUT IT DOES NOT WHEN THE RECT IS SQUARE, AND THE ACCENT LAYER IS ALMOST ALL
				# SQUARE. A quarter-turn maps this section's drawn x-extent onto z and its z-extent
				# onto x; when those are equal the union is byte-identical and
				# `Spatial.cover_between` cannot tell the difference — while the MESH inside it
				# turns through 90 degrees, which is the one rotation a small blocky prop actually
				# reads. So the turn is gated on the SECTION's own measured squareness rather than
				# permitted or banned globally.
				var square: bool = absf(seg.x - seg.z) <= maxf(seg.x, seg.z) * 0.02
				var turns: int = (hsh / 5) % (4 if square else 2)
				# ⚠️ AND THE HEIGHT JITTER IS GRADE-AWARE NOW. ±2% was set as "coursing
				# irregularity" and is genuinely invisible on a knee-high crate. Non-blocking cover
				# can take far more without meaning anything different — its grade is "you shoot
				# over it" either way — so the accent layer gets a spread the eye can actually see.
				# BLOCKING keeps the tight band: `_probe_venue.gd` fails a blocking piece under 1.0
				# creature heights, and 1.18 x 0.88 would cross it.
				var blocking: bool = absf(want.y - prop_height("blocking")) < 0.01
				var jitter: float = 0.02 if blocking else 0.055
				var hv: float = 1.0 + (float(hsh % 5) - 2.0) * jitter
				var basis := Basis().scaled(Vector3(s.x * lap, s.y * hv, s.z * lap))
				if turns > 0:
					basis = basis.rotated(Vector3.UP, PI * 0.5 * float(turns))
				# Re-seat on the ground: the prop's own minimum, scaled, is the offset from centre.
				placed.append(Transform3D(basis,
					Vector3(ox, foot - ab.position.y * s.y * hv, oz)))

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = placed.size()
	for i in range(placed.size()):
		mm.set_instance_transform(i, placed[i])

	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = _prop_material(kind, mat)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.name = "Prop_%s%s" % [kind, ("_" + suffix) if suffix != "" else ""]
	add_child(node)
	return true


## How many sections of a prop to lay along X and Z to fill a cover rect without stretching it out
## of proportion. Height is never sectioned — the sim carries the cover GRADE in height and a
## stacked wall would misreport it.
##
## The prop's natural width is taken at the scale its HEIGHT is being drawn at, so a piece keeps a
## believable width:height ratio; anything wider than ~1.6 of that gets another section.
## ⚠️ RAISING THE DRAWN HEIGHT ALSO CUTS THE SEGMENT COUNT, WHICH IS THE FIRST HALF OF THE "COMB"
## FIX AND COSTS NOTHING. `s_y` is the scale the model is being drawn at, so a prop drawn 62%
## taller (blocking cover, 3.2 -> 5.19) is also 62% wider per section and needs 62% fewer sections
## to span the same rect. The wall that reported as a comb of six crenellations spans in two.
static func _segment_counts(want: Vector3, natural: Vector3, cap: int = MAX_SEGMENTS_PER_AXIS) -> Vector2i:
	if natural.y <= 0.0001:
		return Vector2i(1, 1)
	var lim: int = clampi(cap, 1, MAX_SEGMENTS_PER_AXIS)
	var s_y: float = want.y / natural.y
	var nat_x: float = maxf(0.0001, natural.x * s_y)
	var nat_z: float = maxf(0.0001, natural.z * s_y)
	var nx: int = clampi(int(round(want.x / (nat_x * 1.6))), 1, lim)
	var nz: int = clampi(int(round(want.z / (nat_z * 1.6))), 1, lim)
	return Vector2i(nx, nz)


## THE PROP GEOMETRY REPORT — what `_probe_venue.gd` measures proportion from.
##
## ⚠️ THE INSTRUMENT READS THE RENDERER, IT DOES NOT RE-DERIVE IT. The last round of this file's
## history is full of numbers that were reasoned about rather than measured; a probe that computed
## its own idea of a prop's drawn height would agree with the code exactly until someone changed
## one of them, and would then confidently report on a board nobody is looking at. Every figure
## below comes from the same calls `_build_obstacles` makes.
##
## Returns one row per obstacle: kind · grade · drawn w/h/d in world units · the same three in
## CREATURE HEIGHTS (the yardstick the proportion complaint was stated in) · the section counts
## actually used · the model's natural proportions.
func prop_report() -> Array:
	var rows: Array = []
	var natural_cache: Dictionary = {}
	for o in _obstacles:
		var kind: String = str(o.get("kind", "crate"))
		var grade: String = str(o.get("grade", "soft"))
		var r: Rect2 = o["rect"]
		var w := maxf(r.size.x * WORLD_SCALE, 0.6)
		var d := maxf(r.size.y * WORLD_SCALE, 0.6)
		var h := prop_height(grade)
		if not natural_cache.has(kind):
			natural_cache[kind] = _prop_natural(kind)
		var nat: Vector3 = natural_cache[kind]
		var segs := Vector2i(1, 1)
		if nat.y > 0.0:
			segs = _segment_counts(Vector3(w, h, d), nat)
		rows.append({
			"kind": kind, "grade": grade,
			"centre": _to_world(r.position + r.size * 0.5) + Vector3(0, h * 0.5, 0),
			"w": w, "d": d, "h": h,
			"w_bodies": w / UNIT_HEIGHT, "d_bodies": d / UNIT_HEIGHT, "h_bodies": h / UNIT_HEIGHT,
			"long_over_tall": maxf(w, d) / maxf(0.001, h),
			"segments": segs, "natural": nat,
		})
	return rows


## The model's own bounding size, or Vector3.ZERO when the kind draws as a primitive.
func _prop_natural(kind: String) -> Vector3:
	var path := PROP_DIR + kind + ".glb"
	if not ResourceLoader.exists(path):
		return Vector3.ZERO
	var scn := load(path) as PackedScene
	if scn == null:
		return Vector3.ZERO
	var inst: Node = scn.instantiate()
	var mi := _first_mesh(inst) as MeshInstance3D
	var out := Vector3.ZERO
	if mi != null and mi.mesh != null:
		out = (_chain_from(inst, mi) * mi.get_aabb()).size
	inst.free()
	return out


## The material a prop is actually drawn with. See the block comment above `MAX_SEGMENTS_PER_AXIS`
## for why the imported one cannot be used as-is.
##
## ⚠️ THE MISSING-TEXTURE PATH IS THE ONE THAT LIGHTS UP FOR FREE. A kind whose model ships without
## a texture takes the authored `assets/arena/` art instead, mapped WORLD-TRIPLANAR so it tiles
## correctly across a sectioned wall regardless of what the model's own UVs do. When more arena
## textures land, adding a row to `OBSTACLE_TEX` is the whole integration; when one is absent it
## degrades to the kind's tint, which is a plausible object rather than a grey box.
func _prop_material(kind: String, imported: Material) -> Material:
	var tint: Color = _prop_tint(kind)
	var base := StandardMaterial3D.new()
	var tex: Texture2D = Art.load_or_null(str(OBSTACLE_TEX.get(kind, "")))
	if tex != null:
		# ⚠️ FIRST CHOICE: THE AUTHORED PER-KIND TEXTURE, MAPPED WORLD-TRIPLANAR. Authored beats
		# imported for two reasons. It is INTENT — someone drew `low-wall-brick.jpg` FOR the low
		# wall, where the model's own texture is a shared CC0 atlas that happens to contain a wall.
		# And it SURVIVES THE FIT: a cover piece is scaled and sectioned to the sim's own rect, and
		# a triplanar projection is indifferent to that where atlas UVs stretch to a flat smear.
		# Adding a row to `OBSTACLE_TEX` is the whole integration for a newly generated texture;
		# removing one degrades to the model's own look, and then to a tinted solid.
		base.albedo_texture = tex
		base.uv1_triplanar = true
		base.uv1_world_triplanar = true
		base.uv1_scale = Vector3(0.45, 0.45, 0.45)
		base.albedo_color = tint
	elif imported is StandardMaterial3D and (imported as StandardMaterial3D).albedo_texture != null:
		base = (imported as StandardMaterial3D).duplicate()
		var own: Color = base.albedo_color
		base.albedo_color = Color(own.r * tint.r, own.g * tint.g, own.b * tint.b, own.a)
	else:
		var fb: Color = OBSTACLE_FALLBACK.get(kind, Color(0.5, 0.45, 0.35))
		base.albedo_color = Color(fb.r * tint.r, fb.g * tint.g, fb.b * tint.b)
	# ⚠️ THE LINE THAT FIXED THE GREY. Wood and stone are dielectrics; the glTF import gives them
	# metallic 0.4 and this scene has nothing for a metal to reflect.
	base.metallic = 0.0
	base.metallic_specular = 0.22
	base.roughness = maxf(base.roughness, 0.82)
	base.rim_enabled = true
	base.rim = 0.45
	base.rim_tint = 0.5
	return base


## The accumulated local transform from `root` down to `node`, for a scene that is not in the
## tree. Multiplies parent-to-child so the result maps `node`'s local space into `root`'s.
static func _chain_from(root: Node, node: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _first_mesh(n: Node) -> Node:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _first_mesh(c)
		if r != null:
			return r
	return null


## ═══════════════════════════════════════════════════════════════════════════════════════════════
## HUE SEPARATION — because value alone does not stop cover vanishing into its floor
## ═══════════════════════════════════════════════════════════════════════════════════════════════
##
## ⚠️ THE REPORT WAS "AT MASTERS THE MAJORS HUE-MATCH THE RED-BRICK FLOOR AND NEARLY VANISH", and
## it is exactly right: `low-wall-brick.jpg` is a red-orange brick and Masters' ground art is a
## red-orange brick. `_probe_frame.gd` measures it as a hue distance between the piece's lit face
## and the floor immediately beside it, and the two land within a few degrees of each other while
## passing every luminance check in the project — because those checks only ever asked about VALUE.
##
## ⚠️ AND THE OLD `_prop_tint` MADE IT WORSE, NOT BETTER, WHICH IS THE PART WORTH REMEMBERING. It
## multiplied the kind's tint by `LEAGUE_LOOK.ground` — the league's own FLOOR colour — so every
## prop in the venue was being pushed toward the hue of the surface it needed to stand out from.
## That was the right instinct (props must take the league's tone or they drift out of the value
## ladder, which is the fault the `OBSTACLE_TINT` header records) applied on the wrong channel. The
## league tone is a VALUE relationship, so it is applied as a value here: the ground colour's mean,
## not its RGB. Every measured luminance the previous rounds tuned survives — `LEAGUE_LOOK.ground`
## rows are near-neutral, so their mean is within a few percent of their per-channel effect — and
## hue is freed to do the job value cannot.
##
## Then the collision is corrected where it actually occurs. Both the floor and the prop are
## TEXTURES, so their colours are properties of the ART and cannot be reasoned about from the tint
## alone; both are measured from the images themselves, once, at venue build. If the predicted
## product lands too close to the floor, `_chroma_separated` re-solves the tint until it does not.
##
## ⚠️ THE CORRECTION MOVES CHROMA, NOT HUE, AND NOT VALUE — see `_chroma_separated` for the frame
## that killed the hue version (pink walls at Wood) and `PROP_VALUE_MAX_SCALE` for the frame that
## killed the value version (boulders out-valuing the creatures). Both were caught by looking at a
## picture after the numbers had already agreed the change was good, which is the standing lesson
## of this file.
const HUE_MAX_TINT := 2.4        # a re-solved tint channel is clamped here; see `_chroma_separated`
const PROP_MAX_SAT := 0.34       # the venue is muted; chroma belongs to the team and status channels

## Average colour of a texture path, computed once per venue. ⚠️ CACHED BECAUSE `get_image()` ON A
## COMPRESSED TEXTURE IS A DECOMPRESS: eleven kinds x every piece would be a decompress per prop.
var _tex_avg_cache: Dictionary = {}


func _tex_average(path: String) -> Color:
	return _avg_of(Art.load_or_null(path), path)


## ⚠️ KEYED BY A CALLER-SUPPLIED STRING, NOT BY A PATH, because the ground texture does NOT come
## from a path this file can build: `Art.ground_for()` walks down the ladder to the nearest painted
## league, so a league with no art of its own borrows a lower rung's. Reconstructing that slug here
## would be a second copy of that rule, and the two would part company the first time a league was
## painted.
func _avg_of(tex: Texture2D, cache_key: String) -> Color:
	if _tex_avg_cache.has(cache_key):
		return _tex_avg_cache[cache_key]
	var out := Color(0, 0, 0, 0)      # alpha 0 = "no answer", never a plausible-looking grey
	if tex != null:
		var img: Image = tex.get_image()
		if img != null:
			# ⚠️ A 1x1 RESIZE, NOT A PIXEL LOOP. `Image.resize` box-filters on the way down, which is
			# the average, and it runs in the engine rather than in a GDScript double loop over a
			# 1024x1024 texture (which is 1M `get_pixel` calls per kind).
			var small: Image = img.duplicate()
			if small.is_compressed():
				small.decompress()
			small.resize(1, 1, Image.INTERPOLATE_LANCZOS)
			out = small.get_pixel(0, 0)
			out.a = 1.0
	_tex_avg_cache[cache_key] = out
	return out


## The floor's own average colour as DRAWN — the ground art times the league's tone. This is the
## thing cover has to separate from, and it is neither the texture alone nor the tint alone.
## The multiplier that lands a venue-shell surface at `ratio` of THIS league's drawn floor value.
##
## `base` is what the surface would be drawn as at a multiplier of 1.0 (its texture average times
## the league tone, or the tone alone when there is no art). Both sides are albedo and both sides
## are lit by the same lamps, so the albedo ratio is the rendered ratio to within the shading term
## — which is why this can be solved once at build time instead of measured off a frame.
func _shell_tone(base: Color, ratio: float) -> float:
	var floor_l: float = _floor_average().get_luminance()
	var base_l: float = maxf(0.001, base.get_luminance())
	return clampf(ratio * floor_l / base_l, SHELL_TONE_MIN, SHELL_TONE_MAX)


func _floor_average() -> Color:
	var g: Color = _look()["ground"]
	var t: Color = _avg_of(Art.ground_for(league_name, _league_names()), "ground:" + league_name)
	if t.a < 0.5:
		# No readable ground art: the floor IS the tone, which is what `_build_world` falls back to.
		return Color(0.55 * g.r, 0.50 * g.g, 0.43 * g.b)
	return Color(t.r * g.r, t.g * g.g, t.b * g.b)


## Re-solve `tint` so the drawn cover separates from its floor on the CHROMA axis, at constant
## value — the only axis with room left once the value ladder has claimed the other one.
##
## ⚠️ THIS WAS A HUE ROTATION FIRST AND THE HUE ROTATION WAS WRONG. Rotating a colour away from the
## floor's hue is arithmetically clean and visually indefensible: Wood's floor is brown (hue ~0.08),
## so a 0.17 rotation put the brick walls at hue 0.91 and the boulders at 0.25 — **PINK WALLS AND
## GREEN ROCKS**, which is not a legibility fix, it is a colour accident. `ART_BIBLE_GUILD_COLOURS.md`
## allows three colour systems and forbids a fourth; a venue that invents magenta masonry has broken
## the rule far worse than the collision it was solving. It shipped as far as one captured frame and
## no further, which is the entire argument for judging from frames rather than from tables.
##
## ⚠️ THE REPLACEMENT USES THE AXIS A REAL VENUE USES: chroma, not hue. Grey stone reads
## effortlessly against a red-brick floor — not because its hue differs but because it has almost
## none. So when the predicted cover colour sits too close to the floor in the opponent-colour
## plane, its SATURATION is pulled away from the floor's, toward stone. Every rotation this can
## produce stays inside the masonry-and-timber gamut, because desaturating a brick gives you a
## paler brick and never gives you a pink one.
##
## ⚠️ AND IT MOVES AT CONSTANT VALUE, which is what makes it safe to use at all. `_probe_venue.gd`
## needs stands < walls < floor < cover < creatures, and the cast sits only ~1.12-1.2x the floor, so
## the value band available to cover is a few percent wide. A chroma move cannot spend any of it.
const CHROMA_MIN_SEP := 0.115    # opponent-plane distance; see `_chroma_of`
const CHROMA_PULL := 0.42        # how far toward stone a colliding kind is taken
const CHROMA_SAT_MIN := 0.045    # never fully grey — a colourless prop reads as untextured


## Two cheap opponent-colour axes. ⚠️ NOT HUE, and the difference is the whole point: hue is
## undefined at low saturation and jumps wildly near it, which is why the first version of the
## probe reported a `bench` at 0.003 hue distance and a `barrel` at 0.148 from art that looks
## nearly identical. Distance in this plane behaves at every saturation, including zero.
static func _chroma_of(c: Color) -> Vector2:
	return Vector2(c.r - c.g, 0.5 * (c.r + c.g) - c.b)


static func _chroma_separated(tint: Color, tex_avg: Color, floor_col: Color) -> Color:
	if tex_avg.a < 0.5:
		return tint
	var predicted := Color(tex_avg.r * tint.r, tex_avg.g * tint.g, tex_avg.b * tint.b)
	if _chroma_of(predicted).distance_to(_chroma_of(floor_col)) >= CHROMA_MIN_SEP:
		return tint
	# Toward stone when the floor carries the colour, and a little warmer when the floor is grey —
	# in both cases AWAY from whatever the floor is doing, which is the only requirement.
	var target_s: float
	if floor_col.s >= predicted.s:
		target_s = maxf(CHROMA_SAT_MIN, predicted.s - (predicted.s - CHROMA_SAT_MIN) * CHROMA_PULL)
	else:
		target_s = minf(PROP_MAX_SAT, predicted.s + (PROP_MAX_SAT - predicted.s) * CHROMA_PULL)
	var target := Color.from_hsv(predicted.h, target_s, predicted.v)
	return Color(
		clampf(target.r / maxf(0.02, tex_avg.r), 0.0, HUE_MAX_TINT),
		clampf(target.g / maxf(0.02, tex_avg.g), 0.0, HUE_MAX_TINT),
		clampf(target.b / maxf(0.02, tex_avg.b), 0.0, HUE_MAX_TINT))


## The kind's material tint, TAKEN INTO THE LEAGUE'S OWN VALUE RANGE and then separated in chroma from
## the floor it stands on. See `OBSTACLE_TINT` for what the league factor is for, and the block
## above for why it is applied as a VALUE and no longer as a colour.
func _prop_tint(kind: String) -> Color:
	var t: Color = OBSTACLE_TINT.get(kind, PROP_TINT_DEFAULT)
	var g: Color = _look()["ground"]
	var gv: float = (g.r + g.g + g.b) / 3.0
	var scaled := Color(t.r * gv * PROP_LIFT, t.g * gv * PROP_LIFT, t.b * gv * PROP_LIFT)
	var tex_path: String = str(OBSTACLE_TEX.get(kind, ""))
	if tex_path == "":
		return scaled
	var tex_avg: Color = _tex_average(tex_path)
	var floor_avg: Color = _floor_average()
	scaled = _value_separated(scaled, tex_avg, floor_avg)
	return _chroma_separated(scaled, tex_avg, floor_avg)


## ── THE PER-LEAGUE VALUE CORRECTION THE `PROP_LIFT` HEADER ASKED FOR AND COULD NOT DO ──────────
##
## ⚠️ `PROP_LIFT`'s own note names this exactly: *"the sharp [instrument] would be a per-league prop
## factor measured off each ground"*, and says it was not worth doing speculatively. It is worth
## doing now, because the frame probe measured the damage. A prop takes the league's `ground`
## MULTIPLIER but has never seen how bright that league's ground TEXTURE actually is, so the
## prop-against-floor relationship the tints were calibrated for holds only at the league they were
## calibrated on. Measured, at a bar of 0.16 stops: Masters `low_wall` 0.13 · Masters `boulder` 0.07
## · Tamers Apex `fence` 0.09 · Tamers Apex `pillar` 0.08 — cover drawn at the same value as the
## floor under it, in the leagues that matter most.
##
## Both terms are now READ FROM THE ART: the floor's average as drawn (texture x league tone) and
## the kind's own texture average. When the predicted product lands too close to the floor, the
## tint is scaled until it does not.
##
## ⚠️ IT FIRES ONLY ON A COLLISION, WHICH IS WHY IT DOES NOT UNDO THREE ROUNDS OF TUNING. A kind
## already sitting clear of its floor is returned untouched; the correction is a floor under the
## relationship, not a replacement for the authored values.
##
## ⚠️ AND IT PUSHES UP, NEVER DOWN. `OBSTACLE_TINT` records what happened when props were allowed
## to sink: "planter at 0.75x, which is what [a stain on the floor] looks like". Cover is an object
## standing on the ground and reads a little above it. The clamp is what stops that becoming a
## bright slab on a very dark league — past 1.8x the authored tint, the honest answer is that the
## league's ground art is too bright, not that its cover should glow.
const PROP_OVER_FLOOR := 1.24     # predicted drawn value of cover against its own floor
## ⚠️ 0.30 PREDICTED, TO BUY 0.16 RENDERED, AND THE GAP IS NOT SLACK — IT IS THE LAMP. This
## prediction is an albedo product; the pixel has been through a strongly warm key, a cool fill, a
## FILMIC curve and the fog term, all of which compress differences. Measured, a predicted 0.075 of
## HUE separation rendered as 0.030. Calibrate this against `_probe_frame.gd`, never against the
## arithmetic.
const PROP_VALUE_MIN_SEP := 0.30
## ⚠️ 1.8 -> 1.30 -> 1.18 -> 1.10, AND THE LAST CUT IS THE IMPORTANT ONE BECAUSE IT WAS A
## REGRESSION CAUGHT BY LOOKING. At 1.18 the Wood boulders measured 0.96 stops above their floor
## and rendered as bright cream lumps that OUT-VALUED THE CREATURES — the one thing
## `ART_DIRECTION.md` never allows, fixed on one axis by breaking a more important rule on another.
##
## ⚠️ THE REAL LESSON IS THAT VALUE IS THE WRONG CHANNEL FOR THIS JOB, AND THE LADDER SAYS SO.
## `_probe_venue.gd` requires stands < walls < floor < cover < creatures, and the cast sits only
## ~1.12-1.2x the floor — so the whole band available to cover is a few percent wide. Asking value
## to also carry 0.16 stops of separation is asking it to be in two places at once. HUE is where
## the room is: `_hue_separated` moves a colour at constant S and V, so it cannot touch the ladder
## at all. Value is left as a small nudge for the case where a kind is literally the same value as
## its floor, and it is capped where it cannot reach the cast.
const PROP_VALUE_MAX_SCALE := 1.10


static func _luma_of(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


static func _value_separated(tint: Color, tex_avg: Color, floor_col: Color) -> Color:
	if tex_avg.a < 0.5:
		return tint
	var fv: float = _luma_of(floor_col)
	var pv: float = _luma_of(Color(tex_avg.r * tint.r, tex_avg.g * tint.g, tex_avg.b * tint.b))
	if fv < 0.01 or pv < 0.004:
		return tint
	if absf(log(pv / fv) / log(2.0)) >= PROP_VALUE_MIN_SEP:
		return tint
	var k: float = clampf((fv * PROP_OVER_FLOOR) / pv, 1.0, PROP_VALUE_MAX_SCALE)
	return Color(tint.r * k, tint.g * k, tint.b * k)


func _obstacle_material(kind: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var tint: Color = _prop_tint(kind)
	var tex: Texture2D = Art.load_or_null(OBSTACLE_TEX.get(kind, "res://assets/arena/crate-wood.jpg"))
	if tex != null:
		mat.albedo_texture = tex
		mat.albedo_color = tint
	else:
		var fb: Color = OBSTACLE_FALLBACK.get(kind, Color(0.5, 0.45, 0.35))
		mat.albedo_color = Color(fb.r * tint.r, fb.g * tint.g, fb.b * tint.b)
	mat.roughness = 0.9
	return mat


func _league_names() -> Array:
	var career := get_node_or_null("/root/Career")
	if career == null:
		return Art.ARENA_LEAGUES
	var names: Array = []
	for l in career.leagues:
		names.append(l.get("name", ""))
	return names


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# CAMERA — follows the living units' own spread, never a static formula.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## Bounding box of the currently-alive units (all units if none are alive yet/left), in world
## space, padded and clamped. This is the ONLY thing the camera reads to decide where to look —
## positions the frame stream already gave the renderer, nothing invented.
func _camera_target() -> Dictionary:
	if _cam_mode == CamMode.FREE:
		return {"center": _free_center, "span": _free_span}
	# ⚠️ Observation mode — frame the whole ground and never move.
	if _cam_mode == CamMode.ARENA:
		var bw := ground_size.x * WORLD_SCALE
		var bd := ground_size.y * WORLD_SCALE
		# The ground's half-depth is foreshortened by the camera pitch; its half-width is not. Take
		# whichever needs the wider frame so neither edge is cropped.
		# ⚠️ `span` is the half-extent that fills the VERTICAL fov, so a width cannot be compared
		# against it directly — it has to be divided by the aspect ratio first. Comparing them raw
		# over-sized the frame by the full 16:9, which is why the whole arena sat as a small slab
		# with empty margins above and below it.
		var aspect: float = maxf(0.1, get_viewport().get_visible_rect().size.aspect())
		var need_x: float = (bw * 0.5) / aspect
		var need_z: float = bd * 0.5 * sin(deg_to_rad(CAM_PITCH_DEG))
		return {"center": Vector3.ZERO, "span": maxf(need_x, need_z) * 1.04}

	# ⚠️ ACTION mode is now a DIRECTOR, not a fitter — it finds where the fight is and frames that.
	if _cam_mode == CamMode.ACTION:
		return _director_target()

	var pts: Array = []
	for k in range(nodes.size()):
		if k >= all_units.size() or not _alive_now(k):
			continue
		# TEAM mode: frame YOUR side (team A) — the fight from the owner's box seat. The enemy
		# enters frame exactly when it engages your line, which is when it matters.
		if _cam_mode == CamMode.TEAM and not (all_units[k] in team_a):
			continue
		pts.append((nodes[k]["holder"] as Node3D).position)
	if pts.is_empty():
		for k in range(nodes.size()):
			pts.append((nodes[k]["holder"] as Node3D).position)
	if pts.is_empty():
		return {"center": Vector3.ZERO, "span": _cam_max_span}

	var mn: Vector3 = pts[0]
	var mx: Vector3 = pts[0]
	for p in pts:
		mn.x = minf(mn.x, p.x); mn.z = minf(mn.z, p.z)
		mx.x = maxf(mx.x, p.x); mx.z = maxf(mx.z, p.z)
	var center := Vector3((mn.x + mx.x) * 0.5, 0.0, (mn.z + mx.z) * 0.5)
	# ⚠️ Bodies, not points — see the constants above. A creature standing on the edge of the pack
	# extends half a footprint further out than the position the sim reports for it, and its head
	# extends upward into screen space the ground box cannot see.
	var half_x := (mx.x - mn.x) * 0.5 + CAM_BODY_RADIUS
	var half_z := (mx.z - mn.z) * 0.5 + CAM_BODY_RADIUS
	var span := maxf(half_x, half_z) * CAM_PADDING + CAM_HEADROOM + CAM_HEIGHT_ALLOWANCE
	span = maxf(span, CAM_MIN_SPAN)
	span = minf(span, _cam_max_span)
	return {"center": center, "span": span}


## Playback time in seconds — the replay's own clock, NOT the wall clock. Everything the director
## remembers (dwell, a recent hit, a recent death) is measured on this, so the shot behaves the
## same at 0.5x as at 4x and a scrub backwards rewinds the camera's memory with the fight.
func _play_t() -> float:
	return frame_pos * NewSim.DT


## How much this unit deserves the shot RIGHT NOW. Every term is read from the frame being
## displayed or from an event the player has already been shown — the renderer invents no state
## here, it only decides where to point (`docs/BUILD_CONTRACT.md` §2: presentation may prioritise,
## it may not compute a game fact).
func _cam_interest(k: int) -> float:
	var t := _play_t()
	if not _alive_now(k):
		# A body that has just fallen is the most important thing on the board for a moment, and
		# nothing at all after that.
		var d: float = t - float(_death_at.get(k, -999.0))
		return 12.0 if (d >= 0.0 and d < CAM_DEATH_HOLD) else -1.0
	var rec: Dictionary = (nodes[k] as Dictionary).get("last_rec", {})
	var w := 1.0
	var st := str(rec.get("state", "idle"))
	if st == "attack":
		w += 3.0
	elif st == "cast":
		w += 2.6      # the windup IS the drama — it is the interrupt window
	elif st == "stunned":
		w += 1.6
	if not (rec.get("statuses", []) as Array).is_empty():
		w += 0.8
	var mx: float = float(all_units[k].max_hp) if k < all_units.size() else 0.0
	if mx > 0.0:
		var frac: float = float(rec.get("hp", mx)) / mx
		if frac < 0.35:
			w += 2.5
		elif frac < 0.7:
			w += 0.9
	var since_hit: float = t - float(_hit_at.get(k, -999.0))
	if since_hit >= 0.0 and since_hit < CAM_HIT_MEMORY:
		w += 3.5 * (1.0 - since_hit / CAM_HIT_MEMORY)
	if k == selected_idx:
		w += 4.0      # the player asked to watch this one
	return w


## The unit on the player's side of the closest living A-vs-B pair — the contact that is about to
## happen. Returns -1 if either side is empty. Positions come from the frame; nothing derived.
func _closest_opposing_pair() -> int:
	var na: int = team_a.size()
	var best := -1
	var best_d := 1e12
	for a in range(0, na):
		if not _alive_now(a):
			continue
		var pa: Vector3 = (nodes[a]["holder"] as Node3D).position
		for b in range(na, nodes.size()):
			if not _alive_now(b):
				continue
			var d: float = pa.distance_squared_to((nodes[b]["holder"] as Node3D).position)
			if d < best_d:
				best_d = d
				best = a
				_cam_partner = b
	if best < 0:
		_cam_partner = -1
	return best


## Pick a subject under the stickiness rule above, then frame ITS ENGAGEMENT — the subject plus
## everything standing within `CAM_ENGAGE_R` of it. That is what makes this direction rather than
## averaging: the far wing of a strung-out fight is deliberately left out of shot, and the pips
## in `_update_offscreen_pips()` are what stop that from being a lie.
func _director_target() -> Dictionary:
	var t := _play_t()
	var best := -1
	var best_w := -1.0
	for k in range(nodes.size()):
		var w := _cam_interest(k)
		if w > best_w:
			best_w = w
			best = k
	# ⚠️ THE APPROACH IS 40% OF EVERY FIGHT AND THE DIRECTOR HAS NO SIGNAL DURING IT. Measured:
	# first damage lands at t=9.6-9.9s of a 22s fight (`docs/WATCH_AUDIT.md` §0), so for the first
	# nine seconds nobody is casting, nobody is hurt, nobody has been hit — every interest score
	# is the 1.0 floor and the subject is whichever unit happens to be first in the roster. That
	# produced a shot of one rival standing alone while all five of the player's monsters were off
	# frame (`watch_..._cam1_04_t008.0.png`).
	#
	# The approach has exactly one piece of drama and it is the GAP: which two lines are about to
	# meet, and how long is left. So when nothing else is happening the shot goes to the closest
	# opposing pair — the contact that is about to happen — and the tension is legible instead of
	# being dead air over an arbitrary monster.
	# ⚠️ THE APPROACH SHOT BYPASSES THE DWELL RULE, AND IT HAS TO. The first cut of this made the
	# closest pair merely a CANDIDATE, and it never won: with every interest score sitting on the
	# 1.0 floor, no challenger can beat an incumbent by the 1.5x switch margin, so the camera kept
	# whichever unit it happened to grab in the first frame for the whole nine-second approach.
	# Stickiness protects a shot from being stolen mid-drama; during dead air there is no drama to
	# protect, so the rule is suspended rather than fought.
	_cam_partner = -1
	var approach: bool = best_w < 2.0
	if approach:
		var pair := _closest_opposing_pair()
		if pair >= 0:
			if pair != _cam_subject:
				_cam_subject = pair
				_cam_subject_since = t
			best = pair
	var cur_w: float = _cam_interest(_cam_subject) if _cam_subject >= 0 else -1.0
	var held: float = t - _cam_subject_since
	var take := false
	if _cam_subject < 0 or cur_w < 0.0:
		take = true                                   # no subject, or the subject is gone
	elif not approach and held >= CAM_DWELL and best_w > cur_w * CAM_SWITCH_MARGIN:
		take = true                                   # earned the cut
	if take and best >= 0 and best != _cam_subject:
		var old_pos := Vector3.ZERO
		if _cam_subject >= 0:
			old_pos = (nodes[_cam_subject]["holder"] as Node3D).position
		var new_pos: Vector3 = (nodes[best]["holder"] as Node3D).position
		# A long move is a CUT (the eye accepts it as a new shot); a short one EASES (it reads as
		# the same shot following the action). A three-second swoop across the board is the worst
		# of both and is what a pure fitter does every time the fight spreads.
		_cam_want_snap = _cam_subject >= 0 and old_pos.distance_to(new_pos) > _cam_span * CAM_SNAP_SPANS
		_cam_subject = best
		_cam_subject_since = t
	# The partner belongs to the CHALLENGER's shot. If the dwell rule kept the old subject, the
	# approach pair is not what we are framing and must not widen it.
	if _cam_subject != best:
		_cam_partner = -1
	if _cam_subject < 0:
		return {"center": Vector3.ZERO, "span": _cam_max_span}

	var focus: Vector3 = (nodes[_cam_subject]["holder"] as Node3D).position
	var mn := focus
	var mx := focus
	for k in range(nodes.size()):
		if k == _cam_subject or not _alive_now(k):
			continue
		var p: Vector3 = (nodes[k]["holder"] as Node3D).position
		# The approach partner is in shot whatever the engagement radius says — it IS the shot.
		var reach: float = (CAM_APPROACH_R if k == _cam_partner else CAM_ENGAGE_R) * WORLD_SCALE
		if focus.distance_to(p) > reach:
			continue
		mn.x = minf(mn.x, p.x); mn.z = minf(mn.z, p.z)
		mx.x = maxf(mx.x, p.x); mx.z = maxf(mx.z, p.z)
	var center := Vector3((mn.x + mx.x) * 0.5, 0.0, (mn.z + mx.z) * 0.5)
	var half_x := (mx.x - mn.x) * 0.5 + CAM_BODY_RADIUS
	var half_z := (mx.z - mn.z) * 0.5 + CAM_BODY_RADIUS
	var span := maxf(half_x, half_z) * CAM_PADDING + CAM_HEADROOM + CAM_HEIGHT_ALLOWANCE
	span = clampf(span, CAM_MIN_SPAN, _cam_max_span)
	return {"center": center, "span": span}


## Places the camera at the CURRENT `_cam_center`/`_cam_span`, geometrically guaranteed to look
## exactly at `_cam_center` regardless of span: distance R is chosen so the span fills the FOV,
## then decomposed into height/depth by the fixed pitch, and `look_at` does the rest — no
## rotation-convention guesswork.
func _apply_camera_now() -> void:
	var theta := deg_to_rad(CAM_PITCH_DEG)
	var fov_half := deg_to_rad(camera.fov * 0.5)
	var r: float = _cam_span / tan(fov_half)
	var h: float = r * sin(theta)
	var d: float = r * cos(theta)
	camera.position = _cam_center + Vector3(0, h, d)
	camera.look_at(_cam_center, Vector3.UP)


func _update_camera(delta: float) -> void:
	if camera == null:
		return
	var target: Dictionary = _camera_target()
	var a := 1.0 - exp(-CAM_FOLLOW_RATE * delta)
	# The director asked for a CUT: land on the new shot this frame rather than sailing to it.
	if _cam_want_snap:
		_cam_want_snap = false
		a = 1.0
	_cam_center = _cam_center.lerp(target["center"], a)
	_cam_span = lerpf(_cam_span, target["span"], a)
	_apply_camera_now()
	# Camera punch: a small decaying offset AFTER positioning, so the follow logic never fights
	# it. Pseudo-random from playback time — render-only, the sim knows nothing of it.
	if _shake > 0.004:
		var tphase := frame_pos * 12.7
		camera.position += Vector3(sin(tphase * 1.13), sin(tphase * 0.71) * 0.6, cos(tphase * 1.31)) \
			* _shake * UNIT_HEIGHT * 0.18
		_shake *= exp(-9.0 * delta)


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# UNITS
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _build_units() -> void:
	nodes.clear()
	_build_shadow_multimesh()
	for i in range(all_units.size()):
		var m = all_units[i]
		var side := "A" if i < team_a.size() else "B"
		m.side = side
		var holder := Node3D.new()
		add_child(holder)
		var team_ring := _add_team_ring(holder, side)

		# ⚠️ THE RIGGED PATH IS TRIED FIRST, AND ITS ABSENCE IS NOT AN ERROR. The roster is 65
		# species and models arrive one at a time, so for most of this project's life MOST units
		# will fall through to the sprite below. `creature_rig.gd` presents the same
		# `setup`/`set_state`/`flinch` interface `creature_anim.gd` does, so everything downstream
		# — `_apply_frame`, the flinch on a landed shot, the death topple — drives either one
		# without knowing which it got.
		#
		# ⚠️ A rigged unit gets NO Sprite3D at all. Building both and hiding one would leave a
		# billboarded quad inside the holder that `_apply_frame` still writes to every tick, and
		# the first person to debug a facing bug would find two things claiming to be the body.
		var rig = CreatureRigScript.new()
		holder.add_child(rig)
		if rig.build(m.species_id, UNIT_HEIGHT):
			# The cast is the subject of the frame, so it gets its own lamp — see `CAST_LIGHT_LAYER`.
			_add_to_cast_layer(holder)
			var rplate := _make_plate(m, side, i)
			plates_root.add_child(rplate)
			nodes.append({
				"holder": holder, "sprite": null, "rig": rig, "plate": rplate, "anim": rig,
				"hp_fill": rplate.get_meta("hp_fill"), "hp_text": rplate.get_meta("hp_text"),
				"mp_fill": rplate.get_meta("mp_fill"), "mp_text": rplate.get_meta("mp_text"), "cast_bg": rplate.get_meta("cast_bg"),
				"cast_fill": rplate.get_meta("cast_fill"), "cast_lbl": rplate.get_meta("cast_lbl"), "cast_icon": rplate.get_meta("cast_icon"),
				"status_row": rplate.get_meta("status_row"), "intent_lbl": rplate.get_meta("intent_lbl"),
				"border": rplate.get_meta("border"), "last_rec": {}, "team_ring": team_ring,
				"head": rplate.get_meta("head"), "mp_bg": rplate.get_meta("mp_bg"),
				"status_strip": rplate.get_meta("status_strip"),
				"_status_sig": "", "_state_sig": "",
				"dead": false,
			})
			continue
		rig.queue_free()

		var spr := Sprite3D.new()
		var tex: Texture2D = Art.creature_texture(m.species_id)
		if tex != null:
			spr.texture = tex
			spr.pixel_size = UNIT_HEIGHT / float(tex.get_height())
		else:
			var ph := PlaceholderTexture2D.new()
			ph.size = Vector2(180, 380)
			spr.texture = ph
			spr.pixel_size = UNIT_HEIGHT / 380.0
			# ⚠️ `Art.team_identity(...)["colour"]`, not `Art.team_colour(...)` alone
			# (`docs/ACCESSIBILITY.md` §2, `arena_3d.gd:316` finding) — future-proofed so this
			# fallback tint is never the ONLY team tell if nameplates are ever made toggleable.
			spr.modulate = Art.team_identity(0 if side == "A" else 1)["colour"]
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		spr.shaded = false
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		spr.flip_h = (side == "B")
		spr.position = Vector3(0, UNIT_HEIGHT * 0.5, 0)
		holder.add_child(spr)

		# ⚠️ PROCEDURAL ANIMATION — see docs/MESHY_SPIKE_RESULT.md. Meshy's auto-rig is
		# HUMANOID-ONLY (it refused an avian with `422 Pose estimation failed`), and the roster is
		# 65 species across 13 body types, so skeletal animation cannot cover it. This poses the
		# whole body from the frame stream's own `state`/`facing` and works identically for every
		# body — including the ones no rig will ever fit.
		#
		# ⚠️ Drives the SPRITE, not the holder. The holder carries the unit's world POSITION,
		# which `_apply_frame` writes every tick from the sim; animating it would fight the sim
		# for the same transform and the unit would visibly stutter.
		var anim = CreatureAnimScript.new()
		holder.add_child(anim)
		anim.setup(spr)
		# ⚠️ Harmless-but-deliberate on this path: a `Sprite3D` here is `shaded = false`, so no lamp
		# reaches it at all and the cast light changes nothing. Set anyway, because the day a
		# painted sprite is made shaded it must light like the rigged units do, not stay a flat
		# cut-out among lit bodies.
		_add_to_cast_layer(holder)

		var plate := _make_plate(m, side, i)
		plates_root.add_child(plate)
		nodes.append({
			"holder": holder, "sprite": spr, "plate": plate, "anim": anim,
			"hp_fill": plate.get_meta("hp_fill"), "hp_text": plate.get_meta("hp_text"),
			"mp_fill": plate.get_meta("mp_fill"), "mp_text": plate.get_meta("mp_text"), "cast_bg": plate.get_meta("cast_bg"),
			"cast_fill": plate.get_meta("cast_fill"), "cast_lbl": plate.get_meta("cast_lbl"), "cast_icon": plate.get_meta("cast_icon"),
			"status_row": plate.get_meta("status_row"), "intent_lbl": plate.get_meta("intent_lbl"),
			"border": plate.get_meta("border"), "last_rec": {}, "team_ring": team_ring,
			"head": plate.get_meta("head"), "mp_bg": plate.get_meta("mp_bg"),
			"status_strip": plate.get_meta("status_strip"),
			"_status_sig": "", "_state_sig": "",
			"dead": false,
		})


## ⚠️ THE TEAM TELL MUST BE ON THE BODY. This is the finding from looking at a real scrum capture
## (`watch_four_pillar_t35_cam0_06_t012.0.png`): eight overlapping creatures of eight different
## species colours, and NOTHING on any of them said which side it was on. The only team channel
## in the fight was the badge on a nameplate, and nameplates are 52-69% orphaned from the head
## they annotate and collide 1.8-4.1 times a frame — so in exactly the ten seconds that decide
## the match, the team channel is gone.
##
## A ring on the ground under the feet cannot be orphaned, cannot collide, cannot be lifted, and
## survives every camera distance including ARENA mode. It is a CHILD OF THE HOLDER, so it tracks
## the unit for free and there is no second place that has to remember to move it.
##
## ⚠️ Guild Colours rule: this is `Art.team_identity()`, the same swatch every other screen uses
## for "whose is this" — never a new palette, and never the channel colours, which mean something
## else entirely (`docs/ART_THEME.md`: three colour systems that must never collide).
func _add_team_ring(holder: Node3D, side: String) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.92
	tor.outer_radius = 1.42
	tor.rings = 24
	tor.ring_segments = 6
	ring.mesh = tor
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var col: Color = Art.team_identity(0 if side == "A" else 1)["colour"]
	# ⚠️ THE FIRST ATTEMPT LERPED 42% TO WHITE AND BOTH SIDES READ AS THE SAME PALE RING at
	# fight distance — the livery colours (slate blue / oxblood) are deliberately muted, and
	# desaturating them further to survive a dark floor destroyed the only thing the ring is for.
	# The value lift now comes from raising the colour's own VALUE, keeping its hue and saturation
	# intact, so blue stays blue and oxblood stays red.
	var hsv := Color.from_hsv(col.h, maxf(col.s, 0.62), maxf(col.v, 0.86))
	mat.albedo_color = Color(hsv.r, hsv.g, hsv.b, 0.95)
	ring.material_override = mat
	ring.position = Vector3(0, 0.06, 0)
	ring.scale = Vector3(1.0, 0.35, 1.0)   # flattened: a ring on the floor, not a tyre
	holder.add_child(ring)
	return ring


## One MultiMeshInstance3D for every unit's ground shadow, per-instance COLOUR (not just
## transform) so a fallen unit's shadow dims along with its plate — `MultiMesh.use_colors`
## requires the material's `vertex_color_use_as_albedo` to actually read it.
func _build_shadow_multimesh() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(1.9, 1.2)
	var mat := StandardMaterial3D.new()
	var grad := GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.55))
	g.set_color(1, Color(0, 0, 0, 0.0))
	grad.gradient = g
	grad.width = 64; grad.height = 64
	mat.albedo_texture = grad
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.vertex_color_use_as_albedo = true

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = q
	mm.instance_count = maxi(1, all_units.size())
	var flat_xf := Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(-90)), Vector3(0, 0.03, 0))
	for i in range(mm.instance_count):
		mm.set_instance_transform(i, flat_xf)
		mm.set_instance_color(i, Color(1, 1, 1, 1))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	shadow_mm = mm


## Team + badge + border + name/HP/status. Bigger text than the earlier pass on purpose —
## `docs/ACCESSIBILITY.md` §5/§8 flags 9px/8px as roughly HALF the 18px floor and asks for the fix
## BEFORE density gets worse, not after.
func _make_plate(m, side: String, idx: int) -> Control:
	var ident: Dictionary = Art.team_identity(0 if side == "A" else 1)
	# ⚠️ FULLY FRAMELESS (user direction 2026-08-06): every text element now carries its own
	# black outline, so the plate needs no card at all — the UI floats on the scene. The team
	# identity tell moves from the border to the badge glyph (kept, a11y load-bearing) and the
	# team-coloured HP bar edge below.
	var plate_bg := Color(0.085, 0.07, 0.055, 0.0)
	var border_col := _accessible_border(ident["colour"], plate_bg)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = plate_bg
	sb.border_color = border_col
	sb.set_border_width_all(0)   # frameless — the badge glyph and bar edge carry team identity
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 4; sb.content_margin_right = 4
	sb.content_margin_top = 2; sb.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", sb)
	# ⚠️ SIZED FOR THE PULLED-BACK CAMERA (2026-08-05). Plates are SCREEN-SPACE, so when the camera
	# moved from 58deg/40fov to 38deg/26fov the units shrank and the plates did not — five of them
	# stacked into an unreadable wall across the top of the frame, hiding the fight they annotate.
	# 148 -> 104 wide with smaller type.
	#
	# ⚠️ AND 104 WAS STILL TOO WIDE ONCE THE BOARD TRIPLED. The ground went 160x88 -> 352x194 and
	# the units spread properly, so the fight now occupies a QUARTER of the frame while ten plates
	# at 104px occupied most of the rest — the annotation was larger than the thing annotated.
	# 104 -> 82. ⚠️ THIS IS THE FLOOR: `docs/ACCESSIBILITY.md` sets the minimum readable type and
	# the 11px name below is at it. Any further reduction has to come from showing FEWER plates,
	# not smaller ones — which is what the quiet-unit fade below does instead.
	panel.custom_minimum_size = Vector2(82, 0)
	# Tier-2 disclosure — clicking a plate opens ITS callout (only one open at a time). Real
	# `Control` input, not a paint-only panel, so it is Tab/Enter reachable too (`_unhandled_input`
	# below handles the keyboard path per `docs/UX_LEGIBILITY.md` §10 / `docs/ACCESSIBILITY.md` #1).
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.gui_input.connect(func(ev): _on_plate_input(ev, idx))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)

	# ── PLATER GRAMMAR (user direction 2026-08-06, after WoW's Plater addon): a compact dark
	# plate — tiny name, slim health bar with % inside, hair-thin mana bar, and a CAST BAR below
	# that appears only while casting, carrying the ability name (icons join it when the ability
	# icon set exists). The innate line and large chips are gone: minimalist is the spec, and the
	# innate is still one Tab away on the orders panel.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 3)
	col.add_child(head)
	var nm := Label.new()
	nm.text = "%s %s" % [ident["badge"], m.species_name]
	nm.add_theme_font_size_override("font_size", 18)
	nm.add_theme_color_override("font_color", Color(0.96, 0.96, 0.98))
	nm.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	nm.add_theme_constant_override("outline_size", 4)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nm)
	var intent_lbl := Label.new()
	intent_lbl.text = ""
	intent_lbl.add_theme_font_size_override("font_size", 18)
	intent_lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.92))
	intent_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	intent_lbl.add_theme_constant_override("outline_size", 4)
	head.add_child(intent_lbl)

	# The team RULE: with the border gone, this slim line under the name carries the team
	# COLOUR (the badge glyph carries the non-colour tell — both survive framelessness).
	var team_rule := ColorRect.new()
	team_rule.color = border_col
	team_rule.custom_minimum_size = Vector2(176, 3)
	col.add_child(team_rule)

	# bars live in one column so the death-hide collapses all of them together
	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 1)
	col.add_child(bars)

	# ⚠️ TRUE BARS (user direction 2026-08-06): the troughs were PanelContainers, and containers
	# STRETCH children — the fill fought the layout instead of being a clean fraction of a fixed
	# trough. Each bar is now a plain Control (fixed size, no layout opinions) holding a
	# semi-transparent background and a left-anchored fill whose width IS the fraction:
	# full [==========] · half [=====/////] — the empty remainder always visible.
	var bar_bg := Control.new()
	bar_bg.custom_minimum_size = Vector2(176, 20)
	bars.add_child(bar_bg)
	var hp_trough := ColorRect.new()
	hp_trough.color = Color(0.05, 0.04, 0.03, 0.08)   # user-tuned 2026-08-06 (round 2): a ghost of a trough
	hp_trough.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_bg.add_child(hp_trough)
	var fill := ColorRect.new()
	fill.color = Color(0.32, 0.76, 0.36)
	fill.position = Vector2(1, 1)
	fill.size = Vector2(174, 18)
	bar_bg.add_child(fill)
	var hp_text := Label.new()
	hp_text.text = ""
	hp_text.add_theme_font_size_override("font_size", 16)
	hp_text.add_theme_color_override("font_color", Color(1, 1, 1))
	# ⚠️ The outline is what makes the number readable — white on mid-green fails contrast at ANY
	# size; a 3px black outline reads over every fill colour and every HP state.
	hp_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hp_text.add_theme_constant_override("outline_size", 3)
	hp_text.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	hp_text.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hp_text.position = Vector2(-4, 0)
	bar_bg.add_child(hp_text)

	# mana: hair-thin, the caster's second resource always visible
	var mp_bg := Control.new()
	mp_bg.custom_minimum_size = Vector2(176, 12)
	bars.add_child(mp_bg)
	var mp_trough := ColorRect.new()
	mp_trough.color = Color(0.04, 0.05, 0.08, 0.08)
	mp_trough.set_anchors_preset(Control.PRESET_FULL_RECT)
	mp_bg.add_child(mp_trough)
	var mp_fill := ColorRect.new()
	mp_fill.color = Color(0.35, 0.55, 0.92)
	mp_fill.position = Vector2(1, 1)
	mp_fill.size = Vector2(174, 10)
	mp_bg.add_child(mp_fill)
	# ⚠️ The mana bar was 6px, colour-only, no text — the exact failure the HP bar had before its
	# fix, left on the sibling bar (accessibility audit #1). Same treatment: outlined % inside.
	var mp_text := Label.new()
	mp_text.text = ""
	mp_text.add_theme_font_size_override("font_size", 11)
	mp_text.add_theme_color_override("font_color", Color(1, 1, 1))
	mp_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	mp_text.add_theme_constant_override("outline_size", 3)
	mp_text.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	mp_text.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	mp_text.position = Vector2(-4, 0)
	mp_bg.add_child(mp_text)

	# ── the STATUS strip (user direction): a reserved slim slot between the resource bars and
	# the cast bar. It NEVER disappears — an always-present strip means statuses appear in a
	# stable place instead of reflowing the plate, which is what makes them scannable mid-fight.
	var status_strip := PanelContainer.new()
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0.04, 0.04, 0.05, 0.15)   # the status strip joins the transparency pass
	ssb.content_margin_left = 1; ssb.content_margin_right = 1
	ssb.content_margin_top = 0; ssb.content_margin_bottom = 0
	status_strip.add_theme_stylebox_override("panel", ssb)
	status_strip.custom_minimum_size = Vector2(176, 17)
	bars.add_child(status_strip)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 2)
	status_strip.add_child(status_row)

	# cast bar BELOW the statuses (user direction); fills with castFrac, names the ability
	var cast_bg := Control.new()
	cast_bg.custom_minimum_size = Vector2(176, 19)
	cast_bg.visible = false
	bars.add_child(cast_bg)
	var cast_trough := ColorRect.new()
	cast_trough.color = Color(0.06, 0.04, 0.02, 0.08)
	cast_trough.set_anchors_preset(Control.PRESET_FULL_RECT)
	cast_bg.add_child(cast_trough)
	var cast_fill := ColorRect.new()
	cast_fill.color = Color(0.95, 0.68, 0.25)
	cast_fill.position = Vector2(1, 1)
	cast_fill.size = Vector2(0, 17)
	cast_bg.add_child(cast_fill)
	# The ability ICON — the slot this bar has carried since the Plater rework, now filled by
	# the generated 141-icon set (line glyph + stat tint + type badge).
	var cast_icon := TextureRect.new()
	cast_icon.custom_minimum_size = Vector2(19, 19)
	cast_icon.position = Vector2(1, 0)
	cast_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cast_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cast_bg.add_child(cast_icon)
	var cast_lbl := Label.new()
	cast_lbl.text = ""
	cast_lbl.add_theme_font_size_override("font_size", 16)
	cast_lbl.add_theme_color_override("font_color", Color(0.98, 0.94, 0.85))
	cast_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	cast_lbl.add_theme_constant_override("outline_size", 3)
	cast_lbl.position = Vector2(23, -1)
	cast_bg.add_child(cast_lbl)

	panel.set_meta("hp_fill", fill)
	panel.set_meta("hp_text", hp_text)
	panel.set_meta("mp_fill", mp_fill)
	panel.set_meta("mp_text", mp_text)
	panel.set_meta("cast_bg", cast_bg)
	panel.set_meta("cast_fill", cast_fill)
	panel.set_meta("cast_lbl", cast_lbl)
	panel.set_meta("cast_icon", cast_icon)
	panel.set_meta("status_row", status_row)
	panel.set_meta("intent_lbl", intent_lbl)
	# The rows a QUIET unit's plate collapses (see `_update_plates`' two-tier pass). Kept as metas
	# so the tier logic never has to know the plate's node layout.
	panel.set_meta("head", head)
	panel.set_meta("mp_bg", mp_bg)
	panel.set_meta("status_strip", status_strip)
	panel.set_meta("border", sb)
	return panel


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# ACCESSIBILITY HELPERS — WCAG relative luminance / contrast, used only to keep team borders off
# the colour-alone floor (`docs/ACCESSIBILITY.md` §3 finding #6: iron-grey measured 2.60:1,
# below the 3:1 non-text floor; #9: three more pass with effectively no margin). Computed locally
# rather than editing `art.gd`'s `TEAM_COLOURS` — that table is not owned by this file/stream.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _srgb_to_linear(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


func _relative_luminance(c: Color) -> float:
	return 0.2126 * _srgb_to_linear(c.r) + 0.7152 * _srgb_to_linear(c.g) + 0.0722 * _srgb_to_linear(c.b)


func _contrast_ratio(a: Color, b: Color) -> float:
	var la := _relative_luminance(a) + 0.05
	var lb := _relative_luminance(b) + 0.05
	return maxf(la, lb) / minf(la, lb)


## Lightens `c` toward white just enough to clear a 3.5:1 margin against `bg` (WCAG's own floor is
## 3:1 for non-text UI — the extra 0.5 is the buffer `docs/ACCESSIBILITY.md` §3 asks for so a
## palette/blend-mode change doesn't tip a border back under the line). A colour that already
## clears the margin is returned unchanged.
func _accessible_border(c: Color, bg: Color) -> Color:
	var out := c
	var tries := 0
	while _contrast_ratio(out, bg) < 3.5 and tries < 30:
		out = out.lerp(Color(1, 1, 1), 0.08)
		tries += 1
	return out


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# TIER-2 DISCLOSURE — one unit's callout, click or Tab to open. `docs/UX_LEGIBILITY.md` §6 Tier 2
# / §11 item 1 ("the cheap interim slice, buildable now"): the Orders Summary (ORDER vs NATURE,
# using tactics.gd's own *_INFO copy verbatim — never a paraphrase) plus, when the sim populates
# them, the live `intent`/`reason` sentence.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _on_plate_input(ev: InputEvent, idx: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		_select_unit(-1 if selected_idx == idx else idx)


func _select_unit(idx: int) -> void:
	selected_idx = idx
	for k in range(nodes.size()):
		var sb2: StyleBoxFlat = nodes[k]["border"]
		sb2.set_border_width_all(4 if k == idx else 2)
	if idx < 0:
		callout.visible = false
		return
	_refresh_callout(idx)
	callout.visible = true


func _refresh_callout(idx: int) -> void:
	if idx < 0 or idx >= all_units.size():
		return
	var m = all_units[idx]
	var rec: Dictionary = nodes[idx].get("last_rec", {})
	var ident: Dictionary = Art.team_identity(0 if m.side == "A" else 1)
	callout_title.text = "%s %s" % [ident["badge"], m.species_name]

	var lines: Array = []
	var hp_i := int(round(float(rec.get("hp", m.hp))))
	var mp_i := int(round(float(rec.get("mp", m.mp))))
	lines.append("HP %d / %d   MP %d / %d" % [hp_i, m.max_hp, mp_i, m.max_mp])

	var intent: String = str(rec.get("intent", ""))
	var reason: String = str(rec.get("reason", ""))
	lines.append("")
	if intent != "" or reason != "":
		if intent != "":
			lines.append(intent)
		if reason != "":
			lines.append(reason)
	else:
		# ⚠️ Honest about the gap rather than inventing a sentence — this sim build does not
		# populate `intent`/`reason` yet (`docs/BUILD_CONTRACT.md` §2, stream A mid-rewrite).
		lines.append("This build's simulation doesn't report a live intent yet.")

	lines.append("")
	lines.append("[b]Standing orders[/b]")
	for row in _orders_summary(m):
		lines.append("%s %s — %s" % [row["icon"], row["name"], row["tag"]])

	callout_body.text = "\n".join(lines)


## Reuses `tactics.gd`'s own *_INFO tables verbatim (`docs/UX_LEGIBILITY.md` §1 rule 1: "the
## vocabulary is not invented twice") to tag each axis ORDER (explicitly set, team plan or
## per-monster override) or ITS NATURE (absent, engine default) — exactly the distinction
## `tactics.gd`'s own doc comment says the data already supports.
func _orders_summary(m) -> Array:
	var committed: Dictionary = TacticsScript.committed
	var plan: Dictionary = committed.get("planA" if m.side == "A" else "planB", {})
	var orders: Dictionary = committed.get("ordersA" if m.side == "A" else "ordersB", {})
	var own: Dictionary = orders.get(m, {})
	var merged: Dictionary = plan.duplicate()
	for k in own:
		merged[k] = own[k]

	var out: Array = []

	var tp_has: bool = merged.has("targetPriority") and str(merged.get("targetPriority", "")) != ""
	var tp_info: Dictionary = TacticsScript.info_by_id(TacticsScript.TARGET_PRIORITY_INFO, merged.get("targetPriority", ""))
	if tp_info.is_empty():
		tp_info = TacticsScript.TARGET_PRIORITY_INFO[0]
	out.append({"icon": tp_info.get("icon", ""), "name": tp_info.get("name", ""), "tag": "your order" if tp_has else "its nature"})

	var temp_has: bool = own.has("temperament")
	var temp_val: String = str(merged.get("temperament", "balanced"))
	if temp_val == "":
		temp_val = "balanced"
	var temp_info: Dictionary = TacticsScript.info_by_id(TacticsScript.TEMPERAMENT_INFO, temp_val)
	out.append({"icon": temp_info.get("icon", ""), "name": temp_info.get("name", ""), "tag": "your order" if temp_has else "its nature"})

	var mana_has: bool = merged.has("manaPolicy")
	var mana_val: String = str(merged.get("manaPolicy", "normal"))
	if mana_val == "":
		mana_val = "normal"
	var mana_info: Dictionary = TacticsScript.info_by_id(TacticsScript.MANA_POLICY_INFO, mana_val)
	out.append({"icon": mana_info.get("icon", ""), "name": mana_info.get("name", ""), "tag": "your order" if mana_has else "its nature"})

	return out


func _unhandled_input(event: InputEvent) -> void:
	# ── FREE camera: hold LMB and drag to pan, wheel to zoom. First touch captures the current
	# framing so the hand-off is seamless; C returns to the auto modes. ──
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_panning = event.pressed
			if event.pressed and _cam_mode != CamMode.FREE:
				_free_center = _cam_center
				_free_span = _cam_span
				_cam_mode = CamMode.FREE
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if _cam_mode != CamMode.FREE:
				_free_center = _cam_center
				_free_span = _cam_span
				_cam_mode = CamMode.FREE
			var zf := 0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.14
			_free_span = clampf(_free_span * zf, CAM_MIN_SPAN * 0.6, _cam_max_span * 1.2)
	elif event is InputEventMouseMotion and _panning and _cam_mode == CamMode.FREE:
		# Screen-space drag → ground-plane pan, scaled so a full-height drag crosses ~two spans.
		var vp_h: float = maxf(1.0, get_viewport().get_visible_rect().size.y)
		var k_pan: float = _free_span * 2.0 / vp_h
		var right: Vector3 = camera.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		var fwd: Vector3 = -camera.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		_free_center += (-right * event.relative.x + fwd * event.relative.y) * k_pan
		var half_w: float = ground_size.x * WORLD_SCALE * 0.6
		var half_d: float = ground_size.y * WORLD_SCALE * 0.6
		_free_center.x = clampf(_free_center.x, -half_w, half_w)
		_free_center.z = clampf(_free_center.z, -half_d, half_d)

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_cycle_selection(event.shift_pressed)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and selected_idx >= 0:
			_select_unit(-1)
			get_viewport().set_input_as_handled()
		# ⚠️ BOTH CAMERAS, BECAUSE NEITHER ONE IS RIGHT ON ITS OWN AND THAT IS MEASURED. The
		# whole-arena shot holds every unit in frame but puts a body at ~4% of frame height; the
		# follow shot reads a body at ~12-13% but loses the flanks. "See the whole fight" and "see
		# the creatures" are in genuine tension at 5v5 and one span cannot serve both, so this is a
		# key rather than a constant somebody has to pick.
		elif event.keycode == KEY_C:
			# Cycle ACTION → TEAM → ARENA → ACTION; from FREE, C returns home to ACTION.
			match _cam_mode:
				CamMode.ACTION: _cam_mode = CamMode.TEAM
				CamMode.TEAM: _cam_mode = CamMode.ARENA
				_: _cam_mode = CamMode.ACTION
			get_viewport().set_input_as_handled()
		# Slow the replay down to watch a specific exchange, or speed through the approach.
		elif event.keycode == KEY_BRACKETLEFT:
			speed = maxf(0.25, speed - 0.25)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_BRACKETRIGHT:
			speed = minf(4.0, speed + 0.25)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE:
			speed = 0.0 if speed > 0.0 else 1.0
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_LEFT:
			_seek(frame_pos * NewSim.DT - 3.0)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_RIGHT:
			_seek(frame_pos * NewSim.DT + 3.0)
			get_viewport().set_input_as_handled()


func _cycle_selection(reverse: bool) -> void:
	if nodes.is_empty():
		return
	var n := nodes.size()
	var start := selected_idx
	var step := -1 if reverse else 1
	for _i in range(n):
		start = (start + step + n) % n
		if start < all_units.size() and _alive_now(start):
			_select_unit(start)
			return


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# PLAYBACK — interpolate the frame stream
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## Every per-frame watch surface in one call. ⚠️ The squad HUD used to be updated ONLY on the
## active-playback path, so it was stale through the opening hold, stale while paused, and stale
## on the final frame — the three moments a viewer is most likely to actually be reading it.
func _update_watch_surfaces() -> void:
	if scrub != null and not frames.is_empty():
		scrub.max_value = float(frames.size() - 1) * NewSim.DT
		# `set_value_no_signal` — writing the playhead back into the slider must not be mistaken
		# for the player dragging it, or every frame would trigger a seek.
		scrub.set_value_no_signal(frame_pos * NewSim.DT)
	_update_plates()
	_update_standing_hud()
	_update_offscreen_pips()
	_update_tethers()
	_sync_audio_transport()


func _process(delta: float) -> void:
	if not playing:
		_update_watch_surfaces()
		_update_camera(delta)
		return
	# ⚠️ Check for a frame stream BEFORE the opening hold, not after. The hold path called
	# `_apply_frame(0.0)`, which indexes `frames[0]` — so with the non-spatial fallback (no frame
	# stream at all) it crashed on the very first frame, before the guard below could catch it.
	if frames.is_empty():
		# Non-spatial fallback: no positions to replay. Units stay on their deploy marks and only
		# the log advances, which is honest about what this engine does and does not know.
		_drain_log(event_log.size())
		playing = false
		_finish()
		return

	opening_timer += delta * speed
	if opening_timer < OPENING_HOLD:
		_apply_frame(0.0)
		_update_watch_surfaces()
		_update_camera(delta)
		return

	_update_innate_tells()
	# Frames are one simulation tick apart, so advancing at `1 / DT` frames per second replays the
	# fight at true speed. ⚠️ Interpolating BETWEEN frames is what makes 10 Hz simulation look
	# smooth without the renderer inventing any motion of its own.
	# Hit-stop: _feel_slow dips on big hits and recovers in ~0.15s. It multiplies the PLAYBACK,
	# not `speed` — the user's chosen speed is never overwritten, the moment just lands heavier.
	_feel_slow = lerpf(_feel_slow, 1.0, 1.0 - exp(-14.0 * delta))
	frame_pos += delta * speed * 10.0 * _feel_slow
	if frame_pos >= float(frames.size() - 1):
		frame_pos = float(frames.size() - 1)
		_apply_frame(frame_pos)
		_drain_log(event_log.size())
		playing = false
		_finish()
		_update_watch_surfaces()
		_update_camera(delta)
		return
	_apply_frame(frame_pos)
	_update_watch_surfaces()
	_update_camera(delta)


func _apply_frame(fpos: float) -> void:
	var i := int(floor(fpos))
	var j: int = mini(i + 1, frames.size() - 1)
	var t: float = fpos - float(i)
	var fa: Dictionary = frames[i]
	var fb: Dictionary = frames[j]
	var ua: Array = fa.get("units", [])
	var ub: Array = fb.get("units", [])

	# Transition-only ticker entries (`docs/UX_LEGIBILITY.md` §1 rule 2) — checked once per NEW
	# discrete tick, never once per interpolated sub-frame, so a fast playback speed can't spam it.
	var new_tick: bool = i != _seen_tick
	if new_tick:
		_seen_tick = i
		_check_intent_transitions(fa)

	for k in range(mini(nodes.size(), ua.size())):
		var rec: Dictionary = ua[k]
		var rec_b: Dictionary = ub[k] if k < ub.size() else rec
		var nd: Dictionary = nodes[k]
		nd["last_rec"] = rec
		var pa: Vector2 = rec.get("pos", Vector2.ZERO)
		var pb: Vector2 = rec_b.get("pos", pa)
		var world := _to_world(pa.lerp(pb, t))
		(nd["holder"] as Node3D).position = world

		var alive: bool = bool(rec.get("alive", true))
		if not alive and not nd["dead"]:
			_topple(k)
		# ⚠️ A dead unit keeps its NAME but loses its bar. An empty red trough sitting over a corpse
		# reads as "still fighting, nearly gone" — the opposite of what happened — and it competes
		# for attention with the units still alive, which is the whole point of plate declutter.
		# ⚠️ A dead monster loses its WHOLE plate (user call, 2026-08-06 — this hid only the HP row
		# at first). A corpse does not need a name tag: the plate exists to carry live reads
		# (HP, statuses, intent), and ten plates over five corpses is exactly the clutter the
		# declutter pass exists to prevent. The body + topple still say who fell, and the log
		# keeps the record.
		if not alive:
			(nd["plate"] as Control).visible = false
		# ⚠️ A CORPSE'S TEAM RING DIMS BUT DOES NOT VANISH. The bodies stay on the field, so where
		# a side LOST its monsters is a real spatial fact a viewer can read off the floor — which
		# flank collapsed, whether the line held. At full brightness it competed with the living;
		# gone entirely it would take that read away.
		var tr = nd.get("team_ring")
		if tr != null and is_instance_valid(tr):
			var trm: StandardMaterial3D = (tr as MeshInstance3D).material_override
			if trm != null:
				trm.albedo_color.a = 0.95 if alive else 0.30

		if shadow_mm != null and k < shadow_mm.instance_count:
			shadow_mm.set_instance_transform(k, Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(-90)), world + Vector3(0, 0.03, 0)))
			shadow_mm.set_instance_color(k, Color(1, 1, 1, 0.35 if not alive else 1.0))

		var m = all_units[k]
		var hp: float = float(rec.get("hp", m.hp))
		var frac: float = 0.0 if m.max_hp <= 0 else clampf(hp / float(m.max_hp), 0.0, 1.0)
		var fill: ColorRect = nd["hp_fill"]
		fill.size = Vector2(174.0 * frac, 18)
		# mana — the hair-thin second bar (Plater grammar)
		var mfrac: float = 0.0 if m.max_mp <= 0 else clampf(float(rec.get("mp", 0.0)) / float(m.max_mp), 0.0, 1.0)
		(nd["mp_fill"] as ColorRect).size = Vector2(174.0 * mfrac, 10)
		(nd["mp_text"] as Label).text = "%d%%" % int(round(mfrac * 100.0))
		# cast bar — visible only while the sim says cast, filling with the windup
		var casting_b: bool = str(rec.get("state", "")) == "cast" and alive
		var flashing: bool = Time.get_ticks_msec() < int(nd.get("cast_flash_until", 0))
		(nd["cast_bg"] as Control).visible = casting_b or (flashing and alive)
		if casting_b:
			(nd["cast_fill"] as ColorRect).color = Color(0.95, 0.68, 0.25)   # restore after any flash
			# ⚠️ The bar MOVES with the cast (user direction): castFrac is lerped between the same
			# two frames positions interpolate between, so it glides at render rate instead of
			# stepping at the sim's 10Hz.
			var cf_a: float = float(rec.get("castFrac", 0.0))
			var cf_b: float = float(rec_b.get("castFrac", cf_a)) if str(rec_b.get("state", "")) == "cast" else cf_a
			(nd["cast_fill"] as ColorRect).size = Vector2(174.0 * clampf(lerpf(cf_a, cf_b, t), 0.0, 1.0), 17)
			(nd["cast_lbl"] as Label).text = str(rec.get("castMove", ""))
			var icon_mv: Dictionary = _move_by_name.get(str(rec.get("castMove", "")), {})
			var icon_path: String = "res://assets/icons/abilities/%s.png" % str(icon_mv.get("id", ""))
			(nd["cast_icon"] as TextureRect).texture = load(icon_path) if icon_mv.has("id") and ResourceLoader.exists(icon_path) else null
		if frac < 0.25:
			fill.color = Color(0.87, 0.24, 0.24)
		elif frac < 0.5:
			fill.color = Color(0.88, 0.70, 0.25)
		else:
			fill.color = Color(0.32, 0.76, 0.36)
		var hp_text: Label = nd["hp_text"]
		hp_text.text = "%d%%" % int(round(frac * 100.0))

		# Weary rides the status row as a pseudo-status — the care loop must be READABLE.
		var row_statuses: Array = (rec.get("statuses", []) as Array).duplicate()
		if bool(rec.get("weary", false)):
			row_statuses.append("weary")
		_sync_status_row(nd, row_statuses)
		_sync_intent_glyph(nd, str(rec.get("state", "idle")))

		# ⚠️ Feed the procedural animator the sim's OWN state and facing. The renderer derives
		# nothing here (docs/BUILD_CONTRACT.md §2) — both fields are already in the frame.
		# Cast telegraph: a rising channel-coloured glow while (and only while) the sim says this
		# unit is casting — the windup the interrupt game is played against, visible at any zoom.
		if vfx != null:
			var casting_now: bool = str(rec.get("state", "")) == "cast" and alive
			# ── AoE TELEGRAPH: while an allEnemies move winds up, its ACTUAL area sits on the
			# ground as a ring around the caster — the WoW grammar: you see the circle, you know
			# what is coming, and repositioning out of it is real counterplay the eye can verify.
			# Radius is the move's own authored reach (the same number the fan-out now enforces),
			# so the ring never lies about what it will hit. ──
			var tele_mv: Dictionary = _move_by_name.get(str(rec.get("castMove", "")), {})
			if casting_now and str(tele_mv.get("target", "")) == "allEnemies":
				_show_aoe_ring(k, Sp.reach_of(tele_mv, false), str(tele_mv.get("channel", "magic")))
			else:
				_hide_aoe_ring(k)
			if casting_now and not bool(nd.get("_was_casting", false)):
				# Cast START: one charge-ring play-through — the moment the windup begins is the
				# moment the interrupt window opens, and it deserves a beat of its own.
				vfx.flip((nd["holder"] as Node3D).position + Vector3(0, UNIT_HEIGHT * 0.5, 0),
					"charge", 5.0, Color(0.85, 0.70, 1.0), 0.5)
			nd["_was_casting"] = casting_now
			if casting_now:
				# ⚠️ CHANNEL-TRUE (UI team 2026-08-06): this hardcoded magic-violet for EVERY
				# caster — a melee windup telegraphed as a spell. Colour is a promise the player
				# banks reads on; the glow now speaks the casting move's own channel. Neutral
				# grey-white when the move is unknown (basics) — never a wrong colour.
				var glow_mv: Dictionary = _move_by_name.get(str(rec.get("castMove", "")), {})
				var glow_col: Color = vfx.CHANNEL_COLOUR.get(str(glow_mv.get("channel", "")), Color(0.85, 0.85, 0.9))
				vfx.cast_glow(k, nd["holder"], glow_col)
			else:
				vfx.end_cast_glow(k)

		var anim = nd.get("anim")
		if anim != null:
			var f = rec.get("facing", Vector2(0, 1))
			var md = rec.get("moveDir", Vector2.ZERO)
			anim.set_state(str(rec.get("state", "idle")), f if f is Vector2 else Vector2(0, 1),
				md if md is Vector2 else Vector2.ZERO)

	# ⚠️⚠️ ONCE PER SIM TICK, NOT ONCE PER RENDERED FRAME. This loop had no tick gate, and
	# `_apply_frame` runs every `_process`: at 1x speed `frame_pos` advances 0.167 frames per
	# render frame, so `frames[i]` stayed current for ~6 render frames and EVERY SHOT WAS
	# PRESENTED SIX TIMES — six bursts, six tracers, six camera punches and six damage floats for
	# one hit (24 at 0.25x, where the player has deliberately slowed down to read it). That is the
	# single largest cause of the unreadable scrum in `docs/WATCH_AUDIT.md` §0: the eight identical
	# `10`s over eight overlapping bodies were never eight hits. The fan-out in `_float_text`,
	# added to separate simultaneous hits, was faithfully fanning out duplicates of one hit.
	#
	# ⚠️ AND THE GATE MUST STAY EVEN IF THE SHOT ART CHANGES. Anything one-shot — a burst, a float,
	# a punch, a sound — belongs inside it. Anything continuous (positions, bars, glows) belongs
	# outside, driven by the interpolation, as it already is above.
	if new_tick:
		# ⚠️ ONE NUMBER PER VICTIM PER TICK. Three hits landing on one body in the same tick used
		# to stack three floats; the tick now sums them, so the number on a body is what that body
		# lost this beat. The individual attributions are still in the log and in the tracers.
		var dmg_by_victim: Dictionary = {}
		for shot in fa.get("shots", []):
			_draw_shot(shot, dmg_by_victim)
			# A landed hit shakes its VICTIM — the exchange reads as two-sided rather than one
			# unit lunging into empty air.
			if bool(shot.get("hit", false)):
				var vid := int(shot.get("toId", -1))
				if vid >= 0 and vid < nodes.size():
					var va = nodes[vid].get("anim")
					if va != null:
						va.flinch()
					# The director's memory of who is under fire (`_cam_interest`), and the
					# squad-level focus read (`_update_focus_read`).
					_hit_at[vid] = _play_t()
					_recent_hits.append({"t": _play_t(), "from": int(shot.get("fromId", -1)),
						"to": vid})
		_flush_damage_floats(dmg_by_victim)
		# ⚠️ AUDIO FIRES HERE AND NOWHERE ELSE — inside the tick gate, for the same reason the
		# bursts and floats do. Outside it, every cue would play ~6 times at 1x and ~24 at 0.25x:
		# the six-times bug this gate was built to remove, reintroduced in the audio layer.
		_play_tick_audio(fa)

	_sync_projectiles(fa, fb, t)

	# Keep the text log in step with the frame we're showing.
	var now_t: float = float(fa.get("t", 0.0))
	var upto := logged_upto
	while upto < event_log.size() and float(event_log[upto].get("t", 0.0)) <= now_t:
		upto += 1
	_drain_log(upto)

	if selected_idx >= 0:
		_refresh_callout(selected_idx)


## Rebuilds a unit's status-chip row only when the status list actually changed (cheap signature
## check) — avoids destroying/recreating `Control` children every tick for a unit whose statuses
## haven't moved, which is the common case.
func _sync_status_row(nd: Dictionary, statuses: Array) -> void:
	var sig: String = ",".join(statuses.map(func(s): return str(s)))
	if nd.get("_status_sig", "") == sig:
		return
	nd["_status_sig"] = sig
	var row: HBoxContainer = nd["status_row"]
	for c in row.get_children():
		c.queue_free()
	# Overflow cap (UX audit #6): a late-fight unit can carry 5+ statuses; uncapped chips clip
	# past the plate. Four visible + a neutral "+N" chip, matching the disclosure-tier idea.
	var shown: Array = statuses.slice(0, 4)
	if statuses.size() > 4:
		shown.append("+%d" % (statuses.size() - 4))
	for s in shown:
		var kind := str(s)
		var meta: Dictionary = STATUS_META.get(kind, {"abbr": kind.substr(0, 4).to_upper(), "color": Color(0.7, 0.7, 0.7)})
		var col: Color = meta.get("color", Color(0.7, 0.7, 0.7))
		var chip := PanelContainer.new()
		var csb := StyleBoxFlat.new()
		csb.bg_color = Color(col.r, col.g, col.b, 0.28)
		csb.border_color = col
		csb.set_border_width_all(1)
		csb.set_corner_radius_all(3)
		csb.content_margin_left = 2; csb.content_margin_right = 2
		csb.content_margin_top = 0; csb.content_margin_bottom = 0
		chip.add_theme_stylebox_override("panel", csb)
		var lbl := Label.new()
		lbl.text = str(meta.get("abbr", "?"))
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", col)
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		lbl.add_theme_constant_override("outline_size", 3)
		chip.add_child(lbl)
		row.add_child(chip)


func _sync_intent_glyph(nd: Dictionary, state: String) -> void:
	if nd.get("_state_sig", "") == state:
		return
	nd["_state_sig"] = state
	var lbl: Label = nd["intent_lbl"]
	lbl.text = "" if state == "dead" else str(STATE_GLYPH.get(state, ""))


## Transition-only intent/reason logging into the existing ticker (Tier 3,
## `docs/UX_LEGIBILITY.md` §6) — the cheap slice: no branch enum needed, just "did this unit's
## `intent` string change since the last tick we looked at". Silently does nothing while the sim
## doesn't populate `intent` (every entry is `""`), which is the correct degrade, not a bug.
func _check_intent_transitions(fa: Dictionary) -> void:
	var grouped: Dictionary = {}   # "side|reason" -> [names]
	for rec in fa.get("units", []):
		var uid: int = int(rec.get("id", -1))
		var intent: String = str(rec.get("intent", ""))
		if intent == "":
			continue
		if _last_intent.get(uid, "") == intent:
			continue
		_last_intent[uid] = intent
		var reason: String = str(rec.get("reason", ""))
		var txt := _humanise_ids(reason if reason != "" else intent)
		# ⚠️ COLLAPSE THE SQUAD INTO ONE LINE. The ticker used to print five identical lines —
		# `Gruulk: target: b02 (weakest)` / `Terrock: target: b02 (weakest)` / … — five reads that
		# say one thing. And that ONE thing, "the whole squad has agreed on a target", is the most
		# interesting fact the ticker ever carries and the only genuinely squad-level one in it
		# (`docs/WATCH_AUDIT.md` §6). Grouped by side and by reason, it finally says so.
		var key := "%s|%s" % ["A" if uid < team_a.size() else "B", txt]
		var g: Array = grouped.get(key, [])
		g.append(_unit_name(uid))
		grouped[key] = g
	for key in grouped.keys():
		var names: Array = grouped[key]
		var txt2: String = str(key).split("|", true, 1)[1]
		if names.size() >= 3:
			log_view.append_text("[color=#9fb6d9]%d monsters — %s[/color]\n" % [names.size(), txt2])
		else:
			log_view.append_text("[color=#9fb6d9]%s: %s[/color]\n" % [
				", ".join(PackedStringArray(names)), txt2])
	if not grouped.is_empty():
		call_deferred("_snap_log")


## ⚠️ THE PLAYER NEVER SEES `a03` ANYWHERE ELSE IN THE GAME. The behaviour tree writes its
## reasons with the sim's own unit ids — "bulling through a03 to a02", "peel b01 off a04" — and
## those strings go straight onto the screen. `docs/UX_LEGIBILITY.md` §1 rule 1 is that the
## vocabulary is never invented twice; a machine key leaking into the ticker invents it a third
## time. Every `a`/`b` + two digits token is resolved to the name the nameplates already use.
func _humanise_ids(text: String) -> String:
	if text == "":
		return text
	var out := ""
	var i := 0
	while i < text.length():
		var c := text[i]
		if (c == "a" or c == "b") and i + 2 < text.length() \
			and text[i + 1].is_valid_int() and text[i + 2].is_valid_int() \
			and (i == 0 or not text[i - 1].is_valid_identifier()) \
			and (i + 3 >= text.length() or not text[i + 3].is_valid_int()):
			out += _name_of_sim_id(text.substr(i, 3))
			i += 3
			continue
		out += c
		i += 1
	return out


func _unit_name(uid: int) -> String:
	if uid >= 0 and uid < all_units.size():
		return all_units[uid].species_name
	return "?"


func _draw_shot(shot: Dictionary, acc: Dictionary = {}) -> void:
	var from_id: int = int(shot.get("fromId", -1))
	var to_id: int = int(shot.get("toId", -1))
	if to_id < 0 or to_id >= nodes.size():
		return
	if bool(shot.get("hit", false)):
		_hit_flash(to_id)
		var crit: bool = bool(shot.get("crit", false))
		# ── impact burst, channel-coloured (never team-coloured — Guild Colours rule). Crit is
		# bigger and gains sparks: the payoff must read at fight speed, not only in the log. ──
		if vfx != null:
			# ── PLAY_ABILITY: the docs/VFX_ABILITY_MAP.md engine. The shot carries the move
			# NAME; the move dict carries everything the recipe cascade needs (name override →
			# line flavour → type/channel rules). The old channel-only block lives on inside
			# play_ability as the final fallback, so an unknown name still bursts. ──
			var vpos: Vector3 = (nodes[to_id]["holder"] as Node3D).position + Vector3(0, UNIT_HEIGHT * 0.5, 0)
			var cpos: Vector3 = vpos
			if from_id >= 0 and from_id < nodes.size():
				cpos = (nodes[from_id]["holder"] as Node3D).position + Vector3(0, UNIT_HEIGHT * 0.5, 0)
			var mv_d: Dictionary = _move_by_name.get(str(shot.get("move", "")), {})
			if mv_d.is_empty():
				mv_d = {"name": str(shot.get("move", "")), "type": "damage",
					"channel": str(shot.get("kind", "melee")), "target": "enemy"}
			# ── game feel: effect size scales with the WOUND, not the move. dmg as a fraction of
			# the victim's pool decides the oomph — a 5-damage poke on a wall stays a tick, the
			# same number on a dying wisp is a blow. Crits and heavy fractions also punch the
			# camera and pop the victim.
			var vic_hp := 1.0
			if to_id < all_units.size():
				vic_hp = maxf(1.0, float(all_units[to_id].max_hp))
			var frac: float = float(int(shot.get("dmg", 0))) / vic_hp
			var oomph: float = clampf(0.8 + frac * 2.5, 0.8, 2.0)
			vfx.play_ability(mv_d, cpos, vpos, crit, oomph)
			if crit or frac >= 0.18:
				_punch(0.45 if crit else 0.3, 0.3 if crit else 0.18)
				_scale_pop(to_id)

		var dmg_i: int = int(shot.get("dmg", 0))
		# ⚠️ Non-colour crit tell (`docs/ACCESSIBILITY.md` §4): crit vs. normal used to be
		# colour-only (gold vs. salmon, same size). A trailing "!" makes it readable without colour.
		#
		# ⚠️ AND THE SAME RULE FOR THE REAR BONUS. A backstab is a POSITIONAL read paying off, and
		# a player who cannot intervene has only the aftermath to learn from — so it says BACK in
		# words, not in a colour. Text, because facing is invisible at 4-13% of frame height.
		var arc := str(shot.get("arc", "front"))
		var label := ("%d!" % dmg_i) if crit else str(dmg_i)
		if arc == "rear":
			label = "%s BACK" % label
		# ⚠️ Damage numbers were a FOURTH colour system (gold/salmon/orange, mapping to nothing
		# the player had learned elsewhere). They now speak the channel palette — a magic hit's
		# number matches its burst — lightened for readability; crit keeps the "!" and a gold
		# LEAN (a modifier, not a base hue), rear keeps the BACK text.
		var num_col: Color = vfx.CHANNEL_COLOUR.get(str(shot.get("kind", "melee")), Color(0.9, 0.9, 0.9)) if vfx != null else Color(0.9, 0.9, 0.9)
		num_col = num_col.lerp(Color.WHITE, 0.35)
		if crit:
			num_col = num_col.lerp(Color(1.0, 0.84, 0.36), 0.5)
		# Accumulate into this tick's per-victim total; `_flush_damage_floats` emits one float per
		# body. `label` is kept for the single-hit case, where the crit "!" and the "BACK" tell
		# are exactly the reads the accessibility pass added and must not be summed away.
		var e_acc: Dictionary = acc.get(to_id, {"dmg": 0, "n": 0, "crit": false, "label": "", "col": num_col})
		e_acc["dmg"] = int(e_acc["dmg"]) + dmg_i
		e_acc["n"] = int(e_acc["n"]) + 1
		e_acc["crit"] = bool(e_acc["crit"]) or crit
		e_acc["label"] = label
		e_acc["col"] = num_col
		acc[to_id] = e_acc
	else:
		_float_text(to_id, "MISS", Color(0.78, 0.78, 0.84))
	# A tracer for anything not swung in melee, so ranged and magic read as reaching across.
	# ⚠️ NOT FOR FRIENDLY CASTS. The user spotted a gold "laser" spanning the arena — Larkessa
	# team-buffing a distant ally. Team coverage is formation-fraction by design (the deployment
	# board's aura/AoE trade), so the REACH is intended; the LINE was the lie — it reads as an
	# attack. Buff recipients are already marked by the aura_pulse ring, which is the grammar
	# built for exactly this. Attacks keep their tracers.
	var mv_t: Dictionary = _move_by_name.get(str(shot.get("move", "")), {})
	var friendly_cast: bool = str(mv_t.get("target", "enemy")) in ["self", "ally", "team"]
	if from_id >= 0 and from_id < nodes.size() and not friendly_cast:
		if str(shot.get("kind", "melee")) != "melee":
			_tracer((nodes[from_id]["holder"] as Node3D).position,
					(nodes[to_id]["holder"] as Node3D).position)
		elif bool(shot.get("hit", false)):
			# ⚠️ MELEE ATTRIBUTION (UX audit #4): in a 4-body scrum nothing pointed from attacker
			# to victim — the flinch and the number sat on the victim alone. A subdued flick
			# (dimmer, faster than a tracer — this is attribution, not reach) survives density.
			_tracer((nodes[from_id]["holder"] as Node3D).position,
					(nodes[to_id]["holder"] as Node3D).position, 0.35, 0.12)


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# AUDIO — the sim's own events, at the sim's own tick rate, positioned on the sim's own bodies.
#
# ⚠️ THE WHOLE INTERFACE IS `on_event(raw_event, actor_pos, impact_pos)`. The mixer reads nothing
# else about the fight — the same rule the renderer follows, for the same reason: two sources of
# truth drift. Two kinds resolve their position differently and both are stated rather than
# guessed: a `death` names its unit as `id` (not `to`), and an `aoe` happens at a point on the
# GROUND (`centre`), not on a body.
#
# ⚠️ AND IT MUST BE SILENT DURING A SCRUB. `_seek` replays the whole match's events to rebuild the
# log; without the mute that would fire the entire mix in a single frame. Same contract as
# `_fx_muted`, deliberately keyed off the same flag so the two layers cannot get out of step.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _sim_world_pos(sim_id: String) -> Vector3:
	if sim_id == "":
		return Vector3.ZERO
	var slot: int = sim_id.substr(1).to_int()
	var k: int = slot if sim_id.begins_with("a") else team_a.size() + slot
	if k < 0 or k >= nodes.size():
		return Vector3.ZERO
	return (nodes[k]["holder"] as Node3D).position


func _play_tick_audio(fa: Dictionary) -> void:
	if _audio == null or _fx_muted:
		return
	for e in (fa.get("events", []) as Array):
		var ev: Dictionary = e
		var kind := str(ev.get("kind", ""))
		var cpos: Vector3 = _sim_world_pos(str(ev.get("from", "")))
		var apos: Vector3 = _sim_world_pos(str(ev.get("to", "")))
		if kind == "death":
			apos = _sim_world_pos(str(ev.get("id", "")))
		elif kind == "aoe":
			var c: Vector2 = ev.get("centre", Vector2.ZERO)
			# Centre-frame -> corner-frame -> world, the same translation every other consumer of
			# a sim position on this screen makes (see the ⚠️⚠️ coordinate note in _run_new_sim).
			apos = _to_world(c + ground_size * 0.5)
		if apos == Vector3.ZERO:
			apos = cpos
		if cpos == Vector3.ZERO:
			cpos = apos
		_audio.on_event(ev, cpos, apos)


## The transport follows the playback controls from ONE place, because `speed` is written from
## five call sites (three keys, the button row, the pause toggle) and a mixer that tracked only
## some of them would drift out of step with the picture. Pushed only on CHANGE — `set_muted`
## walks every voice, which is not a per-frame cost worth paying for a value that rarely moves.
func _sync_audio_transport() -> void:
	if _audio == null:
		return
	var want_muted: bool = speed <= 0.0 or not playing
	if not is_equal_approx(speed, _audio_speed) and speed > 0.0:
		_audio_speed = speed
		_audio.set_speed(speed)
	if want_muted != _audio_muted:
		_audio_muted = want_muted
		_audio.set_muted(want_muted)


## One damage number per victim per tick. A single hit keeps its own label verbatim (crit "!",
## rear "BACK"); two or more are summed and marked with a hit count, because "34 ×3" is a read a
## viewer can take in at fight speed and three separate numbers on one overlapping body is not.
func _flush_damage_floats(acc: Dictionary) -> void:
	for vid in acc.keys():
		var e: Dictionary = acc[vid]
		var n: int = int(e.get("n", 1))
		var txt: String = str(e.get("label", "")) if n <= 1 else "%d ×%d%s" % [
			int(e.get("dmg", 0)), n, "!" if bool(e.get("crit", false)) else ""]
		_float_text(int(vid), txt, e.get("col", Color(0.9, 0.9, 0.9)))


func _tracer(a: Vector3, b: Vector3, alpha: float = 0.9, dur: float = 0.22) -> void:
	var im := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	# Craft pass: bright at the shooter, fading toward the mark — a line of equal weight reads
	# as a wall; a gradient reads as travel.
	st.set_color(Color(1.0, 0.92, 0.6, alpha))
	st.add_vertex(a + Vector3(0, UNIT_HEIGHT * 0.55, 0))
	st.set_color(Color(1.0, 0.92, 0.6, 0.15))
	st.add_vertex(b + Vector3(0, UNIT_HEIGHT * 0.55, 0))
	im.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.material_override = mat
	add_child(im)
	var tw := create_tween()
	tw.tween_property(mat, "albedo_color:a", 0.0, dur / maxf(0.25, speed))
	tw.tween_callback(im.queue_free)


## In-flight aimed abilities (`docs/BUILD_CONTRACT.md` §2's new `projectiles` array) — drawn as a
## short streak that travels from `from` to `to` at `progress`. ⚠️ This is what makes a shot that
## MISSES because the target moved actually visible: the streak flies to `to` (where the target
## was aimed at) and the target may simply not be there anymore — no special-casing needed, the
## renderer just draws what the stream says. Guarded throughout: the current sim build emits no
## `projectiles` at all yet, so this is a no-op until stream A lands it.
func _sync_projectiles(fa: Dictionary, fb: Dictionary, t: float) -> void:
	var pa: Array = fa.get("projectiles", [])
	if pa.is_empty() and _projectile_nodes.is_empty():
		return
	var pb: Array = fb.get("projectiles", [])
	var seen: Dictionary = {}
	for proj in pa:
		var pid: int = int(proj.get("id", -1))
		var from_a: Vector2 = proj.get("from", Vector2.ZERO)
		var to_a: Vector2 = proj.get("to", from_a)
		var prog_a: float = clampf(float(proj.get("progress", 0.0)), 0.0, 1.0)
		var pos2: Vector2 = from_a.lerp(to_a, prog_a)
		var proj_b = _find_projectile(pb, pid)
		if proj_b != null:
			var from_b: Vector2 = proj_b.get("from", from_a)
			var to_b: Vector2 = proj_b.get("to", to_a)
			var prog_b: float = clampf(float(proj_b.get("progress", prog_a)), 0.0, 1.0)
			pos2 = pos2.lerp(from_b.lerp(to_b, prog_b), t)
		var dir2: Vector2 = to_a - from_a
		_update_projectile_node(pid, pos2, dir2, str(proj.get("kind", "ranged")))
		seen[pid] = true
	for pid in _projectile_nodes.keys():
		if not seen.has(pid):
			_projectile_nodes[pid].queue_free()
			_projectile_nodes.erase(pid)


func _find_projectile(arr: Array, pid: int):
	for p in arr:
		if int(p.get("id", -1)) == pid:
			return p
	return null


func _update_projectile_node(pid: int, pos2: Vector2, dir2: Vector2, kind: String) -> void:
	var mi: Node3D = _projectile_nodes.get(pid)
	if mi == null:
		# ⚠️ MAGIC IS A FIREBALL NOW — an animated flipbook billboard (Brackeys CC0 fire sheet,
		# looping) with an ember trail, replacing the grey box. Other channels keep the bolt
		# box: an arrow SHOULD read as a shaft, and one showpiece per channel beats four kinds
		# of fireworks nobody can tell apart. The trail is a child emitter, so it follows for
		# free and dies with the projectile node.
		if kind == "magic":
			var holder := Node3D.new()
			var quad := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(3.2, 3.2)
			# Craft pass 2026-08-06: the flame ANIMATES in flight — a fragment shader cycles the
			# 8x8 sheet on TIME (was a single frozen frame; the trail carried all the motion).
			# Billboarding is done in the vertex stage, the standard Godot snippet.
			var fsh := Shader.new()
			fsh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform sampler2D sheet : source_color;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	float f = mod(floor(TIME * 30.0), 64.0);
	vec2 cell = vec2(mod(f, 8.0), floor(f / 8.0));
	vec2 uv = (UV + cell) / 8.0;
	vec4 c = texture(sheet, uv);
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
"""
			var fmat := ShaderMaterial.new()
			fmat.shader = fsh
			var ft = load("res://assets/vfx/flipbooks/fire_01_8x8_clean.png")
			if ft != null:
				fmat.set_shader_parameter("sheet", ft)
			qm.material = fmat
			quad.mesh = qm
			holder.add_child(quad)
			var trail := GPUParticles3D.new()
			trail.amount = 20
			trail.lifetime = 0.5
			var tm := ParticleProcessMaterial.new()
			tm.direction = Vector3(0, 0, 0)
			tm.spread = 30.0
			tm.initial_velocity_min = 0.5
			tm.initial_velocity_max = 1.5
			tm.gravity = Vector3(0, 1.5, 0)
			tm.scale_min = 0.3
			tm.scale_max = 0.8
			tm.color = Color(1.0, 0.55, 0.2)
			trail.process_material = tm
			var tq := QuadMesh.new()
			tq.size = Vector2(0.9, 0.9)
			var tmat := StandardMaterial3D.new()
			tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			tmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			tmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			tmat.vertex_color_use_as_albedo = true
			var st = load("res://assets/vfx/kenney/spark.png")
			if st != null:
				tmat.albedo_texture = st
			tq.material = tmat
			trail.draw_pass_1 = tq
			holder.add_child(trail)
			# Quality tier: the fireball CARRIES ITS OWN LIGHT — the floor glows as it passes,
			# which is the difference between an object in the world and a sprite over it.
			var flight := OmniLight3D.new()
			flight.light_color = Color(1.0, 0.6, 0.25)
			flight.light_energy = 3.5
			flight.omni_range = 16.0
			flight.shadow_enabled = false
			holder.add_child(flight)
			mi = holder
		else:
			var box := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.35, 0.22, 1.3)
			box.mesh = bm
			var mat := StandardMaterial3D.new()
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.albedo_color = PROJECTILE_COLOUR.get(kind, Color(0.9, 0.9, 0.9))
			box.material_override = mat
			mi = box
		add_child(mi)
		_projectile_nodes[pid] = mi
	mi.position = _to_world(pos2) + Vector3(0, UNIT_HEIGHT * 0.55, 0)
	if dir2.length() > 0.001 and mi is MeshInstance3D:
		mi.rotation = Vector3(0, atan2(dir2.x, dir2.y), 0)


## Log events carry a unit NAME (the sim's own event vocabulary), the float-text helper wants the
## index into `all_units`. ⚠️ Names are not guaranteed unique — two Larkessa on one side is
## legal — so this returns the FIRST match and the float may land on the wrong twin. Accepted:
## the alternative is threading unit ids through every event, and the log line beside it always
## names the caster, so the information is not lost, only its anchor is approximate.
func _index_of_unit_named(nm: String) -> int:
	for i in range(all_units.size()):
		if str(all_units[i].species_name) == nm:
			return i
	return -1


var _float_recent := {}   # unit idx -> {t, n} — staggers same-moment floats (UX audit #3)

## ⚠️ `scale` IS A LEGIBILITY HIERARCHY, NOT A COSMETIC KNOB. Every float used to be the same
## size, so a REACTIVE number (thorns reflecting 6, a ward eating 14) shouted exactly as loudly as
## the blow that caused it. Measured on the first cut of the thorns presentation: four identical
## `6 THORNS` labels in one scrum frame, larger than the `16 ×2` damage float they were reacting
## to — the audit's "eight identical white 10s" failure, rebuilt from new parts. A secondary read
## is drawn secondary; the primary number stays the biggest thing on the body.
func _float_text(idx: int, text: String, col: Color, scale: float = 1.0) -> void:
	# ⚠️ Muted while a scrub rebuilds the log — see `_seek`. Without this a jump to t=20s spawns
	# every damage number of the fight at once.
	if _fx_muted:
		return
	# Same-tick hits on one body used to spawn at the identical offset — a multi-hit or two
	# attackers turned the payoff numbers into one unreadable smear at exactly the moment the
	# player most wants to read them. Floats within 0.4s on the same unit now fan out.
	var now_ms := Time.get_ticks_msec()
	var rec_f: Dictionary = _float_recent.get(idx, {"t": 0, "n": 0})
	if now_ms - int(rec_f["t"]) < 400:
		rec_f["n"] = int(rec_f["n"]) + 1
	else:
		rec_f["n"] = 0
	rec_f["t"] = now_ms
	_float_recent[idx] = rec_f
	var fan: int = int(rec_f["n"])
	var lbl := Label3D.new()
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 96
	lbl.outline_size = 30
	lbl.outline_modulate = Color(0, 0, 0, 0.9)
	lbl.modulate = col
	lbl.pixel_size = 0.0075 * clampf(scale, 0.3, 2.0)
	lbl.no_depth_test = true
	add_child(lbl)
	# World-space fan: same-moment floats on one body step sideways then up a row (a Label3D
	# lives in world units, not pixels — ~1.7 units x is one digit-width at this camera).
	var fan_off := Vector3(float((fan % 3) - 1) * 1.7, float(fan / 3) * 1.3, 0)
	var start: Vector3 = (nodes[idx]["holder"] as Node3D).position + Vector3(0, UNIT_HEIGHT * 0.8, 0) + fan_off
	lbl.position = start
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position", start + Vector3(0, 2.4, 0), 0.8 / maxf(0.25, speed))
	tw.tween_property(lbl, "modulate:a", 0.0, 0.8 / maxf(0.25, speed))
	tw.chain().tween_callback(lbl.queue_free)


## The red flash on a landed hit. ⚠️ Two bodies, two mechanisms: a `Sprite3D` has `modulate`, a
## rigged `MeshInstance3D` does not — its colour lives on the material. Tinting is not optional
## polish here; without it a hit that deals damage has no tell on the BODY at all, only a floating
## number, and `docs/ACCESSIBILITY.md` counts the number as one channel rather than two.
func _hit_flash(idx: int) -> void:
	if _fx_muted:
		return
	if idx < 0 or idx >= nodes.size():
		return
	var nd: Dictionary = nodes[idx]
	var spr = nd.get("sprite")
	if spr != null:
		var tw := create_tween()
		tw.tween_property(spr, "modulate", Color(1.7, 0.55, 0.55), 0.05)
		tw.tween_property(spr, "modulate", Color(1, 1, 1), 0.18)
		return
	var rig = nd.get("rig")
	if rig != null and rig.has_method("hit_flash"):
		rig.hit_flash()


var _aoe_rings := {}   # unit index -> MeshInstance3D (the AoE windup telegraph)
var _innate_rings := {}   # unit index -> MeshInstance3D (persistent innate-zone tells)

## INNATE ZONE TELLS — the care loop's spatial innates made visible. A zoner (auraEnemySlow)
## carries a faint slow-field ring at its reach; a territorial (homeGroundDR) gets a fixed ring
## at its STATION. Innate identity is static monster data — the same data the nameplate's innate
## line already shows — so the renderer computing it breaks no contract. Brace/charge arming
## glints still need sim-side frame flags; deferred with this note, not forgotten.
func _build_innate_tells() -> void:
	var InnatesL = load("res://scripts/innate_fx.gd")
	for k in range(all_units.size()):
		var m = all_units[k]
		var fx: Dictionary = InnatesL.compute(m, GameData.innate_effects)
		var ring: MeshInstance3D = null
		var col := Color(1, 1, 1)
		var radius := 0.0
		var follow := false
		if fx.has("auraEnemySlow"):
			col = Color(0.55, 0.62, 0.80, 0.20)   # cold blue-grey: the slow field
			radius = 18.0   # ~ a melee kit's reach; exact per-kit reach varies per move
			follow = true
		elif fx.has("homeGroundDR"):
			col = Color(0.72, 0.60, 0.35, 0.22)   # earthy: home ground
			radius = InnatesL.HOME_RADIUS
		if radius <= 0.0:
			continue
		# ⚠️ THESE TWO RADII ARE SIM UNITS AND THE TORUS IS BUILT IN RENDER SPACE. Until 2026-08-08
		# they were fed straight to the mesh, so homeGroundDR drew a 61.6-unit ground annulus — 40%
		# of the short side of a 5v5 board — where 20.9 was intended, and auraEnemySlow drew 36.0
		# where 12.2 was intended: a flat 1/WORLD_SCALE = 2.94x error. Found by `_probe_vfx_scale`
		# while it was auditing vfx.gd, which does not own this ring and never did. Every other
		# length in this file crosses the boundary through `_to_world`/`* WORLD_SCALE`; this one
		# skipped it, which is the "two opinions about a distance" failure `spatial.gd`'s own header
		# warns about. Convert HERE, at the one place the two spaces meet.
		radius *= WORLD_SCALE
		ring = MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = maxf(radius - 0.4, radius * 0.90)
		tor.outer_radius = radius
		tor.rings = 48
		ring.mesh = tor
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = col
		ring.material_override = mat
		ring.position = (nodes[k]["holder"] as Node3D).position + Vector3(0, 0.12, 0)
		add_child(ring)
		_innate_rings[k] = {"ring": ring, "follow": follow}


func _update_innate_tells() -> void:
	for k in _innate_rings:
		var rec: Dictionary = _innate_rings[k]
		var ring: MeshInstance3D = rec["ring"]
		var dead: bool = bool(nodes[k].get("dead", false))
		ring.visible = not dead
		if bool(rec["follow"]) and not dead:
			ring.position = (nodes[k]["holder"] as Node3D).position + Vector3(0, 0.12, 0)

# ── GAME FEEL (2026-08-06). All of it renderer-side and decaying — the sim never notices. ──
var _feel_slow := 1.0    # playback multiplier: dips on big hits (hit-stop), recovers fast
var _shake := 0.0        # camera punch magnitude, decays exponentially

## One call per impactful moment. `stop` dips playback (0.35 = strong hit-stop), `shake` kicks
## the camera. Both decay on their own — stacking punches extends, never accumulates runaway.
func _punch(stop: float, shake: float) -> void:
	if _fx_muted:
		return
	_feel_slow = minf(_feel_slow, 1.0 - clampf(stop, 0.0, 0.85))
	_shake = maxf(_shake, shake)
	# The stands feel the shake too (user direction): any camera punch rolls a small per-model
	# cheer chance; deaths roll their own larger chance at the death event.
	if spectators != null:
		spectators.react(clampf(shake * 0.6, 0.08, 0.3))


## Victim scale-pop: a fast 1.0 → 1.12 → 1.0 on the holder. The body visibly TAKES the hit.
func _scale_pop(idx: int) -> void:
	if idx < 0 or idx >= nodes.size():
		return
	var h := nodes[idx]["holder"] as Node3D
	var tw := create_tween()
	tw.tween_property(h, "scale", Vector3.ONE * 1.12, 0.05)
	tw.tween_property(h, "scale", Vector3.ONE, 0.12)

func _show_aoe_ring(idx: int, radius: float, channel: String) -> void:
	var ring: MeshInstance3D = _aoe_rings.get(idx)
	if ring == null:
		ring = MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = maxf(0.5, radius - 0.6)
		tor.outer_radius = radius
		tor.rings = 48
		ring.mesh = tor
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var col: Color = vfx.CHANNEL_COLOUR.get(channel, Color(0.9, 0.6, 0.3)) if vfx != null else Color(0.9, 0.6, 0.3)
		mat.albedo_color = Color(col.r, col.g, col.b, 0.45)
		ring.material_override = mat
		add_child(ring)
		_aoe_rings[idx] = ring
	ring.position = (nodes[idx]["holder"] as Node3D).position + Vector3(0, 0.15, 0)
	ring.visible = true


## THE AoE IMPACT. `_show_aoe_ring` above is the TELEGRAPH — the ring that sits under a caster
## while an allEnemies move winds up. This is the other half: the moment it lands, at the centre
## and radius the SIM reported, expanding once and fading. The sim's own comment at `sim.gd:1585`
## is the specification; every number here comes off the event.
func _aoe_burst(centre_ground: Vector2, radius: float, targets: int) -> void:
	if _fx_muted or radius <= 0.0:
		return
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	var r: float = radius * WORLD_SCALE
	tor.inner_radius = maxf(0.2, r - 0.45)
	tor.outer_radius = r
	tor.rings = 48
	ring.mesh = tor
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# ⚠️ THE COUNT IS THE MECHANIC. "Weak into one body, strong into three" is the whole falloff
	# design, so the burst reads heavier the more bodies it caught — that is the fact the viewer
	# is meant to learn, and a fixed ring would hide it.
	var heat: float = clampf(float(targets - 1) / 3.0, 0.0, 1.0)
	mat.albedo_color = Color(1.0, 0.62, 0.28).lerp(Color(1.0, 0.30, 0.22), heat)
	mat.albedo_color.a = 0.30 + 0.45 * heat
	ring.material_override = mat
	ring.position = _to_world(centre_ground) + Vector3(0, 0.12, 0)
	ring.scale = Vector3(0.55, 1.0, 0.55)
	add_child(ring)
	var dur: float = 0.5 / maxf(0.25, speed)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector3.ONE, dur)
	tw.tween_property(mat, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(ring.queue_free)
	if targets >= 2:
		_punch(0.2 + 0.08 * float(targets), 0.12 + 0.05 * float(targets))


## A LASTING LINE BETWEEN TWO BODIES. `_tracer` is a 0.22s flick built for attribution of a blow;
## this is for a RELATION that persists — a taunt compelling one monster onto another. It follows
## both units while it lives, because a static line between two moving bodies would be a lie the
## moment either of them stepped.
var _tethers: Array = []

func _tether(from_idx: int, to_idx: int, col: Color, dur: float) -> void:
	if _fx_muted:
		return
	if from_idx < 0 or to_idx < 0 or from_idx >= nodes.size() or to_idx >= nodes.size():
		return
	var im := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = col
	mat.no_depth_test = true
	im.material_override = mat
	add_child(im)
	_tethers.append({"node": im, "mat": mat, "a": from_idx, "b": to_idx, "until": _play_t() + dur,
		"dur": dur, "col": col})


func _update_tethers() -> void:
	var t := _play_t()
	var keep: Array = []
	for th in _tethers:
		var d: Dictionary = th
		var im: MeshInstance3D = d["node"]
		var left: float = float(d["until"]) - t
		if left <= 0.0 or left > float(d["dur"]) or not is_instance_valid(im):
			if is_instance_valid(im):
				im.queue_free()
			continue
		var a: Vector3 = (nodes[int(d["a"])]["holder"] as Node3D).position + Vector3(0, UNIT_HEIGHT * 0.55, 0)
		var b: Vector3 = (nodes[int(d["b"])]["holder"] as Node3D).position + Vector3(0, UNIT_HEIGHT * 0.55, 0)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_LINES)
		st.set_color(Color(d["col"]))
		st.add_vertex(a)
		st.set_color(Color(d["col"]))
		st.add_vertex(b)
		im.mesh = st.commit()
		(d["mat"] as StandardMaterial3D).albedo_color.a = clampf(left / float(d["dur"]), 0.0, 1.0)
		keep.append(d)
	_tethers = keep


func _hide_aoe_ring(idx: int) -> void:
	if _aoe_rings.has(idx):
		(_aoe_rings[idx] as MeshInstance3D).visible = false


func _topple(idx: int) -> void:
	if _fx_muted:
		return
	if vfx != null and idx >= 0 and idx < nodes.size():
		vfx.burst((nodes[idx]["holder"] as Node3D).position + Vector3(0, UNIT_HEIGHT * 0.4, 0),
			"smoke", Color(0.55, 0.55, 0.60), 1.8, 16)
	var nd: Dictionary = nodes[idx]
	if nd["dead"]:
		return
	nd["dead"] = true
	# The director holds the shot on a body that has just fallen (`CAM_DEATH_HOLD`) so the kill
	# reads instead of the camera leaving for the next exchange mid-collapse.
	_death_at[idx] = _play_t()
	(nd["plate"] as Control).modulate = Color(1, 1, 1, 0.4)
	if selected_idx == idx:
		_select_unit(-1)

	# ⚠️ A RIGGED UNIT MUST NOT BE TOPPLED BY THE RENDERER — it has a real death ANIMATION, and
	# rotating the body on top of it would fight the clip for the same transform. `set_state("dead")`
	# has already started that clip by the time this runs. The tween below exists only for the
	# sprite path, where there is no death motion and a topple is the only way a body reads as down.
	var spr = nd.get("sprite")
	if spr == null:
		return
	# ⚠️ Billboarding must be disabled first — a Y-billboard re-solves its orientation every frame
	# and would silently undo the topple, leaving the creature fading while still standing.
	spr.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	var side_sign := -1.0 if idx < team_a.size() else 1.0
	var tw := create_tween()
	nd["topple_tw"] = tw     # so a backwards scrub can kill it — see `_undo_deaths`
	tw.set_parallel(true)
	tw.tween_property(spr, "rotation_degrees:z", 80.0 * side_sign, 0.4)
	tw.tween_property(spr, "position:y", UNIT_HEIGHT * 0.2, 0.4)
	tw.tween_property(spr, "modulate:a", 0.4, 0.45)
	if selected_idx == idx:
		_select_unit(-1)


## How loudly this unit's plate should read, 0.42 (quiet) .. 1.0 (full). Driven entirely by the
## frame stream's own fields — no renderer-side notion of "interesting", per `BUILD_CONTRACT.md`
## §2 ("the renderer derives nothing").
const PLATE_QUIET := 0.45
const PLATE_HURT_HP := 0.98      # anything below full HP has a story
const PLATE_DEAD := 0.32

## ⚠️ FEWER PLATES, NOT SMALLER ONES — this file's own conclusion, three shrinks ago:
## "148 -> 104 -> 82 … THIS IS THE FLOOR. Any further reduction has to come from showing FEWER
## plates, not smaller ones." The quiet-unit FADE was the answer at the time and it was not
## enough: `docs/WATCH_AUDIT.md` §2 measured 52-69% of plates orphaned from their own unit and
## the annotation occupying 2.4x the screen area of the fight it annotates. A dimmed plate is
## still a full-size rectangle competing for the same pixels.
##
## So a plate now has TWO SIZES. A unit doing something the player must read — casting, hurt,
## under a status, striking, selected, or the one the camera is on — keeps the full Plater plate.
## Everyone else collapses to the health bar alone: no name row, no mana, no status strip, and
## scaled down. The name is not lost, it is DEFERRED — the body carries the team ring, and one
## Tab or click restores the full plate on demand (`docs/UX_LEGIBILITY.md`'s disclosure tiers).
const PLATE_MINI_SCALE := 0.62
## ⚠️ A HARD CAP, NOT A PREDICATE. The first cut of this was a boolean test — casting, hurt, under
## a status, striking — and it measured almost NO improvement, because in the ten-second scrum
## that decides the match EVERY unit satisfies it. A rule that stops applying exactly when the
## screen is busiest is not a declutter rule. So the tier is now a RANKING with a ceiling: at most
## `PLATE_FULL_MAX` full plates on screen, always the most newsworthy ones, everyone else
## collapsed. The clutter is bounded by construction instead of by hope.
const PLATE_FULL_MAX := 4

## How much this unit's plate deserves to be a full one. Same sourcing rule as `_cam_interest`:
## every term comes off the displayed frame or off the roster, none of it is invented here.
func _plate_priority(idx: int, nd: Dictionary) -> float:
	if idx == selected_idx:
		return 1000.0                     # the player asked for this one
	if idx == _cam_subject:
		return 900.0                      # the shot is on it; it must be named
	var rec: Dictionary = nd.get("last_rec", {})
	if rec.is_empty():
		return 800.0                      # the deploy shot names everybody, once
	var w := 0.0
	var st := str(rec.get("state", "idle"))
	if st == "cast":
		w += 300.0                        # the cast bar IS the plate's reason to exist here
	elif st == "stunned":
		w += 220.0
	elif st == "attack":
		w += 60.0
	var mx: float = float(all_units[idx].max_hp) if idx < all_units.size() else 0.0
	if mx > 0.0:
		w += 400.0 * (1.0 - clampf(float(rec.get("hp", mx)) / mx, 0.0, 1.0))
	w += 40.0 * float((rec.get("statuses", []) as Array).size())
	return w


## Populated once per frame by `_update_plates`; read by the placement pass and by the sort.
var _plate_full_set: Dictionary = {}

func _plate_is_full(idx: int, _nd: Dictionary) -> bool:
	return bool(_plate_full_set.get(idx, false))


func _choose_full_plates() -> void:
	var rank: Array = []
	for k in range(nodes.size()):
		if not _alive_now(k):
			continue
		rank.append({"k": k, "w": _plate_priority(k, nodes[k])})
	rank.sort_custom(func(a, b):
		if not is_equal_approx(float(a["w"]), float(b["w"])):
			return float(a["w"]) > float(b["w"])
		return int(a["k"]) < int(b["k"]))     # stable tie-break: no slot-swapping between frames
	_plate_full_set.clear()
	for i in range(mini(PLATE_FULL_MAX, rank.size())):
		_plate_full_set[int(rank[i]["k"])] = true


func _apply_plate_tier(idx: int, nd: Dictionary) -> void:
	var full := _plate_is_full(idx, nd)
	if nd.get("_tier_full", null) == full:
		return
	nd["_tier_full"] = full
	var plate: Control = nd["plate"]
	(nd["head"] as Control).visible = full
	(nd["mp_bg"] as Control).visible = full
	(nd["status_strip"] as Control).visible = full
	plate.scale = Vector2.ONE if full else Vector2(PLATE_MINI_SCALE, PLATE_MINI_SCALE)
	plate.reset_size()


func _plate_emphasis(idx: int, nd: Dictionary) -> float:
	var rec: Dictionary = nd.get("last_rec", {})
	if rec.is_empty():
		return 1.0
	if not bool(rec.get("alive", true)):
		return PLATE_DEAD
	# The selected unit is always at full emphasis — the player asked for it.
	if idx == selected_idx:
		return 1.0
	# Anything the sim says is NOT routine: hurt, under a status, or doing something.
	#
	# ⚠️ `maxHp` is NOT in the frame contract (`spatial_sim.gd:_record_frame` emits hp, mp, alive,
	# state, statuses, pos, facing, targetId, intent, reason — and no ceiling). It comes from the
	# unit's own static data, exactly as the HP bar at `_apply_frame` already does. That is not the
	# renderer deriving state; it is the renderer reading the roster.
	var mx: float = float(all_units[idx].max_hp) if idx < all_units.size() else 0.0
	if mx > 0.0 and float(rec.get("hp", mx)) / mx < PLATE_HURT_HP:
		return 1.0
	if not (rec.get("statuses", []) as Array).is_empty():
		return 1.0
	var st := str(rec.get("state", "idle"))
	if st == "attack" or st == "cast" or st == "stunned":
		return 1.0
	return PLATE_QUIET


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# THE SQUAD READ — `docs/FUN_ADDITIONS.md`: "the unit of attention in a 5v5 must be the SQUAD,
# not the monster."
#
# ⚠️ WHAT WAS HERE BEFORE WAS THE ONLY SQUAD-LEVEL SURFACE IN THE GAME AND IT WAS INVERTED. It
# counted `MonsterInstance.alive`, which `_write_back_final` had already set to the fight's final
# state, so it announced the winner at frame zero and then disagreed with the screen for 100% of
# the fight (`docs/WATCH_AUDIT.md` §1a — 749 of 750 frames). It also spoke in "Team A"/"Team B",
# a vocabulary that appears nowhere else in the game.
#
# It now reads from the DISPLAYED FRAME and says three things a survivor count cannot:
#   · how many are standing, as pips — countable at a glance, and a non-colour channel
#   · how much squad is LEFT, as pooled HP, which is the difference between 4-on-4 even and
#     4-on-4 already lost
#   · who the fight is being decided on — the body currently taking fire from two or more
# ⚠️ Pooled HP is an AGGREGATE OF STREAM VALUES, not a derived game fact: every term is a `hp`
# and a `max_hp` the plates already display individually. The renderer adds them up; it does not
# know anything the frame did not tell it.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

var _hud_panel: PanelContainer = null
var _hud_pips := {}     # side -> Label
var _hud_fill := {}     # side -> ColorRect
var _hud_pct := {}      # side -> Label
var _hud_focus: Label = null
const HUD_BAR_W := 210.0
## The top band the scoreboard owns. Nameplates clamp below it — see `_update_plates`.
const HUD_RESERVE_Y := 92.0
## Landed hits kept for the focus read, {t, from, to}. Pruned to FOCUS_WINDOW every update.
var _recent_hits: Array = []
const FOCUS_WINDOW := 2.5      # playback seconds a hit still counts toward "being focused"
const FOCUS_MIN_ATTACKERS := 2 # one attacker is a duel, two or more is a squad decision


func _build_squad_hud() -> void:
	if _hud_panel != null or overlay == null:
		return
	_hud_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.06, 0.80)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14; sb.content_margin_right = 14
	sb.content_margin_top = 8; sb.content_margin_bottom = 8
	_hud_panel.add_theme_stylebox_override("panel", sb)
	_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_panel.anchor_left = 0.5; _hud_panel.anchor_right = 0.5
	_hud_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hud_panel.offset_top = 10
	# ⚠️ Above the nameplates. `_update_plates` gives each plate a `z_index` of its depth rank, so
	# a plate could out-rank a z_index-0 panel and draw over the scoreboard.
	_hud_panel.z_index = 60
	overlay.add_child(_hud_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	_hud_panel.add_child(col)
	for side in ["A", "B"]:
		var ident: Dictionary = Art.team_identity(0 if side == "A" else 1)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		col.add_child(row)
		var badge := Label.new()
		badge.text = "%s %s" % [str(ident["badge"]), "Your squad" if side == "A" else "The rival"]
		badge.custom_minimum_size = Vector2(150, 0)
		badge.add_theme_font_size_override("font_size", 15)
		badge.add_theme_color_override("font_color", (ident["colour"] as Color).lerp(Color.WHITE, 0.45))
		row.add_child(badge)
		var pips := Label.new()
		pips.custom_minimum_size = Vector2(86, 0)
		pips.add_theme_font_size_override("font_size", 15)
		pips.add_theme_color_override("font_color", Color(0.94, 0.94, 0.96))
		row.add_child(pips)
		_hud_pips[side] = pips
		var trough := ColorRect.new()
		trough.color = Color(0.13, 0.13, 0.16, 0.9)
		trough.custom_minimum_size = Vector2(HUD_BAR_W, 13)
		row.add_child(trough)
		var fill := ColorRect.new()
		fill.color = (ident["colour"] as Color).lerp(Color.WHITE, 0.25)
		fill.position = Vector2.ZERO
		fill.size = Vector2(HUD_BAR_W, 13)
		trough.add_child(fill)
		_hud_fill[side] = fill
		var pct := Label.new()
		pct.custom_minimum_size = Vector2(54, 0)
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pct.add_theme_font_size_override("font_size", 14)
		pct.add_theme_color_override("font_color", Color(0.85, 0.85, 0.90))
		row.add_child(pct)
		_hud_pct[side] = pct
	_hud_focus = Label.new()
	_hud_focus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_focus.add_theme_font_size_override("font_size", 14)
	_hud_focus.add_theme_color_override("font_color", Color(1.0, 0.72, 0.36))
	col.add_child(_hud_focus)


func _update_standing_hud() -> void:
	_build_squad_hud()
	if _hud_panel == null:
		return
	var na: int = team_a.size()
	for side in ["A", "B"]:
		var lo: int = 0 if side == "A" else na
		var hi: int = na if side == "A" else all_units.size()
		var up := 0
		var hp := 0.0
		var pool := 0.0
		var pips := ""
		for k in range(lo, hi):
			var mx: float = float(all_units[k].max_hp)
			pool += mx
			if _alive_now(k):
				up += 1
				pips += "●"
				hp += float((nodes[k].get("last_rec", {}) as Dictionary).get("hp", mx))
			else:
				pips += "○"
		var frac: float = 0.0 if pool <= 0.0 else clampf(hp / pool, 0.0, 1.0)
		(_hud_pips[side] as Label).text = "%s %d/%d" % [pips, up, hi - lo]
		(_hud_fill[side] as ColorRect).size = Vector2(HUD_BAR_W * frac, 13)
		(_hud_pct[side] as Label).text = "%d%%" % int(round(frac * 100.0))
	_update_focus_read()


## WHO IS THE FIGHT BEING DECIDED ON. A body taking fire from two or more enemies inside a 2.5s
## window is the squad's actual decision made visible — `docs/TACTICS_BRAINSTORM.md` records that
## focus fire is architecturally weak because target priority lives on the individual, so five
## monsters agree only by coincidence; when they DO agree, that is the most interesting fact on
## the board and until now nothing said it.
func _update_focus_read() -> void:
	var t := _play_t()
	var keep: Array = []
	for h in _recent_hits:
		if t - float((h as Dictionary)["t"]) <= FOCUS_WINDOW and t >= float((h as Dictionary)["t"]):
			keep.append(h)
	_recent_hits = keep
	var attackers: Dictionary = {}   # victim -> {attacker: true}
	for h in _recent_hits:
		var v: int = int((h as Dictionary)["to"])
		var s: Dictionary = attackers.get(v, {})
		s[int((h as Dictionary)["from"])] = true
		attackers[v] = s
	var best := -1
	var best_n := 0
	for v in attackers.keys():
		var n: int = (attackers[v] as Dictionary).size()
		if n > best_n and _alive_now(int(v)):
			best_n = n
			best = int(v)
	if best < 0 or best_n < FOCUS_MIN_ATTACKERS:
		_hud_focus.text = ""
		_set_focus_ring(-1)
		return
	var side_txt := "The rival is" if best < team_a.size() else "Your squad is"
	_hud_focus.text = "%s focusing %s — %d on one" % [side_txt, _unit_name(best), best_n]
	_set_focus_ring(best)


var _focus_ring: MeshInstance3D = null
var _focus_ring_on := -1

## The same fact, ON THE BODY. The HUD line says who; this says WHERE, which is the half a text
## line cannot carry in a scrum.
func _set_focus_ring(idx: int) -> void:
	if _focus_ring == null:
		_focus_ring = MeshInstance3D.new()
		var tor := TorusMesh.new()
		tor.inner_radius = 1.5
		tor.outer_radius = 2.0
		tor.rings = 32
		_focus_ring.mesh = tor
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.62, 0.28, 0.75)
		_focus_ring.material_override = mat
		add_child(_focus_ring)
	_focus_ring_on = idx
	if idx < 0 or idx >= nodes.size():
		_focus_ring.visible = false
		return
	_focus_ring.visible = true
	_focus_ring.position = (nodes[idx]["holder"] as Node3D).position + Vector3(0, 0.1, 0)


func _update_plates() -> void:
	if camera == null:
		return
	if _focus_ring != null and _focus_ring_on >= 0 and _focus_ring_on < nodes.size():
		_focus_ring.position = (nodes[_focus_ring_on]["holder"] as Node3D).position + Vector3(0, 0.1, 0)
	# ⚠️ DECLUTTER PASS. Five plates in a scrum land on the same few screen pixels and stack into an
	# unreadable wall — the thing that hid the fight when the camera pulled back to 38 degrees.
	# Two rules, in this order:
	#   1. Sort by DEPTH so the nearest unit's plate is placed last and therefore drawn on top.
	#      A plate half-covered by a MORE distant unit's plate reads as a rendering fault.
	#   2. Nudge a plate UP whenever it would overlap one already placed this frame. Vertical, not
	#      horizontal, because a plate must stay above its own unit to be attributable at all —
	#      sliding it sideways breaks the one thing it is for.
	_choose_full_plates()
	var placed: Array = []   # Rect2 of each plate already positioned this frame
	# ⚠️ STACK IN A STABLE ORDER, DRAW BY DEPTH — two different questions the old code answered
	# with one sort. Processing by camera distance made the lift order reshuffle every frame as
	# units moved, so clustered plates SWAPPED SLOTS constantly — the "hard to read when they are
	# together" the user saw. Placement now runs in fixed unit order (a scrum stacks into the
	# same column every frame); depth only decides z_index, so the nearest still draws on top.
	var order: Array = []
	for k in range(nodes.size()):
		var h := nodes[k]["holder"] as Node3D
		order.append({"k": k, "d": camera.global_position.distance_to(h.global_position)})
	var by_depth := order.duplicate()
	by_depth.sort_custom(func(a, b): return float(a["d"]) > float(b["d"]))
	for rank in range(by_depth.size()):
		(nodes[int(by_depth[rank]["k"])]["plate"] as Control).z_index = rank
	# ⚠️ THE UNITS THAT MATTER GET THE PIXELS. Placement now runs FULL plates first and MINI
	# plates second, so a crowded frame spends its space on the monster that is casting, hurt or
	# under a status rather than on whichever unit happens to sit lowest in the roster. Still a
	# FIXED order within each tier (`k`), so a scrum stacks the same way every frame and plates
	# do not swap slots as units shuffle — the bug the note above records.
	order.sort_custom(func(a, b):
		var fa2: bool = _plate_is_full(int(a["k"]), nodes[int(a["k"])])
		var fb2: bool = _plate_is_full(int(b["k"]), nodes[int(b["k"])])
		if fa2 != fb2:
			return fa2
		return int(a["k"]) < int(b["k"]))

	for entry in order:
		var k: int = int(entry["k"])
		var nd: Dictionary = nodes[k]
		var plate: Control = nd["plate"]
		# ⚠️ THE DEAD STAY UNPLATED. This pass sets `visible = true` on every plate it places, so
		# without this skip it silently resurrected the plate `_apply_frame` just hid — the
		# hide-and-reshow fight would be invisible in any headless probe and obvious on screen.
		if bool(nd.get("dead", false)) or not bool((nd.get("last_rec", {}) as Dictionary).get("alive", true)):
			plate.visible = false
			_set_leader(k, false, Vector2.ZERO, Vector2.ZERO)
			continue
		var world: Vector3 = (nd["holder"] as Node3D).global_position + Vector3(0, UNIT_HEIGHT + 0.7, 0)
		if camera.is_position_behind(world):
			plate.visible = false
			_set_leader(k, false, Vector2.ZERO, Vector2.ZERO)
			continue
		# ⚠️ AN OFF-SCREEN UNIT'S PLATE MUST NOT BE DRAGGED BACK INTO FRAME. The viewport clamp
		# below exists so a LIFTED plate cannot escape the top of the screen; applied to a unit
		# that is genuinely outside the shot it did something else entirely — it pinned a row of
		# health bars to the left edge, each annotating a monster nowhere near it, duplicating the
		# edge pip that is the correct representation for exactly this case. Seen on
		# `watch_four_pillar_t35_cam1_04_t008.0.png`: four stray bars stacked down the left margin.
		# Off the shot, the pip speaks; the plate stays quiet.
		var vp0: Vector2 = get_viewport().get_visible_rect().size
		var anchor_px: Vector2 = camera.unproject_position(world)
		if anchor_px.x < -40.0 or anchor_px.x > vp0.x + 40.0 			or anchor_px.y < -40.0 or anchor_px.y > vp0.y + 40.0:
			plate.visible = false
			_set_leader(k, false, Vector2.ZERO, Vector2.ZERO)
			continue
		plate.visible = true
		# Full plate or collapsed health bar — decided per unit, per frame, from the frame stream.
		_apply_plate_tier(k, nd)
		# ⚠️ SIZE MUST INCLUDE SCALE. A mini plate is `scale`d, and `Control.size` does not know
		# that — measuring the declutter rect off the unscaled size would reserve half the screen
		# for a plate that draws at two thirds, and the pass would think it had cleared overlaps
		# it had not.
		var psize: Vector2 = plate.size * plate.scale
		var pos: Vector2 = camera.unproject_position(world) - Vector2(psize.x * 0.5, psize.y)

		# ⚠️ A MINI PLATE NEVER LIFTS — IT YIELDS. Lifting is what ORPHANS a plate from its own
		# unit, and `docs/WATCH_AUDIT.md` §2 measured 52-69% of plates lifted more than a body
		# height from the head they annotate, which makes them unattributable and therefore
		# useless. That cost is worth paying for a monster mid-cast at 20% HP. It is not worth
		# paying for a monster at full health walking forwards, whose team ring already says
		# who and whose side. So a quiet unit's collapsed bar sits on its own head or not at all.
		var rect := Rect2(pos, psize)
		var lifts := 0
		if not bool(nd.get("_tier_full", true)):
			for r in placed:
				if rect.intersects(r as Rect2):
					plate.visible = false
					break
			if not plate.visible:
				_set_leader(k, false, Vector2.ZERO, Vector2.ZERO)
				continue
		else:
			# Lift until clear of everything already placed. Bounded: after PLATE_MAX_LIFT steps
			# we accept the overlap rather than launch a plate off the top of the screen, which
			# would be a worse failure than a slightly crowded corner.
			while lifts < PLATE_MAX_LIFT:
				var clash := false
				for r in placed:
					if rect.intersects(r as Rect2):
						clash = true
						break
				if not clash:
					break
				# ⚠️ STOP AT THE SCOREBOARD BAND — DO NOT LIFT INTO IT AND GET CLAMPED BACK.
				# The first cut clamped `pos.y` to the band AFTER the loop, which quietly undid
				# the stacking: three plates that had been lifted into three tidy rows were all
				# pushed back onto the same row and overlapped horizontally instead
				# (`watch_central_mass_t80_cam1_08_t016.0.png` — "Titanus◆ Grynt Mirejaw" run
				# together). A clamp applied after a placement pass invalidates the placement
				# pass. The ceiling belongs INSIDE the loop.
				if pos.y - (psize.y + PLATE_GAP) < HUD_RESERVE_Y:
					break
				pos.y -= psize.y + PLATE_GAP
				rect = Rect2(pos, psize)
				lifts += 1

		# ⚠️ CLAMP INTO THE VIEWPORT. Lifting a plate to dodge an overlap can push it clean off the
		# top of the screen, which is a worse failure than the crowding it was avoiding — the unit
		# is then annotated by something the player cannot see. Observed at 1280x800 with five
		# units in a scrum: the nearest plate left the frame entirely.
		# ⚠️ QUIET UNITS RECEDE. Ten full-strength plates all shouting equally is why the annotation
		# read louder than the fight — and in an autobattler the player's attention is the ONLY
		# resource they have left, because they cannot intervene. A unit at full HP that is walking
		# is not news; a unit taking damage, casting, stunned or dying is.
		#
		# ⚠️ THIS DIMS, IT NEVER HIDES. Every plate stays on screen and stays legible — `CLAUDE.md`
		# makes legibility load-bearing, and a player who cannot find their own monster has been
		# failed worse than one reading a busy frame. This is emphasis, not disclosure.
		plate.modulate.a = _plate_emphasis(k, nd)

		var vp: Vector2 = get_viewport().get_visible_rect().size
		pos.x = clampf(pos.x, 4.0, maxf(4.0, vp.x - psize.x - 4.0))
		# ⚠️ RESERVE THE TOP BAND FOR THE SQUAD SCOREBOARD. The lift loop pushes crowded plates
		# upward, and with the scoreboard now living at the top centre they climbed straight
		# through it — the one surface that answers "who is winning" was being buried by the ten
		# surfaces that answer "how is this individual". First measured on
		# `watch_four_pillar_t35_cam1_06_t012.0.png`, where three plates sat across it.
		pos.y = clampf(pos.y, HUD_RESERVE_Y, maxf(HUD_RESERVE_Y, vp.y - psize.y - 4.0))
		plate.position = pos
		# ⚠️ A LIFTED PLATE NEEDS A LEADER LINE, OR IT IS NOT ANNOTATION — IT IS DECORATION.
		# `docs/WATCH_AUDIT.md` §2's "orphaned" measure (a plate more than a body-height from the
		# head it belongs to) is a proxy for the real failure, which is *unattributable*. Capping
		# the plate count and collapsing quiet units both help and neither can eliminate lifting:
		# four full plates over one scrum is four 90px rectangles that must stack somewhere. A
		# connector fixes attribution directly instead of trying to make lifting unnecessary — the
		# standard call-out solution, and the one this file had not tried.
		var head_px: Vector2 = camera.unproject_position(
			(nd["holder"] as Node3D).global_position + Vector3(0, UNIT_HEIGHT, 0))
		_set_leader(k, lifts > 0, Vector2(pos.x + psize.x * 0.5, pos.y + psize.y), head_px)
		# ⚠️ Record the CLAMPED rect, not the pre-clamp one — a plate pushed back down by the
		# viewport clamp occupies different pixels, and registering the wrong rect would let the
		# next plate overlap it anyway.
		placed.append(Rect2(pos, psize))
		# The lifted plate no longer sits on its unit's head, so it must still be attributable.
		# Fade it slightly as it climbs — a plate far from its unit reads as less certain, which
		# is honest, and the fade also stops a stack of lifted plates competing for attention.
		plate.modulate.a = 1.0 if lifts == 0 else maxf(0.55, 1.0 - 0.15 * float(lifts))


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# OFF-SCREEN CONSEQUENCE — the thing that makes a directed camera honest.
#
# ⚠️ A CAMERA THAT CHOOSES A SUBJECT IS A CAMERA THAT HIDES EVERYTHING ELSE, AND IN A GAME THE
# PLAYER CANNOT INTERVENE IN, HIDING IS LYING. The old fitter never had this problem because it
# never chose; it paid for that by pulling back until a monster was 43 pixels tall
# (`docs/WATCH_AUDIT.md` §3). The trade is only acceptable if what leaves the shot still reports:
# a pip on the edge of the frame, in the unit's own team colour and badge, carrying its name and
# its HP, flaring when it takes a hit and going dark when it falls. Your monster dying on the far
# wing is then something you WATCH HAPPEN, not something you discover in the report.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

var _pips := {}        # unit idx -> {panel, label}
const PIP_MARGIN := 26.0

func _update_offscreen_pips() -> void:
	if camera == null or plates_root == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var t := _play_t()
	for k in range(nodes.size()):
		var pip: Dictionary = _ensure_pip(k)
		var panel: PanelContainer = pip["panel"]
		# ⚠️ ARENA mode already holds everyone in frame, and FREE is the player's own shot — a pip
		# in either is clutter answering a question nobody asked.
		if not _alive_now(k) or _cam_mode == CamMode.ARENA:
			panel.visible = false
			continue
		var world: Vector3 = (nodes[k]["holder"] as Node3D).global_position + Vector3(0, UNIT_HEIGHT * 0.5, 0)
		var behind: bool = camera.is_position_behind(world)
		var sp: Vector2 = camera.unproject_position(world)
		if behind:
			# `unproject_position` mirrors points behind the lens; reflect through the centre so
			# the pip sits on the side the unit actually is.
			sp = vp * 0.5 + (vp * 0.5 - sp)
		var inside: bool = (not behind) and sp.x > PIP_MARGIN and sp.x < vp.x - PIP_MARGIN \
			and sp.y > PIP_MARGIN and sp.y < vp.y - PIP_MARGIN
		if inside:
			panel.visible = false
			continue
		panel.visible = true
		var lbl: Label = pip["label"]
		var mx: float = float(all_units[k].max_hp) if k < all_units.size() else 0.0
		var rec: Dictionary = (nodes[k] as Dictionary).get("last_rec", {})
		var frac: float = 1.0 if mx <= 0.0 else clampf(float(rec.get("hp", mx)) / mx, 0.0, 1.0)
		var ident: Dictionary = Art.team_identity(0 if k < team_a.size() else 1)
		lbl.text = "%s %s  %d%%" % [str(ident["badge"]), _unit_name(k), int(round(frac * 100.0))]
		# A hit taken off-screen FLARES. Without it the pip is a roster listing, not a report.
		var since: float = t - float(_hit_at.get(k, -999.0))
		var hot: bool = since >= 0.0 and since < CAM_HIT_MEMORY
		lbl.add_theme_color_override("font_color",
			Color(1.0, 0.55, 0.45) if hot else (ident["colour"] as Color).lerp(Color.WHITE, 0.55))
		panel.size = Vector2.ZERO   # let it shrink to content
		var half: Vector2 = panel.size * 0.5
		panel.position = Vector2(
			clampf(sp.x - half.x, 4.0, maxf(4.0, vp.x - panel.size.x - 4.0)),
			# Below the scoreboard band, for the same reason the plates are.
			clampf(sp.y - half.y, HUD_RESERVE_Y, maxf(HUD_RESERVE_Y, vp.y - panel.size.y - 4.0)))


func _ensure_pip(k: int) -> Dictionary:
	if _pips.has(k):
		return _pips[k]
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.05, 0.86)
	sb.set_corner_radius_all(4)
	sb.border_color = Art.team_identity(0 if k < team_a.size() else 1)["colour"]
	sb.set_border_width_all(2)
	sb.content_margin_left = 6; sb.content_margin_right = 6
	sb.content_margin_top = 1; sb.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.visible = false
	plates_root.add_child(panel)
	var lbl := Label.new()
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 3)
	panel.add_child(lbl)
	_pips[k] = {"panel": panel, "label": lbl}
	return _pips[k]


var _leaders := {}   # unit idx -> Line2D connecting a lifted plate to its own unit

func _set_leader(k: int, on: bool, from_px: Vector2, to_px: Vector2) -> void:
	var ln: Line2D = _leaders.get(k)
	if ln == null:
		if not on:
			return
		ln = Line2D.new()
		ln.width = 2.0
		ln.default_color = Color(Art.team_identity(0 if k < team_a.size() else 1)["colour"], 0.0)
		ln.z_index = -1     # under the plates, over the world
		plates_root.add_child(ln)
		_leaders[k] = ln
	ln.visible = on
	if not on:
		return
	ln.points = PackedVector2Array([from_px, to_px])
	# Fades with distance: a short connector is barely there, a long one has to be findable.
	var d: float = from_px.distance_to(to_px)
	var col: Color = Art.team_identity(0 if k < team_a.size() else 1)["colour"]
	ln.default_color = Color(col.lerp(Color.WHITE, 0.5), clampf(0.22 + d / 900.0, 0.22, 0.72))


func _drain_log(upto: int) -> void:
	while logged_upto < upto and logged_upto < event_log.size():
		_log_event(event_log[logged_upto])
		logged_upto += 1


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# SCRUB — going BACK.
#
# ⚠️ "COMMIT, THEN OBSERVE" IS UNDERMINED IF THE OBSERVATION IS ONE-SHOT. `docs/WATCH_AUDIT.md`
# measured first blood at 46% of the fight with the match resolving in the ten seconds after it;
# a viewer who looks away once has missed the entire decisive exchange, and the moment they think
# "wait, why did that happen?" the answer is already gone. Speed and pause existed; there was no
# way back. The replay is an ARRAY OF FRAMES, so there is no reason for that except that nobody
# built it.
#
# ⚠️ SEEKING BACKWARDS MUST UNDO EVERYTHING THE FORWARD PASS DID ONCE. Three kinds of state are
# one-way: the text log (`logged_upto` only climbs), the death topple (a tween that rotates a body
# and hides its plate), and the director's memory. All three are rebuilt here. And the log rebuild
# runs with the EFFECT LAYER MUTED — replaying 130 events to catch up must not fire 130 bursts,
# 130 floats and 130 camera punches in one frame, which is what a naive re-drain does.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

var _fx_muted := false
var scrub: HSlider = null

func _seek(seconds: float) -> void:
	if frames.is_empty():
		return
	var last: float = float(frames.size() - 1)
	var target: float = clampf(seconds / NewSim.DT, 0.0, last)
	var backwards: bool = target < frame_pos
	frame_pos = target
	_seen_tick = -1
	opening_timer = OPENING_HOLD    # a scrub means the player is past the opening beat
	if backwards:
		_undo_deaths()
		banner.visible = false
	# Rebuild the read-back log from scratch, silently.
	var stash = vfx
	_fx_muted = true
	vfx = null
	# ⚠️ The mixer is fight-local: a cast rise in flight and the running damage reference both
	# belong to the stretch being scrubbed away. `_fx_muted` already stops the catch-up drain
	# from firing cues (`_play_tick_audio` checks it); this clears what was already sounding.
	if _audio != null:
		_audio.reset()
	log_view.clear()
	logged_upto = 0
	_last_intent.clear()
	_recent_hits.clear()
	_float_recent.clear()
	var upto := 0
	var now_t: float = target * NewSim.DT
	while upto < event_log.size() and float(event_log[upto].get("t", 0.0)) <= now_t:
		upto += 1
	_drain_log(upto)
	vfx = stash
	_fx_muted = false
	_apply_frame(frame_pos)
	_update_watch_surfaces()
	playing = target < last
	_snap_log()


## Put every toppled body back on its feet. Called only when the player scrubs BACKWARDS past a
## death — a corpse that stays down while its HP bar reads 80% is a worse lie than no scrub.
func _undo_deaths() -> void:
	for k in range(nodes.size()):
		var nd: Dictionary = nodes[k]
		if not bool(nd.get("dead", false)):
			continue
		nd["dead"] = false
		_death_at.erase(k)
		_hit_at.erase(k)
		# ⚠️ KILL THE TOPPLE TWEEN FIRST. It is still animating rotation/alpha for up to 0.45s and
		# would silently re-apply them over the reset a frame later.
		var tw = nd.get("topple_tw")
		if tw != null and is_instance_valid(tw) and tw.is_valid():
			tw.kill()
		nd["topple_tw"] = null
		(nd["plate"] as Control).modulate = Color(1, 1, 1, 1)
		var spr = nd.get("sprite")
		if spr != null:
			spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			spr.rotation_degrees.z = 0.0
			spr.position = Vector3(0, UNIT_HEIGHT * 0.5, 0)
			spr.modulate = Color(1, 1, 1, 1)
		nd["_state_sig"] = ""    # force the intent glyph and animator state to re-sync
	for th in _tethers:
		var im = (th as Dictionary)["node"]
		if is_instance_valid(im):
			im.queue_free()
	_tethers.clear()


func _log_event(e: Dictionary) -> void:
	match e.get("kind", ""):
		"start":
			log_view.append_text("[color=#d9b957]The fight begins.[/color]\n")
		"hit":
			var col := "#ffcf5c" if e.get("crit", false) else "#e6e6ec"
			log_view.append_text("[color=%s]%s → %s: %s (%d)%s[/color]\n" % [col, e["attacker"], e["target"], e["move"], e["dmg"], "  CRIT" if e.get("crit", false) else ""])
		"miss":
			log_view.append_text("[color=#8a8a92]%s's %s missed %s[/color]\n" % [e["attacker"], e["move"], e["target"]])
		"status_apply":
			log_view.append_text("[color=#c98a3a]%s is now %s[/color]\n" % [e["unit"], e["status"]])
			# A launched body is a spatial event, and text in a side log does not read at fight
			# speed. ⚠️ THE `"taunt"` ARM OF THIS BRANCH WAS DEAD CODE AND HAS BEEN REMOVED —
			# taunt is not a `fieldStatus`, so `status_applied` never carries it and this could
			# not fire. It is handled by the real `taunted` event below. Leaving a plausible-
			# looking branch in place is exactly how the mechanic stayed invisible through four
			# rounds of presentation work (`docs/WATCH_AUDIT.md` §4).
			var stk := str(e.get("status", ""))
			if stk == "knockback":
				var stid := _index_of_unit_named(str(e.get("unit", "")))
				if stid >= 0:
					_float_text(stid, "LAUNCHED", Color(0.80, 0.60, 0.95))
					if vfx != null:
						vfx.burst((nodes[stid]["holder"] as Node3D).position + Vector3(0, 0.5, 0),
							"dust", Color(0.75, 0.68, 0.55), 1.5, 14)
		"status_expire":
			log_view.append_text("[color=#6f6f77]%s's %s wears off[/color]\n" % [e["unit"], e["status"]])
		"buff":
			log_view.append_text("[color=#7fd0a0]%s's %s aids %s[/color]\n" % [e["caster"], e["move"], e["unit"]])
			# THE BUFF GRAMMAR: ring under every affected monster, charge on the caster. The sim
			# emits one buff event PER AFFECTED UNIT, so a team buff rings exactly who it touched.
			if vfx != null:
				var bid := _index_of_unit_named(str(e.get("unit", "")))
				var bcid := _index_of_unit_named(str(e.get("caster", "")))
				if bid >= 0:
					var bmv: Dictionary = _move_by_name.get(str(e.get("move", "")), {})
					var bcaster: Vector3 = (nodes[bcid]["holder"] as Node3D).position if bcid >= 0 else (nodes[bid]["holder"] as Node3D).position
					vfx.play_ability(bmv if not bmv.is_empty() else {"name": "", "type": "buff", "channel": "support", "target": "ally"},
						bcaster + Vector3(0, UNIT_HEIGHT * 0.5, 0),
						(nodes[bid]["holder"] as Node3D).position, false)
		# ⚠️ heal and cleanse were MISSING from this dispatch, so the two effects fixed on
		# 2026-08-05 — friendly effects and healing, neither of which worked in either engine
		# before that day — would have landed invisibly. In a game the player only WATCHES, an
		# effect with no line in the log did not happen as far as they are concerned.
		"heal":
			var blocked: bool = bool(e.get("healblocked", false))
			log_view.append_text("[color=#7fd0a0]%s's %s heals %s for %d%s[/color]
" % [
				e["caster"], e["move"], e["unit"], int(e.get("amount", 0)),
				" (healblocked)" if blocked else ""])
			# ⚠️ Float it ON THE UNIT too, not only in the log. Damage already floats; a heal that
			# only ever appears as a line of text reads as bookkeeping rather than as something
			# that happened to a creature you are watching.
			var hid := _index_of_unit_named(str(e["unit"]))
			if hid >= 0:
				_float_text(hid, "+%d" % int(e.get("amount", 0)), Color(0.50, 0.82, 0.63))
				if vfx != null:
					vfx.heal_rise((nodes[hid]["holder"] as Node3D).position)
					vfx.aura_pulse((nodes[hid]["holder"] as Node3D).position, Color(0.50, 0.82, 0.63))
		"cleanse":
			# The most dramatic counter-play in the game: breaking hard control off a pinned ally.
			# Gold, because it is a save, not routine upkeep.
			var broke: Array = e.get("broke", [])
			log_view.append_text("[color=#d8b859]%s's %s frees %s from %s[/color]
" % [
				e["by"], e["move"], e["unit"], ", ".join(PackedStringArray(broke))])
			# Gold, and it says FREED rather than the status name — the player needs to read the
			# save at a glance, and which particular control broke is in the log line beside it.
			var cid := _index_of_unit_named(str(e["unit"]))
			if cid >= 0:
				_float_text(cid, "FREED", Color(0.85, 0.72, 0.35))
		# ── the 2026-08-06 mechanics — every one of these existed in the sim before it existed
		# on screen, and "an effect with no line in the log did not happen as far as the player
		# is concerned" (the heal/cleanse lesson, same file, one day earlier). ──
		"interrupt":
			log_view.append_text("[color=#ff8a5c]%s's %s is INTERRUPTED — %s[/color]\n" % [
				e.get("unit", "?"), e.get("move", "?"), e.get("reason", "")])
			var iid := _index_of_unit_named(str(e.get("unit", "")))
			if iid >= 0:
				_float_text(iid, "INTERRUPTED", Color(1.0, 0.54, 0.36))
				if vfx != null:
					vfx.burst((nodes[iid]["holder"] as Node3D).position + Vector3(0, UNIT_HEIGHT * 0.7, 0),
						"twirl", Color(1.0, 0.54, 0.36), 1.1, 10)
				# ⚠️ THE PLATER INTERRUPT FLASH: the cast bar does not vanish — it fills grey,
				# says "Interrupted", holds ~0.7s, THEN goes. A bar that silently disappears is
				# ambiguous (finished? cancelled?); the grey flash is the unambiguous "denied".
				var ind: Dictionary = nodes[iid]
				ind["cast_flash_until"] = Time.get_ticks_msec() + 700
				(ind["cast_fill"] as ColorRect).color = Color(0.55, 0.55, 0.60)
				(ind["cast_fill"] as ColorRect).size = Vector2(174.0, 17)
				(ind["cast_lbl"] as Label).text = "Interrupted"
		"cast_steady":
			log_view.append_text("[color=#d8b859]%s shrugs off the interrupt — %s continues[/color]\n" % [
				e.get("unit", "?"), e.get("move", "?")])
			var sid := _index_of_unit_named(str(e.get("unit", "")))
			if sid >= 0:
				_float_text(sid, "STEADY", Color(0.85, 0.72, 0.35))
				if vfx != null:
					vfx.burst((nodes[sid]["holder"] as Node3D).position + Vector3(0, 0.4, 0),
						"circle", Color(0.85, 0.72, 0.35), 1.4, 6)
		"detonate":
			log_view.append_text("[color=#ff9f45]%s[/color]\n" % e.get("reason", "a status detonates"))
			var did := _index_of_unit_named(str(e.get("unit", "")))
			if did >= 0:
				_float_text(did, "DETONATED", Color(1.0, 0.62, 0.27))
				if vfx != null:
					var dpos: Vector3 = (nodes[did]["holder"] as Node3D).position + Vector3(0, UNIT_HEIGHT * 0.5, 0)
					vfx.burst(dpos, "flare", Color(1.0, 0.62, 0.27), 1.8, 14)
					vfx.burst(dpos, "scorch", Color(0.9, 0.45, 0.2), 1.2, 6)
		"contagion":
			log_view.append_text("[color=#8fbf6a]☣ %s[/color]\n" % e.get("reason", "a status spreads"))
			var cgid := _index_of_unit_named(str(e.get("unit", "")))
			if cgid >= 0:
				_float_text(cgid, "INFECTED", Color(0.56, 0.75, 0.42))
				if vfx != null:
					vfx.burst((nodes[cgid]["holder"] as Node3D).position + Vector3(0, UNIT_HEIGHT * 0.5, 0),
						"smoke", Color(0.56, 0.75, 0.42), 1.2, 12)
		# ── the four kinds `docs/WATCH_AUDIT.md` §4 found silent, in its priority order ──
		"taunted":
			log_view.append_text("[color=#f08c4a]%s's taunt drags %s onto it (%.1fs)[/color]\n" % [
				e.get("by", "?"), e.get("unit", "?"), float(e.get("seconds", 0.0))])
			var tvid := _index_of_unit_named(str(e.get("unit", "")))
			var tbid := _index_of_unit_named(str(e.get("by", "")))
			if tvid >= 0:
				_float_text(tvid, "TAUNTED", Color(0.94, 0.55, 0.28))
				# ⚠️ THE TETHER IS THE POINT, NOT THE FLOAT. What a viewer cannot otherwise explain
				# is not that a monster is taunted, it is that it TURNED AROUND — so the line has
				# to say WHO pulled it. A float alone leaves the "why" unanswered, which is the
				# failure the whole legibility rule exists to prevent.
				if tbid >= 0:
					_tether(tvid, tbid, Color(0.96, 0.58, 0.26), 1.4)
				if vfx != null:
					vfx.burst((nodes[tvid]["holder"] as Node3D).position + Vector3(0, UNIT_HEIGHT * 0.6, 0),
						"twirl", Color(0.96, 0.58, 0.26), 1.3, 10)
		"aoe":
			var n_t: int = int(e.get("targets", 0))
			log_view.append_text("[color=#ff9f45]%s's %s bursts over %d %s[/color]\n" % [
				e.get("caster", "?"), e.get("move", "?"), n_t,
				"body" if n_t == 1 else "bodies"])
			_aoe_burst((e.get("centre", Vector2.ZERO) as Vector2), float(e.get("radius", 0.0)), n_t)
		"fizzle":
			log_view.append_text("[color=#8a8a92]%s's %s fizzles — nothing in reach[/color]\n" % [
				e.get("unit", "?"), e.get("move", "?")])
			var fid := _index_of_unit_named(str(e.get("unit", "")))
			if fid >= 0:
				# The same unambiguous "denied" grammar the interrupt already uses — a bar that
				# vanishes silently is the ambiguity, not the fizzle.
				var fnd: Dictionary = nodes[fid]
				fnd["cast_flash_until"] = Time.get_ticks_msec() + 700
				(fnd["cast_fill"] as ColorRect).color = Color(0.42, 0.42, 0.47)
				(fnd["cast_fill"] as ColorRect).size = Vector2(174.0, 17)
				(fnd["cast_lbl"] as Label).text = "No target"
				_float_text(fid, "FIZZLED", Color(0.72, 0.72, 0.78))
		"debuff":
			log_view.append_text("[color=#b98ad8]%s's %s weakens %s (%.1fs)[/color]\n" % [
				e.get("by", "?"), e.get("move", "?"), e.get("unit", "?"),
				float(e.get("seconds", 0.0))])
			var dbid := _index_of_unit_named(str(e.get("unit", "")))
			if dbid >= 0:
				_float_text(dbid, "WEAKENED", Color(0.76, 0.58, 0.90))
				if vfx != null:
					# Mirrors the buff grammar deliberately — same ring, opposite hue — so the two
					# read as one vocabulary with a sign, not as two unrelated effects.
					vfx.aura_pulse((nodes[dbid]["holder"] as Node3D).position, Color(0.66, 0.46, 0.86))
		"thorns":
			log_view.append_text("[color=#c9d16a]%s's barbs bite %s back for %d[/color]\n" % [
				e.get("by", "?"), e.get("unit", "?"), int(e.get("dmg", 0))])
			var thid := _index_of_unit_named(str(e.get("unit", "")))
			var thby := _index_of_unit_named(str(e.get("by", "")))
			if thid >= 0:
				# ⚠️ THE TETHER RUNS BACKWARDS ON PURPOSE — from the DEFENDER to the ATTACKER,
				# which is the direction the damage travelled. It is the only arrow on the board
				# that points the other way, and that is exactly what makes thorns readable: the
				# viewer just watched a hit go left-to-right and now watches HP leave the striker.
				# `↩` and a half-size label: the reflect is a CONSEQUENCE of a blow the viewer
				# already saw, so it must not compete with that blow's own number.
				_float_text(thid, "↩%d" % int(e.get("dmg", 0)), Color(0.79, 0.82, 0.42), 0.5)
				if thby >= 0:
					_tether(thby, thid, Color(0.79, 0.82, 0.42), 0.35)
		"ward_soak":
			log_view.append_text("[color=#7fd4e8]%s's ward absorbs %d[/color]\n" % [
				e.get("unit", "?"), int(e.get("amount", 0))])
			var wsid := _index_of_unit_named(str(e.get("unit", "")))
			if wsid >= 0:
				# Damage that lands and does nothing is indistinguishable from a miss without
				# this. Glassy blue is the ward's own colour everywhere else on the screen.
				_float_text(wsid, "◈%d" % int(e.get("amount", 0)), Color(0.50, 0.83, 0.91), 0.55)
				if vfx != null:
					vfx.aura_pulse((nodes[wsid]["holder"] as Node3D).position, Color(0.50, 0.83, 0.91))
		"death":
			log_view.append_text("[color=#ff5f5f]%s falls![/color]\n" % e["unit"])
			_punch(0.55, 0.45)
	call_deferred("_snap_log")


func _snap_log() -> void:
	var bar := log_scroll.get_v_scroll_bar()
	if bar != null:
		log_scroll.scroll_vertical = int(bar.max_value)


func _finish() -> void:
	# ⚠️ HERE, NOT IN `_adapt_result`. The report screen and the career read the monster objects
	# and need the fight's final state on them; the REPLAY needs them untouched until it is over.
	# Both are satisfied by writing back at the end. `docs/WATCH_AUDIT.md` §1.
	_write_back_final(frames)
	var w: String = result.get("winner", "draw")
	banner_title.text = "Your team wins!" if w == "A" else ("The rival wins." if w == "B" else "Draw.")
	banner_sub.text = "%d vs %d standing — %.1fs" % [
		result.get("survivorsA", 0), result.get("survivorsB", 0), result.get("duration", 0.0)]
	banner.visible = true
	var ReportScript = load("res://scripts/ui/report_ui.gd")
	ReportScript.hand_off(result, team_a, team_b)
	_offer_cup_continuation(w == "A")


## If this fight was fought as part of a live cup run (`CupRun`), record the round's outcome and
## offer the player a way forward — another round's tactics screen, or, once every round is
## fought, the cup's final result (`tournament.tscn`, which pays the purse and applies promotion
## via `CupRun.finish() -> Career.apply_tournament_outcome()`). Standalone fights (no cup active)
## are untouched — same "See the report"/"Back to the Stable" pair as always.
func _offer_cup_continuation(won: bool) -> void:
	var cup := get_node_or_null("/root/CupRun")
	if cup == null or not cup.active:
		return
	cup.record_round_result(won)
	var cont := Button.new()
	cont.custom_minimum_size = Vector2(0, 36)
	if cup.is_finished():
		cont.text = "See cup results  →"
		cont.pressed.connect(func():
			cup.finish()
			get_tree().change_scene_to_file("res://scenes/tournament.tscn"))
	else:
		cont.text = "Next round (%d of %d)  →" % [cup.current_round + 1, cup.rival_count]
		cont.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/tactics.tscn"))
	banner_box.add_child(cont)


func _skip() -> void:
	if not frames.is_empty():
		frame_pos = float(frames.size() - 1)
		_apply_frame(frame_pos)
	_drain_log(event_log.size())
	for k in range(nodes.size()):
		if not _alive_now(k):
			_topple(k)
	playing = false
	_finish()


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# OVERLAY
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _build_overlay() -> void:
	overlay = CanvasLayer.new()
	add_child(overlay)
	plates_root = Control.new()
	plates_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plates_root.anchor_right = 1; plates_root.anchor_bottom = 1
	overlay.add_child(plates_root)

	var ui := Control.new()
	ui.anchor_right = 1; ui.anchor_bottom = 1
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(ui)

	var header := Label.new()
	header.position = Vector2(20, 12)
	header.text = "%s League" % league_name
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", Color(0.87, 0.74, 0.36))
	ui.add_child(header)

	# Say plainly which engine produced what is on screen — a viewer should never have to guess
	# whether they are watching the real simulation or the non-spatial fallback. Populated by
	# `_update_mode_label()` once the (now async) fight has actually resolved — built here only as
	# a placeholder so the label exists for that later call.
	mode_label = Label.new()
	mode_label.position = Vector2(20, 42)
	mode_label.add_theme_font_size_override("font_size", 11)
	mode_label.add_theme_color_override("font_color", Color(0.55, 0.58, 0.64))
	mode_label.text = "resolving…"
	ui.add_child(mode_label)

	resolving_label = Label.new()
	resolving_label.anchor_right = 1; resolving_label.anchor_bottom = 1
	resolving_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resolving_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	resolving_label.text = "Resolving the fight…"
	resolving_label.add_theme_font_size_override("font_size", 22)
	resolving_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.90))
	resolving_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resolving_label.visible = false
	ui.add_child(resolving_label)

	var hint := Label.new()
	hint.position = Vector2(20, 60)
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.50, 0.53, 0.60))
	# ⚠️ Every control this screen has, stated on this screen. The camera toggle and the replay
	# speed keys exist because neither camera and no single speed is right for every moment — a
	# tension that is measured, not a preference — and a control the player cannot discover is the
	# same as one that does not exist.
	hint.text = "Tab / click a nameplate for its orders · Esc close · C camera (Action/Team/Arena) · drag to pan, wheel to zoom · Space pause · [ ] speed · ← → rewind 3s"
	ui.add_child(hint)

	callout = PanelContainer.new()
	callout.visible = false
	callout.custom_minimum_size = Vector2(300, 0)
	callout.position = Vector2(20, 84)
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.04, 0.04, 0.06, 0.96)
	csb.border_color = Color(0.87, 0.74, 0.36)
	csb.set_border_width_all(2)
	csb.set_corner_radius_all(6)
	csb.content_margin_left = 12; csb.content_margin_right = 12
	csb.content_margin_top = 10; csb.content_margin_bottom = 10
	callout.add_theme_stylebox_override("panel", csb)
	callout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(callout)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	callout.add_child(cv)
	callout_title = Label.new()
	callout_title.add_theme_font_size_override("font_size", 18)
	callout_title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.97))
	cv.add_child(callout_title)
	callout_body = RichTextLabel.new()
	callout_body.bbcode_enabled = true
	callout_body.fit_content = true
	callout_body.custom_minimum_size = Vector2(280, 0)
	callout_body.add_theme_font_size_override("normal_font_size", 14)
	callout_body.add_theme_color_override("default_color", Color(0.90, 0.90, 0.93))
	cv.add_child(callout_body)

	var strip := HBoxContainer.new()
	strip.anchor_top = 1.0; strip.anchor_bottom = 1.0
	strip.anchor_left = 0.0; strip.anchor_right = 1.0
	strip.offset_top = -132; strip.offset_left = 16; strip.offset_right = -16; strip.offset_bottom = -12
	strip.add_theme_constant_override("separation", 12)
	ui.add_child(strip)

	var log_panel := PanelContainer.new()
	log_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lsb := StyleBoxFlat.new()
	lsb.bg_color = Color(0.04, 0.04, 0.06, 0.82)
	lsb.set_corner_radius_all(5)
	lsb.content_margin_left = 10; lsb.content_margin_right = 10
	lsb.content_margin_top = 6; lsb.content_margin_bottom = 6
	log_panel.add_theme_stylebox_override("panel", lsb)
	strip.add_child(log_panel)
	log_scroll = ScrollContainer.new()
	log_panel.add_child(log_scroll)
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.fit_content = true
	log_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(log_view)

	var ctrl := VBoxContainer.new()
	ctrl.custom_minimum_size = Vector2(230, 0)
	ctrl.add_theme_constant_override("separation", 5)
	strip.add_child(ctrl)
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 4)
	ctrl.add_child(speeds)
	for s in SPEED_OPTIONS:
		var b := Button.new()
		b.text = ("%.1fx" % s) if s < 1.0 else ("%dx" % int(s))
		b.custom_minimum_size = Vector2(50, 28)
		b.pressed.connect(func(): speed = s)
		speeds.add_child(b)
	# ── THE SCRUB. `docs/WATCH_AUDIT.md`: first blood lands at 46% and the match resolves in the
	# ten seconds after it, so a viewer who looks away once has missed the fight. The replay is an
	# array of frames; going back costs almost nothing and is the difference between a fight you
	# watched and a fight you can STUDY. ──
	scrub = HSlider.new()
	scrub.custom_minimum_size = Vector2(0, 20)
	scrub.min_value = 0.0
	scrub.step = 0.05
	scrub.value_changed.connect(func(v):
		if scrub.has_focus() or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_seek(float(v)))
	ctrl.add_child(scrub)
	var jump := HBoxContainer.new()
	jump.add_theme_constant_override("separation", 4)
	ctrl.add_child(jump)
	var b_back := Button.new()
	b_back.text = "◀ 3s"
	b_back.custom_minimum_size = Vector2(56, 26)
	b_back.pressed.connect(func(): _seek(frame_pos * NewSim.DT - 3.0))
	jump.add_child(b_back)
	var b_fwd := Button.new()
	b_fwd.text = "3s ▶"
	b_fwd.custom_minimum_size = Vector2(56, 26)
	b_fwd.pressed.connect(func(): _seek(frame_pos * NewSim.DT + 3.0))
	jump.add_child(b_fwd)

	var skip := Button.new()
	skip.text = "Skip to result"
	skip.pressed.connect(_skip)
	ctrl.add_child(skip)
	var back := Button.new()
	back.text = "Back to the Stable"
	back.pressed.connect(func():
		var cup := get_node_or_null("/root/CupRun")
		if cup != null and cup.active:
			cup.cancel()
		get_tree().change_scene_to_file("res://scenes/stable.tscn"))
	ctrl.add_child(back)

	banner = PanelContainer.new()
	banner.anchor_left = 0.30; banner.anchor_right = 0.70
	banner.anchor_top = 0.34; banner.anchor_bottom = 0.34
	banner.offset_bottom = 140
	var bsb2 := StyleBoxFlat.new()
	bsb2.bg_color = Color(0.05, 0.05, 0.07, 0.94)
	bsb2.border_color = Color(0.87, 0.74, 0.36)
	bsb2.set_border_width_all(2)
	bsb2.set_corner_radius_all(8)
	bsb2.content_margin_top = 14; bsb2.content_margin_bottom = 14
	banner.add_theme_stylebox_override("panel", bsb2)
	banner.visible = false
	ui.add_child(banner)
	var bv := VBoxContainer.new()
	banner.add_child(bv)
	banner_box = bv
	banner_title = Label.new()
	banner_title.add_theme_font_size_override("font_size", 28)
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(banner_title)
	banner_sub = Label.new()
	banner_sub.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bv.add_child(banner_sub)
	var rb := Button.new()
	rb.text = "See the report  →"
	rb.custom_minimum_size = Vector2(0, 36)
	rb.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/report.tscn"))
	bv.add_child(rb)
