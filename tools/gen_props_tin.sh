#!/usr/bin/env bash
# EXPANDING THE PROP VOCABULARY (2026-08-02).
#
# ⚠️ THE HEAP IS BEING REPLACED, NOT REPAIRED. `orepile` and `slagheap` both build from one
# `heap` shape — a flattened sphere with rubble stuck on it — and it reads as a blob at
# every size on every league. A pile of ore is not a smooth dome; it is TIPPED, so it has a
# slumped face, a crest and an edge, and the honest way to draw one at this camera is a
# timber-framed BIN with the ore heaped inside it. The frame is what gives it a silhouette.
#
# ⚠️ AND NOT EVERY CUP HAS TO BE ABOUT THE METAL. A circuit named after a material does not
# mean every ground on it is a working floor — an abandoned wash pool taken back by moss and
# ivy is still Tin, and it gives the league a board that is not another shed full of hot
# things. That is what `vinewall` is for.
set -u
GEN="$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
RAW="$(cd "$(dirname "$0")/.." && pwd)/public/field/_raw"; mkdir -p "$RAW"

# ⚠️ MAGENTA, NOT GREEN. `proc_arena_art.py` keys both, and greenery on a green screen
# floods straight out of the backdrop into the foliage — see the scenery batch.
S="A single object viewed STRAIGHT FROM THE SIDE at eye level, 16-bit side-view pixel-art \
game — NOT from above or isometric. It rests on flat ground with its base exactly on the \
bottom edge, no gap beneath and no ground drawn. Chunky readable silhouette, soft ambient \
light, muted palette. Plain flat solid bright magenta (#FF00FF) background filling every \
pixel around it. No shadow, no text, no border."

gen () { local o="$RAW/$1"; shift; [ -f "$o" ] && { echo "SKIP $(basename "$o")"; return; }
  echo "GEN  $(basename "$o")"
  bash "$GEN" --prompt "$*" --out "$o" >/dev/null 2>&1 && echo "  ok" || echo "  FAILED"; }

gen prop-anvil.png "A blacksmith's anvil on a squat timber stump block: heavy iron body \
with a tapering horn on one side and a flat working face, the waist visibly narrower than \
the base, a hammer and a pair of tongs resting against the block. Slightly wider than tall. $S"

gen prop-orebin.png "A timber-framed ore bin: four stout corner posts and plank sides \
about waist high, heaped above the rim with broken grey-brown ore rock that slumps over one \
side. The frame is clearly visible through and around the ore. Wider than tall. $S"

gen prop-vinewall.png "A low ruined stone wall smothered in ivy: coursed grey blocks with \
the top broken uneven, dense dark-green climbing leaves covering most of the face and \
trailing down over the base, a few bare stones showing through the growth. Much wider than \
tall. $S"

echo DONE
