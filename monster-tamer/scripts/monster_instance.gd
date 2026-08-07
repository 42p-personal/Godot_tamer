## A LIVE MONSTER — runtime state for the mockup's stable/training/battle loop.
##
## Wraps the pure contract math (Classify/Derive) with mutable state a battle or training
## session actually needs to track. Deliberately thin: no save format, no lifespan/happiness/
## bloodline fields — this is the skeleton loop, not a port of `Monster` in `src/monster.ts`.
class_name MonsterInstance
extends RefCounted

var species_id: String
var species_name: String
var body: String
var flavour: String
var innate: Array = []

## Stable identity for this career slot — used as the seed key for the weekly RNG
## (`week.gd`), so training rolls are deterministic per (monster, week) and never
## drift between preview and apply. Defaults to species_id so scripts that build a
## monster ad-hoc (tests, probes) still get a stable key without setting one.
var id: String = ""

var stats: Dictionary = {}  # Stat -> float, CURRENT (post-training) values

# ── career/weekly-tick state (docs/CORE_LOOP_PORT.md §3, ported from src/game.ts Career) ──
var stamina: float = 100.0       # 0..MAX_STAMINA (week.gd.MAX_STAMINA) — the training gate
var happiness: int = 5           # 0..MAX_HAPPINESS (week.gd.MAX_HAPPINESS)
var age_weeks: int = 48          # starts as a Teen (WEEKS_PER_YEAR), mirrors START_AGE_WEEKS
var career_week: int = 0         # weeks of TRAINING taken — the RNG seed key, distinct from age
var retired: bool = false
var fed_this_week: bool = false
var last_food: String = ""       # for satiety (same food twice running halves the happiness gain)
var favourite_food: String = ""
var hated_food: String = ""
var potential: float = 1.0       # bloodline potential — multiplies the league stat cap
var lifespan_years: float = 8.0  # careerSpanYears equivalent — species base + bonuses, flattened here
var log: Array = []              # Array[String], most-recent-last (week.gd trims to 40)

# ── weekly PLAN state (docs/CORE_LOOP_PORT.md §2) ────────────────────────────────────────────
# ⚠️ THIS IS THE FIX FOR "i can still train infintely... this game does not loop": the stable
# screen used to call GameData.train() the instant a drill button was clicked. Now clicking a
# drill only writes a PLAN here — stats/stamina/gold move ONLY when the feeding phase resolves
# the week (feeding_ui.gd:_resolve_week). Nothing is spent by planning, by design.
const MAX_STAMINA := 100.0
const BASIC_STAMINA_COST := 10.0
const INTENSIVE_STAMINA_COST := 25.0
# ⚠️ PLACEHOLDER, NOT A PORT — src/game.ts rolls rest recovery 30%..100% of MAX_STAMINA per
# week (game.ts:302-305). This is a flat mid-point stand-in (CLAUDE.md: "the port is a skeleton,
# not a specification" — reproduce the shape, not the exact roll) until week.gd owns this.
const REST_STAMINA_RESTORE := 60.0
# Free fallback feeding cost — forage never costs gold, only stamina + happiness (CORE_LOOP_PORT
# §3: "hunger is never free, it is only ever paid differently"). Placeholder magnitude.
const FORAGE_STAMINA_COST := 8.0
const FORAGE_HAPPINESS_COST := 1

var plan_kind: String = "none"   # "none" | "train" | "rest" — "none" means the week does nothing
var plan_stat: String = ""       # set when plan_kind == "train"
var plan_intensive: bool = false
var plan_paired_stat: String = ""

var planned_food: String = ""    # food id chosen in the feeding phase; "" == forage (free fallback)


## Stamina cost of the CURRENT plan (0 for "none"/"rest" — rest spends no stamina, it restores it).
func plan_stamina_cost() -> float:
	if plan_kind != "train":
		return 0.0
	return INTENSIVE_STAMINA_COST if plan_intensive else BASIC_STAMINA_COST


## True if this monster has enough CURRENT stamina to carry out its own plan right now. Checked
## both when the plan is set (training_ui.gd disables the button) and again when the week
## resolves (stamina may have dropped further from foraging in between — see feeding_ui.gd).
func can_afford_plan() -> bool:
	return stamina >= plan_stamina_cost() - 0.001


func clear_plan() -> void:
	plan_kind = "none"
	plan_stat = ""
	plan_intensive = false
	plan_paired_stat = ""

