#!/usr/bin/env python3
"""Render a deploy board to a high-resolution PNG from tools/dumpboard.ts output.

WARNING: THE GEOMETRY IS IMPORTED, NOT REIMPLEMENTED. Every hex centre, the tile
shape, the zone tags and the obstacle rectangles come from the TypeScript via
dumpboard.ts. This script only paints them. Re-deriving the lattice here would give
a picture that could quietly disagree with the game -- which is the whole failure
mode this project keeps hitting, and a preview you cannot trust is worse than none.

WARNING: PIL DRAWS POLYGONS WITH NO ANTIALIASING. The first version of this script
called ImageDraw.polygon straight onto the canvas, so every one of the six hex edges
came out a hard pixel staircase and the whole board read as cheap -- the jaggies were
a large part of "the hexagons don't look right", not the colour. Cells are now
rendered ONCE per zone into a tile at SS times scale and LANCZOS-downsampled, then
stamped at each centre. Supersampling the tile rather than the canvas is the cheap
version of the same quality: the tile is a few hundred pixels, the canvas is 4K.

Usage: npx tsx tools/dumpboard.ts wood-boards | python3 tools/drawboard.py out.png
"""
import json
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
PUBLIC = ROOT / 'public'

LONG_EDGE = 3840       # render 4K on the long side, whatever the arena's shape
SS = 4                 # tile supersample -- the antialiasing
FACE = 0.93            # face inset, matching deploy.css's transform:scale(.93)

# WARNING: THESE MIRROR deploy.css BY HAND -- the one thing this script does not
# import. Geometry is exported from the code so it cannot drift; colour is not, so if
# the stylesheet changes and this does not, the preview flatters or slanders a board
# that looks different in the browser. Change both together.
#
# Each zone is a THREE-STOP GRADIENT plus two rim colours, because that is what makes
# a cell read as a tile instead of a paper cut-out: light down the face, a bright lip
# on the three top edges, a dark one on the three bottom edges. Flat fills have no
# thickness and no light, and no amount of resolution fixes that.
ZONES = {
    #        top                  mid (46%)            bottom              lip                 shade
    'play':  ((132, 208, 255, 158), (34, 130, 224, 130), (12, 58, 122, 122), (222, 244, 255, 122), (3, 22, 52, 92)),
    'enemy': ((255, 128, 196, 150), (214, 44, 132, 122), (110, 16, 70, 115), (255, 205, 232, 112), (48, 4, 26, 87)),
    'board': ((226, 238, 255, 46), (146, 166, 194, 23), (66, 82, 106, 31), (255, 255, 255, 51), (0, 0, 0, 51)),
}
RECESS = (8, 11, 16, 128)  # the gap between tiles -- .dp-hex's own background


class Camera:
    """The tilt, mirrored from src/tamerengine/camera.ts.

    WARNING: THIS IS A RE-IMPLEMENTATION, WHICH IS THE ONE THING THIS SCRIPT TRIES NOT
    TO DO. It is unavoidable -- every prop's base has to be projected, and a table of
    pre-computed answers cannot cover arbitrary points. So dumpboard.ts ships REFERENCE
    OUTPUTS from the real project(), and the constructor reproduces them before
    anything is drawn. If camera.ts changes and this does not, the render fails loudly
    instead of quietly showing a board the game does not render.
    """

    def __init__(self, cam):
        self.d, self.sin, self.cos = cam['depth'], cam['sin'], cam['cos']
        self.fit, self.y_off = cam['fit'], cam['yOffset']
        self.height_ratio = cam['heightRatio']
        for (u, v), want in zip([(-0.5, -0.5), (0.5, 0.5), (0.2, -0.1)], cam['check']):
            got = self.project(u, v)
            for k in ('x', 'y', 's'):
                assert abs(got[k] - want[k]) < 1e-9, (
                    "drawboard.py's camera disagrees with camera.ts at "
                    "(%s,%s): %s %r != %r" % (u, v, k, got[k], want[k]))

    def project(self, u, v):
        s = self.d / (self.d - v * self.sin) * self.fit
        return {'x': u * s, 'y': v * self.cos * s, 's': s}


def solve8(rows, rhs):
    """Gaussian elimination -- the 8 perspective coefficients from 4 point pairs."""
    n = len(rhs)
    m = [list(r) + [b] for r, b in zip(rows, rhs)]
    for i in range(n):
        pv = max(range(i, n), key=lambda r: abs(m[r][i]))
        m[i], m[pv] = m[pv], m[i]
        for r in range(n):
            if r == i:
                continue
            f = m[r][i] / m[i][i]
            for c in range(i, n + 1):
                m[r][c] -= f * m[i][c]
    return [m[i][n] / m[i][i] for i in range(n)]


