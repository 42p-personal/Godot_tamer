## THE LAB — preservation, the bill that makes it a decision, and the fusion bench.
##
## ⚠️ THE LAB'S JOB IS TO DECOUPLE THE BARN FROM THE BLOODLINE. A monster you want to breed from
## later does not need to occupy a barn slot in the meantime — but it does not become free either,
## because the freezer charges rent EVERY WEEK (`week_plan.gd:rent_for`).
##
## ⚠️ WITHOUT THE RENT THIS IS AN INFINITE BARN AND THE 2-SLOT LIMIT STOPS MEANING ANYTHING. The
## upkeep is not flavour; it is the entire reason freezing is a trade rather than a free win.
##
## ⚠️ BUT IT IS CHARGED ON THE OPTION, NOT ON THE STORAGE (2026-08-09), and the flat version was
## strangling the half of the game it was supposed to price. Rent guards against PARKING a
## monster that could still be racing — frozen bodies do not age, so the freezer would otherwise
## be a fountain of youth. A RETIRED monster cannot be parked; it can never race again however
## long it sits there, so it is enshrined free. Measured before the change (`_probe_breed.gd`
## §2): breeding needs TWO parents, so the standing charge was 24g/week — 16,800g over the back
## 700 weeks of a career against a measured career GROSS of ~20,875g. **The generational half of
## the game cost 80% of everything the stable ever earned**, and the career autopilot's answer
## was to preserve its first monster at week 336 and breed zero times in ten in-game years.
## `week_plan.gd:rent_for` is the one place that decides; this screen only draws it.
##
## ⚠️ AND THE FREEZER IS NOW THE ONLY BREEDING STOCK (`Roster.breeding_stock()`), which is what
## `src/town.ts:787` always did and the port had dropped. That single line is what turns the Lab
## from a parking bay into the decision at the centre of the meta-game: you must take a monster
## OUT OF COMPETITION, while it is still winning, and accept a bill that never stops, in exchange
## for its line. See the header of `breeding_ui.gd` for the measurements behind that change.
##
## ⚠️ IT IS ALSO THE HALL OF FAME, DELIBERATELY, AND NOT A TROPHY CASE. A retired champion has
## exactly two fates here: preserved (its stats, its potential and its heirloom move stay
## available to every future foal, for a weekly fee forever) or released (gone, permanently).
## A trophy case is a display; a standing bill is a decision, and it is what makes a monster
## matter for years after its last race. ⚠️ It also happens to be the only version that SURVIVES
## A SAVE — `save_game.gd` persists `Roster.frozen` and nothing else roster-shaped, and that file
## belongs to another workstream.
##
## ── FUSION (`docs/FUSION_DESIGN.md`) ─────────────────────────────────────────────────────────
## ⚠️ FUSION EXISTED ONLY AS A DESIGN DOC AND 20 PAINTED SPECIES. Measured 2026-08-09: the Godot
## build shipped **zero lines** of it, while `data/data.json` carries all 20 fusion species and
## `assets/creatures/` carries a finished portrait for every one of them. The Market draws from
## `Art.ROSTER` (20 ids, none of them fusion), so **45 of 65 species — including every fusion
## body — were unreachable in the entire game.** This is `CLAUDE.md`'s named signature failure at
## species scale: content authored, priced and painted, then never reached because the list
## upstream of it still described the old world. Fusion is the only route to those 20, which is
## what makes it a goal worth working toward rather than a second breeding button.
##
## ⚠️ THE SPECIES IS STEERED, NOT SPUN — and this deliberately follows the DESIGN DOC over the
## TypeScript. `FUSION_DESIGN.md` is explicit: *"You steer the outcome by choosing which legacies
## to sacrifice — that's the strategy, and it makes every one of the 5 reachable on purpose."*
## The shipped `town.ts:fusionSpin` ignores that and rolls `rng()` over the pool. A random result
## cannot be aimed, and a meta-game whose stated skill is *knowing WHICH monster to make* cannot
## have its most expensive act be a dice roll. `_fusion_result()` below matches the parents'
## combined stat profile against each candidate's own, deterministically.
##
## ⚠️ NOT PORTED, AND IT MATTERS: `FUSION_DESIGN.md` hard-caps a gen-1 fusion at Platinum until
## the line is bred onward, and gives it TWO +20% training majors. Both live in
## `week.gd` (`stat_cap_for`, `training_profile`), which is not this workstream's file — so
## neither is implemented and neither is claimed anywhere on screen. Without the wall, fusion's
## founding potential is a shortcut with no ceiling attached; that is a real balance debt to
## settle at the re-baseline, not a silent one.
##
## ⚠️ ALL NUMBERS ARE PLACEHOLDERS, accepted as such by the user — the balance baseline is
## SUSPENDED. The SHAPES are ported; the VALUES want a pass at the re-baseline.
extends Control

