// THE ART STYLE, WRITTEN DOWN.
//
// The leagues are named after materials — Wood, Copper, Tin, Bronze, Iron, Silver,
// Gold — so the fights happen in WORKING YARDS, not in fantasy arenas. That is already
// what `themes.ts` says the grounds and the cover are. This file decides how those
// yards are LIT and PHOTOGRAPHED, which is the part that makes them look like anything.
//
//   "A craftsman's yard after the day's work, lit by one warm working lamp."
//
// Deep shadow, a single warm key, cool bounce off the sky, and everything past the
// arena wall falling away into the dark. Per-league identity then comes for free from
// the colour of that lamp: Wood is an amber lantern over pale sawdust; Copper is
// furnace-glow against green patina; Tin is a cold overcast on grey water and white
// metal.
//
// ⚠️ THE OCTOPATH LOOK IS A LENS TREATMENT, NOT A MODELLING ONE, AND THAT IS WHY THE
// PROPS DID NOT LOOK GOOD ENOUGH. HD-2D reads the way it does because of TILT-SHIFT
// DEPTH OF FIELD, BLOOM AND A HARD COLOUR GRADE — the near and far of the board fall
// out of focus, highlights bleed, and the whole frame is pushed warm-in-light and
// cool-in-shadow. Untreated, the same geometry under the same lights reads as an asset
// viewer: everything equally sharp, equally lit, equally present. Adding detail to the
// meshes does not fix that; the frame has to be photographed.
//
// ⚠️ AND IT IS A DIAL, NOT A SWITCH. The deploy screen is a TACTICAL GRID first — blur
// the near and far ranks hard enough and the player cannot count them. `BOARD` and
// `CINEMATIC` are the two settings, and the deploy screen must use `BOARD`.
import * as THREE from 'three'
import type { PropPalette } from './props3d'

export interface Look {
  /** Colour of the single working light. */
  keyColour: number
  keyIntensity: number
  /** Sky and bounce, for the shadowed side. */
  skyColour: number
  bounceColour: number
  ambient: number
  /** How dark the world beyond the arena goes. */
  voidColour: number
  /** Multiplies the shadow half of the frame. */
  shadowTint: [number, number, number]
  /** Multiplies the lit half. */
  highlightTint: [number, number, number]
  saturation: number
  /**
   * Stand structure — concrete, timber, brick. Per league, like everything else.
   *
   * ⚠️ DARKER AND COOLER THAN THE ARENA FLOOR, ALWAYS. Matched to the floor's own
   * timber the whole frame became one brown mass with a board somewhere in it. The
   * playing surface is the lit subject; the bowl around it is the room.
   */
  stone: number
  /**
   * Crowd shirts.
   *
   * ⚠️ MUTED, AND FEW. A crowd at this distance is a TEXTURE, not a set of characters:
   * a wide bright palette turns the stands into confetti and pulls the eye straight off
   * the board, which is the one thing the player is meant to be reading.
   */
  crowd: number[]
}

