## ARCHETYPE PROBE — "is the champion a different KIND of team, or just a stronger one?"
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_archetypes.tscn
##
## The integrator verdict of 2026-08-09 named this the biggest miss against the vision: all eleven
## league champions authored a `read` line ("Stalls. Wins on the clock", "Controls. You will be
## stunned…") and every one of them was FLAVOUR TEXT, because every rival team in the game came
## out of one generator that differed only by `field_fill`. This probe is the acceptance test for
## the fix: it builds each archetype, fights it, and asserts its SIGNATURE is visible in the event
## log. A `read` line this probe cannot verify is a lie, and the line changes rather than shipping.
##
## ⚠️ IT ALSO CHECKS ITSELF (§9 of the round brief — last round an arc probe reported byte-identical
## results after real changes and that was an instrument artifact). `_null_run()` re-runs the whole
## metric table with the archetype argument SUPPRESSED. If the six rows do not collapse into each
## other there, the instrument is not measuring what it claims to measure and the probe says so.
##
## ⚠️ THE ENGINE HERE IS `battle_sim.gd`, DELIBERATELY. That is the engine `career.gd:
## enter_league_tournament()` and the arc instrument actually fight the ladder on — so an
## archetype that only showed up in the spatial sim would not exist where the ladder is measured.
## It is also why two authored champion reads (Bray's flanks, Vane's kiting) had to be rewritten:
## `battle_sim.gd` has no positions at all.
extends Node

const BattleSimScript = preload("res://scripts/battle_sim.gd")
const TacticsScript = preload("res://scripts/tactics.gd")

## Platinum: cap 900, team size 5 — the game is a 5v5 game (CLAUDE.md), and the archetypes have to
## be legible at the size the ladder is balanced for.
const LEAGUE_IDX := 7
const TEAM_SIZE := 5
const FILL := 0.65          ## the integrator's measured "real winning roster" fill
const TRIALS := 24
const BASE_SEED := 20260809

var _pass := 0
var _fail := 0