# ── derived, recomputed whenever stats change ────────────────────────────────
var class_name_: String = "Generalist"
var role: String = "damage"
var mana_role: String = "damage"
var basic_attack: Dictionary = {}
var max_hp: int = 1
var max_mp: int = 0
var moveset: Array = []  # Array[Dictionary] — authored moves this monster currently knows

# ── battle-only runtime state, reset by BattleSim before each fight ──────────
var hp: float = 1.0
var mp: float = 0.0
var statuses: Array = []      # [{kind, until, from}]
var mods: Array = []          # [{atkMult?, accMod?, dodgeMod?, defMitDebuff?, ward?, guard?, regen?, hpRegen?, until}]
var cooldowns: Dictionary = {}  # move name -> seconds remaining ("__basic__" for the free attack)
var cc_resist: float = 0.0
var last_cc_at: float = -999.0
var has_acted: bool = false
var alive: bool = true

# identity for the battle log / UI
var side: String = ""  # "A" or "B"
var slot: int = 0


func recompute_class() -> void:
	class_name_ = Classify.class_for_stats(stats)
	role = Classify.role_of_class(class_name_)
	mana_role = Classify.mana_role_of(stats, class_name_)
	basic_attack = Classify.basic_attack_for(stats)


func recompute_pools() -> void:
	max_hp = Derive.max_hp(stats.get("CON", 0.0))
	max_mp = Derive.max_mana(stats.get("WIS", 0.0), stats.get("INT", 0.0))


