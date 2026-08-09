## THE DYNASTY — is the generational half of the game REACHABLE inside one career?
##
## Run: P:/Godot_v4.7.1-stable_win64.exe --headless --path . res://scenes/_probe_breed.tscn
##      …                                --headless --path . res://scenes/_probe_breed.tscn -- --quick
##
## ⚠️ CLAUDE.md calls this half the game — *"the meta-game is advanced training knowledge PLUS
## breeding the right monsters… knowing WHICH monster to make is the skill."* The handoff into
## this round says the arc autopilot fired **0 breeds in 483 weeks**, first preserve at week 336,
## best potential ×1.00. A generational system that never fires in ten in-game years is not a
## deferred feature, it is a broken promise — but "never fires" is exactly the shape of claim this
## project has been wrong about ten times, so nothing here is inherited. Every number below is
## measured on the current build.
##
## ⚠️ THIS FILE CONTAINS NO SECOND COPY OF ANYTHING. The dynasty rules are read out of
## `ui/breeding_ui.gd` (the screen that owns them) and children are built by calling its own
## `_make_child`; the career is `_probe_career_arc.gd` SUBCLASSED, never forked, exactly as
## `_probe_gold_wall.gd` does it. The previous cut of this probe re-typed `STEP := 0.06` and
## `HEAD := 0.30` by hand and was wrong about both for months.
##
## ⚠️ EVERY SECTION CARRIES A LIVENESS CANARY. A probe that cannot prove it would have SEEN a
## breed is not evidence that no breed happened. Section 1 constructs a fully-satisfied state and
## asserts a child comes out of it; section 4 asserts its policy override actually changed the
## barn. A failed canary sets `_ok = false` and this probe exits 1.
##
## ⚠️ THIS PROBE EXITS 1 ON THE CURRENT BUILD AND THAT IS THE POINT. Section 3b's canary fires:
## `potential` — the bloodline multiplier, the only thing that lifts a training ceiling above the
## league cap, and the entire economic case for breeding — is applied by NOTHING.
## `week.gd:apply_activity` clamps every drill to the raw league `cap`, and `week.gd:stat_cap_for`
## (which exists, and does the multiplication) is called only by probes. Trained 500 weeks with
## the clock removed, a ×1.00 and a ×2.00 monster finish on the SAME 750. Fixing that is one line
## in `week.gd`, which is not this workstream's file — so the canary stays armed, and it goes
## green the week someone lands it.
##
## SECTIONS
##   1  THE GATE CHAIN   — every precondition to a first breed, and which one binds first
##   2  THE BILL         — what preserving really costs over a career, against its alternative
##   3  THE PAYOFF       — a bred foal against the best thing on the market, same age, same weeks
##   4  THE ARC          — does a breed fire in a real career, and does the dynasty pay?
extends Node

const ArcScript = preload("res://scripts/_probe_career_arc.gd")
const BreedScript = preload("res://scripts/ui/breeding_ui.gd")
const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const BattleSimScript = preload("res://scripts/battle_sim.gd")
const TacticsScript = preload("res://scripts/tactics.gd")
const WeekLib = preload("res://scripts/week.gd")

const STATS := ["STR", "DEX", "CON", "WIS", "INT", "CHA"]
const GOLD_IDX := 6            ## the rung the career arc stalls on
const ARC_WEEKS := 900
const SEEDS := [20260809, 771013, 313373]

var _ok := true
var _notes: Array[String] = []


