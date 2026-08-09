## THE READ, MEASURED — does the loop actually close?
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_read.tscn
##
## ⚠️ THIS PROBE EXISTS BECAUSE A GRADING SYSTEM CAN BE WRONG, AND A WRONG ✓ IS WORSE THAN NO ✓.
## `FUN_ADDITIONS.md` §1 names that risk explicitly: "a wrong or vague grade... teaches the player
## a false lesson, and in a game where preparation is the entire skill, teaching false lessons is
## the fatal failure." So the claims `report_ui.gd:build_read()` states and `grade_read()` answers
## are not shipped on the strength of reading nicely — they are run against REAL fights out of the
## REAL battle screen (`arena3d.tscn`, the new sim, the real committed plan) and reported as rates.
##
## It answers four questions, in order of how much they could embarrass us:
##
##   A. DOES EVERY ORDER PRODUCE A CLAIM? An order the player can set that generates no claim is
##      an order the report cannot answer — the loop is open for that axis.
##   B. DO THE CLAIMS DISCRIMINATE? A claim that reads HELD for every order set, or BROKE for
##      every order set, is not measuring the order — it is measuring the weather. Both are
##      reported per claim id.
##   C. DOES THE ORDER MOVE ITS OWN CLAIM? The load-bearing one: giving the order that a claim is
##      about must make that claim more likely to hold than not giving it. If it does not, either
##      the order does nothing (this project's signature failure) or the measurement is wrong.
##   D. IS THE TURNING POINT THE TURNING POINT? `report_ui.gd:_narrative()` has ONE hand-authored
##      detector and it names the FIRST DEATH. This measures, per fight, where that moment sits in
##      the fight and how far it is from the largest actual swing in the frame stream.
extends Node

const TacticsScript = preload("res://scripts/tactics.gd")
const ReadScript = preload("res://scripts/ui/report_ui.gd")
const ARENA_SCENE := "res://scenes/arena3d.tscn"

## Sliding window for the swing measurement, in sim seconds. Two seconds is roughly the ~2s
## half-life the sim's own threat ledger decays on (`sim.gd`: "~2s half-life at 10Hz"), so it is
## the engine's own idea of "recently".
const SWING_WINDOW_S := 2.0
const DT := 0.1

var _team_a: Array = []
var _team_b: Array = []
var _rows: Array = []            # one per fight: {band, label, graded, verdict, swing, conc_*}
var _controls: Array = []        # per band: the unordered fight's concentration on the same bodies
var _out: Array = []


func _line(s: String) -> void:
	_out.append(s)


## ⚠️ THE ORDER SETS ARE THE INDEPENDENT VARIABLE. Each pair is (label, plan-builder) — the
## builder gets the scouted rival roster so `manmark` can name a real body. `null` orders mean
## "the player set nothing", which is its own important case: it must produce the NO READ verdict
## rather than a confident tick on something they never chose.
func _order_sets() -> Array:
	return [
		{"label": "no orders", "plan": {}, "per": {}},
		{"label": "hunt casters, tight", "plan": {"targetPriority": "casters", "formation": "tight"}, "per": {}},
		{"label": "hunt casters, loose", "plan": {"targetPriority": "casters", "formation": "loose"}, "per": {}},
		{"label": "break the tank", "plan": {"targetPriority": "tanks", "formation": "tight"}, "per": {}},
		{"label": "man mark", "plan": {"targetPriority": "manmark", "formation": "tight"}, "per": {}},
		{"label": "cautious front, loose", "plan": {"formation": "loose"}, "per": {"temperament": "cautious"}},
		{"label": "dive the back line", "plan": {"formation": "tight"}, "per": {"positionalIntent": "dive"}},
	]


