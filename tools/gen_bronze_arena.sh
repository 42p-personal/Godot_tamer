#!/usr/bin/env bash
# Bronze league arena art — 2 ground tiles only.
#
# ⚠️ BRONZE NEEDS NO NEW PROPS, AND THAT IS THE POINT RATHER THAN A SHORTCUT. Bronze IS
# copper and tin — the ladder is literally an alloy story, Wood → Copper → Tin → BRONZE —
# so its yards are stocked from BOTH earlier leagues: Copper's ore piles, crucibles,
# ingots and slag beside Tin's gravel bars and cast blocks. That is the flavour the naming
# already paid for, and it means four new arenas cost two images instead of ten.
#
# ⚠️ IT STILL NEEDS ITS OWN GROUND, THOUGH. Reusing Copper's floor would make Bronze read
# as a fourth Copper arena; the ground is what a player names a league from in a still
# frame. Bronze's is the alloy visibly happening: green copper scale and pale tin dust
# trodden together into the warm gold-brown of the metal they make.
set -u
GEN="$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
RAW="$(cd "$(dirname "$0")/.." && pwd)/public/field/_raw"
mkdir -p "$RAW"

GROUND_STYLE="Seamless tiling top-down texture for a 16-bit pixel-art game battlefield. \
Flat even ambient light with NO directional shadows and no vignette, so the tile repeats \
without visible seams or hotspots. Muted palette, medium contrast, fine grain — readable as \
ground but quiet enough that pixel-art creatures stand out clearly on top of it. No objects, \
no creatures, no text, no border. Square image."

gen () { local out="$RAW/$1"; shift
  if [ -f "$out" ]; then echo "SKIP $(basename "$out")"; return; fi
  echo "GEN  $(basename "$out")"
  bash "$GEN" --prompt "$*" --out "$out" >/dev/null 2>&1 \
    && echo "  ok $(stat -c%s "$out" 2>/dev/null || echo '?') bytes" || echo "  FAILED"
}

gen ground-alloyfloor.png "The beaten earth floor of a bronze foundry yard: warm gold-brown \
dust trodden hard, streaked with verdigris-green copper scale and pale grey tin ash mixed \
together, scattered flecks of spilled bronze that catch a dull warm sheen, faint ring-marks \
where crucibles have stood. Warm brown-gold palette with green and pale grey grit through \
it. $GROUND_STYLE"

gen ground-bellyard.png "The floor of a bell-casting yard: packed dark casting sand and fine \
grey loam, raked into shallow parallel furrows, ringed with pale mould-dust and small dark \
patches of burnt sand, a few chips of broken clay mould trodden in. Cooler and darker than a \
foundry floor, grey-brown with warm dust. $GROUND_STYLE"

echo "DONE"
