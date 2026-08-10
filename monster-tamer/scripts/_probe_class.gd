## THE CLASS PROBE — is ASSIGNABLE CLASS a decision worth building?
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_class.tscn -- --all
##   sections:  --gym     (seconds, exact, no fights)   what do PER-CLASS CAPS do to a stat vector?
##              --fight   (~1-3 min)                    what does the DECISION buy, and cost?
##      flags:  --weeks N   training weeks per body (default 240)
##              --salts N   paired fight repeats per rung (default 8)
##
## ⚠️ THIS SUBCLASSES `_probe_shape.gd` (which subclasses `_probe_career_arc.gd`). A second
## autopilot is this project's most expensive recurring failure. Everything here reuses the
## shipped training tick (`week.gd:apply_activity`), the shipped kit draft
## (`monster_instance.gd:assign_moveset`), the shipped rivals (`Career.make_league_rivals`) and
## the shipped fight (`battle_sim.gd`). The ONLY new machinery is (a) a per-class stat cap applied
## brain-side and (b) a STORED class that the kit is drawn from.
##
## ─── WHAT THIS EXISTS TO ANSWER ──────────────────────────────────────────────────────────────
##
## `docs/SHAPE_DIAGNOSIS.md` measured a 14x dynamic range on kit ALIGNMENT (4% mismatched -> 56%
## matched) and concluded the player's hand is nowhere near the lever, because class is derived
## from stats every week and the kit is redrawn from class for free. `docs/CLASS_REWORK.md`
## proposes putting the lever in the player's hand.
##
## ⚠️ BUT THE 14x IS NOT AUTOMATICALLY PURCHASABLE BY ASSIGNING THE CLASS, AND THAT IS THE FIRST
## THING THIS PROBE HAD TO CHECK RATHER THAN ASSUME. Derivation makes the kit follow the STATS;
## assignment makes the kit follow the CHOICE. Either way stats and kit agree **as soon as the
## player trains toward the class they picked**. Misalignment — arm D, the 4% — requires the stat
## vector and the kit to DISAGREE, which under assignment happens only while a player is in
## TRANSIT toward a class they do not yet have the stats for. So the honest questions are:
##
##   Q1  do per-class caps DELETE the flat generalist?  (`--gym`, exact)
##   Q2  what does committing to the RIGHT class buy in the fight, per training week spent?
##   Q3  what does committing to the WRONG class cost — the trap the decision needs to have?
##   Q4  how big is the TRANSIT penalty — a kit drawn from a class the body is not yet?
##
## Q1 is the one that matters most and it is the cheapest. `docs/SHAPE_DIAGNOSIS.md`'s standing
## negative is that the naive "train the lowest stat" policy completes the game at the same 87.5%
## as a competent one. That policy is a points-maximiser that builds a flat generalist. If
## per-class caps make it ILLEGAL, the skill gap the vision needs appears without any new
## content — and if they do not, assignable classes will not produce one either.
extends "res://scripts/_probe_shape.gd"

# =============================================================================
# THE PER-CLASS CAP — the thing under test
# =============================================================================
## ⚠️ TWO TIER SETS, AND THE DIFFERENCE BETWEEN THEM IS A DESIGN DECISION, NOT A TUNING KNOB.
##
## TIGHT is `docs/CLASS_REWORK.md` §4.1 exactly as written: primary 1.00 / secondary 0.90 /
## other 0.70, multiplying `statCapFor`. It was authored 2026-08-03.
##
## ⚠️ TIGHT WOULD PARTLY UNDO ROUND 14. `week.gd:stat_ceiling` (shipped 2026-08-09) already lets a
## committed body push ONE stat to `SPIKE_HEADROOM 1.35 x nominal` out of a shared `6 x nominal`
## budget — that change is what took a real specialist from 4/24 careers to 26/32, i.e. from a
## trap to a build. A primary tier of 1.00 hands that headroom straight back.
##
## ARCHETYPE re-bases the tiers on numbers the game already ships: 1.35 and 1.15 are
## `roster.gd:SHAPE_PRIMARY` / `SHAPE_SECONDARY`, the exact primary/secondary weights of the
## archetype vector every rival is built from. So a class's ceiling is precisely the shape the
## ladder already fields, and the restriction lands where CLASS_REWORK actually wants it — on the
## four OFF-class stats. Total budget: 1.35 + 1.15 + 4 x 0.70 = 5.30 against week.gd's 6.00, so it
## tightens the total by 12% as well, which is the anti-generalisation the rework is for.
const CAP_TIERS := {
	"TIGHT":     {"primary": 1.00, "secondary": 0.90, "other": 0.70},
	"ARCHETYPE": {"primary": 1.35, "secondary": 1.15, "other": 0.70},
}