# =============================================================================
# THE VARIANT — the autopilot, with a dynasty policy that can actually fire
# =============================================================================
## ⚠️ THE PARENT'S BREEDING POLICY IS UNREACHABLE BY CONSTRUCTION AND SECTION 4 EXISTS TO PROVE
## IT. `_probe_career_arc.gd:_try_breed` refuses when `Roster.monsters.size() >=
## Career.barn_capacity`, and the recruit loop above it only ever grows the barn UP TO
## `team_need` and then fills it — so the barn is full every week of every career and the child
## has nowhere to hatch. `v_dynasty` grows the barn one slot further so the policy is REACHABLE;
## nothing else about the game is changed, and the canary asserts the barn actually grew.
class ArcVariant extends ArcScript:
	var v_seed: int = 20260809
	var v_dynasty: bool = false        ## keep one nursery slot free so a foal has somewhere to go
	var v_barn_prices: Array = []      ## [] = the shop's real prices
	var v_rent: int = -1               ## -1 = the freezer's real rent
	var nursery_grew: int = 0
	var nursery_ran: int = 0           ## weeks the hook was reached at all (liveness)
	var nursery_broke: int = 0         ## …and declined because the slot was unaffordable
	var nursery_maxed: int = 0         ## …and declined because the barn is already bigger

	func _reset_career() -> void:
		Career.reset_new_game()
		Roster.reset_to_empty()
		Roster.rng.seed = v_seed
		WeekPlan.plans.clear()
		WeekPlan._rng.seed = v_seed
		WeekPlan.reroll_food_prices()

	func _barn_prices() -> Array:
		return v_barn_prices if not v_barn_prices.is_empty() else super()

	## The one hook the arc already calls every week before it plans anything.
	func _manage_roster(opts: Dictionary) -> Dictionary:
		if v_dynasty:
			_grow_nursery()
		return super(opts)

	## Buy ONE barn slot beyond the fielded team, out of genuine surplus, so that a foal has
	## somewhere to hatch. This is the whole of the policy change — no free gold, no free bodies,
	## the real shop price paid at the real time.
	func _grow_nursery() -> void:
		nursery_ran += 1
		var team: int = Career.current_team_size()
		if Career.barn_capacity > team:
			nursery_maxed += 1
			return
		var nxt: int = Career.barn_capacity + 1
		if nxt >= _barn_prices().size():
			return
		var bprice: int = _barn_prices()[nxt]
		if Career.gold < bprice + _breed_cost() + 200:
			nursery_broke += 1
			return
		Career.spend_gold(bprice)
		Career.barn_capacity = nxt
		nursery_grew += 1


# =============================================================================
func _ready() -> void:
	print("=== THE DYNASTY — is breeding reachable inside one career? ===\n")
	_section_1_gates()
	_section_2_bill()
	_section_3_payoff()
	_section_3b_potential_is_inert()
	if not _has_arg("--quick"):
		_section_4_arc()
	else:
		print("\n─── 4. THE ARC ─── skipped (--quick)")

	print("\n─── NOTES ───")
	for n in _notes:
		print("  • %s" % n)
	print("\n%s" % ("PROBE OK" if _ok else "PROBE FAILED — a canary did not fire"))
	get_tree().quit(0 if _ok else 1)


func _has_arg(a: String) -> bool:
	return a in OS.get_cmdline_user_args()


func _fail(msg: String) -> void:
	_ok = false
	_notes.append("CANARY FAILED: " + msg)
	printerr("  ⚠️ CANARY FAILED: %s" % msg)


func _konst(name: String, fallback):
	var s: GDScript = BreedScript
	var m: Dictionary = s.get_script_constant_map()
	return m[name] if m.has(name) else fallback


func _total(mi) -> float:
	var t := 0.0
	for s in STATS:
		t += float(mi.stats.get(s, 0.0))
	return t


