// THE BATTLEFIELD, IN THREE DIMENSIONS.
//
// ⚠️ THIS IS A RENDERER, AND IT IS THE ONLY THING THAT CHANGES. The engine hands over
// a FINISHED simulation — positions, hp, statuses, all in flat world units — and this
// draws it. Nothing here may be imported by `engine.ts`, no golden can move because of
// anything in this file, and the 2D renderer stays alongside it so the two can be
// compared rather than argued about. `TamerArena.tsx` is a replay viewer and so is
// this; that is what makes swapping them a bounded job instead of a rewrite.
//
// ⚠️ WHY 3D AT ALL, WHEN THE SPRITES STAY 2D. The complaint was that objects look flat
// and papery, and the cause is NOT that they are 2D — it is that they receive no
// light, cast no real shadow, and are never occluded. Octopath Traveler is 2D sprites
// in a 3D scene and reads perfectly solid. So this buys the CHEAP half of 3D: the
// world. Ground, cover and lighting become real geometry (~30 static meshes, no
// rigging, no animation), while the creatures stay sprites — LIT by the scene's key
// light and casting its shadow. The expensive half of 3D is 65 rigged, animated
// creatures, and none of that is needed to fix what is actually broken.
//
// ⚠️ AXES. Engine x → three X, engine y → three Z, Y is up. The engine's `y` grows
// toward the viewer, which is what the camera sits on the +Z side to match.
import * as THREE from 'three'
import type { Obstacle, UnitVisState } from '../types'
import { groundFor, type ArenaTheme, type SurfaceId } from '../themes'
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js'
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js'
import { BokehPass } from 'three/examples/jsm/postprocessing/BokehPass.js'
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js'
import { ShaderPass } from 'three/examples/jsm/postprocessing/ShaderPass.js'
import { OutputPass } from 'three/examples/jsm/postprocessing/OutputPass.js'
import { buildProp, propMaterials, type PropPalette } from './props3d'
import { GradeShader, LENS, lookFor, type LensMode } from './look'
import { buildStadium } from './stadium'
import { venueFor, type Venue } from './venue'

export interface Unit3D {
  id: string; side: 'A' | 'B'; sprite: string; x: number; y: number
  /** −1 faces left, +1 faces right. */
  facing?: number
  /** What the unit is doing, straight off the sim's snapshot. */
  state?: UnitVisState
  dead?: boolean
}
export interface Cell3D { x: number; y: number; zone: 'A' | 'B' | 'neutral'; playable: boolean }

export interface Scene3DOpts {
  world: { w: number; h: number }
  obstacles: Obstacle[]
  /** Dressing OUTSIDE the field — trees, bushes. Drawn, never collided with. */
  scenery?: Obstacle[]
  theme: ArenaTheme
  /** This cup's floor, overriding the league's ground. See `themes.ts:SURFACES`. */
  surface?: SurfaceId
  palette: PropPalette
  cells?: Cell3D[]
  units?: Unit3D[]
  hexSize?: number
  /** Stands and crowd. Off for a quick preview; on for anything the player sees. */
  stadium?: boolean
  /** How grand the ground is — see venue.ts. Defaults to the bottom rung. */
  venue?: Venue
  /** `BOARD` keeps the deploy grid legible; `CINEMATIC` is the fight. See look.ts. */
  lens?: LensMode
}

/** How far the camera looks down at the board, from the ground plane. */
export const ELEV_DEG = 38
/** A long lens. Short ones bow a 43-unit-wide arena at the edges. */
export const FOV_DEG = 26

// The two team colours the game uses everywhere, plus a near-white for the grid. The
// neutral only ever draws as an OUTLINE, never as a fill — see the board section.
const TEAM = { A: 0x5ab0ff, B: 0xff4fa3, neutral: 0xdfe8f4 }

