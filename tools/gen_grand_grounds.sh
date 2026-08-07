#!/usr/bin/env bash
# THE GRAND CIRCUIT — twenty 5v5 grounds, shared by every league from Platinum up.
#
# ⚠️ THE ARENA AND THE STADIUM ARE SEPARATE LAYERS, AND THIS IS WHERE THAT PAYS OFF. Every
# league below builds its own boards because its MATERIAL is its name — Wood is timber, Iron
# is forge scale. From Platinum the team size stops growing (five, all the way to Apex) and
# the ladder is carried by the VENUE instead: the same twenty grounds, under a stadium that
# gains arches, then an entablature, then turrets, then the victory arch. One pool, four
# leagues, four visibly different occasions.
#
# ⚠️ SO THE POOL IS DIFFERENTIATED BY COLOUR, which is the only axis it has left. Twenty
# boards at one team size cannot be told apart by scale, and they must not be told apart by
# league because they belong to all four. What is left is the STONE: porphyry, serpentine,
# basalt, alabaster, slate — real, historically-quarried arena stones, each unmistakable at a
# glance and none of them the working-yard browns and greys of the circuits below.
#
# ⚠️ AND THEY MUST BE QUIETER THAN THEY SOUND. "Imperial porphyry" and "green marble" are
# exactly the prompts that come back at 0.5 saturation — see `proc_arena_art.py`, where Gold's
# gilded court did that and had to be pulled back hard. A grand ground is grand because of
# what STANDS on it and who is watching; the floor's job is still to sit under a monster
# without competing with it. Each prompt asks for the stone WORN and MUTED.
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

gen ground-porphyry.png "A ceremonial floor of worn porphyry slabs: dull brick-red stone \
flecked with small pale grey and white crystals, cut in large rectangles with thin dark \
joints, the surfaces polished smooth by use and dulled by dust. Desaturated brick-red, \
never bright or pink. $G"

gen ground-serpentine.png "A floor of worn serpentine marble slabs: muted grey-green stone \
with darker veining wandering across it, cut in large rectangles with fine joints, surfaces \
scuffed and matte rather than glossy. Grey first and green second. $G"

gen ground-basalt.png "A floor of dark basalt paving: near-black grey-blue volcanic stone \
laid as tight interlocking blocks, faintly pitted with small vesicles, dry and matte with a \
scatter of pale grit in the joints. Almost colourless and quite dark. $G"

gen ground-alabaster.png "A floor of warm alabaster slabs: soft creamy off-white stone with \
faint honey-coloured banding running through it, large panels with hairline joints, worn \
and slightly chalky rather than polished. Warm but pale and quiet. $G"

gen ground-slateyard.png "A floor of blue-grey slate flags: cool dark grey stone split with \
a faintly layered riven surface, laid as large irregular flags with thin gritty joints, dry \
and matte. Cool grey with only a hint of blue. $G"

echo DONE
