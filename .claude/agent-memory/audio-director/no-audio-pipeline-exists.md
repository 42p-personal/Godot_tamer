---
name: no-audio-pipeline-exists
description: No audio generation/sourcing pipeline exists in this repo, unlike the working image pipeline — do not assume one when scoping audio work
metadata:
  type: project
---

As of 2026-08-04, this repo has **zero audio infrastructure**: no assets, no engine wiring,
no generation tool. `docs/ART_PIPELINE.md` documents two live image-generation routes (OpenAI
API and a `codex` CLI riding the ChatGPT Plus subscription) plus a code-drawn fallback
(`pixelRig.ts`) — **none of this produces audio**, and nothing analogous exists for sound.

**Why this matters:** it would be easy to assume an audio-gen path exists by analogy with the
art pipeline (the project has a working pattern for "AI generates the asset via a CLI tool").
It does not, and this has not even been investigated — see `docs/AUDIO_DIRECTION.md` §8
"Route C" for the explicit flag that this is unverified, not a known gap.

**How to apply:** the realistic near-term route is CC0/CC-BY sourced libraries (Kenney.nl —
stylistically closest to this game's clean sport-not-war register, CC0 no-attribution;
Sonniss GDC free yearly bundles; Freesound.org for one-offs, needs per-item license
curation) assembled against the taxonomy in `AUDIO_DIRECTION.md` §3, not found pre-made — no
library ships this game's specific invented vocabulary (five-channel outcome taxonomy,
grouped status stings, the specific crowd reaction states). Godot's built-in
`AudioStreamGenerator` is a viable fallback for the simplest mechanical sounds (generic hit
thump, UI click) if library search comes up short, but cannot fake a convincing crowd —
crowd needs real recorded/sampled material. Music is the one category most likely to need a
composer collaborator rather than a sourced library, given the bespoke per-league adaptive
system this game's design calls for. If a technical-director wants to explore an AI
audio-gen route (Route C), that is unscoped work, not a known capability — check before
planning against it.
