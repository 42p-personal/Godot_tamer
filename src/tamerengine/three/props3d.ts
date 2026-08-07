// COVER, AS ACTUAL GEOMETRY.
//
// ⚠️ THESE ARE MODELLED, NOT DRAWN, AND THAT IS THE WHOLE POINT. A barrel sprite is a
// picture of a barrel from one angle; a barrel MESH is a barrel. The first has a
// single correct viewpoint and looks like a card from every other one — which is
// exactly what "the objects look 2d on the tilted plane" was reporting. Tilting the
// floor could never fix it, because at 46° you should be able to see the TOP of the
// barrel and a side elevation has no top to show.
//
// ⚠️ PROCEDURAL, NOT AUTHORED ASSETS, AND THAT IS A DELIBERATE TRADE. Every object
// the leagues need is an industrial primitive — barrels, crates, stumps, log stacks,
// ingots, ore piles, crucibles. Lathes, boxes and cylinders describe all of them
// exactly, at a few hundred triangles, with no modelling tool, no export pipeline, no
// binary assets in the repo and no licence questions. A generated GLB would be more
// detailed and would also be 30 opaque files nobody can diff or re-tint.
//
// ⚠️ MATERIALS COME FROM THE THEME, NOT FROM THE PROP. `themes.ts` already says a
// league is timber or copper or tin; a barrel in the Wood yard and a barrel in the
// Smelt should be the same geometry in different materials, or every new league needs
// its own copy of every shape.
import * as THREE from 'three'
import type { ObstacleKind } from '../types'

/** Which kinds are ARENA rather than TRADE — see `propMaterials`. */
export const FURNITURE_KINDS = new Set(
  // ⚠️ `vinewall` IS IN HERE BECAUSE IT IS A WALL. The ivy is authored on the shape; the
  // masonry under it must still climb the venue's course like every other built thing, or
  // an overgrown ruin would be the one piece of stone in the game wearing a league's TRADE
  // colours — which is the exact mistake the furniture split was made to stop.
  ['wall', 'pillar', 'gate', 'dais', 'obelisk', 'ruinedwall', 'brokenpillar', 'vinewall',
    'colonnade', 'brokencolonnade'])

// ⚠️ `hedge` IS DELIBERATELY NOT IN `FURNITURE_KINDS`, AND `urn` IS NOT EITHER. Furniture
// takes the venue's dressed-stone ladder so a wall climbs from rough coursing to pale
// ashlar across the leagues. A hedge is not stone at any rung — re-tinting it with
// `venue.masonry` would draw grey foliage — and the urn authors its own greenery on top of
// masonry it gets from the theme. Both are their own colour, which is the point of them.

/**
 * Which authored MATERIAL a theme's trade props are made of.
 *
 * ⚠️ TEXTURES MAP TO MATERIAL, NOT TO OBJECT. A crate, a log stack and a palisade are all
 * sawn timber; a wall, a pillar and a ruin are all dressed stone. Per-object textures would
 * be forty images and forty UV layouts; per-material is four and none.
 */
export type PropSurface = 'timber' | 'stone' | 'metal' | 'earth'

export interface PropPalette {
  /** What this league's TRADE props are made of. Furniture is always stone. */
  surface?: PropSurface
  /** The main body — planks, stone, ore. */
  body: number
  /** Banding, hoops, nails, iron. */
  trim: number
  /** Cut ends, exposed inner faces, rubble. */
  inner: number
  /** How rough the body reads: 1 is raw timber, 0.35 is polished metal. */
  rough?: number
  /**
   * The arena's own masonry, for `FURNITURE_KINDS`.
   *
   * ⚠️ FURNITURE MUST NOT WEAR THE TRADE PALETTE, AND THE FIRST BUILD PROVED IT. Tinted
   * with `body`, a stone wall came out the same gold as the Bronze foundry floor it stood
   * on — the coursing, the capping and the plinth all vanished into one flat shape, and
   * five distinct objects read as five tan smears. A barrel is the league's TRADE and
   * should match its yard; a wall is the ARENA and should match the STANDS. Passed in
   * from `venue.ts`, so furniture climbs the ladder with the bowl: raw timber at Wood,
   * dressed pale stone at Apex, gilt trim at the top.
   */
  stone?: number
  stoneTrim?: number
  stoneMetal?: number
}

/**
 * A shared surface-noise texture, generated once.
 *
 * ⚠️ THIS IS WHY THE PROPS "DON'T LOOK GOOD ENOUGH". A mesh with a flat colour and no
 * surface is PLASTIC — light lands on it perfectly evenly, so a barrel and a crate and
 * a stump all read as the same moulded material in different shapes. Real timber,
 * stone and slag all have relief, and relief is what a key light has to catch. This
 * costs one 256px canvas, generated in the browser with no asset to ship.
 *
 * ⚠️ THE NOTE THAT USED TO BE HERE WAS THE REASON EVERYTHING LOOKED LIKE PLASTIC, and it
 * is kept because the half of it that is true is still true. It said: use this as
 * `bumpMap` and `roughnessMap` but NEVER as `map`, because as a colour map it would mottle
 * every prop grey and fight the per-league palette. Correct — as a MAP. What it missed is
 * that there is a third option, which is to MULTIPLY the palette colour by it. Grey
 * mottling replaces the hue; a multiply varies its VALUE and leaves the hue alone.
 *
 * ⚠️ AND THE DIFFERENCE IS THE WHOLE "NOT HIGH DEFINITION" COMPLAINT. A prop with one flat
 * albedo has exactly as many tones as the lighting gives it — three or four, all smooth —
 * so a crate is a brown shape and a wall is a grey shape, and no amount of bevelling or
 * polygon count changes that. Real timber and real stone have tonal RANGE inside a single
 * face. That range is what a painted 2D-in-3D style is made of; without it the geometry is
 * the only thing carrying the object.
 */
let GRAIN: THREE.Texture | null = null
function grain(): THREE.Texture {
  if (GRAIN) return GRAIN
  const N = 512
  const cv = document.createElement('canvas')
  cv.width = cv.height = N
  const g = cv.getContext('2d')!
  const img = g.createImageData(N, N)
  // ⚠️ HASHED, NOT Math.random(). Regenerating on a resize or an arena change would
  // give every prop a different surface each time and the whole yard would crawl.
  const h = (x: number, y: number) => {
    const n = Math.sin(x * 127.1 + y * 311.7) * 43758.5453
    return n - Math.floor(n)
  }
  for (let y = 0; y < N; y++) {
    for (let x = 0; x < N; x++) {
      // Three octaves: broad blotches, grain, and a fine speckle.
      // ⚠️ FIVE OCTAVES NOW, NOT THREE, AND THE COARSE ONES CARRY MOST OF THE WEIGHT. The
      // fine speckle is what a bump map wants; broad blotches are what an ALBEDO wants,
      // because tonal variation only reads at this camera distance if the patches are
      // bigger than a pixel or two. Weighted the other way it just looks like noise.
      let v = 0.34 * h(Math.floor(x / 48), Math.floor(y / 48))
        + 0.27 * h(Math.floor(x / 16), Math.floor(y / 16))
        + 0.19 * h(Math.floor(x / 6), Math.floor(y / 6))
        + 0.12 * h(Math.floor(x / 2), Math.floor(y / 2))
        + 0.08 * h(x, y)
      v = 74 + v * 150
      const i = (y * N + x) * 4
      img.data[i] = img.data[i + 1] = img.data[i + 2] = v
      img.data[i + 3] = 255
    }
  }
  g.putImageData(img, 0, 0)
  GRAIN = new THREE.CanvasTexture(cv)
  GRAIN.wrapS = GRAIN.wrapT = THREE.RepeatWrapping
  GRAIN.repeat.set(2, 2)
  return GRAIN
}

// WARNING: SMOOTH BY DEFAULT NOW, FACETED ONLY WHERE FACETS ARE THE POINT. Global
// `flatShading` is a low-poly STYLE, and it fights "high definition" directly: it
// hard-edges every curve, so a 28-segment barrel looks exactly as coarse as an
// 11-segment one and the extra geometry buys nothing. Rubble keeps it, because a
// broken lump genuinely does have flat faces.
/**
 * The four authored material textures, loaded once and shared by every material.
 *
 * ⚠️ NEAR-GREY ON PURPOSE, AND MULTIPLIED RATHER THAN MAPPED. They carry PATTERN and VALUE
 * — plank seams, mortar joints, hammer dents — and no colour of their own, so `themes.ts`
 * keeps complete control of what a league looks like.
 */
const MAT_TEX: Partial<Record<string, THREE.Texture>> = {}
function matTex(kind: string): THREE.Texture {
  const hit = MAT_TEX[kind]
  if (hit) return hit
  const t = new THREE.TextureLoader().load(`/field/mat-${kind}.jpg`)
  t.wrapS = t.wrapT = THREE.RepeatWrapping
  t.colorSpace = THREE.NoColorSpace          // it is a multiplier, not a colour
  MAT_TEX[kind] = t
  return t
}

/** World units one tile of material covers. Stone blocks want to read at roughly this. */
const MAT_SCALE = 0.42

