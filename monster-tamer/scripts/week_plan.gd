## THE WEEK PLAN — what each monster is BOOKED to do, before anything is spent.
##
## ⚠️ THIS IS THE FIX FOR "i can still train infintely". The old `game_data.gd:train()` applied a
## stat gain the instant the button was clicked, with no clock and no cost, so a player could
## click a drill an unlimited number of times inside a single week. Nothing about stamina fixes
## that on its own — `week.gd`'s stamina malus floors at 0.5 and never blocks a drill, exactly as
## `game.ts:149 staminaMalus()` does. **The CLOCK is what bounds training**, and this file is the
## clock's ledger: planning writes here, and only `advance_week()` spends anything.
##
## Mirrors `town.ts`'s `weekPlans: Record<string, WeekPlanEntry>` — one entry per monster id:
##   {"activity": "<drill id>" | "rest" | "excursion", "food": "<food id>", "forage": bool}
##
## Autoload name: `WeekPlan`.
extends Node

const WeekLib = preload("res://scripts/week.gd")

## monster id -> {activity, food, forage}
var plans: Dictionary = {}

## food id -> this week's price. Rerolled every week, like `town.ts`'s `foodMarket`.
var food_market: Dictionary = {}

## Weekly rent per frozen monster — mirrors scripts/ui/lab_ui.gd. Placeholder value.
const RENTAL_PER_FROZEN := 12

var _rng := RandomNumberGenerator.new()

signal week_advanced(week: int, report: Dictionary)


func _ready() -> void:
	_rng.seed = 20260804
	if food_market.is_empty():
		reroll_food_prices()


## ⚠️ ±40% weekly swing, per `docs/CORE_LOOP_PORT.md` §3. Prices moving is what makes "buy the
## cheap food this week" an actual decision rather than a fixed tax.
func reroll_food_prices() -> void:
	food_market.clear()
	for f in WeekLib.FOODS:
		var base: float = float(f["price"])
		var mult := 0.6 + _rng.randf() * 0.8
		food_market[f["id"]] = maxi(1, int(round(base * mult)))


func price_of(food_id: String) -> int:
	return int(food_market.get(food_id, 0))


## The default a monster sits on until the player decides otherwise. Rest, unfed — so an
## untouched monster costs nothing and gains nothing. ⚠️ Never default to a drill: a plan the
## player did not make must not spend their gold.
func plan_for(monster_id: String) -> Dictionary:
	if not plans.has(monster_id):
		plans[monster_id] = {"activity": "rest", "food": "", "forage": false, "chosen": false}
	return plans[monster_id]


## ⚠️ `chosen` marks that the PLAYER picked this, as opposed to the default the plan was born
## with. It matters because REST is also the default: without this flag "did the player rest?" and
## "did the player do nothing?" are the same state, and anything asking that question (the
## tutorial's stamina lesson, any future "you left a monster idle" warning) silently gets a
## false positive on every untouched monster.
func set_activity(monster_id: String, activity: String) -> void:
	var p := plan_for(monster_id)
	p["activity"] = activity
	p["chosen"] = true
	plans[monster_id] = p


func set_food(monster_id: String, food_id: String) -> void:
	var p := plan_for(monster_id)
	p["food"] = food_id
	p["forage"] = false
	plans[monster_id] = p


func set_forage(monster_id: String) -> void:
	var p := plan_for(monster_id)
	p["food"] = ""
	p["forage"] = true
	plans[monster_id] = p


func is_planned(monster_id: String) -> bool:
	var p := plan_for(monster_id)
	return str(p.get("activity", "rest")) != "rest" or str(p.get("food", "")) != "" or bool(p.get("forage", false))


## What this week's plan will COST, totalled across the stable — shown on the Advance Week button
## so the player sees the bill before they pay it (`docs/CORE_LOOP_PORT.md` §4).
func projected_cost(monsters: Array) -> Dictionary:
	var gold_cost := 0
	var stamina_cost := 0.0
	for mi in monsters:
		if mi.retired:
			continue
		var p := plan_for(mi.id)
		var food_id: String = str(p.get("food", ""))
		if food_id != "":
			gold_cost += price_of(food_id)
		if bool(p.get("forage", false)):
			stamina_cost += WeekLib.FORAGE_STAMINA_COST
		var act: String = str(p.get("activity", "rest"))
		if act != "rest" and act != "excursion":
			var d: Dictionary = WeekLib.drill_by_id(act)
			if not d.is_empty():
				stamina_cost += WeekLib.drill_stamina(str(d.get("kind", "basic")))
	return {"gold": gold_cost, "stamina": stamina_cost}


