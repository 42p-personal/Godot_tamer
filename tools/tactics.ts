// WHICH TACTICS ACTUALLY REACH THE FIELD ENGINE?
//
// ⚠️ `Tactics` is documented as parameterising the AI side-agnostically — the same
// fields drive the player's orders and rival gameplans. That is true of the TURN
// engine. On the FIELD engine, four of thirteen fields are read by NOTHING:
//
//   manaPolicy       set by 3 GAMEPLANS   — rivals configured with a no-op
//   comboDiscipline  set by 1 GAMEPLAN
//   openerIds        exposed in the UI    — the player sets it, nothing happens
//   ccPriority       exposed in the UI    — the player sets it, nothing happens
//
// ⚠️ CLAUDE.md documents the SPATIAL orders as field-only, with battle.ts ignoring
// them. Nobody wrote down that the reverse also holds, so half the tactics
// vocabulary is silently dead on the engine the game is moving to (M7 retires
// simulateTeamBattle). A player toggling "lead with control" sees no effect.
//
// Same failure family as tools/effects.ts, one layer up: authored, wired to a UI,
// set by content, and never read.
//
// Usage: npx tsx tools/tactics.ts
import * as fs from 'fs'
import * as path from 'path'

/**
 * ⚠️ PARSED FROM THE `Tactics` INTERFACE, NOT HAND-LISTED. This was a literal
 * array, and it went stale the moment a field was renamed: `spacing` became
 * `formation` and `comboDiscipline` became `comboRole`, so the audit cheerfully
 * reported two DELETED fields as "dead on the field engine" while the two LIVE
 * ones went unaudited entirely. An audit that misses a live field is worse than
 * no audit — it reports a clean bill on something it never looked at.
 */
const ALL_TACTICS = (() => {
  const src = fs.readFileSync('src/core.ts', 'utf8')
  const body = src.slice(src.indexOf('export interface Tactics {'))
  const end = body.indexOf('\n}')
  return [...body.slice(0, end).matchAll(/^\s{2}(\w+)\??:/gm)].map((m) => m[1])
})()
const read = (dir: string, filter: (f: string) => boolean) =>
  fs.readdirSync(dir).filter(filter).map((f) => fs.readFileSync(path.join(dir, f), 'utf8')).join('\n')

const field = read('src/tamerengine', (f) => f.endsWith('.ts') && !f.includes('.test.'))
const turn = fs.readFileSync('src/battle.ts', 'utf8')
const plans = fs.readFileSync('src/core.ts', 'utf8')
const ui = ['src/tamerengine/TacticsPanel.tsx', 'src/App.tsx']
  .filter((p) => fs.existsSync(p)).map((p) => fs.readFileSync(p, 'utf8')).join('\n')

// ⚠️ STRING CONCAT, NOT A TEMPLATE LITERAL. `` inside a template literal is a
// BACKSPACE character, not a word boundary — the first version of this tool
// reported all 13 tactics as field-inert because every match returned null, and
// the tool's own headline finding was an escaping bug.
const WORD = String.raw`\b`
const hits = (hay: string, t: string) =>
  (hay.match(new RegExp(WORD + t + WORD, 'g')) ?? []).length

console.log('tactic            field   turn   gameplans   UI')
const dead: string[] = []
for (const t of ALL_TACTICS) {
  const f = hits(field, t)
  if (f === 0) dead.push(t)
  console.log(`  ${t.padEnd(16)}${String(f).padStart(5)}${String(hits(turn, t)).padStart(7)}`
    + `${String(hits(plans, t)).padStart(12)}${String(hits(ui, t)).padStart(5)}`
    + (f === 0 ? '   ← FIELD-INERT' : ''))
}
console.log(`\n${dead.length} of ${ALL_TACTICS.length} tactics are read by NOTHING in the field engine`
  + (dead.length ? `: ${dead.join(', ')}` : ''))
console.log('⚠️ Shrink that number deliberately. Every entry is a control the player'
  + '\n   or a gameplan can set that does nothing in the engine being shipped.')
