extends Node
func _ready() -> void:
	print("=== LAB — does the freezer actually bill? ===\n")
	Career.reset_new_game(); Roster.reset_to_empty(); Roster._generate_starting_roster()
	print("  barn %d, frozen %d, gold %d" % [Roster.monsters.size(), Roster.frozen.size(), Career.gold])
	# freeze three
	for i in range(3):
		Roster.frozen.append(Roster.monsters.pop_back())
	print("  after freezing 3 -> barn %d, frozen %d" % [Roster.monsters.size(), Roster.frozen.size()])
	print("\n  wk | gold | rent charged")
	var prev := Career.gold
	for w in range(4):
		WeekPlan.advance(Roster.monsters)
		print("  %3d | %4d | %d" % [Career.week, Career.gold, prev - Career.gold])
		prev = Career.gold
	print("\n  expected 3 x 12 = 36g/week (plus any food, which is none here)")
	print("\n  --- do frozen monsters age? they must NOT ---")
	var f = Roster.frozen[0]
	var age_before: int = f.age_weeks
	WeekPlan.advance(Roster.monsters)
	print("  frozen monster age: %d -> %d  (%s)" % [age_before, f.age_weeks,
		"OK, suspended" if f.age_weeks == age_before else "*** AGEING WHILE FROZEN ***"])
	get_tree().quit(0)
