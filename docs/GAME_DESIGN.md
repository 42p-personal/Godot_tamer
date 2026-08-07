# Monster Tamer — Game Design Document

> **Status:** Draft / concept. Living document.
> **Genre:** Monster raising & breeding sim with auto-battler tournaments.
> **Primary inspirations:** Monster Rancher (raising, breeding, lifespan, care loop) + Teamfight Manager (auto-battle you influence as a manager, not a controller).
> **Platform:** Web (browser-first). Local-first saves. **Pixel-art** presentation.

---

## 1. Core Fantasy

You are a **Tamer**: you raise, train, breed, and combine monsters, then enter them into
tournaments to climb a ladder of **licenses/leagues**. You never directly control a monster
in combat — battles are **auto-simulated** (Teamfight Manager style). Your skill expression
is in *how you build the monster* and *how you prepare for the fight*: stat training, breed and
class, trait/ability selection, fusion, team composition, and — in team formats — **explicit
tactics and formations**.

The central tension is **lifespan**: every monster has a limited competitive career. Your best
fighter *will* age out, so you are always investing in the next generation via breeding, fusion,
and expert trainers.

Monsters are **sapient, willing partners**, not captured beasts — a Tamer provides training, care, and
food; the monster brings its own ambition and reasons for competing. See the [Bestiary](BESTIARY.md) for
the 20 launch species and their stories.

---

## 2. Game Loop

### 2.1 Macro loop (the calendar)
- Time advances on a **schedule** (weeks within months within years).
- **Tournaments** open for sign-up in specific months. The player plans training around them.
- Each in-game year the monster ages; breeds have a limited number of competitive years.

### 2.2 Weekly actions (micro loop)
Each week the player chooses an activity for a monster (and/or the stable):
- **Training** — raise a targeted stat via a **drill** (§2.4). Costs stamina, may cause fatigue/injury.
- **Rest** — recover stamina/fatigue, reduce injury risk.
- **Feeding** — diets that nudge stats, growth, and lifespan/condition.
- **Excursions** — expeditions/adventures for items, rare seeds, encounters, money, XP.
- (Future) other care actions as systems expand.

### 2.3 Tournament week
- If signed up, the monster competes. Battles **auto-resolve** as an auto-battler.
- Results affect ranking, prize money, reputation, and rank-up eligibility.

### 2.4 Training drills
When the weekly action is **Training**, the player picks a **drill**. All gains are clamped to the
license cap (§3) and reduced by the life-stage **training malus** (§9.1: −5% Fully Grown, −20% Elder).

**Basic drills** — raise one stat by a **minor** amount (≈ +6/week), no downside. Safe, steady growth.

| Drill            | Raises |
|------------------|--------|
| Weight Training  | STR    |
| Agility Course   | DEX    |
| Endurance Run    | CON    |
| Meditation       | WIS    |
| Study            | INT    |
| Stage Practice   | CHA    |

**Intensive drills** — raise one stat by a **greater** amount (≈ +12/week) but **slightly lower another**
(≈ −4/week). Faster specialisation at the cost of a weakness; the pairings are thematic.

| Drill               | Raises (greatly) | Lowers (slightly) | Theme                          |
|---------------------|------------------|-------------------|--------------------------------|
| Powerlifting        | STR              | DEX               | bulk dulls speed               |
| Berserker Training  | STR              | WIS               | fury over composure            |
| Sprint Intervals    | DEX              | STR               | lean speed, less brawn         |
| Acrobatics          | DEX              | CON               | nimbleness over toughness      |
| Toughening Regimen  | CON              | DEX               | mass and grit, heavier feet    |
| Iron Diet           | CON              | INT               | body over book                 |
| Deep Meditation     | WIS              | STR               | inner focus, softer muscle     |
| Ascetic Trance      | WIS              | CHA               | solitude over showmanship      |
| Arcane Study        | INT              | CON               | mind sharpens, body wanes      |
| Runic Focus         | INT              | STR               | mind over might                |
| Oratory Drills      | CHA              | INT               | charm over calculation         |
| Showmanship         | CHA              | CON               | flair over conditioning        |

Each stat has **two** intensive drills (each sacrificing a different stat), so a trainer can push a
build hard while choosing *which* weakness to accept. Data lives in `src/drills.ts`.
*(Exact per-week values and stamina/injury interactions are tuning, §13.)*

### 2.5 Feeding & happiness
Each monster is assigned a **random favourite** and **hated** food at birth. Feeding is a **start-of-week
choice, separate from the weekly activity**: at the start of each week a **food market** opens and the
player may buy **one** food for the monster.

- **Favourite → +1 happiness**, **hated → −1**, any other food is neutral (0). **Not feeding → −1
  (hunger).**
- **Happiness** runs **0–10** and scales battle damage at **+1% per point** — max happiness deals
  **×1.10** (`happinessMultiplier` in `src/core.ts`).
- **Prices fluctuate weekly** — each food's price is rolled at **±40% around its base value** every week
  (`rollMarket` in `src/game.ts`). Only **one food per week per monster** may be bought.

**Foods** (cheapest → most expensive base price; feeding costs money, §12):

| Food         | Base | 
|--------------|:----:|
| Vegetables   | 5    |
| Fruit        | 10   |
| Meat         | 20   |
| Sweet Treats | 40   |

**The complication:** a monster whose favourite is **Sweet Treats** is dear to keep happy, and even a
veggie-lover can be priced out on a bad week. When the favourite spikes, the player must choose — pay the
premium for **+1**, settle for a cheaper neutral food to *maintain* (0), or go **hungry (−1)** to save
gold for training and rank-up fees. Favourite/hated are fixed on the monster; the market and happiness are
live state.

---

## 3. Leagues & Ranking (Licenses)

Ascending order. A monster's **license** gates its **stat cap** (see §5).

