# Personality Stats — Discipline, Nerve, Aggression, Focus, and Speed

**2026-08-04.** Written as an **extension plan**, not a new-system spec. `docs/AUTOBATTLER_DESIGN.md`
§3 originally proposed "four new personality stats" without checking the codebase first —
`src/tamerengine/personality.ts` (v0.93) already ships six axes, live-wired into `decide.ts`,
covered by tests, with zero migration cost for existing saves. This is the **eighth** instance of
this project's "already built while documented as missing" pattern
(`docs/HANDOVER.md` lists the first seven). Everything below builds *on* the existing system.
**Nothing in this document authorises editing source — it is a specification for whoever picks up
the build steps in §12.**

Read `src/tamerengine/personality.ts`, `docs/TAMERENGINE.md`, and `docs/AUTOBATTLER_DESIGN.md` §3
(corrected alongside this doc) before making any further change to this system.

---

## 0. What already exists, in one table

| axis | internal field | file | already does |
|---|---|---|---|
| Aggression | `aggression` | `personality.ts` | feeds `FieldTraits.predation`, archetype tagging |
| Teamplay | `teamplay` | `personality.ts` | feeds `FieldTraits.cohesion` |
| Mental | `mental` | `personality.ts` | `panicThreshold()` |
| Temperament | `temperament` | `personality.ts` | `coachedValue()` — the obey/coaching blend weight |
| Awareness | `awareness` | `personality.ts` | `threatRadius()` |
| Patience | `patience` | `personality.ts` | `spendAbove()` — cooldown-holding threshold |
| Speed | *(none)* | *(none — currently `2.4 + DEX/1000×3.6` inline in `engine.ts`/`Spatial.gd`)* | per-unit movement, DEX-derived today |

