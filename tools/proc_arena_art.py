#!/usr/bin/env python3
"""Post-process generated arena art into the shapes the renderer wants.

Two kinds, two treatments — see docs/ART_PIPELINE.md, which makes the same point
about portraits vs battle sprites:

  ground-*  -> JPEG, square, 1254px, matching public/field/arena-grass.jpg.
               JPEG because it is a full-bleed opaque texture where a 2MB PNG buys
               nothing a player can see; the tile is repeated dozens of times per
               frame so its weight is the one that matters.

  prop-*    -> PNG RGBA, alpha-trimmed to the object, max 256px on the long side,
               matching public/field/boulder.png (256x240 RGBA).

WARNING: PROPS ARE TRIMMED TO THEIR ALPHA BBOX, AND THAT IS LOAD-BEARING. The
renderer stretches each prop to its obstacle's exact rectangle, because the
rectangle is what the engine collides against. Any transparent margin left in the
file therefore becomes a gap between the drawn cover and the real cover -- the
player sees a gap they cannot walk through, or walks into an edge that looks clear.

WARNING: A PROP WITH NO ALPHA IS REJECTED, NOT SILENTLY ACCEPTED. A generator that
returns an opaque background produces a prop with a visible box around it; that
must fail here rather than ship looking like a rendering fault.

Usage: python3 tools/proc_arena_art.py            (processes everything in _raw)
"""
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageEnhance

FIELD = Path(__file__).resolve().parent.parent / 'public' / 'field'
RAW = FIELD / '_raw'
GROUND_PX = 1254
PROP_MAX = 256


# ⚠️ SHARED SURFACES ARE EXPOSURE-CORRECTED; LEAGUE GROUNDS ARE NOT, AND THAT ASYMMETRY IS
# THE POINT. A league's ground is lit by ITS OWN lamp, tuned against it in look.ts, so its
# brightness is a design decision -- Copper's smelt yard at 42 is meant to be dark and Tin's
# blowing house at 175 is meant to be bleached. A shared surface has to sit under all ten
# lamps, so it cannot be bright: sand came back at 193 against a house median of 105 and
# clipped to flat white under Bronze's key at 4.4, taking the raked texture with it.
#
# ⚠️ AND THE CHECK BELOW MEASURED SATURATION ONLY, so it passed sand at 0.10 while the
# image was three-quarters blown out. A near-white floor is desaturated BECAUSE it is
# clipped; the two numbers have to be read together or the quiet ones hide the loud ones.
# ⚠️ AND ONE LEAGUE GROUND IS ON THE LIST TOO, WHICH THE PARAGRAPH ABOVE SAYS SHOULD NOT
# HAPPEN. `ground-sawdust` came back at 0.44 saturation and 145 luminance — the loudest
# floor in the game after Bronze's — and the check flagged it every run since Bronze while
# nobody acted. In the Timberyard render it blazed yellow and swallowed the single log
# stack standing on it. The rule stands (a league's brightness is a design decision); the
# EXCEPTION is that the generator overshot, which is the whole reason the check exists.
# Correcting the overshoot is not overriding the design.
#
# ⚠️ SILVER'S TWO CAME BACK AT 210 AND 215 AGAINST A HOUSE MEDIAN OF 103, which is the
# same overshoot as sand and for the same reason: ask the generator for "chalky",
# "bone-ash" or "pale limestone" and it returns something nearer paper than stone. Silver
# is MEANT to be the palest circuit, so these are corrected to ~120 rather than to the
# median — brighter than every league ground except Tin's blowing house, and not clipped.
SURFACE_EXPOSURE = {
    'ground-sand': 0.57, 'ground-concrete': 0.74, 'ground-flagstone': 0.81,
    'ground-sawdust': 0.74,
    'ground-assayfloor': 0.55, 'ground-cupelhearth': 0.55,
    # ⚠️ GOLD OVERSHOT ON BOTH AXES AT ONCE, WHICH NO PREVIOUS LEAGUE MANAGED. Ask for
    # "warm honey sandstone" and the generator returns 186 luminance at 0.53 SATURATION —
    # the loudest texture this project has produced, half again past `ground-sawdust`'s
    # original 0.44. Gold is meant to be the rich league, not the orange one; a floor that
    # saturated leaves no headroom for the gilt trim the venue puts on top of it.
    'ground-parterre': 0.61, 'ground-gildedcourt': 0.62,
    # ⚠️ ALABASTER IS THE POOL'S PALE ONE AND CAME BACK AT 220 — near paper. Corrected to
    # ~130: still the brightest ground in the game after Tin's blowing house, which is what
    # the stone is for, but with its banding intact instead of clipped away.
    # ⚠️ BASALT IS DELIBERATELY NOT ON THIS LIST at luminance 36. It is the darkest floor in
    # the game on purpose and its lamp is the hardest in the pool to match — see look.ts. A
    # dark ground is a design decision; a BLOWN one is a generator overshoot, and only the
    # second is this table's business.
    'ground-alabaster': 0.58,
    # ⚠️ BLOCK 2 OVERSHOT ON THE TWO THE SCRIPT'S OWN HEADER PREDICTED. `gen_grand_grounds2`
    # warns in writing that "ochre" and "violet" come back saturated and that pale stones come
    # back near paper — and travertine returned at luminance 201, jasper at 0.52 SATURATION,
    # the joint-loudest texture this project has produced. Knowing the failure in advance does
    # not prevent it; the table is what prevents it.
    'ground-travertine': 0.60,
    # ⚠️ BLOCK 3 CAME BACK BRIGHT ACROSS THE BOARD — mosaic 159, rose 159, onyx 140 — and
    # the reason is in the prompts: "cream", "off-white", "dusty pink" and "tesserae" all ask
    # for pale materials, and the generator answers the adjective rather than the stone. Onyx
    # is left highest of the three on purpose: cream-to-near-black WITHIN a slab is the only
    # thing that stone has, and pulling it down closes the dark bands.
    'ground-mosaic': 0.72, 'ground-rosestone': 0.72, 'ground-onyx': 0.84,
}

