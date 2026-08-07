extends Node
const Sp = preload("res://scripts/spatial.gd")
const D = preload("res://scripts/derive.gd")
const SM = preload("res://scripts/status_math.gd")

func _ready() -> void:
	var f := FileAccess.open("res://data/data.json", FileAccess.READ)
	var moves: Array = JSON.parse_string(f.get_as_text())["moves"]
	var band := {}
	var interruptible := 0
	for mv in moves:
		var w: float = Sp.windup_of(mv, D.cast_time_of(mv))
		var k := ("instant <0.7" if w < 0.7 else ("telegraphed 1.0-1.5" if w <= 1.5 else "heavy >1.5"))
		band[k] = int(band.get(k, 0)) + 1
		if Sp.is_interruptible(w): interruptible += 1
	print("POOL WINDUPS: %s" % str(band))
	print("interruptible: %d of %d (%.0f%%)\n" % [interruptible, moves.size(), 100.0*interruptible/moves.size()])

	# Do the monsters we actually field carry anything that can interrupt?
	var carriers := 0
	var names: Array = []
	for i in range(10):
		var m = GameData.make_monster(Art.ROSTER[i], 0.35)
		var has := false
		for mv in m.moveset:
			var st = mv.get("status")
			if st != null and SM.HARD_CONTROL.has(str(st.get("kind", ""))):
				has = true
				names.append("%s: %s (%s)" % [m.species_name, mv["name"], st["kind"]])
		if has: carriers += 1
	print("FIELDED MONSTERS CARRYING HARD CONTROL: %d of 10" % carriers)
	for n in names: print("   %s" % n)
	if carriers == 0:
		print("   ⚠️ NONE — the interrupt cannot fire because nothing on the field can apply it.")
	get_tree().quit()
