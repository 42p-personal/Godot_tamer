/**
 * Emit the game DATA as engine-neutral JSON for the Godot port: `src/tamerengine/data.json`.
 *
 * ⚠️ DATA IS EXPORTED, NOT PORTED, AND THE DISTINCTION IS THE WHOLE POINT. 141 moves, 65
 * species and 18 classes are TABLES. Rewriting them as GDScript literals would create a second
 * copy that drifts the first time anyone retunes a number, and the drift would present as an
 * engine disagreement rather than as stale data.
 *
 * ⚠️ `FIELD_STATUS` IS IN HERE FOR A SPECIFIC REASON. The first cut of `status_math.gd`
 * hardcoded `MAX_STACKS = {bleed: 3}` and `LURCH_TO_SOURCE = {charm: 2.5}` — two entries out of
 * a fifteen-entry table, transcribed by hand because they were the only two `applyStatus` reads
 * today. Add a second stacking status and the GDScript would silently not stack it. The table
 * travels as data so that cannot happen.
 *
 * Usage: npx tsx tools/exportdata.ts
 */
import { writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { buildDataExport } from '../src/tamerengine/dataExport'

const data = buildDataExport()
const out = resolve(process.cwd(), 'src/tamerengine/data.json')
writeFileSync(out, JSON.stringify(data, null, 2) + '\n', 'utf8')

console.log(`wrote ${out}`)
for (const [k, v] of Object.entries(data)) {
  if (k === 'schema' || k === 'note') continue
  const n = Array.isArray(v) ? v.length : Object.keys(v as object).length
  console.log(`  ${k.padEnd(22)} ${String(n).padStart(4)}`)
}