# ⚠️ SATURATION BELONGS IN THE PIPELINE, NOT IN A HAND-EDITED JPEG, AND THAT WAS LEARNED
# BY LOSING ONE. `ground-sawdust` was pulled from 0.44 to 0.29 by editing the published
# file directly; the very next `proc_arena_art` run rebuilt it from `_raw` and put the
# 0.44 straight back. Anything under `public/field/` is BUILD OUTPUT — a correction that
# does not live in this table is a correction with a half-life of one run.
SURFACE_SATURATION = {
    'ground-sawdust': 0.60,     # 0.44 -> 0.29, the loudest floor in the game, on Wood
    'ground-gildedcourt': 0.42,  # 0.53 -> ~0.22; warm and rich, not orange
    'ground-jasper': 0.44,       # 0.52 -> ~0.23; earthy ochre, not mustard
    'ground-verdite': 0.55,      # 0.31 -> ~0.17; olive, not moss
}

# ⚠️ THE THIRD KNOB, AND ONYX IS WHY IT HAD TO EXIST. Exposure moves a floor up or down and
# saturation moves it toward grey; neither touches the SPREAD between a texture's lightest
# and darkest pixel, and that is the axis a banded stone lives on. Onyx came back with
# cream-to-near-black sweeping across every slab and drew as hard diagonal streaks that were
# read BEFORE the cover standing on them — the same legibility failure as Copper's flattened
# Ingot Yard and Gold's blown gilded court, arriving down a third road.
# ⚠️ AND TILE SCALE COULD NOT FIX IT. Tightening the tile from 32% to 20% made the bands
# smaller without making them quieter, because the contrast is in the IMAGE, not in how often
# it repeats. Two knobs had been tried on a problem neither could reach.
SURFACE_CONTRAST = {
    'ground-onyx': 0.58,        # the banding becomes marble instead of stripes
}


def do_ground(src: Path) -> str:
    im = Image.open(src).convert('RGB')
    if im.width != im.height:
        s = min(im.size)
        left, top = (im.width - s) // 2, (im.height - s) // 2
        im = im.crop((left, top, left + s, top + s))
    im = im.resize((GROUND_PX, GROUND_PX), Image.LANCZOS)
    k = SURFACE_EXPOSURE.get(src.stem)
    if k:
        im = im.point(lambda v, k=k: int(v * k))
    sat = SURFACE_SATURATION.get(src.stem)
    if sat:
        im = ImageEnhance.Color(im).enhance(sat)
    con = SURFACE_CONTRAST.get(src.stem)
    if con:
        im = ImageEnhance.Contrast(im).enhance(con)
    out = FIELD / (src.stem + '.jpg')
    im.save(out, quality=88, optimize=True)
    return f'{out.name}  {im.size[0]}x{im.size[1]} RGB  {out.stat().st_size // 1024}KB'


