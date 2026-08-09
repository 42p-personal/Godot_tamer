# The Meta-Game Review — the stable half, measured

**Written 2026-08-09.** The battle half has had eight rounds of design attention. The stable half
— market, week, training, feeding, cups, breeding, lab, shop — is a straight port of the
TypeScript original and has had none. `docs/OUTSTANDING.md` §3 says the biggest unchecked
assumption in the project is whether this is actually fun, and that **there is not one playtest
record in the repo**. This document is the first one.

**The instrument:** `monster-tamer/scripts/_probe_career_arc.gd` + `scenes/_probe_career_arc.tscn`.

```
cd monster-tamer && "P:/Godot_v4.7.1-stable_win64.exe" --headless --path . res://scenes/_probe_career_arc.tscn
```

Deterministic (seeded, verified in-probe by re-running a short arc twice and diffing), ~9 minutes,
exit 0. Every number in this document is printed by that probe. **Re-run it after any change to
the stable half and diff the arc** — that is what it is for.

**Provenance.** Run twice, ~40 minutes apart, on branch `3doverhal` while three other workstreams
were committing to `career.gd`, `week.gd`, `week_plan.gd`, `tournament_ui.gd`, `breeding_ui.gd`,
`lab_ui.gd` and `training_ui.gd`. Both runs printed **byte-identical** results, so the figures
below describe the tree as of 2026-08-09 and are not an artefact of one snapshot. The full probe
battery (sim, sim-quality, arena-switch, layout, career-loop 149/149, combat-tree, bt, audio) was
green before and after.

---

## 0. The verdict, in one paragraph

**The loop works, it is completable, and it is almost entirely maintenance.** An autopilot playing
best-known strategy wins Tamers Apex in **319 weeks (6.6 in-game years), 88 cups, 264 fights, and
~2,540 discrete decisions** — roughly **4.6 hours of pure interaction at a machine's pace**, so
considerably more for a human. Of those 2,540 decisions, essentially **one is real**: which stat
line to commit a monster to. The other ~2,400 have a constant correct answer that never changes
with knowledge, opponent, league or week. Gold stops being a constraint at week 43 and finishes
at 21,630 against total lifetime sinks of ~8,100. Breeding never fires. No monster ever retires.
The league stat cap — the thing `career.gd` describes as "the ladder doing real work" — never
binds once in 319 weeks. **Nothing in the stable half is currently a strategy layer feeding the
fight; it is a clock the player winds until the battle half will let them past.**

⚠️ **AND THE MOST IMPORTANT NUMBER IS A SENSITIVITY, NOT AN AVERAGE.** Two autopilot policies,
identical in every other respect:

| training policy | points/week | outcome |
|---|---|---|
| "biggest drill on your weakest stat" (one line of logic) | 14.45 | **wins Tamers Apex at week 319** |
| a 30-drill expected-value optimiser | 11.38 | **stalls at Masters forever** |

A 27% difference in training throughput is the difference between finishing the game and never
finishing it — and the *dumber* policy is the winning one. There is no signal anywhere in the
game that tells a player which side of that line they are on. See finding **L1**.

---

## 1. What the instrument does, and what it does not model

Five measurements, each answering one pacing question.

| # | instrument | question |
|---|---|---|
| 1 | **THE ARC** | An autopilot plays a fresh career forward — recruits, plans every week, feeds, enters cups, breeds, upgrades the barn — until it wins or walls. Per league: weeks, gold in/out, cups, rounds won, roster churn, how far stats got against the cap. |
| 2 | **THE GRIND** | Is gold ever scarce? What does a week cost to run, and what does a cup pay? |
| 3 | **THE WALL** | Win rate of a cap-trained team, and of fresh recruits, against each league's own rivals. Does the climb get harder? |
| 4 | **THE GYM** | Weeks of perfect training to fill each league's stat ceiling, against a monster's lifespan. |
| 5 | **THE CHOICE** | Four training policies over the same 200 weeks. Does the weekly decision change the outcome? |

