## THE PORT'S ACCEPTANCE TEST — runs every contract in `data/` through the GDScript engine.
##
## ⚠️ THIS IS NOT A SMOKE TEST, IT IS THE MILESTONE. The question it answers is the only one
## worth asking at this stage: does identical arithmetic come out of two languages? No visuals,
## no arenas, no navigation, no sprites. If it passes, the rest of the port is downhill; if it
## does not, we find out in a day rather than a month.
##
##   combat.json  damage resolution        -> damage.gd
##   derive.json  pools, mana, cooldowns   -> derive.gd
##   status.json  statuses and CC DR       -> status_math.gd
##   tick.json    timers, regen, attrition -> tick.gd
##   classify.json class, role, free attack  -> classify.gd
##
## The contracts are generated from the TypeScript by `npx tsx tools/exportport.ts` and diffed
## against the live TS fixtures on every `npm test`, so they cannot rot into a snapshot of
## something that used to be true. `run_contract.sh` re-copies them before every run.
extends Node

## ⚠️ PRELOADED RATHER THAN REACHED FOR BY `class_name`. A global class name resolves only
## once the project's class cache is warm, so `validate_script` on a single file reports it as
## undeclared — a false failure that costs more to explain than the preload costs to write.
const DamageMath := preload("res://scripts/damage.gd")
const DeriveMath := preload("res://scripts/derive.gd")
const StatusMathLib := preload("res://scripts/status_math.gd")
const TickLib := preload("res://scripts/tick.gd")
const ClassifyLib := preload("res://scripts/classify.gd")

## Fields compared per damage case. Every one is something a port can get wrong on its own.
const STRIKE_FIELDS := ["hit", "crit", "dmg", "wardSoaked", "toHp", "wardLeft", "spendsOwnWard"]
const STATUS_FIELDS := ["applied", "refusedBecause", "statuses", "ccResist", "seconds",
	"lurch", "ccMeterTouched"]
const TICK_FIELDS := ["hp", "mp", "statuses", "mods", "cooldowns", "ccResist", "dead",
	"expired", "attrition"]


func _ready() -> void:
	var failures := 0
	failures += _run("combat.json", _strike_case)
	failures += _run("derive.json", _derive_case)
	failures += _run("status.json", _status_case)
	failures += _run("tick.json", _tick_case)
	failures += _run("classify.json", _classify_case)
	failures += _check_data()
	print("")
	if failures == 0:
		print("PASS  every contract matches TypeScript exactly")
	else:
		print("FAIL  %d cases differ across all contracts" % failures)
	# ⚠️ EXIT CODE IS THE RESULT. A headless run that prints FAIL and exits 0 is a green CI
	# light on a broken port.
	get_tree().quit(0 if failures == 0 else 1)


func _run(file: String, runner: Callable) -> int:
	var path := "res://data/" + file
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("FAIL  %s missing — run ./run_contract.sh" % path)
		return 1
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		print("FAIL  %s is not valid JSON" % file)
		return 1

	var contract: Dictionary = parsed
	var cases: Array = contract.get("cases", [])
	print("── %s  %d cases  %s" % [file, cases.size(), contract.get("subject", "?")])
	if cases.is_empty():
		print("FAIL  %s carries no cases" % file)
		return 1

	var failures := 0
	var by_axis := {}
	var fail_axis := {}
	for case in cases:
		var axis: String = case["axis"]
		by_axis[axis] = int(by_axis.get(axis, 0)) + 1
		var diffs: Array = runner.call(case)
		if not diffs.is_empty():
			failures += 1
			fail_axis[axis] = int(fail_axis.get(axis, 0)) + 1
			print("  FAIL  [%s] %s" % [axis, case["name"]])
			for d in diffs:
				print("          %s" % d)

	var axes: Array = by_axis.keys()
	axes.sort()
	if failures == 0:
		var line := ""
		for axis in axes:
			line += "%s(%d) " % [axis, int(by_axis[axis])]
		print("  ok  " + line.strip_edges())
	else:
		for axis in axes:
			if fail_axis.has(axis):
				print("      %-20s %d/%d fail" % [axis, int(fail_axis[axis]), int(by_axis[axis])])
	return failures


# ── per-contract runners ─────────────────────────────────────────────────────

func _strike_case(case: Dictionary) -> Array:
	var got: Dictionary = DamageMath.resolve_strike(case["input"])
	return _diff_fields(got, case["expect"], STRIKE_FIELDS)