Generation: `basePersonality(seed, species)` = `speciesBias(species)` (a pure function of the
species' six base combat stats) + `±18` individual jitter, off the stream
`seed + ':personality:v1'` — a stream that never touches `generateMonster`'s own rng, which is why
every existing save already has a personality with no migration step.

Runtime value: `personalityOf(monster) = clamp(basePersonality + monster.personality drift)`. The
drift field (`Monster.personality?: Partial<Personality>`) is the only STORED piece; the base is
recomputed fresh every time and is therefore always the same for a given (seed, species) pair.

**What this document adds:**
1. A seventh axis, `focus` (§1).
2. A trainable "bred band" for the drift layer, and the coach that moves it (§§3–4).
3. Breeding inheritance for personality — does not exist today at all (§5).
4. Speed as a genuinely new, independently-modelled trainable stat (§6) — NOT built the same way
   as the six/seven personality axes, and that split is deliberate (see §6.0).
5. UI exposure: four of the seven axes surface to the player (§7).
6. The Godot/data/save impact, all of which is currently zero on the Godot side — personality has
   not been ported at all yet (§8).

---

## 1. The seventh axis — Focus

**What it governs:** target commitment. `sticky` (holds a target ~4s unless it dies or a taunt
overrides) vs `reassess` (re-scores every decision tick) — `docs/AUTOBATTLER_DESIGN.md` §2A. This
is genuinely new: nothing today reads a per-monster value to decide retarget cadence. The closest
existing hook is `RETARGET_EVERY` (`tamerengine/types.ts:471`, default 0.6s) and `retargetIn` on
`FieldUnit` — both currently class/role-level constants (the `Duellist` role lengthens it as a
fixed override), not personality-driven.

**Generation — species bias, matching the existing formula style exactly:**

```ts
// speciesBias(), appended as the 7th field:
focus: 50 + (share(b.STR) + share(b.INT) - share(b.DEX) - share(b.CHA)) * 16,
```

| Symbol | Type | Range | Description |
|---|---|---|---|
| `share(n)` | float | ~0.3 – 2.5 | `(n / totalBaseStats) × 6` — 1.0 means an even share of the species' base stat total |
| `b.STR`, `b.INT`, `b.DEX`, `b.CHA` | int | species-authored | the species' base combat stats |
| `focus` (bias, pre-jitter) | float | roughly 15 – 90 before clamp | the species' innate lean before individual variation |

**Output range:** clamped to 0–100 after jitter, same as every other axis (`clamp()` in
`personality.ts`).

**Worked example:** Grivvel (Mammal, wolverine — `STR 34, DEX 40, CON 22, WIS 12, INT 10, CHA 14`,
total 132): `share(STR)=1.545, share(DEX)=1.818, share(INT)=0.455, share(CHA)=0.636`.
`focus = 50 + (1.545 + 0.455 − 1.818 − 0.636) × 16 = 50 + (−0.454) × 16 ≈ 42.7` → a scrappy,
short-tempered predator (per its own flavour text) reads as **mildly distractible**, which fits: a
"relentless and short-tempered" wolverine is not a patient hunter, it takes whatever opening
appears.

**Design rationale for the stat pairing:** every one of the existing six axes includes a `WIS`
term. Focus deliberately does not — STR (a brawler locks onto what it's hitting) and INT
(calculated persistence: is switching worth it?) pull it up; DEX (quick reflexes, quick to
redirect at the next opening) and CHA (reactive to the wider spectacle of a fight) pull it down.
This gives Focus a correlation pattern distinct from the other six, rather than becoming "another
WIS-derived stat" — and it hands DEX-heavy species (already the fastest, most aggressive,
highest-awareness archetype) a genuine soft spot: hard to keep locked onto one target.

⚠️ **IMPLEMENTATION ORDER CONSTRAINT.** `basePersonality()` calls `vary()` once per field, and JS
evaluates object-literal properties left to right — so the six existing axes' RNG draws happen in
a fixed sequence today (aggression → teamplay → mental → temperament → awareness → patience).
`focus`'s `vary()` call **must be appended after `patience`**, both in `speciesBias()`'s return
object and in `basePersonality()`'s. Doing so adds one new draw at the END of the stream and
changes NOTHING about the six existing values for any existing save. Inserting it anywhere else
(alphabetically, say) would shift every subsequent draw and silently re-roll every monster's
`patience` in every save that has one. See §11 for the full safety argument — this was one of the
two questions I was asked to answer directly.

---

## 2. Who exposes what — the UI/hidden split, argued

Four axes surface as player-visible, tactic-linked stats: **Aggression, Discipline (`temperament`),
Nerve (`mental`), Focus**. Two stay hidden: **Teamplay, Patience**.

**Why these four:** each has a *tactic the player directly sets* that it is the default for —
`docs/AUTOBATTLER_DESIGN.md` §2 is explicit that "personality supplies each monster's preferred
value, shown in the UI as its default." Aggression defaults positional intent (§2B) and target
priority (§2A); Discipline is literally the obey-weight for the whole tactics system; Nerve is the
`when hurt` default (§2D); Focus is the target-commitment default (`sticky`/`reassess`, §2A).

**Why not Teamplay and Patience, yet:** this project's own legibility doctrine
(`docs/AUTOBATTLER_DESIGN.md` §6, and `CLAUDE.md`'s "every order must be legible enough to
predict") says a visible stat needs a visible lever. Teamplay only feeds a **team-level derived
value** (`FieldTraits.cohesion`) — there is no per-monster tactic called "how much of a team
player are you" for the player to set or override, so showing the stat with nothing to compare it
against is a spreadsheet column, not character. Patience is the natural driver of the **ability
policy** axis (§2D: `free` / `hold big` / `combo`) — but that axis is designed, not built (§2D is
present in `AUTOBATTLER_DESIGN.md` as a table, with no field on `Tactics` yet). Promoting Patience
before its lever exists has the same problem as Teamplay: nothing to explain it against.

**Recommendation, not yet built:** when ability policy ships as a real `Tactics` field, promote
Patience alongside it in the same PR — the internal machinery (`spendAbove()`) is already there
and already reads a personality value; only the exposure and the Tactics field are missing. Do
not promote it before then.

---

## 3. The bred band — how wide, and how visible

The **drift field** (`Monster.personality?: Partial<Personality>`) is the trainable/breedable
layer for all seven axes; the **base** (`basePersonality`) never moves and is not player-visible
as a separate number — the player only ever sees `personalityOf()`, the resolved value.

**Band width — recommended default: ±15, flat, same for every monster.**

| Symbol | Type | Range | Description |
|---|---|---|---|
| `PERSONALITY_BAND` | int (constant) | 15 | maximum magnitude of drift from a monster's own effective starting value (base + any inherited drift from breeding, §5) |
| `drift[axis]` | int | −15 … +15 | the coach's cumulative effect on one axis for one monster |
| `personalityOf(m)[axis]` | int, derived | 0–100 | `clamp(base[axis] + drift[axis], 0, 100)` — unchanged formula, drift is simply now bounded |

**Output range:** the resolved value stays 0–100 (existing `clamp()`); the NEW clamp is on
`drift` itself, at generation/coach-write time, to `[-PERSONALITY_BAND, +PERSONALITY_BAND]`.

**Worked example:** Grivvel's focus base (species+individual roll) lands at 47. The coach can move
it anywhere in **32–62** over time (47 ± 15). A player who wants a maximally sticky Grivvel cannot
get there through coaching alone if the roll came in low — they need a different parent, which is
the point (§5).

⚠️ **Why flat ±15 over the two alternatives I considered, and why this is a recommendation, not
a confirmed decision** — the coordinating question that would have settled this
(`AskUserQuestion`) did not reach the user this session. Flagging explicitly for override:

- *Narrower (±10)* leans harder into "breeding is the skill" — coaching alone can't compensate
  for a bad roll, so the right PARENTS matter more. Cleaner story, smaller number to tune.
- *Species/breeding-variable width* (a "malleability" stat mirroring the potential-star system)
  is more expressive but adds a whole second breeding axis to explain in the UI, for a stat
  category that is already adding five new numbers to the ranch screen in one pass. **Over-designed
  for a first landing** — see §13.
- **±15 flat is the middle ground**: simple to show as a bar with a shaded range, one constant to
  tune later against playtesting, and it does not block a variable-width version being layered on
  top afterward if breeding-for-temperament turns out to want more depth.

**UI visibility of the band:** show it as a **shaded region on the stat's bar** (the coached-in
value inside a lighter full-range shade), the same visual language already used for the bloodline
`potential`/stat-cap display on the ranch stat bars — no new UI pattern, reuse the existing one.

---

## 4. The coach — facility, pacing, and why it can't compete with combat training

**Mechanism:** one **weekly slot**, entirely separate from the training row's weekly action slot
(`applyWeek`'s `activity` field) — a monster can be assigned a combat drill AND a personality-coach
target in the same week without conflict, because the coach does not touch `stats`/`hp`/`mp`/
`stamina`, only `personality` drift. This is what satisfies AUTOBATTLER §8 #25's "does NOT compete
with combat training" literally, not just in spirit: it is a second, independent weekly
assignment, not a substitute for the first.

**Weekly drift rate:** mirrors `rollDrillGain`'s shape (happiness-weighted roll, not a flat
number) but at personality's own scale:

```
gain = round(uniform(2, 5) × happinessSkew(happiness))
```

| Symbol | Type | Range | Description |
|---|---|---|---|
| `gain` | int | 2 – 5 per week, happiness-skewed toward 5 the same way `rollDrillGain` skews toward its ceiling | one week's movement on the targeted axis, toward whichever direction the player coaches (raise or lower) |
| `happinessSkew(h)` | float, existing formula reused | 0 (uniform) … 1 (top-skewed) | identical skew law to `rollDrillGain`, `h` = the monster's current happiness 0–10 |

**Output range:** the applied `gain` is further clamped so `drift` never exceeds
`±PERSONALITY_BAND` — a coach cannot push a monster past its bred ceiling no matter how many weeks
are spent trying, exactly as a combat stat cannot train past its league/potential cap.

**Worked example:** at happiness 5 (`happinessSkew ≈ 0.55`), a typical week nets **+3 to +4** on
the targeted axis. Moving a monster from the bottom of its band to the top (a 30-point swing at
±15) takes roughly **8–10 weeks** of dedicated coaching on that single axis — deliberately slower
than combat training (a basic drill nets ~6 points/week per stat with no ceiling this tight),
because personality is meant to read as *temperament*, not a fifth set of numbers to grind.

**Facility unlock/upgrade — recommendation: the existing manual pattern, cost left TBD.**
Mirrors `EXTREME_MANUAL_COST`/`DIVERSE_MANUAL_COST` (`town.ts`) exactly: a one-time gold purchase
from the Ranch Shop — "Personality Coach" — unlocks coaching one axis per week; a second purchase
("Senior Coach" or similar) raises that to two or three concurrent axes. This reuses a pattern the
player already knows (two manuals exist today) rather than inventing new economy shape.

⚠️ **The gold costs themselves are an explicit TBD, not an oversight.** `CLAUDE.md`'s roadmap
defers the economy rebalance until every sink/source is in "so it's balanced against reality in
one pass," and `docs/CLASS_REWORK.md` already deferred its own reassignment price on the same
ground. A coach-unlock price belongs in that same pass, not invented here in isolation. This
mirrors the third option I would otherwise have asked about — recommending it directly since it is
consistent with a standing project rule, not a genuinely open call.

**Which axes can the coach reach?** All seven internal axes, including the two hidden ones
(Teamplay, Patience) — hidden from the STAT DISPLAY, not from the coach. A player who has read the
bestiary or watched enough fights can still deliberately coach a monster's cohesion/cooldown-timing
behaviour even without a bar to watch move; the coach screen lists all seven by internal
description, the ranch stat panel shows only the four (§7). This keeps the mechanic honest — the
axes aren't inert, only unlabelled — and costs nothing extra to build since the coach writes to
`Monster.personality[axis]` the same way regardless of which axis it targets.

---

## 5. Breeding inheritance — the lever that makes the ranch feed the fight

**This does not exist today.** `town.ts:breed()` sets `baby.stats`, `baby.heritageStat`,
`baby.generation`, `baby.signature`, `baby.potential` — nothing personality-related. This section
is entirely new design, not a correction of existing behaviour.

**Goal, restated from the brief:** breeding must let a player select FOR temperament, not merely
receive a personality independent of parentage — this is the mechanism that makes "breeding the
right monsters to have the correct tactics" (the game's stated vision) actually true for
personality, the same way `BREED_HEAD_START` already makes it true for raw stats.

**Mechanism — an inherited drift nudge, mirroring `BREED_HEAD_START`'s shape exactly:**

```ts
// New, at breed() time, once for each of the 7 axes:
const parentRealized = (personalityOf(a) + personalityOf(b)) / 2  // per axis
const babyOwnBase = basePersonality(babySeed, baby.species)        // per axis, its own roll
const nudge = round(BREED_PERSONALITY_HEAD_START * (parentRealized - babyOwnBase))
baby.personality[axis] = clamp(nudge, -PERSONALITY_BAND, +PERSONALITY_BAND)
```

| Symbol | Type | Range | Description |
|---|---|---|---|
| `parentRealized[axis]` | float, per axis | 0–100 | average of both parents' CURRENT resolved personality — base + their OWN accumulated coaching, so a well-coached parent passes its coached improvement forward, not just its innate roll |
| `babyOwnBase[axis]` | float, per axis | 0–100 | what the baby's own `(babySeed, species)` pair would roll with no inheritance at all |
| `BREED_PERSONALITY_HEAD_START` | float (constant) | recommended 0.4 | fraction of the gap between the baby's own roll and its parents' average that inheritance closes |
| `baby.personality[axis]` | int, stored (new) | −15…+15 (clamped to the band) | the baby's STARTING drift — the coach still has the full band to work with afterward, in either direction |

**Output range:** `baby.personality[axis]` is clamped to `±PERSONALITY_BAND` exactly like coach
output — inheritance and coaching share one ceiling, so a baby can never START already maxed out
with no room for the player's own coaching to matter.

**Worked example:** two parents both coached to Discipline 85 (`parentRealized = 85`); a baby whose
own seed+species would roll Discipline 55 (`babyOwnBase = 55`). `nudge = round(0.4 × (85 − 55)) =
12`. The baby starts at `55 + 12 = 67` Discipline — noticeably more disciplined than a random
hatchling of its species, but not simply cloned from its parents, and the coach still has room to
push it toward 82 (67 + 15) if the player keeps working it.

**Why 0.4, not `BREED_HEAD_START`'s 0.3:** personality's band is much narrower (±15) than the
combat-stat ceiling gap `BREED_HEAD_START` operates against, so a smaller fraction would make
selective breeding for temperament barely register against the ±18 individual jitter every monster
already carries. 0.4 is a recommended starting point for the eventual re-baseline, not a measured
number — the balance baseline is suspended project-wide per `CLAUDE.md`.

**Does personality inheritance climb across generations, like `potential`/`BREED_STEP_BY_TIER`?**
**Recommendation: no, not in this pass.** `potential`'s climbing ladder exists because stat
ceilings are meant to be a multi-generation dynasty project. Personality's band is already
deliberately narrow and does not need a second escalating axis on top — layering "wider bands over
generations" in now would be exactly the kind of scope creep flagged in §13. If breeding-for-
temperament turns out to be too shallow after playtesting, a generational band-widening step is
the natural next lever, built once there's evidence it's wanted.

---

## 6. Speed

### 6.0 Why Speed is modelled DIFFERENTLY from the seven personality axes — read this first

The personality axes use a **derive-fresh-every-time** architecture (base recomputed from seed +
species on every read, only drift stored) specifically because that made "every existing save
already has one, zero migration" true for free. **That specific benefit does not apply to Speed —
there is no existing save with a Speed value to protect, migration is required either way** (every
save needs the new field added with a default/generated value regardless of which architecture is
chosen). So Speed does not inherit that constraint, and the user's own framing — *"the bias just
gives them additional starting stat"* — points at the simpler, more familiar model: **Speed is
generated ONCE at birth (a real stored number, not a formula), and trains/breeds exactly like a
combat stat thereafter.**

⚠️ **THIS SUPERSEDES `docs/ENGAGEMENT_DESIGN.md` §6's recommendation.** That document worked the
"where does speed come from" question in full (options 6a–6e) and recommended **6e**:
`speed = CLASS_SPEED[class] × BODY_SPEED[body]`, a **derived, non-trainable multiplier** —
written before the personality-stats decision existed. AUTOBATTLER_DESIGN's decision #23 ("Speed
is a 0–100 stat, like personality... uncapped by league") and the user's confirmation this session
both describe a trainable stat, not a computed multiplier. **§6e is superseded, not merely
alternative** — noted here explicitly so the next reader who finds `ENGAGEMENT_DESIGN.md` §6 does
not rebuild the derived-multiplier version by mistake. The one piece of §6e worth keeping is
folded in below: body/species still gives Speed real identity, just as a STARTING bias rather than
a permanent multiplier.

⚠️ **STILL BINDING, UNCHANGED BY ANY OF THIS: SPEED MUST NEVER BE USED TO FIX KITING.**
`docs/ENGAGEMENT_DESIGN.md` records the measurement — without the advance/retreat asymmetry,
*"a chase NEVER resolves... left units out of range 76% of the fight regardless of field size or
speed (both measured, both invariant)."* `Spatial.BACKPEDAL_MULT` (0.60) stays exactly as it is.
Making Speed trainable/breedable does not reopen this — a player raising a monster's Speed stat is
a legitimate build choice with real cost (see §6.2), not a systemic fix for the chase problem,
which is a different mechanism (`CLOSING_BONUS`, minimum range, the engagement boundary) entirely.

### 6.1 Generation — species/body bias as a starting value only

```ts
// New, at generateMonster() time, alongside the existing stat generation:
const speedBias = 50 + (share(b.DEX) - share(b.CON)) * 20
const speed = clamp(round(speedBias + individualJitter(±10)), 0, 100)
```

| Symbol | Type | Range | Description |
|---|---|---|---|
| `speedBias` | float | roughly 10 – 90 before clamp | species lean, off the SAME base-stat mechanism as personality's `speciesBias()` — DEX pulls it up, CON pulls it down |
| `individualJitter` | float | ±10 | one-time roll at generation, same spirit as personality's ±18 individual variance but narrower — Speed is meant to read as a body-plan trait first, an individual trait second |
| `speed` (stored) | int | 0–100 | the monster's STARTING Speed stat — stored on `Career`/`Monster`, not recomputed on later reads |

**Output range:** 0–100, clamped once at generation. After this point Speed behaves exactly like a
combat stat: training/coaching mutates the STORED value directly (§6.2), nothing recomputes it
from species again.

**Worked example:** Balaenix (Avian, shoebill stork — `DEX 44, CON 18` of a 140 total):
`share(DEX)=1.886, share(CON)=0.771`. `speedBias = 50 + (1.886 − 0.771) × 20 ≈ 72.3`. A
"motionless until it strikes" ambush hunter still gets a genuinely fast STARTING roll from its
build — the bias is about body plan, not temperament, so Balaenix's patient hunting STYLE
(governed by its Focus/Patience personality) and its raw physical quickness (Speed) are free to
tell different stories about the same animal. That is the intended texture: a species can be
built for speed and still be coached/played cautiously.

### 6.2 Training — a new drill, or the coach facility?

**Recommendation: the personality coach facility trains Speed too**, as its fifth option, rather
than adding a seventh combat drill. Reasoning:

- Speed is explicitly grouped with the four personality stats throughout this brief and
  `AUTOBATTLER_DESIGN.md` — treating it as a genuinely separate combat-drill-style stat with its
  own weekly slot would mean SIX new weekly systems (5 stats × dedicated slots) instead of one
  coach facility with five targets, which is a much smaller UI and mental-model footprint.
- It still satisfies "does not compete with combat training" (§8 #25) exactly as personality does
  — the coach's weekly slot is independent of the training row's slot.
- Weekly gain and band width for Speed use the SAME constants as personality (§§3–4) for
  consistency — a `SPEED_BAND` of ±15 (0–100 scale, so this is a real, meaningful range) and the
  same happiness-skewed 2–5/week roll.

⚠️ Unlike personality, Speed's "band" (§3's `PERSONALITY_BAND`) is anchored to its STORED starting
value, not to a re-derived base — so the band moves with the stat as the coach trains it in one
direction repeatedly, exactly like `statCapFor()`'s relationship to trained combat stats, NOT like
personality's fixed-base-plus-bounded-drift model. Concretely: `SPEED_BAND` limits how far ONE
COACHING ASSIGNMENT can move Speed from wherever it currently sits before the player has to leave
it and let happiness/other factors catch up — not a hard lifetime ceiling relative to birth. This
is deliberately looser than personality's band because Speed has no upper stat-cap ladder (§8 #23:
"uncapped by league") to interact with; the only ceiling is the 0–100 scale itself.

