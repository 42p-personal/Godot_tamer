## THE WEEKLY TICK — port of `src/town.ts:1757 advanceWeek()` + `src/game.ts:549 applyWeek()`.
##
## docs/CORE_LOOP_PORT.md §3 is the binding spec. This is the fix for the reported bug:
## `game_data.gd:train()` applied a stat gain with NO stamina cost, NO week advance, NO gold
## cost — an infinite free button. This file makes training cost STAMINA (a pool of 100,
## −15/−25/−35 per drill tier) so a monster cannot train every week; it must rest, and resting
## is a week it did not improve. That constraint is the whole point (see the ⚠️ in the spec).
##
## ⚠️ PRELOAD, NOT `class_name` RESOLUTION — see technical-preferences.md; this can be pulled in
## before the class cache has scanned a new script.
##
## ⚠️ RNG DISCIPLINE (non-negotiable, CORE_LOOP_PORT.md §3): `preview_week()` must mirror
## `apply_week()` byte-exactly. This file does NOT hand-write two versions of the math — it
## writes ONE (`apply_week`), and `preview_week` runs it on a throwaway `clone_for_preview()`
## copy of the monster, seeded with the SAME (monster id, career_week) key, then diffs the
## result. There is no second code path that could drift.
##
## What this file does NOT port (scope cut, honestly noted rather than silently dropped):
## training gear tiers, bred heritage/fusion stat bonuses, the Extreme/Diverse Manual gates
## (both drill rows are open here), signatures, and the fusion/prestige gen-1 stat-cap special
## cases in `game.ts:statCapFor` (this file applies `league_cap * potential` only). All of
## these are meta-systems layered ON TOP of the tick, not the tick itself — see
## docs/META_GAME_DISPOSITION.md for what's ported vs a presence layer vs UI-only.
extends RefCounted

const ClassifyLib = preload("res://scripts/classify.gd")
const DeriveLib = preload("res://scripts/derive.gd")

# ── constants (src/game.ts) ──────────────────────────────────────────────────
const MAX_STAMINA := 100.0
const MAX_HAPPINESS := 10
const WEEKS_PER_MONTH := 4
const MONTHS_PER_YEAR := 12
const WEEKS_PER_YEAR := WEEKS_PER_MONTH * MONTHS_PER_YEAR  # 48

# ⚠️ These are 15/25/35/35, NOT the 10/25 the task brief quoted — src/game.ts is the source of
# truth (`BASIC_DRILL_STAMINA`/`INTENSIVE_DRILL_STAMINA`/`EXTREME_DRILL_STAMINA`/
# `DIVERSE_DRILL_STAMINA`) and this file ports THAT, not the brief's paraphrase. Against a pool
# of 100 the shape is unchanged: 15/25/35 still means you cannot train every week.
const BASIC_DRILL_STAMINA := 15.0
const INTENSIVE_DRILL_STAMINA := 25.0
const EXTREME_DRILL_STAMINA := 35.0
const DIVERSE_DRILL_STAMINA := 35.0
const EXCURSION_COST := 25.0
const FORAGE_STAMINA_COST := 25.0
const FORAGE_HAPPINESS_COST := 2

# ── FOCUS COST — the thing that makes a training week a DECISION (2026-08-09) ────────────────
#
# ⚠️ MEASURED FIRST, THEN BUILT. `scripts/_probe_training.gd` ran every drill family as a fixed
# policy over four full 336-week careers on identical seeds. Before this change:
#
#     basic 6.04 pts/wk · intensive 9.05 · diverse 12.13 · EXTREME 15.41 · greedy-all 15.57
#
# greedy-all ≈ extreme to within 1%, i.e. the "best play" WAS "take the extreme drill for the
# stat you care about, every week you can afford it". That is the obvious click CLAUDE.md says
# is a failure state, and it was measurable, not a matter of taste.
#
# FOCUS COST is the pushback: a drill pays LESS into a stat the further that stat already leads
# the monster's OWN average. Depth stays available and stays correct — it just stops being free,
# so every week is a live weigh-up between pushing the spike and shoring up the second stat, and
# the answer MOVES as the build moves.
#
# Three properties that made this the choice over the alternatives considered:
#   • It is a pure function of `mi.stats`, which already persists. A per-monster "conditioning"
#     or "strain" counter would have been the richer mechanic, but MonsterInstance and
#     save_game.gd are not this workstream's files — a mechanic that silently resets on load is
#     worse than no mechanic.
#   • It is deterministic and fully legible: the training card can print the exact multiplier and
#     the exact resulting number, so the player can PREDICT it, which is the standing requirement
#     for a game you commit to and then watch.
#   • It is a soft curve, never a wall (floor 0.55). ⚠️ The 5v5 sim rewards specialists and this
#     must not quietly forbid one — CLAUDE.md's rule that a species must never be locked out of a
#     role applies to builds too. Specialising still wins; it now COSTS.
#
# ⚠️ THE FLOOR WAS 0.55 AND IT PRICED A SPECIALIST OUT OF THE GAME (round 14, 2026-08-09).
# `docs/SHAPE_DIAGNOSIS.md` §3 measured a true archetype spike over a full 336-week career at
# **−31.9% of its lifetime stat points** against a flat body, mean focus multiplier 0.618 — and
# the ladder's difficulty model prices the player on stat TOTAL (`career.gd:expected_climber_fill`
# is a total over a cap and is structurally blind to shape). So the player who committed to a
# shape paid a third of their career for it and was then priced as though they had bought
# nothing: 4 careers won in 24, against 21/24 for a flat body. That is not a soft curve, it is a
# trap with a price tag on it.
#
# ⚠️ AND NOTE WHICH DIRECTION THIS MOVES. The floor is *also* what makes "train whatever stat is
# lowest" the points-optimal rule — a lagging stat pays ×1.00 while the leading one pays the
# floor, so a greedy-by-points brain rotates around the bottom of the spread by construction and
# `_probe_training.gd` §5's 94 switches were 94 switches between six ways of staying flat. Raising
# the floor narrows that gap from 1.82x to 1.33x. It does not, on its own, make shape the better
# play — the field has to do that (SHAPE_DIAGNOSIS §5 BUILDER B) — but it stops the training
# economy actively punishing the decision the game wants the player to make.
#
# ⚠️ THE SLOPE IS DELIBERATELY UNCHANGED. The floor sets the price of a FINISHED spike; the slope
# sets how fast that price arrives. Only the floor is implicated by the measured 0.618, and moving
# both at once would make the re-measurement unreadable.
const FOCUS_SLOPE := 0.45
const FOCUS_FLOOR := 0.75

