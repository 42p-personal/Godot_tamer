// AUTHOR PROJECTILE CHARACTER ONTO EVERY MOVE THAT FLIES.
//
// ⚠️ WHY THIS EXISTS (decision #34). The field sim owns exactly TWO projectile
// speeds — `sim.gd:PROJECTILE_SPEED = {ranged: 90, magic: 55}` — and they are
// keyed by CHANNEL. That is the same conflation `authorranges.ts` was written to
// undo one axis earlier: DEX's channel is `ranged` whether the move is a longbow
// or a stiletto, so a thrown knife at 2.8 reach and Deadeye at 9.2 currently fly
// at the identical 90 u/s, and every INT spell in the pool — a curling hex, a
// snap bolt, a lobbed boulder — is one 55 u/s blob. A shot's flight is the most
// visible thing about it in a game whose entire battle loop is WATCHING, and the
// engine was rendering all 41 of them the same.
//
// ⚠️ AND IT IS NOT ONLY LOOKS. Speed is a real tactical quantity here: shots
// resolve at LAUNCH and apply at ARRIVAL (sim.gd `_projectile_land`), so a slow
// shot is one a dying target can outlive and a fast one is committed damage.
// Width and pierce are new mechanics, deliberately dormant until the integrator
// wires them (see §INTEGRATION at the foot of this file) — the DATA lands first
// so that job is small.
//
// Three axes, seeded per LINE, because a line is a group sharing a win condition
// and how its shots travel is part of that identity — the same argument that put
// reach on the line rather than the channel:
//
//   speed  world units/second. Directly comparable to the 90/55 being replaced.
//   width  in BODY RADII (a monster is 1.0; sim.gd BODY_RADIUS = 2.2 world).
//          The shot's own radius, added to a body's for the clip test. ⚠️ 0 is
//          exactly today's behaviour — a point that only ever touches the body
//          it homed on. Width is what lets a shot clip someone it never aimed at.
//   pierce how many ADDITIONAL bodies the shot passes through before expending.
//          ⚠️ NOT `effects.pierce`, which is armour penetration as a fraction
//          (Void Lance 0.5) and an entirely different quantity. They are nested
//          apart on purpose; do not merge them.
//
// ⚠️ WRITES EXPLICIT NUMBERS INTO src/moves.ts AND IS NOT A RUNTIME RULE — same
// contract as authorranges.ts. The output is authored data a designer argues
// with; the generator only seeds it, and re-running would erase hand-tuning, so
// it refuses without --force.
//
// Usage: npx tsx tools/authorprojectiles.ts [--write] [--force]
import * as fs from 'fs'
import { ALL_MOVES } from '../src/moves'
import { LINE_OF } from '../src/lines'
import type { Move, MoveProjectile } from '../src/core'

/**
 * ⚠️ ONLY THESE CHANNELS FLY, AND THAT MUST NOT CHANGE HERE. `sim.gd` takes the
 * projectile branch on `PROJECTILE_SPEED.has(channel)` — melee and voice are
 * instant (a swing and a shout have no flight path) and friendly casts return
 * before the check. Authoring a speed onto a shout would be a number nothing
 * reads at best, and a melee swing that suddenly travels at worst.
 */
const FLYING_CHANNELS = new Set(['ranged', 'magic'])

/**
 * ⚠️ AND A FRIENDLY CAST NEVER FLIES EITHER, WHATEVER ITS CHANNEL. `sim.gd`
 * `_execute_cast` resolves self/ally/team casts on their own path and RETURNS
 * before the channel check — they are touch and aura, not shots. Exactly one
 * move in the pool is caught by this (Firewall: magic, self), and authoring a
 * speed onto it would be a number describing a flight that cannot happen.
 */
const FRIENDLY_TARGETS = new Set(['self', 'ally', 'team'])

/**
 * Per-line projectile character. The reason column is the point — a number
 * without one is how this project ended up with two channel constants nobody
 * had ever decided.
 */