/** Wood — an amber lantern over pale sawdust and bare boards. */
export const LOOKS: Record<string, Look> = {
  plankyard: {
    keyColour: 0xffe3b0, keyIntensity: 4.6, skyColour: 0x8fb4ee, bounceColour: 0x7a5334,
    ambient: 1.25, voidColour: 0x0d0b09,
    shadowTint: [0.80, 0.86, 1.06], highlightTint: [1.08, 1.02, 0.90], saturation: 1.12,
    stone: 0x3d3226, crowd: [0x8c7b68, 0x6d5f52, 0xa08a6d, 0x5b6470, 0x7a6a5c, 0x93a08c],
  },
  timberyard: {
    keyColour: 0xffdda0, keyIntensity: 4.8, skyColour: 0x93b8f0, bounceColour: 0x8a6238,
    ambient: 1.2, voidColour: 0x100c08,
    shadowTint: [0.79, 0.85, 1.07], highlightTint: [1.10, 1.03, 0.88], saturation: 1.14,
    stone: 0x453623, crowd: [0x8c7b68, 0x74665a, 0xa89070, 0x5f6a74, 0x806f5e, 0x9aa48f],
  },
  // Copper — furnace glow. The hottest league; green patina lives in the shadows.
  washfloor: {
    keyColour: 0xfff0d4, keyIntensity: 4.2, skyColour: 0x9ccfd6, bounceColour: 0x2f6b5c,
    ambient: 1.3, voidColour: 0x080f0e,
    shadowTint: [0.78, 0.99, 0.97], highlightTint: [1.06, 1.02, 0.94], saturation: 1.1,
    stone: 0x333b38, crowd: [0x74807a, 0x5c6a66, 0x8a8f80, 0x4e6b6a, 0x6f7d72, 0x93a09a],
  },
  // ⚠️ FOUR SEPARATE ORANGES WERE STACKED HERE AND THE BOARD WENT FLAT. An amber key at
  // 5.2 — the hottest lamp in the game — over a red-orange bounce, then a red-shifted
  // highlight tint, then a 1.2 global saturation on top. Each is defensible alone; all
  // four together pushed the Ingot Yard's floor, its cover and its stands to a single
  // terracotta value, and cover that is the same value as the ground is cover you cannot
  // read. That breaks a legibility rule, not a taste one.
  // ⚠️ COPPER STAYS THE WARM LEAGUE — this is a reduction, not a re-theme. The key is
  // still amber, the bounce still red, and it is still the only league lit by a furnace
  // rather than by daylight; the ambient goes UP because the smelt yard's ground is the
  // darkest in the game (luminance 42) and was losing its own texture to the shadows.
  smeltyard: {
    keyColour: 0xffcf9c, keyIntensity: 4.6, skyColour: 0x7f8ec4, bounceColour: 0x8a4a2c,
    ambient: 1.28, voidColour: 0x120806,
    shadowTint: [0.84, 0.84, 1.02], highlightTint: [1.09, 1.00, 0.89], saturation: 1.06,
    stone: 0x2e221c, crowd: [0x7a5c48, 0x63483a, 0x8e6a4c, 0x5a5450, 0x6e5344, 0x8a7a68],
  },
  // Tin — cold, because Copper is hot. Two industrial leagues in a row must not be the
  // same industrial yard with different props.
  streamworks: {
    keyColour: 0xe8f2ff, keyIntensity: 4.0, skyColour: 0xa9c6e8, bounceColour: 0x53636e,
    ambient: 1.45, voidColour: 0x0a0e12,
    shadowTint: [0.88, 0.94, 1.10], highlightTint: [0.98, 1.01, 1.06], saturation: 0.95,
    stone: 0x3e4248, crowd: [0x7d858c, 0x646c74, 0x93999e, 0x566068, 0x8a9096, 0x9fa8ae],
  },
  blowinghouse: {
    keyColour: 0xfff6e2, keyIntensity: 4.4, skyColour: 0xb0c4dc, bounceColour: 0x6a6560,
    ambient: 1.3, voidColour: 0x0c0d10,
    shadowTint: [0.90, 0.94, 1.06], highlightTint: [1.04, 1.02, 0.98], saturation: 1.0,
    stone: 0x393937, crowd: [0x7e7c78, 0x66645f, 0x8f8c86, 0x5a5f64, 0x86837c, 0x9b9992],
  },
  // ── Bronze: the alloy, lit warm ───────────────────────────────────────────
  // ⚠️ WARMER THAN COPPER'S FURNACE, NOT HOTTER. Copper is fire and soot with green
  // patina in the shadows; Bronze is the METAL those two made — so the key is a settled
  // gold rather than a flame, and the verdigris moves from the shadows into the bounce.
  // Two industrial leagues in a row that both read "orange yard" would be one league.
  alloyfloor: {
    keyColour: 0xffd9a0, keyIntensity: 4.7, skyColour: 0x9fb8d8, bounceColour: 0x6d7a4a,
    ambient: 1.25, voidColour: 0x100d08,
    shadowTint: [0.82, 0.92, 1.02], highlightTint: [1.12, 1.03, 0.86], saturation: 1.16,
    stone: 0x4a3f2c, crowd: [0x8a7a5c, 0x6b6047, 0x9c8a66, 0x5f6a5a, 0x7d7154, 0x98a082],
  },
  // ⚠️ IRON'S LAMP IS THE HARDEST IN THE GAME, and that is its identity rather than a
  // preference. Copper is a warm bath of orange; Tin is pale and nearly colourless; Iron is
  // a forge — one small violent heat source and everything else falling to cold. So: a
  // white-hot key at the highest intensity on the ladder, the LOWEST ambient of any league,
  // and a strongly blue sky fill so the shadows go cold rather than grey. High contrast is
  // the whole point; a soft Iron would be a dark Copper.
  forgefloor: {
    keyColour: 0xffd9b0, keyIntensity: 5.2, skyColour: 0x7d94b8, bounceColour: 0x3a3f47,
    ambient: 0.95, voidColour: 0x08090b,
    shadowTint: [0.84, 0.92, 1.08], highlightTint: [1.12, 1.04, 0.9], saturation: 0.92,
    stone: 0x3a3d42, crowd: [0x5f646b, 0x4a4e54, 0x6d727a, 0x565b62, 0x787d85, 0x44484e],
  },
  cinderyard: {
    keyColour: 0xffe2c2, keyIntensity: 4.9, skyColour: 0x8496b0, bounceColour: 0x40434a,
    ambient: 1.05, voidColour: 0x0a0a0c,
    shadowTint: [0.87, 0.94, 1.06], highlightTint: [1.09, 1.03, 0.93], saturation: 0.95,
    stone: 0x3f4247, crowd: [0x63686f, 0x4e525a, 0x71767e, 0x5a5f66, 0x7c818a, 0x484c52],
  },

  // ⚠️ SILVER'S LAMP IS THE CLEANEST IN THE GAME, which is the opposite of Iron's and is
  // deliberately so: Iron is one violent heat source with everything else falling to cold,
  // Silver is even daylight on white stone. High ambient, a near-white key at MODERATE
  // intensity, and the lowest saturation on the ladder — a pale floor under a hot lamp
  // clips, and clipped stone is the failure this circuit is most exposed to.
  // ⚠️ AND IT IS WARM-NEUTRAL WHERE TIN IS BLUE. The two pale leagues are told apart by
  // the SIGN of their tint, not by brightness: Tin's shadows go blue and its highlights
  // stay cool; Silver's shadows are barely tinted and its highlights carry a trace of
  // cream, so the same white stone reads as daylight rather than as overcast.
  assayfloor: {
    keyColour: 0xfff4e4, keyIntensity: 4.1, skyColour: 0xbcc9d8, bounceColour: 0x6e6a62,
    ambient: 1.5, voidColour: 0x0c0c0d,
    shadowTint: [0.93, 0.96, 1.03], highlightTint: [1.04, 1.02, 0.97], saturation: 0.9,
    stone: 0x54524c, crowd: [0x8a8880, 0x6e6c66, 0x9b998f, 0x5f6870, 0x807e76, 0xa2a096],
  },
  cupelhearth: {
    keyColour: 0xfff8ee, keyIntensity: 3.9, skyColour: 0xc4cedb, bounceColour: 0x74716b,
    ambient: 1.55, voidColour: 0x0d0d0e,
    shadowTint: [0.94, 0.96, 1.02], highlightTint: [1.03, 1.02, 0.98], saturation: 0.88,
    stone: 0x59574f, crowd: [0x8e8c84, 0x72706a, 0x9f9d93, 0x636c74, 0x84827a, 0xa6a49a],
  },

  // ══ THE GRAND CIRCUIT ══════════════════════════════════════════════════
  // ⚠️ THE LAMP IS THE STONE'S, NOT THE LEAGUE'S, which inverts everything below. Wood's
  // lantern, Copper's furnace and Iron's forge are LEAGUE identities; here one ground is
  // fought on by Platinum and by Apex, so the light has to belong to the floor. Each of
  // these is the daylight that flatters its own stone: warm on porphyry and alabaster,
  // cool on serpentine and slate, and hard on basalt because a near-black floor needs a
  // specular to read as stone rather than as a hole.
  // ⚠️ ALL FIVE SIT NEAR SATURATION 1.0. The floors already carry the colour — that is what
  // the pool is differentiated BY — and the venue puts gilt or silver on the trim at every
  // rung from here up. Grading on top is the Copper smelt-yard mistake at four times the
  // scale, and it would collapse twenty grounds back into four.
  porphyry: {
    keyColour: 0xffe4c6, keyIntensity: 4.4, skyColour: 0x9fb0d4, bounceColour: 0x6b4038,
    ambient: 1.3, voidColour: 0x0e0a0a,
    shadowTint: [0.88, 0.90, 1.04], highlightTint: [1.08, 1.01, 0.94], saturation: 1.0,
    stone: 0x4a3a38, crowd: [0x8a7a74, 0x6c605c, 0x9a8a82, 0x5f6a70, 0x7d706a, 0x9aa096],
  },
  serpentine: {
    keyColour: 0xf2f6e8, keyIntensity: 4.2, skyColour: 0xa8c4c0, bounceColour: 0x4a6050,
    ambient: 1.42, voidColour: 0x0a0e0c,
    shadowTint: [0.90, 0.98, 1.00], highlightTint: [1.02, 1.04, 0.96], saturation: 0.98,
    stone: 0x3e4a42, crowd: [0x7e8880, 0x626c66, 0x8e988e, 0x5a6668, 0x76807a, 0x94a09a],
  },
  // ⚠️ THE HARDEST KEY IN THE POOL, ON THE DARKEST FLOOR, AND THE TWO GO TOGETHER. A
  // near-black ground under a soft lamp is not a dark arena, it is an absent one — the
  // texture disappears and the board reads as a hole with monsters standing over it. The
  // specular is what says basalt.
  basalt: {
    keyColour: 0xf4f0ff, keyIntensity: 5.0, skyColour: 0x8496c0, bounceColour: 0x3a4048,
    ambient: 1.18, voidColour: 0x07080a,
    shadowTint: [0.86, 0.92, 1.10], highlightTint: [1.04, 1.03, 1.02], saturation: 0.94,
    stone: 0x33383f, crowd: [0x656d76, 0x4e555d, 0x767e88, 0x5a626c, 0x808892, 0x474e56],
  },
  alabaster: {
    keyColour: 0xfff2df, keyIntensity: 4.0, skyColour: 0xc0cee0, bounceColour: 0x74695a,
    ambient: 1.5, voidColour: 0x0d0c0a,
    shadowTint: [0.93, 0.96, 1.03], highlightTint: [1.05, 1.02, 0.96], saturation: 0.95,
    stone: 0x565046, crowd: [0x8f8878, 0x716b5f, 0x9f9888, 0x646e72, 0x827b6d, 0xa39c8e],
  },
  slateyard: {
    keyColour: 0xeef2fa, keyIntensity: 4.3, skyColour: 0xa6bad6, bounceColour: 0x4c5560,
    ambient: 1.36, voidColour: 0x090b0e,
    shadowTint: [0.89, 0.94, 1.08], highlightTint: [1.00, 1.02, 1.04], saturation: 0.96,
    stone: 0x3b4249, crowd: [0x767e88, 0x5c636c, 0x878f99, 0x566068, 0x808892, 0x969ea8],
  },

  // ── block 2: the five hues the game had none of ─────────────────────────
  // ⚠️ EACH LAMP IS THE DAYLIGHT THAT FLATTERS ITS OWN STONE, and the bounce is kept close
  // to neutral on all five. The floor is what carries the colour — that is the whole basis
  // the pool is sorted on — so a bounce tinted to match would be the Copper smelt-yard
  // mistake with hues instead of oranges: three warm things stacked is one orange thing,
  // and three green things stacked is one green board.
  travertine: {
    keyColour: 0xfff0dc, keyIntensity: 4.2, skyColour: 0xb4c4dc, bounceColour: 0x6c6558,
    ambient: 1.44, voidColour: 0x0d0c09,
    shadowTint: [0.92, 0.95, 1.03], highlightTint: [1.05, 1.02, 0.96], saturation: 0.97,
    stone: 0x524a3e, crowd: [0x8c8474, 0x6e675b, 0x9c9484, 0x626c70, 0x7f7869, 0x9fa090],
  },
  // ⚠️ THE ONLY FLECKED FLOOR IN THE GAME, WHICH IS WHY ITS KEY IS SLIGHTLY HARDER. Granite
  // reads as granite because of specular glints off individual crystals; soften the lamp and
  // it collapses into flat mid-grey, which is the one thing this ground must not be — the
  // pool already has slate for that.
  granite: {
    keyColour: 0xfaf4ee, keyIntensity: 4.6, skyColour: 0xacbcd0, bounceColour: 0x5e5a58,
    ambient: 1.34, voidColour: 0x0a0a0b,
    shadowTint: [0.92, 0.94, 1.04], highlightTint: [1.03, 1.02, 1.00], saturation: 0.96,
    stone: 0x484a4c, crowd: [0x7c7e80, 0x616365, 0x8d8f91, 0x5c6468, 0x86888a, 0x9ba0a2],
  },
  jasper: {
    keyColour: 0xffeecc, keyIntensity: 4.4, skyColour: 0x9db2d0, bounceColour: 0x6a5c42,
    ambient: 1.3, voidColour: 0x0e0b07,
    shadowTint: [0.89, 0.93, 1.05], highlightTint: [1.07, 1.02, 0.93], saturation: 0.98,
    stone: 0x4c4232, crowd: [0x8a7e64, 0x6c6250, 0x9a8e74, 0x606a64, 0x7d7360, 0x9aa088],
  },
  // ⚠️ A HUE THIS PROJECT HAS NEVER USED, AND IT IS THE ONE MOST AT RISK OF READING AS A
  // LIGHTING BUG. Violet on stone is rare enough that a strong tint looks like a broken
  // grade rather than a quarry; the lamp is deliberately the most neutral in the pool so the
  // colour is unmistakably IN the floor.
  amethystine: {
    keyColour: 0xf6f2fa, keyIntensity: 4.3, skyColour: 0xb0b0cc, bounceColour: 0x585460,
    ambient: 1.38, voidColour: 0x0a090c,
    shadowTint: [0.94, 0.93, 1.06], highlightTint: [1.02, 1.00, 1.03], saturation: 0.94,
    stone: 0x44414c, crowd: [0x7a7684, 0x5f5c68, 0x8b8794, 0x5a6068, 0x848090, 0x9a96a4],
  },
  malachite: {
    keyColour: 0xf0f8f4, keyIntensity: 4.4, skyColour: 0x9cbcc0, bounceColour: 0x46564e,
    ambient: 1.32, voidColour: 0x080c0a,
    shadowTint: [0.91, 0.98, 1.01], highlightTint: [1.01, 1.04, 0.98], saturation: 0.95,
    stone: 0x39463f, crowd: [0x76847c, 0x5c6862, 0x86948a, 0x586468, 0x707e76, 0x8e9c94],
  },

  // ── block 3: two patterns and the last three hues ───────────────────────
  // ⚠️ THE PATTERNED FLOORS GET THE SOFTEST LAMPS IN THE POOL, which is the opposite of the
  // instinct. A figured floor already carries its own contrast — a chequer has a hard edge
  // every few units and a mosaic has one every few INCHES — so a hard key doubles it and the
  // board starts competing with the sprites standing on it. Basalt needs a specular because
  // it has no figure of its own; these two need the reverse.
  chequer: {
    keyColour: 0xfdf6ec, keyIntensity: 3.9, skyColour: 0xb6c2d4, bounceColour: 0x605a52,
    ambient: 1.48, voidColour: 0x0b0a09,
    shadowTint: [0.93, 0.95, 1.03], highlightTint: [1.03, 1.01, 0.98], saturation: 0.93,
    stone: 0x4a4640, crowd: [0x86807a, 0x69645e, 0x96908a, 0x5f676c, 0x7c766f, 0x9a9a94],
  },
  mosaic: {
    keyColour: 0xfff2e0, keyIntensity: 4.0, skyColour: 0xaebed4, bounceColour: 0x64604e,
    ambient: 1.46, voidColour: 0x0c0b08,
    shadowTint: [0.92, 0.95, 1.04], highlightTint: [1.04, 1.02, 0.97], saturation: 0.95,
    stone: 0x4c473c, crowd: [0x898270, 0x6b6558, 0x999182, 0x616a6a, 0x7d7768, 0x9b9c8c],
  },
  rosestone: {
    keyColour: 0xfff0e8, keyIntensity: 4.2, skyColour: 0xb4bcd0, bounceColour: 0x6a5a56,
    ambient: 1.4, voidColour: 0x0c0a0a,
    shadowTint: [0.93, 0.94, 1.03], highlightTint: [1.05, 1.01, 0.98], saturation: 0.96,
    stone: 0x4e4644, crowd: [0x8a8078, 0x6c645e, 0x9a9088, 0x606a6e, 0x7e746e, 0x9c9a94],
  },
  // ⚠️ ONYX HAS THE WIDEST TONAL RANGE OF ANY FLOOR — cream to near-black WITHIN one slab —
  // so its lamp is flat and its saturation the lowest in the pool. Anything else and the
  // pale bands clip while the dark ones close up, which throws away the only thing the
  // stone has.
  onyx: {
    keyColour: 0xfaf6f0, keyIntensity: 3.8, skyColour: 0xb0b8c6, bounceColour: 0x585450,
    ambient: 1.52, voidColour: 0x0a0908,
    shadowTint: [0.95, 0.96, 1.02], highlightTint: [1.02, 1.01, 0.99], saturation: 0.9,
    stone: 0x474440, crowd: [0x848078, 0x67635d, 0x949088, 0x5e6668, 0x7a766e, 0x989690],
  },
  verdite: {
    keyColour: 0xfaf6e4, keyIntensity: 4.4, skyColour: 0xa4b6c4, bounceColour: 0x4e5440,
    ambient: 1.3, voidColour: 0x090b07,
    shadowTint: [0.91, 0.96, 1.02], highlightTint: [1.04, 1.03, 0.95], saturation: 0.96,
    stone: 0x3e4436, crowd: [0x7a8070, 0x5f6458, 0x8a9080, 0x5a6462, 0x74796a, 0x929888],
  },



  // ⚠️ GOLD IS THE ONLY LEAGUE LIT LIKE LATE AFTERNOON RATHER THAN LIKE A WORKING LAMP,
  // and it is the one place on the ladder where that is allowed. Every circuit below is a
  // YARD — a furnace, a forge, an assay floor — so the house note is "a craftsman's yard
  // lit by one working lamp". A pleasance is not a workplace; it is a garden laid out to be
  // walked in, and the light that belongs on it is low warm sun. Slightly lower key, higher
  // ambient than Iron, and the warmest highlight tint on the ladder.
  // ⚠️ SATURATION STAYS NEAR 1.0 DESPITE THE NAME. The ground already carries the warmth
  // (gilded court is the richest floor in the game even after correction) and the venue
  // puts GILT on every trim at this rung. Pushing the grade as well is how Copper's smelt
  // yard went flat — three warm things stacked is one orange thing.
  gildedcourt: {
    keyColour: 0xffe6bc, keyIntensity: 4.3, skyColour: 0x9fbcdc, bounceColour: 0x6e6440,
    ambient: 1.38, voidColour: 0x0e0c08,
    shadowTint: [0.86, 0.92, 1.04], highlightTint: [1.10, 1.03, 0.90], saturation: 1.02,
    stone: 0x4c4433, crowd: [0x8c8168, 0x6d6552, 0x9c9070, 0x606a62, 0x7e7460, 0x9aa084],
  },
  parterre: {
    keyColour: 0xfff0d2, keyIntensity: 4.2, skyColour: 0xa8c0dc, bounceColour: 0x5e6a44,
    ambient: 1.42, voidColour: 0x0c0d0a,
    shadowTint: [0.88, 0.94, 1.04], highlightTint: [1.07, 1.03, 0.93], saturation: 1.0,
    stone: 0x4a4838, crowd: [0x89836c, 0x6b6656, 0x999274, 0x5e6864, 0x7c7663, 0x97a086],
  },

  bellyard: {
    keyColour: 0xffe8c4, keyIntensity: 4.4, skyColour: 0xa8b6c8, bounceColour: 0x5c5a4e,
    ambient: 1.35, voidColour: 0x0d0c0a,
    shadowTint: [0.88, 0.94, 1.04], highlightTint: [1.06, 1.02, 0.94], saturation: 1.04,
    stone: 0x474338, crowd: [0x807a68, 0x646054, 0x928c78, 0x5c6462, 0x76705f, 0x8f9280],
  },

  proving: {
    keyColour: 0xfff0d0, keyIntensity: 4.4, skyColour: 0xa8c4f0, bounceColour: 0x5d6b46,
    ambient: 1.3, voidColour: 0x0b0f16,
    shadowTint: [0.86, 0.92, 1.06], highlightTint: [1.06, 1.02, 0.94], saturation: 1.06,
    stone: 0x3a3c34, crowd: [0x82806f, 0x676555, 0x969480, 0x5d6668, 0x7c7a6a, 0x9aa08c],
  },
}

