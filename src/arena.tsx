// Animated arena: plays a resolved battle's event stream as live beats —
// Teamfight-Manager style. The sim is already decided (deterministic); this is
// pure presentation. 1v1 (Wood/Copper leagues, Sandbox) keeps the original
// lunge/projectile choreography exactly as it was. Team battles (>1 per side)
// use a compact roster-row presentation instead — full per-monster traversal
// animation doesn't stay legible at 6v6 — leaning on the scrolling turn-by-turn
// log for the detailed narration either way.
import { useEffect, useMemo, useRef, useState } from 'react'
import { BattleEvent, BattleResult, BattleSide } from './battle'
import { Channel, Monster, Move, StatusKind, frontRowCount } from './core'
import { maxHp, maxMana } from './monster'
import { analyzeBattle } from './battleReport'
import { Sprite } from './Sprite'
import { backgroundFor } from './leagueArt'

const CHANNEL_COLOR: Record<Channel, string> = { melee: '#eee', ranged: '#ffd54f', magic: '#ba68c8', voice: '#f48fb1', support: '#80cbc4' }
const STATUS_ICON: Record<StatusKind, string> = {
  blind: '🕶️', poison: '☠️', burn: '🔥', fear: '😱', confusion: '💫', stun: '💤', knockback: '💨',
  bleed: '🩸', silence: '🤐', vulnerable: '🎯', sleep: '😴', doom: '💀', healblock: '🚫', haste: '⚡', charm: '💞',
}

// Live status-effect row (2026-07-25 "more information" addition) — reads the
// per-round `snap` event's own status list, so this reflects what's actually
// active right now rather than guessing from transient floats.
function StatusIcons({ statuses }: { statuses: StatusKind[] }) {
  if (!statuses.length) return null
  return (
    <div className="status-row">
      {statuses.map((s, i) => <span key={i} className="status-chip" title={s}>{STATUS_ICON[s]}</span>)}
    </div>
  )
}

interface FloatFx { id: number; side: BattleSide; slot: number; text: string; cls: string }
interface BarState { hp: number; mana: number; ward: number; statuses: StatusKind[] }
type Bars = Record<string, BarState> // keyed by `${side}${slot}`

// Per-move visual identity (user spec 2026-07-25: "a claw raking the enemy, a
// thunderbolt, etc" — every move should look like what it is, not a generic
// dot). `kind` picks the shape/animation; `struct` picks how it gets there:
// 'lunge' — the attacker bumps into melee range, effect lands on the target;
// 'proj' — something travels from attacker to target (arrow/fireball/etc);
// 'burst' — appears directly at the target with no travel (spike erupting
// from the ground, a lightning strike, a soundwave, a psychic pulse).
// Base motions. The first nine are the original channel kit; the rest
// (v0.80) are BESPOKE motions hand-assigned to distinctive moves via BESPOKE_KIND
// below — the "hybrid" the design calls for: shared bases for moves that
// legitimately look alike (every fireball, every arrow), bespoke motions for the
// ones that deserve a signature.
type FxKind =
  | 'claw' | 'arrow' | 'fireball' | 'waterbolt' | 'earthspike' | 'lightning' | 'sonic' | 'psychic' | 'arcane'
  | 'slam' | 'guillotine' | 'flurry' | 'beam' | 'volley' | 'chain' | 'cage' | 'firewall' | 'notes'
type FxStruct = 'lunge' | 'proj' | 'burst' | 'stance'
// Composite overlays — layered on top of ANY base so the effect a move HAS reads
// at a glance, on moves that otherwise share a base. Driven off the resolved
// Move's effects + the event, so no per-move authoring.
type Overlay =
  | 'exec' | 'tether' | 'manaburn' | 'crater'
  | 'shield' | 'thorns' | 'heal' | 'cleanse'
  | 'aura-atk' | 'aura-def' | 'aura-dodge' | 'aura-regen'
interface Fx {
  id: number; side: BattleSide; slot: number; struct: FxStruct; kind?: FxKind; color?: string
  targetSide?: BattleSide; targetSlot?: number; crit?: boolean
  overlays?: Overlay[]; status?: StatusKind
}

// Bespoke base motion per move NAME (the acting Move is resolved from the
// monster's loadout, so names are unique within a fight). Moves not listed fall
// through to the channel base in fxFor — that's the hybrid.
const BESPOKE_KIND: Record<string, FxKind> = {
  // Heavy overhead impacts — crater + screen shake.
  'Power Strike': 'slam', 'Reckless Slam': 'slam', 'Titanfall': 'slam', 'Shell Slam': 'slam',
  'Body Slam': 'slam', 'Colossus Crash': 'slam', 'Earthshaker': 'slam', 'World Ender': 'slam',
  // Decisive finishing drop.
  'Executioner': 'guillotine', 'Showstopper': 'guillotine',
  // Rapid repeated strikes.
  'Flurry of Blows': 'flurry', 'Bloodletter': 'flurry', 'Twin Fangs': 'flurry', 'Shadow Barrage': 'flurry',
  // Instant piercing line.
  'Snipe': 'beam', 'Deadeye': 'beam', 'Pin Down': 'beam', 'Stone Spear': 'beam', 'Void Lance': 'beam',
  // Arced rain of many projectiles.
  'Rain of Arrows': 'volley', 'Needle Storm': 'volley',
  // Arcing bolt that jumps.
  'Static Chain': 'chain',
  // Encasing prison.
  'Glacial Prison': 'cage', 'Deep Freeze': 'cage',
  // Engulfing flame.
  'Inferno': 'firewall',
  // Musical notes (song buffs).
  'Rallying Song': 'notes', 'Battle Hymn': 'notes', 'Standing Ovation': 'notes',
  'Lullaby': 'notes', 'Crescendo': 'notes',
}
// Which struct a bespoke kind travels with.
const KIND_STRUCT: Partial<Record<FxKind, FxStruct>> = {
  slam: 'lunge', guillotine: 'burst', flurry: 'lunge', beam: 'burst', volley: 'burst',
  chain: 'burst', cage: 'burst', firewall: 'burst', notes: 'stance',
}

