/**
 * Emit the field goldens as a LANGUAGE-NEUTRAL contract: `src/tamerengine/goldens.json`.
 *
 * ⚠️ THIS IS THE PORT'S ACCEPTANCE TEST, AND IT IS THE REASON THE FILE EXISTS. The goldens
 * are pinned today as inline TypeScript fixtures, which is fine for vitest and useless to
 * GDScript. Porting `engine.ts` means proving the ported engine produces the same fight, and
 * that proof needs inputs and outputs both sides can read.
 *
 * ⚠️ IT EXPORTS *RESOLVED* INPUTS, NOT SEEDS, AND THAT IS THE WHOLE DESIGN. A golden's team
 * is built by `generateMonster(seed)` and then hand-pinned to an explicit kit. If the JSON
 * carried only the seed, the Godot side would have to reproduce this project's seeded RNG
 * bit-exactly before it could even start comparing engines — a second, harder port bolted to
 * the front of the real one, and one whose failures would look like engine bugs.
 *
 * Exporting concrete stats, concrete loadouts, concrete positions and concrete obstacles
 * isolates the port to the SIMULATION. Godot loads the file, runs its engine on those exact
 * inputs, and diffs against the same expected block. `generateMonster`, `chooseLoadout`,
 * `ALL_MOVES` and the draft rules are all out of scope for the port, permanently.
 *
 * ⚠️ AND THE JSON IS REGENERATED AND DIFFED BY A TEST, so it cannot rot into a snapshot of
 * something that used to be true — see `goldens.contract.test.ts`. If the engine changes,
 * that test fails alongside `golden.test.ts`, and both are recaptured in one deliberate
 * commit that says which change did it.
 *
 * Usage: npx tsx tools/exportgoldens.ts
 */
import { writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { buildGoldenContract } from '../src/tamerengine/goldenFixtures'

const out = resolve(process.cwd(), 'src/tamerengine/goldens.json')
const contract = buildGoldenContract()
writeFileSync(out, JSON.stringify(contract, null, 2) + '\n', 'utf8')

console.log(`wrote ${out}`)
console.log(`  schema  ${contract.schema}`)
console.log(`  engine  ${contract.engine}`)
console.log(`  fights  ${contract.fights.length}`)
for (const f of contract.fights) {
  console.log(`    ${f.name.padEnd(20)} ${f.teamA.length}v${f.teamB.length}  `
    + `winner ${f.expect.winner}  ${f.expect.duration}s  hp [${f.expect.finalHp.join(', ')}]`)
}
