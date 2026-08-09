## THE GOLD WALL — WHY does the career autopilot stop at Gold?
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_gold_wall.tscn
##      …          --headless --path . res://scenes/_probe_gold_wall.tscn -- --quick
##
## ⚠️ THIS FILE DOES NOT CONTAIN A SECOND COPY OF THE AUTOPILOT, AND THAT IS THE WHOLE DESIGN.
## `_probe_career_arc.gd` already IS the autopilot; a rival copy would drift from it inside one
## round, which is this project's single most expensive recurring failure. So every variant here
## SUBCLASSES that script (a Node whose `_ready()` never runs because it is never added to the
## tree) and overrides only the seam it needs. What cannot be reached by an override — the cap
## table, the team-size table, the travel charge — is perturbed by mutating the autoload the arc
## reads, and RESTORED afterwards.
##
## ⚠️ EVERY PERTURBATION CARRIES A LIVENESS CANARY. Round 10's slope probe reported 100% ADVANCE
## at ten of eleven rungs because it silently carried a second copy of the climber model. So each
## mutation below asserts, against the live objects, that the thing it claims to have changed HAS
## changed and then changed back; a failed canary sets `_ok = false` and this probe exits 1.
##
## THE QUESTION: the arc reaches Gold (week 332) and stalls for 150 weeks, entering 36 Gold cups,
## winning 3 of 144 rounds — 2%. Five candidate causes, one paired experiment each:
##   H1 team-size step at SILVER (3->4) dilutes the roster        -> flat team sizes
##   H2 cap step at GOLD (+150 not +100) outruns a linear budget  -> flat +100 caps
##   H3 26% of career weeks are travel, so 29 weeks/rung is fiction -> travel charged 0 weeks
##   H4 insolvency — 33% of purse income goes on entry fees        -> free entry/recruits/barn
##   H5 something none of us named                                -> see sections 2 and 4
extends Node

const ArcScript = preload("res://scripts/_probe_career_arc.gd")
const CupRunScript = preload("res://scripts/cup_run.gd")
const BattleSimScript = preload("res://scripts/battle_sim.gd")
const TacticsScript = preload("res://scripts/tactics.gd")

const ARC_WEEKS := 900        ## > the control's 483; also suppresses the arc's own per-clear prints
const SEEDS := [20260809, 771013, 313373, 4242424, 99180]
const GOLD := 6               ## the rung the arc stalls on

var _ok := true
var _notes: Array[String] = []
var _tree: SceneTree

# ── snapshots for restore ────────────────────────────────────────────────────
var _caps_orig: Array = []
var _team_orig: Dictionary = {}


# =============================================================================
# THE VARIANT — one subclass, every knob the arc's own `opts` cannot reach
# =============================================================================
## ⚠️ THIS SUBCLASS IS NOW A THIN ADAPTER, AND THAT IS THE FIX, NOT A REGRESSION. Every knob
## below used to be IMPLEMENTED here — a second copy of the training brain, of the successor
## loop and of the free-body overrides, living in a different file from the autopilot it was
## a variant of. `_probe_career_arc.gd` now owns all of them as first-class POLICIES
## (`POLICIES` / `apply_policy`), because they are the definition of the reference player the
## whole difficulty curve is priced against, and a player model with two implementations has
## two definitions. The `v_*` names and `succession_buys` are KEPT because
## `_probe_ladder_slope.gd` (not this workstream's file) sets and reads them.
class ArcVariant extends ArcScript:
	var v_seed: int = 20260809
	var v_redraft_kits: bool = false     ## re-draft the moveset every week (see section 2)
	var v_immortal: bool = false         ## lifespan -> 1000y: nothing ever retires
	var v_free_bodies: bool = false      ## recruits, barn slots and breeding cost nothing
	## ⚠️ THE POLICY TEST. The parent's bench was once UNREACHABLE BY CONSTRUCTION: it bought a
	## spare only when `Career.barn_capacity > team_need`, and the same loop only ever grew the
	## barn UP TO `team_need`. Measured: `benchWeeks = 0` over a 483-week career. So "the stable
	## never had a trained successor" was a property of the autopilot, not of the game — and the
	## question "is the wall the POLICY rather than the GAME" cannot be answered without this row.
	var v_succession: bool = false
	var v_succession_lead: int = 150     ## kept for callers; the parent's SUCCESSION_LEAD is 150
	var succession_buys: int = 0
	## Train the stats the monster is GOOD at instead of the one it is worst at. The parent's
	## naive policy ("biggest drill on the lowest stat") maximises POINTS and is measured at
	## 14.45/wk against the optimiser's 12.01 — but it builds a perfectly flat generalist, and
	## every rival is shaped onto an archetype axis. This row asks what the flatness costs.
	var v_shaped_training: bool = false

	## The one seam: copy this variant's knobs onto the parent's policy vars, then run the ONE
	## autopilot. Nothing here re-implements a policy.
	func _run_arc(max_weeks: int, opts: Dictionary = {}) -> Dictionary:
		p_seed = v_seed
		p_redraft_kits = v_redraft_kits
		p_immortal = v_immortal
		p_free_bodies = v_free_bodies
		p_succession = v_succession
		p_shaped_training = v_shaped_training
		var out: Dictionary = super(max_weeks, opts)
		succession_buys = p_succession_buys
		return out


