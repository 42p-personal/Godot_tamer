// ─────────────────────────────────────────────────────────────────────────────
// HEX (tamerengine M5) — the deployment grid math.
//
// Hexes are used ONLY for deployment: the player drops each monster onto a hex
// to set a starting formation, and the enemy is placed on its own hexes too.
// During the fight movement is continuous — so this file is small, just enough
// to lay a hex grid over a team's deployment zone and turn a chosen cell into
// the world Vec2 the engine's `placeA` / `placeB` accepts.
//
// Pointy-top axial hexes. World units are the engine's (40×22 field).
import { FIELD_H, FIELD_W, Vec2 } from './types'

export type HexZone = 'A' | 'B' | 'neutral'

/**
 * Hex circumradius in WORLD units — the one number that sets how fine the board is.
 *
 * ⚠️ IT IS A WORLD SIZE, NOT A COUNT, and that is the whole point: a bigger arena
 * gets MORE hexes of the same size rather than the same few stretched to fit. The
 * Wash Pool (30x30) and the Blowing House (47x22) should feel like the same board
 * material cut to different rooms.
 *
 * ⚠️ 2.6 WAS TOO COARSE TO PLAY WITH. It left a deploy zone of six to eight cells
 * for up to five monsters — barely a choice, and the reason the board read as a few
 * scattered markers rather than somewhere you position a team. At 1.4 a zone offers
 * roughly fifty.
 *
 * ⚠️ THE FLOOR IS SET BY MONSTER SIZE, NOT BY TASTE. Neighbouring centres in a
 * regular hex lattice sit √3·size apart, and a monster has radius 0.9, so anything
 * at or below 1.04 lets two deployed monsters overlap before the fight even starts.
 * 1.4 gives 2.42 between neighbours — a clear 0.6 of daylight.
 */
export const HEX_SIZE = 1.4

/** Column spacing — also the full width of a pointy-top hex. */
export const HEX_W = Math.sqrt(3) * HEX_SIZE
/** Row spacing — three quarters of the hex height. */
export const HEX_ROW = 1.5 * HEX_SIZE
/** How many hex columns deep each side's deployment band is. */
export const DEPLOY_COLS = 3

/**
 * The arena size that a whole number of hexes fills EXACTLY.
 *
 * ⚠️ THE MAP IS BUILT FROM THE GRID, NOT THE OTHER WAY ROUND. Arenas used to be
 * authored as round world numbers (30x18, 47x22) and the lattice was laid over the
 * top, so the last column and row fell wherever they fell and left a ragged strip of
 * board against the wall. Sizing from `cols x rows` makes the left and right edges
 * land exactly on a column boundary and the top and bottom on a row boundary.
 *
 * ⚠️ POINTY-TOP HEXES HAVE VERTICAL FLAT SIDES, which is why the left and right
 * edges can be genuinely flush: a column of them has a straight edge. The top and
 * bottom are vertex rows, so `h` includes the half-hex above the first row centre
 * and below the last — that is the `+ HEX_SIZE` at each end, not a fudge factor.
 *
 * ⚠️ ODD ROWS STILL START HALF A HEX IN. That notch is filled by the clipped
 * half-hexes `fieldHexCoverage` generates past the boundary, so the edge reads as a
 * straight line of alternating whole and half cells — the way a hex board is drawn
 * flush. It is not dead space.
 */
export function hexArenaSize(cols: number, rows: number): { w: number; h: number } {
  return {
    w: +(cols * HEX_W).toFixed(2),
    h: +(2 * HEX_SIZE + (rows - 1) * HEX_ROW).toFixed(2),
  }
}

export interface HexCell {
  /** axial coordinates, unique per cell */
  q: number; r: number
  /** world-space centre — this is what feeds the sim's placement */
  cx: number; cy: number
}
export interface FieldHexCell extends HexCell {
  /** which band of the field this cell falls in — A/B deploy zones or the middle */
  zone: HexZone
}

/**
 * EVERY hex needed to cover the field edge to edge, including the ones that hang
 * off it. `playable` marks the subset that `fieldHexCells` returns.
 *
 * ⚠️ THE BOARD MUST REACH THE ARENA WALL. `fieldHexCells` only emits cells that sit
 * a full radius inside the field, because a deployment must not straddle an edge —
 * correct for placement, and it leaves a band of bare ground all round that makes
 * the board look like a rug thrown on the floor rather than the floor itself. This
 * generates the tiling PAST the boundary; the arena crops it (`.dp-field` clips),
 * so the hexes run under the wall the way a real tiled floor does.
 *
 * ⚠️ AND IT ADDS NO PLACEMENT. The playable set is exactly `fieldHexCells` — same
 * centres, same count, so `autoDeployByRole` and every harness are untouched. The
 * overhanging cells are scenery: they draw, they never take a monster. Widening the
 * placeable set here would have been a gameplay change smuggled in as a paint job.
 */
