#!/usr/bin/env bash
# THE GRAND CIRCUIT, BLOCK 2 — five more stones.
#
# ⚠️ THE POOL IS DIFFERENTIATED BY COLOUR, SO BLOCK 2 MUST NOT REPEAT BLOCK 1'S HUES. Those
# five are brick-red porphyry, grey-green serpentine, near-black basalt, pale alabaster and
# blue-grey slate. Picking another red or another cool grey would spend a whole board and
# buy nothing: at twenty grounds the pool's identity IS its spread, and a colour used twice
# is a board the player cannot name.
#
# So block 2 takes the five hues the game has none of anywhere:
#   travertine  warm buff-cream, pitted   — warm-pale, where alabaster is cool-pale
#   granite     speckled mid-grey + pink  — the only FLECKED floor; reads as grain, not tint
#   jasper      deep ochre-gold           — the game's only yellow ground
#   amethystine muted violet-grey         — a hue this project has never used at all
#   malachite   dark blue-green           — deeper and bluer than serpentine's grey-green
#
# ⚠️ AND THEY MUST BE QUIETER THAN THEY SOUND, which is now a five-time lesson. "Ochre",
# "violet" and "malachite" are exactly the prompts that come back at 0.5 saturation — Gold's
# gilded court did it at 0.53 and had to be pulled back hard in `proc_arena_art.py`. A grand
# ground is grand because of what stands on it; the floor still has to sit under a monster
# without competing with it. Every prompt below asks for the stone WORN, DUSTY and MUTED.
set -u
GEN="$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
RAW="$(cd "$(dirname "$0")/.." && pwd)/public/field/_raw"; mkdir -p "$RAW"

G="Seamless tiling top-down texture for a 16-bit pixel-art game battlefield. Flat even \
ambient light with NO directional shadows and no vignette, so the tile repeats without \
visible seams or hotspots. MUTED and low-saturation — the colour should read as a tint in \
grey stone, never as a bright hue — medium contrast, fine even grain, quiet enough that \
pixel-art creatures and pale stone architecture both stand out clearly on top of it. No \
objects, no creatures, no text, no border. Square image."

gen () { local o="$RAW/$1"; shift; [ -f "$o" ] && { echo "SKIP $(basename "$o")"; return; }
  echo "GEN  $(basename "$o")"
  bash "$GEN" --prompt "$*" --out "$o" >/dev/null 2>&1 && echo "  ok" || echo "  FAILED"; }

gen ground-travertine.png "A floor of worn travertine slabs: warm buff-cream stone shot \
through with fine horizontal bedding lines and small natural pits and voids, cut in large \
panels with thin joints, surfaces smoothed by traffic and dulled with pale dust. Warm but \
quiet, never yellow. $G"

gen ground-granite.png "A floor of polished-then-worn grey granite: mid-grey stone densely \
speckled with tiny black, white and faint dusty-pink crystals, laid in big square panels \
with hairline joints. The colour comes from the FLECKS, not from a tint. $G"

gen ground-jasper.png "A floor of deep ochre jasper panels: dull mustard-brown stone with \
darker rust banding swirling through it, cut in large rectangles with fine dark joints, \
matte and dusty rather than polished. Earthy and desaturated, closer to brown than yellow. $G"

gen ground-amethystine.png "A floor of muted violet-grey stone flags: cool grey rock with a \
faint dusty lilac cast and thin darker purple veining, laid as large flags with gritty \
joints, dry and matte. Grey first and violet only as a hint. $G"

gen ground-malachite.png "A floor of dark blue-green stone slabs: deep teal-grey rock with \
banded darker green swirls running through it, large panels with fine joints, worn matte and \
softened with pale dust in the seams. Dark and desaturated, never emerald. $G"

echo DONE
