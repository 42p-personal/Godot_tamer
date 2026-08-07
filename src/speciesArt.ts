// Real hand-generated (AI pixel-art) sprites for the 30 base species (2026-07-25).
// One image per species, adult-only — see CLAUDE.md's "adult-only" decision:
// generating every life stage independently produced worse art (chained
// identity-preservation across stages pulled adult faces toward "cute"), so
// every stage now just displays this same adult image; Elder/Retiree keep
// applying the existing aging CSS filter over it, same as Sprite.tsx already
// did for the old hand-drawn grids. Files live in `public/sprites/<id>.png`,
// 320x320 RGBA, trimmed to content + a small even margin.
// The 15 exclusive-body species (Draconic/Abyssal/Mythical) got their own
// real-art pass on 2026-07-25 too, following this exact recipe — every base
// and exclusive species now renders real art; the sprites.ts pixel-grid path
// is retained only as Sprite.tsx's structural fallback (still required by
// the SPRITES[body] lookup for type-safety) and is no longer reached by any
// species in practice.
export const SPECIES_ART: Partial<Record<string, string>> = {
  kongrath: '/sprites/kongrath.png',
  aegisox: '/sprites/aegisox.png',
  maneleo: '/sprites/maneleo.png',
  grivvel: '/sprites/grivvel.png',
  ursath: '/sprites/ursath.png',
  pinguox: '/sprites/pinguox.png',
  strixil: '/sprites/strixil.png',
  balaenix: '/sprites/balaenix.png',
  corvaan: '/sprites/corvaan.png',
  larkessa: '/sprites/larkessa.png',
  bruxaroo: '/sprites/bruxaroo.png',
  koalio: '/sprites/koalio.png',
  quokkade: '/sprites/quokkade.png',
  sylvaglide: '/sprites/sylvaglide.png',
  tazzik: '/sprites/tazzik.png',
  maelurk: '/sprites/maelurk.png',
  nautilux: '/sprites/nautilux.png',
  carcharun: '/sprites/carcharun.png',
  mantaris: '/sprites/mantaris.png',
  lanterix: '/sprites/lanterix.png',
  scarabrute: '/sprites/scarabrute.png',
  mantevoke: '/sprites/mantevoke.png',
  arachnyx: '/sprites/arachnyx.png',
  vespera: '/sprites/vespera.png',
  odonatra: '/sprites/odonatra.png',
  crocmaw: '/sprites/crocmaw.png',
  iguanor: '/sprites/iguanor.png',
  serpwyn: '/sprites/serpwyn.png',
  geckari: '/sprites/geckari.png',
  tortavos: '/sprites/tortavos.png',
  pyraxon: '/sprites/pyraxon.png',
  frostwyren: '/sprites/frostwyren.png',
  stormlerath: '/sprites/stormlerath.png',
  verdantdrake: '/sprites/verdantdrake.png',
  voidmaw: '/sprites/voidmaw.png',
  tenebrae: '/sprites/tenebrae.png',
  abyssomancer: '/sprites/abyssomancer.png',
  lurkerss: '/sprites/lurkerss.png',
  'chrono-leviathan': '/sprites/chrono-leviathan.png',
  cephalumbra: '/sprites/cephalumbra.png',
  titanrex: '/sprites/titanrex.png',
  stellarion: '/sprites/stellarion.png',
  wisdomkeeper: '/sprites/wisdomkeeper.png',
  'archmage-aleph': '/sprites/archmage-aleph.png',
  harmonybringer: '/sprites/harmonybringer.png',
  // Fusion species (v0.7) — generated via Codex image-gen, same style.
  grendscale: '/sprites/grendscale.png',
  vipramane: '/sprites/vipramane.png',
  thornhide: '/sprites/thornhide.png',
  runewyrm: '/sprites/runewyrm.png',
  basilroar: '/sprites/basilroar.png',
  thunderoc: '/sprites/thunderoc.png',
  galewing: '/sprites/galewing.png',
  tidecaller: '/sprites/tidecaller.png',
  maelstrom: '/sprites/maelstrom.png',
  brinehowl: '/sprites/brinehowl.png',
  chitinhop: '/sprites/chitinhop.png',
  broodmother: '/sprites/broodmother.png',
  mantiskin: '/sprites/mantiskin.png',
  resinback: '/sprites/resinback.png',
  swarmherd: '/sprites/swarmherd.png',
  // Primeval — the prestige fusion (v0.88), same recipe as every sprite above.
  aeonrex: '/sprites/aeonrex.png',
  stellavore: '/sprites/stellavore.png',
  chronoshell: '/sprites/chronoshell.png',
  originmage: '/sprites/originmage.png',
  worldsong: '/sprites/worldsong.png',
}
