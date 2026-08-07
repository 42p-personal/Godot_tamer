# Tactics — the standing orders, what they do, and what actually works

`Tactics` (`src/core.ts`) parameterises the AI **side-agnostically**: the same fields
drive the player's orders and rival `GAMEPLANS`. A scouted plan is the one actually
fought.

⚠️ **That is true of the TURN engine. It was not true of the FIELD engine** — the one
M7 is moving the game to. `tools/tactics.ts` audits which fields the field engine
reads at all; run it after touching anything here.

```bash
npx tsx tools/tactics.ts
```

⚠️ **AND ITS FIELD LIST IS PARSED FROM THE `Tactics` INTERFACE, NOT HAND-WRITTEN.**
It was a literal array and it rotted the moment fields were renamed: `spacing` →
`formation` and `comboDiscipline` → `comboRole` left the audit reporting two
DELETED fields as "dead on the field engine" while the two LIVE ones went
unexamined. It had also never listed `burst` at all — a real tactic with 20 field
references that this document's own status table was missing too, because the table
was written from the audit. An audit that misses a live field is worse than none:
it reports a clean bill on something it never looked at.

⚠️ **`burst` THE TACTIC IS NOT `manaPolicy: 'burst'`.** Same word, two unrelated
controls, one interface — `burst` decides whether the biggest move is held for a
finish, `manaPolicy: 'burst'` decides whether MP is hoarded. Worth renaming one of
them; until then, read every mention carefully.

⚠️ **The audit counts MENTIONS, not firing.** An incidental reference launders a dead
field as a live one — a stray `!u.m.tactics?.openerIds` clause in an unrelated
condition once made the tool report `openerIds` as wired. A field dropping off the
dead list means the engine *reads* it, nothing more. Prove it FIRES separately:
build two teams differing only in that field and count the casts it should change.
`healPolicy` was the first with that evidence (the trio golden moved); `manaPolicy`
now has the strongest — `chooseMove` is exported and its gate asserted directly,
because a sweep cannot tell "the order fired and did little" from "it never fired".

---

## Status

| tactic | what it does | state |
|---|---|---|
| `temperament` | aggressive / balanced / cautious — the master dial on how far a monster commits | ✅ live, 19 refs |
| `targetPriority` | who to attack: weakest / casters / tanks / marked | ✅ live — **now reaches melee too** |
| `preserve` | below a HP threshold, play to survive — block, drop self-harm moves | ✅ live |
| `formation` | `keep` the deployed slot, or `tight`/`spread` and drift with the team | ✅ **live, built** (replaced `spacing`) |
| `commit` | `dive` past the enemy front line, or `hold` and refuse to over-extend | ✅ live |
| `healPolicy` | `triage` holds a restore until an ally is ≤55% HP; `steady` fires when up | ✅ live, **verified** |
| `useCover` | prefer ground where an obstacle breaks enemy line of sight | ✅ live |
| `burst` | `nuke` holds the biggest move for a finish; `steady` fires it the moment it is up | ✅ live, 20 refs |
| `manaPolicy` | `conserve` holds 30% MP as a finisher fund; `burst` spends freely | ✅ live, **verified** |
| `ccPriority` | lead with hard control before committing to damage | ⚠️ wired, unverified |
| `openerIds` | scripted opening sequence, up to 2 equipped moves, played in order | ❌ **dead — should work** |
| `openerId` | legacy single opener, superseded by `openerIds` | ❌ dead — **delete** |
| `engageRange` | skirmish at max reach / brawl close / hold position | ❌ **remove** |
| `comboRole` | `prime` applies the setup, `detonate` hunts whoever is primed | ✅ live, **verified** (was `comboDiscipline`) |

---

## Decisions taken (2026-08-01)

### REMOVE `engageRange`
Superseded. `CLASS_BASIC` now authors a reach band per class and `reachOf` takes the
shorter of best weapon and class basic, so where a monster stands is decided by what
it is holding rather than by an order. The tactic had **one** reference left in the
field engine and no longer expresses anything the engine does not already decide
better.

### ~~REMOVE~~ REWORK `comboDiscipline` — the removal was wrong

The original call was: *the combo is the PLAYER'S choice, not an order; a monster
holding both the setup and the payoff should prefer to combo without being told.*

