## THE LADDER SLOPE INSTRUMENT — is each rung harder than the one below it, FOR A PLAYER WHO HAS
## CLIMBED TO IT?
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_ladder_slope.tscn
##      (add `-- --quick` for a coarse pass while tuning; `-- --liveness` for the canary alone)
##
## ⚠️ RUNS AS A SCENE, NEVER `--script` — it needs the Career/Roster/GameData autoloads.
##
## ── WHY A SECOND LADDER INSTRUMENT EXISTS ────────────────────────────────────────────────────
## `_probe_career_arc.gd` §3b already measures the cup field, but it measures it against a team
## pinned at ONE fill (`GATE_REAL_FILL = 0.65`) at every rung. That answers "is this league hard
## for a 65% team", which is the wrong question: the player is not a 65% team at every rung, they
## are a GROWING team, and a ladder is a climb only if the field outgrows them. Measuring eleven
## leagues against a fixed roster measures the FIELD, not the CLIMB. That is precisely how the
## previous round's reading came out flat (Wood 63% · Tin 25 · Bronze 63 · Silver 63 · Gold 50,
## no trend) and was read as "the ladder is not sloped" when it did not yet contain a model of the
## player at all.
##
## ── THE PLAYER MODEL, AND WHY THIS ONE ───────────────────────────────────────────────────────
## The brief's trap: a FIXED roster measures the field; a PERFECTLY SCALED roster (always at the
## same fraction of the current cap) measures nothing, because rival fill is also a fraction of
## the same cap — the two cancel and every rung reads identical by construction. So the player
## model must be ABSOLUTE (points), not relative (fill), and the fill must fall out of it.
##
## ⚠️ AND IT IS NO LONGER DERIVED AT ALL — IT IS MEASURED. The model used to be an arithmetic
## sketch (`base + 12.97 * (29 * L + warmup) / 6` per stat, divided by the cap). Both of its
## inputs are now known to be fiction on this build: the arc spends 60-70 weeks per rung, not 29,
## and banks ~7.3 effective points per monster-CALENDAR-week, not 12.97, once rest, excursion and
## the 26% of the calendar spent travelling are counted. `career.gd:expected_climber_fill()` is
## therefore a lookup into `CLIMBER_FILL_BY_LEAGUE`, a table of the autopilot's own `fill@exit` per
## rung — and SECTION 5 OF THIS FILE (`-- --arc-table`) is what produces it. Measure it, paste it,
## never reason it. The row is printed on every run, because a difficulty number quoted without its
## player model is meaningless.
##
## ── THE TWO NUMBERS THIS PRINTS ──────────────────────────────────────────────────────────────
##   1. THE CLIMB     — at the modelled fill for THAT rung: opener/champion/round win rates, the
##                      TITLE (sweep) rate, and ADVANCE, which is the real promotion rule. A
##                      sloped ladder shows ADVANCE falling as the rungs go up.
##   2. THE THRESHOLD — the lowest player fill that advances from half its cups (t*), and the
##                      HEADROOM `climbing_fill - t*`. Headroom is the honest difficulty measure:
##                      cap-free and nearly player-model-free. A climb SHRINKS it up the ladder;
##                      slightly negative at the top simply means that rung costs several cups.
##   3. THE RESPONSE  — (`-- --response`) the fill -> win-rate transfer function the field's
##                      constants are authored against, per rung. Never guess those constants.
##   4. WHICH PLAYER  — the same fill built two ways. The disagreement between this probe and the
##                      arc probe is ENTIRELY the player model, and it must stay visible.
##   5. THE ARC TABLE — (`-- --arc-table`) runs the AUTOPILOT and measures the climber itself,
##                      per rung, with sample counts. This is what authors `career.gd`'s
##                      `CLIMBER_FILL_BY_LEAGUE`. Takes about a minute for ten careers.
##
## `-- --seeds N` raises the CLIMB sample from its default 32. A proportion at n=32 carries ±9
## points and this file's verdict counts INVERSIONS, so it can manufacture one; raise N first.
##
## ── ⚠️ BEWARE THE INSTRUMENT (rule 9) ────────────────────────────────────────────────────────
## Last round an arc probe reported byte-identical numbers after real changes, and that was an
## artefact. So this file runs a LIVENESS canary FIRST and fails loudly if it does not fire:
##   * sweep rate must rise when the player's fill rises (the input that must move the output)
##   * the field the probe fights must actually restat when `career.gd`'s fill constants change
##     (checked by generating rivals at two fills and comparing their measured stat fill)
##   * champion fill must differ across rungs (if it is flat, no slope is even expressible)
## If the canary fails, every number below it is suspect and the probe exits non-zero.
extends Node

const BattleSimScript = preload("res://scripts/battle_sim.gd")
const TacticsScript = preload("res://scripts/tactics.gd")
## ⚠️ PRELOADED ONLY FOR ITS `ArcVariant` SUBCLASS — see `_run_arc_table()`. This probe does not
## own `_probe_gold_wall.gd` and does not modify it; it reuses the ONE autopilot subclass that
## already exists rather than growing a third copy of the career loop, which is this project's
## most expensive recurring failure.
const GoldWallScript = preload("res://scripts/_probe_gold_wall.gd")

