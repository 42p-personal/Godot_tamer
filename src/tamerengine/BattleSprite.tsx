// ─────────────────────────────────────────────────────────────────────────────
// BATTLE SPRITE (v0.93) — a monster that MOVES, built from the art we have.
//
// The plan was 6 hand-generated frames per species (docs/BATTLE_SPRITES.md).
// Both image-generation routes have been returning hard failures since
// 2026-07-27 (API billing cap; codex image service 403), so that set does not
// exist and cannot be made today. See docs/ART_PIPELINE.md.
//
// So there are TWO ways here to get a moving monster without one, and this
// file picks between them on a `mode` prop:
//
//   'portrait' — animate the existing 320px painting as one piece. Squash,
//                stretch, lean and recoil read as weight, and it needs no new
//                art at all. But a painting has no separable arms, so nothing
//                can ever actually swing.
//   'pixel'    — build the creature from PARTS at 48px and rotate the joints
//                (`pixelRig.ts`). Arms swing, legs stride, tails lag. This is
//                the one that answers "sprites with moving arms".
//
// ⚠️ Both are SUBSTITUTES, not replacements. When generation unblocks, real
// frames drop into `frameFor()` and every caller keeps working — the state
// machine, the facing and the layout do not change. Nothing else in the
// codebase needs to know which of the three is live.
//
// ⚠️ TRANSFORM COMPOSITION. Three nested elements, each owning exactly one job:
//   .bs        position on the field   (translate — set by the caller)
//   .bs-face   which way it looks      (scaleX ±1)
//   .bs-anim   what it is doing        (the keyframes)
// Collapsing these fights: a keyframe that sets `transform` wipes the facing
// flip, and the sprite silently snaps to facing right mid-animation.
import { useEffect, useRef, useState } from 'react'
import { UnitVisState } from './types'
import { FRAME, FRAMES_PER_ANIM, RIG_ANIMS, RigAnim, sheetUrl } from './pixelRig'

/** What the sprite is doing. Extends the engine's states with combat beats the
 *  event stream can drive but the tick snapshot does not carry. */
export type SpriteAction = UnitVisState | 'hurt' | 'attack'

/**
 * Which art the sprite is built from.
 *
 * `portrait` animates the existing 320px painting as ONE piece — it reads as
 * weight, but a painting has no separable arms, so nothing can ever swing.
 * `pixel` draws the creature from parts at 48px and rotates the joints, so arms
 * genuinely swing and legs genuinely stride. See `pixelRig.ts`.
 */
export type SpriteMode = 'portrait' | 'pixel' | 'sheet'

/**
 * Species that have a real generated battle-frame set in `public/battle/`
 * (idle · walk1-4 · strike), matched to their portrait. As more groups are
 * generated, add their ids here — `frameFor` and the renderer key off this set,
 * so a species without frames automatically falls back to the portrait path
 * and nothing else needs to change.
 */
export const BATTLE_SPRITE_SET = new Set<string>([
  'kongrath', 'aegisox', 'maneleo', 'grivvel', 'ursath', // Mammal
])

/** The four contact/pass frames a `move` cycles through. */
const WALK_CYCLE = ['walk1', 'walk2', 'walk3', 'walk4'] as const

/** Which battle frame a given action shows (before any walk-cycling). */
function battleFrameName(action: SpriteAction): string {
  switch (action) {
    case 'move': return 'walk1'      // cycled by the renderer
    case 'attack':
    case 'cast': return 'strike'
    default: return 'idle'           // idle · hurt · dead all base on idle
  }
}

export interface BattleSpriteProps {
  /** Species id — resolves to `public/sprites/<id>.png`. */
  speciesId: string
  action: SpriteAction
  /** 1 faces right, -1 faces left. Matches `FieldEvent` snapshot `facing`. */
  facing: 1 | -1
  /** Rendered height in px. Width follows the source's square aspect. */
  size?: number
  /** Position within a field container, in px. Omit to lay out normally. */
  x?: number
  y?: number
  /** 0–1. Tints toward grey as it drops, so a nearly-dead unit reads at a glance
   *  without needing its bar. */
  hpFrac?: number
  label?: string
  mode?: SpriteMode
}