// ⚠️ ELEMENTS REMOVED — this branched on fire/water/earth/air before the
// channel, because an element was the more specific identity. With elements
// gone the channel is the only delivery signal, and it is the one that maps to
// how a move actually behaves: a lunge, a bolt, a shout.
function fxFor(channel: Channel): { struct: FxStruct; kind: FxKind; color: string } {
  if (channel === 'melee') return { struct: 'lunge', kind: 'claw', color: CHANNEL_COLOR.melee }
  if (channel === 'ranged') return { struct: 'proj', kind: 'arrow', color: CHANNEL_COLOR.ranged }
  if (channel === 'voice') return { struct: 'burst', kind: 'sonic', color: CHANNEL_COLOR.voice }
  if (channel === 'support') return { struct: 'burst', kind: 'psychic', color: CHANNEL_COLOR.support }
  return { struct: 'proj', kind: 'arcane', color: CHANNEL_COLOR.magic } // INT
}

// The full visual for a damaging move: bespoke base if one is assigned (its own
// struct), else the channel base; plus overlays derived from the move
// and the event.
function fxForMove(
  move: Move | undefined, channel: Channel,
  e: { execute?: boolean; lifesteal?: number; manaBurn?: number; crit?: boolean },
): { struct: FxStruct; kind: FxKind; color: string; overlays: Overlay[] } {
  const base = fxFor(channel)
  const bespoke = move && BESPOKE_KIND[move.name]
  const kind = bespoke ?? base.kind
  const struct = bespoke ? (KIND_STRUCT[bespoke] ?? base.struct) : base.struct
  const overlays: Overlay[] = []
  if (e.execute) overlays.push('exec')
  if ((e.lifesteal ?? 0) > 0) overlays.push('tether')
  if ((e.manaBurn ?? 0) > 0) overlays.push('manaburn')
  if (kind === 'slam' || e.crit) overlays.push('crater')
  return { struct, kind, color: base.color, overlays }
}

// The visual for a non-damaging (buff/debuff) move — an aura on the caster or a
// tell on the target, from the move's effects.
function utilityFx(move: Move | undefined): { overlays: Overlay[]; color: string } {
  const fx = move?.effects
  const overlays: Overlay[] = []
  if (fx?.ward || fx?.guard || fx?.defBuff) overlays.push('shield')
  if (fx?.thorns) overlays.push('thorns')
  if (fx?.cleanse) overlays.push('cleanse')
  if (fx?.atkBuff) overlays.push('aura-atk')
  if (fx?.dodgeBuff) overlays.push('aura-dodge')
  if (fx?.regenBuff || fx?.hpRegenBuff) overlays.push('aura-regen')
  if (!overlays.length) overlays.push('aura-def') // generic self-buff glow
  return { overlays, color: CHANNEL_COLOR.support }
}

// Glow colour for a buff/aura overlay, so the team-battle tiles can light up the
// affected monster the way the 1v1 arena's aura overlays do. Every buff/utility
// (struct 'stance') gets SOME glow — a specific colour when the overlay is known,
// else a neutral golden buff-glow — so no buff ever plays without a visible tell.
const AURA_GLOW: Partial<Record<Overlay, string>> = {
  shield: 'rgba(129,212,250,.95)', thorns: 'rgba(174,213,129,.95)', heal: 'rgba(129,199,132,.98)',
  cleanse: 'rgba(255,241,118,.95)', 'aura-atk': 'rgba(239,83,80,.95)', 'aura-def': 'rgba(144,164,174,.95)',
  'aura-dodge': 'rgba(77,208,225,.95)', 'aura-regen': 'rgba(129,199,132,.95)',
}
const BUFF_GLOW_DEFAULT = 'rgba(255,213,79,.9)'
function buffGlowColor(overlays?: Overlay[]): string {
  for (const o of overlays ?? []) if (AURA_GLOW[o]) return AURA_GLOW[o]!
  return BUFF_GLOW_DEFAULT
}

const barKey = (side: BattleSide, slot: number) => `${side}${slot}`
// Fixed 1v1 stage coordinates: the target position an effect travels to /
// erupts at, given which side is attacking (mirrors projA/projB's endpoints).
const targetX1v1 = (attackerSide: BattleSide) => (attackerSide === 'A' ? { left: '78%' } : { left: '22%' })

// Renders one move's visual identity in the 1v1 arena — 'proj' travels
// attacker->target (styled by kind); 'lunge' (claw) lands its slash marks
// directly on the target as the attacker bumps in; 'burst' kinds appear at
// the target with no travel time at all (a spike erupting from the ground
// reads wrong if it "flies" there).
// A claw rake used by both `claw` and the bespoke `flurry` (flurry just repeats
// faster + more strokes, driven by a CSS class).
function ClawFx({ fx, extra }: { fx: Fx; extra?: string }) {
  return (
    <div key={fx.id} className={`claw-fx ${extra ?? ''}`} style={targetX1v1(fx.side)}>
      <svg viewBox="0 0 64 64">
        <path className="claw-slash claw-1" d="M10 16 L42 48" />
        <path className="claw-slash claw-2" d="M18 8 L50 40" />
        <path className="claw-slash claw-3" d="M26 2 L58 34" />
      </svg>
    </div>
  )
}

