// ─────────────────────────────────────────────────────────────────────────────
// TACTICS PANEL (tamerengine Step 1) — pre-battle orders on the deploy screen.
//
// A COMPACT, standalone editor for the Tactics fields the FIELD engine actually
// reads (src/tamerengine/decide.ts): temperament (gates how much the spatial
// orders land), target priority, formation, commit, cover, survival.
// Deliberately NOT the turn-engine's full TacticsControls (openers / combo / mana
// / cc) — those are turn-based concepts the field decider ignores, so exposing
// them here would be controls that do nothing.
//
// Kept inside tamerengine (not imported from App.tsx) so the engine stays a
// standalone module — it only borrows the option TABLES from core.ts, which are
// engine-agnostic data.
import { Tactics, TEMPERAMENT_INFO, TARGET_PRIORITY_INFO, PRESERVE_INFO } from '../core'
import './deploy.css'

// Spatial orders have no INFO table in core (they're plain unions) — author the
// display options here. `undefined` = "Auto" (the archetype decides), so the
// player only overrides what they mean to.
type Opt<T> = { id: T; icon: string; name: string }
// ⚠️ ONE control, three choices — not a formation toggle plus a nested spacing
// row. `keep` holds the slot the player DREW on the deploy screen, so its density
// is already chosen there; only the two no-slot options have a density left to
// pick. A nested control would have offered a second answer to a settled question.
const FORMATION: Opt<Tactics['formation']>[] = [
  { id: undefined, icon: '◦', name: 'Auto' },
  { id: 'keep', icon: '▦', name: 'Keep' },
  { id: 'spread', icon: '↔', name: 'Spread' },
  { id: 'tight', icon: '⊚', name: 'Tight' },
]
const COMMIT: Opt<Tactics['commit']>[] = [
  { id: undefined, icon: '◦', name: 'Auto' },
  { id: 'dive', icon: '⚡', name: 'Dive' },
  { id: 'hold', icon: '🛑', name: 'Hold line' },
]
// ⚠️ NO 'default' ENTRY. Every other order here can be left unset; a heal policy
// cannot, because "unset" silently means triage and the player would have no way
// to see which one is running. Both states are explicit and pickable.
const HEALS: Opt<'steady' | 'triage'>[] = [
  { id: 'triage', icon: '🚑', name: 'Save for low HP' },
  { id: 'steady', icon: '💧', name: 'Heal freely' },
]
const COVER: Opt<boolean | undefined>[] = [
  { id: undefined, icon: '◦', name: 'Ignore' },
  { id: true, icon: '🧱', name: 'Use cover' },
]

function Row<T>({ label, opts, cur, onPick }: {
  label: string; opts: Opt<T>[]; cur: T; onPick: (v: T) => void
}) {
  return (
    <div className="tac-row">
      <span className="tac-label">{label}</span>
      <div className="tac-opts">
        {opts.map((o, i) => (
          <button key={i} type="button"
            className={'tac-opt' + (cur === o.id ? ' on' : '')}
            onClick={() => onPick(o.id)}>{o.icon} {o.name}</button>
        ))}
      </div>
    </div>
  )
}

export function TacticsPanel({ name, value, onChange }: {
  name: string; value: Tactics; onChange: (t: Tactics) => void
}) {
  const set = (patch: Partial<Tactics>) => onChange({ ...value, ...patch })
  return (
    <div className="tac-panel">
      <div className="tac-head">Orders — <b>{name}</b></div>
      <Row label="Temperament" cur={value.temperament}
        opts={TEMPERAMENT_INFO.map((o) => ({ id: o.id, icon: o.icon, name: o.name }))}
        onPick={(v) => set({ temperament: v })} />
      <Row label="Target" cur={value.targetPriority}
        opts={TARGET_PRIORITY_INFO.map((o) => ({ id: o.id, icon: o.icon, name: o.name }))}
        onPick={(v) => set({ targetPriority: v })} />
      <Row label="Formation" cur={value.formation} opts={FORMATION} onPick={(v) => set({ formation: v })} />
      <Row label="Commit" cur={value.commit} opts={COMMIT} onPick={(v) => set({ commit: v })} />
      <Row label="Cover" cur={value.useCover} opts={COVER} onPick={(v) => set({ useCover: v || undefined })} />
      <Row label="Healing" cur={value.healPolicy ?? 'triage'} opts={HEALS}
        onPick={(v) => set({ healPolicy: v })} />
      <Row label="Survival" cur={value.preserve ?? 'off'}
        opts={PRESERVE_INFO.map((o) => ({ id: o.id, icon: o.icon, name: o.name }))}
        onPick={(v) => set({ preserve: v })} />
    </div>
  )
}
