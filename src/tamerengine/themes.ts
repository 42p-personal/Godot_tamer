// ARENA THEMES — what an arena is made of, as opposed to what shape it is.
//
// `maps.ts` owns GEOMETRY (size, where the cover stands, symmetry). This file owns
// MATERIAL (what the ground is, what the cover is made of). They are split because
// they change for different reasons and at different rates: a league's visual
// identity is one theme shared by all of its arenas, while every arena in that
// league is a different layout.
//
// ⚠️ A THEME IS MANY-TO-ONE, DELIBERATELY. Gold onwards needs six arenas each; six
// unique ground textures per league would be ~50 bespoke images for a difference the
// player reads as "this is still the Gold circuit". Six LAYOUTS on one material is
// the variety that matters in play, and it is also the version that can actually be
// drawn. Where two arenas in a league genuinely want different materials — Wood's
// mud paddock against its sawdust timberyard — they simply reference two themes.
//
// ⚠️ EVERY PROP FALLS BACK TO THE BOULDER. A theme that has not been drawn yet
// still renders a playable arena rather than an invisible one, so geometry can be
// authored and simulated before any art exists. Missing art must look like missing
// art, never like an empty field the units mysteriously path around.
import type { ObstacleKind } from './types'

export interface ArenaTheme {
  id: string
  name: string
  /** Tiling ground texture, drawn repeating under the whole field. */
  ground: string
  /**
   * CSS `background-size` for that tile.
   *
   * ⚠️ SET PER THEME, NOT GLOBALLY. The field is a fixed aspect box whose PIXEL size
   * varies with the viewport, so a tile sized in pixels would grow and shrink
   * relative to the monsters standing on it. A percentage of the field's height
   * keeps the ground's grain constant against the sprites at every window size.
   */
  groundScale: string
  /** Sprite per obstacle kind. Anything absent falls back to the boulder. */
  props: Partial<Record<ObstacleKind, string>>
}

// ⚠️ ARENA FURNITURE IS SHARED BY EVERY THEME, AND THAT IS THE DESIGN. Barrels and ore
// piles belong to a league because they are its TRADE; a wall, a pillar, a gate and a
// dais are the ARENA, and an arena is dressed stone at every rung. One grey set, generated
// once, re-tinted per league by `PropPalette` in 3D. Five images for the whole game rather
// than five per league — and it is also why they are spliced into every `props` map below
// rather than listed by hand in each.
export const FALLBACK_PROP = '/field/boulder.png'

