extends Node
func _ready() -> void:
	print("=== THE LADDER — can it actually be climbed? ===\n")
	Career.reset_new_game(); Roster.reset_to_empty()
	Roster._generate_starting_roster()
	print("  league    | team | cap  | roster | can enter?")
	for idx in range(Career.leagues.size()):
		var ts: int = Career.team_size_for_league(idx)
		print("  %-9s |  %d   | %4d |   %2d   | %s" % [
			Career.league_at(idx).get("name","?"), ts, int(Career.stat_cap_for_league(idx)),
			Roster.monsters.size(), "yes" if Roster.monsters.size() >= ts else "NO - need more"])

	print("\n--- entering the Wood cup repeatedly until promoted ---")
	var tries := 0
	while tries < 12 and Career.league_index == 0:
		tries += 1
		var out: Dictionary = Career.enter_league_tournament(0, 3)
		Career.week += 1
		print("  try %2d: %d/3 wins  swept=%s  promoted=%s" % [
			tries, out.get("wins",0), out.get("swept",false), out.get("promoted",false)])
		if out.get("promoted", false):
			break
	print("\n  now in: %s (cap %d)" % [Career.current_league_name(), int(Career.current_stat_cap())])
	if Career.league_index > 0:
		print("  OK — promotion works, the ladder moves.")
	else:
		print("  *** no promotion in %d tries — sweep may be unreachable at this roster ***" % tries)
	get_tree().quit(0)
