extends Node
func _ready() -> void:
	print("=== TUTORIAL STEP MACHINE ===\n")
	Career.reset_new_game(); Roster.reset_to_empty(); Tutorial.reset()
	print("  start                    -> %s" % Tutorial.current_id())
	Roster._generate_starting_roster()
	while Roster.monsters.size() > 1: Roster.monsters.pop_back()
	var m = Roster.monsters[0]
	Tutorial.poll(); print("  after buying             -> %s" % Tutorial.current_id())
	WeekPlan.set_food(m.id, "meat")
	Tutorial.poll(); print("  after choosing food      -> %s" % Tutorial.current_id())
	WeekPlan.set_activity(m.id, "weights")
	Tutorial.poll(); print("  after booking a drill    -> %s" % Tutorial.current_id())
	WeekPlan.advance(Roster.monsters)
	Tutorial.poll(); print("  after advancing a week   -> %s" % Tutorial.current_id())
	print("\n  --- the regression: burn 4 weeks WITHOUT ever resting ---")
	for i in range(4):
		WeekPlan.set_activity(m.id, "powerlift")
		WeekPlan.advance(Roster.monsters)
		Tutorial.poll()
	print("  week %d, stamina %.0f      -> %s" % [Career.week, m.stamina, Tutorial.current_id()])
	if Tutorial.current_id() == "stamina":
		print("  OK — the stamina lesson HELD. A week counter used to skip it entirely.")
	else:
		print("  *** FAIL: stamina step skipped again ***")
	WeekPlan.set_activity(m.id, "rest")
	Tutorial.poll(); print("  after booking a rest     -> %s" % Tutorial.current_id())
	get_tree().quit(0)