// The self/target overlays that ride on top of a base motion. `self` overlays
// (auras, shields) anchor on the caster; target overlays (exec flash, mana
// burn, tether) anchor over the target.
function Overlays({ fx }: { fx: Fx }) {
  if (!fx.overlays?.length) return null
  const selfPos = targetX1v1(fx.side === 'A' ? 'B' : 'A') // caster is the "other" end of the target axis
  const tgtPos = targetX1v1(fx.side)
  return (
    <>
      {fx.overlays.map((o, i) => {
        switch (o) {
          case 'crater': return <div key={i} className="ov-crater" style={tgtPos} />
          case 'exec': return <div key={i} className="ov-exec" style={tgtPos} />
          case 'manaburn': return <div key={i} className="ov-manaburn" style={tgtPos} />
          case 'tether': return <div key={i} className={`ov-tether ${fx.side === 'A' ? 'tetherA' : 'tetherB'}`} />
          case 'shield': return <div key={i} className="ov-shield" style={selfPos} />
          case 'thorns': return <div key={i} className="ov-thorns" style={selfPos} />
          case 'heal': return <div key={i} className="ov-heal" style={selfPos} />
          case 'cleanse': return <div key={i} className="ov-cleanse" style={selfPos} />
          case 'aura-atk': return <div key={i} className="ov-aura ov-aura-atk" style={selfPos} />
          case 'aura-def': return <div key={i} className="ov-aura ov-aura-def" style={selfPos} />
          case 'aura-dodge': return <div key={i} className="ov-aura ov-aura-dodge" style={selfPos} />
          case 'aura-regen': return <div key={i} className="ov-aura ov-aura-regen" style={selfPos} />
          default: return null
        }
      })}
    </>
  )
}

function MoveFx({ fx }: { fx: Fx }) {
  const pos = targetX1v1(fx.side)
  // Status landing — a themed icon puff over the afflicted monster.
  if (fx.struct === 'burst' && fx.status) {
    return <div key={fx.id} className="status-puff" style={pos}>{STATUS_ICON[fx.status]}</div>
  }

  let base: JSX.Element | null = null
  if (fx.struct === 'proj') {
    base = <i key={fx.id} className={`proj proj-${fx.kind} ${fx.side === 'A' ? 'projA' : 'projB'}`} style={{ background: fx.color, color: fx.color }} />
  } else if (fx.kind === 'claw') {
    base = <ClawFx fx={fx} />
  } else if (fx.kind === 'flurry') {
    base = <ClawFx fx={fx} extra="claw-flurry" />
  } else if (fx.kind === 'slam') {
    base = <div key={fx.id} className="slam-fx" style={pos}><div className="slam-mark" /></div>
  } else if (fx.kind === 'guillotine') {
    base = <div key={fx.id} className="guillotine-fx" style={pos}><div className="guillotine-blade" /></div>
  } else if (fx.kind === 'beam') {
    base = <div key={fx.id} className={`beam-fx ${fx.side === 'A' ? 'beamA' : 'beamB'}`} style={{ background: fx.color, color: fx.color }} />
  } else if (fx.kind === 'volley') {
    base = <div key={fx.id} className="volley-fx" style={pos}>{[0, 1, 2, 3, 4].map((n) => <i key={n} className="volley-arrow" style={{ animationDelay: `${n * 60}ms` }} />)}</div>
  } else if (fx.kind === 'chain') {
    base = (
      <div key={fx.id} className="lightning-fx chain-fx" style={pos}>
        <svg viewBox="0 0 20 200" className="lightning-bolt" preserveAspectRatio="none">
          <polyline points="10,0 4,80 12,90 2,170 10,200 6,140 14,130 8,50 16,40" fill="none" stroke="#b3e5fc" strokeWidth="3" />
        </svg>
      </div>
    )
  } else if (fx.kind === 'cage') {
    base = <div key={fx.id} className="cage-fx" style={pos}>{[0, 1, 2, 3].map((n) => <i key={n} className="cage-bar" style={{ left: `${12 + n * 22}%` }} />)}</div>
  } else if (fx.kind === 'firewall') {
    base = <div key={fx.id} className="firewall-fx" style={pos} />
  } else if (fx.kind === 'notes') {
    base = <div key={fx.id} className="notes-fx" style={targetX1v1(fx.side === 'A' ? 'B' : 'A')}>{['♪', '♫', '♩'].map((c, n) => <span key={n} className="note" style={{ animationDelay: `${n * 120}ms` }}>{c}</span>)}</div>
  } else if (fx.kind === 'earthspike') {
    base = <div key={fx.id} className="burst-fx" style={pos}><div className="earthspike-fx" /></div>
  } else if (fx.kind === 'lightning') {
    base = (
      <div key={fx.id} className="lightning-fx" style={pos}>
        <svg viewBox="0 0 20 200" className="lightning-bolt" preserveAspectRatio="none">
          <polyline points="10,0 4,80 12,90 2,170 10,200 6,140 14,130 8,50 16,40" fill="none" stroke="#fff59d" strokeWidth="3" />
        </svg>
      </div>
    )
  } else if (fx.kind === 'sonic') {
    base = (
      <div key={fx.id} className="sonic-anchor" style={pos}>
        <div className="sonic-fx sonic-ring1" />
        <div className="sonic-fx sonic-ring2" />
      </div>
    )
  } else if (fx.kind === 'psychic') {
    base = <div key={fx.id} className="psychic-fx" style={pos} />
  }

  return <>{base}<Overlays fx={fx} /></>
}

