#!/usr/bin/env bash
# Generate the five arena-dressing textures for the top-down 3D battlefield rebuild.
# Writes raw generations to monster-tamer/assets/arena/_raw/, then this script's
# caller (or you, by hand) post-processes them into monster-tamer/assets/arena/.
#
# ⚠️ STRICTLY SEQUENTIAL. gen.sh finds its output by diffing codex session files
# before/after the run; running two generations concurrently steals each other's
# images. Never background these, never run them in parallel.
#
# Usage: bash tools/gen_arena_dressing.sh
set -euo pipefail

GEN="$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
OUT="G:/p42.uk/Monster-Tamer/monster-tamer/assets/arena/_raw"
mkdir -p "$OUT"

TILE_WRAP="Seamless tiling game texture, flat even ambient lighting with NO directional shadows, no vignette and no hotspots so the tile repeats invisibly. Muted natural palette, medium contrast, fine readable grain — dressing that stays quiet so brightly coloured competitors read clearly against it. No creatures, no people in the foreground, no text, no lettering, no logos, no border. Square image."
CUTOUT_WRAP="A single object centred on a plain solid pure white background, viewed straight-on at eye level, painterly game-art illustration, soft even lighting, no cast shadow, no text, no lettering, no logo, no border. Square image."

gen() {
  local name="$1" prompt="$2"
  echo "=== generating $name ==="
  "$GEN" --prompt "$prompt" --out "$OUT/$name.png" --timeout-sec 300
}

gen "wall-timber" "Seamless tiling texture of a stout timber arena barrier wall, horizontal wooden planks with iron banding, viewed flat-on. $TILE_WRAP"
gen "wall-stone" "Seamless tiling texture of a pale dressed-stone arena barrier wall, large rectangular blocks, viewed flat-on. $TILE_WRAP"
gen "stands-crowd" "Seamless HORIZONTALLY-tiling texture of a packed arena crowd in tiered seating, seen from a distance and slightly above, small indistinct figures, warm muted clothing. Must tile left-to-right without a visible seam. No individual faces, no text. $TILE_WRAP"
gen "banner-guild" "A single hanging vertical cloth guild banner with a simple geometric emblem, plain white background, no text or lettering. $CUTOUT_WRAP"
gen "barrel-wood" "Seamless tiling texture of wooden barrel staves with iron hoops, for wrapping onto a cylinder, vertical planks, tiles horizontally. $TILE_WRAP"

echo "done — raw files in $OUT"
