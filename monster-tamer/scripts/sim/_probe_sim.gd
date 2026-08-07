## SIM REWRITE PROBE — headless acceptance for sim.gd v1. Exit code is the result.
## Pins: fights resolve, pathing routes around cover, intent rides the stream, the anti-blob
## tactics separate destinations, and twin seeded runs hash byte-identical.
extends Node3D

const Sim = preload("res://scripts/sim/sim.gd")
const Kit = preload("res://scripts/sim/kit.gd")

var _fails := 0


func _check(name: String, ok: bool) -> void:
	if ok:
		print("  ok  ", name)
	else:
		_fails += 1
		print("  FAIL ", name)


func _units_5v5(tactics_a: Dictionary) -> Array:
	var out: Array = []
	for i in 5:
		out.append({"id": "a%d" % i, "team": "A", "pos": Vector2(-40, -12 + 6 * i),
			"stats": {"STR": 60, "CON": 40, "INT": 10, "WIS": 10}, "speed": 9.0, "tactics": tactics_a})
		out.append({"id": "b%d" % i, "team": "B", "pos": Vector2(40, -12 + 6 * i),
			"stats": {"STR": 45, "CON": 35, "INT": 30, "WIS": 25}, "speed": 8.0,
			"tactics": {"target_priority": "nearest", "positional": "push"}})
	return out


func _run_sim(seed_val: int, tactics_a: Dictionary) -> Dictionary:
	var sim = Sim.new()
	sim.setup(seed_val, _units_5v5(tactics_a),
		Vector2(110, 62), [{"rect": Rect2(-4, -4, 8, 8)}])  # central pillar
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-40, 0), Vector2(40, 0))
	if not ok:
		return {}
	return sim.run()


func _hash_frames(res: Dictionary) -> String:
	return str(JSON.stringify(res.get("frames", [])).hash()) + "|" + str(res.get("winner"))


func _ready() -> void:
	_go()


