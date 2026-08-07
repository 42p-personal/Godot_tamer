// A PLAYABLE TEST BENCH for the tamerengine fight screen — pick a size, pick a
// matchup, watch it. Reachable via the `?tamerarena` dev route (see main.tsx).
// NOT part of the tournament flow.
//
// ⚠️ THE CONTROLS EXIST TO REPRODUCE SPECIFIC THINGS, not to be configurable for
// its own sake. Each one reaches a case that replaying one fixed 3v3 cannot:
//
//   1v1     — every unit is alone from t=0, so this is the only way to watch the
//             last-monster-standing rule across a WHOLE fight rather than in the
//             last few seconds of a team fight.
//   MIRROR  — identical species AND identical seeds on both sides, so the teams
//             are indistinguishable except by team colour. If the ground rings or
//             roster tints are wrong, this is where it shows; a mixed matchup
//             hides the fault behind "that one's the big ape".
//   5v5     — the league cap, and the busiest the roster columns ever get.
//
// ⚠️ QUICK FIGHT SKIPS DEPLOY ON PURPOSE. Hand-placing five monsters before every
// look at a render change is friction that stops you looking. The deploy path is
// still here because the ORDERS set there are what the field decider reads, and
// that is worth exercising deliberately — just not on every reload.
import { useMemo, useState } from 'react'
import type { CSSProperties } from 'react'
import { generateMonster } from '../monster'
import { simulateFieldBattle } from './engine'
import { setFieldSize } from './types'
import { ArenaMap, arenasForLeague } from './maps'
import { autoDeployByRole } from './hex'
import { Monster } from '../core'
import { TamerArena } from './TamerArena'
import { Deploy, DeployMonster, DeployResult } from './Deploy'

// ⚠️ REAL LEAGUE ARENAS, not a hand-rolled obstacle list. The bench used to fight
// on six blocks invented here, which meant it could not show what an arena actually
// looks like — the one thing you come to a bench to check.
const ARENAS: ArenaMap[] = arenasForLeague('Wood')
// ⚠️ THE FIVE WITH REAL BATTLE SPRITES (`BATTLE_SPRITE_SET`). Any species renders,
// but the other 60 fall back to a static portrait with no walk cycle — which reads
// as a broken renderer when you are here to look at the renderer.
const ROSTER = ['kongrath', 'maneleo', 'grivvel', 'aegisox', 'ursath']
const SIZES = [1, 2, 3, 4, 5]
const build = (sp: string, seed: string): Monster =>
  generateMonster(seed, { speciesId: sp, train: 850 }) as Monster