## The assigned class of the body currently being trained ("" = none, today's behaviour).
var c_assigned := ""
## Which tier set is live ("" = per-class caps OFF).
var c_tiers := ""
## Which brain the capped arms use underneath the cap: "flat" (naive) or "commit" (train the
## assigned class's pair).
var c_under := "flat"
## The class the KIT is drawn from. Normally the same as `c_assigned` — they differ only in the
## TRANSIT arm, which is the whole point of that arm.
var c_kit := ""

var _cok := true


func _ready() -> void:
	_tree = get_tree()
	print("=== CLASS PROBE — is assignable class a decision worth building? ===\n")
	var args: Array = OS.get_cmdline_user_args()
	args.append_array(OS.get_cmdline_args())
	var all: bool = "--all" in args
	if all or "--gym" in args:
		_run_cap_gym()
	if all or "--fight" in args:
		_run_decision()
	print("\n=== class probe: %s ===" % ("OK" if _cok else "INSTRUMENT BROKEN"))
	_tree.quit(0 if _cok else 1)


## The class pair of the assigned class, or [] when unassigned.
func _assigned_pair() -> Array:
	if c_assigned == "":
		return []
	return Roster._class_pair(c_assigned)


## The per-class ceiling for one stat, in the same units `week.gd:stat_cap_for` returns.
## ⚠️ APPLIED BRAIN-SIDE, NOT IN THE TICK. `week.gd` is another workstream's file. A brain that
## refuses to plan a drill on a capped stat is STRICTLY MORE GENEROUS than a tick that clamps the
## roll to zero — the week is spent somewhere legal instead of being wasted. So every capped arm
## below is an UPPER bound on what the capped player achieves, and any negative finding
## ("the caps did not bite") is therefore stronger, not weaker, than a real implementation.
func _class_cap(stat: String, nominal: float) -> float:
	if c_tiers == "" or c_assigned == "":
		return nominal
	var t: Dictionary = CAP_TIERS[c_tiers]
	var pair: Array = _assigned_pair()
	if pair.size() >= 1 and stat == str(pair[0]):
		return nominal * float(t["primary"])
	if pair.size() >= 2 and stat == str(pair[1]):
		return nominal * float(t["secondary"])
	return nominal * float(t["other"])


## ⚠️ THE ONLY OVERRIDE. `_probe_shape.gd` overrides this to switch training brains; this file
## wraps that with the per-class cap and the commit brain. Everything else — barn, recruits, cups,
## the fight — is untouched.
func _drill_plan_greedy(mi, league_cap: float) -> Dictionary:
	if c_tiers == "" and c_under != "commit":
		return super(mi, league_cap)
	var nominal: float = WeekLib.stat_cap_for(mi, league_cap)
	var pair: Array = _assigned_pair()
	var legal: Array = []
	for s in Classify.STATS:
		if float(mi.stats.get(s, 0.0)) < _class_cap(s, nominal) - 0.5:
			legal.append(s)
	if legal.is_empty():
		return {"mode": "idle", "id": ""}
	var want := ""
	if c_under == "commit" and pair.size() >= 2:
		# Drive the assigned pair, primary-first at the archetype's own 1.35 : 1.15 ratio; fall
		# through to whatever is still legal once the pair is capped. Same rule as
		# `_probe_shape.gd:_drill_plan_spike`, keyed to the ASSIGNED class rather than to aptitude.
		var pri: String = str(pair[0])
		var sec: String = str(pair[1])
		var pv: float = float(mi.stats.get(pri, 0.0))
		var sv: float = float(mi.stats.get(sec, 0.0))
		if legal.has(pri) and (not legal.has(sec) or pv < sv * (Roster.SHAPE_PRIMARY / Roster.SHAPE_SECONDARY)):
			want = pri
		elif legal.has(sec):
			want = sec
		elif legal.has(pri):
			want = pri
	if want == "":
		# The naive rule, restricted to legal stats: biggest drill on the LOWEST one.
		want = str(legal[0])
		for s in legal:
			if float(mi.stats.get(s, 0.0)) < float(mi.stats.get(want, 0.0)):
				want = str(s)
	if mi.stamina >= WeekLib.EXTREME_DRILL_STAMINA:
		return {"mode": "train", "id": "x" + want.to_lower()}
	return {"mode": "rest", "id": ""}


