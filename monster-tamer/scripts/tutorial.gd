## THE TUTORIAL — a step POINTER on game state, not a scripted cutscene.
##
## ⚠️ IT ADVANCES WHEN THE PLAYER DOES THE THING, never on a timer and never on a click-through.
## Each step declares a `done` test read from live state, so the tutorial cannot desync from the
## game, cannot be skipped by accident, and survives a save/load with no extra plumbing.
##
## Mirrors `town.ts:582 newGame()`'s `tutorialEnabled` / `tutorialDismissed` / `tutorialStep`.
##
## ⚠️ STEP 5 (stamina) IS THE ONE THAT MATTERS. The user's loudest complaint about this build was
## *"i can still train infintely"*. A tutorial that does not teach what bounds training has failed
## at its only real job — so that step is the one written most carefully, and it tells the truth:
## stamina does NOT stop training, it HALVES it, and the wall is the league cap.
##
## Autoload name: `Tutorial`.
extends Node

signal step_changed(step_id: String)

var enabled: bool = true
var dismissed: bool = false
var step_index: int = 0

## ⚠️ Each `done` is a Callable read from LIVE state — never a flag this file sets itself, or the
## tutorial and the game can disagree and the player gets told to do something already done.
var _steps: Array = []


func _ready() -> void:
	_steps = [
		{
			"id": "buy",
			"title": "Recruit your first monster",
			"body": "Your stable is empty and you have 500 gold. The Market is in the Town. The barn holds two — choose well, because a third costs an upgrade.",
			"done": func() -> bool: return Roster.monsters.size() > 0,
		},
		{
			"id": "food",
			"title": "Decide what it eats",
			"body": "Open Training and pick this week's food. Paid food costs gold. Foraging is free but costs stamina and heart — hunger is never free, it is only ever paid differently.",
			"done": func() -> bool: return _any_planned_food(),
		},
		{
			"id": "plan",
			"title": "Book a drill — it spends nothing yet",
			"body": "Booking a drill only writes the plan. No stat moves until the week does. Take your time and read what each drill costs.",
			"done": func() -> bool: return _any_planned_drill(),
		},
		{
			"id": "advance",
			"title": "Advance the week",
			"body": "This is the only thing that moves the clock. It feeds the stable, runs every drill you booked, ages your monsters and pays the bills — all at once.",
			"done": func() -> bool: return Career.week >= 1,
		},
		{
			"id": "stamina",
			"title": "Tired monsters train badly",
			"body": "Every drill costs stamina. Below 30 a drill pays HALF — it does not stop, it just stops being worth it. A rest week often earns more than a tired drill does.\n\nBook a rest week to clear this.\n\nThe real ceiling is your league: train a stat to the Wood cap and only promotion raises it.",
			# ⚠️ THIS CONDITION USED TO BE `Career.week >= 3` AND IT SKIPPED THE STEP ENTIRELY.
			# `_advance_past_completed()` fast-forwards past anything already true, so a player who
			# advanced three weeks before reading the banner raced straight past the single most
			# important lesson in the tutorial — caught by driving the real flow, not by reading it.
			#
			# A week counter never proved the player LEARNED anything. Resting does: it is the
			# specific behaviour this step exists to teach, and it cannot be satisfied by accident.
			"done": func() -> bool: return _has_rested_deliberately(),
		},
		{
			"id": "tournament",
			"title": "Enter a cup",
			"body": "You will not command the fight. You set the tactics, and then you watch your read play out. Everything you decide before the bell is the whole of your skill.",
			"done": func() -> bool: return false,  # terminal — the tutorial ends here
		},
	]
	_advance_past_completed()


func _any_planned_food() -> bool:
	for mi in Roster.monsters:
		var p: Dictionary = WeekPlan.plan_for(mi.id)
		if str(p.get("food", "")) != "" or bool(p.get("forage", false)):
			return true
	return false


## ⚠️ "Rest" is also the DEFAULT plan, so a monster sitting untouched is not evidence of anything.
## Only a deliberate rest counts — one booked while the monster is actually tired enough for it to
## be the right call. Otherwise the step clears itself the instant the tutorial starts.
var _rest_seen: bool = false

func _has_rested_deliberately() -> bool:
	if _rest_seen:
		return true
	for mi in Roster.monsters:
		var p: Dictionary = WeekPlan.plan_for(mi.id)
		if mi.stamina < 60.0 and str(p.get("activity", "rest")) == "rest" and bool(p.get("chosen", false)):
			_rest_seen = true
			return true
	return false


func _any_planned_drill() -> bool:
	for mi in Roster.monsters:
		if str(WeekPlan.plan_for(mi.id).get("activity", "rest")) != "rest":
			return true
	return false


## Skip any step whose condition is ALREADY true — so a player who wanders off-script (buys two
## monsters before reading anything) is never told to do something they have done.
func _advance_past_completed() -> void:
	var moved := false
	while step_index < _steps.size() - 1 and bool(_steps[step_index]["done"].call()):
		step_index += 1
		moved = true
	if moved:
		step_changed.emit(current_id())


func poll() -> void:
	if not is_active():
		return
	var before := step_index
	_advance_past_completed()
	if step_index != before:
		step_changed.emit(current_id())


func is_active() -> bool:
	return enabled and not dismissed and step_index < _steps.size()


func current() -> Dictionary:
	if not is_active():
		return {}
	return _steps[step_index]


func current_id() -> String:
	var c := current()
	return str(c.get("id", ""))


func dismiss() -> void:
	dismissed = true
	step_changed.emit("")


func reset() -> void:
	step_index = 0
	dismissed = false
	_advance_past_completed()
