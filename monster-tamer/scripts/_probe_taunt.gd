## Does a landed taunt actually FORCE the victim's target? Give a tanky unit Challenge, watch
## whether enemies that were hitting someone else swing to the taunter while taunted.
extends Node
func _ready() -> void:
	var Sim = load("res://scripts/spatial_sim.gd")
	var mrng := RandomNumberGenerator.new(); mrng.seed = 42
	var a: Array = []; var b: Array = []
	for i in range(3):
		a.append(GameData.make_monster(Art.ROSTER[i], 0.5, mrng))
		b.append(GameData.make_monster(Art.ROSTER[i + 5], 0.5, mrng))
	# force Challenge into a[0]'s kit
	var challenge: Dictionary = {}
	for mv in GameData.moves:
		if mv["name"] == "Challenge": challenge = mv
	a[0].moveset = [challenge]
	var sim = Sim.new(a, b, 42, {}, {}, {}, [])
	var res: Dictionary = await sim.run()
	var taunt_applied := 0
	var taunt_reasons := 0
	var taunt_status_frames := 0
	var swings := 0
	for e in res.get("log", []):
		if str(e.get("status","")) == "taunt": taunt_applied += 1
	var taunter_id := -1
	for f in res.get("frames", []):
		for u in f.get("units", []):
			if "taunted by" in str(u.get("reason","")): taunt_reasons += 1
			var sts: Array = u.get("statuses", [])
			for st in sts:
				var kind: String = str(st.get("kind", st)) if st is Dictionary else str(st)
				if kind == "taunt":
					taunt_status_frames += 1
					if int(u.get("targetId", -1)) == 0: swings += 1
	print("taunts applied: %d | victim-frames with taunt status: %d | of those, targeting the taunter: %d | 'taunted by' reasons: %d" % [
		taunt_applied, taunt_status_frames, swings, taunt_reasons])
	get_tree().quit()
