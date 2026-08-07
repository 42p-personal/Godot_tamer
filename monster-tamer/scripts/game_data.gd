## GAME DATA — loads data.json once and exposes lookups + a monster factory.
##
## Autoload singleton (see project.godot [autoload]). This is the mockup's ONLY reader of
## data.json outside the contract scripts, which already load it themselves (Classify,
## StatusMath, Tick each cache their own copy). Duplicating the parse here is deliberate —
## those three are pure-math contract classes and stay decoupled from anything gameplay-shaped.
##
## ⚠️ THIS IS A SKELETON MOCKUP, NOT THE PORTED META-GAME. `game.ts`/`town.ts` (4,170 lines of
## career, breeding, licensing, tournaments) are not ported here — see the open "meta-game
## disposition" question in docs/HANDOVER.md. What's built is the smallest real loop that
## exercises the VERIFIED contract math (Damage/Derive/StatusMath/Tick/Classify) end to end:
## pick a monster, train it, watch it fight. Everything about training curves, roster
## generation and rival strength is a plausible placeholder, not tuned data.
extends Node

## ⚠️ PRELOAD, NOT `class_name` RESOLUTION. `MonsterInstance`/`BattleSim` are new scripts and
## this project's own `.claude/docs/technical-preferences.md` already documents the failure mode:
## the global script-class cache is cold for a brand-new `class_name` until the editor has
## scanned the project once, and an autoload that references the bare name at boot fails with
## "not declared in the current scope" before that scan happens. `preload()` sidesteps the cache
## entirely — this file is an autoload, so it is exactly the boot-order-sensitive case the rule
## warns about.
const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")

const DATA_PATH := "res://data/data.json"

var species: Array = []
var moves: Array = []
var classes: Array = []
var line_of: Dictionary = {}
var class_lines: Dictionary = {}
var species_by_id: Dictionary = {}
var moves_by_line: Dictionary = {}  # line name -> Array[move dict], sorted by learnLevel
var field_status: Dictionary = {}   # status kind -> rule dict (mirrors StatusMath/Tick's own copy —
var innate_effects: Dictionary = {}   # ability NAME -> effect dict (the care loop reads this)
var bios: Dictionary = {}             # species id -> long-form in-game bio (bestiary lore)
                                     # exposed publicly here so battle_sim/monster_instance don't
                                     # reach into those contract classes' underscore-prefixed internals)

# ⚠️ THE FLAT PLACEHOLDER CAP IS GONE — the cap now comes from the LEAGUE.
# This was `const STAT_CAP := 900.0` with a comment admitting it stood in for
# `game.ts:statCapFor()` only because no career model existed. `career.gd` supplies one now, so
# training is bounded by the rung the player has actually reached (Wood 100 → Tamers Apex 1100).
# That makes the ladder change the GAME rather than only scale the numbers: a Wood monster is
# genuinely capped, and climbing is what unlocks growth.
#
# The fallback is the old 900 and exists for one reason: `Career` is an autoload, and a scene run
# directly (the contract test, or a screen opened standalone during development) may resolve this
# before/without it. A missing career must degrade to "trainable", never to "cap 0".
const STAT_CAP_FALLBACK := 900.0


func stat_cap() -> float:
	var career := get_node_or_null("/root/Career")
	if career == null:
		return STAT_CAP_FALLBACK
	return career.current_stat_cap()


# =============================================================================
# FOOD — the feeding phase's data table. Mirrors the FLAVOUR of src/core.ts's `NORMAL_FOODS`
# (4 flat-price rations, taste-based ±1 happiness) without its training/premium tiers — this is
## the smallest real version of "favourite/hated differ per monster, feeding costs gold, forage
## is the free stamina/happiness-costing fallback" (docs/CORE_LOOP_PORT.md §3/§4).
# =============================================================================
const FOODS := [
	{"id": "vegetables",   "name": "Vegetables",    "icon": "🥬", "price": 10},
	{"id": "fruit",        "name": "Fruit",         "icon": "🍎", "price": 10},
	{"id": "meat",         "name": "Meat",          "icon": "🍖", "price": 10},
	{"id": "sweet treats", "name": "Sweet Treats",  "icon": "🍰", "price": 10},
]