const UiTheme = preload("res://scripts/ui/theme.gd")
const MonsterInstanceScript = preload("res://scripts/monster_instance.gd")
const ClassifyLib = preload("res://scripts/classify.gd")
const DeriveLib = preload("res://scripts/derive.gd")
const WeekLib = preload("res://scripts/week.gd")

const STATS := ["STR", "DEX", "CON", "WIS", "INT", "CHA"]


## ⚠️ NO LONGER A MIRROR. This used to be a hand-copied `const RENTAL_PER_FROZEN := 12` with a
## comment admitting that if the two files ever disagreed the screen would be the one lying —
## which is `technical-preferences.md`'s named forbidden pattern (never hand-transcribe a table
## the tick owns). The screen now reads the tick's own constant and the tick's own billing rule,
## so the number on the button IS the number charged, by construction.
static func _rent() -> int:
	return int(WeekPlan.RENTAL_PER_FROZEN)

## `town.ts:FUSION_COST`. Steep on purpose: both parents are CONSUMED.
const FUSION_COST := 1000

## `FUSION_DESIGN.md`: *"a MODERATE inherited base (~40% of the parents' averaged stats)"*.
## Higher than breeding's 30% because breeding PRESERVES its parents and fusion EATS them.
const FUSION_HEAD_START := 0.40

## The five recipes (`town.ts:FUSION_RECIPES`), keyed by the parents' BODY types. ⚠️ Off-recipe
## pairs are invalid on purpose — "no known fusion for this pairing" is what makes the three base
## recipes feel like discoveries rather than a formula.
const FUSION_RECIPES := [
	{"pair": ["Mammal", "Reptilian"], "body": "Saurian", "potential": 1.15, "licence": ""},
	{"pair": ["Avian", "Aquatic"], "body": "Tempestine", "potential": 1.15, "licence": ""},
	{"pair": ["Marsupial", "Insectoid"], "body": "Broodkin", "potential": 1.15, "licence": ""},
	{"pair": ["Mythical", "Draconic"], "body": "Primeval", "potential": 1.25, "licence": "Elite License"},
	{"pair": ["Mythical", "Abyssal"], "body": "Primeval", "potential": 1.25, "licence": "Elite License"},
]

var _box: VBoxContainer
var _plate_host: VBoxContainer
var _log_label: Label
var _fuse_a = null
var _fuse_b = null
var _fuse_heirloom := ""


func _ready() -> void:
	self.theme = UiTheme.base_theme()
	_build()
	_refresh()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.SURFACE
	bg.anchor_right = 1; bg.anchor_bottom = 1
	add_child(bg)

	var tex: Texture2D = Art.area_texture("lab")
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

	# The room's signboard — see `UiTheme.room_plate()`. Rebuilt every refresh: the freezer bill
	# and the preserved count both move when a body is preserved or released.
	_plate_host = VBoxContainer.new()
	page.add_child(_plate_host)
	_log_label = UiTheme.body_text("", "muted")
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


# ── fusion maths ─────────────────────────────────────────────────────────────────────────────

static func recipe_for(body_a: String, body_b: String) -> Dictionary:
	for r in FUSION_RECIPES:
		if (r["pair"][0] == body_a and r["pair"][1] == body_b) \
				or (r["pair"][0] == body_b and r["pair"][1] == body_a):
			return r
	return {}


