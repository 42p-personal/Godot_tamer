// ─────────────────────────────────────────────────────────────────────────────
// PIXEL RIG (v0.93) — battle sprites DRAWN IN CODE, with limbs that move.
//
// Why this exists: both image-generation routes have been returning hard
// failures since 2026-07-27 (API billing cap; codex image service 403), so the
// hand-generated 6-frame sets in docs/BATTLE_SPRITES.md cannot be made. See
// docs/ART_PIPELINE.md.
//
// The procedural pass in `battleSprite.css` animates the whole portrait as one
// piece — squash, lean, recoil. It reads as weight, but a portrait has no
// separable arms, so nothing can ever swing. At small pixel sizes we can go
// further: build the creature from PARTS and rotate the joints. Arms swing,
// legs stride, the tail lags behind the hips.
//
// Two properties make this worth doing rather than waiting:
//   • It needs no art service at all — it is arithmetic and canvas calls.
//   • Colour is INHERITED from each species' existing portrait (`RAMPS` below
//     was sampled from `public/sprites/<id>.png`), so a pixel sprite still
//     looks like the creature the player already knows.
//
// ⚠️ ANTIALIASING IS THE ENEMY OF PIXEL ART. Canvas 2D has no way to turn it
// off, so drawing at final scale gives soft, muddy edges that read as "small
// blurry drawing" rather than "pixel art". Instead we draw at LOGICAL size
// (48×48) and then quantise — alpha snapped to 0 or 1, colour snapped to the
// species ramp. That is what produces hard pixel edges.
//
// ⚠️ AND SO SHEETS ARE BUILT ONCE, NOT PER FRAME. The quantise pass is a
// per-pixel loop; running it every frame for a dozen units would be thousands
// of loops a second. `spriteSheet()` renders every pose of every animation up
// front into one canvas and caches it, exactly like a hand-drawn sprite sheet.
// Runtime cost after that is a blit.

export const FRAME = 48        // logical pixels per frame, square
export const FRAMES_PER_ANIM = 8

export type BodyPlan = 'biped' | 'quadruped'
export type RigAnim = 'idle' | 'move' | 'attack' | 'cast' | 'hurt' | 'dead'
export const RIG_ANIMS: RigAnim[] = ['idle', 'move', 'attack', 'cast', 'hurt', 'dead']

export interface RigSpec {
  plan: BodyPlan
  /** 5 colours, darkest → lightest. Sampled from the species portrait. */
  ramp: string[]
  /** Overall build. 1 is average; a bear is heavier, a wolverine slighter. */
  bulk: number
  /** Height multiplier — how tall it stands relative to its frame. */
  stature: number
  /** Arm length multiplier. A silverback's reach is most of its silhouette, so
   *  this has to be per-species rather than derived from bulk. */
  reach?: number
  mane?: boolean
  horns?: boolean
  ears?: 'round' | 'pointed' | 'none'
  tail?: 'none' | 'stub' | 'long'
  hump?: boolean
}

/**
 * A pose is joint ANGLES, in radians, not positions. That is the whole point:
 * an animation interpolates angles and the limbs follow, which is what makes a
 * swing look hinged instead of slid.
 *
 * Angles are measured clockwise from straight down, so 0 is a hanging limb.
 */
export interface Pose {
  bodyY: number      // vertical offset of the whole body, logical px
  bodyLean: number   // torso rotation
  headTilt: number
  /** [shoulder, elbow] for each arm; 'far' is the side away from the viewer. */
  armFar: [number, number]
  armNear: [number, number]
  legFar: [number, number]
  legNear: [number, number]
  tail: number
  /** Whole-sprite rotation about the feet — only death uses it. */
  topple: number
  /** 0–1; blows out the palette on the frame a hit lands. */
  flash: number
}

const P = (o: Partial<Pose> = {}): Pose => ({
  bodyY: 0, bodyLean: 0, headTilt: 0,
  armFar: [0, 0], armNear: [0, 0], legFar: [0, 0], legNear: [0, 0],
  tail: 0, topple: 0, flash: 0, ...o,
})

const TAU = Math.PI * 2
const lerp = (a: number, b: number, k: number) => a + (b - a) * k
/** Ease so a limb slows at the ends of its swing — a linear swing looks robotic. */
const wave = (t: number, phase = 0) => Math.sin((t + phase) * TAU)

