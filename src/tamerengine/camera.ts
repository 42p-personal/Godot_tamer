// THE CAMERA — the one place that decides how the battlefield is seen.
//
// ⚠️ THE PROPS LOOKED "STUCK ON" BECAUSE THE GROUND AND THE PROPS DISAGREED ABOUT
// WHERE THE CAMERA WAS. The ground was drawn top-down (you are looking straight down
// at boards, gravel, a wash floor) and every prop was drawn side-on (you are looking
// at a barrel from the side, at eye level). Both images are fine; together they are
// two photographs of two different scenes, and no shadow, outline or resolution fixes
// that — a viewer reads the mismatch instantly as a sticker on a backdrop.
//
// The fix is not to redraw the props. It is to give the GROUND a camera, so that a
// side-on sprite standing upright out of it is the correct thing to draw. That is
// what TFT, Auto Chess and the rest of the genre do: the board is a plane tilted away
// from the viewer, and everything on it is a billboard standing up from its footprint.
//
// ⚠️ THIS IS A RENDERER CHANGE ONLY, AND MUST STAY ONE. The engine keeps working in
// flat world units — positions, ranges, collisions and the goldens are all untouched,
// because the tilt exists only between the world and the screen. Nothing here may ever
// be imported by engine.ts.
//
// ⚠️ SQUASH AND TAPER ARE TWO DIFFERENT KNOBS, AND TREATING THEM AS ONE IS WHY THE
// FIRST ATTEMPT DID NOT WORK. The worry was real — our arenas run to 18x8 (the Smelt)
// where TFT's board is 7x8 and nearly square, and a wide board under a steep camera
// squeezes the far rank into a sliver. The deploy screen is a TACTICAL GRID before it
// is a picture: ranks have to be countable. So the tilt was set gently, at 26°, and
// the result read as no camera at all — cos 26° squashes a hex by ten percent, which
// the eye takes for a slightly wonky drawing rather than a floor.
//
// But the two effects have separate causes. The TILT decides how much the floor is
// foreshortened; the DEPTH decides how much the far edge narrows. Pushing the eye back
// while tilting further gives a floor that plainly recedes AND a far rank as wide as
// the gentle version had. That is the setting: a strong tilt at a long lens.

/** How far the board leans away from the viewer — this is the SQUASH. */
export const CAM_TILT_DEG = 46
/** Distance from the eye to the board, in board HEIGHTS — this is the TAPER. Long, so
 *  a 43-unit-wide arena's far rank stays as wide as it was under the gentle tilt. */
export const CAM_DEPTH = 5.0

const RAD = (CAM_TILT_DEG * Math.PI) / 180
export const CAM_SIN = Math.sin(RAD)
export const CAM_COS = Math.cos(RAD)

/**
 * Perspective scale at depth `v`, where v is the distance from the board's centre
 * line as a fraction of board height: −0.5 is the far wall, +0.5 the near one.
 */
export const depthScale = (v: number): number => CAM_DEPTH / (CAM_DEPTH - v * CAM_SIN)

export const NEAR_SCALE = depthScale(0.5)
export const FAR_SCALE = depthScale(-0.5)

/**
 * The uniform scale that brings the projected NEAR edge back to the board's own
 * width.
 *
 * ⚠️ WITHOUT IT THE NEAR CORNERS LEAVE THE FRAME, AND THEY ARE NOT SPARE. Tilting
 * pushes the bottom edge toward the eye, which makes it wider than the flat board —
 * and both deployment zones run along the LEFT AND RIGHT walls, so what would be
 * cropped is the one part of the board the player acts in.
 */
export const CAM_FIT = 1 / NEAR_SCALE

/** Far edge width as a fraction of the near edge — the visible taper. */
export const CAM_TAPER = FAR_SCALE / NEAR_SCALE

/** Projected height as a fraction of the flat board's height. */
export const CAM_HEIGHT_RATIO = (CAM_COS * (1 + CAM_TAPER)) / 2

/**
 * How far the projected board's centre sits BELOW the plane's own centre, as a
 * fraction of board height.
 *
 * ⚠️ THE TILTED BOARD IS NOT CENTRED ON THE FLAT ONE, AND ASSUMING IT WAS PUSHED THE
 * NEAR RANK OFF THE BOTTOM OF THE SCREEN. Perspective magnifies the near half and
 * shrinks the far half, so the projected board runs from −0.5·cos·taper to +0.5·cos —
 * asymmetric about zero. Centring the PLANE therefore leaves the BOARD low by this
 * much, which measured as three placeable cells hanging 19px past the frame. Both
 * deployment zones live on the walls, so what fell off was cells the player uses.
 */
export const CAM_Y_OFFSET = (CAM_COS * (1 - CAM_TAPER)) / 4

/**
 * Project a point on the board to the screen.
 *
 * Takes and returns CENTRED FRACTIONS: `u` is the distance from the middle as a
 * fraction of board width, `v` the same for height (+v is toward the viewer). Returns
 * the same for the screen, plus `s`, the scale everything standing at that depth is
 * drawn at.
 *
 * ⚠️ FRACTIONS, NOT PIXELS, SO THE CSS AND THE PREVIEW RENDERER CANNOT DRIFT. The
 * browser derives the same projection from `perspective` + `rotateX`; this function
 * is what tools/drawboard.py mirrors and what the tests pin. If the two ever disagree
 * the preview lies about the game, which has already cost this project a day once.
 */
export function project(u: number, v: number): { x: number; y: number; s: number } {
  const s = depthScale(v) * CAM_FIT
  return { x: u * s, y: v * CAM_COS * s, s }
}

/**
 * The scale a thing standing at world `y` on a board `h` deep is drawn at.
 * 1.0 at the near wall, `CAM_TAPER` at the far one.
 */
export const standScale = (y: number, h: number): number => project(0, y / h - 0.5).s