export interface CoverCell extends FieldHexCell { playable: boolean }

export function fieldHexCoverage(size = HEX_SIZE): CoverCell[] {
  const w = Math.sqrt(3) * size
  const h = (3 / 2) * size
  const halfW = w / 2
  const play = new Set(fieldHexCells(size).map((c) => `${c.cx},${c.cy}`))
  const zA = deployZone('A'), zB = deployZone('B')
  const out: CoverCell[] = []
  // Rows run from above the top edge to below the bottom one; a hex counts if any
  // part of it falls inside the field.
  // ⚠️ THE MARGIN IS TWO CELLS, NOT ONE, BECAUSE THE BOARD IS SEEN AT AN ANGLE. The
  // camera tapers the far edge in (see camera.ts:CAM_TAPER), so the plane has to reach
  // further past the wall than the wall itself to still cover the frame's far corners
  // once projected. One cell was enough while the board was flat and cropped at its
  // own edge; under the tilt it left bare triangles at the top corners.
  // ⚠️ AND ODD ROWS ONLY REACHED HALF AS FAR. They are shifted right by half a cell,
  // so at `q = -1` an odd row started at x = 0 while an even row started at −w — the
  // overhang alternated between one cell and none, and the gap appeared on every
  // other row. Starting at −2 makes the SHORTER of the two rows deep enough.
  for (let r = -3; ; r++) {
    const cy = size + r * h
    if (cy - size > FIELD_H + h) break
    if (cy + size < -h) continue
    // ⚠️ `((r % 2) + 2) % 2` — plain `r % 2` is NEGATIVE for negative rows in JS, so
    // the rows above the field would shift the wrong way and the tiling would seam
    // exactly where it is hardest to notice: under the arena wall.
    const xOff = (((r % 2) + 2) % 2) * halfW
    for (let q = -2; ; q++) {
      const cx = halfW + xOff + q * w
      if (cx - halfW > FIELD_W + w) break
      // ⚠️ THE SKIP GUARD HAS TO MOVE OUT WITH THE LOOP BOUND, and forgetting it made
      // the wider margin above do nothing at all. `cx + halfW < 0` drops any cell
      // entirely left of the wall — correct when the board was cropped at its own
      // edge, but it silently threw away exactly the extra column the tilt needs, so
      // starting the loop at −2 still produced a −1 board. It measured as a 32px bare
      // triangle at the top-LEFT only: even rows kept one column of overhang, odd rows
      // (shifted half a cell right) kept none, so the gap appeared on alternate rows.
      if (cx + halfW < -w) continue
      const key = `${+cx.toFixed(2)},${+cy.toFixed(2)}`
      // ⚠️ BOTH BOUNDS. This only ever tested the INNER edge (`cx <= zA.x1`), so any
      // cell left of the zone's own `x0` was still tagged 'A'. Invisible at the old
      // radius because the first column landed at 2.6, inside the 1.5 margin; at 1.4
      // the first column sits at 1.4 and is deployable while being outside the band
      // that scouting and the UI describe. A zone should mean the zone.
      const zone: HexZone = cx >= zA.x0 && cx <= zA.x1 ? 'A'
        : cx >= zB.x0 && cx <= zB.x1 ? 'B' : 'neutral'
      out.push({ q, r, cx: +cx.toFixed(2), cy: +cy.toFixed(2), zone, playable: play.has(key) })
    }
  }
  return out
}

/**
 * A team's deployment zone: the back band on its own side of the field.
 *
 * ⚠️ EXACTLY `DEPLOY_COLS` HEX COLUMNS DEEP, not a percentage of the width. As 24%
 * it grew with the arena — a 47-wide board handed you a 12.8-unit band and a 26-wide
 * one 7.7, so "your back three ranks" meant something different on every map and a
 * big arena let you spread out in ways a small one never could. A fixed number of
 * RANKS is the rule a player can actually hold in their head, and it is what makes
 * two arenas comparable to deploy on.
 *
 * ⚠️ The band is measured in hex columns from the wall, so it always ends on a
 * column boundary — no half-rank of cells that look placeable and are not.
 */
export function deployZone(side: 'A' | 'B'): { x0: number; x1: number; y0: number; y1: number } {
  const band = DEPLOY_COLS * HEX_W
  return side === 'A'
    ? { x0: 0, x1: band, y0: 0, y1: FIELD_H }
    : { x0: FIELD_W - band, x1: FIELD_W, y0: 0, y1: FIELD_H }
}

/**
 * ONE continuous pointy-top hex grid over the WHOLE field, each cell tagged with
 * the band it lands in. The deploy screen draws all of them (the middle band
 * faint, the two zones live) — the board reads as fully hexed, TFT-style, while
 * the grid stays a single aligned lattice so nothing seams at the zone edges.
 * `size` is the hex radius in world units — tuned so a cell comfortably holds one
 * monster (radius 0.9) past the ~1.19 non-overlap gap, so a placed formation
 * never starts overlapping.
 */