def _background_mask(a):
    """Pixels that LOOK like backdrop, before asking whether they are connected to it.

    WARNING: THE GENERATOR FAKES TRANSPARENCY TWO DIFFERENT WAYS, and both must be
    handled or three assets in four come out with a box around them. Asked for a
    "transparent background" it returned:
      * a flat chroma-key GREEN (~18,241,15) for one prop, and
      * a literally DRAWN light-grey CHECKERBOARD for the other three — the
        transparency pattern itself, painted as pixels.
    Neither is alpha. Do not assume a future batch picks the same one.
    """
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    mx, mn = np.maximum(np.maximum(r, g), b), np.minimum(np.minimum(r, g), b)
    green = (g > 90) & (g > np.maximum(r, b) * 1.55)
    # ⚠️ AND MAGENTA, BECAUSE GREENERY CANNOT BE SHOT ON GREEN. Every prop so far was
    # timber, stone or metal, so a chroma-key green was safely absent from the subject.
    # A tree is not: keyed on green, the flood fill walks straight out of the backdrop
    # and into the foliage, and both scenery sprites came back REJECTED with nothing
    # removed. Magenta is the standard second key for exactly this reason — it is the
    # colour no plant, rock or plank contains. `gen_scenery.sh` asks for it by name.
    magenta = (r > 90) & (b > 90) & (np.minimum(r, b) > g * 1.55)
    # The checkerboard is near-neutral and bright; both of its squares qualify.
    #
    # ⚠️ THE THRESHOLD REACHES DOWN INTO THE SHADOW ON PURPOSE (176, not 200). The
    # prompt asks for a soft contact shadow, which the generator drew ON TOP of the
    # checkerboard — so it keys as mid-grey and survives as a pale halo under every
    # prop, which on dark ground reads as a smudge rather than a shadow. Reaching
    # lower is only safe BECAUSE the fill is border-connected: the equally pale cut
    # ends of the logs and the bleached top of the stump are interior, never touched.
    checker = (mx - mn < 30) & (mx > 176)
    return green | magenta | checker


def cut_background(im: Image.Image) -> Image.Image:
    """Remove the faked backdrop, keeping anything not connected to the border.

    WARNING: FLOOD-FILLED FROM THE EDGES, NOT KEYED GLOBALLY. A global colour test
    also erases every pale, low-saturation pixel INSIDE the object — the cut face of
    a log, the bleached top of a stump, a specular highlight on wet wood — punching
    holes through the middle of the prop. Only backdrop that touches the frame edge
    is backdrop.

    ⚠️ EXCEPT MAGENTA, WHICH IS KEYED GLOBALLY, AND THE FIRST PIERCED PROP IS WHY. Every
    prop until now was a solid lump — a barrel, a wall, a stump — so "backdrop touches the
    edge" was always true. A COLONNADE has holes THROUGH it: the gaps between the shafts are
    enclosed by the architrave above, the stylobate below and a column either side, so the
    flood fill never reaches them and both runs came back with solid magenta panels between
    every column. Seeing through the gaps is the entire reason this prop exists.
    ⚠️ AND ONLY MAGENTA. The rule above still holds for the other two keys: the checkerboard
    is near-NEUTRAL, so keying it globally would punch holes through every pale interior the
    warning lists, and the green key would eat the ivy on `vinewall`. Magenta is the one
    backdrop colour that cannot occur in dressed stone, timber, metal or foliage — which is
    exactly why `gen_props_tin.sh` started asking for it.
    """
    a = np.array(im)
    h, w = a.shape[:2]
    cand = _background_mask(a)
    r0, g0, b0 = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    magenta = (r0 > 90) & (b0 > 90) & (np.minimum(r0, b0) > g0 * 1.55)

    # Iterative flood fill from the border across `cand`, by repeated dilation
    # intersected with the candidate set — vectorised, so no per-pixel Python loop.
    reach = np.zeros((h, w), bool)
    reach[0, :] |= cand[0, :]; reach[-1, :] |= cand[-1, :]
    reach[:, 0] |= cand[:, 0]; reach[:, -1] |= cand[:, -1]
    while True:
        grown = reach.copy()
        grown[1:, :] |= reach[:-1, :]
        grown[:-1, :] |= reach[1:, :]
        grown[:, 1:] |= reach[:, :-1]
        grown[:, :-1] |= reach[:, 1:]
        grown &= cand
        if grown.sum() == reach.sum():
            break
        reach = grown

    reach |= magenta
    a[..., 3] = np.where(reach, 0, 255)

    # DESPILL. Keying alone leaves a green rim on every anti-aliased edge, which on a
    # dark battlefield reads as a glow around the prop. Only pixels that survived are
    # touched, so genuinely green things inside the object are left alone.
    keep = ~reach
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    mx = np.maximum(r, b)
    spill = keep & (g > mx + 8)
    a[..., 1] = np.where(spill, np.minimum(g, mx + 8), g).astype(np.uint8)
    return Image.fromarray(a, 'RGBA')


