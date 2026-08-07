# Balancing — findings & working reference

Living doc for the economy/progression balance effort. Condensed from the
2026-07-23 balancing sessions. Numbers are current as of **v0.74**.

## Design principles (from the user)
- **Challenging but possible.** The top (Masters / Tamer Elite) should be hard-won, not gated shut.
- **No fixed timeline / forced pacing.** We do NOT target "reach X by year N." A skilled player goes faster; a mediocre one takes a long time. Both are fine.
- **Slow iterations.** Small tuning steps, each **validated against the long-haul sim**, then adjust. The sim is the arbiter.

## How we measure — the long-haul sim
A competent-player bot plays the full game (economy + cups + trials + licenses +
breeding) reporting **peak league, end gold, dynasty generation, cup record**.
As of v0.81 it is **committed** (no longer scratch): `sim/bot.ts`, run with
`npx tsx sim/bot.ts [years] [seeds]` (default 15×3). It's outside the app build
(`tsconfig` includes only `src`) and drives the real exported game functions —
including the v0.81 deferred flow (stage → per-fight `MatchOrders` → finalize)
via a "coach AI" (`coachOrders`) that uses **every** tactics lever (temperament,
scouting-informed target priority, mana policy, opening sequence, survival,
control-first, combo, formation, protect, focus/mark). Keep it in sync when
mechanics change. Peak league + whether breeding fires are the headline metrics.
**v0.81 baseline (15y × 4 seeds):** Silver ×4, gen-2 ×4, ~210 cups/seed,
~55–75% cup wins, 24k–33k end gold — a stable competent-but-unoptimised floor
(a skilled human should still outrun it, per the design principles above).

## Current numbers

### Cup rewards (1st-place gold; exp = gold/2)
| League | Wood | Copper | Tin | Bronze | Iron | Silver | Gold | Platinum | Masters | Tamer Elite |
|---|--|--|--|--|--|--|--|--|--|--|
| Regular cup | 120 | 180 | 250 | 330 | 420 | 500 | 590 | 690 | 800 | 920 |
| Marquee event | — | — | — | — | — | 650 | 760 | 880 | 1010 | 1150 |

- **Roster stipend** `CUP_ROSTER_STIPEND = 20`g per *extra* team member (income scales a bit with team size).
- **Placement** `PLACEMENT_REWARD_FRACTION`: 1st 100% · 2nd 65% · 3rd 40% · 4th+ 0.
- **Punch-down** `rewardMultiplier`: 100% at league · 50% one below · 10% two+ below.
- **Entry fee** `entryFee = (leagueIndex + 1) × 10`g (Wood 10 … Tamer Elite 100).

### Other income
- **Trainer stipend (v0.72):** `+5g/wk × trainer level` (Lv1 = 5 … Lv10 = 50/wk). Paid weekly. **Hook for achievements:** achievements will grant trainer XP → level → stipend.
- **Trainer XP** `TRAINER_XP_PER_LEVEL = 250`; from cup podiums + raising monsters to retirement. Also grants **+1 barn slot / 2 levels**.
- **Pension** (retired champions): 2 + 1/podium + 2/championship, cap 10g/wk.
- **Stud income** (frozen legacy w/ Stud Book): 1/podium + 3/championship, uncapped.
- **Excursion:** cap = `LEAGUE_TOP_GOLD × 0.4` (was ⅓), bottom-skewed (`rng²`). `LEAGUE_TOP_GOLD` Wood 110 … TE 760, tuned **independently** of cups but must stay ≤ cup gold (validated).

### Costs / sinks
- **Food** — the dominant sink (~60–70% of spend). Rations swing ±60%; training/premium 0.9–1.5×. Forage fallback only when gold < 10.
- **Monsters** ~MARKET_BASE 150 ±60%. **Barn** 120 × current cap.
- **Fusion** 1000g. **Breeding** `BREED_COST = 300`. **Lab/stud slots** expand 400/800/1600.
- Comfort set 300/500/1000, Extreme Manual 1500, food contracts 400/1500, breeding licenses 800/2000, peddler gear 200–1250/tier, Elder Tonic 500, Stud Book 750.

### Progression / combat gates
- **League caps** (per-stat): Wood 100, Copper 200, Tin 300, Bronze 400, Iron 500, Silver 600, Gold 700, Platinum 800, Masters 900, Tamer Elite 1000.
- **Team size:** Wood/Copper 1 · Tin 2 · Bronze/Iron 3 · Silver/Gold 4 · Platinum 5 · Masters/TE 6.
- **Trial to rank up:** beat a champion team scaled to `leagueCap × rivalBudgetMult(leagueIdx) × TRIAL_CHAMPION_MULT(1.25)`.
- **Rival budget escalation (v0.75):** `rivalBudgetMult(i) = 1.8 + i × 0.02` (Wood 1.8 → Tamer Elite 1.98). Was a flat 1.8 — a constant ratio the player's compounding power outgrew, making late leagues walkovers. The gentle per-league ramp keeps difficulty pacing the player. Applies to cup rivals, challenge skirmishes, and rank-up champions. **Deliberately shallow** (first increment — tune the step up from the sim if the top is still a coast).
- **`statCapFor = leagueCap × potential`** (gen-1 fusion hard-capped at Platinum = 800).
- **Career span** ~6 years base; **+2yr pedigree bonus (`PEDIGREE_SPAN_BONUS`, v0.73)** for fusion / prestige (Draconic/Abyssal/Mythical) / bred (gen≥2) monsters — wild base monsters unchanged.

### Breeding & fusion
- **Potential:** wild = 1.0; **+0.10 / generation** + up to **+0.08** champion-parent bonus; **cap `MAX_POTENTIAL = 1.5`** (~4–5 generations to reach). Breed cost 300, ≤2 children per stud, heritage stat +10%, **head-start `BREED_HEAD_START = 0.45`** (child hatches at 45% of parents' averaged stats — v0.73).
- **Fusion:** 1000g, consumes two monsters **from the stable OR the freezer (v0.74 — no freeze step)**; result = **all stats 100**, **+20% on each parent's major** + rolled +10%/−10%, species by spinning wheel, **potential 1.15 (3★, v0.74)**, gen-1 **Platinum-capped**, then fully breedable (gen-2 ≈ 3★ → Tamer Elite).

## Sim findings

### v0.71 → v0.72 (economy pass)
| | v0.71 (before) | v0.72 (after) |
|---|---|---|
| Peak league (3 seeds) | Tin / Bronze / Bronze | **Platinum / Gold / Gold** |
| Breeding | 0 | **gen-2, ~4 dynasties/seed** |
| End gold | 30–114g (cash-starved) | **1,900–3,300g (surplus)** |
| Fusions | 0 | **still 0** |

The economy pass (cup gold up + trainer stipend + excursion nudge) **fixed the
money gate**: the wall moved from Bronze up to Gold/Platinum, and breeding
dynasties now fire. Masters/TE remained unreached at the ~19-year sim cap.

### Diagnosis — what gates the top now (NOT money)
The 1,900–3,300g surplus proves gold is no longer the constraint. The top is
gated by:
1. **The roster-assembly treadmill.** Higher leagues need more monsters (4v4 → 6v6) all trained to champion-grade stats *simultaneously*; each takes years (≈1 stat/week, stamina-gated) and **ages out at ~6 years**. By the time monster #4 is ready, #1 is retiring. Arrivals show a ~4-year stall just at Iron (3v3).
2. **Potential is NOT the binding limit.** At Masters (cap 900) even potential 1.0 has room to train champion stats — raising the cap makes elites *stronger*, not the top *more reachable*. Potential helps only indirectly (higher ceiling + bigger breeding head-start).
3. **Ran out of clock, not road.** All seeds stopped at the sim's fixed 19-year cap while still climbing — "peak Gold/Platinum" is the *pace*, not a wall.
4. **The two accelerants went unused:** fusion (0×) and deep breeding (only gen-2). A player leaning on both goes further.

## Open levers (candidate next iterations — NOT yet done)

### Encourage fusion (ranked by impact)
1. ✅ **DONE (v0.74)** Potential edge — gen-1 fusion 1.075 → **1.15** (seeds a high-potential bloodline).
2. ✅ **DONE (v0.74)** Cut friction — fuse straight from the stable (no freeze step). (Cost still 1000g.)
3. **Signature skills** (task #112) — an exclusive strong move per fusion species = the combat draw.
4. **Longer career span for fusion monsters** — more training years for the "burn-bright" specialists.
5. Keep the **gen-1 Platinum cap** so none of this is an instant-win.

### Make the top more reachable (if desired)
- **Head-start 0.35 → ~0.45** (best lever — shortens the aging treadmill directly).
- **Potential step 0.10 → 0.15** (dynasties compound faster).
- **Career span +** (more training time per monster).
- **Do NOT raise MAX_POTENTIAL (1.5) yet** — not the binding constraint.

### Still-open economy items
- Fusion firing in practice (bot never coordinates it — a human would; validate with the levers above).
- Whether the v0.72 bump overshot (Bronze → Gold/Platinum is ~2–3 leagues; dial back top-league cup gold or stipend if too generous).
- Food-cost relief for large rosters (bulk-feeding discount) — deferred lever.

## v0.77 — the big economy correction

**Diagnosis (measured, 25y × 3 seeds).** Income was inverted: retiree **pension 45%**,
**trainer stipend 40%**, **cup prizes just 7%**. Both faucets were perpetual, uncapped and
cumulative (retirees never leave; stipend grew forever), while every sink was a one-off.
An average player finished on **~180,000g** with nothing to spend it on.

**Fixes**
- **Pension REMOVED.** Retirement Ranch → **🏛 Hall of Fame**: honours only, no income,
  **unlimited room** (retirees no longer occupy barn slots — they used to clog it).
  Breeding still requires freezing into the limited stud farm.
- **Trainer stipend capped**: was `5g × level` uncapped (~95g/wk by LV19). Now **1g/level,
  flat from level 15 = 15g/wk**. A LV53 trainer still earns 15g/wk.
- **Cup gold +8%** and **Extreme Manual 1500 → 1200**, to re-open the advanced systems the
  cut had priced out.

**Result:** average end gold **180k → 2.8–15.4k**; cups became **~81%** of a good player's
income. Gold is a real constraint again.

### Gen-1 training ceilings (v0.77)
A monster you did not BREED is walled. Breeding (gen 2+) is the only unconditional way past.
| Kind | Ceiling |
|---|---|
| Wild / market, no coach | **800** |
| Wild / market + Market Coach I | **900** |
| Wild / market + Market Coach II | **1000** |
| **Fusion (gen 1)** | **1000** |
| Bred gen 2+ | `leagueCap × potential` (1100+ at TE) |

Rank-up needs `leagueCap − 10`, so: **Masters** requires coach I / fusion / breeding;
**Tamer Elite** requires coach II / fusion / breeding. The Coach's league gates (Gold, then
Platinum) line up exactly with where the lift is needed. Fusion gen-1 now **out-ceilings
uncoached market stock by 200** — that's the draw that pays for 1000g + two monsters.

### Potential ladder (verified against `breedPotentialV2`)
| Line | Gen 1 | Gen 2 | Gen 3 | Gen 4 | Gen 5 | Gen 6 |
|---|--|--|--|--|--|--|
| Bred, plain parents | 1.00 | 1.10 | 1.20 | 1.30 | 1.40 | **1.50** |
| Bred, champion parents | 1.00 | 1.18 | 1.36 | **1.50** | — | — |
| Fusion, plain parents | 1.15 | 1.25 | 1.35 | 1.45 | **1.50** | — |
| Fusion, champion parents | 1.15 | 1.33 | **1.50** | — | — | — |

All lines converge at `MAX_POTENTIAL 1.5`; fusion + champion parents is the fastest route
(3 generations vs 4 or 6).

### Two-profile sim (25y × 3 seeds, post-change)
| | Good player | Average player |
|---|---|---|
| Peak | **Tamer Elite / Masters / Tamer Elite** | Iron / Bronze / Silver |
| Best stat | 1000 / 930 / 1000 | 260 / 104 / 430 |
| Cup wins | 90–106 | 25–33 |
| End gold | 0.6–2.2k (fully invested) | 2.8–15.4k |
| Coach bought | **2/2 every seed** | never |

⚠️ **Known gap:** fusion still fires only ~1× per 25 years. The binding constraint is NOT
gold — it's needing two *spare* monsters forming a valid body pair (Mammal+Reptilian /
Avian+Aquatic / Marsupial+Insectoid). A roster/recipe friction, not an economy one.

