## THE BOARD-COMPOSITION INSTRUMENT — one table, five verdicts, per league.
##
## ⚠️ BUILT BEFORE ANY LAYOUT WAS TOUCHED, on purpose. The previous round's win came from
## measuring first; "it looks emptier now" is not a result. This probe is the deliverable as
## much as the boards are.
##
## WHAT IT CHECKS, and where each rule comes from (`docs/ARENA_DESIGN.md` unless noted):
##
##   DENSITY CEILING  §1 — "one piece of cover per 300 square units. Hard ceiling."
##                    `ArenaLayout.AREA_PER_PIECE` carries `GEOMETRY_SCALE²` on top, because it
##                    is an area and the body grew. Exceeding it is CLUTTER.
##   DENSITY FLOOR    ⚠️ NOT IN THE DOC AS A NUMBER, AND SAID SO OUT LOUD. §1 is a ceiling only,
##                    which is why eight pieces on a 108,000-unit ground passed every existing
##                    guard while reading as an empty car park. The floor here is NOT invented:
##                    it is `ceiling / DENSITY_SAFETY_FACTOR` — the target the generator's own
##                    scatter path already aims at (`_target_pairs`) — taken at half strength so
##                    an authored composition may be sparser than a scatter but not emptier than
##                    half of it. One constant, derived from a constant already in the file.
##   COVER FRACTION   §4's Silver failure ("shipped at 0.79% cover") is the low end; the
##                    `AREA_PER_PIECE` header records that ~7% "buries the ground in cover" and
##                    that boards measured 1.3-1.4% before the geometry lift. Band: 1.5%-6.5%.
##   SIGNATURE        §4 — "No two boards share a LAYOUT SIGNATURE." The five axes an eye sorts
##                    on before it reads any detail: piece COUNT, how many are long BARS, how
##                    many are CHUNKY blocks, how far the mass sits from centre in X, and in Y.
##                    Hashed; a collision between two leagues FAILS.
##   SYMMETRY         §5 — 180-degree rotational fairness is not negotiable. Every piece must
##                    have a partner at `g - pos - size`, or BE that partner (a centrepiece on
##                    the axis is its own, and §4 says it is emitted once).
##   DETERMINISM      `docs/SPATIAL_HANDOFF.md` §1 — same league + same seed -> byte-identical
##                    board, or replays diverge. Generated twice and diffed, every league.
##
## Exit code is the result: 0 clean, 1 if any league fails any check.
extends Node

const Sp = preload("res://scripts/spatial.gd")
const Layout = preload("res://scripts/arena_layout.gd")

## Wood -> Tamers Apex, with the team size each fields (`data/data.json:teamSizeByLeague`,
## mirrored here so the probe does not need the career autoload booted).
const LEAGUES := [
	["Wood", 1], ["Copper", 2], ["Tin", 2], ["Bronze", 3], ["Iron", 3],
	["Silver", 4], ["Gold", 4], ["Platinum", 5], ["Masters", 5],
	["Tamer Elite", 5], ["Tamers Apex", 5],
]

## The seed the real battle screen uses (`arena_3d.gd:_prepare_layout`). Measuring on any other
## seed would measure a board no player ever sees.
const ARENA_SEED := 20260804

## See the header. Half the generator's own scatter target.
const FLOOR_FRACTION_OF_SCATTER_TARGET := 0.5

const COVER_FRACTION_MIN := 0.015
const COVER_FRACTION_MAX := 0.065

## A piece is a BAR if it is at least this many times longer than it is deep; CHUNKY if it is
## within this ratio of square AND at least a body across. The two silhouette families §4 names
## ("swap the mass from bars to blocks... the single biggest lever").
##
## ⚠️ CHUNKY_RATIO IS 2.5 BECAUSE A COMPOSITION'S MAJORS ARE 0.42 DEEP, ratio 2.38. At 2.0 the
## four pieces that DEFINE every board counted as neither family, so the two axes the doc calls
## the biggest lever were both blind to the mass itself. Measured, not guessed: the first run of
## this probe reported `b0/k6` for a board whose four majors are its entire silhouette.
const BAR_RATIO := 3.0
const CHUNKY_RATIO := 2.5

