## THE READ — pre-battle standing orders. Static utility class, not a scene node and not a
## RefCounted data object: every other runtime shape in this port (moves, statuses, mods) is a
## plain Dictionary, so orders are too. Keys are camelCase, mirroring `src/core.ts`'s `Tactics`
## interface directly (`temperament`, `targetPriority`, `manaPolicy`, `formation`) so this schema
## stays legible against the TS source of truth instead of inventing a parallel vocabulary.
##
## ⚠️ THIS IS A DELIBERATE SUBSET OF `core.ts`'s `Tactics`, NOT A FULL PORT. `comboRole`,
## `openerIds`, `preserve`, `ccPriority`, `healPolicy`, `burst`, `useCover`, `commit` are real,
## designed orders — they are not represented here because `battle_sim.gd` has no Block/Guard
## action, no positions and no combo/status-cashing bookkeeping to hang them on. Adding the UI
## for an order the engine cannot act on is this project's own named failure mode (moves that are
## "authored, typed and priced but never drafted"); an order with no engine effect is the same
## bug wearing a different hat. Wire the engine first, then the order.
##
## TWO SCOPES, per docs/TACTICS_BRAINSTORM.md §1's own boundary ("if an order only means
## something when everyone obeys it at once, it is a team order"):
##
##   TEAM PLAN (one per side) — {
##     "targetPriority": "casters" | "tanks" | "manmark",   # absent = today's lowest-HP default
##     "markedUnit": <MonsterInstance>,                     # only read when targetPriority == "manmark"
##     "manaPolicy": "normal" | "conserve",                 # absent = "normal"
##     "formation":  "tight" | "loose",                     # absent = "tight" — TEAM-ONLY, see below
##   }
##
##   PER-MONSTER ORDERS (keyed by MonsterInstance) — {
##     "targetPriority": "casters" | "tanks" | "manmark",   # optional, overrides the team plan
##     "temperament": "aggressive" | "balanced" | "cautious",
##   }
##
## ⚠️ `formation` HAS NO PER-MONSTER OVERRIDE, ON PURPOSE. It is the one order that is incoherent
## for an individual to hold alone — "I personally will stand loose while my team stands tight" is
## not a thing a formation can do. Every other axis here is legitimately mixed (one monster can
## hunt casters while its team defaults to the tank), so only `formation` is excluded from the
## per-monster dictionary's accepted keys.
##
## ⚠️ `manaPolicy` DROPS `core.ts`'s THIRD OPTION, `'burst'`. In `battle.ts`, burst vs. normal is a
## real behavioural difference; in `battle_sim.gd`'s `_act()`, the current move-choice policy
## already casts the strongest ready move with no reservation at all — that IS burst. Adding a
## `'burst'` option here would be a second name for the existing default, which is exactly the
## "control that does nothing" failure mode `comboRole` was already flagged for at ~32% of
## monsters. Only `'conserve'` is a real, observable change (see `battle_sim.gd`'s ready-move
## filter), so only two honest options ship.
##
## ⚠️ `temperament`'s `'cautious'` IS A COMPRESSED STAND-IN FOR `core.ts`'s SEPARATE `preserve`
## AXIS, not a full port of it. `battle_sim.gd` has no Block/Guard action to gate on an HP
## threshold the way `PRESERVE_INFO` describes ("guards incoming hits"); what IS implementable
## without a new engine mechanic is skipping self-harm (recoil) moves under a survival floor,
## which is the other half of that same TS description ("stops throwing self-harm moves"). That
## is the only thing `'cautious'` does. `'aggressive'` and `'balanced'` have NO behavioural
## difference from each other yet — both are the engine's untouched default. The UI must say so
## in the option's own description text, not imply a parity that does not exist.
class_name Tactics
extends RefCounted


# ── Team-wide handoff slot ───────────────────────────────────────────────────────────────────
# GDScript `static var`s are shared process-wide with no autoload registration needed — this is
# how `tactics_ui.gd` hands a committed plan to whichever scene fights the battle next, without
# this file owning `project.godot` or `battle_sim.gd`/`battle_ui.gd` needing to exist yet. Inert
# until a consumer chooses to read it, exactly like this codebase's other authored-before-read
# fields (e.g. `statScale` in the ability pool is "FIELD-ONLY" until the field engine reads it).
static var committed: Dictionary = {}


