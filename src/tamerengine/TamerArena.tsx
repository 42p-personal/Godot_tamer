// ─────────────────────────────────────────────────────────────────────────────
// TAMER ARENA (M4) — the mounted renderer for a tamerengine fight.
//
// Plays back a `FieldResult` (the deterministic event stream) on the pixel
// battlefield: the battle sprites walk/strike, ability animations fire off the
// cast/hit events, and the player controls the pace with the timer toggles.
//
// STATE LIVES IN THE ROSTERS, NOT ON THE FIELD — the player's team down the left,
// opponents down the right, each tile carrying a portrait, HP and MP bars with the
// numbers inside them, and that unit's statuses.
//
// ⚠️ NOTHING IS DRAWN OVER THE SPRITES ANY MORE, and the cost of that is real: a
// bar above a monster tells you WHO is hurt and WHERE it is standing in one look,
// which a side roster cannot. The tiles therefore FLASH when their unit takes a hit
// — that is what keeps field and roster connected, and it is why the flash is not
// decoration and should not later be tidied away as noise.
//
// ⚠️ DRIVEN IMPERATIVELY, not by per-frame React state. At 60fps a React tree of
// a dozen animating sprites would thrash; instead React lays out the shell and
// controls once, and a single rAF loop in an effect updates the DOM (transforms,
// bar fills, icon rows) and the fx canvas directly. React state is only the
// controls (speed, playing). This is the same shape the previews proved.
//
// The sprite frame logic mirrors BattleSprite's `sheet` mode (walk cycle from
// public/battle, strike on a cast) — kept inline here because the playback owns
// the animation clock rather than each sprite owning its own.
import { useEffect, useRef, useState } from 'react'
import { FieldEvent, FieldResult, Obstacle, FIELD_W, FIELD_H } from './types'
import { ArenaMap } from './maps'
import { groundFor, propSprite, themeById } from './themes'
import { moveFx, effectIcon, TRAVELS, MoveFx } from './fieldFx'
import { BATTLE_SPRITE_SET } from './BattleSprite'
import { CAM_TILT_DEG, CAM_DEPTH, CAM_FIT, CAM_HEIGHT_RATIO, CAM_Y_OFFSET } from './camera'
import './tamerArena.css'

type Snap = Extract<FieldEvent, { kind: 'snapshot' }>
/** The sim snapshots at 10 Hz. */
const SNAP_DT = 0.1
const WALK = ['walk1', 'walk2', 'walk3', 'walk4']
// ⚠️ 8x IS THE CEILING, AND IT IS A RENDERING LIMIT, NOT A PREFERENCE. The clock
// is time-scaled (`clock += dt * speed`) so any multiplier is legal, but the sim
// snapshots at 10 Hz: at 8x a 60fps frame advances 1.33 sim ticks, which the
// interpolation still smooths. Past ~10x it skips whole ticks and motion goes
// back to looking like the teleports we just spent a day removing.
// Added when MAX_SECONDS went to 300 — a four-minute grind is 30s at 8x.
const SPEEDS = [0.25, 0.5, 1, 2, 4, 8]

/**
 * Which snapshot to draw for a playback time, clamped into the array.
 *
 * ⚠️ EXPORTED ONLY SO IT CAN BE TESTED, and it earned that. Unclamped below, a
 * negative time gave `snaps[-1]` = undefined; reading `.units` off it threw INSIDE
 * the rAF callback, before the line that schedules the next frame, so playback died
 * on frame one — every unit stranded at translate(0,0), unsized, piled in the
 * corner of the field. See `frameDelta` for how the time went negative.
 */
export const snapIndexAt = (tt: number, len: number): number =>
  Math.max(0, Math.min(len - 1, Math.floor(tt / SNAP_DT) || 0))

