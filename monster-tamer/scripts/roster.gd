## PLAYER ROSTER — autoload holding the mockup's stable for the session.
##
## No save format, no career/week clock (see docs/META_GAME_DISPOSITION.md — the weekly tick and
## career state are a future port, not this mockup). On first access this generates a small,
## varied starting stable so the stable screen has something real to look at immediately.
extends Node

var monsters: Array = []  # Array[MonsterInstance]
var selected_index: int = 0

## ⚠️ CRYO STORAGE — monsters kept out of the barn without being lost (scripts/ui/lab_ui.gd).
## Deliberately a SEPARATE array from `monsters`: everything that iterates the stable — the weekly
## tick, tournaments, breeding — must NOT see frozen monsters, and keeping them in one list behind
## a flag is how that gets forgotten exactly once and then ages a frozen monster for a year.
var frozen: Array = []
var rng := RandomNumberGenerator.new()

## Monotonic counter behind `next_slot_id()`. Not saved: ids themselves are saved, and
## `_bump_slot_counter_past()` re-floors this above every loaded id so a post-load recruit can
## never collide with one already in the stable.
var _slot_counter: int = 0


## A UNIQUE CAREER-SLOT ID for a monster entering the stable.
##
## ⚠️ THIS EXISTS BECAUSE `GameData.make_monster()` LEAVES `id` EMPTY AND NOBODY NOTICED. Every
## recruit bought at the Market therefore had `id == ""` — and `week_plan.gd` keys its plans by
## `mi.id` while `week.gd` seeds the training roll off `"%s:%d" % [mi.id, mi.career_week]`. With
## two monsters in the barn that meant ONE shared plan slot (booking a drill for one booked it for
## both) and one shared RNG stream (identical rolls). It was invisible at a one-monster Wood
## stable and would have gone wrong the moment the player bought their second monster.
## `breeding_ui.gd` was already assigning its own ids, which is what made the gap easy to miss.
func next_slot_id() -> String:
	_slot_counter += 1
	return "slot-%d" % _slot_counter


## Raise the counter above any numeric slot id already present, so ids stay unique across a load.
func _bump_slot_counter_past(id: String) -> void:
	if not id.begins_with("slot-"):
		return
	_slot_counter = maxi(_slot_counter, id.trim_prefix("slot-").to_int())

## ⚠️ THE STABLE DRAWS FROM `Art.ROSTER`, NOT FROM ALL 65 SPECIES, AND THAT IS DELIBERATE.
## This list used to be five hand-picked ids topped up with random species from `data.json`.
## That was fine when nothing had art — but this build paints exactly twelve creatures, and a
## roster drawn from all sixty-five fills the stable with placeholder initials for species whose
## art will never exist in this slice. Seeing your monsters is the point of the stable screen;
## a roster that mostly can't be seen defeats it.
##
## The twelve are chosen for body and role spread (see `art.gd:ROSTER` and
## `docs/SLICE_DECISIONS_2026-08-04.md` §1), so this costs variety of silhouette, not variety of
## play — class is emergent, so these twelve still train into most of the eighteen classes.
func _starter_species() -> Array:
	return Art.ROSTER.duplicate()


## ⚠️ DO NOT GENERATE A STARTING ROSTER HERE. This autoload used to call
## `_generate_starting_roster()` on boot, which is why a New Career showed the player six
## finished monsters in the stable at week 1 — the exact thing the user reported as "the initial
## screen once ive hit new game is already wrong".
##
## `town.ts:582 newGame()` starts with `stable: []`. Buying your FIRST monster is the player's
## first real decision, it costs gold they cannot spare, and the barn holds two. Handing them a
## team deletes the opening of the game. The stable is filled by the Market, or by a save load —
## never by this function.
##
## `_generate_starting_roster()` is kept below because `make_rival_team()` and the sandbox still
## want a deterministic pool to draw from; it is simply no longer called at boot.
func _ready() -> void:
	rng.seed = 20260804


func _generate_starting_roster() -> void:
	monsters.clear()
	# Six of the painted twelve, drawn deterministically off this node's seeded rng so a New
	# Career is reproducible. The other six remain available to `make_rival_team`, so the player
	# meets creatures they don't own — the stable should not be the whole bestiary.
	var picked: Array = []
	for id in _starter_species():
		if GameData.species_by_id.has(id) and not picked.has(id):
			picked.append(id)
	# Fisher-Yates on the seeded rng (NOT `Array.shuffle()`, which reseeds from Godot's global
	# state and would make the starting stable differ run to run).
	for i in range(picked.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = picked[i]
		picked[i] = picked[j]
		picked[j] = tmp
	picked = picked.slice(0, 6)

	for id in picked:
		# Stagger training_level so the roster shows monsters at different points in their
		# career, not six identical fresh recruits — 0.0 (wild) up to 0.55 (well underway).
		var t := rng.randf_range(0.0, 0.55)
		var mi = GameData.make_monster(id, t, rng)
		mi.id = next_slot_id()   # ⚠️ see next_slot_id() — an empty id collides in WeekPlan
		monsters.append(mi)


func selected():
	if monsters.is_empty():
		return null
	return monsters[clampi(selected_index, 0, monsters.size() - 1)]


## Empties the stable entirely. This is the "real" starting state for a genuine New Career
## (docs/CORE_LOOP_PORT.md §1 — `town.ts:newGame()` gives the player `stable: []`, never a
## pre-made team) — called from title_ui.gd's New Career handler alongside
## `Career.reset_new_game()`. `_generate_starting_roster()` above stays as-is and keeps firing
## from `_ready()`, because that's what lets stable.tscn/training.tscn/sandbox.tscn etc. still run
## standalone (F6, no title screen) with something real to look at; a true New Career overrides it
## immediately with this.
func reset_to_empty() -> void:
	frozen.clear()
	monsters.clear()
	selected_index = 0
	_slot_counter = 0


## Build a plausible rival team of the same size as the player's fielded team, drawn from
## species the player does NOT currently field, at a comparable training level — enough for a
## real fight, not tuned opposition (see docs/META_GAME_DISPOSITION.md on rival-team disposition).
func make_rival_team(size: int, avg_training_level: float) -> Array:
	var used_ids := {}
	for m in monsters:
		used_ids[m.species_id] = true
	# ⚠️ Rivals come from the PAINTED roster too, for the same reason the stable does — an
	# opponent the player cannot see is worse than an opponent they don't own. Prefer species the
	# player isn't fielding, but fall back to the full painted set rather than returning an empty
	# team when the player owns most of it (at 6 owned of 12, a 5v5 would otherwise run dry).
	var unowned: Array = Art.ROSTER.filter(func(id): return not used_ids.has(id))
	var pool: Array = unowned if unowned.size() >= size else Art.ROSTER.duplicate()
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var team: Array = []
	for i in range(size):
		var t: float = clampf(avg_training_level + rng.randf_range(-0.1, 0.1), 0.0, 1.0)
		team.append(GameData.make_monster(pool[i % pool.size()], t, rng))
	return team