## ⚠️ `deploy_a` IS LIVE — `arena_3d.gd:803-806` folds it into `orders[m]["deployPos"]` and
## `arena_3d.gd:931` reads it again for the start positions. This block used to call it
## "FORWARD-COMPATIBLE PLUMBING, NOT A LIVE HOOK YET" and name `spatial_sim.gd`/`spatial_ai.gd`;
## that was true of the LEGACY sim and became false when the arena path landed on 2026-08-08.
##
## ⚠️ `intents_a` IS THE ONE GENUINELY DEAD KEY, AND IT IS PROBE-ONLY BY DECISION.
## Written here, and the only reader in the tree is `_probe_career_loop.gd:495`, which asserts
## the key EXISTS and nothing more. It is a DUPLICATE of the per-monster `positionalIntent` that
## `ordersA` already carries, and `ordersA` is the copy `arena_3d._new_sim_tactics()` reads.
## It is kept rather than deleted because SAVE_VERSION 4 files and that probe both name it, and
## deleting a key from a serialised dictionary is a save-compat change for zero gameplay gain.
## Do not add a second consumer: if a screen wants a monster's posture, read `ordersA`.
## ⚠️ `team_a`/`team_b` ARE THE EXACT ROSTER ARRAYS "The Read" SHOWED THE PLAYER — pass them so
## whichever screen fights the battle next (arena_3d.gd) uses THESE, not a freshly regenerated
## rival team. `arena_3d.gd` used to call `Roster.make_rival_team()` a second time with its own
## RNG draw, so the scouted gameplan/rival roster the player saw on this screen and the roster
## they actually fought could silently differ — found while wiring the tournament path to the
## live arena. Both default to `[]` so every existing caller that doesn't pass them (report_ui.gd's
## standalone demo, any future standalone tactics.tscn run) is unaffected.
static func commit(plan_a: Dictionary, plan_b: Dictionary, orders_a: Dictionary, orders_b: Dictionary,
		deploy_a: Dictionary = {}, intents_a: Dictionary = {}, team_a: Array = [], team_b: Array = []) -> void:
	committed = {
		"planA": plan_a, "planB": plan_b, "ordersA": orders_a, "ordersB": orders_b,
		"deployA": deploy_a, "intentsA": intents_a, "teamA": team_a, "teamB": team_b,
	}


# ── Legible descriptions for the UI — every option states what it DOES, ported/adapted from
# `core.ts`'s `TEMPERAMENT_INFO` / `TARGET_PRIORITY_INFO` / `MANA_POLICY_INFO`. `FORMATION_INFO`
# has no TS equivalent to port (formation is a field-engine-only order there); its copy is
# grounded in docs/ARENA_BLUEPRINT.md §5's decided aura-vs-AoE trade-off instead. ─────────────

const TEMPERAMENT_INFO := [
	{"id": "aggressive", "icon": "⚔", "name": "Aggressive", "desc": "Fights on the class's own instincts — no different from Balanced yet in this build."},
	{"id": "balanced", "icon": "⚖", "name": "Balanced", "desc": "Fights on the class's own instincts."},
	{"id": "cautious", "icon": "🛡", "name": "Cautious", "desc": "Below 40% HP, refuses its riskiest (self-harming) moves rather than trading down to the end."},
]

const TARGET_PRIORITY_INFO := [
	{"id": "", "icon": "🎲", "name": "Team default (weakest)", "desc": "No standing order — goes for whichever enemy is lowest on HP."},
	{"id": "casters", "icon": "🧙", "name": "Hunt the casters", "desc": "Goes for the enemy's supports — silence the heals before they undo your damage."},
	{"id": "tanks", "icon": "🐘", "name": "Break the tank", "desc": "Goes for the highest-CON wall and stays on it."},
	{"id": "manmark", "icon": "🎯", "name": "Man mark", "desc": "Hunts the one rival monster you marked below. Requires scouting — click a rival to mark it."},
]

const MANA_POLICY_INFO := [
	{"id": "normal", "icon": "💠", "name": "As needed", "desc": "Spends MP on the class's own judgement — this is the engine's existing default, not a passive option."},
	{"id": "conserve", "icon": "💧", "name": "Conserve", "desc": "Won't cast a skill if it would drop MP below a quarter of the pool — holds back for something worth it."},
]

const FORMATION_INFO := [
	{"id": "tight", "icon": "🤝", "name": "Tight", "desc": "Stay clustered: your team-wide buffs and auras reach almost everyone — but so does the enemy's area damage."},
	{"id": "loose", "icon": "↔", "name": "Loose", "desc": "Fan out: the enemy's area damage catches only part of your team — but so do your own team buffs and auras."},
]

## `docs/AUTOBATTLER_DESIGN.md` §2B's positional-intent axis — *where do I want to be*, distinct
## from *who do I attack* (`TARGET_PRIORITY_INFO`).
##
## ⚠️ THIS BLOCK SAID "NOT YET CONSUMED BY THE ENGINE" UNTIL 2026-08-13 AND IT WAS FALSE.
## It described `spatial_sim.gd`/`spatial_ai.gd` — the LEGACY sim, superseded on 2026-08-08 and
## now reached only from the Sandbox screen. The live path consumes every one of these ids:
##   `tactics_ui._on_board_changed()` → `ordersA[m]["positionalIntent"]`
##   → `arena_3d.gd:1001-1013 _new_sim_tactics()` → `t["positional"]` (+ `t["guard_ally"]`)
##   → `combat_tree.gd:565 _positional_node()` → five posture branches (hold/push/wings/dive/guard)
##   → `sim.gd:497 bb.set_value("guard_id", ...)` for the guard charge.
## The order is REAL. Note the deliberate camelCase→snake_case rename at the arena boundary:
## grepping for `positional_intent` finds only the legacy tree and reads as "nothing uses it",
## which is exactly the wrong conclusion two separate reviewers drew from this comment.
##
## ⚠️ AND THE LESSON THIS COST: a "NOT YET WIRED" note needs the file whose change retires it
## named in the note, or it outlives the thing it describes and becomes the misinformation the
## comment style exists to prevent. This one outlived its subject by five days and produced a
## round-20 brief whose central claim was refuted.
const POSITIONAL_INTENT_INFO := [
	{"id": "hold", "icon": "⚓", "name": "Hold", "desc": "Keep the line near where you deployed."},
	{"id": "push", "icon": "➡", "name": "Push", "desc": "Advance on the enemy line, take ground."},
	{"id": "wings", "icon": "↗", "name": "Wings", "desc": "Work wide, approach from the flank."},
	{"id": "dive", "icon": "⤴", "name": "Dive", "desc": "Go around or through for the enemy back line."},
	{"id": "guard", "icon": "🛡", "name": "Guard", "desc": "Stay near a named ally and intercept threats to it."},
]

