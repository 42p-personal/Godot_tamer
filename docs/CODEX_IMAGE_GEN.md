# Generating images with Codex — the process

**This is the route this project uses.** All 65 species portraits and all 18
backdrops were made this way. Do not go looking for a different image service
when it fails; work this process.

---

## 0. PRE-FLIGHT — always, before anything else

```bash
python3 tools/codex_check.py
```

Exit 0 means generate. Exit 1 prints the reason and the fix — **stop, do not
start a batch, do not start debugging prompts.**

> ⚠️ **This step exists because of a real two-day failure.** On 2026-07-27
> generation began returning `403 Forbidden` with no detail. It was investigated
> as a prompt problem, then a missing-flag problem, then a quota problem. It was
> none of those: **the ChatGPT Plus subscription had expired at
> 2026-07-27T15:39Z**, one day after the last successful image.
>
> The trap is that **`codex login status` still reports "Logged in using
> ChatGPT"**, because the OAuth token is perfectly valid — only the entitlement
> behind it is gone. Every surface-level check looks healthy. The only signal is
> `chatgpt_subscription_active_until` inside the token, which is exactly what
> `tools/codex_check.py` reads.

---

## 1. Generate

```bash
bash ~/.claude/skills/gpt-image-2/scripts/gen.sh \
  --prompt "<the prompt>" \
  --out /absolute/path/out.png
```

That wrapper is preferred over calling `codex exec` by hand: it snapshots
`~/.codex/sessions/`, runs the generation, diffs for the new rollout, and
decodes the base64 payload straight to `--out`. Doing it by hand means hunting
for the file yourself.

If you do call codex directly:

```bash
codex exec --enable image_generation --skip-git-repo-check \
  "Generate exactly one image and do nothing else (no code, no file edits). Image: <SUBJECT>; <STYLE WRAPPER>."
```

Two flags people get wrong on codex-cli 0.111.0+:

- **`--enable image_generation` is required.** The feature is off by default.
  (Note: adding it does *not* fix a 403 — that is an entitlement failure, a
  different layer. Check pre-flight first.)
- **Never `--ephemeral`.** Ephemeral sessions are not persisted, so the image
  payload has nowhere to live and cannot be recovered.

Raw output lands in `~/.codex/generated_images/<session>/*.png` — RGB, solid
background, ~1024px. Newest file:

```bash
find ~/.codex/generated_images -name '*.png' -printf '%T@ %p\n' | sort -rn | head -1 | cut -d' ' -f2-
```

> ⚠️ **Path form.** That yields a git-bash path (`/c/Users/...`). Windows Python
> needs `C:/Users/...` — convert with `sed 's|^/c/|C:/|'` or Pillow throws
> `FileNotFoundError`.

---

## 2. Prompting for a consistent set

Consistency across a set comes from the **style wrapper being identical**, not
from the subject descriptions. Read one existing asset first and mirror it.

- Ask for a **plain solid pure-white background** so the flood-fill has a clean
  seed — unless the art itself is light, then pick a contrasting flat colour.
- Check what you already have with Pillow before writing the wrapper:
  `Image.open(p).size, .mode, .getbbox()`.

---

## 3. Post-process

| Asset kind | Script | Anchoring |
|---|---|---|
| Portraits | `image-gen-codex` skill's `process.py` | bbox-**centred** |
| Battle sprites | `tools/battle_sprite.py` | **foot-anchored, one shared scale** |

⚠️ These differ deliberately. Centring each frame's bounding box is right for a
single still and **wrong for animation** — a walk frame whose creature is a few
pixels shorter gets re-centred, so the sprite bobs and slides instead of
walking.

---

## 4. Batching

One `codex exec` per asset, ~1–3 min each including agent overhead. Run the loop
with `run_in_background: true` and post-process each raw as it lands.

65 species × 4 frames ≈ 260 images ≈ 4–13 hours of wall clock — batch it
overnight and verify in the morning rather than blocking on it.

⚠️ **Re-run the pre-flight before a long batch.** `codex_check.py` warns when
the subscription has ≤7 days left; starting a 13-hour run that expires halfway
through wastes the whole night and produces a half-set.

---

## Failure decision tree

| Symptom | Cause | Action |
|---|---|---|
| `403 Forbidden` from the image service | **Subscription expired** (most likely), or image-gen not entitled on the plan | Run `tools/codex_check.py`. Renew if expired. Nothing about the prompt or flags helps. |
| `billing_hard_limit_reached` | That is **Route A** (direct OpenAI API), not codex | Different route entirely — see `docs/ART_PIPELINE.md`. A hard account cap; not fixed by cheaper size/quality/model. |
| Codex answers in prose, burns tokens, no image | `--enable image_generation` missing | Add the flag. |
| Generation succeeds, no file found | `--ephemeral` was passed | Drop it; the session must persist. |
| `FileNotFoundError` in post-processing | git-bash path handed to Windows Python | `sed 's|^/c/|C:/|'` |

**Whatever the symptom: run the pre-flight before forming a theory.** Every hour
lost to this so far was spent theorising before checking.