⚠️ **THAT ARGUMENT ASSUMED A PREFERENCE THAT DOES NOT EXIST.** `comboDiscipline` is
one of the field-inert fields — nothing in the field engine reads it — so "it should
just combo by default" describes behaviour nobody wrote. Measured on the real
compositions (`tools/combo.ts`, 80 fights, mid tier):

| setup status | payoff casts | connected | rate |
|---|---|---|---|
| burn | 598 | 111 | **18.6%** |
| vulnerable | 40 | 4 | **10.0%** |
| **total** | **638** | **115** | **18.0%** |

⚠️ **AND 18% IS THE OPTIMISTIC READING.** The instrument treats a status as live for
8s from its `status` event, with no expiry and no cleanse, so the true rate is lower.

**523 of 638 payoff casts did not collect their multiplier.**

⚠️ **AND THAT IS NOT THE SAME AS 523 WASTED CASTS — see the correction under
"What shipped" below.** `effPowerField` already credits the multiplier when the
status is live, so a payoff fires clean because at base power it is still the best
thing in that kit, not because the engine is blind to the rider. A clean cast is
only *waste* if the move was priced below its peers to pay for the conditional. The
claim as first written overreached; the connect rate is a real diagnostic, but it
measures coordination, not waste.

Either way the tactic has a real job. It had simply never done it.

### Two EARLY DETONATORS added first (2026-08-01)

⚠️ **THE 18% WAS PARTLY A LEVEL PROBLEM, NOT A TARGETING PROBLEM.** Every payoff sat
far above its own setup, and at train 850 (top stat ~455) only two were learnable:

| status | earliest applier | earliest payoff | gap |
|---|---|---|---|
| burn | lv40 | lv200 | 160 |
| vulnerable | lv120 | lv340 | 220 |
| **poison** | **lv90** | **lv560** | **470** |
| **bleed** | **lv280** | **lv780** | **500** |
| fear | lv160 | lv780 | 620 |
| doom | lv540 | lv780 | 240 |

That is why `combo.ts` saw only burn and vulnerable connect: the rest do not exist
below Masters. Two weak, early payoffs were authored against the two worst gaps —
lower multipliers than the capstones on purpose, because these are the versions you
combo *with*, not the ones you build toward:

- **`Fester`** — DEX / Venomcraft, lv220, ×1.5 poison (vs Virulence lv560 ×2.6)
- **`Twist the Knife`** — STR / Duelist, lv360, ×1.5 bleed (vs Bloodletter lv780 ×2.5)

⚠️ Fear was the third-worst gap and was deliberately SKIPPED: fear is applied on
0.42% of casts, so a fear payoff would be authoring a consumer for a status that
barely happens. Fix the appliers before adding a consumer.

**The two moves proved opposite halves of the argument:**

| status | payoff casts | connected | rate | |
|---|---|---|---|---|
| poison | 316 | 203 | **64.2%** | ← Fester: one monster holds both, chains itself |
| burn | 532 | 113 | 21.2% | |
| vulnerable | 40 | 2 | 5.0% | |
| bleed | 60 | 1 | **1.7%** | ← Twist the Knife: partner is a DIFFERENT monster |
| **total** | **948** | **319** | **33.6%** | was 18.0% |

✅ **`Fester` settles the level question.** Venomcraft drafts the applier and the
payoff onto the same monster, which chains them with no tactic at all — 64% connect
from a standing start. The gap was real and pricing fixed it.

⚠️ **`Twist the Knife` settles the TACTIC question, and is currently UNDERWATER.**
Its setup (Twin Fangs, DEX lv280) lives on a different monster to itself (STR
lv360), nothing coordinates the two, and it connects **1.7%** of the time — today a
trap pick that pays a premium and collects nothing in 98% of casts. No reprice fixes
that; it is precisely the job `comboRole` exists to do. Ship the tactic, or move it
to lv480 beside STR's own `Rend` so it can self-combo — but the first option is the
one that makes cross-stat play real.

### ✅ BUILT: `comboRole: 'prime' | 'detonate'`