const mat = (color: number, rough: number, metal = 0, flat = false,
  surface: string = 'stone') => {
  const m = new THREE.MeshStandardMaterial({
    color, roughness: rough, metalness: metal, flatShading: flat,
    bumpMap: grain(), bumpScale: metal > 0.2 ? 0.5 : 1.3,
    roughnessMap: grain(),
  })
  /**
   * ⚠️ ALBEDO VARIATION, AND IT IS A MULTIPLY RATHER THAN A MAP — see `grain()`. The same
   * texture is sampled twice at different scales and remapped to a narrow band around 1.0,
   * then multiplied into the diffuse. The hue is untouched, so `themes.ts` still owns the
   * league's colour completely; what changes is that a single face now has range in it.
   *
   * ⚠️ THE BAND IS DELIBERATELY NARROW (0.80-1.14). Wide enough and the prop reads as
   * dirty or damaged rather than made of something; this is the difference between a
   * material and a stain. Two scales because one lattice at one frequency is visible AS a
   * lattice — the same reason the ground needed de-tiling.
   */
  /**
   * ⚠️ TRIPLANAR, BECAUSE THESE SHAPES HAVE NO USABLE UVs. Every prop is procedural —
   * extrusions, lathes, cylinders, spheres — and their UVs are whatever the primitive
   * happened to generate: a box gives each face 0..1, so one tile would stretch to fit a
   * fourteen-unit wall on one face and a half-unit plinth on the next. Unwrapping forty
   * procedural shapes by hand is the alternative.
   *
   * ⚠️ SO THE TEXTURE IS PROJECTED FROM WORLD SPACE ON THREE AXES and blended by the
   * normal. Texel density is then IDENTICAL on every prop and every face of every prop,
   * which is what makes a set of objects look like one world rather than a set of objects.
   * It also means the per-instance rotation in `scene3d.ts` re-projects the material, so
   * two mirrored twins do not even share a grain pattern.
   *
   * ⚠️ AND IT STAYS A MULTIPLY INTO A NARROW BAND. The texture supplies pattern and value;
   * the palette supplies hue. Wider and the prop reads as dirty rather than as made of
   * something — the difference between a material and a stain.
   */
  m.onBeforeCompile = (sh) => {
    sh.uniforms.matTex = { value: matTex(surface) }
    sh.uniforms.matScale = { value: MAT_SCALE }
    const HEAD = 'varying vec3 vWPos;\nvarying vec3 vWNrm;\n'
    sh.vertexShader = HEAD + sh.vertexShader.replace(
      '#include <begin_vertex>',
      [
        '#include <begin_vertex>',
        'vWPos = ( modelMatrix * vec4( transformed, 1.0 ) ).xyz;',
        'vWNrm = normalize( mat3( modelMatrix ) * objectNormal );',
      ].join('\n'),
    )
    sh.fragmentShader = 'uniform sampler2D matTex;\nuniform float matScale;\n'
      + HEAD
      + sh.fragmentShader.replace(
        '#include <color_fragment>',
        [
          '#include <color_fragment>',
          // A SHARP BLEND. pow(4) keeps faces crisp; a soft blend smears all three
          // samples over every surface, which is what makes lazy triplanar look like mud.
          'vec3 bw = pow( abs( vWNrm ), vec3( 4.0 ) );',
          'bw /= max( bw.x + bw.y + bw.z, 0.0001 );',
          'float tX = texture2D( matTex, vWPos.zy * matScale ).r;',
          'float tY = texture2D( matTex, vWPos.xz * matScale ).r;',
          'float tZ = texture2D( matTex, vWPos.xy * matScale ).r;',
          'float tV = tX * bw.x + tY * bw.y + tZ * bw.z;',
          // ⚠️ THE CEILING IS 1.20, NOT 1.30, AND THAT IS WHY. A multiply that can exceed
          // ~1.2 pushes an already-pale material past white under a bright lamp, and Tin's
          // is the brightest in the game — the wall capping courses were clipping to flat
          // white and losing their moulding entirely. A texture may darken a surface freely
          // and may only lift it a little; the palette decides how bright a thing is.
          'diffuseColor.rgb *= ( 0.72 + tV * 0.48 );',
        ].join('\n'),
      )
  }
  return m
}

/**
 * A box with bevelled edges.
 *
 * WARNING: THE BEVEL IS THE WHOLE "HIGH DEFINITION" TRICK ON HARD-SURFACE PROPS, AND
 * IT IS NOT ABOUT POLYGON COUNT. A perfect 90-degree edge catches NO highlight -- it is
 * a discontinuity, so light jumps from one face value straight to the next with nothing
 * in between, and the object reads as a flat-shaded diagram of a box. A small chamfer
 * gives the key light a thin bright line to run along every edge, and that line is what
 * the eye reads as "solid, machined, real". Every hard-surface prop gets one.
 */
function roundedBox(w: number, h: number, d: number, r = Math.min(w, h, d) * 0.08): THREE.BufferGeometry {
  const sh = new THREE.Shape()
  const x = Math.max(0.001, w / 2 - r), z = Math.max(0.001, d / 2 - r)
  sh.absarc(x, z, r, 0, Math.PI / 2, false)
  sh.absarc(-x, z, r, Math.PI / 2, Math.PI, false)
  sh.absarc(-x, -z, r, Math.PI, Math.PI * 1.5, false)
  sh.absarc(x, -z, r, Math.PI * 1.5, Math.PI * 2, false)
  const g = new THREE.ExtrudeGeometry(sh, {
    depth: Math.max(0.001, h - r * 2), bevelEnabled: true,
    bevelSize: r, bevelThickness: r, bevelSegments: 3, curveSegments: 3,
  })
  g.rotateX(-Math.PI / 2)
  // WARNING: BASE-ANCHORED AT y=0, AND THE OFFSET IS `r`, NOT `h / 2`. ExtrudeGeometry
  // runs 0..depth and the BEVEL adds `bevelThickness` at each end, so after the rotate
  // the mesh spans -r .. h-r. Shifting by h/2 (the obvious guess, and the first thing
  // written here) floats every box half its own height off the ground -- crates hovered
  // with their corner posts spiking out of the lids. Base-anchored also matches how
  // every prop in this file is positioned: by where it stands, not by its centre.
  g.translate(0, r, 0)
  g.computeVertexNormals()
  return g
}

/** Everything a prop is made of, built once per theme and shared by every instance. */
export function propMaterials(p: PropPalette) {
  const r = p.rough ?? 0.85
  return {
    body: mat(p.body, r, 0, false, p.surface ?? 'stone'),
    inner: mat(p.inner, Math.min(1, r + 0.08), 0, false, p.surface ?? 'stone'),
    /** Broken stone, slag, rubble -- the one place hard facets are correct. */
    rubble: mat(p.inner, Math.min(1, r + 0.1), 0, true, 'rubble'),
    /** The arena's masonry. Falls back to the trade body only if a venue never set it. */
    stone: mat(p.stone ?? p.body, 0.93, 0, false, 'stone'),
    stoneTrim: mat(p.stoneTrim ?? p.trim, p.stoneMetal && p.stoneMetal > 0.5 ? 0.4 : 0.85,
      p.stoneMetal ?? 0.2, false, 'stone'),
    // ⚠️ SOME metalness ON THE TRIM, NOT NONE AND NOT FULL. Iron banding with
    // metalness 0 is painted-on and flat; at 1 it goes black under a single key light
    // because a pure metal has no diffuse and there is no environment map to reflect.
    trim: mat(p.trim, 0.55, 0.45, false, 'metal'),
  }
}
export type PropMats = ReturnType<typeof propMaterials>

/** A barrel: a lathed body with two iron hoops and a visible lid. */
function barrel(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const r = w / 2
  // The bulge is what says "barrel" rather than "cylinder" — a straight tube reads as
  // a bin. LatheGeometry over a shallow arc costs nothing and carries the silhouette.
  // Twenty rungs of profile, so the bilge is a curve rather than three straight
  // sections, and 28 around so it is a turned object instead of a polygon.
  const pts: THREE.Vector2[] = []
  for (let i = 0; i <= 20; i++) {
    const t = i / 20
    pts.push(new THREE.Vector2(r * (0.80 + 0.20 * Math.sin(t * Math.PI)), t * hgt))
  }
  const body = new THREE.Mesh(new THREE.LatheGeometry(pts, 28), m.body)
  g.add(body)
  // Three hoops, not two: a coopered barrel is banded at both chimes AND the bilge,
  // and the middle band is what stops the silhouette reading as a plain drum.
  for (const hoop of [[hgt * 0.08, 0.84], [hgt * 0.5, 1.0], [hgt * 0.92, 0.84]]) {
    const ring = new THREE.Mesh(new THREE.TorusGeometry(r * hoop[1], r * 0.05, 8, 28), m.trim)
    ring.rotation.x = Math.PI / 2
    ring.position.y = hoop[0]
    g.add(ring)
  }
  const lid = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.79, r * 0.79, hgt * 0.03, 24), m.inner)
  lid.position.y = hgt * 0.99
  g.add(lid)
  const bung = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.11, r * 0.11, hgt * 0.05, 12), m.trim)
  bung.position.set(r * 0.4, hgt * 1.0, 0)
  g.add(bung)
  return g
}

/** A stack of crates: three boxes, offset, with a lighter lid face. */
function crates(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const c = w * 0.46
  const put = (x: number, y: number, z: number, s: number, rot: number) => {
    const e = c * s
    const crate = new THREE.Group()
    crate.position.set(x, y, z)
    crate.rotation.y = rot
    g.add(crate)

    const box = new THREE.Mesh(roundedBox(e, e, e, e * 0.05), m.body)
    box.position.y = 0
    crate.add(box)
    // A lid face a shade lighter reads as a lid; without it a crate is a solid cube
    // and the eye has nothing to tell it which way up it is.
    const lid = new THREE.Mesh(new THREE.PlaneGeometry(e * 0.98, e * 0.98), m.inner)
    lid.rotation.x = -Math.PI / 2
    lid.position.y = e + 0.005
    crate.add(lid)
    // ⚠️ CORNER POSTS AND A CROSS-BRACE, BECAUSE A CUBE HAS NOTHING FOR THE KEY LIGHT
    // TO FIND. A single flat-shaded box gives the eye three faces and no edges; the
    // posts break the silhouette and catch a highlight, which is most of the
    // difference between "a crate" and "a brown cube".
    const post = e * 0.09
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
      const p = new THREE.Mesh(roundedBox(post, e * 1.02, post, post * 0.2), m.trim)
      p.position.set(sx * (e / 2 - post / 2), 0, sz * (e / 2 - post / 2))
      crate.add(p)
    }
    // Plank battens on all four sides. A crate is BOARDS, and two battens per face is
    // the cheapest thing that says so -- they also break the key light across a
    // surface that would otherwise be one flat value from edge to edge.
    for (const sz of [-1, 1]) for (let k = 0; k < 2; k++) {
      for (const axis of [0, 1]) {
        const batten = new THREE.Mesh(
          roundedBox(axis ? post * 0.5 : e * 0.99, post * 0.6, axis ? e * 0.99 : post * 0.5, post * 0.14),
          m.trim,
        )
        const y = e * (0.28 + k * 0.4)   // base of the batten, not its centre
        batten.position.set(axis ? sz * (e / 2 + 0.004) : 0, y, axis ? 0 : sz * (e / 2 + 0.004))
        crate.add(batten)
      }
    }
  }
  put(-w * 0.2, 0, w * 0.08, 1, 0.12)
  put(w * 0.22, 0, -w * 0.06, 0.92, -0.2)
  put(-w * 0.02, c, 0.0, 0.78, 0.34)
  void hgt
  return g
}