// Field geometry, extracted as a PURE function so it can be unit-tested without
// a browser (the visual layer cannot be asserted in CI, but the maths can).
// Returns a post in PERCENT of the field box.
//
// ⚠️ Mirrors the engine's `formationRank`: a monster's row is its index among
// still-LIVING teammates, so when a front-liner drops the one behind is promoted
// and visibly walks forward into the gap.
export const FIELD_LANES = { frontA: 35, backA: 17, frontB: 65, backB: 83 }
export function fieldPostFor(
  side: BattleSide, slot: number, livingSlots: number[], teamSize: number,
): { x: number; y: number } {
  const fallen = !livingSlots.includes(slot)
  // A KO'd monster keeps the post it died on rather than snapping elsewhere.
  const order = fallen ? Array.from({ length: teamSize }, (_, i) => i) : livingSlots
  const rank = Math.max(0, order.indexOf(slot))
  const front = frontRowCount(order.length)
  const isFront = rank < front
  const rowCount = isFront ? Math.min(front, order.length) : order.length - front
  const idxInRow = isFront ? rank : rank - front
  const x = side === 'A'
    ? (isFront ? FIELD_LANES.frontA : FIELD_LANES.backA)
    : (isFront ? FIELD_LANES.frontB : FIELD_LANES.backB)
  const span = 54
  const y = rowCount <= 1 ? 50 : 50 - span / 2 + (idxInRow * span) / (rowCount - 1)
  return { x, y }
}

