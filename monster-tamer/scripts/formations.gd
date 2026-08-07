## SAVED FORMATIONS — persistence + roster-mismatch matching for the deployment board.
##
## Implements `docs/UX_DEPLOYMENT.md` §3, the load-bearing idea in that spec: **a formation saves
## a slot's POSITION and ROLE/CLASS TAG, never a monster's identity.** A naive save
## (`{monster_instance: pos}`) breaks the day the roster changes at all; tagging by
## `m.role`/`m.class_name_` instead means a formation survives a retirement, a breed, or fielding
## a different five for a different league. See `docs/TACTICS_BRAINSTORM.md` §2.3, the earlier
## "name slots by intent, not coordinates" finding this is a one-layer-down reuse of.
##
## Static utility class, same shape as `tactics.gd` (no scene, no autoload registration needed —
## `preload()` it from whichever screen owns the board).
##
## ⚠️ Positions are stored NORMALISED (0..1 x, 0..1 y) within the OWN deployable zone at save
## time, not as raw world coordinates. `tactics_ui.gd`'s current mockup only ever plays 5v5
## (`TEAM_SIZE := 5`, hardcoded), so this never gets exercised today — but the zone is a function
## of `team_size` (`Spatial.ground_size`), and a formation that stored raw coordinates would
## silently misplace itself the day a screen this saves from actually varies team size. Normalise
## once now rather than re-learn the lesson `UX_DEPLOYMENT.md` §3.1 already paid for.
class_name Formations
extends RefCounted

const SAVE_PATH := "user://formations.json"
const MAX_SAVED := 12  ## ⚠️ UX_DEPLOYMENT.md §3.2 — a judgement call, not a hard number.

static var _cache: Array = []       ## Array[Dictionary] — loaded saved formations, most-recent first
static var _loaded: bool = false


# ── Persistence ──────────────────────────────────────────────────────────────────────────────

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_cache = []
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Array:
		_cache = parsed


static func _persist() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Formations: cannot open %s for writing" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(_cache))
	f.close()


## All player-saved formations (most-recently-used first). Does NOT include starter presets —
## call `starter_presets()` separately; the gallery UI concatenates them.
static func all() -> Array:
	_ensure_loaded()
	return _cache.duplicate(true)


# ── Save / update / delete ───────────────────────────────────────────────────────────────────

## `placements`: Array of {"monster": <MonsterInstance>, "pos": Vector2 (world, own zone)}.
## `intents`: Dictionary MonsterInstance -> String, optional per-slot positional intent.
static func save(fname: String, team_size: int, zone: Rect2, placements: Array,
		intents: Dictionary = {}) -> Dictionary:
	_ensure_loaded()
	var entry := _build_entry(fname, team_size, zone, placements, intents)
	_cache.push_front(entry)
	while _cache.size() > MAX_SAVED:
		_cache.pop_back()
	_persist()
	return entry


static func update(existing_name: String, team_size: int, zone: Rect2, placements: Array,
		intents: Dictionary = {}) -> Dictionary:
	_ensure_loaded()
	for i in range(_cache.size()):
		if _cache[i]["name"] == existing_name:
			var entry := _build_entry(existing_name, team_size, zone, placements, intents)
			entry["created"] = _cache[i].get("created", entry["created"])
			_cache[i] = entry
			_persist()
			return entry
	return save(existing_name, team_size, zone, placements, intents)


static func delete(fname: String) -> void:
	_ensure_loaded()
	_cache = _cache.filter(func(e): return e["name"] != fname)
	_persist()


static func rename(old_name: String, new_name: String) -> void:
	_ensure_loaded()
	for e in _cache:
		if e["name"] == old_name:
			e["name"] = new_name
	_persist()


static func touch_last_used(fname: String) -> void:
	_ensure_loaded()
	for e in _cache:
		if e["name"] == fname:
			e["lastUsed"] = Time.get_unix_time_from_system()
			# Move to front so the gallery's natural order surfaces recently-used formations —
			# UX_DEPLOYMENT.md §7's speed argument: the common case is loading what you used last.
			_cache.erase(e)
			_cache.push_front(e)
			break
	_persist()


static func _build_entry(fname: String, team_size: int, zone: Rect2, placements: Array,
		intents: Dictionary) -> Dictionary:
	var slots: Array = []
	for p in placements:
		var m = p["monster"]
		var pos: Vector2 = p["pos"]
		var rel := Vector2.ZERO
		if zone.size.x > 0.0 and zone.size.y > 0.0:
			rel = Vector2(
				clampf((pos.x - zone.position.x) / zone.size.x, 0.0, 1.0),
				clampf((pos.y - zone.position.y) / zone.size.y, 0.0, 1.0))
		slots.append({
			"rel": [rel.x, rel.y],
			"role": String(m.role),
			"class": String(m.class_name_),
			"intent": String(intents.get(m, "")),
		})
	var now := Time.get_unix_time_from_system()
	return {
		"name": fname, "teamSize": team_size, "created": now, "lastUsed": now,
		"slots": slots,
	}


