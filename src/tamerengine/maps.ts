// ARENAS — three authored battlegrounds, differing in size, cover density and
// cover SHAPE.
//
// ⚠️ FAIRNESS IS STRUCTURAL, NOT CHECKED. Every map is built from `mirror()`,
// which authors one obstacle and derives its 180°-rotated partner about the
// field centre. You cannot write an asymmetric map with this helper by accident.
// That matters more than it looks: an arena that favours one side biases EVERY
// measurement taken on it, silently and in one direction, and a sweep would
// report it as a balance finding about the monsters. The engine's own
// DEFAULT_OBSTACLES carry the same note ("a symmetric pair of blocks so neither
// side is advantaged") — this makes the property impossible to lose rather than
// a thing to remember.
//
// Rotational, not mirror, symmetry: the sides face each other along x, so a
// left-right flip alone would put a wall on one side's left and the other's
// right. 180° is the transform that actually maps the fight onto itself.
//
// Cover SIZE never scales with the field. The premise these were built to test
// is that the things standing on the ground keep their size while the ground
// grows — so a big arena is genuinely sparser, not a photocopy.
import type { Obstacle } from './types'
import { HEX_ROW, HEX_W, hexArenaSize } from './hex'
import { THEMES, type SurfaceId } from './themes'

export interface ArenaMap {
  id: string
  name: string
  /** One line on what this arena is FOR — what it should stress in the sim. */
  brief: string
  w: number
  h: number
  obstacles: Obstacle[]
  /** Theme id — the material this arena is made of. See `themes.ts`. */
  theme: string
  /**
   * What this cup's floor is laid with. Omitted = the league's own ground.
   *
   * ⚠️ THIS IS HOW SIX CUPS ON ONE LEAGUE STOP LOOKING LIKE ONE ARENA SIX TIMES. Layout
   * variety is the one that matters in play, but it is invisible in a still frame — two
   * boards with the same floor, the same props and the same stands read as the same
   * place. A sand pit beside a flagged court is one line of authoring and reads as two
   * venues. See `themes.ts:SURFACES`.
   */
  surface?: SurfaceId
  /**
   * Leagues that draw this arena. Empty = not league content (a test fixture).
   *
   * ⚠️ THE THREE ORIGINAL ARENAS HAVE NONE, AND THAT IS THE POINT. They existed for
   * a year as content nothing could reach: `MAPS` was imported only by tools and
   * tests, while the game and the demo both fought on a hardcoded obstacle list at
   * the default size. Saying "no league" out loud is what stops a fixture being
   * mistaken for shipped content — and what makes `arenasForLeague` able to prove
   * every league actually has arenas.
   */
  leagues: string[]
  /**
   * Dressing that stands OUTSIDE the field. Drawn, never collided with.
   *
   * ⚠️ A SEPARATE LIST FROM `obstacles` BECAUSE IT MUST NOT BE ONE. Everything in
   * `obstacles` is cover: the engine paths around it, `reachOf` measures against it, the
   * sweep counts it. Scenery is set dressing in the trackway ring — trees behind the rail,
   * bushes at the corners — and putting it in the same array would silently add cover to
   * every board that got prettier, which is a balance change disguised as an art change.
   *
   * ⚠️ AND ITS COORDINATES ARE DELIBERATELY OUTSIDE 0..w / 0..h. `mapProblems` asserts it,
   * because the ONE way this feature goes wrong is a decorative tree drawn on the pitch
   * that monsters walk through — cover the player can see and the engine cannot.
   */
  scenery?: Obstacle[]
}

/**
 * One authored block plus its 180° partner. A block already centred on the field
 * is its own partner and is emitted once, so a centrepiece does not get drawn
 * (and collided with) twice.
 */
function mirror(w: number, h: number, o: Obstacle): Obstacle[] {
  // ⚠️ `...o` FIRST — the twin must inherit every field, not just the rectangle.
  // Spelling out `{ x, y, w, h }` silently dropped `kind`, so one of each mirrored
  // pair drew as the fallback boulder: a timber yard with a rock in it, and a
  // paddock whose two troughs were a trough and a boulder. The geometry was
  // perfect, which is what made it invisible to every existing check — only the
  // renderer's deliberate never-invisible fallback made it show up on screen.
  const twin: Obstacle = { ...o, x: w - o.x - o.w, y: h - o.y - o.h }
  const same = Math.abs(twin.x - o.x) < 1e-6 && Math.abs(twin.y - o.y) < 1e-6
  return same ? [o] : [o, twin]
}

const build = (w: number, h: number, half: Obstacle[]): Obstacle[] =>
  half.flatMap((o) => mirror(w, h, o))

// ── 1. Dustbowl ─────────────────────────────────────────────────────────────
// Small and nearly bare. Nowhere to hide, so approach is trivial and the fight
// is decided on raw trade — the control against which the other two read.
const DUSTBOWL_W = 34
const DUSTBOWL_H = 20

// ── 2. The Ossuary ──────────────────────────────────────────────────────────
// Medium, and the only map with LONG cover. Two 12-unit transverse walls set
// diagonally opposite force the approach into lanes instead of a straight line,
// and the centre pillar splits the one gap that connects them.
const OSSUARY_W = 48
const OSSUARY_H = 26

// ── 3. Titan's Rest ─────────────────────────────────────────────────────────
// Large, with a single massive centre block — the only true hard-cover wall in
// the set — ringed by rubble. Long approach, and a caster that wants line of
// sight has to commit to a side and give up the middle.
const TITAN_W = 64
const TITAN_H = 34

// ══ WOOD — the village circuit ═════════════════════════════════════════════
// ⚠️ BOTH ARE SMALL, AND THAT IS A DESIGN DECISION ABOUT THE LEAGUE, NOT A
// SHORTCUT. Wood is fought 1v1 (`TEAM_SIZE_BY_LEAGUE`) and its fights run ~17.6s.
// On a big field two lone monsters spend most of that walking toward each other,
// and walking is the least interesting thing this engine does. Space is something
// later leagues earn as they get more bodies to put in it.
//
// ⚠️ FEW, LARGE PIECES — NEVER SCATTERED RUBBLE. That is the hard lesson written
// up on Titan's Rest below: small blocks are each a cheap way to break line of
// sight without leaving the fight, so a shooter steps, re-acquires, loses sight
// and the exchange never closes. Big blocks measured HARMLESS; small ones stalled
// every fight on the map. Wood is the first arena a player sees and it must read
// as a clean fight.
// ⚠️ EVERY BOARD GREW ~1.4x LINEAR (2026-08-02) AND THE PIECES DID NOT. The whole set
// read as cluttered and small; positions scaled with the board, footprints stayed put, so
// cover fell from 6–16% to 3–6% and the same furniture now sits on twice the floor. The
// measured cost is approach time — contact roughly doubled (the Boards 1.9s → 3.5s, the
// Long Cast 5.3s → 8.4s) and fights run 2–4s longer. All 18 still resolve 40/40. The next
// pass is per league: grow the PIECES back toward the board so cover is sparse-but-large
// rather than merely sparse.
//
// ⚠️ SHAPE IS A REAL VARIABLE, NOT JUST A SIZE. These four span aspect 1.24 to
// 2.77 — a nearly square pit and a long narrow run are different fights, not the
// same fight scaled. Width sets how long the approach is; HEIGHT sets how much room
// there is to go around anything, which is what decides whether cover creates a
// flank or just a wall. Two arenas at the same aspect are one arena wearing a hat.
const TIMBERYARD = hexArenaSize(21, 13)
const TIMBERYARD_W = TIMBERYARD.w
const TIMBERYARD_H = TIMBERYARD.h
const LONGYARD = hexArenaSize(24, 10)
const LONGYARD_W = LONGYARD.w
const LONGYARD_H = LONGYARD.h

// ══ COPPER — ore and smelting ══════════════════════════════════════════════
// ⚠️ ROOMIER THAN WOOD BECAUSE COPPER IS 2v2. Wood's four span 952–1389 square
// units for a single monster a side; these run 1304–1528 for two. Space is something
// a league earns as it gets bodies to put in it — scaling the ground without
// scaling the team just adds walking, which is the least interesting thing this
// engine does.
//
// ⚠️ AND THE THREE DIFFER IN SHAPE, NOT JUST FURNITURE — 1.15, 1.42 and 2.44. On
// Wood that spread moved contact-to-first-blow by 2.5x, so it is the lever that
// actually changes how a fight opens.
const WASHFLOOR = hexArenaSize(20, 15)
const WASHFLOOR_W = WASHFLOOR.w
const WASHFLOOR_H = WASHFLOOR.h
// ⚠️ STILL THE CRAMPED ONE OF THE THREE, AND IT HAS TO BE MEASURED THAT WAY. At its
// first size it was BILLED as cramped and played at 2.4s to contact against the Smelt's
// 3.0s, so the three barely differed. Contact tracks WIDTH almost directly (the original
// Wood ladder: 26→1.5s, 30→2.1s, 36→2.9s, 42→3.7s); depth makes it a room rather than a
// corridor. Now 38.8 wide against the Smelt's 60.6, and it measures 3.3s to the Smelt's
// 6.8 — the gap the three were supposed to have.
const INGOTYARD = hexArenaSize(16, 16)
const INGOTYARD_W = INGOTYARD.w
const INGOTYARD_H = INGOTYARD.h
const SMELT = hexArenaSize(25, 11)
const SMELT_W = SMELT.w
const SMELT_H = SMELT.h

// ══ THE ARENAS ARE BUILT, SO THEY ARE BUILT OF MASONRY ═════════════════════
// ⚠️ THE TRADE PROPS WERE THE PROBLEM, AND THE COMPLAINT WAS THAT THEY DID NOT MAKE
// SENSE. An ore bin, an anvil, a crucible and a sluice are things you find in a WORKING
// YARD; scattered across a fighting floor with a crowd watching, they read as objects
// someone left out rather than as a place built for a contest. A wall, a colonnade and a
// ruin are what an arena is MADE of, so they need no excuse for standing there.
//
// ⚠️ SO ARCHITECTURE IS THE DEFAULT AND TRADE IS THE ACCENT — at most one or two pieces
// of a league's own kit per board, placed where a working yard would actually keep them.
// The league still reads: the STONE is tinted by `venue.masonry`, the floor is the
// league's, and the lamp is the league's.

// ══ TIN — stream works and blowing houses ══════════════════════════════════
// ⚠️ SHAPES TIN DOES NOT SHARE WITH COPPER. Copper runs 1.15 / 1.54 / 2.62; these
// are 0.98 / 1.98 / 2.23 — and ⚠️ the Wash Pool at 0.98 is the one board in the game
// DEEPER than it is wide, which `ART_DIRECTION.md` otherwise forbids for the camera. It
// predates the rule and is kept on purpose as the extreme of the depth axis; do not copy
// it, and do not "fix" it without deciding that Tin loses its deep board. so the two leagues do not simply repeat each other's
// three boards in different colours. Tin is 2v2 like Copper, so the areas are
// comparable — what changes is the proportion, and with it how long the approach
// is against how much room there is to go round anything.
// ⚠️ SQUARE, AND NOTHING ELSE IN THE GAME IS. First drafted 39x30, which read as
// "deep" on paper but played at 2.6s to contact against the other two Tin boards'
// 3.0 and 3.5 — three wide arenas with a narrow spread between them. Narrowing it to
// 30 keeps the depth that makes a flank real while giving Tin the fast opening its
// set was missing. Contact tracks WIDTH; depth decides what you can do once there.
// ── Bronze (3v3) ────────────────────────────────────────────────────────────
// ⚠️ FOUR SHAPES, NOT FOUR LAYOUTS OF ONE SHAPE. Bronze runs four cups a year on these
// grounds, so the same team meets them repeatedly — and a deployment that is correct on
// every board is not a decision. The square, the deep, the long and the wide each break
// a different plan: the long one punishes a slow front line, the deep one gives a caster
// somewhere to run, the wide one lets both sides flank at once.
// All four sit inside `arenaGridFor(3)`'s band (16x12 = 192 cells, 150-298).
const ALLOYFLOOR = hexArenaSize(22, 17)     // 192 — the reference square
const BELLPIT = hexArenaSize(18, 21)        // 195 — deep, a well
const LONGCAST = hexArenaSize(29, 13)        // 189 — long and shallow
const SLAGYARD = hexArenaSize(25, 15)       // 198 — wide, open flanks

// ══ THE GRAND CIRCUIT — twenty 5v5 grounds, shared Platinum to Apex ════════
// ⚠️ ONE POOL, FOUR LEAGUES, AND THE STADIUM CARRIES THE LADDER. Every circuit below builds
// its own boards because its MATERIAL is its name. From Platinum up the team size stops
// growing — five, all the way to Apex — so the boards stop belonging to a league: each lists
// all four, `arenasForLeague` filters on `leagues.includes`, and the same twenty grounds
// serve every rung. What changes between them is the VENUE: arches and a canopy at Platinum,
// an entablature and statues at Masters, turrets and a mosaic at Tamer Elite, the victory
// arch at Apex. That is the whole reason the venue was built as a layer of its own.
//
// ⚠️ SO THE POOL IS DIFFERENTIATED BY COLOUR, because it is the only axis left. Twenty
// boards at one team size cannot be told apart by scale and must not be told apart by
// league. What separates them is the STONE — porphyry, serpentine, basalt, alabaster,
// slate — one theme per ground, each with its own lamp.
//
// ⚠️ AND EVERY BOARD DRAWS ON THE WHOLE LIBRARY, which no league below does. A circuit's
// boards share a silhouette family precisely so the circuit reads as one place; the grand
// pool has no single material to be faithful to, so a colonnade court, a walled ring and an
// overgrown ruin can sit in the same twenty. That is what stops the biggest pool in the game
// from being the most repetitive one — the failure Gold shipped at six.
//
// Areas 4767 / 4685 / 4889 / 4705 / 4848, aspects 1.60 / 2.01 / 1.23 / 2.42 / 1.40.
const PORPHYRY = hexArenaSize(36, 26)      // 936 cells — 1.60, the reference court
const SERPENTINE = hexArenaSize(40, 23)    // 920 — 2.01, long and green
const BASALTRING = hexArenaSize(32, 30)    // 960 — 1.23, deep and dark
const ALABASTER = hexArenaSize(44, 21)     // 924 — 2.42, the longest ground in the game
const SLATEYARD = hexArenaSize(34, 28)     // 952 — 1.40, the grid's own target


// ── block 2 ────────────────────────────────────────────────────────────────
// ⚠️ AREA IS PROPORTIONAL TO CELL COUNT, so two grids with the same cells are the same
// board however differently they are shaped: `hexArenaSize` is cols x 2.4249 by rows x 2.1,
// and the product is cols x rows x 5.09. The size tripwire compares AREAS, so avoiding a
// clash means choosing distinct CELL COUNTS — 30x32 and 32x30 are both 960 and would trip
// it. Block 1 spent 936 / 920 / 960 / 924 / 952; block 2 takes 945 / 912 / 966 / 900 / 988.
const LISTS = hexArenaSize(35, 27)         // 945 cells — 1.50, the tilting lane
const ISLANDS = hexArenaSize(38, 24)       // 912 — 1.83, four clusters and open ground
const CAUSEWAY = hexArenaSize(42, 23)      // 966 — 2.11, a raised spine
const GROVE = hexArenaSize(30, 30)         // 900 — 1.15, the square, planted
const BREAKWATER = hexArenaSize(38, 26)    // 988 — 1.69, a staggered diagonal


// ── block 3 ────────────────────────────────────────────────────────────────
// ⚠️ AND ONE OF THEM IS TALLER THAN IT IS WIDE, WHICH NOTHING IN THIS GAME HAS EVER BEEN.
// Every board from Wood up is landscape, so every fight has a long approach and shallow
// flanks. `THE PIT` inverts that: 68 wide by 76 deep, so the two sides start barely thirty
// units apart with an enormous amount of room to either side of the crossing.
// ⚠️ IT COSTS VENUE, AND THAT IS A KNOWN TRADE. `docs/ARENA_DESIGN.md` measures how much
// stadium is visible against board aspect — the camera fits the BOARD, so a portrait ground
// is bound by its HEIGHT and the far stand is cropped hard. What it buys back is the sides:
// bound vertically, the frame runs wider, so the flanking banks and their treeline show more
// than on any other ground in the pool. It is the one board that trades one for the other.
const CHEQUERYARD = hexArenaSize(34, 27)   // 918 cells — 1.45, the four-square
const MOSAICCOURT = hexArenaSize(36, 27)   // 972 — 1.54, spokes from a centre
const ROSEWALK = hexArenaSize(49, 19)      // 931 — 2.98, the longest board in the game
const ONYXHALL = hexArenaSize(41, 23)      // 943 — 2.06, a nave and two aisles
const THEPIT = hexArenaSize(28, 36)        // 1008 — 0.90, the only PORTRAIT ground
const THELEVEL = hexArenaSize(35, 28)      // 980 — 1.44, and NOTHING stands on it

