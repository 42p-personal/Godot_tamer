## A LIVE MONSTER — runtime state for the mockup's stable/training/battle loop.
##
## Wraps the pure contract math (Classify/Derive) with mutable state a battle or training
## session actually needs to track. Deliberately thin: no save format, no lifespan/happiness/
## bloodline fields — this is the skeleton loop, not a port of `Monster` in `src/monster.ts`.
class_name MonsterInstance
extends RefCounted

var species_id: String
var species_name: String
var body: String
var flavour: String
var innate: Array = []

## Stable identity for this career slot — used as the seed key for the weekly RNG
## (`week.gd`), so training rolls are deterministic per (monster, week) and never
## drift between preview and apply. Defaults to species_id so scripts that build a
## monster ad-hoc (tests, probes) still get a stable key without setting one.
##
## ⚠️ `id` ALSO CARRIES THE LINEAGE, AND IT HAS TO. `save_game.gd` persists a fixed field list
## (speciesId/stats/id/stamina/happiness/ageWeeks/careerWeek/retired/potential/lifespanYears/
## foods/children) and it is not this workstream's file. A bred monster's generation, its
## emphasis and its heirloom move are the whole point of breeding — if they lived in plain
## fields they would be silently erased by the first save/load, and a Gen-4 dynasty would come
## back from lunch as a Gen-1 wild. So the lineage rides on the one string that IS persisted, as
## an appended `#gen,emph,moveId,stat,awakenAt` token.
##
## ⚠️ EVERY FIELD IN THE TOKEN IS FIXED AT BIRTH — nothing in it ever changes. That is not a
## coincidence, it is the constraint: `week.gd` seeds the training roll off `"%s:%d" % [mi.id,
## mi.career_week]`, so an `id` that mutated mid-career would silently re-roll the monster's
## entire remaining training. Whether the heirloom has AWAKENED is therefore DERIVED from the
## current stat (`heirloom_is_awake()`), never stored.
var id: String = "" : get = _get_id, set = _set_id
var _id_bare: String = ""

# ── LINEAGE (breeding_ui.gd / lab_ui.gd) ─────────────────────────────────────────────────────
## Dynasty depth. 1 = wild-caught or bought; a bred child is max(parents) + 1.
var generation: int = 1
## The stat the parents' head start was concentrated into at birth ("" = spread evenly). This is
## the player AIMING the child — see breeding_ui.gd's bequest.
var emphasis: String = ""
## The heirloom: one move from a parent's kit that this monster is BORN knowing, holding a
## reserved loadout slot regardless of its learn level. Dormant (60% power, riders stripped)
## until the heir trains `heirloom_stat` up to `heirloom_awaken_at` — the value its parent had on
## the day it was bequeathed. ⚠️ The bar is literally the ancestor's peak: the dynasty starts
## ahead and still has something left to prove.
var heirloom_move_id: String = ""
var heirloom_stat: String = ""
var heirloom_awaken_at: float = 0.0

## A dormant heirloom keeps its identity but not its edge (`src/signature.ts:SIGNATURE_DORMANT_MULT`).
const HEIRLOOM_DORMANT_MULT := 0.6

var stats: Dictionary = {}  # Stat -> float, CURRENT (post-training) values

# ── career/weekly-tick state (docs/CORE_LOOP_PORT.md §3, ported from src/game.ts Career) ──
var stamina: float = 100.0       # 0..MAX_STAMINA (week.gd.MAX_STAMINA) — the training gate
var happiness: int = 5           # 0..MAX_HAPPINESS (week.gd.MAX_HAPPINESS)
var age_weeks: int = 48          # starts as a Teen (WEEKS_PER_YEAR), mirrors START_AGE_WEEKS
var career_week: int = 0         # weeks of TRAINING taken — the RNG seed key, distinct from age
var retired: bool = false
var fed_this_week: bool = false
var last_food: String = ""       # for satiety (same food twice running halves the happiness gain)
var favourite_food: String = ""
var hated_food: String = ""
var potential: float = 1.0       # bloodline potential — multiplies the league stat cap
var lifespan_years: float = 8.0  # careerSpanYears equivalent — species base + bonuses, flattened here
var log: Array = []              # Array[String], most-recent-last (week.gd trims to 40)

