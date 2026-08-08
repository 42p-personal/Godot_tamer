extends Node3D
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# BATTLE AUDIO — the fight's second read.
#
# The game was completely silent, which in a WATCH-ONLY game is the largest missing sensory layer
# there is: the player commits tactics and then has one channel (their eyes) to learn what those
# tactics did. This node opens the second one.
#
# HOW IT IS DRIVEN. Entirely by the frame stream. `on_event()` takes an event dictionary straight
# out of `sim.gd` and a world position, and that is the whole interface. It derives NOTHING about
# the fight on its own — no re-simulation, no reading unit state, no timers of its own that decide
# anything. If the stream says it happened, it makes a sound; otherwise there is silence.
#
# ⚠️ DETERMINISM. This is presentation code and may use randomness freely, and it does (voice
# stealing depends on wall-clock arrival, per-unit pitch on a string hash). NOTHING here is ever
# read back by the sim — there is no path from this node into `Sim`. It never touches `sim.rng`.
#
# ⚠️ IT MUST NEVER TAKE THE WATCH SCENE DOWN. Every public method early-returns when `_ok` is
# false, `_ok` is set only after the whole cue bank renders, and the caller loads this script
# defensively. A broken audio layer degrades to the silent game we already had.
#
# ───────────────────────────────────────────────────────────────────────────────────────────────
# MIX DISCIPLINE — the part that decides whether this is a soundscape or a wall of noise.
#
# A 5v5 fires dozens of events per second. Played naively that is not "loud", it is INFORMATION
# LOSS: the interrupt that decided the fight arrives inside a hash of ticks and misses and the
# viewer learns nothing. Four mechanisms, all in `_voice()`:
#
#   1. PRIORITY (0..3). Every cue is banded. A high-priority cue may steal a voice from a
#      strictly lower-priority one; it may never steal from an equal or higher one.
#   2. PER-KIND CAPS. At most N of any one cue may be in flight — five simultaneous body hits
#      read as a scrum, twelve read as static.
#   3. PER-KIND COOLDOWNS. A cue that just fired is suppressed for a few tens of ms. This is what
#      collapses a multi-hit into one audible flurry instead of five separate transients.
#   4. DUCKING. `_loud` rises on every priority-3 beat and decays over ~1.2s. While it is up, the
#      low-priority cues (ticks, misses) lose up to 14 dB. The important beats stay on top by
#      pushing the small ones down, not by getting louder themselves.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

const Synth = preload("res://scripts/audio/synth.gd")
const Cues = preload("res://scripts/audio/cues.gd")

## Positional voices — impacts, casts, deaths. Sized for a 5v5 scrum plus headroom; the caps
## below mean the pool is never actually exhausted by legitimate play, only by pathology.
const VOICES := 20

## Master trim for the whole battle layer, in dB. Everything else is relative to this.
const MASTER_DB := -6.0

## Ducking depth for priority-0 cues at full `_loud`.
const DUCK_DB := 14.0

## How fast the "something big just happened" meter falls back. ~1.2s to clear from full.
const LOUD_DECAY := 0.85

