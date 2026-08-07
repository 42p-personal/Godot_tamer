#!/usr/bin/env bash
# Wood league — second prop wave: one redraw and three new shapes of cover.
#
# ⚠️ THE LOG STACK IS A REDRAW, AND THE REASON IS THE CAMERA. The first version drew
# the round cut ends FACE-ON while also showing the full length of the logs running
# away to the side. Those are two different viewpoints in one sprite: from the side-on
# camera the sprites use, a log's end is edge-on and all but invisible, and you read
# the log by its LENGTH and its bark. Seeing a circle and a length at once is what
# made it "not make sense in perspective". It is also the wrong read for the job —
# the obstacle is a 7-unit-wide wall running left-to-right, so the logs must lie
# along it, not point out of the screen at the viewer.
#
# ⚠️ EVERY PIECE IS STILL WOODEN — Wood is the league's tier material.
#
# Usage: bash tools/gen_wood_props2.sh
set -u
GEN="$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
RAW="$(cd "$(dirname "$0")/.." && pwd)/public/field/_raw"
mkdir -p "$RAW"

PROP_STYLE="A single object viewed STRAIGHT FROM THE SIDE at eye level, as in a 16-bit \
side-view pixel-art game — NOT from above, NOT a top-down or isometric view, and NOT a \
three-quarter view. The object rests on flat ground and its base sits exactly on the bottom \
edge of the image, with no gap beneath it and no ground, floor or grass drawn. Chunky \
readable pixel-art silhouette that still reads at about 40 pixels tall, warm natural colours, \
soft ambient light. Plain flat solid bright green background (#00FF00) filling every pixel \
around the object. No shadow, no scenery, no text, no border."

gen () { local out="$RAW/$1"; shift
  if [ -f "$out" ]; then echo "SKIP $(basename "$out")"; return; fi
  echo "GEN  $(basename "$out")"
  bash "$GEN" --prompt "$*" --out "$out" >/dev/null 2>&1 \
    && echo "  ok $(stat -c%s "$out" 2>/dev/null || echo '?') bytes" || echo "  FAILED"
}

# ⚠️ "LYING ALONG THE WIDTH", "SIDE OF THE LOGS", "no circular ends facing the viewer".
gen prop-logstack.png "A long low woodpile of felled tree trunks lying flat and LENGTHWISE \
along the width of the image, seen from the side so you look at the long bark-covered SIDES of \
the trunks running left to right, stacked two rows high. The logs run parallel to the ground \
across the whole image; no circular cut ends face the viewer. Rough brown bark, a few stubs of \
sawn branches. $PROP_STYLE"

gen prop-palisade.png "A short section of a rough wooden palisade fence: five or six thick \
upright split logs of slightly uneven height, sharpened at the top, lashed together with two \
horizontal crossbeams. Weathered grey-brown timber. $PROP_STYLE"

gen prop-cart.png "An old wooden handcart standing side-on with its two spoked wooden wheels \
facing the viewer, plank sides, handles tilted down to the ground, a few loose planks in the \
bed. Weathered brown timber with iron bands on the wheel rims. $PROP_STYLE"

gen prop-sawhorse.png "A carpenter's wooden sawhorse: a thick horizontal beam on four splayed \
legs, with a half-sawn plank resting across it. Pale rough-sawn timber, sawdust on the beam. \
$PROP_STYLE"

echo "DONE"
