// OBEDIENCE — does the player's target order actually change who gets hit?
//
// ⚠️ THE INSTRUMENT COMES FIRST, AGAIN, AND FOR THE USUAL REASON. `targetPriority` is
// four options in the tactics UI, persisted, scouted and shown to the player as an
// order. Whether it MOVES ANY DAMAGE has never been measured. This project's signature
// failure is content that is authored, priced and unreachable — abilities nobody could
// draft, aptitudes nothing read — and an order that reads as a nudge worth 5% of a
// score is exactly that shape. Measure before touching a line of `decide.ts`.
//
// The metric is SHARE OF DAMAGE landing on enemies matching the order, against a
// control run with the order unset. Damage, not target-picks: a unit that selects the
// right enemy and never reaches it has obeyed nothing.
//
// ⚠️ ONLY 'casters' AND 'tanks' ARE MEASURED. Both are STATIC properties of the target
// (class role, maxHp), so "did it match" is unambiguous at any moment. 'weakest' and
// 'focus' are dynamic — the set of matching enemies changes tick by tick, so a share
// figure would be measuring the fight's shape as much as the order's effect. They need
// their own instrument, and pretending otherwise is how a number gets quoted for years.
//
// Usage: npx tsx tools/targeting.ts [--seeds N]
import { simulateFieldBattle } from '../src/tamerengine/engine'
import { autoDeployByRole } from '../src/tamerengine/hex'
import { COMPS, teamFor } from './comps'
import { roleOfClass } from '../src/core'
import type { Monster, TargetPriority } from '../src/core'

const SEEDS = Number(process.argv.includes('--seeds')
  ? process.argv[process.argv.indexOf('--seeds') + 1] : 6)

/** Does this enemy match the order? Static reads only — see the header. */
const matches = (p: TargetPriority, m: Monster): boolean => {
  if (p === 'casters') return roleOfClass(m.className) === 'support'
  if (p === 'tanks') return (40 + m.stats.CON * 2.0) >= 260
  return false
}

interface Row { dealt: number; onMatch: number; matchFrac: number; clear: number[] }

function run(order: TargetPriority | null): Row {
  let dealt = 0, onMatch = 0, matchN = 0, foeN = 0
  const clear: number[] = []
  for (const comp of COMPS) {
    for (let s = 0; s < SEEDS; s++) {
      const sd = `tgt${s}`
      // ⚠️ THE ORDER GOES ON SIDE A ONLY. Both sides carrying it would move the
      // baseline along with the treatment and the difference would vanish into itself.
      const A = teamFor(comp, 'a', sd).map((m) => ({
        ...m, tactics: { ...m.tactics, targetPriority: order ?? undefined },
      })) as Monster[]
      const B = teamFor(comp, 'b', sd)
      const front = (m: Monster) => ({ front: m.stats.CON + m.stats.STR - m.stats.INT - m.stats.WIS })
      const r = simulateFieldBattle({
        seed: sd + comp.name, teamA: A as never[], teamB: B as never[], obstacles: [],
        placeA: autoDeployByRole('A', A.map(front)), placeB: autoDeployByRole('B', B.map(front)),
      })
      const isMatch = new Map<string, boolean>()
      B.forEach((m, i) => { isMatch.set('B' + i, order ? matches(order, m) : false) })
      if (order) { foeN += B.length; matchN += B.filter((m) => matches(order, m)).length }
      const ev = r.events as never as
        { kind: string; t: number; id: string; targetId: string; dmg: number }[]
      // ⚠️ THE WINDOW CLOSES WHEN THE LAST MATCHING ENEMY DIES, AND WITHOUT THAT THE
      // METRIC PUNISHES SUCCESS. Damage after the supports are dead can only land on
      // non-supports, so an order that works PERFECTLY drags its own share down toward
      // the composition's — the better it obeys, the sooner it runs out of things to
      // obey with. The first version of this tool had no window and reported a hard
      // filter as worth +2.7pp over a nudge, which is how a real effect gets refuted by
      // its own instrument.
      let last = Infinity
      if (order) {
        const matchIds = new Set([...isMatch].filter(([, v]) => v).map(([k]) => k))
        if (matchIds.size) {
          last = 0
          const deadAt = new Map<string, number>()
          for (const e of ev) if (e.kind === 'death' && matchIds.has(e.id)) deadAt.set(e.id, e.t)
          last = deadAt.size === matchIds.size ? Math.max(...deadAt.values()) : Infinity
        }
      }
      if (order) clear.push(Number.isFinite(last) ? last : -1)
      for (const e of ev) {
        if (e.kind !== 'hit' || !e.targetId || e.id[0] !== 'A' || e.targetId[0] !== 'B') continue
        if (e.t > last) continue
        dealt += e.dmg
        if (isMatch.get(e.targetId)) onMatch += e.dmg
      }
    }
  }
  return { dealt, onMatch, matchFrac: foeN ? matchN / foeN : 0, clear }
}

const control = run(null)
console.log(`compositions ${COMPS.length} x ${SEEDS} seeds`)
console.log('')
console.log('order      dmg on matching   share    if targeting were BLIND   lift')
for (const order of ['casters', 'tanks'] as TargetPriority[]) {
  const r = run(order)
  const share = r.onMatch / Math.max(1, r.dealt)
  // ⚠️ THE BASELINE IS THE MATCHING ENEMIES' SHARE OF THE ROSTER, NOT ZERO. If two of
  // five enemies are supports, blind targeting already puts ~40% of damage on them —
  // quoting the raw share as "obedience" would credit the order with the composition.
  const blind = r.matchFrac
  console.log(
    `${order.padEnd(9)}  ${Math.round(r.onMatch).toString().padStart(7)} / `
    + `${Math.round(r.dealt).toString().padEnd(8)} ${(share * 100).toFixed(1).padStart(5)}%`
    + `           ${(blind * 100).toFixed(1).padStart(5)}%      `
    + `${share >= blind ? '+' : ''}${((share - blind) * 100).toFixed(1)}pp`
    + `   cleared ${r.clear.filter((c) => c >= 0).length}/${r.clear.length}`
    + ` in ${(r.clear.filter((c) => c >= 0).reduce((a, b) => a + b, 0)
        / Math.max(1, r.clear.filter((c) => c >= 0).length)).toFixed(1)}s`)
}
console.log('')
console.log(`control (no order): ${Math.round(control.dealt)} damage dealt across the same fights`)
