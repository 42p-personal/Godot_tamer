// AUTHOR A RANGE ONTO EVERY MOVE IN THE POOL.
//
// ⚠️ WHY THIS EXISTS. `CHANNEL_RANGE` is five numbers standing in for 137, and
// every place that consulted it was guessing. The cost was not theoretical: the
// free attack's channel was reconstructed from whichever move happened to reach
// furthest, so a Warrior that drafted one Piercing Shot became a ranged unit and
// stood off at 6.4 — a melee class shooting, spotted by eye in a replay. That
// bug had already been found and fixed once in `reachOf`; it survived in a
// second copy because the underlying quantity was DERIVED rather than AUTHORED.
//
// Ranges are per-LINE first, because a line is a group sharing a win condition
// and its reach is part of that identity — Volley fights at the far end of the
// field, Assassin fights inside your guard. Individual moves then modulate off
// the line: heavy hitters give up reach, AoE gives up reach (you must come close
// to catch three bodies, which is the same trade `aoeFalloff` prices), and pokes
// keep it.
//
// ⚠️ THIS WRITES EXPLICIT NUMBERS INTO moves.ts AND IS NOT A RUNTIME RULE. The
// output is authored data a designer can argue with and hand-edit; the generator
// only seeds it. Re-running would overwrite hand-tuning, so it refuses unless
// given --force.
//
// Usage: npx tsx tools/authorranges.ts [--write] [--force]
import * as fs from 'fs'
import { ALL_MOVES } from '../src/moves'
import { LINE_OF } from '../src/lines'
import type { Move } from '../src/core'

/**
 * The reach each LINE fights at, in world units, on a field 34–64 wide.
 *
 * Anchored to the four class bands that govern where a unit STANDS (CLASS_BASIC
 * in tamerengine/types.ts: melee 3.0 · ranged 8.0 · magic 7.0 · support 6.0).
 * The bands cap the standoff; these decide what can be thrown from it. A line
 * may deliberately out-reach its band — that is how a Warrior keeps a melee
 * basic and still lands Piercing Shot from where it stands.
 */
const LINE_RANGE: Record<string, number> = {
  // ── STR: everything is inside arm's reach except the shout ──────────────
  Bloodrage: 2.8,     // pays in blood, fights in the blood
  Duelist: 3.4,       // weapon work — the longest honest melee
  Warcry: 6.5,        // a shout carries; it is the STR line that is not a swing
  // ── DEX: the widest spread in the pool, because DEX is knife AND bow ─────
  Assassin: 2.8,      // inside the guard
  Venomcraft: 8.5,    // darts
  Volley: 10.5,       // the longest reach in the game, and its whole identity
  // ── CON: a wall works at the wall ────────────────────────────────────────
  Warden: 3.0,
  Guardian: 4.5,      // reaches an ally to cover them
  Bulwark: 3.0,
  // ── WIS: restores and disrupts from behind the line ──────────────────────
  Disruptor: 7.0,
  Mender: 8.0,        // ⚠️ must out-reach the front line or it cannot heal it
  Siphon: 6.5,
  // ── INT: the artillery stat ──────────────────────────────────────────────
  Hexer: 7.5,
  Elementalist: 8.0,
  Arcanist: 7.0,
  // ── CHA: voice carries, but not as far as a bow ──────────────────────────
  Enchanter: 6.5,
  Captain: 7.5,       // orders reach the whole team
  Demagogue: 6.0,
}

/**
 * ⚠️ THE LINE OWNS THE REACH, NOT THE CHANNEL. The first draft clamped by
 * channel and produced Assassin knives at 5.0–6.5, because DEX's channel is
 * `ranged` whether the move is a bow or a stiletto — and `support` is the
 * channel of every buff, including a Bloodrage self-buff cast mid-brawl. Channel
 * decides MITIGATION and cast time; it was never a statement about distance, and
 * reading reach out of it is the same conflation that made a Warrior shoot.
 *
 * So a move may modulate its line by about a third either way and no further:
 * enough for a heavy capstone or a light poke to feel different from its
 * siblings, never enough to leave the line's identity.
 */
const LINE_SPAN: [number, number] = [0.75, 1.35]
const HARD: [number, number] = [2.4, 11.0]

/** Median power of the line, so "heavy" is judged against its own peers. */
function lineMedians(): Map<string, number> {
  const byLine = new Map<string, number[]>()
  for (const m of ALL_MOVES) {
    const ln = LINE_OF[m.name]
    if (!ln) continue
    const arr = byLine.get(ln) ?? []
    arr.push(m.power || 0)
    byLine.set(ln, arr)
  }
  const out = new Map<string, number>()
  for (const [ln, arr] of byLine) {
    const s = [...arr].sort((a, b) => a - b)
    out.set(ln, s[Math.floor(s.length / 2)] || 1)
  }
  return out
}