func _go() -> void:
	var r1: Dictionary = await _run_sim(42, {"target_priority": "nearest", "positional": "push"})
	_check("nav ready and fight ran", not r1.is_empty() and r1.frames.size() > 10)
	_check("the fight RESOLVES (a side wins inside the cap)", str(r1.winner) in ["A", "B"])
	# The stream carries intent from the tree, and the log is a handful of decisions, not spam.
	var mid: Dictionary = r1.frames[mini(40, r1.frames.size() - 1)]
	var has_intent := false
	for u in mid.units:
		if str(u.intent) != "":
			has_intent = true
	_check("stream: units carry live intent", has_intent)
	var log_a0: Array = r1.decision_logs.get("a0", [])
	_check("decision log exists and is compact (changes only)", log_a0.size() >= 1 and log_a0.size() < 60)
	# Strikes actually flow through the contracted maths.
	var strikes := 0
	for f in r1.frames:
		for e in f.events:
			if e.kind == "strike":
				strikes += 1
	_check("strikes landed through resolve_strike", strikes > 10)

	# Anti-blob geometry: wings and push must produce genuinely different early destinations.
	var r_push: Dictionary = await _run_sim(42, {"target_priority": "nearest", "positional": "push"})
	var r_wing: Dictionary = await _run_sim(42, {"target_priority": "nearest", "positional": "wings", "wing_side": 1})
	var spread_push := _team_a_y_spread(r_push, 60)
	var spread_wing := _team_a_y_spread(r_wing, 60)
	_check("wings spreads team A wider than push by tick 60 (the anti-blob axis)",
		spread_wing > spread_push + 4.0)

	# Determinism: same seed twice — byte-identical frames. Different seed diverges.
	var t1: Dictionary = await _run_sim(1234, {"target_priority": "weakest", "positional": "push"})
	var t2: Dictionary = await _run_sim(1234, {"target_priority": "weakest", "positional": "push"})
	var t3: Dictionary = await _run_sim(4321, {"target_priority": "weakest", "positional": "push"})
	_check("determinism: same seed, twin runs, identical frame stream + winner",
		_hash_frames(t1) == _hash_frames(t2))
	_check("guard: different seed diverges (probe not vacuous)",
		_hash_frames(t1) != _hash_frames(t3))

	# The WoW-arena layer: a caster commits to a big cast; a fighter with a kick breaks it.
	var duel_kick: Dictionary = await _run_duel(true)
	var duel_free: Dictionary = await _run_duel(false)
	_check("casts: the caster commits (cast_start present)", _count(duel_free, "cast_start") > 0)
	_check("casts: uninterrupted casts LAND (control run)", _count(duel_free, "cast_done") > 0)
	_check("interrupt: the kick breaks a committed cast", _count(duel_kick, "interrupt") > 0)
	_check("interrupt: the lockout holds - the kicked school is silent for the full window",
		_lockout_respected(duel_kick, 30))
	var dk2: Dictionary = await _run_duel(true)
	_check("determinism holds with casts and kicks in play",
		_hash_frames(duel_kick) == _hash_frames(dk2))

	# The PEEL: a diver goes for the caster; the bodyguard swaps to the diver and body-blocks.
	var peel: Dictionary = await _run_peel()
	_check("peel: the guard swaps to the charge's attacker (reason logged)",
		_log_has(peel, "a1", "peel b0 off a0"))
	_check("peel: the guard actually fights the diver (strikes a1->b0)",
		_strikes_between(peel, "a1", "b0") > 0)
	_check("threat: the priority tracks the real damager", _log_has(peel, "a0", "(threat)"))
	var peel2: Dictionary = await _run_peel()
	_check("determinism holds with peels in play", _hash_frames(peel) == _hash_frames(peel2))

	# #39: the kite has a cost and an END - no infinite-kite stalemate.
	var kite: Dictionary = await _run_kite()
	_check("kite: the kiter kites (reason logged)", _log_has(kite, "b0", "kiting"))
	_check("kite: the budget ENDS it (standing logged)", _log_has(kite, "b0", "kite budget spent"))
	_check("kite: the fight RESOLVES inside the cap - no infinite kite", str(kite.winner) in ["A", "B"])
	var minr: Dictionary = await _run_minrange()
	_check("min range: casts happened at range (non-vacuous)", _count(minr, "cast_start") > 0)
	_check("min range: no cast starts with the chaser inside it", _min_range_respected(minr, "b0", 8.0))
	var kite2: Dictionary = await _run_kite()
	_check("determinism holds with kiting in play", _hash_frames(kite) == _hash_frames(kite2))

	# REAL KITS: authored moves from data.json drive the casts - names, damage and mana all real.
	var rk: Dictionary = await _run_real_kits()
	_check("real kits: authored moves cast by NAME from data.json", _cast_moves(rk).size() >= 2)
	_check("real kits: authored damage lands (dmg > 0 on cast_done)", _min_cast_dmg(rk) > 0)
	_check("real kits: the fight resolves on authored numbers", str(rk.winner) in ["A", "B"])
	var rk2: Dictionary = await _run_real_kits()
	_check("determinism holds on real kits", _hash_frames(rk) == _hash_frames(rk2))

	# MOVEMENT FEEL: surround slots fan melee into an arc, strafing keeps eyes on the target,
	# soft-avoid separates bodies, and nothing ever teleports.
	var srd: Dictionary = await _run_surround()
	_check("surround: 3 melee on one target occupy >= 2 distinct approach angles",
		_surround_angles(srd, ["a0", "a1", "a2"], "b0") >= 2)
	_check("strafe: attackers in reach keep FACING the target while repositioning",
		_strafe_faces_target(srd, ["a0", "a1", "a2"], "b0"))
	var srd2: Dictionary = await _run_surround()
	_check("determinism holds with slots and steering in play",
		_hash_frames(srd) == _hash_frames(srd2))
	_check("separation: no two living units within 1.6x body radius at fight end",
		_final_separation_ok(r1) and _final_separation_ok(srd))
	_check("anti-teleport: no unit moves more than 2.0 units in one tick (all runs)",
		_no_teleport(r1) and _no_teleport(peel) and _no_teleport(kite) and _no_teleport(srd))

	# FIELD STATUSES: DoTs tick with no attacker action, stun freezes body and hands, hard
	# control severs a committed cast, silence splits casts from melee, a 0-power control move
	# still lands its status, and determinism holds with statuses + DR in play.
	var brn: Dictionary = await _run_burn()
	_check("dot: burn landed on the walker (non-vacuous)", _applied(brn, "burn", "b0").size() > 0)
	_check("dot: the burn target loses HP on ticks where NO strike/cast hits it",
		_hp_drop_without_hit(brn, "b0"))
	_check("bb: an enemy's live ailment is PUBLISHED on the blackboard record (wishlist closed)",
		await _burn_reaches_bb())
	var stn: Dictionary = await _run_stun_freeze()
	var stn_apps: Array = _applied(stn, "stun", "b0")
	_check("stun: landed mid-approach (non-vacuous)", stn_apps.size() > 0)
	_check("stun: the victim does not MOVE for the duration",
		stn_apps.size() > 0 and _frozen_during(stn, "b0", stn_apps[0]))
	_check("stun: the victim neither strikes nor casts for the duration",
		stn_apps.size() > 0 and _silent_during(stn, "b0", stn_apps[0], true))
	var cbk: Dictionary = await _run_castbreak()
	_check("control: a committed cast is LOST to a landed stun (status_break, not interrupt)",
		_count_break(cbk, "stun", "control") > 0)
	var sil: Dictionary = await _run_silence()
	var sil_apps: Array = _applied(sil, "silence", "b0")
	_check("control: a 0-power move still lands its status (silence applied)", sil_apps.size() > 0)
	var sil_ok := sil_apps.size() > 0
	for app in sil_apps:
		if not _silent_during(sil, "b0", app, false):
			sil_ok = false
	_check("silence: no cast_start inside ANY silence window", sil_ok)
	_check("silence: melee is NOT blocked (the silenced hybrid still swings)",
		_strikes_from_in_windows(sil, "b0", sil_apps) > 0)
	var sil2: Dictionary = await _run_silence()
	var brn2: Dictionary = await _run_burn()
	_check("determinism holds with statuses, DoTs and DR in play",
		_hash_frames(sil) == _hash_frames(sil2) and _hash_frames(brn) == _hash_frames(brn2))
	var moves_all := _load_moves()
	_check("kit: a real status-carrying control move builds (Hush)",
		Kit.build(["Hush"], moves_all).size() == 1)
	_check("kit: a status-less enemy debuff now builds (Sunder — mods are live)",
		Kit.build(["Sunder"], moves_all).size() == 1)
	_check("kit: a pure heal builds (Mend — the friendly-cast path)",
		Kit.build(["Mend"], moves_all).size() == 1)
	_check("kit: tauntForce still skips loudly (Taunt — a taunt that never taunts is a lie)",
		Kit.build(["Taunt"], moves_all).size() == 0)
	_check("kit: thorns-only self move still skips loudly (Zone of Control)",
		Kit.build(["Zone of Control"], moves_all).size() == 0)
	_check("kit: allEnemies debuff still skips loudly (Demoralize — no AoE geometry)",
		Kit.build(["Demoralize"], moves_all).size() == 0)

	# THE SUPPORT LAYER: heals reach the wounded ally, wards soak before health, a timed atk
	# buff raises damage then expires, a cleanse scrubs a DoT early — and none of it pauses the
	# stagnation ratchet ('heal'/'buff'/'cleanse' are absent from the pause list BY CHOICE:
	# sustain is not fight progress, so a heal-heavy fight still comes under the growing leash;
	# the resolution checks below are the ratchet's regression guard).
	var hl: Dictionary = await _run_heal()
	var heals_to_tank := _heal_events(hl, "a1", "a0")
	_check("heal: the healer heals the wounded ally (heal a1->a0, amount > 0)",
		heals_to_tank > 0)
	_check("heal: no self-heal hijack (an unhurt healer never heals itself over the tank)",
		_no_self_heal_hijack(hl, "a1", "a0"))
	_check("heal: the ally's HP visibly RISES on the stream", _hp_rises(hl, "a0"))
	_check("heal: a sustained-heal fight still RESOLVES inside the cap (stagnation choice)",
		str(hl.winner) in ["A", "B"])
	var hl2: Dictionary = await _run_heal()
	_check("determinism holds with heals in play", _hash_frames(hl) == _hash_frames(hl2))

	var wd: Dictionary = await _run_ward()
	_check("ward: the absorb pool soaks damage (ward_soak events, non-vacuous)",
		_count(wd, "ward_soak") > 0)
	_check("ward: a fully-soaked hit leaves the defender's HP untouched",
		_ward_full_soak_ok(wd, "a0"))
	_check("ward: the pool DEPLETES/expires (a later strike lands with no soak)",
		_ward_eventually_leaks(wd, "a0"))
	var wd2: Dictionary = await _run_ward()
	_check("determinism holds with wards in play", _hash_frames(wd) == _hash_frames(wd2))

	var ab: Dictionary = await _run_atkbuff()
	var ab_win := _buff_window(ab, "a0")
	_check("buff: the self atk buff applies (buff event, non-vacuous)", ab_win.t >= 0)
	_check("buff: buffed strikes hit HARDER than every post-expiry strike, then it EXPIRES",
		_buff_raises_then_expires(ab, "a0", ab_win))

	var cl: Dictionary = await _run_cleanse()
	_check("cleanse: a DoT is scrubbed EARLY (battle.ts:423 — ailments go, beneficial stays)",
		_cleanse_scrubbed_burn(cl, "a2", "a0"))

	print("SIM PROBE %s (%d failures)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)


func _team_a_y_spread(res: Dictionary, tick: int) -> float:
	var f: Dictionary = res.frames[mini(tick, res.frames.size() - 1)]
	var lo := INF
	var hi := -INF
	for u in f.units:
		if u.team == "A":
			lo = minf(lo, u.pos.y)
			hi = maxf(hi, u.pos.y)
	return hi - lo


func _count(res: Dictionary, kind: String) -> int:
	var n := 0
	for f in res.frames:
		for e in f.events:
			if str(e.kind) == kind:
				n += 1
	return n


## 2v2 close-quarters duel: one side has an interrupter, the other a hard-hitting caster.
func _run_duel(with_kick: bool) -> Dictionary:
	var kit_fighter: Array = [{"name": "Kick", "kind": "interrupt"}] if with_kick else []
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-12, 0), "speed": 10.0,
			"stats": {"STR": 70, "CON": 60, "INT": 10, "WIS": 20},
			"kit": kit_fighter, "tactics": {"target_priority": "casters", "positional": "push"}},
		{"id": "a1", "team": "A", "pos": Vector2(-12, 6), "speed": 9.0,
			"stats": {"STR": 50, "CON": 50, "INT": 10, "WIS": 20},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
		{"id": "b0", "team": "B", "pos": Vector2(12, 0), "speed": 7.0,
			"stats": {"STR": 15, "CON": 40, "INT": 85, "WIS": 60},
			"kit": [{"name": "Pyroblast", "kind": "cast", "power": 55, "cast_time": 2.2,
				"cooldown": 3.0, "mana": 8, "channel": "magic"}],
			"tactics": {"target_priority": "weakest", "positional": "hold"}},
		{"id": "b1", "team": "B", "pos": Vector2(12, 6), "speed": 8.0,
			"stats": {"STR": 55, "CON": 55, "INT": 10, "WIS": 20},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
	]
	var sim = Sim.new()
	sim.setup(777, us, Vector2(80, 44), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-12, 0), Vector2(12, 0))
	if not ok:
		return {}
	return sim.run()