## ⚠️ `guard` IS INHERENTLY PER-MONSTER AND MUST NOT BE OFFERED AS A TEAM DEFAULT — it is the
## mirror image of `formation`, which this file already excludes from the per-monster keys for
## the same reason. A whole team ordered to guard has no charges to guard: every body would name
## an ally, `arena_3d.gd:1013` downgrades a charge-less guard to `hold`, and the player would have
## picked a posture that silently became a different one. Five dead controls in one dropdown.
const TEAM_POSITIONAL_INTENT_INFO := [
	{"id": "hold", "icon": "⚓", "name": "Hold", "desc": "Keep the line near where you deployed."},
	{"id": "push", "icon": "➡", "name": "Push", "desc": "Advance on the enemy line, take ground."},
	{"id": "wings", "icon": "↗", "name": "Wings", "desc": "Work wide, approach from the flank."},
	{"id": "dive", "icon": "⤴", "name": "Dive", "desc": "Go around or through for the enemy back line."},
]


# ── ARCHETYPES — rival gameplans that are a DIFFERENT KIND OF TEAM, not a strength multiplier ──
#
# ⚠️ THIS TABLE WAS PRESENTATION TEXT AND NOTHING ELSE UNTIL 2026-08-09, AND THAT WAS THE SINGLE
# BIGGEST MISS AGAINST THE VISION. Every rival team in the game came out of ONE generator
# (`Roster.make_rival_team`) that draws random painted species at a fill level — so a "Bulwark"
# and a "Rushdown" were the same team with different scouting copy on the sign-up screen, and
# eleven league champions differed from each other only by `field_fill`. If every opponent is the
# same shape then "knowing WHICH monster to make is the skill" (CLAUDE.md) is not a skill, and
# scouting a field you cannot read anything off is decoration.
#
# What makes an archetype REAL here is that each one now drives all three of:
#   `classes`  — the slot-by-slot CLASS pattern the team is built to. Class is emergent from the
#                two highest stats (`classify.gd`) and class picks the ability LINES a kit draws
#                from (`data.json:classLines`), so a class pattern is a KIT pattern: an Orator
#                draws Enchanter/Disruptor (10 status-carrying moves between them) and a Mystic
#                draws Mender/Siphon (6 heals). `Roster.make_rival_team(..., archetype)` shapes
#                the generated monsters onto this pattern, sum-preserving (see roster.gd).
#   `tactics`  — the team plan + per-monster orders `battle_sim.gd` actually reads.
#   `signature`— what the archetype must be OBSERVED doing in the event log. Asserted per
#                archetype by `scripts/_probe_archetypes.gd`; a `read` line that the probe cannot
#                verify is a lie and gets rewritten rather than shipped.
#
# ⚠️ THE `read` LINE IS THE CONTRACT, NOT THE FLAVOUR. `career.gd:CHAMPIONS` authored eleven of
# them ("Stalls. Wins on the clock", "Controls. You will be stunned…") against a generator that
# could not produce any of it. The lines below are the ones the sim can be held to; where the
# authored line described something the engine has no vocabulary for (flanks, kiting — both
# spatial, and the cup path fights on the NON-spatial `battle_sim.gd`), the LINE changed.
#
# ⚠️ `formation` per archetype is still this file's own extrapolation, not a TS port — but it is
# no longer arbitrary: `aoe_coverage()` gates area damage on the DEFENDER's formation and
# `aura_coverage()` gates team buffs/heals on the CASTER's own, so "tight" and "loose" are a real
# two-sided trade and each archetype picks the side its win condition needs.
# ⚠️ `counterRoster` IS THE `counter` PROSE IN MACHINE FORM, AND IT LIVES HERE SO THERE IS ONE COPY.
# `roster.gd:counter_gap()` reads it to answer "what kind of roster does this rung's champion need,
# and does the stable own any of it". It arrived in round 19 as a second table inside `roster.gd`;
# a second copy of a truth is this project's most-repeated failure and it was moved on sight.
#
# ⚠️⚠️ AND THE NUMBERS IN IT ARE STALE, WHICH IS WHY NO SCREEN PRINTS THEM ANY MORE.
# `_probe_archetypes.gd:_counter_matrix()` at HEAD (2026-08-11) reports a DIFFERENT winning kind in
# FOUR of these six rows:
#
#     row            authored here          measured at HEAD
#     vs rushdown    zone      +24          bulwark   +16   (zone now +5)
#     vs bulwark     focusfire +20          focusfire +29   ✓ kind agrees
#     vs attrition   focusfire +13          focusfire +13   ✓ agrees exactly
#     vs focusfire   control   +27          control   +19   ✓ kind agrees
#     vs control     bulwark   +13          attrition +25   (bulwark now -0)
#     vs zone        rushdown  +25          control    +9   (rushdown now +7)
#
# The same drift is in the zone prose's "six wins in twenty-four" — today's run says nine.
# ⚠️ DO NOT "FIX" THESE BY COPYING TODAY'S RUN IN. `MATRIX_TRIALS = 12`, so a cell's win rate
# carries a standard error near 14 points and the gap between the top two answers in four of these
# rows is smaller than that. Both tables are under-powered, not one wrong and one right. The rung's
# ARCHETYPE and the SHAPE of each answer are what the screens are allowed to state; the point
# figures are not, until someone re-measures at 48+ trials. See round 20's list.
#
# ⚠️⚠️ ROUND 20 DERIVED THE POWER AND "48+ TRIALS" IS NOT ENOUGH — THE DEBT IS BIGGER THAN THE
# NOTE ABOVE SAYS, BY 29%. The 14-point figure is the standard error of a CELL, but nothing on any
# screen quotes a cell: what is quoted is which kind WINS, and that is a comparison between two
# rows' residuals in one column. The column and grand means cancel in that difference, leaving a
# difference of two row-centred cells whose SD is **1.29x the cell SE** — 18.6 points at 12 trials,
# not 14. (`_probe_archetypes.gd:_gap_sd()` carries the derivation and computes it at run time.)
#
#     trials/cell    95% band on the top-two gap    matrix cost
#          12                +/- 36.5 pt              504 fights
#          48                +/- 18.3 pt            2,016 fights
#          96                +/- 12.9 pt            4,032 fights
#         251                +/-  8.0 pt           10,542 fights
#
# The leads in the rows above run about 2 to 11 points, so 48 trials would settle NONE of the four
# disputed rows and would hand back a fresh set of confident-looking numbers with a band twice the
# effect — the same debt, one round newer, which is exactly what the ⚠️ above was written to stop.
# 251 trials/cell is what an 8-point gap costs at 95%; a 2-point gap (control +9 vs rushdown +7,
# vs zone) costs ~4,000 trials/cell and is not worth buying at any price.
#
# ⚠️ SO THE POINT FIGURES ARE GONE FROM THE PROSE, AND THAT DELETION NEEDED NO NEW RUN.
# Asserting a DIFFERENT winner requires a measurement; DELETING a claim requires only the proof
# that no measurement supports it, and the table above is that proof — both runs are at 12 trials
# with a ±36.5 pt band on gaps of 2..11 pts. Eight numeric claims were shipping verbatim to the
# player (`+24`, `+3`, `+20`, `+13`, `+27`, `+13`, `+25`, and zone's "six wins in twenty-four"),
# in GOLD body text on the Stable screen (`stable_ui.gd:_frontier_brief`) and in the Tournament
# board's chip tooltip (`tournament_ui.gd`). Every one is now removed. What each row states is the
# KIND, framed as "the authored answer" — a design read, which is what `roster.gd:counter_gap()`
# already treats it as — plus the MECHANISM, which is reasoning about how guard/CC-resist/area
# coverage work and needs no trial count to be true.
#
# ⚠️ THE ONE CLAIM THAT KEPT ITS EVIDENCE IS ZONE'S FORMATION ORDER, and the reason is the design
# of the test, not its size: `_counter_formation()` is PAIRED (identical teams, identical seeds,
# one order changed) and judged on a sign test, so it cancels the roster variance that swamps the
# matrix. Do not "tidy" it into the same hedge as the rest — see the note on the zone entry.
#
# ⚠️ AND `counterRoster` LOST ITS `residual` KEY, WHICH NOTHING HAD EVER READ. It was authored six
# times and consumed nowhere (`roster.gd:counter_gap()` reads `.kind` and only `.kind`) — a stale
# number kept alive with no consumer is a number that gets quoted by the next screen that wants
# one, which is precisely how this debt started.
#
# ⚠️ AND ROUND 20 COULD NOT RUN THE MEASUREMENT: the Godot binary
# (`P:/Godot_v4.7.1-stable_win64.exe`) is not present on the build machine — `run_contract.sh`
# exits 127 and the only trace left is a broken shortcut to a deleted `.zip`. Nothing below was
# re-measured, so nothing below was changed. The arithmetic above is closed-form binomial and
# needed no engine; the numbers in the strings still need one.
const GAMEPLANS := {
	"rushdown": {
		"name": "Rushdown", "icon": "🔥",
		"tell": "Fast, aggressive, no support — all pressure.",
		"read": "Comes straight down the middle and hits first. Nothing clever, and nothing held back.",
		## AUTHORED ANSWER: an area/ZONE roster. ⚠️ THE OLD LINE HERE WAS THE WORST SENTENCE IN THE
		## TABLE AND IT SHIPPED IN GOLD ON THE STABLE SCREEN: "Out-tanking the opening is NOT the
		## answer; a wall roster measures +3." The HEAD run recorded in the ⚠️ block above measured
		## the WALL as the best answer to rushdown (+16) with zone down at +5 — so the screen was
		## steering the player away from what the most recent measurement named as the best. Neither
		## run can settle it (both 12 trials, ±36.5 pt band), and a NEGATIVE claim is the least
		## supportable form there is, so it is deleted rather than reversed.
		"counter": "They come as one block with no healer and no wall — every body of theirs is in range of the same cast. AREA damage is the authored answer to that shape, so a zone roster is what to build toward.",
		"counterRoster": {"kind": "zone"},
		"winCon": "Kill something in the first few exchanges and snowball the numbers advantage.",
		"signature": "front-loaded damage — the highest damage-per-second of any archetype, and the shortest fights",
		"classes": ["Warrior", "Skirmisher", "Captain", "Warrior", "Rogue"],
		"tactics": {"temperament": "aggressive", "manaPolicy": "normal", "formation": "tight"},
	},
	"bulwark": {
		"name": "Bulwark", "icon": "🛡",
		"tell": "Tanks and guardians around a protected carry.",
		"read": "Will not break. Brings guards and wards and expects you to run out of patience.",
		## AUTHORED ANSWER: a BURST/focus-fire roster. The MECHANISM below is design reasoning about
		## how guard works and survives the deletion; only the point figure went.
		"counter": "Guard is FLAT reduction per hit, so chip damage is worth nothing against them: you need few big blows, not many small ones. A burst roster is the authored answer.",
		"counterRoster": {"kind": "focusfire"},
		"winCon": "Keep one carry alive behind a wall until it out-damages everything you have left.",
		"signature": "protective buffs — ward/guard mods applied on its own side, and the lowest damage taken per landed hit",
		## ⚠️ SLOT 4 IS A CAPTAIN, NOT A SHAMAN, AND THAT WAS MEASURED. With a Shaman here the
		## bulwark comp drew TWO Mender lines and out-healed the attrition archetype 593 to 430 HP
		## a fight — the wall was quietly the best healer on the ladder, which makes two archetypes
		## the same team. Captain keeps the protective identity (Captain/Warcry carry ward, guard
		## and the team buffs) without the restoration that belongs to attrition.
		"classes": ["Tank", "Spellshield", "Warrior", "Tank", "Captain"],
		"tactics": {"temperament": "cautious", "manaPolicy": "conserve", "formation": "tight"},
	},
	"attrition": {
		"name": "Attrition", "icon": "☠",
		"tell": "Poison and stall, with a mender behind it — out-lasts you.",
		"read": "Stalls. Heals what you break and wins on the clock unless you make the fight happen.",
		## AUTHORED ANSWER: a BURST/focus-fire roster. ⚠️ THE METHODOLOGICAL LESSON ON THIS ROW IS
		## THE PART WORTH KEEPING, AND IT IS NOT A NUMBER. The first version of this line was an
		## untested guess that then "measured as one": burst looked confirmed at +8 wins over a
		## generic roster — until the same burst roster gained MORE against the WALL, which it does
		## not counter at all. Burst is simply a strong roster, and only the two-way residual
		## separates that from an answer. Round 20 added the second half of the lesson: the residual
		## itself needs ~20x the trials anyone has ever run before it can name a winner either. The
		## figures are gone; the reasoning is why this row is still focus-fire.
		"counter": "Healing is throughput and only wins a long fight. Kill one of them faster than the mender can refill it — a burst roster is the authored answer.",
		"counterRoster": {"kind": "focusfire"},
		"winCon": "Out-heal the damage you can sustain and outlive the clock.",
		"signature": "healing — real HP restored to its own side, and the longest fights on the ladder",
		"classes": ["Mystic", "Stalker", "Sage", "Shaman", "Stalker"],
		"tactics": {"temperament": "cautious", "manaPolicy": "conserve", "formation": "tight"},
	},
	"focusfire": {
		"name": "Focus-Fire", "icon": "🎯",
		"tell": "High burst — the whole team piles onto one target.",
		"read": "Focuses one target down and moves on. Your softest body dies first.",
		## AUTHORED ANSWER: a CONTROL roster. ⚠️ "the largest counter effect in the game" went with
		## the number — it was a RANKING across the six rows, which needs every row measured to the
		## same precision to mean anything, and no run has ever had that.
		"counter": "They man-mark your LOWEST-CON monster and delete it in under three seconds. Taking their turns away is what breaks that, so a control roster is the authored answer. Spreading durability so there is no soft body to pick is the roster-building version of the same answer.",
		"counterRoster": {"kind": "control"},
		"winCon": "Mark one monster and delete it before it acts twice.",
		"signature": "concentration — the largest share of its damage landing on one enemy, and the fastest first kill",
		"classes": ["Rogue", "Skirmisher", "Ranger", "Rogue", "Swashbuckler"],
		"tactics": {"temperament": "aggressive", "targetPriority": "manmark", "manaPolicy": "normal", "formation": "tight"},
	},
	"control": {
		"name": "Control", "icon": "🔗",
		"tell": "Hexers and orators — they take your turns away before they take your HP.",
		"read": "Controls. You will be stunned, silenced and blinded on purpose, and your supports go first.",
		## AUTHORED ANSWER: a WALL/bulwark roster. ⚠️ THIS IS THE ROW MOST LIKELY TO BE WRONG — the
		## HEAD run put bulwark at −0 here and named ATTRITION (+25) instead. It is kept as the
		## authored design read (CON saturating the CC-resist meter is a real mechanism, stated
		## below) and NOT as a measurement, which is the only claim the evidence supports.
		"counter": "Control lands through the CC-resist meter, which saturates with CON — a high-CON line shrugs off the second stun and cleanses the first. A wall roster is the authored answer.",
		"counterRoster": {"kind": "bulwark"},
		"winCon": "Take enough turns away that the fight is five-on-three whether or not anything has died.",
		"signature": "status application — far more landed statuses than any other archetype, hard control included",
		## ⚠️ NO SAGE HERE, AND THE POOL IS THE REASON. Sage draws Mender/Siphon/Hexer and carries
		## exactly ZERO hard-control moves — "the caster class" is not the same thing as "the
		## control class". Counted over `lineOf`, hard control (stun/sleep/fear/confusion/charm/
		## silence/knockback) lives in Enchanter (5), Disruptor (3), Warcry (2) and Warden (2), so
		## the classes that can actually take a turn away are Orator (8 between its four lines),
		## Bard (5) and Wizard (4). With a Sage in the middle slot this archetype measured 9.4 hard
		## controls a fight and was OUT-CONTROLLED BY THE BULWARK WALL at 14.5 — the wall draws
		## Warden and Warcry, both of which knock down and stun in an area.
		"classes": ["Orator", "Wizard", "Bard", "Orator", "Wizard"],
		"tactics": {"temperament": "balanced", "targetPriority": "casters", "manaPolicy": "normal", "formation": "tight"},
	},
	"zone": {
		"name": "Zone", "icon": "🌩",
		"tell": "Heralds and evokers — everything they throw lands on your whole team at once.",
		"read": "Opens wide. Everything hits everyone, so a tight formation gives them the whole team for free.",
		## TWO ANSWERS — the only archetype with both an ORDER and a ROSTER answer, and they do NOT
		## rest on the same quality of evidence. ⚠️ KEEP THAT DISTINCTION.
		##   • The FORMATION answer is the best-evidenced claim in this whole table:
		##     `_probe_archetypes.gd:_counter_formation()` is a PAIRED test — identical teams,
		##     identical seeds, one order changed — judged on a sign test (8/24 -> 14/24, sign 6:0,
		##     which is p≈0.03 two-sided on its own). A paired design cancels the roster variance
		##     that makes the counter matrix so noisy, which is exactly why it can say something the
		##     matrix cannot. Only the exact COUNT was dropped (the run drifts 6..9 of 24); the
		##     DIRECTION stands and is asserted by the probe every run.
		##   • The ROSTER answer comes from the same under-powered matrix as every other row and is
		##     an authored read, nothing more. The HEAD run put rushdown at +7 and control at +9 —
		##     a 2-point gap that would cost ~4,000 trials/cell to call, and is not worth buying.
		"counter": "Area damage is gated by YOUR formation, not theirs: order LOOSE and roughly half your side falls out of the blanket. That one is measured on identical teams and seeds, and it wins fights a tight formation loses — the price is your own buffs and heals thinning out too. On the roster side, closing fast is the authored answer.",
		"counterRoster": {"kind": "rushdown"},
		"winCon": "Blanket the whole team in area damage and never trade one-for-one.",
		"signature": "breadth — area casts that touch every living enemy, and the flattest damage spread of any archetype",
		"classes": ["Herald", "Evoker", "Orator", "Evoker", "Ranger"],
		"tactics": {"temperament": "balanced", "manaPolicy": "normal", "formation": "loose"},
	},
}

