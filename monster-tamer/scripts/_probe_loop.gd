## END-TO-END LOOP PROOF. Throwaway probe.
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_loop.tscn
##
## Plays the actual game loop headlessly: new game -> buy -> plan -> advance week, repeatedly.
## Answers the user's complaint directly: is training still infinite?
extends Node

const WeekLib = preload("res://scripts/week.gd")


func _ready() -> void:
	print("=== END-TO-END LOOP PROOF ===\n")

	Career.reset_new_game()
	Roster.reset_to_empty()
	print("--- new game ---")
	print("  monsters: %d   week: %d   gold: %d   barn: %d" % [
		Roster.monsters.size(), Career.week, Career.gold, Career.barn_capacity])
	if Roster.monsters.size() != 0:
		print("  *** FAIL: a new game must start with an EMPTY stable ***")
	else:
		print("  OK — empty stable, the first monster is a decision the player makes")

	# Acquire two monsters the way the Market does.
	Roster._generate_starting_roster()
	while Roster.monsters.size() > Career.barn_capacity:
		Roster.monsters.pop_back()
	print("\n--- after buying to the barn limit ---")
	print("  monsters: %d (barn holds %d)" % [Roster.monsters.size(), Career.barn_capacity])

	var m = Roster.monsters[0]
	print("\n--- 15 weeks: book 'powerlift' every week, then Advance ---")
	print("  wk | gold | stamina |  STR  | gained | plan spent?")
	var prev_str: float = float(m.stats["STR"])
	for wk in range(1, 16):
		WeekPlan.set_activity(m.id, "powerlift")
		var str_at_book: float = float(m.stats["STR"])
		# ⚠️ THE KEY ASSERTION: booking a drill must change NOTHING.
		var booked_changed := absf(str_at_book - prev_str) > 0.001
		WeekPlan.advance(Roster.monsters)
		var now: float = float(m.stats["STR"])
		print("  %3d | %4d |  %5.1f  | %5.1f | %+5.1f  | %s" % [
			Career.week, Career.gold, m.stamina, now, now - prev_str,
			"*** BOOKING SPENT — BUG ***" if booked_changed else "no"])
		prev_str = now

	print("\n--- can the player click a drill 10x inside ONE week? ---")
	var before: float = float(m.stats["STR"])
	for i in range(10):
		WeekPlan.set_activity(m.id, "powerlift")
	var after: float = float(m.stats["STR"])
	print("  10 bookings, no Advance Week:  STR %.1f -> %.1f  (delta %+.1f)" % [before, after, after - before])
	if absf(after - before) < 0.001:
		print("  VERDICT: booking is FREE and IDEMPOTENT — the infinite-training bug is dead.")
		print("           one action per monster per WEEK; the clock is the bound.")
	else:
		print("  VERDICT: *** STILL BROKEN — clicking still moves stats ***")

	print("\n--- the real ceiling: league cap ---")
	print("  %s cap = %d   STR now %.1f" % [Career.current_league_name(), int(Career.current_stat_cap()), m.stats["STR"]])
	print("\n=== done ===")
	get_tree().quit(0)
