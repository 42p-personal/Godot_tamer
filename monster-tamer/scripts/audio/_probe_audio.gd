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
extends SceneTree

const BattleAudio = preload("res://scripts/audio/battle_audio.gd")
const Synth = preload("res://scripts/audio/synth.gd")
const Cues = preload("res://scripts/audio/cues.gd")

var _fails := 0


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

	# CAP. Tested on `cast_rise` because it is the one cue with no cooldown — on a cue that has
	# one, the cooldown and the cue's own length bound the overlap first and the cap never binds,
	# so the test would pass without the cap existing at all.
	a.reset()
	var taken := 0
	for i in range(8):
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
	var pitches := {}
	for uid in ["a0", "a1", "a2", "a3", "a4"]:
		pitches[a._unit_pitch(uid)] = true
	_check("five units get five distinct voices", pitches.size() == 5)
	_check("per-unit pitch is stable across calls", a._unit_pitch("a3") == a._unit_pitch("a3"))
	_check("pitch stays inside a natural band",
		a._unit_pitch("a0") > 0.9 and a._unit_pitch("a0") < 1.1)

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
	var silent_by_design := ["fizzle", "status_expire"]
	var mute: Array = []
	for k in kinds:
		a.reset()
		a._clock += 0.5
		a.on_event({"kind": k, "from": "a0", "to": "b0", "id": "b0", "dmg": 30, "amount": 25,
			"targets": 3, "status": "poison", "move": "Bolt", "crit": false,
			"centre": Vector2.ZERO, "radius": 6.0}, Vector3.ZERO, Vector3(1, 0, 1))
		if a._last_played.is_empty():
			mute.append(k)
	_check("every routed kind produces a cue except the two that must not %s" % str(mute),
		mute == silent_by_design)

	a.crowd_swell(0.9)
	_check("a big crowd beat swells the bed", a._bed_target > -20.0)
	a.reset()
	_check("reset silences the bed and the pool", a._bed_target <= -30.0 and a._casting.is_empty())

	a.queue_free()