## THE ELEVEN RUNGS, EACH A KIND OF TEAM. Parallel to `career.gd:CHAMPIONS` by INDEX — Wood at 0,
## Tamers Apex at 10.
##
## ⚠️ THE LADDER TEACHES A VOCABULARY, IN ORDER, AND THAT IS THE WHOLE POINT OF THE MAPPING.
## Wood opens with the simplest thing in the game (walk forward and hit); each new rung introduces
## exactly one new problem the player has not had to answer yet; the top three re-ask the earlier
## questions at a level where a single generalist roster cannot cover all of them. A ladder whose
## eighth rung is the same shape as its first has no climb in it, however much its stats grew.
##
## ⚠️ TWO CHAMPIONS HAD READS THE CUP ENGINE CANNOT HONOUR AND THEY WERE REWRITTEN, NOT FAKED.
## Dunnal Bray ("Opens wide, then collapses the flanks. Punishes a spread deployment") and Cassia
## Vane ("Refuses to stand still. Kites the slowest thing you field") both describe SPATIAL
## behaviour — and the cup path fights on `battle_sim.gd`, which has no positions at all. Their
## replacements keep the intent (Bray punishes a formation choice; Vane picks off one body) in
## terms the engine can actually be held to. See `champion_read()`.
const ARCHETYPE_BY_LEAGUE := [
	"rushdown",   #  0 Wood        — Otta Vance, the Paddock King.   Walk forward and hit.
	"bulwark",    #  1 Copper      — Merrin Kell, the Kettle Queen.  Two bodies that guard each other.
	"attrition",  #  2 Tin         — Sable Roke, the Tinsmith.       The clock is a weapon.
	"zone",       #  3 Bronze      — Dunnal Bray, Bellfounder.       Your formation is a choice.
	"bulwark",    #  4 Iron        — Ysolde Ferrum, the Anvil.       The wall, at size.
	"focusfire",  #  5 Silver      — Cassia Vane, the Quicksilver.   One body, gone.
	"control",    #  6 Gold        — Auric Halloway, the Sovereign.  Your turns are the resource.
	"focusfire",  #  7 Platinum    — Perrin Adamant, the Vanguard.   Focus fire at 5v5.
	"control",    #  8 Masters     — Ianthe Corvo, the Crownless.    Control at 5v5.
	"rushdown",   #  9 Tamer Elite — Marek Thule, the Undisputed.    The simplest thing, perfected.
	"zone",       # 10 Tamers Apex — The Dynast.                     Everything, everywhere.
]


