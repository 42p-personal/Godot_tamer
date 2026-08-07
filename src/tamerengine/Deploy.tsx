// ─────────────────────────────────────────────────────────────────────────────
// DEPLOY (tamerengine) — the pre-battle PLANNING phase.
//
// One screen that commits BOTH the formation and the orders before the fight, so
// the player's plan drives the battle (the M5/Step-1 requirement that pre-battle
// tactics "greatly drive behaviour"):
//   • drop each monster onto a hex in your zone (one per hex, so a formation can
//     never start stacked); the enemy auto-deploys on its own hexes by role.
//   • the SELECTED monster's orders show in a TacticsPanel below the field — the
//     same Tactics the field decider reads, so they genuinely bite.
//   • FIGHT fades the hex grid out and hands (placement + tactics) to the sim;
//     the hexes exist only for deployment, gone once the fight begins.
//
// ⚠️ SPRITES RENDER IN THEIR OWN UN-CLIPPED LAYER, not inside the hex divs. A
// clip-path hexagon clips its CHILDREN, so a sprite nested in the hex was cut to
// the hex shape. The hex slot markers are drawn small (well inside the cell
// spacing) so they never overlap.
//
// Static UI, so plain React state is fine here (unlike the animated TamerArena).
import { useLayoutEffect, useRef, useState } from 'react'
import { FIELD_H, FIELD_W, Vec2 } from './types'
import { FieldHexCell, fieldHexCells, fieldHexCoverage, hexTile } from './hex'
import { CAM_TILT_DEG, CAM_DEPTH, CAM_FIT, CAM_HEIGHT_RATIO, CAM_Y_OFFSET } from './camera'
import { BATTLE_SPRITE_SET } from './BattleSprite'
import { TacticsPanel } from './TacticsPanel'
import { Tactics, DEFAULT_TACTICS } from '../core'
import { ArenaMap } from './maps'
import { groundFor, propSprite, themeById } from './themes'
import './deploy.css'

/**
 * Per-cell brightness multiplier, hashed from the cell's own lattice coordinates.
 *
 * ⚠️ WITHOUT IT THE BOARD READS AS ONE PRINTED SHEET. The ground texture runs
 * continuously under every cell, so identically-rendered tiles let its grain line up
 * straight across every seam and the eye sees one surface with a hex pattern on it,
 * not a floor of separate tiles. A few percent of variation is all it takes to break
 * the continuity — and it is HASHED rather than rolled so a cell looks the same on
 * every render and nothing shimmers when the component rerenders.
 *
 * ⚠️ THE MULTIPLIERS MUST BE COPRIME WITH THE MODULUS, WHICH IS WHY THIS IS EXPORTED
 * AND TESTED. It was first written `(q * 7 + r * 13) % 7`, where `q * 7 % 7` is
 * identically zero: the column term vanished, every cell in a row got the same value,
 * and the board came out in flat horizontal bands. That is subtle enough to look
 * deliberate — it was caught by reading the computed `--j` off six cells and finding
 * all six equal, not by looking at it. 5 and 3 share no factor with 7.
 */
export const hexJitter = (q: number, r: number): number =>
  1 + (((q * 5 + r * 3) % 7 + 7) % 7 - 3) * 0.02

export interface DeployMonster { id: string; name: string; species: string }
export interface DeployResult { placeA: Vec2[]; tactics: Tactics[] }
export interface DeployProps {
  team: DeployMonster[]
  onStart: (r: DeployResult) => void
  /**
   * The arena this formation will actually be fought in.
   *
   * ⚠️ WITHOUT IT THE DEPLOY BOARD WAS A DIFFERENT MAP FROM THE FIGHT. `setFieldSize`
   * was called inside the fight's memo — AFTER deploy — so the grid was laid out at
   * whatever the previous size happened to be, usually the 40x22 default. Place a
   * monster on the bottom row of that board and then fight in an 18-tall arena and
   * its position is off the field entirely; the engine clamps it to the edge, so it
   * looks like a formation you never chose. The caller must set the field size for
   * this arena BEFORE rendering.
   */
  map?: ArenaMap
}

const spriteSrc = (species: string) =>
  BATTLE_SPRITE_SET.has(species) ? `/battle/${species}-idle.png` : `/sprites/${species}.png`

const prefersReducedMotion = () =>
  typeof window !== 'undefined' && !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches

