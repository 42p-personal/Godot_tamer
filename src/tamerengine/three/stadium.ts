// THE STADIUM — raked stands, a crowd, banners and floodlights around the board.
//
// ⚠️ THIS IS ALSO THE FIX FOR "THE ARENA IS FLOATING IN A VOID". A lit slab on a dark
// plane reads as an asset viewer no matter how well the slab is lit, and the fog-and-
// surround version was only ever a stopgap. A fight in a monster-taming CIRCUIT should
// be watched by somebody: the stands say what this place is, and the crowd says the
// match matters. It is the cheapest storytelling in the whole renderer.
//
// ⚠️ THE CROWD IS INSTANCED, AND IT HAS TO BE. Three thousand spectators as three
// thousand meshes is three thousand draw calls a frame and the tab dies. One merged
// body+head geometry in an InstancedMesh is ONE draw call for the entire bowl, with
// per-instance colour doing the work of variety.
//
// ⚠️ AND EVERY SPECTATOR IS HASHED FROM THEIR SEAT, NEVER ROLLED. `Math.random()` here
// would reshuffle the whole crowd on every resize and arena change — thousands of
// people teleporting between seats, which is far more distracting than no crowd at all.
// Same seat, same person, same shirt, every render.
import * as THREE from 'three'
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js'
import type { Venue } from './venue'

export interface StadiumOpts {
  /** Arena size in world units. */
  w: number
  h: number
  /** Crowd shirt palette. Muted; a crowd is a texture, not a rainbow. */
  crowd: number[]
  /** Team colours, for the banners. */
  teamA: number
  teamB: number
  /**
   * How grand the ground is — see venue.ts.
   *
   * ⚠️ THIS REPLACED THREE MODULE CONSTANTS, AND THAT WAS THE BUG. Row counts lived as
   * `const ROWS_FAR = 9` and friends, so every league on the ladder was handed the same
   * building. Wood is a knock-about on borrowed ground and Tamers Apex is the summit of
   * the circuit; they cannot be the same bowl with the timber re-tinted.
   */
  venue: Venue
}

/** Deterministic hash in [0,1) — see the file header for why this is not random. */
const h1 = (n: number): number => {
  const x = Math.sin(n * 127.1) * 43758.5453
  return x - Math.floor(x)
}

// ⚠️ THE BOWL IS SIZED BY WHAT FITS THE FRAME, NOT BY WHAT A STADIUM WOULD HAVE. Rows
// climb AWAY from the board, so every one added pushes the camera back to keep them in
// shot and shrinks the playing surface — the thing the player is actually reading. Deep
// enough to look like a crowd, shallow enough that the arena still owns the screen.
// ⚠️ THE NEAR BANK STAYS SHALLOW AT EVERY TIER. It climbs TOWARD the camera, so every
// row it gains eats a band off the bottom of the frame — at five it spent a fifth of the
// screen on the backs of people's heads. `venue.ts` ramps it 2 → 4 and no further, while
// the far bank goes 7 → 16.
const RISE = 0.62
const RUN = 1.15
const GAP = 1.6          // trackway between the arena wall and row one

/** One spectator: a body and a head, merged so the crowd is a single instanced mesh. */
function personGeometry(): THREE.BufferGeometry {
  const body = new THREE.CapsuleGeometry(0.19, 0.42, 3, 6)
  body.translate(0, 0.4, 0)
  const head = new THREE.SphereGeometry(0.16, 7, 5)
  head.translate(0, 0.86, 0)
  return mergeGeometries([body, head])!
}

interface Bank { rows: number; dir: THREE.Vector3; origin: THREE.Vector3; along: THREE.Vector3; len: number }

