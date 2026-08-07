# Monster Tamer — Version history

Per-version rationale and the load-bearing ⚠️ invariants behind each change,
**newest first** — the top entry is the current build. This is the changelog split
out of `CLAUDE.md`; the timeless architecture / ops reference stays there. Balancing
evidence for every tuning number lives in `docs/BALANCING.md`.

> Many ⚠️ notes below are still-active engineering invariants, not just history —
> read the relevant version before touching the system it describes.

---

## v0.93 — reach is authored, nothing teleports, and the instrument was lying

**v0.93 — the day three separate things turned out to be DERIVED when they should
have been AUTHORED, and the harness that would have caught it was fighting teams
that did not exist.**

### The free attack is authored per class (`tamerengine/types.ts:CLASS_BASIC`)
`basicAttackFor` reconstructed a monster's fighting identity from whichever damage
move it happened to draft. There is no version of that guess that works: keyed by
POWER, a ranged monster got a melee basic it could never reach with; keyed by
REACH, a Warrior that drafted one `Piercing Shot` became a ranged unit and stood
off at 6.4 — a STR-348 kongrath shooting, spotted by eye in a replay.

⚠️ **The same mistake had already been found and fixed once in `reachOf`.** This was
a second copy. A derived property has to be re-derived correctly at every site and
there is no single place to be right — which is the whole argument for authoring.

Four bands: melee 3.0 · ranged 8.0 · magic 7.0 · support 6.0, each carrying channel,
reach AND scaling stat. ⚠️ The stat was a second inference in the same function — read
off the channel, so a Rogue's knife scaled on STR and a Spellsword's blade ignored
INT. ⚠️ DEX is why no formula replaces the table: Rogue is a knife, Ranger is a bow,
and the stat pair cannot tell them apart.

`reachOf` now takes the SHORTER of best weapon and class basic — stand where
everything in your hands works. Before, **31.7%** of monsters parked outside their own
free attack (Rogue 67%, Spellsword 100%); now 0%.

### All 137 moves author a range (`tools/authorranges.ts`)
Seeded per LINE — a line is a shared win condition and its reach is part of that
identity. Assassin 2.4–2.8, Volley 8.4–11.0.

⚠️ **92 moves already carried a `range` and it LOOKED authored. It was not:** 13 distinct
values across 92 moves, partitioning cleanly by channel — two buckets per channel — so
an Assassin stiletto reached 5.6 for no reason but DEX being typed `ranged`. ⚠️ The LINE
owns the reach, never the channel. `validate.ts` now fails any move without one.

Together these give the design the ranges were for: a Warrior keeps a melee basic at
3.0, stands at 2.8, and still fires Piercing Shot at reach 9 from where it stands.

### Nothing teleports (`engine.ts`, `KNOCKBACK_SPEED`)
`applyOnTarget` wrote `target.pos = dest`, so Body Slam's `push: 3` landed all three
units inside one 0.1s tick — 30 units/second, ~7x a walk. Measured on a 3v3: 1532
ticks moved ≤0.5 units and nine moved 1.8–3.1, with NOTHING in between. All nine
matched a `shove` event exactly.

⚠️ **This is why tuning the dash did nothing.** Three commits moved `DASH_SPEED_MULT`
chasing "the retreats look like teleports". Not one jump was a retreat. Measure which
mechanic is FIRING before tuning the one you assume is.

Knockback now travels and costs the target control for the flight, and collides.
⚠️ **Placement is load-bearing:** the gate first went ABOVE the per-unit timers, freezing
cooldowns, mana, regen and status durations — a stealth stun that also paused recovery.
`duel-melee` went 15s → **91.5s**. It belongs after the timers, before the decision.

### The balance harnesses were fighting teams that do not exist
`sweep40.ts` and `ab.ts` each carried their own copy of ten hand-picked species triples
that existed NOWHERE in the game. ⚠️ `src/teamTemplates.ts` was written to close exactly
that gap and its header already claimed to be "THE SWEEP'S COMPOSITIONS" — it was
imported by nothing but its own test. Both now draw from one shared `tools/comps.ts`.

Added per-composition reporting (the sweep's founding claim could not be READ from its
output) and **time to first kill**.

⚠️ **`resolved` is now AT CEILING** — sd 0.00 across five seed batches. It can catch a
regression but not an improvement. Judge on duration (beat ~2.2s) and first kill.

### P6 (focus fire) was aimed at the wrong lever — `tools/focus.ts`
The roadmap's highest-value item rested on "damage spreads evenly across a whole enemy
side". It does not: top share measures **0.711** where an even split would be 0.333.
maxHp **r=+0.79** against time-to-first-kill; top share **r=−0.56**. Healing was the
other suspect and is not it (0–9% of damage dealt).

⚠️ **And the lever recorded as "measured NULL" is not null** — re-run on the fixed harness
the maxHp coefficient gives **p=0.0022**, concentrated on the grinding shapes. The earlier
null was an instrument artifact. Fixing the harness FIRST is what made this visible.

### Five-minute cap, sudden death at 4:15, 8x playback
⚠️ **Raising the timer does not lengthen fights and is not meant to.** At the old 120s cap:
median 15.3s, 0/40 sweep fights reached even sudden death, and 120 → 300 produced a
byte-identical sweep. It bounds the TAIL: at 6v6 one fight in forty ran 166.9s and was
being truncated at the wall. `maxHp` deliberately UNCHANGED at 2.0 — measured, it raises
the median (+18%) but compresses the spread (9.8x → 4.0x), which is the wrong trade when
the goal is variation between builds.

---

## v0.92 — the weekly window + rival teams built to a plan