func _setup_state(want_size: int, a_fill: float) -> void:
	Career.reset_new_game()
	Roster.reset_to_empty()
	var idx := Career.league_index
	for i in range(Career.leagues.size()):
		if Career.team_size_for_league(i) >= want_size:
			idx = i
			break
	Career.league_index = idx
	CupRun.start(idx, 3)
	CupRun.current_round = 1
	var team_size: int = Career.team_size_for_league(idx)
	# The player's side is BUILT at the band's fill rather than taken from the starting roster —
	# the starting roster is untrained, which is not a band, it is a floor.
	for i2 in range(team_size):
		Roster.monsters.append(GameData.make_monster(Art.ROSTER[i2 % Art.ROSTER.size()], a_fill))
	_team_a = Roster.monsters.slice(0, mini(team_size, Roster.monsters.size()))
	_team_b = CupRun.current_rival_team()


## Boot the REAL battle screen through the REAL committed handoff — same entry state
## `tactics_ui.gd` leaves behind, including the stored `read`, so this measures the shipped path
## and not a reconstruction of it.
func _run_fight(entry: Dictionary) -> Dictionary:
	for m in _team_a + _team_b:
		m.reset_for_battle()
	var plan_a: Dictionary = (entry["plan"] as Dictionary).duplicate()
	var orders_a: Dictionary = {}
	for m in _team_a:
		orders_a[m] = (entry["per"] as Dictionary).duplicate()
	if str(plan_a.get("targetPriority", "")) == "manmark":
		plan_a["markedUnit"] = TacticsScript.softest_body(_team_b)

	var gp_id := TacticsScript.gameplan_for(_team_b.map(func(m): return m.species_name))
	TacticsScript.commit(plan_a, TacticsScript.team_plan_for_gameplan(gp_id, _team_a), orders_a,
		TacticsScript.orders_for_gameplan(gp_id, _team_b), {}, {}, _team_a, _team_b)
	var claims: Array = ReadScript.build_read(plan_a, orders_a, _team_a, _team_b)
	TacticsScript.committed["read"] = {"claims": claims, "gameplan": gp_id}

	var arena = load(ARENA_SCENE).instantiate()
	add_child(arena)
	for _i in 4000:
		await get_tree().process_frame
		if not (arena.get("result") as Dictionary).is_empty():
			break
	var res: Dictionary = arena.get("result")
	arena.queue_free()
	await get_tree().process_frame
	return {"result": res, "claims": claims, "plan": plan_a, "gameplan": gp_id}


## ⚠️ TWO STRENGTH BANDS, BECAUSE A GRADER THAT ONLY EVER SEES LOSSES IS NOT TESTED. The first
## pass of this probe ran a single band, the player lost all seven fights, and the target claim
## read PARTLY every time — which looked like a broken grader and was actually a fixed opponent.
## Every verdict branch has to be REACHABLE for the verdict table to mean anything, so the same
## seven order sets are fought against a weak rival and a strong one.
## ⚠️ THE BAND VARIES THE PLAYER, NOT THE RIVAL, AND THE FIRST VERSION OF THIS PROBE GOT THAT
## WRONG. It moved the rival's fill and left team A on the untrained starting roster — so the
## "weak rival" band still beat the player 7 times out of 7, and three of `read_verdict()`'s six
## branches were never reached at all. A verdict branch nobody has seen is untested copy.
## ⚠️ THREE SEEDS, BECAUSE ONE FIGHT IS NOT A MEASUREMENT. CLAUDE.md's balancing doctrine is
## explicit that changes were once made on 1-fight differences a paired A/B later showed did
## nothing. The first version of question C below read "the casters order moved concentration
## from 38% to 32%" off a single fight, which is noise wearing a minus sign. The fight seed is
## hashed off `CupRun.current_round` (`arena_3d.gd:_resolve_fight`), so moving it re-rolls the
## fight without touching either roster.
const SEEDS := [1, 2, 3]

const BANDS := [
	{"label": "player ahead (0.55 vs 0.20)", "a": 0.55, "b": 0.20},
	{"label": "player behind (0.20 vs 0.55)", "a": 0.20, "b": 0.55},
]


