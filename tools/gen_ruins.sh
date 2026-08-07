#!/usr/bin/env bash
set -u
GEN="$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
RAW="$(cd "$(dirname "$0")/.." && pwd)/public/field/_raw"; mkdir -p "$RAW"
S="A single object viewed STRAIGHT FROM THE SIDE at eye level, 16-bit side-view pixel-art \
game — NOT from above or isometric. It rests on flat ground with its base exactly on the \
bottom edge, no gap beneath and no ground drawn. Chunky readable silhouette, soft ambient \
light, NEUTRAL PALE GREY DRESSED STONE so it can be re-tinted per league. Plain flat solid \
bright green (#00FF00) background filling every pixel around it. No shadow, no text, no border."
gen () { local o="$RAW/$1"; shift; [ -f "$o" ] && { echo "SKIP $1"; return; }
  bash "$GEN" --prompt "$*" --out "$o" >/dev/null 2>&1 && echo "ok $(basename $o)" || echo "FAILED $(basename $o)"; }
gen prop-ruinedwall.png "A ruined arena wall of dressed stone running left to right: the \
capping course broken away, a jagged gap torn through the middle, the top edge uneven where \
blocks have fallen, a few tumbled blocks resting at the foot. Much wider than tall. $S"
gen prop-brokenpillar.png "A broken stone pillar snapped off partway up, jagged fractured \
top, still on its square moulded base, with one fallen cylindrical drum lying on its side \
beside it. Slightly taller than wide. $S"
echo DONE