const PRESTIGE_BODIES := ["Draconic", "Abyssal", "Mythical"]
const PRESTIGE_FLAW_PENALTY := 0.95

const BODY_MINOR := {
	"Mammal": "STR", "Avian": "WIS", "Marsupial": "CHA", "Aquatic": "INT",
	"Insectoid": "CON", "Reptilian": "DEX",
	"Draconic": "WIS", "Abyssal": "INT", "Mythical": "CHA",
}

# ── drills (src/drills.ts — 30 total). Not in data.json (drills are authored config, not
# generated math), so ported as a GDScript table here, same pattern GameData already uses for
# CLASS_LINES. gains: positive = raise, negative = paired malus. ─────────────────────────────
const BASIC_GAIN := 6.0
const INTENSIVE_GAIN := 12.0
const INTENSIVE_COST := 4.0
const EXTREME_GAIN := 24.0
const EXTREME_COST := 4.0
const DIVERSE_GAIN := 8.0

const DRILLS := [
	{"id": "weights", "name": "Weight Training", "kind": "basic", "gains": {"STR": BASIC_GAIN}},
	{"id": "agility", "name": "Agility Course", "kind": "basic", "gains": {"DEX": BASIC_GAIN}},
	{"id": "endurance", "name": "Endurance Run", "kind": "basic", "gains": {"CON": BASIC_GAIN}},
	{"id": "meditation", "name": "Meditation", "kind": "basic", "gains": {"WIS": BASIC_GAIN}},
	{"id": "study", "name": "Study", "kind": "basic", "gains": {"INT": BASIC_GAIN}},
	{"id": "stage", "name": "Stage Practice", "kind": "basic", "gains": {"CHA": BASIC_GAIN}},
	{"id": "powerlift", "name": "Powerlifting", "kind": "intensive", "gains": {"STR": INTENSIVE_GAIN, "DEX": -INTENSIVE_COST}},
	{"id": "berserker", "name": "Berserker Training", "kind": "intensive", "gains": {"STR": INTENSIVE_GAIN, "WIS": -INTENSIVE_COST}},
	{"id": "sprints", "name": "Sprint Intervals", "kind": "intensive", "gains": {"DEX": INTENSIVE_GAIN, "STR": -INTENSIVE_COST}},
	{"id": "acrobatics", "name": "Acrobatics", "kind": "intensive", "gains": {"DEX": INTENSIVE_GAIN, "CON": -INTENSIVE_COST}},
	{"id": "toughening", "name": "Toughening Regimen", "kind": "intensive", "gains": {"CON": INTENSIVE_GAIN, "DEX": -INTENSIVE_COST}},
	{"id": "irondiet", "name": "Iron Diet", "kind": "intensive", "gains": {"CON": INTENSIVE_GAIN, "INT": -INTENSIVE_COST}},
	{"id": "deepmed", "name": "Deep Meditation", "kind": "intensive", "gains": {"WIS": INTENSIVE_GAIN, "STR": -INTENSIVE_COST}},
	{"id": "ascetic", "name": "Ascetic Trance", "kind": "intensive", "gains": {"WIS": INTENSIVE_GAIN, "CHA": -INTENSIVE_COST}},
	{"id": "arcane", "name": "Arcane Study", "kind": "intensive", "gains": {"INT": INTENSIVE_GAIN, "CON": -INTENSIVE_COST}},
	{"id": "runic", "name": "Runic Focus", "kind": "intensive", "gains": {"INT": INTENSIVE_GAIN, "STR": -INTENSIVE_COST}},
	{"id": "oratory", "name": "Oratory Drills", "kind": "intensive", "gains": {"CHA": INTENSIVE_GAIN, "INT": -INTENSIVE_COST}},
	{"id": "showmanship", "name": "Showmanship", "kind": "intensive", "gains": {"CHA": INTENSIVE_GAIN, "CON": -INTENSIVE_COST}},
	{"id": "xstr", "name": "Titan Regimen", "kind": "extreme", "gains": {"STR": EXTREME_GAIN, "DEX": -EXTREME_COST, "WIS": -EXTREME_COST}},
	{"id": "xdex", "name": "Gauntlet Sprints", "kind": "extreme", "gains": {"DEX": EXTREME_GAIN, "STR": -EXTREME_COST, "CON": -EXTREME_COST}},
	{"id": "xcon", "name": "Stone Vigil", "kind": "extreme", "gains": {"CON": EXTREME_GAIN, "DEX": -EXTREME_COST, "INT": -EXTREME_COST}},
	{"id": "xwis", "name": "Void Fast", "kind": "extreme", "gains": {"WIS": EXTREME_GAIN, "STR": -EXTREME_COST, "CHA": -EXTREME_COST}},
	{"id": "xint", "name": "Forbidden Texts", "kind": "extreme", "gains": {"INT": EXTREME_GAIN, "CON": -EXTREME_COST, "CHA": -EXTREME_COST}},
	{"id": "xcha", "name": "Grand Spectacle", "kind": "extreme", "gains": {"CHA": EXTREME_GAIN, "WIS": -EXTREME_COST, "INT": -EXTREME_COST}},
	{"id": "dpilgrim", "name": "Pilgrim's Burden", "kind": "diverse", "gains": {"STR": DIVERSE_GAIN, "WIS": DIVERSE_GAIN}},
	{"id": "dcannon", "name": "The Cannon Crew", "kind": "diverse", "gains": {"STR": DIVERSE_GAIN, "INT": DIVERSE_GAIN}},
	{"id": "dtrapeze", "name": "Trapeze Hours", "kind": "diverse", "gains": {"DEX": DIVERSE_GAIN, "CON": DIVERSE_GAIN}},
	{"id": "dblindfold", "name": "Blindfold Forms", "kind": "diverse", "gains": {"DEX": DIVERSE_GAIN, "WIS": DIVERSE_GAIN}},
	{"id": "dfall", "name": "Taking the Fall", "kind": "diverse", "gains": {"CON": DIVERSE_GAIN, "CHA": DIVERSE_GAIN}},
	{"id": "dpatter", "name": "Illusionist's Patter", "kind": "diverse", "gains": {"INT": DIVERSE_GAIN, "CHA": DIVERSE_GAIN}},
]

