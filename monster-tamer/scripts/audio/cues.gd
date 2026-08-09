extends RefCounted
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# THE CUE SHEET — designed, not sprayed.
#
# One entry per SOUND, not one per event kind: several kinds share a cue at different gains, and
# one kind (a strike) picks a different cue depending on what actually happened. The rule that
# shaped every number below:
#
#   A viewer who cannot intervene learns the fight by WATCHING it. Audio is the second read of
#   the same information, so two beats that mean different things must SOUND different, and two
#   that mean the same thing must not compete.
#
# The three contrasts that carry the most information, in order:
#   1. body hit vs CRIT vs SOAKED — the same swing with three outcomes. Different register
#      (thump / driven square / glass bell), not just different volume.
#   2. cast RESOLVING vs cast CUT — the rising tone either lands on a chord or is severed by the
#      interrupt clang mid-slide. The interrupt is the most satisfying sound in arena games
#      precisely because it is the ABSENCE of the resolution the ear was already expecting.
#   3. a death vs everything else — the only cue that goes properly sub-bass and long.
#
# Everything else is deliberately smaller than those three. See `battle_audio.gd` for the mix
# discipline that keeps it that way.
# ═══════════════════════════════════════════════════════════════════════════════════════════════

const Synth = preload("res://scripts/audio/synth.gd")


