## Does a dragged chip actually START the fight where it was dropped? Three cases:
## 1. legal placement -> first-frame position equals it
## 2. placement in the ENEMY zone -> clamped back into ours (the sim owns legality)
## 3. per-monster orders reach the sim (the ordersA/orders key bug)
extends Node
const Sp = preload("res://scripts/spatial.gd")
func _ready() -> void:
	var Sim = load("res://scripts/spatial_sim.gd")
	var mrng := RandomNumberGenerator.new(); mrng.seed = 7
	var a: Array = []; var b: Array = []
	for i in range(5):
		a.append(GameData.make_monster(Art.ROSTER[i], 0.35, mrng))
		b.append(GameData.make_monster(Art.ROSTER[i + 5], 0.35, mrng))
	var zone: Rect2 = Sp.deploy_zone(5, "A")
	var legal := zone.position + Vector2(zone.size.x * 0.2, zone.size.y * 0.8)
	var hostile := Vector2(Sp.ground_size(5).x * 0.9, 30.0)  # deep in enemy territory
	var orders := {
		a[0]: {"deployPos": legal, "temperament": "aggressive"},
		a[1]: {"deployPos": hostile},
	}
	var sim = Sim.new(a, b, 99, {}, {}, orders, [])
	add_child(sim)
	# ⚠️ Measure the DEPLOY, not frame 0 — frames are emitted post-tick, so by the first frame a
	# unit has already walked ~2 units toward the enemy and an exact-equality check "fails" on
	# motion that is correct. The first version of this probe did exactly that.
	sim._deploy()
	var p0: Vector2 = sim.spatial_state[a[0]]["pos"]
	var p1: Vector2 = sim.spatial_state[a[1]]["pos"]
	print("legal drop   : wanted %s got %s  %s" % [str(legal.round()), str(p0.round()),
		"OK" if p0.distance_to(legal) < 0.5 else "*** FAIL"])
	var in_zone := zone.grow(0.1).has_point(p1)
	print("hostile drop : wanted %s got %s  in OUR zone: %s  %s" % [str(hostile.round()), str(p1.round()),
		str(in_zone), "OK (clamped)" if in_zone else "*** FAIL — started in enemy zone"])
	var eff: Dictionary = sim.unit_orders.get(a[0], {})
	print("orders reach : temperament=%s  %s" % [str(eff.get("temperament", "MISSING")),
		"OK" if eff.get("temperament", "") == "aggressive" else "*** FAIL"])
	get_tree().quit()
