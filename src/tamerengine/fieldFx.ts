// ─────────────────────────────────────────────────────────────────────────────
// FIELD FX (tamerengine M4) — every ability's visual identity, as DATA.
//
// Ported from the 1v1 arena's animation vocabulary (`arena.tsx` BESPOKE_KIND +
// fxFor) so a move looks like what it IS on the field too — a claw rake, a
// thrown fireball, a piercing beam, an overhead slam — not a generic dot. The
// arena renders these as bespoke SVG/DOM; the field renders them on a canvas
// overlay (see TamerArena), but the CLASSIFICATION is the same table, kept here
// engine-agnostic so both could share it if the two renderers ever converge.
//
// The point (user requirement): "all the abilities used by monsters will have
// animations so the player can clearly see what is happening."
import { Channel, StatusKind } from '../core'

/** How the effect is delivered from caster to target. */
export type FxStruct = 'lunge' | 'proj' | 'burst' | 'stance'

/** The effect's shape/identity — picks how the canvas draws it. */
export type FxKind =
  | 'claw' | 'arrow' | 'beam' | 'fireball' | 'waterbolt' | 'earthspike' | 'lightning'
  | 'sonic' | 'psychic' | 'arcane'
  | 'slam' | 'guillotine' | 'flurry' | 'volley' | 'chain' | 'cage' | 'firewall' | 'notes'
  | 'heal' | 'buff'

/** Kinds that TRAVEL from caster to target (drawn as a moving projectile);
 *  everything else appears at the target as a burst. */
export const TRAVELS = new Set<FxKind>(['arrow', 'beam', 'fireball', 'waterbolt', 'arcane'])

export interface MoveFx { struct: FxStruct; kind: FxKind; color: string }

const CHANNEL_COLOR: Record<Channel, string> = {
  melee: '#f0f0f0', ranged: '#ffd54f', magic: '#ba68c8', voice: '#f48fb1', support: '#80cbc4',
}

// Bespoke base motion per move NAME — the moves that earn a signature. Ported
// verbatim from arena.tsx so the two renderers agree.
const BESPOKE_KIND: Record<string, FxKind> = {
  'Power Strike': 'slam', 'Reckless Slam': 'slam', 'Titanfall': 'slam', 'Shell Slam': 'slam',
  'Body Slam': 'slam', 'Colossus Crash': 'slam', 'Earthshaker': 'slam', 'World Ender': 'slam',
  'Executioner': 'guillotine', 'Showstopper': 'guillotine',
  'Flurry of Blows': 'flurry', 'Bloodletter': 'flurry', 'Twin Fangs': 'flurry', 'Shadow Barrage': 'flurry',
  'Snipe': 'beam', 'Deadeye': 'beam', 'Pin Down': 'beam', 'Stone Spear': 'beam', 'Void Lance': 'beam',
  'Rain of Arrows': 'volley', 'Needle Storm': 'volley',
  'Static Chain': 'chain',
  'Glacial Prison': 'cage', 'Deep Freeze': 'cage',
  'Inferno': 'firewall',
  'Rallying Song': 'notes', 'Battle Hymn': 'notes', 'Standing Ovation': 'notes',
  'Lullaby': 'notes', 'Crescendo': 'notes',
} as unknown as Record<string, FxKind>

const KIND_STRUCT: Partial<Record<FxKind, FxStruct>> = {
  slam: 'lunge', guillotine: 'burst', flurry: 'lunge', beam: 'burst', volley: 'burst',
  chain: 'burst', cage: 'burst', firewall: 'burst', notes: 'stance',
}

/**
 * Base motion from the CHANNEL.
 * ⚠️ ELEMENTS REMOVED — this used to branch on fire/water/earth/air first, since
 * an element was the more specific identity. With elements gone the channel is
 * the only delivery signal, and it is the one that actually maps to how the move
 * behaves (a lunge, a bolt, a shout).
 */
function baseFx(channel: Channel): MoveFx {
  if (channel === 'melee') return { struct: 'lunge', kind: 'claw', color: CHANNEL_COLOR.melee }
  if (channel === 'ranged') return { struct: 'proj', kind: 'arrow', color: CHANNEL_COLOR.ranged }
  if (channel === 'voice') return { struct: 'burst', kind: 'sonic', color: CHANNEL_COLOR.voice }
  if (channel === 'support') return { struct: 'burst', kind: 'psychic', color: CHANNEL_COLOR.support }
  return { struct: 'proj', kind: 'arcane', color: CHANNEL_COLOR.magic }
}

/** The full visual for a move: its bespoke signature if it has one, else the base. */
export function moveFx(moveName: string | undefined, channel: Channel): MoveFx {
  const base = baseFx(channel)
  const bespoke = moveName ? BESPOKE_KIND[moveName] : undefined
  if (!bespoke) return base
  return { struct: KIND_STRUCT[bespoke] ?? base.struct, kind: bespoke, color: base.color }
}

/** The heal visual — support casts with power land a green mend on an ally. */
export const HEAL_FX: MoveFx = { struct: 'burst', kind: 'heal', color: '#7dffab' }
/** The generic self/team buff glow. */
export const BUFF_FX: MoveFx = { struct: 'stance', kind: 'buff', color: '#ffd54f' }

// ── Status / buff / debuff icons ─────────────────────────────────────────────
// The emoji the two HUD rows draw, keyed by the snapshot `buffs`/`debuffs`
// entries (status kinds + the mod keys atkUp/atkDown/defUp).
export const EFFECT_ICON: Record<string, string> = {
  // statuses (ported from arena.tsx STATUS_ICON)
  blind: '🕶️', poison: '☠️', burn: '🔥', fear: '😱', confusion: '💫', stun: '💤', knockback: '💨',
  bleed: '🩸', silence: '🤐', vulnerable: '🎯', sleep: '😴', doom: '💀', healblock: '🚫', haste: '⚡', charm: '💞',
  // mods
  atkUp: '🗡️', atkDown: '🡇', defUp: '🛡️',
}
export const effectIcon = (key: string): string => EFFECT_ICON[key] ?? '•'

// Re-export the status-kind icon for callers that want it typed.
export const statusIcon = (k: StatusKind): string => EFFECT_ICON[k] ?? '•'
