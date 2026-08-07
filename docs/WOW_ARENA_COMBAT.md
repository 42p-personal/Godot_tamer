# World of Warcraft Arena — combat mechanics, and what transfers to a zero-intervention autobattler

**2026-08-06.** Companion to `WOW_ARENA_REFERENCE.md` (maps) and `ARENA_ETHOS_REVIEW.md` /
`ARENA_SCALE_COMPARISON.md` (scale). Those cover the STAGE. This covers what actually happens on
it — the action economy, interrupts, CC/DR, burst windows, roles, and positioning-as-skill — and
then the part that matters for us: which of it can survive a player who never touches the fight
once it starts.

⚠️ **SOURCING CAVEAT — READ BEFORE CITING ANYTHING BELOW.** This session had no web-access tool
(no WebFetch/WebSearch was available), so nothing here was fetched or verified live against
Wowpedia/warcraft.wiki.gg/Blizzard blue posts during authoring, despite that being the brief.
What follows is drawn from established, broadly-stable WoW PvP knowledge (the kind repeated
consistently across Wowpedia, Icy Veins/Method-style guides, and years of Blizzard's own PvP
tuning posts) up to this model's training cutoff (January 2026). Two things follow from that:

1. **Structural claims are solid.** The GCD exists, casts are interruptible, DR halves and
   resets, trinkets exist, comps have roles — this is bedrock WoW design that has been true,
   in shape, since TBC-era arena and is not seriously in dispute anywhere.
2. **Exact numbers are era-dependent and NOT independently verified this session.** WoW has
   re-tuned GCD floors, interrupt lockout durations, DR reset timers and trinket cooldowns
   repeatedly across 20 years of expansions. Where a specific number is given below it is
   marked with the era it's commonly associated with and flagged ⚠️ UNVERIFIED THIS SESSION.
   **Before anyone treats a specific number as a design input, it should be checked against a
   current source** (Wowpedia's "Diminishing returns" and "Global cooldown" pages, or Blizzard's
   PvP tuning posts) — this doc is a structural reference, not a numbers-verified one.

Per the project's standing rule (`CLAUDE.md`): a confident wrong number is worse than an admitted
gap. Treat every ⚠️ below as "reason from this, don't cite it as fact."

---

## 1. The action economy

**Global Cooldown (GCD).** After using almost any ability, a short universal lockout prevents
using *another* ability (not the same one — a different cooldown system handles that). This is
the single most load-bearing rhythm mechanic in WoW combat: it caps how many discrete decisions a
player can make per second, regardless of how many abilities are off cooldown.
- Base GCD is commonly cited as **1.5 seconds**, reduced by the player's Haste stat down to a
  floor. ⚠️ UNVERIFIED THIS SESSION — the floor itself has moved between expansions (values as
  low as 1.0s and as low as 0.75s for some specs/eras have been cited in different periods); do
  not treat either number as current without a check.
- Some abilities are explicitly **off the GCD** (defensive cooldowns, some utility) — these are
  the tools a player can use *in addition to* their GCD-gated action that second, which is part
  of why defensive cooldowns feel like "free" reactions rather than competing for the same slot.

**Cast times.** WoW's spell cast times occupy a real spread, and the spread is the point — it is
the axis that separates "instant, always available" from "a commitment the enemy can see and
punish":
- **Instant (0s)** — resolves on the GCD with no further exposure. Most melee abilities, many
  utility spells, some direct-damage spells (often at a damage discount vs. their cast-time
  sibling, e.g. instant-cast versions of a spell historically hit for less than the cast-time
  version).
- **Short cast (~1.0–1.5s)** — barely longer than the GCD itself; a caster can only be
  meaningfully interrupted here if the interrupt is already lined up.
- **Medium cast (~2–2.5s)** — the most common band for "real" damage/heal spells across most of
  WoW's history (examples widely cited: Fireball, Flash Heal-tier spells). Long enough that a
  watching opponent has a real reaction window.
