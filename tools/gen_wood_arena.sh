#!/usr/bin/env bash
# Wood league arena art — 2 ground tiles + 4 props.
#
# ⚠️ "WOOD" IS THE LEAGUE'S TIER MATERIAL, NOT A FARMYARD. The first pass read the
# name as a rustic setting and produced a mud paddock with a STRAW bale in it —
# straw is not wood. Every prop here is a WOODEN object, and one of the two grounds
# is literally boards, so the league reads as its own material at a glance. The tier
# runs Wood → Copper → Tin → Bronze → Iron → Silver → Gold; each league's arenas
# should look like the thing it is named after.
#
# ⚠️ THE CAMERA MUST MATCH THE MONSTERS, and the first pass got this wrong too. The
# battle sprites are drawn SIDE-ON at eye level, standing on a flat groundline
# (public/battle/*-idle.png). Props drawn "from a slight top-down three-quarter
# angle" are a different camera: put the two together and you are looking down at
# the crate and level at the gorilla beside it. Everything below is specified at the
# sprites' camera instead.
#
# ⚠️ AND THE PROP MUST SIT ON ITS OWN GROUNDLINE. The renderer pins each sprite's
# BOTTOM edge to the front of the obstacle's footprint, so any empty space below the
# object floats it, and any ground drawn under it double-draws the arena floor.
#
# ⚠️ ONE SHARED STYLE WRAPPER PER KIND, appended verbatim to every subject —
# docs/ART_PIPELINE.md: "Consistency across a set comes from the wrapper being
# identical, not from the subject descriptions."
#
# Usage: bash tools/gen_wood_arena.sh   (≈1–3 min per asset, run in background)
set -u
GEN="$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
OUT="$(cd "$(dirname "$0")/.." && pwd)/public/field"
RAW="$OUT/_raw"
mkdir -p "$RAW"

GROUND_STYLE="Seamless tiling top-down texture for a 16-bit pixel-art game battlefield. \
Flat even ambient light with NO directional shadows and no vignette, so the tile repeats \
without visible seams or hotspots. Muted natural palette, medium contrast, fine grain — \
readable as ground but quiet enough that pixel-art creatures stand out clearly on top of it. \
No objects, no creatures, no text, no border. Square image."

# ⚠️ "SIDE ON, AT EYE LEVEL" and "resting on flat ground" are the load-bearing phrases.
PROP_STYLE="A single object viewed STRAIGHT FROM THE SIDE at eye level, as in a 16-bit \
side-view pixel-art game — NOT from above, NOT a top-down or isometric view. The object \
rests on flat ground and its base sits exactly on the bottom edge of the image, with no gap \
beneath it and no ground, floor or grass drawn. Chunky readable pixel-art silhouette that \
still reads at about 40 pixels tall, warm natural colours, soft ambient light. Plain flat \
solid bright green background (#00FF00) filling every pixel around the object. No shadow, no \
scenery, no text, no border."

gen () { # gen <outfile> <prompt>
  local out="$RAW/$1"; shift
  if [ -f "$out" ]; then echo "SKIP $(basename "$out") (exists)"; return; fi
  echo "GEN  $out"
  bash "$GEN" --prompt "$*" --out "$out" >/dev/null 2>&1 \
    && echo "  ok $(stat -c%s "$out" 2>/dev/null || echo '?') bytes" \
    || echo "  FAILED $out"
}

# ── ground 1: the boarded ring ──────────────────────────────────────────────
gen ground-plankyard.png "Weathered wooden floorboards of an old timber fighting ring: wide \
grey-brown planks laid in one direction, visible grain and knots, dark gaps between boards, \
a few iron nail heads. $GROUND_STYLE"

# ── ground 2: the timber yard floor ─────────────────────────────────────────
gen ground-sawdust.png "The floor of a working timber yard: pale sawdust and wood chips over \
packed dirt, scattered bark fragments and offcuts, faint drag marks. $GROUND_STYLE"

# ── props — every one of them WOODEN ────────────────────────────────────────
gen prop-crates.png "A stack of three sturdy wooden shipping crates, plank sides with iron \
corner brackets, stacked two on the bottom and one on top. $PROP_STYLE"

gen prop-barrel.png "A single large wooden barrel standing upright on its end, curved oak \
staves bound with three iron hoops, flat lid on top. $PROP_STYLE"

gen prop-logstack.png "A long low stack of freshly cut logs lying horizontally, pale round \
cut ends facing the viewer, rough brown bark, stacked three logs wide and two rows high. \
$PROP_STYLE"

gen prop-stump.png "A large tree stump used as a chopping block, thick dark gnarled bark down \
the sides, flat pale cut top with growth rings, an axe buried in the top. $PROP_STYLE"

echo "DONE — raws in $RAW"