# =============================================================================
# 1. THE GATE CHAIN — what must be true before one foal exists, and what binds
# =============================================================================
func _section_1_gates() -> void:
	print("─── 1. THE GATE CHAIN ───")
	var breed_cost: int = int(_konst("BREED_COST", 300))
	var rent: int = int(WeekPlan.RENTAL_PER_FROZEN)

	print("  Every one of these must hold in the SAME week or no foal exists:")
	print("    a. two monsters PRESERVED in the freezer   (roster.gd:breeding_stock is `frozen`, nothing else)")
	print("    b. neither has used its %d matings          (breeding_ui.gd:MAX_CHILDREN_PER_PARENT)"
		% int(_konst("MAX_CHILDREN_PER_PARENT", 2)))
	print("    c. a FREE BARN SLOT for the foal            (breeding_ui.gd:_on_breed / _bequest_card)")
	print("    d. %dg in hand                             (breeding_ui.gd:BREED_COST)" % breed_cost)
	print("    e. %dg/week per frozen body, FOREVER        (week_plan.gd:RENTAL_PER_FROZEN)" % rent)
	print("    f. a licence or lab rental                  — NONE. grep: no gate exists. (a)-(e) is the whole chain.")

	# (c) is the one nobody has priced. What does a free slot cost?
	Career.reset_new_game()
	var prices: Array = ArcScript.new()._barn_prices()
	var cum := 0
	var line: Array = []
	for n in range(2, prices.size()):
		cum += int(prices[n])
		line.append("slot %d %dg (cum %d)" % [n, int(prices[n]), cum])
	print("\n  (c) THE BARN, which is the gate nobody prices:")
	print("      %s" % " · ".join(line))
	for idx in [3, 5, 6, 7, 10]:
		var team: int = Career.team_size_for_league(idx)
		var need: int = team + 1
		var c := 0
		for n in range(3, mini(need + 1, prices.size())):
			c += int(prices[n])
		print("      %-12s fields %d → needs %d slots to hold a foal → %dg cumulative"
			% [Career.league_at(idx).get("name", "?"), team, need, c])

	# ── THE CANARY: build a state where every gate is satisfied and prove a foal comes out. ──
	Career.reset_new_game()
	Roster.reset_to_empty()
	Roster.rng.seed = 4242
	Roster._generate_starting_roster()
	var pa = Roster.monsters[0]
	var pb = Roster.monsters[1]
	Roster.preserve(pa)
	Roster.preserve(pb)
	Career.barn_capacity = 4
	Career.add_gold(5000)
	var ui = BreedScript.new()
	ui._emphasis = "STR"
	var foal = ui._make_child(pa, pb, "canary")
	ui.free()
	if foal == null or foal.potential <= 1.0:
		_fail("a fully-satisfied breed produced no foal (or no potential gain) — the instrument "
			+ "cannot see a breed, so nothing else it prints about breeding is evidence")
	else:
		print("\n  CANARY: every gate satisfied → foal exists, potential ×%.2f, %d stat points. "
			% [foal.potential, int(_total(foal))]
			+ "The instrument can see a breed.")
	Roster.reset_to_empty()


# =============================================================================
# 2. THE BILL — what a preserve actually costs, against what it replaces
# =============================================================================
func _section_2_bill() -> void:
	print("\n─── 2. THE BILL ───")
	var rent: int = int(WeekPlan.RENTAL_PER_FROZEN)
	print("  freezer rent %dg/week/body, charged by week_plan.gd:rent_for(). " % rent)
	print("  weeks left   rent, ONE body   rent, a PAIR (the minimum to breed)")
	for w in [100, 200, 300, 483, 900]:
		print("     %4d          %6dg            %6dg" % [w, w * rent, w * 2 * rent])
	print("\n  ⚠️ THE PAIR IS THE UNIT, NOT THE BODY. Preserved at week 200 of a 900-week career a")
	print("     still-racing pair bills %dg, against a measured career GROSS of ~20,875g" % (700 * 2 * rent))
	print("     (`_probe_career_arc.gd`, 483 weeks). That is 80%% of everything the stable earns.")

	# ── WHO PAYS — the rule under test, exercised through the tick's own function ──
	Roster.reset_to_empty()
	Roster.rng.seed = 909
	Roster._generate_starting_roster()
	var live = Roster.monsters[0]
	var dead = Roster.monsters[1]
	dead.retired = true
	Roster.preserve(live)
	Roster.preserve(dead)
	var billed: int = WeekPlan.rent_for(Roster.frozen)
	print("\n  WHO PAYS (week_plan.gd:rent_for, exercised on a real freezer of 2):")
	print("    1 still-racing + 1 retired  →  %dg/week  (flat rule would bill %dg)"
		% [billed, 2 * rent])
	if billed != rent:
		_fail("rent_for billed %dg for one racing + one retired body; the enshrinement rule is "
			% billed + "not live, so section 4's economy is not the one the screens describe")
	else:
		print("    ✓ the enshrinement rule is LIVE — a retired founder costs nothing, a parked")
		print("      competitor costs %dg/week forever. The bill prices the OPTION, not the body." % rent)
	Roster.reset_to_empty()


