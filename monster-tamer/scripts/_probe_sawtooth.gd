## THE SAWTOOTH DECOMPOSITION — WHY is the ADVANCE column jagged?
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_sawtooth.tscn
##      -- --seeds 96          cups per rung (default 96; a proportion at n=32 carries +/-9 pts)
##      -- --quick             seeds 16, for a smoke pass
##      -- --smooth            ALSO run the smooth-climber-table counterfactual (doubles runtime)
##      -- --liveness          the canary alone
##
## ⚠️ RUNS AS A SCENE, NEVER `--script` — it needs the Career/Roster/GameData/Art autoloads.
##
## ── WHAT THIS ANSWERS ────────────────────────────────────────────────────────────────────────
## `_probe_ladder_slope` reports ADVANCE per rung and nothing about WHY it moves. ADVANCE under
## the drop-one rule is a deterministic function of three things:
##     (1) the per-round win probability vector p[r] at that rung
##     (2) the NUMBER OF ROUNDS in the draw          (`rival_count_for_league`: 3 3 3 3 3 4 4 5 5 5 5)
##     (3) whether the rung forgives a dropped round (`dropped_rounds_allowed`: 1 everywhere, 0 at Apex)
## So the sawtooth is either in (1) — the field is genuinely non-monotone — or in (2)/(3) — the
## per-round difficulty is smooth and the COMBINATORICS are making it jagged. Those two have
## completely different fixes, and nobody has separated them.
##
## This probe measures p[r] directly, reconstructs ADVANCE from it analytically (Poisson-binomial
## over the real rule), checks the reconstruction against the empirical ADVANCE from the SAME cups,
## and then runs counterfactuals that hold one term fixed at a time.
##
## ── ⚠️ THE COPY, AND WHY IT IS SAFE ──────────────────────────────────────────────────────────
## Section 5 needs to price a field against a DIFFERENT climber table, and
## `career.gd:CLIMBER_FILL_BY_LEAGUE` is a `const` this probe does not own and must not edit. So
## `_field_fill_with()` is a re-implementation of `Career.field_fill()` parameterised by the
## climber table. A second copy of a model is this project's most expensive recurring bug, so the
## canary ASSERTS the copy reproduces `Career.field_fill()` exactly, for every (rung, rounds,
## round index) triple, before any number is printed. If it drifts, the probe exits non-zero.
extends Node

const BattleSimScript = preload("res://scripts/battle_sim.gd")
const TacticsScript = preload("res://scripts/tactics.gd")

const STATS_PER_MONSTER := 6.0

var seeds := 96
var do_smooth := false
var do_kinds := false
var do_cf := false
var _tree: SceneTree
var _fights := 0
var _fail := false


func _ready() -> void:
	_tree = get_tree()
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	if "--quick" in args:
		seeds = 16
	for i in range(args.size()):
		if str(args[i]) == "--seeds" and i + 1 < args.size():
			seeds = maxi(4, int(str(args[i + 1])))
	do_smooth = "--smooth" in args
	do_kinds = "--kinds" in args
	do_cf = "--cf" in args

	print("=== SAWTOOTH DECOMPOSITION PROBE ===")
	print("  cups per rung: %d" % seeds)

	if not _liveness():
		print("\n=== sawtooth probe: INSTRUMENT FAILED — numbers not printed ===")
		_tree.quit(1)
		return
	if "--liveness" in args:
		print("\n=== sawtooth probe (liveness only): OK ===")
		_tree.quit(0)
		return

	_print_structure()
	var real: Array = Career.CLIMBER_FILL_BY_LEAGUE.duplicate()
	var meas: Array = _measure_all(real, "MEASURED table (career.gd as shipped)")
	_reconstruct(meas)
	_decompose(meas)
	_correlations(meas, real)

	if do_kinds:
		_archetype_parity(meas)

	## ── 8. THE TWO SUSPECTS, TURNED OFF ONE AT A TIME ────────────────────────────────────────
	## `--cf` re-measures the whole ladder with (a) `FIELD_DEPTH_RELIEF_PER_ROUND` and
	## `FIELD_APEX_QUAL_RELIEF` set to zero, and (b) every champion forced to ONE kind. Those are
	## the only two authored discontinuities that land where the ADVANCE row jumps. Nothing is
	## committed — this is a measurement of what each is worth.
	if do_cf:
		var rows: Array = [{"advance": [], "label": "A  as shipped"}]
		var cf_a: Array = _measure_all(real, "COUNTERFACTUAL: depth relief = 0", {"no_relief": true})
		var cf_b: Array = _measure_all(real, "COUNTERFACTUAL: every champion is `bulwark` (FILL_MULT 1.00)",
			{"champ_kind": "bulwark"})
		var cf_c: Array = _measure_all(real, "COUNTERFACTUAL: both", {"no_relief": true, "champ_kind": "bulwark"})
		_cf_report(meas, cf_a, cf_b, cf_c)

	if do_smooth:
		var smooth: Array = _smooth_table(real)
		var s_meas: Array = _measure_all(smooth, "SMOOTH monotone table (counterfactual, NOT committed)")
		_compare_rows(meas, s_meas, real, smooth)

	print("\n%d simulated fights" % _fights)
	print("=== sawtooth probe: %s ===" % ("OK" if not _fail else "FAILED"))
	_tree.quit(1 if _fail else 0)