## After every interrupt, the kicked unit must start no cast for `lockout` ticks - the
## mechanically exact contract, immune to fight-length differences between runs.
func _lockout_respected(res: Dictionary, lockout: int) -> bool:
	var found := false
	for i in res.frames.size():
		for e in res.frames[i].events:
			if str(e.kind) == "interrupt":
				found = true
				for j in range(i, mini(i + lockout, res.frames.size())):
					for e2 in res.frames[j].events:
						if str(e2.kind) == "cast_start" and str(e2.from) == str(e.to):
							print("    LOCKOUT VIOLATION: kick@%d cast_start@%d by %s move %s" % [i, j, str(e2.from), str(e2.move)])
							return false
	return found


func _log_has(res: Dictionary, unit_id: String, needle: String) -> bool:
	for entry in res.decision_logs.get(unit_id, []):
		if str(entry.get("reason", "")).contains(needle):
			return true
	return false


func _strikes_between(res: Dictionary, from_id: String, to_id: String) -> int:
	var n := 0
	for f in res.frames:
		for e in f.events:
			if str(e.kind) == "strike" and str(e.get("from", "")) == from_id and str(e.get("to", "")) == to_id:
				n += 1
	return n


## The peel scenario: a0 is a soft caster on `threat` priority, a1 its bodyguard on `guard`,
## b0 a fast diver ordered onto the weakest, b1 a frontliner to keep a1 honest.
func _run_peel() -> Dictionary:
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-24, 0), "speed": 6.0,
			"stats": {"STR": 15, "CON": 30, "INT": 80, "WIS": 55},
			"kit": [{"name": "Bolt", "kind": "cast", "power": 30, "cast_time": 1.4,
				"cooldown": 2.0, "mana": 5, "channel": "magic"}],
			"tactics": {"target_priority": "threat", "positional": "hold"}},
		{"id": "a1", "team": "A", "pos": Vector2(-18, 2), "speed": 9.5,
			"stats": {"STR": 65, "CON": 70, "INT": 10, "WIS": 25},
			"tactics": {"target_priority": "nearest", "positional": "guard", "guard_ally": "a0"}},
		{"id": "b0", "team": "B", "pos": Vector2(24, -4), "speed": 11.0,
			"stats": {"STR": 60, "CON": 35, "INT": 10, "WIS": 15},
			"tactics": {"target_priority": "weakest", "positional": "dive"}},
		{"id": "b1", "team": "B", "pos": Vector2(24, 4), "speed": 8.0,
			"stats": {"STR": 55, "CON": 60, "INT": 10, "WIS": 20},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
	]
	var sim = Sim.new()
	sim.setup(4242, us, Vector2(96, 52), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-20, 0), Vector2(20, 0))
	if not ok:
		return {}
	return sim.run()


