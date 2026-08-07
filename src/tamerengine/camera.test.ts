// The camera's geometry. Every number here was a bug at some point in getting the
// battlefield to read as a floor rather than a top-down diagram with stickers on it.
import { describe, it, expect } from 'vitest'
import {
  CAM_COS, CAM_FIT, CAM_HEIGHT_RATIO, CAM_TAPER, CAM_Y_OFFSET,
  NEAR_SCALE, FAR_SCALE, project, standScale,
} from './camera'

describe('the battlefield camera', () => {
  it('brings the near edge back to exactly the board width', () => {
    // ⚠️ THE NEAR CORNERS ARE NOT SPARE. Tilting pushes the bottom edge toward the eye
    // and makes it wider than the flat board; both deployment zones run along the LEFT
    // AND RIGHT walls, so anything cropped there is cells the player acts in.
    expect(project(0.5, 0.5).x).toBeCloseTo(0.5, 10)
    expect(project(-0.5, 0.5).x).toBeCloseTo(-0.5, 10)
    expect(CAM_FIT * NEAR_SCALE).toBeCloseTo(1, 10)
  })

  it('recentres the board, because the tilted board is not centred on the flat one', () => {
    // Perspective magnifies the near half and shrinks the far half, so the projected
    // board is asymmetric about the plane's own centre. Centring the PLANE left the
    // BOARD low, and three placeable cells hung off the bottom of the frame.
    const near = project(0, 0.5).y, far = project(0, -0.5).y
    expect(near + far).toBeGreaterThan(0)                 // it really is asymmetric
    expect((near + far) / 2).toBeCloseTo(CAM_Y_OFFSET, 10)
    // ...and with the offset applied, both edges land on the frame.
    const h = CAM_HEIGHT_RATIO
    expect(near - CAM_Y_OFFSET).toBeCloseTo(h / 2, 10)
    expect(far - CAM_Y_OFFSET).toBeCloseTo(-h / 2, 10)
  })

  it('squash and taper are separate knobs', () => {
    // ⚠️ THE FIRST ATTEMPT TREATED THEM AS ONE AND READ AS NO CAMERA AT ALL. A gentle
    // 26° tilt squashes a hex by ten percent, which the eye takes for a wonky drawing.
    // The tilt owns the squash; the eye distance owns the taper. A strong tilt at a
    // long lens gives a floor that plainly recedes AND a far rank that stays wide.
    expect(CAM_COS).toBeLessThan(0.75)      // the floor genuinely recedes
    expect(CAM_TAPER).toBeGreaterThan(0.82) // ...without pinching the far rank
  })

  it('keeps the far rank usable on our widest arena', () => {
    // The Smelt is 43.65 wide. Whatever the tilt, a back-rank cell must not shrink
    // below a size a player can aim at — this screen is a tactical grid first.
    expect(FAR_SCALE / NEAR_SCALE).toBe(CAM_TAPER)
    expect(43.65 * CAM_TAPER).toBeGreaterThan(36)
  })

  it('scales what stands on it by depth, near-to-far', () => {
    expect(standScale(17.5, 17.5)).toBeCloseTo(1, 10)          // at the near wall
    expect(standScale(0, 17.5)).toBeCloseTo(CAM_TAPER, 10)     // at the far wall
    // monotonic: nothing at the back may draw bigger than the same thing at the front
    let prev = 0
    for (let y = 0; y <= 17.5; y += 1.75) {
      const s = standScale(y, 17.5)
      expect(s).toBeGreaterThan(prev)
      prev = s
    }
  })

  it('is a pure projection — the middle of the board does not move sideways', () => {
    for (const v of [-0.5, -0.2, 0, 0.3, 0.5]) expect(project(0, v).x).toBeCloseTo(0, 12)
  })
})
