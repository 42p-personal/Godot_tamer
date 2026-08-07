# Monster Tamer

A browser-based monster raising, breeding & auto-battler sim. Inspired by **Monster Rancher**
(raising / breeding / lifespan) and **Teamfight Manager** (battles auto-resolve — you build the
monster, you don't pilot it).

Full design: [`docs/GAME_DESIGN.md`](docs/GAME_DESIGN.md) · Roadmap: [`docs/OUTLINE.md`](docs/OUTLINE.md)

## Run it

```bash
npm install
npm run dev      # dev server at http://localhost:5173
npm run build    # type-check + production build
```

## What the prototype does (M1 slice)

- **Seed → monster generator** — a seed word deterministically produces a monster (species, sex,
  stats, class, sprite). Same seed → same monster.
- **Training slider** — invest points to raise stats along the species' lean, unlocking learned
  moves (at levels 40/90/160/…/920) and the species ultimate at 600.
- **1v1 auto-battle** — deterministic simulation using stats, the 3-move loadout, accuracy,
  cooldowns, and status effects (burn/poison/etc.), with a full battle log.

## Code map (`src/`)

| File | Contents |
|------|----------|
| `core.ts` | Types, seeded RNG, leagues, classes, status list, learn ladder |
| `species.ts` | The 20 base species (stats, lifespans, innate abilities, ultimates) |
| `moves.ts` | The 60-skill shared learned-move pool |
| `monster.ts` | Seed→monster generation + derived combat values |
| `battle.ts` | The 1v1 auto-battle simulator |
| `App.tsx` | UI: stables, monster cards, pixel sprite, battle runner |

Not yet built (see the roadmap): the weekly calendar, tournaments/leagues progression, breeding &
fusion, retirement, team formats (2v2+), and balance tuning.
