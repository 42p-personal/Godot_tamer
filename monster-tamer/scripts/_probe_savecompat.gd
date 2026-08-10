## SAVE COMPATIBILITY, RUN RATHER THAN READ (round 17 integration).
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_savecompat.tscn
##
## ⚠️ THE BYTES MUST COME FROM THE OLD SERIALISER, NOT FROM A HAND-BUILT FIXTURE. A synthetic
## "v3 file" is written by someone who already knows what the new reader wants, so it tests the
## reader against its own assumptions. `scripts/_legacy_save_v3.gd` is `git show
## HEAD:scripts/save_game.gd` — the pre-round-17 file, unedited — instantiated and asked to write.
##
## What is asserted: the file is genuinely v3 and carries none of the round-17 keys; the live
## `SaveGame.load_game()` accepts it; THE ROSTER SURVIVES, monster for monster, with its stats;
## the career state survives; and the loaded career grades to something sane rather than
## crashing or reading a false verdict.
extends Node

const LegacyScript = preload("res://scripts/_legacy_save_v3.gd")
const SAVE_PATH := "user://save.json"

var _fail: Array = []


func _ready() -> void:
	var legacy = LegacyScript.new()
	add_child(legacy)

	# ── 1. A career worth reloading, written by the OLD code. ────────────────────────────────
	Career.reset_new_game()
	Career.week = 371
	Career.league_index = 6
	## ⚠️ `leagues_won` is Array[bool] parallel to `leagues`, NOT a count — assigning an int to it
	## is a PARSE error, which makes the script fail to load, which makes the probe hang forever
	## rather than fail. Cost me two ten-minute timeouts; a probe that cannot load is a probe that
	## cannot report.
	for i in range(mini(5, Career.leagues_won.size())):
		Career.leagues_won[i] = true
	Career.gold = 4210
	Career.won_game = false
	## ⚠️ AND THE BARN MUST NOT BE EMPTY. `reset_new_game()` clears the roster, so a probe that
	## measured "the roster survives" straight after it would compare 0 against 0 and PASS while
	## testing nothing — signature failure #2, an instrument that lies. Five real bodies, and a
	## canary below that fails if there are fewer than three.
	for i in range(5):
		Roster.monsters.append(GameData.make_monster(Art.ROSTER[i % Art.ROSTER.size()], 0.5))
	var before: Array = []
	for m in Roster.monsters:
		before.append({"id": m.id, "sp": m.species_id, "nick": m.species_name,
			"str": int(m.stats.get("STR", 0)), "con": int(m.stats.get("CON", 0)),
			"age": int(m.age_weeks)})
	_check(before.size() >= 3,
		"CANARY: the barn under test actually holds bodies (%d) — otherwise 'the roster survives' is vacuous" % before.size())
	var wrote: bool = legacy.save_game()
	_check(wrote, "the pre-round-17 serialiser wrote a save")
	_check(int(legacy.SAVE_VERSION) == 3, "…and it is version 3, not 4")

	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var raw: String = f.get_as_text()
	var parsed = JSON.parse_string(raw)
	_check(parsed is Dictionary and int(parsed["version"]) == 3,
		"the file on disk says version 3")
	var career_blob: Dictionary = parsed.get("career", {})
	_check(not career_blob.has("wonWeek"), "…and carries NO wonWeek (the round-17 field)")
	_check(not career_blob.has("frontier"), "…and NO frontier record")
	print("      legacy file: %d bytes, %d roster entries, week %d, leagueIndex %d" % [
		raw.length(), (parsed.get("roster", []) as Array).size(),
		int(career_blob.get("week", -1)), int(career_blob.get("leagueIndex", -1))])

	# ── 2. Wipe the live state, then load the old file with the NEW deserialiser. ────────────
	Career.reset_new_game()
	Roster.reset_to_empty()
	_check(Roster.monsters.is_empty(), "state wiped before the load (the load is what restores it)")
	var loaded: bool = SaveGame.load_game()
	_check(loaded, "SaveGame.load_game() accepts a v3 file written by the old code")

	# ── 3. THE ROSTER SURVIVES. This is the non-negotiable one. ──────────────────────────────
	_check(Roster.monsters.size() == before.size(),
		"the roster survives the load (%d of %d bodies)" % [Roster.monsters.size(), before.size()])
	var intact: int = 0
	for i in range(mini(Roster.monsters.size(), before.size())):
		var m = Roster.monsters[i]
		var b: Dictionary = before[i]
		if m.species_id == b["sp"] and m.species_name == b["nick"] \
				and int(m.stats.get("STR", 0)) == int(b["str"]) \
				and int(m.stats.get("CON", 0)) == int(b["con"]) \
				and int(m.age_weeks) == int(b["age"]):
			intact += 1
	_check(intact == before.size(),
		"…and every body keeps its species, name, stats and age (%d of %d)" % [intact, before.size()])
	_check(Career.week == 371 and Career.league_index == 6 and Career.titles_taken() == 5
			and Career.gold == 4210,
		"…and the career keeps its week/rung/titles/gold (wk %d, idx %d, %d titles, %dg)" % [
			Career.week, Career.league_index, Career.titles_taken(), Career.gold])

	# ── 4. IT ACQUIRES A SANE GRADE. Not "a grade" — a grade whose parts agree with the file. ─
	var g: Dictionary = Career.grade_result()
	print("      grades as: %s" % str(g.get("line", "")))
	_check(g.has("tier") and str(g["tier"]) != "", "the loaded career gets a tier")
	_check(not bool(g.get("final", true)), "…marked PROVISIONAL — this career has not won yet")
	_check(int(g.get("titles", -1)) == 5, "…and its title count matches the file (5)")
	var v: Dictionary = Career.frontier_verdict()
	print("      frontier verdict: %s — %s" % [str(v.get("state", "")), str(v.get("line", ""))])
	_check(str(v.get("state", "")) not in ["outclassed", "unlucky"],
		"…and an unknown frontier NEVER reads as a difficulty verdict (reads '%s')" % str(v.get("state", "")))

	# ── 5. RE-SAVE AND RE-LOAD: the upgraded file must round-trip too. ───────────────────────
	_check(SaveGame.save_game(), "the loaded career re-saves (now at v%d)" % SaveGame.SAVE_VERSION)
	var week_before: int = Career.week
	Career.reset_new_game()
	Roster.reset_to_empty()
	_check(SaveGame.load_game(), "…and the upgraded file loads back")
	_check(Career.week == week_before and Roster.monsters.size() == before.size(),
		"…with the same week and the same roster (v3 -> v4 loses nothing)")

	print("")
	if _fail.is_empty():
		print("=== save compat: PASS (v3 written by the old code loads clean on the new one) ===")
		get_tree().quit(0)
		return
	for x in _fail:
		print("  FAIL  %s" % x)
	print("=== save compat: FAIL (%d) ===" % _fail.size())
	get_tree().quit(1)
	return


func _check(ok: bool, what: String) -> void:
	print("   %s %s" % ["OK  " if ok else "FAIL", what])
	if not ok:
		_fail.append(what)