# =============================================================================
# 1. THE CAP GYM — do per-class caps delete the flat generalist? (exact, no fights)
# =============================================================================
const CGYM_SPECIES := 10
const CGYM_CAP := 1100.0          ## Tamers Apex

func _run_cap_gym() -> void:
	var weeks: int = _arg_int("--weeks", 336)
	print("─── 1. THE CAP GYM — what do per-class caps do to a body? (%d weeks) ───" % weeks)
	print("  ⚠️ Q1: the naive brain trains the LOWEST stat, which is a points-maximiser that")
	print("     builds a flat generalist and still completes the game at 87.5%. If per-class caps")
	print("     make that policy ILLEGAL, the skill gap appears for free.")
	print("  ⚠️ SWEPT ACROSS THE LADDER'S OWN CAPS, because a ceiling only exists where a career")
	print("     can reach it. `_probe_training.gd` §1 measures a full career banking ~4,450 points")
	print("     against a 6,600-point budget at the Apex cap — so a cap set as a FRACTION of the")
	print("     Apex ceiling may never be touched by any player at all.\n")
	Career.reset_new_game()
	Roster.reset_to_empty()
	for idx in [4, 6, 8, 10]:
		_cap_gym_at(idx, Career.stat_cap_for_league(idx), weeks)
	print("")
	print("  spread = (max-min)/mean, the arc's own `_shape_spread`. A `_shape_to_class` rival —")
	print("  the body every rival on the ladder is built as — sits at 0.475. The naive player")
	print("  measures 0.03 in this gym and 0.12 over a career.")


func _cap_gym_at(idx: int, cap: float, weeks: int) -> void:
	print("  ── %s · cap %.0f · off-class ceiling %.0f ──" % [
		Career.league_at(idx).get("name", "?"), cap, cap * 0.70])
	print("  %-26s  %8s  %8s  %7s  %7s  %7s  %s" % [
		"arm", "total", "vs base", "spread", "top", "6th", "class@exit"])
	var base := 0.0
	for arm in [
			["today: naive, no caps",      "flat",   "",          false],
			["today: apt, no caps",        "apt",    "",          false],
			["naive + TIGHT caps",         "flat",   "TIGHT",     true],
			["naive + ARCHETYPE caps",     "flat",   "ARCHETYPE", true],
			["commit + TIGHT caps",        "commit", "TIGHT",     true],
			["commit + ARCHETYPE caps",    "commit", "ARCHETYPE", true],
			["commit, no caps (=spike)",   "commit", "",          true],
		]:
		var r: Dictionary = _cgym_arm(str(arm[0]), str(arm[1]), str(arm[2]), bool(arm[3]), weeks, cap)
		if base == 0.0:
			base = float(r["total"])
		print("  %-26s  %8.0f  %8s  %7.2f  %7.0f  %7.0f  %s" % [
			str(arm[0]), float(r["total"]),
			"—" if float(r["total"]) == base else "%+.1f%%" % (100.0 * (float(r["total"]) / base - 1.0)),
			float(r["spread"]), float(r["top"]), float(r["low"]), str(r["classes"])])