/** A stack of felled logs, cut ends toward the viewer. */
function logstack(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const r = Math.min(hgt * 0.36, w * 0.13)
  const len = w * 0.92
  const row = (y: number, n: number) => {
    for (let i = 0; i < n; i++) {
      const log = new THREE.Mesh(new THREE.CylinderGeometry(r, r * 0.94, len, 18), m.body)
      log.rotation.z = Math.PI / 2
      log.position.set(0, y + r, (i - (n - 1) / 2) * r * 2.05)
      g.add(log)
      // ⚠️ THE CUT ENDS ARE A SEPARATE MATERIAL. Bark and heartwood are different
      // colours, and it is the pale end grain that makes a pile of cylinders read as
      // FELLED TIMBER rather than as pipes.
      for (const s of [-1, 1]) {
        const end = new THREE.Mesh(new THREE.CircleGeometry(r * 0.97, 18), m.inner)
        end.position.set((len / 2 + 0.002) * s, y + r, (i - (n - 1) / 2) * r * 2.05)
        end.rotation.y = (Math.PI / 2) * s
        g.add(end)
      }
    }
  }
  row(0, 3)
  row(r * 1.75, 2)
  return g
}

/** A chopping stump: a short trunk with pale end grain on top. */
function stump(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const r = w / 2
  const body = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.92, r, hgt, 26), m.body)
  body.position.y = hgt / 2
  g.add(body)
  // Growth rings on the cut face. A chopping block IS its end grain; without them it
  // is a bollard.
  for (let i = 1; i <= 3; i++) {
    const ring = new THREE.Mesh(new THREE.TorusGeometry(r * 0.92 * (i / 3.6), r * 0.012, 5, 26), m.body)
    ring.rotation.x = Math.PI / 2
    ring.position.y = hgt + 0.008
    g.add(ring)
  }
  const top = new THREE.Mesh(new THREE.CircleGeometry(r * 0.92, 26), m.inner)
  top.rotation.x = -Math.PI / 2
  top.position.y = hgt + 0.004
  g.add(top)
  return g
}

/** A palisade: driven stakes, sharpened, leaning slightly and unevenly tall. */
function palisade(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const n = Math.max(3, Math.round(w / 0.55))
  for (let i = 0; i < n; i++) {
    // ⚠️ HASHED FROM THE INDEX, NEVER Math.random(). The renderer rebuilds the scene
    // on resize and on every arena change; a rolled jitter would reshuffle the fence
    // each time and the arena would visibly twitch. Same index, same stake, always.
    const j = ((i * 37) % 11) / 11
    const h = hgt * (0.8 + j * 0.3)
    const r = w / n / 2.4
    const stake = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.7, r, h, 14), m.body)
    stake.position.set((i - (n - 1) / 2) * (w / n), h / 2, (j - 0.5) * 0.12)
    stake.rotation.z = (j - 0.5) * 0.09
    g.add(stake)
    const tip = new THREE.Mesh(new THREE.ConeGeometry(r * 0.7, r * 1.7, 14), m.inner)
    tip.position.set(stake.position.x, h + r * 0.85, stake.position.z)
    tip.rotation.z = stake.rotation.z
    g.add(tip)
  }
  return g
}

/** A cart: a bed on two wheels with a raised tail. */
function cart(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const bedH = hgt * 0.55
  const bed = new THREE.Mesh(roundedBox(w, hgt * 0.22, w * 0.42, hgt * 0.03), m.body)
  bed.position.y = bedH - hgt * 0.11
  g.add(bed)
  for (const s of [-1, 1]) {
    const wheel = new THREE.Mesh(new THREE.TorusGeometry(bedH * 0.78, bedH * 0.11, 10, 24), m.trim)
    wheel.position.set(w * 0.12, bedH * 0.78, s * w * 0.24)
    g.add(wheel)
    const side = new THREE.Mesh(new THREE.BoxGeometry(w * 0.94, hgt * 0.3, 0.04), m.body)
    side.position.set(0, bedH + hgt * 0.2, s * w * 0.21)
    g.add(side)
  }
  const shaft = new THREE.Mesh(new THREE.BoxGeometry(w * 0.5, 0.06, 0.06), m.body)
  shaft.position.set(-w * 0.6, bedH * 0.75, 0)
  shaft.rotation.z = 0.22
  g.add(shaft)
  return g
}

/** A sawhorse: a beam on two splayed pairs of legs. */
function sawhorse(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const beam = new THREE.Mesh(new THREE.BoxGeometry(w, hgt * 0.16, w * 0.16), m.body)
  beam.position.y = hgt * 0.92
  g.add(beam)
  for (const sx of [-1, 1]) {
    for (const sz of [-1, 1]) {
      const leg = new THREE.Mesh(new THREE.BoxGeometry(0.07, hgt * 0.95, 0.07), m.body)
      leg.position.set(sx * w * 0.34, hgt * 0.46, sz * w * 0.11)
      leg.rotation.z = sx * 0.18
      leg.rotation.x = sz * 0.2
      g.add(leg)
    }
  }
  return g
}

/** A heap of loose material — ore, gravel, slag. Clustered lumps, not a cone. */
function heap(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const main = new THREE.Mesh(new THREE.SphereGeometry(w * 0.5, 20, 14), m.body)
  main.scale.set(1, (hgt / (w * 0.5)) * 0.9, 0.7)
  main.position.y = 0
  g.add(main)
  for (let i = 0; i < 6; i++) {
    const j = ((i * 29) % 13) / 13
    const lump = new THREE.Mesh(new THREE.DodecahedronGeometry(w * (0.08 + j * 0.07), 0), m.rubble)
    const a = (i / 6) * Math.PI * 2
    lump.position.set(Math.cos(a) * w * 0.44, hgt * 0.1 * j, Math.sin(a) * w * 0.3)
    lump.rotation.set(j * 3, j * 5, j * 2)
    g.add(lump)
  }
  return g
}

/** A sunken channel — a leat or sluice: a trough with raised sides. */
function channel(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  for (const s of [-1, 1]) {
    const wall = new THREE.Mesh(roundedBox(w, hgt, w * 0.09, hgt * 0.1), m.body)
    wall.position.set(0, 0, s * w * 0.19)
    g.add(wall)
  }
  // ⚠️ WATER IS THE SAME COLOUR IN EVERY LEAGUE — the second time this exact mistake has
  // been made, after the furnace mouth. Taking the theme's `inner` gives a channel whatever
  // the league's cut-face colour happens to be, and on Tin — a deliberately pale,
  // near-colourless palette — that is almost white, so every leat and sluice rendered as a
  // glowing bar brighter than anything else on the board. A trough of water is dark, and it
  // is dark at Wood and at Apex.
  // ⚠️ AND IT IS LOW-ROUGHNESS RATHER THAN EMISSIVE. What reads as water is a SHEEN — one
  // moving highlight off the key light — not a lit surface. Emissive would put it straight
  // back into the bloom pass, which is where it just came from.
  const water = new THREE.Mesh(new THREE.PlaneGeometry(w * 0.98, w * 0.3),
    new THREE.MeshStandardMaterial({
      color: 0x1d3a42, roughness: 0.16, metalness: 0.28,
    }))
  water.rotation.x = -Math.PI / 2
  water.position.y = hgt * 0.55
  g.add(water)
  return g
}

/** A furnace or crucible: a tapering stack with a hot mouth. */
function furnace(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const body = new THREE.Mesh(new THREE.CylinderGeometry(w * 0.34, w * 0.5, hgt, 26), m.body)
  body.position.y = hgt / 2
  g.add(body)
  // ⚠️ FIRE IS THE SAME COLOUR IN EVERY LEAGUE, so the mouth does NOT take the theme's
  // `inner`. On Tin — a deliberately pale, near-colourless palette — that made the mouth
  // white, and under bloom a furnace read as a headlight pointed at the camera. A dim
  // warm emissive lets the bloom pass find it as a glow instead of a blowout.
  const mouth = new THREE.Mesh(new THREE.CircleGeometry(w * 0.3, 26),
    new THREE.MeshStandardMaterial({
      color: 0x4a1c08, emissive: 0xff7a2a, emissiveIntensity: 0.9, roughness: 1,
    }))
  mouth.rotation.x = -Math.PI / 2
  mouth.position.y = hgt + 0.005
  g.add(mouth)
  const band = new THREE.Mesh(new THREE.TorusGeometry(w * 0.42, w * 0.04, 10, 26), m.trim)
  band.rotation.x = Math.PI / 2
  band.position.y = hgt * 0.35
  g.add(band)
  return g
}

/** Stacked bars — ingots, tin blocks. */
function bars(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const bh = hgt / 3
  for (let r = 0; r < 3; r++) {
    const n = 3 - r
    for (let i = 0; i < n; i++) {
      const bar = new THREE.Mesh(roundedBox(w * 0.86, bh * 0.9, w * 0.24, bh * 0.12), m.trim)
      bar.position.set(0, bh * r, (i - (n - 1) / 2) * w * 0.27)
      g.add(bar)
    }
  }
  return g
}

/**
 * How tall each shape stands, as a multiple of its footprint.
 *
 * ⚠️ HEIGHT IS PER SHAPE AND IS MEASURED OFF THE *SMALLER* FOOTPRINT SIDE FOR ANYTHING
 * THAT LIES DOWN. Deriving it from `max(w, d)` for everything turned the Tin arena's
 * gravel bars — long, low ridges of washed stone — into four grey domes the size of
 * igloos, because their footprint is wide and the height followed the width. A barrel
 * is as tall as it is round; a gravel bar is a metre high however long it runs.
 */
