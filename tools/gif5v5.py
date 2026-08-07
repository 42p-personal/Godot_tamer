"""Render a dumped tamerengine fight to an animated GIF.

Usage:
    npx tsx tools/dump5v5.ts fight.json <seed>
    python tools/gif5v5.py fight.json fight.gif [tickStep] [fps]

Requires Pillow. Produces a 960x670 GIF: the field with obstacles, units with
HP, hit lines and damage numbers, plus a roster strip naming each monster and
its CLASS — ten monsters in a melee are unreadable in-field, and the roster is
where "who is still up, and what were they" actually reads.

Reads the JSON produced by tools/dump5v5.ts — the same per-tick snapshot stream
TamerArena consumes — and draws each frame: units, HP, obstacles, casts, hits.
"""
import json, sys, math
from PIL import Image, ImageDraw, ImageFont

src, dst = sys.argv[1], sys.argv[2]
# ⚠️ REAL TIME IS FPS == TICK_HZ / STEP. Snapshots are 10 Hz, so STEP 1 / FPS 10
# plays at 1x. The old defaults (STEP 2, FPS 20) ran at FOUR TIMES real time, and
# every render in this session until now was 3x-4.5x — which is why the movement
# looked like sprinting and every direction change looked like a jolt. Three
# engine changes were made chasing a renderer setting. If you speed it up to keep
# a file small, say so on the image; do not judge feel from a fast-forward.
TICK_HZ = 10
STEP = int(sys.argv[3]) if len(sys.argv) > 3 else 1
# ⚠️ INTERPOLATE. The sim ticks at 10 Hz; drawing those samples raw shows
# continuous motion as ten discrete jumps a second, which is why it still read as
# teleporting even at 1x. This file's own docstring has always claimed "the
# renderer interpolates them" — it never did. Positions are now blended between
# snapshots so the output can run at a frame rate the eye reads as movement.
FPS = int(sys.argv[4]) if len(sys.argv) > 4 else 30
SUB = max(1, round(FPS * STEP / TICK_HZ))   # frames drawn per sim tick
RATE = (FPS / SUB) * STEP / TICK_HZ

d = json.load(open(src, encoding='utf-8'))
# ⚠️ Read the field from the DUMP. These were hardcoded 40x22, which silently
# drew every other arena at the wrong scale — units walking off the painted
# pitch, obstacles landing in the wrong place — while looking like a plausible
# render. A dump that carries its own dimensions cannot disagree with itself.
MAP = d.get('map', {})
FW, FH = float(MAP.get('w', 40.0)), float(MAP.get('h', 22.0))
# Scale to a roughly constant OUTPUT width so three arenas of different sizes
# arrive as comparable images. Sprites are drawn in world units, so on a bigger
# map they correctly come out smaller — that IS the thing being shown.
SC = max(11, min(24, int(1180 / FW)))
PAD_T, PAD_B = 46, 96   # bottom pad holds the roster
W, H = int(FW * SC), int(FH * SC) + PAD_T + PAD_B

BG      = (14, 14, 19)
FIELD   = (23, 24, 31)
GRID    = (32, 33, 42)
ROCK    = (52, 51, 62)
INK     = (236, 235, 242)
DIM     = (128, 124, 140)
A_COL   = (86, 170, 255)      # team A — cool
B_COL   = (255, 122, 79)      # team B — warm
HP_GOOD = (108, 214, 128)
HP_LOW  = (232, 196, 92)
HP_CRIT = (232, 92, 92)
CAST    = (196, 148, 255)
HIT     = (255, 236, 160)


def font(sz, bold=False):
    for p in (r'C:\Windows\Fonts\segoeuib.ttf' if bold else r'C:\Windows\Fonts\segoeui.ttf',
              r'C:\Windows\Fonts\arialbd.ttf' if bold else r'C:\Windows\Fonts\arial.ttf'):
        try:
            return ImageFont.truetype(p, sz)
        except OSError:
            pass
    return ImageFont.load_default()


F_TITLE, F_LBL, F_SM, F_HUD = font(19, True), font(12, True), font(11), font(15, True)
meta, frames, obstacles = d['meta'], d['frames'], d['obstacles']


def wx(x): return int(x * SC)
def wy(y): return int(y * SC) + PAD_T


# Persist brief visual effects across the sampled frames so a 1-tick event is
# still visible when we only keep every Nth tick.
recent_hits, recent_casts, dead = [], [], set()
out = []

