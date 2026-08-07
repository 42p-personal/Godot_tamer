#!/usr/bin/env bash
# REGENERATING BRONZE'S GROUND (2026-08-02).
#
# ⚠️ THE ORIGINAL WAS THE LOUDEST TEXTURE IN THE GAME AND THE CHECK SAID SO FROM DAY ONE.
# 0.57 saturation against a house median of 0.18 — nearly three times as punchy as any
# other floor — and `proc_arena_art.py:check_ground_palette` flagged it on every batch for
# weeks while it shipped anyway. Against the pale masonry the arenas are now built from it
# reads as a sheet of orange with grey benches on it, and the other three Bronze boards
# look better purely because they sit on quieter ground.
#
# ⚠️ THE BRIEF IS THE SAME STORY, TOLD QUIETER. Bronze is still the alloy visibly
# happening — green copper scale and pale tin dust trodden together — but as a WORN FLOOR
# rather than as pigment. The identity was never in the saturation.
set -u
GEN="$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
RAW="$(cd "$(dirname "$0")/.." && pwd)/public/field/_raw"; mkdir -p "$RAW"
bash "$GEN" --prompt "Seamless tiling top-down texture for a 16-bit pixel-art game \
battlefield: a worn foundry floor of trodden metal dust. Muted grey-brown ground with a \
faint warm bronze cast, flecked sparingly with dull green copper scale and pale grey tin \
dust worked into it, fine grit and old scuff marks. DESATURATED and quiet — no orange, no \
gold, no bright colour anywhere; the warmth must be barely perceptible. Flat even ambient \
light with NO directional shadows and no vignette so the tile repeats without seams or \
hotspots. Medium-low contrast, fine even grain, readable as ground but quiet enough that \
pixel-art creatures and pale grey stone both stand out clearly on top of it. No objects, \
no text, no border. Square image." --out "$RAW/ground-alloyfloor.png" >/dev/null 2>&1 \
  && echo "ok" || echo "FAILED"