const LINE_PROJECTILE: Record<string, MoveProjectile> = {
  // ── DEX ────────────────────────────────────────────────────────────────────
  // ⚠️ Assassin is channel `ranged` and fights at 2.4–2.8 reach. It is a flicked
  // blade, not a shot: over ~6 world units of flight it is functionally instant,
  // and it SHOULD be — an assassin's tell is that there wasn't one.
  Assassin: { speed: 130, width: 0.20, pierce: 0 },
  // Darts. Thin and quick; they hit the throat they were aimed at or nothing.
  Venomcraft: { speed: 95, width: 0.22, pierce: 0 },
  // ⚠️ The bow line is the SLOWEST of the three ranged lines on purpose. Volley
  // fights at 8.4–11.0, the longest reach in the game, and a shot that crosses
  // 24 world units instantly makes that reach invisible. A visible arc is what
  // turns "it out-ranges you" from a stat into something the player watches
  // happen. The width is the widest of the ranged lines for the same reason —
  // walking through a firing line should cost you.
  Volley: { speed: 78, width: 0.45, pierce: 0 },
  // ── INT ────────────────────────────────────────────────────────────────────
  // Force, not weather: flat, fast and it does not stop politely at the first
  // body. The ONLY line that pierces by default, and the one whose shots read as
  // beams and lances rather than as thrown objects.
  Arcanist: { speed: 72, width: 0.55, pierce: 1 },
  // A curse curls; a fracturing stone lobs. Slow enough that the target is
  // visibly living on borrowed time between launch and landing, which is the
  // whole fiction of a hex.
  Hexer: { speed: 46, width: 0.50, pierce: 0 },
  // ⚠️ THE ARTILLERY LINE — the slowest and fattest in the pool. This is the
  // "lobbed boulder" the decision names: comets, boulders, a wall of frost. Its
  // legibility is that you see it coming and you see where it lands.
  Elementalist: { speed: 34, width: 0.85, pierce: 0 },
}

/** Absolute sanity rails. Nothing modulates out of plausibility. */
const SPEED_CLAMP: [number, number] = [25, 145]
const WIDTH_CLAMP: [number, number] = [0.12, 1.70]
const PIERCE_CLAMP: [number, number] = [0, 3]

/**
 * ⚠️ PIERCE IS NAMED, NEVER DERIVED. There is no signal in the data that says
 * "this thing goes through people" — power does not (Arcane Overload is a beam,
 * Throat Cut is not), and channel certainly does not. So the moves whose fiction
 * IS penetration are listed, and everything else takes its line's default.
 */
const PIERCE_BY_NAME: Record<string, number> = {
  'Piercing Shot': 2,     // named for it; the one move where this was always true
  'Void Lance': 2,        // a lance runs through — `effects.pierce: 0.5` is its ARMOUR half
  'Arcane Overload': 3,   // the pool's biggest number (168); it unmakes the whole line
  'Deadeye': 1,           // a marksman's shot exits
  'Ricochet': 1,          // it bounces onward by name
  'Static Chain': 1,      // it chains
  'Smoke Bomb': 0,        // ⚠️ explicit: a bomb STOPS. Listed so nobody "fixes" it later.
}

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

const clamp = (v: number, [lo, hi]: [number, number]) => Math.max(lo, Math.min(hi, v))

/**
 * The projectile a move flies as, or `null` if it does not fly.
 *
 * ⚠️ MODULATION READS AUTHORED SIGNALS, NEVER POWER ALONE. The first draft scaled
 * speed off power — heavier is slower — and it produced a Deadeye (power 131,
 * variance 0.05, the capstone marksman shot) as the SLOWEST arrow in the game,
 * which is precisely backwards. Power says how much it hurts, not what shape it
 * is. `variance` and `hits` are the fields that already encode shape, so those
 * are what modulate here: a disciplined shot (variance 0.05) is fast and thin, a
 * wild throw (0.30+) is slow and fat, and a burst of many small hits is quicker
 * and thinner per shot than one big one.
 */