## Which of the recipe's five species the parents produce. ⚠️ DETERMINISTIC AND STEERABLE — see
## the header. Each candidate has its own two-stat identity in its authored `base`; the winner is
## the one whose SHAPE best matches the parents' combined shape. Both sides are normalised to
## fractions first, so a pair of enormous champions and a pair of modest ones with the same
## profile fuse to the same species — you steer with what you TRAINED, not with how much.
##
## ⚠️ AND IT IS NOT SPECIES-DESTINY (`CLAUDE.md`'s standing guard). The read is on the parents'
## CURRENT, TRAINED stats, never on their species. Two Mammal+Reptilian pairs trained differently
## give different fusions, and every one of the five is reachable from any legal pair.
static func fusion_result(a, b) -> Dictionary:
	var recipe := recipe_for(a.body, b.body)
	if recipe.is_empty():
		return {}
	var want := {}
	var want_total := 0.0
	for s in STATS:
		var v: float = float(a.stats.get(s, 0.0)) + float(b.stats.get(s, 0.0))
		want[s] = v
		want_total += v
	if want_total <= 0.0:
		want_total = 1.0

	var best_id := ""
	var best_score := -1.0
	for sid in GameData.species_by_id:
		var sp: Dictionary = GameData.species_by_id[sid]
		if sp.get("body", "") != recipe["body"]:
			continue
		var base: Dictionary = sp.get("base", {})
		var base_total := 0.0
		for s in STATS:
			base_total += float(base.get(s, 0.0))
		if base_total <= 0.0:
			base_total = 1.0
		var score := 0.0
		for s in STATS:
			score += (float(want[s]) / want_total) * (float(base.get(s, 0.0)) / base_total)
		# ⚠️ Deterministic tie-break by ID, never by dictionary order. `species_by_id` iterates in
		# insertion order today; relying on that would make the fusion result depend on the order
		# data.json happened to be written in.
		if score > best_score + 0.000001 or (absf(score - best_score) <= 0.000001 and sid < best_id):
			best_score = score
			best_id = sid
	if best_id == "":
		return {}
	return {"recipe": recipe, "species_id": best_id}


## Every move either parent knows — the fusion carries ONE forward. `FUSION_DESIGN.md` gives a
## fusion an exclusive signature move; there is no signature-move table on the Godot side, so the
## heirloom is the analogue that exists, and it is the part the FIGHT can see.
static func heirloom_options(a, b) -> Array:
	var out: Array = []
	var seen := {}
	for parent in [a, b]:
		for m in parent.moveset:
			var mid: String = str(m.get("id", ""))
			if mid == "" or seen.has(mid):
				continue
			seen[mid] = true
			var stat: String = str(m.get("stat", "STR"))
			out.append({"id": mid, "name": str(m.get("name", "?")), "stat": stat,
				"at": float(parent.stats.get(stat, 0.0)), "from": parent.species_name})
	return out


## ⚠️ THE ONE BUILDER — the preview and the commit both call it, so the card cannot drift from
## the result (the same rule `week.gd:preview_week` follows).
func _make_fusion(a, b, slot_id: String):
	var res := fusion_result(a, b)
	if res.is_empty():
		return null
	var sp: Dictionary = GameData.species_by_id[res["species_id"]]
	var base: Dictionary = sp.get("base", {})

	var child = MonsterInstanceScript.new()
	child.id = slot_id if slot_id != "" else "preview"
	child.species_id = res["species_id"]
	child.species_name = sp.get("name", res["species_id"])
	child.body = sp.get("body", "")
	child.flavour = sp.get("flavour", "")
	child.innate = sp.get("innate", [])
	child.potential = float(res["recipe"]["potential"])
	child.generation = 1  # founds a brand-new bloodline; breeding climbs it from here
	# Forged, not born: a fusion walks out of the Lab a year old, past the Baby training penalty.
	child.age_weeks = WeekLib.WEEKS_PER_YEAR

	child.stats = {}
	for s in STATS:
		var avg: float = (float(a.stats.get(s, 0.0)) + float(b.stats.get(s, 0.0))) * 0.5
		child.stats[s] = maxf(float(base.get(s, 10.0)), round(avg * FUSION_HEAD_START))

	if _fuse_heirloom != "":
		for opt in heirloom_options(a, b):
			if opt["id"] == _fuse_heirloom:
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

	var rng := RandomNumberGenerator.new()
	rng.seed = hash("fuse:%s+%s:%d:%s" % [a.bare_id(), b.bare_id(), Career.week, _fuse_heirloom])
	if child.has_method("assign_moveset"):
		child.assign_moveset(rng)
	var prefs: Dictionary = GameData._pick_food_prefs(rng)
	child.favourite_food = prefs["fav"]
	child.hated_food = prefs["hated"]
	child.log = ["forged from %s and %s — a %s." % [a.species_name, b.species_name, child.species_name]]
	return child


