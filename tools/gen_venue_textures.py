#!/usr/bin/env python3
"""VENUE TEXTURE GENERATION for the Godot arena (monster-tamer/assets/arena*).

Run:  python3 tools/gen_venue_textures.py            # write everything
      python3 tools/gen_venue_textures.py --report   # measure only, write nothing

WHAT THIS FIXES, MEASURED
-------------------------
Before this ran, the Godot arena had FIVE league ground/backdrop pairs for an ELEVEN
league ladder, and nine obstacle kinds sharing SIX dressing textures. That is why every
league looked the same and cover looked bare.

WARNING -- MOST OF THE "MISSING" ART WAS NOT MISSING. This project's signature failure is
work that is already built while documented as missing (ten recorded instances; this is
the eleventh and twelfth). Counted from the filesystem, the React tree already holds:

  * public/backgrounds/  -- ALL ELEVEN painted league backdrops (wood .. tamers-apex).
    Only five had ever been copied into the Godot project.
  * public/field/        -- THIRTY-FOUR authored, league-themed ground tiles, generated
    through ART_PIPELINE.md Route B (codex image_gen) when the subscription was live.
    Godot was using none of them.

So the primary route here is NOT generation, it is INHERITANCE: take the authored art the
studio already paid for, repair it, grade it and file it under the names `scripts/art.gd`
asks for. Only the cover dressing -- which never existed as tiling material, only as 2D
prop cutouts that a 3D box cannot wear -- is synthesised.

THE THREE CORRECTIONS APPLIED ON THE WAY IN
-------------------------------------------
1. SEAMS. A tile whose wrap error exceeds its interior gradient shows a grid line across
   the floor. Measured before: wood 12.0/13.3 against an interior of 7.0; wall-timber
   7.9/26.2 against 3.8 -- a hard horizontal band up every prop in the game. `_tileable`
   rolls the image by half (which makes the outer edges continuous by construction, since
   they were interior neighbours) and heals the cross that lands in the middle.

2. VALUE. THE FLOOR SITS UNDER THE MONSTERS, so it must sit under them in VALUE too.
   Measured before: bronze-ground luminance 225, silver 235, platinum 219 -- three of five
   league floors were near-white, brighter than any creature standing on them, which is
   why cover and bodies both washed out. Every ground is graded into GROUND_LUMA_BAND.

3. SATURATION. docs/ART_DIRECTION.md: house saturation is ~0.21, and Bronze once shipped a
   0.57 floor that "blazed orange and swallowed the cover on it". Grounds are pulled toward
   the house level only when they are LOUDER than it -- a quiet league (Tin is designed
   nearly colourless) is a design choice and is left alone, exactly as
   proc_arena_art.py:check_ground_palette argues.

DETERMINISM: every synthesised tile is seeded from its own name, so re-running produces
byte-comparable output. This is presentation art, not sim code, but reproducibility is what
makes a regeneration reviewable.
"""

from __future__ import annotations

import argparse
import os
import sys

import numpy as np
from PIL import Image, ImageStat

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIELD = os.path.join(ROOT, "public", "field")
BACKDROPS = os.path.join(ROOT, "public", "backgrounds")
OUT_ARENAS = os.path.join(ROOT, "monster-tamer", "assets", "arenas")
OUT_ARENA = os.path.join(ROOT, "monster-tamer", "assets", "arena")

TILE = 1024
# The floor is under the monsters, so it is under them in value. Nothing above 140.
GROUND_LUMA_BAND = (62.0, 132.0)
HOUSE_SAT = 0.21