| # | League         | Stat Cap |
|---|----------------|----------|
| 1 | Wood           | 100      |
| 2 | Copper         | 200      |
| 3 | Tin            | 300      |
| 4 | Bronze         | 400      |
| 5 | Iron           | 500      |
| 6 | Silver         | 600      |
| 7 | Gold           | 700      |
| 8 | Platinum       | 800      |
| 9 | Masters League | 900      |
| 10| Tamer Elite    | 999      |

---

## 4. Tournaments

### 4.1 Formats
- **Early game:** 1v1 only, **round-robin** for standing.
- **Rank-up:** a **knockout tournament** decides whether a monster can promote to the next league.
- **Progression unlocks:** larger/alternate formats appear as the game advances —
  **2v2, 3v3, 4v4, 1v1v1v1 (free-for-all)**, etc. Team formats are what make **formations**
  and multi-monster **tactics** meaningful (see §11), so unlocking a format also unlocks that
  layer of pre-fight decision-making.

### 4.2 League rulesets
- Each league introduces **its own rules**, picked from a **random ruleset pool for that league**.
- Rules and new **tournament types** are introduced as the player climbs.
- Examples of the kind of modifiers a ruleset might hold (to be designed): stat restrictions,
  banned abilities, element bans, weather/arena effects, team-size requirements, handicaps.

> **Design note:** model rulesets as data (modifiers applied to the battle sim), so new leagues =
> new data, not new code.

---

## 5. Stats

Monsters have **six** core stats. Start values are typically **under 50**. Trainable up to **999**,
but **capped by the monster's current license/league** (see §3).

| Stat         | Meaning             | Combat effect                                   |
|--------------|---------------------|-------------------------------------------------|
| Strength     | Physical strength   | Physical **melee** damage **and defence**       |
| Dexterity    | Nimbleness          | **Dodging** and physical **ranged** damage      |
| Constitution | Toughness           | **Hitpoints**                                   |
| Wisdom       | Wisdom              | **Mana regeneration** and **total mana**        |
| Intelligence | Arcane aptitude     | **Elemental magic** damage                      |
| Charisma     | Charm               | **Non-elemental "voice"** damage                |

> **Intelligence ≠ sapience.** Every monster is a **fully intelligent, sapient creature** that competes
> **willingly** (see the [Bestiary](BESTIARY.md)). The INT stat measures only a creature's aptitude for
> **elemental magic** — a Warrior with INT 10 is as thoughtful and willful as a Wizard with INT 900; it
> just channels no elemental power. A low INT never means "unintelligent."

A monster's **class** is a label derived from its **stat priorities** — a *primary* (major) stat and
a *secondary* (minor/lesser) stat. Class signals a monster's battle role, informs recommended
training, and can gate/flavour certain abilities.

This table is **balanced for even stat distribution** (see rationale below).

| Class       | Primary (major) | Secondary (minor) | Role sketch                          |
|-------------|-----------------|-------------------|--------------------------------------|
| Tank        | Constitution    | Strength          | Soak damage, hold the front          |
| Warrior     | Strength        | Constitution      | Durable melee bruiser                |
| Rogue       | Dexterity       | Strength          | Fast, aggressive skirmisher          |
| Ranger      | Dexterity       | Intelligence      | Ranged, evasive, arcane archer       |
| Sage        | Wisdom          | Intelligence      | Mana engine + support caster         |
| Wizard      | Intelligence    | Wisdom            | Elemental burst damage               |
| Spellsword  | Intelligence    | Constitution      | Sturdy battlemage (melee + magic)    |
| Spellshield | Constitution    | Wisdom            | Defensive caster / warder            |
| Captain     | Strength        | Charisma          | Frontline leader                     |
| Orator      | Charisma        | Dexterity         | Quick-tongued voice damage           |
| Bard        | Charisma        | Dexterity         | Mobile voice damage / disruptor      |

*(11 classes at launch.)*

### 6.1 Stat-distribution rationale
The original priorities made **Strength** the primary of 4 of 11 classes while Dexterity, Wisdom,
and Intelligence were each a primary only once — pushing the meta toward Strength builds. The table
above rebalances so each stat is a primary ~2× and a secondary ~2×:

| Stat | As primary | As secondary |
|------|:---------:|:------------:|
| Strength     | 2 | 2 |
| Dexterity    | 2 | 2 |
| Constitution | 2 | 2 |
| Wisdom       | 1 | 2 |
| Intelligence | 2 | 2 |
| Charisma     | 2 | 1 |

Combined coverage flattens to **4-4-4-3-4-3** across the six stats (was 5-3-3-3-5-3). No stat
dominates, and every stat is the carry for at least one archetype.

### 6.2 Body types drive population distribution
If class is **emergent** (default), the real spread of classes in play depends on which stat pairs
are common — set by **species/body type**, not the class table. Each body type therefore gets a
distinct **stat lean** so the roster naturally spans all archetypes (see §8.1).

> **Open items to confirm:**
> - Class **emergent** (re-labels as you train, default) vs **intrinsic** to the breed (fixed).
> - Notes used both "lesser" and "minor"; treated here as the same tier (**secondary**).
> - Only 11 of the 30 possible ordered stat pairs are named classes; the rest can read as
>   "generalist / no specialisation." Add more named archetypes later if desired.

---

## 7. Abilities & Moves

A monster's kit has **three kinds** of ability:

### 7.1 Innate abilities (species)
Signature abilities the species **always has**, listed per species in **§8.3**. These are **always in
effect** and **do not count** against the learned-move loadout.

### 7.2 Learned moves (shared pool, milestone-gated)
**Non-unique** moves from a **shared pool** grouped by stat / damage-channel — **10 skills per stat**
(60 total), listed in **§7.5**. Each skill has a **fixed learn level**; a monster learns it the moment
that stat crosses the level.

- **Learn ladder (per stat):** the 10 skills unlock at stat levels
  **40 · 90 · 160 · 240 · 330 · 430 · 540 · 650 · 780 · 920** (curve ≈ `L(n) = 35·n^1.4`, rounded). Same
  ladder for every stat; only the skill *content* differs. Early skills are reachable in low leagues; the
  last few need Platinum+ caps.
