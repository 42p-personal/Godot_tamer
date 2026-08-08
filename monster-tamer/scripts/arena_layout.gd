## THE ARENA LAYOUT GENERATOR — cover and obstacles a fight is actually fought around.
##
## ⚠️ STREAM C OF THE SPATIAL FAN-OUT (`docs/SPATIAL_HANDOFF.md` §4C). This file is owned
## exclusively by this stream — do not fold sim or AI logic in here, and nothing in here may
## reach into `spatial_sim.gd` / `spatial_ai.gd`.
##
## Sources for every rule below (nothing here is invented fresh):
##   `docs/ARENA_DESIGN.md`     — the density law, "every arena is one built place", what
##                                cover is FOR, and why boards are 180°-symmetric but must not
##                                LOOK symmetric.
##   `docs/ARENA_BLUEPRINT.md`  §7, §11 — the annulus placement rule (cover sits between the
##                                TIGHT and LOOSE leash radii) and the per-team-size density
##                                ceilings, explicitly flagged there as EXTRAPOLATED.
##   `docs/SPATIAL_COMBAT_DESIGN.md` — cover as a graded accuracy debuff, and the grade
##                                vocabulary (`soft` / `hard` / `blocking`) that `Spatial`
##                                already reads in `cover_between`.
##
## ⚠️ DETERMINISM: every random choice below comes from the INJECTED `rng`. No `randf()`, no
## `Array.shuffle()` (reseeds from global state). Same seed + same inputs -> identical layout,
## always — `docs/SPATIAL_HANDOFF.md` §1.
class_name ArenaLayout
extends RefCounted

## ⚠️ PRELOAD, NOT THE BARE `Spatial` CLASS NAME.
## The global script-class cache is COLD under `--headless --script` and during early autoload
## boot, so `Sp.foo()` fails to parse with "Identifier not declared in the current scope"
## even though the class_name is real. This project has now hit that trap three times; it is
## documented in `.claude/docs/technical-preferences.md`. `preload()` resolves the file directly
## and sidesteps the cache entirely.
const Sp = preload("res://scripts/spatial.gd")

# ═══════════════════════════════════════════════════════════════════════════════════════════════
# TUNABLES
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## ⚠️ EXTRAPOLATED, NOT VALIDATED. `ARENA_BLUEPRINT.md` §7: 300 was measured on Tin/Bronze
## boards an order of magnitude smaller than the new 5v5 ground (14,080 sq units) and is being
## applied "roughly 3-5x outside the size range it was measured on". Treat the ceiling this
## produces as a CEILING TO CHECK AGAINST, never a target to author toward — see `_target_pairs`
## below, which generates to a fraction of it on purpose.
## ⚠️ AND IT NOW CARRIES `GEOMETRY_SCALE` SQUARED, BECAUSE IT IS AN AREA. Measured before the
## change: cover fraction held at 1.3-1.4% across every team size, so the LAW is sound — an
## area-proportional rule is scale-free by construction and the growing piece COUNT was never the
## problem. What broke is that piece SIZES are body-relative (see `KIND_TABLE`) and the body grew,
## so scaling the footprints without scaling this would have quadrupled the covered fraction to
## ~7% and buried the ground in cover. Both move together or neither should.
const AREA_PER_PIECE := 300.0 * Sp.GEOMETRY_SCALE * Sp.GEOMETRY_SCALE

## How far under the (extrapolated) ceiling to actually generate. 1.8 means ~55% of the ceiling
## — a deliberate margin so an uncertain formula doesn't get treated as a precise budget.
const DENSITY_SAFETY_FACTOR := 1.8

## Obstacles must sit fully this far inside the ground's own edge. The VENUE (stands, crowd)
## begins past the ground entirely (`ARENA_BLUEPRINT.md` §6) — nothing playable should hug the
## boundary line itself.
const EDGE_MARGIN := 2.0

## Extra buffer added AROUND each deploy band's own geometry before cover is excluded from it.
## `Sp.deploy_positions` staggers alternating ranks by ±3 units, so a piece sitting exactly
## on the band's edge could still end up under a spawned unit.
const DEPLOY_CLEARANCE_MARGIN := 3.0

## Minimum clear gap kept between any two obstacles' bounding boxes — pieces that touch read as
## one lumpy shape instead of two decisions.
const PIECE_GAP := 1.0

const MAX_PLACEMENT_ATTEMPTS := 600

const SYMMETRY_EPS := 0.01

## ⚠️ NOT SCALED BY `Sp.ground_scale`, BUT SCALED BY `Sp.GEOMETRY_SCALE` — and the difference is
## the whole point. Obstacle footprint is a body-to-body question, like `DEPLOY_DEPTH`: a
## monster's collision radius does not change because the GROUND grew, so a barrel should not
## either. That reasoning is still right. Its PREMISE changed: the body itself grew, from a 1.8
## unit diameter to 4.4, when real geometry replaced billboarded sprites.
##
## ⚠️ MEASURED CONSEQUENCE OF LEAVING THEM ALONE: eight of the nine kinds below became NARROWER
## THAN A MONSTER — a "blocking" pillar at 0.64 body diameters, a barrel at 0.55, a shrine at
## 0.45. Cover you are wider than does not hide you, so every grade below `low_wall` had quietly
## stopped being cover at all while still costing its place in the density budget. The eighth
## instance this session of a bare world-distance that the board moved underneath.
##
## Sizes still stay fixed across every TEAM SIZE; only WHERE they can go (the annulus) and HOW
## MANY (the density ceiling) scale with the ground.
##
## `kind` is a semantic tag only — the renderer (stream D/E) picks the mesh. The first five kinds
## are the ones named in the brief; the four below them came from the wider CC0 sweep
## (`docs/OBSTACLE_KIND_CANDIDATES.md`) that closed the one-kind-per-grade gap flagged at the
## mirror-pair roll: `hard` and `blocking` each have a second kind now, so symmetric pairs stop
## looking like copies. Footprints for the new kinds are from the measured import proportions
## (`_probe_obstacles.gd` output), not guessed. More kinds can still be added here without
## touching the placement logic.
## ⚠️ BLOCKING COVER IS NOW LONG WALLS, NOT SMALL PILLARS — and the reason is geometry, measured.
## A line of fire is tens of units long and crosses a lot of ground, so even eight small pillars
## intercepted 17.8% of all lines. A POSITION is a point, and the chance any given point sits in a
## pillar's shadow from a specific threat was about a third of one percent. Sparse blockers
## therefore produced denial and almost no protection: an obstacle to attacking, never a resource
## for defending, which is why cover-SEEKING measured as pure noise no matter what the AI did.
##
## A wall casts a long shadow. That single change is what gives a unit somewhere to actually stand,
## and it is the same change that makes the navmesh deflect a path by more than 1%.
##
## `pillar` and `shrine` drop to `hard` rather than being deleted: they still read as cover, still
## cost accuracy, and `ARENA_DESIGN.md` wants variety in the silhouette. They simply stop pretending
## to hide anyone.
## ⚠️ RESIZED 2026-08-08 — "THE ACCENT LAYER IS DEBRIS, NOT ARCHITECTURE". The integrator's read of
## eleven league frames, and `_probe_layout.gd` now puts a number on it: across the eleven boards,
## **the median board had 71% of its pieces small AND isolated**, and on nine of eleven leagues the
## cluster count EQUALLED the piece count — not one piece on those boards touched another. A
## hundred-odd near-identical half-body props spread evenly over a floor is a rash, and every
## existing guard passed it, because every existing guard measures quantity or difference-between-
## boards and none measured SHAPE.
##
## `ARENA_DESIGN.md` §3 already had the rule in words and no number behind it: ⚠️ "FEWER AND
## LARGER, ALWAYS. Five small pieces give a board where nothing fully blocks a lane and every
## position is about as good as every other — busy, with no decision in it."
##
## So the props grow to architectural scale. Sizes below are stated in BODY DIAMETERS in the
## trailing comment, because that is the unit the rule is written in and `2.0 * G` is not legible
## as "one body". The threshold that matters: `_probe_layout.gd` calls a piece SMALL under two
## bodies on its longest side, and only `barrel` and `crate` — the two TRADE kinds, which §2 caps
## at one or two per board — are now under it.
##
## ⚠️ THE KIND NAMES ARE DELIBERATELY UNCHANGED, and that is a constraint I accepted rather than a
## lack of ambition. `arena_3d.gd` carries a per-kind tint table calibrated last round out of
## measured frames (0 of 9 kinds were correct before it), plus a texture per kind. A brand-new kind
## arrives with no texture and an untuned tint — trading a measured value ladder for a bigger
## vocabulary. The rect is what the sim and the silhouette read; the mesh is stretched to it. So
## the vocabulary grows by SIZE and by ARRANGEMENT, both of which are mine, and not by name.
const G := Sp.GEOMETRY_SCALE
const KIND_TABLE := [
	# TRADE — §2 allows one or two pieces per board, "only where a working yard would keep them".
	# The only two kinds still under two bodies, so they are the only two that can ever measure as
	# debris; every board that uses them stacks them against something.
	{"kind": "barrel", "grade": "soft", "size": Vector2(2.4 * G, 2.4 * G)},   # 1.2 x 1.2 bodies
	{"kind": "crate", "grade": "soft", "size": Vector2(3.0 * G, 3.0 * G)},    # 1.5 x 1.5
	# FURNITURE — the things a built place stands out, long enough to read as a line.
	{"kind": "planter", "grade": "soft", "size": Vector2(4.8 * G, 3.0 * G)},  # 2.4 x 1.5
	{"kind": "bench", "grade": "soft", "size": Vector2(6.0 * G, 2.0 * G)},    # 3.0 x 1.0
	{"kind": "fence", "grade": "soft", "size": Vector2(9.0 * G, 1.2 * G)},    # 4.5 x 0.6
	# MASONRY — the building itself. A pillar is now a PIER: you can put a shoulder to it.
	{"kind": "boulder", "grade": "hard", "size": Vector2(4.6 * G, 3.8 * G)},  # 2.3 x 1.9
	{"kind": "pillar", "grade": "hard", "size": Vector2(4.2 * G, 4.2 * G)},   # 2.1 x 2.1
	{"kind": "shrine", "grade": "hard", "size": Vector2(4.4 * G, 4.4 * G)},   # 2.2 x 2.2
	# The two that break line of sight. Long on one axis and thin on the other, so they shelter a
	# whole approach from one angle while leaving it open from another — which is what makes taking
	# cover a DECISION rather than a place to stand.
	{"kind": "low_wall", "grade": "blocking", "size": Vector2(16.0 * G, 1.8 * G)},
	{"kind": "low_wall_border", "grade": "blocking", "size": Vector2(11.0 * G, 1.6 * G)},
]