# ── foods (src/core.ts FOODS — full 10-entry table, ported verbatim) ─────────────────────────
const FOODS := [
	{"id": "vegetables", "name": "Vegetables", "price": 10, "tier": "normal"},
	{"id": "fruit", "name": "Fruit", "price": 10, "tier": "normal"},
	{"id": "meat", "name": "Meat", "price": 10, "tier": "normal"},
	{"id": "sweet treats", "name": "Sweet Treats", "price": 10, "tier": "normal"},
	{"id": "prime cut", "name": "Prime Cut", "price": 75, "tier": "training", "boostStats": ["STR", "CON"], "boostMult": 0.3, "happiness": -1, "stamina": -15},
	{"id": "scholars tea", "name": "Scholar's Tea", "price": 75, "tier": "training", "boostStats": ["WIS", "INT"], "boostMult": 0.3, "happiness": -1, "stamina": -15},
	{"id": "sprinters mix", "name": "Sprinter's Mix", "price": 75, "tier": "training", "boostStats": ["DEX", "CHA"], "boostMult": 0.3, "happiness": -1, "stamina": -15},
	{"id": "vigor melon", "name": "Vigor Melon", "price": 90, "tier": "premium", "stamina": 30},
	{"id": "bliss berry", "name": "Bliss Berry", "price": 90, "tier": "premium", "happiness": 3},
	{"id": "golden truffle", "name": "Golden Truffle", "price": 500, "tier": "premium", "rewardMult": 1.5},
]

const LEAGUE_TOP_GOLD := {
	"Wood": 110, "Copper": 165, "Tin": 220, "Bronze": 280, "Iron": 340,
	"Silver": 520, "Gold": 580, "Platinum": 640, "Masters": 700, "Tamer Elite": 760, "Tamers Apex": 820,
}
const EXCURSION_CAP_FRACTION := 0.4


static func drill_by_id(id: String) -> Dictionary:
	for d in DRILLS:
		if d["id"] == id:
			return d
	return DRILLS[0]


static func food_by_id(id: String) -> Dictionary:
	for f in FOODS:
		if f["id"] == id:
			return f
	return {}


static func drill_stamina(kind: String) -> float:
	match kind:
		"basic": return BASIC_DRILL_STAMINA
		"intensive": return INTENSIVE_DRILL_STAMINA
		"diverse": return DIVERSE_DRILL_STAMINA
		_: return EXTREME_DRILL_STAMINA


## Deterministic RNG for one (monster, week) pair. Same key -> same stream, every call —
## this is the whole mechanism that keeps preview and apply in lock-step, not a copy of
## `mulberry32`/`hashString` byte-for-byte (Godot's RNG need not match the TS PRNG; only
## Godot's own preview and apply need to match each other, and they always call this the
## same way because preview runs `apply_week` itself, see the file header).
static func _seeded_rng(mi) -> RandomNumberGenerator:
	var key := "%s:%d" % [mi.id, mi.career_week]
	var rng := RandomNumberGenerator.new()
	rng.seed = key.hash()
	return rng


