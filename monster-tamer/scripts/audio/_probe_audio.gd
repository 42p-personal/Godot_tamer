## AUDIO PROBE — headless acceptance test for the procedural audio layer. Exit code is the result.
##
## Two halves, because the layer has two independent ways to be wrong:
##   1. THE SYNTH. Every cue must render to a non-empty, audible, non-clipped, DC-free buffer.
##      A silent cue and a clipped cue both "work" at runtime and both sound broken.
##   2. THE MIXER. Caps, cooldowns, priority stealing, ducking and the cast cut must actually
##      refuse work. A mixer that never says no is not a mixer, and in a 5v5 that is the whole
##      difference between a soundscape and static.
##
## ⚠️ Headless runs on the dummy audio driver: nothing is audible and `player.playing` is not a
## reliable liveness signal. That is precisely why `battle_audio` tracks its own `until` per voice
## — so the limits under test here are the same limits that run with a real device.
##
## ⚠️ §4 IS THE ONE THAT CAN CATCH THIS PROJECT'S SIGNATURE BUG. §1–3 test the layer against
## ITSELF — synthetic events, hand-written by the same author as the cues, which is exactly the
## shared-assumption trap. §4 runs REAL seeded 5v5 fights and streams the sim's own event array
## through `on_event()` at the real tick rate, so the census, the density and the refusal rate are
## measurements of the game rather than of the probe.
extends SceneTree

const BattleAudio = preload("res://scripts/audio/battle_audio.gd")
const Synth = preload("res://scripts/audio/synth.gd")
const Cues = preload("res://scripts/audio/cues.gd")
const Sim = preload("res://scripts/sim/sim.gd")
const Kit = preload("res://scripts/sim/kit.gd")
const Sp = preload("res://scripts/spatial.gd")

var _fails := 0
var _worst := {}     # composition of the densest one-second window seen in §4
var _worst_n := 0
var _shape: Array = []   # per-decile cue counts of the sample fight — the fight's shape in sound
var _dmg_of := {}        # damage-carrying kind -> every damage number it delivered
var _cut_total := 0      # interrupts + hard-control breaks seen on the real path
var _cut_with_rise := 0  # ...of which the victim had an audible rise for the clang to sever
var _break_cause := {}   # status_break `cause` tag -> count, on the real path


func _check(name: String, ok: bool) -> void:
	if ok:
		print("  ok  ", name)
	else:
		_fails += 1
		print("  FAIL ", name)


func _initialize() -> void:
	print("── AUDIO PROBE ──")
	_test_synth()
	_test_bank()
	_test_mixer()
	await _test_real_path()
	print("── audio probe: %d failure(s) ──" % _fails)
	quit(1 if _fails > 0 else 0)


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# 1. THE SYNTH
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _test_synth() -> void:
	print(" synth")
	var st: AudioStreamWAV = Synth.render([
		{"wave": "sine", "f0": 440, "dur": 0.25, "amp": 1.0, "atk": 0.01, "dec": 0.05,
			"sus": 0.7, "rel": 0.08}])
	_check("render returns a stream", st != null)
	if st == null:
		return
	_check("16-bit mono at the declared rate",
		st.format == AudioStreamWAV.FORMAT_16_BITS and not st.stereo and st.mix_rate == Synth.RATE)
	_check("sample count matches duration", absf(st.get_length() - 0.25) < 0.01)
	_check("empty layer list renders nothing (guard, not crash)", Synth.render([]) == null)

	# Determinism of the synth itself: same params, same bytes. Not a sim constraint — a cue that
	# rendered differently per boot would make every A/B of the cue sheet meaningless.
	var a: AudioStreamWAV = Synth.render([{"wave": "noise", "dur": 0.2, "seed": 7, "amp": 1.0}])
	var b: AudioStreamWAV = Synth.render([{"wave": "noise", "dur": 0.2, "seed": 7, "amp": 1.0}])
	var c: AudioStreamWAV = Synth.render([{"wave": "noise", "dur": 0.2, "seed": 8, "amp": 1.0}])
	_check("same params render byte-identical", a.data == b.data)
	_check("different seed actually diverges (probe not vacuous)", a.data != c.data)

	# Normalisation is what makes "no clipping" a property of the synth rather than of the author.
	var hot: AudioStreamWAV = Synth.render([
		{"wave": "square", "f0": 200, "dur": 0.2, "amp": 40.0, "drive": 12.0},
		{"wave": "saw", "f0": 201, "dur": 0.2, "amp": 40.0},
		{"wave": "noise", "dur": 0.2, "amp": 40.0}])
	_check("a wildly over-driven cue still normalises under the ceiling",
		_peak(hot) <= 0.86 and _peak(hot) > 0.8)

	# The endpoint fades: a cue that starts on a DC step clicks.
	var first := absf(float(st.data.decode_s16(0)) / 32768.0)
	var last := absf(float(st.data.decode_s16(st.data.size() - 2)) / 32768.0)
	_check("cue starts and ends near zero (no click)", first < 0.02 and last < 0.02)


