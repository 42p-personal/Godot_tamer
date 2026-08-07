## THE CROWD — HUMAN spectators on the venue apron (user call 2026-08-06: no monsters watching
## monsters). Six CC0 Quaternius humans, every one carrying a REAL `Sitting` clip — found by
## sweeping Poly Pizza's animated CC0 humans and reading each GLB's clips (the bundle the user
## suggested was static meshes; these are the rigged ones). They SIT, desynced; they CLAP on
## crits; they JUMP + clap on kills. The full sports grammar, purely render-side.
##
## ⚠️ FILL IS A PARAMETER BECAUSE FAME WILL DRIVE IT (standing memory: "stadium seats fill from
## team fame and meta modifiers; NEVER scale the crowd to arena size"). Today it defaults to a
## modest house; when the fame meta lands, the caller passes the real figure. Do not "fix" an
## empty-looking stand by raising the default — wire fame.
extends Node3D

const PACK_DIR := "res://assets/models/spectators/"
const SPECTATOR_SCALE := 0.75  # ⚠️ user-tuned 2026-08-06: 2.6 towered over the stands; spectators are set dressing, not units
const ROW_SEATS := 22          # seats per row at fill = 1.0 (smaller bodies, denser rows)
const CHEER_CLIPS := ["Clapping", "Jump"]
const SIT_CLIPS := ["Sitting"]

var _spectators: Array = []    # {node, player, idle, cheers: Array[String]}
var _rng := RandomNumberGenerator.new()
var _fidget_t := 0.0


func build(ground: Vector2, to_world: Callable, fill: float = 0.5) -> void:
	_rng.seed = 20260806   # fixed: the same crowd every fight, until fame varies it
	var packs: Array = ["man_a.glb", "man_b.glb", "woman_dress.glb", "woman_casual.glb",
		"woman_tank.glb", "woman.glb"]
	if packs.is_empty():
		return
	# ⚠️ ALL FOUR SIDES, three stepped rows, density derived from edge length — every step of
	# the apron holds a seat at fill = 1.0 (user: "I want to see all of the seats filled").
	var seats: Array = []
	var seat_spacing := 6.0
	for row in range(5):
		var off := 4.5 + row * 3.5
		# ⚠️ The Sitting clip drops the hips BELOW the model origin, so without this lift they
		# sink INTO the step. Lift = step height + seated-hip offset, tuned by screenshot.
		var lift := 1.6 + row * 1.4
		var nx := maxi(2, int(ground.x * 0.9 / seat_spacing))
		for i in range(nx):
			var x := ground.x * (0.05 + 0.90 * float(i) / float(nx - 1))
			seats.append({"g": Vector2(x, -off), "lift": lift, "face": 0.0})
			seats.append({"g": Vector2(x, ground.y + off), "lift": lift, "face": PI})
		var ny := maxi(2, int(ground.y * 0.8 / seat_spacing))
		for i in range(ny):
			var y := ground.y * (0.10 + 0.80 * float(i) / float(ny - 1))
			seats.append({"g": Vector2(-off, y), "lift": lift, "face": PI * 0.5})
			seats.append({"g": Vector2(ground.x + off, y), "lift": lift, "face": -PI * 0.5})
	# Fill: fame decides HOW MANY seats hold a body; empty seats stay empty (a half-full house
	# must READ half-full — that is the whole point of fame-driven attendance).
	var occupied := int(round(seats.size() * clampf(fill, 0.0, 1.0)))
	seats.shuffle()   # render-side rng; the sim never sees this
	for k in range(occupied):
		var seat: Dictionary = seats[k]
		var pack: String = packs[_rng.randi_range(0, packs.size() - 1)]
		_spawn(seat, pack, to_world)


func _spawn(seat: Dictionary, pack: String, to_world: Callable) -> void:
	var scene: PackedScene = load(PACK_DIR + pack)
	if scene == null:
		return
	var inst := scene.instantiate()
	var holder := Node3D.new()
	var wpos: Vector3 = to_world.call(seat["g"])
	holder.position = wpos + Vector3(0, float(seat["lift"]), 0)
	holder.rotation.y = float(seat["face"]) + _rng.randf_range(-0.25, 0.25)
	holder.scale = Vector3.ONE * SPECTATOR_SCALE * _rng.randf_range(0.85, 1.15)
	holder.add_child(inst)
	add_child(holder)
	# Colour variance: six models repeat visibly in a full house — a per-instance tint on
	# duplicated materials breaks the clone army. Subtle hue shift, not team colours (the crowd
	# must never read as either side's colour system).
	_tint_meshes(inst, Color.from_hsv(_rng.randf(), _rng.randf_range(0.05, 0.30), _rng.randf_range(0.75, 1.0)))
	var player := _find_player(inst)
	if player == null:
		return
	var idle := ""
	var cheers: Array = []
	for anim_name in player.get_animation_list():
		var short := str(anim_name).get_slice("|", str(anim_name).get_slice_count("|") - 1)
		for sc in SIT_CLIPS:
			if short.ends_with(sc) and idle == "":
				idle = anim_name   # the seat IS the idle
		for c in CHEER_CLIPS:
			if short.ends_with(c):
				cheers.append(anim_name)
	if idle != "":
		var a := player.get_animation(idle)
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR
		player.play(idle)
		# Desync: a crowd breathing in perfect unison reads as an army, not an audience.
		player.seek(_rng.randf() * 2.0, true)
	_spectators.append({"player": player, "idle": idle, "cheers": cheers})


## The fight's beats reach the stands — and ONLY the beats (user direction: sitting is the
## default; cheering happens on camera shakes and deaths, never ambiently).
## ⚠️ PER-MODEL RANDOM DELAY (0–0.7s) before each cheer starts: a crowd that reacts on the same
## frame reads as an animatronic display, one that RIPPLES reads as people. The roll is also
## per model, so who stands differs every event.
func react(intensity: float = 0.4) -> void:
	for sp in _spectators:
		if _rng.randf() > intensity:
			continue
		if bool(sp.get("cheering", false)):
			continue
		var cheers: Array = sp["cheers"]
		if cheers.is_empty() or sp["player"] == null:
			continue
		sp["cheering"] = true
		var clip: String = cheers[_rng.randi_range(0, cheers.size() - 1)]
		var delay := _rng.randf_range(0.0, 0.7)
		get_tree().create_timer(delay).timeout.connect(_start_cheer.bind(sp, clip))


func _start_cheer(sp: Dictionary, clip: String) -> void:
	var p: AnimationPlayer = sp["player"]
	if p == null or not is_instance_valid(p):
		return
	p.play(clip)
	if not p.animation_finished.is_connected(_back_to_idle):
		p.animation_finished.connect(_back_to_idle.bind(sp))


func _back_to_idle(_anim: StringName, sp: Dictionary) -> void:
	sp["cheering"] = false
	if sp["idle"] != "" and sp["player"] != null:
		(sp["player"] as AnimationPlayer).play(sp["idle"])


func _tint_meshes(n: Node, tint: Color) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		for i in range(mi.get_surface_override_material_count()):
			var mat := mi.mesh.surface_get_material(i) if mi.get_surface_override_material(i) == null else mi.get_surface_override_material(i)
			if mat is StandardMaterial3D:
				var dup := (mat as StandardMaterial3D).duplicate()
				dup.albedo_color = dup.albedo_color * tint
				mi.set_surface_override_material(i, dup)
	for c in n.get_children():
		_tint_meshes(c, tint)


func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_player(c)
		if r != null:
			return r
	return null
