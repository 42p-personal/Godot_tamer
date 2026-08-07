// Hex deployment (tamerengine M5).
import { describe, it, expect } from 'vitest'
import { hexCells, deployZone, autoDeployByRole, hexTile, fieldHexCells, fieldHexCoverage, HEX_SIZE } from './hex'
import { hexJitter } from './Deploy'
import { generateMonster } from '../monster'
import { simulateFieldBattle } from './engine'
import { DEFAULT_TACTICS, Monster } from '../core'
import { FieldEvent, FIELD_W, FIELD_H, setFieldSize } from './types'

const plain = (seed: string): Monster =>
  ({ ...generateMonster(seed, { train: 600 }), tactics: { ...DEFAULT_TACTICS } }) as Monster
const snaps = (evs: FieldEvent[]) =>
  evs.filter((e) => e.kind === 'snapshot') as Extract<FieldEvent, { kind: 'snapshot' }>[]

describe('tamerengine — hex deployment', () => {
  it('cells sit inside the team deploy zone and never coincide', () => {
    for (const side of ['A', 'B'] as const) {
      const z = deployZone(side)
      const cells = hexCells(side)
      expect(cells.length).toBeGreaterThanOrEqual(6) // room for a full team
      const seen = new Set<string>()
      for (const c of cells) {
        expect(c.cx).toBeGreaterThanOrEqual(z.x0 - 0.01)
        expect(c.cx).toBeLessThanOrEqual(z.x1 + 0.01)
        const key = `${c.cx},${c.cy}`
        expect(seen.has(key)).toBe(false)
        seen.add(key)
      }
    }
  })

  it('cells are spaced wider than the non-overlap floor', () => {
    // Any two occupied cells must be far enough apart that placed monsters start
    // non-overlapping (the collision floor is ~1.19).
    const cells = hexCells('A')
    let worst = Infinity
    for (let i = 0; i < cells.length; i++) {
      for (let j = i + 1; j < cells.length; j++) {
        worst = Math.min(worst, Math.hypot(cells[i].cx - cells[j].cx, cells[i].cy - cells[j].cy))
      }
    }
    expect(worst).toBeGreaterThan(1.3)
  })

  it('auto-deploy puts the sturdiest monster on a front cell', () => {
    // front score = CON+STR - INT-WIS. Side A's front is the higher-x cells.
    const team = [{ front: -300 }, { front: 500 }, { front: 100 }]
    const placed = autoDeployByRole('A', team)
    // the sturdiest (index 1) should have the greatest x (closest to enemy)
    const maxX = Math.max(...placed.map((p) => p.x))
    expect(placed[1].x).toBe(maxX)
  })

  it('a chosen placement feeds through the sim; units start on their cells', () => {
    const cells = hexCells('A')
    const teamA = [plain('a0'), plain('a1'), plain('a2')]
    const placeA = [cells[0], cells[2], cells[4]].map((c) => ({ x: c.cx, y: c.cy }))
    const r = simulateFieldBattle({ seed: 'dep', teamA, teamB: [plain('b0'), plain('b1'), plain('b2')], placeA })
    const first = snaps(r.events)[0]
    // Each A unit starts at (or, after the setup non-overlap pass, very near) its
    // chosen cell — and no two share a spot.
    for (let i = 0; i < 3; i++) {
      const u = first.units.find((x) => x.id === 'A' + i)!
      expect(Math.hypot(u.x - placeA[i].x, u.y - placeA[i].y)).toBeLessThan(0.5)
    }
    const aPos = first.units.filter((u) => u.id[0] === 'A')
    for (let i = 0; i < aPos.length; i++) {
      for (let j = i + 1; j < aPos.length; j++) {
        expect(Math.hypot(aPos[i].x - aPos[j].x, aPos[i].y - aPos[j].y)).toBeGreaterThan(1.1)
      }
    }
  })
})