## Fast kiting caster with a min-range spell vs a slower melee chaser.
func _run_kite() -> Dictionary:
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-20, 0), "speed": 8.5,
			"stats": {"STR": 70, "CON": 95, "INT": 10, "WIS": 45},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
		# A PURE runner: no kit, so nothing interrupts the retreat - the budget is the only
		# thing that can end this chase, which is exactly what the check needs to see.
		# CON 90 (was 45): velocity smoothing makes each kite episode start from rest, so the
		# runner takes more hits before the budget spends - it must SURVIVE to the budget end.
		{"id": "b0", "team": "B", "pos": Vector2(20, 0), "speed": 10.0, "kite_budget": 25,
			"stats": {"STR": 15, "CON": 90, "INT": 60, "WIS": 55},
			"tactics": {"target_priority": "nearest", "positional": "kite"}},
	]
	var sim = Sim.new()
	sim.setup(51, us, Vector2(96, 52), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-20, 0), Vector2(20, 0))
	if not ok:
		return {}
	return sim.run()


## No cast_start by `caster` on a frame where its nearest enemy sat inside `min_range`.
func _min_range_respected(res: Dictionary, caster: String, min_range: float) -> bool:
	for f in res.frames:
		var cpos = null
		var epos = null
		for u in f.units:
			if str(u.id) == caster:
				cpos = u.pos
			elif u.alive:
				epos = u.pos
		if cpos == null or epos == null:
			continue
		for e in f.events:
			if str(e.kind) == "cast_start" and str(e.from) == caster \
					and Vector2(cpos).distance_to(epos) < min_range - 0.01:
				return false
	return true


## A standing caster with a min-range spell as melee closes: casts fire at range, never inside.
func _run_minrange() -> Dictionary:
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-20, 0), "speed": 8.5,
			"stats": {"STR": 70, "CON": 80, "INT": 10, "WIS": 30},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
		{"id": "b0", "team": "B", "pos": Vector2(20, 0), "speed": 7.0,
			"stats": {"STR": 15, "CON": 50, "INT": 70, "WIS": 55},
			"kit": [{"name": "Frostbolt", "kind": "cast", "power": 20, "cast_time": 1.2,
				"cooldown": 1.5, "mana": 4, "channel": "magic", "min_range": 8.0}],
			"tactics": {"target_priority": "nearest", "positional": "hold"}},
	]
	var sim = Sim.new()
	sim.setup(52, us, Vector2(96, 52), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-20, 0), Vector2(20, 0))
	if not ok:
		return {}
	return sim.run()


## Three melee ordered onto ONE tank: the surround must fan them into an arc, not a stack.
func _run_surround() -> Dictionary:
	var melee := {"target_priority": "nearest", "positional": "push"}
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-24, -6), "speed": 9.0,
			"stats": {"STR": 45, "CON": 60, "INT": 10, "WIS": 15}, "tactics": melee},
		{"id": "a1", "team": "A", "pos": Vector2(-24, 0), "speed": 8.5,
			"stats": {"STR": 45, "CON": 60, "INT": 10, "WIS": 15}, "tactics": melee},
		{"id": "a2", "team": "A", "pos": Vector2(-24, 6), "speed": 8.0,
			"stats": {"STR": 45, "CON": 60, "INT": 10, "WIS": 15}, "tactics": melee},
		{"id": "b0", "team": "B", "pos": Vector2(20, 0), "speed": 7.0,
			"stats": {"STR": 20, "CON": 160, "INT": 10, "WIS": 30},
			"tactics": {"target_priority": "nearest", "positional": "hold"}},
	]
	var sim = Sim.new()
	sim.setup(303, us, Vector2(96, 52), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-20, 0), Vector2(20, 0))
	if not ok:
		return {}
	return sim.run()


## Best count over the fight of DISTINCT 45-degree bearing buckets occupied by the attackers,
## sampled only on frames where the target lives and all attackers stand within reach of it.
func _surround_angles(res: Dictionary, attackers: Array, target: String) -> int:
	var best := 0
	for f in res.frames:
		var tpos = null
		var pos := {}
		for u in f.units:
			if str(u.id) == target and u.alive:
				tpos = u.pos
			elif str(u.id) in attackers and u.alive:
				pos[str(u.id)] = u.pos
		if tpos == null or pos.size() < attackers.size():
			continue
		var buckets := {}
		var all_in_reach := true
		for a in attackers:
			var d: float = Vector2(pos[a]).distance_to(tpos)
			if d > 6.6:  # BASE_REACH
				all_in_reach = false
				break
			buckets[int(roundf(Vector2(pos[a] - tpos).angle() / (TAU / 8.0)))] = true
		if all_in_reach:
			best = maxi(best, buckets.size())
	return best


## Every frame where an attacker is IN REACH of the living target and MOVING, its facing must
## point at the target (dot > 0.5) - facing and move_dir decouple during the strafe.
func _strafe_faces_target(res: Dictionary, attackers: Array, target: String) -> bool:
	var samples := 0
	for f in res.frames:
		var tpos = null
		for u in f.units:
			if str(u.id) == target and u.alive:
				tpos = u.pos
		if tpos == null:
			continue
		for u in f.units:
			if not (str(u.id) in attackers) or not u.alive:
				continue
			# d <= 5.0 post-move guarantees the unit was ALREADY in reach before it moved
			# (max tick move ~1.1 < 6.27-5.0), i.e. the strafe branch ran — boundary frames
			# where a unit crosses into reach mid-turn are the approach branch, not strafe.
			var d: float = Vector2(u.pos).distance_to(tpos)
			if d > 5.0 or d < 0.5 or Vector2(u.move_dir) == Vector2.ZERO:
				continue
			samples += 1
			if Vector2(u.facing).dot((Vector2(tpos) - u.pos).normalized()) < 0.5:
				return false
	return samples >= 3  # non-vacuous: the strafe actually happened


## Final frame: every pair of living units at least 1.6x body radius apart - the blob is dead.
func _final_separation_ok(res: Dictionary) -> bool:
	var f: Dictionary = res.frames[res.frames.size() - 1]
	var live: Array = []
	for u in f.units:
		if u.alive:
			live.append(u)
	for i in live.size():
		for j in range(i + 1, live.size()):
			if Vector2(live[i].pos).distance_to(live[j].pos) < Sim.BODY_RADIUS * 1.6 - 0.01:
				print("    SEPARATION VIOLATION: %s-%s at %.2f" % [live[i].id, live[j].id,
					Vector2(live[i].pos).distance_to(live[j].pos)])
				return false
	return true


