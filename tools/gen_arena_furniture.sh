#!/usr/bin/env bash
# ARENA FURNITURE — five shared props, generated ONCE for the whole game.
#
# ⚠️ THESE ARE NOT PER-LEAGUE, AND THAT IS THE SAVING. Barrels and ore piles belong to a
# league because they are its trade; a wall, a pillar, a gate and a dais are the ARENA
# itself, and an arena is dressed stone everywhere on the ladder. So one grey set is
# generated once and each league re-tints it — `PropPalette` in 3D, and in 2D they read as
# the stonework the venue is already built from. Five images total, not five per league.
set -u
GEN="$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
RAW="$(cd "$(dirname "$0")/.." && pwd)/public/field/_raw"
mkdir -p "$RAW"
PROP_STYLE="A single object viewed STRAIGHT FROM THE SIDE at eye level, as in a 16-bit \
side-view pixel-art game — NOT from above, NOT isometric or three-quarter. The object rests \
on flat ground and its base sits exactly on the bottom edge of the image, no gap beneath and \
no ground drawn. Chunky readable pixel-art silhouette, soft ambient light, NEUTRAL PALE GREY \
DRESSED STONE so it can be re-tinted per league. Plain flat solid bright green background \
(#00FF00) filling every pixel around the object. No shadow, no scenery, no text, no border."
gen () { local out="$RAW/$1"; shift
  if [ -f "$out" ]; then echo "SKIP $(basename "$out")"; return; fi
  echo "GEN  $(basename "$out")"
  bash "$GEN" --prompt "$*" --out "$out" >/dev/null 2>&1 && echo "  ok" || echo "  FAILED"
}
gen prop-wall.png "A long low arena rampart of dressed stone blocks running left to right, \
about waist high, with a flat capping course along the top and visible courses of masonry. \
Much wider than it is tall. $PROP_STYLE"
gen prop-pillar.png "A single freestanding stone pillar on a square base with a moulded \
capital, standing about twice the height of its width, slightly weathered. $PROP_STYLE"
gen prop-gate.png "A heavy stone arched gateway block: two thick piers carrying a round arch \
with a keystone, the opening dark. Roughly as wide as it is tall. $PROP_STYLE"
gen prop-dais.png "A low stepped stone platform of three shallow tiers, square in plan, with \
a flat top surface. Much wider than it is tall. $PROP_STYLE"
gen prop-obelisk.png "A tall slender four-sided stone obelisk tapering to a pyramid tip, on a \
small stepped plinth. Much taller than it is wide. $PROP_STYLE"
echo DONE
