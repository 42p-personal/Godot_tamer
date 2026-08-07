# Fun additions — the creative director's proposals

**Written 2026-08-03.** A ranked set of additions and reworks aimed at one question the project
has never asked out loud: *is this game FUN, and where specifically does the fun live?*

⚠️ **THIS IS A PROPOSAL DOCUMENT, NOT A SPEC AND NOT A DECISION.** Everything here is argued
against the vision in `CLAUDE.md` and the doubts in `OUTSTANDING.md` §3. Nothing is agreed.

**Every idea below survives the no-intervention rule.** Anything requiring the player to act
during a fight was cut before it reached this page — see §4.

---

## 0. The thing that comes before every idea on this page

⚠️ **NOBODY HAS EVER WATCHED A FIGHT AND WRITTEN DOWN WHETHER IT WAS ENJOYABLE.**
`OUTSTANDING.md` §3.1, and it is still true. Fight length, damage tiers, focus share and connect
rate are all measured. Enjoyment is not measured at all, and it is the only metric that decides
whether this game ships.

**One person watching ten 5v5 fights and writing down, per fight: (a) could you tell who was
winning, (b) could you tell WHY, (c) did you want to watch the next one — would tell us more
than every idea below.** Several proposals here are expensive, and half of them are cheap if the
answer to (a) is *yes* and unaffordable if it is *no*. Do that first.

I am proposing anyway, because the proposals are the hypotheses the playtest should test.

---

## 0.1 The organising claim — read this before the list

⚠️ **THE UNIT OF ATTENTION IN A 5v5 MUST BE THE SQUAD, NOT THE MONSTER.**

`OUTSTANDING.md` §3.2 asks whether five monsters × four abilities × two innates × statuses is
legible. Asked at the level of the *individual*, the honest answer is no, and no amount of UI
fixes it — twenty simultaneous ability procs is not a thing a human parses, it is a thing a human
watches wash over them.

Asked at the level of the *shape*, it is trivially legible. **"Their wedge broke my left and my
casters got eaten"** is one sentence and a player can see it happen.

So the claim: **every presentation layer in this game — camera, commentary, report, replay,
scouting — should speak in shapes, stations and roles, and should mention individual abilities
only when one of them is the reason the shape moved.** `TACTICS_BRAINSTORM.md` §0 reached the
same conclusion from the agency side. It arrives from the legibility side too, which is a strong
sign it is right.

**This claim is the single highest-leverage creative decision available**, because it decides
what the camera points at, what the commentator says, what the report grades and what the
scouting reveals. Everything in §1 assumes it.

⚠️ **AND IT HAS A COROLLARY THE ENGINE WILL NOT LIKE: reduce simultaneity on purpose.** A fight
where everything resolves continuously has no moments in it. Longer cast commitments, a genuine
approach phase, and deaths as discrete punctuated beats are all *legibility features*, not
pacing polish. `ENGAGEMENT_DESIGN.md` §8 already found the archer's 0.30s root is the least
committed action in the game; that is the same finding from a different direction.

---

## 1. THE FIVE

Ranked. If only one thing on this page is built, build #1.

---

### 1. ⭐ THE READ — the player declares what they think will happen, and the fight grades it

**What it is.** After scouting and before the fight, the game states the player's plan back to
them as a small number of **specific, falsifiable claims**, and the player confirms them. Not
prose — generated from the orders they actually gave:

> **Your read on Ferrick's Brood**
> · Their **Wedge** breaks on my **Box** — my screen holds the middle.
> · **Vex** reaches their **Mender** before it lands two heals.
> · I out-last them: their **Attrition** kit runs dry before my back line does.

After the fight, the battle report grades *those three claims* — ✓ / ✗ / partly — before it says
anything else. Score the read, not the match.