## ⚠️ DIFFERENT IN KIND MUST NOT MEAN DIFFERENT IN POWER, AND UNCORRECTED IT DID — BY 3.3x.
## `career.gd:field_fill()` is the ladder's ONLY difficulty dial: round `r` of league `l` is filled
## to a fraction of that league's ceiling, and the whole climb's slope is expressed in those
## numbers. That is only honest while a fill of 0.65 is worth the same whatever KIND of team it
## builds. Measured at fill 0.65, 24 fights each, against identical generic opposition:
##
##     rushdown 96% | focusfire 83% | bulwark 67% | zone 67% | attrition 46% | control 29%
##
## — a spread far wider than the slope the ladder is trying to draw, so an uncorrected archetype
## table would have made "which rung" matter LESS than "which archetype", which is the inverted-
## progression failure this studio has hit before, arriving by a new door.
##
## Each multiplier is the fill at which that archetype wins half its fights, over 0.65. Re-derive
## with `_probe_archetypes.tscn -- --calibrate`; do not hand-tune them. ⚠️ THEY ARE A CORRECTION,
## NOT A BALANCE PASS — the baseline is suspended (CLAUDE.md), and these exist only so that the
## ONE number the ladder does own keeps meaning what it says.
## ⚠️ THE CORRECTION SATURATES AT THE TOP OF THE LADDER, ON PURPOSE AND WITH A COST. `field_fill`
## already runs the Apex champion at 0.95 of its ceiling, so a 1.23x multiplier clamps at 1.0 and
## the attrition/control kinds arrive at the summit slightly UNDER-corrected. Raising the clamp
## instead would mean fielding monsters above the league's own stat cap — the exact illegality
## `career.gd:_cap_override` was added to stop. Living with a mild under-correction in the last
## two rungs is the cheaper of the two wrongs; say so rather than hiding it.
const FILL_MULT := {
	"rushdown": 0.856, "bulwark": 1.000, "attrition": 1.231,
	"focusfire": 0.769, "control": 1.192, "zone": 1.066,
}


