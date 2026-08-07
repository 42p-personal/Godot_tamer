// VISIBILITY-GRAPH PATHFINDING — the global layer under the local steering.
//
// Obstacles are axis-aligned boxes and they never move, which is the easy case:
// **the shortest path in a box world only ever bends at box corners.** So the
// graph is the inflated corners plus whichever of them can see each other, built
// ONCE per battle, and A* over ~30 nodes is nothing.
//
// ⚠️ THIS DOES NOT REPLACE `stepToward`. It replaces the GOAL handed to it. The
// path layer answers "which way round", the existing steering layer still does
// separation, backpedal, collision-slide and the escape scan. Layering it this
// way is what keeps every behaviour tuned into the local steering intact —
// rewriting movement wholesale would have thrown all of it away.
//
// ⚠️ Deterministic throughout: fixed node order, index tie-breaks in the A*
// frontier, no rng. A replay must reproduce exactly.
import type { Obstacle, Vec2 } from './types'

/** Straight-line clearance test, injected by the caller. */
export type LosFn = (a: Vec2, b: Vec2) => boolean

export interface NavGraph {
  /** Inflated obstacle corners that are themselves standable. */
  nodes: Vec2[]
  /** adj[i] = indices of nodes visible from node i, with edge cost. */
  adj: { to: number; cost: number }[][]
}

const dist = (a: Vec2, b: Vec2) => Math.hypot(a.x - b.x, a.y - b.y)

/**
 * Build the graph for a set of obstacles.
 *
 * `pad` must EXCEED the collision inflation used by `tryMove`, or the corners
 * are points the unit is not allowed to stand on and every path aims at
 * somewhere unreachable.
 */
export function buildNavGraph(
  obstacles: Obstacle[],
  pad: number,
  los: LosFn,
  bounds?: { w: number; h: number },
): NavGraph {
  const nodes: Vec2[] = []
  for (const o of obstacles) {
    for (const [cx, cy] of [
      [o.x - pad, o.y - pad],
      [o.x + o.w + pad, o.y - pad],
      [o.x - pad, o.y + o.h + pad],
      [o.x + o.w + pad, o.y + o.h + pad],
    ] as const) {
      if (bounds && (cx < 0.5 || cy < 0.5 || cx > bounds.w - 0.5 || cy > bounds.h - 0.5)) continue
      // A corner swallowed by a NEIGHBOURING block is not a place to stand. Two
      // obstacles close together would otherwise contribute corners inside each
      // other, and a path through one is a path into a wall.
      const inside = obstacles.some((p) =>
        cx > p.x - pad * 0.5 && cx < p.x + p.w + pad * 0.5
        && cy > p.y - pad * 0.5 && cy < p.y + p.h + pad * 0.5)
      if (inside) continue
      nodes.push({ x: cx, y: cy })
    }
  }

  const adj: { to: number; cost: number }[][] = nodes.map(() => [])
  for (let i = 0; i < nodes.length; i++) {
    for (let j = i + 1; j < nodes.length; j++) {
      if (!los(nodes[i], nodes[j])) continue
      const c = dist(nodes[i], nodes[j])
      adj[i].push({ to: j, cost: c })
      adj[j].push({ to: i, cost: c })
    }
  }
  return { nodes, adj }
}

/**
 * The next point to walk toward on the way from `from` to `to`.
 *
 * Returns `to` itself whenever it is directly visible — which is most ticks, so
 * the graph is rarely touched at all. Returns `to` unchanged if no route exists,
 * leaving the old straight-line behaviour as the floor rather than freezing.
 */
