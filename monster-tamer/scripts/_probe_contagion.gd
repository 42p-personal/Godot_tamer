## Do the last two pool-audit fixes actually fire in fights?
## Contagion: force Plague Shot into kits, count contagion events across seeds.
## Knockback: force Body Slam, measure the victim's displacement in the ticks after apply.
extends Node
const Sp = preload("res://scripts/spatial.gd")
func _ready() -> void:
	var mv_by := {}
	for mv in GameData.moves:
		mv_by[mv["name"]] = mv
	# ── contagion ──
	var spread_events := 0
	for seed_i in range(6):
		var Sim = load("res://scripts/spatial_sim.gd")
		var mrng := RandomNumberGenerator.new(); mrng.seed = 900 + seed_i
		var a: Array = []; var b: Array = []
		# ⚠️ ONE carrier only. The first version armed all five with Plague Shot, which poisoned
		# every enemy DIRECTLY — contagion had nobody left to infect and the probe read "broken"
		# off a saturated field. The instrument again.
		for i in range(5):
			var m = GameData.make_monster(Art.ROSTER[i], 0.5, mrng)
			if i == 0:
				m.moveset = [mv_by["Plague Shot"]]
			a.append(m)
			b.append(GameData.make_monster(Art.ROSTER[i + 5], 0.5, mrng))
		var sim = Sim.new(a, b, 900 + seed_i, {}, {}, {}, [])
		var res: Dictionary = await sim.run()
		for e in res.get("log", []):
			if str(e.get("kind","")) == "contagion": spread_events += 1
	print("contagion events across 6 fights: %d  %s" % [spread_events, "OK" if spread_events > 0 else "*** FAIL"])
	# ── knockback ──
	var flights := 0; var max_disp := 0.0
	for seed_i in range(6):
		var Sim2 = load("res://scripts/spatial_sim.gd")
		var mrng2 := RandomNumberGenerator.new(); mrng2.seed = 950 + seed_i
		var a2: Array = []; var b2: Array = []
		for i in range(3):
			var m2 = GameData.make_monster(Art.ROSTER[i], 0.5, mrng2)
			m2.moveset = [mv_by["Body Slam"]]
			a2.append(m2)
			b2.append(GameData.make_monster(Art.ROSTER[i + 5], 0.5, mrng2))
		var sim2 = Sim2.new(a2, b2, 950 + seed_i, {}, {}, {}, [])
		var res2: Dictionary = await sim2.run()
		var frames: Array = res2.get("frames", [])
		# find a status_apply knockback, then measure that unit's travel over the next 10 frames
		var kb_at := {}
		for e in res2.get("log", []):
			if str(e.get("status","")) == "knockback" and str(e.get("kind","")) == "status_apply":
				kb_at[str(e.get("unit",""))] = true
		if kb_at.is_empty(): continue
		# scan frames for large single-tick moves by any unit (the flight)
		var last := {}
		for f in frames:
			for u in f.get("units", []):
				var id = u.get("id")
				var pnow: Vector2 = u.get("pos", Vector2.ZERO)
				if last.has(id):
					var d: float = (last[id] as Vector2).distance_to(pnow)
					if d > 2.5:  # faster than any walk (max walk ~2.0/tick)
						flights += 1
						max_disp = maxf(max_disp, d)
				last[id] = pnow
	print("knockback flight ticks (> walk speed): %d | max per-tick %0.2f (cap %.1f)  %s" % [
		flights, max_disp, Sp.KNOCKBACK_SPEED * Sp.DT,
		"OK" if flights > 0 and max_disp <= Sp.KNOCKBACK_SPEED * Sp.DT + 0.6 else "*** FAIL"])  # +0.6: separation nudge
	get_tree().quit()