const HEIGHT: Record<string, { k: number; of: 'max' | 'min' }> = {
  // A barrel is TALLER than it is round — at k=0.95 it came out a squat drum that
  // read as another stump. Cover has to be tellable apart at a glance.
  barrel: { k: 1.45, of: 'min' }, crates: { k: 0.9, of: 'max' },
  stump: { k: 0.55, of: 'min' }, palisade: { k: 1.5, of: 'min' },
  cart: { k: 0.8, of: 'min' }, sawhorse: { k: 0.75, of: 'min' },
  logstack: { k: 0.62, of: 'min' },
  orepile: { k: 0.5, of: 'min' }, gravelbar: { k: 0.32, of: 'min' }, slagheap: { k: 0.6, of: 'min' },
  leat: { k: 0.3, of: 'min' }, sluice: { k: 0.38, of: 'min' },
  blowingfurnace: { k: 1.7, of: 'min' }, crucible: { k: 0.9, of: 'min' },
  ingots: { k: 0.42, of: 'min' }, tinblocks: { k: 0.5, of: 'min' },
  // ⚠️ ARENA FURNITURE IS SIZED OFF ITS SHORT SIDE AND STANDS MUCH TALLER. A 14-unit
  // wall must not be seven units high; a pillar must not be as wide as it is tall. These
  // are the only shapes whose height is meant to exceed their footprint.
  wall: { k: 1.15, of: 'min' }, pillar: { k: 3.2, of: 'min' },
  ruinedwall: { k: 1.6, of: 'min' }, brokenpillar: { k: 1.9, of: 'min' },
  // ⚠️ A TREE IS THE TALLEST THING ON THE GROUND AND THAT IS FINE — it stands OUTSIDE the
  // field, so the "must not tower over a monster" rule (which is about cover hiding the
  // fight) does not apply to it. Behind the rail, height is what makes it read as scenery
  // rather than as another obstacle someone forgot to place properly.
  tree: { k: 2.6, of: 'max' }, bush: { k: 0.82, of: 'max' },
  anvil: { k: 1.05, of: 'min' }, orebin: { k: 1.0, of: 'min' },
  vinewall: { k: 1.35, of: 'min' },
  gate: { k: 2.2, of: 'min' },
  // ⚠️ MEASURED OFF THE LONG SIDE, NOT THE SHORT ONE, AND THAT WAS THE BUG. `0.42 of min`
  // gave a twelve-unit platform a height of 1.0 — a quarter of a monster — while its own
  // 4.92:1 sprite implies 2.4, so the 3D dais was less than half the height the 2D one
  // draws. On a pale floor it read as a smear rather than as something you stand on, and
  // two Iron boards built around it had no silhouette at all. `0.2 of max` reproduces the
  // sprite's own proportion exactly, which is the rule every other prop already follows.
  dais: { k: 0.2, of: 'max' },
  obelisk: { k: 2.9, of: 'min' },
  // ⚠️ MEASURED OFF THE SPRITE, LIKE `dais`. `prop-colonnade` is 256x85 (aspect 3.01)
  // and `prop-brokencolonnade` is 256x96 (2.67), so `of: 'max'` with k = 1/aspect makes
  // the 3D run exactly as tall as the 2D one draws. A run 13 units wide stands 4.3 — well
  // over a monster, which is why both are UPRIGHT kinds rather than cover.
  colonnade: { k: 0.332, of: 'max' },
  brokencolonnade: { k: 0.375, of: 'max' },
  // ⚠️ A HEDGE IS COVER, NOT ARCHITECTURE, so it lives under the 3.4 ceiling rather than
  // the 7.0 one — you shoot OVER a hedge. `prop-hedge` is 256x67 (aspect 3.82), so a
  // 12-unit run draws 3.14: just under a monster, which is exactly what cover should be.
  hedge: { k: 0.262, of: 'max' },
  // `prop-urn` is 168x256 — the only prop in the library TALLER than it is wide. A 2-unit
  // footprint draws 3.05, so it reads as a standing accent without breaking the ceiling.
  urn: { k: 1.52, of: 'min' },
  // ⚠️ FOUR SILHOUETTE CLASSES, AND THE NUMBERS ARE WHAT MAKE THEM DIFFERENT rather than
  // the names. Each is 1/aspect of its sprite, so 2D and 3D draw the same object:
  //   topiary   66x256  (0.26)  — a 1.6 footprint stands 6.2: UPRIGHT, twice a monster
  //   arbour   234x256  (0.91)  — a 4.0 footprint stands 4.4: UPRIGHT, and pierced
  //   flowerbed 256x20 (12.80)  — a 14 footprint stands 1.1: the only sub-metre cover
  //   fountain 256x116  (2.21)  — a 6.0 footprint stands 2.7: chest height, and ROUND
  topiary: { k: 3.88, of: 'min' },
  arbour: { k: 1.09, of: 'min' },
  flowerbed: { k: 0.078, of: 'max' },
  fountain: { k: 0.453, of: 'max' },
}

/** A clipped standard: a bare stem out of a box, and two balls of yew above it. */
function topiary(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const greens = new THREE.MeshStandardMaterial({ color: 0x32502a, roughness: 0.95 })
  const greensB = new THREE.MeshStandardMaterial({ color: 0x3a5b31, roughness: 0.95 })
  const bark = new THREE.MeshStandardMaterial({ color: 0x4a3b28, roughness: 0.95 })
  const box = new THREE.Mesh(roundedBox(w * 0.86, hgt * 0.13, w * 0.86, 0.04), m.body)
  box.position.y = hgt * 0.065
  box.castShadow = true; box.receiveShadow = true
  g.add(box)
  const rim = new THREE.Mesh(roundedBox(w * 0.95, hgt * 0.025, w * 0.95, 0.02), m.trim)
  rim.position.y = hgt * 0.14
  g.add(rim)
  const stem = new THREE.Mesh(new THREE.CylinderGeometry(w * 0.07, w * 0.09, hgt * 0.36, 8), bark)
  stem.position.y = hgt * 0.32
  stem.castShadow = true
  g.add(stem)
  // ⚠️ TWO BALLS, NOT ONE. A single sphere on a stick is a lollipop and reads as a tree at
  // this camera, which is what the scenery outside the rail already is. The stacked pair is
  // what says CLIPPED — a shape a gardener made, not one that grew.
  for (const [y, r, alt] of [[0.62, 0.42, false], [0.88, 0.27, true]] as const) {
    const ball = new THREE.Mesh(new THREE.SphereGeometry(w * r * 1.6, 12, 10), alt ? greensB : greens)
    ball.scale.y = 0.92
    ball.position.y = hgt * y
    ball.castShadow = true
    g.add(ball)
  }
  return g
}

/**
 * A planted arbour: two posts, an arched beam, and climbing growth over all of it.
 *
 * ⚠️ GOLD'S ONLY PIERCED PIECE, which is what it is for. Every other prop in the planted
 * family is opaque — that is the family's whole contrast with Silver — and a league where
 * NOTHING can be shot through is a league with one answer to every position. The opening
 * under the arch is clear, so this is cover that stops a charge without stopping a bow.
 */
function arbour(_m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const timber = new THREE.MeshStandardMaterial({ color: 0x9a8a6c, roughness: 0.9 })
  const greens = new THREE.MeshStandardMaterial({ color: 0x35522b, roughness: 0.95 })
  const greensB = new THREE.MeshStandardMaterial({ color: 0x3d5c32, roughness: 0.95 })
  const d = Math.max(0.7, w * 0.34)
  const span = w * 0.74
  const pierH = hgt * 0.56
  for (const sx of [-1, 1]) {
    const post = new THREE.Mesh(roundedBox(w * 0.13, pierH, d * 0.62, 0.05), timber)
    post.position.set(sx * span / 2, pierH / 2, 0)
    post.castShadow = true; post.receiveShadow = true
    g.add(post)
  }
  const arch = new THREE.Mesh(
    new THREE.TorusGeometry(span / 2, w * 0.062, 8, 20, Math.PI), timber)
  arch.position.y = pierH
  arch.castShadow = true
  g.add(arch)
  // Climbing growth: clumps hung off the arch and down the posts, hashed off position.
  const hash = (n: number) => {
    const x = Math.sin(n * 91.7 + w * 0.41) * 43758.5453
    return x - Math.floor(x)
  }
  for (let i = 0; i < 11; i++) {
    const t = i / 10
    const a = Math.PI * t
    const j = hash(i)
    const r = w * (0.1 + j * 0.06)
    const clump = new THREE.Mesh(new THREE.SphereGeometry(r, 9, 7), i % 2 ? greensB : greens)
    clump.scale.set(1.1, 0.9, 0.85)
    clump.position.set(Math.cos(a) * span / 2, pierH + Math.sin(a) * span / 2,
      (j - 0.5) * d * 0.4)
    clump.castShadow = true
    g.add(clump)
  }
  for (const sx of [-1, 1]) {
    for (let i = 0; i < 3; i++) {
      const j = hash(i + (sx > 0 ? 20 : 40))
      const r = w * (0.085 + j * 0.05)
      const clump = new THREE.Mesh(new THREE.SphereGeometry(r, 8, 6), i % 2 ? greens : greensB)
      clump.position.set(sx * span / 2, pierH * (0.2 + i * 0.26), (j - 0.5) * d * 0.5)
      clump.castShadow = true
      g.add(clump)
    }
  }
  return g
}

/**
 * A low formal bed: a stone kerb with planting inside it.
 *
 * ⚠️ THE ONLY SUB-METRE COVER IN THE GAME, and Gold needed one badly. Everything else on
 * these boards stands between two and three units — chest height on a monster — so every
 * piece answers the same question. A bed you can see clean over changes what a position is
 * worth without changing where you can walk, which is a thing no other prop here does.
 */