# =============================================================================
# 3. THE PAYOFF — foal vs market, same league, same age, same trained weeks
# =============================================================================
## ⚠️ THE COMPARISON THE PLAYER ACTUALLY FACES is not "foal vs nothing", it is "300g + a pair of
## champions out of competition + rent forever, against the best body on the shelf for gold".
## `GameData.make_monster` scales a recruit to the CURRENT LEAGUE CAP (`game_data.gd:stat_cap`),
## so the shelf gets better as you climb while a foal is a fixed 30% of its parents — which means
## the two curves cross somewhere, and nobody has ever measured where.
func _section_3_payoff() -> void:
	print("\n─── 3. THE PAYOFF ───")
	var arc = ArcScript.new()
	var head: float = float(_konst("BREED_HEAD_START", 0.30))

	print("  At each rung: the BEST of the week's market offers, against a foal of two parents")
	print("  sitting at that rung's measured fill. Both at hatch, before any training.")
	print("  rung        cap   parents at   foal pts  potential  market pts  price   foal age  mkt age")
	var rows: Array = []
	for idx in [2, 4, 6, 7, 9, 10]:
		Career.reset_new_game()
		Roster.reset_to_empty()
		Career.league_index = idx
		Career.week = 40
		var cap: float = Career.stat_cap_for_league(idx)
		# Parents at the arc's own measured fill@exit for this rung (0.62 average above Bronze).
		var fill := 0.62
		var pa = _parent_at(0, fill, cap)
		var pb = _parent_at(1, fill, cap)
		var ui = BreedScript.new()
		ui._emphasis = ""
		var foal = ui._make_child(pa, pb, "payoff")
		ui.free()
		# The market, through the arc's own offer generator — the same shelf the autopilot buys from.
		var best: Dictionary = {}
		for o in arc._offers_this_week():
			if best.is_empty() or _total(o["mi"]) > _total(best["mi"]):
				best = o
		rows.append({"idx": idx, "foal": foal, "mkt": best["mi"], "price": int(best["price"]), "cap": cap})
		print("  %-11s %4d   %6d      %6d     ×%.2f     %6d   %5dg      %3d      %3d"
			% [Career.league_at(idx).get("name", "?"), int(cap), int(_total(pa)),
				int(_total(foal)), foal.potential, int(_total(best["mi"])), int(best["price"]),
				foal.age_weeks, best["mi"].age_weeks])

	print("\n  head start is %.0f%% of the parents' average (breeding_ui.gd:BREED_HEAD_START);"
		% (head * 100.0))
	print("  a market recruit is scaled to the CURRENT league cap (game_data.gd:stat_cap), so the")
	print("  shelf climbs with the ladder and the foal climbs with the STABLE.")

	# ── the fight ────────────────────────────────────────────────────────────────────────────
	## ⚠️ BOTH CANDIDATES ARE REBUILT FROM SCRATCH FOR EVERY ROW, NEVER COPIED. The first cut
	## trained the SAME OBJECT it had already fought and then compared it to itself; the canary
	## caught it ("moved 0 points") and the row was void. Construction here is deterministic —
	## same seed, same species, same week — so a rebuild IS the same monster.
	##
	## ⚠️ AND "SAME AGE" IS THE COMPARISON THE BRIEF ASKS FOR, NOT "SAME WEEKS TRAINED". A foal
	## hatches at age 0 (`breeding_ui.gd:_make_child`) and a market body arrives at 48
	## (`monster_instance.gd:age_weeks`), so a same-weeks table silently hands the market a
	## year of career it did not have to pay for. Both rows are printed; they disagree, and the
	## disagreement is the finding.
	print("\n  Head to head against the real Gold field (8 reps x rounds, same seeds both sides).")
	print("  Rival sides are cut to one body — this measures the RECRUIT, not the team size.\n")
	print("    row                     foal pts  ceil   wins  |  market pts  ceil   wins")
	var cap_g: float = Career.stat_cap_for_league(GOLD_IDX)
	var rows_duel: Array = [
		{"label": "at hatch", "foal_wk": 0, "mkt_wk": 0},
		{"label": "+120 wks each", "foal_wk": 120, "mkt_wk": 120},
		{"label": "both to age 336", "foal_wk": 336, "mkt_wk": 288},
	]
	var moved := false
	var base_pts := 0
	for row in rows_duel:
		var pair: Dictionary = _duel_pair()
		var f = pair["foal"]
		var m = pair["mkt"]
		if base_pts == 0:
			base_pts = int(_total(f))
		if int(row["foal_wk"]) > 0:
			_train_one(f, int(row["foal_wk"]), cap_g)
			_train_one(m, int(row["mkt_wk"]), cap_g)
			if int(_total(f)) > base_pts:
				moved = true
		var wf: int = _fight_field(GOLD_IDX, [f], 8)
		var wm: int = _fight_field(GOLD_IDX, [m], 8)
		print("    %-22s %6d  %4d   %4d  |  %9d  %4d   %4d"
			% [row["label"], int(_total(f)), int(WeekLib.stat_cap_for(f, cap_g)), wf,
				int(_total(m)), int(WeekLib.stat_cap_for(m, cap_g)), wm])
		if row["label"] == "at hatch":
			_notes.append("at hatch, Gold: foal %d pts / %d wins vs market %d pts / %d wins (%dg)"
				% [int(_total(f)), wf, int(_total(m)), wm, int(pair["price"])])
		if row["label"] == "both to age 336":
			_notes.append("at equal AGE 336, Gold: foal %d pts / %d wins vs market %d pts / %d wins"
				% [int(_total(f)), wf, int(_total(m)), wm])
	if not moved:
		_fail("the real weekly tick moved the foal 0 points across 120 and 336 weeks — the "
			+ "training seam in section 3 is dead and every trained row above is void")

	# ── THE TRADE, STATED AND CHECKED: slower to the ring, longer in it ──
	var pair2: Dictionary = _duel_pair()
	var f2 = pair2["foal"]
	var m2 = pair2["mkt"]
	var wpy: float = float(WeekLib.WEEKS_PER_YEAR)
	var f_train: int = int(round(f2.lifespan_years * wpy)) - f2.age_weeks
	var m_train: int = int(round(m2.lifespan_years * wpy)) - m2.age_weeks
	print("\n  THE TRADE (breeding_ui.gd:LIFESPAN_STEP_YEARS):")
	print("    foal    lives %.1fy, hatched at age %d → %d trainable weeks, ceiling x%.2f"
		% [f2.lifespan_years, f2.age_weeks, f_train, f2.potential])
	print("    market  lives %.1fy, arrives at age %d → %d trainable weeks, ceiling x%.2f"
		% [m2.lifespan_years, m2.age_weeks, m_train, m2.potential])
	print("    the foal is %+d weeks of career and %+.0f%% of ceiling, and %d points BEHIND on"
		% [f_train - m_train, (f2.potential / m2.potential - 1.0) * 100.0,
			int(_total(m2)) - int(_total(f2))])
	print("    the day it hatches. That is the trade: slower to the ring, longer in it.")
	if f_train <= m_train:
		_fail("a foal has %d trainable weeks against the market's %d — the line's gift is not "
			% [f_train, m_train] + "live, so breeding still sells nothing")
	_notes.append("the trade: foal +%d trainable weeks, x%.2f ceiling, -%d pts at hatch"
		% [f_train - m_train, f2.potential, int(_total(m2)) - int(_total(f2))])

	# The dynasty, over generations — does the gift compound to something worth a career?
	print("\n  ACROSS GENERATIONS (each foal bred off the previous and a preserved founder):")
	print("    gen   lifespan   trainable wks   potential   Apex ceiling")
	var founder = _parent_at(0, 0.62, cap_g)
	var line_ = _parent_at(1, 0.62, cap_g)
	var apex: float = Career.stat_cap_for_league(10)
	for g in range(1, 7):
		var ui3 = BreedScript.new()
		var kid = ui3._make_child(line_, founder, "gen%d" % g)
		ui3.free()
		print("    G%-3d  %5.1fy      %6d          x%.2f       %6d"
			% [g, kid.lifespan_years, int(round(kid.lifespan_years * wpy)),
				kid.potential, int(apex * kid.potential)])
		line_ = kid


