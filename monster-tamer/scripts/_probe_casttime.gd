extends Node
const D = preload("res://scripts/derive.gd")
func _ready() -> void:
	var f := FileAccess.open("res://data/data.json", FileAccess.READ)
	var moves: Array = JSON.parse_string(f.get_as_text())["moves"]
	var instant := 0; var timed := 0
	var buckets := {}
	for mv in moves:
		var ct: float = D.cast_time_of(mv)
		if ct <= 0.0: instant += 1
		else:
			timed += 1
			var b := "%.1fs" % ct
			buckets[b] = int(buckets.get(b, 0)) + 1
	print("pool: %d moves — INSTANT %d (%.0f%%)  timed %d (%.0f%%)" % [
		moves.size(), instant, 100.0*instant/moves.size(), timed, 100.0*timed/moves.size()])
	print("cast times present: %s" % str(buckets))
	get_tree().quit()