⚠️ **NOT AN ON/OFF, BECAUSE AN ON/OFF HAS NO WRONG ANSWER.** "Hold the payoff for
its window" is either strictly right or a pure tempo loss depending on whether the
setup lands — which is not a decision the player makes, it is a dice roll they
watch. Split it across the two halves of the combo and it becomes ROLE ASSIGNMENT,
which is a decision with a real failure mode on both sides:

- **`prime`** — prioritises APPLYING a status some ally's kit pays off on. A score
  multiplier in `chooseMove`, exactly the shape `ccPriority` already uses. It is the
  enabler, and it gives up damage to be one.
- **`detonate`** — prefers TARGETS that already carry its setup status. ⚠️ It does
  NOT hold the payoff for a window; that half was deliberately left unbuilt (see
  below).
- **absent / Auto** — today's behaviour: fire whenever it scores best.

⚠️ **NAMED `prime`/`detonate`, NOT `start`/`finish`.** Three collisions already exist
in this vocabulary and "finish" hits the worst: `manaPolicy`'s reserve is *the
finisher fund* (`FINISHER_AT`), so two tactics would be talking about finishing on
one screen. "Start" sits next to `openerIds`; "mark" is taken by the scouting mark.
Prime/detonate collides with nothing, and the pool already contains an INT move
literally called `Detonate` — the game speaks this language already.

⚠️ **THE ROW MUST BE KIT-GATED.** Of 320 drafted monsters: 59% can prime, 26% can
detonate, 17% can do both, and **32% can do NEITHER**. Showing that third a live
control that does nothing is this project's signature failure mode. `TacticsControls`
already takes `loadout` as a prop.

⚠️ **ALL 10 PAYOFFS CONSUME THE STATUS.** Not a buff to sit on: prime, cash,
re-prime. Two detonators sharing one primer means the second whiffs, so the ratio is
roughly one primer per detonator — a real constraint the screen will teach.

### What shipped, and what it measured

Both halves are score nudges, in the shape `ccPriority` already proved:

- `prime` — `COMBO_PRIME_BONUS` (1.7×) on a move applying a status **this unit's
  SIDE** can cash, gated on the target not already carrying it.
  ⚠️ *Side*, not *self*: `FieldUnit.comboPrimes` is the union of the team's
  cashable statuses, resolved once at setup because `chooseMove` never sees allies.
  That union is what makes prime/detonate a division of labour rather than two
  settings on one monster.
- `detonate` — `COMBO_TARGET_BIAS` (0.45, same scale as `priorityBias`) toward an
  enemy already carrying a status **this unit** can cash.
  ⚠️ **Applied at BOTH `pickTarget` sites.** The melee branch returns before the
  scoring loop — the exact route by which `targetPriority` was dead on most of the
  roster for months — and `Twist the Knife` is a *melee* detonator, so the melee
  path is the case this exists for, not an afterthought. A test pins it.

| setup status | comboRole off | assigned | |
|---|---|---|---|
| poison | 64.0% | 65.5% | already self-comboing — nothing to coordinate |
| burn | 21.3% | 21.6% | ditto |
| vulnerable | 5.0% | 2.3% | |
| **bleed** | **1.7%** | **10.7%** | ← the cross-monster case, 6× |
| **total** | **33.6%** | **34.6%** | |

✅ **The tactic helps exactly where it was supposed to and nowhere else.** A monster
holding both halves is already attacking the enemy it just primed, so a target bias
has nothing to add — poison and burn barely move. Bleed, whose primer (Twin Fangs,
DEX) and payoff (Twist the Knife, STR) sit on *different monsters*, is the case with
a coordination problem, and it improves 6×.

⚠️ **BUT 1 POINT OVERALL IS A SMALL RETURN, AND THE HEADLINE CLAIM NEEDS CORRECTING.**
"523 casts collected nothing" reads as pure waste, and that is not established.
`effPowerField` **already credits the `bonusVsStatus` multiplier** when the status is
live (`engine.ts:328`), so a payoff is scored honestly both ways — it fires clean
because at base power it is still the best thing in that kit, not because the engine
is blind. A clean cast is only *waste* if the move was priced below its peers to pay
for the rider. `Fester` and `Twist the Knife` were authored that way deliberately;
whether `Cinderburst` (40 power, cd 3, lv200) is fairly priced clean is a **separate
pricing audit**, not something `comboRole` can fix.