function flowerbed(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const soil = new THREE.MeshStandardMaterial({ color: 0x2e261c, roughness: 0.98 })
  const leaf = new THREE.MeshStandardMaterial({ color: 0x405532, roughness: 0.96 })
  const d = Math.max(1.4, hgt * 3.4)
  const kerb = new THREE.Mesh(roundedBox(w, hgt * 0.5, d, 0.05), m.body)
  kerb.position.y = hgt * 0.25
  kerb.castShadow = true; kerb.receiveShadow = true
  g.add(kerb)
  const bed = new THREE.Mesh(roundedBox(w * 0.9, hgt * 0.2, d * 0.78, 0.03), soil)
  bed.position.y = hgt * 0.55
  g.add(bed)
  const PETAL = [0xd8c9a8, 0xc98fa2, 0xd6c47a, 0xbfb6c6]
  const hash = (n: number) => {
    const x = Math.sin(n * 33.7 + w * 0.71) * 43758.5453
    return x - Math.floor(x)
  }
  const n = Math.max(6, Math.round(w / 0.85))
  for (let i = 0; i < n; i++) {
    const j = hash(i), k = hash(i + 99)
    const r = hgt * (0.22 + j * 0.14)
    const mat = i % 3 === 0
      ? new THREE.MeshStandardMaterial({ color: PETAL[i % PETAL.length], roughness: 0.9 })
      : leaf
    const tuft = new THREE.Mesh(new THREE.SphereGeometry(r, 7, 5), mat)
    tuft.scale.set(1, 0.8, 1)
    tuft.position.set(-w / 2 + w * ((i + 0.5) / n), hgt * 0.66, (k - 0.5) * d * 0.5)
    g.add(tuft)
  }
  return g
}

/**
 * A round basin with a pedestal and a spill.
 *
 * ⚠️ THE ONLY ROUND FOOTPRINT IN THE LIBRARY, and that is the reason it exists. Every other
 * piece of cover in the game is a rectangle, so every board is made of bars however they
 * are arranged; one circular landmark changes the geometry of the space around it rather
 * than just its contents. The engine still collides against the authored RECTANGLE — the
 * roundness is presentation, exactly like every prop's height.
 */
function fountain(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const r = w * 0.5
  const water = new THREE.MeshStandardMaterial({
    color: 0x7fa8b8, roughness: 0.18, metalness: 0.1, transparent: true, opacity: 0.86 })
  for (const [k, rr, hh] of [[0, 1.0, 0.16], [1, 0.9, 0.2]] as const) {
    const step = new THREE.Mesh(new THREE.CylinderGeometry(r * rr, r * (rr + 0.04), hgt * hh, 20), m.body)
    step.position.y = hgt * (k ? 0.26 : 0.08)
    step.castShadow = true; step.receiveShadow = true
    g.add(step)
  }
  const rim = new THREE.Mesh(new THREE.TorusGeometry(r * 0.88, hgt * 0.055, 8, 22), m.trim)
  rim.rotation.x = Math.PI / 2
  rim.position.y = hgt * 0.37
  g.add(rim)
  const pool = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.84, r * 0.84, hgt * 0.04, 20), water)
  pool.position.y = hgt * 0.35
  g.add(pool)
  const ped = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.13, r * 0.2, hgt * 0.36, 12), m.body)
  ped.position.y = hgt * 0.55
  ped.castShadow = true
  g.add(ped)
  const dish = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.4, r * 0.16, hgt * 0.12, 16), m.trim)
  dish.position.y = hgt * 0.77
  dish.castShadow = true
  g.add(dish)
  // Four falling threads. ⚠️ EMISSIVE-FREE — the bloom pass would turn a garden fountain
  // into a light source, which is what happened to Tin's furnace mouth and Copper's channel.
  for (let i = 0; i < 4; i++) {
    const a = (i / 4) * Math.PI * 2 + 0.4
    const jet = new THREE.Mesh(new THREE.CylinderGeometry(hgt * 0.02, hgt * 0.03, hgt * 0.4, 6), water)
    jet.position.set(Math.cos(a) * r * 0.36, hgt * 0.57, Math.sin(a) * r * 0.36)
    g.add(jet)
  }
  return g
}

/**
 * A clipped garden hedge: a solid mass of foliage with a flat top and a woody base.
 *
 * ⚠️ THE OPPOSITE OF `colonnade`, ON PURPOSE, AND THAT IS THE WHOLE POINT OF THE FAMILY.
 * Silver's runs are pierced — you read the enemy between the shafts. A hedge has no gaps at
 * all: it is the densest cover in the game, and the two leagues share a team size and must
 * not share a look. Built from overlapping blobs rather than one box so the top reads as
 * clipped growth rather than as a green wall.
 */
function hedge(_m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const d = Math.max(0.8, hgt * 0.78)
  const foliage = new THREE.MeshStandardMaterial({ color: 0x35502a, roughness: 0.96 })
  const foliageB = new THREE.MeshStandardMaterial({ color: 0x3d5b30, roughness: 0.96 })
  const stem = new THREE.MeshStandardMaterial({ color: 0x3a2f22, roughness: 0.95 })
  // A shadowed woody base, so the hedge sits ON the ground instead of floating over it.
  const foot = new THREE.Mesh(roundedBox(w * 0.96, hgt * 0.18, d * 0.8, 0.05), stem)
  foot.position.y = hgt * 0.09
  foot.receiveShadow = true
  g.add(foot)
  const body = new THREE.Mesh(roundedBox(w, hgt * 0.78, d, Math.min(0.35, d * 0.3)), foliage)
  body.position.y = hgt * 0.55
  body.castShadow = true; body.receiveShadow = true
  g.add(body)
  // ⚠️ THE RAGGED TOP IS HASHED OFF POSITION, NEVER Math.random — the scene rebuilds on
  // every resize and lens toggle, and a hedge that reshuffled itself each time would be
  // the treeline bug with leaves on.
  // ⚠️ THE FIRST PASS DREW A SMOOTH GREEN BOX, and it took a render to see it. The puffs
  // were radius `hgt * 0.2-0.3` — under a unit on a 3.1-unit hedge — scaled to 0.62 in Y,
  // so they added roughly half a unit of lumpiness to a two-and-a-half-unit body and
  // vanished at the camera. Cover that reads as an extruded rectangle is the "objects don't
  // look octopath" complaint waiting to happen; a clipped hedge is defined by the fact that
  // its top is ALMOST flat and not quite.
  // ⚠️ SO THEY ARE BIGGER, DENSER AND THEY BREAK THE ENDS TOO. Radius scales with the
  // hedge's DEPTH rather than its height (a hedge is as wide across as its foliage mass),
  // they overhang the body left and right so the ends are not square corners, and the run
  // is sampled at 1.35-unit spacing instead of 2.1 so no gap between them reads as a notch.
  const n = Math.max(4, Math.round(w / 1.35))
  for (let i = 0; i < n; i++) {
    const t = i / (n - 1)
    const j = Math.abs(Math.sin((i + 1) * 12.9898 + w * 0.317) * 43758.5453) % 1
    const k = Math.abs(Math.sin((i + 1) * 78.233 + w * 0.117) * 43758.5453) % 1
    const r = d * (0.62 + j * 0.2)
    const puff = new THREE.Mesh(new THREE.SphereGeometry(r, 10, 8), i % 2 ? foliageB : foliage)
    puff.scale.set(1.0, 0.66 + k * 0.16, 0.94)
    puff.position.set(-w / 2 + w * t, hgt * (0.8 + j * 0.09), (k - 0.5) * d * 0.34)
    puff.castShadow = true; puff.receiveShadow = true
    g.add(puff)
  }
  return g
}

/**
 * A formal garden urn on a plinth, planted.
 *
 * ⚠️ THE ONLY PROP IN THE LIBRARY TALLER THAN IT IS WIDE, and Gold needed one. A family
 * built from hedges alone is a board of horizontal bars — the exact failure the `dais`
 * boards had at Iron. The urn is the vertical accent that gives an arrangement a corner,
 * a centre or a marker, at a footprint small enough not to spend the density allowance.
 */
function urn(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const r = w * 0.5
  const greens = new THREE.MeshStandardMaterial({ color: 0x38542c, roughness: 0.95 })
  const plinth = new THREE.Mesh(roundedBox(w * 0.86, hgt * 0.34, w * 0.86, 0.05), m.body)
  plinth.position.y = hgt * 0.17
  plinth.castShadow = true; plinth.receiveShadow = true
  g.add(plinth)
  const cap = new THREE.Mesh(roundedBox(w * 0.98, hgt * 0.05, w * 0.98, 0.03), m.trim)
  cap.position.y = hgt * 0.36
  g.add(cap)
  const stemM = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.22, r * 0.32, hgt * 0.14, 12), m.body)
  stemM.position.y = hgt * 0.45
  g.add(stemM)
  // The bowl: a wide shallow cone with a rolled rim, which is what makes it an urn and
  // not a pot. Flat-shaded so the flutes read as facets at this distance.
  const bowl = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.86, r * 0.34, hgt * 0.26, 14, 1),
    new THREE.MeshStandardMaterial({ color: m.body.color, roughness: 0.86, flatShading: true }))
  bowl.position.y = hgt * 0.65
  bowl.castShadow = true
  g.add(bowl)
  const rim = new THREE.Mesh(new THREE.TorusGeometry(r * 0.86, r * 0.1, 8, 16), m.trim)
  rim.rotation.x = Math.PI / 2
  rim.position.y = hgt * 0.78
  g.add(rim)
  for (const [dx, dy, dz, rr] of [
    [0, 0, 0, 0.62], [-0.5, -0.22, 0.14, 0.42], [0.52, -0.18, -0.12, 0.44],
  ] as const) {
    const ball = new THREE.Mesh(new THREE.SphereGeometry(r * rr, 10, 8), greens)
    ball.position.set(dx * r, hgt * (0.88 + dy * 0.14), dz * r)
    ball.castShadow = true
    g.add(ball)
  }
  return g
}

/**
 * A run of colonnade: a stylobate, a file of columns, an architrave across the top.
 *
 * ⚠️ THE ONE PIECE OF COVER YOU CAN SEE THROUGH, and that is its whole job. Bronze's
 * `wall` is opaque and Iron's `gate` has a single opening; this has six gaps, so it
 * screens a line of sight without ending it. At the shipped camera you read the enemy
 * BETWEEN the shafts, which is a different tactical object from either of them.
 *
 * ⚠️ AND IT EXISTS BECAUSE A BARE COLUMN COULD NOT CARRY A BOARD. Silver's first five
 * grounds measured 0.79%-1.41% of their area under cover against 3.1%-11.2% everywhere
 * else — see `types.ts`. Same family, at wall scale.
 */