# =============================================================================
# LIVENESS — rule 9. Three canaries, any of which failing invalidates everything below.
# =============================================================================
func _liveness() -> bool:
	print("\n─── LIVENESS ───")
	var ok := true

	# 1. THE COPY IS THE COPY. `_field_fill_with(real_table)` must equal `Career.field_fill()`
	#    exactly, for every (rung, rounds, round) triple the ladder can produce.
	var real: Array = Career.CLIMBER_FILL_BY_LEAGUE.duplicate()
	var worst := 0.0
	for idx in range(Career.leagues.size()):
		for rounds in range(1, 7):
			for r in range(rounds):
				var a: float = Career.field_fill(r, rounds, idx)
				var b: float = _field_fill_with(r, rounds, idx, real)
				worst = maxf(worst, absf(a - b))
	print("  field_fill copy vs career.gd:  max |diff| %.6f   %s" % [
		worst, "OK" if worst < 1e-6 else "DRIFTED"])
	ok = ok and worst < 1e-6

	# 2. THE SUBSTITUTION MOVES THE FIELD. A counterfactual table that changes nothing measures
	#    nothing — the whole of section 5 would be a null by construction.
	var probe_table: Array = []
	for i in range(real.size()):
		probe_table.append(0.60)
	var moved := 0.0
	for idx in range(Career.leagues.size()):
		var rounds: int = Career.rival_count_for_league(idx)
		for r in range(rounds):
			moved = maxf(moved, absf(_field_fill_with(r, rounds, idx, real)
				- _field_fill_with(r, rounds, idx, probe_table)))
	print("  substituted table moves fill:  max |diff| %.3f   %s" % [
		moved, "OK" if moved > 0.02 else "DEAD"])
	ok = ok and moved > 0.02

	# 3. THE FIGHT RESPONDS. Per-round win rate must rise with player fill, or every p[r] below
	#    is noise around a constant.
	var mid: int = Career.leagues.size() / 2
	var lo := _round_rate(mid, 0.30, 6)
	var hi := _round_rate(mid, 0.95, 6)
	print("  round win rate vs player fill: %.0f%% at .30 -> %.0f%% at .95   %s" % [
		lo * 100.0, hi * 100.0, "OK" if hi > lo + 0.10 else "DEAD"])
	ok = ok and hi > lo + 0.10

	if not ok:
		print("  ⚠️ CANARY FAILED — the probe is not measuring what it claims to.")
	return ok


## Crude helper for canary 3 only: fraction of ALL rounds won across `n` cups at `fill`.
func _round_rate(idx: int, fill: float, n: int) -> float:
	var w := 0
	var t := 0
	var table: Array = Career.CLIMBER_FILL_BY_LEAGUE.duplicate()
	for a in range(n):
		var res: Array = _run_cup(idx, fill, a, table)
		for x in res:
			t += 1
			if bool(x):
				w += 1
	return float(w) / float(maxi(1, t))


# =============================================================================
# THE COPY OF THE FIELD MODEL, PARAMETERISED BY THE CLIMBER TABLE
# =============================================================================
## Byte-for-byte `Career.field_fill()` with `expected_climber_fill(league)` replaced by a lookup
## into `table`. Asserted equal to the original by canary 1.
func _field_fill_with(round_idx: int, rounds: int, idx: int, table: Array, no_relief: bool = false) -> float:
	var r: int = maxi(1, rounds)
	var climber: float = clampf(float(table[clampi(idx, 0, table.size() - 1)]), 0.05, 1.0)
	var relief: float = 0.0
	if not no_relief:
		relief = float(maxi(0, r - 3)) * Career.FIELD_DEPTH_RELIEF_PER_ROUND
		if Career.is_final_league(idx):
			relief += Career.FIELD_APEX_QUAL_RELIEF
	var lt: float = Career.ladder_shape(idx)
	var qual_top: float = lerpf(Career.FIELD_QUAL_RATIO_BOTTOM, Career.FIELD_QUAL_RATIO_TOP, lt) - relief
	if round_idx >= r - 1:
		var cbase: float = (qual_top + Career.champion_gap(idx)) * climber
		if Career.has_beaten_champion(idx):
			cbase += Career.CHAMPION_REMATCH_BUMP
		return clampf(cbase, 0.05, 0.98)
	var opener: float = qual_top - lerpf(Career.FIELD_DRAW_RAMP_BOTTOM, Career.FIELD_DRAW_RAMP_TOP, lt)
	var t: float = 0.0 if r <= 2 else clampf(float(round_idx) / float(r - 2), 0.0, 1.0)
	return clampf(lerpf(opener, qual_top, t) * climber, 0.05, 0.98)