// ── The animations ───────────────────────────────────────────────────────────
// Each takes a normalised 0–1 time and returns a pose. Arms and legs are driven
// in OPPOSITION (a half-cycle apart) because that is what walking is; putting
// them in phase reads instantly as a toy being shuffled along.
export function poseFor(anim: RigAnim, t: number, plan: BodyPlan): Pose {
  switch (anim) {
    case 'idle': {
      const b = wave(t) * 0.5
      return P({
        bodyY: b * 0.6,
        bodyLean: b * 0.02,
        headTilt: wave(t, 0.12) * 0.05,
        armFar: [wave(t, 0.1) * 0.08, 0.12 + wave(t, 0.1) * 0.05],
        armNear: [wave(t, 0.15) * 0.08, 0.14 + wave(t, 0.15) * 0.05],
        tail: wave(t, 0.25) * 0.22,
      })
    }
    case 'move': {
      // A quadruped's front legs are its "arms", so the same swing drives both
      // plans — only the amplitude differs, since a biped's arms carry no weight
      // and therefore swing further.
      const amp = plan === 'biped' ? 0.85 : 0.6
      const s = wave(t)
      const o = wave(t, 0.5)
      return P({
        // Two footfalls per cycle: the body rises between them, so it bobs at
        // DOUBLE the stride frequency. Bobbing at stride rate looks like limping.
        bodyY: -Math.abs(Math.sin(t * TAU)) * 1.6,
        bodyLean: plan === 'biped' ? 0.06 : 0.02,
        headTilt: wave(t, 0.5) * 0.06,
        armFar: [s * amp, Math.max(0, -s) * 0.5],
        armNear: [o * amp, Math.max(0, -o) * 0.5],
        legFar: [o * 0.75, Math.max(0, o) * 0.6],
        legNear: [s * 0.75, Math.max(0, s) * 0.6],
        tail: wave(t, 0.25) * 0.3,
      })
    }
    case 'attack': {
      // Anticipation → strike → recovery, deliberately asymmetric. The wind-up
      // takes 40% of the clip and the strike lands in the next 15%.
      if (t < 0.4) {
        const k = t / 0.4
        return P({
          bodyLean: lerp(0, -0.22, k),
          bodyY: lerp(0, 1, k),
          headTilt: lerp(0, -0.15, k),
          armFar: [lerp(0, -1.5, k), lerp(0.1, 0.9, k)],
          armNear: [lerp(0, -1.7, k), lerp(0.1, 1.1, k)],
          legNear: [lerp(0, -0.2, k), 0],
          tail: lerp(0, -0.4, k),
        })
      }
      if (t < 0.55) {
        const k = (t - 0.4) / 0.15
        return P({
          bodyLean: lerp(-0.22, 0.34, k),
          bodyY: lerp(1, -0.5, k),
          headTilt: lerp(-0.15, 0.2, k),
          armFar: [lerp(-1.5, 1.5, k), lerp(0.9, 0, k)],
          armNear: [lerp(-1.7, 1.8, k), lerp(1.1, 0, k)],
          legNear: [lerp(-0.2, 0.5, k), 0],
          legFar: [lerp(0, -0.3, k), 0],
          tail: lerp(-0.4, 0.5, k),
          flash: k,
        })
      }
      const k = (t - 0.55) / 0.45
      return P({
        bodyLean: lerp(0.34, 0, k),
        bodyY: lerp(-0.5, 0, k),
        headTilt: lerp(0.2, 0, k),
        armFar: [lerp(1.5, 0, k), 0],
        armNear: [lerp(1.8, 0, k), lerp(0, 0.14, k)],
        legNear: [lerp(0.5, 0, k), 0],
        legFar: [lerp(-0.3, 0, k), 0],
        tail: lerp(0.5, 0, k),
        flash: (1 - k) * 0.35,
      })
    }
    case 'cast': {
      // Both arms rise and hold, with a tremor. Reads as gathering rather than
      // striking, which is what a long wind-up needs to communicate.
      const rise = Math.min(1, t * 2.4)
      const trem = wave(t * 3) * 0.06 * rise
      return P({
        bodyY: -rise * 1.2,
        bodyLean: -rise * 0.12,
        headTilt: -rise * 0.24,
        armFar: [-rise * 2.1 + trem, -rise * 0.5],
        armNear: [-rise * 2.3 - trem, -rise * 0.6],
        tail: -rise * 0.3 + trem,
        flash: rise * 0.5 + trem,
      })
    }
    case 'hurt': {
      // Snap back hard, settle slowly. The flash is front-loaded so the frame
      // the blow lands on is unmistakable in a crowded field.
      const k = t < 0.25 ? t / 0.25 : 1 - (t - 0.25) / 0.75
      const back = t < 0.25 ? t / 0.25 : Math.max(0, 1 - (t - 0.25) / 0.5)
      return P({
        bodyLean: back * 0.4,
        bodyY: back * -1,
        headTilt: back * 0.5,
        armFar: [back * 1.3, back * 0.4],
        armNear: [back * 1.6, back * 0.5],
        legNear: [back * -0.5, 0],
        legFar: [back * 0.3, 0],
        tail: back * 0.6,
        flash: k,
      })
    }
    case 'dead': {
      // Topples and stays down. Limbs go slack rather than holding a pose —
      // a corpse frozen mid-stride is the classic tell of a rig with no death.
      const k = Math.min(1, t * 1.6)
      const e = k * k * (3 - 2 * k)
      return P({
        topple: e * 1.25,
        bodyY: e * 2,
        bodyLean: e * 0.2,
        headTilt: e * 0.6,
        armFar: [e * 0.9, e * 0.3],
        armNear: [e * 1.1, e * 0.2],
        legFar: [e * -0.6, e * 0.4],
        legNear: [e * -0.4, e * 0.5],
        tail: e * 0.8,
      })
    }
  }
}

