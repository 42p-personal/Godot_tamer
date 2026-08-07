// Tests the PATH LAYER in isolation, with a real line-of-sight function but no
// engine. What matters is the routing decision, not what a monster does with it.
import { describe, it, expect } from 'vitest'
import { buildNavGraph, nextWaypoint, LosFn } from './navgraph'
import { hasLineOfSight } from './engine'
import type { Obstacle, Vec2 } from './types'

const losFor = (obs: Obstacle[]): LosFn => (a, b) => hasLineOfSight(a, b, obs)
const PAD = 0.79 // matches the engine's radius*0.6 + 0.25

/** A wall across the middle, with a gap at each end. */
const WALL: Obstacle[] = [{ x: 18, y: 6, w: 3, h: 10 }]

describe('buildNavGraph', () => {
  it('puts a node outside each corner of each obstacle', () => {
    const g = buildNavGraph(WALL, PAD, losFor(WALL))
    expect(g.nodes).toHaveLength(4)
    for (const n of g.nodes) {
      // Every node must be OUTSIDE the block it belongs to, or a path aims at a
      // point the unit is forbidden to stand on.
      expect(hasLineOfSight(n, n, WALL)).toBe(true)
      const insideX = n.x > WALL[0].x && n.x < WALL[0].x + WALL[0].w
      const insideY = n.y > WALL[0].y && n.y < WALL[0].y + WALL[0].h
      expect(insideX && insideY).toBe(false)
    }
  })

  it('⚠️ drops a corner swallowed by a neighbouring block', () => {
    // ⚠️ THE FIXTURE HAS TO PIN THE THING IT CLAIMS TO TEST. The first version
    // used two EQUAL-height blocks side by side and asserted nodes were dropped
    // — but that configuration swallows nothing: every seam corner sits above or
    // below both blocks and is genuinely standable. The test failed and the code
    // was right. A small block against the FACE of a bigger one is the case that
    // actually swallows corners: the two on the shared side land inside the big
    // block, and a path routed through them is a path into a wall.
    const pair: Obstacle[] = [{ x: 10, y: 10, w: 8, h: 8 }, { x: 18, y: 12, w: 2, h: 2 }]
    const g = buildNavGraph(pair, PAD, losFor(pair))
    expect(g.nodes.length).toBe(6) // 4 + 4, minus the 2 buried in the big block
    for (const n of g.nodes) {
      for (const o of pair) {
        const inside = n.x > o.x && n.x < o.x + o.w && n.y > o.y && n.y < o.y + o.h
        expect(inside).toBe(false)
      }
    }
  })

  it('respects field bounds when asked', () => {
    const edge: Obstacle[] = [{ x: 0, y: 0, w: 4, h: 4 }]
    const g = buildNavGraph(edge, PAD, losFor(edge), { w: 40, h: 22 })
    for (const n of g.nodes) {
      expect(n.x).toBeGreaterThanOrEqual(0.5)
      expect(n.y).toBeGreaterThanOrEqual(0.5)
    }
  })

  it('only links corners that can actually see each other', () => {
    const g = buildNavGraph(WALL, PAD, losFor(WALL))
    // The two corners diagonally across the block cannot see through it.
    for (let i = 0; i < g.nodes.length; i++) {
      for (const e of g.adj[i]) {
        expect(hasLineOfSight(g.nodes[i], g.nodes[e.to], WALL)).toBe(true)
      }
    }
  })
})

describe('nextWaypoint', () => {
  const g = buildNavGraph(WALL, PAD, losFor(WALL))
  const los = losFor(WALL)

  it('returns the goal untouched when it is already visible', () => {
    const to = { x: 30, y: 20 }
    expect(nextWaypoint({ x: 2, y: 20 }, to, g, los)).toBe(to)
  })

  it('routes AROUND a blocking wall instead of into it', () => {
    const from: Vec2 = { x: 5, y: 11 }
    const to: Vec2 = { x: 34, y: 11 }
    expect(los(from, to)).toBe(false) // the wall is between them
    const wp = nextWaypoint(from, to, g, los)
    expect(wp).not.toBe(to)
    // The first hop must be somewhere the unit can actually reach...
    expect(los(from, wp)).toBe(true)
    // ...and off the blocked centre line, i.e. around an end of the wall.
    expect(Math.abs(wp.y - 11)).toBeGreaterThan(1)
  })

  it('picks the SHORTER way round, not merely a way round', () => {
    // Starting below the wall's midline, the bottom end is nearer — a router
    // that returned the first route it found could just as easily go over the
    // top, which is the difference between pathfinding and wandering.
    const from: Vec2 = { x: 5, y: 15 }
    const wp = nextWaypoint(from, { x: 34, y: 15 }, g, los)
    expect(wp.y).toBeGreaterThan(11)
  })

  it('is symmetric — the mirrored trip picks the mirrored corner', () => {
    const up = nextWaypoint({ x: 5, y: 7 }, { x: 34, y: 7 }, g, los)
    expect(up.y).toBeLessThan(11)
  })

  it('⚠️ falls back to the raw goal rather than freezing when boxed in', () => {
    // A unit sealed inside a box has no visible node. Returning the goal keeps
    // the old straight-line behaviour as the floor and lets the steering
    // layer's escape scan take over — never a null that stops movement dead.
    const box: Obstacle[] = [
      { x: 9, y: 9, w: 6, h: 1 }, { x: 9, y: 14, w: 6, h: 1 },
      { x: 9, y: 9, w: 1, h: 6 }, { x: 14, y: 9, w: 1, h: 6 },
    ]
    const bg = buildNavGraph(box, PAD, losFor(box))
    const to = { x: 30, y: 11 }
    expect(nextWaypoint({ x: 12, y: 12 }, to, bg, losFor(box))).toBe(to)
  })

  it('handles an arena with no cover at all', () => {
    const empty = buildNavGraph([], PAD, losFor([]))
    const to = { x: 30, y: 11 }
    expect(nextWaypoint({ x: 2, y: 2 }, to, empty, losFor([]))).toBe(to)
  })

  it('is deterministic — same query, same answer', () => {
    const from: Vec2 = { x: 5, y: 11 }
    const to: Vec2 = { x: 34, y: 11 }
    const a = nextWaypoint(from, to, g, los)
    for (let i = 0; i < 20; i++) expect(nextWaypoint(from, to, g, los)).toEqual(a)
  })
})