func _ready() -> void:
	_line("")
	_line("═══ THE READ, MEASURED — 5v5, real battle screen, real committed plans ═══")
	for band in BANDS:
		_setup_state(5, float((band as Dictionary)["a"]))
		_team_b = Roster.make_rival_team(5, float((band as Dictionary)["b"]))
		_line("")
		_line("╔══ BAND: %s — league %s, %d vs %d ══" % [
			str((band as Dictionary)["label"]), Career.current_league_name(), _team_a.size(), _team_b.size()])
		# The bodies the target orders will resolve to, captured ONCE per band so the unordered
		# control fight can be measured against exactly the same monsters (question C).
		var caster_marks: Array = ReadScript._read_target_monsters("casters", {}, _team_b)
		var tank_marks: Array = ReadScript._read_target_monsters("tanks", {}, _team_b)
		var ctl_casters: Array = []
		var ctl_tanks: Array = []

		for seed in SEEDS:
			for entry in _order_sets():
				CupRun.current_round = int(seed)
				var run: Dictionary = await _run_fight(entry)
				var res: Dictionary = run["result"]
				if res.is_empty():
					_line("  %-22s  FAILED TO RESOLVE" % str(entry["label"]))
					continue
				var graded: Array = ReadScript.grade_read(run["claims"], res, _team_a, _team_b)
				var verdict: Dictionary = ReadScript.read_verdict(graded, str(res.get("winner", "draw")), _team_a, _team_b)
				var cc: float = _concentration(res, caster_marks)
				var ct: float = _concentration(res, tank_marks)
				if str(entry["label"]) == "no orders":
					ctl_casters.append(cc)
					ctl_tanks.append(ct)
				_rows.append({
					"seed": int(seed),
					"band": str((band as Dictionary)["label"]),
					"label": str(entry["label"]), "graded": graded, "verdict": verdict,
					"winner": str(res.get("winner", "draw")), "duration": float(res.get("duration", 0.0)),
					"swing": _swing(res),
					"conc_casters": cc, "conc_tank": ct,
				})
		_controls.append({"band": str((band as Dictionary)["label"]),
			"casters": _mean(ctl_casters), "tanks": _mean(ctl_tanks), "n": ctl_casters.size()})


	_report()
	_dump()
	get_tree().quit(0)


## Share of team A's damage that landed on `marks`, over the whole fight. The SAME measurement
## `report_ui.gd:_grade_target()` makes — restated here as a bare number so an ordered fight can
## be compared against the unordered control on identical bodies.
func _concentration(res: Dictionary, marks: Array) -> float:
	var frames: Array = res.get("frames", [])
	var n_a: int = _team_a.size()
	var ids: Dictionary = {}
	for m in marks:
		var i: int = (_team_a + _team_b).find(m)
		if i >= 0:
			ids[i] = true
	var on := 0.0
	var total := 0.0
	for f in frames:
		for sh in (f.get("shots", []) as Array):
			var from_i: int = int((sh as Dictionary).get("fromId", -1))
			var to_i: int = int((sh as Dictionary).get("toId", -1))
			var d: float = float((sh as Dictionary).get("dmg", 0))
			if from_i < 0 or from_i >= n_a or to_i < n_a or d <= 0.0:
				continue
			total += d
			if ids.has(to_i):
				on += d
	return (on / total) if total > 0.0 else -1.0