// ── Drawing ──────────────────────────────────────────────────────────────────
type Ctx = CanvasRenderingContext2D
interface Pt { x: number; y: number }

/** Rotate `len` from `p` by `a` radians, where 0 points straight DOWN. */
const joint = (p: Pt, a: number, len: number): Pt =>
  ({ x: p.x + Math.sin(a) * len, y: p.y + Math.cos(a) * len })

function bone(ctx: Ctx, a: Pt, b: Pt, w: number, colour: string) {
  ctx.strokeStyle = colour
  ctx.lineWidth = w
  ctx.lineCap = 'round'
  ctx.beginPath()
  ctx.moveTo(a.x, a.y)
  ctx.lineTo(b.x, b.y)
  ctx.stroke()
}

function blob(ctx: Ctx, c: Pt, rx: number, ry: number, colour: string, rot = 0) {
  ctx.fillStyle = colour
  ctx.beginPath()
  ctx.ellipse(c.x, c.y, rx, ry, rot, 0, TAU)
  ctx.fill()
}

/**
 * One frame, drawn at logical scale.
 *
 * ⚠️ DRAW ORDER IS THE DEPTH MODEL. Far limbs, then body, then near limbs.
 * There is no z-buffer here — if the near arm is not drawn last it disappears
 * behind the torso at exactly the moment it swings forward, which is the moment
 * it matters most.
 */
