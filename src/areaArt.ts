// Area backdrops (v0.79) — one painted scene per screen, shown FULL-BLEED behind
// the UI. Same painterly matte-painting look and 1400x788 JPEG format as the
// league arena backgrounds (see leagueArt.ts), so the two sets read as one world.
//
// Legibility: these sit behind dense admin UI (shop rows, dropdowns, lists), so
// `.app` paints a heavy theme-aware scrim over the image — see `.areabg` in
// styles.css. The art carries mood and location identity; the cards stay opaque.
export type AreaArtKey =
  | 'town' | 'market' | 'shop' | 'stables' | 'breeding' | 'halloffame' | 'lab' | 'title'

export const AREA_BACKGROUND: Record<AreaArtKey, string> = {
  town: '/backgrounds/area-town.jpg',
  market: '/backgrounds/area-market.jpg',
  shop: '/backgrounds/area-shop.jpg',
  stables: '/backgrounds/area-stables.jpg',
  breeding: '/backgrounds/area-breeding.jpg',
  halloffame: '/backgrounds/area-halloffame.jpg',
  lab: '/backgrounds/area-lab.jpg',
  title: '/backgrounds/area-title.jpg',
}

export const areaBackgroundFor = (key?: AreaArtKey): string | undefined =>
  key ? AREA_BACKGROUND[key] : undefined

// Which backdrop belongs to a Town sub-area. Kept here so TownArea's local
// state maps to art in one place.
export const TOWN_AREA_ART: Record<string, AreaArtKey> = {
  hub: 'town', market: 'market', shop: 'shop',
  breeding: 'breeding', retirement: 'halloffame', lab: 'lab',
}
