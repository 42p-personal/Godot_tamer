#!/usr/bin/env python3
"""Post-process the arena DRESSING textures (wall/stands/props for the top-down
3D battlefield) from monster-tamer/assets/arena/_raw/ into their final formats
in monster-tamer/assets/arena/.

Two kinds, two treatments:

  TILES  (wall-timber, wall-stone, stands-crowd, barrel-wood, crate-wood)
         -> JPEG, square, 1024px, monster-tamer/assets/arena/<name>.jpg

  CUTOUT (banner-guild)
         -> PNG RGBA, alpha-trimmed to the object, monster-tamer/assets/arena/banner-guild.png

Reuses the flood-fill/despill cutout logic from tools/proc_arena_art.py (loaded
by path, not copied) rather than re-deriving it -- that logic already handles
white/checkerboard/green/magenta backdrops and rejects a raw that carries no
alpha instead of silently accepting a box around the object.

Usage: python3 tools/proc_arena_dressing.py
"""
import importlib.util
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / 'monster-tamer' / 'assets' / 'arena' / '_raw'
OUT = ROOT / 'monster-tamer' / 'assets' / 'arena'
TILE_PX = 1024

TILES = ['wall-timber', 'wall-stone', 'stands-crowd', 'barrel-wood', 'crate-wood']
CUTOUT = 'banner-guild'

_spec = importlib.util.spec_from_file_location('proc_arena_art', ROOT / 'tools' / 'proc_arena_art.py')
_paa = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_paa)


def do_tile(name: str) -> str:
    src = RAW / f'{name}.png'
    im = Image.open(src).convert('RGB')
    if im.width != im.height:
        s = min(im.size)
        left, top = (im.width - s) // 2, (im.height - s) // 2
        im = im.crop((left, top, left + s, top + s))
    im = im.resize((TILE_PX, TILE_PX), Image.LANCZOS)
    out = OUT / f'{name}.jpg'
    im.save(out, quality=90, optimize=True)
    return f'{out.name}  {im.size[0]}x{im.size[1]} RGB  {out.stat().st_size // 1024}KB'


def do_cutout(name: str) -> str:
    src = RAW / f'{name}.png'
    im = _paa.cut_background(Image.open(src).convert('RGBA'))
    bbox = im.getchannel('A').getbbox()
    if bbox is None:
        return f'{src.name}  SKIPPED -- fully transparent'
    covered = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1]) / (im.width * im.height)
    if covered > 0.995:
        return (f'{src.name}  REJECTED -- nothing was keyed out, so the background is '
                f'neither alpha nor the expected white/checkerboard. Look at it before regenerating.')
    im = im.crop(bbox)
    out = OUT / f'{name}.png'
    im.save(out, optimize=True)
    return f'{out.name}  {im.size[0]}x{im.size[1]} RGBA  {out.stat().st_size // 1024}KB'


def main() -> int:
    if not RAW.is_dir():
        print(f'no raw directory at {RAW}')
        return 1
    bad = 0
    for n in TILES:
        src = RAW / f'{n}.png'
        if not src.is_file():
            print(f'  {n}.png  MISSING from _raw -- generate it first')
            bad += 1
            continue
        print('  ' + do_tile(n))
    src = RAW / f'{CUTOUT}.png'
    if not src.is_file():
        print(f'  {CUTOUT}.png  MISSING from _raw -- generate it first')
        bad += 1
    else:
        line = do_cutout(CUTOUT)
        print('  ' + line)
        if 'REJECTED' in line:
            bad += 1
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