/**
 * Seconds of playback for one animation frame.
 *
 * ⚠️ CLAMPED AT BOTH ENDS. The ceiling stops a backgrounded tab resuming with one
 * enormous jump — the teleporting this renderer exists to avoid. The FLOOR is the
 * one that was missing: `last` is seeded from `performance.now()` when the effect
 * runs, but rAF hands back the FRAME START timestamp, which can be EARLIER than
 * that, so the first frame produced a negative delta. Timing-dependent, which is
 * why it reproduced on one machine and not another.
 */
export const frameDelta = (now: number, last: number): number =>
  Math.max(0, Math.min(0.05, (now - last) / 1000))

export interface TamerArenaProps {
  result: FieldResult
  /** unit id (e.g. "A0") → species id, so the renderer knows which sprite. */
  speciesById: Record<string, string>
  /** unit id → display name for the roster. Falls back to the species id. */
  namesById?: Record<string, string>
  obstacles: Obstacle[]
  /** Team display names for the legend. */
  teamAName?: string
  teamBName?: string
  /**
   * The arena this fight was simulated on — supplies its SIZE and its THEME.
   *
   * ⚠️ IF YOU PASS ONE, IT MUST BE THE ARENA THE SIM ACTUALLY RAN ON. The renderer
   * derives pixels-per-world-unit from `map.w`; hand it a different arena than
   * `setFieldSize` was called with and every position is drawn at the wrong scale —
   * silently, and looking like a physics bug rather than a plumbing one.
   *
   * Omitted, it falls back to the engine's current global size and the plain
   * proving-ground art, which is what the older harnesses expect.
   */
  map?: ArenaMap
}

