// THE TICK CONTRACT — timers, regen, attrition, expiry, and the sudden-death clock.
//
// ⚠️ THIS IS WHERE A FIGHT'S PACING ACTUALLY LIVES. Damage decides how hard a blow lands; this
// decides how often anyone can throw one and how long they survive between blows. A port that
// is wrong here produces fights of the wrong LENGTH with perfectly correct damage numbers —
// the hardest kind of discrepancy to localise, because every individual hit checks out.
//
// None of it touches geometry, so all of it survives the spatial rebuild.
import { StatusKind } from '../core'
import { DT, SUDDEN_DEATH_AT } from './types'
import { ActiveStatus } from './statusMath'
import { TickInput, tickUnit, suddenDeathLoss } from './tickMath'

const st = (kind: StatusKind, until: number): ActiveStatus => ({ kind, until, from: 'e1' })

export interface TickCase { name: string; axis: string; input: any; expect: any }

const CASES: TickCase[] = []

/** A unit with nothing happening to it. Each case overrides only what it tests. */
const BASE: TickInput = {
  dt: DT, now: 10,
  hp: 500, maxHp: 500, mp: 50, maxMp: 100,
  wis: 0, isSupport: false,
  statuses: [], mods: [], cooldowns: {},
  ccResist: 0, lastCcAt: 10,
}

function add(axis: string, name: string, over: Partial<TickInput>) {
  const input = { ...BASE, ...over }
  CASES.push({ name, axis, input, expect: tickUnit(input) })
}

// ── timers ───────────────────────────────────────────────────────────────────
add('cooldowns', 'cooldowns count down by dt', { cooldowns: { a: 1.0, b: 0.25 } })
add('cooldowns', 'a cooldown floors at zero, never negative', { cooldowns: { a: 0.05 } })
add('cooldowns', 'an empty cooldown table stays empty', { cooldowns: {} })

// ── mana regen ───────────────────────────────────────────────────────────────
// WIS is the sole regen stat. ⚠️ A SUPPORT earns a flat trickle on top, because it neither
// soaks nor connects reliably — TIME is its resource, and without this its kit is unaffordable.
add('manaRegen', 'no WIS, no regen', { wis: 0 })
add('manaRegen', 'regen at WIS 200', { wis: 200 })
add('manaRegen', 'regen at WIS 400', { wis: 400 })
add('manaRegen', 'a support earns a flat trickle on top', { wis: 200, isSupport: true })
add('manaRegen', 'regen cannot exceed the pool', { wis: 4000, mp: 99.9 })
// ⚠️ `regen` MODS ARE AUTHORED PER ROUND AND PAID PER SECOND. Getting that translation wrong
// makes a buff worth SECONDS_PER_ROUND times too much — and it did nothing at all on the field
// engine until the conversion was added.
add('manaRegen', 'a regen mod is a per-round value paid per second',
  { mods: [{ until: 99, regen: 10 }] })

// ── hp regen ─────────────────────────────────────────────────────────────────
add('hpRegen', 'an hpRegen mod restores per second', { hp: 400, mods: [{ until: 99, hpRegen: 10 }] })
add('hpRegen', 'hp regen cannot exceed the pool', { hp: 499.99, mods: [{ until: 99, hpRegen: 100 }] })
// ⚠️ GATED ON `blockHeal` LIKE EVERY OTHER RESTORE, or healblock has a hole in it and a regen
// buff becomes the one heal it cannot stop.
add('hpRegen', 'healblock stops regen dead',
  { hp: 400, mods: [{ until: 99, hpRegen: 10 }], statuses: [st('healblock', 99)] })

// ── the CC meter cools ───────────────────────────────────────────────────────
// The other half of diminishing returns: without decay, one early stun taxes every later one
// for the whole fight.
add('ccDecay', 'the meter holds inside the reset window', { ccResist: 0.5, lastCcAt: 8, now: 10 })
add('ccDecay', 'the meter clears once the window passes', { ccResist: 0.5, lastCcAt: 6, now: 10 })
add('ccDecay', 'a cold meter stays cold', { ccResist: 0, lastCcAt: 0, now: 10 })

// ── damage over time ─────────────────────────────────────────────────────────
add('dot', 'burn drains hp', { statuses: [st('burn', 99)] })
add('dot', 'bleed drains hp', { statuses: [st('bleed', 99)] })
add('dot', 'three bleed stacks drain three times',
  { statuses: [st('bleed', 99), st('bleed', 99), st('bleed', 99)] })
add('dot', 'burn and bleed together', { statuses: [st('burn', 99), st('bleed', 99)] })
// ⚠️ POISON DRAINS MANA, NOT HEALTH — the one attrition status that attacks the resource
// rather than the pool.
add('dot', 'poison drains mana', { statuses: [st('poison', 99)] })
add('dot', 'mana drain floors at zero', { mp: 0.5, statuses: [st('poison', 99)] })
add('dot', 'attrition can kill', { hp: 0.5, statuses: [st('burn', 99)] })

// ── expiry, and the one status that pays out ON expiry ──────────────────────
add('expiry', 'a status expires when its time is up', { now: 10, statuses: [st('burn', 10)] })
add('expiry', 'a status one tick from expiry survives', { now: 10, statuses: [st('burn', 10.01)] })
// ⚠️ DOOM IS A COUNTDOWN, NOT A DRIP. It does nothing until its timer runs out, then hits for a
// quarter of the victim's health. Cleansing it or killing the caster in time is the whole
// counterplay, so it MUST resolve ON EXPIRY rather than being dropped by the expiry filter.
add('expiry', 'doom detonates for a quarter of max hp when it expires',
  { now: 10, statuses: [st('doom', 10)] })
add('expiry', 'doom does NOTHING while it is still ticking',
  { now: 10, statuses: [st('doom', 20)] })
add('expiry', 'a doom detonation can kill', { hp: 100, now: 10, statuses: [st('doom', 10)] })
add('expiry', 'several statuses expire at once',
  { now: 10, statuses: [st('burn', 9), st('bleed', 10), st('blind', 30)] })

// ── mods expire on their own clock ───────────────────────────────────────────
add('modExpiry', 'an expired mod is dropped', { now: 10, mods: [{ until: 9, regen: 5 }] })
add('modExpiry', 'a live mod is kept', { now: 10, mods: [{ until: 11, regen: 5 }] })

// ── the sudden-death clock ───────────────────────────────────────────────────
// The clock itself starts killing, harder every second, so no pair of teams can stall each
// other past the cap.
const SD: { name: string; now: number }[] = [
  { name: 'before the cap, nothing', now: SUDDEN_DEATH_AT - 1 },
  { name: 'exactly at the cap', now: SUDDEN_DEATH_AT },
  { name: '10s past the cap', now: SUDDEN_DEATH_AT + 10 },
  { name: '60s past the cap ramps hard', now: SUDDEN_DEATH_AT + 60 },
]
for (const c of SD) {
  CASES.push({
    name: `sudden death ${c.name}`, axis: 'suddenDeath',
    input: { now: c.now, maxHp: 500, dt: DT },
    expect: { loss: suddenDeathLoss(c.now, 500, DT) },
  })
}

export const TICK_CASES = CASES

export function buildTickContract() {
  return {
    schema: 1,
    subject: 'tamerengine/tickMath.ts:tickUnit + suddenDeathLoss',
    note: 'Per-tick unit update — timers, regen, attrition, expiry, CC decay, sudden death. '
      + 'Pure arithmetic over time, no geometry. ⚠️ The step ORDER is part of the contract. '
      + 'Regenerate with `npx tsx tools/exportport.ts`.',
    cases: CASES,
  }
}
