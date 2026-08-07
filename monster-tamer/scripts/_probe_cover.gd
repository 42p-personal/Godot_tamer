## DOES COVER ACTUALLY DO ANYTHING? Two separate questions, measured separately:
##   A. Does the SIM apply it — how many line-of-fire checks in a real fight cross an obstacle?
##   B. Does the AI SEEK it — does any unit end a tick better covered than it started?
## ⚠️ (A) can pass while (B) fails completely, and that is the interesting case: cover that
## happens TO you is a dice roll, cover you CHOSE is a tactic.
extends Node
const Sp = preload("res://scripts/spatial.gd")

func _ready() -> void:
	var Sim = load("res://scripts/spatial_sim.gd")
	var Layout = load("res://scripts/arena_layout.gd")
	var team_a: Array = []
	var team_b: Array = []
	for i in range(5):
		team_a.append(GameData.make_monster(Art.ROSTER[i], 0.3))
		team_b.append(GameData.make_monster(Art.ROSTER[i + 5], 0.3))
	var rng := RandomNumberGenerator.new(); rng.seed = 20260804
	var lay: Dictionary = Layout.generate(5, "Platinum", rng)
	var obs: Array = lay.get("obstacles", [])
	var sim = Sim.new(team_a, team_b, 20260804, {}, {}, {}, obs)
	var res: Dictionary = await sim.run()
	var frames: Array = res.get("frames", [])
	print("obstacles: %d   frames: %d" % [obs.size(), frames.size()])
	# ⚠️ ONLY `blocking` GRADE BREAKS LINE OF SIGHT (`Spatial.COVER_BLOCKS_LOS_GRADE`).
	# Cover-SEEKING can only work if there is something to hide BEHIND — soft and hard cover shave
	# accuracy but hide nobody, so they are irrelevant to a unit trying to break LOS. If this
	# footprint is tiny, no amount of AI can find cover that is not there.
	var by_grade := {}
	var block_area := 0.0
	for o in obs:
		var g := str(o.get("grade", "soft"))
		by_grade[g] = int(by_grade.get(g, 0)) + 1
		if g == Sp.COVER_BLOCKS_LOS_GRADE:
			var rr: Rect2 = o["rect"]
			block_area += rr.size.x * rr.size.y
	var gs: Vector2 = Sp.ground_size(5)
	print("by grade: %s" % str(by_grade))
	print("LOS-BLOCKING footprint: %.0f sq units = %.3f%% of the %.0f x %.0f ground" % [
		block_area, 100.0 * block_area / (gs.x * gs.y), gs.x, gs.y])
	print("")

	# ── A. every attacker->target line, every frame, tested against the real cover function ──
	var lines := 0; var soft := 0; var hard := 0; var blocked := 0
	# ── B. did a unit's own cover state IMPROVE between frames while it was moving? ──
	var improved := 0; var worsened := 0; var moves := 0
	var prev_cov := {}
	var prev_pos := {}
	for f in frames:
		var us: Array = f.get("units", [])
		for i in range(us.size()):
			if not bool(us[i].get("alive", true)): continue
			var tid := int(us[i].get("targetId", -1))
			if tid < 0 or tid >= us.size(): continue
			if not bool(us[tid].get("alive", true)): continue
			var c: Dictionary = Sp.cover_between(us[i]["pos"], us[tid]["pos"], obs)
			lines += 1
			if c["blocked"]: blocked += 1
			elif c["accPenalty"] >= Sp.COVER_HARD_ACC: hard += 1
			elif c["accPenalty"] > 0.0: soft += 1

			# How covered is THIS unit from the enemy shooting at it? Track the change.
			var mine: float = (1.0 if c["blocked"] else float(c["accPenalty"]))
			var key := i
			if prev_cov.has(key):
				var p: Vector2 = prev_pos[key]
				if (us[i]["pos"] as Vector2).distance_to(p) > 0.05:
					moves += 1
					if mine > float(prev_cov[key]) + 0.001: improved += 1
					elif mine < float(prev_cov[key]) - 0.001: worsened += 1
			prev_cov[key] = mine
			prev_pos[key] = us[i]["pos"]

	print("A. SIM APPLIES COVER")
	print("   lines of fire tested : %d" % lines)
	print("   crossing soft cover  : %-6d (%.1f%%)" % [soft, 100.0 * soft / maxf(1, lines)])
	print("   crossing hard cover  : %-6d (%.1f%%)" % [hard, 100.0 * hard / maxf(1, lines)])
	print("   BLOCKED outright     : %-6d (%.1f%%)" % [blocked, 100.0 * blocked / maxf(1, lines)])
	print("   any cover at all     : %-6d (%.1f%%)\n" % [soft + hard + blocked,
		100.0 * (soft + hard + blocked) / maxf(1, lines)])
	# ⚠️ SCOPED TO THE POPULATION THE BEHAVIOUR APPLIES TO. Cover-seeking lives in the WITHDRAWAL
	# branches — a pushing unit is supposed to walk into the open, and averaging it in buries the
	# signal under two thousand ticks of units doing something else entirely.
	var w_moves := 0; var w_improved := 0; var w_worsened := 0
	var pc := {}; var pp := {}
	for f in frames:
		var us: Array = f.get("units", [])
		for i in range(us.size()):
			if not bool(us[i].get("alive", true)): continue
			var it := str(us[i].get("intent", ""))
			var tid := int(us[i].get("targetId", -1))
			if tid < 0 or tid >= us.size() or not bool(us[tid].get("alive", true)): continue
			var c: Dictionary = Sp.cover_between(us[i]["pos"], us[tid]["pos"], obs)
			var mine: float = (1.0 if c["blocked"] else float(c["accPenalty"]))
			# ⚠️ COVER FROM THE THREATS, NOT FROM THE TARGET. The previous version measured the line
			# between a unit and whoever it was ATTACKING — but cover-seeking optimises against
			# whoever is SHOOTING IT, and for a withdrawing unit those are usually different people.
			# It was answering a question nobody asked, so "cover-seeking does nothing" was never
			# actually established by it.
			var shelter := 0.0
			var threat_n := 0
			for e in range(us.size()):
				if e == i or not bool(us[e].get("alive", true)): continue
				var same_side: bool = (e < 5) == (i < 5)
				if same_side: continue
				if int(us[e].get("targetId", -1)) != i: continue      # not shooting at me
				threat_n += 1
				if bool(Sp.cover_between(us[i]["pos"], us[e]["pos"], obs)["blocked"]):
					shelter += 1.0
			mine = (shelter / float(threat_n)) if threat_n > 0 else -1.0
			var withdrawing: bool = it in ["falling back", "bailing out", "disengaging", "breaking off"]
			if mine < 0.0:
				pc.erase(i); pp[i] = us[i]["pos"]; continue    # nobody shooting at it this tick
			if pc.has(i) and withdrawing:
				if (us[i]["pos"] as Vector2).distance_to(pp[i]) > 0.05:
					w_moves += 1
					if mine > float(pc[i]) + 0.001: w_improved += 1
					elif mine < float(pc[i]) - 0.001: w_worsened += 1
			pc[i] = mine; pp[i] = us[i]["pos"]
	print("B2. COVER-SEEKING, SCOPED TO WITHDRAWING UNITS ONLY")
	print("   withdrawing moves    : %d" % w_moves)
	print("   cover improved       : %-5d (%.0f%%)" % [w_improved, 100.0*w_improved/maxf(1,w_moves)])
	print("   cover worsened       : %-5d (%.0f%%)" % [w_worsened, 100.0*w_worsened/maxf(1,w_moves)])
	print("")
	print("B. AI SEEKS COVER  (ALL units — includes everyone deliberately walking into the open)")
	print("   moving ticks         : %d" % moves)
	print("   cover improved       : %-6d (%.1f%%)" % [improved, 100.0 * improved / maxf(1, moves)])
	print("   cover worsened       : %-6d (%.1f%%)" % [worsened, 100.0 * worsened / maxf(1, moves)])
	# ── C. WHAT DOES A BLOCKED LINE COST? `_can_resolve` rejects a move whose line is blocked, so
	# a unit behind blocking cover cannot select that move. Does it pick another, or stall?
	# ⚠️ THREE WAYS, NOT TWO. The first version of this counted only "acting", so a unit that
	# steps out from behind cover — exactly the fix — scored identically to one standing there
	# doing nothing, because repositioning is `advance`, not `attack`. The metric could not see
	# its own success. IDLE is the failure state; moving to fix the block is not.
	var blocked_idle := 0; var blocked_acting := 0; var blocked_moving := 0
	var open_idle := 0; var open_acting := 0; var open_moving := 0
	var intents := {}
	for f in frames:
		var us: Array = f.get("units", [])
		for i in range(us.size()):
			if not bool(us[i].get("alive", true)): continue
			var tid := int(us[i].get("targetId", -1))
			if tid < 0 or tid >= us.size() or not bool(us[tid].get("alive", true)): continue
			var c: Dictionary = Sp.cover_between(us[i]["pos"], us[tid]["pos"], obs)
			var st := str(us[i].get("state", "idle"))
			var acting: bool = st in ["attack", "cast"]
			var moving: bool = st in ["advance", "retreat"]
			if c["blocked"]:
				var it := str(us[i].get("intent", ""))
				intents[it] = int(intents.get(it, 0)) + 1
				if acting: blocked_acting += 1
				elif moving: blocked_moving += 1
				else: blocked_idle += 1
			else:
				if acting: open_acting += 1
				elif moving: open_moving += 1
				else: open_idle += 1
	var bt: float = maxf(1, blocked_acting + blocked_idle + blocked_moving)
	var ot: float = maxf(1, open_acting + open_idle + open_moving)
	print("C. WHAT A BLOCKED LINE COSTS  (IDLE is the failure state, not `moving`)")
	print("   line BLOCKED : acting %2.0f%%  moving %2.0f%%  IDLE %2.0f%%   (%d ticks)" % [
		100.0*blocked_acting/bt, 100.0*blocked_moving/bt, 100.0*blocked_idle/bt, bt])
	print("   line OPEN    : acting %2.0f%%  moving %2.0f%%  IDLE %2.0f%%   (%d ticks)" % [
		100.0*open_acting/ot, 100.0*open_moving/ot, 100.0*open_idle/ot, ot])
	print("   what blocked units are DOING: %s" % str(intents))
	print("")
	print("   ⚠️ improved ~= worsened means movement is UNCORRELATED with cover — it is weather,")
	print("      not a decision. A unit that sought cover would improve far more than it worsened.")
	get_tree().quit()
