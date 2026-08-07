## HEADLESS 5v5 BATTLE SIMULATOR — the mockup's "watch it fight" half of the loop.
##
## ⚠️ THIS IS NOT THE SPATIAL FIELD ENGINE. `src/tamerengine/engine.ts`'s ~1,140 lines of AI,
## pathfinding, reach and target-priority are explicitly being REBUILT for Godot, not ported
## (CLAUDE.md: "Do not port what is being redesigned. Arenas, the spatial layer, the camera and
## target selection are all explicitly out"). Building a fake spatial layer here just to make a
## demo LOOK like the field engine would be exactly the throwaway work that rule exists to avoid.
##
## What this sim DOES use, verified and real: `Damage.resolve_strike`, `Derive` (pools/cooldowns/
## mana cost), `StatusMath.apply_status` (CC diminishing returns), `Tick.tick_unit` (regen/
## attrition/expiry — same step order as the contract: cooldowns, mana, HP regen, CC decay,
## attrition/expiry), and `Classify` (class/role/basic attack). Composed here into the smallest
## honest, NON-SPATIAL resolution loop: no positions, no reach, no cover — every enemy is always
## a legal target. AI is a simple priority list, not the real engine's target-priority system.
##
## Produces an event log the presentation layer (battle_ui.gd) replays at watchable speed —
## mirroring `battleReport.ts`'s own separation of pure sim from presentation.
class_name BattleSim
extends RefCounted

## Healing multiplier when the target is healblocked — `src/battle.ts:430`.
const HEALBLOCK_MULT := 0.4

const DT := 0.1
const MAX_DURATION := 180.0  # seconds of sim-time before a forced draw-by-attrition

const TacticsScript = preload("res://scripts/tactics.gd")

var team_a: Array = []  # Array[MonsterInstance]
var team_b: Array = []
var event_log: Array = []  # Array[Dictionary] — one entry per notable event, in order
var now := 0.0
var rng: RandomNumberGenerator

## The committed orders from "The Read" (scripts/tactics.gd). ⚠️ EVERY ONE OF THESE DEFAULTS TO
## EMPTY, AND EMPTY MUST REPRODUCE THE OLD BEHAVIOUR BYTE-FOR-BYTE. A caller that passes no
## tactics gets exactly the fight this sim produced before tactics existed — that is what makes
## the feature additive rather than a silent rebalance of every existing call site.
var team_a_plan: Dictionary = {}
var team_b_plan: Dictionary = {}
var unit_orders: Dictionary = {}  # MonsterInstance -> per-monster order dict, overrides its team plan


func _init(a: Array, b: Array, seed_: int = 0, plan_a: Dictionary = {}, plan_b: Dictionary = {}, orders: Dictionary = {}) -> void:
	team_a = a
	team_b = b
	team_a_plan = plan_a
	team_b_plan = plan_b
	unit_orders = orders
	rng = RandomNumberGenerator.new()
	rng.seed = seed_
	for m in team_a:
		m.side = "A"
		m.reset_for_battle()
	for m in team_b:
		m.side = "B"
		m.reset_for_battle()


func _all_units() -> Array:
	return team_a + team_b


func _enemies_of(m) -> Array:
	return team_b if m.side == "A" else team_a


func _allies_of(m) -> Array:
	return team_a if m.side == "A" else team_b


func _living(units: Array) -> Array:
	return units.filter(func(u): return u.alive)


## Runs the whole fight to completion and returns the summary. `log` holds every event for replay.
func run() -> Dictionary:
	_log_event({"kind": "start", "teamA": _names(team_a), "teamB": _names(team_b)})

	while now < MAX_DURATION:
		if _living(team_a).is_empty() or _living(team_b).is_empty():
			break

		for m in _all_units():
			if m.alive:
				_tick_one(m)

		for m in _all_units():
			if m.alive:
				_act(m)

		now += DT

	var a_alive := _living(team_a).size()
	var b_alive := _living(team_b).size()
	var winner := "draw"
	if a_alive > 0 and b_alive == 0:
		winner = "A"
	elif b_alive > 0 and a_alive == 0:
		winner = "B"
	elif a_alive != b_alive:
		winner = "A" if a_alive > b_alive else "B"  # attrition cap reached — more survivors wins

	var result := {
		"winner": winner, "duration": now, "log": event_log,
		"survivorsA": a_alive, "survivorsB": b_alive,
	}
	_log_event({"kind": "end", "winner": winner, "duration": now})
	return result