# ── the screen ───────────────────────────────────────────────────────────────────────────────

func _refresh() -> void:
	for c in _box.get_children():
		c.queue_free()

	var frozen: Array = Roster.frozen
	# ⚠️ THE TICK'S OWN RULE, NOT A SECOND COPY OF IT — `week_plan.gd:rent_for` is what bills.
	var rent: int = WeekPlan.rent_for(frozen)
	var free_count: int = frozen.filter(func(m): return m.retired).size()
	for c in _plate_host.get_children():
		c.queue_free()
	_plate_host.add_child(UiTheme.room_plate("lab", "The Lab",
		"Cryo storage, and the Hall of Fame with it. A body kept here is out of competition and on the bill forever — a retiree is enshrined free, because it can never race again.",
		# ⚠️ TWO TILES, NOT FOUR, AND THE FIRST AFTER-CAPTURE IS WHY. The plate originally carried
		# preserved / rent / stalls as well — which is exactly the four-tile ledger card sitting
		# 60px below it. Two panels printing the same four numbers is one refactor away from being
		# two panels printing DIFFERENT four numbers, which is this project's rule-(1) failure with
		# a delay fuse on it. The freezer facts belong to the ledger; the plate keeps the purse.
		[
			{"value": "%dg" % Career.gold, "label": "in hand", "tint": UiTheme.GOLD},
			{"value": "%d / %d" % [Roster.monsters.size(), Career.barn_capacity], "label": "stalls used"},
		]))

	if _fuse_a != null and not frozen.has(_fuse_a): _fuse_a = null
	if _fuse_b != null and not frozen.has(_fuse_b): _fuse_b = null

	_box.add_child(_ledger_card(frozen, rent, free_count))

	var retirees: Array = Roster.retirees_in_barn()
	if not retirees.is_empty():
		_box.add_child(UiTheme.heading("Retired — occupying a barn slot", 2))
		_box.add_child(UiTheme.body_text(
			"A retiree cannot train, feed or compete. Preserve it and its stats, its potential and its heirloom stay available to every foal you ever breed — enshrined FREE, because a monster that can never race again cannot be parked. Release it and the line ends here.",
			"muted"))
		for mi in retirees:
			_box.add_child(_barn_row(mi))

	var active: Array = Roster.monsters.filter(func(m): return not m.retired)
	if not active.is_empty():
		_box.add_child(UiTheme.heading("In the barn", 2))
	for mi in active:
		_box.add_child(_barn_row(mi))

	if not frozen.is_empty():
		_box.add_child(UiTheme.heading("Preserved", 2))
	for mi in frozen:
		_box.add_child(_frozen_row(mi))

	_box.add_child(HSeparator.new())
	_box.add_child(_fusion_bench())


## ── THE BILL AS A NUMBER, THE REASONING BEHIND A DISCLOSURE ───────────────────────────────────
## ⚠️ THIS SCREEN OPENED WITH TWO PARAGRAPHS OF 11px JUSTIFICATION BEFORE ANY CONTROL, on the
## screen its own header calls *"the decision at the centre of the meta-game"*. Measured from
## round 18's before-capture: the first interactive thing on the page sat below the halfway line,
## under an essay. The rules in that essay are load-bearing and hard-won — they are NOT deleted,
## they are moved behind `Rules ▸`, and the top of the screen now states the trade the way a
## ledger states it: what is on the bill, what it costs a week, what it buys.
##
## ⚠️ EVERY FIGURE HERE COMES FROM `week_plan.gd:rent_for`, WHICH IS WHAT ACTUALLY BILLS. The
## previous version of this file hand-copied `RENTAL_PER_FROZEN` and its own comment admitted the
## screen would be the one lying if the two ever disagreed. Do not reintroduce a second copy.
var _show_rules := false