- **Long cast (~3s+)** — reserved for the biggest single hits and the biggest heals (examples
  widely cited historically: Frostbolt at 3s in classic-era tuning, Greater Heal at 3s,
  Pyroblast at 4.5s pre-haste in classic-era tuning). ⚠️ UNVERIFIED THIS SESSION, and these
  specific spells have been retuned repeatedly across expansions — treat only the *band*
  (3s+ exists and is reserved for high-commitment casts) as reliable, not the specific numbers.
- **Channelled spells** — the inverse commitment: damage/healing ticks *while the cast bar
  runs*, so partial value is banked even if interrupted partway (unlike a hard cast, which
  banks nothing on interrupt). This is a deliberate risk-shape difference within "spells that
  take time," not just a flavour distinction.

**How much of arena skill is time management.** A large fraction of what separates a good WoW
arena player from a mediocre one is *not* mechanical execution but **timing decisions against a
shared, visible clock**: don't cast into a kick window, don't waste a GCD on a Block-equivalent
when a burst window is open, hold an instant so a kick whiffs on nothing. The GCD means every
choice has an opportunity cost measured in real seconds the opponent can also see ticking. This
is the deepest mechanical fact about WoW arena and the hardest one to reproduce without a live
clock both sides can read and react to.

---

## 2. Interrupts and counterplay

**The interrupt kit.** Most classes carry a dedicated interrupt (examples: Rogue's Kick, Warrior's
Pummel, Mage's Counterspell, Shaman's Wind Shear, Paladin's Rebuke, Priest's Silence as a
spell rather than a melee interrupt). Interrupting a cast:
- Stops the cast immediately (the caster gets **nothing** — contrast with a channel, which banks
  partial value).
- Applies a **lockout** — the caster cannot cast (sometimes just in that spell's school, sometimes
  a mix depending on class/era) for a duration. ⚠️ UNVERIFIED THIS SESSION — lockout duration and
  whether it's single-school vs. broader has changed repeatedly (Counterspell's classic-era
  cross-school lockout was famously long and was cut down significantly in later expansions);
  treat "an interrupt produces a real, multi-second punishment window" as the reliable claim, not
  a specific duration.
- Most interrupts themselves have a cooldown, and most cost the *interrupter* a GCD and a
  positioning commitment (melee interrupts require being in melee range) — so interrupting is not
  free either; it's a trade of the interrupter's own action economy against the caster's.

**A caster's counterplay to being interrupted** (this is the actual skill expression, and it's
almost entirely about denying information or bait/timing, not raw power):
- **Bait the interrupt on a cheap spell**, then follow with the real cast once the interrupt is
  on cooldown.
- **Break line of sight (LOS)** mid-cast-decision, using a pillar — forces the interrupter into
  melee range or denies them the read entirely (you can't interrupt what you can't see/target).
- **Use instants** during the interrupt's cooldown window instead of casts.
- **Have a healer/teammate bait or soak the interrupt** by giving the interrupter a more urgent
  target.
- **Positioning to make melee interrupts costly** — kiting a melee interrupter out of range means
  their interrupt requires closing distance, which itself costs them time and exposes them.

This is the crux of "arena is a game about lying to your opponent about which button you're about
to press" — casters manipulate *when* they commit, interrupters manipulate *when they reveal
their answer is ready*, and both sides are reading real-time tells (animation start, cast bar
appearing) to decide.

---

## 3. Crowd control and diminishing returns (DR)

**Why DR exists.** Without it, a team that lands one CC can chain a second, a third, and a fourth
onto the same target before it ever acts again — "perma-stun," WoW's own historically-cited
degenerate failure mode from vanilla-era PvP. DR exists specifically to make CC an **economy**:
spendable, valuable, and finite, rather than a lock.

**How it works, structurally (this part is stable across WoW's history and is the important
part to port conceptually):**
- CC effects are grouped into **categories** (commonly cited groupings: Stun, Incapacitate
  [sleep/sap/polymorph-type], Disorient [fear/horror-type], Silence, Root, Knockback/disarm-type
  in some eras). Effects in the *same category* share a DR chain; effects in *different*
  categories DR independently.
