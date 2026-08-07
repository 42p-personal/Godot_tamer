// THE VENUE — how grand the ground is, as opposed to what it is made of or how big it
// is. The third and last axis of an arena, and the one that was missing.
//
// An arena is decided by three INDEPENDENT things, and keeping them independent is the
// whole point of this file existing separately:
//
//   MATERIAL  ← the league's NAME.       Wood is timber, Tin is pale metal. `themes.ts`.
//   SIZE      ← the league's TEAM SIZE.  1v1 is small, 5v5 is 5.5x it. `maps.ts`.
//   GRANDEUR  ← the league's RUNG.       Wood is scaffolding, Apex is a colonnade. HERE.
//
// ⚠️ THEY WERE COLLAPSED BEFORE THIS, AND EVERY LEAGUE GOT THE SAME BOWL IN A DIFFERENT
// COLOUR. `stadium.ts` held its row counts as module constants, so a Wood knock-about on
// borrowed ground and the summit of the entire circuit were the same building with the
// timber re-tinted. Size already ramped and material already changed; the thing a player
// would actually read as PROGRESSION did not.
//
// ⚠️ AND GRANDEUR IS NOT MATERIAL, WHICH IS WHY IT IS NOT IN `themes.ts`. Wood's stands
// are wooden because the league is called Wood — but they are also SPARSE, low and
// unroofed because it is the bottom rung. Silver's would be stone and colonnaded even
// though its props are white metal. Fold the two together and you can never say "a grand
// timber ground" or "a mean little iron one", and the ladder loses a dimension.
//
// ⚠️ NOTE THE LADDER IS AN ALLOY STORY AND BRONZE SHOULD LOOK LIKE ONE. Wood → Copper →
// Tin → BRONZE — bronze IS copper and tin, and its venue should read as both: the green
// patina of the Copper yards with Tin's pale metal fittings. That is free flavour the
// naming already paid for.

/**
 * Where each league sits on the ladder, 0 (borrowed ground) to 10 (the summit).
 *
 * ⚠️ NOT THE SAME SHAPE AS TEAM SIZE, DELIBERATELY. Team size plateaus at five from
 * Platinum onward — `town.ts` calls that out as a lost progression axis. Grandeur keeps
 * climbing all the way to Apex, so the top four leagues are told apart by the ground
 * they are fought on when their rosters can no longer tell them apart.
 */
export const VENUE_TIER: Record<string, number> = {
  Wood: 0, Copper: 1, Tin: 2, Bronze: 3, Iron: 4, Silver: 5, Gold: 6,
  Platinum: 7, Masters: 8, 'Tamer Elite': 9, 'Tamers Apex': 10,
}

/**
 * ⚠️ COLUMNS ARRIVE AS THREE DISTINCT BUILDINGS, NOT AS ONE THAT SLOWLY IMPROVES.
 *   plain   — a shaft, a base, a capital and a finial. Freestanding posts.
 *   fluted  — faceted shafts, a taller order, and an ENTABLATURE tying them together.
 *   arcade  — arches sprung between every pair, so the ring becomes a colonnade proper.
 * A player arriving at Masters should be able to say the ground has arches now; a
 * continuously-lerped column would just be very slightly bigger every league and read
 * as nothing at all.
 */
export type ColumnStyle = 'none' | 'plain' | 'fluted' | 'arcade'