func _cgym_arm(_label: String, under: String, tiers: String, assign: bool, weeks: int,
		cap: float = CGYM_CAP) -> Dictionary:
	var tot := 0.0
	var spread := 0.0
	var top := 0.0
	var low := 0.0
	var classes := {}
	for si in range(CGYM_SPECIES):
		var r: Dictionary = _cgym_one(under, tiers, assign, si, weeks, cap)
		tot += float(r["total"])
		spread += float(r["spread"])
		top += float(r["top"])
		low += float(r["low"])
		classes[str(r["class"])] = int(classes.get(str(r["class"]), 0)) + 1
	var n := float(CGYM_SPECIES)
	return {"total": tot / n, "spread": spread / n, "top": top / n, "low": low / n,
		"classes": "%d distinct" % classes.size()}


## Train ONE body for `weeks` under one arm and report its stat vector. No fights, exact.
func _cgym_one(under: String, tiers: String, assign: bool, si: int, weeks: int,
		cap: float) -> Dictionary:
	var mi = _fresh_body(si, cap)
	_set_arm(mi, under, tiers, assign)
	_train(mi, weeks, cap)
	_clear_arm()
	return _vector_of(mi)


## A fresh body, seeded identically across arms so an arm-to-arm difference is only the arm.
func _fresh_body(si: int, _cap: float):
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + si * 977
	var mi = GameData.make_monster(Art.ROSTER[(si * 7) % Art.ROSTER.size()], 0.0, rng)
	mi.id = "class-%d" % si
	mi.happiness = 8
	return mi


## Point the probe's brain at one arm for this body.
## ⚠️ THE ASSIGNED CLASS IS CHOSEN OFF APTITUDE, WHICH IS THE ONLY INFORMATION A PLAYER HAS AT
## THE MOMENT OF CHOOSING. `_probe_shape.gd:_trade_pair` is that rule and it is reused verbatim,
## so "picking right" here means exactly what it means there.
func _set_arm(mi, under: String, tiers: String, assign: bool, wrong: bool = false) -> void:
	c_under = under
	c_tiers = tiers
	s_brain = under if under in ["flat", "apt"] else "flat"
	c_assigned = ""
	if assign:
		var pair: Array = _trade_pair(mi)
		var want: String = _class_of_pair(pair)
		if wrong:
			want = _other_class(want)
		c_assigned = want
	c_kit = c_assigned


func _clear_arm() -> void:
	c_assigned = ""
	c_kit = ""
	c_tiers = ""
	c_under = "flat"
	s_brain = "flat"


## The class whose [primary, secondary] is this pair, or the nearest one sharing the primary.
func _class_of_pair(pair: Array) -> String:
	if pair.size() < 2:
		return "Generalist"
	for c in GameData.classes:
		if str(c.get("primary", "")) == str(pair[0]) and str(c.get("secondary", "")) == str(pair[1]):
			return str(c.get("name", ""))
	for c in GameData.classes:
		if str(c.get("primary", "")) == str(pair[0]):
			return str(c.get("name", ""))
	return "Generalist"


## `weeks` of the SHIPPED training tick. Fed and happy every week — this measures the training
## economy, not the food economy.
func _train(mi, weeks: int, cap: float) -> void:
	for w in range(weeks):
		mi.happiness = 8
		mi.fed_this_week = true
		var plan: Dictionary = _drill_plan_greedy(mi, cap)
		if str(plan["mode"]) == "train":
			WeekLib.apply_activity(mi, {"kind": "train", "drillId": str(plan["id"])}, 0, cap,
				"Tamers Apex")
		else:
			WeekLib.apply_activity(mi, {"kind": "rest"}, 0, cap, "Tamers Apex")
		# ⚠️ THE STORED CLASS HAS TO BE RE-STAMPED EVERY WEEK, AND THAT IS THE FINDING, NOT A
		# WORKAROUND. `week.gd:apply_activity` ends with `recompute_class()` — it overwrites
		# `class_name_` from the stats unconditionally, every single week, on the shipped path.
		# A stored player choice put anywhere near this loop is erased before the player sees it.
		if c_assigned != "":
			mi.class_name_ = c_assigned
			mi.role = Classify.role_of_class(c_assigned)
	mi.recompute_pools()