- **Learn level is *access order*, not a power ranking.** Some later skills are direct upgrades, but
  **many early skills stay optimal at any level** depending on circumstance — cheap, low-cooldown, or
  pure utility/status. The pool is a **toolkit, not a straight upgrade path**; picking the right 3 for the
  matchup matters more than always fielding the highest-level moves.
- **Every skill has attributes:** a **cooldown**, a **hit chance (accuracy)**, a **type** (damage / buff
  / debuff / status / control), and a **target** (self / ally / team / one enemy / all enemies).
  Big-impact skills lean toward **longer cooldowns and lower accuracy**; basic and utility skills toward
  **short cooldowns and high accuracy**. Some deal damage, some buff the user or team, some inflict a
  **status effect** (§7.6).
- **Variety** comes from **which stats a monster trains, and how high** (a WIS Sage learns WIS skills a
  STR bruiser never sees), and from **inheritance at hatch** (§7.4) — not from randomised thresholds.
  *(This fixed 10-skill ladder supersedes the earlier seed-rolled 3-tier sketch.)*
- **Loadout limit:** a monster may **equip only 3 learned moves at once** (freely swappable between
  weeks/battles). It can *know* every skill it has passed the level for, but fields only 3 — building the
  loadout is a key tactical decision.

### 7.3 Ultimate signature move (the 4th slot)
Every monster unlocks a **species-unique ultimate** the first time it reaches **600 in a stat** (requires
Gold+, §3). The ultimate occupies a **dedicated 4th move slot** and does **not** count against the 3
learned slots. Per-species ultimates are listed in **§8.3**.

> So a battle-ready monster fields: **innate passives** (always on) + **3 equipped learned moves** +
> **1 ultimate** (once unlocked). Fusion (§10) can combine/drop learned moves and innate traits.

> **Design note:** store moves as data — `{ channel, learnLevel, type, target, cooldown, accuracy,
> power, status? }` — from one library. The battle sim (§11), the loadout UI, and the fusion
> trait-picker (§10.4) all read from it.

### 7.4 Inherited moves at hatch
A hatchling starts with **very low stats** (§10.2), so it would normally know **no** learned moves yet.
Inheritance gives it a head start — it can be **born already knowing** some of its parents' learned moves.

Let **C** = the set of distinct learned moves known by the two sources (breeding parents, or the fusion
donor + target). For each move *m* ∈ C, the hatchling inherits it with probability:

> **p(m) = p_base × (both sources knew m ? 2 : 1)**,  with **p_base = 0.12** (tunable)

— shared moves are twice as likely. Then:
- **Guarantee ≥ 1:** if the independent rolls produce none, inherit **one** move chosen at random from
  C (weighted by p). Every hatchling is born with **at least one** parental move.
- **Cap 3:** at most **3** inherited moves — a newborn can't start with more than a full loadout.

Expected inherited ≈ `clamp(p_base × |C|, 1, 3)` — modest, so inheritance is a welcome bonus, not a
shortcut past training. Inherited moves are **known even though the hatchling's stats are below their
normal learn level**; the monster fills in the rest by training as usual, and bloodlines pass move
knowledge down the generations.

### 7.5 Shared learned-move pool (60 skills)
Ten skills per stat, at the learn levels from §7.2. Each also carries a **cooldown, accuracy, type and
target** (§7.2); status effects (§7.6) are marked in the effect text. **Learn level is access order, not
strict power** — effects below are sketches for the sim (§11) to tune.

**Strength — melee & defence** *(learn level → skill)*
| Lv  | Skill          | Effect (sketch)                                   |
|-----|----------------|---------------------------------------------------|
| 40  | Jab            | Quick light melee hit                             |
| 90  | Guard          | Block: reduce the next incoming physical hit      |
| 160 | Power Strike   | Heavy single-target melee blow                    |
| 240 | Cleave         | Melee hit that splashes to a second enemy         |
| 330 | Crushing Blow  | Melee that lowers the target's defence            |
| 430 | Bracer         | Passive: raises physical defence for the battle   |
| 540 | Earthshaker    | Melee AoE with a brief stun                       |
| 650 | Sunder Armor   | Melee that ignores a % of defence                 |
| 780 | Berserk        | Trade defence for a large melee-damage boost      |
| 920 | Titanfall      | Massive single-target melee finisher              |

**Dexterity — ranged & dodge** *(learn level → skill)*
| Lv  | Skill          | Effect (sketch)                                   |
|-----|----------------|---------------------------------------------------|
| 40  | Sling          | Light ranged shot                                 |
| 90  | Sidestep       | Small dodge-chance buff                           |
| 160 | Piercing Shot  | Venom-tipped ranged hit ignoring some armor; applies **Poison** |
| 240 | Twin Shot      | Two quick ranged hits                             |
| 330 | Blur           | High dodge for a few ticks                        |
| 430 | Snipe          | High-damage single ranged, slow windup           |
| 540 | Volley         | Light ranged AoE (hits all foes)                  |
| 650 | Riposte        | Counter a dodged attack with a ranged hit         |
| 780 | Rain of Arrows | Sustained ranged AoE                              |
| 920 | Deadeye        | Near-guaranteed critical ranged shot              |

**Constitution — HP & sustain** *(learn level → skill)*
| Lv  | Skill          | Effect (sketch)                                   |
|-----|----------------|---------------------------------------------------|
| 40  | Brace          | Small flat damage reduction this turn             |
| 90  | Second Wind    | Heal a little HP                                  |
| 160 | Taunt          | Force enemies to target this monster              |
| 240 | Iron Skin      | Passive HP / defence bump                         |
| 330 | Regenerate     | Heal over time                                    |
| 430 | Bulwark        | Soak damage aimed at an adjacent ally             |
| 540 | Last Stand     | Survive one lethal hit at 1 HP (once per battle)  |
| 650 | Fortify        | Large shield absorbing damage                     |
| 780 | Vital Surge    | Big heal + cleanse debuffs                        |
| 920 | Undying        | Auto-heal when dropping below a HP threshold      |

