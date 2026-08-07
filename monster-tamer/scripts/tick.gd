## THE PER-TICK UNIT UPDATE, PORTED FROM `tickMath.ts`.
##
## ⚠️ THIS IS WHERE A FIGHT'S PACING LIVES. Damage decides how hard a blow lands; this decides
## how often anyone can throw one and how long they survive between blows. Get this wrong and
## you produce fights of the wrong LENGTH with perfectly correct damage numbers — the hardest
## discrepancy to localise, because every individual hit checks out.
##
## ⚠️ AND THE STEP ORDER IS THE CONTRACT, NOT AN IMPLEMENTATION DETAIL. Cooldowns, then mana,
## then health regen, then the CC meter, then attrition and expiry. Moving attrition ahead of
## regen would let a damage-over-time out-race a heal that should have landed first.
##
## ⚠️ THE TIMERS MUST TICK BEFORE ANY KNOCKBACK HANDLING. The TypeScript engine's own comment
## records the cost of learning this: with the shove placed above the timers, a golden fight
## went from 15s to 91.5s, because pausing every clock for a 0.25s stagger turned a stagger
## into a fight-long stalemate. Being shoved costs tempo, never recovery.
##
## ⚠️ PER THE STANDING RULE IN CLAUDE.md, THESE RATES ARE A STARTING POINT, NOT A TARGET.
## They are what the TypeScript does today. Reproduce them so a deliberate change is
## distinguishable from a translation bug — then change them freely.
##
## Verified against `data/tick.json` — 34 cases, 8 axes.
class_name Tick
extends RefCounted

const SECONDS_PER_ROUND := 2.0
const WIS_REGEN_DIVISOR := 200.0
const MANA_SUPPORT_PER_SEC := 1.0
## Seconds without control before the diminishing-returns meter clears.
const CC_DR_RESET := 3.0

const SUDDEN_DEATH_AT := 255.0    ## seconds
const SUDDEN_DEATH_BASE := 0.010  ## fraction of maxHp per second at onset
const SUDDEN_DEATH_RAMP := 0.004  ## added per further second

const DATA_PATH := "res://data/data.json"
static var _field_status: Dictionary = {}


## ⚠️ THE STATUS TABLE IS LOADED AS DATA, NEVER TRANSCRIBED. Hand-copying the two or three
## entries this file happens to read today is how a later status silently stops working —
## already caught once in `status_math.gd`. One source of truth, and it is `data.json`.
static func _table() -> Dictionary:
	if _field_status.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f == null:
			push_error("cannot open %s — run ./run_contract.sh" % DATA_PATH)
			return {}
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary and parsed.has("fieldStatus"):
			_field_status = parsed["fieldStatus"]
	return _field_status


static func _rule(kind: String) -> Dictionary:
	var r = _table().get(kind)
	return r if r is Dictionary else {}


static func _has_block_heal(statuses: Array) -> bool:
	for s in statuses:
		if _rule(s["kind"]).get("blockHeal", false):
			return true
	return false