**v0.92 — the weekly window + rival teams that are BUILT to a plan.**

### Food and training are ONE decision (`App.tsx`)
Training moved out of the Ranch and into the weekly **feed-and-train walkthrough**:
one monster per screen, food picker then `<TrainingPicker>` (extracted from
`RanchView`, also reused nowhere else yet — the extraction is what made the move
cheap). The reason they belong together: drill previews read the selected food
through `previewWeekEffects`, so picking Prime Cut visibly moves Weight Training
from **+6 → +8 STR** on the same screen. That coupling was invisible when the two
lived on different screens.

**The Ranch is now overview + tournaments**: stable strip, detail panel (stats,
abilities, rank-up trial, Rite), a read-only **"This week's plan"** card, and the
calendar at the bottom. The card links back into the walkthrough (`open it now`).

### Sign-ups open a WEEK EARLY (`town.ts`)
`SIGNUP_LEAD_WEEKS = 1`. Entering on the event week would overwrite the plan the
player had just set in the walkthrough, so the roster is now decided *before* that
window opens.

> ⚠️ A week-early entry is a **RESERVATION, not a lock**. Three things had to agree
> or it silently breaks:
> - `signUp` only stamps `activity: 'compete'` when `tournamentAbsWeek === g.week`
> - `stageCup` returns null unless `pendingCupIsThisWeek(g)` — else it fires early
> - `advanceWeek` must **preserve** `pendingTournament` across the reservation week
>   (it used to clear it unconditionally — the entry evaporated before its event)
>
> `pendingCupIsThisWeek(g)` is the single question everything asks. Anything new
> that treats a sign-up as "competing now" must call it, **not** `!!pendingTournament`.

Trial/Rite guards relaxed to match — a cup reserved for next week no longer blocks
this week's arena event.

### Rival teams are built to their gameplan
The plan used to be rolled **after** the team was generated and stamped on top, so
`bulwark` described rosters with no tanks. Now the plan is chosen first and shapes
the roster (`compositionTemplate(size, plan)` — 6v6: rushdown 5/1, focusfire·zone
4/2, attrition 3/3, bulwark 2/4), `equipForPlan` bends loadouts toward it, and each
plan states its `winCon` in the scout panel.

> ⚠️ `equipForPlan` **searches** for a combo the team can actually field rather than
> assuming one. Only bleed/doom/burn/fear have `bonusVsStatus` finishers in the pool
> — **poison and vulnerable have NONE** — so `attrition`/`focusfire` could never
> assemble the combo their winCon promised. It now finds a status the team can both
> set and cash, on two different members. Combos land on 60–74% of teams; they skew
> burn (613/626) because Cinderburst is lv200 and every other payoff is lv780+.

> ⚠️ `compositionTemplate`'s "one of each role" clamp was guarded on `teamSize > 1`,
> so at **1v1** bulwark's 2/4 mix rounded to ZERO damage — a Wood/Copper rival
> holding only Mend + Focus, no damage move at all. A solo monster has no team to
> support: `teamSize === 1` always fields damage. Found only by playing at Wood;
> the 925-team audit swept Tin→Apex, all sizes 2–6.