## The anti-teleport tripwire from the old repo: nothing displaces > 2.0 units in one tick.
func _no_teleport(res: Dictionary) -> bool:
	for i in range(1, res.frames.size()):
		var prev := {}
		for u in res.frames[i - 1].units:
			if u.alive:
				prev[str(u.id)] = u.pos
		for u in res.frames[i].units:
			if u.alive and prev.has(str(u.id)) \
					and Vector2(u.pos).distance_to(prev[str(u.id)]) > 2.0:
				print("    TELEPORT: %s moved %.2f at tick %d" % [str(u.id),
					Vector2(u.pos).distance_to(prev[str(u.id)]), i])
				return false
	return true


func _load_moves() -> Array:
	var txt := FileAccess.get_file_as_string("res://data/data.json")
	return JSON.parse_string(txt)["moves"]


func _cast_moves(res: Dictionary) -> Dictionary:
	var seen := {}
	for f in res.frames:
		for e in f.events:
			if str(e.kind) == "cast_done":
				seen[str(e.move)] = true
	return seen


func _min_cast_dmg(res: Dictionary) -> int:
	var lo := 999999
	for f in res.frames:
		for e in f.events:
			if str(e.kind) == "cast_done":
				lo = mini(lo, int(e.dmg))
	return 0 if lo == 999999 else lo


## Deterministic pick from the data: the two first magic damage moves by name, kitted onto
## casters against a melee pair. Everything the casts do comes from authoring.
func _run_real_kits() -> Dictionary:
	var moves := _load_moves()
	var magic: Array = moves.filter(func(m): return str(m.get("channel")) == "magic" and str(m.get("type")) == "damage")
	magic.sort_custom(func(a, b): return str(a.name) < str(b.name))
	var kit1 := Kit.build([str(magic[0].name)], moves)
	var kit2 := Kit.build([str(magic[1].name)], moves)
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-22, -4), "speed": 8.5,
			"stats": {"STR": 70, "CON": 75, "INT": 10, "WIS": 30},
			"kit": [Kit.kick()], "tactics": {"target_priority": "casters", "positional": "push"}},
		{"id": "a1", "team": "A", "pos": Vector2(-22, 4), "speed": 7.5,
			"stats": {"STR": 20, "CON": 45, "INT": 75, "WIS": 60},
			"kit": kit1, "tactics": {"target_priority": "weakest", "positional": "hold"}},
		{"id": "b0", "team": "B", "pos": Vector2(22, -4), "speed": 8.0,
			"stats": {"STR": 65, "CON": 70, "INT": 10, "WIS": 25},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
		{"id": "b1", "team": "B", "pos": Vector2(22, 4), "speed": 7.0,
			"stats": {"STR": 20, "CON": 50, "INT": 80, "WIS": 55},
			"kit": kit2, "tactics": {"target_priority": "weakest", "positional": "hold"}},
	]
	var sim = Sim.new()
	sim.setup(9001, us, Vector2(100, 56), [{"rect": Rect2(-3, -3, 6, 6)}])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-22, 0), Vector2(22, 0))
	if not ok:
		return {}
	return sim.run()


# ═══ FIELD-STATUS SCENARIOS ══════════════════════════════════════════════════════════════════


## DoT: a standing caster lights the slow walker on fire; the burn must tick HP away on frames
## where nothing else touches the victim.
func _run_burn() -> Dictionary:
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-14, 0), "speed": 8.0,
			"stats": {"STR": 10, "CON": 45, "INT": 70, "WIS": 60},
			"kit": [{"name": "Ember", "kind": "cast", "power": 12, "accuracy": 100, "cast_time": 1.0,
				"cooldown": 4.0, "mana": 3, "channel": "magic",
				"status": {"kind": "burn", "chance": 100, "duration": 3}}],
			"tactics": {"target_priority": "nearest", "positional": "hold"}},
		{"id": "b0", "team": "B", "pos": Vector2(14, 0), "speed": 5.0,
			"stats": {"STR": 40, "CON": 120, "INT": 10, "WIS": 20},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
	]
	var sim = Sim.new()
	sim.setup(61, us, Vector2(96, 52), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-14, 0), Vector2(14, 0))
	if not ok:
		return {}
	return sim.run()


## WISHLIST close-out (enemies[i].statuses): white-box — step the burn duel until the burn is
## LIVE on b0, then fill the caster's blackboard and read b0's record. Passes only if the
## published statuses list is non-empty AND minimal ({kind} only — no timers for the tree to
## lean on). Beneficial filtering is the sim's job (see _fill_bb); this pins the ailment path.
func _burn_reaches_bb() -> bool:
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-14, 0), "speed": 8.0,
			"stats": {"STR": 10, "CON": 45, "INT": 70, "WIS": 60},
			"kit": [{"name": "Ember", "kind": "cast", "power": 12, "accuracy": 100, "cast_time": 1.0,
				"cooldown": 4.0, "mana": 3, "channel": "magic",
				"status": {"kind": "burn", "chance": 100, "duration": 3}}],
			"tactics": {"target_priority": "nearest", "positional": "hold"}},
		{"id": "b0", "team": "B", "pos": Vector2(14, 0), "speed": 5.0,
			"stats": {"STR": 40, "CON": 120, "INT": 10, "WIS": 20},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
	]
	var sim = Sim.new()
	sim.setup(61, us, Vector2(96, 52), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-14, 0), Vector2(14, 0))
	if not ok:
		return false
	while sim.winner == "" and sim.tick_now < 600:
		sim._step()
		var b0 = sim._unit("b0")
		if b0 == null or not b0.alive or (b0.statuses as Array).is_empty():
			continue
		var a0 = sim._unit("a0")
		sim._fill_bb(a0)
		for e in a0.bb.get_value("enemies", []):
			if str(e.id) != "b0":
				continue
			var sts: Array = e.get("statuses", [])
			if sts.is_empty():
				return false
			for s in sts:
				if not (s is Dictionary) or (s as Dictionary).keys() != ["kind"]:
					return false   # record leaked payload — the contract is minimal {kind}
			return true
	return false   # burn never became live-visible — vacuous, so fail loudly