func _tick_one(m) -> void:
	var inp := {
		"dt": DT, "now": now, "statuses": m.statuses, "mods": m.mods,
		"cooldowns": m.cooldowns, "wis": m.stats.get("WIS", 0.0),
		"isSupport": m.mana_role == "support", "mp": m.mp, "maxMp": float(m.max_mp),
		"hp": m.hp, "maxHp": float(m.max_hp), "ccResist": m.cc_resist,
		"lastCcAt": m.last_cc_at,
	}
	var out := Tick.tick_unit(inp)
	m.hp = out["hp"]
	m.mp = out["mp"]
	m.statuses = out["statuses"]
	m.mods = out["mods"]
	m.cooldowns = out["cooldowns"]
	m.cc_resist = out["ccResist"]

	for kind in out["expired"]:
		_log_event({"kind": "status_expire", "unit": m.species_name, "side": m.side, "status": kind})

	# Attrition (poison/burn/bleed/doom) is applied every tick but deliberately NOT logged per
	# tick — at DT=0.1 a full-fight DoT would flood the spectator log with hundreds of near-
	# identical lines. What matters to a spectator is that the status was APPLIED (logged below)
	# and, if it kills, the death (logged in _act/_resolve_hit) — the tick-by-tick drip is not a
	# "moment," which is the standard the rest of this log is held to.
	var sd := Tick.sudden_death_loss(now, float(m.max_hp), DT)
	if sd > 0.0:
		m.hp = maxf(0.0, m.hp - sd)

	if out["dead"] or m.hp <= 0.0:
		if m.alive:
			m.alive = false
			_log_event({"kind": "death", "unit": m.species_name, "side": m.side})


func _mod_sum(m, key: String) -> float:
	var total := 0.0
	for mod in m.mods:
		total += float(mod.get(key, 0.0))
	return total


func _act(m) -> void:
	if not m.alive or m.is_incapacitated():
		return
	if m.has_status("fear"):  # noAttack
		return

	var can_skill: bool = not m.has_status("silence")
	var chosen: Dictionary = {}
	var is_basic := true

	var tac: Dictionary = _effective_tactics(m)

	if can_skill:
		var ready: Array = []
		for mv in m.moveset:
			var cd: float = m.cooldowns.get(mv["name"], 0.0)
			var cost: float = Derive.field_mp_cost(mv)
			if cd <= 0.0 and m.mp >= cost:
				# MANA POLICY "conserve": hold a reserve back rather than spending to the floor.
				if tac.get("manaPolicy", "normal") == "conserve" and (m.mp - cost) < 0.25 * float(m.max_mp):
					continue
				# TEMPERAMENT "cautious": stop throwing self-harm (recoil) moves once hurt. This is
				# the compressed stand-in for the TS `preserve` axis — see tactics.gd, which is
				# explicit that `aggressive` and `balanced` do NOT yet differ in this engine and
				# says so in the option's own description rather than implying parity.
				if tac.get("temperament", "") == "cautious" \
						and mv.get("effects", {}).has("recoil") and m.hp_frac() < 0.4:
					continue
				ready.append(mv)
		if not ready.is_empty():
			# Prefer the strongest READY move (highest authored power) — a simple but legible
			# priority, not the real engine's tactic-driven policy.
			ready.sort_custom(func(a, b): return float(a.get("power", 0)) > float(b.get("power", 0)))
			chosen = ready[rng.randi_range(0, mini(1, ready.size() - 1))]
			is_basic = false

	var basic_cd: float = m.cooldowns.get("__basic__", 0.0)
	if is_basic and basic_cd > 0.0:
		return  # nothing ready — waiting out the basic attack's own cooldown
	if is_basic:
		chosen = m.basic_attack
		# ⚠️ `Classify.basic_attack_for` returns a bare {channel/stat/power/range/cooldown/
		# accuracy/castTime} dict — no "name" key, because the free attack isn't drawn from the
		# authored move pool. Every log/cooldown-keying call site below expects one, so stamp it
		# in once, in place (dicts are references — this mutates m.basic_attack itself, which is
		# fine and idempotent: every monster's free attack is always just "Attack").
		if not chosen.has("name"):
			chosen["name"] = "Attack"
			chosen["target"] = "enemy"

	if chosen.is_empty():
		return

	var target_kind: String = chosen.get("target", "enemy")
	var target = null
	match target_kind:
		"enemy":
			target = TacticsScript.pick_target(m, _living(_enemies_of(m)), tac)
		"allEnemies":
			# ⚠️ AoE coverage is gated by the DEFENDING side's formation, not the attacker's — a
			# loose team is harder to blanket however the attacker happens to be arranged.
			var def_plan: Dictionary = team_b_plan if m.side == "A" else team_a_plan
			for e in TacticsScript.aoe_coverage(_living(_enemies_of(m)), def_plan):
				_resolve_hit(m, e, chosen, is_basic)
			_pay_and_cooldown(m, chosen, is_basic)
			return
		"ally":
			var allies := _living(_allies_of(m)).filter(func(u): return u != m)
			target = _pick_lowest_hp(allies) if not allies.is_empty() else m
		"self", "team":
			target = m
		_:
			target = TacticsScript.pick_target(m, _living(_enemies_of(m)), tac)

	if target == null:
		return

	if target_kind == "team":
		# ⚠️ Aura coverage is gated by the CASTER's OWN formation — this is the other half of the
		# same trade (docs/ARENA_BLUEPRINT.md §5): a tight team keeps its buffs across the whole
		# formation, a loose team gives them up. One order, a cost on both sides of it.
		var own_plan: Dictionary = team_a_plan if m.side == "A" else team_b_plan
		for a in TacticsScript.aura_coverage(_living(_allies_of(m)), own_plan):
			_apply_team_effect(m, a, chosen)
		_pay_and_cooldown(m, chosen, is_basic)
		return

	# ⚠️ ROUTE BY HOSTILITY, NOT BY TARGET KIND — THIS WAS A PORT REGRESSION.
	# `src/battle.ts:1337` — the engine the players actually run — branches on whether the move is
	# HOSTILE: `if (!hostile) { for (const t of targets) resolveUtilityOnTarget(...); return }`.
	# Every non-hostile move reaches the utility path regardless of whether it targets self, ally
	# or team. The GDScript port narrowed that predicate to `target_kind == "team"`, so `self` and
	# `ally` fell through to `_resolve_hit` — the COMBAT-STRIKE path, which only applies debuffs
	# and statuses. Every friendly effect (guard, ward, atkBuff, defBuff, dodgeBuff, accBuff,
	# hpRegenBuff, thorns, heal, cleanse) lives in `_apply_team_effect` and was never reached.
	#
	# MEASURED before the fix (`scripts/_probe_bsim.gd`): a fight with Guard, Enrage and Steady
	# Vigil in every moveset logged 167 `hit` events and ZERO `buff` events. 29 of the 141 moves
	# are affected. `spatial_sim.gd` had the identical regression, fixed the same day.
	#
	# ⚠️ The two comments below at `_resolve_hit` asserting "a pure self/team/ally support move
	# never reaches this call" were ASPIRATIONAL, not descriptive — they described the intent this
	# fix restores, while the code did the opposite.
	if _is_friendly_move(chosen):
		_resolve_utility_on_target(m, target, chosen)
		_pay_and_cooldown(m, chosen, is_basic)
		return

	_resolve_hit(m, target, chosen, is_basic)
	_pay_and_cooldown(m, chosen, is_basic)


