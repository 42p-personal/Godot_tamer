#!/usr/bin/env bash
# SHARED SCENERY — greenery every league can stand around its ground.
#
# ⚠️ NOT A LEAGUE'S TRADE AND NOT THE ARENA'S MASONRY — A THIRD CATEGORY. Barrels and ore
# piles say which CIRCUIT you are on; walls and gateways say it is an arena. A tree says
# neither: it is the same tree at Wood and at Apex, which is exactly why it can be shared
# by all forty boards from one image apiece. Two sprites for the whole game.
#
# ⚠️ AND IT EARNS ITS KEEP ORNAMENTALLY, OFF THE PITCH. The bottom leagues are MEANT to be
# fairly empty — a beginner ground with a busy floor is a lie about the difficulty — but
# empty and bare are different things. Scenery in the trackway ring dresses the frame
# without putting one more thing in the fight.
#
# ⚠️ NEUTRAL GREEN, NOT A LEAGUE TINT. The furniture is generated pale so it can be
# re-tinted per league; greenery must NOT be, or Tin grows blue-grey trees. Colour is the
# one thing about a tree that is the same everywhere.
set -u
GEN="$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
RAW="$(cd "$(dirname "$0")/.." && pwd)/public/field/_raw"; mkdir -p "$RAW"

S="A single object viewed STRAIGHT FROM THE SIDE at eye level, 16-bit side-view pixel-art \
game — NOT from above or isometric. It rests on flat ground with its base exactly on the \
bottom edge, no gap beneath and no ground drawn. Chunky readable silhouette, soft ambient \
light, muted natural greens with a little variation, nothing glossy or neon. Plain flat \
solid bright magenta (#FF00FF) background filling every pixel around it. No shadow, no \
text, no border."

gen () { local o="$RAW/$1"; shift; [ -f "$o" ] && { echo "SKIP $(basename "$o")"; return; }
  echo "GEN  $(basename "$o")"
  bash "$GEN" --prompt "$*" --out "$o" >/dev/null 2>&1 && echo "  ok" || echo "  FAILED"; }

gen prop-tree.png "A single broadleaf tree: a stout straight trunk with visible bark \
texture branching into one full rounded canopy of clumped leaves, a few gaps in the \
foliage so it does not read as a solid blob. Clearly taller than it is wide. $S"

gen prop-bush.png "A low dense shrub: a rounded clump of small leaves close to the \
ground, slightly wider than tall, with a few twigs showing at the base and an uneven \
top edge. No flowers, no berries, no pot. $S"

echo DONE
