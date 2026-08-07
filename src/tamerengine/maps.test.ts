import { describe, it, expect } from 'vitest'
import { ARENAS_WANTED, MAPS, arenaFor, arenasForLeague, mapById, mapProblems } from './maps'
import { groundFor, themeById } from './themes'

describe('arenas', () => {
  it('every map is geometrically sound and 180°-symmetric', () => {
    for (const m of MAPS) expect(mapProblems(m), m.id).toEqual([])
  })

  it('the three arenas genuinely differ — size AND cover density', () => {
    // A test bed of three near-identical maps tests nothing. Pin that they
    // actually span a range, so a later edit cannot quietly collapse them.
    const sizes = MAPS.map((m) => m.w * m.h)
    expect(new Set(sizes).size).toBe(MAPS.length)
    const cover = MAPS.map((m) => m.obstacles.reduce((s, o) => s + o.w * o.h, 0) / (m.w * m.h))
    expect(Math.max(...cover) / Math.min(...cover)).toBeGreaterThan(2)
  })

  it('a hand-edited asymmetric map is caught', () => {
    // The guard on the guard: mirror() cannot be bypassed silently.
    const m = { ...MAPS[0], obstacles: [...MAPS[0].obstacles, { x: 2, y: 2, w: 1, h: 1 }] }
    expect(mapProblems(m).some((p) => p.includes('no 180° partner'))).toBe(true)
  })

  it('mapById resolves every published id', () => {
    for (const m of MAPS) expect(mapById(m.id)?.name).toBe(m.name)
    expect(mapById('nope')).toBeUndefined()
  })
})