## Travel is charged inline in `_run_arc` off `CupRun.weeks_for_cup`, which no override can reach.
## Replacing the autoload's script is the only seam; `weeks_for_cup` is a pure function of two
## consts, so nothing else in the arc can notice.
class NoTravelCupRun extends CupRunScript:
	func weeks_for_cup(_idx: int, _rounds: int = -1) -> int:
		return 0


func _ready() -> void:
	_tree = get_tree()
	print("=== GOLD WALL PROBE ===")
	print("why does the career autopilot stop at Gold? %d seeds, %d-week arcs.\n" % [SEEDS.size(), ARC_WEEKS])
	_caps_orig = _read_caps()
	_team_orig = Career.team_size_by_league.duplicate(true)
	print("  caps       %s" % str(_caps_orig))
	print("  team sizes %s" % str(_team_sizes()))

	var quick: bool = _has_arg("--quick")

	_section_1_shape()
	_section_2_kits()
	if not quick:
		_section_3_matrix()
	_section_4_demography()

	print("\n=== instrument notes ===")
	if _notes.is_empty():
		print("  (none)")
	for n in _notes:
		print("  · %s" % n)
	print("\n=== gold wall probe: %s ===" % ("OK" if _ok else "INSTRUMENT BROKEN"))
	_tree.quit(0 if _ok else 1)


func _has_arg(a: String) -> bool:
	return a in OS.get_cmdline_user_args() or a in OS.get_cmdline_args()


func _read_caps() -> Array:
	var out: Array = []
	for i in range(Career.leagues.size()):
		out.append(int(Career.stat_cap_for_league(i)))
	return out


func _team_sizes() -> Array:
	var out: Array = []
	for i in range(Career.leagues.size()):
		out.append(Career.team_size_for_league(i))
	return out


func _lname(i: int) -> String:
	return str(Career.league_at(i).get("name", "?"))


# =============================================================================
# 1. THE SHAPE OF THE PROBLEM — what the arc's own numbers already say
# =============================================================================
## ⚠️ THE ONE ARITHMETIC THAT DECIDES H2 BEFORE ANY ARC IS RUN. `fill` is a QUOTIENT, so a fill
## that falls when the cap steps proves nothing on its own. Multiply it back out: if the roster's
## ABSOLUTE mean stat is still rising at Gold, the wall is a denominator and H2 is live; if the
## absolute stat FALLS, stat capital is being destroyed and no cap schedule can explain it.
func _section_1_shape() -> void:
	print("\n─── 1. THE SHAPE — one control arc, fill converted back to absolute stats ───")
	var a: Dictionary = _arc({})
	_print_arc_table(a)


