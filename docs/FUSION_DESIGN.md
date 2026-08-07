# Fusion & Breeding — Design Draft (v0.6+, chunk B)

Draft for approval. Grounds the two endgame systems in distinct fantasies, then
specs the first of three new fusion classes. Numbers are proposals, tunable.

## Town UI restructure (user, 2026-07-23) — hub of clickable locations
Replace today's long stacked-card Town with a compact **hub screen** (town-map
feel): a persistent top bar (gold / date / trainer level) + location buttons,
each opening a focused sub-screen. Proposed locations:

| Button | Opens | Contents |
|---|---|---|
| 🛒 **Market** | Market screen | buy monsters, licenses, Ranch Shop (comfort set, extreme manual, barn), food contracts |
| 🏟 **Stables** | active roster (today's Ranch) | your competing monsters — train, feed, plan, Advance Week (the main loop) |
| 🐎 **Breeding Ranch** | the stud farm | breeding stock (champions sent to stud) live here; **Breed** two → dynasty child; stud income |
| 🏡 **Retirement Ranch** | pensioners | retired monsters earning passive gold, weekly income totals |
| 🧪 **Lab** (kept) | genome/fusion facility | **Freeze** (send champion to stud), **Fuse** (two → fusion species), lab slots, Stud Books, lab-tech upgrades |

OPEN BOUNDARY to confirm: the Lab and Breeding Ranch both touch breeding stock.
Proposed split — **Lab = the machinery** (freeze a champion into the stud farm,
fuse two into a new species, slot capacity), **Breeding Ranch = the living farm**
(view the studs, breed them, collect stud fees). The frozen roster is shown in
both, in their respective context. Confirm or reassign.

## The canonical game loop (user, 2026-07-23)
Buy two starter monsters → win cups for gold → buy stable space + more monsters →
raise champions → at end of career, each champion either **draws a pension**
(passive income) OR is **sent to the stud farm** (breeding stock) to found a
**dynasty** built on that champion. Fusion is a parallel, pricier option: feed
two lesser monsters in for one powerful new fusion-species specialist.

## The core split — two different fantasies

| | **BREEDING** (built, chunk A) | **FUSION** (this draft) |
|---|---|---|
| Fantasy | Continue a dynasty | Create something new |
| Inputs | 2 frozen legacies (**preserved**) | 2 frozen legacies (**consumed**) |
| Result | Same species as parent A | A brand-new **fusion species** |
| Starting stats | ~35% head start from parents | Low-to-modest (climbs via dual-major training) |
| Growth | Potential ceiling (+10%/gen, cap 1.5) | **Dual +20% majors**; gen-1 capped at Platinum, breed to lift the wall |
| Ceiling | Tamer Elite (via generations) | Platinum at gen-1 → **Tamer Elite once bred (gen-2+)** |
| Unique reward | Bloodline boons + hidden 3rd innate | Species **signature skill** (exclusive move) |
| Feel | Safe compounding | Births a new bloodline; breed it up |

The one-line separation: **breeding keeps a champion's strength and compounds it;
fusion spends two champions to birth a new species — a fast-training, uniquely-
skilled specialist that's capped at Platinum until you breed the line to the top.**
The two systems CHAIN: fusion creates the bloodline, breeding elevates it.

## Fusion mechanics (REVISED 2026-07-23 — Platinum cap + downfall, no train buff)

Balance principle: **fusion is a strong mid-upper-league SPECIALIST with a hard
ceiling, not a path to the top.** The dynasty (breeding) is the ONLY way to
reach Masters/Tamer Elite. Fusion is powerful but terminal — an "instant gotcha"
is prevented by two structural downfalls, not by making it weak.

- **Recipe = the two parent BODY TYPES.** Only 3 canonical pairs are valid;
  any other pairing = "no known fusion for this pairing" (recipes feel like
  discoveries). Each pair yields one of the 3 new fusion CLASSES:

  | Fuse | New class | Element (resist→weak) |
  |---|---|---|
  | Mammal + Reptilian | **Saurian** | earth → air |
  | Avian + Aquatic | **Tempestine** | air → fire |
  | Marsupial + Insectoid | **Broodkin** | water → earth |

- **Which of the class's 5 species you get — decided by the parents' stats.**
  Each of the 5 species in a class has a two-stat identity (its role): e.g.
  Grendscale=STR/CON, Vipramane=DEX/STR, Thornhide=CON-wall, Runewyrm=WIS/INT,
  Basilroar=CHA/STR. On fusion: sum the two parents' stats, take the dominant
  stat(s), and select the class species whose identity best matches. Fuse two
  bruisers → Grendscale; a fast pair → Vipramane; two casters → Runewyrm; a
  face/support pair → Basilroar. Deterministic tiebreak by a fixed stat priority
  (STR>CON>DEX>WIS>INT>CHA) so the result is always predictable. **You steer the
  outcome by choosing which legacies to sacrifice** — that's the strategy, and it
  makes every one of the 5 reachable on purpose.
- **Off-recipe pairs are INVALID** — fusing two body types that aren't one of the
  three canonical pairs shows "no known fusion for this pairing." The three
  recipes are discoveries, and each stays meaningful.
- **Starting stats: a MODERATE inherited base** (~40% of the parents' averaged
  stats). Capable, not dominant — worth two sacrificed legacies without being an
  instant win. (Revised from "start low": with no training buff, a low start
  wouldn't justify the cost.)
- **Training aptitude — DUAL MAJOR (the fusion signature).**
  - **Two +20% majors — PER SPECIES**, authored to match that species' role
    (Grendscale STR+CON, Runewyrm WIS+INT, …). This is the fixed class-species
    identity: every Grendscale trains STR & CON fast.
  - **+10% minor and −10% flaw — PER MONSTER**, rolled at fusion time on stats
    that aren't its two majors. So two Grendscales are individuals — one might
    have a CHA minor, another a DEX minor — stored on the career, not the species.
  - (Normal species: one +20% major, +10% minor, −20% flaw. Fusion: TWO +20%
    role majors + a rolled +10%/−10% pair — stronger trainer, gentler flaw.)
- **⛔ GEN-1 STAT CAP = Platinum (800).** A freshly-FUSED monster (generation 1)
  is hard-capped at Platinum-grade stats — it cannot be trained to Masters (900)
  or Tamer Elite (1000) budgets. Strong specialist for the climb up to Platinum,
  not a top-tier finisher on its own.
- **✅ BREEDABLE — and this is the intended arc.** Fusion monsters breed normally.
  Breeding a fusion line raises potential like any bloodline, which LIFTS the
  Platinum wall: **a gen-2 fusion (bred from fusion parents) is fully capable of
  Tamer Elite.** `statCapFor`: gen-1 fusion → `min(leagueCap, 800)`; gen-2+
  fusion → `leagueCap × potential` (normal, no wall). Fusion CREATES a new
  bloodline of a unique species; breeding ELEVATES it to the summit.
- **Starting stats — around TIN-league strength** (not wild-low). A fresh fusion
  hatches already mid-league competitive: major stats ~150–200, others lower,
  derived from the parents' averaged stats but landed in the Tin band. A real
  head start above wild, well below its Platinum gen-1 cap — immediately usable,
  and the dual-major training carries it up from there.
- **Upside that justifies the cost:** dual-major training + strong innates + an
  exclusive **signature skill** (phase 2) + the start of a brand-new bloodline
  you can breed all the way to Tamer Elite.
- **Cost: 1000g** + both legacies CONSUMED + the Special Breeding License (800g).
  Deliberately steep — the reward is powerful and the two monsters you feed in
  are NOT meant to be your champions (you fuse fodder into one strong specialist;
  you breed your champions to found a dynasty). Fusion is the pricey option.
- **Career span:** 6 years.

### Why this is balanced (not a gotcha)
- A FRESH fusion (gen-1) can't win the top two leagues — Platinum is its wall.
  Reaching Tamer Elite means breeding the fusion line over generations (time +
  frozen legacies + gold), exactly like any dynasty.
- Dual-major fast training only reaches the Platinum cap FASTER; it can't exceed
  the cap. Speed ≠ ceiling.
- Net: **fusion births a powerful new bloodline (capped at Platinum for gen-1);
  breeding carries that bloodline to the summit.** The two systems chain instead
  of competing — fusion → breed → Tamer Elite.

### Signature skills (fusion phase 2 — flagged, not blocking)
Each fusion species learns ONE exclusive signature move no other monster can
equip. Requires extending the move system with species-gated moves (today moves
are purely stat-derived from the 90-pool). Ships AFTER the species themselves so
art/stats aren't blocked on an engine change.

## The retirement fork — pension vs. stud farm (RECOMMENDED, pending confirm)

When a champion's career ends, it faces ONE fork, and the choice should be
weighty — so the stud farm is a **one-way, permanent destination**:

- **Pension** — the champion stays in your stable as a retiree, drawing passive
  gold for the rest of the game (uses a barn slot; can NEVER breed).
- **Stud farm** (the breeding stable = today's Lab, renamed) — the champion is
  sent to found a dynasty. It can be a breeding parent, but earns NO pension and
  does NOT return to the stable. **Breeding IS the end of its earning life.**

Why one-way: if a stud could freely come back to a pension, "send to stud" would
strictly dominate (dynasty now, income later) and the fork would be fake. The
one-way rule makes it a genuine **income-now vs. legacy-later** decision — which
is the heart of the loop above.

Lifecycle detail: a stud that has used all its breeding slots becomes a spent
sire/dam. You may **release** it (frees the stud-farm slot, monster is gone) —
but it does NOT convert back into a pensioner. Want the pension? Don't send it to
stud. (This replaces today's freeze→thaw-to-retiree path, which was the free
round-trip that would undercut the decision.)

Implication for the build: the current `thaw` (frozen → back to stable as a
retiree) is removed/repurposed; freezing = "send to stud" is the permanent move.

## Breeding additions (the other half of the split — small, chunk A follow-on)
- **Bloodline boons:** +1% damage per generation, capped +5% — a bred champion
  is quietly tougher than a wild one of equal stats.
- **Hidden bloodline innate:** at generation 3+, a bred monster unlocks a THIRD
  innate slot drawn from a small bloodline-only pool — dynasties get something
  fusion never does, mirroring fusion's signature skills.

---

## BUILD STATUS
- **Saurian — BUILT & CORRECTED (v0.7, 2026-07-23).** Rebuilt to the corrected model
  after the first attempt diverged. FINAL mechanics:
  - **Lab freezer** — a SEPARATE stasis pool (`g.labFrozen`/`g.labSlots`, expandable
    from Ranch Shop), distinct from the Breeding Ranch stud farm (renamed
    `labCapacity`→`studSlots`). Freeze any active monster (aging paused); thaw back;
    Elder Tonic usable on frozen monsters.
  - **Fuse two lab-frozen** (right body pair, e.g. Mammal+Reptilian → Saurian), 1000g,
    both CONSUMED. **All stats start at 100** (parent stats irrelevant). Aptitude
    INHERITED per-monster: **+20% on each parent's major** (`bonusMajor1/2`) + a rolled
    **+10% minor / −10% flaw**. Species = **spinning wheel** (random of the 5). Potential
    **×1.075 (1½★)**, gen-1 Platinum-capped, then fully breedable (gen-2 ≈ 3★, TE-capable).
  - 5 Saurian species are aptitude-neutral shells (`trainingProfile: {}`) — innates + look only.
  - Sim-verified (8-check corrected sim: freeze/thaw, wheel determinism, all-100 start,
    inherited majors +20% / minor+10% / flaw−10% via training preview, Platinum cap,
    tonic-on-frozen, lab expand) + goldens intact + design validation + live browser
    (Lab freezer + freeze/thaw). **SPRITES: placeholder (Reptilian grid) — real art
    needs the image pipeline.**
- Tempestine — not started. Broodkin — not started.

## CLASS 1 — Saurian (Mammal + Reptilian) · element: resist earth, weak air

Warm-blood fury fused with cold-blood armor: scaled beasts, maned horned
serpents, tusked plated titans. A full self-sufficient spread (one per combat
role) so the class stands alone as a team. Stats are `s(STR,DEX,CON,WIS,INT,CHA)`,
totals ~124–132 to match the exclusive tier. Career span 6y.

1. **Grendscale** — *Warrior* · `s(40,18,36,12,10,14)` — a silverback-saurian,
   scaled and maned with curved horns. Major STR, flaw INT.
   Innates: **Scaled Hide** (−2 damage taken per hit) / **Primal Roar**
   (Enemies: −4% damage dealt).
   Art: a hulking gorilla-bodied beast plated in overlapping earth-brown scales,
   a lion-like mane, two backward-curved horns, mid-roar chest-beat.

2. **Vipramane** — *Rogue* · `s(30,38,20,12,14,12)` — a serpentine striker with a
   bristling mane and horned brow. Major DEX, flaw WIS.
   Innates: **Serpent's Strike** (+35% damage on first hit, +4% crit) /
   **Mane Bristle** (+7% dodge).
   Art: a long low serpent-cat, scaled coils with a feathered-look mane running
   the spine, short horns, coiled mid-lunge.

3. **Thornhide** — *Tank* · `s(28,12,44,18,10,12)` — a tusked, plate-scaled
   low-slung wall. Major CON, flaw DEX.
   Innates: **Thornplate** (attackers take 15% of the damage they deal) /
   **Ironscale** (−2 damage taken per hit).
   Art: a heavy quadruped armored in thick keeled scale-plates, curved tusks, a
   spiked ridge, braced and immovable.

4. **Runewyrm** — *Sage* · `s(16,16,20,36,32,12)` — a horned serpent-scholar,
   scales etched with glowing runes. Major WIS, flaw STR.
   Innates: **Runic Wisdom** (+2 mana regen/turn; +magic damage) /
   **Petrifying Gaze** (8% chance to Stun on hit).
   Art: a slender coiled serpent with a fur ruff and antler-like horns, rune-lit
   scales, an ancient watchful posture.

5. **Basilroar** — *Orator* · `s(28,18,22,14,12,34)` — a maned basilisk whose
   bellow rattles a battlefield. Major CHA, flaw INT.
   Innates: **Dread Bellow** (Enemies: −5% accuracy) / **Rally Cry**
   (Team: +5% damage).
   Art: an upright crested basilisk with a broad lion's mane and a frilled
   throat mid-bellow, scaled and horned.

## CLASS 2 — Tempestine (Avian + Aquatic) · element: resist air, weak fire
Feather-and-fin storm creatures — sky and sea fused into living weather. Career 6y.
Two majors per species shown as [A+B].

1. **Thunderoc** — *Ranger* [DEX+STR] · `s(30,36,20,12,14,12)` — a finned
   thunderbird raptor. **Chain Lightning** (8% Stun on hit) / **Storm Dive**
   (+35% damage on first hit).
   Art: a great storm-raptor, wings edged with fins, crackling feathers, mid-dive.
2. **Galewing** — *Rogue* [DEX+CHA] · `s(20,38,16,16,12,26)` — a scaled sky-ray
   gliding on gusts. **Wind Veil** (+8% dodge) / **Squall** (Enemies: −3% accuracy).
   Art: a manta-ray body with feathered wing-fins, banking on a gale.
3. **Tidecaller** — *Sage* [WIS+CON] · `s(16,18,26,36,20,14)` — a monsoon
   heron-mage. **Tidal Grace** (Team: +2 HP regen) / **Deluge** (Team: +1 mana regen).
   Art: a tall heron with scaled fin-plumes, robed in rain, staff-like beak.
4. **Maelstrom** — *Wizard* [INT+WIS] · `s(14,20,16,30,38,10)` — a storm-serpent
   caster. **Overcharge** (+7% damage) / **Static Field** (6% chance to cast twice).
   Art: a coiling sky-serpent wreathed in a spiralling squall, finned crest.
5. **Brinehowl** — *Orator* [CHA+WIS] · `s(22,16,20,26,12,32)` — a storm-petrel
   serpent whose cry summons squalls. **Gale Cry** (Enemies: −5% accuracy) /
   **Rally Squall** (Team: +5% damage).
   Art: a crested petrel-serpent, throat flared mid-shriek, spray on the wind.

## CLASS 3 — Broodkin (Marsupial + Insectoid) · element: resist water, weak earth
Pouch-and-chitin brood-carriers — armor and swarm, nurture and numbers. Career 6y.

1. **Chitinhop** — *Tank* [CON+STR] · `s(30,14,42,12,14,12)` — a chitin-plated
   hopper. **Carapace** (−2 damage taken per hit) / **Counter-Spines** (Thorns 15%).
   Art: a heavy kangaroo-shape sheathed in beetle-plate, powerful hind legs braced.
2. **Broodmother** — *Sage* [WIS+INT] · `s(14,14,22,34,32,14)` — a hive-mother.
   **Brood Tend** (Team: +2 HP regen) / **Hive Mind** (Team: +1 mana regen).
   Art: a rounded matron with a chitinous brood-pouch aglow with eggs, gentle.
3. **Mantiskin** — *Rogue* [DEX+STR] · `s(32,36,18,12,16,10)` — a mantis with a
   brood-pouch. **Ambush Fold** (+35% damage on first hit) / **Blade Arms** (+4% crit).
   Art: an upright mantis-marsupial, scythe-arms folded, pouch at the belly.
4. **Resinback** — *Tank* [CON+WIS] · `s(24,12,40,24,14,12)` — a resin-armored
   digger. **Resin Plate** (−2 damage taken per hit) / **Sap Ward** (reduces magic damage).
   Art: a burly digger caked in amber resin-armor, broad claws, low stance.
5. **Swarmherd** — *Orator* [CHA+INT] · `s(20,18,22,16,26,26)` — a swarm-shepherd.
   **Command Swarm** (Team: +5% damage) / **Disorient** (Enemies: −4% dodge).
   Art: a lean herald flanked by a drifting insect cloud, pouch of hatchlings.

## Decisions — RESOLVED (2026-07-23)
1. ✅ Two +20% majors PER SPECIES (role-matched); +10% minor / −10% flaw rolled PER MONSTER.
2. ✅ Starting stats around Tin-league strength (not wild-low).
3. ✅ Names approved (all 15).
4. ✅ Species-within-class decided by parents' combined stats (deterministic tiebreak); off-recipe INVALID.
5. ✅ Signature skills PARKED → task #112 (broader "more learnable skills" pass, after the species ship).
6. ✅ Fusion monsters ARE breedable; gen-1 capped at Platinum, gen-2+ (bred) reaches Tamer Elite.

## Build order (data first, art last — art is the expensive, approval-gated step)
Per class, one at a time — **Saurian → Tempestine → Broodkin**:
1. Species data (stats, dual-major profile, innates + INNATE_EFFECTS keys, lore, element pair, bestiary bio)
2. Fusion mechanic (recipe→species selection, Tin-start, per-monster minor/flaw roll, consume legacies, license gate)
3. `statCapFor` gen-1 Platinum cap / gen-2+ lift; breeding a fusion line; validator updates
4. Fusion UI (separate from Breed); verify (tsc/tests/sims/browser)
5. Sprite art (15 total) — LAST, on approval

## Also needed (engine, before/with class 1)
- Per-monster aptitude override (`bonusMinor`/`bonusFlaw` on Career) so the rolled minor/flaw work atop the species dual-major.
- New BodyType values (Saurian/Tempestine/Broodkin) + BODY_ELEMENT entries (earth→air, air→fire, water→earth).