// ══ GOLD — the pleasance circuit (4v4) ═════════════════════════════════════
// ⚠️ THE THIRD REPEAT OF A SCALE ON THE LADDER, and by now the drill is known. Silver and
// Gold both field four, so `arenaGridFor` hands both the same 28x22 target; the leagues are
// separated by SILHOUETTE FAMILY, as Bronze and Iron were:
//   Silver — colonnade runs: hard-edged, pale, PIERCED. You read the enemy through the bays.
//   Gold   — hedging and urns: soft-topped, dark, and completely OPAQUE.
// The contrast is optical rather than thematic on purpose. Two leagues told apart by a
// caption are not told apart.
//
// ⚠️ AND THE FAMILY IS THE RUNG, THE SAME TRICK AGAIN. Tier 5 turns on `venue.columns` and
// Silver's floor is colonnades; tier 6 turns on `venue.planters` and Gold's is planting.
//
// ⚠️ AND SIX DISTINCT PALETTES OF OBJECTS, WHICH THE FIRST PASS DID NOT HAVE. It built all
// six grounds from `hedge` and `urn` — measured, 57 pieces from 2 kinds at 2 sizes — and
// they read as one ground repeated. The arrangements really were different; nobody could
// see it, because a parterre of green bars and a knot of green bars are the same picture.
// ⚠️ SO EACH BOARD NOW DRAWS A SUBSET, NOT THE WHOLE SET. Six kinds exist; no board uses
// more than four, and no two boards use the same four:
//   Parterre     flowerbed + short hedge + urn        — the LOW board, seen clean over
//   Bower        arbour + hedge + topiary             — the board you walk THROUGH
//   Terraces     hedge at 16 / 10 / 14 + topiary      — the long board, three depths
//   Knot Garden  fountain + short hedge + topiary     — the ROUND landmark
//   Long Axis    vinewall + hedge + urn               — the old, overgrown board
//   Corner Walks flowerbed + topiary                  — the sparse, VERTICAL board
// ⚠️ AND THE SIZES VARY. Every hedge used to be 12 x 2.6 on every board; they now run 8 to
// 16, and the beds run 12 to 14. Repeating one footprint is most of what made six grounds
// look like one even before the kinds ran out.
//
// ⚠️ SIX DISTINCT AREAS, SIX DISTINCT ASPECTS, NONE SHARED WITH SILVER'S FIVE. Silver runs
// 3106 / 3222 / 3089 / 3185 / 3151 at aspects 1.25-2.38; Gold runs 3025 / 3162 / 3117 /
// 3157 / 3183 / 3208 at 1.15-2.45. Four of the six are 1.6 or wider, per the aspect law in
// `docs/ARENA_DESIGN.md` — a square board spends its venue.
const PARTERRE = hexArenaSize(33, 18)      // 594 cells — 2.12, the formal walk
const BOWER = hexArenaSize(27, 23)         // 621 — 1.36, deep and enclosed
const TERRACES = hexArenaSize(36, 17)      // 612 — 2.45, the longest ground in the game
const KNOTGARDEN = hexArenaSize(31, 20)    // 620 — 1.79, the reference wide
const LONGAXIS = hexArenaSize(25, 25)      // 625 — 1.15, the square, and it pays for it
const CORNERWALKS = hexArenaSize(30, 21)   // 630 — 1.65, open in the middle

// ══ SILVER — the assay circuit (4v4) ════════════════════════
// ⚠️ SILVER IS GOLD'S TWIN IN TEAM SIZE, which is the Bronze/Iron problem a second time
// and was seen coming rather than discovered in a render. Both field four, so
// `arenaGridFor` hands both the same 28x22 target. The fix that worked once is applied
// again — the leagues are split by SILHOUETTE FAMILY, the thing an eye actually sorts on:
//   Bronze — horizontal masonry: wall runs, collapsed runs, low and long.
//   Iron   — things you pass THROUGH and stand ON: gateways and stepped daises.
//   Silver — TALL SLENDER VERTICALS: columns, broken columns, obelisks. Cover you shoot
//            PAST rather than over, standing in files and rings.
//   Gold   — PLANTED (unauthored): hedges, vine walls, tubs.
//
// ⚠️ AND THE FAMILY IS THE RUNG, WHICH IS WHY IT IS THIS ONE AND NOT ANOTHER. Tier 5 is
// exactly where `venue.columns` turns on: Silver is the league whose STANDS gain a
// colonnade, so its FLOOR is built of columns too and the two read as one place. The same
// trick is waiting for Gold at tier 6, where the planters arrive.
//
// ⚠️ FIVE DISTINCT AREAS AND FIVE DISTINCT ASPECTS, and four of the five are wide. A
// board's aspect ratio decides how much of its stadium is ever in frame — see
// `docs/ARENA_DESIGN.md`, which has the projected numbers. The Cistern is the deliberate
// square: every circuit wants one deep board, and it pays for it in visible venue.
const COLONNADE = hexArenaSize(30, 20)     // 600 cells — 1.73, the reference wide
const CISTERN = hexArenaSize(26, 24)       // 624 — 1.25, deep, the well
const LONGWALK = hexArenaSize(35, 17)      // 595 — 2.38, the longest board in the game
const ASSAYYARD = hexArenaSize(28, 22)     // 616 — 1.47, the grid's own target
const BULLION = hexArenaSize(32, 19)       // 608 — 1.94, wide with open flanks

// ══ IRON — the forge circuit (3v3) ═════════════════════════════════════════
// ⚠️ IRON IS BRONZE'S TWIN IN TEAM SIZE, AND THAT IS THE WHOLE DESIGN PROBLEM. Both field
// three, so `arenaGridFor` hands both the same 22x17 target and the ladder repeats a scale
// for the first time. Everything that makes Iron a different circuit has to come from the
// other axes: its GROUND (two new, deliberately colder and blacker than Copper's smelt),
// its LAMP (the hardest key and the lowest ambient in the game), its RUNG (tier 4 — the
// balustrade and the brazier ring arrive here), and its ARRANGEMENTS.
//
// ⚠️ AND ITS BOARDS MUST NOT SHARE AN AREA WITH BRONZE'S, WHICH IS EXACTLY WHAT THE FIRST
// DRAFT DID. Reaching for the obvious grids gave the Anvil Yard 22x17 and the Furnace Row
// 25x15 — byte-identical to the Alloy Floor and the Slag Yard. Nothing about that is
// visible in a render; the size tripwire in `maps.test.ts` counted 18 distinct areas across
// 20 maps and said so. Two leagues at one team size have to be pulled apart deliberately.
//
// Areas 1833 / 1935 / 1854 / 1991 against Bronze's 1905 / 1925 / 1920 / 1910, and aspects
// 1.85 / 1.22 / 2.49 / 1.56 against Bronze's 1.49 / 0.99 / 2.58 / 1.92.
//
// ⚠️ AND A DIFFERENT VOCABULARY, BECAUSE DIFFERENT DIMENSIONS WERE NOT ENOUGH. The first
// Iron draft was built from wall runs, ruins and piers in the same quantities as Bronze,
// and it read as Bronze again at other sizes — the exact "four boards wearing a hat"
// failure the header above warns about, made anyway. Numbers separated the boards; nothing
// separated the LEAGUES.
//
// So the two circuits are split by SILHOUETTE FAMILY, which is the thing an eye actually
// sorts on:
//   Bronze — horizontal masonry. Wall runs, collapsed runs, ruined coursing, low and long.
//   Iron   — things you pass THROUGH and stand ON. Gateways and stepped daises, upright
//            and blocky, with piers between.
// Both are dressed stone off `venue.masonry`, so the ladder still climbs; what changes is
// the shape the league is built out of. It also puts `gate` and `dais` to work — two kinds
// that had art and no user since the day they were drawn.
const ANVILYARD = hexArenaSize(24, 15)     // 360 — wide, the walled square
const QUENCHPOOL = hexArenaSize(20, 19)    // 380 — near-square and deep
const DRAWFLOOR = hexArenaSize(28, 13)     // 364 — long and shallow
const FURNACEROW = hexArenaSize(23, 17)    // 391 — the roomiest on the circuit

// ⚠️ 29x21, NOT 28x22, BECAUSE THE FIXTURE MUST NOT OWN A REAL BOARD'S SIZE. It sat at
// exactly `arenaGridFor(4)` and Silver's reference ground wants that grid — the size
// tripwire counted 24 distinct areas across 25 maps and refused. A measurement rig is the
// thing that moves in that argument; it only has to be AT 4v4 scale, not at the exact
// target a shipping arena is entitled to.
const FURNITURE = hexArenaSize(29, 21)   // 4v4 scale, for judging arena furniture
const WASHPOOL = hexArenaSize(17, 20)
const WASHPOOL_W = WASHPOOL.w
const WASHPOOL_H = WASHPOOL.h
const LEATS = hexArenaSize(24, 14)
const LEATS_W = LEATS.w
const LEATS_H = LEATS.h
const BLOWING = hexArenaSize(27, 14)
const BLOWING_W = BLOWING.w
const BLOWING_H = BLOWING.h


// == HOW AN ARENA IS LAID OUT ===============================================
// WARNING: AN ARENA IS BUILT BY SOMEONE, SO ITS COVER IS PLACED, NOT SPILLED. The first
// pass read "cover density" as a number and scattered small props to hit it, which gives
// a board where nothing fully blocks a lane, every position is about as good as every
// other, and the deployment that is correct here is correct everywhere. Busy, with no
// decision in it. Every board below is now ONE named arrangement, stated in its brief and
// built from a few LARGE pieces.
//
// The six arrangements, and the question each asks:
//
//   SPINE    one long piece dead centre - two lanes, and you commit before contact
//   FLANKS   long pieces down both edges, middle bare - the fast route is the seen one
//   CHICANE  squat posts staggered through the middle - you may weave, not charge
//   ECHELON  two long pieces diagonally opposed - cover on your own side only, and
//            crossing to the other means being seen doing it
//   DOGLEG   two long pieces overlapping in depth with a step between - one short way
//            through, and it is watched
//   COURT    a landmark dead centre with cover framing it - four approaches, and the
//            middle is worth holding
//
// WARNING: THE ART DECIDES WHICH ARRANGEMENTS ARE EVEN POSSIBLE. Nearly every prop draws
// far WIDER than tall, so its footprint runs along X - the same axis as the approach.
// That makes long props lane DIVIDERS, never walls across the run; a barrier across the
// approach has to be built from the squat props (crates, crucible, furnace, stump, broken
// pillar) stood in a line. Author a chicane out of log stacks and you get a spine you did
// not intend.
//
// WARNING: EACH PROP HAS A FOOTPRINT ENVELOPE, ENFORCED FROM BOTH SIDES BY
// `arenas.test.ts`. Drawn height is `width / aspect`: it must REACH the footprint's depth
// (or you see walkable floor inside solid cover) and stay under 3.4 (a battle sprite's
// height, or the cover hides the fight). So a prop's aspect sets its MAXIMUM width too - a
// sluice may run 18 units, a crate stack may not exceed 3.6. Sizes below are width x
// aspect with a hair of margin, never a round number picked by eye.
//
// WARNING: PIECE COUNT RISES WITH THE TEAM, PIECE SIZE RISES WITH THE BOARD. Wood is a
// duel and two pieces are a whole layout there; Bronze is 3v3 on a board 1.8x the area and
// carries five. Both stay FEW - what grows is the size, because a 16-unit wall on a
// 51-unit board is a decision and five 2-unit heaps on the same board are texture.
//
// WARNING: AND `build` MIRRORS - a piece at x reappears at w-x-width, so nothing may cross
// the centre line, and an authored pair becomes FOUR. A centred piece is its own partner
// and is emitted once, which is the only way to get a true spine.