func _print_arc_table(a: Dictionary) -> void:
	var rows: Array = a["perLeague"]
	print("  league        wks  cups  rounds  won   win%%   fill@exit   cap   ABS pts/stat  recruits  retired")
	var prev_abs := 0.0
	for i in range(rows.size()):
		var r: Dictionary = rows[i]
		if int(r["weeks"]) == 0 and int(r["cups"]) == 0:
			continue
		var cap: float = Career.stat_cap_for_league(i)
		var abs_pts: float = float(r["fillAtExit"]) * cap
		var arrow := ""
		if prev_abs > 0.0:
			arrow = "  %+.0f" % (abs_pts - prev_abs)
		prev_abs = abs_pts
		print("  %-12s %4d  %4d  %6d  %3d  %4.0f%%   %6.0f%%  %5d   %8.0f%s   %5d  %5d" % [
			_lname(i), int(r["weeks"]), int(r["cups"]), int(r["rounds"]), int(r["roundWins"]),
			100.0 * float(r["roundWins"]) / maxf(1.0, float(r["rounds"])),
			float(r["fillAtExit"]) * 100.0, int(cap), abs_pts, arrow,
			int(r["recruits"]), int(r["retirements"])])
	print("  -> stopped at %s after %d weeks · %d recruited · %d retired · %d travel weeks" % [
		_lname(int(a["finalLeague"])), int(a["weeks"]), int(a["recruits"]),
		int(a["retirements"]), int(a.get("travelWeeks", 0))])
	print("  -> bench: %d monster-weeks outside the fielded team" % int(a.get("benchWeeks", 0)))


# =============================================================================
# 2. THE KIT — the same team, the same stats, the same field, one thing changed
# =============================================================================
## ⚠️ `week.gd:apply_activity` CALLS `recompute_class()` AND `recompute_pools()` EVERY WEEK AND
## NEVER CALLS `assign_moveset()`. A monster's kit is drawn once, at the moment it is created,
## from `monster_instance.gd:assign_moveset` — which gates every move on `learnLevel` against the
## CURRENT value of the stat it is authored on. So a body recruited at ~23-80 per stat drafts the
## floor of every line and KEEPS IT for the rest of its career, however much it trains. Every
## rival it ever meets is GENERATED at its fill and therefore drafts to its stats.
##
## This section holds absolutely everything else fixed — same monsters, same stats, same drawn
## field, same battle seeds — and re-drafts only the player's kit. Any gap is the size of that.
func _section_2_kits() -> void:
	print("\n─── 2. THE KIT (does a trained monster still fight with a rookie's moveset?) ───")
	var v := ArcVariant.new()
	v.v_seed = SEEDS[0]
	var a: Dictionary = v._run_arc(ARC_WEEKS, {})
	var idx: int = Career.league_index
	var team: Array = Roster.monsters.filter(func(m): return not m.retired)
	if team.is_empty():
		_notes.append("section 2: the stalled roster was empty — nothing to measure")
		v.free()
		return

	# ── what the arc's own bodies are carrying ──
	print("  the stalled roster at %s (week %d):" % [_lname(idx), int(a["weeks"])])
	print("    slot  species            age/span   mean stat  moves  mean learnLvl  top learnLvl")
	for mi in team:
		var st := _mean_stat(mi)
		var ll := _kit_learn(mi)
		print("    %-4s  %-18s %4d/%-4d  %9.0f  %5d  %13.0f  %12.0f" % [
			str(mi.id).substr(0, 4), str(mi.species_id).substr(0, 18),
			int(mi.age_weeks), int(round(mi.lifespan_years * 48.0)),
			st, int(mi.moveset.size()), ll["mean"], ll["top"]])

	# ── the same bodies, re-drafted ──
	var before: Array = []
	for mi in team:
		before.append({"moves": mi.moveset.duplicate(true), "ll": _kit_learn(mi)})

	## ⚠️ 24 ROUNDS DECIDES NOTHING — a proportion at n=24 carries about ±10 points, and this
	## project's oldest lesson is that a difference inside its own error band is not a difference.
	## 20 repetitions of the whole drawn field is the smallest sample that can separate "the kit
	## matters a little" from "the kit matters not at all".
	const KIT_REPS := 20
	var wins_stale: int = _fight_field(idx, team, KIT_REPS)
	for mi in team:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(mi.id)
		mi.assign_moveset(rng)
	var wins_fresh: int = _fight_field(idx, team, KIT_REPS)
	var rounds: int = Career.rival_count_for_league(idx) * KIT_REPS

	var ll_before := 0.0
	var ll_after := 0.0
	for i in range(team.size()):
		ll_before += float(before[i]["ll"]["mean"])
		ll_after += float(_kit_learn(team[i])["mean"])
	ll_before /= maxf(1.0, float(team.size()))
	ll_after /= maxf(1.0, float(team.size()))

	## ── C. THE SHAPE, at an IDENTICAL stat total ────────────────────────────────────────────
	## ⚠️ THE AUTOPILOT'S TRAINING POLICY IS "PUT THE BIGGEST DRILL ON THE LOWEST STAT", WHICH IS
	## A POLICY FOR MAXIMISING POINTS AND THEREFORE BUILDS A PERFECTLY FLAT GENERALIST. Every
	## rival it meets is `roster.gd:_shape_to_class`d onto an archetype's axis. `_shape_to_class`
	## is SUM-PRESERVING by construction, so running the player's own bodies through the FIELD'S
	## OWN SHAPER changes nothing except how the same points are spent. Any gap here is the price
	## of shape, measured in the one currency the ladder's difficulty model cannot see: the model
	## (`career.gd:expected_climber_fill`) is a stat TOTAL over a cap.
	var shape_classes: Array = TacticsScript.archetype_classes(
		TacticsScript.archetype_for_league(idx), team.size())
	var totals_before: Array = []
	for mi in team:
		totals_before.append(_mean_stat(mi) * float(Classify.STATS.size()))
	for i in range(team.size()):
		var srng := RandomNumberGenerator.new()
		srng.seed = 4400 + i
		Roster._shape_to_class(team[i], str(shape_classes[i % maxi(1, shape_classes.size())]), srng)
	var drift := 0.0
	for i in range(team.size()):
		drift += absf(_mean_stat(team[i]) * float(Classify.STATS.size()) - float(totals_before[i]))
	var wins_shaped: int = _fight_field(idx, team, KIT_REPS)

	print("  identical stats, identical field, identical fight seeds — only the KIT re-drafted:")
	print("    A kit as trained (never re-drafted):  %2d / %d rounds  (%3.0f%%)  mean learnLevel %.0f" % [
		wins_stale, rounds, 100.0 * wins_stale / maxf(1.0, float(rounds)), ll_before])
	print("    B kit re-drafted to current stats:    %2d / %d rounds  (%3.0f%%)  mean learnLevel %.0f" % [
		wins_fresh, rounds, 100.0 * wins_fresh / maxf(1.0, float(rounds)), ll_after])
	print("    C same POINTS, re-SHAPED onto %-12s %2d / %d rounds  (%3.0f%%)  (total drifted %.1f pts)" % [
		str(TacticsScript.archetype_for_league(idx)) + ":",
		wins_shaped, rounds, 100.0 * wins_shaped / maxf(1.0, float(rounds)), drift])
	print("    (C is the FIELD'S OWN shaper, sum-preserving. A>B measures the stale kit; B>C the shape.)")
	if drift > 2.0 * float(team.size()):
		_notes.append("row C's re-shape moved the stat total by %.1f points — the ceiling clamp bit, "
			% drift + "so C is not perfectly sum-preserving here. Read it as approximate.")
	## ⚠️ THE CANARY. If re-drafting did not change a single move, this section measured nothing
	## and its null is an instrument fault, not a finding.
	var moved := false
	for i in range(team.size()):
		if str(before[i]["moves"]) != str(team[i].moveset):
			moved = true
			break
	if not moved:
		_ok = false
		_notes.append("⚠️ section 2 canary FAILED — re-drafting changed no move on any body, so the "
			+ "A/B compared a team with itself. The number above is void.")
	else:
		print("    (canary: the re-draft changed the moveset on at least one body ✓)")
	v.free()


