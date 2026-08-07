// A PROTOTYPE, on its own route (`?arena3d`), deliberately beside the 2D renderer
// rather than replacing it. Nothing in the game imports this — it exists to be judged
// against the current battlefield, and to be deleted cheaply if it loses.
import { useEffect, useRef, useState } from 'react'
import { setFieldSize, type FieldEvent } from '../types'
import { ARENA_LEAGUE_TEAM, arenaGridFor, mapById, MAPS } from '../maps'
import { themeById } from '../themes'
import { autoDeployByRole, fieldHexCoverage, hexArenaSize, HEX_SIZE } from '../hex'
import { simulateFieldBattle } from '../engine'
import { generateMonster } from '../../monster'
import type { Monster } from '../../core'
import { createScene3D, type Unit3D } from './scene3d'
import { venueFor, VENUE_TIER } from './venue'
import { paletteFor } from './look'

const DEMO_TEAM = ['kongrath', 'strixil', 'crocmaw', 'vespera', 'maelurk', 'iguanor']

/** A fixture board (`leagues: []`) has no league, so it gets the 3v3 default. */
const teamSizeForLeague = (lg?: string): number =>
  Math.max(1, Math.min(3, ARENA_LEAGUE_TEAM[lg ?? ''] ?? 3))

/**
 * Run a real fight on this arena and return its position track.
 *
 * WARNING: THIS IS THE ACTUAL ENGINE, NOT A CANNED ANIMATION. `simulateFieldBattle` is
 * the same function the game runs, on the same arena, with the same auto-deploy — so
 * what the replay shows is what the sim did, including the parts that look wrong. A
 * hand-waved demo loop would make the renderer look good and tell us nothing about
 * whether the fight reads.
 */
function runBattle(
  map: { w: number; h: number; obstacles: unknown[]; leagues?: string[] }, seed: string,
) {
  // ⚠️ THE BOARD'S OWN TEAM SIZE, NOT A HARDCODED 3. This was `const per = 3` for every
  // arena in the game, so Wood — a 1v1 league — was judged with SIX monsters standing on a
  // board built for two, and every screenshot of it was of a fight that cannot happen.
  // "Cluttered" was partly this. A preview whose job is to be looked at has to show the
  // fight the league actually runs, or it is measuring the wrong thing at full confidence.
  const per = teamSizeForLeague((map.leagues ?? [])[0])
  const mk = (sp: string, sd: string) => generateMonster(sd, { speciesId: sp, train: 850 }) as Monster
  const aSp = DEMO_TEAM.slice(0, per)
  const bSp = DEMO_TEAM.slice(per, per * 2)
  const teamA = aSp.map((sp, i) => mk(sp, seed + 'a' + i))
  const teamB = bSp.map((sp, i) => mk(sp, seed + 'b' + i))
  const byRole = (t: Monster[], side: 'A' | 'B') => autoDeployByRole(side,
    t.map((m) => ({ front: m.stats.CON + m.stats.STR - m.stats.INT - m.stats.WIS })))
  const result = simulateFieldBattle({
    seed, teamA, teamB,
    obstacles: map.obstacles as never,
    placeA: byRole(teamA, 'A'), placeB: byRole(teamB, 'B'),
  })
  const species: Record<string, string> = {}
  aSp.forEach((sp, i) => { species['A' + i] = sp })
  bSp.forEach((sp, i) => { species['B' + i] = sp })
  const snaps = (result.events as FieldEvent[])
    .filter((e): e is Extract<FieldEvent, { kind: 'snapshot' }> => e.kind === 'snapshot')
  return { snaps, species, result }
}