export const MAPS: ArenaMap[] = [
  {
    // ⚠️ A FIXTURE FOR LOOKING AT THE FURNITURE, NOT LEAGUE CONTENT — `leagues: []` keeps
    // it out of every cup and out of the size guard. Arena furniture only makes sense at
    // 4v4 scale and up, and there is no authored board that big yet, so this exists to
    // judge the objects before forty arenas are built out of them.
    id: 'furniture-proof',
    name: 'Furniture proof',
    brief: 'Not a league ground. Every piece of arena furniture at 4v4 scale.',
    theme: 'alloyfloor',
    surface: 'flagstone',   // the masonry has to be judged against a quiet floor
    leagues: [],
    w: FURNITURE.w,
    h: FURNITURE.h,
    obstacles: build(FURNITURE.w, FURNITURE.h, [
      // ⚠️ FEWER AND LARGER, WHICH IS WHAT COVERAGE ACTUALLY MEANS. Scattering five small
      // pieces gives a board where nothing fully blocks a lane and every position is
      // roughly as good as every other — busy, and no decision in it. One long wall a
      // third of the board wide is a real obstacle: you go round it, and which end you
      // pick matters.
      { x: 18.3, y: 6.9, w: 15, h: 1.8, kind: 'ruinedwall' },
      { x: 18.6, y: 24.8, w: 3.4, h: 3.2, kind: 'brokenpillar' },
      { x: 21.0, y: 34.4, w: 7.5, h: 2.4, kind: 'gate' },
      // ⚠️ EXACTLY CENTRED, SO `mirror` EMITS IT ONCE. A centrepiece is its own 180°
      // partner — see the helper. Off by a hair and the arena grows two obelisks.
      { x: (FURNITURE.w - 2.6) / 2, y: (FURNITURE.h - 2.6) / 2, w: 2.6, h: 2.6, kind: 'obelisk' },
    ]),
  },
  {
    id: 'grand-porphyry',
    name: 'The Porphyry Court',
    brief: 'COURT. Colonnades down both flanks, a low dais between them, obelisks at the mouths.',
    theme: 'porphyry',
    leagues: ['Platinum', 'Masters', 'Tamer Elite', 'Tamers Apex'],
    w: PORPHYRY.w,
    h: PORPHYRY.h,
    obstacles: build(PORPHYRY.w, PORPHYRY.h, [
      // ⚠️ THE POOL WAS MEASURED AND IT WAS FIFTEEN PAINT JOBS ON ONE LAYOUT. Eleven boards
      // carried exactly SIX long bars and no chunky piece at all; thirteen carried 12-14
      // pieces; thirteen put 65-100%% of their cover in the middle third of X. Colour and
      // arrangement NAMES were doing all the differentiating and the silhouettes were one
      // silhouette.
      // ⚠️ TWO CAUSES, ONE STRUCTURAL AND ONE NOT. The deploy band bans the outer 24%% of
      // each end and no piece may cross the centre line, so every authored piece lives in a
      // strip from `w * 0.24 + 1.5` to `w / 2` — about a quarter of the width. That is
      // forced. What was NOT forced was authoring in the middle of that strip every time
      // instead of using both its edges, and reaching for two long runs as the mass on
      // almost every board.
      // ⚠️ SO EVERY BOARD NOW DECLARES A SIGNATURE and no two share one: piece COUNT (8 to
      // 21), how much of the mass is long BARS versus CHUNKY blocks versus many small
      // pieces, and where the cover sits in X and Y.
      //
      // SIGNATURE: 12 pieces / 0 bars / 8 chunky. The only board in the pool with no long
      // run on it — a court of gateways, so its silhouette is eight tall blocks rather than
      // the horizontal bands every other ground opens with. Gates sit at both ends of the
      // legal strip (23 and 34 of a 22.45-43.65 window), which is what spreads the cover in
      // X instead of bunching it at the middle.
      { x: 23, y: 6, w: 6, h: 6.6, kind: 'gate' },
      { x: 23, y: 42, w: 6, h: 6.6, kind: 'gate' },
      { x: 34, y: 17, w: 6, h: 6.6, kind: 'gate' },
      { x: 34, y: 31, w: 6, h: 6.6, kind: 'gate' },
      { x: 28, y: 26, w: 1.4, h: 1.4, kind: 'obelisk' },
      { x: 23, y: 24, w: 2, h: 2, kind: 'urn' },
    ]),
  },
  {
    id: 'grand-serpentine',
    name: 'The Serpentine',
    brief: 'WATER GARDEN. A basin dead centre, hedging down the long sides, urns at the turns.',
    theme: 'serpentine',
    leagues: ['Platinum', 'Masters', 'Tamer Elite', 'Tamers Apex'],
    w: SERPENTINE.w,
    h: SERPENTINE.h,
    obstacles: build(SERPENTINE.w, SERPENTINE.h, [
      // ⚠️ THE POOL WAS MEASURED AND IT WAS FIFTEEN PAINT JOBS ON ONE LAYOUT. Eleven boards
      // carried exactly SIX long bars and no chunky piece at all; thirteen carried 12-14
      // pieces; thirteen put 65-100%% of their cover in the middle third of X. Colour and
      // arrangement NAMES were doing all the differentiating and the silhouettes were one
      // silhouette.
      // ⚠️ TWO CAUSES, ONE STRUCTURAL AND ONE NOT. The deploy band bans the outer 24%% of
      // each end and no piece may cross the centre line, so every authored piece lives in a
      // strip from `w * 0.24 + 1.5` to `w / 2` — about a quarter of the width. That is
      // forced. What was NOT forced was authoring in the middle of that strip every time
      // instead of using both its edges, and reaching for two long runs as the mass on
      // almost every board.
      // ⚠️ SO EVERY BOARD NOW DECLARES A SIGNATURE and no two share one: piece COUNT (8 to
      // 21), how much of the mass is long BARS versus CHUNKY blocks versus many small
      // pieces, and where the cover sits in X and Y.
      //
      // SIGNATURE: 19 pieces / 4 bars / 13 small. The most PIECES of any board in the game
      // and the smallest mean piece — a water garden reads as a scatter of ornament, not as
      // architecture, so the two hedges carry the mass and thirteen urns and standards do
      // the shaping. Nothing else in the pool is built this way round.
      { x: (SERPENTINE.w - 7) / 2, y: (SERPENTINE.h - 3) / 2, w: 7, h: 3, kind: 'fountain' },
      { x: 28, y: 4, w: 12, h: 2.6, kind: 'hedge' },
      { x: 28, y: 41.7, w: 12, h: 2.6, kind: 'hedge' },
      { x: 26, y: 11, w: 2, h: 2, kind: 'urn' },
      { x: 26, y: 35.3, w: 2, h: 2, kind: 'urn' },
      { x: 34, y: 17, w: 2, h: 2, kind: 'urn' },
      { x: 42, y: 12, w: 1.6, h: 1.6, kind: 'topiary' },
      { x: 42, y: 34.7, w: 1.6, h: 1.6, kind: 'topiary' },
      { x: 31, y: 24, w: 1.6, h: 1.6, kind: 'topiary' },
      { x: 38, y: 29, w: 1.4, h: 1.4, kind: 'obelisk' },
    ]),
  },
  {
    id: 'grand-basaltring',
    name: 'The Basalt Ring',
    brief: 'RING. A gateway at each corner and a wall across the middle — the heaviest ground on the circuit.',
    theme: 'basalt',
    leagues: ['Platinum', 'Masters', 'Tamer Elite', 'Tamers Apex'],
    w: BASALTRING.w,
    h: BASALTRING.h,
    obstacles: build(BASALTRING.w, BASALTRING.h, [
      // ⚠️ THE POOL WAS MEASURED AND IT WAS FIFTEEN PAINT JOBS ON ONE LAYOUT. Eleven boards
      // carried exactly SIX long bars and no chunky piece at all; thirteen carried 12-14
      // pieces; thirteen put 65-100%% of their cover in the middle third of X. Colour and
      // arrangement NAMES were doing all the differentiating and the silhouettes were one
      // silhouette.
      // ⚠️ TWO CAUSES, ONE STRUCTURAL AND ONE NOT. The deploy band bans the outer 24%% of
      // each end and no piece may cross the centre line, so every authored piece lives in a
      // strip from `w * 0.24 + 1.5` to `w / 2` — about a quarter of the width. That is
      // forced. What was NOT forced was authoring in the middle of that strip every time
      // instead of using both its edges, and reaching for two long runs as the mass on
      // almost every board.
      // ⚠️ SO EVERY BOARD NOW DECLARES A SIGNATURE and no two share one: piece COUNT (8 to
      // 21), how much of the mass is long BARS versus CHUNKY blocks versus many small
      // pieces, and where the cover sits in X and Y.
      //
      // SIGNATURE: 8 pieces / 2 bars / 4 chunky. The FEWEST pieces in the pool and the
      // largest mean piece — a board of four gateways and one long wall, where every single
      // object is something a monster has to commit to going round. Sparse and heavy is a
      // silhouette in its own right, and nothing else here is allowed to be this empty.
      { x: 21, y: 9, w: 6, h: 6.6, kind: 'gate' },
      { x: 21, y: 47.4, w: 6, h: 6.6, kind: 'gate' },
      { x: 24, y: 29, w: 14, h: 2.8, kind: 'wall' },
      { x: 33, y: 19, w: 2.6, h: 3.15, kind: 'brokenpillar' },
    ]),
  },
  {
    id: 'grand-alabaster',
    name: 'The Alabaster Mile',
    brief: 'MILE. The longest ground in the game — colonnades at the ends, a bed and standards through the middle.',
    theme: 'alabaster',
    leagues: ['Platinum', 'Masters', 'Tamer Elite', 'Tamers Apex'],
    w: ALABASTER.w,
    h: ALABASTER.h,
    obstacles: build(ALABASTER.w, ALABASTER.h, [
      // ⚠️ THE POOL WAS MEASURED AND IT WAS FIFTEEN PAINT JOBS ON ONE LAYOUT. Eleven boards
      // carried exactly SIX long bars and no chunky piece at all; thirteen carried 12-14
      // pieces; thirteen put 65-100%% of their cover in the middle third of X. Colour and
      // arrangement NAMES were doing all the differentiating and the silhouettes were one
      // silhouette.
      // ⚠️ TWO CAUSES, ONE STRUCTURAL AND ONE NOT. The deploy band bans the outer 24%% of
      // each end and no piece may cross the centre line, so every authored piece lives in a
      // strip from `w * 0.24 + 1.5` to `w / 2` — about a quarter of the width. That is
      // forced. What was NOT forced was authoring in the middle of that strip every time
      // instead of using both its edges, and reaching for two long runs as the mass on
      // almost every board.
      // ⚠️ SO EVERY BOARD NOW DECLARES A SIGNATURE and no two share one: piece COUNT (8 to
      // 21), how much of the mass is long BARS versus CHUNKY blocks versus many small
      // pieces, and where the cover sits in X and Y.
      //
      // SIGNATURE: 10 pieces / 6 bars / all at MID depth. Every other bar board in the pool
      // puts a run near the top edge and its mirror near the bottom; this one stacks three
      // runs into the middle third of the depth and leaves both edges completely bare. On
      // the second-longest ground in the game that makes the flanks a genuine open road and
      // the centre a wall of colonnade you have to pick a way through.
      { x: 29, y: 17, w: 16, h: 3.0, kind: 'colonnade' },
      { x: 29, y: 24.1, w: 16, h: 3.0, kind: 'brokencolonnade' },
      { x: 46, y: 20.5, w: 14, h: 1.0, kind: 'flowerbed' },
      { x: 31, y: 12, w: 1.6, h: 1.6, kind: 'topiary' },
      { x: 31, y: 30.5, w: 1.6, h: 1.6, kind: 'topiary' },
    ]),
  },
  {
    id: 'grand-slateyard',
    name: 'The Slate Yard',
    brief: 'RUIN. Fallen coursing, an ivied wall and two arbours — a ground the circuit stopped repairing.',
    theme: 'slateyard',
    leagues: ['Platinum', 'Masters', 'Tamer Elite', 'Tamers Apex'],
    w: SLATEYARD.w,
    h: SLATEYARD.h,
    obstacles: build(SLATEYARD.w, SLATEYARD.h, [
      // ⚠️ THE POOL WAS MEASURED AND IT WAS FIFTEEN PAINT JOBS ON ONE LAYOUT. Eleven boards
      // carried exactly SIX long bars and no chunky piece at all; thirteen carried 12-14
      // pieces; thirteen put 65-100%% of their cover in the middle third of X. Colour and
      // arrangement NAMES were doing all the differentiating and the silhouettes were one
      // silhouette.
      // ⚠️ TWO CAUSES, ONE STRUCTURAL AND ONE NOT. The deploy band bans the outer 24%% of
      // each end and no piece may cross the centre line, so every authored piece lives in a
      // strip from `w * 0.24 + 1.5` to `w / 2` — about a quarter of the width. That is
      // forced. What was NOT forced was authoring in the middle of that strip every time
      // instead of using both its edges, and reaching for two long runs as the mass on
      // almost every board.
      // ⚠️ SO EVERY BOARD NOW DECLARES A SIGNATURE and no two share one: piece COUNT (8 to
      // 21), how much of the mass is long BARS versus CHUNKY blocks versus many small
      // pieces, and where the cover sits in X and Y.
      //
      // SIGNATURE: 16 pieces / 4 bars / 4 arbours / every piece at its own depth. A ruin is
      // the one ground that should look UNPLANNED, so no two objects here sit at the same y
      // and none of them line up in x either. Everywhere else in the pool the mirror is
      // visible as a pair of matching bands; here it is invisible, because there is no band
      // to match.
      { x: 23, y: 5, w: 11, h: 3.0, kind: 'ruinedwall' },
      { x: 31, y: 22, w: 11, h: 2.8, kind: 'vinewall' },
      { x: 24, y: 14, w: 4, h: 4, kind: 'arbour' },
      { x: 35, y: 38, w: 4, h: 4, kind: 'arbour' },
      { x: 27, y: 31, w: 2.6, h: 3.15, kind: 'brokenpillar' },
      { x: 22, y: 45, w: 1.6, h: 1.6, kind: 'pillar' },
      { x: 38, y: 9, w: 1.4, h: 1.4, kind: 'obelisk' },
      { x: 29, y: 51, w: 2, h: 2, kind: 'urn' },
    ]),
  },
  {
    id: 'grand-lists',
    name: 'The Lists',
    brief: 'LISTS. Two colonnades above and below a long central lane — run it, or go the long way.',
    theme: 'travertine',
    leagues: ['Platinum', 'Masters', 'Tamer Elite', 'Tamers Apex'],
    w: LISTS.w,
    h: LISTS.h,
    obstacles: build(LISTS.w, LISTS.h, [
      // ⚠️ THE ONLY BOARD IN THE GAME WITH AN ENCLOSED LANE, and it takes 85 units of width
      // to build one. Two 18-unit runs on each half, above and below, leave a corridor ten
      // units deep and thirty-six long: too narrow to fight loose in, too long to cross
      // quickly, and open at both ends so nobody is ever actually trapped.
      // ⚠️ EIGHTEEN IS THE LONGEST RUN AUTHORED ANYWHERE. A colonnade is UPRIGHT so it may
      // reach 21 before it breaks its ceiling; every league below runs out of BOARD first.
      { x: 24, y: 20, w: 18, h: 3.2, kind: 'colonnade' },
      { x: 24, y: 33.5, w: 18, h: 3.2, kind: 'colonnade' },
      { x: 26, y: 27, w: 1.4, h: 1.4, kind: 'obelisk' },
      { x: 33, y: 8, w: 1.6, h: 1.6, kind: 'pillar' },
      { x: 33, y: 47, w: 1.6, h: 1.6, kind: 'pillar' },
      { x: 23, y: 4, w: 2, h: 2, kind: 'urn' },
    ]),
  },
  {
    id: 'grand-islands',
    name: 'The Islands',
    brief: 'ISLANDS. Three separate clusters with bare ground between them — pick one and hold it.',
    theme: 'granite',
    leagues: ['Platinum', 'Masters', 'Tamer Elite', 'Tamers Apex'],
    w: ISLANDS.w,
    h: ISLANDS.h,
    obstacles: build(ISLANDS.w, ISLANDS.h, [
      // ⚠️ THE POOL WAS MEASURED AND IT WAS FIFTEEN PAINT JOBS ON ONE LAYOUT. Eleven boards
      // carried exactly SIX long bars and no chunky piece at all; thirteen carried 12-14
      // pieces; thirteen put 65-100%% of their cover in the middle third of X. Colour and
      // arrangement NAMES were doing all the differentiating and the silhouettes were one
      // silhouette.
      // ⚠️ TWO CAUSES, ONE STRUCTURAL AND ONE NOT. The deploy band bans the outer 24%% of
      // each end and no piece may cross the centre line, so every authored piece lives in a
      // strip from `w * 0.24 + 1.5` to `w / 2` — about a quarter of the width. That is
      // forced. What was NOT forced was authoring in the middle of that strip every time
      // instead of using both its edges, and reaching for two long runs as the mass on
      // almost every board.
      // ⚠️ SO EVERY BOARD NOW DECLARES A SIGNATURE and no two share one: piece COUNT (8 to
      // 21), how much of the mass is long BARS versus CHUNKY blocks versus many small
      // pieces, and where the cover sits in X and Y.
      //
      // SIGNATURE: 18 pieces / 2 bars / 6 chunky, in three tight knots. The first draft
      // built its islands out of wall runs, which made them read as three more horizontal
      // bands; an island should be a LUMP. Each knot is now a gateway or an arbour with
      // small pieces packed against it, and the bare ground between them is the widest
      // stretch of nothing in the pool.
      { x: 25, y: 7, w: 6, h: 6.6, kind: 'gate' },
      { x: 31, y: 9, w: 2.6, h: 3.15, kind: 'brokenpillar' },
      { x: 25, y: 15, w: 2, h: 2, kind: 'urn' },
      { x: 27, y: 34, w: 4, h: 4, kind: 'arbour' },
      { x: 32, y: 39, w: 1.6, h: 1.6, kind: 'pillar' },
      { x: 25, y: 40, w: 1.4, h: 1.4, kind: 'obelisk' },
      { x: 36, y: 21, w: 10, h: 2.0, kind: 'dais' },
      { x: 34, y: 25, w: 1.6, h: 1.6, kind: 'topiary' },
      { x: 41, y: 17, w: 2, h: 2, kind: 'urn' },
    ]),
  },
  {
    id: 'grand-causeway',
    name: 'The Causeway',
    brief: 'CAUSEWAY. A raised spine end to end with low beds either side — the high road, or the fast one.',
    theme: 'jasper',
    leagues: ['Platinum', 'Masters', 'Tamer Elite', 'Tamers Apex'],
    w: CAUSEWAY.w,
    h: CAUSEWAY.h,
    obstacles: build(CAUSEWAY.w, CAUSEWAY.h, [
      // ⚠️ A SPINE THAT DOES NOT DIVIDE THE BOARD, which is what makes it a causeway rather
      // than Bronze's Long Cast. That one is a collapsed wall down the middle: it BLOCKS,
      // and the fight is about getting round it. This is three low platforms in a line — you
      // can walk straight over the whole thing. What it costs is exposure: the causeway is
      // the shortest route and the only one both sides can see along.
      // ⚠️ THE BEDS EITHER SIDE ARE THE LOWEST COVER IN THE POOL. They draw about a unit, so
      // the "safe" flanking route hides nothing either — it is only slower.
      { x: (CAUSEWAY.w - 14) / 2, y: (CAUSEWAY.h - 2.8) / 2, w: 14, h: 2.8, kind: 'dais' },
      { x: 29, y: 22.9, w: 12, h: 2.4, kind: 'dais' },
      { x: 30, y: 13, w: 14, h: 1.0, kind: 'flowerbed' },
      { x: 30, y: 34.3, w: 14, h: 1.0, kind: 'flowerbed' },
      { x: 28, y: 6, w: 1.6, h: 1.6, kind: 'topiary' },
      { x: 40, y: 44, w: 1.6, h: 1.6, kind: 'pillar' },
    ]),
  },
  {
    id: 'grand-grove',
    name: 'The Grove',
    brief: 'GROVE. Two runs at the ends and a scatter of standards between — thin cover, and a lot of it.',
    theme: 'amethystine',
    leagues: ['Platinum', 'Masters', 'Tamer Elite', 'Tamers Apex'],
    w: GROVE.w,
    h: GROVE.h,
    obstacles: build(GROVE.w, GROVE.h, [
      // ⚠️ THE POOL WAS MEASURED AND IT WAS FIFTEEN PAINT JOBS ON ONE LAYOUT. Eleven boards
      // carried exactly SIX long bars and no chunky piece at all; thirteen carried 12-14
      // pieces; thirteen put 65-100%% of their cover in the middle third of X. Colour and
      // arrangement NAMES were doing all the differentiating and the silhouettes were one
      // silhouette.
      // ⚠️ TWO CAUSES, ONE STRUCTURAL AND ONE NOT. The deploy band bans the outer 24%% of
      // each end and no piece may cross the centre line, so every authored piece lives in a
      // strip from `w * 0.24 + 1.5` to `w / 2` — about a quarter of the width. That is
      // forced. What was NOT forced was authoring in the middle of that strip every time
      // instead of using both its edges, and reaching for two long runs as the mass on
      // almost every board.
      // ⚠️ SO EVERY BOARD NOW DECLARES A SIGNATURE and no two share one: piece COUNT (8 to
      // 21), how much of the mass is long BARS versus CHUNKY blocks versus many small
      // pieces, and where the cover sits in X and Y.
      //
      // SIGNATURE: 21 pieces / 2 bars / 17 small. The most pieces of any board in the game
      // and the smallest mean piece after the Serpentine — a genuine thicket of standards
      // with one run at each end to carry the mass. Silver proved thin cover alone measures
      // under 1%% of board area; two colonnades fix that without turning the board into
      // another pair of bands, because seventeen verticals is what the eye actually reads.
      { x: 20, y: 4, w: 13, h: 2.6, kind: 'colonnade' },
      { x: 22, y: 13, w: 1.6, h: 1.6, kind: 'topiary' },
      { x: 28, y: 13, w: 1.6, h: 1.6, kind: 'topiary' },
      { x: 25, y: 19, w: 1.6, h: 1.6, kind: 'topiary' },
      { x: 31, y: 19, w: 1.6, h: 1.6, kind: 'topiary' },
      { x: 22, y: 25, w: 1.6, h: 1.6, kind: 'topiary' },
      { x: 28, y: 25, w: 1.6, h: 1.6, kind: 'topiary' },
      { x: 25, y: 31, w: 1.4, h: 1.4, kind: 'obelisk' },
      { x: 31, y: 31, w: 1.4, h: 1.4, kind: 'obelisk' },
      { x: 20, y: 37, w: 2, h: 2, kind: 'urn' },
      { x: 30, y: 43, w: 1.6, h: 1.6, kind: 'pillar' },
    ]),
  },
  {
    id: 'grand-breakwater',
    name: 'The Breakwater',
    brief: 'BREAKWATER. Short walls stepping diagonally across the field — permeable everywhere, straight nowhere.',
    theme: 'malachite',
    leagues: ['Platinum', 'Masters', 'Tamer Elite', 'Tamers Apex'],
    w: BREAKWATER.w,
    h: BREAKWATER.h,
    obstacles: build(BREAKWATER.w, BREAKWATER.h, [
      // ⚠️ A DIAGONAL IS THE ONE ARRANGEMENT 180-DEGREE MIRRORING MAKES FREE. Rotate a
      // stepped line half a turn and you get the same line continuing — so a run of four
      // short walls authored on one half becomes an eight-piece stagger across the whole
      // board, and it is perfectly fair while looking nothing like a mirrored layout. Every
      // other shape in this game has to fight the mirror; this one uses it.
      // ⚠️ SHORT PIECES, NOT LONG ONES. Nine units each: long enough to break a line of
      // sight, short enough that every one of them can be walked round. The board has no
      // barrier anywhere and no straight path anywhere either.
      { x: 25, y: 6, w: 9, h: 1.8, kind: 'wall' },
      { x: 29, y: 15, w: 9, h: 1.8, kind: 'wall' },
      { x: 33, y: 24, w: 9, h: 1.8, kind: 'wall' },
      { x: 27, y: 11, w: 2.6, h: 3.15, kind: 'brokenpillar' },
      { x: 31, y: 20, w: 2.6, h: 3.15, kind: 'brokenpillar' },
      { x: 24, y: 30, w: 1.6, h: 1.6, kind: 'pillar' },
      { x: 35, y: 33, w: 6, h: 6.6, kind: 'gate' },
    ]),
  },
  {
    id: 'grand-chequeryard',
    name: 'The Chequer Yard',
    brief: 'FOUR-SQUARE. Cover on the diagonals only — the straight ways across are the empty ones.',
    theme: 'chequer',
    leagues: ['Platinum', 'Masters', 'Tamer Elite', 'Tamers Apex'],
    w: CHEQUERYARD.w,
    h: CHEQUERYARD.h,
    obstacles: build(CHEQUERYARD.w, CHEQUERYARD.h, [
      // ⚠️ THE POOL WAS MEASURED AND IT WAS FIFTEEN PAINT JOBS ON ONE LAYOUT. Eleven boards
      // carried exactly SIX long bars and no chunky piece at all; thirteen carried 12-14
      // pieces; thirteen put 65-100%% of their cover in the middle third of X. Colour and
      // arrangement NAMES were doing all the differentiating and the silhouettes were one
      // silhouette.
      // ⚠️ TWO CAUSES, ONE STRUCTURAL AND ONE NOT. The deploy band bans the outer 24%% of
      // each end and no piece may cross the centre line, so every authored piece lives in a
      // strip from `w * 0.24 + 1.5` to `w / 2` — about a quarter of the width. That is
      // forced. What was NOT forced was authoring in the middle of that strip every time
      // instead of using both its edges, and reaching for two long runs as the mass on
      // almost every board.
      // ⚠️ SO EVERY BOARD NOW DECLARES A SIGNATURE and no two share one: piece COUNT (8 to
      // 21), how much of the mass is long BARS versus CHUNKY blocks versus many small
      // pieces, and where the cover sits in X and Y.
      //
      // SIGNATURE: 10 pieces / 4 bars, all hard against the deploy band. Every other board
      // in the pool bunches its cover toward the centre line; this one pushes everything to
      // the OUTER edge of the legal strip, so the middle of the board is the largest empty
      // square in the game and each side has its shelter behind it rather than in front.
      // Crossing is not contested — it is simply exposed.
      { x: 23, y: 5, w: 12, h: 2.4, kind: 'wall' },
      { x: 23, y: 49.3, w: 12, h: 2.4, kind: 'wall' },
      { x: 23, y: 20, w: 4, h: 4, kind: 'arbour' },
      { x: 23, y: 32.7, w: 4, h: 4, kind: 'arbour' },
      { x: 30, y: 27, w: 1.4, h: 1.4, kind: 'obelisk' },
    ]),
  },
  {
    id: 'grand-mosaiccourt',
    name: 'The Mosaic Court',
    brief: 'WHEEL. Cover set as spokes around an empty hub — every approach is a radius.',
    theme: 'mosaic',
    leagues: ['Platinum', 'Masters', 'Tamer Elite', 'Tamers Apex'],
    w: MOSAICCOURT.w,
    h: MOSAICCOURT.h,
    obstacles: build(MOSAICCOURT.w, MOSAICCOURT.h, [
      // ⚠️ THE POOL WAS MEASURED AND IT WAS FIFTEEN PAINT JOBS ON ONE LAYOUT. Eleven boards
      // carried exactly SIX long bars and no chunky piece at all; thirteen carried 12-14
      // pieces; thirteen put 65-100%% of their cover in the middle third of X. Colour and
      // arrangement NAMES were doing all the differentiating and the silhouettes were one
      // silhouette.
      // ⚠️ TWO CAUSES, ONE STRUCTURAL AND ONE NOT. The deploy band bans the outer 24%% of
      // each end and no piece may cross the centre line, so every authored piece lives in a
      // strip from `w * 0.24 + 1.5` to `w / 2` — about a quarter of the width. That is
      // forced. What was NOT forced was authoring in the middle of that strip every time
      // instead of using both its edges, and reaching for two long runs as the mass on
      // almost every board.
      // ⚠️ SO EVERY BOARD NOW DECLARES A SIGNATURE and no two share one: piece COUNT (8 to
      // 21), how much of the mass is long BARS versus CHUNKY blocks versus many small
      // pieces, and where the cover sits in X and Y.
      //
      // SIGNATURE: 14 pieces / 3 bars of THREE different lengths / 4 chunky. The first draft
      // made its spokes from three runs at even spacing, which is a ladder rather than a
      // wheel. Thirteen, nine and a gateway at three different radii from the hub read as
      // radiating; three equal bars read as shelving.
      { x: 24, y: 10, w: 13, h: 2.6, kind: 'colonnade' },
      { x: 33, y: 21, w: 9, h: 2.2, kind: 'hedge' },
      { x: 26, y: 33, w: 6, h: 6.6, kind: 'gate' },
      { x: 38, y: 6, w: 1.6, h: 1.6, kind: 'topiary' },
      { x: 23, y: 24, w: 2, h: 2, kind: 'urn' },
      { x: 36, y: 44, w: 2.6, h: 3.15, kind: 'brokenpillar' },
      { x: 30, y: 16, w: 1.4, h: 1.4, kind: 'obelisk' },
    ]),
  },
  {
    id: 'grand-rosewalk',
    name: 'The Rose Walk',
    brief: 'GAUNTLET. A hundred and nineteen units long, cover alternating side to side the whole way.',
    theme: 'rosestone',
    leagues: ['Platinum', 'Masters', 'Tamer Elite', 'Tamers Apex'],
    w: ROSEWALK.w,
    h: ROSEWALK.h,
    obstacles: build(ROSEWALK.w, ROSEWALK.h, [
      // ⚠️ THE POOL WAS MEASURED AND IT WAS FIFTEEN PAINT JOBS ON ONE LAYOUT. Eleven boards
      // carried exactly SIX long bars and no chunky piece at all; thirteen carried 12-14
      // pieces; thirteen put 65-100%% of their cover in the middle third of X. Colour and
      // arrangement NAMES were doing all the differentiating and the silhouettes were one
      // silhouette.
      // ⚠️ TWO CAUSES, ONE STRUCTURAL AND ONE NOT. The deploy band bans the outer 24%% of
      // each end and no piece may cross the centre line, so every authored piece lives in a
      // strip from `w * 0.24 + 1.5` to `w / 2` — about a quarter of the width. That is
      // forced. What was NOT forced was authoring in the middle of that strip every time
      // instead of using both its edges, and reaching for two long runs as the mass on
      // almost every board.
      // ⚠️ SO EVERY BOARD NOW DECLARES A SIGNATURE and no two share one: piece COUNT (8 to
      // 21), how much of the mass is long BARS versus CHUNKY blocks versus many small
      // pieces, and where the cover sits in X and Y.
      //
      // SIGNATURE: 16 pieces spread across the WHOLE legal strip — 31 to 57 of a 30-to-59
      // window — where every other board occupies barely half of it. On a 119-unit ground
      // the strip is 29 units wide per half, which is more room than some entire Wood
      // boards, and using all of it is what makes the walk feel long rather than merely
      // wide. Nothing here sits at the same x as anything else.
      { x: 31, y: 4, w: 12, h: 2.4, kind: 'wall' },
      { x: 46, y: 31, w: 10, h: 2.0, kind: 'dais' },
      { x: 38, y: 17, w: 9, h: 2.6, kind: 'ruinedwall' },
      { x: 53, y: 9, w: 2.6, h: 3.15, kind: 'brokenpillar' },
      { x: 34, y: 26, w: 1.6, h: 1.6, kind: 'pillar' },
      { x: 49, y: 21, w: 1.4, h: 1.4, kind: 'obelisk' },
      { x: 42, y: 35, w: 2, h: 2, kind: 'urn' },
      { x: 57, y: 25, w: 1.6, h: 1.6, kind: 'topiary' },
    ]),
  },
  {
    id: 'grand-onyxhall',
    name: 'The Onyx Hall',
    brief: 'HALL. Two long colonnades make a nave with an aisle each side — three parallel fights.',
    theme: 'onyx',
    leagues: ['Platinum', 'Masters', 'Tamer Elite', 'Tamers Apex'],
    w: ONYXHALL.w,
    h: ONYXHALL.h,
    obstacles: build(ONYXHALL.w, ONYXHALL.h, [
      // ⚠️ THE INVERSE OF THE LISTS, USING THE SAME PROP. That board puts its two runs above
      // and below one lane, so there is a corridor and an outside. This puts them so the
      // board is cut into THREE parallel channels of similar width — a nave and two aisles —
      // and nothing crosses between them for most of their length. Three fights happen at
      // once and whoever wins a channel first gets to turn into the next one.
      // ⚠️ SIXTEEN AND FOURTEEN, NOT TWO SIXTEENS. Unequal runs mean the aisles have
      // different mouths, so the board has a fast side and a slow one.
      { x: 28, y: 14, w: 16, h: 3.0, kind: 'colonnade' },
      { x: 30, y: 31, w: 14, h: 2.8, kind: 'brokencolonnade' },
      { x: 26, y: 5, w: 11, h: 2.2, kind: 'dais' },
      { x: 33, y: 22, w: 1.4, h: 1.4, kind: 'obelisk' },
      { x: 26, y: 42, w: 1.6, h: 1.6, kind: 'pillar' },
      { x: 40, y: 9, w: 2, h: 2, kind: 'urn' },
    ]),
  },
  {
    id: 'grand-thepit',
    name: 'The Pit',
    brief: 'PIT. Deeper than it is wide — the two sides start thirty units apart, with room to go round.',
    theme: 'verdite',
    leagues: ['Platinum', 'Masters', 'Tamer Elite', 'Tamers Apex'],
    w: THEPIT.w,
    h: THEPIT.h,
    obstacles: build(THEPIT.w, THEPIT.h, [
      // ⚠️ THE POOL WAS MEASURED AND IT WAS FIFTEEN PAINT JOBS ON ONE LAYOUT. Eleven boards
      // carried exactly SIX long bars and no chunky piece at all; thirteen carried 12-14
      // pieces; thirteen put 65-100%% of their cover in the middle third of X. Colour and
      // arrangement NAMES were doing all the differentiating and the silhouettes were one
      // silhouette.
      // ⚠️ TWO CAUSES, ONE STRUCTURAL AND ONE NOT. The deploy band bans the outer 24%% of
      // each end and no piece may cross the centre line, so every authored piece lives in a
      // strip from `w * 0.24 + 1.5` to `w / 2` — about a quarter of the width. That is
      // forced. What was NOT forced was authoring in the middle of that strip every time
      // instead of using both its edges, and reaching for two long runs as the mass on
      // almost every board.
      // ⚠️ SO EVERY BOARD NOW DECLARES A SIGNATURE and no two share one: piece COUNT (8 to
      // 21), how much of the mass is long BARS versus CHUNKY blocks versus many small
      // pieces, and where the cover sits in X and Y.
      //
      // SIGNATURE: 12 pieces / 2 bars / 4 chunky, and every one of them in the outer fifth
      // of the DEPTH. On the only portrait board in the game the middle is the crossing and
      // must stay clear; all the cover is at the two mouths, which is a distribution no
      // landscape board in the pool can copy because none of them has the depth to spare.
      { x: 19, y: 6, w: 12, h: 2.4, kind: 'wall' },
      { x: 22, y: 12, w: 6, h: 6.6, kind: 'gate' },
      { x: 19, y: 24, w: 9, h: 2.6, kind: 'ruinedwall' },
      { x: 26, y: 19, w: 2.6, h: 3.15, kind: 'brokenpillar' },
      { x: 18, y: 27, w: 1.6, h: 1.6, kind: 'pillar' },
      { x: 24, y: 3, w: 1.4, h: 1.4, kind: 'obelisk' },
    ]),
  },
  {
    id: 'grand-thelevel',
    name: 'The Level',
    brief: 'BARE. No cover anywhere — the only ground in the game where position is all there is.',
    theme: 'travertine',
    // ⚠️ A SHARED SURFACE, NOT A SIXTEENTH STONE, AND THE REASON IS THE BOARD ITSELF. Every
    // other ground in this pool is named for its stone because the stone is what tells the
    // twenty apart. This one has no cover to sort it from the others — its identity is the
    // EMPTINESS — so spending a new quarry on it would be spending the pool's scarcest
    // resource on the board that needs it least. Plain sand is also what a bare arena is
    // actually floored with.
    surface: 'sand',
    leagues: ['Platinum', 'Masters', 'Tamer Elite', 'Tamers Apex'],
    w: THELEVEL.w,
    h: THELEVEL.h,
    // ⚠️ EMPTY ON PURPOSE, AND IT IS A DESIGN STATEMENT RATHER THAN AN OMISSION. Every rule
    // in `docs/ARENA_DESIGN.md` is about what cover is FOR — breaking sight lines, diverting
    // straight runs, giving a ranged monster something to hold. A pool of twenty should
    // contain exactly one ground that asks what happens when none of that exists: no
    // shelter, no flanking route that is safer than any other, nothing to hold. Five a side
    // on open ground is the purest test of a roster the game can set.
    // ⚠️ AND IT MUST BE EXACTLY ONE. Two bare boards is not a statement, it is a gap in the
    // content — `arenas.test.ts` pins the count at one so neither number can drift.
    obstacles: [],
  },
  {
    id: 'gold-parterre',
    name: 'The Parterre',
    brief: 'PARTERRE. Low beds to a formal plan — you can see clean over almost all of it, and so can they.',
    theme: 'gildedcourt',
    leagues: ['Gold'],
    w: PARTERRE.w,
    h: PARTERRE.h,
    obstacles: build(PARTERRE.w, PARTERRE.h, [
      // ⚠️ THE ONE BOARD ALLOWED TO BE A DIAGRAM, because a parterre IS one — a garden set
      // out to a drawn plan is the whole conceit of the league. Everywhere else a regular
      // grid of cover is the failure mode ("too symetrical"); here it is the joke.
      // ⚠️ AND IT IS THE LOW BOARD. Beds draw about a unit — the only cover in the game a
      // monster can see clean over — so this is the one Gold ground where position is worth
      // something and concealment is worth almost nothing. Every other board here is
      // chest-height or taller, which is exactly the sameness this pass is fixing.
      // ⚠️ 0.9 DEEP, NOT 2, AND THE LOWNESS IS WHY. A prop may not be authored deeper than
      // it draws tall, or the sprite fails to cover the ground it blocks — and a bed that
      // draws 0.94 may therefore only be 0.9 deep. That is not a compromise: a formal bed IS
      // a thin line you step over, and it still breaks a straight run twelve units long.
      { x: 22, y: 4, w: 12, h: 0.9, kind: 'flowerbed' },
      { x: 22, y: 32, w: 12, h: 0.9, kind: 'flowerbed' },
      // ⚠️ A SHORT HEDGE MUST ALSO BE A SHALLOW ONE. Depth may not exceed drawn height, and
      // a hedge draws width / 3.82 — so 8 wide can only be 2.0 deep, where 12 wide may be
      // 3.1. The length and the thickness are not independent; authoring 2.6 on an 8-unit
      // run put the footprint half a unit deeper than the sprite covering it.
      { x: 26, y: 17, w: 8, h: 2.0, kind: 'hedge' },
      { x: 21, y: 11, w: 2, h: 2, kind: 'urn' },
      { x: 21, y: 25, w: 2, h: 2, kind: 'urn' },
    ]),
  },
  {
    id: 'gold-bower',
    name: 'The Bower',
    brief: 'BOWER. An arbour and a hedge per side — shelter that stops a charge and not a bow.',
    theme: 'parterre',
    leagues: ['Gold'],
    w: BOWER.w,
    h: BOWER.h,
    obstacles: build(BOWER.w, BOWER.h, [
      // ⚠️ THE DEEP BOARD GETS THE ENCLOSED ONE, WHICH IS THE OPPOSITE OF SILVER'S CISTERN:
      // that board is deep with its cover strung down the middle, so depth means a long
      // exposed walk. Here the depth is spent at the two ENDS — each side starts inside a
      // pocket it can hold cheaply, and the question is who is willing to leave it.
      // ⚠️ AND IT IS THE ONLY GOLD BOARD WITH A PIERCED PIECE. An arbour is cover that stops
      // a charge and not a bow, so a bower is genuinely safe from one kind of monster and
      // not the other — which is a different shelter from the hedges either side of it.
      { x: 20, y: 14, w: 4, h: 4, kind: 'arbour' },
      { x: 20, y: 31, w: 4, h: 4, kind: 'arbour' },
      { x: 18, y: 22.5, w: 10, h: 2.6, kind: 'hedge' },
      { x: 26, y: 6, w: 1.6, h: 1.6, kind: 'topiary' },
    ]),
  },
  {
    id: 'gold-terraces',
    name: 'The Terraces',
    brief: 'TERRACES. Three hedges stepping back in depth — cross early and shallow, or late and deep.',
    theme: 'gildedcourt',
    surface: 'flagstone',
    leagues: ['Gold'],
    w: TERRACES.w,
    h: TERRACES.h,
    obstacles: build(TERRACES.w, TERRACES.h, [
      // ⚠️ NOT AN ECHELON, AND THE DIFFERENCE IS THAT THESE ARE PARALLEL. Bronze's Slag Yard
      // sets two runs DIAGONALLY so the gap between them is a slot you thread. Three runs
      // stepping straight back make three separate crossings at three depths, and picking
      // one commits you to a lane — on the longest ground in the game (2.40), where the
      // wrong lane is forty units from the right one.
      // ⚠️ THREE DIFFERENT LENGTHS, ON PURPOSE. 12, 9 and 11: a terrace that steps back
      // should also step in, or the three crossings are the same crossing three times.
      // ⚠️ AND 12.9 IS THE LONGEST A HEDGE MAY EVER BE. `prop-hedge` is 256x67, so drawn
      // height is width / 3.82; past 12.9 it breaks the 3.4 cover ceiling and stops being
      // something a monster can shoot over. The first draft of this board asked for 16 and
      // `arenas.test.ts` measured it at 4.19 and refused. Long runs are Silver's colonnade,
      // which is UPRIGHT and allowed to be tall; a hedge is not.
      { x: 23, y: 4, w: 12, h: 2.6, kind: 'hedge' },
      { x: 30, y: 15, w: 9, h: 2.2, kind: 'hedge' },
      { x: 25, y: 26, w: 11, h: 2.6, kind: 'hedge' },
      { x: 24, y: 20, w: 1.6, h: 1.6, kind: 'topiary' },
      { x: 36, y: 9, w: 1.6, h: 1.6, kind: 'topiary' },
    ]),
  },
  {
    id: 'gold-knotgarden',
    name: 'The Knot Garden',
    brief: 'KNOT. A basin dead centre with the hedging bunched round it — go round, or go in.',
    theme: 'parterre',
    surface: 'concrete',
    leagues: ['Gold'],
    w: KNOTGARDEN.w,
    h: KNOTGARDEN.h,
    obstacles: build(KNOTGARDEN.w, KNOTGARDEN.h, [
      // ⚠️ THE EXACT INVERSE OF SILVER'S LONG WALK, which puts its cover at the two ends and
      // leaves the middle bare. Here the middle is the only cover and the flanks are open: a
      // melee monster wants the knot, a ranged one wants the edge, and both are viable.
      // ⚠️ AND THE CENTRE IS THE GAME'S ONLY CURVED PIECE. Every other landmark in every
      // league is a bar — Iron's dais, Bronze's wall, Silver's colonnade — so they all divide
      // space the same way whatever the arrangement. A basin is much shorter than it is long
      // and has no flat face, which makes sheltering behind it a genuinely different problem.
      // ⚠️ IT IS AN OVAL, NOT A CIRCLE, AND THE BILLBOARD IS WHY. Authored 7 x 7 the guard
      // refused it: a prop's sprite must draw at least as tall as its footprint is deep, and
      // a fountain draws width / 2.21 — so a 7-unit basin may be 3 deep, never 7. Every prop
      // in this game is a card standing on a rectangle, and a deep round footprint is the
      // one shape that system cannot honestly cover.
      // ⚠️ ON THE MIRROR AXIS, WHICH IS CORRECT HERE. It must sit at exactly
      // (w - size) / 2 or `build` emits it twice, overlapping itself.
      { x: (KNOTGARDEN.w - 7) / 2, y: (KNOTGARDEN.h - 3) / 2, w: 7, h: 3, kind: 'fountain' },
      { x: 24, y: 12, w: 9, h: 2.2, kind: 'hedge' },
      { x: 24, y: 28, w: 9, h: 2.2, kind: 'hedge' },
      { x: 22, y: 20, w: 1.6, h: 1.6, kind: 'topiary' },
      { x: 31, y: 6, w: 2, h: 2, kind: 'urn' },
    ]),
  },
  {
    id: 'gold-longaxis',
    name: 'The Long Axis',
    brief: 'AXIS. An overgrown spine down the middle — the one ground on the circuit nobody keeps up.',
    theme: 'gildedcourt',
    surface: 'sand',
    leagues: ['Gold'],
    w: LONGAXIS.w,
    h: LONGAXIS.h,
    obstacles: build(LONGAXIS.w, LONGAXIS.h, [
      // ⚠️ THE ONE GROUND ON THE CIRCUIT THAT IS NOT KEPT UP, and every league should have
      // one. `vinewall` — a ruined wall smothered in ivy — has existed since Tin and was
      // authored for exactly this: a board that says the garden is OLD. It also means the
      // Long Axis is the only Gold ground with masonry on it, which is most of why it does
      // not look like the other five.
      // ⚠️ A CENTRED PIECE IS CORRECT HERE FOR THE SECOND TIME IN THE GAME (Iron's Furnace
      // Row is the other). A formal garden is laid out ABOUT an axis; take the centre away
      // and this stops being a pleasance and becomes two hedges nobody planted on purpose.
      { x: (LONGAXIS.w - 12) / 2, y: (LONGAXIS.h - 2.6) / 2, w: 12, h: 2.6, kind: 'vinewall' },
      { x: 17, y: 12, w: 10, h: 2.6, kind: 'hedge' },
      { x: 17, y: 38, w: 10, h: 2.6, kind: 'vinewall' },
      { x: 21, y: 22, w: 2, h: 2, kind: 'urn' },
      { x: 27, y: 5, w: 2, h: 2, kind: 'urn' },
    ]),
  },
  {
    id: 'gold-cornerwalks',
    name: 'The Corner Walks',
    brief: 'CORNERS. Beds at the ends, standards through the middle — ankle-high or twice your height, nothing between.',
    theme: 'parterre',
    surface: 'packedearth',
    leagues: ['Gold'],
    w: CORNERWALKS.w,
    h: CORNERWALKS.h,
    obstacles: build(CORNERWALKS.w, CORNERWALKS.h, [
      // ⚠️ THE LAST OF THE SIX, AND THE ONE ABOUT THE CENTRE BEING A BAD PLACE. The Knot
      // makes the middle the only shelter; this makes it the only ground every piece on the
      // board can see. Same league, same allowance, opposite verdict on the same square of
      // floor — which is the argument for six grounds rather than one repeated.
      // ⚠️ AND IT IS THE VERTICAL BOARD. No hedges at all: two long beds you see over and
      // six standards you see PAST. Everything on it is either ankle-high or twice a
      // monster, with nothing in between, which is a silhouette none of the other five has.
      { x: 20, y: 4, w: 14, h: 1.0, kind: 'flowerbed' },
      { x: 20, y: 38, w: 14, h: 1.0, kind: 'flowerbed' },
      // ⚠️ FIVE STANDARDS, NOT THREE, and the count is the point. At three this board's
      // signature matched two Silver grounds exactly; the fix is not decoration but the
      // thing the board is FOR — a walk lined with standards should be lined with enough of
      // them to read as an avenue rather than as three posts.
      { x: 22, y: 12, w: 1.6, h: 1.6, kind: 'topiary' },
      { x: 28, y: 18, w: 1.6, h: 1.6, kind: 'topiary' },
      { x: 22, y: 24, w: 1.6, h: 1.6, kind: 'topiary' },
      { x: 28, y: 30, w: 1.6, h: 1.6, kind: 'topiary' },
      { x: 22, y: 36, w: 1.6, h: 1.6, kind: 'topiary' },
    ]),
  },
  {
    id: 'silver-colonnade',
    name: 'The Colonnade',
    brief: 'PERISTYLE. Colonnades enclosing a centre court, open at the corners — fight inside it or circle it.',
    theme: 'assayfloor',
    leagues: ['Silver'],
    w: COLONNADE.w,
    h: COLONNADE.h,
    obstacles: build(COLONNADE.w, COLONNADE.h, [
      // ⚠️ A PERISTYLE IS NOT A COURT, AND THE DIFFERENCE IS WHERE THE VALUE SITS. Copper's
      // Ingot Yard and Iron's Furnace Row are courts: a landmark dead centre with four ways
      // in, so the middle is the prize. Here the middle is EMPTY and the enclosure is the
      // prize — worth holding, and the thing it encloses is not.
      // ⚠️ AND IT IS BUILT FROM RUNS NOW, NOT FROM SINGLE COLUMNS. The first draft made this
      // shape out of eight `pillar` pieces and measured 0.79% of the board under cover — the
      // emptiest ground in the game by a factor of four. Two colonnade runs per side give it
      // a wall's mass while staying a thing you can see, and shoot, THROUGH.
      // ⚠️ TWO DIFFERENT LENGTHS ON THE TWO SIDES, AND THE MIRROR IS WHY IT IS STILL FAIR.
      // `build` rotates 180 degrees, so the 15 at the top reappears at the bottom on the
      // other half and both players face one of each. A peristyle with four identical sides
      // is a stencil; one with a long side and a short side is a building.
      { x: 19.5, y: 6.5, w: 15, h: 2.6, kind: 'colonnade' },
      { x: 23, y: 33.8, w: 10, h: 2.4, kind: 'colonnade' },
      // The corner posts of the enclosure, and the only slender pieces left on the board.
      { x: 21, y: 16, w: 1.6, h: 1.6, kind: 'pillar' },
      { x: 21, y: 25.1, w: 1.6, h: 1.6, kind: 'pillar' },
      { x: 30, y: 20.65, w: 1.4, h: 1.4, kind: 'obelisk' },
    ]),
  },
  {
    id: 'silver-cistern',
    name: 'The Cistern',
    brief: 'STAGGERED FILE. Two runs offset in depth — no straight lane, and every bay is passable.',
    theme: 'cupelhearth',
    leagues: ['Silver'],
    w: CISTERN.w,
    h: CISTERN.h,
    obstacles: build(CISTERN.w, CISTERN.h, [
      // ⚠️ THE INVERSE OF IRON'S CHICANE, USING THE OPPOSITE PROP, WHICH IS THE POINT. A
      // chicane is built from gateways — wide, opaque, and it BLOCKS: you weave because you
      // cannot pass. A colonnade blocks nothing; every bay is walkable and none of them is
      // safe. Same question asked of a pierced prop instead of a solid one, and the answer
      // changes from "which way round" to "how much am I willing to be seen".
      // ⚠️ STAGGERED IN DEPTH, NOT IN A LINE. Two runs at the same depth would be a screen
      // (that is the Bullion Floor's board); set eleven units apart down a 51-unit ground
      // they are a filter you pass through twice, from different angles.
      { x: 17, y: 11, w: 14, h: 2.6, kind: 'brokencolonnade' },
      { x: 21, y: 22, w: 9, h: 2.2, kind: 'colonnade' },
      { x: 19, y: 33, w: 1.6, h: 1.6, kind: 'pillar' },
      { x: 26, y: 5, w: 1.4, h: 1.4, kind: 'obelisk' },
    ]),
  },
  {
    id: 'silver-longwalk',
    name: 'The Long Walk',
    brief: 'BOOKENDS. Cover clustered at each third and nothing in between — hold your own end, or cross.',
    theme: 'assayfloor',
    surface: 'flagstone',
    leagues: ['Silver'],
    w: LONGWALK.w,
    h: LONGWALK.h,
    obstacles: build(LONGWALK.w, LONGWALK.h, [
      // ⚠️ THE OPPOSITE OF A SPINE, ON THE BOARD WHERE A SPINE WOULD BE OBVIOUS. Bronze's
      // Long Cast is the game's other 2.4-aspect ground and it puts a collapsed run down the
      // MIDDLE, so the length is divided. Doing that again here is how Iron first ended up
      // reading as Bronze. Instead the cover goes to the two ends: 85 units long with a bare
      // forty through the centre, so the middle is ground neither side wants to be caught in
      // and the fight is about whether you leave your own thicket at all.
      // ⚠️ AND THE BOOKEND IS AN L, NOT A BAR. A single run across each end would be a
      // start line; a run plus a second turned along the edge gives the defender a corner to
      // hold and the attacker a flank to go round, which is what makes staying home a choice
      // rather than the only move.
      // ⚠️ THE MASS IS PUSHED HARD OUTWARD, WHICH IS WHAT A BOOKEND MEANS. Authored at 22.5
      // and 24 it sat in the middle of the legal strip and this board's signature came out
      // byte-identical to the Colonnade's — two boards in ONE league with the same piece
      // count, the same bar count and the same spread. A bookend that is not at the end is
      // just a shelf; the runs now start as close to the deployment band as the rule allows.
      { x: 21.9, y: 6, w: 14, h: 2.6, kind: 'colonnade' },
      { x: 21.9, y: 27.9, w: 11, h: 2.4, kind: 'brokencolonnade' },
      { x: 24, y: 16.5, w: 1.4, h: 1.4, kind: 'obelisk' },
      { x: 38, y: 11, w: 1.6, h: 1.6, kind: 'pillar' },
      { x: 38, y: 23.7, w: 1.6, h: 1.6, kind: 'pillar' },
      { x: 30, y: 4, w: 2, h: 2, kind: 'urn' },
    ]),
  },
  {
    id: 'silver-assayyard',
    name: 'The Assay Yard',
    brief: 'QUINCUNX. Four runs around an empty middle — the fastest crossing is the one they all overlook.',
    theme: 'cupelhearth',
    surface: 'concrete',
    leagues: ['Silver'],
    w: ASSAYYARD.w,
    h: ASSAYYARD.h,
    obstacles: build(ASSAYYARD.w, ASSAYYARD.h, [
      // ⚠️ THE CIRCUIT'S REFERENCE BOARD — its grid is exactly what `arenaGridFor(4)` asks
      // for — so it should read as the plain statement of the family rather than as the
      // busiest example of it. Four pieces mirrored to eight, and nothing on the axis.
      // ⚠️ AND THE QUINCUNX KEEPS ITS CENTRE EMPTY, WHICH IS WHAT MAKES IT NOT A COURT.
      // Iron's Furnace Row owns "landmark dead centre with four ways to it" and builds it
      // from a platform you stand ON. The five points of a die with a hole in the middle is
      // a different shape and a different fight: the centre is the fastest crossing and the
      // only place all four runs can see at once.
      { x: 21, y: 9, w: 12, h: 2.4, kind: 'colonnade' },
      { x: 21, y: 34.5, w: 12, h: 2.4, kind: 'colonnade' },
      { x: 26, y: 21, w: 1.4, h: 1.4, kind: 'obelisk' },
      { x: 19, y: 22, w: 1.6, h: 1.6, kind: 'pillar' },
    ]),
  },
  {
    id: 'silver-bullion',
    name: 'The Bullion Floor',
    brief: 'SCREENS. Three runs stacked into a screen per side, one ruined — take a door, or go round the ends.',
    theme: 'assayfloor',
    surface: 'sand',
    leagues: ['Silver'],
    w: BULLION.w,
    h: BULLION.h,
    obstacles: build(BULLION.w, BULLION.h, [
      // ⚠️ A BARRIER ACROSS THE APPROACH IS BUILT BY STACKING RUNS IN DEPTH, NOT BY TURNING
      // ONE SIDEWAYS — and the first draft of this board tried to turn one sideways. The
      // standing warning in ARENA_DESIGN says every prop draws along X, so a 2.4 x 13
      // footprint draws 0.8 units tall over ground 13 deep; `arenas.test.ts` measured
      // exactly that and refused it. A comment two lines above claimed the colonnade was the
      // exception to that rule. It is not: the prop is a billboard, and rotating the
      // RECTANGLE does not rotate the ART.
      // ⚠️ SO THE SCREEN IS THREE RUNS ONE ABOVE ANOTHER. Together they span the depth and
      // stop the charge; the two gaps between them are the doors, about eight units each —
      // wide enough to take, narrow enough to be watched from both sides.
      // ⚠️ THREE UNEQUAL RUNS, NOT THREE COPIES. Stacked at one length the screen reads as
      // fence panels; at 13 / 16 / 11 it reads as a wall that was built in stages, and the
      // two doors between them are different widths, so one is the obvious way through and
      // the other is the one nobody watches.
      { x: 25, y: 4, w: 13, h: 2.4, kind: 'colonnade' },
      { x: 23, y: 15, w: 16, h: 2.8, kind: 'brokencolonnade' },
      { x: 27, y: 26, w: 11, h: 2.4, kind: 'colonnade' },
      { x: 21, y: 34, w: 1.4, h: 1.4, kind: 'obelisk' },
    ]),
  },
  {
    id: 'iron-anvilyard',
    name: 'The Anvil Yard',
    brief: 'CHICANE. Four gateways staggered through the middle — you may weave, not charge.',
    theme: 'forgefloor',
    leagues: ['Iron'],
    w: ANVILYARD.w,
    h: ANVILYARD.h,
    obstacles: build(ANVILYARD.w, ANVILYARD.h, [
      // ⚠️ A CHICANE HAS TO BE BUILT FROM UPRIGHT PROPS, and until the height ceiling was
      // split by kind there were none to build it from. A gateway is 0.88:1 — near enough
      // square in plan to stand IN the run rather than beside it — and at the upright cap
      // it draws 5.7 tall, twice a monster, which is what makes four of them a barrier you
      // read from the far end rather than four bumps.
      // ⚠️ AND IT IS THE ARRANGEMENT BRONZE DOES NOT HAVE. Bronze's four are a court, a
      // scattered ruin, a spine and an echelon; Iron takes the chicane, the dogleg, the
      // flanks and the court-with-a-dais, so the two circuits share nothing but their
      // masonry ladder.
      { x: 16.5, y: 3, w: 5, h: 5.6, kind: 'gate' },
      { x: 16.5, y: 20, w: 5, h: 5.6, kind: 'gate' },
      { x: 24, y: 12, w: 1.6, h: 1.6, kind: 'pillar' },
    ]),
  },
  {
    id: 'iron-quenchpool',
    name: 'The Quench',
    brief: 'AVENUE. Two files of gateways make a corridor down the middle — fast and seen, or long and safe.',
    theme: 'forgefloor',
    surface: 'flagstone',
    leagues: ['Iron'],
    w: QUENCHPOOL.w,
    h: QUENCHPOOL.h,
    obstacles: build(QUENCHPOOL.w, QUENCHPOOL.h, [
      // WARNING: THE DOGLEG DID NOT SURVIVE THE RENDER, AND THE PROP WAS WHY. It was built
      // from four stepped platforms, and a dais at this camera on a pale flagstone floor is
      // a smear — see the height fix in `props3d.ts`. Even corrected, a low platform cannot
      // carry a board on its own: what a dogleg needs is a barrier you can SEE the ends of.
      //
      // WARNING: AN AVENUE IS THE INVERSE OF THE CHICANE, which is why it belongs on the
      // other deep board. The Anvil Yard staggers its gateways so there is no straight
      // line; this one puts them in two files so there IS one — an eleven-unit corridor
      // running the full depth, quick and overlooked from both sides, with the long way
      // round outside them. Same prop, opposite question.
      { x: 13.5, y: 10, w: 5, h: 5.6, kind: 'gate' },
      { x: 13.5, y: 26, w: 5, h: 5.6, kind: 'gate' },
      // A pier at each mouth, so entering the avenue is a decision rather than a default.
      { x: 20, y: 3, w: 1.6, h: 1.6, kind: 'pillar' },
    ]),
  },
  {
    id: 'iron-drawfloor',
    name: 'The Drawing Floor',
    brief: 'FLANKS. Long platforms down both edges, a gateway at each mouth, the middle bare.',
    theme: 'cinderyard',
    leagues: ['Iron'],
    w: DRAWFLOOR.w,
    h: DRAWFLOOR.h,
    obstacles: build(DRAWFLOOR.w, DRAWFLOOR.h, [
      // ⚠️ THE SPINE MOVED TO BRONZE AND STAYED THERE. A collapsed run down the middle is
      // the Long Cast's whole identity, and putting one on the longest Iron board too was
      // how these two leagues ended up reading as one. On a 2.43 aspect the flanks are the
      // other honest answer: the centre line is the only quick path, so fencing the EDGES
      // means a ranged monster can shelter while a melee one that takes the short route
      // arrives seen.
      { x: 18.2, y: 0.6, w: 14, h: 2.8, kind: 'dais' },
      { x: 18.2, y: 23.9, w: 14, h: 2.8, kind: 'dais' },
      { x: 19, y: 11, w: 5, h: 5.6, kind: 'gate' },
    ]),
  },
  {
    id: 'iron-furnacerow',
    name: 'The Furnace Row',
    brief: 'TERRACES. Platforms stepping across the widest ground on the circuit, a gateway pair between.',
    theme: 'cinderyard',
    surface: 'sand',
    leagues: ['Iron'],
    w: FURNACEROW.w,
    h: FURNACEROW.h,
    obstacles: build(FURNACEROW.w, FURNACEROW.h, [
      // WARNING: THE COURT WENT BECAUSE ITS LANDMARK COULD NOT BE SEEN. A centred dais is
      // the textbook answer for a court, and at the old height it drew one unit tall on the
      // roomiest board in the league — a pale smudge on pale sand with four gateways
      // standing round nothing. The height is fixed, but a court needs its centre to be the
      // strongest thing in frame, and a low platform never will be.
      //
      // WARNING: SO THE PLATFORMS BECOME THE POINT INSTEAD OF THE SETTING. Two pairs
      // stepping diagonally across the widest ground in the league: cover you go round OR
      // stand on, at four different depths, so no two crossings are made at the same
      // height. It is the one arrangement that only works with a dais — which is the test
      // of whether a prop deserves to be in the game at all.
      // ⚠️ THE TWO PLATFORMS ARE NOT TWINS, and that is a correction the vocabulary tripwire
      // forced. Iron ran four boards on four footprints — every dais 12 x 2.4 or 14 x 2.8,
      // every gateway 5 x 5.6 — which is one step from the failure Gold shipped. A ten and a
      // thirteen on the roomiest board in the league costs nothing and stops the pair reading
      // as a stamp.
      { x: 15, y: 5, w: 13, h: 2.6, kind: 'dais' },
      { x: 17, y: 26, w: 10, h: 2.0, kind: 'dais' },
      { x: 18, y: 15.5, w: 5, h: 5.6, kind: 'gate' },
    ]),
  },
  {
    id: 'bronze-alloyfloor',
    name: 'The Alloy Floor',
    brief: 'CHICANE. Ruined casting walls staggered through the middle; a crucible in the gap.',
    theme: 'alloyfloor',
    leagues: ['Bronze'],
    w: ALLOYFLOOR.w,
    h: ALLOYFLOOR.h,
        // Bronze's bank is ten rows at tier 3 — 6.2 units — so the line stands further back
    obstacles: build(ALLOYFLOOR.w, ALLOYFLOOR.h, [
      // THE CLOISTER — wall runs at the four corners, one pier pair holding the middle.
      // ⚠️ SIX PIECES IS THE WHOLE ALLOWANCE on 1942 square units. Bronze inherits BOTH
      // parent leagues' prop lists, which makes it the league most likely to be over-filled
      // out of sheer availability — the density law is doing more work here than anywhere.
      { x: 14.7, y: 2.5, w: 11, h: 2.2, kind: 'wall' },
      { x: 14.7, y: 31.7, w: 11, h: 2.2, kind: 'wall' },
      { x: 20, y: 17.4, w: 1.6, h: 1.6, kind: 'pillar' },
    ]),
  },
  {
    id: 'bronze-bellpit',
    name: 'The Bell Pit',
    brief: 'COURT. A crucible on the pit floor, gravel banked into all four corners.',
    theme: 'bellyard',
    leagues: ['Bronze'],
    w: BELLPIT.w,
    h: BELLPIT.h,
        // Bronze's bank is ten rows at tier 3 — 6.2 units — so the line stands further back
    obstacles: build(BELLPIT.w, BELLPIT.h, [
      // THE WELL — the deepest Bronze board, walled at one end and piered at the other.
      // ⚠️ THE CENTRE IS LEFT EMPTY DELIBERATELY. On a board 44.8 deep a centred piece sits
      // ON the mirror axis and is the most symmetric shape available; the Smelt lost its
      // diagonal to exactly that. Everything here is a pair, offset in depth.
      { x: 12.5, y: 8, w: 1.6, h: 1.6, kind: 'pillar' },
      { x: 12.5, y: 16, w: 2.6, h: 3.15, kind: 'brokenpillar' },
      { x: 12.2, y: 28, w: 9, h: 2.7, kind: 'ruinedwall' },
    ]),
  },
  {
    id: 'bronze-longcast',
    name: 'The Long Cast',
    brief: 'SPINE. A wall down the middle of the casting run; the flanks are the way past.',
    theme: 'bellyard',
    surface: 'sand',   // a raked pit, the opposite of the Long Yard it inverts
    leagues: ['Bronze'],
    w: LONGCAST.w,
    h: LONGCAST.h,
        // Bronze's bank is ten rows at tier 3 — 6.2 units — so the line stands further back
    obstacles: build(LONGCAST.w, LONGCAST.h, [
      // THE CAUSEWAY — a wall the length of the middle third, piers to either side of it.
      // ⚠️ EXACTLY CENTRED, WHICH IS THE ONLY WAY TO GET A REAL SPINE. `build` mirrors, so
      // an off-centre piece becomes a PAIR with a hole between them; a centred one is its
      // own 180° partner and is emitted once.
      //
      // ⚠️ RUINED, NOT INTACT, AND THE REASON IS THE CAMERA. A clean wall run is one
      // unbroken bar — correct as a spine and the least interesting silhouette on the
      // ladder. A ruin has a torn top and tumbled blocks at its foot, so it carries the eye
      // along its length; the Slag Yard reads best of Bronze's four precisely because
      // nothing on it is intact. Ruins out-read intact stone at this distance.
      //
      // ⚠️ THREE PIECES RATHER THAN ONE, BECAUSE A RUIN CANNOT BE SIXTEEN UNITS LONG. Its
      // sprite is 3.32:1, so at 16 wide it would draw 4.8 tall against a 3.4 ceiling — the
      // envelope rule, and it bites here. Eleven is the honest maximum, so the causeway is
      // built as a collapsed run: a centred span and a mirrored pair almost touching it,
      // 33 units of broken wall across a 70-unit board.
      { x: (LONGCAST.w - 11) / 2, y: (LONGCAST.h - 3.3) / 2, w: 11, h: 3.3, kind: 'ruinedwall' },
      { x: 18.5, y: (LONGCAST.h - 3.3) / 2, w: 11, h: 3.3, kind: 'ruinedwall' },
      { x: 19.5, y: 4, w: 1.6, h: 1.6, kind: 'pillar' },
      { x: 19.5, y: 22.4, w: 1.6, h: 1.6, kind: 'pillar' },
    ]),
  },
  {
    id: 'bronze-slagyard',
    name: 'The Slag Yard',
    brief: 'ECHELON. Two long slag banks set diagonally, a broken pillar where they cross.',
    theme: 'alloyfloor',
    surface: 'packedearth',   // trodden yard, and it keeps Bronze from being all one floor
    leagues: ['Bronze'],
    w: SLAGYARD.w,
    h: SLAGYARD.h,
        // Bronze's bank is ten rows at tier 3 — 6.2 units — so the line stands further back
    obstacles: build(SLAGYARD.w, SLAGYARD.h, [
      // THE RUIN FIELD — nothing intact on this one, which is what makes it Bronze's own.
      // ⚠️ AND THE HEAPS ARE GONE FROM THE LAST BOARD THAT HAD THEM. `orepile` and
      // `slagheap` build from one flattened sphere with rubble stuck to it and read as a
      // blob at every size; this board was the clearest case, with four of them on the
      // widest ground in the league and not one fully blocking anything.
      { x: 16.5, y: 3, w: 11, h: 3.3, kind: 'ruinedwall' },
      { x: 16.5, y: 25.9, w: 11, h: 3.3, kind: 'ruinedwall' },
      { x: 18, y: 14, w: 2.6, h: 3.15, kind: 'brokenpillar' },
    ]),
  },
  {
    id: 'tin-washpool',
    // ⚠️ ITS OWN FLOOR, BECAUSE THE LEATS HAS THE LEAGUE'S. Tin was the only league running
    // two boards on one ground — `streamworks` twice — which is the thing `surface` exists
    // to prevent. Silt is also the truer floor for a court nobody has washed ore on in
    // years: the water that kept the stone clean stopped running.
    name: 'The Wash Pool',
    brief: 'CHICANE. An abandoned pool gone to ivy — four overgrown walls weave the deepest board in the game.',
    theme: 'streamworks',
    surface: 'packedearth',
    leagues: ['Tin'],
    w: WASHPOOL_W,
    h: WASHPOOL_H,
    obstacles: build(WASHPOOL_W, WASHPOOL_H, [
      // ⚠️ A RUINED COURT, NOT A YARD WITH THINGS IN IT. This is the cup that is not about
      // the metal: a colonnaded wash court nobody has worked in years, its roof gone, its
      // dividing wall broken and ivy over everything. Every piece here is part of the same
      // building, which is the whole difference from four objects on a floor.
      //
      // ⚠️ THE WEAVE IS IN DEPTH, THE ONLY AXIS THIS BOARD HAS TO SPARE. Every long prop's
      // footprint runs along X, so a piece here is a bar you cross ABOVE or BELOW rather
      // than a post you go round. On 42.7 of depth — the deepest board in the game — pieces
      // at staggered depths give a genuine weave: the lane clear at one depth is shut at
      // the next.
      { x: 11.8, y: 9, w: 8.5, h: 2.35, kind: 'vinewall' },
      // ⚠️ THE STANDING PIER PAIR CAME OUT UNDER THE DENSITY LAW. Eight pieces on 1760
      // square units against an allowance of six — and of the three pairs, an INTACT pier
      // was the one that least belonged on a court whose whole subject is that it has been
      // abandoned. The broken one stays.
      { x: 13.6, y: 24.5, w: 2.6, h: 3.15, kind: 'brokenpillar' },
      // The channel that fed the court, still running along the foot of it.
      { x: 11.8, y: 39.5, w: 8.5, h: 1.3, kind: 'leat' },
    ]),
  },
  {
    id: 'tin-leats',
    name: 'The Leats',
    brief: 'SPINE. Twenty units of channel down the centre line, an ore bin at each far shoulder.',
    theme: 'streamworks',
    leagues: ['Tin'],
    w: LEATS_W,
    h: LEATS_H,
    obstacles: build(LEATS_W, LEATS_H, [
      // ⚠️ AN AQUEDUCT HALL, WHICH IS WHAT A LEAT ACTUALLY NEEDS. Twenty units of channel
      // down the centre line was already the signature of this board; standing four piers
      // at the quarters makes it a STRUCTURE the channel runs through rather than a trough
      // lying on a floor. A leat draws 6.4x wider than tall, so it is the only prop in the
      // game that can hold a span this long without towering over the monsters beside it.
      { x: (LEATS_W - 20) / 2, y: (LEATS_H - 3.1) / 2, w: 20, h: 3.1, kind: 'leat' },
      // ⚠️ TWO AUTHORED PIERS BECOME FOUR, one to each quarter. Authored level they would
      // land as a mirrored pair either side of the axis — the Smelt's lesson — so they are
      // offset in depth and the mirror does the rest.
      { x: 16.2, y: 4.6, w: 1.6, h: 1.6, kind: 'pillar' },
      { x: 16.2, y: 23.8, w: 1.6, h: 1.6, kind: 'pillar' },
    ]),
  },
  {
    id: 'tin-blowinghouse',
    name: 'The Blowing House',
    brief: 'REDOUBT. A furnace, a block wall and an anvil to each side — the working floor of a smithy.',
    theme: 'blowinghouse',
    surface: 'flagstone',   // flagged, because a blowing house floor is swept
    leagues: ['Tin'],
    w: BLOWING_W,
    h: BLOWING_H,
    obstacles: build(BLOWING_W, BLOWING_H, [
      // ⚠️ THE HALL THE FURNACES STAND IN, rather than furnaces standing in the open. Two
      // long wall runs give the widest board in the league the one thing it never had — a
      // built edge to fight along — and the furnace stops being an object on a floor
      // because it now has a wall to be against.
      { x: 17.6, y: 3, w: 14, h: 2.8, kind: 'wall' },
      // ⚠️ AND NOT ONE TRADE PIECE EITHER. A furnace pair was kept here on the argument
      // that it is the only genuinely upright thing Tin owns and gave the board something
      // to hold — but a smelting furnace standing on a swept fighting floor is precisely
      // the "objects someone left out" read that moved these arenas onto architecture in
      // the first place. The wall runs and the piers already give the hall its shape; the
      // furnace was only earning its place by being tall, and a pier does that honestly.
      { x: 30, y: 24, w: 1.6, h: 1.6, kind: 'pillar' },
    ]),
  },
  {
    id: 'copper-washfloor',
    name: 'The Washfloor',
    brief: 'FLANKS. Channels down both long edges, a thicket islanded in the middle.',
    theme: 'washfloor',
    leagues: ['Copper'],
    w: WASHFLOOR_W,
    h: WASHFLOOR_H,
    obstacles: build(WASHFLOOR_W, WASHFLOOR_H, [
      // THE CANAL COURT — water instead of cover, and four piers to hold the court.
      // ⚠️ A CHANNEL IS AN OBSTACLE THAT IS NOT A WALL, which is the point of building a
      // board around one. It divides the floor without hiding anything on the far side of
      // it, so the fight stays legible while the route does not. See ARENA_DESIGN.md §2 —
      // moats and canals are a listed theme precisely because they do this.
      { x: (WASHFLOOR_W - 16) / 2, y: (WASHFLOOR_H - 2.9) / 2, w: 16, h: 2.9, kind: 'sluice' },
      // ⚠️ TWO AUTHORED PIERS BECOME FOUR, one to each quarter — and they are offset in
      // depth rather than level, so the mirror does not land them as a facing pair.
      { x: 13.6, y: 4, w: 1.6, h: 1.6, kind: 'pillar' },
      { x: 13.6, y: 26.6, w: 1.6, h: 1.6, kind: 'pillar' },
    ]),
  },
  {
    id: 'copper-ingotyard',
    name: 'The Ingot Yard',
    brief: 'COURT. A crucible mid-yard with two ingot rows set against it, and room all round.',
    // ⚠️ SMELT YARD, NOT THE WASHFLOOR — caught by `mapProblems`, which refused a
    // crucible on a theme that has no sprite for one. That is the check doing its
    // job as a DESIGN question, not a typo check: ore is washed on wet stone and
    // metal is cast over soot, so an ingot yard belongs on the smelting ground.
    theme: 'smeltyard',
    surface: 'concrete',   // a casting floor is poured, not trodden
    leagues: ['Copper'],
    w: INGOTYARD_W,
    h: INGOTYARD_H,
    obstacles: build(INGOTYARD_W, INGOTYARD_H, [
      // THE RUINED COURT — the cramped board, so the pieces are broken ones.
      // ⚠️ AN AUTHORED PIECE HERE MAY BE 8.2 UNITS WIDE AND NO MORE, the tightest window in
      // the game: the deployment bands take 10.8 either side of a 38.8 board and a piece
      // must also stay left of centre, leaving 11.2-19.4 to work in.
      { x: 11.2, y: 6, w: 8, h: 2.4, kind: 'ruinedwall' },
      { x: 11.5, y: 22, w: 2.6, h: 3.15, kind: 'brokenpillar' },
    ]),
  },
  {
    id: 'copper-smelt',
    name: 'The Smelt',
    brief: 'ECHELON. Two long ingot rows diagonally opposed, a crucible at each near shoulder.',
    theme: 'smeltyard',
    leagues: ['Copper'],
    w: SMELT_W,
    h: SMELT_H,
    obstacles: build(SMELT_W, SMELT_H, [
      // THE COLONNADE — two long wall runs and a pier apiece, diagonally opposed.
      // ⚠️ NOTHING ON THE CENTRE LINE, DELIBERATELY. A centred piece sits ON the mirror
      // axis and is the most symmetric shape a board can make; an ore pile there once
      // flattened the very diagonal this arrangement exists for. Four pieces, no axis
      // through the middle, and the crossing is the decision.
      // ⚠️ IT MATCHED TIN'S BLOWING HOUSE EXACTLY — same piece count, same bar count, same
      // spread — across a league boundary. Two circuits are never seen side by side, which
      // is precisely why nobody would have noticed; a board repeated a league later is still
      // a board that did not need authoring.
      { x: 16.4, y: 1.5, w: 13, h: 2.6, kind: 'wall' },
      { x: 20, y: 12, w: 1.6, h: 1.6, kind: 'pillar' },
      { x: 26, y: 6, w: 2.6, h: 3.15, kind: 'brokenpillar' },
    ]),
  },
  {
    id: 'wood-longyard',
    name: 'The Long Yard',
    brief: 'FLANKS. Drystone runs fence the first third of both edges; the middle run is bare.',
    theme: 'timberyard',
    surface: 'packedearth',   // the long approach reads as an open trodden run
    leagues: ['Wood'],
    w: LONGYARD_W,
    h: LONGYARD_H,
    obstacles: build(LONGYARD_W, LONGYARD_H, [
      // THE DRYSTONE RUN — a fenced lane, and nothing else on it.
      // ⚠️ FOUR PIECES IS THE WHOLE ALLOWANCE HERE: 1263 square units at one piece per 300.
      // The board carried six before the density law and read as busy on the smallest
      // ground in the game. Two authored walls become four, and four is the ceiling.
      // ⚠️ STONE AT WOOD IS NOT A CONTRADICTION. `venue.masonry` at tier 0 is rough grey
      // coursing, not dressed ashlar — a drystone field wall, which is what a village
      // ground would actually be fenced with. The league still reads timber from the
      // stands, the packed-earth floor and the lamp.
      { x: 15.9, y: 0.6, w: 12.5, h: 2.5, kind: 'wall' },
      { x: 15.9, y: 18.6, w: 12.5, h: 2.5, kind: 'wall' },
    ]),
  },
  {
    id: 'wood-timberyard',
    name: 'The Timberyard',
    brief: 'SPINE. One long drystone run dead centre makes two real lanes; a post anchors each near corner.',
    theme: 'timberyard',
    leagues: ['Wood'],
    w: TIMBERYARD_W,
    h: TIMBERYARD_H,
    obstacles: build(TIMBERYARD_W, TIMBERYARD_H, [
      // THE GATE RUN — one long wall down the middle, a pier at each near corner.
      // ⚠️ CENTRED BY ARITHMETIC, NOT BY A TYPED-IN NUMBER. A centred piece is its own 180°
      // twin ONLY while it sits exactly at the middle; the stump this replaced was
      // hand-placed for a 36x20 field, and sizing arenas from whole hexes moved the field
      // until it stopped self-twinning and `mirror()` emitted a second copy on top of it.
      { x: (TIMBERYARD_W - 14) / 2, y: (TIMBERYARD_H - 2.8) / 2, w: 14, h: 2.8, kind: 'wall' },
      // ⚠️ A PIER, NOT A STUMP. Both are things to fight beside; only one of them belongs
      // to the building the wall is part of. See docs/ARENA_DESIGN.md §2.
      { x: 15.2, y: 3, w: 1.6, h: 1.6, kind: 'pillar' },
    ]),
  },
  {
    id: 'dustbowl',
    name: 'Dustbowl',
    brief: 'Small, open, almost no cover — the control map. Melee should thrive.',
    theme: 'proving',
    leagues: [],
    w: DUSTBOWL_W,
    h: DUSTBOWL_H,
    obstacles: build(DUSTBOWL_W, DUSTBOWL_H, [
      { x: 15, y: 3.5, w: 2, h: 2 },
      { x: 8, y: 9.2, w: 1.6, h: 1.6 },
    ]),
  },
  {
    id: 'ossuary',
    name: 'The Ossuary',
    brief: 'Long transverse walls and a centre choke. Lanes, not a straight charge.',
    theme: 'proving',
    leagues: [],
    w: OSSUARY_W,
    h: OSSUARY_H,
    obstacles: build(OSSUARY_W, OSSUARY_H, [
      { x: 13, y: 6.5, w: 12, h: 1.4 }, // the long wall; its twin sits diagonally opposite
      { x: 23, y: 11.5, w: 2, h: 3 }, // dead centre — its own twin, emitted once
      { x: 5.5, y: 12.2, w: 1.8, h: 1.8 },
    ]),
  },
  {
    // ⚠️ THIS MAP NO LONGER FAILS — AND THE NOTE BELOW IS KEPT AS HISTORY, NOT AS
    // FACT. It read "does not resolve — 0/40, every fight to sudden death, 72.9s
    // mean". As of 2026-08-01 `mapsweep` reports **40/40 at 25.3s**. Nothing was
    // done to the map; the engine changed underneath it (the retreat/grind-lock
    // fixes and the flat-guard cap). The regression case it was kept for has been
    // paid off, which is the outcome the note was hoping for — but a ⚠️ stating a
    // refuted number is worse than no note, so read the paragraph below as the
    // ORIGINAL diagnosis and the reason the map's geometry is shaped as it is.
    //
    // ⚠️ AND IT IS NOT THE MASSIF, WHICH IS THE OPPOSITE OF WHAT IT LOOKS LIKE.
    // Held at 64x34 with cover as the only variable:
    //     bare (no cover)            0.0% cover   20/20   19.7s
    //     massif only (the 8x8)      2.9% cover   20/20   19.8s   <- harmless
    //     rubble only (no massif)    2.7% cover    0/20   72.5s   <- the cause
    //     full map                   5.6% cover    0/20   72.5s
    // The huge block behaves exactly like an empty field: it is too big to
    // circle, so a unit rounds it once and commits. The SMALL scattered blocks
    // are the killer — each one is a cheap way to break line of sight without
    // leaving the fight, so a shooter steps, re-acquires, loses sight again, and
    // the exchange never closes. Field SIZE was separately measured null (sign
    // test p=0.43 at 1.5x, p=0.64 at 2x), so this is cover GEOMETRY alone.
    //
    // Do not "fix" it by deleting the rubble. Fix target selection (P6) and let
    // this map tell you when it works.
    id: 'titans-rest',
    name: "Titan's Rest",
    brief: 'Large, long approach, one huge central massif. Hard cover and flanks.',
    theme: 'proving',
    leagues: [],
    w: TITAN_W,
    h: TITAN_H,
    obstacles: build(TITAN_W, TITAN_H, [
      { x: 28, y: 13, w: 8, h: 8 }, // the massif — centred, emitted once
      { x: 16, y: 6.5, w: 3.5, h: 3.5 },
      { x: 16, y: 24, w: 3.5, h: 3.5 },
      { x: 9, y: 16, w: 2.2, h: 2.2 },
    ]),
  },
]

