#!/usr/bin/env bash
# Tin league arena art — 2 ground tiles + 4 props.
#
# ⚠️ TIN IS THE TIER MATERIAL, same rule as Wood (timber) and Copper (ore/smelt).
# Tin is won from STREAM WORKS, not deep mines: gravel washed in leats and pools,
# then blown into pale silvery-white metal. That gives it a palette Copper cannot
# have — cold grey water, pale gravel, white metal — where Copper is fire, soot and
# green patina. The player should be able to tell the two apart with the sound off.
#
# ⚠️ SAME CAMERA AS THE MONSTERS: side-on at eye level, base on the bottom edge.
# `arenas.test.ts` checks the consequence — a prop must cover the footprint it is
# given and must not tower over a 3.4-unit monster.
set -u
GEN="$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
RAW="$(cd "$(dirname "$0")/.." && pwd)/public/field/_raw"
mkdir -p "$RAW"

GROUND_STYLE="Seamless tiling top-down texture for a 16-bit pixel-art game battlefield. \
Flat even ambient light with NO directional shadows and no vignette, so the tile repeats \
without visible seams or hotspots. Muted palette, medium contrast, fine grain — readable as \
ground but quiet enough that pixel-art creatures stand out clearly on top of it. No objects, \
no creatures, no text, no border. Square image."

PROP_STYLE="A single object viewed STRAIGHT FROM THE SIDE at eye level, as in a 16-bit \
side-view pixel-art game — NOT from above, NOT a top-down, isometric or three-quarter view. \
The object rests on flat ground and its base sits exactly on the bottom edge of the image, \
with no gap beneath it and no ground, floor or grass drawn. Chunky readable pixel-art \
silhouette that still reads at about 40 pixels tall, soft ambient light. Plain flat solid \
bright green background (#00FF00) filling every pixel around the object. No shadow, no \
scenery, no text, no border."

gen () { local out="$RAW/$1"; shift
  if [ -f "$out" ]; then echo "SKIP $(basename "$out")"; return; fi
  echo "GEN  $(basename "$out")"
  bash "$GEN" --prompt "$*" --out "$out" >/dev/null 2>&1 \
    && echo "  ok $(stat -c%s "$out" 2>/dev/null || echo '?') bytes" || echo "  FAILED"
}

gen ground-streamworks.png "The floor of a tin streamworks: pale wet gravel and rounded \
pebbles in cold grey-brown silt, shallow braided runnels of clear water, patches of dark \
waterlogged sand. Cool desaturated palette. $GROUND_STYLE"

gen ground-blowinghouse.png "The floor of a tin blowing house: pale grey ash and crushed \
white quartz grit over swept stone, scattered flecks of bright silvery tin, faint charcoal \
smears. Cool pale palette. $GROUND_STYLE"

gen prop-leat.png "A long wooden launder — an open water channel on low trestles running \
left to right across the image, dark wet planks, clear water running along it, pale silt \
crusted on the rim. Much wider than it is tall. $PROP_STYLE"

gen prop-gravelbar.png "A long low bar of washed river gravel and rounded pale pebbles, \
heaped into a shallow ridge, damp and cold-toned. Much wider than it is tall. $PROP_STYLE"

gen prop-tinblocks.png "A stack of cast tin ingots: pale silvery-white metal blocks with a \
dull matte sheen and slightly rounded cast edges, stacked in two tidy rows. Wider than it is \
tall. $PROP_STYLE"

gen prop-blowingfurnace.png "A small stone blowing furnace: a squat drystone chimney stack \
about waist high with a dark arched opening at the base, a leather bellows nozzle entering \
one side, pale ash spilling from the mouth. Roughly as tall as it is wide. $PROP_STYLE"

echo "DONE"
