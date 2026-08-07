---
name: project-audio-direction-established
description: AUDIO_DIRECTION.md was authored from scratch 2026-08-04 — the project had zero audio (no assets, no plan) before this
metadata:
  type: project
---

`docs/AUDIO_DIRECTION.md` is the first audio document this project has ever had. Written
2026-08-04 in one pass (no back-and-forth was possible — invoked as a subagent task with a
"report back" instruction, not an interactive session), covering: sonic identity ("a trade
guild's fight night — hand-struck, hide-and-timber, crowd-judged, never a battlefield"),
crowd-as-instrument (crowd FILL scales with team fame per the standing project decision,
crowd REACTIVITY is state-driven off fight events and independent of fill — these two must
never be collapsed onto one fader), combat SFX taxonomy keyed to the game's existing
five-channel `CHANNEL_COLOR` system (melee/ranged/magic/voice/support, from `fieldFx.ts`),
ability cast-tells, per-league music progression mirroring the art bible's cumulative
grandeur ladder, mix priority (information beats spectacle — kill > hard-control > crit/miss
> cast-tell > crowd stinger > steady combat SFX > ambient > music > UI), a ~24-26 sound
minimal viable set, and an honest production-route assessment (see [[no-audio-pipeline-exists]]).

**Why:** the game's core constraint — player never intervenes in a fight, only watches — means
audio isn't decoration, it's a second reading channel for information the eye misses on a
wide board with ten free-moving monsters (`docs/AUTOBATTLER_DESIGN.md`'s free-placement
rework spreads units across the full 160-wide board).

**How to apply:** treat this doc as the brief for `sound-designer` (SFX event lists),
`lead-programmer`/`gameplay-programmer` (bus/priority implementation), and any future
audio-asset sourcing. Several concrete decisions were left open and flagged for other
disciplines rather than decided unilaterally — see the doc's final "Open questions" section
(HP-threshold values, whether the frame-stream event system needs new event types for audio,
the music-presence-level choice between three stated options). Check those haven't been
silently resolved elsewhere before assuming this doc's proposals are final.