export function ArenaBattle({ teamA, teamB, result, league, playerSide, onDone }: { teamA: Monster[]; teamB: Monster[]; result: BattleResult; league?: string; playerSide?: BattleSide; onDone?: () => void }) {
  const is1v1 = teamA.length === 1 && teamB.length === 1
  const events = result.events
  const bgImage = useMemo(() => backgroundFor(league), [league])

  const [idx, setIdx] = useState(0)
  const [speed, setSpeed] = useState(1)
  const [bars, setBars] = useState<Bars>(() => {
    const out: Bars = {}
    teamA.forEach((m, i) => { out[barKey('A', i)] = { hp: Math.min(m.hp ?? maxHp(m.stats), maxHp(m.stats)), mana: Math.min(m.mp ?? maxMana(m.stats), maxMana(m.stats)), ward: 0, statuses: [] } })
    teamB.forEach((m, i) => { out[barKey('B', i)] = { hp: Math.min(m.hp ?? maxHp(m.stats), maxHp(m.stats)), mana: Math.min(m.mp ?? maxMana(m.stats), maxMana(m.stats)), ward: 0, statuses: [] } })
    return out
  })
  const [round, setRound] = useState(0)
  const [fx, setFx] = useState<Fx | null>(null)
  const [floats, setFloats] = useState<FloatFx[]>([])
  const [caption, setCaption] = useState('The battle begins!')
  const counter = useRef(0)
  const notified = useRef(false)

  const done = idx >= events.length
  const teamOf = (side: BattleSide) => (side === 'A' ? teamA : teamB)
  const nameOf = (side: BattleSide, slot: number) => teamOf(side)[slot]?.name ?? '?'
  // The acting Move, recovered from the caster's loadout by name (names are
  // unique within one monster's loadout) — gives the full effects/element so
  // animations can be move-specific without the event carrying the move object.
  const moveOf = (side: BattleSide, slot: number, name: string): Move | undefined =>
    teamOf(side)[slot]?.loadout.find((m) => m.name === name)

  // Turn-by-turn log: every event's caption accumulates below the fight as it
  // plays (skip fills in the rest), so the replay never spoils itself.
  const [history, setHistory] = useState<string[]>(['The battle begins!'])
  const logRef = useRef<HTMLDivElement>(null)
  useEffect(() => { const el = logRef.current; if (el) el.scrollTop = el.scrollHeight }, [history])

  function captionOf(e: BattleEvent): string | null {
    switch (e.kind) {
      case 'round': return `— Round ${e.n} —`
      case 'snap': return null
      case 'hit': {
        const bits = [e.crit ? 'CRITICAL!' : '', e.hits > 1 ? `${e.hits} hits` : '', e.execute ? 'executes!' : ''].filter(Boolean).join(' · ')
        const tgt = e.self ? '' : ` to ${nameOf(e.targetSide, e.targetSlot)}`
        return `${nameOf(e.side, e.slot)} uses ${e.move} → ${e.dmg} damage${tgt}${bits ? ` (${bits})` : ''}`
      }
      case 'miss': return `${nameOf(e.side, e.slot)}'s ${e.move} ${e.blocked ? 'is blocked!' : `misses ${nameOf(e.targetSide, e.targetSlot)}.`}`
      case 'stance': return `${nameOf(e.side, e.slot)} braces to block (+${e.avoid}% avoid).`
      case 'utility': return `${nameOf(e.side, e.slot)} uses ${e.move}${e.hostile || e.targetSlot !== e.slot || e.targetSide !== e.side ? ` on ${nameOf(e.targetSide, e.targetSlot)}` : ''}.`
      case 'status': return `${nameOf(e.side, e.slot)} is afflicted with ${e.status}!`
      case 'dot': return e.status === 'burn' ? `${nameOf(e.side, e.slot)} suffers ${e.amount} burn damage.`
        : e.status === 'bleed' ? `${nameOf(e.side, e.slot)} bleeds for ${e.amount}.`
        : e.status === 'doom' ? `💀 The doom strikes ${nameOf(e.side, e.slot)} for ${e.amount}!`
        : `${nameOf(e.side, e.slot)} loses ${e.amount} MP to poison.`
      case 'skip': return e.reason === 'stun' ? `${nameOf(e.side, e.slot)} is stunned!`
        : e.reason === 'sleep' ? `${nameOf(e.side, e.slot)} is fast asleep!`
        : `${nameOf(e.side, e.slot)} flees in fear!`
      case 'end': return e.winner === 'draw' ? '🏳️ Double knockout — a draw!' : `🏆 ${result.winnerName} wins!`
    }
  }

  useEffect(() => {
    if (done) {
      if (!notified.current) { notified.current = true; onDone?.() }
      return
    }
    const e = events[idx]
    const delay = applyEvent(e)
    const t = setTimeout(() => setIdx((i) => i + 1), Math.max(25, delay / speed))
    return () => clearTimeout(t)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [idx, done, speed])

  function addFloat(side: BattleSide, slot: number, text: string, cls: string) {
    const id = ++counter.current
    setFloats((f) => [...f, { id, side, slot, text, cls }])
    setTimeout(() => setFloats((f) => f.filter((x) => x.id !== id)), 1100)
  }

  function applyEvent(e: BattleEvent): number {
    const cap = captionOf(e)
    if (cap) setHistory((h) => [...h, cap])
    if (cap && e.kind !== 'dot') setCaption(cap)
    switch (e.kind) {
      case 'round':
        setRound(e.n)
        return 450
      case 'snap':
        setBars((prev) => {
          const next = { ...prev }
          for (const s of e.states) next[barKey(s.side, s.slot)] = { hp: s.hp, mana: s.mana, ward: s.ward, statuses: s.statuses }
          return next
        })
        return 30
      case 'hit': {
        const id = ++counter.current
        const mv = moveOf(e.side, e.slot, e.move)
        const { struct, kind, color, overlays } = fxForMove(mv, e.channel, e)
        setFx({ id, side: e.side, slot: e.slot, struct, kind, color, overlays, targetSide: e.targetSide, targetSlot: e.targetSlot, crit: e.crit })
        addFloat(e.targetSide, e.targetSlot, `-${e.dmg}`, 'dmg')
        if (e.warded > 0) addFloat(e.targetSide, e.targetSlot, `🛡 ${e.warded}`, 'info')
        if (e.lifesteal > 0) addFloat(e.side, e.slot, `+${e.lifesteal}`, 'heal')
        if (e.recoil > 0) addFloat(e.side, e.slot, `-${e.recoil}`, 'burn')
        if (e.manaBurn > 0) addFloat(e.targetSide, e.targetSlot, `-${e.manaBurn} MP`, 'mana')
        if (e.crit) addFloat(e.targetSide, e.targetSlot, '💥 CRIT', 'dmg')
        return e.crit || e.execute ? 950 : 800
      }
      case 'miss': {
        const id = ++counter.current
        const { struct, kind, color } = fxFor(e.channel)
        setFx({ id, side: e.side, slot: e.slot, struct, kind, color, targetSide: e.targetSide, targetSlot: e.targetSlot })
        addFloat(e.targetSide, e.targetSlot, e.blocked ? '🛡 blocked!' : 'miss', 'info')
        return 650
      }
      case 'stance':
        setFx({ id: ++counter.current, side: e.side, slot: e.slot, struct: 'stance' })
        addFloat(e.side, e.slot, '🛡', 'info')
        return 550
      case 'utility': {
        const mv = moveOf(e.side, e.slot, e.move)
        const bespoke = mv && BESPOKE_KIND[mv.name] // e.g. song buffs → floating notes
        if (bespoke) {
          setFx({ id: ++counter.current, side: e.side, slot: e.slot, struct: KIND_STRUCT[bespoke] ?? 'stance', kind: bespoke, color: CHANNEL_COLOR.support })
        } else {
          const { overlays } = utilityFx(mv)
          setFx({ id: ++counter.current, side: e.side, slot: e.slot, struct: 'stance', overlays: e.heal > 0 ? ['heal'] : overlays, targetSide: e.targetSide, targetSlot: e.targetSlot })
        }
        if (e.heal > 0) addFloat(e.targetSide, e.targetSlot, `+${e.heal}`, 'heal')
        else addFloat(e.side, e.slot, `✨ ${e.move}`, 'info')
        return 620
      }
      case 'status':
        // side is the OPPOSITE of the afflicted monster so targetX1v1() places
        // the puff over the afflicted one (targetX1v1 returns the DEFENDER's spot).
        setFx({ id: ++counter.current, side: e.side === 'A' ? 'B' : 'A', slot: e.slot, struct: 'burst', status: e.status })
        addFloat(e.side, e.slot, `${STATUS_ICON[e.status]} ${e.status}`, 'info')
        return 520
      case 'dot':
        addFloat(e.side, e.slot,
          e.status === 'burn' ? `-${e.amount} 🔥` : e.status === 'bleed' ? `-${e.amount} 🩸`
            : e.status === 'doom' ? `-${e.amount} 💀` : `-${e.amount} MP ☠️`,
          e.status === 'poison' ? 'mana' : 'burn')
        return 340
      case 'skip':
        addFloat(e.side, e.slot, e.reason === 'stun' ? '💤 stunned' : e.reason === 'sleep' ? '😴 asleep' : '😱 flees', 'info')
        return 550
      case 'end':
        setFx(null) // don't leave a frozen projectile/lunge on screen
        return 400
    }
  }

  const skip = () => {
    const lastSnap = [...events].reverse().find((e): e is Extract<BattleEvent, { kind: 'snap' }> => e.kind === 'snap')
    if (lastSnap) {
      setBars((prev) => {
        const next = { ...prev }
        for (const s of lastSnap.states) next[barKey(s.side, s.slot)] = { hp: s.hp, mana: s.mana, ward: s.ward, statuses: s.statuses }
        return next
      })
    }
    setFloats([])
    setFx(null)
    setCaption(result.winner === 'draw' ? '🏳️ Double knockout — a draw!' : `🏆 ${result.winnerName} wins!`)
    // fill the turn log with everything the replay would still have shown
    const rest = events.slice(idx).map(captionOf).filter((l): l is string => !!l)
    setHistory((h) => [...h, ...rest])
    setIdx(events.length)
  }

  const floatsFor = (side: BattleSide, slot: number) =>
    floats.filter((f) => f.side === side && f.slot === slot).map((f) => <span key={f.id} className={'float ' + f.cls}>{f.text}</span>)

  // Post-battle summary (2026-07-25 playtest addition): a compact per-monster
  // "why did it go that way" — damage dealt/taken, healing given, crits, KO —
  // aggregated straight from the event stream once the replay finishes.
  const summaryRows = useMemo(() => {
    interface Row { side: BattleSide; slot: number; name: string; dealt: number; taken: number; healed: number; crits: number; koed: boolean }
    const rows = new Map<string, Row>()
    const ensure = (side: BattleSide, slot: number): Row => {
      const k = side + slot
      if (!rows.has(k)) rows.set(k, { side, slot, name: (side === 'A' ? teamA : teamB)[slot]?.name ?? '?', dealt: 0, taken: 0, healed: 0, crits: 0, koed: false })
      return rows.get(k)!
    }
    for (const e of result.events) {
      if (e.kind === 'hit') {
        ensure(e.side, e.slot).dealt += e.dmg
        ensure(e.targetSide, e.targetSlot).taken += e.dmg
        if (e.crit) ensure(e.side, e.slot).crits++
      } else if (e.kind === 'dot' && e.status !== 'poison') { // poison drains MP, not HP
        ensure(e.side, e.slot).taken += e.amount
      } else if (e.kind === 'utility' && e.heal > 0) {
        ensure(e.side, e.slot).healed += e.heal
      }
    }
    for (const f of result.finals) if (f.wasKOd) ensure(f.side, f.slot).koed = true
    return [...rows.values()].sort((x, y) => (x.side === y.side ? x.slot - y.slot : x.side === 'A' ? -1 : 1))
  }, [result, teamA, teamB])

  // Causal report (LOOP_DESIGN Phase 4): "you won BECAUSE…" — turning point,
  // whether your orders fired, and what the opponent was running.
  const report = useMemo(() => analyzeBattle(result.events, teamA, teamB, result, playerSide), [result, teamA, teamB, playerSide])

  // Shared tail: the live turn log, plus (once the replay finishes) the battle
  // summary and the raw sim transcript — richer than the captions (buff
  // durations, resist notes).
  const logAndTranscript = (
    <>
      <div className="arena-log" ref={logRef}>
        {history.map((l, i) => (
          <div key={i} className={l.startsWith('— Round') ? 'rnd' : l.startsWith('🏆') || l.startsWith('🏳️') ? 'fin' : ''}>{l}</div>
        ))}
      </div>
      {done && (report.turningPoint || report.tacticOutcomes.length > 0 || report.keyMoments.length > 0) && (
        <div className="battle-report">
          <div className="section-title">📋 Battle report</div>
          {report.turningPoint && <div className="br-turn">{report.turningPoint}</div>}
          {report.counterRead && <div className="br-counter">🧠 {report.counterRead}</div>}
          {report.tacticOutcomes.map((o, i) => (
            <div key={i} className={'br-tactic ' + (o.ok ? 'ok' : 'no')}>{o.ok ? '✓' : '✗'} {o.text}</div>
          ))}
          {report.keyMoments.map((m, i) => <div key={i} className="br-moment">• {m}</div>)}
        </div>
      )}
      {done && (
        <div className="battle-summary">
          <div className="section-title">Battle summary</div>
          <table>
            <thead>
              <tr><th>Monster</th><th>Dealt</th><th>Taken</th><th>Healed</th><th>Crits</th><th></th></tr>
            </thead>
            <tbody>
              {summaryRows.map((r) => (
                <tr key={r.side + r.slot} className={r.side === 'A' ? 'sideA' : 'sideB'}>
                  <td>{r.side === 'A' ? '🟢' : '🔴'} {r.name}</td>
                  <td>{Math.round(r.dealt)}</td>
                  <td>{Math.round(r.taken)}</td>
                  <td>{r.healed > 0 ? Math.round(r.healed) : '–'}</td>
                  <td>{r.crits > 0 ? r.crits : '–'}</td>
                  <td>{r.koed ? '💀 KO' : ''}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {done && (
        <details className="arena-transcript">
          <summary className="dim">📜 full battle transcript</summary>
          <div className="log">
            {result.log.map((line, i) => (
              <div key={i} className={line.startsWith('🏆') || line.startsWith('🏳️') ? 'win' : ''}>{line}</div>
            ))}
          </div>
        </details>
      )}
    </>
  )

  // ---------- 1v1: original lunge/projectile choreography, unchanged ----------
  if (is1v1) {
    const a = teamA[0], b = teamB[0]
    const aMax = { hp: maxHp(a.stats), mana: maxMana(a.stats) }
    const bMax = { hp: maxHp(b.stats), mana: maxMana(b.stats) }
    const aBar = bars[barKey('A', 0)], bBar = bars[barKey('B', 0)]

    const fighterCls = (side: BattleSide) => {
      let cls = 'combatant ' + (side === 'A' ? 'left' : 'right')
      if (fx && fx.side === side && fx.slot === 0) {
        if (fx.struct === 'lunge') cls += side === 'A' ? ' lungeA' : ' lungeB'
        if (fx.struct === 'stance') cls += ' stancePulse'
      }
      return cls
    }
    const ko = (side: BattleSide) => (done && ((side === 'A' && result.winner === 'B') || (side === 'B' && result.winner === 'A')) ? ' ko' : '')

    return (
      <div className="battle-arena">
        <div className="arena-hud">
          <div className="arena-fighter-hud">
            <div className="ahn">{a.name} <span className="dim">· {a.species.name} · {a.className}</span></div>
            <div className="abar hp"><i style={{ width: `${(aBar.hp / aMax.hp) * 100}%` }} /><span>{aBar.hp}/{aMax.hp}</span></div>
            <div className="abar mp"><i style={{ width: `${aMax.mana > 0 ? (aBar.mana / aMax.mana) * 100 : 0}%` }} /><span>{aBar.mana} MP</span></div>
            <div className="ahud-row">
              {aBar.ward > 0 && <div className="award">🛡 shield {aBar.ward}</div>}
              <StatusIcons statuses={aBar.statuses} />
            </div>
          </div>
          <div className="arena-round">{done ? (result.winner === 'draw' ? '🏳️ Draw' : `🏆 ${result.winnerName}`) : round > 0 ? `Round ${round}` : '⚔️'}</div>
          <div className="arena-fighter-hud right">
            <div className="ahn">{b.name} <span className="dim">· {b.species.name} · {b.className}</span></div>
            <div className="abar hp"><i style={{ width: `${(bBar.hp / bMax.hp) * 100}%` }} /><span>{bBar.hp}/{bMax.hp}</span></div>
            <div className="abar mp"><i style={{ width: `${bMax.mana > 0 ? (bBar.mana / bMax.mana) * 100 : 0}%` }} /><span>{bBar.mana} MP</span></div>
            <div className="ahud-row right">
              {bBar.ward > 0 && <div className="award">🛡 shield {bBar.ward}</div>}
              <StatusIcons statuses={bBar.statuses} />
            </div>
          </div>
        </div>

        <div className={'arena-floor' + (fx?.crit ? ' shake' : '')} style={{ backgroundImage: `url(${bgImage})` }}>
          <div className="arena-floor-scrim" />
          <div className={fighterCls('A') + ko('A')}>
            <Sprite species={a.species} size={176} bare />
            <div className="floats">{floatsFor('A', 0)}</div>
          </div>
          {fx && <MoveFx fx={fx} />}
          <div className={fighterCls('B') + ko('B')}>
            <span className="mirror"><Sprite species={b.species} size={176} bare /></span>
            <div className="floats">{floatsFor('B', 0)}</div>
          </div>
          {done && (
            <div className="winner-banner">
              {result.winner === 'draw' ? <>🏳️ Double knockout — a draw!</> : <>🏆 <b>{result.winnerName}</b> wins!</>}
            </div>
          )}
        </div>

        <div className="arena-controls">
          {!done && (
            <>
              {[1, 2, 4].map((s) => (
                <button key={s} className={'ghost' + (speed === s ? ' selected' : '')} onClick={() => setSpeed(s)}>{s}×</button>
              ))}
              <button className="ghost" onClick={skip}>Skip ⏭</button>
            </>
          )}
          <span className="arena-caption">{caption}</span>
        </div>

        {logAndTranscript}
      </div>
    )
  }

  // ---------- Team battles: a 2D battlefield ----------
  // Presentation ONLY. Every position here is DERIVED from the resolved event
  // stream and the engine's own formation rule — nothing on this field feeds
  // back into the sim, so the goldens cannot move. The rule to keep: never
  // invent a spatial fact the engine does not share (e.g. never walk a melee
  // attacker past the front line — the engine walls it there).

  // The field is measured, and posts are emitted in PIXELS. Percentages are a
  // trap here: a % inside `transform` resolves against the element's own box,
  // not the field. Measuring once and doing the arithmetic in JS keeps the
  // geometry unambiguous and the motion on `transform` (GPU-composited).
  const fieldRef = useRef<HTMLDivElement>(null)
  const [fieldBox, setFieldBox] = useState({ w: 0, h: 0 })
  useEffect(() => {
    const el = fieldRef.current
    if (!el) return
    const measure = () => setFieldBox({ w: el.clientWidth, h: el.clientHeight })
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  // Who is still standing, per side. Drives BOTH the live formation and the
  // idle behaviour, so it is computed once per render.
  const livingSlots = (side: BattleSide) =>
    teamOf(side).map((_, i) => i).filter((i) => (bars[barKey(side, i)]?.hp ?? 1) > 0)

  // A slot's post on the field, in % of the field box.
  // ⚠️ Mirrors the ENGINE's `formationRank`: a monster's row is its index among
  // still-LIVING teammates. So when a front-liner drops, the one behind is
  // promoted by the engine and here literally WALKS FORWARD into the gap — the
  // animation is a real mechanic surfacing, not decoration.
  const fieldPos = (side: BattleSide, slot: number): { x: number; y: number } =>
    fieldPostFor(side, slot, livingSlots(side), teamOf(side).length)

  // Personality, read off the SAME Tactics the engine's AI actually uses — so
  // how a monster carries itself on the field is an honest tell, not flavour.
  const postureOf = (side: BattleSide, slot: number): string => {
    const t = teamOf(side)[slot]?.tactics
    const bar = bars[barKey(side, slot)]
    const hurt = bar && bar.hp > 0 && bar.hp / maxHp(teamOf(side)[slot].stats) < 0.35
    const bits: string[] = []
    // temperament drives the resting stance: aggressive crowds the line,
    // defensive gives ground, balanced holds.
    bits.push('temper-' + (t?.temperament ?? 'balanced'))
    // 'preserve' below its threshold means the AI is genuinely playing to
    // survive — show it backing off rather than only saying so in the log.
    if (hurt && t?.preserve && t.preserve !== 'off') bits.push('guarding')
    if (hurt) bits.push('hurt')
    if (bar?.statuses.includes('haste')) bits.push('hasted')
    if (bar?.statuses.some((s) => s === 'fear' || s === 'confusion')) bits.push('shaken')
    if (bar?.statuses.some((s) => s === 'stun' || s === 'sleep')) bits.push('downed')
    return bits.join(' ')
  }

  const renderTile = (side: BattleSide, slot: number) => {
    const m = teamOf(side)[slot]
    const bar = bars[barKey(side, slot)]
    const hpMax = maxHp(m.stats)
    const mpMax = maxMana(m.stats)
    const koed = bar.hp <= 0
    const acting = fx && fx.side === side && fx.slot === slot
    const impacted = fx && fx.targetSide === side && fx.targetSlot === slot
    let cls = 'roster-tile'
    if (koed) cls += ' ko'
    if (acting) cls += ` acting acting-${fx!.kind ?? fx!.struct}`
    if (impacted) cls += ` impact impact-${fx!.kind ?? fx!.struct}`
    // Buff/aura glow: every 'stance' fx (buffs, wards, songs, the free Guard)
    // lights up the monster it lands on — the self-buffer (acting) and any
    // targeted ally (impacted) — so no buff plays without a visible tell.
    const buffed = (acting || impacted) && fx!.struct === 'stance'
    if (buffed) cls += ' buffed'
    // a move's colour rides along as a CSS custom property so acting/impact
    // don't need a hand-written rule per kind just to pick up the right tint
    const fxStyle: Record<string, string> = buffed
      ? { '--glow-color': buffGlowColor(fx!.overlays) }
      : ((acting || impacted) && fx?.color ? { '--fx-color': fx.color } : {})

    // --- Where this monster stands right now ---
    const home = fieldPos(side, slot)
    let { x, y } = home
    // MELEE CLOSES THE DISTANCE. On a 'lunge' fx the attacker travels to just
    // short of its target and back; the CSS transition does the interpolation,
    // so the walk is free. Ranged/magic ('proj') hold their post and throw.
    if (acting && fx!.struct === 'lunge' && fx!.targetSide && fx!.targetSlot !== undefined) {
      const t = fieldPos(fx!.targetSide, fx!.targetSlot)
      x = t.x + (side === 'A' ? -8 : 8) // stop at arm's length, never overlap
      y = t.y
    }
    if (!koed) cls += ' ' + postureOf(side, slot)
    // Side A looks right, side B looks left; an attacker mid-lunge keeps facing
    // the way it is travelling.
    const facing = side === 'A' ? 1 : -1
    // ⚠️ The transform is written out in full here rather than assembled from
    // custom properties in CSS. `var()` inside translate3d() did NOT resolve in
    // testing (the tile silently stayed at 0,0 while the variable read back
    // correctly) — a whole debugging session was lost to it. An explicit string
    // has no indirection to go wrong, and the transition still comes from CSS.
    const px = ((x / 100) * fieldBox.w).toFixed(1)
    const py = ((y / 100) * fieldBox.h).toFixed(1)
    Object.assign(fxStyle, {
      transform: `translate3d(${px}px, ${py}px, 0) translate(-50%, -50%)`,
      '--face': String(facing),
    })

    return (
      <div className={cls} key={slot} title={m.name} style={fxStyle}>
        <div className="rt-body"><Sprite species={m.species} size={60} bare /></div>
        <div className="rt-name">{m.name}</div>
        <div className="rt-class dim">{m.className}</div>
        <div className="rt-bar hp"><i style={{ width: `${Math.max(0, (bar.hp / hpMax) * 100)}%` }} /></div>
        <div className="rt-bar mp"><i style={{ width: `${mpMax > 0 ? Math.max(0, (bar.mana / mpMax) * 100) : 0}%` }} /></div>
        {bar.ward > 0 && <div className="rt-ward">🛡{bar.ward}</div>}
        <StatusIcons statuses={bar.statuses} />
        <div className="floats">{floatsFor(side, slot)}</div>
      </div>
    )
  }

  return (
    <div className="battle-arena team-mode">
      <div className="arena-hud">
        <div className="arena-round">{done ? (result.winner === 'draw' ? '🏳️ Draw' : `🏆 ${result.winnerName}`) : round > 0 ? `Round ${round}` : '⚔️'}</div>
      </div>

      <div className={'arena-floor team-floor'} style={{ backgroundImage: `url(${bgImage})` }}>
        <div className="arena-floor-scrim" />
        {/* THE FIELD. Every combatant is absolutely placed from fieldPos, which
            reads the engine's own living-formation rule — so the front line, the
            promotion when someone drops, and who a melee attacker can reach all
            match the sim exactly. */}
        <div className="battlefield" ref={fieldRef}>
          {teamA.map((_, i) => renderTile('A', i))}
          {teamB.map((_, i) => renderTile('B', i))}
          {/* A ranged/magic cast throws a real projectile across the lane,
              travelling from the caster's post to the target's. */}
          {fx && fx.struct === 'proj' && fx.targetSide && fx.targetSlot !== undefined && (() => {
            const from = fieldPos(fx.side, fx.slot)
            const to = fieldPos(fx.targetSide, fx.targetSlot)
            return (
              <span
                key={fx.id}
                className={'field-shot shot-' + (fx.kind ?? 'proj')}
                style={{
                  '--fx-color': fx.color ?? '#fff',
                  '--x0': ((from.x / 100) * fieldBox.w).toFixed(1) + 'px',
                  '--y0': ((from.y / 100) * fieldBox.h).toFixed(1) + 'px',
                  '--x1': ((to.x / 100) * fieldBox.w).toFixed(1) + 'px',
                  '--y1': ((to.y / 100) * fieldBox.h).toFixed(1) + 'px',
                } as Record<string, string>}
              />
            )
          })()}
        </div>
        {done && (
          <div className="winner-banner">
            {result.winner === 'draw' ? <>🏳️ Double knockout — a draw!</> : <>🏆 <b>{result.winnerName}</b> wins!</>}
          </div>
        )}
      </div>

      <div className="arena-controls">
        {!done && (
          <>
            {[1, 2, 4].map((s) => (
              <button key={s} className={'ghost' + (speed === s ? ' selected' : '')} onClick={() => setSpeed(s)}>{s}×</button>
            ))}
            <button className="ghost" onClick={skip}>Skip ⏭</button>
          </>
        )}
        <span className="arena-caption">{caption}</span>
      </div>

      {logAndTranscript}
    </div>
  )
}
