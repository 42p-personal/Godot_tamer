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
##
## ⚠️ THE FREEZER IS ALSO THE STUD BOOK AND THE HALL OF FAME, AND THAT IS THE DESIGN, NOT A
## SHORTCUT. `src/town.ts:787` reads its breeding parents out of `labFrozen` and nowhere else —
## the Godot port dropped that and let any barn monster breed, which quietly deleted the only
## real decision in the system. Preserving a monster costs a weekly bill FOREVER
## (`week_plan.gd:RENTAL_PER_FROZEN`, charged on `frozen.size()`), so keeping a bloodline alive is
## a standing expense you chose to take on while the monster was still winning. That recurring
## cost is what makes a champion MATTER after its career: a trophy case is a display, a bill is a
## decision.
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


# ── the barn ↔ freezer traffic (lab_ui.gd, breeding_ui.gd) ───────────────────────────────────
# ⚠️ ONE PLACE, BECAUSE TWO SCREENS MOVE THE SAME MONSTERS. The Lab freezes and thaws; the
# Breeding Ranch preserves a parent inline so the player does not have to leave mid-decision.
# When those were two copies of `frozen.append(); monsters.remove_at()` the invariants below
# (never empty the barn, never overfill it, never leave a stale selection) had to hold in both.

## Preserve a barn monster into the freezer. Refuses to empty the barn UNLESS the monster is
## retired — a retiree cannot train, feed, or compete, so a barn holding only retirees is already
## a dead end and preserving the last one is the player's way out of it.
func preserve(mi) -> bool:
	var i: int = monsters.find(mi)
	if i < 0:
		return false
	if monsters.size() <= 1 and not mi.retired:
		return false
	monsters.remove_at(i)
	frozen.append(mi)
	selected_index = clampi(selected_index, 0, maxi(0, monsters.size() - 1))
	return true


## Thaw a preserved monster back into the barn. A retiree may be thawed — it just cannot do
## anything — so the caller (lab_ui) is the one that discourages it, not this.
func thaw(mi, barn_capacity: int) -> bool:
	var i: int = frozen.find(mi)
	if i < 0 or monsters.size() >= barn_capacity:
		return false
	frozen.remove_at(i)
	monsters.append(mi)
	return true


## Let a monster go, from either list. The end of a line: its stats, its potential and its
## heirloom stop existing. Irreversible by design — it is the alternative to paying rent forever.
func release(mi) -> bool:
	var i: int = frozen.find(mi)
	if i >= 0:
		frozen.remove_at(i)
		return true
	i = monsters.find(mi)
	if i >= 0 and (monsters.size() > 1 or mi.retired):
		monsters.remove_at(i)
		selected_index = clampi(selected_index, 0, maxi(0, monsters.size() - 1))
		return true
	return false


## Everything the Breeding Ranch and the Fusion bench may draw a parent from. ⚠️ Frozen ONLY —
## see the note on `frozen`. Retired monsters are INCLUDED: a champion that raced until it
## dropped and was preserved on its last day is exactly the founder a dynasty wants.
func breeding_stock() -> Array:
	return frozen


## Monsters occupying a barn slot that can no longer do anything with it.
func retirees_in_barn() -> Array:
	return monsters.filter(func(m): return m.retired)


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
## ⚠️ `room_mult` is threaded straight through to `GameData.make_monster` and defaults to the same
## 0.6 it always silently applied — see the note there. A caller whose `avg_training_level` is a
## literal chosen by feel (0.2/0.3/0.45) wants the default; a caller whose number is a FRACTION OF
## THE LEAGUE CEILING (`career.gd:field_fill`) must pass 1.0 or its arc is compressed by 1.66x.
func make_rival_team(size: int, avg_training_level: float, room_mult: float = 0.6) -> Array:
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
		team.append(GameData.make_monster(pool[i % pool.size()], t, rng, room_mult))
	return team
