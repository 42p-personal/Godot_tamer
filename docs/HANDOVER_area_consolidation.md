# Handover — move ability geometry onto `Move.area`, retire the `spatial.ts` side table

**Status:** not started (two attempts reverted, see *Traps* — both were scripting
failures, not design problems).
**Branch:** `3doverhal`. **Type:** pure refactor, **no gameplay change**.
**Acceptance:** `npm test` 143 green · `npx tsc --noEmit` clean · `npm run build`
clean · `npx tsx tools/sweep40.ts` unchanged at **40/40 @ 19.8s**.

---

## Why

`src/tamerengine/spatial.ts` keys a move's geometry by **move NAME**:

```ts
export const SPATIAL_MOVES: Record<string, MoveSpatial> = {
  'Cleave': { area: { shape: 'cone', centre: 'self', angle: 100, range: 3.6 } },
  ...
}
```

So an ability's AoE is attached by string match rather than being part of the
ability. **Rename a move and its area silently detaches** — the move keeps
working, just as a single-target one. That is the quietest possible way for
content to break, and `validate.ts` cannot see it.

Only `area` moves in this pass. The other `MoveSpatial` fields (`move`, `push`,
`pull`, `root`, `slow`, `zone`, `fade`, `backstab`, `haulAlly`) stay in the side
table — they are a smaller surface and not what the geometry work needs.

---

## The work

### 1. `src/core.ts` — add the field

`Move` is at **line 222**, `MoveSpatial` at **296**, `MoveArea` at **326**.

- Add `area?: MoveArea` to **`Move`** (put it after `effects?: MoveEffects`).
- Delete `area?: MoveArea` from **`MoveSpatial`** — currently **line 306**.

> ⚠️ **Both interfaces end up declaring `area?: MoveArea` mid-edit, and `Move`
> comes FIRST in the file.** A `count=1` / first-match edit removes the wrong
> one. This bit attempt #2. Target by interface, or by index into the list of
> matches, and assert there are exactly two before deleting the second.

`src/moves.ts` needs no type change — `type Row = Omit<Move, 'id' | 'stat'>`
(line 39) inherits it.

### 2. Splice the geometry onto the moves

Dump the table first so the specs come from the module, never a regex over source:

```ts
// tools/_area.ts (throwaway)
import { SPATIAL_MOVES } from '../src/tamerengine/spatial'
const out = Object.fromEntries(
  Object.entries(SPATIAL_MOVES).filter(([, sp]) => sp.area).map(([n, sp]) => [n, sp.area]))
require('fs').writeFileSync(process.argv[2], JSON.stringify(out))
```

- **28** entries in `SPATIAL_MOVES` carry an `area`; **27** live in
  `src/moves.ts`, **1** is `Bulwark's Challenge`.
- **7 more** are declared inline inside `fieldMoves.ts`'s own `spatial: { … }`
  blocks. These must be lifted onto the move too, or `MoveSpatial.area` cannot
  be deleted.

> ⚠️ **Splice by STRING INDEX. Do not use a regex replacement template.**
> Attempt #1 used `re.subn(r"(, desc: )", ", area: {…}\1", …)`; the `\1` became a
> control character, swallowed `, desc:` on 27 lines and corrupted `moves.ts`.
> Find `line.find(', desc:')` (fall back to `line.rfind(' }')`) and concatenate.

> ⚠️ **`Bulwark's Challenge` is written with DOUBLE quotes** because of the
> apostrophe: `{ name: "Bulwark's Challenge", … }`. A `name: '([^']*)'` pattern
> misses it silently — attempt #2 spliced 27 of 28 and only caught it because
> the script printed its own misses. Print unresolved names; do not trust a count.

### 3. `src/tamerengine/engine.ts` — two read sites

```
1129:  const victims = sp?.area ? areaVictims(u, aim, sp.area)   ->  mv.area
1258:  const areaSpec = spatialOf(mv.name)?.area                 ->  mv.area
```

### 4. `src/tamerengine/spatial.ts` — remove `area` from all 28 entries

> ⚠️ **Brace-aware removal only.** `,?\s*area: \{[^}]*\}` leaves a stray leading
> comma when `area` is the FIRST key (`{ area: {…}, root: 1.8 }` → `{ , root: 1.8 }`).
> Braces still balance, so a brace count says "fine" while `tsc` reports a
> confusing error 100 lines later. Walk to the matching `}` and drop exactly one
> separating comma, whichever side carried it. Entries left empty (`{}`) are
> fine — keep them.

### 5. Tests — four call sites read `sp.area`

| file | line | change |
|---|---|---|
| `spatial.test.ts` | 36 | `sp.area` → the move's own `area` |
| `spatial.test.ts` | 141 | `!spatialOf(m.name)?.area` → `!m.area` |
| `spatial.test.ts` | 148, 151 | `spatialOf(n)!.area!.centre` → look the move up in `ALL_MOVES` |
| `spatial.test.ts` | 157, 167–168 | iterate `ALL_MOVES` instead of `SPATIAL_MOVES` |
| `fieldMoves.test.ts` | 71 | `sp.area` → `m.area` (`m` is in scope) |

### 6. Worth adding while here

`validate.ts` gains the guard this refactor makes possible: **every
`target: 'allEnemies'` move must carry an `area`.** That rule exists today only
as a comment in `spatial.ts` ("⚠️ Every allEnemies move needs an `area` or it has
no geometry"), and it was violated once already (`Dirge`). On the move it is
finally checkable.

---

## Traps, in one list

1. `Move` and `MoveSpatial` both declare `area?: MoveArea` mid-edit — `Move` is first.
2. Never use regex replacement templates on `moves.ts`; splice by index.
3. `Bulwark's Challenge` uses double quotes.
4. `fieldMoves.ts` has 7 inline areas, easy to miss — `grep -c "area: {"` each file.
5. Removing `area:` from `spatial.ts` needs brace-aware scanning, not `[^}]*`.
6. Balanced brace COUNTS do not prove correct nesting.
7. Print what a data pass **missed**. A half-applied pass looks deliberate — the
   same failure mode hit `LINE_OF` earlier, where a regex silently skipped 70 of
   137 moves because keys are only quoted when they contain a space.

## Verify

```bash
npx tsc --noEmit && npm test && npm run build
npx tsx tools/sweep40.ts          # expect 40/40 @ ~19.8s — unchanged
npx tsx tools/inert.ts            # expect 0 inert effect keys
```

A parity check is worth running mid-way: every name in the dumped `areas.json`
should appear on exactly one move with an identical spec, and
`Object.values(SPATIAL_MOVES).filter(sp => sp.area)` should end at zero.