func _vector_of(mi) -> Dictionary:
	var hi := -INF
	var lo := INF
	var sum := 0.0
	for s in Classify.STATS:
		var v: float = float(mi.stats.get(s, 0.0))
		hi = maxf(hi, v)
		lo = minf(lo, v)
		sum += v
	var mean: float = sum / float(Classify.STATS.size())
	var cls: String = str(mi.class_name_)
	if c_assigned == "":
		mi.recompute_class()
		cls = str(mi.class_name_)
	return {"total": sum, "spread": (hi - lo) / maxf(1.0, mean), "top": hi, "low": lo,
		"class": cls}


# =============================================================================
# 2. THE DECISION — what does picking right buy, and picking wrong cost?
# =============================================================================
## Every arm trains for the SAME number of weeks — weeks are what a player actually spends, and
## `docs/SHAPE_DIAGNOSIS.md` §3 is emphatic that a comparison at a constant stat TOTAL flatters
## the specialist by giving away the points its shape costs.
##
##   AUTO       today's game: naive brain, no caps, class DERIVED at exit, kit drawn from it.
##   AUTO-APT   today's competent player: aptitude brain, no caps, class derived.
##   RIGHT      class ASSIGNED to the aptitude-best trade, trained into it, caps on, kit from the
##              assigned class. The decision, made well.
##   WRONG      class assigned to a class sharing NEITHER stat with the aptitude-best trade, and
##              then honestly trained into. Stats and kit AGREE; the only cost is that the body
##              is fighting its own species aptitudes. This is what "picking wrong" actually is.
##   TRANSIT    ⚠️ THE REAL TRAP. Class assigned to the wrong class — kit drawn from it — while
##              the player keeps training their aptitude pair. Stats and kit DISAGREE. This is
##              `docs/SHAPE_DIAGNOSIS.md` arm D (0.07x) reached by a route a player can actually
##              take, and it is the only arm where the 14x is on the table.
##   NEIGHBOUR  ⚠️ THE ARM THAT DECIDES WHETHER THIS IS A DECISION AT ALL. `CLASS_REWORK.md` §2.2's
##              gate deliberately offers SEVERAL classes at once (its own worked example opens
##              Warrior, Skirmisher and Rogue on one body). So the choice a player actually makes
##              is not best-vs-worst, it is between the ADJACENT classes the gate put on the menu.
##              This arm assigns a class sharing the primary stat but not the secondary — the
##              nearest thing on that menu — and trains into it. If NEIGHBOUR ≈ RIGHT, the menu is
##              flat and "assign a class" is a tax on not being stupid, not a decision.
const DEC_RUNGS := [4, 6, 8, 10]
const DEC_ARMS := ["AUTO", "AUTO-APT", "RIGHT", "NEIGHBOUR", "WRONG", "TRANSIT"]

