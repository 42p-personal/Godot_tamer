// ARENA ART vs ARENA GEOMETRY — the two must agree, and only the files can say so.
//
// ⚠️ THIS READS THE ACTUAL PNGs. Every other arena check is pure data, so it cannot
// see the one mismatch that is invisible in the numbers: a prop whose natural shape
// cannot cover the footprint it was assigned. The renderer draws each sprite at the
// footprint's WIDTH and lets its natural aspect set the height, so a wide prop on a
// deep footprint draws SHORTER than the ground it blocks — the player sees walkable
// floor inside solid cover, and pathing that looks broken when it is correct.
//
// Caught two live authoring errors on its first run: a 1.6x2.8 log stack (a prop
// 2.9x wider than tall) and a 3.2x1.8 handcart.
import { describe, it, expect } from 'vitest'
import { LOOKS, PALETTES } from './three/look'
import { readFileSync, existsSync } from 'node:fs'
import { MAPS } from './maps'
import { SURFACES, THEMES, propSprite, themeById } from './themes'

/** PNG dimensions straight from the IHDR chunk — no image library needed. */
function pngSize(file: string): { w: number; h: number } {
  const b = readFileSync(file)
  return { w: b.readUInt32BE(16), h: b.readUInt32BE(20) }
}
const publicPath = (url: string) => 'public' + url

describe('arena props can cover the footprints they are given', () => {
  it('every referenced sprite exists on disk', () => {
    for (const t of Object.values(THEMES)) {
      for (const url of Object.values(t.props)) {
        expect(existsSync(publicPath(url!)), `${t.id}: missing ${url}`).toBe(true)
      }
    }
  })

  it('no obstacle is deeper than its prop can draw', () => {
    for (const m of MAPS.filter((x) => x.leagues.length)) {
      const theme = themeById(m.theme)
      for (const o of m.obstacles) {
        const url = propSprite(theme, o.kind)
        if (!existsSync(publicPath(url))) continue
        const { w: sw, h: sh } = pngSize(publicPath(url))
        // Drawn height = footprint width / sprite aspect. It must reach at least the
        // footprint's depth, or the cover is visibly shallower than it really is.
        const drawnH = o.w / (sw / sh)
        expect(drawnH, `${m.id}: ${o.kind} ${o.w}x${o.h} draws only ${drawnH.toFixed(2)} tall`)
          .toBeGreaterThanOrEqual(o.h - 1e-6)
      }
    }
  })

  // ⚠️ ARCHITECTURE IS ALLOWED TO BE TALL; COVER IS NOT. A wall, a heap or a stack is
  // something you shoot OVER, and one that dwarfs a monster stops reading as cover and
  // starts hiding the fight — that is what the 3.4 ceiling is for. A pillar, a gateway or
  // an obelisk is something you shoot PAST: being twice a monster's height is the whole
  // point of it, and the same ceiling made them unusable rather than safe. The pillar
  // sprite is a tall portrait, so at 3.4 its footprint could be 0.78 units wide — a
  // needle, on a sixty-unit board.
  // ⚠️ A COLONNADE IS ARCHITECTURE, NOT COVER. At 13 units wide it draws 4.3 — over
  // the 3.4 cover ceiling on purpose, for the same reason a gateway is: you shoot PAST
  // it, through the gaps between its shafts, rather than over the top of it.
  const UPRIGHT = new Set(['pillar', 'brokenpillar', 'gate', 'obelisk',
    'colonnade', 'brokencolonnade',
    // A topiary standard and an arbour are both things you shoot PAST, not over — same
    // class as a pillar and a gateway, which is exactly what they are with leaves on.
    'topiary', 'arbour'])

  it('no prop towers over a monster', () => {
    // ⚠️ THE OTHER END OF THE SAME MISTAKE. Nothing stops a very wide footprint on a
    // tall prop drawing a fence four storeys high. A battle sprite stands 3.4 world
    // units; cover that dwarfs it stops reading as cover and starts hiding the fight.
    for (const m of MAPS.filter((x) => x.leagues.length)) {
      const theme = themeById(m.theme)
      for (const o of m.obstacles) {
        const url = propSprite(theme, o.kind)
        if (!existsSync(publicPath(url))) continue
        const { w: sw, h: sh } = pngSize(publicPath(url))
        const cap = UPRIGHT.has(o.kind ?? '') ? 7.0 : 3.4
        expect(o.w / (sw / sh), `${m.id}: ${o.kind} draws taller than its kind allows`)
          .toBeLessThan(cap)
      }
    }
  })
})

describe('a theme must be authored for BOTH renderers', () => {
  // ⚠️ BRONZE SHIPPED INVISIBLE TO THE 3D SCENE, AND NOTHING COMPLAINED. `themes.ts`
  // gained `alloyfloor` and `bellyard`, the 2D board drew them correctly, and the 3D
  // renderer silently fell back to the proving ground's GRASS lighting and the
  // plankyard's TIMBER prop colours — so a bronze foundry rendered as a green field
  // full of wooden crates, and the only reason it was caught is that a human looked.
  // Three tables have to agree; a fallback is right for the renderer and wrong for the
  // author, exactly as `mapProblems` already says about unknown themes.
  it('every theme in THEMES has a look and a prop palette', () => {
    const missing: string[] = []
    for (const id of Object.keys(THEMES)) {
      if (!LOOKS[id]) missing.push(`${id}: no entry in look.ts LOOKS`)
      if (!PALETTES[id]) missing.push(`${id}: no entry in look.ts PALETTES`)
    }
    expect(missing).toEqual([])
  })
})

describe('surfaces', () => {
  // ⚠️ A SURFACE IS AUTHORED IN maps.ts AND DRAWN FROM public/ — the type system proves
  // the id is spelled right and proves nothing at all about whether the image exists.
  // An arena naming a surface whose file is missing renders a BLANK floor, which reads as
  // a rendering bug rather than as missing art, and only the disk can tell the difference.
  it('every surface has its texture on disk', () => {
    const missing: string[] = []
    for (const [id, s] of Object.entries(SURFACES)) {
      if (!existsSync(publicPath(s.ground))) missing.push(`${id}: missing ${s.ground}`)
    }
    expect(missing).toEqual([])
  })

  // ⚠️ THE 3D SCENE PARSES THIS STRING to size its ground tile, so a value it cannot read
  // silently falls back to 32% and the two renderers disagree about how big the floor is
  // under identical monsters. Held to the same `auto NN%` shape every theme uses.
  it('every surface scale is a percentage the 3D scene can parse', () => {
    for (const [id, s] of Object.entries(SURFACES)) {
      expect(s.groundScale, id).toMatch(/^auto \d+%$/)
    }
  })
})