func _ledger_card(frozen: Array, rent: int, free_count: int) -> Control:
	var panel := PanelContainer.new()
	var sb := UiTheme.panel_style("raised", UiTheme.GOLD)
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	panel.add_child(col)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_XXL)
	col.add_child(row)
	row.add_child(_ledger_tile("on the bill", "%d" % (frozen.size() - free_count),
		"paying %dg/week each" % _rent(), UiTheme.CAUTION))
	row.add_child(_ledger_tile("enshrined free", "%d" % free_count,
		"retired — nothing left to pay for", UiTheme.SAFE))
	row.add_child(_ledger_tile("this week", "%dg" % rent,
		"of %dg in hand" % Career.gold, UiTheme.GOLD if rent <= Career.gold else UiTheme.DANGER))
	row.add_child(_ledger_tile("breeding stock", "%d" % frozen.size(),
		"a pairing needs 2", UiTheme.STATUS_BUFF if frozen.size() >= 2 else UiTheme.TEXT_MUTED))

	var toggle := Button.new()
	toggle.text = ("Rules ▾  what preserving does, and why it is billed" if _show_rules
		else "Rules ▸  what preserving does, and why it is billed")
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.custom_minimum_size = Vector2(0, 30)
	toggle.pressed.connect(func(): _show_rules = not _show_rules; _refresh())
	col.add_child(toggle)

	if _show_rules:
		var body := UiTheme.body_text(
			"Preserving takes a monster out of the barn without losing it. It stops ageing and cannot train, compete or be fed — but it becomes BREEDING STOCK, and it is the only thing that is.

THE BILL IS FOR THE OPTION, NOT THE STORAGE. Preserve a monster that could still be racing and the freezer charges %dg every week, forever — you are paying to keep it young and thawable. Preserve one that has RETIRED and it is enshrined free: it can never race again, so there is nothing left to pay for. Waiting costs you the years you could have bred from a monster still climbing." % _rent(),
			"secondary")
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(body)
	return panel


