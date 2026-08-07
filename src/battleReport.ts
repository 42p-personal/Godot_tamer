// Causal battle report (LOOP_DESIGN.md Phase 4). A pure analysis pass over the
// BattleEvent stream + the teams' standing orders that turns "you won" into
// "you won BECAUSE…" — the payoff that makes pre-battle tactics feel causal.
// No engine changes: everything is read from data the sim already emits.
import { BattleEvent, BattleResult } from './battle'
import { GAMEPLANS, Monster, STATS, TeamGameplan } from './core'
import { maxHp } from './monster'
import { ALL_MOVES } from './moves'

type Side = 'A' | 'B'

export interface BattleReport {
  turningPoint: string | null
  tacticOutcomes: { ok: boolean; text: string }[] // player orders that fired or fizzled
  keyMoments: string[]
  counterRead: string | null // the opponent's gameplan, read back after the fight
}

const moveNameById = new Map(ALL_MOVES.map((m) => [m.id, m.name]))

// Reverse-map a monster's standing orders to a known rival gameplan (exact
// tactics match), so the report can name what the opponent was running.
function gameplanOf(m: Monster | undefined): TeamGameplan | null {
  if (!m?.tactics) return null
  const key = JSON.stringify(m.tactics)
  for (const [g, info] of Object.entries(GAMEPLANS)) if (JSON.stringify(info.tactics) === key) return g as TeamGameplan
  return null
}

export function analyzeBattle(
  events: BattleEvent[], teamA: Monster[], teamB: Monster[], result: BattleResult, playerSide?: Side,
): BattleReport {
  const teamOf = (s: Side) => (s === 'A' ? teamA : teamB)
  const nameOf = (s: Side, slot: number) => teamOf(s)[slot]?.name ?? '?'
  const koed = (s: Side, slot: number) => result.finals.some((f) => f.side === s && f.slot === slot && f.wasKOd)

  // --- Turning point: the round the HP gap swung hardest toward the winner ---
  const snaps = events.filter((e): e is Extract<BattleEvent, { kind: 'snap' }> => e.kind === 'snap')
  const fracSum = (states: { side: string; slot: number; hp: number }[], s: Side) =>
    states.filter((st) => st.side === s).reduce((sum, st) => sum + st.hp / Math.max(1, maxHp(teamOf(s)[st.slot].stats)), 0)
  let turningPoint: string | null = null
  if (snaps.length >= 2 && result.winner !== 'draw') {
    const w = result.winner as Side, l: Side = w === 'A' ? 'B' : 'A'
    const diff = snaps.map((sn) => fracSum(sn.states, w) - fracSum(sn.states, l))
    let bestRound = 2, bestSwing = -Infinity
    for (let i = 1; i < diff.length; i++) if (diff[i] - diff[i - 1] > bestSwing) { bestSwing = diff[i] - diff[i - 1]; bestRound = i + 1 }
    const who = !playerSide ? `Team ${w} surged ahead` : w === playerSide ? 'you surged ahead' : 'your opponent surged ahead'
    turningPoint = `Round ${bestRound} decided it — ${who}.`
  } else if (result.winner === 'draw') {
    turningPoint = 'A dead heat — nobody could break the deadlock before the clock ran out.'
  }

  // --- Tactic outcomes (only meaningful when we know which side is the player) ---
  const tacticOutcomes: { ok: boolean; text: string }[] = []
  if (playerSide) {
    const foe: Side = playerSide === 'A' ? 'B' : 'A'
    const mine = teamOf(playerSide), theirs = teamOf(foe)

    // Kill order: a marked enemy the whole team was told to focus.
    const markIdx = theirs.findIndex((m) => m.marked)
    if (markIdx >= 0) {
      const fell = koed(foe, markIdx)
      tacticOutcomes.push({ ok: fell, text: fell
        ? `Your kill order on ${nameOf(foe, markIdx)} worked — it was taken down.`
        : `${nameOf(foe, markIdx)} weathered your kill order and survived.` })
    }
    // Protect order: a guarded carry that should have been kept alive.
    const protIdx = mine.findIndex((m) => m.protect)
    if (protIdx >= 0) {
      const survived = !koed(playerSide, protIdx)
      tacticOutcomes.push({ ok: survived, text: survived
        ? `Your guard held — ${nameOf(playerSide, protIdx)} came through the fight.`
        : `${nameOf(playerSide, protIdx)} fell despite the protect order.` })
    }
    // Scripted opener: did the designated first move actually fire?
    for (let i = 0; i < mine.length; i++) {
      const openerId = mine[i].tactics?.openerIds?.[0]
      if (!openerId) continue
      const openerName = moveNameById.get(openerId)
      const firstAct = events.find((e) => (e.kind === 'hit' || e.kind === 'miss' || e.kind === 'utility') && e.side === playerSide && e.slot === i) as Extract<BattleEvent, { move: string }> | undefined
      const fired = firstAct?.move === openerName
      tacticOutcomes.push({ ok: fired, text: fired
        ? `${nameOf(playerSide, i)} opened on cue with ${openerName}.`
        : `${nameOf(playerSide, i)}'s scripted opener never got the chance to fire.` })
      break // one opener line is enough
    }
  }

  // --- Key moments: the single biggest blow + a KO tally ---
  const keyMoments: string[] = []
  const hits = events.filter((e): e is Extract<BattleEvent, { kind: 'hit' }> => e.kind === 'hit' && e.dmg > 0 && !e.self)
  if (hits.length) {
    const big = hits.reduce((a, b) => (b.dmg > a.dmg ? b : a))
    keyMoments.push(`Biggest blow: ${nameOf(big.side, big.slot)}'s ${big.move} hit ${nameOf(big.targetSide as Side, big.targetSlot)} for ${big.dmg}${big.crit ? ' (crit!)' : ''}.`)
  }
  if (playerSide) {
    const foe: Side = playerSide === 'A' ? 'B' : 'A'
    const downed = teamOf(foe).filter((_, i) => koed(foe, i)).length
    const lost = teamOf(playerSide).filter((_, i) => koed(playerSide, i)).length
    keyMoments.push(`You downed ${downed} of theirs and lost ${lost}.`)
  }

  // --- Counter-read: what the opponent was actually running ---
  let counterRead: string | null = null
  if (playerSide) {
    const foe: Side = playerSide === 'A' ? 'B' : 'A'
    const gp = gameplanOf(teamOf(foe)[0])
    if (gp) counterRead = `They ran ${GAMEPLANS[gp].name}: ${GAMEPLANS[gp].tell}`
  }

  return { turningPoint, tacticOutcomes, keyMoments, counterRead }
}