def perspective_coeffs(src, dst):
    """PIL wants the map from OUTPUT back to INPUT, so `dst` are the output corners."""
    rows, rhs = [], []
    for (sx, sy), (dx, dy) in zip(src, dst):
        rows.append([dx, dy, 1, 0, 0, 0, -sx * dx, -sx * dy])
        rhs.append(sx)
        rows.append([0, 0, 0, dx, dy, 1, -sy * dx, -sy * dy])
        rhs.append(sy)
    return solve8(rows, rhs)


def hexagon(cx, cy, tw, th, k=1.0):
    """A pointy-top hexagon: vertex top and bottom, flat left and right sides,
    corners at a quarter and three quarters of the height."""
    hw, hh = tw * k / 2, th * k / 2
    return [(cx, cy - hh), (cx + hw, cy - hh / 2), (cx + hw, cy + hh / 2),
            (cx, cy + hh), (cx - hw, cy + hh / 2), (cx - hw, cy - hh / 2)]


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def gradient(w, h, top, mid, bot):
    """Vertical three-stop ramp, built one pixel wide and stretched."""
    col = Image.new('RGBA', (1, h))
    for y in range(h):
        t = y / max(1, h - 1)
        col.putpixel((0, y), lerp(top, mid, t / 0.46) if t < 0.46
                     else lerp(mid, bot, (t - 0.46) / 0.54))
    return col.resize((w, h), Image.BILINEAR)


def cell_tile(key, tw, th):
    """One finished cell: dark recess, inset lit face, bevelled rim.

    Rendered at SS scale and downsampled, which is where the clean edges come from.
    """
    W, H = round(tw * SS), round(th * SS)
    top, mid, bot, lip, shade = ZONES[key]
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))

    # the recess: a full-size dark hexagon. The face sits inside it, so the ring left
    # showing IS the seam -- a real gap with a tile proud of it, not a drawn outline.
    m = Image.new('L', (W, H), 0)
    ImageDraw.Draw(m).polygon(hexagon(W / 2, H / 2, W, H), fill=255)
    img.paste(Image.new('RGBA', (W, H), RECESS), (0, 0), m)

    # the face
    fm = Image.new('L', (W, H), 0)
    ImageDraw.Draw(fm).polygon(hexagon(W / 2, H / 2, W, H, FACE), fill=255)
    img.paste(gradient(W, H, top, mid, bot), (0, 0), fm)

    # the bevel: lip along the three edges facing the light, shade along the other
    # three. Drawn as an overlay and masked to the face so it cannot bleed into the
    # seam.
    ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    p = hexagon(W / 2, H / 2, W, H, FACE)
    lw = max(2, round(H * 0.022))
    d.line([p[4], p[5], p[0], p[1]], fill=lip, width=lw, joint='curve')
    d.line([p[1], p[2], p[3], p[4]], fill=shade, width=lw, joint='curve')
    ov.putalpha(Image.composite(ov.getchannel('A'), Image.new('L', (W, H), 0), fm))
    img = Image.alpha_composite(img, ov)

    return img.resize((round(tw), round(th)), Image.LANCZOS)