# ═══════════════════════════════════════════════════════════════════════════════════════════════
# COMPOSITION — the second table, and the one that catches DEBRIS
# ═══════════════════════════════════════════════════════════════════════════════════════════════
#
# ⚠️ THE FIRST TABLE PASSES ON A BOARD THAT LOOKS LIKE A RASH, AND THAT IS THE GAP THIS CLOSES.
# Every check above is about QUANTITY (count, ceiling, floor, covered fraction) or about
# DIFFERENCE BETWEEN boards (signature, geometry hash). None of them can see the thing the
# integrator saw looking at eleven frames: "the accent layer is debris, not architecture" —
# a hundred near-identical half-body props scattered evenly over the floor. That board has a
# perfect count, a perfect cover fraction and a unique signature.
#
# `ARENA_DESIGN.md` §3 already states the rule in words — ⚠️ "FEWER AND LARGER, ALWAYS. Five
# small pieces give a board where nothing fully blocks a lane and every position is about as
# good as every other — busy, with no decision in it." — and §2, "architecture is the default;
# trade is the accent". Neither had a number. These are those numbers.
#
# Three measures, each aimed at one half of the word "debris":
#
#   SMALL       max footprint dimension under `SMALL_MAX_BODIES` body diameters. Straight from
#               this file's own KIND_TABLE header: "cover you are wider than does not hide you".
#               One body is the floor of usefulness, so two is where a piece stops being an
#               object and starts being a structure you could put a shoulder to.
#   SINGLETON   nothing else within `LINK_GAP_BODIES` body diameters of its edge. A colonnade,
#               a wall with a gate, a stand of stalls — every one of them is several pieces
#               close enough that the eye binds them into one thing. A piece with clear floor
#               all around it is read on its own.
#   DEBRIS      SMALL **and** SINGLETON. Neither alone is a fault: a lone gatehouse mass is a
#               singleton and it is the best piece on the board; a tight run of small columns
#               is small and it is a colonnade. It is the CONJUNCTION that reads as litter.
#
# Plus two vocabulary measures, because "many identical small shapes" is the other half of the
# complaint and a debris count alone would pass a board made of forty tightly-packed clones:
#
#   SIZES       distinct STRUCTURE sizes, quantised to `SIZE_QUANT` units.
#   TOP SHARE   the largest single structure size as a share of the board's structures.
#
# ⚠️ THOSE TWO COUNT STRUCTURES, NOT PIECES, AND THE FIRST VERSION COUNTED PIECES — WHICH FAILED
# THE CORRECT ANSWER. Per piece, a ten-bay colonnade is "one prop repeated ten times" and trips a
# monotony check at 64%. But a colonnade IS ten copies of one column; that is what makes it a
# colonnade rather than a pile, and §2 asks for exactly that. Repetition INSIDE a structure is
# architecture; repetition ACROSS a board is monotony, and only the second is a fault. So each
# cluster contributes its LARGEST piece's size once — the scale an eye reads the structure at.
# Found by measuring, not by reasoning: the piece-level version failed Silver's cloister and
# Iron's gatehouse, the two boards whose composition had improved most.

## A piece under this many body diameters on its LONGEST side is small. `Sp.BODY_RADIUS * 2` is
## the body diameter, so this is "less than two monsters wide".
const SMALL_MAX_BODIES := 2.0

## Edge-to-edge gap, in body diameters, under which two pieces read as ONE structure. Set at the
## width of a monster on purpose: if a body cannot walk between two pieces they are a wall, and
## the same threshold is what the pathing sees.
const LINK_GAP_BODIES := 1.0

## Footprint dimensions are bucketed to this many world units before counting distinct sizes —
## two pieces within half a body of each other in both axes are the same shape to an eye.
const SIZE_QUANT := 2.2

## ⚠️ SET FROM THE MEASURED BASELINE, NOT PICKED. The pre-rework boards measured debris fractions
## of 0.14-0.85 with a MEDIAN OF 0.71 — on eight of eleven leagues, four pieces in five were a
## small isolated prop. 0.20 is comfortably under the best board that existed (Gold, 0.14) and
## reachable everywhere by grouping, so it fails the composition that shipped and passes an
## authored one.
##
## ⚠️ AND GOLD SCORING BEST IS THE EVIDENCE THE MEASURE IS POINTED AT THE RIGHT THING. Gold is the
## one league authored as a continuous stepped run rather than a scatter, it is the one board the
## integrator did not call debris, and it is the only one that passes this check unchanged. A
## metric that agreed with the eye on a case nobody tuned it against is worth trusting.
const DEBRIS_FRAC_MAX := 0.20

