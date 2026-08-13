## THE BREEDING RANCH — where a stable becomes a DYNASTY.
##
## ⚠️ THIS IS THE META-GAME'S LOAD-BEARING PILLAR, not a side feature. `CLAUDE.md`: *"The
## meta-game is a MIXTURE... advanced training knowledge plus breeding the right monsters to have
## the correct tactics and skills. Knowing WHICH monster to make is the skill."*
##
## ⚠️ IT WAS NOT THAT. IT WAS A SLOT MACHINE WITH A GOLD COST, AND THE AUDIT SAID SO IN NUMBERS.
## Measured on the shipped port before this pass (`_tmp_lineage_audit`, 2026-08-09):
##   • A bred child hatched with **77 stat points against a wild market recruit's 134** — 300g
##     bought you a monster strictly WORSE than the cheapest thing on the shelf. The cause was a
##     port bug, not a balance call: `src/town.ts:796` is
##     `baby.stats[s] = Math.max(baby.stats[s], round(HEAD_START * avg))` — the `Math.max`
##     against the child's own fresh species roll. The port dropped the max and kept only the
##     head start, so a child could hatch below its own species' wild baseline. Fixed below.
##   • The child inherited **nothing the fight can see**. Its kit was re-drafted from scratch;
##     of three moves shared with its parent, three were coincidence (same species → same class
##     → same lines) and zero were inheritance.
##   • **Nothing about the child was knowable before the gold was spent** except a potential
##     number: not its species (silently the higher-potential parent's), not its class, not its
##     kit, not the aptitude it would train under.
##   • Potential climbed **+0.06 a generation**, against `town.ts:762`'s 0.10–0.15 by heritage.
##
## So: you could not aim it, you could not read it, and it handed back less than the market did.
## That is not "breeding the right monster to have the correct skills" — it is a lever.
##
## ⚠️ WHAT THIS SCREEN IS NOW: **a bequest you specify, resolved in full before you pay.** The
## player answers three questions — which parent's LINE the child takes, which stat its head
## start is CONCENTRATED into, and which single move from either parent's kit it is BORN
## KNOWING — and the card below shows the exact monster those three answers produce, down to its
## class, its stats and its move list. Nothing is rolled that the player has not already seen.
## `_make_child()` is the ONE builder both the preview and the commit call, for the same reason
## `week.gd:preview_week` runs the real `apply_week` on a scratch copy: a second hand-written
## estimate is a lie waiting to happen.
##
## ⚠️ AND THE PARENTS MUST BE PRESERVED FIRST (`Roster.breeding_stock()`). `town.ts:787` reads
## its parents out of `labFrozen` and nowhere else; the port let any barn monster breed, which
## removed the only genuine cost. The decision breeding actually asks is *"is this monster's line
## worth taking out of competition, and worth a freezer bill forever?"* — and it has to be asked
## while the monster is still winning, which is what makes it a decision made with knowledge the
## player earned rather than a purchase.
##
## ⚠️ THE ONE THING THAT MUST SURVIVE (`CLAUDE.md`): *"a SPECIES must never be locked out of a
## role."* Nothing here is species-destiny. The line choice is the PLAYER's, the emphasis stat is
## the PLAYER's and is free of the species' aptitude, and any move either parent knows may be
## bequeathed to a child of either species. Aptitude still makes a path slower; it never forbids
## one.
##
## ⚠️ NUMBERS ARE PLACEHOLDERS and the user has accepted them as such — the balance baseline is
## SUSPENDED (`CLAUDE.md`). The SHAPES are ported; the values want a pass at the re-baseline.
extends Control

const UiTheme = preload("res://scripts/ui/theme.gd")
const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const ClassifyLib = preload("res://scripts/classify.gd")
const DeriveLib = preload("res://scripts/derive.gd")
const WeekLib = preload("res://scripts/week.gd")

const STATS := ["STR", "DEX", "CON", "WIS", "INT", "CHA"]

## `town.ts:752 BREED_COST`.
const BREED_COST := 300

## `town.ts:774 BREED_HEAD_START` — the fraction of the parents' average stats a child hatches
## with. ⚠️ Tuned 0.45 → 0.15 → 0.30 in the React build, so this number has already been argued
## over twice: parents' stats SHOULD carry to the child, but the dynasty's real engine is the
## climbing `potential`, not the head start.
##
## ⚠️ IT IS A FLOOR AGAINST THE SPECIES' OWN BASE, NOT A REPLACEMENT FOR IT — see the header. A
## child is never worse than a wild-caught member of its own species; the head start is what it
## has ON TOP. Restoring the `Math.max` closed a measured 57-point hole.
const BREED_HEAD_START := 0.30

## ⚠️ THE PLAYER AIMS THE CHILD WITH THIS, AND IT IS ZERO-SUM ON PURPOSE. Each of the five
## non-emphasis stats gives up this fraction of ITSELF, and every point of it goes to the
## emphasis stat. Breeding chooses the child's SHAPE — and therefore its class, its kit and the
## role it will fill — never its total. A non-zero-sum emphasis would just be a bigger head start
## with a dropdown on it.
##
## ⚠️ IT IS TAKEN AFTER THE SPECIES-BASE FLOOR, NOT BEFORE, AND THE ORDER IS THE WHOLE MECHANIC.
## Applied before the floor it did nothing at all: a 30% head start off mid-career parents lands
## BELOW the species' own base, so `maxf` swallowed the entire redistribution. Measured — five
## different emphases produced five monsters within 8 points of each other and all five came out
## the same class. A knob that cannot change the answer is not a decision.
const EMPHASIS_TAX := 0.20

## Per-generation potential step by HERITAGE (`town.ts:762 BREED_STEP_BY_TIER`). ⚠️ The port
## flattened all five to 0.06, which erased the entire reason to work toward a prestige licence
## or a fusion line: every dynasty climbed at the same rate no matter what it was made of.
const BREED_STEP_BY_TIER := {
	"wild": 0.10, "prestige": 0.11, "mythical": 0.12, "fusion": 0.13, "primeval": 0.15,
}
const MAX_POTENTIAL := 2.0