### 6.3 Breeding — same head-start shape as combat stats, not personality's nudge

Because Speed is a stored value (§6.0), it breeds like `BREED_HEAD_START` handles the six combat
stats, not like personality's inherited-drift nudge (§5):

```ts
baby.speed = Math.max(baby.speed, Math.round(BREED_HEAD_START * (a.speed + b.speed) / 2))
```

Reusing the EXACT existing constant (`BREED_HEAD_START = 0.3`) rather than inventing a new one —
Speed is architecturally a combat-stat-shaped field now, so it should inherit on the combat-stat
formula, not the personality one. No new constant needed here.

### 6.4 Mapping 0–100 to world units/second — the integration point

Today: `speed_of(dex) = SPEED_MIN + (SPEED_MAX − SPEED_MIN) × clamp(dex/1000, 0, 1)`
(`Spatial.gd`/`engine.ts`, `SPEED_MIN=2.4`, `SPEED_MAX=6.0`). Once Speed is its own 0–100 stat,
the formula's DOMAIN changes, nothing else:

```
speed_of(spd) = SPEED_MIN + (SPEED_MAX − SPEED_MIN) × clamp(spd / 100, 0, 1)
```

| Symbol | Type | Range | Description |
|---|---|---|---|
| `spd` | int | 0–100 | the new Speed stat, replacing `dex` as the input |
| `SPEED_MIN` | float (existing constant, unchanged) | 2.4 | world units/second at Speed 0 |
| `SPEED_MAX` | float (existing constant, unchanged) | 6.0 | world units/second at Speed 100 |
| `speed_of(spd)` | float, derived | 2.4 – 6.0 u/s | the per-tick movement speed the sim already consumes everywhere (`step_len`, `BACKPEDAL_MULT`, `CLOSING_BONUS` all multiply this) |