## Can this monster take this drill, and if not, WHY not — the string is shown on the disabled
## button. ⚠️ Never a dead button with no explanation (`docs/UI_LAYOUT_RULES.md` rule 2's spirit).
##
## ⚠️ Stamina does NOT forbid a drill — `week.gd` mirrors React, where low stamina is a 0.5
## multiplier and never a gate. So this returns a WARNING, not a refusal. The only true refusal is
## the league cap, which is the game's real ceiling (`game.ts:361 statCapFor`).
func drill_note(mi, drill_id: String, cap: float) -> Dictionary:
	var d: Dictionary = WeekLib.drill_by_id(drill_id)
	if d.is_empty():
		return {"allowed": false, "note": "Unknown drill."}
	# ⚠️ Only the stats this drill RAISES can be at the ceiling. `week.gd` stores a paired penalty
	# as a NEGATIVE inside `gains` ({"STR": +12, "DEX": -4}); counting that stat here would refuse
	# a perfectly good drill because the stat it DAMAGES happens to be maxed.
	var gains: Dictionary = d.get("gains", {})
	var at_cap := true
	var any_raised := false
	for stat in gains.keys():
		if float(gains[stat]) <= 0.0:
			continue
		any_raised = true
		if float(mi.stats.get(stat, 0.0)) < cap - 0.001:
			at_cap = false
			break
	if not any_raised:
		at_cap = false
	if at_cap:
		return {"allowed": false, "note": "At the league ceiling — win promotion to train this further."}
	var stam: float = WeekLib.drill_stamina(str(d.get("kind", "basic")))
	if mi.stamina < 30.0:
		return {"allowed": true, "note": "Exhausted — gains halved. A rest week would pay for itself."}
	if mi.stamina < stam:
		return {"allowed": true, "note": "Tired — this will bottom out its stamina."}
	return {"allowed": true, "note": ""}


## ⚠️ THE ONLY THING THAT MOVES THE CLOCK. Runs the tick over the whole stable, clears the plans,
## rerolls prices, and reports what happened so the feeding screen can narrate it.
func advance(monsters: Array) -> Dictionary:
	var before: Dictionary = {}
	for mi in monsters:
		before[mi.id] = {
			"stats": mi.stats.duplicate(),
			"stamina": mi.stamina,
			"happiness": mi.happiness,
		}

	var gold_before: int = Career.gold if has_node("/root/Career") else 0
	var cap: float = Career.current_stat_cap() if has_node("/root/Career") else 300.0
	var league: String = Career.current_league_name() if has_node("/root/Career") else "Wood"

	# ⚠️ The freezer bills EVERY week, and that rent is the only thing stopping the Lab from being
	# an infinite barn. week.gd charges `rental` ONCE per week (not per monster), which is exactly
	# the shape this needs.
	var rental: int = (Roster.frozen.size() if has_node("/root/Roster") else 0) * RENTAL_PER_FROZEN
	var result: Dictionary = WeekLib.advance_week(monsters, plans, gold_before, rental, food_market, cap, league)
	var gold_after: int = int(result.get("gold", gold_before))
	if has_node("/root/Career"):
		Career.gold = gold_after
		Career.week += 1

	# Per-monster deltas, for the feeding screen's narration.
	var lines: Array = []
	for mi in monsters:
		var b: Dictionary = before.get(mi.id, {})
		if b.is_empty():
			continue
		var stat_moves: Array = []
		for stat in ["STR", "DEX", "CON", "WIS", "INT", "CHA"]:
			var delta: float = float(mi.stats.get(stat, 0.0)) - float(b["stats"].get(stat, 0.0))
			if absf(delta) >= 0.5:
				stat_moves.append("%+d %s" % [int(round(delta)), stat])
		lines.append({
			"name": mi.species_name,
			"stats": stat_moves,
			"stamina": mi.stamina - float(b["stamina"]),
			"happiness": mi.happiness - int(b["happiness"]),
		})

	plans.clear()
	for mi in monsters:
		mi.fed_this_week = false
	reroll_food_prices()

	var wk: int = Career.week if has_node("/root/Career") else 0
	var report := {"week": wk, "goldSpent": gold_before - gold_after, "monsters": lines}
	week_advanced.emit(wk, report)
	return report