describe('hexTile — a regular hexagon on a real pointy-top lattice', () => {
  // ⚠️ THE LATTICE WAS MALFORMED AND TWO WORKAROUNDS HID IT. It stepped columns by
  // √3·size and rows by 1.5·size while offsetting odd COLUMNS vertically — half a
  // pointy-top layout, half a flat-top one, tiled by no regular hexagon at all.
  // The board was drawn first as undersized pips (visibly scattered) and then as the
  // lattice's Voronoi cell, which tiles but is squashed and looks wrong. Offsetting
  // odd ROWS instead makes it a genuine lattice; these pin that it stays one.
  it('is REGULAR — width and height in the exact √3 : 2 ratio', () => {
    const t = hexTile(2.6)
    expect(t.w / t.h).toBeCloseTo(Math.sqrt(3) / 2, 10)
  })

  it('same-row neighbours abut, and rows interlock by a quarter of the height', () => {
    const t = hexTile()
    const cells = fieldHexCells()
    const row0 = cells.filter((c) => c.r === 0).sort((a, b) => a.cx - b.cx)
    expect(row0[1].cx - row0[0].cx).toBeCloseTo(t.w, 1)

    const rows = [...new Set(cells.map((c) => c.cy))].sort((a, b) => a - b)
    // Row spacing is ¾ of the hex height — the signature of a pointy-top tiling.
    expect(rows[1] - rows[0]).toBeCloseTo(t.h * 0.75, 1)
  })

  it('odd rows are offset by exactly half a hex', () => {
    const t = hexTile()
    const cells = fieldHexCells()
    const r0 = Math.min(...cells.filter((c) => c.r === 0).map((c) => c.cx))
    const r1 = Math.min(...cells.filter((c) => c.r === 1).map((c) => c.cx))
    expect(r1 - r0).toBeCloseTo(t.w / 2, 1)
  })

  it('both deploy zones still hold a full team', () => {
    // ⚠️ Re-laying the lattice changes how many cells land in each band. A board
    // that is beautiful and cannot seat five monsters is a regression.
    for (const side of ['A', 'B'] as const) {
      expect(fieldHexCells().filter((c) => c.zone === side).length).toBeGreaterThanOrEqual(5)
    }
  })
})

describe('fieldHexCoverage — the board reaches the arena wall', () => {
  // ⚠️ `fieldHexCells` deliberately keeps every cell a full radius inside the field
  // so a deployment cannot straddle an edge. Correct for placement, and it leaves a
  // band of bare ground all round that makes the board look like a rug on the floor
  // rather than the floor. Coverage draws past the boundary and the arena crops it.
  it('spans past every edge of the field', () => {
    const t = hexTile()
    const cov = fieldHexCoverage()
    expect(Math.min(...cov.map((c) => c.cx - t.w / 2))).toBeLessThanOrEqual(0)
    expect(Math.max(...cov.map((c) => c.cx + t.w / 2))).toBeGreaterThanOrEqual(FIELD_W)
    expect(Math.min(...cov.map((c) => c.cy - t.h / 2))).toBeLessThanOrEqual(0)
    expect(Math.max(...cov.map((c) => c.cy + t.h / 2))).toBeGreaterThanOrEqual(FIELD_H)
  })

  it('adds no placeable cell — the playable set is exactly fieldHexCells', () => {
    // ⚠️ THE POINT OF THE SPLIT. Widening what can be placed on would be a gameplay
    // change smuggled in as a paint job; every harness seats teams from this set.
    const play = fieldHexCoverage().filter((c) => c.playable)
    const cells = fieldHexCells()
    expect(play.length).toBe(cells.length)
    const key = (c: { cx: number; cy: number }) => `${c.cx},${c.cy}`
    expect(new Set(play.map(key))).toEqual(new Set(cells.map(key)))
  })

  it('every row is evenly spaced and fully populated — no holes', () => {
    // ⚠️ ASSERTED AS A PROPERTY OF THE SET, not by looking up each neighbour by a
    // rounded key. The first version did that and failed on 4.85 -> 9.36: cell
    // centres are stored rounded to 2dp, so a computed neighbour misses by hundredths
    // and the test reports a hole in a grid that has none. Spacing is the real claim.
    const t = hexTile()
    const cov = fieldHexCoverage()
    const rows = [...new Set(cov.map((c) => c.cy))].sort((a, b) => a - b)
    for (let i = 1; i < rows.length; i++) {
      expect(rows[i] - rows[i - 1]).toBeCloseTo(t.h * 0.75, 1)
    }
    for (const y of rows) {
      const xs = cov.filter((c) => c.cy === y).map((c) => c.cx).sort((a, b) => a - b)
      expect(xs.length).toBeGreaterThan(1)
      for (let i = 1; i < xs.length; i++) expect(xs[i] - xs[i - 1]).toBeCloseTo(t.w, 1)
    }
  })
})