**Output range:** unchanged — 2.4 to 6.0 world units/second, the same envelope every existing
spatial constant (`DEPLOY_SEPARATION`, `TARGET_CLOSE_SECONDS`, `CLOSING_ENGAGE_DIST`) was tuned
against. **This is the whole point of keeping `SPEED_MIN`/`SPEED_MAX` untouched**: nothing in the
arena, deploy, or engagement math needs to be re-tuned by this change, because the OUTPUT range is
identical — only which stat feeds the formula changes.

**Worked example:** a monster trained to Speed 72 (Balaenix's starting bias from §6.1, roughly
untouched by coaching): `speed_of(72) = 2.4 + 3.6 × 0.72 = 4.99` u/s — comparable to a DEX-560
monster under the OLD formula, but now the number is legible on its own 0–100 scale and directly
comparable to the monster's OTHER new stats on the ranch screen, rather than requiring a mental
conversion from a combat stat's 0–1000 scale.

⚠️ **This formula-level change is a source edit** (`engine.ts`, `Spatial.gd`) and is explicitly
OUT of this document's scope to make — it is recorded here as the exact spec for whoever picks up
§12 step 3.

---

## 7. UI — where these read as character, not a spreadsheet

**Placement:** the ranch stable detail panel (`RanchView` per `docs/META_GAME_DISPOSITION.md` §4),
alongside the existing stat bars/aptitude tags/bloodline star display — same visual family, new
row.

