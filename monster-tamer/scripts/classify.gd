## WHAT A MONSTER IS — class, composition role, mana role, and the free attack.
##
## ⚠️ THIS IS UPSTREAM OF ALMOST EVERYTHING ELSE. Class picks the free attack; the free attack
## sets reach; mana role decides how a unit refuels; `CLASS_LINES` keys ability affinity off the
## class name. Get this wrong and every downstream system is subtly wrong for reasons that never
## point back here.
##
## ⚠️ CLASS IS EMERGENT AND RECOMPUTED, NEVER STORED. It comes from a monster's two CURRENT
## highest stats, so training genuinely changes what a monster IS. Any species can in principle
## train into any class; aptitude only weights how fast each stat grows. **Never write flavour
## text or UI as if a species is destined for its class.**
##
## Verified against `data/classify.json` — 46 cases, 4 axes.
class_name Classify
extends RefCounted

## ⚠️ ORDER IS LOAD-BEARING. Ties between two equal stats resolve by this declaration order —
## arbitrary, but STABLE, and a port that "fixes" it into a different arbitrary answer silently
## reclassifies a slice of the population.
const STATS := ["STR", "DEX", "CON", "WIS", "INT", "CHA"]

## Flat floor so an untrained monster can still swing for something.
const BASIC_BASE_POWER := 4.6
const BASIC_STAT_SCALE := 1.0 / 98.0
## Physical swings hit; caster jabs do not. The free attack is not every class's equal.
const BASIC_STAT_TIER := {
	"STR": 0.70, "DEX": 0.63, "INT": 0.56, "CON": 0.49, "CHA": 0.42, "WIS": 0.35,
}
## ⚠️ A FOURTH AUTHORED COOLDOWN IN A FOURTH PLACE — inline here, not in any of the three pool
## files. It was already written in seconds while still being fed through `* COOLDOWN_MULT`;
## retiring that multiplier without scaling this made the single highest-frequency action in the
## game 30% faster, moved three goldens by up to 5.4s, and read as a balance change rather than
## the missed conversion it was.
const BASIC_COOLDOWN := 0.715
const BASIC_ACCURACY := 90.0
const BASIC_CAST_TIME := 0.15

const DATA_PATH := "res://data/data.json"
static var _data: Dictionary = {}


static func _load() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f == null:
			push_error("cannot open %s — run ./run_contract.sh" % DATA_PATH)
			return {}
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			_data = parsed
	return _data


## The monster's two highest stats, in order. Ties break by `STATS` order.
static func _top_two(stats: Dictionary) -> Array:
	var ordered := STATS.duplicate()
	# ⚠️ A STABLE SORT IS REQUIRED, and GDScript's `sort_custom` is NOT stable. Comparing only
	# on value would let equal stats come back in any order and make class assignment
	# non-deterministic between runs. The index tiebreak below makes it total.
	ordered.sort_custom(func(a, b):
		var va := float(stats.get(a, 0))
		var vb := float(stats.get(b, 0))
		if va == vb:
			return STATS.find(a) < STATS.find(b)
		return va > vb)
	return [ordered[0], ordered[1]]


## Derive the class from current stats. Falls back to `Generalist`, which is a REAL class with a
## real free attack — not an error state. It is ~3% of the population.
static func class_for_stats(stats: Dictionary) -> String:
	var pair := _top_two(stats)
	var classes: Array = _load().get("classes", [])
	for c in classes:
		if c.get("primary") == pair[0] and c.get("secondary") == pair[1]:
			return c["name"]
	return "Generalist"


## Team-COMPOSITION role.
##
## ⚠️ TANKS COUNT AS SUPPORT HERE, and that is not a bug. It is a composition label — a Tank is
## not a damage pick — and it drives rival-team templates. Spatially a Tank is a front-line
## anchor, which is a different question with a different answer. Two labels, two purposes.
static func role_of_class(class_name_: String) -> String:
	var roles := {
		"Warrior": "damage", "Rogue": "damage", "Ranger": "damage", "Wizard": "damage",
		"Spellsword": "damage", "Captain": "damage",
		"Tank": "support", "Spellshield": "support", "Sage": "support",
		"Orator": "support", "Bard": "support",
		"Evoker": "damage", "Skirmisher": "damage", "Stalker": "damage",
		"Swashbuckler": "damage",
		"Shaman": "support", "Mystic": "support", "Herald": "support",
	}
	return roles.get(class_name_, "damage")


## How this unit refuels.
##
## ⚠️ MANA BY ROLE IS THE FIX FOR PHYSICAL CLASSES BEING UNABLE TO AFFORD THEIR OWN KIT. A
## damage dealer is paid for CONNECTING, a tank for SOAKING, a support by TIME — each fuels
## itself by doing its actual job.
static func mana_role_of(stats: Dictionary, class_name_: String) -> String:
	if class_name_ == "Tank":
		return "tank"
	if role_of_class(class_name_) == "support":
		return "support"
	var top := ""
	var best := -1.0
	for s in STATS:
		var v := float(stats.get(s, 0))
		if v > best:
			best = v
			top = s
	return "tank" if top == "CON" else "damage"


## The class's free attack.
##
## ⚠️ AUTHORED PER CLASS, NEVER DERIVED FROM THE LOADOUT. Every attempt to infer it produced a
## monster fighting at the wrong range: by POWER a ranged monster got a melee basic it could
## never reach with; by REACH a Warrior that drafted one long shot became a ranged unit standing
## off at 6.4 holding a knife. DEX is why no formula replaces the table — Rogue is a knife,
## Ranger is a bow, and the stat pair cannot tell them apart.
##
## ⚠️ DELIBERATELY WEAK AND FAST. It fills the gaps between real skills; it does not replace
## them. The cooldown buys PRESENCE between casts, not throughput — which is why the damage was
## not raised when the cooldown came down.
static func basic_attack_for(stats: Dictionary) -> Dictionary:
	var cls := class_for_stats(stats)
	var table: Dictionary = _load().get("classBasic", {})
	var spec = table.get(cls, table.get("Generalist"))
	if spec == null:
		push_error("no CLASS_BASIC entry for '%s' and no Generalist fallback" % cls)
		return {}
	var stat: String = spec["stat"]
	return {
		"channel": spec["channel"],
		"stat": stat,
		"power": BASIC_BASE_POWER + float(stats.get(stat, 0)) * BASIC_STAT_SCALE
			* float(BASIC_STAT_TIER.get(stat, 0.5)),
		"range": float(spec["range"]),
		"cooldown": BASIC_COOLDOWN,
		"accuracy": BASIC_ACCURACY,
		"castTime": BASIC_CAST_TIME,
	}
