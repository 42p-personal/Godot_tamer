// Training drills (§2.4). Chosen as a weekly action.
// - Basic drills: raise one stat by a minor amount, no downside.
// - Intensive drills: raise one stat by a greater amount, but slightly lower another.
// Gains are clamped to the monster's license cap and reduced by the life-stage
// training malus (§9.1). Values are first-pass and meant for tuning.
import { Stat } from './core'

export type DrillKind = 'basic' | 'intensive' | 'extreme' | 'diverse'

export interface Drill {
  id: string
  name: string
  kind: DrillKind
  gains: Partial<Record<Stat, number>> // positive = raise, negative = lower
  desc: string
}

export const BASIC_GAIN = 6
export const INTENSIVE_GAIN = 12
export const INTENSIVE_COST = 4

export const BASIC_DRILLS: Drill[] = [
  { id: 'weights', name: 'Weight Training', kind: 'basic', gains: { STR: BASIC_GAIN }, desc: 'Steady strength work.' },
  { id: 'agility', name: 'Agility Course', kind: 'basic', gains: { DEX: BASIC_GAIN }, desc: 'Footwork and reflex drills.' },
  { id: 'endurance', name: 'Endurance Run', kind: 'basic', gains: { CON: BASIC_GAIN }, desc: 'Long, steady conditioning.' },
  { id: 'meditation', name: 'Meditation', kind: 'basic', gains: { WIS: BASIC_GAIN }, desc: 'Quiet focus and breath work.' },
  { id: 'study', name: 'Study', kind: 'basic', gains: { INT: BASIC_GAIN }, desc: 'Books, runes, and theory.' },
  { id: 'stage', name: 'Stage Practice', kind: 'basic', gains: { CHA: BASIC_GAIN }, desc: 'Poise and presence.' },
]

export const INTENSIVE_DRILLS: Drill[] = [
  { id: 'powerlift', name: 'Powerlifting', kind: 'intensive', gains: { STR: INTENSIVE_GAIN, DEX: -INTENSIVE_COST }, desc: 'Raw power; bulk dulls speed.' },
  { id: 'berserker', name: 'Berserker Training', kind: 'intensive', gains: { STR: INTENSIVE_GAIN, WIS: -INTENSIVE_COST }, desc: 'Fury over composure.' },
  { id: 'sprints', name: 'Sprint Intervals', kind: 'intensive', gains: { DEX: INTENSIVE_GAIN, STR: -INTENSIVE_COST }, desc: 'Lean speed; less brawn.' },
  { id: 'acrobatics', name: 'Acrobatics', kind: 'intensive', gains: { DEX: INTENSIVE_GAIN, CON: -INTENSIVE_COST }, desc: 'Nimbleness over toughness.' },
  { id: 'toughening', name: 'Toughening Regimen', kind: 'intensive', gains: { CON: INTENSIVE_GAIN, DEX: -INTENSIVE_COST }, desc: 'Mass and grit; heavier feet.' },
  { id: 'irondiet', name: 'Iron Diet', kind: 'intensive', gains: { CON: INTENSIVE_GAIN, INT: -INTENSIVE_COST }, desc: 'Body over book.' },
  { id: 'deepmed', name: 'Deep Meditation', kind: 'intensive', gains: { WIS: INTENSIVE_GAIN, STR: -INTENSIVE_COST }, desc: 'Inner focus; softer muscle.' },
  { id: 'ascetic', name: 'Ascetic Trance', kind: 'intensive', gains: { WIS: INTENSIVE_GAIN, CHA: -INTENSIVE_COST }, desc: 'Solitude over showmanship.' },
  { id: 'arcane', name: 'Arcane Study', kind: 'intensive', gains: { INT: INTENSIVE_GAIN, CON: -INTENSIVE_COST }, desc: 'The mind sharpens; the body wanes.' },
  { id: 'runic', name: 'Runic Focus', kind: 'intensive', gains: { INT: INTENSIVE_GAIN, STR: -INTENSIVE_COST }, desc: 'Mind over might.' },
  { id: 'oratory', name: 'Oratory Drills', kind: 'intensive', gains: { CHA: INTENSIVE_GAIN, INT: -INTENSIVE_COST }, desc: 'Charm over calculation.' },
  { id: 'showmanship', name: 'Showmanship', kind: 'intensive', gains: { CHA: INTENSIVE_GAIN, CON: -INTENSIVE_COST }, desc: 'Flair over conditioning.' },
]