## Mark every voice busy at a given priority — the only way to reach a full pool, since the
## per-cue caps deliberately prevent legitimate play from ever getting there.
func _occupy(a, prio: int, seconds: float) -> void:
	for v in a._voices:
		v["cue"] = "occupied"
		v["prio"] = prio
		v["until"] = a._clock + seconds


func _peak(st: AudioStreamWAV) -> float:
	var p := 0.0
	for i in range(st.data.size() / 2):
		p = maxf(p, absf(float(st.data.decode_s16(i * 2)) / 32768.0))
	return p


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# 2. THE CUE BANK
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _test_bank() -> void:
	print(" cue bank")
	var rep: Dictionary = BattleAudio.analyse_bank()
	var ids: Array = rep.keys()
	ids.sort()
	_check("every cue in the sheet rendered", ids.size() == Cues.sheet().size())

	var bad_empty: Array = []
	var bad_quiet: Array = []
	var bad_clip: Array = []
	var bad_dc: Array = []
	for id in ids:
		var r: Dictionary = rep[id]
		if not bool(r.get("ok", false)) or int(r.get("samples", 0)) < 64:
			bad_empty.append(id)
			continue
		if float(r["rms"]) < 0.01:
			bad_quiet.append("%s(rms %.4f)" % [str(id), float(r["rms"])])
		if float(r["peak"]) > 0.95:
			bad_clip.append("%s(peak %.3f)" % [str(id), float(r["peak"])])
		if float(r["dc"]) > 0.06:
			bad_dc.append("%s(dc %.3f)" % [str(id), float(r["dc"])])
	_check("no empty buffers %s" % str(bad_empty), bad_empty.is_empty())
	_check("no silent cues %s" % str(bad_quiet), bad_quiet.is_empty())
	_check("no clipped cues %s" % str(bad_clip), bad_clip.is_empty())
	_check("no DC-offset cues %s" % str(bad_dc), bad_dc.is_empty())

	# The three contrasts the cue sheet exists to carry, asserted as measurements rather than
	# as intentions: a crit must be BIGGER than a body hit, a death LONGER than everything, and
	# the attrition tick must stay small enough to sit under a real hit.
	_check("crit is longer-bodied than a plain hit",
		float(rep["hit_crit"]["seconds"]) > float(rep["hit_body"]["seconds"]))
	_check("a hit is bigger than a chip",
		float(rep["hit_body"]["seconds"]) > float(rep["hit_light"]["seconds"]))
	# The impact ladder must be monotonic in body: chip < hit < heavy, and heavy must still sit
	# UNDER the death, which owns the bottom of the register alone.
	_check("a heavy landing is bigger-bodied than a plain hit",
		float(rep["hit_heavy"]["seconds"]) > float(rep["hit_body"]["seconds"]))
	_check("a heavy landing still sits under the death",
		float(rep["hit_heavy"]["seconds"]) < float(rep["death"]["seconds"]))
	_check("death is the longest impact in the sheet",
		float(rep["death"]["seconds"]) >= float(rep["aoe"]["seconds"]))
	_check("the cast rise is long enough to be an unfinished gesture",
		float(rep["cast_rise"]["seconds"]) > 1.0)
	_check("the crowd bed loops (nothing else does)",
		bool(rep["crowd_bed"]["looped"]) and not bool(rep["death"]["looped"]))

	# Mix sanity: the tick and the miss must be the quietest things in the sheet, and the
	# interrupt among the loudest. This is the ranking the whole discipline depends on.
	var db_tick := float(BattleAudio.MIX["tick"]["db"])
	var db_miss := float(BattleAudio.MIX["miss"]["db"])
	var db_int := float(BattleAudio.MIX["interrupt"]["db"])
	_check("interrupt outranks tick and miss by >12 dB",
		db_int - maxf(db_tick, db_miss) > 12.0)
	var missing: Array = []
	for id in ids:
		if not BattleAudio.MIX.has(str(id)) and str(id) != "crowd_bed":
			missing.append(id)
	_check("every playable cue has a mix entry %s" % str(missing), missing.is_empty())


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# 3. THE MIXER
# ═══════════════════════════════════════════════════════════════════════════════════════════════