# ── the ladder ───────────────────────────────────────────────────────────────
# WARNING: SOURCED FROM src/tamerengine/themes.ts, WHICH IS THE AUTHORITY ON WHAT A LEAGUE
# IS MADE OF -- not invented here. Each league takes ONE of its own authored themes, chosen
# for the material identity its section comment states in as many words ("Copper is the
# stuff copper is made FROM", "Iron is the FORGE -- hotter than Copper and blacker"). The
# four grand-circuit leagues share a twenty-theme stone pool, so each takes a DIFFERENT
# stone: those leagues cannot be told apart by team size (all 5v5) or by board, so colour
# and stone are the only channel left.
LEAGUE_GROUND = {
	"wood":        ("ground-plankyard.jpg",   "boarded ring -- the league is named after timber"),
	"copper":      ("ground-smeltyard.jpg",   "smelting yard -- copper is fire and slag"),
	"tin":         ("ground-blowinghouse.jpg", "blowing house -- Tin is cold and near-colourless BY DESIGN"),
	"bronze":      ("ground-alloyfloor.jpg",  "poured alloy -- the two-parent league"),
	"iron":        ("ground-forgefloor.jpg",  "forge floor -- hotter than Copper and blacker"),
	"silver":      ("ground-cupelhearth.jpg", "cupelling hearth -- assay-pale, still not white"),
	"gold":        ("ground-gildedcourt.jpg", "gilded court -- the first league that shows off"),
	"platinum":    ("ground-alabaster.jpg",   "alabaster -- grand circuit, pale stone"),
	"masters":     ("ground-porphyry.jpg",    "porphyry -- grand circuit, imperial purple-red"),
	"tamer-elite": ("ground-onyx.jpg",        "onyx -- grand circuit, dark and formal"),
	"tamers-apex": ("ground-mosaic.jpg",      "mosaic court -- the last venue on the ladder"),
}

# `scripts/art.gd` reads `<slug>-backdrop.jpg`; the React tree files them by bare slug.
LEAGUE_BACKDROP = {slug: slug + ".jpg" for slug in LEAGUE_GROUND}

# Real art already in the Godot tree. Repaired, never regenerated -- see run() step 3a.
EXISTING_DRESSING = [
	"barrel-wood.jpg", "crate-wood.jpg", "wall-timber.jpg", "wall-stone.jpg",
	"stands-crowd.jpg",
]


# ── seamlessness ─────────────────────────────────────────────────────────────
def _quietest_cut(a: np.ndarray, axis: int) -> int:
	"""Index of the smoothest adjacent line pair on `axis` -- where to put the tile edge.

	WARNING: ROLLING BY HALF IS NOT GOOD ENOUGH, AND THE MEASUREMENT SAYS SO. wall-timber's
	repair made its wrap WORSE (26.2 -> 30.4) because the plank butt-join happened to sit at
	mid-height, so a blind half-roll moved the single hardest edge in the texture onto the
	tile boundary. The edge should land where the texture is QUIETEST; everything else about
	the method is unchanged.
	"""
	if axis == 1:
		d = np.abs(a[:, 1:] - a[:, :-1]).mean(axis=(0, 2))
	else:
		d = np.abs(a[1:] - a[:-1]).mean(axis=(1, 2))
	# Ignore the outermost eighth: cutting there barely moves the existing edge.
	n = d.shape[0]
	m = n // 8
	return int(np.argmin(d[m:n - m])) + m + 1


def _heal_band(a: np.ndarray, axis: int, band: int, at: int) -> np.ndarray:
	"""Cross-fade the discontinuity sitting at the centre of `axis` with its mirror.

	The mirror is continuous ACROSS the seam by construction (it is the same pixels read
	the other way), so a linear ramp between image and mirror is exactly zero-gradient at
	the seam line while preserving the texture's own statistics a few pixels out. A blur
	would also remove the seam and would leave a soft stripe -- which reads as a stripe.
	"""
	n = a.shape[axis]
	band = min(band, at, n - at)
	if band < 4:
		return a
	lo, hi = at - band, at + band
	sl = [slice(None)] * a.ndim
	sl[axis] = slice(lo, hi)
	strip = a[tuple(sl)].copy()
	mirror = np.flip(strip, axis=axis)
	ramp = np.abs(np.linspace(-1.0, 1.0, hi - lo))  # 1 at the edges, 0 at the seam
	shape = [1] * a.ndim
	shape[axis] = hi - lo
	w = ramp.reshape(shape)
	a[tuple(sl)] = strip * w + mirror * (1.0 - w)
	return a


