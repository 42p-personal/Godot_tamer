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

var _box: VBoxContainer
var _header: Label
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

	page.add_child(UiTheme.heading("The Breeding Ranch", 1))
	_header = UiTheme.body_text("", "secondary")
	page.add_child(_header)

	_log_label = UiTheme.body_text("Choose two preserved parents.", "primary")
	_log_label.add_theme_color_override("font_color", UiTheme.TEXT_SECONDARY)
	page.add_child(_log_label)
	page.add_child(HSeparator.new())

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
	_header.text = "%d gold · %d preserved in the Lab · %d in the barn (holds %d) · breeding costs %dg" % [
		Career.gold, stock.size(), Roster.monsters.size(), Career.barn_capacity, BREED_COST]

	# Selections can be invalidated by a preserve/release between refreshes.
	if _pick_a != null and not stock.has(_pick_a): _pick_a = null
	if _pick_b != null and not stock.has(_pick_b): _pick_b = null

	_box.add_child(UiTheme.heading("The stud book", 2))
	if stock.is_empty():
		_box.add_child(UiTheme.body_text(
			"Empty. A monster can only be bred from once it has been PRESERVED at the Lab — taken out of competition, kept on the freezer's weekly bill. That is the decision breeding asks, and it has to be made while the monster is still worth preserving.",
			"muted"))
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


func _parent_card(mi) -> Control:
	var picked: bool = (mi == _pick_a or mi == _pick_b)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
		UiTheme.panel_style("raised", UiTheme.GOLD) if picked else UiTheme.panel_style("default"))

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	var used: int = _children_of(mi)
	var role := "A" if mi == _pick_a else ("B" if mi == _pick_b else "")
	col.add_child(UiTheme.heading("%s%s — %s%s" % [
		"[%s] " % role if role != "" else "", mi.species_name, mi.class_name_,
		" (retired)" if mi.retired else ""], 3))
	col.add_child(UiTheme.body_text("%s body · potential ×%.2f · %s · %d of %d matings used" % [
		mi.body, mi.potential, mi.lineage_label(), used, MAX_CHILDREN_PER_PARENT], "secondary"))
	col.add_child(UiTheme.body_text(_aptitude_line(mi), "muted"))
	col.add_child(UiTheme.body_text(_kit_line(mi), "muted"))

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 34)
	btn.focus_mode = Control.FOCUS_ALL
	if used >= MAX_CHILDREN_PER_PARENT:
		btn.disabled = true
		btn.text = "Retired from the stud book — %d children already" % used
	elif picked:
		btn.text = "✓ Chosen — tap to release"
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
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)
	col.add_child(UiTheme.heading("%s — %s%s" % [
		mi.species_name, mi.class_name_, " (retired)" if mi.retired else ""], 3))
	col.add_child(UiTheme.body_text("potential ×%.2f · %s" % [mi.potential, mi.lineage_label()], "muted"))

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 34)
	btn.focus_mode = Control.FOCUS_ALL
	if Roster.monsters.size() <= 1 and not mi.retired:
		btn.disabled = true
		btn.text = "Your only monster — the barn cannot be left empty"
	else:
		btn.text = "Preserve at the Lab — it stops competing, and starts costing rent"
		btn.pressed.connect(func():
			Roster.preserve(mi)
			_refresh())
	col.add_child(btn)
	return panel


func _chip_row(label: String, options: Array, current, on_pick: Callable) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	col.add_child(UiTheme.body_text(label, "secondary"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	for opt in options:
		var b := Button.new()
		b.text = ("● " if opt["value"] == current else "") + str(opt["text"])
		b.tooltip_text = str(opt.get("tip", ""))
		b.custom_minimum_size = Vector2(0, 32)
		b.focus_mode = Control.FOCUS_ALL
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v = opt["value"]
		b.pressed.connect(func(): on_pick.call(v))
		row.add_child(b)
	col.add_child(row)
	return col


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
			"text": "%s" % opt["name"],
			"tip": "%s's %s — dormant until the heir reaches %s %d" % [
				opt["from"], opt["type"], opt["stat"], int(opt["at"])]})
	col.add_child(_chip_row("The move it is BORN knowing (dormant until it matches its parent)",
		heir_opts, _heirloom_id, func(v): _heirloom_id = v; _refresh()))

	col.add_child(HSeparator.new())
	col.add_child(_child_preview(a, b))

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


func _child_preview(a, b) -> Control:
	var child = _make_child(a, b, "")
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	col.add_child(UiTheme.heading("The foal: %s — %s, Gen %d" % [
		child.species_name, child.class_name_, child.generation], 3))

	var stat_bits: Array = []
	for s in STATS:
		stat_bits.append("%s %d%s" % [s, int(child.stats[s]), "◆" if s == _emphasis else ""])
	col.add_child(UiTheme.body_text(" · ".join(stat_bits), "primary"))
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

	col.add_child(UiTheme.body_text(_kit_line(child), "secondary"))
	if child.heirloom_move_id != "":
		var h: Dictionary = child.heirloom_move()
		var line := UiTheme.body_text(
			"☆ %s is bequeathed — it holds a slot from birth at %d%% power and a longer cooldown, and awakens to its parent's full version when the heir reaches %s %d (its parent's value today). The child hatches at %s %d." % [
				h.get("name", "?"), int(MonsterInstanceScript.HEIRLOOM_DORMANT_MULT * 100),
				child.heirloom_stat, int(child.heirloom_awaken_at),
				child.heirloom_stat, int(child.stats.get(child.heirloom_stat, 0))], "primary")
		line.add_theme_color_override("font_color", UiTheme.GOLD)
		col.add_child(line)

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