export interface Venue {
  tier: number
  /** Seating banks: far, the two ends, and the shallow near one. */
  rowsFar: number
  rowsEnd: number
  rowsNear: number
  /** Structure colour. Raw timber at the bottom, dressed stone at the top. */
  stone: number
  /** Fittings — nails and iron low down, gilding high up. */
  trim: number
  /**
   * Masonry for the ARENA'S OWN furniture — walls, ruins, gateways, obelisks.
   *
   * ⚠️ THE STANDS CLIMB THE MATERIAL LADDER; THE FLOOR'S MASONRY DOES NOT. `stone` above
   * starts at raw timber because Wood's SEATING is timber, and floor furniture borrowing
   * it drew Bronze's ruined walls in a near-black brown that read as burnt wood on a gold
   * floor. A ruined wall is dressed stone at every rung — what climbs is how WELL it is
   * dressed, from rough grey coursing to pale ashlar. Keeping the two ladders apart is
   * the same split as material-versus-grandeur one level up.
   */
  masonry: number
  /**
   * Dressings on that masonry — capping courses, copings, keystones.
   *
   * ⚠️ SAME REASON AS `masonry`, AND IT WAS THE MORE VISIBLE HALF. `trim` starts at
   * near-black iron because a Wood stand is nailed timber; a wall borrowing it drew a
   * black capping course over a grey body, which reads as a charred beam rather than
   * stone. Pale dressed stone low down, and the gilt still arrives at Gold — the same
   * rung `trim` gilds at, so the two ladders stay in step where it matters.
   */
  masonryTrim: number
  /** How metallic the trim reads. Gilding needs it; a nailed plank does not. */
  trimMetal: number
  /**
   * Columns standing on the trackway, BETWEEN the floor and the stands.
   *
   * ⚠️ THE FIRST COLONNADE WAS BEHIND THE TOP ROW AND NOBODY EVER SAW IT. It was
   * architecturally sensible and completely wasted: the camera frames the BOARD, so
   * anything behind the back row of a nine-row stand is off-frame at every tier. Grandeur
   * has to be built where the shot is — the trackway is the only ring of space that is
   * always in view and always empty.
   */
  columns: ColumnStyle
  /**
   * A beam of masonry across the column tops, tying them into a single structure.
   *
   * ⚠️ THIS IS WHAT SEPARATES "COLUMNS" FROM "ARCHITECTURE". A ring of freestanding
   * posts reads as fenceposts however ornate each one is; the moment a continuous
   * entablature runs across their capitals the eye reads a BUILDING. It is one box ring
   * and it is the single highest-value piece of masonry in the whole ladder.
   */
  entablature: boolean
  /** Bunting strung between the column finials. */
  pennants: boolean
  /** Turrets at the four corners of the bowl. */
  turrets: boolean
  /** A ceremonial arch centred on the far side. */
  victoryArch: boolean
  /** Quadrant mosaic around the centre medallion. */
  mosaic: boolean
  /** A stepped masonry course running round the arena floor. */
  baseCourse: boolean
  /** A canopy over the far stand — the mark of a permanent ground. */
  canopy: boolean
  /** Pennants along the end barriers. */
  banners: number
  /** Fraction of seats taken. A poor circuit does not fill its stands. */
  fill: number
  /** Seat backs on every row, so the stands read as SEATING and not as steps. */
  seatBacks: boolean
  /**
   * A ring of trees standing beyond the stands.
   *
   * ⚠️ A VENUE FEATURE, NOT PER-ARENA SCENERY, AND THAT IS A CORRECTION. Every board used
   * to author its own treeline by hand — nine or ten entries each, twenty boards, and
   * Wood got one even though Wood is meant to have NO grandeur at all. It is a rung on
   * the ladder, so it belongs to the rung: off at Wood, on from Copper up, sized off the
   * board and the bank depth so all 39 unauthored arenas inherit it for nothing.
   */
  treeline: boolean
  /**
   * Planters on the trackway — small trees and flowers just inside the barrier.
   *
   * ⚠️ THE ONLY GREENERY THAT MAY STAND RINGSIDE, AND IT HAS TO BE SMALL TO DO IT. The
   * trackway is `GAP` = 1.6 units wide, narrower than a bush; a planter is a tub about a
   * unit across, which is exactly why this is the ornament that can go there and the
   * treeline is not.
   */
  planters: number
  /** A turned balustrade instead of a plain kerb. */
  balustrade: boolean
  /** Standing braziers around the trackway. Emissive, so the bloom pass carries them. */
  braziers: number
  /** Inlaid border on the arena floor, 0 = none. */
  floorInlay: number
  /** A medallion at the centre circle. */
  medallion: boolean
  /** Statues on plinths at the four corners. */
  statues: boolean
}

/**
 * ⚠️ ROWS CLIMB SLOWLY AND ORNAMENT ARRIVES IN STEPS. Rows are the expensive axis: each
 * one pushes the camera back to keep it in frame and shrinks the playing surface, which
 * is the part the player is reading. So the bowl roughly doubles across eleven leagues
 * while the ORNAMENT — columns, a canopy, gilding, a full house — does most of the work
 * of saying "this is a bigger occasion". Ornament is free in screen space; rows are not.
 */