func _mean_stat(mi) -> float:
	var t := 0.0
	for s in Classify.STATS:
		t += float(mi.stats.get(s, 0.0))
	return t / float(Classify.STATS.size())


## Mean and top `learnLevel` of the moves a monster is actually carrying — the readable proxy for
## "how grown-up is this kit".
func _kit_learn(mi) -> Dictionary:
	var acc := 0.0
	var top := 0.0
	var n := 0
	for mv in mi.moveset:
		var lv: float = float(mv.get("learnLevel", 0.0)) if mv is Dictionary else 0.0
		acc += lv
		top = maxf(top, lv)
		n += 1
	return {"mean": acc / maxf(1.0, float(n)), "top": top, "n": n}


## Fight this league's real drawn field `reps` times, with the archetype plans the live path uses.
## Deterministic in the seeds, so two calls with the same team are exactly comparable.
func _fight_field(idx: int, team: Array, reps: int) -> int:
	var wins := 0
	var keep_week: int = Career.week
	for f in range(reps):
		Career.week = keep_week + f * 4
		var field: Array = Career.make_cup_field(idx, Career.rival_count_for_league(idx))
		for r in range(field.size()):
			var rng := RandomNumberGenerator.new()
			rng.seed = 610000 + idx * 977 + f * 41 + r
			var rivals: Array = field[r]["team"]
			var gid: String = String(field[r].get("archetype", ""))
			for m in team:
				m.reset_for_battle()
			for m in rivals:
				m.reset_for_battle()
			var plan_b: Dictionary = TacticsScript.team_plan_for_gameplan(gid, team) if gid != "" else {}
			var orders: Dictionary = TacticsScript.orders_for_gameplan(gid, rivals) if gid != "" else {}
			var sim = BattleSimScript.new(team, rivals, rng.randi(), {}, plan_b, orders)
			if str(sim.run().get("winner", "")) == "A":
				wins += 1
	Career.week = keep_week
	return wins