# ═══ D. THE TURNING POINT ═════════════════════════════════════════════════════════════════════
#
# `report_ui.gd:_narrative()` names the FIRST DEATH. Is that the turning point a viewer would
# agree with? Measured against the frame stream two ways, because "turning point" has two honest
# readings and they can disagree:
#
#   HP SWING   — the largest change, over a 2s window, in (A's health share − B's health share).
#                This is "when did the fight tilt", and it is continuous.
#   LEAD LOCK  — the last moment the LIVING-BODY count differential changed sign, i.e. the last
#                point at which the fight was still level on numbers. This is "after which it was
#                never in doubt", which is what the narrative sentence actually claims
#                ("and the fight never came back level").
func _swing(res: Dictionary) -> Dictionary:
	var frames: Array = res.get("frames", [])
	if frames.is_empty():
		return {}
	var n_a: int = _team_a.size()
	var max_a := 0.0
	var max_b := 0.0
	for m in _team_a:
		max_a += float(m.max_hp)
	for m in _team_b:
		max_b += float(m.max_hp)
	if max_a <= 0.0 or max_b <= 0.0:
		return {}

	var diffs: Array = []           # health-share differential per frame
	var counts: Array = []          # living-body differential per frame
	var first_death := -1.0
	for f in frames:
		var ha := 0.0
		var hb := 0.0
		var ca := 0
		var cb := 0
		for u in (f.get("units", []) as Array):
			var uid: int = int((u as Dictionary).get("id", -1))
			var hp: float = float((u as Dictionary).get("hp", 0.0))
			var alive: bool = bool((u as Dictionary).get("alive", false))
			if uid < n_a:
				ha += hp
				ca += 1 if alive else 0
			else:
				hb += hp
				cb += 1 if alive else 0
		diffs.append(ha / max_a - hb / max_b)
		counts.append(ca - cb)
		if first_death < 0.0 and (ca < n_a or cb < (_team_b.size())):
			first_death = float(f.get("t", 0.0))

	var w: int = maxi(1, int(round(SWING_WINDOW_S / DT)))
	var best := 0.0
	var best_t := 0.0
	for i in range(w, diffs.size()):
		var d: float = absf(float(diffs[i]) - float(diffs[i - w]))
		if d > best:
			best = d
			best_t = float((frames[i] as Dictionary).get("t", 0.0))

	# LEAD LOCK — the last frame at which the body-count differential was not yet at its final sign.
	var final_sign: int = signi(int(counts[counts.size() - 1]))
	var lock_t := 0.0
	for i in range(counts.size()):
		if signi(int(counts[i])) != final_sign:
			lock_t = float((frames[i] as Dictionary).get("t", 0.0))
	var dur: float = float((frames[frames.size() - 1] as Dictionary).get("t", 0.0))
	return {
		"first_death": first_death, "swing_t": best_t, "swing_mag": best,
		"lock_t": lock_t, "duration": dur,
	}


# ═══ THE REPORT ═══════════════════════════════════════════════════════════════════════════════

