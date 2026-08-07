#!/usr/bin/env bash
# Five-league arena art slice for the Godot port (backdrop + ground per league)
# plus one title establishing shot. See docs/ART_THEME.md and
# docs/ART_DIRECTION.md for the direction this executes against.
#
# ⚠️ TAMERS APEX IS A TITLE THE GUILD AWARDS, NOT A MATERIAL. Wood/Bronze/Silver/
# Platinum each get ONE material family (see gen_wood_arena.sh's own warning:
# "WOOD" IS THE LEAGUE'S TIER MATERIAL, NOT A FARMYARD — same discipline applies
# to bronze/silver/platinum here). Tamers Apex deliberately combines several
# fine materials (marble, gold, bronze) because it is the capstone TITLE, not a
# rung on the material ladder.
#
# ⚠️ CAMERA MATCHES THE FIGHT, NOT AN AERIAL FANTASY SHOT. The previous
# generation (monster-tamer/assets/arenas/*.jpg, no -backdrop/-ground suffix)
# shipped a muddy farmyard for Wood and a floating sky-castle for Tamers Apex,
# both shot from a high three-quarter angle. Every backdrop below is specified
# low, spectator-level, straight across the field — the wrapper text is
# load-bearing, not decoration.
#
# Usage: bash tools/gen_arenas_slice.sh   (~1-5 min per asset; run sequentially)
set -u
GEN="$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
OUT="$(cd "$(dirname "$0")/.." && pwd)/monster-tamer/assets/arenas"
UI_OUT="$(cd "$(dirname "$0")/.." && pwd)/monster-tamer/assets/ui"
RAW="$OUT/_raw"
mkdir -p "$RAW"

BACKDROP_STYLE="Painterly matte painting of a sports arena interior, seen from a low \
spectator-level camera looking STRAIGHT ACROSS the field with the horizon near the \
vertical middle. Wide establishing shot showing tiered stands, banners and architecture. \
Warm even lighting with soft atmospheric depth haze toward the back of the venue. THE \
ENTIRE FOREGROUND FLOOR IS EMPTY, flat and unobstructed -- animated competitors will be \
composited standing on it, so nothing may occupy the lower third. No creatures, no people \
in the foreground, no text, no logos, no scoreboard lettering, no UI. Muted slightly \
desaturated palette so brightly coloured competitors read clearly against it. Cinematic, \
high detail, 16:9 widescreen landscape."

GROUND_STYLE="Seamless tiling top-down texture for a game battlefield floor. Flat even \
ambient light with NO directional shadows and no vignette, so the tile repeats without \
visible seams or hotspots. Muted natural palette, medium contrast, fine grain -- readable \
as ground but quiet enough that creatures stand out clearly on top of it. No objects, no \
creatures, no text, no border. Square image."

TITLE_STYLE="Painterly matte painting establishing shot, photographed from HIGH UP IN THE \
SPECTATOR STANDS looking down and across a packed arena bowl at golden hour, warm raking \
sunlight, soft atmospheric haze, a vast crowd filling the tiers. Cinematic composition, \
high detail, epic and triumphant mood. No text, no logos, no UI, no scoreboard lettering \
anywhere in the image. 16:9 widescreen landscape."

gen () { # gen <outfile> <prompt>
  local out="$RAW/$1"; shift
  if [ -f "$out" ]; then echo "SKIP $(basename "$out") (exists)"; return; fi
  echo "GEN  $out"
  bash "$GEN" --prompt "$*" --out "$out" --timeout-sec 300 >/dev/null 2>&1 \
    && echo "  ok $(stat -c%s "$out" 2>/dev/null || echo '?') bytes" \
    || echo "  FAILED $out"
}

# ── Wood: the humble parish ring — timber, rope, sawdust ───────────────────
gen wood-backdrop.png "A humble timber fighting ring in a working lumber yard: a circular \
ring built from raw sawn timber boards and stout wooden posts, a low modest wooden \
grandstand of a few tiered plank benches on one side, rope-and-timber rails, stacked \
timber and sawdust piles visible at the venue's edges, warm lantern light at dusk. Small, \
honest, entirely hand-built from wood -- no stone, no metal ornament, no crowds of people. \
$BACKDROP_STYLE"