# =============================================================================
# 3. THE MATRIX — neutralise ONE mechanism at a time, over several seeds
# =============================================================================
## ⚠️ THE ARC IS NOISY: round 10 recorded the same seed stalling at Silver/Gold/Platinum/Masters
## and 324-598 weeks across five runs while the ladder was being retuned underneath it. One arc
## decides nothing. Every row below is `SEEDS.size()` independent careers and reports the SPREAD.
func _section_3_matrix() -> void:
	print("\n─── 3. THE MATRIX (neutralise one mechanism at a time) ───")
	print("  each row: %d seeds, %d-week arcs. 'reached' is the highest league index touched." % [
		SEEDS.size(), ARC_WEEKS])
	## ⚠️ "reached" IS THE PRIMARY METRIC AND THE SPREAD IS THE POINT. The control does NOT reliably
	## stall at Gold: over five seeds it stops at Iron, Silver, Gold and Platinum. A row is only a
	## finding if its whole distribution moves, not if its best seed does.
	## ⚠️ "reached" IS NOT "WON". `Career` has a real terminal condition — `won_game`, set when the
	## draw at Tamers Apex is SWEPT (`career.gd:849`; at the final league the rank IS the title).
	## Touching index 10 only means the player was promoted INTO Apex. Reporting `reached` alone
	## would let a row that arrives at the summit and never clears it read as a completed game,
	## which is the exact shape of claim this project keeps having to retract.
	print("  %-24s  %-22s  %-6s  %-11s  %-5s  %s" % [
		"neutralised", "reached (per seed)", "median", "median wks", "WON", "round win% at the stall"])

	## ⚠️ THE FOUR ROWS BELOW ARE THE SECOND PASS. The first pass ran all eight and settled four of
	## them, and re-running a settled row costs ~8 arcs for a number already in the log:
	##   H1 team-size step  [6,4,6,4,6] vs control [6,4,7,4,5] — inside the spread, NOT the cause
	##   H2 cap step        [6,4,7,4,5] — byte-identical to control. Dead. The Gold cap jump is not it
	##   H3 travel          [5,5,7,5,5] — no better than control
	##   H5a stale kits     [5,5,5,5,5] — no better than control (and see section 2 row B)
	##   H4 money           [6,6,6,6,6] — tightens the spread onto Gold, never breaks past it
	## Restore any of them by putting the row back; the machinery is unchanged.
	var rows: Array = [
		{"name": "— (control)", "kind": "control"},
		{"name": "H5b lifespan (immortal)", "kind": "immortal"},
		{"name": "POLICY: succession(+money)", "kind": "succession"},
		{"name": "POLICY: shaped training", "kind": "shapedtrain"},
		{"name": "POLICY: everything at once", "kind": "policy_all"},
	]
	for row in rows:
		var res: Dictionary = _run_variant(str(row["kind"]))
		print("  %-24s  %-22s  %-6d  %-11d  %-5s  %s" % [
			str(row["name"]), str(res["reached"]), int(res["medianReached"]),
			int(res["medianWeeks"]), "%d/%d" % [int(res["won"]), SEEDS.size()], str(res["stallWin"])])
	print("  (Gold = index %d, Platinum 7, Apex 10. A row is a finding only if its whole" % GOLD)
	print("   distribution moves — one good seed is inside this instrument's own noise.)")