export function drawPose(ctx: Ctx, spec: RigSpec, pose: Pose) {
  const [dark, mid, body, light, hi] = spec.ramp
  const bulk = spec.bulk
  const feetY = FRAME - 3
  const cx = FRAME / 2

  ctx.save()
  // ⚠️ A TOPPLE ABOUT THE FEET THROWS THE BODY SIDEWAYS. Rotating ~80° swings a
  // 30px creature further than the 24px it has to spare, and every death frame
  // was clipped in half by the frame edge — worst on quadrupeds, which are
  // longest. The pivot slides back toward centre as it falls, which is also
  // what actually happens when something topples: it does not rotate about its
  // toes, it goes down.
  ctx.translate(cx - Math.sin(pose.topple) * 9, feetY - Math.sin(pose.topple) * 1.5)
  ctx.rotate(pose.topple)
  ctx.translate(0, pose.bodyY)

  if (spec.plan === 'biped') {
    const hip: Pt = { x: 0, y: -14 * spec.stature }
    const sho: Pt = {
      x: Math.sin(pose.bodyLean) * 10 * spec.stature,
      y: hip.y - Math.cos(pose.bodyLean) * 12 * spec.stature,
    }
    const legLen = 7.6 * spec.stature
    const armLen = 7.4 * spec.stature * (spec.reach ?? 1)
    // Shoulders sit WIDER than hips — the single proportion that separates a
    // beast from a stick figure. A first pass had them equal and every biped
    // read as a small humanoid regardless of its bulk.
    const shoW = 3.4 * bulk

    // far leg, far arm — behind everything
    drawLimb(ctx, { x: hip.x - 2, y: hip.y }, pose.legFar, legLen, 4.8 * bulk, mid)
    drawLimb(ctx, { x: sho.x - shoW, y: sho.y }, pose.armFar, armLen, 3.8 * bulk, mid)

    // torso — chest and haunches as two masses, not one oval
    const tc = { x: (hip.x + sho.x) / 2, y: (hip.y + sho.y) / 2 }
    blob(ctx, { x: hip.x, y: hip.y - 2 }, 6 * bulk, 5 * spec.stature, mid, pose.bodyLean)
    blob(ctx, tc, 7.6 * bulk, 8.6 * spec.stature, body, pose.bodyLean)
    if (spec.hump) blob(ctx, { x: sho.x - 1, y: sho.y - 1 }, 6.6 * bulk, 4.8 * bulk, light, pose.bodyLean)

    // head
    const hc = joint(sho, Math.PI + pose.bodyLean + pose.headTilt, 7 * spec.stature)
    if (spec.mane) blob(ctx, hc, 8.2 * bulk, 7.8 * bulk, mid)
    blob(ctx, hc, 5.2 * bulk, 4.8 * bulk, light)
    blob(ctx, { x: hc.x + 3.6 * bulk, y: hc.y + 1.4 }, 2.9 * bulk, 2.3 * bulk, hi) // muzzle
    drawFace(ctx, spec, hc, bulk, dark, hi)

    // near leg, near arm — in front
    drawLimb(ctx, { x: hip.x + 2, y: hip.y }, pose.legNear, legLen, 5 * bulk, light)
    drawLimb(ctx, { x: sho.x + shoW, y: sho.y }, pose.armNear, armLen, 4 * bulk, light)
    if (spec.tail && spec.tail !== 'none') {
      drawTail(ctx, { x: hip.x - 4, y: hip.y - 1 }, pose.tail, spec.tail === 'long' ? 9 : 4, 2.6 * bulk, mid)
    }
  } else {
    // QUADRUPED — the spine runs horizontally and the front legs are the arms.
    const rear: Pt = { x: -7 * bulk, y: -12 * spec.stature }
    const front: Pt = { x: 7 * bulk, y: -12.5 * spec.stature - pose.bodyLean * 4 }
    const legLen = 6.4 * spec.stature

    drawLimb(ctx, { x: rear.x - 1, y: rear.y }, pose.legFar, legLen, 3.6 * bulk, mid)
    drawLimb(ctx, { x: front.x - 1, y: front.y }, pose.armFar, legLen, 3.4 * bulk, mid)

    // barrel
    const tc = { x: (rear.x + front.x) / 2, y: (rear.y + front.y) / 2 }
    blob(ctx, tc, 10.5 * bulk, 6 * bulk, body, pose.bodyLean * 0.5)
    blob(ctx, { x: rear.x, y: rear.y - 1 }, 6 * bulk, 5.2 * bulk, mid) // haunch
    if (spec.hump) blob(ctx, { x: front.x - 1, y: front.y - 4 }, 6 * bulk, 4.2 * bulk, light)

    // neck and head, carried forward and up
    const neck = { x: front.x + 4, y: front.y - 4 }
    bone(ctx, front, neck, 5.6 * bulk, body)
    const hc = joint(neck, Math.PI * 0.72 + pose.headTilt, 6.4 * spec.stature)
    if (spec.mane) blob(ctx, hc, 7.6 * bulk, 7 * bulk, mid)
    blob(ctx, hc, 4.4 * bulk, 3.9 * bulk, light)
    blob(ctx, { x: hc.x + 3.8 * bulk, y: hc.y + 1 }, 3 * bulk, 2.1 * bulk, hi)
    drawFace(ctx, spec, hc, bulk, dark, hi)

    drawLimb(ctx, { x: rear.x + 1, y: rear.y }, pose.legNear, legLen, 3.8 * bulk, light)
    drawLimb(ctx, { x: front.x + 1, y: front.y }, pose.armNear, legLen, 3.6 * bulk, light)
    if (spec.tail && spec.tail !== 'none') {
      drawTail(ctx, { x: rear.x - 6, y: rear.y - 1 }, pose.tail, spec.tail === 'long' ? 10 : 4, 2.2 * bulk, mid)
    }
  }
  ctx.restore()
}

