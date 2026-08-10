## ROUND 15 INTEGRATION AUDIT — does the player's choice survive, and does the KIT follow it?
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_integrate.tscn
##
## ⚠️ THIS IS DELIBERATELY A SECOND, INDEPENDENT INSTRUMENT. `_probe_assign.gd` was written by the
## same workstream that wrote the feature, and the failure mode this round exists to prevent
## (authored, stored, documented, silently overwritten) is exactly the kind a builder's own probe
## can miss because it tests what the builder believes. Nothing here shares a helper with that
## file. Every survival claim is made by running the SHIPPED function that would have erased the
## choice, and every kit claim is made by reading the DRAFTED MOVES back against the assigned
## class's own lines — never by reading `class_name_`.
##
## SECTIONS
##   1  THE SIX OVERWRITE SITES  — assign, then run each thing that used to stamp over it
##   2  THE KIT SEAM             — assign a class the STATS CONTRADICT; does the kit follow?
##   3  SPECIES LOCKOUT          — 65 species x 18 classes, reachability under the caps AND the gate
##   4  THE CIRCULARITY          — does a cap ever move because of the stat that would re-select it
extends Node

const WeekLib = preload("res://scripts/week.gd")
const ClassifyLib = preload("res://scripts/classify.gd")
const MonsterScript = preload("res://scripts/monster_instance.gd")
const BreedScript = preload("res://scripts/ui/breeding_ui.gd")

var _pass := 0
var _fail := 0
var _failures: Array[String] = []


func _ok(cond: bool, label: String) -> bool:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		_failures.append(label)
		print("  *** FAIL *** %s" % label)
	return cond


func _sec(t: String) -> void:
	print("\n─── %s ───" % t)


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


## A body whose two highest stats are STR/CON — `class_for_stats` derives a STR/CON trade from it,
## and nothing about it points at WIS/INT.
func _brute(id: String):
	var mi = GameData.make_monster(str(Art.ROSTER[3]), 0.0, _rng(11), 1.0)
	mi.id = id
	mi.stats = {"STR": 620.0, "CON": 560.0, "DEX": 180.0, "WIS": 120.0, "INT": 110.0, "CHA": 100.0}
	mi.potential = 1.0
	mi.recompute_class()
	mi.recompute_pools()
	mi.assign_moveset(_rng(12))
	mi.hp = mi.max_hp
	mi.mp = mi.max_mp
	return mi


## The lines a class draws from, as the shipped kit drafter reads them.
func _lines_of(cls: String) -> Array:
	return GameData.class_lines.get(cls, [])


## Which lines a monster's CURRENT moveset actually came from.
func _kit_lines(mi) -> Array:
	var out: Array = []
	for mv in mi.moveset:
		var l: String = str(GameData.line_of.get(str(mv.get("name", "")), ""))
		if l != "" and not out.has(l):
			out.append(l)
	out.sort()
	return out


# ═══════════════════════════════════════════════════════════════════════════════════════════
# 1  THE SIX OVERWRITE SITES
# ═══════════════════════════════════════════════════════════════════════════════════════════