func food_by_id(id: String) -> Dictionary:
	for f in FOODS:
		if f["id"] == id:
			return f
	return {}


## Deterministic per-monster favourite/hated pick off a seeded rng — called once at generation
## (`make_monster`) so a monster's taste never drifts session to session. Distinct ids, always.
func _pick_food_prefs(rng: RandomNumberGenerator) -> Dictionary:
	var ids: Array = []
	for f in FOODS:
		ids.append(f["id"])
	var fav_idx := rng.randi_range(0, ids.size() - 1)
	var hated_idx := rng.randi_range(0, ids.size() - 1)
	while hated_idx == fav_idx:
		hated_idx = rng.randi_range(0, ids.size() - 1)
	return {"fav": ids[fav_idx], "hated": ids[hated_idx]}


# =============================================================================
# TRAINING APTITUDE — major/flaw per species (`Species.trainingProfile`, already in data.json),
# surfaced as a multiplier and a label so the training screen can finally SAY why a drill suits
# THIS monster (docs/CORE_LOOP_PORT.md §4: "already computed and is invisible in the UI today").
# ⚠️ Only major/flaw are ported — the ±10% body-type MINOR bonus needs a BODY_MINOR table that
# was never brought into data.json (see CLAUDE.md "Species Training Aptitude"). Two of the three
# tiers is still a real improvement over showing none; flagged rather than faked.
# =============================================================================
func aptitude_mult(species_id: String, stat: String) -> float:
	var sp: Dictionary = species_by_id.get(species_id, {})
	var profile: Dictionary = sp.get("trainingProfile", {})
	if profile.get("major", "") == stat:
		return 1.2
	if profile.get("flaw", "") == stat:
		return 0.8
	return 1.0


func aptitude_label(species_id: String, stat: String) -> String:
	var mult := aptitude_mult(species_id, stat)
	if mult > 1.0:
		return "★ Major aptitude +20%"
	if mult < 1.0:
		return "Flaw −20%"
	return ""


func _ready() -> void:
	_load()


func _load() -> void:
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("cannot open %s — run ./run_contract.sh first to populate data/" % DATA_PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Dictionary):
		push_error("data.json did not parse to a Dictionary")
		return

	species = parsed.get("species", [])
	moves = parsed.get("moves", [])
	classes = parsed.get("classes", [])
	line_of = parsed.get("lineOf", {})
	class_lines = parsed.get("classLines", {})
	field_status = parsed.get("fieldStatus", {})
	innate_effects = parsed.get("innateEffects", {})
	bios = parsed.get("bios", {})

	for s in species:
		species_by_id[s["id"]] = s

	for m in moves:
		var line: String = line_of.get(m["name"], "")
		if not moves_by_line.has(line):
			moves_by_line[line] = []
		moves_by_line[line].append(m)
	for line in moves_by_line:
		moves_by_line[line].sort_custom(func(a, b): return a["learnLevel"] < b["learnLevel"])