**What's shown, and how:**

- **Four bars, not a table.** Aggression / Discipline / Nerve / Focus, each a labelled 0–100 bar
  with the trainable band shown as a lighter shaded region either side of the current value
  (§3) — visually identical treatment to the existing stat-cap shading, so the player reads it as
  "the same kind of information" rather than a new UI language.
- **Speed sits with them as a fifth bar**, visually grouped but distinguishable (e.g. a different
  bar colour/icon) since it trains/breeds on the combat-stat model (§6), not the personality
  drift model — a small honest visual cue that it behaves slightly differently under the hood,
  without requiring the player to know why.
- **No raw numbers as the primary readout.** Per `docs/AUTOBATTLER_DESIGN.md`'s "personality
  supplies the DEFAULT, shown in the UI as what the creature *wants* to do" — the bar's PRIMARY
  label should be a short descriptor derived from the value (e.g. Aggression 78 reads "Eager",
  Discipline 30 reads "Improvises"), with the number available on hover/detail rather than
  headline. This is what makes it read as temperament rather than a sixth stat block — the same
  distinction the game already draws between "stats" (six bars, numeric) and "class" (a name, not
  a number).
- **On the tactics/orders screen**, each axis' current descriptor appears next to the tactic it
  defaults (Aggression next to positional intent + target priority, Discipline as a small "how
  much of this order will actually stick" indicator, Nerve next to the `when hurt` selector, Focus
  next to target commitment) — directly satisfying AUTOBATTLER §2's "shown as its default so the
  player can see what the creature *wants* to do before overriding it," and reinforcing the link
  between the ranch-side stat and the battle-side behaviour it drives.