## `tick.json` mixes the per-unit tick with the standalone sudden-death curve; the latter has
## its own tiny signature, so it dispatches on the axis.
func _tick_case(case: Dictionary) -> Array:
	if case["axis"] == "suddenDeath":
		var inp: Dictionary = case["input"]
		var got := TickLib.sudden_death_loss(
			float(inp["now"]), float(inp["maxHp"]), float(inp["dt"]))
		var want = (case["expect"] as Dictionary)["loss"]
		if _same(got, want):
			return []
		return ["loss: got %s want %s" % [str(got), str(want)]]
	return _diff_fields(TickLib.tick_unit(case["input"]), case["expect"], TICK_FIELDS)


## `classify.json` mixes four unrelated signatures, so it dispatches on the axis.
func _classify_case(case: Dictionary) -> Array:
	var inp: Dictionary = case["input"]
	var want = case["expect"]
	match case["axis"]:
		"classForStats":
			var got := ClassifyLib.class_for_stats(inp)
			return [] if got == want else ["got %s want %s" % [got, str(want)]]
		"roleOfClass":
			var got2 := ClassifyLib.role_of_class(inp["className"])
			return [] if got2 == want else ["got %s want %s" % [got2, str(want)]]
		"manaRoleOf":
			var cls = inp.get("className")
			if cls == null:
				cls = ClassifyLib.class_for_stats(inp["stats"])
			var got3 := ClassifyLib.mana_role_of(inp["stats"], cls)
			return [] if got3 == want else ["got %s want %s" % [got3, str(want)]]
		"basicAttackFor":
			var got4 := ClassifyLib.basic_attack_for(inp["stats"])
			return _diff_fields(got4, want,
				["channel", "stat", "power", "range", "cooldown", "accuracy", "castTime"])
	return ["unknown axis '%s'" % case["axis"]]


func _status_case(case: Dictionary) -> Array:
	var got: Dictionary = StatusMathLib.apply_status(case["input"])
	return _diff_fields(got, case["expect"], STATUS_FIELDS)


## `derive.json` mixes eight unrelated signatures, so it dispatches on the axis rather than
## sharing one shape. Each branch names the function under test.
func _derive_case(case: Dictionary) -> Array:
	var inp: Dictionary = case["input"]
	var want = case["expect"]
	var got
	match case["axis"]:
		"maxHp":
			got = DeriveMath.max_hp(float(inp["CON"]))
		"maxMana":
			got = DeriveMath.max_mana(float(inp["WIS"]), float(inp["INT"]))
		"manaCost":
			got = DeriveMath.mana_cost(_move_from(inp))
		"fieldMpCost":
			got = DeriveMath.field_mp_cost(_move_from(inp))
		"regen":
			got = DeriveMath.regen_per_sec(float(inp["WIS"]), bool(inp["support"]))
		"castTime":
			got = DeriveMath.cast_time_of(inp)
		"cooldown":
			got = DeriveMath.cooldown_seconds(inp)
		"roundsToSeconds":
			got = DeriveMath.rounds_to_seconds(float(inp["rounds"]))
		_:
			return ["unknown axis '%s' — the contract grew a case this harness cannot run"
				% case["axis"]]
	if _same(got, want):
		return []
	return ["got %s want %s" % [str(got), str(want)]]


## Rebuild a move dictionary from a flattened derive-case input. `hits` is authored at the top
## level for readability and lives under `effects` in the real shape.
func _move_from(inp: Dictionary) -> Dictionary:
	var move := {
		"power": inp.get("power", 0),
		"type": inp.get("type", "damage"),
		"channel": inp.get("channel", "melee"),
	}
	if inp.has("mana"):
		move["mana"] = inp["mana"]
	if inp.has("hits"):
		move["effects"] = {"hits": inp["hits"]}
	return move


# ── comparison ───────────────────────────────────────────────────────────────

func _diff_fields(got: Dictionary, want: Dictionary, fields: Array) -> Array:
	var diffs: Array = []
	for key in fields:
		if not _same(got.get(key), want.get(key)):
			diffs.append("%s: got %s want %s" % [key, str(got.get(key)), str(want.get(key))])
	return diffs


## Compare a GDScript result against a JSON-parsed expectation.
##
## ⚠️ JSON HAS ONE NUMBER TYPE AND GDSCRIPT HAS TWO. `JSON.parse_string` returns every number as
## a float, so an integer `dmg` of 112 arrives as `112.0` and a strict comparison would fail
## every numeric case for no real reason. Compare bools strictly, numbers by value, and recurse
## through the containers so a status list is compared element by element rather than by
## reference.
func _same(got, want) -> bool:
	if got == null or want == null:
		return got == null and want == null
	if got is bool or want is bool:
		return (got is bool) == (want is bool) and bool(got) == bool(want)
	if (got is int or got is float) and (want is int or want is float):
		return is_equal_approx(float(got), float(want))
	if got is Array and want is Array:
		if got.size() != want.size():
			return false
		for i in got.size():
			if not _same(got[i], want[i]):
				return false
		return true
	if got is Dictionary and want is Dictionary:
		if got.size() != want.size():
			return false
		for k in got:
			if not want.has(k) or not _same(got[k], want[k]):
				return false
		return true
	return got == want