func _run_decision() -> void:
	var salts: int = _arg_int("--salts", 8)
	print("\n─── 2. THE DECISION — %d paired salts per rung ───" % salts)
	print("  identical rivals and identical battle seeds in every arm; the only difference is what")
	print("  the player chose to do with the SAME number of weeks.")
	print("  ⚠️ THE WEEK BUDGET IS CALIBRATED PER RUNG so the AUTO arm — today's naive player —")
	print("     lands on `Career.expected_climber_fill`, the ladder's own reference player. Handing")
	print("     every arm a flat 240 weeks put every arm at 100% and measured nothing but a")
	print("     ceiling.\n")
	Career.reset_new_game()
	Roster.reset_to_empty()
	var wins := {}
	var totals := {}
	var n_fights := {}
	for a in DEC_ARMS:
		wins[a] = 0
		totals[a] = 0.0
		n_fights[a] = 0
	var head := "  %-14s %5s %5s" % ["league", "cap", "wks"]
	for a in DEC_ARMS:
		head += "  %-11s" % a
	print(head)
	for idx in DEC_RUNGS:
		Career.league_index = idx
		var size: int = Career.team_size_for_league(idx)
		var cap: float = Career.stat_cap_for_league(idx)
		var rounds: int = maxi(1, Career.rival_count_for_league(idx))
		var weeks: int = _weeks_for_fill(cap, Career.expected_climber_fill(idx))
		var row := {}
		var nn := 0
		for a in DEC_ARMS:
			row[a] = 0
		var teams := {}
		for a in DEC_ARMS:
			teams[a] = _dec_team(a, size, cap, weeks, idx)
			for mi in teams[a]:
				for s in Classify.STATS:
					totals[a] += float(mi.stats.get(s, 0.0))
		for salt in range(salts):
			for r in range(rounds):
				var rf: float = Career.field_fill(r, rounds, idx)
				var rseed: int = abs(880000 + idx * 7919 + salt * 131 + r * 17) % 2147483647
				var bseed: int = 6160 + idx * 313 + salt * 29 + r
				for a in DEC_ARMS:
					if _dec_fight(teams[a], size, idx, rf, rseed, bseed):
						row[a] += 1
					n_fights[a] += 1
				nn += 1
		for a in DEC_ARMS:
			wins[a] = int(wins[a]) + int(row[a])
		var line := "  %-14s %5.0f %5d" % [Career.league_at(idx).get("name", "?"), cap, weeks]
		for a in DEC_ARMS:
			line += "  %-11s" % _frac(int(row[a]), nn)
		print(line)
	var tn: int = int(n_fights["AUTO"])
	var tot := "  %-14s %5s %5s" % ["ALL", "", ""]
	for a in DEC_ARMS:
		tot += "  %-11s" % _frac(int(wins[a]), tn)
	print(tot)
	print("")
	print("  stat total banked in the SAME weeks (the price of each choice):")
	for a in DEC_ARMS:
		print("    %-10s %8.0f   %s" % [a, float(totals[a]),
			"—" if a == "AUTO" else "%+.1f%% vs AUTO" % (
				100.0 * (float(totals[a]) / maxf(1.0, float(totals["AUTO"])) - 1.0))])
	print("")
	var auto: float = maxf(1.0, float(wins["AUTO"]))
	var apt: float = maxf(1.0, float(wins["AUTO-APT"]))
	var right: float = maxf(1.0, float(wins["RIGHT"]))
	print("  AUTO     -> AUTO-APT  = %.2fx  <- TODAY's competent player. No new mechanism at all."
		% (apt / auto))
	print("  AUTO     -> RIGHT     = %.2fx  <- the assigned build vs today's naive one" % (right / auto))
	print("  AUTO-APT -> RIGHT     = %.2fx  <- ⚠️ THE ONLY NUMBER THAT PRICES THE FEATURE: what"
		% (right / apt))
	print("                                    assignment adds ON TOP of what the auto-redraft")
	print("                                    already gives a competent player for free.")
	print("  RIGHT -> NEIGHBOUR    = %.2fx  <- the spread ACROSS the menu the gate offers"
		% (float(wins["NEIGHBOUR"]) / right))
	print("  RIGHT -> WRONG        = %.2fx  <- committing to a class the body fights, trained honestly"
		% (float(wins["WRONG"]) / right))
	print("  RIGHT -> TRANSIT      = %.2fx  <- reassignment on the day it is made: kit from a class"
		% (float(wins["TRANSIT"]) / right))
	print("                                    the body is not. The only place the 14x lives.")