## Material/palette per league. Leagues below Platinum have their own material identity
## (`src/tamerengine/themes.ts` carried the equivalent idea for the 2D renderer — the names below
## are freshly authored for this generator, not copied from it, since that file's asset paths
## don't exist on this side). Platinum and up are one interchangeable pool of grounds
## "differentiated by colour and material" (`CLAUDE.md`, `ARENA_DESIGN.md` §7), so those four
## leagues draw a palette from a shared list instead of owning one each.
const LEAGUE_MATERIAL := {
	"Wood": {"material": "timber", "palette": "warm oak"},
	"Copper": {"material": "ore_stone", "palette": "verdigris green"},
	"Tin": {"material": "wet_stone", "palette": "pale grey-blue"},
	"Bronze": {"material": "alloy_stone", "palette": "warm gold-brown"},
	"Iron": {"material": "forge_stone", "palette": "near-colourless black"},
	"Silver": {"material": "limestone", "palette": "dry pale neutral"},
	"Gold": {"material": "sandstone", "palette": "honey warm"},
}
const GRAND_CIRCUIT_LEAGUES := ["Platinum", "Masters", "Tamer Elite", "Tamers Apex"]
const GRAND_CIRCUIT_PALETTES := [
	"porphyry", "serpentine", "basalt", "alabaster", "slateyard", "travertine",
	"granite", "jasper", "amethystine", "malachite", "chequer", "mosaic",
	"rosestone", "onyx", "verdite",
]


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# GENERATION
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## Build one arena layout. Deterministic: same `team_size` + `league_name` + `rng` state ->
## identical `obstacles` and `theme`, always.
## ═══════════════════════════════════════════════════════════════════════════════════════════════
## NAMED LAYOUTS — compositions, not scatters (docs/ARENA_ETHOS_REVIEW.md, ARENA_SCALE_COMPARISON.md)
## ═══════════════════════════════════════════════════════════════════════════════════════════════
##
## ⚠️ SIXTEEN SHIPPED WoW ARENAS REDUCE TO FOUR COMPOSITIONS PLUS ART, and every one of them is
## describable in a sentence — "four pillars around an open centre". Ours was describable only as
## "twenty-four things". Blizzard's own stated aim for an arena is to *"eliminate randomness as
## much as possible"*; sampling positions from an rng does the opposite.
##
## ⚠️ AND THE PIECES ARE SIZED IN BODIES, NOT COPIED IN PROPORTION. This is the translation that
## matters and it is easy to get wrong by drawing the schematic to scale. In WoW player collision
## is negligible, so a whole team stacks behind ONE pillar and that pillar is team-sized cover. Our
## bodies are solid by design (`AUTOBATTLER_DESIGN.md` #10; `Sp.BODY_RADIUS` 2.2 keeps every pair
## 4.4 apart), so a 5-monster line needs 22 units of FRONTAGE. A Nagrand-proportioned pillar is
## 1.4 bodies wide here — it shelters one monster while the other four stand in the open. Major
## cover must therefore be >= a team's frontage or it is decoration.
##
## `MAJOR_MIN_BODIES` is that rule written down so the next layout cannot forget it.
## ⚠️ 5 -> 9 BODIES (studio owner: "the objects we have are not big enough in our arena at all").
## 5 bodies was derived as the minimum that shelters a 5-monster line — a FLOOR, and I shipped the
## floor as the size. Against the WoW schematics that is far too timid: a Nagrand pillar reads as
## roughly a tenth of the arena's width, and at 5 bodies ours was 7%. At 9 it is ~11%, which is
## the proportion the reference actually uses.
const MAJOR_MIN_BODIES := 9.0

## The prop kinds a named composition's BLOCKING majors cycle through, so one board does not read
## as four copies of the same object. Both are `blocking` in `KIND_TABLE`, so the cycle can never
## change what a piece does — only what it is made of. See `_build_named`.
const MAJOR_BLOCKING_KINDS := ["low_wall", "low_wall_border"]

## ⚠️ A MAJOR IS A FRACTION OF THE BOARD, NOT AN ABSOLUTE — and 9 bodies WAS that fraction, at
## 5v5 only. `MAJOR_MIN_BODIES × 4.4 = 39.6`, and the 5v5 ground is 440 wide, so the reference
## proportion the note above cites ("a Nagrand pillar reads as roughly a tenth of the arena's
## width") is exactly 9%. Every other team size got the same 39.6 unit wall on a smaller ground:
## on Wood's 220-wide board that is 18% of the width, and the measured consequence was a
## **10.2% covered floor** against the 2.55% the same composition produced at 5v5 — four times
## the cover, from one number that did not scale. `_probe_layout.gd` is the instrument that
## caught it.
##
## So the fraction is the rule and the body count is the FLOOR underneath it: cover must still be
## at least a team's frontage wide (`MIN_FRONTAGE_BODIES` per monster, plus a body of slack) or
## it shelters one monster while the rest of the line stands in the open.
const MAJOR_WIDTH_FRACTION := 0.09
const MIN_FRONTAGE_BODIES := 1.0

static func major_min_width() -> float:
	return MAJOR_MIN_BODIES * Sp.BODY_RADIUS * 2.0

## The same number, but honest about the board it is on. Kept alongside the no-argument version
## because that one is the 5v5 REFERENCE value and other streams may quote it.
static func major_min_width_for(team_size: int) -> float:
	var body := Sp.BODY_RADIUS * 2.0
	var frontage := (float(maxi(1, team_size)) * MIN_FRONTAGE_BODIES + 1.0) * body
	return maxf(frontage, MAJOR_WIDTH_FRACTION * Sp.ground_size(team_size).x)