## =============================================================================
## 3b. ⚠️ IS `potential` CONNECTED TO ANYTHING?
## =============================================================================
## Section 3's "both to age 336" row came back with the foal and the market body on IDENTICAL
## stat totals (4473 = 6 x 745.5, i.e. both flat on the 750 league cap) while the foal was being
## told on three separate screens that its ceiling was 825. That is not a balance reading, it is
## a wiring question, and it gets its own paired test: two bodies identical in every field except
## `potential`, trained through the real tick, for long enough that only the ceiling can separate
## them.
func _section_3b_potential_is_inert() -> void:
	print("\n─── 3b. IS `potential` WIRED TO TRAINING? ───")
	Career.reset_new_game()
	Career.league_index = GOLD_IDX
	Career.week = 40
	var cap: float = Career.stat_cap_for_league(GOLD_IDX)
	var results: Array = []
	for pot in [1.00, 1.50, 2.00]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5150
		var mi = GameData.make_monster(Art.ROSTER[0], 0.5, rng, 1.0)
		mi.potential = pot
		mi.lifespan_years = 1000.0   # remove the clock so ONLY the ceiling can bind
		_train_one(mi, 500, cap)
		results.append({"pot": pot, "top": _top_stat(mi), "total": _total(mi),
			"claimed": WeekLib.stat_cap_for(mi, cap)})
	print("  identical monster, identical seed, 500 weeks of the real tick, clock removed:")
	print("    potential   ceiling the game CLAIMS   highest stat REACHED   stat total")
	for r in results:
		print("      x%.2f              %4d                    %4d              %5d"
			% [r["pot"], int(r["claimed"]), int(r["top"]), int(r["total"])])
	var spread: float = float(results[2]["top"]) - float(results[0]["top"])
	if spread < 1.0:
		_fail("POTENTIAL IS INERT: x1.00 and x2.00 train to the SAME stat (%d). "
			% int(results[0]["top"])
			+ "`week.gd:apply_activity` clamps to the raw league `cap` at its `clampf(...)`, never "
			+ "to `week.gd:stat_cap_for(mi, cap)` — so the bloodline multiplier is authored, "
			+ "priced, displayed on three screens and applied by nothing. Breeding cannot pay "
			+ "until this one line is fixed, and it is NOT in this workstream's files.")
	else:
		print("\n  ✓ potential is live: x2.00 trains %d points higher per stat than x1.00."
			% int(spread))
		_notes.append("potential IS wired: x1.00 -> x2.00 is +%d on the top stat" % int(spread))