# ── Starter presets — docs/UX_DEPLOYMENT.md §3.4 ─────────────────────────────────────────────
## Four pre-authored shapes, always present in the gallery, not persisted (rebuilt fresh so an
## edit to one doesn't corrupt the template — "loadable and editable like any other" means the
## EDIT becomes a new save, never a mutation of the preset itself).
##
## Slot tags are generic ("front"/"back") rather than a real monster's role/class, matched below
## by `_score()` via the same role-based path (a "front" tag prefers `role == "damage"`, "back"
## prefers `role == "support"` — the two buckets `classify.gd:role_of_class` actually produces).
const _PRESET_SHAPES := {
	"Line": [
		[0.15, 0.20], [0.15, 0.40], [0.15, 0.60], [0.15, 0.80], [0.05, 0.50],
	],
	"Wedge": [
		[0.05, 0.50], [0.15, 0.30], [0.15, 0.70], [0.28, 0.15], [0.28, 0.85],
	],
	"Box": [
		[0.08, 0.30], [0.08, 0.70], [0.22, 0.30], [0.22, 0.70], [0.15, 0.50],
	],
	"Split": [
		[0.10, 0.10], [0.10, 0.25], [0.10, 0.75], [0.10, 0.90], [0.25, 0.50],
	],
}
## Which of the 5 slots in each shape (by index above) reads as a back-line/support position.
const _PRESET_BACK_SLOT := {
	"Line": [4], "Wedge": [0], "Box": [4], "Split": [4],
}


static func starter_presets(team_size: int) -> Array:
	var out: Array = []
	for shape_name in _PRESET_SHAPES:
		var rels: Array = _PRESET_SHAPES[shape_name]
		var back: Array = _PRESET_BACK_SLOT.get(shape_name, [])
		var slots: Array = []
		for i in range(rels.size()):
			slots.append({
				"rel": rels[i], "role": ("support" if back.has(i) else "damage"),
				"class": "", "intent": "",
			})
		out.append({
			"name": shape_name, "teamSize": team_size, "created": 0, "lastUsed": 0,
			"slots": slots, "preset": true,
		})
	return out


# ── Load / match against a roster (UX_DEPLOYMENT.md §3.3, Cases A-D) ────────────────────────

## Resolves a saved (or preset) formation against `roster` (Array[MonsterInstance], exactly the
## fielded team). Returns:
##   {
##     "placements": [{"monster":..., "pos": Vector2, "intent": String}, ...],
##     "summary": String,           -- human-readable match summary
##     "low_confidence": Array,     -- monsters whose slot match was a weak guess
##     "dropped_slots": int,        -- how many slots were trimmed (Case C)
##   }
static func resolve_for_roster(formation: Dictionary, zone: Rect2, roster: Array) -> Dictionary:
	var slots: Array = formation.get("slots", []).duplicate(true)
	var dropped := 0

	# Case C — fewer monsters than slots: trim to the slots nearest the formation's OWN centroid,
	# so the shape's character survives (a wedge stays a wedge) rather than flattening to a line.
	if roster.size() < slots.size():
		var centroid := Vector2.ZERO
		for s in slots:
			centroid += Vector2(s["rel"][0], s["rel"][1])
		centroid /= float(slots.size())
		slots.sort_custom(func(a, b):
			var da: float = Vector2(a["rel"][0], a["rel"][1]).distance_to(centroid)
			var db: float = Vector2(b["rel"][0], b["rel"][1]).distance_to(centroid)
			return da < db)
		dropped = slots.size() - roster.size()
		slots = slots.slice(0, roster.size())

	# Case D (more monsters than slots) is out of this screen's scope per UX_DEPLOYMENT.md §3.3 —
	# team size is fixed by league before this screen opens. Guard anyway: match what we can.
	var available: Array = roster.duplicate()
	var assigned: Array = []       # parallel to `slots`
	var low_confidence: Array = []
	var role_matches := 0

	for slot in slots:
		var best = null
		var best_score := -1
		for cand in available:
			var s := _score(cand, slot)
			if s > best_score:
				best_score = s
				best = cand
		if best != null:
			available.erase(best)
			assigned.append(best)
			if best_score >= 2:
				role_matches += 1
			if best_score <= 0:
				low_confidence.append(best)
		else:
			assigned.append(null)

	var placements: Array = []
	for i in range(slots.size()):
		var m = assigned[i]
		if m == null:
			continue
		var slot: Dictionary = slots[i]
		var rel := Vector2(slot["rel"][0], slot["rel"][1])
		var pos := zone.position + Vector2(rel.x * zone.size.x, rel.y * zone.size.y)
		placements.append({"monster": m, "pos": pos, "intent": String(slot.get("intent", ""))})

	var matched_count: int = placements.size()
	var reassigned: int = matched_count - role_matches
	var summary: String
	if dropped > 0:
		summary = "Loaded %d of %d slots — dropped the %d slot(s) furthest from centre." % \
			[matched_count, formation.get("slots", []).size(), dropped]
	elif reassigned <= 0:
		summary = "%d/%d slots matched by role." % [matched_count, matched_count]
	else:
		summary = "%d/%d slots matched by role, %d reassigned." % \
			[role_matches, matched_count, reassigned]

	return {
		"placements": placements, "summary": summary,
		"low_confidence": low_confidence, "dropped_slots": dropped,
	}


## Slot-tag match score: exact role+class = 3, role only = 2, class only = 1, neither = 0
## (low-confidence). Two buckets for role (`classify.gd:role_of_class` only ever returns
## "damage"/"support") so class is what actually discriminates most of the time; role alone still
## separates "get me A SUPPORT here" from "get me A DAMAGE DEALER here" even with no class match.
static func _score(monster, slot: Dictionary) -> int:
	var role_match: bool = String(monster.role) == String(slot.get("role", ""))
	var class_match: bool = String(monster.class_name_) == String(slot.get("class", ""))
	if role_match and class_match:
		return 3
	if role_match:
		return 2
	if class_match:
		return 1
	return 0