## ⚠️ AUTOWRAP OFF, AND THAT IS NOT COSMETIC. `UiTheme.body_text` turns word-wrap ON, which is
## right for a paragraph and wrong for a tile: four wrapping labels inside an `HBoxContainer` each
## report a minimum width of one character, so the row collapsed and the four tiles overprinted
## each other into an unreadable column (caught in this round's own after-capture, not by a probe —
## every mechanical check passed on that frame). A fixed floor plus EXPAND_FILL is the fix.
func _ledger_tile(label: String, value: String, note: String, tint: Color) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.custom_minimum_size = Vector2(210, 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l := UiTheme.body_text(label, "muted")
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	col.add_child(l)
	var v := Label.new()
	v.text = value
	v.add_theme_font_size_override("font_size", UiTheme.SIZE_HEADING)
	v.add_theme_color_override("font_color", tint)
	col.add_child(v)
	var n := UiTheme.body_text(note, "secondary")
	n.autowrap_mode = TextServer.AUTOWRAP_OFF
	n.clip_text = true
	col.add_child(n)
	return col


## Portrait, or the species' initials at the same footprint. See the ⚠️ on `breeding_ui.gd`'s copy:
## three screens rendered sixty-five species of finished art as nothing at all.
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


## ⚠️ THE LEFT-HAND SIDE OF THE TRADE, WHICH THE SCREEN NEVER SHOWED. Preserving costs *racing
## years surrendered*; every row offered the bill and none of them offered the loss. A retiree has
## zero left, which is the whole reason it is enshrined free rather than a discount.
func _age_line(mi) -> String:
	var info: Dictionary = WeekLib.stage_info(mi.age_weeks, mi.lifespan_years)
	var left: float = maxf(0.0, mi.lifespan_years - float(mi.age_weeks) / float(WeekLib.WEEKS_PER_YEAR))
	return "%s · %.1f of %.1f yrs · %.1f racing years left" % [
		str(info["stage"]), float(mi.age_weeks) / float(WeekLib.WEEKS_PER_YEAR),
		mi.lifespan_years, left]


func _kit_line(mi) -> String:
	var names: Array = []
	for m in mi.moveset:
		names.append(str(m.get("name", "?")))
	return "kit: " + (", ".join(names) if not names.is_empty() else "—")


func _barn_row(mi) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	panel.add_child(outer)
	outer.add_child(_portrait(mi.species_id, mi.species_name, Vector2(72, 72)))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(col)

	col.add_child(UiTheme.heading("%s — %s · potential ×%.2f%s" % [
		mi.species_name, mi.class_name_, mi.potential, " · RETIRED" if mi.retired else ""], 3))
	col.add_child(UiTheme.body_text(_stats_line(mi), "primary"))
	col.add_child(UiTheme.body_text("%s · %s" % [_age_line(mi), mi.lineage_label()], "secondary"))

	## ⚠️ THE OTHER HALF OF THE PRICE, AND THE SCREEN HAS NEVER STATED IT. The header ⚠️ already
	## says preserving costs *racing years surrendered* and `_age_line()` prints them — but the
	## years are the cost to the MONSTER. Preserving also takes the body out of `Roster.fieldable()`
	## the moment the button is pressed, so it is a cost to the STABLE: the cup sheet loses a slot,
	## and it can lose the last support pick, the last body that can still train, or the only
	## classes that answer the rung's champion. A player who finds that out at the tournament gate
	## has been ambushed by a transaction that quoted them a weekly bill and nothing else.
	##
	## ⚠️ THE COUNTERFACTUAL IS ASKED, NOT DERIVED. `Roster.gaps_opened_by_releasing()` runs the gap
	## analysis over the stable MINUS this body and returns only what is NEW — so this line can
	## never re-state a gap that was already true, which is the failure its own ⚠️ in `roster.gd`
	## was written about. It returns [] for a retiree by construction (a retiree is not fieldable,
	## so removing it changes no gap), which is exactly right: enshrining a retiree costs the stable
	## nothing and the line correctly does not appear.
	##
	## ⚠️ THE FUNCTION NAME IS A NOTE TO THE INTEGRATOR, NOT A BUG. It reads "releasing" and this is
	## the PRESERVE path; both are "this body leaves the fieldable set", which is the question it
	## actually answers. `gaps_opened_by_removing()` is the honest name — one rename, no behaviour.
	## See THE GAP VOICE in `town_ui.gd` for why the words below are `stable_gaps()`'s own.
	##
	## ⚠️ AND NOT WHEN THE BUTTON CANNOT BE PRESSED. `Roster.preserve()` refuses the last active
	## body, and the button below already says so — pricing an action the screen is about to
	## forbid is a cost quoted for a transaction that cannot happen.
	var can_preserve: bool = mi.retired or Roster.monsters.size() > 1
	var opens: Array = Roster.gaps_opened_by_releasing(mi) if can_preserve else []
	if not opens.is_empty():
		var cost := UiTheme.body_text(
			"▲ It leaves the fieldable count the moment you preserve it — the stable would then "
			+ ("lack: %s." % " · ".join(PackedStringArray(opens))), "primary")
		cost.add_theme_color_override("font_color", UiTheme.CAUTION)
		cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(cost)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	col.add_child(row)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 34)
	btn.focus_mode = Control.FOCUS_ALL
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# ⚠️ Never freeze the last ACTIVE monster — an empty barn cannot advance a week or enter a
	# cup, and the player would then be paying rent to get back to a playable state. A retiree is
	# the exception: a barn holding only retirees is already stuck, and preserving the last one is
	# how the player gets out of it (`Roster.preserve` enforces the same rule).
	if not can_preserve:
		btn.disabled = true
		btn.text = "Your only monster — the barn cannot be left empty"
	else:
		btn.text = ("Enshrine — free forever, breedable forever" if mi.retired
			else "Preserve — %dg/week thereafter, breedable forever" % _rent())
		btn.pressed.connect(func():
			if Roster.preserve(mi):
				_log_label.text = "%s preserved. The bill starts next week." % mi.species_name
			_refresh())
	row.add_child(btn)

	if mi.retired:
		var rel := Button.new()
		rel.custom_minimum_size = Vector2(0, 34)
		rel.focus_mode = Control.FOCUS_ALL
		rel.text = "Release — the line ends"
		rel.pressed.connect(func():
			if Roster.release(mi):
				_log_label.text = "%s released. Its potential and its heirloom are gone." % mi.species_name
			_refresh())
		row.add_child(rel)
	return panel


