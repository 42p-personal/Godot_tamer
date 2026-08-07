#!/usr/bin/env bash
# Generate the 12-species creature-art slice for res://assets/creatures/.
# See docs/ART_PIPELINE.md (Route B) and docs/ART_THEME.md ("Guild Colours").
#
# Usage: ./tools/gen_creatures_slice.sh <species_id>
#   generates one species: raw -> RAW_DIR/<id>.png, processed -> assets/creatures/<id>.png
#
# Run ONE AT A TIME (this project's convention, and Route B is ~1-3 min/image anyway).
set -euo pipefail

REPO="G:/p42.uk/Monster-Tamer"
GEN="$HOME/.claude/skills/gpt-image-2/scripts/gen.sh"
PROC="$REPO/tools/process_creature_art.py"
RAW_DIR="C:/Users/P/AppData/Local/Temp/claude/G--p42-uk-Monster-Tamer/fdaca410-f09e-4030-a42c-1169a1f50bc9/scratchpad/creatures_raw"
OUT_DIR="$REPO/monster-tamer/assets/creatures"

# The shared style wrapper — VERBATIM per docs/ART_THEME.md / the task brief.
# Do not vary this per creature; consistency across the set comes from repetition.
WRAPPER="Full-body illustration of a single creature standing in a relaxed athletic ready stance, viewed STRAIGHT FROM THE SIDE at eye level, both feet flat on an implied groundline at the very bottom edge of the frame. Painterly digital illustration with clean readable silhouette, warm even studio lighting, soft ambient occlusion, no harsh directional shadow. This creature is a PROFESSIONAL SPORTS COMPETITOR, not a warrior: it wears lightweight athletic competition gear only — fabric wraps on its striking limbs, a light singlet or harness, and exactly ONE brightly coloured team sash worn across the body as an obviously removable cloth accessory. Absolutely no armour plate, no weapons, no war regalia, no crown, no throne. The creature's own hide, fur, feathers or scales stay in muted natural colours; the sash is the only strongly saturated accent in the image. Plain solid pure white background. No cast ground shadow, no text, no logo, no border, no UI. Square image."