export function TamerArena({ result, speciesById, namesById, obstacles, teamAName = 'Team A', teamBName = 'Team B', map }: TamerArenaProps) {
  const worldW = map?.w ?? FIELD_W
  const worldH = map?.h ?? FIELD_H
  const theme = themeById(map?.theme ?? 'proving')
  const floor = groundFor(theme, map?.surface)
  const fieldRef = useRef<HTMLDivElement>(null)
  const planeRef = useRef<HTMLDivElement>(null)
  const rosterARef = useRef<HTMLDivElement>(null)
  const rosterBRef = useRef<HTMLDivElement>(null)
  const fxRef = useRef<HTMLCanvasElement>(null)
  const [speed, setSpeed] = useState(1)
  const [playing, setPlaying] = useState(true)
  const [ended, setEnded] = useState(false)
  // Live refs the rAF loop reads without re-subscribing.
  const speedR = useRef(speed); speedR.current = speed
  const playR = useRef(playing); playR.current = playing

  useEffect(() => {
    const field = fieldRef.current, fx = fxRef.current
    const rosterA = rosterARef.current, rosterB = rosterBRef.current
    if (!field || !fx || !rosterA || !rosterB) return
    const rosters: Record<string, HTMLDivElement> = { A: rosterA, B: rosterB }
    const ctx = fx.getContext('2d')!
    const snaps = result.events.filter((e) => e.kind === 'snapshot') as Snap[]
    if (!snaps.length) return
    const duration = snaps[snaps.length - 1].t

    // ── geometry ────────────────────────────────────────────────────────────
    const plane = planeRef.current!
    let PX = 1, SPRITE = 1
    const scale = () => {
      PX = plane.clientWidth / worldW
      SPRITE = PX * 3.4
      // ⚠️ THE EYE DISTANCE IS IN PIXELS, SO IT HAS TO BE RE-SET ON EVERY RESIZE.
      // `perspective` takes a length, and camera.ts specifies it in board HEIGHTS —
      // pinning it to a constant px would make the tilt stronger on a phone than on a
      // desktop, i.e. a different camera per window size.
      field.style.perspective = `${CAM_DEPTH * plane.clientHeight}px`
      fx.width = plane.clientWidth
      fx.height = plane.clientHeight
    }

    // ── obstacles (pixel boulders) ────────────────────────────────────────────
    const drawRocks = () => {
      plane.querySelectorAll('.ta-rock').forEach((r) => r.remove())
      for (const o of obstacles) {
        const el = document.createElement('div')
        el.className = 'ta-rock'
        // ⚠️ THE OBSTACLE RECTANGLE IS A FOOTPRINT ON THE GROUND, NOT A PICTURE
        // FRAME. Stretching the sprite to fill it squashed every prop flat into its
        // own floor area — a chopping stump with no height, standing beside a
        // gorilla drawn at full height. The div is the footprint; the sprite STANDS
        // on it (see .ta-rock img: full width, natural height, bottom-anchored), so
        // cover has real height in exactly the way the units do.
        el.style.cssText = `left:${o.x * PX}px;top:${o.y * PX}px;`
          + `width:${o.w * PX}px;height:${o.h * PX}px;`
          // ⚠️ Y-SORTED WITH THE UNITS, on the same rule (`5 + round(y)`). Flat props
          // could sit on a fixed layer behind everything; a prop with height cannot,
          // or a monster standing BEHIND a log stack draws in front of it.
          + `z-index:${5 + Math.round(o.y + o.h)}`
        el.innerHTML = `<img src="${propSprite(theme, o.kind)}" alt="">`
        plane.appendChild(el)
      }
    }

    // ── one unit's DOM (sprite + bars + icon rows) ────────────────────────────
    interface UnitEl {
      root: HTMLDivElement; face: HTMLDivElement; img: HTMLImageElement
      tile: HTMLDivElement; hpFill: HTMLDivElement; mpFill: HTMLDivElement
      hpNum: HTMLSpanElement; mpNum: HTMLSpanElement; fxRow: HTMLDivElement
      species: string; side: string; facing: number; walk: number; wt: number; anim: string
      maxHp: number; maxMp: number
      /** Clock time of the last HP drop — drives the roster flash. */
      hurtAt: number; lastHp: number; wasDead: boolean
    }
    const units: Record<string, UnitEl> = {}

    // ⚠️ THE NOTCHES ARE GONE ON PURPOSE. They existed to convey pool SIZE on a
    // fixed-width bar — more, tighter ticks meant a bigger monster — which was an
    // approximation of a number that is now printed inside the bar. Keeping both
    // would be the same fact told twice, in the smaller space of the two.

    const buildUnits = () => {
      plane.querySelectorAll('.ta-unit').forEach((u) => u.remove())
      rosterA.innerHTML = ''
      rosterB.innerHTML = ''
      for (const key of Object.keys(units)) delete units[key]
      const first = snaps[0]
      for (const u of first.units) {
        const sp = speciesById[u.id]
        const side = u.id[0]
        const root = document.createElement('div')
        root.className = `ta-unit team${side}`
        // ⚠️ THE TEAM RING IS ON THE GROUND, NOT ON THE MONSTER. Tinting or
        // outlining the sprite itself would fight art that is already authored per
        // species, and a floating marker would put clutter back above the sprites
        // that was just deliberately cleared off them. A ring under the feet is the
        // one place a team colour can live without competing with anything.
        //
        // ⚠️ IT IS NOT OPTIONAL POLISH. Both sides can field the SAME SPECIES — the
        // dev route runs kongrath against kongrath — and once the lines close and
        // mix, side is unrecoverable from position or from facing alone.
        root.innerHTML = `<div class="ta-ring"></div><div class="ta-shadow"></div>`
          + `<div class="ta-face"><img draggable="false" alt="${sp}"></div>`
        plane.appendChild(root)
        const has = BATTLE_SPRITE_SET.has(sp)
        const img = root.querySelector('.ta-face img') as HTMLImageElement
        img.src = has ? `/battle/${sp}-idle.png` : `/sprites/${sp}.png`

        // ── the roster tile ───────────────────────────────────────
        // ⚠️ ALWAYS THE PORTRAIT (`/sprites`), never the battle sheet. The battle
        // frames are 128px side-profiles drawn to read in MOTION at arena scale; at
        // thumbnail size, in profile, they are hard to tell apart. Saying WHICH
        // MONSTER THIS IS is the tile's entire job.
        const tile = document.createElement('div')
        tile.className = `ta-tile team${side}`
        tile.innerHTML =
          `<div class="ta-thumb"><img draggable="false" alt="" src="/sprites/${sp}.png"></div>` +
          `<div class="ta-tmeta">` +
          `<div class="ta-tname"></div>` +
          `<div class="ta-tbar ta-thp"><i></i><span></span></div>` +
          `<div class="ta-tbar ta-tmp"><i></i><span></span></div>` +
          `<div class="ta-tfx"></div>` +
          `</div>`
        const nameEl = tile.querySelector('.ta-tname') as HTMLDivElement
        nameEl.textContent = namesById?.[u.id] ?? sp
        nameEl.title = nameEl.textContent
        rosters[side].appendChild(tile)

        units[u.id] = {
          root, face: root.querySelector('.ta-face')!, img, tile,
          hpFill: tile.querySelector('.ta-thp i')!, mpFill: tile.querySelector('.ta-tmp i')!,
          hpNum: tile.querySelector('.ta-thp span')!, mpNum: tile.querySelector('.ta-tmp span')!,
          fxRow: tile.querySelector('.ta-tfx')!,
          species: sp, side, facing: side === 'A' ? 1 : -1, walk: 0, wt: 0, anim: 'idle',
          maxHp: u.maxHp, maxMp: u.maxMp, hurtAt: -9, lastHp: u.hp, wasDead: false,
        }
        paintTile(units[u.id], u, 0)
      }
    }

    const spriteFrame = (u: UnitEl, state: string, dt: number) => {
      const has = BATTLE_SPRITE_SET.has(u.species)
      if (!has) return `/sprites/${u.species}.png`
      if (state === 'move') { u.wt += dt; if (u.wt > 0.11) { u.wt = 0; u.walk = (u.walk + 1) % 4 } return `/battle/${u.species}-${WALK[u.walk]}.png` }
      if (state === 'cast') return `/battle/${u.species}-strike.png`
      return `/battle/${u.species}-idle.png`
    }
    // ⚠️ WRITE-GUARDED, and it matters more here than it looks. This runs for every
    // unit on every frame; assigning identical textContent still dirties layout, and
    // at 60fps x 10 tiles that is a measurable cost for zero visible change. Same
    // reason the bar numbers below compare before writing.
    const setRow = (row: HTMLDivElement, keys: string[]) => {
      const want = keys.map(effectIcon).join('')
      if (row.dataset.k !== want) { row.dataset.k = want; row.textContent = want }
    }
    const setNum = (el: HTMLSpanElement, want: string) => {
      if (el.textContent !== want) el.textContent = want
    }

    /**
     * Paint one roster tile from a snapshot unit.
     *
     * ⚠️ CALLED AT BUILD TIME TOO, not only from the rAF loop, so the roster is
     * correct at t=0. Left to the loop alone the tiles rendered blank until the
     * first animation frame — which is forever if the fight is mounted paused, and
     * was VISIBLY forever in a browser pane that is not compositing, since rAF does
     * not fire at all there. A HUD whose correctness depends on animation running
     * is a HUD that is wrong whenever it is standing still.
     */
    type SnapUnit = Snap['units'][number]
    const paintTile = (el: UnitEl, u: SnapUnit, tt: number) => {
      const dead = u.state === 'dead'
      const pct = (v: number, max: number) => Math.max(0, Math.min(100, (v / Math.max(1, max)) * 100))
      el.hpFill.style.width = pct(u.hp, el.maxHp) + '%'
      el.mpFill.style.width = pct(u.mp, el.maxMp) + '%'
      setNum(el.hpNum, `${Math.max(0, Math.round(u.hp))}/${el.maxHp}`)
      // ⚠️ A ZERO-MANA MONSTER IS A REAL BUILD, not a broken one — maxMana is
      // WIS + floor(INT/2), so a pure bruiser can genuinely have none. Printing
      // "0/0" beside a bar that can never move reads as a fault; an em dash says
      // "this one does not use mana", which is the truth.
      setNum(el.mpNum, el.maxMp > 0 ? `${Math.max(0, Math.round(u.mp))}/${el.maxMp}` : '—')
      // Debuffs first — what is being DONE TO this monster is what a player scans
      // for, and the row wraps when both are busy.
      setRow(el.fxRow, [...u.debuffs, ...u.buffs])

      // Health BANDS, not a gradient: "amber" and "red" read instantly, where a
      // continuously interpolated hue just looks slightly different every frame.
      const frac = u.hp / Math.max(1, el.maxHp)
      el.tile.classList.toggle('low', !dead && frac <= 0.5 && frac > 0.25)
      el.tile.classList.toggle('crit', !dead && frac <= 0.25)
      if (dead !== el.wasDead) { el.wasDead = dead; el.tile.classList.toggle('ko', dead) }

      // The flash, read off the snapshot's own HP rather than the hit stream so
      // poison, burn and recoil register too — anything that actually took health.
      if (u.hp < el.lastHp) el.hurtAt = tt
      el.lastHp = u.hp
      el.tile.style.setProperty('--hurt', Math.max(0, 1 - (tt - el.hurtAt) / 0.45).toFixed(2))
    }

    // ── ability fx (canvas overlay) ───────────────────────────────────────────
    interface Proj { t0: number; t1: number; from: [number, number]; to: [number, number]; fx: MoveFx }
    interface Burst { t: number; at: [number, number]; fx: MoveFx; kind: string; crit?: boolean }
    const projectiles: Proj[] = []
    const bursts: Burst[] = []
    const posAt = (id: string, tt: number): [number, number] | null => {
      const i = Math.max(0, Math.min(snaps.length - 1, Math.round(tt / 0.1)))
      const u = snaps[i].units.find((x) => x.id === id)
      return u ? [u.x, u.y] : null
    }
    // Pre-compute every ability's fx from the cast/hit stream.
    for (const e of result.events) {
      if (e.kind === 'cast' && e.targetId) {
        const fxv = moveFx(e.move, e.channel)
        const from = posAt(e.id, e.t), to = posAt(e.targetId, e.t + 0.2)
        if (!from || !to) continue
        if (TRAVELS.has(fxv.kind)) {
          projectiles.push({ t0: e.t, t1: e.t + (fxv.kind === 'beam' ? 0.16 : 0.34), from, to, fx: fxv })
        } else {
          bursts.push({ t: e.t + 0.12, at: to, fx: fxv, kind: fxv.kind })
        }
      }
      if (e.kind === 'hit') {
        const at = posAt(e.targetId, e.t)
        if (at) bursts.push({ t: e.t, at, fx: moveFx(e.move, e.channel), kind: 'impact', crit: e.crit })
      }
      if (e.kind === 'heal' && (e as { targetId?: string }).targetId) {
        const at = posAt((e as { targetId: string }).targetId, e.t)
        if (at) bursts.push({ t: e.t, at, fx: { struct: 'burst', kind: 'heal', color: '#7dffab' }, kind: 'heal' })
      }
    }

    const drawFx = (tt: number) => {
      ctx.clearRect(0, 0, fx.width, fx.height)
      for (const p of projectiles) {
        if (tt < p.t0 || tt > p.t1) continue
        const f = (tt - p.t0) / (p.t1 - p.t0)
        const x = (p.from[0] + (p.to[0] - p.from[0]) * f) * PX
        const y = (p.from[1] + (p.to[1] - p.from[1]) * f - 1.6) * PX
        const ang = Math.atan2(p.to[1] - p.from[1], p.to[0] - p.from[0])
        ctx.save(); ctx.translate(x, y); ctx.rotate(ang)
        if (p.fx.kind === 'arrow' || p.fx.kind === 'beam') {
          ctx.strokeStyle = p.fx.color; ctx.lineWidth = p.fx.kind === 'beam' ? 3.5 : 2.4
          ctx.beginPath(); ctx.moveTo(-12, 0); ctx.lineTo(8, 0); ctx.stroke()
          ctx.fillStyle = p.fx.color; ctx.beginPath(); ctx.moveTo(12, 0); ctx.lineTo(5, -3.5); ctx.lineTo(5, 3.5); ctx.closePath(); ctx.fill()
        } else {
          const g = ctx.createRadialGradient(0, 0, 0, 0, 0, 10)
          g.addColorStop(0, '#fff'); g.addColorStop(0.4, p.fx.color); g.addColorStop(1, 'transparent')
          ctx.fillStyle = g; ctx.beginPath(); ctx.arc(0, 0, 10, 0, 7); ctx.fill()
        }
        ctx.restore()
      }
      for (const b of bursts) {
        const age = tt - b.t
        const life = b.kind === 'heal' ? 0.4 : b.kind === 'slam' ? 0.32 : 0.26
        if (age < 0 || age > life) continue
        const k = age / life, x = b.at[0] * PX, y = (b.at[1] - 1.6) * PX
        ctx.globalAlpha = 1 - k
        if (b.kind === 'heal') {
          ctx.strokeStyle = '#7dffab'; ctx.lineWidth = 3
          const yy = y - 8 - k * 12; ctx.beginPath(); ctx.moveTo(x, yy); ctx.lineTo(x, yy - 6); ctx.moveTo(x - 3, yy - 3); ctx.lineTo(x + 3, yy - 3); ctx.stroke()
        } else if (b.kind === 'impact' || b.kind === 'claw') {
          const r = 4 + k * 15
          ctx.strokeStyle = b.crit ? '#ffd45e' : '#fff2c8'; ctx.lineWidth = b.crit ? 3 : 2
          ctx.beginPath(); ctx.arc(x, y, r, 0, 7); ctx.stroke()
          const n = b.crit ? 7 : 5
          for (let i = 0; i < n; i++) { const a = (i / n) * 7 + k; ctx.beginPath(); ctx.moveTo(x + Math.cos(a) * r * 0.5, y + Math.sin(a) * r * 0.5); ctx.lineTo(x + Math.cos(a) * r, y + Math.sin(a) * r); ctx.stroke() }
        } else {
          // burst kinds — a coloured shockwave ring (cage/firewall/earthspike/sonic…)
          const r = 6 + k * 22
          ctx.strokeStyle = b.fx.color; ctx.lineWidth = 3
          ctx.beginPath(); ctx.arc(x, y, r, 0, 7); ctx.stroke()
          if (b.kind === 'slam' || b.kind === 'earthspike') { ctx.beginPath(); ctx.arc(x, y, r * 0.6, 0, 7); ctx.stroke() }
        }
        ctx.globalAlpha = 1
      }
    }

    // ── playback loop ─────────────────────────────────────────────────────────
    scale(); drawRocks(); buildUnits()
    // ⚠️ The clock is accumulated from rAF dt, NOT `now - mountTime`. rAF is
    // paused while the tab is hidden but `performance.now()` keeps running, so a
    // component mounted off-screen would, on first paint, jump the fight straight
    // to its end. Accumulating dt (which only advances on real frames) and
    // scaling by the current speed also makes the speed toggles seamless.
    let clock = 0, last = performance.now(), done = false
    const hud = field.querySelector('.ta-hud') as HTMLDivElement

    /**
     * Draw the whole battlefield at time `tt`. Separated from the rAF loop so it
     * can be called with ZERO frames elapsed.
     *
     * ⚠️ THE UNITS USED TO BE POSITIONED AND SIZED ONLY FROM INSIDE THE LOOP, and
     * that is a bug the roster tiles were already fixed for and the sprites were
     * not — the same mistake, half-corrected. Until the first frame ran, every unit
     * sat at translate(0,0) with no width: six monsters stacked in the top-left
     * corner of the field at their natural PNG size, over a HUD still reading "—".
     * It reads exactly like "the deployment isn't working", because the formation
     * is the thing you cannot see.
     *
     * ⚠️ ANY renderer state that only exists after an animation frame is wrong
     * whenever the animation is not running — mounted paused, tab backgrounded, a
     * browser that throttles rAF, a pane that is not compositing. Draw the truth
     * first, then animate it.
     */
    const drawAt = (tt: number, dt: number) => {
      const i = snapIndexAt(tt, snaps.length)
      const j = snapIndexAt(tt + SNAP_DT, snaps.length)
      const f = Math.max(0, Math.min(1, tt / SNAP_DT - i))
      const a = snaps[i], b = snaps[j]
      const bmap: Record<string, Snap['units'][number]> = {}
      for (const u of b.units) bmap[u.id] = u
      for (const ua of a.units) {
        const el = units[ua.id]; if (!el) continue
        const ub = bmap[ua.id] ?? ua
        const x = ua.x + (ub.x - ua.x) * f, y = ua.y + (ub.y - ua.y) * f
        const dead = ua.state === 'dead'
        const dx = ub.x - ua.x
        if (Math.abs(dx) > 0.02) el.facing = dx > 0 ? 1 : -1
        el.img.src = spriteFrame(el, ua.state, dt)
        el.img.style.width = el.img.style.height = SPRITE + 'px'

        paintTile(el, ua, tt)
        // BLOCKING reads as a braced stance — the unit is holding, not idling,
        // and it is now a real slice of the fight, so it must be visible.
        el.face.style.filter = ua.state === 'block' ? 'drop-shadow(0 0 3px #6fb6ff) brightness(0.88)' : ''
        // ⚠️ THE BILLBOARD ROTATION IS IN HERE, NOT IN THE STYLESHEET, AND IT HAS TO
        // BE. This line runs every frame and REPLACES the element's transform, so a
        // `.ta-face { transform: rotateX(...) }` rule would be silently wiped on the
        // first tick and every monster would lie flat on the tilted floor. A CSS rule
        // that a rAF loop overwrites is not a rule, it is a comment.
        // ⚠️ AND THE ORDER MATTERS. `rotateX` is leftmost so it applies LAST: the
        // sprite is flipped for facing and tipped over for death in its own upright
        // space, and only then stood up to face the camera. Put it last and a dead
        // monster falls over sideways in screen space instead of onto the ground.
        el.face.style.transform = `rotateX(${-CAM_TILT_DEG}deg) `
          + `scaleX(${el.facing}) rotate(${dead ? '82deg' : '0'})`
        el.root.style.opacity = dead ? '0.34' : '1'
        el.root.style.transform = `translate3d(${x * PX - SPRITE / 2}px,${y * PX - SPRITE}px,0)`
        el.root.style.zIndex = String(5 + Math.round(y))
      }
      drawFx(tt)
      const alive = a.units.filter((u) => u.state !== 'dead').length
      if (hud) hud.textContent = `t=${tt.toFixed(1)}s / ${duration.toFixed(0)}s`
        + ` · alive ${alive}/${a.units.length} · ${speedR.current}×`
    }

    drawAt(0, 0) // the deployed formation, before a single frame has run

    let raf = 0
    const step = (now: number) => {
      const dt = frameDelta(now, last); last = now
      if (playR.current) {
        clock += dt * speedR.current
        drawAt(clock, dt * speedR.current)
        if (clock >= duration && !done) { done = true; setEnded(true); setPlaying(false) }
      }
      raf = requestAnimationFrame(step)
    }
    raf = requestAnimationFrame(step)

    // ⚠️ A ResizeObserver, NOT just window.resize. The field is now the middle
    // column of a grid, so its width changes without the window changing — and if
    // it is measured at zero (mounted inside a collapsed or not-yet-laid-out
    // container) then PX is 0 and EVERY unit computes to translate(0,0): the same
    // pile-in-the-corner, from a different cause. This re-measures and redraws
    // whenever the box actually changes, including the first time it gains a size.
    const onResize = () => { scale(); drawRocks(); drawAt(clock, 0) }
    const ro = new ResizeObserver(onResize)
    ro.observe(field)
    window.addEventListener('resize', onResize)
    return () => {
      cancelAnimationFrame(raf); ro.disconnect()
      window.removeEventListener('resize', onResize)
    }
  }, [result, speciesById, obstacles, worldW, worldH, theme])

  const winner = result.winner
  return (
    <div className="ta-wrap">
      {/* ⚠️ THE FIELD IS THE MIDDLE COLUMN OF A GRID, so its width is set by
          layout rather than by the viewport. `scale()` derives PX from
          `field.clientWidth`, and it runs on mount and on window resize — which
          covers every way this box can change size, since the roster columns are
          fixed-width and the tiles never reflow the field on their own. */}
      <div className="ta-stage" style={{ ['--cam-tilt' as string]: `${CAM_TILT_DEG}deg` }}>
        <div className="ta-roster side-a">
          <div className="ta-rhead">{teamAName}</div>
          <div className="ta-rlist" ref={rosterARef} />
        </div>
        {/* ⚠️ ASPECT COMES FROM THE ARENA, NOT THE STYLESHEET. `.ta-field` used to
            hard-code 40/22; a 30x18 paddock rendered in that box is stretched, and
            every distance the player judges by eye is wrong even though the sim is
            right. */}
        {/* ⚠️ THE SAME TWO-BOX CAMERA AS THE DEPLOY SCREEN, and it has to be the
            same or the two are different worlds: you would choose a formation on a
            flat diagram and then watch it fought on a tilted floor, with cover a
            different size and shape in each. `.ta-field` is the FRAME (camera + crop),
            `.ta-plane` is the GROUND. See camera.ts for why the props needed this. */}
        <div className="ta-field" ref={fieldRef}
          style={{ aspectRatio: `${worldW}/${worldH * CAM_HEIGHT_RATIO}`,
            }}>
          <div className="ta-plane" ref={planeRef}
            style={{ aspectRatio: `${worldW}/${worldH}`,
              transform: `translateY(calc(-50% - ${(CAM_Y_OFFSET * 100).toFixed(3)}%)) `
                + `rotateX(${CAM_TILT_DEG}deg) scale(${CAM_FIT})`,
              backgroundImage: `url(${floor.ground})`, backgroundSize: floor.groundScale }}>
            {/* ⚠️ THE EFFECTS CANVAS LIVES ON THE PLANE, NOT ON THE FRAME. Every
                projectile, burst and ring it draws is in flat world pixels; left on
                the frame it would keep drawing on a flat surface while the ground
                turned, so a hit ring would sit beside the monster it landed on. On
                the plane it tilts with the floor, which is also where those effects
                belong — they are marks on the ground. */}
            <canvas className="ta-fx" ref={fxRef} />
          </div>
          <div className="ta-hud">—</div>
          {ended && (
            <div className={'ta-banner ' + (winner === 'A' ? 'teamA' : winner === 'B' ? 'teamB' : '')}>
              <span>{winner === 'A' ? `${teamAName} wins` : winner === 'B' ? `${teamBName} wins` : 'Draw'}</span>
            </div>
          )}
        </div>
        <div className="ta-roster side-b">
          <div className="ta-rhead">{teamBName}</div>
          <div className="ta-rlist" ref={rosterBRef} />
        </div>
      </div>
      <div className="ta-controls">
        <button className="ta-btn ta-primary" onClick={() => { setPlaying((p) => !p) }}>{playing ? '⏸ Pause' : '▶ Play'}</button>
        <div className="ta-speeds">
          <span className="ta-lbl">Speed</span>
          {SPEEDS.map((s) => (
            <button key={s} className="ta-btn" aria-pressed={speed === s} onClick={() => setSpeed(s)}>{s}×</button>
          ))}
        </div>
      </div>
    </div>
  )
}
