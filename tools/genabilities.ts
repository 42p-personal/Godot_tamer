// Regenerate docs/ABILITIES.md from the actual pool.
//
// ⚠️ THIS DOC WENT STALE BECAUSE IT WAS HAND-WRITTEN. It described the
// pre-rework 90 moves for long enough that CLAUDE.md carried a standing warning
// not to trust it. A reference that has to be maintained by hand alongside 137
// authored moves will always lose. Generated, it cannot disagree with the code.
//
// Usage: npx tsx tools/genabilities.ts        (rewrites docs/ABILITIES.md)
import * as fs from 'fs'
import { ALL_MOVES } from '../src/moves'
import { LINES } from '../src/lines'
import { CLASS_LINES } from '../src/lines'
import { statScaleOf, varianceOf, aoeFalloff, HARD_CONTROL_STATUSES, Move, Stat } from '../src/core'
import { CHANNEL_RANGE } from '../src/tamerengine/types'
import { spatialOf } from '../src/tamerengine/spatial'

const STATS: Stat[] = ['STR', 'DEX', 'CON', 'WIS', 'INT', 'CHA']
const moves = ALL_MOVES as Move[]
const rangeOf = (m: Move) => m.range ?? CHANNEL_RANGE[m.channel]
const areaOf = (m: Move) => spatialOf(m.name)?.area
const isAoe = (m: Move) => !!areaOf(m) || m.target === 'allEnemies'

/** Every rider a move carries, as short readable keywords. */
function keywords(m: Move): string[] {
  const out: string[] = []
  if (m.status) out.push(HARD_CONTROL_STATUSES.has(m.status.kind)
    ? `**${m.status.kind}**` : m.status.kind)
  const fx = (m.effects ?? {}) as Record<string, unknown>
  const LABEL: Record<string, string> = {
    pierce: 'pierce', execute: 'execute', maxHpDmg: '%max HP', bonusVsStatus: 'detonate',
    hits: 'multi-hit', firstStrikeMult: 'first strike', hpScale: 'hp scaling',
    consumeWard: 'spend ward', recoil: 'recoil', lifesteal: 'lifesteal',
    manaBurn: 'mana burn', spreadStatus: 'contagion', guard: 'guard', ward: 'ward',
    thorns: 'thorns', cleanse: 'cleanse', tauntForce: 'taunt',
    atkBuff: 'atk +', defBuff: 'def +', accBuff: 'acc +', dodgeBuff: 'dodge +',
    hpRegenBuff: 'hp regen', regenBuff: 'mp regen',
    atkDebuff: 'atk −', defDebuff: 'def −', accDebuff: 'acc −',
  }
  for (const k of Object.keys(fx)) if (k !== 'duration' && LABEL[k]) out.push(LABEL[k])
  const a = areaOf(m)
  if (a) out.push(`${a.shape} AoE`)
  const sp = spatialOf(m.name)
  for (const k of ['move', 'push', 'pull', 'root', 'slow', 'zone', 'fade', 'backstab'])
    if (sp && (sp as unknown as Record<string, unknown>)[k]) out.push(k)
  return out
}

const L: string[] = []
const p = (s = '') => L.push(s)