export function Deploy({ team, onStart, map }: DeployProps) {
  const wrapRef = useRef<HTMLDivElement>(null)
  const [px, setPx] = useState(0)
  const [placed, setPlaced] = useState<Record<number, string>>({}) // monster idx → "q,r"
  const [selected, setSelected] = useState<number>(0)               // whose orders/placement is active
  const [tactics, setTactics] = useState<Record<number, Tactics>>({})
  const [launching, setLaunching] = useState(false)

  // ⚠️ TWO LISTS ON PURPOSE. `allCells` is what can be PLACED ON — cells a full
  // radius inside the field, so a deployment never straddles an edge. `coverCells`
  // is what gets DRAWN, and it runs off all four sides so the board reaches the
  // arena wall instead of floating in a margin of bare ground. Keeping them separate
  // is what lets the board be redrawn without moving a single monster.
  const allCells = fieldHexCells()
  const coverCells = fieldHexCoverage()
  const cellByKey = (k: string) => allCells.find((c) => `${c.q},${c.r}` === k)!

  useLayoutEffect(() => {
    const el = wrapRef.current
    if (!el) return
    const measure = () => {
      const f = el.querySelector('.dp-field') as HTMLElement | null
      if (f && f.clientWidth > 0) setPx(f.clientWidth / FIELD_W)
    }
    measure()
    const raf = requestAnimationFrame(measure) // aspect-ratio field may lay out a tick late
    window.addEventListener('resize', measure)
    return () => { cancelAnimationFrame(raf); window.removeEventListener('resize', measure) }
  }, [])

  const usedKeys = new Set(Object.values(placed))
  const allPlaced = team.every((_, i) => placed[i] != null)
  const tacticFor = (i: number) => tactics[i] ?? DEFAULT_TACTICS

  // Click a hex in YOUR zone: if occupied, SELECT that monster (for orders); if
  // empty, place (or move) the selected monster there, then advance to the next
  // unplaced. Neutral / enemy hexes are display-only.
  const placeOnCell = (cell: FieldHexCell) => {
    if (launching || cell.zone !== 'A') return
    const key = `${cell.q},${cell.r}`
    const occ = Object.entries(placed).find(([, k]) => k === key)
    if (occ) { setSelected(Number(occ[0])); return }
    setPlaced((prev) => {
      const next = { ...prev, [selected]: key }
      const nextUnplaced = team.findIndex((_, i) => next[i] == null)
      if (nextUnplaced >= 0) setSelected(nextUnplaced)
      return next
    })
  }

  const start = () => {
    if (!allPlaced || launching) return
    const result: DeployResult = {
      placeA: team.map((_, i) => { const c = cellByKey(placed[i]); return { x: c.cx, y: c.cy } }),
      tactics: team.map((_, i) => tacticFor(i)),
    }
    if (prefersReducedMotion()) { onStart(result); return }
    setLaunching(true) // fade the hexes out, then hand off
    window.setTimeout(() => onStart(result), 460)
  }

  // ⚠️ THE CELL IS DRAWN AT ITS FULL TILE SIZE, SO NEIGHBOURS MEET. This used to be
  // a radius-1.35 marker "sized well inside the cell spacing so neighbours never
  // touch" — which is why the board read as scattered pips instead of a board. The
  // shape comes from `hexTile`: the Voronoi cell of this lattice, which tiles it
  // exactly (see hex.ts for why no REGULAR hexagon can).
  const tile = hexTile()
  const TW = tile.w * px
  const TH = tile.h * px
  // A regular pointy-top hexagon: vertex top and bottom, flat left and right sides,
  // corners at a quarter and three quarters of the height. It tiles the lattice in
  // hex.ts exactly — see `hexTile` for why that took a lattice fix to be true.
  const clipPath = 'polygon(50% 0, 100% 25%, 100% 75%, 50% 100%, 0 75%, 0 25%)'
  const slot = (c: FieldHexCell) => ({
    left: c.cx * px - TW / 2, top: c.cy * px - TH / 2, width: TW, height: TH, clipPath,
    ['--j' as string]: hexJitter(c.q, c.r),
  })

  return (
    // ⚠️ THE TILT REACHES THE STYLESHEET AS A VARIABLE, FROM camera.ts. The billboards
    // counter-rotate by exactly the angle the plane rotates by; if the two are typed
    // out separately they will eventually differ, and a billboard that counter-rotates
    // by the wrong angle leans — which reads as bad art rather than as a bug.
    <div className="dp-wrap" ref={wrapRef} style={{ ['--cam-tilt' as string]: `${CAM_TILT_DEG}deg` }}>
      <div className="dp-stage">
        {/* ⚠️ THE DEPLOY BOARD IS THE ARENA — same shape, same ground, same cover.
            A formation is chosen against the obstacles you will fight around, so
            showing a generic grass rectangle here made the whole screen a guess. */}
        {/* ⚠️ TWO BOXES, NOT ONE. `.dp-field` is the FRAME — it holds the camera
            (`perspective`) and crops. `.dp-plane` is the GROUND — a full-size flat
            board that is then tilted away inside it. They cannot be one element: an
            element cannot both establish the perspective and be the thing seen
            through it, and `overflow:hidden` (which crops the overhanging hexes, and
            is load-bearing) forces a `preserve-3d` element back to flat.
            ⚠️ THE FRAME IS SHORTER THAN THE BOARD BY `CAM_HEIGHT_RATIO`. A tilted
            board is foreshortened, so a frame cut to the flat aspect would band the
            top and bottom of the screen with empty surround. */}
        <div className="dp-field" style={{
          aspectRatio: `${FIELD_W}/${FIELD_H * CAM_HEIGHT_RATIO}`,
          perspective: `${CAM_DEPTH * FIELD_H * px}px`,
        }}>
        <div className="dp-plane" style={{
          aspectRatio: `${FIELD_W}/${FIELD_H}`,
          transform: `translateY(calc(-50% - ${(CAM_Y_OFFSET * 100).toFixed(3)}%)) rotateX(${CAM_TILT_DEG}deg) scale(${CAM_FIT})`,
          backgroundImage: `url(${groundFor(themeById(map?.theme ?? 'proving'), map?.surface).ground})`,
          backgroundSize: groundFor(themeById(map?.theme ?? 'proving'), map?.surface).groundScale,
        }}>
          {/* ⚠️ THE SHADOW IS ITS OWN ELEMENT LYING ON THE GROUND, not a `drop-shadow`
              on the sprite. A drop-shadow is offset in SCREEN space, so it slides
              across the floor as a flat smear that follows the picture rather than the
              light — a large part of why cover read as stuck on. This one lives on the
              plane, so the camera foreshortens it into an ellipse the way it
              foreshortens everything else on the floor. */}
          {px > 0 && (map?.obstacles ?? []).map((o, i) => (
            <div key={`sh${i}`} className="dp-shadow" style={{
              left: o.x * px, top: (o.y + o.h * 0.5) * px,
              width: o.w * px, height: o.h * 0.9 * px,
            }} />
          ))}
          {px > 0 && (map?.obstacles ?? []).map((o, i) => (
            <div key={`o${i}`} className="dp-rock" style={{
              left: o.x * px, top: o.y * px, width: o.w * px, height: o.h * px,
              zIndex: 5 + Math.round(o.y + o.h),
            }}><img src={propSprite(themeById(map?.theme ?? 'proving'), o.kind)} alt="" /></div>
          ))}
          {px > 0 && <>
            {/* HEX GRID — the WHOLE board is hexed (middle band faint, the two
                zones live). Fades out on launch; deployment-only, gone in the fight. */}
            <div className={`dp-hexlayer${launching ? ' launching' : ''}`}>
              {coverCells.map((c) => {
                const key = `${c.q},${c.r}`
                // ⚠️ AN UNPLACEABLE CELL READS AS BOARD, NEVER AS YOUR ZONE. The
                // overhanging edge cells fall inside band A by x, but nothing can be
                // put on them — tinting them like the live zone would advertise a
                // move that silently does nothing.
                if (!c.playable || c.zone === 'neutral') return <div key={`n${key}`} className="dp-hex dp-neutral" style={slot(c)} />
                if (c.zone === 'B') return <div key={`b${key}`} className="dp-hex dp-enemy" style={slot(c)} />
                return (
                  <div
                    key={`a${key}`}
                    className={`dp-hex dp-mine${usedKeys.has(key) ? ' dp-filled' : ' dp-open'}`}
                    style={slot(c)} onClick={() => placeOnCell(c)} role="button" aria-label={`hex ${c.q},${c.r}`}
                  />
                )
              })}
            </div>
            {/* SPRITES — a separate, un-clipped layer so nothing is cut off; stays
                through the hex fade for visual continuity into the fight. */}
            {team.map((m, i) => {
              if (placed[i] == null) return null
              const c = cellByKey(placed[i])
              const S = 3.6 * px
              return (
                <img
                  key={`s${m.id}`} className={`dp-sprite${selected === i ? ' dp-sel' : ''}`} alt={m.name} src={spriteSrc(m.species)}
                  draggable={false}
                  // ⚠️ FEET BELOW THE CELL CENTRE, not on it. A sprite centred on the
                  // hex floats above its own tile; dropping it a fifth of a tile
                  // height seats it on the cell the way a unit stands on the ground.
                  // Was `R * 0.6` off the old marker radius — same offset, now
                  // derived from the tile so it tracks the board instead of a
                  // constant that no longer exists.
                  style={{ left: c.cx * px - S / 2, top: c.cy * px - S + TH * 0.2, width: S, height: S,
                           zIndex: 40 + Math.round(c.cy) }}
                  onClick={() => setSelected(i)}
                />
              )
            })}
          </>}
        </div>
        </div>
      </div>

      <div className="dp-tray">
        <span className="dp-lbl">Your team — pick, then click a hex</span>
        {team.map((m, i) => (
          <button key={m.id}
            className={`dp-chip${selected === i ? ' dp-picked' : ''}${placed[i] != null ? ' dp-done' : ''}`}
            onClick={() => setSelected(i)}>
            <img src={spriteSrc(m.species)} alt="" />
            <span>{m.name}</span>
            {placed[i] != null && <em className="dp-tick">✓</em>}
          </button>
        ))}
        <button className="dp-start" disabled={!allPlaced || launching} onClick={start}>
          {launching ? 'Fighting…' : 'Fight →'}
        </button>
      </div>

      <TacticsPanel name={team[selected]?.name ?? ''} value={tacticFor(selected)}
        onChange={(t) => setTactics((prev) => ({ ...prev, [selected]: t }))} />

      <p className="dp-hint">
        Click a monster (tray or field) to select it, a blue hex to place or move it, and set its
        <b> orders</b> below — they drive how it fights. The enemy (red hexes) deploys by role.
        The grid is for deployment only; it fades when the fight begins.
      </p>
    </div>
  )
}