## ⚠️ Each parent is good for at most this many children (`town.ts:753`). Without a limit,
## breeding the same optimal pair forever is strictly correct and the system stops being a choice.
const MAX_CHILDREN_PER_PARENT := 2

## ── THE LINE'S GIFT IS TIME (2026-08-09) ─────────────────────────────────────────────────────
## ⚠️ THE DYNASTY HAD NOTHING TO SELL, AND THE NUMBERS SAY SO. Measured on this build
## (`_probe_breed.gd` §3, Gold, parents at the arc's own 0.62 fill@exit): a foal hatches with
## **858 stat points against 1,151 for the best body on the market that week — at 253g**. It
## loses the head-to-head 0 wins to 1 at hatch and 8 to 28 after 120 weeks of the real weekly
## tick. **Breeding was strictly dominated by shopping**, which is the complete answer to "why
## did 0 breeds fire in a 483-week career": no policy that wanted to breed would have been right
## to. A market recruit is scaled to the CURRENT LEAGUE CAP (`game_data.gd:stat_cap`), so the
## shelf climbs with the ladder while a foal is a fixed fraction of its parents.
##
## ⚠️ AND `potential` COULD NOT PAY THE DIFFERENCE, BECAUSE NOBODY REACHES A CEILING. The gym
## section of `_probe_career_arc.gd` measures 305 weeks of PERFECT training to fill the Gold cap
## against 336 trainable weeks in a lifespan, and reads RETIRED FIRST at Platinum and above. A
## multiplier on a ceiling nobody touches is worth nothing. That is why raising the head start
## would have been the wrong fix: it would have made a foal a better PURCHASE without making a
## dynasty a better STRATEGY.
##
## **So the trade this system now makes is: a bought monster is instant and capped; a bred one is
## SLOWER TO THE RING and lives LONGER.** The head start stays at 30% — a foal is behind on the
## day it hatches and has to be brought up — and what the line accumulates is the one resource
## the ladder is actually short of. `_probe_gold_wall.gd` measured lifespan as the single
## largest lever in the game: with retirement neutralised the career arc improved on 5 of 5
## seeds (median league reached 5 -> 7, sign test p=0.031). Breeding is now the in-game,
## incremental, PAID version of that lever, and it is the only route to it.
##
## ⚠️ IT MUST STAY INCREMENTAL OR IT BECOMES THE OBVIOUS CLICK. +0.5 years a generation off the
## BETTER parent, hard-capped at MAX_LIFESPAN_YEARS: Gen 1 is 8.5y, Gen 8 is the 12y ceiling.
## Nothing here shortcuts the climb — every step still costs a champion out of competition, a
## barn slot, 300g and a freezer bill, and `MAX_CHILDREN_PER_PARENT` still stops one perfect pair
## from founding the whole stable.
const LIFESPAN_STEP_YEARS := 0.5
const MAX_LIFESPAN_YEARS := 12.0


var _box: VBoxContainer
var _plate_host: VBoxContainer
var _pick_a = null   # MonsterInstance, or null
var _pick_b = null
var _line_from_b := false      # false = child takes parent A's species, true = parent B's
var _emphasis := ""            # "" = an even spread
var _heirloom_id := ""         # move id, "" = bequeath nothing
var _log_label: Label


func _ready() -> void:
	self.theme = UiTheme.base_theme()
	_build()
	_refresh()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.SURFACE
	bg.anchor_right = 1; bg.anchor_bottom = 1
	add_child(bg)

	var tex: Texture2D = Art.area_texture("breeding")
	if tex != null:
		var backdrop := TextureRect.new()
		backdrop.texture = tex
		backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		backdrop.anchor_right = 1; backdrop.anchor_bottom = 1
		backdrop.modulate = Color(1, 1, 1, 0.28)
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(backdrop)

	var margin := MarginContainer.new()
	margin.anchor_right = 1; margin.anchor_bottom = 1
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, UiTheme.SPACE_XL)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	margin.add_child(page)

	# ⚠️ THE PLATE REPLACED A TITLE AND A COMMA-RUN, AND THE FOUR ROOMS OPENED IDENTICALLY WITHOUT
	# IT. See `UiTheme.room_plate()` for why it lives there and what it costs. `_plate_host` is
	# rebuilt every `_refresh()` because the tiles are live numbers (gold, stud book, barn).
	_plate_host = VBoxContainer.new()
	page.add_child(_plate_host)

	_log_label = UiTheme.body_text("Choose two preserved parents.", "primary")
	_log_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	page.add_child(_log_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)

	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box)

	page.add_child(HSeparator.new())
	var back := Button.new()
	back.text = "Back to Town"
	back.custom_minimum_size = Vector2(0, 44)
	back.focus_mode = Control.FOCUS_ALL
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/town.tscn"))
	page.add_child(back)


# ── the maths ────────────────────────────────────────────────────────────────────────────────

func _children_of(mi) -> int:
	return int(mi.get_meta("children", 0))


static func _tier_of(body: String) -> String:
	if body == "Primeval": return "primeval"
	if body in ["Saurian", "Tempestine", "Broodkin"]: return "fusion"
	if body == "Mythical": return "mythical"
	if body in ["Draconic", "Abyssal"]: return "prestige"
	return "wild"


## The step this pairing climbs by — the BETTER of the two heritages, so pairing a prestige
## founder with a modest partner is never punished for the partner.
static func _step_for(a, b) -> float:
	return maxf(float(BREED_STEP_BY_TIER[_tier_of(a.body)]),
		float(BREED_STEP_BY_TIER[_tier_of(b.body)]))


## The child's potential: climbs off the BETTER parent, not their average. ⚠️ `town.ts:781`
## changed this deliberately in v0.88 — averaging meant one exceptional founder was diluted by a
## modest partner, which punished exactly the breeding the system wants to reward.
func _child_potential(a, b) -> float:
	var base: float = maxf(a.potential, b.potential)
	return minf(MAX_POTENTIAL, snappedf(base + _step_for(a, b), 0.01))


