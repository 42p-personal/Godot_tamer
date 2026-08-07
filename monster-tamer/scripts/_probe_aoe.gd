## Does any AoE hit still land beyond the move's own reach? Scan shots vs positions per frame.
extends Node
const Sp = preload("res://scripts/spatial.gd")
func _ready() -> void:
	var mv_by := {}
	for mv in GameData.moves: mv_by[mv["name"]] = mv
	var over := 0; var total := 0; var worst := 0.0
	var by_tgt := {}
	for seed_i in range(4):
		var Sim = load("res://scripts/spatial_sim.gd")
		var mrng := RandomNumberGenerator.new(); mrng.seed = 700 + seed_i
		var a: Array = []; var b: Array = []
		for i in range(5):
			a.append(GameData.make_monster(Art.ROSTER[i], 0.6, mrng))
			b.append(GameData.make_monster(Art.ROSTER[i + 5], 0.6, mrng))
		var sim = Sim.new(a, b, 700 + seed_i, {}, {}, {}, [])
		var res: Dictionary = await sim.run()
		for f in res.get("frames", []):
			var pos := {}
			for u in f.get("units", []): pos[int(u["id"])] = u["pos"]
			for sh in f.get("shots", []):
				var mv2: Dictionary = mv_by.get(str(sh.get("move","")), {})
				if mv2.is_empty(): continue
				total += 1
				var fid := int(sh.get("fromId",-1)); var tid := int(sh.get("toId",-1))
				if not pos.has(fid) or not pos.has(tid): continue
				var d: float = (pos[fid] as Vector2).distance_to(pos[tid])
				var reach := Sp.reach_of(mv2, false)
				if d > reach + 3.0:
					over += 1; worst = maxf(worst, d - reach)
					by_tgt[str(mv2.get("target","?"))] = int(by_tgt.get(str(mv2.get("target","?")), 0)) + 1
	print("shots checked %d | landed BEYOND the move's reach: %d | worst overshoot %.0f  %s" % [
		total, over, worst, "OK" if over == 0 else "see breakdown"])
	print("  overshoots by move target: ", by_tgt)
	get_tree().quit()