def do_prop(src: Path) -> str:
    im = cut_background(Image.open(src).convert('RGBA'))
    bbox = im.getchannel('A').getbbox()
    if bbox is None:
        return f'{src.name}  SKIPPED — fully transparent'
    covered = (bbox[2] - bbox[0]) * (bbox[3] - bbox[1]) / (im.width * im.height)
    if covered > 0.995:
        return (f'{src.name}  REJECTED — nothing was keyed out, so the background is '
                f'neither alpha nor the expected green. Look at it before regenerating.')
    im = im.crop(bbox)
    scale = PROP_MAX / max(im.size)
    if scale < 1:
        im = im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))),
                       Image.LANCZOS)
    out = FIELD / (src.stem + '.png')
    im.save(out, optimize=True)
    return f'{out.name}  {im.size[0]}x{im.size[1]} RGBA  {out.stat().st_size // 1024}KB'


def main() -> int:
    if not RAW.is_dir():
        print(f'no raw directory at {RAW}')
        return 1
    raws = sorted(RAW.glob('*.png'))
    if not raws:
        print('no raws to process')
        return 1
    bad = 0
    for src in raws:
        if src.stem.startswith('ground-'):
            line = do_ground(src)
        elif src.stem.startswith('prop-'):
            line = do_prop(src)
        else:
            line = f'{src.name}  SKIPPED — name must start with ground- or prop-'
        if 'REJECTED' in line:
            bad += 1
        print('  ' + line)
    # WARNING: THIS CALL WENT MISSING ONCE AND THE CHECK RAN ZERO TIMES. The function was
    # written, documented and committed, and main() returned before reaching it -- so the
    # palette comparison silently did nothing for every batch after Bronze, which is the
    # exact failure mode ("a guard that fails loudly beats a bug that ships silently") the
    # check was built to prevent. Found only because a new batch of five floors produced
    # no palette table at all.
    check_ground_palette(FIELD)
    return 1 if bad else 0


def check_ground_palette(pub):
    """WARNING: A TEXTURE ONLY READS AS WRONG NEXT TO THE OTHERS.

    Bronze's first ground came back at 0.57 saturation against a house level of 0.21 --
    nearly three times as punchy as every other floor in the game. On its own it looked
    like a nice foundry floor; in the 3D scene it blazed orange and swallowed the cover
    standing on it. The generator does not reliably honour "muted palette", and there is
    no way to catch that by eyeballing one image, so it gets compared to its neighbours
    here, where every ground passes through anyway.
    """
    from PIL import Image, ImageStat
    rows = []
    for f in sorted(pub.glob('ground-*.jpg')):
        im = Image.open(f).convert('RGB')
        r, g, b = ImageStat.Stat(im).mean
        lum = ImageStat.Stat(im.convert('L')).mean[0]
        rows.append((f.name, (max(r, g, b) - min(r, g, b)) / max(1.0, max(r, g, b)), lum))
    if len(rows) < 3:
        return
    med = sorted(s for _, s, _ in rows)[len(rows) // 2]
    medl = sorted(v for _, _, v in rows)[len(rows) // 2]
    print()
    print('ground palette (median saturation %.2f, luminance %.0f):' % (med, medl))
    for name, s, lum in rows:
        # WARNING: FLAGS THE LOUD ONES ONLY, AND EVEN THEN AS A QUESTION. Running this
        # for the first time called out blowinghouse (0.01), washfloor (0.05) and sawdust
        # (0.44) -- and at least two of those are DESIGN: Tin is meant to be cold and
        # nearly colourless where Copper is fire, and themes.ts says so in as many words.
        # A ground quieter than its neighbours is a choice; one LOUDER than all of them
        # is usually the generator ignoring "muted palette", which is what happened to
        # Bronze at 0.57. So only the high side is called out, and only as "look at this".
        flag = '  <-- louder than the rest; check it against the others' if s > med * 1.6 else ''
        # ⚠️ LUMINANCE IS THE SECOND HALF OF THE SAME QUESTION. Sand passed the saturation
        # test at 0.10 and was still wrong -- it was blown out, and a blown-out floor is
        # desaturated because it is clipped. A LEAGUE ground may be bright by design; a
        # shared surface may not, so this is a look-at-it note rather than a failure.
        if lum > medl * 1.25:
            flag += '  <-- brighter than the rest' if not flag else ' AND brighter'
        print('  %-28s %.2f  lum %5.1f%s' % (name, s, lum, flag))


if __name__ == '__main__':
    sys.exit(main())