export const mapById = (id: string): ArenaMap | undefined => MAPS.find((m) => m.id === id)

/**
 * The grid an arena should be built on, for the team size it will host.
 *
 * ⚠️ ARENA SIZE WAS UNCORRELATED WITH TEAM SIZE, AND POINTING THE WRONG WAY. Measured
 * across the ten authored arenas, a Wood 1v1 gets 48–68 cells per monster and a Tin 2v2
 * gets 42–48 — `wood-timberyard` is the roomiest board in the game per body, for a
 * duel. Nothing enforced anything; each arena's size came from whatever shape it wanted
 * to be. With 3v3 through 5v5 leagues entirely unauthored, that is ~41 boards about to
 * be sized by feel, so the rule goes in first.
 *
 * ⚠️ IT GROWS ON BOTH AXES, AND AN EARLIER VERSION OF THIS RULE GREW ONLY IN DEPTH.
 * That version was right about the tactics and wrong about the camera, which is a
 * mistake you cannot make on a spreadsheet — it took rendering a 5v5 to see it:
 *   • DEPTH is where a team SPREADS. Both deploy zones are `DEPLOY_COLS` columns against
 *     the LEFT and RIGHT walls, so rows are what let five monsters stand abreast.
 *   • BUT DEPTH IS ALSO THE AXIS RUNNING INTO THE SCREEN. The camera looks down it, so a
 *     line spread across 30 rows has its far monster tiny, its near one huge, and the
 *     middle three occluding each other — the formation the depth was bought for becomes
 *     the formation you cannot read. At 18x30 the board rendered as a corridor.
 *   • AND DEPTH SATURATES ANYWAY. Five monsters need about 12 world units of rank to
 *     stand clear; the Wood board already has 17.5. Rows past ~20 buy no formation at
 *     all, only empty lateral ground and screen compression.
 *   • WIDTH is approach time — real, and worth paying for once depth has saturated.
 *     `docs/BALANCING.md` clocks the Smelt (43.65 wide) at 4.2s to contact; a 5v5 at
 *     58.2 is about 5.6s, out of a fight with ten bodies in it.
 * So columns go 12 → 24 (2x) and rows 8 → 20 (2.5x), and every board stays wider than it
 * is deep — which is also the only shape that fills a 16:9 frame.
 *
 * ⚠️ 5v5 BREAKS THE SMOOTH RAMP ON PURPOSE, AND IT IS THE ONLY ROW THAT DOES. Density
 * runs 48 / 35 / 33 / 32 cells per body for 1v1 through 4v4 — and then 5v5 jumps back to
 * 54. Two reasons, and neither is that the curve looked untidy:
 *   • PLATINUM, MASTERS, TAMER ELITE AND TAMERS APEX ALL FIELD FIVE. `town.ts` flags
 *     that plateau itself as "a real loss of a progression axis... worth replacing with
 *     something at the summit". Venue SCALE is one of the few axes left: the same ten
 *     monsters on a markedly grander ground is what makes the top of the ladder read as
 *     the top, when team size has stopped saying it.
 *   • TEN BODIES IS WHERE FORMATION STOPS FITTING. At 4v4's density a 5v5 has its two
 *     lines inside each other's reach from the opening tick, so front/back and flank
 *     mean nothing — the fight is a scrum by construction rather than by choice.
 *
 * ⚠️ AND THE WIDTH IS PINNED TO A MEASURED NUMBER, NOT CHOSEN. 18 columns is 43.6 world
 * units, which is the Smelt's width to within a hair — a board BALANCING.md already
 * clocks at 4.2s to contact. So the whole increase lands in depth and the approach stays
 * a quantity we have measured rather than one we guessed. Growing the width instead
 * would have bought 5v5 nothing but a longer walk.
 *
 * ⚠️ 1v1 IS DELIBERATELY THE ROOMIEST PER BODY. A duel is the one fight that is
 * genuinely about kiting and reach, and two monsters on a board sized at the team rate
 * would be nose to nose from the first tick. Everything from 2v2 up holds ~32–35 cells
 * per monster, which is the density the existing Copper and Tin boards already play at.
 */
