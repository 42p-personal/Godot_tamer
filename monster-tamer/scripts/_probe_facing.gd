## DOES FACING ACTUALLY FIRE, AND WHO GETS THE BONUS? The design claim is that a backstab is a
## TEAM mechanic — you can only be hit from behind by someone who is not your target — so the
## measurement must show rear hits happening AND show they come from a third party.
extends Node
const Sp = preload("res://scripts/spatial.gd")

func _ready() -> void:
	for layout in ["four_pillar", "central_mass"]:
		var Sim = load("res://scripts/spatial_sim.gd")
		var L = load("res://scripts/arena_layout.gd")
		var a: Array = []; var b: Array = []
		for i in range(5):
			a.append(GameData.make_monster(Art.ROSTER[i], 0.35))
			b.append(GameData.make_monster(Art.ROSTER[i + 5], 0.35))
		var rng := RandomNumberGenerator.new(); rng.seed = 20260805
		var lay: Dictionary = L.generate(5, "Platinum", rng, layout)
		var obs: Array = lay.get("obstacles", [])
		var sim = Sim.new(a, b, 20260805, {}, {}, {}, obs)
		var res: Dictionary = await sim.run()
		var frames: Array = res.get("frames", [])

		var arcs := {"front": 0, "side": 0, "rear": 0}
		var rear_from_third := 0
		var rear_from_target := 0
		for f in frames:
			var us: Array = f.get("units", [])
			for sh in f.get("shots", []):
				var arc := str(sh.get("arc", "front"))
				arcs[arc] = int(arcs.get(arc, 0)) + 1
				if arc != "rear": continue
				# was the victim aiming at its attacker, or at someone else?
				var vic := int(sh.get("toId", -1))
				var atk := int(sh.get("fromId", -1))
				if vic >= 0 and vic < us.size():
					if int(us[vic].get("targetId", -1)) == atk: rear_from_target += 1
					else: rear_from_third += 1
		var tot: float = maxf(1, arcs["front"] + arcs["side"] + arcs["rear"])
		var blocking := 0
		var barea := 0.0
		for o in obs:
			if str(o.get("grade","soft")) == Sp.COVER_BLOCKS_LOS_GRADE:
				blocking += 1
				var r: Rect2 = o["rect"]; barea += r.size.x * r.size.y
		var g: Vector2 = Sp.ground_size(5)
		print("── %s ── %d pieces (%d blocking, %.1f%% of ground) · %d frames" % [
			layout, obs.size(), blocking, 100.0 * barea / (g.x * g.y), frames.size()])
		print("   shots by arc: front %d (%.0f%%)  side %d (%.0f%%)  REAR %d (%.0f%%)" % [
			arcs["front"], 100.0*arcs["front"]/tot, arcs["side"], 100.0*arcs["side"]/tot,
			arcs["rear"], 100.0*arcs["rear"]/tot])
		print("   rear hits by a THIRD party: %d   by the victim's own target: %d" % [
			rear_from_third, rear_from_target])
		print("")
	get_tree().quit()