export function TamerArenaDemo() {
  const [n, setN] = useState(1)
  const [size, setSize] = useState(3)
  const [mirror, setMirror] = useState(false)
  const [deployed, setDeployed] = useState<DeployResult | null>(null)
  const [quick, setQuick] = useState(false)
  const [arenaIdx, setArenaIdx] = useState(0)
  const arena = ARENAS[arenaIdx] ?? ARENAS[0]
  // ⚠️ SET BEFORE ANYTHING RENDERS, NOT INSIDE THE FIGHT'S MEMO. It used to be set
  // only when the fight was built — i.e. AFTER the deploy screen had already laid
  // its grid out at whatever size was left over, usually the 40x22 default. You then
  // placed a formation on one map and fought on another; on an 18-tall arena the
  // bottom row of that grid is off the field and the engine clamps it to the edge.
  setFieldSize(arena.w, arena.h)

  const teams = useMemo(() => {
    const seed = 'demo' + n + 'x' + size + (mirror ? 'm' : '')
    const aSpecies = ROSTER.slice(0, size)
    // Offset so the sides differ below 5v5. In MIRROR they share the species list
    // AND the per-monster seed, so the two teams are genuinely identical.
    const bSpecies = mirror ? aSpecies : aSpecies.map((_, i) => ROSTER[(i + 2) % ROSTER.length])
    const teamA = aSpecies.map((s, i) => build(s, seed + 'a' + i))
    const teamB = bSpecies.map((s, i) => build(s, mirror ? seed + 'a' + i : seed + 'b' + i))
    return { seed, teamA, teamB, aSpecies, bSpecies }
  }, [n, size, mirror])

  const deployTeam: DeployMonster[] = teams.teamA.map((m, i) => ({
    id: 'A' + i, name: m.name, species: teams.aSpecies[i],
  }))

  const fight = useMemo(() => {
    if (!deployed && !quick) return null
    const { seed, teamA, teamB, aSpecies, bSpecies } = teams
    // The size is already set for this arena (see the component body) — the sim,
    // the deploy grid and the renderer all read the same one.
    // The player's pre-battle orders ride on each monster's `.tactics` — this is
    // what the field decider reads, so the plan set on the deploy screen bites.
    const teamAO = deployed ? teamA.map((m, i) => ({ ...m, tactics: deployed.tactics[i] })) : teamA
    // Auto-deploy by role puts the sturdier monsters in front.
    const byRole = (t: Monster[], side: 'A' | 'B') => autoDeployByRole(side,
      t.map((m) => ({ front: m.stats.CON + m.stats.STR - m.stats.INT - m.stats.WIS })))
    const speciesById: Record<string, string> = {}
    const namesById: Record<string, string> = {}
    aSpecies.forEach((s, i) => { speciesById['A' + i] = s; namesById['A' + i] = teamA[i].name })
    bSpecies.forEach((s, i) => { speciesById['B' + i] = s; namesById['B' + i] = teamB[i].name })
    const result = simulateFieldBattle({
      seed, teamA: teamAO, teamB, obstacles: arena.obstacles,
      placeA: deployed ? deployed.placeA : byRole(teamA, 'A'), placeB: byRole(teamB, 'B'),
    })
    return { result, speciesById, namesById }
  }, [deployed, quick, teams, arena])

  const back = () => { setDeployed(null); setQuick(false) }
  // ⚠️ EVERY SETTING CHANGE DROPS BACK TO SETUP. Switching size mid-fight would
  // leave a result on screen that no longer matches the controls above it.
  const change = (fn: () => void) => { back(); fn() }

  const btn = (on: boolean): CSSProperties => ({
    font: '600 12px/1 ui-monospace, monospace', letterSpacing: '.05em', textTransform: 'uppercase',
    color: on ? '#12141b' : '#e9ecf3', background: on ? '#f0a23a' : '#1b1f2a',
    border: '1px solid ' + (on ? '#f0a23a' : '#2c3342'), borderRadius: 6,
    padding: '9px 13px', cursor: 'pointer',
  })
  const label: CSSProperties = {
    font: '600 11px/1 ui-monospace, monospace', letterSpacing: '.08em',
    textTransform: 'uppercase', color: '#8a93a7',
  }

  return (
    <div style={{ minHeight: '100vh', background: '#12141b', color: '#e9ecf3', padding: '24px 16px' }}>
      <div style={{ maxWidth: 1320, margin: '0 auto' }}>
        <p style={{ ...label, margin: '0 0 6px' }}>tamerengine · dev route</p>
        <h1 style={{ fontSize: 34, fontWeight: 800, letterSpacing: '-.03em', margin: '0 0 4px' }}>
          {fight ? 'TamerArena' : 'Test bench'}
        </h1>
        <p style={{ color: '#8a93a7', margin: '0 0 16px', maxWidth: '64ch' }}>
          {fight
            ? `${arena.name} — ${arena.w}×${arena.h}. ${arena.brief}`
            : 'Pick a matchup and fight it. MIRROR gives both sides identical monsters, so colour is the only thing telling them apart. 1v1 runs a whole fight with every unit already alone.'}
        </p>

        <div style={{ display: 'flex', gap: 8, alignItems: 'center', flexWrap: 'wrap', marginBottom: 18 }}>
          <span style={label}>Size</span>
          {SIZES.map((s) => (
            <button key={s} style={btn(size === s)} onClick={() => change(() => setSize(s))}>{s}v{s}</button>
          ))}
          <button style={{ ...btn(mirror), marginLeft: 8 }} onClick={() => change(() => setMirror((m) => !m))}>
            ⚖ Mirror {mirror ? 'on' : 'off'}
          </button>
          <span style={{ ...label, marginLeft: 8 }}>Arena</span>
          {ARENAS.map((a, i) => (
            <button key={a.id} style={btn(arenaIdx === i)} title={`${a.brief} · ${a.w}×${a.h}`}
              onClick={() => change(() => setArenaIdx(i))}>{a.name}</button>
          ))}
          <span style={{ flex: 1 }} />
          <button style={btn(false)} onClick={() => change(() => setN((v) => v + 1))}>🎲 Reroll</button>
          {!fight
            ? <button style={btn(true)} onClick={() => setQuick(true)}>▶ Quick fight</button>
            : <button style={btn(false)} onClick={back}>← Setup</button>}
        </div>

        {!fight && (
          <>
            <p style={{ ...label, margin: '0 0 8px' }}>
              …or place them yourself — the orders set here reach the sim
            </p>
            {/* ⚠️ KEYED ON THE MATCHUP. Deploy holds its placements in its own
                state; without the key, changing size leaves stale hexes for
                monsters that no longer exist and FIGHT never enables again. */}
            <Deploy key={`${arena.id}-${size}-${mirror}-${n}`} team={deployTeam} onStart={setDeployed} map={arena} />
          </>
        )}

        {fight && (
          <TamerArena
            result={fight.result} speciesById={fight.speciesById} namesById={fight.namesById}
            obstacles={arena.obstacles} map={arena}
            teamAName="Your team" teamBName={mirror ? 'Mirror' : 'Rivals'}
          />
        )}
      </div>
    </div>
  )
}