# ── weekly PLAN state (docs/CORE_LOOP_PORT.md §2) ────────────────────────────────────────────
# ⚠️ THIS IS THE FIX FOR "i can still train infintely... this game does not loop": the stable
# screen used to call GameData.train() the instant a drill button was clicked. Now clicking a
# drill only writes a PLAN here — stats/stamina/gold move ONLY when the feeding phase resolves
# the week (feeding_ui.gd:_resolve_week). Nothing is spent by planning, by design.
const MAX_STAMINA := 100.0
const BASIC_STAMINA_COST := 10.0
const INTENSIVE_STAMINA_COST := 25.0
# ⚠️ PLACEHOLDER, NOT A PORT — src/game.ts rolls rest recovery 30%..100% of MAX_STAMINA per
# week (game.ts:302-305). This is a flat mid-point stand-in (CLAUDE.md: "the port is a skeleton,
# not a specification" — reproduce the shape, not the exact roll) until week.gd owns this.
const REST_STAMINA_RESTORE := 60.0
# Free fallback feeding cost — forage never costs gold, only stamina + happiness (CORE_LOOP_PORT
# §3: "hunger is never free, it is only ever paid differently"). Placeholder magnitude.
const FORAGE_STAMINA_COST := 8.0
const FORAGE_HAPPINESS_COST := 1

var plan_kind: String = "none"   # "none" | "train" | "rest" — "none" means the week does nothing
var plan_stat: String = ""       # set when plan_kind == "train"
var plan_intensive: bool = false
var plan_paired_stat: String = ""

var planned_food: String = ""    # food id chosen in the feeding phase; "" == forage (free fallback)


## Stamina cost of the CURRENT plan (0 for "none"/"rest" — rest spends no stamina, it restores it).
func plan_stamina_cost() -> float:
	if plan_kind != "train":
		return 0.0
	return INTENSIVE_STAMINA_COST if plan_intensive else BASIC_STAMINA_COST


## True if this monster has enough CURRENT stamina to carry out its own plan right now. Checked
## both when the plan is set (training_ui.gd disables the button) and again when the week
## resolves (stamina may have dropped further from foraging in between — see feeding_ui.gd).
func can_afford_plan() -> bool:
	return stamina >= plan_stamina_cost() - 0.001


func clear_plan() -> void:
	plan_kind = "none"
	plan_stat = ""
	plan_intensive = false
	plan_paired_stat = ""


# ── lineage: the id token ────────────────────────────────────────────────────────────────────

## The lineage suffix, or "" for a monster with nothing to pass on. Omitted entirely for an
## ordinary wild monster so ids of existing saves, probes and week plans are byte-identical.
func _lineage_suffix() -> String:
	if generation <= 1 and emphasis == "" and heirloom_move_id == "":
		return ""
	return "#%d,%s,%s,%s,%d" % [generation, emphasis, heirloom_move_id, heirloom_stat,
		roundi(heirloom_awaken_at)]


func _get_id() -> String:
	return _id_bare + _lineage_suffix()


func _set_id(value: String) -> void:
	var hash_at := value.find("#")
	if hash_at < 0:
		_id_bare = value
		return
	_id_bare = value.substr(0, hash_at)
	var parts: PackedStringArray = value.substr(hash_at + 1).split(",")
	# Tolerant on purpose: a truncated or future-format token degrades to "wild", never crashes a
	# load. Losing an heirloom is recoverable; refusing the save is not.
	generation = maxi(1, parts[0].to_int()) if parts.size() > 0 else 1
	emphasis = parts[1] if parts.size() > 1 else ""
	heirloom_move_id = parts[2] if parts.size() > 2 else ""
	heirloom_stat = parts[3] if parts.size() > 3 else ""
	heirloom_awaken_at = float(parts[4].to_int()) if parts.size() > 4 else 0.0

	# ⚠️ RE-DRAFT THE KIT WHEN A LINEAGE ARRIVES AFTER ONE ALREADY EXISTS.
	# `save_game.gd:_deserialize_roster` calls `assign_moveset()` and THEN assigns `mi.id` — so on
	# load the moveset is built before the heirloom is known, and a bequeathed move would silently
	# vanish across a save. That ordering is in another workstream's file; this guard fixes it from
	# the owning side. Measured: without it, "the heirloom is still in the reloaded kit" fails.
	# Only fires when a kit is already present, so `clone_for_preview()` (which copies `id` into a
	# blank monster before its stats exist) is untouched.
	if heirloom_move_id != "" and not moveset.is_empty():
		var redraft := RandomNumberGenerator.new()
		redraft.seed = hash(value)
		assign_moveset(redraft)