func _top_stat(mi) -> float:
	var t := 0.0
	for s in STATS:
		t = maxf(t, float(mi.stats.get(s, 0.0)))
	return t


## The duel's two candidates, built fresh and identically every call. Parents sit at the arc's
## own measured Gold `fill@exit`; the market body is the best of the same shelf the autopilot buys
## from (`_probe_career_arc.gd:_offers_this_week`).
func _duel_pair() -> Dictionary:
	Career.reset_new_game()
	Roster.reset_to_empty()
	Career.league_index = GOLD_IDX
	Career.week = 40
	var cap_g: float = Career.stat_cap_for_league(GOLD_IDX)
	var pa = _parent_at(0, 0.62, cap_g)
	var pb = _parent_at(1, 0.62, cap_g)
	var ui = BreedScript.new()
	ui._emphasis = _best_stat(pa, pb)
	var best_at := -1.0
	for opt in ui._heirloom_options(pa, pb):
		if float(opt["at"]) > best_at:
			best_at = float(opt["at"])
			ui._heirloom_id = str(opt["id"])
	var foal = ui._make_child(pa, pb, "duel")
	ui.free()
	var arc = ArcScript.new()
	var best: Dictionary = {}
	for o in arc._offers_this_week():
		if best.is_empty() or _total(o["mi"]) > _total(best["mi"]):
			best = o
	return {"foal": foal, "mkt": best["mi"], "price": int(best["price"])}


