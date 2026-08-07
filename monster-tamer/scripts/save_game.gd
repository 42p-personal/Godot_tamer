## SAVE / LOAD — round-trips Career's run state + Roster's stable to one human-readable JSON file.
##
## Autoload singleton. `user://save.json`, a plain JSON object — this is a vertical slice, not a
## shipping save format, so no binary encoding, no versioned migration chain, just a `version`
## field so a future format change has somewhere to branch.
##
## ⚠️ DERIVED MONSTER FIELDS ARE NEVER STORED. `class_name_`/`role`/`mana_role`/`basic_attack`/
## `max_hp`/`max_mp`/`moveset` are recomputed on load via the same `recompute_class()` /
## `recompute_pools()` / `assign_moveset()` calls `GameData.make_monster()` already uses for a
## freshly generated monster — class is emergent by design (classify.gd), so storing it would let
## a save silently disagree with what the monster's own current stats say it is. Only
## `species_id` and the six raw `stats` are persisted; everything else rebuilds from those plus
## the species table.
extends Node

const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Serialise the current Career + Roster state and write it. Returns true on success.
func save_game() -> bool:
	var data := {
		"version": SAVE_VERSION,
		"career": _serialize_career(),
		"roster": _serialize_roster(),
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("save_game: cannot open %s for writing" % SAVE_PATH)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


## Load a save into `Career` + `Roster`. Returns true if a save was found and successfully
## applied. Returns false — WITHOUT mutating `Career`/`Roster` and without crashing — if there is
## no save file, or it exists but is corrupt/unreadable/from an incompatible future format.
## Callers should treat false as "start a new game" (e.g. call `Career.reset_new_game()` and let
## `Roster` keep its own freshly-generated starting stable), not as an error to surface loudly.
func load_game() -> bool:
	if not has_save():
		return false

	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		push_warning("load_game: %s exists but could not be opened — treating as no save" % SAVE_PATH)
		return false
	var text := f.get_as_text()
	f.close()

	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("load_game: %s did not parse to a Dictionary — treating as no save" % SAVE_PATH)
		return false

	var career_data = parsed.get("career")
	var roster_data = parsed.get("roster")
	if not (career_data is Dictionary) or not (roster_data is Array):
		push_warning("load_game: %s is missing expected fields — treating as no save" % SAVE_PATH)
		return false

	var monsters: Array = _deserialize_roster(roster_data)
	if monsters.is_empty() and not roster_data.is_empty():
		# Every entry failed to rebuild (e.g. a species id from a newer/edited save that no
		# longer exists) — refuse the whole load rather than hand the game an empty stable.
		push_warning("load_game: no monster in the save could be rebuilt — treating as no save")
		return false

	_deserialize_career(career_data)
	Roster.monsters = monsters
	var selected: int = int(career_data.get("selectedIndex", 0))
	Roster.selected_index = clampi(selected, 0, maxi(0, monsters.size() - 1))
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


# ── career ────────────────────────────────────────────────────────────────

func _serialize_career() -> Dictionary:
	return {
		"leagueIndex": Career.league_index,
		"gold": Career.gold,
		"week": Career.week,
		"leaguesWon": Career.leagues_won,
		"wonGame": Career.won_game,
		"selectedIndex": Roster.selected_index,
	}


func _deserialize_career(d: Dictionary) -> void:
	var max_idx: int = maxi(0, Career.leagues.size() - 1)
	Career.league_index = clampi(int(d.get("leagueIndex", 0)), 0, max_idx)
	Career.gold = int(d.get("gold", Career.STARTING_GOLD))
	Career.week = maxi(1, int(d.get("week", 1)))
	Career.won_game = bool(d.get("wonGame", false))

	Career.leagues_won.resize(Career.leagues.size())
	Career.leagues_won.fill(false)
	var lw = d.get("leaguesWon", [])
	if lw is Array:
		for i in range(mini(lw.size(), Career.leagues_won.size())):
			Career.leagues_won[i] = bool(lw[i])


# ── roster ────────────────────────────────────────────────────────────────

func _serialize_roster() -> Array:
	var out: Array = []
	for m in Roster.monsters:
		out.append(_serialize_monster(m))
	return out


func _serialize_monster(m) -> Dictionary:
	var stats_out := {}
	for stat in Classify.STATS:
		stats_out[stat] = m.stats.get(stat, 0.0)
	return {
		"speciesId": m.species_id,
		"stats": stats_out,
	}


## Rebuild `MonsterInstance`s from saved (species_id, stats) pairs, skipping and warning on any
## entry whose species no longer exists rather than failing the whole load.
func _deserialize_roster(arr: Array) -> Array:
	var out: Array = []
	for entry in arr:
		if not (entry is Dictionary):
			continue
		var species_id: String = str(entry.get("speciesId", ""))
		if species_id == "" or not GameData.species_by_id.has(species_id):
			push_warning("load_game: unknown species id '%s' — skipping that monster" % species_id)
			continue
		var stats = entry.get("stats", {})
		if not (stats is Dictionary):
			continue

		var sp: Dictionary = GameData.species_by_id[species_id]
		var mi = MonsterInstanceScript.new()
		mi.species_id = species_id
		mi.species_name = sp.get("name", species_id)
		mi.body = sp.get("body", "")
		mi.flavour = sp.get("flavour", "")
		mi.innate = sp.get("innate", [])
		for stat in Classify.STATS:
			mi.stats[stat] = float(stats.get(stat, 10.0))

		mi.recompute_class()
		mi.recompute_pools()
		var load_rng := RandomNumberGenerator.new()
		mi.assign_moveset(load_rng)
		# ⚠️ Food taste isn't persisted (see the class doc note above — only species_id + stats
		# are saved), so it re-rolls on load same as the moveset does on this same line already.
		# A real save format would persist it; this mockup format doesn't yet.
		var prefs: Dictionary = GameData._pick_food_prefs(load_rng)
		mi.favourite_food = prefs["fav"]
		mi.hated_food = prefs["hated"]
		mi.hp = mi.max_hp
		mi.mp = mi.max_mp
		out.append(mi)
	return out