## The career-slot key WITHOUT the lineage token. Nothing needs this today (the token is
## immutable, so the full id is just as stable a seed) — it exists so a future save format that
## stores lineage properly can strip the token without hunting for the parsing.
func bare_id() -> String:
	return _id_bare


# ── lineage: the heirloom ────────────────────────────────────────────────────────────────────

static var _moves_by_id: Dictionary = {}


static func move_by_id(move_id: String) -> Dictionary:
	if move_id == "":
		return {}
	if _moves_by_id.is_empty():
		var loop := Engine.get_main_loop()
		var gd = (loop as SceneTree).root.get_node_or_null("GameData") if loop is SceneTree else null
		if gd == null:
			return {}
		for m in gd.moves:
			_moves_by_id[m.get("id", "")] = m
	return _moves_by_id.get(move_id, {})


## Record a bequest. ⚠️ `at` IS ROUNDED HERE AND ONLY HERE. The awaken bar makes a round trip
## through the id token as an integer, so an un-rounded 53.5 in memory comes back as 54 after a
## load and the monster's awaken bar silently moves. Measured — it failed the save/load check.
func set_heirloom(move_id: String, stat: String, at: float) -> void:
	heirloom_move_id = move_id
	heirloom_stat = stat
	heirloom_awaken_at = float(roundi(at))


## True once the heir has matched its ancestor's peak in the heirloom's stat. ⚠️ DERIVED, never
## stored — see the note on `id`. It flips the moment training crosses the bar, which is exactly
## when the player should feel it.
func heirloom_is_awake() -> bool:
	if heirloom_move_id == "":
		return false
	return float(stats.get(heirloom_stat, 0.0)) >= heirloom_awaken_at - 0.001


## The heirloom resolved to a move dict the battle sim can fight with, or {} if there is none.
## A dormant copy is a real move at 60% power with every rider effect stripped — worth a slot on
## a young heir, never worth as much as the parent's.
func heirloom_move() -> Dictionary:
	var base: Dictionary = move_by_id(heirloom_move_id)
	if base.is_empty():
		return {}
	var out: Dictionary = base.duplicate(true)
	if heirloom_is_awake():
		out["desc"] = "★ Heirloom — " + str(base.get("desc", ""))
		return out
	# ⚠️ DORMANCY SLOWS THE MOVE, IT DOES NOT GUT IT — AND THIS DELIBERATELY DEVIATES FROM
	# `src/signature.ts`, which strips `effects` and `status` outright. That works there because a
	# signature is drawn from a curated list of DAMAGE moves. Here ANY move in a parent's kit can
	# be bequeathed, and 24 of the pool's moves are control/debuff whose entire payload IS the
	# rider — stripping it turns a 0-power stun into a move that does literally nothing, which is
	# worse than inheriting no move at all. Measured: the first bequest the audit tried was
	# `Rallying Song`, power 0. So dormancy is priced in POWER and in COOLDOWN, both of which every
	# move has, and the heirloom always still functions.
	out["power"] = roundi(float(base.get("power", 0)) * HEIRLOOM_DORMANT_MULT)
	out["cooldown"] = snappedf(float(base.get("cooldown", 1.0)) / HEIRLOOM_DORMANT_MULT, 0.1)
	out["desc"] = "☆ Dormant heirloom — " + str(base.get("desc", ""))
	return out