## Every move either parent knows, as [{id, name, stat, at, from}] — `at` being the parent's
## CURRENT value in that move's stat, which becomes the bar the heir must clear to awaken it.
func _heirloom_options(a, b) -> Array:
	var out: Array = []
	var seen := {}
	for parent in [a, b]:
		for m in parent.moveset:
			var mid: String = str(m.get("id", ""))
			if mid == "" or seen.has(mid):
				continue
			seen[mid] = true
			var stat: String = str(m.get("stat", "STR"))
			out.append({
				"id": mid, "name": str(m.get("name", "?")), "stat": stat,
				"at": float(parent.stats.get(stat, 0.0)), "from": parent.species_name,
				"type": str(m.get("type", "damage")),
			})
	return out


## ⚠️ THE ONE BUILDER. Both the preview card and `_on_breed` call this, so what the player is
## shown IS what they get — the same discipline `week.gd:preview_week` uses. `slot_id` is "" for
## the preview (which must not consume a career slot id).
func _make_child(a, b, slot_id: String):
	var donor = b if _line_from_b else a
	var other = a if _line_from_b else b
	var sp: Dictionary = GameData.species_by_id.get(donor.species_id, {})
	var base: Dictionary = sp.get("base", {})

	var child = MonsterInstanceScript.new()
	child.id = slot_id if slot_id != "" else "preview"
	child.species_id = donor.species_id
	child.species_name = donor.species_name
	child.body = donor.body
	child.flavour = sp.get("flavour", "")
	child.innate = sp.get("innate", [])
	child.potential = _child_potential(a, b)
	child.generation = maxi(a.generation, b.generation) + 1
	child.emphasis = _emphasis
	child.age_weeks = 0  # ⚠️ born, not bought — it has a full career ahead of it
	# ⚠️ THE LINE'S GIFT — see the note on LIFESPAN_STEP_YEARS. Off the BETTER parent, for the same
	# reason `_child_potential` climbs off the better parent: averaging punishes a dynasty for the
	# partner it needed to make the pairing legal.
	child.lifespan_years = minf(MAX_LIFESPAN_YEARS,
		snappedf(maxf(a.lifespan_years, b.lifespan_years) + LIFESPAN_STEP_YEARS, 0.01))

	# ⚠️ HEAD START ON TOP OF THE SPECIES' OWN BASE, NEVER INSTEAD OF IT (`town.ts:796`). The
	# `maxf` is the whole fix for the measured 77-vs-134 hole: a child of two champions must never
	# hatch weaker than the same species bought wild off the market.
	child.stats = {}
	for stat in STATS:
		var avg: float = (float(a.stats.get(stat, 0.0)) + float(b.stats.get(stat, 0.0))) * 0.5
		child.stats[stat] = maxf(float(base.get(stat, 10.0)), round(avg * BREED_HEAD_START))

	# THEN the emphasis, on top of the floored numbers — see the note on EMPHASIS_TAX for why the
	# order is load-bearing. Exactly zero-sum: whatever the five give up, the one receives.
	if _emphasis != "" and child.stats.has(_emphasis):
		var pot := 0.0
		for stat in STATS:
			if stat == _emphasis:
				continue
			var give: float = round(child.stats[stat] * EMPHASIS_TAX)
			child.stats[stat] = maxf(1.0, child.stats[stat] - give)
			pot += give
		child.stats[_emphasis] += pot

	# The bequest. `at` is the parent's stat TODAY — the heir awakens the move by matching the
	# ancestor's peak, which is the bar `src/signature.ts` sets and the reason an heirloom earned
	# late is a harder legacy to live up to.
	if _heirloom_id != "":
		for opt in _heirloom_options(a, b):
			if opt["id"] == _heirloom_id:
				child.set_heirloom(opt["id"], opt["stat"], opt["at"])
				break

	child.class_name_ = ClassifyLib.class_for_stats(child.stats)
	child.role = ClassifyLib.role_of_class(child.class_name_)
	child.mana_role = ClassifyLib.mana_role_of(child.stats, child.class_name_)
	child.basic_attack = ClassifyLib.basic_attack_for(child.stats)
	child.max_hp = DeriveLib.max_hp(child.stats["CON"])
	child.max_mp = DeriveLib.max_mana(child.stats["WIS"], child.stats["INT"])
	child.hp = child.max_hp
	child.mp = child.max_mp

	# ⚠️ SEEDED OFF THE PAIRING AND THE WEEK, NOT OFF THE SLOT ID. The preview must draft the
	# SAME kit the commit does, and the slot id does not exist yet at preview time. Same parents,
	# same week, same bequest → same monster, every process (the determinism rule).
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s+%s:%d:%s:%s" % [a.bare_id(), b.bare_id(), Career.week, _emphasis, _heirloom_id])
	if child.has_method("assign_moveset"):
		child.assign_moveset(rng)
	var prefs: Dictionary = GameData._pick_food_prefs(rng)
	child.favourite_food = prefs["fav"]
	child.hated_food = prefs["hated"]
	# The line's OTHER parent still shows up in the log — a dynasty is two names, not one.
	child.log = ["born of %s and %s — Gen %d, potential ×%.2f." % [
		donor.species_name, other.species_name, child.generation, child.potential]]
	return child


# ── the screen ───────────────────────────────────────────────────────────────────────────────