## ⚠️ `FILL_MULT` EQUALISES THE ARCHETYPES TO EACH OTHER. IT DOES NOT MAKE A SHAPED TEAM WORTH THE
## SAME AS THE FLAT GENERATOR IT REPLACED ON THE LADDER, AND THAT SECOND CORRECTION IS NOT THIS
## FILE'S BUSINESS — see `career.gd:FIELD_ARCHETYPE_POWER_MULT`. Two instruments measured the same
## teams and disagreed, because they use different reference opponents: `_probe_archetypes` fights
## a generic 0.65 rival build, `_probe_ladder_slope` fights the modelled CLIMBER. Folding one
## file's answer into the other's constant makes both wrong and neither checkable, which is how a
## tuning value becomes a value nobody can re-derive. One knob per question: kind-parity here,
## ladder difficulty there.
##
## The fill an archetype should actually be built at to be worth `fill` of its league's ceiling.
static func archetype_fill(gid: String, fill: float) -> float:
	return clampf(fill * float(FILL_MULT.get(gid, 1.0)), 0.02, 1.0)


static func archetype_for_league(idx: int) -> String:
	if idx < 0 or idx >= ARCHETYPE_BY_LEAGUE.size():
		return "rushdown"
	return ARCHETYPE_BY_LEAGUE[idx]