## Pick a moveset from the class's affine lines, gated by the move's own learnLevel against the
## CURRENT value of the stat it's authored on. Up to 2 moves per line, capped at 6 total so a
## battle's move menu stays legible. ⚠️ Approximates `chooseLoadout` in spirit (affinity draws
## from `CLASS_LINES`) without its 1.35x affine-weighting pass — this mockup doesn't model a
## learned-vs-affine move pool distinction, every drafted move here IS affine by construction.
func assign_moveset(rng: RandomNumberGenerator) -> void:
	moveset.clear()
	# ⚠️ `GameData` is an autoload, and autoload GLOBALS do not exist under `--headless --script`
	# (SceneTree script mode) — a bare `GameData.x` is a COMPILE error there, which silently took
	# this whole script (and everything that preloads it, including the spatial self-tests) down
	# with it: `.new()` on the uncompiled script fails, teams come back empty, the sim reports a
	# 0-frame draw. Resolve the singleton dynamically instead — identical in-game, null in script
	# mode (where callers construct monsters directly and never call this).
	var game_data = null
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		game_data = (loop as SceneTree).root.get_node_or_null("GameData")
	if game_data == null:
		push_warning("assign_moveset: GameData autoload unavailable (headless script mode?) — moveset left empty")
		return
	var lines: Array = game_data.class_lines.get(class_name_, [])

	# ⚠️ THE OLD RULE WAS "top 2 by learnLevel per line", AND IT MADE WHOLE CATEGORIES OF AUTHORED
	# CONTENT UNDRAFTABLE. `learnLevel` is a power proxy, so sorting by it and taking the top two
	# ranks every line by power — and CONTROL MOVES ARE DELIBERATELY LOW-POWER. Measured: only
	# 4 of 24 control/debuff moves (17%) could ever be candidates, seven whole lines had control
	# content where NONE was draftable, and across 20 MAXED monsters (every stat at the Tamers
	# Apex ceiling) `type: control` was drafted 0 times out of 114 move slots.
	#
	# ⚠️ THIS IS THE SAME FAILURE `lines.ts` WAS CREATED TO FIX, REPRODUCED IN THE PORT. That file
	# exists because "three separate waves of authored content never reached a kit" and control
	# measured 0% equipped for exactly this reason. The line system fixed WHERE a kit draws from;
	# it never fixed the ranking INSIDE a line.
	#
	# A kit is now drafted by ROLE rather than by power: the strongest thing from each line, then
	# a deliberate reservation for utility. That is what a real loadout looks like, and it is what
	# makes every mechanic built on control — interrupts, cleanse, peel — actually reachable.
	var picks: Array = []
	var utility: Array = []
	for line in lines:
		var pool: Array = game_data.moves_by_line.get(line, [])
		var learnable: Array = []
		for m in pool:
			var stat: String = m["stat"]
			if float(stats.get(stat, 0.0)) >= float(m["learnLevel"]):
				learnable.append(m)

		# ⚠️ A FLOOR, SO A YOUNG MONSTER IS NOT WEAPONLESS. The pool's lowest learnLevel is 40 and
		# a fresh monster averages ~32 across its stats, so a starter qualified for NOTHING in most
		# lines and fielded 1.3 moves out of six — the whole early game ran on basic attacks. If a
		# line offers nothing yet, it still offers its CHEAPEST move. Deliberately not a general
		# relaxation: every other move stays gated, so the kit still grows with the monster.
		if learnable.is_empty() and not pool.is_empty():
			var cheapest = pool[0]
			for m in pool:
				if float(m["learnLevel"]) < float(cheapest["learnLevel"]):
					cheapest = m
			learnable.append(cheapest)

		learnable.sort_custom(func(a, b): return a["learnLevel"] > b["learnLevel"])
		# The strongest of the line is always a candidate — a kit should have teeth.
		if not learnable.is_empty():
			picks.append(learnable[0])
		# Everything else in the line is a candidate too, but utility is kept in its own bucket so
		# it can be RESERVED a slot rather than competing on a number it was never authored to win.
		for i in range(1, learnable.size()):
			var m = learnable[i]
			if str(m.get("type", "damage")) in ["control", "debuff"]:
				utility.append(m)
			else:
				picks.append(m)

	# Fisher-Yates using the passed-in RNG, not `Array.shuffle()` — that call reseeds from
	# Godot's global RNG state, which would make moveset assignment non-reproducible even when
	# the caller explicitly passed a seeded generator.
	for arr in [picks, utility]:
		for i in range(arr.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = arr[i]
			arr[i] = arr[j]
			arr[j] = tmp

	# ⚠️ RESERVED SLOTS, NOT A PREFERENCE. Up to two of six go to utility when the monster has any
	# available. A weighting would have left this to chance and chance is what produced 0 of 114.
	var candidates: Array = []
	for i in range(mini(2, utility.size())):
		candidates.append(utility[i])
	candidates.append_array(picks)
	for i in range(2, utility.size()):
		candidates.append(utility[i])

	for m in candidates:
		if moveset.size() >= 6:
			break
		moveset.append(m)


## A scratch copy carrying only the fields the weekly tick reads/mutates — used by
## `week.gd.preview_week()` so the preview can run the EXACT SAME code path as
## `apply_week()` on a throwaway copy and diff the result, rather than a second
## hand-written estimate that could drift from it (docs/CORE_LOOP_PORT.md §3, the
## "RNG discipline" rule). Battle-only fields (hp/mp/statuses/moveset/etc.) are not
## needed for the tick and are left at class defaults.
func clone_for_preview():
	var m = get_script().new()
	m.id = id
	m.species_id = species_id
	m.body = body
	m.stats = stats.duplicate()
	m.max_hp = max_hp
	m.max_mp = max_mp
	m.hp = hp
	m.mp = mp
	m.stamina = stamina
	m.happiness = happiness
	m.age_weeks = age_weeks
	m.career_week = career_week
	m.retired = retired
	m.fed_this_week = fed_this_week
	m.last_food = last_food
	m.favourite_food = favourite_food
	m.hated_food = hated_food
	m.potential = potential
	m.lifespan_years = lifespan_years
	m.log = log.duplicate()
	# Plan state too — a preview of the week has to know what the week WOULD do, same as apply.
	m.plan_kind = plan_kind
	m.plan_stat = plan_stat
	m.plan_intensive = plan_intensive
	m.plan_paired_stat = plan_paired_stat
	m.planned_food = planned_food
	return m


func hp_frac() -> float:
	return 0.0 if max_hp <= 0 else clampf(hp / float(max_hp), 0.0, 1.0)


func mp_frac() -> float:
	return 0.0 if max_mp <= 0 else clampf(mp / float(max_mp), 0.0, 1.0)


func reset_for_battle() -> void:
	hp = float(max_hp)
	mp = float(max_mp)
	statuses = []
	mods = []
	cooldowns = {}
	cc_resist = 0.0
	last_cc_at = -999.0
	has_acted = false
	alive = true


func has_status(kind: String) -> bool:
	for s in statuses:
		if s["kind"] == kind:
			return true
	return false


func is_incapacitated() -> bool:
	for s in statuses:
		if StatusMath._rule(s["kind"]).get("incapacitates", false):
			return true
	return false