- **Post-fight decision log** (`docs/AUTOBATTLER_DESIGN.md` §6) should cite the axis by its UI
  name when it explains a decision — `"Aegisox fell back (Nerve 62: clean disengage)"` is already
  the exact example given in that document; this document confirms `Nerve` = `mental` is the field
  to read for that line.

---

## 8. Data and save impact

### 8.1 The 16 `data.json` tables — none of them move

`moves, species, innateEffects, classes, lines, classLines, lineOf, classBasic, channelCastTime,
channelRange, fieldStatus, beneficialStatuses, hardControlStatuses, spreadableStatuses, leagues,
teamSizeByLeague` — **zero of these sixteen need a new column.** Every generation formula in this
document (personality's seven axes, Speed's bias) computes off the SAME six base combat-stat
columns the `species` table already carries. This is a deliberate consequence of following the
existing `speciesBias()` pattern rather than inventing a new per-species authoring block — see §1
and §6.1.

### 8.2 TypeScript side (`src/`) — additive only

- `core.ts`: `Personality` interface gains `focus: number` (7th field). `Monster` interface's
  `personality?: Partial<Personality>` type widens automatically (it already types against
  `Personality`). New: `Monster.speed?: number` (absent = legacy/rival fallback to the current
  DEX-derived formula, so nothing existing breaks — same "absent means old behaviour" discipline
  already used for `tactics`/`tameness`).
- `Career` interface (`game.ts`/`town.ts`): needs `personality?: Partial<Personality>` (currently
  absent — this is the gap that makes the coach possible at all) and `speed: number` (NOT
  optional — every Career is generated from here on, unlike the drift field).
- `careerMonster()` (`game.ts:472`): needs one added line, `personality: c.personality`, and
  `speed: c.speed` — it currently builds a `Monster` from a `Career` and does not pass personality
  through AT ALL today, meaning the coach (which operates on `Career`) would otherwise have no
  effect on the `Monster` a battle actually uses. This is the single most load-bearing wiring
  change in this whole document — everything else is inert without it.
- `generateMonster()` (`monster.ts`): needs the Speed generation step (§6.1) added alongside
  existing stat generation; personality itself needs NO change here (it is computed on read, not
  at generation, by design).
- `breed()` (`town.ts:785`): needs the personality-nudge block (§5) and the Speed head-start line
  (§6.3) added.