func _test_mixer() -> void:
	print(" mixer")
	var a = BattleAudio.new()
	root.add_child(a)
	a.ensure_built()   # `_ready` does not fire for a node parented during SceneTree._initialize
	_check("layer came up", bool(a._ok))
	if not a._ok:
		return

	# Cooldown: two identical cues back to back — the second is refused.
	a.reset()
	var v1: int = a._play("hit_body", Vector3.ZERO, "a0")
	var v2: int = a._play("hit_body", Vector3.ZERO, "a1")
	_check("first hit takes a voice", v1 >= 0)
	_check("an immediate repeat is refused by the cooldown", v2 < 0)

	# CAP. Still tested on `cast_rise` — it is by far the longest non-loop cue (1.4s), so the cap
	# is what binds rather than the cue simply finishing.
	# ⚠️ THE CLOCK MUST BE ADVANCED PAST THE COOLDOWN BETWEEN PLAYS. `cast_rise` gained a 0.18s
	# cooldown when the density audit found five simultaneous rises in one second; without stepping
	# the clock this loop would measure the COOLDOWN refusing plays and pass at "1", which is the
	# cap test quietly becoming vacuous.
	a.reset()
	var taken := 0
	for i in range(8):
		a._clock += 0.2
		if a._play("cast_rise", Vector3.ZERO, "u%d" % i) >= 0:
			taken += 1
	_check("simultaneous cast rises cap at %d (got %d)" % [int(BattleAudio.MIX["cast_rise"]["cap"]), taken],
		taken == int(BattleAudio.MIX["cast_rise"]["cap"]))

	# PRIORITY. The pool cannot be filled by playing cues — the caps stop that long before 20
	# voices are in flight, which is the design working. So occupy it directly and assert the two
	# directions of the stealing rule.
	a.reset()
	_occupy(a, 1, 5.0)      # every voice busy for 5s at priority 1
	_check("a priority-0 cue is refused when the pool is full of higher-priority ones",
		a._play("tick", Vector3.ZERO, "t") < 0)
	_check("a priority-3 cue steals from a full pool of lower ones",
		a._play("death", Vector3.ZERO, "victim") >= 0)
	a.reset()
	_occupy(a, 3, 5.0)      # every voice busy for 5s at priority 3
	_check("nothing steals from its own band — even a death is refused",
		a._play("death", Vector3.ZERO, "victim") < 0)

	# Ducking: the same low-priority cue is quieter right after a big beat than in silence.
	a.reset()
	var i_quiet: int = a._play("tick", Vector3.ZERO, "q")
	var db_quiet: float = (a._voices[i_quiet]["p"] as AudioStreamPlayer3D).volume_db
	a.reset()
	a._loud = 1.0
	var i_loud: int = a._play("tick", Vector3.ZERO, "q")
	var db_loud: float = (a._voices[i_loud]["p"] as AudioStreamPlayer3D).volume_db
	_check("priority-0 cues duck under a loud beat (%.1f → %.1f dB)" % [db_quiet, db_loud],
		db_loud < db_quiet - 10.0)

	# THE CUT. A cast rise is severed by the interrupt, and the handle is invalidated so a second
	# interrupt cannot silence whatever cue later reused that slot.
	a.reset()
	a.on_event({"kind": "cast_start", "from": "b0", "to": "a0", "move": "Pyroblast"},
		Vector3.ZERO, Vector3.ZERO)
	_check("a cast start holds a live rise voice", a._casting.has("b0"))
	var ci: int = int((a._casting["b0"] as Dictionary)["i"])
	a._clock += 0.4
	a.on_event({"kind": "interrupt", "from": "a1", "to": "b0", "locked": true},
		Vector3.ZERO, Vector3.ZERO)
	# ⚠️ Do NOT assert the slot is idle: the cut frees it and the clang, allocated on the very
	# next line of `on_event`, is entitled to take the freed slot straight back. What must be
	# true is that the RISE is gone — the handle dropped and the slot no longer holds cast_rise.
	_check("the interrupt cuts the rise", not a._casting.has("b0")
		and str((a._voices[ci] as Dictionary)["cue"]) != "cast_rise")
	_check("the interrupt itself got a voice", float(a._last_played.get("interrupt", -999.0)) > -900.0)
	_check("the interrupt raised the duck meter", a._loud > 0.5)

	# A cast that RESOLVES also cuts the rise — the gesture must not overlap its own answer.
	a.reset()
	a.on_event({"kind": "cast_start", "from": "b1", "to": "a0"}, Vector3.ZERO, Vector3.ZERO)
	a._clock += 0.5
	a.on_event({"kind": "cast_done", "from": "b1", "to": "a0", "dmg": 40, "move": "Pyroblast"},
		Vector3.ZERO, Vector3.ZERO)
	_check("a resolved cast releases its rise", not a._casting.has("b1"))
	_check("cast_done sounded", float(a._last_played.get("cast_done", -999.0)) > -900.0)

	# A projectile move never emits cast_done — the launch is what ends the rise.
	a.reset()
	a.on_event({"kind": "cast_start", "from": "b2", "to": "a0"}, Vector3.ZERO, Vector3.ZERO)
	a._clock += 0.6
	a.on_event({"kind": "proj_launch", "from": "b2", "to": "a0"}, Vector3.ZERO, Vector3.ZERO)
	_check("a projectile launch releases its rise", not a._casting.has("b2"))

	# Per-unit pitch: five monsters must not be one monster.
	# ⚠️ "DISTINCT" MUST MEAN AUDIBLY DISTINCT. The original check asserted only that the five
	# floats were unequal, and passed for two years on a hash that spread `a0`…`a4` across 0.0006
	# — a thousandth of a semitone. A pitch test that a constant would pass is not a test.
	# 0.01 is ~17 cents, about the floor of what a listener resolves on a short percussive hit.
	var pitches: Array = []
	for uid in ["a0", "a1", "a2", "a3", "a4"]:
		pitches.append(a._unit_pitch(uid))
	pitches.sort()
	var min_gap := 9.0
	for i in range(1, pitches.size()):
		min_gap = minf(min_gap, float(pitches[i]) - float(pitches[i - 1]))
	_check("five units get five AUDIBLY distinct voices (min gap %.4f)" % min_gap, min_gap >= 0.01)
	_check("per-unit pitch is stable across calls", a._unit_pitch("a3") == a._unit_pitch("a3"))

	# ── THE SIDE IS AUDIBLE. The check that makes the off-screen answer real rather than intended.
	# Both bands must be natural (nothing chipmunked or subsonic), and the GAP BETWEEN THEM must be
	# wider than the spread within either — otherwise "whose was that" would be a coin toss decided
	# by which unit happened to act, which is worse than no signal at all.
	var lo_a := 9.0
	var hi_a := 0.0
	var lo_b := 9.0
	var hi_b := 0.0
	for i in 5:
		var pa: float = a._unit_pitch("a%d" % i)
		var pb: float = a._unit_pitch("b%d" % i)
		lo_a = minf(lo_a, pa)
		hi_a = maxf(hi_a, pa)
		lo_b = minf(lo_b, pb)
		hi_b = maxf(hi_b, pb)
	_check("the two team bands never overlap (A %.3f-%.3f, B %.3f-%.3f)" % [lo_a, hi_a, lo_b, hi_b],
		hi_a < lo_b)
	_check("the gap between sides is wider than the spread inside a side",
		(lo_b - hi_a) > maxf(hi_a - lo_a, hi_b - lo_b))
	_check("both bands stay inside a natural voice range",
		lo_a > 0.8 and hi_b < 1.25)
	_check("an id belonging to neither side lands in the neutral middle",
		a._unit_pitch("crowd") > hi_a and a._unit_pitch("crowd") < lo_b)

	# Every event kind the watch scene presents must route without error — including the ones
	# that are deliberately silent. This is the "authored but unreachable" tripwire for audio.
	a.reset()
	# ⚠️ This list is EVERY kind the watch scene's own vocabulary line has printed, not just the
	# 17 it draws. Two of them — `debuff` and `proj_hit` — were silent on the first pass and only
	# the vocabulary line caught it. Keep them in sync: an event kind with no cue is this
	# project's "authored but unreachable" failure wearing an audio costume.
	var kinds := ["strike", "proj_hit", "cast_start", "cast_done", "interrupt", "death", "heal",
		"ward_soak", "thorns", "status_applied", "status_break", "cleanse", "taunted", "buff",
		"debuff", "status_tick", "aoe", "proj_launch", "miss", "cast_miss", "proj_fizzle",
		"fizzle", "status_expire"]
	var silent_by_design := ["status_expire"]
	var mute: Array = []
	for k in kinds:
		a.reset()
		a._clock += 0.5
		a.on_event({"kind": k, "from": "a0", "to": "b0", "id": "b0", "dmg": 30, "amount": 25,
			"targets": 3, "status": "poison", "move": "Bolt", "crit": false,
			"centre": Vector2.ZERO, "radius": 6.0}, Vector3.ZERO, Vector3(1, 0, 1))
		if a._last_played.is_empty():
			mute.append(k)
	_check("every routed kind produces a cue except the one that must not %s" % str(mute),
		mute == silent_by_design)

	a.crowd_swell(0.9)
	_check("a big crowd beat swells the bed", a._bed_target > -20.0)
	a.reset()
	_check("reset silences the bed and the pool", a._bed_target <= -30.0 and a._casting.is_empty())

	a.queue_free()


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# 4. THE REAL PATH — seeded 5v5 fights, streamed through the mixer at the real tick rate.
#
# ⚠️ WHY THIS SECTION EXISTS. §1–3 were written by the same hand as `cues.gd`, against events that
# hand invented. That is precisely the shared-assumption trap this project has fallen into ten
# times: a system authored, priced, documented — and never reached. Everything below reads the
# SIM's own event array, so a kind the fight never emits shows as zero, and a cue the mix eats
# shows as a refusal, whatever the cue sheet's comments claim.
#
# The stream is fed tick by tick with `_clock` advanced by `Sim.DT`, so cooldowns and caps see
# exactly the timing they see at 1x playback. Nothing here touches `sim.rng`.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