## v0.78 — freeze-to-breed (the Lab is the only preservation route)

**Problem.** Breeding stock could only be banked *after* retirement (`freeze()` required
`c.retired`), and lab-frozen monsters were breeding-ineligible. So the intended plan —
"freeze the ones you want to breed" — was impossible, and the incentives ran the other way:
retirement preserves stats and the Hall of Fame is unlimited, so waiting was strictly better.
Dynasties stalled at **gen 2** in every sim ever run.

**Change.** One preservation store: `labFrozen`. Breeding and fusion both read it.
`freezeToLab()` refuses retired monsters. Stud farm (`frozen`, `studSlots`, `freeze`, `thaw`,
`expandStud`) deleted; saves migrate. Hall of Fame = honours only.

**Reprice** (the Lab was costed as an optional parking bay, not core infrastructure):
| | was | now |
|---|--|--|
| `LAB_SLOTS_BASE` | 2 | **3** |
| Expansions | 400 / 800 / 1600 | **250 / 500 / 900** |
| Upkeep per monster | 5g/wk | **3g/wk** (loan 3 → **2**) |

**Results, 25y × 3 seeds (good player)**
| | Old retire→stud | Freeze-only, untuned | Freeze-only, tuned |
|---|---|---|---|
| Peak | TE / Masters / TE | Masters / Gold / Platinum | **TE / Platinum / Gold** |
| Best stat | 1000 / 930 / 1000 | 886 / 692 / 800 | 975 / 801 / 679 |
| Breeds | 4 | 4 | **6** |
| Generation | 2 | 2 (one seed 3) | **2 / 3 / 3** |

Gen 3 on two of three seeds is the deepest any sim has reached. The untuned row shows why the
reprice was needed: freezing removes a monster from the roster mid-career, and at 2 slots /
400g / 5g-wk it competed directly with the Market Coach (the thing that actually lifts your
stat ceiling) — one seed never afforded the Coach at all.

⚠️ **Open:** more variable than the old path (one seed stalled at Gold, 679 — eleven points
short of the 690 needed to rank into Platinum). Also the "average player" bot is modelled as
*always* missing the freeze window, so it ends gen 1 with no breeding and 30–40k unspent gold;
that is probably harsher than a real casual player and overstates the skill gap.

## Ledger of changes made
- **v0.62** — economy pass #1 (stipend/pension/comfort/peddler/breeding/soft-lock).
- **v0.72** — cup gold ↑ + trainer gold stipend + excursion nudge. Peak Bronze → Gold/Platinum; breeding now fires.
- **v0.74** — fuse-from-stable (removed the freeze hoop) + fusion potential 1.075→1.15. Mechanic verified firing in the sim; fusion now a 1-click stable action.
- **v0.73** — pedigree span +2yr (fusion/prestige/bred) + bred head-start 0.35→0.45. **Peak Gold → Masters/Tamer Elite** (1 seed reached TE @ yr 12.7); top is now reachable via breeding, still challenging (12–19yr). Fusion still unused by the bot.
- **v0.75** — difficulty escalation: flat `RIVAL_BUDGET_MULT 1.8` → `rivalBudgetMult(i) = 1.8 + i×0.02` (Wood 1.8 → TE 1.98). **A/B (25yr × 3 seeds, rebuilt bot):** flat → Gold/Gold/Bronze; escalating → Gold/**Silver**/Bronze — one seed held back a league, win-rates dipped slightly, no collapse. Gentle friction confirmed, first increment. ⚠️ **Instrument caveat:** the rebuilt bot trains only basic drills / 3-stat builds and peaks at **Gold** — much weaker than the prior Masters/TE bot, so it can't reproduce the skilled-human "easy run to Masters" the change targets. Money is a non-constraint at every peak (48k–121k surplus). Next: either strengthen the bot (intensive/extreme drills, comfort/tonic, timed breeding) to test the top directly, or nudge the step up (0.02 → ~0.03) and re-A/B.

## v0.861 — validation run for the un-simmed v0.85–v0.86 batch

**What accumulated without a sim pass:** life-stage training Teen 1.0→1.35× / Fully Grown
0.95→1.15×; prestige overhaul (base stats ~144/~158, gen-1 cap 800→1000, 9–12y careers,
−5%/no flaws); COACH_PRESTIGE_MULT; BREED_HEAD_START 0.45→0.15→0.30; free cup entry;
trial gold; ≥2 cups/month.

**Run (25y × 3 seeds, v0.81 bot) + A/B isolating the training multipliers:**
| | OLD mults (1.0/0.95) | NEW mults (1.35/1.15) |
|---|---|---|
| Peak | Iron / Silver / Silver | **Silver / Silver / Silver** |
| End gold | 56–66k | 50–71k |
| Cup 1sts | 234–237 | 209–270 |
| Trials won | 4–5 | 5 |
| Generation | 2 | 2–3 |

**Read:** the training bump is a mild accelerant, not a runaway — the stat cap
(league cap × potential) binds either way, so faster training mostly reaches the same wall
sooner (one seed converted Iron→Silver; ~+10% cup wins). No economy spiral. The two
standing caveats predate this batch and still dominate the signal: (1) money is a
non-constraint (50–70k unspent — sinks needed at the top end, or the bot under-spends);
(2) the bot's basic-drill 3-stat build stalls at the Silver→Gold trial, so the top half of
the ladder (where the prestige/coach changes actually live) is untested by this instrument.
**Next:** strengthen the bot's economy brain (intensive/extreme drills, comfort/tonics,
licenses+prestige purchases, timed freezes) before drawing conclusions above Silver.

### v0.861 follow-up — full-economy bot rebuild + retest (same code, better instrument)

The bot now exercises EVERY mechanic (all three drill tiers incl. the Extreme Manual,
aptitude-aware 3-stat builds with maluses steered off-build, training foods + Vigor Melon
rescues, market slots/coach, prestige licenses + prestige-preferring recruitment to a
league-sized stable, barn/comfort/lab/pantry purchases, infirmary healing, peddler tonics,
Elder freezing, best-pair breeding, spare-pair fusion, trial-first scheduling).

**25y × 3 seeds, current live tuning:**
| seed | peak | @yr | best stat | gen | cups→1sts | trials | breeds | coach | prestige owned | end gold |
|---|---|---|---|---|---|---|---|---|---|---|
| 0 | Tamer Elite | 10 | 1180 | 2 | 192→125 | 9 | 4 | 2/2 | 13 | 702 |
| 1 | Tamer Elite | 10 | 1180 | 2 | 192→140 | 9 | 4 | 2/2 | 13 | 754 |
| 2 | Tamer Elite | 19 | 1170 | 2 | 211→117 | 9 | 4 | 2/2 | 10 | 1037 |

**Reads:**
- **The whole ladder is beatable** — first time any sim instrument has seen Masters/TE.
  An optimal player summits in **~10y** (worst seed 19y); the v0.73 design point was
  12–19y for a strong player, so the v0.85/0.86 buff stack has shaved ~2–3y off the
  fast path. Borderline — a human is less optimal than this bot; watch, don't panic-nerf.