describe('HEX_SIZE is a world size, not a cell count', () => {
  // ⚠️ THE PROPERTY THE BOARD HAS TO HAVE. A bigger arena must get MORE hexes of the
  // same size, never the same few stretched to fit — the Wash Pool (30x30) and the
  // Blowing House (47x22) should read as one board material cut into different
  // rooms. Pinned because the natural way to "fix" a board that looks wrong is to
  // scale the cells to the field, which quietly destroys exactly that.
  const zoneCount = (w: number, h: number) => {
    setFieldSize(w, h)
    return fieldHexCells().filter((c) => c.zone === 'A').length
  }

  it('a wider arena buys APPROACH, not deployment room', () => {
    // ⚠️ THIS TEST USED TO ASSERT THE OPPOSITE, and was right until the deploy band
    // stopped being 24% of the width and became exactly DEPLOY_COLS ranks. Under the
    // old rule a 47-wide board handed you a 12.8-unit band and a 26-wide one 7.7, so
    // "your back three ranks" meant something different on every map. Now width adds
    // NEUTRAL ground — a longer walk — and leaves the formation you can set alone,
    // which is what makes two arenas comparable to deploy on.
    expect(zoneCount(47, 22)).toBe(zoneCount(30, 22))
    // ...and the extra width really is board, not nothing.
    setFieldSize(47, 22); const wide = fieldHexCells().length
    setFieldSize(30, 22); const narrow = fieldHexCells().length
    expect(wide).toBeGreaterThan(narrow)
  })

  it('a deeper arena offers strictly more too', () => {
    expect(zoneCount(30, 30)).toBeGreaterThan(zoneCount(30, 18))
  })

  it('the tile itself never changes size between arenas', () => {
    setFieldSize(30, 18); const small = hexTile()
    setFieldSize(47, 22); const big = hexTile()
    expect(big).toEqual(small)
  })

  it('leaves room to actually choose — a zone holds many times a full team', () => {
    // ⚠️ THE REASON THIS CHANGED. At the old radius a zone was six to eight cells
    // for up to five monsters, which is not a decision. Five is the largest team.
    setFieldSize(30, 18)
    expect(fieldHexCells().filter((c) => c.zone === 'A').length).toBeGreaterThanOrEqual(20)
  })

  it('never seats two monsters close enough to overlap', () => {
    // Neighbours sit √3·size apart; a monster has radius 0.9.
    expect(Math.sqrt(3) * HEX_SIZE).toBeGreaterThan(1.8)
  })
})

describe('per-cell brightness jitter', () => {
  // ⚠️ THESE GUARD A BUG THAT LOOKED DELIBERATE. `hexJitter` was first written
  // `(q * 7 + r * 13) % 7` — and `q * 7 % 7` is identically zero, so the column term
  // vanished, every cell in a row got the same brightness, and the board rendered in
  // flat horizontal bands. Nothing about that looks broken on screen; it was found by
  // reading the computed `--j` off six cells and noticing all six were equal. A
  // striped board is a real regression (it is the "made of paper" look coming back),
  // so the property gets a test rather than an eyeball.
  const grid = (): number[][] =>
    Array.from({ length: 8 }, (_, r) => Array.from({ length: 12 }, (_, q) => hexJitter(q, r)))

  it('varies along BOTH axes, not just down the rows', () => {
    const g = grid()
    // a row must not be one flat value...
    expect(new Set(g[0]).size).toBeGreaterThan(1)
    // ...and neither must a column.
    expect(new Set(g.map((row) => row[0])).size).toBeGreaterThan(1)
  })

  it('uses its whole range, roughly evenly', () => {
    const flat = grid().flat()
    expect(new Set(flat).size).toBe(7)
    const counts = [...new Set(flat)].map((v) => flat.filter((x) => x === v).length)
    // 96 cells over 7 values — no value may be starved or dominate.
    expect(Math.max(...counts) - Math.min(...counts)).toBeLessThanOrEqual(2)
  })

  it('stays subtle, and is stable for a given cell', () => {
    const flat = grid().flat()
    expect(Math.min(...flat)).toBeCloseTo(0.94, 5)
    expect(Math.max(...flat)).toBeCloseTo(1.06, 5)
    // hashed, not rolled: the same cell must render identically every time, or the
    // board shimmers on every rerender.
    expect(hexJitter(5, 3)).toBe(hexJitter(5, 3))
  })

  it('handles the negative q,r of the overhanging edge cells', () => {
    // fieldHexCoverage generates cells PAST all four walls; a raw `%` on a negative
    // would index outside the range and give a brightness below the floor.
    for (const [q, r] of [[-1, -1], [-3, 0], [0, -5], [-4, -7]]) {
      expect(hexJitter(q, r)).toBeGreaterThanOrEqual(0.94)
      expect(hexJitter(q, r)).toBeLessThanOrEqual(1.06)
    }
  })
})