## Each layout returns pieces in NORMALISED coordinates (0..1 across the ground) so one
## composition scales to every team size, and is mirrored about the SPAWN AXIS rather than rotated
## 180 degrees — mirror is the weaker constraint, it is what WoW actually uses, and it is the only
## one that admits odd counts like Robodrome's and Maldraxxus' three-piece triad.
const LAYOUTS := {
	# NAGRAND / TOL'VIRON / NOKHUDON / EMPYREAN — the workhorse. Four major blockers ringing an
	# open middle, so the centre is the killing ground and the cover is what you retreat TO.
	"four_pillar": {
		"centre": "open",
		"major": [
			{"at": Vector2(0.30, 0.27), "w": 1.0, "grade": "blocking"},
			{"at": Vector2(0.30, 0.73), "w": 1.0, "grade": "blocking"},
			{"at": Vector2(0.70, 0.27), "w": 1.0, "grade": "blocking"},
			{"at": Vector2(0.70, 0.73), "w": 1.0, "grade": "blocking"},
		],
		# Accents: small, cheap, and deliberately NOT paired with the majors — they add texture
		# and a reason to be somewhere, never a second tier of real cover.
		# ⚠️ AUTHORED AS THE CANONICAL HALF ONLY; the builder emits each one's 180-degree
		# partner with the SAME rect. They used to be authored as both halves, and each half rolled
		# its OWN kind from the grade pool — so a "pair" could be a 5.28-square barrel opposite a
		# 12.1x2.2 fence. The board was therefore NOT 180-degree symmetric, which is the one
		# property `ARENA_DESIGN.md` §5 calls non-negotiable, because an asymmetric board biases
		# every measurement taken on it. Nothing caught it: `problems()` had only ever been run
		# against the scatter path, which mirrors by construction. `_probe_layout.gd` catches it now.
		# ⚠️ ONE STAND, NOT TWO STRAYS. This used to be two single accents; emitted with their
		# partners that is four isolated small props, and the SAME four on all eleven leagues —
		# which `_probe_layout.gd` measured as the single largest shared contribution to the
		# debris count. A stand of three reads as a screen you can put a shoulder to; three
		# separate posts over the same floor read as things somebody left out.
		"accents": [
			{"at": Vector2(0.50, 0.13), "grade": "hard", "n": 3, "dir": Vector2(1, 0), "gap": 0.45},
		],
	},

	# RUINS OF LORDAERON / BLACK ROOK HOLD / CAGE OF CARNAGE — the OTHER half of the 8/8 split the
	# blueprints revealed. Here the centre IS the obstacle, so the middle is the prize rather than
	# the killing ground, and the fight is fought AROUND one dominant mass.
	#
	# ⚠️ The size hierarchy is the point (`ARENA_ETHOS_REVIEW.md` §1.4): one piece that defines the
	# map, then offset accents that only matter once you are committed. Lordaeron is "one central
	# tomb plus smaller tombstones"; ours is one central mass plus two offset ruins.
	"central_mass": {
		"centre": "occupied",
		"major": [
			{"at": Vector2(0.50, 0.50), "w": 1.55, "d": 0.62, "grade": "blocking"},
			# Offset, NOT a mirrored pair across the short axis — Black Rook Hold places its ruins
			# so each team meets one on its own approach. Still mirror-symmetric about the spawn
			# axis, so it stays fair.
			{"at": Vector2(0.27, 0.30), "w": 0.72, "d": 0.55, "grade": "blocking"},
			{"at": Vector2(0.73, 0.30), "w": 0.72, "d": 0.55, "grade": "blocking"},
			{"at": Vector2(0.27, 0.70), "w": 0.72, "d": 0.55, "grade": "blocking"},
			{"at": Vector2(0.73, 0.70), "w": 0.72, "d": 0.55, "grade": "blocking"},
		],
		"accents": [
			{"at": Vector2(0.50, 0.15), "grade": "hard", "n": 3, "dir": Vector2(1, 0), "gap": 0.45},
		],
	},

	# ROBODROME / MALDRAXXUS — the THREE-piece composition the blueprints singled out: a diagonal
	# triad, so no straight lane across the middle survives, and every approach must pick a side
	# of at least one pillar. Deliberately asymmetric-looking while staying mirror-fair: the
	# centre piece sits ON the axis of symmetry, the flankers mirror each other.
	"triad": {
		"centre": "occupied",
		"major": [
			{"at": Vector2(0.50, 0.50), "w": 1.1, "grade": "blocking"},
			{"at": Vector2(0.32, 0.68), "w": 1.0, "grade": "blocking"},
			{"at": Vector2(0.68, 0.32), "w": 1.0, "grade": "blocking"},
		],
		"accents": [
			{"at": Vector2(0.28, 0.22), "grade": "hard", "n": 2, "dir": Vector2(1, 1), "gap": 0.4},
			{"at": Vector2(0.50, 0.11), "grade": "soft", "n": 2, "dir": Vector2(1, 0), "gap": 0.4},
		],
	},

	# HOOK POINT / ENIGMA CRUCIBLE — LANES: two long walls parallel to the spawn axis divide the
	# board into a wide centre lane and two narrow wings. The read is entirely different from the
	# pillar maps: cover here is a WALL you commit to a side of, not an island you orbit, and the
	# wings are where duels and flanks happen while the centre carries the main line.
	"lanes": {
		"centre": "open",
		"major": [
			{"at": Vector2(0.38, 0.30), "w": 1.9, "d": 0.34, "grade": "blocking"},
			{"at": Vector2(0.62, 0.70), "w": 1.9, "d": 0.34, "grade": "blocking"},
		],
		"accents": [
			{"at": Vector2(0.50, 0.50), "grade": "hard", "n": 3, "dir": Vector2(0, 1), "gap": 0.4},
			{"at": Vector2(0.18, 0.74), "grade": "soft", "n": 2, "dir": Vector2(1, 0), "gap": 0.4},
		],
	},
}