- **The gold hoard was bot passivity, not a design hole**: fully-invested end gold is
  ~0.7–1k (vs the old bot's 50–70k). A good player has real sinks all the way up.
- **Fusion never fires for a prestige-heavy stable** — prestige bodies have no fusion
  recipes, so once the Special License lands, fusable base bodies stop entering the
  roster. Structural tension worth a design look (prestige recipes? keep as niche?).
- **Gen stalls at 2** even with 4 breeds: freezer slots fill with the original parents,
  so bred children rarely get frozen before career end. Partly bot heuristics, partly
  a real slot-pressure feel a player would also hit.
- Sustained ~60–65% cup win rate at-league — strong but not degenerate.

## v0.87 — prestige scarcity increment #1 (market rarity + price premium + scout nerf)

**Problem (from the v0.861 full-economy run):** once the Special License lands, prestige
bodies are ~1/3 of all market rolls at ordinary prices — the roster goes all-prestige
(10–13 owned per 25y) and the ladder's fast path compressed to ~10y.

**Change (gentle first increment, all in `rollMarketOffers` — golden-safe):**
- `PRESTIGE_MARKET_CHANCE 0.12` — only 12% of would-be prestige rolls survive; the rest
  re-roll to base species. Measured stock: prestige fell 33% → **5.3% of offers**
  (~1 offer per 3 full restocks). The Market Scout pick deliberately bypasses rarity —
  scouting IS the hunting tool.
- `PRESTIGE_PRICE_MULT 1.5` on the rolled price (measured avg 209g vs 150g base).
- `SCOUT_CHANCE 0.15/0.25 → 0.12/0.20` — the hunting tool lands a touch less often.

**Retest (25y × 3 seeds, full-economy bot):**
| | before | after |
|---|---|---|
| Peak @yr | TE@10 / TE@10 / TE@19 | TE@18 / TE@17 / Masters@19 |
| Prestige owned | 13 / 13 / 10 | **4 / 3 / 1** |
| Cup 1sts | 125 / 140 / 117 | 98 / 130 / 76 |
| End gold | 702–1037 | 719–806 |

The fast path moved from ~10y back into the 12–19y design band, prestige ownership landed
in the intended 2–4 range, money stays fully invested, and one seed now tops out at
Masters — the summit is once again earned. License-price increase (option 3) held in
reserve; fusion still never fires (structural, separate design question).

## v0.87 — mid-game difficulty pass (four small nudges, one increment)

**Problem:** every seed cleared Tin→Gold nearly frictionless — mid trials never failed,
mid cup win rates peaked, difficulty lived only in the last two trials.

**Nudges:**
| knob | was | now |
|---|---|---|
| `RIVAL_BUDGET_STEP` | 0.02 | **0.03** (v0.75's prescribed increment; TE mult 1.98 → 2.07) |
| `RIVAL_BAND_MIN` | 0.60 | **0.65** (fewer rolled-weak teams = fewer free round-robin wins) |
| trial champion mult | 1.25 flat | **1.30 for Bronze→Gold** (`trialChampionMult`; top trials unchanged — already the hardest step) |
| `LICENSE_COSTS` mid | 220/350/520/750 | **235/410/610/860** (~10–15%; still monotonic + never-doubling) |

**Retest (25y × 6 seeds):** summit years stretched (TE @ 17/18/22/25 vs 17–18 clustered),
cup 1st-place rate fell ~20–25% across the board (72–119 vs 76–140), one seed now tops out
at Platinum (was Masters), and — first time ever — one seed reached **gen 3 / best stat
1270**. Money still fully invested. Mid-game friction is real without any collapse: the
distribution now runs Platinum → TE across six optimal-play runs, which is the shape we
want (summit possible, never guaranteed).

## v0.87 — interlocking gen-1 cap ladder (user spec)

**Change:** the Market Coach becomes a UNIVERSAL quality upgrade — it lifts wild AND
prestige walls by tier. `statCapFor` reads the coach tier from the synced wildCap:

|            | no coach | coach T1 | coach T2 |
|---|---|---|---|
| wild/market | **700** (was 800) | 800 | 900 (was 1000) |
| Draconic/Abyssal | **800** (was 1000) | 900 | 950 |
| Mythical | **900** (was 1000) | 950 | **1000** |
| fusion gen-1 | 1000 flat (unchanged) | | |
| **Primeval** gen-1 | **1100 flat** (v0.88) — the only gen-1 above the TE league cap | | |

Only fusion and a fully-coached Mythical reach 1000 — every other gen-1 now falls short
of the TE cap, so the summit belongs to bred dynasties. Saves re-sync wildCap on load.

**Retest (25y × 6):** 5/6 seeds reach TE (@15–25y), seed 5 still walls at Platinum.
Best stats 1000–1180 are now BRED gen-2 monsters — and notably seed 4 summited with
**zero prestige owned**: with prestige walls lowered, optimal spending shifted from
"buy prestige" to "breed earlier", which is precisely the intent. The ladder made
dynasty the endgame route without making the summit unreachable. Fusion still 0 —
its problem is recipe friction, not ceilings.

## v0.88 — Primeval: the prestige fusion (Mythical + Draconic/Abyssal)

**New fusion class** (5 species: Aeonrex, Stellavore, Chronoshell, Originmage, Worldsong —
roster 65): two body-pair recipes (Mythical+Draconic, Mythical+Abyssal) feed one class.
**1.25× potential** (vs 1.15 base fusion) makes Primeval the premier founder of endgame
bloodlines. Element affinity inherits Mythical's air/earth (all 12 pairs were taken —
one sanctioned validator exception). Fusion bodies stay out of wild/market generation —
goldens untouched.

**Making the bot prove it** (three instrumented findings, each a real player insight):
1. The scout was priority-starved — bigger purchases drained gold below its threshold
   every week for 25 straight years. Promoted: scouting is the prestige-hunting tool.
2. The pair's Elder windows never overlap (the Mythical arrives ~a decade later) —
   fuse YOUNG, weakest-of-each-body, like a player deliberately building a Primeval.
3. Even with the pair assembled for 9 straight years, gold never touched the fuse
   threshold at the weekly check — the bot now EARMARKS the fusion cost while the
   ingredients are owned. This is a genuine UX signal: a player needs a way to see
   "you own a fusable pair — save 1000g" (future nudge?).

**Result (25y × 6):** fusion fires 1–2× in 5/6 seeds (was 0 in every sim ever run);
peaks TE ×5 @13–21y + Masters ×1; best stats 1035–1180. The fusion loop is finally a
living part of optimal play, and Primeval lines are staged as the Tamers Apex on-ramp.

## v0.88 — breeding cap ladder by heritage (user spec)

**Change.** The per-generation potential step is no longer flat 0.10 — it now depends on
the line's BEST parent (`BREED_STEP_BY_TIER` / `breedStepFor`), and `breedPotentialV2`
bases off `max(parents)` instead of their average so one exceptional founder isn't
diluted by a modest partner. (For same-generation pairings — the usual case — max ==
average, so ordinary lines are unchanged.)

| heritage | step/gen | gen-1 cap | gens to a 1400 cap |
|---|---|---|---|
| wild | 0.10 | 700–900 | **4** |
| Draconic / Abyssal | 0.11 | 800–950 | 4 (reaches 1440) |
| Mythical | 0.12 | 900–1000 | 4 (reaches 1480) |
| base fusion | 0.13 | 1000 | 2 |
| **Primeval** (prestige fusion) | **0.15** | 1100 | **1** |

**Measured ladder** (Tamer Elite, league cap 1000, no champion bonus):
```
tier              gen1   gen2          gen3          gen4          gen5
wild               700   1100 (1.10)   1200 (1.20)   1300 (1.30)   1400 (1.40)
Draconic           800   1110 (1.11)   1220 (1.22)   1330 (1.33)   1440 (1.44)
Mythical           900   1120 (1.12)   1240 (1.24)   1360 (1.36)   1480 (1.48)
fusion (Saurian)  1000   1280 (1.28)   1410 (1.41)   1500 (cap)    1500 (cap)
Primeval          1100   1400 (1.40)   1500 (cap)    1500 (cap)    1500 (cap)
```
A lone Primeval bred with a plain wild gen-1 partner still lands **1.40 / 1400** — the
stated one-generation target holds for the realistic pairing, not just Primeval×Primeval.

**Note:** `MAX_POTENTIAL` stays 1.5, so the prestige-fusion advantage is *speed to the
ceiling*, not a higher ceiling — a patient wild dynasty still gets there, four
generations later. Long-haul sim unchanged (TE ×5 / Masters ×1, 25y × 6) because the bot
plateaus at gen 2; the ladder is a deterministic formula, verified analytically above.

## v0.89 — league curve steepened + TAMERS APEX (11th league)

**Curve (user spec).** The top of the ladder pulls away from the flat +100/league:
Gold 700→**750**, Platinum 800→**900**, Masters 900→**1000**, Tamer Elite 1000→**1200**,
and a new summit **Tamers Apex at 1400**. (Spec read "Masters 100" — taken as 1000, the
only monotonic value between Platinum 900 and TE 1200.)

Apex is wired through every league-keyed table: pool rewards (1140/570), an 8-name cup
pool, the annual marquee **The Dynasty Eternal** (month 12), 6v6, 5 rival teams,
half-density calendar [Q2,Q4], license 2100g, excursion ceiling 820g, validator probes.
Backdrop reuses the Tamer Elite art (TODO: generate its own).

**Golden moved (recaptured):** `3v3-high`. `boostConstitution` derives its CON target from
the league cap of the monster's stat band, so changing Masters/TE caps changes a
`train: 2000` roll. Legitimate data change, not a regression. 12/12 green.

**Retest (25y × 6):**
| | before curve | after curve |
|---|---|---|
| Peaks | TE ×5, Masters ×1 | **TE ×2, Masters ×3, Platinum ×1** |
| Best stat | 1035–1190 | 1035–1428 |
| Apex reached | — | **never** |

**Two consequences worth a decision:**
1. **The whole late game got materially harder.** Rival budgets are `league cap × mult`,
   so raising four league caps raised every late-game field with them: a Tamer Elite cup
   rival went ~1683 → ~2049 total stats. Three seeds that used to summit now stop at
   Masters/Platinum. That may be exactly the intent (the summit should be rare) — but it
   is a bigger difficulty swing than the four "small nudges" that preceded it.
2. **Tamers Apex is currently unreachable.** Its trial champion is **3675 total stats per
   monster, six of them**, versus a player best of ~1428 top / ~2400 total. No seed won
   the TE trial *and* then the Apex trial. If Apex is meant to be enterable this decade,
   it needs either a gentler `trialChampionMult` at the top or a lower Apex rival mult.
3. **The breeding ballpark drifted.** Bred caps are `league cap × potential`, so with Apex
   at 1400 a *wild* gen-2 line already reaches 1540 there — the "4 generations to a 1400
   cap" target was calibrated against a 1000-cap league and now lands in ~1 generation at
   the top. The tier ORDER still holds (wild < prestige < Mythical < fusion < Primeval);
   only the absolute numbers moved.

## v0.89 (fix pass) — the summit is reachable

Three findings, each fixed and re-simmed:

**1. The final gates were a compounding wall.** `trialChampionMult` was a flat 1.25 while
`league cap` AND `rivalBudgetMult` both climb, so the Tamer Elite champion sat at 3105
total stats per monster ×6 — the sim never won it once, making Tamers Apex unreachable by
construction. Now per-rung: **1.30** Bronze→Gold (the v0.87 mid-game friction), **1.15**
at Tamer Elite/Apex. The TE trial started falling immediately (10 trials won).

**2. The prestige licence reprice starved fusion.** Repricing to the original design
values (800/2000) pushed fusion to **0 across all six seeds** — gold that would have
forged a Primeval went on licences. Dialled back to **500/1200** (still 2.5×/2× the old
200/600) and fusion returned (3 of 6 seeds). Apex licence also trimmed 2100 → **1900**:
winning the last trial and then being unable to afford entry made the summit a tease.

**3. The bot never bought a licence it had EARNED.** It earmarks gold for fusion but not
for licences, so it won the Apex trial and spent the entrance fee on more monsters — for
35 straight years. That is an instrument gap, not a design flaw: a rational player stops
shopping and saves. Added `licenseEarmark`.

**Result (25y × 6):** **Tamers Apex reached** — seed 4, year 23, best stat 1416, 10 trials
won. Distribution now runs Masters ×2 / Tamer Elite ×3 / **Tamers Apex ×1**, fusion fires
in 4 of 6 seeds, money stays fully invested (524–927g). The ladder terminates: the summit
is winnable, rare, and takes most of a 25-year career.

**Still open:** gen 3 remains rare (freezer-slot pressure), and rivals do not follow the
gen-1 cap ladder — their budget is `league cap × mult` as a total-stat pool, so any future
`LEAGUES` edit moves every field with it.

## v0.90 — training tiers: Diverse Manual, extreme retune, basic stamina

**Changes under test.** New DIVERSE tier (800g manual): +8/+8 on a pair, no malus,
35 stamina — six off-archetype pairs, every stat exactly twice. EXTREME retuned
20/−6/−6 → **24/−4/−4** so it nets +16 at 35 stamina, exactly mirroring diverse
(same output, same cost, opposite shape). EXTREME_MANUAL 1200 → **800**.
BASIC_DRILL_STAMINA 10 → **15**, which drops basic to 0.40 net/stamina — *below*
both top tiers at 0.46, so the safe option is no longer the quietly optimal one.

**Instrument change (same pass).** The bot picked drills off a fixed tier ladder,
which could never evaluate a pair tier. It now scores every affordable drill by
USEFUL yield — gains on a build stat count, gains on a capped stat are wasted,
losses count only if they land on the build — and takes the best. That is also
just better play, and it is what lets diverse compete on merit (+16 when both
stats are on-build, +8 when only one is).

**Result (25y × 6):**
| | before (v0.89 fix pass) | after |
|---|---|---|
| Peaks | TE ×3, Masters ×2, **Apex ×1** | TE ×3, Masters ×2, **Platinum ×1** |
| Best stat | 1062–1416 | **1332 / 1320 / 1428** top three |
| Fusion fired | 3 of 6 seeds | **6 of 6** |
| Cups entered | 191–249 | 160–196 |
| End gold | 341–917 | 341–860 (still fully invested) |

**Read.** The training buff did **not** cause a power spiral — peaks are flat or
slightly lower even though best stats rose ~10%. Same lesson as the v0.851
life-stage bump: the stat CAP binds, so faster training mostly reaches the same
wall sooner. The visible cost is throughput: pricier basic drills and a 35-stamina
top tier mean more rest weeks, so cup entries fell ~20% and one seed slipped
Apex → Platinum. Fusion firing in every seed is the clear win.

⚠️ **Confounded comparison.** The drill data and the bot's drill AI changed in the
same run, so this is not a clean A/B — the peak movement could be either. The
headline (no runaway) is robust because it is cap-bound, but if the Apex → Platinum
slip matters, isolate it by running the new bot against the old drill values.

## v0.90 — premium food reprice (Vigor Melon + Bliss Berry → 90g)

**Change.** Vigor Melon 200 → **90g**, Bliss Berry 250 → **90g**. The melon was the
only stamina food in the game and cost more than a top-tier drill's entire stamina
budget, so it was never worth buying; the berry's +3 happiness was priced like a
luxury for an effect that only skews a roll. Both now sit just above the 75g
training foods, making a feeding week a real three-way call: train harder, recover,
or lift mood.

**Instrument.** The bot's feeding brain was rewritten to actually use them, and the
FIRST policy was badly wrong in an instructive way — "melon whenever below the
full-effectiveness band (<=70)" meant ~90g × 6 monsters × nearly every week:

| | melon-every-week | disciplined (<=50 only) |
|---|---|---|
| Peaks | Masters ×2, TE ×2, Platinum ×1, **Gold ×1** | TE ×3, Masters ×2, **Apex ×1** |
| Best stat | 750–1416 | **1168–1652** |
| Breeds | 0–2 | 3–4 |
| Fusion fired | **1 of 6** | 5 of 6 |
| Coach bought | 0–1 | 1–2 |

Weekly food drained the capital that the Coach, the manuals, breeding and fusion
all need — one seed stalled at **Gold on generation 1**. Paying 90g to escape the
−5% band recovers ~0.8 stat points; paying it to escape the −50% cliff doubles the
week. The fixed policy buys a melon only at `staminaMalus < 0.95` (stamina ≤50),
a berry only below 4 happiness, and holds an 800–1200g floor so capital wins.

**Result (25y × 6, best run to date):** peaks TE ×3 / Masters ×2 / **Tamers Apex ×1**
(seed 2, year 15, best stat **1652**), fusion in 5 of 6 seeds, 3–4 breeds each,
money still fully invested (236–1620g).

⚠️ **Design signal, not just a bot bug.** At 90g premium food is now cheap enough
that a player *can* casually overspend into a wrecked economy — the failure is
invisible (you feel well-fed while your capital never compounds). That is either a
genuinely interesting trap or an unfair one; worth a UI nudge if playtesters fall in.

---

## v0.93 — the combat-balance session (2026-08-01)

The largest single balancing session in the project. ⚠️ **Read the instrument
section first** — most of the day's findings were only possible because the
harness was wrong, and several previously-recorded conclusions are overturned
below.

### THE INSTRUMENT WAS MEASURING THE WRONG GAME

Five defects, each of which silently produced plausible wrong numbers rather than
errors. Every balance figure recorded before this session should be read with
these in mind.

| defect | what it meant |
|---|---|
| `sweep40` and `ab.ts` each carried their **own copy** of ten hand-picked species triples | every balance number ever produced was measured against teams that existed **nowhere in the game**. `src/teamTemplates.ts` was written to fix exactly this and was imported by nothing but its own test |
| every composition was **3v3** | the harness measured Bronze/Iron and nothing else, while the game runs 1v1 to 6v6 |
| **no per-composition reporting** | "composition is a variable" is the sweep's founding claim and could not be read from its output |
| **one training tier** (850 → top stat ~455) | every capstone (lv650–920) was invisible to every measurement; late content was authored blind |
| `generateMonster` **hard-clamped stats at 1000** | Tamer Elite (1050) and Apex (1100) could not be simulated at all — `leagues.ts` reported a Masters monster as an Apex one **without saying so** |

All five fixed. `tools/comps.ts` is the single definition both harnesses fight,
spanning 2v2–6v6; `--elite` selects the endgame tier; `--noise` and `--league`
exist on `tools/leagues.ts`; `GenOptions.statCap` carries the ceiling.

⚠️ **Coverage went up AND the error band went down** — duration sd 1.11s → 0.91s,
so a change must now beat ~1.8s. `resolved` is **at ceiling** (sd 0.00) and can
only detect regressions; judge on duration and time-to-first-kill.

### Overturned by measurement

- ⚠️ **FOCUS FIRE (P6) was aimed at the wrong lever.** The roadmap's top item
  rested on "damage spreads evenly across a whole enemy side". It does not: top
  share is **0.711** where an even split is 0.333. maxHp correlates **r=+0.79**
  with time-to-first-kill; top share **r=−0.56**. Focus is real but smaller.
  Healing was the other suspect and is not it (0–9% of damage).
- ⚠️ **"The maxHp coefficient measured NULL" was an instrument artifact.** Re-run
  on the fixed harness: **p = 0.0022**, concentrated on the grinding shapes.
- ⚠️ **Raising `maxHp` COMPRESSES the spread** — median +18% but max/min fell
  9.8× → 4.0×. More HP makes trades decisive: it raises the floor and eats the
  ceiling. **Do not use it to create range.**

### Healing: four A/Bs, four nulls, then the real fix

| test | condition | p |
|---|---|---|
| HEAL_MULT 1.3 | thin pool | 1.00 |
| HEAL_MULT 2.5 | thin pool | 0.38 |
| HEAL_MULT 1.3 | +2 direct heals | 0.18 |
| HEAL_MULT 1.3 | under triage | 1.00 |

⚠️ The count of fights the constant could even touch fell **40 → 21 → 14 → 12**.
Restoration reaches too few fights for a magnitude to matter, and every test
showed support-heavy sides getting **FASTER** with more healing — it was acting
as a tempo multiplier, not an attrition brake. `HEAL_MULT` **deleted** per the
isolation-term standard ("if it is still null then, delete it").

**Timing beat size.** `healPolicy: 'triage'` (hold a restore until an ally is at
or below `TRIAGE_AT` 0.55) did in one commit what no coefficient could: the trio
golden's worst survivor went 18 HP → 303, duration 14.4s → 16.9s.

Heals also now scale with their stat like damage always has, and so does
`hpRegenBuff` — both halves of a restore move together, or regen-led moves
(Renewal) silently fall behind their own line-mates.

### Reachability — the session's recurring failure mode

Content that is authored, priced, lined, range-checked and `validate.ts`-clean
can still **not exist**, because one number put it above what anyone reaches.
Four instances:

- `basicAttackFor` derived a monster's channel from its inventory — a Warrior
  that drafted one Piercing Shot became a ranged unit at 6.4. ⚠️ **Second copy of
  a bug already fixed once in `reachOf`.**
- 92 moves carried a `range` that *looked* authored: 13 distinct values
  partitioning cleanly by channel, so an Assassin stiletto reached 5.6 because
  DEX is typed `ranged`.
- `Mending Surge` (lv400) and `Second Wind` (lv480) drafted by **1 monster in
  320** — above WIS/CHA p90 (355/396). Repriced to 300/340 → 10/320, 21 casts.
- `Tranquility` (lv430) — caught by the new guard on its first run.

`src/reachability.test.ts` pins both tiers. ⚠️ **The pair is the point:** 67
unreachable at mid-game is *progression*; unreachable at ELITE would be a defect
(currently 0).

### Changes shipped, with their measurements

| change | effect |
|---|---|
| free attack authored per class (`CLASS_BASIC`, four bands) | 31.7% → **0%** of monsters standing outside their own basic |
| all 137 moves author a `range`, seeded per LINE | 13 → 46 distinct values |
| knockbacks travel + cost control (`KNOCKBACK_SPEED`) | max single-tick move 3.09 → **1.28** units |
| timer 120→300s, sudden death 90→255s | **inert by design** — 0/40 reached even the old SD |
| `maxHp` superlinear: `40 + CON*2 + CON²/1600` | CON 1000: 2040 → **2665** |
| `statScale` −10% (LOW 1/360, HIGH 1/145) | mid 18.8s → **26.1s**, spread ~5× → **7.5×**, kills UP |
| `MIT_DIVISOR` 1400 → 1250 | +2.6pp DR at CON 300 |
| mitigation KNEE curve replaces the hard cap | never flatlines; 0.550 at 688 → 0.750 at 1400 |
| Tamer Elite cap 1050 / Apex 1100, trained at 2800 / 3500 | the top separates by INVESTMENT, not ceiling |

### ⚠️ THREE COPIES OF THE MITIGATION FORMULA HAD DRIFTED APART

`strike`, the damage estimator, and pierce valuation each had their own copy.
Within one session the estimator kept `1400` after the divisor moved to 1250, and
pierce kept **both** `0.55` and `1400` — so pierce was priced against a curve the
game no longer used. All three now call `mitigationFor(defStat, pierce)`. **One
formula, called everywhere, is the only thing that ends this.**

### Where fights stand, and the open diagnosis

The full ladder resolves 40/40 at every league. ⚠️ **Wood is the outlier of the
whole progression** — 54.7s with a first kill at 15.9s, against a 17–20s band and
5.7–7.4s everywhere above. At cap 100 the flat +40 in `maxHp` and a move's base
power dominate, so a new player's first fights are the slowest in the game.

⚠️ **THE BURST IS THE CASCADE, NOT THE OPENING.** Measured:

- **40%** of a fight elapses before the first death (30% at elite)
- then bodies drop at **0.41/s** — one every ~2.4s, near-constant regardless of
  team size
- the longest shape, Phalanx v Vanguard 3v3 at 81.4s, has only 14%
  pre-first-blood and the **lowest cascade rate** (0.27/s)

Long fights come from a slow cascade, not a slow opening. Drivers: numbers
advantage compounds directly and focus fire is already high (0.65–0.71).

⚠️ **FLANKING: A CORRECT THEORY MEASURED AGAINST A BROKEN IMPLEMENTATION.** This
section first named `+10 acc when outnumbered and unsupported` as the snowball
amplifier — reasoned, not measured. Measurement then showed it firing on **2.2%
of attacks** with zeroing it moving nothing, so the claim was retracted as
inert.

Both readings were partly wrong. The RADII were broken: `FLANK_ENGAGE_RADIUS`
2.6 sat **below melee reach 3.0**, so a melee attacker at its own proper distance
did not register as "on" the target — the mechanic was blind to the exact
situation it exists for — while `FLANK_SUPPORT_RADIUS` 3.2 was **wider than
engage**, so a defender counted as protected by an ally standing further off than
the enemies hitting it. Fixed to 4.0 / 2.5: fire rate **2.2% → 17.5%**.

And with working radii the original theory held exactly. At +10 it cut mid 26.1s
→ **20.0s** and elite 19.5s → **17.2s** — a real amplifier, pointed at the side
already losing, and directly against the goal of longer fights. Halved to **+5**:
live at 17.5% for a cost inside the noise band (mid 25.4s, elite 17.7s).

⚠️ **The lesson is the difference between the two readings.** A null result
refutes the CODE, not the idea — check whether the mechanism can fire before
concluding the design is wrong.

⚠️ **A defensive bonus when outnumbered ("last stand") was proposed and REJECTED
on design grounds** — prolonging a fight that is already decided is not the same
as making it competitive. Do not re-propose it.

The next move is an EFFECT REACHABILITY AUDIT instead. Six mechanisms this
session turned out not to reach, and `guard`, `ward`, `thorns`, `protect` and
`taunt` have never been fire-rate checked. Find what is already inert before
adding anything new — see `tools/effects.ts`.

Leave `maxHp` and `statScale` alone: the first compresses the spread, and the
second is the PROGRESSION axis (trimmed 10% and reverted the same day — with the
opening guard, MIT_SOFT and COOLDOWN_MULT in place it was carrying nothing).

### Standing method notes earned this session

- ⚠️ **Measure which mechanic is FIRING before tuning the one you assume is.**
  Three commits tuned `DASH_SPEED_MULT` against a fight where no dash ever fired,
  and against a GIF playing at 4.5× real time.
- ⚠️ **A bimodal displacement histogram is the tell** for something bypassing a
  system: 1532 ticks ≤0.5 units, nine at 1.8–3.1, nothing between.
- ⚠️ **Read the per-composition rows, not the total.** A 22.5s mean at Tamer
  Elite was one 256s fight in 200; the other four batches sat at 17.2–18.0s.
- ⚠️ **Reversing a measured decision is correct when what it optimised for is no
  longer what is wrong.** `STAT_SCALE_HIGH` was raised on p=0.0066 when fights
  were not resolving; that is solved, and the problem inverted.
- ⚠️ **Where a control-loss gate sits in the tick is load-bearing.** Knockback's
  gate placed above the per-unit timers froze cooldowns, mana and status
  durations — `duel-melee` went 15s → 91.5s.


## ⚠️ THE 40-MATCHUP SWEEP FIGHTS MONSTERS WITH NO TACTICS (2026-08-01)

`generateMonster` does not set `tactics`, and `tools/comps.ts` does not add any. So
every unit in the sweep — and in `tools/ab.ts`, `tools/effects.ts`, `tools/focus.ts`
and `tools/leagues.ts`, which all build teams the same way — has
`m.tactics === undefined`.

**Every tactic that reads `m.tactics` is therefore invisible to the balance
harness.** `targetPriority`, `temperament`, `preserve`, `formation`, `commit`,
`useCover`, `healPolicy`, `manaPolicy`, `ccPriority`: all of them fall through to
their no-order branch in a sweep, in an A/B, and in every league run.

How it surfaced: melee target priority was fixed (`MELEE_PRIORITY_SLACK`), the
`trio` golden moved 27.6s → 23.6s, and the sweep reported **byte-identical** totals
at slack 0, 4, 6, 10 and 14 — 23.9s, 188 kills, 2781 damage every time. Not a small
effect. No effect, because there was no order to obey.

⚠️ **So "the sweep says nothing changed" is not evidence about anything tactical.**
Re-read past sessions with that in mind: several tactics were called inert on sweep
evidence that could not have detected them either way.

Measured with orders applied (`DEFAULT_TACTICS` on both sides, 40 fights):

| `MELEE_PRIORITY_SLACK` | mean | median | kills | range |
|---|---|---|---|---|
| 0 (order dead on melee) | 23.2s | 22.0s | 185 | 9.6–40.9s |
| 4 | 24.1s | 22.6s | 189 | 9.6–52.9s |
| 6 | 23.7s | 23.9s | 194 | 9.6–52.5s |
| 10 (shipped) | 23.1s | 19.9s | 193 | 9.6–68.9s |
| 14 | 23.1s | 23.2s | 193 | 9.6–51.5s |
| *no tactics at all* | 23.9s | 22.8s | 188 | 9.6–48.0s |

Means are flat inside the documented sd 0.7 band — the fix is not a burst
accelerator at the default `weakest` priority, which is the reassuring half. The
signed effect is on the ordered metric instead (`tools/priority.ts`).

### ✅ FIXED — `generateMonster` now sets `DEFAULT_TACTICS`

⚠️ **Fixed at the SOURCE, not in the harness.** Patching `tools/comps.ts` would have
repaired the four tools that exist today and left the trap armed for the fifth. Every
tool builds its teams from `generateMonster`, so that is where the floor belongs.

⚠️ **Absent `tactics` and `DEFAULT_TACTICS` were never the same thing.** Absent means
`targetPriority` is undefined and `priorityBias` returns 0 — a monster fighting with
part of the AI switched off. The real game overwrites this anyway (the pre-fight
orders screen and `GAMEPLANS` both assign tactics), so this is a floor whose job is
to make "nobody set orders" mean the same thing everywhere.

**No goldens moved.** Neither engine's fixtures changed: the field goldens already
set `DEFAULT_TACTICS` explicitly, and the turn engine's no-tactics path already
behaved as `weakest`. 203 tests green.

**The smoke test that proves the instrument works now** — one constant, five values,
five different answers where there had been one:

| `MELEE_PRIORITY_SLACK` | resolved | dur | kills | dmg/fight |
|---|---|---|---|---|
| 0 | 40/40 | 23.2s | 185 | 2739 |
| 4 | 40/40 | 24.1s | 189 | 2773 |
| 10 | 40/40 | 23.1s | 193 | 2709 |
| 14 | 40/40 | 23.1s | 193 | 2763 |
| *(before the fix, ALL values)* | 40/40 | 23.9s | 188 | 2781 |

### Then: every composition got its own PLAN

Setting `DEFAULT_TACTICS` everywhere fixed "no orders" but left a second, quieter
gap: **the harness spanned ten SHAPES and exactly one PLAN.** Every composition
fought on identical neutral orders, which is not a thing that happens in the game —
rival teams carry a `TeamGameplan` and players pick orders before every match.

Each `TeamTemplate` now declares a `gameplan`, and `tools/comps.ts:teamFor()` builds
species, training **and** orders together:

| template | gameplan | why |
|---|---|---|
| Phalanx | `bulwark` | turtle behind the wall and protect the carry |
| Coven | `zone` | back-row casters hunting the fragile — an all-caster side has no other plan |
| Wolfpack | `rushdown` | fast, aggressive, no support |
| Choir | `attrition` | wants the clock and out-sustains you |
| Vanguard | `focusfire` | front-loaded burst, ends it before sustain matters |
| **Hammer & Anvil** | **none** | ⚠️ the CONTROL — see below |

⚠️ **REUSES `GAMEPLANS`, DOES NOT INVENT A HARNESS-ONLY VOCABULARY.** These are the
five plans rivals field and players scout. Authoring separate tactics for the sweep
would put it back to measuring fights that happen nowhere in the game — the exact
mistake `tools/comps.ts` was written to undo.

⚠️ **ONE TEMPLATE IS DELIBERATELY UNPLANNED.** Without an unordered composition the
sweep cannot separate "this plan helped" from "having any plan at all helped".
Hammer & Anvil mirror came out at **17.1s / 14 kills before and after** — byte
identical, which is the self-check that the control is genuinely a control.

⚠️ **AND `teamFor()` IS NOW THE ONLY WAY IN.** The per-tool `mk = generateMonster(...)`
helpers are deleted, not merely unused. Nine independent call sites each failing to
add tactics is how the original hole stayed open; leaving a local builder next to a
COMPS loop is an invitation for the next edit to reopen it.

What the plans did to the fights — the matchups now behave like their briefs:

| composition | uniform orders | own plans |
|---|---|---|
| Phalanx mirror 6v6 (bulwark mirror) | 27.0s | **30.1s** — turtles grind |
| Vanguard v Choir 5v5 (focusfire v attrition) | 43.5s | **49.3s** — the sustain question, now the longest fight |
| Coven mirror 2v2 (zone mirror) | 16.8s | **14.1s** — glass trades faster |
| Hammer & Anvil mirror 3v3 (control) | 17.1s | 17.1s |

### ⚠️ NEW REFERENCE NUMBERS — everything above this section was measured tactics-off

| sweep | resolved | dur | kills | dmg/fight |
|---|---|---|---|---|
| mid (train 850) | 40/40 | **24.5s** | 199 | 2762 |
| elite (train 3200) | **40/40** | **26.5s** | 200 | 9928 |

⚠️ **Elite now resolves 40/40 and got FASTER (33.6s → 26.5s).** The one fight that
used to run out the clock was two teams with no plan grinding each other; give both
sides a win condition and somebody executes it.

⚠️ **The noise band WIDENED — sd 0.60s → 0.93s, so a change must now beat ~1.9s.**
That is the honest price of the change: distinct plans interact with distinct shapes
differently per seed, so the instrument is more realistic and less precise at once.
Do not read the wider band as the harness getting worse — it was previously narrow
because every fight was the same fight. `resolved` remains at ceiling and useless.

⚠️ **Treat every figure recorded in this document before 2026-08-01 as measured with
all tactics disabled.** They are not wrong about the things they measured — pool
damage, mana, mitigation, HP scaling — but any conclusion that touched targeting,
positioning, healing discipline or mana policy was drawn from fights where those
orders did nothing.


## Two early detonators — Fester + Twist the Knife (2026-08-01)

Pool 139 → 141. Full rationale in `docs/TACTICS.md`; the balance summary:

| | before | after |
|---|---|---|
| `bonusVsStatus` moves | 8 | 10 |
| monsters drafting one | 175/640 (27%) | **308/640 (48%)** |
| payoff casts | 638 | 948 (8.0% of all casts) |
| combo connect rate | 18.0% | **33.6%** |
| sweep total | 24.5s / 199 kills | **22.9s / 197 kills / 2773 dmg** |

⚠️ **Four goldens recaptured, deliberately** — a pool addition re-drafts every kit,
which CLAUDE.md already names as a reason goldens move. One (`3v3-high`) **flipped
winner, A → B**. That is the loudest a golden gets, and it is the honest consequence
of adding content a train-2000 kit will draft. If a later change flips it back, that
is a new question, not a return to normal.

⚠️ The sweep dropped 24.5s → 22.9s, **inside the ±1.9s noise band** — do not read it
as a burst regression on this evidence alone. Re-measure if it persists.


## Combo templates — Vivisect + Contagion (2026-08-01)

Two templates designed around `comboRole`, with **per-slot roles** (`TeamTemplate.roles`):

- **Vivisect** — `skirmish/front/caster`, roles `prime/detonate/–`, gameplan `focusfire`
- **Contagion** — `skirmish/caster/support`, roles `prime/prime/–`, gameplan `attrition`

⚠️ **Contagion is the CONTROL.** It spreads the same statuses and never cashes them,
which is a legitimate shape (affliction is damage) and, more importantly, stops
"combo templates win" being confounded with "status templates win".

Sweep grows 40 → 48 matchups (12 compositions). New baseline: **48/48, 23.3s, 230
kills, 2803 dmg/fight**. The header is now derived from `COMPS.length` rather than
hard-coded, so the next addition cannot silently mislabel itself.

### ⚠️ A SLOT CANNOT PROMISE A MOVE — the first version of this was broken

`speciesForTemplate` picks a species by stat affinity and `chooseLoadout` then drafts
from that stat's LINES, so which status a monster carries is decided **downstream of
the template**. Measured on the first cut, where roles were applied by slot alone:

- Vivisect's `detonate` slot is a front-liner — **one of eight** drafted any payoff.
- Its `prime` slot kept landing Rogues holding a poison applier **and its payoff** —
  monsters told to set up for someone else when they could have cashed it themselves.
- Bleed's connect rate **fell 10.7% → 3.0%**, worse than no roles at all.

That is this project's signature failure one layer up: an authored order the system
cannot reach. Fixed by `resolveRole()` in `tools/comps.ts` — the declared role is a
**preference checked against the kit**, so a monster is never handed a job it has no
move for, nor stripped of one it could do. Bleed recovered to **9.8%**.

### ⚠️ AND THE ROLES DO NOT WIN FIGHTS

| test | result |
|---|---|
| Vivisect v Contagion, 12 seeds | **11 – 1** to Vivisect |
| Vivisect v Phalanx, 12 seeds | 4 – 8 — a wall outlasts the setup |
| **Vivisect MIRROR, roles vs no roles, 32 mirrored fights** | **15 – 17** |

The 11–1 is **the shape, not the roles**. Strip the roles from one side of a Vivisect
mirror and it is dead even. `comboRole` demonstrably fires and demonstrably raises
bleed's connect rate ~6×, and that is still worth too little to move a win rate: only
61 bleed payoff casts exist across the sweep, so five extra connections at ×1.5 on a
38-power move is noise.

**The honest state:** the combo system works mechanically and is not yet worth
building around. The payoffs that get drafted most (burn, poison) already self-combo
and need no coordination; the one that needs it (bleed) is drafted rarely. The levers
to try next, in order: raise the early payoffs' multipliers, or make the cross-stat
appliers more likely to be drafted — NOT more tactics.


## Cooldowns are SECONDS now (2026-08-01)

`Move.cooldown` meant two things at once: `battle.ts` documented it as "turns
remaining", the field engine did `cooldown * COOLDOWN_MULT + castTime` and
decremented by `DT`. Worse, **four places authored it in three different units**:

| source | authored | effective on the field |
|---|---|---|
| `src/moves.ts` (141) | 1–9, turns | ×1.3 |
| `src/signatureMoves.ts` (50) | 5–6, turns | ×1.3 |
| `src/tamerengine/fieldMoves.ts` (18) | 4–26, **already seconds** | ×1.3 again |
| `engine.ts:basicAttackFor` | 0.55, **already seconds** | ×1.3 again |

`Disengage` at 26 became **33.8s** on a field whose median fight is 23.3s.

**The conversion:** every authored cooldown ×1.3, `COOLDOWN_MULT` 1.3 → 1.0, and
`core.ts:SECONDS_PER_TURN = 1.3` for the two consumers that still need turns.
Values are deliberately ugly (1.3 / 2.6 / 3.9 …) — this is a *rename*, and making
them round numbers is a balance pass that has to be measured separately.

✅ **Provably behaviour-neutral.** 218 tests green with **no golden movement**, and
both sims byte-identical: sweep 48/48 / 23.3s / 230 kills / 2803 dmg, combo connect
1175 casts / 384 / 32.7%.

### ⚠️ THREE CONSUMERS THE RENAME BROKE, AND THE GOLDENS CAUGHT ALL THREE

The first attempt moved three field goldens by up to **5.4s**. The causes, in the
order they were found — each one only visible after the previous was fixed:

1. **`monster.ts:expectedOutput`** — the loadout picker discounts by
   `(cooldown − 1) × COOLDOWN_DISCOUNT`, a constant calibrated against turns 1–9.
   Fed seconds it inflated every discount and **re-drafted every kit**. Now divides
   by `SECONDS_PER_TURN`.
2. **`engine.ts:basicAttackFor`** — a **fourth** authored cooldown, inline, already
   in seconds, still multiplied. Retiring the multiplier made the free attack 30%
   faster; it is the highest-frequency action in the game.
3. **`battle.ts`** — the write site now converts via `turnsOf()`. ⚠️ Zero must stay
   zero: a bare `Math.max(1, …)` would have put the free attack behind a one-turn
   wait it never had.

⚠️ **A float hypothesis was tested and REFUTED before any of these were found.**
`3 × 1.3` is `3.9000000000000004` in JS while the authored literal is `3.9`, so
cd 3/6/9 (40 moves) differ by ~1e-15 — a tempting explanation. Reproducing the old
product exactly still failed, which is what forced the search to continue. Had that
test not been run, the goldens would have been recaptured over three real bugs.


## Less bursty: damage down, mitigation up (2026-08-01)

Two levers, **measured independently first** because both push the same direction
and moving them together would make neither attributable.

### ⚠️ MITIGATION IS NOT A DURATION LEVER — a clean null

`MIT_DIVISOR` swept over its whole usable range, mid sweep:

| divisor | mitigation @CON455 | @CON1000 | duration | kills |
|---:|---:|---:|---:|---:|
| 1250 | 36.4% | 67.5% | 24.6s | 250 |
| 1150 | 39.6% | 71.0% | 24.2s | 246 |
| 1050 | 43.3% | 75.1% | 24.6s | 246 |
| 950 | 47.9% | **80.0% (ceiling)** | 24.9s | 244 |

**+0.3s across the entire range.** Damage per fight falls (2985 → 2868) and kills
fall slightly, but the clock does not move. This is the same shape as the statScale
trim that was reverted: per-hit numbers set time-to-FIRST-blood, and ~60% of a fight
happens after that, governed by the numbers advantage. `COOLDOWN_MULT` remains what
this document already called it — the one lever that slows the cascade too.

### Damage is a slightly better lever, and still weak

| `DAMAGE_MULT` | duration | kills |
|---:|---:|---:|
| 1.00 | 24.6s | 250 |
| 0.92 | 24.2s | 237 |
| 0.85 | 26.5s | 233 |
| 0.78 | 27.0s | 242 |

### Applied: `DAMAGE_MULT` 0.92, `MIT_DIVISOR` 1150

The gentle first increment, per the standing rule. Combined result:

| | before | after |
|---|---|---|
| mid | 48/48, 24.6s, 250 kills | 48/48, **26.2s**, 246 |
| elite | 48/48, 29.0s, 237 kills | 48/48, **30.0s**, 234 |

⚠️ **AND +1.6s IS NOT A DEMONSTRATED EFFECT.** The noise band re-measured on this
build is **sd 1.96s → a change must beat ~3.9s**. Mid's +1.6s and elite's +1.0s are
both inside it. This is a direction taken in a small increment, not a proven result;
the next increment is 0.85 / 1050, which put elite at 35.0s — the first reading that
clears the band.

⚠️ **THE BAND ITSELF DOUBLED, 1.9s → 3.9s**, and that is unexplained. It widened
somewhere between the gameplan pass and here. Chase it before trusting any
fine-grained duration reading — a doubling of measurement noise matters more than
either constant.

⚠️ **`DAMAGE_MULT` IS A DIAL, NOT A DECISION.** Once a value settles it must be
BAKED INTO THE AUTHORED POWERS and the constant returned to 1.0, or
`docs/ABILITIES.md` prints numbers the engine does not use — the exact failure the
generated doc exists to prevent.

✅ It scales the FREE ATTACK too (the basic resolves through `strike()`), so the
"never below the free attack" floor holds without touching `BASIC_BASE_POWER`. An
earlier draft of the constant's comment claimed the opposite; acting on it would
have double-cut the basic.


## The free attack, cut — and where it stops (2026-08-01)

`BASIC_STAT_SCALE` 1/70 → **1/90**. `BASIC_BASE_POWER` held at **5**.

⚠️ **THE FREE ATTACK IS NOT A DURATION LEVER EITHER** — the third null in a row.
Sweeping `BASIC_BASE_POWER` 5 → 2 (a 32% cut to the swing):

| base | STR455 power | share of casts | share of damage | duration |
|---:|---:|---:|---:|---:|
| 5 | 9.6 | 32.0% | **14.7%** | 26.2s |
| 4 | 8.6 | 32.5% | 13.2% | 26.1s |
| 3 | 7.5 | 33.2% | 11.8% | 25.1s |
| 2 | 6.5 | 32.6% | **9.6%** | 25.6s |

Damage share falls by a third; the clock does not move. What cutting the basic
actually buys is **share** — less of a fight decided by the filler, more by what the
monster drafted. That is the reason to do it, and it is not the reason it was asked
for.

⚠️ **AND CUTTING THE FLAT FLOOR PRODUCED A DRAW.** `base 4 + scale 1/105` (a −26%
free attack) pushed a fight to **112.1s against status.test.ts's 90s bound** and
dropped elite to 47/48. The free attack IS the filler: take enough away and a
grinding matchup has nothing left to close with. The invariant caught it; the sweep
alone would not have, because mid actually got *faster* (24.3s) while a single elite
grind blew out.

**Why the SCALE and not the floor.** The floor is what the weakest monsters lean on —
a Wood-league kit is mostly this swing — so cutting it is regressive. The scale is
progressive, and lands where abilities are strong enough to cover the slack:

| | Wood | Tin | mid | Masters | Apex |
|---|---:|---:|---:|---:|---:|
| 1/70 → 1/90 | −4% | −8% | −11% | −13% | −15% |
| (rejected) base 4 + 1/105 | −22% | −25% | −26% | −28% | −29% |

**Result:** mid 48/48 **26.6s**, elite 48/48 **30.3s**, free attack down to ~13% of
damage dealt. ⚠️ Still inside the ±3.9s band — a direction, not a proven effect.


## ⚠️ A GRIND-LOCK IN THE ENGINE — found tuning COOLDOWN_MULT (2026-08-01)

Swept gradually from 1.0, watching the cast mix as this document's own warning
demands. The clock is not the finding:

| `COOLDOWN_MULT` | no-draws bound | basic % dmg | mid | elite |
|---:|---|---:|---:|---:|
| 1.00 | ✓ | 13.7% | 26.6s | 30.3s |
| 1.02 | ✓ | — | 27.3s | 31.8s |
| 1.03 | ✗ **110.7s** | — | — | — |
| 1.05 | ✗ **256.6s** | 13.6% | 27.0s | 33.8s |
| 1.08 | ✓ | — | — | — |
| 1.10 | ✓ | 14.6% | 27.9s | 32.5s |
| 1.15 | ✓ | 15.0% | 26.3s | 35.3s |
| 1.20 | ✓ | 14.7% | 26.0s | 36.3s |

**One fixture in `status.test.ts`'s 24-fight spread flips between resolving normally
and grinding to 256.6s — against a 300s engine cap — on a 1% parameter change, and
flips BACK by 1.08.** That is not a tuning threshold. Some matchup reaches a state
where neither side can close, and which constants trigger it is chaotic.

⚠️ **The sweep median never sees it.** At 1.05, mid reads 27.0s and elite 33.8s —
both healthy. A hard invariant caught what an aggregate hid, for the second time
today (the free-attack cut did the same thing).

⚠️ **CHASE THE GRIND-LOCK BEFORE TUNING COOLDOWNS FURTHER.** The usable range is
pocked with values that look fine on the median and blow one fight out to four
minutes. Worth doing, because this IS the lever: elite rises 30.3s → 36.3s across
the range, the only reading all session that clears the ±3.9s band. Mid stays flat
throughout, which says the same thing three other levers said — mid duration is
governed by the cascade, not by throughput.

**Applied: 1.02**, the only gradual step with clear headroom. mid 27.3s, elite 31.8s,
48/48 both. Honestly: it buys nothing measurable. It is a placeholder until the
grind-lock is understood.

### Session summary — four levers, one signal

| lever | mid duration | verdict |
|---|---|---|
| `MIT_DIVISOR` 1250→950 | +0.3s | **null** |
| `DAMAGE_MULT` 1.0→0.78 | +2.4s | inside noise |
| free attack −32% | −0.6s | **null** (but −5pp damage share) |
| `COOLDOWN_MULT` 1.0→1.20 | −0.6s | **null at mid, +6.0s at ELITE** |

⚠️ **Mid-game fight length has not responded to anything.** Four independent levers,
one direction each, all null. That is now a strong enough pattern to stop treating
it as a tuning problem: if mid fights should be longer, the cause is structural —
`maxHp`, the cascade, or the numbers advantage after first blood — not per-hit
throughput.


## The grind-lock, diagnosed and fixed (2026-08-01)

`COOLDOWN_MULT` reverted to **1.0** — the 1.02 step bought nothing measurable and
existed only as a placeholder while this was chased.

### It was a MUTUAL RETREAT STANDOFF

The 256.6s fight, instrumented. Three survivors, t=60 to t=250:

| t | alive | |
|---:|---|---|
| 60s | 3 | A2 hp 18% mp 40% · B1 hp 17% mp 68% · B2 hp 16% mp 91% |
| 250s | 3 | A2 hp 11% mp **75%** · B1 hp 13% mp 69% · B2 hp 16% mp **100%** |

In the last 197 seconds: **4 hits landed**, against **39 fallbacks**, **16 abandoned
chases**, and **27 casts of Enrage** on an already-buffed self. Mana *refilled to
100%*. They were not starved, not out-healing, not on cooldown — **they were running
away from each other**.

`decide.ts:retreatThreatOf` returned the nearest enemy whenever the unit was below
its panic threshold, with no check on whether that enemy could do anything. Once
every survivor is wounded, each flees the others and the fight stops. Whether all
survivors dip under the threshold together is exquisitely sensitive to damage rolls
— which is why it read as a *chaotic* failure at `COOLDOWN_MULT` 1.03 and 1.05 that
vanished again by 1.08.

**Fix:** do not retreat from an enemy that is itself below its own panic threshold.
Retreat exists to break contact with something that can still kill you; a unit at
13% HP is not that.

**Result:** that fight 256.6s → **66.4s**, and the no-draws bound now passes at every
cooldown value from 1.0 to 1.20 — the tuning range is no longer pocked with
landmines. Sweep: mid **25.6s**, elite **29.5s**, 48/48 both.

### ⚠️ AND THE TEST'S 90s BOUND WAS STALE

With the lock fixed, 1.03 still failed — at 110.7s, a *completely different* fight:
231 casts, 167 hits, **64.5 damage/s**, 18 heals, one team's sustain out-lasting the
other and then wiping it 3-0. That is attrition working, not a lock.

The 90s bound predates the 5-minute clock and the stated design goal of a SPREAD
("some maybe 1 minute, some may be 4, that's the variation the builds will allow").
Raised to **150s** — still catches a lock, which trends toward the 255s sudden-death
point, while leaving room for an honest grind.

⚠️ **The two assertions in that test are not the same guard.** `draws === 0` is the
invariant. The duration bound is a lock DETECTOR, and it earned its keep here — it
caught the standoff that the sweep median never saw. Do not delete it; keep it
calibrated.

⚠️ **Still unfixed: 27 casts of `Enrage` on an already-buffed self.** A unit with no
reachable target falls back on re-casting buffs it already has. Separate defect,
cheap to fix, and it will make any idle-time measurement honest.


## 6v6 REMOVED — the game caps at 5v5 (2026-08-01)

User spec. `TEAM_SIZE_BY_LEAGUE` now tops out at 5; `validate.ts`'s guard is
re-pointed from "6 is the max, and reserved for the summit" to "5 is the max".

⚠️ **THE SUMMIT FIGHT WAS THE QUICKEST ONE.** Measured with `compAtSize` — same
pairing, same league, same seeds, median of 8, only the size differing:

| league | pairing | 5v5 | 6v6 | delta |
|---|---|---:|---:|---:|
| Gold | Vanguard v Choir | 42.4s | 27.2s | −15.2s |
| Gold | Phalanx mirror | 59.7s | 33.1s | **−26.6s** |
| Platinum | Phalanx mirror | 46.3s | 34.9s | −11.4s |
| Masters | Vanguard v Choir | 47.3s | 41.1s | −6.2s |

A sixth body puts more damage on the field and brings the cascade sooner. The
effect is largest at Gold and smallest at Masters — at a low cap an extra body is
proportionally more throughput.

### The sweep moved more than four tuning levers managed

| | before | after |
|---|---|---|
| mid | 48/48, 23.3s, 230 kills | 48/48, **27.8s**, 238 |
| elite | 48/48, 29.5s, 229 kills | 48/48, **30.3s**, 221 |
| noise band | ±3.9s | **±2.8s** |

⚠️ **+4.5s at mid CLEARS the band** — the first change all session to do so. Four
levers swept independently (mitigation, global damage, the free attack, cooldowns)
all came back null at mid; removing a body did in one edit what none of them could.
That is the same conclusion from the other side: mid duration is set by how fast the
cascade runs, and the cascade is driven by how many bodies are on the field.

✅ **And the noise band NARROWED, 3.9s → 2.8s.** The doubled band flagged as
unexplained earlier was at least partly the 6v6 compositions: the biggest fights
carried the widest per-seed spread. Measurements from here are sharper.

⚠️ `Phalanx mirror 5v5` is now the sweep's longest composition at **61.8s** (it was
30.1s at 6v6). The tank mirror grinds, and at 5v5 it grinds twice as long — worth
watching as the shape most likely to reach the clock.

