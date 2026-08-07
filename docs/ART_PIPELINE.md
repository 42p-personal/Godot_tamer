# Art pipeline — how this game's images get made

⚠️ **CORRECTED 2026-08-03 — THE "0 GENERATED" FIGURE IN THIS FILE AND IN `ART_PIPELINE.md`
WAS WRONG.** Counted from the filesystem: **30 of 390 battle sprites already exist** — the
complete Mammal group (Kongrath, Aegisox, Maneleo, Grivvel, Ursath), all six frames each. So the
pilot everyone keeps proposing has already been run once, and its output is on disk.

⚠️ **THAT IS THE SEVENTH THING THIS REVIEW HAS FOUND ALREADY BUILT WHILE DOCUMENTED AS
MISSING**, after per-unit speed, the leash, `spreadStatus`, the cohesion/predation archetype
grid, per-ability `range`, and the measurement that speed does not fix chasing. **Count the
files before believing a count in prose.**


Every bitmap asset in the game was generated through one of the two routes
below. This file exists because the method kept getting rediscovered from
scratch; check here before assuming anything is impossible.

## What has been produced this way

| Asset set | Count | Spec | Location |
|---|---|---|---|
| Species portraits | 65 | 320×320 RGBA, transparent, adult-only, 3/4 hero pose | `public/sprites/<id>.png` |
| League arena backdrops | 10 | 1400×788 JPEG, painterly matte | `public/backgrounds/` |
| Area backdrops | 8 | 1400×788 JPEG, same look | `public/backgrounds/` |
| **Battle sprites** (generated) | **0 of 260** | 128×128 RGBA, side profile, 4 frames | `public/battle/<id>-<frame>.png` |
| **Rigged pixel sprites** (Route C) | **all 65, computed** | 48×48, 6 anims × 8 frames | none — built at runtime |

The first three sets are done. Battle sprites are specified
(`docs/BATTLE_SPRITES.md`) and tooled (`tools/battle_sprite.py`) but **not yet
generated** — see Status below.

## Route A — OpenAI API (the fast path, when it works)

`gpt-image-1` with `background: transparent` gives **native alpha**, so no
flood-fill and no white halo. This is the preferred route.

```bash
# needs OPENAI_API_KEY in the environment (it is set on this machine)
python3 tools/gen_image.py "<prompt>" out.png
```

**Known failure:** `400 billing_hard_limit_reached`. This is a hard account
cap — it is NOT worked around by asking for a cheaper size, quality or model.
When you see it, switch to Route B.

## Route B — Codex CLI (the billing-cap workaround)

> **📖 Full process: [`CODEX_IMAGE_GEN.md`](CODEX_IMAGE_GEN.md).** This is the
> route the project actually uses. Start there, and always run
> `python3 tools/codex_check.py` BEFORE anything else.


The `codex` CLI has a built-in `image_gen` tool authenticated by the **ChatGPT
subscription**, which bypasses the API billing cap entirely. This is how all 65
portraits and all 18 backdrops were actually made.

```bash
codex exec --skip-git-repo-check \
  "Generate exactly one image and do nothing else (no code, no file edits). Image: <SUBJECT>; <STYLE WRAPPER>."
```

- Output lands in `~/.codex/generated_images/<session>/*.png` — **RGB with a
  solid background**, ~1024px. There is no destination argument; copy it out.
- Find the newest raw:
  ```bash
  find ~/.codex/generated_images -name '*.png' -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-
  ```
- ⚠️ **Path form:** that yields a git-bash path (`/c/Users/...`). Windows Python
  needs `C:/Users/...` — convert with `sed 's|^/c/|C:/|'` or Pillow throws
  `FileNotFoundError`.
- Ask for a **plain solid pure-white background** so the flood-fill has a clean
  seed, unless the art itself is light — then pick a contrasting flat colour.

**Known failure:** `image generation failed: http 403 Forbidden`. The codex
agent itself still works (it answers, burns tokens) — only the image service
refuses.

⚠️ **CAUSE FOUND 2026-07-28: the ChatGPT Plus subscription EXPIRED at
2026-07-27T15:39Z** — one day after the last successful image on 2026-07-26.
This was originally logged here as a guess ("quota/entitlement") and then
re-investigated twice as a prompt problem and a missing-flag problem. It is
neither, and `--enable image_generation` does not fix it.

