// NAVIGATION HEALTH — the instruments that make a pathfinding failure visible.
//
// ⚠️ THESE EXIST BECAUSE `sweep40` REPORTED A HEALTHY 38/40 WHILE TWO UNITS WERE
// FROZEN SOLID FOR AN ENTIRE FIGHT. On Titan's Rest, Zarok and Sylix spawned
// inside an obstacle and never moved once across all 750 ticks — and every
// instrument the project had said the arena was fine. Outcome metrics (resolved,
// duration, damage) cannot see a unit that is present, alive, targetable and
// completely inert. Nothing in Stage 0 gets graded on `resolved`; it gets graded
// on these.
//
// Pure observation: this reads the snapshot stream the renderer already consumes
// and touches no engine state, so measuring costs nothing and cannot alter a
// fight.
import type { FieldEvent, Obstacle, Vec2 } from './types'

/** Movement below this in one tick is "did not move" (world units). */
export const FROZEN_EPS = 0.02
/** Within this of an obstacle counts as touching cover (world units). */
export const HUG_MARGIN = 1.2
/** Stuck for this fraction of its living ticks and a unit is not slow, it is dead weight. */
export const DEADLOCK_FRAC = 0.9

export interface NavStats {
  id: string
  /** Ticks observed alive. */
  ticks: number
  /** Ticks the unit was in the `move` state — i.e. it WANTED to move. */
  moveTicks: number
  /** Wanted to move and didn't. */
  stuck: number
  /** Stuck AND touching cover — stuck *because of geometry*. */
  blocked: number
  /** Total distance walked. */
  path: number
  /** Straight-line distance from first position to last. */
  net: number
  /** path ÷ net. 1.0 is a straight line; large means scraping around. */
  wander: number
  /** Stuck for ≥ DEADLOCK_FRAC of the ticks it tried to move. Catastrophic. */
  deadlocked: boolean
  /** Share of move-ticks spent stuck. The headline per-unit number. */
  stuckFrac: number
}

/**
 * Distance from a point to an axis-aligned box; 0 when inside.
 *
 * ⚠️ Not centre-distance. A long wall's centre can be 20 units away while the
 * unit is pressed against its face, so centre-distance would report a unit
 * scraping along the Ossuary's walls as nowhere near cover.
 */
export function distanceToObstacle(p: Vec2, o: Obstacle): number {
  const dx = Math.max(o.x - p.x, 0, p.x - (o.x + o.w))
  const dy = Math.max(o.y - p.y, 0, p.y - (o.y + o.h))
  return Math.hypot(dx, dy)
}

export const touchingCover = (p: Vec2, obstacles: Obstacle[], margin = HUG_MARGIN): boolean =>
  obstacles.some((o) => distanceToObstacle(p, o) <= margin)

/**
 * Per-unit navigation health from a finished battle's event stream.
 *
 * ⚠️ `stuck` KEYS OFF THE `move` STATE, not merely off standing still. An
 * earlier version of this metric counted any tick with no displacement, which
 * runs at 40–86% for perfectly healthy units — they are casting, or standing in
 * range, or waiting behind an ally. That version could not separate "content to
 * stand here" from "trying to walk into a wall". Asking the unit what it was
 * TRYING to do removes the ambiguity instead of guessing around it.
 */
export function navStats(events: FieldEvent[], obstacles: Obstacle[]): NavStats[] {
  const acc = new Map<string, {
    ticks: number; moveTicks: number; stuck: number; blocked: number
    path: number; first: Vec2 | null; last: Vec2
  }>()
  let prev: Map<string, Vec2> | null = null

  for (const e of events) {
    if (e.kind !== 'snapshot') continue
    const now = new Map<string, Vec2>()
    for (const u of e.units) {
      if (u.hp <= 0) continue // the dead do not navigate
      const p = { x: u.x, y: u.y }
      now.set(u.id, p)
      const a = acc.get(u.id) ?? {
        ticks: 0, moveTicks: 0, stuck: 0, blocked: 0, path: 0, first: null, last: p,
      }
      a.first ??= p
      a.last = p
      a.ticks++
      const before = prev?.get(u.id)
      if (before) {
        const step = Math.hypot(p.x - before.x, p.y - before.y)
        a.path += step
        if (u.state === 'move') {
          a.moveTicks++
          if (step < FROZEN_EPS) {
            a.stuck++
            if (touchingCover(p, obstacles)) a.blocked++
          }
        }
      }
      acc.set(u.id, a)
    }
    prev = now
  }

  const out: NavStats[] = []
  for (const [id, a] of acc) {
    const net = a.first ? Math.hypot(a.last.x - a.first.x, a.last.y - a.first.y) : 0
    const stuckFrac = a.moveTicks > 0 ? a.stuck / a.moveTicks : 0
    out.push({
      id,
      ticks: a.ticks,
      moveTicks: a.moveTicks,
      stuck: a.stuck,
      blocked: a.blocked,
      path: a.path,
      net,
      // ⚠️ Guard the divisor. A unit that never moved has net 0, and path/0 is
      // Infinity — which sorts to the top of a "worst wander" table and buries
      // the units with a real, finite problem.
      wander: net > 0.5 ? a.path / net : 1,
      deadlocked: a.moveTicks >= 10 && stuckFrac >= DEADLOCK_FRAC,
      stuckFrac,
    })
  }
  return out.sort((x, y) => y.stuckFrac - x.stuckFrac || y.wander - x.wander)
}

export interface NavSummary {
  units: number
  deadlocked: number
  /** Share of all move-ticks, across all units, spent stuck. */
  stuckPct: number
  /** Share of stuck ticks attributable to geometry. */
  blockedPct: number
  /** Mean wander over units that actually travelled. */
  wander: number
}

export function navSummary(all: NavStats[]): NavSummary {
  const moveTicks = all.reduce((s, u) => s + u.moveTicks, 0)
  const stuck = all.reduce((s, u) => s + u.stuck, 0)
  const blocked = all.reduce((s, u) => s + u.blocked, 0)
  const travelled = all.filter((u) => u.net > 0.5)
  return {
    units: all.length,
    deadlocked: all.filter((u) => u.deadlocked).length,
    stuckPct: moveTicks ? (stuck / moveTicks) * 100 : 0,
    blockedPct: stuck ? (blocked / stuck) * 100 : 0,
    wander: travelled.length
      ? travelled.reduce((s, u) => s + u.wander, 0) / travelled.length
      : 1,
  }
}

/** Merge summaries across many fights, weighted by the work each one observed. */
export function mergeNav(all: NavStats[][]): NavSummary {
  return navSummary(all.flat())
}
