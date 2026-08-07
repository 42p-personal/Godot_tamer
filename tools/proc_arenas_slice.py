#!/usr/bin/env python3
"""Post-process the five-league arena art slice (tools/gen_arenas_slice.sh) into
the shapes monster-tamer/scripts/art.gd expects.

  <slug>-backdrop.png (raw) -> monster-tamer/assets/arenas/<slug>-backdrop.jpg
      centre-cropped to 16:9, resized to 1400x788, JPEG.
  <slug>-ground.png   (raw) -> monster-tamer/assets/arenas/<slug>-ground.jpg
      centre-cropped to square, resized to 1024x1024, JPEG.
  title.png            (raw) -> monster-tamer/assets/ui/title.jpg
      same treatment as a backdrop (16:9, 1400x788).

Same crop/resize discipline as tools/proc_arena_art.py's do_ground() -- centre
crop to the target aspect first, THEN resize, so a slightly off-aspect raw
doesn't get squashed.

Usage: python3 tools/proc_arenas_slice.py
"""
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / 'monster-tamer' / 'assets' / 'arenas' / '_raw'
ARENA_OUT = ROOT / 'monster-tamer' / 'assets' / 'arenas'
UI_OUT = ROOT / 'monster-tamer' / 'assets' / 'ui'

BACKDROP_SIZE = (1400, 788)
GROUND_SIZE = (1024, 1024)


def crop_to_aspect(im: Image.Image, target_w: int, target_h: int) -> Image.Image:
    target_ratio = target_w / target_h
    w, h = im.size
    ratio = w / h
    if ratio > target_ratio:
        # too wide -- crop width
        new_w = round(h * target_ratio)
        left = (w - new_w) // 2
        im = im.crop((left, 0, left + new_w, h))
    elif ratio < target_ratio:
        # too tall -- crop height
        new_h = round(w / target_ratio)
        top = (h - new_h) // 2
        im = im.crop((0, top, w, top + new_h))
    return im


def process_backdrop(src: Path, dest: Path) -> str:
    im = Image.open(src).convert('RGB')
    im = crop_to_aspect(im, *BACKDROP_SIZE)
    im = im.resize(BACKDROP_SIZE, Image.LANCZOS)
    im.save(dest, quality=90, optimize=True)
    return f'{dest.name}  {im.size[0]}x{im.size[1]} RGB  {dest.stat().st_size // 1024}KB'


def process_ground(src: Path, dest: Path) -> str:
    im = Image.open(src).convert('RGB')
    im = crop_to_aspect(im, *GROUND_SIZE)
    im = im.resize(GROUND_SIZE, Image.LANCZOS)
    im.save(dest, quality=90, optimize=True)
    return f'{dest.name}  {im.size[0]}x{im.size[1]} RGB  {dest.stat().st_size // 1024}KB'


def main() -> int:
    if not RAW.is_dir():
        print(f'no raw directory at {RAW}')
        return 1
    raws = sorted(RAW.glob('*.png'))
    if not raws:
        print('no raws to process')
        return 1
    ARENA_OUT.mkdir(parents=True, exist_ok=True)
    UI_OUT.mkdir(parents=True, exist_ok=True)
    bad = 0
    for src in raws:
        try:
            if src.stem == 'title':
                line = process_backdrop(src, UI_OUT / 'title.jpg')
            elif src.stem.endswith('-backdrop'):
                line = process_backdrop(src, ARENA_OUT / (src.stem + '.jpg'))
            elif src.stem.endswith('-ground'):
                line = process_ground(src, ARENA_OUT / (src.stem + '.jpg'))
            else:
                line = f'{src.name}  SKIPPED -- name must end -backdrop/-ground or be title'
        except Exception as e:  # noqa: BLE001
            line = f'{src.name}  FAILED -- {e}'
            bad += 1
        print('  ' + line)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