The reason it misleads: **`codex login status` still says "Logged in using
ChatGPT"**, because the OAuth token remains valid — only the entitlement behind
it lapsed. `python3 tools/codex_check.py` reads
`chatgpt_subscription_active_until` out of the token and says so in one line.
**Run it before forming any theory.**

## Post-processing

| Asset kind | Script | Anchoring |
|---|---|---|
| Portraits | `image-gen-codex` skill's `process.py` | bbox-**centred** |
| Battle sprites | `tools/battle_sprite.py` | **foot-anchored, one shared scale** |

⚠️ They are deliberately different. Centring each frame's bounding box is right
for a single still portrait and **wrong for animation** — a walk frame whose
creature is a few pixels shorter gets re-centred, so the sprite bobs and slides
instead of walking. See `docs/BATTLE_SPRITES.md`.

## Matching an existing set

Read one existing asset first and mirror its look in a **shared style wrapper**
appended to every subject prompt. Check size/mode/framing with Pillow
(`Image.open(p).size, .mode, .getbbox()`). Consistency across a set comes from
the wrapper being identical, not from the subject descriptions.

## Batching

One `codex exec` per asset, ~1–3 min each including agent overhead. Run the loop
with `run_in_background: true` and post-process each raw as it lands. 65 species
× 4 frames = 260 images ≈ 4–13 hours of wall clock, so batch overnight and
verify in the morning rather than blocking on it.

## Route C — draw it in code (no art service at all)

When both routes above are down, small pixel art can be **computed**. `src/tamerengine/
pixelRig.ts` builds each creature from parts — torso, head, two arms, two legs,
tail — and animates it by rotating the joints, so arms genuinely swing and legs
genuinely stride. Six animations × 8 frames per species, generated into a sprite
sheet at load and cached.

Colour is **inherited, not invented**: `tools/sample_ramp.py` derives a 5-step
ramp from each species' existing portrait, so a rigged sprite still looks like
the creature the player knows.

```bash
python3 tools/sample_ramp.py kongrath aegisox maneleo grivvel ursath
```

⚠️ Three failures worth not repeating, none of them visible in a still frame:
- **Hue by circular mean gives a purple gorilla.** A silverback has warm fur AND
  a cool silver back; averaging two opposite hues lands between them and matches
  neither. Use the peak of a saturation-weighted hue histogram.
- **No saturation floor.** Forcing a minimum saturation onto a near-achromatic
  creature invents a colour it does not have.
- **Ramp floor matters as much as its ceiling.** Starting at 0.34 of the
  creature's lightness put its darkest mass within a few points of the
  battlefield background and the silhouette dissolved.

## Status — 2026-08-01: Route B is LIVE again

`python3 tools/codex_check.py` probes green and generation works. Six Wood arena
assets (two ground tiles, four props) were produced this way on 2026-08-01 —
see `tools/gen_wood_arena.sh` for the batch and `tools/proc_arena_art.py` for
the post-processing.

⚠️ **The status below is the PREVIOUS one, kept because the diagnosis is the
reusable part.** A blocked-status note is the most expensive kind of stale
documentation: it does not merely mislead, it stops the next session from
even attempting the thing that now works. If you are reading a "blocked"
banner here, run the pre-flight probe before believing it.

### Previously — 2026-07-28

Battle sprite GENERATION was **blocked, and the cause was known**:

- Route A → `billing_hard_limit_reached` — OpenAI API account hard-capped.
- Route B → `403 Forbidden` — **the ChatGPT Plus subscription expired
  2026-07-27T15:39Z.** Renewing it made Route B work again immediately; nothing in
  the repo needed to change.

Confirm with `python3 tools/codex_check.py`.

**Route C exists as a fallback** — rigged pixel sprites, no art service needed —
but it is NOT good enough to ship: procedural capsules and ellipses produce a
generic beast that does not read as the specific creature. Use it only as a
placeholder. Real art comes from Route B once the subscription is live.

The spec, the processor and its verification all exist and are proven against
real art (`kongrath.png` run through the pipeline as four frames produced a
clean cutout with feet aligned within 0px). The moment either route returns,
the pilot can run unchanged.