p('# The Ability Pool')
p()
p('> **Generated — do not hand-edit.** `npx tsx tools/genabilities.ts` rewrites this')
p('> file from `src/moves.ts`. It went stale once by being written by hand; a')
// ⚠️ COMPUTED, like every other count in this file. This one line held a literal
// `137` while the pool grew to 141 — so each regeneration stamped a stale figure
// into the very header that warns the doc goes stale. A hard-coded number inside a
// generator is the same bug the generator exists to prevent.
p(`> reference maintained alongside ${moves.length} authored moves will always lose that race.`)
p()
p(`**${moves.length} abilities** across six stats and **18 lines**. A line is a group to`)
p('draw from, not a track you commit to — `CLASS_LINES` gives a class affinity for three')
p('of them, and `chooseLoadout` multiplies affine moves by 1.35 so off-line picks stay')
p('reachable.')
p()
p('Reading the numbers:')
p()
p('- **pwr** is the MID-POINT of a damage range, not a fixed number; **±** is the spread.')
p('- **scale** is `statScale` — damage is `pwr × (1 + stat × scale)`, so a high-scaling')
p('  move rewards training the stat rather than just having the move.')
p('- **mp** prices EFFECTIVENESS, not power. `Blood Price` is cheap because it is paid')
p('  for in blood.')
p('- **rng** is field reach in world units (the arena is 40 × 22).')
p('- **cd (s)** is recharge in SECONDS — the field engine reads it directly.')
p('  `battle.ts` still counts rounds and divides by `SECONDS_PER_TURN`; nothing')
p('  authors turns any more.')
p('- AoE damage is judged at THREE targets, never one — `aoeFalloff` is')
p(`  −5%/extra target, floored at 40%, so three bodies is ×${(3 * aoeFalloff(3)).toFixed(2)} of a single hit.`)
p('- **Bold** keywords are HARD control (they take an action away).')
p()

// ── class → lines table ────────────────────────────────────────────────────
p('## Which lines a class draws from')
p()
p('| class | lines |')
p('|---|---|')
for (const [cls, ls] of Object.entries(CLASS_LINES)) p(`| ${cls} | ${ls.join(' · ')} |`)
p()

// ── per stat ───────────────────────────────────────────────────────────────
for (const st of STATS) {
  const ms = moves.filter((m) => m.stat === st)
  p(`## ${st}`)
  p()
  p(`${ms.length} abilities · lines: ${LINES[st].join(' · ')}`)
  p()
  for (const line of LINES[st]) {
    const lm = ms.filter((m) => m.line === line).sort((a, b) => a.learnLevel - b.learnLevel)
    if (!lm.length) continue
    p(`### ${line}`)
    p()
    p('| lv | ability | type | pwr | ± | scale | mp | cd (s) | acc | rng | keywords |')
    p('|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---|')
    for (const m of lm) {
      const pw = m.power > 0 ? String(m.power) : '—'
      const sc = m.power > 0 ? `1/${Math.round(1 / statScaleOf(m))}` : '—'
      p(`| ${m.learnLevel} | **${m.name}** | ${m.type}/${m.channel} | ${pw} `
        + `| ${m.power > 0 ? '±' + Math.round(varianceOf(m) * 100) + '%' : '—'} | ${sc} `
        + `| ${m.mana ?? '—'} | ${m.cooldown} | ${m.accuracy} | ${rangeOf(m)} `
        + `| ${keywords(m).join(', ') || '—'} |`)
    }
    p()
    for (const m of lm) p(`- **${m.name}** — ${m.desc}`)
    p()
  }
}

// ── summary ────────────────────────────────────────────────────────────────
const hard = moves.filter((m) => m.status && HARD_CONTROL_STATUSES.has(m.status.kind))
p('## Totals')
p()
p('| | count |')
p('|---|---:|')
p(`| abilities | ${moves.length} |`)
p(`| lines | 18 |`)
p(`| hard control | ${hard.length} |`)
p(`| area effects | ${moves.filter(isAoe).length} |`)
p(`| damage moves | ${moves.filter((m) => m.type === 'damage').length} |`)
for (const st of STATS) p(`| ${st} | ${moves.filter((m) => m.stat === st).length} |`)
p()
p('---')
p()
p('⚠️ **Elements are removed from the game.** Body types no longer carry a resist/weak')
p('pair and no move carries an element. The INT line named *Elementalist* is unrelated')
p('and stays. See `CLAUDE.md`.')

fs.writeFileSync('docs/ABILITIES.md', L.join('\n') + '\n')
console.log(`docs/ABILITIES.md regenerated — ${moves.length} abilities, ${L.length} lines`)