export function createScene3D(canvas: HTMLCanvasElement, o: Scene3DOpts) {
  const { w: W, h: H } = o.world

  const renderer = new THREE.WebGLRenderer({
    canvas, antialias: true,
    // ⚠️ NEEDED SO THE CANVAS CAN BE READ BACK. Screenshots are unavailable in this
    // environment and a WebGL scene has no DOM to probe — its pixels are the ONLY
    // queryable property it has. Without this the drawing buffer is cleared after
    // present and `toBlob` returns an empty frame. See vite.config.ts:shotPlugin.
    preserveDrawingBuffer: true,
  })
  renderer.setPixelRatio(Math.min(devicePixelRatio, 2))
  renderer.shadowMap.enabled = true
  renderer.shadowMap.type = THREE.PCFSoftShadowMap
  // ⚠️ TONE MAPPING AND COLOUR SPACE ARE MOST OF "PROFESSIONAL". Raw linear output
  // clips highlights to flat white and crushes shadows to flat black, which is the
  // single biggest tell of an untreated real-time render. ACES rolls both off.
  renderer.toneMapping = THREE.ACESFilmicToneMapping
  renderer.toneMappingExposure = 1.5
  renderer.outputColorSpace = THREE.SRGBColorSpace

  // ⚠️ EVERY LIGHT AND EVERY GRADE VALUE COMES FROM look.ts, NEVER FROM HERE. A league
  // is supposed to be nameable from a still frame; hard-coding a warm key in the
  // renderer would give all ten arenas the same lamp and undo that in one line.
  const look = lookFor(o.theme.id)
  const lens = LENS[o.lens ?? 'BOARD']

  const scene = new THREE.Scene()
  scene.background = new THREE.Color(look.voidColour)
  scene.fog = new THREE.Fog(look.voidColour, H * 2.4, H * 7.5)

  const camera = new THREE.PerspectiveCamera(FOV_DEG, 1, 0.5, 400)
  const target = new THREE.Vector3(W / 2, 0.6, H / 2)

  // ── light ────────────────────────────────────────────────────────────────
  // ⚠️ ONE KEY WITH A SHADOW IS THE ENTIRE FIX. Flat, papery objects are objects with
  // no cast shadow: nothing ties them to the floor and nothing says which way is up.
  // Everything else here is support for that one light.
  const key = new THREE.DirectionalLight(look.keyColour, look.keyIntensity)
  key.position.set(W * 0.32, Math.max(W, H) * 0.85, H * 0.95)
  key.target.position.copy(new THREE.Vector3(W / 2, 0, H / 2))
  key.castShadow = true
  key.shadow.mapSize.set(4096, 4096)   // the bowl widened the shadow camera; hold detail
  // The shadow camera is orthographic and must be fitted to the board: too wide and
  // every shadow is a soft grey smear at this map size, too narrow and cover at the
  // walls stops casting entirely.
  const span = Math.max(W, H) * 0.86
  Object.assign(key.shadow.camera, { left: -span, right: span, top: span, bottom: -span, near: 1, far: Math.max(W, H) * 3 })
  key.shadow.bias = -0.0012
  key.shadow.normalBias = 0.02
  scene.add(key, key.target)

  // Sky/bounce fill, warm from above and cool off the ground, so shadowed faces keep
  // colour instead of going to neutral grey.
  scene.add(new THREE.HemisphereLight(look.skyColour, look.bounceColour, look.ambient))
  // A dim rim from behind separates cover from the ground at the far wall.
  const rim = new THREE.DirectionalLight(look.skyColour, 0.9)
  rim.position.set(W * 0.7, Math.max(W, H) * 0.4, -H * 0.6)
  scene.add(rim)

  // ── ground ───────────────────────────────────────────────────────────────
  const floor = groundFor(o.theme, o.surface)
  const tex = new THREE.TextureLoader().load(floor.ground)
  tex.colorSpace = THREE.SRGBColorSpace
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping
  tex.anisotropy = renderer.capabilities.getMaxAnisotropy()
  // ⚠️ READ OFF `groundScale`, NOT HARDCODED. It used to be a flat `H * 0.32` with a
  // comment claiming it matched the 2D renderer — true only while every floor happened to
  // be authored near 32%. A surface with a coarser grain (flagstone at 36%) or a finer one
  // (sand at 26%) would then tile at a different size in 3D than in 2D, and the two
  // renderers would disagree about how big the ground is under identical monsters.
  const TILE = H * ((parseFloat(floor.groundScale.replace(/[^0-9.]/g, '')) || 32) / 100)
  tex.repeat.set(W / TILE, H / TILE)
  const groundMat = new THREE.MeshStandardMaterial({ map: tex, roughness: 0.94, metalness: 0 })
  /**
   * ⚠️ THE GRID IS THE TELL, AND NO AMOUNT OF TEXTURE QUALITY FIXES IT. A tiling map
   * repeats every `TILE` units, and the human eye finds that lattice instantly — one
   * distinctive knot or stone lands at 24 places in a perfect rectangular array and the
   * floor reads as wallpaper however good the tile is. The fix is not a bigger texture; it
   * is breaking the PERIOD.
   *
   * ⚠️ SAMPLED TWICE AT AN IRRATIONAL RATIO, THEN OVERLAID. The second sample runs at
   * 0.379x the repeat and is offset, so the two lattices only re-align every ~1/0.379
   * tiles — far beyond the board. Overlay (not multiply) keeps the mid-tone, so the floor
   * neither darkens nor washes out. One extra texture fetch, no second asset, and it works
   * on every ground and surface in the game rather than one hand-fixed image.
   */
  groundMat.onBeforeCompile = (sh) => {
    sh.fragmentShader = sh.fragmentShader.replace(
      '#include <map_fragment>',
      [
        'vec4 sampledDiffuseColor = texture2D( map, vMapUv );',
        'vec3 bigT = texture2D( map, vMapUv * 0.379 + vec2( 0.317, 0.113 ) ).rgb;',
        'vec3 baseT = sampledDiffuseColor.rgb;',
        // Overlay: darkens where the broad pass is dark, lifts where it is light.
        'vec3 ovl = mix( 2.0 * baseT * bigT,',
        '  1.0 - 2.0 * ( 1.0 - baseT ) * ( 1.0 - bigT ),',
        '  step( vec3( 0.5 ), baseT ) );',
        'sampledDiffuseColor.rgb = mix( baseT, ovl, 0.55 );',
        'diffuseColor *= sampledDiffuseColor;',
      ].join('\n'),
    )
  }
  const ground = new THREE.Mesh(new THREE.PlaneGeometry(W, H), groundMat)
  ground.rotation.x = -Math.PI / 2
  ground.position.set(W / 2, 0, H / 2)
  ground.receiveShadow = true
  scene.add(ground)

  // ⚠️ THE CONCOURSE, NOT THE ENVIRONMENT. This used to be the whole answer to "the
  // arena is floating in a void" — a big darkened plane and some fog. It was always a
  // stopgap: a lit slab on a dark plane still reads as an asset viewer. The STANDS are
  // the environment now (stadium.ts), and this is just the walkway they stand on.
  const yard = new THREE.Mesh(
    new THREE.PlaneGeometry(W * 5, H * 5),
    new THREE.MeshStandardMaterial({ map: tex.clone(), color: 0x3e3a35, roughness: 1 }),
  )
  const yardTex = yard.material.map!
  yardTex.wrapS = yardTex.wrapT = THREE.RepeatWrapping
  yardTex.repeat.set((W * 5) / TILE, (H * 5) / TILE)
  yardTex.needsUpdate = true
  yard.rotation.x = -Math.PI / 2
  yard.position.set(W / 2, -0.06, H / 2)
  yard.receiveShadow = true
  scene.add(yard)

  // A low wall around the board, so the arena has an edge and the eye has something
  // for the fog and the rim light to land on.
  const wallMat = new THREE.MeshStandardMaterial({ color: 0x4a4640, roughness: 0.9, flatShading: true })
  const T = 0.34, WH = 0.5     // thickness and height — a kerb, not a rampart
  for (const [x, z, sw, sd] of [[W / 2, -T / 2, W + T * 2, T], [W / 2, H + T / 2, W + T * 2, T],
    [-T / 2, H / 2, T, H], [W + T / 2, H / 2, T, H]] as const) {
    const wall = new THREE.Mesh(new THREE.BoxGeometry(sw, WH, sd), wallMat)
    wall.position.set(x, WH / 2, z)
    wall.castShadow = true; wall.receiveShadow = true
    scene.add(wall)
  }

  // ── the stadium ──────────────────────────────────────────────────────────
  if (o.stadium !== false) {
    scene.add(buildStadium({
      w: W, h: H, crowd: look.crowd, teamA: TEAM.A, teamB: TEAM.B,
      venue: o.venue ?? venueFor(0),
    }))
  }

  // ── the deploy board ─────────────────────────────────────────────────────
  // Flat hexagons laid just above the ground, one InstancedMesh for the lot so a
  // 250-cell board is a single draw call.
  // ⚠️ THE COVERAGE LIST RUNS PAST ALL FOUR WALLS AND MUST BE CLIPPED HERE. That
  // overhang exists for the 2D renderer, which crops it with `overflow:hidden` so the
  // board meets the arena wall with no bare margin. There is no crop in a 3D scene —
  // the cells simply carry on across the floor outside the arena, which is what the
  // first render showed: a board sitting inside a much larger field of loose hexes.
  const inside = (o.cells ?? []).filter((c) => c.x > 0 && c.x < W && c.y > 0 && c.y < H)
  if (inside.length) {
    const R = o.hexSize ?? 1.4
    const ring = (k: number, path: THREE.Shape | THREE.Path) => {
      for (let i = 0; i < 6; i++) {
        const a = (Math.PI / 180) * (60 * i - 90)          // pointy-top
        const x = Math.cos(a) * R * k, y = Math.sin(a) * R * k
        i ? path.lineTo(x, y) : path.moveTo(x, y)
      }
      return path
    }
    const flat = (g: THREE.BufferGeometry) => { g.rotateX(-Math.PI / 2); return g }

    // ⚠️ FILL AND OUTLINE ARE TWO PASSES, AND THAT IS NOT DECORATION. Filling every
    // cell and relying on colour alone to say which is which produced a screen that
    // reads as two coloured blocks with bare floor between them — the same failure the
    // 2D board hit, from the same cause. The OUTLINE runs across every cell so the
    // whole surface is visibly a board; the FILL is painted only where a zone actually
    // is. Grid and ownership are separate facts and want separate marks.
    //
    // ⚠️ AND THE FILL IS NORMAL-BLENDED, NOT ADDITIVE. Additive survives any ground
    // brightness, which is why it was tempting — but it can only ever ADD light, so a
    // 46% zone bleached the timber under it to pastel and a neutral cell had to be
    // near-black, i.e. invisible. Normal blending keeps the floor's own material
    // reading through the tint, which is what makes the board look laid ON something.
    const outline = new THREE.InstancedMesh(
      flat(new THREE.ShapeGeometry(
        (() => { const s = ring(0.97, new THREE.Shape()) as THREE.Shape
                 s.holes.push(ring(0.88, new THREE.Path()) as THREE.Path); return s })(),
      )),
      new THREE.MeshBasicMaterial({ transparent: true, opacity: 0.34, depthWrite: false }),
      inside.length,
    )
    const zoneCells = inside.filter((c) => c.playable && c.zone !== 'neutral')
    const fill = new THREE.InstancedMesh(
      flat(new THREE.ShapeGeometry(ring(0.9, new THREE.Shape()) as THREE.Shape)),
      new THREE.MeshBasicMaterial({ transparent: true, opacity: 0.26, depthWrite: false }),
      Math.max(1, zoneCells.length),
    )
    fill.count = zoneCells.length

    const m4 = new THREE.Matrix4(); const col = new THREE.Color()
    inside.forEach((c, i) => {
      outline.setMatrixAt(i, m4.makeTranslation(c.x, 0.035, c.y))
      const live = c.playable && c.zone !== 'neutral'
      outline.setColorAt(i, col.setHex(live ? TEAM[c.zone as 'A' | 'B'] : TEAM.neutral))
    })
    zoneCells.forEach((c, i) => {
      fill.setMatrixAt(i, m4.makeTranslation(c.x, 0.03, c.y))
      fill.setColorAt(i, col.setHex(TEAM[c.zone as 'A' | 'B']))
    })
    scene.add(fill, outline)
  }

  // ── cover ────────────────────────────────────────────────────────────────
  // ⚠️ THE VENUE'S MASONRY IS FOLDED INTO THE PROP PALETTE, so arena furniture is built
  // from the same stone as the stands and climbs the ladder with them.
  const venue = o.venue ?? venueFor(0)
  const mats = propMaterials({
    ...o.palette, stone: venue.masonry, stoneTrim: venue.masonryTrim,
    // Gilt only from Gold up, matching `masonryTrim`'s own step — below that a capping
    // course is stone and must not read as metal.
    stoneMetal: venue.tier >= 6 ? venue.trimMetal : 0.1,
  })
  /**
   * ⚠️ THE BOARDS READ AS "TOO SYMMETRICAL" BECAUSE THEY ARE, AND THAT IS NOT AN AUTHORING
   * MISTAKE — IT IS THE FAIRNESS INVARIANT. `maps.ts:mirror` derives every obstacle's
   * 180°-rotated partner so an arena cannot favour a side, which also means every piece has
   * a twin at the same distance on the opposite diagonal. Reducing the piece count helps
   * and has been done three times; it cannot fix the cause, because the cause is a
   * guarantee we want to keep.
   *
   * ⚠️ SO BREAK IT IN THE RENDERER, WHERE IT COSTS NOTHING. The engine knows RECTANGLES —
   * `x, y, w, h` — and nothing else. Inside that rectangle the mesh may be turned, tipped
   * and resized freely: the footprint a monster collides with is identical for both twins,
   * while the objects standing in them are visibly not the same object. A pair of ore bins
   * stops being a reflection and becomes two bins someone put down.
   *
   * ⚠️ HASHED OFF POSITION, NEVER `Math.random()`. The whole scene is rebuilt on a resize,
   * an arena change or a lens toggle; a random jitter would make every prop on the board
   * hop each time. Hashing the world position means the same board always looks the same.
   */
  const jitter = (x: number, y: number, salt: number) => {
    const n = Math.sin(x * 12.9898 + y * 78.233 + salt * 37.719) * 43758.5453
    return n - Math.floor(n)
  }
  for (const ob of o.obstacles) {
    const g = buildProp(ob.kind, mats, ob.w, ob.h)
    const cx = ob.x + ob.w / 2, cz = ob.y + ob.h / 2
    const a = jitter(cx, cz, 1), b = jitter(cx, cz, 2), c = jitter(cx, cz, 3)
    // Yaw is the one that does the work; a few degrees is enough to kill a reflection and
    // little enough that a long piece still reads as lying along its own footprint.
    g.rotation.y = (a - 0.5) * 0.20
    // ⚠️ SCALE ONLY IN X AND Y, NEVER Z. `buildProp` has already squeezed the group's depth
    // to the authored footprint — that is the invariant that stopped cover drawing deeper
    // than the thing you collide with — and scaling Z here would undo it silently.
    g.scale.x *= 0.94 + b * 0.12
    g.scale.y *= 0.93 + c * 0.14
    g.position.set(cx, 0, cz)
    scene.add(g)
  }
  // ⚠️ SAME BUILDER, SEPARATE LIST, AND THE SEPARATION IS THE POINT. Scenery stands in the
  // trackway ring outside the field; the engine has never heard of it. Drawing it from
  // `obstacles` would have been one line fewer and would have added cover to every board
  // that got prettier.
  for (const sc of o.scenery ?? []) {
    const g = buildProp(sc.kind, mats, sc.w, sc.h)
    g.position.set(sc.x + sc.w / 2, 0, sc.y + sc.h / 2)
    scene.add(g)
  }

  // ── units: sprites that are LIT and CAST SHADOW ──────────────────────────
  // ⚠️ UPRIGHT, AND STRETCHED BY 1/cos(ELEV). A vertical plane seen from 38° above is
  // foreshortened to cos(38°) = 79% of its height, so a monster authored at the right
  // size renders squat. Tilting the plane back to face the camera instead would lift
  // its feet off the ground and undo the contact the shadow just bought.
  const loader = new THREE.TextureLoader()
  const upScale = 1 / Math.cos((ELEV_DEG * Math.PI) / 180)
  // ⚠️ BUILT ONCE, MOVED EVERY FRAME. A battle replay is ~250 snapshots; rebuilding
  // six sprites, six materials and six textures per snapshot would re-decode the same
  // PNGs 1500 times and stutter on every one. The roster is fixed for a fight, so the
  // meshes are too — `setUnits` only ever writes positions and states onto them.
  // ⚠️ `phase` AND `since` ARE RENDERER STATE, AND THEY HAVE TO BE. Animation needs to
  // know how long a unit has been doing what it is doing — a lunge is a curve over ~0.3s,
  // not a property of one instant — and the sim's snapshot carries no such thing, nor
  // should it: `state` is a fact about the fight, timing is a fact about the drawing.
  // ⚠️ AND `phase` IS HASHED FROM THE ID. Without a per-unit offset every monster on the
  // board breathes in perfect unison, which reads as a screensaver rather than as six
  // animals. Hashed, not rolled, so a replay scrubbed backwards looks identical.
  interface Live {
    plane: THREE.Mesh; ring: THREE.Mesh; h: number
    phase: number; state: UnitVisState; since: number
    /** Eased, so a turn is a turn and not a one-frame mirror flip. */
    face: number
  }
  const live: Record<string, Live> = {}
  for (const u of o.units ?? []) {
    const t = loader.load(u.sprite)
    t.colorSpace = THREE.SRGBColorSpace
    const hgt = 3.0 * upScale
    const plane = new THREE.Mesh(
      new THREE.PlaneGeometry(3.0, hgt),
      new THREE.MeshStandardMaterial({
        map: t, roughness: 1, metalness: 0,
        // ⚠️ THE ART IS ITS OWN FLOOR LIGHT. A sprite lit ONLY by the scene goes to
        // near-black wherever the key does not reach, and these are 320px portraits
        // with their own baked shading — losing them to shadow throws away the art the
        // game already has. A low emissive from the same map keeps them readable while
        // the key still does the work of tying them to the floor.
        emissiveMap: t, emissive: 0xffffff, emissiveIntensity: 0.42,
        // ⚠️ alphaTest, NOT transparent. A transparent material does not write depth,
        // so two overlapping monsters sort by draw order and flicker as they move —
        // and it would not cast a shaped shadow, only a rectangle.
        alphaTest: 0.5, side: THREE.DoubleSide,
      }),
    )
    plane.position.set(u.x, hgt / 2, u.y)
    plane.castShadow = true
    scene.add(plane)

    // The team ring is a mark ON the ground, exactly as in the 2D renderer, and for
    // the same reason: both sides can field the same species.
    const ring = new THREE.Mesh(
      new THREE.RingGeometry(0.72, 0.95, 24),
      new THREE.MeshBasicMaterial({ color: TEAM[u.side], transparent: true, opacity: 0.75, depthWrite: false }),
    )
    ring.rotation.x = -Math.PI / 2
    ring.position.set(u.x, 0.04, u.y)
    scene.add(ring)
    const hash = [...u.id].reduce((a, ch) => a * 31 + ch.charCodeAt(0), 7) % 1000
    live[u.id] = { plane, ring, h: hgt, phase: (hash / 1000) * 6.28, state: 'idle', since: 0, face: 1 }
  }

  // ── camera fit ───────────────────────────────────────────────────────────
  // ⚠️ FITTED BY PROJECTION, NOT BY A BOUNDING SPHERE. A sphere fit is conservative
  // for any rotation, and our boards are wide and shallow — the sphere's radius is
  // half the WIDTH, so fitting it vertically would push the camera far enough back to
  // waste most of the frame. Projecting the eight box corners and rescaling converges
  // in a few passes and frames each arena's real shape.
  // ⚠️ THE FIT BOX IS STILL THE BOARD, NOT THE BOWL, AND THAT IS DELIBERATE. Framing
  // the whole stadium would shrink the playing surface to a postage stamp in the middle
  // of a lot of seating — the stands are BACKGROUND, and background is allowed to run
  // off the edges of the frame. A small margin lets the front rows and the barrier in.
  const box = new THREE.Box3(new THREE.Vector3(-0.5, 0, -0.5), new THREE.Vector3(W + 0.5, 2.2, H + 0.5))
  const corners = [0, 1].flatMap((i) => [0, 1].flatMap((j) => [0, 1].map((k) =>
    new THREE.Vector3(i ? box.max.x : box.min.x, j ? box.max.y : box.min.y, k ? box.max.z : box.min.z))))
  const elev = (ELEV_DEG * Math.PI) / 180
  let dist = Math.max(W, H) * 1.2
  const place = () => {
    camera.position.set(W / 2, Math.sin(elev) * dist + 0.6, H / 2 + Math.cos(elev) * dist)
    camera.lookAt(target)
    camera.updateMatrixWorld(); camera.updateProjectionMatrix()
  }
  const fit = (margin: number) => {
    for (let pass = 0; pass < 6; pass++) {
      place()
      let worst = 0
      for (const c of corners) {
        const p = c.clone().project(camera)
        worst = Math.max(worst, Math.abs(p.x), Math.abs(p.y))
      }
      dist *= worst / margin
    }
    place()
  }

  // ── the lens ─────────────────────────────────────────────────────────────
  // ⚠️ THIS IS THE PART THAT MAKES IT LOOK LIKE A GAME AND NOT AN ASSET VIEWER, and no
  // amount of detail on the meshes substitutes for it. HD-2D reads the way it does
  // because the frame is PHOTOGRAPHED: the near and far of the board fall out of focus,
  // highlights bleed, and the image is graded warm-in-light and cool-in-shadow.
  // Untreated, the same geometry under the same lights is uniformly sharp, uniformly
  // lit and uniformly present, which is exactly how a model viewer looks.
  const composer = new EffectComposer(renderer)
  composer.addPass(new RenderPass(scene, camera))
  // Depth of field. Focus rides the camera distance so the MIDDLE of the board is
  // always sharp — see look.ts for why the deploy screen gets a much weaker aperture.
  const bokeh = new BokehPass(scene, camera, {
    focus: 1, aperture: lens.dofAperture, maxblur: lens.dofBlur,
  })
  composer.addPass(bokeh)
  const bloom = new UnrealBloomPass(new THREE.Vector2(1, 1), lens.bloom, 0.6, 0.82)
  composer.addPass(bloom)
  const grade = new ShaderPass(GradeShader)
  grade.uniforms.shadowTint.value.set(...look.shadowTint)
  grade.uniforms.highlightTint.value.set(...look.highlightTint)
  grade.uniforms.saturation.value = look.saturation
  grade.uniforms.vignette.value = lens.vignette
  composer.addPass(grade)
  // ⚠️ OutputPass LAST, AND IT IS WHAT APPLIES THE TONE MAPPING NOW. With a composer
  // the renderer's own tone mapping no longer runs on the final image; drop this and
  // the whole frame comes out linear — blown highlights, crushed blacks, exactly the
  // untreated-render look the grade is there to avoid.
  composer.addPass(new OutputPass())

  const resize = () => {
    const wpx = canvas.clientWidth || 800
    const hpx = canvas.clientHeight || 450
    renderer.setSize(wpx, hpx, false)
    composer.setSize(wpx, hpx)
    bloom.setSize(wpx, hpx)
    camera.aspect = wpx / hpx
    dist = Math.max(W, H) * 1.2
    fit(lens.fit)   // DEPLOY fills the panel with the board; REPLAY pulls back for the bowl
    ;(bokeh.uniforms as Record<string, { value: number }>).focus.value = dist
  }
  resize()

  return {
    render: () => composer.render(),
    resize,
    /**
     * Move the cast. Called once per replay frame.
     *
     * ⚠️ FACING IS `scale.x`, NOT A ROTATION. The sprites are billboards standing
     * square to a fixed camera; rotating one to face left would turn it edge-on and it
     * would vanish. Mirroring the plane is what "turning round" means for a billboard,
     * and it is the same trick the 2D renderer uses (`scaleX(facing)`).
     */
    /**
     * Move and animate the cast. `t` is battle time in seconds.
     *
     * ⚠️ PROCEDURAL, NOT FRAME-SWAPPED, AND THAT IS A DELIBERATE CALL. Only FIVE of the
     * sixty-five species have a drawn frame set (`BATTLE_SPRITE_SET` — the Mammals), so
     * an animation system built on frames would animate one monster in six on this very
     * demo and would not exist for the game at all. That is exactly the authored-but-
     * unreachable failure this project keeps hitting. Bob, lean, lunge, flinch and
     * crouch are computed from `state` and time, so all 65 species animate today; where
     * frames DO exist they can be layered on top later as a strict upgrade.
     */
    setUnits: (list: Unit3D[], t = 0) => {
      for (const u of list) {
        const e = live[u.id]
        if (!e) continue
        const st: UnitVisState = u.dead ? 'dead' : (u.state ?? 'idle')
        // A state CHANGE starts the clock — this is what makes a cast a one-shot lunge
        // instead of a permanent pose.
        if (st !== e.state) { e.state = st; e.since = t }
        const age = Math.max(0, t - e.since)
        const ph = t * 1.0 + e.phase
        const mat = e.plane.material as THREE.MeshStandardMaterial

        e.plane.visible = true
        // ⚠️ THE TURN IS EASED, NOT SNAPPED. `scale.x` flipping between −1 and 1 in one
        // frame is a mirror, and a monster that mirrors instantly reads as a sprite
        // being flipped rather than as an animal turning round. Easing it pushes the
        // plane through zero width, which is exactly what a turn looks like on a
        // billboard — and it costs one lerp.
        const want = u.facing != null && u.facing < 0 ? -1 : 1
        e.face += (want - e.face) * 0.34
        const face = Math.abs(e.face) < 0.06 ? Math.sign(e.face || want) * 0.06 : e.face
        const dir = want
        let dx = 0, dy = 0, roll = 0, sx = 1, sy = 1, flash = 0

        switch (st) {
          case 'idle':
            // Breathing. Tiny — the point is that a still unit is not FROZEN.
            dy = Math.sin(ph * 2.1) * e.h * 0.012
            sy = 1 + Math.sin(ph * 2.1) * 0.018
            break
          case 'move': {
            // A hop, with squash on the landing. `abs(sin)` gives the double-bounce of
            // a gait rather than the float of a plain sine.
            const b = Math.abs(Math.sin(ph * 5.2))
            dy = b * e.h * 0.055
            sy = 1 + b * 0.05 - 0.03
            sx = 1 - b * 0.04 + 0.02
            roll = -dir * 0.05                     // lean into the run
            break
          }
          case 'cast': {
            // Rear back, then drive forward. One arc over ~0.36s, held at rest after.
            const k = Math.min(1, age / 0.36)
            const arc = Math.sin(k * Math.PI)
            dx = dir * (arc * 0.55 - (k < 0.25 ? 0.25 : 0))
            dy = arc * e.h * 0.04
            sx = 1 + arc * 0.10
            sy = 1 + arc * 0.06
            roll = -dir * arc * 0.10
            break
          }
          case 'hurt': {
            // Knocked back and shaken, decaying out. The flash is on the EMISSIVE, not
            // the colour, so a dark sprite flinches as visibly as a bright one.
            const k = Math.min(1, age / 0.3), decay = 1 - k
            dx = -dir * decay * 0.34
            dy = Math.sin(k * 26) * decay * e.h * 0.02
            roll = dir * decay * 0.16
            // An impact POP on top of the shake. A hit that only moves a unit reads as a
            // shove; the squash is what says something landed on it.
            sx = 1 + decay * 0.14
            sy = 1 - decay * 0.10
            flash = decay * 1.5
            break
          }
          case 'block': {
            // Braced: crouched, squat, leaning away from the blow.
            const k = Math.min(1, age / 0.18)
            sy = 1 - k * 0.10
            sx = 1 + k * 0.07
            dy = -e.h * 0.03 * k
            roll = dir * k * 0.09
            break
          }
          case 'dead': {
            // ⚠️ FALLS OVER, RATHER THAN SNAPPING FLAT. A body that pops to horizontal
            // in one frame reads as a rendering glitch; a quarter-second topple reads as
            // a death, and it also tells you WHEN it happened, which a static pose does
            // not. It stays on the board either way — vanishing would lose the count.
            const k = Math.min(1, age / 0.42)
            const e2 = k * k * (3 - 2 * k)          // smoothstep, so it settles
            roll = dir * e2 * Math.PI * 0.46
            dy = -e.h * 0.38 * e2
            break
          }
        }

        e.plane.position.set(u.x + dx, e.h / 2 + dy, u.y)
        e.plane.rotation.z = roll
        e.plane.scale.set(face * sx, sy, 1)
        // ⚠️ THE RING STAYS ON THE GROUND WHILE THE UNIT HOPS. It is a mark on the
        // floor, not a badge attached to the sprite — carrying it up with the bob would
        // detach both from the surface and undo the contact the shadow buys.
        e.ring.position.set(u.x, 0.04, u.y)
        const ringMat = e.ring.material as THREE.MeshBasicMaterial
        // Fades out as the body falls, rather than vanishing on the frame of death.
        ringMat.opacity = st === 'dead' ? Math.max(0, 0.75 - age / 0.42 * 0.75) : 0.75
        e.ring.visible = ringMat.opacity > 0.02
        mat.emissiveIntensity = st === 'dead' ? 0.16 : 0.42 + flash
        mat.color.setScalar(st === 'dead' ? 0.45 : 1)
      }
    },
    /**
     * Point the camera: `elev` is the angle above the ground, `az` swings it around
     * the board's centre (0 = square on from the near side).
     *
     * ⚠️ THE ORBIT IS NOT A GAMEPLAY FEATURE. It exists so a still scene can be shown
     * MOVING — a slow swing is the only way to demonstrate that this is real geometry
     * and not another flat picture, which is the exact question the last three renderer
     * attempts kept failing. The shipped camera is fixed; see look.ts.
     */
    setCamera: (elev: number, az = 0) => {
      const e = (elev * Math.PI) / 180, a = (az * Math.PI) / 180
      const ground = Math.cos(e) * dist
      camera.position.set(
        W / 2 + Math.sin(a) * ground,
        Math.sin(e) * dist + 0.6,
        H / 2 + Math.cos(a) * ground,
      )
      camera.lookAt(target); camera.updateProjectionMatrix()
      ;(bokeh.uniforms as Record<string, { value: number }>).focus.value = dist
    },
    setElevation: (deg: number) => {
      const e = (deg * Math.PI) / 180
      camera.position.set(W / 2, Math.sin(e) * dist + 0.6, H / 2 + Math.cos(e) * dist)
      camera.lookAt(target); camera.updateProjectionMatrix()
      ;(bokeh.uniforms as Record<string, { value: number }>).focus.value = dist
    },
    dispose: () => {
      scene.traverse((n) => {
        const m = n as THREE.Mesh
        if (m.isMesh) {
          m.geometry.dispose()
          const mm = m.material as THREE.Material | THREE.Material[]
          Array.isArray(mm) ? mm.forEach((x) => x.dispose()) : mm.dispose()
        }
      })
      composer.dispose()
      renderer.dispose()
    },
  }
}