## Per-cue mix: gain in dB, priority band, max simultaneous, and minimum gap between two of them.
## ⚠️ THESE FOUR NUMBERS ARE THE MIX. Changing a `db` without looking at `prio`/`cap`/`cd` is how
## a cue sheet turns into noise — a loud cue with a high cap and no cooldown will bury the fight
## no matter how well it was synthesised.
const MIX := {
	"hit_body":    {"db":  -3.0, "prio": 2, "cap": 5, "cd": 0.035},
	"hit_light":   {"db":  -9.0, "prio": 1, "cap": 4, "cd": 0.045},
	"hit_crit":    {"db":   0.0, "prio": 3, "cap": 3, "cd": 0.02},
	"ward_soak":   {"db":  -7.0, "prio": 1, "cap": 3, "cd": 0.06},
	"miss":        {"db": -15.0, "prio": 0, "cap": 2, "cd": 0.15},
	"thorns":      {"db": -10.0, "prio": 1, "cap": 2, "cd": 0.09},
	"cast_rise":   {"db":  -8.0, "prio": 2, "cap": 4, "cd": 0.0},
	"cast_done":   {"db":  -2.0, "prio": 3, "cap": 3, "cd": 0.03},
	"interrupt":   {"db":   1.0, "prio": 3, "cap": 2, "cd": 0.02},
	"status_break":{"db":  -1.0, "prio": 3, "cap": 2, "cd": 0.04},
	"death":       {"db":   0.0, "prio": 3, "cap": 3, "cd": 0.02},
	"aoe":         {"db":  -1.0, "prio": 3, "cap": 2, "cd": 0.05},
	"taunt":       {"db":  -4.0, "prio": 3, "cap": 1, "cd": 0.25},
	"heal":        {"db":  -6.0, "prio": 2, "cap": 3, "cd": 0.07},
	"cleanse":     {"db":  -7.0, "prio": 2, "cap": 2, "cd": 0.12},
	"buff":        {"db":  -9.0, "prio": 1, "cap": 2, "cd": 0.10},
	"debuff":      {"db":  -9.0, "prio": 1, "cap": 2, "cd": 0.10},
	"status":      {"db": -10.0, "prio": 1, "cap": 3, "cd": 0.07},
	"tick":        {"db": -17.0, "prio": 0, "cap": 2, "cd": 0.13},
	"proj_launch": {"db": -12.0, "prio": 1, "cap": 4, "cd": 0.05},
	"crowd_roar":  {"db":  -9.0, "prio": 3, "cap": 2, "cd": 0.45},
}

## Statuses are separated by PITCH rather than by cue — 15 of them cannot each earn a sound, but
## "the sour blip that means poison" and "the one that means stun" being different notes is enough
## for the ear to tell a re-application from a new affliction. Anything unlisted rides at 1.0.
const STATUS_PITCH := {
	"stun": 0.66, "fear": 0.72, "sleep": 0.62, "confusion": 0.78, "charm": 0.84,
	"silence": 0.90, "blind": 0.96, "poison": 1.06, "burn": 1.14, "bleed": 1.22,
	"vulnerable": 1.30, "doom": 0.58, "healblock": 1.38, "haste": 1.46, "knockback": 1.02,
}

var _ok := false                  # the bank rendered and the pool built — every entry point gates on it
var _bank := {}                   # cue id -> AudioStreamWAV
var _voices: Array = []           # Array[Dictionary] — see `_voice()`
var _serial := 0                  # monotonic voice-acquisition id; a cast handle checks it before cutting
var _last_played := {}            # cue id -> _clock at last successful play (the cooldown gate)
var _clock := 0.0                 # audio-local seconds; the ONLY time source in this file
var _loud := 0.0                  # 0..1 "a big beat just landed" meter — drives ducking
var _casting := {}                # unit id -> {"i": voice index, "serial": int} — so a rise can be CUT
var _speed := 1.0                 # replay speed, so a cast rise resolves with the cast bar
var _bed: AudioStreamPlayer = null
var _bed_target := -30.0
var _bed_db := -30.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	ensure_built()


## Idempotent build. `_ready()` is the normal entry; the probe calls it directly because a node
## added to `root` from `SceneTree._initialize()` is not yet inside the tree and never gets one.
func ensure_built() -> void:
	if _ok:
		return
	_rng.seed = 90210
	_build()


## Render every cue and build the voice pool. Any failure leaves `_ok` false and the node inert.
func _build() -> void:
	if not _voices.is_empty():
		return   # a half-built pool must never be built twice on top of itself
	var sheet: Dictionary = Cues.sheet()
	var ids: Array = sheet.keys()
	ids.sort()
	for id in ids:
		var st: AudioStreamWAV = Synth.render(sheet[id] as Array, 0.85, str(id) == "crowd_bed")
		if st == null:
			push_warning("battle_audio: cue '%s' failed to render — audio layer disabled" % str(id))
			return
		_bank[str(id)] = st

	for i in range(VOICES):
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 26.0          # the camera sits ~55u out; the whole ground must stay audible
		p.max_distance = 190.0
		p.max_db = 3.0
		add_child(p)
		_voices.append({"p": p, "cue": "", "prio": -1, "until": -1.0, "serial": -1})

	_bed = AudioStreamPlayer.new()
	_bed.stream = _bank["crowd_bed"]
	_bed.volume_db = _bed_db
	add_child(_bed)

	_ok = true