/**
 * The art URL for one action of one species.
 *
 * A species WITH a generated battle set serves its real `<id>-<frame>.png`; one
 * WITHOUT falls back to the single portrait (animated by CSS in `portrait`
 * mode). This is the seam the whole system turns on — nothing above it needs to
 * know which species have frames yet.
 */
export function frameFor(speciesId: string, action: SpriteAction): string {
  if (BATTLE_SPRITE_SET.has(speciesId)) {
    return `/battle/${speciesId}-${battleFrameName(action)}.png`
  }
  return `/sprites/${speciesId}.png`
}

export function BattleSprite({
  speciesId, action, facing, size = 96, x, y, hpFrac = 1, label, mode = 'portrait',
}: BattleSpriteProps) {
  const positioned = x !== undefined && y !== undefined
  // A species with a real battle-frame set plays those, unless the caller has
  // deliberately forced a different mode. This is what makes the generated
  // pixel art the default the moment its frames exist.
  if (mode === 'sheet' || (mode === 'portrait' && BATTLE_SPRITE_SET.has(speciesId))) {
    return (
      <SheetSprite
        speciesId={speciesId} action={action} facing={facing} size={size}
        x={x} y={y} hpFrac={hpFrac} label={label}
      />
    )
  }
  if (mode === 'pixel') {
    return (
      <PixelSprite
        speciesId={speciesId} action={action} facing={facing} size={size}
        x={x} y={y} hpFrac={hpFrac} label={label}
      />
    )
  }
  return (
    <div
      className={`bs${positioned ? ' bs-abs' : ''}`}
      style={{
        width: size, height: size,
        ...(positioned ? { transform: `translate3d(${x - size / 2}px, ${y - size}px, 0)` } : null),
      }}
      title={label}
    >
      {/* A contact shadow does more for "standing on ground" than any amount of
          sprite detail — without it a floating cutout never sits in the scene. */}
      <div className="bs-shadow" />
      <div className="bs-face" style={{ transform: `scaleX(${facing})` }}>
        <div className={`bs-anim bs-${action}`}>
          <img
            src={frameFor(speciesId, action)}
            alt={label ?? speciesId}
            draggable={false}
            style={{
              // Wounded monsters desaturate rather than turning red — a red
              // tint reads as "on fire", which is a status we actually have.
              filter: hpFrac < 1 ? `saturate(${0.35 + hpFrac * 0.65})` : undefined,
            }}
          />
        </div>
      </div>
    </div>
  )
}

/**
 * The rigged sprite: one generated sheet, stepped by a CSS `steps()` animation
 * on `background-position`.
 *
 * ⚠️ `steps()` ON BACKGROUND-POSITION, NOT A PER-FRAME TIMER. A JS interval per
 * sprite would mean a dozen timers all re-rendering React on their own
 * schedule; this hands the whole thing to the compositor and costs nothing.
 *
 * ⚠️ And `image-rendering: pixelated` is not decoration. Without it the browser
 * smooths a 48px sheet up to display size and every hard-won pixel edge turns
 * to mush — the exact thing `quantise()` exists to produce.
 */
