#!/usr/bin/env python3
"""Assemble a numbered frame sequence from .shots/ into a looping GIF.

Pairs with vite.config.ts's dev-only /__shot route and scene3d.ts's `setCamera`
hook: the browser steps the camera, posts each frame as a PNG, and this stitches
them. It exists because a still image cannot answer "is that actually 3D?" -- the
only thing that settles it is watching the thing move.

WARNING: THE FRAME LOOP MUST BE A CLOSED CYCLE, NOT A SWEEP. Capture with the camera
on a full sine (az = A*sin(2*pi*t)) so the last frame flows back into the first. A
linear pan from one end to the other snaps on loop, which reads as a broken capture
rather than a moving camera.

Usage: python3 tools/makegif.py orbit out.gif [width] [ms-per-frame]
"""
import sys
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    prefix = sys.argv[1] if len(sys.argv) > 1 else 'orbit'
    out = sys.argv[2] if len(sys.argv) > 2 else 'out.gif'
    width = int(sys.argv[3]) if len(sys.argv) > 3 else 720
    ms = int(sys.argv[4]) if len(sys.argv) > 4 else 70

    files = sorted((ROOT / '.shots').glob(f'{prefix}-*.png'))
    if not files:
        print(f'no frames matching {prefix}-*.png', file=sys.stderr)
        return 1

    frames = []
    for f in files:
        im = Image.open(f).convert('RGB')
        im = im.resize((width, round(width * im.height / im.width)), Image.LANCZOS)
        # WARNING: ONE SHARED PALETTE, QUANTISED PER FRAME FROM THE SAME BASE. Letting
        # each frame pick its own adaptive palette makes the whole image shimmer between
        # frames -- every flat surface crawls, because the colours it is approximated
        # with change every 70ms. Deriving one palette from the middle frame and mapping
        # the rest onto it keeps the scene still while the camera moves.
        frames.append(im)

    colors = int(sys.argv[5]) if len(sys.argv) > 5 else 160
    base = frames[len(frames) // 2].quantize(colors=colors, method=Image.MEDIANCUT)
    # WARNING: NO DITHER. Floyd-Steinberg is the right default for a still, but across
    # frames its error diffusion is recomputed from scratch every time, so the speckle
    # pattern changes on every frame and every smooth surface -- which here is most of
    # the arena floor -- crawls with noise. A flat mapping bands slightly and holds
    # perfectly still, and still beats sparkly on a 70ms loop.
    pal = [f.quantize(palette=base, dither=Image.NONE) for f in frames]

    # WARNING: disposal=1, NOT 2, AND ON A LOCKED CAMERA IT IS WORTH MEGABYTES. Disposal
    # 2 restores the background before each frame, so every frame has to be a FULL image;
    # disposal 1 leaves the previous frame in place, which lets the encoder ship only the
    # rectangle that actually changed. When the camera is fixed and six sprites are the
    # only things moving, that is a few percent of the picture -- the same 66 frames went
    # from 13 MB to a fraction of it with no loss of quality at all.
    # It is the WRONG choice for a moving camera, where every pixel changes anyway.
    pal[0].save(out, save_all=True, append_images=pal[1:], duration=ms, loop=0,
                optimize=True, disposal=1)
    size = Path(out).stat().st_size
    print(f'{out}  {len(pal)} frames  {pal[0].size[0]}x{pal[0].size[1]}  '
          f'{size / 1024:.0f} KB', file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