# ════════════════════════════════════════════════
# LEAGUE BOARDS — eleven built places, not one composition in eleven colours
# ════════════════════════════════════════════════
#
# ⚠️ THE MEASURED PROBLEM THIS SOLVES, from `_probe_layout.gd` before the change:
#
#     every one of the eleven leagues generated **eight pieces**, one **signature**
#     (`c8/b1/k3/x8/y9`), and Bronze/Iron, Silver/Gold and Platinum/Masters/Tamer Elite/Tamers
#     Apex were **byte-identical geometry**. The whole ladder was one board re-lit.
#
# Two causes, both structural rather than anybody's oversight:
#   1. `arena_3d.gd` reads the composition out of the committed orders and defaults to
#      `"four_pillar"`, and nothing in the career path ever sets that key — so every league on
#      the ladder asked for the same family.
#   2. A family is authored in NORMALISED coordinates, so the same family on a bigger ground is
#      the same picture at a bigger size. Normalisation is what makes one composition portable;
#      it is also what makes eleven leagues identical.
#
# ⚠️ AND EIGHT PIECES WAS NOT A DENSITY-LAW VIOLATION, WHICH IS WHY NOTHING CAUGHT IT.
# `ARENA_DESIGN.md` §1 is a CEILING — "no more than one piece per 300 square units" — and eight
# pieces against a 5v5 ceiling of seventy-four passes with room to spare. The law has no floor,
# so an empty board is legal by every guard in the file. `_probe_layout.gd` adds the floor
# (half the generator's own scatter target) rather than leaving "reads as empty" to the eye.
#
# THE FIX IS A SECOND AXIS, NOT A SECOND TABLE. `LAYOUTS` still owns the FAMILY — the four
# compositions the WoW blueprints reduce to — and a caller that names one still gets it, so
# `watch.gd` and `_probe_newlayouts.gd` keep comparing families like for like. What is new is
# that the LEAGUE owns the built place standing in that family: how far the majors sit from
# centre, and the furniture layer that turns four slabs on an empty floor into a court, a
# cloister, a gatehouse or an obelisk field.
#
# ⚠️ EVERY ELEMENT BELOW IS AUTHORED IN THE CANONICAL HALF ONLY and emitted with its
# 180-degree partner (`_emit_pair`). That is what keeps the fairness `ARENA_DESIGN.md` §5 calls
# non-negotiable — it is a property of the EMITTER, so no author can forget it — while §5's
# other demand ("must not LOOK symmetric") is served by staggered depths and mixed prop kinds.
#
# ⚠️ PIECE COUNT CLIMBS WITH THE LADDER ON PURPOSE, ~12 at Wood to ~42 at Tamers Apex. It is a
# progression axis the game had lost (`ARENA_DESIGN.md` §7 concedes the plateau above Platinum
# is real), it costs nothing, and it guarantees eleven distinct signatures by construction
# rather than by an author's memory. Every count is checked against BOTH ends of the density
# law by `_probe_layout.gd`; none is authored to a round number.
#
# Element grammar — three shapes. `at` is always normalised 0..1 across the ground; `dir` is a
# WORLD direction, so a diagonal is a real diagonal and not one the ground's aspect ratio shears.
#   {"t": "post", "at": V2, "grade", "kind"}                      one piece + its partner
#   {"t": "run",  "at": V2, "dir": V2, "n": i, "gap": f(bodies),  a STRUCTURE: n pieces centred
#                 "grade", "kind"}                                on `at`, plus n partners
#   {"t": "bar",  "at": V2, "w": f, "d": f, "grade", "kind"}      authored geometry — a wall, a
#                                                                 gate jamb, a dais, and a partner
#
# ⚠️ `row` IS GONE AND `run` REPLACED IT, AND THE DIFFERENCE IS THE WHOLE FIX. `row` authored two
# endpoints in NORMALISED coordinates and spread n pieces between them, so spacing was a fraction
# of the ground: the same authored "colonnade" was a tight run on a small board and six body-widths
# of bare floor between neighbours on a large one. See `DEFAULT_RUN_GAP`, which carries the
# measurement. `run` authors the GAP in body diameters, so a structure is the same structure on
# every ground.
#
# ⚠️ "Architecture is the default; trade is the accent" (§2). `pillar`, `boulder`, `shrine`,
# `low_wall` and `fence` are the building; `crate` and `barrel` appear as at most ONE stand on a
# board, and only where a working yard would keep them — never spread out, always stacked against
# something, because they are the only two kinds still under two bodies and therefore the only two
# that can measure as debris at all.
#
# ⚠️ A GATE IS TWO `bar` ENTRIES, NOT A NEW ELEMENT TYPE. Author the jambs either side of the
# centre line at the SAME depth — x=0.43 and x=0.57 at y=0.15 — and the emitter's 180-degree
# partner builds the matching gate at y=0.85 for free. A single bar at x=0.43 does NOT make a gate:
# its partner lands at x=0.57 on the OTHER side of the board, which is a pair of stubs at opposite
# corners. That mistake is invisible in the authored numbers and obvious in the frame.
const LEAGUE_BOARDS := {
	# —— THE APPROACH LEAGUES —— small grounds, few decisions, read in one glance.
	#
	# ⚠️ THE SMALL BOARDS ARE THE TIGHT ONES FOR COVER BUDGET, WHICH IS NOT INTUITIVE. The four
	# family majors are a fixed FRACTION of the board (`MAJOR_WIDTH_FRACTION`), so they cost 2.43%
	# of the floor at EVERY team size — leaving Wood roughly 1,100 square units of remaining
	# allowance under the 6.5% ceiling against Tamers Apex's 4,300. A small board earns its
	# character from ARRANGEMENT, not from quantity, and trying to give Wood a colonnade as well as
	# its crib is how it ends up over the ceiling.
	"Wood": {
		"place": "the Timberyard Ring — a crib of stacked timber down one side",
		"mass": Vector2(0.92, 0.94),
		"furniture": [
			{"t": "run", "at": Vector2(0.20, 0.62), "dir": Vector2(0, 1), "n": 2, "gap": 0.5,
				"grade": "soft", "kind": "bench"},
			{"t": "run", "at": Vector2(0.13, 0.30), "dir": Vector2(0, 1), "n": 2, "gap": 0.35,
				"grade": "soft", "kind": "barrel"},
		],
	},
	"Copper": {
		"place": "the Smelt Court — a three-bay colonnade down one wing, barrels stacked at its foot",
		"mass": Vector2(1.06, 0.88),
		"furniture": [
			{"t": "run", "at": Vector2(0.22, 0.12), "dir": Vector2(1, 0), "n": 3, "gap": 0.4,
				"grade": "hard", "kind": "pillar"},
			{"t": "run", "at": Vector2(0.14, 0.44), "dir": Vector2(0, 1), "n": 2, "gap": 0.35,
				"grade": "soft", "kind": "barrel"},
		],
	},
	"Tin": {
		"place": "the Wash Court — two planted terraces at different depths",
		"mass": Vector2(0.86, 1.10),
		"furniture": [
			{"t": "run", "at": Vector2(0.20, 0.10), "dir": Vector2(1, 0), "n": 3, "gap": 0.4,
				"grade": "soft", "kind": "planter"},
			{"t": "run", "at": Vector2(0.27, 0.34), "dir": Vector2(1, 0), "n": 3, "gap": 0.5,
				"grade": "soft", "kind": "fence"},
		],
	},
	"Bronze": {
		"place": "the Alloy Hall — a four-bay colonnade and a stack of fallen drums",
		"mass": Vector2(1.14, 0.90),
		"furniture": [
			{"t": "run", "at": Vector2(0.24, 0.11), "dir": Vector2(1, 0), "n": 4, "gap": 0.4,
				"grade": "hard", "kind": "pillar"},
			{"t": "run", "at": Vector2(0.19, 0.40), "dir": Vector2(1, 1), "n": 2, "gap": 0.4,
				"grade": "hard", "kind": "boulder"},
			{"t": "run", "at": Vector2(0.30, 0.64), "dir": Vector2(1, 0), "n": 3, "gap": 0.45,
				"grade": "soft", "kind": "bench"},
			{"t": "bar", "at": Vector2(0.34, 0.20), "w": 0.10, "d": 0.030,
				"grade": "soft", "kind": "bench"},
		],
	},
	# ⚠️ IRON IS THE GATEHOUSE, AND THAT IS WHY IT GETS THE ONLY GATE BELOW THE SUMMIT.
	# `ARENA_DESIGN.md` §6 records exactly this split: Bronze and Iron both field three, so both get
	# the same ground, and the only thing that ever pulled them apart was silhouette FAMILY —
	# Bronze horizontal masonry, Iron "things you pass THROUGH and stand ON". Two colonnades at
	# different sizes read as the same place. A colonnade and a gatehouse do not.
	"Iron": {
		"place": "the Gatehouse — a wall with a gate in it, and tumbled blocks behind",
		"mass": Vector2(0.78, 1.16),
		"furniture": [
			{"t": "bar", "at": Vector2(0.42, 0.36), "w": 0.13, "d": 0.024},
			{"t": "bar", "at": Vector2(0.58, 0.36), "w": 0.13, "d": 0.024},
			{"t": "run", "at": Vector2(0.24, 0.42), "dir": Vector2(1, 1), "n": 3, "gap": 0.4,
				"grade": "hard", "kind": "boulder"},
			{"t": "run", "at": Vector2(0.16, 0.66), "dir": Vector2(0, 1), "n": 2, "gap": 0.35,
				"grade": "soft", "kind": "crate"},
		],
	},
	# —— THE MIDDLE LEAGUES —— the ground is now big enough that arrangement, not size, carries the
	# difference. Both are 4v4, which the doc's "Status" note flags as the exact trap Iron and
	# Bronze fell into, so they are split by silhouette family: Silver is an upright colonnade
	# turning a corner, Gold is a stepped echelon of low runs lying flat.
	"Silver": {
		"place": "the Cloister — a colonnade turning a corner around an open middle",
		"mass": Vector2(0.72, 1.04),
		"furniture": [
			{"t": "run", "at": Vector2(0.22, 0.09), "dir": Vector2(1, 0), "n": 5, "gap": 0.45,
				"grade": "hard", "kind": "pillar"},
			{"t": "run", "at": Vector2(0.155, 0.22), "dir": Vector2(0, 1), "n": 4, "gap": 0.45,
				"grade": "hard", "kind": "boulder"},
			{"t": "run", "at": Vector2(0.30, 0.40), "dir": Vector2(1, 0), "n": 3, "gap": 0.45,
				"grade": "soft", "kind": "bench"},
			# ⚠️ THE ONLY `shrine` ON THE LADDER, AND IT IS HERE BECAUSE THE PROBE FOUND IT ORPHANED.
			# Every other kind is placed by some league's furniture; `shrine` was reachable only if the
			# family accent's rng happened to roll it out of the hard pool, and across all eleven
			# leagues at the real arena seed it never did — authored, sized, textured and never on a
			# board. A cloister is where a shrine belongs, so it stops being a lottery ticket.
			{"t": "run", "at": Vector2(0.22, 0.72), "dir": Vector2(1, 0), "n": 2, "gap": 0.4,
				"grade": "hard", "kind": "shrine"},
		],
	},
	# ⚠️ GOLD IS THE BOARD THE INSTRUMENT AGREED WITH BEFORE ANYTHING WAS TOUCHED — 14% debris
	# against a median of 71% — because it was already authored as a continuous run rather than as a
	# scatter. It keeps its identity and simply gains the tight spacing every other board needed.
	# `ARENA_DESIGN.md` §4: "use the mirror instead of fighting it — a stepped diagonal continues
	# under 180-degree rotation".
	"Gold": {
		"place": "the Chequer — a stepped echelon of low runs that the mirror continues",
		"mass": Vector2(1.20, 1.34),
		"furniture": [
			{"t": "run", "at": Vector2(0.20, 0.30), "dir": Vector2(1, 0.28), "n": 5, "gap": 0.4,
				"grade": "soft", "kind": "fence"},
			{"t": "run", "at": Vector2(0.34, 0.56), "dir": Vector2(1, 0.28), "n": 5, "gap": 0.4,
				"grade": "soft", "kind": "fence"},
			{"t": "run", "at": Vector2(0.12, 0.80), "dir": Vector2(1, 0), "n": 2, "gap": 0.4,
				"grade": "soft", "kind": "planter"},
		],
	},
	# —— THE GRAND CIRCUIT —— four leagues, one ground size (§7). Colour is the cheapest axis and
	# the least memorable, so these four are pulled apart by ARRANGEMENT first: a court with a
	# raised terrace, a spine, a broken court at every depth, and a field of standing stones behind
	# a gate.
	"Platinum": {
		"place": "the Four Piers — a stand of piers, a raised terrace and a planted walk",
		"mass": Vector2(1.00, 1.00),
		"furniture": [
			{"t": "run", "at": Vector2(0.20, 0.09), "dir": Vector2(1, 0), "n": 5, "gap": 0.45,
				"grade": "hard", "kind": "pillar"},
			# The terrace. A `bar` at SOFT grade is the element doing something no prop in
			# `KIND_TABLE` can — a broad low platform rather than a wall — and grade is what the
			# sim reads, so calling it soft is the statement that this is something to stand on and
			# shoot over, not something to hide behind.
			{"t": "bar", "at": Vector2(0.30, 0.40), "w": 0.11, "d": 0.035,
				"grade": "soft", "kind": "bench"},
			{"t": "run", "at": Vector2(0.24, 0.44), "dir": Vector2(1, 0), "n": 4, "gap": 0.4,
				"grade": "soft", "kind": "planter"},
			{"t": "run", "at": Vector2(0.13, 0.68), "dir": Vector2(0, 1), "n": 2, "gap": 0.35,
				"grade": "soft", "kind": "crate"},
		],
	},
	"Masters": {
		"place": "the Spine — a cross-wall on the centre line with a bay each side",
		"mass": Vector2(1.22, 0.86),
		"furniture": [
			{"t": "bar", "at": Vector2(0.50, 0.28), "w": 0.24, "d": 0.022},
			{"t": "run", "at": Vector2(0.19, 0.10), "dir": Vector2(1, 0), "n": 5, "gap": 0.45,
				"grade": "hard", "kind": "pillar"},
			{"t": "run", "at": Vector2(0.28, 0.45), "dir": Vector2(1, 0), "n": 2, "gap": 0.4,
				"grade": "hard", "kind": "boulder"},
			{"t": "run", "at": Vector2(0.22, 0.62), "dir": Vector2(1, 0), "n": 3, "gap": 0.45,
				"grade": "soft", "kind": "bench"},
		],
	},
	"Tamer Elite": {
		"place": "the Broken Court — tumbled coursing, no two runs sharing a depth or an angle",
		"mass": Vector2(0.80, 1.18),
		"furniture": [
			{"t": "run", "at": Vector2(0.15, 0.10), "dir": Vector2(1, 0), "n": 3, "gap": 0.4,
				"grade": "hard", "kind": "boulder"},
			{"t": "run", "at": Vector2(0.30, 0.12), "dir": Vector2(1, 1), "n": 3, "gap": 0.4,
				"grade": "hard", "kind": "pillar"},
			{"t": "run", "at": Vector2(0.18, 0.38), "dir": Vector2(1, -1), "n": 3, "gap": 0.4,
				"grade": "hard", "kind": "boulder"},
			{"t": "run", "at": Vector2(0.34, 0.55), "dir": Vector2(1, 0), "n": 4, "gap": 0.45,
				"grade": "hard", "kind": "pillar"},
			{"t": "run", "at": Vector2(0.11, 0.70), "dir": Vector2(0, 1), "n": 2, "gap": 0.35,
				"grade": "soft", "kind": "crate"},
			{"t": "run", "at": Vector2(0.25, 0.86), "dir": Vector2(1, 0), "n": 3, "gap": 0.5,
				"grade": "soft", "kind": "fence"},
		],
	},
	"Tamers Apex": {
		"place": "the Obelisk Field — three ranks of standing stones behind a gate",
		"mass": Vector2(1.10, 1.12),
		"furniture": [
			{"t": "bar", "at": Vector2(0.43, 0.24), "w": 0.11, "d": 0.020},
			{"t": "bar", "at": Vector2(0.57, 0.24), "w": 0.11, "d": 0.020},
			{"t": "run", "at": Vector2(0.26, 0.32), "dir": Vector2(1, 0), "n": 6, "gap": 0.45,
				"grade": "hard", "kind": "pillar"},
			{"t": "run", "at": Vector2(0.30, 0.48), "dir": Vector2(1, 0), "n": 5, "gap": 0.4,
				"grade": "hard", "kind": "boulder"},
			{"t": "run", "at": Vector2(0.24, 0.64), "dir": Vector2(1, 0), "n": 6, "gap": 0.45,
				"grade": "soft", "kind": "fence"},
			{"t": "run", "at": Vector2(0.11, 0.86), "dir": Vector2(1, 0), "n": 2, "gap": 0.35,
				"grade": "soft", "kind": "barrel"},
		],
	},
}


