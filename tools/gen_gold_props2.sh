#!/usr/bin/env bash
# GOLD, SECOND PASS — four more kinds, because one prop cannot carry six boards.
#
# ⚠️ THE FIRST GOLD PASS SHIPPED SIX GROUNDS BUILT FROM ONE OBJECT, and they read as one
# ground six times. The arrangements were genuinely different — a parterre, a bower, three
# terraces, a knot, an axis, four corners — and NONE of that was visible, because every
# piece on every board was the same 12 x 2.6 green bar with the same small pale urn beside
# it. Layout variety is invisible when the vocabulary is a single word.
#
# ⚠️ COMPARE THE LEAGUES THAT WORKED. Bronze draws on wall, ruinedwall, brokenpillar and
# pillar; Iron on gate, dais, wall and pillar. Four kinds each, in two silhouette classes
# (long-and-low, tall-and-upright), and their boards are told apart at a glance. Silver and
# Gold were each given ONE mass prop plus one accent, which is half a vocabulary.
#
# ⚠️ AND A GARDEN IS THE EASIEST PLACE IN THE GAME TO FIX THAT, because a real pleasance is
# full of different things: clipped hedges, standard topiary, an arbour you walk through, a
# low flowering bed, a basin. Four new kinds spanning three silhouette classes —
#   PIERCED   arbour      (you see and shoot THROUGH it, like Silver's colonnade)
#   LOW       flowerbed   (you shoot clean over it; the only sub-metre cover Gold has)
#   ROUND     fountain    (the one non-rectangular footprint in the whole library)
#   UPRIGHT   topiary     (a vertical, so a board is not all horizontals)
# — plus `vinewall`, which has existed since Tin and belongs here more than it belongs there.
set -u
GEN="$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
RAW="$(cd "$(dirname "$0")/.." && pwd)/public/field/_raw"; mkdir -p "$RAW"

S="A single object viewed STRAIGHT FROM THE SIDE at eye level, 16-bit side-view pixel-art \
game — NOT from above or isometric. It rests on flat ground with its base exactly on the \
bottom edge, no gap beneath and no ground drawn. Chunky readable silhouette, soft ambient \
light, muted palette. Plain flat solid bright magenta (#FF00FF) background filling every \
pixel around it. No shadow, no text, no border."

gen () { local o="$RAW/$1"; shift; [ -f "$o" ] && { echo "SKIP $(basename "$o")"; return; }
  echo "GEN  $(basename "$o")"
  bash "$GEN" --prompt "$*" --out "$o" >/dev/null 2>&1 && echo "  ok" || echo "  FAILED"; }

gen prop-topiary.png "A single formal topiary standard in a low square stone box: a clean \
bare stem rising from clipped soil to a tight ball of dark clipped yew at the top, and a \
second smaller ball above it. Tall and narrow — clearly much taller than it is wide. $S"

gen prop-arbour.png "A garden arbour: a pale timber pergola of two upright posts and a \
curved arch beam, smothered in climbing green foliage over the top and down both posts, \
with the OPENING UNDER THE ARCH COMPLETELY EMPTY so the magenta background shows straight \
through the gap. About as wide as it is tall. $S"

gen prop-flowerbed.png "A long low formal flower bed edged with a single course of pale \
cut stone: dark soil inside packed with small low flowering plants in muted whites, dusty \
pinks and pale yellows, none of them taller than the stone edging by much. Very low and \
very wide — at most one fifth as tall as it is wide. $S"

gen prop-fountain.png "A round formal garden fountain: a wide shallow circular stone basin \
on a stepped plinth, a fluted pedestal rising from the middle with a small upper dish, and \
a low spill of water running over its rim into the basin. Wider than tall, symmetrical. $S"

echo DONE