export function arenaGridFor(teamSize: number): { cols: number; rows: number; cells: number } {
  const table: Record<number, [number, number]> = {
    1: [17, 11], 2: [20, 14], 3: [22, 17], 4: [28, 22], 5: [34, 28], 6: [36, 31],
  }
  const [cols, rows] = table[Math.max(1, Math.min(6, Math.round(teamSize)))] ?? table[3]
  return { cols, rows, cells: cols * rows }
}

/**
 * How far an arena may stray from that target and still be legitimate.
 *
 * ⚠️ A WIDE BAND ON PURPOSE, BECAUSE SHAPE VARIETY IS A FEATURE. The Smelt is long and
 * shallow, the Wash Pool is square and deep, and both are the same league — collapsing
 * every board onto one size would throw that away to satisfy a number. What the guard is
 * actually for is the failure that matters: a five-a-side fight on a board built for a
 * duel, where there is nowhere to deploy and nothing to do but collide.
 */
export const ARENA_CELLS_MIN = 0.78
export const ARENA_CELLS_MAX = 1.55

/**
 * How many arenas each league should end up with.
 *
 * ⚠️ WOOD 2 AND GOLD-ONWARDS 6 ARE SPECIFIED; THE MIDDLE IS A PROPOSAL. It ramps
 * with team size and prestige — Wood is 1v1 on borrowed ground, Gold is 4v4 on a
 * real circuit, and the number of grounds a circuit keeps should read that way.
 * Change the middle rows freely; they are a design call, not a constraint.
 *
 * ⚠️ THIS IS A TARGET, NOT A GATE. `validate.ts` only complains about a league that
 * has SOME arenas but fewer than it wants — a league at zero is "not authored yet"
 * and is expected during the rollout, while a league stuck at 3 of 6 is a job
 * someone abandoned half-done and is exactly what goes unnoticed.
 */
