// The pixel rig (v0.93).
//
// The failure this file exists to catch is a rig that RENDERS but does not
// ANIMATE — every frame identical, or a limb whose angle never changes. That
// looks completely fine in a still screenshot and completely broken in motion,
// which is exactly the class of bug a test has to carry because a glance at the
// code will not.
//
// Only the pose maths is tested here, not the canvas: `drawPose`/`quantise`
// need a real 2D context, which the node test environment has no business
// providing. Poses are the part with the logic in them.
import { describe, it, expect } from 'vitest'
import {
  poseFor, RIG_ANIMS, RIGS, RAMPS, rigFor, FRAMES_PER_ANIM, Pose, RigAnim,
} from './pixelRig'

const frames = (anim: RigAnim, plan: 'biped' | 'quadruped' = 'biped') =>
  Array.from({ length: FRAMES_PER_ANIM }, (_, i) => poseFor(anim, i / FRAMES_PER_ANIM, plan))

/** Every number in a pose, flattened — for "did anything at all change" checks. */
const flat = (p: Pose) => [
  p.bodyY, p.bodyLean, p.headTilt, ...p.armFar, ...p.armNear,
  ...p.legFar, ...p.legNear, p.tail, p.topple, p.flash,
]

describe('pixel rig — the rigs themselves', () => {
  it('every rigged species has a ramp, and every ramp is 5 usable colours', () => {
    for (const [id, spec] of Object.entries(RIGS)) {
      expect(RAMPS[id], `${id} has no ramp`).toBeTruthy()
      expect(spec.ramp, `${id} ramp length`).toHaveLength(5)
      for (const c of spec.ramp) expect(c, `${id}: ${c}`).toMatch(/^#[0-9a-f]{6}$/)
    }
  })

  it('ramps run dark to light, so shading reads in one direction', () => {
    const lum = (c: string) => {
      const n = parseInt(c.slice(1), 16)
      return 0.2126 * ((n >> 16) & 255) + 0.7152 * ((n >> 8) & 255) + 0.0722 * (n & 255)
    }
    for (const [id, spec] of Object.entries(RIGS)) {
      const ls = spec.ramp.map(lum)
      for (let i = 1; i < ls.length; i++) {
        expect(ls[i], `${id} ramp step ${i} is not lighter than ${i - 1}`).toBeGreaterThan(ls[i - 1])
      }
    }
  })

  it('falls back to a usable rig for an unrigged species', () => {
    const r = rigFor('no-such-monster')
    expect(r.ramp).toHaveLength(5)
    expect(r.bulk).toBeGreaterThan(0)
  })
})

describe('pixel rig — the limbs actually move', () => {
  it('no animation is a set of identical frames', () => {
    for (const anim of RIG_ANIMS) {
      const seen = new Set(frames(anim).map((p) => JSON.stringify(flat(p))))
      expect(seen.size, `${anim} never changes — it would render as a still`).toBeGreaterThan(1)
    }
  })

  // The whole point of the rig over the portrait path: ARMS SWING. A rig whose
  // arm angles are pinned at 0 is just a bobbing picture with extra steps.
  it('every animation moves at least one arm', () => {
    for (const anim of RIG_ANIMS) {
      const fs = frames(anim)
      const span = (pick: (p: Pose) => number) => {
        const v = fs.map(pick)
        return Math.max(...v) - Math.min(...v)
      }
      const arms = Math.max(
        span((p) => p.armFar[0]), span((p) => p.armNear[0]),
        span((p) => p.armFar[1]), span((p) => p.armNear[1]),
      )
      expect(arms, `${anim}: no arm moves at all`).toBeGreaterThan(0.05)
    }
  })

  it('walking swings arms and legs in OPPOSITION, not together', () => {
    for (const plan of ['biped', 'quadruped'] as const) {
      const fs = frames('move', plan)
      // Near arm forward should coincide with near leg back. If the two are in
      // phase the creature reads as a toy being shuffled, not as walking.
      const agree = fs.filter((p) => Math.sign(p.armNear[0]) === Math.sign(p.legNear[0])).length
      expect(agree, `${plan}: arms and legs swing in phase`).toBeLessThan(fs.length / 2)
    }
  })

  it('a walk bobs twice per stride, since there are two footfalls', () => {
    const ys = frames('move').map((p) => p.bodyY)
    // Count local minima around the cycle (it wraps, so compare cyclically).
    let dips = 0
    for (let i = 0; i < ys.length; i++) {
      const prev = ys[(i - 1 + ys.length) % ys.length]
      const next = ys[(i + 1) % ys.length]
      if (ys[i] < prev && ys[i] <= next) dips++
    }
    expect(dips, 'body bobs once per stride — that is a limp').toBeGreaterThanOrEqual(2)
  })

  it('attack anticipates before it strikes', () => {
    // The arm must travel BACKWARDS before it travels forwards; a strike with no
    // wind-up gives the player nothing to read.
    const fs = frames('attack')
    const back = Math.min(...fs.map((p) => p.armNear[0]))
    const fwd = Math.max(...fs.map((p) => p.armNear[0]))
    expect(back, 'no wind-up').toBeLessThan(-0.5)
    expect(fwd, 'no follow-through').toBeGreaterThan(0.5)
    expect(fs.findIndex((p) => p.armNear[0] === back))
      .toBeLessThan(fs.findIndex((p) => p.armNear[0] === fwd))
  })

  it('only death topples, and it stays within its frame', () => {
    for (const anim of RIG_ANIMS) {
      const top = Math.max(...frames(anim).map((p) => Math.abs(p.topple)))
      if (anim === 'dead') expect(top, 'death does not fall').toBeGreaterThan(1)
      else expect(top, `${anim} topples`).toBe(0)
    }
    // ⚠️ Toppling about the feet throws the body sideways; at the original 1.45
    // rad every death frame was clipped by the frame edge. The engine offsets
    // the pivot to compensate, but the angle itself still has to stay sane.
    const maxTopple = Math.max(...frames('dead').map((p) => p.topple))
    expect(maxTopple).toBeLessThan(1.35)
  })

  it('flashes on impact frames only', () => {
    const lit = (a: RigAnim) => Math.max(...frames(a).map((p) => p.flash))
    expect(lit('attack')).toBeGreaterThan(0.5)
    expect(lit('hurt')).toBeGreaterThan(0.5)
    expect(lit('idle')).toBe(0)
    expect(lit('move')).toBe(0)
    expect(lit('dead')).toBe(0)
  })

  it('is a pure function — the same frame always poses the same', () => {
    for (const anim of RIG_ANIMS) {
      expect(JSON.stringify(poseFor(anim, 0.375, 'biped')))
        .toBe(JSON.stringify(poseFor(anim, 0.375, 'biped')))
    }
  })
})
