#!/usr/bin/env bash
# SHARED ARENA SURFACES — five floors every league can stand on.
#
# ⚠️ THESE ARE NOT A LEAGUE'S GROUND, THEY ARE THE ARENA'S FLOOR, and the distinction is
# the same one that made the stone furniture shared. A league's own ground (Copper's wash
# floor, Bronze's alloy floor) says WHICH CIRCUIT you are on and there is exactly one per
# theme. These say what THIS CUP's floor is laid with, so two cups on the same circuit can
# be a sand pit and a flagged court without either stopping being Bronze — the props, the
# venue stone and the lamp still carry the league.
#
# ⚠️ AND FIVE IMAGES COVER FORTY ARENAS. The alternative is a bespoke ground per cup, which
# is ~50 textures for a difference a player reads as "still the Gold circuit". Variety that
# costs one image per LEAGUE is worth drawing; variety that costs one per CUP is not.
#
# ⚠️ NEUTRAL AND QUIET ON PURPOSE. House ground saturation is ~0.21 and Bronze's first
# floor came back at 0.57 and blazed orange under everything standing on it. A surface that
# has to work beneath ten different palettes has to be the quietest thing in the frame —
# `proc_arena_art.py:check_ground_palette` will flag any of these that isn't.
set -u
GEN="$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
RAW="$(cd "$(dirname "$0")/.." && pwd)/public/field/_raw"
mkdir -p "$RAW"

S="Seamless tiling top-down texture for a 16-bit pixel-art game battlefield. Flat even \
ambient light with NO directional shadows and no vignette, so the tile repeats without \
visible seams or hotspots. DESATURATED, near-neutral palette, medium contrast, fine even \
grain — readable as a floor but quiet enough that pixel-art creatures and grey stone \
obstacles both stand out clearly on top of it. No objects, no creatures, no text, no \
border, no puddles, no bright accents. Square image."

gen () { local out="$RAW/$1"; shift
  if [ -f "$out" ]; then echo "SKIP $(basename "$out")"; return; fi
  echo "GEN  $(basename "$out")"
  bash "$GEN" --prompt "$*" --out "$out" >/dev/null 2>&1 \
    && echo "  ok $(stat -c%s "$out" 2>/dev/null || echo '?') bytes" || echo "  FAILED"
}

gen ground-sand.jpg "Raked arena sand: fine pale greyish-buff sand, evenly raked with \
shallow parallel drag lines, a scatter of darker grains and a few small pebbles trodden \
in. Soft loose surface, no dunes, no ripples large enough to read as terrain. $S"

gen ground-concrete.jpg "Poured concrete arena floor: broad slabs with fine expansion \
joints in a rectangular grid, a faint float-trowel swirl across each slab, hairline cracks \
and small chips at a few joints, light staining. Cool mid-grey. $S"

gen ground-timber.jpg "Timber arena decking: wide sawn planks laid in one direction with \
tight seams, visible straight grain, dark iron nail heads in pairs at regular intervals, \
scuffed and weathered to a grey-brown. Flat and even, no gaps or gloss. $S"

gen ground-flagstone.jpg "Flagstone arena paving: large irregular rectangular slabs of \
dressed grey stone fitted with thin dark mortar joints, each slab a slightly different \
tone, worn smooth in places with fine chipping at the edges. $S"

gen ground-packedearth.jpg "Packed earth arena floor: hard-trodden dry brown-grey soil, \
compacted smooth with a fine dust bloom over it, faint drag marks and a scatter of small \
stones pressed flush into the surface. No grass, no cracks large enough to read as terrain. $S"

echo DONE