## The 180-degree partner of a rect about the ground centre. ⚠️ DELEGATES TO `_mirror_rect`
## RATHER THAN RESTATING IT — that function's own comment says every symmetry guarantee in this
## file rests on it, which is only true while there is one copy. A second transcription of the
## formula is how the emitter and the checker drift apart and each keeps passing its own test.
static func _partner(rect: Rect2, g: Vector2) -> Rect2:
	return _mirror_rect(rect, g)


## Appends a piece AND its 180-degree partner, or the piece alone when it is its own partner
## (`ARENA_DESIGN.md` §4: "a centrepiece sits at exactly (w - size) / 2 — it is its own 180-degree
## partner and is emitted once").
##
## ⚠️ THE PAIR IS ALL-OR-NOTHING. If either member will not fit, clips a deploy band or touches
## an existing piece, BOTH are dropped — dropping one would leave the board asymmetric, which is
## the one property `ARENA_DESIGN.md` §5 calls non-negotiable. A board a piece lighter is a far
## cheaper failure than a board that favours a side.
static func _emit_pair(out: Array, rect: Rect2, grade: String, kind_a: String, kind_b: String,
		g: Vector2, bands: Array) -> int:
	var twin := _partner(rect, g)
	var self_partnered: bool = rect.position.distance_to(twin.position) < SYMMETRY_EPS
	var members: Array = [rect] if self_partnered else [rect, twin]
	for r in members:
		if not _fits(r, g) or _intersects_any_band(r, bands) or _overlaps_any(r, out):
			return 0
	out.append({"rect": rect, "grade": grade, "kind": kind_a})
	if self_partnered:
		return 1
	out.append({"rect": twin, "grade": grade, "kind": kind_b})
	return 2


static func _kind_size(kind_name: String) -> Vector2:
	for k in KIND_TABLE:
		if str(k["kind"]) == kind_name:
			return k["size"]
	return Vector2(3.0 * G, 3.0 * G)


## ⚠️ THE ONE CONSTANT THAT TURNS A ROW OF POSTS INTO A COLONNADE, and the absence of it is the
## structural cause of the whole debris finding.
##
## The old `row` element authored its two ENDPOINTS in normalised coordinates and spread `n` pieces
## evenly between them — so the spacing was a fraction of the ground, and grew with it. Measured on
## the boards that shipped: Copper's authored "colonnade down one wing" ran three pillars from
## x=0.20 to x=0.44 on a 275-wide ground, which is 33 units between centres for a 6.2-unit pillar —
## **a 27-unit gap, six body-widths of bare floor between neighbours.** That is not a colonnade, it
## is three separate posts, and the author could not see it because the authored numbers describe a
## line and the rendered result is a scatter.
##
## `run` fixes the frame of reference: spacing is authored in BODY DIAMETERS of clear gap, so a
## structure is the same structure on every ground, and the pieces stay close enough that an eye
## binds them into one object. 0.5 bodies is the default — a body cannot pass through, so it reads
## and paths as a single mass.
const DEFAULT_RUN_GAP := 0.5