def _tileable(im: Image.Image, band: int = 96) -> Image.Image:
	"""Make a texture wrap. Roll by half, then heal the cross that lands in the middle.

	WARNING: THE ROLL IS THE PART THAT ACTUALLY FIXES THE EDGE, and it is easy to get
	backwards. After rolling by w/2, column 0 and column w-1 are the two pixels that were
	interior neighbours around the old centre -- so the outer wrap is continuous for free,
	permanently, and only the newly-central seam needs work.
	"""
	a = np.asarray(im.convert("RGB")).astype(np.float64)
	h, w = a.shape[:2]
	cx, cy = _quietest_cut(a, 1), _quietest_cut(a, 0)
	a = np.roll(a, (-cy, -cx), axis=(0, 1))
	# The OLD tile edge now sits at `n - cut`; that is the discontinuity to heal, not the middle.
	b = min(band, h // 4, w // 4)
	a = _heal_band(a, 1, b, w - cx)
	a = _heal_band(a, 0, b, h - cy)
	return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def seam_stats(im: Image.Image) -> tuple[float, float, float]:
	"""Wrap error on each axis, and the bar it has to clear.

	WARNING: THE OBVIOUS METRIC IS THE WRONG ONE, and it cost a round of chasing ghosts.
	Comparing the wrap error to the MEAN interior gradient condemns any texture with strong
	local edges: a stone course line landing on the tile boundary reads as a 25-vs-5
	"failure" while being the same jump the texture makes twenty times internally. The bar
	is therefore the 95th percentile of adjacent-line differences -- a wrap no worse than
	the texture's own hardest internal edge is not a seam, it is a course.
	"""
	a = np.asarray(im.convert("RGB")).astype(float)
	ex = float(np.abs(a[:, 0] - a[:, -1]).mean())
	ey = float(np.abs(a[0] - a[-1]).mean())
	cols = np.abs(a[:, 1:] - a[:, :-1]).mean(axis=(0, 2))
	rows = np.abs(a[1:] - a[:-1]).mean(axis=(1, 2))
	bar = float(np.percentile(np.concatenate([cols, rows]), 95))
	return ex, ey, bar


def palette_stats(im: Image.Image) -> tuple[float, float]:
	rgb = im.convert("RGB")
	r, g, b = ImageStat.Stat(rgb).mean
	lum = ImageStat.Stat(rgb.convert("L")).mean[0]
	sat = (max(r, g, b) - min(r, g, b)) / max(1.0, max(r, g, b))
	return lum, sat


# ── grading ──────────────────────────────────────────────────────────────────
def _grade(im: Image.Image, band: tuple[float, float], sat_ceiling: float) -> Image.Image:
	"""Pull luminance into `band` and saturation down to `sat_ceiling` -- never up.

	WARNING: ONE-SIDED ON PURPOSE. A ground QUIETER than the house level is a league's
	identity (Tin), and "fixing" it would erase the design. A ground LOUDER than the house
	level is the generator ignoring "muted palette" -- the failure that shipped Bronze at
	0.57. Same asymmetry proc_arena_art.py already argues for, applied instead of printed.
	"""
	a = np.asarray(im.convert("RGB")).astype(np.float64)
	lum = a @ np.array([0.299, 0.587, 0.114])
	mean = float(lum.mean())
	lo, hi = band
	target = min(max(mean, lo), hi)
	if abs(target - mean) > 0.5:
		# Gamma rather than a multiply: a multiply on a bright floor clips the highlights
		# and a clipped floor is a DESATURATED floor, which is the second half of the same
		# bug (sand "passed the saturation test at 0.10 and was still wrong").
		g = np.log(max(target, 1.0) / 255.0) / np.log(max(mean, 1.0) / 255.0)
		a = 255.0 * np.power(np.clip(a / 255.0, 0.0, 1.0), g)
	mx, mn = a.max(axis=2), a.min(axis=2)
	sat = (mx - mn) / np.maximum(mx, 1.0)
	cur = float(sat.mean())
	if cur > sat_ceiling * 1.05:
		k = sat_ceiling / cur
		grey = (a @ np.array([0.299, 0.587, 0.114]))[..., None]
		a = grey + (a - grey) * k
	return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


# ── periodic noise, for the synthesised dressing ─────────────────────────────
def _rng(name: str) -> np.random.Generator:
	"""Seeded from the tile's own NAME so a regeneration is reproducible and reviewable.

	WARNING: NOT `hash(name)` -- Python salts str hashes per process, so that would make
	every run produce different art while looking deterministic in the source.
	"""
	return np.random.default_rng(int.from_bytes(name.encode(), "little") % (2**32))


def _value_noise(rng: np.random.Generator, n: int, period: int) -> np.ndarray:
	"""Tileable value noise: a lattice sampled with wrap, smoothstep-interpolated."""
	lat = rng.random((period, period))
	ys = np.linspace(0, period, n, endpoint=False)
	xs = np.linspace(0, period, n, endpoint=False)
	y0 = np.floor(ys).astype(int) % period
	x0 = np.floor(xs).astype(int) % period
	y1 = (y0 + 1) % period
	x1 = (x0 + 1) % period
	fy = ys - np.floor(ys)
	fx = xs - np.floor(xs)
	sy = (fy * fy * (3 - 2 * fy))[:, None]
	sx = (fx * fx * (3 - 2 * fx))[None, :]
	top = lat[np.ix_(y0, x0)] * (1 - sx) + lat[np.ix_(y0, x1)] * sx
	bot = lat[np.ix_(y1, x0)] * (1 - sx) + lat[np.ix_(y1, x1)] * sx
	return top * (1 - sy) + bot * sy


def _fbm(name: str, n: int, base: int = 4, octaves: int = 5) -> np.ndarray:
	rng = _rng(name)
	out = np.zeros((n, n))
	amp, tot, per = 1.0, 0.0, base
	for _ in range(octaves):
		out += amp * _value_noise(rng, n, per)
		tot += amp
		amp *= 0.5
		per *= 2
	out /= tot
	# numpy 2 removed ndarray.ptp(); np.ptp() is the portable form.
	return (out - out.min()) / max(1e-6, float(np.ptp(out)))


def _tint(mono: np.ndarray, dark, light) -> np.ndarray:
	d = np.array(dark, dtype=float)
	l = np.array(light, dtype=float)
	return d[None, None, :] + (l - d)[None, None, :] * mono[..., None]


# ── dressing patterns ────────────────────────────────────────────────────────
# WARNING: THESE ARE SYNTHESISED, NOT INHERITED, AND THAT IS NOT A SECOND-BEST.
# The React library's cover art is 2D PROP CUTOUTS (prop-barrel.png and friends) -- a
# silhouette with baked lighting. The Godot arena wears its dressing as a TILING MATERIAL
# on a box, so a cutout is unusable: it would appear pasted, once, with its own shadow
# pointing the wrong way. A tiling material for a barrel is staves; for a crate, boards.
# Nothing in the library is one, so these are the only genuinely missing files.

def _stripes(n: int, count: int, axis: int) -> np.ndarray:
	"""Periodic bands with a dark groove -- staves, planks, courses. Wraps by construction."""
	t = np.linspace(0, count * 2 * np.pi, n, endpoint=False)
	wave = np.sin(t)
	band = 0.5 + 0.5 * wave
	groove = np.clip(np.abs(wave) * 3.0, 0.0, 1.0)  # dark line at every band edge
	prof = (0.55 + 0.45 * band) * (0.45 + 0.55 * groove)
	return prof[:, None] * np.ones((1, n)) if axis == 0 else prof[None, :] * np.ones((n, 1))


def _plank(name: str, n: int, rows: int, dark, light, grain: float = 0.35) -> Image.Image:
	base = _stripes(n, rows, 0)
	fb = _fbm(name + "-grain", n, base=2, octaves=5)
	streak = _fbm(name + "-streak", n, base=1, octaves=3)
	mono = np.clip(base * (1 - grain) + fb * grain * 0.8 + streak * grain * 0.4, 0, 1)
	# per-plank value variation, so boards are not clones of one board. Phase-derived for
	# the same wrap reason as the weave -- and the board change always lands on a groove.
	idx = np.floor(np.linspace(0.0, float(rows), n, endpoint=False)).astype(int) % rows
	shade = _rng(name + "-shade").uniform(0.86, 1.12, rows)[idx][:, None]
	mono = np.clip(mono * shade, 0, 1)
	return Image.fromarray(np.clip(_tint(mono, dark, light), 0, 255).astype(np.uint8))


def _staves(name: str, n: int, count: int, dark, light) -> Image.Image:
	base = _stripes(n, count, 1)
	fb = _fbm(name + "-g", n, base=3, octaves=5)
	mono = np.clip(base * 0.7 + fb * 0.35, 0, 1)
	# two iron hoops across the barrel, dark
	y = np.linspace(0, 1, n, endpoint=False)
	hoop = np.exp(-((np.minimum(np.abs(y - 0.27), np.abs(y - 0.73))) / 0.035) ** 2)
	mono = np.clip(mono * (1 - 0.55 * hoop[:, None]) + 0.10 * hoop[:, None], 0, 1)
	return Image.fromarray(np.clip(_tint(mono, dark, light), 0, 255).astype(np.uint8))


def _brick(name: str, n: int, rows: int, cols: int, dark, light, mortar) -> Image.Image:
	rng = _rng(name)
	img = np.zeros((n, n))
	rh, cw = n / rows, n / cols
	yy, xx = np.mgrid[0:n, 0:n]
	row = (yy / rh).astype(int)
	offset = (row % 2) * (cw * 0.5)
	col = ((xx + offset) / cw).astype(int)
	shade = rng.uniform(0.72, 1.15, (rows + 2, cols + 2))
	img = shade[row % (rows + 2), col % (cols + 2)]
	# mortar courses -- wrap-safe because they are derived from the same modulo grid
	ry = np.abs((yy % rh) - rh / 2) > (rh / 2 - max(2.0, rh * 0.055))
	rx = np.abs(((xx + offset) % cw) - cw / 2) > (cw / 2 - max(2.0, cw * 0.035))
	fb = _fbm(name + "-f", n, base=4, octaves=5)
	mono = np.clip(img * 0.7 + fb * 0.45, 0, 1)
	out = _tint(mono, dark, light)
	m = np.array(mortar, dtype=float)
	joint = (ry | rx)[..., None]
	out = np.where(joint, m[None, None, :] * (0.85 + 0.3 * fb[..., None]), out)
	return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def _rock(name: str, n: int, dark, light, roughness: float = 1.0) -> Image.Image:
	"""Fractured rock. ⚠️ SMOOTH fbm ALONE READS AS CLOUD, NOT AS STONE — the first cut was a
	grey smudge on the contact sheet. Rock needs FACETS: a cell pattern gives the flat planes,
	the ridged noise gives the chipping, and the sharp value break between them is what the
	eye reads as "this is hard"."""
	cell = _fbm(name + "-cell", n, base=7, octaves=2)
	facet = np.floor(cell * 6.0) / 6.0  # quantised planes — flat faces, hard edges between
	ridge = 1.0 - np.abs(_fbm(name + "-ridge", n, base=12, octaves=4) * 2.0 - 1.0)
	grit = _fbm(name + "-grit", n, base=28, octaves=2)
	mono = np.clip(facet * 0.52 + ridge * 0.34 * roughness + grit * 0.22, 0, 1)
	mono = np.clip((mono - 0.18) / 0.64, 0, 1)
	return Image.fromarray(np.clip(_tint(mono, dark, light), 0, 255).astype(np.uint8))


def _marble(name: str, n: int, dark, light) -> Image.Image:
	"""⚠️ VEINS MUST BE FEW, LONG AND DIRECTIONAL. Driving the swirl at high frequency with a
	full-amplitude fbm produced scribble — dozens of short worms with no direction, which
	reads as damage rather than as stone. One dominant axis, a gentle warp and a second
	fainter vein set is what marble actually looks like."""
	warp = _fbm(name + "-warp", n, base=2, octaves=4)
	x = np.linspace(0, 2 * np.pi, n, endpoint=False)
	axis = x[None, :] * 2.0 + x[:, None] * 1.0
	major = np.sin(axis + (warp - 0.5) * 4.2)
	minor = np.sin(axis * 2.0 + (warp - 0.5) * 5.0 + 1.7)
	vein = np.exp(-(np.abs(major) / 0.075) ** 2) + 0.45 * np.exp(-(np.abs(minor) / 0.05) ** 2)
	body = _fbm(name + "-body", n, base=5, octaves=4)
	mono = np.clip(0.74 + 0.16 * body - 0.55 * np.clip(vein, 0, 1), 0, 1)
	return Image.fromarray(np.clip(_tint(mono, dark, light), 0, 255).astype(np.uint8))


def _twill(name: str, n: int, count: int, dark, light) -> Image.Image:
	"""Banner cloth. ⚠️ NOT THE SACK WEAVE — reusing `_weave` for the banner made it read as
	noise at arena distance, because a banner is seen as a FLAT HANGING PANEL where a sandbag
	is seen as a lumpy object. Twill's diagonal is the only thing at that scale that still
	says cloth, and a woven-in stripe gives the guild signage something to sit on."""
	t = np.linspace(0, count * 2 * np.pi, n, endpoint=False)
	diag = 0.5 + 0.5 * np.sin(t[:, None] + t[None, :])
	stripe = 0.5 + 0.5 * np.sin(np.linspace(0, 6 * 2 * np.pi, n, endpoint=False))[None, :]
	drape = _fbm(name + "-drape", n, base=2, octaves=4)
	fuzz = _fbm(name + "-fuzz", n, base=24, octaves=2)
	mono = np.clip(0.30 + 0.34 * diag + 0.16 * stripe + 0.26 * drape + 0.08 * fuzz, 0, 1)
	return Image.fromarray(np.clip(_tint(mono, dark, light), 0, 255).astype(np.uint8))


def _weave(name: str, n: int, count: int, dark, light) -> Image.Image:
	"""Coarse sack canvas -- an over/under weave, so sandbags read as cloth not as stone."""
	# WARNING: THE OVER/UNDER INDEX MUST BE DERIVED FROM THE CONTINUOUS PHASE, not from
	# `arange(n) * count // n`. Integer division only wraps when `count` divides `n`, and at
	# count=46 on a 1024 tile the last thread came out half-width -- a 10-unit wrap error on
	# an otherwise 1.8-unit texture, i.e. a visible stripe down every sandbag.
	t = np.linspace(0, count * 2 * np.pi, n, endpoint=False)
	warp = 0.5 + 0.5 * np.sin(t)[None, :]
	weft = 0.5 + 0.5 * np.sin(t)[:, None]
	# WARNING: A HARD over/under CHECKER IS NOT SEAMLESS EVEN WHEN ITS INDEX WRAPS. Switching
	# between warp and weft with `np.where` jumps by whatever the two happen to differ by at
	# the crossing -- measured 10.3 against a 2.3 texture bar, on a tile whose index arithmetic
	# was already correct. The blend has to be CONTINUOUS, so the crossover is a cosine.
	blend = 0.5 + 0.5 * np.cos(t[None, :] - t[:, None])
	mono = warp * blend + weft * (1.0 - blend)
	lump = _fbm(name + "-lump", n, base=2, octaves=4)
	grit = _fbm(name + "-grit", n, base=16, octaves=2)
	mono = np.clip(mono * 0.45 + lump * 0.45 + grit * 0.18, 0, 1)
	return Image.fromarray(np.clip(_tint(mono, dark, light), 0, 255).astype(np.uint8))


def _soil(name: str, n: int, dark, light) -> Image.Image:
	fb = _fbm(name, n, base=6, octaves=6)
	clod = _fbm(name + "-clod", n, base=14, octaves=3)
	mono = np.clip(fb * 0.6 + clod * 0.55, 0, 1)
	return Image.fromarray(np.clip(_tint(mono, dark, light), 0, 255).astype(np.uint8))


# ── the dressing manifest ────────────────────────────────────────────────────
# WARNING: THE PALETTE IS GUILD COLOURS, NOT TEAM COLOURS (docs/ART_THEME.md: three colour
# systems that must never collide). Every swatch below is a MATERIAL -- timber, stone,
# brick, canvas, soil. None of them is a team livery hue and none is a status hue, so a
# barrel can never be mistaken for a sash or for a burn.
def dressing() -> dict:
	n = TILE
	return {
		# kinds that had NO texture of their own and were borrowing a tinted neighbour
		"planter-soil.jpg":  lambda: _soil("planter", n, (38, 31, 22), (104, 92, 66)),
		"bench-wood.jpg":    lambda: _plank("bench", n, 5, (48, 34, 23), (142, 108, 71)),
		"fence-timber.jpg":  lambda: _plank("fence", n, 13, (46, 37, 26), (150, 122, 84)),
		"boulder-rock.jpg":  lambda: _rock("boulder", n, (52, 49, 45), (136, 128, 116)),
		"pillar-stone.jpg":  lambda: _brick("pillar", n, 5, 3, (86, 83, 78), (162, 156, 146), (104, 100, 94)),
		"shrine-marble.jpg": lambda: _marble("shrine", n, (66, 62, 56), (172, 164, 148)),
		"low-wall-brick.jpg": lambda: _brick("lowwall", n, 9, 5, (86, 54, 42), (150, 96, 70), (118, 112, 102)),
		# the brief's remaining vocabulary
		"sandbag-canvas.jpg": lambda: _weave("sandbag", n, 46, (66, 56, 38), (146, 130, 96)),
		"stone-block.jpg":   lambda: _brick("stoneblock", n, 4, 2, (78, 76, 72), (146, 142, 134), (100, 97, 92)),
		"timber-stack.jpg":  lambda: _plank("timberstack", n, 11, (44, 33, 22), (134, 104, 70)),
		"banner-cloth.jpg":  lambda: _twill("banner", n, 26, (48, 45, 44), (132, 126, 120)),
	}


# ── writing ──────────────────────────────────────────────────────────────────
def _save_jpg(im: Image.Image, path: str, quality: int = 92) -> None:
	os.makedirs(os.path.dirname(path), exist_ok=True)
	im.convert("RGB").save(path, quality=quality, subsampling=0)


def run(write: bool) -> int:
	rows = []
	os.makedirs(OUT_ARENAS, exist_ok=True)
	os.makedirs(OUT_ARENA, exist_ok=True)

	# 1. league grounds -- INHERITED from the authored library, repaired and graded
	for slug, (src, why) in LEAGUE_GROUND.items():
		sp = os.path.join(FIELD, src)
		if not os.path.exists(sp):
			print("MISSING SOURCE %s" % sp, file=sys.stderr)
			return 1
		im = Image.open(sp).convert("RGB").resize((TILE, TILE), Image.LANCZOS)
		before = palette_stats(im) + seam_stats(im)[:2]
		im = _tileable(im)
		im = _grade(im, GROUND_LUMA_BAND, HOUSE_SAT)
		lum, sat = palette_stats(im)
		ex, ey, bar = seam_stats(im)
		out = os.path.join(OUT_ARENAS, "%s-ground.jpg" % slug)
		if write:
			_save_jpg(im, out)
		rows.append(("ground", slug, src, "lum %5.1f (was %5.1f)  sat %.2f  wrap %.1f/%.1f vs bar %.1f"
		             % (lum, before[0], sat, ex, ey, bar), why))

	# 2. league backdrops -- straight inheritance, no processing; these are approved paintings
	for slug, src in LEAGUE_BACKDROP.items():
		sp = os.path.join(BACKDROPS, src)
		out = os.path.join(OUT_ARENAS, "%s-backdrop.jpg" % slug)
		if not os.path.exists(sp):
			rows.append(("backdrop", slug, src, "SOURCE MISSING", ""))
			continue
		existed = os.path.exists(out)
		im = Image.open(sp).convert("RGB")
		if write and not existed:
			_save_jpg(im, out, quality=90)
		rows.append(("backdrop", slug, src,
		             "%s  %dx%d" % ("kept (already filed)" if existed else "copied", *im.size), ""))

	# 3a. the dressing that ALREADY EXISTS -- authored through Route B when the subscription
	# was live. WARNING: DO NOT REGENERATE THESE. Procedural staves are a fallback, not an
	# upgrade on real art, and ART_PIPELINE.md's Route C section says exactly that about
	# computed sprites. All they need is the seam repair -- wall-timber measured a 26.2 wrap
	# against a 3.8 interior, i.e. a hard band across every timber prop in the game.
	for name in EXISTING_DRESSING:
		p = os.path.join(OUT_ARENA, name)
		if not os.path.exists(p):
			rows.append(("dressing", name, "authored", "MISSING -- not regenerated", ""))
			continue
		src = Image.open(p).convert("RGB")
		bex, bey, _ = seam_stats(src)
		im = _tileable(src, band=64)
		lum, sat = palette_stats(im)
		ex, ey, bar = seam_stats(im)
		if write:
			_save_jpg(im, p)
		rows.append(("dressing", name, "authored+repair",
		             "lum %5.1f  sat %.2f  wrap %.1f/%.1f (was %.1f/%.1f) vs bar %.1f"
		             % (lum, sat, ex, ey, bex, bey, bar), "kept: real art, seam repaired"))

	# 3b. cover dressing that never existed as a tiling material -- SYNTHESISED
	for name, make in dressing().items():
		im = make()
		im = _tileable(im, band=64)
		lum, sat = palette_stats(im)
		ex, ey, bar = seam_stats(im)
		out = os.path.join(OUT_ARENA, name)
		if write:
			_save_jpg(im, out)
		rows.append(("dressing", name, "procedural",
		             "lum %5.1f  sat %.2f  wrap %.1f/%.1f vs bar %.1f" % (lum, sat, ex, ey, bar), ""))

	w = max(len(r[1]) for r in rows)
	for kind, name, src, stat, why in rows:
		print("%-9s %-*s  <- %-24s %s%s" % (kind, w, name, src, stat, ("   # " + why) if why else ""))
	return 0


if __name__ == "__main__":
	ap = argparse.ArgumentParser()
	ap.add_argument("--report", action="store_true", help="measure only, write nothing")
	args = ap.parse_args()
	sys.exit(run(write=not args.report))