export function projectileFor(m: Move): MoveProjectile | null {
  const chan = String(m.channel)
  if (!FLYING_CHANNELS.has(chan)) return null
  if (FRIENDLY_TARGETS.has(String(m.target))) return null
  const ln = LINE_OF[m.name]
  const base = LINE_PROJECTILE[ln]
  if (!base) return null

  let speed = base.speed
  let width = base.width

  // ── AIM DISCIPLINE. `variance` is the half-width of the damage roll and is
  // already authored per move as "how reliably this lands where it was aimed".
  // A shot that lands where it aimed is a flat fast one; a wild one wobbles.
  // Centred on the pool's DEFAULT_VARIANCE of 0.15 so an unauthored move sits
  // exactly on its line's seed.
  const varDelta = (m.variance ?? 0.15) - 0.15
  speed *= 1 - 1.6 * varDelta        // 0.05 → +16% · 0.35 → −32%
  width *= 1 + 1.4 * varDelta        // wild throws cover more ground

  // ── MANY SMALL SHOTS. A volley of six is six lighter things in the air; each
  // one is quicker and thinner than the single heavy shot the line usually
  // throws. Read off the authored `hits` range, not invented.
  const hits = m.effects?.hits
  if (hits) {
    const avg = (hits[0] + hits[1]) / 2
    if (avg > 1) {
      const k = Math.min(1, (avg - 1) / 2.5)   // saturates around 3.5 hits
      speed *= 1 + 0.18 * k
      width *= 1 - 0.30 * k
    }
  }

  // ── A HEX IS NOT A MISSILE. A power-0 control move (Sap Will, Curse of Ruin,
  // Unmake) is a thing that reaches you, not a thing thrown at you. Slower, and
  // narrow — it should never clip a bystander it did not curse.
  if ((m.power || 0) <= 0) {
    speed *= 0.80
    width *= 0.55
  }

  // ── THE BURST OPENS. ⚠️ `allEnemies` moves do NOT take the projectile branch
  // today — sim.gd resolves them as a caster-centred burst and returns before
  // the channel check — so this modulation is currently INERT. It is authored
  // anyway because the data should describe the move, not the current wiring;
  // when the integrator gives a burst a travelling delivery, Inferno should
  // already be a slow fat thing and not a dart.
  if (m.target === 'allEnemies') {
    speed *= 0.82
    width *= 1.45
  }

  // ── AND THE ONE THING THAT IS HEAVY ENOUGH TO MATTER. A capstone at twice its
  // line's median really is a bigger object; bounded hard so it modulates rather
  // than redefines, and applied to WIDTH only — see the Deadeye note above for
  // why it must not touch speed.
  const med = MED.get(ln) || 1
  if ((m.power || 0) > 0 && med > 0) {
    const rel = clamp(m.power / med, [0.5, 2.0])
    width *= 1 + 0.20 * clamp(rel - 1, [-1, 1])
  }

  const pierce = PIERCE_BY_NAME[m.name] ?? base.pierce

  return {
    speed: Math.round(clamp(speed, SPEED_CLAMP)),
    width: Math.round(clamp(width, WIDTH_CLAMP) * 100) / 100,
    pierce: Math.round(clamp(pierce, PIERCE_CLAMP)),
  }
}

// ═══ §INTEGRATION — WHAT sim.gd NEEDS, PRECISELY ══════════════════════════════
//
// `scripts/sim/kit.gd` already attaches the authored block to every flying kit
// entry as `entry.projectile = {speed, width, pierce}`, with the CHANNEL
// constants as the fallback, so an unauthored move is byte-identical to today.
// Three small changes in `sim.gd` consume it (that file is owned elsewhere):
//
//  1. SPEED — in `_execute_cast`, replace
//         "speed": float(PROJECTILE_SPEED[chan]),
//     with the entry's authored value:
//         "speed": float(kentry.get("projectile", {}).get("speed", PROJECTILE_SPEED[chan])),
//     and carry "width"/"pierce" onto the in-flight dictionary alongside it.
//     ⚠️ KEEP THE `PROJECTILE_SPEED.has(chan)` GATE AS THE FLIGHT TEST. Do not
//     switch it to `kentry.has("projectile")` — the gate is what guarantees a
//     shout and a swing never travel, and kit.gd's own channel filter is a
//     second lock on the same door, not a replacement for it.
//
//  2. WIDTH — in `_advance_projectiles`, after stepping a shot, test the swept
//     segment against every living enemy body of the shooter's side in UNIT-ID
//     ORDER (determinism: iterate `units` as already ordered, never a dict) and
//     treat a body as clipped when the segment's distance to it is
//     <= BODY_RADIUS + width * BODY_RADIUS. width == 0.0 must short-circuit the
//     whole test so today's path stays literally unchanged.
//     ⚠️ THE CLIPPED BODY IS NOT THE RESOLVED ONE. The outcome riding the shot
//     was resolved at launch against the HOMED target. A clipped bystander needs
//     its OWN resolve_strike, which means NEW RNG DRAWS — three per clip
//     (acc/crit/variance) plus the hit-gated status draw, in clip order. That is
//     a new position in the rng stream and it MUST be documented in sim.gd's
//     header alongside the existing four draws, or every fight silently rewrites
//     itself and no probe says why.
//
//  3. PIERCE — a shot expends on its homed target as today when pierce == 0.
//     With pierce == N it survives up to N clipped bodies, decrementing a
//     counter, and only then lands/expends. `proj_hit` fires per body; the
//     watch scene already presents that kind, so no renderer work is needed.
//
// ⚠️ ALL THREE CHANGE FIGHT TRAJECTORIES, AND (2) CHANGES THE RNG STREAM. Land
// speed first on its own — it is a one-line swap with no new draws — and read
// the probes before touching width, so a shifted check has exactly one candidate
// cause instead of three.