export const ARENAS_WANTED: Record<string, number> = {
  // ⚠️ 2, AND IT WENT 4 → 3 → 2 ACROSS ONE DAY (2026-08-02) — every step a design call, not
  // a tripwire being wrong, which is the whole reason this number is asserted at all.
  // Wood is the league a player passes through fastest and it has the smallest prop
  // vocabulary in the game, so each extra board was another arrangement of the same four
  // objects rather than another place. Two that each say something beats four where two
  // are filler.
  // ⚠️ WHAT THE CUTS COST, WRITTEN DOWN SO IT IS A CHOICE AND NOT AN ACCIDENT: Wood no
  // longer has a near-SQUARE board (the Sawpit, 1.21) — its two run 2.68 and 1.82, both
  // wide — and it no longer uses the CHICANE arrangement or the `timber` surface or the
  // `plankyard` theme at all. Those are still authored and cost nothing to sit idle; if
  // Wood ever wants a third, the square is the shape that is missing.
  Wood: 2,
  Copper: 3, Tin: 3,
  Bronze: 4, Iron: 4,
  Silver: 5,
  Gold: 6,
  // ⚠️ THE TOP FOUR SHARE ONE POOL OF TWENTY, WHICH IS WHY THEY ALL SAY 20. Every league
  // below builds its own boards because its MATERIAL is its name — Wood is timber, Iron is
  // forge scale, and a Wood board on the Iron circuit would be a category error. From
  // Platinum up the team size stops growing (five, all the way to Apex) and the boards stop
  // belonging to a league at all: `arenasForLeague` filters on `leagues.includes`, so one
  // ground listing all four appears in all four pools.
  // ⚠️ AND THE LADDER IS CARRIED BY THE STADIUM INSTEAD. Platinum gains arches and a canopy,
  // Masters an entablature and statues, Tamer Elite turrets and a mosaic, Apex the victory
  // arch — four visibly different occasions on the same twenty grounds. That is the whole
  // reason the venue was built as a separate layer from the arena.
  // ⚠️ THIS NUMBER CLIMBS 5 -> 10 -> 15 -> 20 AS THE BLOCKS LAND, and it is deliberately
  // NOT set to the final 20 up front. `validate.ts` flags any league that has SOME arenas
  // but fewer than it wants, so parking it at 20 during the rollout makes the suite red for
  // three blocks — and a red suite is a suite nobody reads. The count means "how many this
  // league draws from TODAY, and must not silently lose"; the design target of twenty is in
  // the header above, where a number cannot rot into a false pass.
  Platinum: 16, Masters: 16, 'Tamer Elite': 16, 'Tamers Apex': 16,
}

