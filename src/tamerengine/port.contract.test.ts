// THE PORT CONTRACTS ARE LIVE, NOT SNAPSHOTS.
//
// ⚠️ A COMMITTED JSON THAT NOTHING RE-DERIVES IS A LIE WITH A TIMESTAMP. `combat.json`,
// `derive.json` and `status.json` are what the Godot port diffs its engine against; if the TS
// drifts and a JSON does not, the port passes a test the game would fail, and the failure
// surfaces as "the ported engine is wrong" when the truth is that the contract went stale. So
// all three are regenerated from the same fixtures on every run and compared:
//     npx tsx tools/exportport.ts
//
// ⚠️ AND THEY ASSERT THE CONTRACTS ARE USEFUL, not merely present. A table where every case
// misses, or where half the axes vanished in a refactor, would still round-trip perfectly and
// still be worthless as a port test. The coverage checks below are cheap and catch that.
import { readFileSync, existsSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, it, expect } from 'vitest'
import { buildCombatContract, COMBAT_CASES } from './combatFixtures'
import { buildDeriveContract, DERIVE_CASES } from './deriveFixtures'
import { buildStatusContract, STATUS_CASES } from './statusFixtures'
import { buildTickContract, TICK_CASES } from './tickFixtures'
import { tickUnit } from './tickMath'
import { buildClassifyContract, CLASSIFY_CASES } from './classifyFixtures'
import { buildDataExport } from './dataExport'
import { resolveStrike } from './damage'
import { applyStatus } from './statusMath'
import { maxHp } from '../monster'
import { roleOfClass } from '../core'

const PARTS = [
  ['combat.json', buildCombatContract],
  ['derive.json', buildDeriveContract],
  ['status.json', buildStatusContract],
  ['tick.json', buildTickContract],
  ['classify.json', buildClassifyContract],
  // ⚠️ THE DATA IS IN THE SAME LOOP AS THE ARITHMETIC. A stale `data.json` is the quietest
  // failure of the four: the port runs a smaller move pool, or an old status table, and every
  // test still passes on both sides.
  ['data.json', buildDataExport],
] as const