# =============================================================================
# ONE CUP — same construction as `career.gd:make_cup_field` + `_probe_ladder_slope:_run_cup`
# =============================================================================
func _player_team(idx: int, fill: float, salt: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5100 + salt * 37 + idx
	var prev: int = Career.league_index
	Career.league_index = idx
	var team: Array = []
	for i in range(Career.team_size_for_league(idx)):
		var species: String = Art.ROSTER[(salt * 3 + i * 5) % Art.ROSTER.size()]
		var mi = GameData.make_monster(species, clampf(fill, 0.0, 1.0), rng, 1.0)
		if mi != null:
			team.append(mi)
	Career.league_index = prev
	return team


## Returns Array[bool] — one per round, won or not. Uses `table` to price the field.
## `cf` is the counterfactual switchboard (section 8): {"no_relief": bool, "champ_kind": String}.
## Empty = the ladder exactly as shipped.
func _run_cup(idx: int, fill: float, attempt: int, table: Array, cf: Dictionary = {}) -> Array:
	var prev_week: int = Career.week
	Career.week = 1 + attempt * 4
	Career.league_index = idx
	var rounds: int = maxi(1, Career.rival_count_for_league(idx))
	var size: int = Career.team_size_for_league(idx)
	var base_seed: int = Career.cup_field_seed(idx)
	var learned: Array = Career.archetypes_taught_by(idx)
	var wins: Array = []
	for r in range(rounds):
		var is_champ: bool = r == rounds - 1
		var gid: String = TacticsScript.archetype_for_league(idx) if is_champ \
			else String(learned[abs(base_seed + r * 31) % maxi(1, learned.size())])
		if is_champ and String(cf.get("champ_kind", "")) != "":
			gid = String(cf["champ_kind"])
		var ffill: float = _field_fill_with(r, rounds, idx, table, bool(cf.get("no_relief", false)))
		var rivals: Array = Career.make_league_rivals(size, idx, ffill,
			abs(base_seed + r * 7919) % 2147483647, gid)
		var team: Array = _player_team(idx, fill, attempt * 11 + r)
		for m in team:
			m.reset_for_battle()
		for m in rivals:
			m.reset_for_battle()
		var rng := RandomNumberGenerator.new()
		rng.seed = 41000 + idx * 313 + attempt * 17 + r
		var plan_b: Dictionary = TacticsScript.team_plan_for_gameplan(gid, team)
		var orders: Dictionary = TacticsScript.orders_for_gameplan(gid, rivals)
		var sim = BattleSimScript.new(team, rivals, rng.randi(), {}, plan_b, orders)
		_fights += 1
		wins.append(str(sim.run().get("winner", "")) == "A")
	Career.week = prev_week
	return wins


# =============================================================================
# 1. THE STRUCTURE — every term the sawtooth could live in, printed side by side
# =============================================================================
func _print_structure() -> void:
	print("\n─── 1. STRUCTURE (the terms ADVANCE is a function of) ───")
	print("  league        cap  team  rnds  need  drop  fill   champFill  openFill")
	for idx in range(Career.leagues.size()):
		var rounds: int = Career.rival_count_for_league(idx)
		print("  %-12s %4.0f    %d     %d    %d/%d    %d   %.2f    %.3f      %.3f" % [
			Career.league_at(idx).get("name", "?"),
			Career.stat_cap_for_league(idx),
			Career.team_size_for_league(idx),
			rounds,
			Career.wins_needed_to_advance(idx, rounds), rounds,
			Career.dropped_rounds_allowed(idx),
			Career.expected_climber_fill(idx),
			Career.field_fill(rounds - 1, rounds, idx),
			Career.field_fill(0, rounds, idx),
		])


# =============================================================================
# 2. PER-ROUND WIN PROBABILITY — the term nobody has measured
# =============================================================================
## Returns Array of {idx, rounds, need, p: Array[float] per round, advance, sweep, pbar}
func _measure_all(table: Array, label: String, cf: Dictionary = {}) -> Array:
	print("\n─── 2. PER-ROUND WIN PROBABILITY — %s ───" % label)
	print("  league        fill  rnds |  p[0]  p[1]  p[2]  p[3]  p[4] | pbar  ADVANCE  TITLE")
	var out: Array = []
	for idx in range(Career.leagues.size()):
		var fill: float = Career.expected_climber_fill(idx)
		var rounds: int = maxi(1, Career.rival_count_for_league(idx))
		var need: int = Career.wins_needed_to_advance(idx, rounds)
		var hits: Array = []
		for r in range(rounds):
			hits.append(0)
		var adv := 0
		var swept := 0
		for a in range(seeds):
			var wins: Array = _run_cup(idx, fill, a, table, cf)
			var w := 0
			for r in range(wins.size()):
				if bool(wins[r]):
					hits[r] = int(hits[r]) + 1
					w += 1
			if w >= need:
				adv += 1
			if w == rounds:
				swept += 1
		var p: Array = []
		var psum := 0.0
		for r in range(rounds):
			var v: float = float(hits[r]) / float(seeds)
			p.append(v)
			psum += v
		var row := {
			"idx": idx, "rounds": rounds, "need": need, "p": p,
			"pbar": psum / float(rounds),
			"advance": float(adv) / float(seeds),
			"sweep": float(swept) / float(seeds),
			"fill": fill,
		}
		out.append(row)
		var cells := ""
		for r in range(5):
			cells += ("%5.2f " % float(p[r])) if r < rounds else "    . "
		print("  %-12s  %.2f   %d  | %s| %.2f   %4.0f%%   %4.0f%%" % [
			Career.league_at(idx).get("name", "?"), fill, rounds, cells,
			float(row["pbar"]), float(row["advance"]) * 100.0, float(row["sweep"]) * 100.0])
	print("  p[0] = the opener, p[rnds-1] = the champion. THE QUESTION: is p smooth where ADVANCE is not?")
	return out


# =============================================================================
# 3. RECONSTRUCTION — does the analytic rule reproduce the empirical ADVANCE?
# =============================================================================
## Poisson-binomial: P(at least `need` successes) given independent per-round probabilities.
func _p_at_least(p: Array, need: int) -> float:
	var dist: Array = [1.0]
	for q in p:
		var nxt: Array = []
		nxt.resize(dist.size() + 1)
		nxt.fill(0.0)
		for k in range(dist.size()):
			nxt[k] = float(nxt[k]) + float(dist[k]) * (1.0 - float(q))
			nxt[k + 1] = float(nxt[k + 1]) + float(dist[k]) * float(q)
		dist = nxt
	var s := 0.0
	for k in range(need, dist.size()):
		s += float(dist[k])
	return s


func _reconstruct(meas: Array) -> void:
	print("\n─── 3. RECONSTRUCTION (analytic rule from measured p[] vs the empirical ADVANCE) ───")
	print("  If these agree, ADVANCE is FULLY explained by (p vector, round count, drop rule) and")
	print("  the decomposition below is complete. If they disagree, rounds are CORRELATED within a")
	print("  cup (the same player build fights all of them) and that correlation is itself a term.")
	print("  league        empirical  analytic   diff")
	var worst := 0.0
	var sumabs := 0.0
	for row in meas:
		var a: float = _p_at_least(row["p"], int(row["need"]))
		var e: float = float(row["advance"])
		worst = maxf(worst, absf(a - e))
		sumabs += absf(a - e)
		print("  %-12s   %4.0f%%      %4.0f%%    %+4.0f" % [
			Career.league_at(int(row["idx"])).get("name", "?"), e * 100.0, a * 100.0, (a - e) * 100.0])
	print("  mean |diff| %.1f pts, worst %.1f pts  (sampling noise alone is ~%.1f pts at n=%d)" % [
		sumabs / float(meas.size()) * 100.0, worst * 100.0, 100.0 * 0.5 / sqrt(float(seeds)), seeds])


# =============================================================================
# 4. THE DECOMPOSITION — hold one term fixed, see how much of the shape survives
# =============================================================================
func _spread(xs: Array) -> float:
	var lo := 9.0
	var hi := -9.0
	for x in xs:
		lo = minf(lo, float(x))
		hi = maxf(hi, float(x))
	return hi - lo


## Total absolute rung-to-rung movement — the direct measure of "how jagged is this row".
func _roughness(xs: Array) -> float:
	var s := 0.0
	for i in range(1, xs.size()):
		s += absf(float(xs[i]) - float(xs[i - 1]))
	return s


## Sum of the UPWARD steps only — a rung easier than the one below it is the inversion this
## project has named as its progression failure mode. This is the sawtooth, quantified.
func _inversion_mass(xs: Array) -> float:
	var s := 0.0
	for i in range(1, xs.size()):
		var d: float = float(xs[i]) - float(xs[i - 1])
		if d > 0.0:
			s += d
	return s


func _count_inversions(xs: Array, thresh: float) -> int:
	var n := 0
	for i in range(1, xs.size()):
		if float(xs[i]) > float(xs[i - 1]) + thresh:
			n += 1
	return n


func _decompose(meas: Array) -> void:
	print("\n─── 4. DECOMPOSITION (each row is ADVANCE with ONE term neutralised) ───")
	var n: int = meas.size()

	# A — actual, analytic (so every counterfactual is computed the same way)
	var A: Array = []
	# B — STRUCTURE ONLY: every rung gets the ladder-mean per-round probability, keeps its own
	#     round count and drop rule. Whatever shape survives is PURE COMBINATORICS.
	var B: Array = []
	# C — FIELD ONLY: every rung keeps its own mean per-round probability, but is forced onto the
	#     3-round / drop-one structure. Whatever shape survives is the FIELD's own difficulty.
	var C: Array = []
	# D — own p-bar, own structure: removes only the within-cup round-to-round shape (opener vs
	#     champion), so A-D isolates how much the ARC of a cup matters.
	var D: Array = []
	var grand := 0.0
	for row in meas:
		grand += float(row["pbar"])
	grand /= float(n)

	for row in meas:
		var rounds: int = int(row["rounds"])
		var need: int = int(row["need"])
		A.append(_p_at_least(row["p"], need))
		var flat_mean: Array = []
		var flat_own: Array = []
		for r in range(rounds):
			flat_mean.append(grand)
			flat_own.append(float(row["pbar"]))
		B.append(_p_at_least(flat_mean, need))
		D.append(_p_at_least(flat_own, need))
		var three: Array = [float(row["pbar"]), float(row["pbar"]), float(row["pbar"])]
		C.append(_p_at_least(three, 2))

	print("  league        A actual  B struct-only  C field-only  D own-pbar/own-struct")
	for i in range(n):
		print("  %-12s   %4.0f%%       %4.0f%%          %4.0f%%         %4.0f%%" % [
			Career.league_at(int(meas[i]["idx"])).get("name", "?"),
			float(A[i]) * 100.0, float(B[i]) * 100.0, float(C[i]) * 100.0, float(D[i]) * 100.0])

	print("\n  metric              A actual   B struct-only   C field-only   D own-pbar")
	print("  spread (hi-lo)       %5.1f      %5.1f          %5.1f         %5.1f" % [
		_spread(A) * 100.0, _spread(B) * 100.0, _spread(C) * 100.0, _spread(D) * 100.0])
	print("  roughness (sum|d|)   %5.1f      %5.1f          %5.1f         %5.1f" % [
		_roughness(A) * 100.0, _roughness(B) * 100.0, _roughness(C) * 100.0, _roughness(D) * 100.0])
	print("  INVERSION MASS       %5.1f      %5.1f          %5.1f         %5.1f" % [
		_inversion_mass(A) * 100.0, _inversion_mass(B) * 100.0,
		_inversion_mass(C) * 100.0, _inversion_mass(D) * 100.0])
	print("  inversions (>0)      %5d      %5d          %5d         %5d" % [
		_count_inversions(A, 0.0), _count_inversions(B, 0.0),
		_count_inversions(C, 0.0), _count_inversions(D, 0.0)])
	print("  inversions (>12pt)   %5d      %5d          %5d         %5d" % [
		_count_inversions(A, 0.12), _count_inversions(B, 0.12),
		_count_inversions(C, 0.12), _count_inversions(D, 0.12)])
	print("  B is the sawtooth STRUCTURE alone could produce; C is what the FIELD alone produces.")
	print("  Whichever of B/C carries more INVERSION MASS is the term that drives the sawtooth.")


# =============================================================================
# 5. CORRELATIONS — every candidate driver against ADVANCE, and against p-bar
# =============================================================================
func _corr(xs: Array, ys: Array) -> float:
	var n: float = float(xs.size())
	var mx := 0.0
	var my := 0.0
	for i in range(xs.size()):
		mx += float(xs[i])
		my += float(ys[i])
	mx /= n
	my /= n
	var sxy := 0.0
	var sxx := 0.0
	var syy := 0.0
	for i in range(xs.size()):
		var dx: float = float(xs[i]) - mx
		var dy: float = float(ys[i]) - my
		sxy += dx * dy
		sxx += dx * dx
		syy += dy * dy
	if sxx <= 0.0 or syy <= 0.0:
		return 0.0
	return sxy / sqrt(sxx * syy)


func _correlations(meas: Array, table: Array) -> void:
	print("\n─── 5. CORRELATIONS (n=11 rungs; |r|>0.60 is p<0.05 at this n) ───")
	var adv: Array = []
	var pbar: Array = []
	var fill: Array = []
	var rounds: Array = []
	var need: Array = []
	var team: Array = []
	var cap: Array = []
	var champ: Array = []
	var idxs: Array = []
	for row in meas:
		var i: int = int(row["idx"])
		adv.append(float(row["advance"]))
		pbar.append(float(row["pbar"]))
		fill.append(float(table[i]))
		rounds.append(float(row["rounds"]))
		need.append(float(row["need"]))
		team.append(float(Career.team_size_for_league(i)))
		cap.append(Career.stat_cap_for_league(i))
		champ.append(float((row["p"] as Array)[int(row["rounds"]) - 1]))
		idxs.append(float(i))
	print("  term                    r vs ADVANCE   r vs per-round pbar")
	print("  climber fill table         %+.2f            %+.2f" % [_corr(fill, adv), _corr(fill, pbar)])
	print("  round count                %+.2f            %+.2f" % [_corr(rounds, adv), _corr(rounds, pbar)])
	print("  wins needed                %+.2f            %+.2f" % [_corr(need, adv), _corr(need, pbar)])
	print("  team size                  %+.2f            %+.2f" % [_corr(team, adv), _corr(team, pbar)])
	print("  stat cap                   %+.2f            %+.2f" % [_corr(cap, adv), _corr(cap, pbar)])
	print("  league index               %+.2f            %+.2f" % [_corr(idxs, adv), _corr(idxs, pbar)])
	print("  per-round pbar             %+.2f              —" % _corr(pbar, adv))
	print("  champion round p           %+.2f            %+.2f" % [_corr(champ, adv), _corr(champ, pbar)])
	print("  ⚠️ The pricing model PREDICTS a NEGATIVE fill<->ADVANCE correlation (a stronger expected")
	print("     climber buys a stronger field). A positive one means the fill table is not the driver.")


# =============================================================================
# 8. THE TWO SUSPECTS, TURNED OFF
# =============================================================================
func _adv_row(m: Array) -> Array:
	var out: Array = []
	for row in m:
		out.append(float(row["advance"]))
	return out


func _cf_report(base: Array, a: Array, b: Array, c: Array) -> void:
	print("\n─── 8. COUNTERFACTUALS (nothing committed — this is what each suspect is WORTH) ───")
	var r0 := _adv_row(base)
	var ra := _adv_row(a)
	var rb := _adv_row(b)
	var rc := _adv_row(c)
	print("  league        shipped   no relief   one champ kind   both")
	for i in range(r0.size()):
		print("  %-12s   %4.0f%%     %4.0f%%        %4.0f%%          %4.0f%%" % [
			Career.league_at(int(base[i]["idx"])).get("name", "?"),
			float(r0[i]) * 100.0, float(ra[i]) * 100.0, float(rb[i]) * 100.0, float(rc[i]) * 100.0])
	print("\n  metric              shipped   no relief   one champ kind   both")
	print("  spread (hi-lo)       %5.1f     %5.1f        %5.1f           %5.1f" % [
		_spread(r0) * 100.0, _spread(ra) * 100.0, _spread(rb) * 100.0, _spread(rc) * 100.0])
	print("  roughness (sum|d|)   %5.1f     %5.1f        %5.1f           %5.1f" % [
		_roughness(r0) * 100.0, _roughness(ra) * 100.0, _roughness(rb) * 100.0, _roughness(rc) * 100.0])
	print("  INVERSION MASS       %5.1f     %5.1f        %5.1f           %5.1f" % [
		_inversion_mass(r0) * 100.0, _inversion_mass(ra) * 100.0,
		_inversion_mass(rb) * 100.0, _inversion_mass(rc) * 100.0])
	print("  inversions (>0)      %5d     %5d        %5d           %5d" % [
		_count_inversions(r0, 0.0), _count_inversions(ra, 0.0),
		_count_inversions(rb, 0.0), _count_inversions(rc, 0.0)])
	print("  inversions (>12pt)   %5d     %5d        %5d           %5d" % [
		_count_inversions(r0, 0.12), _count_inversions(ra, 0.12),
		_count_inversions(rb, 0.12), _count_inversions(rc, 0.12)])
	var cups := "  cups for the climb:  "
	for row in [r0, ra, rb, rc]:
		var s := 0.0
		for x in row:
			s += 1.0 / maxf(0.01, float(x))
		cups += " %6.1f" % s
	print(cups)


# =============================================================================
# 7. ARCHETYPE PARITY AGAINST THE CLIMBER — the suspect the ladder file names but never measures
# =============================================================================
## ⚠️ `tactics.gd:FILL_MULT` equalises the six KINDS — but its own comment says it was calibrated
## "against a generic 0.65 rival build", NOT against the climbing player this ladder is priced
## for. Meanwhile `career.gd:make_cup_field` draws each qualifying round's kind from
## `archetypes_taught_by(idx)`, a pool that GROWS at Copper, Tin, Bronze, Silver and Gold and is
## frozen at six thereafter. So if the kinds are not equal against THIS opponent, the per-round
## difficulty of a rung steps every time the pool composition changes — a discontinuity nobody
## authored as a difficulty curve.
##
## This measures, per rung, the climber's win rate against each kind built at that rung's own mean
## qualifier fill. Then it predicts p-bar per rung from the pool mix alone and correlates that
## against the measured p-bar.
const KINDS := ["rushdown", "bulwark", "attrition", "focusfire", "control", "zone"]

func _archetype_parity(meas: Array) -> void:
	print("\n─── 7. ARCHETYPE PARITY vs THE CLIMBER (win rate per KIND, at the rung's qualifier fill) ───")
	var n: int = mini(seeds, 32)
	var head := "  league       qfill |"
	for k in KINDS:
		head += " %-9s" % k.substr(0, 9)
	print(head + "| spread")
	var per_rung: Array = []
	var pooled: Dictionary = {}
	for k in KINDS:
		pooled[k] = [0, 0]
	for idx in range(Career.leagues.size()):
		var rounds: int = maxi(1, Career.rival_count_for_league(idx))
		var qsum := 0.0
		for r in range(rounds - 1):
			qsum += Career.field_fill(r, rounds, idx)
		var qfill: float = qsum / float(maxi(1, rounds - 1))
		var size: int = Career.team_size_for_league(idx)
		var pf: float = Career.expected_climber_fill(idx)
		var rates: Dictionary = {}
		var line := "  %-12s %.2f |" % [Career.league_at(idx).get("name", "?"), qfill]
		for k in KINDS:
			var w := 0
			for a in range(n):
				Career.league_index = idx
				var rivals: Array = Career.make_league_rivals(size, idx, qfill, 7700 + a * 53 + idx * 11, k)
				var team: Array = _player_team(idx, pf, a * 13 + idx)
				for m in team:
					m.reset_for_battle()
				for m in rivals:
					m.reset_for_battle()
				var rng := RandomNumberGenerator.new()
				rng.seed = 82000 + idx * 271 + a
				var plan_b: Dictionary = TacticsScript.team_plan_for_gameplan(k, team)
				var orders: Dictionary = TacticsScript.orders_for_gameplan(k, rivals)
				var sim = BattleSimScript.new(team, rivals, rng.randi(), {}, plan_b, orders)
				_fights += 1
				if str(sim.run().get("winner", "")) == "A":
					w += 1
			var rate: float = float(w) / float(n)
			rates[k] = rate
			(pooled[k] as Array)[0] = int((pooled[k] as Array)[0]) + w
			(pooled[k] as Array)[1] = int((pooled[k] as Array)[1]) + n
			line += "   %4.0f%%   " % (rate * 100.0)
		var vals: Array = []
		for k in KINDS:
			vals.append(float(rates[k]))
		per_rung.append(rates)
		print(line + "| %4.0f" % (_spread(vals) * 100.0))

	var pl := "  POOLED       ---- |"
	var pv: Array = []
	for k in KINDS:
		var a2: Array = pooled[k]
		var r2: float = float(int(a2[0])) / float(maxi(1, int(a2[1])))
		pv.append(r2)
		pl += "   %4.0f%%   " % (r2 * 100.0)
	print(pl + "| %4.0f" % (_spread(pv) * 100.0))
	print("  ⚠️ If this spread is large, `FILL_MULT` does NOT equalise the kinds against the CLIMBER,")
	print("     and every rung where the drawn pool changes gets a difficulty step nobody authored.")

	# Predict per-rung qualifier difficulty from the POOL MIX alone, and correlate with reality.
	print("\n  pool mix -> predicted qualifier win rate vs the MEASURED one")
	print("  league       poolsize  predicted  measured(qual)  diff")
	var pred: Array = []
	var obs: Array = []
	for idx in range(meas.size()):
		var learned: Array = Career.archetypes_taught_by(idx)
		var s := 0.0
		for g in learned:
			s += float((per_rung[idx] as Dictionary).get(String(g), 0.0))
		var p: float = s / float(maxi(1, learned.size()))
		var row: Dictionary = meas[idx]
		var rounds: int = int(row["rounds"])
		var qs := 0.0
		for r in range(rounds - 1):
			qs += float((row["p"] as Array)[r])
		var o: float = qs / float(maxi(1, rounds - 1))
		pred.append(p)
		obs.append(o)
		print("  %-12s   %d       %4.0f%%        %4.0f%%        %+4.0f" % [
			Career.league_at(idx).get("name", "?"), learned.size(),
			p * 100.0, o * 100.0, (p - o) * 100.0])
	print("  r(predicted-from-pool, measured qualifier win rate) = %+.2f" % _corr(pred, obs))


# =============================================================================
# 6. THE SMOOTH-TABLE COUNTERFACTUAL — should difficulty track a MEASURED table at all?
# =============================================================================
## A monotone least-squares-ish fit through the measured points: the same endpoints, forced
## non-increasing (the real table's own trend), with the Bronze bump removed. Deliberately the
## SIMPLEST honest smoothing, so any difference is attributable to the bumps rather than to a
## cleverer curve.
func _smooth_table(real: Array) -> Array:
	var n: int = real.size()
	var lo: float = float(real[n - 1])
	var hi: float = float(real[0])
	# mean of the measured points, so the smooth curve carries the same average player strength
	var mean := 0.0
	for x in real:
		mean += float(x)
	mean /= float(n)
	var out: Array = []
	for i in range(n):
		var t: float = float(i) / float(maxi(1, n - 1))
		out.append(lerpf(hi, lo, t))
	# re-centre so the counterfactual is not secretly a global buff/nerf
	var m2 := 0.0
	for x in out:
		m2 += float(x)
	m2 /= float(n)
	for i in range(n):
		out[i] = clampf(float(out[i]) + (mean - m2), 0.05, 1.0)
	return out


func _compare_rows(a: Array, b: Array, ta: Array, tb: Array) -> void:
	print("\n─── 6. MEASURED TABLE vs SMOOTH AUTHORED TABLE ───")
	print("  ⚠️ THE SMOOTH TABLE IS NOT COMMITTED. This measures whether a designed curve, validated")
	print("     by measurement, produces a better ladder than a curve that IS the measurement.")
	print("  league        fill(meas) fill(smooth) | ADVANCE meas  ADVANCE smooth   d")
	var ra: Array = []
	var rb: Array = []
	for i in range(a.size()):
		var x: float = float(a[i]["advance"])
		var y: float = float(b[i]["advance"])
		ra.append(x)
		rb.append(y)
		print("  %-12s   %.2f       %.2f      |    %4.0f%%        %4.0f%%       %+4.0f" % [
			Career.league_at(int(a[i]["idx"])).get("name", "?"),
			float(ta[i]), float(tb[i]), x * 100.0, y * 100.0, (y - x) * 100.0])
	print("\n  metric              measured table   smooth table")
	print("  spread (hi-lo)        %5.1f            %5.1f" % [_spread(ra) * 100.0, _spread(rb) * 100.0])
	print("  roughness (sum|d|)    %5.1f            %5.1f" % [_roughness(ra) * 100.0, _roughness(rb) * 100.0])
	print("  INVERSION MASS        %5.1f            %5.1f" % [
		_inversion_mass(ra) * 100.0, _inversion_mass(rb) * 100.0])
	print("  inversions (>0)       %5d            %5d" % [
		_count_inversions(ra, 0.0), _count_inversions(rb, 0.0)])
	print("  inversions (>12pt)    %5d            %5d" % [
		_count_inversions(ra, 0.12), _count_inversions(rb, 0.12)])
	var ca := "  cups per rung meas:   "
	var cb := "  cups per rung smooth: "
	var ta_sum := 0.0
	var tb_sum := 0.0
	for i in range(ra.size()):
		ta_sum += 1.0 / maxf(0.01, float(ra[i]))
		tb_sum += 1.0 / maxf(0.01, float(rb[i]))
		ca += "%.1f " % (1.0 / maxf(0.01, float(ra[i])))
		cb += "%.1f " % (1.0 / maxf(0.01, float(rb[i])))
	print(ca + " = %.1f" % ta_sum)
	print(cb + " = %.1f" % tb_sum)