**Why it makes the game more fun.** This is the missing half of "commit, then observe." The
vision's fantasy is *my read was right*, and you cannot feel vindicated by an outcome you never
committed to in words. Right now the player sets seven abstract knobs and then watches a thing
happen; the report tells them what happened. **A declared read converts watching from
consumption into suspense** — the player is not waiting to find out who won, they are waiting to
find out if they were right, which is a much stronger emotion and starts the moment the fight
does.

It also does the legibility work almost by accident: **a claim tells the player where to look.**
If the game has just said "Vex reaches their Mender," the player watches Vex, and a 5v5 suddenly
has a protagonist.

**What it costs.** **Small to medium.** `battleReport.ts:analyzeBattle` already emits
`tacticOutcomes` as ✓/✗ per order plus a `counterRead` — the grading machinery mostly exists. The
new work is (a) generating the claim text from orders + scouting, and (b) promoting it to the
top of the report and the pre-fight screen.

**What it risks.** ⚠️ **A wrong or vague grade is worse than no grade at all** — a ✓ on a tactic
that did not actually decide anything teaches the player a false lesson, and in a game where
preparation is the entire skill, teaching false lessons is the fatal failure. Claims must be
about things the engine can genuinely attribute. **Three specific claims beat ten fuzzy ones.**
And ⚠️ it depends on orders being legible in the first place — it should follow the formation
work, not precede it.

**How it serves the climb.** The climb is a learning curve. This is the feedback signal on that
curve, delivered at the exact moment the player is paying most attention. It is what makes the
tenth cup easier than the first for a reason the player can name.

**Touches:** `battleReport.ts`, the scout/sign-up screens, the post-fight card, and whatever
formation/team-tactics layer lands from `TACTICS_BRAINSTORM.md`.

---

### 2. ⭐ THE CHALKBOARD — re-run the fight with one order changed

**What it is.** After a match, the player may re-run it having altered **exactly one** decision —
one formation, one team order, one loadout slot, one station assignment — and watch what happens
instead. Same seed, same opponent, same everything else.

> *"You lost by 140 HP. What if the Warden had anchored the centre instead of screening left?"*

**Why it makes the game more fun.** ⚠️ **This is the strongest differentiator available to this
project and I am not aware of an autobattler that has it.** The vision says the meta-game is
*advanced training knowledge* — but knowledge has to come from somewhere, and today the only
teacher is trial across an entire career, at one data point per cup. The Chalkboard turns a lost
fight into a **laboratory**, which is the exact fantasy of a tactician.

It also converts the game's biggest technical asset into a *feature*. The sim is pure and
reproducible — that is why the port contract and the goldens work at all. Almost no game can
offer a true counterfactual; this one can, nearly for free, because it already had to be
deterministic for other reasons.