func _frozen_row(mi) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("raised", UiTheme.GOLD))
	var outer := HBoxContainer.new()
	outer.add_theme_constant_override("separation", UiTheme.SPACE_MD)
	panel.add_child(outer)
	outer.add_child(_portrait(mi.species_id, mi.species_name, Vector2(72, 72)))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(col)

	col.add_child(UiTheme.heading("%s — %s · potential ×%.2f%s" % [
		mi.species_name, mi.class_name_, mi.potential,
		" · enshrined" if mi.retired else ""], 3))
	col.add_child(UiTheme.body_text(_stats_line(mi), "primary"))
	col.add_child(UiTheme.body_text("%s · %d of 2 matings used" % [
		mi.lineage_label(), int(mi.get_meta("children", 0))], "secondary"))
	col.add_child(UiTheme.body_text(_kit_line(mi), "muted"))
	col.add_child(UiTheme.body_text(
		("Enshrined — not ageing, not training, costing nothing." if mi.retired
			else "Not ageing, not training, costing %dg a week." % _rent()), "muted"))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	col.add_child(row)

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 34)
	btn.focus_mode = Control.FOCUS_ALL
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if mi.retired:
		btn.disabled = true
		btn.text = "Enshrined — it has raced its last, but its line has not"
	elif Roster.monsters.size() >= Career.barn_capacity:
		btn.disabled = true
		btn.text = "Barn is full (%d of %d) — extend it at the Shop" % [
			Roster.monsters.size(), Career.barn_capacity]
	else:
		btn.text = "Thaw into the barn"
		btn.pressed.connect(func():
			Roster.thaw(mi, Career.barn_capacity)
			_refresh())
	row.add_child(btn)

	var pick := Button.new()
	pick.custom_minimum_size = Vector2(0, 34)
	pick.focus_mode = Control.FOCUS_ALL
	if mi == _fuse_a or mi == _fuse_b:
		pick.text = "• on the fusion bench"
		pick.pressed.connect(func():
			if _fuse_a == mi: _fuse_a = null
			elif _fuse_b == mi: _fuse_b = null
			_fuse_heirloom = ""
			_refresh())
	else:
		pick.text = "To the fusion bench"
		pick.pressed.connect(func():
			if _fuse_a == null: _fuse_a = mi
			elif _fuse_b == null: _fuse_b = mi
			else: _fuse_b = mi
			_fuse_heirloom = ""
			_refresh())
	row.add_child(pick)

	var rel := Button.new()
	rel.custom_minimum_size = Vector2(0, 34)
	rel.focus_mode = Control.FOCUS_ALL
	rel.text = "Release — stop the bill"
	rel.pressed.connect(func():
		if Roster.release(mi):
			_log_label.text = "%s released. %dg/week saved, the line ended." % [
				mi.species_name, _rent()]
		_refresh())
	row.add_child(rel)
	return panel