⚠️ **So the move-holding half is still NOT built, and should stay unbuilt until that
audit happens.** Holding a payoff for a window costs tempo — `manaPolicy` measured
that price — and if the payoffs are fairly priced clean, holding them is a straight
loss. Reprice first, then decide.

A whole team on `setup` never converts. A whole team on `payoff` stalls, because
nobody applies anything. That tension is the tactic, and it is per-monster, which is
where it belongs on the two screens.

⚠️ **PREFER THE TARGET BEFORE HOLDING THE MOVE.** Target preference is free — it
reuses `priorityBias`, which is shipped, verified, and now reaches melee — while
holding a move costs tempo. This session already measured what withholding costs in
this engine: `manaPolicy`'s finisher fund is correct and still sits ~3 kills behind
spending freely. Build the free half first, measure the connect rate again, and only
add a hold if 18% has not moved far enough.

⚠️ **`attrition` IS THE ONLY GAMEPLAN THAT SETS THIS FIELD** (`comboDiscipline:
true`), and it is also the gameplan built around `poison` + `payoff`. It should
become `'payoff'`, and its status-appliers `'setup'` — which is only expressible
once tactics are genuinely per-monster rather than stamped team-wide.

### ✅ FIXED: `manaPolicy` is a finisher fund

- **`burst`** — spend freely, no reserve. Identical to absent, deliberately, so no
  existing caller changed.
- **`conserve`** — hold `MANA_RESERVE` (30%) of the pool, and release it on the
  kit's **dearest** move once the target drops below `FINISHER_AT` (50% HP).

⚠️ **TWO WRONG VERSIONS SHIPPED FIRST, and they are the same mistake from opposite
ends.** v1 blocked any cast that dipped below the reserve, so a `conserve` unit
never spent the 30% at all and ended fights holding mana. v2 let it through for the
dearest move with **no condition on the target**, so the reserve went the moment the
dearest move was simply the dearest move. A fund that empties itself on a
full-health enemy is not a fund. **A reserve is neither untouchable nor free — it is
saved FOR A MOMENT, and the moment has to be in the code.** That moment is
`FINISHER_AT`.

⚠️ **DEAREST BY MP, NOT BY POWER.** The gate only ever bites on a move the unit
cannot otherwise afford, so the fund exists to keep the EXPENSIVE option live; a
cheap hard-hitter never trips it and needs no help. Mana prices effectiveness in
this pool, so cost is the honest anchor.

⚠️ **`chooseMove` IS EXPORTED FOR THIS, and only for this.** Both wrong versions
survived because the evidence was statistical — a sweep cannot tell "the order
fired and did little" from "the order never fired". The gate is a three-way
condition (reserve / target HP / dearest move) and `tactics.test.ts` now asserts all
three directly, plus the pair v1 would fail.

**Balance — the three versions side by side** (`FINISHER_AT` 0.00 reproduces v1,
1.01 reproduces v2; `bulwark`/Phalanx and `attrition`/Choir are the compositions
that run `conserve`):

| | total dur | kills | Phalanx mirror 6v6 | its kills |
|---|---|---|---|---|
| 0.00 — v1, never released | 24.5s | 196 | 30.9s | 27 |
| **0.50 — shipped** | 24.6s | 196 | **32.2s** | 27 |
| 1.01 — v2, no HP condition | 24.5s | 199 | 30.1s | 30 |

⚠️ **BE HONEST ABOUT WHAT THIS BOUGHT.** The order is now *correct* — it does what
it says — but as a *strategy* `conserve` is currently ~3 kills behind spending
freely across 40 fights, sitting with v1 rather than v2 on that count. The payoff it
is supposed to earn (a held spell converting a wounded enemy into a dead one) is not
showing at mid tier; what it reliably produces is a longer bulwark mirror (+2.1s).
Totals are inside the ±1.9s noise band either way. `FINISHER_AT` is the dial if that
needs to change — lower it and `conserve` hoards through fights it could have
closed, raise it and it stops being distinguishable from `burst`.