export function buildStadium(o: StadiumOpts): THREE.Group {
  const { w: W, h: H } = o
  const g = new THREE.Group()

  const v = o.venue
  const stoneMat = new THREE.MeshStandardMaterial({ color: v.stone, roughness: 0.93, metalness: 0.02 })
  // ⚠️ THE TRIM CARRIES THE ORNAMENT, AND ITS METALNESS RAMPS WITH IT. Gilding at the
  // top of the ladder has to actually catch the key light; nailed planks at the bottom
  // must not. One material, two ends of a ladder.
  const trimMat = new THREE.MeshStandardMaterial({
    color: v.trim, roughness: v.trimMetal > 0.5 ? 0.35 : 0.85, metalness: v.trimMetal,
  })

  // The four banks, described as (start corner, direction the rows climb, direction
  // along the seating). Building them from one description keeps every side's rake,
  // rise and run identical — four hand-placed stands would drift apart immediately.
  const banks: Bank[] = [
    { rows: v.rowsFar, dir: new THREE.Vector3(0, 0, -1), origin: new THREE.Vector3(0, 0, -GAP), along: new THREE.Vector3(1, 0, 0), len: W },
    { rows: v.rowsNear, dir: new THREE.Vector3(0, 0, 1), origin: new THREE.Vector3(0, 0, H + GAP), along: new THREE.Vector3(1, 0, 0), len: W },
    { rows: v.rowsEnd, dir: new THREE.Vector3(-1, 0, 0), origin: new THREE.Vector3(-GAP, 0, 0), along: new THREE.Vector3(0, 0, 1), len: H },
    { rows: v.rowsEnd, dir: new THREE.Vector3(1, 0, 0), origin: new THREE.Vector3(W + GAP, 0, 0), along: new THREE.Vector3(0, 0, 1), len: H },
  ]

  // ── the raked steps ──────────────────────────────────────────────────────
  const seats: { pos: THREE.Vector3; bank: number }[] = []
  banks.forEach((b, bi) => {
    for (let r = 0; r < b.rows; r++) {
      const y = (r + 1) * RISE
      const off = r * RUN
      const centre = b.origin.clone()
        .addScaledVector(b.dir, off + RUN / 2)
        .add(b.along.clone().multiplyScalar(b.len / 2))
      centre.y = y / 2
      // ⚠️ THE STEP IS SOLID DOWN TO THE GROUND, not a floating slab. A rake made of
      // hovering planks shows daylight under every row from this camera height.
      const isX = Math.abs(b.along.x) > 0.5
      const step = new THREE.Mesh(
        new THREE.BoxGeometry(isX ? b.len + off * 2 + RUN : RUN, y, isX ? RUN : b.len + off * 2 + RUN),
        stoneMat,
      )
      step.position.copy(centre)
      step.receiveShadow = true
      step.castShadow = r < 3          // only the front rows can reach the board
      g.add(step)

      // ⚠️ A SEAT BACK PER ROW IS WHAT TURNS STEPS INTO SEATING. Without it a stand is
      // a staircase with people standing on it — which is exactly right for a Wood
      // knock-about and exactly wrong for anything with a roof. One thin box per row,
      // in trim, and the whole bowl stops reading as scaffolding.
      if (v.seatBacks) {
        const backH = RISE * 0.52
        const bar = new THREE.Mesh(
          new THREE.BoxGeometry(isX ? b.len + off * 2 + RUN : 0.14, backH, isX ? 0.14 : b.len + off * 2 + RUN),
          trimMat,
        )
        bar.position.copy(centre)
        bar.position.y = y + backH / 2
        bar.position.addScaledVector(b.dir, RUN * 0.42)
        bar.castShadow = true; bar.receiveShadow = true
        g.add(bar)
      }

      // seats along this row
      const n = Math.floor((b.len + off * 2) / 0.62)
      for (let i = 0; i < n; i++) {
        const t = (i + 0.5) / n
        const p = b.origin.clone()
          .addScaledVector(b.dir, off + RUN * 0.55)
          .add(b.along.clone().multiplyScalar((t - 0.5) * (b.len + off * 2)))
        p.y = y
        seats.push({ pos: p, bank: bi })
      }
    }
  })

  // ── the crowd ────────────────────────────────────────────────────────────
  // ⚠️ GAPS ARE LOAD-BEARING. A perfectly full bowl reads as a printed pattern, the
  // same failure the hex board hit — it is the empty seats and the uneven heights that
  // make it look like people rather than wallpaper.
  const taken = seats.filter((_, i) => h1(i * 3.7) < v.fill)
  const crowd = new THREE.InstancedMesh(
    personGeometry(),
    new THREE.MeshStandardMaterial({ roughness: 0.95, metalness: 0 }),
    taken.length,
  )
  const m4 = new THREE.Matrix4(); const q = new THREE.Quaternion()
  const scl = new THREE.Vector3(); const col = new THREE.Color()
  taken.forEach((s, i) => {
    const a = h1(i * 1.7), b = h1(i * 5.3), c = h1(i * 9.1)
    // Everyone faces the middle of the board, with a few degrees of lean and turn.
    const face = Math.atan2(W / 2 - s.pos.x, H / 2 - s.pos.z) + (b - 0.5) * 0.5
    q.setFromEuler(new THREE.Euler(0, face, (c - 0.5) * 0.12))
    scl.setScalar(0.86 + a * 0.3)
    m4.compose(
      new THREE.Vector3(s.pos.x + (b - 0.5) * 0.16, s.pos.y, s.pos.z + (c - 0.5) * 0.12),
      q, scl,
    )
    crowd.setMatrixAt(i, m4)
    // Team-coloured blocks behind each end, plain cloth everywhere else — a crowd
    // that is all one palette has no sides in it.
    const home = s.bank === 2, away = s.bank === 3
    const shirt = home && a > 0.62 ? o.teamA : away && a > 0.62 ? o.teamB
      : o.crowd[Math.floor(a * o.crowd.length) % o.crowd.length]
    // ⚠️ DARKENED HARD. The crowd is BACKGROUND — at full value the stands out-read the
    // board, and the board is the only part the player is actually playing.
    crowd.setColorAt(i, col.setHex(shirt).multiplyScalar(0.34 + b * 0.34))
  })
  crowd.castShadow = false      // thousands of shadow casters for no visible gain
  crowd.receiveShadow = true
  g.add(crowd)

  // ── the barrier between crowd and floor ──────────────────────────────────
  // ⚠️ THIS RING IS THE MOST VALUABLE SURFACE IN THE WHOLE BOWL, because it is the only
  // part of the structure the camera is always pointed at. Everything behind the front
  // row is off-frame at every tier — so the ladder's ornament goes HERE first and in the
  // back rows last, which is the opposite of how a real stadium would be built.
  for (const b of banks) {
    const isX = Math.abs(b.along.x) > 0.5
    const len = b.len + GAP * 2
    const at = b.origin.clone()
      .addScaledVector(b.dir, -0.1)
      .add(b.along.clone().multiplyScalar(b.len / 2))

    if (!v.balustrade) {
      const rail = new THREE.Mesh(
        new THREE.BoxGeometry(isX ? len : 0.22, 1.05, isX ? 0.22 : len), trimMat)
      rail.position.set(at.x, 0.52, at.z)
      rail.castShadow = true; rail.receiveShadow = true
      g.add(rail)
    } else {
      // A turned balustrade: capping rail, plinth, and lathed balusters between. Three
      // pieces of geometry that cost almost nothing and read as dressed stone rather
      // than as a fence.
      for (const [yy, hh, ww] of [[0.12, 0.24, 0.34], [1.0, 0.2, 0.36]] as const) {
        const band = new THREE.Mesh(
          new THREE.BoxGeometry(isX ? len : ww, hh, isX ? ww : len), stoneMat)
        band.position.set(at.x, yy, at.z)
        band.castShadow = true; band.receiveShadow = true
        g.add(band)
      }
      const prof: THREE.Vector2[] = []
      for (let i = 0; i <= 10; i++) {
        const t = i / 10
        prof.push(new THREE.Vector2(0.055 + 0.055 * Math.sin(t * Math.PI) ** 2, t * 0.7))
      }
      const baluster = new THREE.LatheGeometry(prof, 10)
      const count = Math.max(6, Math.round(len / 0.62))
      const rowMesh = new THREE.InstancedMesh(baluster, stoneMat, count)
      const mm = new THREE.Matrix4()
      for (let i = 0; i < count; i++) {
        const t = (i + 0.5) / count - 0.5
        mm.makeTranslation(
          at.x + (isX ? t * len : 0), 0.24, at.z + (isX ? 0 : t * len))
        rowMesh.setMatrixAt(i, mm)
      }
      rowMesh.castShadow = true; rowMesh.receiveShadow = true
      g.add(rowMesh)
    }
  }

  // ── banners on the end barriers, in the two team colours ─────────────────
  for (const [side, colour] of [[2, o.teamA], [3, o.teamB]] as const) {
    const b = banks[side]
    for (let i = 0; i < v.banners; i++) {
      const t = (i + 1) / (v.banners + 1)
      const banner = new THREE.Mesh(
        new THREE.PlaneGeometry(1.5, 0.72),
        new THREE.MeshStandardMaterial({ color: colour, roughness: 0.9, side: THREE.DoubleSide }),
      )
      const p = b.origin.clone().add(b.along.clone().multiplyScalar((t - 0.5) * b.len + b.len / 2))
      banner.position.set(p.x - b.dir.x * 0.13, 0.55, p.z)
      banner.rotation.y = b.dir.x > 0 ? -Math.PI / 2 : Math.PI / 2
      g.add(banner)
    }
  }

  // ── the floor ────────────────────────────────────────────────────────────
  // ⚠️ INLAY GOES ON THE FLOOR BECAUSE THE FLOOR IS HALF THE FRAME. It is the single
  // largest surface the camera sees and until now it was bare boards at every tier — a
  // gilt border and a centre medallion do more for "this is a grand ground" than another
  // four rows of seating nobody can see, and they cost two flat meshes.
  // ⚠️ THEY SIT BELOW THE DEPLOY HEXES (y 0.03) AND ABOVE THE GROUND. Coplanar with
  // either and they z-fight.
  const inlayMat = new THREE.MeshStandardMaterial({
    color: v.trim, roughness: 0.4, metalness: Math.max(0.3, v.trimMetal),
    emissive: v.trim, emissiveIntensity: v.tier >= 8 ? 0.28 : 0.08,
  })
  for (let i = 0; i < v.floorInlay; i++) {
    const inset = 1.1 + i * 0.7
    const band = 0.16 + (v.floorInlay - i) * 0.05
    const sh = new THREE.Shape()
    sh.moveTo(inset, inset)
    sh.lineTo(W - inset, inset); sh.lineTo(W - inset, H - inset)
    sh.lineTo(inset, H - inset); sh.lineTo(inset, inset)
    const hole = new THREE.Path()
    hole.moveTo(inset + band, inset + band)
    hole.lineTo(W - inset - band, inset + band); hole.lineTo(W - inset - band, H - inset - band)
    hole.lineTo(inset + band, H - inset - band); hole.lineTo(inset + band, inset + band)
    sh.holes.push(hole)
    const geo = new THREE.ShapeGeometry(sh)
    geo.rotateX(-Math.PI / 2)
    const m = new THREE.Mesh(geo, inlayMat)
    m.position.y = 0.016
    g.add(m)
  }
  if (v.medallion) {
    const cx0 = W / 2, cz0 = H / 2, r0 = Math.min(W, H) * 0.13
    for (const [ri, ro] of [[r0 * 0.94, r0], [r0 * 0.52, r0 * 0.6]] as const) {
      const ring = new THREE.Mesh(new THREE.RingGeometry(ri, ro, 48), inlayMat)
      ring.rotation.x = -Math.PI / 2
      ring.position.set(cx0, 0.018, cz0)
      g.add(ring)
    }
    // Four quadrant wedges outside the ring — the mosaic a ground lays once it has been
    // running long enough to have a coat of arms.
    if (v.mosaic) {
      for (let q = 0; q < 4; q++) {
        const wedge = new THREE.Mesh(
          new THREE.RingGeometry(r0 * 1.25, r0 * 1.62, 24, 1, q * Math.PI / 2 + 0.14, Math.PI / 2 - 0.28),
          inlayMat)
        wedge.rotation.x = -Math.PI / 2
        wedge.position.set(cx0, 0.017, cz0)
        g.add(wedge)
      }
    }
    // Twelve rays out of the centre — a sunburst, which is what a circuit that has been
    // running long enough to have heraldry would put under its champions' feet.
    for (let i = 0; i < 12; i++) {
      const a = (i / 12) * Math.PI * 2
      const ray = new THREE.Mesh(new THREE.PlaneGeometry(r0 * 0.34, 0.12), inlayMat)
      ray.rotation.x = -Math.PI / 2
      ray.rotation.z = -a
      ray.position.set(cx0 + Math.cos(a) * r0 * 0.76, 0.018, cz0 + Math.sin(a) * r0 * 0.76)
      g.add(ray)
    }
  }

  // ── ornament ─────────────────────────────────────────────────────────────
  // ⚠️ ORNAMENT IS FREE IN SCREEN SPACE AND ROWS ARE NOT, which is why the ladder is
  // mostly built out of this rather than out of a bigger bowl. Every row added pushes
  // the camera back and shrinks the playing surface; a colonnade behind the existing top
  // row costs nothing the player was looking at.
  // ⚠️ ON THE TRACKWAY, NOT BEHIND THE STANDS. The first version put the colonnade
  // behind the back row, which is architecturally sensible and completely invisible —
  // the camera frames the board, so anything past the front rows is off-frame at every
  // tier. This ring of columns stands between the floor and the barrier, where it is
  // always in shot and reads against the crowd behind it.
  /**
   * How wide a hole the victory arch punches in the far colonnade, 0 when there is none.
   *
   * ⚠️ THE ARCH IS PART OF THE COLONNADE, WHICH IS THE THIRD PLACE IT HAS BEEN BUILT AND
   * THE FIRST ONE THE CAMERA CAN SEE. It began INSIDE the far stand (`-GAP * 2.6`, four
   * units behind a bank that runs twenty deep at tier 10) and was then moved BEYOND the
   * bowl, sized off it, which is architecturally right and still invisible: the shipped
   * camera frames the BOARD, so the far roofline is the top of the picture and nothing
   * past it is ever in shot. Both times Apex rendered as Tamer Elite with an ornament
   * nobody could point at.
   *
   * ⚠️ THE LESSON IS ALREADY WRITTEN IN `venue.ts` ABOUT THE FIRST COLONNADE — "grandeur
   * has to be built where the shot is" — and this is the same mistake made twice more
   * after it. The trackway is the only ring of space that is always in frame, so the
   * summit's arch stands on it: the centre bays of the far arcade are omitted and one
   * monumental arch is sprung across the gap, rising well above the colonnade and reading
   * against the crowd behind it. That is also what a triumphal arch is FOR — the champions
   * walk out under it, and now the camera can watch them do it.
   */
  const archSpan = v.victoryArch ? Math.min(W * 0.22, 12) : 0
  const archHalf = archSpan / 2
  /** Is this x inside the arch's opening? Far-side ornament skips it. */
  const inArch = (x: number) => archHalf > 0 && Math.abs(x - W / 2) < archHalf - 0.4
  /** The far run, split either side of the arch: `[centre, width]` per segment. */
  const farSegs: [number, number][] = archHalf > 0
    ? [[(-GAP + W / 2 - archHalf) / 2, W / 2 - archHalf + GAP],
      [(W + GAP + W / 2 + archHalf) / 2, W / 2 - archHalf + GAP]]
    : [[W / 2, W + GAP * 2]]

  if (v.columns !== 'none') {
    // ⚠️ THE NEAR SIDE TAKES COLUMNS BUT NEVER ARCHES OR AN ENTABLATURE. Anything
    // spanning ABOVE the near trackway sits between the camera and the board and cuts
    // the front rank in half — the same reason the canopy only covers the far stand. A
    // ground that is grander at the back than the front is architecturally odd and is
    // the only version that can actually be watched.
    const fluted = v.columns !== 'plain'
    const shaftMat = fluted
      ? new THREE.MeshStandardMaterial({ color: v.stone, roughness: 0.9, flatShading: true })
      : stoneMat
    const HGT = fluted ? 5.6 : 4.2
    const top = HGT + 0.5

    interface Col { x: number; z: number; near: boolean; along: 'x' | 'z' }
    const ring: Col[] = []
    const nx = Math.max(3, Math.round(W / 6)), nz = Math.max(2, Math.round(H / 6))
    for (let i = 0; i <= nx; i++) {
      const x = (i / nx) * W
      ring.push({ x, z: -GAP * 0.55, near: false, along: 'x' })
      ring.push({ x, z: H + GAP * 0.55, near: true, along: 'x' })
    }
    for (let i = 1; i < nz; i++) {
      const z = (i / nz) * H
      ring.push({ x: -GAP * 0.55, z, near: false, along: 'z' })
      ring.push({ x: W + GAP * 0.55, z, near: false, along: 'z' })
    }

    for (const c of ring) {
      // The arch's own piers stand where these would; two orders in one bay reads as a
      // mistake rather than as a monument.
      if (c.along === 'x' && !c.near && inArch(c.x)) continue
      // Fluted shafts are faceted on purpose: 12 flat-shaded segments read as the
      // grooves of a classical order, where a smooth 24-segment cylinder reads as pipe.
      const shaft = new THREE.Mesh(
        new THREE.CylinderGeometry(0.28, 0.36, HGT, fluted ? 12 : 16), shaftMat)
      shaft.position.set(c.x, HGT / 2 + 0.4, c.z)
      shaft.castShadow = true; shaft.receiveShadow = true
      g.add(shaft)
      for (const [yy, rb, rt, hh] of [[0.2, 0.56, 0.5, 0.4], [0.5, 0.48, 0.42, 0.22]] as const) {
        const base = new THREE.Mesh(new THREE.CylinderGeometry(rt, rb, hh, 16), stoneMat)
        base.position.set(c.x, yy, c.z)
        base.castShadow = true
        g.add(base)
      }
      const cap = new THREE.Mesh(new THREE.CylinderGeometry(0.56, 0.36, 0.46, 16), trimMat)
      cap.position.set(c.x, top - 0.2, c.z)
      cap.castShadow = true
      g.add(cap)
      if (!fluted) {
        const fin = new THREE.Mesh(new THREE.OctahedronGeometry(0.3, 0), trimMat)
        fin.position.set(c.x, top + 0.3, c.z)
        g.add(fin)
      }
    }

    // ── the entablature: one beam across every capital ─────────────────────
    if (v.entablature) {
      const runs: [number, number, number, number][] = [
        // ⚠️ THE FAR RUN IS A PAIR OF SEGMENTS WHENEVER THE ARCH IS UP. One beam across the
        // whole width would pass straight through the arch's opening at pier height — a
        // lintel drawn across a doorway, which reads as clipping rather than as masonry.
        ...farSegs.map(([cx, sw]) => [cx, -GAP * 0.55, sw, 0.66] as [number, number, number, number]),
        [-GAP * 0.55, H / 2, 0.66, H + GAP * 2],
        [W + GAP * 0.55, H / 2, 0.66, H + GAP * 2],
      ]
      for (const [x, z, sw, sd] of runs) {
        const arch = new THREE.Mesh(new THREE.BoxGeometry(sw, 0.5, sd), stoneMat)
        arch.position.set(x, top + 0.28, z)
        arch.castShadow = true; arch.receiveShadow = true
        g.add(arch)
        const cornice = new THREE.Mesh(new THREE.BoxGeometry(sw + 0.3, 0.16, sd + 0.3), trimMat)
        cornice.position.set(x, top + 0.6, z)
        g.add(cornice)
      }
    }

    // ── the arcade: arches sprung between neighbours ───────────────────────
    if (v.columns === 'arcade') {
      const spanX = W / nx, spanZ = H / nz
      const arc = (cx: number, cz: number, span: number, axis: 'x' | 'z') => {
        const r = span / 2
        const m = new THREE.Mesh(
          new THREE.TorusGeometry(r, 0.17, 8, 20, Math.PI), stoneMat)
        m.position.set(cx, top - 0.3, cz)
        if (axis === 'z') m.rotation.y = Math.PI / 2
        m.castShadow = true; m.receiveShadow = true
        g.add(m)
      }
      for (let i = 0; i < nx; i++) {
        const cx = (i + 0.5) * spanX
        if (inArch(cx)) continue
        arc(cx, -GAP * 0.55, spanX, 'x')
      }
      for (let i = 0; i < nz; i++) {
        arc(-GAP * 0.55, (i + 0.5) * spanZ, spanZ, 'z')
        arc(W + GAP * 0.55, (i + 0.5) * spanZ, spanZ, 'z')
      }
    }

    // ── pennant lines strung between the finials ───────────────────────────
    if (v.pennants) {
      const line = (x: number, z: number, sw: number, sd: number, colour: number) => {
        const cord = new THREE.Mesh(new THREE.BoxGeometry(sw, 0.06, sd),
          new THREE.MeshStandardMaterial({ color: colour, roughness: 0.9 }))
        cord.position.set(x, top + 0.9, z)
        g.add(cord)
        const n = Math.round(Math.max(sw, sd) / 1.6)
        for (let i = 0; i < n; i++) {
          const t = (i + 0.5) / n - 0.5
          const flag = new THREE.Mesh(new THREE.ConeGeometry(0.2, 0.5, 4),
            new THREE.MeshStandardMaterial({
              color: i % 2 ? o.teamA : o.teamB, roughness: 0.95, side: THREE.DoubleSide,
            }))
          flag.position.set(x + (sw > sd ? t * sw : 0), top + 0.62, z + (sd > sw ? t * sd : 0))
          flag.rotation.x = Math.PI
          g.add(flag)
        }
      }
      for (const [cx, sw] of farSegs) line(cx, -GAP * 0.55, sw - GAP * 2, 0.06, v.trim)
      line(-GAP * 0.55, H / 2, 0.06, H, v.trim)
      line(W + GAP * 0.55, H / 2, 0.06, H, v.trim)
    }
  }

  // ── a stepped masonry course round the floor ──────────────────────────────
  // ⚠️ IT SITS BETWEEN THE FLOOR AND THE BALUSTRADE, WHICH IS EXACTLY WHERE THE EYE
  // ALREADY IS. Two shallow steps for almost no geometry, and the arena stops being a
  // rectangle painted on the ground and starts being a thing set INTO one.
  // ⚠️ FOUR BARS, NOT A BOX. `BoxGeometry` is SOLID — the first version laid two of them
  // centred on the arena and paved straight over the entire playing surface, medallion,
  // inlay, hexes and all. A course is a FRAME; the only thing it may touch is the margin
  // between the floor and the balustrade.
  if (v.baseCourse) {
    for (const [out, yy, hh] of [[GAP, 0.07, 0.14], [GAP * 0.6, 0.2, 0.14]] as const) {
      for (const [x, z, sw, sd] of [
        [W / 2, -out / 2, W + out * 2, out],
        [W / 2, H + out / 2, W + out * 2, out],
        [-out / 2, H / 2, out, H],
        [W + out / 2, H / 2, out, H],
      ] as const) {
        const bar = new THREE.Mesh(new THREE.BoxGeometry(sw, hh, sd), stoneMat)
        bar.position.set(x, yy, z)
        bar.receiveShadow = true; bar.castShadow = true
        g.add(bar)
      }
    }
  }

  // ── corner turrets ────────────────────────────────────────────────────────
  if (v.turrets) {
    /**
     * ⚠️ IN THE CORNER GAP BETWEEN TWO BANKS, WHICH IS BOTH THE VISIBLE PLACE AND THE
     * CORRECT ONE. This has now been wrong twice in opposite directions: at `GAP * 1.5` the
     * turrets stood 2.4 units off the floor, buried in the first rows of both banks, so
     * nine units of masonry bought four cone tips in the seating; pushed out to
     * `GAP + rowsEnd * RUN * 0.82` they cleared the bowl properly and left the frame
     * entirely, because `scene3d.ts` fits the BOARD and the bowl is explicitly allowed off
     * the edges. Architecturally right and invisible is the same failure the victory arch
     * and the first colonnade both made.
     *
     * The four banks are separate rectangles, so where they meet there is a real HOLE in
     * the bowl at each corner — visible as a dark notch in every tier-7+ render. A stair
     * tower is what a ground actually puts there. Sitting it a few rows in fills the notch,
     * keeps it inside the frame, and only has to clear the bank rather than the whole
     * stadium — which is what brings its height back under the ceiling.
     */
    const tOff = GAP + Math.min(v.rowsEnd, 4) * RUN
    const turretH = v.rowsFar * RISE + 0.2
    for (const [x, z] of [[-tOff, -tOff], [W + tOff, -tOff],
      [-tOff, H + tOff], [W + tOff, H + tOff]]) {
      const body = new THREE.Mesh(new THREE.CylinderGeometry(1.5, 1.75, turretH, 14), stoneMat)
      body.position.set(x, turretH / 2, z)
      body.castShadow = true; body.receiveShadow = true
      g.add(body)
      const band = new THREE.Mesh(new THREE.CylinderGeometry(1.72, 1.72, 0.4, 14), trimMat)
      band.position.set(x, turretH - 0.4, z)
      g.add(band)
      const roof = new THREE.Mesh(new THREE.ConeGeometry(2.0, 3.4, 14), trimMat)
      roof.position.set(x, turretH + 1.7, z)
      roof.castShadow = true
      g.add(roof)
      const spike = new THREE.Mesh(new THREE.OctahedronGeometry(0.34, 0), trimMat)
      spike.position.set(x, turretH + 3.7, z)
      g.add(spike)
    }
  }

  // ── the victory arch, sprung across the centre of the far colonnade ──────
  // The one piece of the ground that exists purely to be walked out under.
  if (archHalf > 0) {
    // ⚠️ ON THE COLONNADE LINE, AT THE COLONNADE'S DEPTH. `-GAP * 0.55` is where the
    // far columns stand and `GAP` is 1.6 units wide, so the piers are 1.4 deep — a
    // monument that overhangs the trackway would be built into the barrier at the back
    // and over the playing surface at the front.
    const z0 = -GAP * 0.55
    /**
     * ⚠️ THERE IS A HARD CEILING ON THIS AND IT IS ABOUT FIFTEEN UNITS. `scene3d.ts`
     * frames the BOARD — `fit(0.998)`, with "the bowl allowed off the edges" — so the top
     * of the picture sits a fixed distance above the far barrier however tall the bowl
     * gets. The first trackway version crowned at 15.4 with another six units of attic and
     * standards above it, and the whole crest was cropped: a monument you can only see the
     * legs of is the invisible-ornament bug again, one step milder.
     *
     * So the arch is sized DOWN to its frame rather than up to its importance. It crowns
     * near 10 against an arcade that tops out at 6.1, and spans twice a colonnade bay —
     * proportion is what makes it read as a monument, not absolute height.
     */
    const pierH = 4.0
    const crown = pierH + archHalf
    for (const sx of [-1, 1]) {
      const pier = new THREE.Mesh(new THREE.BoxGeometry(1.7, pierH, 1.4), stoneMat)
      pier.position.set(W / 2 + sx * archHalf, pierH / 2, z0)
      pier.castShadow = true; pier.receiveShadow = true
      g.add(pier)
      const plinth = new THREE.Mesh(new THREE.BoxGeometry(2.2, 0.55, 1.9), stoneMat)
      plinth.position.set(W / 2 + sx * archHalf, 0.28, z0)
      plinth.castShadow = true
      g.add(plinth)
      const impost = new THREE.Mesh(new THREE.BoxGeometry(2.1, 0.4, 1.8), trimMat)
      impost.position.set(W / 2 + sx * archHalf, pierH - 0.2, z0)
      g.add(impost)
    }
    const vault = new THREE.Mesh(
      new THREE.TorusGeometry(archHalf, 0.85, 12, 28, Math.PI), stoneMat)
    vault.position.set(W / 2, pierH, z0)
    vault.castShadow = true
    g.add(vault)
    const keystone = new THREE.Mesh(new THREE.BoxGeometry(1.3, 1.7, 1.6), trimMat)
    keystone.position.set(W / 2, crown + 0.2, z0)
    keystone.castShadow = true
    g.add(keystone)
    const attic = new THREE.Mesh(new THREE.BoxGeometry(archSpan + 2.6, 2.2, 1.7), stoneMat)
    attic.position.set(W / 2, crown + 1.9, z0)
    attic.castShadow = true; attic.receiveShadow = true
    g.add(attic)
    const cornice = new THREE.Mesh(new THREE.BoxGeometry(archSpan + 3.4, 0.5, 2.1), trimMat)
    cornice.position.set(W / 2, crown + 3.25, z0)
    cornice.castShadow = true
    g.add(cornice)
    // ⚠️ ONE FINIAL, ON THE AXIS, AND NOTHING FLANKING IT. A quadriga is out of scope and
    // a pair of standards on the attic corners is where the last unit of the height budget
    // went — they were the first thing the frame cut off. The centre staff is the only
    // crest that fits under the ceiling described above.
    const staff = new THREE.Mesh(new THREE.CylinderGeometry(0.11, 0.14, 1.1, 8), trimMat)
    staff.position.set(W / 2, crown + 3.6, z0)
    g.add(staff)
    const orb = new THREE.Mesh(new THREE.SphereGeometry(0.34, 14, 10), trimMat)
    orb.position.set(W / 2, crown + 4.3, z0)
    g.add(orb)
  }

  // Braziers: emissive bowls on the trackway. ⚠️ EMISSIVE, NOT LIGHTS — twelve more
  // shadow-casting lamps would twelve times the shadow cost for something the bloom pass
  // already sells, and the key light is what the eye reads as the source.
  if (v.braziers > 0) {
    const fireMat = new THREE.MeshStandardMaterial({
      color: 0xffb257, emissive: 0xff9a3c, emissiveIntensity: 3.2, roughness: 0.5,
    })
    for (let i = 0; i < v.braziers; i++) {
      const t = (i + 0.5) / v.braziers
      const per = Math.PI * 2 * t
      const x = W / 2 + Math.cos(per) * (W / 2 + GAP * 0.75)
      const z = H / 2 + Math.sin(per) * (H / 2 + GAP * 0.75)
      const stand = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.22, 1.5, 10), trimMat)
      stand.position.set(x, 0.75, z)
      stand.castShadow = true
      g.add(stand)
      const bowl = new THREE.Mesh(new THREE.CylinderGeometry(0.42, 0.2, 0.34, 12), trimMat)
      bowl.position.set(x, 1.62, z)
      g.add(bowl)
      const fire = new THREE.Mesh(new THREE.IcosahedronGeometry(0.3, 0), fireMat)
      fire.position.set(x, 1.86, z)
      fire.scale.y = 1.5
      g.add(fire)
    }
  }

  // Corner statues on plinths — the summit's own flourish.
  if (v.statues) {
    for (const [x, z] of [[-GAP, -GAP], [W + GAP, -GAP], [-GAP, H + GAP], [W + GAP, H + GAP]]) {
      const plinth = new THREE.Mesh(new THREE.BoxGeometry(1.5, 1.9, 1.5), stoneMat)
      plinth.position.set(x, 0.95, z)
      plinth.castShadow = true; plinth.receiveShadow = true
      g.add(plinth)
      const cap2 = new THREE.Mesh(new THREE.BoxGeometry(1.75, 0.2, 1.75), trimMat)
      cap2.position.set(x, 1.98, z)
      g.add(cap2)
      // A figure, abstracted: torso, head, and a raised arm. Read at this distance it is
      // a champion cast in the trim metal; read closely it is three primitives, which is
      // the right trade for something forty units from the camera.
      const body = new THREE.Mesh(new THREE.CapsuleGeometry(0.3, 1.0, 4, 10), trimMat)
      body.position.set(x, 2.9, z)
      body.castShadow = true
      g.add(body)
      const head = new THREE.Mesh(new THREE.SphereGeometry(0.26, 12, 9), trimMat)
      head.position.set(x, 3.72, z)
      g.add(head)
      const arm = new THREE.Mesh(new THREE.CapsuleGeometry(0.11, 0.9, 3, 7), trimMat)
      arm.position.set(x + 0.36, 3.5, z)
      arm.rotation.z = -0.5
      g.add(arm)
    }
  }
  if (v.canopy) {
    // A roof over the far stand only — the mark of a permanent ground, and the near
    // side must stay open or it would close over the camera.
    // ⚠️ IT SITS ON THE BACK OF THE STAND, NOT ABOVE THE WHOLE BOWL. Spanning the full
    // rake at a clear height read as a slab hanging in mid-air over the crowd — a roof
    // has to be attached to something. This covers the back two thirds only, with its
    // front edge just above the seats it shelters, so the eaves and the top rows meet.
    const b = banks[0]
    const back = b.rows * RUN
    const depth = back * 0.68
    const top = b.rows * RISE
    const roof = new THREE.Mesh(new THREE.BoxGeometry(W + back * 1.4, 0.3, depth), trimMat)
    roof.position.set(W / 2, top + 2.1, -GAP - back + depth / 2 - 0.4)
    roof.rotation.x = 0.16                      // eaves drop toward the field
    roof.castShadow = true
    g.add(roof)
    // Posts, or the roof is still floating — this is the difference between "a canopy"
    // and "a rectangle that happens to be up there".
    const n = Math.max(3, Math.round(W / 7))
    for (let i = 0; i < n; i++) {
      const x = ((i + 0.5) / n - 0.5) * (W + back) + W / 2
      const post = new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.16, 2.4, 8), trimMat)
      post.position.set(x, top + 1.0, -GAP - back + depth - 0.6)
      post.castShadow = true
      g.add(post)
    }
  }

  // ── floodlights ──────────────────────────────────────────────────────────
  // ⚠️ EMISSIVE, NOT ACTUAL LIGHTS. Four more shadow-casting lamps would quadruple the
  // shadow cost for an effect the bloom pass already sells — the lamp heads glow and
  // bleed, and the KEY light is what the eye reads as the source. One real light with
  // one shadow map is the whole lighting rig, on purpose.
  const headMat = new THREE.MeshStandardMaterial({
    color: 0xfff4d8, emissive: 0xffe9b8, emissiveIntensity: 2.4, roughness: 0.4,
  })
  const reach = (v.rowsEnd + 2) * RUN
  for (const [x, z] of [[-reach, -reach], [W + reach, -reach], [-reach, H + reach], [W + reach, H + reach]]) {
    const poleH = (v.rowsFar + 5) * RISE + 4
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.16, 0.24, poleH, 8), trimMat)
    pole.position.set(x, poleH / 2, z)
    pole.castShadow = true
    g.add(pole)
    const head = new THREE.Mesh(new THREE.BoxGeometry(1.5, 0.55, 0.5), headMat)
    head.position.set(x, poleH, z)
    head.lookAt(W / 2, 0, H / 2)
    g.add(head)
  }

  // ── the treeline ─────────────────────────────────────────────────────────
  /**
   * ⚠️ SET BACK BEYOND THE BANK AND TALL ENOUGH TO CLEAR IT, which is the only placement
   * that works. The trackway is 1.6 units wide — nothing stands ringside — and a tree
   * behind a stand it cannot see over is a tree nobody sees. So the line is pushed out
   * past the deepest bank and its height is taken from the bank's own, not from a
   * constant: a four-row Wood bank and a sixteen-row Apex bank need very different trees.
   *
   * ⚠️ IT SHOWED ON 5 BOARDS OF 14, AND MAKING THE TREES TALLER DID NOT FIX IT. Rendering
   * every authored ground at its own rung is the only way this was ever going to be
   * caught, and the first two guesses — taller trees, then a line pushed further back —
   * were both wrong. `_framecheck` projects `scene3d.ts`'s exact camera fit and reports
   * the highest world-y that still lands inside the frame:
   *
   *     board              bank |  ceiling at depth behind the far bank      | side
   *                             |  +0     +4     +8    +14    +22            | ceiling
   *     copper-ingotyard   5.0  |  3.2    1.3    0.0    0.0    0.0           |  12.3
   *     iron-quenchpool    6.8  |  3.7    1.8    0.0    0.0    0.0           |  15.1
   *     bronze-longcast    6.2  | 12.5   10.6    8.8    6.0    2.2           |  21.9
   *
   * ⚠️ THE CEILING FALLS WITH DEPTH, WHICH IS THE OPPOSITE OF THE INTUITION. The camera
   * looks DOWN at 38°, so the top-of-frame ray descends toward the ground as it travels
   * away: every unit further back COSTS height rather than buying it. The line had been
   * sitting at +4 to +7, where three of the leagues have a ceiling of literally zero —
   * on a square board the far bank's own top row is already cropped, so no tree behind
   * it can ever be seen at any height.
   *
   * ⚠️ AND THE SIDES HAVE THREE TO FOUR TIMES THE HEADROOM — 12.3 to 21.9 against the
   * same bank tops. The frame is 16:9 and the board's WIDTH is what binds it, so there
   * is always slack at the left and right edges and almost none at the top. So the wood
   * is now mostly a SIDE planting, denser, hard against the end banks, with a far line
   * kept tight at +1.5 that reads on the wide boards and crops harmlessly on the square
   * ones. That is also just what a ground looks like: trees down the flanks where there
   * is room for them.
   *
   * ⚠️ WHICH MATTERS MORE HERE THAN ANYWHERE, because the treeline is the WHOLE of
   * Copper's and Tin's grandeur — two entire leagues whose one rung showed up on a third
   * of their boards.
   *
   * ⚠️ AND NOTHING ON THE NEAR SIDE. The camera looks OVER the near bank, so anything
   * placed behind it sits between the lens and the board.
   *
   * ⚠️ HASHED OFF POSITION, NEVER Math.random. The scene rebuilds on every resize and
   * lens toggle; a random line would make the whole wood hop each time.
   */
  if (v.treeline) {
    const bark = new THREE.MeshStandardMaterial({ color: 0x33281d, roughness: 0.95 })
    const leafA = new THREE.MeshStandardMaterial({ color: 0x2c421f, roughness: 0.94 })
    const leafB = new THREE.MeshStandardMaterial({ color: 0x364e26, roughness: 0.94 })
    const hash = (n: number) => {
      const x = Math.sin(n * 127.1) * 43758.5453
      return x - Math.floor(x)
    }
    const farDepth = GAP + v.rowsFar * RUN
    const endDepth = GAP + v.rowsEnd * RUN
    const bankTop = v.rowsFar * RISE
    const tree = (cx: number, cz: number, seed: number) => {
      const k = 0.9 + hash(seed) * 0.2
      const hgt = Math.min(bankTop + 7.0, 14.5) * k
      const t = new THREE.Group()
      const trunkH = hgt * 0.46
      const trunk = new THREE.Mesh(
        new THREE.CylinderGeometry(hgt * 0.035, hgt * 0.06, trunkH, 10), bark)
      trunk.position.y = trunkH / 2
      t.add(trunk)
      const CL: [number, number, number, number][] = [
        [0, 0.02, 0, 0.17], [-0.14, -0.01, 0.03, 0.13], [0.15, -0.01, -0.03, 0.14],
        [0.05, 0.06, 0.07, 0.12], [-0.07, 0.05, -0.08, 0.11],
      ]
      for (const [dx, dy, dz, r] of CL) {
        const sph = new THREE.Mesh(new THREE.SphereGeometry(hgt * r, 12, 9),
          Math.abs(dx) > 0.1 ? leafB : leafA)
        sph.position.set(dx * hgt, trunkH + hgt * (0.22 + dy), dz * hgt)
        t.add(sph)
      }
      t.position.set(cx, 0, cz)
      g.add(t)
    }
    // The far line, kept HARD against the bank — every unit further back costs ceiling.
    const stepX = Math.max(9, W / 5)
    for (let x = -stepX * 0.4; x < W + stepX * 0.4; x += stepX) {
      tree(x + (hash(x) - 0.5) * 3, -(farDepth + 1.2 + hash(x + 7) * 1.4), x)
    }
    // ⚠️ THE SIDES CARRY THE WOOD, AND THEY ARE PLANTED TWO DEEP. This is where the
    // headroom is (12–22 units against a 5–7 unit bank on every board measured), so it
    // is where a line thick enough to read as woodland can actually be seen. One rank at
    // H/3 was four trees a side and read as four trees; two ranks at H/4, the back one
    // offset and further out, read as a wood.
    const stepZ = Math.max(7.5, H / 4)
    for (let z = -stepZ * 0.3; z < H + stepZ * 0.3; z += stepZ) {
      // ⚠️ HARD AGAINST THE BACK OF THE END BANK, BECAUSE THE FRAME EDGE IS RIGHT THERE.
      // Projected, the old `endDepth + 1.6` rank lands at ndc.x −1.13 to −1.19 on twelve
      // of the fourteen boards: off the side of the picture by 13–19%, and vertically
      // fine at ndc.y 0.5–0.7. It was never a height problem on the sides at all.
      for (const [rank, off] of [[0, 0.4], [1, 4.6]] as const) {
        const jz = z + (rank ? stepZ * 0.5 : 0)
        tree(-(endDepth + off + hash(jz + 3 + rank) * 2.2), jz + (hash(jz) - 0.5) * 3, jz + 100 + rank * 50)
        tree(W + endDepth + off + hash(jz + 11 + rank) * 2.2, jz + (hash(jz + 5) - 0.5) * 3, jz + 200 + rank * 50)
      }
    }
  }

  // ── planters on the trackway ─────────────────────────────────────────────
  // ⚠️ THE ONE ORNAMENT THAT FITS RINGSIDE. `GAP` is 1.6 units, so a tub about a unit
  // across is the largest thing that can stand between the floor and the barrier — which
  // is exactly why the treeline goes outside and this does not.
  //
  // ⚠️ SO THEY GREW UPWARD, BECAUSE THE FIRST VERSION WAS INVISIBLE. Rendered at tier 6 for
  // the first time, a 0.5-radius tub with a 0.46 bush on it topped out at ONE unit on a
  // 68-unit board — present in the frame, and nobody would ever notice it. Width is capped
  // by the trackway and cannot be spent; height is free, and the brief this rung came from
  // asked for "flowers and SMALL TREES just inside the fence". So each planter is now a
  // standard: a tub, a clear trunk, and a clipped crown at about 2.7 units — two thirds of
  // a monster, standing against the barrier where there is nothing else that height.
  // ⚠️ AND FEWER OF THEM. Eleven one-unit dots read as litter; the same budget spent on
  // seven proper standards reads as planting. `venue.planters` is a budget, not a count.
  if (v.planters > 0) {
    const tubMat = new THREE.MeshStandardMaterial({ color: v.masonry, roughness: 0.9 })
    const trimTub = new THREE.MeshStandardMaterial({ color: v.masonryTrim, roughness: 0.85 })
    const bark = new THREE.MeshStandardMaterial({ color: 0x4a3a28, roughness: 0.95 })
    const shrub = new THREE.MeshStandardMaterial({ color: 0x3d5626, roughness: 0.94 })
    const shrubB = new THREE.MeshStandardMaterial({ color: 0x476038, roughness: 0.94 })
    const bloom = new THREE.MeshStandardMaterial({
      color: 0xc9718a, roughness: 0.8, emissive: 0x2a0d14, emissiveIntensity: 0.45 })
    const ring: [number, number][] = []
    // ⚠️ NOT ON THE NEAR SIDE. Anything 2.7 units tall standing on the near trackway is
    // between the camera and the front rank — the same rule that keeps arches and the
    // canopy off the near side, and the reason the first version could afford to ring the
    // whole bowl: at one unit tall it occluded nothing.
    const per = Math.max(2, Math.round(v.planters / 3))
    for (let i = 0; i < per; i++) {
      const t = (i + 0.5) / per
      ring.push([W * t, -GAP * 0.5], [-GAP * 0.5, H * t], [W + GAP * 0.5, H * t])
    }
    for (const [px, pz] of ring) {
      const tub = new THREE.Mesh(new THREE.CylinderGeometry(0.52, 0.4, 0.62, 12), tubMat)
      tub.position.set(px, 0.31, pz)
      tub.castShadow = true; tub.receiveShadow = true
      g.add(tub)
      const rim = new THREE.Mesh(new THREE.CylinderGeometry(0.58, 0.58, 0.12, 12), trimTub)
      rim.position.set(px, 0.62, pz)
      g.add(rim)
      const trunk = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.12, 1.0, 8), bark)
      trunk.position.set(px, 1.15, pz)
      trunk.castShadow = true
      g.add(trunk)
      // A clipped crown, built from three overlapping spheres so it is not a lollipop.
      for (const [dx, dy, dz, r, alt] of [
        [0, 0, 0, 0.62, false], [-0.26, -0.16, 0.1, 0.44, true], [0.27, -0.13, -0.09, 0.46, true],
      ] as const) {
        const ball = new THREE.Mesh(new THREE.SphereGeometry(r, 12, 9), alt ? shrubB : shrub)
        ball.position.set(px + dx, 2.16 + dy, pz + dz)
        ball.castShadow = true
        g.add(ball)
      }
      for (let k = 0; k < 4; k++) {
        const f = new THREE.Mesh(new THREE.SphereGeometry(0.11, 6, 5), bloom)
        f.position.set(px + Math.cos(k * 1.6) * 0.44, 2.3 + Math.sin(k * 2.2) * 0.28,
          pz + Math.sin(k * 1.6) * 0.44)
        g.add(f)
      }
    }
  }

  return g
}