## Build a runtime monster from a species id at a given "training level" (0..1, how far through
## its stat curve it's progressed — a stand-in for weeks of career training).
func make_monster(species_id: String, training_level: float = 0.0, rng: RandomNumberGenerator = null):
	var sp: Dictionary = species_by_id.get(species_id, {})
	if sp.is_empty():
		push_error("unknown species id: %s" % species_id)
		return null

	var mi = MonsterInstanceScript.new()
	mi.species_id = species_id
	mi.species_name = sp["name"]
	mi.body = sp["body"]
	mi.flavour = sp.get("flavour", "")
	mi.innate = sp.get("innate", [])

	var base: Dictionary = sp["base"]
	for stat in Classify.STATS:
		mi.stats[stat] = float(base.get(stat, 10.0))

	# Nudge stats up toward the cap by training_level, weighted by trainingProfile (major/minor/flaw)
	# so training visibly favours the species' own aptitude — a light echo of game.ts's real
	# aptitude-weighted drill system, not a port of it.
	var profile: Dictionary = sp.get("trainingProfile", {})
	if training_level > 0.0:
		var cap := stat_cap()
		for stat in Classify.STATS:
			var mult := 1.0
			if profile.get("major") == stat:
				mult = 1.35
			elif profile.get("flaw") == stat:
				mult = 0.7
			var room: float = cap - mi.stats[stat]
			mi.stats[stat] += room * training_level * mult * 0.6
			mi.stats[stat] = minf(cap, mi.stats[stat])

	mi.recompute_class()
	mi.recompute_pools()
	# ⚠️ THE FALLBACK MUST BE DETERMINISTIC. This was `RandomNumberGenerator.new()` — ENTROPY
	# seeded — so any caller that did not pass an rng got a different moveset every process. That
	# is a straight violation of the determinism contract ("RNG is injected", SPATIAL_HANDOFF §1),
	# and it was found the expensive way: a probe timed out at 1801 frames in one run and resolved
	# in 435 in the "identical" next run, and half a day's seed-to-seed comparisons were quietly
	# comparing DIFFERENT MONSTERS. Variety is the caller's job — pass an rng for it. The default
	# is repeatable: same species + training level = same monster, every process, every machine.
	var use_rng := rng
	if use_rng == null:
		use_rng = RandomNumberGenerator.new()
		use_rng.seed = hash(species_id) + int(round(training_level * 1000.0))
	mi.assign_moveset(use_rng)
	var prefs := _pick_food_prefs(use_rng)
	mi.favourite_food = prefs["fav"]
	mi.hated_food = prefs["hated"]
	mi.hp = mi.max_hp
	mi.mp = mi.max_mp
	return mi


## Apply one training drill to a live monster (mockup version of drills.ts). Basic drills raise
## one stat modestly with no cost; intensive drills raise one stat more, at a flat cost to a
## second. Numbers approximate `src/drills.ts`'s BASIC_GAIN/INTENSIVE_GAIN bands, not copied
## exactly (that file rolls a happiness-weighted range per week; this is a single deterministic
## step sized for a demo — see the doc note at the top of this file).
func train(mi, stat: String, intensive: bool, paired_stat: String = "") -> Dictionary:
	var before_class: String = mi.class_name_
	var gain := 12.0 if intensive else 6.0
	# ⚠️ Room is measured against the CURRENT LEAGUE's cap, so a monster at the Wood ceiling
	# genuinely cannot be trained further until the player is promoted. That is the ladder doing
	# real work rather than merely scaling numbers — and it means `applied` can legitimately be 0,
	# which the UI must be able to say out loud rather than silently doing nothing.
	var room: float = maxf(0.0, stat_cap() - mi.stats[stat])
	var applied: float = minf(gain, room)
	mi.stats[stat] += applied

	var cost := 0.0
	if intensive and paired_stat != "" and paired_stat != stat:
		cost = minf(4.0, mi.stats[paired_stat])
		mi.stats[paired_stat] -= cost

	mi.recompute_class()
	mi.recompute_pools()
	# ⚠️ MUST RE-ROLL THE MOVESET HERE, NOT JUST CLASS/POOLS. `assign_moveset` draws from
	# `CLASS_LINES[class_name_]` — a class change with a stale moveset would show a Warrior still
	# fighting with its old Tank-affinity Warden/Guardian picks, which is exactly the kind of
	# "trained it but nothing downstream followed" bug this loop exists to avoid (caught by
	# inspecting the stable screen after a training pass moved Aegisox Tank -> Warrior).
	mi.assign_moveset(RandomNumberGenerator.new())
	mi.hp = minf(mi.hp, float(mi.max_hp))
	mi.mp = minf(mi.mp, float(mi.max_mp))

	return {
		"stat": stat, "gain": applied, "pairedStat": paired_stat, "cost": cost,
		"classBefore": before_class, "classAfter": mi.class_name_,
		"classChanged": before_class != mi.class_name_,
	}


## The long-form bestiary bio for a species, falling back to its one-line flavour. Screens
## should call this rather than read `bios` directly, so a species missing a long bio degrades
## to the short one instead of to an empty panel.
func bio_for(species_id: String) -> String:
	var b := str(bios.get(species_id, ""))
	if b != "":
		return b
	var sp: Dictionary = species_by_id.get(species_id, {})
	return str(sp.get("flavour", ""))
