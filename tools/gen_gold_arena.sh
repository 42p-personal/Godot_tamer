#!/usr/bin/env bash
# GOLD — the pleasance circuit. Two grounds and two props.
#
# ⚠️ GOLD IS SILVER'S TWIN IN TEAM SIZE, the third time the ladder repeats a scale. Both
# field four, so `arenaGridFor` hands both the same 28x22 target, and the split has to come
# from the SILHOUETTE FAMILY — the same fix that separated Bronze from Iron and then Silver
# from both:
#   Bronze — horizontal masonry, low and long, OPAQUE.
#   Iron   — gateways and stepped daises: things you pass THROUGH and stand ON.
#   Silver — colonnade runs: hard-edged, pale, and PIERCED. You shoot through the bays.
#   Gold   — HEDGES AND PLANTED STONE: soft-topped, dense and opaque again, but green.
#
# ⚠️ AND THE FAMILY IS THE RUNG, THE SAME TRICK SILVER USED. Tier 5 is where the stands gain
# their colonnade and Silver's floor is colonnades; tier 6 is where `venue.planters` turns on
# and Gold's floor is planting. The stands and the ground say the same thing.
#
# ⚠️ THE CONTRAST WITH SILVER IS DELIBERATELY OPTICAL, NOT JUST THEMATIC. A colonnade is
# straight lines, hard shadow and holes you can see through; a hedge is a soft mass with a
# ragged top and no holes at all. At the shipped camera those two read apart instantly, which
# is the whole job — two pale-stone leagues at one team size would not.
set -u
GEN="$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
RAW="$(cd "$(dirname "$0")/.." && pwd)/public/field/_raw"; mkdir -p "$RAW"

G="Seamless tiling top-down texture for a 16-bit pixel-art game battlefield. Flat even \
ambient light with NO directional shadows and no vignette, so the tile repeats without \
visible seams or hotspots. Muted, low-saturation palette — no bright colour anywhere — \
medium contrast, fine even grain, readable as ground but quiet enough that pixel-art \
creatures and dark green hedging both stand out clearly on top of it. No objects, no \
creatures, no text, no border. Square image."

# ⚠️ MAGENTA, NOT GREEN — and on this league it matters more than on any other. Both of
# Gold's props are FOLIAGE; keyed on green the flood fill walks straight out of the backdrop
# into the leaves, which is exactly how the first scenery batch came back rejected.
S="A single object viewed STRAIGHT FROM THE SIDE at eye level, 16-bit side-view pixel-art \
game — NOT from above or isometric. It rests on flat ground with its base exactly on the \
bottom edge, no gap beneath and no ground drawn. Chunky readable silhouette, soft ambient \
light, muted palette. Plain flat solid bright magenta (#FF00FF) background filling every \
pixel around it. No shadow, no text, no border."

gen () { local o="$RAW/$1"; shift; [ -f "$o" ] && { echo "SKIP $(basename "$o")"; return; }
  echo "GEN  $(basename "$o")"
  bash "$GEN" --prompt "$*" --out "$o" >/dev/null 2>&1 && echo "  ok" || echo "  FAILED"; }

gen ground-parterre.png "A formal garden walk of raked pale gravel: fine buff and grey \
chippings evenly spread, faint parallel rake lines running across, a scatter of larger \
pebbles and a few stray leaves trodden in. Dry, quiet and almost colourless. $G"

gen ground-gildedcourt.png "A ceremonial court floor of warm honey-coloured sandstone \
slabs laid in a tight grid: smooth worn surfaces, thin darker joints, faint traces of an \
inlaid border pattern almost polished away. Warm but muted, never bright. $G"

gen prop-hedge.png "A long clipped garden hedge: a dense solid block of dark green foliage \
with a flat-clipped top and slightly ragged edges, small leaves packed tight so no gaps show \
through, a hint of woody stems at the very base. Completely opaque, no holes. Much wider \
than tall. $S"

gen prop-urn.png "A large formal garden urn on a square stone plinth: a wide pale stone \
bowl with a fluted body and a rolled rim, planted with a low mound of dark clipped greenery \
that spills slightly over one side. Slightly taller than wide. $S"

echo DONE
