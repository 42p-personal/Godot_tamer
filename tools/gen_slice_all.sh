#!/usr/bin/env bash
# The whole vertical-slice art batch, in ONE strictly sequential stream.
#
# ⚠️ SERIAL IS NOT A STYLE CHOICE, IT IS A CORRECTNESS REQUIREMENT.
# `~/.claude/skills/gpt-image-2/scripts/gen.sh` finds its output by diffing the set of codex
# session rollout files before and after the run (`comm -13 before after`). Two generations
# running at once therefore each see the OTHER's session as "new" and can decode the wrong
# image into the wrong file. Two art agents were originally given one batch each to run in
# parallel; that would have silently produced creatures in arena files. Do not parallelise this.
#
# Both underlying scripts are resumable — they skip an asset whose raw already exists — so this
# is safe to re-run after an interruption, and interruption is likely: ~1-5 min per image, 22
# images, and the service is subscription-gated (see docs/ART_PIPELINE.md for both prior outages).
#
# Creatures run FIRST because they are the more visible half of "I want to see artwork", and
# because every screen in the game shows a creature while only one shows an arena.
#
# Usage: bash tools/gen_slice_all.sh    (run in background; tail the log)
set -u
cd "$(dirname "$0")/.."

CREATURES="kongrath aegisox grivvel corvaan larkessa strixil scarabrute mantevoke crocmaw pyraxon tenebrae titanrex"

echo "########## CREATURES ##########"
for id in $CREATURES; do
  out="monster-tamer/assets/creatures/$id.png"
  if [ -f "$out" ]; then
    echo "SKIP $id (final exists)"
    continue
  fi
  echo "---------- $id ----------"
  bash tools/gen_creatures_slice.sh "$id" || echo "  FAILED $id"
done

echo "########## ARENAS ##########"
bash tools/gen_arenas_slice.sh

echo "########## BATCH COMPLETE ##########"
echo "creatures: $(ls monster-tamer/assets/creatures/*.png 2>/dev/null | wc -l)/12"
echo "arenas:    $(ls monster-tamer/assets/arenas/*-backdrop.jpg monster-tamer/assets/arenas/*-ground.jpg 2>/dev/null | wc -l)/10"
echo "ui:        $(ls monster-tamer/assets/ui/*.jpg 2>/dev/null | wc -l)/1"