## ⚠️ THE MEASURE THAT STAYS LIVE AFTER THE PROPS GROW. Raising every prop above two bodies makes
## the debris count easy to satisfy by size alone — which is the intended fix, but it would leave
## nothing watching ARRANGEMENT. This is that watch: the share of pieces belonging to a cluster of
## two or more. Baseline measured 0.00-0.29 (clusters == piece count on nine of eleven leagues:
## nothing on those boards touched anything else). Half is the bar because the family's four
## blocking MAJORS are deliberately standalone masses — a board cannot be asked to group its
## centrepieces — so half the board is the most that can be required to be built.
const GROUPED_FRAC_MIN := 0.50

## At least this many distinct footprint sizes per board. Four is the minimum that can express a
## hierarchy — mass, secondary, accent, trade — which is the size ladder `ARENA_DESIGN.md` §1.4
## (via ARENA_ETHOS_REVIEW) says a composition needs.
const DISTINCT_SIZES_MIN := 4

## No single size class may be more than this share of the board. Above it the board IS that one
## prop, whatever else is standing on it.
const TOP_SIZE_SHARE_MAX := 0.42

# ═══════════════════════════════════════════════════════════════════════════════════════════════
# PASSAGE — can a formation still cross the board?
# ═══════════════════════════════════════════════════════════════════════════════════════════════
#
# ⚠️ ADDED BECAUSE NOTHING IN THE BATTERY MEASURED PATHING ON THE REAL LEAGUE BOARDS, AND I
# ALMOST REPORTED THAT IT DID. `_probe_sim_quality.gd` line 26 says it out loud — "THE OBSTACLE
# FIELD IS DELIBERATELY *NOT* `arena_layout.gd`'s" — so its path-efficiency figure held at 0.98/0.99
# across this whole rework for the simple reason that it never saw any of it. An unchanged number
# from an instrument that is not connected to the thing you changed is the most expensive kind of
# green: it reads exactly like evidence and is not.
#
# This is the geometry-only replacement, and it is deliberately not a navmesh bake: it needs no
# scene, no `NavigationServer3D` and no async wait, so it stays inside a probe that must remain
# fast and exactly reproducible. Flood fill on a grid, from one deploy band to the other, with the
# obstacles inflated by a clearance radius; binary-search the largest clearance that still gets
# across. Twice that is the board's BOTTLENECK — the narrowest place the whole fight has to funnel
# through.
#
# ⚠️ IT COUNTS `blocking` PIECES ONLY, BECAUSE THAT IS WHAT THE SIM COUNTS. `arena_3d.gd` carves
# only blocking-grade obstacles into the navmesh (`_build_nav`), so a colonnade of hard-grade piers
# costs accuracy and does not obstruct a path. Measuring soft and hard here would report a
# bottleneck the engine does not have, and the whole point of this check is to say what the sim
# will do.
const GRID_STEP := 2.0

## The board must admit at least this many body-widths of clear corridor end to end. One body is
## survival; two is a formation. A 5v5 line is five bodies of frontage, so this does NOT promise
## the team crosses abreast — it promises the board never funnels them into single file, which is
## the failure a wall-and-gate composition can introduce and a scatter never could.
const MIN_CORRIDOR_BODIES := 2.0