## ⚠️ HOSTILITY, NOT TARGET KIND — mirrors `src/battle.ts:1337`'s `if (!hostile)`. Any move aimed
## at your own side is utility, full stop. ⚠️ Do NOT add a `power <= 0` test here: on a FRIENDLY
## move `power` is the HEAL AMOUNT, not damage (Mending Surge 97, Tranquility 74, Vital Surge 46),
## so a power test would send nine healing moves — including one of the three cleanses — straight
## back into the combat-strike path.
func _is_friendly_move(mv: Dictionary) -> bool:
	return str(mv.get("target", "enemy")) in ["self", "ally", "team"]


## Port of `src/battle.ts:1051 resolveUtilityOnTarget` — the non-hostile resolution path that this
## engine never had.
##
## ⚠️ BEFORE THIS EXISTED, HEALING DID NOT WORK AT ALL. `grep '\.hp +' battle_sim.gd` found
## nothing: every HP write in this file SUBTRACTS. Mend, Renewal, Tranquility and Mending Surge —
## authored at power 15/11/74/97 — were routed into `_resolve_hit` and resolved as combat strikes
## against the ally they were meant to save. WIS is documented as the only stat that can heal
## another monster (`CLAUDE.md`); in this engine it could not heal anything.
func _resolve_utility_on_target(caster, target, mv: Dictionary) -> void:
	var power := float(mv.get("power", 0.0))
	if power > 0.0:
		# battle.ts: round(power * 1.2 * (healblock ? HEALBLOCK_MULT : 1))
		var mult: float = HEALBLOCK_MULT if target.has_status("healblock") else 1.0
		var heal: float = round(power * 1.2 * mult)
		var before: float = target.hp
		target.hp = minf(float(target.max_hp), target.hp + heal)
		_log_event({
			"kind": "heal", "unit": target.species_name, "side": target.side,
			"move": mv["name"], "caster": caster.species_name,
			"amount": int(target.hp - before), "healblocked": target.has_status("healblock"),
		})
	_apply_team_effect(caster, target, mv)