// Only when run as a script — `projectileFor` is importable by tools and tests.
if (/authorprojectiles/.test(process.argv[1] ?? '')) {
  const rows = ALL_MOVES.map((m) => ({ m, ln: LINE_OF[m.name] ?? '??', p: projectileFor(m) }))
  const missing = rows.filter((x) => x.ln === '??')
  if (missing.length) {
    console.error(`⚠️ ${missing.length} moves have no LINE — cannot author: `
      + missing.map((x) => x.m.name).join(', '))
    process.exit(1)
  }
  const flying = rows.filter((x) => x.p !== null) as { m: Move; ln: string; p: MoveProjectile }[]

  // ⚠️ TRIPWIRE: every move on a flying CHANNEL must have got a block. If a new
  // line appears in LINE_OF with ranged/magic moves and nobody seeds it here,
  // those moves silently fall back to the channel constant — which is exactly
  // the invisible-default failure this tool exists to end.
  const unseeded = rows.filter((x) => FLYING_CHANNELS.has(String(x.m.channel))
    && !FRIENDLY_TARGETS.has(String(x.m.target)) && x.p === null)
  if (unseeded.length) {
    console.error(`⚠️ ${unseeded.length} flying moves have no line seed in LINE_PROJECTILE: `
      + unseeded.map((x) => `${x.m.name} (${x.ln})`).join(', '))
    process.exit(1)
  }

  const byLine = new Map<string, { m: Move; p: MoveProjectile }[]>()
  for (const x of flying) byLine.set(x.ln, [...(byLine.get(x.ln) ?? []), { m: x.m, p: x.p }])
  console.log('line            n   speed        width       pierce')
  const order = [...byLine].sort((a, b) => LINE_PROJECTILE[a[0]].speed - LINE_PROJECTILE[b[0]].speed)
  for (const [ln, xs] of order) {
    const sp = xs.map((x) => x.p.speed), wd = xs.map((x) => x.p.width), pc = xs.map((x) => x.p.pierce)
    console.log(`${ln.padEnd(14)} ${String(xs.length).padStart(2)}  `
      + `${String(Math.min(...sp)).padStart(3)}–${String(Math.max(...sp)).padEnd(4)}  `
      + `${Math.min(...wd).toFixed(2)}–${Math.max(...wd).toFixed(2)}  `
      + `${Math.min(...pc)}–${Math.max(...pc)}`)
  }
  console.log(`\n${flying.length} of ${rows.length} moves fly (channels ranged/magic); `
    + `${rows.length - flying.length} are instant by channel and author nothing.`)
  console.log(`speed ${Math.min(...flying.map((x) => x.p.speed))}–${Math.max(...flying.map((x) => x.p.speed))} u/s `
    + `(replacing the two constants 90 / 55), `
    + `${flying.filter((x) => x.p.pierce > 0).length} pierce.`)

  if (!process.argv.includes('--write')) {
    console.log('\n(dry run — pass --write to author into src/moves.ts)')
    process.exit(0)
  }

  const src = fs.readFileSync('src/moves.ts', 'utf8')
  // ⚠️ Strip any previous pass first, or the insert doubles the key — the trap
  // authorranges.ts documents, and the same fix.
  const cleaned = src.replace(/ projectile: \{ speed: [0-9.]+, width: [0-9.]+, pierce: [0-9]+ \},/g, '')
  if (/\bprojectile: \{/.test(src) && !process.argv.includes('--force')) {
    console.error('src/moves.ts already authors projectiles — refusing to overwrite hand-tuning. Use --force.')
    process.exit(1)
  }
  let out = cleaned
  let done = 0
  for (const { m, p } of flying) {
    // Single-line literals, keyed by the unique `name:` — the same key LINE_OF
    // and INNATE_EFFECTS use, so a rename breaks this loudly rather than quietly.
    const needle = `{ name: '${m.name.replace(/'/g, "\\'")}',`
    const alt = `{ name: "${m.name}",`
    const at = out.indexOf(needle) >= 0 ? out.indexOf(needle) : out.indexOf(alt)
    if (at < 0) { console.error(`could not locate ${m.name}`); process.exit(1) }
    const end = out.indexOf('\n', at)
    const line = out.slice(at, end)
    const descAt = line.indexOf(' desc:')
    if (descAt < 0) { console.error(`no desc in ${m.name}`); process.exit(1) }
    const lit = ` projectile: { speed: ${p.speed}, width: ${p.width}, pierce: ${p.pierce} },`
    out = out.slice(0, at) + line.slice(0, descAt) + lit + line.slice(descAt) + out.slice(end)
    done++
  }
  fs.writeFileSync('src/moves.ts', out)
  console.log(`\nauthored ${done} projectiles into src/moves.ts`)
  console.log('next: npx tsx tools/exportdata.ts   (flows through to monster-tamer/data/data.json)')
}