for fi in range(0, len(frames), STEP):
    # gather the events of every tick we skipped, so nothing is silently dropped
    for f in frames[fi:fi + STEP]:
        for h in f['hits']:
            recent_hits.append([h, 3])
        for c in f['casts']:
            recent_casts.append([c, 3])
        for x in f['deaths']:
            dead.add(x)
    fr = frames[fi]
    # ⚠️ Blend positions toward the NEXT sampled tick. `sub` frames are drawn per
    # tick, each one part-way between this snapshot and the next, so a monster
    # slides between samples instead of jumping to each one.
    nxt = frames[min(fi + STEP, len(frames) - 1)]
    nxt_pos = {u['id']: u for u in nxt['units']}
    for si in range(SUB):
      k = si / SUB
      fr = dict(frames[fi])
      fr['units'] = [
          {**u,
           'x': u['x'] + (nxt_pos[u['id']]['x'] - u['x']) * k if u['id'] in nxt_pos else u['x'],
           'y': u['y'] + (nxt_pos[u['id']]['y'] - u['y']) * k if u['id'] in nxt_pos else u['y']}
          for u in frames[fi]['units']]

      im = Image.new('RGB', (W, H), BG)
      g = ImageDraw.Draw(im)

      # ── field ────────────────────────────────────────────────────────────────
      g.rectangle([0, PAD_T, W, PAD_T + int(FH * SC)], fill=FIELD)
      for gx in range(0, int(FW) + 1, 4):
          g.line([wx(gx), PAD_T, wx(gx), PAD_T + int(FH * SC)], fill=GRID)
      for gy in range(0, int(FH) + 1, 4):
          g.line([0, wy(gy), W, wy(gy)], fill=GRID)
      g.line([wx(FW / 2), PAD_T, wx(FW / 2), PAD_T + int(FH * SC)], fill=(44, 45, 56))
      # ⚠️ x,y IS THE TOP-LEFT CORNER, NOT THE CENTRE. `insideObstacle` in the
      # engine tests `p.x > o.x && p.x < o.x + o.w`, and TamerArena draws with
      # `left: o.x * PX`. Drawing these centred put every rock 1.1 units up-and-left
      # of where it really is, which made shots look like they passed THROUGH cover
      # when they were passing beside it.
      for o in obstacles:
          g.rounded_rectangle(
              [wx(o['x']), wy(o['y']), wx(o['x'] + o['w']), wy(o['y'] + o['h'])],
              radius=4, fill=ROCK)

      pos = {u['id']: u for u in fr['units']}

      # ── hit lines (drawn under the units) ────────────────────────────────────
      for h, life in recent_hits:
          a, b = pos.get(h['id']), pos.get(h['targetId'])
          if not a or not b:
              continue
          fade = life / 3.0
          col = tuple(int(c * fade + FIELD[i] * (1 - fade)) for i, c in enumerate(HIT))
          g.line([wx(a['x']), wy(a['y']), wx(b['x']), wy(b['y'])], fill=col, width=2 if h['crit'] else 1)

      # ── units ────────────────────────────────────────────────────────────────
      for u in fr['units']:
          m = meta[u['id']]
          team = A_COL if u['id'][0] == 'A' else B_COL
          x, y = wx(u['x']), wy(u['y'])
          r = int(0.9 * SC)
          down = u['id'] in dead or u['hp'] <= 0

          if down:
              g.line([x - 7, y - 7, x + 7, y + 7], fill=(78, 74, 88), width=3)
              g.line([x - 7, y + 7, x + 7, y - 7], fill=(78, 74, 88), width=3)
              continue

          casting = any(c['id'] == u['id'] for c, _ in recent_casts)
          if casting:
              g.ellipse([x - r - 5, y - r - 5, x + r + 5, y + r + 5], outline=CAST, width=2)
          body = tuple(int(c * 0.42 + FIELD[i] * 0.58) for i, c in enumerate(team))
          g.ellipse([x - r, y - r, x + r, y + r], fill=body, outline=team, width=2)

          # HP bar
          frac = max(0.0, min(1.0, u['hp'] / max(1, u['maxHp'])))
          hp_col = HP_GOOD if frac > 0.5 else HP_LOW if frac > 0.25 else HP_CRIT
          bw = r * 2
          by = y - r - 9
          g.rectangle([x - r, by, x - r + bw, by + 4], fill=(40, 40, 50))
          g.rectangle([x - r, by, x - r + int(bw * frac), by + 4], fill=hp_col)
          g.text((x, y + r + 2), m['name'], font=F_SM, fill=(96, 93, 108), anchor='ma')

      # ── damage numbers, over everything ──────────────────────────────────────
      for h, life in recent_hits:
          b = pos.get(h['targetId'])
          if not b:
              continue
          rise = (3 - life) * 5
          g.text((wx(b['x']), wy(b['y']) - 24 - rise), str(int(h['dmg'])),
                 font=F_LBL, fill=HIT if not h['crit'] else (255, 210, 120), anchor='ma')

      # ── HUD ──────────────────────────────────────────────────────────────────
      aliveA = sum(1 for u in fr['units'] if u['id'][0] == 'A' and u['id'] not in dead and u['hp'] > 0)
      aliveB = sum(1 for u in fr['units'] if u['id'][0] == 'B' and u['id'] not in dead and u['hp'] > 0)
      g.text((14, 10), MAP.get('name', 'tamerengine'), font=F_TITLE, fill=INK)
      # ⚠️ Derived, not hardcoded: this said "5 v 5" over a 3v3 the moment the
      # dumper learned a team size. A caption that cannot be wrong beats one that
      # happens to be right.
      nA = sum(1 for k in meta if k.startswith('A'))
      nB = sum(1 for k in meta if k.startswith('B'))
      g.text((14 + 128, 14), f'{nA} v {nB}  ·  field battle', font=F_SM, fill=DIM)
      g.text((W - 14, 12), f"{fr['t']:.1f}s", font=F_HUD, fill=INK, anchor='ra')
      g.text((W / 2 - 30, 14), f'{aliveA}', font=F_HUD, fill=A_COL, anchor='ra')
      g.text((W / 2, 16), 'alive', font=F_SM, fill=DIM, anchor='ma')
      g.text((W / 2 + 30, 14), f'{aliveB}', font=F_HUD, fill=B_COL, anchor='la')
      # ── ROSTER ───────────────────────────────────────────────────────────────
      # Ten monsters bunched in a melee are unreadable in-field; this is where the
      # class identity and who is still up actually reads.
      ry = PAD_T + int(FH * SC) + 10
      for side, col, x0 in (('A', A_COL, 14), ('B', B_COL, W // 2 + 8)):
          for i in range(5):
              uid = f'{side}{i}'
              u = pos.get(uid)
              if not u:
                  continue
              m = meta[uid]
              gone = uid in dead or u['hp'] <= 0
              cx = x0 + (i % 5) * ((W // 2 - 30) // 5)
              nm = m['name'] if not gone else m['name']
              g.text((cx, ry), nm, font=F_LBL, fill=(92, 89, 104) if gone else INK)
              g.text((cx, ry + 15), m['cls'], font=F_SM, fill=(72, 70, 84) if gone else DIM)
              frac = 0.0 if gone else max(0.0, min(1.0, u['hp'] / max(1, u['maxHp'])))
              bw2 = (W // 2 - 30) // 5 - 14
              g.rectangle([cx, ry + 32, cx + bw2, ry + 37], fill=(36, 36, 46))
              if frac > 0:
                  hc = HP_GOOD if frac > 0.5 else HP_LOW if frac > 0.25 else HP_CRIT
                  g.rectangle([cx, ry + 32, cx + int(bw2 * frac), ry + 37], fill=hc)
              else:
                  g.line([cx + 2, ry + 34, cx + 10, ry + 34], fill=(92, 89, 104), width=2)
          g.text((x0, ry - 14), 'TEAM ' + side, font=F_SM, fill=col)

      if abs(RATE - 1.0) > 0.01:
          g.text((W / 2, H - 16), f'PLAYBACK {RATE:g}x REAL TIME', font=F_LBL,
                 fill=(196, 148, 255), anchor='ma')
      foot = (f"seed {d['seed']}  ·  winner {d['winner']}  ·  "
              f"{d['duration']}s  ·  {d['survivorsA']}v{d['survivorsB']} standing")
      if MAP:
          g.text((14, H - 16), f"{MAP['w']:g} x {MAP['h']:g}  ·  {MAP['brief']}",
                 font=F_SM, fill=(84, 81, 96))
      g.text((W - 14, H - 16), foot, font=F_SM, fill=(84, 81, 96), anchor='ra')

      out.append(im.convert('P', palette=Image.ADAPTIVE, colors=128))

    recent_hits = [[h, l - 1] for h, l in recent_hits if l > 1]
    recent_casts = [[c, l - 1] for c, l in recent_casts if l > 1]

# hold the final frame so the result reads before it loops
out += [out[-1]] * int(FPS * 1.6)
# ⚠️ SCALE THE OUTPUT, NEVER THE PLAYBACK. A full-size render is ~5.6 MB; a batch
# of 22 is 125 MB. The tempting fix is a bigger STEP or a higher FPS, and this
# file's own header explains why that is wrong — every render in an earlier
# session ran 3x-4.5x real time and three engine changes were made chasing what
# turned out to be a renderer setting. Downscaling loses pixels; it does not lie
# about how the fight moved.
SCALE = float(sys.argv[5]) if len(sys.argv) > 5 else 1.0
if SCALE != 1.0:
    out = [f.resize((int(W * SCALE), int(H * SCALE)), Image.LANCZOS) for f in out]

# ⚠️ A 64-COLOUR SHARED PALETTE WAS TRIED AND REMOVED. It looked like the obvious
# way to shrink these — the renderer draws flat UI tones — but Pillow's
# `optimize=True` already does that work: 5662 KB -> 5406 KB, a 5% gain for a
# quantise pass over every frame. Not worth the code, and the comment justifying
# it claimed "roughly halves the file", which was simply untrue.

out[0].save(dst, save_all=True, append_images=out[1:],
            duration=int(1000 / FPS), loop=0, optimize=True, disposal=2)
print(f'{dst}: {len(out)} frames, {W}x{H}, {FPS}fps')
