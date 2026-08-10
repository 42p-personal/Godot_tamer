## THE COMMITMENT — does a stored class actually SURVIVE the game, and what does the gate offer?
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_assign.tscn
##
## ⚠️ THIS PROBE EXISTS BECAUSE THE FEATURE'S FAILURE MODE IS SILENCE. `docs/CLASS_REWORK.md`
## §10.2: a stored player choice in this codebase is erased by default — `recompute_class()` wrote
## all four derived fields unconditionally and one of its callers runs EVERY WEEK, while two UI
## screens overwrote the same fields without calling it at all. A class that is authored, stored,
## saved and documented and is quietly re-derived by the next tick is this project's signature bug
## (10+ instances). So nothing here is argued: every survival claim is made by RUNNING the thing
## that would have erased it — the real `week.gd:apply_week`, the real `save_game.gd` serializer,
## the real `roster.gd:_shape_to_class`, the real `breeding_ui.gd:_make_child`.
##
## ⚠️ AND SECTION 4 IS A CANARY ON A FILE THIS WORKSTREAM DOES NOT OWN. `week.gd:assignment_active`
## is a FEATURE DETECT — `"assigned_class" in mi` — so the mere EXISTENCE of the field flips
## `class_headroom` from round 14's `SPIKE_HEADROOM 1.35` to `UNASSIGNED_HEADROOM 1.00` for every
## monster in the game that has not committed. That is a real balance change delivered by a field
## declaration, and it must be seen rather than discovered later.
##
## SECTIONS
##   1  THE GATE            — pure, incl. the "no species locked out" extension (§10.3)
##   2  THE OVERWRITE SITES — assign it, then run everything that used to stamp over it
##   3  GENERALIST          — the uncommitted state, and that it still arms itself
##   4  THE week.gd CANARY  — what landing the field does to the training ceiling
extends Node

const WeekLib = preload("res://scripts/week.gd")
const BreedScript = preload("res://scripts/ui/breeding_ui.gd")

## The four rungs round 15 measured on, so the gate's menu can be read against the same ladder.
const RUNGS := [
	{"name": "Iron", "idx": 4, "cap": 500.0},
	{"name": "Gold", "idx": 6, "cap": 750.0},
	{"name": "Masters", "idx": 8, "cap": 1000.0},
	{"name": "Apex", "idx": 10, "cap": 1100.0},
]

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


func _section(t: String) -> void:
	print("\n─── %s ───" % t)


func _ready() -> void:
	print("\n=== ASSIGNABLE CLASS: does the commitment survive? ===")
	_section_gate()
	_section_overwrite_sites()
	_section_generalist()
	_section_week_canary()
	print("\n=== assign: %d passed, %d failed ===" % [_pass, _fail])
	for f in _failures:
		print("   failed: %s" % f)
	get_tree().quit(0 if _fail == 0 else 1)


# ── 1. THE GATE ──────────────────────────────────────────────────────────────────────────────