export const lookFor = (themeId: string): Look => LOOKS[themeId] ?? LOOKS.proving

/**
 * What each theme's COVER is made of, in the 3D scene.
 *
 * ⚠️ THIS LIVES BESIDE `LOOKS` NOW, AND IT USED TO LIVE IN THE PREVIEW COMPONENT. Two
 * per-theme presentation tables in two different files is how Bronze shipped invisible
 * to the 3D renderer: `themes.ts` gained `alloyfloor` and `bellyard`, the 2D board drew
 * them correctly, and the 3D scene silently fell back to grass lighting and timber prop
 * colours because nobody remembered there were three tables to add to. `arenas.test.ts`
 * now asserts every theme has an entry in both — a half-authored theme must fail loudly
 * rather than render as the wrong league.
 */
export const PALETTES: Record<string, PropPalette> = {
  plankyard: { surface: 'timber', body: 0x8a5f3a, trim: 0x4a4a52, inner: 0xc9a273, rough: 0.9 },
  timberyard: { surface: 'timber', body: 0x7d5432, trim: 0x4a4a52, inner: 0xd8b985, rough: 0.92 },
  washfloor: { surface: 'stone', body: 0x6f7a80, trim: 0x59636a, inner: 0x4e8f7d, rough: 0.88 },
  smeltyard: { surface: 'stone', body: 0x5a4438, trim: 0xb5703a, inner: 0xd9843c, rough: 0.8 },
  streamworks: { surface: 'stone', body: 0x7c8790, trim: 0x9aa6b0, inner: 0xc3d2dc, rough: 0.86 },
  blowinghouse: { surface: 'metal', body: 0x554e4a, trim: 0xc0c6cc, inner: 0xe4e9ee, rough: 0.8 },
  // Bronze: warm metal bodies, verdigris in the broken faces, pale tin fittings — the
  // two parent leagues visible in one object.
  alloyfloor: { surface: 'metal', body: 0x8a6a3e, trim: 0xb9985e, inner: 0x5f8f6a, rough: 0.82 },
  // Dark iron and hammer scale, with a bright-cut edge where the metal is fresh.
  // ⚠️ `stone`, NOT `metal`, EVEN THOUGH THE LEAGUE IS A METAL. Silver's floor family is
  // the COLONNADE — columns, broken columns, obelisks — and a column is masonry whatever
  // the circuit is called. The league's metal shows in the venue's trim, which is silvered
  // at this rung anyway; putting it on the cover as well would make every piece read as a
  // casting.
  // ⚠️ THE GRAND CIRCUIT'S COVER IS DRESSED STONE MATCHED TO ITS FLOOR. Below Platinum a
  // theme's palette is its TRADE — copper's patina, iron's scale — because the props are the
  // league's working gear. Here the props are architecture and the floor is the identity, so
  // each palette is the same stone one shade lighter, which is how a real ground is built:
  // the walls come out of the same quarry as the paving.
  chequer: { surface: 'stone', body: 0xa8a49c, trim: 0xcecac2, inner: 0xb4b0a8, rough: 0.85 },
  mosaic: { surface: 'stone', body: 0xa8a08c, trim: 0xcec8b4, inner: 0xb4ac98, rough: 0.86 },
  rosestone: { surface: 'stone', body: 0xa8968e, trim: 0xd0bcb2, inner: 0xb4a29a, rough: 0.86 },
  onyx: { surface: 'stone', body: 0xa6a29a, trim: 0xd2cec4, inner: 0xb2aea6, rough: 0.82 },
  verdite: { surface: 'stone', body: 0x8c9080, trim: 0xb4b8a6, inner: 0x989c8c, rough: 0.85 },
  travertine: { surface: 'stone', body: 0xb0a690, trim: 0xd4ccb8, inner: 0xbcb29c, rough: 0.86 },
  granite: { surface: 'stone', body: 0x8a8c8e, trim: 0xb2b4b6, inner: 0x96989a, rough: 0.82 },
  jasper: { surface: 'stone', body: 0xa08c68, trim: 0xc8b892, inner: 0xac9a78, rough: 0.85 },
  amethystine: { surface: 'stone', body: 0x8e8a98, trim: 0xb6b2c0, inner: 0x9a96a4, rough: 0.85 },
  malachite: { surface: 'stone', body: 0x7c8e84, trim: 0xa6b6ac, inner: 0x8a9a90, rough: 0.84 },
  porphyry: { surface: 'stone', body: 0x9a7a72, trim: 0xc4a898, inner: 0xa88a80, rough: 0.85 },
  serpentine: { surface: 'stone', body: 0x8a9a8c, trim: 0xb4c2b2, inner: 0x96a698, rough: 0.86 },
  basalt: { surface: 'stone', body: 0x6e747c, trim: 0x99a0a8, inner: 0x7c828a, rough: 0.82 },
  alabaster: { surface: 'stone', body: 0xb0a894, trim: 0xd6cebc, inner: 0xbcb49f, rough: 0.86 },
  slateyard: { surface: 'stone', body: 0x7e868e, trim: 0xa8b0b8, inner: 0x8a929a, rough: 0.84 },
  // ⚠️ WARMER STONE THAN SILVER'S, BECAUSE THE URN IS THE ONLY MASONRY ON THESE BOARDS.
  // Gold's cover is hedging, which authors its own green; the theme palette reaches only
  // the urn's plinth and bowl. Pale-cool there would read as a Silver piece left behind.
  gildedcourt: { surface: 'stone', body: 0xa39a86, trim: 0xd8c68e, inner: 0xb0a184, rough: 0.84 },
  parterre: { surface: 'stone', body: 0x9c9582, trim: 0xcfc59c, inner: 0xa8a087, rough: 0.86 },
  assayfloor: { surface: 'stone', body: 0x8e8a80, trim: 0xb8b4a8, inner: 0x9c988c, rough: 0.86 },
  cupelhearth: { surface: 'stone', body: 0x928e84, trim: 0xbcb8ac, inner: 0xa09c90, rough: 0.88 },
  forgefloor: { surface: 'metal', body: 0x4a4d52, trim: 0x9aa0a8, inner: 0x6e737a, rough: 0.78 },
  cinderyard: { surface: 'metal', body: 0x4f5257, trim: 0x969ba2, inner: 0x74797f, rough: 0.82 },
  bellyard: { surface: 'metal', body: 0x6b6250, trim: 0xc2c6c0, inner: 0x8d8a72, rough: 0.86 },
  proving: { surface: 'stone', body: 0x6b6f5e, trim: 0x4a4a52, inner: 0x9aa08a, rough: 0.92 },
}
export const paletteFor = (themeId: string): PropPalette => PALETTES[themeId] ?? PALETTES.proving