func _run_variant(kind: String) -> Dictionary:
	_apply_env(kind)
	var reached: Array = []
	var weeks: Array = []
	var gwins := 0
	var grounds := 0
	var games_won := 0
	for s in SEEDS:
		var opts: Dictionary = {}
		if kind in ["rich", "succession", "policy_all"]:
			opts["feeMult"] = 0.0
		var v := ArcVariant.new()
		v.v_seed = int(s)
		v.v_redraft_kits = kind in ["redraft", "policy_all"]
		v.v_immortal = kind == "immortal"
		## ⚠️ SUCCESSION IMPLIES FREE BODIES, AND THAT IS NOT A CHEAT — IT IS THE FIRST PASS'S
		## FINDING MADE INTO A CONTROL. Run at real prices the policy fired ZERO times on all five
		## seeds and the canary voided the row: a fifth barn slot costs 2600g (`shop_ui.gd:
		## BARN_PRICES`) and the control career PEAKS at 1465g, so a stable physically cannot house
		## a successor at Gold. To ask "would a successor fix the wall" at all, the barn has to be
		## affordable — so this row answers the design question and the price is reported as its
		## own finding rather than silently swallowed.
		v.v_free_bodies = kind in ["rich", "succession", "policy_all"]
		v.v_succession = kind in ["succession", "policy_all"]
		v.v_shaped_training = kind in ["shapedtrain", "policy_all"]
		var a: Dictionary = v._run_arc(ARC_WEEKS, opts)
		var buys: int = v.succession_buys
		var bench: int = int(a.get("benchWeeks", 0))
		var was_succession: bool = v.v_succession
		v.free()
		## ⚠️ THE CANARY WAS RIGHT AND IS NOW A FALSE ALARM, WHICH IS ITSELF THE FINDING. It fired
		## when a fifth barn slot cost 2600g against a career peak of 1465g. With `shop_ui.gd:
		## BARN_PRICES` repriced, the BASE autopilot now keeps a bench of its own, so
		## `_grow_successor` correctly returns early ("a spare already exists") and buys nothing.
		## Voiding the row on that would report an instrument fault where the game got better. So
		## the row is void only if the policy bought nothing AND no spare was ever held.
		if was_succession and buys == 0 and bench == 0:
			_fail("succession canary: the policy never bought a successor on seed %d and the "
				% int(s) + "stable never held a spare either — the row measures nothing")
		reached.append(int(a["finalLeague"]))
		weeks.append(int(a["weeks"]))
		if bool(a.get("won", false)):
			games_won += 1
		## ⚠️ AT THE LEAGUE THIS SEED ACTUALLY STALLED ON, not at a fixed rung. A column keyed to
		## Gold reads "0/0" for every row that never got there, which is the row saying nothing at
		## the exact moment it is most interesting.
		var g: Dictionary = a["perLeague"][int(a["finalLeague"])]
		gwins += int(g["roundWins"])
		grounds += int(g["rounds"])
	_restore_env(kind)
	weeks.sort()
	var sorted_reached: Array = reached.duplicate()
	sorted_reached.sort()
	return {
		"reached": str(reached),
		"medianReached": int(sorted_reached[sorted_reached.size() / 2]),
		"medianWeeks": int(weeks[weeks.size() / 2]),
		"won": games_won,
		"stallWin": "%d/%d (%.0f%%)" % [gwins, grounds, 100.0 * gwins / maxf(1.0, float(grounds))],
	}


## Mutate the autoloads the arc reads. ⚠️ Every branch asserts it actually changed something.
func _apply_env(kind: String) -> void:
	match kind:
		"flatcaps":
			# 100 -> 1100 in eleven equal steps of +100: same floor, same ceiling, no Gold jump.
			var step: float = float(_caps_orig[_caps_orig.size() - 1] - _caps_orig[0]) \
				/ float(maxi(1, _caps_orig.size() - 1))
			for i in range(Career.leagues.size()):
				Career.leagues[i]["cap"] = float(_caps_orig[0]) + step * float(i)
			if is_equal_approx(Career.stat_cap_for_league(GOLD), float(_caps_orig[GOLD])):
				_fail("flatcaps canary: the Gold cap did not move (%d)" % _caps_orig[GOLD])
			else:
				print("    [canary] caps now %s" % str(_read_caps()))
		"flatteam":
			# No team growth above Bronze/Iron's three: the Silver 3->4 and Platinum 4->5 steps go.
			for i in range(Career.leagues.size()):
				Career.team_size_by_league[_lname(i)] = mini(int(_team_orig.get(_lname(i), 1)), 3)
			if Career.team_size_for_league(5) != 3:
				_fail("flatteam canary: Silver still fields %d" % Career.team_size_for_league(5))
			else:
				print("    [canary] team sizes now %s" % str(_team_sizes()))
		"notravel":
			var was: int = CupRun.weeks_for_cup(GOLD, 4)
			CupRun.set_script(NoTravelCupRun)
			var now: int = CupRun.weeks_for_cup(GOLD, 4)
			if not (was > 0 and now == 0):
				_fail("notravel canary: weeks_for_cup went %d -> %d" % [was, now])
			else:
				print("    [canary] cup travel %d weeks -> %d weeks" % [was, now])
		"rich":
			print("    [canary] entry fee x0, recruit price 0, barn prices 0")
		_:
			pass   # redraft / immortal / succession / control need no environment mutation


