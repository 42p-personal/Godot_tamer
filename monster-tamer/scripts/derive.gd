## STAT DERIVATIONS AND PACING CONSTANTS, PORTED FROM `monster.ts` + `tamerengine/types.ts`.
##
## ⚠️ THESE ARE THE NUMBERS EVERY OTHER NUMBER IS RELATIVE TO. `max_hp` decides how long a
## fight lasts; `max_mana` and the field cost multiplier decide how many abilities a monster
## gets to use at all. A port that is 5% wrong here is wrong about the whole game in a way no
## single fight would localise.
##
## Verified against `data/derive.json` — 46 cases, 8 axes.
class_name Derive
extends RefCounted

const WIS_REGEN_DIVISOR := 200.0
const MANA_SUPPORT_PER_SEC := 1.0
const SECONDS_PER_ROUND := 2.0
const COOLDOWN_MULT := 1.0

## ⚠️ THE FIELD ENGINE PAYS 30% OF THE AUTHORED PRICE. The turn engine charges the full amount
## once per ROUND; a continuous field lets a unit cast far more often, so the same sticker price
## would starve every kit. A port that misses this can afford roughly a third of its abilities.
const FIELD_MANA_COST_MULT := 0.30

const CHANNEL_CAST_TIME := {
	"melee": 0.15, "ranged": 0.3, "magic": 0.55, "voice": 0.45, "support": 0.4,
}


## ⚠️ THE HP FORMULA IS QUADRATIC AND THE PROJECT DOCS SAID IT WAS LINEAR.
## `CLAUDE.md` recorded `maxHp = 40 + CON x 2.0`; the real formula carries a `CON^2 / 1600`
## term worth +56 HP at CON 300 and +400 at CON 800 — a 24% larger pool than the documented
## version. A port written from the documentation would give every high-CON monster a smaller
## pool and every fight a shorter clock, and it would look like a tuning disagreement rather
## than a transcription error.
static func max_hp(con: float) -> int:
	return int(round(40.0 + con * 2.0 + (con * con) / 1600.0))


## WIS is the mana FOUNDATION and the sole regen stat; INT contributes HALF its value, floored.
## ⚠️ The floor is load-bearing: INT 51 and INT 50 give the same pool.
static func max_mana(wis: float, intel: float) -> int:
	return int(wis) + int(floor(intel / 2.0))


## Mana per second from standing still.
static func regen_per_sec(wis: float, is_support: bool) -> float:
	return wis / WIS_REGEN_DIVISOR + (MANA_SUPPORT_PER_SEC if is_support else 0.0)


## The authored MP price of a move.
##
## ⚠️ AN AUTHORED COST WINS OUTRIGHT. Mana prices EFFECTIVENESS, not power — a move may be
## deliberately cheap for its number because it is paid for on some other axis. All 141 moves
## in the live pool author one, so the derived branch below is a fallback, not the common path.
static func mana_cost(move: Dictionary) -> int:
	if move.has("mana") and move["mana"] != null:
		return int(move["mana"])
	var avg_hits := 1.0
	var fxr = move.get("effects")
	if fxr is Dictionary and fxr.has("hits"):
		var h: Array = fxr["hits"]
		avg_hits = (float(h[0]) + float(h[1])) / 2.0
	var power := float(move.get("power", 0))
	var base := 6.0
	if move.get("type", "") == "damage":
		base = maxf(4.0, round(power * avg_hits * 0.45))
	elif power > 0.0:
		base = maxf(6.0, round(power * 0.4))
	return int(base * 2.0)


## What a cast actually costs on the field.
static func field_mp_cost(move: Dictionary) -> float:
	return float(mana_cost(move)) * FIELD_MANA_COST_MULT


## The cast time a move uses — its authored value, else its channel's default.
static func cast_time_of(move: Dictionary) -> float:
	if move.has("castTime") and move["castTime"] != null:
		return float(move["castTime"])
	return float(CHANNEL_CAST_TIME.get(move.get("channel", "melee"), 0.15))


## Seconds of lockout a move costs after being cast.
##
## ⚠️ `cooldown` IS SECONDS, and it used to mean two different things at once — `battle.ts`
## decremented it per ROUND while the field engine multiplied it and decremented by delta. The
## unit is now honest; do not reintroduce the ambiguity in the new engine.
static func cooldown_seconds(move: Dictionary) -> float:
	return float(move.get("cooldown", 0)) * COOLDOWN_MULT + cast_time_of(move)


## Status durations are authored in ROUNDS and lived in SECONDS. One constant joins them.
static func rounds_to_seconds(rounds: float) -> float:
	return rounds * SECONDS_PER_ROUND
