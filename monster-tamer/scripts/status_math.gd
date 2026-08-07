## STATUS APPLICATION AND CC DIMINISHING RETURNS, PORTED FROM `statusMath.ts`.
##
## ⚠️ THIS IS THE BALANCE GUARD-RAIL THE PORT MOST NEEDS TO CARRY. Diminishing returns are the
## hard cap on the lockout build: control on the same target lands 100/75/50/25/immune, and CON
## puts a FLOOR under the meter so a Juggernaut cannot be chained the way a caster can. Drop any
## part of it and the new engine ships an unanswerable comp — which would surface as a balance
## complaint months later, not as a failing test.
##
## ⚠️ AND THE LURCH IS REPORTED, NOT PERFORMED. Charm drags its victim toward the charmer; that
## is a position write, so it belongs to whatever navigation this engine ends up using. This
## file returns the distance and lets the caller move the body.
##
## Verified against `data/status.json` — 31 cases, 8 axes.
class_name StatusMath
extends RefCounted

const CC_DR_STEP := 0.25
const SECONDS_PER_ROUND := 2.0

## ⚠️ DELIBERATELY NOT EVERY DEBUFF. poison/burn/bleed/vulnerable/doom/healblock hurt you but
## leave you playing the game. Putting them on the DR meter would let a damage-over-time kit
## burn away the protection that exists to guard against LOCKOUT — the exact thing DR is for.
const HARD_CONTROL := ["stun", "sleep", "fear", "charm", "silence", "knockback", "confusion"]

## ⚠️ THE STATUS TABLE IS LOADED AS DATA, NOT TRANSCRIBED. The first cut of this file
## hardcoded `MAX_STACKS = {"bleed": 3}` and `LURCH_TO_SOURCE = {"charm": 2.5}` — two entries
## out of fifteen, copied by hand because they were the only two `apply_status` reads today.
## Add a second stacking status in `status.ts` and this file would have silently not stacked
## it, with nothing failing. `data.json` carries the whole table; there is one source of truth.
const DATA_PATH := "res://data/data.json"
static var _field_status: Dictionary = {}


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
	var t := _table()
	var r = t.get(kind)
	return r if r is Dictionary else {}


static func _refuse(reason: String, statuses: Array, cc_resist: float, touched: bool) -> Dictionary:
	return {
		"applied": false, "refusedBecause": reason, "statuses": statuses,
		"ccResist": cc_resist, "seconds": 0.0, "lurch": 0.0, "ccMeterTouched": touched,
	}


## Apply one status, resolving diminishing returns and stacking.
static func apply_status(inp: Dictionary) -> Dictionary:
	var kind: String = inp["kind"]
	var statuses: Array = inp["statuses"]
	var cc_resist := float(inp["ccResist"])

	if bool(inp["targetDead"]):
		return _refuse("dead", statuses, cc_resist, false)

	var seconds := float(inp["rounds"]) * SECONDS_PER_ROUND
	var touched := false
	var now := float(inp["now"])

	if kind in HARD_CONTROL:
		# Cleansed targets are briefly immune, so a cleanse cannot be undone by the next cast
		# in the same breath.
		if now < float(inp["ccImmuneUntil"]):
			return _refuse("immune", statuses, cc_resist, false)
		# ⚠️ CON RESISTS CONTROL NATIVELY, AS A FLOOR ON THE METER RATHER THAN A SEPARATE ROLL.
		# A high-CON unit starts partway up the DR curve instead of getting a chance to dodge
		# control outright.
		#
		# ⚠️ THE FLOOR SATURATES AT CON 900, NOT 3000. `min(0.3, CON/3000)` reaches its cap at
		# 900, so every CON above that buys exactly zero extra control resistance. The divisor
		# reads as though it scales to 3000 and it does not.
		var con_floor: float = minf(0.3, float(inp["targetCon"]) / 3000.0)
		var resist: float = minf(1.0, maxf(cc_resist, con_floor))
		seconds *= 1.0 - resist
		cc_resist = minf(1.0, maxf(float(inp["ccResist"]), con_floor) + CC_DR_STEP)
		touched = true
		if seconds <= 0.05:
			# Fully diminished — the control simply fails. ⚠️ THE METER STILL ADVANCED, so the
			# attempt costs the caster its cooldown either way. That is what stops
			# spam-until-it-sticks from being free.
			return _refuse("fullyDiminished", statuses, cc_resist, true)

	var until := now + seconds
	var next: Array = []
	for s in statuses:
		next.append({"kind": s["kind"], "until": s["until"], "from": s["from"]})

	var rule := _rule(kind)
	if rule.has("maxStacks"):
		var n := 0
		for s in next:
			if s["kind"] == kind:
				n += 1
		if n >= int(rule["maxStacks"]):
			return _refuse("maxStacks", statuses, cc_resist, touched)
		next.append({"kind": kind, "until": until, "from": inp["from"]})
	else:
		var found := false
		for s in next:
			if s["kind"] == kind:
				# ⚠️ REFRESH TAKES THE LONGER OF THE TWO, NEVER THE NEWER. A short
				# re-application must not cut a long one short, or a cheap spam move becomes a
				# soft dispel of the expensive one.
				s["until"] = maxf(float(s["until"]), until)
				s["from"] = inp["from"]  # whoever applied it last is what fear runs from
				found = true
				break
		if not found:
			next.append({"kind": kind, "until": until, "from": inp["from"]})

	return {
		"applied": true, "refusedBecause": null, "statuses": next, "ccResist": cc_resist,
		"seconds": seconds, "lurch": float(rule.get("lurchToSource", 0.0)),
		"ccMeterTouched": touched,
	}
