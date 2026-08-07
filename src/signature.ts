// SIGNATURE SKILLS (v0.91) — the one move a monster EARNS rather than learns,
// and the only thing besides stats and potential that a bloodline passes down.
//
// EARNED at the Signature Rite (town.ts): an on-demand special event modelled on
// the rank-up trial, fought by the WHOLE active roster, allowed once a year win
// or lose, harder than a rank-up champion at every rung, and gated on TRAINER
// level 6. Win and the player CHOOSES one monster and one move from that
// monster's body-type list (signatureMoves.ts). That is the only source.
//
// INHERITED DORMANT. A bred child of a signature-holder is born knowing the move
// at SIGNATURE_DORMANT_MULT power with its rider effects stripped, and awakens it
// to full by training the relevant stat up to what the parent had when the parent
// earned it (`awakenStat`). The dynasty starts ahead but still has something left
// to achieve, and the bar it must clear is literally its ancestor's peak. See
// breed() in town.ts and the awakening check in applyWeek.
//
// COSTS A NORMAL LOADOUT SLOT (user spec) — careerMonster() appends the signature
// to the learned-move pool, so it competes with the 90-move pool for one of three
// slots like anything else. That choice is also what keeps this small: the
// ability selector, auto-pick and the battle engine need no knowledge of
// signatures at all.
//
// ⚠️ Why the golden battle tests do NOT move: this file adds no engine code. A
// signature resolves to an ordinary `Move`, handed to simulateTeamBattle through
// the existing loadout path. Generated and rival monsters never carry one, so
// every golden matchup is byte-identical.
import { Move, Stat } from './core'
import { signatureMoveById } from './signatureMoves'

export interface Signature {
  moveId: string // id into signatureMoves.ts (`SIG-<listKey>-<index>`)
  stat: Stat // the stat the awaken bar is measured on — the earner's best at the time
  eventName: string // which rite forged it, for the log and the UI
  forgedBy: string // the monster that first earned it — carried down the line
  awakenStat: number // stat value an heir must reach to wield it at full power
  awakened: boolean // false only for an inherited copy that has not met the bar
  inherited: number // 0 = forged here; N = generations down the line
}

// A dormant (inherited, un-awakened) signature keeps its identity but not its
// edge: 60% power and NO rider effects at all. Still worth a slot on a young
// heir, never worth as much as earning it.
export const SIGNATURE_DORMANT_MULT = 0.6

// Resolve a Signature to the real Move the engine will fight with. A dormant copy
// loses its effects and 40% of its power; everything else is identical, so the UI
// and the battle engine treat an heirloom exactly like any other equipped move.
export function signatureMove(sig: Signature): Move | null {
  const base = signatureMoveById(sig.moveId)
  if (!base) return null // a save from a build where this move was renamed/removed
  if (sig.awakened) return { ...base, desc: '★ Signature — ' + base.desc }
  return {
    ...base,
    power: Math.round(base.power * SIGNATURE_DORMANT_MULT),
    effects: undefined,
    status: undefined,
    desc: '☆ Dormant signature — ' + base.desc,
  }
}

// Forge a brand-new signature. `stat` is the winner's best stat and `atStat` its
// value right now, which becomes the bar every heir must clear to awaken the move.
export const forgeSignature = (opts: {
  moveId: string
  stat: Stat
  atStat: number
  eventName: string
  forgedBy: string
}): Signature => ({
  moveId: opts.moveId,
  stat: opts.stat,
  eventName: opts.eventName,
  forgedBy: opts.forgedBy,
  awakenStat: opts.atStat,
  awakened: true,
  inherited: 0,
})

// The copy a bred child is born with: same move, same lineage, dormant until the
// heir matches its ancestor's peak in that stat.
export const inheritSignature = (sig: Signature): Signature => ({
  ...sig,
  awakened: false,
  inherited: (sig.inherited ?? 0) + 1,
})

// Pure check — has this heir earned the right to wield it at full power?
export const canAwaken = (sig: Signature, stats: Record<Stat, number>): boolean =>
  !sig.awakened && stats[sig.stat] >= sig.awakenStat

// Display name, without needing the caller to resolve the whole Move.
export const signatureName = (sig: Signature): string => signatureMoveById(sig.moveId)?.name ?? 'Unknown Signature'