export function nextWaypoint(from: Vec2, to: Vec2, g: NavGraph, los: LosFn): Vec2 {
  if (los(from, to)) return to
  if (!g.nodes.length) return to

  // Attach start and goal to the static graph. Cheap: two passes over the nodes.
  const startAdj: number[] = []
  const goalVis: boolean[] = new Array(g.nodes.length)
  for (let i = 0; i < g.nodes.length; i++) {
    if (los(from, g.nodes[i])) startAdj.push(i)
    goalVis[i] = los(to, g.nodes[i])
  }
  if (!startAdj.length) return to // boxed in; steering's escape scan takes over

  const n = g.nodes.length
  const gScore = new Array<number>(n).fill(Infinity)
  const fScore = new Array<number>(n).fill(Infinity)
  const cameFrom = new Array<number>(n).fill(-1)
  const closed = new Array<boolean>(n).fill(false)
  const h = (i: number) => dist(g.nodes[i], to)

  for (const i of startAdj) {
    gScore[i] = dist(from, g.nodes[i])
    fScore[i] = gScore[i] + h(i)
  }

  let best = -1
  let bestCost = Infinity
  for (;;) {
    // ⚠️ Linear scan, not a heap, and index order breaks ties. ~30 nodes makes
    // the scan free, and a deterministic tie-break is worth more here than the
    // asymptotics: a heap with unstable ordering would desync replays.
    let cur = -1
    let curF = Infinity
    for (let i = 0; i < n; i++) {
      if (closed[i] || fScore[i] === Infinity) continue
      if (fScore[i] < curF) { curF = fScore[i]; cur = i }
    }
    if (cur < 0) break
    closed[cur] = true

    if (goalVis[cur]) {
      const total = gScore[cur] + dist(g.nodes[cur], to)
      if (total < bestCost) { bestCost = total; best = cur }
      // Do not stop here: a node further along the frontier can still reach the
      // goal more cheaply, and taking the first arrival gives a longer route.
    }
    for (const e of g.adj[cur]) {
      if (closed[e.to]) continue
      const tentative = gScore[cur] + e.cost
      if (tentative < gScore[e.to]) {
        gScore[e.to] = tentative
        fScore[e.to] = tentative + h(e.to)
        cameFrom[e.to] = cur
      }
    }
    if (curF >= bestCost) break // nothing left can beat the route already found
  }

  if (best < 0) return to
  // Walk the chain back to the first hop from `from`.
  let node = best
  while (cameFrom[node] >= 0) node = cameFrom[node]
  return g.nodes[node]
}

/**
 * The best place to run to when breaking contact.
 *
 * ⚠️ THIS IS WHAT MAKES COVER A MECHANIC RATHER THAN SCENERY. Fall Back used to
 * retreat to `position + away × 10` — a straight line directly away from the
 * threat — so cover only ever helped when a rock happened to lie in that line.
 * Measured: cover was worth +13%/+17% survival before Fall Back existed and
 * roughly nothing after, because a universal escape that works anywhere makes
 * the ground irrelevant.
 *
 * The graph's corner nodes ARE the "around the pillar" points, so the candidates
 * come free. Speed still comes from suspending the backpedal penalty; this
 * supplies the DESTINATION — and on a bare map no candidate beats running
 * straight away, so Fall Back degrades to exactly its old behaviour. That is the
 * design: an arena with pillars makes retreat strong, an empty one does not, and
 * the map does the balancing instead of a constant.
 *
 * Deterministic: fixed node order, no rng.
 */
export function bestCoverPoint(
  from: Vec2,
  threat: Vec2,
  reach: number,
  g: NavGraph,
  los: LosFn,
  allies: Vec2[] = [],
): Vec2 | null {
  let best: Vec2 | null = null
  let bestScore = 0.35 // ⚠️ a floor: a marginal corner must not beat running away
  const nowD = dist(from, threat)
  for (const n of g.nodes) {
    const cost = dist(from, n)
    if (cost > reach) continue // cannot get there inside the retreat window
    // ⚠️ Never retreat INTO the threat. A corner can break line of sight while
    // sitting closer to the attacker, which is a hiding place you die in.
    const gained = dist(n, threat) - nowD
    if (gained < 0) continue
    const hidden = los(n, threat) ? 0 : 1
    // Staying in sight of the team matters because LoS is symmetric: a support
    // that cannot see its allies cannot heal them, so a corner that abandons the
    // fight is worth less than one that merely breaks the chase.
    const withTeam = allies.some((a) => los(n, a)) ? 1 : 0
    const score = 2.0 * hidden
      + 1.0 * Math.min(1, gained / 8)
      - 1.2 * (cost / Math.max(1e-6, reach))
      + 0.5 * withTeam
    if (score > bestScore) { bestScore = score; best = n }
  }
  return best
}