## Life stage from age in weeks vs the monster's effective career span in years.
## Mirrors `game.ts:stageInfo` (Baby year 0 · Teen year 1 · Elder final year · Retiree past span).
static func stage_info(age_weeks: int, lifespan_years: float) -> Dictionary:
	var age_years := int(floor(age_weeks / float(WEEKS_PER_YEAR)))
	var span_weeks := int(round(lifespan_years * WEEKS_PER_YEAR))
	var stage: String
	var train_mult: float
	if age_weeks < WEEKS_PER_YEAR:
		stage = "Baby"; train_mult = 0.5
	elif age_weeks < 2 * WEEKS_PER_YEAR:
		stage = "Teen"; train_mult = 1.35
	elif age_weeks >= span_weeks:
		stage = "Retiree"; train_mult = 0.0
	elif age_weeks >= span_weeks - WEEKS_PER_YEAR:
		stage = "Elder"; train_mult = 0.8
	else:
		stage = "Fully Grown"; train_mult = 1.15
	return {"stage": stage, "trainMult": train_mult, "ageYears": age_years}


static func stamina_malus(stamina: float) -> float:
	if stamina > 70.0: return 1.0
	if stamina > 50.0: return 0.95
	if stamina > 30.0: return 0.9
	return 0.5


## A drill's positive gain is a happiness-weighted roll, not a flat number (game.ts:rollDrillGain).
## Range is ±1/3 of the base; happiness 0 rolls uniformly across it, happiness 10 skews hard to
## the top. Malus values are NOT rolled — flat, unaffected by happiness.
static func roll_drill_gain(rng: RandomNumberGenerator, base: float, happiness: int) -> int:
	var range_ := roundi(base / 3.0)
	var skew := 1.0 / (1.0 + happiness / 5.0)
	var t := pow(rng.randf(), skew)
	return int(base) - range_ + roundi(t * range_ * 2.0)


static func _is_prestige(body: String) -> bool:
	return PRESTIGE_BODIES.has(body)


## {major, minor, flaw} for this monster: minor from body type, major/flaw authored per species
## in data.json's `trainingProfile`. Falls back to no bonus stats if the species carries neither
## (mirrors game.ts:trainingProfileFor's legacy branch loosely — full top/2nd/lowest derivation
## is not ported here since every shipped species already authors a profile).
static func training_profile(mi) -> Dictionary:
	var sp: Dictionary = GameData.species_by_id.get(mi.species_id, {})
	var authored: Dictionary = sp.get("trainingProfile", {})
	return {
		"minor": BODY_MINOR.get(mi.body, ""),
		"major": authored.get("major", ""),
		"flaw": authored.get("flaw", ""),
	}


static func stat_training_bonus(mi, stat: String) -> float:
	var prof := training_profile(mi)
	if stat == prof["major"]: return 1.2
	if stat == prof["minor"]: return 1.1
	if stat == prof["flaw"]: return PRESTIGE_FLAW_PENALTY if _is_prestige(mi.body) else 0.8
	return 1.0


## Diminishing returns on a stat that already leads this monster's own spread. 1.0 for anything
## at or below its own average; falls toward FOCUS_FLOOR as the lead grows.
##
## ⚠️ MEASURED AGAINST THE MONSTER'S OWN AVERAGE, NOT THE LEAGUE CAP. Against the cap it would be
## a second, softer copy of the cap — the same wall twice — and it would punish a Wood-league
## rookie and an Apex champion identically for having a 400 STR. Against its own average it asks
## the only question that is actually a design decision: how LOPSIDED is this monster.
static func focus_cost(mi, stat: String) -> float:
	var total := 0.0
	var n := 0
	for s in mi.stats:
		total += float(mi.stats[s])
		n += 1
	if n == 0:
		return 1.0
	var avg := total / float(n)
	if avg <= 1.0:
		return 1.0
	var lead := (float(mi.stats.get(stat, 0.0)) - avg) / avg
	return clampf(1.0 - FOCUS_SLOPE * lead, FOCUS_FLOOR, 1.0)


static func stat_malus_multiplier(mi, stat: String) -> float:
	var prof := training_profile(mi)
	if stat != prof["flaw"]: return 1.0
	return 1.0 if _is_prestige(mi.body) else 1.5


## League cap x bloodline potential (CLAUDE.md: "the ceiling is league cap × potential").
## ⚠️ Does not port the fusion/Primeval/prestige gen-1 sub-caps in game.ts:statCapFor — see the
## scope note at the top of this file.
##
## ⚠️ THIS IS THE *NOMINAL* CEILING — what the bars and the league text mean by "the cap". The
## ceiling a drill is actually clamped against is `stat_ceiling()` below, which is the same number
## for a balanced body and higher for a committed one. Callers that want "what does this league
## cap at" keep using this; only the tick and anything previewing the tick want the other.
static func stat_cap_for(mi, league_cap: float) -> float:
	return roundi(league_cap * mi.potential)