func _process(delta: float) -> void:
	if not _ok:
		return
	# The bed starts on the first frame INSIDE the tree, not at build time: Godot refuses
	# playback on an unparented node, and the probe builds the layer outside the tree on purpose.
	if not _bed.playing and _bed.is_inside_tree():
		_bed.play()
	_clock += delta
	_loud = maxf(0.0, _loud - delta * LOUD_DECAY)
	# The bed rises fast on a swell and falls slowly — a crowd that snaps back to room tone in
	# half a second sounds like a volume slider, not like people.
	var rate := 6.0 if _bed_target > _bed_db else 0.6
	_bed_db = move_toward(_bed_db, _bed_target, delta * rate * 12.0)
	_bed_target = maxf(-30.0, _bed_target - delta * 2.5)
	_bed.volume_db = _bed_db + MASTER_DB


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# THE INTERFACE — four calls, and the first one is the whole game.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## Sound one event from the frame stream.
## `from_pos` is the actor's world position, `at_pos` where the thing HAPPENED (the victim, the
## AoE centre, the corpse). Both are already-derived presentation state; nothing is recomputed.
func on_event(e: Dictionary, from_pos: Vector3, at_pos: Vector3) -> void:
	if not _ok:
		return
	var kind := str(e.get("kind", ""))
	var actor := str(e.get("from", ""))
	var subject := str(e.get("to", e.get("id", "")))
	match kind:
		# `proj_hit` is an arrow ARRIVING and carries the same dmg/crit shape as a strike, so it
		# sounds like one — the whip of `proj_launch` already told the ear it was a shot.
		# ⚠️ Both were in the watch scene's printed vocabulary and were silent on the first pass.
		# Routing every kind the stream can produce is this project's standing rule about authored
		# content that nothing reaches, applied to audio.
		"strike", "proj_hit":
			var dmg := int(e.get("dmg", 0))
			if bool(e.get("crit", false)):
				_play("hit_crit", at_pos, subject)
			elif dmg >= 8:
				_play("hit_body", at_pos, subject)
			else:
				_play("hit_light", at_pos, subject)
		"miss", "cast_miss", "proj_fizzle":
			if kind != "miss":
				_cut_cast(actor)
			_play("miss", at_pos, actor)
		"proj_launch":
			# ⚠️ A projectile move emits NO cast_done — the sequence is cast_start → proj_launch →
			# proj_hit. Without the cut here a ranged caster's rise keeps climbing after the shot
			# has already left the hand, which is the one lie this cue exists to prevent.
			_cut_cast(actor)
			_play("proj_launch", from_pos, actor)
		"cast_start":
			_begin_cast(actor, from_pos)
		"cast_done":
			# The rise resolves INTO this — cut it on the same frame so there is no overlap
			# between the unfinished gesture and its answer.
			_cut_cast(actor)
			_play("cast_done", at_pos, actor)
			if bool(e.get("crit", false)):
				_play("hit_crit", at_pos, subject)
		"fizzle":
			_cut_cast(actor)
		"interrupt":
			# ⚠️ ORDER MATTERS. The rise is severed BEFORE the clang is queued, so the clang is
			# never the cue that gets denied a voice while the thing it interrupts keeps playing.
			_cut_cast(subject)
			_play("interrupt", at_pos, subject)
			_bump_loud(0.55)
		"status_break":
			_cut_cast(subject)
			_play("status_break", at_pos, subject)
			_bump_loud(0.4)
		"death":
			_cut_cast(subject)
			_play("death", at_pos, subject)
			_bump_loud(0.8)
		"aoe":
			var targets := int(e.get("targets", 1))
			# "Weak into one body, strong into three" is a balance rule; here it is a mix rule.
			_play("aoe", at_pos, actor, 0.0, clampf(-6.0 + 3.0 * float(targets), -6.0, 3.0))
			if targets >= 3:
				_bump_loud(0.6)
		"heal":
			if int(e.get("amount", 0)) > 0:
				_play("heal", at_pos, subject)
		"ward_soak":
			if int(e.get("amount", 0)) > 0:
				_play("ward_soak", at_pos, subject)
		"thorns":
			if int(e.get("dmg", 0)) > 0:
				_play("thorns", at_pos, subject)
		"status_applied":
			_play("status", at_pos, subject, _status_pitch(str(e.get("status", ""))) - 1.0)
		"cleanse":
			_play("cleanse", at_pos, subject)
		"taunted":
			_play("taunt", from_pos, actor)
			_bump_loud(0.3)
		"buff":
			_play("buff", at_pos, subject)
		"debuff":
			_play("debuff", at_pos, subject)
		"status_tick":
			if float(e.get("dmg", 0.0)) > 0.0:
				_play("tick", at_pos, subject)
		_:
			pass   # status_expire and anything new stay silent until someone designs a cue for it


