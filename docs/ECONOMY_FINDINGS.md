# Economy Evaluation — Full-Ladder Playtest Findings (2026-07-22, v0.5)

Input to the upcoming economy pass. Produced by a competent-player bot (3-stat
builds, excursions when poor, barn/roster management) run to 16 game-years × 3
seeds through the REAL game loop. All numbers empirical.

## Headline: nobody reaches Masters — every run dies

| Seed | Peak league | End state |
|---|---|---|
| lh-a | Tin (yr 2.6) | 0 active monsters, 80g — dead stable |
| lh-b | Tin (yr 2.5) | 0 active monsters, 59g — dead stable |
| lh-c | Bronze (yr 3.0) | 0 active monsters, 75g — dead stable |

The bot podiumed 33/36 cups it entered and STILL bled out.

## Per-league ledger (approx, per era)

- Wood (~35wk): cups +240–365g · other +200g · food −300–450g · **net −191 to +28g**
- Copper (~75wk): cups +600g · other +400–755g · food −1,150–1,770g · **net −431 to −685g**
- Tin: cups +200–1,200g · other +400–1,236g · food −1,170–2,254g · **net −359 to +34g**
- Bronze: couldn't afford a 3rd monster → **0 cups entered in 650 weeks**

Food ≈ 12g/monster/wk is ~60–70% of ALL spending. Runs survive on the 500g
starting purse, not on income.

## Four structural problems

1. **Permanent deficit at every league** — even near-perfect cup results + excursions don't cover a 2-monster food bill.
2. **Costs scale with team size, income doesn't** — each league adds mouths (1→2→3→5) but cup gold only +50g/league and you still enter ONE cup. Bronze 3v3 = the wall.
3. **True soft-lock** — all monsters retired + gold < cheapest recruit = zero income forever. All 3 runs ended here.
4. **Ladder outlives gen-1 monsters and breeding is priced out** — Tin by yr ~2.5–3 of a 4–6yr lifespan; the intended fix (breed stronger gen-2 via potential) costs 500g fusion + 8g/wk freeze upkeep, unaffordable in a deficit economy.

Also validated en route (earlier playtest, fixes already in-tree uncommitted):
- Wood→Copper pacing good (license by wk 7–25); at-league cups winnable (13/18 podiums).
- Trial curve is sound: 1-stat builds win <10% beyond Wood, 3-stat ~65–75% everywhere.
  The old "ready" trap was fixed with an honest readiness meter in the trial panel
  (team avg total vs champion target ≈ cap × 1.8 × 1.25) + reworded tip.
- Rivals/champions always field FULL teams; the player is gated until fully staffed
  (the 2nd-monster purchase is the early-game cliff).

## Economy-pass targets (agreed direction)

1. Cup gold scales with league roster properly (a podium ≈ several weeks of that league's full-roster food burn — genuinely profitable).
2. Break the ration-line deficit (cheaper base food and/or higher excursion floor) — careful play ≈ break-even BEFORE winnings.
3. Kill the soft-lock (guaranteed recovery path at 0 active monsters — e.g. stray-monster event / rebuilding grant).
4. Make breeding reachable mid-game (fusion/freeze pricing) — gen-2 monsters are the intended Bronze+ engine.
5. Acceptance test: re-run the long-haul battery; at least one seed reaches Masters in ~6–10 game-years across monster generations.

## CHUNK A RESULTS (2026-07-22, uncommitted — the economy pass built + tested)

Built (all sim-verified 23/23 + live browser): cup roster stipend (+20g/member,
`CUP_ROSTER_STIPEND`), league redistribution (Iron 3v3, Gold 4v4 — perfect size
pairs), retiree pension (2+podium+2×champ, cap 10g/wk, `pensionFor`), freeze =
retirees only + lab slots (2 base, expand 400/800/1600) + upkeep 8→5(→3 via
lab-tech loan event), thaw returns RETIRED (rejuvenation exploit closed),
comfort set (stable-wide +2mo each, 300/500/1000, synced `comfortWeeks`),
Mysterious Peddler event (all 6 gear lines 200/500/750/1000/1250 tier-reveal,
Elder Tonic 500g→inventory, Stud Book 750g uncapped stud income), extreme
drills (+20/−6/−6, −35 stam, 1500g manual, data-layer gated), BREEDING v2
(parents preserved, ≤2 children, potential avg+10%+champ bonus cap 1.5, 35%
head start `BREED_HEAD_START`, heritage stat +10%, gen tags + ★), stray-monster
soft-lock backstop (force-fires at 0 active), negative-gold clamp on lab upkeep,
"career span" rename. Old fuse UI replaced by Breed UI (fusion returns in chunk B).

**Acceptance (3 seeds × 16.7yr, upgraded bot):**
- Targets 1–4 ACHIEVED: no deficit spiral (gold positive throughout, no dead
  stables), pensions+stipend+events sustain multi-monster stables, breeding
  fires (gen-2 everywhere; best seed bred 5), soft-lock gone.
- Target 5 NOT met: best seed reached SILVER at ~yr 16 (Masters wanted in 6–10).
  Bottleneck is now PACING, not money: the Bronze+ trials need N simultaneously
  cap-trained, simultaneously healthy monsters while careers age out — the
  roster-assembly problem, not individual strength. Head-start bump 20→35%
  didn't move it. OPEN DESIGN QUESTION for the user: (a) accept a longer arc,
  (b) champion multiplier tapers at higher leagues, (c) cup exp rewards scale up
  (train-by-competing), (d) faster high-league training (drill gains scale with
  license), (e) looser breeding (no decoration prerequisite, 3 children).

## Session state (for continuation)

- v0.5 is COMMITTED & DEPLOYED (`bb463ea`, Cloudflare deploy verified).
- UNCOMMITTED in-tree: trial readiness meter + reworded rankup tip (App.tsx) — ship with the economy pass.
- Step plan: 1 playtest ✅ (this doc) → **2 economy pass (next)** → 3 license-UI cleanup (per-monster league labels redundant; battle-replay lost on tab switch; rivals panel next-appearance) → 4 achievements → later (season arc, HoF, elixir, class fine-tune, onboarding).
- Long-haul bot script deleted (recreate from this doc's description if needed).
