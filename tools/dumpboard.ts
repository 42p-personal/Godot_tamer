// Export a deploy board's real geometry as JSON, for rendering to an image.
//
// ⚠️ EXPORTS FROM THE CODE, IT DOES NOT RE-DERIVE. The hex centres, the tile shape,
// the zones and the obstacle rectangles all come from `hex.ts` / `maps.ts`, so a
// picture made from this is a picture of what the game actually computes. Writing a
// second copy of the lattice maths in the renderer script would be the same
// authored-twice trap that has already cost this project a day.
//
// Usage: npx tsx tools/dumpboard.ts <arena-id> > board.json
import { mapById } from '../src/tamerengine/maps'
import { fieldHexCoverage, hexTile, HEX_SIZE } from '../src/tamerengine/hex'
import { setFieldSize } from '../src/tamerengine/types'
import { propSprite, themeById } from '../src/tamerengine/themes'
import { CAM_COS, CAM_DEPTH, CAM_FIT, CAM_SIN, CAM_Y_OFFSET, CAM_HEIGHT_RATIO, project } from '../src/tamerengine/camera'

const id = process.argv[2]
const m = mapById(id)
if (!m) { console.error(`no arena '${id}'`); process.exit(1) }

setFieldSize(m.w, m.h)
const theme = themeById(m.theme)
const tile = hexTile()

console.log(JSON.stringify({
  id: m.id, name: m.name, w: m.w, h: m.h, brief: m.brief,
  ground: theme.ground, tile, hexSize: HEX_SIZE,
  // ⚠️ THE CAMERA TRAVELS AS PRIMITIVES *AND* AS ANSWERS. drawboard.py has to project
  // arbitrary points (every prop's base), so it re-implements the three-line formula —
  // and a re-implementation is exactly how a preview starts lying about the game. The
  // `check` samples are reference outputs from the real `project()`; the renderer
  // asserts its own maths reproduces them before drawing anything.
  cam: {
    depth: CAM_DEPTH, sin: CAM_SIN, cos: CAM_COS, fit: CAM_FIT,
    yOffset: CAM_Y_OFFSET, heightRatio: CAM_HEIGHT_RATIO,
    check: [[-0.5, -0.5], [0.5, 0.5], [0.2, -0.1]].map(([u, v]) => project(u, v)),
  },
  // q/r travel because the renderer mirrors Deploy.tsx's per-cell brightness jitter,
  // which is hashed from the lattice coordinates — without them the preview would
  // have to invent its own variation and stop matching the screen.
  cells: fieldHexCoverage().map((c) => ({ x: c.cx, y: c.cy, q: c.q, r: c.r, zone: c.zone, playable: c.playable })),
  obstacles: m.obstacles.map((o) => ({ ...o, sprite: propSprite(theme, o.kind) })),
}))
