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


## ⚠️ `deploy_a`/`intents_a` ARE FORWARD-COMPATIBLE PLUMBING, NOT A LIVE HOOK YET. `tactics_ui.gd`'s
## deployment board (`docs/UX_DEPLOYMENT.md`) computes a real per-monster start position and a
## positional-intent choice — but `spatial_sim.gd::_deploy()` still always calls
## `Spatial.deploy_positions()` and has no override, and `spatial_ai.gd` has no concept of
## positional intent at all. Recording the real data here now means the day someone extends those
## two functions (stream A's files, not this one's), the data is already flowing rather than
## needing a second pass through this screen. Until then these two keys are written and read by
## nobody but a future consumer — same status as `statScale` being "FIELD-ONLY" for a stretch
## before the field engine read it.
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
## from *who do I attack* (`TARGET_PRIORITY_INFO`). ⚠️ NOT YET CONSUMED BY THE ENGINE: neither
## `spatial_sim.gd` nor `spatial_ai.gd` reads a per-monster intent today (checked directly —
## `spatial_ai.gd` only reads `tactics.formation`). `deployment_board.gd` still shows and stores
## it, honestly labelled as a hint rather than a simulated behaviour, per this file's own standing
## doctrine (see the header comment above): don't build a control implying a mechanic the engine
## doesn't run, but a PLANNING tool with truthful copy is not that failure mode.
const POSITIONAL_INTENT_INFO := [
	{"id": "hold", "icon": "⚓", "name": "Hold", "desc": "Keep the line near where you deployed."},
	{"id": "push", "icon": "➡", "name": "Push", "desc": "Advance on the enemy line, take ground."},
	{"id": "wings", "icon": "↗", "name": "Wings", "desc": "Work wide, approach from the flank."},
	{"id": "dive", "icon": "⤴", "name": "Dive", "desc": "Go around or through for the enemy back line."},
	{"id": "guard", "icon": "🛡", "name": "Guard", "desc": "Stay near a named ally and intercept threats to it."},
]


# ── Rival gameplans (LOOP_DESIGN.md Phase 3 / `core.ts:GAMEPLANS`) — presentation text only.
## The full TS record also drives team GENERATION (`mix`, `wants`) — out of scope for this
## screen, which only needs the scouting read: name, tell, counter, win condition, and the team
## plan the gameplan implies. `formation` per gameplan has no TS source (formation is field-engine
## only there) — the choices below are this file's own extrapolation from each plan's winCon, not
## a port, and are called out as such. ─────────────────────────────────────────────────────────
const GAMEPLANS := {
	"rushdown": {
		"name": "Rushdown", "icon": "🔥",
		"tell": "Fast, aggressive, no support — all pressure.",
		"counter": "They rush your softest monster and spend big early. Put a tank up front, or burst them before they snowball.",
		"winCon": "Kill something in the first few exchanges and snowball the numbers advantage.",
		"tactics": {"temperament": "aggressive", "manaPolicy": "normal", "formation": "tight"},
	},
	"bulwark": {
		"name": "Bulwark", "icon": "🛡",
		"tell": "Tanks and guardians around a protected carry.",
		"counter": "They turtle around one damage dealer. Grind the wall down, or focus the protected monster before its guards react.",
		"winCon": "Keep one carry alive behind a wall until it out-damages everything you have left.",
		"tactics": {"temperament": "cautious", "manaPolicy": "conserve", "formation": "tight"},
	},
	"attrition": {
		"name": "Attrition", "icon": "☠",
		"tell": "Poison, bleed and stall — out-lasts you.",
		"counter": "They drag the fight long and out-sustain you. End it fast, or bring cleanse and healing to weather it.",
		"winCon": "Stack damage-over-time on everything and outlive the clock.",
		"tactics": {"temperament": "cautious", "manaPolicy": "conserve", "formation": "loose"},
	},
	"focusfire": {
		"name": "Focus-Fire", "icon": "🎯",
		"tell": "High burst — the whole team piles onto one target.",
		"counter": "They assassinate one of your monsters early. Protect your carry, or spread durability so no single loss breaks you.",
		"winCon": "Mark one monster and delete it before it acts twice.",
		"tactics": {"temperament": "aggressive", "targetPriority": "manmark", "manaPolicy": "normal", "formation": "tight"},
	},
	"zone": {
		"name": "Zone", "icon": "🌩",
		"tell": "Back-row casters hunting your fragile monsters.",
		"counter": "They hunt your casters. Shield your back line, or lead with a durable front they have to chew through first.",
		"winCon": "Blanket the whole team in area damage and never trade one-for-one.",
		"tactics": {"temperament": "balanced", "targetPriority": "casters", "manaPolicy": "normal", "formation": "loose"},
	},
}


## Deterministic gameplan pick for a scouted rival roster — no persistent scouting system exists
## in this slice (meta-game is not ported, per CLAUDE.md's "skeleton, not specification"), so this
## screen treats the rival as fully scouted and needs only a stable, reproducible choice.
static func gameplan_for(rival_names: Array) -> String:
	var ids: Array = GAMEPLANS.keys()
	var h := hash(", ".join(rival_names))
	return ids[abs(h) % ids.size()]


## Build the TEAM PLAN a gameplan implies, reduced to this file's v1 axis set.
static func team_plan_for_gameplan(gid: String) -> Dictionary:
	var g: Dictionary = GAMEPLANS.get(gid, {})
	var t: Dictionary = g.get("tactics", {})
	var plan := {"manaPolicy": t.get("manaPolicy", "normal"), "formation": t.get("formation", "tight")}
	if t.has("targetPriority"):
		plan["targetPriority"] = t["targetPriority"]
	return plan


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
