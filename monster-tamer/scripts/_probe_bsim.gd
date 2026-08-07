## Does battle_sim.gd (the NON-spatial reference engine) apply friendly effects and healing?
extends Node
const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const BattleSimScript = preload("res://scripts/battle_sim.gd")
const ClassifyLib = preload("res://scripts/classify.gd")
const DeriveLib = preload("res://scripts/derive.gd")

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

func _ready() -> void:
	var f := FileAccess.open("res://data/data.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()); f.close()
	var by := {}
	for m in d.get("moves", []):
		by[str(m.get("name"))] = m

	print("=== battle_sim.gd — friendly effects and healing ===")
	var kit: Array = []
	for n in ["Guard", "Enrage", "Steady Vigil", "Mending Surge", "Scrap"]:
		if by.has(n):
			kit.append(by[n])
	print("  team A carries Guard(self) Enrage(self) Steady Vigil(ally) Mending Surge(ally, power 97 = HEAL)")

	var a := [_mk("A1", kit), _mk("A2", kit)]
	var b := [_mk("B1", [by["Scrap"]]), _mk("B2", [by["Scrap"]])]
	var sim = BattleSimScript.new(a, b, 4242)
	var r: Dictionary = sim.run()

	var kinds := {}
	var buffs := 0
	var heals := 0
	var healed := 0
	for e in r.get("log", []):
		var k := str(e.get("kind", ""))
		kinds[k] = int(kinds.get(k, 0)) + 1
		if k == "buff":
			buffs += 1
		elif k == "heal":
			heals += 1
			healed += int(e.get("amount", 0))

	print("  winner=%s  log kinds: %s" % [r.get("winner", "?"), str(kinds)])
	print("  'buff' events: %d" % buffs)
	print("  'heal' events: %d   total HP restored: %d" % [heals, healed])
	var verdict := "*** STILL BROKEN ***"
	if buffs > 0 and heals > 0:
		verdict = "effects land AND healing works"
	elif buffs > 0:
		verdict = "effects land, but healing still does nothing"
	print("  VERDICT: %s" % verdict)
	get_tree().quit(0)
