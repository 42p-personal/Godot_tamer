// League-themed arena backgrounds (2026-07-25) — one wide backdrop per
// league, painted to match each league's existing cupLore/CIRCUIT_LORE_FLAVOUR
// setting in town.ts (Wood's muddy paddock, Iron's forge-district, Silver's
// hammered-silver-crescent banner, etc.) so the fight screen actually looks
// like the tournament it's part of. Files live in `public/backgrounds/
// <slug>.jpg`, ~1400px wide, painterly concept-art style (deliberately NOT
// pixel art — a painted backdrop behind crisp pixel-art sprites is a common,
// readable combination, and it lets the background stay atmospheric/soft
// without competing with the foreground for detail).
export const LEAGUE_BACKGROUND: Partial<Record<string, string>> = {
  Wood: '/backgrounds/wood.jpg',
  Copper: '/backgrounds/copper.jpg',
  Tin: '/backgrounds/tin.jpg',
  Bronze: '/backgrounds/bronze.jpg',
  Iron: '/backgrounds/iron.jpg',
  Silver: '/backgrounds/silver.jpg',
  Gold: '/backgrounds/gold.jpg',
  Platinum: '/backgrounds/platinum.jpg',
  Masters: '/backgrounds/masters.jpg',
  'Tamer Elite': '/backgrounds/tamer-elite.jpg',
  'Tamers Apex': '/backgrounds/tamers-apex.jpg',
}

// Sandbox and any other league-less battle falls back to the Wood backdrop
// (the plainest/most neutral of the ten) rather than showing no background.
export const backgroundFor = (league?: string): string => (league && LEAGUE_BACKGROUND[league]) || LEAGUE_BACKGROUND.Wood!