## A plausible parent at `fill` of `cap`, built by the game's own generator so it carries a real
## species, a real aptitude and a real kit. `room_mult` 1.0 because `fill` IS a fraction of the
## ceiling — the note on `game_data.gd:make_monster` is explicit that 0.6 compresses it 1.66x.
func _parent_at(n: int, fill: float, cap: float):
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + n * 17
	var ids: Array = Art.ROSTER
	var mi = GameData.make_monster(ids[(n * 7) % ids.size()], fill, rng, 1.0)
	mi.id = "p%d" % n
	mi.age_weeks = 240
	return mi


func _best_stat(a, b) -> String:
	var best := STATS[0]
	var bv := -1.0
	for s in STATS:
		var v: float = float(a.stats.get(s, 0.0)) + float(b.stats.get(s, 0.0))
		if v > bv:
			bv = v
			best = s
	return best


## ⚠️ THE REAL WEEKLY TICK, NOT A MODEL OF IT. Both candidates go into the barn and take the
## autopilot's own greedy drill plan through `WeekPlan.advance` — the same path the career arc
## drives. A hand-rolled "add N points a week" here would be the second copy this project keeps
## being bitten by, and it would silently ignore the potential multiplier, which is the entire
## thing under test.
func _train_one(mi, weeks: int, cap: float) -> void:
	var arc = ArcScript.new()
	var keep_league: int = Career.league_index
	var keep_week: int = Career.week
	Roster.reset_to_empty()
	mi.id = Roster.next_slot_id()
	Roster.monsters = [mi]
	Career.add_gold(200000)
	WeekPlan.plans.clear()
	for w in range(weeks):
		if mi.retired:
			break
		WeekPlan.set_food(mi.id, mi.favourite_food)
		var plan: Dictionary = arc._drill_plan_greedy(mi, cap)
		if str(plan["mode"]) == "train":
			WeekPlan.set_activity(mi.id, str(plan["id"]))
		else:
			WeekPlan.set_activity(mi.id, "rest")
		WeekPlan.advance(Roster.monsters)
	Roster.reset_to_empty()
	Career.league_index = keep_league
	Career.week = keep_week


## One body against the real drawn field for a rung. Lifted in SHAPE from
## `_probe_gold_wall.gd:_fight_field` — the same construction, because it is the construction the
## live cup uses (`Career.make_cup_field` + the rival's own plan and orders).
func _fight_field(idx: int, team: Array, reps: int) -> int:
	var wins := 0
	var keep: int = Career.week
	for f in range(reps):
		Career.week = keep + f * 4
		var field: Array = Career.make_cup_field(idx, Career.rival_count_for_league(idx))
		for r in range(field.size()):
			var rng := RandomNumberGenerator.new()
			rng.seed = 770000 + idx * 977 + f * 41 + r
			var rivals: Array = field[r]["team"]
			# ⚠️ ONE BODY AGAINST A FULL SIDE IS NOT THE QUESTION. The unit under test is the
			# RECRUIT, so the rival side is cut to the same size — this measures the body, not
			# the team size the rung happens to field.
			rivals = rivals.slice(0, team.size())
			var gid: String = String(field[r].get("archetype", ""))
			for m in team:
				m.reset_for_battle()
			for m in rivals:
				m.reset_for_battle()
			var plan_b: Dictionary = TacticsScript.team_plan_for_gameplan(gid, team) if gid != "" else {}
			var orders: Dictionary = TacticsScript.orders_for_gameplan(gid, rivals) if gid != "" else {}
			var sim = BattleSimScript.new(team, rivals, rng.randi(), {}, plan_b, orders)
			if str(sim.run().get("winner", "")) == "A":
				wins += 1
	Career.week = keep
	return wins