// Extreme drills (v0.6 economy pass, user spec): the risk tier above intensive —
// a big gain to one stat at the cost of EIGHT points across TWO paired stats and
// heavy stamina. Locked behind the Extreme Training Manual (Ranch Shop, 800g).
// v0.90: retuned 20/-6 -> 24/-4 so the tier nets +16 (24 - 4 - 4), exactly
// matching DIVERSE's +16 at the same 35 stamina. The two are deliberate MIRRORS:
// same total gain, same cost, opposite shape. Extreme puts every point into one
// stat and pays for it out of two others; diverse splits the same total across a
// pair and pays nothing. The softer -4 (was -6) keeps the tier a gamble without
// making it a trap — two drills can still un-learn a move or drop a class
// threshold, but a single one is far less likely to wreck a build.
export const EXTREME_GAIN = 24
export const EXTREME_COST = 4

export const EXTREME_DRILLS: Drill[] = [
  { id: 'xstr', name: 'Titan Regimen', kind: 'extreme', gains: { STR: EXTREME_GAIN, DEX: -EXTREME_COST, WIS: -EXTREME_COST }, desc: 'Brutal loads; speed and composure pay for it.' },
  { id: 'xdex', name: 'Gauntlet Sprints', kind: 'extreme', gains: { DEX: EXTREME_GAIN, STR: -EXTREME_COST, CON: -EXTREME_COST }, desc: 'Blinding speed; muscle and mass melt away.' },
  { id: 'xcon', name: 'Stone Vigil', kind: 'extreme', gains: { CON: EXTREME_GAIN, DEX: -EXTREME_COST, INT: -EXTREME_COST }, desc: 'Unmoving endurance; quickness and wits dull.' },
  { id: 'xwis', name: 'Void Fast', kind: 'extreme', gains: { WIS: EXTREME_GAIN, STR: -EXTREME_COST, CHA: -EXTREME_COST }, desc: 'Total seclusion; body and charm wither.' },
  { id: 'xint', name: 'Forbidden Texts', kind: 'extreme', gains: { INT: EXTREME_GAIN, CON: -EXTREME_COST, CHA: -EXTREME_COST }, desc: 'Dangerous knowledge; health and warmth fade.' },
  { id: 'xcha', name: 'Grand Spectacle', kind: 'extreme', gains: { CHA: EXTREME_GAIN, WIS: -EXTREME_COST, INT: -EXTREME_COST }, desc: 'All showmanship; depth and study abandoned.' },
]

// Diverse drills (v0.90): raise TWO stats by +8 each with NO malus, for 35
// stamina — the exact mirror of an EXTREME drill (+24 / -4 / -4 = +16 at 35
// stamina). Neither tier is stronger; you are choosing a SHAPE. Extreme is one
// huge spike bought with two sacrifices; diverse is a clean pair with nothing
// given up. Locked behind the Diverse Training Manual (Ranch Shop, 800g).
//
// All six pairs are OFF-ARCHETYPE: of the 15 possible stat pairs, 9 are a
// CLASSES primary/secondary pair and these are the other 6. So a diverse drill
// never just hands you a class — it pushes a monster somewhere the class table
// has no entry for, and whatever class emerges is a consequence of the whole
// build rather than of picking the matching drill.
// That complement set is also perfectly even on its own: every stat appears in
// exactly TWO of the six, so no build is favoured. Both properties come from the
// same choice — changing any single pair breaks one or both, so retune with care.
export const DIVERSE_GAIN = 8

export const DIVERSE_DRILLS: Drill[] = [
  { id: 'dpilgrim', name: "Pilgrim's Burden", kind: 'diverse', gains: { STR: DIVERSE_GAIN, WIS: DIVERSE_GAIN }, desc: 'Stone carried up the mountain and back — the body labours, the mind settles.' },
  { id: 'dcannon', name: 'The Cannon Crew', kind: 'diverse', gains: { STR: DIVERSE_GAIN, INT: DIVERSE_GAIN }, desc: 'Haul the barrel into place, then work out exactly where it points.' },
  { id: 'dtrapeze', name: 'Trapeze Hours', kind: 'diverse', gains: { DEX: DIVERSE_GAIN, CON: DIVERSE_GAIN }, desc: 'Swing until the hands give out, then swing another hour.' },
  { id: 'dblindfold', name: 'Blindfold Forms', kind: 'diverse', gains: { DEX: DIVERSE_GAIN, WIS: DIVERSE_GAIN }, desc: 'Practised sightless, until reading the room stops needing eyes.' },
  { id: 'dfall', name: 'Taking the Fall', kind: 'diverse', gains: { CON: DIVERSE_GAIN, CHA: DIVERSE_GAIN }, desc: 'Absorb the hit, sell the hit, get up grinning.' },
  { id: 'dpatter', name: "Illusionist's Patter", kind: 'diverse', gains: { INT: DIVERSE_GAIN, CHA: DIVERSE_GAIN }, desc: 'Sleight of hand and a running commentary nobody can quite follow.' },
]

export const ALL_DRILLS: Drill[] = [...BASIC_DRILLS, ...INTENSIVE_DRILLS, ...EXTREME_DRILLS, ...DIVERSE_DRILLS]