func _section_gate() -> void:
	_section("1. the gate (pure) — docs/CLASS_REWORK.md §2.2")

	# §2.3 worked example A, reproduced verbatim. If the gate ever stops agreeing with the
	# document's own worked example, one of the two is wrong and this says which.
	var a := {"STR": 380.0, "DEX": 340.0, "CON": 210.0, "WIS": 90.0, "INT": 70.0, "CHA": 60.0}
	var got_a := Classify.classes_available_for(a, 400.0)
	_ok(got_a == ["Rogue", "Skirmisher", "Warrior"],
		"§2.3 example A opens exactly Warrior/Skirmisher/Rogue (got %s)" % [got_a])

	# §2.3 example B — the CON+CHA hybrid that no class in the 18-entry table pairs. The document
	# claims it qualifies for zero. That claim is now a test rather than a paragraph.
	var b := {"CON": 320.0, "CHA": 300.0, "INT": 260.0, "STR": 150.0, "WIS": 140.0, "DEX": 110.0}
	var got_b := Classify.classes_available_for(b, 500.0)
	_ok(got_b.is_empty(), "§2.3 example B opens nothing — the CON+CHA coverage gap is real (got %s)"
		% [got_b])

	# The floor bites: the same shape, untrained, must NOT open the same menu.
	var tiny := {"STR": 38.0, "DEX": 34.0, "CON": 21.0, "WIS": 9.0, "INT": 7.0, "CHA": 6.0}
	_ok(Classify.classes_available_for(tiny, 400.0).is_empty(),
		"GATE_FLOOR blocks a flat untrained body from committing on day one")

	# `Generalist` is never a gated option — it is the uncommitted state, offered separately.
	var any_generalist := false
	for r in RUNGS:
		if Classify.classes_available_for(a, float(r["cap"])).has("Generalist"):
			any_generalist = true
	_ok(not any_generalist, "Generalist is never offered BY the gate — it is the ungated fallback")

	# ⚠️ THE NON-NEGOTIABLE, EXTENDED TO THE GATE (CLAUDE.md; §10.3). `_probe_archetypes.gd:128`
	# already proves every species can be SHAPED into every archetype class. That test cannot see
	# the gate, and the gate is the thing that could lock a species out by the back door. This
	# closes it constructively: shape a real body of every species onto every one of the 18
	# classes at the Apex cap, sum-preserving, and assert the gate then OFFERS that class.
	# ⚠️ SET THE LADDER FIRST. `GameData.make_monster` fills toward `GameData.stat_cap()`, which is
	# `Career.current_stat_cap()` — the league the game is STANDING IN. Generating at Wood and
	# shaping with an Apex `cap_override` produces a 93-point body wearing an Apex label, and the
	# gate's floor then correctly refuses all 18 classes. That is `roster.gd`'s documented
	# flattener biting the instrument instead of the game; it cost this section its first run.
	Career.league_index = 10  # Tamers Apex, the top rung
	var apex: float = Career.current_stat_cap()
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var misses: Array[String] = []
	var checked := 0
	for c in GameData.classes:
		var want: String = str(c.get("name", ""))
		for sid in Art.ROSTER:
			var mi = GameData.make_monster(str(sid), 0.75, rng, 1.0)
			if mi == null:
				continue
			Roster._shape_to_class(mi, want, rng, apex)
			checked += 1
			if not Classify.classes_available_for(mi.stats, apex).has(want):
				misses.append("%s/%s" % [sid, want])
	_ok(misses.is_empty(),
		"no species is locked out of a class BY THE GATE — %d species x class checked, %d misses%s"
			% [checked, misses.size(), "" if misses.is_empty() else (" e.g. " + misses[0])])

	# ── MEASUREMENT, not an assertion: what does GATE_FLOOR 0.20 actually cost, per rung?
	# Round 15's finding is that a fraction of the LEAGUE cap inherits the same inversion the
	# per-class caps do — inert where the game is won. This is the number that would move it.
	print("\n  GATE_FLOOR = %.2f x nominal cap. Menu size for a naive career body at each rung:" % Classify.GATE_FLOOR)
	print("  (body = the archetype-shaped Warrior vector at the rung's own realistic fill)")
	for r in RUNGS:
		Career.league_index = int(r["idx"])
		var cap: float = Career.current_stat_cap()
		var probe_rng := RandomNumberGenerator.new()
		probe_rng.seed = 4242
		var mi = GameData.make_monster(Art.ROSTER[0], 0.62, probe_rng, 1.0)
		Roster._shape_to_class(mi, "Warrior", probe_rng, cap)
		var menu := Classify.classes_available_for(mi.stats, cap)
		var top: float = 0.0
		for s in Classify.STATS:
			top = maxf(top, float(mi.stats[s]))
		print("    %-8s cap %4d  floor %4d  primary %4d  menu %d  %s"
			% [r["name"], int(cap), int(round(Classify.GATE_FLOOR * cap)), int(top), menu.size(), menu])
	print("  ⚠️ A floor the primary clears at every rung is a floor that never taught anything.")


# ── 2. THE OVERWRITE SITES ───────────────────────────────────────────────────────────────────

## A body deliberately shaped so that its assigned class and its DERIVED class disagree — the only
## configuration in which "the commitment survived" means anything at all.
func _committed_tank() -> Object:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var mi = GameData.make_monster(Art.ROSTER[0], 0.5, rng, 1.0)
	mi.stats = {"CON": 300.0, "STR": 290.0, "DEX": 120.0, "WIS": 110.0, "INT": 100.0, "CHA": 90.0}
	mi.assign_class("Tank")
	mi.recompute_pools()
	mi.assign_moveset(rng)
	return mi


