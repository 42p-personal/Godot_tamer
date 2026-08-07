## Every one of the 141 moves through play_ability — the dispatch must never crash, and every
## recipe branch must execute. Counts recipes used so a dead branch is visible.
extends Node3D
func _ready() -> void:
	var VfxScript = load("res://scripts/ui/vfx.gd")
	var vfx = VfxScript.new()
	add_child(vfx)
	await get_tree().process_frame
	var used := {}
	var silent: Array = []
	for mv in GameData.moves:
		var recipe: String = vfx.ABILITY_OVR.get(str(mv["name"]), "")
		if recipe == "" and vfx.LINE_FLAVOUR.has(str(mv.get("line",""))) and str(mv.get("type","")) == "damage":
			recipe = vfx.LINE_FLAVOUR[str(mv["line"])]
		if recipe == "":
			recipe = vfx._rule_recipe(mv)
		used[recipe] = int(used.get(recipe, 0)) + 1
		# ⚠️ EMISSION, NOT JUST DISPATCH. A recipe that matches but plays nothing (missing texture,
		# empty flipbook) would pass a dispatch-only check — count nodes actually emitting.
		# ⚠️ "Emits" now spans TWO tiers: particle emitters firing, OR shader-effect nodes
		# (lightning/siphon/static-ring — MeshInstance3D holders) spawned by the call. The probe
		# flagged 10 moves silent the moment their recipes upgraded to shaders — the instrument's
		# definition had gone stale, not the effects.
		var before: int = vfx.get_child_count()
		vfx.play_ability(mv, Vector3(0, 0, 0), Vector3(10, 0, 10), false)
		var emitting := 0
		for c in vfx.get_children():
			if c is GPUParticles3D and (c as GPUParticles3D).emitting:
				emitting += 1
		if emitting == 0 and vfx.get_child_count() <= before:
			silent.append("%s (%s)" % [mv["name"], recipe])
		for c in vfx.get_children():
			if c is GPUParticles3D:
				(c as GPUParticles3D).emitting = false
		vfx.play_ability(mv, Vector3(0, 0, 0), Vector3(10, 0, 10), true)
		for c in vfx.get_children():
			if c is GPUParticles3D:
				(c as GPUParticles3D).emitting = false
	print("all %d moves dispatched twice (normal + crit) without error" % GameData.moves.size())
	if silent.is_empty():
		print("EVERY move EMITS at least one effect  OK")
	else:
		print("*** SILENT moves (%d): %s" % [silent.size(), ", ".join(PackedStringArray(silent))])
	var ks: Array = used.keys(); ks.sort()
	for k in ks:
		print("  %-16s %d moves" % [k, used[k]])
	# flipbook inventory sanity
	print("flipbooks loaded: %d of %d" % [vfx._flip_tex.size(), vfx.FLIPBOOKS.size()])
	get_tree().quit()