/** Every arena a league draws from. */
export const arenasForLeague = (league: string): ArenaMap[] =>
  MAPS.filter((m) => m.leagues.includes(league))

/**
 * Which arena a given fight is played on.
 *
 * ⚠️ SEEDED FROM THE FIGHT, NOT RANDOM. The whole engine is deterministic — the
 * same seed must reproduce the same battle byte for byte, and an arena chosen with
 * `Math.random()` would break that at the first thing that matters. It also means a
 * scouted cup shows the ground it will actually be fought on.
 *
 * ⚠️ Returns null rather than a default when a league has no arenas yet. A silent
 * fallback to some other league's ground is precisely how content stays missing
 * without anyone noticing; `validate.ts` asserts the pools are non-empty instead.
 */
export function arenaFor(league: string, seed: string): ArenaMap | null {
  const pool = arenasForLeague(league)
  if (!pool.length) return null
  let h = 2166136261
  for (let i = 0; i < seed.length; i++) { h ^= seed.charCodeAt(i); h = Math.imul(h, 16777619) }
  return pool[Math.abs(h) % pool.length]
}

/**
 * Problems with an arena's geometry, for `validate.ts` and the map tests.
 * Checks what `mirror()` cannot: blocks inside the field, blocks not overlapping
 * each other, symmetry surviving any later hand edit, and a deployment band that
 * is not so blocked a team cannot seat in it.
 */