// Battle Analyst (v0.84): turns a report + the matchup into 1-3 concrete pieces
// of advice for the NEXT fight. A paid-tier layer on top of analyzeBattle.
export function battleAdvice(report: BattleReport, teamA: Monster[], teamB: Monster[], result: BattleResult, playerSide: Side): string[] {
  const mine = playerSide === 'A' ? teamA : teamB
  const theirs = playerSide === 'A' ? teamB : teamA
  const total = (ms: Monster[]) => ms.reduce((s, m) => s + STATS.reduce((t, k) => t + m.stats[k], 0), 0)
  const won = result.winner === playerSide
  const oppCaster = Math.max(0, ...theirs.map((m) => m.stats.INT + m.stats.WIS))
  const failed = (re: RegExp) => report.tacticOutcomes.some((o) => !o.ok && re.test(o.text))
  const tips: string[] = []
  if (report.counterRead && oppCaster >= 380) tips.push("Their casters carried it — set Target priority to 'Hunt the casters', or lead a monster with Control-first to silence/stun them.")
  if (failed(/kill order/)) tips.push('Your focus target survived — mark a squishier threat (their lowest-CON monster), or bring more single-target damage.')
  if (failed(/protect/)) tips.push("Your guarded monster still fell — front-line a tankier body and set it to 'Guard at 40%' survival.")
  if (failed(/opener/)) tips.push('Your scripted opener never fired — pick a cheaper first move so it lands on turn 1.')
  if (!won && total(mine) < total(theirs) * 0.95) tips.push('You were out-powered on paper — train two focused stats higher before the rematch.')
  if (!tips.length) tips.push(won
    ? 'A clean win — keep the same orders unless the next opponent looks different.'
    : 'It was close — a tighter opener or a Control-first lead could flip it next time.')
  return tips.slice(0, 3)
}