const TEAM := 5
## Deliberately awkward for the mix: two AoE casters, two healers, a kicker, a taunter, a thorns
## body and a warded tank. A plain brawl emits `strike`/`miss` and almost nothing else, and would
## flatter the layer by never testing it.
const KIT_AOE := ["Whirlwind", "Earthshaker"]
const KIT_AOE_R := ["Rain of Arrows"]
const KIT_HEAL := ["Mend", "Clarity"]
const KIT_WARD := ["Bastion", "Fortify"]
const KIT_THORN := ["Barbed Carapace", "Riposte"]
const KIT_DEBUFF := ["Sunder", "Enfeeble"]
const KIT_TAUNT := ["Taunt", "Challenge"]
const KIT_STATUS := ["Headbutt", "Toxin Stack"]
const KIT_MAGIC := ["Ember", "Cinderburst"]

## The ceiling this whole mix discipline exists to hold. A listener resolves a handful of discrete
## transients per second; past that the ear integrates them into texture and the information is
## gone. Measured per SECOND OF FIGHT at 1x.
const PEAK_CUES_PER_SEC := 12
## The same ceiling at 4x fast-forward, where the ungated priority-3 band compresses four
## fight-seconds of fight-deciding beats into one listening second. See the check for why it is
## deliberately looser rather than a gate on deaths.
const PEAK_4X_CUES_PER_SEC := 15
## And the floor. A fight that is mostly silent is not carrying its own shape, only its climaxes.
const MIN_MEAN_CUES_PER_SEC := 0.8