subject_for() {
  case "$1" in
    kongrath)
      echo "A powerfully built silverback gorilla, broad-chested with a distinctive silver-grey saddle of fur across its back and shoulders, dark fur elsewhere. Standing upright on two legs, knuckles loosely guarded near its chest like a boxer, calm and watchful expression — a quiet, disciplined protector, not a rampaging beast." ;;
    aegisox)
      echo "A stocky bipedal ox-bull creature with a thick, ridged hide across its shoulders and back that is naturally tough like a rhino's skin (its own hide, NOT metal armour), short blunt horns, and sturdy braced legs. Calm, immovable bearing, built low and wide like a heavyweight wrestler planted for a shove." ;;
    grivvel)
      echo "A lean, wiry wolverine creature standing upright, dense dark-brown fur with a lighter stripe along its flanks, a short bristling ruff at the neck, claws visible but not exaggerated into weapons. Tense, coiled posture like a boxer on the balls of its feet, short-tempered energy in its stance." ;;
    corvaan)
      echo "A sleek bipedal raven-creature, glossy blue-black feathers, a sharp intelligent eye, a slender curved beak, feathered arms that fold like a cloak at rest. Alert, upright posture, standing on taloned bird legs, watchful and quick." ;;
    larkessa)
      echo "A graceful songbird creature standing upright on slender legs, plumage in soft warm browns and creams with a bright streak of natural colour at the throat (its own feather colour, not dye), a delicate crest, chest slightly puffed as if mid-song. Poised and light on its feet." ;;
    strixil)
      echo "A large owl creature standing upright, dense mottled grey-brown plumage, an oversized still gaze with big forward-facing eyes, short feathered ear-tufts, feathered arms folded close. Perfectly still, watchful, unnervingly calm posture." ;;
    scarabrute)
      echo "A colossal beetle creature reared up on four sturdy hind legs with two shorter forelimbs held guarded at its chest, a broad domed carapace in deep bronze-black with a natural glossy sheen (its own chitin shell, NOT metal armour), thick plated legs. Braced, dam-like, immovable stance." ;;
    mantevoke)
      echo "A tall praying-mantis creature standing upright on two rear leg pairs, slender triangular head with large compound eyes, folded raptorial forelimbs held close and precise like a fighter's guard (its own chitin, not blades), pale jade-green and tan colouring. Patient, still, coiled-to-strike posture." ;;
    crocmaw)
      echo "A bipedal river-crocodile creature, broad snout with visible interlocking teeth closed in a calm expression, thick natural scaled hide in mottled olive-brown (its own scales, not armour), a low wide powerful stance with a thick balancing tail trailing behind. Patient ambush-predator calm, not aggressive." ;;
    pyraxon)
      echo "A bipedal drake standing upright, hide with a burnished, oxide-toned scale sheen in deep rust and bronze, small backswept horns, folded leathery wings held close against its back, a faint warm glow at the throat like banked embers (ancient fire creature, not breathing flame here). A heraldic drape crosses one shoulder like a champion's earned mantle, not a warlord's cape. Proud, disciplined stance." ;;
    tenebrae)
      echo "An upright shadow-squid creature, glossy deep-indigo hide with faint bioluminescent markings glowing softly along its arms in place of dye or paint, a cluster of thick muscular tentacles gathered beneath it that plant flat against the ground like braced legs, two longer limbs held guarded near its head. Sleek, poised, sneaky-assassin stillness." ;;
    titanrex)
      echo "A massive bipedal tyrant-lizard creature, thick rugged hide in deep slate-grey with faint darker banding (its own scales, not armour), a huge powerful head with a closed jaw, small forearms tucked close, thick tree-trunk legs braced wide, a heavy balancing tail. A simple cord of small guild medallions rests across its chest, marking it as a renowned individual rather than any birthright. Raw, grounded, immovable power." ;;
    ursath)
      echo "A massive brown bear creature standing upright on two thick legs, deep umber-brown shaggy fur, small rounded ears, a broad heavy-boned frame built to absorb punishment rather than dodge it, forepaws held loosely guarded near its chest like a heavyweight's guard. Slow, unhurried, immensely sturdy bearing — a wall of a competitor." ;;
    pinguox)
      echo "A stocky upright penguin creature, torpedo-built body, dense waterproof plumage in charcoal-black over the back and clean white over the belly, small flipper-arms held close to its sides, sturdy webbed feet. Alert, poised, a diver's readiness in its stance. Its body plan cannot take a chest sash: instead a single dyed cord band wraps one ankle as its only mark of team colour, and plain neutral tan wrap-cord binds the base of both flippers, matching the wrap material worn by the rest of the roster." ;;
    balaenix)
      echo "A tall shoebill stork creature standing statue-still on long slender legs, blue-grey plumage, a massive broad hooked bill held level and closed, wide unblinking eyes, small wings folded close at its sides. Motionless, ambush-predator patience, a creature that wins by waiting. Its body plan cannot take a chest sash: instead a single dyed ribbon is threaded through the flight feathers of one folded wing as its only mark of team colour, and plain neutral tan wraps bind its legs just above the ankle, matching the wrap material worn by the rest of the roster." ;;
    bruxaroo)
      echo "A lean athletic kangaroo creature standing upright on powerful hind legs with a thick balancing tail planted behind it, reddish-tan fur, forepaws raised in a genuine boxer's guard, a confident showman's expression, chest puffed with charisma. A crowd-pleasing competitor's poise, weight balanced and ready to spring." ;;
    tazzik)
      echo "A compact, wiry Tasmanian-devil creature standing upright on hind legs, dense black fur with a ragged white stripe across the chest, a wide undershot jaw held in a tense calm, small alert ears, forepaws held loose and ready like a scrapper's guard. Twitchy, coiled, ready-to-lunge energy held just in check." ;;
    nautilux)
      echo "A nautilus creature whose lower body is a weathered spiral shell in muted cream and rust-brown growth bands, upright at rest, a cluster of short pale tentacle-arms held guarded in front of a small hard-shelled head, a calm and patient bearing like something that has weathered a thousand tides. It has no torso or limbs to sash: instead a single dyed cord is wound once around the outer whorl of its shell near the opening as its only mark of team colour, and plain neutral tan wrap-cord binds the base of its tentacle-arms, matching the wrap material worn by the rest of the roster." ;;
    arachnyx)
      echo "A large spider creature reared up on its rear four legs, front four legs held guarded close to its body like a boxer's stance, glossy dark chitin with faint violet-brown mottling, several small eyes, spinnerets tucked beneath its abdomen. Still, patient, web-weaver stillness — a creature that wins by waiting. Its chitin body has nothing for cloth to tie to: instead a waxed thread in the team colour is lashed once across its thorax as its only mark of colour, in place of any sash, and plain neutral tan wrap-thread binds two of its foreleg joints, matching the wrap material worn by the rest of the roster." ;;
    iguanor)
      echo "A bipedal crested iguana creature, vivid natural green scales with a tall fibrous dorsal crest running down its spine and a proud dewlap at the throat (its own hide colouring, not dye), sturdy clawed legs, a long balancing tail trailing behind, chest out in a proud showman's posture. Sun-crowned confidence, a champion's bearing." ;;
    *)
      echo "ERROR: unknown species id '$1'" >&2; exit 2 ;;
  esac
}

id="${1:?usage: gen_creatures_slice.sh <species_id>}"
subject="$(subject_for "$id")"
mkdir -p "$RAW_DIR" "$OUT_DIR"

raw_path="$RAW_DIR/$id.png"
out_path="$OUT_DIR/$id.png"

echo "== $id =="
echo "-- generating raw --"
"$GEN" --prompt "$subject $WRAPPER" --out "$raw_path" --timeout-sec 300

echo "-- post-processing --"
python3 "$PROC" "$raw_path" "$out_path"