**Faithful to the shipped game:** it drives the real `WeekPlan.advance()` tick, the real
`Career.enter_league_tournament()` (which shares its promotion tail with the live `CupRun` path),
the real `GameData.make_monster`, the real `Roster.make_rival_team`, and the real market offer
generation and pricing.

**Deliberately not modelled — each noted with which way it biases the result:**
- **Fights are `battle_sim.gd`, not the spatial sim.** The arena the player watches is the 3D
  spatial engine; the reference sim is what `career.gd` itself uses for headless cups. Win rates
  may differ in absolute terms; the *shape* (equal-strength teams, sweep-gated promotion) does not.
- **Tactics are never set.** Every fight is fought on default orders. A player who reads the
  scouted rival well should beat 49%.
- **The autopilot releases retired monsters.** The game does not require this (see **R1**) — it
  would let you field a retired champion forever. The arc is therefore *harsher* than the game.
- **No weekly events, no gear, no tonics, no signature rite, no trainer XP.** None of these exist
  in the Godot build (they do in TypeScript — see §4).

**The economy constants it mirrors** (purse, barn prices, recruit price, breeding) all live in
**UI scripts**, so the probe reads them out of those scripts' constant maps rather than copying
them. That the model layer cannot compute a purse is finding **E1**.

---

## 2. THE ARC — the measured career

Seed 20260809, best-known training policy, one cup attempt per month.

```
  league        wks  cups  rounds  won   gold in  gold out    fill@exit
  Wood            1     1       3    3       132       348        44%
  Copper         25     7      21    7       782       498        39%
  Tin            17     6      18    7       834       364        43%
  Bronze         65    16      48   23      4770      2860        67%
  Iron            5     2       6    4       650       176        56%
  Silver         61    16      48   22      6287      4083        67%
  Gold           41    11      33   15      4768      1623        66%
  Platinum        5     2       6    5      1400      3149        52%
  Masters        73    19      57   28     11838      3624        63%
  Tamer Elite     5     2       6    4      1233       261        61%
  Tamers Apex    21     6      18   12      6480      1058        62%

  WON THE GAME at Tamers Apex after 319 weeks (6.6 in-game years)
  cups entered:  88  (264 rounds, 130 won = 49%)
  gold:          ended 21630, peaked 21630 · 2 weeks of 319 with gold under 100
  monster weeks: 757 trained · 448 rested · 17 excursion  (of 1222)
  weeks with NOTHING to train (every stat at the league ceiling): 0
  roster churn:  5 recruited · 0 retired · 0 bred (best potential x1.00)
  DECISION POINTS: 2540  →  ~169 min of menus + 264 fights (~110 min at 25s)
```

**Read the `wks` column.** Iron 5, Platinum 5, Tamer Elite 5 — cleared on the second cup attempt.
Bronze 65, Masters 73, Silver 61 — sixteen to nineteen attempts. The league's *position on the
ladder* explains none of it. What explains it is whether the sweep lottery happened to land while
the team was on a good part of its training curve. **The pacing of this game is currently noise.**

---

## 3. The findings

Ordered by how much they cost the vision, not by how easy they are to fix.

### L1 — Promotion is three coin flips, so the ladder is a lottery with an invisible threshold
**Evidence.** Promotion requires sweeping all three rounds (`career.gd:apply_tournament_outcome`,
`swept = wins == rival_count`). The measured per-round win rate across the whole winning career is
**49%**. A 49% per-round rate gives a **12% sweep chance**, i.e. ~8 cups per promotion — and the
measured figure is 88 cups for 11 leagues. At the 43%/34% rates the weaker policies produced, the
sweep chance falls to 8%/4% and the run never promotes again.

**Why this is the worst finding.** It converts every pacing question into a variance question. A
player cannot tell whether they are stuck because their stable is wrong (a signal to go and train
differently — the vision's whole loop) or because three coins have not landed yet (a signal to
press the button again). CLAUDE.md's own standard for the battle half applies verbatim here: *"an
unreadable fight is not a hard fight, it is a slot machine."* The ladder is currently the slot
machine.

