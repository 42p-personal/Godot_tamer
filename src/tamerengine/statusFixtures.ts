// THE STATUS CONTRACT — application, refresh, stacking, and CC diminishing returns.
//
// ⚠️ THIS IS THE BALANCE GUARD-RAIL THE PORT MOST NEEDS TO CARRY. Diminishing returns are the
// hard cap on the lockout build: control on the same target lands 100/75/50/25/immune, and CON
// puts a FLOOR under the meter so a Juggernaut cannot be chained the way a caster can. A port
// that quietly drops any part of that ships an unanswerable comp — and it would present as a
// balance complaint months later, not as a failing test.
//
// None of it touches geometry. The one thing that does — the charm lurch — is reported as a
// number for the caller to act on, and the caller is where the position write stays.
import { StatusKind } from '../core'
import { applyStatus, ActiveStatus } from './statusMath'

const st = (kind: StatusKind, until: number, from = 'e1'): ActiveStatus => ({ kind, until, from })

export interface StatusCase { name: string; axis: string; input: any; expect: any }

const CASES: StatusCase[] = []
function add(axis: string, name: string, over: any) {
  const input = {
    kind: 'stun' as StatusKind, rounds: 2, now: 10, from: 'a1',
    statuses: [] as ActiveStatus[], ccResist: 0, ccImmuneUntil: 0,
    targetCon: 0, targetDead: false,
    ...over,
  }
  CASES.push({ name, axis, input, expect: applyStatus(input) })
}

// ── the plain case ───────────────────────────────────────────────────────────
add('apply', 'a stun lands on a clean target', {})
add('apply', 'a burn lands on a clean target', { kind: 'burn' })
add('apply', 'nothing lands on a dead target', { targetDead: true })

// ── diminishing returns: the 100/75/50/25/immune ladder ─────────────────────
// ⚠️ MEASURED AT EACH RUNG, NOT JUST AT THE ENDS. The step is what makes chain-CC a timing
// decision instead of a dump, and an off-by-one-step port would look almost right.
for (const [i, r] of [0, 0.25, 0.5, 0.75, 1].entries()) {
  add('ccDr', `control at DR rung ${i} (ccResist ${r})`, { ccResist: r })
}
add('ccDr', 'an attrition status ignores the meter entirely', { kind: 'burn', ccResist: 0.75 })
add('ccDr', 'the meter advances even when the control fully fails', { ccResist: 1 })

// ── the CON floor ────────────────────────────────────────────────────────────
// ⚠️ CON IS A FLOOR ON THE METER, NOT A SEPARATE ROLL. A high-CON unit starts partway up the
// DR curve rather than getting a chance to dodge control outright.
for (const con of [0, 300, 900, 1200, 3000]) {
  add('conFloor', `control against CON ${con}`, { targetCon: con })
}
add('conFloor', 'the CON floor caps at 0.3 however high CON goes', { targetCon: 100000 })
add('conFloor', 'an already-high meter beats a low CON floor', { targetCon: 300, ccResist: 0.75 })

// ── cleanse immunity ─────────────────────────────────────────────────────────
add('immunity', 'control is refused inside the immunity window',
  { now: 10, ccImmuneUntil: 11 })
add('immunity', 'control lands once the window closes',
  { now: 11, ccImmuneUntil: 11 })
add('immunity', 'immunity does not block an attrition status',
  { kind: 'burn', now: 10, ccImmuneUntil: 11 })

// ── refresh vs stack ─────────────────────────────────────────────────────────
// ⚠️ REFRESH TAKES THE LONGER OF THE TWO, NEVER THE NEWER. A short re-application must not cut
// a long one short — otherwise a cheap spam move would be a soft dispel of the expensive one.
add('refresh', 'a longer re-application extends', { kind: 'burn', rounds: 5, statuses: [st('burn', 12)] })
add('refresh', 'a shorter re-application does NOT cut it short',
  { kind: 'burn', rounds: 1, statuses: [st('burn', 30)] })
add('refresh', 'refresh re-attributes the source', { kind: 'fear', rounds: 3, statuses: [st('fear', 12, 'old')] })

// bleed is the one stacking status, capped at 3.
add('stacks', 'bleed stacks onto an empty target', { kind: 'bleed', statuses: [] })
add('stacks', 'bleed stacks a second time', { kind: 'bleed', statuses: [st('bleed', 14)] })
add('stacks', 'bleed stacks a third time', { kind: 'bleed', statuses: [st('bleed', 14), st('bleed', 15)] })
add('stacks', 'a fourth bleed is refused',
  { kind: 'bleed', statuses: [st('bleed', 14), st('bleed', 15), st('bleed', 16)] })

// ── the lurch, reported but not performed ───────────────────────────────────
add('lurch', 'charm reports a pull for the caller to perform', { kind: 'charm' })
add('lurch', 'a stun reports no pull', { kind: 'stun' })

// ── duration arithmetic ──────────────────────────────────────────────────────
add('duration', 'rounds convert to seconds', { kind: 'burn', rounds: 3, now: 0 })
add('duration', 'expiry is now plus the granted seconds', { kind: 'burn', rounds: 2, now: 7.5 })

export const STATUS_CASES = CASES

export function buildStatusContract() {
  return {
    schema: 1,
    subject: 'tamerengine/statusMath.ts:applyStatus',
    note: 'Status application, refresh, stacking and CC diminishing returns. The charm lurch '
      + 'is reported as a number; the caller performs the movement. Regenerate with '
      + '`npx tsx tools/exportport.ts`.',
    cases: CASES,
  }
}