/**
 * The tile for one cell: a REGULAR pointy-top hexagon, width √3·size, height 2·size.
 *
 * ⚠️ THIS WAS NOT REGULAR UNTIL THE LATTICE WAS FIXED, and the two go together. The
 * grid used to step columns by √3·size and rows by 1.5·size while offsetting odd
 * COLUMNS vertically — which is half of a pointy-top layout and half of a flat-top
 * one. No regular hexagon tiles that, so the board was first drawn as undersized
 * pips (visibly scattered) and then as the lattice's Voronoi cell, which tiles but
 * is SQUASHED — 5.35 wide by 3.9 tall — and looks wrong for the obvious reason that
 * it is not symmetrical. Both were workarounds for a malformed grid.
 *
 * The fix is one line in `fieldHexCells`: offset odd ROWS horizontally instead. Same
 * spacings, now a genuine pointy-top lattice, and a regular hexagon tiles it exactly.
 */
export function hexTile(size = HEX_SIZE): { w: number; h: number } {
  return { w: Math.sqrt(3) * size, h: 2 * size }
}

export function fieldHexCells(size = HEX_SIZE): FieldHexCell[] {
  const w = Math.sqrt(3) * size       // hex WIDTH, and the spacing between columns
  const h = (3 / 2) * size            // vertical spacing between rows (¾ of hex height)
  const zA = deployZone('A'), zB = deployZone('B')
  const cells: FieldHexCell[] = []
  // ⚠️ ODD ROWS SHIFT SIDEWAYS — this is what makes it a real pointy-top lattice.
  // It used to offset odd COLUMNS downward instead, which pairs a pointy-top column
  // spacing with a flat-top offset: solve the two spacings for a regular hexagon's
  // radius and you get 3.00 and 2.25, so nothing regular could ever tile it. The
  // deploy board spent a year hiding that, first with undersized cells and then with
  // a squashed Voronoi tile. One offset moved, and a regular hexagon fits exactly.
  // ⚠️ THE FIRST COLUMN'S LEFT EDGE IS THE WALL. Centres start at HALF a hex in
  // (`w / 2`), not a full radius — a pointy-top hex is `w` wide, so a centre at `w/2`
  // puts its flat left side exactly on x=0. Starting at `size` instead left a sliver
  // of bare board against the wall on every map, because `size` is the hex's
  // half-HEIGHT and has nothing to do with its width.
  let r = 0
  for (let cy = size; cy <= FIELD_H - size + 0.01; cy += h, r++) {
    const xOff = (r % 2) * (w / 2)
    let q = 0
    for (let cx = w / 2 + xOff; cx <= FIELD_W - w / 2 + 0.01; cx += w, q++) {
      // ⚠️ BOTH BOUNDS. This only ever tested the INNER edge (`cx <= zA.x1`), so any
      // cell left of the zone's own `x0` was still tagged 'A'. Invisible at the old
      // radius because the first column landed at 2.6, inside the 1.5 margin; at 1.4
      // the first column sits at 1.4 and is deployable while being outside the band
      // that scouting and the UI describe. A zone should mean the zone.
      const zone: HexZone = cx >= zA.x0 && cx <= zA.x1 ? 'A'
        : cx >= zB.x0 && cx <= zB.x1 ? 'B' : 'neutral'
      cells.push({ q, r, cx: +cx.toFixed(2), cy: +cy.toFixed(2), zone })
    }
  }
  return cells
}

/**
 * The hex cells a team may deploy on — its band of the continuous field grid.
 * Derived from `fieldHexCells` so a zone cell and its neighbour in the middle
 * band share one lattice (a placed formation lines up with the drawn grid).
 */
export function hexCells(side: 'A' | 'B', size = HEX_SIZE): HexCell[] {
  return fieldHexCells(size)
    .filter((c) => c.zone === side)
    .map(({ q, r, cx, cy }) => ({ q, r, cx, cy }))
}

/** Enemy auto-deploy: sort its team by role and lay it onto its hexes —
 *  anchors (sturdy) on the FRONT column, artillery/support on the BACK. */
export function autoDeployByRole(
  side: 'A' | 'B',
  team: { front: number }[], // `front` = CON+STR vs INT+WIS score; higher = more front-line
  size = HEX_SIZE,
): Vec2[] {
  const cells = hexCells(side, size)
  // Front column = the one nearest the enemy (max cx for A, min cx for B).
  const frontFirst = [...cells].sort((a, b) => (side === 'A' ? b.cx - a.cx : a.cx - b.cx) || a.cy - b.cy)
  const order = team.map((t, i) => ({ i, front: t.front })).sort((a, b) => b.front - a.front)
  const out: Vec2[] = new Array(team.length)
  order.forEach((t, k) => {
    const cell = frontFirst[k] ?? frontFirst[frontFirst.length - 1]
    out[t.i] = { x: cell.cx, y: cell.cy }
  })
  return out
}