## Build one arm's team: `size` bodies, each trained for `weeks` under the arm's rules, then given
## a kit. The kit is the whole point — see the per-arm note.
func _dec_team(arm: String, size: int, cap: float, weeks: int, salt: int) -> Array:
	var team: Array = []
	var krng := RandomNumberGenerator.new()
	krng.seed = 3300 + salt
	for i in range(size):
		var mi = _fresh_body(salt * 13 + i, cap)
		mi.id = "dec-%s-%d-%d" % [arm, salt, i]
		var pair: Array = _trade_pair(mi)
		var right: String = _class_of_pair(pair)
		match arm:
			"AUTO":
				_set_arm(mi, "flat", "", false)
			"AUTO-APT":
				_set_arm(mi, "apt", "", false)
			"RIGHT":
				_set_arm(mi, "commit", "ARCHETYPE", true)
			"NEIGHBOUR":
				_set_arm(mi, "commit", "ARCHETYPE", true)
				c_assigned = _neighbour_class(right)
				c_kit = c_assigned
			"WRONG":
				# assigned to a class sharing neither stat with the aptitude-best trade, and then
				# trained into it honestly — the caps and the brain both key off the WRONG class.
				_set_arm(mi, "commit", "ARCHETYPE", true, true)
			"TRANSIT":
				# ⚠️ THE ONLY ARM WHERE STATS AND KIT DISAGREE, AND THE ONLY PLACE THE 14x IS ON
				# THE TABLE. The body is trained into the RIGHT class exactly as arm RIGHT is —
				# same brain, same caps, same stat vector — and then the player REASSIGNS to a
				# class sharing neither of its stats. The kit is redrawn from the new class onto
				# a body that has none of its stats. That is what a reassignment costs on the day
				# it is made, and it is the cost that makes assignment a real commitment.
				_set_arm(mi, "commit", "ARCHETYPE", true)
				c_kit = _other_class(right)
		_train(mi, weeks, cap)
		# ── the kit ──────────────────────────────────────────────────────────────────────────
		# AUTO/AUTO-APT get today's behaviour: class derived from the stats they ended with, kit
		# drawn from that. The assigned arms keep their STORED class and draw from that instead.
		if c_kit == "":
			mi.recompute_class()
		else:
			mi.class_name_ = c_kit
			mi.role = Classify.role_of_class(c_kit)
			mi.mana_role = Classify.mana_role_of(mi.stats, c_kit)
			mi.basic_attack = Classify.basic_attack_for(mi.stats)
		mi.recompute_pools()
		mi.assign_moveset(krng)
		if mi.moveset.is_empty():
			_cok = false
			push_error("class probe: arm %s drafted an EMPTY kit for class '%s'" % [
				arm, str(mi.class_name_)])
		mi.hp = mi.max_hp
		mi.mp = mi.max_mp
		_clear_arm()
		team.append(mi)
	return team


## A class sharing `c`'s PRIMARY stat but not its secondary — the adjacent entry on the gate's own
## menu (`CLASS_REWORK.md` §2.2 opens top-2 primary / top-3 secondary, so neighbours like this are
## exactly what a player is choosing between). Falls back to a class sharing the SECONDARY as
## primary, then to `c` itself.
func _neighbour_class(c: String) -> String:
	var pair: Array = Roster._class_pair(c)
	if pair.size() < 2:
		return c
	for other in GameData.classes:
		var nm: String = str(other.get("name", ""))
		if nm == c:
			continue
		if str(other.get("primary", "")) == str(pair[0]):
			return nm
	for other in GameData.classes:
		var nm2: String = str(other.get("name", ""))
		if nm2 != c and str(other.get("primary", "")) == str(pair[1]):
			return nm2
	return c


## How many weeks the NAIVE brain needs to reach `cap x fill` mean stat on a representative body.
## ⚠️ CALIBRATED ON AUTO, THEN GIVEN TO EVERY ARM. The alternative — a flat week budget — put all
## five arms at 100% at every rung, because a body trained for 240 weeks at the Apex cap arrives
## at 488/stat against a reference climber at 407 and a rival field lower still. An instrument
## pinned above the ceiling measures the ceiling.
func _weeks_for_fill(cap: float, fill: float) -> int:
	var target: float = cap * fill
	var mi = _fresh_body(0, cap)
	_clear_arm()
	for w in range(1, 601):
		mi.happiness = 8
		mi.fed_this_week = true
		var plan: Dictionary = _drill_plan_greedy(mi, cap)
		if str(plan["mode"]) == "train":
			WeekLib.apply_activity(mi, {"kind": "train", "drillId": str(plan["id"])}, 0, cap,
				"Tamers Apex")
		else:
			WeekLib.apply_activity(mi, {"kind": "rest"}, 0, cap, "Tamers Apex")
		var sum := 0.0
		for s in Classify.STATS:
			sum += float(mi.stats.get(s, 0.0))
		if sum / float(Classify.STATS.size()) >= target:
			return w
	return 600


func _dec_fight(team: Array, size: int, idx: int, rival_fill: float, rseed: int,
		bseed: int) -> bool:
	var rivals: Array = Career.make_league_rivals(size, idx, rival_fill, rseed)
	for m in team:
		m.reset_for_battle()
	for m in rivals:
		m.reset_for_battle()
	var sim = BattleSimScript.new(team, rivals, bseed)
	return str(sim.run().get("winner", "")) == "A"