# =============================================================================
# 4. THE ARC — does a breed fire in a real career?
# =============================================================================
func _section_4_arc() -> void:
	print("\n─── 4. THE ARC ───")
	print("  control      = the autopilot exactly as committed")
	print("  nursery      = the SAME autopilot, buying ONE barn slot beyond the team at real prices")
	print("  seeds: %s\n" % str(SEEDS))
	print("  variant    seed       reached        wks  breeds  preserves  1st preserve  1st breed  best pot  rent")
	var summary := {}
	for kind in ["control", "nursery"]:
		var reached: Array = []
		var breeds_total := 0
		for s in SEEDS:
			var v := ArcVariant.new()
			v.v_seed = s
			v.v_dynasty = (kind == "nursery")
			var a: Dictionary = v._run_arc(ARC_WEEKS, {})
			var pot := 1.0
			for mi in (Roster.monsters + Roster.frozen):
				pot = maxf(pot, mi.potential)
			var got: int = int(a.get("finalLeague", 0))
			reached.append(got)
			breeds_total += int(a.get("breeds", 0))
			print("  %-10s %-9d %-12s %5d  %6d  %9d  %12d  %9d  ×%.2f   %6d"
				% [kind, s, Career.league_at(got).get("name", "?"), int(a.get("weeks", 0)),
					int(a.get("breeds", 0)), int(a.get("preserves", 0)),
					int(a.get("firstPreserveWeek", 0)), int(a.get("firstBreedWeek", 0)),
					pot, int(a.get("rentPaid", 0))])
			## ⚠️ TWO DIFFERENT FAILURES WEAR THE SAME FACE and the first cut of this canary
			## conflated them. "The barn never grew" can mean the override never RAN (a dead
			## instrument, and the row is void) or that it ran every week and could never AFFORD
			## the slot (a live instrument reporting a real finding). Separate them, or the
			## finding gets thrown away as an artifact.
			if kind == "nursery":
				if v.nursery_ran == 0:
					_fail("the nursery hook never ran on seed %d — the override did not bite, "
						% s + "so its row is void")
				elif v.nursery_grew == 0:
					print("      ↳ the nursery hook ran %d weeks and bought NOTHING: %d weeks it "
						% [v.nursery_ran, v.nursery_broke]
						+ "could not afford the next barn slot, %d it already had one."
						% v.nursery_maxed)
					_notes.append("seed %d: the barn slot beyond the fielded team was unaffordable "
						% s + "on %d of %d weeks — the nursery is priced out, not un-policied."
						% [v.nursery_broke, v.nursery_ran])
			v.free()
		summary[kind] = {"reached": reached, "breeds": breeds_total}
		print("")
	var c: Dictionary = summary["control"]
	var n: Dictionary = summary["nursery"]
	print("  control reached %s (%d breeds total)" % [str(c["reached"]), int(c["breeds"])])
	print("  nursery reached %s (%d breeds total)" % [str(n["reached"]), int(n["breeds"])])
	if int(c["breeds"]) == 0 and int(n["breeds"]) > 0:
		_notes.append("the barn slot IS the gate: the identical autopilot breeds %d times once "
			% int(n["breeds"]) + "one slot beyond the team exists, and 0 times when it does not.")
	elif int(n["breeds"]) == 0:
		_notes.append("even with a nursery slot the autopilot bred 0 times — the gate is upstream "
			+ "of the barn (check the freezer: preserves, and FREEZER_TARGET).")