**It is also why the sensitivity in §0 is invisible.** `w³` is brutally steep: 55%→17%, 49%→12%,
43%→8%. A small, unsignalled change in team strength swings the number of cups per promotion by
2–4×, and the player experiences that as randomness.

### L2 — The ladder has no difficulty curve; the numbers grow and cancel
**Evidence — THE WALL.** A team trained exactly to the league ceiling wins **100% (8/8) at every
one of the eleven leagues**. A team of fresh recruits wins **0–13% at every league**. Rival stat
fill is flat at **40–51% of the cap at every league**, Wood to Apex.

Rivals are generated at `fill = league_cap / apex_cap` (`career.gd:make_league_rivals`) and then
`make_monster` scales that against the same cap — so rival strength is a fixed *fraction* of the
ceiling, forever. The ceiling rises; the relative difficulty does not move. Every league is the
same fight with bigger numbers. There are exactly two outcomes at every rung — you are above the
line and win everything, or below it and win nothing — and the game's job is to make you cross
that line eleven times.

### L3 — Nothing on the ladder tells the player where the line is
There is no scouting cost, no strength readout, no "your team is not ready" signal, no record of
why the last cup was lost. `tactics_ui.gd` shows the scouted rival's roster, which is the closest
thing — but nothing relates it to the sweep threshold. Given L1 and L2, the player's actual
information state after losing a cup is *nothing at all*.

### G1 — The league stat cap never binds. The real ceiling is lifespan, and it only bites at the top
**Evidence — THE ARC:** weeks in which a monster had nothing left to train because every stat was
at the league ceiling: **0 of 1,222**. Roster fill at promotion peaked at **67%**.
**Evidence — THE GYM:** weeks of perfect training to fill 95% of each cap, against a career of 336
weeks (a monster starts as a Teen at 48 weeks old and retires at 8 years):

```
  Wood 35 · Copper 70 · Tin 110 · Bronze 159 · Iron 201 · Silver 235 · Gold 305
  Platinum 900  → RETIRES FIRST (336 weeks, not enough)
  Masters, Tamer Elite, Tamers Apex → RETIRE FIRST
```

So: below Gold the cap is reachable but the player promotes long before reaching it; from Platinum
up it is **unreachable within one lifetime**. Either way it never functions as a gate.
`career.gd` claims the cap "makes the ladder change the GAME rather than only scale the numbers."
Measured, it does neither.

⚠️ **This is exactly the class of inherited number CLAUDE.md warns about** — evidence of what
happened, not evidence that anyone decided it.

### G2 — Lifespan never forces turnover, because the game ends first
**Evidence.** The winning run took 319 weeks. A monster's career is 336. **Zero retirements in a
winning career; five recruits, all to grow the team for a larger league, none to replace a death.**
The generational fantasy — the thing breeding, potential, the lab and the freezer all exist to
serve — is never once touched by a player who wins.

### B1 — Breeding is structurally locked out at the top four leagues, and never fires anywhere
**Evidence.** `breeding_ui.gd:487` refuses when `Roster.monsters.size() >= Career.barn_capacity`.
The barn maxes at **5** (`shop_ui.gd:BARN_PRICES` has six entries) and Platinum, Masters, Tamer
Elite and Tamers Apex all field **5**. So from Platinum onward, breeding requires deliberately
fielding an incomplete team or paying freezer rent to park a monster. The autopilot bred **0**
times across a whole winning career; best bloodline potential at the end: **×1.00**.

⚠️ **And `potential` — the only mechanic in the game that can exceed a league cap — raises a
ceiling that G1 shows is never reached.** Breeding's real value is the child's 30% stat head start
(worth ~100 weeks of training), and nothing in the UI says so.