## Advance one unit by one tick.
static func tick_unit(inp: Dictionary) -> Dictionary:
	var dt := float(inp["dt"])
	var now := float(inp["now"])
	var statuses: Array = inp["statuses"]
	var mods: Array = inp["mods"]

	# ── timers ────────────────────────────────────────────────────────────────
	var cooldowns := {}
	var in_cd: Dictionary = inp["cooldowns"]
	for k in in_cd:
		cooldowns[k] = maxf(0.0, float(in_cd[k]) - dt)

	# ── MANA REGEN ────────────────────────────────────────────────────────────
	# WIS is the caster's engine and the sole regen stat. A SUPPORT earns a steady trickle on
	# top: it neither soaks nor connects reliably, so TIME is its resource.
	# ⚠️ `regen` MODS ARE AUTHORED PER ROUND AND PAID PER SECOND. Skip that conversion and the
	# buff is worth SECONDS_PER_ROUND times too much.
	var mod_regen := 0.0
	for m in mods:
		mod_regen += float(m.get("regen", 0.0))
	var regen := float(inp["wis"]) / WIS_REGEN_DIVISOR \
		+ (MANA_SUPPORT_PER_SEC if bool(inp["isSupport"]) else 0.0) \
		+ mod_regen / SECONDS_PER_ROUND
	var mp: float = minf(float(inp["maxMp"]), float(inp["mp"]) + regen * dt)

	# ── HP REGEN ──────────────────────────────────────────────────────────────
	# Gated on `blockHeal` like every other restore, or healblock has a hole in it.
	var hp := float(inp["hp"])
	var max_hp := float(inp["maxHp"])
	var mod_hp_regen := 0.0
	for m in mods:
		mod_hp_regen += float(m.get("hpRegen", 0.0))
	if mod_hp_regen > 0.0 and not _has_block_heal(statuses):
		hp = minf(max_hp, hp + (mod_hp_regen / SECONDS_PER_ROUND) * dt)

	# ── CC METER DECAY ────────────────────────────────────────────────────────
	# The other half of diminishing returns. Without decay, one early stun taxes every later
	# one for the rest of the fight.
	var cc_resist := float(inp["ccResist"])
	if cc_resist > 0.0 and now - float(inp["lastCcAt"]) >= CC_DR_RESET:
		cc_resist = 0.0

	# ── attrition, expiry, and the one status that pays out ON expiry ─────────
	var kept_mods: Array = []
	for m in mods:
		if now < float(m["until"]):
			kept_mods.append(m)

	var attrition := 0.0
	var expired: Array = []
	var kept_statuses: Array = statuses

	if not statuses.is_empty():
		for s in statuses:
			var rule := _rule(s["kind"])
			if rule.has("hpPerSec"):
				attrition += max_hp * float(rule["hpPerSec"]) * dt
			# ⚠️ APPLIED IMMEDIATELY AND SEQUENTIALLY, not accumulated like the HP drain,
			# because it floors at 0 — accumulating first would let two drains take a unit
			# below empty and then clamp, which is a different number.
			if rule.has("mpPerSec"):
				mp = maxf(0.0, mp - float(inp["maxMp"]) * float(rule["mpPerSec"]) * dt)

		# ⚠️ DOOM IS A COUNTDOWN, NOT A DRIP. It does nothing until its timer runs out and then
		# hits for a quarter of the victim's health. Cleansing it or killing the caster in time
		# is the whole counterplay, so it MUST resolve ON EXPIRY rather than being dropped by
		# the filter below.
		var survivors: Array = []
		for s in statuses:
			if now >= float(s["until"]):
				expired.append(s["kind"])
				var det = _rule(s["kind"]).get("detonate")
				if det != null:
					attrition += max_hp * float(det)
			else:
				survivors.append(s)
		if survivors.size() != statuses.size():
			kept_statuses = survivors

	if attrition > 0.0:
		hp -= attrition
	var dead := false
	if hp <= 0.0:
		hp = 0.0
		dead = true

	return {
		"hp": hp, "mp": mp, "statuses": kept_statuses, "mods": kept_mods,
		"cooldowns": cooldowns, "ccResist": cc_resist, "dead": dead,
		"expired": expired, "attrition": attrition,
	}


## The clock itself starts killing, harder every second, so no pair of teams can stall each
## other past the cap.
##
## ⚠️ SEPARATE FROM `tick_unit` BECAUSE THE ENGINE APPLIES IT IN A SEPARATE PASS, after every
## unit has ticked. Folding it in would change the HP a unit dies on when attrition and the
## clock land in the same tick.
static func sudden_death_loss(now: float, max_hp: float, dt: float) -> float:
	if now < SUDDEN_DEATH_AT:
		return 0.0
	var rate := SUDDEN_DEATH_BASE + (now - SUDDEN_DEATH_AT) * SUDDEN_DEATH_RAMP
	return max_hp * rate * dt
