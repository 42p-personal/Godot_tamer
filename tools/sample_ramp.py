"""Build a 5-step pixel-art colour ramp for each species from its portrait.

Why not just quantise the portrait? Because picking the N most common quantised
colours and sorting them by luminance mixes hues: a brown gorilla painted against
a navy backdrop yields a ramp with a blue in the middle, and the sprite comes out
looking bruised. A ramp has to be COHERENT to read as one creature.

So instead: find the creature's dominant hue (circular mean, weighted by
saturation so grey pixels do not drag it), then GENERATE five steps in lightness
from it. Darks are shifted slightly cool and lights slightly warm, which is
standard pixel-art practice and is what stops a ramp looking like one colour with
the brightness turned up.
"""
from PIL import Image
import colorsys, math, json, sys

def ramp_for(path, k=5):
    im = Image.open(path).convert('RGBA')
    px = [p for p in im.get_flattened_data() if p[3] > 200]
    if not px: raise SystemExit('empty ' + path)
    # ⚠️ HUE HISTOGRAM PEAK, NOT CIRCULAR MEAN. A silverback has warm fur AND a
    # cool silver back; the circular mean of two opposite hues lands between
    # them and matches neither — it produced a PURPLE gorilla. The peak of a
    # saturation-weighted histogram picks the colour the creature actually is.
    BINS = 36
    hist = [0.0] * BINS
    sats = []; vals = []; hues = []
    for r, g, b, _ in px:
        h, s, v = colorsys.rgb_to_hsv(r/255, g/255, b/255)
        hist[int(h * BINS) % BINS] += s * s   # squared: confident pixels vote louder
        sats.append(s); vals.append(v); hues.append((h, s))
    peak = max(range(BINS), key=lambda i: hist[i] + 0.5*(hist[(i-1) % BINS] + hist[(i+1) % BINS]))
    lo, hi = (peak - 1) / BINS, (peak + 2) / BINS
    near = [h for h, s in hues if s > 0.12 and (lo % 1.0) <= h <= (hi % 1.0)] if lo >= 0 and hi <= 1 else []
    hue = (sum(near) / len(near)) if near else (peak + 0.5) / BINS
    sats.sort(); vals.sort()
    sat = sats[int(len(sats)*0.72)]          # upper-mid: the creature's colour,
    val = vals[int(len(vals)*0.70)]          # not its shadows
    # ⚠️ NO SATURATION FLOOR. A silverback gorilla is very nearly achromatic, so
    # its hue is pure noise; forcing a minimum saturation onto it produced a
    # PURPLE gorilla. If the creature has no colour, its ramp should have none.
    sat = min(0.82, sat if sat > 0.14 else 0.0)
    val = min(0.92, max(0.40, val))

    out = []
    for i in range(k):
        t = i / (k - 1)
        # Reaches well past `val` at the top: these sprites sit on a dark
        # battlefield, and a ramp that stops at the creature's average lightness
        # has no highlight left to separate it from the ground.
        # ⚠️ The FLOOR matters as much as the ceiling. A ramp starting at 0.34
        # of the creature's lightness put its darkest mass within a few points
        # of the battlefield's own background, and the silhouette dissolved.
        v = val * (0.48 + 1.02 * t)           # dark -> light
        s = sat * (1.12 - 0.42 * t)          # highlights desaturate
        h = (hue + (t - 0.5) * 0.045) % 1.0  # darks cool, lights warm
        r, g, b = colorsys.hsv_to_rgb(h, min(1, s), min(1, v))
        out.append('#%02x%02x%02x' % (int(r*255), int(g*255), int(b*255)))
    return out

if __name__ == '__main__':
    print(json.dumps({i: ramp_for(f'public/sprites/{i}.png') for i in sys.argv[1:]}, indent=1))