func _section_overwrite_sites() -> void:
	_section("2. the overwrite sites — run the thing that used to erase it")

	var mi = _committed_tank()
	_ok(mi.class_name_ == "Tank" and mi.is_class_assigned(), "assign_class('Tank') sticks")
	_ok(mi.role == "support" and mi.mana_role == "tank",
		"role/mana_role follow the ASSIGNED class, not the derived one (%s/%s)" % [mi.role, mi.mana_role])
	_ok(str(mi.basic_attack.get("stat", "")) == str(
			Classify.basic_attack_for_class("Tank", mi.stats).get("stat", "")),
		"the free attack is the ASSIGNED class's — the contracted derivation no longer decides it")

	# (a) the bare recompute — five shipped callers funnel through this one function.
	mi.recompute_class()
	_ok(mi.class_name_ == "Tank", "survives recompute_class() (game_data/roster/save_game/week)")

	# (b) ⚠️ THE CRITICAL ONE. A STAT CHANGE THAT WOULD HAVE RE-DERIVED IT. Train STR past CON so
	# `class_for_stats` genuinely disagrees — otherwise every check below is vacuously true.
	mi.stats["STR"] = 900.0
	mi.recompute_class()
	var derived_now := Classify.class_for_stats(mi.stats)
	_ok(derived_now != "Tank",
		"the control holds: these stats WOULD derive '%s', not Tank" % derived_now)
	_ok(mi.class_name_ == "Tank", "survives a stat change that would have re-derived the class")
	_ok(mi.mana_role == "tank" and mi.role == "support",
		"and the derived fields still follow the COMMITMENT, not the new stat shape")

	# (c) THE WEEKLY TICK, REAL. week.gd:apply_activity calls recompute_class() then
	# _redraft_if_stale every week for every monster. This is the caller that made the whole
	# feature a coin flip. Ten real weeks, real drills, real RNG seeding.
	var tick = _committed_tank()
	var before_kit: int = tick.moveset.size()
	var gold := 5000
	var drill := WeekLib.drill_by_id("weights")
	for i in range(10):
		tick.stamina = 100.0
		gold = WeekLib.apply_week(tick, drill, gold, 0, "", true, 0, 1100.0, "Tamers Apex")
	_ok(tick.class_name_ == "Tank" and tick.assigned_class == "Tank",
		"survives 10 real weeks of week.gd:apply_week (career_week %d, STR %d)"
			% [tick.career_week, int(tick.stats["STR"])])
	_ok(tick.moveset.size() > 0,
		"and the weekly re-draft never disarmed it (%d -> %d moves)" % [before_kit, tick.moveset.size()])

	# (d) SAVE / LOAD, through the real serializer and the real deserializer.
	var row: Dictionary = SaveGame._serialize_monster(tick)
	_ok(str(row.get("assignedClass", "")) == "Tank", "the save row carries `assignedClass`")
	var back: Array = SaveGame._deserialize_roster([row])
	_ok(back.size() == 1 and back[0].class_name_ == "Tank" and back[0].assigned_class == "Tank",
		"survives a save/load round trip")

	# (e) THE MIGRATION. Strip the key exactly as a v1/v2 save has it: the monster must load,
	# must keep the class it always had (derived), and must NOT be silently committed to it.
	var legacy: Dictionary = row.duplicate(true)
	legacy.erase("assignedClass")
	var old: Array = SaveGame._deserialize_roster([legacy])
	_ok(old.size() == 1, "a v2 save row (no `assignedClass`) still loads — nobody loses a roster")
	if old.size() == 1:
		_ok(not old[0].is_class_assigned() and old[0].class_name_ == Classify.class_for_stats(old[0].stats),
			"…and loads UNCOMMITTED, deriving exactly as it always did (%s)" % old[0].class_name_)

	# (f) THE PREVIEW CLONE. week.gd:preview_week runs the real apply_week on this copy; a clone
	# that arrived uncommitted would preview a different class from the one the week produces.
	var clone = tick.clone_for_preview()
	_ok(clone.assigned_class == "Tank" and clone.class_name_ == "Tank",
		"clone_for_preview carries the commitment (the preview/apply mirror)")

	# (g) roster.gd:_shape_to_class — the sum-preserving shaper every rival and every finished
	# market body goes through. It must ADVERTISE the trade and NOT commit it: committing here
	# would hand a body the player just bought a permanent 0.70 ceiling on four stats
	# (`week.gd:CLASS_OFF_HEADROOM`) for a decision they never made. See the note at that call site.
	var srng := RandomNumberGenerator.new()
	srng.seed = 11
	Career.league_index = 10
	var shaped = GameData.make_monster(Art.ROSTER[3], 0.6, srng, 1.0)
	Roster._shape_to_class(shaped, "Ranger", srng, Career.current_stat_cap())
	_ok(shaped.class_name_ == "Ranger", "_shape_to_class still lands the class it was asked for")
	_ok(not shaped.is_class_assigned(),
		"…and does NOT commit it — the market advertises a trade, the player ratifies it")
	# And a body that WAS committed must not keep a stale commitment through a reshape onto a
	# different axis — that is round 15's 0.07x mismatched build, manufactured by the shaper.
	shaped.assign_class("Ranger")
	Roster._shape_to_class(shaped, "Tank", srng, Career.current_stat_cap())
	_ok(not shaped.is_class_assigned() and shaped.class_name_ == "Tank",
		"re-shaping a COMMITTED body clears the stale commitment instead of mismatching it")

	# (h) game_data.gd:make_monster — a generated body is born UNCOMMITTED. This is a deliberate
	# refusal of §10.2 row 2; see the comment at that call site.
	var grng := RandomNumberGenerator.new()
	grng.seed = 12
	var fresh = GameData.make_monster(Art.ROSTER[5], 0.4, grng, 1.0)
	_ok(not fresh.is_class_assigned(),
		"a generated monster is born uncommitted — every probe/rival/save behaves as before")

	# (i) breeding_ui.gd:_make_child — one of the two INLINE overwrite sites (§10.2 rows 6/7).
	# It writes class_name_/role/mana_role directly, bypassing recompute_class() entirely. A child
	# born uncommitted makes that write CORRECT rather than dangerous, which is why the file did
	# not have to be edited by this workstream.
	Roster.reset_to_empty()
	Roster._generate_starting_roster()
	if Roster.monsters.size() >= 2:
		var pa = Roster.monsters[0]
		var pb = Roster.monsters[1]
		pa.assign_class("Warrior")
		pb.assign_class("Tank")
		var ui = BreedScript.new()
		ui._emphasis = "STR"
		var foal = ui._make_child(pa, pb, "assignprobe")
		ui.free()
		_ok(foal != null, "a breed still produces a foal with committed parents")
		if foal != null:
			_ok(not foal.is_class_assigned(),
				"the foal is born UNCOMMITTED — every child is a fresh decision (design call, see report)")
			_ok(foal.class_name_ == Classify.class_for_stats(foal.stats),
				"…and breeding_ui's inline write agrees with the derivation for an uncommitted body")
		_ok(pa.assigned_class == "Warrior" and pb.assigned_class == "Tank",
			"a breeding cycle does not disturb the PARENTS' commitments")
	Roster.reset_to_empty()