function PixelSprite({
  speciesId, action, facing, size, x, y, hpFrac = 1, label,
}: Omit<BattleSpriteProps, 'mode'> & { size: number }) {
  // The engine's states map 1:1 onto rig rows; the extra beats fall back.
  const anim: RigAnim = (RIG_ANIMS as string[]).includes(action)
    ? (action as RigAnim)
    : action === 'hurt' ? 'hurt' : 'idle'
  const row = RIG_ANIMS.indexOf(anim)
  const positioned = x !== undefined && y !== undefined
  // One-shot clips must not loop, or a corpse stands back up.
  const once = anim === 'attack' || anim === 'hurt' || anim === 'dead'
  const dur = anim === 'move' ? 0.5 : anim === 'idle' ? 2.4 : anim === 'dead' ? 0.8 : 0.42

  return (
    <div
      className={`bs${positioned ? ' bs-abs' : ''}`}
      style={{
        width: size, height: size,
        ...(positioned ? { transform: `translate3d(${x! - size / 2}px, ${y! - size}px, 0)` } : null),
      }}
      title={label}
    >
      <div className="bs-shadow" />
      <div className="bs-face" style={{ transform: `scaleX(${facing})` }}>
        <div
          className="bs-px"
          style={{
            backgroundImage: `url(${sheetUrl(speciesId)})`,
            backgroundSize: `${FRAMES_PER_ANIM * 100}% ${RIG_ANIMS.length * 100}%`,
            backgroundPositionY: `${(row / (RIG_ANIMS.length - 1)) * 100}%`,
            animation: `bs-steps ${dur}s steps(${FRAMES_PER_ANIM}) ${once ? '1 forwards' : 'infinite'}`,
            filter: hpFrac < 1 ? `saturate(${0.35 + hpFrac * 0.65})` : undefined,
            // See the keyframe: the end stop must be 100 × N/(N−1), not 100%.
            ['--bs-end' as string]: `${(100 * FRAMES_PER_ANIM) / (FRAMES_PER_ANIM - 1)}%`,
          }}
          // Re-keying on the action remounts the node, which is what restarts a
          // one-shot clip — without it a second hit landing during the first
          // would silently not replay.
          key={`${anim}-${speciesId}`}
          aria-label={label ?? speciesId}
          role="img"
        />
      </div>
    </div>
  )
}

export { FRAME as PIXEL_FRAME }

/**
 * The generated pixel-art battle sprite: plays the real `public/battle` frames.
 *
 * A `move` cycles the four walk frames; everything else is a single frame
 * (`idle`, or `strike` for an attack/cast). One `requestAnimationFrame` loop
 * advances the walk index and swaps the `<img src>` — the frames are ~2KB each
 * and the browser caches them after first paint, so this is just an attribute
 * change per step, not a re-render of anything expensive.
 *
 * ⚠️ `image-rendering: pixelated`, like the rig, so the 128px art scales up with
 * hard edges instead of being smoothed to mush.
 */
function SheetSprite({
  speciesId, action, facing, size, x, y, hpFrac = 1, label,
}: Omit<BattleSpriteProps, 'mode'> & { size: number }) {
  const [walkIx, setWalkIx] = useState(0)
  const raf = useRef(0)
  const acc = useRef(0)
  const last = useRef(0)

  const cycling = action === 'move'
  useEffect(() => {
    if (!cycling) return
    // ~11 fps: two footfalls over ~0.36s reads as a walk without strobing.
    const step = (t: number) => {
      if (!last.current) last.current = t
      acc.current += (t - last.current) / 1000
      last.current = t
      if (acc.current >= 0.09) {
        acc.current = 0
        setWalkIx((i) => (i + 1) % WALK_CYCLE.length)
      }
      raf.current = requestAnimationFrame(step)
    }
    raf.current = requestAnimationFrame(step)
    return () => { cancelAnimationFrame(raf.current); last.current = 0 }
  }, [cycling, speciesId])

  const frame = cycling ? WALK_CYCLE[walkIx] : battleFrameName(action)
  const src = `/battle/${speciesId}-${frame}.png`
  const positioned = x !== undefined && y !== undefined

  // hurt flashes brighter, dead topples and fades — both over the idle frame,
  // matching the portrait path's tells so the two renderers read the same.
  const extra =
    action === 'dead' ? 'bs-dead'
    : action === 'hurt' ? 'bs-hurt'
    : ''

  return (
    <div
      className={`bs${positioned ? ' bs-abs' : ''}`}
      style={{
        width: size, height: size,
        ...(positioned ? { transform: `translate3d(${x! - size / 2}px, ${y! - size}px, 0)` } : null),
      }}
      title={label}
    >
      <div className="bs-shadow" />
      <div className="bs-face" style={{ transform: `scaleX(${facing})` }}>
        <div className={`bs-anim ${extra}`}>
          <img
            className="bs-px-img"
            src={src}
            alt={label ?? speciesId}
            draggable={false}
            style={{
              width: '100%', height: '100%',
              objectFit: 'contain', objectPosition: '50% 100%',
              filter: hpFrac < 1 ? `saturate(${0.35 + hpFrac * 0.65})` : undefined,
            }}
          />
        </div>
      </div>
    </div>
  )
}