## A unit's effective orders: its team's plan, with its own per-monster overrides layered on top.
func _effective_tactics(m) -> Dictionary:
	var plan: Dictionary = team_a_plan if m.side == "A" else team_b_plan
	var merged: Dictionary = plan.duplicate()
	var own: Dictionary = unit_orders.get(m, {})
	for k in own:
		merged[k] = own[k]
	return merged


func _pick_lowest_hp(units: Array):
	if units.is_empty():
		return null
	var best = units[0]
	for u in units:
		if u.hp_frac() < best.hp_frac():
			best = u
	return best


func _pay_and_cooldown(m, mv: Dictionary, is_basic: bool) -> void:
	m.has_acted = true
	if is_basic:
		m.cooldowns["__basic__"] = mv["cooldown"]
		return
	m.mp = maxf(0.0, m.mp - Derive.field_mp_cost(mv))
	m.cooldowns[mv["name"]] = Derive.cooldown_seconds(mv)


## Buffs/debuffs/heals-over-time that target the caster's own side (self/ally/team) — no strike
## roll, just a mod applied for the move's authored duration (rounds -> seconds via Derive).
func _apply_team_effect(caster, target, mv: Dictionary) -> void:
	var fx: Dictionary = mv.get("effects", {})
	if fx.is_empty():
		return
	var duration_s := Derive.rounds_to_seconds(float(fx.get("duration", 1)))
	var mod := {"until": now + duration_s}
	var applied := false
	if fx.has("atkBuff"):
		mod["atkMultBonus"] = float(fx["atkBuff"]); applied = true
	if fx.has("defBuff"):
		mod["defMitDebuff"] = -float(fx["defBuff"]); applied = true
	if fx.has("accBuff"):
		mod["accMod"] = float(fx["accBuff"]); applied = true
	if fx.has("dodgeBuff"):
		mod["dodgeMod"] = float(fx["dodgeBuff"]); applied = true
	if fx.has("ward"):
		mod["ward"] = float(fx["ward"]); applied = true
	if fx.has("guard"):
		mod["guard"] = float(fx["guard"]); applied = true
	if fx.has("hpRegenBuff"):
		mod["hpRegen"] = float(fx["hpRegenBuff"]); applied = true
	if fx.has("regenBuff"):
		mod["regen"] = float(fx["regenBuff"]); applied = true
	if applied:
		target.mods.append(mod)
		_log_event({
			"kind": "buff", "unit": target.species_name, "side": target.side,
			"move": mv["name"], "caster": caster.species_name,
		})
	if fx.has("cleanse"):
		target.statuses = target.statuses.filter(func(s): return not StatusMath.HARD_CONTROL.has(s["kind"]))


