extends Node
const WeekLib = preload("res://scripts/week.gd")

func _ready() -> void:
	print("=== FOOD IN THE WEEKLY PLAN ===\n")
	Career.reset_new_game()
	Roster.reset_to_empty()
	Roster._generate_starting_roster()
	while Roster.monsters.size() > 1:
		Roster.monsters.pop_back()
	var m = Roster.monsters[0]

	print("--- 6 weeks: drill + PAID food every week ---")
	print("  wk | gold | stamina | happy | STR")
	for wk in range(6):
		WeekPlan.set_activity(m.id, "weights")
		WeekPlan.set_food(m.id, "meat")
		WeekPlan.advance(Roster.monsters)
		print("  %3d | %4d |  %5.1f  |  %2d   | %5.1f" % [
			Career.week, Career.gold, m.stamina, m.happiness, m.stats["STR"]])

	print("\n--- 3 weeks: drill + FORAGE (free) ---")
	print("  wk | gold | stamina | happy")
	for wk in range(3):
		WeekPlan.set_activity(m.id, "weights")
		WeekPlan.set_forage(m.id)
		WeekPlan.advance(Roster.monsters)
		print("  %3d | %4d |  %5.1f  |  %2d" % [Career.week, Career.gold, m.stamina, m.happiness])

	print("\n  VERDICT: paid food drains gold; forage is free but costs stamina + happiness.")
	get_tree().quit(0)