func _ready() -> void:
	var failures: Array = []
	var seen_signatures: Dictionary = {}   # signature -> first league that used it

	print("BOARD COMPOSITION — %d leagues" % LEAGUES.size())
	print("AREA_PER_PIECE %.0f (300 x GEOMETRY_SCALE^2)   body diameter %.2f   major min width %.1f"
		% [Layout.AREA_PER_PIECE, Sp.BODY_RADIUS * 2.0, Layout.major_min_width()])
	print("")
	print("%-12s %-3s %-11s %8s %6s %6s %7s %5s %5s %5s %5s  %s" % [
		"league", "n", "ground", "area", "piece", "ceil", "cover%", "bars", "blks", "dx", "dy", "signature"])
	print("%s" % "-".repeat(112))

	var comp_rows: Array = []

	for entry in LEAGUES:
		var league: String = entry[0]
		var n: int = entry[1]
		var g: Vector2 = Sp.ground_size(n)
		var area: float = g.x * g.y

		var obs: Array = _gen(n, league)
		var obs2: Array = _gen(n, league)

		for o in obs:
			_seen_kinds[str((o as Dictionary).get("kind", ""))] = true

		var m: Dictionary = _measure(obs, g)
		var intent: int = _intended_pieces(league)
		var ceiling: int = int(floor(area / Layout.AREA_PER_PIECE))
		var scatter_target: float = area / (Layout.AREA_PER_PIECE * Layout.DENSITY_SAFETY_FACTOR)
		var floor_pieces: int = int(round(scatter_target * FLOOR_FRACTION_OF_SCATTER_TARGET))

		print("%-12s %-3d %-11s %8d %6s %6d %6.2f%% %5d %5d %5.2f %5.2f  %s" % [
			league, n, "%dx%d" % [int(g.x), int(g.y)], int(area),
			"%d/%d" % [obs.size(), intent], ceiling, 100.0 * m["cover_fraction"],
			m["bars"], m["chunky"], m["dx"], m["dy"], m["signature"]])

		# ⚠️ SILENT DROPS ARE THE FAILURE MODE OF AN ALL-OR-NOTHING EMITTER. `_emit_pair`
		# refuses a pair that would clip a deploy band, leave the ground or touch a neighbour —
		# correct, and invisible: the author sees a board two pieces lighter and no reason why.
		# Reporting emitted-against-authored is what turns that into a number.
		if obs.size() != intent:
			failures.append("%s: emitted %d pieces from %d authored — %d were dropped by the placement gate (band clash, edge, or a neighbour inside PIECE_GAP)"
				% [league, obs.size(), intent, intent - obs.size()])

		# ── density ceiling
		if obs.size() > ceiling:
			failures.append("%s: %d pieces exceeds the density CEILING of %d (ARENA_DESIGN §1)"
				% [league, obs.size(), ceiling])
		# ── density floor
		if obs.size() < floor_pieces:
			failures.append("%s: %d pieces is below the density FLOOR of %d (half the generator's own scatter target of %.0f) — the board reads as empty"
				% [league, obs.size(), floor_pieces, scatter_target])
		# ── cover fraction
		var cf: float = m["cover_fraction"]
		if cf < COVER_FRACTION_MIN:
			failures.append("%s: cover fraction %.2f%% is under the %.1f%% floor (ARENA_DESIGN §4, the Silver 0.79%% failure)"
				% [league, 100.0 * cf, 100.0 * COVER_FRACTION_MIN])
		if cf > COVER_FRACTION_MAX:
			failures.append("%s: cover fraction %.2f%% is over the %.1f%% ceiling — the ground is buried"
				% [league, 100.0 * cf, 100.0 * COVER_FRACTION_MAX])
		# ── signature uniqueness across leagues
		var sig: String = m["signature"]
		if seen_signatures.has(sig):
			failures.append("%s: LAYOUT SIGNATURE %s is identical to %s — two leagues, one board (ARENA_DESIGN §4)"
				% [league, sig, seen_signatures[sig]])
		else:
			seen_signatures[sig] = league
		# ── exact-geometry duplication, which a signature can miss
		var geo: String = _geometry_hash(obs)
		if _seen_geometry.has(geo):
			failures.append("%s: byte-identical geometry to %s" % [league, _seen_geometry[geo]])
		else:
			_seen_geometry[geo] = league
		# ── symmetry (180-degree rotational, self-mirroring centrepieces allowed)
		for problem in _symmetry_problems(obs, g):
			failures.append("%s: %s" % [league, problem])
		# ── determinism
		if _geometry_hash(obs2) != geo:
			failures.append("%s: NOT DETERMINISTIC — two generations with the same seed differ" % league)
		# ── the structural rules the generator already owns
		for problem in Layout.problems(obs, n):
			failures.append("%s: %s" % [league, problem])

		# ── COMPOSITION: is the accent layer architecture, or debris?
		var comp: Dictionary = _composition(obs)
		var corridor: float = _bottleneck(obs, g)
		comp["corridor"] = corridor
		comp_rows.append([league, obs.size(), comp])
		var body: float = Sp.BODY_RADIUS * 2.0
		if corridor < 0.0:
			failures.append("%s: SEALED — no route across the board at all; the blocking pieces close it end to end"
				% league)
		elif corridor < MIN_CORRIDOR_BODIES * body:
			failures.append("%s: BOTTLENECK — the widest corridor across the board is %.1f units (%.1f bodies), under the %.1f-body minimum; the fight funnels into single file"
				% [league, corridor, corridor / body, MIN_CORRIDOR_BODIES])
		if float(comp["debris_frac"]) > DEBRIS_FRAC_MAX:
			failures.append("%s: DEBRIS — %d of %d pieces are small (<%.1f bodies) AND isolated (>%.1f bodies of clear floor all round), %.0f%% against a %.0f%% ceiling. ARENA_DESIGN §3: fewer and larger, always"
				% [league, int(comp["debris"]), obs.size(), SMALL_MAX_BODIES, LINK_GAP_BODIES,
					100.0 * float(comp["debris_frac"]), 100.0 * DEBRIS_FRAC_MAX])
		if float(comp["grouped_frac"]) < GROUPED_FRAC_MIN:
			failures.append("%s: SCATTER — only %.0f%% of pieces belong to a structure (min %.0f%%); %d pieces form %d clusters. ARENA_DESIGN §2: architecture is the default"
				% [league, 100.0 * float(comp["grouped_frac"]), 100.0 * GROUPED_FRAC_MIN,
					obs.size(), int(comp["clusters"])])
		if int(comp["sizes"]) < DISTINCT_SIZES_MIN:
			failures.append("%s: only %d distinct STRUCTURE sizes (min %d) across %d structures — the board has no size hierarchy"
				% [league, int(comp["sizes"]), DISTINCT_SIZES_MIN, int(comp["clusters"])])
		if float(comp["top_share"]) > TOP_SIZE_SHARE_MAX:
			failures.append("%s: one structure size is %.0f%% of the board's structures (max %.0f%%) — it is that shape repeated, not a composition"
				% [league, 100.0 * float(comp["top_share"]), 100.0 * TOP_SIZE_SHARE_MAX])

	# ── KIND REACHABILITY, across the whole ladder rather than one league.
	# ⚠️ THIS CHECK MOVED HERE FROM `scripts/_probe_kinds.gd`, WHICH NOW REPORTS A FALSE POSITIVE.
	# That probe (its own header calls it "THROWAWAY VERIFICATION... delete freely") generates 120
	# layouts and every one of them is **Wood**, then fails any `KIND_TABLE` kind it did not see. It
	# passed while all eleven leagues were one board, and its premise died the moment each league
	# got its own authored furniture: a kind used on Tin and Platinum is simply not on the Wood
	# board, and never was going to be. It is not this stream's file, so it is reported rather than
	# edited — but the standard behind it is real (`CLAUDE.md`: "an ability that is authored, typed
	# and priced but never drafted does not exist"), so it is re-asked correctly here: every kind
	# must be reachable SOMEWHERE ON THE LADDER.
	var unreachable: Array = []
	for spec in Layout.KIND_TABLE:
		var k: String = str((spec as Dictionary)["kind"])
		if not _seen_kinds.has(k):
			unreachable.append(k)
	if not unreachable.is_empty():
		failures.append("kinds authored in KIND_TABLE but placed on NO league board: %s"
			% ", ".join(unreachable))

	print("")
	print("kinds in use across the ladder: %d of %d" % [_seen_kinds.size(), Layout.KIND_TABLE.size()])
	print("")
	print("COMPOSITION — is the accent layer architecture or debris?")
	print("%-12s %5s %7s %8s %7s %8s %6s %6s %8s %9s" % [
		"league", "n", "clust", "group%", "small", "debris", "sizes", "top%", "med(b^2)", "corridor"])
	print("%s" % "-".repeat(84))
	for row in comp_rows:
		var c: Dictionary = row[2]
		print("%-12s %5d %7d %7.0f%% %7d %3d/%3.0f%% %6d %5.0f%% %8.2f %6.1fb" % [
			row[0], row[1], int(c["clusters"]), 100.0 * float(c["grouped_frac"]),
			int(c["small"]), int(c["debris"]),
			100.0 * float(c["debris_frac"]), int(c["sizes"]),
			100.0 * float(c["top_share"]), float(c["med_bodies"]),
			float(c["corridor"]) / (Sp.BODY_RADIUS * 2.0)])

	print("")
	print("distinct signatures across %d leagues: %d" % [LEAGUES.size(), seen_signatures.size()])
	print("distinct geometries across %d leagues: %d" % [LEAGUES.size(), _seen_geometry.size()])
	print("")

	if failures.is_empty():
		print("LAYOUT PROBE: PASS — %d leagues, every board inside the density law, uniquely composed, symmetric and deterministic" % LEAGUES.size())
		get_tree().quit(0)
	else:
		for f in failures:
			print("  FAIL  %s" % f)
		print("")
		print("LAYOUT PROBE: FAIL — %d problems" % failures.size())
		get_tree().quit(1)