# ── the climbing-player model ────────────────────────────────────────────────────────────────
## ⚠️ THE `PTS_PER_WEEK` / `WEEKS_PER_RUNG` / `WARMUP_WEEKS` CONSTANTS THAT LIVED HERE ARE DELETED,
## NOT UPDATED, AND THAT IS DELIBERATE. They described an ANALYTIC climber that `career.gd` no
## longer computes: `expected_climber_fill()` is now a lookup into a measured table
## (`CLIMBER_FILL_BY_LEAGUE`), produced by section 5 of this file. Leaving the old constants here
## would have re-created the exact failure the header warns about — two models of the player,
## agreeing only by hand, drifting apart the moment one of them changed. Both numbers were also
## wrong: `_probe_gold_wall.tscn` measures 60-70 weeks per rung, not 29, and ~7.3 effective points
## per monster-calendar-week once rest, excursion and the 26% road tax are counted, not 12.97.
const STATS_PER_MONSTER := 6.0

# ── sampling ─────────────────────────────────────────────────────────────────────────────────
var seeds_climb := 32            ## cup draws per league for the CLIMB table
var seeds_thresh := 8            ## cup draws per (league, fill) for the THRESHOLD scan
const THRESH_FILLS := [0.25, 0.35, 0.45, 0.55, 0.65, 0.75, 0.85, 0.95]

var _tree: SceneTree
var _fights := 0
var _fail := false


func _ready() -> void:
	_tree = get_tree()
	var args := OS.get_cmdline_user_args() + OS.get_cmdline_args()
	if "--quick" in args:
		seeds_climb = 8
		seeds_thresh = 4
	## ⚠️ `-- --seeds N` EXISTS BECAUSE THIS FILE'S OWN VERDICT LINE COUNTS INVERSIONS, AND AT
	## n=32 a proportion carries about ±9 points — so the instrument can manufacture an inversion
	## out of nothing and then report it as a finding. Raise the sample before believing one; that
	## is the note already written against the Masters/Tamer Elite wobble, made runnable.
	for i in range(args.size()):
		if str(args[i]) == "--seeds" and i + 1 < args.size():
			seeds_climb = maxi(4, int(str(args[i + 1])))
	print("=== LADDER SLOPE PROBE ===")
	_print_model()

	if not _liveness():
		print("\n=== ladder slope probe: INSTRUMENT FAILED — numbers not printed ===")
		_tree.quit(1)
		return
	if "--liveness" in args:
		print("\n=== ladder slope probe (liveness only): OK ===")
		_tree.quit(0)
		return

	## ⚠️ THE MODE THAT AUTHORS `career.gd:CLIMBER_FILL_*`. Everything else in this file MEASURES
	## the ladder against the climber model; this one MEASURES THE CLIMBER. Run it, read the two
	## tables it prints, paste them into `career.gd`. Never author that table by reasoning.
	if "--arc-table" in args:
		var seeds: int = 2 if "--quick" in args else 5
		_run_arc_table(seeds)
		## ⚠️ THIS MODE USED TO EXIT 0 WITH ITS OWN CANARIES SCREAMING (round 12). `_fail` is set
		## by the succession canary inside `_arc_fills`, and nothing read it here — so a run whose
		## competent player had no bench at all reported "OK" and its table got pasted anyway.
		## A canary that cannot fail the run is a comment.
		if _fail:
			print("=== ladder slope probe (arc table only): CANARY FAILED — "
				+ "the measured player is not the one the column claims ===")
			_tree.quit(1)
			return
		print("=== ladder slope probe (arc table only): OK ===")
		_tree.quit(0)
		return

	if "--response" in args:
		_run_response()
		print("\n%d simulated fights" % _fights)
		print("=== ladder slope probe (response only): OK ===")
		_tree.quit(0)
		return

	var climb: Array = _run_climb()
	var thresh: Array = _run_threshold()
	_report(climb, thresh)
	_run_model_sensitivity()
	print("\n%d simulated fights" % _fights)
	print("=== ladder slope probe: %s ===" % ("OK" if not _fail else "FAILED"))
	_tree.quit(1 if _fail else 0)


# =============================================================================
# THE CLIMBING PLAYER
# =============================================================================

## Mean base stat of the species the player can actually field — measured, not assumed, so a
## roster change moves this rather than silently invalidating the model.
func _base_avg() -> float:
	var total := 0.0
	var n := 0
	for id in Art.ROSTER:
		var sp: Dictionary = GameData.species_by_id.get(id, {})
		var base: Dictionary = sp.get("base", {})
		if base.is_empty():
			continue
		var s := 0.0
		for stat in Classify.STATS:
			s += float(base.get(stat, 10.0))
		total += s / STATS_PER_MONSTER
		n += 1
	return total / maxf(1.0, float(n))


## The fraction of rung `idx`'s ceiling a player who has CLIMBED to it can plausibly have filled.
## Absolute points in, fill out — see the header. Never a free parameter tuned to taste.
## ⚠️ THIS USED TO BE A SECOND COPY OF THE MODEL, AND THE COPY IS WHAT BROKE. `career.gd` prices
## the field as a RATIO to the expected climber; this probe then measured that field against a
## climber it computed itself, from its own `PTS_PER_WEEK`/`WEEKS_PER_RUNG` constants. So long as
## the two agreed by hand the numbers meant something. The moment `expected_climber_fill()` gained
## the team-size dilution and road-tax terms, the field came down and the probe's player did not —
## and the instrument reported a ladder that had gone from a climb to 100% ADVANCE at ten of
## eleven rungs. That was not the ladder getting easier; it was two models of the player drifting
## apart, which is the whole failure class this round was told to watch for.
## The constants above are retained ONLY to print the model's provenance; the number itself now
## comes from the file that USES it, so a change to one can never silently flatter the other.
func climbing_fill(idx: int) -> float:
	return Career.expected_climber_fill(idx)