/** A two-segment limb. The second angle is RELATIVE to the first, so an elbow
 *  bends with its upper arm instead of swinging independently in world space. */
function drawLimb(ctx: Ctx, from: Pt, [a, b]: [number, number], len: number, w: number, colour: string) {
  const knee = joint(from, a, len)
  const foot = joint(knee, a + b, len * 0.9)
  bone(ctx, from, knee, w, colour)
  bone(ctx, knee, foot, w * 0.82, colour)
}

function drawTail(ctx: Ctx, from: Pt, a: number, len: number, w: number, colour: string) {
  const mid = joint(from, Math.PI * 0.5 + a, len * 0.6)
  const tip = joint(mid, Math.PI * 0.5 + a * 1.6, len * 0.5)
  bone(ctx, from, mid, w, colour)
  bone(ctx, mid, tip, w * 0.6, colour)
}

function drawFace(ctx: Ctx, spec: RigSpec, hc: Pt, bulk: number, dark: string, hi: string) {
  // One eye is enough in profile, and two would read as a front-facing head.
  ctx.fillStyle = hi
  ctx.fillRect(hc.x + 1.2 * bulk, hc.y - 1.4 * bulk, 1.6, 1.6)
  ctx.fillStyle = dark
  ctx.fillRect(hc.x + 1.8 * bulk, hc.y - 1.1 * bulk, 0.9, 1.1)
  if (spec.horns) {
    // At 48px a horn is 3-4 pixels; anything subtler simply is not there.
    bone(ctx, { x: hc.x - 1, y: hc.y - 2.6 * bulk }, { x: hc.x + 6.5 * bulk, y: hc.y - 7 * bulk }, 2.6, hi)
    bone(ctx, { x: hc.x - 1, y: hc.y - 2.6 * bulk }, { x: hc.x - 5.5 * bulk, y: hc.y - 7 * bulk }, 2.6, hi)
  }
  if (spec.ears === 'round') blob(ctx, { x: hc.x - 2 * bulk, y: hc.y - 3.4 * bulk }, 1.7, 1.7, dark)
  if (spec.ears === 'pointed') {
    ctx.fillStyle = dark
    ctx.beginPath()
    ctx.moveTo(hc.x - 3 * bulk, hc.y - 2 * bulk)
    ctx.lineTo(hc.x - 1.2 * bulk, hc.y - 6 * bulk)
    ctx.lineTo(hc.x + 0.4 * bulk, hc.y - 2.4 * bulk)
    ctx.closePath()
    ctx.fill()
  }
}

// ── Quantise: what actually makes it pixel art ───────────────────────────────
/**
 * Snap the antialiased canvas onto the species ramp.
 *
 * Alpha becomes fully on or fully off — a soft edge is the single biggest tell
 * that something is a shrunken drawing rather than a sprite. Colour snaps to
 * the nearest ramp entry so the whole sheet stays within its palette however
 * many overlapping strokes built a pixel.
 */
export function quantise(ctx: Ctx, w: number, h: number, ramp: string[], flash: number) {
  const rgb = ramp.map(hexToRgb)
  const img = ctx.getImageData(0, 0, w, h)
  const d = img.data
  for (let i = 0; i < d.length; i += 4) {
    if (d[i + 3] < 110) { d[i + 3] = 0; continue }
    d[i + 3] = 255
    let bi = 0, bd = Infinity
    for (let c = 0; c < rgb.length; c++) {
      const dr = d[i] - rgb[c][0], dg = d[i + 1] - rgb[c][1], db = d[i + 2] - rgb[c][2]
      const dist = dr * dr + dg * dg + db * db
      if (dist < bd) { bd = dist; bi = c }
    }
    // A flash lifts each pixel UP the ramp rather than washing it white, so the
    // creature stays recognisably itself while it is lit.
    const k = Math.min(rgb.length - 1, bi + Math.round(flash * 2.2))
    d[i] = rgb[k][0]; d[i + 1] = rgb[k][1]; d[i + 2] = rgb[k][2]
  }
  ctx.putImageData(img, 0, 0)
}

function hexToRgb(h: string): [number, number, number] {
  const n = parseInt(h.slice(1), 16)
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}

// ── Sheet building ───────────────────────────────────────────────────────────
const sheets = new Map<string, HTMLCanvasElement>()

