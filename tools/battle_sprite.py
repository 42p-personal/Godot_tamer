#!/usr/bin/env python3
"""Post-process a species' battle-sprite frames into an animation-ready set.

    python3 tools/battle_sprite.py <id> <idle> <walk1> <walk2> <walk3> <walk4> <strike>
    python3 tools/battle_sprite.py --check <id>        # inspect a finished set

White background -> transparent, trim, then place every frame on a 128x128
canvas with ONE SHARED SCALE and its feet on a FIXED BASELINE.

Two things here are load-bearing, and both are the opposite of what the
portrait pipeline does:

1. FOOT-ANCHORED, not bbox-centred. Centring each frame's bounding box is right
   for a lone still image and wrong for animation: a walk frame whose creature
   is a few pixels shorter gets re-centred, so the sprite bobs and slides
   between frames instead of walking.

2. ONE SCALE FOR THE WHOLE SPECIES, taken from the largest frame. Scaling each
   frame independently to "fill the canvas" makes the monster visibly grow and
   shrink as it animates — a lunging strike frame is wider than an idle, so
   fitting each one alone would shrink the strike. All six are measured
   together, then scaled by the same factor.
"""
import sys
from PIL import Image

SIZE = 128
BASELINE = 0.94   # feet sit this far down the canvas
FILL = 0.88       # the largest frame occupies this much of the canvas
THRESH = 26       # how close to white counts as background
FRAMES = ('idle', 'walk1', 'walk2', 'walk3', 'walk4', 'strike')
OUT_DIR = 'public/battle'


def fill_interior_white(im, thresh=THRESH):
    """Repaint near-white pixels that are NOT connected to the border.

    The generator sometimes renders the GAP between a creature's legs (or a
    pass-pose's gathered legs) as a white shape sealed inside the silhouette.
    The border flood-fill leaves it, because it isn't reachable from the edge,
    so it survives as a bright hole. This grows the surrounding colour inward to
    close it — a leg-gap is bordered by dark legs, so it fills dark and vanishes.
    Runs BEFORE to_transparent so the closed region is treated as body.
    """
    from collections import deque
    im = im.convert('RGBA')
    w, h = im.size
    px = im.load()

    def is_white(p):
        return p[0] >= 255 - thresh and p[1] >= 255 - thresh and p[2] >= 255 - thresh

    # mark border-connected white (the real background)
    outside = [[False] * h for _ in range(w)]
    q = deque([(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)]
              + [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)])
    while q:
        x, y = q.popleft()
        if not (0 <= x < w and 0 <= y < h) or outside[x][y] or not is_white(px[x, y]):
            continue
        outside[x][y] = True
        q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])

    interior = [(x, y) for x in range(w) for y in range(h)
                if is_white(px[x, y]) and not outside[x][y]]
    if not interior:
        return im, 0

    # iteratively pull in the nearest non-white neighbour colour
    interior_set = set(interior)
    for _ in range(max(w, h)):
        if not interior_set:
            break
        filled = []
        for (x, y) in interior_set:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and not is_white(px[nx, ny]) and px[nx, ny][3] > 0:
                    px[x, y] = px[nx, ny]
                    filled.append((x, y))
                    break
        if not filled:
            break
        for f in filled:
            interior_set.discard(f)
    return im, len(interior)


def to_transparent(im: Image.Image, thresh: int = THRESH) -> Image.Image:
    """Flood-fill the background inward from the border, so white INSIDE the
    creature (an eye, a tusk) survives."""
    im = im.convert('RGBA')
    w, h = im.size
    px = im.load()

    def is_bg(p):
        return p[0] >= 255 - thresh and p[1] >= 255 - thresh and p[2] >= 255 - thresh

    stack = [(x, 0) for x in range(w)] + [(x, h - 1) for x in range(w)]
    stack += [(0, y) for y in range(h)] + [(w - 1, y) for y in range(h)]
    seen = set()
    while stack:
        x, y = stack.pop()
        if (x, y) in seen or not (0 <= x < w and 0 <= y < h):
            continue
        seen.add((x, y))
        p = px[x, y]
        if p[3] == 0 or not is_bg(p):
            continue
        px[x, y] = (255, 255, 255, 0)
        stack.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    return im


def build(species_id: str, paths: list[str]) -> int:
    if len(paths) != len(FRAMES):
        print(f'ERROR: expected {len(FRAMES)} frames {FRAMES}, got {len(paths)}')
        return 2

    cut = []
    for p in paths:
        # Close any sealed white gaps (leg-gap artifacts) BEFORE the background
        # flood-fill, so they read as body rather than as holes punched in the
        # silhouette. Then remove the true (border-connected) background.
        raw, closed = fill_interior_white(Image.open(p))
        if closed:
            print(f'  {p}: closed {closed} interior white px')
        im = to_transparent(raw)
        bbox = im.getbbox()
        if not bbox:
            print(f'ERROR: {p} is empty after background removal')
            return 1
        cut.append(im.crop(bbox))

    # ONE scale for the set, from whichever frame is largest in either axis, so
    # nothing overflows the canvas and nothing changes size mid-animation.
    limit = SIZE * FILL
    scale = min(min(limit / c.width, limit / c.height) for c in cut)

    for name, im in zip(FRAMES, cut):
        new = (max(1, round(im.width * scale)), max(1, round(im.height * scale)))
        im = im.resize(new, Image.LANCZOS)
        canvas = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
        x = (SIZE - im.width) // 2                 # centred horizontally
        y = int(SIZE * BASELINE) - im.height       # FEET on the baseline
        canvas.paste(im, (x, max(0, y)), im)
        out = f'{OUT_DIR}/{species_id}-{name}.png'
        canvas.save(out)
        print(f'  {out}  content={im.size}  feet_y={int(SIZE * BASELINE)}')
    print(f'{species_id}: {len(FRAMES)} frames, shared scale {scale:.3f}')
    return 0


def check(species_id: str) -> int:
    """Verify a finished set is animation-safe."""
    ok = True
    feet = []
    for name in FRAMES:
        p = f'{OUT_DIR}/{species_id}-{name}.png'
        try:
            im = Image.open(p)
        except FileNotFoundError:
            print(f'  MISSING {p}')
            ok = False
            continue
        bb = im.getbbox()
        if im.size != (SIZE, SIZE):
            print(f'  {name}: WRONG CANVAS {im.size}')
            ok = False
        if bb:
            feet.append(bb[3])
            print(f'  {name}: bbox={bb} w={bb[2]-bb[0]} h={bb[3]-bb[1]}')
    if feet and max(feet) - min(feet) > 2:
        print(f'  FAIL: feet vary by {max(feet) - min(feet)}px — the sprite will bob')
        ok = False
    elif feet:
        print(f'  feet aligned within {max(feet) - min(feet)}px')
    print('OK' if ok else 'PROBLEMS FOUND')
    return 0 if ok else 1


def main() -> int:
    if len(sys.argv) >= 3 and sys.argv[1] == '--check':
        return check(sys.argv[2])
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    return build(sys.argv[1], sys.argv[2:])


if __name__ == '__main__':
    raise SystemExit(main())