var _seen_geometry: Dictionary = {}
var _seen_kinds: Dictionary = {}


## What the tables ASK FOR, counted straight off the authored data: family majors are authored as
## full 180-degree pairs, accents and furniture as the canonical half only.
func _intended_pieces(league: String) -> int:
	var fam: Dictionary = Layout.LAYOUTS.get("four_pillar", {})
	var total: int = (fam.get("major", []) as Array).size()
	# ⚠️ AN ACCENT IS A STAND NOW, SO IT IS `2 * n`, NOT 2. This line read `2 * accents.size()`
	# while accents were single pieces; leaving it that way would have under-counted the authored
	# board and reported every extra piece as a phantom drop — the check would have failed on the
	# fix rather than on a fault.
	for a in fam.get("accents", []):
		total += 2 * maxi(1, int((a as Dictionary).get("n", 2)))
	var board: Dictionary = Layout.LEAGUE_BOARDS.get(league, {})
	for e in board.get("furniture", []):
		var t: String = str((e as Dictionary).get("t", "post"))
		if t == "run":
			total += 2 * maxi(1, int((e as Dictionary).get("n", 3)))
		else:
			total += 2
	return total


func _gen(n: int, league: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = ARENA_SEED
	# The battle screen's own call shape — layout id defaulted, league carried.
	return (Layout.generate(n, league, rng) as Dictionary).get("obstacles", []) as Array


## The five signature axes of ARENA_DESIGN §4, plus the cover fraction the density law is really
## about. `dx`/`dy` are how far the MASS sits from centre, normalised to the half-ground, so they
## are comparable across team sizes.
func _measure(obs: Array, g: Vector2) -> Dictionary:
	var bars := 0
	var chunky := 0
	var covered := 0.0
	var body := Sp.BODY_RADIUS * 2.0
	var dx_acc := 0.0
	var dy_acc := 0.0
	var w_acc := 0.0
	for o in obs:
		var r: Rect2 = (o as Dictionary)["rect"]
		var a: float = r.size.x * r.size.y
		covered += a
		var lo: float = minf(r.size.x, r.size.y)
		var hi: float = maxf(r.size.x, r.size.y)
		var ratio: float = hi / maxf(lo, 0.001)
		if ratio >= BAR_RATIO:
			bars += 1
		elif ratio <= CHUNKY_RATIO and hi >= body:
			chunky += 1
		var c: Vector2 = r.get_center()
		dx_acc += a * absf(c.x - g.x * 0.5)
		dy_acc += a * absf(c.y - g.y * 0.5)
		w_acc += a
	var dx: float = (dx_acc / maxf(w_acc, 0.001)) / (g.x * 0.5)
	var dy: float = (dy_acc / maxf(w_acc, 0.001)) / (g.y * 0.5)
	# Quantised before hashing: two boards whose mass sits within 5% of the same place ARE the
	# same picture, and an unquantised float would let a rounding difference pass as variety.
	var sig := "c%d/b%d/k%d/x%d/y%d" % [
		obs.size(), bars, chunky, int(round(dx * 20.0)), int(round(dy * 20.0))]
	return {
		"bars": bars, "chunky": chunky, "cover_fraction": covered / (g.x * g.y),
		"dx": dx, "dy": dy, "signature": sig,
	}


## The composition measures — see the COMPOSITION block at the top of the file for what each one
## is for and where its threshold comes from.
##
## ⚠️ CLUSTERING IS SINGLE-LINKAGE ON EDGE-TO-EDGE GAP, NOT ON CENTRES. Centre distance is the
## wrong instrument here by construction: a 40-unit wall and a 6-unit pillar touching end to end
## have centres 23 units apart, so a centre-distance rule would call the two pieces of a gatehouse
## separate and a pair of small props on opposite sides of a lane the same structure. The whole
## question is whether there is FLOOR between them.
func _composition(obs: Array) -> Dictionary:
	var body: float = Sp.BODY_RADIUS * 2.0
	var n: int = obs.size()
	if n == 0:
		return {"debris": 0, "debris_frac": 0.0, "grouped_frac": 0.0, "small": 0, "clusters": 0,
			"sizes": 0, "top_share": 0.0, "med_bodies": 0.0}

	# ── single-linkage clusters by edge gap
	var parent: Array = []
	for i in n:
		parent.append(i)
	var link: float = LINK_GAP_BODIES * body
	for i in n:
		var ri: Rect2 = (obs[i] as Dictionary)["rect"]
		for j in range(i + 1, n):
			var rj: Rect2 = (obs[j] as Dictionary)["rect"]
			if _rect_gap(ri, rj) <= link:
				var a := _find(parent, i)
				var b := _find(parent, j)
				if a != b:
					parent[a] = b
	var members: Dictionary = {}
	for i in n:
		var root := _find(parent, i)
		members[root] = int(members.get(root, 0)) + 1

	# ── small / debris / size vocabulary
	var small := 0
	var debris := 0
	var grouped := 0
	var size_counts: Dictionary = {}   # cluster root -> the size key of its largest piece
	var biggest: Dictionary = {}       # cluster root -> that piece's area
	var areas: Array = []
	for i in n:
		var r: Rect2 = (obs[i] as Dictionary)["rect"]
		var is_small: bool = maxf(r.size.x, r.size.y) < SMALL_MAX_BODIES * body
		var alone: bool = int(members[_find(parent, i)]) == 1
		if not alone:
			grouped += 1
		if is_small:
			small += 1
			if alone:
				debris += 1
		# The structure's size is its LARGEST piece — a gate jamb with a crate leaning on it is
		# read at the jamb's scale, not averaged with the crate.
		var root := _find(parent, i)
		var a: float = r.size.x * r.size.y
		if a > float(biggest.get(root, -1.0)):
			biggest[root] = a
			size_counts[root] = "%d/%d" % [
				int(round(minf(r.size.x, r.size.y) / SIZE_QUANT)),
				int(round(maxf(r.size.x, r.size.y) / SIZE_QUANT))]
		areas.append(a / (body * body))
	areas.sort()
	var key_counts: Dictionary = {}
	for root in size_counts:
		var k: String = str(size_counts[root])
		key_counts[k] = int(key_counts.get(k, 0)) + 1
	var top := 0
	for k in key_counts:
		top = maxi(top, int(key_counts[k]))
	return {
		"debris": debris,
		"debris_frac": float(debris) / float(n),
		"grouped_frac": float(grouped) / float(n),
		"small": small,
		"clusters": members.size(),
		"sizes": key_counts.size(),
		"top_share": float(top) / float(maxi(1, members.size())),
		"med_bodies": float(areas[n / 2]),
	}


## The widest corridor, in world units, that still crosses the board from one deploy end to the
## other. Binary search on clearance; -1.0 if not even a point can get across (a sealed board).
func _bottleneck(obs: Array, g: Vector2) -> float:
	var walls: Array = []
	for o in obs:
		if str((o as Dictionary).get("grade", "")) == "blocking":
			walls.append((o as Dictionary)["rect"] as Rect2)
	if walls.is_empty():
		return g.y      # nothing blocks: the corridor is the whole board
	if not _crosses(walls, g, 0.0):
		return -1.0
	var lo := 0.0
	var hi: float = g.y * 0.5
	for _i in 12:
		var mid: float = 0.5 * (lo + hi)
		if _crosses(walls, g, mid):
			lo = mid
		else:
			hi = mid
	return 2.0 * lo


## Grid flood fill from the x<0 end to the x>W end, treating every wall grown by `clear` as solid.
func _crosses(walls: Array, g: Vector2, clear: float) -> bool:
	var nx: int = int(ceil(g.x / GRID_STEP))
	var ny: int = int(ceil(g.y / GRID_STEP))
	var blocked: PackedByteArray = PackedByteArray()
	blocked.resize(nx * ny)
	for w in walls:
		var r: Rect2 = (w as Rect2).grow(clear)
		var x0: int = clampi(int(floor(r.position.x / GRID_STEP)), 0, nx - 1)
		var x1: int = clampi(int(ceil((r.position.x + r.size.x) / GRID_STEP)), 0, nx - 1)
		var y0: int = clampi(int(floor(r.position.y / GRID_STEP)), 0, ny - 1)
		var y1: int = clampi(int(ceil((r.position.y + r.size.y) / GRID_STEP)), 0, ny - 1)
		for gy in range(y0, y1 + 1):
			for gx in range(x0, x1 + 1):
				blocked[gy * nx + gx] = 1
	# The board's own edge is a wall too: a body needs `clear` of room inside it.
	var margin: int = int(ceil(clear / GRID_STEP))
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(nx * ny)
	var stack: Array[int] = []
	for gy in range(margin, ny - margin):
		var idx: int = gy * nx + margin
		if blocked[idx] == 0 and seen[idx] == 0:
			seen[idx] = 1
			stack.append(idx)
	var goal_x: int = nx - 1 - margin
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		var cx: int = cur % nx
		var cy: int = cur / nx
		if cx >= goal_x:
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ax: int = cx + d.x
			var ay: int = cy + d.y
			if ax < margin or ax > goal_x or ay < margin or ay >= ny - margin:
				continue
			var ni: int = ay * nx + ax
			if blocked[ni] == 0 and seen[ni] == 0:
				seen[ni] = 1
				stack.append(ni)
	return false


## Shortest distance between two axis-aligned rects; 0 when they touch or overlap.
func _rect_gap(a: Rect2, b: Rect2) -> float:
	var dx: float = maxf(0.0, maxf(a.position.x - (b.position.x + b.size.x),
		b.position.x - (a.position.x + a.size.x)))
	var dy: float = maxf(0.0, maxf(a.position.y - (b.position.y + b.size.y),
		b.position.y - (a.position.y + a.size.y)))
	return sqrt(dx * dx + dy * dy)


func _find(parent: Array, i: int) -> int:
	var r: int = i
	while int(parent[r]) != r:
		r = int(parent[r])
	while int(parent[i]) != i:
		var nx: int = int(parent[i])
		parent[i] = r
		i = nx
	return r


## Exact geometry, order-independent — catches "same board, different league" even when the
## signature axes coincidentally differ.
func _geometry_hash(obs: Array) -> String:
	var parts: Array = []
	for o in obs:
		var r: Rect2 = (o as Dictionary)["rect"]
		parts.append("%.3f,%.3f,%.3f,%.3f,%s,%s" % [
			r.position.x, r.position.y, r.size.x, r.size.y,
			str((o as Dictionary).get("grade", "")), str((o as Dictionary).get("kind", ""))])
	parts.sort()
	return str(hash("|".join(parts)))


## ⚠️ ACCEPTS A SELF-MIRRORING CENTREPIECE, which `ArenaLayout.problems()` did not.
## `ARENA_DESIGN.md` §4: "A centrepiece sits at exactly (w - size)/2 — it is its own 180-degree
## partner and is emitted once". A pairing check that demands a distinct partner rejects the one
## arrangement the doc explicitly authorises.
func _symmetry_problems(obs: Array, g: Vector2) -> Array:
	var out: Array = []
	var matched: Array = []
	for i in obs.size():
		matched.append(false)
	for i in obs.size():
		if matched[i]:
			continue
		var r: Rect2 = (obs[i] as Dictionary)["rect"]
		var want := Rect2(g - r.position - r.size, r.size)
		if r.position.distance_to(want.position) < 0.01:
			matched[i] = true      # its own partner, on the axis
			continue
		var found := -1
		for j in range(i + 1, obs.size()):
			if matched[j]:
				continue
			var rj: Rect2 = (obs[j] as Dictionary)["rect"]
			if rj.position.distance_to(want.position) < 0.01 and rj.size.distance_to(want.size) < 0.01:
				found = j
				break
		if found == -1:
			out.append("symmetry: piece %d at %s has no 180-degree partner" % [i, r])
		else:
			matched[i] = true
			matched[found] = true
	return out
