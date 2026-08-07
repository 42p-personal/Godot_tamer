#!/usr/bin/env bash
# SILVER LEAGUE — two grounds, and no new props.
#
# ⚠️ SILVER IS GOLD'S TWIN IN TEAM SIZE, the same problem Iron had with Bronze. Both field
# four, so `arenaGridFor` hands both the same 28x22 target and the ladder repeats a scale
# for the second time. What separates them has to come from the other axes — and the plan
# is the one that worked for Bronze/Iron: a different SILHOUETTE FAMILY on the floor.
#   Silver — tall slender VERTICALS. Columns, broken columns, obelisks. Cover you shoot
#            PAST, standing in files and rings, echoing the colonnade the stands gain at
#            this exact rung (tier 5 is where `venue.columns` turns on).
#   Gold   — PLANTED. Hedges, vine walls, tubs. Tier 6 is where `venue.planters` turns on,
#            so the same trick works twice: the floor says what the stands just gained.
#
# ⚠️ AND SILVER MUST NOT BE TIN AGAIN. Tin is the game's other pale-and-cold circuit
# (streamworks, luminance 110, saturation 0.13). Silver is pale but WARM-neutral and much
# harder-lit — dressed limestone and bone-ash rather than wet grey stone — because two
# whitish leagues four rungs apart would collapse into one.
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

gen ground-assayfloor.png "A worn floor of pale dressed limestone slabs laid tight: warm \
off-white stone with faint grey veining, edges rounded by use, thin dark joints and a \
scatter of fine pale dust in them. Dry, chalky and almost colourless — warm-neutral \
rather than cold. $S"

gen ground-cupelhearth.png "A refining hearth floor of packed bone ash: matte chalk-white \
and pale grey powder trodden flat, faint sweeping arcs across it, a few darker sintered \
patches and specks of grey slag worked in. Powdery, soft-edged and nearly colourless. $S"

echo DONE