### Known, not fixed (deliberate)
~6% of Wood/Copper rivals roll every stat under 40 and so learn **nothing** (the
pool's lowest `learnLevel` is 40), leaving an empty loadout — they can still use the
free Attack. Pre-existing; first-league difficulty is a balance number and goes
through the sim, not a unilateral edit.

---

## v0.91 — signature skills + the combat-depth pass

**v0.91 — signature skills + the combat-depth pass.** The largest single feature
since fusion. Full ability design and the balance audit: `docs/SIGNATURE_DESIGN.md`.

### Signature skills — the one move a monster EARNS
Won at **THE SIGNATURE RITE** (`town.ts`), an on-demand event modelled on the
rank-up trial: no calendar slot, fought by the **whole active roster**, allowed
**once a year win or lose**, and gated on **trainer level 6** — not on the
monster, so a first season never sees it. Winning **BANKS** the prize
(`GameState.riteReward`); the player then chooses which monster steps forward
AND which of its body's moves it takes (`claimSignature`). The chosen monster's
current value in that move's stat becomes the **awaken bar**.

**50 authored moves in 8 lists** (`signatureMoves.ts`): six base bodies get 6
each, **Draconic and Abyssal SHARE a list of 8**, Mythical gets 6. Fusion bodies
author none — they resolve to their recipe's parent lists, so every fusion picks
from 12 and **Primeval from 14**.

> ⚠️ Sharing the prestige list is **load-bearing**. Primeval has TWO recipes
> (Mythical+Draconic, Mythical+Abyssal), so its body type alone never revealed
> which pair produced a monster. One shared list makes its pool identical either
> way — which is why nothing has to record fused parentage.

**Inherited DORMANT**: a bred child is born knowing the move at 60% power with
effects AND status stripped, and awakens it by training that stat to the
ancestor's peak. If both parents hold one, the child takes the copy **closest to
its origin** (lowest `inherited` depth).

**Costs a normal loadout slot** — `careerMonster` appends it to the learned pool,
so the ability selector, auto-pick and the battle engine need no knowledge of
signatures at all. That is what kept the feature small.

### Five new engine mechanics (all gated, all golden-safe by construction)
| Effect | What it does |
|---|---|
| `randomTargets` | multi-hit where each strike picks a random living enemy — **ignores the front-row wall** |
| `frontRow` / `backRow` | row-wide targets; each falls back to the other row when its own is empty |
| `spreadStatus` | contagion — a status jumps to N other enemies; omit `kind` to spread whatever they carry |
| `consumeWard` / `consumeThorns` | spend a defensive buff to power the blow (⚠️ only ON A LANDED CAST) |
| `hpScale` | damage lerps on the CASTER's remaining HP — the smooth version of Frenzy/Statue Stance |
| `displace` | drag a target to the front or shove it to the back |

**AoE FALLOFF** — `−5%` per *additional* target (100/95/90/85/80/75%), floored at
40%. Multi-target damage used to scale linearly, so World Ender was worth 56 at
1v1 and **336 at 6v6**. Charged per additional target so a lone survivor takes an
undiminished hit — and so single-target AoE casts don't move.

**FORMATION IS LIVE.** Rows were stamped at setup, so a team that lost its front
line kept a permanently unreachable back line. A monster's row is now its index
among **still-living** teammates via `Combatant.formationRank`. Front line is 2,
**3 at 6v6**.

> ⚠️ `formationRank` is deliberately separate from `slot` (identity — events and
> finals key off it) and from `ctx.all` order (the **initiative tie-break**).
> Reordering `ctx.all` to move someone up the line would silently change turn
> order.

**Melee reach rule**: single-target melee is walled to the front line; melee AoE
and melee scatter ignore rows entirely. That exemption is what makes them the
answer to a turtled back line.

### Balance discipline that emerged (read before touching numbers)
- **A signature may exceed a pool ceiling on ONE axis by ~15–20%**, and must sit
  at or under on every other. 37 numbers were cut in audit for breaching two or
  three at once.
- **Contagion is paid for** — a lower spread chance, or cooldown. ⚠️ **Ember was
  REJECTED** as a contagion carrier: it is the most-equipped move in the game
  (8/14 goldens) and adding a spread moved three goldens including two winner
  flips. Contagion belongs on moves a player CHOOSES, not the default.
- **On cheap, frequently-equipped moves, tune the new effect down rather than
  taxing the old one.** Paying for Piercing Shot's spread with cooldown 2→3
  flipped a golden by itself.
- ⚠️ **Non-consuming payoffs only work when cooldown ≤ status duration.** Fear
  lasts 2 rounds, so a cd5 non-consuming fear payoff is INERT — it would ship
  doing nothing. Only Cinderburst (cd3, 3-round burn) qualifies today.
- ⚠️ **UNITS ARE NOT UNIFORM.** `atkBuff`/`pierce`/`execute` are FRACTIONS;
  `dodgeBuff`/`accBuff`/`accDebuff`/`defBuff` are percentage POINTS. `accBuff:
  0.15` compiles, runs and does nothing. `validate.ts` now guards both directions.

### Sim findings
The rite was **UNWINNABLE** at first: 0 wins from 13 attempts over 45 simulated
years. Cause was a rule that was never specified — the challenger side matched the
roster one-for-one, so a deep stable was *strictly worse*. Capping the challenger
at the league's team size fixed it: **7 won of 47, 11 signatures, 4 inherited**.
`RITE_EXTRA_MULT` sim-tuned 0.15 → 0.05.

⚠️ `Static Chain` (reshape to a chaining debuff) and `Cinderburst` (non-consuming)
are **parked pending a sim** — both are good design but sit in 3/14 and 9/14
golden loadouts respectively.

---

## v0.90 — training-tier rebalance + toolchain fix

**v0.90 — the training-tier rebalance + the toolchain fix.** Shipped on top of the v0.89
endgame arc (documented immediately below, still current). Validated against `sim/bot.ts`;
evidence in `docs/BALANCING.md`.

**Four training tiers**, with `diverse` new:

| Tier | Shape | Net | Stamina | net/stam |
|---|---|---|---|---|
| basic | +6 | 6 | **15** (was 10) | 0.40 |
| intensive | +12 / −4 | 8 | 25 | 0.32 |
| **diverse** (NEW) | **+8 / +8** | **16** | **35** | 0.46 |
| extreme | **+24 / −4 / −4** (was +20/−6/−6) | **16** | 35 | 0.46 |

**Diverse and extreme are deliberate MIRRORS** — same net, same cost, opposite shape.
Extreme spikes one stat and pays out of two others; diverse splits the total across a pair
and pays nothing. Neither is stronger; you pick a shape. **Basic is now the LEAST efficient
tier** (0.40 < 0.46), so the safe option is no longer the quietly optimal one and the
manuals buy real throughput. New **📗 Diverse Training Manual, 800g** (`diverseUnlocked`),
priced level with the **📕 Extreme Manual, repriced 1200 → 800g** — siblings, not a ladder.

The six diverse drills: Pilgrim's Burden STR+WIS · The Cannon Crew STR+INT · Trapeze Hours
DEX+CON · Blindfold Forms DEX+WIS · Taking the Fall CON+CHA · Illusionist's Patter INT+CHA.

> ⚠️ **These six are exactly the complement of the 9 `CLASSES` stat-pairs.** That single
> choice gives BOTH properties at once: all off-archetype (0/6 class pairs) AND perfectly
> even coverage (every stat ×2). **Moving any one pair breaks one or both** — rediscovered
> the hard way over ~5 edits. The `src/drills.ts` header records it.

**Food:** Vigor Melon 200 → **90g**, Bliss Berry 250 → **90g**. Both now sit just above the
75g training foods, so a feeding week is a real three-way call: train harder (+30% pair,
−15 stam), recover (+30 stam), or lift mood (+3 happiness, persists). Golden Truffle stays
500g — a cup-day gamble, not weekly upkeep.

**Any drill/manual number shown in the UI must interpolate its constant.** The Extreme
Manual shop copy hardcoded the old `+20/−6` and went stale through the retune; it now reads
`EXTREME_GAIN`/`EXTREME_COST`. Static checks can't catch this class of bug — only a browser
pass did.

**Toolchain:** vite 5 → 8 (see the ✅ note below) — the Cloudflare auto-build works now.

---

## v0.89 — the endgame arc

**v0.89 — the endgame arc.** Everything below was validated against the rebuilt
full-economy sim bot (`sim/bot.ts`), and the evidence lives in `docs/BALANCING.md`.

**TAMERS APEX — an 11th league (cap 1400)** sits above Tamer Elite, and the top of the
curve steepens to meet it: Gold 700→**750**, Platinum 800→**900**, Masters 900→**1000**,
Tamer Elite 1000→**1200**. Apex is wired through every league-keyed table (pool rewards,
an 8-name cup pool, the annual marquee *The Dynasty Eternal*, 6v6, 5 rival teams,
half-density calendar, 1900g license, excursion ceiling, `validate.ts` probes) and has its
own painted backdrop. Because every gen-1 monster is walled at 700–1100, **an Apex-grade
roster can only come from a bred dynasty** — that is the whole point of the league.

**PRIMEVAL — the prestige fusion** (`Mythical + Draconic/Abyssal`, two recipes → one
class of five: Aeonrex, Stellavore, Chronoshell, Originmage, Worldsong). Roster **65
species**, all with real sprite art. **1.25× potential** and a **1100 gen-1 cap** — the
only gen-1 monster above the Tamer Elite league cap. Element affinity inherits Mythical's
air/earth (all 12 distinct pairs were taken — the one sanctioned `validate.ts` exception).

**The gen-1 cap ladder.** The Market Coach is now a *universal* quality upgrade, lifting
wild AND prestige walls by tier (`statCapFor` reads the coach tier off the synced `wildCap`):

|              | no coach | coach T1 | coach T2 |
|--------------|----------|----------|----------|
| wild/market  | 700      | 800      | 900      |
| Draconic/Abyssal | 800  | 900      | 950      |
| Mythical     | 900      | 950      | 1000     |
| fusion       | 1000 flat | | |
| **Primeval** | **1100 flat** | | |

**The breeding ladder.** The per-generation potential step keys off the line's BEST parent
(`BREED_STEP_BY_TIER`) — wild .10, prestige .11, Mythical .12, fusion .13, **Primeval .15**
— and `breedPotentialV2` bases off `max(parents)` rather than their average, so one
exceptional founder isn't diluted by a modest partner. Ratio the user specified: a wild
line needs FOUR breeding generations to reach ~1.40 potential; a Primeval needs ONE.
(Absolute caps scale with league cap, so the numbers rise at the top — the ORDER is the
invariant.) `BREED_HEAD_START` is 0.30.

**Prestige scarcity.** Licensed prestige stock is a *rare find*, not regular stock:
`PRESTIGE_MARKET_CHANCE` 0.12 lets only 12% of would-be prestige rolls through (measured
33% → 5.3% of offers), survivors carry a 1.5× premium, and the Market Scout —
which deliberately BYPASSES rarity, making it the hunting tool — was trimmed to 12/20%.
Licenses repriced 200/600 → **500/1200**.

**Difficulty.** `RIVAL_BUDGET_STEP` .02→**.03**, `RIVAL_BAND_MIN` .60→**.65**, mid license
costs +10–15%, and `trialChampionMult` is now per-rung: **1.30** Bronze→Gold (mid-game
friction), **1.15** at Tamer Elite/Apex (summit relief — a flat 1.25 compounded with the
climbing budget mult into a literal wall; the sim never once won the TE trial before this).

**⚠️ Rivals do NOT follow the gen-1 cap ladder.** Their strength is
`league cap × rivalBudgetMult(i)` as a TOTAL-stat budget per monster (no per-stat cap at
all) — so raising a league cap raises its whole field automatically. Worth remembering
before touching `LEAGUES`.

**Other v0.89 fixes.** Resume-mid-cup no longer replays fought matches (`resumeOutcomes`
rebuilds the win/loss strip from the committed `MatchOrders` — results are deterministic —
and `doneThrough` is now actually maintained); the Lab shows a **fusion nudge** when you
hold a fusable pair (the sim only started fusing once it earmarked the cost, so a player
needs telling); `BREED_HEAD_START` carries 30% of parents' stats.

**✅ The Cloudflare auto-build is FIXED (vite 5 → 8).** The tree used to carry two esbuilds
— vite@5 pinned 0.21.5 while vitest@4's nested vite wanted ^0.27||^0.28 — and the
deeply-nested duplicate's platform-gated optional deps tripped Cloudflare's pinned
`npm@10.9.2` with `EBADPLATFORM — @esbuild/aix-ppc64`. Upgrading vite realigns it with what
vitest already pulls in: **one hoisted `esbuild@0.28.1`**, wrangler deduped onto it, no
nested copy. `vite.config.ts` needed no changes. Also pins Node (`.node-version` 22.12.0 +
`engines`), since vite 8 needs `^20.19.0 || >=22.12.0` and nothing declared a version.
Green on Cloudflare — see the deploy section. Historical note: the first attempt was a
package.json `overrides` forcing esbuild 0.28.1 under vite@5; that deduped the tree and then
broke vite@5's own `esbuild-transpile` with 124 transform errors. **Upgrade vite, don't pin
esbuild beneath it.**

---

## v0.851 — prestige overhaul + life-stage / career-span tuning

**v0.851 — prestige overhaul + life-stage / career-span tuning.** A multi-step pass
(v0.84 → v0.851) on top of the v0.81 tactics architecture. All of it is **golden-safe
except the one deliberate recapture noted below** — training aptitude, stat caps, life
stages, and aging never touch `simulateTeamBattle`'s RNG.

**Prestige groups reworked (v0.85, `species.ts`/`game.ts`/`core.ts`)** so the
license + rank gate buys a real, distinct creature instead of a worse-than-fusion body:
- **Authored training aptitudes** for all 15 exclusive species — each now has a
  hand-picked `trainingProfile` (major + flaw) *plus a shared group body-minor* added to
  `BODY_MINOR`: **Draconic WIS**, **Abyssal INT**, **Mythical CHA**. No more legacy
  stat-derived fallback (that path in `trainingProfileFor` now only catches future species
  that forget to author one).
- **Gentle / no flaws:** Draconic & Abyssal flaws softened from −20% to a token **−5%**
  (`PRESTIGE_FLAW_PENALTY` in `statTrainingBonus`; no amplified intensive-drill malus
  either). **Mythical carry no flaw at all** (authored major-only). `AptMarks` renders a
  hollow ▽ for the soft flaw and suppresses a minor mark that duplicates the major.
- **Long lifespans:** base `lifespan` values raised so effective **career spans are
  9–12y** (via the existing +2 `pedigreeSpanBonus`), the longest of any monster.
- **Ceiling lifted:** prestige gen-1 stat cap **800 → 1000** (`PRESTIGE_GEN1_CAP`, fusion
  parity) in `statCapFor` — they now reach the full league cap at Masters/Tamer Elite
  instead of walling at 800. Still bound *by* the league cap, so they can't out-scale a
  league's rival field. (The gen1cap tip + "raise the ceiling" help text exclude prestige.)
- **Draconic base-stat parity (v0.851):** Draconic averaged only ~123 total (vs ~133–142
  for every other body — the roster's weakest). Bumped the five to ~132–134 each,
  preserving class/flaw/identity. Abyssal (~132) was already at parity and left alone.
  **This moved two golden battles** (`gold-b1` rolls Pyraxon, `gold-b3` rolls Stormlerath —
  prestige bodies ARE generated by `generateMonster`, unlike fusion bodies) — `1v1-low`
  and `2v2-mid` recaptured deliberately in `battle.test.ts` (2v2-mid flipped B→A). 12/12.

**Life stages (v0.851, `game.ts:stageInfo`):** training multipliers bumped —
**Teen 1.0× → 1.35×**, **Fully Grown 0.95× → 1.15×** (Baby 0.5×, Elder 0.8×, Retiree 0×
unchanged). This is a broad power increase across every monster's whole career and has
**not yet had a long-haul sim pass** — flagged as the next balance task.

**Career span now computed in WEEKS (v0.851):** `stageInfo` derives Elder/Retiree
boundaries from `spanWeeks = round(careerSpanYears × 48)` instead of an integer-year
compare. The old compare rounded any fractional span up to a whole extra year, so one
Comfort item and three gave the *same* retirement. Now each **+8-week** comfort/tonic
purchase (`COMFORT_WEEKS_PER_ITEM`/`TONIC_WEEKS`) delays aging by exactly its weeks, and
the added weeks all land in the **Fully Grown** adult phase (Elder is a fixed final-year
window that just slides later). Baby/Teen stay pinned to whole years.

**v0.84 — post-fight Match Analysis + Battle Analyst + economy tweaks.**
- **📋 Match analysis** card on the between-match bracket hub AND the results screen
  (`MatchAnalysis` in `App.tsx`, over `battleReport.analyzeBattle`): turning point,
  tactic ✓/✗, key moments — free. Hiring the **🔎 Battle Analyst** (500g, Ranch Shop,
  `battleAnalyst`/`buyBattleAnalyst`) adds the opponent's gameplan counter-read + 1–3
  concrete tips (`battleReport.battleAdvice`).
- **Live round-robin standings** grid on the bracket hub (rebuilt deterministically,
  revealed through the player's last match). Tournament **calendar is always-on** (the
  toggle was removed).
- Economy: **≥2 cups/month** guaranteed (`tournamentCalendarFor` filler + a `validate.ts`
  assertion), **rank-up trial pays 50% of a league cup** (`finalizeTrial` goldReward),
  **cup entry fee removed** (free to enter), and the **Rival Challenge event shows a rough
  win-chance** (`challengeWinChance`).

---

## v0.81 — per-fight tactics + deferred tournament resolution

**v0.81 — per-fight tactics + deferred, interactive tournament resolution.**
Tactics are no longer a monster's standing trait — they're chosen **fresh before each
battle the player fights**, exactly like abilities are chosen before a tournament. The
standing-orders `<details>` panel is **gone from the Stables** (`TacticsControls` was
extracted and now lives only on the new pre-fight screen and the Sandbox lab editor).

The enabling change is architectural: the whole tournament used to be simulated **up
front** inside `advanceWeek` (`resolveTournament`/`resolveTrial`), and the battle screen
merely **replayed** a finished `lastBattle`. Now `advanceWeek` only **stages** the event
(`stageCup`/`stageTrial` → `GameState.activeCup`, a serializable in-flight event carrying
the fielded ids + the generated rival teams). The `'battle'` phase fights it **match by
match**: `preamble → bracket (scout) → tactics → fight (simulated live) → … → finalize`.
Each player match is simulated at the moment its `MatchOrders` are committed, so tactics
genuinely decide the outcome. `finalizeCup`/`finalizeTrial` (called from the UI when the
last match ends) score standings, rewards, injury, exp, trainer XP, the seated-rival
head-to-head, and license unlock — the tail of the old resolvers, moved out of the tick.

**Expanded tactic set (same v0.81 cycle):** three new coach-level orders on
`TacticsControls`, all opt-in and golden-safe (default off): **opening sequence**
(`Tactics.openerIds` — up to 2 scripted first plays, replacing the single
`openerId`; the engine tracks an `openerQueue`), **survival** (`Tactics.preserve`
— below 40%/25% HP the monster guards incoming hits and drops self-harm/recoil
moves), and **control-first** (`Tactics.ccPriority` — leads with a hard CC status
(stun/sleep/silence/…) before committing to damage; gated on having a control
move equipped). Each verified to change the battle log in a differential sim.

**Why goldens don't move:** `simulateTeamBattle` seeds its RNG purely from monster seeds
(`battle.ts`), so a matchup is a pure function of (monsters + their tactics) — the engine
is untouched, and a scratch sim confirmed two different `MatchOrders` for the same matchup
produce different battle logs (tactics bite). 12/12 tests still green. `MatchOrders`
(per-member `Tactics` + formation row order + protect + mark) and `ActiveCup` live in
`core.ts`; the old `setTactics`/`setProtectTarget`/`setMarkTarget` and the sign-up
protect/mark pickers are removed (those orders are now picked per fight). Applies to **all
player fights** — team cups, 1v1 cups, and rank-up trials. A staged event is persisted, so
a reload mid-cup resumes (migration routes `activeCup` saves to the ranch). Browser-verified
end-to-end: an Iron 3v3 cup fought match-by-match, finished 1st/4, +494g, `activeCup`
cleared.

---

## v0.80 — per-move battle animations + Bastion rename

**v0.80 — per-move battle animations (hybrid) + Bastion rename.** The 1v1 arena
(`arena.tsx`, shown in Sandbox + Wood/Copper) now animates each ability distinctly.
The design is a **hybrid**: shared base motions for moves that legitimately look alike
(every fireball, every arrow) + **bespoke motions** hand-assigned to ~28 distinctive
moves via `BESPOKE_KIND` (keyed by move NAME — the acting Move is recovered from the
caster's loadout by name, since names are unique within a loadout): `slam` (heavy
crash — Titanfall/Colossus Crash/World Ender/…), `guillotine` (Executioner/Showstopper),
`flurry` (rapid multi-slash), `beam` (pierce line — Snipe/Deadeye/Void Lance/…), `volley`
(Rain of Arrows/Needle Storm), `chain` (Static Chain), `cage` (Glacial Prison/Deep
Freeze), `firewall` (Inferno), `notes` (song buffs). On TOP of the base, a **composite
overlay layer** (`fxForMove`/`utilityFx`) adds a per-effect tell driven off the Move's
fields — `exec` flash, lifesteal `tether`, `manaburn`, `crater`, `shield`/`thorns`/`heal`/
`cleanse`, buff `aura-*` — plus a themed **status puff** (the STATUS_ICON emoji) over the
afflicted monster on every `status` event. All presentation-only: goldens unmoved. The
team-battle (>1) compact tile presentation is unchanged. Every new class verified bound to
a real keyframe. `respects prefers-reduced-motion`.
Also: the self-ward CON move **`Bulwark` → `Bastion`** (distinct from `Bulwark's Challenge`
the mass-taunt, and the `bulwark` rival GAMEPLAN which is unrelated and stays). Move ids
are positional (`CON-6`), not name-derived, so loadouts/goldens were unaffected.

---

## v0.79 — painted area backdrops

**v0.79 — painted area backdrops.** Eight new full-bleed scene paintings, one per
screen: **Town** (village square at dusk), **Market** (beast bazaar), **Ranch Shop**
(tack-and-tonics store interior), **Stables** (training yard), **Breeding Ranch**
(paddocks + hatchery), **Hall of Fame** (marble gallery of champion statues), **Lab**
(cryo-stasis chamber), **Title** (tamer + dragon overlooking the valley). Same
painterly matte-painting look, 1400×788 JPEG, as the 10 league arena backdrops —
`src/areaArt.ts` mirrors `leagueArt.ts`. Distinct palettes double as navigation: the
Lab's icy cyan vs the Breeding Ranch's pastoral green tells you instantly which
preservation screen you're on.
**Legibility:** these sit behind dense admin UI, so `.areabg` is a `position: fixed`
layer under a **theme-aware scrim** (night `rgba(18,20,28,.80→.95)`, day
`rgba(243,245,250,.82→.95)`); cards stay fully opaque — and it MUST be `z-index: -1`
(at 0 a positioned element paints above all static content; the scrim buried every
button on the live site, see the deploy section's verification note). Each view mounts
its own backdrop (fixed positioning means no state lifting); the arena stands down
during battles since it paints its own league backdrop. Art total 3.4MB.

**Post-v0.79 fix passes (same day, shipped as fix commits):**
- **Desktop UX audit** — `.hubbtn`/`.ev-choice`/`.forage-option` set their own panel
  background but inherited `--btn-ink` (text-on-accent) → near-invisible labels; all set
  `color: var(--ink)` explicitly now. Any new button style that overrides `background`
  MUST also set `color`. Day-theme `--btn-ink` is near-black (white on `#0fb488` was
  2.7:1, AA fail). Feeding queue now iterates ACTIVE monsters only (Hall of Fame
  retirees were adding a weekly feeding click + food bill each, forever). Range sliders
  styled with a 24px hit area.
- **Mobile audit (375px)** — `.arena` stacks to one column ≤720px (the two sandbox team
  cards forced 631px page width); theme toggle is icon-only ≤560px (`.tt-label` hidden)
  with `h1` padding to clear it; `.stablescreen` bottom padding 88px so the fixed rail
  can't cover the last row (tactics "Conserve" was unclickable).
- **Tutorial rewrite** — welcome banner now teaches the real loop (weekly tick, cups +
  rank-up licenses, freeze-before-retirement, gen-1 ceiling); five new one-shot
  `TipBanner`s (ids: `market`, `lab`, `breeding`, `hof`, plus conditional `freezewindow`
  — fires at first Elder with freezer room — and `gen1cap` — fires when a gen-1 monster
  nears its `wildCap`, tested against the wall itself, NOT `wall < leagueCap`, which is
  false at Platinum where they're equal). Tips gate on `tutorialEnabled` + `tipsSeen`.

---

## v0.78 — Lab freezer as the sole preservation mechanism

**v0.78 — the Lab freezer is the single preservation mechanism.** The stud farm is
**gone**. `breed()` and `fuse()` both draw from `labFrozen`, and `freezeToLab()` now
**refuses retired monsters** — you must commit a monster to the freezer *before* its career
ends. Let it age out and it retires to the Hall of Fame (honours only) and the line is
closed. That is the core dynasty decision now: **freeze early** (bank the genome at peak,
sacrifice the remaining competing years, occupy a limited Lab slot) **vs compete to the end**
(full career, cups, trainer XP — but no bloodline). Stud Book moved onto lab-frozen monsters;
`Career` gained `breedCount`/`studBook`. Old saves migrate their banked studs into the
freezer with `labSlots` widened to fit, so no bloodline is lost.
**Lab repriced** from luxury to core infrastructure: `LAB_SLOTS_BASE` 2→**3**, expansions
400/800/1600→**250/500/900**, upkeep 5→**3g/wk** (lab-tech loan 3→2). The Lab UI now also
lists the fusion pairs, which were previously invisible.
**Result (25y × 3 seeds):** good player TE/Platinum/Gold, **6 breeds**, and **generation 3 on
two of three seeds** — the deepest dynasties any sim has produced (previously always gen 2).
More variable than the old retire→stud path; see `docs/BALANCING.md`.

---

## v0.77 — economy correction + market systems + gen-1 caps

**v0.77 — economy correction + market systems + gen-1 caps.** The retiree **pension is
gone** (it was 45% of all income, perpetual and cumulative); the Retirement Ranch is now the
**🏛 Hall of Fame** — honours only, **unlimited room**, and retirees no longer occupy barn
slots. **Trainer stipend capped** at 1g/level, flat from LV15 (15g/wk). Cup gold +8%.
Result: cups went from 7% → ~81% of a good player's income; an average player's end gold
fell from ~180k to ~3–15k. **Gen-1 training ceilings**: wild/market **800** (→900/1000 via
the two Market Coach tiers), **fusion gen-1 1000**, bred gen-2+ `leagueCap × potential`.
**Monster-market upgrades**: Market Slots (50/100/150 → 3 to 6 offers), **Market Scout**
(350g, 15%/slot; +500g → 25% and a 2nd species pick), **Market Coach** (Gold: 300g Tin-band
stock +100g each; Platinum: 750g Iron-band +250g each). Prestige licences now **actually
enforce rank** (Special 200g @ Iron, Elite 600g @ Platinum — previously the requirement was
copy only); the stray event can no longer roll a prestige body. Rival budget escalates
gently by league (`1.8 + i×0.02`). Day/night theme toggle on every screen. See
`docs/BALANCING.md` for the full evidence.

---

## v0.7 — fusion system + 15 fusion species

**v0.7 — Fusion system + 15 fusion species (2026-07-23):** the 🧪 Lab is now a real
**stasis freezer** (`labFrozen`/`labSlots`, expandable from the Ranch Shop), SEPARATE
from the Breeding Ranch stud farm (the old `labCapacity` was renamed `studSlots`).
Freeze any active monster to pause its aging (e.g. until you can afford an Elder Tonic,
which now works on frozen monsters); **fuse** two lab-frozen monsters of a valid
BODY-TYPE pair into a brand-new **fusion species**. Fusion: 1000g, both consumed, all
stats start at **100**; aptitude is INHERITED per-monster (+20% on each parent's
training major) plus a rolled +10% minor / −10% flaw; the species (which of the class's
5) is a **spinning wheel**; potential **×1.075 (1½★)**, gen-1 **Platinum-capped** then
fully breedable (gen-2 ≈3★ → Tamer Elite). **15 new fusion species across 3 classes**
(`docs/FUSION_DESIGN.md`): **Saurian** (Mammal+Reptilian, earth/air), **Tempestine**
(Avian+Aquatic, air/fire), **Broodkin** (Marsupial+Insectoid, water/earth) — each 5
species, aptitude-neutral shells (`trainingProfile {}`), 30 unique innates, real
generated sprite art (via Codex image-gen, `image-gen-codex` skill). Fusion bodies are
excluded from wild/market generation (`generateMonster`), keeping goldens byte-exact.
**Roster: 60 species.**

---

## v0.62 — economy pass + Town hub

**v0.62 — economy pass + Town hub (2026-07-23):** the big economy rebalance plus a
Town navigation restructure. Economy (see `docs/ECONOMY_FINDINGS.md` for the sim
evidence that drove it): cup roster **stipend** (+20g/extra member), league team-size
redistribution (Iron 4v4→3v3, Gold 5v5→4v4 — perfect pairs), retiree **pension**
(2 +1/podium +2/champ, cap 10g/wk), freeze = **retirees only** + limited lab slots
(2, expand 400/800/1600) + upkeep 8→5(→3 via lab-tech loan event), **comfort set**
(stable-wide +2mo career span each: 300/500/1000), **Mysterious Peddler** event (the
only source of training gear — 6 stat lines ×5 tiers 200/500/750/1000/1250 with a
reveal chain; Elder Tonic 500g; Stud Book 750g uncapped stud income), **extreme
drills** (+20/−6/−6, 1500g manual), **breeding** (two frozen legacies → child, parents
preserved ≤2 each, potential avg+10%+champ bonus cap 1.5, 35% head start, heritage
stat, Gen ★), **stray-monster** soft-lock backstop, "career span" rename. Town is now
a **hub of location buttons** (🛒 Market · 🏟 Stables · 🐎 Breeding Ranch · 🏡 Retirement
Ranch · 🧪 Lab), each a focused sub-screen; new games still open in the Market. The
🧪 Lab is a placeholder for the upcoming **fusion** system (`docs/FUSION_DESIGN.md`:
15 new fusion species across 3 classes — NOT yet built).

---

## v0.5 — per-player licensing + trial battles + combat balance pass

Everything is **committed on `main`/`preview` and deployed live**. `tsc`/`npm run build`/`npm test`
(12/12) clean; `validateDesign()` reports `45 species, 11 classes, 90 moves, ~48 tournaments/yr —
all consistent ✓`. Full per-item history is in git; the design arc behind the recent work is in
`docs/LOOP_DESIGN.md`.

**Systems in place:** 45 species with real sprite art + 10 league arena backgrounds; emergent
classes (class = current top-two stats, never species-locked); 90-move pool with round-based
buffs/debuffs + a status framework; round-robin **team tournaments** (1v1→6v6, `simulateTeamBattle`
is a real N-vs-N engine); a **tactics** system (temperament, target priority, formation/row order,
kill-order marks, protect, scripted opener, combo discipline, mana policy — team orders locked
until the first team league); title screen + 3-slot saves; **food system** (rations + training +
premium tiers, satiety, forage fallback when <10g, two-stage discount contracts); the five
`docs/LOOP_DESIGN.md` phases: **events**, **rivals** (named, rubber-banded, challenge skirmishes),
**rival gameplans + scouting reveal**, **causal battle report**, and **meta-progression** (trainer
level + bloodline breeding where `potential` lifts the stat cap and climbs each generation).

**v0.5 also ships the sim-driven COMBAT BALANCE PASS (2026-07-22, ~2,500 battles measured):**
sudden-death chip is now **%-of-max-HP** (8% +5%/rd from rd 35 — flat chip let raw HP auto-win
the clock, double-dipping CON; the 3v3 golden went draw→decisive); **turn order = highest DEX
first** (replaces CON-ascending; symmetric tiebreak killed the old side-A bias that flipped ~1
in 5 mirror matchups); **WIS is the caster foundation** (+WIS×0.6 to magic/voice damage — was a
dead stat at 0% win); `maxHp = 40 + CON×2.0` (was 50+2.5), CON melee mitigation 0.05→0.04;
**`RIVAL_BUDGET_MULT` 3.5→1.8** (was: every rival had 3-4 stats near cap, unreachable in a
lifespan — a just-ranked player placed LAST 100% at Iron+; now a dedicated player is competitive
at every league). Results: draws 10→4%, Tank 71→52%, Wizard 49→62%, Bard/Orator strong in teams
(a support 3rd now beats a 3rd Warrior in 3v3), all four battle goldens deliberately recaptured.

**v0.5 — per-player licensing + trial battles + compete-as-action (2026-07-22):**
- **The license belongs to the TRAINER** (`GameState.licenseIndex`), not the monster — recruits/
  thaws/babies join at the player's tier; every stable `Career.licenseIndex` is kept SYNCED to it
  (the one invariant, enforced at every career-creation funnel + `buyLicense` + migration), so the
  many per-career consumers (stat caps, fees, exp clamps) work unchanged. The guest-leader rule is
  obsolete and removed from sign-up.
- **Rank-up = win an on-demand TRIAL BATTLE, then BUY the license.** `startTrial` (Ranch panel)
  sets a champion fight vs a hard same-league team (`TRIAL_CHAMPION_MULT` 1.25× of cap ×
  `RIVAL_BUDGET_MULT` — sim-tuned: a just-ready single-stat monster wins ~38%, a capped one ~63%);
  resolves in `advanceWeek` (mutually exclusive with a cup — one arena event per week); win →
  license unlocks in the Ranch Shop (`licenseEarned`), lose → 3-week cooldown; standard injury
  either way. `LICENSE_COSTS` = 0/50/120/220/350/520/750/1000/1300/1650 (~i^1.5, validator-checked
  monotonic + never-doubling). Trials are DE-CALENDARIZED (RANK_UP_MONTHS/isRankUpWeek/
  promoteMonster/rankUp all gone; calendar week-4 reservation removed).
- **Competing IS the weekly action**: cup/trial monsters get `{kind:'compete'}` forced in
  advanceWeek (no training/rest that week), plans lock to 'compete' at signUp/startTrial and free
  on cancel; training row shows a lock banner.
- **Punch-down steepened**: 2+ leagues below now pays 10% (was 20%).
- **Named rival seated in cups**: `seatedRivalTeamIndex` — ~1/3 of at-league cups, GUARANTEED at
  marquee events; the seated team runs the rival's personality gameplan
  (`RIVAL_PERSONALITY_GAMEPLAN`), the scout panel shows "🥊 {name}'s Team · record", and the
  player-vs-rival cup result moves the head-to-head.
- Sign-up gained an **underpowered-team warning** (below the league band) and a competing-week
  notice. Browser-verified E2E: trial → victory → shop unlock → buy (−50g) → account at Copper →
  Tin gate at 120g. Old saves migrate (player license = max of old per-career licenses).