func _refresh() -> void:
	for c in _box.get_children():
		c.queue_free()

	var stock: Array = Roster.breeding_stock()
	for c in _plate_host.get_children():
		c.queue_free()
	_plate_host.add_child(UiTheme.room_plate("breeding", "The Breeding Ranch",
		"Two champions out of competition make a third that neither could be. The line's gift is TIME — a foal is behind on the day it hatches and outlives everything it will ever race.",
		[
			{"value": "%dg" % Career.gold, "label": "in hand", "tint": UiTheme.GOLD},
			{"value": "%d" % stock.size(), "label": "in the stud book"},
			{"value": "%d / %d" % [Roster.monsters.size(), Career.barn_capacity], "label": "stalls used"},
			{"value": "%dg" % BREED_COST, "label": "a pairing costs"},
		]))

	# Selections can be invalidated by a preserve/release between refreshes.
	if _pick_a != null and not stock.has(_pick_a): _pick_a = null
	if _pick_b != null and not stock.has(_pick_b): _pick_b = null

	_box.add_child(UiTheme.heading("The stud book — %d preserved" % stock.size(), 2))
	# ⚠️ THE SCREEN'S REAL FAILURE STATE, NAMED. Round 18's before-capture showed ONE eligible stud
	# and the screen said only "Choose two preserved parents." — so the whole apparatus below
	# (bequest, foal preview, the comparison) was structurally unreachable and nothing on the page
	# said why or where to go. `docs/META_UI_DIRECTION.md` read that capture as "no foal preview";
	# the preview was there and could not render. A gate the player cannot see is the same defect
	# as a gate that does not exist.
	if stock.size() < 2:
		_box.add_child(_gate_card(stock.size()))
	for mi in stock:
		_box.add_child(_parent_card(mi))

	if _pick_a != null and _pick_b != null and _pick_a != _pick_b:
		_box.add_child(HSeparator.new())
		_box.add_child(_bequest_card())

	if not Roster.monsters.is_empty():
		_box.add_child(HSeparator.new())
		_box.add_child(UiTheme.heading("In the barn", 2))
		_box.add_child(UiTheme.body_text(
			"Competing, and therefore not breeding stock. Preserve one to add it to the stud book — it leaves the barn and starts costing rent.", "muted"))
		for mi in Roster.monsters:
			_box.add_child(_barn_card(mi))


func _aptitude_line(mi) -> String:
	var prof: Dictionary = WeekLib.training_profile(mi)
	var bits: Array = []
	if str(prof.get("major", "")) != "": bits.append("major %s" % prof["major"])
	if str(prof.get("minor", "")) != "": bits.append("minor %s" % prof["minor"])
	if str(prof.get("flaw", "")) != "": bits.append("flaw %s" % prof["flaw"])
	return "trains: " + (", ".join(bits) if not bits.is_empty() else "no aptitude")


func _kit_line(mi) -> String:
	var names: Array = []
	for m in mi.moveset:
		names.append(str(m.get("name", "?")))
	return "kit: " + (", ".join(names) if not names.is_empty() else "—")


## ⚠️ THE KIT WAS A COMMA-SEPARATED STRING WHILE 141 AUTHORED ICONS SAT ON DISK. `kit: Grand
## Mockery, Bravura, Sidestep, Discord, Screech, Anthem of Iron` is six facts a player has to read
## as prose; the icons are addressed by the id the moveset already carries. Icon BESIDE the name,
## never instead of it — these badges are abstract and cannot name a move on their own.
func _kit_row(mi) -> Control:
	if mi.moveset.is_empty():
		return UiTheme.body_text("kit: —", "muted")
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.add_child(UiTheme.body_text("kit", "muted"))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", UiTheme.SPACE_MD)
	flow.add_theme_constant_override("v_separation", UiTheme.SPACE_XS)
	for m in mi.moveset:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", UiTheme.SPACE_XS)
		var tex: Texture2D = UiTheme.ability_texture(str(m.get("id", "")))
		if tex != null:
			var ic := TextureRect.new()
			ic.texture = tex
			ic.custom_minimum_size = Vector2(24, 24)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cell.add_child(ic)
		var nm := Label.new()
		nm.text = str(m.get("name", "?"))
		nm.autowrap_mode = TextServer.AUTOWRAP_OFF
		nm.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
		nm.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
		nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_child(nm)
		flow.add_child(cell)
	col.add_child(flow)
	return col


## ── PORTRAITS AND NUMBERS ON EVERY BODY THIS SCREEN NAMES ─────────────────────────────────────
## ⚠️ THIS SCREEN RENDERED SIXTY-FIVE SPECIES OF FINISHED ART AS NOTHING AT ALL, and every row as
## the same string: `potential ×1.00 · Wild stock — Gen 1`. Five bodies, five identical lines, and
## the question the screen exists to ask is *which one*. Portrait + the six stats + the age is the
## whole fix: it is all live data, none of it is new, and without it the decision has literally no
## discriminating information on the page.
func _portrait(species_id: String, species_name: String, size_px: Vector2) -> Control:
	var tex: Texture2D = Art.creature_texture(species_id)
	if tex != null:
		var t := TextureRect.new()
		t.texture = tex
		t.custom_minimum_size = size_px
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		return t
	var p := PanelContainer.new()
	p.custom_minimum_size = size_px
	p.add_theme_stylebox_override("panel", UiTheme.panel_style("default", UiTheme.GOLD))
	var l := Label.new()
	l.text = species_name.substr(0, 2).to_upper()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", UiTheme.GOLD)
	l.add_theme_font_size_override("font_size", int(size_px.y * 0.35))
	p.add_child(l)
	return p


func _stats_line(mi) -> String:
	var bits: Array = []
	for s in STATS:
		bits.append("%s %d" % [s, int(float(mi.stats.get(s, 0.0)))])
	return " · ".join(PackedStringArray(bits))


## Age said in years against its own span — the number that decides whether a body still has a
## career to surrender. `week.gd:stage_info` grades it; this only reads.
func _age_line(mi) -> String:
	var info: Dictionary = WeekLib.stage_info(mi.age_weeks, mi.lifespan_years)
	return "%s · %.1f of %.1f yrs" % [
		str(info["stage"]), float(mi.age_weeks) / float(WeekLib.WEEKS_PER_YEAR), mi.lifespan_years]