func _sec_sites() -> void:
	_sec("1  THE OVERWRITE SITES — assign, then run the thing that used to erase it")

	# The class we commit to is deliberately one the stats do NOT derive: if anything re-derives,
	# the field flips back to the STR/CON answer and the check goes red immediately.
	var target := "Sage"
	if not GameData.class_lines.has(target):
		for c in GameData.classes:
			if str(c.get("primary", "")) == "WIS":
				target = str(c.get("name", ""))
				break
	print("  committed class under test: %s   (stats derive: %s)" %
		[target, ClassifyLib.class_for_stats(_brute("x").stats)])

	# ── SITE 1: week.gd:apply_week — THE WEEKLY TICK, the one that runs every week ──────────
	var m1 = _brute("site1")
	m1.assign_class(target, _rng(21))
	var gold := 5000
	for w in range(10):
		var act := {"kind": "train", "stat": "STR", "intensity": "intensive"}
		gold = WeekLib.apply_week(m1, act, gold, 0, "", true, 0, 1100.0, "Iron")
	_ok(m1.assigned_class == target and m1.class_name_ == target,
		"SITE 1  week.gd:apply_week x10 real weeks — assigned='%s' class_name_='%s'" %
			[m1.assigned_class, m1.class_name_])

	# ── SITE 2: save_game.gd — serialize + deserialize ──────────────────────────────────────
	var save = load("res://scripts/save_game.gd").new()
	var row: Dictionary = save._serialize_monster(m1)
	var back: Array = save._deserialize_roster([row])
	_ok(back.size() == 1 and back[0].assigned_class == target and back[0].class_name_ == target,
		"SITE 2  save_game round trip — assigned='%s' class_name_='%s'" %
			[back[0].assigned_class if back.size() > 0 else "<none>",
			 back[0].class_name_ if back.size() > 0 else "<none>"])
	# and the migration: a row with the key STRIPPED must load uncommitted, deriving as always
	var v2row := row.duplicate(true)
	v2row.erase("assignedClass")
	var v2back: Array = save._deserialize_roster([v2row])
	_ok(v2back.size() == 1 and v2back[0].assigned_class == ""
			and v2back[0].class_name_ == ClassifyLib.class_for_stats(v2back[0].stats),
		"SITE 2b MIGRATION: a pre-v3 save row loads UNCOMMITTED and derives as before ('%s')" %
			(v2back[0].class_name_ if v2back.size() > 0 else "<none>"))
	save.free()

	# ── SITE 3: a stat change that WOULD have re-derived, then recompute_class() ─────────────
	var m3 = _brute("site3")
	m3.assign_class(target, _rng(31))
	m3.stats["DEX"] = 5000.0     # DEX now dominates by a mile
	m3.stats["CHA"] = 4000.0
	var control := ClassifyLib.class_for_stats(m3.stats)
	m3.recompute_class()
	_ok(control != target, "SITE 3  control: those stats DO derive a different class ('%s')" % control)
	_ok(m3.class_name_ == target,
		"SITE 3  recompute_class() after a class-flipping stat change — still '%s'" % m3.class_name_)
	# and the fields that MUST still track the body do
	_ok(m3.basic_attack.get("stat", "") == ClassifyLib.basic_attack_for_class(target, m3.stats).get("stat", ""),
		"SITE 3b basic_attack follows the ASSIGNED class, not the derived one")

	# ── SITE 4: game_data.gd:make_monster — generation ──────────────────────────────────────
	var m4 = GameData.make_monster(str(Art.ROSTER[7]), 0.4, _rng(41), 1.0)
	_ok(m4.assigned_class == "" and m4.class_name_ == ClassifyLib.class_for_stats(m4.stats),
		"SITE 4  make_monster: born UNCOMMITTED, class derives exactly as before ('%s')" % m4.class_name_)
	_ok(not ("train" in GameData),
		"SITE 4b the dead game_data.gd:train() — a sixth writer of the derived fields — is GONE")

	# ── SITE 5: roster.gd:_shape_to_class ───────────────────────────────────────────────────
	var m5 = _brute("site5")
	m5.assign_class(target, _rng(51))
	# ⚠️ `cap_override` IS NOT OPTIONAL IN A PROBE. Without it the shaper reads
	# `GameData.stat_cap()`, which reads `Career.league_index` — 0 (Wood) in a fresh process — so
	# every stat clamps to the Wood ceiling, the six values flatten, and the shape the function was
	# asked for is not the shape it produces. This cost a false FAIL on the first run of this file.
	Roster._shape_to_class(m5, "Warrior", _rng(52), 1100.0)
	_ok(m5.assigned_class == "",
		"SITE 5  _shape_to_class CLEARS a stale commitment (assigned='%s') — no 0.07x trap" % m5.assigned_class)
	_ok(m5.class_name_ == "Warrior",
		"SITE 5b _shape_to_class still derives the shape it was asked for ('%s') — the archetype assertion is real" % m5.class_name_)

	# ── SITE 6: breeding_ui.gd / lab_ui.gd — the two DIRECT writers of class_name_ ───────────
	var pa = _brute("dam"); pa.assign_class(target, _rng(61))
	var pb = _brute("sire"); pb.assign_class("Warrior", _rng(62))
	var breeder = BreedScript.new()
	add_child(breeder)
	var child = breeder._make_child(pa, pb, "slotX")
	var child_ok: bool = child != null
	_ok(child_ok and pa.assigned_class == target and pb.assigned_class == "Warrior",
		"SITE 6  breeding_ui._make_child: BOTH parents keep their commitment (%s / %s)" %
			[pa.assigned_class, pb.assigned_class])
	_ok(child_ok and child.assigned_class == ""
			and child.class_name_ == ClassifyLib.class_for_stats(child.stats),
		"SITE 6b the foal is born UNCOMMITTED, so the inline class_name_ write AGREES with derivation")
	breeder.queue_free()
	# lab_ui.gd:273 is the identical two-line pattern on the identical object — assert the shape
	# rather than re-running a second UI: the claim is that a direct `class_name_` write is safe
	# ONLY while the body is uncommitted, and it is the SAME claim.
	var lab_src := FileAccess.get_file_as_string("res://scripts/ui/lab_ui.gd")
	_ok(lab_src.find("child.class_name_ = ClassifyLib.class_for_stats") >= 0
			and lab_src.find("assign_class") < 0,
		"SITE 6c lab_ui.gd writes class_name_ inline on an UNCOMMITTED child only (no assign_class path)")

	# ── SITE 7 (the brief's sixth, and it is the one nobody listed): THE MARKET ──────────────
	var offers: Array = Roster.market_offers(30, 4, 6, 1.0)
	var all_uncommitted := true
	var grades: Array = []
	for o in offers:
		grades.append(str(o.get("grade", "")))
		if o["mi"].assigned_class != "":
			all_uncommitted = false
	_ok(offers.size() > 0 and all_uncommitted,
		"SITE 7  market_offers: every recruit (%s) arrives UNCOMMITTED — the till takes no decision" %
			", ".join(PackedStringArray(grades)))