## Emits `n` pieces in a line through `centre` along `dir` (a WORLD direction, so a diagonal is a
## real diagonal rather than a normalised one that the ground's aspect ratio would shear), each
## with its 180-degree partner. Returns how many pieces were actually emitted.
##
## ⚠️ THE PIECES ARE SPACED EDGE-TO-EDGE, NOT CENTRE-TO-CENTRE. `PIECE_GAP` (1.0 world unit) is the
## generator's minimum clear gap between any two pieces, so the run's own gap is floored just above
## it — a run authored tighter than `PIECE_GAP` would have every piece after the first rejected by
## `_overlaps_any` and the board would silently come out short.
static func _emit_run(out: Array, centre: Vector2, dir: Vector2, n: int, gap_bodies: float,
		size: Vector2, grade: String, kind: String, g: Vector2, bands: Array) -> int:
	var d := dir.normalized() if dir.length() > 0.0001 else Vector2.RIGHT
	var extent: float = absf(d.x) * size.x + absf(d.y) * size.y
	var step: float = extent + maxf(PIECE_GAP + 0.2, gap_bodies * Sp.BODY_RADIUS * 2.0)
	var count: int = maxi(1, n)
	var emitted := 0
	for i in count:
		var t: float = float(i) - float(count - 1) * 0.5
		var c: Vector2 = centre + d * (t * step)
		emitted += _emit_pair(out, Rect2(c - size * 0.5, size), grade, kind, kind, g, bands)
	return emitted


## Lays the league's furniture over whatever family is already in `out`. Pure geometry off the
## authored table — no rng at all, so a board is the same board on every replay by construction
## rather than by seeding discipline.
static func _build_furniture(league_name: String, g: Vector2, bands: Array, out: Array) -> void:
	var board: Dictionary = LEAGUE_BOARDS.get(league_name, {})
	if board.is_empty():
		return
	# ⚠️ THE CEILING IS ENFORCED HERE, NOT ONLY REPORTED BY `problems()`. A league board is
	# authored against the ground that league actually fields, but nothing stops a caller pairing
	# them freely — `sandbox_ui.gd` already generates a "Wood" board at every team size, and
	# `_probe_density.gd` asks for "Platinum" at team size 1. Measured: the Platinum board on a
	# 1v1 ground emitted 28 pieces against a ceiling of 18, so a mismatched pairing shipped a
	# density-law violation with no guard between it and the screen. This is that guard, and it
	# stops on the CEILING rather than clamping counts, because the law is the law and a board
	# that runs out of allowance should simply be the board it can afford.
	var ceiling: int = int(floor((g.x * g.y) / AREA_PER_PIECE))
	var bar_i := 0
	for e in board.get("furniture", []):
		if out.size() + 2 > ceiling:
			return
		var t: String = str(e.get("t", "post"))
		if t == "post":
			var kind: String = str(e.get("kind", "crate"))
			var sz := _kind_size(kind)
			var c: Vector2 = (e["at"] as Vector2) * g
			_emit_pair(out, Rect2(c - sz * 0.5, sz), str(e.get("grade", "soft")), kind, kind, g, bands)
		elif t == "run":
			# ⚠️ THE CEILING GUARD IS INSIDE `_emit_run` VIA THE CALLER'S BUDGET, not per piece —
			# a run is ONE structure and half a colonnade is a worse board than no colonnade. The
			# whole run is skipped if it would not fit under the density ceiling.
			var kind2: String = str(e.get("kind", "pillar"))
			var sz2 := _kind_size(kind2)
			var n: int = maxi(1, int(e.get("n", 3)))
			if out.size() + 2 * n > ceiling:
				continue
			_emit_run(out, (e["at"] as Vector2) * g, e.get("dir", Vector2.RIGHT), n,
				float(e.get("gap", DEFAULT_RUN_GAP)), sz2, str(e.get("grade", "hard")),
				kind2, g, bands)
		elif t == "bar":
			# A `bar` is authored geometry rather than a kind, so it is the element a board reaches
			# for when it needs a WALL, a GATE JAMB or a DAIS — shapes no prop in `KIND_TABLE` can
			# make. Grade defaults to `blocking` (the wall case); a board that wants a platform to
			# stand on rather than a wall to hide behind says so.
			var w: float = float(e.get("w", 0.2)) * g.x
			var d: float = maxf(Sp.BODY_RADIUS * 2.0, float(e.get("d", 0.03)) * g.y)
			var c3: Vector2 = (e["at"] as Vector2) * g
			var bg: String = str(e.get("grade", "blocking"))
			var ka: String = str(e.get("kind", MAJOR_BLOCKING_KINDS[bar_i % MAJOR_BLOCKING_KINDS.size()]))
			var kb: String = str(e.get("kind", MAJOR_BLOCKING_KINDS[(bar_i + 1) % MAJOR_BLOCKING_KINDS.size()]))
			bar_i += 1
			_emit_pair(out, Rect2(c3 - Vector2(w, d) * 0.5, Vector2(w, d)), bg, ka, kb, g, bands)


## Builds a named composition: the FAMILY skeleton (`LAYOUTS`) warped by the LEAGUE's own mass
## placement, then the league's furniture laid over it (`LEAGUE_BOARDS`).
##
## `w` on a major is a multiple of `major_min_width_for(team_size)`, so no layout can author
## cover too narrow to hide a formation — nor, since that became a fraction of the board, four
## times too wide on the small grounds.
##
## ⚠️ THE LEAGUE `mass` MULTIPLIER SCALES EACH MAJOR'S OFFSET FROM CENTRE, never its position
## outright. Scaling an offset about the centre commutes with the 180-degree rotation, so the
## warp cannot break fairness no matter what an author types — which is the only reason it is
## safe to expose an arrangement knob at all. `ARENA_DESIGN.md` §4 names exactly this as the
## third-biggest lever on a board's signature: "push the mass to one edge of the legal strip".
static func _build_named(layout_id: String, g: Vector2, rng: RandomNumberGenerator,
		league_name: String = "", team_size: int = 5) -> Array:
	var spec: Dictionary = LAYOUTS.get(layout_id, {})
	if spec.is_empty():
		return []
	var bands := _deploy_bands(team_size)
	var board: Dictionary = LEAGUE_BOARDS.get(league_name, {})
	var mass: Vector2 = board.get("mass", Vector2.ONE)
	var out: Array = []
	var base := major_min_width_for(team_size)
	var major_i := 0
	for m in spec.get("major", []):
		var w: float = base * float(m.get("w", 1.0))
		# Thickness is a quarter of the width — long and thin, which is what makes cover a READ
		# (it shelters an approach, not a position) rather than a safe default.
		# ⚠️ 0.25 -> 0.42 THICK. A blade-thin wall casts a shadow from only two directions, so a unit
		# that walks 40 degrees around it loses all cover — which is why the pillar/wall distinction
		# in `ARENA_SCALE_COMPARISON.md` matters. WoW's pillars are chunky precisely so the shelter
		# is omnidirectional enough to be worth standing behind.
		var d: float = maxf(Sp.BODY_RADIUS * 2.0, w * float(m.get("d", 0.42)))
		var at: Vector2 = m["at"]
		var warped := Vector2(0.5 + (at.x - 0.5) * mass.x, 0.5 + (at.y - 0.5) * mass.y)
		var c: Vector2 = warped * g
		# ⚠️ EVERY MAJOR USED TO BE THE SAME `kind`, AND IT SHOWED. A composition's four blocking
		# pieces were all `low_wall`, so a board rendered as four copies of one prop — the "grey
		# slabs" read, half of which was a LAYOUT problem and not a renderer one. `ARENA_DESIGN.md`
		# §5 already asks for exactly this ("prefer odd arrangements... too symmetrical kept
		# recurring") and the scatter path below has always rolled its mirror partner's kind
		# independently for the same reason; the authored path simply never did.
		#
		# ⚠️ ALTERNATED BY INDEX, NOT ROLLED FROM `rng`. Two reasons and both matter: an extra rng
		# draw here would shift every accent kind downstream (the accents draw from the same
		# stream), silently changing boards that nothing asked to change; and a *deterministic*
		# alternation guarantees a mirror PAIR gets different props, where a roll only probably
		# would. The rect, the grade and therefore everything the sim reads are untouched — this
		# chooses a mesh, nothing more.
		var mg: String = str(m.get("grade", "blocking"))
		var mkind: String = MAJOR_BLOCKING_KINDS[major_i % MAJOR_BLOCKING_KINDS.size()] \
			if mg == "blocking" else ("boulder" if major_i % 2 == 0 else "pillar")
		major_i += 1
		out.append({
			"rect": Rect2(c - Vector2(w, d) * 0.5, Vector2(w, d)),
			"grade": mg,
			"kind": mkind,
		})
	for a in spec.get("accents", []):
		var grade: String = str(a.get("grade", "soft"))
		var pool: Array = []
		for k in KIND_TABLE:
			if str(k["grade"]) == grade and float((k["size"] as Vector2).x) < base:
				pool.append(k)
		if pool.is_empty():
			continue
		var pick: int = rng.randi_range(0, pool.size() - 1)
		var kind: Dictionary = pool[pick]
		var sz: Vector2 = kind["size"]
		# ⚠️ ACCENTS ARE DELIBERATELY NOT WARPED BY `mass`. The knob exists to move the MASS
		# (§4: "push the mass to one edge of the legal strip"), and applying it to a piece already
		# near an edge walks that piece off the board — Gold's 1.34 push put both accents outside
		# `EDGE_MARGIN`, where `_emit_pair` silently dropped them. A knob whose range depends on
		# which pieces it happens to touch is a knob nobody can use.
		var c2: Vector2 = (a["at"] as Vector2) * g
		# ⚠️ AN ACCENT IS NOW A STAND OF PIECES, NOT ONE PIECE, AND THAT IS WHERE HALF THE DEBRIS
		# CAME FROM. The four families each authored two single accents; emitted with their
		# partners that is FOUR ISOLATED SMALL PROPS ON EVERY BOARD IN THE GAME, before a league
		# adds anything of its own — and the family accents were the same four on all eleven, so
		# the one part of the layout that was truly shared was also the part that read as litter.
		# `n` defaults to 2 so an un-migrated family gets a stack rather than a stray.
		var n_a: int = maxi(1, int(a.get("n", 2)))
		# ⚠️ THE PARTNER SHARES THE RECT AND ONLY DIFFERS IN MESH — except within a run, where both
		# halves keep ONE kind on purpose. Rolling the partner's SIZE is what made the authored
		# boards asymmetric; rolling its KIND is what `ARENA_DESIGN.md` §5 asks for. But a stand of
		# three DIFFERENT props is a pile, and a stand of three of the same is a colonnade, so the
		# per-piece variety §5 wants comes from the renderer's position-hashed yaw and scale here,
		# not from mixing the kinds inside one structure.
		if n_a > 1:
			_emit_run(out, c2, a.get("dir", Vector2.RIGHT), n_a,
				float(a.get("gap", DEFAULT_RUN_GAP)), sz, grade, str(kind["kind"]), g, bands)
		else:
			var kind_b: String = str((pool[(pick + 1) % pool.size()] as Dictionary)["kind"])
			_emit_pair(out, Rect2(c2 - sz * 0.5, sz), grade, str(kind["kind"]), kind_b, g, bands)
	_build_furniture(league_name, g, bands, out)
	return out


