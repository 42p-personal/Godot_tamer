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
#   5. THE DENSITY GATE. A trailing cues-per-second meter that REFUSES low bands outright once the
#      second is already full. See `GATE_*` below.
#
# ⚠️ MECHANISMS 1–4 ARE ALL PER-CUE, AND THAT IS WHY THEY WERE NOT ENOUGH. Every one of them
# bounds ONE cue id against ITSELF, so twenty different cues can each sit comfortably inside their
# own cap and still sum to a wall. Measured on three seeded 5v5 fights (`_probe_audio.gd` §4):
# **21 cues in one second**, of which the largest single contributor was 5 — no per-cue number
# could have caught it, because no per-cue number was being broken. Mechanism 5 is the answer, and
# it is a REFUSAL rather than an attenuation on purpose: 21 quiet transients in a second are still
# 21 transients, and the ear integrates them into texture either way.
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

## ── THE DENSITY GATE ───────────────────────────────────────────────────────────────────────────
## `_rate` is a leaky integrator over ~1s, so its value reads directly as "cues per second right
## now". Once it passes a threshold the corresponding priority band stops being played AT ALL.
##
## The thresholds are the answer to "how many discrete events can a listener actually separate?"
## Around five is the honest number for unfamiliar transients; the bands are spaced so that a busy
## second degrades in the right ORDER — attrition ticks and whiffs go first, then the small support
## and utility beats, then body hits, and the fight-deciding band (deaths, interrupts, crits,
## resolutions, AoE) is NEVER gated. It keeps its own per-cue caps and that is the only limit it
## answers to.
##
## ⚠️ THIS RAISES DYNAMIC RANGE ON PURPOSE, AND THAT IS THE POINT. A quiet second is now fully
## audible down to the ticks; a scrum is reduced to its skeleton. The fight gets a SHAPE in sound
## instead of a flat wall, which is the whole reason to have a second channel at all.
const RATE_WINDOW := 1.0        # seconds of memory in the meter — makes `_rate` read as cues/sec
const GATE_P0 := 4.0            # above this, priority-0 (tick, miss) is refused
const GATE_P1 := 7.0            # above this, priority-1 (buff, debuff, ward, thorns, launch) too
const GATE_P2 := 9.0            # above this, even priority-2 (body hits, heals, cast rises)

