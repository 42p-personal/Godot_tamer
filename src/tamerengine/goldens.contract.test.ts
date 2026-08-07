// THE PORT CONTRACT IS LIVE, NOT A SNAPSHOT.
//
// ⚠️ A COMMITTED JSON THAT NOTHING RE-DERIVES IS A LIE WITH A TIMESTAMP. `goldens.json` is
// what the Godot port will diff its engine against; if the TypeScript engine drifts and the
// JSON does not, the port passes a test the game would fail, and the failure surfaces as
// "the ported engine is wrong" when the truth is that the contract went stale.
//
// So the file is regenerated from the same fixtures on every test run and compared. It fails
// alongside `golden.test.ts` — one deliberate recapture updates both:
//     npx tsx tools/exportgoldens.ts
//
// ⚠️ AND IT ASSERTS THE CONTRACT IS COMPLETE, not merely present. A resolved input that is
// missing a stat block or a loadout would still parse as JSON and still round-trip; it would
// just be unportable. The shape checks below are cheap and catch exactly that.
import { readFileSync, existsSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, it, expect } from 'vitest'
import { buildGoldenContract } from './goldenFixtures'

const FILE = resolve(process.cwd(), 'src/tamerengine/goldens.json')

describe('golden port contract', () => {
  it('goldens.json exists and matches the live fixtures', () => {
    expect(existsSync(FILE), 'run `npx tsx tools/exportgoldens.ts`').toBe(true)
    const onDisk = JSON.parse(readFileSync(FILE, 'utf8'))
    // Round-trip the built contract through JSON so undefined-vs-absent and any
    // non-serialisable field compare the way the port will actually see them.
    const live = JSON.parse(JSON.stringify(buildGoldenContract()))
    expect(onDisk, 'goldens.json is stale — regenerate with `npx tsx tools/exportgoldens.ts` '
      + 'in the SAME commit as the engine change that moved it').toEqual(live)
  })

  it('every fight carries fully resolved inputs a port could consume', () => {
    const c = buildGoldenContract()
    expect(c.fights.length).toBeGreaterThan(0)
    for (const f of c.fights) {
      expect(f.teamA.length + f.teamB.length, `${f.name}: no units`).toBeGreaterThan(0)
      expect(f.placeA.length, `${f.name}: placeA must cover teamA`).toBe(f.teamA.length)
      expect(f.placeB.length, `${f.name}: placeB must cover teamB`).toBe(f.teamB.length)
      expect(f.expect.finalHp.length, `${f.name}: finalHp must cover every unit`)
        .toBe(f.teamA.length + f.teamB.length)
      for (const m of [...f.teamA, ...f.teamB]) {
        // ⚠️ STATS AND LOADOUT ARE THE TWO THINGS A PORT CANNOT DERIVE. Everything else it
        // can default; without these it cannot run the fight at all.
        expect(m.stats, `${f.name}: ${m.name} has no stats`).toBeTruthy()
        expect(m.loadout.length, `${f.name}: ${m.name} has no loadout`).toBeGreaterThan(0)
        for (const mv of m.loadout) {
          expect(typeof mv.name, `${f.name}: a move lost its name`).toBe('string')
          expect(typeof mv.power, `${f.name}: ${mv.name} lost its power`).toBe('number')
          // `range` is the axis every league below Platinum was authored against and the one
          // most likely to be dropped by a hand-written serialiser.
          expect(typeof mv.range, `${f.name}: ${mv.name} lost its range`).toBe('number')
        }
      }
    }
  })
})
