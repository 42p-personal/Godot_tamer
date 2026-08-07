## Do the three cleanse abilities actually remove hard control in the SPATIAL sim?
extends Node
const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const SpatialSimScript = preload("res://scripts/spatial_sim.gd")
const StatusMathLib = preload("res://scripts/status_math.gd")
const ClassifyLib = preload("res://scripts/classify.gd")
const DeriveLib = preload("res://scripts/derive.gd")

func _ready() -> void:
	print("=== DO CLEANSE ABILITIES ACTUALLY CLEANSE? ===\n")
	var f := FileAccess.open("res://data/data.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()); f.close()
	var moves: Array = d.get("moves", [])

	var cleansers: Array = []
	for m in moves:
		var e = m.get("effects")
		if e is Dictionary and e.get("cleanse"):
			cleansers.append(m)

	print("  HARD_CONTROL = %s\n" % str(StatusMathLib.HARD_CONTROL))
	print("  ability        target    routed via                 will it cleanse?")
	for m in cleansers:
		var tgt: String = str(m.get("target", "?"))
		# spatial_sim.gd:811 — ONLY target=="team" reaches _apply_team_effect, the real
		# buff/heal/cleanse path. "ally"/"self" fall through to _resolve_hit, a combat strike.
		var routed := "_apply_team_effect" if tgt == "team" else "_resolve_hit (combat strike)"
		var works := "YES" if tgt == "team" else "*** NO — effect never applied ***"
		print("  %-14s %-9s %-26s %s" % [str(m.get("name")), tgt, routed, works])

	print("\n  --- confirm by reading the code path ---")
	var src := FileAccess.open("res://scripts/spatial_sim.gd", FileAccess.READ)
	var text := src.get_as_text(); src.close()
	var idx := text.find("if fx.has(\"cleanse\")")
	if idx >= 0:
		# which function contains it?
		var before := text.substr(0, idx)
		var fn := before.rfind("func ")
		var line_end := before.find("\n", fn)
		print("  the cleanse code lives in: %s" % before.substr(fn, line_end - fn).strip_edges())
	print("\n  --- does the AI ever ask for a cleanse? ---")
	for path in ["res://scripts/ai/monster_tree.gd", "res://scripts/spatial_ai.gd"]:
		var g := FileAccess.open(path, FileAccess.READ)
		if g == null: continue
		var t := g.get_as_text(); g.close()
		print("  %-38s mentions cleanse: %s" % [path, "yes" if t.to_lower().find("cleanse") >= 0 else "NO"])
	print("
  --- RUNTIME TEST: cast a self-target buff, does the effect land? ---")
	await _runtime_test()
	get_tree().quit(0)


func _mk(nm: String, ms: Array):
	var mi = MonsterInstanceScript.new()
	mi.id = nm; mi.species_id = "test"; mi.species_name = nm; mi.body = "Mammal"
	mi.stats = {"STR": 200.0, "DEX": 200.0, "CON": 200.0, "WIS": 250.0, "INT": 200.0, "CHA": 200.0}
	mi.class_name_ = ClassifyLib.class_for_stats(mi.stats)
	mi.basic_attack = ClassifyLib.basic_attack_for(mi.stats)
	mi.max_hp = DeriveLib.max_hp(200.0); mi.hp = mi.max_hp
	mi.max_mp = DeriveLib.max_mana(250.0, 200.0); mi.mp = mi.max_mp
	mi.moveset = ms
	return mi


func _runtime_test() -> void:
	var f := FileAccess.open("res://data/data.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()); f.close()
	var moves: Array = d.get("moves", [])
	var by_name := {}
	for m in moves: by_name[str(m.get("name"))] = m

	# Guard: target=self, effects={guard}. If self-target buffs work, a guard mod must appear.
	var probe_moves: Array = []
	for n in ["Guard", "Enrage", "Clarity", "Mending Surge"]:
		if by_name.has(n): probe_moves.append(by_name[n])
	if probe_moves.is_empty():
		print("    (probe moves not found)")
		return

	var a := [_mk("BUFFER", probe_moves), _mk("A2", probe_moves)]
	var b := [_mk("B1", [by_name.get("Scrap", moves[0])]), _mk("B2", [by_name.get("Scrap", moves[0])])]
	var sim = SpatialSimScript.new(a, b, 777, {"formation":"tight"}, {"formation":"loose"}, {}, [])
	var r: Dictionary = await sim.run()

	# scan every frame for a buff/guard ever appearing on team A
	var saw_buff := false
	var casts := 0
	for fr in r.get("frames", []):
		for sh in fr.get("shots", []):
			if str(sh.get("move","")) in ["Guard", "Enrage", "Clarity"]:
				casts += 1
	for e in r.get("log", []):
		if str(e.get("kind","")) == "buff":
			saw_buff = true
	print("    fight ran %.1fs, winner %s" % [r.get("duration",0.0), r.get("winner","?")])
	print("    self/ally buff moves CAST: %d" % casts)
	print("    'buff' events in the log: %s" % ("YES - effects land" if saw_buff else "*** NONE - buffs never applied ***"))
	var heals := 0
	var healed := 0
	for e in r.get("log", []):
		if str(e.get("kind","")) == "heal":
			heals += 1
			healed += int(e.get("amount", 0))
	print("    'heal' events: %d   HP restored: %d   %s" % [heals, healed,
		"(healing works)" if heals > 0 else "*** NO HEALING ***"])