# ── THE HEADROOM TRADE — the price of shape, and where it actually lived (round 14, 2026-08-09) ──
#
# ⚠️ `docs/SHAPE_DIAGNOSIS.md` §3 attributes the cost of specialising to `focus_cost` and states
# the floor "is the only knob that sets it". MEASURED, THAT IS WRONG, and the measurement is
# `_probe_training.gd` §7 plus two runs of `_probe_shape.tscn --gym`:
#
#     FOCUS_FLOOR 0.55 -> 0.75 : spike deficit  -31.9% -> -30.3%   (focus mult 0.618 -> 0.781)
#     FOCUS_FLOOR      -> 1.00 : spike deficit           -28.8%    (focus cost OFF entirely)
#     ceiling removed, floor 0.75, shape vs lowest-stat:  -25.7% -> **+7.6%**
#
# Focus cost is worth ~3 points of a ~30-point deficit. **The other ~27 are the CEILING, and it is
# geometry rather than tuning: the cap is PER STAT and identical on all six, so a body that
# commits to two stats is handed one third of the room a body that trains all six gets.** A
# specialist does not lose points to a multiplier — it runs out of anywhere to put them, and then
# spends the back half of its career pouring weeks into a wall. That is the 31.9% and the 4/24.
#
# THE FIX IS A BUDGET, NOT A HIGHER WALL. A monster still gets exactly `6 x nominal cap` of total
# room — so `career.gd:expected_climber_fill`, which is a stat TOTAL over a cap, reads a committed
# build and a balanced one as the same strength and BUILDER B's field work is not disturbed by
# this. What changes is that the room is now spendable where the player chooses, up to
# `SPIKE_HEADROOM` on any one stat.
#
# ⚠️ THE HEADROOM NUMBER IS NOT INVENTED. 1.35 is `roster.gd:SHAPE_PRIMARY` — the exact primary
# weight of the archetype vector the game already builds its rivals from. So the ceiling a player
# can train to is precisely the shape the ladder already fields, and no further.
#
# ⚠️ AND THE TOTAL BUDGET DOES NOT BIND TODAY, deliberately. A full career banks ~4,450 points
# against a 6,600 budget at the Apex cap (`_probe_training.gd` §1), so this is a guard against
# generalisation, not a live constraint — it exists so that raising the per-stat ceiling cannot
# quietly raise the total one. If a future career ever reaches it, that is the moment
# `docs/CLASS_REWORK.md`'s per-class caps become load-bearing rather than optional.
const SPIKE_HEADROOM := 1.35


## The ceiling THIS stat may actually be trained to on THIS body: the nominal cap x SPIKE_HEADROOM,
## less anything the rest of the monster has already spent out of the shared `6 x nominal` budget.
## For a balanced body the budget term never binds and this returns the nominal cap, unchanged.
static func stat_ceiling(mi, league_cap: float, stat: String) -> float:
	var nominal := float(stat_cap_for(mi, league_cap))
	var spent_elsewhere := 0.0
	for s in mi.stats:
		if str(s) != stat:
			spent_elsewhere += float(mi.stats[s])
	var from_budget: float = 6.0 * nominal - spent_elsewhere
	return maxf(nominal, minf(nominal * SPIKE_HEADROOM, from_budget))


## How far a monster's TOP stat may outrun its TOP carried move's `learnLevel` before the kit is
## judged stale. The pool spans learnLevel 40..920 with a median near 340, so 120 is roughly one
## step up a line: big enough that a kit is not re-examined for every drill, small enough that a
## body cannot carry a rookie's loadout into Gold.
const KIT_STALE_MARGIN := 120.0


## ⚠️ `apply_activity` CALLED `recompute_class()` AND `recompute_pools()` EVERY WEEK AND NEVER
## `assign_moveset()`. `monster_instance.gd:assign_moveset` gates every move on `learnLevel`
## against the CURRENT value of the stat it is authored on — so a body recruited at ~23-80 per
## stat drafted the floor of every line and KEPT IT for its whole career. Measured on the arc's
## stalled Gold roster: mean carried learnLevel 118, top 200, on a body at 424 mean stat, against
## rivals who are GENERATED at their fill and therefore always draft to their stats.
##
## The retired `game_data.gd:train()` already does this, under a ⚠️ comment saying it must; the
## live path was written without it. This is that comment's rule, moved onto the path the game
## actually runs.
##
## ⚠️ THE RNG IS SEEDED ON THE MONSTER'S IDENTITY ALONE, NEVER ON THE WEEK. That makes the kit a
## pure function of (id, class, stats): re-drafting twice at the same stats yields the same six
## moves, so the gate can fire as often as it likes and the loadout still cannot churn. A
## week-salted seed would reshuffle a settled kit every time the trigger held, which is a worse
## bug than the one being fixed.
static func _redraft_if_stale(mi, class_before: String) -> void:
	var stale: bool = str(mi.class_name_) != class_before or mi.moveset.is_empty()
	if not stale:
		var top_carried := 0.0
		for mv in mi.moveset:
			if mv is Dictionary:
				top_carried = maxf(top_carried, float(mv.get("learnLevel", 0.0)))
		var top_stat := 0.0
		for s in mi.stats:
			top_stat = maxf(top_stat, float(mi.stats[s]))
		stale = top_stat > top_carried + KIT_STALE_MARGIN
	if not stale:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(mi.id))
	## ⚠️ A RE-DRAFT MUST NEVER DISARM A MONSTER, AND THIS TRIPWIRE IS NOT THEORETICAL —
	## `assign_moveset` clears the kit before it rebuilds, so any class whose lines resolve to
	## nothing leaves the body carrying only its basic attack for the rest of its life. That is
	## exactly what `Generalist` did (no `classLines` entry; fixed in `monster_instance.gd`), and
	## it took the career arc from clearing Gold to stalling at Wood. Keeping the old kit is
	## always better than fielding none, and the warning names the class so the next one is found
	## in a log rather than in a 500-week arc.
	var keep: Array = mi.moveset.duplicate(true)
	mi.assign_moveset(rng)
	if mi.moveset.is_empty() and not keep.is_empty():
		push_warning("week.gd: re-draft produced an EMPTY moveset for class '%s' — kit kept" % str(mi.class_name_))
		mi.moveset = keep