func _moves() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/data.json"))["moves"]


func _u(id: String, team: String, pos: Vector2, stats: Dictionary, speed: float,
		tactics: Dictionary, kit: Array) -> Dictionary:
	return {"id": id, "team": team, "pos": pos, "stats": stats, "speed": speed,
		"tactics": tactics, "kit": kit}


## A roster built to emit the WIDEST event vocabulary the sim has, not the most typical one.
func _roster(moves: Array) -> Array:
	var bruiser := {"STR": 60, "CON": 45, "INT": 10, "WIS": 15}
	var tank := {"STR": 45, "CON": 70, "INT": 10, "WIS": 25}
	var caster := {"STR": 15, "CON": 35, "INT": 75, "WIS": 55}
	var healer := {"STR": 10, "CON": 60, "INT": 20, "WIS": 80}
	var pa: Array = Sp.deploy_positions(TEAM, "A")
	var pb: Array = Sp.deploy_positions(TEAM, "B")
	var spd := Sp.slow_unit_speed(TEAM)
	var push := {"target_priority": "nearest", "positional": "push"}
	var hold := {"target_priority": "weakest", "positional": "hold"}
	var out: Array = []
	out.append(_u("a0", "A", pa[0], caster, spd, hold, Kit.build(KIT_AOE, moves)))
	out.append(_u("a1", "A", pa[1], healer, spd,
		{"target_priority": "nearest", "positional": "guard", "guard_ally": "a2"},
		Kit.build(KIT_HEAL, moves)))
	out.append(_u("a2", "A", pa[2], tank, spd, push, Kit.build(KIT_WARD, moves)))
	out.append(_u("a3", "A", pa[3], bruiser, spd * 1.15,
		{"target_priority": "casters", "positional": "push"}, [Kit.kick()]))
	out.append(_u("a4", "A", pa[4], bruiser, spd, push, Kit.build(KIT_STATUS, moves)))
	out.append(_u("b0", "B", pb[0], caster, spd, hold, Kit.build(KIT_MAGIC, moves)))
	out.append(_u("b1", "B", pb[1], healer, spd,
		{"target_priority": "nearest", "positional": "guard", "guard_ally": "b2"},
		Kit.build(KIT_HEAL, moves)))
	out.append(_u("b2", "B", pb[2], tank, spd, push, Kit.build(KIT_THORN, moves)))
	out.append(_u("b3", "B", pb[3], bruiser, spd, push, Kit.build(KIT_TAUNT, moves)))
	out.append(_u("b4", "B", pb[4], caster, spd, push, Kit.build(KIT_AOE_R + KIT_DEBUFF, moves)))
	return out


func _run_fight(seed_val: int, moves: Array) -> Dictionary:
	var g := Sp.ground_size(TEAM)
	var sim = Sim.new()
	sim.setup(seed_val, _roster(moves), g,
		[{"rect": Rect2(g.x * 0.5 - 16.0, g.y * 0.5 - 16.0, 32.0, 32.0)}])
	var ok: bool = await sim.nav.until_ready(self, Vector2(20, g.y * 0.5),
		Vector2(g.x - 20, g.y * 0.5))
	if not ok:
		sim.nav.free_rids()
		return {}
	var res: Dictionary = sim.run()
	sim.nav.free_rids()   # every discarded sim leaks ~18 NavigationServer RIDs without this
	return res


