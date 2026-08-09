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
## It does, from two measured numbers:
##   * the best drill family yields **12.97 stat points per monster-week** (`_probe_training` §2,
##     measured on THIS build — not META_GAME_REVIEW §T1's 14.45, which predates the focus rework)
##   * the winning career took **319 weeks for 11 rungs ≈ 29 weeks per rung** (META_GAME_REVIEW §2)
## A monster's stats are therefore roughly `base + 12.97 * (29 * L + warmup) / 6` per stat on
## arriving at rung L — an ABSOLUTE budget growing LINEARLY — while the cap grows 100 → 1100.
## Dividing gives the fill the player can actually have; the probe prints the whole row every run.
##
## ⚠️ AND THAT IS THE MODEL'S OWN VALIDATION, TWICE OVER: the arc probe's independently measured
## `fill@exit` column reads 44/39/43/67/56/67/66/52/63/61/62, and `_probe_training` §1 measures a
## full career banking 4,479 stat points — 746 per stat, 0.68 of the Apex ceiling. The model lands
## on both without being fitted to either. It is printed on every run, because a difficulty number
## quoted without its player model is meaningless.
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

# ── the climbing-player model (see header) ───────────────────────────────────────────────────
## ⚠️ MEASURED BY `scenes/_probe_training.tscn` §2 ON THIS BUILD (12.97 pts/week, best drill
## family), NOT the 14.45 in META_GAME_REVIEW §T1 — that figure predates the focus-cost training
## rework. `career.gd:CLIMBER_PTS_PER_WEEK` carries the same number; if the two ever disagree the
## ladder is being tuned against a player the game does not produce.
const PTS_PER_WEEK := 12.97
const WEEKS_PER_RUNG := 29.0     ## measured: 319 weeks / 11 rungs (§2)
const STATS_PER_MONSTER := 6.0
## ⚠️ NOBODY ENTERS A CUP THE WEEK THEY ARRIVE. Without this the model says a Wood player is at
## 23% of the Wood ceiling — literally a monster straight off the market with no training at all —
## and Wood then measures as the HARDEST rung on the ladder, which is a modelling artefact, not a
## finding. Eight weeks is the arc probe's own cadence (a cup attempt every 4 weeks, and the arc
## needed two attempts at the quick rungs). It also brings the model onto the arc's independently
## measured Wood fill@exit of 0.44 (model: 0.42), which is the check that it is not made up.
const WARMUP_WEEKS := 8.0

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
	print("  a monster gains %.2f stat points/week (measured, META_GAME_REVIEW T1) and the measured" % PTS_PER_WEEK)
	print("  winning career spent %.0f weeks per rung, so its stat budget grows LINEARLY while the" % WEEKS_PER_RUNG)
	print("  league cap grows 100 -> 1100. Fill is the QUOTIENT, not an input:")
	print("  base stat of a fresh recruit: %.0f" % _base_avg())
	var line := "  "
	for idx in range(Career.leagues.size()):
		line += "%s %.2f  " % [str(Career.league_at(idx).get("name", "?")).substr(0, 3), climbing_fill(idx)]
	print(line)
	print("  (arc probe's independently measured fill@exit: .44 .39 .43 .67 .56 .67 .66 .52 .63 .61 .62)")


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
	var lo := Career.champion_fill_for(0)
	var hi := Career.champion_fill_for(Career.leagues.size() - 1)
	print("  champion fill Wood->Apex:  %.2f -> %.2f   %s" % [lo, hi, "OK" if hi > lo + 0.05 else "DEAD"])
	ok = ok and hi > lo + 0.05

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
		for a in range(seeds_climb):
			var res: Dictionary = _run_cup(idx, fill, a)
			var wins: Array = res["wins"]
			var won_count := 0
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
		out.append({
			"idx": idx, "fill": fill, "rounds": rounds, "need": need,
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
