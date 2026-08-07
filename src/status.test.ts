// applyStatus stacking/refresh rules: bleed is the ONE stacking status (capped
// at 3); everything else refreshes duration to the max instead of duplicating.
import { describe, expect, it } from 'vitest'
import { BLEED_MAX_STACKS, applyStatus } from './battle'

const fresh = () => ({ statuses: [] as { kind: string; turns: number }[] })

describe('applyStatus', () => {
  it('bleed stacks up to the cap, then refuses further stacks', () => {
    const c = fresh()
    for (let i = 0; i < 5; i++) applyStatus(c as never, 'bleed', 3)
    expect(c.statuses.filter((s) => s.kind === 'bleed').length).toBe(BLEED_MAX_STACKS)
  })

  it('non-stacking statuses refresh duration to the max, never duplicate', () => {
    const c = fresh()
    applyStatus(c as never, 'burn', 3)
    applyStatus(c as never, 'burn', 2) // shorter re-apply must not shorten
    expect(c.statuses.filter((s) => s.kind === 'burn').length).toBe(1)
    expect(c.statuses[0].turns).toBe(3)
    applyStatus(c as never, 'burn', 5) // longer re-apply extends
    expect(c.statuses[0].turns).toBe(5)
  })

  it('reports true only when a NEW status (or bleed stack) was added', () => {
    const c = fresh()
    expect(applyStatus(c as never, 'stun', 1)).toBe(true)
    expect(applyStatus(c as never, 'stun', 1)).toBe(false)
    expect(applyStatus(c as never, 'bleed', 3)).toBe(true)
    expect(applyStatus(c as never, 'bleed', 3)).toBe(true)
    expect(applyStatus(c as never, 'bleed', 3)).toBe(true)
    expect(applyStatus(c as never, 'bleed', 3)).toBe(false) // cap hit
  })
})