**Wisdom — mana & support** *(learn level → skill)*
| Lv  | Skill          | Effect (sketch)                                   |
|-----|----------------|---------------------------------------------------|
| 40  | Focus          | Restore a little mana                             |
| 90  | Meditate       | Mana-regen buff                                   |
| 160 | Cleanse        | Remove a debuff from an ally                      |
| 240 | Empower        | Buff an ally's next move                          |
| 330 | Mana Font      | Team mana-regen aura                              |
| 430 | Barrier        | Magic-damage shield on an ally                    |
| 540 | Haste          | Speed up an ally's actions                        |
| 650 | Channel        | Convert mana into a team heal                     |
| 780 | Arcane Insight | Big mana battery + cooldown reset                 |
| 920 | Ascendance     | Team-wide power surge for a few ticks             |

**Intelligence — elemental magic** *(learn level → skill)*
| Lv  | Skill          | Effect (sketch)                                   |
|-----|----------------|---------------------------------------------------|
| 40  | Spark          | Small elemental bolt                              |
| 90  | Ember          | Minor fire damage; applies **Burn** (HP damage over time) |
| 160 | Frost Shard    | Elemental hit that slows                          |
| 240 | Shock          | Elemental hit with stun chance                    |
| 330 | Fireball       | Solid single-target elemental burst               |
| 430 | Ice Lance      | High elemental damage, pierces                    |
| 540 | Chain Lightning| Elemental bolt bouncing between foes              |
| 650 | Inferno        | Fire AoE; applies **Burn** to all hit               |
| 780 | Blizzard       | Elemental AoE + freeze                            |
| 920 | Meteor         | Massive elemental AoE nuke                        |

**Charisma — voice (non-elemental)** *(learn level → skill)*
| Lv  | Skill          | Effect (sketch)                                   |
|-----|----------------|---------------------------------------------------|
| 40  | Taunt Cry      | Light voice damage + minor aggro                  |
| 90  | Discord        | Voice hit; applies **Blind** (lowers target accuracy) |
| 160 | War Chant      | Team attack buff                                  |
| 240 | Screech        | Voice AoE, small damage; chance to inflict **Fear** |
| 330 | Demoralize     | Lower enemy attack                                |
| 430 | Anthem         | Team defence buff                                 |
| 540 | Sonic Boom     | Heavy single-target voice burst                   |
| 650 | Lullaby        | Chance to put an enemy to sleep                   |
| 780 | Cacophony      | Voice AoE; applies **Confusion**                  |
| 920 | Crescendo      | Massive voice AoE finisher                        |

### 7.6 Status effects
Skills, innate abilities, and ultimates can inflict these **status effects**. (*Slow* also exists as a
minor timing debuff.)

| Status        | Effect                                                                                   |
|---------------|------------------------------------------------------------------------------------------|
| **Blind**     | Lowers the target's **chance to hit** (accuracy).                                         |
| **Poison**    | Target takes ongoing **mana damage** — drains its mana pool over time.                    |
| **Burn**      | Target takes ongoing **HP damage** (fire damage over time).                               |
| **Fear**      | Target briefly **turns and flees** the opposite direction, aborting/losing its action while it runs. |
| **Confusion** | The target's **next ability has a 20% chance to be used on itself**.                      |
| **Stun**      | Target **cannot act** for a short duration — it skips its turn(s) while stunned.          |
| **Knockback** | Target is **shoved back**: in team formats it loses its formation position (pushed to the back line) and its next action is delayed; in 1v1 it interrupts and delays the target's next move. |

**Typical sources (tunable, §13):** Burn ← INT *Ember* / *Inferno*; Blind ← CHA *Discord* (and Maelurk's
innate *Ink Cloud*); Confusion ← CHA *Cacophony*; Fear ← CHA *Screech*; Poison ← DEX *Piercing Shot*.
More skills/abilities can apply statuses as the pool is balanced.

> **Design note:** model a status as `{ kind, magnitude, duration }` on the combatant; the sim ticks it
> each round. Poison hits **mana**, Burn hits **HP** — keep the two damage-over-time channels separate.

---

## 8. Monster Roster

- **4 body types**, **5 base species each = 20 base monsters** at launch.
- Combination is **within the same body type** (matches the breeding rule, §10). Pairings are
  **ordered** (base frame + accent, see §10.1): **5 × 5 = 25** varieties per type — 5 purebreds +
  20 hybrids — × **4 types = 100 total varieties**.
- Presentation is **pixel art** — chosen to keep the art scope small and readable, and to make the
  **appearance-parts** system (swapping parts during fusion) tractable.

### 8.1 Body types & stat leans
The four body types double as the game's main **stat-distribution** lever: each leans toward a
different stat pair, so the starting population spreads across all classes (§6.2) rather than
clustering. (Leans are tendencies/growth bias, not hard caps.)

| Body type  | Stat lean                 | Gravitates to classes like        |
|------------|---------------------------|-----------------------------------|
| Mammal     | Strength / Constitution   | Warrior, Tank, Captain            |
| Avian      | Dexterity / Wisdom        | Ranger, Rogue, Sage               |
| Marsupial  | Charisma / Dexterity      | Orator, Bard, Captain             |
| Aquatic    | Wisdom / Intelligence     | Wizard, Sage, Spellshield         |

The four **primary** leans (STR, DEX, CHA, WIS) are distinct, so no body type duplicates another's
carry stat and **Charisma has a dedicated home** (Marsupial). Constitution and Intelligence appear as
**secondary** leans only (Mammal, Aquatic) — acceptable with just 4 types for 6 stats.

> **Design note:** if appearance is composed of swappable pixel-art **parts** keyed to the genome,
> the 20 base species × part combinations naturally produce the 100 varieties without hand-drawing
> each one. Same-body-type restriction keeps part sets compatible when fusing.