## Stun freeze: the holder stuns the approaching melee at range — the victim must not move,
## strike or cast for the (DR-resolved) duration the status_applied event reports.
func _run_stun_freeze() -> Dictionary:
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-22, 0), "speed": 8.0,
			"stats": {"STR": 10, "CON": 40, "INT": 60, "WIS": 60},
			"kit": [{"name": "Concuss", "kind": "cast", "power": 5, "accuracy": 100, "cast_time": 0.8,
				"cooldown": 5.0, "mana": 3, "channel": "magic",
				"status": {"kind": "stun", "chance": 100, "duration": 2}}],
			"tactics": {"target_priority": "nearest", "positional": "hold"}},
		{"id": "b0", "team": "B", "pos": Vector2(22, 0), "speed": 7.0,
			"stats": {"STR": 50, "CON": 30, "INT": 10, "WIS": 15},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
	]
	var sim = Sim.new()
	sim.setup(62, us, Vector2(96, 52), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-22, 0), Vector2(22, 0))
	if not ok:
		return {}
	return sim.run()


## Cast break: two standing casters — one on a fast stun, one on a long 2.5s commitment. The
## stun must sever the long cast: status_break with cause "control", never an "interrupt".
func _run_castbreak() -> Dictionary:
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-12, 0), "speed": 8.0,
			"stats": {"STR": 10, "CON": 40, "INT": 60, "WIS": 70},
			"kit": [{"name": "Concuss", "kind": "cast", "power": 5, "accuracy": 100, "cast_time": 0.8,
				"cooldown": 3.0, "mana": 3, "channel": "magic",
				"status": {"kind": "stun", "chance": 100, "duration": 1}}],
			"tactics": {"target_priority": "nearest", "positional": "hold"}},
		{"id": "b0", "team": "B", "pos": Vector2(12, 0), "speed": 8.0,
			"stats": {"STR": 10, "CON": 20, "INT": 60, "WIS": 70},
			"kit": [{"name": "Zap", "kind": "cast", "power": 10, "accuracy": 100, "cast_time": 2.5,
				"cooldown": 0.5, "mana": 2, "channel": "magic"}],
			"tactics": {"target_priority": "nearest", "positional": "hold"}},
	]
	var sim = Sim.new()
	sim.setup(63, us, Vector2(80, 44), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-12, 0), Vector2(12, 0))
	if not ok:
		return {}
	return sim.run()


## Silence: a 0-power hush vs a melee/caster hybrid. The hush must LAND its status (decision
## #20 analogue: same accuracy roll, no damage needed), the silenced hybrid must start no cast
## inside the window — and must still swing its fists.
func _run_silence() -> Dictionary:
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-16, 0), "speed": 9.0,
			"stats": {"STR": 55, "CON": 60, "INT": 20, "WIS": 40},
			"kit": [{"name": "Hush0", "kind": "cast", "power": 0, "accuracy": 100, "cast_time": 1.0,
				"cooldown": 5.0, "mana": 3, "channel": "voice",
				"status": {"kind": "silence", "chance": 100, "duration": 3}}],
			"tactics": {"target_priority": "nearest", "positional": "push"}},
		{"id": "b0", "team": "B", "pos": Vector2(16, 0), "speed": 8.0,
			"stats": {"STR": 45, "CON": 60, "INT": 60, "WIS": 50},
			"kit": [{"name": "Zap", "kind": "cast", "power": 15, "accuracy": 100, "cast_time": 1.2,
				"cooldown": 1.0, "mana": 2, "channel": "magic"}],
			"tactics": {"target_priority": "nearest", "positional": "push"}},
	]
	var sim = Sim.new()
	sim.setup(64, us, Vector2(96, 52), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-16, 0), Vector2(16, 0))
	if not ok:
		return {}
	return sim.run()


## All status_applied events of `status` onto `to_id`, as {t: frame index, n: window ticks
## derived from the event's own DR-resolved seconds}.
func _applied(res: Dictionary, status: String, to_id: String) -> Array:
	var out: Array = []
	for i in res.frames.size():
		for e in res.frames[i].events:
			if str(e.kind) == "status_applied" and str(e.get("status", "")) == status \
					and str(e.get("to", "")) == to_id:
				out.append({"t": i, "n": int(float(e.get("seconds", 0.0)) / 0.1)})
	return out


## True if some frame shows the victim's HP dropping with a status_tick and NO strike/cast
## landing on it that tick — damage with no attacker action, the DoT signature.
func _hp_drop_without_hit(res: Dictionary, victim: String) -> bool:
	for i in range(1, res.frames.size()):
		var prev_hp := -1
		var cur_hp := -1
		for u in res.frames[i - 1].units:
			if str(u.id) == victim:
				prev_hp = int(u.hp)
		for u in res.frames[i].units:
			if str(u.id) == victim:
				cur_hp = int(u.hp)
		if prev_hp <= cur_hp or cur_hp <= 0:
			continue
		var hit := false
		var ticked := false
		for e in res.frames[i].events:
			if str(e.kind) in ["strike", "cast_done"] and str(e.get("to", "")) == victim:
				hit = true
			if str(e.kind) == "status_tick" and str(e.get("to", "")) == victim:
				ticked = true
		if ticked and not hit:
			return true
	return false


## Position pinned for the whole control window (movement for the application tick itself has
## already happened, so the anchor is t+1; pushes would move it, but the scenarios stun at range).
func _frozen_during(res: Dictionary, victim: String, app: Dictionary) -> bool:
	var t := int(app.t)
	var n := int(app.n)
	if t + 2 >= res.frames.size() or n < 3:
		return false
	var anchor = null
	for u in res.frames[t + 1].units:
		if str(u.id) == victim:
			anchor = u.pos
	if anchor == null:
		return false
	for j in range(t + 1, mini(t + n, res.frames.size())):
		for u in res.frames[j].units:
			if str(u.id) == victim and Vector2(u.pos).distance_to(anchor) > 0.001:
				return false
	return true