func _restore_env(kind: String) -> void:
	match kind:
		"flatcaps":
			for i in range(Career.leagues.size()):
				Career.leagues[i]["cap"] = float(_caps_orig[i])
			if int(Career.stat_cap_for_league(GOLD)) != int(_caps_orig[GOLD]):
				_fail("flatcaps restore FAILED — every later row is contaminated")
		"flatteam":
			Career.team_size_by_league = _team_orig.duplicate(true)
			if Career.team_size_for_league(5) != int(_team_orig.get(_lname(5), 0)):
				_fail("flatteam restore FAILED — every later row is contaminated")
		"notravel":
			CupRun.set_script(CupRunScript)
			if CupRun.weeks_for_cup(GOLD, 4) <= 0:
				_fail("notravel restore FAILED — every later row is contaminated")


func _fail(msg: String) -> void:
	_ok = false
	_notes.append("⚠️ " + msg)
	print("    *** %s ***" % msg)


# =============================================================================
# 4. DEMOGRAPHY — is the climb longer than a monster's career?
# =============================================================================
## Section 4 of the arc probe already says a Gold ceiling takes 305 weeks of PERFECT training to
## fill and a monster's career is 336 weeks. This asks the follow-on the arc cannot: given the
## calendar the autopilot actually spends, when does each body arrive, and when does it die?
func _section_4_demography() -> void:
	print("\n─── 4. DEMOGRAPHY (is the climb longer than a career?) ───")
	var span: int = 8 * 48
	print("  a monster is bought as a Teen (48w) and retires at 8 game-years = %dw, so a career is" % span)
	print("  %d trainable weeks. The control arc reaches Gold at week ~332." % (span - 48))
	var v := ArcVariant.new()
	v.v_seed = SEEDS[0]
	var a: Dictionary = v._run_arc(ARC_WEEKS, {})
	print("  at the stall (week %d, %s):" % [int(a["weeks"]), _lname(Career.league_index)])
	print("    slot  age  weeks left  mean stat  fill of cap  status")
	var cap: float = Career.current_stat_cap()
	for mi in Roster.monsters:
		var left: int = int(round(mi.lifespan_years * 48.0)) - int(mi.age_weeks)
		print("    %-4s %4d  %10d  %9.0f  %10.0f%%  %s" % [
			str(mi.id).substr(0, 4), int(mi.age_weeks), left, _mean_stat(mi),
			100.0 * _mean_stat(mi) / maxf(1.0, cap), "RETIRED" if mi.retired else "active"])
	print("  frozen: %d · best potential x%.2f · breeds %d" % [
		Roster.frozen.size(), float(a["bestPotential"]), int(a["breeds"])])
	## The training the calendar actually bought, against the ~12.97/monster-week ceiling.
	var mweeks: int = int(a["trainWeeks"]) + int(a["restWeeks"]) + int(a["excursionWeeks"])
	print("  monster-weeks: %d trained / %d rested / %d excursion = %.0f%% of the calendar spent training" % [
		int(a["trainWeeks"]), int(a["restWeeks"]), int(a["excursionWeeks"]),
		100.0 * float(a["trainWeeks"]) / maxf(1.0, float(mweeks))])
	print("  …and %d of %d CALENDAR weeks were travel, on which nobody trains at all." % [
		int(a.get("travelWeeks", 0)), int(a["weeks"])])
	v.free()


func _arc(opts: Dictionary) -> Dictionary:
	var v := ArcVariant.new()
	v.v_seed = SEEDS[0]
	var a: Dictionary = v._run_arc(ARC_WEEKS, opts)
	v.free()
	return a