func _print_model() -> void:
	print("\n─── THE CLIMBING PLAYER (the assumption every number below rests on) ───")
	## ⚠️ ROUND 12: THE TABLE IS NOW AUTHORED AND THIS PROBE'S `--arc-table` MODE VALIDATES IT
	## RATHER THAN DEFINING IT. It re-measured at .57 .36 .47 .46 .38 .38 .39 .36 .38 .38 .39
	## against a round-10 row of .49 .44 .49 .59 .53 .50 .48 .44 .44 .42 .43 — same instrument,
	## same policy, no difficulty decision in between, up to 22 points of silent re-pricing at a
	## rung. A measurement that moves like that cannot be the DEFINITION of a difficulty curve.
	print("  ⚠️ AUTHORED CURVE, VALIDATED BY MEASUREMENT (round 12). `career.gd` samples")
	print("  lerp(CLIMBER_FILL_WOOD, CLIMBER_FILL_APEX, ladder_shape(idx)); `-- --arc-table` runs")
	print("  the autopilot and CHECKS it. Systematic gap -> move an endpoint. One-rung gap ->")
	print("  investigate that rung, never put a bump in the curve.")
	print("  base stat of a fresh recruit: %.0f" % _base_avg())
	var line := "  "
	for idx in range(Career.leagues.size()):
		line += "%s %.2f  " % [str(Career.league_at(idx).get("name", "?")).substr(0, 3), climbing_fill(idx)]
	print(line)
	print("  (this row IS the measurement — `Career.expected_climber_fill`, straight from the table)")