## What is standing between the player and a pairing, and the door that fixes it. Never a dead end.
func _gate_card(have: int) -> Control:
	var panel := PanelContainer.new()
	var sb := UiTheme.panel_style("raised", UiTheme.CAUTION)
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)
	var head := UiTheme.body_text(
		"A pairing needs TWO preserved parents — you have %d." % have, "primary")
	head.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBHEADING)
	head.add_theme_color_override("font_color", UiTheme.CAUTION)
	col.add_child(head)
	var why := UiTheme.body_text(
		"Only a monster PRESERVED at the Lab is breeding stock. Preserving takes it out of competition and starts a freezer bill that never stops — a retired one is enshrined free, because it can never race again. That trade is the decision breeding asks, and it has to be made while the monster is still worth making it for.",
		"secondary")
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(why)
	var b := Button.new()
	b.text = "Go to the Lab — preserve %s →" % ("a second body" if have == 1 else "a body")
	b.custom_minimum_size = Vector2(0, 38)
	b.focus_mode = Control.FOCUS_ALL
	for state in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(state, UiTheme.button_stylebox("primary", state))
	b.add_theme_stylebox_override("focus", UiTheme.button_stylebox("primary", "focus"))
	b.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/lab.tscn"))
	col.add_child(b)
	return panel


func _parent_card(mi) -> Control:
	var picked: bool = (mi == _pick_a or mi == _pick_b)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UiTheme.panel_style("raised", UiTheme.GOLD) if picked else UiTheme.panel_style("default"))

	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	panel.add_child(outer)
	outer.add_child(_portrait(mi.species_id, mi.species_name, Vector2(88, 88)))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(col)

	var used: int = _children_of(mi)
	var role := "A" if mi == _pick_a else ("B" if mi == _pick_b else "")
	col.add_child(UiTheme.heading("%s%s — %s%s" % [
		"[%s] " % role if role != "" else "", mi.species_name, mi.class_name_,
		" (retired)" if mi.retired else ""], 3))
	col.add_child(UiTheme.body_text(_stats_line(mi), "primary"))
	col.add_child(UiTheme.body_text("%s body · %s · potential ×%.2f · %s · %d of %d matings used" % [
		mi.body, _age_line(mi), mi.potential, mi.lineage_label(), used, MAX_CHILDREN_PER_PARENT], "secondary"))
	col.add_child(UiTheme.body_text(_aptitude_line(mi), "muted"))
	col.add_child(_kit_row(mi))

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 34)
	btn.focus_mode = Control.FOCUS_ALL
	if used >= MAX_CHILDREN_PER_PARENT:
		btn.disabled = true
		btn.text = "Retired from the stud book — %d children already" % used
	elif picked:
		btn.text = "Chosen — tap to release"
		btn.pressed.connect(func():
			if _pick_a == mi: _pick_a = null
			elif _pick_b == mi: _pick_b = null
			_reset_bequest()
			_refresh())
	else:
		btn.text = "Choose as a parent"
		btn.pressed.connect(func():
			if _pick_a == null: _pick_a = mi
			elif _pick_b == null: _pick_b = mi
			else: _pick_b = mi
			_reset_bequest()
			_refresh())
	col.add_child(btn)
	return panel


## ⚠️ A bequest is only meaningful against the pair it was chosen from — changing a parent must
## clear it, or the child would silently inherit a move neither of its parents knows.
func _reset_bequest() -> void:
	_heirloom_id = ""
	_line_from_b = false
	_emphasis = ""


func _barn_card(mi) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	panel.add_child(outer)
	outer.add_child(_portrait(mi.species_id, mi.species_name, Vector2(64, 64)))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(col)
	col.add_child(UiTheme.heading("%s — %s%s" % [
		mi.species_name, mi.class_name_, " (retired)" if mi.retired else ""], 3))
	col.add_child(UiTheme.body_text(_stats_line(mi), "primary"))
	# ⚠️ WHAT PRESERVING COSTS, ON THE ROW THAT OFFERS IT. The trade is *racing years surrendered*
	# against *a line kept* — and the age is the whole left-hand side of it. A retiree has none left
	# to surrender, which is exactly why it is enshrined free.
	col.add_child(UiTheme.body_text("%s · potential ×%.2f · %s" % [
		_age_line(mi), mi.potential, mi.lineage_label()], "secondary"))

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 34)
	btn.focus_mode = Control.FOCUS_ALL
	if Roster.monsters.size() <= 1 and not mi.retired:
		btn.disabled = true
		btn.text = "Your only monster — the barn cannot be left empty"
	else:
		# ⚠️ THE PRICE OF PRESERVING IS DIFFERENT FOR A RETIREE AND THE BUTTON MUST SAY WHICH — the
		# rule lives in `week_plan.gd:rent_for` (retired bodies are not billed), so the two labels
		# below are two readings of ONE rule, never a second copy of it.
		btn.text = ("Preserve — enshrined FREE, it can never race again"
			if mi.retired else
			"Preserve — surrenders %.1f racing years, then %dg/week forever" % [
				maxf(0.0, mi.lifespan_years - float(mi.age_weeks) / float(WeekLib.WEEKS_PER_YEAR)),
				int(WeekPlan.RENTAL_PER_FROZEN)])
		btn.pressed.connect(func():
			Roster.preserve(mi)
			_refresh())
	col.add_child(btn)
	return panel


func _chip_row(label: String, options: Array, current, on_pick: Callable) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	col.add_child(UiTheme.body_text(label, "secondary"))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", UiTheme.SPACE_XS)
	row.add_theme_constant_override("v_separation", UiTheme.SPACE_XS)
	for opt in options:
		var chosen: bool = opt["value"] == current
		var b := Button.new()
		b.text = ("• " if chosen else "") + str(opt["text"])
		b.tooltip_text = str(opt.get("tip", ""))
		b.custom_minimum_size = Vector2(0, 34)
		b.focus_mode = Control.FOCUS_ALL
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# ⚠️ THE CHOSEN CHIP LOOKED EXACTLY LIKE THE ELEVEN IT WAS CHOSEN OVER. Read off
		# `09_breeding.png`: three rows of identical grey buttons, the selection carried by a `●`
		# prefix alone at 16px. This is a COMMITTED choice about a creature that costs 300g — it
		# gets the theme's primary treatment, and the `●` stays, because the glyph is the channel
		# that survives a colourblind read.
		if chosen:
			for state in ["normal", "hover", "pressed", "focus"]:
				b.add_theme_stylebox_override(state, UiTheme.button_stylebox("primary", state))
		# ⚠️ THE ICONS WERE ALREADY ON DISK AND EXACTLY ONE FILE IN THE PROJECT LOADED THEM
		# (`arena_3d.gd:3894`). Twelve heirloom buttons here rendered twelve authored 64x64 icons
		# as twelve identical grey words. `icon_id` is the move id the option already carries, so
		# this costs a lookup and nothing else.
		var icon_id: String = str(opt.get("icon_id", ""))
		if icon_id != "":
			var tex: Texture2D = UiTheme.ability_texture(icon_id)
			if tex != null:
				b.icon = tex
				b.expand_icon = true
				b.add_theme_constant_override("icon_max_width", 22)
		var v = opt["value"]
		b.pressed.connect(func(): on_pick.call(v))
		row.add_child(b)
	col.add_child(row)
	return col