## Stream one fight's events through the mixer; return the per-second cue histogram.
## Positions are resolved off the FRAME — the same rule the renderer follows. Nothing is recomputed.
func _stream(a, res: Dictionary) -> Array:
	return _stream_at(a, res, Sim.DT)


## The same, at an arbitrary clock step — `Sim.DT` is 1x playback, `Sim.DT / 4` is the 4x button.
func _stream_at(a, res: Dictionary, step: float) -> Array:
	var per_sec: Array = []
	var bucket := int(a._clock)
	var mark := _total(a.stat_played)
	var snap: Dictionary = a.stat_played.duplicate()
	for f in (res.get("frames", []) as Array):
		var fr: Dictionary = f
		var pos := {}
		for u in (fr.get("units", []) as Array):
			var ud: Dictionary = u
			var p := Vector2(ud.get("pos", Vector2.ZERO))
			pos[str(ud.get("id", ""))] = Vector3(p.x, 1.0, p.y)
		for e in (fr.get("events", []) as Array):
			var ev: Dictionary = e
			var from_p: Vector3 = pos.get(str(ev.get("from", "")), Vector3.ZERO)
			var at_p: Vector3 = pos.get(str(ev.get("to", ev.get("id", ""))), from_p)
			if str(ev.get("kind", "")) == "aoe":
				var c := Vector2(ev.get("centre", Vector2.ZERO))
				at_p = Vector3(c.x, 1.0, c.y)
			var ek := str(ev.get("kind", ""))
			if ek == "cast_done" or ek == "proj_hit" or ek == "strike":
				var dm := int(ev.get("dmg", 0))
				_dmg_of[ek] = (_dmg_of.get(ek, []) as Array) + [dm]
			# ⚠️ THE INTERRUPT ONLY WORKS AS THE ABSENCE OF A RESOLUTION THE EAR EXPECTED. If the
			# density gate refused the victim's rise, the clang lands on silence and the whole
			# point of the second contrast is gone. Counted here, before the event is consumed.
			# ⚠️ ONLY `cause: control` DESTROYS A CAST. The other two tags on `status_break`
			# (`damage` = sleep woke on a hit, `consumed` = a detonator spent its fuel) touch no
			# cast at all, and counting them here is what exposed the mix routing all three to the
			# shatter. An untagged break would be routed as a shatter by default, so it is counted
			# and reported rather than silently assumed benign.
			if ek == "status_break":
				var cause := str(ev.get("cause", ""))
				_break_cause[cause] = int(_break_cause.get(cause, 0)) + 1
			if ek == "interrupt" or (ek == "status_break" and str(ev.get("cause", "")) == "control"):
				_cut_total += 1
				if a._casting.has(str(ev.get("to", ""))):
					_cut_with_rise += 1
			a.on_event(ev, from_p, at_p)
		a._clock += step
		if int(a._clock) > bucket:
			var n := _total(a.stat_played) - mark
			per_sec.append(n)
			# Keep the composition of the WORST second seen anywhere. A density number on its own
			# says "too loud"; the composition says WHICH cues to squeeze, which is the only form
			# of the finding you can act on without guessing.
			if n > _worst_n:
				_worst_n = n
				_worst = {}
				for k in a.stat_played:
					var d := int(a.stat_played[k]) - int(snap.get(k, 0))
					if d > 0:
						_worst[k] = d
			mark = _total(a.stat_played)
			snap = a.stat_played.duplicate()
			bucket = int(a._clock)
	return per_sec


