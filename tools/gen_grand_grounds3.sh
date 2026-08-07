#!/usr/bin/env bash
# THE GRAND CIRCUIT, BLOCK 3 — and colour alone has started to run out.
#
# ⚠️ TEN HUES ARE SPENT AND THE ELEVENTH IS ALWAYS A NEIGHBOUR OF AN EXISTING ONE. Blocks 1
# and 2 took brick-red, grey-green, near-black, warm pale, blue-grey, buff-cream, flecked
# grey, ochre, violet and teal. Every remaining "new" stone is a shade of one of those — and
# a board a player cannot name is a board that did not need authoring. Picking a slightly
# different green for the eleventh ground is exactly the failure Gold shipped at six, with a
# quarry catalogue instead of a hedge.
#
# ⚠️ SO BLOCK 3 OPENS A SECOND AXIS: PATTERN. Two of these five are differentiated by their
# LAYOUT rather than their hue — a chequer of black and white squares and a fine tesserae
# mosaic — and both read instantly at the camera precisely because no other floor in the game
# has a figure on it. Twenty grounds sorted on one axis is a gradient; sorted on two it is a
# set. The remaining three take the last three genuinely unused hues.
#
# ⚠️ AND THE PATTERNED TWO MUST BE THE QUIETEST OF ALL, which sounds like a contradiction and
# is not. A high-contrast floor competes with the SPRITES rather than with the other floors:
# black-and-white squares at full strength put a hard edge under every monster on the board.
# Both prompts ask for the pattern WORN, the contrast reduced and the tiles large.
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

gen ground-chequer.png "A worn chequerboard marble floor: LARGE alternating squares of dark
grey-brown and pale warm grey stone, the contrast between them SOFTENED by heavy wear and a \
film of pale dust, edges chipped and joints uneven. Never crisp black and white — both \
squares are muted greys with only a modest difference between them. $G"

gen ground-mosaic.png "A worn Roman tesserae mosaic floor: thousands of small square stone \
tiles in muted dusty ochre, soft grey-blue and off-white, laid in a simple geometric \
interlace with a plain border, many tiles chipped or missing and the whole surface dulled \
with age. Fine scale — the tiles are tiny relative to the frame. $G"

gen ground-rosestone.png "A floor of dusty rose sandstone slabs: soft muted pink-grey stone \
with faint darker bedding lines, cut as large panels with fine sandy joints, matte and worn \
with a bloom of pale dust across it. Desaturated and dusty, closer to grey than pink. $G"

gen ground-onyx.png "A floor of banded onyx panels: creamy off-white stone shot through with \
sweeping bands of dark brown-black that swirl across the slabs, cut as large rectangles with \
hairline joints, polished then dulled by wear. High tonal contrast within the stone, but no \
colour beyond cream and near-black. $G"

gen ground-verdite.png "A floor of deep olive-green stone flags: dark muted moss-and-khaki \
rock with faint darker mottling, laid as large irregular flags with gritty joints, dry and \
matte. Olive and earthy, distinctly warmer and darker than blue-green. $G"

echo DONE
