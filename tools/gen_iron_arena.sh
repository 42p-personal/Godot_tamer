#!/usr/bin/env bash
# IRON LEAGUE — two grounds, and no new props.
#
# ⚠️ TWO IMAGES FOR FOUR ARENAS, AND THAT IS THE WHOLE ART COST OF A LEAGUE NOW. Iron's
# boards are BUILT PLACES — wall runs, colonnades, ruins — and every one of those is shared
# dressed stone already drawn and re-tinted by `venue.masonry`. What a new league still owes
# is its GROUND, because that is what a player names a circuit from in a still frame, and
# its LAMP. Four distinct floors come from two new grounds plus two shared surfaces.
#
# ⚠️ AND IRON MUST NOT BE COPPER AGAIN. Copper's smelt yard is the game's darkest floor at
# luminance 42 and reads warm-orange; Iron is the FORGE, which is hotter but blacker — iron
# scale, hammer soot, clinker. The separation has to be in the ground because the two
# leagues share a 3v3 board size with Bronze and cannot be told apart by scale.
set -u
GEN="$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
RAW="$(cd "$(dirname "$0")/.." && pwd)/public/field/_raw"; mkdir -p "$RAW"

S="Seamless tiling top-down texture for a 16-bit pixel-art game battlefield. Flat even \
ambient light with NO directional shadows and no vignette, so the tile repeats without \
visible seams or hotspots. Muted, low-saturation palette — no bright colour anywhere — \
medium contrast, fine even grain, readable as ground but quiet enough that pixel-art \
creatures and pale grey stone both stand out clearly on top of it. No objects, no \
creatures, no text, no border. Square image."

gen () { local out="$RAW/$1"; shift
  if [ -f "$out" ]; then echo "SKIP $(basename "$out")"; return; fi
  echo "GEN  $(basename "$out")"
  bash "$GEN" --prompt "$*" --out "$out" >/dev/null 2>&1 \
    && echo "  ok" || echo "  FAILED"
}

gen ground-forgefloor.png "A forge floor of hammered iron plate bedded into packed black \
scale: dark blue-grey metal worn smooth in patches, flaking rust-dark oxide at the edges, \
scattered hammer scale and fine soot trodden into the seams. Almost colourless, cold \
rather than warm. $S"

gen ground-cinderyard.png "A cinder yard of raked furnace clinker: coarse grey-black \
burnt aggregate and pale ash worked together, small fused lumps and fine grit, faint rake \
lines across it. Dry, matte and nearly colourless. $S"

echo DONE