⚠️ **CAVEAT:** `breeding_ui.gd` was being actively reworked by another workstream during this
round (it grew from ~300 to ~570 lines while the probe was running, and briefly broke this probe's
constant reads). Re-run the arc before acting on B1.

### E1 — The economy has no model layer; it lives in UI scripts
The purse formula is in `scripts/ui/tournament_ui.gd` (`BASE_PURSE`, `PURSE_PER_LEAGUE`,
`REWARD_BY_DROP`, and the payout itself in `_show_result`). Barn prices are in `shop_ui.gd`.
Recruit pricing is in `market_ui.gd:_estimate_value`. Breeding rules are in `breeding_ui.gd`.
**Nothing headless can compute what a cup pays** — this probe has to read those scripts' constant
maps and re-implement the arithmetic. That is why `career.gd:enter_league_tournament` can run a
whole tournament without any gold changing hands, and why the QA harness has never been able to
measure the economy at all. Any economy rebalance has to move these first.

### E2 — Gold stops mattering at week 43, and cups cost nothing
**Evidence.** Gold ended at **21,630** and peaked there — it was never spent down. Total permanent
sinks in the entire game: barn upgrades 5,020 + licences 2,800 + 300/child = **~8,100**. Two weeks
out of 319 had gold under 100, both in the opening. A stable of five costs ~39g/week to feed; one
Wood sweep pays for six of those weeks, one Apex sweep for forty-two.

**And the supply side is unbounded.** Measured directly: a Wood-capped monster entered the Wood cup
ten times back to back for **+1,100g while the clock moved 0 weeks**. Nothing on the cup path
touches `Career.week` — no entry fee, no week consumed, no stamina, no injury, no cooldown. Gold
per week of game time is infinite by construction. CLAUDE.md defers the economy rebalance
deliberately; **this is the measurement that pass needs, and its conclusion is that the problem is
structural, not a matter of tuning purse sizes.**

### E3 — There is a reachable dead save, and the original had a backstop this build dropped
With one monster and under ~120 gold (the market's floor price, `market_ui.gd:_estimate_value`
returns `120 + frac*520`), losing that monster to retirement leaves a stable of zero. With zero
monsters there is no cup to enter (every league needs ≥1), no excursion to run, and no income of
any kind. Gold can never increase again. The save is dead.

The TypeScript build had an explicit backstop for exactly this: **"A Stray at the Gate"**
(`src/town.ts:1643`), a weekly event with `weight: 100` whenever the stable is empty or fully
retired, offering a free recruit — commented as *"a soft-lock backstop, not a free bypass"*. The
Godot build ported neither the events system nor the backstop.

### T1 — The ceiling of training skill is a one-liner, and knowledge does not pay
**Evidence — THE CHOICE**, 200 weeks, one monster, Platinum ceiling, fed, happiness 8:

```
  lowest-stat extreme     2889 points (14.45/wk)   ← a one-line policy
  optimiser               2275 points (11.38/wk)   ← 30-drill expected-value search
  random drill            1480 points  (7.40/wk)
  basic drills only       1114 points  (5.57/wk)
```

The best play is *"always put the biggest drill on your weakest stat"*, it never changes, and a
genuinely more sophisticated policy is **21% worse**. Random play reaches half of best play; the
whole skill range of the training layer is a factor of ~2, and the top of it is a constant.

**Further:** the top-scoring drill beats the runner-up by less than 5% in **49% of training
weeks**. Half the time there is not even a nominal best answer.

This is the finding that hits the vision most directly. CLAUDE.md: *"Training and breeding are
STRATEGY, NOT MAINTENANCE. If a training week is an obvious click, it has failed."* Measured, it
is an obvious click, and it is clicked ~1,200 times per career.

### T2 — Stamina is not a currency, because rest refunds a flat amount
`week.gd:apply_activity` restores **30–100 stamina (mean ~65) on a rest week, regardless of how
much was spent**. So a 35-cost drill and a 15-cost drill both cost about one rest week eventually,
and the correct play is always the most expensive drill available. This is *why* T1's one-liner
wins, and it is why the 30-drill table collapses to six entries (the six extremes).