static func excursion_gold(rng: RandomNumberGenerator, league_name: String) -> int:
	var top: int = LEAGUE_TOP_GOLD.get(league_name, LEAGUE_TOP_GOLD["Wood"])
	var cap := maxi(10, roundi(top * EXCURSION_CAP_FRACTION))
	var floor_ := maxi(5, roundi(cap * 0.15))
	return floor_ + roundi(rng.randf() * rng.randf() * (cap - floor_))


# ── feeding (game.ts foodHappinessDelta / buyFood / forageFeed) ─────────────────────────────

static func food_happiness_delta(mi, food_id: String) -> int:
	var def := food_by_id(food_id)
	if def.is_empty(): return 0
	var raw: int
	if def.has("happiness"):
		raw = int(def["happiness"])
	else:
		# taste: favourite +1, hated -1, else 0 (feedDelta)
		raw = 1 if food_id == mi.favourite_food else (-1 if food_id == mi.hated_food else 0)
	if raw > 0 and mi.last_food == food_id:
		return int(floor(raw / 2.0))  # satiety: same food twice running halves a positive gain
	return raw


static func food_stamina_delta(food_id: String) -> int:
	var def := food_by_id(food_id)
	return int(def.get("stamina", 0))


static func food_train_mult(food_id: String, stat: String) -> float:
	if food_id == "": return 1.0
	var def := food_by_id(food_id)
	var boosts: Array = def.get("boostStats", [])
	return (1.0 + float(def.get("boostMult", 0.0))) if boosts.has(stat) else 1.0


## Buy one food from the week's market. Does NOT advance the week — feeding resolves before the
## planned activity. Returns the new gold; mutates `mi` (happiness/stamina/fed_this_week/last_food)
## in place. If unaffordable, mi is untouched and `fed_this_week` stays false (the caller then
## falls back to forage, matching advanceWeek's `plan.food` vs `plan.forage` branch).
static func buy_food(mi, gold: int, food_id: String, price: int) -> Dictionary:
	if mi.retired or mi.fed_this_week or price > gold:
		return {"gold": gold, "fed": false}
	var d := food_happiness_delta(mi, food_id)
	mi.happiness = clampi(mi.happiness + d, 0, MAX_HAPPINESS)
	mi.stamina = clampf(mi.stamina + food_stamina_delta(food_id), 0.0, MAX_STAMINA)
	mi.fed_this_week = true
	mi.last_food = food_id
	return {"gold": gold - price, "fed": true}


## Forage: the free fallback. Never costs gold; costs stamina + happiness instead — hunger is
## never free, only paid differently (CORE_LOOP_PORT.md §3).
static func forage_feed(mi) -> void:
	if mi.retired or mi.fed_this_week: return
	mi.happiness = clampi(mi.happiness - FORAGE_HAPPINESS_COST, 0, MAX_HAPPINESS)
	mi.stamina = clampf(mi.stamina - FORAGE_STAMINA_COST, 0.0, MAX_STAMINA)
	mi.fed_this_week = true
	mi.last_food = ""


# ── the tick itself ───────────────────────────────────────────────────────────────────────

## A monster that took no action this week (retired, or age-only) still ages.
static func age_one_week(mi) -> void:
	var before: String = stage_info(mi.age_weeks, mi.lifespan_years)["stage"]
	mi.age_weeks += 1
	mi.fed_this_week = false
	var now: String = stage_info(mi.age_weeks, mi.lifespan_years)["stage"]
	if now != before:
		if now == "Retiree":
			mi.retired = true
			mi.log.append("has reached retirement age and can no longer compete.")
		else:
			mi.log.append("is now %s." % now)
	if mi.log.size() > 40:
		mi.log = mi.log.slice(mi.log.size() - 40)