## One line describing where this monster came from, for the stable and the breeding card.
func lineage_label() -> String:
	if generation <= 1 and heirloom_move_id == "":
		return "Wild stock — Gen 1"
	var bits: Array = ["Gen %d" % generation]
	if emphasis != "":
		bits.append("bred for %s" % emphasis)
	var h: Dictionary = move_by_id(heirloom_move_id)
	if not h.is_empty():
		if heirloom_is_awake():
			bits.append("★ %s awakened" % h.get("name", "?"))
		else:
			bits.append("☆ %s dormant (%s %d/%d)" % [h.get("name", "?"), heirloom_stat,
				int(stats.get(heirloom_stat, 0.0)), int(heirloom_awaken_at)])
	return " · ".join(bits)

# ── derived, recomputed whenever stats change ────────────────────────────────
var class_name_: String = "Generalist"
var role: String = "damage"
var mana_role: String = "damage"
var basic_attack: Dictionary = {}
var max_hp: int = 1
var max_mp: int = 0
var moveset: Array = []  # Array[Dictionary] — authored moves this monster currently knows

# ── battle-only runtime state, reset by BattleSim before each fight ──────────
var hp: float = 1.0
var mp: float = 0.0
var statuses: Array = []      # [{kind, until, from}]
var mods: Array = []          # [{atkMult?, accMod?, dodgeMod?, defMitDebuff?, ward?, guard?, regen?, hpRegen?, until}]
var cooldowns: Dictionary = {}  # move name -> seconds remaining ("__basic__" for the free attack)
var cc_resist: float = 0.0
var last_cc_at: float = -999.0
var has_acted: bool = false
var alive: bool = true

# identity for the battle log / UI
var side: String = ""  # "A" or "B"
var slot: int = 0


## ⚠️ THE PLAYER'S COMMITMENT. "" means UNCOMMITTED, and an uncommitted monster behaves EXACTLY as
## it always has — `recompute_class()` derives its class from its two highest stats every time it
## runs. That default is not timidity, it is the migration: every existing save, every rival, every
## market body and every probe monster loads and behaves byte-for-byte as before, and the feature
## only ever turns on where a player (or `_shape_to_class`) has said so out loud.
##
## ⚠️ AND THIS FIELD IS WHY `recompute_class()` DID NOT HAVE TO BE DELETED FROM ITS FIVE CALLERS.
## The overwrite problem (docs/CLASS_REWORK.md §10.2) was that a stored choice is stamped over by
## `week.gd`'s weekly tick, by `save_game.gd` on load, and by two UI screens that bypass
## `recompute_class()` altogether. Every one of those calls still runs, unchanged, in files this
## workstream does not own — they simply no longer have anything to overwrite, because the
## authority moved OUT of `class_name_` and into a field nothing else writes. The fix is at the
## chokepoint rather than at eleven call sites, which is the only version of it that could be
## verified rather than merely believed.
var assigned_class: String = ""


func is_class_assigned() -> bool:
	return assigned_class != ""


## Commit this monster to a trade. Does NOT gate — the caller checks
## `Classify.classes_available_for()` first, because the gate needs the monster's own nominal cap
## (league cap x potential) and this object does not know its league.
##
## ⚠️ PASS AN `rng` WHENEVER THE CLASS ACTUALLY CHANGES, OR THE KIT WILL NOT FOLLOW IT. Alignment
## between class and kit is the largest measured lever in the game (round 15: 5.50x on a
## byte-identical stat vector), and `week.gd:_redraft_if_stale` CANNOT rescue a forgotten redraw —
## it fires on `class_before != class_name_`, and after a reassignment those are already equal by
## the time the tick runs. So a reassignment without a redraw leaves the monster fighting its old
## trade's kit forever, silently, which is the exact failure this whole round exists to prevent.
## The rng is a parameter rather than a `RandomNumberGenerator.new()` because determinism is the
## contract — an entropy-seeded generator hidden inside this call is how `make_monster` once
## shipped a different monster every process.
func assign_class(cls: String, rng: RandomNumberGenerator = null) -> void:
	assigned_class = cls
	recompute_class()
	if rng != null:
		assign_moveset(rng)


## Return to the uncommitted state — class derives from stats again, as it always did.
func clear_class_assignment() -> void:
	assigned_class = ""
	recompute_class()