And the psychology is precise: **loss aversion plus autonomy.** A loss you can interrogate is not
a loss, it is a lesson, and the sting of the no-intervention rule ("I could see it going wrong
and could do nothing") is answered *after* the fact without ever breaking the rule.

**What it costs.** **Medium engineering, large design care.** The engine must be re-runnable from
a serialised match input — which `GODOT_MIGRATION.md` says the goldens contract already carries
in resolved form — plus a screen and a diff presentation ("first kill 3.1s earlier; their Mender
died; you win by 90"). The design care is in the limits, not the code.

**What it risks.** ⚠️ **Two real ones.**

1. **It can trivialise the game.** Unlimited re-runs turn a strategy game into brute-force search.
   **Mitigation: it is a resource.** Gate it — a facility the trainer level unlocks, a limited
   number of uses per season, available only after a *loss*, or only on the one order the report
   already flagged as decisive. My preference: **losses only, one axis, one re-run**, and it is
   free. That is a consolation mechanic, not an optimiser.
2. ⚠️ **It will expose the sim's noise, and that is a load-bearing risk.** If changing one order
   swings the result wildly, or if changing nothing at all produces a different fight, the
   counterfactual is a lie and the player will find out inside three uses. **Which makes the
   Chalkboard a test instrument for `OUTSTANDING.md` §3.1 as well as a feature** — if the fight
   is not causally legible, this cannot ship, and the fact that it cannot ship is the diagnosis.

**How it serves the climb.** It is the accelerator on the learning curve. A player who can study
their Iron Cup loss arrives at Gold genuinely better rather than merely stronger — which is the
difference between a climb and a grind.

**Touches:** the Godot engine entry point, match serialisation, a new screen, `battleReport.ts`
(it should nominate *which* order is worth changing), trainer-level unlocks.

---

### 3. ⭐ THE BROADCAST — a director, a commentator, and a highlights mode

**What it is.** Three parts of one system, all driven by a single **drama score** computed over
the `BattleEvent` stream:

- **A director, not a tripod.** The camera cuts to the highest-scoring moment — first contact, a
  flank landing, a monster surviving at 6 HP, the shape collapsing. It does not sit at a fixed
  distance watching ten ants.
- **A commentator.** One templated line at a time, spoken in **squad language** (§0.1): *"The
  wedge is through on the left — and Vex is going straight for their healer."* ⚠️ Football
  Manager's commentary bar is the single most load-bearing legibility device in that entire game,
  and it is text.
- **Highlights mode.** The full fight, an ~20-second highlight cut, or an instant result. The
  same drama score authors the cut.

**Why it makes the game more fun.** Two separate wins.

The first is legibility: **the camera and the commentator are the game telling the player where
to look.** A spectator game that does not direct attention is asking the player to do the
director's job, and they will not.

The second is arithmetic and nobody has costed it: **a career is a lot of fights.** Round-robin
cups run 3–5 matches, across a ladder of eleven leagues and multiple cups per quarter per year.
If every fight must be watched in full — and `ENGAGEMENT_DESIGN.md` cites a 255s sudden-death
backstop — the career is not playable. ⚠️ **Without time compression, the ladder is a chore no
matter how good the fights are.** And time compression is only tolerable if it is *curated*,
which is what the drama score is for.

**What it costs.** **Medium to large, and it is the one that most needs art and audio.** The
drama score itself is small and pure (a scoring pass over an event stream that already exists).
The camera work is real Godot effort. Commentary is a template bank plus authoring, and it is
where a lot of the charm will live or fail to.

**What it risks.** ⚠️ **A director that cuts badly is worse than a fixed camera** — missing the
kill because it was framing a heal is infuriating, and a camera that cuts every 0.8s is
unwatchable. Cut budget and minimum shot length are the two numbers that decide whether this
works. ⚠️ And commentary that repeats itself becomes noise within an hour; the template bank has
to be genuinely wide, or deliberately sparse.

**How it serves the climb.** It makes the climb *survivable* at length and *readable* at depth.
Highlights mode alone may be the difference between a game people finish and one they abandon in
Gold.

**Touches:** everything visual in Godot (none of which exists yet — `OUTSTANDING.md` §1.2), the
event stream, `battleReport.ts` (shared drama scoring), audio.

⚠️ **Build the drama score FIRST and alone.** It is pure, it is testable, it is the input to all
three parts, and it can be validated against a human watching the same fight — which makes it,
usefully, the instrument for §3.1.

---

### 4. ⭐ THE TRAINING PROGRAMME — kill the 30-drill click, keep the 30 drills

**What it is.** Two changes that belong together.

**(a) The player authors a multi-week PROGRAMME, not a weekly pick.** "Eight weeks: strength
focus, rest when stamina drops below 30, premium food while gold holds." The weekly tick executes
it. The game **only interrupts when there is a real decision** — an event, an injury, a plateau,
a breakthrough, a cup entering its sign-up window, a monster refusing.

**(b) Plateau and stimulus.** Repeating the same drill on the same stat produces **decaying
returns**; changing the stimulus resets the decay. A monster that has done Weight Training four
weeks running is bored of it.

**Why it makes the game more fun.** `OUTSTANDING.md` §3.5 asks whether the 30-drill loop is a
game or a chore, and the honest answer is that **it is 30 options presented for what is a
three-option decision** — which stat, how hard, and whether to rest. The information architecture
is inverted: maximum clicks, minimum choice.

**(a) removes the clicking without removing a single decision**, because the decisions were never
in the weekly repetition — they were in the plan and in the interruptions. And the interruptions
become *more* interesting once they are the only thing that stops you, which is a compounding
win with the existing event framework (~45% of weeks already roll one).

**(b) is the bigger idea and it is small to build.** ⚠️ Today, "advanced training knowledge" means
reading the aptitude tag and picking the matching drill. That is a lookup, not knowledge, and the
vision's second fixed point is built on it. A plateau mechanic converts the 30 drills from a menu
into a **rotation puzzle with a hidden state the player learns to read** — which is what a
training sim's depth is actually made of, and it makes the extreme and diverse tiers *tools for a
job* rather than a strictly-better purchase behind an 800g manual.

**What it costs.** **(a) is medium** — a planning UI plus changes to the weekly tick, and
⚠️ `previewWeekEffects` must mirror `applyWeek` byte-exactly, which is the standing trap here.
**(b) is small** — per-monster per-stat decay state and one multiplier, plus the UI to show it,
because an invisible plateau is a bug and not a mechanic.

**What it risks.** ⚠️ **(a) can drain the sense of husbandry.** Monster Rancher's weekly ritual
was part of the bond — you fed the thing, you saw it react. Mitigate by keeping the *feeding*
phase hands-on (it already is, and for a good reason — favourite foods differ per monster) and
automating only the drill. ⚠️ **(b) risks feeling like an anti-fun tax** if the decay is steep;
it should reward variety, never punish focus. A 10–20% decay that recovers is a puzzle; a 50% one
is a wall.

**How it serves the climb.** The climb is dozens of years of weeks. This is the difference
between those weeks being *the game* and being the load screen between cups.

**Touches:** `game.ts` (`applyWeek` / `previewWeekEffects` / `rollDrillGain`), `drills.ts`,
`RanchView` in `App.tsx`, the event framework.

---

### 5. ⭐ THE CROWD — momentum as a reward channel, not a punishment

**What it is.** `ENGAGEMENT_DESIGN.md` §C3 proposes a crowd meter that rises with action and
falls with passivity, escalating the arena when it bottoms out. **I want to keep the meter and
invert the payoff.**

The crowd meter is primarily **the audience's read, made visible** — a diegetic tension gauge
that tells the player, in the language of the fiction, *this is exciting right now*. High crowd
pays out: **gold, fame, sponsor interest, seats filled next time.** Only at the far low end does
it escalate the arena.

**Why it makes the game more fun.** Three things at once, which is why it ranks this high despite
being the least essential of the five.

- **It is the tension curve the fight does not currently have.** A rising bar is a thing a
  spectator can feel. It gives a 5v5 a shape even before the deaths start.
- **It is thematic to the point of being obvious in hindsight.** This is a tournament, in a
  stadium, in front of a crowd. The crowd caring is the most natural mechanic this setting offers,
  and it connects directly to the planned fame-driven crowd fill.
- **As a reward it creates a second axis of play that costs nothing to ignore.** A player who
  wants to grind out attrition wins can. A player who wants to *put on a show* gets paid for it —
  which is a genuine expression outlet in a game that otherwise has none, and it gives CHA and the
  Demagogue/Captain lines a reason to exist beyond their damage tier.

**What it costs.** **Medium.** A new meter with its own balance surface, a visible presentation,
and hooks into the fame/economy systems — which the economy pass is already deliberately waiting
for.

**What it risks.** ⚠️ **The punishment version taxes correct play**, and `ENGAGEMENT_DESIGN.md`
already spotted this: a stall penalty punishes Anchor and Artillery kits for doing their job. That
is why I want it as a reward first. ⚠️ **And a reward channel is a balance surface**: if crowd
gold materially beats placement gold, the game quietly becomes about showboating rather than
winning, and the ladder stops being the spine. **Cap it well below placement rewards.**

**How it serves the climb.** It gives the mid-ladder — where the player has learned the systems
and is grinding league to league — a second thing to get better at, and it makes the venue
upgrade from Wood shed to Apex stadium feel earned rather than reskinned.

**Touches:** the engine (a meter over the event stream), the arena presentation, fame, the
economy pass, `ENGAGEMENT_DESIGN.md`'s anti-stall stack.

---

## 2. STRONG SECONDS

Real ideas, smaller or more dependent. Roughly ranked.

### 2.1 The week-ahead strip — the cheapest retention device available

A permanent strip showing what is coming: *"Wk 34 — Iron Cup sign-ups open · Wk 37 — Vex's
signature awakens (CON 640/700) · Wk 40 — Ferrick entered a Draconic."*

**Why:** "one more week" needs a reason, and a reason is a thing you can see approaching. This is
the goal-gradient effect at near-zero cost, and it makes the calendar — which already generates a
full year of cups — actually *felt*. **Cost: small.** **Risk: none worth naming.**

### 2.2 Earned epithets

A monster earns a title from a deed the engine can detect: *Vex the Unbroken* (survived below 10%
and won), *the Kingmaker* (three fights where its kill was the turning point), *the Glass Spear*
(highest damage, lowest survival). Generated from the event stream, awarded by the crowd.

**Why:** `OUTSTANDING.md` §3.4 asks whether a monster is anything more than a stat block with a
portrait. An epithet is **identity earned in play rather than assigned at generation** — which is
the strongest form of the endowment effect available, and it costs a template table and a
detection pass. **Cost: small.** ⚠️ **Risk:** epithets that everyone gets are worthless; the bar
must be genuinely high and the list must be wide.

### 2.3 The last season, and the farewell

When a monster enters its final year the game says so, the UI marks it, and its last tournament is
framed as such — a name on the card, a line in the report, a place in the Hall.

**Why:** lifespan is this game's emotional engine and it currently expires as a state change.
Retirement to an honours-only Hall (a deliberate and correct cost — see `town.ts`) is a *bill*;
a farewell is a *scene*. Manufacturing the emotional peak costs almost nothing and the pressure
is already built. **Cost: small.** ⚠️ **Risk:** sentiment without substance reads as filler. It
needs one real mechanical beat — a final-season stat floor, or a guaranteed cup slot.

### 2.4 The dynasty made visible

A family tree screen. The line has a name. Each ancestor shows its peak, its epithets, what it
contributed — the potential step it added, the signature it forged, the aptitude it passed.

**Why:** the bloodline is the true meta-character (potential climbs 5% a generation to a 1.5 cap;
signatures inherit dormant and awaken against the ancestor's peak). That is a genuinely elegant
system and it is currently **invisible as a story**. A tree turns a multiplier into a house.
**Cost: small–medium (mostly UI).** **Risk: low.**

### 2.5 Contracts — sponsors that set objectives

Time-bound, accepted deliberately: *"Podium at the Iron Cup with a Reptilian on the roster —
600g."* Gold, a target, and a reason to field a monster the meta would not pick.

**Why:** this is the deferred achievements/goal-gradient work in a diegetic, time-bound shape,
and it does a job nothing else does — **it makes the roster's breadth matter.** With 65 species
and 18 classes, the fastest route is to find the best five and repeat; a contract pays you to
deviate. **Cost: medium.** ⚠️ **Risk:** contracts that fight the ladder are noise. Every one must
be completable *while climbing*, never instead of climbing.

### 2.6 The rival who counter-builds

The rival's roster persists across years — you watch the same monsters improve — and their
breeding and drafting respond to what *you* run. Lose to a Box three times and they start
bringing zone casters.

**Why:** this is the highest form of the meta loop, and it is the only thing on this page that
makes the player's own tendencies visible to them. `town.ts` already carries `Rival`,
personality-to-gameplan mapping and a seated-rival hook, so the scaffolding is standing.
**Cost: medium–large.** ⚠️ **Risk:** an adaptive AI that is invisible is indistinguishable from a
random one. **The adaptation must be announced** — in scouting, in the pre-match preamble, in the
report. If the player cannot see the rival reacting, do not build it.

### 2.7 The monster with a voice

Templated reactions off existing state: refusing a drill at low happiness, showing off after a
win, sulking after a loss to a specific opponent, taking to one food and not another. Not written
narrative — generated beats.

**Why:** Monster Rancher's creatures had personality in the training screen and that is most of
why anyone remembers them. **Cost: small.** ⚠️ **Risk:** it can slide into noise fast; it should
fire rarely and always ride an actual mechanical event.

### 2.8 Aptitude as a ceiling modifier — I endorse `TACTICS_BRAINSTORM.md` §5.2 option D

Not my idea; I want it on the record that I back it. Making major/minor/flaw scale the **cap**
and not just the training rate fixes three things at once — a monster stops being able to max
everything, aptitude stops evaporating as it approaches cap, and ⚠️ **species identity becomes
something the player can feel** rather than a tag they read. That last one is the answer to
`OUTSTANDING.md` §3.4 and no other proposal on this page answers it as directly.

⚠️ **And the standing caution stands:** it reshapes every monster in the game. It belongs in the
deliberate re-baseline, not before it.

---

## 3. BIG SWINGS

Ambitious, expensive, or unproven. Listed because the brief asked for ambition — not
recommended for v1 without argument.

### 3.1 Backroom staff

A head trainer, a scout, a vet, a handler. Wages, specialisms, opinions.

**The weak argument** is that it is a gold sink and a stat modifier. **The strong argument is
legibility:** a head trainer who says *"she's plateaued on strength — try something else"* is a
diegetic tutorial for the hidden-state training game in §1.4, and it is how "advanced training
knowledge" becomes something the game *teaches* rather than something the player is expected to
already have. Staff are the reason a training sim is learnable.

⚠️ **Cost: large, and it is a whole subsystem with its own UI, economy and content.** ⚠️ **Risk:
it makes the ranch a second game**, which the vision explicitly rejects — the ranch is *how you
build the answer*, not a parallel management title. If it ships, it ships as **one hire, the head
trainer, whose only job is to make the training state readable.** That version I would argue for.

### 3.2 Schools of training

The career picks a doctrine at the start — a school that unlocks specific drills, team shapes and
a philosophy. It gives the whole run an identity and a replay axis.

⚠️ **Cost: large, and it fights the design.** Classes here are deliberately *emergent, never
species-destiny*, and a school is a commitment made before you know anything. Attractive, and I
suspect wrong for this game. Noted, not recommended.

### 3.3 Injury and condition as real stakes

Extreme drills can genuinely hurt a monster; recovery costs weeks; the infirmary matters.

**Why it is tempting:** it makes the extreme tier a real gamble and gives the weekly tick teeth.
⚠️ **Why I am wary:** this game already has lifespan pressure, stamina, happiness and a hard cap.
Adding a fourth attrition channel risks a career that feels like managing decay rather than
building a champion, and punitive systems are especially harsh in a game where you cannot
intervene to save the situation. **If it lands, it should be rare, forecastable and survivable.**

### 3.4 A pre-fight prediction market

The crowd, the bookmakers and the rival trainers state odds before the match. Beating the odds
pays; the odds themselves are a scouting tool.

**Why it is interesting:** it gives the player an external, honest read on their own team — which
is exactly the information a preparation game should sell — and it makes an upset *legible as an
upset*, which is one of the strongest emotions a sports game has. **Cost: medium.** ⚠️ **Risk:**
odds are a lie unless the sim can actually estimate outcomes, and honest odds require running the
fight in advance, which is either expensive or a spoiler.

---

## 4. WHAT I WOULD SAY NO TO

Every "no" here protects a "yes" above.

- ⚠️ **No mid-fight intervention in any disguise.** No pause-and-reorder, no timed button, no
  "hero moment," no ultimate the player triggers. It is the vision's first fixed point and it is
  also the only thing that makes preparation matter. Anything that lets the player rescue a bad
  plan makes the plan worthless.
- ⚠️ **No more content in the fight until it is legible.** 141 moves, 18 lines, 18 classes, 65
  species, 4 loadout slots, 2 innates. Six passives are designed and unbuilt; a seventh stat has
  been floated. **The constraint on this game is not content, it is attention.** Adding rules to
  an unreadable fight makes it less readable. This is the project's named failure mode — three
  waves of authored content that never reached a kit — in a new coat.
- **No second currency.** Gold plus time is enough scarcity, and the economy pass has not even run
  once.
- **No content that does not serve Wood → Apex.** The ladder is the spine. For every deferred item
  in `OUTSTANDING.md` §1.4 the question is *"does this make the climb better, or just bigger?"*
- ⚠️ **No unlimited Chalkboard.** If §1.2 ships unbounded it stops being a strategy game.

---

## 5. A possible order

Sequenced by dependency and by what teaches us the most soonest.

| # | item | size | why here |
|---|---|---|---|
| 0 | **Watch ten fights and write it down** | tiny | ⚠️ every item below is a hypothesis until this happens |
| 1 | **The drama score** (pure, headless) | small | input to camera, commentary, highlights AND the report; testable against a human |
| 2 | **Plateau / stimulus** (§1.4b) | small | independent of everything, turns 30 drills into a puzzle today |
| 3 | **Week-ahead strip** (§2.1) | small | cheapest retention win on the page |
| 4 | **Highlights mode + commentary** (§1.3) | medium | the career is unplayable at full length; do this before the camera |
| 5 | **The Read** (§1.1) | small–med | needs the formation/team-order work to have something legible to claim |
| 6 | **The training programme** (§1.4a) | medium | bigger UI job; the plateau work informs it |
| 7 | **The camera director** (§1.3) | medium | needs a battle scene to exist at all |
| 8 | **The Chalkboard** (§1.2) | medium | needs a stable engine and a serialised match; the payoff is largest |
| 9 | **The crowd** (§1.5) | medium | rides the economy pass and the arena rebuild |

⚠️ **Items 1, 2 and 3 can start now.** None of them depend on the spatial rework, the formation
system or anything that renders.

---

## 6. Where the disciplines disagree

**Balancing:** *"Three of the five have a balance surface — crowd payouts, plateau decay,
contract rewards — and the baseline is suspended. I can't tell you whether any of them are tuned
right and I won't be able to until the re-baseline lands. Ship the ones that are pure
presentation first: the drama score, the commentary, the Read. Those cannot move a number."*

**Game mechanics:** *"The Chalkboard is the one that scares me, and not for the reason stated. A
counterfactual demands that one changed order produces one comprehensible difference — that is a
statement about the sim's sensitivity, and nobody has measured it. Run the experiment headless
before anyone builds a screen: same fight, one order flipped, forty times. If the outcome
distribution is a coin flip, we have learned something much more important than whether this
feature is fun."*

**Art & design:** *"Everything in §1.3 is mine and none of it exists — there is no battle scene,
no camera, no unit node. I would rather have a fixed camera on a fight I can read than a
director cutting around a fight I can't. And the crowd meter is the first mechanic on this page
that gives the stands a reason to be modelled, which makes the venue-versus-ground split real
instead of a note in a doc."*

**QA:** *"The Read is a grading system, which means it can be WRONG, and a wrong ✓ is worse than
no report at all. Every claim it can generate needs a fixture proving the grade matches what the
event stream actually shows. Same for epithets — 'the Unbroken' awarded to a monster that was
never below half health is the kind of bug players screenshot."*

⚠️ **All four point the same way: build the pure, headless, testable pieces first — the drama
score, the plateau, the grading logic — and let the presentation follow them onto an engine that
does not exist yet.**

---

## 7. The open questions I could not answer from the docs

1. **How long should a fight be?** Nobody has stated a target. It decides the camera, the
   commentary density, the crowd meter's curve and whether highlights mode is optional or
   mandatory. My instinct is **45–75 seconds for a 5v5** with the 255s clock as a genuine
   emergency backstop, but that is an instinct.
2. **How many fights does a full Wood → Apex career contain?** ⚠️ **Nobody appears to have
   counted, and it is the number that decides whether §1.3's compression is a nicety or a
   blocker.** It is arithmetic over the calendar generator and it should be worked out this week.
3. **Is the player meant to run one monster at a time or a stable of ten?** The barn cap, the
   lab, breeding and the 5v5 team size all pull in different directions, and the answer changes
   whether §1.4's programme is a convenience or the only way the game is playable.
4. **Does the player ever lose a monster to something other than age?** The stakes answer
   depends on it, and §3.3 lives or dies on it.


---

## APPENDIX — "How many fights is a full career?" MEASURED 2026-08-03

The Creative Director flagged this as the arithmetic that decides whether highlight compression
is a nicety or a blocker. **Nobody had ever run it.** Probed over 8 game years against
`tournamentCalendarFor`, seed `career-probe`, assuming a 4-rival round robin (midpoint of the
3-5 band):

| league | cups | matches | team size |
|---|---|---|---|
| Wood | 50 | 200 | 1 |
| Copper | 49 | 196 | 2 |
| Tin | 44 | 176 | 2 |
| Bronze | 39 | 156 | 3 |
| Iron | 42 | 168 | 3 |
| Silver | 46 | 184 | 4 |
| Gold | 45 | 180 | 4 |
| Platinum | 44 | 176 | 5 |
| Masters | 23 | 92 | 5 |
| Tamer Elite | 21 | 84 | 5 |
| Tamers Apex | 24 | 96 | 5 |
| **TOTAL** | **427** | **1,708** | — |

**1,708 matches available across 8 years — about 214 per year.**

⚠️ **THIS IS MATCHES AVAILABLE, NOT MATCHES REQUIRED.** A career enters a subset, so the
figure is an upper bound rather than a playthrough length. But the shape of the answer is what
matters: **a Wood-to-Apex climb is measured in HUNDREDS of battles, not dozens.**

⚠️ **SO COMPRESSION IS A BLOCKER, NOT A NICETY — the Creative Director's ranking of it is
CONFIRMED by measurement.** At the old ~23s median, even 200 watched fights is over an hour of
pure battle-watching with no interaction, in a game whose central verb is watching. Every fight
being individually excellent does not save that; it is a volume problem, and volume problems are
solved by curation.

⚠️ **AND IT SHARPENS THE OPEN QUESTION ABOUT FIGHT LENGTH.** Fight duration is not just a
pacing knob — it multiplies by a number in the hundreds. Shaving 5 seconds off a median fight is
worth ~15 minutes across a climb. That reframes duration as a *career-length* decision rather
than a *combat-feel* one, and it should be decided with this table in view.

Note also the **half-density top three** (Masters 23, Tamer Elite 21, Apex 24 cups vs 39-50
below): the ladder already thins deliberately at the summit, which is the right instinct. The
crush is in the Wood-to-Gold teaching band, which is exactly where a new player is least
equipped to enjoy 200 fights.