## ── the DATA check ───────────────────────────────────────────────────────────
##
## ⚠️ DATA IS EXPORTED, NOT PORTED, SO WHAT IS TESTED IS COMPLETENESS, NOT ARITHMETIC.
## 141 moves and 65 species are TABLES; rewriting them as GDScript literals would create a
## second copy that drifts the first time anyone retunes a number. What can still go wrong is a
## serialiser silently dropping a field, so this asserts the shapes a port actually consumes.
func _check_data() -> int:
	var f := FileAccess.open("res://data/data.json", FileAccess.READ)
	if f == null:
		print("FAIL  data.json missing — run ./run_contract.sh")
		return 1
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		print("FAIL  data.json is not valid JSON")
		return 1
	var d: Dictionary = parsed
	print("── data.json  %d tables" % (d.size() - 2))

	var problems: Array[String] = []

	# ⚠️ COUNTS ARE TRIPWIRES, NOT TRIVIA. The pool has been 141 since the rework; a drop means
	# the exporter lost rows, and a rise means content landed that nothing here has judged.
	# ⚠️ `innateEffects` IS THE NEWEST AND THE EASIEST TO LOSE. Species innate NAMES have
	# always travelled; their numeric EFFECTS did not reach Godot at all until 2026-08-03,
	# so 130 entries of species identity arrived as flavour text with no mechanism behind
	# them. A count alone would not have caught that - the names were present the whole
	# time - which is why the name-resolution check below matters more than the number.
	var counts := {"moves": 141, "species": 65, "classes": 18, "lineOf": 141,
		"fieldStatus": 15, "innateEffects": 130}
	for key in counts:
		var got: int = (d[key] as Array).size() if d[key] is Array else (d[key] as Dictionary).size()
		if got != int(counts[key]):
			problems.append("%s: %d rows, expected %d" % [key, got, int(counts[key])])

	# Every move must carry the fields the engine reads. `range` is the axis most likely to be
	# dropped by a hand-written serialiser, and a move without one is unreachable.
	var missing := 0
	for m in d["moves"]:
		for key in ["id", "name", "stat", "channel", "power", "accuracy", "cooldown", "range"]:
			if not m.has(key) or m[key] == null:
				if missing < 5:
					problems.append("move '%s' has no %s" % [m.get("name", "?"), key])
				missing += 1

	# ⚠️ EVERY MOVE MUST APPEAR IN `lineOf`. A lineless move is invisible to affinity and
	# silently unpickable — the exact failure that made three waves of authored content
	# unreachable and cost the whole lines rework to fix.
	var line_of: Dictionary = d["lineOf"]
	for m in d["moves"]:
		if not line_of.has(m["name"]) and not line_of.has(m["id"]):
			problems.append("move '%s' is not in lineOf" % m.get("name", "?"))
			break

	# ⚠️ EVERY SPECIES INNATE NAME MUST RESOLVE TO AN EFFECT. This is the check that would
	# have caught the real bug: the names shipped, the effects did not, and nothing failed.
	var effects: Dictionary = d.get("innateEffects", {})
	var unresolved := 0
	for sp in d["species"]:
		for ab in sp.get("innate", []):
			if not effects.has(ab["name"]):
				if unresolved < 5:
					problems.append("innate \"%s\" (%s) has no effect entry"
						% [ab["name"], sp.get("name", "?")])
				unresolved += 1
	if unresolved > 5:
		problems.append("...and %d more unresolved innates" % (unresolved - 5))

	# Every hard-control status must exist in the behaviour table, or `apply_status` would
	# diminish something the engine cannot then describe.
	var fs: Dictionary = d["fieldStatus"]
	for k in d["hardControlStatuses"]:
		if not fs.has(k):
			problems.append("hard control '%s' has no fieldStatus rule" % k)

	if problems.is_empty():
		print("  ok  moves(141) species(65) classes(18) lineOf(141) fieldStatus(15) "
			+ "innateEffects(%d) classBasic(%d) leagues(%d)"
			% [effects.size(), (d["classBasic"] as Dictionary).size(),
			(d["leagues"] as Array).size()])
		return 0
	for p in problems:
		print("  FAIL  %s" % p)
	return problems.size()
