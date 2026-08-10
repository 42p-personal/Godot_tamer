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
##
## ⚠️ ONE EXCEPTION AS OF v3, AND IT IS THE POINT OF THE EXCEPTION: `assignedClass` IS STORED.
## A class the player COMMITTED to is not derived — it is the single most consequential decision
## they make about a monster (round 15: kit alignment is the largest measured lever in the game),
## and a decision that a save/load re-derives is a decision that does not exist. It is still true
## that `class_name_` is never stored: the stored thing is the COMMITMENT, and `class_name_` is
## still recomputed from it on load. "" means the monster never committed, which is what every
## v1/v2 save reads back as, and those monsters derive exactly as before.
##
## ⚠️ "DERIVED" IS NOT THE SAME AS "EARNED", AND v1 CONFLATED THEM. The first format saved six
## stats and nothing else, so a save/load quietly wiped every number the player had spent a week
## or a purse on: the barn extension bought at the Shop (career.gd:barn_capacity), the licences
## (`Career` metas), the frozen monsters in the Lab (`Roster.frozen` — which also stopped their
## rent), and each monster's stamina, happiness, age, career length and food tastes. Barn capacity
## was the worst of them: Bronze fields three monsters and the barn starts at two, so a player who
## paid 320g for room three and then reloaded was silently walled out of the team leagues with no
## message and no refund. Found by `scripts/_probe_career_loop.gd`, which now pins all of it.
##
## ⚠️ AGE AND STAMINA ARE NOT COSMETIC EITHER — resetting them on load makes save-scumming a
## mechanic: reload for a full stamina bar, reload to un-age a monster near the end of its
## lifespan. State the CLOCK touches has to survive the clock.
extends Node

const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const SAVE_PATH := "user://save.json"

## 1 — stats only. 2 — the career state a player actually earns (barn, licences, freezer) plus
## each monster's weekly-tick state. A v1 file still loads: every v2 field falls back to the value
## a fresh monster/career would have, which is exactly what v1 was doing implicitly.
const SAVE_VERSION := 3

## Licences ride along in `Career.licences` (a real Dictionary — `career.gd:holds_licence()`
## explains why it is not `set_meta`), so this format persists that dictionary wholesale rather
## than enumerating names it would then have to be kept in step with.


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Serialise the current Career + Roster state and write it. Returns true on success.
func save_game() -> bool:
	var data := {
		"version": SAVE_VERSION,
		"career": _serialize_career(),
		"roster": _serialize_roster(),
		"frozen": _serialize_frozen(),
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
	var frozen_data = parsed.get("frozen", [])
	Roster.frozen = _deserialize_roster(frozen_data) if frozen_data is Array else []
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
		"barnCapacity": Career.barn_capacity,
		"licences": Career.licences.duplicate(),
		"leaguesWon": Career.leagues_won,
		"wonGame": Career.won_game,
		"selectedIndex": Roster.selected_index,
	}


func _deserialize_career(d: Dictionary) -> void:
	var max_idx: int = maxi(0, Career.leagues.size() - 1)
	Career.league_index = clampi(int(d.get("leagueIndex", 0)), 0, max_idx)
	Career.gold = int(d.get("gold", Career.STARTING_GOLD))
	# ⚠️ `maxi(0, ...)`, not the `maxi(1, ...)` this used to be: a career genuinely starts on week 0
	# (`career.gd:reset_new_game()` mirrors `town.ts:newGame()`), so clamping to 1 silently
	# fast-forwarded a save taken before the player's first week had turned.
	Career.week = maxi(0, int(d.get("week", 0)))
	Career.barn_capacity = maxi(Career.STARTING_BARN_CAPACITY, int(d.get("barnCapacity", Career.STARTING_BARN_CAPACITY)))
	Career.won_game = bool(d.get("wonGame", false))

	var licences = d.get("licences", {})
	Career.licences = (licences as Dictionary).duplicate() if licences is Dictionary else {}

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