/**
 * Team size per league, duplicated here on purpose.
 *
 * ⚠️ `maps.ts` MUST NOT IMPORT `town.ts`. town pulls in the whole game state — market,
 * breeding, the tournament calendar — and the arena table is read by the renderer, the
 * preview tools and the sim harnesses, none of which should drag that in. The list is
 * six entries and `validate.ts` asserts it against the real one, so it cannot drift.
 */
const LEAGUE_TEAM: Record<string, number> = {
  Wood: 1, Copper: 2, Tin: 2, Bronze: 3, Iron: 3, Silver: 4, Gold: 4,
  Platinum: 5, Masters: 5, 'Tamer Elite': 5, 'Tamers Apex': 5,
}
const teamSizeForLeagueLocal = (lg: string): number => LEAGUE_TEAM[lg] ?? 1
export const ARENA_LEAGUE_TEAM = LEAGUE_TEAM

/**
 * Square units of floor each piece of cover is allowed.
 *
 * ⚠️ 300 IS MEASURED OFF THE BOARDS THAT PASSED REVIEW, not chosen for roundness. The three
 * Tin halls that were signed off sit at 350-490 square units per piece; the two boards that
 * drew "cluttered" sat at 210-220. 300 puts the ceiling between them, which is what a
 * threshold is for.
 */
export const AREA_PER_PIECE = 300

/** The most cover a board of this area may carry. Never fewer than two. */
export const maxPiecesFor = (area: number): number =>
  Math.max(2, Math.round(area / AREA_PER_PIECE))

/**
 * A reference piece, in square units — what "one piece" means to the density law.
 *
 * ⚠️ THE LAW COUNTED HEADS AND WAS BLIND TO SIZE, WHICH WAS FLAGGED AT SILVER AND IS BEING
 * FIXED HERE. `AREA_PER_PIECE` was measured off the Tin and Bronze boards that passed
 * review, and everything on those is a 10-to-14 unit wall — so the number encodes "one wall
 * per 300 square units" while the code reads "one OBJECT per 300". A 1.6-unit topiary is a
 * fifteenth of a wall's footprint and was costing the same allowance, which made a thicket
 * of standards illegal and a row of walls fine even though the thicket is plainly the
 * emptier board.
 * ⚠️ IT ALSO LET SILVER SHIP AT 0.79%% COVER. Ten columns "filled" a 3100-unit ground under
 * the old rule; weighted, they spend a third of the allowance and the shortfall is visible
 * in the number rather than only in the render.
 */
export const REFERENCE_PIECE = 12

/**
 * What one obstacle costs against `maxPiecesFor`.
 *
 * ⚠️ FLOORED AT 0.3, NOT AT ZERO. Weighting purely by area would make small pieces free and
 * a board could ship fifty urns — and fifty of anything is clutter however small each one
 * is, because the cost the law is really policing is how many separate things the eye has
 * to parse. Capped at 1.0 for the same reason in reverse: a very long run is one decision,
 * not two, so it must not cost double and quietly ban the boards built out of them.
 */
export const pieceCost = (o: { w: number; h: number }): number =>
  Math.max(0.3, Math.min(1, (o.w * o.h) / REFERENCE_PIECE))

export function mapProblems(m: ArenaMap): string[] {
  const out: string[] = []

  // ⚠️ AN ARENA TOO SMALL FOR ITS LEAGUE'S TEAM SIZE IS THE ONE THAT MATTERS. Five a
  // side on a board built for a duel has nowhere to deploy and nothing to do but
  // collide — no formation, no flanking, no reason for cover to exist. Size was
  // uncorrelated with team size until this guard, and with 3v3 through 5v5 entirely
  // unauthored the mistake was about to be made forty times.
  // ⚠️ THE UPPER BOUND IS LOOSE AND THE LOWER ONE IS NOT. Being roomy costs approach
  // time and nothing else; being cramped costs the whole tactical layer.
  for (const lg of m.leagues ?? []) {
    const want = arenaGridFor(teamSizeForLeagueLocal(lg))
    const cells = Math.round((m.w / HEX_W) * (m.h / HEX_ROW))
    if (cells < want.cells * ARENA_CELLS_MIN) {
      out.push(`${m.id}: ${cells} cells is too small for ${lg}'s ${teamSizeForLeagueLocal(lg)}v`
        + `${teamSizeForLeagueLocal(lg)} — wants about ${want.cols}x${want.rows} (${want.cells})`)
    } else if (cells > want.cells * ARENA_CELLS_MAX) {
      out.push(`${m.id}: ${cells} cells is far larger than ${lg} needs (~${want.cells}) — `
        + 'every extra column is approach time before anything happens')
    }
  }

  // ⚠️ A THEME TYPO MUST NOT BE SURVIVABLE. `themeById` falls back to the plain
  // proving-ground art so a half-authored arena still renders — which is right for
  // the renderer and wrong for the author, who would ship a league arena wearing
  // test-fixture grass and never see an error.
  if (!THEMES[m.theme]) out.push(`${m.id}: unknown theme '${m.theme}'`)

  // ⚠️ Cover must be built from KINDS THE THEME DRAWS. Otherwise the prop silently
  // falls back to a boulder and a timber yard grows rocks.
  const theme = THEMES[m.theme]
  if (theme) {
    for (const o of m.obstacles) {
      if (o.kind && !theme.props[o.kind]) {
        out.push(`${m.id}: theme '${m.theme}' has no sprite for '${o.kind}' — it will draw as a boulder`)
      }
    }
  }

  for (const [i, o] of m.obstacles.entries()) {
    if (o.x < 0 || o.y < 0 || o.x + o.w > m.w || o.y + o.h > m.h) {
      out.push(`${m.id}: obstacle ${i} (${o.x},${o.y} ${o.w}x${o.h}) falls outside the field`)
    }
    for (const [j, p] of m.obstacles.entries()) {
      if (j <= i) continue
      const overlap = o.x < p.x + p.w && p.x < o.x + o.w && o.y < p.y + p.h && p.y < o.y + o.h
      if (overlap) out.push(`${m.id}: obstacles ${i} and ${j} overlap`)
    }
  }

  // ⚠️ SCENERY LIVES OFF THE PITCH, AND ONLY THIS CHECK KEEPS IT THERE. A decorative
  // tree inside the field is cover the player can see and the engine cannot path around —
  // the most confusing thing an arena can do, and the exact failure this list exists to
  // make impossible. Overlapping the boundary counts as inside.
  for (const [i, o] of (m.scenery ?? []).entries()) {
    const inside = o.x + o.w > 0 && o.x < m.w && o.y + o.h > 0 && o.y < m.h
    if (inside) {
      out.push(`${m.id}: scenery ${i} (${o.kind}) at (${o.x.toFixed(1)},${o.y.toFixed(1)}) `
        + 'overlaps the playing field — scenery is dressing and is never collided with')
    }
  }

  // The symmetry `mirror()` guarantees — asserted anyway, because a later hand
  // edit to the emitted array would not go through the helper.
  for (const o of m.obstacles) {
    const twin = { x: m.w - o.x - o.w, y: m.h - o.y - o.h, w: o.w, h: o.h }
    const found = m.obstacles.some(
      (p) => Math.abs(p.x - twin.x) < 1e-6 && Math.abs(p.y - twin.y) < 1e-6
        && Math.abs(p.w - twin.w) < 1e-6 && Math.abs(p.h - twin.h) < 1e-6,
    )
    if (!found) out.push(`${m.id}: obstacle at (${o.x},${o.y}) has no 180° partner — the map favours a side`)
  }

  // ⚠️ NOTHING MAY STAND IN A DEPLOYMENT BAND. FULL STOP (2026-08-02, user rule).
  //
  // ⚠️ AND THIS DELIBERATELY REVERSES WHAT THIS GUARD USED TO SAY, so the reasoning it
  // replaces is kept rather than deleted: the old rule allowed up to 15% of a band to be
  // blocked, on the grounds that cover near your own spawn is a design CHOICE (a caster
  // breaking sight from the start line) and that `mirror()` already guarantees both sides
  // get exactly the same of it, so there is no bias to catch. That argument is still
  // sound about FAIRNESS. It is not about READABILITY, which is what changed the call: a
  // monster seated on top of a stump reads as clipping, and a start line you cannot see
  // the whole of is a worse trade than a piece of cover you cannot have.
  //
  // ⚠️ ALL TWELVE LEAGUE BOARDS FAILED THIS THE MOMENT IT WAS WRITTEN, which is a fact
  // about the BAND and not about the layouts. `hex.ts:zoneFor` sizes it `0.24w + 1.5` —
  // off the board's WIDTH, with no idea how many monsters have to stand in it — so after
  // the boards grew, a single Wood monster gets a 15.5-unit spawn zone while three Bronze
  // ones share 14.3. The bands now eat 52-56% of every board and the legal strip for
  // cover is the ~45% in the middle. Sizing the band off the TEAM is the real fix and it
  // moves auto-deploy, so it is a separate, measured decision.
  // ⚠️ THE DENSITY LAW: ONE PIECE PER `AREA_PER_PIECE` SQUARE UNITS, AND IT IS A HARD
  // CEILING (2026-08-02, user rule). "Cluttered" was the single most repeated note across
  // four leagues of review, and every time it was answered by hand — trim two here, drop a
  // pair there — it came back on the next board, because nothing stopped the next author
  // from filling the floor again. A number that fails the suite does.
  //
  // ⚠️ AREA, NOT PIECE COUNT, AND NOT TEAM SIZE. A flat cap would make the 1263-unit Long
  // Yard and the 1971-unit Blowing House equally busy, which is exactly the mistake. Team
  // size already drives area through `arenaGridFor`, so measuring against area picks that
  // up for free and stays right for the 4v4 and 5v5 boards nobody has authored yet.
  //
  // ⚠️ AND IT COUNTS EMITTED PIECES, NOT AUTHORED ONES. `build` mirrors, so an author
  // typing three obstacles ships six; the player sees six, and six is what "cluttered"
  // means. Judging the authored list would let the rule be doubled by construction.
  for (const lg of m.leagues ?? []) {
    void lg
    const max = maxPiecesFor(m.w * m.h)
    // ⚠️ WEIGHTED BY FOOTPRINT — see `pieceCost`. Counting heads made a thicket of standards
    // illegal and a row of walls legal on the same ground, which is backwards.
    const spend = m.obstacles.reduce((t, o) => t + pieceCost(o), 0)
    if (spend > max + 1e-9) {
      out.push(`${m.id}: ${m.obstacles.length} pieces costing ${spend.toFixed(1)} on `
        + `${Math.round(m.w * m.h)} square `
        + `units — the density law allows ${max}. Cover must be FEW and LARGE; see `
        + 'docs/ARENA_DESIGN.md')
    }
    break
  }

  //
  // ⚠️ SHIPPED CONTENT ONLY. The three original boards are MEASUREMENT FIXTURES whose
  // numbers are quoted in this file and in `docs/BALANCING.md` — Titan's Rest is the whole
  // evidence for "small blocks stall a fight and big ones do not". Moving their rubble to
  // satisfy a presentation rule would invalidate every figure taken on them, silently.
  const band = m.w * 0.24 + 1.5 // mirrors hex.ts:zoneFor
  for (const [i, o] of (m.leagues.length ? m.obstacles : []).entries()) {
    if (o.x < band) {
      out.push(`${m.id}: obstacle ${i} (${o.kind}) reaches x=${o.x.toFixed(1)} inside side `
        + `A's deployment band (0-${band.toFixed(1)}) — nothing may stand where a team seats`)
    } else if (o.x + o.w > m.w - band) {
      out.push(`${m.id}: obstacle ${i} (${o.kind}) reaches x=${(o.x + o.w).toFixed(1)} inside `
        + `side B's deployment band (${(m.w - band).toFixed(1)}-${m.w.toFixed(1)}) — nothing `
        + 'may stand where a team seats')
    }
  }

  return out
}