## The champion `read` a league's titleholder has EARNED — the archetype's own verified line.
## ⚠️ `career.gd:CHAMPIONS[idx].read` is the OLD, unverifiable copy; this is the replacement, and
## the integrator note in the handover says exactly how to point the name/title at it.
static func champion_read(idx: int) -> String:
	return str(GAMEPLANS.get(archetype_for_league(idx), {}).get("read", ""))


## The `read` line for an archetype ID directly — the qualifying rounds of a cup carry a kind but
## not a titleholder, so the scouting screen needs the line without going through a league index.
static func read_for(gid: String) -> String:
	return str(GAMEPLANS.get(gid, {}).get("read", ""))


static func counter_for(gid: String) -> String:
	return str(GAMEPLANS.get(gid, {}).get("counter", ""))


static func champion_counter(idx: int) -> String:
	return str(GAMEPLANS.get(archetype_for_league(idx), {}).get("counter", ""))


## The slot-by-slot CLASS pattern for a team of `size`. Slot 0 is the archetype's most defining
## member on purpose — a Wood cup fields ONE monster (`teamSizeByLeague`), so the 1v1 champion has
## to read as its archetype all by itself. Beyond the authored pattern the list cycles.
static func archetype_classes(gid: String, size: int) -> Array:
	var pattern: Array = GAMEPLANS.get(gid, {}).get("classes", [])
	if pattern.is_empty():
		return []
	var out: Array = []
	for i in range(maxi(0, size)):
		out.append(pattern[i % pattern.size()])
	return out


## Deterministic gameplan pick for a scouted rival roster — used for the NON-champion rounds and
## for any standalone screen with no league context. A cup's champion does NOT come through here:
## it is authored per rung (`archetype_for_league`), because "the player learns a name, loses to
## it, trains for it, and takes it" only works if the name means the same thing every time.
static func gameplan_for(rival_names: Array) -> String:
	var ids: Array = GAMEPLANS.keys()
	var h := hash(", ".join(rival_names))
	return ids[abs(h) % ids.size()]