## No cast_start (and, if `include_strikes`, no strike/miss) FROM the victim inside the window.
func _silent_during(res: Dictionary, victim: String, app: Dictionary, include_strikes: bool) -> bool:
	var t := int(app.t)
	var n := int(app.n)
	for j in range(t + 1, mini(t + n, res.frames.size())):
		for e in res.frames[j].events:
			if str(e.get("from", "")) != victim:
				continue
			if str(e.kind) == "cast_start":
				return false
			if include_strikes and str(e.kind) in ["strike", "miss"]:
				return false
	return true


func _count_break(res: Dictionary, status: String, cause: String) -> int:
	var c := 0
	for f in res.frames:
		for e in f.events:
			if str(e.kind) == "status_break" and str(e.get("status", "")) == status \
					and str(e.get("cause", "")) == cause:
				c += 1
	return c


func _strikes_from_in_windows(res: Dictionary, attacker: String, apps: Array) -> int:
	var c := 0
	for app in apps:
		for j in range(int(app.t), mini(int(app.t) + int(app.n), res.frames.size())):
			for e in res.frames[j].events:
				if str(e.kind) == "strike" and str(e.get("from", "")) == attacker:
					c += 1
	return c


# ═══ SUPPORT-LAYER SCENARIOS ═════════════════════════════════════════════════════════════════


## Tank a0 brawls b0 up front; healer a1 stands off on hold with an ally-targeted heal. b0's
## nearest enemy stays the tank, so the healer is never wounded — every heal must go forward.
func _run_heal() -> Dictionary:
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-8, 0), "speed": 9.0,
			"stats": {"STR": 45, "CON": 80, "INT": 10, "WIS": 20},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
		{"id": "a1", "team": "A", "pos": Vector2(-20, 0), "speed": 7.0,
			"stats": {"STR": 10, "CON": 40, "INT": 40, "WIS": 60},
			"kit": [{"name": "Mend0", "kind": "cast", "power": 40, "cast_time": 0.8,
				"cooldown": 5.0, "mana": 3, "channel": "support", "target": "ally", "range": 40.0}],
			"tactics": {"target_priority": "nearest", "positional": "hold"}},
		{"id": "b0", "team": "B", "pos": Vector2(8, 0), "speed": 8.0,
			"stats": {"STR": 60, "CON": 70, "INT": 10, "WIS": 20},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
	]
	var sim = Sim.new()
	sim.setup(71, us, Vector2(96, 52), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-8, 0), Vector2(8, 0))
	if not ok:
		return {}
	return sim.run()


func _heal_events(res: Dictionary, from_id: String, to_id: String) -> int:
	var n := 0
	for f in res.frames:
		for e in f.events:
			if str(e.kind) == "heal" and str(e.get("from", "")) == from_id \
					and str(e.get("to", "")) == to_id and int(e.get("amount", 0)) > 0:
				n += 1
	return n


## A heal to SELF is a hijack only if the tank stood alive and MORE wounded that frame.
func _no_self_heal_hijack(res: Dictionary, healer: String, tank: String) -> bool:
	for i in res.frames.size():
		for e in res.frames[i].events:
			if str(e.kind) != "heal" or str(e.get("to", "")) != healer:
				continue
			var hf := 1.0
			var tf := 1.0
			var tank_alive := false
			for u in res.frames[i].units:
				if str(u.id) == healer:
					hf = float(u.hp) / float(u.max_hp)
				elif str(u.id) == tank and u.alive:
					tank_alive = true
					tf = float(u.hp) / float(u.max_hp)
			if tank_alive and tf < hf:
				return false
	return true


func _hp_rises(res: Dictionary, uid: String) -> bool:
	var prev := -1
	for f in res.frames:
		for u in f.units:
			if str(u.id) == uid and u.alive:
				if prev >= 0 and int(u.hp) > prev:
					return true
				prev = int(u.hp)
	return false


## Self-warder a0 walks in against a harder hitter; the ward must soak before health.
func _run_ward() -> Dictionary:
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-12, 0), "speed": 8.5,
			"stats": {"STR": 40, "CON": 100, "INT": 10, "WIS": 25},
			"kit": [{"name": "Aegis0", "kind": "cast", "power": 0, "cast_time": 0.5,
				"cooldown": 60.0, "mana": 2, "channel": "support", "target": "self",
				"effects": {"ward": 80, "duration": 6}}],
			"tactics": {"target_priority": "nearest", "positional": "push"}},
		{"id": "b0", "team": "B", "pos": Vector2(12, 0), "speed": 8.0,
			"stats": {"STR": 55, "CON": 60, "INT": 10, "WIS": 20},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
	]
	var sim = Sim.new()
	sim.setup(72, us, Vector2(96, 52), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-12, 0), Vector2(12, 0))
	if not ok:
		return {}
	return sim.run()


## Every frame where a strike on `uid` was FULLY soaked (ward_soak amount == strike dmg), the
## victim's streamed HP must not have dropped from the previous frame. Non-vacuous: at least
## one such frame must exist.
func _ward_full_soak_ok(res: Dictionary, uid: String) -> bool:
	var found := false
	for i in range(1, res.frames.size()):
		var strike_dmg := -1
		var soak := -1
		for e in res.frames[i].events:
			if str(e.kind) == "strike" and str(e.get("to", "")) == uid:
				strike_dmg = int(e.get("dmg", 0))
			elif str(e.kind) == "ward_soak" and str(e.get("to", "")) == uid:
				soak = int(e.get("amount", 0))
		if strike_dmg <= 0 or soak != strike_dmg:
			continue
		found = true
		var prev_hp := -1
		var cur_hp := -1
		for u in res.frames[i - 1].units:
			if str(u.id) == uid:
				prev_hp = int(u.hp)
		for u in res.frames[i].units:
			if str(u.id) == uid:
				cur_hp = int(u.hp)
		if cur_hp < prev_hp:
			print("    WARD LEAK: full soak at frame %d but hp %d -> %d" % [i, prev_hp, cur_hp])
			return false
	return found


## Depletion/expiry: some LATER strike on `uid` lands with no soak at all in its frame.
func _ward_eventually_leaks(res: Dictionary, uid: String) -> bool:
	var soaked_once := false
	for f in res.frames:
		var hit := false
		var soak := false
		for e in f.events:
			if str(e.kind) == "strike" and str(e.get("to", "")) == uid and int(e.get("dmg", 0)) > 0:
				hit = true
			elif str(e.kind) == "ward_soak" and str(e.get("to", "")) == uid:
				soak = true
		if soak:
			soaked_once = true
		elif hit and soaked_once:
			return true
	return false


