# Handover — Monster Tamer, v0.89 → v0.90 (in progress)

Session handover. `CLAUDE.md` is the durable project guide and is **current to
v0.89**; `docs/BALANCING.md` is the balance ledger and is current through the
v0.90 food pass. This file covers only what those two don't: repo state, what is
unshipped, and the decisions/gotchas from this session.

---

## 1. Repo state — READ FIRST

| | |
|---|---|
| Branch | `feat/v0.89-tamers-apex` (checked out, synced with origin) |
| `origin/main` | `e55892d` (v0.861) |
| Open PR | **#1** → `main`, 18 commits, **Cloudflare check green** |
| `APP_VERSION` | `0.89` — **not bumped for the v0.90 training/food work** |
| Working tree | clean |
| Deployed | **nothing from this session** — production is still v0.861 |

**Local `main` is also 4 commits ahead of `origin/main`** (it holds the same
first four commits, which are now safely on the branch). Harmless; reconciles on
merge. Reset it to `origin/main` if you want main clean.

**PR #2** (vite 5 → 8) was stacked on this branch and is **merged** — that is what
turned the Cloudflare check green. Its branch is deleted.

`GH_TOKEN` is a fine-grained PAT. It initially lacked *Pull requests: write* (403 on
create); the permission has since been added and PR creation works. If a 403 comes
back, that's the setting to check — editing a fine-grained PAT's permissions does
not change the token value, so nothing needs re-exporting.

### Before shipping
1. Decide the version bump (the v0.90 work is unversioned).
2. Merge PR #1 into `main`. **Deploy is now automatic** — the vite 8 migration
   fixed the Cloudflare auto-build, so pushing `main` builds and ships it.
   Manual `wrangler` is the fallback only; if you use it, see the deploy section
   in `CLAUDE.md` for the Preview-misroute trap.
3. Update `CLAUDE.md` to v0.90 (it stops at v0.89).

---

## 2. What shipped in v0.89 (documented in CLAUDE.md, verified, committed)

Tamers Apex (11th league, cap 1400) + steepened curve (Gold 750 / Platinum 900 /
Masters 1000 / TE 1200); Primeval prestige fusion (5 species, real sprites, roster
65); the gen-1 cap ladder; the breeding ladder by heritage; prestige market
scarcity; mid-game difficulty nudges; summit-gate relief; the resume-mid-cup fix;
the Lab fusion nudge; the Apex backdrop.

**Browser-verified** (crafted saves, zero console errors): resume-mid-cup resumed
correctly at "Match 2 of 3" and rebuilt the ✅/🔸 strip from a save with a
deliberately stale `doneThrough`; the Lab fusion nudge; the Primeval sprite at
full resolution; all 11 leagues in the calendar; the arena backdrop pipeline.

---

## 3. What is v0.90 (NOT in CLAUDE.md yet — document it when you bump)

### Training tiers
| Tier | Shape | Net | Stamina | net/stam |
|---|---|---|---|---|
| basic | +6 | 6 | **15** (was 10) | 0.40 |
| intensive | +12 / −4 | 8 | 25 | 0.32 |
| **diverse** (NEW) | **+8 / +8** | **16** | **35** | 0.46 |
| extreme | **+24 / −4 / −4** (was +20/−6/−6) | **16** | 35 | 0.46 |

- **Diverse and extreme are deliberate mirrors** — same net, same cost, opposite
  shape. Extreme spikes one stat and pays out of two others; diverse splits the
  total across a pair and pays nothing. Neither is stronger; you pick a shape.
- **Basic is now the LEAST efficient tier** (0.40 < 0.46), so the safe option is
  no longer the quietly optimal one and the manuals buy real throughput.
- **📗 Diverse Training Manual, 800g** (`diverseUnlocked`), priced level with the
  **📕 Extreme Manual, repriced 1200 → 800g**. Siblings, not a ladder.

**The six diverse drills** — Pilgrim's Burden STR+WIS · The Cannon Crew STR+INT ·
Trapeze Hours DEX+CON · Blindfold Forms DEX+WIS · Taking the Fall CON+CHA ·
Illusionist's Patter INT+CHA.

> ⚠️ These six are **exactly the complement of the 9 CLASSES stat-pairs**. That
> single choice gives BOTH properties at once: all off-archetype (0/6 class pairs)
> AND perfectly even coverage (every stat ×2). **Moving any one pair breaks one or
> both** — this was rediscovered the hard way over ~5 edits. The file header in
> `src/drills.ts` records it.

### Food
Vigor Melon **200 → 90g**, Bliss Berry **250 → 90g**. Both now sit just above the
75g training foods, so a feeding week is a real three-way call: train harder
(+30% pair, −15 stam), recover (+30 stam), or lift mood (+3 happiness, persists).
Golden Truffle stays 500g — a cup-day gamble, not weekly upkeep.