func _report() -> void:
	_line("")
	_line("── A/B. WHAT EACH ORDER SET CLAIMED, AND HOW IT GRADED ──")
	_line("  (the per-fight listing shows seed 1 only; the rates below are over all %d seeds)" % SEEDS.size())
	var seen_band := ""
	for r in _rows:
		var row: Dictionary = r
		if int(row["seed"]) != int(SEEDS[0]):
			continue
		if str(row["band"]) != seen_band:
			seen_band = str(row["band"])
			_line("")
			_line("  ══ %s ══" % seen_band)
		_line("")
		_line("  %s   [%s in %.1fs]   → %s" % [
			str(row["label"]).to_upper(), "WON" if str(row["winner"]) == "A" else "LOST",
			float(row["duration"]), str((row["verdict"] as Dictionary).get("headline", ""))])
		_line("      %s" % str((row["verdict"] as Dictionary).get("sub", "")))
		for c in (row["graded"] as Array):
			var cl: Dictionary = c
			_line("      [%-9s] %-8s %s" % [str(cl.get("id", "")), str(cl.get("verdict", "")).to_upper(), str(cl.get("claim", ""))])
			_line("                            %s" % str(cl.get("evidence", "")))

	# ── B. discrimination ──
	_line("")
	_line("── B. DO THE CLAIMS DISCRIMINATE? (a claim with one verdict everywhere measures nothing) ──")
	var by_id: Dictionary = {}
	for r2 in _rows:
		for c2 in ((r2 as Dictionary)["graded"] as Array):
			var cl2: Dictionary = c2
			var k := str(cl2.get("id", ""))
			if not by_id.has(k):
				by_id[k] = {}
			var v := str(cl2.get("verdict", ""))
			(by_id[k] as Dictionary)[v] = int((by_id[k] as Dictionary).get(v, 0)) + 1
	for k2 in by_id:
		var tally: Dictionary = by_id[k2]
		var parts: Array = []
		for v2 in tally:
			parts.append("%s×%d" % [str(v2), int(tally[v2])])
		var flat: String = "  ⚠ ONE VERDICT ONLY — not discriminating" if tally.size() == 1 else ""
		_line("  %-9s  %s%s" % [str(k2), ", ".join(parts), flat])

	# ── VERDICT COVERAGE — every branch of read_verdict() must be reachable ──
	_line("")
	_line("── VERDICT BRANCHES REACHED (an unreachable branch is untested copy) ──")
	var heads: Dictionary = {}
	for r5 in _rows:
		var h := str(((r5 as Dictionary)["verdict"] as Dictionary).get("headline", ""))
		heads[h] = int(heads.get(h, 0)) + 1
	for h2 in heads:
		_line("  ×%d  %s" % [int(heads[h2]), str(h2)])

	# ── C. does giving the order move its own claim? ──
	_line("")
	_line("── C. DOES THE ORDER MOVE ITS OWN CLAIM? (mean share of your damage onto the SAME bodies) ──")
	_line("  %-28s %-22s %13s %10s" % ["band", "fight", "onto casters", "onto tank"])
	for ctl in _controls:
		var cd: Dictionary = ctl
		_line("  %-28s %-22s %12.0f%% %9.0f%%" % [str(cd["band"]), "NO ORDERS (control)",
			float(cd.get("casters", -1.0)) * 100.0, float(cd.get("tanks", -1.0)) * 100.0])
		for want in ["hunt casters, tight", "break the tank"]:
			var cs: Array = []
			var ts: Array = []
			for r3 in _rows:
				var row3: Dictionary = r3
				if str(row3["band"]) == str(cd["band"]) and str(row3["label"]) == want:
					cs.append(float(row3["conc_casters"]))
					ts.append(float(row3["conc_tank"]))
			if cs.is_empty():
				continue
			_line("  %-28s %-22s %12.0f%% %9.0f%%   (n=%d, spread %.0f-%.0f%%)" % ["", want,
				_mean(cs) * 100.0, _mean(ts) * 100.0, cs.size(),
				(cs.min() if want.begins_with("hunt") else ts.min()) * 100.0,
				(cs.max() if want.begins_with("hunt") else ts.max()) * 100.0])

	# ── D. the turning point ──
	_line("")
	_line("── D. IS THE TURNING POINT THE TURNING POINT? ──")
	_line("  report_ui:_narrative() names the FIRST DEATH. Measured against the frame stream:")
	_line("  %-24s %-22s %7s %7s %7s %7s %7s" % ["band", "fight", "dur", "1stdth", "swing", "lock", "gap"])
	var gaps: Array = []
	var lock_gaps: Array = []
	var frac_death: Array = []
	for r4 in _rows:
		var sw: Dictionary = (r4 as Dictionary)["swing"]
		if sw.is_empty():
			continue
		if int((r4 as Dictionary)["seed"]) != int(SEEDS[0]):
			# still counted in the means below, just not printed row by row
			gaps.append(absf(float(sw["swing_t"]) - float(sw["first_death"])))
			lock_gaps.append(absf(float(sw["lock_t"]) - float(sw["first_death"])))
			if float(sw["duration"]) > 0.0:
				frac_death.append(float(sw["first_death"]) / float(sw["duration"]))
			continue
		var gap: float = absf(float(sw["swing_t"]) - float(sw["first_death"]))
		gaps.append(gap)
		lock_gaps.append(absf(float(sw["lock_t"]) - float(sw["first_death"])))
		if float(sw["duration"]) > 0.0:
			frac_death.append(float(sw["first_death"]) / float(sw["duration"]))
		_line("  %-24s %-22s %6.1fs %6.1fs %6.1fs %6.1fs %6.1fs" % [
			str((r4 as Dictionary)["band"]), str((r4 as Dictionary)["label"]), float(sw["duration"]),
			float(sw["first_death"]), float(sw["swing_t"]), float(sw["lock_t"]), gap])
	if not gaps.is_empty():
		_line("")
		_line("  mean gap, named moment vs largest 2s HP swing : %.1fs" % _mean(gaps))
		_line("  mean gap, named moment vs LEAD LOCK           : %.1fs" % _mean(lock_gaps))
		_line("  the first death lands at %.0f%% of the fight on average" % (_mean(frac_death) * 100.0))


func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += float(v)
	return t / float(a.size())


func _dump() -> void:
	for s in _out:
		print(s)