## Every cue id → its layer stack. Built once at boot and cached as streams by `battle_audio.gd`.
static func sheet() -> Dictionary:
	return {
		# ── IMPACTS ────────────────────────────────────────────────────────────────────────────
		# A body hit: low sine thump with a short noise transient on the front. Nothing clever —
		# it fires more than any other cue in the fight and must never become tiring.
		"hit_body": [
			{"wave": "sine", "f0": 190, "f1": 78, "dur": 0.17, "amp": 1.0,
				"atk": 0.001, "dec": 0.06, "sus": 0.18, "rel": 0.09},
			{"wave": "noise", "noise_lp": 0.28, "dur": 0.09, "amp": 0.55,
				"atk": 0.001, "dec": 0.03, "sus": 0.0, "rel": 0.05, "seed": 11},
		],
		# A weak hit — a chip, a tick of a multi-hit. Same family, thinner and higher, so a flurry
		# of small hits reads as a flurry rather than as five heavy blows.
		"hit_light": [
			{"wave": "sine", "f0": 260, "f1": 140, "dur": 0.10, "amp": 0.75,
				"atk": 0.001, "dec": 0.035, "sus": 0.12, "rel": 0.05},
			{"wave": "noise", "noise_lp": 0.55, "dur": 0.05, "amp": 0.3,
				"atk": 0.001, "dec": 0.02, "sus": 0.0, "rel": 0.03, "seed": 12},
		],
		# A HEAVY LANDING — the third grade of the same swing, below the body hit rather than above
		# it. Lower fundamental, longer tail, a fatter transient: it is the SAME family as
		# `hit_body`, so nobody has to learn a new sound, but it is unmistakably a bigger blow.
		#
		# ⚠️ IT EXISTS BECAUSE THE BIGGEST DAMAGE IN THE GAME WAS THE LEAST LEGIBLE BY EAR.
		# Measured over three seeded 5v5s: a basic `strike` spans 8–23 damage, while `cast_done`
		# spans 1–80 (p50 17, p90 60) and `proj_hit` 10–74. Every non-crit cast landed on the same
		# resolution chord at the same gain, and every non-crit arrow — 74 damage or 10 — fell on
		# the one absolute threshold (`dmg >= 8`) that was authored for basic attacks. So an 80
		# damage spell and a 9 damage poke made the same noise, in a game whose entire loop is
		# watching a fight you cannot intervene in.
		#
		# ⚠️ IT IS DELIBERATELY NOT THE CRIT AND NOT THE DEATH. The crit is the driven square (an
		# ORTHOGONAL fact — a roll went your way), the death owns 38 Hz alone. Heavy sits between
		# `hit_body` and `death` in register and is the only thing in that gap.
		"hit_heavy": [
			{"wave": "sine", "f0": 132, "f1": 54, "dur": 0.34, "amp": 1.0,
				"atk": 0.001, "dec": 0.11, "sus": 0.26, "rel": 0.19},
			{"wave": "saw", "f0": 96, "f1": 44, "dur": 0.24, "amp": 0.3, "drive": 1.4,
				"atk": 0.002, "dec": 0.08, "sus": 0.2, "rel": 0.13},
			{"wave": "noise", "noise_lp": 0.22, "dur": 0.15, "amp": 0.62,
				"atk": 0.001, "dec": 0.05, "sus": 0.05, "rel": 0.08, "seed": 14},
		],
		# A CRIT. Driven square over the thump: harmonics the body hit does not have, so it cuts
		# through a scrum without simply being louder than everything else.
		"hit_crit": [
			{"wave": "square", "f0": 330, "f1": 118, "dur": 0.26, "amp": 0.62, "drive": 2.4,
				"atk": 0.001, "dec": 0.09, "sus": 0.22, "rel": 0.14},
			{"wave": "sine", "f0": 145, "f1": 58, "dur": 0.32, "amp": 1.0,
				"atk": 0.001, "dec": 0.11, "sus": 0.3, "rel": 0.19},
			{"wave": "noise", "noise_lp": 0.5, "dur": 0.14, "amp": 0.7,
				"atk": 0.001, "dec": 0.05, "sus": 0.05, "rel": 0.08, "seed": 13},
		],
		# THE SOAK. Glassy and high — the hit CONNECTED but the ward ate it. Without a distinct
		# sound a viewer hears a clean strike do nothing and reads it as a bug (the same reasoning
		# that put the ◈ float on screen).
		"ward_soak": [
			{"wave": "sine", "f0": 900, "f1": 1380, "dur": 0.24, "amp": 0.5,
				"atk": 0.004, "dec": 0.08, "sus": 0.35, "rel": 0.15},
			{"wave": "tri", "f0": 1810, "f1": 2450, "dur": 0.16, "amp": 0.2,
				"atk": 0.003, "dec": 0.05, "sus": 0.2, "rel": 0.1},
		],
		# A MISS: air, no impact. Quiet by design and the first thing ducked — absence of impact is
		# the read, and a loud whiff would lie about what happened.
		"miss": [
			{"wave": "noise", "noise_lp": 0.8, "dur": 0.19, "amp": 0.32,
				"atk": 0.045, "dec": 0.06, "sus": 0.32, "rel": 0.08, "seed": 21},
		],
		# Reflected damage — a spiky metallic tick, clearly not a swing.
		"thorns": [
			{"wave": "tri", "f0": 1250, "f1": 660, "dur": 0.13, "amp": 0.5,
				"atk": 0.001, "dec": 0.04, "sus": 0.15, "rel": 0.08},
			{"wave": "noise", "noise_lp": 0.9, "dur": 0.06, "amp": 0.3,
				"atk": 0.001, "dec": 0.02, "sus": 0.0, "rel": 0.03, "seed": 22},
		],

		# ── CASTING: THE RISE, THE RESOLUTION, AND THE CUT ─────────────────────────────────────
		# The rise. A saw climbing two octaves over ~1.4s — an unfinished musical gesture the ear
		# wants resolved. It is the ONLY looping-length cue in the fight and it is tracked per
		# caster so it can be severed. `battle_audio` pitch-scales it toward the real cast time.
		"cast_rise": [
			{"wave": "saw", "f0": 165, "f1": 640, "dur": 1.4, "amp": 0.42,
				"atk": 0.14, "dec": 0.2, "sus": 0.85, "rel": 0.22, "detune": 0.008},
			{"wave": "sine", "f0": 330, "f1": 1280, "dur": 1.4, "amp": 0.18,
				"atk": 0.2, "dec": 0.2, "sus": 0.8, "rel": 0.25},
		],
		# THE RESOLUTION. Falls where the rise was climbing — the gesture completes.
		"cast_done": [
			{"wave": "sine", "f0": 660, "f1": 320, "dur": 0.46, "amp": 0.85,
				"atk": 0.002, "dec": 0.14, "sus": 0.3, "rel": 0.28},
			{"wave": "square", "f0": 330, "f1": 160, "dur": 0.34, "amp": 0.34, "drive": 1.7,
				"atk": 0.002, "dec": 0.1, "sus": 0.22, "rel": 0.2},
			{"wave": "noise", "noise_lp": 0.35, "dur": 0.1, "amp": 0.45,
				"atk": 0.001, "dec": 0.04, "sus": 0.0, "rel": 0.05, "seed": 31},
		],
		# THE CUT. A metallic clang plunging an octave and a half in 0.22s — it arrives as the rise
		# is still climbing and the rise stops dead underneath it. Never let this get quiet.
		"interrupt": [
			{"wave": "noise", "noise_lp": 1.0, "dur": 0.12, "amp": 1.0,
				"atk": 0.0005, "dec": 0.04, "sus": 0.1, "rel": 0.06, "seed": 41},
			{"wave": "square", "f0": 1420, "f1": 380, "dur": 0.24, "amp": 0.9, "drive": 2.6,
				"atk": 0.0005, "dec": 0.07, "sus": 0.2, "rel": 0.15},
			{"wave": "sine", "f0": 700, "f1": 185, "dur": 0.32, "amp": 0.6,
				"atk": 0.001, "dec": 0.1, "sus": 0.25, "rel": 0.2},
		],
		# Hard control eating a cast — a shatter, not a clang. The feed already teaches the viewer
		# that "kicked" and "stunned out of it" are different things; this is the same lesson by ear.
		"status_break": [
			{"wave": "noise", "noise_lp": 1.0, "dur": 0.36, "amp": 0.8,
				"atk": 0.001, "dec": 0.13, "sus": 0.22, "rel": 0.2, "seed": 42},
			{"wave": "square", "f0": 2250, "f1": 880, "dur": 0.2, "amp": 0.42, "drive": 1.9,
				"atk": 0.001, "dec": 0.06, "sus": 0.15, "rel": 0.12},
		],

		# ── THE BIG BEATS ──────────────────────────────────────────────────────────────────────
		# A death. The only cue that goes to 38 Hz and runs near a second. Nothing else in the mix
		# occupies that register, so it lands even under a full-team scrum.
		"death": [
			{"wave": "sine", "f0": 170, "f1": 38, "dur": 0.95, "amp": 1.0,
				"atk": 0.008, "dec": 0.3, "sus": 0.4, "rel": 0.5},
			{"wave": "saw", "f0": 120, "f1": 30, "dur": 0.8, "amp": 0.36, "drive": 1.5,
				"atk": 0.01, "dec": 0.25, "sus": 0.3, "rel": 0.42},
			{"wave": "noise", "noise_lp": 0.16, "dur": 0.7, "amp": 0.5,
				"atk": 0.02, "dec": 0.2, "sus": 0.3, "rel": 0.4, "seed": 51},
		],
		# An AoE burst. Sub boom plus a dark noise wash — the wide sound for the wide event.
		"aoe": [
			{"wave": "sine", "f0": 96, "f1": 42, "dur": 0.8, "amp": 1.0,
				"atk": 0.004, "dec": 0.25, "sus": 0.42, "rel": 0.35},
			{"wave": "noise", "noise_lp": 0.13, "dur": 0.62, "amp": 0.8,
				"atk": 0.006, "dec": 0.2, "sus": 0.35, "rel": 0.34, "seed": 52},
			{"wave": "saw", "f0": 72, "f1": 30, "dur": 0.5, "amp": 0.34, "drive": 1.5,
				"atk": 0.004, "dec": 0.16, "sus": 0.25, "rel": 0.25},
		],
		# A taunt. Brassy, detuned, RISING — a challenge, and the one cue that reads as a voice.
		"taunt": [
			{"wave": "saw", "f0": 186, "f1": 250, "dur": 0.55, "amp": 0.7, "drive": 1.9,
				"detune": 0.012, "atk": 0.05, "dec": 0.12, "sus": 0.65, "rel": 0.18},
			{"wave": "square", "f0": 93, "f1": 125, "dur": 0.55, "amp": 0.3, "drive": 1.3,
				"atk": 0.06, "dec": 0.12, "sus": 0.6, "rel": 0.2},
		],

		# ── THE SUPPORT LAYER ──────────────────────────────────────────────────────────────────
		# A heal. Rising, consonant, soft — the only warm sound in the sheet, because a heal is the
		# moment a kill window CLOSED and that deserves its own colour.
		"heal": [
			{"wave": "sine", "f0": 523, "f1": 784, "dur": 0.5, "amp": 0.55,
				"atk": 0.05, "dec": 0.15, "sus": 0.5, "rel": 0.28},
			{"wave": "sine", "f0": 1046, "f1": 1568, "dur": 0.44, "amp": 0.16,
				"atk": 0.07, "dec": 0.14, "sus": 0.4, "rel": 0.22},
		],
		# A cleanse: a three-note rise, built from delayed layers. Related to the heal by interval,
		# distinct from it by being an arpeggio rather than a swell.
		"cleanse": [
			{"wave": "sine", "f0": 660, "dur": 0.22, "amp": 0.4,
				"atk": 0.005, "dec": 0.07, "sus": 0.3, "rel": 0.12},
			{"wave": "sine", "f0": 880, "dur": 0.22, "amp": 0.4, "delay": 0.09,
				"atk": 0.005, "dec": 0.07, "sus": 0.3, "rel": 0.12},
			{"wave": "sine", "f0": 1320, "dur": 0.34, "amp": 0.38, "delay": 0.18,
				"atk": 0.005, "dec": 0.1, "sus": 0.3, "rel": 0.2},
		],
		# A buff — a major triad struck fast. Bright, short, unmistakably NOT damage.
		"buff": [
			{"wave": "tri", "f0": 523, "dur": 0.26, "amp": 0.42,
				"atk": 0.004, "dec": 0.08, "sus": 0.3, "rel": 0.15},
			{"wave": "tri", "f0": 659, "dur": 0.26, "amp": 0.38, "delay": 0.05,
				"atk": 0.004, "dec": 0.08, "sus": 0.3, "rel": 0.15},
			{"wave": "tri", "f0": 784, "dur": 0.3, "amp": 0.36, "delay": 0.1,
				"atk": 0.004, "dec": 0.09, "sus": 0.3, "rel": 0.18},
		],
		# A debuff — the buff's triad inverted: minor, FALLING, and slightly sour. Sharing the
		# shape with `buff` is the point; the direction is what tells the viewer which it was.
		"debuff": [
			{"wave": "tri", "f0": 392, "dur": 0.26, "amp": 0.4, "detune": 0.02,
				"atk": 0.004, "dec": 0.08, "sus": 0.3, "rel": 0.15},
			{"wave": "tri", "f0": 311, "dur": 0.26, "amp": 0.36, "delay": 0.05, "detune": 0.02,
				"atk": 0.004, "dec": 0.08, "sus": 0.3, "rel": 0.15},
			{"wave": "tri", "f0": 233, "dur": 0.32, "amp": 0.36, "delay": 0.1, "detune": 0.02,
				"atk": 0.004, "dec": 0.1, "sus": 0.3, "rel": 0.2},
		],
		# A status landing: a small detuned sour blip. Deliberately unpleasant and deliberately
		# small — 15 statuses share it, separated by pitch (see `battle_audio._status_pitch`).
		"status": [
			{"wave": "saw", "f0": 300, "f1": 228, "dur": 0.3, "amp": 0.45, "detune": 0.055,
				"atk": 0.006, "dec": 0.1, "sus": 0.3, "rel": 0.18},
			{"wave": "sine", "f0": 150, "f1": 114, "dur": 0.3, "amp": 0.26,
				"atk": 0.008, "dec": 0.1, "sus": 0.3, "rel": 0.18},
		],
		# Attrition. A dull woodblock tick, ~70ms. DoTs must be AUDIBLE — a unit dying to poison
		# with no sound is as unreadable as one dying with no float — without competing with a hit.
		"tick": [
			{"wave": "tri", "f0": 430, "f1": 380, "dur": 0.07, "amp": 0.25,
				"atk": 0.001, "dec": 0.025, "sus": 0.1, "rel": 0.04},
		],
		# A projectile leaving the hand. The whip that makes a visible miss make sense: you hear
		# the shot go out and then hear nothing land.
		"proj_launch": [
			{"wave": "noise", "noise_lp": 0.6, "dur": 0.14, "amp": 0.38,
				"atk": 0.004, "dec": 0.05, "sus": 0.2, "rel": 0.07, "seed": 61},
			{"wave": "saw", "f0": 880, "f1": 1650, "dur": 0.12, "amp": 0.18,
				"atk": 0.004, "dec": 0.04, "sus": 0.2, "rel": 0.06},
		],

		# ── THE CROWD ──────────────────────────────────────────────────────────────────────────
		# The bed: a 2.4s loop of very dark noise, sitting under everything at low gain. It is the
		# room tone that makes the arena feel occupied; the swell rides on top of it.
		"crowd_bed": [
			{"wave": "noise", "noise_lp": 0.055, "dur": 2.4, "amp": 0.9,
				"atk": 0.0, "dec": 0.0, "sus": 1.0, "rel": 0.0, "seed": 71},
			{"wave": "noise", "noise_lp": 0.02, "dur": 2.4, "amp": 0.5,
				"atk": 0.0, "dec": 0.0, "sus": 1.0, "rel": 0.0, "seed": 72},
		],
		# The roar. Fires on the beats the crowd already reacts to VISUALLY (`_crowd_react`), so
		# the seats and the sound swell together rather than as two unrelated systems.
		"crowd_roar": [
			{"wave": "noise", "noise_lp": 0.09, "dur": 1.7, "amp": 0.9,
				"atk": 0.14, "dec": 0.4, "sus": 0.6, "rel": 0.85, "seed": 73},
			{"wave": "noise", "noise_lp": 0.34, "dur": 1.5, "amp": 0.34,
				"atk": 0.2, "dec": 0.35, "sus": 0.5, "rel": 0.7, "seed": 74},
		],
	}