### MAKE `openerIds` WORK
Ten UI references — a player builds a scripted opening and the field engine ignores
it entirely. ⚠️ This is the only one of the five that is **not** a scoring nudge: it
needs per-unit sequence state (which opener index this monster has played), so it
cannot be done as a multiplier in `chooseMove` the way `ccPriority` was.

---

## Two screens: TEAM tactics and MONSTER tactics

The orders split by **what they are a decision about**. A team order is a plan for
the side — it should read the same for every monster on it. A monster order is that
individual's own behaviour, and two monsters on one team should routinely differ.

### Team tactics — one setting for the side

| tactic | why it belongs to the team |
|---|---|
| `temperament` | how hard the SIDE commits; mixing it per monster produces a team fighting two plans at once |
| `commit` | dive or hold — whether the side over-extends together |
| `healPolicy` | triage or steady is a plan for the team's whole mana pool, not one healer's habit |

⚠️ **`spacing` LEFT this screen.** It was listed here on the reasoning that a
formation is meaningless if half the team disagrees. That reasoning survives — the
SHAPE is still a team artefact, drawn on the deploy screen — but *adherence to it*
is the interesting decision and it is per monster. See `formation` below.

### Monster tactics — per individual

| tactic | why it belongs to the monster |
|---|---|
| `ccPriority` | only meaningful on a monster that HAS hard control; nonsense as a team-wide toggle |
| `manaPolicy` | a nuker holds its reserve, a filler-caster should not — the opposite orders on one team is correct play |
| `useCover` | a back-liner hugs the pillar, the wall in front of it must not |
| `preserve` | when THIS monster gives up on the fight and plays to live; a per-monster risk appetite |
| `formation` | one monster can hold its slot while another fans out — see below |
| `targetPriority` | see below — the one that gains the most from being per-monster |

⚠️ **`targetPriority` becomes an enemy PICKER, not a rule.** Today it is an abstract
preference (weakest / nearest / biggest threat). Per monster, against a scouted
field, it should let the player name *which enemy* this monster goes for — which is
what makes scouting worth paying for. A scouted cup already reveals the rival's
`TeamGameplan`; naming the enemy healer and pointing two monsters at it is the
payoff that turns scouting from information into a decision.