describe('league arena pools', () => {
  // ⚠️ THE FAILURE THIS GUARDS IS "AUTHORED BUT UNREACHABLE" — the pattern that has
  // now bitten this project with control moves, team buffs, four whole tactics and
  // the arenas themselves, which sat in MAPS for a year while every actual fight
  // used a hardcoded obstacle list. A map that no league draws is a test fixture,
  // and it has to SAY so rather than merely happen to be unused.
  it('every league arena names a league, and every fixture names none', () => {
    // ⚠️ DERIVED FROM `ARENAS_WANTED`, not a hardcoded list of prefixes. The first
    // version tested `id.startsWith('wood-')` and broke the moment Copper landed —
    // a test that has to be edited for every new league is a tax on the rollout and
    // will eventually be "fixed" by loosening it.
    const slugs = Object.keys(ARENAS_WANTED).map((l) => [l, l.toLowerCase().replace(/ /g, '-')])
    // ⚠️ `grand-` IS A THIRD CASE AND IT IS NOT A FIXTURE. Until the top of the ladder every
    // board belonged to exactly one league and its id said which. The 5v5 pool belongs to
    // FOUR — Platinum, Masters, Tamer Elite and Tamers Apex all field five and fight on the
    // same twenty grounds — so it cannot carry a league slug without lying about the other
    // three. It must still name every league it serves, or the "authored but unreachable"
    // failure this test exists for comes back through the side door.
    const GRAND = ['Platinum', 'Masters', 'Tamer Elite', 'Tamers Apex']
    for (const m of MAPS) {
      if (m.id.startsWith('grand-')) {
        expect([...m.leagues].sort(), `${m.id} must serve all four 5v5 leagues`)
          .toEqual([...GRAND].sort())
        continue
      }
      const owner = slugs.find(([, slug]) => m.id.startsWith(slug + '-'))
      if (owner) expect(m.leagues).toContain(owner[0])
      else expect(m.leagues, `${m.id} is a fixture and must name no league`).toEqual([])
    }
  })

  it('Wood is fully authored, and no two of its arenas are the same shape', () => {
    const wood = arenasForLeague('Wood')
    expect(wood.length).toBe(ARENAS_WANTED.Wood)

    // ⚠️ SHAPE, NOT JUST AREA. Two arenas at the same ASPECT are one arena scaled:
    // width sets how long the approach is and height sets how much room there is to
    // go around cover, and those are the two things that decide how a fight opens.
    // Measured, the two now span contact-to-first-blow 5.1s (the Timberyard) to 6.5s
    // (the Long Yard). ⚠️ THAT SPREAD USED TO BE 2.5x AND IS NOW 1.3x, because the shape
    // that made the range was the near-square Sawpit and Wood no longer has one. Cutting
    // to two boards cost the league its shape variety, and this note is here so the next
    // person reads that as a decision rather than as a set nobody finished.
    const aspects = wood.map((m) => +(m.w / m.h).toFixed(2))
    expect(new Set(aspects).size).toBe(wood.length)

    // ⚠️ THE FLOOR, NOT THE THEME — AND THIS IS A CHANGE, SO HERE IS WHY. Two distinct
    // THEMES was the right test while Wood had four boards and two of them were plankyard.
    // At two boards, both drawing timber props, Wood IS one material — that is what the
    // league is — and demanding two themes would force a plankyard board that cannot hold
    // a log stack, which `mapProblems` rejects outright. What has to differ is the thing a
    // player looks at: the GROUND. `surface` exists precisely so two boards on one theme
    // can be two places, and asserting the resolved floor is strictly stronger than
    // asserting the theme for any board that declares one.
    const floors = wood.map((m) => groundFor(themeById(m.theme), m.surface).ground)
    expect(new Set(floors).size, `Wood's floors: ${floors.join(', ')}`).toBe(wood.length)

    const kits = wood.map((m) => [...new Set(m.obstacles.map((o) => o.kind))].sort().join('+'))
    expect(new Set(kits).size).toBe(wood.length)
  })

  // ⚠️ AND THE SAME RULE FOR EVERY LEAGUE THAT HAS BOARDS, not just Wood. The floor test
  // was written while Wood was the only authored league and stayed Wood-only afterwards —
  // so Tin quietly shipped two boards on `streamworks` and nothing said a word. A rule
  // worth asserting for one league is worth asserting for all of them, and the cost of
  // not generalising it is exactly one silent duplicate per league added later.
  it('no league shows the same floor twice', () => {
    for (const lg of Object.keys(ARENAS_WANTED)) {
      const pool = arenasForLeague(lg)
      if (!pool.length) continue
      const floors = pool.map((m) => groundFor(themeById(m.theme), m.surface).ground)
      expect(new Set(floors).size, `${lg}: ${floors.join(', ')}`).toBe(pool.length)
    }
  })

  /**
   * No two boards in the game may have the same LAYOUT SIGNATURE.
   *
   * ⚠️ THE POOL WAS FIFTEEN PAINT JOBS ON ONE LAYOUT AND EVERY EXISTING GUARD PASSED. Areas
   * were distinct, floors were distinct, every piece was individually legal, the density law
   * was satisfied — and eleven of the fifteen 5v5 boards carried exactly six long bars, no
   * chunky piece at all, and 65-100%% of their cover in the middle third of X. Nothing asked
   * whether two boards were the same SHAPE, because nothing had ever needed to: below
   * Platinum a league has three to six grounds and an author holds them all in their head.
   * At twenty, nobody does.
   *
   * The signature is five coarse numbers, chosen because they are what an eye sorts on
   * before it reads any detail:
   *    how MANY pieces          — 8 reads as sparse, 22 as a thicket
   *    how many are long BARS   — the horizontal-band look that swallowed the pool
   *    how many are CHUNKY      — square blocks: gateways, arbours, snapped piers
   *    how far the mass sits from the centre in X, in tenths
   *    ...and the same in Y
   *
   * ⚠️ DELIBERATELY COARSE, AND DELIBERATELY GLOBAL. Comparing exact coordinates would pass
   * two boards that differ by a unit and are visibly identical, which is the failure this
   * exists to catch. And it compares across LEAGUES, not just within a pool: Copper's Smelt
   * and Tin's Blowing House had matching signatures, which nobody would ever have noticed
   * because the two circuits are never seen side by side — a board repeated a league later
   * is still a board that did not need authoring.
   *
   * ⚠️ IF THIS FAILS, DO NOT LOOSEN THE BUCKETS. The fix is to make one of the two boards a
   * different SHAPE — move its mass outward, change how many pieces it has, swap a run for a
   * pair of blocks. That is the whole point.
   */
  it('no two arenas share a layout signature', () => {
    const sigOf = (m: (typeof MAPS)[number]) => {
      const bars = m.obstacles.filter((o) => o.w / o.h >= 3.5).length
      const chunky = m.obstacles.filter((o) => o.w / o.h < 2 && o.w >= 3).length
      const tot = m.obstacles.reduce((t, o) => t + o.w * o.h, 0) || 1
      const off = (pick: (o: (typeof m.obstacles)[number]) => number) =>
        Math.round(10 * m.obstacles.reduce((t, o) => t + o.w * o.h * pick(o), 0) / tot)
      return [
        m.obstacles.length, bars, chunky,
        off((o) => Math.abs((o.x + o.w / 2) / m.w - 0.5)),
        off((o) => Math.abs((o.y + o.h / 2) / m.h - 0.5)),
      ].join('/')
    }
    const seen = new Map<string, string>()
    for (const m of MAPS.filter((x) => x.leagues.length)) {
      const sig = sigOf(m)
      const twin = seen.get(sig)
      expect(twin, `${m.id} has the same layout signature as ${twin} (${sig}) — `
        + 'count / bars / chunky / x-spread / y-spread. Change its SHAPE, not the test.')
        .toBeUndefined()
      seen.set(sig, m.id)
    }
  })

  /**
   * Exactly one ground in the game is bare.
   *
   * ⚠️ ONE IS A STATEMENT AND TWO IS A GAP. An empty arena asks what a fight looks like with
   * no shelter, no flanking route safer than any other and nothing to hold — the purest test
   * of a roster the game can set, and worth having once. A SECOND one is indistinguishable
   * from a board somebody forgot to finish, which is exactly how it would arrive.
   */
  it('exactly one arena is bare', () => {
    const bare = MAPS.filter((m) => m.leagues.length && m.obstacles.length === 0)
    expect(bare.map((m) => m.id)).toEqual(['grand-thelevel'])
  })

  it('picks an arena deterministically from the fight seed', () => {
    // ⚠️ The engine is deterministic end to end; an arena chosen with Math.random()
    // would break seed-reproducibility at the first thing that matters, and a
    // scouted cup would show ground the fight is not held on.
    for (const seed of ['a', 'cup-7', 'x'.repeat(40)]) {
      expect(arenaFor('Wood', seed)!.id).toBe(arenaFor('Wood', seed)!.id)
    }
    // ...and actually uses the whole pool rather than always landing on one.
    const picked = new Set(Array.from({ length: 40 }, (_, i) => arenaFor('Wood', 's' + i)!.id))
    expect(picked.size).toBe(arenasForLeague('Wood').length)
  })

  /**
   * A league may not build every board out of the same object.
   *
   * ⚠️ GOLD SHIPPED SIX GROUNDS FROM TWO KINDS AT TWO SIZES — 57 pieces, all of them a
   * 12 x 2.6 green bar or a 2 x 2 urn — and they read as one ground repeated. The
   * arrangements were genuinely different (a parterre, a bower, three terraces, a knot, an
   * axis, four corners) and NONE of it was visible, because layout variety cannot be seen
   * when the vocabulary is one word. Nothing caught it: every existing guard asks whether a
   * single piece is legal, and each of those 57 was.
   *
   * ⚠️ THE THRESHOLDS ARE THE LEAGUES THAT WORK, not round numbers. Bronze draws 4 kinds at
   * 5 distinct footprints across 4 boards; Iron 3 at 4. This asks for kinds >= 3 and
   * footprints >= boards + 1 from any league with three or more grounds — deliberately
   * BELOW Bronze, so it catches the catastrophe rather than legislating taste.
   */
  it('no league builds every board from the same one or two objects', () => {
    const leagues = new Set(MAPS.flatMap((m) => m.leagues))
    for (const lg of leagues) {
      const boards = MAPS.filter((m) => m.leagues.includes(lg))
      if (boards.length < 3) continue
      const kinds = new Set<string>()
      const sizes = new Set<string>()
      for (const m of boards) {
        for (const o of m.obstacles) {
          kinds.add(o.kind ?? '?')
          sizes.add(`${o.w}x${o.h}`)
        }
      }
      expect(kinds.size, `${lg}: ${boards.length} boards built from only ${kinds.size} kind(s)`)
        .toBeGreaterThanOrEqual(3)
      expect(sizes.size, `${lg}: ${boards.length} boards using only ${sizes.size} footprint(s)`)
        .toBeGreaterThanOrEqual(boards.length + 1)
    }
  })

  it('returns null for a league with no arenas yet, rather than another league\'s', () => {
    // Silently substituting is how content stays missing without anyone noticing.
    //
    // ⚠️ AND THE ROLLOUT IS NOW FINISHED, SO THIS ASSERTS ON A LEAGUE THAT DOES NOT EXIST.
    // It chased the ladder up — `'Gold'` until Gold was built, then `'Platinum'` — and each
    // time it failed the moment the boards landed, which is the guard working rather than
    // breaking. Every league in the game now has arenas, so the only honest subject left is
    // an unknown name: the behaviour under test is "an unrecognised league gets NULL, not
    // somebody else's ground", and that never stops mattering.
    expect(arenaFor('Wood', 'seed')).not.toBeNull()
    expect(arenaFor('Journeyman', 'seed')).toBeNull()
  })

  it('flags a theme that cannot draw the cover an arena asks for', () => {
    const m = { ...MAPS[0], obstacles: [{ x: 1, y: 1, w: 1, h: 1, kind: 'boulder' as const }] }
    expect(mapProblems({ ...m, theme: 'plankyard' }).some((p) => p.includes('no sprite for'))).toBe(true)
    expect(mapProblems({ ...m, theme: 'not-a-theme' }).some((p) => p.includes('unknown theme'))).toBe(true)
  })
})

describe('mirror() carries the whole obstacle, not just its rectangle', () => {
  // ⚠️ REGRESSION. The twin was built as a fresh `{x,y,w,h}` literal, which dropped
  // `kind` — so exactly half of every themed arena's cover rendered as the fallback
  // boulder. Geometry stayed perfect, so symmetry, bounds and overlap checks all
  // passed; it was visible only on screen. Assert the property, not the pixels.
  it('every mirrored pair shares its kind', () => {
    for (const m of MAPS) {
      for (const o of m.obstacles) {
        if (!o.kind) continue
        const twin = m.obstacles.find((p) => p !== o
          && Math.abs(p.x - (m.w - o.x - o.w)) < 1e-6 && Math.abs(p.y - (m.h - o.y - o.h)) < 1e-6)
        if (twin) expect(twin.kind).toBe(o.kind)
      }
    }
  })

  it('no league arena falls back to the boulder', () => {
    // The fallback exists so missing art is visible, never so it is acceptable.
    for (const m of MAPS.filter((x) => x.leagues.length)) {
      for (const o of m.obstacles) expect(o.kind).toBeDefined()
    }
  })
})