# ═══════════════════════════════════════════════════════════════════════════════════════════
# 2  THE KIT SEAM — kit alignment is the 14x. Does the moveset follow the CHOICE?
# ═══════════════════════════════════════════════════════════════════════════════════════════

func _sec_kit() -> void:
	_sec("2  THE KIT SEAM — assign a class the stats CONTRADICT and read the drafted moves back")

	var target := "Sage"
	if not GameData.class_lines.has(target):
		for c in GameData.classes:
			if str(c.get("primary", "")) == "WIS":
				target = str(c.get("name", ""))
				break

	# CONTROL: uncommitted, the kit follows the DERIVED class.
	var ctl = _brute("kit_ctl")
	var derived := str(ctl.class_name_)
	var ctl_lines := _kit_lines(ctl)
	var derived_lines: Array = _lines_of(derived)
	var ctl_in := true
	for l in ctl_lines:
		if not derived_lines.has(l):
			ctl_in = false
	_ok(ctl.moveset.size() > 0 and ctl_in,
		"CONTROL  uncommitted body drafts from its DERIVED class '%s' — kit lines %s ⊆ %s" %
			[derived, str(ctl_lines), str(derived_lines)])

	# THE TEST: commit to a class this body's stats do not point at, with an rng.
	var m = _brute("kit_test")
	m.assign_class(target, _rng(71))
	var kit_lines := _kit_lines(m)
	var want_lines: Array = _lines_of(target)
	var all_in := kit_lines.size() > 0
	for l in kit_lines:
		if not want_lines.has(l):
			all_in = false
	_ok(all_in, "KIT follows the ASSIGNMENT: '%s' lines %s, kit drew from %s" %
		[target, str(want_lines), str(kit_lines)])
	# and it is genuinely DIFFERENT from what the stats would have drawn
	var overlap := 0
	for l in kit_lines:
		if derived_lines.has(l):
			overlap += 1
	_ok(overlap < kit_lines.size(),
		"KIT is not the derived kit by coincidence: %d of %d lines overlap the derived class" %
			[overlap, kit_lines.size()])

	# ⚠️ AND IT MUST SURVIVE THE RE-DRAFT. `week.gd:_redraft_if_stale` is the ONLY thing that
	# redraws a kit in the shipped game, and it fires on stat growth as well as class change.
	# If it drew from the derived class, ten weeks of STR training would quietly re-arm this
	# monster as a brute and the commitment would be cosmetic.
	var gold := 5000
	for w in range(14):
		gold = WeekLib.apply_week(m, {"kind": "train", "stat": "STR", "intensity": "intensive"},
			gold, 0, "", true, 0, 1100.0, "Iron")
	var after := _kit_lines(m)
	var still_in := after.size() > 0
	for l in after:
		if not want_lines.has(l):
			still_in = false
	_ok(still_in,
		"KIT survives 14 weeks of OFF-CLASS training + _redraft_if_stale — kit lines %s" % str(after))
	_ok(not m.moveset.is_empty(), "KIT is never empty after a re-draft (%d moves)" % m.moveset.size())

	# REASSIGNMENT: the one hazard the builder flagged — `_redraft_if_stale` cannot rescue a
	# forgotten redraw, because class_before == class_name_ by the time the tick runs.
	var r = _brute("kit_reassign")
	r.assign_class(target, _rng(81))
	r.assign_class("Warrior", null)          # deliberately NO rng — the forgetful call
	var stale := _kit_lines(r)
	var warrior_lines: Array = _lines_of("Warrior")
	var leaked := false
	for l in stale:
		if not warrior_lines.has(l):
			leaked = true
	_ok(leaked,
		"HAZARD CONFIRMED: assign_class() without an rng leaves the OLD kit (%s) on a '%s' — callers MUST pass rng" %
			[str(stale), r.class_name_])
	# ⚠️ AND THE RESCUE IS REAL BUT CONDITIONAL, WHICH IS WORSE THAN EITHER PURE ANSWER.
	# `_redraft_if_stale` has TWO staleness tests. The class-change one cannot fire after a
	# reassignment (class_before == class_name_ by then) — that is the builder's finding and it is
	# correct. But the SECOND one — top stat outrunning the top carried learnLevel by
	# KIT_STALE_MARGIN — knows nothing about class, and it re-drafts from the NEW class's lines
	# when it fires. So a reassigned monster whose body has outgrown its kit self-heals within a
	# week, and one whose kit is already at its stat level carries the WRONG kit indefinitely.
	# Both branches are asserted here, on the same object, so neither can be mistaken for the rule.
	var g2 := 5000
	g2 = WeekLib.apply_week(r, {"kind": "rest"}, g2, 0, "", true, 0, 1100.0, "Iron")
	var after_tick := _kit_lines(r)
	var rescued := after_tick.size() > 0
	for l in after_tick:
		if not warrior_lines.has(l):
			rescued = false
	_ok(rescued,
		"RESCUE branch A: a body that has OUTGROWN its kit self-heals on the next tick — kit now %s" % str(after_tick))

	# branch B: the same forgetful reassignment on a body whose kit already matches its stats.
	# Nothing is stale, so nothing re-drafts, and the wrong kit is permanent.
	var q = _brute("kit_nodrift")
	q.assign_class(target, _rng(91))
	var top_stat := 0.0
	for s in q.stats:
		top_stat = maxf(top_stat, float(q.stats[s]))
	var top_carried := 0.0
	for mv in q.moveset:
		top_carried = maxf(top_carried, float(mv.get("learnLevel", 0.0)))
	# put the body level with its kit so the learnLevel branch cannot fire
	for s in q.stats:
		q.stats[s] = minf(float(q.stats[s]), top_carried + 10.0)
	q.assign_class("Warrior", null)          # the forgetful call again
	var g3 := 5000
	for w in range(6):
		g3 = WeekLib.apply_week(q, {"kind": "rest"}, g3, 0, "", true, 0, 1100.0, "Iron")
	var stuck := _kit_lines(q)
	var leaked_b := false
	for l in stuck:
		if not warrior_lines.has(l):
			leaked_b = true
	_ok(leaked_b,
		"RESCUE branch B: a body LEVEL with its kit never re-drafts — 6 weeks on, a '%s' still carries %s. The rng is a caller CONTRACT." %
			[q.class_name_, str(stuck)])