## Apply one week's ACTIVITY (train/rest/excursion/compete) to `mi` — mirrors `game.ts:applyWeek`
## minus the feed step (feeding is a separate call, see `apply_week` below, matching
## advanceWeek's own feed-then-activity order). Mutates `mi`; returns the new gold.
## `action` = {"kind": "train", "drillId": ...} | {"kind": "rest"} | {"kind": "excursion"}
##          | {"kind": "compete"}
## `eaten_food` is the food the monster ACTUALLY ate this week ("" = none/forage) — see the
## training-food note in the train branch. Defaults to "" so existing 5-arg callers still work.
static func apply_activity(mi, action: Dictionary, gold: int, cap: float, league_name: String, eaten_food: String = "") -> int:
	if mi.retired: return gold
	var g := gold
	var rng := _seeded_rng(mi)
	var info := stage_info(mi.age_weeks, mi.lifespan_years)
	var train_mult: float = info["trainMult"]
	var wk: int = int(mi.career_week) + 1
	var kind: String = action.get("kind", "rest")

	if kind == "train":
		var drill := drill_by_id(action.get("drillId", ""))
		var stam_cost := drill_stamina(drill.get("kind", "basic"))
		var malus := stamina_malus(mi.stamina)
		var eff := train_mult * malus
		var changes: Array = []
		for stat in drill["gains"]:
			var delta: float = drill["gains"][stat]
			var applied: int
			if delta > 0.0:
				# ⚠️ `food_train_mult` WAS DEAD CODE. It was ported, documented and advertised on the
				# training card ("+30% STR/CON") but never called from the tick — so the three 75g
				# training foods bought literally nothing, and the one place where the week had TWO
				# interacting variables was inert. Wiring it in is the fix.
				var rolled := roll_drill_gain(rng, delta, mi.happiness)
				applied = roundi(rolled * eff * stat_training_bonus(mi, stat)
					* food_train_mult(eaten_food, stat) * focus_cost(mi, stat))
			else:
				# ⚠️ THE MALUS NOW SCALES BY `eff` TOO, AND THAT IS A DELIBERATE DESIGN CHANGE, NOT A
				# PORT FIX. src/game.ts applies the paired malus FLAT while scaling the gain by life
				# stage x stamina — so `drills.ts`'s own authored claim that extreme (+24/−4/−4) and
				# diverse (+8/+8) are "deliberate MIRRORS, same +16 net" is false in the TypeScript too.
				# Measured over four full careers: extreme 15.41 pts/wk vs diverse 12.13 — a 1.27x edge
				# on a tier that costs the same 35 stamina. Scaling both halves by the same multiplier
				# restores the intended mirror and turns "which tier" back into a question about SHAPE.
				applied = roundi(delta * stat_malus_multiplier(mi, stat) * eff)
			# ⚠️ THE CEILING IS `league cap x bloodline potential`, NOT THE RAW LEAGUE CAP. This line
			# clamped to `cap` from the day it was written, so `stat_cap_for` — defined 124 lines
			# above, matching CLAUDE.md's "the ceiling is league cap × potential" verbatim, printed
			# on three screens — had NO shipped caller anywhere in the game. Measured before the fix
			# (`_probe_breed.gd` §3b, paired, clock removed, 500 weeks of the real tick): potential
			# x1.00, x1.50 and x2.00 all finished on exactly 750/stat. Bloodline potential is the
			# ONLY thing breeding sells that the market shelf cannot, so breeding was strictly
			# dominated by shopping for as long as this said `cap`.
			# ⚠️ `stat_ceiling`, NOT `stat_cap_for` — see the HEADROOM TRADE block above. A balanced
			# body gets the identical number this line always used; a body that has committed its
			# points to two stats may push those two to SPIKE_HEADROOM, out of the same total
			# budget. Nothing here raises what a monster can bank in a career, only where it sits.
			var nv: float = clampf(mi.stats[stat] + applied, 1.0, stat_ceiling(mi, cap, stat))
			var real: float = nv - float(mi.stats[stat])
			mi.stats[stat] = nv
			if real != 0.0:
				changes.append("%s %s%d" % [stat, "+" if real > 0 else "", int(real)])
		mi.stamina = maxf(0.0, mi.stamina - stam_cost)
		mi.log.append("Wk %d: %s — %s." % [wk, drill["name"], (", ".join(changes)) if changes.size() > 0 else "no gain (capped)"])

	elif kind == "compete":
		mi.log.append("Wk %d: competed in the arena." % wk)

	elif kind == "rest":
		var rest_min := roundi(0.3 * MAX_STAMINA)
		var rest_max := roundi(1.0 * MAX_STAMINA)
		var rest_amount := rest_min + int(floor(rng.randf() * ((rest_max - rest_min) / 5.0 + 1.0))) * 5
		mi.stamina = minf(MAX_STAMINA, mi.stamina + rest_amount)
		var max_hp_now := float(DeriveLib.max_hp(mi.stats.get("CON", 0.0)))
		var max_mp_now := float(DeriveLib.max_mana(mi.stats.get("WIS", 0.0), mi.stats.get("INT", 0.0)))
		var heal_amt := roundi(max_hp_now * (0.3 + rng.randf() * 0.4))
		var mp_amt := roundi(max_mp_now * (0.25 + rng.randf() * 0.55))
		mi.hp = minf(max_hp_now, mi.hp + heal_amt)
		mi.mp = minf(max_mp_now, mi.mp + mp_amt)
		mi.log.append("Wk %d: rested. Stamina %d/%d." % [wk, int(mi.stamina), int(MAX_STAMINA)])

	else:  # excursion
		mi.stamina = maxf(0.0, mi.stamina - EXCURSION_COST)
		var purse := excursion_gold(rng, league_name)
		g += purse
		mi.happiness = clampi(mi.happiness + 1, 0, MAX_HAPPINESS)
		mi.log.append("Wk %d: excursion — returned with %dg, spirits high (happiness %d/%d)." % [wk, purse, mi.happiness, MAX_HAPPINESS])

	# hunger: unfed this week costs happiness
	if not mi.fed_this_week:
		mi.happiness = maxi(0, mi.happiness - 1)
		mi.log.append("went unfed — happiness %d/%d." % [mi.happiness, MAX_HAPPINESS])

	mi.career_week += 1
	mi.fed_this_week = false

	var class_before: String = str(mi.class_name_)
	mi.recompute_class()
	_redraft_if_stale(mi, class_before)
	var prev_max_hp: float = float(mi.max_hp)
	var prev_max_mp: float = float(mi.max_mp)
	mi.recompute_pools()
	# growth heals with it: a stat gain that raised max HP/MP raises current by the same amount,
	# so training doesn't come out of the gym looking "injured" relative to its new ceiling.
	if mi.max_hp > prev_max_hp:
		mi.hp += (mi.max_hp - prev_max_hp)
	if mi.max_mp > prev_max_mp:
		mi.mp += (mi.max_mp - prev_max_mp)
	mi.hp = clampf(mi.hp, 1.0, float(mi.max_hp))
	mi.mp = clampf(mi.mp, 0.0, float(mi.max_mp))

	age_one_week(mi)  # advances age_weeks, may retire

	if mi.log.size() > 40:
		mi.log = mi.log.slice(mi.log.size() - 40)
	return g


