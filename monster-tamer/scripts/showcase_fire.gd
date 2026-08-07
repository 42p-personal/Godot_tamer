## FIRE SHOWCASE — a real 5v5, but three monsters per side are armed with the magic showpieces
## (Spark, Void Lance, Inferno, Detonate, Cinderburst) so fireballs and layered explosions are
## GUARANTEED on screen within seconds. Everything else is the normal fight.
extends Node

func _ready() -> void:
	var mv_by := {}
	for mv in GameData.moves:
		mv_by[mv["name"]] = mv
	var mrng := RandomNumberGenerator.new()
	mrng.seed = 20260806
	var a: Array = []
	var b: Array = []
	for i in range(5):
		var ma = GameData.make_monster(Art.ROSTER[i], 0.7, mrng)
		var mb = GameData.make_monster(Art.ROSTER[i + 5], 0.7, mrng)
		ma.happiness = 10
		mb.happiness = 10
		a.append(ma)
		b.append(mb)
	# Three casters per side: single-target fireballs + the AoE ring-explosion + detonators.
	for kit in [[a[0], ["Spark", "Void Lance", "Detonate"]], [a[1], ["Inferno", "Spark"]],
			[a[2], ["Chain Lightning", "Static Chain"]],
			[a[3], ["Hymn of Shields", "Arcane Aegis", "Spark"]], [b[3], ["Body Slam", "Overrun"]], [b[0], ["Doom", "Void Lance", "Spark"]],
			[b[1], ["Life Drain", "Siphon Soul", "Mana Burn"]], [b[2], ["Cinderburst", "Chain Lightning"]]]:
		var m = kit[0]
		var names: Array = kit[1]
		m.moveset = []
		for nm in names:
			if mv_by.has(nm):
				m.moveset.append(mv_by[nm])
		# INT high enough to afford and favour the kit
		m.stats["INT"] = maxf(float(m.stats.get("INT", 0)), 300.0)
		m.stats["WIS"] = maxf(float(m.stats.get("WIS", 0)), 250.0)
	var Tactics = load("res://scripts/tactics.gd")
	Tactics.commit({}, {}, {}, {}, {}, {}, a, b)
	get_tree().change_scene_to_file.call_deferred("res://scenes/arena3d.tscn")
