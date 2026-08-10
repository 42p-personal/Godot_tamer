## WHAT A MONSTER IS — class, composition role, mana role, and the free attack.
##
## ⚠️ THIS IS UPSTREAM OF ALMOST EVERYTHING ELSE. Class picks the free attack; the free attack
## sets reach; mana role decides how a unit refuels; `CLASS_LINES` keys ability affinity off the
## class name. Get this wrong and every downstream system is subtly wrong for reasons that never
## point back here.
##
## ⚠️ CLASS IS NO LONGER PURELY EMERGENT — IT CAN BE A STORED PLAYER COMMITMENT (round 15).
## `class_for_stats()` below is UNCHANGED and still under contract (46 pinned cases), but its JOB
## changed: it no longer DECIDES a monster's class, it SUGGESTS one (for a monster that has not
## committed) and it GATES which classes a monster may commit TO (`classes_available_for`).
## `MonsterInstance.assigned_class` is the authority when it is set; when it is "" the old
## emergent behaviour holds byte-for-byte, which is what makes every existing save load unchanged.
##
## Any species can in principle train into any class; aptitude only weights how fast each stat
## grows. **Never write flavour text or UI as if a species is destined for its class.**
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
	return basic_attack_for_class(class_for_stats(stats), stats)


## The free attack of a NAMED class, scaled by this monster's stats.
##
## ⚠️ THIS SPLIT EXISTS BECAUSE `basic_attack_for` IS CONTRACTED AND MUST NOT CHANGE. It took a
## `stats` dictionary and derived the class inside itself — which is exactly the hidden
## re-derivation that would have silently un-done a stored class every time a monster's pools were
## refreshed. `basic_attack_for(stats)` is now a thin wrapper over this and returns the identical
## answer for every input, so `data/classify.json`'s 7 `basicAttackFor` cases still pass exactly.
static func basic_attack_for_class(cls: String, stats: Dictionary) -> Dictionary:
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


# ═════════════════════════════════════════════════════════════════════════════════════════════
# THE ASSIGNMENT GATE — which classes a monster may COMMIT to (docs/CLASS_REWORK.md §2.2, §10.3)
# ═════════════════════════════════════════════════════════════════════════════════════════════
#
# ⚠️ THIS SITS BESIDE `class_for_stats`, IT DOES NOT REPLACE IT. `class_for_stats` is contracted
# maths (46 pinned cases, exact equality against the TypeScript) and returns the same answer for
# every input it ever has. What changed is what the answer is USED for: for an uncommitted monster
# it is still the class, and for a committed one it is only the suggestion the gate is built from.
#
# ⚠️ AND THE GATE IS THE THING THAT COULD BREAK THE ONE NON-NEGOTIABLE — "a species must never be
# locked out of a role" (CLAUDE.md). It cannot, and the reason is structural rather than lucky:
# every condition below reads only `stats`, never `species_id`, `body` or `trainingProfile`. Two
# of the three are RANK tests, and rank is relative, so any body that trains a stat to the top of
# its own spread satisfies them regardless of how slowly it got there. Species aptitude is a RATE,
# never a ceiling. `_probe_archetypes.gd:128` is the assertion of record.

## Rank thresholds, 0-indexed. Primary must be top-2, secondary top-3 — deliberately LOOSER than
## `class_for_stats`'s exact ordered-pair match, because an exact match would make the "choice"
## a single forced answer, i.e. `class_for_stats` wearing a UI.
const GATE_PRIMARY_RANK := 1
const GATE_SECONDARY_RANK := 2

## The absolute floor: the primary stat must represent real investment, not merely be relatively
## tallest on a flat body (some stat is always top-2 of six, however untrained).
##
## ⚠️ UNMEASURED, AND ROUND 15 SAYS IT IS TOO LOW — read `docs/CLASS_REWORK.md` §10.3 before
## touching it. Expressed as a fraction of the LEAGUE cap it inherits §2's inversion exactly: at
## Iron (cap 500) a naive body reaches the cap, so 0.20 is satisfied from very early, while at
## Apex the same fraction is a number a career can miss. The honest version is a fraction of what
## a career can BANK, which is the same quantity §10.1 fixes in `week.gd:stat_ceiling()`. Left at
## the authored 0.20 here so the gate ships with ONE unmeasured constant rather than two, and so
## the number that moves it is the number §10.1 measures. `scripts/_probe_assign.gd` §2 reports
## what the current value costs, per rung.
const GATE_FLOOR := 0.20


## Stat names in descending order of this monster's current values. Ties resolve by `STATS`
## order — the same total order `_top_two()` relies on, so the gate needs no new convention.
static func _ranked_stats(stats: Dictionary) -> Array:
	var ordered := STATS.duplicate()
	ordered.sort_custom(func(a, b):
		var va := float(stats.get(a, 0))
		var vb := float(stats.get(b, 0))
		if va == vb:
			return STATS.find(a) < STATS.find(b)
		return va > vb)
	return ordered


## PURE. The classes this stat vector currently qualifies to be ASSIGNED, sorted by name.
##
## `nominal_cap` is the monster's own training ceiling (league cap x bloodline potential — what
## `week.gd:stat_ceiling` calls nominal), NOT the raw league cap, so a high-potential bloodline
## is held to a proportionally higher bar rather than a cheaper one.
##
## ⚠️ `Generalist` IS NEVER IN THIS LIST AND THAT IS DELIBERATE. It is the UNCOMMITTED state, it
## carries no `classes` entry to gate against, and it is always available — see
## `MonsterInstance.clear_class_assignment()`. A UI offers it separately, as the honest
## always-open fallback, never as a gated option.
static func classes_available_for(stats: Dictionary, nominal_cap: float) -> Array:
	var ranked := _ranked_stats(stats)
	var floor_value: float = GATE_FLOOR * maxf(0.0, nominal_cap)
	var out: Array = []
	for c in _load().get("classes", []):
		var p: String = str(c.get("primary", ""))
		var s: String = str(c.get("secondary", ""))
		if ranked.find(p) > GATE_PRIMARY_RANK:
			continue
		if ranked.find(s) > GATE_SECONDARY_RANK:
			continue
		if float(stats.get(p, 0.0)) < floor_value:
			continue
		out.append(str(c.get("name", "")))
	out.sort()
	return out


## Why a class is NOT available, as one short player-facing line, or "" if it IS available.
## The gate's third requirement is "give training a goal" (§2.1) — a gate that only says no does
## not meet it, so the reason is part of the mechanism rather than a UI afterthought.
static func gate_reason(stats: Dictionary, nominal_cap: float, cls: String) -> String:
	for c in _load().get("classes", []):
		if str(c.get("name", "")) != cls:
			continue
		var p: String = str(c.get("primary", ""))
		var s: String = str(c.get("secondary", ""))
		var ranked := _ranked_stats(stats)
		if ranked.find(p) > GATE_PRIMARY_RANK:
			return "%s must be one of the two highest stats (it is #%d)" % [p, ranked.find(p) + 1]
		if ranked.find(s) > GATE_SECONDARY_RANK:
			return "%s must be one of the three highest stats (it is #%d)" % [s, ranked.find(s) + 1]
		var floor_value: float = GATE_FLOOR * maxf(0.0, nominal_cap)
		if float(stats.get(p, 0.0)) < floor_value:
			return "%s must reach %d (it is %d)" % [p, int(round(floor_value)),
				int(round(float(stats.get(p, 0.0))))]
		return ""
	return "unknown class"