## Full per-monster week: feed (paid food, or forage as the free-but-costly fallback), then the
## planned activity. `food_id == ""` and `forage == false` means "no plan submitted" — the
## monster goes unfed (mirrors advanceWeek: a plan with no food/forage entry just doesn't feed).
static func apply_week(mi, action: Dictionary, gold: int, rental: int, food_id: String, forage: bool, price: int, cap: float, league_name: String) -> int:
	if mi.retired:
		age_one_week(mi)
		return gold
	var g := gold
	# ⚠️ `eaten` is what the monster ACTUALLY ATE, not what was booked. A Prime Cut the player
	# could not afford must not still hand out its +30% — `buy_food` reports `fed`, and only a
	# successful purchase feeds the training multiplier into the drill below.
	var eaten := ""
	if food_id != "":
		var r := buy_food(mi, g, food_id, price)
		g = r["gold"]
		if r["fed"]:
			eaten = food_id
		elif forage:
			forage_feed(mi)
	elif forage:
		forage_feed(mi)
	g = apply_activity(mi, action, g, cap, league_name, eaten)
	if rental > 0:
		g = maxi(0, g - rental)
		mi.log.append("lab upkeep -%dg (frozen genomes)." % rental)
	return g


## ⚠️ THE INVARIANT: runs `apply_week` on a throwaway clone, seeded identically (same id, same
## career_week), and reads off the deltas. This IS "mirrors apply_week byte-exactly" — there is
## no second implementation to drift.
static func preview_week(mi, action: Dictionary, gold: int, rental: int, food_id: String, forage: bool, price: int, cap: float, league_name: String) -> Dictionary:
	var scratch = mi.clone_for_preview()
	var before_stats: Dictionary = mi.stats.duplicate()
	var before_stamina: float = mi.stamina
	var before_happiness: int = mi.happiness
	var before_hp: float = mi.hp
	var before_mp: float = mi.mp
	var new_gold := apply_week(scratch, action, gold, rental, food_id, forage, price, cap, league_name)

	var stat_deltas := {}
	for stat in scratch.stats:
		var d: float = scratch.stats[stat] - before_stats.get(stat, scratch.stats[stat])
		if d != 0.0:
			stat_deltas[stat] = d

	return {
		"statDeltas": stat_deltas,
		"staminaDelta": scratch.stamina - before_stamina,
		"happinessDelta": scratch.happiness - before_happiness,
		"hpDelta": scratch.hp - before_hp,
		"mpDelta": scratch.mp - before_mp,
		"goldDelta": new_gold - gold,
		"retiredNow": scratch.retired and not mi.retired,
	}


# ── the global tick (town.ts:advanceWeek order: per monster feed->activity->age, THEN lab rental
# once, THEN globals) ──────────────────────────────────────────────────────────────────────────

## `monsters`: Array[MonsterInstance]. `plans`: Dictionary[mi.id -> {"activity": drillId|"rest"|
## "excursion"|"compete", "food": foodId, "forage": bool}]. Monsters with no entry rest (the UI's
## own promised default). Lab rental is charged once total, against the FIRST monster processed
## (mirrors advanceWeek: `rentalDue` zeroes after the first `applyWeek` call; if every monster is
## retired, it's deducted at the end instead so it's never silently skipped).
static func advance_week(monsters: Array, plans: Dictionary, gold: int, rental_total: int, food_market: Dictionary, cap: float, league_name: String) -> Dictionary:
	var g := gold
	var rental_due := rental_total
	for mi in monsters:
		if mi.retired:
			age_one_week(mi)
			continue
		var plan: Dictionary = plans.get(mi.id, {"activity": "rest", "food": "", "forage": false})
		var food_id: String = plan.get("food", "")
		var forage: bool = plan.get("forage", false)
		var price: int = int(food_market.get(food_id, 0))
		var activity: String = plan.get("activity", "rest")
		var action: Dictionary
		if activity == "rest" or activity == "compete":
			action = {"kind": "rest"}
		elif activity == "excursion":
			action = {"kind": "excursion"}
		else:
			action = {"kind": "train", "drillId": activity}
		g = apply_week(mi, action, g, rental_due, food_id, forage, price, cap, league_name)
		rental_due = 0  # charged once per week, not per monster
	if rental_due > 0:
		g = maxi(0, g - rental_due)  # nobody processed the charge (all retired) — never skip it
	return {"gold": g}