## ⚠️ ICONS GO BESIDE NAMES, NEVER INSTEAD OF THEM. These are abstract badges — nobody reads
## `three slashes` as `Rend` — so their job is scanning and stat-channel colour, not naming.
## The lookup is `UiTheme.ability_texture()` (and `UiTheme.ability_icon()` when you want the whole
## control): a missing file returns null and the caller simply renders the word, which is the
## `portrait()` degrade pattern — never a layout jump when an import fails.
##
## ⚠️ IT WAS A PRIVATE COPY IN THIS FILE UNTIL ROUND 21's INTEGRATION, alongside two others in
## `stable_ui.gd` and — via a cross-screen call into this file — `lab_ui.gd`. Three loaders for one
## asset folder, all authored in the same round the icons first reached a meta screen.


func _bequest_card() -> Control:
	var a = _pick_a
	var b = _pick_b
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("raised", UiTheme.GOLD))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	panel.add_child(col)

	col.add_child(UiTheme.heading("%s × %s — the bequest" % [a.species_name, b.species_name], 2))
	col.add_child(UiTheme.body_text(
		"Three choices, and the exact monster they produce is shown below before you pay.", "secondary"))

	# ⚠️ THE FOAL IS THE PRODUCT AND IT WAS BELOW THE FOLD, RENDERED AS A TABLE. Read off
	# `A_comfortable/09_breeding.png` and `..._end.png`: the pairing's three creatures never appear
	# together anywhere on the page — parent A and parent B are two 88px thumbnails in two separate
	# stacked rows, and the child arrives 400px further down as a column of numbers headed by a
	# 56px face. `CLAUDE.md` calls this half the vision ("knowing WHICH monster to make is the
	# skill") and the most emotionally loaded thing the game does; it read as a spreadsheet diff.
	# The banner puts the three faces on one line, at the size the art was drawn for, above the
	# three chips that change the third one. Everything in it is already-computed live data.
	#
	# ⚠️ IT IS BUILT FROM THE SAME `child` THE PREVIEW AND THE COMMIT USE. `_make_child` is called
	# ONCE here and handed to both, so the face in the banner and the numbers in the grid cannot
	# come from two different rolls of the same pairing.
	var child = _make_child(a, b, "")
	col.add_child(_pairing_banner(a, b, child))

	# 1 — the LINE. Species carries body, art, innates and the training aptitude the child will
	# live under, so this is the single largest decision on the screen.
	col.add_child(_chip_row("The line it takes", [
		{"value": false, "text": "%s (%s)" % [a.species_name, a.body], "tip": _aptitude_line(a)},
		{"value": true, "text": "%s (%s)" % [b.species_name, b.body], "tip": _aptitude_line(b)},
	], _line_from_b, func(v): _line_from_b = v; _refresh()))

	# 2 — the EMPHASIS. Zero-sum; this picks the child's shape and therefore its class.
	var emph_opts: Array = [{"value": "", "text": "even", "tip": "an even spread of the parents' average"}]
	for s in STATS:
		emph_opts.append({"value": s, "text": s,
			"tip": "every other stat gives up %d%% of itself, and all of it goes to %s" % [
				int(EMPHASIS_TAX * 100), s]})
	col.add_child(_chip_row("What it is bred FOR (zero-sum — shape, not strength)",
		emph_opts, _emphasis, func(v): _emphasis = v; _refresh()))

	# 3 — the HEIRLOOM. The part the FIGHT can see.
	var heir_opts: Array = [{"value": "", "text": "no heirloom", "tip": "the child drafts its own kit"}]
	for opt in _heirloom_options(a, b):
		heir_opts.append({"value": opt["id"],
			"text": "%s" % opt["name"], "icon_id": str(opt["id"]),
			"tip": "%s's %s — dormant until the heir reaches %s %d" % [
				opt["from"], opt["type"], opt["stat"], int(opt["at"])]})
	col.add_child(_chip_row("The move it is BORN knowing (dormant until it matches its parent)",
		heir_opts, _heirloom_id, func(v): _heirloom_id = v; _refresh()))

	col.add_child(HSeparator.new())
	col.add_child(_child_preview(a, b, child))

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 40)
	btn.focus_mode = Control.FOCUS_ALL
	if Roster.monsters.size() >= Career.barn_capacity:
		btn.disabled = true
		btn.text = "Barn is full (%d of %d) — extend it at the Shop" % [
			Roster.monsters.size(), Career.barn_capacity]
	elif Career.gold < BREED_COST:
		btn.disabled = true
		btn.text = "Need %d more gold" % (BREED_COST - Career.gold)
	else:
		btn.text = "Breed — %dg" % BREED_COST
		btn.pressed.connect(_on_breed)
	col.add_child(btn)
	return panel