### 8.2 Base species (30 — this section covers the original 20; Insectoid/Reptilian added later, not yet tabled here — see `docs/BESTIARY.md` for all 30)
Five per body type. **Natural class** = the class a fresh purebred emerges into from its two highest
start stats (§6); it can change as the monster trains. Start stats are illustrative (all begin < 50,
per §5) — starting totals are held roughly even (~130) so species differ in *shape*, not raw power.
Format: **STR · DEX · CON · WIS · INT · CHA**.

**Mammal** *(lean: STR / CON)*
| Species    | Natural class | STR·DEX·CON·WIS·INT·CHA | Flavour                          |
|------------|---------------|-------------------------|----------------------------------|
| Kongrath   | Warrior       | 42·20·34·12·10·16       | Silverback gorilla, quiet protector turned fighter |
| Aegisox    | Tank          | 30·14·44·16·10·14       | Armoured ox, immovable wall      |
| Maneleo    | Captain       | 40·22·26·12·12·30       | Lion pride-leader, inspiring     |
| Grivvel    | Rogue         | 34·40·22·12·10·14       | Wolverine brawler, off-lean DEX  |
| Ursath     | Warrior       | 40·14·38·14·10·12       | Great bear, slow but immensely sturdy |

**Avian** *(lean: DEX / WIS)*
| Species    | Natural class | STR·DEX·CON·WIS·INT·CHA | Flavour                          |
|------------|---------------|-------------------------|----------------------------------|
| Skyrend    | Ranger        | 20·44·18·24·28·12       | Raptor, diving ranged striker    |
| Strixil    | Sage          | 10·22·16·42·32·14       | Owl, quiet mana engine           |
| Zephyri    | Rogue         | 28·44·18·20·16·14       | Swift, evasive skirmisher        |
| Corvaan    | Wizard        | 12·26·16·30·40·16       | Sorcerous raven, arcane          |
| Larkessa   | Bard          | 12·34·14·22·16·42       | Songlark, off-lean CHA voice     |

**Marsupial** *(lean: CHA / DEX)*
| Species    | Natural class | STR·DEX·CON·WIS·INT·CHA | Flavour                          |
|------------|---------------|-------------------------|----------------------------------|
| Bruxaroo   | Captain       | 40·28·26·12·10·34       | Boxing kangaroo, charismatic     |
| Koalio     | Orator        | 12·20·18·30·14·44       | Crooning koala, commanding voice |
| Quokkade   | Bard          | 12·36·14·22·14·40       | Beaming quokka, nimble performer |
| Sylvaglide | Ranger        | 12·42·12·24·28·26       | Sugar glider, gliding ranged     |
| Tazzik     | Rogue         | 34·40·24·12·12·20       | Tasmanian devil, ferocious       |

**Aquatic** *(lean: WIS / INT)*
| Species    | Natural class | STR·DEX·CON·WIS·INT·CHA | Flavour                          |
|------------|---------------|-------------------------|----------------------------------|
| Maelurk    | Wizard        | 12·22·18·32·44·14       | Octopus mage, elemental burst    |
| Nautilux   | Spellshield   | 14·12·42·32·20·12       | Nautilus, defensive warder       |
| Serapelle  | Sage          | 12·16·24·44·30·14       | Sea-turtle sage, deep mana       |
| Voltaray   | Ranger        | 14·42·18·22·32·12       | Electric ray, shock skirmisher   |
| Corallux   | Spellsword    | 20·14·36·24·40·12       | Coral crustacean, mage-bruiser   |

All **11 classes are represented** across the 20 purebreds; hybrids (§10.1) fill and blend the rest.