## Refresh everything downstream of stats. ⚠️ IT NO LONGER DECIDES THE CLASS OF A COMMITTED
## MONSTER — it only re-derives one for a monster that never committed. `role`, `mana_role` and
## `basic_attack` still track the monster every time, which is why the call had to be kept rather
## than removed: a Warrior that trains into a Tank's stat shape is still a Warrior, but its mana
## role and the power of its free attack must follow its actual body.
func recompute_class() -> void:
	class_name_ = assigned_class if assigned_class != "" else Classify.class_for_stats(stats)
	role = Classify.role_of_class(class_name_)
	mana_role = Classify.mana_role_of(stats, class_name_)
	basic_attack = Classify.basic_attack_for_class(class_name_, stats)


func recompute_pools() -> void:
	max_hp = Derive.max_hp(stats.get("CON", 0.0))
	max_mp = Derive.max_mana(stats.get("WIS", 0.0), stats.get("INT", 0.0))


## Pick a moveset from the class's affine lines, gated by the move's own learnLevel against the
## CURRENT value of the stat it's authored on. Up to 2 moves per line, capped at 6 total so a
## battle's move menu stays legible. ⚠️ Approximates `chooseLoadout` in spirit (affinity draws
## from `CLASS_LINES`) without its 1.35x affine-weighting pass — this mockup doesn't model a
## learned-vs-affine move pool distinction, every drafted move here IS affine by construction.
func assign_moveset(rng: RandomNumberGenerator) -> void:
	moveset.clear()
	# ⚠️ `GameData` is an autoload, and autoload GLOBALS do not exist under `--headless --script`
	# (SceneTree script mode) — a bare `GameData.x` is a COMPILE error there, which silently took
	# this whole script (and everything that preloads it, including the spatial self-tests) down
	# with it: `.new()` on the uncompiled script fails, teams come back empty, the sim reports a
	# 0-frame draw. Resolve the singleton dynamically instead — identical in-game, null in script
	# mode (where callers construct monsters directly and never call this).
	var game_data = null
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		game_data = (loop as SceneTree).root.get_node_or_null("GameData")
	if game_data == null:
		push_warning("assign_moveset: GameData autoload unavailable (headless script mode?) — moveset left empty")
		return
	var lines: Array = game_data.class_lines.get(class_name_, [])

	# ⚠️ `Generalist` IS A REAL CLASS WITH NO ENTRY IN `classLines`, AND WITHOUT THIS IT DRAFTS AN
	# EMPTY KIT. `classify.gd:class_for_stats` returns "Generalist" whenever no authored stat pair
	# matches, `classify.gd` gives it a CLASS_BASIC so it has a free attack, and `data.json`'s
	# classLines table has 18 keys and Generalist is not one of them — so `lines` came back [],
	# every bucket below stayed empty, and `moveset.clear()` at the top of this function left the
	# monster with NOTHING but its basic attack, permanently.
	#
	# ⚠️ THIS WAS A LIVE, SHIPPED BUG, NOT ONLY A PROBE ONE. `save_game.gd:_deserialize_roster`
	# calls `assign_moveset()` on load, so any saved Generalist reloaded weaponless. It stayed
	# invisible only because nothing else re-drafted a kit after creation; the moment `week.gd`
	# started re-drafting on a class change it became catastrophic, because the autopilot's
	# "train the lowest stat" policy walks every monster toward a perfectly FLAT spread — which
	# is precisely the definition of Generalist. Measured: the career arc collapsed from clearing
	# Gold at week 442 to stalling at WOOD with 1 round won in 114, every fielded body carrying
	# zero moves.
	#
	# The fallback is the honest reading of what a Generalist IS: a monster with no committed
	# pair, so it draws from the lines of whatever two stats it happens to lead on. That keeps
	# CLAUDE.md's rule that no build is locked out of a role, and it is derived rather than
	# authored — `data/*.json` is generated and must never be hand-edited.
	if lines.is_empty():
		lines = _fallback_lines(game_data)

	# ⚠️ THE OLD RULE WAS "top 2 by learnLevel per line", AND IT MADE WHOLE CATEGORIES OF AUTHORED
	# CONTENT UNDRAFTABLE. `learnLevel` is a power proxy, so sorting by it and taking the top two
	# ranks every line by power — and CONTROL MOVES ARE DELIBERATELY LOW-POWER. Measured: only
	# 4 of 24 control/debuff moves (17%) could ever be candidates, seven whole lines had control
	# content where NONE was draftable, and across 20 MAXED monsters (every stat at the Tamers
	# Apex ceiling) `type: control` was drafted 0 times out of 114 move slots.
	#
	# ⚠️ THIS IS THE SAME FAILURE `lines.ts` WAS CREATED TO FIX, REPRODUCED IN THE PORT. That file
	# exists because "three separate waves of authored content never reached a kit" and control
	# measured 0% equipped for exactly this reason. The line system fixed WHERE a kit draws from;
	# it never fixed the ranking INSIDE a line.
	#
	# A kit is now drafted by ROLE rather than by power: the strongest thing from each line, then
	# a deliberate reservation for utility. That is what a real loadout looks like, and it is what
	# makes every mechanic built on control — interrupts, cleanse, peel — actually reachable.
	var picks: Array = []
	var utility: Array = []
	for line in lines:
		var pool: Array = game_data.moves_by_line.get(line, [])
		var learnable: Array = []
		for m in pool:
			var stat: String = m["stat"]
			if float(stats.get(stat, 0.0)) >= float(m["learnLevel"]):
				learnable.append(m)

		# ⚠️ A FLOOR, SO A YOUNG MONSTER IS NOT WEAPONLESS. The pool's lowest learnLevel is 40 and
		# a fresh monster averages ~32 across its stats, so a starter qualified for NOTHING in most
		# lines and fielded 1.3 moves out of six — the whole early game ran on basic attacks. If a
		# line offers nothing yet, it still offers its CHEAPEST move. Deliberately not a general
		# relaxation: every other move stays gated, so the kit still grows with the monster.
		if learnable.is_empty() and not pool.is_empty():
			var cheapest = pool[0]
			for m in pool:
				if float(m["learnLevel"]) < float(cheapest["learnLevel"]):
					cheapest = m
			learnable.append(cheapest)

		learnable.sort_custom(func(a, b): return a["learnLevel"] > b["learnLevel"])
		# The strongest of the line is always a candidate — a kit should have teeth.
		if not learnable.is_empty():
			picks.append(learnable[0])
		# Everything else in the line is a candidate too, but utility is kept in its own bucket so
		# it can be RESERVED a slot rather than competing on a number it was never authored to win.
		for i in range(1, learnable.size()):
			var m = learnable[i]
			if str(m.get("type", "damage")) in ["control", "debuff"]:
				utility.append(m)
			else:
				picks.append(m)

	# Fisher-Yates using the passed-in RNG, not `Array.shuffle()` — that call reseeds from
	# Godot's global RNG state, which would make moveset assignment non-reproducible even when
	# the caller explicitly passed a seeded generator.
	for arr in [picks, utility]:
		for i in range(arr.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp = arr[i]
			arr[i] = arr[j]
			arr[j] = tmp

	# ⚠️ RESERVED SLOTS, NOT A PREFERENCE. Up to two of six go to utility when the monster has any
	# available. A weighting would have left this to chance and chance is what produced 0 of 114.
	var candidates: Array = []
	for i in range(mini(2, utility.size())):
		candidates.append(utility[i])
	candidates.append_array(picks)
	for i in range(2, utility.size()):
		candidates.append(utility[i])

	# ⚠️ THE HEIRLOOM TAKES A RESERVED SLOT, AND IT MUST BE RESERVED RATHER THAN RANKED.
	# The whole promise breeding makes is "this child will have THIS move". A weighting would
	# have left it to chance, and this file already carries the scar of exactly that mistake one
	# comment block up: control moves competed on a power number they were never authored to win
	# and measured 0 drafted out of 114 slots. A bequest the player paid 300g for and cannot see
	# in the fight is worse than no bequest at all.
	#
	# ⚠️ AND IT IGNORES `learnLevel` ON PURPOSE. A newborn heir qualifies for almost nothing (the
	# pool's floor is 40 and a fresh monster averages ~32), so gating the heirloom would mean the
	# inheritance did not exist for the first year of the child's life — the exact window in which
	# the player is deciding whether breeding was worth doing. The dormant multiplier is what
	# prices the early access; the level gate would just delete it.
	var heir: Dictionary = heirloom_move()
	if not heir.is_empty():
		var heir_name: String = str(heir.get("name", ""))
		# Drop any learned copy of the same move — `cooldowns` is keyed by move NAME, so two
		# entries sharing a name would share one cooldown and the duplicate would read as a bug.
		var deduped: Array = []
		for m in candidates:
			if str(m.get("name", "")) != heir_name:
				deduped.append(m)
		candidates = deduped
		moveset.append(heir)

	for m in candidates:
		if moveset.size() >= 6:
			break
		moveset.append(m)


## A scratch copy carrying only the fields the weekly tick reads/mutates — used by
## `week.gd.preview_week()` so the preview can run the EXACT SAME code path as
## `apply_week()` on a throwaway copy and diff the result, rather than a second
## hand-written estimate that could drift from it (docs/CORE_LOOP_PORT.md §3, the
## "RNG discipline" rule). Battle-only fields (hp/mp/statuses/moveset/etc.) are not
## needed for the tick and are left at class defaults.
func clone_for_preview():
	var m = get_script().new()
	m.id = id
	m.species_id = species_id
	m.body = body
	m.stats = stats.duplicate()
	# ⚠️ THE COMMITMENT TRAVELS WITH THE PREVIEW. `week.gd.preview_week()` runs the REAL
	# `apply_week` on this copy and diffs the result, so a copy that arrived uncommitted would
	# re-derive its class inside the preview and the stable screen would quote a different class
	# (and a different free attack) from the one the week actually produces.
	m.assigned_class = assigned_class
	m.class_name_ = class_name_
	m.max_hp = max_hp
	m.max_mp = max_mp
	m.hp = hp
	m.mp = mp
	m.stamina = stamina
	m.happiness = happiness
	m.age_weeks = age_weeks
	m.career_week = career_week
	m.retired = retired
	m.fed_this_week = fed_this_week
	m.last_food = last_food
	m.favourite_food = favourite_food
	m.hated_food = hated_food
	m.potential = potential
	m.lifespan_years = lifespan_years
	m.log = log.duplicate()
	# Plan state too — a preview of the week has to know what the week WOULD do, same as apply.
	m.plan_kind = plan_kind
	m.plan_stat = plan_stat
	m.plan_intensive = plan_intensive
	m.plan_paired_stat = plan_paired_stat
	m.planned_food = planned_food
	return m


func hp_frac() -> float:
	return 0.0 if max_hp <= 0 else clampf(hp / float(max_hp), 0.0, 1.0)


func mp_frac() -> float:
	return 0.0 if max_mp <= 0 else clampf(mp / float(max_mp), 0.0, 1.0)


func reset_for_battle() -> void:
	hp = float(max_hp)
	mp = float(max_mp)
	statuses = []
	mods = []
	cooldowns = {}
	cc_resist = 0.0
	last_cc_at = -999.0
	has_acted = false
	alive = true


func has_status(kind: String) -> bool:
	for s in statuses:
		if s["kind"] == kind:
			return true
	return false


func is_incapacitated() -> bool:
	for s in statuses:
		if StatusMath._rule(s["kind"]).get("incapacitates", false):
			return true
	return false


## The lines a class-less monster may draw from: every line whose moves are authored on one of
## this monster's two highest stats. Deterministic (stat order is `Classify.STATS`), derived from
## the generated move table rather than a hand-written map, and never empty — if even that finds
## nothing it falls back to every line in the game, because a monster with no moves is not a
## design outcome anyone chose.
func _fallback_lines(game_data) -> Array:
	var order: Array = []
	for s in Classify.STATS:
		order.append({"stat": s, "v": float(stats.get(s, 0.0))})
	order.sort_custom(func(a, b): return float(a["v"]) > float(b["v"]))
	var top: Array = []
	for i in range(mini(2, order.size())):
		top.append(str(order[i]["stat"]))
	var out: Array = []
	for line in game_data.moves_by_line.keys():
		var pool: Array = game_data.moves_by_line[line]
		if pool.is_empty():
			continue
		if str(pool[0].get("stat", "")) in top:
			out.append(line)
	if out.is_empty():
		out = game_data.moves_by_line.keys()
	out.sort()
	return out