## Melee a0 with a big timed self atk buff (x2.5, 2 rounds) against a wall that barely hits
## back — buffed strikes must out-damage every post-expiry strike, floor above ceiling.
func _run_atkbuff() -> Dictionary:
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-10, 0), "speed": 9.0,
			"stats": {"STR": 60, "CON": 60, "INT": 10, "WIS": 15},
			"kit": [{"name": "Rage0", "kind": "cast", "power": 0, "cast_time": 0.5,
				"cooldown": 150.0, "mana": 2, "channel": "support", "target": "self",
				"effects": {"atkBuff": 2.0, "duration": 2}}],
			"tactics": {"target_priority": "nearest", "positional": "push"}},
		{"id": "b0", "team": "B", "pos": Vector2(10, 0), "speed": 7.0,
			"stats": {"STR": 20, "CON": 200, "INT": 10, "WIS": 30},
			"tactics": {"target_priority": "nearest", "positional": "hold"}},
	]
	var sim = Sim.new()
	sim.setup(73, us, Vector2(96, 52), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-10, 0), Vector2(10, 0))
	if not ok:
		return {}
	return sim.run()


## First 'buff' event on `uid`: {t: frame, n: window ticks from the event's own seconds}.
func _buff_window(res: Dictionary, uid: String) -> Dictionary:
	for i in res.frames.size():
		for e in res.frames[i].events:
			if str(e.kind) == "buff" and str(e.get("to", "")) == uid:
				return {"t": i, "n": int(float(e.get("seconds", 0.0)) / 0.1)}
	return {"t": -1, "n": 0}


## min(strike dmg inside the window) > max(strike dmg after it) — with atkBuff 2.0 the buffed
## floor (x3.0 * 0.85 variance) clears the unbuffed CRIT ceiling (x1.5 * 1.15), so rng cannot
## blur the comparison. Two guards keep the margin honest: boundary frames (+-3 ticks around
## expiry) are skipped, and after-window strikes stop at frame 290 — the opening-mitigation
## bonus fades from t=30s, which would inflate late unbuffed hits past the buffed floor.
## Both sides must be non-empty (expiry actually observed).
func _buff_raises_then_expires(res: Dictionary, uid: String, win: Dictionary) -> bool:
	if int(win.t) < 0:
		return false
	var lo_in := 999999
	var hi_after := -1
	for i in range(int(win.t), mini(res.frames.size(), 291)):
		for e in res.frames[i].events:
			if str(e.kind) != "strike" or str(e.get("from", "")) != uid:
				continue
			if i <= int(win.t) + int(win.n) - 3:
				lo_in = mini(lo_in, int(e.get("dmg", 0)))
			elif i >= int(win.t) + int(win.n) + 3:
				hi_after = maxi(hi_after, int(e.get("dmg", 0)))
	if lo_in == 999999 or hi_after < 0:
		print("    BUFF WINDOW VACUOUS: strikes in-window? %s after? %s" % [lo_in != 999999, hi_after >= 0])
		return false
	if lo_in <= hi_after:
		print("    BUFF FLAT: min buffed %d <= max unbuffed %d" % [lo_in, hi_after])
		return false
	return true


## Burner b0 sets the tank alight; cleanser a2 scrubs it early. The DoT must vanish from the
## victim's streamed status chips well before its natural expiry.
func _run_cleanse() -> Dictionary:
	var us: Array = [
		{"id": "a0", "team": "A", "pos": Vector2(-8, 0), "speed": 8.5,
			"stats": {"STR": 50, "CON": 90, "INT": 10, "WIS": 20},
			"tactics": {"target_priority": "nearest", "positional": "push"}},
		{"id": "a2", "team": "A", "pos": Vector2(-20, 0), "speed": 7.0,
			"stats": {"STR": 10, "CON": 40, "INT": 40, "WIS": 60},
			"kit": [{"name": "Purify0", "kind": "cast", "power": 0, "cast_time": 0.6,
				"cooldown": 6.0, "mana": 3, "channel": "support", "target": "ally", "range": 40.0,
				"effects": {"cleanse": true}}],
			"tactics": {"target_priority": "nearest", "positional": "hold"}},
		{"id": "b0", "team": "B", "pos": Vector2(10, 0), "speed": 8.0,
			"stats": {"STR": 30, "CON": 70, "INT": 60, "WIS": 40},
			"kit": [{"name": "Ember", "kind": "cast", "power": 8, "accuracy": 100, "cast_time": 1.0,
				"cooldown": 6.0, "mana": 3, "channel": "magic",
				"status": {"kind": "burn", "chance": 100, "duration": 4}}],
			"tactics": {"target_priority": "nearest", "positional": "hold"}},
	]
	var sim = Sim.new()
	sim.setup(74, us, Vector2(96, 52), [])
	var ok: bool = await sim.nav.until_ready(get_tree(), Vector2(-8, 0), Vector2(10, 0))
	if not ok:
		return {}
	return sim.run()


## A 'cleanse' event from the cleanser broke "burn" on the victim, AND the victim's very next
## frame carries no burn chip while the burn still had >1s left to run — scrubbed, not expired.
func _cleanse_scrubbed_burn(res: Dictionary, cleanser: String, victim: String) -> bool:
	for i in res.frames.size():
		for e in res.frames[i].events:
			if str(e.kind) != "cleanse" or str(e.get("from", "")) != cleanser \
					or str(e.get("to", "")) != victim:
				continue
			if not ("burn" in (e.get("broke", []) as Array)):
				continue
			# The burn must have had real time left the frame BEFORE the scrub.
			var left := 0.0
			for u in res.frames[maxi(0, i - 1)].units:
				if str(u.id) == victim:
					for s in u.statuses:
						if str(s.kind) == "burn":
							left = maxf(left, float(s.left))
			if left <= 1.0:
				continue
			if i + 1 >= res.frames.size():
				continue
			var gone := true
			for u in res.frames[i + 1].units:
				if str(u.id) == victim:
					for s in u.statuses:
						if str(s.kind) == "burn":
							gone = false
			if gone:
				return true
	return false