### Sim bot (`sim/bot.ts`)
- **Yield-based drill choice** replaced the fixed tier ladder — scores every
  affordable drill by useful yield (gains on build stats count; gains on capped
  stats are wasted; losses count only if they land on the build). Required, or a
  pair tier is invisible to it.
- **Feeding brain** rewritten for the 90g premiums (see §5 for the trap).
- Also carries: license earmark, fusion earmark, early Market Scout purchase.

### Latest sim — 25y × 6, best run to date
`TE ×3 / Masters ×2 / Tamers Apex ×1` (seed 2, yr 15, **best stat 1652**), fusion
in 5 of 6 seeds, 3–4 breeds each, money fully invested (236–1620g).

---

## 4. Standing gotchas

- **Rivals do NOT follow the gen-1 cap ladder.** Their strength is
  `league cap × rivalBudgetMult(i)` as a **total-stat budget per monster with no
  per-stat cap**. Any `LEAGUES` edit moves every rival field with it.
- **The Cloudflare auto-build is FIXED** (vite 5 → 8, PR #2, merged). Two things
  must not regress or it breaks again: `npm ls esbuild --all` must show ONE
  version, and `.node-version`/`engines` must keep pinning Node ≥22.12 (vite 8
  requires it). The earlier `overrides` attempt — forcing esbuild 0.28.1 under
  vite@5 — deduped the tree and then broke vite@5's `esbuild-transpile` with 124
  transform errors. **Upgrade vite, don't pin esbuild beneath it.**
- **`boostConstitution` derives its CON target from the league cap**, so changing
  `LEAGUES` legitimately moves high-`train` goldens. `3v3-high` was recaptured for
  exactly this reason — check the inline note before assuming a regression.
- **Prestige bodies ARE generated by `generateMonster`** (unlike fusion bodies), so
  prestige base-stat edits move goldens. Fusion/Primeval edits do not.
- **Golden recaptures are legitimate when species/league DATA changes** — the
  engine is untouched. Recapture deliberately and note why inline.
- Screenshots are often unavailable; prefer `read_page` / JS DOM probes. For
  layering bugs use a paint-order probe (`document.elementsFromPoint`), since a
  `pointer-events: none` overlay passes every hit-test while hiding the UI.

---

## 5. Design signals worth acting on (found by sim, not yet addressed)

1. **Cheap premium food can wreck an economy invisibly.** The bot's first feeding
   policy ("melon whenever below full effectiveness") cost it 2–5 breeds, 5 of 6
   fusions and most Coach purchases — one seed stalled at **Gold on gen 1** — because
   weekly food starved capital. Escaping the −5% band recovers ~0.8 stat points for
   90g; escaping the −50% cliff doubles the week. A player can fall in the same hole
   and **the failure is invisible**. Consider a feeding-screen nudge when weekly food
   spend outpaces cup income.
2. **Gen 3 is still rare** — freezer-slot pressure means bred children rarely get
   frozen before their careers end, so the deep end of the breeding ladder is mostly
   theoretical.
3. **Throughput vs power.** The v0.90 drill retune raised best stats ~10% but cut cup
   entries ~20% (pricier basic, 35-stamina top tiers). The food reprice partly offsets
   it. Peaks are cap-bound, so no runaway — but competing got rarer.

---

## 6. Outstanding work, roughly prioritised

1. **Browser-verify the v0.90 UI** — the diverse training row and the 📗 shop entry
   have NEVER been seen in a browser. Everything else was verified.
2. **Version bump + merge PR #1 + deploy** (see §1). Deploy is automatic now.
3. **Update CLAUDE.md to v0.90** — it stops at v0.89.
4. **Fusion signature moves + expanded learnable skills** (task #112) — the best
   remaining feature. The four fusion classes currently differ statistically but
   play identically.
5. Achievements / goal-gradient; Hall of Fame live perks + richer inheritance;
   `tauntForce` targeting pass.
6. Housekeeping: save slot 3 may hold a throwaway "Buck" tutorial-test game.

*(vite 5 → 8 was on this list and is now DONE — PR #2, merged.)*

---

## 7. Working agreements observed this session

- **The sim is the arbiter.** Small increments, validated against `sim/bot.ts`;
  record every pass in `docs/BALANCING.md` with before/after numbers.
- When the bot can't evaluate a change, **fix the instrument first** — three real
  findings came from that (scout starvation, license earmark, the feeding trap).
- Flag confounded comparisons rather than over-claiming: the v0.90 drill run
  changed data *and* bot AI together, and the ledger says so.
- Verify with `npx tsc --noEmit`, `npx vitest run` (12/12), `npm run build` before
  every commit.