def main() -> int:
    b = json.load(sys.stdin)
    cam = Camera(b['cam'])
    px = LONG_EDGE / max(b['w'], b['h'])

    # The FLAT board is rendered with a MARGIN, because the hex coverage runs past all
    # four walls and the tilt needs that overhang: the far edge tapers in, so the plane
    # has to reach further out than the wall to still fill the frame's far corners.
    # Cropping to the wall here would put the bare triangles straight back.
    MARGIN = 3.0
    mx = round(MARGIN * px)
    PW, PH = round(b['w'] * px) + 2 * mx, round(b['h'] * px) + 2 * mx

    # -- ground, tiled --------------------------------------------------------
    img = Image.new('RGBA', (PW, PH), (40, 38, 34, 255))
    g = Image.open(PUBLIC / b['ground'].lstrip('/')).convert('RGB')
    gs = round(b['h'] * px * 0.32)
    g = g.resize((gs, gs), Image.LANCZOS)
    for y in range(-gs, PH, gs):
        for x in range(-gs, PW, gs):
            img.paste(g, (x, y))

    # -- the hex board --------------------------------------------------------
    tw, th = b['tile']['w'] * px, b['tile']['h'] * px
    tiles = {(k, j): ImageEnhance.Brightness(cell_tile(k, tw, th)).enhance(1 + (j - 3) * 0.02)
             for k in ZONES for j in range(7)}
    for c in b['cells']:
        k = ('play' if c['zone'] == 'A' else 'enemy') if c['playable'] else 'board'
        if c['zone'] == 'neutral':
            k = 'board'
        t = tiles[(k, ((c['q'] * 5 + c['r'] * 3) % 7 + 7) % 7)]  # coprime with 7, see Deploy.tsx
        img.paste(t, (mx + round(c['x'] * px - tw / 2), mx + round(c['y'] * px - th / 2)), t)

    # -- shadows, which belong ON the ground ----------------------------------
    # Drawn BEFORE the warp, so the tilt foreshortens them exactly as it foreshortens
    # the board. That is most of why cover stops reading as pasted: a shadow that is
    # part of the floor is what says the thing is standing on the floor.
    sh = Image.new('RGBA', (PW, PH), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    for o in b['obstacles']:
        sd.ellipse([mx + o['x'] * px, mx + (o['y'] + o['h'] * 0.45) * px,
                    mx + (o['x'] + o['w']) * px, mx + (o['y'] + o['h'] * 1.35) * px],
                   fill=(0, 0, 0, 125))
    img = Image.alpha_composite(img, sh.filter(ImageFilter.GaussianBlur(px * 0.16)))

    # -- the arena's light ----------------------------------------------------
    cx, cy = PW / 2, PH * 0.42
    key = Image.new('RGBA', (PW, PH), (0, 0, 0, 0))
    ImageDraw.Draw(key).ellipse([cx - PW * .34, cy - PH * .29, cx + PW * .34, cy + PH * .29],
                                fill=(255, 247, 228, 40))
    img = Image.alpha_composite(img, key.filter(ImageFilter.GaussianBlur(min(PW, PH) * 0.11)))
    vig = Image.new('L', (PW, PH), 255)
    ImageDraw.Draw(vig).ellipse([PW / 2 - PW * .52, PH * .58 - PH * .46,
                                 PW / 2 + PW * .52, PH * .58 + PH * .46], fill=0)
    vig = vig.filter(ImageFilter.GaussianBlur(min(PW, PH) * 0.13)).point(lambda v: round(v * .26))
    img = Image.alpha_composite(img, Image.merge('RGBA', (Image.new('L', (PW, PH), 0),) * 3 + (vig,)))

    # -- tilt the ground ------------------------------------------------------
    BW, BH = b['w'] * px, b['h'] * px
    W, H = round(BW), round(BH * cam.height_ratio)

    def to_screen(u, v):
        p = cam.project(u, v)
        return (BW * (0.5 + p['x']), BH * (p['y'] - cam.y_off) + H / 2)

    um, vm = 0.5 + MARGIN / b['w'], 0.5 + MARGIN / b['h']
    src = [(0, 0), (PW, 0), (PW, PH), (0, PH)]
    dst = [to_screen(-um, -vm), to_screen(um, -vm), to_screen(um, vm), to_screen(-um, vm)]
    img = img.transform((W, H), Image.PERSPECTIVE, perspective_coeffs(src, dst), Image.BICUBIC)

    # -- cover: billboards STANDING UP out of the tilted ground ---------------
    # Anchored at the middle of the footprint's FRONT edge and scaled by the depth
    # there, so the same prop is smaller at the back of the arena than at the front.
    # It is NOT foreshortened -- it faces the camera. That is what a billboard is, and
    # it is why a side-on drawing is now the correct thing to draw.
    for o in sorted(b['obstacles'], key=lambda ob: ob['y'] + ob['h']):
        p = cam.project((o['x'] + o['w'] / 2) / b['w'] - 0.5, (o['y'] + o['h']) / b['h'] - 0.5)
        sx = BW * (0.5 + p['x'])
        sy = BH * (p['y'] - cam.y_off) + H / 2
        sp = Image.open(PUBLIC / o['sprite'].lstrip('/')).convert('RGBA')
        dw = max(1, round(o['w'] * px * p['s']))
        dh = max(1, round(dw * sp.height / sp.width))
        sp = sp.resize((dw, dh), Image.LANCZOS)
        img.paste(sp, (round(sx - dw / 2), round(sy - dh)), sp)

    out = sys.argv[1] if len(sys.argv) > 1 else 'board.png'
    img.convert('RGB').save(out)
    play = sum(1 for c in b['cells'] if c['playable'] and c['zone'] == 'A')
    print(f"{out}  {b['name']}  {b['w']}x{b['h']}  {W}x{H}px  "
          f"{len(b['cells'])} cells drawn, {play} yours", file=sys.stderr)
    return 0


if __name__ == '__main__':
    sys.exit(main())