- The **first** application of a category on a target is full duration.
- Each subsequent application **within a rolling window** is progressively shorter — the
  commonly-cited pattern is **100% → 50% → 25% → immune**, i.e. the second same-category CC on
  that target lands at half duration, the third at a quarter, and a fourth would be fully
  resisted.
- The DR chain **resets** after the target goes a period without being hit by that category
  again — commonly cited as **~18 seconds** ⚠️ UNVERIFIED THIS SESSION (this figure has been
  reported consistently across many eras/guides, but was not independently checked this
  session).
- Some categories (notably long-duration incapacitates like Polymorph, or roots) have additional
  special-cased rules in various eras (e.g., breaking on damage, "diminishing but never fully
  immune" variants) — treat the 4-step 100/50/25/immune model as the general shape, not a
  universal law with zero exceptions.

**Why this makes CC an economy rather than a lock:** a team cannot just re-chain the same stun
category forever — the second one is half as good, the third is barely worth casting, and the
fourth does nothing. So CC has to be **spent deliberately**, on a specific target, at a specific
moment, and the DR clock means a team must actually plan *when* in the fight their CC chain
lands rather than being able to apply it reactively and indefinitely. This is also why PvP
trinkets (an item that clears one CC effect and grants brief CC immunity, historically on a
cooldown in the region of **~90 seconds at rank 1** ⚠️ UNVERIFIED THIS SESSION) matter — a trinket
use is a hard counter to a CC chain that a team must bait or play around, on both sides.

---

## 4. Burst windows and cooldown alignment

WoW arena fights are **punctuated, not steady** — long stretches of poking/positioning/mana
attrition interrupted by short windows where a team commits every available cooldown at once to
force a kill, because:
- **Damage cooldowns are large, discrete, and timed** (multi-minute cooldowns that roughly
  double or triple a player's output for a short duration). Using them outside a coordinated
  window wastes most of their value — a burst cooldown popped into full defensive/healing
  coverage does nothing; the same cooldown popped when the healer is CC'd or out of range/LOS is
  often lethal.
- **Teams create windows deliberately**, usually by combining CC (to remove the enemy healer's
  ability to react, per §3) with burst cooldowns (to output more damage than the healing that
  *does* land can undo) — the classic pattern is "CC the healer, burst the target."
- **Teams defend windows with defensive cooldowns and trinkets** — a defensive cooldown
  (damage reduction, immunity, a bubble/shield) timed correctly can fully no-sell a burst
  window; timed incorrectly (popped too early, on cooldown when needed) it does nothing. Trinkets
  specifically counter the CC half of a burst window (see §3).
- The result is a fight shaped like a series of **skirmishes**, not a even grind — long lulls
  where both sides are repositioning, interrupting, and managing mana/resources, and short
  spikes where the actual kill risk exists. Reading *when* the next window is coming (cooldown
  tracking — "their trinket is down, their CC is up, now") is itself a major skill axis, distinct
  from mechanical execution.

---

## 5. Role structure

Arena comps are built from three functional roles, and what each role *does* moment-to-moment is
distinct from its label:

- **Healers** — sustain the team's HP pool against attrition, but their actual skill expression
  in a burst window is **triage under CC pressure**: deciding who to heal when they themselves
  may be silenced/feared/stunned any second, when to pre-heal (top someone off before the burst
  lands, since a bigger buffer survives longer) vs. reactive-heal, and when to use their own
  defensive/immunity cooldown to simply survive a window rather than out-heal it.
- **Damage** — split in practice into two sub-roles that matter more than the DPS number:
  - **The "kill target" applier** — the player whose burst cooldown *is* the win condition;
    everyone else's job during a window is to support this player's cooldown landing clean.
  - **Utility/control damage** — carries the CC, the interrupts, the peels; contributes less raw
    damage but enables the window to exist at all.
- **"Peel"** is not a separate class role but a *verb* every non-healer performs: using CC,
  slows, knockbacks, or defensive utility on the enemy's damage dealers to protect your own
  healer or kill target. A comp that cannot peel loses every burst-window race even with equal
  raw damage, because the enemy simply kills the healer first.

**What makes a comp** is the combination of these — reliable ways to create a burst window
(enough simultaneous CC + burst cooldowns), reliable ways to defend one (peels + defensives +
healer output), and a kill target selection that the team can actually coordinate around. Named
archetypes (e.g. historically "cleave" comps built around one relentless kill-target burst,
"CC-chain" comps built around long CC lockdown, "dampening"/turtle comps built to outlast) are
really just different answers to "how do we create and win a burst window."

---

## 6. Positioning as skill — what a player is physically doing

- **Pillar-dancing / "pillar-humping"** — deliberately keeping a line-of-sight blocker between
  yourself and an enemy caster/healer, stepping in and out of LOS to interrupt their cast-target
  lock (a caster who loses LOS on their target loses the cast) without exposing yourself to their
  allies.
- **Juking** — faking a direction change or an ability use to bait a reactive response (a trinket,
  an interrupt, a CC) that then whiffs, buying a free window afterward.
- **LOS training a healer** — repeatedly forcing the enemy healer to break LOS on their own team
  (by attacking from an angle that requires them to reposition to keep healing), which both
  interrupts their own casts if they're mid-heal and burns their movement/positioning attention
  that a coordinated burst window can then exploit.
- **Kiting** — a ranged/mobile player maintaining distance from a melee threat using slows,
  roots, and terrain, converting movement skill directly into damage avoided.
- **Terrain memory** — knowing a specific map's pillar geometry well enough to path a kite or a
  LOS break without looking directly at the obstacle, freeing attention for the rest of the fight.

All of the above are **real-time, input-driven, reactive** skills — the player is making a
sub-second decision based on what they see happening *right now* (an enemy cast bar starting, an
enemy trinket icon lighting up, a teammate's HP dropping) and executing a physical input in
response. This is the category that matters most for §7.

---

## 7. Transfer table

Verdicts: **TRANSFERS AS-IS** (the mechanic works unchanged in a pre-commit, watch-only game) ·
**TRANSFERS AS A PRE-COMMITTED ORDER** (the *idea* survives if converted from a reflex into a
standing instruction the player sets before the fight) · **DOES NOT TRANSFER** (reflex-only;
removing the ability to react removes the mechanic's reason to exist).

| WoW mechanic | Verdict | Why |
|---|---|---|
| **GCD** (§1) | TRANSFERS AS-IS | It's just a cooldown/action-rate limiter on the acting unit — this is already how our sim paces actions. No player reflex is involved in the GCD itself; it constrains the AI/unit, not the human. |
| **Cast times as exposure windows** (§1) | TRANSFERS AS A PRE-COMMITTED ORDER — *if* the windup is long enough to be legible on replay, and *if* something else in the sim is allowed to react to it | The cast time itself (a unit being briefly committed and vulnerable) is a pure sim fact. What does NOT transfer is a **human** reading the cast bar and deciding to kick it live — that has to become an **AI behaviour** (a tactic like "interrupt casters" that a monster is *pre-configured* to attempt), and it only produces a legible fight if the cast is slow enough for a viewer to see the interrupt land in relation to it. See §8 — at 0.1–0.6s this is currently too fast to read. |
| **Manual interrupt timing / baiting an interrupt** (§2) | DOES NOT TRANSFER | This is the single most reflex-dependent mechanic in the list — a player watching a specific enemy's cast bar and pressing a button within a ~1–2s window, and the caster's counterplay is *also* reflex (bait, feint, reposition mid-decision). Neither side of this exchange can be pre-committed without collapsing into a coin flip: "always try to interrupt caster X" is a standing order, not the skill of *timing* the interrupt against a live bait. |
| **Interrupt LOCKOUT as a consequence** (§2) | TRANSFERS AS-IS | Once an interrupt lands (by whatever AI logic decides it), the lockout duration and its effect on the target's next available action is pure state — no different from any other status/CC duration already in the sim. |
| **CC as a resource with DR** (§3) | TRANSFERS AS A PRE-COMMITTED ORDER | The DR *math* is pure state and already close to what "hard control has diminishing value against a team that's been CC'd recently" would look like in our status system. What transfers is the RULE (CC gets cheaper to resist the more it's used on a target, within a window) — not the live decision of *which* CC to use *when*, which in WoW is reactive to the moment. A tactics field like "CC priority: control > isolate > ignore" pre-commits the intent; the DR system then governs how well repeated attempts pay off, same as it does for a human. |
| **PvP trinket (manual CC break)** (§3) | DOES NOT TRANSFER (as a manual action) / TRANSFERS AS A PRE-COMMITTED ORDER (as a threshold rule) | "Player sees they're CC'd and presses trinket" is reflex. But "this monster breaks the first hard-CC applied to it, once, per fight, on a cooldown" is a legitimate standing rule an AI can execute deterministically and a viewer can read after the fact ("it broke free of the stun"). The INTERESTING part of the trinket — *when* to hold it for a bigger CC later — is a judgement call that in WoW is made live; ours would have to be authored as a threshold (e.g., break on the first CC that would leave the target CC'd for >Xs) rather than a live read. |
| **Burst window creation (CC + cooldown stacking)** (§4) | TRANSFERS AS A PRE-COMMITTED ORDER | This is close to a best-case transfer: "when ally CC lands on the enemy healer, use burst cooldowns on the marked target" is exactly the shape of a pre-committed tactic/gameplan already described in `docs/TACTICS_BRAINSTORM.md`. The live *reading* of the window (seeing the CC land, seeing the healer is out of position) becomes an AI trigger condition instead of a player reflex — legitimate, and arguably the single highest-value WoW mechanic to adapt, because it produces the "my read was right" moment `CLAUDE.md` names as the core fantasy. |
| **Defensive cooldown timing** (§4) | TRANSFERS AS A PRE-COMMITTED ORDER | Same shape as the trinket: "use defensive cooldown when HP drops below X% or when hit by a marked burst" is a legible standing rule, not a live read. The skill moves from the player's execution to the player's PRE-FIGHT choice of threshold and priority — which is exactly where this game's skill is supposed to live. |
| **Healer triage under CC pressure** (§5) | TRANSFERS AS A PRE-COMMITTED ORDER | Heal-priority rules (lowest HP%, tank/kill-target priority, "pre-heal before an incoming known burst") are all expressible as tactics fields. What's lost is the live judgement call under uncertainty — the AI's rule will be consistent where a human's is adaptive, which is a feature for legibility, not a bug, per the project's "every outcome must be readable" requirement. |
| **Peel (protecting the healer/kill target)** (§5) | TRANSFERS AS A PRE-COMMITTED ORDER | "Use CC/knockback on whoever is attacking our healer" is a standing tactic, already close to `tauntForce`/protect-style fields the codebase has. |
| **Comp/role identity (kill-target caller, utility, healer)** (§5) | TRANSFERS AS-IS | This is a team-composition and preparation question, not a live-execution one — it's exactly the breeding/roster-building half of the game already. Deciding WHO does what before the fight starts is the stable's whole job. |
| **Pillar-dancing / LOS-breaking a cast** (§6) | DOES NOT TRANSFER (as authored by a player) / TRANSFERS AS-IS (as an AI behaviour) | A human physically walking a unit in and out of cover mid-fight to deny a specific cast is pure reflex+spatial-reasoning under time pressure. But "AI seeks cover when threatened by a ranged/casting enemy" is already the kind of behaviour `spatial_ai.gd`/`ARENA_ETHOS_REVIEW.md` describes units doing autonomously — so the MECHANIC (cover denies LOS, LOS-denial stops a cast) transfers as a simulated fact the AI exploits, just never as a player input. |
| **Juking / faking a direction to bait a response** (§6) | DOES NOT TRANSFER | Requires a live opponent (human or AI) making a live reactive read of an ambiguous signal and being WRONG. Our system has no such live read on the player's side (the player isn't reacting to anything mid-fight) — the closest analogue would be AI-vs-AI juking, which is a real but very different design problem (deceiving an algorithm, not a human), and not obviously worth building. |
| **Kiting** | TRANSFERS AS-IS (as a spatial AI behaviour), already flagged as a live design problem | `docs/ENGAGEMENT_DESIGN.md` already treats this as a spatial-sim question — kiting is a legitimate AI tactic with no player input required, it's a movement/range/speed relationship between two AI-controlled units. The open problem there (no cost, no end to a chase) is unrelated to reflex — it's a pure systems-tuning question. |
| **Terrain memory (a player learning a map)** | DOES NOT TRANSFER | This is knowledge held by a HUMAN across many live fights on the same map, applied via reflex during the next live fight. There's no equivalent when the player never controls a unit in real time — the closest transfer is the player learning which ARENA TYPE favours which tactics preset before committing orders, which is a real but much coarser-grained version of the same idea. |

**Reading the table as a whole:** every mechanic whose skill lives in a human's live reaction to
an ambiguous, fast signal (interrupt timing, juking, pillar-dancing as an *input*, terrain
memory) does not transfer. Every mechanic whose skill lives in *preparation* — deciding
priorities, thresholds, and trigger conditions before the fight, then watching whether the read
was right — transfers cleanly as a pre-committed order, and several of these (burst-window
creation, defensive-cooldown thresholds, peel priority) are close to directly implementable
extensions of `Tactics`/`GAMEPLANS` already in the codebase. This matches the project's own
three fixed points almost exactly: WoW arena's "skill" bifurcates cleanly along the same line as
"commit, then observe."

---

## 8. Cast-time telegraphs — what a defensible windup tier looks like

**Our situation, as stated in the brief:** the pool's authored cast/windup times run **0.1s to
0.6s**, against a **0.1s simulation tick**. That means the fastest authored windup is a single
tick and the slowest is six ticks — none of it is long enough for a *human watching a replay* to
register "that unit is about to act, and I could have seen it coming," because the entire
window is comparable to or shorter than a single frame of readable animation at normal game
speed.

**What WoW's distribution actually looks like (§1, restated for this purpose):** WoW casts
cluster in **whole-second bands starting at 1.0s** — instant (0s, no telegraph at all, by
design, usually the cheaper/weaker option), then a real distribution across **1.0–1.5s**,
**2–2.5s**, and **3s+**, with the longest, highest-commitment spells reserved for the far end.
The key structural property is NOT any specific number — it's that **the shortest non-instant
cast in WoW is still an order of magnitude longer than a single action-resolution tick**, and the
bands are spaced widely enough (roughly a second apart) that a viewer can visually distinguish
"fast cast" from "slow cast" at a glance, without needing to read a number.

**Why 0.1–0.6s cannot do the job WoW's cast times do, structurally, independent of exact
numbers:**
1. **No headroom above the tick.** A 0.1s tick can only resolve a 0.1s windup as "instant" —
   there is no way to render a sub-tick telegraph at all, so the entire bottom of our range is
   functionally identical to WoW's *instant* tier (no telegraph, full commitment, resolves this
   frame).
2. **No separation between bands.** 0.1s to 0.6s is a 6x range compressed into six ticks; WoW's
   1.0s-to-3s+ range is a 3x-or-more range spread across whole seconds, each of which is dozens
   of render frames. Ours cannot be visually distinguished by a human watching normal-speed
   playback; WoW's can.
3. **No time for the OTHER thing a telegraph is for.** A telegraph isn't just "this unit is
   busy" — in WoW it exists so an opponent (or here, an ally AI, or a spectating human) has time
   to *do something in response* (interrupt, reposition, brace). At 0.1s–0.6s there is
   categorically no time for a response to be legible even if the AI reacts instantly, because
   the response and the cast resolve within the same handful of ticks the human eye is being
   asked to parse as one event.

**A defensible windup tier, reasoned from WoW's structural ratios rather than its raw numbers**
(this is a PROPOSAL for systems-designer/game-designer review, not a decision — flagging per the
collaboration protocol):

| tier | windup (ticks @ 0.1s) | windup (seconds) | WoW analogue | intended read |
|---|---|---|---|---|
| Instant | 1 tick | 0.1s | Instant-cast spells | No telegraph, by design — cheap/reactive/defensive moves only, same design logic WoW uses (instants trade power for the lack of a tell). |
| Quick | 3–5 ticks | 0.3–0.5s | *(no direct analogue — faster than any WoW hard cast)* | A visible but brief windup; readable in a slow-mo replay, not really reactable to at normal speed. This is roughly where today's 0.1–0.6s pool sits and it should be understood as WoW's "instant" tier stretched thin, not as WoW's "cast time" tier. |
| Telegraphed | 10–15 ticks | 1.0–1.5s | WoW's short-cast band | The shortest windup that is unambiguously visible at normal playback speed and gives a watching player (pre-fight, on replay, or via an AI's pre-committed reaction) real separation from the action resolving. This is the floor a "big" ability's windup should sit at if the goal is "the player could have predicted this." |
| Heavy | 20–30 ticks | 2.0–3.0s | WoW's medium/long-cast band | Reserved for the pool's biggest single hits — the equivalent of a capstone/ultimate-tier commitment. Long enough that its OWN vulnerability (being interruptible, or simply being a huge tell before a huge hit) is a real, replay-visible story beat. |

⚠️ **This table is reasoned from ratios (tick-count and WoW's band spacing), not measured
against our own pool's balance** — it says what a *legible* windup would look like structurally,
not what the current 141-move pool's power/cost math would tolerate if windups were lengthened.
Before adopting it: (a) confirm with `battle.ts`/`tamerengine` whether any move's economy assumes
its current near-instant resolution (a windup that can be interrupted is worth less than one that
can't, so lengthening windups is a balance change, not just a legibility one — this needs
`tools/ab.ts`, not a sim, per the standing balancing rule), and (b) decide whether "Telegraphed"
and "Heavy" should also carry the interrupt/counterplay half of the WoW mechanic (§2/§7 — an
AI-executed interrupt tactic), since a long windup with nothing able to react to it just becomes
a slower version of the same unreadable problem.

---

## Summary for the studio

- WoW arena's skill splits cleanly into **preparation** (comp building, cooldown tracking, threat
  prioritisation, threshold decisions) and **live execution** (interrupt timing, juking,
  pillar-dancing as physical input). The first half maps almost directly onto tactics/gameplans
  this project already has the machinery for; the second half is exactly the category the
  project's zero-intervention rule excludes by design, and no amount of clever conversion makes
  it transfer — it has to be dropped or re-cast as an AI-vs-AI behaviour instead of a
  player-vs-moment reflex.
- The highest-value adaptation is **burst-window creation** (§4/§7): CC-then-burst,
  defended-by-cooldown, is close to directly buildable on `Tactics`/`GAMEPLANS` and produces
  exactly the "my read was right" moment the project's vision statement names as the fantasy.
- DR (§3) is worth porting as a STATUS-SYSTEM RULE (CC gets cheaper to land repeatedly on the
  same target within a window), independent of any player-facing trinket mechanic.
- The cast-time finding (§8) is the most actionable: **0.1–0.6s cannot do the telegraph job at a
  0.1s tick, structurally, regardless of what the exact numbers are** — a legible windup needs to
  clear roughly 1.0s (10 ticks) before a human watching a replay can register it as a tell rather
  than as part of the resolution itself. That's a proposal for `game-designer`/`systems-designer`
  to weigh against pool balance, not a decision made here.

⚠️ **Re-affirming the sourcing caveat:** structural claims above are solid; specific numbers
(GCD floor, interrupt lockout duration, DR reset timer, trinket cooldown, specific spell cast
times) are flagged ⚠️ UNVERIFIED THIS SESSION throughout and should be checked against a live
source before being used as a design input rather than background colour.