The probe made this mistake itself first — scoring drills per stamina point measured 2,051 points
where the naive policy measured 2,889. **The system's own numbers punish thinking about stamina.**

### D1 — Foraging is strictly dominated by doing nothing
`week.gd:forage_feed` costs **25 stamina and 2 happiness**. Going unfed costs **1 happiness and
nothing else** (`apply_activity`, the hunger branch). Foraging is therefore never correct: it is
worse than the free alternative on both axes. The autopilot never forages, and says so in a
comment. The "free fallback" the design intended is a trap.

### D2 — Feeding is worth ~19%, and is the one input that is priced correctly
Happiness 0 → 9.75 points/week; happiness 10 → 11.63. A ~19% throughput swing for ~8g/week is a
real, legible, cheap-to-understand decision. It is the healthiest single number in this document,
and it is currently buried behind the forage trap and a food market whose price swing (±40%) is
smaller than the cost of getting it wrong.

### R1 — Retired monsters still fight, and the player cannot choose the team
`career.gd:enter_league_tournament` fields `Roster.monsters.slice(0, team_size)`, and
`tactics_ui.gd:43` does the same for the live cup. Neither filters `retired`, and a retired
monster's stats are untouched — so a retired champion fights at full strength forever, and
retirement's only consequence is that it stops training. It is also **the first N of an array**:
there is no team selection UI at all. A player with six monsters cannot pick which five compete.

---

## 4. What the TypeScript original did that this build does not

Read `src/town.ts` before designing the replacement — most of these were solved once already, and
several were solved *because* of a failure this build has now reproduced.

| system | TypeScript | Godot today |
|---|---|---|
| **Promotion** | A purchased **licence** (`LICENSE_COSTS` 0→1,900g) plus an on-demand **rank-up trial**, gated on having trained a monster to `cap − 10` — an explicit, legible *"you are ready"* threshold, with a 3-week cooldown on failure | sweep 3 of 3, unlimited retries, no cost, no signal |
| **Cups** | A seeded annual **calendar** — every league guaranteed ≥1 cup per quarter, Masters/Elite at half density, one marquee prestige event per league; entering consumes the monster's week | unlimited, instant, free |
| **Placement** | Round-robin vs 3–5 rival teams, reward by placement (100/65/40/0%) | binary: swept or not |
| **Weekly events** | ~45% of weeks roll an event with a blocking choice — the peddler (gear tiers, tonics, stud book), the stray backstop, and more | none |
| **Gold sinks** | Gear tiers (200–1,250 × 6 stats), comfort items, pantry/larder contracts, tonics, stud book, manuals, battle analyst, lab expansion, fusion (1,000), licences | barn, licences, breeding, food |
| **Gold sources** | Purses, stud income from podium finishes, cup roster stipend | purses, excursions |
| **Career depth** | Trainer XP and level, signature rite at trainer 6, Hall of Fame, tournament history and podium counts | none |
| **Breeding** | Potential step by tier (wild .10 → primeval .15), head start 0.30, max 2 children/parent, fusion recipes | potential step .06, head start .30, max 2 children — but barn-locked (B1) |
| **Soft-lock** | "A Stray at the Gate", weight 100 on an empty stable | dead save (E3) |

⚠️ **This is not an argument to port it.** CLAUDE.md is explicit that the port is a skeleton and
every system gets reworked. It *is* an argument that the questions in §3 have precedent, and that
the licence/trial structure in particular is a directly better answer to L1 than the sweep rule.

---

## 5. What would most improve it — ranked

Ranked by how much each moves the vision's three fixed points (the ladder is the spine; the ranch
feeds the fight; training and breeding are strategy). Each names the measurement that would prove
it worked, so the next round can use the same instrument.

