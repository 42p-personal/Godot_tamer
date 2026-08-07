#!/usr/bin/env python3
"""Post-process a raw creature render (solid white background) into a transparent,
alpha-trimmed sprite for res://assets/creatures/<species_id>.png.

Unlike the portrait pipeline (image-gen-codex's process.py), this does NOT pad to a
square or centre the bbox. See docs/ART_THEME.md / the creature-art task brief: these
sprites are FOOT-ANCHORED — the renderer plants the bottom of the sprite on the ground,
so the crop must be the bare alpha bbox. Padding would reintroduce the "floating
creature" bug the battle-sprite pipeline already solved once.

Usage: python3 tools/process_creature_art.py <raw.png> <out.png> [max_side=512] [thresh=40]
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw


def process(raw_path: str, out_path: str, max_side: int = 512, thresh: int = 40) -> str:
    im = Image.open(raw_path).convert("RGB")
    w, h = im.size
    sentinel = (255, 0, 255)
    fillmap = im.copy()
    for corner in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        ImageDraw.floodfill(fillmap, corner, sentinel, thresh=thresh)
    rgba = im.convert("RGBA")
    src, dst = fillmap.load(), rgba.load()
    for y in range(h):
        for x in range(w):
            if src[x, y] == sentinel:
                r, g, b, _ = dst[x, y]
                dst[x, y] = (r, g, b, 0)

    bbox = rgba.getbbox()
    if bbox is None:
        return f"{raw_path}  REJECTED — fully transparent after keying"
    covered = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1]) / (w * h)
    if covered > 0.995:
        return (f"{raw_path}  REJECTED — nothing was keyed out; background is not "
                f"solid white (or thresh too low). Inspect before re-running.")

    rgba = rgba.crop(bbox)
    cw, ch = rgba.size
    scale = max_side / max(cw, ch)
    if scale < 1.0:
        rgba = rgba.resize((max(1, round(cw * scale)), max(1, round(ch * scale))), Image.LANCZOS)

    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    rgba.save(out_path)
    ow, oh = rgba.size
    has_alpha = rgba.getchannel("A").getextrema()[0] < 255
    return f"{Path(out_path).name}  {ow}x{oh} RGBA  alpha={'yes' if has_alpha else 'NO (opaque!)'}  {Path(out_path).stat().st_size // 1024}KB"


if __name__ == "__main__":
    a = sys.argv
    print(process(a[1], a[2],
                   int(a[3]) if len(a) > 3 else 512,
                   int(a[4]) if len(a) > 4 else 40))