## A player team at `fill` of rung `idx`'s ceiling, built through the SAME generator the rivals
## use (`GameData.make_monster` with `room_mult = 1.0`), so "fill" means the identical thing on
## both sides of the fight. ⚠️ The arc probe's `_team_at_fill` instead pins all six stats flat at
## `cap * fill`; that is a monster no training system can produce (and it classifies as a
## generalist, which changes its whole moveset), so it is not used here.
func _player_team(idx: int, fill: float, salt: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5100 + salt * 37 + idx
	var prev_league: int = Career.league_index
	Career.league_index = idx     # make_monster reads the cap through Career.current_stat_cap()
	var team: Array = []
	var size: int = Career.team_size_for_league(idx)
	for i in range(size):
		var species: String = Art.ROSTER[(salt * 3 + i * 5) % Art.ROSTER.size()]
		var mi = GameData.make_monster(species, clampf(fill, 0.0, 1.0), rng, 1.0)
		if mi != null:
			team.append(mi)
	Career.league_index = prev_league
	return team


## The OTHER player model — `_probe_career_arc.gd:_team_at_fill`, which pins all six stats flat at
## `cap * fill`. Reproduced here only so the two instruments' disagreement can be MEASURED rather
## than argued about (section 4). ⚠️ It is not a team any training system can produce: it dumps
## nothing, so it carries a maximal CON (and `maxHp` is superlinear in CON) and classifies as a
## generalist, which changes its whole moveset.
func _player_team_flat(idx: int, fill: float, salt: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91000 + salt
	var cap: float = Career.stat_cap_for_league(idx)
	var team: Array = []
	for i in range(Career.team_size_for_league(idx)):
		var mi = GameData.make_monster(Art.ROSTER[(salt + i * 5) % Art.ROSTER.size()], 0.0, rng)
		if mi == null:
			continue
		for stat in Classify.STATS:
			mi.stats[stat] = maxf(float(mi.stats[stat]), cap * fill)
		mi.recompute_class()
		mi.recompute_pools()
		mi.assign_moveset(rng)
		mi.hp = mi.max_hp
		mi.mp = mi.max_mp
		team.append(mi)
	return team


func _measured_fill(team: Array, cap: float) -> float:
	if team.is_empty():
		return 0.0
	var total := 0.0
	for m in team:
		var s := 0.0
		for stat in Classify.STATS:
			s += float(m.stats[stat])
		total += s / STATS_PER_MONSTER
	return total / float(team.size()) / maxf(1.0, cap)


# =============================================================================
# 5. THE ARC TABLE — MEASURE the climber instead of modelling it
# =============================================================================
## ⚠️ THIS SECTION EXISTS BECAUSE THE ANALYTIC CLIMBER MODEL WAS THE LADDER FILE'S LARGEST KNOWN
## INACCURACY, AND BECAUSE THE ATTEMPT TO FIX IT ANALYTICALLY FAILED. `career.gd` used to compute
## `CLIMBER_PTS_PER_WEEK * CLIMBER_WEEKS_PER_RUNG / cap`; adding per-body join weeks and a road tax
## to that formula drove the expected fill to 0.22-0.31 against an arc that independently measures
## 0.44-0.67, and the ladder read 100% ADVANCE at ten of eleven rungs. So the table is now MEASURED:
## run the autopilot, record what fraction of each rung's ceiling its roster actually carries when
## it leaves that rung, and interpolate THAT.
##
## ⚠️ TWO CLIMBERS ARE MEASURED, NOT ONE, AND THE DIFFERENCE IS THE POINT.
##   * CONTROL   — the autopilot exactly as it plays today. It stalls (median Silver over 5 seeds),
##                 so its top four rungs have FEW OR NO SAMPLES. A table with fabricated rows is
##                 worse than a formula, because it looks measured.
##   * COMPETENT — the same autopilot with the stable half played properly: shaped training, a
##                 re-drafted kit, a successor kept in training. AT FULL PRICE.
##                 ⚠️ ROUND 12: THIS COLUMN WAS SUBSIDISED UNTIL 2026-08-09 — free recruits, free
##                 barn slots, free breeding and a waived entry fee — and the whole field was
##                 priced against it. Measured at 8 seeds, the same policy completes 2/8 careers
##                 at full price against 8/8 subsidised. A discount is not a skill.
## The field must be priced against the player the game intends to produce, which is the competent
## one; the control column is printed beside it so the gap is visible rather than assumed.
const ARC_SEEDS := [20260809, 771013, 313373, 4242424, 99180]
const ARC_WEEKS := 900

func _run_arc_table(n_seeds: int) -> void:
	print("\n─── 5. THE ARC TABLE (measure the climber; author career.gd's fill table off this) ───")
	var control: Array = _arc_fills("control", n_seeds)
	var competent: Array = _arc_fills("policy_all", n_seeds)
	print("\n  league        control fill@exit (n)      competent fill@exit (n)")
	for idx in range(Career.leagues.size()):
		var c: Dictionary = control[idx]
		var k: Dictionary = competent[idx]
		print("  %-12s  %s   %s" % [
			Career.league_at(idx).get("name", "?"), _fmt_cell(c), _fmt_cell(k)])
	var row := "  competent, as a career.gd table: ["
	for idx in range(Career.leagues.size()):
		row += "%.2f, " % float(competent[idx]["mean"])
	print(row + "]")
	print("  ⚠️ A CELL WITH n=0 IS NOT A MEASUREMENT. Mark it EXTRAPOLATED in career.gd.")


func _fmt_cell(c: Dictionary) -> String:
	if int(c["n"]) == 0:
		return "     —      (0)   "
	return "  %.2f  [%.2f-%.2f] (%d)" % [float(c["mean"]), float(c["lo"]), float(c["hi"]), int(c["n"])]


## Run `n_seeds` autopilot careers of `kind` and return, per league index, the mean/min/max
## `fillAtExit` over the seeds that actually VISITED that rung, plus the sample count.
func _arc_fills(kind: String, n_seeds: int) -> Array:
	var acc: Array = []
	for i in range(Career.leagues.size()):
		acc.append([])
	var reached: Array = []
	for s in range(mini(n_seeds, ARC_SEEDS.size())):
		var v = GoldWallScript.ArcVariant.new()
		v.v_seed = int(ARC_SEEDS[s])
		if kind == "policy_all":
			## ⚠️ ROUND 12 SEAM FIX — THIS COLUMN USED TO BE SUBSIDISED AND CALLED COMPETENT.
			## It also set `v_free_bodies = true` and passed `{"feeMult": 0.0}`, i.e. free
			## recruits, free barn slots, free breeding and no entry fee. Measured by
			## `_probe_career_arc.gd --policies` at 8 seeds on the round-11 ship ladder, the SAME
			## policy wins 2/8 careers at full price against 8/8 subsidised. So the table the
			## whole field is priced against was priced against a player who does not pay for
			## anything — a 4x difference in completion hiding behind a label. Competence is
			## SHAPED TRAINING + A RE-DRAWN KIT + SUCCESSION. It is not a discount.
			v.v_redraft_kits = true
			v.v_succession = true
			v.v_shaped_training = true
		var opts: Dictionary = {}
		var a: Dictionary = v._run_arc(ARC_WEEKS, opts)
		var buys: int = v.succession_buys
		v.free()
		reached.append(int(a["finalLeague"]))
		## ⚠️ THE SUCCESSION CANARY ASKED THE WRONG QUESTION AND FAILED EVERY SEED (round 12).
		## `_grow_successor()` returns early when `active.size() > team` — i.e. when a spare
		## already exists — and round 11's four-wire fix made the arc's MAINLINE recruit
		## `team_need + BENCH_SIZE`. So succession never has anything left to buy. The switch is
		## REDUNDANT, not inert, and the thing it was invented to guarantee (a trained body
		## outside the team sheet) is what must be asserted. `benchWeeks == 0` is the real
		## failure: that is a stable one retirement away from a forfeit.
		if kind == "policy_all" and int(a.get("benchWeeks", 0)) <= 0:
			print("  ⚠️ succession canary: seed %d spent 0 monster-weeks on the bench (%d "
				% [int(ARC_SEEDS[s]), buys] + "successor buys) — no trained cover exists.")
			_fail = true
		var rows: Array = a["perLeague"]
		for i in range(rows.size()):
			var r: Dictionary = rows[i]
			## Only rungs the arc actually STOOD ON contribute. `fillAtExit` is left at 0.0 for a
			## rung never reached, and averaging a zero in is how a fabricated row gets born.
			if int(r["weeks"]) > 0 and float(r["fillAtExit"]) > 0.0:
				(acc[i] as Array).append(float(r["fillAtExit"]))
	print("  %-12s reached %s" % [kind, str(reached)])
	var out: Array = []
	for i in range(acc.size()):
		var xs: Array = acc[i]
		if xs.is_empty():
			out.append({"mean": 0.0, "lo": 0.0, "hi": 0.0, "n": 0})
			continue
		var sum := 0.0
		var lo := 9.0
		var hi := 0.0
		for x in xs:
			sum += float(x)
			lo = minf(lo, float(x))
			hi = maxf(hi, float(x))
		out.append({"mean": sum / float(xs.size()), "lo": lo, "hi": hi, "n": xs.size()})
	return out


# =============================================================================
# ONE CUP
# =============================================================================

## Fight the real drawn field of rung `idx` once, with a player team at `fill`.
## Returns {"wins": [bool per round], "swept": bool, "fill": measured player fill}.
func _run_cup(idx: int, fill: float, attempt: int, flat: bool = false) -> Dictionary:
	var prev_week: int = Career.week
	Career.week = 1 + attempt * 4      # ⚠️ the field seed is month-stable — move it or every
	Career.league_index = idx          #    attempt redraws the same three teams
	var rounds: int = maxi(1, Career.rival_count_for_league(idx))
	var field: Array = Career.make_cup_field(idx, rounds)
	var wins: Array = []
	var swept := true
	for r in range(field.size()):
		var salt: int = attempt * 11 + r
		var team: Array = _player_team_flat(idx, fill, salt) if flat else _player_team(idx, fill, salt)
		var rivals: Array = field[r]["team"]
		for m in team:
			m.reset_for_battle()
		for m in rivals:
			m.reset_for_battle()
		var rng := RandomNumberGenerator.new()
		rng.seed = 41000 + idx * 313 + attempt * 17 + r
		## ⚠️ THE FIELD FIGHTS WITH ITS OWN PLAN, BECAUSE THE GAME NOW DOES. `career.gd:
		## enter_league_tournament` passes the drawn round's archetype plan and orders into the
		## sim; an instrument that built the same teams and then fought them WITHOUT their tactics
		## would be measuring a fight no player ever has — and it would read as ~10 points of free
		## ladder. Same construction as the live path, deliberately.
		var gid: String = String(field[r].get("archetype", ""))
		var plan_b: Dictionary = TacticsScript.team_plan_for_gameplan(gid, team) if gid != "" else {}
		var orders: Dictionary = TacticsScript.orders_for_gameplan(gid, rivals) if gid != "" else {}
		var sim = BattleSimScript.new(team, rivals, rng.randi(), {}, plan_b, orders)
		_fights += 1
		var won: bool = str(sim.run().get("winner", "")) == "A"
		wins.append(won)
		if not won:
			swept = false
	Career.week = prev_week
	return {"wins": wins, "swept": swept}


func _sweep_rate(idx: int, fill: float, attempts: int, flat: bool = false) -> float:
	var sweeps := 0
	for a in range(attempts):
		if bool(_run_cup(idx, fill, a, flat)["swept"]):
			sweeps += 1
	return float(sweeps) / float(maxi(1, attempts))


## The rate at which a team at `fill` takes the RANK — the rule the ladder actually runs on
## (`Career.wins_needed_to_advance`). ⚠️ The threshold scan measures THIS, not the sweep: a
## threshold quoted against a rule the game does not use is a number about a different game.
## At Tamers Apex the two coincide, because the summit forgives nothing.
func _advance_rate(idx: int, fill: float, attempts: int) -> float:
	var got := 0
	for a in range(attempts):
		var res: Dictionary = _run_cup(idx, fill, a)
		var rounds: int = (res["wins"] as Array).size()
		var w := 0
		for x in res["wins"]:
			if bool(x):
				w += 1
		if w >= Career.wins_needed_to_advance(idx, rounds):
			got += 1
	return float(got) / float(maxi(1, attempts))


## ⚠️ SECTION 4 EXISTS BECAUSE TWO INSTRUMENTS IN THIS REPO DISAGREE ABOUT THE SAME LADDER, AND
## THE DIFFERENCE IS ENTIRELY THE PLAYER MODEL. Same fill, same field, same fights — one team
## built by the real generator, one with all six stats pinned flat. If these two columns are far
## apart, then every ladder number ever quoted in this project is a statement about the team that
## was assumed, not about the ladder.
func _run_model_sensitivity() -> void:
	print("\n─── 4. WHICH PLAYER? (sweep rate at the SAME 0.65 fill, two ways of building it) ───")
	print("  league        generator-built   flat-stat build (arc probe's)")
	for idx in [0, 3, 5, 7, 10]:
		if idx >= Career.leagues.size():
			continue
		var gen := _sweep_rate(idx, 0.65, seeds_thresh)
		var flat := _sweep_rate(idx, 0.65, seeds_thresh, true)
		print("  %-12s      %4.0f%%              %4.0f%%" % [
			Career.league_at(idx).get("name", "?"), gen * 100.0, flat * 100.0])
	print("  (a flat build dumps NOTHING, so it carries a maximal CON — and maxHp is superlinear in")
	print("   CON. It is stronger than any trained monster at the same fill. This probe uses the")
	print("   generator build for every other number.)")


# =============================================================================
# LIVENESS CANARY — does this instrument move when its inputs move?
# =============================================================================
func _liveness() -> bool:
	print("\n─── LIVENESS (rule 9: an instrument that cannot move cannot measure) ───")
	var ok := true
	var mid: int = Career.leagues.size() / 2

	# 1. the field restats when asked for a different fill
	Career.league_index = mid
	var weak: Array = Career.make_league_rivals(3, mid, 0.25, 12345)
	var strong: Array = Career.make_league_rivals(3, mid, 0.90, 12345)
	var cap: float = Career.stat_cap_for_league(mid)
	var wf := _measured_fill(weak, cap)
	var sf := _measured_fill(strong, cap)
	print("  field restats with fill:   %.2f -> %.2f   %s" % [wf, sf, "OK" if sf > wf + 0.2 else "DEAD"])
	ok = ok and sf > wf + 0.2

	# 2. champion fill differs across rungs — without this no slope is even expressible
	## ⚠️ THIS CHECK USED TO READ `champion_fill_for(Apex) > champion_fill_for(Wood) + 0.05`, AND
	## IT FIRED THE MOMENT THE CLIMBER MODEL BECAME A MEASUREMENT. That is the canary doing its job
	## and then the check being wrong: `champion_fill_for` is a QUOTIENT of the league's own
	## ceiling, and the MEASURED climber's fill FALLS up the ladder (0.49 at Wood, 0.43 at Apex —
	## the cap outruns what a career can train). A field priced as a RATIO to that climber falls as
	## a fraction too, while getting enormously stronger in absolute points. So the two things that
	## must actually be true are checked instead: the champion's RATIO to the climber rises (the
	## difficulty knob this file authors) and the champion's ABSOLUTE budget rises (the fight the
	## player really has). A flat fill is evidence of nothing either way.
	var top: int = Career.leagues.size() - 1
	var lo_ratio := Career.champion_fill_for(0) / maxf(0.01, Career.expected_climber_fill(0))
	var hi_ratio := Career.champion_fill_for(top) / maxf(0.01, Career.expected_climber_fill(top))
	print("  champion RATIO Wood->Apex: %.2f -> %.2f   %s" % [
		lo_ratio, hi_ratio, "OK" if hi_ratio > lo_ratio + 0.02 else "DEAD"])
	ok = ok and hi_ratio > lo_ratio + 0.02
	var lo_abs := Career.champion_fill_for(0) * Career.stat_cap_for_league(0)
	var hi_abs := Career.champion_fill_for(top) * Career.stat_cap_for_league(top)
	print("  champion PTS  Wood->Apex:  %.0f -> %.0f   %s" % [
		lo_abs, hi_abs, "OK" if hi_abs > lo_abs * 2.0 else "DEAD"])
	ok = ok and hi_abs > lo_abs * 2.0

	# 3. THE ONE THAT MATTERS: sweep rate must respond to player strength
	var low_rate := _sweep_rate(mid, 0.30, 6)
	var high_rate := _sweep_rate(mid, 0.95, 6)
	print("  sweep vs player fill:      %.0f%% at .30 -> %.0f%% at .95   %s" % [
		low_rate * 100.0, high_rate * 100.0, "OK" if high_rate > low_rate else "DEAD"])
	ok = ok and high_rate > low_rate
	if not ok:
		print("  ⚠️ CANARY FAILED — the probe is not measuring what it claims to.")
	return ok


# =============================================================================
# 1. THE CLIMB
# =============================================================================
func _run_climb() -> Array:
	var out: Array = []
	for idx in range(Career.leagues.size()):
		var fill: float = climbing_fill(idx)
		var rounds: int = maxi(1, Career.rival_count_for_league(idx))
		var opener := 0
		var champ := 0
		var sweeps := 0
		var promotes := 0
		var hurried := 0
		var round_wins := 0
		var round_total := 0
		var need: int = Career.wins_needed_to_advance(idx, rounds)
		## ⚠️ PER-ROUND HITS — the term the CHAMPION BAND is computed from (section 1b). It is
		## measured here rather than in `_probe_sawtooth.gd` because that probe carries a COPY of
		## `Career.field_fill()` and its canary refuses to run whenever the champion formula
		## changes. This one calls `Career.make_cup_field()` directly, so it cannot drift.
		var hits: Array = []
		for r in range(rounds):
			hits.append(0)
		for a in range(seeds_climb):
			var res: Dictionary = _run_cup(idx, fill, a)
			var wins: Array = res["wins"]
			var won_count := 0
			for r in range(mini(wins.size(), hits.size())):
				if bool(wins[r]):
					hits[r] = int(hits[r]) + 1
			if wins.size() > 0 and bool(wins[0]):
				opener += 1
			if wins.size() > 0 and bool(wins[wins.size() - 1]):
				champ += 1
			for w in wins:
				round_total += 1
				if bool(w):
					round_wins += 1
					won_count += 1
			if bool(res["swept"]):
				sweeps += 1
			if won_count >= need:
				promotes += 1
			## ⚠️ THE HURRIED CLIMBER. The model assumes 29 weeks per rung; a ladder that promotes
			## FASTER hands the player a rung they have trained less for, so the difficulty must
			## also be measured for a climber arriving ~15% under-filled. If this column collapses
			## to zero, the ladder punishes its own pacing.
			if bool(_run_cup(idx, fill * 0.85, a)["swept"]):
				hurried += 1
		var p: Array = []
		for r in range(rounds):
			p.append(float(hits[r]) / float(seeds_climb))
		var qsum := 0.0
		for r in range(rounds - 1):
			qsum += float(p[r])
		var qmean: float = qsum / float(maxi(1, rounds - 1))
		out.append({
			"idx": idx, "fill": fill, "rounds": rounds, "need": need,
			"p": p, "qmean": qmean, "band": float(p[rounds - 1]) - qmean,
			"opener": float(opener) / float(seeds_climb),
			"champion": float(champ) / float(seeds_climb),
			"sweep": float(sweeps) / float(seeds_climb),
			"promote": float(promotes) / float(seeds_climb),
			"hurried": float(hurried) / float(seeds_climb),
			"round": float(round_wins) / float(maxi(1, round_total)),
		})
	return out


# =============================================================================
# 2. THE THRESHOLD
# =============================================================================
func _run_threshold() -> Array:
	var out: Array = []
	for idx in range(Career.leagues.size()):
		var t := -1.0
		var rates: Array = []
		for f in THRESH_FILLS:
			var rate := _advance_rate(idx, float(f), seeds_thresh)
			rates.append(rate)
			if t < 0.0 and rate >= 0.5:
				t = float(f)
		out.append({"idx": idx, "t": t, "rates": rates})
	return out


# =============================================================================
# 3. THE RESPONSE — the transfer function the fill constants are authored against
# =============================================================================
## ⚠️ THIS IS THE TABLE THAT MAKES `career.gd`'s FILL CONSTANTS AUTHORABLE RATHER THAN GUESSED.
## `FIELD_OPENER_*` / `FIELD_CHAMPION_*` are fractions of a league ceiling; what a designer
## actually wants to author is a WIN RATE per round. Those two are related by a curve that is
## different at every rung (the caps differ, and HP is superlinear in CON), so the only honest way
## to set the constants is to measure the curve and read the fill off it.
##
## Run alone with `-- --response`.
const RESPONSE_FILLS := [0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 1.00]

func _run_response() -> void:
	print("\n─── 3. THE RESPONSE (climbing player's win rate vs ONE rival team at a given fill) ───")
	var head := "  league       climb |"
	for f in RESPONSE_FILLS:
		head += " %.2f" % float(f)
	print(head)
	for idx in range(Career.leagues.size()):
		var pf: float = climbing_fill(idx)
		var size: int = Career.team_size_for_league(idx)
		var line := "  %-12s %.2f |" % [Career.league_at(idx).get("name", "?"), pf]
		for f in RESPONSE_FILLS:
			var wins := 0
			var n := seeds_climb
			for a in range(n):
				Career.league_index = idx
				var rivals: Array = Career.make_league_rivals(size, idx, float(f), 900 + a * 61 + idx * 7)
				var team: Array = _player_team(idx, pf, a * 13 + idx)
				for m in team:
					m.reset_for_battle()
				for m in rivals:
					m.reset_for_battle()
				var rng := RandomNumberGenerator.new()
				rng.seed = 61000 + idx * 271 + a
				var sim = BattleSimScript.new(team, rivals, rng.randi())
				_fights += 1
				if str(sim.run().get("winner", "")) == "A":
					wins += 1
			line += " %3.0f " % (100.0 * float(wins) / float(n))
		print(line)
	print("  (read a target win rate off the row, take the fill from the column heading, then")
	print("   author it into career.gd's FIELD_* endpoints. Never guess these.)")


# =============================================================================
# REPORT
# =============================================================================
func _report(climb: Array, thresh: Array) -> void:
	print("\n─── 1. THE CLIMB (each rung fought by the player who climbed to it) ───")
	print("  league        fill  rnds need  opener  champ  round  sweep  ADVANCE  d   hurried")
	var prev := -1.0
	for row in climb:
		var d := "   —" if prev < 0.0 else "%+4.0f" % ((float(row["promote"]) - prev) * 100.0)
		print("  %-12s  %.2f   %d   %d/%d  %4.0f%%  %4.0f%%  %4.0f%%  %4.0f%%   %4.0f%%  %s   %4.0f%%" % [
			Career.league_at(int(row["idx"])).get("name", "?"), float(row["fill"]), int(row["rounds"]),
			int(row["need"]), int(row["rounds"]),
			float(row["opener"]) * 100.0, float(row["champion"]) * 100.0,
			float(row["round"]) * 100.0, float(row["sweep"]) * 100.0,
			float(row["promote"]) * 100.0, d, float(row["hurried"]) * 100.0])
		prev = float(row["promote"])
	print("  ADVANCE = the real rule (`Career.wins_needed_to_advance`); sweep = the TITLE.")
	print("  (a CLIMB shows ADVANCE falling as the rungs go up. Flat = a time gate, not a ladder.)")

	## ── 1b. THE CHAMPION BAND ────────────────────────────────────────────────────────────────
	## ⚠️ THE DIRECT TEST OF "EVERY RUNG HAS A REAL CHAMPION". `band` = the champion round's win
	## probability MINUS the mean of that cup's own qualifying rounds. It must be NEGATIVE at every
	## rung (the titleholder is the hardest team in their own draw) and it should DEEPEN up the
	## ladder. A POSITIVE band means the rung's "champion" is a soft round wearing a name — which
	## is exactly what Silver (+0.09) and Platinum (+0.03) measured before this section existed,
	## and those were the two largest ADVANCE inversions in the ladder.
	print("\n─── 1b. THE CHAMPION BAND (champion p minus this cup's own qualifier mean) ───")
	print("  league        p[0]  p[1]  p[2]  p[3]  p[4] | qual mean  champion   BAND")
	var soft := 0
	for row in climb:
		var p: Array = row["p"]
		var cells := ""
		for r in range(5):
			cells += ("%5.2f " % float(p[r])) if r < p.size() else "    . "
		var band: float = float(row["band"])
		if band >= 0.0:
			soft += 1
		print("  %-12s %s|   %.2f      %.2f     %+.2f %s" % [
			Career.league_at(int(row["idx"])).get("name", "?"), cells,
			float(row["qmean"]), float(p[p.size() - 1]), band,
			"⚠️ NOT A CHAMPION" if band >= 0.0 else ""])
	print("  rungs whose champion is EASIER than their own qualifiers: %d of %d   %s" % [
		soft, climb.size(), "OK" if soft == 0 else "⚠️ SOFT CHAMPIONS"])

	print("\n─── 2. THE THRESHOLD (lowest player fill that ADVANCES from half its cups) ───")
	var head := "  league        t*   climb  headroom |"
	for f in THRESH_FILLS:
		head += " %.2f" % float(f)
	print(head)
	var neg := 0
	var heads: Array = []
	for i in range(thresh.size()):
		var row: Dictionary = thresh[i]
		var idx: int = int(row["idx"])
		var t: float = float(row["t"])
		var cf: float = climbing_fill(idx)
		var headroom: float = (cf - t) if t >= 0.0 else -1.0
		heads.append(headroom)
		## ⚠️ NEGATIVE HEADROOM IS NOT "IMPOSSIBLE", IT IS "MORE THAN ONE CUP". A rung whose t*
		## sits above the modelled fill costs the climber a few attempts (or a few more weeks in
		## the gym) — which is what the top of a ladder is FOR. The completability test is the
		## harsher one below: a rung no roster in the scan can advance from at all.
		if t < 0.0:
			neg += 1
		var line := "  %-12s %s  %.2f   %s |" % [
			Career.league_at(idx).get("name", "?"),
			("%.2f" % t) if t >= 0.0 else " —  ", cf,
			("%+.2f" % headroom) if t >= 0.0 else " n/a "]
		for r in row["rates"]:
			line += " %3.0f " % (float(r) * 100.0)
		print(line)
	print("  (t* = required fill; headroom = what the climber has spare. A CLIMB shrinks headroom")
	print("   up the ladder and may go slightly negative at the top — that is the rung costing more")
	print("   than one cup, which is what a summit is for. Uncompletable is the line below it.)")

	# The two verdicts, stated rather than left to the reader.
	var first_adv: float = float(climb[0]["promote"])
	var last_adv: float = float(climb[climb.size() - 1]["promote"])
	print("\n─── VERDICT ───")
	print("  slope (Wood advance -> Apex):      %.0f%% -> %.0f%%   %s" % [
		first_adv * 100.0, last_adv * 100.0,
		"SLOPED" if last_adv < first_adv - 0.10 else "FLAT / INVERTED"])
	# Monotonicity matters as much as the endpoints: a rung EASIER than the one below it is the
	# inverted-progression failure this studio has hit before.
	var inversions := 0
	for i in range(1, climb.size()):
		if float(climb[i]["promote"]) > float(climb[i - 1]["promote"]) + 0.12:
			inversions += 1
	print("  rungs easier than the one below:   %d   %s" % [
		inversions, "MONOTONE" if inversions == 0 else "⚠️ INVERTED somewhere"])
	## ⚠️ INVERSION MASS — the same statistic `_probe_sawtooth.gd` reports, computed here so this
	## probe can stand alone. A COUNT of inversions is threshold-sensitive (±9 pts at n=32 can
	## manufacture or hide one); the MASS — the total of every upward rung-to-rung step — is
	## continuous, so it moves smoothly with a real improvement instead of flipping.
	var inv_mass := 0.0
	var inv_count := 0
	for i in range(1, climb.size()):
		var d: float = float(climb[i]["promote"]) - float(climb[i - 1]["promote"])
		if d > 0.0:
			inv_mass += d
			inv_count += 1
	print("  INVERSION MASS (sum of up-steps): %5.1f over %d up-steps  (0.0 = perfectly monotone)" % [
		inv_mass * 100.0, inv_count])
	var cups := "  expected cups per rung:            "
	for row in climb:
		var p: float = maxf(0.01, float(row["promote"]))
		cups += "%.1f " % (1.0 / p)
	print(cups)
	var head_lo: float = float(heads[0])
	var head_hi: float = float(heads[heads.size() - 1])
	print("  headroom Wood -> Apex:             %+.2f -> %+.2f   %s" % [
		head_lo, head_hi, "TIGHTENS" if head_hi < head_lo else "SLACKENS"])
	print("  rungs no roster can advance from:  %d of %d   %s" % [
		neg, thresh.size(), "COMPLETABLE" if neg == 0 else "⚠️ NOT COMPLETABLE"])
	var walled := 0
	for row in climb:
		if float(row["promote"]) <= 0.0:
			walled += 1
	print("  rungs the modelled climber never clears: %d   %s" % [
		walled, "the ladder is walkable" if walled == 0 else "⚠️ WALL"])
	if walled > 0:
		_fail = true
	if float(climb[climb.size() - 1]["sweep"]) <= 0.0:
		_fail = true
		print("  ⚠️ Apex is never swept in %d attempts by the modelled climber — the ship target" % seeds_climb)
		print("     ('winning is completing Tamers Apex') is not reachable. This is a FAILURE.")