**1. Replace the sweep gate with a readiness threshold.** Promotion should be something the player
can *see themselves approaching*. The TypeScript answer — train a monster to within 10 of the cap,
then take an on-demand trial — is legible, is a training goal, and turns the stat cap (currently
inert, G1) into the actual gate. Any variant works as long as promotion stops being `w³`.
*Prove it:* cups-per-promotion falls to ~1–2 and stops varying 2–19 between leagues; the arc's
per-league week counts become monotonic.

**2. Make a cup cost a week, and make losing cost something.** One line — the cup path never
touches `Career.week` — closes the infinite-gold exploit (E2), makes the entry decision real, and
makes L1 hurt enough to be worth fixing properly. Add an entry fee scaled to the league and the
purse becomes a wager rather than a faucet.
*Prove it:* gold-at-end drops from 21,630 toward the ~8,100 of lifetime sinks; "weeks broke" rises
above 2.

**3. Give the weekly plan a real decision.** T1/T2 are the vision's own stated failure mode,
measured. The cheapest structural fix is to make **rest refund proportionally to what was spent**
(or make expensive drills carry a lasting cost — injury risk, happiness, a recovery week), so the
30-drill table stops collapsing to six. The richer fix is the one CLAUDE.md already wants:
per-class stat caps and doctrine, so *which* stat to raise is a commitment with a cost.
*Prove it:* the gap between "lowest-stat extreme" and a real optimiser inverts; the near-tie rate
falls well below 49%; distinct drills used rises above 6.

**4. Unlock breeding, and make the ladder need it.** Raise the barn one slot above the largest
team (6), or exempt a nursery slot, so B1's structural lock goes. Then make the top of the ladder
actually require a bloodline: G1 shows Platinum+ caps are unreachable in one lifetime, which is
*already* the hook — a second-generation monster with a 30% head start is the intended answer and
nothing says so.
*Prove it:* a winning arc records >0 breeds and best potential >1.00; roster churn stops being 5
recruits and 0 retirements.

**5. Move the economy out of the UI scripts (E1).** Purse, prices, sinks and sources belong in a
`scripts/economy.gd` the headless harness can call. Without it no economy pass can be measured,
and the deferred rebalance CLAUDE.md keeps promising cannot begin.
*Prove it:* this probe stops mirroring four UI scripts.

**6. Fix the three outright bugs.** Forage is strictly dominated (D1). Retired monsters still
compete (R1). The empty stable is a dead save (E3) — port the stray backstop or give the market a
free/`0g` floor offer.

**7. Add the missing signal.** After a lost cup, say why. After a won one, say what changed. The
player cannot currently distinguish "my stable is wrong" from "the coins landed badly", and until
they can, no amount of depth in items 1–4 will be legible.

⚠️ **Do 1 and 2 before anything else, and re-run the arc between them.** They interact: making a
cup cost a week while promotion is still a 12% lottery would turn a 319-week career into a
1,000-week one. Order matters here more than usual.

---

## 6. Re-running, and what to watch

```
cd monster-tamer && "P:/Godot_v4.7.1-stable_win64.exe" --headless --path . res://scenes/_probe_career_arc.tscn
```

Exit code 0 means the instrument is sound, **not** that the game is good — it reports, it does not
judge. Watch these five numbers:

| number | today | what it means |
|---|---|---|
| weeks to win (or the league it stalls at) | **319, won** | the spine |
| cups per promotion | **8 (range 1–19)** | L1, the lottery |
| gold at end vs lifetime sinks | **21,630 vs ~8,100** | E2, whether gold means anything |
| best policy vs optimiser, points/week | **14.45 vs 11.38** | T1, whether training rewards knowledge |
| breeds, retirements | **0, 0** | G2/B1, whether the dynasty exists |

⚠️ **And the honest limit of all of it:** this measures a machine playing perfectly and silently.
It cannot tell you whether the 110 minutes of watching fights are *enjoyable*, only that there are
264 of them. `docs/OUTSTANDING.md` §3 remains open, and a human playtest is still the missing
record.