export const THEMES: Record<string, ArenaTheme> = {
  // ── Wood: the league's own material ───────────────────────────────────────
  // ⚠️ "WOOD" IS THE TIER, NOT A SETTING. The first pass read the name as a rustic
  // vibe and produced a mud paddock with a STRAW bale in it — straw is not wood.
  // Every prop in both Wood themes is a wooden object and one of the two grounds is
  // literally boards, so the league reads as the material it is named after. The
  // ladder is Wood → Copper → Tin → Bronze → Iron → Silver → Gold; each league's
  // arenas should look like their own rung.
  plankyard: {
    id: 'plankyard',
    name: 'Boarded ring',
    ground: '/field/ground-plankyard.jpg',
    groundScale: 'auto 34%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
      crates: '/field/prop-crates.png',
      barrel: '/field/prop-barrel.png',
      cart: '/field/prop-cart.png',
      sawhorse: '/field/prop-sawhorse.png',
    },
  },
  timberyard: {
    id: 'timberyard',
    name: 'Timber yard',
    ground: '/field/ground-sawdust.jpg',
    groundScale: 'auto 30%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
      logstack: '/field/prop-logstack.png',
      stump: '/field/prop-stump.png',
      palisade: '/field/prop-palisade.png',
    },
  },

  // ── Copper: ore and smelting ──────────────────────────────────────────────
  // ⚠️ THE LEAGUE'S OWN MATERIAL AGAIN. Wood was timber and boards; Copper is the
  // stuff copper is made FROM and made INTO — blue-green malachite ore, raw ingots,
  // crucibles, slag. A player should be able to name the league from a still frame
  // of the ground, which is the test every rung has to pass.
  //
  // ⚠️ TWO THEMES FOR THREE ARENAS, which is the many-to-one design working as
  // intended: the washfloor is wet stone, the smelt yard is soot and cinders, and
  // the third arena reuses one of them with a different LAYOUT and different cover.
  washfloor: {
    id: 'washfloor',
    name: 'Ore-washing floor',
    ground: '/field/ground-washfloor.jpg',
    groundScale: 'auto 32%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
      sluice: '/field/prop-sluice.png',
      orepile: '/field/prop-orepile.png',
    },
  },
  smeltyard: {
    id: 'smeltyard',
    name: 'Smelting yard',
    ground: '/field/ground-smeltyard.jpg',
    groundScale: 'auto 30%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
      crucible: '/field/prop-crucible.png',
      anvil: '/field/prop-anvil.png',
      orebin: '/field/prop-orebin.png',
      slagheap: '/field/prop-slagheap.png',
      ingots: '/field/prop-ingots.png',
      orepile: '/field/prop-orepile.png',
    },
  },

  // ── Tin: stream works and blowing houses ──────────────────────────────────
  // ⚠️ TIN HAS TO LOOK COLD, because Copper is hot. Tin is won from STREAM WORKS
  // rather than deep mines — gravel washed through leats and pools, then blown into
  // pale silvery-white metal. So: grey water, washed pebbles, white metal and ash,
  // against Copper's fire, soot and green patina. Two leagues in a row of "an
  // industrial yard" would be one league with two names.
  streamworks: {
    id: 'streamworks',
    name: 'Tin streamworks',
    ground: '/field/ground-streamworks.jpg',
    groundScale: 'auto 32%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
      leat: '/field/prop-leat.png',
      orebin: '/field/prop-orebin.png',
      gravelbar: '/field/prop-gravelbar.png',
    },
  },
  blowinghouse: {
    id: 'blowinghouse',
    name: 'Blowing house',
    ground: '/field/ground-blowinghouse.jpg',
    groundScale: 'auto 30%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
      blowingfurnace: '/field/prop-blowingfurnace.png',
      anvil: '/field/prop-anvil.png',
      tinblocks: '/field/prop-tinblocks.png',
      gravelbar: '/field/prop-gravelbar.png',
    },
  },

  // ── Bronze: the alloy, and its props come from BOTH parents ───────────────
  // ⚠️ THE LADDER IS AN ALLOY STORY AND BRONZE IS WHERE IT PAYS OFF. Wood → Copper →
  // Tin → BRONZE, and bronze IS copper and tin. So these two themes are stocked from
  // BOTH earlier leagues — Copper's ore piles, crucibles, ingots and slag standing
  // beside Tin's gravel bars and cast blocks — which is both the correct flavour and
  // the reason four new arenas cost two images instead of ten.
  //
  // ⚠️ THE GROUND IS STILL ITS OWN, THOUGH, AND THAT PART IS NOT OPTIONAL. Reusing
  // Copper's floor would make Bronze read as a fourth Copper arena; the ground is what
  // a player names a league from in a still frame. Bronze's is the alloy visibly
  // happening: green copper scale and pale tin dust trodden into warm gold-brown.
  alloyfloor: {
    id: 'alloyfloor',
    name: 'Alloy floor',
    ground: '/field/ground-alloyfloor.jpg',
    groundScale: 'auto 31%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
      crucible: '/field/prop-crucible.png',
      ingots: '/field/prop-ingots.png',
      orepile: '/field/prop-orepile.png',
      tinblocks: '/field/prop-tinblocks.png',
      slagheap: '/field/prop-slagheap.png',
    },
  },
  bellyard: {
    id: 'bellyard',
    name: 'Bell yard',
    ground: '/field/ground-bellyard.jpg',
    groundScale: 'auto 29%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
      crucible: '/field/prop-crucible.png',
      gravelbar: '/field/prop-gravelbar.png',
      tinblocks: '/field/prop-tinblocks.png',
      slagheap: '/field/prop-slagheap.png',
      blowingfurnace: '/field/prop-blowingfurnace.png',
      anvil: '/field/prop-anvil.png',
    },
  },

  // ── Iron: the forge circuit ───────────────────────────────────────────────
  // ⚠️ IRON MUST NOT BE COPPER AGAIN, AND THE GROUND IS THE ONLY THING THAT CAN SAY SO.
  // Iron shares its 3v3 board size with Bronze, so the two cannot be told apart by scale;
  // and Copper is already the warm-orange smelting league. Iron is the FORGE — hotter than
  // Copper and blacker: iron scale, hammer soot, raked clinker, almost colourless.
  //
  // ⚠️ AND IT ADDS NO PROPS AT ALL, WHICH IS WHAT THE ARCHITECTURE RULE BOUGHT. Every
  // piece on an Iron board is shared dressed stone re-tinted by `venue.masonry`. A league
  // used to cost ten images; it now costs two grounds and a lamp.
  // ══ THE GRAND CIRCUIT — twenty 5v5 grounds, shared Platinum to Apex ════
  // ⚠️ NAMED FOR STONE, NOT FOR A LEAGUE, and that is the whole structural point. Every
  // theme above belongs to one circuit because the circuit's MATERIAL is its name. These
  // twenty belong to four leagues at once, so they cannot be. What separates them is the
  // stone they are cut from — and colour is the only axis left once team size stops growing.
  //
  // ⚠️ AND THE PROP MAP IS THE WHOLE LIBRARY. A league below draws on one family because
  // that family IS the league; the grand circuit is where a board may be a colonnade court,
  // a walled ring or an overgrown ruin, so every kind in the game has to be reachable from
  // every one of these themes.
  porphyry: {
    id: 'porphyry',
    name: 'Porphyry court',
    ground: '/field/ground-porphyry.jpg',
    groundScale: 'auto 30%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  serpentine: {
    id: 'serpentine',
    name: 'Serpentine court',
    ground: '/field/ground-serpentine.jpg',
    groundScale: 'auto 30%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  basalt: {
    id: 'basalt',
    name: 'Basalt ring',
    ground: '/field/ground-basalt.jpg',
    groundScale: 'auto 26%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  alabaster: {
    id: 'alabaster',
    name: 'Alabaster court',
    ground: '/field/ground-alabaster.jpg',
    groundScale: 'auto 32%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  slateyard: {
    id: 'slateyard',
    name: 'Slate yard',
    ground: '/field/ground-slateyard.jpg',
    groundScale: 'auto 28%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  travertine: {
    id: 'travertine',
    name: 'Travertine court',
    ground: '/field/ground-travertine.jpg',
    groundScale: 'auto 30%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  granite: {
    id: 'granite',
    name: 'Granite court',
    ground: '/field/ground-granite.jpg',
    groundScale: 'auto 28%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  jasper: {
    id: 'jasper',
    name: 'Jasper court',
    ground: '/field/ground-jasper.jpg',
    groundScale: 'auto 30%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  amethystine: {
    id: 'amethystine',
    name: 'Amethystine court',
    ground: '/field/ground-amethystine.jpg',
    groundScale: 'auto 28%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  malachite: {
    id: 'malachite',
    name: 'Malachite court',
    ground: '/field/ground-malachite.jpg',
    groundScale: 'auto 30%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  chequer: {
    id: 'chequer',
    name: 'Chequer court',
    ground: '/field/ground-chequer.jpg',
    groundScale: 'auto 34%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  mosaic: {
    id: 'mosaic',
    name: 'Mosaic court',
    ground: '/field/ground-mosaic.jpg',
    // ⚠️ 30, NOT 18, AND THE FIRST RENDER IS WHY. The reasoning for 18 was sound on paper —
    // a mosaic only reads as tesserae if the tiles are tiny — and it produced a plain buff
    // floor with no figure at all: at that scale the interlace is finer than the camera can
    // resolve and averages to a flat colour. The whole point of this ground was PATTERN as a
    // second axis to sort twenty boards on, and at 18 it contributed nothing.
    groundScale: 'auto 30%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  rosestone: {
    id: 'rosestone',
    name: 'Rose court',
    ground: '/field/ground-rosestone.jpg',
    groundScale: 'auto 30%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  onyx: {
    id: 'onyx',
    name: 'Onyx court',
    ground: '/field/ground-onyx.jpg',
    // ⚠️ 20, NOT 32, AND IT IS THE OPPOSITE PROBLEM TO THE MOSAIC'S. Onyx's banding is the
    // highest-contrast figure in the pool, and at slab scale it drew as broad diagonal
    // streaks that competed with the cover standing on them — a floor loud enough to be read
    // BEFORE the props is a floor that has stopped being a floor. Tightening the tile turns
    // the same bands into grain.
    groundScale: 'auto 20%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  verdite: {
    id: 'verdite',
    name: 'Verdite court',
    ground: '/field/ground-verdite.jpg',
    groundScale: 'auto 28%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  // ══ GOLD — the pleasance circuit (4v4) ═════════════════════════════════
  // ⚠️ WARM WHERE SILVER IS NEUTRAL, AND THAT IS THE WHOLE SEPARATION AT THIS TEAM SIZE.
  // Both leagues field four and share a grid; Silver is dry pale limestone under a clean
  // even lamp, Gold is honey sandstone and raked gravel with dark hedging on it. The floor
  // family does the rest.
  gildedcourt: {
    id: 'gildedcourt',
    name: 'Gilded court',
    ground: '/field/ground-gildedcourt.jpg',
    groundScale: 'auto 32%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  parterre: {
    id: 'parterre',
    name: 'Parterre',
    ground: '/field/ground-parterre.jpg',
    groundScale: 'auto 26%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  // ══ SILVER — the assay circuit (4v4) ═══════════════════════════════════
  // ⚠️ PALE, BUT NOT TIN AGAIN. Tin is the game's other whitish league — streamworks at
  // luminance 110, saturation 0.13, a wet blue-grey cobble. Silver is DRY and warm-neutral:
  // dressed limestone and swept bone ash, harder-lit, four rungs further up. Two pale
  // circuits that read the same would waste both.
  assayfloor: {
    id: 'assayfloor',
    name: 'Assay floor',
    ground: '/field/ground-assayfloor.jpg',
    groundScale: 'auto 30%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  cupelhearth: {
    id: 'cupelhearth',
    name: 'Cupel hearth',
    ground: '/field/ground-cupelhearth.jpg',
    groundScale: 'auto 28%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  forgefloor: {
    id: 'forgefloor',
    name: 'Forge floor',
    ground: '/field/ground-forgefloor.jpg',
    groundScale: 'auto 30%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },
  cinderyard: {
    id: 'cinderyard',
    name: 'Cinder yard',
    ground: '/field/ground-cinderyard.jpg',
    groundScale: 'auto 28%',
    props: {
      wall: '/field/prop-wall.png',
      pillar: '/field/prop-pillar.png',
      gate: '/field/prop-gate.png',
      dais: '/field/prop-dais.png',
      obelisk: '/field/prop-obelisk.png',
      ruinedwall: '/field/prop-ruinedwall.png',
      brokenpillar: '/field/prop-brokenpillar.png',
      colonnade: '/field/prop-colonnade.png',
      brokencolonnade: '/field/prop-brokencolonnade.png',
      hedge: '/field/prop-hedge.png',
      urn: '/field/prop-urn.png',
      topiary: '/field/prop-topiary.png',
      arbour: '/field/prop-arbour.png',
      flowerbed: '/field/prop-flowerbed.png',
      fountain: '/field/prop-fountain.png',
      tree: '/field/prop-tree.png',
      bush: '/field/prop-bush.png',
      vinewall: '/field/prop-vinewall.png',
    },
  },

  // ── The three original test arenas ────────────────────────────────────────
  // ⚠️ KEPT ON THE ORIGINAL GRASS/BOULDER ART. These are measurement fixtures
  // (`tools/mapsweep.ts`, `navdiag`, `escape`) whose numbers are quoted in
  // maps.ts and BALANCING.md; re-skinning them changes nothing they measure but
  // does make those quotes harder to trust. They are not league content.
  proving: {
    id: 'proving',
    name: 'Proving ground',
    ground: '/field/arena-grass.jpg',
    groundScale: 'auto 34%',
    props: {},
  },
}

export const themeById = (id: string): ArenaTheme => THEMES[id] ?? THEMES.proving

// ── SURFACES ────────────────────────────────────────────────────────────────
/**
 * What THIS CUP's floor is laid with, as opposed to what circuit it is on.
 *
 * ⚠️ A DIFFERENT QUESTION FROM `ArenaTheme.ground`, AND THE SPLIT IS THE WHOLE POINT.
 * A theme's ground says WHICH LEAGUE — Copper's wash floor, Bronze's alloy floor — and
 * there is one per theme because that is the thing a player names a league from in a
 * still frame. A surface says what this particular ground is PAVED WITH, so two cups on
 * the same circuit can be a sand pit and a flagged court without either stopping being
 * Bronze: the props, the venue stone and the lamp still carry the league.
 *
 * ⚠️ AND IT IS FIVE IMAGES FOR FORTY ARENAS. The alternative — a bespoke ground per cup —
 * is ~50 textures for a difference that reads as "still the Gold circuit". Variety costing
 * one image per LEAGUE is worth drawing; variety costing one per CUP is not. Same
 * reasoning that made the dressed-stone furniture shared rather than redrawn per league.
 *
 * ⚠️ THEY MUST STAY QUIETER THAN A LEAGUE GROUND. A texture used beneath ten palettes has
 * to be the least assertive thing in the frame — `proc_arena_art.py:check_ground_palette`
 * holds them to it, and Bronze's 0.57-saturation first floor is why the check exists.
 */
export type SurfaceId = 'sand' | 'concrete' | 'timber' | 'flagstone' | 'packedearth'

export const SURFACES: Record<SurfaceId, { name: string, ground: string, groundScale: string }> = {
  // ⚠️ THE SCALES ARE PER-SURFACE BECAUSE THE FEATURE SIZE IS. A tile is a percentage of
  // the board's HEIGHT, so 30% on a 42-unit 5v5 board means one tile every 12.6 world
  // units — fine for a gravel grain and hopeless for a plank, which came out as a faint
  // grey grid with no timber in it at all. Coarse features need a big tile; fine ones do
  // not. Judged in the 3D scene, never from the texture on its own.
  sand: { name: 'Raked sand', ground: '/field/ground-sand.jpg', groundScale: 'auto 45%' },
  concrete: { name: 'Poured concrete', ground: '/field/ground-concrete.jpg', groundScale: 'auto 34%' },
  timber: { name: 'Timber deck', ground: '/field/ground-timber.jpg', groundScale: 'auto 58%' },
  flagstone: { name: 'Flagstone', ground: '/field/ground-flagstone.jpg', groundScale: 'auto 36%' },
  packedearth: { name: 'Packed earth', ground: '/field/ground-packedearth.jpg', groundScale: 'auto 28%' },
}

/**
 * The floor an arena actually renders — its own surface if it declares one, else its
 * league's ground.
 *
 * ⚠️ EVERY RENDERER MUST GO THROUGH THIS. There are three consumers of the ground
 * (`Deploy.tsx`, `TamerArena.tsx`, `three/scene3d.ts`) and a theme authored in some of
 * them but not all has already shipped once — Bronze rendered correctly in 2D while the
 * 3D scene fell back to grass lighting. One resolver is what stops that recurring.
 */
export const groundFor = (
  theme: ArenaTheme, surface?: SurfaceId,
): { ground: string, groundScale: string } =>
  (surface && SURFACES[surface]) || theme

/** Sprite for one piece of cover, with the never-invisible fallback. */
export const propSprite = (theme: ArenaTheme, kind?: ObstacleKind): string =>
  (kind && theme.props[kind]) || FALLBACK_PROP