func _serialize_frozen() -> Array:
	var out: Array = []
	for m in Roster.frozen:
		out.append(_serialize_monster(m))
	return out


func _serialize_monster(m) -> Dictionary:
	var stats_out := {}
	for stat in Classify.STATS:
		stats_out[stat] = m.stats.get(stat, 0.0)
	return {
		"speciesId": m.species_id,
		"stats": stats_out,
		# ⚠️ `id` is the career-slot key `week_plan.gd` files plans under AND the seed key
		# `week.gd` rolls training off. Regenerating it on load would re-roll every future
		# training result for a monster mid-career.
		"id": m.id,
		# ⚠️ THE ONE FIELD THAT IS STORED RATHER THAN DERIVED, AND IT MUST NOT RIDE ON `id`.
		# Lineage rides the `id` string precisely because every field in that token is FIXED AT
		# BIRTH — `week.gd` seeds the training roll off `mi.id`, so a mutable token would silently
		# re-roll a monster's entire remaining career the moment the player reassigned. A class
		# commitment is mutable by definition, so it needs a real field. "" = uncommitted, which
		# is what every v1/v2 save reads back as, which is the whole migration.
		"assignedClass": m.assigned_class,
		"stamina": m.stamina,
		"happiness": m.happiness,
		"ageWeeks": m.age_weeks,
		"careerWeek": m.career_week,
		"retired": m.retired,
		"potential": m.potential,
		"lifespanYears": m.lifespan_years,
		"favouriteFood": m.favourite_food,
		"hatedFood": m.hated_food,
		"lastFood": m.last_food,
		"children": int(m.get_meta("children", 0)),
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

		# ⚠️ READ THE COMMITMENT BEFORE `recompute_class()`, NOT AFTER. This line IS the save
		# migration and it is a fallback read, not a script: absent `assignedClass` => "" =>
		# `recompute_class()` derives exactly as it always has, so every existing save loads with
		# every monster keeping the class it has always had and nobody loses a roster. Ordering is
		# load-bearing — set after the recompute and the first weekly tick would quietly re-derive
		# over the player's choice, which is the exact failure docs/CLASS_REWORK.md §10.2 exists
		# to prevent.
		mi.assigned_class = str(entry.get("assignedClass", ""))
		mi.recompute_class()
		mi.recompute_pools()
		var load_rng := RandomNumberGenerator.new()
		mi.assign_moveset(load_rng)

		# ── the state the weekly clock touches (v2). Every field falls back to what a fresh
		# monster would have, so a v1 save still loads without a migration branch. ──
		mi.id = str(entry.get("id", ""))
		if mi.id == "":
			mi.id = Roster.next_slot_id()
		else:
			Roster._bump_slot_counter_past(mi.id)
		mi.stamina = float(entry.get("stamina", mi.stamina))
		mi.happiness = int(entry.get("happiness", mi.happiness))
		mi.age_weeks = int(entry.get("ageWeeks", mi.age_weeks))
		mi.career_week = int(entry.get("careerWeek", mi.career_week))
		mi.retired = bool(entry.get("retired", false))
		mi.potential = float(entry.get("potential", mi.potential))
		mi.lifespan_years = float(entry.get("lifespanYears", mi.lifespan_years))
		mi.set_meta("children", int(entry.get("children", 0)))

		# ⚠️ Food taste is a per-monster identity the feeding screen shows and the tick prices —
		# re-rolling it on load would change which food the player's monster likes between
		# sessions. v1 saves have none, so those still re-roll, which is the old behaviour.
		var prefs: Dictionary = GameData._pick_food_prefs(load_rng)
		mi.favourite_food = str(entry.get("favouriteFood", prefs["fav"]))
		mi.hated_food = str(entry.get("hatedFood", prefs["hated"]))
		mi.last_food = str(entry.get("lastFood", ""))

		mi.hp = mi.max_hp
		mi.mp = mi.max_mp
		out.append(mi)
	return out