func _total(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n


func _test_real_path() -> void:
	print(" real path (seeded 5v5, sim stream → mixer)")
	var moves := _moves()
	var a = BattleAudio.new()
	root.add_child(a)
	a.ensure_built()
	if not a._ok:
		_check("audio layer came up for the real-path run", false)
		return

	var census := {}
	var hist: Array = []
	var keep := {}
	a.audit_reset()
	for seed_val in [1, 7, 13]:
		a.reset()
		var res: Dictionary = await _run_fight(seed_val, moves)
		if res.is_empty():
			_check("fight seed %d built a navmesh" % seed_val, false)
			continue
		var h: Array = _stream(a, res)
		hist.append_array(h)
		if seed_val == 1:
			keep = res
			print("   sample fight: winner %s, %.1fs" % [str(res.get("winner", "?")),
				float(int(res.get("ticks", 0))) * Sim.DT])
			_shape = _deciles(h)
			print("   shape (cues/s per tenth of the fight): ", str(_shape))
	for k in a.stat_events:
		census[k] = int(a.stat_events[k])

	# ── THE CENSUS. Every kind the sim can emit, and whether this fight produced any. ──────────
	var sim_kinds := ["strike", "proj_hit", "miss", "cast_miss", "proj_fizzle", "cast_start",
		"cast_done", "proj_launch", "fizzle", "interrupt", "status_break", "death", "aoe",
		"taunted", "heal", "cleanse", "buff", "debuff", "status_applied", "status_expire",
		"status_tick", "ward_soak", "thorns"]
	var never: Array = []
	for k in sim_kinds:
		if int(census.get(k, 0)) == 0:
			never.append(k)
	print("   census:  ", _sorted_line(census))
	print("   absent:  ", str(never))
	print("   played:  ", _sorted_line(a.stat_played))
	print("   refused: ", _sorted_line(a.stat_refused))
	print("   cast rises cut: %d" % a.stat_cut)

	# ── DENSITY. ───────────────────────────────────────────────────────────────────────────────
	var peak := 0
	var sum := 0
	for n in hist:
		peak = maxi(peak, int(n))
		sum += int(n)
	var mean := float(sum) / maxf(1.0, float(hist.size()))
	print("   cues/sec: mean %.2f, peak %d, over %d fight-seconds" % [mean, peak, hist.size()])
	print("   densest second: %d cues — %s" % [_worst_n, _sorted_line(_worst)])
	var quiet := 0
	for n in hist:
		if int(n) == 0:
			quiet += 1
	print("   silent seconds: %d of %d (%.0f%%)" % [quiet, hist.size(),
		100.0 * float(quiet) / maxf(1.0, float(hist.size()))])
	for k in ["strike", "cast_done", "proj_hit"]:
		var arr: Array = _dmg_of.get(k, [])
		if not arr.is_empty():
			arr.sort()
			print("   %s dmg: n=%d min=%d p50=%d p90=%d max=%d" % [k, arr.size(), int(arr[0]),
				int(arr[arr.size() / 2]), int(arr[int(arr.size() * 0.9)]), int(arr[-1])])
	_check("peak cue density stays at or under %d/s (got %d)" % [PEAK_CUES_PER_SEC, peak],
		peak <= PEAK_CUES_PER_SEC)
	_check("the fight is not mostly silent (mean %.2f cues/s)" % mean,
		mean >= MIN_MEAN_CUES_PER_SEC)

	# ── CONTRAST 2, ON REAL DATA. `cues.gd` builds the interrupt as "the ABSENCE of the resolution
	# the ear was already expecting". That only holds if the victim's rise was actually playing —
	# so this is the check that stops the density gate quietly demolishing the sheet's own design.
	print("   status_break causes: ", _sorted_line(_break_cause))
	print("   cast-destroying cuts with a live rise: %d of %d" % [_cut_with_rise, _cut_total])
	_check("every cast cut short had an audible rise to sever (%d/%d)" % [_cut_with_rise, _cut_total],
		_cut_total == 0 or _cut_with_rise == _cut_total)
	# An untagged `status_break` is routed to the shatter by default, which is the loud, wrong
	# answer for two of its three meanings. If the sim ever stops tagging, fail here rather than
	# discover it by ear six months later.
	_check("every status_break carries a cause tag", not _break_cause.has(""))

	# ── 4x FAST-FORWARD IS THE GATE'S HARDEST CASE, AND IT IS THE ONE PLAYERS USE. `_clock`
	# advances on WALL time (`_process` delta), not on fight time, so at 4x four fight-seconds of
	# events arrive in one listening second. That is the correct frame of reference — the ear works
	# in wall time — but it means the gate has to absorb 4x the arrivals, and if it could not, the
	# speed button would turn the fight into the static this whole discipline exists to prevent.
	# Re-streamed here at a quarter of the clock step, and judged per WALL second.
	if not keep.is_empty():
		a.reset()
		var save := _worst.duplicate()   # the 1x finding must not be overwritten by the 4x pass
		var save_n := _worst_n
		var fast := _stream_at(a, keep, Sim.DT / 4.0)
		_worst = save
		_worst_n = save_n
		var fpeak := 0
		for n in fast:
			fpeak = maxi(fpeak, int(n))
		print("   at 4x: peak %d cues per WALL second" % fpeak)
		# ⚠️ THE 4x BAR IS HIGHER THAN THE 1x BAR AND THAT IS A DESIGN CONSEQUENCE, NOT SLACK.
		# The meter already measures WALL seconds, so the gate needs no speed correction — it
		# tightens automatically. What leaks is the priority-3 band, which is ungated on purpose:
		# four fight-seconds of deaths, crits, interrupts, AoE bursts and resolutions genuinely do
		# arrive inside one listening second at 4x. Gating them would mean a player who pressed
		# fast-forward stops hearing the fight-deciding beats, which is the exact information loss
		# the whole layer exists to prevent. So the skeleton is allowed to be dense; the flesh is
		# not. Naive (ungated) 4x would be ~84/s — the gate is doing the work.
		_check("the density gate still holds at 4x fast-forward (peak %d/s)" % fpeak,
			fpeak <= PEAK_4X_CUES_PER_SEC)

	# ── ALL FOUR IMPACT GRADES MUST BE REACHABLE ON A REAL FIGHT. A grade nothing ever reaches is
	# this project's signature failure in audio costume: authored, mixed, documented, inaudible.
	var unreached: Array = []
	for g in ["hit_light", "hit_body", "hit_heavy", "hit_crit"]:
		if int(a.stat_played.get(g, 0)) == 0:
			unreached.append(g)
	_check("every impact grade is reached by a real fight %s" % str(unreached), unreached.is_empty())

	# ── AND THE GRADER MUST BE SCALE-FREE. This is the whole reason it is a ratio and not a
	# constant: the same fight shape at Wood-league numbers and at Apex numbers must produce the
	# same GRADES, or the mix silently becomes all-heavy at the top of the ladder.
	var grades_small := _grade_run(a, [12, 11, 13, 10, 12, 44, 9, 5])
	var grades_big := _grade_run(a, [120, 110, 130, 100, 120, 440, 90, 50])
	_check("the impact grader is scale-free (%s vs %s)" % [str(grades_small), str(grades_big)],
		grades_small == grades_big)
	# ⚠️ THE OPENING OF A FIGHT MUST NOT BE ALL HAYMAKERS. The first draft of the grader tracked a
	# running MAXIMUM, so every early hit was the largest so far and graded heavy — five opening
	# haymakers followed by a calm fight, which is precisely backwards.
	_check("the first blow of a fight grades neutral, not heavy",
		_grade_run(a, [12])[0] == "hit_body")
	_check("a typical run of similar blows stays neutral",
		grades_small.slice(0, 5) == ["hit_body", "hit_body", "hit_body", "hit_body", "hit_body"])
	_check("an outlier three times the norm reads as heavy", grades_small[5] == "hit_heavy")
	_check("a chip well under the norm reads as light", grades_small[7] == "hit_light")

	# ── THE TRIPWIRE. Any kind the REAL fight emits must reach a cue, or be silent by design.
	var silent_by_design := ["status_expire"]
	var unheard: Array = []
	for k in census:
		if int(census[k]) > 0 and not (str(k) in silent_by_design) and not _kind_sounds(a, str(k)):
			unheard.append(k)
	unheard.sort()
	_check("every kind the real fight emits reaches a cue %s" % str(unheard), unheard.is_empty())

	a.queue_free()


## Feed a sequence of damage numbers through the grader and return which impact cue each earned.
## The clock is stepped between hits so the per-cue cooldowns cannot swallow one and make two runs
## differ for a reason that has nothing to do with grading.
func _grade_run(a, dmgs: Array) -> Array:
	a.reset()
	var out: Array = []
	for d in dmgs:
		var before: Dictionary = a.stat_played.duplicate()
		a._clock += 0.5
		a.on_event({"kind": "strike", "from": "a0", "to": "b0", "dmg": int(d), "crit": false},
			Vector3.ZERO, Vector3.ZERO)
		var got := "none"
		for g in ["hit_light", "hit_body", "hit_heavy", "hit_crit"]:
			if int(a.stat_played.get(g, 0)) > int(before.get(g, 0)):
				got = g
		out.append(got)
	return out


## Does this kind, on its own, produce a play? Replayed in isolation on a clean mixer, so the
## answer is about ROUTING rather than about whether that particular moment lost a voice.
func _kind_sounds(a, kind: String) -> bool:
	var before := _total(a.stat_played)
	a.reset()
	a._clock += 1.0
	a.on_event({"kind": kind, "from": "a0", "to": "b0", "id": "b0", "dmg": 30, "amount": 25,
		"targets": 3, "status": "poison", "move": "Bolt", "crit": false,
		"centre": Vector2.ZERO, "radius": 6.0}, Vector3.ZERO, Vector3(1, 0, 1))
	return _total(a.stat_played) > before


## Mean cues/second in each tenth of a fight. THE question this answers is whether the mix has a
## SHAPE — an approach, a clash, a turn, an ending — or whether every second sounds like every
## other second, in which case it is texture rather than information.
func _deciles(h: Array) -> Array:
	var out: Array = []
	if h.is_empty():
		return out
	for d in 10:
		var lo := int(float(d) * float(h.size()) / 10.0)
		var hi := maxi(lo + 1, int(float(d + 1) * float(h.size()) / 10.0))
		var s := 0
		for i in range(lo, mini(hi, h.size())):
			s += int(h[i])
		out.append(snappedf(float(s) / float(maxi(1, hi - lo)), 0.1))
	return out


func _sorted_line(d: Dictionary) -> String:
	var ks: Array = d.keys()
	ks.sort()
	var parts: Array = []
	for k in ks:
		parts.append("%s=%d" % [str(k), int(d[k])])
	return " ".join(parts)