# ═══════════════════════════════════════════════════════════════════════════════════════════
# 3  SPECIES LOCKOUT — CLAUDE.md's one non-negotiable, tested against the CAPS and the GATE
# ═══════════════════════════════════════════════════════════════════════════════════════════

func _sec_lockout() -> void:
	_sec("3  NO SPECIES IS LOCKED OUT OF ANY ROLE — 65 species x 18 classes, under caps AND gate")

	# ⚠️ `make_monster` READS `Career.league_index` FOR ITS OWN CEILING, so a fresh process
	# generates WOOD-scale bodies (cap 120) no matter what cap this probe then quotes at the gate.
	# Presenting a Wood body against an Apex nominal cap fails the 0.20 floor for every one of the
	# 1170 pairs and reads as a total lockout — which is what the first run of this file reported.
	# Move the whole process to the rung being tested, and restore it afterwards.
	var saved_league: int = Career.league_index
	Career.league_index = 10
	var cap: float = Career.current_stat_cap()
	print("  rung under test: league_index=%d  cap=%d  gate floor=%d" %
		[Career.league_index, int(cap), int(ClassifyLib.GATE_FLOOR * cap)])
	var gate_misses: Array = []
	var cap_misses: Array = []
	var kit_misses: Array = []
	var pairs := 0

	for sp in GameData.species:
		var sid: String = str(sp.get("id", ""))
		for c in GameData.classes:
			var want: String = str(c.get("name", ""))
			pairs += 1
			var mi = GameData.make_monster(sid, 0.55, _rng(910 + pairs), 1.0)
			if mi == null:
				continue
			mi.potential = 1.0
			# The player's real route: train toward the trade (the shaper is the sum-preserving
			# stand-in for a career of drills — it INVENTS no points), then present at the gate.
			Roster._shape_to_class(mi, want, _rng(920 + pairs), cap)
			var menu: Array = ClassifyLib.classes_available_for(mi.stats, cap)
			if not menu.has(want):
				gate_misses.append("%s->%s" % [sid, want])
				continue
			mi.assign_class(want, _rng(930 + pairs))
			# The cap must leave the class's own primary room to grow — a ceiling at or below the
			# current value would be a role this species can enter but never advance in.
			var pri: String = str(c.get("primary", ""))
			var ceil_pri: float = WeekLib.stat_ceiling(mi, cap, pri)
			if ceil_pri < cap:
				cap_misses.append("%s->%s (%s ceiling %d < %d)" % [sid, want, pri, int(ceil_pri), int(cap)])
			if mi.moveset.is_empty():
				kit_misses.append("%s->%s" % [sid, want])

	print("  tested %d species x class pairs" % pairs)
	_ok(gate_misses.is_empty(), "GATE opens for every species x class pair (%d misses%s)" %
		[gate_misses.size(), "" if gate_misses.is_empty() else ": " + ", ".join(PackedStringArray(gate_misses.slice(0, 6)))])
	_ok(cap_misses.is_empty(), "CAPS leave the class primary at least the full nominal cap (%d misses%s)" %
		[cap_misses.size(), "" if cap_misses.is_empty() else ": " + ", ".join(PackedStringArray(cap_misses.slice(0, 6)))])
	_ok(kit_misses.is_empty(), "EVERY committed pair arms a kit (%d disarmed)" % kit_misses.size())

	Career.league_index = saved_league

	# Generalist is the 19th and is never gated — assert it separately, as the always-open state.
	var g = GameData.make_monster(str(Art.ROSTER[0]), 0.5, _rng(999), 1.0)
	g.assign_class("Generalist", _rng(998))
	_ok(g.class_name_ == "Generalist" and not g.moveset.is_empty(),
		"GENERALIST is assignable and still arms itself via _fallback_lines (%d moves)" % g.moveset.size())
	# ⚠️ SINCE THE PER-CLASS CAPS WERE RETIRED (2026-08-10) *EVERY* CLASS TAKES THE UNIFORM
	# CEILING, so this no longer distinguishes Generalist from anything — it now asserts the
	# retirement itself, which is the invariant worth guarding. Generalist stays interesting for
	# the OTHER reason: it is not in `GameData.classes`, it is the class you fall into, and it
	# shipped kitless once already (round 11). That half is asserted directly above.
	var uniform := true
	for st in ClassifyLib.STATS:
		if not is_equal_approx(WeekLib.class_headroom(g, st), WeekLib.SPIKE_HEADROOM):
			uniform = false
	_ok(uniform,
		"GENERALIST takes the same ceiling as every other class — the per-class caps are retired")