/**
 * The grade: split-toning and a vignette, applied after bloom.
 *
 * ⚠️ SPLIT-TONING IS THE CHEAPEST THING THAT READS AS "GRADED". Pushing the shadows
 * one way and the highlights the other is what separates a photographed frame from a
 * rendered one — a scene lit by a warm lamp should have COOL shadows, because the only
 * thing filling them is the sky. Tinting the whole image instead just looks like a
 * colour cast.
 */
export const GradeShader = {
  name: 'GradeShader',
  uniforms: {
    tDiffuse: { value: null as THREE.Texture | null },
    shadowTint: { value: new THREE.Vector3(0.86, 0.92, 1.06) },
    highlightTint: { value: new THREE.Vector3(1.06, 1.02, 0.94) },
    saturation: { value: 1.06 },
    vignette: { value: 0.42 },
  },
  vertexShader: /* glsl */`
    varying vec2 vUv;
    void main() {
      vUv = uv;
      gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
    }`,
  fragmentShader: /* glsl */`
    uniform sampler2D tDiffuse;
    uniform vec3 shadowTint;
    uniform vec3 highlightTint;
    uniform float saturation;
    uniform float vignette;
    varying vec2 vUv;
    void main() {
      vec4 c = texture2D(tDiffuse, vUv);
      float l = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
      c.rgb *= mix(shadowTint, highlightTint, smoothstep(0.12, 0.78, l));
      c.rgb = mix(vec3(l), c.rgb, saturation);
      vec2 d = vUv - 0.5;
      c.rgb *= 1.0 - vignette * dot(d, d) * 2.1;
      gl_FragColor = c;
    }`,
}