# ── 3. GENERALIST ────────────────────────────────────────────────────────────────────────────

func _section_generalist() -> void:
	_section("3. Generalist — the uncommitted state, and it still arms itself")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var mi = GameData.make_monster(Art.ROSTER[1], 0.5, rng, 1.0)
	mi.assign_class("Generalist")
	mi.assign_moveset(rng)
	_ok(mi.class_name_ == "Generalist", "Generalist is assignable (ungated, always available)")
	_ok(mi.moveset.size() > 0,
		"…and still arms itself via _fallback_lines (%d moves) — the round-11 tripwire holds"
			% mi.moveset.size())
	_ok(not mi.basic_attack.is_empty(), "…and keeps its authored free attack")
	mi.clear_class_assignment()
	_ok(not mi.is_class_assigned() and mi.class_name_ == Classify.class_for_stats(mi.stats),
		"clear_class_assignment returns it to derivation (%s) — the commitment is reversible" % mi.class_name_)


# ── 4. THE week.gd CANARY ────────────────────────────────────────────────────────────────────

func _section_week_canary() -> void:
	_section("4. ⚠️ what landing this field does to week.gd (NOT this workstream's file)")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var mi = GameData.make_monster(Art.ROSTER[2], 0.5, rng, 1.0)
	_ok(WeekLib.assignment_active(mi),
		"week.gd:assignment_active is now TRUE — the feature detect has flipped for EVERY monster")
	var uncommitted := WeekLib.class_headroom(mi, "STR")
	mi.assign_class("Warrior")
	var primary := WeekLib.class_headroom(mi, "STR")
	var off := WeekLib.class_headroom(mi, "CHA")
	print("  headroom on STR: uncommitted %.2f -> Warrior-primary %.2f · off-class CHA %.2f"
		% [uncommitted, primary, off])
	# ⚠️ THE PER-CLASS CAPS WERE RETIRED (user decision 2026-08-10) AND THIS CHECK IS INVERTED
	# ON PURPOSE. It used to assert `primary > off` — that committing BOUGHT stat room. It did,
	# and that was the problem: the same clip cost a committed specialist 8 careers in 16 while
	# the naive player never moved, because `career.gd:expected_climber_fill` prices on stat TOTAL
	# and is blind to shape. See the long block above `week.gd:class_headroom` for the measurement.
	# What the probe must now defend is that committing costs NOTHING in ceiling terms, so the
	# decision is paid for in kit alignment alone and can never re-import that inversion.
	_ok(is_equal_approx(primary, off) and is_equal_approx(primary, WeekLib.SPIKE_HEADROOM),
		"committing changes NO stat ceiling — every stat keeps SPIKE_HEADROOM (%.2f/%.2f/%.2f)"
		% [uncommitted, primary, off])