/**
 * Every animation of one species, laid out one row per animation, built once
 * and cached. This IS a sprite sheet — the only difference from a hand-drawn
 * one is that it was computed rather than painted.
 */
export function spriteSheet(key: string, spec: RigSpec): HTMLCanvasElement {
  const hit = sheets.get(key)
  if (hit) return hit
  const cv = document.createElement('canvas')
  cv.width = FRAME * FRAMES_PER_ANIM
  cv.height = FRAME * RIG_ANIMS.length
  const sheet = cv.getContext('2d')!

  // Each frame is drawn on its own scratch canvas: quantise() reads back a
  // whole rectangle, and doing that on the shared sheet would re-quantise every
  // frame already written to its left.
  const one = document.createElement('canvas')
  one.width = FRAME; one.height = FRAME
  const ctx = one.getContext('2d', { willReadFrequently: true })!

  RIG_ANIMS.forEach((anim, row) => {
    for (let f = 0; f < FRAMES_PER_ANIM; f++) {
      ctx.clearRect(0, 0, FRAME, FRAME)
      const pose = poseFor(anim, f / FRAMES_PER_ANIM, spec.plan)
      drawPose(ctx, spec, pose)
      quantise(ctx, FRAME, FRAME, spec.ramp, pose.flash)
      sheet.drawImage(one, f * FRAME, row * FRAME)
    }
  })
  sheets.set(key, cv)
  return cv
}

/** The sheet as a data URL, cached — CSS background-image needs a URL, and
 *  re-encoding a canvas per render would be pure waste. */
const urls = new Map<string, string>()
export function sheetUrl(speciesId: string): string {
  const hit = urls.get(speciesId)
  if (hit) return hit
  const u = spriteSheet(speciesId, rigFor(speciesId)).toDataURL('image/png')
  urls.set(speciesId, u)
  return u
}

// ── Species rigs ─────────────────────────────────────────────────────────────
// ⚠️ RAMPS were SAMPLED from `public/sprites/<id>.png`, not invented — each
// species' pixel sprite carries the colours of the portrait the player already
// associates with it. Regenerate with tools/sample_ramp.py if the art changes.
export const RAMPS: Record<string, string[]> = {
  kongrath: ['#301d14', '#4a3223', '#644a34', '#7e6449', '#998161'],
  aegisox: ['#30160c', '#4a2a18', '#644128', '#7e5c3b', '#997952'],
  maneleo: ['#531f08', '#7f3e17', '#ac662d', '#d8944b', '#ffc26e'],
  grivvel: ['#30201b', '#4a362c', '#644f40', '#7e6956', '#99856e'],
  ursath: ['#30160f', '#4a291c', '#643f2c', '#7e593f', '#997656'],
}

export const RIGS: Record<string, RigSpec> = {
  // Silverback gorilla — heavy top, long arms, stands upright.
  kongrath: { plan: 'biped', ramp: RAMPS.kongrath, bulk: 1.3, stature: 0.96, reach: 1.32, ears: 'round', tail: 'none', hump: true },
  // Armoured ox — squat, horned, all mass over the shoulders.
  aegisox: { plan: 'quadruped', ramp: RAMPS.aegisox, bulk: 1.3, stature: 0.92, horns: true, ears: 'round', tail: 'stub', hump: true },
  // Lion — the mane is the silhouette.
  maneleo: { plan: 'quadruped', ramp: RAMPS.maneleo, bulk: 1.05, stature: 1.0, mane: true, ears: 'round', tail: 'long' },
  // Wolverine — low, long, slight.
  grivvel: { plan: 'quadruped', ramp: RAMPS.grivvel, bulk: 0.88, stature: 0.82, ears: 'pointed', tail: 'long' },
  // Great bear — the biggest thing on the field.
  ursath: { plan: 'biped', ramp: RAMPS.ursath, bulk: 1.4, stature: 1.05, reach: 1.05, ears: 'round', tail: 'stub', hump: true },
}

/** The rig for a species, falling back to a plain build for anything unrigged. */
export function rigFor(speciesId: string): RigSpec {
  return RIGS[speciesId] ?? {
    plan: 'quadruped', ramp: RAMPS[speciesId] ?? ['#1b1b24', '#333546', '#4d5068', '#6d7290', '#9aa0bd'],
    bulk: 1, stature: 1, ears: 'round', tail: 'long',
  }
}