## Parent A · parent B · foal, one row per stat, with the three faces above their columns. The
## emphasis stat is marked ◆ in the LABEL column so the mark reads against the row it belongs to.
func _lineage_grid(a, b, child) -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", UiTheme.SPACE_LG)
	grid.add_theme_constant_override("v_separation", 2)

	grid.add_child(_cell("", "muted", 80))
	# ⚠️ "AT HATCH" IS NOT DECORATION. Read from the capture, the grid invites the wrong comparison:
	# a foal of two trained champions shows 48/46/131 against parents at 198/202/277 and looks like
	# a catastrophe, when it is the 30% head start plus the species floor behaving exactly as
	# designed — the honest yardstick is a WILD-CAUGHT body of the same species, which the line
	# under this card already gives (360 points against 136). Naming the column for the moment it
	# describes is the cheapest way to stop the table implying a claim it is not making.
	for entry in [[a, "A"], [b, "B"], [child, "foal at hatch"]]:
		var head := VBoxContainer.new()
		head.add_theme_constant_override("separation", 0)
		var face := HBoxContainer.new()
		face.add_theme_constant_override("separation", UiTheme.SPACE_XS)
		face.add_child(_portrait(entry[0].species_id, entry[0].species_name, Vector2(56, 56)))
		head.add_child(face)
		var nm := _cell("%s (%s)" % [entry[0].species_name, entry[1]],
			"primary" if str(entry[1]).begins_with("foal") else "secondary", 110)
		if str(entry[1]).begins_with("foal"):
			nm.add_theme_color_override("font_color", UiTheme.GOLD)
		head.add_child(nm)
		grid.add_child(head)

	for s in STATS:
		var lbl := _cell("%s%s" % [s, " •" if s == _emphasis else ""], "secondary", 80)
		if s == _emphasis:
			lbl.add_theme_color_override("font_color", UiTheme.GOLD)
		grid.add_child(lbl)
		grid.add_child(_cell("%d" % int(float(a.stats.get(s, 0.0))), "muted", 110))
		grid.add_child(_cell("%d" % int(float(b.stats.get(s, 0.0))), "muted", 110))
		var kid := _cell("%d" % int(float(child.stats.get(s, 0.0))), "primary", 110)
		kid.add_theme_color_override("font_color", UiTheme.GOLD if s == _emphasis else UiTheme.TEXT_PRIMARY)
		grid.add_child(kid)
	return grid


## ⚠️ TABLE CELLS MUST NOT WORD-WRAP. `UiTheme.body_text` turns wrapping on — correct for prose,
## fatal in a `GridContainer`, where a wrapping label's minimum width is ONE CHARACTER and the
## whole table collapses into overlapping vertical strips. It happened twice in this round (here
## and on `shop_ui.gd`) and every mechanical probe check passed on both frames; only reading the
## capture caught it.
func _cell(text: String, tier: String, width: int) -> Label:
	var l := UiTheme.body_text(text, tier)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.custom_minimum_size = Vector2(width, 0)
	return l


## ── THE MATING PEN ────────────────────────────────────────────────────────────────────────────
## Three creatures on one line, at portrait scale: the two you preserved, and the one they make.
## Nothing here is computed — every value is read off the instances the caller already built.
##
## ⚠️ `×` IS USED AND `→` IS NOT, ON PURPOSE. Probed against the packaged Open Sans SemiBold
## (`docs/POLISH_DIRECTION.md` §2): U+00D7 is in the face, U+2192 is not — it renders on Windows
## only because a system font supplies it. The parents-to-foal step is therefore the WORD "makes",
## not an arrow. No new glyph enters this file without that check.
func _pairing_banner(a, b, child) -> Control:
	var panel := PanelContainer.new()
	var sb := UiTheme.panel_style("default", UiTheme.BORDER)
	sb.bg_color = UiTheme.SURFACE
	sb.content_margin_top = UiTheme.SPACE_MD
	sb.content_margin_bottom = UiTheme.SPACE_MD
	panel.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_LG)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)

	row.add_child(_banner_face(a, "parent A", 104, false))
	row.add_child(_joiner("×"))
	row.add_child(_banner_face(b, "parent B", 104, false))
	row.add_child(_joiner("makes"))
	row.add_child(_banner_face(child, "Gen %d · potential ×%.2f" % [child.generation, child.potential], 132, true))
	return panel


func _banner_face(mi, caption: String, px: int, is_foal: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var frame := PanelContainer.new()
	var fsb := UiTheme.panel_style("raised" if is_foal else "default", UiTheme.GOLD if is_foal else UiTheme.BORDER)
	fsb.set_border_width_all(3 if is_foal else 1)
	frame.add_theme_stylebox_override("panel", fsb)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.add_child(_portrait(mi.species_id, mi.species_name, Vector2(px, px)))
	col.add_child(frame)

	var nm := Label.new()
	nm.text = mi.species_name
	nm.autowrap_mode = TextServer.AUTOWRAP_OFF
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBHEADING if is_foal else UiTheme.SIZE_BODY)
	nm.add_theme_color_override("font_color", UiTheme.GOLD if is_foal else UiTheme.TEXT_PRIMARY)
	col.add_child(nm)

	var cls := Label.new()
	cls.text = mi.class_name_
	cls.autowrap_mode = TextServer.AUTOWRAP_OFF
	cls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cls.add_theme_font_size_override("font_size", UiTheme.SIZE_BODY)
	cls.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	col.add_child(cls)

	var cap := Label.new()
	cap.text = caption
	cap.autowrap_mode = TextServer.AUTOWRAP_OFF
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_font_size_override("font_size", UiTheme.SIZE_CAPTION)
	cap.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	col.add_child(cap)
	return col


func _joiner(text: String) -> Control:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", UiTheme.SIZE_SUBHEADING)
	l.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


