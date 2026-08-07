## Does the AI now USE a cleanse when an ally is hard-controlled?
extends Node
const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const SpatialSimScript = preload("res://scripts/spatial_sim.gd")
const StatusMathLib = preload("res://scripts/status_math.gd")
const ClassifyLib = preload("res://scripts/classify.gd")
const DeriveLib = preload("res://scripts/derive.gd")
var _by_name := {}

func _mk(nm: String, ms: Array, wis: float = 250.0):
	var mi = MonsterInstanceScript.new()
	mi.id = nm; mi.species_id = "test"; mi.species_name = nm; mi.body = "Mammal"
	mi.stats = {"STR": 200.0, "DEX": 200.0, "CON": 200.0, "WIS": wis, "INT": 200.0, "CHA": 200.0}
	mi.class_name_ = ClassifyLib.class_for_stats(mi.stats)
	mi.basic_attack = ClassifyLib.basic_attack_for(mi.stats)
	mi.max_hp = DeriveLib.max_hp(200.0); mi.hp = mi.max_hp
	mi.max_mp = DeriveLib.max_mana(wis, 200.0); mi.mp = mi.max_mp
	mi.moveset = ms
	return mi

## a control move to stun with, and a cleanse to answer it
func _control_moves() -> Array:
	var out: Array = []
	for n in _by_name:
		var m = _by_name[n]
		var st = m.get("status")
		if st != null and StatusMathLib.HARD_CONTROL.has(str(st.get("kind", ""))):
			out.append(m)
		if out.size() >= 3: break
	return out

func _run(with_cleanse: bool) -> Dictionary:
	var ctrl := _control_moves()
	var cleanse = _by_name.get("Clarity")
	var filler = _by_name.get("Scrap")
	var a_moves: Array = [filler]
	if with_cleanse and cleanse != null:
		a_moves = [cleanse, filler]
	var a := [_mk("A_CLEANSER", a_moves), _mk("A_BODY", [filler])]
	var b := [_mk("B_CONTROL", ctrl), _mk("B_BODY", [filler])]
	var sim = SpatialSimScript.new(a, b, 31337, {"formation":"tight"}, {"formation":"loose"}, {}, [])
	return await sim.run()

func _count(r: Dictionary) -> Dictionary:
	var cleanse_casts := 0
	var control_applied := 0
	var control_ticks := 0
	for fr in r.get("frames", []):
		for sh in fr.get("shots", []):
			pass
		for u in fr.get("units", []):
			if not bool(u.get("alive", true)): continue
			for st in u.get("statuses", []):
				if StatusMathLib.HARD_CONTROL.has(str(st)):
					control_ticks += 1
	for e in r.get("log", []):
		if str(e.get("kind","")) == "cleanse":
			cleanse_casts += 1
		if str(e.get("kind","")) == "status_apply" and StatusMathLib.HARD_CONTROL.has(str(e.get("status",""))):
			control_applied += 1
	return {"cleanse_casts": cleanse_casts, "control_applied": control_applied, "control_ticks": control_ticks}

func _ready() -> void:
	var f := FileAccess.open("res://data/data.json", FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text()); f.close()
	for m in d.get("moves", []): _by_name[str(m.get("name"))] = m

	print("=== DOES THE AI CLEANSE? ===")
	var ctrl := _control_moves()
	var names: Array = []
	for c in ctrl: names.append(str(c.get("name")))
	print("  team B's control kit: %s" % str(names))
	print("  team A's cleanser holds: Clarity (ally-target)\n")

	var off: Dictionary = await _run(false)
	var a := _count(off)
	print("--- WITHOUT a cleanse in the loadout ---")
	print("  cleanse casts %d   control applications %d   unit-ticks spent controlled %d" % [
		a["cleanse_casts"], a["control_applied"], a["control_ticks"]])

	var on: Dictionary = await _run(true)
	var b := _count(on)
	print("\n--- WITH Clarity in the loadout ---")
	print("  cleanse casts %d   control applications %d   unit-ticks spent controlled %d" % [
		b["cleanse_casts"], b["control_applied"], b["control_ticks"]])

	print("\n=== VERDICT ===")
	if b["cleanse_casts"] > 0:
		print("  The AI CASTS the cleanse: %d times." % b["cleanse_casts"])
		var delta: int = a["control_ticks"] - b["control_ticks"]
		print("  Time spent under hard control: %d -> %d unit-ticks (%+d)" % [
			a["control_ticks"], b["control_ticks"], -delta])
		print("  %s" % ("Control is measurably shorter — the counter-play works." if delta > 0
			else "⚠️ Cast, but control time did NOT drop — needs a look."))
	else:
		print("  *** The AI still never casts it. ***")
	get_tree().quit(0)
