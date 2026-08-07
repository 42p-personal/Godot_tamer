// PLAYBACK CLOCK — the two clamps that keep the renderer's animation loop alive.
//
// ⚠️ THESE PIN A REAL BUG, NOT A HYPOTHETICAL. `frameDelta` was clamped only at the
// TOP. `last` is seeded from `performance.now()` when the effect runs, but rAF hands
// back the FRAME START timestamp, which can be EARLIER than that moment — so the
// first frame computed a NEGATIVE delta, drove the playback clock below zero, and
// `snaps[-1]` came back undefined. Reading `.units` off it threw INSIDE the rAF
// callback, before the line that reschedules the next frame, so playback died on
// frame one and never restarted.
//
// What that looked like: every monster stranded at translate(0,0) with no width —
// the whole team piled in the top-left corner of the field at natural PNG size, over
// a HUD still reading "—". It reads as "the deployment isn't working", because the
// formation is precisely the thing you cannot see.
//
// ⚠️ AND IT WAS TIMING-DEPENDENT, which is why it reproduced for the user and not
// here. That is the argument for testing the arithmetic rather than trusting a
// browser check: the browser check PASSED while the bug was live.
import { describe, it, expect } from 'vitest'
import { frameDelta, snapIndexAt } from './TamerArena'

describe('frameDelta', () => {
  it('never returns a negative delta, however the clocks disagree', () => {
    // The exact shape of the bug: the frame timestamp predates the effect's seed.
    expect(frameDelta(1000, 1050)).toBe(0)
    expect(frameDelta(0, 999999)).toBe(0)
  })

  it('still caps a long stall so a backgrounded tab does not jump', () => {
    // ⚠️ The ceiling must survive the fix. Clamping only the floor would trade one
    // failure for the other: a tab resumed after 30s would advance the fight 30s in
    // a single frame, which is the teleporting this renderer was built to remove.
    expect(frameDelta(30000, 0)).toBe(0.05)
  })

  it('passes an ordinary frame through untouched', () => {
    expect(frameDelta(1016, 1000)).toBeCloseTo(0.016, 5)
  })
})

describe('snapIndexAt', () => {
  it('clamps below zero rather than indexing off the front of the array', () => {
    expect(snapIndexAt(-5, 100)).toBe(0)
    expect(snapIndexAt(-0.0001, 100)).toBe(0)
  })

  it('clamps past the end rather than off the back', () => {
    expect(snapIndexAt(9999, 100)).toBe(99)
  })

  it('survives a NaN clock', () => {
    // ⚠️ NaN is not hypothetical either — it is what any arithmetic on an undefined
    // speed or timestamp produces, and `Math.min(len-1, NaN)` is NaN, which indexes
    // to undefined exactly like a negative does.
    expect(snapIndexAt(NaN, 100)).toBe(0)
  })

  it('maps a real time onto the 10 Hz snapshot grid', () => {
    expect(snapIndexAt(0, 100)).toBe(0)
    expect(snapIndexAt(0.1, 100)).toBe(1)
    expect(snapIndexAt(2.35, 100)).toBe(23)
  })

  it('always returns an index that is in range for a one-frame result', () => {
    // A degenerate one-snapshot fight must not produce -1 or 1.
    for (const t of [-1, 0, 0.05, 10, NaN]) expect(snapIndexAt(t, 1)).toBe(0)
  })
})