/**
 * How hard the lens is applied.
 *
 * ⚠️ `BOARD` IS NOT A WEAKER `CINEMATIC`, IT IS A DIFFERENT JOB. On the deploy screen
 * the player is counting ranks and reading which cells are theirs; depth of field that
 * softens the near and far ranks makes a picture out of a thing they have to operate.
 * Deployment gets the grade and a trace of bloom, and keeps its focus.
 *
 * ⚠️ `fit` IS THE SAME SPLIT, AND IT IS WHY GRANDEUR KEPT VANISHING. The camera frames
 * the BOARD, not the bowl — at 0.998 the playing surface fills the picture and the
 * stadium runs off all four edges, so on any ground under about 1.5 aspect there is
 * almost no venue in shot at all. Every ornament added to the ladder has had to be
 * rescued from that: the first colonnade, the corner turrets, the victory arch (twice)
 * and the treeline were all authored, correct, and outside the frame.
 *
 * Loosening it globally would shrink the playing surface ~14% on the screen the player
 * OPERATES, which is the wrong trade — the board being too small is a complaint this
 * project has already had three times. So the two lenses take different framings, which
 * is what a lens is for: DEPLOY is fitted tight to the thing being read, and the REPLAY
 * pulls back far enough to show the ground it is being fought in.
 */
export const LENS = {
  BOARD: { dofAperture: 0.00010, dofBlur: 0.0035, bloom: 0.20, vignette: 0.32, fit: 0.998 },
  // ⚠️ FAR GENTLER THAN A PHOTOGRAPHIC TILT-SHIFT, AND IT HAS TO BE. At a real
  // shallow-focus aperture the effect blurred the MONSTERS — the arena is ~17 units
  // deep and the units stand at its two far edges, so anything that leaves a thin band
  // in focus leaves the units outside it. Octopath blurs SCENERY and keeps its cast
  // sharp; here the same setting does the opposite, because our subjects are at the
  // extremes of the depth range rather than the middle of it.
  CINEMATIC: { dofAperture: 0.00034, dofBlur: 0.006, bloom: 0.38, vignette: 0.46, fit: 0.86 },
}
export type LensMode = keyof typeof LENS