## Build the TEAM PLAN a gameplan implies, reduced to this file's v1 axis set.
##
## ⚠️ `enemy_roster` IS WHAT MAKES FOCUS-FIRE A REAL ARCHETYPE RATHER THAN A LABEL. `manmark`
## without a `markedUnit` falls straight through to the lowest-HP default in `pick_target()` — so
## for as long as nobody passed the opposing roster in, the "whole team piles onto one target"
## plan was byte-identical to no plan at all. The mark is the SOFTEST BODY (lowest CON), which is
## both the correct predator read and the thing the archetype's `read` line promises the player.
## Defaults to `[]` so every existing caller is unaffected.
static func team_plan_for_gameplan(gid: String, enemy_roster: Array = []) -> Dictionary:
	var g: Dictionary = GAMEPLANS.get(gid, {})
	var t: Dictionary = g.get("tactics", {})
	var plan := {"manaPolicy": t.get("manaPolicy", "normal"), "formation": t.get("formation", "tight")}
	if t.has("targetPriority"):
		plan["targetPriority"] = t["targetPriority"]
		if t["targetPriority"] == "manmark" and not enemy_roster.is_empty():
			var mark = softest_body(enemy_roster)
			if mark != null:
				plan["markedUnit"] = mark
	return plan


## Lowest-CON living monster in a roster — ties keep the earlier entry, so the pick is stable for
## a given roster order and the whole cup stays reproducible.
static func softest_body(roster: Array):
	var best = null
	var best_con := INF
	for m in roster:
		if m == null or not m.alive:
			continue
		var c := float(m.stats.get("CON", 0.0))
		if c < best_con:
			best_con = c
			best = m
	return best


## Build PER-MONSTER orders for a rival roster from its gameplan — every rival fights with the
## same temperament, uniformly, since a gameplan is a whole-team read, not an individual one.
static func orders_for_gameplan(gid: String, roster: Array) -> Dictionary:
	var g: Dictionary = GAMEPLANS.get(gid, {})
	var t: Dictionary = g.get("tactics", {})
	var orders := {}
	for m in roster:
		orders[m] = {"temperament": t.get("temperament", "balanced")}
	return orders


# ── Engine-facing logic. `battle_sim.gd` calls these three; see the patch text in the report for
## exactly where. Every one reproduces today's behaviour byte-for-byte when `tactics`/`plan` is
## empty — an order with no entry in the dictionary must fight exactly as it always has. ───────

## Single-target enemy pick. `tactics` is the MERGED (team-plan + per-monster-override) dict for
## the ACTING monster, built by `battle_sim.gd`'s `_effective_tactics()`.
static func pick_target(_attacker, candidates: Array, tactics: Dictionary):
	if candidates.is_empty():
		return null
	var priority: String = tactics.get("targetPriority", "")
	if priority == "manmark":
		var marked = tactics.get("markedUnit")
		if marked != null and candidates.has(marked):
			return marked
		# marked unit already dead or never set — fall through to the default below, same as an
		# order that names nobody. This is a real, watchable moment: a team ordered to man-mark a
		# target that already died goes back to picking on its own.
	elif priority == "tanks":
		return _highest_stat(candidates, "CON")
	elif priority == "casters":
		var casters: Array = candidates.filter(func(u): return u.role == "support")
		if not casters.is_empty():
			return _lowest_hp(casters)
		# no support left alive among the candidates — falls through to lowest-HP below.
	return _lowest_hp(candidates)


## Coverage for the ACTOR's own `allEnemies` move, gated by the DEFENDING side's formation —
## a loose defender is a worse target for area damage, regardless of how the attacker is arranged.
static func aoe_coverage(units: Array, defender_plan: Dictionary) -> Array:
	return _spread_subset(units, defender_plan)


## Coverage for the CASTER's own `team`-target buff/heal, gated by the CASTER's own formation —
## a loose team's supports don't reach the whole roster.
static func aura_coverage(units: Array, caster_plan: Dictionary) -> Array:
	return _spread_subset(units, caster_plan)


## The shared non-spatial approximation of docs/ARENA_BLUEPRINT.md §5's aura-vs-AoE trade: with no
## real positions to measure a radius against, "loose" is modelled as roughly half the roster
## (first half, by existing living-order — deterministic, no extra RNG draw so it can't perturb
## `battle_sim.gd`'s own seeded rng sequence) instead of all of it. ⚠️ THIS IS A HONEST
## APPROXIMATION, NOT A SIMULATION OF THE REAL TRADE — it can't yet be WATCHED happening (no
## positions to draw apart on screen), only its outcome measured. Worth redoing once the field
## engine has real ground to spread out on.
static func _spread_subset(units: Array, plan: Dictionary) -> Array:
	if plan.get("formation", "tight") != "loose":
		return units
	var keep := int(ceil(units.size() / 2.0))
	return units.slice(0, keep)


static func _lowest_hp(units: Array):
	var best = units[0]
	for u in units:
		if u.hp_frac() < best.hp_frac():
			best = u
	return best


static func _highest_stat(units: Array, stat: String):
	var best = units[0]
	var best_v: float = float(units[0].stats.get(stat, 0.0))
	for u in units:
		var v: float = float(u.stats.get(stat, 0.0))
		if v > best_v:
			best_v = v
			best = u
	return best


static func info_by_id(info_list: Array, id) -> Dictionary:
	for entry in info_list:
		if entry["id"] == id:
			return entry
	return {}