## The crowd, swelling on the same beats it already reacts to visually.
## `intensity` is the value `_watch_sim._crowd_react` was called with, so the seats and the sound
## are one system rather than two that happen to agree.
func crowd_swell(intensity: float) -> void:
	if not _ok:
		return
	var i := clampf(intensity, 0.0, 1.0)
	_bed_target = maxf(_bed_target, lerpf(-26.0, -9.0, i))
	if i >= 0.5:
		_play("crowd_roar", Vector3.ZERO, "crowd", _rng.randf_range(-0.05, 0.05),
			lerpf(-8.0, 0.0, i))


## Replay speed. The cast rise is the one cue with a musical DURATION, so it is pitched to land
## roughly where the cast bar does; at 4x an un-scaled rise would still be climbing after the
## spell resolved, which is exactly the wrong lie to tell.
func set_speed(s: float) -> void:
	_speed = clampf(s, 0.25, 8.0)


## Silence everything. Called on replay restart — a cast rise from the previous run must not
## survive into a fight that is starting again from tick 0.
func reset() -> void:
	if not _ok:
		return
	for v in _voices:
		(v["p"] as AudioStreamPlayer3D).stop()
		v["until"] = -1.0
		v["cue"] = ""
		v["prio"] = -1
	_casting.clear()
	_last_played.clear()
	_loud = 0.0
	_bed_target = -30.0


func set_muted(m: bool) -> void:
	if not _ok:
		return
	for v in _voices:
		(v["p"] as AudioStreamPlayer3D).stream_paused = m
	_bed.stream_paused = m


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# THE MIXER
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## Play a cue, or decline to. Returns the voice index, or -1 if the mix refused it — a refusal is
## a normal, frequent, DESIRED outcome, not an error.
func _play(cue: String, pos: Vector3, uid: String, pitch_off: float = 0.0, gain_off: float = 0.0) -> int:
	var mix: Dictionary = MIX.get(cue, {})
	if mix.is_empty() or not _bank.has(cue):
		return -1
	var prio := int(mix["prio"])
	var i := _voice(cue, prio, float(mix["cd"]), int(mix["cap"]))
	if i < 0:
		return -1

	# Per-unit pitch. Five monsters swinging must not sound like one monster swinging five times,
	# and the offset is a HASH of the id so a given fighter sounds the same every replay.
	var pitch := clampf(_unit_pitch(uid) + pitch_off, 0.35, 3.0)
	if cue == "cast_rise":
		pitch = clampf(pitch * _speed, 0.35, 4.0)

	var duck := 0.0
	if prio <= 1:
		duck = -DUCK_DB * _loud * (1.0 if prio == 0 else 0.6)

	var v: Dictionary = _voices[i]
	var p: AudioStreamPlayer3D = v["p"]
	var st: AudioStreamWAV = _bank[cue]
	p.stop()
	p.stream = st
	p.pitch_scale = pitch
	p.position = pos
	p.volume_db = MASTER_DB + float(mix["db"]) + gain_off + duck
	if p.is_inside_tree():
		p.play()   # out of tree (probe) the bookkeeping below still runs — the mix is testable

	_serial += 1
	v["cue"] = cue
	v["prio"] = prio
	v["serial"] = _serial
	# ⚠️ The pool tracks its own busy-until rather than reading `player.playing`. Headless runs on
	# the dummy audio driver, where `playing` is not a reliable liveness signal — basing voice
	# limiting on it would mean the caps silently stop existing in exactly the configuration the
	# probes run in, and the probes would happily pass on an unlimited mixer.
	v["until"] = _clock + st.get_length() / maxf(pitch, 0.05)
	_last_played[cue] = _clock
	if prio >= 3:
		_bump_loud(0.3)
	return i


