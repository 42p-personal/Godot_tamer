#!/usr/bin/env bash
# Copper league arena art — 2 ground tiles + 5 props.
#
# ⚠️ COPPER IS THE TIER MATERIAL, same rule Wood established. Wood was timber and
# boards; Copper is ORE AND SMELTING — blue-green malachite, raw ingots, crucibles,
# slag. The ladder is Wood → Copper → Tin → Bronze → Iron → Silver → Gold, and a
# player should be able to name the league from a still frame of the ground.
#
# ⚠️ SAME CAMERA AS THE MONSTERS. Side-on at eye level, base on the bottom edge —
# see gen_wood_arena.sh for why (the battle sprites are drawn that way, and a prop
# from a top-down three-quarter view puts two cameras in one picture). And
# `arenas.test.ts` now checks the RESULT: a prop must be able to cover the footprint
# it is given and must not tower over a 3.4-unit monster.
#
# Usage: bash tools/gen_copper_arena.sh
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

# ── grounds ─────────────────────────────────────────────────────────────────
gen ground-washfloor.png "The wet stone floor of an ore-washing yard: grey flagstones and \
packed wet gravel, shallow rivulets of milky water, streaks and crusts of blue-green copper \
staining in the cracks, scattered crushed ore grit. $GROUND_STYLE"

gen ground-smeltyard.png "The floor of a copper smelting yard: dark soot-blackened packed \
earth and cinders, scattered charcoal, glittering flecks of copper dust and small chips of \
green slag. $GROUND_STYLE"

# ── props — ore, metal and smelting ─────────────────────────────────────────
gen prop-orepile.png "A rough heap of raw copper ore chunks: angular rocks with vivid \
blue-green malachite and azurite crusts over dull grey stone, piled into a low mound wider \
than it is tall. $PROP_STYLE"

gen prop-ingots.png "A neat stack of raw copper ingots: rough-cast reddish-orange metal bars \
stacked in three tidy rows like bricks, dull oxidised sheen with faint green patina at the \
edges. Wider than it is tall. $PROP_STYLE"

gen prop-crucible.png "A large squat smelting crucible: a thick blackened clay-and-iron pot \
sitting in a heavy riveted metal cradle, its rim crusted with dried copper slag, a dull \
red-orange glow inside. Roughly as tall as it is wide. $PROP_STYLE"

gen prop-slagheap.png "A low mound of cooled smelting slag: glassy black and dark green \
clinker lumps with a faint iridescent copper sheen, heaped into a rough pile wider than it \
is tall. $PROP_STYLE"

gen prop-sluice.png "A long ore-washing sluice: an open wooden channel on low trestle legs \
running left to right across the image, lined with copper-stained boards and a few riffle \
bars, a trickle of milky water in the bottom. Much wider than it is tall. $PROP_STYLE"

echo "DONE"