func _child_preview(a, b, child) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	col.add_child(UiTheme.heading("The foal: %s — %s, Gen %d" % [
		child.species_name, child.class_name_, child.generation], 3))

	# ⚠️ THE PREDICTION IS THE PRODUCT, SO IT IS RENDERED AS A COMPARISON AND NOT AS A SENTENCE.
	# `docs/META_UI_DIRECTION.md`'s acceptance for this screen is *"from breeding they can predict
	# roughly what a pairing yields"*, and a six-item run-on line of the child's stats cannot be
	# compared against the two parents it came from — the player would have to hold twelve numbers
	# in their head and do the averaging the code just did. Three columns against one stat label is
	# the same information, arranged so the head start, the emphasis tax and the species floor are
	# all VISIBLE as differences rather than asserted in prose underneath.
	col.add_child(_lineage_grid(a, b, child))
	col.add_child(UiTheme.body_text("%d HP · %d MP · %s · %s" % [
		child.max_hp, child.max_mp, child.body, _aptitude_line(child)], "secondary"))

	# Potential is invisible unless stated, and it is the only thing training cannot buy.
	var league_cap: float = Career.stat_cap_for_league(Career.league_index)
	var why := UiTheme.body_text(
		"Potential ×%.2f (+%.2f a generation for this heritage) — every league ceiling it ever trains against is multiplied by it. At %s that is %d instead of %d. Training cannot raise it; only breeding can." % [
			child.potential, _step_for(a, b), Career.current_league_name(),
			int(league_cap * child.potential), int(league_cap)], "primary")
	why.add_theme_color_override("font_color", UiTheme.GOLD)
	col.add_child(why)

	# ⚠️ SAY THE GIFT OUT LOUD OR IT DOES NOT EXIST. A longer career is invisible on a stat card —
	# it shows up 300 weeks later as "this one is still training" — and an unstated mechanic is
	# this project's named signature failure. The comparison to a bought body is on the card for
	# the same reason the market's stat total is.
	var wpy: float = float(WeekLib.WEEKS_PER_YEAR)
	# ⚠️ ONE GOLD PARAGRAPH, NOT THREE. `docs/POLISH_DIRECTION.md` §1.1 measures GOLD against
	# CAUTION at 1.023:1 — one colour under two names — and counts this file at 13 amber text
	# references against 2 greys. When the heading ink, the emphasis ink and the warning ink are
	# the same value, nothing on the page is emphasised. Potential keeps the gold because it is the
	# one thing on this card training can never buy; the lifespan gift and the bequest drop to
	# TEXT_PRIMARY, which is BRIGHTER than gold and therefore loses no emphasis at all — it only
	# stops competing.
	var span := UiTheme.body_text(
		"Lives %.1f years to its parent's %.1f (+%.1f a generation, ceiling %.0f). That is %d more trainable weeks than a monster bought off the market, which arrives already %d weeks old. Training is bounded by the CLOCK, not the ceiling — the line's real gift is time." % [
			child.lifespan_years, maxf(a.lifespan_years, b.lifespan_years), LIFESPAN_STEP_YEARS,
			MAX_LIFESPAN_YEARS,
			int(round((child.lifespan_years - 8.0) * wpy)) + 48, 48], "primary")
	col.add_child(span)

	col.add_child(_kit_row(child))
	if child.heirloom_move_id != "":
		var h: Dictionary = child.heirloom_move()
		# The bequeathed move gets its authored icon, at the size the theme reserves for an inline
		# mark — beside the sentence that names it, never instead of it.
		var hrow := HBoxContainer.new()
		hrow.add_theme_constant_override("separation", UiTheme.SPACE_SM)
		var htex: Texture2D = UiTheme.ability_texture(child.heirloom_move_id)
		if htex != null:
			var ic := TextureRect.new()
			ic.texture = htex
			ic.custom_minimum_size = Vector2(32, 32)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			hrow.add_child(ic)
		var line := UiTheme.body_text(
			"%s is bequeathed — it holds a slot from birth at %d%% power and a longer cooldown, and awakens to its parent's full version when the heir reaches %s %d (its parent's value today). The child hatches at %s %d." % [
				h.get("name", "?"), int(MonsterInstanceScript.HEIRLOOM_DORMANT_MULT * 100),
				child.heirloom_stat, int(child.heirloom_awaken_at),
				child.heirloom_stat, int(child.stats.get(child.heirloom_stat, 0))], "primary")
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hrow.add_child(line)
		col.add_child(hrow)

	# ⚠️ SAY WHAT THE MARKET WOULD HAVE GIVEN. The measured failure of the old screen was that
	# 300g bought a monster weaker than a wild recruit and nothing on the page said so. The
	# comparison belongs on the card whether it flatters the system or not.
	var sp: Dictionary = GameData.species_by_id.get(child.species_id, {})
	var wild_total := 0.0
	var child_total := 0.0
	for s in STATS:
		wild_total += float(sp.get("base", {}).get(s, 10.0))
		child_total += float(child.stats[s])
	col.add_child(UiTheme.body_text(
		"%d stat points against %d for a wild-caught %s — a head start of %+d, before potential." % [
			int(child_total), int(wild_total), child.species_name, int(child_total - wild_total)],
		"muted"))
	# ⚠️ `panel`, not `col` — `col` is already parented to it, and returning a parented node makes
	# `add_child` refuse at the call site. Caught by the screen-level check, invisible to the maths.
	return panel


func _on_breed() -> void:
	var a = _pick_a
	var b = _pick_b
	if a == null or b == null or a == b:
		return
	if Roster.monsters.size() >= Career.barn_capacity:
		return
	if not Career.spend_gold(BREED_COST):
		return

	var child = _make_child(a, b, Roster.next_slot_id())
	a.set_meta("children", _children_of(a) + 1)
	b.set_meta("children", _children_of(b) + 1)
	Roster.monsters.append(child)

	# ⚠️ THE PARENTS STAY IN THE FREEZER. Breeding preserves them (`town.ts` keeps `labFrozen`
	# intact and only bumps `breedCount`) — the cost of the line is the standing rent, not the
	# parent, which is what lets a player run a second child off the same founder later.
	_log_label.text = "%s born — Gen %d %s, %s, potential ×%.2f.%s" % [
		child.species_name, child.generation, ClassifyLib.class_for_stats(child.stats),
		"bred for %s" % _emphasis if _emphasis != "" else "an even spread", child.potential,
		" Carries %s, dormant." % child.heirloom_move().get("name", "?") if child.heirloom_move_id != "" else ""]
	_log_label.add_theme_color_override("font_color", UiTheme.GOLD)
	_pick_a = null
	_pick_b = null
	_reset_bequest()
	_refresh()