export function Arena3DPreview() {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  // ⚠️ DERIVED, NOT A TYPED-IN ID. This was `'wood-plankyard'`; retiring that board left
  // the preview pointing at a map that no longer exists, `mapById` returned undefined and
  // the effect bailed before building a scene — a blank canvas with no error, which reads
  // as a renderer fault rather than a dead reference. Nothing in the test suite covers the
  // preview, so the first arena in MAPS is the only default that cannot rot.
  const [arenaId, setArenaId] = useState(MAPS[0].id)
  const [elev, setElev] = useState(38)
  const [showHexes, setShowHexes] = useState(true)
  const [cine, setCine] = useState(false)
  const [stands, setStands] = useState(true)
  const [tier, setTier] = useState(0)
  const [team, setTeam] = useState(0)   // 0 = the arena's own size

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return
    const map = mapById(arenaId)
    if (!map) return
    // ⚠️ BEFORE ANYTHING READS IT. `FIELD_W/H` is documented mutable global state and
    // the hex coverage is derived from it — set it late and the board is generated for
    // the previous arena, which is a bug this project has already shipped once.
    // ⚠️ AN OVERRIDE, BECAUSE NO 3v3+ ARENA EXISTS TO LOOK AT YET. Bronze through Apex
    // are entirely unauthored, so the only way to judge a 5v5 ground before building
    // forty of them is to resize an existing one to the rule in `arenaGridFor`. The
    // arena's own size stays the default; this is a preview knob, not a fallback.
    const grid = team ? arenaGridFor(team) : null
    const size = grid ? hexArenaSize(grid.cols, grid.rows) : { w: map.w, h: map.h }
    setFieldSize(size.w, size.h)

    const theme = themeById(map.theme)
    const cells = showHexes
      ? fieldHexCoverage().map((c) => ({ x: c.cx, y: c.cy, zone: c.zone, playable: c.playable }))
      : []

    // A real 3v3 on this arena. The first snapshot is the starting formation, so the
    // static view and the replay's frame zero are the same picture.
    const battle = runBattle(map, 'a3d-' + arenaId)
    const first = battle.snaps[0]
    const units: Unit3D[] = first.units.map((u) => ({
      id: u.id, side: u.id[0] as 'A' | 'B',
      sprite: `/sprites/${battle.species[u.id]}.png`,
      x: u.x, y: u.y, facing: u.facing, dead: false,
    }))

    const s = createScene3D(canvas, {
      world: { w: size.w, h: size.h },
      obstacles: grid ? [] : map.obstacles,
      scenery: grid ? [] : map.scenery,
      theme,
      surface: map.surface,
      palette: paletteFor(map.theme),
      cells, units, hexSize: HEX_SIZE,
      // ⚠️ The deploy screen is a tactical grid first — see look.ts:LENS.
      lens: cine ? 'CINEMATIC' : 'BOARD',
      stadium: stands,
      venue: venueFor(tier),
    })
    s.setElevation(elev)

    // ⚠️ RENDER ON DEMAND, NOT IN A rAF LOOP. Nothing in this scene moves — it is a
    // still frame of a deployment — and a permanent loop would burn a GPU core to
    // redraw an identical image sixty times a second. The real renderer will need a
    // loop; a static preview does not.
    let raf = 0
    const draw = () => s.render()
    const onResize = () => { s.resize(); s.setElevation(elev); draw() }
    // A couple of late redraws catch the ground and sprite textures as they decode.
    draw()
    const t1 = setTimeout(draw, 120)
    const t2 = setTimeout(draw, 600)
    window.addEventListener('resize', onResize)
    // exposed so the capture harness can force a fresh frame before reading pixels
    ;(window as unknown as { __draw3d?: () => void }).__draw3d = draw
    // Capture hook: point the camera and draw one frame, synchronously, so the harness
    // can step an orbit and read the canvas between steps.
    ;(window as unknown as { __cam3d?: (e: number, a: number) => void }).__cam3d =
      (e, a) => { s.setCamera(e, a); draw() }
    // Replay hook: seek to a snapshot and draw it. WARNING: the camera is NOT touched
    // here — a battle capture is meant to show the FIGHT, and a camera that drifts
    // during it makes every motion ambiguous between the units moving and the eye
    // moving. Locked, per the brief.
    /**
     * Seek by TIME and interpolate, rather than snapping to a snapshot.
     *
     * ⚠️ WITHOUT THIS THE ANIMATION IS CAPPED AT 10 FPS, WHICH IS THE WHOLE "IT LOOKS
     * CHOPPY" PROBLEM. The sim emits a snapshot every 0.1s — that is a simulation rate,
     * not a frame rate, and stepping one snapshot per frame hard-limits the replay to
     * ten frames a second however smooth the easing curves are. Positions lerp between
     * the two bracketing snapshots; the STATE comes from the earlier one, because a
     * state is a thing that is true over an interval and blending "casting" with
     * "hurt" is meaningless.
     */
    ;(window as unknown as { __seekT3d?: (t: number) => void }).__seekT3d = (tt) => {
      const arr = battle.snaps
      const last = arr[arr.length - 1]
      const t = Math.max(arr[0].t, Math.min(last.t, tt))
      let i = 0
      while (i < arr.length - 2 && arr[i + 1].t <= t) i++
      const a = arr[i], b = arr[Math.min(arr.length - 1, i + 1)]
      const span = b.t - a.t
      const k = span > 0 ? (t - a.t) / span : 0
      const by: Record<string, (typeof b.units)[number]> = {}
      for (const u of b.units) by[u.id] = u
      s.setUnits(a.units.map((u) => {
        const n = by[u.id] ?? u
        return {
          id: u.id, side: u.id[0] as 'A' | 'B', sprite: '',
          x: u.x + (n.x - u.x) * k, y: u.y + (n.y - u.y) * k,
          facing: u.facing, state: u.state, dead: u.state === 'dead',
        }
      }), t)
      draw()
    }
    ;(window as unknown as { __seek3d?: (i: number) => number }).__seek3d = (i) => {
      const idx = Math.max(0, Math.min(battle.snaps.length - 1, i))
      const snap = battle.snaps[idx]
      // ⚠️ THE SNAPSHOT'S OWN `t` IS PASSED THROUGH, NOT THE FRAME INDEX. The animation
      // clock has to be BATTLE time: sample every fifth snapshot for a fast-forward and
      // an index-driven clock would run the bobs and lunges five times too slow, so the
      // one thing the capture is meant to show would be smeared away.
      s.setUnits(snap.units.map((u) => ({
        id: u.id, side: u.id[0] as 'A' | 'B', sprite: '',
        x: u.x, y: u.y, facing: u.facing, state: u.state, dead: u.state === 'dead',
      })), snap.t)
      draw()
      return battle.snaps.length
    }
    ;(window as unknown as { __battleInfo?: unknown }).__battleInfo = {
      snaps: battle.snaps.length, duration: battle.result.duration,
      winner: battle.result.winner,
      // per-snapshot state census, so a capture can find the busy stretch of the fight
      // rather than guessing at one
      busy: battle.snaps.map((sn) =>
        sn.units.filter((u) => u.state === 'cast' || u.state === 'hurt' || u.state === 'block').length),
    }
    return () => {
      cancelAnimationFrame(raf); clearTimeout(t1); clearTimeout(t2)
      window.removeEventListener('resize', onResize)
      s.dispose()
    }
  }, [arenaId, elev, showHexes, cine, stands, tier, team])

  return (
    <div style={{ maxWidth: 1320, margin: '0 auto', padding: 16, color: '#e9ecf3' }}>
      <h2 style={{ font: '700 15px/1.4 ui-monospace, Consolas, monospace', letterSpacing: '.08em' }}>
        BATTLEFIELD — 3D PROTOTYPE
      </h2>
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', margin: '10px 0' }}>
        <select value={arenaId} onChange={(e) => setArenaId(e.target.value)}>
          {MAPS.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
        </select>
        <label>camera {elev}°{' '}
          <input type="range" min={18} max={62} value={elev}
            onChange={(e) => setElev(+e.target.value)} />
        </label>
        <label>
          <input type="checkbox" checked={showHexes}
            onChange={(e) => setShowHexes(e.target.checked)} /> deploy hexes
        </label>
        <label>
          <input type="checkbox" checked={cine}
            onChange={(e) => setCine(e.target.checked)} /> cinematic lens
        </label>
        <label>
          <input type="checkbox" checked={stands}
            onChange={(e) => setStands(e.target.checked)} /> stadium
        </label>
        <label>
          {Object.keys(VENUE_TIER)[tier]} ({tier}){' '}
          <input type="range" min={0} max={10} value={tier}
            onChange={(e) => setTier(+e.target.value)} />
        </label>
        <label>
          board {team ? team + 'v' + team : 'as authored'}{' '}
          <input type="range" min={0} max={5} value={team}
            onChange={(e) => setTeam(+e.target.value)} />
        </label>
      </div>
      <canvas ref={canvasRef} style={{
        width: '100%', aspectRatio: '16/9', display: 'block',
        borderRadius: 12, border: '1px solid rgba(0,0,0,.35)',
        boxShadow: '0 12px 44px rgba(0,0,0,.5)',
      }} />
    </div>
  )
}