describe('port contracts', () => {
  for (const [file, build] of PARTS) {
    it(`${file} exists and matches the live fixtures`, () => {
      const path = resolve(process.cwd(), 'src/tamerengine', file)
      expect(existsSync(path), 'run `npx tsx tools/exportport.ts`').toBe(true)
      const onDisk = JSON.parse(readFileSync(path, 'utf8'))
      const live = JSON.parse(JSON.stringify(build()))
      expect(onDisk, `${file} is stale — regenerate with \`npx tsx tools/exportport.ts\` in the `
        + 'SAME commit as the engine change that moved it').toEqual(live)
    })
  }

  it('covers every axis of the damage math', () => {
    // ⚠️ NAMED EXPLICITLY SO DELETING A CASE IS A TEST FAILURE, NOT A QUIET LOSS OF COVERAGE.
    const want = ['baseline', 'channel', 'statScale', 'variance', 'accuracy', 'crit',
      'mitigation', 'pierce', 'mitDebuff', 'openingMitigation', 'guard', 'block', 'ward',
      'execute', 'firstStrike', 'hpScale', 'bonusVsStatus', 'consumeWard', 'maxHpDmg',
      'behind', 'falloff', 'mods', 'floor']
    const have = new Set(COMBAT_CASES.map((k) => k.axis))
    expect(want.filter((a) => !have.has(a)), 'an axis lost its cases').toEqual([])
  })

  it('covers every axis of the derivations', () => {
    const want = ['maxHp', 'maxMana', 'manaCost', 'fieldMpCost', 'regen', 'castTime',
      'cooldown', 'roundsToSeconds']
    const have = new Set(DERIVE_CASES.map((k) => k.axis))
    expect(want.filter((a) => !have.has(a)), 'an axis lost its cases').toEqual([])
  })

  it('covers every axis of the status rules', () => {
    const want = ['apply', 'ccDr', 'conFloor', 'immunity', 'refresh', 'stacks', 'lurch',
      'duration']
    const have = new Set(STATUS_CASES.map((k) => k.axis))
    expect(want.filter((a) => !have.has(a)), 'an axis lost its cases').toEqual([])
  })

  it('covers every axis of the tick', () => {
    const want = ['cooldowns', 'manaRegen', 'hpRegen', 'ccDecay', 'dot', 'expiry',
      'modExpiry', 'suddenDeath']
    const have = new Set(TICK_CASES.map((k) => k.axis))
    expect(want.filter((a) => !have.has(a)), 'an axis lost its cases').toEqual([])
  })

  it('the tick never produces impossible state', () => {
    // ⚠️ CHEAP INVARIANTS THAT CATCH A WHOLE CLASS OF PORT BUG. A pool that goes negative or
    // overflows its cap reads as a wild damage number several seconds later, nowhere near the
    // tick that caused it.
    for (const k of TICK_CASES) {
      if (k.axis === 'suddenDeath') continue
      const e = k.expect
      expect(e.hp, `${k.name}: hp below zero`).toBeGreaterThanOrEqual(0)
      expect(e.hp, `${k.name}: hp above the pool`).toBeLessThanOrEqual(k.input.maxHp)
      expect(e.mp, `${k.name}: mp below zero`).toBeGreaterThanOrEqual(0)
      expect(e.mp, `${k.name}: mp above the pool`).toBeLessThanOrEqual(k.input.maxMp)
      expect(e.ccResist, `${k.name}: meter out of range`).toBeGreaterThanOrEqual(0)
      for (const v of Object.values(e.cooldowns as Record<string, number>)) {
        expect(v, `${k.name}: negative cooldown`).toBeGreaterThanOrEqual(0)
      }
    }
  })

  it('covers every axis of classification', () => {
    const want = ['classForStats', 'roleOfClass', 'manaRoleOf', 'basicAttackFor']
    const have = new Set(CLASSIFY_CASES.map((k) => k.axis))
    expect(want.filter((a) => !have.has(a)), 'an axis lost its cases').toEqual([])
  })

  it('every class in CLASSES has a free attack and a role', () => {
    // ⚠️ A CLASS WITHOUT A BASIC WOULD FALL BACK TO Generalist SILENTLY, giving a whole class
    // the wrong reach and the wrong scaling stat with nothing failing.
    const d = buildDataExport() as any
    for (const c of d.classes) {
      expect(d.classBasic[c.name], `${c.name} has no CLASS_BASIC entry`).toBeTruthy()
      expect(['damage', 'support'], `${c.name} has no role`).toContain(roleOfClass(c.name))
    }
    expect(d.classBasic.Generalist, 'the Generalist fallback must exist').toBeTruthy()
  })

  it('exercises both the hit and the miss path', () => {
    const c = buildCombatContract()
    expect(c.cases.filter((k) => k.expect.hit).length).toBeGreaterThan(30)
    expect(c.cases.filter((k) => !k.expect.hit).length).toBeGreaterThan(0)
  })

  it('exercises both the applied and the refused path', () => {
    const c = buildStatusContract()
    expect(c.cases.filter((k) => k.expect.applied).length).toBeGreaterThan(10)
    // Every refusal reason must be represented — each is a distinct branch a port can drop,
    // and dropping one silently makes a status land that should not.
    const reasons = new Set(c.cases.map((k) => k.expect.refusedBecause).filter(Boolean))
    expect([...reasons].sort()).toEqual(['dead', 'fullyDiminished', 'immune', 'maxStacks'])
  })

  it('every landed hit does at least 1 damage', () => {
    for (const k of buildCombatContract().cases) {
      if (k.expect.hit) expect(k.expect.dmg, `${k.name} landed for 0`).toBeGreaterThanOrEqual(1)
    }
  })

  it('a miss carries no damage and no side effects', () => {
    for (const k of buildCombatContract().cases) {
      if (k.expect.hit) continue
      expect(k.expect.dmg, k.name).toBe(0)
      expect(k.expect.toHp, k.name).toBe(0)
      expect(k.expect.wardSoaked, k.name).toBe(0)
      expect(k.expect.spendsOwnWard, k.name).toBe(false)
    }
  })

  it('ward accounting always balances', () => {
    for (const k of buildCombatContract().cases) {
      const e = k.expect
      expect(e.wardSoaked + e.toHp, `${k.name}: ward + hp must equal the blow`).toBe(e.dmg)
      expect(e.wardLeft, `${k.name}: ward cannot go negative`).toBeGreaterThanOrEqual(0)
    }
  })

  it('the CC meter only ever advances', () => {
    // ⚠️ A METER THAT COULD FALL INSIDE `applyStatus` WOULD MAKE CHAIN-CC FREE. It is cleared
    // by quiet time in the engine loop, never by another application.
    for (const k of STATUS_CASES) {
      expect(k.expect.ccResist, `${k.name}`).toBeGreaterThanOrEqual(k.input.ccResist)
    }
  })

  it('only hard control touches the CC meter', () => {
    // The guard for the bug found while extracting `applyFieldStatus`: an attrition status
    // that stamped `lastCcAt` would stop `CC_DR_RESET` ever firing while a DoT ticked.
    for (const k of STATUS_CASES) {
      if (k.expect.ccMeterTouched) {
        expect(['stun', 'sleep', 'fear', 'confusion', 'charm', 'silence', 'knockback'],
          `${k.name}: a non-control status touched the meter`).toContain(k.input.kind)
      }
    }
  })

  it('the functions are pure — the same input twice gives the same answer', () => {
    // ⚠️ THE ONE PROPERTY THE WHOLE CONTRACT RESTS ON. If either function reached for a clock,
    // a shared rng or module state, the JSON would be a recording rather than a spec and the
    // port would be chasing a moving target.
    for (const k of COMBAT_CASES) {
      expect(resolveStrike(k.input), k.name).toEqual(resolveStrike(k.input))
    }
    for (const k of STATUS_CASES) {
      expect(applyStatus(k.input), k.name).toEqual(applyStatus(k.input))
    }
    for (const k of TICK_CASES) {
      if (k.axis === 'suddenDeath') continue
      expect(tickUnit(k.input), k.name).toEqual(tickUnit(k.input))
    }
  })

  it('the exported data carries every table the port consumes', () => {
    const d = buildDataExport() as any
    // Counts are tripwires, not trivia: a drop means the exporter lost rows, a rise means
    // content landed that nothing has judged.
    expect(d.moves.length, '141-move pool').toBe(141)
    expect(d.species.length, '65 species').toBe(65)
    expect(d.classes.length, '18 classes').toBe(18)
    expect(Object.keys(d.lineOf).length, 'every move has a line').toBe(141)
    expect(Object.keys(d.fieldStatus).length, '15 statuses').toBe(15)
    // ⚠️ 130 — TWO INNATES FOR EACH OF 65 SPECIES. Species names/descriptions were exported
    // long before their numeric effects were; this tripwire is what stops a future serialiser
    // silently dropping the table again (`docs/INNATES_ON_FIELD.md`).
    expect(Object.keys(d.innateEffects).length, '130 innate effect entries').toBe(130)
    // Every species innate NAME must resolve to an entry — the guard `validate.ts` already runs,
    // repeated here because `data.json` is what the PORT actually reads, not `validate.ts`.
    for (const sp of d.species) {
      for (const ab of sp.innate) {
        expect(d.innateEffects[ab.name], `${sp.name}'s "${ab.name}" has no innateEffects entry`).toBeTruthy()
      }
    }
    // ⚠️ EVERY HARD-CONTROL STATUS NEEDS A BEHAVIOUR RULE, or `applyStatus` diminishes
    // something the engine cannot then describe.
    for (const k of d.hardControlStatuses) {
      expect(d.fieldStatus[k], `hard control '${k}' has no rule`).toBeTruthy()
    }
  })

  it('maxHp is QUADRATIC in CON, not linear', () => {
    // ⚠️ PINNED BECAUSE THE PROJECT DOCS SAID OTHERWISE. `CLAUDE.md` recorded
    // `maxHp = 40 + CON x 2.0` for a formula that also carries `CON^2 / 1600` — worth +56 HP
    // at CON 300 and +400 at CON 800, a 24% larger pool than the documented version. Anyone
    // porting or re-deriving from the prose would shorten every high-CON fight.
    const s = (CON: number) => ({ STR: 0, DEX: 0, CON, WIS: 0, INT: 0, CHA: 0 }) as any
    expect(maxHp(s(0))).toBe(40)
    expect(maxHp(s(300))).toBe(696)   // linear reading would say 640
    expect(maxHp(s(800))).toBe(2040)  // linear reading would say 1640
  })
})
