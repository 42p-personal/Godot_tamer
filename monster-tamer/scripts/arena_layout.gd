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
const G := Sp.GEOMETRY_SCALE
const KIND_TABLE := [
	{"kind": "barrel", "grade": "soft", "size": Vector2(2.4 * G, 2.4 * G)},
	{"kind": "crate", "grade": "soft", "size": Vector2(3.0 * G, 3.0 * G)},
	{"kind": "planter", "grade": "soft", "size": Vector2(3.6 * G, 2.2 * G)},
	{"kind": "bench", "grade": "soft", "size": Vector2(4.0 * G, 1.5 * G)},
	{"kind": "fence", "grade": "soft", "size": Vector2(5.5 * G, 1.0 * G)},
	{"kind": "boulder", "grade": "hard", "size": Vector2(3.2 * G, 2.6 * G)},
	{"kind": "pillar", "grade": "hard", "size": Vector2(2.8 * G, 2.8 * G)},
	{"kind": "shrine", "grade": "hard", "size": Vector2(2.0 * G, 2.0 * G)},
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
		"accents": [
			{"at": Vector2(0.5, 0.14), "grade": "hard"},
			{"at": Vector2(0.5, 0.38), "grade": "soft"},
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
			{"at": Vector2(0.5, 0.16), "grade": "hard"},
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
			{"at": Vector2(0.30, 0.24), "grade": "hard"},
			{"at": Vector2(0.5, 0.12), "grade": "soft"},
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
			{"at": Vector2(0.5, 0.5), "grade": "hard"},
			{"at": Vector2(0.18, 0.72), "grade": "soft"},
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
# Element grammar — three shapes, all normalised 0..1 across the ground:
#   {"t": "post", "at": V2, "grade": s, "kind": s}                 one piece + its partner
#   {"t": "row",  "from": V2, "to": V2, "n": i, "grade", "kind"}   n evenly spaced + n partners
#   {"t": "bar",  "at": V2, "w": f, "d": f}                        a blocking run + its partner
#
# ⚠️ "Architecture is the default; trade is the accent" (§2). `pillar`, `boulder`, `low_wall`
# and `fence` are the building; `crate`/`barrel` appear at most as one pair on a board, and only
# where a working yard would keep them.
const LEAGUE_BOARDS := {
	# —— THE APPROACH LEAGUES —— small grounds, few decisions, read in one glance.
	"Wood": {
		"place": "the Timberyard Ring — four stacks and a pair of benches",
		"mass": Vector2(0.92, 0.94),
		"furniture": [
			{"t": "post", "at": Vector2(0.20, 0.30), "grade": "soft", "kind": "bench"},
			{"t": "post", "at": Vector2(0.20, 0.70), "grade": "soft", "kind": "planter"},
		],
	},
	"Copper": {
		"place": "the Smelt Court — a colonnade down one wing",
		"mass": Vector2(1.06, 0.88),
		"furniture": [
			{"t": "row", "from": Vector2(0.20, 0.15), "to": Vector2(0.44, 0.15), "n": 3,
				"grade": "hard", "kind": "pillar"},
		],
	},
	"Tin": {
		"place": "the Wash Court — two benched terraces at different depths",
		"mass": Vector2(0.86, 1.10),
		"furniture": [
			{"t": "row", "from": Vector2(0.17, 0.15), "to": Vector2(0.30, 0.15), "n": 2,
				"grade": "soft", "kind": "planter"},
			{"t": "row", "from": Vector2(0.17, 0.85), "to": Vector2(0.30, 0.85), "n": 2,
				"grade": "soft", "kind": "bench"},
		],
	},
	"Bronze": {
		"place": "the Alloy Hall — a four-bay colonnade and a pair of fallen drums",
		"mass": Vector2(1.14, 0.90),
		"furniture": [
			{"t": "row", "from": Vector2(0.17, 0.12), "to": Vector2(0.47, 0.12), "n": 4,
				"grade": "hard", "kind": "pillar"},
			{"t": "row", "from": Vector2(0.23, 0.42), "to": Vector2(0.39, 0.42), "n": 2,
				"grade": "hard", "kind": "boulder"},
		],
	},
	"Iron": {
		"place": "the Gatehouse — stepped blocks, no two at the same depth",
		"mass": Vector2(0.78, 1.16),
		"furniture": [
			{"t": "post", "at": Vector2(0.13, 0.09), "grade": "hard", "kind": "boulder"},
			{"t": "post", "at": Vector2(0.19, 0.17), "grade": "hard", "kind": "pillar"},
			{"t": "post", "at": Vector2(0.25, 0.45), "grade": "hard", "kind": "boulder"},
			{"t": "post", "at": Vector2(0.31, 0.53), "grade": "hard", "kind": "pillar"},
			{"t": "post", "at": Vector2(0.37, 0.61), "grade": "hard", "kind": "boulder"},
			{"t": "post", "at": Vector2(0.43, 0.69), "grade": "soft", "kind": "crate"},
			{"t": "post", "at": Vector2(0.49, 0.77), "grade": "hard", "kind": "pillar"},
		],
	},
	# —— THE MIDDLE LEAGUES —— the ground is now big enough that arrangement, not size, carries
	# the difference. Both are 4v4, which the doc's "Status" note flags as the exact trap Iron and
	# Bronze fell into, so they are split by silhouette family: Silver is upright posts around an
	# empty middle, Gold is one long diagonal run of low bars.
	"Silver": {
		"place": "the Cloister — a perimeter colonnade around an open middle",
		"mass": Vector2(0.72, 1.04),
		"furniture": [
			{"t": "row", "from": Vector2(0.12, 0.07), "to": Vector2(0.60, 0.07), "n": 6,
				"grade": "hard", "kind": "pillar"},
			{"t": "row", "from": Vector2(0.12, 0.30), "to": Vector2(0.12, 0.70), "n": 3,
				"grade": "hard", "kind": "pillar"},
		],
	},
	"Gold": {
		"place": "the Chequer — a stepped echelon of low runs that the mirror continues",
		"mass": Vector2(1.20, 1.34),
		"furniture": [
			{"t": "row", "from": Vector2(0.10, 0.06), "to": Vector2(0.50, 0.94), "n": 10,
				"grade": "soft", "kind": "fence"},
		],
	},
	# —— THE GRAND CIRCUIT —— four leagues, one ground size (§7). Colour is the cheapest axis
	# and the least memorable, so these four are pulled apart by ARRANGEMENT first: an open court
	# with piers, a spine, a broken court at every depth, and a field of standing stones.
	"Platinum": {
		"place": "the Four Piers — a stand of piers, a planted terrace, two flanking stones",
		"mass": Vector2(1.00, 1.00),
		"furniture": [
			{"t": "row", "from": Vector2(0.16, 0.11), "to": Vector2(0.44, 0.11), "n": 5,
				"grade": "hard", "kind": "pillar"},
			{"t": "row", "from": Vector2(0.16, 0.89), "to": Vector2(0.44, 0.89), "n": 4,
				"grade": "soft", "kind": "planter"},
			{"t": "post", "at": Vector2(0.30, 0.50), "grade": "hard", "kind": "boulder"},
			{"t": "post", "at": Vector2(0.50, 0.66), "grade": "soft", "kind": "bench"},
		],
	},
	"Masters": {
		"place": "the Spine — a cross-run on the centre line with a bay each side",
		"mass": Vector2(1.22, 0.86),
		"furniture": [
			{"t": "bar", "at": Vector2(0.50, 0.30), "w": 0.26, "d": 0.030},
			{"t": "row", "from": Vector2(0.13, 0.09), "to": Vector2(0.45, 0.09), "n": 6,
				"grade": "hard", "kind": "pillar"},
			{"t": "row", "from": Vector2(0.20, 0.44), "to": Vector2(0.42, 0.44), "n": 3,
				"grade": "hard", "kind": "boulder"},
			{"t": "row", "from": Vector2(0.21, 0.63), "to": Vector2(0.41, 0.63), "n": 3,
				"grade": "soft", "kind": "bench"},
		],
	},
	"Tamer Elite": {
		"place": "the Broken Court — tumbled coursing, no two pieces sharing a depth",
		"mass": Vector2(0.80, 1.18),
		"furniture": [
			{"t": "post", "at": Vector2(0.12, 0.08), "grade": "hard", "kind": "boulder"},
			{"t": "post", "at": Vector2(0.21, 0.14), "grade": "hard", "kind": "pillar"},
			{"t": "post", "at": Vector2(0.33, 0.10), "grade": "soft", "kind": "crate"},
			{"t": "post", "at": Vector2(0.45, 0.26), "grade": "hard", "kind": "boulder"},
			{"t": "post", "at": Vector2(0.17, 0.42), "grade": "hard", "kind": "pillar"},
			{"t": "post", "at": Vector2(0.27, 0.48), "grade": "soft", "kind": "planter"},
			{"t": "post", "at": Vector2(0.39, 0.54), "grade": "hard", "kind": "boulder"},
			{"t": "post", "at": Vector2(0.13, 0.60), "grade": "hard", "kind": "pillar"},
			{"t": "post", "at": Vector2(0.23, 0.66), "grade": "soft", "kind": "bench"},
			{"t": "post", "at": Vector2(0.35, 0.72), "grade": "hard", "kind": "boulder"},
			{"t": "post", "at": Vector2(0.47, 0.78), "grade": "hard", "kind": "pillar"},
			{"t": "post", "at": Vector2(0.19, 0.86), "grade": "soft", "kind": "planter"},
			{"t": "post", "at": Vector2(0.31, 0.92), "grade": "hard", "kind": "boulder"},
			{"t": "post", "at": Vector2(0.43, 0.38), "grade": "hard", "kind": "pillar"},
			{"t": "post", "at": Vector2(0.49, 0.32), "grade": "soft", "kind": "barrel"},
		],
	},
	"Tamers Apex": {
		"place": "the Obelisk Field — three ranks of standing stones and a cross-wall",
		"mass": Vector2(1.10, 1.12),
		"furniture": [
			{"t": "bar", "at": Vector2(0.50, 0.18), "w": 0.22, "d": 0.028},
			{"t": "row", "from": Vector2(0.11, 0.08), "to": Vector2(0.45, 0.08), "n": 6,
				"grade": "hard", "kind": "pillar"},
			{"t": "row", "from": Vector2(0.11, 0.34), "to": Vector2(0.45, 0.34), "n": 6,
				"grade": "hard", "kind": "boulder"},
			{"t": "row", "from": Vector2(0.15, 0.52), "to": Vector2(0.43, 0.52), "n": 5,
				"grade": "hard", "kind": "pillar"},
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
		elif t == "row":
			var kind2: String = str(e.get("kind", "pillar"))
			var sz2 := _kind_size(kind2)
			var n: int = maxi(1, int(e.get("n", 2)))
			var a: Vector2 = e["from"]
			var b: Vector2 = e["to"]
			for i in n:
				if out.size() + 2 > ceiling:
					return
				var f: float = 0.0 if n == 1 else float(i) / float(n - 1)
				var c2: Vector2 = a.lerp(b, f) * g
				_emit_pair(out, Rect2(c2 - sz2 * 0.5, sz2), str(e.get("grade", "hard")),
					kind2, kind2, g, bands)
		elif t == "bar":
			var w: float = float(e.get("w", 0.2)) * g.x
			var d: float = maxf(Sp.BODY_RADIUS * 2.0, float(e.get("d", 0.03)) * g.y)
			var c3: Vector2 = (e["at"] as Vector2) * g
			var ka: String = MAJOR_BLOCKING_KINDS[bar_i % MAJOR_BLOCKING_KINDS.size()]
			var kb: String = MAJOR_BLOCKING_KINDS[(bar_i + 1) % MAJOR_BLOCKING_KINDS.size()]
			bar_i += 1
			_emit_pair(out, Rect2(c3 - Vector2(w, d) * 0.5, Vector2(w, d)), "blocking",
				ka, kb, g, bands)


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
		# ⚠️ THE PARTNER SHARES THE RECT AND ONLY DIFFERS IN MESH. Rolling the partner's SIZE is
		# what made the authored boards asymmetric; rolling its KIND is what `ARENA_DESIGN.md` §5
		# asks for ("prefer odd arrangements... too symmetrical kept recurring"). Stepped by index
		# rather than rolled, so the pair is GUARANTEED two different props instead of probably two.
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