func _ready() -> void:
	print("=== ARCHETYPES: is the champion a different KIND of team? ===\n")
	Career.reset_new_game()
	Roster.reset_to_empty()
	Career.league_index = LEAGUE_IDX
	print("league %s (idx %d)  cap %.0f  team size %d  fill %.2f  trials %d\n" % [
		Career.current_league_name(), LEAGUE_IDX, Career.current_stat_cap(), TEAM_SIZE, FILL, TRIALS])

	if OS.get_cmdline_user_args().has("--calibrate"):
		_calibrate()
		get_tree().quit(0)
		return

	_composition_report()
	var rows := _metric_table(true)
	_signature_assertions(rows)
	_strength_band(rows)
	_null_run(rows)
	_counter_formation()
	_counter_matrix()
	_ladder_reads()

	print("\n=== archetypes: %d passed, %d failed ===" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		print("  *** FAIL *** %s" % label)


func _ids() -> Array:
	return TacticsScript.GAMEPLANS.keys()


# ── 1. COMPOSITION: do the teams differ in KIND? ─────────────────────────────────────────────

func _composition_report() -> void:
	print("── COMPOSITION (the classes each archetype actually fields) ──")
	var seen_signatures := {}
	for gid in _ids():
		Roster.rng.seed = BASE_SEED
		var team: Array = Roster.make_rival_team(TEAM_SIZE, FILL, 1.0, gid)
		var classes: Array = team.map(func(m): return m.class_name_)
		var roles: Array = team.map(func(m): return m.role)
		var want: Array = TacticsScript.archetype_classes(gid, TEAM_SIZE)
		var matched := 0
		for i in range(team.size()):
			if str(classes[i]) == str(want[i]):
				matched += 1
		print("  %-10s %-52s supports %d/%d" % [gid, ", ".join(classes), roles.count("support"), team.size()])
		_check(matched == team.size(), "%s fields exactly its authored class pattern (%d/%d)" % [gid, matched, team.size()])
		seen_signatures[", ".join(classes)] = gid
	_check(seen_signatures.size() == _ids().size(),
		"all %d archetypes field a DISTINCT composition (%d distinct)" % [_ids().size(), seen_signatures.size()])

	# SUM-PRESERVING DISCIPLINE: shaping redistributes points, it never adds them.
	# ⚠️ MEASURED ON THE SAME MONSTER, BEFORE AND AFTER. The first version of this check compared
	# a shaped TEAM against an unshaped one and read 6.2% drift — but the two teams are different
	# SPECIES (the archetype path picks the species that suits the slot's class), so it was
	# measuring species variance, not shaping. `field_fill()` is the one dial that says how strong
	# a round is; if shaping moved the total, every measurement taken against that curve would be
	# wrong, so this has to be exact.
	var rng := RandomNumberGenerator.new()
	rng.seed = BASE_SEED
	var worst := 0.0
	var wrong_class := 0
	for gid in _ids():
		for want in TacticsScript.archetype_classes(gid, TEAM_SIZE):
			for sid in Art.ROSTER:
				var mi = GameData.make_monster(str(sid), FILL, rng, 1.0)
				var before := 0.0
				for st in Classify.STATS:
					before += float(mi.stats[st])
				Roster._shape_to_class(mi, str(want), rng)
				var after := 0.0
				for st in Classify.STATS:
					after += float(mi.stats[st])
				worst = maxf(worst, absf(after - before) / maxf(1.0, before))
				if mi.class_name_ != str(want):
					wrong_class += 1
	print("  shaping, per monster: worst stat-total drift %.4f%% over %d shapes" % [
		worst * 100.0, _ids().size() * TEAM_SIZE * Art.ROSTER.size()])
	_check(worst < 0.005, "shaping is sum-preserving (worst drift %.4f%% < 0.5%%)" % (worst * 100.0))
	_check(wrong_class == 0,
		"every species can be shaped into every archetype class — no species is locked out of a role (%d misses)" % wrong_class)
	print("")


func _stat_sum(team: Array) -> float:
	var t := 0.0
	for m in team:
		for st in Classify.STATS:
			t += float(m.stats.get(st, 0.0))
	return t


# ── 2. SIGNATURE: does each archetype DO what its read line says? ────────────────────────────

## ⚠️ CONCENTRATION IS MEASURED UP TO THE FIRST KILL, NOT OVER THE WHOLE FIGHT, AND THE FIRST
## VERSION OF THIS PROBE GOT IT WRONG IN EXACTLY THE WAY `tools/focus.ts` DID FIRST. Over a whole
## fight, top-share is dominated by fight LENGTH: a team that wins has by definition damaged every
## enemy to death, so the flattest number on the board belonged to the fastest killer (focus-fire
## measured 0.272, the LOWEST of six) while the archetype that barely damaged anything measured
## the highest. Up to the first death the metric means what its name says — how much of the
## opening exchange landed on one body.
## ⚠️ TURN-DENYING CONTROL, AND `knockback` IS DELIBERATELY NOT IN IT even though `data.json:
## hardControlStatuses` lists it. Its entire rule is `{"speedMult": 0.6}` — on the NON-SPATIAL cup
## engine there is no speed and no position, so a landed knockback changes literally nothing. It
## was 5 of the wall archetype's hard-control events per fight (one area cast touches five bodies),
## which is how a comp with no casters in it came within a hair of out-controlling the control
## comp on the naive metric. Counting an effect the engine does not implement is the "authored but
## never reachable" failure this codebase keeps re-finding, wearing a measurement's hat.
const HARD_CONTROL := ["stun", "sleep", "fear", "confusion", "charm", "silence"]


## One fight, measured from B's point of view (B is always the archetype under test).
func _measure(team_a: Array, team_b: Array, plan_a: Dictionary, plan_b: Dictionary,
		orders: Dictionary, seed_: int) -> Dictionary:
	# "Your softest body dies first" is a claim about WHICH monster dies, so record the answer
	# before the fight starts — CON is what `Tactics.softest_body()` marks on.
	var softest = TacticsScript.softest_body(team_a)
	var softest_name: String = str(softest.species_name) if softest != null else ""
	var sim = BattleSimScript.new(team_a, team_b, seed_, plan_a, plan_b, orders)
	var res: Dictionary = sim.run()
	var first_dead := ""
	var dmg_by_target := {}
	var b_dmg := 0.0
	var b_dmg_early := 0.0
	var b_status := 0
	var b_hard := 0
	var b_heal := 0.0
	var b_buff := 0
	var a_dmg := 0.0
	var a_hits := 0
	var first_kill := -1.0
	var own_first_death := -1.0
	for e in res["log"]:
		var kind := str(e.get("kind", ""))
		if kind == "death" and str(e.get("side", "")) == "A" and first_kill < 0.0:
			first_kill = float(e.get("t", 0.0))
			first_dead = str(e.get("unit", ""))
		if kind == "death" and str(e.get("side", "")) == "B" and own_first_death < 0.0:
			own_first_death = float(e.get("t", 0.0))
		match kind:
			"hit":
				if str(e.get("attackerSide", "")) == "B":
					var d := float(e.get("dmg", 0))
					b_dmg += d
					if first_kill < 0.0:
						b_dmg_early += d
						var k: String = str(e.get("target", ""))
						dmg_by_target[k] = float(dmg_by_target.get(k, 0.0)) + d
				else:
					a_dmg += float(e.get("dmg", 0))
					a_hits += 1
			"status_apply":
				if str(e.get("side", "")) == "A":
					b_status += 1
					if HARD_CONTROL.has(str(e.get("status", ""))):
						b_hard += 1
			"heal":
				if str(e.get("side", "")) == "B":
					b_heal += float(e.get("amount", 0))
			"buff":
				if str(e.get("side", "")) == "B":
					b_buff += 1
	var top := 0.0
	for k in dmg_by_target:
		top = maxf(top, float(dmg_by_target[k]))
	return {
		"won": res["winner"] == "B",
		"duration": float(res["duration"]),
		"dps": b_dmg / maxf(0.1, float(res["duration"])),
		"concentration": top / maxf(1.0, b_dmg_early),
		"first_kill": first_kill if first_kill >= 0.0 else float(res["duration"]),
		"softest_first": 1.0 if (first_dead != "" and first_dead == softest_name) else 0.0,
		"held": own_first_death if own_first_death >= 0.0 else float(res["duration"]),
		"statuses": float(b_status),
		"hard_cc": float(b_hard),
		"healed": b_heal,
		"buffs": float(b_buff),
		"taken_per_hit": a_dmg / maxf(1.0, float(a_hits)),
	}


## The full table: every archetype fought against the SAME generic opposition, same seeds.
## `shaped` false is the null run — the archetype argument is dropped and every row should
## collapse, which is what proves the instrument responds to its input at all.
func _metric_table(shaped: bool) -> Dictionary:
	if shaped:
		print("── SIGNATURE (each archetype as team B vs the same generic team A) ──")
		print("  %-10s %5s %6s %6s %7s %6s %6s %6s %6s %6s %7s %6s" % [
			"archetype", "win%", "dur", "dps", "conc", "1stkl", "soft%", "held", "hardCC", "heal",
			"buffs", "tkn/hit"])
	var rows := {}
	for gid in _ids():
		var acc := {"won": 0.0, "duration": 0.0, "dps": 0.0, "concentration": 0.0, "first_kill": 0.0,
			"softest_first": 0.0, "held": 0.0, "statuses": 0.0, "hard_cc": 0.0, "healed": 0.0,
			"buffs": 0.0, "taken_per_hit": 0.0}
		for t in range(TRIALS):
			Roster.rng.seed = BASE_SEED + t
			var team_b: Array = Roster.make_rival_team(TEAM_SIZE, FILL, 1.0, gid if shaped else "")
			Roster.rng.seed = BASE_SEED + 90000 + t
			var team_a: Array = Roster.make_rival_team(TEAM_SIZE, FILL, 1.0, "")
			var plan_b: Dictionary = TacticsScript.team_plan_for_gameplan(gid, team_a) if shaped else {}
			var orders: Dictionary = TacticsScript.orders_for_gameplan(gid, team_b) if shaped else {}
			var m := _measure(team_a, team_b, {}, plan_b, orders, BASE_SEED + t * 31)
			for k in acc:
				acc[k] += (1.0 if m["won"] else 0.0) if k == "won" else float(m[k])
		for k in acc:
			acc[k] /= float(TRIALS)
		rows[gid] = acc
		if shaped:
			print("  %-10s %4.0f%% %6.1f %6.1f %7.3f %6.1f %5.0f%% %6.1f %6.2f %6.0f %7.2f %6.1f" % [
				gid, acc["won"] * 100.0, acc["duration"], acc["dps"], acc["concentration"],
				acc["first_kill"], acc["softest_first"] * 100.0, acc["held"], acc["hard_cc"],
				acc["healed"], acc["buffs"], acc["taken_per_hit"]])
	return rows


func _argmax(rows: Dictionary, key: String) -> String:
	var best := ""
	var best_v := -INF
	for gid in rows:
		if float(rows[gid][key]) > best_v:
			best_v = float(rows[gid][key])
			best = gid
	return best


func _argmin(rows: Dictionary, key: String) -> String:
	var best := ""
	var best_v := INF
	for gid in rows:
		if float(rows[gid][key]) < best_v:
			best_v = float(rows[gid][key])
			best = gid
	return best


## ⚠️ EACH ASSERTION IS THE ARCHETYPE'S OWN `read` LINE, RESTATED AS A MEASUREMENT. If one fails,
## the honest fix is to change the LINE (or the composition), never to loosen the check — an
## unverifiable read is exactly the thing this round exists to delete.
func _signature_assertions(rows: Dictionary) -> void:
	print("\n── THE READ, AS A MEASUREMENT ──")
	## ⚠️ HARD CONTROL, NOT "STATUSES". Measured on raw status count, the leader was ATTRITION —
	## Venomcraft's poison rides on damage moves, so a poison team lands more status events than a
	## control team ever will while taking nobody's turn away. The two archetypes' read lines
	## already say which is which ("poison and stall" vs "stunned, silenced"); the metric had to
	## learn the difference too.
	_check(_argmax(rows, "hard_cc") == "control",
		"control lands the most HARD control — stun/silence/fear (%s leads, %.2f/fight)" % [
			_argmax(rows, "hard_cc"), rows["control"]["hard_cc"]])
	_check(rows["attrition"]["healed"] > 0.0 and _argmax(rows, "healed") == "attrition",
		"attrition heals the most (%s leads, %.0f HP restored/fight)" % [
			_argmax(rows, "healed"), rows["attrition"]["healed"]])
	_check(_argmax(rows, "duration") == "attrition",
		"attrition drags the fight longest (%s leads at %.1fs)" % [
			_argmax(rows, "duration"), rows["attrition"]["duration"]])
	_check(_argmax(rows, "buffs") == "bulwark",
		"bulwark applies the most protective buffs (%s leads, %.2f/fight)" % [
			_argmax(rows, "buffs"), rows["bulwark"]["buffs"]])
	## ⚠️ "WILL NOT BREAK" IS A CLAIM ABOUT WHEN THE FIRST BODY FALLS, and it has to be measured
	## that way rather than as damage-taken-per-hit. Once `FILL_MULT` exists the archetypes no
	## longer stand at the same stat level, and per-hit mitigation moves with CON regardless of
	## kit — attrition (corrected UP to 0.80 fill) tied the wall at 24.0 vs 24.2 on that metric
	## while dying far sooner. Time to its own first death is the thing the read line promises.
	_check(_argmax(rows, "held") == "bulwark",
		"bulwark holds its line longest — first body down at %.1fs (%s leads)" % [
			rows["bulwark"]["held"], _argmax(rows, "held")])
	## ⚠️ TOP-SHARE ALONE CANNOT CARRY THE FOCUS-FIRE READ, AND THAT TOO WAS MEASURED. Even
	## restricted to the opening, the metric rewards whoever gets to the first kill in the fewest
	## exchanges — rushdown measured 0.903 against focus-fire's 0.708, because focus-fire's Volley
	## and Demagogue picks carry area moves that ignore the mark entirely. So the read line is
	## checked as the two things it actually promises: the kill comes FASTEST, and it lands on the
	## body the plan marked ("your softest body dies first"), not on whoever happened to be handy.
	_check(_argmin(rows, "first_kill") == "focusfire",
		"focus-fire takes the first kill fastest (%s leads at %.1fs)" % [
			_argmin(rows, "first_kill"), rows["focusfire"]["first_kill"]])
	_check(_argmax(rows, "softest_first") == "focusfire" and rows["focusfire"]["softest_first"] >= 0.5,
		"focus-fire kills the SOFTEST body first %.0f%% of the time (chance is 20%%; %s leads)" % [
			rows["focusfire"]["softest_first"] * 100.0, _argmax(rows, "softest_first")])
	_check(_argmin(rows, "concentration") == "zone",
		"zone spreads the opening flattest (%s lowest at %.3f top-share to first kill)" % [
			_argmin(rows, "concentration"), rows["zone"]["concentration"]])
	_check(_argmax(rows, "dps") == "rushdown",
		"rushdown deals damage fastest (%s leads at %.1f dmg/s)" % [
			_argmax(rows, "dps"), rows["rushdown"]["dps"]])


## ⚠️ BEWARE THE INSTRUMENT. Re-run the identical table with the archetype argument suppressed:
## every row is then the SAME generator and the signature spread must collapse. A probe whose
## numbers do not move when its input is removed is measuring nothing.
func _null_run(shaped_rows: Dictionary) -> void:
	print("\n── INSTRUMENT CHECK (same table, archetype argument suppressed) ──")
	var null_rows := _metric_table(false)
	var keys := ["statuses", "healed", "buffs", "concentration", "dps", "duration"]
	var moved := 0
	for k in keys:
		var s_spread := _spread(shaped_rows, k)
		var n_spread := _spread(null_rows, k)
		var verdict := "MOVES" if s_spread > n_spread * 2.0 + 0.0001 else "flat"
		print("  %-14s shaped spread %8.3f   null spread %8.3f   %s" % [k, s_spread, n_spread, verdict])
		if s_spread > n_spread * 2.0 + 0.0001:
			moved += 1
	_check(moved >= 5, "the instrument responds to its input on %d of %d axes" % [moved, keys.size()])


## Max-minus-min across the archetype rows for one metric, normalised by the mean so the axes are
## comparable — this is the number that must be large when shaped and ~0 when suppressed.
func _spread(rows: Dictionary, key: String) -> float:
	var lo := INF
	var hi := -INF
	var sum := 0.0
	for gid in rows:
		var v := float(rows[gid][key])
		lo = minf(lo, v)
		hi = maxf(hi, v)
		sum += v
	var mean: float = sum / float(rows.size())
	return (hi - lo) / maxf(0.001, absf(mean))


# ── 2b. STRENGTH: different in KIND must not mean different in POWER ─────────────────────────

## ⚠️ THIS IS THE CHECK THAT KEEPS THE LADDER'S SLOPE MEANING ANYTHING. `career.gd:field_fill()`
## is the ONE dial that says how hard a cup round is, and it is a fraction of the league ceiling.
## The moment archetypes exist, that dial is only honest if every archetype is worth the same at
## the same fill — otherwise "Silver's champion" is hard because it is a focus-fire team, not
## because Silver is the sixth rung, and the whole climb becomes noise.
##
## MEASURED BEFORE THE CORRECTION (24 fights each, fill 0.65, same generic opposition):
##   rushdown 96% | focusfire 83% | bulwark 67% | zone 67% | attrition 46% | control 29%
## — a 3.3x spread, wider than anything the ladder's own slope produces. `Tactics.FILL_MULT`
## corrects it; this asserts the correction held.
func _strength_band(rows: Dictionary) -> void:
	print("\n── STRENGTH BAND (every archetype must be worth the same at the same fill) ──")
	var lo := INF
	var hi := -INF
	for gid in rows:
		lo = minf(lo, float(rows[gid]["won"]))
		hi = maxf(hi, float(rows[gid]["won"]))
	print("  win rate vs the same generic team: %.0f%% .. %.0f%% (spread %.0f points)" % [
		lo * 100.0, hi * 100.0, (hi - lo) * 100.0])
	_check(hi - lo <= 0.35,
		"the six archetypes sit inside a 35-point band (%.0f points) — kind, not power" % ((hi - lo) * 100.0))
	_check(lo >= 0.2 and hi <= 0.9,
		"no archetype is a walkover or a wall on its own (%.0f%%..%.0f%%)" % [lo * 100.0, hi * 100.0])


## CALIBRATION RUN — `-- --calibrate`. Sweeps each archetype across a fill range against the same
## generic opposition and prints the fill at which it wins half its fights, which IS the multiplier
## baked into `Tactics.FILL_MULT`. Not part of the default battery: it is how the constants were
## derived, kept runnable so the next person can re-derive them instead of trusting them.
func _calibrate() -> void:
	const FILLS := [0.40, 0.50, 0.65, 0.80, 0.95]
	const CAL_TRIALS := 12
	print("── CALIBRATION: win rate vs a generic team at fill %.2f ──" % FILL)
	print("  %-10s %s" % ["archetype", " ".join(FILLS.map(func(f): return "%6.2f" % f))])
	for gid in _ids():
		var wins: Array = []
		for f in FILLS:
			var w := 0
			for t in range(CAL_TRIALS):
				Roster.rng.seed = BASE_SEED + t
				var team_b: Array = Roster.make_rival_team(TEAM_SIZE, float(f), 1.0, gid)
				Roster.rng.seed = BASE_SEED + 90000 + t
				var team_a: Array = Roster.make_rival_team(TEAM_SIZE, FILL, 1.0, "")
				var plan_b: Dictionary = TacticsScript.team_plan_for_gameplan(gid, team_a)
				var orders: Dictionary = TacticsScript.orders_for_gameplan(gid, team_b)
				if BattleSimScript.new(team_a, team_b, BASE_SEED + t * 31, {}, plan_b, orders).run()["winner"] == "B":
					w += 1
			wins.append(float(w) / float(CAL_TRIALS))
		# Linear interpolation for the fill that wins half — the multiplier is that over FILL.
		var half := -1.0
		for i in range(FILLS.size() - 1):
			if wins[i] <= 0.5 and wins[i + 1] >= 0.5 and wins[i + 1] > wins[i]:
				half = lerpf(float(FILLS[i]), float(FILLS[i + 1]),
					(0.5 - float(wins[i])) / (float(wins[i + 1]) - float(wins[i])))
				break
		print("  %-10s %s   -> 50%% at fill %s  (mult %s)" % [
			gid, " ".join(wins.map(func(w): return "%5.0f%%" % (w * 100.0))),
			"%.3f" % half if half > 0.0 else "  n/a",
			"%.3f" % (half / FILL) if half > 0.0 else " n/a"])


# ── 3. COUNTERPLAY: could the player have PREPARED for this? ─────────────────────────────────

## COUNTER TO ZONE — pure tactics, no roster change. `Tactics.aoe_coverage()` gates area damage on
## the DEFENDER's formation, so ordering LOOSE against a blanket team drops roughly half the side
## out of every area cast. Same teams, same seeds, one order changed: this is the cleanest
## demonstration in the build that a scouted read is worth acting on.
func _counter_formation() -> void:
	print("\n── COUNTER 1: formation LOOSE vs the zone champion (identical teams, one order) ──")
	var tight_wins := 0
	var loose_wins := 0
	var better := 0
	var worse := 0
	for t in range(TRIALS):
		Roster.rng.seed = BASE_SEED + t
		var team_b: Array = Roster.make_rival_team(TEAM_SIZE, FILL, 1.0, "zone")
		Roster.rng.seed = BASE_SEED + 90000 + t
		var team_a: Array = Roster.make_rival_team(TEAM_SIZE, FILL, 1.0, "")
		var plan_b: Dictionary = TacticsScript.team_plan_for_gameplan("zone", team_a)
		var orders: Dictionary = TacticsScript.orders_for_gameplan("zone", team_b)
		var tight = BattleSimScript.new(team_a, team_b, BASE_SEED + t * 31, {"formation": "tight"}, plan_b, orders).run()
		var loose = BattleSimScript.new(team_a, team_b, BASE_SEED + t * 31, {"formation": "loose"}, plan_b, orders).run()
		var tw: bool = tight["winner"] == "A"
		var lw: bool = loose["winner"] == "A"
		tight_wins += 1 if tw else 0
		loose_wins += 1 if lw else 0
		if lw and not tw:
			better += 1
		elif tw and not lw:
			worse += 1
	print("  player wins: TIGHT %d/%d   LOOSE %d/%d   (loose flipped %d fights to a win, %d to a loss)" % [
		tight_wins, TRIALS, loose_wins, TRIALS, better, worse])
	_check(loose_wins > tight_wins and better > worse,
		"the authored counter to zone measurably works (+%d wins, sign %d:%d)" % [
			loose_wins - tight_wins, better, worse])


## COUNTER MATRIX — every roster KIND against every rival KIND, and the residual that says which
## pairing is a real counter rather than a generally good team.
##
## ⚠️ "BURST BEATS ATTRITION MORE OFTEN THAN GENERIC DOES" IS NOT EVIDENCE, AND THE AUTHORED
## COUNTER FOR ATTRITION WAS WRONG BECAUSE OF EXACTLY THAT. Measured as a straight comparison the
## burst roster gained +8 wins against attrition and the check passed — until the same roster was
## run against the WALL and gained +13. Burst is simply a strong roster; the +8 was its main
## effect, not counterplay. What identifies a counter is the two-way RESIDUAL: how much better a
## pairing does than the row's own average and the column's own average predict.
##
##   residual(p, r) = win(p, r) − rowMean(p) − colMean(r) + grandMean
##
## ⚠️ EVERY PLAYER COMP IS BUILT AT THE SAME EFFECTIVE FILL. `FILL_MULT` is a difficulty correction
## for OPPOSITION; left in place on the player's own side it would field the burst comp at 0.50
## against the control comp's 0.77 and measure the handicap instead of the matchup.
const MATRIX_TRIALS := 12

func _counter_matrix() -> void:
	print("
── COUNTER MATRIX: which KIND of roster answers which KIND of team? ──")
	var comps: Array = ["generic"] + _ids()
	var win := {}
	for p in comps:
		win[p] = {}
		for r in _ids():
			win[p][r] = float(_matchup_wins(p, r)) / float(MATRIX_TRIALS)

	var grand := 0.0
	for p in comps:
		for r in _ids():
			grand += win[p][r]
	grand /= float(comps.size() * _ids().size())

	var row_mean := {}
	for p in comps:
		var t := 0.0
		for r in _ids():
			t += win[p][r]
		row_mean[p] = t / float(_ids().size())
	var col_mean := {}
	for r in _ids():
		var t2 := 0.0
		for p in comps:
			t2 += win[p][r]
		col_mean[r] = t2 / float(comps.size())

	print("  raw win%% (rows = player roster kind, columns = rival archetype)")
	print("  %-10s %s   avg" % ["", " ".join(_ids().map(func(r): return "%9s" % r))])
	for p in comps:
		print("  %-10s %s  %4.0f%%" % [p,
			" ".join(_ids().map(func(r): return "%8.0f%%" % (win[p][r] * 100.0))),
			row_mean[p] * 100.0])

	print("  residual, in win-rate points (positive = better than both averages predict)")
	print("  %-12s %s" % ["", " ".join(comps.map(func(p): return "%9s" % p))])
	var answers := {}
	for r in _ids():
		var best := ""
		var best_v := -INF
		var line: Array = []
		for p in comps:
			var resid: float = win[p][r] - row_mean[p] - col_mean[r] + grand
			line.append("%+8.0f" % (resid * 100.0))
			if p != "generic" and resid > best_v:
				best_v = resid
				best = p
		answers[r] = {"comp": best, "resid": best_v}
		print("  vs %-9s %s  -> %-10s %+.0f pts" % [
			r, " ".join(line), best, best_v * 100.0])

	var distinct := {}
	var positive := 0
	for r in _ids():
		distinct[answers[r]["comp"]] = true
		if float(answers[r]["resid"]) > 0.05:
			positive += 1
	_check(positive >= 4,
		"%d of %d archetypes have a roster answer worth preparing (residual > 5 pts)" % [positive, _ids().size()])
	_check(distinct.size() >= 3,
		"the answers are %d DIFFERENT kinds of roster — preparation is a choice, not one dominant comp" % distinct.size())


## Player-side fill that cancels the opposition correction, so two player comps of different KINDS
## still carry the same number of stat points into the fight.
func _player_fill(gid: String) -> float:
	return FILL / float(TacticsScript.FILL_MULT.get(gid, 1.0))


## Wins out of MATRIX_TRIALS for player comp `p` ("generic" = the unshaped generator) against rival
## archetype `r`, on shared seeds so every cell of the matrix fights the same fights.
func _matchup_wins(p: String, r: String) -> int:
	var wins := 0
	for t in range(MATRIX_TRIALS):
		Roster.rng.seed = BASE_SEED + t
		var team_b: Array = Roster.make_rival_team(TEAM_SIZE, FILL, 1.0, r)
		Roster.rng.seed = BASE_SEED + 90000 + t
		var team_a: Array = Roster.make_rival_team(TEAM_SIZE,
			FILL if p == "generic" else _player_fill(p), 1.0, "" if p == "generic" else p)
		var plan_a: Dictionary = {} if p == "generic" else TacticsScript.team_plan_for_gameplan(p, team_b)
		var plan_b: Dictionary = TacticsScript.team_plan_for_gameplan(r, team_a)
		var orders_b: Dictionary = TacticsScript.orders_for_gameplan(r, team_b)
		if BattleSimScript.new(team_a, team_b, BASE_SEED + t * 31, plan_a, plan_b, orders_b).run()["winner"] == "A":
			wins += 1
	return wins


# ── 4. THE LADDER: eleven rungs, and what each one asks ──────────────────────────────────────

func _ladder_reads() -> void:
	print("\n── THE ELEVEN RUNGS ──")
	var kinds := {}
	for i in range(Career.leagues.size()):
		var gid: String = TacticsScript.archetype_for_league(i)
		kinds[gid] = true
		print("  %-12s %-10s %s" % [
			Career.league_at(i).get("name", ""), gid, TacticsScript.champion_read(i)])
	_check(Career.leagues.size() == TacticsScript.ARCHETYPE_BY_LEAGUE.size(),
		"every league has an authored archetype (%d leagues, %d entries)" % [
			Career.leagues.size(), TacticsScript.ARCHETYPE_BY_LEAGUE.size()])
	_check(kinds.size() == _ids().size(),
		"the climb uses every archetype at least once (%d of %d)" % [kinds.size(), _ids().size()])
	# The first five rungs must each pose a NEW question — a ladder that repeats itself early is
	# the "no climb in it" failure the round brief opened with.
	var first_five := {}
	for i in range(5):
		first_five[TacticsScript.archetype_for_league(i)] = true
	_check(first_five.size() >= 4,
		"the opening five rungs pose %d distinct problems" % first_five.size())