export function venueFor(tier: number): Venue {
  const t = Math.max(0, Math.min(10, tier)) / 10
  const lerp = (a: number, b: number) => a + (b - a) * t
  // Raw timber → weathered board → dressed stone → pale dressed stone.
  const stone = [0x3d3226, 0x413428, 0x44392c, 0x473d31, 0x4b463e, 0x525049,
    0x5a5952, 0x63625c, 0x6c6b66, 0x757470, 0x807f7c][Math.round(t * 10)]
  // Nails and iron → bronze → silvered → gilt.
  const trim = [0x2b2723, 0x33291f, 0x3c2e20, 0x6b4a2a, 0x4a4a52, 0x8a8f96,
    0xb0a06a, 0xc8b878, 0xd6c88c, 0xe2d69c, 0xf0e4b0][Math.round(t * 10)]
  return {
    tier,
    rowsFar: Math.round(lerp(7, 16)),
    rowsEnd: Math.round(lerp(5, 13)),
    rowsNear: Math.round(lerp(2, 4)),
    stone,
    trim,
    // Rough grey coursing → dressed → pale ashlar. Never timber, never near-black.
    masonry: [0x6a6156, 0x6e655a, 0x72695e, 0x776e63, 0x7d7469, 0x847b70,
      0x8b8277, 0x938a7f, 0x9b9288, 0xa39a91, 0xaba299][Math.round(t * 10)],
    // ⚠️ DARKER BELOW GOLD THAN THE FIRST PASS. A capping course is the top surface of a
    // wall, so it takes the key light almost square-on; pale dressing plus a bright lamp
    // clipped it to white and the moulding vanished. It only needs to read LIGHTER than
    // the coursing under it, not light in absolute terms.
    masonryTrim: [0x7a7268, 0x7f776c, 0x847c71, 0x8a8276, 0x90887c, 0x968e82,
      0xb0a06a, 0xc8b878, 0xd6c88c, 0xe2d69c, 0xf0e4b0][Math.round(t * 10)],
    trimMetal: lerp(0.15, 0.85),
    // ⚠️ COLUMNS START AT GOLD (6), NOT SILVER. Silver keeps the balustrade and the
    // braziers as its step up; masonry is what Gold buys. Spreading the ladder's big
    // moments out matters more than giving every rung something — two leagues in a row
    // that both "get stone" is one moment, not two.
    // ⚠️ COLUMNS AT SILVER AND ARCHES AT PLATINUM (2026-08-02, user ladder). They used to
    // be 6 and 9, which put the two biggest architectural moments three rungs apart and
    // left Silver — the first league a player would call GRAND — with nothing of its own.
    // ⚠️ AND `fluted` IS OFF THE LADDER RATHER THAN DELETED. It is a refinement of the
    // plain order, and with arches arriving at 7 there is no rung left between plain and
    // arcade for it to occupy. The style stays in the union and in `stadium.ts` so a later
    // pass can make the ARCADE's own piers fluted at the summit — which is where it always
    // belonged. A dead branch that says why is worth more than a deleted one.
    columns: tier >= 7 ? 'arcade' : tier >= 5 ? 'plain' : 'none',
    entablature: tier >= 8,
    pennants: tier >= 7,
    turrets: tier >= 9,
    victoryArch: tier >= 10,
    mosaic: tier >= 9,
    baseCourse: tier >= 7,
    canopy: tier >= 7,
    banners: Math.round(lerp(2, 6)),
    // ⚠️ ORNAMENT ARRIVES IN STEPS, NOT ON A RAMP, AND THE STEPS ARE THE PROGRESSION.
    // A continuously-interpolated stadium is one stadium getting imperceptibly nicer; a
    // player climbing the ladder should be able to name what the new ground HAS that the
    // old one did not:
    //    3  seat backs          6  columns (plain) + floor medallion
    //    4  balustrade,          7  base course, pennants, canopy
    //       braziers             8  fluted columns + ENTABLATURE, statues
    //    5  (holds — Silver      9  arcade (arches), corner turrets, mosaic
    //       gets the stone      10  victory arch
    //       balustrade)
    // ⚠️ THE LADDER AS BRIEFED, AND IT IS CUMULATIVE — every rung keeps what the one below
    // it had and adds its own:
    //    0  Wood            nothing at all. A field with a rail round it.
    //    1  Copper          + a treeline behind the stands
    //    2  Tin             (holds — Copper and Tin are one step together)
    //    3  Bronze          + seat backs: the stands become SEATING, not steps
    //    4  Iron            + balustrade and braziers
    //    5  Silver          + COLUMNS, in the league's own colour
    //    6  Gold            + planters — small trees and flowers inside the barrier
    //    7  Platinum        + ARCHES instead of columns, canopy, base course, pennants
    //    8  Masters         + entablature and statues
    //    9  Tamer Elite     + corner turrets and the quadrant mosaic
    //   10  Tamers Apex     + the ceremonial victory arch
    treeline: tier >= 1,
    planters: tier >= 6 ? Math.round(lerp(0, 18)) : 0,
    seatBacks: tier >= 3,
    balustrade: tier >= 4,
    braziers: tier >= 4 ? Math.round(lerp(0, 12)) : 0,
    floorInlay: tier >= 2 ? Math.min(3, Math.floor((tier - 2) / 3) + 1) : 0,
    medallion: tier >= 6,
    statues: tier >= 8,
    // ⚠️ A HALF-EMPTY BOTTOM-RUNG GROUND IS THE POINT, NOT AN OVERSIGHT. Nobody comes to
    // watch a Wood qualifier; a full house at Apex is most of what makes it feel like
    // one. Crowd SIZE is the cheapest grandeur there is — it costs no screen space and
    // no extra draw call, because the bowl is one instanced mesh either way.
    fill: lerp(0.42, 0.97),
  }
}

/** The venue for a league, falling back to the bottom rung for anything unlisted. */
export const venueForLeague = (league: string): Venue => venueFor(VENUE_TIER[league] ?? 0)