## Voice allocation: cooldown, then cap, then a free slot, then a steal from strictly below.
func _voice(cue: String, prio: int, cooldown: float, cap: int) -> int:
	if _clock - float(_last_played.get(cue, -999.0)) < cooldown:
		return -1
	var live := 0
	var free := -1
	var steal := -1
	var best_prio := 999
	var best_until := INF
	for i in range(_voices.size()):
		var v: Dictionary = _voices[i]
		if float(v["until"]) <= _clock:
			if free < 0:
				free = i
			continue
		if str(v["cue"]) == cue:
			live += 1
		# Steal the one that is both LOWEST priority and closest to finishing — cutting a cue that
		# had 30ms left costs the listener nothing. A cue NEVER steals from its own band or above.
		var vp := int(v["prio"])
		if vp < prio and (vp < best_prio or (vp == best_prio and float(v["until"]) < best_until)):
			steal = i
			best_prio = vp
			best_until = float(v["until"])
	if live >= cap:
		return -1
	if free >= 0:
		return free
	return steal


func _bump_loud(amount: float) -> void:
	_loud = minf(1.0, _loud + amount)


## Start a caster's rising tone and remember the handle, so `_cut_cast` can sever exactly it.
func _begin_cast(uid: String, pos: Vector3) -> void:
	if uid == "":
		return
	_cut_cast(uid)
	var i := _play("cast_rise", pos, uid)
	if i >= 0:
		_casting[uid] = {"i": i, "serial": int((_voices[i] as Dictionary)["serial"])}


## THE CUT. Stops the rise only if that voice is still the one this caster started — the serial
## check is what stops a stale handle silencing whatever cue later reused the slot.
func _cut_cast(uid: String) -> void:
	if uid == "" or not _casting.has(uid):
		return
	var h: Dictionary = _casting[uid]
	_casting.erase(uid)
	var i := int(h["i"])
	if i < 0 or i >= _voices.size():
		return
	var v: Dictionary = _voices[i]
	if int(v["serial"]) != int(h["serial"]):
		return
	(v["p"] as AudioStreamPlayer3D).stop()
	v["until"] = -1.0
	v["cue"] = ""
	v["prio"] = -1


## Stable per-unit pitch offset from the id string. Deterministic by construction: the same
## fighter has the same voice in every replay of every fight.
func _unit_pitch(uid: String) -> float:
	if uid == "":
		return 1.0
	var h := 0
	for c in uid.to_utf8_buffer():
		h = (h * 131 + int(c)) & 0xFFFFFF
	return 0.92 + float(h % 1000) / 1000.0 * 0.16


func _status_pitch(kind: String) -> float:
	return float(STATUS_PITCH.get(kind, 1.0))


# ═══════════════════════════════════════════════════════════════════════════════════════════════
# SELF-TEST — run by `scripts/audio/_probe_audio.gd`.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## Render every cue OUTSIDE the node and report its shape. A cue that comes back empty, silent,
## clipped or DC-offset is a bug the ear would only find later and only vaguely.
static func analyse_bank() -> Dictionary:
	var out := {}
	var sheet: Dictionary = Cues.sheet()
	var ids: Array = sheet.keys()
	ids.sort()
	for id in ids:
		var st: AudioStreamWAV = Synth.render(sheet[id] as Array, 0.85, str(id) == "crowd_bed")
		if st == null:
			out[str(id)] = {"ok": false, "reason": "render returned null"}
			continue
		var data: PackedByteArray = st.data
		var n := data.size() / 2
		var peak := 0.0
		var sum := 0.0
		var energy := 0.0
		for i in range(n):
			var v := float(data.decode_s16(i * 2)) / 32768.0
			peak = maxf(peak, absf(v))
			sum += v
			energy += v * v
		out[str(id)] = {
			"ok": true,
			"samples": n,
			"seconds": st.get_length(),
			"peak": peak,
			"rms": sqrt(energy / maxf(1.0, float(n))),
			"dc": absf(sum / maxf(1.0, float(n))),
			"looped": st.loop_mode == AudioStreamWAV.LOOP_FORWARD,
		}
	return out
