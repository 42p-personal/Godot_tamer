/**
 * Emit the PORT CONTRACT — every part of the simulation that survives the spatial rebuild.
 *
 * ⚠️ THIS IS THE PORT'S ACCEPTANCE TEST, AND IT IS NOT `goldens.json`. The whole-fight goldens
 * pin durations and final HP — numbers produced by pathfinding, cover and reach, all of which
 * Godot rebuilds natively rather than receives. A correct Godot engine will not reproduce
 * `23.2s` and must not be failed for it.
 *
 * Three files, three subjects, one rule: explicit inputs, explicit outputs, no geometry and no
 * seeded RNG anywhere.
 *
 *   combat.json  damage resolution        damage.ts:resolveStrike
 *   derive.json  pools, mana, cooldowns   monster.ts + types.ts
 *   status.json  statuses and CC DR       statusMath.ts:applyStatus
 *   tick.json    timers, regen, attrition  tickMath.ts:tickUnit
 *   classify.json class, role, free attack   core.ts + decide.ts + engine.ts
 *
 * Usage: npx tsx tools/exportport.ts
 */
import { writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { buildCombatContract } from '../src/tamerengine/combatFixtures'
import { buildDeriveContract } from '../src/tamerengine/deriveFixtures'
import { buildStatusContract } from '../src/tamerengine/statusFixtures'
import { buildTickContract } from '../src/tamerengine/tickFixtures'
import { buildClassifyContract } from '../src/tamerengine/classifyFixtures'

const PARTS = [
  ['combat.json', buildCombatContract()],
  ['derive.json', buildDeriveContract()],
  ['status.json', buildStatusContract()],
  ['tick.json', buildTickContract()],
  ['classify.json', buildClassifyContract()],
] as const

let total = 0
for (const [file, contract] of PARTS) {
  const out = resolve(process.cwd(), 'src/tamerengine', file)
  writeFileSync(out, JSON.stringify(contract, null, 2) + '\n', 'utf8')
  const byAxis = new Map<string, number>()
  for (const k of contract.cases as { axis: string }[]) byAxis.set(k.axis, (byAxis.get(k.axis) ?? 0) + 1)
  total += contract.cases.length
  console.log(`${file.padEnd(12)} ${String(contract.cases.length).padStart(3)} cases, `
    + `${String(byAxis.size).padStart(2)} axes  ${contract.subject}`)
  console.log(`             ${[...byAxis.keys()].sort().join(' · ')}`)
}
console.log(`\n${total} cases total across ${PARTS.length} contracts`)