# ═══════════════════════════════════════════════════════════════════════════════════════════
# 4  THE CIRCULARITY — a cap must never move because of the stat that would re-select the class
# ═══════════════════════════════════════════════════════════════════════════════════════════

func _sec_circularity() -> void:
	_sec("4  THE CIRCULARITY — is the loop that killed the first attempt actually broken?")

	var cap := 1100.0
	var m = _brute("circ")
	m.assign_class("Warrior", _rng(101))
	var pair := WeekLib.class_stat_pair("Warrior")
	var base_pri: float = WeekLib.class_headroom(m, str(pair[0]))
	var base_off: float = WeekLib.class_headroom(m, "INT")

	# Drive the stat vector through six radically different shapes — every one of which derives a
	# DIFFERENT class. If any headroom moves, the cap is still reading the body rather than the
	# choice, and the loop is intact.
	var moved: Array = []
	var derived_seen: Array = []
	for st in ClassifyLib.STATS:
		var probe = _brute("circ_" + st)
		probe.assign_class("Warrior", _rng(102))
		for s in ClassifyLib.STATS:
			probe.stats[s] = 100.0
		probe.stats[st] = 1050.0
		var d := ClassifyLib.class_for_stats(probe.stats)
		if not derived_seen.has(d):
			derived_seen.append(d)
		if WeekLib.class_headroom(probe, str(pair[0])) != base_pri:
			moved.append("%s: primary headroom moved" % st)
		if WeekLib.class_headroom(probe, "INT") != base_off and str(pair[0]) != "INT" and str(pair[1]) != "INT":
			moved.append("%s: off-class headroom moved" % st)
	_ok(moved.is_empty(),
		"HEADROOM is a function of the CHOICE only — 6 stat shapes deriving %s, %d movements" %
			[str(derived_seen), moved.size()])

	# And the specific circular form: raising the stat that CHOSE the class must not raise its own cap.
	var a = _brute("circ_a"); a.assign_class("Warrior", _rng(103))
	var before := WeekLib.class_headroom(a, str(pair[0]))
	a.stats[str(pair[0])] = 1090.0
	var after := WeekLib.class_headroom(a, str(pair[0]))
	_ok(before == after,
		"raising the class's OWN primary does not raise its own headroom (%.3f -> %.3f)" % [before, after])

	# Source-level guard: week.gd must never CALL `class_for_stats`. ⚠️ Comments mention it by name
	# (the ⚠️ on `assigned_class_of` says "NEVER class_for_stats(mi.stats)"), so a bare substring
	# search reports a false positive on the very warning that prevents the bug. Strip comments.
	var wsrc := FileAccess.get_file_as_string("res://scripts/week.gd")
	var live_hits := 0
	for line in wsrc.split("\n"):
		var l := str(line).strip_edges()
		if l.begins_with("#"):
			continue
		if l.find("class_for_stats") >= 0:
			live_hits += 1
	_ok(live_hits == 0,
		"week.gd makes NO live call to class_for_stats (%d outside comments) — a cap cannot read a derived class" % live_hits)


func _ready() -> void:
	print("\n=== ROUND 15 INTEGRATION AUDIT ===")
	_sec_sites()
	_sec_kit()
	_sec_lockout()
	_sec_circularity()
	print("\n%d passed / %d failed" % [_pass, _fail])
	for f in _failures:
		print("   FAILED: %s" % f)
	get_tree().quit(1 if _fail > 0 else 0)