- `personality.ts` (`tamerengine/`): `speciesBias()` and `basePersonality()` each gain one
  appended field (§1's ordering constraint).

### 8.3 Godot side — this is where the real new work is

⚠️ **Personality has not been ported to Godot at all yet, in any form** — there is no
`personality.gd`, and none of the 6 (now 7) axes exist anywhere in `monster-tamer/scripts/` or
`monster-tamer/data/`. `MonsterInstance` (`monster_instance.gd`) carries no personality field, no
Speed field, and `save_game.gd`'s `_serialize_monster`/`_deserialize_roster` only round-trip
`speciesId` and the six `Classify.STATS`. This is consistent with `docs/TAMERENGINE.md`'s own
framing — "nothing in `src/tamerengine/` is imported by the shipping game loop yet" — the whole
personality system is presently TypeScript-only.

**What porting this needs, when that reason arrives** (per `docs/META_GAME_DISPOSITION.md`'s own
standing rule — do not move code before there's a reason to):

- A `personality.gd` mirroring `personality.ts`: `species_bias()`, `base_personality()`,
  `coached_value()`, `panic_threshold()`, `spend_above()`, all seven axes. Same determinism
  discipline as every other `.gd` port — seeded RNG only, no `randf()`.
- `MonsterInstance` gains `var personality_drift: Dictionary = {}` (mirrors `Monster.personality`)
  and `var speed: float = 50.0` (mirrors the new `Career.speed`).
- `save_game.gd`'s `_serialize_monster`/`_deserialize_roster` gain two fields — `personalityDrift`
  and `speed` — alongside the existing `speciesId`/`stats` round-trip. ⚠️ Following the file's own
  existing rule ("DERIVED MONSTER FIELDS ARE NEVER STORED"): only the DRIFT is persisted for
  personality (matching the TS side exactly), never the resolved/base values — the base recomputes
  from `species_id` on load, exactly as `class_name_`/`max_hp` etc. already do. Speed, being a
  stored stat rather than a derived one, IS persisted directly (like `stats`), not recomputed.
- A **contract case is worth adding** if/when this ports, matching the project's existing
  discipline (`classify.json`, `derive.json`) — `personality.json` pinning `speciesBias`/
  `basePersonality` outputs for a handful of sample (seed, species) pairs, so a future GDScript
  port can be verified by exact equality rather than by eye. Not urgent while the system is
  TS-only and unshipped, but cheap to set up alongside the port itself.

**Nothing above blocks §1–§7.** The generation/breeding/coach/UI design is engine-agnostic; the
Godot port is a separate, later build step (§12 step 6), consistent with `CLAUDE.md`'s standing
"the port is a skeleton, not a specification" doctrine.

---

## 9. `classForStats` exclusion — the guarantee, stated precisely

**Guarantee:** none of the five new stats (Discipline/Nerve/Aggression/Focus/Speed) can ever
influence class derivation, under either the current emergent model or the proposed assignable
model (`docs/CLASS_REWORK.md`).

**Why this is true by construction, not by a new guard:**

- `classForStats(stats: Stats): string` (`core.ts:812`) takes a `Stats` object and sorts
  `STATS` (`['STR','DEX','CON','WIS','INT','CHA']`) by value — a closed, six-element array. There
  is no code path by which `Personality` (a structurally distinct interface) or a `speed: number`
  field could enter that sort, because `stats[k]` only ever indexes into `STATS`'s six keys.
- `CLASS_REWORK.md`'s proposed stat GATE (§2, "assign class gated by stats") is described as
  reading "current stats" — the same `Stats` type, same six keys. Nothing in that proposal
  introduces a channel for `Personality` or `Speed` to reach it either.
- Therefore: **no new guard, test, or validation needs to be written for this exclusion.** It
  already holds, and continues to hold after this document's changes, purely because `Personality`
  and the new `speed` field are never merged into the `Stats` type anywhere. The only way to BREAK
  this guarantee would be to explicitly write `stats.focus` or similar into a `Stats`-typed object
  somewhere — which would be a visible, reviewable one-line change, not something that could
  happen silently.

---

## 10. Interaction with the ability-policy default (§2D)

`docs/AUTOBATTLER_DESIGN.md` §2D lists an "ability policy" axis (`free` / `hold big` / `combo`)
paired with the `when hurt` tactic, and does not assign any stat as its default. **Recommendation:
`patience` should drive it**, once it is built — `spendAbove()` already computes exactly this
question ("how soft does a target have to be before I spend a big cooldown on it") and is already
read live in `decide.ts`. `hold big` is what a high-patience monster already does by default with
no tactic set at all; `free` is what a low-patience monster does. This is not new design so much
as recognising that §2D's third column is describing behaviour `patience` already produces, and
formalising it as an explicit `Tactics` field (rather than an always-on personality effect) is what
would let the player OVERRIDE a monster's natural patience the same way `temperament`
(`aggressive`/`cautious`) already lets them override its aggression. I'd treat this as a small,
low-risk follow-up to whoever builds the `Tactics.abilityPolicy` field, not part of this
document's build order (§12) — it touches `Tactics`/`decide.ts`, outside personality-stats' scope.

---

## 11. RNG-stream safety of adding `focus` — the direct answer

**Question asked: does adding `focus` disturb `seed + ':personality:v1'` in a way that breaks
existing saves?**

**Answer: no, provided it is appended LAST — and this is a hard implementation constraint, not a
style preference.**

`basePersonality()`'s RNG stream is consumed strictly in the order the object literal's values are
evaluated (`aggression`, then `teamplay`, then `mental`, then `temperament`, then `awareness`,
then `patience` — six sequential `rng()` draws through `vary()`, each pulling the mulberry32
generator forward by one step). Nothing else shares this specific `rng` instance; it is created
fresh inside `basePersonality()` and discarded at the end of the call. Two consequences:

1. **`speciesBias()` needs no ordering care at all** — it is a pure function of the species'
   already-authored base stats, no RNG involved, so `focus`'s bias formula can be added anywhere
   in that function's return object with zero effect on anything.
2. **`basePersonality()`'s `vary()` call for `focus` MUST come after `patience`'s.** If it is
   inserted anywhere earlier (alphabetically, say, between `aggression` and `mental`), every
   `vary()` call from that point onward draws from a DIFFERENT position in the same seeded stream
   than it did before — silently re-rolling `mental`, `temperament`, `awareness`, and `patience`
   for every monster in every existing save, with no error, no test failure (unless a golden
   happens to assert an exact personality value, which none currently do), and no visible symptom
   beyond monsters "feeling different" than they did last session. Appending after `patience`
   means the six existing draws are untouched and a SEVENTH, NEW draw simply extends the stream by
   one step, which existing code never depended on being empty.

**This is exactly the same class of hazard `CLAUDE.md`'s "RNG discipline" note already warns
about** for `advanceWeek`/`previewWeekEffects` ("anything that changes monster generation's rng
shifts the golden battle tests") — the mechanism is identical (call-order-dependent seeded
streams), just in a different file. I've stated the constraint as a ⚠️ in §1 and again in the
corrected `AUTOBATTLER_DESIGN.md` §3 specifically so an implementer doesn't have to rediscover it.

---

## 12. Staged build order

1. **`focus` axis** — add to `speciesBias()` and `basePersonality()`, appended last (§1, §11).
   Zero-risk, additive, no other system depends on it yet. Ship first so it's live before anything
   else references it.
2. **`Career.personality` + `careerMonster()` wiring** (§8.2) — without this, the coach has no
   effect on actual battles. This is the load-bearing plumbing step; nothing in §§3–5 matters until
   it lands.
3. **The coach facility** — weekly slot, drift-write mechanism, band clamp (§§3–4). Depends on
   step 2. Ship WITHOUT the gold-gated unlock at first if useful for testing (always-available in
   a dev build), then wire the manual-purchase gate before it reaches players.
4. **Breeding inheritance** — personality nudge (§5) and Speed head-start (§6.3). Depends on step
   2 (needs `Career.personality` to exist) and step 5 (needs `Career.speed` to exist) — sequence
   after both.
5. **Speed** — generation (§6.1), `Career.speed` field, `careerMonster()` wiring (parallel to step
   2's personality wiring, same PR is reasonable), the coach's fifth target (§6.2). The
   `engine.ts`/`Spatial.gd` formula swap (§6.4) is a SEPARATE, later step — Speed can exist as a
   trained/bred stat before anything in the field sim reads it, exactly as `Monster.personality`
   already exists and is read by nothing outside `tamerengine`.
6. **UI** (§7) — stat bars, descriptors, tactics-screen defaults, decision-log labelling. Can start
   as soon as step 2/5 land (there's a real value to show), does not block anything after it.
7. **`engine.ts`/`Spatial.gd` Speed integration** (§6.4) — swap the movement formula's input from
   `dex` to `spd`. This is the step that actually changes battle behaviour; do it once Speed has
   had time to generate/train/breed across a reasonable population, so there's a real distribution
   to tune the formula's output range against (though `SPEED_MIN`/`SPEED_MAX` themselves shouldn't
   need to move — see §6.4).
8. **Godot port** (§8.3) — explicitly LAST, and explicitly "when there's a reason to," per
   `docs/META_GAME_DISPOSITION.md`'s standing rule. Nothing above requires it.

---

## 13. What's over-designed, and what I'd cut if asked to simplify

Asked to say so plainly: **five new stats is already a lot of new ranch-screen surface, and two
things in this document are the ones I'd cut first if the studio wants a smaller first landing.**

1. **Speed as a fifth coach-trainable axis is the single biggest "does this earn its place"
   question.** Of the five, it's the only one with no existing tactic that reads it as a
   *preference* the way Aggression/Discipline/Nerve/Focus each default a named `Tactics` field —
   it just makes a monster faster, full stop. That's a legitimate stat, but it is closer in KIND to
   the six combat stats than to personality, and grouping it under "the coach" (§6.2) rather than
   giving it its own drill row is itself an argument that it doesn't quite belong with the other
   four. If the studio wants a smaller first cut, **ship Discipline/Nerve/Aggression/Focus alone
   and hold Speed for a second pass** — nothing in §§1–5 or §7 depends on Speed existing, and §6 is
   already written as a self-contained section for exactly this reason.
2. **Species/breeding-variable band width (§3's third, rejected option)** — flagged in-line as
   over-designed already; not recommending it, just naming it so it isn't proposed again without
   the context of why it was set aside.
3. **What I would NOT cut, even under pressure to simplify:** the breeding nudge (§5). It's the
   one piece of this whole document that directly satisfies the brief's own framing —
   "this is the lever that makes the ranch feed the battle half, which is the game's stated
   vision" — and it's cheap (one small formula, reuses the existing `personalityOf`/
   `basePersonality` functions verbatim, no new stored state beyond what the coach already needs).
   Cutting it would leave breeding controlling everything EXCEPT the exact new axis this document
   exists to add.