static func generate(team_size: int, league_name: String, rng: RandomNumberGenerator,
		layout_id: String = "four_pillar") -> Dictionary:
	var g := Sp.ground_size(team_size)
	var area := g.x * g.y
	var tight_r := Sp.engagement_radius(team_size, 0.0)
	var loose_r := Sp.engagement_radius(team_size, 1.0)
	var center := g * 0.5
	var bands := _deploy_bands(team_size)

	# ⚠️ A NAMED LAYOUT SHORT-CIRCUITS THE SCATTER ENTIRELY. The sampling loop below is kept — it
	# is still the fallback for an unknown layout id, and it is what the density law was written
	# against — but a composition is authored, not sampled, and mixing the two would put random
	# pieces on top of a deliberate arrangement.
	var named := _build_named(layout_id, g, rng, league_name, team_size)
	if not named.is_empty():
		return {
			"obstacles": named,
			"layout": layout_id,
			"place": str((LEAGUE_BOARDS.get(league_name, {}) as Dictionary).get("place", layout_id)),
			"centre": str((LAYOUTS[layout_id] as Dictionary).get("centre", "open")),
			"theme": _theme_for(league_name, rng),
		}

	var target_pairs := _target_pairs(area, rng)

	var obstacles: Array = []
	var attempts := 0
	while obstacles.size() < target_pairs * 2 and attempts < MAX_PLACEMENT_ATTEMPTS:
		attempts += 1

		# Sample uniformly by AREA inside the annulus (not by radius, which would bias toward
		# the outer edge) — r^2 is uniform between the two radii-squared.
		var theta := rng.randf_range(0.0, TAU)
		var r := sqrt(rng.randf_range(tight_r * tight_r, loose_r * loose_r))
		var p := center + Vector2(cos(theta), sin(theta)) * r

		# Only generate the canonical (left) half; every accepted piece is mirrored below. This
		# is what GUARANTEES 180-degree symmetry rather than checking for it after the fact.
		if p.x > center.x:
			continue

		# ⚠️ GRADE FIRST, THEN A KIND WITHIN THAT GRADE. Picking uniformly from `KIND_TABLE` made the
		# grade mix an ACCIDENT OF HOW MANY ROWS EACH GRADE HAPPENED TO HAVE — so adding a tenth
		# kind silently halved the line-of-sight-blocking cover in the game (8 blocking pieces down
		# to 4) and the only symptom was a probe number moving. A board's balance of soft / hard /
		# blocking is a design decision; it must never be a side effect of table length.
		var spec: Dictionary = _pick_spec(rng)
		var sz: Vector2 = spec["size"]
		var rect := Rect2(p - sz * 0.5, sz)
		if not _fits(rect, g):
			continue
		if _intersects_any_band(rect, bands):
			continue
		if _overlaps_any(rect, obstacles):
			continue

		var mirror_rect := _mirror_rect(rect, g)
		if not _fits(mirror_rect, g):
			continue
		if _intersects_any_band(mirror_rect, bands):
			continue
		if _overlaps_any(mirror_rect, obstacles):
			continue

		var grade: String = spec["grade"]
		var kind_a: String = spec["kind"]
		# The mirror partner keeps the EXACT same rect (position mirrored, size identical) —
		# that is what makes the two sides mechanically equal. Only its `kind` (the mesh the
		# renderer picks) is independently rolled, so a symmetric pair does not look like two
		# copies of the same prop (`ARENA_DESIGN.md` §5: "prefer odd arrangements... too
		# symmetrical kept recurring"). Every grade has at least two kinds since the sweep in
		# `docs/OBSTACLE_KIND_CANDIDATES.md` added bench/fence/boulder/shrine, so the roll has
		# real choices in all three grades.
		# ⚠️ The partner'S ROLLED KIND KEEPS THE PLACED RECT — kinds within a grade have
		# different authored footprints, and the rect must stay identical for mechanical
		# symmetry. The renderer stretches the partner's mesh to the shared rect, which is the
		# same thing it already does for every kind.
		var kind_b := _kind_of_same_grade(grade, rng)

		obstacles.append({"rect": rect, "grade": grade, "kind": kind_a})
		obstacles.append({"rect": mirror_rect, "grade": grade, "kind": kind_b})

	return {"obstacles": obstacles, "theme": _theme_for(league_name, rng)}