func _fusion_bench() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.panel_style("default"))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", UiTheme.SPACE_SM)
	panel.add_child(col)

	col.add_child(UiTheme.heading("The fusion bench", 2))
	col.add_child(UiTheme.body_text(
		"Two preserved monsters, CONSUMED, become one of twenty species that exist nowhere else — not in the market, not in the wild. The pairing's BODY TYPES decide the family; the stats you trained into them decide which of the five you get.",
		"secondary"))

	var known: Array = []
	for r in FUSION_RECIPES:
		var gate: String = str(r["licence"])
		var held: bool = gate == "" or Career.holds_licence(gate)
		known.append("%s + %s makes %s%s" % [r["pair"][0], r["pair"][1], r["body"],
			"" if held else " (needs the %s)" % gate])
	col.add_child(UiTheme.body_text("Known recipes: " + " · ".join(known), "muted"))

	if _fuse_a == null or _fuse_b == null or _fuse_a == _fuse_b:
		col.add_child(UiTheme.body_text(
			"Put two preserved monsters on the bench to see what they would make.", "muted"))
		return panel

	var res := fusion_result(_fuse_a, _fuse_b)
	if res.is_empty():
		col.add_child(UiTheme.body_text(
			"No known fusion for %s + %s." % [_fuse_a.body, _fuse_b.body], "primary"))
		return panel

	var recipe: Dictionary = res["recipe"]
	var gate: String = str(recipe["licence"])
	var child = _make_fusion(_fuse_a, _fuse_b, "")

	# The heirloom the fusion carries forward — the one thing of its parents that survives them.
	var opts: Array = [{"value": "", "text": "carry nothing forward"}]
	for o in heirloom_options(_fuse_a, _fuse_b):
		opts.append({"value": o["id"], "text": o["name"],
			"tip": "%s's — dormant until %s %d" % [o["from"], o["stat"], int(o["at"])]})
	var row_label := UiTheme.body_text("One move survives the fusion", "secondary")
	col.add_child(row_label)
	var chips := HBoxContainer.new()
	chips.add_theme_constant_override("separation", UiTheme.SPACE_XS)
	for o in opts:
		var b := Button.new()
		var chosen: bool = o["value"] == _fuse_heirloom
		b.text = ("• " if chosen else "") + str(o["text"])
		b.tooltip_text = str(o.get("tip", ""))
		b.custom_minimum_size = Vector2(0, 34)
		b.focus_mode = Control.FOCUS_ALL
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# A committed choice gets the primary treatment; the • stays as the non-colour channel.
		if chosen:
			for state in ["normal", "hover", "pressed", "focus"]:
				b.add_theme_stylebox_override(state, UiTheme.button_stylebox("primary", state))
		# ⚠️ 141 AUTHORED ICONS, ONE FILE LOADING THEM. `arena_3d.gd:3894` was the only caller in
		# the project; every screen that names a move drew a word. `UiTheme.ability_texture()` is
		# the ONE shared lookup (round 21 deleted three private copies) and degrades to the word
		# when a file is missing.
		var tex: Texture2D = UiTheme.ability_texture(str(o["value"]))
		if tex != null:
			b.icon = tex
			b.expand_icon = true
			b.add_theme_constant_override("icon_max_width", 22)
		var v = o["value"]
		b.pressed.connect(func(): _fuse_heirloom = v; _refresh())
		chips.add_child(b)
	col.add_child(chips)

	col.add_child(HSeparator.new())
	col.add_child(UiTheme.heading("It would forge: %s — %s, a %s" % [
		child.species_name, child.class_name_, child.body], 3))
	var stat_bits: Array = []
	for s in STATS:
		stat_bits.append("%s %d" % [s, int(child.stats[s])])
	col.add_child(UiTheme.body_text(" · ".join(stat_bits), "primary"))
	col.add_child(UiTheme.body_text("%d HP · %d MP · %s" % [
		child.max_hp, child.max_mp, _kit_line(child)], "secondary"))
	var why := UiTheme.body_text(
		"Founds a new bloodline at potential ×%.2f — a wild line starts at ×1.00 and climbs ×0.10 a generation, so this is roughly %d generations of breeding, bought outright." % [
			child.potential, int(round((child.potential - 1.0) / 0.10))], "primary")
	why.add_theme_color_override("font_color", UiTheme.GOLD)
	col.add_child(why)
	col.add_child(UiTheme.body_text(
		"Steered by the parents' trained stats — a different pair of %s and %s, trained differently, forges a different one of the five." % [
			_fuse_a.body, _fuse_b.body], "muted"))

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 40)
	btn.focus_mode = Control.FOCUS_ALL
	if gate != "" and not Career.holds_licence(gate):
		btn.disabled = true
		btn.text = "Requires the %s — buy it at the Shop" % gate
	elif Career.gold < FUSION_COST:
		btn.disabled = true
		btn.text = "Need %d more gold" % (FUSION_COST - Career.gold)
	elif Roster.monsters.size() >= Career.barn_capacity:
		btn.disabled = true
		btn.text = "Barn is full (%d of %d) — extend it at the Shop" % [
			Roster.monsters.size(), Career.barn_capacity]
	else:
		btn.text = "Fuse — %dg, and both parents are consumed" % FUSION_COST
		btn.pressed.connect(_on_fuse)
	col.add_child(btn)
	return panel


func _on_fuse() -> void:
	var a = _fuse_a
	var b = _fuse_b
	if a == null or b == null or a == b:
		return
	var res := fusion_result(a, b)
	if res.is_empty() or Roster.monsters.size() >= Career.barn_capacity:
		return
	var gate: String = str(res["recipe"]["licence"])
	if gate != "" and not Career.holds_licence(gate):
		return
	if not Career.spend_gold(FUSION_COST):
		return

	var child = _make_fusion(a, b, Roster.next_slot_id())
	if child == null:
		Career.add_gold(FUSION_COST)  # never take the gold without giving the monster
		return
	# ⚠️ CONSUMED — and the rent stops with them. That is the fusion trade in one line: breeding
	# keeps its parents and their standing bill, fusion spends both and buys the bill out.
	Roster.release(a)
	Roster.release(b)
	Roster.monsters.append(child)
	_fuse_a = null
	_fuse_b = null
	_fuse_heirloom = ""
	_log_label.text = "%s forged — a %s at potential ×%.2f. %s and %s are gone." % [
		child.species_name, child.body, child.potential, a.species_name, b.species_name]
	_log_label.add_theme_color_override("font_color", UiTheme.GOLD)
	_refresh()
