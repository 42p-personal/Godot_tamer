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

	for entry in LEAGUES:
		var league: String = entry[0]
		var n: int = entry[1]
		var g: Vector2 = Sp.ground_size(n)
		var area: float = g.x * g.y

		var obs: Array = _gen(n, league)
		var obs2: Array = _gen(n, league)

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


## What the tables ASK FOR, counted straight off the authored data: family majors are authored as
## full 180-degree pairs, accents and furniture as the canonical half only.
func _intended_pieces(league: String) -> int:
	var fam: Dictionary = Layout.LAYOUTS.get("four_pillar", {})
	var total: int = (fam.get("major", []) as Array).size() + 2 * (fam.get("accents", []) as Array).size()
	var board: Dictionary = Layout.LEAGUE_BOARDS.get(league, {})
	for e in board.get("furniture", []):
		var t: String = str((e as Dictionary).get("t", "post"))
		if t == "row":
			total += 2 * maxi(1, int((e as Dictionary).get("n", 2)))
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