function colonnade(m: PropMats, w: number, hgt: number, broken = false): THREE.Group {
  const g = new THREE.Group()
  const d = Math.max(0.55, hgt * 0.34)
  // Two steps, the upper inset — a stylobate is what makes a row of posts architecture.
  for (const [k, sw, sh] of [[0, 1.0, 0.09], [1, 0.94, 0.08]] as const) {
    const step = new THREE.Mesh(roundedBox(w * sw, hgt * sh, d * (1.34 - k * 0.16), 0.04), m.body)
    step.position.y = hgt * (k ? 0.13 : 0.045)
    step.castShadow = true; step.receiveShadow = true
    g.add(step)
  }
  const base = hgt * 0.17
  const shaftH = hgt * (broken ? 0.62 : 0.66)
  const n = 7
  const gapW = w / n
  const rad = Math.min(gapW * 0.3, d * 0.34)
  // ⚠️ THE BROKEN RUN IS AUTHORED, NOT RANDOMISED. `Math.random` is unavailable in this
  // project's scripts and would be wrong here anyway — the scene rebuilds on every resize
  // and lens toggle, so a random ruin would rearrange itself while the player watched.
  const STUMPED = new Set([2, 5])
  const MISSING = 4
  for (let i = 0; i < n; i++) {
    if (broken && i === MISSING) continue
    const x = -w / 2 + gapW * (i + 0.5)
    const h = broken && STUMPED.has(i) ? shaftH * 0.42 : shaftH
    const shaft = new THREE.Mesh(new THREE.CylinderGeometry(rad * 0.86, rad, h, 12), m.body)
    shaft.position.set(x, base + h / 2, 0)
    shaft.castShadow = true; shaft.receiveShadow = true
    g.add(shaft)
    const plinth = new THREE.Mesh(roundedBox(rad * 2.4, hgt * 0.05, rad * 2.4, 0.03), m.body)
    plinth.position.set(x, base + hgt * 0.025, 0)
    g.add(plinth)
    if (broken && STUMPED.has(i)) continue
    const cap = new THREE.Mesh(roundedBox(rad * 2.5, hgt * 0.06, rad * 2.5, 0.03), m.trim)
    cap.position.set(x, base + h + hgt * 0.03, 0)
    cap.castShadow = true
    g.add(cap)
  }
  // The architrave. On the ruined run it survives over the left half only, which is what
  // turns "some columns are shorter" into "this fell down".
  const beamW = broken ? w * 0.46 : w * 1.0
  const beamX = broken ? -w / 2 + beamW / 2 : 0
  const beam = new THREE.Mesh(roundedBox(beamW, hgt * 0.11, d * 1.06, 0.04), m.trim)
  beam.position.set(beamX, base + shaftH + hgt * 0.115, 0)
  beam.castShadow = true; beam.receiveShadow = true
  g.add(beam)
  if (broken) {
    // A toppled drum on the steps, lying across the run — the silhouette that says ruin.
    const drum = new THREE.Mesh(new THREE.CylinderGeometry(rad, rad, gapW * 0.8, 10), m.body)
    drum.rotation.z = Math.PI / 2
    drum.position.set(w / 2 - gapW * 0.6, hgt * 0.19 + rad, d * 0.1)
    drum.castShadow = true
    g.add(drum)
  }
  return g
}

/**
 * A long arena wall: a plinth, coursed masonry, and a capping course.
 *
 * ⚠️ BUILT FROM COURSES, NOT AS ONE BOX. A wall this long — eight to sixteen units, where
 * every other prop is under four — is the biggest flat surface on the board, and a single
 * extrusion gives the key light one value across the whole span and reads as a painted
 * bar. Stacking two courses of offset blocks puts a shadow line at every joint, which is
 * the only thing that makes stone read as stone at this size.
 */
function wall(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const d = Math.max(0.5, hgt * 0.42)
  const plinth = new THREE.Mesh(roundedBox(w, hgt * 0.16, d * 1.22, d * 0.06), m.body)
  g.add(plinth)
  // Two courses, offset by half a block so the joints break — the oldest trick in
  // masonry and the one that stops a wall looking printed.
  const rows = 2
  const bh = (hgt * 0.66) / rows
  for (let r = 0; r < rows; r++) {
    const n = Math.max(3, Math.round(w / (bh * 1.9)))
    const bw = w / n
    for (let i = 0; i < n; i++) {
      const off = r % 2 ? bw * 0.5 : 0
      const x = -w / 2 + bw * (i + 0.5) + off
      if (x > w / 2 - bw * 0.25) continue
      const blk = new THREE.Mesh(roundedBox(bw * 0.94, bh * 0.9, d, bh * 0.08), m.body)
      blk.position.set(x, hgt * 0.16 + bh * r, 0)
      blk.castShadow = true; blk.receiveShadow = true
      g.add(blk)
    }
  }
  const cap = new THREE.Mesh(roundedBox(w * 1.02, hgt * 0.14, d * 1.3, d * 0.08), m.trim)
  cap.position.y = hgt * 0.82
  g.add(cap)
  return g
}

/** A freestanding pillar: base, fluted shaft, capital, and a shallow finial. */
function pillar(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const r = w * 0.34
  for (const [y, rb, rt, h] of [[0, r * 1.5, r * 1.35, hgt * 0.09],
    [hgt * 0.09, r * 1.28, r * 1.12, hgt * 0.05]] as const) {
    const b = new THREE.Mesh(new THREE.CylinderGeometry(rt, rb, h, 18), m.body)
    b.position.y = y + h / 2
    g.add(b)
  }
  // 14 flat-shaded segments ARE the flutes — see the same call in stadium.ts.
  const shaft = new THREE.Mesh(
    new THREE.CylinderGeometry(r * 0.86, r, hgt * 0.66, 14),
    new THREE.MeshStandardMaterial({ color: m.body.color, roughness: 0.9, flatShading: true,
      bumpMap: grain(), bumpScale: 1.2 }))
  shaft.position.y = hgt * 0.14 + hgt * 0.33
  g.add(shaft)
  const cap = new THREE.Mesh(new THREE.CylinderGeometry(r * 1.42, r * 0.9, hgt * 0.11, 18), m.trim)
  cap.position.y = hgt * 0.855
  g.add(cap)
  const abacus = new THREE.Mesh(roundedBox(w * 1.05, hgt * 0.06, w * 1.05, w * 0.06), m.trim)
  abacus.position.y = hgt * 0.91
  g.add(abacus)
  return g
}

/** A gateway: two piers, a round arch, an entablature over. Blocks sight, not movement. */
function gate(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  // ⚠️ NOTHING MAY SPAN THE FULL WIDTH ACROSS THE TOP. Three builds of this piece read as
  // a TABLE, and the cause was the same every time: from a 38° camera a horizontal slab
  // over two legs IS a table, whatever the arch underneath is doing. The fix is not a
  // thinner slab — it is no slab. The PIERS stand proud above the crown, each with its own
  // coping, and the masonry between them stops lower. That silhouette cannot be read as
  // furniture because its highest points are its two ends.
  const pier = w * 0.28
  const span = w - pier * 2
  const springY = hgt * 0.46
  const crown = springY + span / 2
  for (const sx of [-1, 1]) {
    const p = new THREE.Mesh(roundedBox(pier, crown + pier * 0.62, pier * 1.15, pier * 0.09), m.body)
    p.position.set(sx * (w / 2 - pier / 2), 0, 0)
    p.castShadow = true; p.receiveShadow = true
    g.add(p)
    // Coping over each pier ONLY — trim at the scale trim belongs at.
    const cap = new THREE.Mesh(roundedBox(pier * 1.2, hgt * 0.06, pier * 1.34, pier * 0.06), m.trim)
    cap.position.set(sx * (w / 2 - pier / 2), crown + pier * 0.62, 0)
    cap.castShadow = true
    g.add(cap)
  }
  const arch = new THREE.Mesh(
    new THREE.TorusGeometry(span / 2, pier * 0.5, 10, 22, Math.PI), m.body)
  arch.position.y = springY
  arch.castShadow = true
  g.add(arch)
  // A keystone, because the eye goes to the crown of an arch and finds nothing there.
  const key = new THREE.Mesh(roundedBox(pier * 0.5, pier * 0.9, pier * 1.22, pier * 0.06), m.body)
  key.position.y = crown - pier * 0.3
  g.add(key)
  // Spandrel: the masonry filling the shoulders, stopping BELOW the pier copings.
  const spandrel = new THREE.Mesh(
    roundedBox(span + pier * 0.9, pier * 0.42, pier * 1.02, pier * 0.05), m.body)
  spandrel.position.y = crown + pier * 0.18
  spandrel.castShadow = true
  g.add(spandrel)
  return g
}

/** A stepped dais — three shallow tiers. The one piece of cover you can stand ON. */
function dais(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const tiers = 3
  for (let i = 0; i < tiers; i++) {
    const k = 1 - i * 0.16
    const step = new THREE.Mesh(
      roundedBox(w * k, hgt / tiers, w * k * 0.62, hgt * 0.05),
      i === tiers - 1 ? m.trim : m.body)
    step.position.y = (hgt / tiers) * i
    step.castShadow = true; step.receiveShadow = true
    g.add(step)
  }
  return g
}

/** An obelisk on a stepped plinth — tall, thin, and the only vertical accent on a board. */
function obelisk(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  for (const [i, k] of [1.0, 0.74].entries()) {
    const p = new THREE.Mesh(roundedBox(w * k, hgt * 0.05, w * k, w * 0.04), m.body)
    p.position.y = hgt * 0.05 * i
    g.add(p)
  }
  const shaftH = hgt * 0.76
  const shaft = new THREE.Mesh(
    // ⚠️ 3:1, NOT 8:1. At the old ratio a 2.6-wide obelisk drew a 0.9-wide shaft eleven
    // units tall and read as a lamp post — a stone monolith is a HEAVY thing, and its
    // weight is the taper, not the height.
    new THREE.CylinderGeometry(w * 0.24, w * 0.36, shaftH, 4), m.body)
  shaft.rotation.y = Math.PI / 4
  shaft.position.y = hgt * 0.1 + shaftH / 2
  shaft.castShadow = true
  g.add(shaft)
  const tip = new THREE.Mesh(new THREE.ConeGeometry(w * 0.33, hgt * 0.14, 4), m.trim)
  tip.rotation.y = Math.PI / 4
  tip.position.y = hgt * 0.1 + shaftH + hgt * 0.07
  g.add(tip)
  return g
}

