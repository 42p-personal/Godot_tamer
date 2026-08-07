extends Node3D
func _ready() -> void:
	var V = load("res://scripts/ui/vfx.gd")
	var v = V.new()
	add_child(v)
	await get_tree().process_frame
	var ok := true
	for nm in ["RAMP_FIRE","RAMP_SMOKE","RAMP_MAGIC","RAMP_HEAL","RAMP_SPARK"]:
		var t: GradientTexture1D = v.get(nm)
		var n: int = t.gradient.get_point_count() if t != null and t.gradient != null else 0
		print("%s: %d stops %s" % [nm, n, "OK" if n >= 3 else "*** FAIL"])
		if n < 3: ok = false
	print("spark trail pool: %d | lights: %d" % [v._spark_trails.size(), v._lights.size()])
	v.explosion_pro(Vector3.ZERO, 1.0)
	print("explosion_pro fired without error  OK")
	get_tree().quit()