### ⚠️ Two things this costs

1. **The ladder plateaus at Platinum.** Platinum, Masters, Tamer Elite and Tamers
   Apex all field 5. Progression past Platinum is now stat cap and roster quality
   only — a progression axis has been removed and is worth replacing at the summit.
2. **`frontRowCount`'s `>= 6` branch is dead code.** Kept deliberately: it is the
   only record of why the wall ever widened ("six bodies behind two shields left the
   back far too safe"). If a larger fight ever returns, that reasoning applies again.


## A buff stacked with itself — 17 moves (2026-08-01)

⚠️ **NOT WASTED CASTS. COMPOUNDING ONES.** `modAtk` MULTIPLIES every entry in
`FieldUnit.mods` and guard/thorns/dodge/acc/hpRegen/regen all ADD, and
`resolveUtility` pushed a fresh mod on every cast with no dedup. Re-casting a buff
did not refresh it — it stacked.

And it was the normal case, not an edge one. **17 pool moves re-arm before their own
effect expires**, so anything holding one sat permanently multi-stacked:

| move | effect | duration | recharge | overlap |
|---|---|---:|---:|---:|
| Brace | guard | 6.0s | 3.0s | **×2.00** |
| Sunder | defDebuff | 6.0s | 4.0s | ×1.48 |
| Renewal | hpRegenBuff | 8.0s | 5.6s | ×1.43 |
| Guard | guard | 6.0s | 4.3s | ×1.40 |
| …13 more | | | | ×1.04–1.16 |

**Fix:** every mod carries the `src` move id, and `bestUtility` refuses a move whose
own mod is still live on the aim. ⚠️ **Keyed on the MOVE, not the effect** — two
different moves granting `atk` are *meant* to stack; that is what makes a Captain
worth fielding beside a Warcry. Only self-reapplication is blocked.

Found in the grind-lock trace, where a unit with no reachable target cast `Enrage`
27 times in 197 seconds — every one of them multiplying its own attack.

**Effect:** sweep 27.8s → 27.2s, 238 → 233 kills, 2774 → 2751 dmg — all inside the
±2.8s band, and **no goldens moved**. The bug was real and its aggregate cost small,
because buff-heavy kits are a minority. Verified firing directly rather than
inferred from the aggregate: `Brace` in a 21.7s fight casts 3×, against a ceiling of
4 with the gate and 8 without. Pinned by a test.

## THE GOLDENS ARE FROZEN (2026-08-01)

They moved ~10 times in one day. A fixture recaptured every commit detects nothing —
it records. The pool is stable (141 moves, 48/48), so both suites now carry a policy
header:

1. A golden moving is a **question**, not a chore — answer it before editing.
2. Deliberate change → recapture **and write the reason on the fixture**.
3. **Cannot name the cause → DO NOT RECAPTURE.** Twice today a golden moved for what
   turned out to be a real bug: a loadout picker fed the wrong unit, and a free
   attack silently made 30% faster. Both would have been papered over — and the
   second was found only because a plausible float explanation was tested and
   **refuted**.
4. `tools/regold.ts` serves step 2. It is never permission to skip step 1.

## `DAMAGE_MULT` baked into the pool (2026-08-01)

The ledger's own instruction from the pass above — *"once a value settles it must be
BAKED INTO THE AUTHORED POWERS and the constant returned to 1.0"* — carried out.
141 authored powers ×0.92, rounded to integers; `DAMAGE_MULT` 0.92 → **1.0**, kept
as a neutral dial exactly as `COOLDOWN_MULT` was after the seconds conversion.

**Effect:** 48/48, 27.2s → **27.1s**, 233 → **233** kills, 2751 → **2731** dmg.
Flat, well inside the ±2.8s band.

⚠️ **IT WAS NOT A PURE REFACTOR, AND THE GOLDENS SAID SO FIRST.** All seven moved.
Both causes were isolated by re-running with **unrounded** powers, which splits them
cleanly:

| | held unrounded? | cause |
|---|---|---|
| `duel-melee`, `caster-vs-brawler` | ✅ bit-identical | integer rounding, ≤2.7% on any one move |
| `1v1-low/high`, `2v2-mid`, `3v3-high` | ❌ still moved | a real 8% cut to **battle.ts** |
| `trio` | ❌ still moved | `UTILITY_FLOOR`, below |

⚠️ **THE TURN ENGINE WAS RUNNING THE SAME POOL 8% HOTTER.** `DAMAGE_MULT` lived in
tamerengine's `strike()`; `battle.ts` never applied it. One pool, two damage levels —
a bug the dial was hiding, and baking is what fixed it. `3v3-high` flips winner; it
is the fixture that runs to the round-35 sudden-death clock, the state most sensitive
to total damage in the air.

⚠️ **A DIAL AT RESOLUTION IS INVISIBLE TO DECISIONS.** `bestUtility` weighs its score
against a raw `power` (`Math.max(UTILITY_FLOOR, mv.power)`), and that comparison never
saw the multiplier. Powers dropped 8%; the floor had to follow (8 → **7.4**) or the
bar a utility effect must clear would have silently risen. Chosen on **units, not the
sim** — 27.1s/233 against 27.4s/234, a 0.3s gap inside a 2.8s band, so the 48-fight
sweep says the choice is free. One fixture disagrees loudly (`trio` swings 30.9s ↔
38.6s) and one fixture is not evidence.

⚠️ **Scaling that floor does NOT restore the pre-bake fight** — `bestUtility` mixes
power-derived terms with HP-derived ones and HP did not move, so no single scalar on
it can neutralise a pool-wide power change. Two drafts of the code comment claimed
otherwise before the runs were diffed. Rule 3 of the freeze, working as intended.

**Left for a separate, measured step:** the powers are now integers rounded off 0.92
(17, 21, 31…), not re-authored to round design numbers. Re-authoring is a rebalance
and wants its own sweep — bundling it here would have been the rename-plus-reprice
the cooldown conversion was explicitly split to avoid.

## The pool audit closed out — and four instrument bugs behind it (2026-08-01)

`tools/pool.ts` went 12 flags → **0** across all six stats. Only four of those were
repriced. The other eight were the tool.

**The four real reprices** (sweep 27.1s → **25.4s**, 48/48, 231 kills, inside band):

| move | change | why |
|---|---|---|
| `Fester` lv220 | cd 3.9 → **2.6** | a detonator's axis is TEMPO, not power — it must fire while the poison is up, so it takes its applicator's cooldown rather than a bigger number |
| `Colossus Crash` lv850 | power 31 → **26** | 1.68× its CON cohort with three riders. CON protects; a capstone that is mostly riders IS the identity |
| `Mana Leech` lv335 | power 44 → **34** | 1.96× the tier-normalised all-stat norm for its level, *plus* mana burn *plus* 25% lifesteal |
| `Arcane Overload` lv850 | power 129 → **168** | lost to `Void Lance` 70 levels earlier on BOTH rates — inverted progression, and the capstone is the one to raise |

**The four instrument bugs**, all of them the same shape:

1. **`target: 'team'` was not AoE.** An enemy AoE was credited at three bodies while a
   team buff covering the identical three was credited at one — so `Ward Against Ruin`
   (lv650, team) read as "dominated" by a lv300 single-target heal.
2. **`hpRegenBuff` was priced as a flat +15% rider.** `Renewal` is power 11 with 10
   HP/round for 4 rounds: the rider is worth **3.6×** the move, not 0.15×. It now
   counts the HP it actually restores.
3. **No resolution floor.** A "dominated" verdict was being issued on a **0.4%** gap
   (`Gambler's Volley` 24.9 vs 25.0/s) when `power` is an authored integer and one
   step is 2.5%. `DOMINANCE_MARGIN` 1.05 — a tool may not resolve finer than its data.
4. **The AoE double-standard, in two more checks.** After the OVERBUDGET cohort was
   fixed for it earlier, it was still live in the PROGRESSION ladder and the DOMINATED
   filter. Unsplit, `Mana Leech` (single target) was reported as failing to progress
   past `Static Chain` (`allEnemies`) — and then flagged HOT-FOR-LEVEL by a different
   check. **Two flags, opposite advice, one cause.** Contradictory output was the tell.

⚠️ **INT IS NOT RUNNING HOT — CHECKED BEFORE TOUCHING IT.** Its cohort median is
43.1/s against STR 25.4, which reads as a 70% lead and an inversion of the documented
tier. Re-run crediting AoE at **one** body, INT's median is **17.3** — below STR 25.3
and DEX 28.2, near the bottom. That is the standing rule ("AoE is weak into one body
and strong into three") working exactly as designed: INT buys multi-target dominance
with single-target mediocrity. The documented tier table is not on the same footing as
this reading, so the two must not be compared. A stat-wide rebalance was one keystroke
away and would have been wrong.

## The Wood grind was flat `guard` — and the tool was measuring the wrong fight (2026-08-01)

Wood is the first battle a player ever sees and it ran **34.4s**, against 17–18s for
Copper and Tin. Two things were wrong, one in the instrument and one in the engine.

### The instrument: `leagues.ts` fought every league at 2v2–5v5

**Wood is 1v1** (`TEAM_SIZE_BY_LEAGUE`). Every row ran the standard multi-unit
compositions, so the headline "Wood is the outlier of the whole progression at 41.2s"
described a five-a-side brawl between cap-100 monsters that no Wood player can enter.
Fixed with `compAtSize` — the same helper built for the ten hand-picked species
triples that existed nowhere in the game. ⚠️ **A league is a cap, a BUDGET and a TEAM
SIZE. Two out of three is a different game.**

### The engine: flat `guard` DR against damage that scales 16×

The pacing number is not seconds, it is **hits to kill** (`tools/pacing.ts`):

| league | dmg/hit | HP | hits to kill |
|---|---:|---:|---:|
| Wood | 2.7 | 101 | **37.6** |
| Copper | 13.2 | 168 | 12.7 |
| Iron | 28.1 | 380 | 13.5 |
| Masters | 42.6 | 758 | 17.8 |

`guard` is authored as a flat number in the same units as `power` — but power is
multiplied by `(1 + stat × statScale)` and guard is not. Confirmed by zeroing
`modGuard`: Wood **36.5s → 15.3s** and 37.6 hits-to-kill → 10.7, while Masters moved
17.8 → 16.8. **One authored 6 removes 72% of every hit at Wood and 6% at Masters.**

⚠️ **THE TURN ENGINE NEVER HAD THIS.** `battle.ts` scales guard by CON and folds it
into mitigation; only the field engine subtracts the raw number. Same shape as
`DAMAGE_MULT` living in one engine and not the other — found by measurement, not by
reading either file.

**Applied: `GUARD_MAX_FRACTION` = 0.35.** A cap, deliberately *not* a conversion to a
percentage: guard is flat DR on purpose — strong against chip, weak against a nuke —
and a percentage would delete that identity. The cap only bites where the flat number
was eating most of the blow, the case it was never calibrated for.

**Effect** — the whole ladder, at each league's real team size:

| | Wood | Copper | Tin | Masters | Apex | mid sweep |
|---|---:|---:|---:|---:|---:|---:|
| before | 34.4s | 17.9s | 18.4s | 29.5s | 36.3s | 25.4s |
| after | **18.5s** | 17.3s | 18.1s | 29.3s | 35.8s | 25.2s |

Wood's hits-to-kill 37.6 → **15.0**, inside the 12.1–17.2 the rest of the ladder runs
at. One field golden moved (`trio`, the only one of the three whose kits brace) and is
recaptured. Pinned by a test that asserts the ratio at **two caps an order of magnitude
apart** — at one scale it would pass with the cap removed.

⚠️ **Two hypotheses were measured and REFUTED first**, both of which sounded right and
one of which was written into `leagues.ts`'s own header as fact: the flat +40 in
`maxHp` (halving it buys 3.5s of a 17s gap; removing 75% buys 5.4s) and the free
attack's base power (+4.4s). Neither is the driver. The flat +40 is still a real
low-league distortion and still not worth moving on its own.

## Deployment lattice re-baselined (2026-08-01)

The deploy grid was malformed: columns stepped `√3·size`, rows `1.5·size`, and odd
COLUMNS were offset vertically — half a pointy-top layout and half a flat-top one.
Solve each spacing for a regular hexagon's radius and you get 3.00 and 2.25, so no
regular hexagon could tile it. Fixed by offsetting odd ROWS horizontally instead:
same spacings, now a genuine pointy-top lattice.

⚠️ **THIS MOVED EVERY `autoDeployByRole` PLACEMENT**, so every harness that seats a
team by role re-baselines. Nothing regressed — all still resolve — but the numbers
quoted elsewhere in this file for those tools are from the old grid:

| | before | after |
|---|---|---|
| `sweep40` total | 25.2s, 231 kills, 2739 dmg | **23.2s, 231 kills, 2752 dmg** |
| Wood (1v1) | 17.6s | **17.2s** |
| Copper (2v2) | 16.9s | **18.8s** |
| Masters (5v5) | 28.8s | **30.1s** |

⚠️ **THE GOLDENS DID NOT MOVE, AND THAT IS NOT LUCK** — they pin `placeA`/`placeB`
as literal coordinates rather than deriving them from the hex grid, which is exactly
why a change to deployment geometry could be made at all. 242 tests green with
nothing recaptured.

## Hex board re-scaled — HEX_SIZE 2.6 → 1.4 (2026-08-01)

The deploy zone held six to eight cells for a team of up to five, which is not a
choice. `HEX_SIZE` is a WORLD size, so dropping it multiplies cells rather than
shrinking a fixed set: a zone now offers 24–28 on the small arenas and ~50 on the
large ones, and a bigger arena genuinely gets MORE board rather than the same board
stretched.

⚠️ **The floor is set by monster size, not taste.** Neighbouring centres sit
`√3·size` apart and a monster has radius 0.9, so anything at or below **1.04** lets
two deployed monsters overlap before the fight starts. 1.4 gives 2.42 — 0.6 of
daylight.

⚠️ **It moved every `autoDeployByRole` placement again**, so the arena sweep
re-baselines. Contact times drop across the board (finer cells seat teams slightly
further forward), and the SPREAD is preserved, which is what the shapes are for:

| | contact before | after |
|---|---|---|
| The Sawpit / Ingot Yard (cramped) | 1.3s | **1.1s** |
| The Boards / Wash Pool | 1.5–2.0s | **1.4–1.5s** |
| The Smelt / Long Yard / Blowing House (long) | 2.8–3.5s | **2.5–3.1s** |

All ten arenas still 40/40.

⚠️ **And it exposed a real zone-tagging bug.** `fieldHexCells` only ever tested the
INNER edge of a deploy band (`cx <= zA.x1`), so a cell left of the band's own `x0`
was still tagged as belonging to it. Invisible at radius 2.6 because the first
column landed at 2.6, inside the 1.5 margin; at 1.4 the first column sits at 1.4 and
was deployable while being outside the zone that scouting and the UI describe. Both
bounds are checked now.

## Arenas are built FROM the hex grid, and each side gets 3 ranks (2026-08-01)

Two rules, both of which change how arenas are authored:

1. **`hexArenaSize(cols, rows)`** — an arena is a whole number of hex columns and
   rows, so the grid fills it exactly instead of being laid over the top and leaving
   a ragged strip against the wall. All ten arenas re-expressed; sizes moved by at
   most 1 world unit and aspects by ≤0.05, so the shape design survives intact.
2. **`DEPLOY_COLS = 3`** — the deployment band is exactly three hex ranks, not 24% of
   the width. As a percentage it grew with the arena: a 47-wide board handed you a
   12.8-unit band and a 26-wide one 7.7, so "your back three ranks" meant something
   different on every map.

⚠️ **THE CONSEQUENCE IS THE POINT: width now buys APPROACH, not deployment room.**
Deployment depth is constant across the ladder, so a long arena is a longer walk into
the same formation options. The old test asserting "a wider arena offers more
deployment cells" was correct under the old rule and is now inverted deliberately.

**Effect** — all ten still 40/40, and the contact spread WIDENS to 1.3s → 4.3s
(it was 1.1 → 3.1), because a fixed band leaves more neutral ground on the long maps:

| | contact |
|---|---|
| The Sawpit / Ingot Yard | 1.3s |
| The Boards / Wash Pool | 1.9s |
| The Timberyard / Washfloor | 2.7–2.9s |
| The Long Yard / Leats | 3.6–3.7s |
| The Smelt / Blowing House | 4.2–4.3s |

⚠️ **The centre stump caught a real trap.** It is its own 180° twin only while it sits
exactly at the middle, and it had been hand-placed for a 36×20 field. Resizing to
36.37×19.6 stopped it self-twinning, so `mirror()` emitted a second copy on top of it
and `mapProblems` reported the overlap. Centred obstacles are now derived from the
field rather than typed in.