func _resolve_hit(attacker, target, mv: Dictionary, is_basic: bool) -> void:
	# A pure self/team/ally support move never reaches this call (routed to _apply_team_effect
	# above); a damage/debuff/control move aimed at an enemy always does.
	var fx: Dictionary = mv.get("effects", {})
	var mit_stat: float = target.stats.get("CON", 0.0) if (mv["channel"] == "melee" or mv["channel"] == "ranged") else target.stats.get("WIS", 0.0)

	var acc_penalty := 0.0
	if attacker.has_status("blind"):
		acc_penalty += StatusMath._rule("blind").get("accPenalty", 0.0)
	if attacker.has_status("confusion"):
		acc_penalty += StatusMath._rule("confusion").get("accPenalty", 0.0)

	var dmg_taken_mult := 1.0
	if target.has_status("vulnerable"):
		dmg_taken_mult *= StatusMath._rule("vulnerable").get("damageTakenMult", 1.0)

	var hits := 1
	if fx.has("hits"):
		var h: Array = fx["hits"]
		hits = rng.randi_range(int(h[0]), int(h[1]))

	var total_dmg := 0
	var last_out := {}
	for i in range(maxi(1, hits)):
		if not target.alive:
			break
		var inp := {
			"move": mv,
			"rolls": {"acc": rng.randf(), "crit": rng.randf(), "variance": rng.randf()},
			"accPenalty": acc_penalty, "accMod": _mod_sum(attacker, "accMod"),
			"dodgeMod": _mod_sum(target, "dodgeMod"), "flankBonus": 0.0,
			"defHasAttacked": target.has_acted, "attackerHpFrac": attacker.hp_frac(),
			"attackerWard": _mod_sum(attacker, "ward"), "defHpFrac": target.hp_frac(),
			"defHasBonusStatus": false, "defMaxHp": float(target.max_hp),
			"behindMult": 1.0, "falloff": 1.0,
			"atkMult": 1.0 + _mod_sum(attacker, "atkMultBonus"),
			"defMit": mit_stat, "defMitDebuff": _mod_sum(target, "defMitDebuff"),
			"defBlocking": false, "defStatusDmgTaken": dmg_taken_mult,
			"defDmgTakenMod": 1.0, "defGuard": _mod_sum(target, "guard"),
			"defWard": _mod_sum(target, "ward"), "atk": attacker.stats.get(mv.get("stat", "STR"), 0.0),
			"now": now,
		}
		var out := Damage.resolve_strike(inp)
		last_out = out
		if out["hit"]:
			total_dmg += out["dmg"]
			target.hp = maxf(0.0, target.hp - float(out["toHp"]))
			if out["wardSoaked"] > 0:
				var remaining: float = out["wardSoaked"]
				for mod in target.mods:
					if remaining <= 0.0:
						break
					if mod.has("ward") and float(mod["ward"]) > 0.0:
						var take: float = minf(float(mod["ward"]), remaining)
						mod["ward"] = float(mod["ward"]) - take
						remaining -= take

			var recoil = fx.get("recoil")
			if recoil != null:
				attacker.hp = maxf(0.0, attacker.hp - float(out["dmg"]) * minf(0.15, float(recoil)))
			var lifesteal = fx.get("lifesteal")
			if lifesteal != null:
				attacker.hp = minf(float(attacker.max_hp), attacker.hp + float(out["toHp"]) * float(lifesteal))
			var thorns = fx.get("thorns")
			if thorns != null and not is_basic:
				pass  # thorns is a defender-reflect on being hit — out of scope for this mockup pass

	attacker.has_acted = true
	if target.hp <= 0.0 and target.alive:
		target.alive = false
		_log_event({"kind": "death", "unit": target.species_name, "side": target.side, "killer": attacker.species_name})

	_log_event({
		"kind": "hit" if last_out.get("hit", false) else "miss",
		"attacker": attacker.species_name, "attackerSide": attacker.side,
		"target": target.species_name, "targetSide": target.side,
		"move": mv["name"], "dmg": total_dmg, "crit": last_out.get("crit", false),
		"targetHpFrac": target.hp_frac(),
	})

	# Enemy-facing debuff mods carried on a damage/debuff move (e.g. Sunder's defDebuff) — the
	# ally/self/team case is handled entirely by _apply_team_effect and never reaches here.
	if last_out.get("hit", false) and target.alive:
		var debuff_mod := {}
		var has_debuff := false
		if fx.has("defDebuff"):
			debuff_mod["defMitDebuff"] = float(fx["defDebuff"]); has_debuff = true
		if fx.has("atkDebuff"):
			debuff_mod["atkMultBonus"] = -float(fx["atkDebuff"]); has_debuff = true
		if fx.has("accDebuff"):
			debuff_mod["accMod"] = -float(fx["accDebuff"]); has_debuff = true
		if fx.has("manaBurn"):
			target.mp = maxf(0.0, target.mp - float(fx["manaBurn"]))
		if has_debuff:
			debuff_mod["until"] = now + Derive.rounds_to_seconds(float(fx.get("duration", 1)))
			target.mods.append(debuff_mod)

	var status_spec = mv.get("status")
	if status_spec != null and target.alive:
		if rng.randf() * 100.0 < float(status_spec.get("chance", 100.0)):
			var out := StatusMath.apply_status({
				"kind": status_spec["kind"], "statuses": target.statuses,
				"ccResist": target.cc_resist, "targetDead": false,
				"rounds": float(status_spec.get("duration", 1)), "now": now,
				"ccImmuneUntil": -999.0, "targetCon": target.stats.get("CON", 0.0),
				"from": attacker.species_name,
			})
			if out["applied"]:
				target.statuses = out["statuses"]
				target.cc_resist = out["ccResist"]
				if out["ccMeterTouched"]:
					target.last_cc_at = now
				_log_event({
					"kind": "status_apply", "unit": target.species_name, "side": target.side,
					"status": status_spec["kind"], "from": attacker.species_name,
				})


func _log_event(e: Dictionary) -> void:
	e["t"] = now
	event_log.append(e)


func _names(team: Array) -> Array:
	return team.map(func(m): return m.species_name)