/**
 * A ruined wall: the same coursing, with the top torn away and a gap through it.
 *
 * ⚠️ THE GAP AND THE UNEVEN TOP ARE THE WHOLE POINT, and both are hashed rather than
 * rolled so a board looks identical on every render. An intact wall covers uniformly; a
 * ruined one gives partial cover that differs along its length, which is the only kind
 * that makes WHERE you stand behind it matter.
 */
function ruinedwall(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  // ⚠️ NEARLY AS DEEP AS IT IS TALL. At 0.45 the courses came out as slabs laid on edge
  // and the tumbled blocks read as dropped floor tiles; a ruin is rubble, and rubble is
  // the one thing on the board that has to look like it has VOLUME.
  const d = Math.max(0.6, hgt * 0.78)
  const plinth = new THREE.Mesh(roundedBox(w, hgt * 0.14, d * 1.2, d * 0.06), m.body)
  g.add(plinth)
  const rows = 3
  const bh = (hgt * 0.8) / rows
  const n = Math.max(4, Math.round(w / (bh * 1.7)))
  const bw = w / n
  // One breach, placed a third or two thirds along depending on the wall's own length.
  const breach = Math.floor(n * (w % 2 < 1 ? 0.36 : 0.62))
  for (let r = 0; r < rows; r++) {
    for (let i = 0; i < n; i++) {
      const h = ((i * 31 + r * 17) % 11) / 11
      // The higher the course, the more of it has fallen — a wall collapses from the top.
      if (h < r * 0.34) continue
      if (i >= breach && i <= breach + 1 && r > 0) continue
      const off = r % 2 ? bw * 0.5 : 0
      const x = -w / 2 + bw * (i + 0.5) + off
      if (x > w / 2 - bw * 0.25) continue
      const blk = new THREE.Mesh(
        roundedBox(bw * (0.88 + h * 0.08), bh * 0.92, d * (0.9 + h * 0.14), bh * 0.09), m.body)
      blk.position.set(x, hgt * 0.14 + bh * r, (h - 0.5) * d * 0.1)
      blk.rotation.y = (h - 0.5) * 0.07
      blk.castShadow = true; blk.receiveShadow = true
      g.add(blk)
    }
  }
  // Tumbled blocks at the foot — the rubble a collapse actually leaves.
  for (let i = 0; i < 3; i++) {
    const h = ((i * 53) % 9) / 9
    const blk = new THREE.Mesh(roundedBox(bw * 0.7, bh * 0.6, d * 0.7, bh * 0.1), m.body)
    blk.position.set(-w / 2 + w * (0.2 + h * 0.6), bh * 0.3, d * (0.6 + h * 0.4))
    blk.rotation.set(h * 0.3, h * 2.4, (h - 0.5) * 0.4)
    blk.castShadow = true
    g.add(blk)
  }
  return g
}

/** A snapped pillar: jagged stump on its base, with the fallen drum beside it. */
function brokenpillar(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const r = w * 0.3
  const base = new THREE.Mesh(roundedBox(w * 0.86, hgt * 0.09, w * 0.86, w * 0.05), m.body)
  g.add(base)
  const stumpH = hgt * 0.46
  const stump = new THREE.Mesh(
    new THREE.CylinderGeometry(r * 0.94, r, stumpH, 14),
    new THREE.MeshStandardMaterial({ color: m.body.color, roughness: 0.94, flatShading: true,
      bumpMap: grain(), bumpScale: 1.3 }))
  stump.position.y = hgt * 0.09 + stumpH / 2
  stump.castShadow = true
  g.add(stump)
  // ⚠️ THE FRACTURE IS A LOW-POLY CONE, NOT A FLAT CAP. A clean disc on top reads as a
  // bollard someone cut with a saw; a few jagged facets read as stone that BROKE.
  const frac = new THREE.Mesh(new THREE.ConeGeometry(r * 0.96, hgt * 0.1, 7), m.body)
  frac.position.y = hgt * 0.09 + stumpH + hgt * 0.03
  frac.rotation.y = 0.4
  g.add(frac)
  // ⚠️ THE SAME STONE AS THE STUMP IT FELL OFF. In trim it read as a brass barrel someone
  // had rolled in — a fracture does not change what the rock is made of.
  const drum = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.88, r * 0.84, w * 0.8, 14), m.body)
  drum.rotation.set(0, 0.35, Math.PI / 2)
  drum.position.set(w * 0.62, r * 0.88, w * 0.34)
  drum.castShadow = true; drum.receiveShadow = true
  g.add(drum)
  return g
}

/**
 * A broadleaf tree: a tapered trunk, two boughs, and a canopy of clumped spheres.
 *
 * ⚠️ THE CANOPY IS SEVERAL OVERLAPPING SPHERES, NOT ONE. A single sphere reads as a
 * lollipop from every angle — there is no silhouette in it, and silhouette is all a tree
 * contributes at this camera distance. Five clumps at hashed offsets give an uneven edge
 * and let the key light find gaps, which is what says "foliage" rather than "ball".
 *
 * ⚠️ AND SCENERY IS NOT RE-TINTED PER LEAGUE. Every other prop takes the theme's palette
 * so a barrel matches its yard; a tree that did would come out blue-grey at Tin. Colour is
 * the one thing about a tree that is the same in every league, so it is authored here.
 */
function tree(_m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  // ⚠️ DARK GREEN, NOT MID GREEN. The first pass used a daylight leaf (0x4a6b32) and the
  // treeline came out the brightest thing in the frame — plastic broccoli behind a dim
  // warm-lit ground. The scene's whole premise is one working lamp with everything past
  // the wall falling into dark, and scenery is PAST THE WALL. It has to sit at the value
  // of the thing it stands behind, not at the value the object would be at noon.
  const bark = new THREE.MeshStandardMaterial({
    color: 0x33281d, roughness: 0.95, bumpMap: grain(), bumpScale: 1.4 })
  const leafA = new THREE.MeshStandardMaterial({
    color: 0x2c421f, roughness: 0.94, bumpMap: grain(), bumpScale: 1.1 })
  const leafB = new THREE.MeshStandardMaterial({
    color: 0x364e26, roughness: 0.94, bumpMap: grain(), bumpScale: 1.1 })
  const trunkH = hgt * 0.46
  const r = w * 0.1
  const trunk = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.72, r * 1.25, trunkH, 12), bark)
  trunk.position.y = trunkH / 2
  trunk.castShadow = true
  g.add(trunk)
  for (const [sx, tilt] of [[-1, 0.5], [1, -0.42]] as const) {
    const b = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.34, r * 0.6, trunkH * 0.62, 8), bark)
    b.position.set(sx * w * 0.11, trunkH * 0.86, 0)
    b.rotation.z = tilt
    g.add(b)
  }
  const cy = trunkH + hgt * 0.21
  // ⚠️ WIDER THAN TALL, AND OVERLAPPING HARD. Stacked vertically the clumps read as a
  // snowman; a canopy is a broad mass with an uneven edge, so the spread is mostly
  // horizontal and every sphere intersects its neighbours rather than sitting on them.
  const CLUMPS: [number, number, number, number][] = [
    [0, 0.02, 0, 0.36], [-0.30, -0.03, 0.06, 0.28], [0.31, -0.02, -0.07, 0.29],
    [0.10, 0.12, 0.14, 0.25], [-0.14, 0.10, -0.16, 0.23], [0.02, 0.17, -0.02, 0.21],
  ]
  for (const [dx, dy, dz, k] of CLUMPS) {
    const s = new THREE.Mesh(new THREE.SphereGeometry(w * k, 16, 12),
      Math.abs(dx) > 0.1 ? leafB : leafA)
    s.position.set(dx * w, cy + dy * hgt, dz * w)
    s.castShadow = true; s.receiveShadow = true
    g.add(s)
  }
  return g
}

/** A low shrub: three squashed clumps, wider than tall. */
function bush(_m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  // A shrub stands ON the pitch, so it is lit by the key and may be a touch lighter than
  // the treeline behind the stands — but only a touch.
  // ⚠️ A SHRUB IS LIT BY THE KEY AND THE TREELINE IS NOT, so it cannot share their colour
  // — at the treeline's value it would be a black smudge on a lit floor, and at a daylight
  // green it was a bright cushion. This sits between: dark enough to belong to the scene,
  // light enough to read as a plant rather than a hole.
  const leaf = new THREE.MeshStandardMaterial({
    color: 0x35491f, roughness: 0.95, bumpMap: grain(), bumpScale: 1.3 })
  const leaf2 = new THREE.MeshStandardMaterial({
    color: 0x3e5526, roughness: 0.95, bumpMap: grain(), bumpScale: 1.3 })
  // ⚠️ FIVE CLUMPS AND ONLY LIGHTLY SQUASHED. Three flattened spheres read as a lily pad
  // from above — and above is most of what this camera sees. The taller, lumpier mass is
  // what makes it a shrub.
  for (const [dx, dz, k, i] of [[-0.28, 0.06, 0.30, 0], [0.26, -0.07, 0.29, 1],
    [0.02, 0.10, 0.36, 2], [-0.10, -0.16, 0.24, 1], [0.13, 0.19, 0.23, 0]] as const) {
    const s = new THREE.Mesh(new THREE.SphereGeometry(w * k, 14, 10), i === 1 ? leaf2 : leaf)
    s.scale.y = 0.86
    s.position.set(dx * w, hgt * 0.40, dz * w)
    s.castShadow = true; s.receiveShadow = true
    g.add(s)
  }
  return g
}

/**
 * A smith's anvil on its stump block, with a hammer leaning against it.
 *
 * ⚠️ THE WAIST IS THE WHOLE SILHOUETTE. An anvil drawn as a box with a point on it is a
 * doorstop; what says "anvil" is the pinch between the heavy base and the working face,
 * and the horn tapering off one end. Both are two extra primitives and neither is
 * optional.
 */
