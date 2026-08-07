#!/usr/bin/env bash
# THE COLONNADE — the one prop Silver actually needed.
#
# ⚠️ A BARE COLUMN CANNOT CARRY A BOARD, AND THE NUMBERS SAY SO. Silver's first five
# grounds were authored from `pillar`, `brokenpillar` and `obelisk` and measured 0.79% to
# 1.41% of board area under cover, against 3.1% to 11.2% for every other league in the
# game. A pillar is 2.56 square units; a wall run is about 29. Ten columns on a 3100-unit
# 4v4 board is a rounding error, and at the shipped 38-degree camera they read as pale
# stubs on a pale floor rather than as architecture.
#
# ⚠️ AND THE DENSITY LAW DID NOT CATCH IT, because `maxPiecesFor` counts PIECES and is
# blind to their size. It is calibrated on the 10-to-14-unit props Bronze and Iron are
# built from and says nothing useful about a 1.6-unit one.
#
# So the family keeps its idea and gains a unit of MASS: a colonnade run — a stylobate,
# six or seven columns standing on it, an architrave across the top. Wall-sized footprint,
# wall-sized presence, and you can see THROUGH it between the shafts, which is what
# separates it from Bronze's solid coursing and from Iron's single-opening gateway.
set -u
GEN="$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
RAW="$(cd "$(dirname "$0")/.." && pwd)/public/field/_raw"; mkdir -p "$RAW"

# ⚠️ MAGENTA, NOT GREEN — `proc_arena_art.py` keys both, and green floods out of the
# backdrop into anything green. Kept identical to the Tin batch so the set stays coherent.
S="A single object viewed STRAIGHT FROM THE SIDE at eye level, 16-bit side-view pixel-art \
game — NOT from above or isometric. It rests on flat ground with its base exactly on the \
bottom edge, no gap beneath and no ground drawn. Chunky readable silhouette, soft ambient \
light, muted palette. Plain flat solid bright magenta (#FF00FF) background filling every \
pixel around it. No shadow, no text, no border."

gen () { local o="$RAW/$1"; shift; [ -f "$o" ] && { echo "SKIP $(basename "$o")"; return; }
  echo "GEN  $(basename "$o")"
  bash "$GEN" --prompt "$*" --out "$o" >/dev/null 2>&1 && echo "  ok" || echo "  FAILED"; }

gen prop-colonnade.png "A short run of classical colonnade in pale dressed limestone: a \
two-step stylobate base running the full width, SEVEN plain round columns standing evenly \
spaced on it with simple bases and capitals, and a flat architrave beam laid across all \
their tops. The gaps BETWEEN the columns are open — the magenta background shows straight \
through every gap. Roughly two and a half times as wide as it is tall. $S"

gen prop-brokencolonnade.png "A ruined run of classical colonnade in pale dressed \
limestone: a cracked two-step stylobate with SEVEN column positions along it, but only \
four columns still standing — two are broken off at waist height and one is missing \
entirely, its drum lying toppled across the steps. The architrave beam survives over only \
the left half and is snapped off jaggedly. Open magenta background showing through every \
gap. Roughly two and a half times as wide as it is tall. $S"

echo DONE