⚠️ **`openerIds` is unassigned.** A scripted opening is per-monster by nature (it
names that monster's own equipped moves), so it belongs on the MONSTER screen — but
it is still unbuilt, so place it when it is built rather than reserving space now.

⚠️ **Splitting the screens is a UI change over a SHARED data model.** `Tactics` stays
one interface; the two screens are two views onto it. Do NOT fork the type — the
whole reason a scouted plan is the one actually fought is that rival `GAMEPLANS` and
player orders write the same fields.

---

## `formation` — SHIPPED

Replaced `spacing`. One control, three choices:

| option | behaviour |
|---|---|
| `keep` | hold the SLOT it deployed in, relative to the team as the team advances |
| `tight` | no slot — drift with the team and clump up (focus-fire, AoE bait) |
| `spread` | no slot — drift with the team but fan out (AoE insurance) |

### What `keep` actually does

The anchor is **`live ally centroid + this unit's deploy offset`**, blended into the
goal at `FORMATION_KEEP_PULL` (0.55), coached by temperament like every other
spatial order.

⚠️ **THE ANCHOR IS RELATIVE, NOT ABSOLUTE.** Pinning to the literal deploy point is
a formation that never leaves the start line — at a 0.55 blend nothing would ever
reach the enemy and every fight would run to sudden death. `tactics.test.ts` pins
this directly: a straggler whose team has advanced is pulled FORWARD, not back to
spawn.

⚠️ **BOTH CENTROIDS OVER THE SAME LIVE SET, both including self.** Hold the deploy
centroid over the original six and a team down to two keeps standing in the gaps
where its dead used to be, politely spread out for an enemy that is now
concentrated. Taking them over *different* sets offsets the whole formation by the
difference.

⚠️ **`deployPos` is stamped AFTER the obstacle nudge**, not before — a slot inside a
rock is one the unit spends the whole fight failing to stand on.

⚠️ **`keep` takes the BASE spacing radius**, not a third density setting. Under
`keep` the density was already drawn on the deploy screen, so a multiplier on top
would be a second, invisible order fighting the slot the unit is being pulled
toward. Density is a choice only when there is no slot to hold.

### Measured — `tools/formation.ts`

⚠️ **MIRRORED PAIRS, NOT A WIN RATE AGAINST A FIXED FOE.** The compositions are not
symmetric, so "the keeping team won 60%" would mostly measure whether template A
beats template B. Every fight runs both ways round and the score is how often the
ORDERED side won, which cancels the matchup out. Sign test, 160 fights each:

| order | ordered side W–L | p | median duration | range |
|---|---|---|---|---|
| `keep` | 74–86 | 0.34 | 22.7s (plain 22.3s) | 7.6–66.9s |
| `tight` | 82–78 | 0.75 | 21.4s | 7.4–58.9s |
| `spread` | 73–87 | 0.27 | 23.4s | **9.7–256.8s** |

✅ **All three are win-rate neutral, which is the RIGHT result for a tactic** — a
style choice, not a power choice. They visibly change the fights (durations and
outcomes both move) without any one being correct.

⚠️ **But `spread` has a 256.8s tail**, against a 48.0s worst case unordered — one
fight nearly ran the 300s cap out. That is PRE-EXISTING (`spacing: 'spread'` used
the same ×2.6 radius) and had simply never been measured. A team ordered to fan out
can fail to concentrate enough damage to close a fight at all. Left as-is because
it is a real cost of a real choice, but it is the first thing to look at if the
grind complaint comes back.

### ⚠️ No `break` option — designed and rejected

A third setting, "ignore the formation and hunt `targetPriority`", was designed for
diving an enemy back line and then cut. Two reasons, both worth keeping written
down so it is not re-proposed:

1. **It re-creates by order the one shape this engine balances worst.** Melee
   measured 100% deaths alone against 81% beside a second front-liner — same
   monsters, different team. A monster crossing the field solo IS that case.
2. **It needed the melee nearest-target early return opened up.**
   `decide.ts:pickTarget` returns the nearest enemy for melee and returns BEFORE
   the scoring loop `priorityBias` lives in — so `targetPriority` is currently dead
   on every melee unit, including the knife assassin the idea rested on. That guard
   is correct as a default; its own comment records that value-chasing "is exactly
   what made melee race around the map".

✅ Note (2) is now FIXED — see below. Note (1) still stands on its own.

---

## `targetPriority` — from rule to picker

Today: four abstract preferences, applied as a **nudge, not an override**
(`priorityBias`, +0.30–0.50 into a score that reaches ~5) — deliberately, so a target
order coaches rather than mind-controls.

- `weakest` — bias by missing HP
- `casters` — bias support-role enemies
- `tanks` — bias by maxHp (⚠️ also *lowers* predation in `traitsFor`)
- `focus` — bias whoever carries `Monster.marked`

⚠️ **`focus` + `marked` IS ALREADY THE PICKER, at team scale.** `town.ts:2352` sets
`marked` on exactly ONE enemy at scout time and the whole side prioritises it. So the
per-monster picker is a *generalisation of shipped plumbing*, not new machinery:
`marked: boolean` on the enemy becomes a `targetId` on the chooser.

### ✅ FIXED: the order now reaches melee

`pickTarget` returned the nearest enemy for melee and returned **before** the
scoring loop `priorityBias` lives in, so `targetPriority` did nothing at all on a
melee monster — most of the roster. Set in the UI, set by three `GAMEPLANS`,
silently discarded.

⚠️ **The fix is NOT to score melee like ranged.** Value-chasing across open ground
is the failure that branch exists to prevent. The order is spent as a **bounded
distance discount** instead: a prioritised enemy counts as up to
`MELEE_PRIORITY_SLACK` (10) × `priorityBias` world units nearer than it is — 3.0–5.0
units, against deploy hexes 2.6 apart. That is one to two ranks: far enough to step
around a front-liner onto the marked healer behind it, nowhere near far enough to
cross a 40-unit field. `tactics.test.ts` pins BOTH halves — it takes the mark at 15,
and refuses it at 30.

It also pays for the reach honestly: standing next to someone you are not hitting is
free damage for them.

**Measured — `tools/priority.ts`**, mirrored pairs, 119 fights where the defender
actually fields a support (⚠️ fights without one would dilute a real effect toward
zero with fights the order cannot express):

| slack | support died | median time to that kill |
|---|---|---|
| 0 (melee deaf) | 73/119 | 14.4s |
| 4 | 72/119 | 13.9s |
| 6 | 70/119 | 13.9s |
| 8 | 77/119 | 13.7s |
| **10 (shipped)** | 73/119 | **12.9s** |

*(plain, no order: 68/119 at 15.7s.)*

Monotone on time, noise on the count: ordering `casters` does not change **whether**
their support dies, it changes **when** — and the melee half of the order is worth
about half of that. Fights where the order was already obeyed by the ranged units
were carrying it alone.

⚠️ **The `trio` golden moved 27.6s → 23.6s and this time the cause IS understood** —
goldens set `DEFAULT_TACTICS`, whose `targetPriority` is `weakest`, so melee now
finishes wounded bodies.

⚠️ **The 40-matchup sweep saw NOTHING, and that was the instrument's fault.**
`generateMonster` did not set `tactics`, so every unit in every balance tool had
EVERY ORDER DISABLED and the sweep returned byte-identical totals across five values
of `MELEE_PRIORITY_SLACK`. Now fixed at the source — `generateMonster` sets
`DEFAULT_TACTICS`, no goldens moved, and the sweep gives five different answers to
those five values. New reference numbers and the discontinuity warning are in
`docs/BALANCING.md`.

### Proposed shape

```
targetPriority: 'weakest' | 'casters' | 'tanks' | 'focus' | { enemyId: string }
```

- Named enemy resolves to a bias like `focus`'s, and falls back to `weakest` when
  that enemy is dead or was never in the fight.
- ⚠️ **It must survive not scouting.** A named enemy is only offerable when the field
  is known; unscouted cups and the ranch's standing orders must still produce a legal
  value. Keep the four abstract options as the always-available set.
- ⚠️ **Keep it a bias.** Raising it to an override would undo the diveThreat /
  isolation / focus-fire reads that make the field engine look coordinated, and would
  make every monster on a team walk past a live threat to reach one named body.
  A `break`-formation monster is where a *stronger* bias belongs — that is what the
  player traded position for.

### Why this makes scouting pay

Scouting already reveals the rival `TeamGameplan`. It currently buys ONE kill order
for the whole side. Per monster it buys a plan: two bodies on their healer, the
assassin `break`ing onto their artillery, the wall holding formation in front. That
is information becoming a decision, which is the thing scouting has never quite done.

---

## Constants

| constant | value | file |
|---|---|---|
| `TRIAGE_AT` | 0.55 | `tamerengine/types.ts` |
| `MANA_RESERVE` | 0.30 | `tamerengine/types.ts` |
| `CC_PRIORITY_BONUS` | 1.8 | `tamerengine/types.ts` |

⚠️ `CC_PRIORITY_BONUS` is a **multiplier, not an override** — control still has to be
worth casting, so a 10-power stun does not beat a finisher on a nearly-dead target.
It is also gated on the target not already being under hard control, or the order
spends every stun re-stunning someone helpless.

---

## Open

- `ccPriority` fire-checked — wired, never proven to change a cast.
- `openerIds` implemented with per-unit sequence state.
- `engageRange` deleted from `Tactics`, `GAMEPLANS`, `TacticsPanel`, and any saves
  migration. ⚠️ `comboDiscipline` is NO LONGER on that list — see the rework above.
- `comboDiscipline` reworked to `'setup' | 'payoff'`, target-preference half first,
  and `tools/combo.ts` re-run to see whether 18% moves.
- Split `TacticsPanel` into TEAM and MONSTER screens per the section above —
  two views over one `Tactics` type, not two types.
- `targetPriority` reworked from an abstract rule into a scouted-enemy picker.
- ⚠️ **`targetPriority` is dead on melee** — `decide.ts:pickTarget` returns before
  `priorityBias` is ever read. Fix this BEFORE building the picker, or the picker
  ships dead on half the roster.
- ⚠️ **An unexplained golden.** The `trio` field golden moved when `manaPolicy`'s
  reserve rule changed, and absent `manaPolicy` should be a no-op — that golden sets
  none. Recaptured on instruction, not because the cause was understood. Chase it
  before trusting the constant.