gen wood-ground.png "Weathered wooden floorboards of an old timber fighting ring: wide \
grey-brown planks laid in one direction, visible wood grain and knots, dark gaps between \
boards, a few iron nail heads, scattered sawdust caught in the seams. $GROUND_STYLE"

# ── Bronze: the foundry-town arena — cast bronze, patina, brazier light ────
gen bronze-backdrop.png "A foundry-town sports arena at dusk: cast bronze fittings and \
railings with a warm green-brown patina, a ring of brazier flames casting warm light, a \
mid-size tiered stone grandstand hung with bronze standards and banners, industrial \
furnace stacks and chimneys visible beyond the venue walls, proud working-class \
architecture. Materials are bronze, patinated copper-alloy metal and warm brick. No \
crowds of people. $BACKDROP_STYLE"

gen bronze-ground.png "The packed floor of a foundry-town arena: dark tamped clay dusted \
with fine bronze filings and warm patina-green flecks, subtle scorch marks, a few worn \
bronze rivets pressed into the surface. $GROUND_STYLE"

# ── Silver: the refined civic hall — polished pale stone, silver inlay ─────
gen silver-backdrop.png "A refined civic sporting hall interior: a polished pale grey \
stone colonnade ringing the field, clean silver inlay lines tracing the tiers, tall \
arched windows admitting cool daylight, a larger and more formal tiered stand with \
silver-trimmed balustrades, elegant restrained architecture of a respected trade guild's \
flagship hall. No crowds of people. $BACKDROP_STYLE"

gen silver-ground.png "Polished pale grey stone flagstones of a refined civic arena \
floor, fine silver inlay lines tracing a subtle geometric pattern between the slabs, cool \
even tone, faint natural stone veining. $GROUND_STYLE"

# ── Platinum: the grand modern coliseum — white metal, glass, sweeping tiers ─
gen platinum-backdrop.png "A grand modern coliseum interior: sweeping tiers of pale white \
metal and glass, soaring platinum-toned structural arches, bright daylight flooding \
through a vast glazed canopy, banners and pennants along a wide ornate colonnade, an \
enormous gleaming venue built to host the circuit's greatest matches. No crowds of \
people. $BACKDROP_STYLE"

gen platinum-ground.png "Smooth pale platinum-white stone and metal tiles of a grand \
modern coliseum floor, faint geometric inlay lines, bright clean surface with a soft cool \
metallic sheen. $GROUND_STYLE"

# ── Tamers Apex: the capstone TITLE venue — every fine material combined ───
gen tamers-apex-backdrop.png "The single most awe-inspiring venue in the Tamer Circuit: a \
monumental open-air ceremonial coliseum built from fine dressed marble, gold inlay and \
bronze statuary, an immense ceremonial victory arch spanning the far end, tiered stone \
stands rising into a grand entablature lined with statues along the cornice, a mosaic \
floor medallion, open to a vast golden-hour sky. Radiant and triumphant -- the pinnacle \
venue a champion earns, built from the finest craft of every guild combined rather than \
any single material. No crowds of people. $BACKDROP_STYLE"

gen tamers-apex-ground.png "A grand ceremonial floor of pale polished marble inlaid with \
fine gold and bronze medallion patterns radiating from the centre, warm gold filigree \
veining the stone, the finest craftsmanship of every guild combined. $GROUND_STYLE"

# ── Title: the hero establishing shot ───────────────────────────────────────
gen title.png "The Tamer Circuit's grandest coliseum, packed to capacity with an immense \
cheering crowd, golden-hour sunlight raking across marble, gold and bronze architecture, \
banners rippling in a warm breeze, a vast tiered stadium bowl radiant and triumphant. \
$TITLE_STYLE"

echo "DONE -- raws in $RAW"
