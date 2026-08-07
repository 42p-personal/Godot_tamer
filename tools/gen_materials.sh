#!/usr/bin/env bash
# AUTHORED MATERIAL TEXTURES — the "not high enough definition" fix, properly.
#
# ⚠️ TONAL NOISE IS NOT DETAIL. The albedo multiply added RANGE to a prop's colour, which
# stopped it reading as plastic — but a plank has plank LINES, a wall has joints, iron has
# hammer marks. Those are drawn features, not variance, and no amount of procedural noise
# produces them. This is the difference between "solid" and "painted", and painted is what
# the 2D-in-3D style is.
#
# ⚠️ FOUR TEXTURES FOR EVERY PROP IN THE GAME, because they map to MATERIAL and not to
# object. A crate, a log stack and a palisade are all sawn timber; a wall, a pillar and a
# ruin are all dressed stone. Per-object textures would be forty images and forty UV
# layouts; per-material is four and none, because they are projected rather than unwrapped
# (see the triplanar note in props3d.ts).
#
# ⚠️ AND THEY MUST BE NEAR-GREY. They are MULTIPLIED into the theme's palette, exactly like
# the noise was — so a texture with colour of its own would fight `themes.ts` for control
# of the league's identity, which is the one thing that file exists to own. Value and
# pattern only.
set -u
GEN="$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
RAW="$(cd "$(dirname "$0")/.." && pwd)/public/field/_raw"; mkdir -p "$RAW"

S="Seamless tiling texture for a 16-bit pixel-art game, viewed straight on, flat even \
ambient light with NO directional shadows and no vignette so it repeats without visible \
seams or hotspots. NEARLY DESATURATED — greys and near-greys only, no strong colour of its \
own, because it will be tinted afterwards. Clear readable surface detail at a medium \
distance, medium contrast. No objects, no text, no border, no gloss. Square image."

gen () { local o="$RAW/$1"; shift; [ -f "$o" ] && { echo "SKIP $(basename "$o")"; return; }
  echo "GEN  $(basename "$o")"
  bash "$GEN" --prompt "$*" --out "$o" >/dev/null 2>&1 && echo "  ok" || echo "  FAILED"; }

gen mat-timber.png "Sawn timber boards laid side by side, running in one direction: \
straight visible wood grain along each board, a dark seam between neighbours, occasional \
knots and small splits, saw marks across the face, worn but not rotten. $S"

gen mat-stone.png "Dressed stone ashlar: rectangular blocks in offset courses with narrow \
recessed mortar joints, each block lightly tooled with fine chisel marks, a few chipped \
corners and worn edges. Blocks clearly different tones from one another. $S"

gen mat-iron.png "Hammered wrought iron plate: a dense field of shallow overlapping hammer \
dents, faint forge scale mottling, a few rivet heads, edges slightly pitted. Dark, matte, \
no rust bloom and no polish. $S"

gen mat-rubble.png "Broken stone aggregate packed tight: angular fractured rock fragments \
of mixed sizes wedged together with fine grit filling the gaps, sharp facets catching flat \
light, no rounded pebbles and no soil. $S"

echo DONE
