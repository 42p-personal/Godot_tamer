extends RefCounted
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# SYNTH — every sound in the game is GENERATED, none is licensed.
#
# The project already took the "generate it, don't licence it" route for particle textures; audio
# takes the same one. Nothing is downloaded, nothing carries a licence, the repo stays clean, and
# a cue is a handful of numbers in `cues.gd` rather than a binary nobody can diff.
#
# The unit of authoring is a LAYER — one oscillator with a pitch slide and an ADSR envelope. A cue
# is an Array of layers summed together (a body thump is a sine + a noise transient; a crit is
# those plus a driven square). `render()` mixes them, soft-clips, and NORMALISES to a target peak,
# so a badly-authored cue comes out quiet rather than clipped. `_probe_audio.gd` asserts that.
#
# ⚠️ THIS IS PRESENTATION CODE. It uses its own RandomNumberGenerator, seeded per layer, and never
# touches sim.rng. Nothing it produces feeds back into the fight — the sim does not know it exists.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

## 22050 Hz mono. Every cue here is percussive, sub-1.6s and mostly below 4kHz; the extra octave a
## 44.1k rate would buy is inaudible on a body thump and doubles every buffer in memory.
const RATE := 22050

## Hard ceiling on a single cue. A runaway `dur` would otherwise allocate without bound.
const MAX_DUR := 4.0

## Layer keys (all optional except `dur`):
##   dur       seconds of this layer
##   delay     silence before it starts — how the arpeggios (cleanse, buff) are built
##   wave      "sine" | "square" | "saw" | "tri" | "noise"
##   f0, f1    pitch slide start/end in Hz (f1 defaults to f0 = no slide)
##   slide     "exp" (default, musical) | "lin"
##   amp       pre-mix gain
##   atk/dec/rel   ADSR times in seconds; sus is the sustain LEVEL (0..1)
##   detune    second oscillator at f*(1+detune), summed — thickness/beating
##   noise_lp  one-pole lowpass coefficient for "noise" (1.0 raw hiss, 0.1 dark rumble)
##   drive     soft-clip amount; >1 adds harmonics (the metallic edge on interrupt/taunt)
##   seed      per-layer rng seed — same params always render the same bytes


## Render a cue (Array of layer Dictionaries) to a playable stream.
## `loop` makes it seamless-ish for the crowd bed. Returns null only if there is nothing to render.
static func render(layers: Array, target_peak: float = 0.85, loop: bool = false) -> AudioStreamWAV:
	if layers.is_empty():
		return null
	var total := 0.0
	for l in layers:
		var d: Dictionary = l
		total = maxf(total, float(d.get("delay", 0.0)) + float(d.get("dur", 0.2)))
	total = clampf(total, 0.01, MAX_DUR)
	var n := int(total * RATE)
	if n < 2:
		return null

	var buf := PackedFloat32Array()
	buf.resize(n)
	buf.fill(0.0)

	for l in layers:
		_render_layer(buf, l as Dictionary, n)

	# Peak-normalise. This is what makes "no clipping" a PROPERTY of the synth rather than a thing
	# each cue's author has to get right by hand.
	var peak := 0.0
	for i in range(n):
		peak = maxf(peak, absf(buf[i]))
	var gain := (target_peak / peak) if peak > 0.0001 else 0.0

	# A short fade at both ends. Without it every cue starts and ends on a DC step, which reads as
	# a click on top of the sound — the single most common "my procedural audio sounds cheap" bug.
	var fade := mini(int(0.004 * RATE), maxi(1, n / 8))

	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in range(n):
		var v := buf[i] * gain
		if i < fade:
			v *= float(i) / float(fade)
		elif not loop and i >= n - fade:
			v *= float(n - 1 - i) / float(fade)
		v = clampf(v, -1.0, 1.0)
		bytes.encode_s16(i * 2, int(v * 32767.0))

	var st := AudioStreamWAV.new()
	st.format = AudioStreamWAV.FORMAT_16_BITS
	st.mix_rate = RATE
	st.stereo = false
	st.data = bytes
	if loop:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_begin = 0
		st.loop_end = n - 1
	return st


static func _render_layer(buf: PackedFloat32Array, d: Dictionary, n: int) -> void:
	var dur := clampf(float(d.get("dur", 0.2)), 0.001, MAX_DUR)
	var off := int(maxf(0.0, float(d.get("delay", 0.0))) * RATE)
	if off >= n:
		return
	var count := mini(int(dur * RATE), n - off)
	if count < 1:
		return

	var wave := str(d.get("wave", "sine"))
	var f0 := maxf(1.0, float(d.get("f0", 220.0)))
	var f1 := maxf(1.0, float(d.get("f1", f0)))
	var exp_slide := str(d.get("slide", "exp")) == "exp"
	var amp := float(d.get("amp", 1.0))
	var detune := float(d.get("detune", 0.0))
	var drive := maxf(0.0, float(d.get("drive", 1.0)))
	var noise_lp := clampf(float(d.get("noise_lp", 1.0)), 0.001, 1.0)

	# ADSR. If the three timed stages overrun the layer they are scaled down together rather than
	# silently truncated — a cue authored with a long release on a short body still has a shape.
	var atk := maxf(0.0, float(d.get("atk", 0.005)))
	var dec := maxf(0.0, float(d.get("dec", 0.05)))
	var rel := maxf(0.0, float(d.get("rel", 0.05)))
	var sus := clampf(float(d.get("sus", 0.5)), 0.0, 1.0)
	var stages := atk + dec + rel
	if stages > dur and stages > 0.0:
		var k := dur / stages
		atk *= k
		dec *= k
		rel *= k

	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.get("seed", 1))
	var phase := 0.0
	var phase2 := 0.0
	var nz := 0.0
	var is_noise := wave == "noise"

	for i in range(count):
		var t := float(i) / float(RATE)
		var f := (f0 * pow(f1 / f0, t / dur)) if exp_slide else lerpf(f0, f1, t / dur)

		var s := 0.0
		if is_noise:
			nz += noise_lp * (rng.randf_range(-1.0, 1.0) - nz)
			s = nz
		else:
			phase += f * TAU / float(RATE)
			s = _osc(wave, phase)
			if detune != 0.0:
				phase2 += f * (1.0 + detune) * TAU / float(RATE)
				s = (s + _osc(wave, phase2)) * 0.5

		# Soft clip. `x/(1+|x|)` is monotonic and bounded, so drive adds harmonics without ever
		# producing the hard-edged digital clip that a naive clamp() would.
		if drive != 1.0:
			var x := s * drive
			s = x / (1.0 + absf(x))

		buf[off + i] += s * amp * _env(t, dur, atk, dec, sus, rel)


static func _osc(wave: String, phase: float) -> float:
	match wave:
		"square":
			return 1.0 if sin(phase) >= 0.0 else -1.0
		"saw":
			return fposmod(phase, TAU) / PI - 1.0
		"tri":
			return 4.0 * absf(fposmod(phase, TAU) / TAU - 0.5) - 1.0
		_:
			return sin(phase)


static func _env(t: float, dur: float, atk: float, dec: float, sus: float, rel: float) -> float:
	if atk > 0.0 and t < atk:
		return t / atk
	if dec > 0.0 and t < atk + dec:
		return lerpf(1.0, sus, (t - atk) / dec)
	var rel_start := dur - rel
	if t < rel_start or rel <= 0.0:
		return sus if (atk + dec) > 0.0 else 1.0
	return sus * maxf(0.0, (dur - t) / rel)
