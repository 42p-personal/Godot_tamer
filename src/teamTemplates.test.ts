import { describe, it, expect } from 'vitest'
import {
  BASE_POOL, TEAM_TEMPLATES, slotAffinity, slotsFor, speciesForTemplate, templateById,
} from './teamTemplates'
import { GAMEPLANS, PRESTIGE_BODIES, isFusionBody } from './core'
import { SPECIES_BY_ID } from './species'

describe('team templates', () => {
  it('the shapes genuinely differ — no two share a pattern', () => {
    // A template set whose members are all "one of each" tests nothing and gives
    // a player nothing to scout.
    const seen = new Set(TEAM_TEMPLATES.map((t) => t.pattern.join('/')))
    expect(seen.size).toBe(TEAM_TEMPLATES.length)
  })

  it('⚠️ tanky shapes carry a support and fast shapes do not', () => {
    // The design rule: sustain is worth what the fight is long enough to use.
    const has = (id: string) => templateById(id)!.pattern.includes('support')
    expect(has('phalanx')).toBe(true)
    expect(has('choir')).toBe(true)
    expect(has('wolfpack')).toBe(false)
    expect(has('vanguard')).toBe(false)
  })

  it('cycles a pattern out to any league team size', () => {
    const t = templateById('hammer-anvil')!
    expect(slotsFor(t, 1)).toEqual(['front'])
    expect(slotsFor(t, 6)).toHaveLength(6)
    expect(slotsFor(t, 6).slice(0, 3)).toEqual(t.pattern)
  })

  it('⚠️ the default pool excludes prestige and fusion bodies', () => {
    // Ranking raw base stats without this hands every slot to Mythical/Abyssal:
    // the first draft fielded titanrex in four of six shapes. A licence-gated
    // species is not what a Wood-league rival should bring.
    for (const sp of BASE_POOL) {
      expect(PRESTIGE_BODIES).not.toContain(sp.body)
      expect(isFusionBody(sp.body)).toBe(false)
    }
  })

  it('a support slot prefers WIS over CHA', () => {
    // WIS is the only stat that can heal another monster. A support slot led by
    // CHA would field buffers and never a healer.
    const wisLed = { STR: 10, DEX: 10, CON: 10, WIS: 60, INT: 10, CHA: 20 }
    const chaLed = { STR: 10, DEX: 10, CON: 10, WIS: 20, INT: 10, CHA: 60 }
    expect(slotAffinity(wisLed, 'support')).toBeGreaterThan(slotAffinity(chaLed, 'support'))
  })

  it('is deterministic, and varies the roster by seed', () => {
    const t = templateById('phalanx')!
    expect(speciesForTemplate(t, 3, 7)).toEqual(speciesForTemplate(t, 3, 7))
    const rosters = new Set(
      Array.from({ length: 8 }, (_, s) => speciesForTemplate(t, 3, s).join(',')))
    expect(rosters.size).toBeGreaterThan(1) // not the same team forever
  })

  it('never fields the same species twice in one team', () => {
    for (const t of TEAM_TEMPLATES) {
      for (let s = 0; s < 6; s++) {
        const ids = speciesForTemplate(t, 4, s)
        expect(new Set(ids).size).toBe(ids.length)
        for (const id of ids) expect(SPECIES_BY_ID[id]).toBeDefined()
      }
    }
  })

  it('every declared gameplan is a real one', () => {
    for (const t of TEAM_TEMPLATES) {
      if (!t.gameplan) continue
      expect(GAMEPLANS[t.gameplan], `${t.id} -> ${t.gameplan}`).toBeDefined()
    }
  })

  it('every gameplan the game fields is carried by some template', () => {
    // ⚠️ THIS USED TO ASSERT EXCLUSIVITY — no two templates sharing a plan — and
    // that was the right property while `gameplan` was the ONLY thing separating
    // two templates. It is not any more: Vivisect and Vanguard both run focusfire
    // but differ in pattern AND in per-slot combo roles, which is two genuinely
    // different fights. What actually protects the harness's span is COVERAGE —
    // that no plan the game can field goes untested — so that is what is asserted.
    const carried = new Set(TEAM_TEMPLATES.map((t) => t.gameplan).filter(Boolean))
    for (const plan of Object.keys(GAMEPLANS)) expect(carried).toContain(plan)
  })

  it('a template that declares combo roles declares a REAL loop or none at all', () => {
    // ⚠️ A `detonate` slot with no `prime` slot beside it is a template promising a
    // payoff nobody sets up — the cross-monster failure this whole system exists to
    // fix, reintroduced one layer higher. Priming without cashing IS allowed
    // (affliction is damage); cashing without priming is not.
    for (const t of TEAM_TEMPLATES) {
      if (!t.roles?.includes('detonate')) continue
      expect(t.roles, `${t.id} cashes but never primes`).toContain('prime')
    }
  })

  it('roles line up with the pattern they are cycled against', () => {
    for (const t of TEAM_TEMPLATES) {
      if (!t.roles) continue
      expect(t.roles.length, `${t.id}`).toBe(t.pattern.length)
    }
  })

  it('⚠️ exactly one template is UNPLANNED — the control', () => {
    // Without an unordered composition the sweep cannot separate "this plan helped"
    // from "having any plan at all helped". Hammer & Anvil is that baseline.
    const bare = TEAM_TEMPLATES.filter((t) => !t.gameplan)
    expect(bare.map((t) => t.id)).toEqual(['hammer-anvil'])
  })
})