### 8.3 Species lifespans, innate abilities & ultimates
Each species has a **breed lifespan** (the age at which it becomes a Retiree, §9.1), **1–2 innate
abilities** it always starts with (always in effect, don't count against the 3-move loadout, §7.1), and
a **unique ultimate** unlocked at 600 in a stat (§7.3). Further moves are *learned* from the shared pool
via stat milestones (§7.2). Lifespans range **4–6 years**; the intended trade-off is that **longer-lived
breeds grow more slowly**, so their extra seasons partly pay to reach the same ceiling (tuning in §13).

**Mammal**
| Species  | Lifespan | Innate abilities                                                                 |
|----------|:--------:|----------------------------------------------------------------------------------|
| Kongrath | 4        | **Chest Beat** (bonus damage on first melee hit) · **Rising Fury** (melee grows stronger as the fight goes on) |
| Aegisox  | 6        | **Ironclad** (reduces incoming melee) · **Immovable** (resists knockback/displacement)   |
| Maneleo  | 4        | **Rallying Roar** (team attack/morale buff) · **Pride** (stronger while allies stand)    |
| Grivvel  | 4        | **Rend** (attacks cause bleed/DoT) · **Frenzy** (attack speed up at low HP)              |
| Ursath   | 5        | **Thick Hide** (flat damage reduction) · **Maul** (heavy melee crits)                   |

**Avian**
| Species  | Lifespan | Innate abilities                                                                 |
|----------|:--------:|----------------------------------------------------------------------------------|
| Skyrend  | 4        | **Dive Bomb** (high-damage opening ranged strike) · **Keen Eye** (ignores some dodge)   |
| Strixil  | 5        | **Wellspring** (boosts team mana regen) · **Silent Wisdom** (passive mana over time)    |
| Zephyri  | 4        | **Evasion** (high dodge) · **Flurry** (multiple fast strikes)                            |
| Corvaan  | 4        | **Arcane Bolt** (elemental nuke) · **Hex** (lowers enemy accuracy/mana)                  |
| Larkessa | 4        | **Song of Valor** (voice AoE: buffs allies) · **Encore** (repeats last ally buff)       |

**Marsupial**
| Species    | Lifespan | Innate abilities                                                               |
|------------|:--------:|--------------------------------------------------------------------------------|
| Bruxaroo   | 4        | **Haymaker** (big melee blow, stun chance) · **Southpaw** (counter on dodge)          |
| Koalio     | 5        | **Drowsy Aura** (nearby foes grow sleepy/slow) · **Soothing Words** (steadies/heals allies)|
| Quokkade   | 4        | **Cheer** (team dodge/crit buff) · **Quickstep** (evasive)                            |
| Sylvaglide | 4        | **Glide Strike** (ranged hit-and-retreat) · **Aerial** (briefly untargetable)         |
| Tazzik     | 4        | **Devour** (lifesteal on melee) · **Whirlwind** (spinning AoE melee)                  |

**Aquatic**
| Species   | Lifespan | Innate abilities                                                                |
|-----------|:--------:|---------------------------------------------------------------------------------|
| Maelurk   | 4        | **Ink Cloud** (lowers enemy accuracy) · **Tentacle Barrage** (multi-hit elemental)     |
| Nautilux  | 5        | **Ward** (team absorb shield) · **Spiral Shell** (reflects part of magic damage)       |
| Serapelle | 6        | **Tidal Wisdom** (team mana + heal over time) · **Ancient Carapace** (high defence)    |
| Voltaray  | 4        | **Live Wire** (ranged hit, stun chance) · **Static Field** (chips enemy mana)           |
| Corallux  | 5        | **Spellblade** (melee hits add elemental damage) · **Coral Guard** (defence while casting)|

**Ultimate signature moves** (unlock at 600 in a stat, §7.3) — one per species, fills the 4th slot:

| Species (Mammal) | Ultimate            | Species (Avian) | Ultimate          |
|------------------|---------------------|-----------------|-------------------|
| Kongrath         | Silverback Rampage  | Skyrend         | Death from Above  |
| Aegisox          | Aegis Fortress      | Strixil         | Eclipse           |
| Maneleo          | Pride's Roar        | Zephyri         | Thousand Cuts     |
| Grivvel          | Blood Frenzy        | Corvaan         | Doomcaw           |
| Ursath           | Titan's Maul        | Larkessa        | Anthem of Glory   |

| Species (Marsupial) | Ultimate         | Species (Aquatic) | Ultimate        |
|---------------------|------------------|-------------------|-----------------|
| Bruxaroo            | Knockout Combo   | Maelurk           | Abyssal Grasp   |
| Koalio              | Dreamsong        | Nautilux          | Pearl Barrier   |
| Quokkade            | Festival         | Serapelle         | Ancient Tide    |
| Sylvaglide          | Skydance         | Voltaray          | Thunderstorm    |
| Tazzik              | Tasmanian Fury   | Corallux          | Reef Blade      |

> **Design note:** store innate abilities and the ultimate on the species record, and learned-move
> milestones on the genome (§7). All moves are data — effect + trigger + magnitude — so the battle sim
> (§11) and the fusion trait-picker (§10.4) read from one library.

### 8.4 Individuality within a body type
Body type gives shared identity (§8.1); each species is an **individual variation** on it, differing in
three ways so no two feel the same even inside the same type:

1. **Stat signature** — every species deviates from its **body-type average** below. The signature is
   *which stats sit notably above / below that average* (e.g. Ursath is **▲ CON, ▼ DEX/CHA** vs the
   Mammal average — sturdier and slower). Computed by `bodySignature()` in `src/core.ts` and shown on
   each monster card.
2. **Unique innate passives** — the 1–2 innate abilities in §8.3 are species-exclusive and named
   distinctly from the shared learned-move pool (§7.5), so they read as that creature's signature trait
   (e.g. Aegisox's *Ironclad*, Voltaray's *Live Wire*).
3. **Unique ultimate** — one species-only ultimate each (§8.3), unlocked at 600.

**Body-type average stat profiles** (`BODY_AVERAGES` in code) — *STR · DEX · CON · WIS · INT · CHA*:

| Body type  | STR | DEX | CON | WIS | INT | CHA |
|------------|:---:|:---:|:---:|:---:|:---:|:---:|
| Mammal     | 37  | 22  | 33  | 13  | 10  | 17  |
| Avian      | 16  | 34  | 16  | 28  | 26  | 20  |
| Marsupial  | 22  | 33  | 19  | 20  | 16  | 33  |
| Aquatic    | 14  | 21  | 28  | 31  | 33  | 13  |

> When a monster is generated, its stats = species base (already the average + this signature) + small
> individual variance (§10.2) — so even two same-species monsters differ slightly, and every species
> differs meaningfully from its body-type norm.

### 8.5 Elemental affinities
Elemental magic (§5, INT channel) comes in four elements — **fire, water, earth, air**. Each **body type
resists one** element (takes less) and is **weak to one** (takes more). Two mirrored pairs, so every
element is resisted by exactly one body type and exploited against exactly one:

| Body type  | Resists (×0.7) | Weak to (×1.3) |
|------------|:--------------:|:--------------:|
| Aquatic    | 🔥 Fire        | ⛰️ Earth       |
| Avian      | 💨 Air         | 💧 Water       |
| Mammal     | 💧 Water       | 💨 Air         |
| Marsupial  | ⛰️ Earth       | 🔥 Fire        |

*(Insectoid and Reptilian, added later, aren't in this table yet — see `src/core.ts:BODY_ELEMENT` for
the current full set of 9.)*

*Theme:* water douses fire (Aquatic resists fire) but silt/ground unsettles it; wind is a flier's home
turf (Avian resists air) but waterlogged wings ground them fast; grounded beasts shrug off water (Mammal)
but are tossed by gusts; earthbound marsupials shrug off tremors and rockslides (Marsupial resists earth)
but are helpless against fire in dry brush. Multipliers (`RESIST_MULT` / `WEAK_MULT` in `src/core.ts`) are
tunable. Only moves with an `element` (the INT pool, §7.5) trigger affinity; melee/ranged/voice are
non-elemental.

---

## 9. Lifespan, Life Cycle & Retirement

### 9.1 Life cycle
Every monster ages through five stages. The ages below are the **standard ~4-year career**; a monster's
**breed lifespan** (§8.3) shifts the later boundaries — longer-lived breeds spend **more years Fully
Grown** before turning Elder; shorter-lived breeds reach Retiree sooner. The **training malus is by
stage**, not raw age.

| Age (yrs)   | Stage        | Training modifier | Notes                                        |
|-------------|--------------|-------------------|----------------------------------------------|
| 0           | Baby         | — (grows fast)    | Just hatched; very low stats, unlicensed (§10.2) |
| 1           | Teen         | none              | Prime learning years                         |
| 2 …         | Fully Grown  | **−5%**           | Competitive prime; length varies by breed    |
| lifespan − 1| Elder        | **−20%**          | Declining, but still competes                |
| lifespan    | Retiree      | cannot compete    | Must choose a retirement option (§9.2)       |

*Standard breed (lifespan 4): Baby y0 → Teen y1 → Fully Grown y2 → Elder y3 → Retiree y4.*

### 9.2 Retirement
When a monster reaches **Retiree** it can no longer compete, and the player **must** choose one of:
1. **Sell** — convert to money.
2. **Freeze** — preserve its genome for later **combination/fusion**.
3. **Expert Trainer** — keep it on staff. Grants monsters (up to the **highest league the
   trainer attained**) a **small XP bonus**.
4. **Breeding Pen** — pair with another monster of the **same body type** and **opposite sex**
   to produce **combined eggs** (offspring inheriting from both parents).

> **Freezing is available at *any* time**, not only at retirement — a monster can be frozen whenever
> the player chooses (e.g. to bank a strong genome, or pause a career). Retirement is simply the point
> at which a *choice among the four options above is forced*.

---

## 10. Breeding, Combination & Fusion

Breeding and fusion are **two modes of one shared genome operation**, so they reuse the same
inheritance code. A monster's genome has four gene groups:
- **Species genes** — which base species contribute (drives variety + appearance parts).
- **Stat genes** — per-stat base value + growth potential.
- **Trait/ability genes** — a pool of innate traits/abilities, each **dominant** or **recessive**.
- **Seed** — deterministic RNG for milestones, variance, and mutation.

### 10.1 Variety identity (how we reach 100)
Within a body type, offspring **variety** is set by an **ordered species pair** `(baseParent → accentParent)`:
the base parent supplies the **body/frame**, the accent parent supplies **features/coloring**. With 5
species that's **5 × 5 = 25** ordered results (5 purebreds where base = accent, + 20 hybrids) × 4 body
types = **100**. Order mattering (A→B differs from B→A) is what earns the full 100 from only 5 species.
Store this as a per-type **variety matrix** so results are named and deterministic.

### 10.2 Stat inheritance (differs by mode)
A new monster **hatches with very low actual stats and belongs to no league yet** — it must be trained
and licensed from the bottom like any rookie. What breeding/fusion set is the baby's inherited
**potential** (per-stat growth quality + trait/ability pool + appearance), **not** its starting numbers.
Strong parents raise the *ceiling* a monster can eventually reach, not its day-one power.
- **Breeding (egg):** inherited potential = a **blend of the parents with variance** — roughly the
  average of the two parents' potentials, ± a random spread, **nudged toward the body-type lean** (§8.1),
  with a small **mutation** chance to exceed both. Good parents raise the ceiling; every clutch surprises.
- **Fusion (combine):** inherited potential = the **average of the two sources, minus a small penalty**
  (e.g. ~10%, tunable), deterministic. No mutation/upside — fusion **trades a little potential for
  control** over which traits, abilities, and appearance carry over.

Because actual stats always start very low, this cleanly resolves the earlier league-cap question:
high-league parents pass down a **higher ceiling**, never immediate power.

Hatchlings also **inherit learned moves** from their sources (**≥ 1 guaranteed**, §7.4) — so a newborn
enters the world with at least one move despite its low stats.

### 10.3 Traits & abilities
Offspring draw from the **combined parent gene pool**. Each ability has an inheritance chance: **dominant**
genes pass reliably, **recessive** ones need both parents (or luck). Some abilities only surface from
specific pairings, giving breeders combos to chase.

### 10.4 Two modes, same engine
- **Breeding (pen)** — two *living*, **compatible** monsters (same body type, **opposite sex**, both
  able to breed) → **egg** → hatchling (§10.2). Inheritance is **mostly randomised**. **Cheap** (§12) —
  the everyday way to grow fresh competitors and iterate a bloodline across generations.
- **Fusion (combine)** — uses **frozen** genomes (§9; freezing is available anytime) and also produces a
  **hatchling**. The player **deliberately chooses which parts, traits, and abilities** carry over,
  **changing its appearance** and combining/dropping traits; inherited potential is the **average minus a
  small penalty** (§10.2). Directed and low-variance (no sex requirement — it's a graft, not a mating),
  **consumes** the frozen donor, and is **very expensive** (§12) — a deliberate, high-investment play to
  fold a specific build into your next generation.

> **Design note:** "monster = genome + parts + traits/abilities" is the unifying model; breeding and
> fusion are just *random* vs *directed* applications of the same genome-cross. A deterministic
> **seed → genome** generator also lets monsters be generated from arbitrary input.

---

## 11. Battle Model (Auto-Battler)

- Battles are **simulated**, not manually controlled (Teamfight Manager influence: manager, not pilot).
- Player influence comes **before** the fight:
  - **Build:** stats, class, breed, traits/abilities, fusion.
  - **Preparation:** team composition and — in team formats — **explicit tactics and formations**.
    Formations/tactics scale in importance as bigger formats unlock (2v2 → 3v3 → 4v4 → FFA), so the
    tactical layer deepens as the player climbs leagues (see §4.1).
- Damage channels implied by stats: **melee**, **ranged**, **elemental magic**, **non-elemental voice**;
  mitigation via **defence**, **dodge**, **HP**, and **mana** economy.
- Each move resolves against its **accuracy** and **cooldown** (§7.2); moves may deal damage, buff, or
  apply a **status effect** (§7.6). The sim ticks statuses (Burn→HP, Poison→mana) each round.
- **Damage multipliers:** elemental moves scale by the target's **body-type affinity** (§8.5,
  ×0.7 resisted / ×1.3 weak), and all damage a monster deals scales by its **happiness** (§2.5, ×1.00–1.10).
- The sim consumes: monster stats, class, **innate abilities + 3 equipped learned moves + ultimate**
  (§7), team format (1v1…4v4, FFA), chosen tactics/formation, and the active **league ruleset** modifiers.
- **Presentation:** the fight resolves instantly, but the log **plays back turn-by-turn** (~1.5s per
  action) so it reads like a match you're watching — the winner is hidden until the replay finishes, with
  a **skip** to reveal the rest at once (`BattleReplay` in `src/App.tsx`).

---

## 12. Economy & Costs

Money is the throttle on every mechanic — you earn it in the arena and spend it in the stable.

### 12.1 Income
- **Tournament payouts** — the primary source. Prize money scales with **league**, **format**, and
  **placement**; higher leagues and knockouts pay more.
- Secondary (TBD): **selling** monsters (§9), valuables found on **excursions**.

### 12.2 Costs (everything has a price)
| Mechanic            | Cost      | Notes                                                             |
|---------------------|-----------|------------------------------------------------------------------|
| Weekly care         | Low       | Training / rest / excursions — routine upkeep.                   |
| **Feeding**         | Veg → Sweets (cheap→dear) | Buys a food; favourite raises **happiness** → battle damage (§2.5). |
| **Breeding**        | **Cheap** | Needs a **compatible male + female** (same body type, opposite sex). The everyday generational tool. |
| **Fusion**          | **Very expensive** | Directed, consumes a frozen donor — a premium, deliberate play. |
| Freezing / storage  | TBD       | Possible upkeep per frozen genome or stable slot.                |
| Tournament entry    | TBD       | Optional entry fees as a money sink.                             |

### 12.3 Design intent
The wide **cheap-breeding vs. expensive-fusion** gap reinforces the risk/control trade-off (§10.4):
breeding is the accessible, high-volume way to roll for a standout; fusion is a rare, costly move to
**engineer** a specific result once you can afford it. Tournament winnings are what unlock the latter,
tying combat success back into the raising loop.

---

## 13. Areas & Navigation

The game is played across **areas**, reached from a hub. All areas share one **gold** wallet and one
**GameState** (stable of owned monsters, frozen genomes, ranch upgrades, current area).

### 13.1 Town (starting hub)
The starting area. From Town the player enters four locations:

- **Market — buy monsters.** Shows **3 random base monsters** (never fusions). Every base species is
  weighted **equally**, so the offering is truly random. Each has a **purchase price** that **fluctuates
  around a shared base value on a *wider* band than the food market** (≈ ±60% vs food's ±40%). Stock
  refreshes on demand (a Refresh action) / on revisit.
- **Lab — cryogenics & fusion.** Charges a **weekly rental per frozen monster**. Options:
  - **Freeze** — put a monster into stasis (banks its genome, frees a ranch slot).
  - **Thaw** — return a frozen monster to the stable.
  - **Fuse** — combine two monsters into a new hatchling (§10) for a **huge** one-off cost.
- **Ranch** — travel to the Ranch area (the raising loop, §2 / §13.2).
- **Ranch Shop — buy ranch upgrades**, e.g. **bigger barns** (raise stable capacity → keep and raise more
  monsters), **bulk food buying** (stockpile / discount food), and more.

### 13.2 Ranch (raising area)
Home of the weekly loop (§2): the stable, training drills (§2.4), the food market & feeding (§2.5),
excursions, rest, rank-ups, and aging. The **barn capacity** (upgraded at the Ranch Shop) caps how many
monsters the stable holds — the gate for the multi-monster game.

### 13.3 Price bands & costs
| Sink | Scale |
|------|-------|
| Food (§2.5) | ±40% weekly fluctuation |
| **Monster market** | **±~60% fluctuation** around a shared base price (equal for all species) |
| Lab rental | recurring, per frozen monster per week |
| **Fusion** | **huge** one-off |
| Ranch upgrades | one-off per upgrade |

### 13.4 Implementation notes
- One shared **GameState**: `{ gold, stable[], frozen[], barnCapacity, upgrades, area, market }`.
- Monsters bought from the Market are **base, untrained** (equal-weighted species pick via the seeded
  generator). Fusion output is a **baby** (§10.2), so it goes through the Ranch like any hatchling.
- **Open:** market refresh cadence & exact price band; rental amount; fusion price; the full upgrade list
  and prices; whether idle stable monsters age.

---

## 14. Open Questions (to resolve later)
- Exact training math (stat gains, diminishing returns, fatigue/injury curves).
- Elements/types list and matchup chart; how "voice" (non-elemental) interacts with defences.
- Balance the **60-skill pool** (§7.5): per-skill cooldown / accuracy / power / status; each species' ultimate effect; status magnitudes & durations (§7.6); tune `p_base` for hatch inheritance (§7.4); how fusion combines/drops moves.
- Class assignment rule (emergent vs intrinsic) — see §6.
- Species, lifespans, and innate abilities drafted (§8.2/§8.3); still to do: pixel-art part sets, ability magnitudes/triggers, and whether to allow sub-4-year "glass cannon" breeds (needs faster maturation to avoid skipping stages).
- **How low** hatchlings start, and how inherited **potential** maps to per-stat growth (§10.2); confirm the "longer-lived breeds grow slower" trade-off (§8.3).
- Tuning constants: breeding stat-blend spread, mutation rate, **fusion penalty %**, ability odds (§10).
- **Concrete prices** for breeding, fusion, care, freezing, and entry fees; payout curve by league/format (§12).
- Tactics/formation vocabulary (positions, roles, orders) per team format.
- Turn/tick resolution model for the auto-battler; targeting/positioning in team battles.