## Every piece placed at `p` must have a partner at `ground_size - p - size`. This is a static
## check other streams can call on their own layouts too — problems() below is the enforcement
## for the four requirements the brief calls out: symmetry, deploy-zone clearance, the density
## ceiling, and no overlaps. Empty return means clean.
static func problems(obstacles: Array, team_size: int) -> Array:
	var out: Array = []
	var g := Sp.ground_size(team_size)

	# ── shape sanity — cheap, and a malformed obstacle would otherwise silently no-op every
	# other check below rather than being caught.
	for i in obstacles.size():
		var o = obstacles[i]
		if not (o is Dictionary) or not o.has("rect") or not o.has("grade") or not o.has("kind"):
			out.append("obstacle %d: missing rect/grade/kind" % i)
			continue
		if not (o["rect"] is Rect2):
			out.append("obstacle %d: rect is not a Rect2" % i)
			continue
		var grade: String = str(o["grade"])
		if grade != "soft" and grade != "hard" and grade != "blocking":
			out.append("obstacle %d: unknown grade '%s' (must be soft/hard/blocking)" % [i, grade])
		var rect: Rect2 = o["rect"]
		if rect.position.x < 0.0 or rect.position.y < 0.0 \
				or rect.position.x + rect.size.x > g.x or rect.position.y + rect.size.y > g.y:
			out.append("obstacle %d: rect %s extends outside the ground %s" % [i, rect, g])

	# ── deploy zones stay clear
	var bands := _deploy_bands(team_size)
	for i in obstacles.size():
		var o = obstacles[i]
		if not (o is Dictionary) or not (o.get("rect") is Rect2):
			continue
		if _intersects_any_band(o["rect"], bands):
			out.append("obstacle %d: rect %s overlaps a deploy band" % [i, o["rect"]])

	# ── no two pieces overlap
	for i in obstacles.size():
		var oi = obstacles[i]
		if not (oi is Dictionary) or not (oi.get("rect") is Rect2):
			continue
		var ri: Rect2 = oi["rect"]
		for j in range(i + 1, obstacles.size()):
			var oj = obstacles[j]
			if not (oj is Dictionary) or not (oj.get("rect") is Rect2):
				continue
			if ri.intersects(oj["rect"]):
				out.append("obstacles %d and %d overlap (%s / %s)" % [i, j, ri, oj["rect"]])

	# ── density ceiling. ⚠️ EXTRAPOLATED — see the note on AREA_PER_PIECE. A pass here says the
	# layout is under a formula nobody has validated at this scale yet, not that it reads right.
	var ceiling: int = int(floor((g.x * g.y) / AREA_PER_PIECE))
	if obstacles.size() > ceiling:
		out.append("density: %d pieces exceeds the ceiling of %d (%d sq units / %.0f per piece) for a %d-a-side ground"
			% [obstacles.size(), ceiling, int(g.x * g.y), AREA_PER_PIECE, team_size])

	# ── 180-degree rotational symmetry
	# ⚠️ AN ODD COUNT IS LEGAL AND THE OLD CHECK SAID IT WAS NOT. `ARENA_DESIGN.md` §4: "a
	# centrepiece sits at exactly (w - size) / 2 — it is its own 180-degree partner and is emitted
	# once". Two of the four authored families (`central_mass`, `triad`) put a mass on the axis, so
	# this rule rejected the arrangement the design doc explicitly authorises. It never fired
	# because `problems()` had only ever been run against the scatter path.
	var matched: Array = []
	for i in obstacles.size():
		matched.append(false)
	for i in obstacles.size():
		if matched[i]:
			continue
		var oi = obstacles[i]
		if not (oi is Dictionary) or not (oi.get("rect") is Rect2):
			continue
		var want := _mirror_rect(oi["rect"], g)
		if (oi["rect"] as Rect2).position.distance_to(want.position) < SYMMETRY_EPS:
			matched[i] = true      # on the axis: its own partner, emitted once
			continue
		var found := -1
		for j in range(i + 1, obstacles.size()):
			if matched[j]:
				continue
			var oj = obstacles[j]
			if not (oj is Dictionary) or not (oj.get("rect") is Rect2):
				continue
			var rj: Rect2 = oj["rect"]
			if rj.position.distance_to(want.position) < SYMMETRY_EPS \
					and rj.size.distance_to(want.size) < SYMMETRY_EPS:
				found = j
				break
		if found == -1:
			out.append("symmetry: obstacle %d at %s has no 180-degree mirror partner" % [i, oi["rect"]])
		else:
			matched[i] = true
			matched[found] = true

	return out


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# INTERNAL — placement geometry
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## The intended balance of cover grades on a board, as a stated decision rather than an emergent
## one. ⚠️ `blocking` is the expensive grade — it stops a shot outright and carves the navmesh —
## and it is also the ONLY grade a unit can hide behind, so it is the one that decides whether
## cover-seeking is a tactic or a decoration. A third is deliberate: enough that a sampled position
## has a real chance of being sheltered, not so much that a sports ground reads as a maze.
const GRADE_MIX := {"soft": 0.42, "hard": 0.25, "blocking": 0.33}


## Picks a grade by weight, then a kind within it. Deterministic off the injected rng — one draw
## for the grade, one for the kind — so a given seed still produces a given board.
static func _pick_spec(rng: RandomNumberGenerator) -> Dictionary:
	var roll := rng.randf()
	var acc := 0.0
	var want := "soft"
	for grade in ["soft", "hard", "blocking"]:
		acc += float(GRADE_MIX[grade])
		if roll <= acc:
			want = grade
			break
	var pool: Array = []
	for spec in KIND_TABLE:
		if str(spec["grade"]) == want:
			pool.append(spec)
	if pool.is_empty():
		return KIND_TABLE[rng.randi_range(0, KIND_TABLE.size() - 1)]
	return pool[rng.randi_range(0, pool.size() - 1)]


## How many mirrored PAIRS to aim for. Clamped well under the (extrapolated) density ceiling —
## see `DENSITY_SAFETY_FACTOR` — with a small seeded jitter so different seeds at the same team
## size and league still look like different boards.
static func _target_pairs(area: float, rng: RandomNumberGenerator) -> int:
	var ceiling: int = int(floor(area / AREA_PER_PIECE))
	var target_total: int = int(round(area / (AREA_PER_PIECE * DENSITY_SAFETY_FACTOR)))
	target_total = clampi(target_total, 2, maxi(2, ceiling))
	# Halving is intentional — cover is placed in 180°-symmetric PAIRS, so only half are sampled.
	# Written as an explicit float floor rather than integer division so the truncation is a stated
	# decision instead of a Godot "integer division, decimal part discarded" warning that a reader
	# has to guess the intent behind.
	var pairs := maxi(1, int(floor(float(target_total) / 2.0)))
	pairs = clampi(pairs + rng.randi_range(-1, 1), 1, maxi(1, int(floor(float(ceiling) / 2.0))))
	return pairs


## The two deploy-clearance rectangles (side A near x=0, side B near x=W), each grown by
## `DEPLOY_CLEARANCE_MARGIN` and spanning the full ground height. Derived from the same decided
## geometry `Sp.deploy_positions` uses (`ARENA_BLUEPRINT.md` §1-2): a flat, team-size-
## independent `DEPLOY_SEPARATION` between the front lines, and `deploy_depth(team_size)` behind
## each front line toward the ground's own edge.
static func _deploy_bands(team_size: int) -> Array:
	var g := Sp.ground_size(team_size)
	var depth := Sp.deploy_depth(team_size)
	var half_sep := Sp.deploy_separation(team_size) * 0.5
	var cx := g.x * 0.5
	var flank_margin := (g.x - 2.0 * depth - Sp.deploy_separation(team_size)) * 0.5

	var a_x0 := flank_margin - DEPLOY_CLEARANCE_MARGIN
	var a_x1 := (cx - half_sep) + DEPLOY_CLEARANCE_MARGIN
	var b_x0 := (cx + half_sep) - DEPLOY_CLEARANCE_MARGIN
	var b_x1 := (g.x - flank_margin) + DEPLOY_CLEARANCE_MARGIN

	var band_a := Rect2(Vector2(a_x0, -1.0), Vector2(a_x1 - a_x0, g.y + 2.0))
	var band_b := Rect2(Vector2(b_x0, -1.0), Vector2(b_x1 - b_x0, g.y + 2.0))
	return [band_a, band_b]


static func _intersects_any_band(rect: Rect2, bands: Array) -> bool:
	for b in bands:
		if rect.intersects(b):
			return true
	return false


static func _fits(rect: Rect2, g: Vector2) -> bool:
	return rect.position.x >= EDGE_MARGIN and rect.position.y >= EDGE_MARGIN \
		and rect.position.x + rect.size.x <= g.x - EDGE_MARGIN \
		and rect.position.y + rect.size.y <= g.y - EDGE_MARGIN


static func _overlaps_any(rect: Rect2, obstacles: Array) -> bool:
	var grown := rect.grow(PIECE_GAP)
	for o in obstacles:
		if grown.intersects(o["rect"]):
			return true
	return false


## The 180-degree rotation of a rect about the ground's centre: a piece at `position` reappears
## at `ground_size - position - size`, same size. This is the one formula every symmetry
## guarantee in this file rests on.
static func _mirror_rect(rect: Rect2, g: Vector2) -> Rect2:
	return Rect2(g - rect.position - rect.size, rect.size)


static func _kind_of_same_grade(grade: String, rng: RandomNumberGenerator) -> String:
	var options: Array = []
	for spec in KIND_TABLE:
		if spec["grade"] == grade:
			options.append(spec["kind"])
	return options[rng.randi_range(0, options.size() - 1)]


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# INTERNAL — theme
# ═══════════════════════════════════════════════════════════════════════════════════════════════

static func _theme_for(league_name: String, rng: RandomNumberGenerator) -> Dictionary:
	if LEAGUE_MATERIAL.has(league_name):
		var spec: Dictionary = LEAGUE_MATERIAL[league_name]
		return {"league": league_name, "material": spec["material"], "palette": spec["palette"]}
	if GRAND_CIRCUIT_LEAGUES.has(league_name):
		var palette: String = GRAND_CIRCUIT_PALETTES[rng.randi_range(0, GRAND_CIRCUIT_PALETTES.size() - 1)]
		return {"league": league_name, "material": "dressed_stone", "palette": palette}
	push_warning("ArenaLayout: unknown league '%s', falling back to a neutral theme" % league_name)
	return {"league": league_name, "material": "dressed_stone", "palette": "neutral grey"}