function anvil(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const iron = new THREE.MeshStandardMaterial({
    color: 0x2f3338, roughness: 0.52, metalness: 0.5, bumpMap: grain(), bumpScale: 0.7 })
  const blockH = hgt * 0.34
  const block = new THREE.Mesh(roundedBox(w * 0.5, blockH, w * 0.42, w * 0.03), m.body)
  block.position.x = -w * 0.16
  block.castShadow = true; block.receiveShadow = true
  g.add(block)
  const base = new THREE.Mesh(roundedBox(w * 0.42, hgt * 0.09, w * 0.3, w * 0.02), iron)
  base.position.set(-w * 0.16, blockH, 0)
  g.add(base)
  const waist = new THREE.Mesh(new THREE.CylinderGeometry(w * 0.09, w * 0.12, hgt * 0.14, 8), iron)
  waist.position.set(-w * 0.16, blockH + hgt * 0.16, 0)
  g.add(waist)
  const body = new THREE.Mesh(roundedBox(w * 0.5, hgt * 0.16, w * 0.26, w * 0.02), iron)
  body.position.set(-w * 0.14, blockH + hgt * 0.23, 0)
  body.castShadow = true
  g.add(body)
  const horn = new THREE.Mesh(new THREE.ConeGeometry(w * 0.1, w * 0.3, 12), iron)
  horn.rotation.z = -Math.PI / 2
  horn.position.set(w * 0.26, blockH + hgt * 0.31, 0)
  g.add(horn)
  // The hammer: a haft leaning on the block and a head across the top of it.
  const haft = new THREE.Mesh(new THREE.CylinderGeometry(w * 0.022, w * 0.026, hgt * 0.5, 7), m.trim)
  haft.rotation.z = 0.42
  haft.position.set(w * 0.22, hgt * 0.24, w * 0.16)
  g.add(haft)
  const head = new THREE.Mesh(roundedBox(w * 0.13, w * 0.07, w * 0.07, w * 0.015), iron)
  head.position.set(w * 0.32, hgt * 0.47, w * 0.16)
  g.add(head)
  return g
}

/**
 * A timber-framed ore bin, heaped above the rim.
 *
 * ⚠️ THIS IS THE ANSWER TO THE HEAP, AND THE FRAME IS THE ANSWER. Loose ore has no
 * silhouette of its own — tip it on open ground and it is a dome, which is exactly what
 * the old `heap` drew and exactly why it read as a blob. Put four posts and plank sides
 * round it and the object has corners, a rim line and a load spilling over one edge.
 */
function orebin(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const d = Math.max(0.6, hgt * 0.85)
  const wallH = hgt * 0.62
  const post = w * 0.055
  for (const sx of [-1, 1]) {
    for (const sz of [-1, 1]) {
      const p = new THREE.Mesh(roundedBox(post * 1.6, hgt * 0.78, post * 1.6, post * 0.3), m.trim)
      p.position.set(sx * (w / 2 - post), 0, sz * (d / 2 - post))
      p.castShadow = true
      g.add(p)
    }
  }
  // Plank sides — two courses, so the rim has a line under it rather than one flat face.
  for (const [i, k] of [0.34, 0.72].entries()) {
    for (const [ww, dd, sz, sx] of [[w, post * 1.1, 1, 0], [w, post * 1.1, -1, 0],
      [post * 1.1, d, 0, 1], [post * 1.1, d, 0, -1]] as const) {
      const pl = new THREE.Mesh(roundedBox(ww, wallH * 0.4, dd, post * 0.2), m.body)
      pl.position.set(sx * (w / 2 - post * 0.5), wallH * k - wallH * 0.2, sz * (d / 2 - post * 0.5))
      pl.receiveShadow = true
      g.add(pl)
      void i
    }
  }
  // The load: hashed lumps mounded above the rim, slumping over one side.
  for (let i = 0; i < 9; i++) {
    const h = ((i * 37) % 13) / 13
    const h2 = ((i * 53) % 11) / 11
    const r = w * (0.055 + h * 0.05)
    const lump = new THREE.Mesh(new THREE.DodecahedronGeometry(r, 0), m.rubble)
    const spill = i > 6 ? 0.62 : 0.34
    lump.position.set((h - 0.5) * w * spill * 2, wallH + r * (0.4 + h2 * 0.9),
      (h2 - 0.5) * d * 0.7)
    lump.rotation.set(h * 3, h2 * 3, h * 2)
    lump.castShadow = true
    g.add(lump)
  }
  return g
}

/**
 * A low ruined wall smothered in ivy — the piece that lets a cup stop being about metal.
 *
 * ⚠️ THE LEAF IS AUTHORED, THE STONE IS NOT. The masonry takes the venue's course like
 * every other built thing, so an overgrown wall still climbs the ladder with its league;
 * the ivy does not, because ivy is the same colour at Wood and at Apex — the same rule the
 * treeline follows.
 */
function vinewall(m: PropMats, w: number, hgt: number): THREE.Group {
  const g = new THREE.Group()
  const d = Math.max(0.5, hgt * 0.62)
  const ivyA = new THREE.MeshStandardMaterial({
    color: 0x2f4620, roughness: 0.95, bumpMap: grain(), bumpScale: 1.4 })
  const ivyB = new THREE.MeshStandardMaterial({
    color: 0x394f26, roughness: 0.95, bumpMap: grain(), bumpScale: 1.4 })
  const rows = 3
  const bh = (hgt * 0.86) / rows
  const n = Math.max(4, Math.round(w / (bh * 1.7)))
  const bw = w / n
  for (let r = 0; r < rows; r++) {
    for (let i = 0; i < n; i++) {
      const h = ((i * 29 + r * 19) % 11) / 11
      if (h < r * 0.3) continue          // the top course is the one that has fallen
      const off = r % 2 ? bw * 0.5 : 0
      const x = -w / 2 + bw * (i + 0.5) + off
      if (x > w / 2 - bw * 0.25) continue
      const blk = new THREE.Mesh(roundedBox(bw * 0.9, bh * 0.92, d, bh * 0.08), m.body)
      blk.position.set(x, bh * r, 0)
      blk.castShadow = true; blk.receiveShadow = true
      g.add(blk)
    }
  }
  // ⚠️ THE IVY IS SQUASHED SPHERES ON THE FACE, NOT A SKIN. A shell over the wall hides
  // the coursing, and the coursing is what says the green is growing on STONE. Clumps let
  // the block edges read through the gaps.
  const clumps = Math.max(5, Math.round(w * 1.1))
  for (let i = 0; i < clumps; i++) {
    const h = ((i * 41) % 17) / 17
    const h2 = ((i * 23) % 13) / 13
    const cl = new THREE.Mesh(new THREE.SphereGeometry(w * (0.045 + h * 0.05), 10, 8),
      i % 3 === 0 ? ivyB : ivyA)
    cl.scale.set(1.25, 0.8, 0.7)
    cl.position.set(-w / 2 + w * ((i + 0.5) / clumps), hgt * (0.18 + h2 * 0.72),
      d * (0.45 + h * 0.22))
    cl.castShadow = true
    g.add(cl)
  }
  return g
}

const SHAPES: Record<string, (m: PropMats, w: number, h: number) => THREE.Group> = {
  tree, bush, anvil, orebin, vinewall,
  wall, pillar, gate, dais, obelisk, ruinedwall, brokenpillar,
  colonnade,
  brokencolonnade: (m, w, h) => colonnade(m, w, h, true),
  hedge, urn, topiary, arbour, flowerbed, fountain,
  barrel, crates, logstack, stump, palisade, cart, sawhorse,
  orepile: heap, gravelbar: heap, slagheap: heap,
  leat: channel, sluice: channel,
  blowingfurnace: furnace, crucible: furnace,
  ingots: bars, tinblocks: bars,
}

/**
 * Build one piece of cover, sized to its footprint.
 *
 * ⚠️ `w` AND `d` ARE THE COLLISION RECTANGLE, AND THE HEIGHT IS NOT. The engine's
 * obstacle box is a FOOTPRINT on the ground — it has no third dimension, because
 * nothing in the sim ever needed one. The mesh's height is a presentation choice per
 * shape, exactly as the sprite's height used to be its own natural proportion. Reading
 * the footprint's depth as a height is the bug that once squashed every prop flat into
 * its own floor area.
 */
export function buildProp(
  kind: ObstacleKind | undefined, m: PropMats, w: number, d: number,
): THREE.Group {
  // Arena furniture is built from the venue's masonry, not the league's trade colours.
  const mm: PropMats = FURNITURE_KINDS.has(kind ?? '')
    ? { ...m, body: m.stone, trim: m.stoneTrim, inner: m.stone }
    : m
  const make = SHAPES[kind ?? ''] ?? heap
  const hh = HEIGHT[kind ?? ''] ?? { k: 0.5, of: 'min' as const }
  const g = make(mm, w, (hh.of === 'max' ? Math.max(w, d) : Math.min(w, d)) * hh.k)
  // ⚠️ EVERY SHAPE INVENTS ITS OWN DEPTH FROM `w`, AND NOTHING WAS CHECKING IT AGAINST THE
  // FOOTPRINT. `make` is handed a width and a HEIGHT — the authored depth `d` only ever
  // reached it as an input to that height — so a channel drew `0.47 * w` deep whatever
  // rectangle the map actually reserved. At the old 8-unit leat those agreed by luck; at
  // 20 units the trough drew 9.4 deep on a 3.1-deep footprint and covered a fifth of the
  // board in white water nothing collided with.
  // ⚠️ THE FOOTPRINT IS THE TRUTH, so the geometry is squeezed to it rather than the other
  // way round. It is the same invariant the 2D renderer has had all along — draw at the
  // footprint's width and let the art fill it — and the same one `arenas.test.ts` enforces
  // on the sprites. A player must never see cover that is deeper than the thing they
  // collide with, in either renderer.
  const box = new THREE.Box3().setFromObject(g)
  const depth = box.max.z - box.min.z
  if (depth > 1e-3) g.scale.z = d / depth
  g.traverse((o) => {
    if ((o as THREE.Mesh).isMesh) { o.castShadow = true; o.receiveShadow = true }
  })
  return g
}