const MED = lineMedians()

export function rangeFor(m: Move): number {
  const ln = LINE_OF[m.name]
  const base = LINE_RANGE[ln] ?? 6
  let r = base

  // ⚠️ POWER BUYS ITSELF WITH REACH. A capstone that hits hardest should have to
  // walk into the fight to do it; a cheap poke keeps its distance. Bounded to
  // ±12% so it modulates a line rather than redefining it.
  const med = MED.get(ln) || 1
  if (m.power > 0 && med > 0) {
    const rel = Math.max(0.5, Math.min(2.0, m.power / med))
    r *= 1 - 0.12 * Math.max(-1, Math.min(1, rel - 1))
  }

  // ⚠️ AoE PAYS IN REACH. "Weak into one body, strong into three" is the pool's
  // standing rule; making the caster come closer to catch three is the
  // positional half of that price, and it is the half `aoeFalloff` cannot
  // express. Self/team buffs are exempt — they are cast on your own side.
  if (m.target === 'allEnemies') r *= 0.85

  // A move cast ON AN ALLY has to cover your own formation or a healer stands in
  // the front rank to reach anyone. Capped by the line span below, so a Bulwark
  // shield still reads as a wall's move rather than a ranged one.
  if (m.target === 'ally' || m.target === 'team') r = Math.max(r, 6.0)

  const lo = Math.max(HARD[0], base * LINE_SPAN[0])
  const hi = Math.min(HARD[1], base * LINE_SPAN[1])
  return Math.round(Math.max(lo, Math.min(hi, r)) * 10) / 10
}

// Only when run as a script — `rangeFor` is imported by tools and tests.
if (/authorranges/.test(process.argv[1] ?? '')) {
  // ── report ────────────────────────────────────────────────────────────────
  const rows = ALL_MOVES.map((m) => ({ m, ln: LINE_OF[m.name] ?? '??', r: rangeFor(m) }))
  const missing = rows.filter((x) => x.ln === '??')
  if (missing.length) {
    console.error(`⚠️ ${missing.length} moves have no LINE — cannot author: `
      + missing.map((x) => x.m.name).join(', '))
    process.exit(1)
  }
  const byLine = new Map<string, number[]>()
  for (const x of rows) byLine.set(x.ln, [...(byLine.get(x.ln) ?? []), x.r])
  console.log('line            n   min   max   (authored reach)')
  for (const [ln, rs] of [...byLine].sort((a, b) => LINE_RANGE[a[0]] - LINE_RANGE[b[0]]))
    console.log(`${ln.padEnd(14)} ${String(rs.length).padStart(2)}  ${Math.min(...rs).toFixed(1).padStart(4)}  ${Math.max(...rs).toFixed(1).padStart(4)}`)
  console.log(`\n${rows.length} moves, reach ${Math.min(...rows.map((x) => x.r))}–${Math.max(...rows.map((x) => x.r))}`)

  if (!process.argv.includes('--write')) {
    console.log('\n(dry run — pass --write to author into src/moves.ts)')
    process.exit(0)
  }

  const src = fs.readFileSync('src/moves.ts', 'utf8')
  // ⚠️ Strip any previous pass first, or the insert doubles the key. The pass
  // this replaced LOOKED authored and was not: 92 moves carried 13 distinct
  // values partitioning cleanly by channel — two buckets per channel — so an
  // Assassin stiletto reached 5.6 for no reason but DEX being typed `ranged`.
  const cleaned = src.replace(/ range: [0-9.]+,/g, '')
  if (/\brange: [0-9]/.test(src) && !process.argv.includes('--force')) {
    console.error('src/moves.ts already authors ranges — refusing to overwrite hand-tuning. Use --force.')
    process.exit(1)
  }
  let out = cleaned
  let done = 0
  for (const { m, r } of rows) {
    // Single-line literals, keyed by the unique `name:` — the same key `LINE_OF`
    // and `INNATE_EFFECTS` use, so a rename breaks this loudly rather than quietly.
    const needle = `{ name: '${m.name.replace(/'/g, "\\'")}',`
    const alt = `{ name: "${m.name}",`
    const at = out.indexOf(needle) >= 0 ? out.indexOf(needle) : out.indexOf(alt)
    if (at < 0) { console.error(`could not locate ${m.name}`); process.exit(1) }
    const end = out.indexOf('\n', at)
    const line = out.slice(at, end)
    const descAt = line.indexOf(' desc:')
    if (descAt < 0) { console.error(`no desc in ${m.name}`); process.exit(1) }
    out = out.slice(0, at) + line.slice(0, descAt) + ` range: ${r},` + line.slice(descAt) + out.slice(end)
    done++
  }
  fs.writeFileSync('src/moves.ts', out)
  console.log(`\nauthored ${done} ranges into src/moves.ts`)
}
