// WHICH AUTHORED EFFECTS DO NOTHING ON THE FIELD?
//
// The field engine and the turn engine implement overlapping but DIFFERENT
// subsets of `core.ts:MoveEffects`. An effect the field never reads is silently
// inert: the move is learnable, equippable, castable, and contributes nothing.
// That exact class of bug already cost this project 11 do-nothing moves once.
//
// ⚠️ WORD-BOUNDARY MATCHING WITHOUT BACKSLASHES, ON PURPOSE. The obvious
// `new RegExp('\\b' + key + '\\b')` is a trap in a generated file: if the source
// ends up with a single backslash, '\b' is the BACKSPACE character (U+0008), the
// regex silently matches nothing, and the audit reports EVERY effect as inert —
// including ones you can read the implementation of. A hand-rolled boundary
// check has no escaping to get wrong.
//
// Usage: npx tsx tools/inert.ts
import * as fs from 'fs'
import { ALL_MOVES } from '../src/moves'

const isWordChar = (c: string) => /[A-Za-z0-9_$]/.test(c)
/** True if `key` occurs in `src` as a whole identifier, not inside a longer one. */
function mentions(src: string, key: string): boolean {
  let from = 0
  for (;;) {
    const i = src.indexOf(key, from)
    if (i < 0) return false
    const before = i === 0 ? '' : src[i - 1]
    const after = src[i + key.length] ?? ''
    if (!isWordChar(before) && !isWordChar(after)) return true
    from = i + 1
  }
}

const read = (dir: string) => fs.readdirSync(dir)
  .filter((f) => f.endsWith('.ts') && !f.endsWith('.test.ts'))
  .map((f) => fs.readFileSync(dir + '/' + f, 'utf8')).join('\n')

const fieldSrc = read('src/tamerengine')
const turnSrc = fs.readFileSync('src/battle.ts', 'utf8')

const core = fs.readFileSync('src/core.ts', 'utf8')
const i = core.indexOf('export interface MoveEffects')
const body = core.slice(i, core.indexOf('\n}', i))
const keys = [...body.matchAll(/^\s+(\w+)\??:/gm)].map((m) => m[1])

const all = ALL_MOVES as never as { name: string; stat: string; effects?: Record<string, unknown> }[]
const rows = keys.map((k) => ({
  k,
  field: mentions(fieldSrc, k),
  turn: mentions(turnSrc, k),
  n: all.filter((m) => m.effects && m.effects[k] !== undefined).length,
}))

console.log('EFFECT KEY             field   turn   moves')
for (const r of rows.sort((a, b) => Number(a.field) - Number(b.field) || b.n - a.n))
  console.log('  ' + r.k.padEnd(20)
    + (r.field ? 'yes' : 'NO ').padStart(5)
    + (r.turn ? 'yes' : 'NO ').padStart(7)
    + String(r.n).padStart(8)
    + (!r.field && r.n ? '   <- INERT ON FIELD' : ''))

const dead = rows.filter((r) => !r.field && r.n)
console.log(`\n${dead.length} of ${keys.length} effect keys are authored on moves but never read by the`)
console.log(`field engine, across ${dead.reduce((n, r) => n + r.n, 0)} move instances.`)
if (dead.length) {
  console.log('\nThe moves carrying them:')
  for (const r of dead) {
    const names = all.filter((m) => m.effects && m.effects[r.k] !== undefined)
      .map((m) => m.stat + ':' + m.name)
    console.log('  ' + r.k.padEnd(18) + names.join(', '))
  }
}