## Per-cue mix: gain in dB, priority band, max simultaneous, and minimum gap between two of them.
## ⚠️ THESE FOUR NUMBERS ARE THE MIX. Changing a `db` without looking at `prio`/`cap`/`cd` is how
## a cue sheet turns into noise — a loud cue with a high cap and no cooldown will bury the fight
## no matter how well it was synthesised.
const MIX := {
	"hit_body":    {"db":  -3.0, "prio": 2, "cap": 5, "cd": 0.035},
	"hit_light":   {"db":  -9.0, "prio": 1, "cap": 4, "cd": 0.045},
	# Band 3, ungated: a blow this size is fight-deciding by definition, and it is rare — 13% of
	# casts and no basic attack in the measured fights reached the grade.
	"hit_heavy":   {"db":  -1.0, "prio": 3, "cap": 3, "cd": 0.05},
	"hit_crit":    {"db":   0.0, "prio": 3, "cap": 3, "cd": 0.02},
	# ⚠️ WARD_SOAK IS BAND 2, NOT BAND 1, AND THE MEASUREMENT IS WHY. `cues.gd` names the soak as
	# one of the three contrasts the whole sheet exists to carry — a clean hit that DOES NOTHING
	# reads as a bug unless something says the ward ate it. At band 1 the density gate played 1 of
	# 13 real soaks: the mix was deleting the answer to its own stated question.
	"ward_soak":   {"db":  -7.0, "prio": 2, "cap": 3, "cd": 0.06},
	"miss":        {"db": -15.0, "prio": 0, "cap": 2, "cd": 0.15},
	"thorns":      {"db": -10.0, "prio": 1, "cap": 2, "cd": 0.09},
	# ⚠️ THE RISE IS THE ONE SUSTAINED CUE, SO OVERLAP COSTS MORE HERE THAN ANYWHERE ELSE. It had
	# no cooldown at all, and `_begin_cast` frees the previous slot before taking a new one, so a
	# 5v5 opening put FIVE simultaneous two-octave saw sweeps in the air — measured, and the single
	# largest contributor to the densest second in the fight. Five overlapping sweeps are a drone,
	# not five readable intentions.
	# ⚠️ AND THE CAP IS THE WRONG LEVER FOR IT — MEASURED, TWICE. Dropping the cap to 2 silences a
	# SPECIFIC caster for the full 1.4s of somebody else's rise, so the third caster in a scrum
	# never winds up at all and the interrupt that kicks it lands on silence: the probe's
	# "every cast cut short had an audible rise to sever" check went from 3/3 to 1/3 on that one
	# change. The density gate bites only in genuinely busy seconds, and busy seconds are short.
	# So: cap stays at 3, band drops to 1 (a cast STARTING is less need-to-know than one LANDING),
	# and the gate does the rest. Peak density 12 → 11; 3/3 interrupts keep their rise.
	"cast_rise":   {"db":  -8.0, "prio": 1, "cap": 3, "cd": 0.18},
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
var _rate := 0.0                  # leaky cues/second meter — drives the density gate
var _rate_at := 0.0               # `_clock` when `_rate` was last decayed (lazy, see `_rate_now`)
var _dmg_ref := 1.0               # what a TYPICAL blow is in THIS fight — see `_dmg_ratio`
var _dmg_seen := 0
var _casting := {}                # unit id -> {"i": voice index, "serial": int} — so a rise can be CUT
var _speed := 1.0                 # replay speed, so a cast rise resolves with the cast bar
var _bed: AudioStreamPlayer = null
var _bed_target := -30.0
var _bed_db := -30.0
var _rng := RandomNumberGenerator.new()

## ── THE AUDIT COUNTERS ─────────────────────────────────────────────────────────────────────────
## Presentation bookkeeping. Nothing in the mix ever reads these back, and the sim cannot see them.
##
## ⚠️ THEY EXIST BECAUSE THE ONLY HONEST QUESTION ABOUT A MIX IS "WHAT DID THE LISTENER ACTUALLY
## HEAR", AND THAT IS A COUNT, NOT AN OPINION. A cue sheet can be beautifully authored, fully
## priced and completely inaudible — the caps and cooldowns above are DESIGNED to refuse work, and
## without a refusal count there is no way to tell "the mix is protecting the important beats" from
## "the mix is eating them". `_probe_audio.gd` §4 reads these off a real fight.
var stat_events := {}    # sim event kind -> times on_event() saw it
var stat_played := {}    # cue id -> times it took a voice
var stat_refused := {}   # cue id -> times the mix declined it
var stat_cut := 0        # cast rises severed (interrupt / resolve / launch / hard control)


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
	stat_events[kind] = int(stat_events.get(kind, 0)) + 1
	var actor := str(e.get("from", ""))
	var subject := str(e.get("to", e.get("id", "")))
	match kind:
		# `proj_hit` is an arrow ARRIVING and carries the same dmg/crit shape as a strike, so it
		# sounds like one — the whip of `proj_launch` already told the ear it was a shot.
		# ⚠️ Both were in the watch scene's printed vocabulary and were silent on the first pass.
		# Routing every kind the stream can produce is this project's standing rule about authored
		# content that nothing reaches, applied to audio.
		"strike", "proj_hit":
			var ratio := _dmg_ratio(int(e.get("dmg", 0)))
			if bool(e.get("crit", false)):
				_play("hit_crit", at_pos, subject)
			elif ratio >= HEAVY_RATIO:
				_play("hit_heavy", at_pos, subject)
			elif ratio >= BODY_RATIO:
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
			# ⚠️ THE CHORD NOW CARRIES THE WEIGHT OF THE BLOW, NOT JUST THE FACT OF IT. Every cast
			# used to resolve at one fixed gain across a 1–80 damage range. Scaling the resolution
			# costs nothing in density — same one play — and is the same trick `aoe` already uses
			# with its target count two branches down.
			var cr := _dmg_ratio(int(e.get("dmg", 0)))
			_play("cast_done", at_pos, actor, 0.0,
				lerpf(-6.0, 2.0, clampf(cr / HEAVY_RATIO, 0.0, 1.0)))
			if bool(e.get("crit", false)):
				_play("hit_crit", at_pos, subject)
			elif cr >= HEAVY_RATIO:
				# A big spell LANDING gets the impact under its chord. Rare by construction, so
				# this adds ~13 plays across a 265-second sample — nothing the gate has to absorb.
				_play("hit_heavy", at_pos, subject)
		"fizzle":
			# ⚠️ THIS USED TO BE SILENT, AND SILENCE WAS THE WRONG ANSWER. A fizzle is an AoE that
			# committed and caught nobody: the rise stops dead and nothing arrives. That is exactly
			# the ambiguity the interrupt cue was built to remove — a gesture that simply vanishes
			# reads as a dropped frame, not as an outcome. `cast_miss` two branches up already
			# answers the identical situation with the whiff, so answering it differently here was
			# an inconsistency, not a decision. Two plays per 265 seconds of fight; no density cost.
			_cut_cast(actor)
			_play("miss", at_pos, actor)
		"interrupt":
			# ⚠️ ORDER MATTERS. The rise is severed BEFORE the clang is queued, so the clang is
			# never the cue that gets denied a voice while the thing it interrupts keeps playing.
			_cut_cast(subject)
			_play("interrupt", at_pos, subject)
			_bump_loud(0.55)
		"status_break":
			# ⚠️ `status_break` IS THREE DIFFERENT EVENTS SHARING ONE NAME, AND ONLY ONE OF THEM IS
			# A CAST BEING DESTROYED. `sim.gd` tags each with a `cause`:
			#   "control"  — hard control ate a COMMITTED CAST. This is the shatter.
			#   "damage"   — sleep woke because something hit the sleeper. No cast involved.
			#   "consumed" — a detonator cashed in its bonusVsStatus fuel. A combo PAYOFF.
			# All three used to cut the victim's rise and play the shatter at priority 3, so a
			# sleeping monster woken by a stray blow fired the loudest "your cast was destroyed"
			# sound in the mix, and a combo landing sounded like a catastrophe. In a game whose
			# whole loop is watching, that is not a mix problem — it is the audio LYING.
			# ⚠️ MEASURED, NOT SUSPECTED: across three seeded 5v5s BOTH status_breaks that occurred
			# were false shatters. `_probe_audio.gd` §4 counts every cut against whether a rise
			# existed to sever, and neither of them had one.
			if str(e.get("cause", "control")) == "control":
				_cut_cast(subject)
				_play("status_break", at_pos, subject)
				_bump_loud(0.4)
			# `damage` and `consumed` stay silent, and that is a lie removed rather than a sound
			# taken away: both arrive on the same tick as the hit that caused them, and that hit
			# already sounds. Both still deserve presentation — on the VISUAL layer, where neither
			# has any today.
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
	_rate = 0.0
	_rate_at = _clock
	# The damage reference is fight-local: a replay restarting must not inherit the last fight's
	# idea of what a big hit was, or the opening exchange would be graded against a boss.
	_dmg_ref = 1.0
	_dmg_seen = 0
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
		stat_refused[cue] = int(stat_refused.get(cue, 0)) + 1
		return -1
	var prio := int(mix["prio"])
	# THE GATE, before the voice pool is even consulted — a refused cue must not cost an allocation
	# or bump a cooldown, or a busy second would go on quietly rationing voices nobody hears.
	if _gated(prio):
		stat_refused[cue] = int(stat_refused.get(cue, 0)) + 1
		return -1
	var i := _voice(cue, prio, float(mix["cd"]), int(mix["cap"]))
	if i < 0:
		stat_refused[cue] = int(stat_refused.get(cue, 0)) + 1
		return -1
	stat_played[cue] = int(stat_played.get(cue, 0)) + 1
	_rate = _rate_now() + 1.0

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


## How big was that blow, ON THE SCALE OF THIS FIGHT? Returns 0..1-ish against a leaky reference
## that tracks the largest damage seen recently.
##
## ⚠️ IT IS RELATIVE ON PURPOSE, AND THE ABSOLUTE IT REPLACES WAS A REAL BUG WAITING TO HAPPEN.
## The old grader asked `dmg >= 8`, a constant authored when a basic attack was the only thing
## being graded. Damage in this game scales with stats across the whole ladder — the Tamers Apex
## cap is 1100 — so ANY fixed threshold means every hit is "heavy" at the top of the ladder and
## none is at the bottom. `docs/ABILITY_BALANCE_REVIEW.md` records exactly this failure mode for
## the spatial constants ("every spatial constant is a fixed absolute … none scale"); repeating it
## in audio would be paying for the same lesson twice.
##
## ⚠️ AND IT DERIVES NO GAME FACT. This is a compressor: the presentation layer normalising its own
## dynamic range from the stream it is handed. Nothing is read back, nothing reaches `Sim`, and the
## thing a listener learns — "that was a big one FOR THIS FIGHT" — is the more useful read anyway,
## because it stays true at every league.
## ⚠️ THE REFERENCE IS A RUNNING MEAN, NOT A RUNNING MAXIMUM, AND THE FIRST DRAFT GOT THAT WRONG.
## Tracking the largest hit so far makes every early hit the largest so far, so a fight opened with
## five consecutive haymakers and then calmed down — exactly backwards, and worst precisely at the
## moment `docs/WATCH_AUDIT.md` says everything happens at once. A mean converges in a handful of
## events and puts the NEUTRAL grade in the middle, which is the honest default for an unknown hit:
## the very first blow of a fight grades `hit_body`, because nothing yet knows any better.
const HEAVY_RATIO := 1.8        # this many times the typical blow of this fight
const BODY_RATIO := 0.72        # below this it is a chip, a tick of a multi-hit, a glancing poke
const DMG_REF_RATE := 0.15      # how fast the mean tracks; ~15 hits to fully re-centre

func _dmg_ratio(dmg: int) -> float:
	if _dmg_seen == 0:
		_dmg_ref = maxf(1.0, float(dmg))
	else:
		_dmg_ref += (float(dmg) - _dmg_ref) * DMG_REF_RATE
	_dmg_seen += 1
	return float(dmg) / maxf(1.0, _dmg_ref)


## The density meter, decayed LAZILY off `_clock` rather than in `_process`.
## ⚠️ THAT IS DELIBERATE AND IT IS WHAT MAKES THE GATE TESTABLE. `_process` runs at the render
## frame rate, which under `--headless` bears no relation to fight time; the probe drives `_clock`
## by `Sim.DT` instead. Decaying here means the gate the probe measures is byte-for-byte the gate
## that runs with a real device and a real frame rate.
func _rate_now() -> float:
	var dt := maxf(0.0, _clock - _rate_at)
	_rate_at = _clock
	if dt > 0.0:
		_rate *= exp(-dt / RATE_WINDOW)
	return _rate


## Is this priority band currently shut out by the density gate? Band 3 never is.
func _gated(prio: int) -> bool:
	if prio >= 3:
		return false
	var r := _rate_now()
	if prio == 0:
		return r >= GATE_P0
	if prio == 1:
		return r >= GATE_P1
	return r >= GATE_P2


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
	stat_cut += 1


## Clear the audit counters. Separate from `reset()` on purpose: `reset()` runs on every replay
## restart and speed change, and a counter that a UI action silently zeroed would report a fight
## that never happened.
func audit_reset() -> void:
	stat_events.clear()
	stat_played.clear()
	stat_refused.clear()
	stat_cut = 0


## Stable per-unit pitch offset from the id string. Deterministic by construction: the same
## fighter has the same voice in every replay of every fight.
##
## ⚠️ THE BAND IS THE TEAM, AND THAT IS THE POINT OF THIS FUNCTION NOW, NOT A DECORATION.
## The camera can only ever show one part of the ground, and `docs/ENGAGEMENT_DESIGN.md` leads with
## the finding that an arena larger than the screen makes a diffuse fight UNFILMABLE. Sound is the
## channel that keeps working while the camera is looking elsewhere — but only if it says WHOSE.
## Positional panning already says WHERE; nothing said WHICH SIDE, so a death off-screen was a
## death, full stop, and the viewer had to wait for the camera or the log to learn whether it was
## theirs. Splitting the hash into two disjoint bands makes the answer instant and pre-verbal:
##
##   team A (the player's side, by the sim's own id convention)  →  0.86 … 0.95  — the low voices
##   team B (the opposition)                                     →  1.05 … 1.14  — the high voices
##
## The ~1.7-semitone gap between the bands is wider than the spread WITHIN either, so the side
## always reads before the individual. Every cue inherits it — a death, a soak, a taunt, a crit —
## so this is one change that makes twenty cues carry a fact they did not carry before.
##
## ⚠️ IT READS THE ID PREFIX, WHICH IS THE SIM'S OWN TEAM MARKER, AND DERIVES NOTHING. `sim.gd`
## mints ids as `a<slot>` / `b<slot>` and `arena_3d.gd:_name_of_sim_id` already resolves the side
## the same way. An id matching neither falls to the neutral middle band rather than guessing, so
## a future third side or a non-unit emitter (the crowd) is merely unbanded, never mislabelled.
##
## ⚠️ THE OFFSET INSIDE A BAND COMES FROM THE SLOT, NOT FROM A HASH, AND THE OLD HASH WAS BROKEN.
## `h = h * 131 + c` over `"a0"`…`"a4"` differs only in the final byte, so `h % 1000` came out as
## 755, 756, 757, 758, 759 — the five voices of a five-monster side spanned **0.0006 in pitch**,
## which is a thousandth of a semitone and flatly inaudible. The probe passed it anyway, because it
## only asserted the five floats were UNEQUAL. Spacing the slot across the band is guaranteed
## distinct by construction instead of by luck, and it is just as deterministic.
##
## ⚠️ AND THE TRADE-OFF IS STATED RATHER THAN SPLIT: with five bodies a side, the band cannot be
## both wide enough to identify an individual and narrow enough for the SIDE to read first. Side
## wins — it is the thing the camera cannot tell you — so the gap between bands is twice the spread
## inside one. Individual pitch is texture (five swings must not sound like one swing five times);
## side is information.
const TEAM_A_PREFIX := "a"
const TEAM_B_PREFIX := "b"
const BAND_A_LO := 0.88
const BAND_B_LO := 1.06
const BAND_SPREAD := 0.06     # width of one side's band; the A→B gap is 0.12, twice this

func _unit_pitch(uid: String) -> float:
	if uid == "":
		return 1.0
	var h := 0
	for c in uid.to_utf8_buffer():
		h = (h * 131 + int(c)) & 0xFFFFFF
	# Slot 0..5 spaced across the band; anything unparseable falls back to the hash, which is
	# still fine for texture — it is only the SIDE that has to be reliable.
	var tail := uid.substr(1)
	var f := (float(tail.to_int() % 6) / 5.0) if tail.is_valid_int() else float(h % 1000) / 1000.0
	if uid.begins_with(TEAM_A_PREFIX):
		return BAND_A_LO + f * BAND_SPREAD
	if uid.begins_with(TEAM_B_PREFIX):
		return BAND_B_LO + f * BAND_SPREAD
	return 0.97 + float(h % 1000) / 1000.0 * 0.06


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
